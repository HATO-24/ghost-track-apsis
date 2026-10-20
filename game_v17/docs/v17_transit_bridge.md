# 阶段2-CORE-B · transit 场景 + L4→L1 转移接 bridge/state

> 任务 阶段2-CORE-B（task-99）。工程 `game_v17`。
> 只改 `scripts/framework_bridge.gd`、`scripts/state.gd`、`tests/*`、`docs/*`；
> 不改 hud/plot/main/project、core/sim 模型；未 commit。
> **默认 legacy，不切启动；不接 HUD；transit 只是 bridge/state 只读数据路径。**
> 最小 probe：`tests/v17_transit_bridge_probe.gd` → `PASS=136 FAIL=0`（单次约 56 s）。

## 1　模式（`V17_SCENARIO=transit|legacy`）

| 值 | 行为 |
| --- | --- |
| 未设/空/其它/`legacy`（默认） | 加载原默认场景 `scenario_l1_v2.json`（V15/旧关卡不变）；`scenario_mode="legacy"`；不做转移规划；`transfer_ready=false` |
| `transit`（显式） | 加载 `framework/content/scenario_transit_l4_l1.json`（补 `tracks=[]`/`phases=[]` 通过 V2 场景校验）；own=apsis；旧关卡实体不进入 V2 场景；运行一次 `transfer_planner.plan()` 并缓存；`scenario_mode="transit"`、`transfer_ready=true` |
| transit 场景加载失败 | 回落 legacy，记录 `scenario_fallback_reason`，不崩溃 |
| 未知值 | 按 legacy（不报错） |

> **不改默认启动**：`main`/HUD 仍走 V15 legacy 显示；transit 数据只在 bridge/state 只读字段中。
> transit 场景 `tracks=[]`，因此 V2 contacts 为空（sensor/info/optical 等 bridge 子系统照常初始化但不产生接触）。

## 2　bridge API（只读）

| API / 字段 | 说明 |
| --- | --- |
| `scenario_mode` / `scenario_requested_mode` / `scenario_fallback_reason` | 有效/请求/回落原因 |
| `scenario_view()` | `v17_scenario_bridge.v1`：mode/requested/fallback/scenario_id/title/datum/own_entity/entity_count/station_count/transfer_ready/source_port/target_port |
| `own_reference()` | `v17_own_reference.v1`：scenario_mode/scenario_id/own_entity/batch/display_name/lpoint/source_port/target_port（transit: apsis/1000） |
| `transfer_plan()` | 缓存 `transfer_planner.plan()` 结果（`v17_transfer_l4_l1.v1`：source/target/transfer{timeline, Δv, arrival, fleet…}）；legacy 为空 |
| `transfer_ready` | bool（transit 且 plan.ok） |
| `transfer_tick(t_s)` | `v17_transfer_tick.v1` **只读插值**（不做新物理）：按 timeline 线性插值 pos/vel；`t` clamp 到 [0,tof]；`phase=departure/cruise/arrival`；返回 t_s/requested_t_s/t_days/clamped/progress/pos_rot_km/vel_rot_kmps/range_to_target_km/timeline_index/tof_s；未就绪 `ok=false` |
| `scenario_entity_list()` / `scenario_station_list()` | 场景实体/固定体只读行：id/batch/kind/side/name/fixed/orbit_frame/orbit_r/orbit_v/tags；station 为 `is_fixed()` 子集 |
| `bridge_state()` | 增 scenario_mode/requested/fallback/scenario/own_reference/scenario_entities/scenario_stations/transfer/transfer_ready |

## 3　state API（不接 HUD）

| 字段 / 方法 | 说明 |
| --- | --- |
| `fw_transfer` | 转移计划深拷贝（`fw_sync` 刷新；legacy 为空） |
| `fw_transfer_ready` | bool |
| `fw_scenario` | 场景视图（v17_scenario_bridge.v1） |
| `fw_own_reference` | 本舰参考（transit: apsis/1000；legacy: harmattan/1001） |
| `fw_scenario_entities` / `fw_scenario_stations` | 场景实体/固定体只读映射（不写 state.tracks） |
| `fw_transfer_tick(t_s)` | 只读 tick 包装（同 bridge.transfer_tick） |
| `fw_transfer_view()`/`fw_scenario_view()`/`fw_scenario_entity_list()`/`fw_scenario_station_list()` | getters |
| `fw_bridge_state()` | 增 scenario/own_reference/scenario_entities/scenario_stations/transfer/transfer_ready |
| 旧字段 | `fw_sensor*/fw_info*/fw_physics*/fw_optical*/fw_docking*` 等全部不变 |

**V15 不写**：transit 下 `state.tracks`（V15 旧关卡）不被 bridge 写；`fw_sync` 只拉只读字段。
legacy 默认路径行为与之前一致（probe 断言 legacy 场景 id/own/transfer_ready 不变）。

## 4　transit 场景与转移结果（本次实测）

- 场景：`transit_l4_l1`（9 实体：舰队 5 + L4-02 母港 + L1 港群 3；无旧关卡实体）。
- own=apsis（batch 1000），datum=L4；source_port=`l4_02_hammer`，target_port=`l1_meridian_05`。
- 转移（缓存一次）：**TOF 6.00 天，Δv 1,822.6 m/s**，入轨半径 **0.771 km**、相对速度 **0.969 km/s**，
  `arrival.ok=true`；timeline 11 点；fleet 5 舰（详细见 `docs/transfer_l4_l1.md`）。
- `transfer_tick`：t=0 → departure/progress 0；tof/2 → cruise/progress 0.5；tof → arrival/progress 1；
  超界 clamp 到端点；timeline 采样点可精确还原（误差 <1e-6 km）。
- transit boot 需运行一次规划（headless 约 18–20 s）；之后 `transfer_tick` 为纯插值（O(timeline)）。

## 5　最小验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_transit_bridge_probe.gd
# V17 TRANSIT BRIDGE PROBE RESULT: PASS=136 FAIL=0（exit 0；单次约 56 s）
```

覆盖（5 节）：
1. **legacy 默认**：scenario_mode/requested=legacy、场景 id=l1_supervision_v2、own=harmattan(1001)、
   transfer_ready=false、transfer 空、tick ok=false、entities/stations>0、state 字段、旧 sensor/physics 字段正常；
2. **transit**：场景 id/own=apsis(1000)/source/target、transfer_ready=true、plan schema/ok/TOF/Δv/arrival/
   timeline 11/fleet 5、场景实体 9（旧实体不存在）、station ≥4、state 字段、**V15 tracks/r/v/等级/clock 不变**、
   bridge_state 字段；
3. **transfer_tick**：departure/cruise/arrival、progress、超界/负时间 clamp、timeline 采样点还原、
   state 包装一致、JSON；
4. **legacy/回退**：显式 legacy 与未知值均回 legacy、transfer_ready=false、场景 id 不变；
5. **JSON**：fw_transfer/fw_scenario/fw_own_reference/fw_bridge_state 可回读（bridge JSON ~59 KB）。
按任务要求只跑一次，未跑全量回归。

## 6　真实 / 近似边界

- 转移计划本身为 CR3BP/RK4 + Lambert 种子的模型结果（见 `transfer_l4_l1.md` 真实/近似边界）；
  `transfer_tick` 是**只读线性插值**，不做新物理、不推进 world、不写 V15。
- transit 场景数据骨架中 `tracks=[]`，V2 contacts 为空（不是完整 detection/fusion 数据）；
  sensor/info/optical/bridge 子系统仍按空场景初始化。
- 港站为旋转系固定/站保持近似；不落实体、不执行推力、不生成任务/剧情/教学。
- 默认 legacy：transit 需显式 `V17_SCENARIO=transit`；不接 HUD/plot/存档；未 commit。

## 7　接入建议（后续任务）

1. 启动/切场景：后续由显式流程设置 `V17_SCENARIO=transit`（当前不改默认启动），或新增场景切换 API。
2. HUD/剧情：读取 `fw_transfer_tick(t)` 获取位置/阶段/进度；`fw_scenario_*` 用于实体/港群列表；
   `fw_transfer.arrival/fleet` 用于到达/舰队面板（需另立 HUD 任务）。
3. 若要“旧关卡不展示”，需在 V15/HUD 层按 `fw_scenario.mode` 切换显示；本任务不接 HUD。
4. 性能：transit boot 只规划一次（缓存）；restart 复用缓存（`transfer_plan_data` 非空不重算）；
   tick O(timeline)。
5. 回退：删除 env 即 legacy；数据/字段全部只读，不影响现有流程。
