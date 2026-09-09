param([string]$ModulePath, [int]$Iterations=10)
$ErrorActionPreference='Stop'
Import-Module $ModulePath -Force
$module=Get-Module CodexTrayManager.Core
$snapshot=@(& $module { Get-CodexProcessSnapshot })
[void](Get-CodexInstanceStates -Processes $snapshot)
$cached=@(); $full=@()
for ($i=0;$i -lt $Iterations;$i++) {
    $watch=[Diagnostics.Stopwatch]::StartNew(); [void](Get-CodexInstanceStates -Processes $snapshot); $watch.Stop(); $cached+=$watch.Elapsed.TotalMilliseconds
    $watch.Restart(); [void](Get-CodexInstanceStates); $watch.Stop(); $full+=$watch.Elapsed.TotalMilliseconds
}
[pscustomobject]@{ Module=$ModulePath; ProcessCount=$snapshot.Count; CachedAverageMs=[math]::Round(($cached | Measure-Object -Average).Average,1); FullAverageMs=[math]::Round(($full | Measure-Object -Average).Average,1); FullMinMs=[math]::Round(($full | Measure-Object -Minimum).Minimum,1); FullMaxMs=[math]::Round(($full | Measure-Object -Maximum).Maximum,1); FullSamplesMs=@($full | ForEach-Object { [math]::Round($_,1) }); CachedSamplesMs=@($cached | ForEach-Object { [math]::Round($_,1) }) } | ConvertTo-Json -Depth 3
