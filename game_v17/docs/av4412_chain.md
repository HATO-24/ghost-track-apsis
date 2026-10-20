# 完整游戏-阶段3W · Av4412Chain AV-4412 轨道/对峙/谈判链

> 任务 task-177。工程 `game_v17`。
> 新文件：`scripts/core/av4412_chain.gd`、`tests/av4412_probe.gd`、
> 本文件、`framework/content/story_av4412.json`。
> 不改其他；不写 world/UI；未 commit。

## 1　状态机

```text
ORBIT_DEPARTURE → WINDOW_OPEN → EARLY_RADAR / PASSIVE_CONTACT
  → COMMS → NEGOTIATION → STRONG / STANDARD / QUESTION / RETREAT
  → RESOLUTION → REPORT_HANDOFF
```

- **手动 advance**，每次一步；不自动推进、不自动开火。
- 窗口期结束/提前雷达**二选一**：雷达开启只能走 `early_radar`，未开雷达只能走
  `passive_contact`；二者互斥。
- 谈判**四选一**：`strong/standard/question/retreat`；选择后不可改选。
- **退让需副官多次劝阻**：`deputy_warn` 累计 3 次（内容可配）后才允许
  `retreat`；劝阻文本为 TBD key，不伪造。
- 四选项都经 `resolve → REPORT_HANDOFF` 手动收尾；退让标记 `death_ending/demo_end`。
- 乱序/重复/未满足前置 → 明确 reason（`invalid_transition/window_closed/
  radar_inactive/radar_active_mutually_exclusive/missing_retreat_warnings/
  missing_orbit/already_warned`），失败不改状态。

## 2　真实轨道输入（不伪造）

`update_orbit(av4412_track)` 接受：

```text
{
  t: float,                 # 时间
  pos: [x,y,z] km,          # 三维有限数值
  vel: [x,y,z] km/s,        # 三维有限数值
  window_open: bool,
  radar_active: bool
}
```

校验类型/维度/有限性；原样保存，不做插值/猜测。输出：
- `detected`：雷达开启或已进入接触/谈判阶段；
- `window_closed`：轨道窗口已关闭/已提前接触/已发生接触；
- 不自动推进状态；`window_open` 动作需先有真实轨道且 `window_open=true`。

## 3　四选项效果

| 选项 | 状态/效果 | threat | trust | 声望 | 触发 |
| --- | --- | --- | --- | --- | --- |
| strong 强硬 | `roe_tight` + `fire_control_illumination` 事件；`auto_fire=false`；AV-4412 撤离 | +2 | 0 | ocu+2/meridian+1 | av4412_strong |
| standard 标准 | 威胁后离开；AV 回话 TBD | +1 | 0 | ocu+1 | av4412_standard |
| question 质疑 | 展示遥测证据；上级叫停/AV 返回；完整返回威胁文本 TBD | 0 | +1 | ocu+2/meridian+1 | av4412_question |
| retreat 退让 | 3 次劝阻后可选；死亡结局/`demo_end`；仅一次 | −1 | 劝阻 −1/次 + 退让 −3 | ocu−3/meridian−2 | av4412_retreat / av4412_death_ending |

- 强硬只做 ROE 切换与火控照射，**不自动开火**（无 weapon_launch 事件/flag）。
- 事件 schema `av4412_chain_event.v1`：transition + `roe_tight`/
  `fire_control_illumination`/`death_ending` 特殊事件，均 `writes_v15=false`。
- 证据 schema `av4412_chain_evidence.v1`。
- 输出 flags/evidence/threat/trust/reputation/events/triggers，供 StoryRuntime/UI 消费。

## 4　文本来源（不改写，缺文本 TBD）

- 来源：`docs/44_新剧本_2193.md` 当前副本第 225–259 行（任务原始行 100–116 区段）。
- 仅去 markdown `> ` / `- ` / `**` 与缩进，正文逐字保留；`en` 留空（不伪译），
  `draft=true`。
- 11 条原文（source_lines=docs/44 实际行）：
  - `av4412.contact_rules` 227（窗口/提前雷达/被动接触规则）；
  - `av4412.negotiation_rules` 231（谈判判定/坚守/撤离）；
  - `av4412.opening` 233（AV-4412 开场喊话）；
  - `av4412.strong` 237 / `av4412.strong_aftermath` 239；
  - `av4412.standard` 241 / `av4412.standard_aftermath` 243；
  - `av4412.question` 245 / `av4412.question_aftermath` 247；
  - `av4412.retreat_rules` 253 / `av4412.retreat_ending` 255。
- **6 条 TBD**（zh=`TBD`，tbd=true，不伪造，source_lines 空）：
  `av4412.standard_av_reply_tbd`、`av4412.question_av_reply_tbd`、
  `av4412.av_return_threat_tbd`、`av4412.retreat_deputy_warn_{1,2,3}_tbd`。
- `note(text_key)` 可记录查看；TBD 条目返回 `tbd=true`；未知 key 明确错误。

## 5　API

| API | 说明 |
| --- | --- |
| `Av4412Chain.new(cfg)` / `setup(cfg)` | cfg：`content` 或 `content_path`；默认加载本内容 |
| `current_state()` / `available_actions()` / `can_advance()` / `is_complete()` | 状态查询 |
| `update_orbit(track)` | 真实轨道输入；输出 detected/window_closed；无效轨道拒绝 |
| `advance(action, payload={})` | 手动推进；窗口/雷达互斥、四选一、退让劝阻校验；失败不改状态 |
| `note(text_key)` / `text()` / `text_keys_list()` | 文本查看 |
| `detection_status()` / `get_orbit_track()` | 检测/轨道 |
| `get_threat/get_trust/get_retreat_warnings/get_resolution/get_flag/get_flags` | 输出 |
| `get_evidence/get_events/get_notes/get_reputation/get_triggers/trigger_ids` | 输出 |
| `vm()/summary()/to_json()/save_state()/load_state()/check_contracts()` | VM/摘要/JSON/存档/DbC |

存档 `v17.av4412_chain_save.v1`：state/orbit/window/radar/contact/option/resolution/
retreat_warnings/threat/trust/flags/evidence/events/notes/triggers/reputation/seq；
load 校验 schema/version/state/option/flags/evidence/events，非法整体拒绝（不改状态）。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/av4412_probe.gd
# V17 AV4412 CHAIN PROBE RESULT: PASS=734 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：12 状态/17 文本（11 原文逐字 docs/44 + 6 TBD 不伪造）；真实轨道/非法轨道/
窗口开关/雷达互斥/detected；四选项 happy path（ROE/火控/证据/死亡/声望/trust）；
12 状态×12 动作乱序矩阵；退让劝阻/TBD/仅一次；note/save-load（mid/final/retreat/
非法存档原子拒绝）；非法 action/内容/不存在文件/确定性/无自动开火。

## 7　接入 / 边界

- 真实轨道由上层物理/轨道服务提供；本链只接受 `av4412_track`，不生成假轨道、
  不读取 TrackTable；输出 events/flags/evidence/threat/trust/reputation 供 UI/剧情消费。
- 不自动开火：强硬只切 ROE TIGHT + 火控照射；开火由后续特殊隐藏分支/上层决定。
- 窗口结束/退让不自动推进后续剧情；REPORT_HANDOFF 交给报告/StoryRuntime。
- 文本 TBD 处保留 key，不伪造台词；待用户二次润色/补写。
- 不写 world/UI/V15；未接 UI/物理；未跑全量回归；未 commit。
