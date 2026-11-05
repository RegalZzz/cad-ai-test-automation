#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [ValidateSet('None','Once','Always')][string]$DllAction='None'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CadTest.Common.ps1')
$root = (Resolve-Path -LiteralPath $RunDirectory).Path
$runPath = Join-Path $root 'run.json'
$run = Read-CadJson $runPath
if ($DllAction -eq 'Always' -and -not $run.AutoTrustRunnerRequested) { throw 'Persistent approval was not requested for this run.' }
if ($DllAction -eq 'Once' -and -not $run.AutoLoadRunnerRequested) { throw 'Load-once approval was not requested for this run.' }
if ($run.State -ne 'Launched' -or $run.Host -ne 'Desktop') { throw 'Only an active Desktop launcher can handle dialogs.' }
if (-not (Get-CadRunProcess $run)) { [pscustomobject]@{Status='ProcessNotRunning';ActionInvoked=$false}; return }

$mutex = [Threading.Mutex]::new($false,('Local\CadTestDialogs_' + [string]$run.ProcessId))
$taken = $false
try {
    try { $taken = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $taken=$true }
    if (-not $taken) { [pscustomobject]@{Status='HandlerBusy';ActionInvoked=$false}; return }
    $dialogs = @(Get-CadDialogElements $run.ProcessId)
    $pendingPath = Join-Path $root 'dialog-action.pending.json'
    if (Test-Path -LiteralPath $pendingPath) {
        $pending = Read-CadJson $pendingPath
        if ($pending.Status -ne 'Invoked') { throw 'Previous dialog action outcome is unknown; inspect its intent/action evidence before continuing.' }
        $unchanged = @($dialogs | Where-Object { (Get-CadDialogFingerprint $_) -eq $pending.Fingerprint })
        if ($unchanged.Count -gt 0) {
            if (([DateTime]::UtcNow - ([DateTimeOffset]$pending.Utc).UtcDateTime).TotalSeconds -gt 10) {
                throw 'A handled dialog did not close or advance within 10 seconds; inspect the original run.'
            }
            [pscustomobject]@{Status='AwaitingDialogClose';ActionInvoked=$false}; return
        }
        Remove-Item -LiteralPath $pendingPath
    }
    foreach ($dialog in $dialogs) {
        $plan = Get-CadDialogPlan $dialog $DllAction
        if (-not $plan) { continue }
        # Recheck run identity immediately before touching a control. started.txt
        # and result.json intentionally do not stop post-open prompt handling.
        if ((Read-CadJson $runPath).State -ne 'Launched') { throw 'Run changed before dialog action.' }
        if (-not (Get-CadRunProcess $run)) { [pscustomobject]@{Status='ProcessNotRunning';ActionInvoked=$false}; return }
        if ((Get-CadHash $run.TestAssemblyPath) -ne $run.TestAssemblySha256) { throw 'Runner SHA256 changed; refusing dialog action.' }
        [CadTestDialogs]::Validate($dialog.Handle,$plan.Confirm.Handle,[int]$run.ProcessId)
        $evidenceRoot = Join-Path $root 'dialog-actions'
        New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        $actionId = [Guid]::NewGuid().ToString('N')
        $intentPath = Join-Path $evidenceRoot ($actionId + '.intent.json')
        $record = [ordered]@{
            Status='IntentRecorded';ActionInvoked=$false;Action=$plan.Action;ProcessId=$run.ProcessId
            Fingerprint=(Get-CadDialogFingerprint $dialog);Title=$dialog.Title;DialogHandle=$dialog.Handle
            Button=$plan.Confirm.Name;ButtonHandle=$plan.Confirm.Handle;ButtonId=$plan.Confirm.Id
            Content=@($dialog.Controls | ForEach-Object { $_.Name });DllAction=$DllAction;Utc=[DateTime]::UtcNow.ToString('o')
        }
        $stream = [IO.File]::Open($intentPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=[Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Depth 8)); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
        Write-CadJson $pendingPath $record
        try {
            $detail = Invoke-CadDialogPlan $dialog $plan $run.ProcessId
            $record.Status='Invoked'; $record.ActionInvoked=$true; $record['Detail']=$detail
        } catch {
            $record.Status='InvocationOutcomeUnknown'; $record.ActionInvoked=$true; $record['Error']=$_.Exception.Message
            Write-CadJson (Join-Path $evidenceRoot ($actionId + '.action.json')) $record
            Write-CadJson $pendingPath $record
            throw
        }
        Write-CadJson (Join-Path $evidenceRoot ($actionId + '.action.json')) $record
        Write-CadJson $pendingPath $record
        [pscustomobject]$record
        return # Re-discover controls before handling the next, possibly new prompt.
    }
    if ($dialogs.Count -gt 0) {
        Write-CadJson (Join-Path $root 'dialogs.latest.json') ([pscustomobject]@{Status='Observed';ProcessId=$run.ProcessId;ObservedUtc=[DateTime]::UtcNow.ToString('o');Windows=$dialogs})
    }
    [pscustomobject]@{Status='NoMatchingDialogs';ActionInvoked=$false}
} finally {
    if ($taken) { $mutex.ReleaseMutex() }; $mutex.Dispose()
}
