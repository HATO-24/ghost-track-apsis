# SENSOR EXPLORER · 雷达 / 光电 / IFF / ELINT / EW 独立技术演示

> 任务 SENSOR-EXPLORER-1（task-60）→ **R5-DEMO-1（task-93）升级**。工程 `sensor_explorer/`；V1 线框视觉。
> 本演示**只读调用** V2 传感器模型，不改 `sim/*.gd` / `scripts/sensor_model.gd` / `project.godot`；
> 光学/IR 与信息作战使用 **vendored V2 模型**（`ui/sx_optical_ir.gd` / `ui/sx_information_warfare.gd`，
> 与 game_v17 的 `V2OpticalIRChannel` / `V2InformationWarfare` 同源，独立 exe 自包含）。
> HUD 固定标注 **`V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17`**。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `sensor_explorer.gd` | Node3D 场景：本舰 + 6 目标 + 球形雷达球/参考面 + TWS 目标环 + 光学视锥 + ELINT 方位线；相机/时间/选择/IFF/ELINT/EW/截图 |
| `sensor_explorer.tscn` | Node3D + Camera3D + MeshInstance3D + CanvasLayer/HUD（引用 `ui/sx_hud.gd`） |
| `ui/sx_hud.gd` | V1 HUD：目标列表、选中详情、**OPTICAL/IR 完整通道**、**IFF/ELINT/COMINT**、**EW/INFO OPS**、TWS 六态、事件时间线、传感器状态、时间/倍率；页脚诚实标注 |
| `ui/sx_optical_ir.gd` | vendored `V2OpticalIRChannel`（FOV/IFOV/遮挡/光照/SNR/凝视/锁定；与 game_v17 同源） |
| `ui/sx_information_warfare.gd` | vendored `V2InformationWarfare`（IFF/ELINT/COMINT/EW 事件总线；与 game_v17 同源） |
| `tests/sensor_explorer_probe.gd` | headless probe：旧雷达/TWS/光学/IFF/ELINT 回归 + 新 optical_ir + information_warfare（单次） |
| `docs/sensor_explorer.md` | 本文件 |
| `mockups/sensor-overview.png`、`sensor-tws.png`、`sensor-optical.png`、`sensor-elint.png`、`sensor-ew.png` | 5 张 1920×1080 截图 |

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


---

## 9　R5-DEMO-1：完整光学/IR + 信息作战升级

> 任务 task-93。只改 `sensor_explorer.gd`、`ui/*`、`tests/*`、`docs/*`、`mockups/`；
> 未改 `sim/*` / `project.godot` / game_v17；未 commit。

### 9.1　模型来源（vendored，独立 exe 自包含）

- `ui/sx_optical_ir.gd` = `V2OpticalIRChannel`（game_v17 task-86）的字节级 vendored 副本，仅把
  `Types` 预加载路径改为 `res://sim/sensor_types.gd`；`sensor_explorer` 独立项目可直接 `preload`，
  打包进 pck，无需外部 game_v17 文件。
- `ui/sx_information_warfare.gd` = `V2InformationWarfare`（game_v17 task-75）的 vendored 副本，同样只改类型路径。
- `sim/optical.gd`、`sim/{radar,tws,sensor_types}.gd` 与 `scripts/sensor_model.gd` **未修改**；
  旧 probe 回归段落仍直接验证它们（保留旧路径回退/对照）。
- 两 vendored 文件头部保留原 schema/公式；同步规则：game_v17 模型更新时手工同步这两个副本
  （本任务不引入构建时依赖外部目录）。

### 9.2　光学 / IR（HUD `OPTICAL / IR CHANNELS`）

- 演示主通道：`VIS T1`（12,000 km，约 90 s 预算内锁定 → L3 + classification）与
  `IR T6`（1,501 km → 4 s 锁定 → L1，不分类）。
- HUD 显示：backend=`optical_ir`、status/progress/level、FOV/IFOV_eff、SNR(含 min_snr 对照)、
  illum、boresight/off-axis、occluded、N_px、reason（fov_miss/occluded/too_dark/blurred/low_snr/…）。
- 3D 视锥半角来自真实 `fov_deg/2`，方向来自 `boresight_deg/el`（不再是固定 2°/3.2°）。
- 目标速度按脚本 range_rate/bearing_rate 换算；为避免 1 µrad IFOV 下脚本角速度必然
  `blurred`（真实物理），演示轨迹的 bearing_rate 降至 0.00001°/s；range_rate 保留 km/s 量级。
- T3 仍用目标 `illum=0.02` 表达阴影；新光学模型对 T3 VIS 判 `too_dark`，IR 仍可工作
  （演示只主开 T1/T6 通道，避免同视轴多目标抢占）。

### 9.3　信息作战（HUD `IFF / ELINT / COMINT` + `EW / INFO OPS`）

- `V2InformationWarfare` 真实 step；observer=`SX-01`，2 个 ELINT 站（A 原点 / B 5000 km），
  目标携带 IFF transponder/codes、雷达 emissions、COMINT comms。
- 脚本 IFF 时间线：T6@8 s（friend）、T1@12 s（out_of_range，12,000>2,000）、T2@20 s（no_reply）、
  T4@34 s（faulty）、T5@46 s（captured）；`Q` 可询问选中目标；所有结果 identity 仅
  friend/unknown，**无 hostile/自动判敌**；HUD 显示 friend/unknown/hostile=0 计数。
- ELINT：真实链预算截获（T2/T5 YW-R9 发射源）；单站只出信号（HUD `NO CONTACT`），
  两站 `triangulate_all` 可出 `SIGNAL FIX` 候选（HUD 计数 + 事件）；事件日志节流 8 s/源。
- COMINT：T2 加密（仅元数据/不解码）、T5 明文；HUD 显示 encrypted/decode=OFF。
- EW 时间线：t=150 s 注入 noise_jam(0.7)、comms_jam(0.5)、deception(2)、chaff(2)；
  t=152 s comms_spoof；t=160 s laser_dazzle + LWR。HUD 显示 effects 数/名称、
  radar jam/R_eff、comms latency/loss、phantom、dazzle；事件全部来自 `ew.effect` 总线。
  `X` 键手动注入 noise_jam+laser_dazzle。
- 所有 IFF/ELINT/COMINT/EW 事件在 explorer 事件日志可见；不写 TrackTable/V15，不自动判敌。

### 9.4　控制 / 截图

- 控制新增：`E` ELINT RX 开关（信息作战扫描仍按模型 refresh）、`X` 手动 EW 演示；
  `V` 重建 VIS T1 通道、`I` 重建 IR T6 通道（新 API `start_channel/stop_channel`）。
- 截图视图：`DSH_SX_VIEW=overview|tws|optical|elint|ew`；`DSH_SX_SHOT=<png>`；
  预热 `overview=80、tws=200、optical=120、elint=55、ew=165` 秒，第 36 帧保存 1920×1080。

```powershell
$godot = ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe"; $mock = "D:\GHOST TRACK_APSIS\mockups"
$env:DSH_SX_VIEW="overview"; $env:DSH_SX_SHOT="$mock\sensor-overview.png"; & $godot --path .\sensor_explorer
$env:DSH_SX_VIEW="tws";      $env:DSH_SX_SHOT="$mock\sensor-tws.png";      & $godot --path .\sensor_explorer
$env:DSH_SX_VIEW="optical";  $env:DSH_SX_SHOT="$mock\sensor-optical.png";  & $godot --path .\sensor_explorer
$env:DSH_SX_VIEW="elint";    $env:DSH_SX_SHOT="$mock\sensor-elint.png";    & $godot --path .\sensor_explorer
$env:DSH_SX_VIEW="ew";       $env:DSH_SX_SHOT="$mock\sensor-ew.png";       & $godot --path .\sensor_explorer
Remove-Item Env:DSH_SX_VIEW,Env:DSH_SX_SHOT
```

实测 5 张 `SHOT err=0`：
- `sensor-overview.png`：targets/TWS + 新 OPTICAL/INFO/EW 面板（t=80 s，VIS staring 83%、IR locked）。
- `sensor-tws.png`：TWS 六态/通道/失锁重捕（t=200 s）。
- `sensor-optical.png`：VIS T1 **locked/L3/classification**、IR T6 **locked/L1**、FOV/IFOV/SNR/遮挡全显示（t=120 s）。
- `sensor-elint.png`：IFF friend/unknown 计数、ELINT 单站无接触、COMINT 加密/明文（t=55 s）。
- `sensor-ew.png`：effects=7（noise_jam/comms_jam/deception/chaff/comms_spoof/laser_dazzle/lwr）、
  radar jam=0.70→R_eff 18,420 km、comms 21 s/loss 45%、phantom 4、dazzle=Y（t=165 s）。

### 9.5　单次 probe / 验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\sensor_explorer --script res://tests/sensor_explorer_probe.gd
# [SUMMARY] pass=78 fail=0 → SENSOR EXPLORER PROBE PASS；退出码 0
```

新增 §9/§10 覆盖：
- `ui/sx_optical_ir.gd`：默认 FOV/IFOV（VIS 0.2444°/1.0417 µrad，IR 0.7334°）、
  VIS 锁定→L3/classification、IR 锁定→L1、FOV 外 `fov_miss`、地球遮挡 `occluded`、
  角速度 `blurred`、VM JSON/不写 TrackTable；
- `ui/sx_information_warfare.gd`：IFF friend / no_reply + never_hostile、ELINT 单站
  `produces_contact=false`/≤L3、COMINT 加密仅元数据、EW noise factor=0.608、phantom=2、
  VM JSON、hostile=0、不写 TrackTable。
- 旧雷达/TWS/旧光学/IFF/ELINT/JSON/确定性段落继续通过（保留旧路径回归）。
- headless boot：`--headless --path .\sensor_explorer --quit` 无 SCRIPT ERROR，打印
  `[SX] boot ...`；未做全量回归。

### 9.6　限制 / 未完成

- 技术演示，不是 V17 权威：本舰固定、目标脚本轨迹；HUD 页脚明示
  `V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17`。
- vendored 模型是副本，需手工同步 game_v17；本任务不建立构建时共享依赖，避免破坏独立 exe。
- 光学演示只用一条 VIS + 一条 IR 通道（同 sensor 共享云台视轴）；多通道/多相机交互未做。
- IFF 目标为演示 transponder/codes；ELINT/COMINT 依脚本 emissions/comms；EW 依脚本时间线，
  非玩家自由编辑；未接 V17 bridge/state/HUD，未做打包二次验证（留 exe 打包任务）。
- 事件日志最多 80 条；ELINT 信号事件按 8 s/源节流；1000× 下仍可能刷屏。
