# cad-ai-test-automation

面向 Windows / AutoCAD 二次开发的 AI 自动测试 Skill，v1.0

基于 [revit-ai-test-automation](https://github.com/RegalZzz/revit-ai-test-automation) 的测试闭环，针对 CAD 重做 DLL 加载、命令执行、事务隔离、弹窗处理和图纸关闭机制。包含可运行的 PowerShell 工具与 C# 测试插件模板，帮助 AI 从业务需求完成场景、代码、构建、实机执行、断言和修正回归。

## 安装与调用

```powershell
git clone https://github.com/RegalZzz/cad-ai-test-automation.git
```

项目根目录就是完整 Skill。将整个目录放到支持的技能目录，例如 `%USERPROFILE%\.codex\skills\cad-ai-test-automation` 或项目的 `.agents/skills/cad-ai-test-automation`。也可由其他 AI 工具读取 SKILL.md，按相对路径使用脚本和模板。

> 使用 $cad-ai-test-automation 为当前 AutoCAD 插件设计并执行回归测试：复用真实业务服务，生成最小图形场景，在图纸副本中验证实际实体和正式命令入口，诊断失败并交付可复现证据。

需要 Windows、完整 AutoCAD、可用许可、.NET SDK 与相应 targeting pack。支持生成 2020–2026 工程，实际测试版本和限制见 [验证记录](references/package-validation.md)。其他 CAD 厂商和 AutoCAD LT 未适配。

## 运行示例

从 Skill 目录执行，路径按本机环境填写。PowerShell 7 不可用时改为 powershell.exe：

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-CadTestHarness.ps1 `
    -Destination 'D:\MyCadPlugin\tests\CadTests' -Name CadTests -CadVersion 2020

# 构建、冻结 DLL 与复制输入；不会启动 CAD。
.\scripts\Run-CadIntegrationTest.cmd `
    -ProjectPath 'D:\MyCadPlugin\tests\CadTests\CadTests.csproj' `
    -CadInstallDir 'D:\Program Files\Autodesk\AutoCAD 2020' `
    -DrawingPath 'D:\TestAssets\Base.dwg' -PrepareOnly

# 去掉 PrepareOnly 才会实机运行。
# 无底图时可将 DrawingPath 换为 TemplatePath，指向实际 .dwt。
# 自动处理本轮指定测试 DLL 的“始终加载”，会记住对应 DLL 的信任决定。
.\scripts\Run-CadIntegrationTest.cmd `
    -ProjectPath 'D:\MyCadPlugin\tests\CadTests\CadTests.csproj' `
    -CadInstallDir 'D:\Program Files\Autodesk\AutoCAD 2020' `
    -TemplatePath 'D:\TestAssets\acadiso.dwt' -AutoTrustRunner

# 超时或处理启动提示后，读取同一轮结果：
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Read-CadTestResult.ps1 `
    -RunDirectory 'D:\MyCadPlugin\tests\CadTests\.local\cad-tests\实际运行ID'
```

默认产物目录是生成工程下 `.local/cad-tests/<ID>/`；可用 TestRoot 指定。每轮生成 `run.json`、构建/断言日志、原子 `result.json` 和必要图形证据。源输入与副本磁盘哈希均检查，超时保留 CAD 进程与原始状态。测试产物加入业务仓库忽略规则。

`-AutoTrustRunner` 自动识别本轮 DLL 并点击“始终加载”，不等待用户手点；不全局关闭安全加载。只需“加载一次”时使用 `-AutoLoadRunner`，两者互斥。加载授权只适用于指定测试 DLL；业务依赖的独立加载提示需分别匹配。详细实现与实测控件见 [加载与弹窗处理](references/load-dialogs.md)。

已验证的运行入口是 **Desktop**。包内保留 `-HostMode CoreConsole -DrawingPath <DWG>` 实验入口；当前 AutoCAD 2020 环境在 NETLOAD 阶段失败，尚未通过实机验证。无界面模式需要进一步适配加载环境，不应替代 Desktop 验收。详细限制见 [验证记录](references/package-validation.md)。

默认示例是 **api-smoke + fixture-command-smoke**：创建实体、验证嵌套事务撤销、真实调度测试用命令、回读几何、关闭且不保存。它不包含用户的生产业务。按 [业务接入说明](references/adapters.md) 替换场景并记录真实业务 DLL；不能把示例通过当成业务回归完成。

## 包结构

```text
cad-ai-test-automation/
├── SKILL.md             AI 执行流程与约束
├── agents/openai.yaml   展示与调用元数据
├── scripts/             生成、运行、加载诊断与结果读取
├── assets/harness/      .NET 测试插件源码模板
├── references/          CAD 机制、接入、弹窗与验证记录
├── tests/               工具和证据校验回归
└── LICENSE              MIT
```

完整 [运行流程](references/workflow.md)、[加载与弹窗处理](references/load-dialogs.md)、[PowerShell 兼容说明](references/powershell-compatibility.md)。本包不含 Autodesk DLL、业务插件和图纸；不永久注册插件，仅按选项记录指定 DLL 的信任，不全局关闭安全加载。
