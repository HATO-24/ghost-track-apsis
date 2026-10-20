# 完整游戏-阶段3X · LegalStatusService（ID13 法律状态机制）

> 任务 task-179。工程 `game_v17`。
> 新文件：`scripts/core/legal_status_service.gd`、`tests/legal_status_probe.gd`、
> 本文件；改 `scripts/core/game_session.gd`、`tests/session_probe.gd`、
> `docs/game_session.md`。不改其他；不写 world/UI；未 commit。

## 1　状态机

```text
UNLISTED（初始；UEG 非法舰队名册暂未列入）
  → WATCHLIST → RESTRICTED → DESIGNATED_ILLEGAL → HUNTED
CLEARED（极少数；显式 cleared/vindicated/exonerated 或 set_status；设置后锁定）
```

- 状态由累计 `heat` 与可配置阈值推导：默认 WATCHLIST=2 / RESTRICTED=4 /
  DESIGNATED_ILLEGAL=7 / HUNTED=10。
- 默认只升不降（`allow_deescalation=false`）；配置可开降级，或显式 `set_status`。
- `CLEARED` 为终态：不再接受事件/降级/`set_status` 其他状态（`cleared_locked`）。
- 所有变化（事件、去重、tick、set_status、CLEARED）都写 `log`，含 reason/from/to/
  heat/weight/t，不静默。

## 2　触发与权重（默认，可用 config 覆盖）

| 因素 | trigger 示例 | 权重 |
| --- | --- | --- |
| 对清算者强硬/火控 | `strong`、`strong_negotiator`、`negotiation_strong`、`roe_tight`、`fire_control_illumination` | +1/+1/+1/+1/+2 |
| 公开黑匣子/证据 | `blackbox`、`blackbox_public`、`blackbox_recovered`、`evidence`、`evidence_public`、`evidence_presented` | +2/+2/+1/+1/+2/+1 |
| 袭击 UEG/NESOSS | `attack_ueg`、`attack_nesoss`、`attack` | +4/+5/+3 |
| 谈判选择 | `negotiation_standard`/`standard`、`negotiation_question`/`question`、`negotiation_retreat`/`retreat` | +0.5/+1/−1 |
| 报告 | `report_public`、`report`、`report_suppress` | +2/+1/−1 |
| 副官信任/政治倾向 | `deputy_trust_low`、`deputy_trust_high`、`deputy_trust`、`political_aeug`、`political_ueg` | +1/−1/+1/+2/+1 |
| AEUG 行为 | `aeug_action` | +2 |
| 清除 | `cleared`、`vindicated`、`exonerated` | 直接 CLEARED |

- 阈值与权重由构造 config 覆盖：`{thresholds:{...}, weights:{...}, impacts:{...},
  decay_per_day, allow_deescalation}`。
- `payload.weight` 可覆盖单次权重（有限数值）；`payload.event_id/id/uid` 明确定义
  去重键；未给时按 `trigger+payload` 去重；`payload.force=true` 可绕过。
- 未知/空 trigger 明确 `unknown_trigger/invalid_trigger`，不改状态。

## 3　影响接口（只输出标志）

`impact()` 返回：

```json
{
  "port_access": {"ueg": "...", "joint": "..."},
  "iff_watch_flag": true/false,
  "combat_roe_modifier": 1.0,
  "ending_branch_hint": "standard|watchlist|restricted|designated_illegal|hunted|cleared",
  "legal_status": "...",
  "heat": 0.0,
  "writes": {"world": false, "side": false, "legal_text": false, "ui": false}
}
```

状态映射：

| 状态 | UEG 港 | 共管港 | iff watch | ROE mod | ending hint |
| --- | --- | --- | --- | --- | --- |
| UNLISTED | NORMAL | NORMAL | false | 1.00 | standard |
| WATCHLIST | WATCHED | NORMAL | true | 1.05 | watchlist |
| RESTRICTED | RESTRICTED | WATCHED | true | 1.15 | restricted |
| DESIGNATED_ILLEGAL | DENIED | RESTRICTED | true | 1.30 | designated_illegal |
| HUNTED | DENIED | DENIED | true | 1.50 | hunted |
| CLEARED | CLEARED | CLEARED | false | 1.00 | cleared |

只输出标志，不直接改 world side、法律文本、港口/战斗服务；由上层消费。

## 4　API

| API | 说明 |
| --- | --- |
| `LegalStatusService.new(cfg)` / `setup(cfg)` | 阈值/权重/impact/decay 可配 |
| `apply_event(trigger, payload={})` | 触发累计；去重；记录 log；返回 status/heat/previous/weight/reason |
| `set_status(status, reason="")` | 显式设置；CLEARED 锁定；记录 log |
| `tick(dt)` | 时间推进/可选 decay；状态变化记录；非法 dt 拒绝 |
| `vm()` / `summary()` / `to_json()` | 只读 VM/摘要/JSON |
| `impact()` / `port_access()` / `iff_watch_flag()` / `combat_roe_modifier()` / `ending_branch_hint()` | 影响接口 |
| `save_state()` / `load_state()` / `reset()` / `check_contracts()` | 存档/重置/DbC |

## 5　GameSession 接入

- **可选组件**：boot config `legal_status: true` 或配置字典；缺省/`false` → 不组合，
  全部 legal API 返回 `no_legal_status_service`/空，旧档仍兼容。
- 新增 session API：
  `legal_apply_event(trigger,payload)` / `legal_set_status` / `legal_tick` /
  `legal_vm` / `legal_summary` / `legal_impact` / `legal_status_text` /
  `legal_port_access` / `legal_iff_watch_flag` / `legal_combat_roe_modifier` /
  `legal_ending_branch_hint`；别名 `apply_legal_event`。
- `tick(dt)`：调用 `legal_status_service.tick(sim_dt)`，结果在
  `tick().legal_status_tick`，`components.legal_status=true`；不写 world。
- `snapshot().legal_status` 只读快照；save 嵌入 `legal_status_service` 快照；
  load 恢复；**旧存档**缺字段/seed 配置 → 组件退化，日志中的 legal op 跳过
  （`skipped:no_legal_status_service`）。
- 脚本事件可通过 `session.legal_apply_event(...)` 驱动并记录操作日志（可 replay）。
- DbC：legal ready、service 自身 contracts；不检查 legal 内部时间与会话时间一致
  （`legal_tick` 可独立驱动服务时钟），但 session tick 会同步推进。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/legal_status_probe.gd
# V17 LEGAL STATUS PROBE RESULT: PASS=342 FAIL=0（exit 0，只跑一次）

.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/session_probe.gd
# V17 SESSION PROBE RESULT: PASS=1057 FAIL=0（含 legal 集成；只跑一次）
```

legal probe 覆盖（7 节）：默认/阈值；逐级迁移/边界/自定义阈值；6 状态影响接口；
CLEARED 锁定/tick/decay/deescalation；去重；save/load/非法存档/config/确定性；
29 个触发别名/副官信任/政治倾向/AEUG/报告。
session probe 新增 legal 集成：可选退化、初始 UNLISTED、事件/去重/影响、tick、
save/load/旧档兼容、确定性。

## 7　边界 / 待做

- 只做法律状态与影响标志；不改 world side、港口放行、战斗 ROE、剧情文本；
  这些由上层读取 `impact()` 后自行决定。
- 阈值/权重为默认策划值，可按任务配置调整；未做完整政治/道德系统。
- `CLEARED` 极少数，需上层显式触发；未接 UI/剧情运行时；未跑全量回归；未 commit。
