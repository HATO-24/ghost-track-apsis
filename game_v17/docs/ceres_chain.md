# 完整游戏-阶段3U · CeresChain 谷神-2 识别/救援链

> 任务 task-172。工程 `game_v17`。
> 新文件：`scripts/core/ceres_chain.gd`、`tests/ceres_chain_probe.gd`、
> 本文件、`framework/content/story_ceres.json`。
> 不改其他；不写 world/UI；未 commit。

## 1　状态机

```text
L1 → L2 → L3 → LIGHT_READ → L4_TYPE → RESCUE_PROMPT
                                    ├→ RESCUED → COMPLETE
                                    └→ IGNORED → COMPLETE
```

- **手动 advance**：每次只走一步；不会自动完成；`note` 仅记录查看文本，不改状态。
- `L2` 需数据链/多传感器定位证据（`data_link=true` 且 `sensor_sources>=2`，或通过
  `ingest` 预置 data_link + ≥2 sensor 证据）。
- `L3` 需 L2 证据/识别输入（level L2/L3/L4 或识别证据）。
- `LIGHT_READ` 需可见光四位应急代码匹配（内容 `emergency_light_code="7700"`，
  演示占位；原剧本未给定具体码）。
- `L4_TYPE` 需先完成 light read；识别为 `ceres_2` 型作业船。
- `RESCUE_PROMPT` 后才可选择救援：`rescue` / `ignore` **互斥且只能一次**；
  选择后需手动 `complete` 才到 COMPLETE。
- 乱序/重复动作 → `invalid_transition`，失败不改状态。

## 2　文本来源（不做改写）

- 来源：`docs/44_新剧本_2193.md` 当前副本第 163–191 行（任务原始行 73–86 区段）。
- 抽取时仅去掉 markdown `> ` / `- ` / `**` 标记与行首缩进，正文逐字保留；
  `en` 留空（不伪译），`draft=true`。
- 9 条：
  - `ceres.fault`（故障/通信阵列失效/应答机不工作/可见光应急代码，docs/44 167）
  - `ceres.l2`（数据链 L2 教学，171）
  - `ceres.l3_l4`（L2 后 VIS/ELINT/数据库/IFF 到 L3/L4，173）
  - `ceres.identify_prompt`（175）
  - `ceres.vis_read`（可见光自动读取/谷神-2 型识别，177）
  - `ceres.rescue_prompt`（救援问句，181）
  - `ceres.rescue_yes` / `ceres.rescue_no`（183/185）
  - `ceres.optional_note`（可选项纳入声望，189）
- 文本内容 schema：`v17.story_ceres.v1`，含 `entity_id`、`chain`、`triggers`、
  `reputation{rescue,ignore}`、`texts[]`（`text_key/zh/en/source_lines/usage/draft`）。

## 3　API

| API | 说明 |
| --- | --- |
| `CeresChain.new(cfg)` / `setup(cfg)` | cfg：`content` 或 `content_path`；默认加载本内容 |
| `current_state()` / `available_actions()` / `can_advance(action)` / `is_complete()` | 状态查询 |
| `advance(action, payload={})` | 手动推进；L2/L3/灯语码/救援互斥/完成条件校验；失败不改状态 |
| `ingest(input)` | 解耦输入：`kind=data_link/sensor/level/text/evidence`；存储证据，不影响状态 |
| `note(text_key, opts={})` | 记录查看的文本 key；未知 key 明确错误；不改状态 |
| `text(key)` / `text_keys_list()` | 原文/keys |
| `get_flags()` / `get_flag(k)` / `get_evidence()` / `get_events()` / `get_notes()` | 输出 |
| `get_reputation()` / `get_triggers()` / `trigger_ids()` / `chosen_action()` | 声望/触发/选择 |
| `vm()` / `summary()` / `to_json()` / `save_state()` / `load_state()` / `check_contracts()` | VM/摘要/JSON/存档/DbC |

触发（写入 triggers 历史/事件）：
- `ceres_light_read`（LIGHT_READ）；
- `ceres_rescue_prompt`（RESCUE_PROMPT）；
- `ceres_rescued` / `ceres_ignored`（选择）；
- `ceres_complete`（手动 complete，内容补充）。
事件 schema `ceres_chain_event.v1`：action/from/to/trigger_id/state/flags/
reputation_delta/reputation，`writes_v15=false`。
证据 schema `ceres_chain_evidence.v1`：kind/level/source/entity_id/payload。
声望：内容配置 rescue `{meridian:+2, outer:+1, ocu:+1}`、ignore
`{meridian:-1, outer:-2}`；选择仅应用一次。

## 4　存档

`v17.ceres_chain_save.v1`：state/flags/evidence/events/notes/triggers/chosen/reputation/
seq/content_path；`load_state` 校验 schema/version/state/flags/evidence/events/chosen 后恢复，
非法整体拒绝（不改当前状态）。load 后可继续 advance。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ceres_chain_probe.gd
# V17 CERES CHAIN PROBE RESULT: PASS=505 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：setup/9 文本逐字 docs/44；happy path L1→…→COMPLETE + 声望/触发；
9 状态 × 8 动作乱序拒绝矩阵；证据输入/L2 条件/灯语码；note；save/load（mid/final/
非法存档）；非法 action/内容/不存在文件/确定性。

## 6　接入 / 边界

- 与 TrackTable/transponder/signal **输入解耦**：只通过 `ingest` 接收证据/等级/文本 key；
  不直接读取/写入这些服务；不写 world/UI/V15。
- 不自动完成：状态推进必须由上层命令/教学 UI 触发 `advance`；选择互斥且只一次。
- 文本为原剧本摘录（draft），待用户二次润色；en 留空不伪译。
- 输出 flags/evidence/reputation/triggers 供 StoryRuntime/UI/声望系统消费；
  本任务不接 UI/剧情运行时/物理；未跑全量回归；未 commit。
