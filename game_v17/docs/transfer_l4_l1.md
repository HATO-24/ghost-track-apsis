# 阶段2-CORE-A · L4-02 → L1 真实轨道转场

> 任务 阶段2-CORE-A（task-97）。工程 `game_v17`。
> 新文件（未改 core/ui/state/bridge/project；未 commit）：
> - `framework/sim/transfer_planner.gd`（转移规划器）
> - `framework/content/scenario_transit_l4_l1.json`（新场景骨架）
> - `tests/transfer_probe.gd`（最小 probe，`PASS=451 FAIL=0`）
> - 本文件
> 不接 UI/bridge；不改默认启动。

## 1　定位与不变量

- **真实转移**：地月 CR3BP 动力学（`framework/sim/cislunar_physics.gd` 的 RK4，
  `propagate_state`，步长 ≤60s），**不是**直线/脚本插值。
- 求解链：两体 Lambert（Earth ECI 种子，短/长程两分支）→ 旋转系初速 →
  CR3BP 打靶（有限差分 Newton，固定 TOF，命中 L1 港位置）→ departure burn + arrival burn；
  可选半程中途修正（MCC）。
- 默认扫描 TOF ∈ {3,4,5,6} 天 × 两分支 Lambert 种子；选**可行且总 Δv 最小**的解。
- 不写 V15/不落实体/不执行推力；输出纯规划数据（JSON 可序列化）；确定性（同输入同输出）。

## 2　场景骨架（`scenario_transit_l4_l1.json`，仅数据）

- `schema=scenario.v2`、`id=transit_l4_l1`、`own_entity=apsis`、`datum=L4`、
  `meta.stage=stage2-core-A`、`meta.default_start=false`（不改默认启动）。
- **L4-02 Hammer 母港**：`l4_02_hammer`（station，L4 偏移 `[-520,310,40] km`）。
- **L1 港群**：`l1_meridian_05`（主港，目标）、`l1_anchorage_02`（泊位）、
  `l1_drydock_01`（干坞），L1 偏移见文件。
- **舰队 5 舰**：`apsis`（旗舰）/`harmattan`/`ferry`/`watchtower`/`deepwell`
  （批次 1000–1004；`meta.fleet_offset_km` 为规划器小偏移）。
- **无旧关卡实体**：不含 `summons_4471/ceres_2/chronos_station/tank_farm`；
  `transfer` 节记录 source/target/planner/TOF 候选/入轨门限。
- 该文件当前不被默认启动读取；由后续任务决定如何载入。

## 3　API（`transfer_planner.gd`，全部 static）

| API | 说明 |
| --- | --- |
| `plan(opts := {}) -> Dictionary` | 主规划。opts：`tof_days`（默认 [3,4,5,6]）、`arrival_radius_gate_km`（3000）、`arrival_speed_gate_kmps`（3.0）、`max_total_dv_mps`（10000）、`include_mcc`（true） |
| `to_json(opts := {}) -> String` | `JSON.stringify(plan(opts))` |
| `lambert(r1v, r2v, tof_s, mu_km3_s2, prograde) -> Dictionary` | 两体 Lambert（短/长程；返回 v1/v2/dnu/z/f/g/gdot） |
| `l4_port_state() / l1_port_state() -> Dictionary` | 源/目标港旋转系状态（`{r,v}`，km/km/s） |
| `l1_cluster_offsets() -> Array` | L1 港群 3 个端口偏移 |
| `Physics.propagate_state(state, dt, {step_s:60})` | 底层 CR3BP/RK4 传播（仅引用，不修改） |

### 3.1　输出（`v17_transfer_l4_l1.v1`）

```
{
 schema, ok, reason, scenario_id,
 frame {inertial:"earth_eci", rotating:"bary_rot", units:"km,km/s,s"},
 source {port_id, lpoint, pos_rot_km, vel_rot_kmps, earth_distance_km, moon_distance_km},
 target {同上},
 transfer {
   method:"lambert_seed_cr3bp_shooting", tof_s, tof_days, prograde,
   lambert {ok, dnu_deg, prograde, z},
   shooting {iterations, converged, error_km},
   depart_state_rot {r,v}, arrival_state_rot {r,v},
   depart_dv_rot, arrival_dv_rot,
   depart_dv_mps, arrival_dv_mps, mcc_dv_mps, total_dv_mps,
   mcc {applied, dv_mps, dv, mid_t_s, mid_state_rot, reason},
   candidate_count
 },
 arrival {radius_km, relative_speed_kmps, gate_radius_km, gate_speed_kmps,
          time_window_ok, time_window_days, ok},
 timeline [11 × {schema, t_s, t_days, pos_rot_km, vel_rot_kmps,
                 range_to_target_km, alt_km, error_km}],
 fleet [5 × {id, batch, role, offset_km, offset_kmps,
             initial_state_rot, depart_state_rot,
             arrival_state_rot {ok,r,v}, arrival_error_km,
             arrival_speed_kmps, within_gate}],
 budget {depart_dv_mps, arrival_dv_mps, mcc_dv_mps, total_dv_mps},
 warnings, errors, deterministic:true, note
}
```

- `target_rot.v=0`（港站旋转系站保持）；arrival Δv = |v_arrival_rot − 0|。
- 入轨判定：`radius_km ≤ gate_radius_km`（默认 3000）、`relative_speed_kmps ≤ gate_speed_kmps`
  （默认 3.0）、TOF 在 [1,15] 天；不满足时 `ok=false, reason="arrival_gate_failed"`（不伪造）。
- 首点 t=0；末点 t=TOF；每点含目标距离/误差。

## 4　本次结果（probe 实测，确定性）

| 项 | 值 |
| --- | --- |
| 源/目标 | L4-02 Hammer（L4 偏 606.7 km）→ L1 Meridian-05（L1 偏 184.2 km） |
| L1/L4 地心距 | 326,380.9 km / 384,400.0 km |
| Lambert 种子 | dnu=18.952°，prograde，CR3BP 打靶 4 次迭代，误差 0.771 km |
| TOF | **6.00 天** |
| Δv | departure **853.4 m/s** + arrival **969.2 m/s** + MCC 0 m/s = **1,822.6 m/s** |
| 入轨 | 半径 **0.771 km**、相对速度 **0.969 km/s**、时间窗通过 → `arrival.ok=true` |
| 时间线 | 11 点（0 → 518,400 s），末点距目标 0.771 km |
| 舰队（共享转移 + 小偏移） | apsis 1 km / harmattan 544 km / ferry 592 km / watchtower 1193 km / deepwell 1381 km，均 ≤3000 km 门限 |
| 候选 | 8 条（4 TOF × 2 Lambert 分支） |

## 5　真实 / 近似边界（重要）

- **真实部分**：最终轨迹由 CR3BP/RK4 在旋转系积分（含 Coriolis/离心/三体引力），
  departure/arrival 状态、时间线、到达误差、入轨判定均由真实传播得出；不是直线插值。
- **近似部分**：
  - Lambert 种子为 **两体（Earth ECI）** 初值，仅用于给 CR3BP 打靶一个合理初速；
  - CR3BP 忽略地球扁率/J2、太阳引力、月球偏心率与倾角、质心摆动（物理核心既有边界）；
  - 港站视为旋转系固定站保持（v_rot=0，无真实站保持推力/星历）；L4-02/L1 港用偏移近似；
  - 固定 TOF 打靶只约束**到达位置**；arrival burn 为非约束相对速度（Δv 实测 ~969 m/s），
    未做到达速度优化/多脉冲最优求解；
  - MCC 默认按半程小修正计算（本次主解残差 <1 km，`applied=false`），不是完整中途制导；
  - 舰队为共享 Δv + 小位置/速度偏移的**开环**传播（不做编队保持/避碰/通信时延）；
  - Float32 Vector3 在 38 万 km 量级精度 ~0.03 km；数值为模型值，非 JPL 星历。
- 结论：**“真实轨道转场（CR3BP/RK4），带两体 Lambert 种子与脉冲 Δv 近似”**，
  不是高保真星历/最优控制。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/transfer_probe.gd
# V17 TRANSFER PROBE RESULT: PASS=451 FAIL=0（exit 0；单次约 53 s）
```

覆盖（9 节）：场景骨架字段/实体/无旧关卡实体；L4/L1 位置与港口偏移；RK4 传播
（60s/0s/批量/确定性/往返/Jacobi 漂移/非法状态）；Lambert（短/长程、字段、种子转换、
非法输入）；转移方案（TOF/打靶/Δv/预算/入轨判定/候选）；时间线 11 点单调/距离/误差；
舰队 5 舰状态与门限；JSON 回读与确定性（两次 plan 完全一致）；边界（空/负 TOF、
不可达门限、no_mcc、非法 Lambert/传播）。按任务要求只跑一次，未跑全量回归。

## 7　接入方式（后续任务，不在本任务）

1. 由新场景 `transit_l4_l1` 启动（当前不改默认启动）：载入场景 JSON，取 source/target 端口。
2. 调用 `V2Planner.plan()` 获得时间线/Δv/入轨状态；供第 3 阶段 UI/剧情消费（本任务不接）。
3. 若接 bridge：建议只读 `plan()` 快照（不写 V15）；舰队状态可映射到 V15 显示字段
   （与 R5 显示层权威类似），但需另立任务与显式 env，默认关闭。
4. 性能：完整 `plan()`（8 候选 × 打靶）约 18 s（headless）；可传 `tof_days` 单值降至 ~4–5 s。
5. 回退：不启用新场景即保持现状；planner 为独立新文件，不改变任何现有行为。

## 8　未完成 / 待办

- 未做 arrival Δv 最优（可用 6 变量打靶/多脉冲序列/到达速度约束进一步降低 ~1,822 m/s）。
- 未接真实星历、J2、太阳光压、月球倾角/偏心率；港站无站保持推力模型。
- 未接 UI/bridge/存档；未定义剧情/事件/教学；未 commit。
