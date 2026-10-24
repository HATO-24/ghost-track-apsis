# 模型结构自动审计 / MODEL STRUCTURE AUDIT（task-232）

自动检查 `models/oneill_island3_hi.tscn` 的**结构合理性**与**穿模**：主尺度、反射板数量/分布/张开角、板与主体/端盖/板间/外部件穿插、镜面正面保护、-X 端外部件互不穿插、+X 端分工、AABB 数值健康。
**不**判断外观、材质、贴图、美术效果；**不**修改模型几何。只读运行，不写 world/session、不截图、不接物理。

**模型改动后先跑这个 probe，再谈外观/提交。**

| 文件 | 作用 |
|---|---|
| `game_v17/tests/model_structure_probe.gd` | 审计 probe（`extends SceneTree`，单次运行，exit code 0/1） |
| `game_v17/docs/model_audit.md` | 本文件：规则、容差、允许接触对、运行方式、边界、基线 |
| `game_v17/models/oneill_island3_hi.gd` | 只加了**非视觉** `name` / `group` / `meta` 标记 + 根部审计契约 meta；几何/材质/位置未改 |

---

## 1. 运行

工作区根目录 `D:\GHOST TRACK_APSIS`：

```powershell
& "tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game_v17 `
    --script res://tests/model_structure_probe.gd
```

- 退出码：`0` = PASS（允许 WARN）；`1` = 有 FAIL。Windows 上 `$LASTEXITCODE` 可直接判断。
- 单次运行（约 1–2 秒），无循环等待；失败项以 `[FAILED] ...` 打印，含**部件名 + role + side/index + 数值**。
- 调试：`$env:DSH_PROBE_DEBUG='1'` 时额外打印 `[PART]` 全量部件清单（name/role/side/index/世界 AABB/shape），用于人工复核；正常 CI 不要开。
- 输出分区：`[A]` 契约/标记、`[B]` 部件清单、`[C]` 主尺度、`[D]` 采光窗、`[E]` 反射板几何、`[F]` 反射板穿模、`[G]` 镜面正面、`[H]` -X 外部件、`[I]` +X 规则、`[J]` 数值/AABB。
- `[DATA]` 行为测量值快照（便于对比改动前后）；`[WARN]` 为不阻塞的提醒（当前基线 0 条）。

---

## 2. 标记契约（probe 的唯一数据源）

probe **不复制模型常数**，从场景根节点 meta 读取审计契约；每个 `MeshInstance3D` 必须带 role 标记。

### 2.1 根节点 meta（`_stamp_audit_contract()` 写入）

| meta | 值 | 含义 |
|---|---|---|
| `audit_schema` | `1` | 标记协议版本 |
| `audit_length` | `4.4` | 圆柱长度（场景单位，对应 30 km） |
| `audit_radius` | `0.55` | 圆柱半径（对应 3.75 km；D=1.1 → 7.5 km） |
| `audit_window_centers_deg` | `[0, 120, 240]` | 3 条采光窗中心方位角 |
| `audit_window_half_deg` | `17.0` | 窗带半角（全宽 34°） |
| `audit_reflector_count` | `3` | 反射板片数 |
| `audit_reflector_azimuths_deg` | `[60, 180, 300]` | 反射板根部方位（避开窗带） |
| `audit_reflector_open_deg` | `25.0` | 反射板相对圆柱轴的张开角 |
| `audit_reflector_root_standoff` | `0.30` | 根部相对 +X 端面的外伸距离 |
| `audit_reflector_len_factor` | `1.06` | 板长 / 圆柱长 |
| `audit_reflector_width` | `0.62` | 板宽（≈0.56×直径） |

### 2.2 每个 MeshInstance3D 的标记

由 `_attach(mi, role, side, index)` 统一写入：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | String | `role[_index]_<seq>`，同级唯一（probe 用 meta，不依赖名字） |
| `add_to_group("audit_" + role)` | group | 便于编辑器/外部工具按 role 选取 |
| `meta audit_role` | String | **必需**；缺失或 `"misc"` → `[B]` FAIL（未标记部件） |
| `meta audit_side` | int | `+1` = +X 反射板端；`-1` = -X 港口/工业端；`0` = 舱段/壳体等 |
| `meta audit_index` | int | 反射板片号 0–2；外部件 assembly 序号 0–5；-1 = 无 |

### 2.3 role 分类表（新增部件必须落入其中之一）

| role | 归属 | 基线数量 | 允许的接触/嵌套 |
|---|---|---|---|
| `hull_shell` | 主圆柱外壳（128×48） | 1 | — |
| `window_glass` / `window_frame` | 3 条采光窗玻璃 / 凹框边梁横肋 | 3 / 36 | 贴在外壳表面（允许） |
| `hull_ring`/`hull_stringer`/`hull_seam`/`hull_hatch`/`hull_panel_line` | 外壳表面细节 | 11/6/60/12/6 | 贴在外壳表面（允许） |
| `interior_terrain`/`interior_water`/`interior_clouds` | 窗内陆地/水/云 | 33/3/9 | 位于壳体内部（允许，视为设计内容） |
| `reflector_panel` | 镜面板（3 段/片） | 9 | 不与任何结构穿插 |
| `reflector_frame`/`reflector_rail`/`reflector_rib` | 板背框/导轨/横肋 | 9/18/9 | 必须整体在镜面**背面** |
| `reflector_hinge` | 根部横梁/双铰座/轴承/限位/止挡 | 39 | 允许与 +X 端盖环接触 |
| `reflector_strut` | A 字背撑 + 板轮廓外绕入连接杆（B-53 起） | 30 | 允许端盖连接座接触；**不得穿镜面正面/根部边缘**；G 组覆盖 |
| `reflector_actuator` | 线性作动器（杆/套筒/锚座） | 24 | 同上 |
| `endcap` | 两端端盖圆盘/环/放射肋/枢纽 | 40 | — |
| `endcap_mount` | 端盖环安装环/座：+X 反射板 6 + 12 连接座 + 5 系泊连接杆 | 23 | 与铰座接触（允许）；不参与 G 正面检查（不进入镜面投影） |
| `dock_port` | -X 端 6 个港口对接口 | 12 | 必须位于端盖**外侧** |
| `radiator` | 两端端盖环外 4 组散热鳍（含支臂/根部环） | 32（每端 16） | 同 assembly（同 role+index+side）内部允许装配接触 |
| `solar` | -X 端 4 组太阳能阵列 | 20 | 同上 |
| `mooring` | -X 端 5 个系泊塔 | 15 | 同上；不得穿壳体/窗带 |
| `dock_interface` | -X 端 5 个交通艇接口 | 15 | 同上 |

> 新增外部件时，用 `_cyl(..., role, side, index)`、`_box(..., role, side, index)`、`_torus(..., role, side, index)`、`_sphere(..., role, side, index)`、`_box_basis(..., role, side, index)`、`_band(..., role, index)` 传入标记；不要裸 `add_child(MeshInstance3D)`，否则 `[B]` 判 FAIL。
> 新增 role 或改动数量时，同步更新 `[B]` 的期望数量表与本文件的 role 表。

---

## 3. 检查项与容差

世界单位为场景单位：模型 1.0 单位 ≈ 30 km / 4.4 ≈ **6.818 km**（真实比例仅作文案参考）。`TOUCH_EPS = 0.004` ≈ 27 km（展示尺度上的“接触容差”）。

| 分组 | 检查 | 规则 / 容差 |
|---|---|---|
| A | 契约 meta 齐全 + 数值 | schema=1；L=4.4±1e-4；R=0.55±1e-4；L/D=4.0±0.001；窗中心/半角/反射板 3/25°/1.06/0.62/0.30 与契约一致；根缩放均匀且 >0 |
| B | 部件清单 | mesh 数 350–700；必需 role 数量下限；`hull_shell` 唯一；`window_glass`=3；`reflector_panel`=9；每侧 `radiator`=16；未标记/null mesh = 0；name 唯一；role 在分类表内 |
| C | 主尺度 | 外壳顶点 L=4.4±0.02；D=1.1±0.015；L/D=4.0±0.05；±X 端对称 ±0.01 |
| D | 采光窗 | 外壳角向缺口恰 3 条；每条角宽 30–37°；中心距契约 0/120/240±2°；3 条近似 120° 均布；玻璃 3 条、方位 ±2°、半径 1.004R±0.01 |
| E | 反射板几何 | 每片 3 段、共 3 片；3 段共面/法线一致；张开角 25°±2°；根部方位契约 ±3°；根部半径 1.08R±0.02R；根部外伸 0.30±0.02；板长 1.06L±0.03；端到端跨度 1.0–1.1L；板宽/直径 0.5636±0.02；与筒体间隙 ≥R+0.01；与窗带中心错开 ≥20° |
| F | 反射板穿模 | 板不穿筒体壳体、不穿端盖/对接口、板间不穿插、不穿 -X 外部件；根部结构（铰座/背撑/作动器）不穿筒体壳体 |
| G | 镜面正面 | 正面 = 镜面法线**朝向筒轴**一侧（背面 = `back=-0.052` 外侧）。背框/导轨/横肋最大法向 ≤ -0.009+0.004；`reflector_strut`（含 B-53 的 12 根连接杆，role 已从 endcap_mount 改记）/`reflector_actuator` 表面点若在镜面轴向 t∈[-0.05,1.05]、横向 |u|≤板宽/2+0.02 内且法向 > +0.011 → FAIL；> -0.009 → WARN。连接杆经板轮廓外 |u|>0.31 的 waypoint 绕入背面。 |
| H | -X 端外部件 | 散热/太阳能/系泊/交通艇/对接口总数=78 且 side=-1；不穿筒体壳体（轴向端面 0.03 余量内豁免）；不穿窗带；港口对接口 x_max ≤ -L/2+0.02；互不穿插（同 role+index+side 视为同一 assembly，允许装配接触）；数量：散热 16 / 太阳能 20 / 系泊 15 / 交通艇 15 / 对接口 12 |
| I | +X 端规则 | +X 端无 solar/mooring/dock_interface/dock_port；+X 端反射板安装件 ≥6；反射板根部结构（铰座/背撑/作动器）不与 +X 端散热鳍穿插 |
| J | 数值/AABB | 无 NaN/Inf；三轴尺寸 >1e-4；采样点有限；全部部件 |x|≤6、半径≤5（世界单位）；模型整体包围在限内 |

### 检测方法

1. 实例化 `oneill_island3_hi.tscn` 并等待一帧，让程序化 `_ready()` 建完 440 个 MeshInstance3D。
2. 每个 mesh 取 `mesh.get_aabb()` → 世界 AABB；取**真实表面顶点**（每个 mesh 最多约 48 个，按 stride 抽样）作为采样点，避免旋转 AABB 角点造成假穿模。
3. 点-实体判定按 mesh 类型精确：`BoxMesh`（OBB）、`CylinderMesh`（圆柱）、`SphereMesh`（球）、`TorusMesh`（环面）；SurfaceTool 自定义网格退化为局部 AABB。
4. 先用世界 AABB 预筛“近邻对”，再对采样点做点-实体判定；允许 `TOUCH_EPS` 接触容差。

---

## 4. 允许接触对 / 嵌套（豁免清单）

以下接触是设计允许的，probe 不报 FAIL：

1. **反射板根部铰座 ↔ +X 端盖**：`reflector_hinge` 与 `endcap` / `endcap_mount` 允许根部机械接触。
2. **背撑/作动器 ↔ 端盖**：`reflector_strut` / `reflector_actuator` 允许锚点在端盖环上。
3. **外部件 ↔ 端盖**：`radiator` / `solar` / `mooring` / `dock_interface` / `dock_port` 与端盖的挂点接触不单独判穿插（只查壳体/窗带/对接口位置/外部件互穿）。
4. **外壳表面细节 ↔ 外壳**：`window_*`、`hull_ring/stringer/seam/hatch/panel_line` 贴在外壳表面属设计层，不做两两穿插检查。
5. **窗内内容 ↔ 壳体内部**：`interior_*` 位于壳体内部属设计内容，不判“进入筒体”。
6. **同一 assembly 内部**：`[H]` 互穿检查中，`role + index + side` 完全相同的两件视为同一装配（如散热鳍板与其支臂），允许接触。
7. **端面安装余量**：筒体轴向端面往里 `0.03` 单位内不判“穿入壳体”，避免把端盖安装座误判为穿模；`[H]` 另外用“对接口必须在端盖外侧”覆盖该区域。

**不允许**：镜面板穿壳体/端盖/其他板/外部件；框架/导轨/背撑/作动器穿过镜面正面；-X 外部件互穿或穿壳体/窗带；+X 端出现港口/系泊/太阳能；反射板根部结构与 +X 散热鳍冲突。

---

## 5. 边界与局限（重要）

1. **不是精确三角面碰撞**：probe 用 AABB 预筛 + 表面顶点采样 + primitive 实体判定；极薄件、相切、仅棱/点接触、大曲面边缘可能漏检或需要人工复核。
2. **采样密度**：每个 mesh 最多约 48 个表面点；对环面/圆柱等曲面是离散采样，接触深度小于采样间距的穿插可能漏报。
3. **AABB 只是包络**：对 SurfaceTool 自定义网格（外壳/窗带/内部地形）以局部 AABB 参与判定；这些部件本身不参与主体互穿检查。
4. **镜面正面定义**：以片体法线**朝向筒轴**为正面（与模型背面层 `back=-0.052` 的层级一致）。若未来改变镜面板朝向/层级，必须同步更新 probe 的 G 组判定。
5. **尺度**：容差是展示尺度上的“接触不判穿”，不是真实工程公差；1 单位 ≈ 6.818 km，`0.004` ≈ 27 km，结论按展示模型理解。
6. **不检查**：外观/材质/贴图/颜色、悬空/未连接挂点（例如支臂是否真的焊在端盖上）、遮挡关系、LOD、性能、物理/质量、真实热/电/系泊功能。
7. **只覆盖本场景**：`oneill_island3_hi.tscn`；其他模型（module station、Stanford torus 等）需要各自添加 role 契约并扩展 probe。
8. **不替代人工**：FAIL 为几何量测结论；是否修、如何修（移动挂点/改尺寸/接受遮挡）由建模任务决定，probe 不改外观。

---

## 6. 基线（B-53，2026-10-22）

probe 命令见 §1。当前基线：**checks=181，fails=0，warns=0，meshes=475**，exit code 0；实测运行 **666 ms**（wall，含引擎启动）。
probe 文件 SHA256 `7F3A57D374101FD227E18644B20F77A65E176E80A7A63D667B516E711485D7D6`，自 B-52 复核后**未再修改**；B-52/B-53 期间无 allowlist、无静默放宽、无检查项/阈值变更（`TOUCH_EPS=0.004`、`MIRROR_FRONT_TOL=0.011`、G 组角色仍为既有五类）。

### 6.1 B-52 独立复核（历史，probe PASS）

- B-51 的 8 项 probe FAIL 已逐项修复，并用独立数值方法复核：
  - [G] A 字背撑/作动器的锚点与杆件全部在镜面背面（锚点最大法向 w=-0.062 ≤ -0.009）；
  - [H] 6 个 -X 对接口移到端盖外侧：中心 x=-2.34、x_max=-2.27 ≤ -2.18；
  - [H] 5 个系泊塔根部/塔体全部在 x≤-2.55（筒体端面 -2.20 之外），不再进入壳体/窗带；
  - [H] -X 外部件近邻对=0、互不穿插；散热支臂改为向外延伸（r 0.652–1.172），与交通艇接口（r≤0.227）分离；
  - [I] +X 散热鳍外移到 x 2.68–2.94，与反射板根部横梁（x≤2.562）留 0.118 间隙，近邻 0 对。
- 主尺度/窗带/反射板几何/穿模/AABB 共 181 项检查全 PASS；`mockups/models-oneill-hi-clean-1920.png`（B-52 重截）整机 3/4 视角无明显穿模。

### 6.2 B-52 残余风险（历史，已由 B-53 修复）

- 12 件原 `endcap_mount` 连接杆穿镜面板根部边缘：法向 w 从 +0.118（端盖环端）到 -0.062（背锚点端），穿镜面 t≈0.018、u=±0.211/±0.136（板半宽 0.31、板根 t=0.0067），相交 t 区间 0.0082–0.0295；G 组不检查 `endcap_mount` → 属**角色覆盖缺口**（不是规则被放宽）。B-53 已修复并关闭，见 §6.4。

### 6.3 B-51 历史基线（FAIL，已由 B-52 修复）

- **B-51（2026-10-22，历史 FAIL）**：checks=181 / fails=8，失败项为 A 字背撑/作动器穿镜面 ×3、系泊根部方块穿壳体/窗带 ×2、-X 对接口位置错误 ×1、-X 外部件互穿 ×1、+X 根部结构与散热鳍冲突 ×1（明细见 task-232 报告）。

### 6.4 B-53 当前基线（probe PASS，2026-10-22）

- 独立重跑 `res://tests/model_structure_probe.gd`：**checks=181 fails=0 warns=0 meshes=475**，exit 0，**666 ms**；分区全 OK；`outboard_neg near_pairs=0`、`+X near_pairs=0`、G 组三片 `frame_parts=30 / front_hits=0 / close_hits=0`。
- 连接杆处理：B-52 的 12 根「端盖环 → 背锚点」直杆改为「端盖环 → 板轮廓外 waypoint → 板背锚点」两段，并新增 6 个 waypoint 块。靠镜面一侧的 12 根外段 + 6 个 waypoint 块记 `reflector_strut`（G 组覆盖）；端盖侧 12 根短段仍记 `endcap_mount`（位于板轮廓外）。role 数量：`reflector_strut` 12→30、`endcap_mount` 23，与 §2.3 一致。
- 独立数值复核（不依赖 probe）：ring→waypoint 段横向 |u|=0.390（A 架）/0.370（作动器）> 板半宽 0.31，杆半径 0.024/0.020 → 距板边 ≥0.036；waypoint→背锚点段两端法向 w=-0.062/-0.057，全在镜面背面；所有连接杆/waypoint 表面点与 3×3 镜面板相交数 = **0**；镜面几何未变（t 根部 0.0067、半宽 0.31、厚 0.018）。
- 截图：`mockups/models-oneill-hi-clean-1920.png`（B-53 重截）整机无可见穿模；`mockups/models-oneill-hi-reflector-mount-1920.png`（B-53 重截）连接杆绕板边、镜面正面无框架/穿孔。
- 其余检查（主尺度 4:1、3 窗带、3 片反射板 120°/25°/1.06L/0.62、-X/+X 分工、AABB/NaN）保持 PASS。

### 6.5 历史基线汇总

- **B-51（历史 FAIL，已由 B-52 修复）**：8 项穿模/错位（明细见 §6.3）。
- **B-52（历史 PASS）残余风险（历史一句）**：12 根 `endcap_mount` 连接杆曾穿镜面根部（G 角色覆盖缺口），已由 B-53 修复并关闭（§6.2/§6.4）。

---

## 7. 变更流程（强制）

1. 改 `oneill_island3_hi.gd` / `.tscn` / 挂点后，先跑 probe；`fails=0` 才进入外观/截图步骤。
2. 新增/改名/改数量 → 同步更新 `[B]` 期望表、§2.3 role 表、§6 基线。
3. 确需豁免某项 FAIL：优先修模型；确不能修时，在 probe 里加**显式 allowlist 常量**并注明原因，同时更新本文件，不要静默放宽阈值。
4. 标记改动必须非视觉：只允许 `name` / `group` / `meta` / 根部契约 meta；不得改 mesh、transform、material。
5. 运行结果（checks/fails 明细）随模型改动记入对应任务报告；不 commit 由 Lead 统一处理。
