#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CadTest.Common.ps1')
$root = (Resolve-Path -LiteralPath $RunDirectory).Path
$run = Read-CadJson (Join-Path $root 'run.json')
$process = Get-CadRunProcess $run
if (-not $process) { [pscustomobject]@{Status='ProcessNotRunning';Windows=@()}; return }
if ($run.Host -ne 'Desktop') { [pscustomobject]@{Status='ConsoleHost';Windows=@()}; return }
$windows = @(Get-CadDialogElements $run.ProcessId)
$observation = [pscustomobject]@{Status='Observed';ProcessId=$run.ProcessId;ObservedUtc=[DateTime]::UtcNow.ToString('o');Windows=$windows}
Write-CadJson (Join-Path $root 'dialogs.latest.json') $observation
$observation
