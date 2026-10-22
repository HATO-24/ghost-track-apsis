# 3D 模型资产 / MODEL PREVIEW（方案B-32 task-205）

## 1. 文件

| 文件 | 内容 |
|---|---|
| `models/planet_model.gd` | 程序化行星：SphereMesh + StandardMaterial3D + 可选经纬网/大气壳 |
| `models/earth.tscn` | Earth 预制：radius=1.25（真实 6371 km），低饱和蓝绿，经纬网 |
| `models/moon.tscn` | Moon 预制：radius=0.34（真实 1737 km），灰色，经纬网 |
| `models/station_model.gd` | 程序化空间站：圆柱/环面/箱体/太阳能板组合 |
| `models/l1_port.tscn` | L1 港：port 变体，scale=1.55，modules=4 |
| `models/otc_satellite.tscn` | OTC 卫星：otc 变体（碟形天线/环/板），scale=1.35 |
| `models/fuel_tank_farm.tscn` | 燃料储罐区：fuel 变体（三罐/管线/基座），scale=1.25 |
| `scripts/ui/model_preview.gd` | 预览场景：正交相机、方向光/补光、旋转展示、DSH_SHOT 截图 |
| `model_preview.tscn` | 预览入口场景（直接 `res://model_preview.tscn`） |
| `mockups/models-earth-moon-stations-1920.png` | 1920×1080 预览截图 |

## 2. 材质 / 几何

- 全部程序化、本地生成；**无贴图、无外部下载**。
- 行星：`StandardMaterial3D` 纯色（Earth 低饱和蓝绿、Moon 灰）；透明大气壳；`ImmediateMesh` 经纬线（无贴图）。
- 空间站：低饱和 hull 灰、accent 青绿、solar 深蓝、amber 储罐顶；`CylinderMesh`/`TorusMesh`/`BoxMesh`/`SphereMesh`（hemisphere dish）。
- 尺度：Earth/Moon 半径比例 6371:1737 ≈ 1.25:0.34（场景单位）；空间站真实尺度不进入地球半径换算，预览按可读性缩放。
- 无 PBR 贴图/法线贴图；GL Compatibility 可运行。

## 3. 参数

- Planet：`body_name`、`radius`、`base_color`、`grid_color`、`atmosphere`、`grid_lines`。
- Station：`station_type`（depot/port/otc/tank/fuel/research）、`station_scale`、`module_count`。
- 变体：L1Port（port）、OTCSatellite（otc）、FuelTankFarm（fuel）；新增变体只需新 tscn 设同一脚本参数。

## 4. 预览

- 正交相机 `size=8.2`，位置 (1.15,2.8,11.0)，look_at (1.15,0.05,0)；方向光 + 冷色补光；ShowcasePivot 缓慢 yaw 0.06 rad/s。
- 截图：`DSH_SHOT=... DSH_HUD_SIZE=1920x1080` 运行 `res://model_preview.tscn`；40 帧后写 PNG 并退出。
- headless 验证：`--headless res://model_preview.tscn --quit-after 5`，打印 `loaded=5 failed=0 errors=[]`。

## 5. 未来替换点 / 边界

- 替换点：保留 root Node3D 与参数，直接替换 `MeshInstance3D.mesh`/`material_override` 或换高模 tscn；预览/参数不变。
- 当前不含：贴图、法线/粗糙度贴图、LOD、碰撞、动画、真实尺度装配、HUD/物理接入。
- 预览仅资产展示，不写 world/session/V15。


---

## B-36：ISS/天宫参考空间站重做（task-213）

- 参考：天宫 T 字构型（核心舱约 16.6m×4.2m、节点舱多向对接、两实验舱、太阳翼、暴露平台）；ISS 桁架 backbone、散热器、太阳能翼、对接端口/气闸。仅供结构与比例参考，不复制现实实体。
  - https://www.nasa.gov/international-space-station/
  - https://www.esa.int/Science_Exploration/Human_and_Robotic_Exploration/International_Space_Station
  - https://orbitalradar.com/satellites/css-modules
- `station_model.gd` 结构函数：
  - `_core_and_node`：中央圆柱核心舱 + 节点舱 + 径向/端部对接环；
  - `_module`/`_lab_radial`：实验舱（T 字/径向）；
  - `_truss_x`：沿 X 的桁架（四根纵梁 + 横梁 + X 斜撑）；
  - `_solar_wing`：分段太阳翼 + 边框 + 中轴；
  - `_add_radiator`：散热器板 + 加强筋；
  - `_docking_port`：对接环/端口；另含气闸/天线/推进舱。
- 6 类差异：
  - port：大核心 + 节点舱 + 两向实验舱 + 端部太阳翼 + 多对接口 + 散热器；
  - depot：核心 + 长桁架 + 货舱/储罐 + 太阳翼 + 加注管；
  - otc：核心柱 + 转台 + 碟形天线 + 相控阵 + 太阳翼；
  - tank：桁架基座 + 多圆柱罐 + 管线 + 对接环；
  - fuel：储罐 + 两段加注臂/喷嘴 + 软管 + 对接；
  - research：实验舱 + 暴露平台/载荷框 + 散热器 + 太阳翼。
- 尺度：场景单位 stylized；`station_scale` 控制整体；核心/实验舱/罐体采用人类站体比例圆柱与舱段，不再方块堆。真实 16.6m 尺度只作参考，不进入物理换算。
- 材质：`StandardMaterial3D` 纯色低饱和 hull/accent/solar/radiator/amber/dark；无贴图、无外部下载。
- 预览：`DSH_PREVIEW_VIEW=stations` 运行 `res://model_preview.tscn`，显示 6 类并截图；默认预览仍为 Earth/Moon + 3 站。
- 截图：`mockups/models-stations-ref-1920.png`（6 类）、`mockups/v1-hud-nearview-facility-1920.png`（NEAR VIEW 选中 Chronos/depot 重截）。
- headless：`DSH_PREVIEW_VIEW=stations` 加载 6/6 成功，`failed=0 errors=[]`。

### 边界

1. 过渡资产：结构参考现实站，但不是现实实体复刻；无贴图/法线/LOD/碰撞/真实质量分布。
2. 近景为 UI 展示；不接物理/truth；不做近景构件交互。
3. 尺度为展示比例，非真实米制装配。


---

## B-37：大型居住站（奥尼尔/斯坦福，task-214）

依据 `docs/44_新剧本_2193.md` 第 51 行：
- 大型站采用奥尼尔双圆柱（长 30 km、直径 7.5 km，约 2 分钟一圈）；
- 或斯坦福环面（直径 1.8 km，容量 1–14 万人）；
- 仅明确小型站点继续传统模块站。

### 模型

- `models/habitat_model.gd`：程序化居住站；纯色 StandardMaterial3D、无贴图、视觉旋转示意。
- `models/oneill_cylinder.tscn`：
  - 两根反向旋转圆柱（场景长 4.0 / 直径 1.0 对应 30:7.5 的 4:1 比例）；
  - 端盖/轴承/对接环、轴向对接枢纽、窗带/陆地带/散热条、太阳翼/电站、端部散热片。
- `models/stanford_torus.tscn`：
  - 直径 1.8 的环面、6 根轮辐、中央枢纽、对接端口、镜面/太阳翼、维护环；环体旋转示意。
- 旋转仅视觉，不接物理；场景尺度为展示比例，真实 km 设定见文案/文档，不进入物理。

### 映射（FacilityModelFactory）

- `L5-07 Savannah` / `L5-01 Eko` / `L3-01 Aurora` → `oneill`。
- `NESOSS-05 Saturnus` → `stanford`。
- 其它小型 station/port/depot/otc/tank/fuel/research → 现有模块站。
- `describe/create` 输出 `model_family=habitat|module_station`、`habitat_type`、`habitat_known`、`habitat_fallback`、`habitat_scale`。
- 未知大型居住/生态站（residential/tourism/agricultural/habitat 且 radius≥2.0）：按半径 fallback（≥3.2 → oneill，否则 stanford），标注 fallback。

### 预览 / 截图

- `DSH_PREVIEW_VIEW=habitats` 运行 `res://model_preview.tscn`，显示 2 个居住站（loaded=2 failed=0）。
- `mockups/models-habitats-lore-1920.png`：双圆柱 + 斯坦福环面、窗带/陆地带/轮辐/镜面/太阳翼。
- `mockups/v1-hud-nearview-savannah-1920.png`：NEAR VIEW 选中 L5-07 Savannah，显示 `habitat_model.gd / oneill`、ID/CODE、habitat mapping。
- FacilityModelFactory probe 仍通过：`checks=1697 fails=0 fallbacks=0`（110 设施）。

### 边界

- 过渡资产：结构/比例参考设定，不复制现实实体；无贴图/法线/LOD/碰撞/真实质量或转速物理。
- 近景/预览为 UI 展示；不写 world/session；真实尺寸只在文案/比例中标注。
