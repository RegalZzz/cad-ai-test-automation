#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\CadTest.Common.ps1')
$testRoot = Join-Path $repo ('.local\dialog-checks\'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$evidence = Join-Path $testRoot 'events.txt'
$hostScript = Join-Path $PSScriptRoot 'fixtures\Show-CadDialogFixture.ps1'
$fixtureExe=Join-Path $testRoot 'acad.exe'
$frameworkCompiler=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $frameworkCompiler -NoProfile -ExecutionPolicy Bypass -File $hostScript -BuildExecutable $fixtureExe
if ($LASTEXITCODE -ne 0) { throw 'Synthetic fixture compilation failed.' }
$process = Start-Process -FilePath $fixtureExe -WindowStyle Hidden -PassThru -ArgumentList ('"{0}"' -f $evidence)
$checks = 0
function Check($Condition,$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++; Write-Host "PASS $Message"
}
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath ($evidence+'.ready')) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) { Start-Sleep -Milliseconds 50 }
    Check (Test-Path -LiteralPath ($evidence+'.ready')) 'Native fixture host started'
    $runner=Join-Path $testRoot 'Runner.dll'
    [IO.File]::WriteAllText($runner,'SYNTHETIC BYTES; NOT A MANAGED ASSEMBLY')
    $run=[ordered]@{State='Launched';Host='Desktop';ProcessId=$process.Id;ProcessStartedUtc=$process.StartTime.ToUniversalTime().ToString('o');ExecutablePath=$fixtureExe;AutoTrustRunnerRequested=$true;AutoLoadRunnerRequested=$false;TestAssemblyPath=$runner;TestAssemblySha256=(Get-CadHash $runner)}
    Write-CadJson (Join-Path $testRoot 'run.json') $run
    $handler=Join-Path $repo 'scripts\Handle-CadTestDialogs.ps1'
    Initialize-CadDialogNative
    $fingerprints=@(); $handles=@(); $actions=@(); $timer=[Diagnostics.Stopwatch]::StartNew()
    for ($index=0; $index -lt 8; $index++) {
        $dialogs=@(Get-CadDialogElements $process.Id)
        Check ($dialogs.Count -eq 1) 'Discover enabled native dialog in another process'
        $dialog=$dialogs[0]; $fingerprints+=Get-CadDialogFingerprint $dialog; $handles+=$dialog.Handle
        $dllAction=if ($index -ge 5) { 'None' } else { 'Always' }
        $plan=Get-CadDialogPlan $dialog $dllAction
        Check ($null -ne $plan) 'Recognize next known prompt'
        if ($index -lt 2) {
            Check ($null -eq (Get-CadDialogPlan $dialog None)) 'No DLL action without trust option'
            Check ((Get-CadDialogPlan $dialog Once).Confirm.Id -eq 1002) 'Explicit load-once compatibility'
        }
        if ($index -ge 5) {
            Check ($plan.Kind -eq 'ShapeFile' -and $plan.Confirm.Id -eq 2) 'Select Cancel for the changing shape filename without DLL approval'
        }
        $record=& $handler -RunDirectory $testRoot -DllAction $dllAction
        Check ($record.Status -eq 'Invoked') 'Handler sends one recorded dialog action'
        $detail=$record.Detail
        if ($index -ge 3 -and $index -lt 5) { Check ($detail.SelectedIndex -eq 1 -and $detail.SelectedFont -eq 'big2.shx') 'Read back second Big Font selection' }
        if ($index -ge 5) { Check ($record.Action -eq 'CancelShapeFileSelection' -and $detail.Method -eq 'BM_CLICK') 'Record native Cancel button action for each shape-file prompt' }
        $actions+=$plan.Action
        if ($index -eq 0) {
            [IO.File]::WriteAllText((Join-Path $testRoot 'started.txt'),'SYNTHETIC runner started')
            [IO.File]::WriteAllText((Join-Path $testRoot 'result.json'),'{}')
        }
    }
    $timer.Stop()
    $events=@(Get-Content -LiteralPath $evidence)
    Check ($events.Count -eq 8) 'Each prompt handled exactly once'
    Check ($events[0] -eq 'Dll|0|1001' -and $events[1] -eq 'Dll|1|1001') 'Always Load clicked for runner and unrelated dependency'
    Check (@(Get-ChildItem (Join-Path $testRoot 'dialog-actions') -Filter '*.action.json').Count -eq 8) 'All prompts logged, including prompts after started.txt and result.json'
    Check ($events[2] -eq 'Proxy|1') 'Show Proxy Graphics checked before confirmation'
    Check ($events[3] -eq 'Font|3|0|1|1' -and $events[4] -eq 'Font|4|0|1|1') 'Consecutive fonts use second right-list item, notify CAD, and leave left list alone'
    Check ($events[5] -eq 'ShapeFile|5|2' -and $events[6] -eq 'ShapeFile|6|2' -and $events[7] -eq 'ShapeFile|7|2') 'Consecutive Chinese and English shape-file prompts receive Cancel, never Open'
    Check (@($handles | Select-Object -Unique).Count -eq 1) 'Fixture reuses the same dialog HWND'
    Check (@($fingerprints | Select-Object -Unique).Count -eq 8) 'Updated DLL/font/shape-file content is treated as a new prompt despite HWND reuse'
    $unknown=@(Get-CadDialogElements $process.Id)[0]
    Check ($null -eq (Get-CadDialogPlan $unknown Always)) 'Unknown save dialog with Cancel and an SHX filename is left untouched'
    $notShape=[pscustomobject]@{Title='Open';Controls=$unknown.Controls}
    Check ($null -eq (Get-CadDialogPlan $notShape None)) 'Ordinary file picker with an SHX filename is left untouched'
    $withoutCancel=[pscustomobject]@{Title=$dialog.Title;Controls=@($dialog.Controls | Where-Object { $_.Id -ne 2 })}
    Check ($null -eq (Get-CadDialogPlan $withoutCancel None)) 'Shape-file prompt without an enabled Cancel button is left untouched'
    $disabledCancel=[pscustomobject]@{Title=$dialog.Title;Controls=@([pscustomobject]@{Name='Cancel';ClassName='Button';Id=2;Enabled=$false})}
    Check ($null -eq (Get-CadDialogPlan $disabledCancel None)) 'Disabled shape-file Cancel button is left untouched'
    Check ((& $handler -RunDirectory $testRoot -DllAction Always).ActionInvoked -eq $false) 'Handler leaves unknown confirmation buttons untouched'
    $pendingPath=Join-Path $testRoot 'dialog-action.pending.json'
    $pending=@{Status='Invoked';Fingerprint=(Get-CadDialogFingerprint $unknown);Utc=[DateTime]::UtcNow.ToString('o')}
    Write-CadJson $pendingPath $pending
    Check ((& $handler -RunDirectory $testRoot -DllAction Always).Status -eq 'AwaitingDialogClose') 'A live handled dialog is not clicked twice'
    $pending.Utc=[DateTime]::UtcNow.AddSeconds(-11).ToString('o'); Write-CadJson $pendingPath $pending
    $rejected=$false
    try { & $handler -RunDirectory $testRoot -DllAction Always | Out-Null } catch { $rejected=$_.Exception.Message -match 'did not close' }
    Check $rejected 'A stuck dialog stops without repeated clicks'
    $pending.Status='IntentRecorded'; Write-CadJson $pendingPath $pending
    $rejected=$false
    try { & $handler -RunDirectory $testRoot -DllAction Always | Out-Null } catch { $rejected=$_.Exception.Message -match 'outcome is unknown' }
    Check $rejected 'Uncertain actions cannot be automatically retried'
    $wrongPid=$process.Id+1
    $rejected=$false
    try { Invoke-CadDialogPlan $unknown ([pscustomobject]@{Kind='Dll';Confirm=$unknown.Controls[0]}) $wrongPid | Out-Null } catch { $rejected=$_.Exception.Message -match 'ownership' }
    Check $rejected 'Native ownership check rejects a different process'
    [pscustomobject]@{Status='PASS';Checks=$checks;PowerShell=$PSVersionTable.PSVersion.ToString();DialogCount=$events.Count;DialogMilliseconds=$timer.ElapsedMilliseconds;Evidence=$testRoot;Scope='synthetic native Windows controls; no AutoCAD execution'}
} finally {
    if (-not $process.HasExited) {
        [void]$process.CloseMainWindow()
        if (-not $process.WaitForExit(3000)) { Stop-Process -Id $process.Id } # Only this disposable fixture process.
    }
}
