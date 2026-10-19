# SENSOR EXPLORER · 雷达 / 光电 / IFF / ELINT 独立技术演示

> 任务 SENSOR-EXPLORER-1（task-60）。工程 `sensor_explorer/`；V1 线框视觉。
> 本演示**只读调用** V2 传感器模型，不修改 `sim/*.gd` / `scripts/sensor_model.gd` / `project.godot`；
> HUD 固定标注 **`V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17`**。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `sensor_explorer.gd` | Node3D 场景：本舰 + 6 目标 + 球形雷达球/参考面 + TWS 目标环 + 光学视锥 + ELINT 方位线；相机/时间/选择/IFF/ELINT/截图 |
| `sensor_explorer.tscn` | Node3D + Camera3D + MeshInstance3D + CanvasLayer/HUD（引用 `ui/sx_hud.gd`） |
| `ui/sx_hud.gd` | V1 HUD：目标列表、选中详情、TWS 六态面板、事件时间线、传感器状态（暴露/ELINT/VIS-IR/IFF）、时间/倍率、图例/标签、页脚诚实标注 |
| `tests/sensor_explorer_probe.gd` | headless probe：型号记录 / R_eff / 暴露 / TWS 六态 / 失锁重捕 / VIS-IR / IFF / ELINT / JSON / 确定性 |
| `docs/sensor_explorer.md` | 本文件 |
| `mockups/sensor-overview.png`、`sensor-tws.png`、`sensor-optical.png`、`sensor-elint.png` | 4 张 1920×1080 截图 |

## 2　数据来源（V2 模型，只读）

- 型号能力：`sim/sensor_types.gd` → `Types.record(...)`：`YW-R9`（球形搜索雷达，30,000 km / 6 s / TWS 6 通道）、
  `MS-OT2`（VIS 15,000 km / 凝视 40 s@8,000 km）、`CH-IR2`（IR 60,000 km / 4 s 锁定）、
  `MK-12`（IFF 2,000 km）、`ELINT`（60,000 km，被动、只出信号）。
- 球形范围 / RCS / 干扰 / 暴露：`sim/radar.gd`：`effective_radius_km(rec, rcs, jamming)`、
  `effective_track_radius_km(...)`、`sphere_for(...)`、`exposure_state(...)`。
  基准 RCS 10 m² → R_eff = 30,000 km；track ring = 15,000 km；R_eff ∝ RCS^0.25；
  干扰 0.7 时 R_eff ×0.608（YW-R9 抗干扰 0.2）。
- TWS 六态：`sim/tws.gd`：SEARCH→DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL；
  quality / age / 失锁（`max(2×刷新,12 s)`）/ 重捕 / 通道容量 6 / 火控解算；
  每步 `TwsModel.step(dt, snapshot)` 真实推进（不是 HUD 假装）。
- 光学/IR：`sim/optical.gd`：VIS 需光照 + 凝视；IR 4 s；`_fail` 处理 shadow/occluded/out_of_range；
  通道状态 idle/acquiring/staring/locked/lost；VIS/IR 独立通道（不同目标/不同状态）。
- IFF：`scripts/sensor_model.gd::interrogate_iff`（2,000 km；friend / wrong_code / no_reply /
  faulty_transponder；`不明 ≠ 敌意`）。
- ELINT：`scripts/sensor_model.gd::detect_elint`（被动截获发射源；`produces_contact=false`、
  仅方位、静默收不到、超截获距离收不到）+ `emission_for` / `elint_intercept`（本舰发射被对方 ELINT 截获）。

## 3　场景 / 坐标

- 本舰固定在 **L1 局部板坐标系原点**（技术演示；非 V17 关卡数据）。
  板坐标：x=东、y=北、z=天顶（km）；场景单位 **1 unit = 1,000 km**，显示映射 X=东 / Y=天顶 / Z=北。
- 6 个脚本轨迹目标（远距 + 近距编队；近距 3 个用于 IFF 2,000 km 演示）：

| ID | 名称 | 初距 | 作用 |
| --- | --- | --- | --- |
| T1 | 远地点 | 12,000 km | 主光学 VIS 目标（12,000 km，约 90 s 锁定）；TWS 远距通道 |
| T2 | 渡口 | 1,899 km | IFF **无应答**（应答机关闭）；ELINT 发射源 |
| T3 | 望楼 | 24,000 km | t∈[90,200) 进入阴影 → VIS **lost/shadow**，IR 仍工作 |
| T4 | 深井 | 28,500 km ± 3,200 km（120 s 振荡） | 进出 R_eff 球 → TWS **失锁/重捕**可观察 |
| T5 | 传令者 | 28,000 km | 敌意 ELINT 发射源（YW-R9）→ 只截获信号/方位；IFF 超距 |
| T6 | 谷神-2 | 1,501 km | IFF **友方应答**（CMP-207）；IR 锁定目标 |

- 参考面：以本舰为心的水平外环 + 12 方位辐条（标注为 L1 局部板参考面，不伪造地球实体）。
- 球形雷达：真实球体线框（3 大圆 + 5 纬圆，1px）+ track ring；EMCON 关闭即隐藏球体；
  渲染半径 = V2 `effective_radius_km`（随 RCS/干扰变化）。
- 目标标记：八面体 + 3D TWS 环（半径 2.0 units，六态刻度，当前态外伸短线 + quality 外弧；
  蓝=SEARCH..STARE，琥珀=FIRE_CONTROL）+ 发射源小方框。
- 光学视锥：由 V2 optical 通道的 bearing/elevation 生成，锥长按通道实际距离收口
  （VIS 2.0° / IR 3.2° 半角；VIS 薄荷绿、IR 冰蓝）。
- ELINT：仅按方位画虚线（无距离/无接触），符合 05 §S-05。
- IFF：最近询问连线（friend 薄荷绿 / 其他琥珀）。

## 4　控制

- 鼠标：LMB 拖拽旋转；RMB/MMB 拖拽平移；滚轮缩放；点击目标标签/左侧列表选中。
- 键盘：`TAB` 循环目标、`1–6` 选择目标、`0` 相机回本舰、`F` 焦点切本舰/选中目标、
  `R` 重置（相机/时间/速率/事件）、`SPACE` 暂停/播放、`-`/`=` 时间倍率 1×/10×/100×/1000×。
- 传感器：`M` 雷达开/EMCON（影响球形范围与暴露）、`V` VIS 通道组开关、`I` IR 通道组开关、
  `E` ELINT 接收机开关、`Q` IFF 询问选中目标（2 s 冷却）。
- 时间：暂停时 `STEP` 不推进；播放时按倍率以 0.25 s 子步推进 V2 模型（状态机真实 step）。

## 5　HUD（1920×1080，V1 风格）

- 左：`TARGETS` 6 行（选中高亮、距离、TWS 状态、quality）+ 操作提示。
- 右：`SELECTED` 详情（range/geom、RCS/R_eff、illum、TWS/quality/update rate、VIS/IR、IFF、emitter、transponder/说明）。
- 下左：`TWS STATE MACHINE` 六态 chips（计数）+ 6 通道行（slot/target/state/q/age/lost）。
- 下中：`EVENT LOG` 事件时间线（TWS 状态迁移/失锁/火控、光学状态、IFF、ELINT、暴露；自动截断）。
- 下右：`SENSORS`：RADAR ON/EMCON、EXPOSURE（ELINT ≤45,000 km / fix %）、ELINT RX、
  VIS/IR 全局通道与锁定计数、ELINT SIGNALS、IFF 最近询问。
- 3D 投影标签：目标名+状态（碰撞避让）、`SPHERICAL SEARCH · R_eff … km`、`TRACK RING … km`、
  `VIS BORESIGHT` / `IR BORESIGHT`。
- 页脚：`V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17` + 数据源说明。

## 6　截图钩子

```powershell
$godot = ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
# 视图：overview / tws / optical / elint；自动预热到可观察状态后暂停
$env:DSH_SX_SHOT="D:\GHOST TRACK_APSIS\mockups\sensor-overview.png"
$env:DSH_SX_VIEW="overview"
& $godot --path .\sensor_explorer
# 可选：DSH_SX_TIME=<s>、DSH_SX_SPEED=<1|10|100|1000>、DSH_SX_PAUSE=1
```

各视图预热时间：overview = 80 s；
tws = 200 s（6 通道：T1/T2/T6 FC、T3/T5 ACQ、T4 已失锁并重捕为 DET / lost_lock_count=1；
事件时间线含 SRCH→DET 重捕与失锁）、
optical = 120 s（VIS T1 locked / IR T6 locked；T3 VIS 阴影 lost 已在时间线）、
elint = 55 s（IFF friend/no_reply/out_of_range + ELINT 信号截获）。
截图窗口 1920×1080，`frame>=36` 保存并退出。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\sensor_explorer --script res://tests/sensor_explorer_probe.gd
# 末行 SENSOR EXPLORER PROBE PASS；退出码 0；日志 tests/sensor_explorer_probe.log
```

probe 覆盖：型号记录（YW-R9/MS-OT2/CH-IR2/MK-12/ELINT）；R_eff=30,000 km、RCS^0.25、干扰因子；
6 TWS 通道 + 六态序列 + FC quality/更新率；目标移出后 `lock_lost`/释放 + 返回重捕；
VIS 凝视锁定/进度 100%/L3；IR 4 s 锁定；VIS 阴影 lost/shadow 且 IR 不受影响；
IFF friend / faulty_transponder / no_reply / wrong_code / out_of_range + 「不明≠敌意」；
ELINT 截获信号（produces_contact=false/仅方位/特征码）、静默收不到、超距收不到；
JSON 可序列化；同输入两次 TWS 运行结果一致。

`--headless --path .\sensor_explorer --quit` → 无 SCRIPT ERROR，打印
`[SX] boot t=0.0 radar=true targets=6 tws_ch=5`（t=0 时 T4 在球外 → 5 通道，符合脚本轨迹）。

## 8　未完成 / 边界

- 技术演示场景：本舰固定、目标为脚本线性/振荡轨迹（非 V17 关卡实体）；HUD 已明示非 V17 权威模型。
- 球形范围按基准 RCS 10 m² 画单一球；每个目标另有自己的 R_eff（HUD 选中详情显示），未为每个目标画独立球（避免视觉爆炸）。
- 3D 目标状态环为世界水平面环（屏幕投影近似），HUD 另有屏幕空间六态短环；不是严格面向相机的公告板。
- IFF 仅演示询问/应答状态与 2,000 km 限制；未做 IFF 数据库/敌我判定逻辑（不明不自动判敌，符合 05 §S-06）。
- ELINT 只给方位线；未做多信号测向交叉定位（05 §S-05 说需与航迹按方位相关，留给后续）。
- 时间倍率影响 V2 模型步进；1000× 下事件日志刷新很快（自动截断 80 条 / HUD 显示 8 条）。
- 相机为环绕焦点相机；未做地形/遮挡碰撞；参考面为示意，不画真实地球弧（避免混合 L1 局部系与地心系）。
