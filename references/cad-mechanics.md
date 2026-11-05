# AutoCAD 与 Revit 的宿主差异

| 环节 | Revit 方案 | 本 CAD 方案 |
| --- | --- | --- |
| 注册/加载 | 用户 Addins 中临时 `.addin` | 新进程 `.scr` 调用 `NETLOAD`；不注册永久插件 |
| 初始化 | `IExternalApplication.OnStartup` 注册 Idling | `IExtensionApplication.Initialize` 校验运行身份、记录已加载信号 |
| 测试入口 | 一次 Idling 主线程回调 | `[CommandMethod] CADTEST_RUN` 的 Modal 文档命令 |
| 正式入口 | 需真实 ExternalCommand 调度 | `Editor.Command` 调度已注册的全局命令名，并检查命令结束事件 |
| 撤销 | 外层 TransactionGroup.RollBack | 服务外层 Transaction.Abort；命令阶段以专用副本和 CloseAndDiscard 隔离 |
| 文档关闭 | 外部打开文档 Close(false) | 独立 Session 命令关闭本轮文档；不能在正在运行的文档命令中关闭该文档 |
| 加载提示 | Revit 发布者/总是载入 | CAD 安全性提示/始终加载；依据实际控件与 DLL 字段校验 |
| 无界面 | 不作为通用后台宿主 | `accoreconsole.exe` 可执行兼容的数据库/命令；无 Ribbon、桌面文档窗口 |
| API 引用 | RevitAPI、RevitAPIUI | AcDbMgd、AcCoreMgd；桌面特有功能另加 AcMgd，Private=False |

## 版本及产品边界

| AutoCAD 年份 | ACADVER 前缀 | 模板 TargetFramework |
| --- | --- | --- |
| 2020 | 23.1 | net472 |
| 2021 | 24.0 | net48 |
| 2022 | 24.1 | net48 |
| 2023 | 24.2 | net48 |
| 2024 | 24.3 | net48 |
| 2025 | 25.0 | net8.0-windows |
| 2026 | 25.1 | net8.0-windows |

每个年份引用对应安装目录的 API 并实机回归，特别是 2025 的 .NET 8 迁移。此映射只用于生成工程；本次验证年份在验证记录中单独列出。AutoCAD LT 的插件能力、Civil 3D/Map/Architecture 的额外依赖、天正等附加插件以及其他厂商 CAD 都需要另外适配。

Core Console 构建设置 `CadHost=CoreConsole`，模板不引用 AcMgd。业务依赖桌面程序集、UI 或不支持的命令时不能强行声称 Console 兼容。首轮用桌面生成的 `before-commands.dwg` 可作为下一轮的独立 DWG 输入；`after-commands.dwg` 已含 fixture 命令产物，未经调整不能重复套用唯一性预期。

本包的 Console 启动、输出捕获及退出校验为实验实现。在本次 2020 安装中，中文与纯英文输出目录均发生 NETLOAD“无法加载程序集”，未产生启动信号；尚未证明 Console 可执行此模板。不改变全局安全变量来绕过该失败；当前已验证路径为 Desktop。

## 命令与上下文

`CommandFlags.Modal` 在活动文档命令上下文中执行，适合同步服务/命令测试。`CommandFlags.Session` 是应用上下文，用于本模板的关闭动作；Session 业务访问数据库时按 API 要求锁定文档。不能把 Session 命令作为普通 `Editor.Command` 的通用嵌套目标。

内建命令使用全局命令/选项，例如 `_.LINE`、`_non` 和完整终止参数；`_` 为国际化名称，`.` 绕开重新定义的内建命令。插件命令使用它实际注册的全局名。命令名、选项、选择集、点和结束输入都依据命令真实提示设计，不能把本地化提示猜成通用参数。

`Editor.Command` 只适用于允许同步调用的命令上下文。不能在 Initialize、外部线程、无模式窗口事件中直接调用。需要 `ExecuteInCommandContextAsync`、`CommandAsync` 或排队命令时，单独实现等待、异常与取消路径；完成信号应在最终命令结束及数据库检查以后生成。不能等待自己排队的命令同时阻塞 CAD 主线程。

## 加载生命周期

加载测试 DLL 与加载业务 DLL是两个独立步骤。项目引用能使业务类型解析，不能代替所有生产插件的 `NETLOAD`/初始化副作用或命令发现。正式命令测试前用真实加载流程加载生产程序集，验证其命令确已注册，然后执行。需要多 DLL 加载时逐个记录路径/哈希并精确处理提示；本包自动确认选项只处理测试入口 DLL。

AutoCAD 的 `SECURELOAD`、`TRUSTEDPATHS`、`APPAUTOLOAD`、签名以及 Windows 下载标记会影响加载。不要为了通过测试全局关闭安全检查或覆盖用户配置。命令未发现时查看启动信号、错误日志、目标框架、依赖解析和命令注册，再判断是否业务故障。
