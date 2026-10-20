# 阶段2-FLEET-ORBIT-1 · 5 舰独立 CR3BP 轨道传播

> 任务 阶段2-FLEET-ORBIT-1（task-111）。工程 `game_v17`。
> 新文件（不改 transit/transit_hud/其他；未 commit）：
> - `framework/sim/fleet_transfer.gd`
> - `framework/content/transfer_l4_l1_fleet_cached.json`（确定性缓存，47,649 B）
> - `tests/fleet_transfer_probe.gd`（`PASS=587 FAIL=0`）
> - 本文件
> 不接 UI；仅模型/数据层。

## 1　定位：独立传播，不是 timeline+偏移

- 基准：`transfer_planner.gd` 的 L4-02 出发状态（单 TOF=6 天；与默认规划选中解一致）。
- 5 舰各有明确初始偏移（位置/速度，见 §2）；每舰从自己的 departure 状态**独立**调用
  `cislunar_physics.propagate_state`（CR3BP/RK4；step_s=60，6 天=8640 步）传播到同一 TOF；
  **不是**“旗舰 timeline + 常量偏移”。
- 独立 11 点采样：每舰从自己的 departure 状态分段传播（t=0…TOF），`sample(t)` 在相邻采样间
  线性插值；旗舰与 `transfer_planner` timeline 一致（同初速），其余舰轨迹因初始偏移而真实分化。
- probe 证据：4 舰在采样点的位置与“baseline timeline + 初始常量偏移”偏差 >1 km；
  mid 相对旗舰偏移（134.6 / 173.0 / 222.0 / 276.8 km）≠ 初始偏移（14.6 / 18.4 / 18.3 / 24.2 km）。

## 2　5 舰偏移（明确数值，km / km/s）与实测结果

| 舰 | batch | role | 位置偏移 | 速度偏移 | 到达误差 | 到达速度 | dep Δv | arr Δv | 总 Δv |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| apsis | 1000 | flagship | [0,0,0] | [0,0,0] | **0.77 km** | 0.969 km/s | 853.4 m/s | 969.2 m/s | 1822.6 m/s |
| harmattan | 1001 | command | [12,-8,2] | [0.0004,-0.0003,0.00005] | **244.3 km** | 0.970 km/s | 853.8 | 969.6 | 1823.3 |
| ferry | 1002 | escort | [-15,10,-3] | [-0.0005,0.0004,0] | **316.1 km** | 0.969 km/s | 852.9 | 968.8 | 1821.7 |
| watchtower | 1003 | relay | [8,16,4] | [0.0003,0.0006,-0.0001] | **609.3 km** | 0.970 km/s | 853.7 | 969.5 | 1823.2 |
| deepwell | 1004 | tanker | [-20,-12,-5] | [-0.0007,-0.0005,0.00015] | **744.0 km** | 0.969 km/s | 852.7 | 968.6 | 1821.3 |

- 到达 gate：半径 ≤3000 km、相对速度 ≤3 km/s；**5 舰全部 within_gate=true**；
  max_error=744.0 km、max_speed=0.970 km/s。
- Δv 分配：sum_departure=4266.5 m/s、sum_arrival=4845.7 m/s、sum_total=9112.2 m/s；
  avg_total=1822.44 m/s（各舰接近 baseline，偏移只小幅改变 Δv）。
- 所有舰同一 TOF（6 天）；未使用额外 MCC（误差已满足 gate）。

## 3　API（`fleet_transfer.gd`，实例方法；JSON 安全）

| API | 说明 |
| --- | --- |
| `plan(opts := {})` | 规划：基准 `transfer_planner` + 5 舰独立传播 + 11 点采样 + cache 构造。opts：`tof_days`（默认 [6.0]）、`use_cache`（true 则先读 cache）、`cache_path`。失败返回 `ok=false`、不伪造 |
| `sample(t) -> Dictionary` | 按时间 t（秒，clamp 到 [0,tof]）返回每舰插值：`pos_rot_km/vel_rot_kmps`、`earth_distance_km`、`distance_to_target_km`、`rel_to_flagship_km`/`_mag_km`，以及 `phase=departure/cruise/arrival`、`clamped`、`progress`、`requested_t_s` |
| `fleet() -> Array` | 5 舰行：initial/departure/arrival 状态、offsets、Δv、arrival_error/speed、gate、propagated_steps |
| `summary() -> Dictionary` | schema/fleet/tof/ship_count/sample_count/arrival{rows,max_error,max_speed,all_within_gate,gate}/dv{rows,sum/avg/max}/ships/cache |
| `to_json() -> String` | `JSON.stringify(summary())` |
| `cache()` / `save_cache(path)` / `load_cache(path)` | 缓存读写（schema=`v17_fleet_transfer_cache.v1`；加载校验 5 舰/11 采样） |
| `has_ship/row_for/reset` | 查询/复位 |

每舰行关键字段：`ship_id/batch/role/offset_km/offset_kmps/initial_state_rot/departure_state_rot/
departure_dv_rot/departure_dv_mps/arrival_state_rot/arrival_dv_rot/arrival_dv_mps/total_dv_mps/
arrival_error_km/arrival_speed_kmps/gate_radius_km/gate_speed_kmps/within_gate/
independent_propagation/propagated_steps`。

## 4　缓存 JSON（`transfer_l4_l1_fleet_cached.json`）

```
{
 schema:"v17_fleet_transfer_cache.v1", generated_by:"fleet_transfer.gd",
 fleet:"transit_l4_l1", source_port:"L4-02 Hammer", target_port:"L1-Meridian-05",
 tof_s:518400.0, tof_days:6.0,
 baseline:{planner:"transfer_planner.gd",method:"lambert_seed_cr3bp_shooting",
           total_dv_mps,arrival_error_km},
 ships:[5 × 独立传播行], samples:[11 × {t_s,t_days,progress,ships[5 × ...]}],
 arrival:{...}, dv:{...}, deterministic:true
}
```

- 缓存由 `plan()` 后 `save_cache()` 确定性生成；`plan({"use_cache":true})` 可直接恢复。
- 现算与缓存数值一致（容差验证；JSON 浮点序列化往返有 ~1e-15 相对差异，不按字符串严格比较）。

## 5　接入 transit 的替换点（本任务不接）

- 目前 transit bridge/state 使用 `transfer_planner` 的**旗舰 timeline**（`fw_transfer`/`fw_transfer_tick`）。
- 后续可替换为：`fleet_transfer.plan()` 得到每舰独立行 → `fw_transfer.fleet` 替换单舰 fleet；
  `transfer_tick(t)` → `fleet_transfer.sample(t)`，HUD 用每舰 `pos_rot_km/rel_to_flagship_km/
  distance_to_target_km` 与到达 gate 数据。
- 字段对应：`fw_transfer.transfer.depart_state_rot` → `row_for(ship).departure_state_rot`；
  `arrival.radius/speed` → `row_for(ship).arrival_error_km/arrival_speed_kmps`；
  `fw_transfer_tick` 的 fleet 视图 → `sample(t).ships`。
- 替换为后续任务；本任务未改 transit/state/bridge。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/fleet_transfer_probe.gd
# V17 FLEET TRANSFER PROBE RESULT: PASS=587 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：缓存 JSON（schema/5 舰/11 采样/字段/有限）；缓存 plan；现算 plan（5 舰状态/Δv/
误差/速度/gate/propagated_steps，与缓存容差一致）；独立轨迹（旗舰=baseline timeline，
4 舰偏离 baseline+常量偏移 >1km，mid 相对偏移≠初始偏移，末采样=arrival）；sample(t)（三阶段/
progress/clamp/采样点还原/5 舰位置可区分）；summary/arrival/dv/fleet/JSON；边界（未 plan、
缓存缺失、错误 schema、无效 TOF 均 `ok=false` 不伪造）。

## 7　边界 / 未完成

- **非星历**：CR3BP 圆轨道近似（忽略 J2/太阳/月球偏心率/倾角/质心摆动）；float32 Vector3
  （38 万 km 量级 ~0.03 km 精度）；港站为旋转系固定站保持（v_rot=0），**无真实站保持推力**。
- Δv 为模型脉冲（departure/arrival burn），**不执行推力/姿态/燃料消耗**；无 MCC（误差已 gate）。
- 各舰偏移为**明确数值**（§2），不是随机/隐藏偏移；到达误差由独立传播自然产生，未用“偏移后强行修正”。
- 不接 UI/transit/state/bridge；未接存档；未跑全量回归；未 commit。
