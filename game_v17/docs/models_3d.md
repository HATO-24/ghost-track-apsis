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
