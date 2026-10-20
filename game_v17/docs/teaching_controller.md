# 阶段2-TEACHING-1 · 07 教学目标手动控制器

> 任务 阶段2-TEACHING-1（task-104）。工程 `game_v17`。
> 新文件（未改 transit/hud/state/bridge/core/content；未 commit）：
> - `scripts/teaching_controller.gd`
> - `tests/teaching_probe.gd`（`PASS=385 FAIL=0`）
> - 本文件
> 不接 HUD/state/bridge；不实现 UI/文本渲染；只读 VM + 玩家动作入口。

## 1　定位

- 读取 `framework/content/teaching_l4_l1.json`（**4 goals / 20 steps**），实现**手动**教学目标状态机。
- `manual_only=true`、`auto_complete=false`：**只有玩家动作 `note()` 推进**；`tick(t)` 只记录时间，
  不自动完成任何步骤、不按 timer 触发。
- 与转场场景动作对应：设目的地 / 选窗口 / 点火 / 抵达 L1 / 打开接触列表 / 交叉定位 /
  型号识别 / IFF / 选舰 / 雷达开关 / 命令序列 / 暴露 / ROE / 裁决 / 报告。
- 不渲染文本/UI；`vm()` 供后续 HUD/剧情层只读消费。

## 2　API

| API | 说明 |
| --- | --- |
| `Controller.new(path := DEFAULT_PATH)` | 加载并校验；`ready/errors/warnings` |
| `note(action, target := "", extra := {}) -> Dictionary` | **唯一推进入口**（玩家动作）。返回 `{ok, reason, matched_step_id, goal_id, skipped_branch, progress, duplicate, blocked_step_id}` |
| `tick(t) -> Dictionary` | 只更新时间；不自动完成（manual-only） |
| `skip_step(step_id, reason) -> Dictionary` | 显式跳过（不算完成；重复/未知拒绝） |
| `reset() -> void` | 复位全部步骤/事件/进度（不重新读文件） |
| `vm() -> Dictionary` | 只读 VM（JSON 安全） |
| `to_json() -> String` | `JSON.stringify(vm())` |
| `step_state(step_id)` / `goal_state(goal_id)` | 单步/单目标只读视图 |
| `is_goal_completed(goal_id)` / `is_complete()` | 目标/整体是否完成 |

## 3　动作映射（业务动作 → trigger_condition）

| 业务动作 `action`（target/extra 示例） | 匹配步骤/触发 |
| --- | --- |
| `open_prelude`（extra.phase=prelude） | T07-G1-S1（ui_event prelude.opened） |
| `set_destination`（target=`meridian`） | T07-G1-S2（selection prelude.routes=meridian） |
| `select_window`（target=`t1800`） | T07-G1-S3（selection prelude.windows=t1800） |
| `confirm_burn` / `ignite` | T07-G1-S4（player_action prelude.confirm_burn） |
| `arrive_l1` / `transit_done` / `execution_window` | T07-G1-S5（state prelude.transit_done=true / fallback_ui） |
| `open_contact_list`（target=`9001` 等） | T07-G2-S1（ui_event contact_list.opened + selection） |
| `crossfix` / `radar_illum`（extra.track_level≥2） | T07-G2-S2（action_result + L2 门限） |
| `model_ident` / `optical_channel`（extra.track_level≥3） | T07-G2-S3（action_result + L3 门限） |
| `iff_query`（target=`9001/2001`） | T07-G2-S4（action_result track） |
| `ack_identity` | T07-G2-S5（manual_ack identity_legend） |
| `select_ship`（target=`harmattan`） | T07-G3-S1（selection unit_panel.ship） |
| `sensor_toggle`（target=`harmattan/YW-R9`, extra.value=on） | T07-G3-S2（sensor_toggle） |
| `command_event`（extra.sequence=[command.queued,command.aborted], link=LR） | T07-G3-S3（command_event 序列） |
| `state`（target=`emission_state.harmattan.exposed`, equals=true） | T07-G3-S4（state） |
| `open_roe_card` | T07-G4-S1（ui_event roe_card.opened） |
| `decision`（target=HOLD/EVACUATE/EXPOSE/FIRE） | T07-G4-S2–S5（decision_choice；EXPOSE 需 evidence_count≥2，FIRE 需 weapons_release_confirmed） |
| `report_submit`（target=INTERNAL_AFTER_ACTION） | T07-G4-S6（report_submit） |

- 也支持直接传 trigger kind（`ui_event`/`selection`/`player_action`/`state`/`action_result`/
  `sensor_toggle`/`command_event`/`decision_choice`/`manual_ack`/`report_submit`），便于上层通用转发。
- `extra.success=false` 或 action 以 `fail` 开头 → **失败动作不触发**。
- 同一动作（action+target+extra 完全相同）第一次成功后再次调用 → `duplicate_action`，不推进。
- **乱序补触发**：任意 pending 步骤的 trigger 匹配即完成该步（不要求前序已做）；
  `current` 仍取最早 pending 步骤，`hints` 取各未完成 goal 的首个 pending 步骤。
- **需求门限**：`requires` 中 `phase=prelude` 按 extra 校验（缺失不阻塞）；`evidence_count>=2`、
  `weapons_release.confirmed` 不满足 → `requirements_not_met`，不触发。
- **G4 互斥分支**：完成一个 `decision_choice` 后，同 goal 其余 pending 的 decision_choice 步骤
  标记 `skipped`（reason=exclusive_decision），因此 G4 可完成；`skipped` 不计完成但计入 resolved。

## 4　状态机 / 进度

- 步骤状态：`pending → completed`（或显式 `skipped`）；每步 `manual_only=true/auto_complete=false`。
- 目标完成：目标内 pending=0 且至少 completed>0 → `completed`；有完成/跳过但仍有 pending →
  `in_progress`；否则 `pending`。
- 总进度：`{completed, skipped, resolved(=completed+skipped), total=20, pending,
  pct, resolved_pct, goals_completed, goals_total}`。
- `current`：最早 pending 步骤（含 step_id/goal_id/title/objective/player_action/hint/text_keys）。
- `hints`：各未完成 goal 的首个 pending 步骤（各一条）。
- `last_event` / `events`：`{seq,t,action,target,kind,step_id,ok,reason}`（最多 200 条）。
- `completed` / `skipped`：步骤 id 数组。

## 5　VM（`v17_teaching_controller.v1`，只读 JSON）

```
{
 schema, source, scenario_id, story_file, ready, manual_only, auto_complete, t_s,
 goals:[{id,title,objective,source,status,completed_steps,skipped_steps,pending_steps,step_count,steps:[...]}],
 steps:[{id,goal_id,order,title,objective,player_action,status,manual_only,auto_complete,text_keys,gap_id}],
 progress:{completed,skipped,resolved,total,pending,pct,resolved_pct,goals_completed,goals_total},
 current:{step_id,goal_id,title,objective,player_action,hint,text_keys} (无 pending 时 {}),
 hints:[{goal_id,step_id,title,hint,text_keys}],
 last_event:{...}, completed:[...], skipped:[...], events:[...],
 status_vocabulary:{...}, errors:[...], warnings:[...], note
}
```

## 6　验证（最小 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/teaching_probe.gd
# V17 TEACHING PROBE RESULT: PASS=385 FAIL=0（exit 0，只跑一次）
```

覆盖（8 节）：加载/初始（4 goals/20 steps/manual 标志/current/hints/空进度）；G1 顺序、
错误目标、失败动作、重复动作、goal 完成；G2 接触列表/等级门限（L1 不触发、L2/L3 触发）/IFF/图例；
G3 选舰/雷达开关/命令序列/暴露 + **乱序补触发**；G4 ROE、EXPOSE/FIRE 需求门控、HOLD 互斥跳过
其余 3 分支、报告提交、G4 完成；manual-only tick 不自动推进、skip/reset、完整通关
（17 completed + 3 skipped = 20 resolved、goals=4、is_complete）；直接 trigger kind 转发；
JSON/确定性。按任务要求只跑一次，未跑全量回归。

示例通关顺序（probe 使用）：

```
open_prelude → set_destination(meridian) → select_window(t1800) → confirm_burn → arrive_l1
→ open_contact_list(9001) → crossfix(track 9002,L2) → model_ident(track 9002,L3)
→ iff_query(2001) → ack_identity
→ select_ship(harmattan) → sensor_toggle(harmattan/YW-R9,on)
→ command_event([queued,aborted],LR) → state(emission...exposed,true)
→ open_roe_card → decision(HOLD) → report_submit(INTERNAL_AFTER_ACTION)
```

## 7　UI / 后续接入建议（本任务不做）

1. 每个玩家按钮/选择调用 `controller.note(action,target,extra)`；不要把 timer/自动逻辑接到 note。
2. HUD 读 `vm()`：当前步骤 `current`、提示 `hints`、进度 `progress`、完成/跳过列表；
   只渲染，不写控制器状态。
3. 决策面板：`decision(HOLD/EVACUATE/EXPOSE/FIRE)`；EXPOSE/FIRE 传 `evidence_count` /
   `weapons_release_confirmed` 以通过门限；未通过时 `requirements_not_met` 显示原因。
4. 目标完成/整体完成可驱动后续剧情/结算；不自动完成，仍由玩家动作触发。
5. 若接 state/bridge：建议只读暴露 `vm()`（显式 env/默认关闭），另立任务；本控制器不改它们。

## 8　边界 / 未完成

- **不实现 UI/文本渲染**；不读 text_catalog 渲染，不含文本资源。
- 控制器状态不持久化（无存档），`reset()` 仅内存复位；未接 replay。
- 动作映射针对 07 教学 4 goals 硬编码（业务动作别名）；其它关卡需扩展/替换映射。
- `requires` 仅实现 `phase=`、`evidence_count>=`、`weapons_release.confirmed`；未知 token 不阻塞。
- G4 分支为互斥：选择后其余 decision 步骤 `skipped`；是否允许重新选择/回滚不在本任务。
- 不接 HUD/state/bridge/core；未跑全量回归；未 commit。
