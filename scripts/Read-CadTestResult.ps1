#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CadTest.Common.ps1')
$root = (Resolve-Path -LiteralPath $RunDirectory).Path
$run = Read-CadJson (Join-Path $root 'run.json')
if ($run.SchemaVersion -ne 1) { throw 'Unsupported run schema.' }
if ($run.State -eq 'Prepared' -or [int]$run.ProcessId -le 0) { throw 'Prepared only: no CAD execution recorded.' }
$resultPath = Join-Path $root 'result.json'
if (-not (Test-Path -LiteralPath $resultPath)) { throw "Incomplete: result.json is missing. Inspect PID $($run.ProcessId), startup-error.txt and assertions.log." }
$result = Read-CadJson $resultPath
if ($result.SchemaVersion -ne 1 -or $result.RunId -ne $run.RunId -or $result.ProcessId -ne $run.ProcessId) { throw 'Result run/process/schema mismatch.' }
if ($result.Host -ne $run.Host -or [regex]::Match($result.AcadVersion,'^\d+\.\d+').Value -ne $run.ExpectedAcadVersion) { throw 'Wrong CAD host or version.' }
if (-not $result.Complete -or -not $result.Success -or @($result.Failures).Count -gt 0) { throw "Failed/incomplete: $($result.Failures -join '; ')" }
if (-not $result.ServiceTransactionAborted -or -not $result.ModelHandleSetRestored -or [int]$result.AssertionCount -lt 1) { throw 'Missing assertions, service abort or handle-set verification.' }
if ([int]$result.ScenarioAssertionCount -lt 1) { throw 'No scenario assertion was executed.' }
foreach ($flag in @('Complete','Success','ServiceTransactionAborted','ModelHandleSetRestored')) {
    if ($result.$flag -isnot [bool] -or $result.$flag -ne $true) { throw "Expected boolean true: $flag" }
}
$alive = $null -ne (Get-CadRunProcess $run)
if ($run.Host -eq 'Desktop') {
    if ($result.ClosedWithoutSaving -isnot [bool] -or $result.ClosedWithoutSaving -ne $true) { throw 'Missing Desktop CloseAndDiscard evidence.' }
} else {
    if ($result.DiscardOnProcessExitRequested -isnot [bool] -or $result.DiscardOnProcessExitRequested -ne $true -or $alive) { throw 'Core Console discard/exit is not complete.' }
    if ($run.PSObject.Properties.Name -notcontains 'ProcessExitCode' -or $run.ProcessExitCode -ne 0) { throw 'Core Console requires a recorded zero process exit code.' }
}
if ($run.PSObject.Properties.Name -contains 'ProcessExitCode' -and $run.ProcessExitCode -ne 0) { throw 'CAD host exit failed; inspect original launcher error separately from scenario assertions.' }
if ([string]::IsNullOrWhiteSpace($result.Scope)) { throw 'Missing actual test scope.' }
if ([IO.Path]::GetFullPath($result.DrawingPath) -ine [IO.Path]::GetFullPath($run.DrawingPath)) { throw 'Wrong input drawing copy.' }
if ([IO.Path]::GetFullPath($result.TestAssemblyPath) -ine [IO.Path]::GetFullPath($run.TestAssemblyPath)) { throw 'Wrong loaded runner path.' }
$hash = Get-CadHash $run.TestAssemblyPath
if ($hash -ne $run.TestAssemblySha256 -or $result.TestAssemblySha256 -ne $hash) { throw 'Runner SHA256 mismatch.' }
foreach ($file in @($run.BinaryFiles)) { if ((Get-CadHash $file.Path) -ne $file.Sha256) { throw "Staged binary changed: $($file.Path)" } }
foreach ($file in @($result.PluginAssemblies)) {
    if ((Get-CadHash $file.Path) -ne $file.Sha256) { throw "Loaded assembly hash changed: $($file.Path)" }
}
foreach ($file in @($run.InputFiles)) {
    if ((Get-CadHash $file.Source) -ne $file.Sha256 -or (Get-CadHash $file.Copy) -ne $file.Sha256) { throw "Input/source hash changed: $($file.Source)" }
}
[pscustomobject]@{
    Status='PASS';Scope=$result.Scope;Host=$result.Host;AcadVersion=$result.AcadVersion;HostBuild=$result.HostBuild
    AssertionCount=$result.AssertionCount;CommandsCompleted=@($result.CommandsCompleted);ClosedWithoutSaving=$true;InputHashesUnchanged=$true
    ProcessStillRunning=$alive;OriginalLauncherState=$run.State;ResultPath=$resultPath
}
