# V17-SENSOR-1 TWS / 球形雷达（V15 plot 增量）

> 任务 task-55。工程 `game_v17`（V15 视觉 + `framework/` V2 core/sim）。
> 改动：`scripts/plot.gd`、新增 `scripts/tws_bridge.gd`、新增 `tests/plot_tws_probe.gd`、新增截图
> `mockups/v17-tws.png` / `mockups/v17-radar-sphere.png`、本文件。
> 未改 `hud.gd` / `state.gd` / `main.gd` / `framework/*` / `project.godot`；未 commit。
> 视觉沿用 V15：1px 线、7pt mono、`Palette.PH/PH_DIM/BLUE/AMBER/RED` 色板，不引入 V2 UI 版式。

## 1　文件与职责

| 文件 | 内容 |
| --- | --- |
| `scripts/tws_bridge.gd`（新） | `V17TwsBridge`：只读 V15 `state` → V2 模型数据（球形雷达 R_eff / TWS 通道 / 光学通道），不画 UI、不改 state |
| `scripts/plot.gd` | `_draw_radar_sphere()`（球壳线框 + `SPHERICAL SEARCH · R_eff … km`）、`_draw_tws_channels()`/`_draw_tws_ring()`（六态环 + 短标签）、`_v17_exposure_line()`（EMIT 状态行改用 V2 暴露数据）；替换旧「未建模」文案 |
| `tests/plot_tws_probe.gd`（新） | headless probe：V2 模型装载 / 6 通道状态机 / 球形 R_eff / 暴露 / 关机 EMCON / 光学通道 / 只读契约 |
| `mockups/v17-tws.png`、`v17-radar-sphere.png` | DSH_SHOT 截图 |

## 2　数据来源与只读契约

- V15 侧（只读）：`state.racks`（`SensorModel.all_racks()`）、`state.sensor_on`、`state.tracks`
  （`id/name/en/cls/role/side/level/r/v/epoch/own/phantom/occluded/off`）、`state.tau()`、
  `state.board_pos(track, tau)`、`state.is_emcon()`、`state.is_mast_deployed()`、`state.radar_on_t`。
- V2 侧（`framework/sim/`，只调用）：
  - `radar.gd`：`nominal_radius_km` / `effective_radius_km` / `effective_track_radius_km` /
    `sphere_for` / `exposure_state`；
  - `tws.gd`：`V2TwsModel` 六态状态机（`SEARCH→DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL`）；
  - `optical.gd`：`V2OpticalModel`（VIS/IR 凝视通道，plot 暂仍用 V15 光学绘制，桥已提供数据）。
- V2 记录由 V15 型号架转换：`V2SensorTypes.record_from_rack_sensor(SensorModel.rack_sensor(...))`；
  哈马丹 `YW-R9` → 球形搜索雷达、`range=30,000 km`、`track_range=15,000 km`、`refresh=6 s`、
  `TWS 通道=6`。R_eff 基准 RCS = 10 m²（与 `docs/11` §3.2 一致）→ **R_eff = 30,000 km**。
- **桥不修改 V15 state**：不调 `set_sensor/refresh/clock/...`；probe 用 state 签名（clock/tracks/sensor_on/
  own_events）在 bridge 前后对比验证。`state.board_pos` 只读计算本舰/目标 L1 局部坐标。

## 3　API（`scripts/tws_bridge.gd`）

```gdscript
var bridge = V17TwsBridge.new(state, {"ship": "harmattan", "radar_model": "YW-R9"})
bridge.step(dt)          # dt<0：按 state.tau() 差值追帧（plot 每帧调用，自动补算）
                         # dt>=0：显式推进（probe/外部时钟）
                         # → {ok, available?, tau, simulated_dt, active, channels, channel_count,
                         #    active_channels, by_state, sphere, exposure, optical, events,
                         #    state_modified:false}
bridge.channels()        # TWS 通道 + join 的 batch/name/en/side/level/state_index/short/quality/
                         # age_s/update_rate_hz/range_km/.../fire_control
bridge.radar_sphere()    # {available, active, shape:"sphere", no_sector:true, center_km,
                         #  nominal_radius_km, effective_radius_km, track_radius_km, refresh_s,
                         #  scan_index, seconds_on, targets_total, targets_in_sphere, exposure{...}}
bridge.exposure_line()   # EMIT 第二行：球面搜索 · R_eff … km · ELINT 截获 … km / EMCON 提示
bridge.optical_channels() / start_optical(id) / start_ir(id) / stop_optical()
bridge.snapshot()        # 给 V2 模型的 world_snapshot（V15 tracks → pos_km/rcs/classification）
bridge.summary()         # 一行诊断
```

追帧细节：单次最多补 600 s、0.5 s 步长；只把「雷达开机之后」的模拟时间喂给 TWS
（`state.radar_on_t` 之前不补），避免把开机前历史补成已跟踪。雷达/EMCON/桅杆判定沿用 V15
`state.sensor_on` 的当前值（plot/截图钩子提前开机时按已开机处理）。

## 4　plot 绘制

### 4.1　球形雷达范围（不是扇形）

- 仅在 `state.sensor_on["harmattan"]["YW-R9"] == true` 且非 EMCON、桅杆伸出、图层 `radar` 打开时绘制；
  关机/EMCON → 不画。
- 半径直接取 V2 `effective_radius_km`（YW-R9：**30,000 km**，R_eff @ RCS 10 m²）；3D 模式按
  `_px_per_km(本舰局部 km)` 透视投影，压平模式按 `_planar_scale` 投影。
- 画法：球心轮廓圆 + 2 条经线椭圆 + 赤道圈 + 中心十字 + 半径刻度（全部 1px，alpha 0.12–0.30）；
  球壳线框表达「球形」，**不画扇形/锥形/示意圆**。
- 本舰视图内可见半径有限（3D 视野约数百 km 量级），当 R_eff 投影超过视界时按
  `0.46 × min(plot 宽, 高)` 压缩显示，并在标注里写 `视界外按视界压缩`（不伪造比例尺）；
  压平战略图（700,000 km 跨度）里 30,000 km 直接按真实比例约 40 px 显示。
- 标注（7pt mono，带弱底衬 + 1px 引线）：`SPHERICAL SEARCH · R_eff 30,000 km`、
  `球面搜索 · V2 球体半径（非扇形）· 视界外按视界压缩`、`TWS 6 CH · 6 ACTIVE · 状态环在接触旁`；
  标注锚点固定在 plot 右侧 `(size.x-272, size.y-260)`，不压本舰/点火/命令注记。

### 4.2　TWS 通道状态环 / 短标签

- 每个非本舰通道：屏幕点 = `_track_pos(track)`；环半径 21 px：
  - 底环（当前雷达活动时 alpha 0.22，失锁 0.10）；
  - quality 弧（12 点顺时针，alpha 0.48，1px）；
  - 六态刻度（6 等分）：当前态高亮短弧 + 外伸刻度（2px），其余 1px 弱刻度；
  - 颜色：`SEARCH/DETECT/ACQUIRE/TRACK/STARE` = `Palette.BLUE`，`FIRE_CONTROL` = `Palette.AMBER`；
  - 短标签在接触左下 `(-62,+27)`px：`SRCH/DET/ACQ/TRK/STARE/FC + quality%`，FC 追加 `· FC`；
    7pt mono + 弱底衬，不抢 V15 主标签（batch/舰名在 off 方向）。
- 数据完全来自 V2 TWS 状态机（扫描 6 s/次，quality/age/失锁/更新率由 V2 模型给出），plot 不做规则判定。
- 压平战略图里接触聚合成编队框，不画 6 个外圈状态环（避免与编队框/引线标签重叠）；球形范围仍按
  平面比例尺绘制并标注（`· 平面比例尺`）。

### 4.3　文案替换（EMIT / 旧「未建模」）

- `_draw_emit_status` 第二行：`截获半径/扫描范围未建模（第二批 TWS）` → `_v17_exposure_line()`
  （球面搜索 · R_eff 30,000 km · ELINT 截获 45,000 km / EMCON 提示）。
- ELINT 点名行：`（示意连线，范围未建模）` → `（V2 暴露模型 · 截获 45,000 km）`。
- 压平 EMIT 环标注：`（按比例）` → `（V2 模型 · 平面比例）`。
- 底部图层说明：`（截获半径未建模）` → `（球面搜索 / TWS 通道见战术图）`。
- 保留 V15 原语义：L1 方位线、光学凝视进度、IFF 标签、ELINT 点名、通信链路、轨迹预测不变。

## 5　截图（DSH_SHOT）

`plot.gd` 侧截图/演示钩子（不改 state.gd）：`DSH_V17_RADAR=1` → 通过公开 `state.set_sensor()`
提前手动开 YW-R9；`DSH_V17_TWS=0` → 隐藏 TWS 环（只拍球形范围）。

```powershell
$godot = ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
# 1) TWS 通道环（T+14：雷达手动开 14 s → 六通道 TRACK，quality≈83%）
$env:DSH_SCENE="l1"; $env:DSH_SENSOR="2"; $env:DSH_CLOCK="774.8"; $env:DSH_V17_RADAR="1"
$env:DSH_SHOT="D:\GHOST TRACK_APSIS\mockups\v17-tws.png"
& $godot --path .\game_v17
# 2) 球形雷达范围（同 T+14；隐藏 TWS 环，换俯仰看球壳）
$env:DSH_V17_TWS="0"; $env:DSH_YAW="24"; $env:DSH_PITCH="18"
$env:DSH_SHOT="D:\GHOST TRACK_APSIS\mockups\v17-radar-sphere.png"
& $godot --path .\game_v17
```

`DSH_CLOCK` 是绝对仿真时钟（`state.T0=760.8`）：`774.8 = T+14 s`。T+20 前不进入 V15 COMMAND
阶段（不会自动弹出副官/决策覆盖层），因此截图干净；雷达用 `DSH_V17_RADAR=1` 提前开。
坐标/尺寸：plot 区域 `(396,124) 1128×752`；本舰投影在 plot 中心附近；球形标注锚点
plot `(856,492)`（屏幕约 `(1252,616)`）；TWS 环半径 21 px、短标签偏移 `(-62,+27)` px。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/plot_tws_probe.gd
# 末行 V17 SENSOR-1 TWS PROBE PASS；退出码 0；[SUMMARY] pass=59 fail=0
# 日志：game_v17/tests/plot_tws_probe.log

.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --quit
# AUDIO OK；无 SCRIPT ERROR（intro.tscn 解析）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 res://main.tscn --quit
# MAIN READY / V17 FRAMEWORK ok=true / V17 BRIDGE ready=true（plot.gd 解析、桥接层装载）
```

probe 覆盖：V2 模型装载（radar/tws/optical、YW-R9 记录）；step(-1) 追帧 → 6 通道全部
FIRE_CONTROL（quality≥0.85、更新率≈1/6 Hz、age≤6 s）；单通道状态序列覆盖
DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL；球 R_eff=30,000 km 与 `V2RadarModel.effective_radius_km`
直接计算一致、track_radius=15,000 km、6 目标在球内；暴露 ELINT 45,000 km / 20 s 定位；
`world_snapshot` 6 目标 + observer=1001；关机/EMCON → active=false；VIS 凝视 5 s 锁定（L3）；
bridge 前后 state 签名一致（只读）；step/snapshot/last_step JSON 可序列化；`state.board_pos`
可投影全部通道目标。

## 7　未完成 / 边界

- 球形范围是「屏幕空间球壳示意 + 真实 V2 R_eff 数值」：30,000 km 远大于 V15 局部战术视图，
  3D 下按视界压缩显示（标注写明）；压平战略图为真实比例。未做 3D 球体网格/遮挡/深度排序。
- plot 的 TWS 只画状态环 + 短标签，不画通道分配/火控解算细节（V2 `fire_control{}` 已透传，留给后续）。
- 光学/IR：plot 保留 V15 现有凝视语义；V2 `V2OpticalModel` 数据由桥提供（`start_optical/start_ir`），
  是否切换到 V2 光学绘制留给后续任务。
- 桥的模型时间从「雷达开机时刻」开始补算（最多 600 s），不重建开机前的 TWS 历史。
- 未使用 v17-core 的 `state.fw_contacts` 站体/储罐标记（本任务只做 TWS/球形雷达；固定设施标记可由
  plot 后续按 `fw_contacts.fixed/icon/size_km` 增量绘制，V15 tracks 当前不含 0100/0101）。
- 截图钩子 `DSH_V17_RADAR/DSH_V17_TWS` 属于 plot 侧演示/截图自动化，不影响正常游玩（默认不触发）。
