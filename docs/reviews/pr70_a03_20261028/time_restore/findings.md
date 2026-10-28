# JC-A03 延迟观测时序与恢复复核

- 被审 HEAD：`6bd919aa19898bbf31f5dd7c3287befc47392877`
- 引擎：Godot 4.7.2 stable；诊断：`diag.gd`，一次有效运行。
- 有效运行时间：2026-10-28 18:13:42.704–18:13:45.614 Asia/Shanghai（UTC 10:13:42.704–10:13:45.614）；exit 0。
- 完整结果在 `result.json`，`comparison.json` 为对严格类型相等问题的离线深比对摘要，日志/运行时间在 `run.log`、`run-meta.txt`。

## 真实文件中的在途观测与 10 tick 继续

诊断经 `apply_ew(noise_jam, raider_2, severity=0.5, duration_s=120)` 后推进真实 Session 两 tick，捕获真实 Sensor 观测 `OBS-000001`，保存于实际 `user://` 文件并加载至新 Session。保存前后队列各有该 observation 一项；load `ok=true`，完整队列条目语义相同。

捕获样本在 session/observed t=1：effect delay=3s、原质量 1.0、投递质量 0.7；队列快照保留 `arrive_t=4`、真实 captured `obs`、`range_km=600.400024414063`、`bearing_deg=0`、空 `position_km`、effect 快照和 `truth_regenerated=false`。t=3仍在队列且 owner measurement 不可见；t=4按 ETA 投递，记录 `received_t=4`，满足 `received>=observed` 且 `received-observed=delay=3`。10 tick 中观察到的所有唯一已投递 ID（OBS-000001、000008–000011）均满足双时间与 delay 一致。

源会话和恢复会话在 t=3..12 每 tick 对照：完整队列条目及 captured observation、EW samples、SensorService observation geometry、delivered rows、owner visible track/measurement quality、combat track 和实际 solution rows。离线逐字段比较（数值容差 1e-9，字符串/布尔/键/数组顺序精确）为 10/10 相同、0 个语义差异。`result.json` 里的 GDScript 原生 `==` 标志为 false，是 JSON roundtrip 将整数值规范化为浮点值（如 support/seq 的 `2` 与 `2.0`）所致；不能将该原始类型相等标志解读为恢复偏差。

恢复链在 t=4 实际调用一次 `combat_request_solution`，源/恢复均得到 `SOL-000001`，其状态/ready_t 和后续逐 tick solution rows 相同。测试结束 t=12 时仍为 `COMPUTING`（ready_t=19）；本对照证明了在途解算状态的继续一致，未覆盖其最终完成帧，也未测量任何火控阈值。

## 无 A03 新段的旧档兼容

从真实 `save_state()` 文本构造兼容夹具，只移除七个 A03 新字段（EW samples/queue/delivered/candidates/sequence/quality history/combat quality），保留原 `ew_service` 段并另存/从实际文件加载。`load_state()` 返回 `ok=true`、无 errors；随后 tick 正常完成，A03 队列/quality history/combat quality 为空。符合恢复器对缺段给空值默认的实现。

## 正式 probe 覆盖审查

正式 W7 (`jc_ew_observation_probe.gd:221–275`) 确实真实文件保存并恢复，然后 10 tick 对照可见 track ID、当前 measurement quality、最终队列长度、投递数与末尾 observation ID。它没有逐 tick 比较完整 pending queue/observation ID，也没有保存/比较队列中的捕获几何与 effect/质量快照；W7 未调用实际 solution API，虽标题称“解算继续”，但没有实际解算结果逐 tick 对照。W8 的 EW=0 是新建 session 的无效果兼容，不是缺少 A03 新段的旧档 load。上面这份限定诊断补了这些具体观测；没有重跑正式 probe。

## 到期 effect 采样语义

补充极小诊断：`expiry.gd` 真实 `apply_ew(noise_jam, severity=0.5, duration_s=1)` 返回 `t_start=0/t_end=1`。首个 GameSession tick 前 `session_now=0, ew.t=0, step_count=0` 且效果 active。该 tick 内 first sensor sample 的 `sampled_t=observed_t=1`，记录 `confidence_mult=0.7, delay_s=3, quality 1.0→0.7`；随后本 tick 的 EW step 推进至 `ew.t=1/step_count=1` 并将效果置 inactive。故实际样本的时间戳恰等于 t_end，但采样当下查询的是 EW step 前仍 active 的状态；它没有使用已标记 inactive 的 effect。Session time 先前进、Sensor 采样、到期 effect step 后执行这一顺序与观察结果相符。

EW=0 首 tick 对照的样本 `sampled_t=observed_t=1, confidence_mult=1, delay_s=0, quality 1→1`，并立即 delivered (`received_t=1`)。已过期 Session 在下一 tick 开始时为 `session_now=1, ew.t=1, step_count=1, active_effects=[]`，但该 tick 没有生成 raider_2 observation；因此本补充只确定 t_end 边界样本，**没有**直接测到严格晚于 t_end 后的下一条观测。原 10-tick 持久化 fixture 与正式 W7 的 effect duration 120s 都不会到期；这部分证据限制仍成立。没有据此判 bug，也没有重新定义采样合同。

边界诊断时间：2026-10-28 18:18:25.786–18:18:28.544 Asia/Shanghai（UTC 10:18:25.786–10:18:28.544）；exit 0。原始数据 `expiry.json`，stdout `expiry-run.log`，时间记录 `expiry-run-meta.txt`。
静态位置：`game_session.gd:1365–1402`（tick 顺序）、`:2555–2574`（effect sample）、`:2582–2627`（捕获/入队）、`:2631–2694`（投递双时间）、`:2833–2847`（缺段默认）、`:5874–5920`（存档）；`ew_service.gd:117–149,173–194`（t_end/step expiry）；正式 W7 为 `jc_ew_observation_probe.gd:221–275`。

退出时 Godot 打印 142 个 ObjectDB instances leaked 与 22 个 resources still in use；进程 exit 0。未改生产、正式 probe、writer/reader matrix 或 baseline；所有新增脚本和报告仅在本证据目录。


