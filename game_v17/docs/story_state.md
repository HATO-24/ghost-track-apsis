# 完整游戏-阶段3A · StoryState 剧情状态服务

> 任务 完整游戏-阶段3A（task-128）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/剧情文本/物理；不接旧场景；未 commit）：
> - `scripts/core/story_state.gd`
> - `tests/story_state_probe.gd`（`PASS=213 FAIL=0`）
> - 本文件

## 1　状态字段（`v17.story_state.v1`，version `1.0.0`）

| 字段 | 类型/范围 | 默认 | 说明 |
| --- | --- | --- | --- |
| `flags` | Dictionary[String → 标量] | `{}` | 剧情 flag（bool/string/number）；名 `^[a-z][a-z0-9_]*$` |
| `evidence_ids` | Array[String]（唯一、排序） | `[]` | 已获证据 id |
| `choices` | Array[{choice_id,t_s,chapter,phase,meta}] | `[]` | 已记录选择；choice_id 唯一 |
| `trust` | float [0,100] | 50 | 副官信任 |
| `morality` | float [-100,100] | 0 | 道德 |
| `reputation` | float [0,100] | 50 | 声望 |
| `threat` | float [0,5] | 1 | 威胁等级 |
| `chapter` | non-empty String | `prelude` | 章节 |
| `phase` | enum | `prelude` | prelude/read/command/decision/consequence/report/end |
| `t_s` | float ≥0，单调 | 0 | 剧情时间 |
| `revision` | int ≥1，单调 | 1 | 状态版本（每次合法变更 +1） |

`snapshot()/vm()` 返回深拷贝只读 VM（含 `ranges`、`branches` 评估、`contracts`、errors）。

## 2　API

| API | 说明 |
| --- | --- |
| `StoryState.new(seed)` / `setup(seed)` | seed 可含上述字段；非法返回 ready=false + errors |
| `set_flag(name, value=true)` / `clear_flag(name)` / `has_flag(name)` / `flag_value(name)` | 设置允许新 flag；**清除未知 flag 拒绝**；非法名/非标量值拒绝 |
| `add_evidence(id)` / `has_evidence(id)` | 证据唯一；重复/非法 id 拒绝 |
| `record_choice(choice_id, meta={})` / `has_choice` | 记录 choice（唯一）；自动带 t_s/chapter/phase/meta |
| `adjust_trust(delta)` / `adjust_morality` / `adjust_reputation` / `adjust_threat` | 加 delta 并 clamp 到范围；返回 before/after/delta/clamped；非有限 delta 拒绝 |
| `set_chapter(ch)` / `set_phase(phase)` | 非空/枚举校验 |
| `set_time(t_s)` | 只允许向前（回退拒绝） |
| `gate(conditions)` | 通用分支条件评估（见 §3） |
| `evaluate_branch(id)` / `evaluate_branches()` / `branch_ids()` | 数据化分支评估（见 §4） |
| `snapshot()` / `vm()` / `to_json()` | 只读快照/JSON |
| `save_state()` → JSON String | 存档（含全部状态字段） |
| `load(data)` | 接受 JSON 字符串或 Dictionary；失败不改现有状态；版本不兼容拒绝 |
| `reset()` | 回到 setup 时初始状态 |
| `check_contracts()` | 不变量检查（范围/唯一/时间/章节/phase） |

- 所有拒绝路径返回 `{ok:false,reason,errors}`，并记录 `errors/contract_errors`；不静默改状态。
- `set_flag` 的 `value` 接受 bool/string/number（标量），非标量拒绝。

## 3　gate 条件（AND 语义）

```
flags[]        全部已设置
flags_any[]    至少一个已设置
flags_not[]    全部未设置
evidence[]     全部证据已获得
evidence_any[] 至少一个证据
choices[]      全部 choice 已记录
trust_min/max, morality_min/max, reputation_min/max, threat_min/max
chapter / chapter_in[] ; phase / phase_in[]
```

- 返回 `{ok, passed, failed[], details, condition_count}`：`ok` = 评估本身成功；
  `passed` = 条件是否全部满足。
- 未满足的条件进入 `failed`（如 `flag_missing:x`、`trust_below_min`、`evidence_missing:...`）；
  **未知条件键** → `ok=false, reason=unknown_condition`（不静默忽略）。
- 条件缺失（flag 未设置）是“不通过”，不是异常；未知分支 id → `unknown_branch`。

## 4　数据化分支（最小条件，不含文案）

| id | name | 条件 |
| --- | --- | --- |
| `aeug` | AEUG | `flags:[aeug_contact]`, `trust_min:60` |
| `ghost_track` | GHOST TRACK | `flags:[ghost_track_found]`, `evidence:[ev_ghost_track]` |
| `procedural_justice` | 程序正义 | `flags:[procedural_justice]`, `reputation_min:60` |
| `misplaced_trust` | 错付 | `flags:[misplaced_trust]`, `trust_min:70` |
| `silence` | 守口如瓶 | `flags:[silence_pact]`, `threat_max:3` |

- `BRANCHES` 常量数据化（id/name/conditions），`evaluate_branches()` 按声明顺序返回全部结果；
  新增分支只需加数据（或后续外置 JSON）。
- 结果 `{branch_id,branch_name,ok,passed,failed,...}`；不做文案/剧情推进。

## 5　DbC / 不变量

- 数值范围：trust[0,100]、morality[-100,100]、reputation[0,100]、threat[0,5]；
  `adjust_*` 自动 clamp 并返回 `clamped`；NaN/INF delta 拒绝。
- flag 名/evidence id/choice id 模式 `^[a-z][a-z0-9_]*$`；evidence 唯一；choice_id 唯一。
- 未知 flag 清除拒绝（`unknown_flag`）；重复证据/选择拒绝。
- 时间 `t_s` 有限、≥0、只增不减；`revision` 每次合法变更递增。
- 不变量检查 `check_contracts()`：范围/phase/chapter/证据唯一/choices 索引一致。

## 6　存档 / 版本

- `save_state()` JSON：`{schema,version,revision,t_s,chapter,phase,flags,evidence_ids,choices,trust,morality,reputation,threat}`。
- `load(data)`：解析 → schema/version 校验（未来 `unsupported_future_version`，其他版本
  `unsupported_version`）→ 在临时实例 `setup(seed)` 校验全部字段 → 成功才替换当前状态；
  失败**不改变**现有状态（probe 验证）。
- 无旧版本迁移（1.0.0 初版）；后续版本在此加迁移骨架。
- JSON 数值往返按浮点；快照一致性用 JSON 规范化比较。

## 7　接入 GameSession（后续，不含 UI/文本）

- StoryState 为独立 `RefCounted`；GameSession 可持有实例，并在 `tick` 后
  `story.set_time(session.now_s())`，订单/通信/选择事件经 session 事件总线转成
  `story.set_flag/add_evidence/record_choice/adjust_*`（由剧情层规则决定，不在本服务硬编码）。
- 存档接入：把 `story.save_state()` JSON 作为 GameSession 存档的嵌套字段（或作为 seed/日志一部分），
  读档时先 `GameSession.load_state` 再 `story.load(...)`；SaveService 只保存整体 payload。
- 分支 gate 由剧情层在决策点调用 `gate(conditions)`/`evaluate_branch(id)`，不自动推进剧情。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/story_state_probe.gd
# V17 STORY STATE PROBE RESULT: PASS=213 FAIL=0（exit 0，只跑一次）
```

覆盖（10 节）：初始/VM 只读/JSON；flags（set/覆盖/清除/未知拒绝/非法名/非法值）；
evidence（唯一/重复/非法 id）；choices（唯一/重复/非法 id/上下文记录）；数值边界
（trust/morality/reputation/threat clamp、NaN/INF 拒绝）；chapter/phase/time（枚举/非空/单调）；
gate（flags/any/not/evidence/choices/chapter/phase/数值范围、未知条件拒绝）；5 分支条件通过/未知分支拒绝；
save/load snapshot 一致/reset/seed；非法 load 不改变状态、拒绝无副作用、JSON/确定性。

## 9　边界 / 未完成

- 只做状态与条件判定：**不做 UI/剧情文本/过场/物理/命令执行**；不写旧场景。
- flags/evidence/choices 为开放数据；没有内置剧情 JSON/文本表（分支条件已数据化，后续可外置）。
- trust/morality/reputation/threat 为线性数值 + clamp，无复杂公式/因果链。
- 存档仅 JSON；无加密/压缩；无旧版本迁移（初版）。
- 未接入 GameSession/SaveService（接入点见 §7）；未跑全量回归；未 commit。
