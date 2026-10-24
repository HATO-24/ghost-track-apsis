# 完整游戏-阶段2I · 传感器服务管道（Observation / Evidence）

> 任务 task-130。工程 `game_v17`。**只新增 3 个文件**：
> `scripts/core/sensor_service.gd`、`tests/sensor_service_probe.gd`、
> `docs/sensor_service.md`。
> 未改旧 HUD/state/bridge/core/sim/project；不接物理/UI；不写 world/TrackTable/V15；未 commit。

## 1　定位与数据流

```
observer / mounts / targets snapshot / environment
        │
        ▼
V2SensorService
  ├─ V2SensorAuthority（YW-R9 球形雷达/TWS、MS-OT2 VIS、CH-IR2 IR）
  └─ V2InformationWarfare（MK-12 IFF）
        │
        ▼
Observation 事件 sensor_observation.v1
Evidence    事件 track_evidence.v1
        │
        ▼
上层 fusion / TrackTable（本服务**不写**；单站/数据链 L1/L2 由上层决定）
```

- 服务只产生**观测/证据事件**；不判等级、不建航迹、不写 TrackTable/world/V15/UI。
- 雷达/TWS 观测来自 authority 的 advisory observations；VIS 锁定并分类时产生
  `optical` evidence（support=3，无位置/接触）；IR 锁定时通过观测/通道体现（不分类）。
- IFF 通过 `query_iff` 显式询问，产生 `iff` evidence（support=4），**不产生位置/接触**，
  identity 只 friend/unknown，`hostile=false/never_hostile=true`。
- EMCON/雷达关闭时过滤主动雷达观测；被动光学/IR 仍可。

## 2　API

```gdscript
const SensorService := preload("res://scripts/core/sensor_service.gd")
var s = SensorService.new({
  "observer": {"id": "harmattan", "pos_km": [0,0,0], "vel_kmps": [0,0,0],
    "attitude_quat": [0,0,0,1]},
  "mounts": [],           # 空=authority 默认 YW-R9/MS-OT2/CH-IR2
  "targets": [
    {"id":"T1","entity_id":"E1","batch":"2001","pos_km":[0,500,0],
     "vel_kmps":[0,0,0],"rcs_m2":10,"temp_k":300,"area_m2":1000,"size_m":50,
     "illum":1,"transponder":"ok","iff_code":"CMP-2001","registered":true,
     "crypto_epoch":"epoch-1","side":"friend",
     "classification":{"ship_class":"DDG"}}
  ],
  "snapshot": {"sun_dir": [0,0,1], "sun_illum":1.0, "jamming":0.0,
    "shadow":false, "los":true},
  "options": {"radar_enabled": true, "emcon": false,
    "optical_backend": "optical_ir", "iff_enabled": true}
})
s.step(dt, snapshot := {}) -> VM          # authority + IFF 推进，返回 vm()
s.set_target(id) -> {ok,reason}           # 选中目标（IFF/上层引用）
s.start_channel("optical"|"ir", target, opts := {}) -> authority result
s.stop_channel(kind := "", target := "") -> {ok,reason,stopped}
s.set_radar_enabled(on) -> {ok,radar_enabled,emcon,writes}
s.set_emcon(on) -> {ok,radar_enabled,emcon}
s.query_iff(target_id := "") -> {ok,status,identity,evidence,never_hostile}
s.iff(target_id := "") -> 同上（别名）
s.vm() / s.summary() / s.to_dict() / s.to_json()
s.events / s.events_since(i) / s.take_events()
```

`step(dt, snapshot)` 可传 world/entity snapshot（observer/targets/env）；不传则用 setup 的
observer/targets/snapshot。所有方法为只读或服务内部状态；不调用 TrackTable。

## 2A　几何绑定（A0-T2 / Issue #4.1）

传感器几何 = **observer/targets 的位置与速度**；静态元数据 = `rcs_m2`/`side`/`iff_code`/
`classification`/`batch` 等。两者来源不同，不可混用：

| 类别 | 来源 | 说明 |
|---|---|---|
| 几何（pos/vel） | **PhysicsWorld**（绑定后） | 与统一物理世界同一仿真时刻；frame=`bary_rot`，km / km/s |
| 静态元数据 | 原权威（EntityCatalog / 配置） | 几何刷新**不覆盖**这些字段 |

```gdscript
# GameSession 在 boot 末尾自动绑定（physics 已启用且 seed 未做 L1→bary_rot 转换时）
var bind := session.sensor_service.bind_geometry_provider(provider)  # {ok,source,frame,t,bound,...}
session.sensor_geometry_status()  # 只读诊断（见下）

# provider 契约（只读，不写任何状态）：
#   geometry_ready() -> bool
#   geometry_frame() -> String（必须 == "bary_rot"）
#   geometry_t() -> float（同一仿真时刻，秒）
#   geometry_state(entity_id) -> {ok,frame,t,r:[x,y,z] km,v:[x,y,z] km/s}
```

- **采样时刻**：`step()` 在推进后按当前 `t` 刷新几何；`geometry_t == physics t == session t`。
  若 `|provider_t - t| > 1e-6 s` → `ok=false, reason="time_mismatch"`，**不使用旧几何**。
- **几何不可用时抑制观测**：`step()` 用 `_geometry_usable()` 判定；时间不一致 / observer
  缺失 / 目标缺失 / 帧不匹配时**不生成** observation/evidence（只记一次
  `geometry_unavailable` 事件并累加 `suppressed_steps`）。绝不把上一次坐标当成当前观测。
- **降级（显式，不静默）**：
  - 无 PhysicsWorld → `source="static"`、`authoritative=false`、`reason="no_physics_world"`
    （静态配置位置，非物理真值）；
  - 坐标系不匹配（4F 帧转换会话）→ `source="static"`、`reason="frame_mismatch"`
    （由 `mark_geometry_unavailable("frame_mismatch")` 显式标记）；绝不把 bary_rot
    数值写进 L1 相对语义的静态 target；
  - 单个 target 缺失 → 该行 `geometry_source="unavailable"`、`pos_km/vel_kmps` 清空，
    **不沿用旧静态坐标**参与观测；整体 `authoritative=false`。
- **诊断** `sensor_service.geometry_status()`：
  `{source, authoritative, complete, available, reason, frame, units, t, geometry_t,
  observer_id, observer_pos_km, observer_bound, targets, bound, missing, skipped,
  mismatched_frame, suppressed_steps, last, seq, writes}`；
  `last` 含 `{ok,source,frame,t,provider_t,time_ok,bound,missing,skipped,mismatched_frame,
  observer_bound,usable,reason,seq}`。
  `authoritative` **仅当** `source=physics_world` 且 `complete`（时间一致 + observer 绑定 +
  targets 全部绑定 + 无帧不匹配）时为 true；部分成功不会误报。
- **边界**：几何绑定只改内存中的 observer/targets 几何字段与 authority 快照，
  **不写 world/TrackTable/V15/UI**；`range_km`/`bearing_deg` 仍是**观测值**（含传感器噪声），
  不得替换为物理真值；HUD/CombatService 不读传感器内部真值。


## 3　事件 schema

### 3.1 Observation `sensor_observation.v1`

```json
{"schema":"sensor_observation.v1","kind":"observation",
 "event_id":"OBS-000001","t":30.0,"observer_id":"harmattan",
 "target_id":"T1","sensor":"radar|radar.tws|optical|ir",
 "sensor_model":"YW-R9|MS-OT2|CH-IR2",
 "support":2,"quality":1.0,"range_km":500.0,"bearing_deg":90.0,
 "position_km":[],"reason":"",
 "level_decided":false,"produces_contact":false,"writes_v15":false}
```

- 只给传感器观测；`support` 为原始传感器支持（不写等级）；
- `level_decided=false`、`produces_contact=false`；上层 fusion 决定 L1/L2。

### 3.2 Evidence `track_evidence.v1`（optical / IFF）

```json
{"schema":"track_evidence.v1","kind":"evidence","event_id":"EVD-000001",
 "evidence_id":"EVD-000001","t":30.0,"observer_id":"harmattan",
 "target_id":"T1","evidence_type":"optical|iff","support":3,
 "identity":"unknown|friend","classification":{...}?,
 "iff_status":"...", "raw_status":"...", "friend":false,
 "hostile":false,"never_hostile":true,
 "produces_contact":false,"produces_position":false,
 "level_decided":false,"writes_v15":false}
```

- optical：VIS locked + classification 非空才产生，support=3；每个目标一次；
- IFF：显式 `query_iff` 才产生，support=4；IFF 只给身份证据，**无 position/pos_km**；
  `no_reply/faulty/out_of_range/crypto_mismatch` → identity unknown；
  `friend` → identity friend；`hostile` 恒 false、`never_hostile=true`。

### 3.3 Service event `sensor_service_event.v1`

`set_radar_enabled/set_emcon/target/channel/iff` 等控制动作：
`{schema,kind,seq,t,observer_id,detail,shadow,writes_v15:false}`；与
observation/evidence 一起进 `events`；`take_events` 返回未取事件。

## 4　传感器覆盖 / 开关

| 能力 | 来源 | 输出 |
| --- | --- | --- |
| 雷达/TWS | authority YW-R9 sphere/TWS | observation（sensor=radar/radar.tws，support 原样，含 distance/bearing/quality） |
| VIS | authority optical_ir（MS-OT2） | observation；locked+classification→optical evidence L3 |
| IR | authority optical_ir（CH-IR2） | observation；锁定→L1 观测（不分类） |
| IFF | V2InformationWarfare MK-12 | evidence L4（身份）；无位置/接触 |
| EMCON | authority observer emcon + mount | 关闭主动雷达观测；IFF 返回 blocked |
| channels | start/stop optical/ir | authority 通道状态/FOV/SNR/reason；不写 V15 |

失败 reason 透传 authority：`fov_miss/out_of_range/occluded/too_dark/blurred/low_snr`
等；观察/证据事件本身不伪造成功。

## 5　只读 VM

```text
schema=sensor_service.v1, mode=shadow, ready, t, dt, step_count,
observer, mounts, selected_target, targets,
radar_enabled, emcon, optical_backend,
observations[], evidence[], channels[],
events[]（observation/evidence/control 事件）,
counts{observations,evidence,events,channels,radar_obs,tws_obs,optical_evidence,iff_evidence},
warnings, errors,
writes={track_table:false,v15:false,world:false}
```

- JSON-safe、确定性；`take_events` 可取未消费事件；
- `summary()` 给轻量计数；`to_json()` 完整 VM。
- 无写 TrackTable API；上层需自行把 observations/evidence 交给 fusion/TrackTable。

## 6　接入 GameSession + TrackTable

```gdscript
var sensors = SensorService.new(config)
var vm = sensors.step(dt, world_snapshot)
for obs in vm.observations:
    track_table.handle_observation(obs, "fusion")      # 由 fusion authority 写
for ev in vm.evidence.filter(func(x): return x.get("evidence_type") == "iff"):
    track_table.handle_evidence(ev, "fusion")
```

- 本服务不引用 TrackTable/GameSession，保持单向依赖；
- GameSession 负责时间/seed/存档；本服务只读 snapshot、输出事件；
- EMCON/开关/目标/通道由 GameSession/UI 调服务 API，不由 UI 直接改 TrackTable。

## 7　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/sensor_service_probe.gd
# SENSOR SERVICE PROBE RESULT: PASS=128 FAIL=0
# SENSOR SERVICE PROBE OK（退出码 0）
```

覆盖（128 checks）：
- setup/ready/mounts/observer/VM schema/writes=false/JSON；
- 雷达观测事件 schema/事件 id/support/quality/range/bearing/sensor_model/不判等级/
  不产生 contact/不写；
- VIS/IR：通道 locked、FOV/IFOV/SNR/off-axis/occluded/detected、IR L1；
  光学 classification → optical evidence support3、无 contact/位置、JSON；
- 目标/通道 start/stop、未知目标/非法 kind/无匹配 stop；
- 雷达开关/EMCON：off 无新雷达观测、IFF blocked、恢复；set_emcon；
- IFF：T1 friend、T3 faulty、T2 out_of_range、未知/未选目标；evidence schema/
  support4/无位置/无 contact/hostile=false；
- 无目标/超距/遮挡：远目标 lost reason、observer 地球背面 occluded=true；
- outbox/events/JSON/summary、完整流程确定性、不写 TrackTable/V15/world。

## 8　边界 / 未完成

- 不接物理/UI/HUD/bridge/state；不写 world/TrackTable/V15；只读输入 snapshot。
- 服务不判 L1–L4、不建航迹；上层 fusion/TrackTable 才写等级/身份。
- 不实现 ELINT/COMINT/EW 管道；IFF 只做身份证据，不自动判敌/不产生位置。
- 雷达/TWS 观测复用 authority 的现有输出；不做额外融合/去重（上层负责）；
  optical evidence 每目标每目标通道只发一次（去重仅本地）。
- `set_radar_enabled(false)` 即本层 EMCON，不写权威 EMCON；恢复后需 step 重新扫描。
- 未做多观察者/数据链聚合、传感器损坏恢复、真实姿态/遮挡几何；mounts 缺能力会
  由 authority setup 报错（不静默补假能力）。
- 未跑全量回归；只单次跑本 probe。
