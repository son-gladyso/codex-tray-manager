[CmdletBinding()]
param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'CodexTrayManager.Core.psm1'
Import-Module $modulePath -Force
$script:passes = 0
$script:failures = [Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { $script:passes++; Write-Output "PASS: $Name" }
    else { $script:failures.Add($Name); Write-Output "FAIL: $Name" }
}
function Assert-Set($Actual, $Expected, [string]$Name) {
    Assert-True ((@($Actual | Sort-Object) -join ',') -eq (@($Expected | Sort-Object) -join ',')) $Name
}
function New-Fixture([int]$Id, [int]$Parent, [string]$Name, [string]$Command, [int]$Second = 1, [string]$Path = '') {
    if (-not $Path) { $Path = if ($Name -eq 'ChatGPT.exe') { 'D:\test-app\ChatGPT.exe' } else { "D:\test-core\$Name" } }
    [pscustomobject]@{ ProcessId=$Id; ParentProcessId=$Parent; Name=$Name; CommandLine=$Command; CreationDate=([datetime]'2026-09-08T02:00:00Z').AddSeconds($Second); ExecutablePath=$Path }
}
$app = New-Fixture 100 1 'ChatGPT.exe' 'ChatGPT.exe --user-data-dir=D:\codex4\codex-desktop-userdata'
$renderer = New-Fixture 101 100 'ChatGPT.exe' 'ChatGPT.exe --type=renderer --user-data-dir="D:\codex4\codex-desktop-userdata"' 2
$server = New-Fixture 102 100 'codex.exe' '"D:\test-core\codex.exe" app-server' 2
$hostProcess = New-Fixture 103 102 'codex-code-mode-host.exe' 'codex-code-mode-host.exe' 3
$other = New-Fixture 200 1 'ChatGPT.exe' 'ChatGPT.exe --user-data-dir=D:\codex5\codex-desktop-userdata'
$updater = New-Fixture 104 102 'powershell.exe' 'powershell.exe -File unrelated-name.ps1' 4
$fixture = @($app,$renderer,$server,$hostProcess,$other)
$profile = 'D:\codex4\codex-desktop-userdata'
$plan = New-CodexTerminationPlan -Processes $fixture -UserDataPath $profile
Assert-Set $plan.ApplicationProcesses.ProcessId @(100,101,102,103) 'Only Electron and verified application helpers belong to this instance'
Assert-True ($plan.UnknownProcesses.Count -eq 0) 'Known helper hierarchy has no unknown task'
$plan = New-CodexTerminationPlan -Processes @($fixture + $updater) -UserDataPath $profile
Assert-Set $plan.UnknownProcesses.ProcessId @(104) 'Arbitrary child script requires inspection regardless of its filename'
$older = New-Fixture 105 100 'codex.exe' 'codex.exe app-server' 0
$plan = New-CodexTerminationPlan -Processes @($fixture + $older) -UserDataPath $profile
Assert-True (105 -notin $plan.AllProcessIds) 'PID reuse: a child older than the current parent is excluded'
$unknownIdentity = $app.PSObject.Copy(); $unknownIdentity.CreationDate = $null
$plan = New-CodexTerminationPlan -Processes @($unknownIdentity,$server) -UserDataPath $profile
Assert-True ($plan.ApplicationProcesses.Count -eq 0 -and $plan.UnknownProcesses.Count -eq 2) 'Missing creation times do not authorize termination'
$lookalike = New-Fixture 106 100 'ChatGPT.exe' 'ChatGPT.exe --type=renderer' 2 'D:\other\ChatGPT.exe'
$plan = New-CodexTerminationPlan -Processes @($app,$lookalike) -UserDataPath $profile
Assert-Set $plan.UnknownProcesses.ProcessId @(106) 'Same-name helper with a different executable path remains unknown'
$longer = New-Fixture 107 1 'ChatGPT.exe' 'ChatGPT.exe --user-data-dir=D:\codex4\codex-desktop-userdata-old'
$embedded = New-Fixture 108 1 'ChatGPT.exe' 'ChatGPT.exe x--user-data-dir=D:\codex4\codex-desktop-userdata'
$plan = New-CodexTerminationPlan -Processes @($longer,$embedded) -UserDataPath $profile
Assert-True ($plan.AllProcessIds.Count -eq 0) 'Profile matching rejects prefix collisions and embedded arguments'
$empty = New-CodexTerminationPlan -Processes @() -UserDataPath $profile
Assert-True ($empty.AllProcessIds.Count -eq 0) 'Empty process list is valid'
$quoted = New-Fixture 109 1 'ChatGPT.exe' 'ChatGPT.exe "--user-data-dir=D:\codex4\codex-desktop-userdata"'
$embeddedQuoted = New-Fixture 110 1 'ChatGPT.exe' 'ChatGPT.exe --title="example --user-data-dir=D:\codex4\codex-desktop-userdata"'
$plan = New-CodexTerminationPlan -Processes @($quoted,$embeddedQuoted) -UserDataPath $profile
Assert-Set $plan.RootProcessIds @(109) 'Windows argument parsing supports quoted flags without matching text inside another argument'
$std = New-Fixture 500 1 'ChatGPT.exe' 'ChatGPT.exe --user-data-dir=D:\codex25\codex-desktop-userdata'
$ui = New-Fixture 600 1 'ChatGPT.exe' 'ChatGPT.exe --user-data-dir=D:\codex25\ui-canary-state-26.810.7004.0\codex-desktop-userdata'
$state25 = Get-CodexInstanceStates -Numbers @(25) -Processes @($std,$ui)
Assert-Set $state25.ActiveVariants @('Standard','UICanary') 'An instance can aggregate standard and canary variants'
Assert-True ($state25.ProcessCount -eq 2) 'Merged Codex 25 count includes both versions'
$states = @(Get-CodexInstanceStates -Numbers @(4,5) -Processes $fixture)
Assert-True ($states[0].ProcessCount -eq 4 -and $states[1].ProcessCount -eq 1) 'Shared snapshot isolates instance counts'
$bad = $false
try { Get-CodexInstanceDefinition 3 | Out-Null } catch { $bad = $true }
Assert-True $bad 'Unsupported instance numbers are rejected'
$window = Select-CodexWindowCandidate -Windows @(
    [pscustomobject]@{ Handle=[intptr]11; ProcessId=100; Visible=$false; ClassName='Chrome_WidgetWin_0'; Title='' },
    [pscustomobject]@{ Handle=[intptr]12; ProcessId=100; Visible=$false; ClassName='Chrome_WidgetWin_1'; Title='ChatGPT' },
    [pscustomobject]@{ Handle=[intptr]13; ProcessId=200; Visible=$true; ClassName='Chrome_WidgetWin_1'; Title='ChatGPT' }
) -ProcessIds @(100)
Assert-True ($window.Handle -eq [intptr]12) 'Hidden main window is selected without selecting another instance'

# Replace OS calls inside the module; these tests cannot close any user application.
function Set-SimulatedRuntime($Snapshots, [int[]]$Denied = @()) {
    Import-Module $modulePath -Force
    $module = Get-Module CodexTrayManager.Core
    & $module {
        param($Snapshots,$Denied)
        $script:Snapshots = [Collections.Generic.Queue[object]]::new()
        foreach ($snapshot in $Snapshots) { $script:Snapshots.Enqueue($snapshot) }
        $script:Denied = $Denied; $script:Killed = @(); $script:Requested = 0; $script:Observed = @{}
        function script:Get-CodexProcessSnapshot { if ($script:Snapshots.Count -eq 0) { throw 'Test snapshot queue exhausted' }; $script:Snapshots.Dequeue() }
        function script:Request-CodexWindowClose { param($Plan); $script:Requested++ }
        function script:Acquire-CodexProcessLease {
            param($Process)
            $key = "$($Process.ProcessId):$(Get-CodexIdentityTime $Process)"
            $lease = [pscustomobject]@{}
            $lease | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
            $script:LeasedIdentities[$key] = $lease
        }
        function script:Invoke-CodexProcessIdentity {
            param($Process,[switch]$Terminate)
            if ($Process.ProcessId -in $script:Denied) { throw 'Access denied (test)' }
            if ($Process.ProcessId -in $script:Killed) { return 'Gone' }
            if ($Terminate) { $script:Killed += $Process.ProcessId; return 'TerminationRequested' }
            return 'Alive'
        }
    } $Snapshots $Denied
    return $module
}
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server,$updater))
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0
$counts = & $module { @($script:Requested,$script:Killed.Count) }
Assert-True (-not $result.Stopped -and $result.Status -eq 'BlockedUnknownTasks') 'Unregistered waiting script blocks close with an explicit result'
Assert-True ($counts[0] -eq 0 -and $counts[1] -eq 0) 'Blocked close does not send WM_CLOSE or kill an ancestor'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server)); $snapshots.Add(@($server)); $snapshots.Add(@($server))
$module = Set-SimulatedRuntime $snapshots @(102)
$result = Stop-CodexInstance 4 -GraceSeconds 0
Assert-True (-not $result.Stopped -and 102 -in $result.Remaining) 'Orphan app server with denied access prevents a false success'
Assert-True (($result.Errors -join ' ') -match 'Access denied') 'Termination and verification errors remain visible'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server)); $snapshots.Add(@($server)); $snapshots.Add(@())
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0
Assert-True ($result.Stopped -and $result.Remaining.Count -eq 0) 'Successful close verifies remembered helpers after the root disappears'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server)); $snapshots.Add(@($server,$updater)); $snapshots.Add(@($server,$updater))
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0
$killCount = & $module { $script:Killed.Count }
Assert-True (-not $result.Stopped -and $killCount -eq 0) 'Task appearing during graceful wait prevents forced termination'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app)); $snapshots.Add(@($app)); $snapshots.Add(@($server))
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0
Assert-True (-not $result.Stopped -and 102 -in $result.Remaining) 'A newly discovered helper remains attributable after its leased parent exits'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server)); $snapshots.Add(@($app,$server)); $snapshots.Add(@($updater))
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0
Assert-True (-not $result.Stopped -and $result.Unknown.Count -eq 1) 'Late orphan user task is reported through retained ancestor identities'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server,$updater)); $snapshots.Add(@($app,$server,$updater)); $snapshots.Add(@())
$module = Set-SimulatedRuntime $snapshots
$result = Stop-CodexInstance 4 -GraceSeconds 0 -IncludeUnconfirmedTasks
Assert-True ($result.Stopped -and $result.Forced -eq 3) 'Explicit emergency close includes child tasks using individual verified identities'
$snapshots = [Collections.Generic.List[object]]::new(); $snapshots.Add(@($app,$server)); $snapshots.Add(@($server)); $snapshots.Add(@())
$module = Set-SimulatedRuntime $snapshots
$stateA = Get-CodexInstanceState 4; $stateB = Get-CodexInstanceState 4; $stateC = Get-CodexInstanceState 4
Assert-True ($stateA.ProcessCount -eq 2 -and $stateB.Running -and $stateB.ProcessCount -eq 1 -and -not $stateC.Running) 'Session tracking retains a known orphan and clears it after exit'
& $module {
    function script:Stop-CodexInstance { param($Number,$GraceSeconds)
        if ($Number -eq 5) { throw 'Access denied on instance 5' }
        [pscustomobject]@{ Number=$Number; Stopped=($Number -ne 6); Found=1; Forced=0; Status='Test'; Remaining=@(); Unknown=@(); Errors=@() }
    }
}
$batch = Stop-AllCodexInstances -Numbers @(4,5,6,7)
Assert-True ($batch.Succeeded -eq 2 -and $batch.Failed -eq 2 -and $batch.Results.Count -eq 4) 'Batch reports partial failures and continues after an exception'
& $module {
    $script:StartedVariants = @()
    function script:Get-CodexInstanceState { param($Number); [pscustomobject]@{ ActiveVariants=@('Standard','UICanary') } }
    function script:Start-CodexInstance { param($Number,$Variant); $script:StartedVariants += $Variant }
}
Restart-CodexInstance 25
Assert-Set (& $module { $script:StartedVariants }) @('Standard','UICanary') 'Restart preserves both previously active Codex 25 versions'
& $module {
    $script:StartedVariants = @()
    function script:Stop-CodexInstance { param($Number); [pscustomobject]@{ Number=$Number; Stopped=$false; Remaining=@(104); Unknown=@(); Errors=@('Blocked'); Found=1 } }
}
$threw = $false
try { Restart-CodexInstance 25 } catch { $threw=$true }
Assert-True ($threw -and @(& $module { $script:StartedVariants }).Count -eq 0) 'Restart never launches after blocked or failed close'
Import-Module $modulePath -Force
$module = Get-Module CodexTrayManager.Core
& $module {
    function script:Get-CodexProcessSnapshot { @() }
    function script:Test-Path { param($LiteralPath); return $true }
    function script:Start-Process {
        $p = [pscustomobject]@{ HasExited=$true; ExitCode=9 }
        $p | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
        $p | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        $p
    }
}
$threw = $false
try { Start-CodexInstance 4 -TimeoutSeconds 1 | Out-Null } catch { $threw = $_.Exception.Message -match '退出码 9' }
Assert-True $threw 'Failed launcher exit is reported rather than announcing startup'
Import-Module $modulePath -Force

# Warm snapshots must not repeat WMI, and a recycled PID must fetch a new command line.
$module = Get-Module CodexTrayManager.Core
$reused = $app.PSObject.Copy(); $reused.CreationDate = $app.CreationDate.AddMinutes(1)
$reused.CommandLine = 'ChatGPT.exe --user-data-dir=D:\codex5\codex-desktop-userdata'
& $module {
    param($App,$Reused)
    $script:NativeQueue = [Collections.Generic.Queue[object]]::new()
    foreach ($p in @($App,$App,$Reused)) { $copy=$p.PSObject.Copy(); $copy.CommandLine=$null; $script:NativeQueue.Enqueue(@($copy)) }
    $script:NativeQueue.Enqueue(@())
    $script:MetadataQueue = [Collections.Generic.Queue[object]]::new()
    $script:MetadataQueue.Enqueue(@($App)); $script:MetadataQueue.Enqueue(@($Reused))
    $script:MetadataCalls = 0
    function script:Get-CodexNativeSnapshot { $script:NativeQueue.Dequeue() }
    function script:Get-CodexCommandMetadata { param($ProcessIds); $script:MetadataCalls++; $script:MetadataQueue.Dequeue() }
} $app $reused
$cacheStates = & $module {
    $a=@(Get-CodexProcessSnapshot); $b=@(Get-CodexProcessSnapshot); $warmCalls=$script:MetadataCalls
    $c=@(Get-CodexProcessSnapshot); $newCalls=$script:MetadataCalls
    [void](Get-CodexProcessSnapshot)
    [pscustomobject]@{ WarmCalls=$warmCalls; NewCalls=$newCalls; NewCommand=$c[0].CommandLine; Cached=$script:CommandCache.Count }
}
Assert-True ($cacheStates.WarmCalls -eq 1) 'Unchanged identities reuse command metadata without another WMI query'
Assert-True ($cacheStates.NewCalls -eq 2 -and $cacheStates.NewCommand -match 'codex5') 'A recycled PID refreshes metadata instead of inheriting its old profile'
Assert-True ($cacheStates.Cached -eq 0) 'Exited identities are removed from the metadata cache'
Import-Module $modulePath -Force

# Each failed refresh discovers a different valid identity before encountering a bad record.
# Pruning at the end would leak every valid identity added by those failed refreshes.
$module = Get-Module CodexTrayManager.Core
$stress = & $module {
    $script:CacheStressRound = 0
    function script:Get-CodexNativeSnapshot {
        $script:CacheStressRound++
        foreach ($id in @((10000+$script:CacheStressRound),99999)) {
            [pscustomobject]@{ ProcessId=$id; ParentProcessId=1; Name='ChatGPT.exe'; CreationDate=[datetime]'2026-09-08T02:00:00Z'; CommandLine=$null; ExecutablePath='D:\test-app\ChatGPT.exe' }
        }
    }
    function script:Get-CodexCommandMetadata {
        param($ProcessIds)
        foreach ($id in $ProcessIds) {
            [pscustomobject]@{ ProcessId=$id; CreationDate=[datetime]'2026-09-08T02:00:00Z'; CommandLine=$(if ($id -eq 99999) { '' } else { 'ChatGPT.exe --user-data-dir=D:\codex4\codex-desktop-userdata' }) }
        }
    }
    $maximum = 0; $failures = 0
    for ($round=0; $round -lt 1000; $round++) {
        try { [void](Get-CodexProcessSnapshot) } catch { $failures++ }
        $maximum = [math]::Max($maximum,$script:CommandCache.Count)
    }
    function script:Get-CodexNativeSnapshot { @() }
    [void](Get-CodexProcessSnapshot)
    [pscustomobject]@{ Rounds=1000; Failures=$failures; Maximum=$maximum; AfterExit=$script:CommandCache.Count }
}
Assert-True ($stress.Failures -eq 1000 -and $stress.Maximum -eq 1) "1000 partial metadata failures keep at most one current cache entry (failures=$($stress.Failures) max=$($stress.Maximum))"
Assert-True ($stress.AfterExit -eq 0) 'Cache is empty after all stress-test identities exit'
Import-Module $modulePath -Force

if ($Integration) {
    Initialize-CodexWindowApi
    $treeMarker = Join-Path $env:TEMP ("codex-tray-tree-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $parentProcess = $null; $childIdentity = $null; $lease = $null
    try {
        $code = "`$c=Start-Process powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru; Set-Content -LiteralPath '$treeMarker' -Value (`$c.Id.ToString()+'|'+`$c.StartTime.ToUniversalTime().ToFileTimeUtc()); Start-Sleep -Seconds 60"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $parentProcess = Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encoded" -WindowStyle Hidden -PassThru
        $deadline = [datetime]::UtcNow.AddSeconds(8)
        while (-not (Test-Path -LiteralPath $treeMarker) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
        $childIdentity = (Get-Content -LiteralPath $treeMarker -Raw).Trim() -split '\|'
        $created = $parentProcess.StartTime.ToUniversalTime().ToFileTimeUtc()
        $lease = [CodexTrayManager.ProcessControl]::AcquireLease($parentProcess.Id,$created)
        $native = @([CodexTrayManager.ProcessControl]::Snapshot())
        $nativeChild = $native | Where-Object ProcessId -eq ([int]$childIdentity[0])
        Assert-True ($nativeChild.ParentProcessId -eq $parentProcess.Id -and $null -ne $nativeChild.CreationDate) 'Native snapshot identifies a real disposable parent-child relationship'
        [void][CodexTrayManager.ProcessControl]::Inspect($parentProcess.Id,$created,$true)
        Assert-True ($parentProcess.WaitForExit(3000)) 'Retained identity handle permits exit and remains held until verification'
        Assert-True ([CodexTrayManager.ProcessControl]::Inspect([int]$childIdentity[0],[long]$childIdentity[1],$false) -eq 'Alive') 'Individual parent termination does not implicitly terminate its child task'
    } finally {
        if ($null -ne $childIdentity) { [void][CodexTrayManager.ProcessControl]::Inspect([int]$childIdentity[0],[long]$childIdentity[1],$true) }
        if ($null -ne $lease) { $lease.Dispose() }
        if ($null -ne $parentProcess) { if (-not $parentProcess.HasExited) { $parentProcess.Kill() }; $parentProcess.Dispose() }
        Remove-Item -LiteralPath $treeMarker -Force -ErrorAction SilentlyContinue
    }
    $child = $null
    try {
        $child = Start-Process powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru
        $creation = $child.StartTime.ToUniversalTime().ToFileTimeUtc()
        $wrong = [CodexTrayManager.ProcessControl]::Inspect($child.Id, $creation + 10000000, $true)
        Assert-True ($wrong -eq 'IdentityChanged' -and -not $child.HasExited) 'Real process with mismatched creation time cannot be terminated'
        $answer = [CodexTrayManager.ProcessControl]::Inspect($child.Id, $creation, $true)
        Assert-True ($child.WaitForExit(3000)) 'Real disposable process terminates through a verified handle'
        $gone = [CodexTrayManager.ProcessControl]::Inspect($child.Id, $creation, $false)
        Assert-True ($gone -eq 'Gone') 'Exited disposable process is reported gone'
    } finally { if ($null -ne $child) { if (-not $child.HasExited) { $child.Kill() }; $child.Dispose() } }
    $marker = Join-Path $env:TEMP ("codex-tray-focus-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $windowProcess = $null
    try {
        $code = "Add-Type -AssemblyName System.Windows.Forms; `$f=[Windows.Forms.Form]::new(); `$f.Text='Codex disposable window'; `$f.Show(); `$h=`$f.Handle; `$f.Hide(); Set-Content -LiteralPath '$marker' -Value `$h.ToInt64(); [Windows.Forms.Application]::Run()"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $windowProcess = Start-Process powershell.exe -ArgumentList "-NoProfile -STA -EncodedCommand $encoded" -WindowStyle Hidden -PassThru
        $deadline = [datetime]::UtcNow.AddSeconds(8)
        while (-not (Test-Path -LiteralPath $marker) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
        $handle = [intptr][long](Get-Content -LiteralPath $marker -Raw)
        $focused = Invoke-CodexWindowForeground $handle
        $record = [CodexTrayManager.NativeMethods]::GetTopLevelWindows() | Where-Object Handle -eq $handle
        Assert-True ($focused -and $record.Visible) "Real hidden disposable window becomes visible and foreground (focused=$focused visible=$($record.Visible))"
        Assert-True ([CodexTrayManager.NativeMethods]::RequestClose($handle,$windowProcess.Id)) 'Hidden-window close path posts WM_CLOSE to its verified owner'
    } finally {
        if ($null -ne $windowProcess) { if (-not $windowProcess.HasExited) { $windowProcess.Kill() }; $windowProcess.Dispose() }
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    }
}
& pwsh.exe -NoProfile -File (Join-Path $root 'CodexTrayManager.ps1') -ValidateOnly | Out-Host
Assert-True ($LASTEXITCODE -eq 0) 'UI and native dependencies pass self-check'
if ($script:failures.Count) { Write-Output "FAILED: $($script:failures.Count); passed: $script:passes"; exit 1 }
Write-Output "PASS: $script:passes behavioral checks. Integration=$Integration"

