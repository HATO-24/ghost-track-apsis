# 完整游戏-阶段3V · ChronosChain 港务/私人通信/行动链

> 任务 task-174。工程 `game_v17`。
> 新文件：`scripts/core/chronos_chain.gd`、`tests/chronos_chain_probe.gd`、
> 本文件、`framework/content/story_chronos.json`。
> 不改其他；不写 world/UI；未 commit。

## 1　状态机

```text
WAIT_DOCK → PORT_COMM → ACTION_EVAC → PRIVATE_COMM → CHOICE
  → ACTIONS → WINDOW_END → COMPLETE
```

- **手动 advance**，每次一步；不会自动推进剧情。
- `accept`/`reject` 互斥、只能一次；accept 提高 trust 并解锁
  `blackbox/telemetry/evidence` 行动；reject 降低 trust，但保留
  `future_suggestion_allowed`（后续同类型事件仍可再建议）。
- `ACTIONS`：`evac` 始终可用；`blackbox/telemetry/evidence` 仅 accept 解锁；
  每个行动只能执行一次；`window_end` 结束窗口期。
- `WINDOW_END` 只标记 `window_ended/handoff_4412`，**不自动开始 AV-4412 剧情**；
  `complete` 需手动，交后续 4412 chain。
- 乱序/重复/未解锁动作 → 明确 reason（`invalid_transition/requires_accept/
  already_done`），失败不改状态。

## 2　文本来源（不改写）

- 来源：`docs/44_新剧本_2193.md` 当前副本第 195–221 行（任务原始行 87–99 区段）。
- 仅去 markdown `> ` / `- ` / `**` 与行首缩进；正文逐字保留；`en` 留空（不伪译），
  `draft=true`。
- 9 条：
  - `chronos.port_header`（197，RDO header）；
  - `chronos.port_rdo`（199，储罐区值守人员/家属、三号罐泄漏、协助撤离、不要拖走储罐）；
  - `chronos.evac_option`（201，行动菜单多出协助撤离）；
  - `chronos.private_comm`（207，黑匣子/港务遥测调度建议）；
  - `chronos.accept` / `chronos.reject`（213/215）；
  - `chronos.trust_note`（217，信任度/后续再建议机制）；
  - `chronos.actions_menu`（219，动态行动菜单/窗口期自由操作）；
  - `chronos.window_teaching`（221，窗口期教学弹窗提醒）。
- 内容 schema `v17.story_chronos.v1`：`entity_id/chain/trust/actions/reputation/
  triggers/texts[]`（texts 含 text_key/zh/en/source_lines/usage/draft）。

## 3　信任 / 行动 / 声望

- trust 初始 0；accept +2，reject −1；`blackbox +1`、`telemetry +1`；
  `trust_state`：trusted/cold/neutral。
- 行动输出：
  - `evac`：flag `evac_done`，声望 meridian+1/ocu+1；
  - `blackbox`：flag `blackbox_done/evidence_blackbox`，trust+1，声望 ocu+1；
  - `telemetry`：flag `telemetry_done`，trust+1，声望 ocu+1；
  - `evidence`：flag `evidence_done/evidence_optional`，声望 ocu+1；
  - accept 声望 ocu+1/meridian+1；reject 声望 meridian−1。
- 触发：`chronos_port_comm/private_comm/accept/reject/evac/blackbox/telemetry/
  window_end/complete`（内容可配）。
- 事件 schema `chronos_chain_event.v1`：action/from/to/choice/trust/trust_delta/
  trigger_id/flags/reputation_delta/reputation，`writes_v15=false`。
- 证据 schema `chronos_chain_evidence.v1`：kind/text_key/state/entity_id/payload。

## 4　API

| API | 说明 |
| --- | --- |
| `ChronosChain.new(cfg)` / `setup(cfg)` | cfg：`content` 或 `content_path`；默认加载本内容 |
| `current_state()` / `available_actions()` / `can_advance()` / `is_complete()` | 状态/行动查询 |
| `advance(action, payload={})` | 手动推进；接受/拒绝互斥、行动只一次、窗口/完成校验；失败不改状态 |
| `action_details()` | 动态行动 enabled/done/reason（供 UI 读取，不改状态） |
| `note(text_key, opts={})` | 记录文本 key；未知 key 明确错误；不改状态 |
| `text()` / `text_keys_list()` | 文本 |
| `get_trust()` / `trust_state()` / `chosen_choice()` | 信任/选择 |
| `get_flags/get_flag/get_evidence/get_events/get_notes/get_reputation/get_triggers/trigger_ids` | 输出 |
| `vm()/summary()/to_json()/save_state()/load_state()/check_contracts()` | VM/摘要/JSON/存档/DbC |

存档 `v17.chronos_chain_save.v1`：state/choice/trust/flags/evidence/events/notes/
triggers/reputation/done_actions/seq；load 校验后恢复，非法整体拒绝。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/chronos_chain_probe.gd
# V17 CHRONOS CHAIN PROBE RESULT: PASS=616 FAIL=0（exit 0，只跑一次）
```

覆盖（8 节）：8 状态/9 文本逐字 docs/44；accept 全链路（trust 0→2→4、解锁行动、
声望、handoff、events）；reject（trust −1、future_suggestion、未解锁拒绝）；
8 状态×12 动作乱序矩阵；行动只一次/action_details；note；save/load（mid/final/reject、
非法存档原子拒绝）；非法 action/内容/不存在文件/确定性。

## 6　接入 / 边界

- 与 **CeresChain 输入解耦**：本链不读取 CeresChain 状态；只输出自身
  flags/evidence/trust/reputation/events，供 StoryRuntime/UI/声望系统消费。
- 窗口期结束只标记 `handoff_4412`，不自动推进 AV-4412/剧情；由后续 4412 chain 接管。
- 不写 world/UI/V15；不自动完成；接受/拒绝互斥、行动只一次。
- 文本为原剧本摘录（draft），待用户二次润色；en 留空不伪译。
- 未接 UI/物理/剧情运行时；未跑全量回归；未 commit。
