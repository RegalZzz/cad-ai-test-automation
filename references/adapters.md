# 业务接入与断言

## 服务接入

在生成工程加入真实生产项目引用，不复制生产算法。按其可访问性复用服务；internal 优先沿用已有友元测试入口，避免为测试扩大整个公开 API。

```xml
<ItemGroup>
  <ProjectReference Include="..\..\YourPlugin\YourPlugin.csproj" />
</ItemGroup>
```

在 `TestScenario.RunServices(TestContext context)` 内：

```csharp
context.RecordAssembly(typeof(YourBusinessService).Assembly);
// 建立最小场景，提交嵌套事务；调用真实业务服务。
// 新开读事务检查实际实体与属性。
context.Check(independentlyVerifiedCondition, "业务规则及独立预期");
```

`YourBusinessService` 和条件是接入形态，不是默认可执行示例。把 `Scope` 改为实际业务与场景。真实 DLL 以 RecordAssembly 的 Location/SHA256 为准，发现旧版本则结束原测试进程后启动新轮；同进程反复 NETLOAD 新 DLL 不是可靠热替换。

服务如果拒绝外层事务、独立保存图纸或操作多个文档，应按真实语义另建隔离模式，分别记录清理；不能删除模板的检查后继续报告“撤销已验证”。模板约定的服务外层事务不能覆盖所有插件。

## 正式命令接入

先确认生产命令已通过合法 NETLOAD/bundle/需求加载注册和初始化，记录实际业务 DLL。把 `RunCommands` 的 fixture 命令替换为真实全局命令名与完整参数。需要程序选择时可用 `Editor.SetImpliedSelection` 并核对命令 `UsePickSet` 语义。点参数明确 WCS/UCS，内建命令使用国际化选项。

```csharp
// 仅示意；以生产命令真实提示为准。
context.ExecuteCommand("YOUR_GLOBAL_COMMAND", /* complete prompt arguments */);
// 重新查询实际数据库，核对新增、修改、排除和原有对象。
```

`ExecuteCommand` 使用同步 Editor.Command，记录目标命令 Ended/Failed/Cancelled；不支持有未完成提示的交互命令、Session 命令或异步工作。命令执行完成仍需独立数据库断言；只检查返回值或 CommandEnded 不足以证明正确。

异步/排队命令应在真实命令结束事件及后续业务完成信号之后回读并写结果，不把 `SendStringToExecute` 返回当作通过。通过桌面工具验证生产按钮时，在本轮 CAD 窗口中按实际控件操作并核对模型，不把 WPF 事件单测或调用命令类方法当作完整 UI 验收。

## 场景与独立预期

| 场景 | 应核对的结果 |
| --- | --- |
| 实体生成 | 类型、数量、端点/长度/半径、模型或纸空间、图层、颜色和线型 |
| 块与属性 | 块定义/动态块语义、插入点、旋转/比例、属性 TAG/值、既有定义是否被污染 |
| 标注/文字 | 标注对象与几何、文字/样式/高度、比例与注释性、避让和重叠、去重 |
| 过滤 | 当前图层、锁定/冻结/关闭图层、空间、选择集、对象类别和应排除项 |
| 坐标/单位 | WCS/UCS、OCS、块/外参嵌套变换、INSUNITS 和明确单位换算；角度用弧度 |
| 重复执行 | 无重复对象、正确更新本功能产物、保留手工及其他功能产物 |
| 非法输入/取消 | 明确错误/取消、事务清理、无半成品；不仅断言“抛了任意异常” |
| 外部引用 | 使用副本及明确路径重定向、变换只应用一次、源外链哈希与写入目标 |
| 事务回归 | 业务改动的原属性、符号表/字典恢复；句柄集相同不能替代这些检查 |

纯几何逻辑在普通 .NET 测试做边界和参数组合；事务、文档、命令入口留在真实 CAD。最小场景优先固定坐标和明确容差，真实字体、动态块、代理对象或 Object Enabler 用专用 fixture，不能用普通 Line 假装覆盖这些语义。

`SaveEvidenceDrawing` 通过 Wblock 克隆保存到本轮目录，不保存活动输入。导出截图/PNG 时标明是 CAD API 导图还是桌面截图，记录视角、UCS、视觉样式和图层状态；图像仅补充实体断言。
