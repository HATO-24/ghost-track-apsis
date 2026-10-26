# DS-A-00 · 断言契约映射表（I0）

> 本文件是 DS-A-00「现有 PR 依赖与契约协调」的交付物之一：把 T22 原有的断言口径与
> Phase A 协调后的产品语义逐项对齐，并给出等强度负例。
>
> - 整合候选 **I0** = `b9101c8369c44dc293e579701efa0a4029d28dec`
>   （S0 `4b0b102` + merge P20 `7a4f325`（含 P17 `5bb763d` + P19 `8c1483a`）+ merge T22 `8bf7517`）
> - 本文件只记录**测试契约**；不改游戏源码、不改默认 profile、不把 Phase A 并入 Phase 0。

## 0. 为什么需要协调

T22（PR #22）的 A0-T2 探针把「静态字段必须复制到所有容器」当作需求，A0-T3 把
「`JSON.parse` 之后 `seq is int`」当作需求。这两条与 Phase A 的权威模型冲突：

| 冲突点 | T22 旧口径 | Phase A 权威模型 | 后果 |
| --- | --- | --- | --- |
| 静态元数据位置 | physics/world/snapshot/track/contact **都必须**带 `side/batch/rcs/radius/has_pd` | **EntityCatalog** 是静态信息唯一权威；PhysicsWorld 只写运动学；WorldState/snapshot 是投影 | 旧口径通过 = 强制把真值复制进玩家视图 → **反向制造泄漏** |
| JSON 数字类型 | 解析后 `seq` 必须是 `int` | JSON 数字解析为 `float` 是正常现象；应校验**数值语义**，恢复后才是运行时类型 | 旧口径会逼实现改存档格式；且掩盖真正的运行时类型漂移 |

因此 A-00 先改测试契约，再由后续卡修真实缺陷。

## 1. 映射表

列说明：**旧断言位置** → **产品语义** → **权威字段/读者** → **新断言** → **保留/新增负例** → **改变理由**。

### 1.1 静态元数据（A0-T2 `a0_entity_metadata_pipeline_probe.gd`）

| 旧断言位置 | 产品语义 | 权威字段 / 读者 | 新断言 | 保留 / 新增负例 | 改变理由 |
| --- | --- | --- | --- | --- | --- |
| 旧 step 3 `PhysicsWorld exposes all static metadata fields for 7 entities` | 位置/速度由物理写，静态特征不属于物理状态 | `physics_state()[r,v,...]`；读者：弹道、航迹几何 | **删除**，改为 step 4「运动容器可省略静态字段，但**一旦声明必须等于 catalog**」 | 新增：容器声明了错误静态值 → 违例 | 原有断言要求物理容器复制静态真值，与「PhysicsWorld 只写运动学」冲突 |
| 旧 step 4 `WorldState carries all static metadata fields` | WorldState 是事件状态 / 运动投影 | `world.entity()[id,kind,name,pos_km,vel_kmps,flags,alive,version]` | 同上，并入 step 4 容器检查 | 同上 | 同上 |
| 旧 step 5 `snapshot().entities carries all static metadata fields` | 合成视图应**说明字段来源**，不必复制全部静态字段 | `snapshot().entities[]` + 新增 `snapshot().entity_catalog` 来源块 | step 5：snapshot 实体必须是含 `pos_km` 的运动投影；声明了的静态字段必须 catalog-exact；且 **snapshot 必须暴露 `entity_catalog` 来源块** | 新增：snapshot 声明错误静态值 / 缺 catalog 来源块 → 失败 | 原口径要求复制，新口径要求「可追溯来源」 |
| 旧 step 6 `tracks carry all static metadata fields` | TrackTable 只接观测/证据 | `track_table.vm().tracks[]`；读者：玩家 contacts/HUD | **反向**：step 7「tracks **不得**泄漏 `batch/rcs_m2/radius_km/has_pd`」 | 新增：track 出现 truth-only 字段 → 违例（I0 实测命中 2 条：`batch`） | 旧口径会把真值泄漏写成期望 |
| 旧 step 7c `contacts carry all static metadata fields` | 玩家 contacts 必须匿名化 | `binder.contacts[]`；例外：本舰 / 有公开记录的设施（`facility_id` 非空）且声明来源 | **反向**：step 8b「contacts 不得泄漏 truth-only 字段」；例外必须有来源声明 | 保留原 silent-friend 负例；新增 truth 泄漏负例 | 同上 |
| 旧 step 7d `contacts expose batch for traceability` | `batch` 是真值/内部信息 | — | **删除**，改为 8c「玩家可见字段必须声明 `side_source`/`identity_source`/`display_source`」 | 新增：缺来源声明 → 失败 | 旧断言直接要求泄漏 truth |
| 旧 step 8 五层 × 7 实体 × 6 字段透传矩阵 | 各层职责不同，不能统一要求透传 | — | **删除**统一矩阵，改为 5 个独立契约断言（catalog / 容器不伪造 / snapshot 来源 / 玩家不泄漏 / 来源声明） | 见各步 | 统一矩阵无法表达分层职责 |
| （新增） | 静态特征必须能被内部消费者按稳定 ID 取到 | `entity_catalog.get_entity(id)`；读者：弹道、识别、facility registry | step 3：catalog 对 7 实体 × 6 字段**精确等于 scenario truth**，且 `id` 稳定 | **新增 3 个负例**：字段丢失、ID 互换、radius 兜底冒充 catalog | Phase A 协调后 catalog 是唯一权威，必须直接验收 |
| （新增） | 弹道必须读 catalog，不得静默兜底 | `combat_ballistics` 的 catalog 引用 + `radius_km/rcs_m2/has_pd` | step 6：弹道持有 catalog 引用，且 7 实体取值等于 catalog | 新增：无 catalog 引用 / 取值不符 → 失败 | 修复 A0 调查记录的「radius 兜底」缺陷 |

### 1.2 事件序号（A0-T3 `a0_save_roundtrip_authority_probe.gd` step 5）

| 旧断言位置 | 产品语义 | 权威字段 / 读者 | 新断言 | 保留 / 新增负例 | 改变理由 |
| --- | --- | --- | --- | --- | --- |
| 旧 5a `save.bus.events[i].seq` 必须 `is int` | 存档里的 JSON 数字是**载体**，不是运行时类型 | 存档 JSON 数字；读者：恢复器 | **改为数值语义**：有限、整数值、落在 `0..2^53-1`、事件 `seq ≥ 1`、**严格递增** | 新增 4 个负例：负数 / 零 / 分数 / 越界；并验证合法值 `1` 不被误拒 | 不依赖 JSON 数字的 Variant 类型，避免逼实现改存档格式 |
| 旧 5a 同样作用于 `bus.seq` | 高水位 | `save.bus.seq` | 同一数值契约（允许 `0`） | 同上 | 同上 |
| 旧 5b `loaded.bus.events[i].seq` 必须 `is int` | 恢复后才是运行时类型判据 | `session.bus.events[]`（内存） | **保留并加强**：必须是真正的 GDScript `int` | 保留类型漂移负例（I0 实测命中 27 处） | 这正是 A0 C4 记录的真实缺陷，不能删 |

> A-00 明确**不删除**恢复后的类型断言（任务卡要求）；只把「原始 JSON」与「运行时」两个
> 边界分开，前者用数值契约，后者用运行时类型契约。

### 1.3 未在本卡调整的断言

| 断言 | 原因 |
| --- | --- |
| A0-T1 的 `track range matches physics truth within 0.5 km` 等全部检查 | P20 链修复了几何绑定后该探针 **PASS 45/0**；断言未放宽，是真实的实现修复导致的转绿 |
| A0-T1 identity/threat/side 四类检查 | T22 已按 GPT 审查补齐，本卡保留原强度 |
| A0-T3 physics/world/track 数值往返、canonical equality、传感器 EMCON/channels | 本卡保留原强度，仅新增协调后的 seq 契约 |
| Phase 0 的 6 个 gate case 与 8 项 legacy baseline | 任务卡禁止改动；I0 实测仍 6/6 与 8 项 FAIL |

## 2. 负例覆盖（等强度）

| 负例 | 位置 | 验证方式 | I0 实测 |
| --- | --- | --- | --- |
| catalog 字段丢失 | A0-T2 step 9a | 用 fixture 行删掉 `rcs_m2`，`_authority_field_violations` 必须报违例 | 检出 1 处 |
| catalog ID 互换 | A0-T2 step 9b | 把 harmattan 的数据挂在 raider_2 的 ID 上比较 | 检出多处 |
| radius 兜底冒充 catalog | A0-T2 step 9c | 用假 `radius_km=1.0` 的行与 catalog 真值比较 | 检出 3 处 |
| 玩家 contacts 泄漏 truth | A0-T2 step 9d | 注入带 `batch/rcs/radius/has_pd` 的 contact 行 | 检出 4 处 |
| 未知目标变 friend | A0-T2 step 9e | hostile truth 的实体验证 friend 判定 | 检出 |
| 非法 seq 形态 | A0-T3 step 5c | 负数/零/分数/越界必须被同一判据拒绝；合法 `1` 必须通过 | 全部按预期 |
| 运行时 seq 类型漂移 | A0-T3 step 5b | 读档后逐事件检查 `is int` | 检出 27 处（真实缺陷） |

## 3. 命令与证据

```powershell
# Phase A 专项（不带 baseline，单跑）
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-00/phaseA

# Phase 0 门禁（必须 6/6）
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-00/phase0

# 全量矩阵（双 baseline）
pwsh -NoProfile -File ./run_tests.ps1 -Ci `
  -Baseline game_v17/tests/known_baseline_failures.json `
  -BaselineExtra game_v17/tests/phasea_baseline_failures.json `
  -ResultsDir .test-results/phase-a/cards/DS-A-00/full
```

I0 实测结果：Phase 0 **6/6 PASS**；Phase A **1 PASS / 2 FAIL**
（`a0_track_truth_authority` 45/0、`a0_entity_metadata_pipeline` 26/4、
`a0_save_roundtrip_authority` 37/4）；全量 **78 = 68 PASS / 10 FAIL**，
两份 baseline 均 `new_fail=0 drift=0 complete=true`。
