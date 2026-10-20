# R5-SENSOR-BRIDGE-1 · 传感器 shadow 接入 V17 bridge/state

> 任务 R5-SENSOR-BRIDGE-1（task-83）。工程 `game_v17`。
> 模型：`framework/sim/sensor_authority.gd`（`V2SensorAuthority`，R5-SENSOR-1）。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读）。
> **本文件明确：shadow advisory only；不写 TrackTable/V15；不接 HUD。** 另见 R5-AUTHORITY-DISPLAY-1（`v17_sensor_authority_display.md`）：显式 `V17_SENSOR_AUTHORITY=authoritative` 时由 state 仅映射 V15 显示字段（bridge 仍不写 TrackTable）。
> 按任务要求只做最小 probe，未跑全量回归；未 commit。

## 1　定位与不变量

- bridge 启动创建 `V2SensorAuthority`（shadow），每帧用 **V2 world/entity snapshot** 喂
  `step(dt, snapshot)`；只读输出 advisory contacts/channels/observations，**不写 V2 TrackTable、
  不写 V15 tracks/HUD/plot**（模型自带 `writes.track_table=false / writes.v15=false`）。
- `V17_SENSOR_AUTHORITY=shadow|off`（默认 shadow）：
  - `off`：不创建模型，view/summary 为空、compare 返回不可用；
  - 传入 `authoritative`/`auth`/`v2`：模型仍只跑 shadow（advisory 只读）；bridge 记录
    `sensor_authority_mode="authoritative"`（显示层权威），传感器模型本身 `authoritative=false`；
    显示字段映射由 state 在 R5-AUTHORITY-DISPLAY-1 中显式执行（见 `v17_sensor_authority_display.md`）。
- 初始化失败不阻塞 bridge（world/nav/physics 等照常），只置 `sensor_shadow_ready=false` 并记录 warning。
- 不接 HUD/plot；不改变 V15 现有传感器权威（`state.sensor_authority` 仍是 legacy_v15）。

## 2　输入 snapshot（bridge 构造；只读）

| 字段 | 来源 |
| --- | --- |
| `observer` | `SensorAuthority.default_observer(world.own_id)`（harmattan）；`pos_km/vel_kmps=[0,0,0]`（L1 局部板原点）；`mast_deployed=true`、`emcon=false`、attitude 默认；`damage.sensors` = `world.vm_damage_full().effects.sensors.mult`（若可用），comms/propulsion=1.0 |
| `targets` | `world.vm_contacts()` 中 `bearing_only=false 且 range_km>0 且 entity_id 非空/非本舰` 的行；用 `make_target(track_id, range_km, bearing_deg, {entity_id,batch,name,faction,transponder:"off"})` 构造 |
| env | `sun_illum=1.0, jamming=0.0, shadow=false, los=true` |
| 帧 | 与 V15/V2 同帧（L1 局部板）；不做跨帧转换/姿态建模；模型自带 `ATTITUDE NOT MODELED`/`IDENTITY NOT ASSERTED` 标注 |

> 固定站体/储罐（0100/0101）与舰船一样在 contacts 中，按 range/bearing 进入 snapshot（不额外判敌）。

## 3　推进

- `bridge.sync(dt)`：`dt>0` 时 `sensor_shadow.step(dt, 新 snapshot)`；`dt=0`（暂停/冻结）**不推进**。
- boot 时做一次 **priming**：`step(0.0, snapshot)`（不推进时间 t）以生成首次雷达扫描/观测，
  保证启动后 advisory contacts/channels 立即可读；之后运行时 `dt=0` 不会推进。
- 每帧 `refresh()` 更新 `sensor_shadow_view_data` / `sensor_shadow_summary_data`。

## 4　bridge API（只读）

| API / 字段 | 说明 |
| --- | --- |
| `sensor_shadow` | V2SensorAuthority 实例（off/失败为 null） |
| `sensor_shadow_mode` | `"shadow"` / `"off"`（有效模式） |
| `sensor_authority_requested_mode` / `sensor_authority_mode` | env 请求 / 有效显示权威（shadow/authoritative/off） |
| `sensor_shadow_ready` | bool |
| `sensor_shadow_fallback_reason` | 初始化失败说明（authoritative 显示层无回落 reason） |
| `sensor_shadow_view()` | `vm_sensor()`：`schema=sensor_shadow.v1`、mode=shadow、authoritative=false、t/dt/step_count、observer/mounts、radar(sphere/exposure/…)、channels、advisory_contacts/observations、optical_summary、warnings/notes/events、writes{track_table:false,v15:false}、counts |
| `sensor_shadow_summary()` | `summary()`：mode/ready/t/observer/mounts/contacts/observations/channels/warnings/radar_active，`writes_track_table/v15=false` |
| `sensor_compare(legacy_tracks)` | 调模型 `compare()`；返回 `sensor_shadow_compare.v1`：advisory_count/legacy_count/legacy_skipped_own/matched_count/only_advisory/only_legacy/diffs[{key,batch,advisory_level,legacy_level,level_delta,identity_diff,range_delta_km,bearing_delta_deg,reason_guess...}]/summary{level_equal,advisory_higher/lower,identity_diff_unscoped,only_*,avg_range_delta_km,avg_bearing_delta_deg,level_gate_pass,within_tolerance}/tolerances/warnings（READ-ONLY）；只读缓存 `sensor_compare_last` |
| `bridge_state()` | 增 `sensor_shadow/sensor_shadow_summary/sensor_shadow_ready/sensor_shadow_mode/sensor_authority_requested_mode/sensor_shadow_fallback_reason/sensor_compare`（另含 `sensor_shadow_warnings` 在 view.warnings） |

## 5　state API（HUD 后续接；本任务不接）

| 字段 / 方法 | 说明 |
| --- | --- |
| `fw_sensor_shadow` | bridge sensor shadow view 深拷贝；`fw_sync` 每帧刷新 |
| `fw_sensor_shadow_ready` | bool |
| `fw_sensor_compare` | `fw_sync` 用 `state.tracks`（只读）生成 compare；off/未就绪为空 |
| `fw_sensor_shadow_view()` / `fw_sensor_compare_view()` | getter |
| `fw_bridge_state()` | 增 `sensor_shadow/sensor_shadow_ready/sensor_compare` |

`fw_sync` 构造 legacy 行：`{id, batch, level, identity, range_km(取 range_3d_km/range), bearing_deg(取 bearing/az_deg)}`，
只读传入 compare；**不写 state.tracks / V15 显示**。旧字段全部不变。
`restart` 复位后重新初始化 sensor shadow 并重算 compare。

## 6　验证（最小 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_sensor_shadow_probe.gd
# V17 SENSOR SHADOW PROBE RESULT: PASS=105 FAIL=0（exit 0）
```

覆盖：boot（mode=shadow/ready/advisory contacts=8/channels=6/writes=false/bridge_state 字段）；
`sync(10)` 推进 t、`sync(0)` 不推进；state 字段与 compare（ok/read_only/字段/summary/warnings，
V15 tracks 与 V2 vm_tracks 未被写）；authoritative 请求 → 模型 shadow + 显示层权威标记；
`V17_SENSOR_AUTHORITY=off` 降级（view/summary 空、compare 不可用、不崩溃）；
view/compare/bridge_state JSON 可回读。按任务要求未跑全量回归。

## 7　边界 / 未完成

- **shadow advisory only**：不写 TrackTable/V15、不改显示层；V15 传感器权威不变。
- **authoritative 为显示层权威**（R5-AUTHORITY-DISPLAY-1）：模型仍 shadow，bridge 不写 TrackTable；state 仅映射 V15 显示字段（显式 env）。
- 模型仅覆盖 radar/TWS/VIS/IR；IFF/ELINT 未接入（identity=unknown，不判敌）；姿态未建模
  （光学视轴默认 LOS，模型 warning）。
- snapshot 为 L1 局部板，未做 ECI/姿态/跨帧转换；目标来自 caller snapshot（V2 world contacts）。
- 不接 HUD/plot（后续任务）；compare 仅诊断，不自动融合/写等级。
- 未跑全量回归；未 commit。
