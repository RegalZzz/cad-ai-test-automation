#Requires -Version 5.1
# Tool/evidence tests only. Synthetic evidence does not prove execution in AutoCAD.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\CadTest.Common.ps1')
$testDirectory = Join-Path $repo ('.local\package-checks\'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$script:checks=0
function Check($Condition,$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++; Write-Host "PASS $Message"
}
function Reject($Action,$Expected,$Message) {
    $rejected=$false
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Expected) { throw }; $rejected=$true }
    Check $rejected $Message
}
foreach ($file in Get-ChildItem (Join-Path $repo 'scripts') -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) ("Parse "+$file.Name)
}
$generated = Join-Path $testDirectory 'Generated'
$newScript = Join-Path $repo 'scripts\New-CadTestHarness.ps1'
& $newScript -Destination $generated -Name CheckHarness -CadVersion 2020 | Out-Null
Check ((Read-CadJson (Join-Path $generated 'harness.json')).TargetFramework -eq 'net472') 'AutoCAD 2020 framework'
Reject { & $newScript -Destination $generated -Name CheckHarness -CadVersion 2020 } 'already exists' 'Refuse overwrite'
$modern = Join-Path $testDirectory 'Modern'
& $newScript -Destination $modern -Name ModernHarness -CadVersion 2025 | Out-Null
Check ((Read-CadJson (Join-Path $modern 'harness.json')).TargetFramework -eq 'net8.0-windows') '2025 framework generation only'
Check (-not ((Get-ChildItem $generated -File | Get-Content -Raw) -match '__HARNESS_NAME__|__TARGET_FRAMEWORK__')) 'No template placeholders'
$dllPath = 'C:\new\north folder\Harness.dll'
$escaped = 'Name: Harness.dll\r\nPublisher: Unknown\r\nLocation: C:\\new\\north folder\r\nIssuer: None'
Check (Test-CadDialogDll $escaped $dllPath) 'Escaped CRLF and backslashes match exact fields'
Check (Test-CadDialogDll "Name: Harness.dll`r`nLocation: C:\new\north folder" $dllPath) 'Actual CRLF matches exact fields'
Check (-not (Test-CadDialogDll $escaped 'C:\new\north folder2\Harness.dll')) 'Reject directory prefix collision'
Check (-not (Test-CadDialogDll $escaped 'C:\new\north folder\Other.dll')) 'Reject other DLL'
Check (-not (Test-CadDialogDll ($escaped+'\r\nName: Harness.dll') $dllPath)) 'Reject ambiguous fields'
$observed = Read-CadJson (Join-Path $PSScriptRoot 'fixtures\load-dialog-2020.zh-CN.json')
Check (Test-CadDialogDll $observed.ContentText $observed.AssemblyPath) 'Observed Chinese dialog shape with Unicode and escaped paths'
$fixtureRoot = Join-Path $testDirectory 'Evidence'
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
foreach ($name in @('source.dwg','Drawing.dwg','Runner.dll')) { [IO.File]::WriteAllText((Join-Path $fixtureRoot $name),'SYNTHETIC TOOL TEST; NOT A CAD FILE') }
$runner = Join-Path $fixtureRoot 'Runner.dll'; $source=Join-Path $fixtureRoot 'source.dwg'; $copy=Join-Path $fixtureRoot 'Drawing.dwg'
$runnerHash=Get-CadHash $runner; $inputHash=Get-CadHash $source
$baseRun=[ordered]@{
    SchemaVersion=1;RunId='synthetic';State='ProcessExited';Host='Desktop';ExpectedAcadVersion='23.1';ProcessId=2147483647;ProcessStartedUtc='2026-11-05T00:00:00Z'
    ExecutablePath='C:\SYNTHETIC\acad.exe';DrawingPath=$copy;TestAssemblyPath=$runner;TestAssemblySha256=$runnerHash;ProcessExitCode=0
    BinaryFiles=@(@{Path=$runner;Sha256=$runnerHash});InputFiles=@(@{Source=$source;Copy=$copy;Sha256=$inputHash})
}
$baseResult=[ordered]@{
    SchemaVersion=1;RunId='synthetic';ProcessId=2147483647;Host='Desktop';AcadVersion='23.1s (LMS Tech)';HostBuild='SYNTHETIC';Scope='synthetic evidence checks only'
    Complete=$true;Success=$true;ServiceTransactionAborted=$true;ModelHandleSetRestored=$true;ClosedWithoutSaving=$true;DiscardOnProcessExitRequested=$false
    AssertionCount=2;ScenarioAssertionCount=1;Failures=@();CommandsCompleted=@();PluginAssemblies=@(@{Path=$runner;Sha256=$runnerHash})
    DrawingPath=$copy;TestAssemblyPath=$runner;TestAssemblySha256=$runnerHash
}
$runFile=Join-Path $fixtureRoot 'run.json'; $resultFile=Join-Path $fixtureRoot 'result.json'
function Reset-Evidence {
    Write-CadJson $runFile $baseRun; Write-CadJson $resultFile $baseResult
    [IO.File]::WriteAllText($source,'SYNTHETIC TOOL TEST; NOT A CAD FILE')
    [IO.File]::WriteAllText($copy,'SYNTHETIC TOOL TEST; NOT A CAD FILE')
    [IO.File]::WriteAllText($runner,'SYNTHETIC TOOL TEST; NOT A CAD FILE')
}
$reader=Join-Path $repo 'scripts\Read-CadTestResult.ps1'
Reset-Evidence
Check ((& $reader -RunDirectory $fixtureRoot).Status -eq 'PASS') 'Accept internally consistent synthetic evidence'
$cases=@(
    @('RunId','wrong','run/process/schema','Reject wrong run'),
    @('ProcessId',1,'run/process/schema','Reject wrong process'),
    @('Host','CoreConsole','host or version','Reject wrong host'),
    @('AcadVersion','24.0','host or version','Reject wrong CAD version'),
    @('Success',$false,'Failed/incomplete','Reject failed suite'),
    @('Success','true','boolean true','Reject string masquerading as boolean'),
    @('ScenarioAssertionCount',0,'No scenario','Reject infrastructure-only assertions'),
    @('AssertionCount',0,'Missing assertions','Reject zero assertions'),
    @('ServiceTransactionAborted',$false,'service abort','Reject missing service abort'),
    @('ModelHandleSetRestored',$false,'handle-set','Reject failed handle restoration'),
    @('ClosedWithoutSaving',$false,'CloseAndDiscard','Reject missing Desktop closure'),
    @('Scope','','Missing actual test scope','Reject empty scope'),
    @('DrawingPath',$source,'Wrong input','Reject wrong drawing copy'),
    @('TestAssemblyPath',$source,'Wrong loaded runner','Reject wrong loaded DLL path'),
    @('TestAssemblySha256',('0'*64),'SHA256 mismatch','Reject wrong loaded DLL hash')
)
foreach ($case in $cases) {
    Reset-Evidence; $changed=Read-CadJson $resultFile; $changed.($case[0])=$case[1]; Write-CadJson $resultFile $changed
    Reject { & $reader -RunDirectory $fixtureRoot } $case[2] $case[3]
}
Reset-Evidence; $changed=Read-CadJson $runFile; $changed.State='Prepared'; Write-CadJson $runFile $changed
Reject { & $reader -RunDirectory $fixtureRoot } 'Prepared only' 'PrepareOnly cannot pass'
Reset-Evidence; Remove-Item -LiteralPath $resultFile
Reject { & $reader -RunDirectory $fixtureRoot } 'result.json is missing' 'Missing result cannot pass'
Reset-Evidence; [IO.File]::AppendAllText($runner,'changed')
Reject { & $reader -RunDirectory $fixtureRoot } 'SHA256 mismatch' 'Detect staged DLL modification'
Reset-Evidence; [IO.File]::AppendAllText($source,'changed')
Reject { & $reader -RunDirectory $fixtureRoot } 'Input/source hash changed' 'Detect source modification'
Reset-Evidence; [IO.File]::AppendAllText($copy,'changed')
Reject { & $reader -RunDirectory $fixtureRoot } 'Input/source hash changed' 'Detect input-copy modification'
Reset-Evidence; $changed=Read-CadJson $runFile; $changed.ProcessExitCode=1; Write-CadJson $runFile $changed
Reject { & $reader -RunDirectory $fixtureRoot } 'host exit failed' 'Nonzero host exit cannot pass'
Reset-Evidence; $changed=Read-CadJson $runFile; $changed.State='TimedOut'; Write-CadJson $runFile $changed; $originalHash=Get-CadHash $runFile
Check ((& $reader -RunDirectory $fixtureRoot).OriginalLauncherState -eq 'TimedOut') 'Resume reading preserves original timeout state'
Check ((Get-CadHash $runFile) -eq $originalHash) 'Reader does not rewrite run metadata'
Reset-Evidence; $changed=Read-CadJson $runFile; $changed.Host='CoreConsole'; Write-CadJson $runFile $changed
$changed=Read-CadJson $resultFile; $changed.Host='CoreConsole'; $changed.ClosedWithoutSaving=$false; $changed.DiscardOnProcessExitRequested=$true; Write-CadJson $resultFile $changed
Check ((& $reader -RunDirectory $fixtureRoot).Status -eq 'PASS') 'Core discard requires exited process and zero exit code'
$changed=Read-CadJson $runFile; $changed.PSObject.Properties.Remove('ProcessExitCode'); Write-CadJson $runFile $changed
Reject { & $reader -RunDirectory $fixtureRoot } 'recorded zero' 'Core cannot pass without recorded process exit'
Reset-Evidence
$approval=Join-Path $repo 'scripts\Approve-CadTestDll.ps1'
Reject { & $approval -RunDirectory $fixtureRoot } 'exactly one' 'Approval requires a specific action'
$changed=Read-CadJson $runFile; $changed | Add-Member NoteProperty AutoTrustRunnerRequested $false; Write-CadJson $runFile $changed
Reject { & $approval -RunDirectory $fixtureRoot -ApproveAlways } 'not requested' 'Approval requires recorded authorization'
$changed.AutoTrustRunnerRequested=$true; Write-CadJson $runFile $changed
Reject { & $approval -RunDirectory $fixtureRoot -ApproveAlways } 'active Desktop' 'Approval refuses stopped launcher'
[pscustomobject]@{Status='PASS';Checks=$script:checks;PowerShell=$PSVersionTable.PSVersion.ToString();Evidence=$testDirectory;Scope='tool checks; synthetic evidence; no AutoCAD execution'}
