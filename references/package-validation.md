# 包内资源验证记录

最近更新：2026-11-11。版本：v1.1；下列真实 AutoCAD 运行是 v1.0 的历史验证，新版弹窗处理的验证范围单独列出。

## 已通过的真实 AutoCAD 运行

目标为本机完整 AutoCAD 2020 中文界面，API 版本 23.1，ACADVER 实际值 `23.1s (LMS Tech)`，可执行文件 Build `R23.1.47.0.0`。

| 运行 | 输入 | 加载确认 | 结果 |
| --- | --- | --- | --- |
| PowerShell 7.5.4 / Desktop | 系统 acadiso.dwt 的本轮副本；路径含中文与空格 | 脚本按进程、DLL 字段与哈希匹配，向实际“始终加载”按钮发送 BM_CLICK，无人工点击 | 7 条断言通过，CADTEST_PROBE 真实调度，CAD 正常退出，启动器退出码 0 |
| Windows PowerShell 5.1.22621.7376 / Desktop | 首轮生成的 before-commands.dwg 另复制为本轮输入；路径含中文与空格 | 同上，无人工点击 | 7 条断言通过，CADTEST_PROBE 真实调度，CAD 正常退出，启动器退出码 0 |

每轮包含 6 条场景/命令断言和 1 条基础设施断言：实体长度、提交的嵌套事务实体端点回读、外层 Abort 后 ModelSpace 句柄集恢复、真实命令完成事件、新增数量及已知几何。默认场景明确标注 `api-smoke + fixture-command-smoke; no business plugin tested`。

两次均生成 before/after DWG 数据库证据，记录实际 runner 路径/哈希、启动信号、断言和原子结果；CloseAndDiscard 成功，源输入与磁盘副本 SHA256 均未改变。退出通过一次 Idle 回调请求，不在清理命令栈内直接退出。

这些结果证明模板与基本宿主闭环，不证明用户生产插件、Ribbon 或第三方 UI 已通过。保存的 DWG 是数据库证据，不是屏幕截图。原始本机运行记录保留在项目忽略的 `.local/` 下，没有上传图纸、DLL 或机器路径。

## 弹窗实现的实测依据

从本机实际安全提示取得：标题“安全性 - 未签名的可执行文件”、#32770、MainInstruction、ContentText、三个按钮与其文字/ID。DLL 信息分成“名称”和“位置”；UI Automation Name 使用转义 CRLF 和双反斜线。对话框挂在 CAD 主窗口下面，按桌面直接子窗口或 ClassName 查询不足以可靠找到。

`InvokePattern.Invoke()` 返回后，实测窗口仍存在且无 DLL 启动信号；经再次核验目标后，原生 BM_CLICK 才使运行继续。当时的 v1.0 使用一次性意图记录及 SendMessageTimeout 向实际按钮发送消息，验证按钮 PID、父子关系与可用状态。两个 PowerShell 宿主均完成自动“始终加载”实机运行。

早期调试中用户手动操作过“始终加载”。最终两轮均采用新运行目录并记录脚本的实际按钮操作，不把用户之前的手动动作作为自动化证据。不声称新路径或重编译 DLL 必然继承旧信任，也没有修改 SECURELOAD 或 TRUSTEDPATHS。

## 工具验证

`tests/Test-Package.ps1` 在 PowerShell 7.5.4 与 Windows PowerShell 5.1.22621.7376 下各通过 47 项检查，覆盖：

- 八份 PowerShell 脚本解析、生成 net472 工程、拒绝覆盖、2025 net8.0-windows 映射和模板占位符清除。
- DLL 提示的真实/转义 CRLF、双反斜线、中文路径、目录前缀碰撞、不同 DLL 和重复字段。
- 合成证据的运行/进程/宿主/年份错误、失败标志、字符串冒充布尔值、无场景断言、无撤销/关闭、错误范围/路径/哈希、输入修改、缺少结果及 PrepareOnly 冒充通过。
- 非零宿主退出、Core 退出要求、保留原超时状态、读取器不改写运行记录、未指定动作/未记录授权/已停止启动器的确认拒绝路径。

这些工具检查中的图纸/DLL 是明确标识的合成字节，不调用 CAD，不作为实机证据。脱敏的中文弹窗结构位于 `tests/fixtures/`，用于解析回归。

另外实际执行了 PrepareOnly 构建和输入复制，支持中文及空格路径；CMD 主入口选中 PowerShell 7 并成功完成 PrepareOnly。CMD 的自动回落 5.1 分支本次未单独模拟；5.1 的直接启动与真实 Desktop 测试已经通过。

Skill frontmatter 经 skill-creator 的 quick_validate.py 检查；在 Windows 中文默认代码页下以 `python -X utf8` 执行。包内相对链接与 Git 内容在交付前检查。

## v1.1 连续弹窗控件回归

`tests/Test-Dialogs.ps1` 在上述两个 PowerShell 宿主下各通过 35 项检查。它编译并启动独立的合成原生窗口进程，使用测试目录中的 `acad.exe` 名称验证生产处理器的进程身份检查；该程序只创建 Windows 控件，不包含 Autodesk 代码、不加载 DLL、不读写图纸。

- 两个不同 DLL 的加载确认都收到“始终加载”原生按钮消息；第二个在合成 `started.txt` / `result.json` 出现后继续处理。
- “代理信息”互斥选项在确认前实际处于“显示代理图形”选中状态。
- 两个连续“指定字体给样式…”弹窗的右侧大字体索引均为 1，回读为 `big2.shx`，各收到一次 `LBN_SELCHANGE` 后确认；左侧列表保持索引 0。
- 五个提示复用同一窗口 HWND，标题 / 内容变化仍产生五个独立的意图和结果记录。同一尚未关闭提示不重复点击，停滞和未知结果会中止重试。
- 未知保存提示保持待处理，跨 PID 控件操作被拒绝；显式“加载一次”和未授权 DLL 的行为保留。

一次连续五窗的处理约 1–1.5 秒，包含身份检查、哈希和操作文件写入；这是本机合成控件测量，不能作为真实 CAD 加载耗时保证。字体和代理弹窗布局依据用户提供的界面说明与截图；v1.1 完整弹窗链尚未在真实 CAD 中复测。

复现：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Package.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Dialogs.ps1
# 用 powershell.exe 替代 pwsh.exe 可验证 Windows PowerShell 5.1。
```

## 选择形文件补充回归（2026-11-11）

`tests/Test-Dialogs.ps1` 在 PowerShell 7.5.4 与 Windows PowerShell 5.1.22621.7376 下各通过 54 项检查。原有五个提示后追加三个连续的形文件选择框，分别使用“选择形文件: AAA.SHX”“选择形文件：缺失字体.shx”和“Select Shape File: Other.SHX”标题，全部复用同一窗口句柄，并在 DLL 操作选项为 `None` 时执行生产处理器：

- 每窗实际收到“取消”按钮（ID 2）的 `BM_CLICK`，未点击“打开”；三个操作均独立留有 `CancelShapeFileSelection` 意图和结果记录。
- 文件名、中英文标题、全角冒号和按钮助记符变化后仍继续处理；所有提示均在合成 `started.txt` / `result.json` 已出现后处理。
- 八窗分别记录、每窗只操作一次；取消链结束后无匹配弹窗，普通打开或保存窗口即使含 SHX 文件名和取消按钮也不处理；缺少可用取消按钮时不执行。
- 原有 DLL、代理、大字体选择、未关闭弹窗去重、未知结果停止及 PID 校验继续通过。

八窗处理分别耗时约 0.9 秒（7）和 1.2 秒（5.1），仅是本机合成控件测量。此处使用独立 Windows 原生窗口，不是实际 AutoCAD；选择形文件布局依据用户截图，尚未使用会触发该弹窗的真实 DWG 验证。

## 发现并修正的问题

- ACADVER 存在字母/构建后缀，改为提取开头数字主次版本；保留完整值作证据。
- Desktop 启动时隐藏主窗口会妨碍用户观察，改为交互窗口；不将 Desktop 伪装成无界面运行。
- 直接在 Session 清理命令栈中 Quit 出现非零退出；改为清理后的一次 Idle 回调，最终两轮退出码均为 0。
- 最初的加载脚本未覆盖 CAD 对话框的层级与分字段路径；依据实际观测修正，并以原生按钮消息完成验证。

早期失败与超时记录仍保留，未改写为成功。曾有超时后恢复得到通过结果的运行，读取器保留其原始 TimedOut 状态。

## 尚未通过及未覆盖

Core Console 是实验入口：修正了缺少桌面 CloseAndDiscard 扩展的编译问题，确认构建输出不引用 AcMgd，并按实际 UTF-16 解码 Console 输出。但本机 2020 环境在中文及纯英文运行目录均出现 NETLOAD“无法加载程序集”，未产生 started.txt/result.json。没有通过修改全局安全变量绕过，也没有把进程退出码 0 当成测试通过。加载失败原因尚未确定，不声称该模式已经可用。

AutoCAD 2021–2026 的实机兼容性、英文界面按钮、AutoCAD LT/其他厂商/垂直产品、生产业务 DLL、异步/Session 业务命令、Ribbon/对话框/点选流程、复杂外参及多文档副作用均未验证。新接入业务仍须在目标 CAD 与专用 fixture 中执行。
