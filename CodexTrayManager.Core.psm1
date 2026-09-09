Set-StrictMode -Version 2.0
$script:Observed = @{}
$script:CommandCache = @{}
$script:LeasedIdentities = @{}

$script:Settings = $null
$script:Definitions = @{}

function Get-CodexManagerSettings {
    if ($null -ne $script:Settings) { return $script:Settings }
    $path = Join-Path $PSScriptRoot 'manager.settings.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw '缺少 manager.settings.json。请复制 manager.settings.example.json，并按本机路径修改。'
    }
    $settings = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($settings.SchemaVersion -ne 1 -or $settings.PollIdleSeconds -lt 2 -or $settings.PollIdleSeconds -gt 60 -or
        $settings.PollMenuSeconds -lt 1 -or $settings.PollMenuSeconds -gt 10 -or
        $settings.StartupTimeoutSeconds -lt 1 -or $settings.StartupTimeoutSeconds -gt 120) {
        throw 'manager.settings.json 的版本或刷新/启动超时设置无效。'
    }
    $definitions = @{}; $profiles = @{}
    foreach ($definition in $settings.Instances) {
        $number = [int]$definition.Number
        if ($number -lt 4 -or $number -gt 25 -or $definitions.ContainsKey($number) -or @($definition.Variants).Count -eq 0) {
            throw 'manager.settings.json 的实例编号重复、越界或缺少版本。'
        }
        $names = @{}
        foreach ($variant in $definition.Variants) {
            if ($variant.Name -notin @('Standard','UICanary') -or $names.ContainsKey($variant.Name)) { throw "Codex $number 的版本名称无效或重复。" }
            $names[$variant.Name] = $true
            foreach ($value in @($variant.Launcher,$variant.UserDataPath)) {
                if (-not [IO.Path]::IsPathFullyQualified($value) -or $value.Contains('"')) { throw "Codex $number 的路径必须是有效绝对路径。" }
            }
            $profile = [IO.Path]::GetFullPath($variant.UserDataPath).TrimEnd('\')
            if ($profiles.ContainsKey($profile)) { throw "用户数据目录被重复分配：$profile" }
            $profiles[$profile] = $true
            $variant.UserDataPath = $profile
        }
        if (-not $names.ContainsKey('Standard')) { throw "Codex $number 缺少默认普通版。" }
        $standard = $definition.Variants | Where-Object Name -eq 'Standard' | Select-Object -First 1
        $definition | Add-Member -NotePropertyName Launcher -NotePropertyValue $standard.Launcher -Force
        $definition | Add-Member -NotePropertyName UserDataPath -NotePropertyValue $standard.UserDataPath -Force
        $definitions[$number] = $definition
    }
    if ($definitions.Count -eq 0) { throw 'manager.settings.json 至少需要配置一个实例。' }
    $script:Definitions = $definitions
    $script:Settings = $settings
    return $script:Settings
}

function Get-CodexInstanceDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number)
    [void](Get-CodexManagerSettings)
    return $script:Definitions[$Number]
}

function Initialize-CodexWindowApi {
    if ($null -eq ('CodexTrayManager.NativeMethods' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'CodexTrayManager.Native.cs')
    }
    if ($null -eq ('CodexTrayManager.ProcessControl' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'CodexTrayManager.Process.cs')
    }
}

function Get-CodexProcessSnapshot {
    Initialize-CodexWindowApi
    $snapshot = @(Get-CodexNativeSnapshot)
    $relevant = @($snapshot | Where-Object { $_.Name -in @('ChatGPT.exe','codex.exe') })
    $missing = @(); $keys = @{}
    foreach ($process in $relevant) {
        $key = "$($process.ProcessId):$(Get-CodexIdentityTime $process)"
        $keys[$key] = $true
        if (-not $script:CommandCache.ContainsKey($key)) { $missing += $process }
    }
    # Prune before querying metadata: an exception below must not retain historical identities.
    foreach ($key in @($script:CommandCache.Keys)) { if (-not $keys.ContainsKey($key)) { $script:CommandCache.Remove($key) } }
    # Cache the launch identity for Electron/Codex; never reuse it for a new creation time.
    # WMI is used only to identify newly observed application processes, never on every idle tick.
    if ($missing.Count -gt 0) {
        $metadata = @(Get-CodexCommandMetadata -ProcessIds @($missing.ProcessId))
        $byId = @{}; foreach ($process in $metadata) { $byId[[int]$process.ProcessId] = $process }
        foreach ($process in $missing) {
            $meta = $byId[[int]$process.ProcessId]
            if ($null -eq $meta) { continue } # exited during discovery; no ownership is inferred
            $nativeTime = Get-CodexIdentityTime $process; $cimTime = Get-CodexIdentityTime $meta
            if ($nativeTime -le 0 -or $cimTime -le 0 -or [math]::Abs($nativeTime-$cimTime) -ge 10) {
                throw "进程 PID $($process.ProcessId) 在采样期间发生变化或无法核验；请刷新后重试。"
            }
            if ([string]::IsNullOrWhiteSpace($meta.CommandLine)) { throw "无法读取应用进程 PID $($process.ProcessId) 的身份参数；本轮状态不可确认。" }
            $script:CommandCache["$($process.ProcessId):$nativeTime"] = [string]$meta.CommandLine
        }
    }
    foreach ($process in $relevant) { $process.CommandLine = $script:CommandCache["$($process.ProcessId):$(Get-CodexIdentityTime $process)"] }
    $snapshot
}

function Get-CodexNativeSnapshot { [CodexTrayManager.ProcessControl]::Snapshot() }

function Get-CodexCommandMetadata {
    param([int[]]$ProcessIds)
    $filter = ($ProcessIds | ForEach-Object { "ProcessId = $_" }) -join ' OR '
    Get-CimInstance Win32_Process -Filter $filter -Property ProcessId,CreationDate,CommandLine -ErrorAction Stop
}

function Get-CodexIdentityTime {
    param($Process)
    if ($null -eq $Process -or $null -eq $Process.PSObject.Properties['CreationDate'] -or $null -eq $Process.CreationDate) { return 0L }
    try { return ([datetime]$Process.CreationDate).ToUniversalTime().ToFileTimeUtc() } catch { return 0L }
}

function Test-CodexSameProcess {
    param($First, $Second)
    $firstTime = Get-CodexIdentityTime $First
    return $null -ne $Second -and $firstTime -gt 0 -and
        [int]$First.ProcessId -eq [int]$Second.ProcessId -and $firstTime -eq (Get-CodexIdentityTime $Second)
}

function New-CodexProcessIndex {
    param([AllowEmptyCollection()][object[]]$Processes = @())
    Initialize-CodexWindowApi
    $byId = @{}; $children = @{}; $profiles = @{}
    foreach ($process in $Processes) {
        $byId[[int]$process.ProcessId] = $process
        $parentId = [int]$process.ParentProcessId
        if (-not $children.ContainsKey($parentId)) { $children[$parentId] = [Collections.Generic.List[object]]::new() }
        $children[$parentId].Add($process)
        if ($process.Name -ieq 'ChatGPT.exe') {
            $profile = [CodexTrayManager.ProcessControl]::ProfilePath($process.CommandLine)
            if (-not [string]::IsNullOrWhiteSpace($profile)) {
                if (-not $profiles.ContainsKey($profile)) { $profiles[$profile] = [Collections.Generic.List[object]]::new() }
                $profiles[$profile].Add($process)
            }
        }
    }
    [pscustomobject]@{ ById = $byId; Children = $children; ByProfile = $profiles }
}

function Test-CodexProfileCommandLine {
    param([AllowNull()][string]$CommandLine, [Parameter(Mandatory)][string]$UserDataPath)
    Initialize-CodexWindowApi
    return [CodexTrayManager.ProcessControl]::ProfilePath($CommandLine) -ieq $UserDataPath.Replace('/','\').TrimEnd('\')
}

function Test-CodexAppChild {
    param($Parent, $Child)
    if ($null -eq $Child.PSObject.Properties['ExecutablePath'] -or
        $null -eq $Parent.PSObject.Properties['ExecutablePath'] -or
        [string]::IsNullOrWhiteSpace($Child.ExecutablePath) -or
        [string]::IsNullOrWhiteSpace($Parent.ExecutablePath)) { return $false }
    if ($Parent.Name -ieq 'ChatGPT.exe') {
        if ($Child.Name -ieq 'ChatGPT.exe') { return $Child.ExecutablePath -ieq $Parent.ExecutablePath }
        # The app server is a direct Electron child, not every codex.exe spawned by a task.
        if ($Child.Name -ieq 'codex.exe') {
            return $Child.CommandLine -match '(?i)^(?:"[^"]*codex\.exe"|\S*codex\.exe)\s+app-server(?:\s|$)'
        }
    }
    if ($Parent.Name -ieq 'codex.exe' -and $Child.Name -ieq 'codex-code-mode-host.exe') {
        return (Split-Path -Parent $Child.ExecutablePath) -ieq (Split-Path -Parent $Parent.ExecutablePath)
    }
    return $false
}

function New-CodexTerminationPlan {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Processes = @(),
        [Parameter(Mandatory)][string]$UserDataPath,
        $Index,
        [AllowEmptyCollection()][object[]]$Remembered = @()
    )
    if ($null -eq $Index) { $Index = New-CodexProcessIndex $Processes }
    $profileKey = $UserDataPath.Replace('/','\').TrimEnd('\')
    $roots = if ($Index.ByProfile.ContainsKey($profileKey)) { @($Index.ByProfile[$profileKey]) } else { @() }
    $selected = @{}; $kind = @{}; $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($root in $roots) {
        $id = [int]$root.ProcessId; $selected[$id] = $root; $kind[$id] = 'Application'; $queue.Enqueue($root)
    }
    foreach ($record in $Remembered) {
        $id = [int]$record.Process.ProcessId
        if (-not $selected.ContainsKey($id) -and (Test-CodexSameProcess $record.Process $Index.ById[$id])) {
            $selected[$id] = $Index.ById[$id]; $kind[$id] = $record.Kind; $queue.Enqueue($Index.ById[$id])
        } elseif (-not $Index.ById.ContainsKey($id) -and $script:LeasedIdentities.ContainsKey("${id}:$(Get-CodexIdentityTime $record.Process)")) {
            # A retained process handle prevents PID reuse until this operation finishes.
            # Traverse its children even if the parent exited between the two snapshots.
            $selected[$id] = $record.Process; $kind[$id] = $record.Kind; $queue.Enqueue($record.Process)
        }
    }
    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue(); $parentTime = Get-CodexIdentityTime $parent
        foreach ($child in $Index.Children[[int]$parent.ProcessId]) {
            if ($null -eq $child) { continue }
            $id = [int]$child.ProcessId
            if ($selected.ContainsKey($id)) { continue }
            $childTime = Get-CodexIdentityTime $child
            # A child older than the current parent belongs to a previous use of that PID.
            if ($parentTime -gt 0 -and $childTime -gt 0 -and $childTime -lt $parentTime) { continue }
            $selected[$id] = $child
            $kind[$id] = if ($parentTime -gt 0 -and $childTime -ge $parentTime -and
                $kind[[int]$parent.ProcessId] -eq 'Application' -and (Test-CodexAppChild $parent $child)) { 'Application' } else { 'Unknown' }
            $queue.Enqueue($child)
        }
    }
    # Missing identity never authorizes termination, including profile-marked roots.
    foreach ($id in @($selected.Keys)) { if ((Get-CodexIdentityTime $selected[$id]) -eq 0) { $kind[$id] = 'Unknown' } }
    $live = @($selected.Values | Where-Object { $Index.ById.ContainsKey([int]$_.ProcessId) })
    $app = @($live | Where-Object { $kind[[int]$_.ProcessId] -eq 'Application' })
    $unknown = @($live | Where-Object { $kind[[int]$_.ProcessId] -eq 'Unknown' })
    [pscustomobject]@{
        RootProcessIds = @($roots | ForEach-Object { [int]$_.ProcessId })
        RootProcesses = $roots
        AllProcessIds = @($live | ForEach-Object { [int]$_.ProcessId } | Sort-Object)
        AllProcesses = @($live)
        ApplicationProcesses = $app
        UnknownProcesses = $unknown
        Records = @($selected.Values | ForEach-Object { [pscustomobject]@{ Process = $_; Kind = $kind[[int]$_.ProcessId] } })
    }
}

function New-CodexInstanceTerminationPlan {
    param([AllowEmptyCollection()][object[]]$Processes = @(), [Parameter(Mandatory)]$Definition, $Index, [switch]$Remember)
    if ($null -eq $Index) { $Index = New-CodexProcessIndex $Processes }
    $plans = @(); $active = @()
    foreach ($variant in $Definition.Variants) {
        $history = if ($Remember -and $script:Observed.ContainsKey($variant.UserDataPath)) { @($script:Observed[$variant.UserDataPath]) } else { @() }
        $plan = New-CodexTerminationPlan -Index $Index -UserDataPath $variant.UserDataPath -Remembered $history
        if ($Remember) { $script:Observed[$variant.UserDataPath] = @($plan.Records) }
        if ($plan.ApplicationProcesses.Count -gt 0 -or $plan.RootProcessIds.Count -gt 0) { $active += $variant.Name }
        $plans += $plan
    }
    [pscustomobject]@{
        RootProcessIds = @($plans | ForEach-Object { $_.RootProcessIds } | Sort-Object -Unique)
        RootProcesses = @($plans | ForEach-Object { $_.RootProcesses } | Sort-Object ProcessId -Unique)
        AllProcessIds = @($plans | ForEach-Object { $_.AllProcessIds } | Sort-Object -Unique)
        AllProcesses = @($plans | ForEach-Object { $_.AllProcesses } | Sort-Object ProcessId -Unique)
        ApplicationProcesses = @($plans | ForEach-Object { $_.ApplicationProcesses } | Sort-Object ProcessId -Unique)
        UnknownProcesses = @($plans | ForEach-Object { $_.UnknownProcesses } | Sort-Object ProcessId -Unique)
        ActiveVariants = $active
    }
}

function Select-CodexWindowCandidate {
    param([AllowEmptyCollection()][object[]]$Windows = @(), [AllowEmptyCollection()][int[]]$ProcessIds = @())
    $candidates = foreach ($window in $Windows) {
        if ($window.ProcessId -notin $ProcessIds -or $window.ClassName -notlike 'Chrome_WidgetWin_*') { continue }
        $score = 0
        if ($window.Title -eq 'ChatGPT') { $score += 100 }
        if ($window.ClassName -eq 'Chrome_WidgetWin_1') { $score += 50 }
        if ($window.Visible) { $score += 20 }
        if (-not [string]::IsNullOrWhiteSpace($window.Title)) { $score += 10 }
        [pscustomobject]@{ Score = $score; Window = $window }
    }
    $selected = $candidates | Sort-Object Score -Descending | Select-Object -First 1
    if ($null -ne $selected) { return $selected.Window }
    return $null
}

function Get-CodexInstanceStates {
    [CmdletBinding()]
    param([ValidateRange(4,25)][int[]]$Numbers, [AllowEmptyCollection()][object[]]$Processes, [switch]$IncludeWindows)
    if (-not $PSBoundParameters.ContainsKey('Numbers')) {
        $Numbers = @((Get-CodexManagerSettings).Instances.Number | Sort-Object)
    }
    $realSnapshot = -not $PSBoundParameters.ContainsKey('Processes')
    $snapshot = if ($realSnapshot) { @(Get-CodexProcessSnapshot) } else { @($Processes) }
    $index = New-CodexProcessIndex $snapshot
    $windows = @()
    if ($IncludeWindows) { Initialize-CodexWindowApi; $windows = @([CodexTrayManager.NativeMethods]::GetTopLevelWindows()) }
    foreach ($number in $Numbers) {
        $definition = Get-CodexInstanceDefinition $number
        $plan = New-CodexInstanceTerminationPlan -Definition $definition -Index $index -Remember:$realSnapshot
        $window = Select-CodexWindowCandidate $windows $plan.RootProcessIds
        [pscustomobject]@{
            Number = $number
            Running = $plan.ApplicationProcesses.Count -gt 0 -or $plan.RootProcessIds.Count -gt 0
            ProcessCount = $plan.ApplicationProcesses.Count
            UnknownCount = $plan.UnknownProcesses.Count
            WindowHandle = $(if ($null -ne $window) { [intptr]$window.Handle } else { [intptr]::Zero })
            MainWindowProcessId = $(if ($null -ne $window) { [int]$window.ProcessId } else { $null })
            ActiveVariants = @($plan.ActiveVariants)
            Available = @($definition.Variants | Where-Object { Test-Path -LiteralPath $_.Launcher }).Count -gt 0
        }
    }
}

function Get-CodexInstanceState {
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number, [switch]$IncludeWindows)
    Get-CodexInstanceStates -Numbers @($Number) -IncludeWindows:$IncludeWindows | Select-Object -First 1
}

function Start-CodexInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number, [string]$Variant = 'Standard', [ValidateRange(1,120)][int]$TimeoutSeconds = (Get-CodexManagerSettings).StartupTimeoutSeconds)
    $definition = Get-CodexInstanceDefinition $Number
    $target = $definition.Variants | Where-Object Name -eq $Variant | Select-Object -First 1
    if ($null -eq $target) { throw "Unknown Codex $Number variant: $Variant" }
    if (-not (Test-Path -LiteralPath $target.Launcher)) { throw "启动脚本不存在：$($target.Launcher)" }
    $before = New-CodexTerminationPlan -Processes (Get-CodexProcessSnapshot) -UserDataPath $target.UserDataPath
    if ($before.RootProcessIds.Count -gt 0) { return [pscustomobject]@{ Number=$Number; Variant=$Variant; Status='AlreadyRunning' } }
    $launcher = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $target.Launcher) -WindowStyle Hidden -PassThru
    try {
        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds); $stable = 0
        do {
            Start-Sleep -Milliseconds 400
            $launcher.Refresh()
            if ($launcher.HasExited -and $launcher.ExitCode -ne 0) { throw "Codex $Number ($Variant) 启动脚本失败，退出码 $($launcher.ExitCode)。" }
            $plan = New-CodexTerminationPlan -Processes (Get-CodexProcessSnapshot) -UserDataPath $target.UserDataPath
            $main = @($plan.RootProcesses | Where-Object { $_.CommandLine -notmatch '(?i)--type=' })
            if ($main.Count -gt 0) { $stable++ } else { $stable = 0 }
            if ($stable -ge 2 -and $launcher.HasExited) { return [pscustomobject]@{ Number=$Number; Variant=$Variant; Status='Started' } }
        } while ([datetime]::UtcNow -lt $deadline)
        throw "Codex $Number ($Variant) 启动超时，未确认主进程稳定运行或启动脚本尚未完成；请刷新后检查。"
    } finally { $launcher.Dispose() }
}

function Invoke-CodexWindowForeground {
    param([Parameter(Mandatory)][intptr]$WindowHandle)
    Initialize-CodexWindowApi
    [CodexTrayManager.NativeMethods]::ActivateWindow($WindowHandle)
}

function Show-CodexInstance {
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number)
    $state = Get-CodexInstanceState $Number -IncludeWindows
    if (-not $state.Running) { [void](Start-CodexInstance $Number); return 'Started' }
    if ($state.WindowHandle -eq [intptr]::Zero) { return 'RunningWithoutWindow' }
    if (Invoke-CodexWindowForeground $state.WindowHandle) { return 'Focused' }
    return 'ForegroundFailed'
}

function Invoke-CodexProcessIdentity {
    param([Parameter(Mandatory)]$Process, [switch]$Terminate)
    Initialize-CodexWindowApi
    [CodexTrayManager.ProcessControl]::Inspect([int]$Process.ProcessId, (Get-CodexIdentityTime $Process), [bool]$Terminate)
}

function Acquire-CodexProcessLease {
    param($Process)
    $key = "$($Process.ProcessId):$(Get-CodexIdentityTime $Process)"
    if (-not $script:LeasedIdentities.ContainsKey($key)) {
        Initialize-CodexWindowApi
        $script:LeasedIdentities[$key] = [CodexTrayManager.ProcessControl]::AcquireLease([int]$Process.ProcessId, (Get-CodexIdentityTime $Process))
    }
}

function Request-CodexWindowClose {
    param($Plan)
    Initialize-CodexWindowApi
    foreach ($window in [CodexTrayManager.NativeMethods]::GetTopLevelWindows()) {
        if ($window.ProcessId -notin $Plan.RootProcessIds -or $window.ClassName -ne 'Chrome_WidgetWin_1') { continue }
        $owner = $Plan.RootProcesses | Where-Object ProcessId -eq $window.ProcessId | Select-Object -First 1
        if ((Invoke-CodexProcessIdentity $owner) -eq 'Alive') {
            if (-not [CodexTrayManager.NativeMethods]::RequestClose($window.Handle, $window.ProcessId)) {
                throw "无法向窗口发送正常关闭请求，PID $($window.ProcessId)。"
            }
        }
    }
}

function Stop-CodexInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number, [ValidateRange(0,30)][int]$GraceSeconds = 3, [switch]$IncludeUnconfirmedTasks)
    $definition = Get-CodexInstanceDefinition $Number
    $initial = New-CodexInstanceTerminationPlan -Processes (Get-CodexProcessSnapshot) -Definition $definition -Remember
    $errors = [Collections.Generic.List[string]]::new()
    $tracked = @{}; $forced = 0
    $targets = if ($IncludeUnconfirmedTasks) { $initial.AllProcesses } else { $initial.ApplicationProcesses }
    foreach ($process in $targets) { $tracked[[int]$process.ProcessId] = $process }
    if ($initial.UnknownProcesses.Count -gt 0 -and -not $IncludeUnconfirmedTasks) {
        return [pscustomobject]@{ Number=$Number; Found=$tracked.Count; Forced=0; Stopped=$false; Status='BlockedUnknownTasks'; Remaining=@($tracked.Keys); Unknown=@($initial.UnknownProcesses | Select-Object ProcessId,Name,CreationDate); Errors=@('检测到未确认用途的子任务，尚未发送关闭请求；请先检查更新脚本或其他任务。') }
    }
    if ($tracked.Count -eq 0) {
        return [pscustomobject]@{ Number=$Number; Found=0; Forced=0; Stopped=$true; Status='AlreadyStopped'; Remaining=@(); Unknown=@(); Errors=@() }
    }
    try {
        foreach ($process in $tracked.Values) { Acquire-CodexProcessLease $process }
        try { Request-CodexWindowClose $initial } catch { $errors.Add($_.Exception.Message) }
        $deadline = [datetime]::UtcNow.AddSeconds($GraceSeconds)
        while ([datetime]::UtcNow -lt $deadline) {
            $alive = $false
            foreach ($process in $tracked.Values) {
                try { if ((Invoke-CodexProcessIdentity $process) -notin @('Gone','IdentityChanged')) { $alive=$true; break } }
                catch { $alive=$true; break }
            }
            if (-not $alive) { break }
            Start-Sleep -Milliseconds 100
        }
        $current = New-CodexInstanceTerminationPlan -Processes (Get-CodexProcessSnapshot) -Definition $definition -Remember
        $targets = if ($IncludeUnconfirmedTasks) { $current.AllProcesses } else { $current.ApplicationProcesses }
        foreach ($process in $targets) { $tracked[[int]$process.ProcessId] = $process }
        if ($current.UnknownProcesses.Count -eq 0 -or $IncludeUnconfirmedTasks) {
            foreach ($process in $targets) { Acquire-CodexProcessLease $process }
            # End producers first. Each individual handle is identity checked; descendants are never killed implicitly.
            foreach ($process in @($tracked.Values | Sort-Object CreationDate)) {
                try { if ((Invoke-CodexProcessIdentity $process -Terminate) -eq 'TerminationRequested') { $forced++ } }
                catch { $errors.Add("PID $($process.ProcessId)：$($_.Exception.Message)") }
            }
        } else { $errors.Add('关闭期间发现新的未确认子任务，已停止强制结束。') }
        Start-Sleep -Milliseconds 200
        $remaining = [Collections.Generic.HashSet[int]]::new()
        # Verify the entire remembered set, even when Electron roots have disappeared.
        foreach ($process in $tracked.Values) {
            try { if ((Invoke-CodexProcessIdentity $process) -notin @('Gone','IdentityChanged')) { [void]$remaining.Add([int]$process.ProcessId) } }
            catch { [void]$remaining.Add([int]$process.ProcessId); $errors.Add("核验 PID $($process.ProcessId)：$($_.Exception.Message)") }
        }
        $after = New-CodexInstanceTerminationPlan -Processes (Get-CodexProcessSnapshot) -Definition $definition -Remember
        foreach ($process in $after.ApplicationProcesses) { [void]$remaining.Add([int]$process.ProcessId) }
        $stopped = $remaining.Count -eq 0 -and $after.UnknownProcesses.Count -eq 0
        [pscustomobject]@{
            Number=$Number; Found=$tracked.Count; Forced=$forced; Stopped=$stopped
            Status=$(if ($stopped) { 'Stopped' } elseif ($after.UnknownProcesses.Count) { 'BlockedUnknownTasks' } else { 'Incomplete' })
            Remaining=@($remaining); Unknown=@($after.UnknownProcesses | Select-Object ProcessId,Name,CreationDate); Errors=@($errors)
        }
    } finally {
        foreach ($lease in $script:LeasedIdentities.Values) { $lease.Dispose() }
        $script:LeasedIdentities.Clear()
    }
}

function Restart-CodexInstance {
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number)
    $variants = @((Get-CodexInstanceState $Number).ActiveVariants)
    $result = Stop-CodexInstance $Number
    if (-not $result.Stopped) { throw (Format-CodexStopResult $result) }
    if ($variants.Count -eq 0) { $variants = @('Standard') }
    foreach ($variant in $variants) { Start-CodexInstance $Number -Variant $variant }
}

function Format-CodexStopResult {
    param($Result)
    if ($Result.Stopped) { return "Codex $($Result.Number)：应用已退出（处理 $($Result.Found) 个进程）。" }
    $unknown = @($Result.Unknown | ForEach-Object { "$($_.Name) [PID $($_.ProcessId)]" }) -join ', '
    "Codex $($Result.Number)：未完成关闭。残留应用 PID：$($Result.Remaining -join ', ')。待检查子任务：$unknown。$($Result.Errors -join '；')"
}

function Get-CodexClosePreview {
    param([Parameter(Mandatory)][ValidateRange(4,25)][int]$Number)
    $plan = New-CodexInstanceTerminationPlan -Processes (Get-CodexProcessSnapshot) -Definition (Get-CodexInstanceDefinition $Number) -Remember
    $lines = @("Codex $Number：$($plan.ApplicationProcesses.Count) 个应用进程；$($plan.UnknownProcesses.Count) 个待检查子任务。")
    foreach ($process in $plan.ApplicationProcesses) { $lines += "应用：$($process.Name) [PID $($process.ProcessId)]" }
    foreach ($process in $plan.UnknownProcesses) { $lines += "待检查：$($process.Name) [PID $($process.ProcessId)]，创建时间 $($process.CreationDate)" }
    if ($plan.UnknownProcesses.Count) { $lines += '普通关闭会拦截这些子任务；请先检查更新或其他工作。应急关闭会中断它们。' }
    $lines -join "`r`n"
}

function Stop-AllCodexInstances {
    param([ValidateRange(4,25)][int[]]$Numbers)
    if (-not $PSBoundParameters.ContainsKey('Numbers')) {
        $Numbers = @((Get-CodexManagerSettings).Instances.Number | Sort-Object)
    }
    $results = foreach ($number in $Numbers) {
        try { Stop-CodexInstance $number -GraceSeconds 2 }
        catch { [pscustomobject]@{ Number=$number; Found=0; Forced=0; Stopped=$false; Status='Error'; Remaining=@(); Unknown=@(); Errors=@($_.Exception.Message) } }
    }
    [pscustomobject]@{ Results=@($results); Succeeded=@($results | Where-Object Stopped).Count; Failed=@($results | Where-Object { -not $_.Stopped }).Count }
}

Export-ModuleMember -Function Get-CodexManagerSettings,Get-CodexInstanceDefinition,New-CodexTerminationPlan,Get-CodexInstanceState,Get-CodexInstanceStates,Start-CodexInstance,Show-CodexInstance,Select-CodexWindowCandidate,Invoke-CodexWindowForeground,Stop-CodexInstance,Restart-CodexInstance,Stop-AllCodexInstances,Format-CodexStopResult,Get-CodexClosePreview,Initialize-CodexWindowApi

