# R6-SHADOW-1 · CR3BP/RK4 物理 shadow 接入说明（V17）

> 任务 R6-SHADOW-1（task-72）。工程 `game_v17`。
> 物理核心：`framework/sim/cislunar_physics.gd`（R6-PHYS-1/task-71）。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读快照）。
> 本文件说明 shadow 语义、API、字段、导航位置 provider、边界与测试。

## 1　定位与不变量

- **shadow（影子）模式**：CR3BP/RK4 物理在 bridge 内独立推进，只提供**只读参考数据**；
  `authoritative=false`。**V15 轨道、sensor_model、plot/HUD、V2 world 实体轨道均不被修改**。
- **默认开启**（`V17_PHYSICS=shadow`，未设置时同）；`V17_PHYSICS=off` 可完全关闭。
- 导航仍按内容中的**抽象转移成本**规划/许可/机动；物理 shadow 只替换导航节点的**位置来源**
  （provider），不改变路线成本、不自动执行。
- 下一步（R6 正式接入）才用物理结果替换 V15 位置源；本任务不切权威。
- 实体初始状态来自 V2 场景的 **L1 局部近似/固定占位**（非 JPL 星历），
  每个实体在 `source` 字段明确标注；缺失/未知状态给明确默认并标注，不伪造星历。

## 2　装载与推进

- bridge `boot()`：创建 `V2CislunarPhysics`（`{"step_s": 60.0}`），遍历 `world.entities`：
  - `orbit.frame == "L1"`：`state = L1 平衡点(bary_rot) + 场景 r 偏移`，速度取场景 `v`；
    固定站点（station/tank/fixed）速度置 0（站保持假设）；
  - 其他/缺失：`L1 静止默认`（source 标注）。
  - 记录每个实体 `source` 与初始 Jacobi（用于漂移）。
- bridge `sync(dt)`：`world.advance(dt)`、`nav.step(dt)` 后，
  `physics.propagate(dt)`（固定步长 ≤60s；`dt=0` 暂停不推进）。
- `restart()`：`world.restart()` + `nav.reset()` 后重建 shadow（t=0、实体重载、重新绑定 provider）。
- 实体 Id 覆盖：harmattan / apsis / ferry / watchtower / deepwell / summons_4471 / ceres_2 /
  chronos_station / tank_farm（9 个，来自场景）。

## 3　API

### 3.1 V17Bridge

| 成员 | 说明 |
| --- | --- |
| `physics` | `V2CislunarPhysics` 实例（off/null 时不存在） |
| `physics_mode` | `"shadow"` / `"off"` |
| `physics_ready` | bool |
| `physics_view() -> Dictionary` | 只读物理 vm（见 §4） |
| `physics_summary() -> Dictionary` | t / 实体数 / warnings / max_jacobi_drift / provider 状态 |
| `bridge_state()` | 增 `physics/physics_summary/physics_ready/physics_mode` |

### 3.2 state（HUD 只读）

| 字段 | 说明 |
| --- | --- |
| `state.fw_physics` | `bridge.physics_view()` 的深拷贝 |
| `state.fw_physics_ready` | bool |
| `state.fw_physics_summary` | `bridge.physics_summary()` 的深拷贝 |
| `state.fw_physics_mode` | `"shadow"` / `"off"` |
| `state.fw_bridge_state()` | 增上述 physics 字段 |

旧字段（`fw_tutorial/fw_flow/fw_damage/fw_nav/fw_damage_full/...`）全部保持不变。

## 4　`physics_view()` 结构（JSON 可序列化）

```
{
  "schema":"cislunar_physics.v1","model":"cr3bp_rk4_circular",
  "authoritative":false,"mode":"shadow","ready":true,
  "v15_orbit_source":"unchanged（V15 轨道/sensor_model/plot 仍是权威；shadow 只读）",
  "t":<shadow 秒>,"step_s":60.0,"config":{...},
  "entities":[{
    "id","t","state_rot","state_earth_eci","state_earth_rot",
    "jacobi","jacobi0","jacobi_drift","energy","finite",
    "earth_distance_km","moon_distance_km","source"
  } × 9],
  "reference":{
    "lagrange":{"L1".."L5":{id,kind,position_earth_rot_km,state_earth_eci,
                            state_earth_rot,distance_earth_km,distance_moon_km,jacobi}},
    "geo":{radius_km,period_s,phase_rad,position_earth_rot_km,state_earth_eci,speed_kmps},
    "lunar_leo":{radius_km,period_s,inclination_deg,position_earth_rot_km,
                 state_earth_eci,distance_moon_km},
    "moon":{distance_km,period_s,phase_rad,position_earth_rot_km,state_earth_eci}
  },
  "warnings":[...],
  "note":"CR3BP/RK4 shadow：只读影子；...R6 才替换 V15 位置源。"
}
```

`physics_summary()`：`{ready,mode,authoritative,t,entities,frames,warnings,max_jacobi_drift,
nav_position_provider,v15_orbit_source,reference{lagrange,geo,lunar_leo,moon}}`。

`state_*` 值包装：`{r:[x,y,z] km, v:[vx,vy,vz] km/s}`；`reference.*.position_earth_rot_km` 为
地心旋转系（与 navigation 内容 `abstract_pos_km` 同系）。

## 5　navigation 位置 provider

- 绑定：bridge boot/restart 后 `nav.bind_position_provider(_nav_shadow_position)`（仅 shadow 模式；
  off 模式调用 `clear_position_provider()` 回退 abstract）。
- 返回：地心旋转系 km（`Array[x,y,z]`），供 `vm_navigation.nodes[].pos_km` /
  `nav.resolve_positions()` 使用；**不参与路线成本/许可/机动**。
- 映射（`position_source`）：

| provider source | 位置来源 |
| --- | --- |
| `cislunar:earth_port` | `[R_earth,0,0]`（地心旋转系） |
| `cislunar:geo_ring` | `physics.geo_state(t)` → earth-rot |
| `cislunar:l1_station` / `l2_station` / `l4_station` / `l5_station` | CR3BP 平衡点 → earth-rot（L1≈326,381 km；L2≈448,915；L4/L5≈384,400） |
| `cislunar:lunar_port` | 月球 earth-rot 位置 − `R_moon`（→ 到月≈1,737.4 km） |
| `cislunar:lunar_leo` | `physics.llo_state(t)` → earth-rot（≈1,837.4 km 绕月） |
| 未知 source | `[]` → navigation 回退内容 abstract 坐标 |

- off/未就绪时导航节点位置回到内容 abstract（probe 验证 l1≈326,283 km）。

## 6　关闭与降级

- `V17_PHYSICS=off`：bridge 不创建物理、`physics_mode="off"`、`physics_ready=false`、
  `physics_view()` 空、state physics 字段为空/false、导航 provider 不绑定（抽象坐标）。
- 物理内容/初始化失败：`errors` 记录、shadow 不可用但 bridge/world/nav 继续（不阻塞 boot）。
- 推进失败/发散/NaN：`warnings` 记录（去重、≤32 条），实体状态由物理模型自身 sanitize；
  不影响 V15/V2 world。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_physics_shadow_probe.gd
# V17 PHYSICS SHADOW PROBE RESULT: PASS=277 FAIL=0（exit 0）
```

覆盖（11 节）：boot/实体装载（9 实体、source 标注、三系状态、Jacobi）；L1–L5/GEO/LLO/月球参考
（距离/半径/周期）；step/Jacobi 漂移/warnings；**V15 轨道/等级/身份/传感器/clock/决策/实体 orbit
不变**；navigation provider 位置替换（l1/l2/l4/geo/moon_port/llo）+ 规划成本不变/不自动执行；
state 字段与旧字段兼容；JSON 回读；不自动执行导航机动；`V17_PHYSICS=off` 降级；restart 复位
（t=0/实体重载/provider 重绑）；长程 3600s finite / Jacobi 漂移 <1e-3。

回归（同任务）：`v17_bridge_probe` 138/0、`v17_nav_integration_probe` 182/0、
`cislunar_physics_probe` 269/0、`nav_probe` 372/0、boot/main headless exit 0。

## 8　边界（明确不做 / 不假装）

- **非 JPL 星历**：圆轨道 + CR3BP；无太阳引力/J2/月球偏心率/倾角/质心摆动。
- 实体初始状态是 V2 场景 L1 局部近似/固定占位（`source` 标注），不是真实历元状态。
- Godot `Vector3` float32：~3.8e5 km 处位置精度 ~0.03 km；高精度需 double/归一化（R6）。
- 固定步长 ≤60s；未做自适应/辛积分；时间加速仍按 dt 分步。
- **不替换 V15 位置源**、不写 V15/V2 world、不接 HUD/plot、不生成武器/伤害。
- 导航仍用抽象转移成本；provider 仅位置显示/几何参考。
- 未接姿态/推力/质量/传感器几何；不自动执行导航机动。
- 未 commit。
