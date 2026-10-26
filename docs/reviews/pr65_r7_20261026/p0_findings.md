# PR65 R7 P0 复核发现

审查对象：候选 `2ae7bf7cba8af32ff4456cefe28efa3650b868dd`。范围仅为 #63/P0 内容方案；核对了提案 Markdown、JSON fixture、probe 和真实 ships catalog。未复跑根代理负责的矩阵，也未要求 B1–B3 实现。

## 已关闭的原残项

- **150 点 APOGEE 不再作为当前 100 点预算内旗舰方案**：当前方案用 20 点 HEMATITE，计入编制点数和容量，两套范例均含 HEMATITE；APOGEE 放在历史附录。见提案 `game_v17/docs/contracts/jc_sector_01_proposal.md:48-56,160-163`，fixture `game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json:59-77,538-541`。但命名映射需澄清，见 P0-1。
- **友军无武装却有开火回执**：当前限定 PALLET/SAFEHARBOR 侦察、中继和撤离支援，未再写射击、拦截或造成火控失能。提案 `:58-65`；catalog 的 PALLET/SAFEHARBOR `weapons=[]` 分别见 `game_v17/framework/content/ships_friendly.json:145-168,418-445`。
- **旧正文与新方案并存**：当前主案明确唯一有效，旧方案置于历史附录。见提案 `:1-11,160-171`。
- **同 tick defeat 优先**：主案明确 `defeat > victory > withdrawal > stalemate`，同 tick 民用损失与撤离轨迹期望 defeat。见提案 `:98-103,132-134`，fixture `:207-208,502-515`。
- **双视图及自主友军完成轨迹**：DV-1 覆盖权威全完成、玩家仍 unknown；另有友军自主完成轨迹。见提案 `:105-121,130-134`，fixture `:218-236,328-342,456-470`。该轨迹与同 tick probe 的逻辑已有覆盖；仍需把胜利例外写入终态表，见 P0-3。

## 待澄清或补齐

### P0-1：APSIS 命名映射需与真实 catalog 对齐

提案将 `apsis → OCUVF-HEMATITE-6C` 写作 `entity_bindings`（`game_v17/docs/contracts/jc_sector_01_proposal.md:31-35`），fixture 也将 `apsis` 绑定到 HEMATITE（`:12-24`）；真实 catalog 的 `entity_bindings.apsis` 实为 `APSIS`，而 APSIS 是 OCUVF-APOGEE 下的既有命名实体（`game_v17/framework/content/ships_friendly.json:70-75,79-88,106-114`）。与此同时，fixture 的旗舰实例标为新 ID `I-A1`、舰级 HEMATITE（`game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json:59-64`）。这两种设定可以区分：新虚构的 `I-A1` 使用 HEMATITE 是可行提案；把既有命名实体 `apsis` 说成 HEMATITE 则与 catalog 冲突。请删除/修正该既有实体映射，或明确旗舰是另一个新命名实例，并让文档、fixture、probe 对齐。无需将 `I-A1` 改为 FERRY，也无需恢复 APOGEE 旗舰方案。

### P0-2：旗舰选择与自定义编制边界未说清

当前列出 `FORM-SENSOR` 和 `FORM-STRIKE` 两个编制（提案 `:48-56`；fixture `:66-78`），并写 P2 从池中选择编制（fixture `:268-270`）。这可以是两个预设范例，材料不足以断言玩家只能二选一；但也没有明确玩家能否自定义、可选舰池/数量边界，以及自定义编制时旗舰如何选择/占位。请说明这两套是范例还是唯一选项；若允许自定义，补充用户可编制并直控的边界规则及旗舰选择约束。点数、容量仍只是待核对提案值。

### P0-3：终态表应显式列出友军自主完成的胜利例外

probe 的 `_trace` 逻辑先对全部必需目标完成加入 victory 候选，再检测 `ally_only` 并移除 victory、加入 stalemate（`game_v17/tests/jc_scenario_spec_probe.gd:275-294`）；因此 `TR-ALLY-AUTONOMOUS-WIN` 期望 stalemate 有规则校验支持。贡献规则也明确写“不得判 victory；推荐 stalemate”（提案 `:116-121`；fixture `:210-216`）。残项是主案终态表只列“三个必需目标全部完成 → victory”（提案 `:90-96`；fixture `:192-208`），没有把这个例外写在 canonical 终态规则处，且仍标作推荐待选。请把例外与推荐/待用户核对状态一并并入终态规则，保持探针轨迹、规则表一致。

### P0-4：简报/战报样例仍是字段提纲

提案仅列简报七段及战报应含的字段（`:123-128`）；fixture `briefing_sample.sections` 和 `debrief_sample.sections` 也只是标签和简短描述（`:238-260`），不是可直接审阅的完整样例文本。请各给一份具体样例，能看到任务/目标/约束/时限/情报限制，以及唯一终态理由、目标依据、玩家与友军分列贡献、报告延迟等字段如何落到实际文字中。样例可标注虚构，不代表批准内容。

## 边界

战区、日期、点数公式/预算、目标与阈值、结算口径等仍是待用户核对提案，不能写成已批准或正典。本复核不要求提前实现 B1–B3。
