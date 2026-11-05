#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$BuildExecutable)
$ErrorActionPreference='Stop'
# Build only a synthetic native-dialog fixture. It contains no Autodesk code and
# never reads a drawing or loads a DLL; acad.exe is used to exercise PID guards.
Add-Type -Path (Join-Path $PSScriptRoot 'CadDialogFixture.cs') -OutputType WindowsApplication -OutputAssembly $BuildExecutable
