# JC-A02（#59）多来源身份收敛与 IFF 闭环 · 交付报告

> 分支 `jc/a02-identity`；开工基线 main `1738a5e41509c09e04dc34da382dc07f4b8982e9`（含 A1 合并 `f62e5e6f`）
> A1 冻结 `845584733df619feb3e372e8c06a7caa9f3fdaba`；G0=K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`
> 环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows

## 1. 写者/读者与四来源字段表

见 `JC_A02_writer_reader_matrix.md`（开工审计 + 目标矩阵 + 四来源字段表）。

## 2. 实现（唯一写者图）

```
四来源证据
  IFF/应答机 ─┐
  ELINT/EW  ─┤   identity_ingest(owner, raw)
  光学/传感器 ─┼─→ 归一化(owner/来源/observed_t/received_t/TTL/confidence/spoof)
  人工确认   ─┘        │
                       ▼
        每 owner 一个 IdentificationService 实例（复用既有算法）
                       │ 仅 Session._route_identity_assessment 读 assessment
                       ▼
        authority_intel.apply_identity(owner, target, patch)   ← 唯一操作性身份写者
                       │
        ┌──────────────┴───────────────┐
        ▼                              ▼
  HUD `ident_view`（owner facade）   火控 `_sync_combat_identity`（消费者投影）
```

- **owner 维度**：`_identity_owners` 每 owner 独立计算器；本舰 owner 复用现有 `identification_service`（旧接口兼容）；未知 owner 拒绝。
- **单一写者**：assessment 只经 Session 路由一次写入 `authority_intel.identity_store` 并投影到该 owner 航迹；同一结论不重复写（`writer_count` 可观察）。
- **四来源归一**：`transponder/iff`、`elint/ew`、`optical/sensor`、`manual`；统一字段 owner/target/source/identity/confidence/observed_t/received_t/ttl_s/spoofed/mode/status/category/note。
- **真实通道接线**：
  - `_bridge_identity_evidence` 从 track evidence 走 owner 归一化入口（不再直写全局单实例）；
  - `_execute_identification_query` 的应答/无回应证据走 owner 入口；
  - `_install_scenario_transponders`：scenario 实体 `transponder_profile` 按实体装入应答配置（声明身份默认 unknown，不用隐藏 side/identity 解题；缺配置保持 `unavailable`）。
- **IFF 状态**：`valid / no_reply / unavailable / jammed / pending`（+ assessment 冲突 `conflict`）；无回应不 hostile/friend；回应声明不等于真值。
- **人工确认**：需要 authority（command/co/captain/tactical/watch_officer），写入 `identity_audit`，操作性身份带 manual/authorized/audit_ids；撤销后恢复推断；不覆写真值、不自动给开火许可。
- **TTL/迟到**：证据 ttl 随记录保存；`identity_advance` 与读路径共同刷新 stale/expired；迟到旧证据（observed_t 早于已采纳最新证据）标记 `late_ignored` 且不改写当前结论。
- **恢复**：`identity_owners`（非本舰 owner 计算器状态）+ `identity_pending_queries` 随档；旧档只有 `identification_service` 单实例 → `legacy_single_owner` 迁移到本舰 owner；`identity_restore_mode` 公开。
- **火控一致性**：`request_fire` 在 ROE 门前把 owner 操作性身份投影到 combat track；`combat_identity()` 与 HUD 读同一记录。

## 3. 验收与红绿证据

`integration.jc_identity_pipeline`（已注册 matrix）：

| 覆盖 | 断言要点 |
|---|---|
| 单一写者/去重 | 相同证据 duplicate=true；一次有效证据只产生一次身份写入；owner 航迹身份来自唯一写者 |
| 四来源 | IFF/ELINT/光学/人工各自可得对应结论；置信度与评估一致（≤1e-9） |
| 冲突 | IFF friend + 光学 hostile → 不维持 friend、`state=conflict`、记录 contradictions |
| TTL/迟到 | TTL 内 valid、超时 stale/expired、新证据刷新；迟到旧证据 late_ignored 且不改写结论 |
| IFF 六态 | 有配置可查、无配置 `unavailable`、受干扰/遮挡有明确状态；无回应不敌对不友军；scenario profile 按实体装入且声明不静默成友军 |
| 人工 | 未授权拒绝（unauthorized）且不改变身份；授权确认 audit_ids、manual/authorized；不覆写真值；撤销后恢复推断 |
| owner 隔离 | 同一目标 player=friend / ally=suspect（单源未授权 hostile 收敛为 suspect），未知 owner 拒绝；不串域 |
| HUD/火控 | `identity_operational` == `combat_identity` == `ident_view`；人工 friend 后仍不自动给开火许可，拒绝原因非授权缺失 |
| 恢复 | 真实文件恢复后 player/ally 身份一致；继续 10 tick 身份/状态/置信度一致；旧档迁移模式 `legacy_single_owner` |

红/绿：
- 红例（实现前，stub API）：**16 PASS / 43 FAIL，退出 1**；
- 绿（实现后）：**66 PASS / 0 FAIL，退出 0**。

## 4. 专项、门禁、C 回归（同一 SHA）

```
专项 7 项：7/7 PASS
  jc_identity_pipeline 66/0 · identification 310/0 · transponder 272/0
  track_table 161/0 · sensor_persistence 86/0 · event_continuity 89/0 · save_roundtrip 41/0
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 见证据目录 full-summary.json（期望 89 = 82 PASS / 7 历史 FAIL、new_fail=0）
```

7 项历史失败未刷新 baseline；未移出 matrix；未放宽负例。

## 5. 限制 / NOT RUN

- 不开发真实 RF/密码学或完整军用 IFF 模式；应答配置为声明模型。
- 未新增 AI/EW/逐舰账本；EW/ELINT 只保留正常证据通道，不实现 EW 新特性。
- Linux/macOS、非 headless 真实渲染、人工可读性、>1000 tick 成本：NOT RUN。
- UI-01 文案/HUD 文件排程仍按 61 号队列与 A02 串行，本卡未改 UI 布局。

## 6. PR69 复核五组返修（真实路径）

| 组 | 修复（最小接线，不改计算器算法） | 正式 probe 断言 |
|---|---|---|
| R1 来源/owner/去重 | 证据事件携带可信 `owner_id`（真实查询/桥接/路由），无 owner 的 legacy 才回退本舰；同一事件 `<event_id>\|<owner>` 只消费一次；track.evidence 先入身份管道再交 TrackTable；四来源 category 显式映射（ELINT 不再被写成 iff） | ally IFF 查询不写本舰 owner；默认/显式 mode 同一回复仅 1 条证据；真实 `SEVD-000001` ELINT 证据 source/category/evidence_type 均保留 |
| R2 人工权限/审计 | Binder 旧入口、新旧公开入口、日志重放统一走受信 `identity_manual_confirm/clear`：authority 白名单 + owner 域授权 actor（非本舰 owner 必须显式 actor）；审计记录 id/actor/authority/operator 并入操作性身份 audit_ids；旧入口不再直写旧计算器 | Binder 旧确认可用且有审计；不可信 caller 不能写 ally owner；Binder 撤销需受信权限并清 manual |
| R3 HUD 航迹键 | `_identity_resolve_target`：owner 身份/owner 航迹 track_id/entity_id/combat track 字段/sensor 映射逐级解析；匿名显示 ID 不参与路由，内部 ID 不改写；火控同步按实际 combat 键投影 | T0001→raider_2 解析到同一 owner friend；request_fire 后实际 T0001 航迹也被投影，不再因未知身份停 unknown_track |
| R4 TTL/迟到 | 有效性先算后统一别名（`valid/validity/effective_identity` 同源）；过期时火控用 effective 身份、HUD 显示 expired 并保留 last-known；迟到证据只记审计、**不进入计算器**，不再污染下一 tick 重算 | 过期后 validity=expired、effective=unknown、HUD valid=false、火控 unknown 且保留 last-known；迟到旧证据标记 late_ignored 且下一 tick 结论不变 |
| R5 IFF 状态分离 | `identity_state`（assessment：valid/conflict/manual/unknown）与 `identity_iff_state`（传输：not_queried/pending/valid/no_reply/unavailable/jammed/expired）分开字段、分别写入；查询状态按实际 transponder 回复原因，请求 jam 不冒充实际阻断；实现真实延迟查询队列（pending→ETA 到达）并随档恢复 | 冲突不被 IFF 回复覆盖；occluded 记 no_reply/reason=occluded；延迟查询 pending→到达到结果；队列随档恢复后按 ETA 到达 |

正式 probe 断言数：66 → **110**（新增 44 条真实入口断言）；`integration.jc_identity_pipeline` **110/0**。

## 7. PR69 第二轮：两处实际 HUD 消费者收尾（R3/R4）

### R3 真实 HUD 航迹键（空映射字段）

- 根因：真实 `_seed_combat_tracks` 种入的 combat 行只有 `id/batch`，`entity_id/ship_id` 为空；原 `_entity_for_track` 未反查已验证 `_sensor_track_map`，新 resolver 只覆盖"字段预填"分支。
- 最小修复：`_entity_for_track` 增加 sensor target→track 反查；`_identity_resolve_target` 增加 `entity_hint`（`request_fire` 已合法解析出的 `target_entity` 优先）；`_sync_combat_identity(target_id, entity)` 把解析结果用于实际 combat 键投影。
- 正式断言（真实路径，无手工预填）：radar 6s → 真实 sensor 映射 → 实际 HUD 式 `register_track(T0001,{id,batch})` → 合法本舰人工 friend → `combat_identity(T0001)` 得 friend/resolved_key=raider_2/via=sensor_map；`request_fire(T0001,...)` 后实际 combat T0001 航迹被投影 friend，不再 unknown_track。预填字段行与实体键兼容正例保留。

### R4 实际 HUD 显示消费有效性

- 根因：`ident_view` 新增字段后，实际 HUD 普通显示仍读原始 `identity`；普通联系人路径也用 owner 原 identity 生成 side/type/ident。
- 最小修复：
  - `ident_view`：过期时普通 `identity=unknown`、`last_known_identity` 保留历史、`warn=true`、`tag=EXPIRED·…`；stale 用 `effective_identity` 并标记 STALE。
  - 普通联系人 `_build_contacts_from_intel`：过期行 identity/side/type 归 unknown，保留 `validity/valid/last_known_identity` 字段供详情。
- 正式断言：TTL5 到 t11 后 `ident_view.identity=unknown`、`last_known_identity=friend`、warn、tag 含 EXPIRED；`binder.contacts` 过期行 identity=unknown、validity=expired、last_known=friend；火控仍用 unknown（上轮已绿）。不重做 TTL/置信度算法，不强制 stale 一律 unknown（state 评估态与 validity 时效分离按新合同保留）。

### 结果（同一 SHA）

```
专项 7/7 PASS：jc_identity_pipeline 122/0（新增真实 HUD/显示消费断言）
  identification 310/0 · transponder 272/0 · track_table 161/0
  sensor_persistence 86/0 · event_continuity 89/0 · save_roundtrip 41/0
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 89 = 82 PASS / 7 历史 FAIL（new_fail=0、complete=true）
```