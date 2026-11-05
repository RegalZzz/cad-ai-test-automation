#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunDirectory,[switch]$LoadOnce,[switch]$ApproveAlways)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'CadTest.Common.ps1')
$root = (Resolve-Path -LiteralPath $RunDirectory).Path
$run = Read-CadJson (Join-Path $root 'run.json')
if ([bool]$LoadOnce -eq [bool]$ApproveAlways) { throw 'Specify exactly one LoadOnce or ApproveAlways action.' }
if ($ApproveAlways -and -not $run.AutoTrustRunnerRequested) { throw 'Persistent approval was not requested for this run.' }
if ($LoadOnce -and -not $run.AutoLoadRunnerRequested) { throw 'Load-once approval was not requested for this run.' }
if ($run.State -ne 'Launched' -or $run.Host -ne 'Desktop') { throw 'Only an active Desktop launcher can approve its runner.' }
if (Test-Path -LiteralPath (Join-Path $root 'result.json')) { throw 'Result already exists; no further approval allowed.' }
if ((Get-CadHash $run.TestAssemblyPath) -ne $run.TestAssemblySha256) { throw 'Runner SHA256 changed; refusing approval.' }
if (-not (Get-CadRunProcess $run)) { throw 'Recorded CAD process is not active.' }
if (Test-Path -LiteralPath (Join-Path $root 'started.txt')) { [pscustomobject]@{Status='RunnerAlreadyStarted';ActionInvoked=$false}; return }
$intent = Join-Path $root 'dll-approval.intent.json'
if (Test-Path -LiteralPath $intent) { throw 'A previous approval intent exists. Inspect it instead of repeating an uncertain action.' }
$candidates = @()
foreach ($dialog in @(Get-CadDialogElements $run.ProcessId)) {
    $content = Get-CadElementById $dialog 'ContentText'
    $instruction = Get-CadElementById $dialog 'MainInstruction'
    $always = Get-CadElementById $dialog 'CommandButton_1001'
    $once = Get-CadElementById $dialog 'CommandButton_1002'
    $deny = Get-CadElementById $dialog 'CommandButton_1003'
    if ($null -eq $content -or $null -eq $instruction -or $null -eq $always -or $null -eq $once -or $null -eq $deny) { continue }
    if ($instruction.Current.Name -notmatch '(?i)publisher|\u53d1\u5e03\u8005') { continue }
    if ($always.Current.Name.Replace('&','').Trim() -notmatch '^(?i:Always\s*Load|\u59cb\u7ec8\u52a0\u8f7d|\u603b\u662f\u52a0\u8f7d)$') { continue }
    if ($once.Current.Name.Replace('&','').Trim() -notmatch '^(?i:Load\s*Once|\u52a0\u8f7d\u4e00\u6b21|\u4ec5\u52a0\u8f7d\u4e00\u6b21)$') { continue }
    if (-not (Test-CadDialogDll $content.Current.Name $run.TestAssemblyPath)) { continue }
    $button = if ($ApproveAlways) { $always } else { $once }
    if ($button.Current.IsEnabled) { $candidates += [pscustomobject]@{Dialog=$dialog;Button=$button;Content=$content.Current.Name} }
}
if ($candidates.Count -eq 0) { [pscustomobject]@{Status='NoMatchingLoadDialog';ActionInvoked=$false}; return }
if ($candidates.Count -ne 1) { throw 'Ambiguous matching dialogs; no action taken.' }
$chosen = $candidates[0]
if ((Read-CadJson (Join-Path $root 'run.json')).State -ne 'Launched' -or -not (Get-CadRunProcess $run) -or (Get-CadHash $run.TestAssemblyPath) -ne $run.TestAssemblySha256) { throw 'Run changed before approval.' }
$dialogHandle = [IntPtr]$chosen.Dialog.Current.NativeWindowHandle
$buttonHandle = [IntPtr]$chosen.Button.Current.NativeWindowHandle
if ($dialogHandle -eq [IntPtr]::Zero -or $buttonHandle -eq [IntPtr]::Zero) { throw 'Observed native dialog/button handles are required.' }
if (-not ('CadTestNativeButton' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CadTestNativeButton {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
    [DllImport("user32.dll")] public static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr result);
}
'@
}
$nativePid = [uint32]0
[void][CadTestNativeButton]::GetWindowThreadProcessId($buttonHandle,[ref]$nativePid)
if ($nativePid -ne $run.ProcessId -or -not [CadTestNativeButton]::IsChild($dialogHandle,$buttonHandle) -or -not [CadTestNativeButton]::IsWindowEnabled($buttonHandle)) { throw 'Native button identity/ownership changed.' }
$record = [ordered]@{Status='IntentRecorded';ActionInvoked=$false;Method='BM_CLICK';PersistentTrustRequested=[bool]$ApproveAlways;ProcessId=$run.ProcessId;AssemblyPath=$run.TestAssemblyPath;Sha256=$run.TestAssemblySha256;Title=$chosen.Dialog.Current.Name;Button=$chosen.Button.Current.Name;AutomationId=$chosen.Button.Current.AutomationId;DialogHandle=$dialogHandle.ToInt64();ButtonHandle=$buttonHandle.ToInt64();Utc=[DateTime]::UtcNow.ToString('o')}
$stream = [IO.File]::Open($intent,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $bytes=[Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json)); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
try {
    # On the verified CAD 2020 dialog InvokePattern returned without dismissing it.
    # Send one native BM_CLICK to the freshly observed, ownership-checked button.
    [void][CadTestNativeButton]::SetForegroundWindow($dialogHandle)
    $messageResult = [IntPtr]::Zero
    $sent = [CadTestNativeButton]::SendMessageTimeout($buttonHandle,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero,2,5000,[ref]$messageResult)
    if ($sent -eq [IntPtr]::Zero) { throw 'Native button message timed out or failed; outcome unknown.' }
    $record.Status='Invoked'; $record.ActionInvoked=$true
} catch {
    $record.Status='InvocationOutcomeUnknown'; $record.ActionInvoked=$true
    Write-CadJson (Join-Path $root 'dll-approval.action.json') $record
    throw
}
Write-CadJson (Join-Path $root 'dll-approval.action.json') $record
[pscustomobject]$record
