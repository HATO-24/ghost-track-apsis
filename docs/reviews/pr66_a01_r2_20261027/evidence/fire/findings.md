# PR66 第二轮：原发射授权十组对照复核

日期：2026-10-26（Asia/Shanghai）。候选：`61f27fc8e841666705b5fd2e843824a03bf6c0b8`。Windows、Godot `4.7.2.stable.official.ed1daf0bf`。

按根代理要求，只原样复跑第一轮 `fire_context_audit.gd` 的10组输入，没有新加边界、没有扩大功能范围。复用既有 `session_probe.gd` 的 `_unified_cfg/_unified_prepare`：TIGHT、有限8枚导弹、真实READY解算与FIRE授权、实际弹道服务。统一导入由根完成；本分项未改生产代码、profile、baseline或GitHub。

## 结果

| 输入（与首轮相同） | 第二轮实际结果 | 副作用 |
|---|---|---|
| 合法本舰 actor/controller/fleet | 成功 | 弹药8→7、1实际弹体、1成功事件 |
| unknown_shooter | unknown_shooter | 8→8、0弹体、0成功事件 |
| ally_shooter | actor_not_authorized | 同上 |
| enemy_shooter | actor_not_authorized | 同上 |
| other_own_unavailable | shooter_runtime_unavailable | 同上 |
| hostile_actor | actor_not_authorized | 同上 |
| wrong_controller | controller_mismatch | 同上 |
| foreign_fleet | fleet_mismatch | 同上 |
| legacy_hostile_actor（缺shooter但显式敌actor） | context_domain_mismatch | 同上 |
| other_own_runtime_flag（配置combat_runtime=true） | shooter_runtime_unavailable | 同上 |

**原F1请求者来源和F2伪运行态借旗舰账本的这批反例均已关闭，保留修复。** 拒绝先后导致盟/敌shooter由新actor检查拦截，结果仍是拒绝且零资源/弹体/成功事件，不要求为了旧理由字符串恢复不安全顺序。

源码对应：`authority_intel.gd:129/200`实际校验context；`:181`开始查调用方注入的runtime集合；`game_session.gd:5802–5811`只从真实现存CombatService.own_id注入，因此第二舰配置bool不能自证运行态。原已通过的显式未知shooter拒绝继续保留。

## 原F3上下文字段缺失：指定症状已关闭

本轮合法真实发射的返回 `authority_context`、保存操作 `saved_fire_ops` 和 `fire_audit` 均实际带上：actor_id=player_ctrl、controller_id=player_ctrl、domain_id=player、fleet_id=taskforce、shooter_id=session_ship、t_s/t=21，另有context_source及legacy_context。拒绝审计也记录requested_actor/controller/domain/fleet/shooter。

对应 `game_session.gd:2980–3003` 成功命令日志/结果和`:5814`审计。静态`:5560–5574`的重放现在从操作恢复actor/controller/domain/fleet/shooter/legacy_context，不再只传salvo回退legacy。**可以关闭“新发射日志/审计没有context、重放只传salvo”的原缺口。** 本窄诊断没有另做动态文件往返，不能把它夸大为整个恢复契约已通过；恢复强校验与总体A01闸门由根代理汇总。

## 作者正例needs_authorization的鉴别

同一旧夹具在第二轮仍能真实成功发射，已具备正常TIGHT、有限库存及真实FIRE grant。由此不能把作者新增probe的`needs_authorization`直接解释成授权设计必须回退，也不能靠关闭正常ROE或无限弹药修正。此分项不改作者探针，只提供可重复的合法正对照。

## 证据与命令

- `fire_context_audit.gd`：原十组脚本，仅输出目录由环境变量指定。
- `fire_context_audit.json`：完整输入、授权结果、库存/事件/弹体、成功命令保存字段与审计。
- `fire_context_audit.log`：原始stdout/stderr。
- `results.json`：简要结构化结果。

```powershell
$env:A01_FIRE_OUT=(Join-Path (Get-Location) '.test-results/sol-a01-r2/fire/fire_context_audit.json')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01-r2/fire/fire_context_audit.gd')
```

脚本退出0表示十组诊断完成；逐例实际数据证实1组成功、9组无副作用拒绝。**不代表移出matrix的作者新探针已通过，不代表整个#58完成，也不抵消根代理新发现的回归。** 本分项已停止扩查。
