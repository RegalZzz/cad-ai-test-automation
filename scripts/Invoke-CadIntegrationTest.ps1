#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$CadInstallDir,
    [string]$DrawingPath,
    [string]$TemplatePath,
    [string[]]$FixturePath = @(),
    [ValidateSet('Desktop','CoreConsole')][string]$HostMode = 'Desktop',
    [string]$TestRoot,
    [ValidateRange(10,86400)][int]$TimeoutSeconds = 300,
    [switch]$PrepareOnly,
    [switch]$AutoLoadRunner,
    [switch]$AutoTrustRunner
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CadTest.Common.ps1')
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$projectRoot = Split-Path -Parent $project
$config = Read-CadJson (Join-Path $projectRoot 'harness.json')
if ($config.SchemaVersion -ne 1 -or $config.AssemblyName -notmatch '^[A-Za-z][A-Za-z0-9_]{0,79}$') { throw 'Invalid harness configuration.' }
$versions = @{2020='23.1';2021='24.0';2022='24.1';2023='24.2';2024='24.3';2025='25.0';2026='25.1'}
if (-not $versions.ContainsKey([int]$config.CadVersion) -or $versions[[int]$config.CadVersion] -ne $config.ExpectedAcadVersion) { throw 'Invalid CAD version mapping.' }
$cadDirectory = (Resolve-Path -LiteralPath $CadInstallDir).Path
$exe = if ($HostMode -eq 'Desktop') { 'acad.exe' } else { 'accoreconsole.exe' }
foreach ($file in @($exe,'accoremgd.dll','acdbmgd.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $cadDirectory $file) -PathType Leaf)) { throw "Missing CAD file: $file" }
}
$apiVersion = (Get-Item -LiteralPath (Join-Path $cadDirectory 'accoremgd.dll')).VersionInfo.FileVersion
if (-not $apiVersion.StartsWith($config.ExpectedAcadVersion + '.')) { throw 'Installed API does not match harness year.' }
if ([bool]$DrawingPath -eq [bool]$TemplatePath) { throw 'Supply exactly one DrawingPath (.dwg) or TemplatePath (.dwt).' }
if ($HostMode -eq 'CoreConsole' -and $TemplatePath) { throw 'CoreConsole requires a DWG, not a DWT. Generate a dedicated drawing with Desktop first.' }
if ($AutoLoadRunner -and $AutoTrustRunner) { throw 'Choose load-once or always-load, not both.' }
if ($HostMode -eq 'CoreConsole' -and ($AutoLoadRunner -or $AutoTrustRunner)) { throw 'Automatic dialog approval is only for Desktop.' }
$inputKind = if ($DrawingPath) { 'Drawing' } else { 'Template' }
$source = if ($DrawingPath) { (Resolve-Path -LiteralPath $DrawingPath).Path } else { (Resolve-Path -LiteralPath $TemplatePath).Path }
$ext = if ($DrawingPath) { '.dwg' } else { '.dwt' }
if ([IO.Path]::GetExtension($source) -ine $ext -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Input must be a $ext file." }
$fixtures = @(); $names = @{}
foreach ($path in $FixturePath) {
    $file = Get-Item -LiteralPath $path
    if ($file.PSIsContainer -or $names.ContainsKey($file.Name)) { throw 'Fixtures must be files with unique names.' }
    $names[$file.Name] = $true; $fixtures += $file
}
if (-not $TestRoot) { $TestRoot = Join-Path $projectRoot '.local\cad-tests' }
$runRoot = Join-Path ([IO.Path]::GetFullPath($TestRoot)) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$runPath = Join-Path $runRoot 'run.json'
$run = [ordered]@{
    SchemaVersion=1;RunId=(Split-Path $runRoot -Leaf);State='Preparing';Host=$HostMode
    ExpectedYear=[int]$config.CadVersion;ExpectedAcadVersion=$config.ExpectedAcadVersion
    PowerShellVersion=$PSVersionTable.PSVersion.ToString();PowerShellEdition=$PSVersionTable.PSEdition
    ExecutablePath=(Join-Path $cadDirectory $exe);InputKind=$inputKind;DrawingPath=(Join-Path $runRoot ('Drawing'+$ext))
    TestAssemblyPath=(Join-Path $runRoot "bin\$($config.AssemblyName).dll");TestAssemblySha256='';BinaryFiles=@();InputFiles=@()
    ProcessId=0;ProcessStartedUtc='';AutoLoadRunnerRequested=[bool]$AutoLoadRunner;AutoTrustRunnerRequested=[bool]$AutoTrustRunner;LauncherError=''
}
Write-CadJson $runPath $run
Write-Host "Run directory: $runRoot"
$process = $null; $mutex = $null; $taken = $false; $marker = $null
try {
    if (-not $PrepareOnly) {
        $mutex = [Threading.Mutex]::new($false,'Local\CadAiTestAutomation')
        try { $taken = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $taken = $true }
        if (-not $taken) { throw 'Another CAD test launcher is active.' }
        $markerRoot = Join-Path $env:LOCALAPPDATA 'cad-ai-test-automation'
        New-Item -ItemType Directory -Path $markerRoot -Force | Out-Null
        $marker = Join-Path $markerRoot 'active.json'
        if (Test-Path -LiteralPath $marker) {
            $active = Read-CadJson $marker
            if (Get-CadRunProcess $active) { throw "Previous CAD test process is active; inspect $($active.RunDirectory)." }
        }
    }
    $binaryRoot = Join-Path $runRoot 'bin'
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $build = @(& (Get-Command dotnet -ErrorAction Stop).Source build $project -c Release --output $binaryRoot "-p:CadInstallDir=$cadDirectory" "-p:CadHost=$HostMode" 2>&1)
        $buildExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    [IO.File]::WriteAllLines((Join-Path $runRoot 'build.log'),[string[]]$build,[Text.UTF8Encoding]::new($false))
    if ($buildExit -ne 0) { throw "Build failed. See $runRoot\build.log" }
    if (-not (Test-Path -LiteralPath $run.TestAssemblyPath)) { throw 'Runner assembly not found.' }
    foreach ($file in Get-ChildItem -LiteralPath $binaryRoot -File) {
        if ($file.Name -imatch '^(AcMgd|AcDbMgd|AcCoreMgd)\.dll$') { throw 'Autodesk API DLLs must have Private=False; do not redistribute them.' }
        $run.BinaryFiles += [pscustomobject]@{Path=$file.FullName;Sha256=(Get-CadHash $file.FullName)}
    }
    $run.TestAssemblySha256 = Get-CadHash $run.TestAssemblyPath
    $pairs = @([pscustomobject]@{Source=$source;Copy=$run.DrawingPath})
    New-Item -ItemType Directory -Path (Join-Path $runRoot 'inputs') | Out-Null
    foreach ($fixture in $fixtures) { $pairs += [pscustomobject]@{Source=$fixture.FullName;Copy=(Join-Path $runRoot "inputs\$($fixture.Name)")} }
    foreach ($pair in $pairs) {
        $hash = Get-CadHash $pair.Source
        Copy-Item -LiteralPath $pair.Source -Destination $pair.Copy
        if ((Get-CadHash $pair.Copy) -ne $hash) { throw 'Input changed during copying.' }
        $run.InputFiles += [pscustomobject]@{Source=$pair.Source;Copy=$pair.Copy;Sha256=$hash}
    }
    # ASCII script; Unicode DLL paths come from the child environment, not SCR encoding.
    # Do not disable SECURELOAD, alter TRUSTEDPATHS, or install a persistent bundle.
    $script = "(command ""_NETLOAD"" (getenv ""CAD_TEST_ASSEMBLY""))`r`nCADTEST_RUN`r`nCADTEST_FINISH`r`n"
    if ($HostMode -eq 'CoreConsole') { $script += "_.QUIT`r`n_N`r`n" }
    $scriptPath = Join-Path $runRoot 'run.scr'
    [IO.File]::WriteAllText($scriptPath,$script,[Text.Encoding]::ASCII)
    $run.State = 'Prepared'; Write-CadJson $runPath $run
    if ($PrepareOnly) { [pscustomobject]@{Status='PREPARED';RunDirectory=$runRoot;CadStarted=$false}; return }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $run.ExecutablePath; $start.UseShellExecute = $false; $start.WorkingDirectory = $runRoot
    # Desktop is deliberately interactive so the operator can inspect prompts.
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
    if ($HostMode -eq 'Desktop') {
        $inputArgument = if ($TemplatePath) { '/t "{0}"' -f $run.DrawingPath } else { '"{0}"' -f $run.DrawingPath }
        $start.Arguments = '/nologo {0} /b "{1}"' -f $inputArgument,$scriptPath
    } else {
        $start.Arguments = '/i "{0}" /s "{1}"' -f $run.DrawingPath,$scriptPath
        $start.CreateNoWindow = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::Unicode
        $start.StandardErrorEncoding = [Text.Encoding]::Unicode
    }
    $start.EnvironmentVariables['CAD_TEST_RUN_DIRECTORY']=$runRoot
    $start.EnvironmentVariables['CAD_TEST_RUN_ID']=$run.RunId
    $start.EnvironmentVariables['CAD_TEST_ASSEMBLY']=$run.TestAssemblyPath
    $process = [Diagnostics.Process]::Start($start)
    if ($HostMode -eq 'CoreConsole') {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    }
    $run.ProcessId=$process.Id; $run.ProcessStartedUtc=$process.StartTime.ToUniversalTime().ToString('o')
    $run.State='Launched'; Write-CadJson $runPath $run
    $activeRun = [ordered]@{ProcessId=$run.ProcessId;ProcessStartedUtc=$run.ProcessStartedUtc;Host=$HostMode;ExecutablePath=$run.ExecutablePath;RunDirectory=$runRoot;RunId=$run.RunId}
    Write-CadJson $marker $activeRun
    Write-Host "CAD PID: $($process.Id)"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $dllAction = if ($AutoTrustRunner) { 'Always' } elseif ($AutoLoadRunner) { 'Once' } else { 'None' }
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $acted = $false
        if ($HostMode -eq 'Desktop') {
            # Dialogs can appear in sequence: runner, dependencies, and finally
            # demand-loaded plug-ins while the drawing is opening. Poll until CAD
            # exits so every matching prompt is handled, including post-open ones.
            $handled = & (Join-Path $PSScriptRoot 'Handle-CadTestDialogs.ps1') -RunDirectory $runRoot -DllAction $dllAction
            $acted = $handled.ActionInvoked
        }
        # Drain consecutive font/DLL prompts immediately; only idle scans wait.
        if (-not $acted) { Start-Sleep -Milliseconds 100 }
    }
    if (-not $process.HasExited) { $run.State='TimedOut'; throw "Timed out. CAD PID $($process.Id) and evidence preserved. Handle the observed prompt, then read this same run with Read-CadTestResult.ps1." }
    if ($HostMode -eq 'CoreConsole') {
        [IO.File]::WriteAllText((Join-Path $runRoot 'console.stdout.log'),$stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $runRoot 'console.stderr.log'),$stderr.GetAwaiter().GetResult())
    }
    $run.State='ProcessExited'; $run['ProcessExitCode']=$process.ExitCode; Write-CadJson $runPath $run
    if ($process.ExitCode -ne 0) { throw "CAD exited with code $($process.ExitCode)." }
    & (Join-Path $PSScriptRoot 'Read-CadTestResult.ps1') -RunDirectory $runRoot
} catch {
    if ($run.State -ne 'TimedOut') { $run.State='LauncherFailed' }
    $run.LauncherError=$_.Exception.Message; Write-CadJson $runPath $run; throw
} finally {
    if ($marker -and (Test-Path -LiteralPath $marker)) {
        $active = Read-CadJson $marker
        if ($active.RunId -eq $run.RunId -and ($null -eq $process -or $process.HasExited)) { Remove-Item -LiteralPath $marker }
    }
    if ($taken) { $mutex.ReleaseMutex() }; if ($mutex) { $mutex.Dispose() }
}
