#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,79}$')][string]$Name,
    [ValidateRange(2020,2026)][int]$CadVersion = 2020
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'Choose a non-reserved name.' }
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) { throw "Destination already exists: $destinationPath" }
$framework = if ($CadVersion -ge 2025) { 'net8.0-windows' } elseif ($CadVersion -ge 2021) { 'net48' } else { 'net472' }
$versions = @{2020='23.1';2021='24.0';2022='24.1';2023='24.2';2024='24.3';2025='25.0';2026='25.1'}
$encoding = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $destinationPath | Out-Null
$template = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\harness'
foreach ($file in Get-ChildItem -LiteralPath $template -File) {
    $nameOnDisk = if ($file.Extension -eq '.csproj') { "$Name.csproj" } else { $file.Name }
    $content = [IO.File]::ReadAllText($file.FullName).Replace('__HARNESS_NAME__',$Name).Replace('__TARGET_FRAMEWORK__',$framework)
    [IO.File]::WriteAllText((Join-Path $destinationPath $nameOnDisk),$content,$encoding)
}
$config = [ordered]@{SchemaVersion=1;AssemblyName=$Name;CadVersion=$CadVersion;ExpectedAcadVersion=$versions[$CadVersion];TargetFramework=$framework}
[IO.File]::WriteAllText((Join-Path $destinationPath 'harness.json'),($config | ConvertTo-Json),$encoding)
[pscustomobject]@{ProjectPath=(Join-Path $destinationPath "$Name.csproj");TargetFramework=$framework;Scope='api-smoke + fixture-command-smoke'}
