# V17-CORE-3 · 清算者无线电教学 / 传感器权威边界

> 工程 `game_v17`。本文件记录 V17-CORE-3 的 API、内容 schema、通信格式、阶段门控与
> 传感器权威边界；HUD 后续接无线电时按 §3 读取/调用即可（本任务不改 HUD 视觉）。
>
> 改动文件：`scripts/state.gd`（API/内容装载/复位）、
> `framework/content/reclaimer_radio_l1.json`（V17 内容副本）、
> `tests/v17_core3_probe.gd`（新 probe）、`docs/v17_radio_sensor.md`（本文件）。
> 未改 `hud.gd`/`plot.gd`/`main.gd`/project/framework 核心；未 commit。

## 1　通信格式（docs/15 §0.3、docs/19 §1）

固定格式：`[发信者至收信者]-[LD/LR/RDO]-[正文]`

- 数据层拆四个字段：`from / to / mode / text`，UI 再拼接（`radio_feed` 既有 schema 不变：
  `{t, from, to, mode, text}`）。
- `state.format_radio_line(from,to,mode,text)` / `state.reclaimer_radio_format(...)`
  返回标准字符串，便于 HUD/日志复用。
- 链路口径：我方战术 `LD/LR`；对清算者的公开法律/程序广播用 `RDO`（可被记录）。
  本教学内容同时包含 RDO（公开）与 LD（直连）两种链路，文字均标注程序词「完毕」。

## 2　内容文件

`framework/content/reclaimer_radio_l1.json`（V17 副本；V2 core 未改）：

```json
{
  "schema": "reclaimer_radio.v1",
  "id": "l1_reclaimer_radio_v1",
  "title": "...", "trigger_phase": "COMMAND",
  "own_callsign": "远地点号", "counterpart": "AV-4412 传唤者",
  "exchange": [ {"dir":"tx|rx","from","to","mode","text"}, ... ],
  "options": [ {"id":"ack","code":"A","label","hint",
                "reply": {line}, "ack": {line}}, ... ],
  "guardrails": {"manual_only":true,"auto_complete":false,
                 "changes_evidence":false,"changes_decision":false,
                 "changes_reputation":false,"changes_clock":false}
}
```

- 内容取第一关 D2 设定：`AV-4412 传唤者`（2001）、`接管官 科尔`、OCJC / UEG 轨道事务委员会、
  第七号轨道紧急托管令 / 《轨道宪章》 / 50 km 检查边界；敌对方用语礼貌、程序化、引用授权文件，
  我方简短、程序化；不抒情、不写电子战/链路故障（docs/15 §0.2–0.3、docs/19 §4 T1-07）。
- 3 个回复选项：`ack`（确认记录并声明立场）、`query`（要求移交授权文件）、
  `decline`（结束通话）。每个选项有玩家回复行（`dir=tx`）与清算者回应行（`dir=rx`）。
- 文件缺失时 `_load_reclaimer_radio()` 使用内置最小兜底（仍遵守手动/无自动完成/格式约束），
  probe 验证正式文件被装载（`content_id=l1_reclaimer_radio_v1`）。

## 3　state API（HUD 只读/调用）

### 3.1 只读字段（每帧可直接读）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `state.reclaimer_radio_content` | Dictionary | 已装载内容（schema/id/title/exchange/options） |
| `state.reclaimer_radio_stage` | String | `idle` / `open` / `done` |
| `state.reclaimer_radio_open` | bool | 是否处于可回复状态 |
| `state.reclaimer_radio_seen` | bool | 是否已发起过（教学进度） |
| `state.reclaimer_radio_choice` | String | 已选选项 id（`ack/query/decline`，未选为 `""`） |
| `state.reclaimer_radio_started_t` | float | 发起时的仿真时间 `tau()`（-1=未发起） |
| `state.reclaimer_radio_transcript` | Array | 已发生条目（含 `stage/dir/from/to/mode/text/formatted/t`） |

### 3.2 方法

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `reclaimer_radio_available() -> bool` | bool | 仅 COMMAND 阶段、未发起、未冻结/裁决/报告/END 时为 true |
| `reclaimer_radio_state() -> Dictionary` | Dictionary | HUD 总览：available/phase/stage/open/seen/choice/content_id/title/options[{id,code,label,hint,enabled,reason}]/transcript/formatted_transcript/note |
| `reclaimer_radio_initiate() -> Dictionary` | `{ok,stage,lines,state}` | 手动发起：写入 `exchange` 全部条目到 `radio_feed`+日志；失败给 reason |
| `reclaimer_radio_reply(choice) -> Dictionary` | `{ok,choice,code,stage,lines,state}` | 按 option id/code/label 选择回复；写入 reply+ack 两行；结束后 stage=done |
| `reclaimer_radio_transcript_lines() -> Array` | Array | transcript 的只读副本 |
| `format_radio_line(...)` / `reclaimer_radio_format(...)` | String | `[from至to]-[mode]-[text]` |
| `sensor_authority_note() -> String` | String | 传感器权威边界说明 |
| `v2_sensor_advisory() -> Dictionary` | Dictionary | V2 传感器/数据模型只读摘要（见 §5） |

`radio_feed` 条目会被 `_append_radio()` 同时写入日志（HUD 现有通信流/日志即可显示，无需新视觉）。
格式错误不会静默：无效选项/阶段返回 `{ok:false, reason}` 并写日志（HOLD），状态不变。

## 4　阶段门控 / 「无自动完成」保证

- 只有 `tut_phase == PHASE_COMMAND`（t≥20 s 且未进入裁决/报告/END、prelude 关闭）时可发起。
- 不会自动触发：`refresh()/_update_phase_gate()/_pump_feeds()` 均不调用 init/reply；
  时间推进、刷新、副官申请、取证任务、决策门控都与该流程无关。
- 一次流程：`initiate` 成功后 `available=false`；`reply` 后 `stage=done`，不可重复发起；
  `restart_demo()` 会复位为 `idle` 并重新装载内容（演示可重来）。
- 无副作用（probe 逐项断言）：不改变 `flags/evidence/reputation/decision_open/
  consequence_open/report_open/end_open/civilians_evacuated/clock`；不改变仿真冻结。
- 不把「已通话」当作任务完成：证据任务、裁决、END 仍由原有流程决定。
- 既有 scenario 时间线自带的清算者广播（T1-07 等）不受影响，也不计入本教学流程
  （probe 用内容文本集合区分「教学流程条目」与 `radio_lines` 时间线条目）。

## 5　传感器权威边界（不切换、不伪造）

- `state.sensor_authority == "legacy_v15"`：**V15 `sensor_model` 仍是接触等级/传感器融合/
  威胁判定的唯一权威**；V2 `framework/sim/{radar,tws,optical}.gd` 仅为数据/演示模型。
- `state.v2_sensor_advisory()` 返回只读摘要（不改任何 V15 传感器状态）：
  `{authority:"legacy_v15", authority_source, role:"advisory_data_demo", switching:false,
    note, v2_ready, v2_sources:["framework/sim/radar.gd","framework/sim/tws.gd","framework/sim/optical.gd"],
    v15:{selected_track_id,selected_level,selected_identity,sensor,fusion_count},
    v2_contact_count(仅 bridge 就绪时), v2_summary(仅 bridge 就绪时)}`
- 未接 bridge 时 `v2_ready=false`；接 `state.framework` 后 `v2_ready=true` 且提供 V2 接触数，
  但 **authority 仍为 legacy_v15、switching 恒为 false**；V15 接触等级/身份/sensor 不受调用影响。
- 后续若要做 V2 雷达/TWS 的视觉展示（V17-SENSOR task-55 的 `tws_bridge.gd`），只能作为
  advisory 叠加；接触等级仍以 V15 为准，不得反向写 `state.tracks/level`。

## 6　HUD 接入建议（后续任务）

- 通信入口（现有通信/动作按钮）：`if state.reclaimer_radio_available():` 显示「清算者通话」
  可点；点击调 `state.reclaimer_radio_initiate()`。
- 弹出选项：读 `state.reclaimer_radio_state().options`（`enabled/reason`），点击调
  `state.reclaimer_radio_reply(id)`。
- 通信流/日志：现有 `radio_feed`/`log_lines` 自动包含新条目（标准格式），无需新面板。
- 完成态：`stage=="done"` 时显示 `choice` 与 transcript（`formatted_transcript`），并隐藏入口。
- 不要自动点「发送」；教学入口必须在 COMMAND 阶段由玩家触发。

## 7　测试

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_core3_probe.gd
# V17 CORE3 PROBE RESULT: PASS=171 FAIL=0（exit 0）
```

覆盖：内容 schema/选项/guardrails；READ 阶段拒绝、COMMAND 可用；3 次刷新/推进无自动触发；
initiate 写 feed 条目与内容逐一对应、标准格式（含 docs/19 示例）、日志更新、不可重复发起；
reply 未知选项拒绝、A 回复写 reply+ack、dir=tx/rx、结束后拒绝；transcript 等长/格式/方向；
「无副作用」逐项断言（flags/evidence/reputation/decision/consequence/report/end/撤离/clock）；
sensor_authority=legacy_v15、advisory 结构、无 bridge/有 bridge 两态、V15 等级不变；
restart 复位且内容重载。既有 `v17_bridge_probe` 与本 probe 均 headless 通过。

## 8　未完成 / 范围外

- 未改 HUD 视觉与交互（通信入口/选项面板由后续 HUD 任务接线；API/字段已稳定）。
- 未切换传感器权威、未改 V2 sim（仅声明 advisory 边界）。
- 未 commit；与 V17 其他任务按本文契约协作。
