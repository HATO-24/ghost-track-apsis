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


---

## B-38：A Baoa Qu 式小行星居住站 + CDE/SFHD 舰船（task-217）

参考（仅作结构/工业感参考，不复制现实/高达/游戏资产）：
- A Baoa Qu：小行星带内拖到 L2，双体小行星（盘+锥）接合、中央塔；Solomon/Luna II 同类；
- Children of a Dead Earth：模块化舰体、燃料罐、散热器、轨道炮/激光、Whipple/多层装甲；
- Spacefleet: Heat Death：硬科幻工业感、外露散热/推进/武器。
- https://store.steampowered.com/app/476530/Children_of_a_Dead_Earth/
- https://store.steampowered.com/app/4388640/Spacefleet_Heat_Death_Prometheus_Demo/

### 小行星居住站

- `models/asteroid_habitat_model.gd` + `asteroid_oneill.tscn` / `asteroid_stanford.tscn` / `asteroid_fortress.tscn`。
- 结构：双体低模小行星外壳（不规则椭球/双体接合/陨石坑/暗色陨坑）、切面开口环+框梁、中央指挥塔、系泊塔、推进模块/喷口、散热鳍、太阳翼、对接口；拖曳改造结构痕迹。
- B-38 原型曾在此嵌入 O'Neill/Stanford 内部结构；**该拼合已在 B-40 撤销**。B-40 起四类空间站独立并存，小行星居住站只保留民用隧道/小舱段，不再塞入 O'Neill/Stanford。
- B-40 类型：民用 `asteroid_habitat` 与军用 `asteroid_fortress` 各自独立场景；见下节。
- 纯色 StandardMaterial3D；无贴图；尺度为展示单位，非真实 km。

### 舰船

- `models/ship_model.gd`：主轴舰体、反应堆/推进簇、燃料罐、外露散热器阵列、轨道炮/激光/导弹舱、传感器桅杆、装甲板/Whipple 板；参数 `ship_class / ship_role / ship_size / radiator_count / weapon_fit / faction`。
- 变体映射：`variant_for()` / `variant_specs()` 覆盖友军 8 型 + 敌军 24 型（含 BB/CA/CL/DD/FF/AV 与 STD/ASSAULT 参数差异）；预览选取 14 个代表变体（8 友军 + BB/CA/CL/DD/FF/AV）展示。
- 纯色基础材质，无贴图；不是物理模型。

### 截图 / 验证

- `mockups/models-asteroid-habitats-1920.png`：B-38 原型拼合预览（历史）。
- `mockups/models-ships-hardscifi-1920.png`：14 变体；14/14 加载。
- `mockups/v1-hud-nearview-savannah-1920.png`：B-40 起为独立 O'Neill，见下节。
- 近景对选中舰船：自动 `ship_model.gd`（无需改 v1_hud）；无选中设施时默认 L1 PORT。
- 既有 FacilityModelFactory probe 仍 `checks=1697 fails=0`（110 设施）。

### 边界

- 过渡资产；外壳/舰体为程序化低模；无贴图/法线/LOD/碰撞/真实质量/热/推进物理。
- 不复制现实/高达资产；旋转仅视觉。
- 不写 world/session；近景/预览只读。


---

## B-40：四类空间站独立拆分 + 人口/功能自动匹配（task-220）

### 四类独立模型族

| 族 | 场景/脚本 | 结构 |
|---|---|---|
| O'Neill 双圆柱 | `oneill_cylinder.tscn` + `habitat_model.gd` | 30:7.5 双圆柱、端盖/轴承/对接枢纽、窗带/陆地带、太阳翼 |
| Stanford 环面 | `stanford_torus.tscn` + `habitat_model.gd` | 1.8 直径环面、轮辐、中央枢纽、镜面/太阳翼 |
| 小行星居住站 | `asteroid_habitat.tscn` + `asteroid_habitat_model.gd` | 双体岩壳/切面/隧道/小舱段/对接/太阳能/散热；**无 O'Neill/Stanford 内部** |
| UEG 小行星要塞 | `asteroid_fortress.tscn` + `asteroid_fortress_model.gd` | 双体小行星、中央指挥塔、炮塔/轨道炮/导弹舱、机库、装甲、系泊；不是民用站 |
| 小型模块站 | `station_model.gd` | 现有 depot/port/otc/tank/fuel/research/small station 模块基型 |

- 四类场景互不拼合/替代；旧 `asteroid_oneill.tscn` / `asteroid_stanford.tscn` 为 B-38 历史文件，B-40 factory 不再使用。

### 匹配规则（FacilityModelFactory）

1. `habitat_profiles.json` known 档案优先（Savannah/Eko/Aurora → oneill；Saturnus → stanford；Victoria → asteroid_habitat；Horizon → asteroid_fortress）。
2. military function/transponder → asteroid_fortress。
3. 小型模块 class（station/port/depot/otc/tank/fuel/relay/research/commercial/industrial/...）→ module_station。
4. 其它按人口阈值：≥200000 → oneill；10000–199999 → stanford；<10000 或 resources=low → asteroid_habitat。
5. 输出 `model_family / family_reason / population / resources / function / profile_source`。
- 全 110 设施当前匹配：oneill=3、stanford=1、asteroid_habitat=1、asteroid_fortress=1、module_station=104（probe 读取）。

### 预览 / 近景截图

- `mockups/models-habitats-four-families-1920.png`：O'Neill / Stanford / Asteroid Habitat / UEG Fortress 四类同框（loaded=4）。
- `mockups/v1-hud-nearview-savannah-1920.png`（O'Neill）、`v1-hud-nearview-eko-1920.png`（O'Neill）、`v1-hud-nearview-aurora-1920.png`（O'Neill）、`v1-hud-nearview-saturnus-1920.png`（Stanford）、`v1-hud-nearview-asteroid-1920.png`（L5-11 Victoria 民用小行星）、`v1-hud-nearview-fortress-1920.png`（L2-07 Horizon UEG 要塞）。
- 均 SHOT err=0；near view 通过 `DSH_NEAR_FACILITY_ID` 选择设施，family/reason 在信息面板显示。

### 边界 / 待确认

- 人口/资源/功能档案为**视觉匹配元数据**，不是 gameplay 人口模拟；阈值不改变游戏经济/物理。
- 已知 6 个大型站/示例按设定；其余 104 为模块小站；若需要更多 O'Neill/Stanford 站，需补 `habitat_profiles.json` 的已知人口/资源数据。
- 纯色程序化过渡资产；无贴图/LOD/碰撞/热/推进物理；不复制现实/高达资产。
- 不写 world/session；未跑全量 regression。完成后按用户要求停止，等待复核。


---

## B-41：O'Neill Island Three 双圆柱回炉（task-221）

参考公开结构：O'Neill Island Three 双圆柱反向旋转，约 8 km 直径 × 32 km；游戏设定 7.5 km × 30 km，保持约 4:1。仅作结构参考。

### 结构

- `models/oneill_model.gd`（新）+ `models/oneill_island3.tscn`：
  - 双圆柱（场景 LENGTH=4.4、RADIUS=0.55 的 4:1 归一化展示尺度）；两根反向旋转；
  - 每根 3 条纵向窗带 + 3 条陆地带交替：窗带为**半透明浅蓝曲面面板**（非绿色方盒条纹），陆地带为曲面地形带 + 低模丘陵；
  - 圆柱外侧 3 组大型反射镜 + 支臂，将阳光导入窗带；
  - 两端端盖、轴承环、轴向对接枢纽；双柱端部通过轴承/桁架连接；
  - 至少一根圆柱（A）带纵向切面开口，内部可见弧形陆地带/丘陵/端部山体/云层/中央照明轴；
  - 外部散热器、电站、系泊塔、交通艇接口。
- `habitat_model.gd` 的 oneill 分支改为委托 `oneill_model.gd`；旧“绿色条纹方盒”实现已移除。Stanford 分支保持独立。
- `oneill_cylinder.tscn` 仍使用 habitat_model（B-40 factory 兼容）；`oneill_island3.tscn` 直接使用 oneill_model 供预览/新引用。

### 预览 / 近景

- `DSH_PREVIEW_VIEW=oneill_island3` → `res://model_preview.tscn`，截图 `mockups/models-oneill-island3-1920.png`。
- NEAR VIEW Savannah（L5-07）重截：`mockups/v1-hud-nearview-savannah-1920.png`，显示 FAMILY=oneill、切面地形、3窗带/3陆地带、反射镜、端盖轴承。
- 均 SHOT err=0；FacilityModelFactory probe 仍 `checks=1697 fails=0`。

### 边界 / 与游戏设定差异

1. 公开 O'Neill 8×32 km 为参考；游戏采用 7.5×30 km，保持 4:1；场景为归一化展示单位，非真实 km 物理装配。
2. 窗带/陆地带为程序化曲面近似，不是真实透明玻璃/植被模拟；内部地形为低模示意。
3. 反射镜/旋转为视觉展示，不做真实光学/约 2 分钟转速物理。
4. 无贴图/LOD/碰撞/热/结构物理；不复制现实资产；不写 world/session。
5. 按用户要求完成预览/近景截图后停止，等待复核。


---

## B-43：O'Neill 内景相机/几何修正（task-223）

参考：`refs/oneill/spacecolony3.jpg`（内部大陆地/3窗带/太阳/端盖）、`refs/oneill/endcap.jpg`（端盖视角/曲面陆地/水面/天空）。
来源：https://commons.wikimedia.org/wiki/Special:FilePath/Spacecolony3edit.jpeg 等（仅参考，无贴图/无复制资产）。

### 相机 / 尺度

- 相机站在**底部陆地带近表面**：near view 内景 `pos=(0,-1.05,4.7)`、看向 `(0,-0.35,-4.8)`、FOV=80（任务要求 70–85）；近端在相机后。
- 基础内径 `RADIUS=1.55`、内长 `LENGTH=4.8`；场景沿轴 `z×2.6` 拉伸为约 4:1 的开敞比例（等效长≈12.5 / 直径3.1），避免窄管；远端端盖在画面中只占小部分。
- 远端端盖：低模草地面盘 + 中央枢纽/对接口 + 端部山丘；近端端盖在相机后。
- NEAR VIEW 默认 INTERIOR；保留 EXTERIOR（I/E 键盘切换；`DSH_NEAR_ONEILL_VIEW=exterior` 可测试），内景下禁止 subject 自动旋转，避免相机/端盖偏移。

### 几何 / 材质

- 3 陆地带（60/180/300°）+ 3 窗带（0/120/240°）交替，内壁曲面。
- 窗带半透明浅蓝（alpha≈0.34），外侧星点/太阳/太阳光斑；太阳光柱为低模半透明锥/柱，照向对面陆地。
- 陆地带贴内表面：草地/农田色块（曲面片）、水面/河流、丘陵、树（树干沿法线、树冠贴地）、小建筑（切向盒）；近景树木/建筑沿底部陆地带排布。
- 云层/薄雾：低空扁云 + 高空薄云 + 远端大气霾半透明面片；无 WorldEnvironment fog 依赖。
- 纯色/半透明 StandardMaterial3D，无贴图；程序化低模。

### 截图 / 验证

- `mockups/models-oneill-interior-v2-1920.png`（model_preview `DSH_PREVIEW_VIEW=oneill_interior`，loaded=1）。
- `mockups/v1-hud-nearview-savannah-interior-1920.png` 重截（L5-07，FAMILY=oneill；内景无自动旋转）。
- 1600 检查：`mockups/v1-hud-nearview-savannah-interior-1600.png`。
- SHOT err=0；FacilityModelFactory probe 未受影响（此前 checks=1697 fails=0）。

### 与参考图对应 / 边界

- 对应：内部曲面陆地带/水面、3 条纵向窗带透太空与阳光、光柱、远端端盖+中央枢纽、云/大气。
- 差异：低模/纯色近似，不是绘景；树/建筑/地形为简化形状；FOV/相机为展示构图；4:1 为沿轴拉伸的展示比例，不是真实 km 物理装配。
- 无贴图/LOD/碰撞/真实大气散射/约 2 分钟转速物理；不写 world/session；完成后停止等复核。


---

## B-44：O'Neill 外景重做 + 内景树方向修正（task-224）

参考：`refs/gundam/settingbook.jpg`（设定书岛三型图）+ `refs/oneill/` Commons 内景图。尺寸使用游戏设定 **30 km × 7.5 km（4:1）**，不采用设定书 32×6.4。

### A. 外景（`models/oneill_model.gd`）

- 双圆柱：场景 `LENGTH=4.4 / RADIUS=0.55`（保持 30:7.5=4:1 展示比例）；一柱完整，一柱纵向剖切，剖切面朝预览相机。
- 每柱 3 陆地带（绿/棕/灰地形）+3 窗带（半透明浅蓝），交替；窗带含纵向边框；不再用绿色方盒条纹。
- 剖切柱：外壳在朝相机方向开口，内部再画 3 内壁带 + 3 陆地带、内表面丘陵/树/小建筑（贴内壁，见 B）；开口有厚框/暗色切口衬底。
- 轴向大型镜面：每柱上方主镜 + 背侧辅镜，沿轴跨窗带长度（不是顶部 3 个小矩形），带支臂。
- 端盖：轴承环、中央轴向对接枢纽、双柱端部连接桁架/主梁；外部散热鳍/电站/系泊塔/交通艇接口。
- 预览相机 3/4 侧视：orthographic size=6.4，位置 `(5.8,2.2,8.8)`，看原点；截图 `mockups/models-oneill-exterior-v2-1920.png`。

### B. 内景树/建筑方向（`models/oneill_interior_model.gd`）

- 内表面法线 `n`（由轴心指向壁面）。树木：树根在 `p`，树干沿 **-n**（朝轴心），树冠在 `p - n*高度`；不再用 `+n`。
- 建筑/田块：底面贴 `p`，向上沿 **-n**（切向 basis 的 up=-n）；近景树/建筑同样修正。
- 端盖树：根在端盖表面，沿端盖内向 +Z 生长。
- 重截 `mockups/models-oneill-interior-v4-1920.png`（model_preview `DSH_PREVIEW_VIEW=oneill_interior`）。

### 边界 / 截图

- 外景为低模程序化、纯色/半透明材质，无贴图；剖切为视觉展示，不是真实结构切分。
- 30×7.5 为游戏设定；设定书 32×6.4 仅参考，不采用。
- 内景树/建筑/地形仍为简化几何；无 LOD/碰撞/热/结构物理。
- 截图：`mockups/models-oneill-exterior-v2-1920.png`、`mockups/models-oneill-interior-v4-1920.png`；均 SHOT err=0。
- FacilityModelFactory probe 未受影响。


---

## B-45：外景按 B 站 05:00 帧重做 + 内景树比例（task-225）

参考：B 站视频 05:00 帧（BrowserSkill 抓取）+ Commons 内景图。外景尺寸仍用游戏 **30×7.5 km（4:1）**。

### A. 外景（`models/oneill_model.gd`）

- 默认双柱**完整**，不剖切：`@export var cutaway_visible := false`；可选剖切保留但默认关闭。
- 灰白 hull（0.62/0.64/0.63），外表面不再有橙/绿宽带；每柱 3 条暗色/浅蓝纵向窗带（暗蓝 + 窄浅蓝玻璃 + 横向肋/边梁）。
- 每柱 3 片大型长镜面：沿轴跨大部分长度、斜向外布置（角度 -55°/0°/+55°），带支臂；去掉单块大平板。
- 暗色端盖环 + 中央轴向对接枢纽；双柱端部竖梁/斜撑/连接桁架；外部散热鳍/电站/系泊塔保留。
- 预览相机 3/4：ortho size=6.4，位置 (5.8,2.2,8.8)；截图 `mockups/models-oneill-exterior-v3-1920.png`。

### B. 内景树/比例（`models/oneill_interior_model.gd`）

- 树高约 0.8–1.2 倍建筑高（侧景 0.080/建筑高0.070，近景 0.082/建筑高0.070）；树冠总宽约建筑宽的 0.6–0.8（侧景 0.062/0.085，近景 0.095/0.14）。
- 树冠由 2–3 个小型团簇组成（不是单个大椭球）；树干可见、沿 **-n** 朝轴心，树根贴 p；树冠在 p - n*高度。
- 树种 3 种绿色材质变化；近景树同样；低模球段数保持程序化。
- 截图 `mockups/models-oneill-interior-v5-1920.png`。

### 边界

- 灰白 hull/窗带/镜面为纯色/半透明程序化低模，无贴图；不复制视频/现实资产。
- 端盖/桁架/镜面为视觉展示，不是真实结构承力/光学。
- 可选剖切模式未生成截图；默认外景不剖切。
- FacilityModelFactory probe 仍 `checks=1697 fails=0`；不写 world/session。


---

## B-46：O'Neill 外景单圆柱 + 3 反射板（task-226）

- 外景改为**一根完整圆柱**：场景 LENGTH=4.4 / RADIUS=0.55，保持 30×7.5 km = 4:1 展示比例；默认不剖切。
- 外壳灰白 `hull`；3 条纵向采光窗带（暗蓝 + 窄浅蓝玻璃 + 肋/边梁）+ 3 条陆地带（低饱和灰绿/灰棕/灰，不做橙/绿宽条纹）；窗带外侧为宇宙。
- **3 片大型反射板**：沿轴分三段布置，各自有角度张开（花瓣/百叶感），带支臂朝窗带；不再是单块大平板。
- 端盖：暗色环 + 中央轴向对接枢纽；外部散热鳍/电站/系泊塔/交通艇接口。
- 预览 3/4 单柱：ortho size=5.4，位置 (5.4,2.2,8.6)；标题 `SINGLE CYLINDER / 3 ANGLED REFLECTORS`。
- 截图 `mockups/models-oneill-exterior-v4-1920.png`。
- 边界：纯色/半透明程序化低模，无贴图；反射板/端盖为视觉结构，不接真实光学/承力；本任务未改内景。


---

## B-47：O'Neill 外景 v5 + 内景真实尺度（task-227）

参考：B 站视频 05:00 帧。外景仍用游戏 30×7.5 km（4:1），不采用设定书 32×6.4。

### A. 外景 v5（`models/oneill_model.gd`）

- **单根完整圆柱**：LENGTH=4.4 / RADIUS=0.55，完整不剖切；灰白 hull。
- 只有 3 条纵向暗色/浅蓝窗带；**删除所有外侧陆地带/橙绿宽条**。
- 3 片长反射板从**一端端盖环**伸出：绕轴 120° 旋转对称，沿轴从 root_x=+L/2 伸向 tip_x=-L/2，长度≈4.43（略大于圆柱），宽度 0.62≈0.56×直径；根部半径 1.08R、梢部略外张到 1.58R；根环/中段支臂。
- 端盖：大圆盘 + 暗色环 + 中央轴向对接枢纽；散热鳍/电站/系泊塔保留。
- 预览 3/4 单柱：ortho size=6.0，位置 (5.8,2.4,9.0)；标题 `SINGLE CYLINDER / 3 END-CAP REFLECTORS`。
- 截图 `mockups/models-oneill-exterior-v5-1920.png`。

### B. 内景真实尺度（`models/oneill_interior_model.gd`）

- 内景展示半径 R=1.55 对应真实 R=3.75 km，约 2419 m / 展示单位。
- 侧景树高 0.016 ≈ 38.7 m；侧景建筑 0.014–0.016 ≈ 34–39 m；端盖树 0.008 ≈ 19 m；均在 20–55 m 量级。
- 近景树高 0.024 ≈ 58 m（**近景 LOD 夸张**，非真实尺度），近景建筑 0.014–0.022 ≈ 34–53 m；树冠 2–3 个团簇、树干沿 -n 朝轴心。
- 预览说明已标注 `REAL-SCALE TREES/BUILDINGS ≈20–55 m · NEAR LOD EXAGGERATED`。
- 截图 `mockups/models-oneill-interior-v6-1920.png`。

### 边界

- 纯色/半透明程序化低模，无贴图；反射板为视觉结构，不接真实光学/承力。
- 内景山体/河流/云仍为场景级低模；近景树/建筑为 LOD 夸张，不能当作真实比例。
- 外景窗带/反射板/端盖为视觉展示；不写 world/session。


---

## B-48：O'Neill 高精度外景重做 + 删除 NEAR VIEW（task-228）

### A. NEAR VIEW 删除

- 删除 `scripts/ui/near_view.gd`、`models/oneill_interior_model.gd`、`models/oneill_interior.tscn`（后续需要再建）。
- `v1_hud.gd` 移除 NEAR 入口按钮/overlay 绘制/点击命中/输入分发/`_near_*` 数据与 `DSH_NEAR_*` 环境读取；SENSOR CONTROLS 仅保留其他入口。
- `model_preview.gd` 移除 oneill_interior/oneill_exterior/oneill_island3 旧模式；旧 near 截图仅作历史。
- HUD boot 验证：`[V1 HUD] binder boot=true errors=[] contacts=9 orders=1`，无悬空引用。

### B. 高精度单圆柱 O'Neill（`models/oneill_island3_hi.gd` + `oneill_island3_hi.tscn`）

- 尺寸 30×7.5 km（4:1）；`LENGTH=4.4 / RADIUS=0.55`。
- 外壳 **128 周向段 × 48 轴向段**；3 条纵向采光窗带（暗玻璃 + 凹框 + 9 道肋 + 边梁），3 条外壳带，外侧无陆地带。
- 外壳：环向加强环（11 道）、6 条纵向梁、分板短缝、浅色 panel 线、检修口；外部散热鳍/太阳能阵列/系泊塔/交通艇接口。
- 窗内内容（只在窗内可见）：3 条低饱和陆地/水面/云层/小微地形，外层 hull 不透明避免外露。
- **3 片长反射板**：从 +X 端盖环伸出，120° 对称（相对窗带偏 60° 避免遮挡），长≈4.4（≈圆柱长）、宽 0.62（≈0.56×直径），3 段分段板 + 长边导轨 + 横梁 + 根部转轴/桁架/中段支臂。
- 端盖：大圆盘 + 放射肋 + 中央枢纽；+X 为反射板环/转轴支撑，-X 为港口环/6 个对接口（双端不同）。
- 材质：灰白 hull、暗玻璃、低饱和陆地带、金属镜面；纯色/半透明，无贴图。
- 预览：`DSH_PREVIEW_VIEW=oneill_hi`（3/4，ortho6.0）、`oneill_hi_detail`（端盖/反射板局部，ortho2.8）。
- 截图：`mockups/models-oneill-hi-1920.png`、`mockups/models-oneill-hi-detail-1920.png`；loaded=1 failed=0。
- 工厂兼容：`oneill_cylinder.tscn` 与 `oneill_island3.tscn` 指向 hi 场景；`habitat_model.gd` oneill 委托 hi；旧 `oneill_model.gd` 删除。
- FacilityModelFactory probe 仍 `checks=1697 fails=0`。

### 边界

- 高精度仍为程序化低模/纯色材质，无贴图；不接真实光学/结构承力/热。
- 窗内陆地仅为窗内视觉内容；近景已删除，不生成 interior 截图。
- 不写 world/session；未跑全量 regression。


---

## B-49：O'Neill 外部件位置校对（task-229）

参考：设定书端盖港口图（南侧港口较小、无重力/低重力工厂）+ B 站 05:00 帧。只调整外部件挂点，不改壳体/窗带/反射板几何。

### +X / -X 分工表

| 位置 | +X 反射板端 | -X 港口/工业端 |
|---|---|---|
| 端盖 | 大圆盘 + 放射肋 + 中央枢纽 | 大圆盘 + 港口环 + 6 对接口 + 中央枢纽 |
| 反射板 | 3 片反射板根部环/转轴/支臂 | — |
| 散热鳍 | 端盖环外侧 **4 组**放射状（45/135/225/315°，避开窗带） | 端盖环外侧 **4 组**放射状（同角度） |
| 太阳能阵列 | — | 端盖环外伸 **4 组**，四象限展开（带桁架/转轴） |
| 系泊塔/泊位 | — | 端盖环 **5 个**均布，朝轴向外侧 |
| 交通艇接口/机库 | — | 中央枢纽附近 **5 个**小对接口，朝外 |
| 筒身/底部 | 无外部件 | 无外部件 |

- 移除：筒身中段散热鳍、筒身两侧/中段太阳能、筒身底部三处系泊塔、筒身中部侧向交通艇接口。
- 散热鳍与反射板/窗带不遮挡：散热鳍只在端环外侧 45/135/225/315°；反射板相对窗带偏 60°。
- 预览：`oneill_hi`（3/4）、`oneill_hi_detail`（+X 端盖/反射板局部）、`oneill_hi_outboard`（-X 港口/工业端特写）。
- 截图：`mockups/models-oneill-hi-outboard-1920.png`；同步重截 `models-oneill-hi-1920.png`、`models-oneill-hi-detail-1920.png`。
- FacilityModelFactory probe 仍 `checks=1697 fails=0`。

### 边界

- 外部件为程序化低模纯色/半透明，无贴图；散热/太阳能/系泊/交通艇接口为视觉挂点，不接真实热/电/系泊物理。
- 不改壳体几何/窗带/反射板尺寸；不写 world/session。


---

## B-50：O'Neill 反射板/系泊塔穿模修复（task-230）

### 反射板分层

- 前层：镜面板（3 段/片），不含任何横梁/贯穿臂。
- 背面层（沿板法线 -0.045）：分段边框、长边导轨、3 道横向肋；全部在镜面背面，不共面。
- 支撑：根部转轴/根部托架接 +X 端盖环；中段 2 根背支撑只连到板背面（端点 `mid + back*2.2`），不穿到前侧。
- 已取消板面中心贯穿式径向臂、正面长边/横梁；正面只有镜面与分段缝。

### 系泊塔/外部件角度表

| 部件 | 角度 | 半径/轴向 |
|---|---|---|
| 散热鳍（两端各4组） | 45/135/225/315° | 端环外侧 1.04R–1.58R，轴向端环 ±(L/2+0.16) |
| 太阳能（仅 -X，4组） | 22.5/112.5/202.5/292.5° | 根部 1.15R，板中心 1.78R，x=-L/2-0.45/-0.75 |
| 系泊塔（仅 -X，5个） | 0/72/144/216/288° | 根部 -X 端环外缘 0.98R，向 -X 伸出 0.30、外张至 1.08R |
| 交通艇/机库（仅 -X，5个） | 72°均布+0.25 | 中央枢纽附近 0.50R，朝 -X |
| +X 端 | — | 仅反射板根部环/转轴/支臂 + 4 组散热鳍 |

- 系泊塔与散热鳍（45°系）角度错开；与太阳能（22.5°系）角度/半径/轴向分层；与端口环（0.5R）半径分离。
- 移除旧筒身中段散热/太阳能、底部三处系泊、中部侧向交通艇接口。

### 截图 / 验证

- `mockups/models-oneill-hi-clean-1920.png`（正面 3/4 全貌）
- `mockups/models-oneill-hi-clean-detail-1920.png`（端盖/反射板正面特写）
- 均 SHOT err=0；FacilityModelFactory probe `checks=1697 fails=0`。

### 边界

- 层厚/角度为视觉避让，不是真实结构间隙/公差；反射板结构只在背面可见，正面无框架线。
- 外部件仍为视觉挂点，不接真实热/电/系泊物理；不写 world/session。


---

## B-51：O'Neill 反射板 25° 张开 + 连接结构（task-231）

### 几何

| 项目 | 值 |
|---|---|
| 张开角 | **25°**（相对圆柱轴，`open_rad=deg_to_rad(25.0)`） |
| 长度 | **1.06L** ≈ 4.66（L=4.4；任务需 1.0–1.1L） |
| 宽度 | 0.62 ≈ **0.56×直径**（直径1.1） |
| 对称 | 3 片，120° 旋转对称；位于 60/180/300°（避开 3 窗带） |
| 根部 | +X 端盖环外伸 standoff 0.30；root_x=+2.50，root_r=1.08R |
| 梢部 | `tip_x=2.50-1.06L*cos25≈-1.73`；`tip_r=root_r+1.06L*sin25≈2.57` |
| 分层 | 镜面为前层；全部框架/导轨/横肋/支撑在背面（法线 -0.052） |

### 连接结构（每片）

- 端盖环**双铰座/耳片**：板根横梁两端各一个铰点；端盖环耳片 + 铰座块 + 轴承壳。
- 根部**横梁/扭力管**：沿板宽（切向）跨接两端铰点，位于背面。
- **A 字背撑**：两根斜撑从端盖环（±切向偏置）汇到板背 15% 长度处。
- **两根线性作动器**：从端盖环到板背 25% 长度处；套筒+杆示意可调角，套管用 accent 色。
- **轴承壳/限位块/止挡**：根部转轴、轴承壳、限位块位于背面；正面无框架线。
- 不穿模：根部/中段支撑端点在板背；镜面前层无横梁/贯穿臂。

### 间隙规则

- +X 端散热鳍外移 `x=+L/2+0.36`，拉开与反射板根部铰座（x≈2.2–2.5）的轴向距离；-X 端散热鳍仍在 `x=-L/2-0.16`。
- 反射板根部角度 60/180/300°，与散热鳍 45/135/225/315°、窗带 0/120/240°错开；A 架/作动器只在背面。
- 双铰座与端盖肋错开布置；不遮挡 3 条采光窗带。

### 截图 / 验证

- `mockups/models-oneill-hi-reflector-angle-1920.png`（侧视：25° 张开、1.06L）
- `mockups/models-oneill-hi-reflector-mount-1920.png`（端盖环根部/铰座/作动器特写；无 3D 浮动标签）
- `mockups/models-oneill-hi-clean-1920.png`（主图同步重截）
- 均 SHOT err=0；FacilityModelFactory probe `checks=1697 fails=0`。

### 边界

- 铰座/作动器为视觉机械结构，不接真实铰链/液压/光学仿真；角度/尺寸为展示比例。
- 背面框架与正面镜面分层，实际正视仅镜面；端视可看到背面结构。
- 不写 world/session；未跑全量 regression。


---

## B-52：按 model-auditor 报告修 8 类穿模（task-233）

运行 `res://tests/model_structure_probe.gd`：**checks=181 fails=0 warns=0 meshes=457**（PASS，退出码0；无 allowlist/放宽）。

### 修复项

| # | 审计项 | 修复 |
|---|---|---|
| 1–3 | `reflector_strut_*` / `reflector_actuator_*` 在 t≈0.05–0.14 穿镜面（w=+0.233） | A字背撑/作动器的锚点与杆件全部移到镜面背面（w≈-0.06～-0.11）；端盖环→背锚点改用 `endcap_mount` 连接座，不再从正面穿过 |
| 4 | `mooring_0/1/2/3/4` 根部方块越过端盖内面 -2.17 进筒体 | 系泊根部外移到 x=-2.62（端盖外侧），根部块完全在端盖外；增加端盖环→根部 outboard 连接杆 |
| 5 | 系泊 0/2/3 压窗带边梁 | 根部径向/轴向外移后避开 0/120/240° 窗带边梁；probe 窗带接触检查通过 |
| 6 | 6 个 -X 对接口 12 件中心在端盖内侧 | `dpos.x` 由 `x - side*0.12` 改为 `x + side*0.12`；全部对接口 x 在端盖外侧（x_max<=-2.18） |
| 7 | 散热支臂以 base 为中心向内伸，撞交通艇接口 | 支臂中心改为 `base + radial*0.34`（向外延伸）；系泊/太阳能/交通艇按角度+轴向分层；太阳能外移到 x=-L/2-0.85、系泊 x=-L/2-0.42 |
| 8 | +X 散热鳍与反射板根部横梁/铰座相切穿插 | +X 散热鳍外移到 x=+L/2+0.55；反射板根部硬件保持 +X 端盖环；probe 近邻0对/无穿插 |

### 约束保留

- 外观风格/尺寸不变：单圆柱 30×7.5（L4.4/R0.55）；反射板 3 片、25°、1.06L、0.62 宽；3 窗带/3 外壳带。
- 镜面前层仍无框架线；硬件全部背面；无 allowlist、无静默放宽。
- 截图：`mockups/models-oneill-hi-clean-1920.png` 重截。
- 结构 probe 181/181 通过；FacilityModelFactory probe 未受影响。

### 边界

- 探针为采样/AABB 近似，非精确碰撞/公差；视觉上仍为程序化低模。
- 外部件为视觉挂点，不接真实热/电/系泊物理；不写 world/session；不 commit。


---

## B-53：修复 endcap_mount 连接杆镜面根部穿模（task-235）

- 审计残留：12 件端盖环→板背连接杆（每片 2 A 架 + 2 作动器）从端盖锚点 w≈+0.118 连到背锚点 w≈-0.062，穿镜面根部 t≈0.018；原 role=endcap_mount，G 组未覆盖。
- 修复：
  - 12 根连接杆改走**板轮廓外**：端盖环 → 外侧 waypoint（|u|=0.37/0.39 > 板半宽0.31）→ 板背锚点；不穿镜面正面/根部；
  - `audit_role` 改为 `reflector_strut`（G 组显式覆盖），`endcap_mount` 仍为 23 件安装座/环；
  - A 字背撑/作动器主杆保持背面，结构可读。
- 验证：`model_structure_probe.gd` → **checks=181 fails=0 warns=0**，G 三片 `front_hits=0 close_hits=0`；无 allowlist；FacilityModelFactory probe 不受影响。
- 截图重截：`mockups/models-oneill-hi-clean-1920.png`、`mockups/models-oneill-hi-reflector-mount-1920.png`。
- 文档：`docs/model_audit.md` §2.3 role 表（reflector_strut=30 / endcap_mount=23）与 §6.4 已同步。
- 边界：连接杆为程序化视觉结构；不接真实铰链/液压仿真；不写 world/session；不 commit。
