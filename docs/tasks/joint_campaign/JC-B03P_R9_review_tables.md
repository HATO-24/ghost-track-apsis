> **历史文档（2026-10-29 R10 起已被取代）**：本 R9 表中的 45 点/3 舰/SENSOR/STRIKE/固定 HEMATITE 旗舰已被用户否定并暂停；不得据此迁移正式 fixture/K0/运行层。当前主案见 [`JC-B03P_scenario_proposal.md`](JC-B03P_scenario_proposal.md) 的 [P0-r10-1](../../../game_v17/docs/contracts/jc_sector_01_proposal.md) 与 [R10 对照表](JC-B03P_R10_review_tables.md)。R9-1..R9-4 的物理压制/OBJ-B 双链/truth-report/评价语义保留。

# JC-B03P R9：两套策略/成本对照、纸面轨迹与待核对参数表

> 卡：JC-B03P [#63](https://github.com/HATO-24/ghost-track-apsis/issues/63)。本文件是 R9 的对照表与待决定表，与 [P0-r9-1 提案](../../../game_v17/docs/contracts/jc_sector_01_proposal.md) 配套。
>
> **状态：全部数值为提案，未获产品批准。** 本轮只改文档；未改正式 fixture、probe、matrix、baseline、运行层、AI。
>
> 文档基线：`main` = `4e75897ed32f8245f35c5ec584f0ec912ec919c6`（不含 D1；D1 获审候选 `b7b1728b9aeec48223b291570ddc8ac7d6f731a7`，PR #75 待合并）。本分支基线 = 上述 main；最终提交 SHA/diff 由交付 PR 记录。
>
> 依据：[Astra 2026-10-29 评审](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/reviews/product_review_20261029/Astra_产品玩法与复古终端评审.md) §2–3；[Sol 玩法修订稿](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/reviews/product_review_20261029/sol/玩法决策与节奏修订提案.md) §1–4；[R9 任务卡](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/tasks/joint_campaign/JC-B03P_scenario_proposal.md)。

## 0. Sol R9 四项内部矛盾逐项关闭表（R9-1..R9-4）

| 编号 | 原矛盾（Sol 复核） | 本轮修订 | 落点 |
|---|---|---|---|
| R9-1 | `SUPPRESS` 被写成固定 120 s 火控降级/迫使开 PD，且似可按射手身份保证不永久失能；railgun `interceptable=false`，无机制依据 | 删除硬编码减益/免杀。`SUPPRESS` 只发射真实 railgun 弹道，效果仅来自真实命中/损伤、目标可拒绝/可失败的机动反应、或玩家创造的条件；不声称 PD 拦截或固定窗口。友军/玩家/其他真实原因造成永久失能都如实记录；`OBJ-C` 是任务/贡献设计，不是身份免疫。若实现目标反应模型，另列 B2/B3 参数（P-25） | 提案 §5、§6.2、§7.1；本表 §4.2、§5、§7 |
| R9-2 | I-OP2 同时有导弹与 railgun，OBJ-B 却只要求 railgun 火控段失能即完成 | OBJ-B 军事属性改为**进攻火控整合（导弹 VLS + railgun 两条链）**；两条链均永久失能才完成；只剩一条则未完成并在战报写剩余能力。若产品选窄范围，须缩小属性并注明仍有另一条进攻链，不能写全面失能 | 提案 §6.2；本表 §5、§6、§8 |
| R9-3 | 纸面轨迹在最后目标失能后等报告才 victory，与“真实条件成立即权威终态”矛盾 | 每条轨迹/样例显式分列 `truth_decided_t`、`report_received_t`、`player_view_t`；权威裁决立即，报告延迟只改玩家视图；B3 若需裁决周期，显式列 P-24，默认 0（同 tick） | 提案 §7.1、§9、§10.3；本表 §6、§7 |
| R9-4 | `有限参与` 要求无目标贡献，但 PT-05 有 1 个目标贡献；玩家独自完成 1 个目标且无友军请求不属于任何档 | 评价改为有序、完备、唯一的判定：**主导 → 有效协同 → 有限参与 → 未参与**；覆盖“1 个目标贡献无请求”“2 个贡献有请求（主导）”“有请求无贡献”等情况；评价不影响世界胜负 | 提案 §7.2、§9；本表 §6、§7、§8 |

## 1. 真实 catalog 依据（本表数值的来源）

- 舰级/武器/传感器：`game_v17/framework/content/ships_friendly.json`、`ships_enemy.json`、`weapons_l1.json`（main `4e75897`）。
- 点数公式仍为提案 `round(displacement_t / 60)`；本表计算只用于证明预算/容量取舍，不是批准定价。
- 统一 sensor range 表未在本卡取证；不写未证实的探测距离。`missile_48_cell`→`missile`、`point_defense`→`pd` 的别名/装填映射依赖 B1b。
- 实体数：本场景纸面 3 玩家舰 + 3 友军舰 + 3 敌舰 + 1 民用中继 = **10 个实体**（另有设施/民用对象按 B3 内容接入）。AI actor 纸面 6（友军 3 + 敌方 3）；B2 未实现，B4 未测。

## 2. 两套策略/成本对照（主案 + 至多一备选）

| 维度 | **FORM-SENSOR（主案）** | **FORM-STRIKE（备选）** |
|---|---|---|
| 编成 | `I-A1` HEMATITE + PALLET + PALLET | `I-A1` HEMATITE + 第二 HEMATITE + PALLET |
| 点数 / 容量 | **30 / 3** | **45 / 3** |
| 舰船实体 | 3 | 3 |
| 主炮 | 1× railgun，120 发基数 | 2× railgun，240 发基数 |
| 点防御 | 1× PD，80 发 | 2× PD，160 发 |
| 传感器平台 | 2× PALLET（ELINT/YW-R9/MS-OT2/CH-IR2/CH-R0）+ HEMATITE LR-4/IR | 1× PALLET + 2× HEMATITE LR-4/IR |
| Δv/加速度（各舰） | HEMATITE 3.15 km/s / 0.10 g；PALLET 2.54 / 0.15 | HEMATITE ×2 3.15 / 0.10；PALLET 2.54 / 0.15 |
| 乘员合计 | 68 + 12 + 12 = 92 | 68 + 68 + 12 = 148 |
| 希望打法 | 先被动/远距建图，等可靠解算与友军情报，进入单一主炮窗口；低暴露、慢击杀 | 双炮更早承诺，依赖 PALLET/友军定位；快击杀、高弹药/暴露/损伤压力 |
| 资源代价 | 只有一门主炮；击杀节奏慢；若敌逼近，火力不足；需友军/时机 | 预算打满；不能带中继/第二侦察；弹药消耗快；探测链路短板明显 |
| 主要失败模式 | 观测够但火力窗口不足→超时/撤离；被 EW/导弹逼退 | 定位不足导致盲射/错过窗口；弹药或损伤先耗尽→撤离/失败 |
| 必须验证 | 首次可靠情报时刻、弹药消耗、友军请求次数/拒绝、敌方反应是否与 STRIKE 不同 | 能否完成同目标；失败模式是否不同；是否仍有“早打/等待/协同”的选择 |
| 当前证据 | 仅 catalog 事实 + 纸面轨迹；**未试玩/未平衡** | 同左 |

**判定**：两套都只是待测起点；若任一套在所有维度支配另一套，先改任务/敌方/成本，再冻结点数（Astra §2.1）。

## 3. 预算与容量各自约束（预算已非空）

| 合法/非法组合 | 点数 | ≤45 | ≤3 舰 | 结论 |
|---|---:|---|---|---|
| 2×HEMATITE + GANTRY | 55 | 否 | 是 | 满火力三舰非法；预算阻止“双主炮+导弹” |
| 2×HEMATITE + SAFEHARBOR | 48 | 否 | 是 | 双主炮+中继非法；中继须牺牲第二门炮 |
| 2×HEMATITE + PALLET | 45 | 是 | 是 | **STRIKE**；第三格只能买侦察 |
| HEMATITE + GANTRY + PALLET | 40 | 是 | 是 | 混合：导弹远火 + 单炮 + 侦察 |
| HEMATITE + GANTRY + SAFEHARBOR | 43 | 是 | 是 | 混合：导弹 + 中继，无专用侦察 |
| HEMATITE + 2×PALLET | 30 | 是 | 是 | **SENSOR**；预算换两套侦察 |
| 任意 4 舰 | — | — | 否 | 容量 3 阻止堆小舰补能力 |

- **容量 3**：限制舰数，不能靠多带小舰补传感器/中继。
- **预算 45**：排除 55 点满火力三舰与 48 点双炮+中继；第三格买侦察/导弹/中继必须取舍。
- 45 是“双主炮+侦察恰好可负担，双主炮+导弹/中继不可负担”的边界提案值；不是按进度条凑数，但仍待试玩和产品核对。

## 4. 友军编组、成本与请求/拒绝

### 4.1 编组与代价

| 舰 | 角色 | catalog 能力事实 | 新增成本/依赖 |
|---|---|---|---|
| PALLET | 前出侦察/ELINT | weapons=[]；ELINT/YW-R9/MS-OT2/CH-IR2/CH-R0 | +1 实体；B2 侦察任务、链路、情报共享 |
| SAFEHARBOR | 中继/撤离保障 | weapons=[]；MS-L2/ELINT_array/CH-R0 | +1 实体；链路/延迟/失联处理 |
| **HEMATITE** | 有限火力护航 | railgun（120 发）+ PD；无导弹/EW/boarding | 相对旧 2 舰友军：**+1 实体、+1 AI actor、+2 武器系统**；弹药/燃料/损伤账本依赖 B1b；AI 依赖 B2；规模/帧成本待 B4 |

- 友军合计 3 舰，独立任务“走廊护航 + 民用中继保护”；**不由玩家直控**，请求经 B2 请求/回执；友军保留自己的 ROE/任务优先级。
- 新增 HEMATITE 不给 PALLET/SAFEHARBOR 暗加武器；两舰仍 `weapons=[]`。
- 若 B4 实测 3 舰规模不允许：备选 `PALLET+HEMATITE`（有侦察、无中继）或 `SAFEHARBOR+HEMATITE`（有中继、无侦察），失去的能力与请求类型明确列出。

### 4.2 请求类型与效果

| 请求 | 友军实际动作 | 对玩家局势的真实影响 | 资源/约束 | 可拒绝原因示例 |
|---|---|---|---|---|
| `OBSERVE` | PALLET 前出/被动 ELINT | 提供带时间戳、质量、来源的航迹；不直接给真值 | 链路、距离、ELINT 暴露 | `ALLY_TASK_CONFLICT`、`OUT_OF_RANGE`、`LINK_LOST`、`BUSY` |
| `RELAY` | SAFEHARBOR 中继/链路延伸 | 降低请求/报告延迟或恢复链路；不创造武器效果 | 中继可用、链路、位置 | `CIVILIAN_RISK`、`LINK_LOST`、`DAMAGE_LIMIT` |
| `ESCORT_WITHDRAW` | HEMATITE 护航/牵制追击 | 改变撤离窗口/追击压力；不保证无伤 | 自身任务、弹药/燃料、受损 | `ALLY_TASK_CONFLICT`、`AMMO_RESERVE`、`DAMAGE_LIMIT` |
| `SUPPRESS` | HEMATITE 一次**真实** railgun 火力任务（只打指定军事目标） | **只有实际武器/行为结果**：真实弹道命中/未命中与 B1b 伤害；目标可拒绝/可失败的机动/交战反应；**没有**固定 120 s 火控降级，也不因射手身份保证“不永久失能” | 每场 ≤1 次、≤24 发（提案）、射程、ROE；railgun `interceptable=false`，不把 PD 当作该弹道的拦截依据 | `OUT_OF_RANGE`、`AMMO_RESERVE`、`ALLY_TASK_CONFLICT`、`ROE_DENIED` |
| 被动（无请求） | 友军按独立任务护航/侦察/中继 | 玩家可能观察到友军行动/报告，但不能假定其接受进攻请求 | 友军自身任务 | — |

- 拒绝必须带原因码与可理解解释；玩家有替代路线（自己打/换目标/等待/撤离）。不写“随机拒绝”。
- **R9-1 关闭**：`SUPPRESS` 的任务/ROE 可限制瞄准对象，但不保证命中，也不保证永远不造成永久失能。若真实命中使目标永久失能（含 `OBJ-C`），权威结果照常记录；玩家授权且友军执行成功、真实造成失能的可计授权贡献；未请求的友军自主造成记友军贡献。目标反应模型若将来实现，必须作为 B2/B3 提案参数（P-25）另行核对，不写成已保证效果。

## 5. 目标/敌方能力对照（真实 catalog vs 旧提案）

| 对象 | 旧提案 | 真实能力 | 本版处理 |
|---|---|---|---|
| I-OP1 `33OSID-RECOURSE` | organic_fire_control | UEG-RAILGUN-L、PD、EW；7500 t；真实主炮 | 保留目标 A（火控失能） |
| I-OP2 `33OSID-REQUISITION` | organic_fire_control | **无主炮**，仅 PD/EW/boarding；4200 t | 主案改用 `33OSID-INTERDICT`（导弹 VLS-8、railgun-L、PD、EW；16000 t）；REQUISITION 作为低强度备选并改属性语义 |
| **OBJ-B（I-OP2）** | organic_fire_control（只写 railgun） | INTERDICT 同时有导弹 VLS 与 railgun 两套进攻链 | 军事属性改为**进攻火控整合（导弹 VLS + railgun）**；两条链均永久失能才完成；只剩一条 → OBJ-B 未完成，战报写剩余能力。窄范围备选必须同步缩小军事属性并注明“仍有另一条进攻链”，不得写全面失能 |
| I-OP-C2 `33OSID-SUMMONS` | command_node | PD、UEG-ELINT/IFF；无舰队指挥传感器；1800 t | 明确“场景指派的前哨指挥/中继 aviso”，不是 catalog 能力自证 |
| `SECTOR-RELAY-CIV` | 民用中继 | 非战斗对象 | 保护目标，禁止攻击 |
| `I-A1` HEMATITE | 旗舰 | railgun/PD；1200 t | 保护目标 + 旗舰，计入编制 |

- I-OP2 换 INTERDICT 会显著提高敌方质量/火力，是**未测平衡提案**；若产品认为过重，退回 REQUISITION 时必须把 OBJ-B 的军事属性改为“护航 PD/EW 火控”并承认它不是主炮火控，不得继续写 organic fire control。
- **R9-2 关闭**：OBJ-B 不写“铁路炮火控段失能=全面失能”。主案要求导弹 VLS 火控链与 railgun 火控链**两条都永久失能**；只失能一条时目标仍有相关进攻能力，OBJ-B 未完成、战报必须写明剩余能力。若采用窄范围（只打某子系统），同步缩小 OBJ-B 的军事属性并加“仍有另一条进攻链”的说明。
- 目标 C 的永久失能依赖 A03/A04 EW+Comms + B1b；临时断链/EW 不计永久，任务对象仍能战斗不计失能。**R9-1 边界**：目标 C 的玩家职责只是任务/贡献设计，没有身份免疫；若友军或其他真实原因使其永久失能，权威结果照常记录。

## 6. 纸面轨迹（内容逻辑，不是真实战报/AI/读档证据）

时间单位模拟秒；玩家/友军位置为示意，不是已实现轨迹。

| 轨迹 | 关键事件（提案时间线） | `truth_decided_t` | `report_received_t` / `player_view_t` | 权威终态 | 玩家贡献 | 指挥评价 | 备注 |
|---|---|---|---:|---|---|---|---|
| `PT-01` 正常/SENSOR | t0 简报/部署；t180 PALLET 被动/ELINT 首获 I-OP1；t240 请求 `OBSERVE` 接受；t300 友军报告；t420 请求 `SUPPRESS` I-OP1，友军执行真实 railgun 射击（不保证命中/失能）；t480 玩家进入射击条件；t700 OBJ-A 永久失能；t900 `RELAY`；t1100 交战 I-OP2；t1500 OBJ-B 两条链均永久失能；t1700 接近 C；t2000 OBJ-C 永久失能 | **t2000** | t2065 / t2065 | `victory` | A/B/C 玩家直接 | `主导` | 友军可侦察/中继/真实射击，但不保证失能；无固定减益 |
| `PT-02` 正常/STRIKE | t0 简报；t150 单 PALLET 被动探测；t240 `OBSERVE`；t360 双炮打 A；t520 OBJ-A；t650 弹药/暴露压力；t800 打 B；t1150 OBJ-B（两条链）；t1400 定位 C；t1500 OBJ-C 失能 | **t1500** | t1560 / t1560 | `victory`（更快但消耗/损伤更高） | A/B/C 玩家直接 | `主导` | 用于验证与 SENSOR 不同失败模式 |
| `PT-03` 不操作 | t0 部署后无命令/无请求；友军独立护航、无进攻请求；t300 敌方发现玩家；t600 首次真实命中 I-A1；t900 旗舰丧失/失去作战能力 | **t900** | t1000 / t1000 | `defeat`（若旗舰未丧失则 t3600 零完成 defeat） | 无 | `未参与` | 防挂机纸面对照，不是运行证据 |
| `PT-04` 不请求友军 | t0 无友军请求；t400 被动/IR 建图；t700 打 A；t1100 OBJ-A；t1300 PALLET 受损；t1500 打 B；t2100 OBJ-B；t2400 旗舰损伤/弹药压力；t2600 无法稳定定位 C；t2900 玩家主动撤离 | **t2900** | t2960 / t2960 | `withdrawal`（2/3 完成） | A/B 玩家直接 | `主导` | 展示友军对时间/风险/中继的影响；评价不受撤离改写 |
| `PT-05` 友军拒绝/受限 | t420 `SUPPRESS` 被拒 `ALLY_TASK_CONFLICT`；玩家改混合火力/等待；t2500 OBJ-A/B 中仅 1 个稳定完成；t3600 时限到达 | **t3600** | t3665 / t3665 | `stalemate`（1–2 完成） | 1 个目标（玩家） | `有限参与` | 有 1 个目标贡献但未达主导：R9-4 的唯一归属 |
| `PT-06` 合成全友军 | 反事实防御测试：合成输入设定友军自主使 A/B/C 全部永久失能，且旗舰与受保护民用完好；不判断当前 AI 能否实际达成 | **t2000**（合成） | t2065 / t2065 | `victory`（合成输入，非实测战果） | 无 | `未参与` | 标“合成/反事实”，不得当 AI 战报 |

- **R9-3**：权威终态在 `truth_decided_t` 立即成立；报告/视图时间只影响玩家看到结果，不改变终态。`PT-01/02/03` 的旧“报告后才 victory/defeat”已改为先裁决后报告。
- **R9-4**：评价按“主导 → 有效协同 → 有限参与 → 未参与”有序判定；`PT-05` 有 1 个目标贡献但未达主导/有效协同 → `有限参与`，不再与旧“有限参与=无贡献”冲突；玩家独自完成 1 目标且无请求同样为 `有限参与`。
- `PT-03` 的“不操作→defeat”依赖敌方真实压迫和玩家位置；若运行时测试显示不操作也能长期无事，说明关卡职责/敌压不足，应改任务而非改结算。
- `PT-06` 用于验证“真实结果与参与度分离”：若世界真完成，结果就是完成；指挥评价单独写未参与，不改写为 stalemate。

## 7. 待核对参数表（全部未批准）

| ID | 参数 | 提案值 | 依据/说明 | 状态 / 待核对 |
|---|---|---|---|---|
| P-01 | `scenario_id`/战区名/架空年月/单位命名 | `jc_sector_01`；EML1-外侧/第33舰队前哨；`2193-04-11T08:00:00Z` | 沿用旧提案；纯内容 | 待产品核对 |
| P-02 | 时间单位/时限 | 模拟秒；`duration_s = 3600` | 旧提案；与 30–45 分钟玩法目标**不是同一概念** | 待试玩/核对 |
| P-03 | 点数公式 | `round(displacement_t/60)` | 透明可复算；但仍为提案 | 待核对；不得当批准定价 |
| P-04 | 预算 | **45** | 排除 55/48 组合，保留 45 组合；见 §3 | 待核对；未改 fixture |
| P-05 | 指挥容量 | **3** | 限制舰数；与预算共同约束 | 待核对 |
| P-06 | 舰池数量 | PALLET×4、HEMATITE×3、GANTRY×2、SAFEHARBOR×1 | 旧提案池；允许重复 | 待核对 |
| P-07 | 主案编制 | SENSOR = HEMATITE+2×PALLET，30 点 | 真实 catalog 点数 | 待核对/试玩 |
| P-08 | 备选编制 | STRIKE = 2×HEMATITE+PALLET，45 点 | 替换旧 55 点非法组合 | 待核对/试玩 |
| P-09 | 旗舰规则 | I-A1 HEMATITE，编制内 20 点，不额外部署 | 与 PROT-2 绑定；不替用户选其他旗舰 | 待核对 |
| P-10 | 友军舰数/舰级 | PALLET + SAFEHARBOR + HEMATITE（3 舰） | Astra §2.2；catalog 实有武器 | 待核对；规模 B4 |
| P-11 | 友军独立任务/ROE | 走廊护航 + 民用中继保护；可拒绝 | 不扩 AI；请求语义待 B2 | 待核对 |
| P-12 | `SUPPRESS` 额度/效果 | 每场 ≤1 次、≤24 发 railgun；**不保证命中/窗口/减益**；效果只来自真实弹道/命中/损伤或目标自身可拒绝/可失败的反应 | 提案额度；railgun `interceptable=false`；反应模型另列 P-25 | 待核对/B1b/B2 |
| P-13 | 友军拒绝原因码 | 见 §4.2 | 可解释、非随机 | 待核对/B2 |
| P-14 | 敌方编成 | I-OP1 RECOURSE；I-OP2 INTERDICT（主案）；I-OP-C2 SUMMONS | 真实 catalog；INTERDICT 较重 | 待核对；备选 REQUISITION |
| P-15 | 敌方行为 | 守卫→攻击→火控失能/任务不可持续时撤退；无 respawn | 最小规则；阈值未定 | 待核对/B2 |
| P-16 | 失能阈值/证据 | 永久失能需真实状态 + 证据；临时压制/断链不计；OBJ-B 两条进攻链均需永久失能 | 依赖 B1b/A03/A04；替代口径明确 | 待核对 |
| P-17 | 保护目标/损失 | PROT-1 民用中继被毁 defeat；PROT-2 旗舰丧失 defeat | 旧提案保留 | 待核对 |
| P-18 | 终态规则 | victory 三目标永久失能；defeat 旗舰/民用/零完成；withdrawal 主动撤离；stalemate 1–2；pending_report 权威/视图分离；`truth_decided_t` 立即、报告只改视图 | 撤销旧 contribution_exception；R9-3 | 待产品核对 |
| P-19 | 同 tick 优先级 | `defeat > victory > withdrawal > stalemate`，只结算一次 | 旧提案保留 | 待核对 |
| P-20 | `command_evaluation` 阈值 | 有序唯一：主导 → 有效协同 → 有限参与 → 未参与，见提案 §7.2；覆盖 1 个目标贡献无请求等情况 | 新设计；不改战区结果；R9-4 | 待核对 |
| P-21 | 报告延迟/情报时效 | 语义字段先定；数值待 B2/B3/B4 | 旧样例 18/42/65 s 仅示例 | 待核对；本轮不生效 |
| P-22 | 实体/AI/性能规模 | 纸面 10 实体、6 AI actor；帧/决策成本 NOT RUN | B2/B4 未实现 | 待测 |
| P-23 | 试玩目标 | 约 30–45 分钟实际游玩目标；非已测时长/留存承诺 | Astra §3.1 / Sol §4 | 待玩家测试 |
| P-24 | 权威裁决周期/完成确认 | 默认 0（同 tick 立即）；若 B3 有周期/确认条件，必须显式配置并记录 `truth_decided_t`，不能等报告才裁决 | R9-3；B3 未实现 | 待核对/B3 |
| P-25 | 目标反应/降级模型（如将来实现） | **不默认存在**；若实现，需另列触发条件/概率/拒绝条件/时效，不得固定 120 s 减益或按身份免杀 | R9-1；B2 未实现 | 待核对；当前无 |
| P-26 | OBJ-B 打击范围 | 主案=导弹 VLS 火控 + railgun 火控两条链均永久失能；备选=仅某一子系统且战报注明剩余攻击链 | R9-2 | 待产品核对 |
| P-27 | 射手身份免疫/贡献过滤 | **无身份免疫**：任何真实原因造成失能均如实裁决；贡献只按实际授权/执行/命中归属 | R9-1/R9-4 | 待核对；规则提案 |

## 8. 旧 fixture/probe/契约迁移清单（本轮不执行）

| 工件 | 旧值/字段 | 迁移后（提案） | 影响/时机 |
|---|---|---|---|
| `game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json` | schema v3 / `proposal_version=P0-r7-1` | 候选 v4 / `P0-r9-1`；**本轮不改** | 获产品核对后另卡/同一后续提交 |
| 同上 `fleet_pool.points_budget` | 100 | 45 | probe 预算/合法性断言更新 |
| 同上 `formations[]` | SENSOR 30 / STRIKE 55（2×HEM+GANTRY） | SENSOR 30 / STRIKE 45（2×HEM+PALLET）；保留混合合法例说明 | probe 期望点数/组合更新 |
| 同上 `own_flag` | HEMATITE 20，in_formation | 保留；补充 I-A1/PROT-2 绑定说明 | 基本不变 |
| 同上 `ally_force` | 2 舰、`capability=unarmed_...`、请求仅 3 类 | 3 舰（+HEMATITE）、`limited_armed_independent_escort`、请求 +`SUPPRESS`、独立任务/ROE/拒绝码 | probe 友军武器/请求/拒绝断言扩展 |
| 同上 `opfor.units[I-OP2]` | `33OSID-REQUISITION` + organic_fire_control | `33OSID-INTERDICT` + **导弹 VLS 火控 + railgun 火控两条链**；备选处理写清 | probe 类 ID/能力/OBJ-B 双链断言更新；平衡待测 |
| 同上 `objectives[OBJ-B]` | 只写 railgun/PD 火控，单链失能即完成 | 军事属性=进攻火控整合；**导弹 VLS 火控 + railgun 火控均永久失能**才完成；只剩一链→未完成且战报写剩余能力（P-26） | probe 完成条件/负面断言扩展 |
| 同上 `objectives[OBJ-C]` | `command_node` 直接引用 SUMMONS | 明确场景指派角色、A03/A04/B1b 依赖、玩家直控 credit；**无身份免疫**，友军/其他真实原因造成失能照常记录 | probe 依赖/贡献断言扩展 |
| 同上 `terminal_rules.victory.exception` / `contribution_exception` | 全友军→stalemate | **删除**；victory 只按真实三目标；新增 `command_evaluation` 独立字段与 `truth_decided_t`/`report_received_t`/`player_view_t` | probe 终态断言改为 truth victory + 评价未参与；时刻字段校验 |
| 同上 `contribution_rules` | `ai_cannot_win_alone` / `ai_autonomous_recommendation` | 改为 objective_credit + **有序唯一** command_evaluation（主导→有效协同→有限参与→未参与）；友军自主只影响评价；无身份过滤 | probe 贡献/评价断言重写；覆盖 1 目标无请求案例 |
| 同上 `event_traces` | 14 条；`TR-ALLY-AUTONOMOUS-WIN` 期望 stalemate | 改期望 victory+评价未参与（标合成）；新增无操作/不请求友军/友军拒绝受限/真实射击轨迹；`TR-ALLY-REFUSE-ALTERNATIVE` 期望按内容重定；每条补 truth/report/player_view 时刻 | probe 轨迹断言扩展；不把旧轨迹当新证据 |
| 同上 `text_samples`/简报/战报 | 旧长文案 | 只保留语义字段；成品措辞由 Sol 统稿 | 文案卡处理；不在本卡改 |
| 同上 `user_decisions_pending` | 旧 7 项 | 用本表 §7 的 P-01..P-27 替换 | 产品核对清单 |
| `game_v17/tests/jc_scenario_spec_probe.gd` | 当前 247/0 | 随上述 fixture 迁移更新断言；**本轮不改** | 后续实现/校验卡，需独立红绿证据 |
| `game_v17/docs/contracts/joint_campaign_r2.md`（K0） | 无 `command_evaluation`/友军任务/请求扩展字段 | 后续 K0 增补（字段/枚举/校验）；本轮不改 | 与 B03P 内容迁移同一批准批次 |
| `docs/tasks/joint_campaign/JC-B03P_scenario_proposal.md` | R8 旧状态 | 顶部 R9 执行记录 + 指向 P0-r9-1；保留历史 | 本轮文档更新 |
| 运行层/正式 fixture/probe/matrix/baseline | — | **保持原样** | 数值批准前禁用改动 |

## 9. 本轮文档检查（不跑游戏全量）

### 9.1 命令

```powershell
python .tmp_r9_doc_check.py
git diff --check
git status --short
git diff --stat 4e75897ed32f8245f35c5ec584f0ec912ec919c6 -- docs game_v17/docs/contracts/jc_sector_01_proposal.md
```

### 9.2 检查内容

1. 解析 `wc -l`/Markdown 表格结构（R9 提案/表）；
2. 相对链接指向的仓库文件存在；
3. catalog 类 ID/舰级存在、武器 ID 与 catalog 一致（别名显式列出）；
4. 点数公式复算与 §3 表一致；
5. fixture JSON 可解析、旧 schema/提案版本未被改动；
6. `git diff --name-only` 仅文档，不含 fixture/probe/运行层；
7. R9-1..R9-4 文本一致性：无固定 120 s 窗口承诺、OBJ-B 双链、三时刻字段、评价优先级顺序、P-24..P-27 均存在。

### 9.3 DeepSeek 原交付检查（45233c47，Sol 文字清理前）

一次性检查脚本（未提交，仅本轮取证）解析三份 Markdown、catalog JSON、fixture JSON，并核对相对链接/点数/类 ID/四项返修文本：

```text
R9 DOC CHECK: checks=52 failures=0
EXIT=0
```

- 相对链接：三份文档全部可解析且目标存在（0 缺失）；
- catalog：友军 PALLET/SAFEHARBOR `weapons=[]`、HEMATITE `railgun/point_defense`、GANTRY `missile_48_cell/point_defense`、敌方 RECOURSE/INTERDICT/SUMMONS 均存在；
- 点数复算：PALLET 5、SAFEHARBOR 8、GANTRY 15、HEMATITE 20、APOGEE 150；SENSOR 30、STRIKE 45；55/48 组合超预算；
- fixture 未改：schema 仍为 `v17.jc.scenario_spec.v3`、`proposal_version=P0-r7-1`、预算仍 100、友军仍 `unarmed_recon_relay_withdraw`、旧 `contribution_exception` 仍在（本轮只列迁移，不执行）；
- R9-1：无“窗口 ≤120 s”承诺；`SUPPRESS` 只写真实弹道/命中/目标反应；无身份免疫；
- R9-2：OBJ-B 导弹 VLS + railgun 两条链均写清；
- R9-3：提案/轨迹/战报均有 `truth_decided_t`/`report_received_t`/`player_view_t`；
- R9-4：评价顺序“主导 → 有效协同 → 有限参与 → 未参与”与“1 个目标贡献无请求→有限参与”均在文档中；P-24..P-27 存在；
- `git diff --check`：无输出（exit 0）；
- 变更范围：仅提案 + 对照表（任务卡保持上一轮 R9 记录）；`git diff --numstat` = 提案 `+236/-174`、对照表 `+234/-0`；无 fixture/probe/运行层/AI 变更。

原交付工件 SHA256/行数（45233c47 对应交付；此后 Sol 文字清理会改变主案哈希，不能作为最终 HEAD 哈希）：

| 文件 | 行数 | SHA256 |
|---|---:|---|
| `game_v17/docs/contracts/jc_sector_01_proposal.md` | 291 | `bc3aa4c652488184f465b6cf2e04888332cddcf1c53fa1e085aa32dd52b800f6` |
| `docs/tasks/joint_campaign/JC-B03P_scenario_proposal.md` | 74 | `aefcddfdd013e107982e71c98d83c3f7e3039fae88cb26bc51016e4eb2299fd5` |

本对照表自身的最终 SHA256 见交付 PR/回执（自引用哈希会随回填变化，故不在此表内写自哈希）。

**NOT RUN（本轮明确未执行）**：游戏全量、部署/战役/战斗探针、AI、30–45 分钟试玩、性能/实体规模测量、真实读档续行。本轮没有任何运行态证据，不能称战役可玩。


## 10. 交接状态

- 交付物：本对照表 + [P0-r9-1 提案](../../../game_v17/docs/contracts/jc_sector_01_proposal.md) + 任务卡 R9 执行记录；未改任何 fixture/probe/运行层/AI。
- 下一步：Sol 技术核对 → 用户产品核对（§7 全部参数）→ 另卡更新 fixture/probe/K0 → 才进入 B3 实现。
- 本卡保持 OPEN；不启动下一卡。完成后代码下一项为原 **#45**（基于包含 D1 的 main），不是 B2/B1b/B3。

### Sol 收尾说明（2026-10-29）

R9-1..R9-4 主规则保留。Sol 仅清理主案/本表 PT-06 的“C 玩家专属/友军必然不能完成”残留：该轨迹明确输入友军自主完成 A/B/C、保护对象完好，唯一预期 victory + 未参与。它不证明当前 AI 可以或不可以完成；不新增身份免疫。主案防挂机说明改为拟定主责分工。未改任何数值、正式 fixture/probe/运行层/AI；未重跑原一次性脚本或游戏。最终复核以 PR 评论中的 40 位 HEAD 为准。
