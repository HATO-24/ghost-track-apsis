# 联合战役 R2 数据/权限/情报契约（K0）

> 卡：JC-B00（#57）；状态：**K0 草案，待独立技术复核后解锁 JC-A01**
> 基线：C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`；G0 冻结后需重述 40 位 SHA
> 校验器：`game_v17/scripts/core/jc_contracts.gd`（`v17.jc.contracts.v1`，version 1）
> 探针：`integration.jc_contracts`（`game_v17/tests/jc_contracts_probe.gd`）
> fixtures：`game_v17/tests/fixtures/jc_contracts/`

本文只定义**契约**：字段、唯一写者、读者、单位、时间、可见域、存档迁移与拒绝原因。
本卡**不实现**部署、战斗、AI、裁决；校验器是语义校验器，**不是**完整 JSON Schema 引擎。

## 1. 权威划分（唯一写者）

| 数据 | 唯一写者 | 读者 | 说明 |
|---|---|---|---|
| 战役/战区内容（campaign_id、目标定义） | 内容配置（scenario/JSON） | 战役运行层、B03 裁决 | 静态内容，不入运行态存档 |
| 舰级静态数据（ship_class、config_revision） | `EntityCatalog` / `ShipCatalog` | 部署、火控、UI | **不**把静态舰级当运行态保存 |
| 编制名册（fleet_id、roster、domain 归属） | 编制服务（`FleetFormation` 扩展） | 部署、协同、情报 | 名册≠实例 |
| 部署实例（entity_instance_id、生命周期） | 部署服务（JC-B01A） | 战斗、感知、存档 | 稳定实例 ID 关联单舰 |
| 单舰装备/弹药/燃料/冷却/损伤/命令账本 | 各舰账本（B1b） | 火控、UI | 每舰唯一账本，**禁止共享** |
| 世界运动学（位置/速度） | `PhysicsWorld` | 感知几何、投影 | bary_rot / km / km/s |
| 操作性航迹（证据/融合结果） | `TrackTable`（或指定证据入口） | UI、火控 | 分方情报各自融合 |
| 事件 ID/seq | `EventBus` | 全部 | 唯一分配器 |
| 观测与共享（owner/observed_t/received_t） | 感知服务 + 情报域 | 各 owner 的 TrackTable | 延迟共享必须显式 |
| 指挥直控/ROE（controller_id、roe） | 指挥授权（Session 权限层） | 命令校验、AI | 阵营≠直控 |
| 目标权威裁决 / 玩家获知状态 | 战役裁决（B3） | UI、战报 | **两个字段，不能混用** |

## 2. 字段表（类型 / 单位 / 时间 / 可见域 / 迁移 / 拒绝原因）

### 2.1 指挥域 `command_domains[]`

| 字段 | 类型 | 单位/取值 | 唯一写者 | 可见域 | 拒绝原因 |
|---|---|---|---|---|---|
| `domain_id` | String | 稳定 ID | 指挥授权 | 全局 | 空/重复 |
| `kind` | String | `player`/`ai_ally`/`ai_hostile` | 指挥授权 | 全局 | 非法枚举 |
| `controller_id` | String | 直控者 | 指挥授权 | 全局 | 空/重复（不同域不得共用直控） |
| `intel_owner_id` | String | 情报拥有者 | 情报域 | 全局 | 空 |
| `faction` | String | 阵营标签 | 内容配置 | 全局 | 空（阵营必须与直控分开） |
| `roe` | String | 交战授权 | 指挥授权 | 全局 | 空（不接受隐式默认） |

**硬约束**：`faction`、`controller_id`、`intel_owner_id`、`roe` 是**四个独立字段**；
`friend` 不赋予直控，也不赋予全部观测。

### 2.2 舰队 / 实例

| 字段 | 类型 | 说明 | 拒绝原因 |
|---|---|---|---|
| `fleet_id` | String | 编制 ID，**不是** entity_id 替代品 | 空/重复/引用未知 domain |
| `roster[].entity_instance_id` | String | 名册成员 | roster 空、成员不属于本 fleet |
| `entity_instance_id` | String | 单舰稳定实例 ID | 空/重复 |
| `domain_id` | String | 实例所属指挥域 | 与 fleet 的域不一致（**跨域指挥拒绝**） |
| `ship_class_id` | String | 静态舰级引用 | 空（静态数据必须来自 catalog） |
| `ship_class_config_revision` | int | 正整数 | 非整数/越界 |
| `deployment_state` | String | `DRAFT`/`VALIDATED`/`DEPLOYED` | 非法枚举 |

命名舰唯一、通用舰体可重复 → **重复的是 `entity_instance_id` 必须被拒绝**。

### 2.3 部署清单 `deployments[]`

| 字段 | 类型 | 说明 | 拒绝原因 |
|---|---|---|---|
| `entity_instance_id` | String | 已部署实例 | 未登记/未 `DEPLOYED` 就进清单 |
| `request_id` | String | 幂等键 | 缺失（重复请求必须幂等） |
| `from_state`/`to_state` | String | 生命周期迁移 | 非单步前进（只允许 DRAFT→VALIDATED→DEPLOYED） |
| `t` | float | 模拟秒 | 非有限/负 |

### 2.4 观测共享 `observation_shares[]`

| 字段 | 类型 | 单位 | 说明 | 拒绝原因 |
|---|---|---|---|---|
| `source` | String | — | 证据来源 | 空 |
| `observer_id` | String | — | 观测者 | 空 |
| `intel_owner_id` | String | — | **情报拥有者** | 空（不得默认全局） |
| `target_entity_instance_id` | String | — | 目标实例 | 未知实例 |
| `observed_t` | float | 模拟秒 | 几何采样时刻 | 非有限/负 |
| `received_t` | float | 模拟秒 | 融合/路由接收时刻 | 非有限/负；**早于 observed_t 拒绝** |
| `delay_s` | float | 秒 | 共享延迟 | 非有限/负 |
| `path` | String | — | 共享路径 | 空 |

**语义**：几何保留 `observed_t`；融合/路由时间单调；**不得**用投递时的真值替换旧观测。

### 2.5 命令 `commands[]`

| 字段 | 类型 | 说明 | 拒绝原因 |
|---|---|---|---|
| `command_id` | String | 命令 ID | 空/重复 |
| `actor_id` | String | 发起者 | 空 |
| `controller_id` | String | 直控者 | 空；与域直控不一致（跨域指挥） |
| `domain_id` | String | 指挥域 | 未知域 |
| `shooter_id` | String | **显式子实体** | 空或无效（**禁止退回旗舰**）；不在该域内 |
| `legacy_context` | String | 旧调用兼容 | 只允许 `own_ship`；不得扩成所有友舰 |

### 2.6 目标 `objectives[]`

| 字段 | 类型 | 说明 | 拒绝原因 |
|---|---|---|---|
| `objective_id` | String | 目标 ID | 空/重复 |
| `target_entity_instance_id` | String | 目标对象 | 未知实例 |
| `threshold` | int | 非负整数 | 非整数/负 |
| `authority_state` | String | **权威裁决状态** | 缺失 |
| `player_known_state` | String | `unknown`/`suspected`/`confirmed`/`disabled` | 非法枚举 |
| `story_independent` | bool | `story=false` 仍裁决 | 显式 false |

### 2.7 单舰账本 `ledgers[]`

| 字段 | 类型 | 单位 | 拒绝原因 |
|---|---|---|---|
| `entity_instance_id` | String | — | 未知/重复账本 |
| `units.mass` | String | **kg** | 非 kg |
| `units.fuel` | String | **kg** | 非 kg |
| `units.delta_v` | String | **km/s** | 非 km/s |
| `mass_kg` | float | kg | 负值 |
| `ammo`/`fuel_kg`/`cooldown_s_count` | int | 个 | 非整数/负 |
| `resource_owner_instance_id` | String | — | **指向别舰拒绝** |

**单位契约**：旧名册 mass/fuel 为 **t**，PhysicsWorld 为 **kg**，
换算固定 `×1000` 且**只做一次**（`Contracts.tons_to_kg()`）；Δv 统一 km/s。

## 3. 时间与延迟

- 模拟秒；与场景 UTC 历元分开（A-02 契约）。
- 新延迟链必须分 `observed_t` / `received_t`：几何保留采样时刻，融合/路由时间单调。
- 同采样时刻差 ≤1e-6 s；同源投影位置 ≤1e-9 km、速度 ≤1e-12 km/s；确定性几何 ≤1e-6 km/deg。
- 质量/置信度 ∈ [0,1]，确定性比较 ≤1e-9。

## 4. 存档与迁移

| 情形 | 策略 |
|---|---|
| 新档 | 携带 `schema`+`version`；本契约字段按版本身份校验 |
| 旧档缺 `campaign`/`fleet`/`instance` 段 | 按 legacy scope 处理：**不虚构**部署实例、不推断友军指挥域 |
| 旧调用缺 `shooter_id`/`controller_id` | 只映射**本舰**语义（`legacy_context=own_ship`），不得扩成友舰 |
| JSON 数字 | 按数值语义/安全范围校验；恢复后契约整数必须是真 int，不全局转 int |
| 未知 `version` | 明确拒绝，不降格为旧档 |

## 5. 拒绝原因（负例矩阵，已被 `integration.jc_contracts` 覆盖）

| 负例 | 期望原因 |
|---|---|
| 重复 `entity_instance_id` | `重复 entity_instance_id` |
| 实例域与舰队域不一致 | `跨域指挥` |
| 缺/无效 `shooter_id` | `shooter_id` |
| 账本资源指向别舰 | `资源引用别舰` |
| 缺单位（fuel/mass/delta_v） | `单位` |
| 未知 version | `version` |
| `observed_t > received_t` | `observed_t` |
| 非整数 threshold | `threshold` |
| 未 DEPLOYED 就进部署清单 | `部署清单` |
| 旧调用扩成所有友舰 | 旧调用不能扩成所有友舰 |

## 6. 已知边界（本卡不做）

- 校验器**不是**通用 JSON Schema 引擎（不支持 `$ref`/`oneOf` 等）。
- 不实现部署/战斗/AI/裁决；不生成“已完成”战役快照。
- 字段值中的舰级名、编制规模、目标阈值均为**提案**，最终由 JC-B03P 提出后交用户核对。
- `authority_state` 的枚举只需存在且非空；完整状态机在 B3。
- 分方情报存储方案（每 owner 独立 TrackTable vs 显式分区）在 JC-A01 定案；
  本契约只要求 `intel_owner_id` 必填且延迟显式。

## 7. 退出条件（K0）

1. `integration.jc_contracts` 全绿（当前 39/0）且已入矩阵；
2. 独立技术复核确认「阵营/直控/情报/ROE」四者真正分开；
3. G0 冻结后重述基线 SHA，并核对无字段漂移；
4. 之后才解锁 JC-A01。

---

## 8. R6 返修：冻结项与拒绝面（2026-10-26）

### 8.1 actor → controller → shooter 授权链（冻结）
- 每个指挥域必须声明 `authorized_actors`（显式名单）；
- 命令 `actor_id` 必须在该域名单内，`controller_id` 必须等于域直控；
- `shooter_id` 必须是该域已登记实例，**禁止退回旗舰**；
- 旧调用 `legacy_context=own_ship` 必须同时给出 `own_entity_instance_id` 且 `shooter_id == own`；
- **玩家填 `ally_ai` 直接 fire 盟军舰船 → 拒绝**（actor 不在 ally 名单 / controller 不符 / shooter 跨域，三重拦截）。

### 8.2 情报共享与延迟（冻结）
- `observer_id` 必须是已登记实例；
- `intel_owner_id` 必须是某域的 `intel_owner_id`（不接受任意字符串）；
- 共享必须有 `share_authorized_by`，且**必须等于**该情报拥有者；
- `received_t - observed_t` 必须与 `delay_s` 一致（≤1e-6 s），否则拒绝；
- 分方情报方案冻结为 `intel_partitioning = per_owner_track_table`（每 owner 独立 TrackTable）。

### 8.3 AI 只读视图（冻结）
- `ai_read_view.reads_ground_truth` 必须为 `false`；
- 每个域只能声明**本域** `intel_owners`；
- 不允许 AI 直读世界真值/敌方全量状态。

### 8.4 选择 → 部署映射（冻结）
- 实例必须显式 `selected: bool`；
- 只有 `selected=true` 且 `deployment_state=DEPLOYED` 的实例可进部署清单；
- 所有 `selected` 实例必须逐一出现在部署清单；
- `request_id` 必须存在且唯一；同一 `request_id` 携带不同载荷 → **幂等键冲突拒绝**；
- `roster` 成员必须是本舰队已登记实例。

### 8.5 生命周期 / legacy scope（冻结）
- `event_lifecycle` 固定 6 阶段：`created → observed → shared → received → executed → closed`；
- `legacy_scope.own_ship_only = true`；`unknown_campaign_behavior ∈ {reject, legacy_tag}`。

### 8.6 单位与数值（区分连续与计数）
- 连续物理量：`mass_kg` / `fuel_kg` / `delta_v_kmps` —— 有限、非负、≤1e15；
- 整数计数：`ammo` / `cooldown_s_count` —— **不接受浮点**，非负、≤2^53-1；
- 必要字段缺失即拒绝（不再"缺了就当 0"）；
- JSON 数字按值语义比较；契约整数必须是真 int。

### 8.7 探针
`integration.jc_contracts` 覆盖上述全部拒绝面，当前 **64/0**；负例 fixture 17 个。
