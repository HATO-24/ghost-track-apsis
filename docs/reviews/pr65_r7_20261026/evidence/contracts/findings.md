# PR65 R7 K0 独立窄复核

- 日期：2026-10-26 Asia/Shanghai；候选 `2ae7bf7cba8af32ff4456cefe28efa3650b868dd`。
- 本次只审合同，不实现生产服务或 AI。Godot `4.7.2.stable.official.ed1daf0bf`，Windows。
- 自带 `jc_contracts_probe.gd` **78 PASS / 0 FAIL，退出 0**，见 `probe.log`。
- 独立 `mutations.gd` 退出 0 表示诊断完成；每行 `ok` 才是该载荷接受/拒绝结果，不能把诊断退出码当全部通过。

## 已关闭，保留修复

1. 将 I-A2 置未选、DRAFT、移出部署后作 shooter：正确拒绝（未被选中、未部署）。`jc_contracts.gd:449–454`。
2. observer=I-OP1 却自报 player_intel、自授权：正确拒绝（原始 owner 不同）。`:313–335`。
3. 部署 t=-5：正确拒绝；当前 DEPLOYED 却记录 DRAFT→VALIDATED：正确拒绝。`:263–273`。
4. 缺 command_id：正确拒绝。`:377–384`。
5. 合法 ally→player 延迟共享 OBS-3 在正常 fixture 通过；回执/执行 request_id 改成其他值正确拒绝。`:410–419`。

## 原合同冻结与本轮声明仍不一致

1. **seq 未必填**：删除 `commands[0].seq`，仍 `ok=true, errors=[]`。`:389–391` 只在非 null 时检查。这与源码 `:385`“需要事件 ID/seq”及 R7 报告新增 seq 的冻结口径不一致。补必需性及对应拒绝，或先明确规范允许无 seq 的合法用途；不能边声称冻结完整标识边默许缺值。
2. **未知 lifecycle_version 接受**：把版本改 `UNSUPPORTED-999` 仍 `ok=true`。`:396–397` 只查非空，未标识唯一受支持版本。应将版本身份/拒绝策略写入合同并验证，不需实现运行态生命周期。
3. **跨 owner 接收字段默许缺失**：删除 OBS-3 的 `received_by_intel_owner_id` 仍 `ok=true`，`:338` 默认使用 `intel_owner_id`。R7 报告 `JC_R7_repair_report.md:63` 却明确该字段“必须存在”；源码注释 `:337` 同样声称跨 owner 必须声明。此处是声明/实现不一致，选择一个明示的规范后保持正负例一致；不要求添加新权限服务。
4. **正式合同文档未同步**：`game_v17/docs/contracts/joint_campaign_r2.md:181–184`（§8.2）仍说授权者必须等于该 `intel_owner_id`，但新增合法 OBS-3 接收 player_intel、由原始 ally_intel 授权。字段表也没有新 event_id/seq/lifecycle/receiver 定义，退出统计仍 39/0、64/0。请归一当前合同，旧口径如保留需显式标历史；这仍是原 #57 字段/写者/读者/单位/时间/可见域冻结交付。

## 非阻塞观察，避免范围扩大

窄诊断还记录反向 lifecycle 时间、receipt=rejected 但 execution=completed、两个不同 command_id 共用 event_id/seq/request_id 均接受。当前原卡未精确冻结这些全部组合，不在本轮另增前置运行态要求；建议在合同中定义其合法性，再决定后续校验。

legacy self-declared own=I-A2 仍通过，和 R6 一样只证明 own 与 shooter 字符串一致，不能证明可信本舰锚点。本轮不擅自指定旗舰，不把它判作生产游戏已越权。现 fixtures 仍无单独旧档缺 campaign/fleet/instance 的迁移夹具；需要在合同冻结时说明由谁提供可信 ownship 与旧输入适配口径。旧调用语义测试存在（正常 `own_ship` 与拒绝 `all_allies`），不要将其写成完全未测。

## 复现

在候选工作树根目录：

```powershell
$env:JC_K0_AUDIT_OUTPUT = (Join-Path (Get-Location) '.test-results/r7-k0-audit/mutations.json')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script (Join-Path (Get-Location) '.test-results/r7-k0-audit/mutations.gd')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'res://tests/jc_contracts_probe.gd'
```

证据：`mutations.gd` / `mutations.json` / `mutations.log` / `probe.log`。未修改生产文件、baseline、阈值或 Github。
