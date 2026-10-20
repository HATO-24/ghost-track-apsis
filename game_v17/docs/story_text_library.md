# 完整游戏-阶段3T · StoryTextLibrary 序章文本库

> 任务 task-170。工程 `game_v17`。
> 新文件：`scripts/core/story_text_library.gd`、`tests/story_text_probe.gd`、
> 本文件、`framework/content/story_prologue_text.json`。
> 不改其他；不写 UI/world/V15；未 commit。

## 1　来源与抽取原则

- **唯一来源**：`docs/44_新剧本_2193.md`（工作区完整剧本副本）。
- **原样抽取，不改写**：`zh` 字段为对应行去掉行首全角缩进后的原文；
  标点/空格/中英混排/`[姓名待补]` 等占位全部保留；不伪译、不总结、不替换角色。
- 任务给的原始剧本行号（briefing 38 / deputy 53–58 / nav 61–63 / comms 65–68 /
  arrival 72）在 docs/44 副本中的对应实际行：
  - briefing.body → **56**
  - deputy.* → **74–79**（74 hello / 75 terminal / 76 nav / 78 nav_panel / 79 command）
  - nav.wrong_dest → **82**；nav.correct / nav.depart_prompt → **84**
  - comms.hammer → **86–87**（只取正文 87，from/to 在 86）
  - comms.formation → **88–89**（只取正文 89）
  - nav.arrival_prompt → **93**
- `source_lines` 记录 docs/44 实际行；`draft=true` 表示待人工润色（en 全为空/TBD，
  不伪造翻译）。
- 特别约束：**Ceres-2 等实体不在本文件改写**；文本只含原剧本中出现的表述。

## 2　内容 schema（`story_prologue_text.json`）

```text
schema: v17.story_text.v1, version 1.0.0
title/source/source_path（../docs/44_新剧本_2193.md）/extracted_at/draft
entries: [{
  id: STXT-xxxx,
  text_key,                 # 唯一
  channel: briefing|deputy|nav|comms,
  speaker_role, listener_role, mode,
  source_lines: [docs/44 行号],
  draft: true,
  zh: 原文（逐字）,
  en: "",                   # 留空/TBD，不伪译
  vars: [变量名...],
  var_specs: {变量名: 文本中的占位 token},
  note
}]
```

## 3　条目（12）

| text_key | channel | 角色 | source_lines | 变量 |
| --- | --- | --- | --- | --- |
| briefing.body | briefing | command_briefing→commander | 56 | — |
| deputy.hello | deputy | deputy→commander | 74 | deputy_name（`[姓名待补]`） |
| deputy.terminal | deputy | deputy→commander | 75 | — |
| deputy.nav | deputy | deputy→commander | 76 | — |
| deputy.nav_panel | deputy | deputy→commander | 78 | — |
| deputy.command | deputy | deputy→commander | 79 | — |
| nav.wrong_dest | nav | navigation_system→commander | 82 | — |
| nav.correct | nav | navigation_system→commander | 84 | — |
| nav.depart_prompt | nav | navigation_system→commander | 84 | — |
| comms.hammer | comms | hammer_port_control→id13 | 86–87 | — |
| comms.formation | comms | apsis→fleet | 88–89 | — |
| nav.arrival_prompt | nav | deputy→commander | 93 | — |

- `nav.correct` 与 `nav.depart_prompt` 同源句（docs/44 第 84 行），按任务要求拆为两个 key，
  文本不改写；如需拆分语义由后续润色任务决定。

## 4　API

| API | 说明 |
| --- | --- |
| `StoryTextLibrary.new(cfg)` / `setup(cfg)` | cfg：`content` 或 `content_path`；默认加载本内容 |
| `load_content(path)` / `load_data(value)` / `validate(value)` | 读取/校验/应用；失败原子（保留旧状态） |
| `ready/errors/warnings` | 状态 |
| `text_keys()` / `entry_ids()` / `channels()` / `roles()` | 列表 |
| `get_text(text_key, lang="zh")` | 条目只读副本；未知 key 空 |
| `Object.get(text_key)`（`_get` 兼容） | 直接按 key 取条目（未知 null） |
| `get(text_key)` | 同 Object.get（GDScript 动态属性兼容） |
| `by_channel(channel)` / `by_role(role)` | 按频道/角色筛选 |
| `source_lines(key="")` | 条目/全部源行 |
| `render(text_key, vars={}, lang="zh")` | 渲染；缺变量→`missing_variables`；en 空→`missing_translation`；未知 key/lang 明确错误 |
| `verify_against_source(path="")` / `verify_content_against_source(value,path="")` | 与 docs/44 逐字校验（返回 mismatches） |
| `to_dict()/to_json()/summary()/check_contracts()` | 内容/JSON/摘要/DbC |

变量：`deputy.hello` 需要 `deputy_name`；`render` 支持 `var_specs`（如
`[姓名待补]`）与 `{var}`/`{{var}}`；缺变量不静默输出原文占位。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/story_text_probe.gd
# V17 STORY TEXT PROBE RESULT: PASS=482 FAIL=0（exit 0，只跑一次）
```

覆盖（5 节）：12 key/字段/频道/角色/唯一；docs/44 逐字匹配 + 关键句 + en 不伪译 +
verify 可发现改写；render 无变量/缺变量/替换/en 错误；14 类非法内容原子拒绝；
to_dict/to_json 往返与两次加载/verify 确定性。

## 6　接入 / 边界

- 只读文本库；不写 UI/world/V15；不接旧场景/剧情运行时。后续序章 UI/StoryRuntime
  用 `get_text/render` + `source_lines` 取文本、按 `draft` 标记待润色。
- `en` 全空/TBD，不做伪翻译；`draft=true`，中文文本待用户二次润色。
- 不修改 docs/44 原文；不改写/总结/替换角色；占位符保留。
- 未接 UI/物理；未跑全量回归；未 commit。
