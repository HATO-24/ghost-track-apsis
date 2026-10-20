# R5-SHADOW-1 · 传感器权威 shadow（V2 Radar/TWS/Optical）

> 任务 R5-SHADOW-1（task-73）。工程 `game_v17` framework/sim。
> **shadow 模式**：V2 传感器模型完整计算 advisory 结果；V15 仍是显示权威；
> **绝不写 TrackTable / V15 state**。不接 HUD/core，不做 authoritative 切换。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `framework/sim/sensor_authority.gd`（新） | `V2SensorAuthority`：shadow 传感器管理器；输入 snapshot+mounts，调用 V2 radar/TWS/optical，输出 advisory contacts/observations/channels/warnings；只读 `compare(legacy_tracks)` |
| `tests/sensor_authority_probe.gd`（新） | headless probe：**SENSOR AUTHORITY PROBE RESULT: PASS=286 FAIL=0**（10 节） |
| `docs/sensor_authority.md`（本文件） | 模式、字段、API、compare 语义、probe、切换路径、边界 |

未改 core/ui/bridge/state/project、现有 sim 模型；未 commit。

## 2　模式与单一权威边界

| 模式 | 权威 | shadow 行为 |
| --- | --- | --- |
| `legacy_v15`（当前 V17 默认） | V15 `sensor_model` 融合写 `state.tracks` | V2 只读 advisory（本任务仍只做影子，不接 state） |
| `shadow`（本实现） | V15 仍写显示 | V2 authority 全算 shadow；输出只读快照，**不回写任何 V15/TrackTable 数据** |
| `v2_authoritative`（R5 目标，未做） | V2 authority + world/TrackTable | 本任务明确**不实现**；只准备 shadow 数据与对比器 |

硬保证（代码/字段可审计）：

- `mode="shadow"`、`authoritative=false`；
- `writes_track_table=false`、`writes_v15=false`，`vm_sensor().writes={track_table:false,v15:false}`；
- `V2SensorAuthority` 不 preload `state.gd`/`world.gd`/`track_table.gd`，没有任何写入/注入 API；
- `compare()` 只读 legacy_tracks 与 advisory，两者均不被修改（probe 用深拷贝对比）；
- 本任务不改 `state.tracks`/`flow`/威胁/身份；HUD 不读本模块（后续 R5 adapter 再接）。

## 3　输入

### 3.1　observer（本舰）

```json
{
  "id": "harmattan",
  "pos_km": [x, y, z],
  "vel_kmps": [vx, vy, vz],
  "attitude_quat": [x, y, z, w],
  "attitude_source": "default_not_modeled",
  "angular_rate_dps": [p, q, r],
  "maneuver_g": 0.0,
  "mast_deployed": true,
  "emcon": false,
  "damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0}
}
```

**姿态未接入**：默认 `quat=[0,0,0,1]` + `attitude_source=default_not_modeled`，
HUD/vm warnings 明示 `ATTITUDE NOT MODELED`；光学视轴默认按本舰→目标 LOS（仅 shadow 标注，不冒充真实姿态）。

### 3.2　sensor mounts（默认 harmattan）

| mount_id | model | kind | 说明 |
| --- | --- | --- | --- |
| `harmattan/YW-R9` | YW-R9 | search_radar | 球形搜索 + TWS 六态；`mast_dependent=true` |
| `harmattan/MS-OT2` | MS-OT2 | optical | VIS 凝视/分类 |
| `harmattan/CH-IR2` | CH-IR2 | ir | 被动 IR（只到 L1） |

挂载可覆盖/替换（`setup({"mounts":[...]})`），支持 `enabled/destroyed` 运行时开关；
`set_mount_enabled(mount_id,on)` 只改 shadow 自身挂载状态，**不调用 V15 `set_sensor`**。

### 3.3　world / entity snapshot（V2 world_snapshot 契约）

```json
{
  "t": 1234.5,
  "observer": {"id":"harmattan","pos_km":[...],"v_kmps":[...],"maneuver_g":0.0},
  "targets": [
    {"id":"T1","entity_id":"...","batch":"2010","name":"目标1",
     "pos_km":[...],"vel_kmps":[...],"rcs_m2":10.0,"temp_k":300.0,"area_m2":1000.0,
     "illum":1.0,"classification":{"ship_class":"DDG","role":"escort","faction":"unknown"},
     "transponder":"off","iff_code":"","faction":"unknown","emissions":[]}
  ],
  "sun_illum":1.0,"jamming":0.0,"shadow":false,"los":true
}
```

允许 `params` 单位：km、km/s、deg、m²、K；模型只读，不改 snapshot（内部 normalize 副本）。
缺省字段（rcs/illum/temp/area/batch/classification）由 authority 归一补默认；无效/重复/无位置目标跳过。

## 4　API

```gdscript
const Auth := preload("res://framework/sim/sensor_authority.gd")
static Auth.default_observer(id) / default_mounts(id)
static Auth.make_target(id, range_km, bearing_deg, opts)    # 测试目标行
static Auth.make_snapshot(t, observer, targets, env)        # world_snapshot

var a = Auth.new()
a.setup({...})                       # 返回 bool；ready/errors
a.set_observer(observer_dict)
a.set_snapshot(snapshot_dict)        # 归一化只读副本
a.set_snapshot_targets(targets)
a.set_mount_enabled(mount_id, on)    # shadow 本地；返回 {ok,shadow,writes_v15:false}
a.start_channel(kind, target_id)     # VIS/IR；mount 关闭/损坏时拒绝
a.stop_channel(kind, target_id := "")

# 每 tick（由未来 bridge/core 调用；本任务不接）
a.step(dt, snapshot := {}) -> vm_sensor 字典

# 只读查询
a.advisory_contacts           # advisory contact 行
a.advisory_observations       # sensor_observation.v1 行
a.channels(kind := "")        # radar.tws / optical / ir
a.channel(kind, target_id)
a.radar_sphere                # shape=sphere / no_sector / 标称/有效/跟踪半径 / 刷新 / scan_index / exposure
a.exposure_state              # V2 exposure_state（ELINT 截获/定位）
a.optical_summary()           # by_status/channels/enabled/attitude_source
a.warnings                    # shadow/attitude/identity/EMCON/mount/damage/扫描等
a.compare(legacy_tracks)      # 只读差异摘要（schema sensor_shadow_compare.v1）
a.vm_sensor() / to_dict()     # schema sensor_shadow.v1，JSON 安全
a.summary()
```

### 4.1　输出字段（`vm_sensor` / contact / observation）

- `vm_sensor`：`schema="sensor_shadow.v1"`、`mode`、`authoritative=false`、`ready/t/dt/step_count`、
  `observer/mounts/records`、`radar{enabled,sphere,exposure,scan_index,seconds_on,...}`、
  `channels`、`optical_summary`、`advisory_contacts`、`advisory_observations`、`warnings`、`notes`、
  `events`、`writes`、`shadow{attitude_source,identity_scope,last_compare}`、`counts`。
- `advisory_contact.v1`：`id/track_id/entity_id/batch/name/level/level_label/identity/classification/
  bearing_deg/range_km/range_sigma_km/range_band/quality/age_s/stale/sources/level_evidence/
  phantom/spoof_flags/threat="none"/mode/authoritative=false/provenance="v2_sensor_shadow"`。
  - level：V2 TWS/Radar 检测 → L2；VIS 锁定 → L3（分类）；IR → L1（仅方位）。
  - identity：**恒 unknown**（本 shadow 不含 IFF/ELINT，不判敌）；identity_scope 标注。
- `sensor_observation.v1`：`id/t/observer_id/mount_id/sensor_model/target_id/kind/detected/pd/
  level_support/produces_contact/bearing/range/range_sigma/range_band/quality/classification/
  notes/reason/extra{...}/mode/authoritative=false/provenance`。
  - kind：`radar`（扫描观测，含 detected=false 与 reason）、`radar.tws`（六态通道）、`optical`、`ir`。

### 4.2　门控（shadow 本地）

- 雷达/TWS：mount.enabled && !destroyed && !observer.emcon && mast_deployed && damage.sensors≥0.5；
- VIS/IR：对应 mount.enabled && !destroyed && damage.sensors≥0.5（mast 仅当 mount 标 mast_dependent）；
- EMCON/桅杆/损坏/关闭只影响 shadow 结果与 warnings，**V15 的 sensor_on/emcon 不被修改**；
- shadow 挂载关闭后 `radar_sphere.active=false`、对应观测停止；重新开启后恢复扫描。

## 5　compare（只读差异分析）

`compare(legacy_tracks)` 输入 V15 `state.tracks` 形态（也可传 `{tracks:[...]}`），按键匹配：
`batch` 优先，其次 `track_id/id/entity_id`；own 航迹跳过。

输出 `sensor_shadow_compare.v1`：

```json
{
  "ok": true, "mode": "shadow", "authoritative": false, "read_only": true, "t": 132.5,
  "advisory_count": 6, "legacy_count": 6, "legacy_skipped_own": 1, "matched_count": 6,
  "diffs": [{"key":"2010","batch":"2010","advisory_level":3,"legacy_level":2,
             "level_delta":1,"level_agree":false,
             "advisory_identity":"unknown","legacy_identity":"friend","identity_diff":true,
             "identity_scope":"shadow_no_iff_elint",
             "advisory_range_km":10000.0,"legacy_range_km":10000.0,"range_delta_km":0.0,
             "advisory_bearing_deg":40.0,"legacy_bearing_deg":40.0,"bearing_delta_deg":0.0,
             "reason_guess":"advisory_higher: V2 VIS/TWS 证据更高（shadow 上游未融合/未降级）"}],
  "only_advisory": [], "only_legacy": ["2099"],
  "summary": {"level_equal":4,"level_advisory_higher":1,"level_advisory_lower":1,
              "identity_diff_unscoped":4,"only_advisory":0,"only_legacy":1,
              "avg_range_delta_km":0.0,"avg_bearing_delta_deg":0.0,
              "level_gate_pass":false,"within_tolerance":false},
  "tolerances": {"level": 0, "range_km": 5.0},
  "warnings": ["COMPARE READ-ONLY: legacy_tracks 与 advisory 均未被修改",
               "IDENTITY SCOPE: ..."]
}
```

- 只读：legacy 输入与 authority 状态均不变（probe 深拷贝验证）。
- identity 差异只记录、不参与 shadow 门禁（本 shadow 无 IFF/ELINT）；
- `reason_guess` 给出等级差异来源（VIS 升级 / 缺少融合老化 / 球外等）。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/sensor_authority_probe.gd
# 末行 SENSOR AUTHORITY PROBE RESULT: PASS=333 FAIL=0 / SENSOR AUTHORITY PROBE OK，退出码 0
```

覆盖（11 节）：
1. 初始化/挂载/记录/mode/writes/warnings/summary；非法装配失败；
2. snapshot/目标归一（缺省字段、重复/无效过滤、JSON）；
3. 球形雷达（shape/sphere/no_sector/R_eff 30,000/track 15,000/refresh 6/active/scan_index/in_sphere 6）+
   TWS 六通道（状态/FC×3/quality/aging）+ 观测类型 + 6 advisory contacts + T1 L3 分类；
4. VIS/IR（锁定、L3/L1、attitude_source、start/stop channel、summary）；
4b. **光学后端切换**（§9）：optical_ir VIS L3/IR L1、FOV/occlusion/snr/boresight 字段、fov_miss/occluded/blurred；
   legacy 回退（config/opts/set_optical_backend）、单通道回退、compare 不变、不写 TrackTable；
5. 光学阴影（illum=0 → VIS lost/shadow；IR 仍 locked）；目标在球外/失锁路径；
6. EMCON/桅杆/损坏/挂载开关/非法通道；
7. **shadow 不写**：V2 TrackTable 签名不变、legacy 输入不变、无 tracks/track_table 字段、contacts 不增删；
8. compare（higher/lower/equal/only_legacy/own skip/identity scope/reason/只读缓存/非法输入）；
9. JSON（vm/contacts/observations/channels/compare；无 Vector3）+ 确定性（两实例逐位一致）；
10. 错误/边界（未初始化、空 target、负 dt clamp、warnings 完整）。

## 7　R5 切换路径（后续，不在本任务实现）

1. **R5.0 开关**：`state.sensor_authority` + `V17_SENSOR_AUTHORITY=legacy|shadow|v2`；
   legacy 默认、行为不变；shadow 只跑本 authority + compare，不接显示。
2. **R5.2/R5.3 接入**：`framework_bridge` 启动时创建 `V2SensorAuthority`（本任务未改 bridge）；
   每 tick 把 V2 world/entity snapshot + mounts 传入 `step(dt,snapshot)`；把 `vm_sensor()`
   暴露为 `fw_sensor_shadow`；shadow 下 V15 仍写显示；`compare(state.tracks)` 写诊断
   （不写 tracks）。
3. **R5.6 `v2_authoritative`**：由 core TrackTable/EventBus 接收本 authority 的观测
   （经未来 `ingest` 路径；本任务不提供写 API），V15 改 adapter 只读；
   切换需显式状态机 + 回退开关。
4. **R5.1 姿态/挂载/环境**：真实 `attitude_quat/angular_rate`、FOV/IFOV、IFF/ELINT/EW 接入后，
   本 shadow 的 `ATTITUDE NOT MODELED`/`identity=unknown` 标注才可移除。
5. 回退：`legacy_v15` 环境变量；shadow 不改变玩家可见结果，可随时关闭。

## 8　限制 / 未完成

- 只覆盖 radar/TWS/VIS/IR；IFF/ELINT/COMINT/EW/通信侦察未接入（identity 恒 unknown，不判敌）。
- 姿态未建模：光学视轴用显式默认 LOS 并 warning，不能替代真实姿态/FOV/IFOV。
- 目标来自调用方 snapshot（未来 core world adapter）；本任务不做 world/V15 自动对接。
- 雷达观测按扫描节拍输出；TWS 通道每 tick 输出；光学按凝视刷新，均按 V2 模型真实 step。
- compare 为只读诊断：不自动融合、不写等级/身份/威胁；不处理 replay/事件总线。
- 不修改 TrackTable/V15；authoritative 切换、HUD 页面、bridge 字段均留给后续 R5 任务。
- 位置/速度/坐标帧：本 shadow 使用调用方 snapshot 的同一帧（默认 L1 局部板）；跨帧转换（ECI/L1）由 R6/world adapter 负责。


---

## 9　R5-SENSOR-OPT-1：统一光学/IR 后端（optical_ir / legacy）

> 任务 task-90。只改 `framework/sim/sensor_authority.gd`、`tests/sensor_authority_probe.gd`、本文件；未改 `optical_ir_channel.gd`、bridge/state/ui/core；未 commit。
> 目标：光学/IR 通道接入 `V2OpticalIRChannel` 的真实 FOV/遮挡/光照/角速度/凝视/SNR，同时保留旧 `optical.gd` 回退。

### 9.1　后端选择

| 方式 | 字段 | 默认/说明 |
| --- | --- | --- |
| authority 级 | `setup({"optical_backend": "optical_ir"|"legacy"})` | 默认 **optical_ir**；非法值 warning + 回退 legacy |
| 单通道 | `start_channel(kind,target,{"backend":"optical_ir"|"legacy"})` | 逐通道选择；可混合 |
| 运行时默认 | `set_optical_backend("optical_ir"|"legacy")` | 只改之后 start 的默认；已有通道继续存在于各自后端 |
| 查询 | `optical_backend()` / `vm_sensor().optical_backend` / `optical_summary().available_backends` | 两个后端均实例化；`available_backends` 反映实际可用 |

- 两个后端**都 step**；各自只处理通过其 `start_channel` 建立的通道。legacy 通道与 optical_ir 通道可并存（probe 覆盖）。
- 请求 backend 不可用时（如新后端初始化失败）：`start_channel` 回退 legacy，返回 `backend_fallback=true` / `reason_text`；不伪造新后端结果。
- 仍为 shadow：不写 TrackTable/V15；`writes_track_table=false`、`writes_v15=false`。

### 9.2　新增/增强字段

**channels[]**（`channels_cache` / `vm_sensor().channels`）新增：
`backend`（`optical_ir|legacy`）、`fov_deg`、`ifov_urad`、`ifov_eff_urad`、`boresight_deg`、`boresight_el_deg`、`off_axis_deg`、`occluded`、`occlusion`、`snr_db`、`snr_available`、`visible`、`detected`、`effective_range_km`、`angular_size_rad`、`n_px`、`smear_px`、`omega_dps`、`level_cap`。

- `optical_ir`：这些字段来自真实模型；`status` 含 idle/acquiring/staring/locked/lost，`reason` 可为
  `fov_miss/occluded/too_dark/dazzled/out_of_range/low_snr/too_fast/blurred/maneuver/target_missing`。
- `legacy`：`status/凝视` 来自旧 optical.gd；`fov/ifov/boresight` 为同型号相机表的只读元数据；
  `snr_db=-999`、`snr_available=false`（legacy 不计算 SNR，不冒充）；`occluded` 由 legacy reason 映射。
- **observations**（`sensor_observation.v1`）新增 extra：`backend/fov_deg/ifov_urad/off_axis_deg/boresight_deg/
  snr_db/snr_available/occluded/occlusion/visible/angular_size_rad/n_px/smear_px/omega_dps/level_cap`；
  notes 增加 `backend=`、`fov=... off_axis=...`、`snr=... dB`、`occluded=true`。
- **optical_summary()** 新增/保留：
  `backend`、`available_backends[]`、`backend_counts{legacy,optical_ir}`、`sensors{optical,ir}`
  （口径/焦距/FOV/IFOV/曝光/云台/活动通道）、`notes[]`；保留 `by_status`/`channels`/`enabled`/`attitude_source`。
- **vm_sensor()** 新增：`optical_backend`、`optical_backends{active,available,legacy_available,
  optical_ir_available,notes}`；`summary()` 同步 `optical_backend`/`optical_backends_available`。
- `compare()` **不变**（schema/只读语义保持；probe 断言）。

### 9.3　advisory / 等级规则（与旧 shadow 一致）

- VIS（新后端）：锁定 + 分类判据成立 → `level_support=3`、classification；未分类 → 1；IR → 1。
- identity 恒 unknown；不判敌；不写 V15/TrackTable。
- 观测 failure（fov_miss/occluded/blurred 等）以 `detected=false`、真实 `reason` 进入 observations；
  不生成伪造 contact。

### 9.4　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/sensor_authority_probe.gd
# SENSOR AUTHORITY PROBE RESULT: PASS=333 FAIL=0 / SENSOR AUTHORITY PROBE OK
```

新增 4b 覆盖：
- new backend setup（默认 optical_ir）、两个后端 available、channel backend/fov/boresight/snr/occlusion 字段；
- optical_ir VIS 锁定 → L3 + classification、IR 锁定 → L1、observation backend/字段、advisory contact L3；
- FOV 外 `fov_miss`（固定视轴）；地球遮挡 `occluded`；相对角速度/曝光 `blurred`；
- legacy 回归（config/opts backend=legacy、channel backend、锁定状态）；`set_optical_backend` 与非法 backend；
- 不写 TrackTable；`compare()` schema/read_only 不变；VM backend 字段。
- 旧 10 节全部通过（原 286 断言 + 新 47 = 333）。

### 9.5　边界 / 未完成

- 本任务是 **sensor_authority 内部后端切换**，不接 bridge/state/UI/core；bridge 的 `fw_sensor` 后续再取新字段。
- optical_ir 的 SNR/遮挡/角速度公式见 `docs/optical_ir_channel.md`；legacy 不计算 SNR，字段明确 `snr_available=false`。
- 两后端并存时，同名 target 的不同 backend 通道会分别出现在 channels[]（backend 区分）；advisory 聚合按目标合并等级证据。
- 未做跨后端自动对比/切换迁移（如 legacy→optical_ir 状态迁移）；未改 optical_ir_channel.gd。
- 仍不写 TrackTable/V15；authoritative 切换留给 R5.6。
