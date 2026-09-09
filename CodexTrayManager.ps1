[CmdletBinding()]
param([switch]$ValidateOnly, [ValidateRange(0,120)][int]$SmokeTestSeconds = 0, [ValidateRange(0,10)][int]$SmokeWorkerDelaySeconds = 0)

$ErrorActionPreference = 'Stop'
$managerRoot = $PSScriptRoot
$modulePath = Join-Path $managerRoot 'CodexTrayManager.Core.psm1'
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Import-Module $modulePath -Force
    $settings = Get-CodexManagerSettings
    Initialize-CodexWindowApi
    $definitions = @($settings.Instances | Sort-Object Number)
    $definitionByNumber = @{}; foreach ($definition in $definitions) { $definitionByNumber[[int]$definition.Number] = $definition }
    $missingLaunchers = @($definitions.Variants | Where-Object { -not (Test-Path -LiteralPath $_.Launcher) })
    if ($SmokeWorkerDelaySeconds -and -not $SmokeTestSeconds) { throw 'Worker delay is only available for smoke tests.' }
} catch {
    $message = "Codex 托盘管理器无法启动：$($_.Exception.Message)"
    try {
        $startupLog = Join-Path $managerRoot 'startup-error.log'
        if ((Test-Path -LiteralPath $startupLog) -and (Get-Item -LiteralPath $startupLog).Length -gt 256KB) {
            Move-Item -LiteralPath $startupLog -Destination (Join-Path $managerRoot 'startup-error.previous.log') -Force
        }
        Add-Content -LiteralPath $startupLog -Value ("$([datetime]::Now.ToString('o')) $message") -Encoding utf8
    } catch { }
    if ($ValidateOnly -or $SmokeTestSeconds) { Write-Error $message -ErrorAction Continue }
    else { [void][Windows.Forms.MessageBox]::Show($message, 'Codex 管理器启动失败') }
    exit 1
}
if ($ValidateOnly) {
    Write-Output "VALID: $($definitions.Count) instances configured; $($missingLaunchers.Count) unavailable launcher(s), isolated to their own instance."
    exit 0
}

$createdNew = $false
$mutexName = 'Local\OpenAI-Codex-Tray-Manager-4-25'
if ($SmokeTestSeconds) { $mutexName += '-SmokeTest' }
$mutex = [Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); exit 0 }
$script:worker = $null; $script:pending = $null; $script:job = $null
$script:runspace = $null; $script:notifyIcon = $null; $script:menu = $null; $script:timer = $null
$script:managerIcon = $null; $script:instanceMenus = @{}
$script:nextRefresh = [datetime]::MinValue; $script:lastStates = @()
$script:refreshCount = 0; $script:refreshErrors = 0; $script:maxTickGapMs = 0.0
$script:lastTick = [datetime]::UtcNow; $script:startedAt = [datetime]::UtcNow
$script:logDirectory = Join-Path $managerRoot 'logs'
$script:exitCode = 0

function Write-ManagerLog {
    param([string]$Event, $Data)
    try {
        [void](New-Item -ItemType Directory -Path $script:logDirectory -Force)
        $logFile = Join-Path $script:logDirectory 'manager.jsonl'
        if ((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt 2MB) {
            Move-Item -LiteralPath $logFile -Destination (Join-Path $script:logDirectory 'manager.previous.jsonl') -Force
        }
        [pscustomobject]@{ Time=[datetime]::UtcNow.ToString('o'); Event=$Event; Data=$Data } |
            ConvertTo-Json -Depth 6 -Compress | Add-Content -LiteralPath $logFile -Encoding utf8
    } catch { $script:statusHeader.Text = '诊断日志无法写入，请检查管理器目录权限' }
}

function Show-ManagerNotice {
    param([string]$Message, [switch]$ErrorNotice)
    $script:notifyIcon.BalloonTipTitle = 'Codex 托盘管理器'
    $script:notifyIcon.BalloonTipText = $Message.Substring(0, [Math]::Min(240, $Message.Length))
    $script:notifyIcon.BalloonTipIcon = if ($ErrorNotice) { [Windows.Forms.ToolTipIcon]::Warning } else { [Windows.Forms.ToolTipIcon]::Info }
    $script:notifyIcon.ShowBalloonTip(4000)
    $script:lastResult = $Message
    $script:resultItem.Enabled = $true
}

function Set-ManagerBusy {
    param([bool]$Busy)
    foreach ($entry in $script:instanceMenus.Values) {
        $entry.Open.Enabled = -not $Busy
        $entry.Close.Enabled = -not $Busy
        $entry.Restart.Enabled = -not $Busy
        $entry.Force.Enabled = -not $Busy
        $entry.Inspect.Enabled = -not $Busy
    }
    $script:closeAllItem.Enabled = -not $Busy
    $script:exitItem.Enabled = -not $Busy
}

function Update-InstanceMenus {
    param([object[]]$States)
    $script:lastStates = @($States)
    $count = @($States | Where-Object Running).Count
    $total = $definitions.Count
    $script:statusHeader.Text = "Codex 管理器：$count / $total 正在运行"
    $script:notifyIcon.Text = "Codex 管理器（$count / $total 运行中）"
    $busy = $null -ne $script:pending -or ($null -ne $script:job -and $script:job.Action -ne 'Refresh')
    foreach ($state in $States) {
        $entry = $script:instanceMenus[[int]$state.Number]
        $label = if ($state.Running) { '运行中' } else { '未运行' }
        if ($state.Running -and @($state.ActiveVariants).Count -gt 1) {
            $variants = @($state.ActiveVariants | ForEach-Object { if ($_ -eq 'UICanary') { 'UI 试点版' } else { '普通版' } })
            $label = $variants -join ' + '
        }
        if ($state.UnknownCount -gt 0) { $label += "；$($state.UnknownCount) 个子任务待检查" }
        if (-not $state.Available) { $label += '；启动脚本缺失' }
        $dot = if ($state.Running) { '●' } else { '○' }
        $entry.Parent.Text = "$dot $($definitionByNumber[[int]$state.Number].Name)（$label）"
        $entry.Open.Text = if ($state.Running) { '切换到前台' } else { '启动' }
        $entry.Open.Enabled = -not $busy -and ($state.Running -or $state.Available)
        $entry.Close.Enabled = -not $busy -and ($state.Running -or $state.UnknownCount -gt 0)
        $entry.Restart.Enabled = -not $busy -and $state.Available -and $state.Running
        $entry.Force.Enabled = -not $busy -and ($state.Running -or $state.UnknownCount -gt 0)
    }
}

function Queue-ManagerAction {
    param([int]$Number, [string]$Action)
    if ($null -ne $script:pending -or ($null -ne $script:job -and $script:job.Action -ne 'Refresh')) { return }
    $script:menu.Close()
    $script:pending = [pscustomobject]@{ Number=$Number; Action=$Action }
    Set-ManagerBusy $true
    Set-ManagerActionLabel $Number $Action
}

function Set-ManagerActionLabel {
    param([int]$Number, [string]$Action)
    $label = switch ($Action) { Show {'启动 / 切换'} Close {'关闭'} Force {'应急关闭'} Restart {'重启'} Inspect {'检查进程'} CloseAll {'关闭全部'} }
    $script:statusHeader.Text = if ($Action -eq 'CloseAll') { '正在关闭所有 Codex…' } else { "正在$label Codex $Number…" }
}

function Sort-InstanceMenus {
    if ($script:lastStates.Count -eq 0) { return }
    $ordered = @($script:lastStates | Sort-Object @{Expression='Running';Descending=$true},Number)
    $position = 2
    foreach ($state in $ordered) {
        $parent = $script:instanceMenus[[int]$state.Number].Parent
        $script:menu.Items.Remove($parent)
        $script:menu.Items.Insert($position, $parent)
        $position++
    }
}

function Start-ManagerJob {
    param([int]$Number, [string]$Action)
    if ($Action -ne 'Refresh') { Set-ManagerActionLabel $Number $Action }
    $script:worker.Commands.Clear()
    [void]$script:worker.AddScript({
        param($Number, $Action, $TestDelay)
        $ErrorActionPreference = 'Stop'
        if ($TestDelay -gt 0) { Start-Sleep -Seconds $TestDelay }
        switch ($Action) {
            'Refresh' { Get-CodexInstanceStates }
            'Show' { Show-CodexInstance $Number }
            'Close' { Stop-CodexInstance $Number }
            'Force' { Stop-CodexInstance $Number -GraceSeconds 0 -IncludeUnconfirmedTasks }
            'Inspect' { Get-CodexClosePreview $Number }
            'Restart' { Restart-CodexInstance $Number }
            'CloseAll' { Stop-AllCodexInstances }
        }
    }).AddArgument($Number).AddArgument($Action).AddArgument($SmokeWorkerDelaySeconds)
    $script:worker.Streams.ClearStreams()
    $script:job = [pscustomobject]@{ Number=$Number; Action=$Action; Started=[datetime]::UtcNow; Handle=$script:worker.BeginInvoke() }
}

function Complete-ManagerJob {
    $job = $script:job
    try {
        $output = @($script:worker.EndInvoke($job.Handle))
        if ($script:worker.HadErrors) { throw ($script:worker.Streams.Error | Out-String) }
        if ($job.Action -eq 'Refresh') {
            $script:refreshCount++
            Update-InstanceMenus $output
            if ($script:refreshCount -eq 1) {
                Write-ManagerLog 'Ready' @{ ProcessId=$PID; Instances=$output.Count; Running=@($output | Where-Object Running).Count; SnapshotDurationMs=[math]::Round(([datetime]::UtcNow-$job.Started).TotalMilliseconds) }
            }
        } else {
            $message = switch ($job.Action) {
                'Show' {
                    switch ([string]$output[0]) {
                        'Started' { "Codex $($job.Number)：已确认应用主进程启动。" }
                        'Focused' { "Codex $($job.Number)：已切换到前台。" }
                        'RunningWithoutWindow' { "Codex $($job.Number)：存在后台进程，但未找到窗口；可能仍在启动或存在异常，请稍后刷新。" }
                        default { "Codex $($job.Number)：未能确认前台切换，请从任务栏检查窗口。" }
                    }
                }
                'Close' { Format-CodexStopResult $output[0] }
                'Force' { Format-CodexStopResult $output[0] }
                'Inspect' { [string]$output[0] }
                'Restart' { "Codex $($job.Number)：已退出并确认原运行版本重新启动。" }
                'CloseAll' {
                    $batch = $output[0]
                    $details = @($batch.Results | Where-Object { -not $_.Stopped } | ForEach-Object { Format-CodexStopResult $_ })
                    "批量关闭：$($batch.Succeeded) 个实例已退出或未运行，$($batch.Failed) 个未完成。`r`n$($details -join "`r`n")"
                }
            }
            Write-ManagerLog -Event $job.Action -Data @{ Number=$job.Number; Result=$message; Details=$output; DurationMs=[math]::Round(([datetime]::UtcNow-$job.Started).TotalMilliseconds) }
            $failed = ($job.Action -in @('Close','Force') -and -not $output[0].Stopped) -or
                ($job.Action -eq 'CloseAll' -and $output[0].Failed -gt 0) -or
                ($job.Action -eq 'Show' -and [string]$output[0] -in @('RunningWithoutWindow','ForegroundFailed'))
            Show-ManagerNotice $message -ErrorNotice:$failed
            if ($job.Action -eq 'Inspect') { [void][Windows.Forms.MessageBox]::Show($message, '进程与关闭检查') }
        }
    } catch {
        $message = "操作 $($job.Action) / Codex $($job.Number) 失败：$($_.Exception.Message)"
        Write-ManagerLog -Event 'Error' -Data $message
        if ($job.Action -eq 'Refresh') {
            $script:refreshErrors++
            $script:statusHeader.Text = '状态读取失败；点击“打开诊断日志”查看'
            $script:notifyIcon.Text = 'Codex 管理器（状态读取失败）'
        } else { Show-ManagerNotice $message -ErrorNotice }
    } finally {
        $script:job = $null
        if ($job.Action -eq 'Refresh') {
            $seconds = if ($script:menu.Visible) { $settings.PollMenuSeconds } else { $settings.PollIdleSeconds }
            $script:nextRefresh = [datetime]::UtcNow.AddSeconds($seconds)
        } else {
            Set-ManagerBusy $false
            $script:nextRefresh = [datetime]::MinValue
        }
    }
}

try {
    $script:menu = [Windows.Forms.ContextMenuStrip]::new()
    $script:statusHeader = [Windows.Forms.ToolStripMenuItem]::new('Codex 管理器：正在读取状态…')
    $script:statusHeader.Enabled = $false
    [void]$script:menu.Items.Add($script:statusHeader)
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    foreach ($definition in $definitions) {
        $number = [int]$definition.Number
        $parent = [Windows.Forms.ToolStripMenuItem]::new("$($definition.Name)（读取中）")
        $entry = [pscustomobject]@{ Parent=$parent; Open=$null; Close=$null; Restart=$null; Force=$null; Inspect=$null }
        foreach ($spec in @(@('Open','启动 / 切换到前台','Show'),@('Close','关闭（含应用后台）','Close'),@('Restart','重启（含应用后台）','Restart'),@('Inspect','查看进程与关闭检查','Inspect'),@('Force','应急关闭（中断全部子任务）','Force'))) {
            $item = [Windows.Forms.ToolStripMenuItem]::new($spec[1])
            $item.Tag = [pscustomobject]@{ Number=$number; Action=$spec[2] }
            $item.add_Click({
                param($sender,$eventArgs)
                if ($sender.Tag.Action -eq 'Force') {
                    $answer = [Windows.Forms.MessageBox]::Show("应急关闭 Codex $($sender.Tag.Number) 将中断其全部已发现子任务，包括等待退出后更新的脚本、终端和正在运行的工作。确定继续？", '应急关闭', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning, [Windows.Forms.MessageBoxDefaultButton]::Button2)
                    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
                }
                Queue-ManagerAction -Number $sender.Tag.Number -Action $sender.Tag.Action
            })
            $entry.($spec[0]) = $item
            [void]$parent.DropDownItems.Add($item)
        }
        $script:instanceMenus[$number] = $entry
        [void]$script:menu.Items.Add($parent)
    }
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $script:closeAllItem = [Windows.Forms.ToolStripMenuItem]::new('关闭所有 Codex（含应用后台）')
    $script:closeAllItem.add_Click({
        $answer = [Windows.Forms.MessageBox]::Show("关闭全部 $($definitions.Count) 个已配置实例？存在未确认子任务的实例会跳过并报告。", '关闭所有 Codex', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -eq [Windows.Forms.DialogResult]::Yes) { Queue-ManagerAction -Number 0 -Action 'CloseAll' }
    })
    [void]$script:menu.Items.Add($script:closeAllItem)
    $refresh = [Windows.Forms.ToolStripMenuItem]::new('刷新状态')
    $refresh.add_Click({ $script:nextRefresh = [datetime]::MinValue })
    [void]$script:menu.Items.Add($refresh)
    $script:resultItem = [Windows.Forms.ToolStripMenuItem]::new('查看最近操作结果')
    $script:resultItem.Enabled = $false
    $script:resultItem.add_Click({ [void][Windows.Forms.MessageBox]::Show($script:lastResult, '最近操作结果') })
    [void]$script:menu.Items.Add($script:resultItem)
    $logs = [Windows.Forms.ToolStripMenuItem]::new('打开诊断日志')
    $logs.add_Click({ if (Test-Path -LiteralPath $script:logDirectory) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:logDirectory) } })
    [void]$script:menu.Items.Add($logs)
    $folder = [Windows.Forms.ToolStripMenuItem]::new('打开管理器目录')
    $folder.add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $managerRoot) })
    [void]$script:menu.Items.Add($folder)
    $script:exitItem = [Windows.Forms.ToolStripMenuItem]::new('退出管理器（不关闭 Codex）')
    $script:exitItem.add_Click({ [Windows.Forms.Application]::ExitThread() })
    [void]$script:menu.Items.Add($script:exitItem)
    $script:menu.add_Opening({ Sort-InstanceMenus; $script:nextRefresh = [datetime]::MinValue })

    $script:notifyIcon = [Windows.Forms.NotifyIcon]::new()
    $iconPath = $settings.IconPath
    $script:managerIcon = if (Test-Path -LiteralPath $iconPath) { [Drawing.Icon]::new($iconPath) } else { [Drawing.SystemIcons]::Application }
    $script:notifyIcon.Icon = $script:managerIcon
    $script:notifyIcon.ContextMenuStrip = $script:menu
    $script:notifyIcon.Text = 'Codex 管理器'
    $script:notifyIcon.Visible = $true
    $script:notifyIcon.add_MouseClick({ param($sender,$eventArgs); if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { $script:menu.Show([Windows.Forms.Cursor]::Position) } })

    $script:runspace = [runspacefactory]::CreateRunspace()
    $script:runspace.ApartmentState = 'STA'
    $script:runspace.ThreadOptions = 'ReuseThread'
    $script:runspace.Open()
    $script:worker = [powershell]::Create()
    $script:worker.Runspace = $script:runspace
    [void]$script:worker.AddCommand('Import-Module').AddParameter('Name',$modulePath)
    [void]$script:worker.Invoke()
    if ($script:worker.HadErrors) { throw ($script:worker.Streams.Error | Out-String) }
    Write-ManagerLog 'Started' @{ Version='2.0.1'; MissingLaunchers=@($missingLaunchers | ForEach-Object Launcher); ProcessId=$PID }
    $script:timer = [Windows.Forms.Timer]::new()
    $script:timer.Interval = 100
    $script:timer.add_Tick({
        $now = [datetime]::UtcNow
        $script:maxTickGapMs = [math]::Max($script:maxTickGapMs, ($now-$script:lastTick).TotalMilliseconds)
        $script:lastTick = $now
        if ($null -ne $script:job -and $script:job.Handle.IsCompleted) { Complete-ManagerJob }
        if ($SmokeTestSeconds -gt 0 -and ($now-$script:startedAt).TotalSeconds -ge $SmokeTestSeconds -and $null -eq $script:job) {
            [Windows.Forms.Application]::ExitThread(); return
        }
        if ($null -eq $script:job) {
            if ($null -ne $script:pending) {
                $pending = $script:pending; $script:pending = $null
                Start-ManagerJob -Number $pending.Number -Action $pending.Action
            } elseif ($now -ge $script:nextRefresh) { Start-ManagerJob -Number 0 -Action 'Refresh' }
        }
    })
    $script:lastTick = [datetime]::UtcNow
    $script:timer.Start()
    [Windows.Forms.Application]::Run()
} catch {
    $script:exitCode = 1
    Write-ManagerLog 'Fatal' $_.Exception.Message
    if (-not $SmokeTestSeconds) { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex 管理器启动失败') }
    else { Write-Error $_ -ErrorAction Continue }
} finally {
    if ($null -ne $script:timer) { $script:timer.Stop(); $script:timer.Dispose() }
    if ($null -ne $script:worker) { $script:worker.Stop(); $script:worker.Dispose() }
    if ($null -ne $script:runspace) { $script:runspace.Dispose() }
    if ($SmokeTestSeconds) {
        [pscustomobject]@{ RefreshCount=$script:refreshCount; RefreshErrors=$script:refreshErrors; MaxTickGapMs=[math]::Round($script:maxTickGapMs,1); States=@($script:lastStates).Count } | ConvertTo-Json -Compress | Write-Output
        if ($script:refreshCount -eq 0 -or $script:refreshErrors -gt 0) { $script:exitCode=1 }
    }
    if ($null -ne $script:notifyIcon) { $script:notifyIcon.Visible=$false; $script:notifyIcon.Dispose() }
    if ($null -ne $script:menu) { $script:menu.Dispose() }
    if ($null -ne $script:managerIcon -and $script:managerIcon -ne [Drawing.SystemIcons]::Application) { $script:managerIcon.Dispose() }
    if ($createdNew) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $script:exitCode
