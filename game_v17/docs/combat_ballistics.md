# 完整游戏-阶段4G · 战斗弹道 / 拦截闭环

> 任务 task-196。工程 `game_v17`。**只新增 3 个文件**：
> `scripts/core/combat_ballistics.gd`、`tests/ballistics_probe.gd`、
> `docs/combat_ballistics.md`。
> 内容复用 `framework/content/weapons_l1.json`；不改其他；不写 world/TrackTable/UI；未 commit。

## 1　定位

`V2CombatBallistics` 是武器弹道/拦截的**服务层**：

```
weapons_l1.json（railgun/missile/pd/decoy/jammer 参数）
        │
        ▼
V2CombatBallistics
  ├─ launch：railgun/missile 生成 projectile；decoy/jammer 生成 countermeasure
  ├─ step(dt, states)：直线/制导积分、hit radius、PD 自动拦截、诱饵/干扰
  ├─ events：launch/hit/miss/intercept/impact/expired/countermeasure_*
  ├─ impacts：命中记录；damage_event：只输出、不应用
  ├─ predict：提前量/TOF/命中概率（不改变状态）
  └─ save/load/reset/vm/JSON
```

- **位置/速度由调用方每步提供**：`step(dt, states)` 的 `states` 可传
  `{"shooters":{id:state},"targets":{id:state}}`（也兼容扁平 id→state）；
- 不写世界、不写 TrackTable、不写 V15/UI；不直接应用伤害；
- 无舰名/关卡硬编码；仅按武器 id/字段和调用方 id 工作。

## 2　内容复用 / 参数

从 `weapons_l1.json` 读取 railgun/missile/pd/decoy/jammer。缺失参数用服务内
`DEFAULTS` 推衍（可被内容字段覆盖）：

| 参数 | railgun | missile | pd | decoy | jammer |
| --- | --- | --- | --- | --- | --- |
| speed_kmps | 15（内容） | 8（内容） | — | — | — |
| max_accel_kmps2 | — | 0.30 | — | — | — |
| turn_rate_dps | — | 45 | — | — | — |
| max_speed_kmps | speed | 12 | — | — | — |
| hit_radius_km | 0.08 | 0.15 | — | — | — |
| lifetime_s | 120 | 300 | — | 20 | 30 |
| fuel_s | — | 120 | — | — | — |
| intercept_prob | — | — | 0.65 | — | — |
| seduce_prob | — | — | — | 0.65 | — |
| lock_loss_prob | — | — | — | — | 0.20 |

- 弹速/加速度/转向/命中半径均可由武器字段覆盖，不写死舰名；
- PD 使用内容 `range_km/ammo/cooldown_s/intercept_accuracy`，额外 `intercept_prob` 默认；
- decoy/jammer 使用 `duration_s`；诱偏/降锁定为**简化概率**，不伪造真实信号。

## 3　API

```gdscript
const B := preload("res://scripts/core/combat_ballistics.gd")
var b = B.new()                       # 默认读 weapons_l1.json
# 或 B.new({"content": {...}, "pd_platform_id": "own"})

b.setup({...}) -> bool
b.launch(shooter_id, target_id, weapon_id, shooter_state, target_state, opts)
  -> {ok, projectile|countermeasure, projectile_id|countermeasure_id, kind}
b.step(dt, states) -> {ok,t,active_projectiles,intercepts,impacts,events,new_events}
b.predict(shooter_state, target_state, weapon_id, opts)
  -> {ok,schema,weapon_id,mode,time_of_flight_s,lead_point_km,
      lead_offset_km,hit_probability,interceptable,fuel_s,range_km}

b.active_projectiles() / b.projectiles_all()
b.intercept_records() / b.impact_records() / b.pd_state()
b.vm() / b.summary() / b.to_dict() / b.to_json()
b.events / b.events_since(seq) / b.take_events()
b.save_state() / b.snapshot() / b.load_state(json_or_dict)
b.reset()
```

- `launch` 只接受 `kinetic`/`guided`（生成 projectile）与 `decoy`/`ew`
  （生成 countermeasure）；`point_defense` 为自动，返回 `pd_is_automatic`；
- 失败 reason：`not_ready/unknown_weapon/invalid_state/empty_shooter/empty_target/
  out_of_range/inside_min_range/missing_speed/pd_is_automatic/weapon_not_launchable`；
- `opts`：
  - `aim_error/aim_error_km`：railgun 瞄准偏差（测试/压制误差）；
  - `force_decoy/force_jam/force_pd`：确定性测试钩子（生产不强制）；
- `states` 每步可更新；目标丢失时使用最后已知位置。

## 4　物理模型

### 4.1 railgun

- 直线弹道，速度恒定（内容 `speed_kmps`）；
- 发射时对目标（含速度）迭代提前量：`t = |lead - shooter| / speed`，
  `lead = target_pos + target_vel * t`；
- 每步段-球检测：`segment(prev, new)` 到目标位置距离 ≤ `hit_radius + target.radius`；
- 命中记录 `ballistic_impact.v1`，并生成 `combat_damage_event.v1`
  （`damage/penetration/damage_kind/hit_point_km`，`applied=false`）；
- 超时/超程/偏差 → `miss`/`projectile_expired` 事件，不生成伤害。

### 4.2 missile

- 制导追踪：目标方向 → 转向率限制 → 最大加速度/最大速度 → 位置积分；
- `fuel_s` 递减；燃料耗尽后变 ballistic，不再转向；
- `lifetime_s` 到期 → 失效/miss；
- proximity fuse：每步段-球检测 `hit_radius + target.radius`；
- 可被 PD 拦截（`interceptable=true`）；
- `decoy`：目标方 countermeasure 存在时按 `seduce_prob` 将 missile 目标点
  改为 decoy 位置（`decoyed`/`guidance_lost`），命中 decoy 只记 `DECOY_IMPACT`；
- `jammer`：目标方 countermeasure 存在时按 `lock_loss_prob` 使导弹丢失制导
  （`guidance_lost`），后续直线飞行，降低命中。

### 4.3 PD

- 每个 step，在 `states.shooters[_pd_platform_id]`（默认 `own`）有
  `has_pd=true` 时自动尝试拦截；
- 目标为 `_pd_platform_id` 的 missile 且位于 PD `range_km` 内；
- 每次最多一发；消耗内容 `ammo`、设置 `cooldown_s`；
- 命中概率 = `intercept_prob × (1 - 0.5*dist/range)`（下限 `range_factor_min`），
  确定性 roll；
- 成功：`ballistic_intercept.v1`（`intercepted=true`）+ `projectile_intercepted`；
  失败：missile 继续；对拦截弹/普通 projectile 只处理 `interceptable`；
- PD 状态 `pd_state()`：ammo/ammo_max/cooldown_until/cooldown_remaining_s。

### 4.4 decoy / jammer

- `launch(...,"decoy"/"jammer",...)` 生成 countermeasure：
  `{kind, owner_id, pos_km, deployed_t, active_until, active, seduce_prob/lock_loss_prob}`；
- 过期自动失效并事件；
- 简化概率，不生成真实射频/假回波；不写世界。

## 5　事件 / 记录 / damage

- events schema `ballistics_event.v1`：
  `{seq,t,kind,payload,shadow,writes_v15:false}`；
  kind：`launch/projectile_expired/projectile_intercepted/impact/miss/
  pd_launch/countermeasure_deployed/countermeasure_expired/ballistics_ready`；
- `intercepts[]` schema `ballistic_intercept.v1`：
  `{intercept_id,t,projectile_id,target_id,platform_id,weapon_id,distance_km,
  chance,roll,intercepted,ammo_left}`；
- `impacts[]` schema `ballistic_impact.v1`：
  `{impact_id,t,projectile_id,shooter_id,target_id,weapon_id,kind,pos_km,
  miss_distance_km,shot_id}`；
- 命中同时生成 `combat_damage_event.v1`：
  `{shot_id,target_id,source_id,weapon_id,damage,penetration,damage_kind,
  hit_point_km,source:"combat_ballistics",applied:false,writes_v15:false}`；
  只输出，调用方/损管决定是否应用。
- 未命中：`miss` 事件 + `projectile_expired`；不产生 damage。

## 6　存档 / 重置

- `save_state()` schema `v17.combat_ballistics_save.v1` v1.0.0：
  t、projectiles、countermeasures、intercepts、impacts、events、pd(ammo/cooldown)、
  seq；`load_state` 校验 schema/version/数组，失败不改状态；
- `reset()` 清空 projectiles/countermeasures/intercepts/impacts/events、t=0、
  PD 弹药恢复、seq 重置；
- JSON-safe、确定性；相同输入/命令序列 VM/events 一致。

## 7　接入 / 边界

- **输入**：调用方每步提供 shooter/target `pos_km`/`vel_kmps`/`radius_km`/
  `has_pd`；服务不查询 world/TrackTable/传感器。
- **输出**：impact/damage events 交上层损管/物理；本服务不写 world/V15/UI；
  PD/诱饵/干扰只输出状态/事件，不改变外部实体。
- **与 CombatService 区分**：CombatService 负责 ROE/授权/火控解算与命中概率接口；
  本服务负责可推进的弹道/PD/反制物理闭环。两者可串联，但本文件不依赖其内部状态。
- 不实现：真实轨道摄动/引力/相对论、雷达截面/引信细节、PD 弹丸独立弹道、
  多目标饱和分配、真实电子战波形、传感器锁定链路；PD/诱饵/干扰为抽象概率模型。
- 不做舰名/关卡/剧情硬编码；无 UI/存档文件 I/O；无世界写。
- probe 304 checks（内容/预测/railgun 命中/miss/提前量/多弹、missile 制导/
  燃料/寿命/移动目标、PD 拦截/射程/弹药/冷却/概率、诱饵/干扰、存档/重置/
  JSON/确定性/不写）；只单次运行，未跑全量回归。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ballistics_probe.gd
# BALLISTICS PROBE RESULT: PASS=304 FAIL=0
# BALLISTICS PROBE OK（退出码 0）
```
