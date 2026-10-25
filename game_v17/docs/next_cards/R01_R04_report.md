# R01–R04 返修报告（合并前验收缺口）

> 基线：S7 = `af5b92471a0f12f1ab95c7defda88360e171e277`。
> 返修分支：`fix/phase-a-merge-review`（每条修复按源码归属原 PR：#33 / #35 / #37 / #38 / #39）。
> 全部证据目录：`.test-results/next-cards/R0x/`。

## R01 · 玩家 VM 所有分支遵守相同可见性（#40 / 原 PR #33）

**红证据**（审查 `REVIEW_PLAYER_SELECTED_TRUTH`）：

```
LIST has_batch=false            ← tracks 已投影
SELECTED has_batch=true batch=SECRET-9001   ← 缺陷：selected 未投影
INTERNAL selected has_batch=true / all_tracks with_batch=1   ← 内部应保留
```

**根因**：A-01 只给 `vm()["tracks"]` 加了 `_player_row` 投影，`selected` 与 `events` 分支未走同一策略。

**修复**：`vm()` 的 `selected` 也过 `_player_row`；新增 `_player_events()` 对事件分支执行同一扣留（防御性，当前事件无 truth-only 字段）。内部 `selected()`/`all_tracks()`/`snapshot()` **不变**（去重/合并/存档仍需要 batch）。本卡不引入本舰/公开设施例外；未来若需公开必须在行内带 `truth_source`。

**绿证据**：
- `unit.track_table_probe` **146→161**（+8 断言：三分支同策略、selected 保留稳定 id、内部保留 batch）
- `integration.a0_integration_authority` **61→65**（+4，真实 HUD 会话）
- 专项 4/4 PASS；C 回归 phase0 6/6、phaseA 3/3、full 84=77/7 baseline 匹配

## R02 · 事件自动 ID 唯一与新档完整性（#41 / 原 PR #35）

**红证据**（审查 `REVIEW_EXPLICIT_AUTO_COLLISION` / `REVIEW_V2_MISSING_SEEN_IDS`）：

```
EXPLICIT ok=true id=evt-000001
AUTO     ok=true id=evt-000001     ← 碰撞：两条成功 publish 同 ID
>1000 事件后删除 seen_ids 的 v2 state：import ok=true, 早期 ID 可再次发布
```

**根因**：(a) 自动分配 `_id_seq += 1` 不跳过已用 ID，显式 `evt-N` 也不抬高水位；
(b) `import_state` 对 v2 的 `seen_ids`/`id_seq` 缺失时用默认值静默接受。

**修复**：(a) 自动分配循环跳过 `_seen_ids` 中已用 ID；显式 `evt-NNNNNN` 抬高高水位；
(b) v2 state **必需字段严格校验**（`seq`/`id_seq`/`events`/`seen_ids` 缺任一 → `invalid_state_missing_fields`），失败不半写、不降格为旧档；仅无 schema 的真实旧格式走迁移。

**绿证据**：`integration.a0_event_continuity` **72→89**（+17：显式/自动碰撞、跨多个 ID、恢复后续发、>1000 缺 seen_ids 拒绝且原子、分配边界 `id_exhausted` 拒绝且不推进 counter）。专项 5/5；C 回归全绿。

## R03 · 传感器严格恢复及同输入续跑一致（#42 / 原 PR #37）

**红证据**（审查三项）：

```
SPLIT_VERSION ok=true            ← version=1.5 被 int 截断成 1 接受
NULL_BACKEND ok=true channels_after=3   ← backend=null 但非空通道，真实通道丢失
A obs_seq=8 vs B obs_seq=10（每 tick 差 2，10 tick 后 64 vs 68）
```

**根因**：
1. `int(state.get("version", 0))` 静默截断分数；
2. `backend` 缺失/为 null 时无校验，真实通道被默认值掩盖；
3. **观测序号在 EMCON 过滤前递增**：恢复会话 authority 仍产出雷达 advisory（被过滤），却消耗 `_obs_seq` → 序号漂移。同时 `import_state` 未调用 `_apply_controls()` 同步控制值到后端。

**修复**：版本精确整数契约；`backend` 键必需且「非空通道 + backend=null」拒绝；`import_state` 末尾**静默**同步 `_apply_controls()`（`_importing` 保护：不 push 事件、不推进 `event_seq`）；`_obs_seq` 改为**只对实际采用的观测**分配；新增可审计 `_filtered_observations` 计数。

**绿证据**：`integration.a0_sensor_persistence` **69→86**（+17），关键断言：
`orig=[8,10,12,…,26]` vs `restored=[8,10,12,…,26]` **逐条一致**，观测 ID 流一致，分配器/时钟/后端通道一致，导入不改写 `event_seq`。专项 7/7；C 回归全绿。

## R04 · 通信 outcome 版本与完整性校验（#43 / 原 PR #38）

**红证据**（审查 `REVIEW_COMMS_UNKNOWN_OUTCOME`）：

```
outcome.version=999 → load ok=true, legacy_unverified=1   ← 损坏档被当旧档放行
```

**根因**：`_replay_send_comms` 只在 `version == 1` 时走校验，其余（含非法版本）落入 legacy 分支。

**修复**：`op.has("outcome")` 即**必须合法**——校验 `schema`/精确整数 `version`/`ok(bool)`/`reason|mode|delivery_id(String)`/`latency_s|arrive_t|sent_t(有限数)`/`relay_count(非负整数)`/`path(Array)`；不合法 → `comms_outcome_invalid` 明确拒绝。仅**确实没有 outcome 字段**的旧操作标 `legacy_unverified`。补 `mode`/`relay_count`/`arrive_t` 一致性核对（离散值精确、时间 ≤1e-6 s）。

**绿证据**：`integration.a0_comms_restore` **45→59**（+14：version999、未知 schema、分数版本、错类型、缺字段、NaN、旧无 outcome 仍 partial、成功/失败按原结果恢复）。专项 4/4；C 回归全绿。

## 共同回归（每卡均执行）

| 卡 | 专项 | phase0 | phaseA | full matrix | baseline |
|---|---|---|---|---|---|
| R01 | 4/4 | 6/6 | 3/3 | 84=77/7 | `new_fail=0 drift=0 complete=true` |
| R02 | 5/5 | 6/6 | 3/3 | 84=77/7 | 同上 |
| R03 | 7/7 | 6/6 | 3/3 | 84=77/7 | 同上 |
| R04 | 4/4 | 6/6 | 3/3 | 84=77/7 | 同上 |
| R05 | benchmark 150/0 | 6/6 | 3/3 | 84=77/7 | 同上 |

**7 项历史失败仍红且未登记为本轮新增**；新增审查缺口（R01–R05）全部转绿，**未**写入 `known_baseline_failures.json`。

## 尚未完成（需下一轮）

1. **按原 PR 分散提交**：R01→#33、R02→#35、R03→#37、R04→#38、R05→#39，并 rebase 下游堆叠、冻结新的每个 head；
2. PR #54 审查分支合入后的最终整链验收；
3. H01–H04（七项历史失败）、S01（预算优化）、Q01–Q03、F01 尚未开始。
