# PR65 R8 P0 独立复核

审查候选：`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。仅审四个 P0 收尾项，静态核对提案、fixture、probe 与真实 catalog；不重复运行矩阵。未改生产代码、不要求 B1–B3 实现。

## 已关闭 / 达成

- **虚构 I-A1 与既有 apsis 映射分开**：当前 `entity_bindings` 为空，`instance_bindings` 明确 I-A1→HEMATITE、I-P1→PALLET 且 `fictional=true`；既有 apsis→APOGEE、harmattan→PALLET 保留。见提案 `game_v17/docs/contracts/jc_sector_01_proposal.md:31-37`，fixture `game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json:13-31`；probe 检查新实例、catalog 舰级和空 entity bindings，见 `game_v17/tests/jc_scenario_spec_probe.gd:108-126`。符合本项，不再要求恢复 APOGEE旗舰或改用 FERRY。
- **推荐预设与自定义数量边界已补**：明确 SENSOR/STRIKE 是非唯一的推荐预设，给出池数量、允许重复、100 点/最多 3 舰、要求编入旗舰舰级。见提案 `:60-67`，fixture `:814-828`。仍有一处旗舰选择的内部歧义，见下方 P0-1。
- **友军自主完成例外进入 canonical 终态规则**：victory exception、stalemate also-covers、贡献例外字段均列于 `terminal_rules`；主文 8.1 也把友军全自主完成列为推荐 stalemate。见提案 `:116-127`，fixture `:215-260`。probe 的自主轨迹要求不是 victory，见 `game_v17/tests/jc_scenario_spec_probe.gd:348-350`；具体 JSON 轨迹在 `:659-692`。
- **具体简报和战报文字已提供**：简报、玩家胜利战报、友军自主战报均有实际文本并标为虚构样例。见提案 `:150-186`，fixture `:829-858`。胜利样例将两目标归于玩家直控、第三目标由玩家打击并由友军侦察中继辅助，能够区分贡献；文本与其 `TR-FULL-VICTORY` 中 `credited_to=player` 一致（JSON `:383-424`）。

## 仍需收尾的 P0 内容一致性

### P0-1：自定义旗舰选择与固定 I-A1 绑定含义不一致

自定义规则一方面要求至少包含 HEMATITE 旗舰舰级，并固定 `own_flag` / `PROT-2` 到实例 I-A1（提案 `:55-57,64-66,90-95`；JSON `:74-80,208-213,814-828`）；另一方面说玩家可在合法池内“任选一舰作旗舰”，但须与 PROT-2 绑定 I-A1 一致（提案 `:65-66`；JSON `:825-827`）。当前没有定义任选非 HEMATITE 时如何重绑 I-A1/保护目标，也没有说明“任选”实际仅指多艘 HEMATITE 中选择哪一艘。请二选一明确：固定 I-A1 为 HEMATITE、玩家只在编入的同级实例中指定旗舰；或允许任意舰级担任旗舰，并说明自定义实例/PROT-2 如何随编队选择。无需实现编辑器或部署 UI。

### P0-2：友军自主“完成”三个失能目标与其能力定义矛盾

主案把友军限制为无武装侦察、中继、协助撤离（提案 `:69-76`；fixture `:103-111`），且三个目标的 `ally_capable` 全为 false（fixture `:154-158,173-177,192-196`）。真实 PALLET 与 SAFEHARBOR catalog 的 `weapons=[]`（`game_v17/framework/content/ships_friendly.json:145-168,418-445`）。但 `TR-ALLY-AUTONOMOUS-WIN` 仍记录友军独自造成 OBJ-A/B/C 三个目标失能，预期 stalemate（fixture `:659-692`），战报也写“OBJ-A/B/C 均由友军自主造成”（提案 `:175-183`；fixture `:850-857`）。这不是再次要求把无武装友军写成火力支援；而是要求这条单独的内容样例能由已定义能力做到。请将自主样例改成可完成的侦察/中继/撤离支援结果（不冒充目标失能），或把有能力完成失能目标的条件明确为另一个提案阵容/能力选择；保持贡献例外结算语义待用户核对。无需实现任何友军 AI。

## 提案口径

预算/容量、点数公式、舰池数量与组合、旗舰产品选择、战区/日期、目标及阈值、零完成与友军自主贡献终态均仍待用户核对，不因本次静态一致性审查或 probe 通过而成为批准值/正典。
