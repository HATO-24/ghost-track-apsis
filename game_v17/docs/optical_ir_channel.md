# R5-OPTICAL-IR-1 · 完整光学 / 红外通道模型

> 任务 R5-OPTICAL-IR-1（task-86）。工程 `game_v17/framework/sim`。
> **只做只读模型 + 单次 probe + 文档**：不接 UI / bridge / sensor_authority / core；
> 不修改现有 `optical.gd` / radar / tws；不写 TrackTable / V15；不 commit。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `framework/sim/optical_ir_channel.gd`（新） | `V2OpticalIRChannel`：相机/望远镜参数、FOV/IFOV、遮挡、光照/反照/眩光、角尺寸、SNR、曝光、凝视、运动模糊、锁定/分类、多目标/多通道 |
| `tests/optical_ir_probe.gd`（新） | 单次 headless probe：**OPTICAL IR PROBE RESULT: PASS=149 FAIL=0** |
| `docs/optical_ir_channel.md`（本文件） | 字段、公式、probe、与 sensor_authority / sensor_explorer 的关系、边界 |

## 2　定位与边界

- 这是 **完整功能模型**，不是 `sensor_authority` 的替代：authority 可实例化本模型，把 world/entity snapshot 喂给 `step(dt, snapshot)`，读取通道 view-model；本文件不写任何世界状态。
- VIS/IR 完全独立：两套传感器、两套云台/通道；同一目标可同时开 VIS+IR 通道，互不覆盖。
- VIS：`level_support` 最高 **L3**（锁定+像素+SNR 分类）；只输出 `classification`（舰级/角色/阵营等来自目标数据），**不输出 identity**。
- IR：锁定只表示热源稳定跟踪，**最高 L1**，不分类、不升 L3；阴影内仍可工作。
- 光学/IR 均为被动：不产生 `expose_self`；不给测量距离：`measured_range_km=-1`，只给几何 `slant_range_km`。
- 不接 UI/bridge；`vm_optical_ir()` 为 JSON 只读快照，`writes={track_table:false,v15:false}`、`authoritative=false`。
- 无随机源：同 setup/同 snapshot/同 dt → 输出逐位一致（可回放/对比）。

## 3　传感器参数（默认基线）

`default_sensors()` 提供 VIS `MS-OT2` + IR `CH-IR2`，可通过 `setup({"sensors": {...}})` 或 `set_sensor(kind, cfg)` 覆盖。

| 字段 | MS-OT2（VIS） | CH-IR2（IR） | 说明 |
| --- | --- | --- | --- |
| `kind` | optical | ir | VIS/IR 独立 |
| `band` | 0.4–0.7 µm | 8–12 µm | 波段 |
| `wavelength_um` | 0.55 | 10.0 | 衍射限 |
| `aperture_m` | 1.2 | 0.35 | 口径 D |
| `focal_m` | 4.8 | 1.2 | 焦距 f |
| `detector_px` | 4096 | 1024 | 探测器宽/高像素 |
| `pixel_pitch_um` | 5.0 | 15.0 | 像元 |
| `range_km` | 15,000 | 60,000 | 标称探测距离 |
| `refresh_s` | 8.0 | 1.0 | 帧刷新/采样 |
| `stare_s_ref` | 40 s @ 8,000 km | 4 s（锁定） | VIS 凝视基准；IR 固定 4 s |
| `illum_min` | 0.10 | 0（热特征） | VIS 最低光照 |
| `min_snr_db` | 8 | 8 | 检测阈值 |
| `max_exposure_s` | 1.0 | 0.25 | 单帧曝光/积分 |
| `classification_px` | 3.0 | 0（不分类） | VIS 分类最低像素覆盖 |
| `reset_maneuver_g` | 0.02 | 0.05 | 自舰机动中断凝视 |
| `reset_angular_rate_dps` | 0.5 | 1.0 | 姿态角速度中断 |
| `track_rate_dps` | 0.8 | 1.2 | 万向架跟瞄角速度上限 |
| `slew_rate_dps` | 5.0 | 6.0 | 云台转向速率 |
| `sun_avoid_deg` | 5.0 | 0（无可见光眩光） | 太阳进入视轴安全角 |
| `lost_hold_s` | 8.0 | 8.0 | 失锁保留凝视进度 |
| `ref_snr_db` / `ref_range_km` / `ref_aperture_m` / `ref_exposure_s` | 16 / 15,000 / 1.2 / 1.0 | 20 / 60,000 / 0.35 / 0.25 | SNR 归一化基线 |
| `sigma_bearing_deg` | 0.05 | 1.2 | 测向 σ |

推导字段（`prepare_sensor` 自动计算，允许覆盖前先合并）：
- `detector_width_m = detector_px · pixel_pitch_um · 1e-6`
- `fov_deg = 2·atan(detector_width_m / (2·focal_m))`（全角）
- `ifov_rad = pixel_pitch_um·1e-6 / focal_m`
- `diffraction_rad = 1.22·λ / D`
- `ifov_eff_rad = max(ifov_rad, diffraction_rad)`
- `fov_half_deg`、`ifov_urad`、`ifov_eff_urad`、`detector_width_m`

默认值校验：MS-OT2 FOV≈0.2444°、IFOV≈1.0417 µrad；CH-IR2 FOV≈0.7334°、IFOV_eff≈34.86 µrad（衍射限）。

## 4　几何 / 物理

### 4.1　FOV / 视轴 / 云台

- 视轴 `boresight_deg/el_deg`（0°=北/+y，90°=东/+x，el 向上 +z）；LOS 由 `target_pos - observer_pos` 计算。
- `off_axis_deg = angle(boresight_unit, LOS_unit)`；`off_axis > fov_deg/2` → 失败 **`fov_miss`**。
- `start_channel`：
  - 默认：无活动通道时云台 slaved 到目标；已有通道时保持视轴，由 `desired_target` + `slew_rate_dps` 逐步转向；
  - `opts.boresight_deg/boresight_el_deg` → 固定视轴；`set_boresight(kind, az, el)`、`aim_at(kind,target_id)`。
- `step` 先按 `slew_rate_dps` 转向 desired target，再检各通道；输出 `boresight_deg/el`、`bearing/elevation`、`off_axis_deg`。

### 4.2　遮挡

- snapshot `los=false` → **`occluded`**。
- 地球：默认球心 `[0,0,0]`、半径 6,378.137 km；线段（observer→target）穿过球体 → `occluded`。
- 月球：snapshot `moon{pos_km,radius_km}`；同样线段-球体相交 → `occluded`。
- 观测者在球内时不因地球自身判遮挡（避免默认原点场景全遮挡）。

### 4.3　光照 / 反照 / 眩光

- VIS 光照：`illum = sun_illum·(1-shadow) + earth_albedo·0.5`，再乘 `optics_transmittance`；目标 `illum` 可限制上限；`shadow=true`/太阳 0 → `too_dark`，IR 不受可见光阴影影响。
- IR 热对比：`contrast = (T/300)⁴ · (area/1000m²) · shadow_factor`（阴影 0.6）；`contrast <0.02` → `too_dark`；有效探测距离 `range_km·sqrt(contrast)`。
- 太阳眩光：`sun_dir` 与 LOS 夹角 `< sun_avoid_deg` → VIS **`dazzled`**；太阳离轴不触发。

### 4.4　目标角尺寸 / 分辨率

- `angular_size_rad = size_m / (range_km·1000)`
- `n_px = angular_size_rad / ifov_eff_rad`（像素覆盖）
- 角分辨率：`ifov_urad`（探测器）/`ifov_eff_urad`（衍射限取大）
- VIS 分类需 `n_px ≥ classification_px`；IR 不分类。

### 4.5　SNR / 曝光

```
SNR(dB) = ref_snr
        + 20·log10(aperture_m / ref_aperture_m)
        + 20·log10(ref_range_km / range_km)
        + 10·log10(exposure_s / ref_exposure_s)
        + 10·log10(signal)
signal = illum（VIS）或 contrast（IR）
```

- `exposure_s = max_exposure_s`（单帧积分）；曝光降低会降低 SNR。
- `range_km > range_km·sqrt(signal)` → **`out_of_range`**；`snr_db < min_snr_db` → **`low_snr`**。
- 大孔径提高 SNR（20log10 关系）；阴影/低光照降低 VIS SNR。

### 4.6　相对角速度 / 运动模糊 / 跟瞄

```
omega = |r × (v_target - v_observer)| / |r|²
omega_total = omega + |observer.angular_rate_dps| (rad/s)
smear_px = omega_total · exposure_s / ifov_eff_rad
```

- `omega_total` 的 deg/s > `track_rate_dps` → **`too_fast`**。
- `smear_px > 1.0` → **`blurred`**（图像模糊，不能继续凝视）；`0.5 < smear ≤ 1` 会降低 VIS 有效 quality/凝视推进（不会瞬间清零），分类要求 `smear_px ≤ 0.5`。
- 自舰 `maneuver_g > reset_maneuver_g` → **`maneuver`**，凝视清零/状态失锁；观测者姿态角速度计入 `omega_total`。

### 4.7　凝视 / 锁定 / 分类

```
VIS required_s = clamp(stare_s_ref · (range/stare_ref_km)² / quality, 4, 240)
quality = illum（可见光），smear>0.5 时再乘 1/(1+smear)
IR  required_s = 4 s
```

- 状态机：`idle → acquiring → staring → locked`；条件不满足 → `lost`（保留进度；超过 `lost_hold_s` 清零；恢复可重新捕获）。
- 锁定（`progress ≥1`）后：
  - VIS：`n_px≥classification_px` 且 `snr≥min_snr` 且 `illum≥illum_min` 且 `smear_px≤0.5` → `classify_ok=true`、`level_support=3`、`classification` 赋值；否则 `level_support=1`；
  - IR：`level_support=1`，不分类；
  - 两者 `identity="unknown"`、`measured_range_km=-1`。
- 失败原因：`fov_miss / occluded / too_dark / dazzled / out_of_range / low_snr / too_fast / blurred / maneuver / target_missing / no_sensor`。

## 5　API

```gdscript
const O := preload("res://framework/sim/optical_ir_channel.gd")
static O.default_sensors() / default_sensor(kind) / prepare_sensor(cfg, kind)
static O.make_snapshot(t, observer, targets, env) / make_target(id, pos_km, opts)

var m = O.new()                                   # 默认 MS-OT2 + CH-IR2
m.setup({"sensors": {"optical": {...}, "ir": {...}}, "enabled": true})
m.set_sensor(kind, cfg) / m.has_sensor(kind) / m.set_enabled(on)
m.start_channel(kind, target_id, opts := {})      # opts: elapsed_s / boresight_deg / boresight_el_deg / desired_target
m.stop_channel(kind, target_id := "") / stop_all()
m.set_boresight(kind, az_deg, el_deg := 0) / aim_at(kind, target_id)
m.step(dt, snapshot) -> {t,dt,enabled,channels,by_status,sensors,events}
m.channel(kind,target_id) / channel_status(target_id := "") / active_targets(kind := "")
m.export_channel(ch) / export_channels() / sensors_view() / by_status()
m.vm_optical_ir() / to_dict() / summary()
```

### 5.1　ChannelView 字段

`channel/target_id/status/status_since_t/progress/stare_s/required_s/refresh_s/samples/exposure_s/model/band/aperture_m/focal_m/detector_px/pixel_pitch_um/fov_deg/ifov_urad/ifov_eff_urad/boresight_deg/boresight_el_deg/bearing_deg/elevation_deg/off_axis_deg/slant_range_km/measured_range_km/range_band/effective_range_km/illum/contrast/snr_db/min_snr_db/angular_size_rad/n_px/classification_px/smear_px/omega_dps/track_rate_dps/visible/detected/locked/classify_ok/level_support/level_cap/classification/identity/reason/failures/locked_t/lost_at/predicted_next_t/history`

### 5.2　VM

`vm_optical_ir()`：
- `schema="optical_ir.v1"`、`model="optical_ir_channel.v1"`、`mode="shadow"`、`authoritative=false`、`enabled`、`t`；
- `sensors{optical,ir}`（型号/口径/焦距/FOV/IFOV/曝光/云台/活动通道数）；
- `channels[]`（ChannelView）、`by_status`、`events[]`、`warnings[]`、`summary`；
- `writes={track_table:false,v15:false}`、`summary{channels,locked,staring,acquiring,lost,optical_l3,ir_l1}`；
- 全部 JSON 安全，无 Vector3。

## 6　验证（单次）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/optical_ir_probe.gd
# 末行 OPTICAL IR PROBE RESULT: PASS=149 FAIL=0 / OPTICAL IR PROBE OK，退出码 0
```

覆盖（10 节，149 断言）：
1. 相机参数/FOV/IFOV 公式一致性、波段/刷新/曝光、只读标志、缺传感器；
2. FOV 内外、`fov_miss`、手动 `set_boresight`、off_axis；
3. 地球/月球/环境 LOS 遮挡；
4. 阴影 `too_dark`、地球反照弱补光、太阳视轴 `dazzled`、太阳离轴不触发；
5. 角尺寸/N_px（6@8k/3.2@15k/1.6@30k）、SNR 口径/曝光关系、`low_snr`；
6. 凝视 required、锁定、VIS 分类 L3 + classification、identity/无测量距离、失锁保持/超时清零；
7. 运动模糊 `blurred`、角速度 `too_fast`、自舰机动 `maneuver`、低速可凝视；
8. IR 4 s 锁定/L1/不分类/阴影可用/range_band/热对比；
9. 多目标 VIS+IR、停止互不影响、容量 `capacity_full`、视轴输出；
10. 错误/目标缺失、JSON、只读、确定性。

## 7　与 sensor_authority / sensor_explorer 的关系

- **sensor_authority**：后续 R5 可在 authority 内实例化本模型（替代/增强现有 `optical.gd` 通道窗）；authority 负责输入 world/entity snapshot、环境、挂载开关，并读取 `vm_optical_ir()`；本模型不写 authority/world/TrackTable/V15。
- **现有 `optical.gd`**：本任务**未改**；其状态机语义（idle→…→lost、IR 4 s、VIS 分类 L3）与本模型兼容。迁移建议：先在 probe/验证台并行对比两模型；确认字段后由 authority 选择新模型，旧模型保留回退。
- **sensor_explorer**：验证台可把本模型的 FOV/IFOV/角速度/遮挡函数（static，可直接调用）用于其几何演示；本模型不反向依赖 demo 数据。
- 与 `sensor_authority` 的 `channel(kind,target)`/`channels(kind)`/`optical_summary()` 字段对齐：本模型 `channel_status/export_channels/summary` 可作为数据源；具体 adapter 留 R5 后续任务。

## 8　限制 / 未完成

- 模型是工程近似：SNR 为归一化工程公式，不是完整辐射传输/大气/探测器噪声链；FOV/IFOV/口径/波长关系按真实几何推导。
- 遮挡只做地球/月球球体线段相交，不含站体/舰体/地形/大气；月球位置需调用方提供，不内置星历。
- 运动模糊只按曝光积分与瞬时相对角速度；不含滚动快门/姿态振动/多帧配准。
- 多通道共享每类传感器一个云台视轴；多相机/多站组合留后续。
- 不分类身份、不写 TrackTable/V15、不接 UI/bridge；`start_channel` 不验证目标存在（step 时报 `target_missing`）。
- 只跑一次 probe，未做全量回归；现有 optical.gd / UI / bridge 未接线。
