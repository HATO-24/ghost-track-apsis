# PR66 第四轮：原情报侧剩余缺口复核

日期：2026-10-27（Asia/Shanghai）。候选 HEAD `eb4b98530b589dd5c452a78d46549660985557d3`；代码提交 `c704f85952eb33ec44c1ac21dfef95d2f8b6a032`（HEAD 仅报告头不同）。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。

**结论：本分项原剩余缺口全部 CLOSED。** selected 已关闭结论保持；owner 的 31/301 秒生命周期与共享读档后的真实 ETA 连续性均已闭环。未发现本范围仍需返修项，到此停止，不扩查 AI/EW 或字段穷举。

根代理统一导入完成并发送 import-ready 后，复用 R3 两份诊断脚本执行；只调整本轮证据路径、HEAD、退出判定和共享 10 tick 对照。没有改动生产代码、正式测试、GitHub 或 baseline，也没有重复根代理已跑的正式 probe。

## CLOSED：selected / 实体详情没有回退到全局航迹

同 R3 合法夹具：盟军 sensor outbox 经真实 `GameSession._advance_sensors(0)` 路由，`route.ok=true`、observations=1；全局 TrackTable 保有私有 T0001，`global_foreign_exists=true`。

- `binder.selected_track({track_id:T0001}) == {}`。
- `binder.selected_entity({track_id:T0001,entity_id:ally_private_contact}) == {}`。
- 本方 `local_contact` 合法正例仍可读：owner=`player_intel`、range=111、quality=0.8；实体详情返回 owner 限定安全投影。

`owner_lifecycle_audit.json`：`selected.closed=true`。此项保持原 CLOSED，并未重新列为缺陷。

## CLOSED：owner 31/301 秒生命周期实际推进

保留 R3 同一真实 GameSession、移除自动 sensor 输入，t=0 只接收一次 `aging_contact`；相同 range500/quality0.8 输入进入 owner facade 和既有 TrackTable 作对照。没有直接调用新增 `authority_intel.advance()`；只用真实 `session.tick(31)`、`tick(270)`，两次均 `ok=true`。

| 会话时刻 | player owner 读数 | 既有全局 TrackTable 对照 |
|---|---|---|
| 0s | 存在；stale=false；age_s=0；last_observed_t=0 | 存在；stale=false |
| 31s | 存在；stale=true；age_s=31；last_observed_t=0 | 存在；stale=true |
| 301s | 已移除 `{}` | 已移除 `{}` |

配置阈值仍为 stale30s / forget300s。`lifecycle.closed=true`、`owner_retained_after_forget=false`、`global_forgotten=true`。本轮退出码已同时要求 selected 与生命周期通过，避免延续 R3 仅由 selected 决定退出码的诊断局限。

源码对应：`authority_intel.gd` 新增逐 owner `advance(t_now)`，`GameSession.tick` 在实际时钟推进后调用；本结论依赖上述动态结果，不依赖类名或只读源码。

## CLOSED：内存与公开文件恢复均在 ETA5 到达

完全复用原合法三域 seed：t=2 经 `queue_intel_share(ally_ship,own_ship,player_intel,...)` 发 `PENDING-ONE`，返回 `delivery_id=C-000001`、pending=1；链路 latency3s，实际 Comms `sent_t=2`、`arrive_t=5`。

两轮独立对照：

1. 内存：`GameSession.save_state()` → 新会话 `load_state()`。
2. 真实文件：现有公开 `SaveService.save_session(s,"save",...)` → `SaveService.load_session("save")`。实际槽位文件保留在 `file-save/save.json`；外层 schema/checksum 走现有服务，未手编存档语义。save/load 均 `ok=true`、load errors=[]。

每轮都于 t=2 发出后立即保存/恢复，再同步推进原会话与恢复会话 **10 tick（t=3..12）**。JSON 保留每 tick 的完整 owner view 和完整签名比较：

| 时刻 | 原会话 / 恢复会话可见航迹 | 共享 pending / Comms pending |
|---|---|---|
| 保存前 t=2 | 均为空 | 均为 1 / 1，ETA=5 |
| 恢复后、尚未 tick 的 t=2 | 均为空 | 均为 1 / 1，ETA=5 |
| t=3、4 | 均为空 | 均为 1 / 1 |
| t=5 | 均首次出现 pending_contact | 均为 0 / 0 |
| t=6..12 | 均保有 pending_contact | 均为 0 / 0 |

两个模式的全部 20 对同步 tick 均 `ok=true`；20 个 `view_signature_equal` 全为 true。完整航迹与观测逐 tick 相等，包含老化字段和接收时间。两模式均 `pending_eta_restored=true`、`normal_arrival_closed=true`、`continuation_equal=true`。

两边最终均保留 `last_observed_t=2`、`last_received_t=5`，实际 delay=3；观测 `observed_t=2`、`received_t=5`；t12 的 age_s=10、stale=false。opfor owner 全程为空。R3 的恢复后 t3 提前可见已不再发生。

## CLOSED：同一共享重投幂等

在两个模式中，原会话和恢复会话均以同一 `C-000001` / `PENDING-ONE` 重投：四次返回均 `ok=true, duplicated=true`，observations 都为 **1→1**，完整 owner view 重投前后保持相同。两模式 `duplicate_closed=true`。

## 证据与运行结果

本目录为 `C:/Users/ASUS/.codex/worktrees/jc-a01-r4-validation/GHOST TRACK_APSIS/.test-results/sol-a01-r4/intel/`。

- `owner_lifecycle_audit.gd` / `.json` / `.log` / `.stderr.log`；`owner_lifecycle_exit.txt` = **0**。
- `share_continue_audit.gd` / `.json` / `.log` / `.stderr.log`；`share_continue_exit.txt` = **0**。
- `file-save/save.json`：真实 SaveService 槽位文件。
- `audit_results.json`：本分项结构化汇总。
- `run_audits.ps1`：本轮实际调用命令与环境路径。

stderr 只保留退出清理提示：owner 50 ObjectDB instances / share 128 instances，分别 20 resources still in use；无脚本解析、脚本运行或业务断言错误。业务结论由 JSON 的明确判定及各引擎退出码得出。

所有原剩余检查通过后停止。本 findings 只关闭上述原缺口，不声称覆盖完整联合战役或新增产品范围。
