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
$records = @()
foreach ($window in $windows) {
    $controls = @()
    $items = $window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
    foreach ($item in $items) {
        $type = $item.Current.ControlType.ProgrammaticName
        if ($type -in @('ControlType.Text','ControlType.Button','ControlType.Edit','ControlType.CheckBox','ControlType.Hyperlink')) {
            $controls += [pscustomobject]@{Name=$item.Current.Name;AutomationId=$item.Current.AutomationId;Type=$type;Enabled=$item.Current.IsEnabled}
        }
    }
    $records += [pscustomobject]@{Title=$window.Current.Name;ClassName=$window.Current.ClassName;Handle=$window.Current.NativeWindowHandle;Controls=$controls}
}
$observation = [pscustomobject]@{Status='Observed';ProcessId=$run.ProcessId;ObservedUtc=[DateTime]::UtcNow.ToString('o');Windows=$records}
Write-CadJson (Join-Path $root 'dialogs.latest.json') $observation
$observation
