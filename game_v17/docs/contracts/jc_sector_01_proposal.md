# JC-B03P：阶段性战区行动内容提案（P0-r9-1 · 当前主案 · 待用户核对）

> 卡：JC-B03P [#63](https://github.com/HATO-24/ghost-track-apsis/issues/63)。本轮执行 R9，依据 [Astra 2026-10-29 评审](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/reviews/product_review_20261029/Astra_产品玩法与复古终端评审.md) 与 [Sol 玩法修订稿](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/reviews/product_review_20261029/sol/玩法决策与节奏修订提案.md)，以及 [R9 任务卡](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/tasks/joint_campaign/JC-B03P_scenario_proposal.md)。
>
> **状态：提案文档，不是正典，也未获产品批准。** 本轮只修改提案文档、对照表与待核对参数表；**未修改正式 fixture、probe、运行层或 AI**。具体数值在用户核对前不生效。
>
> 文档基线：`main` = `4e75897ed32f8245f35c5ec584f0ec912ec919c6`（不含 D1；获审 D1 候选为 `b7b1728b9aeec48223b291570ddc8ac7d6f731a7`，PR #75 待合并）。本文件与对照表的最终提交 SHA 由交付 PR/回执记录；文中类 ID、武器 ID 均来自该基线的正式 content。
>
> 机器可校验内容**暂未改动**：`game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json`（schema `v17.jc.scenario_spec.v3`，`P0-r7-1`）与 `integration.jc_scenario_spec`（当前 247/0）仍是旧提案；迁移清单见 [R9 对照与待核对表](../../../docs/tasks/joint_campaign/JC-B03P_R9_review_tables.md)。

## 1. 本版改了什么（R9）

### 1.1 Sol 四项内部矛盾返修（R9-1..R9-4，逐项关闭）

| 编号 | 原矛盾 | 本版处理 |
|---|---|---|
| R9-1 压制机制 | 曾写“友军 railgun 迫使目标开 PD/固定 120 s 火控降级”，且似可按射手身份保证不永久失能 | 删除硬编码减益/免杀：只产生真实 railgun 弹道与损伤；窗口只能来自真实命中、目标可拒绝/可失败的机动反应或玩家创造的条件；任何真实原因造成永久失能都如实裁决，`OBJ-C` 无身份免疫；反应模型如需实现另列 B2/B3 提案参数 |
| R9-2 OBJ-B 能力 | I-OP2 有导弹+railgun，却只写“railgun 火控段失能”就完成 | OBJ-B 军事属性改为**进攻火控整合（导弹 VLS + railgun 两条链）**；两条链都永久失能才算完成，只剩一条则未完成并在战报写明剩余能力；若产品选窄范围，必须缩小属性并注明“仍有另一条进攻链”，不得写全面失能 |
| R9-3 裁决/报告时刻 | 纸面轨迹在最后目标失能后延迟到报告才 victory，和“真实条件达成立即权威终态”矛盾 | 每个轨迹/样例显式分列 `truth_decided_t`、`report_received_t`、`player_view_t`；权威裁决立即发生，报告延迟只改玩家视图；若 B3 需要裁决周期，必须显式列为提案，不能默默等待回报 |
| R9-4 贡献评价 | `有限参与` 要求无目标贡献，但 PT-05 有 1 个目标贡献；玩家独自完成 1 个目标、无友军请求又不属于任何一档 | 评价改为**有序、完备、唯一**的判定：主导 → 有效协同 → 有限参与 → 未参与；每档条件覆盖“1 个目标贡献但无友军请求”“有贡献无请求”“无贡献但有命令/请求”等；评价不影响世界胜负 |

| 项 | 旧提案（R7/R8，已不适用于新数值） | P0-r9-1 修订 | 依据 | 状态 |
|---|---|---|---|---|
| 预算/容量 | 100 点 / 3 舰；池内最贵 20 点，即使选满 3 艘最贵舰也仅 60 点，预算从不生效 | **45 点 / 3 舰**；保留 `round(displacement_t/60)`，用真实组合证明预算与容量各自约束 | Astra §2.1；真实 catalog 排水量 | 待产品核对；**未改 fixture** |
| 两套编制 | SENSOR 30 / STRIKE 55（双 HEMATITE + GANTRY） | 主案 `FORM-SENSOR` **30**（HEMATITE + 2×PALLET）；备选 `FORM-STRIKE` **45**（2×HEMATITE + PALLET）；另列合法混合组合证明取舍 | 真实舰级能力/点数；两套均含 HEMATITE 旗舰 | 待产品核对 |
| 友军 | 2 艘无武装（PALLET + SAFEHARBOR），只做侦察/中继/撤离 | **3 艘有限武装独立友军**：PALLET 侦察 + SAFEHARBOR 中继 + **HEMATITE 武装护航**；独立任务、可拒绝、一次有限火力任务 | Astra §2.2；catalog 中 HEMATITE 实有 railgun/PD | 舰数/舰型/火力额度待核对；不向无武装舰加武器 |
| 结算 | 友军自主完成全部目标 → `stalemate` | **撤销该口径。** 权威目标全部达成即如实为 `victory`；玩家参与不足另列 `command_evaluation` 与战报，不把已完成目标改名为僵局 | Astra §2.3 | 规则提案；运行层未实现 |
| 目标对象 | I-OP2 使用 `33OSID-REQUISITION` 却写“organic fire control”；该级无主炮，仅 PD/EW/boarding | 主案 I-OP2 改用 `33OSID-INTERDICT`（导弹 VLS、railgun-L、PD、EW，存在真实射击火控）；REQUISITION 方案列备选并标明能力不符风险 | 真实 `ships_enemy.json` | 待产品核对；平衡未测 |
| 目标 C | `33OSID-SUMMONS` 被称 command node，但 catalog 无舰队指挥传感器 | 明确其“前哨指挥/中继 aviso”是**场景角色指派**，不是 catalog 传感器自证；永久失能依赖 A03/A04 + B1b，临时断链不计 | 真实 catalog + A03/A04 依赖 | 待核对；依赖未实现 |
| 节奏 | 3600 模拟秒被当作已定战役长度 | 保留 3600 s 为**提案**；30–45 分钟是玩法试验目标，不是已测时长/留存承诺 | Astra §3.1；Sol §4 | 待试玩与产品核对 |

## 2. 三类信息分开列

| 类别 | 内容 |
|---|---|
| **用户已确认** | 阶段性战区行动（不宣告整个第33舰队去军事化）；自有舰队直控 + 独立 AI 友军协同请求；有限弹药/燃料、正常授权、不完整且有延迟的情报；战役内存档 |
| **本提案建议（全部待核对）** | 预算 45 / 容量 3；主案 SENSOR 30 / 备选 STRIKE 45；有限武装友军 3 舰（PALLET + SAFEHARBOR + HEMATITE）；I-OP2 改用 INTERDICT；3 必需目标 + 2 保护目标；3600 s 提案时限；五终态 + `pending_report`；真实战区结果与 `command_evaluation` 分离 |
| **仍待用户选择** | 战区名称/架空年月/单位命名；点数公式与预算/容量；两套编制的具体舰型与旗舰规则；友军舰数/舰级/火力任务额度；I-OP2 是否接受更重的 INTERDICT（或退回 REQUISITION 并改目标语义）；目标对象/失能阈值/证据；时限与终态口径；指挥评价阈值；全部数值是否要按试玩再调 |

## 3. 真实 catalog 绑定与能力

来源：`game_v17/framework/content/ships_friendly.json`、`ships_enemy.json`、`weapons_l1.json`（基线 main `4e75897`）。`APSIS`/`HARMATTAN` 等是**命名舰实例**，不是 `ship_class_id`；本场景继续使用**虚构实例** `I-A1`、`I-P1` 等，不覆盖既有命名映射。

### 3.1 舰级（catalog 事实字段）

| 舰级 | 角色 | 排水量 | 点数* | Δv km/s | 加速度 g | 乘员 | 传感器（catalog 名称） | 武器（catalog 名称） |
|---|---|---:|---:|---:|---:|---:|---|---|
| `OCUVF-PALLET-5C` | picket | 300 t | 5 | 2.54 | 0.15 | 12 | YW-R9, MS-OT2, CH-IR2, ELINT, CH-R0 | **[]** |
| `OCUVF-SAFEHARBOR-1` | relay | 500 t | 8 | 1.97 | 0.12 | 30 | MS-L2, ELINT_array, CH-R0 | **[]** |
| `OCUVF-GANTRY-3M` | missile | 900 t | 15 | 3.80 | 0.08 | 24 | basic_fire_control, CH-R0 | missile_48_cell, point_defense |
| `OCUVF-HEMATITE-6C` | gun | 1200 t | 20 | 3.15 | 0.10 | 68 | LR-4, CH-IR2, CH-R0 | railgun, point_defense |
| `OCUVF-APOGEE` | depot | 9000 t | 150 | 3.15 | 0.02 | 240 | fleet_command, repair_docks, comms | [] |

\* 点数公式本轮仍为提案 `round(displacement_t / 60)`；不是已批准定价。APOGEE 仅作历史/对照，150 点超任何本轮预算，不作为旗舰。

### 3.2 武器（`weapons_l1.json` 事实；用于说明代价，不是平衡结论）

| 武器 | 关键事实 | 与舰级/提案的关系 |
|---|---|---|
| `railgun` | 120 发、1200 km、6 s 冷却、4 s 解算、0.82 精度、0.35 伤害、弹道、不可拦截 | HEMATITE 主炮；两门 = 240 发；火力任务弹药消耗待 B1b/B4 实测 |
| `point_defense` | 80 发、180 km、2 s 冷却、0.65 拦截、自动 | HEMATITE/GANTRY 防御层；别名与 `weapons_l1` 的 `pd` 映射待 B1b |
| `missile` | 8 发/发射位、6000 km、20 s 冷却、10 s 解算、0.9 精度、0.55 伤害、可拦截、salvo_max 4 | GANTRY 的 `missile_48_cell` 是 catalog 名称，`weapons_l1` 条目为 `missile`；**别名/48 单元装填映射未实现，待 B1b** |

传感器型号在 catalog 中是能力标签；基线的统一 sensor range 表未在本卡取证，故本文**不写**未获证的探测距离。实际质量/时效/距离由 B1b/B4 运行验证。

## 4. 舰池、预算、容量与两套方案

- **点数公式（提案）**：`round(displacement_t / 60)`；**预算 45**；**指挥容量 3**；点数与容量是两把不同的锁。
- 池内数量沿用提案：PALLET ×4、HEMATITE ×3、GANTRY ×2、SAFEHARBOR ×1；允许重复选取。
- **旗舰**：`I-A1` = HEMATITE（20 点），`deployment_rule = in_formation`，计入编制与容量，不额外部署；两套预设均含 HEMATITE，保证保护目标 `PROT-2` 有绑定实体。

### 4.1 两套方案（主案 + 至多一备选）

| | **主案 `FORM-SENSOR`（侦察引导）** | **备选 `FORM-STRIKE`（双击突击）** |
|---|---|---|
| 舰型 | HEMATITE + PALLET + PALLET | HEMATITE + HEMATITE + PALLET |
| 点数 / 容量 | **30 / 3** | **45 / 3** |
| 火力 | 1× railgun（120 发）+ PD | 2× railgun（240 发）+ 2× PD |
| 传感/情报 | 2× PALLET（ELINT/YW-R9/MS-OT2/IR）+ HEMATITE LR-4/IR | 1× PALLET + HEMATITE LR-4/IR；侦察平台更少 |
| 战术 | 先建立远距/被动观测，等可靠解算与友军情报，再进入 railgun 窗口；减少盲打与暴露 | 以双主炮更早承诺火力窗口，依赖 PALLET/友军提供定位；弹药/暴露/损伤压力更大 |
| 主要代价 | 只有一门主炮，击杀节奏慢；若敌压迫近，火力不足；更依赖友军/时机 | 预算打满，无法再带中继/第二侦察；探测与链路短板更明显；两门炮会更快消耗弹药 |
| 失败模式 | 观测够但火力窗口不足 → 超时或撤离；被敌 EW/导弹逼退 | 定位不足导致盲打/错过窗口；弹药与损伤先耗尽 → 撤离/失败 |
| 后续验证 | 同一场景下，首次可靠情报、弹药消耗、请求友军次数、敌反应是否与 STRIKE 不同 | 是否能完成同一目标；是否有不同的失败模式；是否仍存在早打/等待/请求协同的选择 |

两套都只是**纸面可行**；不声称已试玩或平衡。后续真实运行必须验证“互不支配”和不同失败模式。

### 4.2 预算与容量各自约束什么（不再是空预算）

| 组合 | 点数 | ≤45？ | ≤3 舰？ | 说明 |
|---|---:|---|---|---|
| 2×HEMATITE + GANTRY | 55 | **否** | 是 | 满火力三舰非法；预算阻止“双主炮 + 导弹” |
| 2×HEMATITE + SAFEHARBOR | 48 | **否** | 是 | 双主炮 + 中继非法；要中继必须牺牲第二门炮 |
| 2×HEMATITE + PALLET | 45 | 是 | 是 | **STRIKE**：第三格只能买侦察，不能再买导弹/中继 |
| HEMATITE + GANTRY + PALLET | 40 | 是 | 是 | 合法混合例：导弹远火 + 单炮 + 侦察；导弹/侦察取代第二门炮 |
| HEMATITE + GANTRY + SAFEHARBOR | 43 | 是 | 是 | 合法混合例：导弹 + 中继，无专用侦察 |
| HEMATITE + 2×PALLET | 30 | 是 | 是 | **SENSOR**：把预算换成两套侦察；火力最低 |
| 任意 4 舰 | — | — | **否** | 容量 3 阻止靠堆小舰补能力 |

结论（提案论证，不是批准结论）：**容量 3** 限制舰数；**预算 45** 限制“第三格买什么”，并排除 55 点的满火力三舰和 48 点的双炮+中继。两把锁共同逼出 SENSOR / STRIKE / 混合取舍。45 的取值为“双主炮+侦察恰好可负担、双主炮+导弹/中继不可负担”的边界值，仍需试玩后核对；不是按进度条任意定价。

## 5. 友军：有限武装、独立任务、可拒绝

`F-ALLY-1`（域 `ally`，**不由玩家直控**）：

| 舰级 | 任务角色 | 能力事实 | 成本/依赖 |
|---|---|---|---|
| PALLET | 前出侦察/ELINT | 无武器；ELINT/YW-R9/MS-OT2/IR 传感器 | +1 实体；B2 AI 侦察任务、链路与情报共享 |
| SAFEHARBOR | 中继/撤离保障 | 无武器；MS-L2/ELINT_array | +1 实体；链路、延迟、失联处理 |
| **HEMATITE** | **有限火力护航** | railgun（120 发）+ PD；无导弹、无 EW、无 boarding | 相对旧 2 舰友军 **+1 实体、+1 独立 AI actor、+2 武器系统**；弹药/燃料/损伤账本依赖 B1b，AI 决策依赖 B2，规模/帧成本待 B4 |

- **独立任务**：走廊护航 + 保护民用中继 `SECTOR-RELAY-CIV`（与玩家保护目标部分重叠，但友军按自己的任务与 ROE 行动）。友军不因玩家请求取消自己的护航职责。
- **可请求行动**：`OBSERVE`（侦察/ELINT）、`RELAY`（中继/链路）、`ESCORT_WITHDRAW`（撤离掩护）、`SUPPRESS`（**一次**真实 railgun 火力任务，只对一个指定军事目标；友军按自身 ROE/任务决定是否接受，不保证命中或效果）。
- **`SUPPRESS` 的物理/行为依据（R9-1 返修）**：友军发射的是 catalog 既有 `railgun` 真实弹道（`weapons_l1`：1200 km、120 发、6 s 冷却、0.82 精度、0.35 伤害、`interceptable=false`）。因此：
  - **只产生真实武器/损伤结果**：命中/未命中、命中部位与伤害由 B1b 逐舰账本判定；目标是否永久失能由真实状态决定，**不因“友军身份”给目标免疫**，也不存在“友军射击必定不击毁”的规则；
  - **不硬编码免杀或免费减益**：本文不施加固定 120 s 火控降级、不声称“迫使目标开 PD”（railgun `interceptable=false`，PD 不构成对该弹道的拦截依据）。“窗口”只能来自真实命中/损伤、目标自身可拒绝/可失败的机动/交战反应，或玩家创造的位置/时间条件；目标反应模型若将来实现，必须作为 B2/B3 的**显式提案参数**另行核对，不能写成已保证效果；
  - 友军任务/ROE 可以限制其瞄准对象与交战条件，但不能保证命中，也不能保证永远不造成永久失能；
  - **权威结果不按射手身份过滤**：若友军、玩家或其他真实原因使任一目标（含 `OBJ-C`）永久失能，战区裁决如实记录；`OBJ-C` 的“玩家职责”只体现在贡献/评价与任务设计，不是目标免疫或“只有玩家能打掉”的硬编码。
- **`SUPPRESS` 提案额度**：每场至多 1 次、至多 24 发 railgun（**待核对提案**）；额度限制的是友军可消耗资源，不是效果保证。若目标在任务中真实被永久失能，按实际原因记入终态与贡献；若未命中/未失能，玩家需自行完成或承担未完成后果。
- **拒绝/受限原因（明确、可解释，不随机）**：`ALLY_TASK_CONFLICT`（护航/民用中继受威胁）、`CIVILIAN_RISK`、`OUT_OF_RANGE`、`LINK_LOST`、`AMMO_RESERVE`、`DAMAGE_LIMIT`、`ROE_DENIED`、`BUSY`。拒绝时玩家仍有直控替代路线（自己打/换目标/等待/撤离）。
- **不暗加武器**：PALLET/SAFEHARBOR catalog `weapons=[]` 保持不变；不把 HEMATITE 的武器复制给它们。
- **若规模实测不允许 3 舰**：备选 `PALLET + HEMATITE`（有侦察、无中继）或 `SAFEHARBOR + HEMATITE`（有中继、无侦察）；失去的能力与请求种类明确列出，不把两舰方案伪装成同样能力。

## 6. 敌方、目标与保护

### 6.1 敌方（真实 catalog）

| 单位 | 舰级 | 真实能力 | 场景职责 | 备注 |
|---|---|---|---|---|
| `I-OP1` | `33OSID-RECOURSE`（destroyer） | UEG-RAILGUN-L、PD、EW jammer；UEG 传感器族 | 前沿守卫/主炮火力 | 目标 A |
| `I-OP2` | `33OSID-INTERDICT`（light cruiser） | UEG-MISSILE-VLS-8、UEG-RAILGUN-L、PD、EW；16 000 t | 区域防空/导弹火力 | **提案改用**；REQUISITION 无主炮，不能诚实称“organic fire control”，仅作备选 |
| `I-OP-C2` | `33OSID-SUMMONS`（aviso） | PD、UEG-ELINT/IFF；无舰队指挥传感器 | **场景指派**的前哨指挥/中继节点 | 目标 C；角色依赖场景，不冒充 catalog 能力 |

- 行为提案：守卫（standoff）→ 被发现/进入目标包线后攻击 → 火控永久失能或任务不可持续时撤退；`I-OP-C2` 保持距离、维持中继/EW，护卫失能后试图脱离。**无 respawn/无脚本波次**；压迫来自真实武器、EW、导弹与时间。
- 敌方攻击/撤退的具体阈值、ROE、导弹/干扰弹量均为待核对参数；本轮无 AI 实现。

### 6.2 目标（真实属性 + 明确依赖）

| 目标 | 对象 | 军事属性 | 完成条件（永久） | 子机制/替代 | 玩家可见 |
|---|---|---|---|---|---|
| `OBJ-A` | I-OP1 | railgun 进攻火控 | railgun 火控链不可恢复失能 | B1b 逐舰损伤账本（未实现）；替代：临时压制**不计永久** | 权威失能 + 报告延迟后显示 |
| `OBJ-B` | I-OP2 | **进攻火控整合（导弹 VLS + railgun 两条链）** | **两条链均不可恢复失能**；只有一条链失效 → 目标未完成，战报明确剩余能力 | B1b 逐舰损伤/火控账本；友军/玩家真实命中均可造成失能，无身份免疫。若产品选择只打某个子系统，则必须把 OBJ-B 军事属性缩小为该子系统，并在战报注明“仍有导弹/railgun 能力”，不能写全面失能 | 同上；未完成时显示剩余能力 |
| `OBJ-C` | I-OP-C2 | 场景指派指挥/中继节点 | 无法继续指挥/中继战区部队（永久） | 依赖 A03/A04 EW+Comms + B1b；替代：断链 ≥300 s 仅临时，不计永久 | 同上；未知时不显示名称/坐标/损伤 |

- `OBJ-C` 的“玩家职责”是**任务/贡献设计**：玩家可直控或授权友军中继/侦察来创造机会；但**目标没有身份免疫**——若友军或其他真实原因使其永久失能，权威结果照常记录（未请求的友军自主造成记友军贡献；玩家授权且执行成功可计授权贡献）。不写“只有玩家能打掉”的硬编码。
- 任务对象仍能战斗、只是通讯中断/EW 干扰 → **不计失能**；目标撤退但未失能 → 不完成；民用设施不得作攻击/胜利对象。

### 6.3 保护目标

| 目标 | 绑定 | 约束 | 损失后果 |
|---|---|---|---|
| `PROT-1` | `SECTOR-RELAY-CIV` | 玩家不得攻击；友军护航任务也保护它 | 被毁 → 本场 `defeat` |
| `PROT-2` | `I-A1` 旗舰 | 旗舰丧失 → 失败 | `defeat` |

## 7. 终态、真实战区结果与指挥评价

### 7.1 终态、权威裁决时刻与报告时刻（R9-3）

| 条件 | 权威终态 | 裁决时刻 | 玩家视图 |
|---|---|---|---|
| 三个必需目标全部**永久**失能 | **victory**（无论谁造成，权威世界结果如实记录） | 真实条件成立时立即 `truth_decided_t` | 报告到达前 `pending_report`/unknown；`report_received_t` 后更新 |
| 旗舰丧失 / 受保护民用被毁 / 时限到达且零完成 | **defeat** | 真实条件成立时立即 | 同上 |
| 玩家主动撤离且目标未全部完成 | **withdrawal** | 撤离条件成立时立即 | 同上 |
| 时限到达且完成 1–2 个必需目标 | **stalemate** | 时限到达时 | 同上 |

- **权威裁决与报告分离**：`truth_decided_t` 是权威终态确立的模拟秒；`report_received_t` 是玩家收到报告的时刻；`player_view_t` 是玩家视图更新时刻。报告延迟**只影响玩家视图/战报显示**，不影响 `truth_decided_t` 或终态；不得“等报告回来才 victory”。
- 每条轨迹/样例必须同时列这三个时刻；`pending_report` 表示权威已定但玩家未知，不重复结算。**若 B3 实际采用裁决周期/完成确认条件，必须作为显式提案参数（P-24）列出；默认为 0（同 tick 立即）**，不能默默等待回报。
- 同 tick 优先级：`defeat > victory > withdrawal > stalemate`；同一 tick 只结算一次；重复/迟到/读档不重复裁决。
- 撤销旧 `contribution_exception`（“全友军完成→stalemate”）与 `ai_cannot_win_alone`；友军如果真实完成目标，战区结果就是完成。若玩家无贡献，另列 `command_evaluation = 未参与` 并在战报中说明，不改写终态。

### 7.2 玩家贡献与指挥评价（R9-4：有序、完备、唯一）

评价是**从高到低的唯一判定**，不同时输出两个等级；评价**不影响**世界胜负。

| 优先级 | 评价（提案阈值，待核对） | 判定条件（满足即止） |
|---:|---|---|
| 1 | `主导` | 玩家直接/授权贡献的必需目标 ≥2/3，旗舰存活，且无民用损失 |
| 2 | `有效协同` | 未达 `主导`；玩家直接/授权贡献的必需目标 ≥1，且 ≥1 次友军请求被接受并执行完成、可观察到改变了条件 |
| 3 | `有限参与` | 未达前两档；玩家执行过 ≥1 条直控命令或 ≥1 次请求，**或**玩家有 ≥1 个目标贡献（含玩家独自完成 1 个目标、没有友军请求执行的情况） |
| 4 | `未参与` | 无玩家直控命令、无请求、无目标贡献 |

- 覆盖示例：玩家独自完成 1 个目标、无友军请求 → `有限参与`；玩家有 2 个目标贡献 + 友军请求 → `主导`（不是 `有效协同`）；玩家有 1 个目标贡献 + 1 次执行成功的友军请求 → `有效协同`；仅发过请求但无贡献 → `有限参与`；全程无命令/请求/贡献 → `未参与`。
- `objective_credit`：玩家直控造成或玩家授权且友军执行成功的请求可计玩家贡献；友军自主造成 → 仅友军贡献。真实命中造成失能即按实际原因记录；不按射手身份过滤。
- 战区结果字段与 `command_evaluation` 分开；战报同时显示权威结果、玩家视图、各目标贡献、友军行动、未确认报告。
- 防挂机不靠改名：依赖友军独立任务/有限火力、`OBJ-C` 玩家独有职责、敌方压迫与保护目标；“不操作”对照见 §9 纸面轨迹；真实实现后用 B3/B4 验证。

## 8. 玩家决策循环（问题 → 行动 → 情报 → 代价 → 结果 → 反馈）

| 环节 | 玩家要解决的问题 | 可选行动 | 情报 | 代价 | 结果 | 反馈 |
|---|---|---|---|---|---|---|
| 简报/组舰 | 三个军事目标与两个保护对象，如何分工 | 选 SENSOR / STRIKE / 合法混合；分配旗舰与第三格 | catalog 能力、任务摘要、估计威胁 | 点数/容量、失去的能力、弹药基数 | 合法编制/非法拒绝原因 | 缺什么能力、为何受限、预期风险 |
| 首次探测 | 主动探测暴露，还是静默/请求友军观测 | 开雷达、被动 IR/ELINT、请求 `OBSERVE` | 初始仅有旧/不完整航迹；未知目标不显示真值 | 暴露、时间、友军延迟/拒绝 | 新航迹/质量/年龄；敌反应 | 来源、观测时刻、时效、未知/过期 |
| 协同承诺 | 自己突破，还是请求牵制/掩护/撤离 | `SUPPRESS` / `ESCORT_WITHDRAW` / `RELAY` | 友军任务、弹药、链路、ROE、距离 | 请求延迟、友军资源、被拒风险 | 接受/拒绝/执行中/完成/失联/受损 | 状态、原因码、ETA、执行证据 |
| 交战/调整 | 现在消耗弹药/Δv，还是等可靠解算/窗口 | 早打、等待、位置机动、换目标 | 火控质量、弹药、Δv、敌 PD/EW | 弹药、燃料、暴露、损伤 | 命中/未命中/失能；敌压力变化 | 可解释的命中/未中原因（只用已知证据） |
| 撤离/结算 | 继续完成目标还是止损 | 继续、主动撤离、接受时限 | 目标完成、保护状态、剩余资源 | 损失、未完成目标 | 权威终态 + 指挥评价 | 战报：结果/贡献/友军/报告时效；不伪装 |

## 9. 纸面轨迹（内容逻辑，非真实战报/AI 证据）

详细时间线见 [R9 对照与待核对表](../../../docs/tasks/joint_campaign/JC-B03P_R9_review_tables.md) §6；这里只列唯一预期：

| 轨迹 | 剧本 | `truth_decided_t`（权威） | `report_received_t`（玩家） | `player_view_t` | 权威终态 | 玩家贡献 | 指挥评价 |
|---|---|---|---:|---|---|---|---|
| `PT-01` 正常/SENSOR | 侦察建图 → 请求侦察/中继 → railgun 打 A/B → 直控 C | **t2000**（C 永久失能即 victory） | t2065（C 报告） | t2065 | `victory` | A/B/C 玩家直接 | `主导` |
| `PT-02` 正常/STRIKE | 双炮快速窗口，依赖友军定位；A/B 更快但弹药/暴露更高 → C | **t1500**（C 失能即 victory） | t1560 | t1560 | `victory`（代价更高） | A/B/C 玩家直接 | `主导` |
| `PT-03` 不操作 | 无命令/无请求；友军只护航；敌方发现并压迫直至旗舰丧失 | **t900**（旗舰丧失即 defeat；若未丧失则 t3600 零完成 defeat） | t1000 | t1000 | `defeat` | 无 | `未参与` |
| `PT-04` 不请求友军 | 单独推进；无侦察/压制/中继；损伤/时间压力下主动撤离 | **t2900**（撤离条件成立即 withdrawal） | t2960 | t2960 | `withdrawal`（2/3 完成） | A/B 玩家直接 | `主导` |
| `PT-05` 友军拒绝/受限 | `SUPPRESS` 因 `ALLY_TASK_CONFLICT` 拒绝；玩家换混合火力/等待导致 B 超时 | **t3600**（时限 1–2 完成即 stalemate） | t3665 | t3665 | `stalemate`（1–2 完成） | 1 个目标（玩家） | `有限参与` |
| `PT-06` 合成全友军（反事实） | 仅用于内容逻辑：友军完成 A/B（C 仍玩家专属）；**当前友军能力不能达到三目标** | 若三目标真实完成则 t2000（合成） | t2065 | t2065 | 若真实完成则 `victory`；当前能力无此战果 | 无 | `未参与` |

- 权威终态在 `truth_decided_t` 立即成立；`report_received_t`/`player_view_t` 只影响玩家看到结果的时间，不改变终态（R9-3）。若 B3 引入裁决周期，必须显式列 P-24，不能把等待报告写成裁决条件。
- `PT-06` 标注“合成/反事实防御测试”，不得当作当前 AI 战报；`PT-03` 是防挂机的纸面验证，不是运行时证据。

## 10. 简报/回执/战报：只交语义字段

成品措辞由 Sol 统稿；以下只定义字段与技术样例，避免把提案文案当正式文本。

### 10.1 简报字段

```json
{
  "scenario_id": "jc_sector_01",
  "briefing_version": "P0-r9-1",
  "player_questions": ["需解除哪些军事能力", "哪些对象必须保护", "如何分担火力/侦察/撤离"],
  "objectives": [{"id": "OBJ-A", "public": "敌方主炮火控", "evidence_needed": "权威失能+报告", "recoverable": false}],
  "protection": [{"id": "PROT-1", "public": "民用中继", "loss": "defeat"}],
  "ally": {"fleet_id": "F-ALLY-1", "task": "走廊护航/民用中继保护", "requests": ["OBSERVE", "RELAY", "ESCORT_WITHDRAW", "SUPPRESS"], "constraints": ["独立任务", "有限弹药", "可拒绝"]},
  "fog": {"known": [], "unknown": "未探测目标不显示名称/坐标/损伤", "report_delay_s": "待定"},
  "resource_envelope": {"points": 45, "capacity": 3, "ammo": "以舰级账本为准"},
  "disclaimer": "所有数值待产品核对；友军不由玩家直控"
}
```

### 10.2 请求/回执语义样例

```json
{"request_id": "REQ-001", "type": "OBSERVE", "to": "F-ALLY-1", "sent_t": 180, "received_t": 210, "status": "accepted", "reason_code": "", "eta_s": 30, "execution_evidence": "track quality report at t=240"}
{"request_id": "REQ-002", "type": "SUPPRESS", "to": "F-ALLY-1", "sent_t": 420, "received_t": 450, "status": "rejected", "reason_code": "ALLY_TASK_CONFLICT", "eta_s": null, "execution_evidence": null}
{"request_id": "REQ-003", "type": "SUPPRESS", "to": "F-ALLY-1", "sent_t": 480, "received_t": 510, "status": "completed", "reason_code": "", "eta_s": null, "weapon": "railgun", "rounds_requested": 24, "rounds_fired": 14, "hits": 3, "observed_damage": "hull/power sections; no permanent disable confirmed", "effect_basis": "real_ballistic_hits", "execution_evidence": "B1b damage record + observation"}
```

状态至少覆盖：`pending`/`accepted`/`rejected`/`executing`/`completed`/`failed`/`lost`（失联）；另含 `damaged` 对执行中受损的语义。拒绝必须有原因码；不得出现无理由随机拒绝或“已收到”伪装完成。`SUPPRESS` 的 `effect_basis` 只允许真实弹道/命中/损伤/目标反应等可观察依据，不写固定火控减益；未出现永久失能或未命中时，回执不得声称已完成目标。

### 10.3 战报字段

```json
{
  "authority_result": "victory",
  "truth_decided_t": 2000,
  "report_received_t": 2065,
  "player_view": "victory",
  "player_view_t": 2065,
  "objective_results": [{"id": "OBJ-A", "truth": "disabled", "observed": "confirmed", "credit": "player_direct", "truth_decided_t": 700, "report_received_t": 718}],
  "ally_actions": [{"type": "OBSERVE", "status": "completed"}, {"type": "SUPPRESS", "status": "completed", "rounds_fired": 14, "hits": 3, "permanent_disables": 0, "effect_basis": "real_ballistic_hits"}],
  "command_evaluation": "有效协同",
  "evaluation_rule_version": "R9-4/priority-1..4",
  "resource_costs": {"ammo": "以账本为准", "fuel": "以账本为准", "damage": "以账本为准"},
  "unresolved": ["报告未回的临时状态"]
}
```

- `authority_result`/`truth_decided_t` 与 `player_view`/`report_received_t` 分开；战报不得用报告时间倒推裁决时间。
- `command_evaluation` 按 §7.2 的有序判定输出唯一等级；`ally_actions` 的真实命中/损伤/永久失能计数只按实际账本，不按身份过滤。

## 11. 待核对参数、旧 fixture 迁移与检查证据

- **待核对参数表**：见 [R9 对照与待核对表](../../../docs/tasks/joint_campaign/JC-B03P_R9_review_tables.md) §7；所有数值状态均为“未批准”。
- **旧 fixture/probe 迁移清单**：见同表 §8；本轮**不修改** `jc_sector_01_proposal.json`、`jc_scenario_spec_probe.gd`、matrix、baseline、运行层。
- **文档检查**：本轮只做 Markdown 链接、JSON 解析、catalog 类/武器/点数交叉引用检查；不跑游戏全量（运行态未变）。命令与结果见同表 §9。

## 12. 明确未实现 / NOT RUN

- B1b 逐舰战斗/损伤/火控账本、导弹/PD 实际射击 → **未实现**；本文“失能”只有提案与内容逻辑。
- B2 独立友军 AI、请求/回执、情报共享 → **未实现**；友军行动均为语义/纸面。
- B3a 目标裁决运行层、B3b 简报/战报接入 → **未实现**。
- 真实战役试玩、30–45 分钟节奏、平衡、性能（实体/AI/帧耗时） → **NOT RUN**。
- 民用设施不作攻击/胜利对象；不扩多人/战争地图/经济/造船。
- 本轮不改正式 fixture/probe/运行层/AI；具体数值待用户核对。

---

## 附录 A：历史方案（已废弃，仅存档对照）

| 旧值/口径 | 问题 |
|---|---|
| 预算 100 / 容量 3 / 单舰最高 20 点 | 三艘最贵仅 60 点，预算从不限制；点数 UI 无决策价值（Astra §2.1） |
| `FORM-STRIKE` = 2×HEMATITE + GANTRY（55 点） | 旧预算下仍无压力；新预算 45 下非法，现改为 2×HEMATITE + PALLET（45） |
| 友军 PALLET + SAFEHARBOR 无武装，仅侦察/中继 | 无法呈现联合战斗；现增 HEMATITE 有限武装独立护航 |
| 友军自主完成全部目标 → `stalemate` | 用玩家参与度改写真实战果；R9 撤销，改为真实结果 + `command_evaluation` |
| I-OP2 = `33OSID-REQUISITION` 却称 organic fire control | 该级无主炮，仅 PD/EW/boarding；现改 INTERDICT 或作为备选并改写属性 |
| 目标 C = SUMMONS 被称 command node | catalog 无舰队指挥传感器；现明确为场景指派的指挥/中继 aviso，依赖 A03/A04 |

旧 fixture `P0-r7-1` 保留原样直到用户核对；迁移时按对照表 §8 逐项改，不把旧轨迹当当前提案证据。
