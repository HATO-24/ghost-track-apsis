# JC-A02 身份管道：写者/读者矩阵与四来源字段表（开工审计）

> 分支 `jc/a02-identity`，开工 SHA `1738a5e41509c09e04dc34da382dc07f4b8982e9`（含 A1 合并 `f62e5e6`）
> 基线：A1 `845584733df619feb3e372e8c06a7caa9f3fdaba`、G0/K0 `9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`
> 本文件为 A02 第 1 步交付：定位全部 `identity`/`manual_confirm` 写入点与读取点，给四来源字段表与红例计划。

## 1. 当前接入点（实测代码，非设想）

| 角色 | 位置 | 现状 |
|---|---|---|
| 计算器 | `scripts/core/identification_service.gd` | 全局 target 键；有 evidence/assessment/TTL/decay/manual/auto；`events/outbox` |
| 推进 | `GameSession._advance_identification` | 每 tick `set_time`+`step`/`auto_query_tick`，执行 query 请求 |
| 输出 | `GameSession._flush_identification_outputs` | **只发布 `identification.*` 事件**，不产生任何操作性身份写入 |
| IFF 查询 | `GameSession._execute_identification_query` | transponder 应答 → `identification_service.ingest`（全局、无 owner） |
| HUD 读 | `ShellBinder.ident_view` → `session.identification_get(tid)` | 读全局 assessment，不区分 owner |
| 火控读 | `combat_service._action_allowed` 使用 track 内 `identity` 字段 | combat track 的 identity 由外部 `register_track/update_track` 传入；session 未在 assessment 变化后同步 |
| TrackTable 身份 | `track_table._set_identity`（track evidence/observation 入口） | 全局表；直接接受来源 identity；与 identification assessment 是两条路径 |
| owner 情报 | `authority_intel`（A1） | 有 owner 航迹/融合/老化；**无 identity 写入面** |
| transponder | `transponder_service` | profile/interrogate/evidence；按内容配置，缺 profile 有明确 reason |
| EW | `ew_service`（经 session 白名单事件） | 事件可作 ELINT 证据，当前未归一进 identification |
| sensor | `sensor_service`（`_advance_sensors`） | 观测/证据走 track_table；identity 证据未归一进 identification |
| 存档 | `save_state/load_state` | `identification_service` 单实例快照；无 owner 维度、无待处理查询恢复 |

### 结论（缺口）

1. assessment **不落地**：Session 只发事件，操作性身份没有唯一写者。
2. 身份无 owner 维度：同一目标不同 owner 的证据会互相污染。
3. 四来源未归一：transponder 有入口，ELINT/光学/人工未统一进入计算器。
4. 消费者不一致：HUD 读全局 assessment，火控读 combat track 缓存，TrackTable 另有直写路径。
5. 恢复不完整：无 owner、无待处理查询、无 TTL 续算。

## 2. 目标写者/读者矩阵（A02 完成后）

| 数据 | 唯一写者 | 读者 |
|---|---|---|
| 原始证据（四来源） | `GameSession.ingest_identity_evidence(owner, raw)`（校验 owner/来源/时间/TTL） | owner 计算器；审计事件 |
| owner assessment | 每 owner 一个 `IdentificationService` 实例（复用既有算法） | Session 路由（仅此一处读 events 转写） |
| owner 操作性身份 | `authority_intel.apply_identity(owner, target, assessment)`（唯一写者） | HUD `ident_view`、列表/详情、火控投影 |
| IFF 查询/回执 | `GameSession.iff_query(owner, target, opts)`；状态由 evidence+assessment 派生 | HUD、探针、审计 |
| 人工确认 | `GameSession.identification_manual_confirm_for(owner, ...)`（要求 authority，写审计证据） | 计算器证据流、审计 |
| 火控身份投影 | `GameSession._sync_combat_identity(owner, target)`（消费者边界投影，非第二真值库） | `combat_service` ROE 门 |
| 存档 | Session：`identity_owners`（每 owner 服务快照）+ 待处理查询 + 旧单实例迁移 | 恢复、探针 |

## 3. 四来源字段表

| 来源 | source 值 | 关键字段 | 证据语义 | 备注 |
|---|---|---|---|---|
| IFF/应答机 | `transponder` / `iff` | `mode`(mode_a/c/s/5)、`status`(normal/off/faulty/captured/spoofed/crypto_fail/jammed)、`identity`、`confidence`、`spoofed`、`reply` | 回应声明≠真实阵营；无回应≠敌对 | 缺 profile → `unavailable`，不静默全友军 |
| ELINT/EW | `elint` / `ew` | `emitter_id`、`band`、`mode`、`confidence`、`jam`/`spoofed` | 发射源特征→怀疑度，不直接给 friend | 受干扰可降可信度 |
| 光学/传感器 | `optical` / `sensor` | `quality`、`range_km`、`bearing`、`visual_class`、`identity`(可空) | 弱证据不得单独成确定友军 | 与 track 观测同源时保持原始融合 |
| 人工 | `manual` | `authority`、`operator`、`identity`、`ttl_s`/`expire_t`、`reason`、`revoked` | 可审计授权证据；不直接改真值/ROE | 无 authority → 拒绝；撤销/过期后恢复推断 |

统一归一化字段：`owner_id, target_id, source, category, identity, confidence(0..1), observed_t, received_t, ttl_s, spoofed, mode, status, note`。
时间语义：`received_t >= observed_t`，`observed_t` 不得来自未来；TTL 从 `observed_t` 起算；同 tick 边界确定。
置信度比较容差 `≤1e-9`。

## 4. 红例计划（`integration.jc_identity_pipeline` 探针）

| # | 红例（当前必然失败） | 期望绿 |
|---|---|---|
| R1 | 同一证据 ingest 两次 | `duplicate=true`，操作性身份只写一次，无重复事件 |
| R2 | 四来源各自有效 | 每来源得到对应 assessment；confidence 容差 1e-9 |
| R3 | IFF friend + 光学 hostile 冲突 | identity 不为 friend，`state=conflict`，置信度下降 |
| R4 | 证据超过 TTL、同 tick 边界、迟到证据 | stale/expired 正确；迟到旧证据不覆盖新结论 |
| R5 | IFF 查询：有效回应/无回应/缺 profile/受干扰 | `valid/no_reply/unavailable/jammed` 四态；无回应不 hostile、不 friend |
| R6 | 人工确认未授权 / 授权 / 撤销 | 未授权拒绝；授权写审计且 `manual=true`；撤销后恢复推断；不改变真值 side、不自动给开火许可 |
| R7 | 两个 owner 同一目标不同证据 | 各自 assessment/操作性身份独立，不串域 |
| R8 | HUD 与火控读同一操作结果 | `ident_view.identity == combat 门看到的 identity`，且来自 owner 唯一写者 |
| R9 | 旧单实例存档迁移 + 真实文件恢复 + 10 tick | owner 维度恢复、待处理查询恢复、TTL/事件 ID 继续一致 |

红灯证据在实现前保存（probe 注册进 matrix，运行记录 FAIL 计数与断言名）。
