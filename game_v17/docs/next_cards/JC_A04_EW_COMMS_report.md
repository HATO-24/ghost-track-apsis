# JC-A04（#61）EW 进入通信链路并保持确定性恢复 · 交付报告

> 分支 `jc/a04-ew-comms`；开工 main `4e4f90f9eb4964503a61dd915cb1c445294b10a5`（含 A3 合入 `c3fca1c`）
> A1 冻结 `8455847`、A3 冻结 `5d372ea`、G0=K0=`9d0f3b4`；Godot `4.7.2.stable.official.ed1daf0bf`、Windows
> 证据：`game_v17/docs/next_cards/evidence/a04/`（red 红例 + 最终目录）

## 1. 合同（写者/时点/版本/恢复）

- **唯一推进**：`OrderService.tick` 仍是 Comms 唯一 `tick` 调用；Session 不新增第二次推进，避免重复投递。真实 `DELIVERED/FAILED` 通过 `comms_event_sink` 旁路给 Session。
- **发送时刻冻结**：`Comms.send` 在发送成功路由后查询 `ew_service.comms_effect(接收方)`，冻结本次使用值：
  - 纯 `comms_jam=0.5` → `latency_add_s=20s`、`failure_chance=0.4`；基础时延与 EW 附加分列（`latency_base_s`/`latency_ew_add_s`），总时延=基础+附加，`arrive_t=sent_t+总时延`。
  - 确定性 draw：`hash(seed, seq, delivery_id, from_id)`；同 seed+同发送顺序 → 同 draw；`draw<failure_chance` 冻结为「到达时失败」，到达仅执行、不重新抽样。
  - 测试注入 `debug_force_draw(x)` 一次性覆盖下一条 draw；不写存档、不是玩家可选项。
- **结果分发**：真实 `FAILED`（`comms_jam`）→ Session 发布 `comms.failed`，失败订单 `REJECTED`（原因 `comms_comms_jam`）不执行；失败情报共享不融合；成功只在真实 `DELIVERED` 时发布一次并融合。**pending 消失不再当作送达**（无真实结果时发布 `comms.unknown_outcome`）。
- **版本**：outcome v2（`v17.comms_outcome.v2`）增加 `ew`、`latency_base_s/latency_ew_add_s`；v1（`v17.comms_outcome.v1`）合法旧档迁移，重放时 `ignore_ew` 保持旧语义；未知 schema/version 明确拒绝 `comms_outcome_invalid`。Comms state v2 增加 `ew_rng{seed,seq}`；v1 迁移 `migrated_v1`，未知 version 拒绝。
- **恢复**：`seed/comms_ew_seed` 决定重放抽样；读档不重新抽样，真实文件恢复后继续 10+ tick 一致，下一条消息 PRNG 与连续运行一致；`_standalone`/待融合共享随档。

## 2. 实现（文件）

- `comms_service.gd`：EW 采样/冻结、确定性 RNG、EW 失败在到达执行、state v2 + v1 迁移、失败发送也返回统一 EW 零值契约。
- `order_service.gd`：`comms_event_sink` 旁路真实结果（Comms 推进仍唯一），订单按真实 DELIVERED/FAILED 消费。
- `game_session.gd`：boot 接线 `set_ew_service/set_ew_rng/set_comms_event_sink`；outcome v2；`_on_comms_events` 真实结果分发与共享；`_reconcile_standalone` 不再以 pending 消失冒充送达；重放 v1/v2 迁移与 EW 对照；`comms_ew_state`/`comms_debug_force_draw` 诊断口。

## 3. 红→绿（同分支）

| 阶段 | 结果 |
|---|---|
| 实现前红例（`4e4f90f` + 探针） | `integration.jc_ew_comms` **39 PASS / 39 FAIL**，退出 1（`evidence/a04/red/`） |
| 实现后（含交付前加固） | **106 PASS / 0 FAIL**，退出 0 |

覆盖：EW=0 旧路由/时延/一次投递；jam=.5→+20s/.4；draw=.1 失败与 .9 成功边界；三条真实入口（send_comms/issue_order/queue_intel_share）；同 seed 确定性；真实文件 save→load→继续 tick 一致、不重抽样、下一条 PRNG 一致；outcome v2/v1 迁移/未知版本拒绝、state v2/v1 迁移；no_route/invalid_mode/unknown_to/禁用链路/非法 sender 明确原因；无 ew_service 旧 seed 兼容。

## 4. 运行结果

```
卡指定通信专项: 8/8 PASS（jc_ew_comms 106/0、order_comms_probe 137/0、ew_probe、
  a0_comms_restore 59/0、event_continuity 89/0、legacy_save 60/0、save_roundtrip 41/0）
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 91 = 84 PASS / 7 历史 FAIL（new_fail=0、drift=0、complete=true）
```

7 项历史失败未刷新 baseline；matrix 由 90→91（新增 `integration.jc_ew_comms`），未删旧 case。

## 5. 交付前加固（第二轮自审）\n\n- 链路两端采样：发送方或接收方任一被 EW 干扰都按两端最大 severity 生效，每次发送仍只抽一次 draw。\n- 确定性双 seed 臂：真实文件保存→恢复→继续 24 tick，失败臂仍恰好失败一次、成功臂恰好送达一次；下一消息 draw/seq 与连续运行一致。\n- 篡改检测：改 `outcome.ew` → `comms_replay_diverged`；改 pending EW 冻结字段 → `invalid_state`（`pending.ew.frozen_result` 等）明确拒绝。\n- 旧残留：无真实结果的 standalone 明确发布 `comms.unknown_outcome`，不冒充 delivered。\n\n## 6. 未支持 / NOT RUN

- `comms_spoof` 只形成不可信消息/待确认请求，不自动执行命令、不授开火权、不改身份；
- 真实 RF/光学传播、完整军用通信协议、AI 任务接受策略（B2）未接；
- 不把测试 seed 的抽样成功率当作真实 RF 统计；
- Linux/macOS、非 headless 渲染、>1000 tick 成本 NOT RUN。
