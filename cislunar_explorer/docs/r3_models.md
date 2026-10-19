# R3-MODEL · 可见站体 / 港口 / 舰船线框几何

> 任务 R3-MODEL-1（task-64）。工程 `cislunar_explorer/`；V1 线框视觉。
> 本任务只做**视觉几何**：不改 `sim/cislunar_model.gd`、不实现碰撞/对接物理（留给 R4/R6）。
> 站体/港口位置仍来自 `sim/cislunar_model.sample(t)`；舰船为技术演示船，位置相对真实港/站做视觉偏移。

## 1　文件

- `explorer.gd`：新增 R3 几何系统（`_draw_station_model` / `_draw_port_model` /
  `_draw_lunar_station_model` / `_draw_ship_model` + 线框工具），LOD、站体聚焦、舰船对象、模块信息 vm。
- `ui/ce_hud.gd`：对象列表扩容（17 对象）、`MODULES / PORTS` 模块与端口面板、图例/控制提示更新。
- `docs/r3_models.md`：本文件。
- `mockups/cislunar-station.png`、`mockups/cislunar-ship.png`：截图（1920×1080）。

## 2　几何（全部 1px ImmediateMesh 线段，无贴图）

### 2.1　L1–L5 站（`kind=l_station`）
模块化线框，视觉总长 ~2.8 units（1 unit = 1,000 km）：

| 模块 | 线框表现 |
| --- | --- |
| 核心舱 CORE | 沿轨道切向的圆柱线框 + 3 道肋环 |
| 居住舱 HAB×2 | 左右并联圆柱 + 连接短舱 |
| 推进储罐 TANK×2 | 上方双圆柱 + 端盖圆 |
| 对接桁架 TRUSS | 横向四弦杆 + 竖杆/斜撑（6 段） |
| 太阳翼 SOLAR×2 | 桁架两端各 2 块网格面板（3×2 格） |
| 散热板 RADIATOR×2 | 上方两块网格面板 |
| 通信桅杆 COMMS | 垂直桅杆 + 抛物面天线（圆 + 三辐条 + 馈线） |
| 停泊港 DOCK×2 | 两端对接环（圆 + 4 个系泊爪）+ 停泊小舱段 |

### 2.2　地球港 / 月球港（`kind=port`）
系泊平台环（外环 + 内环 + 8 辐条）、中央信标塔（圆柱 + 信标盒 + 4 根天线）、
推进剂储罐 ×2、外伸系泊臂 ×2（带端部缓冲环与 3 根系泊爪）、
航道（两条平行引导线 + 3 个人字标记 + 4 个航道灯标十字）。

### 2.3　月球低轨/极轨站（`kind=lunar_station`）
小型模块 ~1.1 units：核心舱圆柱、电池组 ×2、太阳翼 ×2、姿控推进、通信天线；
轨道圈沿用原 `_add_orbit_ring`（倾角来自模型 station.orbit.inclination_deg）。

### 2.4　舰船（新增对象，`kind=ship`，3 艘 / 3 种尺度）
| 对象 | 视觉长度 | 模块 |
| --- | --- | --- |
| `ship_freighter` HAZE-1 补给船 | ~2.6 units | 长舰体 + 3 货舱 + 双推进段/喷管 + 舰桥 + 通信桅杆 + 侧散热板 |
| `ship_corvette` KESTREL 巡逻舰 | ~1.9 units | 收束舰艏 + 双推进段 + 任务舱 + 传感器桅杆/天线 + 侧散热板 |
| `ship_tug` 月港拖船 S-03 | ~1.2 units | 短舰体 + 双推进段 + 拖曳绞盘 + 驾驶舱 + 桅杆 |

舰船位置（每帧由真实模型位置重算，但**不是 sim 航迹**）：
- HAZE-1：地球港外泊位偏移（+0.80 径向 / +0.42 切向 / +0.22 上）；
- KESTREL：L1 站附近驻留（切向 4.2 / 上 0.9 / 向地 0.6）；
- 月港拖船：月球港泊位偏移。
HUD 选中详情注明「视觉模型（非实体尺寸）」「技术演示船 · 位置相对地球港（视觉偏移，非 sim 航迹）」。

### 2.5　LOD / 可见性
- 相机距离 <55 units：画完整模块（近距截图/近距观察）。
- 距离 ≥55 units：画简化剪影（舰体/桁架梁/太阳翼板/mast），保证全景点仍可见而非单点。
- 所有模块共享站体本地坐标：fwd = 轨道切向、up = 场景天顶、right = fwd×up（`_model_axes`）；
  港口/舰船按同一坐标系定向。

## 3　HUD / 交互

- 对象列表从 14 → **17**（新增 3 艘舰船；原有 14 对象不变），列表高度/行高调整以容纳。
- 右侧新增 `MODULES / PORTS` 面板：选中站体/港口/月轨站/舰船时显示模块列表（两列）、
  端口（DOCK-A/B、BERTH-…）、视觉尺度说明、状态（NOMINAL / DOCKED / STATION KEEPING）。
- 选中信息 `RADIUS` 行改为「站体模型 · 轨道 … km」/「港口平台（视觉模型）」/「视觉模型（非实体尺寸）」，
  避免把视觉几何冒充实体半径。
- 相机：
  - `1` 地球焦点 · `2` 月球焦点 · `3` L1 焦点 · `4` 选中焦点 · `F` 循环焦点
  - **`5` L1 站聚焦（近距 9 units）** · **`6` 舰船聚焦（HAZE-1，8.5 units）** · **`7` 地球港聚焦（8 units）**
  - 鼠标拖拽/滚轮/右键平移不变；TAB 循环选择；R 重置；SPACE 暂停；-/= 时间倍率不变。
- 时间控制/自由相机/原有 14 对象/`sample(t)` 位置驱动均保持。

## 4　截图

```powershell
$godot = ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
# L1 站模块近距
$env:DSH_CE_SHOT="D:\GHOST TRACK_APSIS\mockups\cislunar-station.png"
$env:DSH_CE_VIEW="station"; $env:DSH_CE_PAUSE="1"
& $godot --path .\cislunar_explorer
# 舰船（HAZE-1 补给船，地球港泊位）
$env:DSH_CE_SHOT="D:\GHOST TRACK_APSIS\mockups\cislunar-ship.png"
$env:DSH_CE_VIEW="ship"; $env:DSH_CE_PAUSE="1"
& $godot --path .\cislunar_explorer
```

可选 `DSH_CE_VIEW=port|overview|earth|moon|l1`；`DSH_CE_TIME / DSH_CE_SPEED / DSH_CE_PAUSE` 保持原有钩子。
截图 1920×1080，第 36 帧保存并退出。

## 5　验证

- `godot --headless --path cislunar_explorer --quit`：无 SCRIPT ERROR，
  打印 `[CE] boot ... objects=17`（14 原有 + 3 舰船）。
- 截图 `[CE] SHOT (1920, 1080) err=0`。

## 6　限制 / 未完成

- 严格视觉层：无碰撞体/对接物理/停泊约束；舰船位置为相对港/站的视觉偏移，不是 sim 航迹。
- 视觉尺度（units）与实体物理尺寸无关；HUD 已明确标注「视觉模型 / 非实体尺寸」。
- LOD 只有两级（完整模块 / 简化剪影），未做多级渐隐/屏幕尺寸自适应；远景站体仍较小。
- 模块几何是程序化手写线框，不是 CAD/外部模型；没有贴图、没有 PBR、没有后处理（V1 要求）。
- 地球/月球本体仍为线框球 + 目标环，未做地表/城市/纹理；港口平台为示意结构。
- 未做站体内部/舱段选择、模块级状态灯；模块列表为静态说明（后续 R4/R6 可接物理状态）。
