# 完整游戏-阶段4G · 战斗弹道 / 拦截闭环（R6 物理化 · v2）

> 工程 `game_v17`。核心文件：`scripts/core/combat_ballistics.gd`、
> `tests/ballistics_probe.gd`、本文件。
> 内容复用 `framework/content/weapons_l1.json`；不写 world/TrackTable/UI；不应用伤害。
> **v2 变更**：接口层概率 → 可推进的物理闭环（CR3BP RK4 + 射击法 + 引导头 + 齐射 + 巡航剖面）。

## 1　定位

`V2CombatBallistics` 是武器弹道/拦截的**服务层**，只回答一个问题：
**弹出去以后怎么飞、怎么锁、怎么被打掉、打在哪。**

```
weapons_l1.json（railgun/missile/pd/decoy/jammer 参数）
        │
        ▼
V2CombatBallistics
  ├─ launch：railgun/missile → projectile（含齐射展开）；decoy/jammer → countermeasure
  ├─ step(dt, states)：子步积分 → 引导头状态机 → PN 末制导 → 引信/命中 → PD → 对抗
  ├─ predict / solve_aim：射击法解算瞄准点（不改变状态）
  ├─ events：launch/salvo_launch/waypoint_dv/seeker_lost/impact/miss/
  │           projectile_expired/projectile_intercepted/pd_launch/
  │           countermeasure_deployed/countermeasure_expired/ballistics_ready
  ├─ impacts / intercepts：记录；damage_event 只输出、不应用
  └─ save/load/reset/vm/JSON
```

- **位置/速度由调用方每步提供**：`step(dt, states)` 的 `states` 支持
  `{"shooters":{id:state},"targets":{id:state}}`，也兼容扁平 `id→state`；
- 不写世界、不写 TrackTable、不写 V15/UI；不直接应用伤害；
- 无舰名/关卡硬编码；只按武器 id/字段和调用方 id 工作。

### 与 CombatService 的分工

| | CombatService | CombatBallistics |
| --- | --- | --- |
| 职责 | ROE / 授权 / 火控解算排队 / 弹药 / 齐射参数 | 弹道积分 / 引导头 / 引信 / 点防 / 对抗 |
| 命中 | **不再判定**（`physics:"deferred"`） | 由 `impact`/`miss` 事件异步决定 |
| 时间 | `t` 跟随会话 | `t` 跟随会话（同一时钟） |

统一入口是 `GameSession.request_fire()`：门禁 → 真实发射 → 异步命中。

## 2　内容复用 / 参数

从 `weapons_l1.json` 读 railgun/missile/pd/decoy/jammer；缺失字段由服务内
`DEFAULTS` 推衍（可被内容覆盖）。嵌套字典（`seeker`/`profile`）走深度合并，
内容里只写要覆盖的键即可。

| 参数 | railgun | missile | pd | decoy | jammer |
| --- | --- | --- | --- | --- | --- |
| speed_kmps | 15 | 8 | — | — | — |
| max_accel_kmps2 | — | 0.30 | — | — | — |
| turn_rate_dps | — | 45 | — | — | — |
| max_speed_kmps | speed | 12 | — | — | — |
| hit_radius_km | 0.08 | 0.15 | — | — | — |
| proximity_fuse_km | 0.0 | 0.35 | — | — | — |
| frag_damage | 1.0 | 0.35 | — | — | — |
| lifetime_s | 120 | 900 | — | 20 | 30 |
| fuel_s / boost_s | — | 120 / 8 | — | — | — |
| salvo_spread_deg | 0.05 | 0.15 | — | — | — |
| seeker | — | radar_active 400km/60°/2.5s/1.5s/0.85 | — | — | — |
| profile | — | waypoints[]/terminal_acquire_km 800/seeker_off_until_km 0 | — | — | — |
| intercept_prob | — | — | 0.65 | — | — |
| seduce_prob | — | — | — | 0.65 | — |
| rcs_m2 / ir_signature | — | — | — | 2200 / 0.9 | — |
| power / range_km | — | — | — | — | 1.4 / 5000 |

- **Δv 预算**：`dv_budget = max_accel_kmps2 × fuel_s`。导弹所有机动（含航路点脉冲）
  都从预算里扣；预算耗尽即不再有推力（末制导过载独立限幅）。
- 齐射数上限由 `salvo_max` 决定（railgun 1 / missile 4），**不由本服务拒绝**——
  弹药与齐射数的门禁在 CombatService。

## 3　API

```gdscript
const B := preload("res://scripts/core/combat_ballistics.gd")
var b = B.new()                       # 默认读 weapons_l1.json
# 或 B.new({"content": {...}, "pd_platform_id": "own"})

b.setup({...}) -> bool
b.solve_aim(shooter_state, target_state, weapon_id, opts)
  -> {ok, aim_km, time_of_flight_s, residual_km}
b.predict(shooter_state, target_state, weapon_id, opts)
  -> {ok, schema:"ballistic_prediction.v1", mode:"ballistic"|"guided",
      trajectory:"cr3bp_shooting"|"cr3bp_pn", model:"cr3bp_rk4",
      time_of_flight_s, aim_km, lead_point_km, lead_offset_km, residual_km,
      dv_budget_kmps, fuel_s, hit_probability, error_km, seeker{...}}

b.launch(shooter_id, target_id, weapon_id, shooter_state, target_state, opts)
  # 单发
  -> {ok, projectile_id, projectile, kind}
  # 齐射（opts.salvo > 1 时内部展开）
  -> {ok, salvo_requested, salvo_launched, projectile_ids, failed, kind}

b.step(dt, states) -> {ok, t, substeps, active_projectiles, intercepts,
                       impacts, events, new_events}
b.active_projectiles() / b.projectiles_all()
b.intercept_records() / b.impact_records() / b.pd_state()
b.vm() / b.summary() / b.to_dict() / b.to_json()
b.events / b.events_since(seq) / b.take_events()
b.save_state() / b.snapshot() / b.load_state(json_or_dict)
b.reset()
```

- `launch` 只接受 `kinetic`/`guided`（生成 projectile）与 `decoy`/`ew`
  （生成 countermeasure）；`point_defense` 自动，返回 `pd_is_automatic`。
- 失败 reason：`not_ready / unknown_weapon / invalid_state / empty_shooter /
  empty_target / out_of_range / inside_min_range / missing_speed /
  pd_is_automatic / weapon_not_launchable / salvo_requires_offensive_weapon /
  insufficient_dv / salvo_all_failed`。
- `opts`：
  - `salvo`：齐射数（>1 走齐射展开）；
  - `profile`：单发巡航剖面覆盖；`profiles`：齐射逐发剖面覆盖（数组，按 index 取）；
  - `intent`：仅记录意图，规划由 `V2CombatPlanner` 生成 profile；
  - `force_decoy / force_jam / force_pd`：确定性测试钩子（生产不强制）；
  - `aim_error / aim_error_km`：railgun 瞄准偏差（测试/压制误差）。

## 4　物理模型

### 4.0 积分器与子步

- 坐标系 **bary_rot（CR3BP 旋转系）**，与 `physics_world` 一致：
  `V2CislunarPhysics.acceleration_rot()` 给引力 + 科氏 + 离心；
- 弹道积分统一走 `rk4_step_accel(state, dt, extra_accel)`，导弹推力/PN 过载作为
  `extra_accel` 叠加（实弹 `extra = ZERO`）；
- `step(dt)` 内部切子步：`SUBSTEP_MAX_S = 1.0s`、`MAX_SUBSTEPS = 256`
  （时间倍速下的算力护栏）。子步长决定引信判定与引导头时序的分辨率。

### 4.1 railgun（实弹）

- 出膛速度恒定（内容 `speed_kmps`），无推力；
- 发射时用**射击法**解算瞄准点：迭代"试射 → 比对终点与目标预测位置 →
  修正发射方向"，吃掉 CR3BP 下的科氏/引力偏折
  （`SOLVE_ITER = 4` 次 × `SOLVE_COARSE_STEPS = 24` 步粗积分）；
- 典型量级：15 km/s、1000 km 射程，**不修正会偏 256 m，射击法后残差 ~80 m 量级**；
- 每子步做段-球检测：`segment(prev, new)` 到目标距离 ≤ `hit_radius + target.radius`；
- 命中 → `ballistic_impact.v1` + `combat_damage_event.v1`（`applied=false`）；
- 超时/超程/偏折过大 → `miss` / `projectile_expired`，不产生伤害。

### 4.2 missile（独立飞控 + 引导头）

**飞行阶段**（`phase`）：

```
BOOST ──(boost_s)──> MIDCOURSE ──(进入 terminal_acquire_km)──> TERMINAL
                                                                  │
                                                       丢锁 > break_s
                                                                  ▼
                                                          TERMINAL_LOST
```

**飞控**：姿态向量 `attitude` 限转向率 `turn_rate_dps` 转向期望方向；
推力只在 BOOST / MIDCOURSE 加速段生效，且受 `max_speed_kmps` 与 Δv 预算双重约束；
TERMINAL 段改用 PN 过载（不再用主轴推力）。

**比例导引 PN**：`N = 3.5`，加速度 `a = N × Vc × λ̇`，受 `max_accel_kmps2` 限幅。
丢锁后走 `_inertial_dir()`——**用最后锁定点外推，不读实时目标位置**，
这样干扰/诱饵才真的有效。

**引导头状态机**（`SEEKER_STATES`）：

```
SEARCH ──进入 eff_range 且 margin ≥ break_margin，持续 acquire_s──> ACQUIRE
ACQUIRE ──(累计时间到)──> TRACK
TRACK ──margin < break_margin 持续 break_s──> LOST ──(回滞恢复)──> SEARCH
```

- 四态 + 滞回（`break_margin` 默认 0.85），避免"每步掷骰"式的假丢锁；
- 有效作用距离按**距离方程**：
  - `radar_active`：`R ∝ RCS^0.25 / (1 + jam_ratio)`
  - `ir_passive`：`R ∝ I^0.5`（不受雷达干扰压制）
  - `arm`（反辐射）：不受压制，按辐射源强度
- 诱饵作为**竞争候选**参与 `_pick_track`：谁的回波更强就锁谁；
- `seeker_off_until_km > 0` 时引导头静默到该距离才开机（静默接近）。

**引信**：`proximity_fuse_km` 内触发，伤害按 `frag_damage` 系数打折；
命中方位由相对速度几何推导（`fore/aft/port/starboard/dorsal/ventral`），
交给 DamageService 映射到舱段。

### 4.3 salvo（齐射）

- 一次 `launch(..., {"salvo": N})` 生成 N 个**独立弹丸**：
  各自独立散布（确定性 Box-Muller `_gauss`，种子含 shot/index）、
  独立引导头实例、独立对抗判定；
- 任一发失败不影响已发（`failed[]` 记录 index+reason）；
- 事件 `salvo_launch` 汇总 `requested/launched/projectile_ids/failed`。

### 4.4 profile（巡航路径点 / Δv 时序点）

- `waypoints: [{t_s, dv_kmps}, ...]`，`t_s` 是**相对发射时刻**的脉冲时间；
- 每到一个点扣一次 Δv（`waypoint_dv` 事件），预算不足则 `insufficient_dv` 拒绝发射；
- `seeker_off_until_km`：静默接近，引导头到该距离才开机；
- `terminal_acquire_km`：进入该距离切 TERMINAL 段；
- 规划由 `V2CombatPlanner`（游戏性层）生成，见 `combat_planner.md`。

### 4.5 PD（点防）

- 每子步，`_pd_platform_id` 平台（默认 `own` 哨兵 → 解析成本舰实体）`has_pd=true`
  时自动尝试拦截；
- 目标：射向该平台的 `interceptable` 弹丸，且在 PD `range_km` 内；
- **按 ETA 排序**（先打最快到达的）+ 冷却射速模型，单步最多
  `MAX_PD_SHOTS_PER_STEP = 4` 发 —— 所以**齐射饱和才有意义**；
- 命中概率 = `intercept_prob × (1 - 0.5×dist/range)`（下限 `range_factor_min`），
  确定性 roll；
- 成功 → `ballistic_intercept.v1`（`intercepted=true`）+ `projectile_intercepted`；
  失败则弹丸继续；
- `pd_state()`：`ammo / ammo_max / cooldown_until / cooldown_remaining_s`。

### 4.6 decoy / jammer

- `launch(..., "decoy"/"jammer", ...)` 生成 countermeasure：
  `{kind, owner_id, pos_km, deployed_t, active_until, active, ...}`；
- `decoy`：带 `rcs_m2 / ir_signature`，作为引导头的**竞争目标**参与锁定；
- `jammer`：带 `power / range_km`，按 `jam_ratio` 压低对方引导头有效距离
  （`home_on_jam` 的弹种反而会朝干扰源归向）；
- 过期自动失效并事件；不生成真实射频/假回波。

## 5　事件 / 记录 / damage

- events schema `ballistics_event.v1`：
  `{seq, t, kind, payload, shadow, writes_v15:false}`；
  kind：`launch / salvo_launch / waypoint_dv / seeker_lost / impact / miss /
  projectile_expired / projectile_intercepted / pd_launch /
  countermeasure_deployed / countermeasure_expired / ballistics_ready`；
- `intercepts[]` schema `ballistic_intercept.v1`：
  `{intercept_id, t, projectile_id, target_id, platform_id, weapon_id,
  distance_km, chance, roll, intercepted, ammo_left}`；
- `impacts[]` schema `ballistic_impact.v1`：
  `{impact_id, t, projectile_id, shooter_id, target_id, weapon_id, kind,
  pos_km, miss_distance_km, shot_id, proximity, direction}`；
- 命中同时生成 `combat_damage_event.v1`：
  `{shot_id, target_id, source_id, weapon_id, damage, penetration, damage_kind,
  hit_point_km, direction, source:"combat_ballistics", applied:false, writes_v15:false}`；
  只输出，调用方/损管决定是否应用（`GameSession` 负责路由并去重）。
- 未命中：`miss` 事件 + `projectile_expired`；不产生 damage。

## 6　存档 / 重置

- `save_state()` schema `v17.combat_ballistics_save.v1`，**版本 2.0.0**：
  t、projectiles（含 seeker/phase/dv 预算/waypoints）、countermeasures、
  intercepts、impacts、events、pd(ammo/cooldown)、seq；
- `load_state` 校验 schema/version/数组；**1.0.0 旧档兼容**：丢弃在飞弹丸并告警
  （v1 弹丸没有引导头/Δv 预算字段，无法安全续飞）；
- `reset()` 清空全部状态、t=0、PD 弹药恢复、seq 重置；
- JSON-safe、确定性；相同输入/命令序列 VM/events 一致。

## 7　接入 / 边界

- **输入**：调用方每步提供 `pos_km / vel_kmps / radius_km / has_pd /
  rcs_m2 / ir_signature / kind / side`；服务不查询 world/TrackTable/传感器。
- **输出**：impact/damage events 交上层损管/物理；本服务不写 world/V15/UI。
- **不实现**：真实轨道摄动高阶项、雷达截面细节建模、PD 弹丸独立弹道、
  多目标饱和分配算法、真实电子战波形、传感器锁定链路信号级仿真。
  PD/诱饵/干扰仍是**抽象但状态化**的模型（不再是每步掷骰）。
- 不做舰名/关卡/剧情硬编码；无 UI/存档文件 I/O；无世界写。
- probe：`ballistics_probe.gd` 覆盖内容/预测/射击法残差/railgun 命中与 miss/
  多弹、missile 制导/燃料/寿命/移动目标/引导头四态、PD 拦截/射程/弹药/冷却、
  诱饵/干扰、存档（含 1.0.0 旧档）/重置/JSON/确定性/不写。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ballistics_probe.gd
# BALLISTICS PROBE RESULT: PASS=306 FAIL=0
# BALLISTICS PROBE OK（退出码 0）
```
