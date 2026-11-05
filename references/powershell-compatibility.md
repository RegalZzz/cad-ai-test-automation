# PowerShell 权限与兼容

支持 Windows PowerShell 5.1 与 PowerShell 7 的共同语法/API。推荐独立子进程的临时执行策略：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-CadTestHarness.ps1 -Destination 'D:\MyPlugin\tests\CadTests' -Name CadTests -CadVersion 2020
```

只有 5.1 时把 pwsh.exe 换成 powershell.exe。主运行入口 `Run-CadIntegrationTest.cmd` 优先选择 PATH 中的 PowerShell 7，否则用系统 5.1；只给该进程 Bypass，保留退出码。找到宿主后执行失败不换宿主重复启动。CMD 的 setlocal/PSModulePath 清理避免从 7 继承错误模块路径到 5.1，父会话不变。

MachinePolicy/UserPolicy 优先于 Process；Bypass 不能覆盖组织强制策略，也不能授予管理员/文件 ACL 权限，不能解决 CAD 许可或 NETLOAD 安全提示。无需永久改 CurrentUser/LocalMachine，不自动提权。

脚本保持 ASCII，JSON 明确 UTF-8，C#/Markdown 用 UTF-8。路径包含中文或空格时正常作为参数传入，不使用 Invoke-Expression。SCR 只含 ASCII，通过 getenv 读取子进程 DLL 路径。

PowerShell 7.5 会把 JSON ISO 日期解析成 DateTime，5.1 保留字符串；进程开始时间转 DateTimeOffset 后比较 UTC ticks。原生构建程序按真实 LASTEXITCODE 判定，完整输出保存，不能依赖不同宿主对 stderr 的默认解释。

`-File` 跨进程不能等价传递 PowerShell 数组。多个 FixturePath 应在允许执行脚本的 PowerShell 会话内直接调用 `.ps1 -FixturePath @('a.dwg','b.png')`；CMD 入口适合标量参数和单个 fixture。环境的 PowerShell 版本与 CAD 插件 .NET 版本独立：PowerShell 7 可以构建 net472 并启动 AutoCAD 2020。
