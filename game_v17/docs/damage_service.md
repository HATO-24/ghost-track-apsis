# 完整游戏-阶段2K · DamageService 损管服务

> 任务 完整游戏-阶段2K（task-146）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/物理；未 commit）：
> - `scripts/core/damage_service.gd`
> - `tests/damage_service_probe.gd`（`PASS=319 FAIL=0`）
> - 本文件
> 每舰组合既有 `V2DamageModel`（`framework/core/damage_model.gd`），不重写伤害模型。

## 1　定位 / 数据流

```
damage_l1.json（ships 档案：7 分区/阈值/火灾/失压/维修/效果）
        │
        ▼
DamageService
 ├─ ships: {ship_id -> V2DamageModel}   （每舰独立状态/维修队列/资源）
 ├─ apply_combat_damage(combat_damage_event.v1) → 分区伤害/火灾/失压/断电
 ├─ repair/fix/priority/cancel → V2DamageModel 损管
 └─ tick → 火灾/失压/断电/维修队列推进
        │
        ▼
VM/summary/events/save（只读；不写 UI/物理/world/V15）
```

- 输入 `combat_damage_event.v1`：`{shot_id,target_id,damage,penetration,damage_kind,
  suggested_section,...}`；可带 `target_ship`/`section`/`direction`。
- 舰船映射：`target_ship`/`ship_id`/`opts.ship_id`；`target_id` 恰为舰 id 时直接使用；
  否则使用 `default_ship`（GameSession 会结合 combat track 的 `ship_id` 传入）。
- 分区：`section` > `suggested_section` > `damage_kind` 映射
  （kinetic/fragmentation→hull，explosive→power，energy→sensors，thermal/fire→tanks）。
- 命中只写 DamageService/model；不写 world/V15，不产生物理/UI。

## 2　API

| API | 说明 |
| --- | --- |
| `DamageService.new(cfg)` / `setup(cfg)` | cfg：`content_path`/`content`/`ships[]`/`default_ship`/`t` |
| `validate_content(data)` | 校验 damage content（schema/ships/sections/repair/effects） |
| `ship_ids_list()` / `model(id)` / `is_operational(id)` | 舰列表/模型/可运作 |
| `apply_combat_damage(event, opts={})` | 应用 combat damage event；成功 `{ok,applied:true,ship_id,section,hit,summary,effects,new_events,damage_event}`；失败不改状态 |
| `apply_hit(ship_id, section, energy, penetration=0.5, direction="fore", source="manual")` | 直接伤害（内部同 apply_combat_damage） |
| `repair(ship_id, section, priority=2)` / `fix(...)` | 指派维修（queued；完成由 tick 推进） |
| `cancel_repair(ship_id, section)` / `set_priority(ship_id, section, priority)` | 取消/调整优先级 |
| `tick(dt)` | 推进所有舰模型（火灾/失压/断电/维修）；返回 per-ship summary |
| `vm(ship_id="")` / `ship_vm(id)` / `summary()` | 只读 VM/summary |
| `events` / `events_since(seq)` / `take_events()` | `damage_service_event.v1` |
| `save_state()` / `load_state(json)` | 内存 JSON（每舰 sections/queue/resources/events/seq/t 快照） |
| `check_contracts()` | model ready/t/integrity/资源非负 等不变量 |

失败 reason：`not_ready/invalid_event/invalid_damage/unknown_ship/invalid_section/
apply_failed/invalid_dt/invalid_schema/unsupported_version/invalid_payload/...`；
失败不部分写入（load 先全量校验再应用）。

## 3　伤害 / 火灾 / 失压 / 断电

- 伤害由 `V2DamageModel.apply_hit` 计算：装甲/穿透/溢出相邻分区/状态阈值；伤害值能量
  模型范围 0..1（超界 clamp）。
- 火灾：分区 `fire_risk>=0.2` 且能量≥阈值时点燃；tick 增长强度、损伤、可能蔓延。
- 失压：`vacuum_risk>=0.2` 且能量≥阈值（hull/tanks 穿透要求较低）触发；tick 发展。
- 断电：power 分区受损/毁坏 → `_update_power` 影响 requires_power 分区；effects
  `power.available`/`unpowered_sections`；power/hull 毁坏 → `operational=false`。
- 维修到 1.0 会清火/清失压；destroyed 分区不可现场修复。

## 4　维修资源

使用 damage content `repair`：`teams_total`、`spares`、`power`、`personnel` 等；
`V2DamageModel` 负责排队/团队上限/备件/电力/人员消耗；`DamageService` 只做多舰
调度 + 事件 + 存档。`fix` 与 `repair` 等价（现场维修指派）。

## 5　事件（`damage_service_event.v1`）

`damage.applied`（ship/section/damage/penetration/shot_id/new_events/summary）、
`damage.repair_queued`、`damage.repair_cancelled`、`damage.repair_priority`、
`damage.tick`；`{seq,t,kind,detail,writes_v15:false}`。GameSession 会把这些事件
以同名 `damage.*` 发布到 EventBus。

## 6　存档

```text
{
  schema:"v17.damage_service_save.v1", version:"1.0.0",
  content_path, t, event_seq, ship_ids, default_ship,
  ships: {ship_id: {t, sections[], events[], queue[], resources{},
                    last_effects{}, team_seq, hit_seq}},
  applied_damage[], events[]
}
```

`load_state`：校验 schema/version/ships/sections/integrity/resources，先全量校验
所有已配置舰快照，再应用；失败不改当前状态。load 后可继续 tick/维修；再次 save 一致。

## 7　GameSession 集成（另见 `game_session.md`）

- boot `damage_service`（true 或配置 `{ships[],default_ship,content_path}`）→ 可选组合。
- session tick：`combat_service.tick` → 取 combat outbox，白名单提取
  `combat_damage_event`（`combat_hit`/`incoming_impact` payload.damage_event）→
  `damage_service.apply_combat_damage`（`applied=true`），再 `damage_service.tick(sim_dt)`。
- `request_fire` 命中时立即路由 damage event（`shot_id` 去重，避免 tick flush 二次应用）；
  combat track 的 `ship_id` 决定受损舰（否则 default_ship）。
- session API 委托：`damage_apply_event/apply_hit/repair/fix/cancel_repair/set_priority/
  damage_vm/damage_ship_vm/damage_summary/damage_ships`；save 嵌入 damage 快照，
  旧存档缺字段 → 组件退化、replay 操作跳过。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/damage_service_probe.gd
# V17 DAMAGE SERVICE PROBE RESULT: PASS=319 FAIL=0（exit 0，只跑一次）
```

覆盖（9 节）：setup/内容/子集/default_ship/非法配置；combat damage event（分区/映射/
default/opts/非法拒绝/applied）；分区伤害/火灾/失压/断电/毁坏/不可运作；维修（指派/重复/
资源/队列/tick/恢复/cancel/fix）；优先级/teams/资源；tick 同步/非法 dt/火灾失压推进/多舰；
save/load 一致+继续+非法拒绝；事件/JSON/ship_vm/确定性；批量矩阵（6 舰/7 分区/6 kind/
5 舰存档/7 维修队列/teams 上限）。

## 9　边界 / 未完成

- 不写 UI/物理/world/V15；伤害模型沿用既有 V2DamageModel，不重写弹道/命中判定。
- 服务只做多舰组合/入口/事件/存档；命中概率由 CombatService 决定，damage event 由上层应用。
- 不自动维修完成（tick 推进模型维修进度）；不自动修复 destroyed。
- 舰船映射目标为 `target_ship`/default；无完整 identity/阵营规则（由上层传入）。
- 存档仅内存 JSON；无文件槽位；未跑全量回归；未 commit。
