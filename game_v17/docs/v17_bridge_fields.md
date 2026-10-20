# V17 数据桥字段 / 接口（HUD / plot 对接）

> V17-CORE-1（task-54）。工程 `game_v17` = V15 视觉（HUD/plot 原有）+ `framework/` 的 V2 core/sim
> 数据后端。本文件列出 HUD/plot 需要读取的字段与可调用方法；**视觉层不要反向改 core**。
> 相关文件：`scripts/framework_bridge.gd`（V17Bridge）、`scripts/state.gd`（WarState 的 fw_* 字段）、
> `scripts/main.gd`（每帧 `state.fw_sync(delta)`）、`tests/v17_bridge_probe.gd`。

## 0　启动 / 每帧

```gdscript
# main._ready()
framework = FrameworkBridge.new()
framework.boot()                # 装载 framework/content/scenario_l1_v2.json + world + mission
state.framework = framework
state.fw_sync(0.0)              # 首帧快照

# main._process(delta)
state.refresh(state.clock)      # V15 原流程（不改）
state.fw_sync(delta)            # V2 数据桥：暂停/冻结/截图时内部 dt=0
```

- boot 时默认 **跳过 V2 PRELUDE**（V15 自己拥有 PRELUDE 覆盖层），避免“执行前冻结”双门控；
  需要 V2 prelude 时设 `DSH_V2_PRELUDE=1`。
- 启动打印：`V17 FRAMEWORK ok=... summary={...}` 与 `V17 BRIDGE ready=... contacts=10 ...`。

## 1　state 上的只读字段（HUD/plot 直接读）

| 字段 | 类型 | 来源 / 说明 |
| --- | --- | --- |
| `state.fw_ready` | bool | bridge 是否就绪（未就绪时 HUD 应隐藏新块，不占位） |
| `state.fw_tutorial` | Dictionary | `world.vm_tutorial()`：`enabled/ready/title/hint/done_text/required_actions/min_required/completed[{id,label,at}]/missing[]/progress{done,need}/decision_pending/actions[{id,label,done,at,available,reason}]` |
| `state.fw_flow` | Dictionary | `world.vm_flow()`：`prelude/decision/report/end/mission/tutorial/exec_window_s/exec_left/exec_pct/reputation{ocu,meridian,ueg_doves,outer,reclaimers}/reputation_settled/damage/replay/flags` |
| `state.fw_damage` | Dictionary | `world.vm_damage()`：`entity_id/entity_name/sections[{id,label,state,severity,severity_pct,repair_eta_s,repair_remaining_s,progress,can_repair}]/queue/summary{total,damaged,degraded,repairing,repaired,needs_attention}/repair_rate_s` |
| `state.fw_replay` | Dictionary | `world.vm_replay()`：`recording/playing/paused/index/total/interval_s/t/current{帧}/frames[{index,t,phase,kind,decision_made,ended}]/pinned/frame_t`。**语义**：`t` = 录制时钟（世界时间），不是当前帧时间；当前帧时间看 `frames[index].t` 或 `current.t` / `frame_t`。`index` 是回放查看头；调用 `fw_replay_seek(t)` 或 `fw_replay_seek_index(i)` 后 `pinned=true`，录制继续追加帧不会移动查看头；`fw_replay_stop()` 解除固定。 |
| `state.fw_contacts` | Array | 10 条归一接触（V2 `vm_contacts()`；V15 `tracks` 仍独立保留） |
| `state.fw_actions` | Array | 当前选中目标的可用动作（`available/reason/reason_code`，含 actor_id/actor_name） |
| `state.fw_actions_target` | String | 上面 action 列表对应批号 |
| `state.fw_decision_reason` | String | V15 决策被教学门控阻塞的原因（"" = 未阻塞）；HUD 决策入口置灰时显示 |
| `state.fw_decision_deferred` | bool | 决策已到点但被门控挂起 |
| `state.fw_sync_count` | int | 同步次数（HUD 判定数据新鲜度用） |
| `state.fw_t` | float | V2 世界时间（秒） |
| `state.fw_last_action` | Dictionary | 最近一次 `fw_perform_action` 的返回（供 HUD 提示/日志） |
| `state.framework` | V17Bridge | 直接读 `framework.tutorial/damage/replay` 等快照或 `framework.world`（只读） |

补充字段（`state.fw_flow` 内）：`decision{open, prompt, options[{kind,label,hint,enabled,reason}], evidence_count, can_expose, decision, reply, consequence}`、
`report{available, submitted, ending_kind, audit_flag, report}`、`end{ok, ending_kind, report, reputation, reputation_settled, ...}`。

## 2　state 上的封装方法（HUD 只调这些写 V2）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `state.fw_sync(dt)` | void | 每帧同步；暂停/冻结/截图时内部 dt=0 |
| `state.fw_perform_action(action_id, target_id="")` | Dictionary | 调 V2 `world.perform_action`；`target_id` 空则用当前选中批号；返回 `{ok,action,level,level_name,identity,actor_id,actor_name,reason,reason_code,detail,tutorial,...}`；成功会记录教学门控进度 |
| `state.fw_start_repair(section_id)` | Dictionary | 启动 V2 损管维修（`{ok,reason,section}`） |
| `state.fw_apply_damage(id, severity, label="")` | Dictionary | 剧情/调试施加损伤 |
| `state.fw_open_decision()` / `state.fw_choose_ending(kind)` / `state.fw_submit_report(truth)` | Dictionary | V2 流程封装（V15 原 decision 流程保留，两者 best-effort 镜像） |
| `state.fw_evidence_start(id)` | Dictionary | V2 取证任务 |
| `state.fw_actions_for(track_id)` | Array | 指定目标的 V2 动作可用性 |
| `state.fw_replay_start/pause/stop/seek(t)/seek_index(i)/frame()` | Dictionary | 只读回放；`seek` 不推进世界；seek 后固定查看头（录制追加帧不移动播放头）；`frame()` 返回当前/固定帧 |
| `state.fw_restart()` | void | 重置 V2 世界（V15 `restart_demo()` 内部已调用） |
| `state.fw_tutorial_ready()` / `state.fw_tutorial_allows()` / `state.fw_decision_gate_reason()` | bool/String | 教学门控查询 |
| `state.fw_bridge_state()` | Dictionary | 一帧总览（见上表字段） |
| `state._fw_pull()` | void | 手动把 bridge 快照拉进 state.fw_*（HUD 内部已用，一般不要直接调） |

## 3　V15 决策门控（教学）

- V15 `_update_phase_gate` 在决策到点时调 `_open_decision()`；`_open_decision` 先检查
  `state.fw_tutorial_allows()`。未满足时：
  - 不打开决策、不自动完成识别；`state.fw_decision_deferred=true`，
  - `state.fw_decision_reason="教学门控：识别不足（x/2）— …"`，HUD 在决策入口置灰显示；
  - 玩家通过 `state.fw_perform_action(...)`（HUD 目标动作）完成关键识别后，
    `fw_sync`/`fw_perform_action` 会自动打开挂起的 V15 决策（`decision_open=true`）。
- 自动放行（不阻塞旧演示/截图）：
  - `DSH_SKIP_TUTORIAL=1`（V2 端门控禁用，`fw_tutorial.enabled=false`）；
  - `DSH_SIM` / `DSH_SHOT` 设置时（演示/截图）；
  - `state.capture=true`（截图冻结）。
- 放行后 V15 `choose_ending / authorize_fire / submit_report` 会 best-effort 镜像到 V2
  （`fw_flow` 的 decision/report/reputation 随之更新；V2 端拒绝不影响 V15 流程）。

## 4　HUD 现读字段（task-56 已接线，供核对）

- 教学：`state.fw_tutorial`（`actions/completed/progress/ready/enabled`）、`state.fw_decision_reason`；
- 损管：`state.fw_damage`（`sections/queue/summary`）、`state.fw_start_repair(id)`；
- 回放：`state.fw_replay`（`frames/playing/paused/index/total/t`）、
  `state.fw_replay_start/pause/seek(t)`；
- 兜底：`state.framework`（bridge 的 `tutorial/damage/replay` 快照、`world`）。

## 5　plot 可读字段（task-55 参考）

- 接触/站体：`state.fw_contacts` 行含 `track_id/entity_id/batch/level/identity/kind/display_kind/
  icon/size_km/fixed/entity_tags/orbit_source/range_km/bearing_deg/stale`；
  `fixed=true`（站体 0100 / 储罐 0101）不应画推进/预测，只画固定标记。
- 动作/目标：`state.fw_actions_for(track_id)`、`state.fw_actions`（右键菜单灰显原因）。
- 时间/阶段：`state.fw_flow`（phase、exec_left、decision/report/end）。
- 雷达/TWS 球体仍由 V15 state racks/sensor + `scripts/tws_bridge.gd`（V17-SENSOR）负责；
  bridge 不改 V15 tracks，plot 不需要直接读 `framework.world`。

## 6　测试

```powershell
# 启动（intro 场景，默认 headless 只打印 AUDIO）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --quit

# 主场景 8 帧（跳过 intro）：打印 V17 FRAMEWORK / V17 BRIDGE
$env:DSH_SKIP_INTRO='1'
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --quit-after 8

# 桥接 probe（全绿：PASS=131 FAIL=0；DSH_SKIP_TUTORIAL=1 时 PASS=107）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --script res://tests/v17_bridge_probe.gd
```

覆盖：boot / 10 接触（含站体储罐 fixed）/ tutorial 字段与门控 / `fw_perform_action` 跨 2 动作后
ready / flow（exec_window 360、decision/report/end、五方声望）/ damage（3 项维修）/ replay（帧增长、
seek/pause/stop、只读）/ state.fw_* 归一字段 / V15 决策挂起→自动打开 / HOLD+TRUTH 镜像到 V2。

## 7　已知边界

- V2 flow 的 decision 计时（timeline T+75 / exec 360s）与 V15 的 `decision_t` 各自独立；
  HUD 覆盖层以 V15 `state.decision_open` 为准，`fw_flow` 仅作数据展示（镜像是 best-effort）。
- bridge 只读 `framework/*`；sim/tactical_snapshot、plot/TWS 由 V17-SENSOR 维护，core 不反向依赖。
- 回放为数据帧接口；HUD 回放期间应暂停仿真（`state.paused`/`sim_frozen` 或 UI 自行冻结）。
- 未 commit；与 V17 其他任务（hud/plot）按字段契约协作。
## 9　传感器权威边界（V17-CORE-3）

- `state.sensor_authority == "legacy_v15"`：V15 `sensor_model` 决定接触等级/融合/威胁；
  V2 radar/TWS/optical 仅是数据/演示模型（advisory）。
- `state.v2_sensor_advisory()`：只读摘要（authority/role="advisory_data_demo"/switching=false/
  v2_ready/v2_sources/v15{selected_level,selected_identity,sensor,fusion_count}/v2_contact_count）；
  未接 bridge 时 v2_ready=false；接 `state.framework` 后提供 V2 接触数，但 authority 不变。
- 不切换权威、不伪造；plot 的 TWS/球形雷达演示只能作为 advisory 叠加，不得回写
  `state.tracks/level`。详见 `game_v17/docs/v17_radio_sensor.md`。
## 10　损管字段映射（R2-DAMAGE-2 world 接入）

`state.fw_damage` 仍来自 `bridge.damage_view()` → `world.vm_damage()`；**旧字段完全兼容**，
HUD 现有损管卡无需改动：

| 字段 | 说明 |
| --- | --- |
| `sections` | legacy 3 项（sensor_cal / ir_false_alarm / thermal），含 `state/severity_pct/repair_remaining_s/progress/can_repair` |
| `queue` | legacy 维修队列（section id 数组） |
| `summary` | legacy `{total,damaged,degraded,repairing,repaired,needs_attention}` |
| `repair_rate_s` / `entity_id` / `entity_name` | 同上 |
| `damage_sections` / `damage_queue` | 旧字段别名（内容相同） |

新增完整损管模型只读字段（同一 `vm_damage()` 返回，HUD 新损管页可用）：

| 字段 | 说明 |
| --- | --- |
| `has_full_model` | 本实体是否初始化完整模型（harmattan/summons 为 true；其他舰 false） |
| `model` | 完整 `V2DamageModel.vm_damage()`：sections=7（hull/power/propulsion/sensors/comms/tanks/docking，含 integrity/state/fire/decompression/powered/repair）、events（最近 64 条）、queue、resources、summary、effects、units |
| `events` / `resources` / `effects` / `summary_full` / `units` | 从 `model` 提升的快捷只读字段 |
| `note` | 兼容说明 |

写操作（只读 bridge 不调用；剧情/调试/后续武器系统用 `world` API）：
`world.damage_apply_hit(...)` / `damage_assign_repair(...)` / `damage_cancel_repair(...)` /
`damage_set_priority(...)`；转发到 `entity.damage`，不自动命中、不生成武器。
`world.advance(dt)` 会推进完整模型并返回 `damage_events`；事件同时进 `world.events` 与
`world.damage_events_log`。旧 `apply_damage/start_repair/advance_damage` 行为不变，且不驱动完整模型。
详见 `game_v17/docs/damage_model.md §9`。
### 10.1　R4-CORE-2 追加：完整损管暴露

- bridge：`bridge.damage_full` / `bridge.damage_full_view()`（= `world.vm_damage_full()`，7 分区完整 vm）、
  `bridge.damage_model_ready`；旧 `bridge.damage`（legacy 3 项）不变。
- state：`state.fw_damage_model`（bool，完整模型就绪）、`state.fw_damage_full`（Dictionary，完整 vm）；
  旧 `state.fw_damage` 保持 legacy 3 项不变。`fw_bridge_state()` 含 `damage_full/damage_model`。
- state 写 API（只转发、不自动命中）：`fw_damage_apply_hit(section, energy, pen=0.5, dir="fore",
  source="state", entity_id="")`、`fw_damage_assign_repair(section, priority=2)`、
  `fw_damage_cancel_repair(section)`、`fw_damage_set_priority(section, priority)`；
  对应 bridge：`damage_apply_hit/damage_assign_repair/damage_cancel_repair/damage_set_priority`。

## 11　导航/交通管制/机动规划字段（R4-CORE-2）

模型：`framework/core/navigation_model.gd`（`V2NavigationModel`）+ `framework/content/navigation_l1.json`。
bridge boot 时创建并加载内容；`bridge.sync(dt)` 中 `nav.step(dt)`（dt=0 暂停时不推进）。
**规划抽象模型**：不做真实轨道积分；节点/边成本/交通规则来自内容（8 节点 / 15 边）。

### 11.1 state / bridge 只读

| 位置 | 字段 | 说明 |
| --- | --- | --- |
| state | `fw_nav_ready` | 导航模型是否就绪（bool） |
| state | `fw_nav` | `vm_navigation()`：schema/id/ready/t/nodes[8]/routes/selected/clearance/clearances/queue/planned_maneuvers/budget/limits/events/summary |
| state | `fw_nav_summary` | `summary()`：nodes/edges/routes/selected/requests/queue/pending/hold/granted/denied/maneuvers/maneuver_states/budget |
| bridge | `nav_ready` / `nav_snapshot` / `nav_summary` | 同上（bridge 内部 `nav` 为模型实例，`navigation_view()` 返回快照） |
| bridge | `navigation_view()` / `navigation_summary()` | 只读 vm/summary |
| 两者 | `budget` 键 | `dv_total_ms/dv_reserve_ms/dv_used_ms/dv_committed_ms/dv_available_ms/used_ratio/warning/exhausted` |

### 11.2 写 API（只转发；不自动执行/不自动授权）

| state | bridge | 说明 |
| --- | --- | --- |
| `fw_nav_plan_routes(from,to,constraints={})` | `nav_plan_routes` | 返回 3 类候选（fast/economy/covert），含 dv/duration/exposure/feasible/recommended |
| `fw_nav_select_route(route_arg)` | `nav_select_route` | 选中候选（candidate_id/dict） |
| `fw_nav_request_clearance(route,window,priority=3)` | `nav_request_clearance` | 交通许可；返回 granted/hold/denied + reason |
| `fw_nav_grant/deny/hold(request_id[,reason/until_t])` | `nav_grant/nav_deny/nav_hold`（全名 `*_clearance`） | 管制员放行/拒绝/保持；不执行机动 |
| `fw_nav_plan_maneuver(kind,target="",opts={})` | `nav_plan_maneuver` | hold/approach/retreat/evade/point/burn；买 Δv 由预算检查 |
| `fw_nav_authorize(plan_id)` | `nav_authorize`（全名 `nav_authorize_maneuver`） | PRE_ORDER→AUTHORIZED（预留 Δv） |
| `fw_nav_queue_maneuver(plan_id,clearance_id="")` | `nav_queue_maneuver` | AUTHORIZED→QUEUED（需许可的机动校验许可） |
| `fw_nav_execute(plan_id)` | `nav_execute`（全名 `nav_execute_maneuver`） | QUEUED→EXECUTING；之后 `bridge.sync(dt)` 推进进度 |
| `fw_nav_abort(plan_id[,reason])` | `nav_abort`（全名 `nav_abort_maneuver`） | 中断；EXECUTING 按进度消耗部分 Δv |

**不自动执行**：规划/许可/授权都不会自动进入 EXECUTING；只有显式 `execute` 后由 `step(dt)` 推进，
`AUTHORIZED` 计划即使 sync 也不会自动执行（probe 断言）。

## 12　R4-CORE-2 测试

`tests/v17_nav_integration_probe.gd` → `PASS=182 FAIL=0`（headless exit 0）覆盖：
bridge boot/nav vm 字段/预算；路线候选/选择/规划不消耗 Δv；许可 hold→grant、economy 自动批准、
deny/hold、优先级与时间窗拒绝原因；机动 plan→authorize→queue→execute→step→DONE，无许可 approach
拒绝、执行中 abort 部分 Δv；授权后同步不自动执行；bridge/state 完整损管 full（7 分区）+ 旧 legacy
（3 项）兼容、写 API 转发、无档案实体拒绝；state fw_nav_* 全链路、fw_damage_* 包装、restart 复位、
fw_bridge_state JSON 可回读。回归：`v17_bridge_probe` 138/0（旧字段不变）、`damage_integration_probe`
204/0、`nav_probe` 372/0、boot/main headless exit 0。
## 13　物理 shadow 字段（R6-SHADOW-1）

物理核心 `framework/sim/cislunar_physics.gd`（CR3BP/RK4）以 **shadow 只读**方式接入：
`authoritative=false`，不修改 V15 轨道/sensor_model/plot/HUD，也不修改 V2 world 实体轨道。

| 位置 | 字段 / API | 说明 |
| --- | --- | --- |
| bridge | `physics_mode` / `physics_ready` | `"shadow"`（默认）/`"off"`；`V17_PHYSICS=off` 关闭 |
| bridge | `physics_view()` / `physics_summary()` | 只读 vm（entities/reference/warnings/t/config）与摘要（t/entities/warnings/max_jacobi_drift/nav_position_provider） |
| bridge | `bridge_state()` | 增 `physics/physics_summary/physics_ready/physics_mode` |
| state | `fw_physics` / `fw_physics_ready` / `fw_physics_summary` / `fw_physics_mode` | 只读快照（浅 JSON 深拷贝） |
| navigation | `nav.bind_position_provider(_nav_shadow_position)` | 节点位置替换为 shadow/地月模型的地心旋转系位置；off 时回退 abstract；不影响路线成本/执行 |

`physics_view()` 实体行：`id/t/state_rot/state_earth_eci/state_earth_rot/jacobi/jacobi0/
jacobi_drift/energy/finite/earth_distance_km/moon_distance_km/source`（9 个 V2 实体；
source 标注 L1 局部近似/固定占位/缺失默认，非 JPL 星历）。
`reference`：`lagrange{L1..L5}`、`geo`、`lunar_leo`、`moon`（含 earth_rot 位置/ECI 状态/距离/周期）。
导航节点位置（provider）：L1≈326,381 km、L2≈448,915、L4/L5≈384,400、GEO=42,164、
moon_port 到月≈1,737.4、lunar_leo 绕月≈1,837.4 km；off 时 l1 回退 abstract 326,283 km。

`bridge.sync(dt)` 内固定步长（≤60s）推进 shadow；`sync(0)` 暂停不推进；不自动执行导航机动。
详见 `game_v17/docs/v17_physics_shadow.md`；测试 `tests/v17_physics_shadow_probe.gd`（277/0）。
## 14　authoritative 物理适配层（R6-AUTH-1）

`V17_PHYSICS=shadow|authoritative|off`（默认 shadow）。authoritative 仍**不写 V15 tracks/HUD**；
`display_switched=false`，为下一步切换准备。

| 位置 | 字段 / API | 说明 |
| --- | --- | --- |
| bridge | `physics_requested_mode` / `physics_mode` / `physics_fallback_reason` | 请求/有效模式/回落原因（authoritative 初始化失败 → mode=shadow） |
| bridge | `physics_authoritative_view()` | own/flagship/targets 的 `state_earth_eci`/`state_earth_rot` + 相对 own 的 `board_r/board_v`、`range_km/bearing_deg/elevation_deg/range_rate/closing`、`age_s`、`source`、`warnings`、`flags{authoritative_ready,display_switched,own_id,flagship_id,target_ids,fixed_ids}`；另含 `fixed`/`stations`（固定站体，见下） |
| bridge | `physics_adapter_compare(v15_own, v15_tracks)` | 物理 vs V15 board 只读对比：rows{physics,v15,errors{range_km,bearing_deg,position_km}} + summary{compared,max_*_err,within_threshold} + thresholds{5km,5°,50km} + frame_mismatch_note |
| bridge | `physics_summary()` / `bridge_state()` | 增 requested_mode/authoritative/fallback_reason/display_switched；bridge_state 增 physics_authoritative/physics_adapter |
| state | `fw_physics_authoritative` | authoritative 视图深拷贝（`fw_physics_authoritative_view()`） |
| state | `fw_physics_adapter` | 每帧 `fw_sync` 用 V15 `own_at/board_pos/board_vel` 自动对比（只读） |
| state | `fw_bridge_state()` | 增 physics_authoritative/physics_adapter |

- 固定站体（R6-FIXED-CORE-1）：`fixed`/`stations` 数组含 `chronos_station`、`tank_farm`（role=fixed，
  `entity_kind`/`name`/`fixed` 字段，board 相对 own）；V15 fixed 标识 `0100`/`0101` 经 bridge contacts
  映射；state 显示帧 `fixed`/`fixed_ids` 与 `physics_display_fixed_for(id)` 读取。
- 坐标系：相对板 `board_r = earth_rot(target) − earth_rot(own)`；bearing=atan2(x,y)，
  elevation=atan2(z,horiz)（与 V15 `_derive` 同式）；`frame.inertial=earth_eci`、
  `frame.rotating=earth_rot`。
- 导航：shadow/authoritative 且物理 ready 时 provider=物理位置（L1≈326,381 等）；off 回退 abstract；
  成本仍抽象、不自动执行。
- 边界：V15 board（L1 局部差）与 physics board（earth_rot 差）坐标系未统一，compare 的
  bearing/位置误差含旋转差异，range 可直接比；thresholds 仅供切换评估。详见
  `game_v17/docs/v17_physics_authoritative.md`；测试 `tests/v17_physics_authoritative_probe.gd`（154/0）。
## 15　传感器 shadow 字段（R5-SENSOR-BRIDGE-1）

模型 `framework/sim/sensor_authority.gd`（`V2SensorAuthority`）以 **shadow advisory only** 接入：
不写 TrackTable/V15、不接 HUD/plot；`V17_SENSOR_AUTHORITY=shadow|off`（默认 shadow），
`authoritative` 请求不实现（仍 shadow + `sensor_shadow_fallback_reason` 明示）。

| 位置 | 字段 / API | 说明 |
| --- | --- | --- |
| bridge | `sensor_shadow_mode` / `sensor_authority_requested_mode` / `sensor_shadow_ready` / `sensor_shadow_fallback_reason` | 有效/请求/就绪/回落说明 |
| bridge | `sensor_shadow_view()` | `vm_sensor()`：schema/mode/authoritative=false/ready/t/observer/mounts/radar(sphere/exposure)/channels/advisory_contacts/advisory_observations/optical_summary/warnings/writes{track_table:false,v15:false}/counts |
| bridge | `sensor_shadow_summary()` | mode/ready/t/observer/mounts/contacts/observations/channels/warnings/radar_active + writes=false |
| bridge | `sensor_compare(legacy_tracks)` | 只读 compare：advisory/legacy/matched/only_*/diffs[{level_delta,identity_diff,range/bearing delta}]+summary{level_equal,advisory_higher/lower,only_*,avg deltas,level_gate_pass,within_tolerance}+tolerances+READ-ONLY warnings |
| bridge | `bridge_state()` | 增 `sensor_shadow/sensor_shadow_summary/sensor_shadow_ready/sensor_shadow_mode/sensor_authority_requested_mode/sensor_shadow_fallback_reason/sensor_compare` |
| state | `fw_sensor_shadow` / `fw_sensor_shadow_ready` / `fw_sensor_compare` | 只读快照；`fw_sync` 刷新；compare 用 state.tracks（只读）；off/未就绪为空；旧字段不变 |
| state | `fw_sensor_shadow_view()` / `fw_sensor_compare_view()` | getter |

snapshot 由 bridge 构造：observer=harmattan（L1 板原点，damage.sensors 取完整损管 effects.mult）；
targets 取 `world.vm_contacts()` 中非 bearing-only、range>0、有 entity_id 的行（make_target range/bearing）。
boot 做一次 `step(0.0)` priming（不推进时间）使 advisory 立即可读；运行时 `dt=0` 不推进。
详见 `game_v17/docs/v17_sensor_shadow.md`；最小 probe `tests/v17_sensor_shadow_probe.gd`（105/0）。
## 16　信息作战 shadow 字段（R5-INFO-BRIDGE-1）

模型 `framework/sim/information_warfare.gd`（`V2InformationWarfare`）以 **shadow advisory only**
接入：IFF/ELINT/COMINT/EW 只读 advisory/events/alerts；不写 TrackTable/V15；不接 HUD/plot。
`V17_INFO_WARFARE=shadow|off`（默认 shadow）；`authoritative` 请求不实现（仍 shadow + reason）。

| 位置 | 字段 / API | 说明 |
| --- | --- | --- |
| bridge | `info_warfare_mode` / `info_warfare_requested_mode` / `info_warfare_ready` / `info_warfare_fallback_reason` | 有效/请求/就绪/回落说明 |
| bridge | `info_warfare_view()` | `vm_information_warfare()`：schema/mode/authoritative=false/ready/t/observer/mounts、iff{results,summary,hostile_allowed:false}、elint{state,signals,misses,fix_candidates,summary}、comint{events,summary}、ew{effects,active_count,radar,comms,optical,emcon,phantom,suspicious_commands}、effects/events/alerts/advisory_contacts、summary、writes{track_table:false,v15:false}、shadow{never_auto_hostile:true} |
| bridge | `info_warfare_summary()` | iff/iff_identity_*/signals/fix_candidates/comint/effects/events/alerts/phantom_active/suspicious_commands/hostile_auto_determination=false |
| bridge | `info_warfare_events()` / `info_warfare_alerts()` | 最近 ≤8 条事件/告警缓存（完整见 view） |
| bridge | `bridge_state()` | 增 info_warfare/info_warfare_summary/ready/mode/requested/fallback/recent_events/recent_alerts |
| state | `fw_info_warfare` / `fw_info_warfare_ready` / `fw_info_warfare_summary` | 只读快照；`fw_sync` 刷新；off/未就绪为空；旧字段不变 |
| state | `fw_bridge_state()` | 增 info_warfare/info_warfare_ready/info_warfare_summary |

输入：observer=harmattan（L1 板原点，damage.sensors/comms 取完整损管 effects.mult）；targets 取
`world.vm_contacts()` 非 bearing-only/range>0/has entity 行（友军 transponder=ok+默认 IFF 码，
其余 off；每条带占位雷达 emission + radio comms）；stations=两个 ELINT 站（5000 km 基线）；
advisory_contacts 透传 sensor shadow。`sync(dt)` 中 `dt>0` 才 step；`dt=0` 不推进。
详见 `game_v17/docs/v17_info_warfare_shadow.md`；最小 probe `tests/v17_info_warfare_probe.gd`（116/0）。