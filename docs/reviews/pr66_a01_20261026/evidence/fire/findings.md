# PR66 JC-A01 发射授权独立复核

- 被审 HEAD：`1d1e8399da438b77b74acee40d753711c8d2a8f9`；日期2026-10-26，Windows / Godot `4.7.2.stable.official.ed1daf0bf`。
- 范围限原 #58：实际发射授权、真实运行态可用性、命令上下文/重放。不修改生产代码、profile、baseline或GitHub。
- 复用现有 `session_probe.gd` 的 `_unified_cfg/_unified_prepare`：正常 TIGHT、有限8枚导弹、真实解算READY与FIRE授权、实际弹道服务。不是使用未知武器`gun`或尚无物理目标的假正例。
- 独立脚本 `fire_context_audit.gd` 最终退出0表示十组诊断完成，**不是十组都满足拒绝要求**。逐例实际值见 `fire_context_audit.json`；原始输出见同名 `.log`。

## 保留已通过的真实正负对照

| 输入 | 实际结果 |
|---|---|
| 本舰、合法actor/controller/fleet | ok=true、8→7枚、1弹体、1个combat.weapon_launch |
| 未登记shooter | unknown_shooter，8→8、0弹体、0成功事件 |
| 盟军shooter | direct_command_not_permitted，8→8、0弹体、0成功事件 |
| 敌方shooter | shooter_not_authorized，8→8、0弹体、0成功事件 |
| 其他本方舰，combat_runtime=false | shooter_runtime_unavailable，8→8、0弹体、0成功事件 |

这些修复有效，返修不应整项重做。无锚点纯服务会话的 deferred 兼容本分项未证明有实际越权，不建议简单改成全局拒绝来破坏旧单测。

## F1 / P1：请求者actor/controller/fleet未参与实际授权

`game_v17/scripts/core/authority_intel.gd:119–158` 的 `authorize_fire` 仅读 `shooter_id`，检查实例域kind及bool运行标记；完全没有读取传入actor/controller/fleet，也没有使用setup保存的authorized_actors。返回的controller是从shooter域重新填写的，不能证明调用者获得授权。legacy无shooter分支在133–136也直接放行本舰，忽略显式传入的敌方actor。

以同一个合法可射击夹具为对照，每例新建会话，仅改变一个字段：

- `actor_id=opfor_ai`（player域authorized_actors仅[player_ctrl]）；
- `controller_id=opfor_ai`；
- `fleet_id=enemy_fleet`（实例为taskforce）；
- 删除shooter_id走legacy，同时显式传入 `actor_id=opfor_ai`。

四例均授权`ok=true`，最终`request_fire`也`ok=true`、弹药8→7、生成1个真实弹体和1个成功事件。该缺口不是只返回一个错误状态或诊断字符串不全，而是敌方身份请求实际使用了本舰武器。

最小收尾：实际校验来源context→actor白名单→controller/域→fleet/shooter关系，显式非法context不能被legacy缺shooter分支抹去；只在真正无context的兼容调用里绑定可信本舰。保留已有未知/盟/敌shooter拒绝，无需实施友军协同或完整逐舰战斗。

## F2 / P1：一个配置bool可冒充独立战斗运行态，仍扣旗舰账本

`authority_intel.gd:108–110` 从 `own_fleet[].combat_runtime` 直接设置实例可用性；`153`只查该bool。它未绑定任何逐舰CombatService/弹药/解算状态。

合法夹具增加物理实体`second_own`（pos=[10,0,0]），注册本方实例，并仅在own_fleet中写`combat_runtime=true`。session仍只有一个CombatService，`own_id=session_ship`。请求第二舰实际成功，弹体`shooter_id=second_own`且从其[10,0,0]发射，却扣`session_ship`服务的导弹8→7；返回launch_spec的shooter仍是session_ship。对照同舰flag=false则明确unavailable、无副作用。

`game_session.gd:2964`始终调用同一个combat_service，然后在2990附近从指定shooter物理位置发弹。这正是原卡要求避免的“更换发射点却借旗舰账本”。最小收尾是没有真实逐舰运行态绑定时继续返回shooter_runtime_unavailable，不是要求本卡提前实现B1b账本。

## F3 / P2：实际成功命令仍丢失actor/controller/fleet/shooter上下文，重放走legacy

`game_session.gd:2967–2968` 保存的操作仅包含op、target_id、weapon_id、confirmed、salvo。十例中所有成功射击的 `saved_fire_ops` 都证实没有actor/controller/fleet/shooter；`5472–5477` 重放同样只传salvo，回到无shooter的legacy本舰路径。

`5716–5727`审计仅写从auth重新填充的domain/controller、requested/resolved shooter；缺actor与fleet及请求controller，所以F1敌actor与正常控制的成功审计看不出请求者差异。正常例与F1仍各保留真实FIRE授权，不混淆指挥许可与ROE许可。

最小收尾：在版本化操作/事件/审计与重放中保存并使用规范化的授权context（含模拟时刻、actor/controller/fleet/shooter、legacy来源），失败前留拒绝审计；补内存及文件恢复继续后的context对照。此证据只证明context丢失和重放参数缺失，**不冒称当前所有load都失败**，也不要求新建完整战斗系统。

## 复现

工作树根目录：

```powershell
$env:A01_FIRE_OUT=(Join-Path (Get-Location) '.test-results/sol-a01/fire/fire_context_audit.json')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01/fire/fire_context_audit.gd')
```

三个收尾组均属于原#58八段要求。不新开卡、不扩大AI/逐舰战斗范围。脚本正常TIGHT、FIRE授权、有限库存和真实弹体正对照都已实际运行，避免将“未被授权门拒绝但被下游unknown_weapon拒绝”算成合法发射通过。
