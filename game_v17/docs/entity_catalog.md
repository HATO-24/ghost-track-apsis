# Phase A1.1 · EntityCatalog — 实体静态元数据权威

> 对应 Issue #2 的实体元数据子任务；Phase A0 报告 `docs/55_PhaseA0_物理与信息权威基线调查.md` §C2。
> 本文件描述**已实现**的权威模型与消费边界（2026-10，Phase A1.1）。

## 1. 问题

Phase A0 证实：scenario 实体的静态资料（`side/identity/batch/ship_class/rcs_m2/
ir_signature/radius_km/has_pd/facility_id/transponder_profile`）在进入运行时后没有权威
承载层——`WorldState._normalize_entity()` 只保留 8 个基础字段，`PhysicsWorld` 只保留
运动学。结果：弹道/PD 静默使用 `radius_km=0.06`、`rcs=0`、`has_pd=false` 等错误默认值；
接触表对缺失信息回退 `side="friend"`；玩家界面可能把世界内部真值当成已知结论。

## 2. 权威模型

```text
scenario JSON / seed.entities（完整静态资料）
        │  GameSession.boot() 一次性构建（只读）
        ▼
EntityCatalog（id → 静态元数据；不存位置/速度）
        │
        ├─ GameSession.entity_metadata(id) / entity_metadata_ids() / entity_metadata_all()
        │      ├─ 弹道 / PD（_ballistics_states）：side/has_pd/rcs_m2/ir_signature/radius_km
        │      └─ 未来系统按 id 读取；缺失必须显式处理
        │
        └─ ✗ 不写 TrackTable / 不写 world / 不自动写玩家航迹或 UI

PhysicsWorld（位置/速度唯一权威；不含静态资料）
WorldState（既有 8 键事件状态；不是静态元数据权威）
TrackTable（玩家航迹；side/identity 只来自观测/证据/授权）
```

- `EntityCatalog` 在 `GameSession.boot()` 由 seed 构建，运行期只读；存档/读档通过 seed 重建。
- 缺失字段规范化为空串/0，**不猜测**；`entity_metadata("unknown")` 返回 `{found:false}`。
- 动态实体（earth/moon 等物理基准）没有 catalog 记录，消费方必须显式处理
  “无权威元数据”。

## 3. 弹道 / PD 契约

`GameSession._ballistics_states()` 从 catalog 读取尺寸与能力：

- `side`、`has_pd`、`rcs_m2`、`ir_signature`、`radius_km` 来自 `entity_metadata(id)`；
- 每个 state 增加 `metadata_found`（catalog 是否有该实体）与
  `radius_source`（`catalog` / `default`）；
- 只有 catalog 缺失或 `radius_km<=0` 时才回退 `_default_radius_km(kind)`，并标记
  `radius_source="default"`，避免把兜底尺寸当成真实尺寸；
- `pd_platform_id="own"` 的显式 PD 平台覆盖仍保留（行为不变）。

## 4. 玩家视图契约（truth ≠ 玩家判断）

`ShellBinder._build_contacts()`：

- **TRACK 行**：`side` 只由 `track.identity` 派生，`side_source="track_identity"`；
  `identity_source="track"`；不再回读世界实体 side。
- **ENTITY 行（无玩家证据）**：`side="unknown"`、`identity="unknown"`、
  `side_source="unknown"`、`identity_source="none"`；站点类型仅显示能力
  （`type="station"`），不代表友方。
- **设施行**：side 来自 `facility_registry`（内容/数据库），显式标记
  `side_source="facility_registry"`；identity 仍不自动填充。
- **SIGNAL 行**：signal target registry 的世界内部 side/name/batch 不再自动显示；
  保持 unknown。
- `binder.contacts` 中任何非设施行都不允许默认 `friend` 或泄露 catalog truth。

### 4.1 玩家显示字段（A1.1 聚焦修复：无证据不泄露真值）

每个 contact 行提供独立的安全显示字段，HUD 统一通过
`ShellBinder.contact_display(row)` 读取：

| 字段 | 含义 |
|---|---|
| `display_id` / `display_name` / `display_class` | 玩家可见 ID / 名称 / 类别（安全值） |
| `display_source` | 来源：`track` / `anonymous` / `anonymous_signal` / `facility_registry` / `ownship` |
| `entity_id` / `track_id` / `facility_id` / `signal_target_id` | **内部引用**（选择/传感器/交战/设施查询），不用于显示 |

规则：

- **TRACK**：`display_id = track_id`（航迹编号）、`display_name = "UNKNOWN TRACK"`、
  `display_class = "TRACK L<level>"`、`display_source = "track"`；不读取实体
  name/batch/ship_class。
- **ENTITY（无 track/证据）**：显示为匿名未知接触，`display_id = "UNKNOWN-<序号>"`
  （按实体 id 排序的确定性序号）、`display_name = "UNKNOWN CONTACT"`、
  `display_class = "UNKNOWN"`、`display_source = "anonymous"`；不显示实体
  id/name/batch/ship_class。无证据实体保留为匿名接触（不隐藏），内部
  `entity_id` 引用不变。
- **SIGNAL**：`display_id = "SIGNAL-<序号>"`、`display_name = "UNKNOWN SIGNAL"`、
  `display_class = "SIGNAL"`、`display_source = "anonymous_signal"`；signal target
  registry 的 world side/name/batch 不显示；内部 `signal_target_id` 保留。
- **设施注册表例外**：`display_id = facility_code`（或 transponder_code）、
  `display_name/display_class` 来自 `facility_registry` 公开字段、
  `display_source = "facility_registry"`；identity 仍不自动填充。这是唯一允许
  展示注册表公开内容并显式标记来源的例外。
- **本舰**：HUD 显示 `1000 / OWN SHIP / FLAGSHIP`，`display_source = "ownship"`；
  内部 `entity_id` 仍为真实本舰 id。
- 为兼容其它 UI 路径，legacy `id/name/cls` 同步为上述安全显示值；任何路径都不得
  从 world truth 回填 name/batch/ship_class/side/identity。

### 4.2 HUD 目标文案（光学 / COMMS / IDENT / 战斗 / 命令 / 融合日志）

所有面向玩家绘制的目标名称、编号与操作结果统一通过
`_target_display_text(internal_id)` / `_row_display_text(row)` /
`_display_for_internal(internal_id)` 生成；这些函数只返回 `display_*` 字段，
找不到内部引用时返回匿名值（`UNKNOWN · UNKNOWN CONTACT`），绝不回显内部 id。
内部引用（`_comms_target`/`_optical_target`/`_combat_target`/`entity_id`/
`track_id`）继续用于服务调用、选择、通信路由和交战，不参与显示。

覆盖路径：

- **光学/识别**：`ENTITY/TRACK` 行显示安全 display id + 航迹编号（无内部
  `target_id`）；`IFF` 消息与 transponder 回复行显示安全目标；trigger banner 同样。
- **COMMS**：标题、TARGET 标签、TYPE/SEND 结果、命令队列与详情中的 actor→target
  均显示安全目标；`_comms_target` 内部值不变。
- **IDENT**：INTERROGATE/IFF/CLEAR 结果文案使用当前接触的安全显示；融合日志
  target 列使用安全目标；IDENT 弹层标题使用 display_name。
- **战斗终端**：chips/TGT、目标列表、动作结果文案使用安全目标；`_combat_target`
  内部值不变。
- **交通/OTC**：占用行 occupant 显示安全目标。
- `hud_target_texts(row)` 返回上述实际文案生成函数的结果，供回归探针断言（不是
  只测 `contact_display` helper）。

> 世界内部仍知道 truth（战斗/PD 需要）；玩家视图必须通过观测/证据/授权链获得结论。

## 5. 回归探针

`game_v17/tests/a1_entity_metadata_authority_probe.gd`（matrix id
`integration.a1_entity_metadata_authority`）：

- 真实入口 `main_menu → v1_hud → ShellBinder → GameSession`（`DSH_BUILD=orbital_sim`）；
- 从 `scenario_orbital_sim.json` 直读 7 实体真值，逐实体断言 10 个静态字段可找回；
- 断言弹道/PD state 使用 catalog 值且 `radius_source="catalog"`；
- 断言 contacts 无证据时保持 `unknown`、无 `friend` 默认、无 truth side/identity 泄露；
- 断言玩家显示字段（`display_id/display_name/display_class/display_source`）与 HUD
  `contact_display(row)`：TRACK/ENTITY/SIGNAL 不得包含 truth 的
  name/batch/ship_class/side/identity/entity_id；设施注册表公开字段例外必须
  单独标记 `facility_registry` 并对照 registry 值；
- 断言 HUD **实际文案**：驱动 `_comms_action`/`_ident_action`/`_optical_action`
  并读取实际 `_comms_msg/_ident_msg/_optical_msg/_txp_msg`，以及
  `hud_target_texts(row)` 的 COMMS/光学/IDENT/融合/命令/战斗文案；内部真值哨兵
  不得出现、安全 display 必须出现、内部 `_comms_target/_optical_target/
  _ident_row.entity_id` 保持不变；
- 修复前该探针 FAIL（metadata API 缺失、默认值错误、friend 回退、显示字段缺失/
  泄露真值、HUD 文案泄露内部目标），修复后 PASS（720 断言）。

```powershell
.\run_tests.ps1 -Only '^integration\.a1_entity_metadata_authority$' -Ci
```

## 6. 边界与后续

- 本任务**不处理**：20 km/420 km 传感器几何绑定、world 位置同步、存档类型漂移、
  EW 消费者、HUD 重做、资产（属后续 A1/A2 任务）。
- 后续可把 `entity_metadata` 作为权威输入接入 SensorService 的目标几何绑定
  （Issue #4），但必须同时处理“观测/证据 vs truth”的显示契约。
