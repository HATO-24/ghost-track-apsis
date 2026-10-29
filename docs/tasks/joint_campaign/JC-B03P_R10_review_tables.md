# JC-B03P R10：ID13 满编核对、自由分组、时间预算与待核对参数表

> 卡：JC-B03P [#63](https://github.com/HATO-24/ghost-track-apsis/issues/63)。本文件与 [P0-r10-1 提案](../../../game_v17/docs/contracts/jc_sector_01_proposal.md) 配套，按 Sol R10 交接执行。
>
> **状态：全部数值/舰数/分组/时限为提案，未获产品批准。** 本轮只改提案、对照表、参数/迁移清单与交接说明；**未改正式 fixture、probe、matrix、baseline、运行层或 AI**。
>
> 基线：`main` = `4e75897ed32f8245f35c5ec584f0ec912ec919c6`（不含 D1；D1 获审候选 `b7b1728b9aeec48223b291570ddc8ac7d6f731a7`，PR #75 待合并）；R10 基于 Sol 清理后的 `cd73473b57a3e1fd2c3e06d6c3f1f1f0bc78b33a`。
>
> **已暂停、不得迁移/定价**：R9 的 45 点预算 / 3 舰容量 / 固定 HEMATITE 旗舰。用户要求先给满编 ID13、自由分组、可扩充可选舰只。
>
> 依据：`docs/03_世界观.md` §6.2–6.3；`docs/04_舰船设定.md` §7/§12.4/§12.8；`game_v17/framework/content/ships_friendly.json`；`fleet_roster.json`（提案数据，不等于正典）；[Astra 评审](https://github.com/HATO-24/ghost-track-apsis/blob/05aaf861aa8c0913cb9d139c7771d94732d27698/docs/reviews/product_review_20261029/Astra_产品玩法与复古终端评审.md)；[Sol R9 复核与 R10 交接](https://github.com/HATO-24/ghost-track-apsis/pull/76)。

## 0. R9 已关闭项保留 + R10 变更摘要

| 项 | R9（保留/暂停） | R10 |
|---|---|---|
| R9-1 压制 | CLOSED：真实弹道/命中/目标反应，无固定减益/身份免杀 | 保留 |
| R9-2 OBJ-B | CLOSED：导弹 VLS + railgun 双链均失能才完成 | 保留 |
| R9-3 truth/report | CLOSED：权威立即裁决，报告只改玩家视图 | 保留；R10 轨迹继续列三时刻 |
| R9-4 评价 | CLOSED：主导→有效协同→有限参与→未参与，有序唯一 | 保留 |
| 编组/预算 | 45 点/3 舰/SENSOR/STRIKE/固定 HEMATITE 旗舰 | **暂停**；改为满编 ID13 + 自由分组；不冻结点数 |
| 旗舰 | I-A1 HEMATITE | **APSIS 远地点号 APOGEE**（设定旗舰；不按 150 点排除；不暗设免费战斗单位） |
| 时间 | 3600 s 被当硬时限 | 拆成模拟时长/交火窗口/阶段/真实时长；3600 s=1×60 min；硬时限待定 |
| 规模 | 未列 D1/B1b/B1c/B2/B3/B4 | 逐项列影响与规模风险；D1 旧范围不自动覆盖新方案 |

## 1. 设定与 catalog 依据

### 1.1 舰级事实（ships_friendly.json，main `4e75897`）

| 舰级 | 英文/型号 | 角色 | 干重 | Δv km/s | 加速度 g | 乘员 | 传感器 | 武器 |
|---|---|---|---:|---:|---:|---:|---|---|
| `OCUVF-APOGEE` | Apogee / 刺桐-2M | depot | 9000 t | 3.15 | 0.02 | 240 | fleet_command, repair_docks, comms | [] |
| `OCUVF-PALLET-5C` | Pallet-5C | picket | 300 t | 2.54 | 0.15 | 12 | YW-R9, MS-OT2, CH-IR2, ELINT, CH-R0 | [] |
| `OCUVF-HEMATITE-6C` | Hematite-6C | gun | 1200 t | 3.15 | 0.10 | 68 | LR-4, CH-IR2, CH-R0 | railgun, point_defense |
| `OCUVF-GANTRY-3M` | Gantry-3M | missile | 900 t | 3.80 | 0.08 | 24 | basic_fire_control, CH-R0 | missile_48_cell, point_defense |
| `OCUVF-MOONPORT-4` | Moonport-4 | tanker | 2000 t | 10.63 | 0.01 | 18 | CH-R0 | [] |
| `OCUVF-SAFEHARBOR-1` | Safeharbor-1 | relay | 500 t | 1.97 | 0.12 | 30 | MS-L2, ELINT_array, CH-R0 | [] |
| `OCUVF-WINCH-2` | Winch-2 | tug | 400 t | 3.15 | 0.20 | 9 | CH-R0 | [] |
| `OCUVF-ARIA-1` | Aria-1 | shuttle | 20 t | 6.12 | 1.0 | 3 | CH-R0 | [] |

- `railgun`（weapons_l1）：1200 km、120 发、6 s 冷却、4 s 解算、0.82 精度、0.35 伤害、`interceptable=false`。
- `missile`（weapons_l1）：6000 km、8 发/发射位、20 s 冷却、10 s 解算、0.9 精度、0.55 伤害、可拦截、salvo_max 4；GANTRY 的 catalog 名 `missile_48_cell` 与 weapons_l1 的 `missile` 映射待 B1b。
- 统一传感器最大距离未取证；本表只写 catalog 型号，不写未证实的探测距离。

### 1.2 设定明确/未明确/候选

| 类别 | 内容 |
|---|---|
| **设定已明确** | APSIS（APOGEE 旗舰，001）、HARMATTAN（PALLET 114）、FERRY（HEMATITE 201）、WATCHTOWER（SAFEHARBOR 501）、DEEPWELL（MOONPORT 401）；ARIA-1 类型、APSIS 携带 1–2 架 |
| **满编数量未明确** | ID13 独立舰总数；哨舰/炮舰/导弹舰/油船/中继/拖船各自数量；哪些舰名属于正式名册；`docs/03` §6.3 明确还有“未列入正式编制表的船”可借调/购买改装 |
| **拟扩充/借调候选** | PERIGEE（第二 APOGEE，docs 提到同级二号舰但未说在 ID13）、KRAKATOA/ST HELENS（第二/第三 GANTRY）、ANCHOR/TOWHOOK（第二 WINCH）、SEALING WAX/BULLA（第二/第三 ARIA）、未列名借调/采购船 |
| **不得直接冒充满编** | `fleet_roster.json` 的 13 条提案表、命名池、旧 45/3 舰池都不是正典满编事实 |

## 2. ID13 满编建议清单（提案，不是正典）

### 2.1 建议清单

| 舰名 | 舰级 | 数量建议 | 设定状态 | 作用/理由 |
|---|---|---:|---|---|
| APSIS | APOGEE | 1 | **明确** | 旗舰/船坞/维修/指挥；损失→战役结束；无武器 |
| HARMATTAN | PALLET-5C | 1 | **明确** | 远程搜索/ELINT/AWACS 核心 |
| LEE_SHORE | PALLET-5C | 1 | 建议 | 第二哨舰，避免单点传感器损失；命名来自舰名池 |
| FERRY | HEMATITE-6C | 1 | **明确** | 近距 railgun/PD 火力 |
| ANVIL | HEMATITE-6C | 1 | 建议 | 第二炮舰，双炮/轮换；不声称正典已列装 |
| VESUVIUS | GANTRY-3M | 1 | 建议 | 远程导弹；无远程搜索，依赖哨舰 |
| DEEPWELL | MOONPORT-4 | 1 | **明确** | 舰队燃料/航程；无武器；脆弱 |
| SPRINGHEAD | MOONPORT-4 | 1 | 建议 | 第二油船，支持分组/远距离行动 |
| WATCHTOWER | SAFEHARBOR-1 | 1 | **明确** | 中继/ELINT；命令延迟 45→8 s |
| BEACON | SAFEHARBOR-1 | 1 | 建议 | 第二中继，支持分组链路/备份 |
| BOLLARD | WINCH-2 | 1 | 建议 | 拖救/打捞/救援，非战斗 |
| MISSIVE（ARIA-1） | ARIA-1 | 1–2（APSIS 携带） | 类型明确，数量/命名建议 | 人员转移/救援，不占独立编制 |

- **合计：11 艘独立舰 + 1–2 架舰载穿梭机**。5 艘独立舰设定明确；6 艘独立舰为建议；穿梭机数量 1–2 为设定范围、名称/具体数量待核对。
- 按提案 roster 数值：约 18 300 t 干重、约 529 人、约 16 000 t 燃料；只是提案，不是批准上限，不能用于定价。
- 满编建议是供用户/Astra 核对的一体清单；若用户选择更小满编或把某些候选转正/删去，需改此表与后续 fixture，不在本卡执行。

### 2.2 可扩充/借调候选（默认不计入满编）

| 候选 | 舰级 | 用途 | 风险/备注 |
|---|---|---|---|
| PERIGEE | APOGEE | 第二船坞舰/备份旗舰 | docs 提到同级二号舰但未说在 ID13；不能默认免费第二旗舰 |
| KRAKATOA / ST HELENS | GANTRY-3M | 第二/第三弹舱舰 | 用于 G3 双导弹实验；需产品批准扩充；导弹耗尽后弱 |
| ANCHOR / WHOOK | WINCH-2 | 第二拖船 | 救援/回收备份 |
| SEALING WAX / BULLA | ARIA-1 | 第二/第三穿梭机 | 舰载/救援；数量待定 |
| 未列名借调/采购船 | 现有/明确排期舰种 | 临时补位 | docs/03 已说明存在；不因此暗加武器/新系统 |

## 3. 所有权、任务部署、分遣/留后方与旗舰

| 层次 | 含义 | 本场实体 | 能力/风险 |
|---|---|---|---|
| **owned** | ID13 全舰队名册（满编建议）；玩家拥有比任务更多的舰 | 否（全部） | 可选池；不等于全部免费战力 |
| **deployed** | 进入本场战区的子集 | 是 | 只有部署舰提供本场传感/火力/中继/维修；承担损失 |
| **reserve/detached** | 未进战区/留后方/其他分遣 | 否 | 无即时全图传感/火力/维修/中继；只能按后勤调度延迟支援，需时间/燃料/风险 |
| **旗舰 APSIS** | 船坞/指挥/维修核心；损失→战役结束 | 取决于玩家 | 战区后方支援（有风险）或留后方（无本场维修/指挥）；不是免费战斗单位 |

### 3.1 旗舰与支援选项

| 选项 | 本场能力 | 风险/代价 | 状态 |
|---|---|---|---|
| APSIS 选项 A（推荐先测） | 进战区后方支援组：维修/指挥/通信；无武器 | 有实体/损伤风险，被毁→战役结束；0.02 g 难规避 | 提案 |
| APSIS 选项 B（备选） | 留后方，不作为本场实体 | 无本场维修坞/指挥/中继；任务仍可能失败；不因在场损失而结束 | 提案 |
| DEEPWELL 部署 | 燃料补给 | 被毁→航程/可持续性受损；0.01 g 脆弱 | 提案 |
| DEEPWELL 留后方 | 仅延迟后勤调度 | 不能凭空提供燃料；支援需要时间/护航/风险 | 提案 |
| WATCHTOWER/BEACON 部署 | 中继/降延迟（8 s） | 被毁→链路回退 45 s | 设定明确（能力）；数量提案 |
| WATCHTOWER/BEACON 留后方 | 无本场中继 | 不能免费替代；链路回退 45 s | 提案 |
| BOLLARD 部署/留后方 | 救援/拖带/打捞 vs 无即时回收 | 留后方不提供即时救援 | 提案 |
| ARIA-1 | APSIS 携带 1–2 架；人员转移/救援；不承担通信 | 数量/命名待核对 | 设定类型明确 |

- 不假设离场舰提供免费全图能力；后方支援必须有明确调度延迟、燃料/风险成本（B2/B3/B4 实现）。
- 具体“owned/deployed/reserve”UI 与指令未实现；本表只定义语义。

### 3.2 自由分组规则（提案，不沿用硬 3 舰）

- 玩家从 owned 选择 deployed 子集，再自由编 2–3 个任务组（组数/首轮规模待 B4 与用户核对；**不是 3 舰上限**）。
- 不设强制 role slot/固定模板；侦察/中继/火力/后勤可混合；组间链路/态势共享受中继/距离/延迟影响。
- 首轮教学 demo 建议观察 **8–10 艘同时在场** 的规模，作为 B4 验证起点；不是产品上限，也不减少玩家拥有的舰只。
- 未部署舰在简报/组舰界面可见，但明确“不提供本场能力”；不能作为免费后备瞬间召唤。

## 4. 至少三种自由分组与代价

| 分组 | 组成（示例） | 打法 | 缺失/代价 | 验证问题 |
|---|---|---|---|---|
| **G1 侦察/中继 + 炮 + 导弹（用户所述）** | HARMATTAN + WATCHTOWER + FERRY + VESUVIUS（可选 +LEE_SHORE） | 哨舰远程搜索/ELINT；中继降延迟；FERRY 近距 railgun；VESUVIUS 远程导弹 | 只有 1 炮 1 导弹；哨舰暴露；导弹耗尽后火力下降；需保护 APSIS/中继 | 是否更早形成可靠航迹/窗口？弹药/损伤/时间是否不同？ |
| **G2 双炮突击** | FERRY + ANVIL + HARMATTAN + WATCHTOWER | 两门 railgun 近距持续火力；单哨舰搜索/中继 | 无导弹远程打击；只有 1 哨舰；弹药/暴露压力；需接近 1200 km | 能否在导弹/EW 压力下完成目标？失败模式是否不同？ |
| **G3 双导弹/远程（需扩充候选）** | VESUVIUS + KRAKATOA（候选）+ HARMATTAN + WATCHTOWER | 远程导弹齐射/饱和；哨舰提供目标 | 无炮/近防弱；导弹可拦截/耗尽；依赖第二弹舱舰获批扩充 | 扩充是否允许？导弹耗尽后如何收尾？与 G1/G2 是否真实不同？ |
| **G4 分布式侦察/中继/后勤护航** | HARMATTAN + LEE_SHORE + WATCHTOWER + BEACON + DEEPWELL + BOLLARD（+APSIS 后方） | 高搜索/中继/燃料/救援，低火力；为其他组提供态势/链路/补给 | 自身几乎不能完成打击；组间协同/链路复杂；占多舰/后勤 | 是否为火力组创造真实优势，而非“多带就强”？失去它任务是否明显变难？ |

- G1/G2/G4 不依赖扩充候选；G3 明确依赖 KRAKATOA 等候选，不能当默认满编。
- 若某组支配：先改任务/敌压/资源，再考虑点数；不能靠增加点数让“全带最优”。

## 5. 点数/预算：暂停旧值，不冻结新值

- R9 的 45 点预算、3 舰容量、`round(displacement_t/60)` 定价、SENSOR/STRIKE 预设、固定 HEMATITE 旗舰：**用户未采用，暂停；不得迁移正式 fixture/K0/运行层**。
- 旧公式把 APSIS（9000 t）算成 150 点并试图排除；用户要求恢复 APSIS 旗舰，因此不能用吨位价格排除设定旗舰。
- 本版不冻结新点数。取舍由 owned/deployed 子集 + 实际资源（燃料/弹药/维修/链路/防护）表达。
- 若未来要保留点数，必须先定义它买什么（专用搜索、中继带宽、导弹/弹药、燃料/后勤、维修坞/指挥等），并证明不会排除 APSIS、不会让“全带”永远最优；无依据前不给数字，也不写 fixture。

## 6. 时间预算与纸面轨迹

### 6.1 四个时间概念

| 概念 | 说明 | 状态 |
|---|---|---|
| 战役模拟时长 | 场景 t0 到终态/时限 | 3600 s 只是测试窗口，不是批准硬时限 |
| 单次交火窗口 | 可射击/被射击到脱离/弹药耗尽/目标失能 | 依赖起始距离/相对速度/传感器/敌 AI/B1b 阈值；未测 |
| 阶段目标/敌反应 | 首次接触、协同窗口、敌反应、撤离/结算 | 只有纸面阶段；敌 AI 未实现 |
| 真实游玩时长 | 含暂停/阅读/组舰 | 30–45 分钟只是试验目标；未测 |

- **3600 模拟秒 = 1× 不暂停 60 分钟**；暂停、组舰/阅读/切页额外；加速缩短现实等待但不改变模拟时长。
- 不声称一小时足够或不足；不把 30–45 分钟当已测时长。

### 6.2 纸面时间输入（未知处标未知）

| 输入 | 已知/提案 | 影响 |
|---|---|---|
| railgun | 1200 km、4 s 解算、6 s 冷却、120 发 | 必须进入 1200 km；单/双炮节奏不同 |
| missile | 6000 km、10 s 解算、20 s 冷却、8 发/发射位、可拦截、飞行数百秒 | 可远距先射，但飞行/拦截/耗尽耗时 |
| 起始距离/相对速度 | **未知/待场景定义** | 决定首次接触和进入 railgun 距离的时间 |
| 传感器最大探测/识别距离 | 统一数值未取证；只有型号清单 | 决定发现/识别时间；不能假设全图 |
| 中继/通信延迟 | 8 s（有中继）/45 s（无中继，docs/03） | 命令/报告/协同窗口 |
| 敌反应/ROE/损伤阈值 | **未实现/待定** | 决定交火窗口/终态 |
| 暂停/组舰/阅读 | 玩家行为，未测 | 真实时长可能显著超过模拟 60 分钟 |

- 纸面尺度示例（不是承诺）：起始 4000 km、相对接近 1.5 km/s → 进入 railgun 1200 km 约 1867 s；导弹可在更远处发射但飞行/拦截另计。3600 s 内是否完成三目标取决于未知传感器/敌 AI/损伤阈值，不能先承诺。
- **硬时限建议**：不冻结。选项：(a) 无硬时限（目标/损失/燃料/撤离结束）；(b) 3600 s 测试窗口作宽松时限；(c) 2700–4500 s 软时限区间。禁止为凑 30–45 分钟调物理或硬造 deadline。

### 6.3 纸面轨迹（内容逻辑；R9 truth/report/评价保留）

| 轨迹 | 关键事件（提案时间线） | truth_decided_t | report_received_t / player_view_t | 终态 | 贡献 | 评价 |
|---|---|---|---:|---|---|---|
| PT-01 G1 侦察中继+炮+导弹 | t0 简报/分组；HARMATTAN/WATCHTOWER 建图/中继；FERRY/VESUVIUS 打击；APSIS 后方支援；C 玩家直控 | **t2000** | t2065 / t2065 | victory | A/B/C 玩家直接 | 主导 |
| PT-02 G2 双炮突击 | FERRY+ANVIL 双炮；HARMATTAN/WATCHTOWER 支援；更高弹药/暴露 | **t1500** | t1560 / t1560 | victory（代价更高） | A/B/C 玩家直接 | 主导 |
| PT-03 不操作 | 部署但不发命令/请求；友军独立护航；敌压迫，APSIS 丧失 | **t900** | t1000 / t1000 | defeat | 无 | 未参与 |
| PT-04 不请求友军 | 无友军请求；依赖自有哨舰/中继；损伤/时间压力下主动撤离 | **t2900** | t2960 / t2960 | withdrawal | A/B 玩家直接 | 主导 |
| PT-05 友军拒绝/受限 | SUPPRESS 被拒（ALLY_TASK_CONFLICT）；调整分组/等待，B 超时 | **t3600** | t3665 / t3665 | stalemate | 1 目标玩家 | 有限参与 |
| PT-06 合成全友军 | 合成输入：友军自主完成 A/B/C、保护对象完好；不判断当前 AI 可行性 | **t2000（合成）** | t2065 / t2065 | victory（合成输入） | 无 | 未参与 |

- 时间仅示意；所有结果需 B1b/B2/B3/B4 实测后才可能确认。
- PT-06 是反事实/合成输入，不是 AI 战报；PT-03 是防挂机纸面检查，不是运行证据。

## 7. 受影响系统与规模风险

| 系统/卡 | 受影响项 | 边界/风险 | 验证 |
|---|---|---|---|
| **D1 部署切片（#62）** | 部署选择/实例/资源；更多舰/owned-deployed-reserve/分组 | D1 只验证既有范围，**不自动 PASS** 新方案；需要新测试与 fixture 迁移；D1 旧 94/0 不能外推 | 用户核对后另卡 |
| **B1b 逐舰战斗** | 每舰损伤/火控/弹药/PD；更多实例/武器 | 未实现；railgun/missile/PD 实际射击与损伤账本未接通 | B1b |
| **B1c 舰组/控制（按实际卡范围）** | 任务组选择/分组命令/共享态势/链路 | 组数/规模增加 UI/命令复杂度；未实现 | B1c |
| **B2 独立 AI/协同** | 友军请求/回执/失联、组间共享、AI actor 数 | 更多舰/组=更多 AI 任务/链路；未实现 | B2 |
| **B3a/B3b** | 目标条件、APSIS 损失、truth/report、战报 | 未实现；不能把纸面轨迹当运行态 | B3 |
| **B4 规模/性能** | 实体/传感/链路/AI/帧/存档 | 11 独立舰+1–2 穿梭机 vs 旧 3 舰；帧/决策/UI/存档未测 | B4 |
| 港口经济/造船/持续战争 | — | **不扩**；APSIS 维修坞只在任务内/明确后勤范围 | 后续决定 |

- 实体/规模：owned 11 独立舰+1–2 穿梭机；首轮建议部署 8–10 艘；AI actor 至少友军 3 + 敌方 3（未实现）；实际规模未测。
- D1 的既有数字只覆盖旧范围，不是 R10 规模/PASS 证据。

## 8. 待核对参数表

### 8.1 R9 旧参数（暂停，不再提案）

| ID | 旧参数 | 旧值 | 处理 |
|---|---|---|---|
| P-03 | 点数公式 | `round(displacement_t/60)` | 暂停；不采用/不迁移；旧公式排除了 APSIS |
| P-04 | 预算 | 45 点 | **暂停**；用户未采用 |
| P-05 | 指挥容量 | 3 舰 | **暂停**；用户要求自由分组/满编 |
| P-06 | 舰池数量 | PALLET×4 等旧池 | 暂停；由 R10 满编建议替代 |
| P-07/P-08 | SENSOR/STRIKE 预设 | 30/45 点 | 暂停；由 G1–G4 分组示例替代 |
| P-09 | 固定 HEMATITE 旗舰 | I-A1/HEMATITE 20 点 | 暂停；改为 APSIS 旗舰 |

> R9 其他参数（P-01/P-02/P-10 起……）仍可保留但需按 R10 语境重读；本轮以 R10 表为准。

### 8.2 R10 待核对参数

| ID | 参数 | 提案值 | 依据/说明 | 状态 |
|---|---|---|---|---|
| P-28 | ID13 满编独立舰数量/舰名 | 11 独立舰 + 1–2 穿梭机（5 明确 + 6 建议） | 设定只明确 5 艘独立舰；数量未给出；建议供核对 | 待用户/Astra 核对 |
| P-29 | 明确/建议/候选划分 | §2.1/2.2 | 不把命名池/roster 提案表冒充满编 | 待核对 |
| P-30 | 满编质量/乘员/燃料 | 约 18 300 t / 约 529 人 / 约 16 000 t | roster 提案值；非批准上限 | 待核对/不用于定价 |
| P-31 | owned/deployed/reserve 规则 | 全舰队 owned；任务选 deployed 子集；reserve 无即时能力 | 用户要求先给满编再分组 | 待核对 |
| P-32 | 部署/任务组上限/首轮规模 | 不设硬 3 舰；建议 2–3 组；首轮 8–10 艘在场 | 教学验证规模；不是产品上限 | 待 B4/用户核对 |
| P-33 | 旗舰 APSIS 部署选项/损失 | 选项 A 战区后方支援（风险/损失→defeat）；选 B 留后方无本场支援 | APSIS 0.02g 无武器；不能免费战斗 | 待核对 |
| P-34 | 后方支援延迟/成本 | 无即时全图；按后勤调度延迟/燃料/风险 | 不假设免费能力 | 待 B2/B3 核对 |
| P-35 | 分组示例/最低能力要求 | G1–G4；不强制 role slot | 玩家自由组合；目标需要搜索/中继/火力 | 待试玩 |
| P-36 | 点数是否保留/覆盖资源 | 暂不冻结；若保留须定义搜索/中继/弹药/后勤等定价 | 旧公式不采用；不按吨位排除 APSIS | 待产品核对 |
| P-37 | 战役模拟时长/硬时限 | 3600 s 仅测试窗口；可选无硬限/3600 宽松/2700–4500 软限 | 3600=1×60 min；暂停/阅读额外 | 待试玩/用户核对 |
| P-38 | 单次交火窗口输入 | 起始距离/相对速度/传感器距离/敌 AI/损伤阈值未知 | 不调物理凑时长；缺输入标未知 | 待场景/实测 |
| P-39 | 真实游玩目标 | 30–45 分钟仅试验目标 | 未试玩；不承诺时长/留存 | 待玩家测试 |
| P-40 | D1/B1b/B1c/B2/B3/B4 扩展 | 列影响与规模风险；D1 旧范围不自动 PASS | 代码后续验证 | 用户核对后另卡 |
| P-41 | 友军/敌方/目标/终态/评价 | 保留 R9 方向；具体数量/阈值/额度 | R9 已通过部分保留 | 待产品核对 |

## 9. 旧 fixture/probe/K0 迁移清单（本轮不执行）

| 工件 | 旧值/字段 | R10 迁移后（提案） | 影响/时机 |
|---|---|---|---|
| `game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json` | schema v3 / P0-r7-1；45/3 未迁移 | 候选 v4 / P0-r10-1；**本轮不改** | 用户核对满编/分组/时限后另卡 |
| 同上 `fleet_pool` | 100→45 预算、3 容量、SENSOR/STRIKE、点数公式 | 暂停；改为 owned 满编/deployed 子集/任务组/资源约束；不再用 45/3 | probe 预算/编成断言需重写；旧 247/0 仅对应旧 fixture |
| 同上 `formations[]` | SENSOR/STRIKE 预设 | 改为 G1–G4 示例/自由分组；不是唯一可玩组合 | 后续 probe |
| 同上 `own_flag` | I-A1 HEMATITE | **APSIS APOGEE**（named flagship）；明确 named `apsis` 与旧虚构 I-A1 的迁移关系 | probe/实体映射需更新 |
| 同上 `objectives[PROT-2]` | I-A1 | APSIS 旗舰；损失→defeat | probe |
| 同上 `ally_force` | R9 3 舰有限武装友军 | 保留方向；HEMATITE 表述为赤铁-6改炮舰；无暗加武器 | probe 友军断言 |
| 同上 `opfor/OBJ-B/OBJ-C` | R9 方向 | 保留（I-OP2 INTERDICT 双链；OBJ-C 无身份免疫） | probe 保留/更新 |
| 同上 `terminal/truth/contribution_rules` | R9 truth/report/唯一评价 | 保留；APSIS 损失/旗舰替代 I-A1 | probe |
| 同上 `event_traces` | R9 14 条/PT 轨迹 | 更新为 G1/G2 分组、APSIS 旗舰、owned/deployed/reserve；R9 三时刻与评价保留 | 不把纸面当运行态 |
| 同上 `text_samples/briefing` | 旧文案 | 增加 owned/deployed/reserve/task_groups/flagship/support 字段；措辞 Sol 统稿 | 内容卡 |
| `game_v17/tests/jc_scenario_spec_probe.gd` | 当前 247/0（旧 P0-r7-1） | 随 fixture 迁移更新；本轮不改 | 后续实现/校验卡 |
| `game_v17/docs/contracts/joint_campaign_r2.md`（K0） | 无 owned/deployed/group/flagship 扩展字段 | 后续 K0 增补；本轮不改 | 与 R10 fixture 同批批准 |

## 10. 文档检查与证据

### 10.1 命令

```powershell
python .tmp_r10_doc_check.py
git diff --check
git status --short
git diff --stat 4e75897ed32f8245f35c5ec584f0ec912ec919c6 -- docs game_v17/docs/contracts
```

### 10.2 检查内容

1. Markdown 相对链接可解析；
2. catalog 类 ID/舰名/武器/传感器引用存在；
3. `HEMATITE` 被写为赤铁-6改炮舰/FERRY，不是远地点原型；
4. APSIS=APOGEE 旗舰，catalog 事实/损失→战役结束；
5. WATCHTOWER=安海-1 中继、HARMATTAN=托盘-5改哨舰，不混为同舰；
6. 满编表明确区分“明确/建议/候选”，不把 roster 13 条当正典满编；
7. owned/deployed/reserve 分层与 APSIS 风险；
8. 至少三种分组（G1–G4）含缺失/代价；
9. 时间四概念、3600=60 min、暂停/加速说明、硬时限未冻结；
10. D1/B1b/B1c/B2/B3/B4 影响列出；D1 不自动 PASS 新方案；
11. R9 四项关闭未回退（物理压制/OBJ-B 双链/truth/report/唯一评价）；
12. 仅文档变更，无 fixture/probe/运行层/AI 变更。

### 10.3 结果（2026-10-29 R10 实测）

一次性检查脚本（未提交，仅本轮取证）核对 Markdown 链接、catalog/lore 映射、满编/分组/时间/影响/R9 保留、fixture 未改：

```text
R10 DOC CHECK: checks=105 failures=0
EXIT=0
git diff --check: exit 0（无输出）
```

- 链接：提案/R10 表/R9 历史表全部可解析且目标存在；
- catalog：APSIS→APOGEE、FERRY→HEMATITE、HARMATTAN→PALLET、WATCHTOWER→SAFEHARBOR、DEEPWELL→MOONPORT；HEMATITE 仍 `railgun/point_defense`；PALLET/SAFEHARBOR/MOONPORT 无武器；敌方 RECOURSE/INTERDICT/SUMMONS 存在；
- 设定：docs/03 的 APSIS/刺桐-2M/哈马丹/渡口/望楼/深井；docs/04 的赤铁-6炮舰/托盘-5哨舰/安海-1中继均被引用；
- 满编：5 艘独立舰设定明确，11 艘独立舰为建议，候选/借调另列，未把 roster 13 条冒充满编；
- 分组：G1/G2/G3/G4 及缺失/代价均存在；G3 依赖扩充候选；
- 时间：四概念、3600 s=1×60 min、暂停/加速、硬时限未冻结均写明；
- 影响：D1/B1b/B1c/B2/B3/B4 与规模风险已列，D1 不自动 PASS 新方案；
- R9 保留：物理压制/OBJ-B 双链/truth-report/唯一评价未回退；
- 旧 45/3 只在“暂停/未采用/历史”语境出现；R9 旧表已加历史标注；
- fixture 未改：schema v3 / P0-r7-1 / 预算 100 / 旧旗舰字段仍在（本轮只列迁移）；
- 变更范围：仅 Markdown（主案/R10 表/R9 历史标注/任务卡 R9 记录）；无 fixture/probe/运行层/AI 变更。

工件 SHA256/行数（提交前工作树；最终提交 SHA 见交付 PR/回执）：

| 文件 | 行数 | SHA256 |
|---|---:|---|
| `game_v17/docs/contracts/jc_sector_01_proposal.md` | 267 | `e4f76087058d5a31c69a55a875bd1efe48c67c9346c6bd6620ff329dc0ccfa39` |
| `docs/tasks/joint_campaign/JC-B03P_R9_review_tables.md`（历史标注后） | 240 | `fb7fa5c361405a352b9d77193296d71c4e13722db3dada65020d06a081edac9a` |
| `docs/tasks/joint_campaign/JC-B03P_scenario_proposal.md`（R9 记录，未改） | 74 | `aefcddfdd013e107982e71c98d83c3f7e3039fae88cb26bc51016e4eb2299fd5` |

本 R10 对照表自身的最终 SHA256 见交付 PR/回执（自引用哈希会随回填变化，故不在此表内写自哈希）。

**NOT RUN（本轮明确未执行）**：游戏全量、部署/战役/战斗探针、AI、真实读档、30–45 分钟试玩、性能/实体规模测量。本轮没有任何运行态证据；D1 旧数字只覆盖旧范围，不能当作 R10 规模或方案 PASS。

## 11. 交接状态

- 交付物：本对照表 + [P0-r10-1 提案](../../../game_v17/docs/contracts/jc_sector_01_proposal.md)；未改正式 fixture/probe/运行层/AI。
- 下一步：Sol 技术复核 → 用户/Astra 核对满编数量、owned/deployed/reserve、分组上限、APSIS 风险、点数是否保留、时间/硬时限；然后另卡迁移 fixture/probe/K0。
- 代码下一项仍为原 **#45**（基于包含 D1 的 main），不启动 B2/B1b/B3 或下一张卡；本卡保持 OPEN。
