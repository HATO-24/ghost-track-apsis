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
