# CISLUNAR EXPLORER · 地月系模型说明（v1）

> 工程：`cislunar_explorer/`（独立技术 demo，V1 色板/字体）。
> 模型：`sim/cislunar_model.gd`（`class_name CislunarModel`）。
> 探针：`tests/cislunar_probe.gd`。本文档说明假设、公式、API、算例与边界。
> 结论先说：这是**圆轨道 + CR3BP 驻点近似 + 共转速度**的可验证演示模型，
> **不是 JPL 星历**；所有数字都可用文末探针复算。

## 1　坐标、单位与时间

| 项 | 约定 |
| --- | --- |
| 惯性系 | 地球中心惯性帧（ECI-demo）：原点=地球中心；**XY 平面=月球轨道面**，+Z=轨道法向；t=0 时月球在 +X |
| 地球 | 固定在原点（忽略地月质心摆动；`earth.position=[0,0,0]`，`velocity=[0,0,0]`） |
| 旋转系 | +X 指向月球（地月连线），XY=轨道面，随月球共转；L 点在其中静止 |
| 单位 | 距离 km、时间 s、速度 km/s、角度 rad（对外另带 `_deg` 字段） |
| 时间 | 模型时间 `t`（s，自 `epoch.t0_iso = 2026-01-01T00:00:00Z`）；`set_time/get_time`，`sample(t)` 可显式给 t |
| 数值精度 | 内部用 Godot `Vector3`（**float32**）：位置相对误差 ~1e-7（384,400 km 处约 0.03 km）。探针用相对容差验证 |

## 2　月球圆轨道

给定（任务口径）：半径 `R = 384,400 km`，恒星周期 `T = 27.321661 d = 2,360,591.51 s`。

```
θ(t) = 2π t / T
r_moon = R (cosθ, sinθ, 0)
v_moon = (2πR/T) (−sinθ, cosθ, 0)      // ≈ 1.023157 km/s
n = 2π/T ≈ 2.661699e-6 rad/s
```

- 月球同步自转：本体近地面朝地球，`rotation_period = T`。
- **一致性说明（重要）**：真实地月系中 `R=384,400 km` 与 `T=27.321661 d` 并非严格满足
  `n²R³ = μ_E+μ_M`（真实平均距离约 384,748 km）。本模型以任务给定的 R、T 为准，
  `μ_implied = n²R³ = 402,409.47 km³/s²`，与 `μ_total = 403,503.24` 相差 **0.271%**。
  `mu_consistency_rel_err()` 给出该值；探针检查其 < 0.5%，并在 API/sample 中暴露
  `constants.mu_implied_km3_s2 / constants.mu_consistency_rel_err`。这是演示模型边界，不隐藏。

## 3　L1–L5（CR3BP 驻点）

- 地月质量比：`μ = m_Moon/(m_Earth+m_Moon) = 0.012150585`（`mu_derived()` 由
  `μ_M/(μ_E+μ_M)` 复算验证）。
- 归一化旋转系（地月距=1）：地球在 `x=−μ`，月球在 `x=1−μ`；共线平衡方程

```
f(x) = x − (1−μ)(x+μ)/|x+μ|³ − μ(x−1+μ)/|x−1+μ|³ = 0
```

  L1∈(−μ, 1−μ)、L2∈(1−μ, 2)、L3∈(−2, −μ) 三个根由**二分法求根**（200 次迭代，
  区间 <1e-15），不是硬编码；`collinear_points_normalized()` 直接返回根，
  `collinear_equation(x)` 可独立验证 `|f(x)| < 1e-9`。
- L4/L5：归一化 `(1/2−μ, ±√3/2)` → 地心旋转系 `(0.5R, ±0.866R)`；到地球/月球距离都=R，
  与月球夹角 60°（分居地月连线两侧）。
- 旋转系 → 惯性系：`r_inertial = Rz(θ) · r_rot`；速度按**共转近似** `v = n ẑ × r`
  （L 点站需要站保持，模型不模拟推进/保持误差）。

算例（模型输出，km）：

| 点 | 到地球 | 到月球 | 备注 |
| --- | --- | --- | --- |
| L1 | 326,381 | 58,019 | 地月之间 |
| L2 | 448,915 | 64,515 | 月球外侧 |
| L3 | 381,675 | 766,075 | 反月侧（x<0） |
| L4/L5 | 384,400 | 384,400 | ±60° |

## 4　站点与环

### 4.1 GEO 环
- 半径固定 `42,164 km`；周期由 Kepler 从半径推：`T = 2π√(a³/μ_E) = 86,163.6 s`
  （与地球恒星日 86,164.09 s 相差 ~5e-6，因 42,164 km 为取整值）。
- 环上采样点随地球自转：`φ(t) = 2π t / 86164.0905`；速度 = `ω_E ẑ × r`。

### 4.2 月球同步环（演示数据，注意边界）
- 任务公式：`r = (G·M_moon·T²/4π²)^(1/3)`，`T` = 月球恒星日（=恒星月 27.321661 d）。
  模型用 `μ_Moon = G·M_moon = 4,902.800118 km³/s²`：
  **r = 88,452.215 km**，周期 `2,360,591.51 s`。
- **边界**：该半径大于月球 Hill 球半径 `R(μ/3)^(1/3) = 61,273.9 km`
  （`hill_radius_km()` / `ring.outside_hill_sphere=true`）。因此它是“按公式算出的演示环”，
  不是可稳定维持的月球同步轨道。文档与探针都显式标注，不假装物理可行。
- 采样点相对月球随月球自转（周期=恒星日）共转。

### 4.3 月球低轨 / 极轨 / 港口
- 月球低轨：`r = R_moon + 100 = 1,837.4 km`，周期 `2π√(r³/μ_Moon) = 7,067.46 s`（≈117.8 min）。
- 月球极轨：同半径，倾角 90°（相对轨道面），位置出平面 `z` 分量随相位振荡。
- 地球港：地球赤道表面标记，`r = 6,378.137 km`，随地球自转（周期=恒星日）。
- 月球港：月球近地面（近地点朝向地球）地表标记，`r = 1,737.4 km`，随月球同步自转。
- L1/L2/L4/L5 站、环锚点站、月球轨道站、港口共 10 项，字段见 §6。

## 5　API（`CislunarModel`）

常量：`MU_EARTH / MU_MOON / MU_TOTAL / MU`、`EARTH_RADIUS_KM`、`MOON_RADIUS_KM`、
`EARTH_MOON_DIST_KM`、`MOON_PERIOD_S`、`EARTH_SIDEREAL_DAY_S`、`GEO_RADIUS_KM`、
`G`/`MOON_MASS_KG`、`LUNAR_LEO_ALTITUDE_KM`、`EPOCH_ISO`、`MODEL_ID`、`STATION_IDS`。

静态辅助：

| 函数 | 说明 |
| --- | --- |
| `moon_mean_motion()` | n = 2π/T_moon（rad/s） |
| `period_s(radius_km, mu := MU_EARTH)` | Kepler 周期 |
| `circular_speed_kmps(radius_km, mu := MU_EARTH)` | 圆轨道速度 |
| `geo_period_s()` | GEO 环周期（从 42,164 km 推） |
| `lunar_sync_radius_km()` / `lunar_sync_period_s()` | 月球同步环半径/周期（任务公式） |
| `hill_radius_km()` | 月球 Hill 球半径（边界标注用） |
| `implied_mu_km3_s2()` / `mu_consistency_rel_err()` | R/T 与 μ_total 的自洽性与误差 |
| `mu_derived()` | μ_M/(μ_E+μ_M) |
| `moon_phase(t)` / `moon_state(t)` / `earth_state(t)` | 相位/状态（position/velocity/period/rotation…） |
| `collinear_equation(x)` / `collinear_points_normalized()` | CR3BP 共线方程与三个根（可独立验证） |
| `collinear_points_rotating_km()` / `lagrange_rotating_km()` | 旋转系 km 位置（L1–L5） |
| `lagrange_state(t)` | L1–L5：position_rot_km/position/velocity/distance_earth/moon/angle_from_moon/rot_angle/lagrange_type |
| `geo_ring(t, count)` / `lunar_sync_ring(t, count)` | 环定义 + 采样点/速度 |
| `stations_state(t)` | 10 个站（id/name/kind/parent/orbit{radius_km,period_s,period_days,inclination_deg}/position/velocity/speed/distance_*/distances） |
| `rot_to_inertial(v, phase)` / `corotation_velocity(pos, omega)` | 坐标/速度辅助 |
| `vec3_of(v)` / `distance(a,b)` / `arr(v)` | 输入兼容 Vector3/[x,y,z]/Dictionary、距离、序列化 |

实例：

| 函数 | 说明 |
| --- | --- |
| `new(t0 := 0.0)` / `set_time(t)` / `get_time()` | 模型时间 |
| `sample(t_s := <model.t>)` | 全系统快照（见 §6）；纯函数，不修改 model.t |
| `orbits(samples := 96)` | 月球轨道、GEO 环、月球同步环采样点列 + periods |

## 6　`sample(t)` 结构（JSON 可序列化，km/km/s/rad）

```
{
  "model": "cislunar_circular_cr3bp_v1",
  "units": {"distance":"km","velocity":"km_per_s","angle":"rad","time":"s"},
  "epoch": {"t0_iso":"2026-01-01T00:00:00Z","t_s":<t>,"t_days":<t/86400>},
  "mu": 0.012150585, "mu_derived": 0.01215058…,
  "constants": {mu_earth_km3_s2, mu_moon_km3_s2, mu_total…, earth_radius_km, moon_radius_km,
                earth_moon_distance_km, moon_period_s, earth_sidereal_day_s,
                geo_radius_km, geo_period_s, lunar_sync_radius_km, lunar_sync_period_s,
                hill_radius_km, g_si, moon_mass_kg, mu_implied_km3_s2,
                mu_consistency_rel_err, vector_precision},
  "earth": {position,velocity,radius_km,mu_km3_s2,sidereal_day_s,rotation_angle_rad,angular_velocity_rad_s},
  "moon":  {position,velocity,distance_km,speed_kmps,phase_rad,phase_deg,period_s,
            mean_motion_rad_s,mu_km3_s2,radius_km,rotation_angle_rad,rotation_period_s},
  "lagrange": {"L1"…"L5": {id,position_rot_km,position,velocity,distance_earth_km,
                            distance_moon_km,angle_from_moon_deg,rot_angle_deg,
                            lagrange_type,side}},
  "stations": [ {id,name,kind,parent,orbit{radius_km,period_s,period_days,inclination_deg},
                 position,velocity,speed_kmps,distance_earth_km,distance_moon_km,
                 distances{earth_center_km,moon_center_km,earth_port_km,lunar_port_km},
                 （L 站有 lagrange_id；月球站有 altitude_km；环站有 outside_hill_sphere）}, … 10 项 ],
  "rings": {"geo": {id,name,parent,kind,radius_km,period_s,period_days,count,points[[x,y,z]],velocities},
            "lunar_sync": {…, hill_radius_km, outside_hill_sphere:true}},
  "distances": {"earth|moon":384400, "l1_station|l4_station":…, …（站两两）}
}
```

`orbits()` 结构：`{model, samples, moon{id,parent,radius_km,period_s,points}, geo{…}, lunar_sync{…}, periods{moon_s,geo_s,lunar_sync_s,earth_sidereal_day_s}}`。

## 7　验证（headless probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\cislunar_explorer --script res://tests/cislunar_probe.gd
# 末行：CISLUNAR PROBE RESULT: PASS=255 FAIL=0，退出码 0
# 启动检查：
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\cislunar_explorer --quit
```

覆盖：月球半径/周期/速度、T/4 相位、n²R³ 与 μ_implied 自洽误差、时间可设语义；
L1/L2/L3 共线方程残差（|f|<1e-9）、距离范围、L3 反月侧、L4/L5 等边/±60°、旋转↔惯性变换、
共转速度；GEO 半径/周期/采样点半径/速度/转动 90°；月球同步环公式半径/周期/Hill 外标注/共转；
月球低轨/极轨半径周期、极轨出平面、地球/月球港地表与近地面；10 站字段完整性、相对距离矩阵；
sample 结构、JSON stringify/parse 回读。输出 `[DATA]` 行含关键数值（L1/L2/L3、GEO、月同步、LEO 等）。

## 8　边界（明确不做 / 不假装）

- **不是 JPL 星历**：无真实月球轨道偏心率/倾角、无太阳引力/光压/高阶重力场；月球为圆轨道。
- 地球固定在惯性原点，不建模地月质心摆动（对演示位置影响 ~4,700 km 量级，未补偿）。
- CR3BP L 点为理想驻点；真实 L 点站需要持续站保持推进，模型不模拟。
- 月球同步环半径在月球 Hill 球外（见 §4.2），仅作“按公式计算”的演示数据，不具稳定性含义。
- 演示站点的相位/倾角是初始条件；LEO/极轨/环锚点按固定速率运动，不与月球真实引力场耦合。
- float32 精度：`Vector3` 单精度，位置 ~1e-7 相对误差；需要更高精度（厘米级）时须改 double 运算。
- 不渲染、不做 UI；`explorer.gd` 通过 `sample(t)` 自行适配（当前 UI 任务已按本 schema 接入）。
- 未定义站间通信/可见性/光照/燃料等；后续可在 sample 外扩展 helper，不影响本模型契约。
