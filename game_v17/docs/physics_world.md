# 完整游戏-阶段2L · PhysicsWorld 单一权威物理世界

> 任务 完整游戏-阶段2L（task-151）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/TrackTable/命令；未 commit）：
> - `scripts/core/physics_world.gd`
> - `tests/physics_world_probe.gd`（`PASS=217 FAIL=0`）
> - 本文件
> 复用既有 `framework/sim/cislunar_physics.gd` 常数/帧接口与
> `framework/sim/ephemeris_compact.gd`（无表 analytic fallback）。

## 1　定位

- **单一权威**：所有实体轨道状态（r/v/mass/attitude）+ 世界时间 + 固定步长推进的唯一来源；
  其它层只读 `state()/states()/snapshot()`，不直接改实体。
- 不写 UI/TrackTable/V15/world/命令；不执行武器/伤害/传感器逻辑；输出 physics events。
- 内部用 **GDScript float（64-bit double）数组**做 CR3BP RK4，不经过 Vector3 float32；
  仅入口/出口帧转换调用既有 Physics（Vector3 边界，误差 ~0.03 km 量级，文档注明）。

## 2　模型

- 地月 CR3BP，barycenter rotating 帧；地球位于 `(-μD,0,0)`，月球位于 `((1-μ)D,0,0)`：
  - μ = MU_MOON/(MU_EARTH+MU_MOON) ≈ 0.012150585
  - D = 384400 km；ω = 月球平均角速度
  - 加速度 = 地球/月球引力 + Coriolis（-2Ω×v）+ 离心（-Ω×(Ω×r)）
- 可选太阳第三体（`sun=true`）：太阳位置来自 V2CompactEphemeris（若表含 sun）；
  无表时用 analytic 1 AU 圆轨道近似；加入微分第三体加速度
  `μsun*((rs-r)/|rs-r|³ - rs/|rs|³)`。
- 能量/Jacobi（双精度）：
  - U = 0.5ω²(x²+y²) + μe/r1 + μm/r2
  - Jacobi C = 2U/(ω²D²) - v²/(ω²D²)；energy = 0.5v² - U
- 固定步长 RK4：`dt` 拆成 `n=ceil(dt/step_s)` 步（每步 ≤60 s），`h=dt/n`。

## 3　帧 / 单位 / 精度

- 内部帧固定 **`bary_rot`**（地月旋转系）；支持输入/输出 `earth_eci`、`earth_rot`
  （经既有 Physics 转换，入口/出口一次）。
- 单位：`length=km, time=s, velocity=km/s, mass=kg, angle=deg,
  attitude=quaternion_wxyz`。
- 状态数组 r/v 为 double；质量 double；姿态四元数（**不做姿态动力学**，仅保存/接口）。
- 存档采用 `r_b64/v_b64/jacobi0_b64`（PackedFloat64Array → base64）保证 double 位级
  往返；同时保留可读 `r/v` 数组。JSON 普通数字有 ~14-15 位有效数字，仅用于可读/兼容。

## 4　API

| API | 说明 |
| --- | --- |
| `PhysicsWorld.new(cfg)` / `setup(cfg)` | cfg：`step_s`(≤60)、`max_steps`、`t`、`sun`、`ephemeris_path`、`ephemeris`、`record_samples`、`max_samples`、`jacobi_tol` |
| `upsert_entity(id, data)` | data：`r/v`（或 `state`/`position_km`/`velocity_kmps`）、`mass_kg`、`attitude`、`frame`；同 id 更新，返回 `{ok,created,entity,state}` |
| `remove_entity(id)` / `entity_ids()` / `entity_count()` / `has_entity(id)` / `entities_text()` | 实体查询/删除；未知实体拒绝 |
| `step(dt)` | 固定步长推进；返回 `{ok,t,steps,step_s,entities,warnings,samples_added}`；负/NaN dt、超 max_steps 拒绝 |
| `set_time(t)` | 绝对时间；只允许向前（回退拒绝） |
| `state(id, frame="bary_rot")` | 单实体状态（r/v/speed/mass/attitude/jacobi/energy）+ 帧；未知实体拒绝 |
| `states(frame)` | 全部实体状态（排序，只读副本） |
| `state_at(id, target_t, frame)` | 推进到绝对时间再取状态；回退拒绝 |
| `trajectory(id, frame)` / `samples_count()` | 轨迹采样（默认最多 512 个采样点） |
| `energy(id)` / `jacobi(id)` | 双精度能量/Jacobi（未知实体 NaN） |
| `ephemeris_summary()` / `ephemeris_state(body, t=-1)` | 星历可用性/状态（earth/moon；sun analytic fallback） |
| `snapshot()` / `summary()` / `to_json()` | 只读 VM（entities/samples/events/ephemeris/contracts） |
| `events` / `events_since(seq)` / `take_events()` | physics events（按 key 防重复） |
| `save_state()` / `load_state(json)` | 内存 JSON；load 全量校验成功后才应用 |
| `frame()` / `units()` / `constants()` / `check_contracts()` / `reset()` | 元数据/DbC/复位 |

拒绝：非法实体 id、NaN/Inf r/v、负/NaN 质量、非法 attitude、非法 frame、未知实体、
负/NaN dt、time_regression、max_steps_exceeded、非法存档。

## 5　事件（防重复）

`physics.world_ready`、`physics.entity_added`、`physics.entity_updated`、
`physics.entity_removed`、`physics.step_started`、`physics.step_completed`、
`physics.jacobi_drift`、`physics.diverged`、`physics.time_set`；
每条 `{schema:"physics_event.v1",seq,t,kind,key,detail,writes_v15:false}`。
`_emit_once` 按 key 去重（例如重复 `step(0)` 不重复产生同 key 的 step_started）。

## 6　存档（`v17.physics_world_save.v1`, version `1.0.0`）

```text
{
  schema, version, t, step_s, max_steps, sun_enabled, ephemeris_path,
  entities: [{
    id, r[], v[], r_b64, v_b64, mass_kg, attitude[4], frame, input_frame,
    created_t, updated_t, jacobi0, jacobi0_b64, version
  }],
  samples: [{t, states_enc: {id: {r_b64, v_b64}}}],
  event_seq, events[]
}
```

- `load_state`：校验 schema/version/t/step_s/entities（id 唯一/有限 r/v/质量/attitude/
  jacobi）→ 全量校验通过后才替换；任意非法拒绝且**不改当前状态**。
- load 后 state/samples/save 与保存前一致（b64 双精度），可继续 step 且确定性一致。
- 无外部文件写入；外层可由 SaveService/GameSession 嵌套。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/physics_world_probe.gd
# V17 PHYSICS WORLD PROBE RESULT: PASS=217 FAIL=0（exit 0，只跑一次）
```

覆盖（8 节）：setup/帧/单位/非法配置；实体（upsert/更新/排序/删除/未知/NaN/负质量/
attitude）；帧转换（earth_eci/earth_rot 输入输出、state_at 向前/回退）；固定步长
（step0/60s/90s→2×45/采样轨迹/max_steps/多实体/同操作确定性）；轨道/能量（Jacobi 与
Physics 一致、L4 6h 漂移/能量守恒、60s vs 10s 步长差异）；星历/太阳（analytic fallback、
earth/moon/sun 查询、sun 第三体）；save/load（t/entities/r/v/mass/samples 完全一致、
继续确定性、非法拒绝不改状态）；事件/JSON/去重/确定性/set_time。

## 8　接入 Session / 边界

- 接入建议（后续）：GameSession 可选 `physics_world`；tick 调 `step(scaled_dt)`，
  实体从 session/seed 同步；`state()` 供传感器/显示只读；physics events 可转 EventBus。
  本任务**未改** GameSession/Session/旧场景。
- 不做碰撞/接触/重力梯度/姿态动力学/推进执行/热控；attitude 仅接口保存。
- 不接真实星历表（仓库无表时 analytic fallback）；太阳为可选第三体近似（1 AU 圆轨道）。
- 不对 TrackTable/UI/命令写；无 ROE/伤害/传感器；未跑全量回归；未 commit。
