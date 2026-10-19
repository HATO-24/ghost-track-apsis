# R6-PHYS-1 · 地月物理核心（CR3BP / RK4 / 交会辅助）

> 任务 R6-PHYS-1（task-71）。工程 `game_v17` framework 层。
> **可验证物理模型，先不替换游戏**：圆轨道 + CR3BP 近似，**不是 JPL 星历**。
> 不接 UI/HUD、不做站体模型；现有 core/world/state/framework 模型未修改。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `framework/sim/cislunar_physics.gd`（新） | `V2CislunarPhysics`：参考系/状态向量、CR3BP+RK4、L1–L5、Jacobi/能量/NaN、GEO/LLO/转移初始化、相对运动/LVLH/CW、接近走廊/对接几何、实体推进与采样 |
| `tests/cislunar_physics_probe.gd`（新） | headless probe：**PASS=269 FAIL=0**（11 节） |
| `docs/cislunar_physics.md`（本文件） | 模型假设、坐标、API、R6 接入点、边界 |

未改 core/ui/content/project、现有 sim 模型（sensor_types/radar/tws/optical 等）；未 commit。

## 2　模型假设与常数

- 地球 + 月球 + 测试粒子（CR3BP）；地球固定在 **barycenter 旋转系** `(-μD, 0, 0)`，
  月球固定在 `((1-μ)D, 0, 0)`；旋转角速度 ω = 2π/T_moon。
- 忽略：地球 J2/扁率、太阳引力、月球轨道偏心率与倾角、月球物理天平动、质心摆动的高阶项、
  大气阻力、相对论；时间尺度（一局 40 分钟）内可接受。
- 常数（`km`、`km³/s²`、`s`）：
  - μ_earth = 398600.4418；μ_moon = 4902.800118；R_earth = 6378.137；R_moon = 1737.4
  - D = 384,400 km；T_moon = 27.321661 d = 2,360,591.51 s；GEO r = 42,164 km；
  - μ = μ_moon/(μ_earth+μ_moon) = 0.0121506；归一化时间 T_c = √(D³/(μ_e+μ_m)) ≈ 375,190 s
    （T_c·2π 与观测 T_moon 有约 0.1% 舍入差，属于 GM 常数与观测周期口径差异，文档明示）。
- 归一化（CR3BP canonical）：位置 / D，速度 · T_c / D，时间 / T_c；Jacobi 常数归一化。

## 3　参考系与状态向量

| 帧 | 说明 |
| --- | --- |
| `bary_rot` | barycenter 旋转系（内部积分帧）；地球 (-μD,0,0)、月球 ((1-μ)D,0,0) |
| `earth_rot` | 地心旋转系（Earth-centered rotating；= bary_rot − 地球旋转位置） |
| `earth_eci` | 地心惯性系（Earth-centered inertial；与 `cislunar_explorer` 的站体坐标一致） |

- 内部状态：`{"r": Vector3(km), "v": Vector3(km/s)}`；公开 JSON 形式：
  `{"r":[x,y,z], "v":[vx,vy,vz]}`。
- 转换 API：
  - `bary_rot_to_earth_rot(state)` / `earth_rot_to_bary_rot(state)`
  - `bary_rot_to_earth_eci(state, t)` / `earth_eci_to_bary_rot(state, t)`
  - `to_canonical(state)` / `from_canonical(state)`
  - 旋转系速度含 `ω×r` 项，转换往返已由 probe 验证（位置 ~1e-2 km、速度 ~1e-9 km/s 精度，
    受 Godot Vector3 float32 限制）。

## 4　三体 CR3BP + RK4

旋转系方程（物理单位）：

```
a = −μ_e (r−r_e)/|r−r_e|³ − μ_m (r−r_m)/|r−r_m|³
    − 2 ω×v − ω×(ω×r)
```

- `acceleration_rot(state)`；`rk4_step(state, dt)` 四阶固定步长。
- `propagate_state(state, dt, opts)`：
  - 步长 `opts.step_s` 被 **clamp 到 (0, 60] s**（任务要求 ≤60 s，默认 60 s）；
  - `dt` 可负（反向），步数 `ceil(|dt|/step)`；`max_steps` 保护（默认 2,000,000）；
  - 返回 `{ok, state, steps, step_s, jacobi_start, jacobi, jacobi_drift,
    energy_start, energy, finite, warnings, reason}`；
  - 非法状态（NaN/Inf/零半径/超范围）→ `ok=false, reason=invalid_state`；
  - 传播中出现非有限值 → `reason=non_finite_state` 并返回安全化状态。
- `propagate_states(states, dt, opts)` 批量。
- 不变量：**Jacobi 常数**（CR3BP 守恒量）与能量代理
  `energy = 0.5|v|² − Ω`，两者关系 `C = −2·energy/(ω²D²)`。
- `sanitize_state(state)`：NaN/Inf → 0，返回 `{state, changed, finite}`。
- `validate_state(state)`：半径/有限性检查。
- `effective_potential(state)`、`jacobi_constant(state)`、`jacobi_from_earth_eci(state,t)`。

## 5　L1–L5 / GEO / LLO / 转移初始化

- `equilibrium_points()`：标准 CR3BP 共线方程二分求解（L1/L2/L3）+ L4/L5 等边；
  返回每个点的旋转系物理位置、距地/距月距离、Jacobi、kind（collinear/triangular）。
  参考结果（μ=0.0121506）：L1 距月球 ≈58,000 km、L2 距月球 ≈64,500 km、L3 在月球反侧；
  L4/L5 与地月各构成等边三角形（距地=距月=D），Jacobi ≈3−μ(1−μ)≈2.993。
- `lagrange_state(id, offset_km, velocity_kmps)`：L 点附近测试粒子初始化（旋转系）。
- `two_body_circular_state(mu, radius, phase, inclination_deg)`；
  `geo_state(t, phase0)`：GEO 圆轨道（42,164 km，周期 ≈86,164 s，速度 √(μ/r)）；
  `llo_state(t, phase0, inclination_deg, altitude_km)`：月球低轨（默认 100 km，周期 ≈7,067 s，
  可极轨）；`transfer_state(perigee_km, apogee_km, true_anomaly_deg)`：地月转移椭圆初始化。
- `propagate_two_body(state, mu, dt, opts)`：两体 RK4（用于轨道闭合/精度验证，同样 ≤60 s 步长）。
- `moon_state_eci(t)` / `moon_state_rot()` / `moon_phase(t)`；`earth_position_eci/rot`。

## 6　交会辅助（纯数学，不接武器/伤害）

- `relative_state(chaser, target)`：`Δr/Δv/range/range_rate/closing/relative_speed/TCA/los_unit`
  （closing = −(Δr·Δv)/|Δr|，TCA 线性近似）。
- `lvlh_basis(r, v)`：R 径向、S 沿迹、W 法向（右手）；`to_lvlh(vec, basis)`。
- `cw_matrix(n, t)`：Hill/CW 6×6 状态转移矩阵（状态序 `[x,y,z,vx,vy,vz]`，x=R,y=S,z=W）；
  `propagate_cw(rel, n, t)` 解析传播；probe 验证一周期闭合与 t=0 恒等。
- `approach_corridor_check(rel_pos, rel_vel, spec)`：
  `spec = {axis,length_km,half_angle_deg,lateral_tol_km,max_closing_mps,max_angle_deg}`；
  返回 `inside/along/lateral/corridor_radius/align_angle/closing_mps/angle_ok/speed_ok/status/warnings`。
- `docking_geometry(rel_pos, rel_vel, port_axis, spec)`：
  `spec = {docking_tol_km,lateral_tol_km,align_tol_deg,max_closing_mps,max_lateral_mps,dock_speed_mps}`；
  返回 `range/axial/lateral/align_angle/closing_mps/lateral_mps/status/ok/warnings`；
  status ∈ `approach/aligned/docked/too_fast/misaligned`（dock_speed 为接触速度）。
- `docking_sequence(states, port_axis, spec)`：逐点对接进近序列检查。

## 7　实体推进 / sample_entity

```gdscript
var phys = V2CislunarPhysics.new({"step_s": 60.0, "max_steps": 2000000})
phys.add_entity("probe-1", V2CislunarPhysics.lagrange_state("L4", offset_km, vel_kmps))
phys.propagate(3600.0)                     # 固定步长 RK4（≤60 s），推进所有实体
var sample = phys.sample_entity("probe-1") # {id,t,state_rot,state_earth_eci,state_earth_rot,
                                           #  jacobi,energy,finite,earth_distance_km,moon_distance_km}
phys.sample_all() / phys.entity_ids() / phys.remove_entity(id)
phys.to_dict()                             # schema/constants/config/entities，JSON 可序列化
```

静态批量：`propagate_state` / `propagate_states` / `propagate_two_body`。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/cislunar_physics_probe.gd
# 末行 PHYSICS PROBE RESULT: PASS=269 FAIL=0 / PHYSICS PROBE OK，退出码 0
```

覆盖（11 节）：
1. 常数/归一化（μ、D、T_moon、T_c/V_c、canonical 往返、状态工具、validate）；
2. 参考系转换（bary_rot ↔ earth_rot ↔ earth_eci，位置+速度往返）；
3. L1–L5（二分根、距离/等边/Jacobi/平衡点加速度≈0/静止传播漂移）；
4. CR3BP（RK4 步长≤60 s、Jacobi 守恒、正反向传播、max_steps、NaN/Inf、sanitize、批量、JSON、有效势梯度数值校验）；
5. 两体 RK4 轨道闭合（LEO 400 km <100 m、GEO <5 km、LLO 绕月 <500 m）与转移椭圆；
6. 月球/时间（相位、T 周期回归、速度、旋转系）；
7. 相对运动/LVLH/CW（Δr/Δv/closing/TCA、基正交、CW 一周期闭合）；
8. 接近走廊/对接几何（inside/lateral/angle/speed；aligned/docked/too_fast/misaligned；序列）；
9. 实例实体（add/propagate/sample/remove/多实体/max_steps/JSON）；
10. NaN/JSON（拒绝/安全化/状态数组/失败结果 JSON）；
11. 确定性（CR3BP/两体/实体推进逐位一致）。

## 9　R6 接入点（后续）

1. **world/state 位置源**：R6 后实体 `pos_km/vel_km_s` 由本模型 `sample_entity` 的
   `state_earth_eci`（或 `state_rot`）提供；V17 现有脚本轨道保留为回退，切换时保持同 schema。
2. **navigation 节点**：`V2NavigationModel.bind_position_provider(func(source,node_id) ...)`
   可用本模型站体/轨道状态替换 `cislunar:*` 抽象坐标（L1/L2/月球港等）。
3. **机动执行**：导航模型 `maneuver_done` 事件 → 物理层对实体施加 Δv（改变 `v`），
   再继续 RK4 滑行；本模型不自己判断武器/伤害。
4. **主循环**：core 固定步长 tick（≤60 s；1× 可用更小步长）调 `propagate`/`step`；
   时间加速时用解析/大步长策略（详见 docs/02 §9）。
5. **UI/HUD**：不直接接；导航页由 `sample_entity` + `vm_navigation` 驱动；
   物理模型 `authoritative=false`，R6 切换后以物理世界为权威。
6. **传感器几何**：EO/IR/雷达可用 `state_earth_eci`/姿态（后续）计算遮挡/视轴；当前仅提供位置/速度。

## 10　限制 / 未完成

- 非 JPL 星历：圆轨道 + CR3BP；无太阳引力/J2/月球偏心率/倾角/质心摆动。
- Godot `Vector3` 为 float32：大数值（~3.8e5 km）位置精度约 0.03 km，速度约 1e-7 km/s；
  probe 使用 float32 数值地板验证。需要更高精度时 R6 可改 double 或归一化积分（本模型已提供 canonical 转换）。
- 时间步固定 ≤60 s；未实现自适应步长/辛积分；高偏心率转移仅用于初始化示意。
- 交会辅助为几何/数学函数：CW 为线性化解析，接近走廊/对接只做判定，不实现制导控制/碰撞响应。
- 未做姿态/四元数/推力/质量（docs/02 §6/§7 留给后续）；未接武器/伤害/UI/core。
- L 点结果为 CR3BP 近似；`μ` 使用 GM 推导值，Jacobi 绝对值与文档表格若用不同 μ 会有小差异。
