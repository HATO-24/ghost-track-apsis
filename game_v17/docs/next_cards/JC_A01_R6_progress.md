# JC-A01（#58）R6 返修进展（未完成，需继续）

> 分支 `jc/a01-authority-intel`，head `3163795d97e495a8dd43efcf49823595779fb989`
> 基线 main `3045311657609dfe10a133802b93dde2fc8abb79`（G0=K0=`9d0f3b4…`）
> 环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows

## 已实现（本轮）

| 项 | 实现 |
|---|---|
| R1a 请求 context 参与授权 | `authorize_fire` 校验 `actor_id`∈域授权名单、`controller_id`=域直控、`fleet_id`=域/舰队列、`domain_id` 一致；**显式非法 context 不再被抹成 legacy**（分别返回 `actor_not_authorized`/`controller_mismatch`/`fleet_mismatch`/`context_domain_mismatch`） |
| R1b 真实运行态 | 运行态集合由调用方按**实际** `combat_service.own_id` 注入；`own_fleet[].combat_runtime` 配置不再自证（第二本方舰返回 `shooter_runtime_unavailable`） |
| R2 context 进日志/审计/重放 | `request_fire` 的 `_record` 与返回值带 `authority_context`（actor/controller/domain/fleet/shooter/legacy/t_s）；审计同字段；`_replay_op` 的 `request_fire` 按日志 context 重放 |
| R3a 空情报不回退真值 | `shell_binder.plot_positions()` 在 owner positions 为空时返回 `source=intel, positions=[]`，不再回退 PhysicsWorld/snapshot |
| R3b HUD 走 owner facade | `refresh()` 的 contacts 改由 `_build_contacts_from_intel(owner)` 生成（不再用全局 `track_vm`/snapshot 补齐）；`_intel_owner()` 用 `own_entity_id()` 解析，不再猜第一个 ship |
| R4 共享投递门 | `receive_observation` 要求：observer 已登记、跨 owner 必须有原始 owner 授权 + `delivery_id`、时间有限/非负/`received>=observed`/不得来自未来/`delay` 与差值一致、幂等键去重；未知 owner/observer 不再默认本方 |
| R4 真实链路 | `queue_intel_share` 经既有 `comms.send` 并在 `_reconcile_standalone` 到达后投递融合；延迟按**实际到达**计算（不再用链路理论时延） |
| R5 旧档/坏段/披露 | 真正缺段 → 旧 TrackTable 航迹迁入本舰 owner（不复制盟军）；畸形新段 → 明确失败；`authority_restore_mode`/`reasons` 进入 `load_state` 返回与 `authority_restore_report()` |
| R6 隐藏真值 | 钩子改用 `world.apply(entity.move)`（正确 writer token），返回 `truth_changed` 与 before/after；探针断言真值确实改变且玩家视图不变 |

## 未完成（红→绿尚未闭环）

新验收探针 `tests/jc_authority_intel_probe.gd` 当前 **43 PASS / 13 FAIL**，已从 `probe_matrix.json` 移除（不再注册为回归用例，避免把红例当作通过；7 项历史失败未动）。剩余失败：

1. **真实发射正例**：已加 `FIRE` 授权后仍返回 `needs_authorization`，需按 combat_service 的 grant 作用域/ROE 语义对齐；弹药/弹体/`combat.weapon_launch` 计数尚未取到（当前 `_res` 的库存读取也需改为真实武器表）。
2. **共享到达**：`last_intel_share_result()` 为空，说明 `_reconcile_standalone` 的到达回调未触发（comms 由 `orders.tick` 推进，需确认 pending→delivered 的具体路径并接线）。
3. **旧档真实来源**：用真实旧来源（含 TrackTable 航迹 + log）加载时 `replay tick 失败：contract_violation`，需定位旧 log 重放与当前契约的冲突（或按卡只迁移航迹、不重放旧 tick）。
4. **重复投递幂等**：观测流仍增长 1（去重键/到达记录不一致）。

## 证据

- 探针（红）：`game_v17/tests/jc_authority_intel_probe.gd`；运行输出需在最终提交中另行归档。
- 既有回归保持绿：`unit.track_table_probe 161/0`、`integration.session_probe 1545/0`（本轮改动后复跑）。
- 全量回归 **未在本轮重跑**（探针已移除注册，矩阵 87 项与上一轮一致；需在剩余项闭环后按卡重跑）。

## 下一步（继续原 #58）

1. 修真实发射正例（grant 语义 + 真实库存/弹体/成功事件断言）；
2. 接线共享到达（comms pending→delivered）并验证发出→不可见→到达→仅接收方→重投幂等；
3. 旧档真实来源与重放冲突处理；
4. 三项闭环后注册回矩阵，跑专项 + 全量 C 回归，产出红/绿证据与同 SHA 报告。
