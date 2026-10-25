# DS-A-06 · 真实 HUD 会话的通信读档恢复（I6）

> 执行基线 **I5** = `0a66ea2ca45e36739e3c92da80f742526b8b24cb`；交付 **I6** 见执行报告。

## 1. 复现的缺陷与根因

修复前 A0-T3 的真实 HUD 往返：

```
[A0-T3] FAIL live HUD session save→load ok (real entry roundtrip)
        (errors=["replay send_comms 失败：no_route"])
```

**根因**：`send_comms()` 在**发送前**记录操作，且记录里**没有 outcome**；
`load_state()` 把任何重放 op 的 `ok=false` 当作恢复错误。
orbital_sim 的 links 全部是 LD，HUD 启动时 `_seed_comms_sample()` 发的 LR 本来就会
`no_route` 失败 → 这个**原始失败**在重放时被误报成读档错误。

五种可能中确认的是：**「原运行就失败的 LR 操作被重放成读档错误」**。
不是路由丢失、不是初始化顺序、不是状态未保存。

## 2. 修复语义

1. `send_comms()` **先执行后记录**，记录带版本化 `outcome`：
   `{schema:"v17.comms_outcome.v1", version:1, ok, reason, mode, delivery_id,
     path, latency_s, relay_count, arrive_t, sent_t}`。
2. `_replay_op("send_comms")` → `_replay_send_comms(op)`：执行后逐项核对
   `ok / reason / delivery_id / latency_s(1e-6) / path`：
   - 原始失败 → 重放**同一失败** → `matched_expected_failure`（**不是**错误）；
   - 原始成功但重放失败 / 原因或 ID 或路径或延迟不一致 → `comms_replay_diverged`，读档失败；
   - 旧日志无 outcome → `legacy_unverified`（A-04 版本规则），**显式计数**，不静默忽略。
3. `comms_restore_report()`：逐项 `recorded` vs `replay` 对照 + 计数
   （`matched_success` / `matched_expected_failure` / `legacy_unverified` / `diverged`），
   并显式标注 `losless_claim=false`。

`CommsService` 仍是消息/路径/投递状态写者；EventBus 分配事件；本次**未**修改通信路由算法、
未删除示例发送、未添加不存在的 LR 链、未篡改 scenario 拓扑。

## 3. 原执行 / replay outcome 对照（真实 HUD 会话）

启动通信 2 条（LD 成功 + LR `no_route` 失败），逐项对照结果：

| 字段 | 原执行 | 重放 | 结果 |
|---|---|---|---|
| mode / from / to | LD / apsis→… | 相同 | 一致 |
| ok | true | true | `matched_success` |
| delivery_id | `C-000001` | `C-000001` | 一致 |
| latency_s | 实测值 | 差 ≤1e-6 | 一致 |
| mode / from / to | LR / apsis→… | 相同 | 一致 |
| ok | **false** | **false** | `matched_expected_failure` |
| reason | `no_route` | `no_route` | 一致 |

`diverged=0`、`legacy_unverified=0`；读档后 `comms.failed` 事件数量不变。

## 4. 路由与延迟报告

仅**记录**（本卡不修改路由）：节点数/链路数、每条链路的 mode、`latency_s`、`path`、`relay_count`、
`arrive_t`、`sent_t` 全部进入 `comms_restore_report().ops[*]`，供逐项核对。
LD 直连与 LR 中继两条成功路径 + 一条延迟排队消息在 fixture 中覆盖。

## 5. 旧日志兼容矩阵（A-04 版本规则）

| 旧日志形态 | 行为 | 标记 |
|---|---|---|
| 有 `outcome`（v1） | 逐项核对；原始失败保留为失败 | `matched_*` |
| 无 `outcome` | 仍可读档；该操作标为未验证 | `legacy_unverified`（计数 + 逐项） |
| 有 `outcome` 但与重放不符 | **明确拒绝读档** | `comms_replay_diverged` |
| 缺通信段 | 按 A-04 支持矩阵重建 | `unrecoverable[]` |

## 6. 正负例覆盖（探针 45 断言）

- **正例**：LD 直连、LR 中继（经 `relay1`）、延迟排队消息、立即投递消息；读档后继续 20 tick，
  投递消息的 `delivery_id`/接收者/顺序/时刻完全一致、**恰好一次**、残余队列长度一致。
- **负例**：原始 `no_route` 失败被正确保留并仍显示失败；篡改 recorded outcome（成功→失败）被
  检测为 `comms_replay_diverged` 且读档失败；`invalid_mode`/`unknown_to` 原始失败保留；
  旧日志无 outcome → `legacy_unverified=1` 且不计为分歧。

## 7. 真实执行结果（I6）

```
Phase A gate:  total=3 pass=3 fail=0   ← 三个 Phase A 探针全绿
               (a0_track_truth 45/0、a0_entity_metadata 30/0、a0_save_roundtrip 41/0)
Phase 0 gate:  total=6 pass=6 fail=0
Full matrix:   total=84 pass=77 fail=7
  BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```

**7 个 FAIL = 仅 Phase 0 的 7 项历史失败**（content 2 / unit 1 / integration 4），
Phase A 相关切片（A0-T1/T2/T3 + 本批 4 个新探针）**全部转绿**。
`phasea_baseline_failures.json` 已删除，CI 与最终命令去掉 `-BaselineExtra`。

## 8. 未覆盖 / 尚未验证

- 身份/IFF/EW 与完整战斗仍是后续工作（本卡未触及）；
- 长时存档成本与预算建议 → **DS-A-07**；
- 未验证 Linux/macOS、非 headless 渲染、真实 RF 物理；
- 历史 7 项失败**未**清零，不宣称全量零失败。

## 9. 命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_comms_restore|order_comms|core_time_event|a0_event_continuity|a0_legacy_save|a0_sensor_persistence|a0_save_roundtrip_authority|save_probe|session_probe|e2e_orbital_sim' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-06/full
```
