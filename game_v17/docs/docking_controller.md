# R6-DOCKING-1 · 交会 / 对接几何控制器

> 任务 task-87。工程 `game_v17`。
> 文件：`framework/sim/docking_controller.gd`（新模型）、`tests/docking_probe.gd`（新 probe）、本文件（新）。
> **纯几何/状态机模型**：不接 UI/HUD，不接 world/core，不做物理积分，不写 tracks/state，不生成命令。
> 复用 `framework/sim/cislunar_physics.gd` 的纯数学 `approach_corridor_check` / `docking_geometry`，不修改该文件。

---

## 1　定位与不变量

- **一个控制器 = 一个 chaser 对目标端口的一次交会/对接流程**；端口集与目标端口由调用方提供/选择，控制器只读端口数据。
- 输入：LVLH 相对状态 `rel_pos = target - chaser`（km）、`rel_vel = target_vel - chaser_vel`（km/s）、chaser 端口轴（LVLH，可选）与 `dt`。
- 输出：只读快照 `vm()`/`update()`（状态、走廊、制导、判定、门限、事件、失败原因）。
- **不执行**：不调用 physics.propagate、不写 V2 world/state/track、不写 V15；`writes` 全 false，`authoritative=false`。
- 状态推进只在显式 `update()`/`hold()`/`resume()`/`abort()`/`fail()`/`undock()`/`reset()` 中发生；不自动点执行/不自动对接物理。

---

## 2　端口模型

### 2.1 schema（`v17_docking_port.v1`）

```jsonc
{
  "schema": "v17_docking_port.v1",
  "port_id": "chronos-dock-a",
  "owner_id": "chronos_station",
  "owner_kind": "station|ship|tank",
  "kind": "dock|berth|truss",
  "axis": [1.0, 0.0, 0.0],      // 端口朝外方向（LVLH 单位向量）
  "radius_m": 2.4,
  "status": "open|occupied|damaged|closed",
  "compatible": ["ship"],        // chaser 类型；未知/不兼容拒绝
  "name": "Chronos DOCK-A · 主对接环",
  "meta": {}
}
```

默认端口（`default_ports()`，仅模型样例）：

| port_id | owner | kind | axis | status | 说明 |
| --- | --- | --- | --- | --- | --- |
| `chronos-dock-a` | `chronos_station` | dock | `[1,0,0]` | open | 主对接环 |
| `chronos-dock-b` | `chronos_station` | dock | `[-1,0,0]` | occupied | 辅助环（被占用） |
| `chronos-berth-1` | `tank_farm` | berth | `[0,0,1]` | damaged | 储罐停泊位（损坏） |
| `harmattan-port` | `harmattan` | dock | `[-1,0,0]` | open | 本舰主对接环 |

### 2.2 API

```gdscript
DockingController.make_port(port_id, owner_id, kind, axis, radius_m, opts) -> Dictionary
DockingController.default_ports() -> Array

var c = DockingController.new()
c.setup(ports := [], opts := {}) -> bool       # 空 ports 用默认集
c.add_port(raw) / c.remove_port(port_id) -> Dictionary
c.select_target_port(port_id := "", owner_id := "", chaser_kind := "ship") -> Dictionary
c.target_port() -> Dictionary
```

- 选择：显式 `port_id` 优先；`owner_id` 过滤下选第一个 `open` 且兼容端口；occupied/damaged/unknown/incompatible 返回 `{ok:false,reason}`。
- `docked` 状态拒绝直接换端口，必须先 `undock()`。
- 端口删除目标时清 target 并回 `far`；不伪造隐藏端口。

---

## 3　输入与相对制导

### 3.1 输入

```gdscript
rel = {
  "dr": [x, y, z],        # km，target - chaser（LVLH）
  "dv": [vx, vy, vz],     # km/s，target_vel - chaser_vel
}
attitude = {
  "chaser_port_axis": [x, y, z],  # 可选；chaser 端口朝外轴（LVLH）
}
c.update(rel, attitude, dt := 0.0) -> snapshot
c.preview(rel, attitude)            # 只评估，不推进状态（别名 evaluate）
```

- 约定：目标端口轴 `A_t` 近似 `rel_pos` 方向（target→chaser）；chaser 对接轴应指向目标，即 `-rel_pos` 方向。
- 未提供 chaser 轴时：`chaser_axis_available=false`、`chaser_align_angle_deg=-1`，**不能 `docked`**（只能到 alignment/final），不伪造姿态。
- 非有限/非法相对状态返回 `{ok:false,reason:"invalid_relative_state"}`，状态机不推进。

### 3.2 制导输出（`v17_docking_guidance.v1`）

```jsonc
{
  "schema":"v17_docking_guidance.v1",
  "available":true,
  "range_km":50.0, "standoff_km":0.02, "range_error_km":49.98,
  "closing_actual_mps":10.0, "closing_desired_mps":1.5,
  "time_to_go_s":..., "lateral_km":2.0, "lateral_rate_cmd_mps":...,
  "dv_mps":[x,y,z], "dv_magnitude_mps":...,
  "attitude_available":true,
  "attitude_desired_axis":[-1,0,0],
  "attitude_error_deg":...,
  "gates":{far_km/align_range_km/final_km/contact_tol_km/align_tol_deg/final_closing_mps/dock_speed_mps},
  "warnings":[...]
}
```

- `dv_mps` 是**建议**相对速度修正（当前速度 → 期望相对速度），被 `guidance_max_dv_mps` 限制；不是已执行命令。
- 期望接近速度：`closing_desired = clamp(base + gain * (range - standoff), 0.05, guidance_max_closing_mps)` m/s。
- 横向修正：向 `-lateral_vec` 收敛，`lateral_rate_cmd` 有上限。
- `time_to_go` 基于 max(实际接近率, 期望接近率) 与剩余距离；停止时可为 -1。
- 姿态建议轴：`-rel_pos.normalized()`（chaser 指向目标）；输出误差角，不生成姿态控制指令。

---

## 4　接近走廊

复用 `cislunar_physics.approach_corridor_check(rel_pos, rel_vel, spec)`，`spec.axis = target_port.axis`：

| 门限 | 默认 |
| --- | --- |
| `length_km` | 100 |
| `half_angle_deg` | 10° |
| `lateral_tol_km` | 2.0 |
| `max_closing_mps` | 50 |
| `max_angle_deg` | 15° |

返回 `ok/inside/range_km/along_km/lateral_km/corridor_radius_km/align_angle_deg/closing_mps/angle_ok/speed_ok/warnings`。
走廊内但速度/角度不满足时，近距离可进入 `hold`；走廊外进入 `approach`。

---

## 5　状态机

状态：`far / approach / corridor / hold / alignment / final / docked / aborted / failed`。

| 状态 | 含义 | 典型进入条件 |
| --- | --- | --- |
| `far` | 尚未近距离 | 无 target，或 range > `far_km`(250) |
| `approach` | 接近但不在走廊/门限内 | 走廊外或未对齐 |
| `corridor` | 在接近走廊且速度/角度满足 | `corridor.ok` 且 range > align_range |
| `hold` | 暂停等待（显式或速度/角度违例） | `hold_requested` 或近距离走廊违例 |
| `alignment` | 已对齐，准备末端 | `align_ready` 且 range ≤ `align_range_km`(2) |
| `final` | 末端对接窗内 | `final_ready` 且 range ≤ `final_km`(0.25) |
| `docked` | 对接成功（锁存） | `docking_geometry.status=="docked"` + 判定门限 + chaser 轴有且 ≤5° |
| `aborted` | 显式中止（终态） | `abort()` |
| `failed` | 硬失败（终态） | 接触速度/横向/姿态超硬限，或 `fail()` |

- `update()` 返回当前快照；`docked/aborted/failed` 为终态，`docked` 只由 `undock()` 解除，其余由 `reset()` 清除。
- `docked` 锁存后，再给任意 rel 仍保持 docked（直到 undock）。
- `hold()` 设置显式 hold，`resume()` 清除；自动 hold 在走廊违例解除后下次 update 可离开。
- 状态转换均写 `events[]`（最多 64 条），不写外部。

---

## 6　对接判定

核心判定（`docking_geometry` + chaser 轴）：

| 判定 | 默认门限 |
| --- | --- |
| 距离 range | ≤ `contact_tol_km` 0.05 km（`docking_tol_km`） |
| 横向 lateral | ≤ `align_lateral_km` 0.2 km |
| 目标端口对齐 | ≤ `align_tol_deg` 5° |
| chaser 端口对齐 | ≤ `align_tol_deg` 5°（必须提供轴） |
| 接触速度 closing | ≤ `dock_speed_mps` 0.1 m/s |
| 横向速度 | ≤ `max_lateral_mps` 5 m/s（physics default） |

- 失败原因（`failure_reason` / `hard_fail`）：`contact_speed`、`lateral_misalignment`、`attitude_misalignment`；`docking_geometry` 自身还会给 `too_fast/misaligned` 警告。
- 判定失败不自动改外部实体；`docked` 只是控制器状态，需由上层 world/core 在 authoritative 切层后消费/落账。
- `undock(reason)`：`docked → approach`，记录 `undocked_t`、清 `docked_t`；非 docked 返回 `{ok:false,reason:"not_docked"}`。

---

## 7　配置与只读 view-model

### 7.1 配置（`setup(ports, opts)` 可覆盖）

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `far_km` | 250 | 远处阈值 |
| `align_range_km` | 2.0 | 对齐窗 |
| `final_km` | 0.25 | 末端窗 |
| `hold_range_km` | 5.0 | 违例 hold 范围 |
| `contact_tol_km` | 0.05 | 对接距离 |
| `final_standoff_km` | 0.02 | 制导停机距离 |
| `align_tol_deg` | 5.0 | 目标/chaser 对齐 |
| `align_lateral_km` | 0.2 | 对齐横向 |
| `hard_align_deg` | 15 | 硬失败姿态 |
| `hard_lateral_km` | 0.5 | 硬失败横向 |
| `hard_max_closing_mps` | 2.0 | 硬失败接触速度 |
| `final_closing_mps` | 0.5 | final 窗速度 |
| `dock_speed_mps` | 0.1 | 对接接触速度 |
| `guidance_max_dv_mps` | 3.0 | 建议 Δv 上限 |
| `corridor` / `docking` | physics defaults | 覆盖走廊/判定参数 |

### 7.2 vm（`v17_docking.v1`）

包含：`state/state_order/t/target_port_id/target_port/ports/config/last/events/hold_requested/hold_reason/failure_reason/docked_t/undocked_t/writes/authoritative`。
`update()` 返回当前 snapshot（含 `corridor/docking/guidance/align_ready/final_ready/docking_ok/hard_fail/warnings`）；`vm()` 返回完整只读状态。
`state_signature()` 用于 probe/回放确定性；`to_dict()` = vm。

Writes 均为 false：`world/physics/track_table/v15`；`authoritative=false`。

---

## 8　R6 接入点与边界

### 8.1 后续接入顺序（本任务不实现）

1. **core/world** 每 tick 从真实物理/相对状态生成 `rel`（LVLH `dr/dv`）与 chaser 姿态（来自实体 attitude/port mount），调用 `update(dt, rel, attitude)`；
2. `docked` 事件只在 core 的 authoritative 物理切换完成后由 world 落账（停靠位置/父子关系/资源），控制器不直接写；
3. 制导输出交给命令/导航层（R4/R6），由命令层生成 Δv/姿态指令；控制器不生成/执行命令；
4. UI/HUD 只读 `vm()`/snapshot；本任务不接。

### 8.2 边界

- 无碰撞/接触力/结构损伤/对接机构动力学（只几何+状态机）。
- 端口位置/朝向是调用方提供的 LVLH 端口定义；本模型不计算站体本体几何或姿态传播。
- 端口轴/姿态必须显式给；无 chaser 轴不判 docked，显示 `-1`。
- 不做多端口并行/抢占/排队；一次控制器一个 target port；端口状态由外部维护。
- `docked` 不自动持久化、不自动 undock；需显式生命周期。
- 物理模型/星历边界沿用 `cislunar_physics`；本控制器只读调用其纯数学函数。

---

## 9　probe / 验证

单次运行：

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/docking_probe.gd
# R6 DOCKING PROBE RESULT: PASS=318 FAIL=0 · exit 0
```

覆盖（10 节 / 318 断言）：
- 端口 schema/默认集/选择/occupied/damaged/unknown/incompatible/owner 过滤/docked 拒绝/remove；
- 非法端口/setup/duplicate/add/remove；
- far/approach/corridor 与走廊 inside/angle/speed/closing；
- hold（自动速度 hold/显式 hold/resume/终止态拒绝）；
- alignment/final/docked（锁存、无姿态不 dock、姿态错失败）；
- undock/abort/fail/invalid rel；
- 制导 schema/range/standoff/closing/TGO/dv 3D 与上限/姿态误差/门限/横向方向；
- 硬失败 contact_speed/lateral_misalignment/attitude_misalignment；
- vm/JSON/signature/reset/writes/两实例确定性。

---

## 10　未完成 / 待接入

1. 未接 world/core/物理；`docked` 无实体落账（设计上由后续 world adapter 完成）。
2. 端口数据仍是模型默认样例；真实站体/舰船端口来自 R3/R6 几何/数据后替换。
3. 未接 UI/HUD/plot；无对接走廊可视化/提示。
4. 无强制/接触动力学、无 docked 后的相对漂移/脱离动力学（undock 仅状态复位）。
5. 多端口占用/多船排队/对接许可未做；本任务只单 controller 单端口。
