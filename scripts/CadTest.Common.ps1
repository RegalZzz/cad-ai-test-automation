#Requires -Version 5.1
# Shared evidence helpers; dot source from scripts in this directory.
function Write-CadJson($Path, $Value) {
    $temp = $Path + '.tmp'
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $Path) {
        $backup = $Path + '.previous'
        [IO.File]::Replace($temp, $Path, $backup)
        [IO.File]::Delete($backup)
    } else { [IO.File]::Move($temp, $Path) }
}
function Read-CadJson($Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Get-CadRunProcess($Run) {
    if ([int]$Run.ProcessId -le 0) { return $null }
    $candidate = Get-Process -Id $Run.ProcessId -ErrorAction SilentlyContinue
    if (-not $candidate) { return $null }
    $stamp = [DateTimeOffset]$Run.ProcessStartedUtc
    if ($candidate.StartTime.ToUniversalTime().Ticks -ne $stamp.UtcDateTime.Ticks) { return $null }
    $expected = if ($Run.Host -eq 'CoreConsole') { 'accoreconsole' } else { 'acad' }
    if ($candidate.ProcessName -ine $expected) { throw 'Recorded process is not the expected CAD host.' }
    if ($candidate.Path -ine $Run.ExecutablePath) { throw 'Recorded CAD executable path mismatch.' }
    return $candidate
}
function Get-CadHash($Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-CadDialogElements($ProcessId) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty,[int]$ProcessId)
    $roots = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$condition)
    $contentCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'ContentText')
    foreach ($window in $roots) {
        # The CAD provider does not reliably return nested dialogs from class-name queries.
        # Discover the observed ContentText element and walk to its actual dialog ancestor.
        $seen = @{}
        foreach ($content in $window.FindAll([Windows.Automation.TreeScope]::Descendants,$contentCondition)) {
            $dialog = [Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($content)
            if ($dialog -and $dialog.Current.ClassName -eq '#32770' -and $dialog.Current.ProcessId -eq [int]$ProcessId) {
                $key = [string]$dialog.Current.NativeWindowHandle
                if (-not $seen.ContainsKey($key)) { $seen[$key]=$true; $dialog }
            }
        }
    }
}
function Get-CadElementById($Root, $Id) {
    $Root.FindFirst([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,[string]$Id))
}
function Test-CadDialogDll($Text, $AssemblyPath) {
    # CAD uses separate Name and Location fields. Never decode a path's \n as newline.
    $lines = [regex]::Split($Text,'(?:\r?\n|\\r\\n)')
    $names = @(); $locations = @()
    foreach ($line in $lines) {
        if ($line -match '^(?:Name|\u540d\u79f0)\s*[:\uFF1A]\s*(.+?)\s*$') { $names += $Matches[1] }
        if ($line -match '^(?:Location|\u4f4d\u7f6e)\s*[:\uFF1A]\s*(.+?)\s*$') { $locations += $Matches[1].Replace('\\','\') }
    }
    return $names.Count -eq 1 -and $locations.Count -eq 1 -and $names[0] -ieq [IO.Path]::GetFileName($AssemblyPath) -and $locations[0].TrimEnd('\') -ieq [IO.Path]::GetDirectoryName($AssemblyPath).TrimEnd('\')
}
