# PR68 第二轮 R4 / R5 连续性复核

- Head: `4a658699868b8d046ec5472f9c4b9ea204af6be9`
- 自定义诊断：`diag.gd`；完整原始数据：`result.json`；引擎输出：`run.log`；时间/退出码：`run-meta.txt`
- Godot：`D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game_v17 --script .test-results/sol-a02-r2/time/diag.gd`
- 实际运行时间：2026-10-28 00:40:57.664–00:41:00.758 Asia/Shanghai（UTC 2026-10-27 16:40:57.664–16:41:00.758）；exit 0。
- 仅运行合法 TTL、late 对照和自然 pending 文件恢复对照；没有运行正式 probe，也没有改生产代码、矩阵、baseline 或 GitHub。

## R4

- **TTL/consumer：部分通过。** 观测时间 0、TTL 5，推进到 t=11 后，`state == identity_state == expired`，`valid=false`、`effective_identity=unknown`；火控身份和同步 combat track 均为 `unknown`。HUD `ident_view` 也拿到 `valid=false`、`validity=expired`、`effective_identity=unknown`，但同时保留原字段 `identity=friend`。所以 TTL 已进入 HUD/火控操作结果，state 别名一致；HUD 展示层应消费 `effective_identity` / validity，若直接显示 `identity` 仍会显示旧友军标签。
- 延迟到达对照仍有一个边界：now/received=8、observed=0、TTL=5 时返回 `validity=stale`、`valid=false`，但 `identity_state=state=valid` 且 `effective_identity=friend`。数据同时保留 stale 和友军有效身份，需按产品策略判断；本轮只记录结果，不扩展政策范围。
- **late 连续性通过。** t=2 新证据 `(observed=2, received=2, TTL=20)` 后，旧证据 `(1,2,20)` 标记 `late_ignored=true`；即时与下一 tick 均只含 optical，结论 friend、confidence 0.639。合法 old-first 对照下一 tick 为两来源 conflict/suspect、confidence 0.386。late 数据没有污染下一 tick。

## R5 与原 owner 连续性

- 经真实 API `identity_iff_query("player_intel", "probe_ship", {"latency_s":3})` 创建 `IFFQ-000001`，返回 pending，ETA=t=5；随即 `save_state()` 写入 `user://` 文件，再从该文件读回并 `load_state()` 到新 session。没有手动写入任何 pending 数组。加载 `ok=true`、`restore_mode=full`，保存与加载后各有一个真实查询队列项。
- 10 个同步 tick（t=3..12）逐 tick 比较查询状态、三个 owner 的两个目标身份/置信度/状态及 owner event ID，10/10 `per_tick_equal=true`。t=3、4 保持 pending 且队列长度 1；到 ETA t=5 才变 valid 并清空队列，之后保持 valid，无提前到达或丢响应。
- 原 ally owner 实际证据流连续且源/恢复逐 tick 一致：10-tick confidence 为 `0.444, 0.418, 0.392, 0.367, 0.343, 0.319, 0.296, 0.273, 0.250, 0.229`；事件 ID 从 `ID-EV-000001` 连续到 `ID-EV-000014`，逐 tick 相同。TTL 在 t=6 转 stale、t=11 转 expired，两边一致。

## 执行记录

Godot 输出 `JC-A02 R4/R5 TIME DIAGNOSTIC`，exit 0。退出时引擎打印 196 个 ObjectDB instances leaked 与 22 个 resources still in use；报告已写出，未见脚本解析错误或自定义失败断言（本诊断为观察型报告，不是 assertion suite）。

静态实现对应：[game_session.gd](https://github.com/HATO-24/ghost-track-apsis/blob/4a658699868b8d046ec5472f9c4b9ea204af6be9/game_v17/scripts/core/game_session.gd) 中 IFF API/入队 4265–4298、到期消费 4355–4375、过期有效性及 state 别名 4175–4195；[shell_binder.gd](https://github.com/HATO-24/ghost-track-apsis/blob/4a658699868b8d046ec5472f9c4b9ea204af6be9/game_v17/scripts/ui/shell_binder.gd) 中 HUD 取 operational identity 并传递 validity/effective_identity 1983–2034。自定义诊断对应 `diag.gd` 15–29（TTL）、31–50（late）、52–98（真实保存恢复）、101–115（逐 tick 快照）。

