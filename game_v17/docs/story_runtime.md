# 完整游戏-阶段3B · StoryRuntime 剧情运行时

> 任务 完整游戏-阶段3B（task-134）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/物理；未 commit）：
> - `scripts/core/story_runtime.gd`
> - `framework/content/story_transit_l4_l1.json`
> - `tests/story_runtime_probe.gd`（`PASS=349 FAIL=0`）
> - 本文件
> 只是剧情运行时/内容数据：不渲染文本、不接 UI、不写 world/V15。

## 1　数据流

```
teaching_l4_l1.json（教学步骤引用）  +  story_transit_l4_l1.json（章节/步骤/动作/条件）
        │
        ▼
StoryRuntime（chapter/phase/step 状态机，manual note）
        │  effects: flags/evidence/choice/trust/morality/reputation/threat
        ▼
StoryState（可选绑定）  ←→  GameSession（可选绑定：时间/自动 story_state）
```

- 内容只引用 `text_key`（TXT-…），不写长文案；运行时输出 text_key 供 UI 层取文本。
- 只由玩家 `note(action,target)` 推进；`manual_only=true`、`auto_complete=false`；**不自动完成**。
- StoryState/GameSession 均为可选绑定：无 StoryState 时用内部镜像做 gate/效果；绑定后效果写入 StoryState。

## 2　内容 schema（`v17.story_content.v1`）

```json
{
  "schema":"v17.story_content.v1", "version":"1.0.0",
  "scenario_id":"transit_l4_l1", "title_key":"TXT-0001",
  "teaching_file":"res://framework/content/teaching_l4_l1.json",
  "manual_only":true, "auto_complete":false,
  "chapters":[{"id","title_key","phase","order"}],
  "steps":[{
    "id","chapter","phase","order","title_key","objective_key",
    "teaching_step_ids":["T07-G1-S1"], "text_keys":["TXT-0001"],
    "actions":[{
      "id","action","target","label_key",
      "gate":{...}, "effects":{"flags":[],"evidence":[],"choice":"",
        "trust":0,"morality":0,"reputation":0,"threat":0},
      "advance":true, "ending":"END_HOLD", "locked_reason":"..."
    }]
  }],
  "endings":[{"id","title_key","flags":["choice_hold"]}]
}
```

- 校验：schema/version/scenario/manual_only/auto_complete；chapter/step id 唯一、order 合法、phase 枚举；
  step 至少 1 个 action、action id 唯一、label_key 非空、gate/effects 对象；
  `teaching_step_ids` 必须存在于 `teaching_l4_l1.json`（缺失仅 warning）；action `ending` 必须存在。
- 示例内容覆盖 L4-02 Hammer → L1 Meridian 段 8 步：序章交接、设航线、点火、接触列表、识别、
  雷达命令、HOLD/EXPOSE 分支、提交报告；分支 ending `END_HOLD` / `END_EXPOSE`。
- 教学文件（`teaching.l4_l1.v1`）只读取步骤 id 用于关联，不复制其长文本/UI 结构。

## 3　状态机 / API

状态：`idle → running → awaiting_complete → complete`，另 `skipped` / `failed`（终态）。
`chapter`/`phase`/`step_id` 随当前步骤；`history[]` 记录每次合法 note。

| API | 说明 |
| --- | --- |
| `StoryRuntime.new(opts)` / `setup(opts)` | opts：story_path/teaching_path/story_state/session/t_s；加载+校验内容 |
| `load_content(story_path, teaching_path)` | 加载/校验内容；失败 `ok=false` 不 ready |
| `validate_content(story_dict, teach_dict)` | 内容校验（公开，供 CI/probe） |
| `start(from_chapter="")` | 从首步/指定章节首步开始；重置 history/status |
| `note(action, target="")` | 手动行动：仅当前 step 的**可用** action 可推进；错误 action/目标/locked 均拒绝且不改状态 |
| `complete()` | 仅 `awaiting_complete` 可完成（所有步骤推进后显式完成）；不自动 |
| `skip(reason)` / `fail(reason)` | 显式跳过/失败（终态） |
| `reset()` | 回到 idle（不清空已绑定的 StoryState 效果） |
| `menu()` / `available_actions()` | 动态行动菜单：`{id,action,target,label_key,available,locked,reason,advance}` |
| `eval_gate(conditions)` | gate 判定：绑定 StoryState 时用 StoryState.gate，否则内部镜像子集 |
| `apply_effects(effects)` | 应用 flags/evidence/choice/trust/morality/reputation/threat（同步 StoryState） |
| `bind_story_state(ss)` / `bind_session(session)` | 绑定 StoryState/GameSession（session 自动绑定其 story_state，时间取 session.now_s） |
| `current_step()` / `chapter_list()` / `step_list()` / `ending_list()` / `text_keys()` | 只读内容/当前步骤/文本 key |
| `snapshot()` / `vm()` / `to_dict()` / `to_json()` | 只读 VM（含 step/menu/applied/history/story/contracts） |
| `save_state()` → JSON String / `load_state(json)` | 内存 JSON；含 runtime 状态 + 绑定 StoryState 快照 |
| `check_contracts()` | 状态/step/chapter/phase/数值范围/StoryState 不变量 |

### 3.1　note 语义

1. 未 `start()` → `not_started`；终态 → `already_terminal`。
2. 在当前 step 的 actions 中匹配 `action` 与 `target`（action.target 为空则不限制目标）；
   无匹配 → `wrong_action` / `target_mismatch`，不改状态。
3. 用 gate 判定可用性；locked → `action_locked` + `failed[]`/`locked_reason`，不改状态。
4. 可用 → 应用 effects（flags/evidence/choice/trust…）→ 追加 history → `advance=true` 时进入下一步；
   最后一步推进后状态为 **`awaiting_complete`**（不是 complete，需显式 `complete()`）。
5. 分支由不同 action/target 的 effects/ending 表达（如 hold/expose）。

### 3.2　行动菜单

- 当前 step 的每个 action 依据 gate 生成 `available` / `locked` / `reason`；
  locked reason 取自 gate failed 列表或 action.locked_reason（如 `no_fire_authority`）。
- 菜单/文本 key 只读输出，不渲染；UI 层按 `label_key` 取文本。

## 4　StoryState / GameSession 集成

- `bind_story_state(ss)`：flags/evidence/choices/stats 同步到内部镜像；effects 通过
  `set_flag/add_evidence/record_choice/adjust_*` 写入 StoryState；gate 直接使用 `StoryState.gate`。
- `bind_session(session)`：时间取 `session.now_s()`；若 session 有 `story_state` 且未绑定则自动绑定；
  effects 直接写入 `session.story_state`（不写 world/UI）。
- 不自动完成、不按时间触发；GameSession tick 不会推进剧情（仅时间同步）。

## 5　存档

`save_state()` 返回 JSON：

```text
{
  schema:"v17.story_runtime_save.v1", version:"1.0.0",
  story_path, teaching_path,
  chapter, phase, step_id, step_index, status, ending, reason, t_s,
  history[], flags{}, evidence[], choices[],
  trust, morality, reputation, threat,
  story_save: <绑定的 StoryState.save_state()> | ""
}
```

- `load_state(json)`：校验 schema/version/step/status/StoryState 快照 → 应用；
  步/状态/快照非法均拒绝，失败不改当前 runtime 核心状态；绑定 StoryState 时恢复其快照。
- 未绑定 StoryState 时 `story_save` 忽略（runtime 状态仍恢复）；内容文件需当前 runtime 已加载。
- 无 UI/文件写入；SaveService/GameSession 的外层存档可嵌套本 JSON。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/story_runtime_probe.gd
# V17 STORY RUNTIME PROBE RESULT: PASS=349 FAIL=0（exit 0，只跑一次）
```

覆盖（10 节）：内容文件 schema/chapters/steps/endings/text_keys/teaching 引用；setup/start/
章节起始/菜单/text_keys/无 StoryState 运行；完整步骤 S1→S8（effects→StoryState flags/evidence/
choice/trust、awaiting→显式 complete、ending）；乱序/重复/目标不匹配/locked action 拒绝且不改状态；
hold/expose 分支 ending/trust/choice 差异与确定性；skip/fail/提前 complete/reset；save/load
（snapshot+StoryState 一致、继续推进、非法存档拒绝不改状态、无 StoryState 加载）；GameSession
绑定（自动绑定/时间/效果/存档一致）；内容校验（manual_only/auto_complete/steps/重复/action/phase/schema、
未知 teaching 引用仅 warning）；JSON/同操作确定性。

## 7　边界 / 未完成

- 不实现 UI/文本渲染/物理/过场；只输出 text_key/菜单/状态；长文案不在内容文件中。
- 内容示例仅覆盖 L4→L1 段（8 步/4 章/2 ending）；完整关卡/多章节/多分支需补内容数据。
- gate 为 StoryState 条件子集 + 内部镜像；不做复杂表达式/脚本条件。
- effects 顺序应用；StoryState 异常时错误可见（不静默），未做跨 effect 事务回滚。
- 教学文件只读取步骤 id 关联；不复制教学 UI/验收结构，不做计时/自动触发。
- 存档只内存 JSON；无文件槽位（由 SaveService 负责）；未接旧 HUD/bridge/V15。
- 未跑全量回归；未 commit。
