# PR66 第三轮：原 R3 / R4 情报侧闭环复核

日期：2026-10-27（Asia/Shanghai）。候选 `8b4cf990021bafe0f5b2945039c850b5c985cf5a`。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。

本轮只核验上轮原R3/R4剩余：selected/详情、共享实际到达/幂等/在途恢复，以及已冻结每owner融合生命周期是否等价运行。未添加AI/EW、字段穷举或新的产品范围；未修改生产代码、GitHub、baseline。

## CLOSED：selected / 实体详情的全局航迹绕过

`owner_lifecycle_audit.gd` 复用前两轮合法盟军sensor output，经真实 `_advance_sensors` 路由。全局TrackTable仍存在盟军私有T0001，但在player owner无该观测时：

- `binder.selected_track({track_id:T0001}) == {}`。
- `binder.selected_entity({track_id:T0001,entity_id:ally_private_contact}) == {}`。
- 本方合法 `local_contact` 直接观测正例可读到range111、owner=player_intel；实体详情只返回owner限定的安全投影。

修复位置：`game_v17/scripts/ui/shell_binder.gd:977–1025` 的 `selected_entity` / `selected_track`。这项旧绕过已关闭，不再要求整项重做。前轮已关闭的空绘图不回退真值、contacts不补全局实体仍保留结论，本轮没有重新扩查它们。

证据：`owner_lifecycle_audit.{gd,json,log}` 的 `selected.closed=true`。脚本退出0表示这一组selected对照成功，并不表示下述生命周期已经完成。

## 原 R3 仍未闭环：没有运行每owner的 stale / forget 生命周期

判定依据是原卡要求的融合/衰减行为，**不是要求必须使用某个类名**。合同 `game_v17/docs/contracts/joint_campaign_r2.md` §8.2 冻结 `per_owner_track_table`；原卡和总队列要求各owner保留独立融合/衰减状态，不能只在全知融合后过滤UI。

最小对照：同一真实GameSession，去掉自动sensor输入，只接收一次t=0的 `aging_contact` 观测；其余时间不补新观测。相同range500/quality0.8输入分别进入当前owner facade与现有全局TrackTable，当前TrackTable配置是stale30s、forget300s。

| 会话时刻 | 既有TrackTable对照 | player owner实际可读航迹 |
|---|---|---|
| 0s | 存在，stale=false | 存在，last_observed_t=0、quality0.8 |
| 31s | stale=true | 无任何stale标记，原字段完全不变 |
| 301s | 已移除 | 仍存在，range500、quality0.8、last_observed_t=0 |

两次真实 `session.tick(31)` / `tick(270)` 均ok。`authority_intel.gd:271–363` 接收时仅覆盖普通字典；本候选 `GameSession._advance_components`（`game_session.gd:1455`）仍只推进全局TrackTable，没有owner生命周期推进。动态结果说明当前尚未以等价机制实现已有老化语义。这里不另设新产品阈值；若owner另有策略，需在原合同下明确并实际运行，而不是把永不老化的字典称为完成。

证据：`owner_lifecycle_audit.json` 的 `lifecycle.timeline`、`global_forgotten=true`、`owner_retained_after_forget=true`。此项仍属原R3融合/衰减收尾，不能因selected安全修复而自动关闭。

## CLOSED（窄项）：正常共享实际到达与重投幂等

`share_continue_audit.gd` 采用当前shipped probe同一三域seed、3秒Comms链路。t=2发出 `PENDING-ONE`：

- 原连续会话发出后、t=3/4均不可见，t=5实际到达后接收owner才有航迹。
- 原始观测时刻保留2，接收时刻5，实际delay3。
- 第三方opfor owner始终为空。
- 同一delivery/observation重投返回duplicated=true，观测数量1→1。

`normal_arrival_closed=true`、`duplicate_closed=true`。保留这部分实际修复，不再说共享callback完全未接线。

## 原 R4 / 恢复连续性仍未闭环：在途共享恢复后提前可见

同一消息发出后、仍在t=2时保存，立即加载到另一个真实GameSession，并同步推进两会话：

1. 保存前Comms队列含1条，`arrive_t=5`；共享待融合表也有C-000001。
2. load返回ok=true，待共享表恢复1条，但实际 `restored.comms.pending=[]`。
3. 首个恢复tick到t=3，`_reconcile_standalone` 因未见Comms在途项将其当作到达并调用共享融合；恢复会话已可见，原连续会话仍不可见。
4. 原会话到t=5才正常可见。最终两者虽然都有相同target，但 `last_received_t` 分别5与3，时间/时延与可见轨迹已经分歧。

所有tick均ok，不能用退出/最终target集合一致代替按tick恢复等价。`game_session.gd:_reconcile_standalone` 当前把“pending消失”解释为送达；保存的共享索引不能替代实际Comms在途状态。建议在原R4/读档连续性范围恢复真正消息队列/ETA并保留实际投递结果，避免提前融合；无需扩大完整协同协议。

证据：`share_continue_audit.{gd,json,log}`：`continuation_equal=false`，t3原ids=[]/pending1，恢复ids=[pending_contact]/pending0；`before.comms_pending`含ETA5，`restored_before.comms_pending=[]`。当前脚本最终退出 **1**，专门由这个真实继续分歧使其为红；正常到达与幂等两个闭环标志仍为true。

## 运行与停止边界

根代理统一导入完成后执行。没有重复full/shipped probe，也没有继续扩查。原始ObjectDB/资源退出清理stderr保留，不与上述业务结果混淆。最后只重跑共享脚本以使退出码严格对应逐tick连续性，而非只看最终两个target都存在。

```powershell
$env:A01_R3_OWNER_OUT=Join-Path (Get-Location) '.test-results/sol-a01-r3/intel/owner_lifecycle_audit.json'
$env:A01_R3_SHARE_OUT=Join-Path (Get-Location) '.test-results/sol-a01-r3/intel/share_continue_audit.json'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01-r3/intel/owner_lifecycle_audit.gd')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01-r3/intel/share_continue_audit.gd')
```

结构化汇总：`audit_results.json`。本分项现已停止检查，主要实现继续交DeepSeek。
