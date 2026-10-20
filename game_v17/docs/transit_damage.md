# 阶段2-TRANSIT-DAMAGE-1 · 转场 5 舰损管数据层

> 任务 阶段2-TRANSIT-DAMAGE-1（task-106）。工程 `game_v17`。
> 改动：
> - `framework/content/damage_l1.json`：**追加** apsis/ferry/watchtower/deepwell 四舰档案
>   （harmattan 已有档案保持原样，summons_4471 未动）；
> - `scripts/transit_damage.gd`（新）、`tests/transit_damage_probe.gd`（新）、本文件（新）。
> 不改旧 HUD/UI/其他文件；不写 world/V15；未 commit。
> 最小 probe：`PASS=644 FAIL=0`（只跑一次）。

## 1　5 舰档案（每舰 7 分区）

| 舰 | batch | role | 档案 | 分区 |
| --- | --- | --- | --- | --- |
| apsis 远地点 | 1000 | flagship | 新增 | hull/power/propulsion/sensors/comms/tanks/docking |
| harmattan 哈马丹 | 1001 | command | **已有（未覆盖）** | 7 分区 |
| ferry 渡口 | 1002 | escort | 新增 | 7 分区 |
| watchtower 望楼 | 1003 | relay | 新增 | 7 分区 |
| deepwell 深井 | 1004 | tanker | 新增 | 7 分区 |

- 新增档案结构沿用 `damage_l1.json` 既有 schema：`ships.<id>.sections[]`，每分区含
  `id/label/kind/integrity/systems/requires_power/adjacent/repair_s/fire_risk/vacuum_risk`
  （power 含 `power_critical`）；新增舰附 `transit:{batch,role,fleet:"transit_l4_l1"}` 元数据。
- 全局阈值/火灾/失压/断电/维修/效果参数沿用文件既有配置（`state_thresholds/fire/decompression/
  power/repair/effects`），未改。
- 舰间差异（模型值，非武器裁定）：
  - apsis：hull 240s/推进 180s；tanks 110s；docking 140s（旗舰厚壳）。
  - ferry：hull 200s；tanks fire_risk 0.55（弹药）。
  - watchtower：comms 50s、sensors 70s（中继优先）；hull 180s。
  - deepwell：tanks 60s、fire_risk 0.65/vacuum 0.35（油船高风险）；推进 190s。
  - harmattan：保持原档案（hull 180s 等）。

## 2　`transit_damage.gd` API

| API | 说明 |
| --- | --- |
| `TransitDamage.new(content_override := {}, ship_ids := SHIP_IDS)` | 加载内容并初始化 5 舰（`ready/errors/warnings`） |
| `load_models(...)` | 重新加载（旧档案 harmattan/summons 不覆盖） |
| `ship_ids()` / `has_ship` / `batch_for` / `role_for` / `model(ship_id)` | 查询 |
| `step(dt) -> Dictionary` | 推进全部舰（`t/step_count/summary`）；dt≤0 不推进 |
| `vm(ship_id) -> Dictionary` | **只读**：V2DamageModel `vm_damage()` + wrapper 字段（见 §3） |
| `summary() -> Dictionary` | 舰队汇总（每舰 summary/effects/operational + totals） |
| `assign_repair(ship_id, section_id, priority := 2)` | 指派维修（包装 V2DamageModel） |
| `cancel_repair(ship_id, section_id)` / `set_priority(ship_id, section_id, priority)` | 取消/改优先级 |
| `apply_hit(ship_id, section_id, energy, penetration := 0.5, direction, source)` | **显式诊断伤害**（模型不生成武器命中） |
| `reset_ship(ship_id)` / `reset()` | 单舰/全部重建（清事件/队列/资源） |
| `summary_totals()` | 汇总 totals |

所有方法只操作独立 V2DamageModel 实例；不写 world/V15、不触发 HUD。

## 3　VM 字段（`vm(ship_id)`；供后续 transit_hud 消费）

在 `V2DamageModel.vm_damage()`（`schema=damage.v1`）之上追加：

```
ok=true, wrapper_schema="v17_transit_damage.v1", fleet="transit_l4_l1",
ship_id, batch, role, step_count,
weapon_source="none（模型不生成武器/命中；伤害需显式 apply_hit 诊断输入）",
hud_fields=[...],
// 原有 damage vm：
schema/model/content_id, entity_id, name, class, t,
sections[{id,label,kind,integrity,integrity_pct,state,
          fire{active,intensity}, decompression{active,intensity},
          powered, power_loss, requires_power, systems, repair}],
events[], queue[{section,priority,status,progress_s,required_s,remaining_s,
                 progress_pct,reason,team}],
resources{teams_total,teams_busy,spares,spares_used,power,power_max,personnel,personnel_used},
summary{total,integrity_avg,nominal,degraded,damaged,critical,destroyed,
        on_fire,decompressed,unpowered,repairing,queued,needs_attention},
effects{power,sensors,comms,propulsion,docking,fire,decompression,unpowered_sections}
```

`summary()` 顶层：`{schema,fleet,ready,t,step_count,ships[5],totals{...},weapon_source,note}`；
每舰行含 `ship_id/batch/role/name/class/summary/effects/operational`。
`totals` 聚合 5 舰：`ships/operational/nominal/degraded/damaged/critical/destroyed/on_fire/
decompressed/unpowered/repairing/queued/needs_attention/integrity_avg/sections`。

## 4　行为（probe 实测）

- 初始化：5 舰 ×7 分区全 nominal、integrity=1；resources teams/spares/power 就绪；totals
  nominal=35、operational=5。
- 伤害：`apply_hit` 后 integrity 下降、events 记录；HULL 普通伤害 → degraded/damaged。
- 火灾：apsis tanks（fire_risk 0.30）energy 0.9 → 起火、intensity>0、summary.on_fire≥1；
  `step()` 后强度增长并持续损伤。
- 失压：deepwell hull（vacuum_risk 0.25）energy 0.8/pen 0.4 → 失压、summary.decompressed≥1；
  `step()` 持续降低完整度。
- 断电：watchtower power energy 0.6 → power<0.5，requires_power 分区 powered=false、
  summary.unpowered≥1、effects.sensors.available=false。
- 维修：assign_repair 优先级/重复拒绝；step 后 team busy/spares_used/repairing>0、queue 进度；
  cancel（重复取消拒绝）；多舰资源不超 teams_total/spares。
- 确定性：两实例同输入同 step → VM/summary JSON 完全一致。
- 错误：未知舰/分区/取消/优先级安全返回 `ok=false`；reset 恢复 5 舰全 nominal、t=0、queue 空。
- JSON：每舰 VM/summary 可回读；apsis VM ~3.5KB、summary ~4.4KB。

## 5　接入 transit_hud 的字段（本任务不做 HUD）

- 舰队条：`summary().ships[].{ship_id,batch,summary.integrity_avg,summary.on_fire,
  summary.decompressed,summary.unpowered,operational}`。
- 单舰损管页：`vm(ship_id).sections[]`（integrity_pct/state/fire/decompression/powered）、
  `resources`（teams/spares/power）、`queue`（job progress）、`effects`（power/sensors/comms/
  propulsion/docking 可用性）、`events`（最近 64 条）。
- 维修操作：`assign_repair/cancel_repair/set_priority`；诊断/脚本事件用 `apply_hit`。
- 注意：**无武器命中来源**——模型不生成 hit/武器/伤害事件；`apply_hit` 仅显式诊断输入，
  上层需另立武器/伤害来源任务。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/transit_damage_probe.gd
# V17 TRANSIT DAMAGE PROBE RESULT: PASS=644 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：内容档案（6 profiles=旧2+新4；5 舰×7 分区/参数/transit 元数据；harmattan 原档案
未覆盖）；初始化（5 舰 VM/summary/effects/resources）；伤害（普通/火灾/失压/断电传播/毁坏）；
维修（assign/priority/step/cancel/多舰资源上限/未知拒绝）；step/summary 确定性；
错误/reset；JSON 与 hud_fields。

## 7　边界 / 未完成

- **数据层/API only**：不接 HUD/state/bridge；不写 world/V15；未持久化（存档）。
- **无武器命中来源**：`apply_hit` 为显式诊断；没有 missile/beam/碰撞生成器；不判定击沉/战果。
- 舰档案参数为模型值（repair_s/fire_risk/vacuum_risk 等），非工程/真实舰船数据；
  damage_l1.json 全局阈值/效果未改（仅追加 4 舰档案，harmattan/summons 不动）。
- 未跑全量回归；未 commit。
