# 加载确认与打开图纸弹窗

Desktop 启动器从进程启动到退出或超时持续处理以下已知弹窗。图纸打开、测试 DLL 启动以及 `result.json` 写出后仍继续处理；一次确认后立即重新发现窗口，空闲检查间隔为 100 毫秒。

| 弹窗 | 操作 |
| --- | --- |
| DLL 安全提示 | 使用 `-AutoTrustRunner`，直接点击每个提示的“始终加载 / 总是加载 / Always Load”，包括测试入口、依赖和其他功能 DLL |
| 代理信息 / Proxy Information | 选择“显示代理图形 / Show proxy graphics”互斥选项，核验已选中，再点击“确定 / 确认 / OK” |
| 指定字体给样式… / Specify Font… | 选择右侧“大字体”列表第二项，核验选中，再点击“确定 / 确认 / OK”；连续缺失字体重复执行 |
| 缺少 SHX / 缺失字体的前置提示 | 优先点击明确的“指定替换”入口；没有可用替换入口时允许点击明确的“忽略 / 不加载” |
| 选择形文件: … / Select Shape File: … | 按固定标题前缀识别，文件名动态变化；点击“取消 / Cancel”，每次重新发现窗口，连续出现就逐个取消直到不再出现 |

`-AutoTrustRunner` 保留原参数名，但已经覆盖本轮 CAD 中全部符合结构的 DLL 提示，不再比较测试 DLL 的文件名和目录。它会记住各 DLL 的信任决定。明确只需单次加载时用 `-AutoLoadRunner` 点击每个提示的“加载一次”，两个选项互斥。不指定时，字体、代理和选择形文件弹窗仍自动处理，DLL 提示保持待处理。

## 直接操作原生控件

`CadTest.Dialogs.ps1` 用 `EnumWindows` 和 `EnumChildWindows` 按 PID 枚举可见、可用的 `#32770` 对话框，读取其子控件。这个路径同时包含顶层和 CAD 主窗口内的弹窗，无需每轮遍历整个 CAD 的 UI Automation 树。

DLL 提示必须同时包含实际文字为“始终加载”和“加载一次”的按钮；不用猜坐标，也不只凭一个固定 ID 点击。当前 AutoCAD 2020 中文界面已观察到：

| 控件 | 实测值 |
| --- | --- |
| 标题 / ClassName | 安全性 - 未签名的可执行文件 / #32770 |
| 指令 / 内容（原 UIA 观测） | MainInstruction / ContentText；内容分“名称”和“位置”字段 |
| 始终加载 | CommandButton_1001 |
| 加载一次 | CommandButton_1002 |
| 不加载 | CommandButton_1003 |

对实际按钮发送 `BM_CLICK (0x00F5)`。此前实机中 `InvokePattern.Invoke()` 返回后提示仍存在，原生按钮消息才使 DLL 进入 Initialize。每次发送前通过 `GetWindowThreadProcessId`、`IsChild`、`IsWindowEnabled` 核验当前按钮确实属于本轮进程及目标对话框；`SendMessageTimeout` 限制单次消息等待为 5 秒。

字体弹窗以用户提供的“指定字体给样式…”结构为依据：左侧 SHX 字体，右侧大字体。取最右侧可用的原生 `ListBox`，用 `LB_GETCOUNT` 确认至少两项，`LB_SETCURSEL(1)` 选择第二项，通过 `LB_GETCURSEL` 核验；补发 `WM_COMMAND / LBN_SELCHANGE` 让宿主更新字体状态，最后点击确定。记录选中的索引和字体名。代理选项用 `BM_CLICK` 选择，再用 `BM_GETCHECK` 核验，避免未选到目标就确认。

选择形文件弹窗以用户提供的“选择形文件: AAA.SHX”截图为依据。识别固定的“选择形文件 / Select Shape File”标题，允许冒号（含全角）后的任意文件名，不绑定 `AAA.SHX`。定位可用的“取消 / Cancel”原生按钮并发送 `BM_CLICK`，兼容按钮助记符；记录 `CancelShapeFileSelection` 操作。取消后复用同一持续处理循环，即使 CAD 复用窗口句柄但更换缺失文件名，也继续取消下一窗。普通打开、保存窗口中的 SHX 文件名不会触发此操作。

## 运行身份、连续处理与记录

启动器调用 `Handle-CadTestDialogs.ps1`，原 `Approve-CadTestDll.ps1` 入口仍可使用，转调同一处理器：

1. 核验 Launched / Desktop、本轮 DLL 操作选项、PID、开始时间、进程名和可执行文件路径。每次执行动作前重新核验运行身份及冻结的测试 DLL SHA256。
2. 为当前已识别弹窗写 `dialog-actions/<ID>.intent.json`，记录标题、内容、动作和原生按钮 ID / 句柄；进程级互斥锁防止两个处理器同时点击。
3. 直接操作控件，将结果写入 `<ID>.action.json` 和 `dialog-action.pending.json`。消息超时或操作异常时保留不确定状态，停止自动重试。
4. 下一轮以窗口句柄、标题和内容判断旧提示是否关闭或变为新提示。CAD 复用同一窗口显示另一 DLL / 缺失字体 / 形文件时，内容变化仍会触发新操作。同一未变化的提示不重复点击，10 秒仍未关闭或推进就停止本轮启动器并保留证据。

每窗独立记录，连续弹窗不受“一轮只能点击一次”的限制。只有 `started.txt` 证明测试 DLL 进入 Initialize，只有结果与断言证明测试通过。其他业务程序集仍需实际加载路径和 SHA256 证据。脚本不修改 `SECURELOAD`、`TRUSTEDPATHS` 或其他全局加载设置。

## 观测与恢复

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-CadTestDialog.ps1 -RunDirectory 'D:\CadTests\实际运行目录' | ConvertTo-Json -Depth 8
```

诊断脚本保存 `dialogs.latest.json`，包含本轮 PID 下可见对话框的原生控件文字、类名、ID、句柄、可用状态及位置，不点击。未知的许可、修复、保存、外链等提示保留供诊断，不写“遇到弹窗就 Enter”的循环。

主启动器超时后保留 TimedOut 和原进程。处理原窗口后先用 `Read-CadTestResult.ps1` 读取同一轮，不反复启动新 CAD，也不删除意图记录以掩盖不确定结果。新版控件与连续处理的验证范围见 [验证记录](package-validation.md)。
