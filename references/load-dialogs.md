# DLL 加载确认与弹窗

用户要求自动完成指定测试 DLL 的加载确认时，使用 `-AutoTrustRunner`，由外部 PowerShell 自动操作“始终加载”。用户只要求单次加载时可用 `-AutoLoadRunner` 操作“加载一次”。两者互斥。已有会话授权继续有效，不需要让用户反复手点。

## AutoCAD 2020 的实际控件

本机中文界面观测结果：

| 控件 | 实测值 |
| --- | --- |
| 对话框标题 / ClassName | 安全性 - 未签名的可执行文件 / #32770 |
| 指令文本 ID | MainInstruction，包含“发布者” |
| DLL 内容 ID | ContentText，包含分别展示的“名称”和“位置”字段 |
| 始终加载 | CommandButton_1001，Name=始终加载 |
| 加载一次 | CommandButton_1002，Name=加载一次 |
| 不加载 | CommandButton_1003，Name=不加载 |

这些 ID 来自实际 CAD 窗口，不是从 Revit 猜测而来。虽然按钮 ID 恰好一致，DLL 字段、层级和有效操作方式存在差异，不能只凭 ID 点击。

此 CAD 的对话框在 UI Automation 树中位于 `AfxMDIFrame140u` 主窗口下面；按桌面直接子窗口或按 ClassName 批量查找未能可靠得到它。脚本按本轮 PID 找到根窗口，查找 `ContentText`，通过 ControlViewWalker.GetParent 获取实际 #32770 祖先，再核对同一 PID。

ContentText 的 Name 包含字面的转义 CRLF 和双反斜线。解析只拆真实换行或完整的转义 CRLF，再分别读名称和目录字段；不把路径中的 `\new`、`\north` 等解码成换行。文件名与目录必须分别精确匹配，拒绝同名 DLL 在其他目录、目录前缀相似及重复字段。

## 自动确认的实际实现

主启动器在 Launched 状态等待时调用 `Approve-CadTestDll.ps1`：

1. 校验本轮明确记录了相应自动操作选项、Desktop 宿主、PID/开始时间/进程名/可执行文件路径，且尚无结果。
2. 校验冻结的测试 DLL SHA256；已有 started.txt 则不再操作。
3. 获取上述真实对话框，核对 MainInstruction、三个按钮、名称/目录和实际按钮文字；候选必须唯一。
4. 再校验运行状态、进程与哈希，获取按钮和对话框的实际 NativeWindowHandle。通过 GetWindowThreadProcessId、IsChild、IsWindowEnabled 核验按钮进程、父子关系和可用状态。
5. 用 CreateNew 写 `dll-approval.intent.json`，将目标对话框置前，向该实际按钮发送一次 `BM_CLICK (0x00F5)`，使用 `SendMessageTimeout` 限制等待为 5 秒。无坐标猜测。
6. 写 `dll-approval.action.json`，记录方法、标题、实际按钮文字/ID/句柄、PID、DLL 路径和哈希。发送超时/异常则记为结果不确定，保留意图，停止重试。

本机实测 `InvokePattern.Invoke()` 返回后，加载提示仍停留且未产生 started.txt；对核验后的原生按钮发送 BM_CLICK 后，DLL 立即进入 Initialize。因此包内采用经过验证的原生按钮消息，不把 InvokePattern 返回当作加载成功。

只有 `started.txt` 证明进入测试 DLL，只有结果及断言证明测试通过。操作日志不会替代这两个信号。辅助脚本最多发一次消息，出现第二个不匹配/未知提示时先观测，不能扩展为确认所有弹窗的循环。

“始终加载”会记住对应 DLL 的信任决定；新路径、新构建及不同 CAD 环境仍可能提示。测试 DLL 每轮放在新目录，不依赖此前手动建立的信任。脚本不修改 SECURELOAD/TRUSTEDPATHS，也不把 runner 授权扩大为业务依赖或机器其他插件。

## 只读诊断与恢复

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-CadTestDialog.ps1 -RunDirectory 'D:\CadTests\实际运行目录' | ConvertTo-Json -Depth 8
```

脚本通过运行身份读取已识别的 ContentText 对话框，保存 `dialogs.latest.json`，不点击。没有此结构的其他弹窗需要根据实际桌面工具继续观测，不能把“未找到匹配窗口”当成没有弹窗。

许可、修复、保存、代理对象、外链、首启体验及未知提示按具体内容处理，不写“遇到弹窗就 Enter”的循环。组织策略阻止加载时采用符合组织要求的签名部署，不用自动确认绕过策略。

主启动器超时后保持 TimedOut，自动辅助脚本不再操作。处理原窗口后先用 Read-CadTestResult.ps1 读取同一轮；不要反复启动新 CAD，也不要删除操作意图以掩盖不确定结果。指定 DLL 的信任请求与 CAD 全局安全设置是不同动作。
