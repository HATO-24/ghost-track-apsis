# 完整游戏-阶段3Z · 全港 OTC / 燃料设施 / 交通管制

> 任务 task-182。工程 `game_v17`。修改/新增：
> `framework/content/facilities_system.json`（扩展 OTC/储罐/加注，保留旧 29设施/57端口）、
> `framework/content/lanes_system.json`（新增）、
> `scripts/core/traffic_control_service.gd`（新增）、
> `tests/traffic_control_probe.gd`（新增）、`docs/traffic_control.md`（新增）。
> 不改其他；不写 world/TrackTable/UI；未 commit。

## 1　设施数据扩展（`facilities_system.json`）

### 1.1 兼容策略

原 `facilities` / `clusters` **原样保留**（29 设施 / 57 端口 / 7 港群），
确保旧 `FacilityRegistry` 的既有契约与 probe 仍通过。新增内容放顶层扩展数组：

```text
orbital_nodes      LEO / FAR 两个轨道节点（2）
otc_satellites     OTC 交通管制卫星（19）
fuel_facilities    储罐 TNK + 加注 FUL（62）
```

`TrafficControlService` 将 `facilities + otc_satellites + fuel_facilities` 合并为
110 个交通设施、138 个端口（旧 29/57 全部保留）；`clusters + orbital_nodes`
合并为 9 个港群/节点。旧 `FacilityRegistry` 忽略新增顶层键，仍只读旧 29/57。

### 1.2 OTC 数量（docs/20 §7.1）

| 港群/节点 | OTC 数量 | 本例 facility_id |
| --- | --- | --- |
| L1_MERIDIAN | 2 | OTC-L1_MERIDIAN-01/02 |
| L2_KARMAN | 2 | OTC-L2_KARMAN-01/02 |
| L3_ALBORADA | 1 | OTC-L3_ALBORADA-01 |
| L4_ANVIL | 2 | OTC-L4_ANVIL-01/02 |
| L5_NEW_LAGOS | 2 | OTC-L5_NEW_LAGOS-01/02 |
| NESOSS | 3 | OTC-NESOSS-01/02/03 |
| LEO | 3 | OTC-LEO-01/02/03 |
| FAR | 2 | OTC-FAR-01/02 |
| LUNSYNC | 2 | OTC-LUNSYNC-01/02 |

### 1.3 新增设施字段

- OTC：`facility_class=otc`、`transponder_type=otc`、`services=[traffic_control,radar,surveillance]`；
- 储罐：`TNK-<facility_or_node>`、`facility_class=tank`、`transponder_type=tank`、
  `services=[storage,fuel]`；
- 加注：`FUL-<facility_id>`、`facility_class=fuel`、`transponder_type=fuel`、
  `services=[refuel,fuel,tankfarm,repair]`；
- 均带唯一 `facility_id/facility_code/transponder_code/port_id`；
  物理参数 `physical{orbit, mass_kg, radius_km, cross_section_m2, station_keeping, period_s}`
  为等效值；
- 每个旧设施追加一组 TNK/FUL；LEO/FAR 节点各追加一组；旧设施本体/端口不变。

## 2　航道数据（`lanes_system.json`）

```json
{
  "schema": "v17.lanes_system.v1", "version": "1.0.0",
  "lanes": [{
    "lane_id": "LANE-L1-IN-01", "name": "Meridian 进港主航道",
    "cluster_id": "L1_MERIDIAN",
    "from": {"type":"facility","id":"L1-01"},
    "to": {"type":"facility","id":"L1-03"},
    "direction": "inbound",
    "capacity": 2, "transit_s": 520.0, "priority": 1,
    "windows": [{"open_t":0.0,"close_t":3600.0}],
    "monitor_otc": ["OTC-L1_MERIDIAN-01","OTC-L1_MERIDIAN-02"],
    "hazards": ["tank_farm_L1-05"], "status": "open"
  }],
  "npc_ships": [...],
  "npc_occupancy": [{"lane_id":"LANE-L1-IN-01","npc_id":"NPC-TRADER-01",
    "t_start":0,"t_end":600,"width":1,"priority":3}],
  "record_fields": [...], "clue_types": [...]
}
```

- 当前 18 条航道、6 NPC、6 个 NPC 占用示例；
- lane 字段：端点、容量、窗口（可多窗口）、方向、优先级、OTC 监视节点、
  hazards/status/transit_s；
- 端点可指向 `facilities` 或扩展 OTC/燃料/轨道节点；服务启动时交叉校验；
- NPC 按时刻表占用航道（不是纯背景）；玩家/敌方申请或伪装。

## 3　TrafficControlService API

```gdscript
const TC := preload("res://scripts/core/traffic_control_service.gd")
var s = TC.new()   # 默认读 facilities_system.json/lanes_system.json
# 或 TC.new({"facilities_path":...,"lanes_path":...,"facilities_content":...,"lanes_content":...})

s.ready / s.errors
s.facility(id) / s.lane(id) / s.cluster(id)
s.otc_for(cluster) / s.lanes_for(cluster) / s.lane_occupancy(lane)
s.queue_for(lane) / s.window_open(lane) / s.next_window_open(lane)

s.request_clearance(track_id, lane_id, {priority,width,direction,
    facility_code,transponder_code,route,npc_id})
s.request_lane(...) / s.lane_request(...)      # 别名
s.permit(request_id, {ttl_s}) / s.approve(...) / s.approve_request(...)
s.reject(request_id, reason)
s.occupy(lane_id, occupant_id, {clearance_id,width,direction})
s.release(lane_id, occupant_id="")

s.npc_occupy(lane_id, npc_id, {duration_s,width,contract})
s.npc_release(lane_id, npc_id="")

s.record_disguise(track_id, {transponder_code,facility_code,
    claimed_class,lane_id,route}, {force_detected})
s.clues_for(track_id="") / s.clue(clue_id) / s.records_for(track_id="")
s.step(dt) / s.vm() / s.summary() / s.events / s.take_events()
s.save_state() / s.snapshot() / s.load_state(json_or_dict)
```

- 失败返回 `{ok:false,reason}`：`unknown_lane/unknown_target/empty_track/
  direction_mismatch/window_closed/lane_closed/facility_mismatch/
  transponder_anomaly/capacity_full/unknown_request/already_cleared/
  no_clearance/unknown_clearance/clearance_expired/unknown_npc` 等。
- 状态：`PENDING → QUEUED/CLEARED → OCCUPIED → RELEASED`；拒绝/过期/关闭原因可见。
- 容量：`capacity - 活动占用 - 已预留 CLEARED`；排队按 priority/requested_t；
- 窗口：`windows[]`；窗口外申请返回 `window_closed` + `next_window_s`；
- 方向：单方向航道会拒绝反向请求并生成 `direction_mismatch` clue；
- OTC/设施校验：申请可带 `facility_code/transponder_code`，未知则拒绝并产生 clue；
- step 推进时间、激活/结束 NPC 定时占用、过期 clearance、刷新队列位置、
  输出 `lane_record/otc_event/clue`；不写 world/UI/TrackTable。

### 3.1 伪装 / 识破

`record_disguise` 伪造 transponder/facility/track/route：

- 校验 transponder 是否存在、facility 是否存在、transponder_type 与 claimed_class
  是否匹配、facility 是否为 lane 端点、是否有 OTC 监视、历史伪装是否一致；
- `anomalies[]`：`transponder_anomaly/facility_mismatch/transponder_type_mismatch/
  track_route_mismatch/otc_gap/track_history_mismatch`；
- `probability = 0.15 + 0.2*异常数 + 0.05*(6-lane priority)`，确定性 roll；
- `detected=true` 或 `force_detected` → status `DETECTED`，生成
  `traffic_clue.v1`（`type=ghost_track`, `requires_investigation=true`,
  `produces_contact=false`, `writes_v15=false`）；未识破保留 `ACTIVE`；
- 输出 `lane_record/otc_event/clue`；线索可 `clues_for(track)`/`clue(id)` 查询；
- 不执行身份判定/不写 world/UI。

### 3.2 VM / events / save

```text
VM schema=traffic_control.v1, ready,t,step_count,
facilities(110)/lanes(18)/clusters(7)/orbital_nodes(2),
otc_satellites(19)/fuel_facilities(62),
requests/clearances/occupancies/active_npc/disguises/clues/records/events,
counts, warnings/errors,
writes={world:false,track_table:false,v15:false,ui:false}
```

- events schema `traffic_event.v1`；kind：`lane_record/otc_event/clue`；
- `clue` schema `traffic_clue.v1`；`lane_record.v1` 含 track_id/lane_id/
  transponder/facility/clearance/edit/delete/reason（供调查/谈判/报告）；
- `save_state()` schema `v17.traffic_control_save.v1` v1.0.0：t、requests/
  clearances/occupancies/active_npc/disguises/clues/records/events/seq；
  `load_state` 校验 schema/version/数组；旧/未来版本与坏 JSON 拒绝；
- JSON-safe、确定性；同一输入序列 VM 逐字节一致。

## 4　接入 / 边界

- 数据层：`facilities_system.json` 旧 29/57 保持给 `FacilityRegistry`；
  新 OTC/TNK/FUL 在顶层扩展数组，由 TrafficControlService 合并。
  若后续要让 FacilityRegistry 也直接识别新设施，可再迁移数组（本任务不改其代码）。
- 运行层：GameSession/UI/物理可只读 `vm()/lane_occupancy/clues`；
  申请/许可/占用/释放/伪装由本服务显式 API 驱动，不由 UI 直接改状态。
- 不写 world/TrackTable/V15/UI；不执行物理/泊位/加注/损管；不做真实射频/
  身份识别；伪装概率为可测抽象规则，线索是 GHOST TRACK 候选，不直接判敌。
- NPC 占用为时刻表示例数据；可被外部系统增删（本任务只提供示例与服务逻辑）。
- 未实现：真实 OTC 传感器视场/遮挡/轨道递推、玩家资产自动占用、record 编辑/
  删除 API、跨港群交接（handoff）、与 CommsService/StoryRuntime 的自动联动。
- probe 396 checks：数据量/唯一/轨道/燃料/OTC；18 航道 schema/端点/容量/窗口/
  方向/优先级/OTC 监视；申请/许可/占用/释放/排队/窗口；NPC 定时/手动/容量；
  伪装/异常/识破/线索；存档/JSON/确定性/不写。只单次运行，未跑全量回归。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/traffic_control_probe.gd
# TRAFFIC CONTROL PROBE RESULT: PASS=396 FAIL=0
# TRAFFIC CONTROL PROBE OK（退出码 0）

# 旧注册表回归
# V17 FACILITY REGISTRY PROBE RESULT: PASS=1694 FAIL=0
```
