using System;
using System.IO;
using System.Runtime.InteropServices;
public static class CadDialogFixture {
    private delegate IntPtr WndProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] private struct Msg { public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public int x,y; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr CreateWindowEx(uint ex, string cls, string title, uint style, int x,int y,int width,int height,IntPtr parent,IntPtr id,IntPtr instance,IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern bool SetWindowText(IntPtr h,string text);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr h,int index,IntPtr value);
    [DllImport("user32.dll")] private static extern IntPtr CallWindowProc(IntPtr proc,IntPtr h,uint msg,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h,int command);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int code);
    [DllImport("user32.dll")] private static extern int GetMessage(out Msg msg,IntPtr h,uint first,uint last);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Msg msg);
    [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref Msg msg);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] private static extern IntPtr SendString(IntPtr h,uint msg,IntPtr w,string text);
    private static IntPtr window, original, rightList, leftList, showRadio;
    private static readonly System.Collections.Generic.List<IntPtr> children = new System.Collections.Generic.List<IntPtr>();
    private static WndProc proc = Handle;
    private static string evidence;
    private static int stage, notifications;
    private static IntPtr Child(string cls,string text,int id,int x,int y,int width,int height,uint extra) {
        IntPtr h=CreateWindowEx(0,cls,text,0x50000000|extra,x,y,width,height,window,new IntPtr(id),IntPtr.Zero,IntPtr.Zero);
        if (h==IntPtr.Zero) throw new Exception("Could not create fixture child");
        children.Add(h); return h;
    }
    private static void Populate() {
        foreach (var h in children) DestroyWindow(h); children.Clear(); notifications=0;
        if (stage<2) {
            SetWindowText(window,"\u5b89\u5168\u6027 - \u672a\u7b7e\u540d\u7684\u53ef\u6267\u884c\u6587\u4ef6");
            Child("Static","Name: "+(stage==0?"Runner.dll":"UnrelatedDependency.dll")+"\r\nLocation: C:\\SYNTHETIC",100,10,15,500,90,0);
            Child("Button","\u59cb\u7ec8\u52a0\u8f7d",1001,10,120,130,30,0);
            Child("Button","\u52a0\u8f7d\u4e00\u6b21",1002,155,120,130,30,0);
            Child("Button","\u4e0d\u52a0\u8f7d",1003,300,120,130,30,0);
        } else if (stage==2) {
            SetWindowText(window,"\u4ee3\u7406\u4fe1\u606f");
            Child("Button","\u4e0d\u663e\u793a\u4ee3\u7406\u56fe\u5f62",2001,10,15,330,25,0x20009);
            showRadio=Child("Button","\u663e\u793a\u4ee3\u7406\u56fe\u5f62",2002,10,45,330,25,9);
            Child("Button","\u663e\u793a\u4ee3\u7406\u8fb9\u754c\u6846",2003,10,75,330,25,9);
            Child("Button","\u786e\u8ba4",1,10,120,130,30,0);
        } else if (stage<5) {
            SetWindowText(window,"\u6307\u5b9a\u5b57\u4f53\u7ed9\u6837\u5f0f Style"+stage);
            Child("Static","SHX \u5b57\u4f53(X):",310,10,10,180,20,0);
            Child("Static","\u5927\u5b57\u4f53(B):",311,220,10,180,20,0);
            leftList=Child("ListBox","",301,10,35,180,100,0xA10001);
            rightList=Child("ListBox","",302,220,35,180,100,0xA10001);
            foreach (var name in new[]{"normal1.shx","normal2.shx","normal3.shx"}) SendString(leftList,0x0180,IntPtr.Zero,name);
            foreach (var name in new[]{"big1.shx","big2.shx","big3.shx"}) SendString(rightList,0x0180,IntPtr.Zero,name);
            SendMessage(leftList,0x0186,IntPtr.Zero,IntPtr.Zero); SendMessage(rightList,0x0186,IntPtr.Zero,IntPtr.Zero);
            Child("Static","\u672a\u627e\u5230\u5b57\u4f53: Missing"+stage,312,10,145,350,20,0);
            Child("Button","\u786e\u5b9a",1,420,35,100,30,0);
        } else if (stage<8) {
            SetWindowText(window,stage==5 ? "\u9009\u62e9\u5f62\u6587\u4ef6: AAA.SHX"
                : stage==6 ? "\u9009\u62e9\u5f62\u6587\u4ef6\uff1a\u7f3a\u5931\u5b57\u4f53.shx" : "Select Shape File: Other.SHX");
            Child("Edit",stage==5 ? "AAA.shx" : stage==6 ? "\u7f3a\u5931\u5b57\u4f53.shx" : "Other.SHX",401,10,15,350,25,0);
            IntPtr shapeType=Child("ComboBox","",402,10,55,350,100,3);
            SendString(shapeType,0x0143,IntPtr.Zero,"\u5f62\u5b57\u4f53 (*.shx)");
            SendMessage(shapeType,0x014E,IntPtr.Zero,IntPtr.Zero);
            Child("Button",stage==7 ? "&Open" : "\u6253\u5f00(&O)",1,380,15,130,30,0);
            Child("Button",stage==7 ? "&Cancel" : stage==6 ? "\u53d6\u6d88(&C)" : "\u53d6\u6d88",2,380,55,130,30,0);
        } else {
            SetWindowText(window,"Save Changes?");
            Child("Button","OK",1,10,15,100,30,0);
            Child("Button","Cancel",2,120,15,100,30,0);
            Child("Edit","AAA.SHX",401,10,55,350,25,0);
        }
    }
    private static IntPtr Handle(IntPtr h,uint msg,IntPtr w,IntPtr l) {
        if (msg==0x0010) { DestroyWindow(h); PostQuitMessage(0); return IntPtr.Zero; }
        if (msg==0x0111) {
            int id=(int)(w.ToInt64()&0xffff), code=(int)((w.ToInt64()>>16)&0xffff);
            if (id==302 && code==1) notifications++;
            if ((stage<2 && id>=1001 && id<=1003) || (stage>=2 && id==1) || (stage>=5 && id==2)) {
                string result = stage<2 ? "Dll|"+stage+"|"+id : stage==2 ? "Proxy|"+SendMessage(showRadio,0x00F0,IntPtr.Zero,IntPtr.Zero).ToInt64()
                    : stage<5 ? "Font|"+stage+"|"+SendMessage(leftList,0x0188,IntPtr.Zero,IntPtr.Zero).ToInt64()+"|"+SendMessage(rightList,0x0188,IntPtr.Zero,IntPtr.Zero).ToInt64()+"|"+notifications
                    : stage<8 && id==2 ? "ShapeFile|"+stage+"|"+id : "UNEXPECTED_CONFIRM";
                File.AppendAllText(evidence,result+Environment.NewLine); stage++; Populate(); return IntPtr.Zero;
            }
        }
        return CallWindowProc(original,h,msg,w,l);
    }
    public static void Main(string[] args) { Run(args[0]); }
    public static void Run(string path) {
        evidence=path;
        window=CreateWindowEx(0,"#32770","Fixture",0x10CF0000,40,40,580,240,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
        if (window==IntPtr.Zero) throw new Exception("Could not create fixture dialog");
        original=SetWindowLongPtr(window,-4,Marshal.GetFunctionPointerForDelegate(proc));
        Populate(); ShowWindow(window,5); File.WriteAllText(path+".ready",window.ToInt64().ToString());
        Msg message; while (GetMessage(out message,IntPtr.Zero,0,0)>0) { TranslateMessage(ref message); DispatchMessage(ref message); }
    }
}
