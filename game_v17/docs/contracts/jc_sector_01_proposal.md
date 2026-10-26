# JC-B03P：阶段性战区行动内容提案（P0-r7-1 · 当前主案 · 待用户核对）

> 卡：#63 · 设计起点 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`
> 状态：**提案，不是正典**。未获用户核对前不得作为默认剧情或默认胜利条件。
> 机器可校验内容：`game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json`（schema `v17.jc.scenario_spec.v3`）
> 校验探针：`integration.jc_scenario_spec`（`game_v17/tests/jc_scenario_spec_probe.gd`，当前 247/0）
> 契约依赖：K0 见 `docs/contracts/joint_campaign_r2.md`（JC-B00）
> 实现依赖：B1b（逐舰战斗账本）、B2（AI 协同）、B3a（目标运行层/裁决）、B3b（简报/战报）
>
> **本文档是唯一当前主案**。旧 62/70 点与 APOGEE 旗舰方案已废弃并移入文末「附录 A 历史方案」，
> 仅存档对照，不再具有效力。

## 1. 三类信息分开列

| 类别 | 内容 |
|---|---|
| **用户已确认** | 阶段性战区行动（不宣告整个第33舰队去军事化）；自有舰队直控＋独立 AI 友军协同请求；有限弹药/燃料、正常授权、不完整且有延迟的情报；战役内存档 |
| **本提案建议（待核对）** | 战区命名与架空日期；点数预算 100 / 指挥容量 3；两套编制 **FORM-SENSOR 30 点** / **FORM-STRIKE 55 点**；旗舰按编制内占位（HEMATITE，20 点）；敌方 3 个军事单位；3 必需目标 + 2 保护目标；时限 3600 s；五种终态；同 tick 优先级 `defeat > victory > withdrawal > stalemate` |
| **仍待用户选择** | 战区名称与年月、参战单位命名、点数公式与预算、编制具体舰型、目标对象与失能阈值、结算口径（含零完成→defeat）、友军自主完成时按 stalemate 推荐是否认可 |

## 2. 战区与时间

| 项 | 提案值 | 说明 |
|---|---|---|
| `scenario_id` | `jc_sector_01` | 独立架空模拟场景，复用既有舰型资产 |
| 战区 | EML1-外侧 / 第33舰队前沿哨区 | 命名待用户核定 |
| 架空日期 | `2193-04-11T08:00:00Z` | 仅记录历元；模拟时间用秒，UTC 不混进 tick |
| 时限 | 3600 s | 提案值 |
| story 依赖 | `story_independent: true` | 主线暂停，但战役裁决照常运行 |

## 3. 真实 catalog 绑定（舰级不是自造字符串）

- 友军：`res://framework/content/ships_friendly.json`；敌方：`ships_enemy.json`。
- 命名舰通过 `entity_bindings` 映射真实舰级：**apsis → `OCUVF-HEMATITE-6C`**、**harmattan → `OCUVF-PALLET-5C`**。
- `APSIS` / `HARMATTAN` **不是** `ship_class_id`，不能自证合法；探针会读取 catalog 逐一校验。

## 4. 舰池、预算、容量与旗舰（已自洽）

点数公式：`round(displacement_t / 60)`（提案，可调）；预算 **100**；指挥容量 **3**。

| 舰级 | 角色 | 排水量 | 点数 |
|---|---|---|---|
| `OCUVF-PALLET-5C` | picket | 300 t | 5 |
| `OCUVF-HEMATITE-6C` | gun | 1200 t | 20 |
| `OCUVF-GANTRY-3M` | missile | 900 t | 15 |
| `OCUVF-SAFEHARBOR-1` | relay | 500 t | 8 |

| 编制 | 角色 | 舰型组合 | 点数 | 舰数 |
|---|---|---|---|---|
| `FORM-SENSOR` | 传感型 | HEMATITE + PALLET + PALLET | **30** | 3 |
| `FORM-STRIKE` | 突击型 | HEMATITE + HEMATITE + GANTRY | **55** | 3 |

**旗舰**：`own_flag.entity_instance_id = I-A1`，舰级 `OCUVF-HEMATITE-6C`（20 点），
`deployment_rule = in_formation` —— **计入编制点数与指挥容量，不额外部署**；
两套编制都包含该舰级，保证任一选择都有旗舰。旧方案用 APOGEE（9000 t → 150 点）超预算，
已废弃（见附录 A）。

## 5. 友军：无武装，只能侦察/中继/协助撤离

`F-ALLY-1`（域 `ally`）：`OCUVF-PALLET-5C` + `OCUVF-SAFEHARBOR-1`。
两个舰级在 catalog 中 **`weapons = []`**，因此：

- `capability = unarmed_recon_relay_withdraw`；
- 三类请求只写**侦察 / 中继 / 协助撤离**，回执**不得**出现「射击位 / 拦截 / 火控失能」；
- 探针直接读 catalog 的 `weapons` 并断言回执无开火表述（负例变体 5 覆盖）。

## 6. 敌方与目标

| 目标 | 对象 | 舰级 | 军事属性 | 完成条件 | 本场可恢复 | 贡献口径 |
|---|---|---|---|---|---|---|
| `OBJ-A` | `I-OP1` | `33OSID-RECOURSE` | organic_fire_control | 火控失能且不可恢复 | 否 | 玩家直控或授权友军请求 |
| `OBJ-B` | `I-OP2` | `33OSID-REQUISITION` | organic_fire_control | 同上 | 否 | 同上 |
| `OBJ-C` | `I-OP-C2` | `33OSID-SUMMONS` | command_node | 无法继续指挥战区部队 | 否 | 仅玩家直控 |

每目标都给出 `disable_mechanism` + `mechanism_dependency` + `mechanism_alternative`：
例如 OBJ-A 依赖 B1b 逐舰损伤账本（未实现），替代口径为「火力压制累计判定临时失能」——
**临时失能可本场恢复，不计永久失能**。

## 7. 保护目标（绑定实体 + 损失后果）

| 目标 | 绑定实体 | 约束 | 损失后果 |
|---|---|---|---|
| `PROT-1` | `SECTOR-RELAY-CIV` | 玩家**不得**攻击民用中继 | 被毁 → 本场 **defeat** |
| `PROT-2` | `I-A1`（旗舰） | — | 旗舰丧失 → **defeat** |

平民/民用设施明确不得作为攻击或胜利条件。

## 8. 终态规则（含同 tick 优先级）

| 条件 | 终态 |
|---|---|
| 三个必需目标全部完成 | **victory** |
| 旗舰丧失 / 受保护民用被毁 / **时限到达且零完成** | **defeat** |
| 玩家主动撤离且目标未达成 | **withdrawal** |
| 时限到达且完成 1~2 个 | **stalemate** |
| 已失能但报告未返回 | **pending_report**（玩家视图 unknown） |

- `timeout_never_yields_victory = true`；
- **同 tick 优先级**：`defeat > victory > withdrawal > stalemate`，同一 tick 只结算一次。
  例：`TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW` —— 同 tick 民用损失 + 撤离完成 → **defeat**
  （修复前校验按事件顺序覆盖成 withdrawal，属规格矛盾，已修正）；
- 零完成只在**时限到达**时判 defeat；主动撤离不算零完成失败；
- 每条轨迹有唯一 `decision_id`；重复裁决幂等（两个裁决事件只结算一次）。

## 9. 权威结果 vs 玩家报告视图（双视图样例）

| 样例 | 权威 | 玩家视图 | 结算 |
|---|---|---|---|
| `DV-1` 全部目标已失能但报告未回 | `all_objectives_disabled` | `unknown` | `pending_report`（不得提前胜利） |
| `DV-2` OBJ-A 已失能且报告已回 | `OBJ-A disabled` | `OBJ-A confirmed` | `in_progress` |

未知目标在玩家视图中不显示名称/坐标/损伤。

## 10. 贡献语义（目标完成与玩家贡献分开）

- `objective_completion`：由权威裁决按**真实状态**判定；
- `objective_credit`：仅当玩家直控造成、或玩家授权的友军请求执行成功，才计入**玩家贡献**；
- 友军自主造成且未被请求覆盖 → 计入**友军贡献**；
- **AI 不得包办首胜**：必需目标全部由友军自主完成时不得判 victory，
  **推荐口径 = stalemate**（保留阶段性成果，不授予玩家胜利）；
- 玩家无操作 → 按 timeout 口径结算，AI 不得代为完成必需目标。

## 11. 简报与战报样例

**简报（briefing）**：任务、必需目标、保护目标、兵力与预算、友军能力、时限、情报限制 7 段。

**战报（debrief）**：权威结算（唯一终态）、各目标终态与判定依据、玩家贡献（射击/授权/造成失能）、
友军贡献（侦察/中继/撤离，不计玩家）、保护目标状态、情报时效（失能→报告延迟）。

## 12. 事件轨迹（14 条，内容逻辑 fixture，非真实战报）

覆盖：完整胜利、全部失能未报告（双视图）、单目标失能未报告、失败、撤离、僵局、零完成超时、
EW 非永久失能、仍能战斗不计失能、友军拒绝替代路线、**友军自主完成（→stalemate）**、
重复裁决幂等、民用损失、**同 tick 民用损失+撤离（→defeat）**。

## 13. 待用户核对清单

1. 战区命名、架空年月、参战单位命名；
2. 点数公式 `round(displacement_t/60)`、预算 100、指挥容量 3；
3. 两套编制（当前 SENSOR 30 点 / STRIKE 55 点）与旗舰按编制内占位的规则；
4. 三个目标对象（`I-OP1`/`I-OP2`/`I-OP-C2`）与失能阈值；
5. 失能机制依赖未实现系统时的替代口径；
6. 零完成 → **defeat** 是否认可；
7. **友军自主完成必需目标时按 stalemate** 的推荐口径是否认可。

## 14. 明确未实现 / NOT RUN

- 真实 AI 行为、逐舰战斗账本、完整战役裁决、可玩首版 —— **未实现**；
- 轨迹是内容逻辑 fixture，**不是真实战报**；
- 运行态试玩、性能（AI 决策/帧耗时）—— **NOT RUN**；
- 民用设施不得作为攻击或胜利对象（明确禁止）。

---

## 附录 A：历史方案（已废弃，仅存档对照）

### A.1 P0-r6-1（已废弃）

| 项 | 旧值 | 问题 |
|---|---|---|
| 编制点数 | FORM-SENSOR 25 / FORM-STRIKE 55 | 与旧正文 62/70 并存，读者无法判断哪个有效 |
| 旗舰 | `OCUVF-APOGEE`（9000 t） | 按本提案公式 = **150 点，超预算 100**；且不在两套编制内，保护对象却绑定该旗舰 |
| 友军 | PALLET + SAFEHARBOR | catalog `weapons=[]`，但回执写「射击位/拦截/火控失能」，与能力矛盾 |
| 终态 | 零完成 → stalemate | 与"零完成即失败"的军事语义及本次归一后的口径不符 |
| 同 tick | 未声明 | 校验按事件顺序覆盖，declared priority 与实现矛盾 |

### A.2 更早的历史片段

- 早期草案曾用 62/70 点编制与非 canonical 舰名（APSIS/HARMATTAN 直接当 class_id），
  已被 §3 的 catalog 绑定取代。
- 这些内容**不得**再被引用为当前提案的一部分；如需考古请看 git 历史。
