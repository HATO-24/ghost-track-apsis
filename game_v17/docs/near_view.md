# V1 HUD NEAR VIEW（方案B-34 task-210）

## 文件 / 入口

- 新 `scripts/ui/near_view.gd`（Node，管理 SubViewport 3D）。
- V1 HUD 右侧 SENSOR CONTROLS 新增 `NEAR / 近景`；弹层标题 `近景 / NEAR VIEW · SubViewport 3D`。
- 环境变量截图：`DSH_V1_VIEW=near`、`DSH_NEAR_SUBJECT=earth|moon|facility`、`DSH_V1_SELECT_FACILITY=1`。

## 3D 内容

- SubViewport：`own_world_3d=true`、1280×720 动态尺寸、`UPDATE_ALWAYS`；Camera3D + DirectionalLight3D + OmniLight3D 补光 + WorldEnvironment；SubjectRoot 缓慢自转 0.16 rad/s。
- 依赖既有模型：`models/earth.tscn`、`models/moon.tscn`、`models/station_model.gd` / `l1_port` / `otc_satellite` / `fuel_tank_farm`。
- 纯色 StandardMaterial3D；无贴图；不接物理/truth 位置。

## 设施类型映射

- 可切换 8 类：`station / depot / port / otc / tank / fuel / relay / research`（footer 两行按钮）。
- station_model 映射：station→port、relay→otc；其余同名；其它 facility class 映射 port/depot/tank/research。
- 选中设施：从当前 contact 的 `facility_class / facility_name / facility_id / facility_radius_km` 推导；无选中设施默认 L1 PORT。
- 尺度：`station_scale=1.15 × clamp(radius_km/2.0,0.70,1.50)`；缺 radius 用 1.15。
- 2D 叠加：SUBJECT / NAME / FACILITY CLASS / MODEL / MODEL TYPE / SCALE / RADIUS / SOURCE / MATERIAL；右侧显示 facility ID/CODE/TYPE/STATUS；明确 `PURE COLOR / PROCEDURAL`、`NO TEXTURE · NO PHYSICS TRUTH`。

## 截图

- `mockups/v1-hud-nearview-1920.png`（EARTH）
- `mockups/v1-hud-nearview-facility-1920.png`（选中设施，实际 facility class/模型）
- 1600 布局检查：`mockups/v1-hud-nearview-1600.png`

## 边界

- 模型资产为低模程序化基础材质；非最终美术/贴图/法线/LOD。
- 近景是 UI 展示，不读实体 truth 位置、不写 world/physics。
- 设施类型为 UI 切换/选中推导，不代表 world 中当前位置。
- 不改核心；未跑全量 regression。
