#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunDirectory,[switch]$LoadOnce,[switch]$ApproveAlways)
$ErrorActionPreference='Stop'
if ([bool]$LoadOnce -eq [bool]$ApproveAlways) { throw 'Specify exactly one LoadOnce or ApproveAlways action.' }
$action = if ($ApproveAlways) { 'Always' } else { 'Once' }
# Backward-compatible entrypoint: the scope now includes all DLL prompts in the
# owned CAD process, plus proxy and missing-font dialogs, before and after NETLOAD.
& (Join-Path $PSScriptRoot 'Handle-CadTestDialogs.ps1') -RunDirectory $RunDirectory -DllAction $action
