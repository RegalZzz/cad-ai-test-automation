#Requires -Version 5.1
# Native controls avoid scanning CAD's entire UI Automation tree on every poll.
function Initialize-CadDialogNative {
    if ('CadTestDialogs' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class CadTestDialogs {
    public class Control {
        public long Handle; public int Id; public string Name; public string ClassName;
        public bool Enabled; public int Left; public int Top;
    }
    private delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr l);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr l);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr h, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out Rect r);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] private static extern bool IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr result);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="SendMessageTimeoutW")] private static extern IntPtr SendTextMessage(IntPtr h, uint msg, IntPtr w, StringBuilder l, uint flags, uint ms, out IntPtr result);
    public static string ClassName(long handle) {
        var text = new StringBuilder(256); GetClassName(new IntPtr(handle), text, text.Capacity); return text.ToString();
    }
    public static string Text(long handle) {
        var text = new StringBuilder(8192); IntPtr result;
        SendTextMessage(new IntPtr(handle), 0x000D, new IntPtr(text.Capacity), text, 2, 250, out result);
        return text.ToString();
    }
    public static long[] Dialogs(int pid) {
        var found = new HashSet<long>();
        EnumProc visit = delegate(IntPtr h, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(h, out owner);
            if (owner == (uint)pid && IsWindowVisible(h) && IsWindowEnabled(h) && ClassName(h.ToInt64()) == "#32770") found.Add(h.ToInt64());
            return true;
        };
        EnumWindows(delegate(IntPtr h, IntPtr unused) {
            uint owner; GetWindowThreadProcessId(h, out owner);
            if (owner == (uint)pid) { visit(h, IntPtr.Zero); EnumChildWindows(h, visit, IntPtr.Zero); }
            return true;
        }, IntPtr.Zero);
        var result = new long[found.Count]; found.CopyTo(result); return result;
    }
    public static Control[] Controls(long dialog) {
        var found = new List<Control>();
        EnumChildWindows(new IntPtr(dialog), delegate(IntPtr h, IntPtr unused) {
            if (!IsWindowVisible(h)) return true;
            Rect rect; GetWindowRect(h, out rect);
            found.Add(new Control { Handle=h.ToInt64(), Id=GetDlgCtrlID(h), Name=Text(h.ToInt64()), ClassName=ClassName(h.ToInt64()), Enabled=IsWindowEnabled(h), Left=rect.Left, Top=rect.Top });
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }
    public static void Validate(long dialog, long control, int pid) {
        uint dialogPid, controlPid;
        GetWindowThreadProcessId(new IntPtr(dialog), out dialogPid); GetWindowThreadProcessId(new IntPtr(control), out controlPid);
        if (dialogPid != (uint)pid || controlPid != (uint)pid || !IsChild(new IntPtr(dialog),new IntPtr(control)) || !IsWindowEnabled(new IntPtr(control)))
            throw new InvalidOperationException("Native control identity/ownership changed.");
    }
    private static long Message(long handle, uint msg, IntPtr w, IntPtr l) {
        IntPtr result;
        if (SendMessageTimeout(new IntPtr(handle), msg, w, l, 2, 5000, out result) == IntPtr.Zero)
            throw new InvalidOperationException("Native control message failed or timed out; outcome unknown.");
        return result.ToInt64();
    }
    public static void Click(long dialog, long control, int pid) {
        Validate(dialog,control,pid); SetForegroundWindow(new IntPtr(dialog)); Message(control,0x00F5,IntPtr.Zero,IntPtr.Zero);
    }
    public static long Checked(long control) { return Message(control,0x00F0,IntPtr.Zero,IntPtr.Zero); }
    public static long ListCount(long list) { return Message(list,0x018B,IntPtr.Zero,IntPtr.Zero); }
    public static string SelectSecond(long dialog, long list, int pid) {
        Validate(dialog,list,pid);
        if (ListCount(list) < 2) throw new InvalidOperationException("Replacement list has fewer than two fonts.");
        if (Message(list,0x0186,new IntPtr(1),IntPtr.Zero) != 1 || Message(list,0x0188,IntPtr.Zero,IntPtr.Zero) != 1)
            throw new InvalidOperationException("Second replacement font was not selected.");
        // LB_SETCURSEL does not raise LBN_SELCHANGE; notify the owning dialog so
        // AutoCAD updates its style/font model before OK is clicked.
        Message(GetParent(new IntPtr(list)).ToInt64(),0x0111,new IntPtr((1 << 16) | (GetDlgCtrlID(new IntPtr(list)) & 0xffff)),new IntPtr(list));
        long length = Message(list,0x018A,new IntPtr(1),IntPtr.Zero);
        if (length < 0 || length > 8192) return "";
        var text = new StringBuilder((int)length+1); IntPtr result;
        if (SendTextMessage(new IntPtr(list),0x0189,new IntPtr(1),text,2,1000,out result) == IntPtr.Zero) return "";
        return text.ToString();
    }
}
'@
}
function ConvertTo-CadControlName($Name) {
    return ([string]$Name).Replace('&','').Trim() -replace '\s*\([A-Za-z]\)\s*[:：]?\s*$',''
}
function Get-CadDialogElements($ProcessId) {
    Initialize-CadDialogNative
    foreach ($handle in [CadTestDialogs]::Dialogs([int]$ProcessId)) {
        [pscustomobject]@{Handle=$handle;Title=[CadTestDialogs]::Text($handle);Controls=@([CadTestDialogs]::Controls($handle))}
    }
}
function Get-CadDialogFingerprint($Dialog) {
    # Include title and body: CAD can reuse a live window for another missing font
    # or DLL, with the same handles. Such a new prompt must still be processed.
    $shape = @([string]$Dialog.Handle,[string]$Dialog.Title)
    foreach ($control in $Dialog.Controls) { $shape += ('{0}:{1}:{2}' -f $control.Handle,$control.ClassName,$control.Name) }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($shape -join "`n"))))).Replace('-','') } finally { $hash.Dispose() }
}
function Get-CadDialogPlan($Dialog, [ValidateSet('None','Once','Always')]$DllAction='Always') {
    $controls = @($Dialog.Controls | Where-Object { $_.Enabled })
    $buttons = @($controls | Where-Object { $_.ClassName -match '^(?i:Button|WindowsForms.*BUTTON.*)$' })
    $ok = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '^(?i:OK|确认|确定)$' } | Select-Object -First 1
    $always = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '^(?i:Always\s*Load|始终加载|总是加载)$' } | Select-Object -First 1
    $once = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '^(?i:Load\s*Once|加载一次|仅加载一次)$' } | Select-Object -First 1
    if ($DllAction -ne 'None' -and $always -and $once) {
        $target = if ($DllAction -eq 'Always') { $always } else { $once }
        return [pscustomobject]@{Kind='Dll';Choice=$null;Confirm=$target;Action="Dll$($DllAction)Load"}
    }
    if ($Dialog.Title -match '^(?i:代理信息|Proxy\s*Information)' -and $ok) {
        $radio = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '^(?i:显示代理图形|Show\s+proxy\s+graphics)[。.]?$' } | Select-Object -First 1
        if ($radio) { return [pscustomobject]@{Kind='Proxy';Choice=$radio;Confirm=$ok;Action='ShowProxyGraphics'} }
    }
    # The missing SHX filename after the title prefix changes for each prompt.
    # Match the dialog's purpose, then click its actual enabled Cancel button.
    if ($Dialog.Title -match '^(?i:选择形文件|Select\s+Shape\s+File)\s*(?:[:：].*)?$') {
        $cancel = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '^(?i:取消|Cancel)$' } | Select-Object -First 1
        if ($cancel) { return [pscustomobject]@{Kind='ShapeFile';Choice=$null;Confirm=$cancel;Action='CancelShapeFileSelection'} }
        return $null
    }
    $text = $Dialog.Title + ' ' + (($controls | ForEach-Object { $_.Name }) -join ' ')
    if ($text -notmatch '(?i)指定字体给样式|Specify\s+Font|缺少.*(?:SHX|字体)|缺失.*字体|未找到字体|Missing\s+(?:SHX|Font)') { return $null }
    $lists = @($controls | Where-Object { $_.ClassName -match '^(?i:ListBox|WindowsForms.*LISTBOX.*)$' } | Sort-Object Left)
    if ($lists.Count -gt 0 -and $ok) {
        # The rightmost enabled list is Big Font in the supplied two-list dialog.
        return [pscustomobject]@{Kind='Font';Choice=$lists[-1];Confirm=$ok;Action='ReplaceWithSecondFont'}
    }
    $replace = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '(?i)^(指定替换|指定.*字体|为每个.*指定|Specify.*replacement|Specify.*font)' } | Select-Object -First 1
    if ($replace) { return [pscustomobject]@{Kind='FontPrompt';Choice=$null;Confirm=$replace;Action='OpenFontReplacement'} }
    $ignore = $buttons | Where-Object { (ConvertTo-CadControlName $_.Name) -match '(?i)^(忽略|不加载|Ignore|Do\s+not\s+load)' } | Select-Object -First 1
    if ($ignore) { return [pscustomobject]@{Kind='FontPrompt';Choice=$null;Confirm=$ignore;Action='IgnoreMissingFont'} }
    return $null
}
function Invoke-CadDialogPlan($Dialog, $Plan, $ProcessId) {
    if ($Plan.Kind -eq 'Font') {
        $font = [CadTestDialogs]::SelectSecond($Dialog.Handle,$Plan.Choice.Handle,[int]$ProcessId)
        [CadTestDialogs]::Click($Dialog.Handle,$Plan.Confirm.Handle,[int]$ProcessId)
        return [pscustomobject]@{SelectedIndex=1;SelectedFont=$font;Method='LB_SETCURSEL/LBN_SELCHANGE + BM_CLICK'}
    }
    if ($Plan.Kind -eq 'Proxy') {
        [CadTestDialogs]::Click($Dialog.Handle,$Plan.Choice.Handle,[int]$ProcessId)
        if ([CadTestDialogs]::Checked($Plan.Choice.Handle) -ne 1) { throw 'Show Proxy Graphics radio option was not selected; confirmation withheld.' }
    }
    [CadTestDialogs]::Click($Dialog.Handle,$Plan.Confirm.Handle,[int]$ProcessId)
    return [pscustomobject]@{Method='BM_CLICK'}
}
