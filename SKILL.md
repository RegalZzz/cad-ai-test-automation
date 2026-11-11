---
name: cad-ai-test-automation
description: 指导 AI 编码助手为 Windows 上的 AutoCAD 二次开发建立并执行自动测试，涵盖场景设计、测试代码生成、构建、图纸副本执行、DLL 加载诊断、真实命令调度和回归验证。附 PowerShell 工具与 .NET 测试插件模板；界面入口按实际工具能力追加验证。
metadata:
  version: "1.2"
---

# cad-ai-test-automation

让 AI 把 AutoCAD 插件测试需求落实为可执行代码，在真实 CAD 中运行，读取图形数据库和日志，诊断失败并完成回归。沿用 Revit 自动测试 skill 的“理解需求 → 设计场景 → 接入业务 → 构建 → 副本实机执行 → 断言与证据 → 修正回归”闭环；宿主实现针对 AutoCAD 重做。

## AI 应完成的工作

1. 检查仓库、业务规则、CAD 年份及产品、.NET 环境、入口命令、业务服务和 fixture。优先复用已有测试，不只交付计划或空模板。
2. 设计正常、边界、失败、重复执行场景。用已知坐标、独立几何关系和数据库查询确定预期，避免复制被测算法作为断言。
3. 生成独立测试工程并引用真实业务，构建后在专用进程的图纸副本内串行运行。先用基础示例验证宿主，再接入业务。
4. 读取完整日志，区分环境、场景构造、命令上下文和业务错误。在授权范围内修正有证据的问题并回归；弹窗阻塞时先恢复原运行。
5. 交付源码、复现命令、输入来源、实际 DLL 路径/哈希、断言及未覆盖入口。分别报告已通过、失败、未执行。

## 选择测试入口

- 不依赖 CAD 数据库的几何、规则和参数转换，优先普通 .NET 测试。
- 实体、图层、块、属性、标注、事务及文档行为，在真实 CAD 中测试服务。
- 要证明 `[CommandMethod]` 正式入口，使用真实命令调度并等待完成，再读取数据库；直接 `new Commands().Method()` 不能证明命令注册、上下文和交互。
- 要证明 Ribbon、菜单、工具面板、选点、WPF/WinForms 等界面行为，追加桌面操作和图形结果验收。
- Desktop 是默认且已验证的宿主。Core Console 适用于经验证兼容其 API/命令的无界面测试，不能证明桌面 UI；本包 Console 入口仍为实验模式，本次 2020 环境 NETLOAD 失败，优先使用 Desktop。先读 [宿主机制](references/cad-mechanics.md)。不将 AutoCAD LT、其他 CAD 厂商或垂直产品假定为同一宿主。

## 创建与执行

按需读取 [PowerShell 兼容说明](references/powershell-compatibility.md)，使用进程级临时执行策略，不永久修改策略或自动提权。

1. 阅读 [技术流程与运行说明](references/workflow.md)。用 `scripts/New-CadTestHarness.ps1` 生成新工程，不覆盖已有目录。
2. 按 [业务接入与断言](references/adapters.md) 修改 `TestScenario.cs`，引用生产项目并记录真实业务程序集。默认 `api-smoke + fixture-command-smoke` 只验证框架、基础 API 和测试用命令，不能作为业务回归。
3. 使用 `scripts/Run-CadIntegrationTest.cmd`，指定 CAD 目录及一个 DWG 底图或 DWT 模板。`-PrepareOnly` 只构建和准备副本，不算实机通过。启动器为每次运行冻结一份程序集和输入副本。
4. 启动新的 CAD，ASCII `.scr` 从子进程环境取得 DLL 路径并执行 `NETLOAD → CADTEST_RUN → CADTEST_FINISH`。`Initialize` 只记录加载信号；API 在文档命令上下文内执行。清理使用独立 Session 命令关闭本轮文档且不保存。
5. 检查 `run.json`、`started.txt`、`assertions.log`、`result.json`、程序集/输入哈希与必要 DWG 证据，再给结论。超时或处理弹窗后，用 `Read-CadTestResult.ps1` 读取同一轮，保留原启动器状态。

桌面测试使用 `-AutoTrustRunner`，直接操作本轮 CAD 进程里所有 DLL 安全提示的“始终加载 / Always Load”原生按钮，包括测试 DLL、其他功能 DLL 和依赖；逐个处理，图纸打开后、`started.txt` 或 `result.json` 出现后仍继续，直到进程结束或超时。该选择会记住对应 DLL 的信任决定；已有会话授权继续有效，不等待用户手点或重复询问。明确只需单次加载时使用 `-AutoLoadRunner`，两者互斥。不修改 `SECURELOAD`、`TRUSTEDPATHS`。

Desktop 默认处理打开图纸提示：“代理信息”选择“显示代理图形”再确认；“指定字体给样式…”选择右侧“大字体”列表第二项，核验选中后点击“确定 / 确认”；“选择形文件: … / Select Shape File: …”按固定标题前缀识别，后面的缺失文件名动态变化，点击实际“取消 / Cancel”按钮，连续出现就逐个取消直到不再出现。有多个缺失字体就连续处理；若缺失字体提示没有可用的替换列表，可用明确的“指定替换”或“忽略”按钮。通过原生控件消息处理，完成一次后立即查找下一窗，空闲轮询间隔 100 毫秒。实现、记录与恢复见 [加载确认与弹窗](references/load-dialogs.md)。未知提示用 `Get-CadTestDialog.ps1` 观测实际控件，不猜坐标。

## CAD 执行约束

- 仅修改专用进程的图纸副本；DWG 的外参、图片、字体、数据链接不会因复制主图自动隔离。外部写入目标须分别复制、重定向和验证。
- AutoCAD .NET DLL 通过 `NETLOAD`、bundle 或需求加载注册命令；本模板只临时 `NETLOAD`。不生成 Revit `.addin`，不使用 Revit Idling、ExternalCommandData 或 TransactionGroup。
- 同一 CAD 进程通常不能卸载并替换已加载的 .NET DLL。每轮构建到新目录、启动新进程；以实际加载路径和 SHA256 为准，不能用磁盘源码版本替代运行证据。
- AutoCAD API 在受支持的主线程/命令上下文中调用。普通 Modal 命令通常已有文档锁；Session、无模式界面或外部回调须按实际上下文使用 `DocumentLock`，不能从外部 PowerShell 或 `Task.Run` 建模。
- 服务测试使用外层 `Transaction.Abort`，业务内部可提交嵌套事务；不要在打开的测试事务内运行交互命令。模板只验证 ModelSpace 句柄集恢复，不代表全数据库恢复；属性、图层、块及字典修改须增加独立回读检查。
- 真实命令测试放在服务事务结束后，使用同步 `Editor.Command` 和完整参数；记录 Ended/Failed/Cancelled，并核验图形。`SendStringToExecute` 是排队，调用返回不等于完成；UI、Session 和异步命令需要专用状态机和完成信号。
- AutoCAD 长度单位取决于图纸约定及 `INSUNITS`，不能照搬 Revit 的毫米/304.8。明确 WCS/UCS、OCS、模型/纸空间、块/外参变换与容差。
- 只关闭本轮拥有的文档且不保存；存在其他文档时保留进程。事务不能撤销文件、注册表或外部系统副作用。
- 超时保留进程与证据，不杀进程、不无依据重跑；活动进程记录阻止并发测试。每个已识别弹窗独立记录操作意图和结果；同一未关闭弹窗不重复确认，操作结果不确定时停止重试。

## 交付边界

报告 CAD 年份/API 版本/Build、宿主类型、输入来源、实际测试和业务 DLL、测试范围、断言、服务撤销与不保存关闭、输入哈希、命令及 UI 覆盖。编译成功、无异常或截图好看均不足以证明业务正确。

模板提供 2020–2026 的框架/API 版本映射，实际验证范围见 [验证记录](references/package-validation.md)。不把可生成或可编译等同于跨版本实机通过。仓库只分享文档、脚本和源码，不上传 Autodesk DLL、业务 DLL、图纸、个人路径或机器信息。安装与命令示例见 [README.md](README.md)。
