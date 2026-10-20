# 阶段2 TEXT-ENGINE-1 · 行动触发文本

> 任务 task-101 / R5 阶段2。工程 `game_v17`。
> 只改 `framework/core/mission.gd`、`framework/core/world.gd`（事件/文本部分）、
> `framework/content/story_l1.json`、`tests/story_trigger_probe.gd`、`docs/story_trigger.md`；
> 未改 hud/plot/main/state/bridge；未 commit。
> 设计依据：[`docs/41_工作文本07教学目标映射.md`](../docs/41_工作文本07教学目标映射.md)、
> [`docs/23_Demo文本清单.md`](../docs/23_Demo文本清单.md)、`docs/07`、`docs/15`。

## 1　目标

把第一关的通信/事件文本从**按时间自动播报**改为**玩家动作触发**：

- `story.events` / `story.radio_lines` 仍是**唯一文本池**（不复制、不改写、不新增对白）；
- 只有 `story.triggers` 命中的玩家动作/选择/命令/裁决/取证/报告，才把对应条目
  推入 `world.events` / `world.radio`；
- 纯时间推进 `world.advance(dt)` 不再按 `t` 播报 story 文本；
- 同一动作默认只触发一次；失败动作不触发；动作顺序决定文本顺序；允许补触发早期动作；
- 保留必要的、与玩家动作无关的环境日志（现有执行窗口倒计时/结束仍由
  `world._tick_exec_window` 输出；当前 story 没有另配 environment 触发器）。

## 2　数据 schema（`story_l1.json` → `story.triggers`）

```json
"triggers": [
  {
    "id": "TR-OPTICAL-CLASS",
    "on": "action",
    "action": "model_ident",
    "targets": ["summons_4471", "2001"],
    "channel": "event",
    "event_index": 3,
    "text_key": "TXT-0033",
    "once": true
  },
  {
    "id": "TR-ORDER-RADAR-AUTH",
    "on": "order",
    "action": "radar_illum",
    "targets": ["summons_4471", "2001"],
    "state": "AUTHORIZED",
    "channel": "radio",
    "radio_index": 5,
    "text_key": "TXT-0025"
  }
]
```

| 字段 | 必填 | 含义 |
| --- | --- | --- |
| `id` | 是 | 触发器唯一 id（once 去重键） |
| `on` | 是 | `select` / `action` / `order` / `prelude` / `evidence` / `decision` / `report` / `environment` |
| `action` | 否 | 精确动作名（如 `model_ident`、`open`、`execute`）；空 = 该 `on` 任意 |
| `target` | 否 | 单个目标 id/batch/track id |
| `targets` | 否 | 目标别名数组（同一动作可接受实体 id 或批号） |
| `state` | 否 | `order` 用：`PRE_ORDER/AUTHORIZED/QUEUED/TRANSMITTED/EXECUTING/DONE/ABORTED/REJECTED` |
| `channel` | 是 | `event` → `story.events`；`radio` → `story.radio_lines` |
| `event_index` / `radio_index` | 是 | 对上述数组的索引；只引用既有文本 |
| `text_key` | 否 | `docs/23` 的 `TXT-` key（供审计；不复制文本） |
| `min_t` / `at_t` | environment 必填 | 环境触发器的时间阈值 |
| `once` | 否 | 默认 `true`；`false` 表示每次动作都可再次触发（本关未使用） |
| `note` | 否 | 作者备注，不进入运行时文本 |

文本解析：`_fire_trigger()` 只在触发时复制被引用的 event/radio 字典，并附加
`trigger_id/text_key/source/action/target/seq/t` 元数据；**不读 story entry 的 `t` 自动触发**。
若索引越界/`on` 未知/缺 id，写入 `mission.errors`，跳过该条，不静默改文本。

## 3　API

### 3.1 `V2Mission`

| API | 行为 |
| --- | --- |
| `attach_scenario(scenario)` | 载入 `scenario.story.triggers`；解析失败写 `errors` |
| `note_player_event(kind, action, target="", extra={}) -> Array` | 玩家动作成功后调用；匹配触发器，返回本次条目；`extra={"ok": false}` 或 `state` 可拒绝 |
| `tick_environment(now) -> Array` | 仅触发 `on=="environment"` 的条目；不参与玩家动作顺序 |
| `trigger_snapshot() -> Dictionary` | schema=`v2_story_trigger.v1`、trigger_count/fired_count/log、逐条 fired；JSON-safe |
| `reset_story_triggers(reload=true)` | 清空 fired/log/seq（world.restart 调用） |

触发条目 schema：`v2_story_trigger.v1`：
`{schema, trigger_id, channel, index, text_key, source, action, target, seq, t, event|radio}`。

### 3.2 `V2World` 接线

| 玩家动作 | 世界方法 | 传给 mission 的 `(kind, action, target, extra)` |
| --- | --- | --- |
| 选择目标/航迹 | `select(id)` / `select_batch` | `("select","select",id)` |
| 动作（crossfix/radar/optical/IFF/IR）成功 | `perform_action` | `("action",action_id,target_id)` |
| 发预命令 | `issue_order` | `("order",action_id,target_id,{"state":"PRE_ORDER"})` |
| 授权/入队/传输/执行/完成/撤销/驳回 | `_order_action` | `("order",action,target,{"state":<新状态>,...})` |
| 设目的地/选窗口/确认/点火 | `prelude_choose_route/window/confirm/execute` | `("prelude","route"/"window"/"confirm"/"execute",...)` |
| 开始/完成取证 | `start_evidence` / `evidence_complete` | `("evidence","start"/"complete",id)` |
| 打开决策 | `open_decision` | `("decision","open")` |
| 选择结局 | `choose_ending` | `("decision","choose",kind)` |
| 提交报告 | `submit_report` | `("report","submit",kind)` |

失败路径（前置未完成、结束、动作不可用、目标不存在、非法状态迁移、教学门控拒绝、
未知动作）在调用触发入口前 return，因此**不产生文本**。
`world._push_story_items()` 负责把命中条目写入 `events`/`radio`；`mission.trigger_log`
保留跨通道的严格顺序（seq 单调递增）。

## 4　迁移表（本关 18 条，全部复用既有文本）

| 触发器 | on / action | 目标 | 文本 | TXT |
| --- | --- | --- | --- | --- |
| TR-ARRIVE-NOTICE | prelude / execute | — | events[0] | TXT-0030 |
| TR-ARRIVE-RADIO-GREENWICH | prelude / execute | — | radio[0] | TXT-0018 |
| TR-ARRIVE-RADIO-SEXTANT | prelude / execute | — | radio[1] | TXT-0021 |
| TR-ARRIVE-RADIO-APSIS | prelude / execute | — | radio[2] | TXT-0022 |
| TR-ARRIVE-RADIO-4412 | prelude / execute | — | radio[3] | TXT-0023 |
| TR-SELECT-CERES | select / — | ceres_2 / 9001 | radio[4] | TXT-0024 |
| TR-CROSSFIX-FALSE-ALARM | action / crossfix | 9002 / T9002 | events[1] | TXT-0031 |
| TR-RADAR-ON | action / radar_illum | summons_4471 / 2001 | events[2] | TXT-0032 |
| TR-ORDER-RADAR-AUTH | order / radar_illum / AUTHORIZED | summons_4471 / 2001 | radio[5] | TXT-0025 |
| TR-ORDER-RADAR-TX | order / radar_illum / TRANSMITTED | summons_4471 / 2001 | radio[6] | TXT-0026 |
| TR-OPTICAL-CLASS | action / model_ident | summons_4471 / 2001 | events[3] | TXT-0033 |
| TR-OPTICAL-RADIO | action / model_ident | summons_4471 / 2001 | radio[9] | TXT-0029 |
| TR-IFF-QUERY | action / iff_query | ceres_2 / 9001 | events[4] | TXT-0034 |
| TR-IFF-RADIO | action / iff_query | ceres_2 / 9001 | radio[11] | TXT-0020 |
| TR-DECISION-OPEN-RADIO | decision / open | — | radio[7] | TXT-0027 |
| TR-DECISION-COUNTDOWN | decision / open | — | events[5] | TXT-0035 |
| TR-DECISION-FIRE-REQUEST | decision / open | — | radio[10] | TXT-0019 |
| TR-EVIDENCE-PORT | evidence / start | port_telemetry | radio[8] | TXT-0028 |

- **时间轴 `t` 字段保留在 event/radio 数据中作作者侧元数据，但不再用于自动触发**；
  交付顺序 = 玩家动作顺序/定义顺序。
- 命令撤销：本关 story 没有“撤销”专用文本；schema 支持 `order/state=ABORTED`，
  但**不新增/伪造撤销文本**。命令授权→入队→传输各自有文本（上表 r5/r6）。
- `environment` 触发器 schema 已支持（`min_t/at_t`），但本关不配置；执行窗口倒计时
  仍由 `world._tick_exec_window` 作为环境日志输出，不占用 story 触发顺序。

## 5　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/story_trigger_probe.gd
# STORY TRIGGER PROBE RESULT: PASS=83 FAIL=0
# STORY TRIGGER PROBE OK（退出码 0）
```

覆盖：
1. **schema/文本引用**：18 条（6 event + 12 radio）、id 唯一、索引有效、
   `text_key` 均非空且不重复、初始无触发；
2. **非时间驱动**：前置未完成 `advance(120)` 冻结且无文本；跳过前置后纯推进 60 s
   不新增任何动作触发器/story radio；
3. **世界动作顺序**：prelude_skip 触发 5 条→select 触发 1 条→命令授权/入队/传输
   各触发 r5/r6→crossfix 提升到 L2→model_ident 触发 event+radio→重复 select 抑制→
   非法动作/不存在目标不触发→撤销不新增文本；`trigger seq` 单调；
4. **乱序/补触发**：先 model_ident，再 select，再补 crossfix，文本顺序完全跟随调用顺序；
   直接入口重复/`ok=false`/无匹配均 0 条；prelude execute 的 5 条按定义顺序；
5. **其他动作类型**：decision/open 3 条、evidence/start 1 条、order AUTHORIZED/ TRANSMITTED
   各 1 条、order ABORTED 0 条（无撤销文本）；
6. **世界接线/JSON/重开**：events/radio 文本非空且来自既有 story 条目；
   `trigger_snapshot()` JSON；`world.restart()` 清空 fired/log/seq 并恢复可重触发状态。

## 6　边界 / 未完成

- 本任务是**文本触发引擎**，不接 UI；HUD/plot/main/state/bridge 未改，仍通过
  `world.recent_events()/recent_radio()` 读取结果。
- 不改写 story 文本；新增触发器只引用既有 event/radio 索引。`story.events/radio_lines`
  的 `t` 保留为作者元数据，当前无自动播报。
- 命令撤销无专用 story 文本，故不配置 ABORTED 触发器；未来有文本时加一条
  `on:"order", state:"ABORTED", channel:...` 即可。
- 自动打开决策（执行窗口结束 `_tick_exec_window` 或教学门控补开 `_try_open_pending_decision`）
  仍会走 `open_decision()`，因此 decision 触发文本可能在无玩家点击时出现；这是保留的
  环境/超时路径，不是按 story `t` 时间轴播报。若需完全仅玩家打开，可后续给
  `open_decision` 加 `source` 参数并区分触发器。
- 旧 `story_events_data/story_radio_data` 字段仍在 world 初始化中装载（兼容读取），
  但 `_tick_timeline_events/_tick_timeline_radio` 已不再调用；旧探针若断言时间轴文本
  会失败（本任务不跑全量回归）。
- 未做本地化/文本 key 校验器；`text_key` 仅审计字段，运行时文本仍来自 story 条目。
- 未接 HUD 教学提示；docs/41 的 20 步教学 UI 仍留后续阶段。