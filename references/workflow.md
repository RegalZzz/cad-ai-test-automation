# 技术流程与运行说明

## 环境与资产

检查产品/年份、`acad.exe`、`accoreconsole.exe`、API DLL、可用许可、.NET SDK 与 targeting pack。无需把 CAD API 加载进 PowerShell。先识别业务项目的命令属性、真实服务、图纸单位、外部依赖和保存副作用。

每轮只能选一个 DWG 底图或 DWT 模板。Desktop 用 DWG 副本直接打开，或 `/t` 从 DWT 副本创建未命名图纸；Core Console 只接受 DWG。不要将 DWG 改扩展名假装 DWT，或把随机字节文件用作真实输入。

底图和额外 fixture 都复制并记录 SHA256。主图放 `Drawing.dwg`/`Drawing.dwt`，额外文件放 `inputs/`。DWG 内的外参、图片和数据链接可能仍指向源目录；接入测试时按实际结构复制、重定向，验证没有修改外部源。字体、打印配置、Object Enabler 和垂直产品对象需要专用 fixture。

## 一轮生命周期

1. `New-CadTestHarness.ps1` 生成 C# 工程和 `harness.json`，拒绝覆盖已有目录。
2. `Invoke-CadIntegrationTest.ps1` 校验 CAD API 年份，构建到本轮唯一 `bin/`；保存构建输出和全部输出文件哈希。禁止把 AcMgd/AcDbMgd/AcCoreMgd 复制到输出。
3. 准备输入副本及 ASCII `run.scr`，写 `run.json`。`PrepareOnly` 到此结束，不启动 CAD。
4. 启动新进程：Desktop 使用 `/nologo <DWG> /b <SCR>` 或 `/nologo /t <DWT> /b <SCR>`；Console 使用 `/i <DWG> /s <SCR>`。路径放在独立引号内，运行目录/ID/DLL 路径仅传给子进程。
5. SCR 用 `(command "_NETLOAD" (getenv "CAD_TEST_ASSEMBLY"))` 加载，再运行 `CADTEST_RUN` 和 `CADTEST_FINISH`。脚本本身不嵌入中文路径，避开 AutoCAD 2020 的脚本编码差异。
6. Initialize 校验 ID、加载 DLL 路径与哈希，以 CreateNew 生成 `started.txt`。它不直接运行测试。
7. Modal 测试命令检查实际 CAD 版本、宿主和活动文档身份；服务阶段包在可中止的外层事务内，之后检查 ModelSpace 句柄集，再运行真实命令阶段。
8. Desktop 的 Session 清理命令 CloseAndDiscard 本轮拥有的文档，写原子 `result.json`；没有其他文档时在一次 Idle 回调内请求退出，避免在清理命令栈中直接退出。结果写出前不声称完成。
9. 外部结果读取器校验运行/进程 ID、版本、加载路径/哈希、断言、清理及输入文件。CAD 非零退出码单独作为启动器失败。

进程级互斥锁与 `%LOCALAPPDATA%/cad-ai-test-automation/active.json` 阻止本工具并发启动；PID 还必须匹配开始时间、进程名与可执行文件路径。超时后活动记录保留。它不操作用户已经打开的 CAD。

实验 Console 分支不引用 AcMgd，因而没有桌面的 CloseAndDiscard 扩展。其设计为记录 DiscardOnProcessExitRequested，由 SCR 发 QUIT/N，再由外部读取器要求进程已退出、记录零退出码且输入哈希不变；不会把请求退出冒充文档已关闭。本次尚未到达该测试阶段，2020 环境 NETLOAD 失败，见验证记录。Console 输出按其实际 UTF-16 解码后保存为 UTF-8。

## 结果与恢复

| 文件 | 用途 |
| --- | --- |
| run.json | 本轮 ID、状态、PID/开始时间、宿主、输入与构建哈希、原启动器错误 |
| build.log | 完整构建输出；按真实退出码判定 |
| run.scr | 本轮实际启动脚本 |
| started.txt / startup-error.txt | DLL 已进入 Initialize，或初始化错误 |
| assertions.log | 自动刷新的断言、命令与异常 |
| result.json | API/命令结果、范围、加载程序集、撤销及不保存关闭证据 |
| after-commands.dwg | 默认示例通过 Wblock 另存的数据库证据；不是屏幕截图 |
| dialogs.latest.json | 只读诊断实际 PID 的窗口/控件 |
| dll-approval.intent.json / dll-approval.action.json | 指定 DLL 的加载操作意图、按钮/句柄及调用记录；不是 DLL 加载成功的证明 |
| console.stdout.log / console.stderr.log | Console 正常结束后捕获的原始输出 |

排障顺序：无进程 → 路径/许可；有进程无 started → 启动界面、加载安全提示、脚本或依赖；有 started 无断言 → 命令未调度/图纸未准备；有断言无 result → 命令交互阻塞或 Session 清理未到达；失败结果 → 具体断言和异常。

超时不会杀 CAD 或重新构建。处理已观察提示后，先读取原轮：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-CadTestDialog.ps1 -RunDirectory 'D:\CadTests\实际运行目录' | ConvertTo-Json -Depth 8
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Read-CadTestResult.ps1 -RunDirectory 'D:\CadTests\实际运行目录'
```

读取器不改写 `run.json`，不启动/退出 CAD；超时后得到的 PASS 会带原始 `TimedOut` 状态及进程是否仍存活。不能用它改写之前启动器的退出码。运行仍活跃时先诊断，不删除活动标记以绕开并发保护。

外层事务已 Abort 和 ModelSpace 句柄集相同只说明模板的这两项检查成立，不能证明所有实体属性、符号表、字典、外部文件完全回滚。业务接入须补充对应断言；输入源与副本磁盘哈希不变也不能证明外链未改变。
