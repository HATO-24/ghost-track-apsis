# V17 传感器权威切换计划（R5 · sensor_authority_plan）

> 配套：`docs/38_传感器与信息作战规格.md`（权威规格）、`docs/37_真实空间与信息作战架构.md`、`game_v17/docs/v17_bridge_fields.md`、`game_v17/docs/v17_radio_sensor.md`、`game_v17/docs/v17_sensor_plot.md`。
> 工程：`game_v17`（V15 视觉 HUD/plot + V2 core/sim 数据后端）。本文件只写**迁移/切换计划**，不实现代码。
> 目标：把当前「V15 sensor_model 权威 + V2 advisory」切换为「V2 SensorAuthority 唯一权威」，同时保持 V1 HUD、可回退、每阶段 probe。

---

## 0　当前基线（R4，2026-10-20）

### 0.1　现状事实

- V17 启动：`main.gd` boot `V17Bridge`（`scripts/framework_bridge.gd`）→ `state.framework = bridge` → 每帧 `state.refresh(state.clock)` 与 `state.fw_sync(delta)`。
- **权威仍是 V15**：`state.sensor_authority == "legacy_v15"`（`scripts/state.gd` 常量 ≈L176、变量 ≈L185）；`state._fusion_tick()`（≈L858）用 `scripts/sensor_model.gd` 做探测/融合/等级/身份/威胁；`state.tracks` 是唯一显示来源。
- V2 模型（`framework/sim/{sensor_types,radar,tws,optical}.gd`）当前只用于：
  - bridge 的 `contacts`（V2 归一接触，`state.fw_contacts`，仅数据/教学/flow 用）；
  - plot 的 TWS/球形雷达 overlay（`scripts/tws_bridge.gd`，只读驱动 V2 TWS，plot 叠加显示）；
  - 截图/独立验证（`sensor_explorer`）。
- `state.v2_sensor_advisory()`（≈L3126）明确返回 `authority=legacy_v15`、`role=advisory_data_demo`、`switching=false`；另 `sensor_authority_note()`。
- 现有 probe：`tests/v17_bridge_probe.gd`（138/0）、`tests/v17_core3_probe.gd`（171/0）、`tests/plot_tws_probe.gd`（59/0）；V16 侧 `sensor_probe/snapshot_probe/sensor_bridge_probe`；`sensor_explorer/tests/sensor_explorer_probe.gd`。
- 已知教训：V17 plot 相机 `_focus_km`(km) 与 3D 相机（m）单位混用曾导致主体居中错误；R5 新 authority 必须固定单位/坐标系契约（见 §4）。

### 0.2　现有 V2 模型成熟度（可直接复用）

| 模型 | 当前能力 | R5 缺口 |
| --- | --- | --- |
| `sim/radar.gd` | `R_eff`/RCS/jamming/resist、球形范围、扫描、暴露（ELINT 45,000 km/20 s） | 需要实体姿态/指向、ECCM/欺骗、多雷达、与 TrackTable 接线 |
| `sim/tws.gd` | 6 通道、SEARCH→…→FIRE_CONTROL、quality/age/失锁/重捕/火控解算 | 通道写者改为 authority；与 level 证据合并；HUD 只读 |
| `sim/optical.gd` | VIS/IR 通道状态机、凝视/光照/阴影/遮挡/失锁；缺 FOV/IFOV/角速度 | §5 的物镜/口径/FOV/IFOV/相对角速度/曝光/分类像素判据；通道窗 API |
| `sensor_types.gd` | 型号记录/R_eff/jamming/illum/LOS/暴露 | 光学/IR 配置字段、IFF/ELINT/EW 参数、attitude/pointing |
| V15 `sensor_model.gd` | 完整 L1–L4、融合、IFF/ELINT、暴露/EMCON、协方差、威胁 | **仅保留 legacy 回退/参考；R5 后不作为默认权威** |

---

## 1　目标架构与职责

### 1.1　文件/模块职责（R5 目标）

| 模块 | 职责 | 禁止 |
| --- | --- | --- |
| `framework/core/world.gd` | 实体/世界状态、TrackTable、EventBus、replay、flow | 调 UI/V15 |
| `framework/core/entity.gd` | 实体、位置/速度/姿态/挂载/损伤 | 传感器判定 |
| `framework/sim/sensor_authority.gd`（新） | **唯一传感器管理器**：挂载、环境、观测、信号、IFF、ELINT/COMINT、EW 效果结算、通道管理 | 写 HUD/state 显示 |
| `framework/sim/{radar,tws,optical,sensor_types}.gd` | 纯模型库（被 authority 调用）；无世界写入 | 直接写 TrackTable/EventBus（返回观测/事件即可） |
| `framework/core/track_table.gd` | 唯一航迹/等级/身份/协方差写者 | 被 UI 写 |
| `scripts/state.gd` | V15 HUD 状态 + **adapter**：legacy 融合（仅 legacy 模式）/把 V2 view-model 归一为 V15 字段 | authoritative 模式再跑 V15 融合/写第二套等级 |
| `scripts/framework_bridge.gd` | V2 bridge：boot/sync/read-only view；新增 `sensor_view()` 等 | 写 UI/V15 判定 |
| `scripts/tws_bridge.gd` | 从 authority 快照生成 plot 用的 TWS/球形/光学视图；legacy 下只是 advisory 叠加 | 写 state.tracks/等级 |
| `scripts/main.gd` | 时钟/输入/启动；决定 authority 模式（读 env/state） | 传感器判定 |
| `scripts/hud.gd` / `plot.gd` | 只读显示/交互（独立窗可控制通道） | 计算等级/身份/威胁、调 `sensor_model.detect*` |
| `sensor_explorer/*` | 验证台：模型/几何/数值验证 | 游戏权威/存档来源 |

### 1.2　权威模式（V17 需要实现的状态机）

```text
legacy_v15 (当前默认)        shadow (R5 迁移)                v2_authoritative (R5 目标)
─────────────────────       ──────────────────────           ──────────────────────────
V15 _fusion_tick 写 tracks   V15 _fusion_tick 写 tracks       V2 authority/TrackTable 写 world
V2 advisory 只读             V2 authority 全算 shadow          state adapter 只读 V2 view-model
HUD/plot 读 V15              shadow 对比器只读                 HUD/plot 读归一化 state.tracks
                             不写 state.tracks                 V15 融合停用（代码保留 fallback）
```

- 三模式由 `state.sensor_authority` + 环境变量选择；**同一 tick 只存在一个显示写者**。
- `shadow` 只允许读 V2 shadow 结果、写 diagnosis/compare 日志；**严禁**回写 `state.tracks`、flow、威胁。
- `v2_authoritative` 下 `state._fusion_tick` 不参与显示（保留给回退/旧 demo），状态适配器拉取 V2 `vm_contacts` 并映射为 V15 兼容字段。

---

## 2　V17 切换点清单（逐文件/函数）

> 现状行号为估算（代码会变，按函数名定位）；R5 实现时以实际签名为准。

| # | 位置 | 现状 | R5 目标 |
| --- | --- | --- | --- |
| S1 | `scripts/main.gd::_ready` | boot bridge → `state.framework` → `state.fw_sync(0)` | 读 `V17_SENSOR_AUTHORITY`（默认 legacy）→ `framework.set_authority_mode(mode)`；legacy 时行为不变 |
| S2 | `scripts/state.gd` 常量/变量 `SENSOR_AUTHORITY_LEGACY`、`sensor_authority`（≈L176/185） | 恒 `legacy_v15` | 扩为 `{legacy_v15, shadow, v2_authoritative}`；新增 `set_sensor_authority`/`sensor_authority_state()`；非法值拒绝并回退 |
| S3 | `scripts/state.gd::_fusion_tick`（≈L858） | 每仿真秒用 `sensor_model` 探测/融合/写 tracks | authoritative 模式早退（不写 tracks）；shadow 模式照常写 V15，并把同一 tick 的 V2 shadow 快照交给对比器（只读） |
| S4 | `scripts/state.gd::set_sensor` / `set_emcon`（≈L1096/1123） | 改 V15 `sensor_on/emcon`，刷新融合 | legacy：不变；authoritative：转发到 `framework.world.set_mount_enabled/emcon`（经 bridge 封装），并同步视图；shadow：双跑但 V15 写仍是显示，V2 结果只记录 |
| S5 | `scripts/state.gd::refresh/_update_phase_gate` | 写 `tracks/level/identity/...` | authoritative 模式改为 adapter：从 `framework.vm_contacts()`/`track_view()` 归一化写 V15 字段（只映射，不判定）；legacy/shadow 保持原逻辑 |
| S6 | `scripts/framework_bridge.gd` | boot/sync/contacts/flow/damage/replay/… | 新增 `set_authority_mode`、`sensor_view()`、`sensor_channels()`、`signals()`、`iff_view()`、`ew_effects()`、`shadow_compare()`；`world` API 经封装 |
| S7 | `scripts/tws_bridge.gd`（plot TWS） | V15 state 只读驱动 V2 TWS；plot 叠加 | authoritative：从 authority 通道快照生成同一视图（不重复 step/判定）；legacy/shadow：保留现状（shadow 可标注） |
| S8 | `scripts/plot.gd` `_v17_tws_*`/`_draw_radar_sphere`/`_draw_emission` | 读 `tws_bridge` + V15 emission；绘制球形/TWS/EMIT | 数据源改为 `state.fw_sensor`（authority 归一化）或 `tws_bridge` viewer；不自行算 R_eff/等级/威胁；保留 V1 视觉 |
| S9 | `scripts/hud.gd` 右区传感器架/顶栏/接触列表 | 读 `state.sensors`/`racks`/`sensor_on`/`tracks`/`emission` | 读同一 authority view（通过 state 字段）；新增 ELINT/EW 摘要/独立窗；不本地判定/不双计数 |
| S10 | `scripts/hud.gd` 光学/通道窗、`_optical_*` | V15 演示/进度 | 读 authority `ChannelView`（VIS/IR 完整窗）；开始/停止调 authority（经 state 封装）；窗口字段见 docs/38 §5.6 |
| S11 | `scripts/state.gd::v2_sensor_advisory` / `sensor_authority_note`（≈L3122–3141） | 恒 legacy advisory | 真实模式状态/对比诊断；legacy 时保持旧语义；authoritative 时附 `authority=v2_sensor`、`switching` 记录、`last_sync_t`、`shadow_diff` |
| S12 | probe/CI | 现有 5 个 probe（§0.1） | 增加 R5.0–R5.7 的 probe（§7）；CI 矩阵三模式 |

### 2.1　新增/变更字段（V17 adapter 层，建议命名）

```gdscript
# state（只读字段，供 HUD/plot）
state.sensor_authority           # "legacy_v15" | "shadow" | "v2_authoritative"
state.sensor_authority_state()   # {mode, ready, effective, since_t, reason, shadow_diff, last_tick_t}
state.fw_sensor                  # Dictionary（authority 归一化快照，见下）
state.fw_sensor_shadow           # shadow 模式对比结果（只读；生产模式为空/隐藏）
state.tracks                     # authoritative：由 adapter 从 V2 contacts 归一化；legacy：V15 融合

# fw_sensor 建议结构（schema sensor_view.v1）
{
  "schema": "sensor_view.v1",
  "authority": "v2_sensor"|"legacy_v15"|"shadow",
  "t": 1234.5,
  "channels": {...},            # VIS/IR/TWS/lidar 通道摘要+明细（按需）
  "exposure": {...},            # 暴露/EMCON/ELINT 截获
  "iff": {...},                 # 最近询问/状态
  "signals": [...],             # ELINT/COMINT 信号摘要（不产生接触）
  "ew_effects": [...],          # 当前 EW 效果摘要
  "notes": [...],               # 降级/缺失说明
  "source": "framework/sim/sensor_authority"
}
```

- `state.fw_contacts` 保持 V2 归一接触（教学/flow/站体用）；authoritative 模式下 HUD 显示的 `state.tracks` 由同一份 V2 航迹派生，**不另存第二套**。
- 所有字段必须有 `stale/age` 与数据时间；UI 不显示过期值假装实时。

### 2.2　环境变量 / 开关

| 变量 | 默认 | 语义 |
| --- | --- | --- |
| `V17_SENSOR_AUTHORITY` | `legacy` | `legacy|shadow|v2`；启动时决定模式；运行中只允许显式调试切换（HUD 日志警告） |
| `V17_SENSOR_SHADOW_VERBOSE` | 空 | shadow 对比日志（仅调试） |
| `V17_SENSOR_STRICT` | 空 | v2 模式下缺失传感器数据时 fail-fast（probe/CI 用）；生产应 graceful hide |
| `DSH_LEGACY_SENSOR=1` | 空 | 截图/旧 demo 强制 legacy（与 authority 变量冲突时该变量优先并告警） |
| `DSH_SENSOR_DUMP=path` | 空 | 调试 dump `fw_sensor`/shadow diff JSON（不写存档） |

约束：环境变量解析只在 boot/显式调试入口；**游戏中途不得静默改权威**；模式变更必须写日志/回放事件。

---

## 3　V17 字段映射（adapter）

### 3.1　V2 `vm_contacts()` → V15 `state.tracks`

authoritative 模式下必须保持 HUD/plot 现有字段可用（否则视觉要改，违背 V1 HUD 约束）：

| V15 字段 | V2 来源 | 规则 |
| --- | --- | --- |
| `id/batch` | `track_id/batch` | 直接 |
| `name/en/cls/role/side/kind/display_kind/icon/size_km/fixed` | `vm_contacts` 行 | 直接；fixed 不画推进/预测 |
| `level/level_label` | `level/level_label` | 直接；等级由 authority 给 |
| `identity` | `identity` | 直接；无应答仅 unknown/pending |
| `bearing_deg/range_km/range_band`、`covariance`、`age_s/stale` | 对应 view 字段 | 直接；无距离给 -1/band |
| `sources` | `sources` | 直接（HUD 只读） |
| `iff_status/signal/threat/spoof_flags` | 对应字段 | 直接；`threat` 仅由 authority/指挥给 |
| `off/bearing_only/phantom/occluded` | 对应字段 | 直接；phantom 显示但要可交叉验证 |
| `own` | bridge/view 标记 | 本舰不能当普通接触 |
| `level_evidence/identity_evidence` | 对应 | 不直接进 HUD，仅调试/独立窗/审计 |
| `provenance`（新增） | `authority` | `"legacy_v15"|"v2_sensor"`，UI 小字/调试可见 |

- 映射器只做字段重命名/默认值/单位换算（严格：km↔m 只在一处转换，禁止混用），**不重新计算等级/身份/威胁/协方差**。
- `state.tracks` 的历史行为（排序、选中索引、标号）保留；adapter 保证数组顺序稳定（按 batch/track_id 稳定排序），避免 HUD 选中跳动。

### 3.2　传感器架/开关

- HUD 右区传感器架仍读 `state.racks`/`sensor_on`；authoritative 模式下由 adapter 用 `fw_sensor`/挂载视图映射生成，`set_sensor` 动作经 `state.fw_set_sensor` → `bridge` → `world.set_mount_enabled`。
- 不能因为 V2 传感器模型存在就禁用 V15 架显示；架是「玩家可见的配置+状态」，权威只决定开关/结果。
- `mast/EMCON/damage` 同样映射：桅杆收起/损管损坏 → 主动/被动传感器不可用；UI 只显示不可用原因。

---

## 4　单位/坐标系/时间契约（R5 必须固定）

| 量 | 单位 | 说明 |
| --- | --- | --- |
| 位置/距离 | km（view）/ m（物理公式按需） | authority 内部统一 SI 或明确字段后缀；跨层转换只允许在 adapter 一处 |
| 速度 | km/s | 同上 |
| 角度 | deg（视图） / rad（公式内部） | σ/角速度明确后缀 |
| 时间 | 仿真秒 `t` | 与 V15 `state.tau()`/V2 `world.t` 建立单一映射；禁止双时钟各自判定 |
| 姿态 | 四元数（归一化）+ 角速度 deg/s | 舰体→L1/ECI 必须注明参考系 |
| RCS/温度/面积 | m²/K/m² | 数据表字段 |

- 时钟：authoritative 模式以 V2 world 为仿真时钟，V15 `state.clock` 作为显示时钟（由 adapter 驱动/校准）；回放/暂停冻结两者一致。
- 约束：任何传感器模型不得混用 km/m；R5 probe 增加单位一致性断言（典型：`_focus_km` 类问题不得重现）。
- 参考系：实体状态必须带 `frame`（`l1_local`/`eci`）或统一字段名；光学视轴/姿态必须明确舰体/局部系；多站 ELINT 交叉在统一帧中计算。

---

## 5　迁移步骤（R5.0–R5.7）

> 每阶段独立可运行、可截图、可回退；所有阶段先写 probe 再开 UI。

### R5.0　权威开关与对比骨架（不改可见行为）

- 增加 authority 枚举/环境变量/`sensor_authority_state()`；`legacy` 默认行为不变。
- `shadow` 骨架：V15 写显示；boot 后启动 V2 authority 空跑；每帧记录 V2 结果到 `fw_sensor_shadow`/日志；实现 `shadow_compare` 字段（等级/身份/距离/来源差异）。
- 验收：现有 probe 全绿；legacy 截图像素不变；shadow 不改 `state.tracks`/flow；模式非法回退 legacy 并打印。
- 回退：`V17_SENSOR_AUTHORITY=legacy`。

### R5.1　实体/姿态/环境/挂载数据（依赖 R2/R3/R6 部分）

- core entity 增加 `attitude_quat/angular_rate`、`mounts[]`、`transponder`、`emitters[]`；`EnvironmentFrame`（sun/moon/earth/shadow/LOS/jamming）。
- `content/sensors.json` 数据表（docs/38 §5.1/§10）装载；`SensorAuthority` 骨架（挂载/环境/通道容器）。
- 验收：`v17_entity_env_probe`（schema/单位/确定性/LOS/光照）；sensor_explorer 可继续作为参考。
- 回退：legacy 不需要这些字段；adapter 未启用。

### R5.2　雷达/TWS 权威化（shadow）

- authority 接 `radar.gd`/`tws.gd`：扫描、R_eff、TWS 六态、暴露、失锁；输出观测到 EventBus → core TrackTable；shadow 对比 V15 等级/距离/身份。
- `tws_bridge`/plot TWS 仍读 V15（显示不变）；可选调试 overlay 显示 V2 shadow 与 V15 的差异。
- 验收：`v17_sensor_authority_probe` + radar/TWS shadow 断言（§10 docs/38）；diff 分析表（等级差、距离差、通道状态差）在容忍门限内或已解释。
- 回退：`legacy`/关闭 shadow。

### R5.3　光学/IR 权威化（shadow + 通道窗数据）

- authority 接扩展 `optical.gd`（FOV/IFOV/口径/焦距/光照/遮挡/凝视/相对角速度/运动模糊/分类像素）；输出 `ChannelView`。
- V17 光学/IR 通道窗先读 shadow 数据（标注 SHADOW），保留 V15 视觉主状态；开始/停止先只写 shadow（不改玩法）。
- 验收：`v17_optical_ir_probe` 全绿；通道窗字段/状态机/并行通道；V15 截图像素不变。
- 回退：legacy。

### R5.4　IFF/ELINT/COMINT 权威化（shadow）

- IFF 状态机/模式/代码/欺骗/无应答 → identity evidence；ELINT 信号/测向/指纹/多站；COMINT 内容/加密；全部进 EventBus。
- HUD 只加信号/EW 摘要与独立窗；shadow 先不改显示等级/身份。
- 验收：`v17_iff_probe`/`v17_elint_probe`；「不明不判敌」「单站不产生接触」「多站候选须确认」逐条断言。
- 回退：legacy。

### R5.5　EW/EMCON/通信效果（shadow → 总线）

- 干扰/欺骗/诱饵/假目标/静默/通信干扰/通信欺骗作为 `EWEffect` 进 EventBus；authority 环境帧统一结算；core 合并命令延迟/假批号标记。
- 无独立 EW 脚本；HUD 只显示告警摘要/独立窗。
- 验收：`v17_ew_probe`；效果公式/序列确定/无第二套威胁；EMCON 被动仍工作。
- 回退：legacy。

### R5.6　切换 `v2_authoritative`（默认候选）

- `state._fusion_tick` 在 v2 模式停用；adapter 把 `vm_contacts` 映射进 `state.tracks`；`set_sensor/set_emcon` 调 authority；HUD/plot 读同一视图；TWS/通道/信号/EW 全部来自 authority。
- **HUD/plot 视觉代码零改版**（仅数据来源）；V1 截图回归对比；`fw_contacts`/flow/tutorial/damage/replay 不受影响。
- 验收：三模式矩阵 probe；长跑（≥10 min 模拟）无双写、无等级回跳抖动；HUD 选中稳定；性能达标；回放/截图正常。
- 回退：设置 legacy；保留至少一个版本周期。
- 默认切换：验收通过后由 Lead 决定（`V17_SENSOR_AUTHORITY` 默认值改 v2 或保留 legacy）。

### R5.7　清理/降级

- 删除/隔离 V15 运行时融合（`sensor_model.detect*/update_track/age_track` 只允许出现在 legacy adapter/验证台）；HUD/plot 禁止引用；
- `docs/11` 与 `content/sensors.json` 对齐（数值冲突以数据表为准并更新 docs/11）；标记旧数值为参考；
- 保留 `legacy_v15` 回退路径与旧 probe；sensor_explorer 继续验证模型，不参与游戏；
- 最终验收/文档更新。

---

## 6　兼容/回退矩阵

| 场景 | legacy_v15 | shadow | v2_authoritative |
| --- | --- | --- | --- |
| HUD 现有视觉/坐标 | 不变 | 不变 | 不变（adapter 保证字段） |
| HUD 等级/身份来源 | V15 | V15（V2 仅 shadow） | V2 TrackTable |
| V2 显示数据 | advisory only | shadow 只读 | authority |
| `state.tracks` 写者 | V15 | V15 | adapter（唯一映射 V2，不判定） |
| 玩家传感器开关 | V15 | V15（V2 shadow 跑但不显示） | V2 authority（经 state 封装） |
| 教学/flow/damage/replay | 不变 | 不变 | 不变 |
| 截图/回放 | 不变 | 加对比日志 | 不变（V1 外观） |
| 出错回退 | 默认 | `legacy` | `legacy`（无需存档迁移） |

硬性检查：
- 同一 tick 不得同时出现两个写者（probe 用签名/写入计数器验证）；
- shadow 模式日志/dump 不得影响 UI 状态/回放；
- v2 模式缺失字段时 HUD 隐藏/降级（不伪造），probe 覆盖。

---

## 7　Probe / CI 清单（V17 落地）

### 7.1　现有必须保持

```powershell
# 路径以工作区为准；Godot 可执行文件见 tools/godot
godot --headless --path .\game_v17 --script res://tests/v17_bridge_probe.gd
godot --headless --path .\game_v17 --script res://tests/v17_core3_probe.gd
godot --headless --path .\game_v17 --script res://tests/plot_tws_probe.gd
godot --headless --path .\game_v16 --script res://tests/sensor_probe.gd
godot --headless --path .\game_v16 --script res://tests/snapshot_probe.gd
godot --headless --path .\game_v16 --script res://tests/sensor_bridge_probe.gd
godot --headless --path .\sensor_explorer --script res://tests/sensor_explorer_probe.gd
```

### 7.2　新增（R5）

| Probe | 覆盖 | 退出码 |
| --- | --- | --- |
| `game_v17/tests/v17_sensor_authority_probe.gd` | 模式状态机/唯一写者/shadow 隔离/字段来源/adapter 映射/重启 | 0/1 |
| `game_v17/tests/v17_entity_env_probe.gd` | 实体姿态/环境/LOS/光照/单位/确定性 | 0/1 |
| `game_v17/tests/v17_optical_ir_probe.gd` | docs/38 §5.7 + 通道窗 API | 0/1 |
| `game_v17/tests/v17_iff_probe.gd` | docs/38 §6.4 | 0/1 |
| `game_v17/tests/v17_elint_probe.gd` | docs/38 §7.4 | 0/1 |
| `game_v17/tests/v17_ew_probe.gd` | docs/38 §8.4 | 0/1 |
| `game_v17/tests/v17_hud_boundary_probe.gd` | HUD/plot 只读/无双套/隐藏规则 | 0/1 |
| `game_v17/tests/v17_replay_sensor_probe.gd` | 传感器/EW 事件进回放、只读 | 0/1 |

### 7.3　CI 矩阵

| 模式 | Env | 通过标准 |
| --- | --- | --- |
| legacy | `V17_SENSOR_AUTHORITY=legacy`（默认） | 现有 probe 全绿；旧截图/流程不变 |
| shadow | `V17_SENSOR_AUTHORITY=shadow` | shadow 隔离/对比断言；不允许写 V15 |
| v2 | `V17_SENSOR_AUTHORITY=v2` | 全量 R5 probe + HUD/flow/replay 回归 |
| skip tutorial/capture | `DSH_SKIP_TUTORIAL=1`/`DSH_SHOT` | 不阻塞截图/回归；authority 行为一致 |
| 回放 | `DSH_UI=fw_replay`/replay probe | 传感器事件/通道/EW 只读重放 |

Definition of Done（R5）：三模式可启动；legacy 视觉零改版；shadow/v2 probe 全绿；HUD/plot 无权威判定；事件/序列/存档可序列化；回退演练通过；`docs/11` 与数据表一致；无 commit 由 Lead 汇总。

---

## 8　风险与缓解

| 风险 | 症状 | 缓解 |
| --- | --- | --- |
| 双写（V15+V2） | 等级/身份跳变、HUD 与逻辑不一致 | authority 状态机 + 写者计数 probe；shadow 禁写；代码审查/CI grep |
| 时钟不同步 | 等级衰减/回放/暂停错位 | 单一 V2 时钟；V15 显示时钟 adapter；probe 对照 |
| 单位混用 | 相机/距离/协方差错误（已出现过） | 字段带单位/换算单点；单位 probe；禁止隐式换算 |
| 光学数据缺口 | FOV/口径/焦距无 canon 数值 | §5.1 定值先冻结，lore/设定签字；数据表驱动 |
| HUD 性能/视觉过载 | 新增细节压主线 | HUD 摘要/独立窗；V1 字号/坐标；probe 字段白名单 |
| 旧截图/回归失败 | 视觉改动 | authority 默认 legacy 直到 R5.6 验收；截图矩阵；adapter 保证字段 |
| ELINT/EW 直接改状态 | 第二套权威 | 只进 EventBus；效果由 authority/track core 结算；probe 断言 |
| 多站 ELINT 生成假接触 | 污染 HUD | 单站不产生接触；多站候选需确认；phantom/spoof 标记 |
| 回退不可用 | 线上问题无法恢复 | 每阶段 flag；`legacy` 保留一个版本；回退演练 |

---

## 9　待定/需 Lead 决策

1. **默认切换时机**：R5.6 验收后立即默认 v2，还是保留 legacy 默认一轮？
2. **光学数值签字**：§5.1 口径/焦距/FOV/像素为【定义】；需 lore-keeper/04/05 对齐后冻结。
3. **TWS overlay 去留**：authoritative 后 plot 的 TWS 环/球形是否仍由 `tws_bridge` viewer 生成（推荐），或转移到独立窗（HUD 减负）？
4. **IFF/ELINT 细节是否外显**：主 HUD 只 badge/count（推荐），完整窗在独立页；是否增加“信号页”新 HUD 组件？
5. **多站 ELINT**：本关是否提供第二 ELINT 平台/编队交叉定位演示？若没有数据，先留 API/probe 不接 UI。
6. **EW 可感知性**：玩家是否总能看到干扰源方位/类型，还是需 ELINT/受扰传感器发现（推荐后者）？
7. **V15 `sensor_model` 的去留**：保留 legacy + 验证台参考；是否在 R5.7 后从默认运行时移除（推荐保留回退一版）。
8. **迁移负责人/任务拆分**：见 §5 各阶段；与 R2/R3/R6、V17-CORE/UI 任务对齐。

---

> 本计划不实现代码；实现以 `docs/38` 为契约，每阶段先 probe、后接 UI、最后切权威。
