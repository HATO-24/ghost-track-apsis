# 完整游戏-阶段4C · AfterActionReport 事后报告/分支判定/序章完成

> 任务 task-185。工程 `game_v17`。
> 新文件：`scripts/core/after_action_report.gd`、`tests/report_probe.gd`、
> 本文件、`framework/content/story_report.json`。
> 不改其他；不写 world/UI/V15；未 commit。

## 1　定位

- 汇集序章行动结果（Ceres/Chronos/AV-4412/证据/报告选择/ID13 法律状态与
  政治-信任），判定报告文本与分支 hint，输出 `PROLOGUE_COMPLETE`。
- **demo 只输出 branch_hint + PROLOGUE_COMPLETE，不执行完整结局**（`ending_executed=false`）。
- 报告/分支文本从 docs/44 原样抽取；缺失文本显式 TBD，不伪造。

## 2　输入（ingest / choose_report）

| 输入 | 值 | 说明 |
| --- | --- | --- |
| `ceres` | `rescued` / `ignored` | 谷神-2 救援/忽略 |
| `chronos` | `{evac,blackbox,telemetry,choice}` | 撤离/黑匣子/遥测/接受拒绝 |
| `chronos_*` | 扁平别名 | `chronos_evac/blackbox/telemetry/choice` |
| `av4412` | `strong/standard/question/retreat` | 谈判四选项 |
| `evidence` | 数组或对象 | `blackbox/telemetry/elint/comms`（别名归一） |
| `report_choice` / `choose_report` | `submit_evidence` / `withhold_evidence` | 上报/保密；支持 submit/withhold 别名 |
| `legal_status` | 六态 | ID13 法律状态（仅记录/呈现） |
| `threat` / `trust` | 数值 | 威胁/副官信任（0..1，trust 夹取） |
| `political` | 0..1 或 `aeug/ueg/neutral` | 政治倾向；`political_aeug` 布尔别名 |

- 非法枚举/类型返回明确 reason（`invalid_ceres/invalid_av4412/invalid_evidence/
  invalid_legal_status/invalid_threat/invalid_trust/invalid_political/invalid_choice`），
  失败**不改**已接受输入；未知键仅 warning。
- `ingest` 可多次调用合并；`choose_report` 可改选（提交/保密）。

## 3　判定规则

- **核心完成**：Ceres rescued + Chronos evac + blackbox + telemetry。
- **程序正义线**：核心完成 + AV-4412 `question` + 报告 `submit_evidence` +
  四项证据齐全 → `branch_hint=program_justice`，报告 `report.program_justice`。
- **GHOST/错付/守口线**：核心完成 + 报告 `withhold_evidence` +
  AV-4412 为 strong/standard/question：
  - 政治倾向 ≥ 阈值 且 trust ≥ 阈值 且证据齐全 → `ghost_track`；
  - 政治倾向 ≥ 阈值 且（trust 低 或证据不齐）→ `wrong_justice`；
  - 政治倾向 < 阈值 且 trust ≥ 阈值 → `sleeping`；
  - 其他中性/低低组合 → `ghost_track`（GHOST hint）；
  - 报告模板统一 `report.ghost_track`（docs/44 原文）。
  - 内容还登记 `colonial_savior`/`butterfly` 分支文本，供后续剧情使用；demo 不判定完整结局。
- **其他组合**：`branch_hint=standard`，报告 `report.standard_missing_tbd`（TBD），
  并列出 `missing_items`（如 `ceres_rescued/chronos_evac/chronos_blackbox/
  chronos_telemetry/av4412_question/evidence_*`）。
- 阈值来自内容 `rules.political_threshold=0.6` / `trust_threshold=0.6`，可调。

## 4　文本来源（不改写）

- 来源：`docs/44_新剧本_2193.md` 当前副本第 263–293 行（任务原始行 117–131 区段）。
- 仅去 markdown `> ` 与行首缩进；正文逐字保留；`en` 留空（不伪译）。
- 3 报告模板：
  - `report.program_justice`（269，完成黑匣子/撤离/遥测/质疑/上报）；
  - `report.ghost_track`（275，完成黑匣子/撤离/遥测、普通或强硬、未上报）；
  - `report.standard_missing_tbd`（TBD，其他组合文本 docs/44 未给出，不伪造）。
- 5 分支文本（6 分支描述）：
  - `branch.program_justice`（271，程序正义线）；
  - `branch.ghost_track`（277，GHOST TRACK/错付正义/守口如瓶总述）；
  - `branch.colonial_savior`（279，殖民地的救世主）；
  - `branch.wrong_justice_butterfly`（281，错付的正义/蝴蝶效应同段原文，分支 id
    `wrong_justice`/`butterfly` 共用）；
  - `branch.sleeping`（283，你永远叫不醒一个装睡的人）。
- `reuse_notes`（287/289/291）保留 docs/44 复用说明原文。

## 5　API

| API | 说明 |
| --- | --- |
| `AfterActionReport.new(cfg)` / `setup(cfg)` | cfg：`content`/`content_path`；默认加载本内容 |
| `ingest(value)` | 接受输入并合并；非法原子拒绝；未知键 warning |
| `choose_report(choice)` | 上报/保密选择；非法 reason |
| `compose()` | 判定并返回 `{branch_hint,prologue_status,prologue_complete,ending_executed,report,missing_items,inputs,candidates}` |
| `report()` / `report_text()` | 当前报告（必要时自动 compose） |
| `branch_hint()` / `missing_items()` / `report_choice_value()` | 当前 hint/缺失/选择 |
| `report_template(key)` / `branch_text(branch_id)` / `branch_info(id)` / `branch_ids()` / `text_keys()` | 原文/分支查询 |
| `vm()` / `summary()` / `to_json()` / `check_contracts()` | VM/摘要/JSON/DbC |
| `save_state()` / `load_state()` / `reset()` | 存档/载入/重置 |

- 存档 schema `v17.after_action_report_save.v1`：inputs/composed/branch_hint/
  missing/status/report_choice；非法存档整体拒绝，不改当前状态。
- `PROLOGUE_COMPLETE` 只表示序章报告完成；`ending_executed=false`，不触发完整结局。

## 6　示例

```text
inputs: Ceres rescued; Chronos evac+blackbox+telemetry+accept;
        AV-4412 question; evidence blackbox/telemetry/elint/comms;
        report submit_evidence; legal WATCHLIST; threat 2; trust .8; political .8
→ branch_hint = program_justice
→ prologue_status = PROLOGUE_COMPLETE, ending_executed=false
→ report.text_key = report.program_justice（docs/44 269 原文）

inputs: 同上但 report withhold_evidence; political .9; trust .1
→ branch_hint = wrong_justice（report.ghost_track 原文；missing 空）

inputs: Ceres ignored; 其他缺失
→ branch_hint = standard; report.standard_missing_tbd; missing=[ceres_rescued,...]
```

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/report_probe.gd
# V17 REPORT PROBE RESULT: PASS=965 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：内容/schema/3 报告/5 分支文本/6 分支描述/TBD；ingest 别名/dict evidence/
二次合并/13 类非法原子拒绝/未知键 warning/choose；程序正义完整+9 类缺失+未上报；
GHOST 6 政治/信任/证据组合+core 缺失/retreat；128 行动组合+25 政治/信任网格；
报告/分支逐字 docs/44 + reuse notes；save/load/reset/非法存档/确定性。

## 8　接入 / 边界

- 只做报告/分支判定与文本选择：不执行完整结局、不写 world/UI/V15、不改 Ceres/
  Chronos/AV-4412 链状态；由上层把各链结果 `ingest` 进来。
- 缺失文本用 TBD key，不伪造；分支文本含完整结局描述但 demo 只输出 hint。
- 政治倾向/信任阈值可配置；legal_status/threat 仅记录/呈现，暂不单独改变 branch
  （避免伪造未定规则）。
- 未接 UI/剧情运行时；未跑全量回归；未 commit。
