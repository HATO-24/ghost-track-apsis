# S-04｜第一批舰船、武器与弹药设定整合

日期：2026-10-29 首交，2026-10-30 依 `D:/GHOST TRACK_APSIS/docs/reviews/writing_workflow_20261029/Astra_L03_S04_审查与裁定_20261030.md` 窄修 R1–R5。原执行依据为同目录 `Astra_设定整合与弹种扩充交接.md`，以及用户在 Astra 对话中授权沿用现有 Luna/Sol 对话推进。此包为**设定登记、裁定与正文候选**；未改游戏代码、原始 PureWriter 合集或已审 B001。新增弹种在本轮**未实现/NOT RUN**；这不构成“当前项目完全没有相关基础”的判断。S-03 已交工程 Sol 的 B001 状态不变，S-04 待 Astra 复核关闭。

## 六份产物

| 文件 | 用途 |
|---|---|
| `setting_registry.csv` | 每条当前说法、旧版本、来源、适用层及实现核对点。 |
| `conflict_decisions.md` | 旧新方案并列，按已确认/设计/待产品裁定/待工程核实裁定。 |
| `ships_weapons_ammunition.md` | 联合战役舰船—武器—弹药整合正文候选；两艘同级舰异构装载示意。 |
| `ammunition_cards.md` | 单体动能弹、集束动能弹、航迹仿真诱饵三卡；数值与工程参数待验证。 |
| `change_impact.md` | 文档、内容、接口、UI、存档和验收影响。 |
| `README.md` | 来源/覆盖与下一步。 |

## 证据状态

- 已确认产品口径：**11 = 8 艘旗舰/支援舰 + 3 个作战位置**，远地点号属前 8 艘，在战区后方承担真实风险且不占作战位；炮/导 3:0、2:1、1:2、0:3 均合法。点数暂不冻结、无全局硬倒计时。Astra 2026-10-30 审查已核 GitHub main 的 `docs/tasks/joint_campaign/JC-B03P_用户确认与后续执行_20261029.md`（所读 blob `8cacef9ec07280afe39faed3ed79d22132f25483`）及工程对话用户决定。首版 S-04 曾误将旗舰计数列待选，现已更正，旧 3舰/100点/3600秒仍保留为历史方案。
- Astra 本轮产品裁定：合法舰级模板建立同级舰独立场景实例、稳定唯一 ID 与逐舰库存/燃料/损伤；新舰名未定可用场景呼号。首个新增主武器装载切片每舰单一、舰间可不同，保留既有 PD/独立对抗设备；同一主发射系统有限混装后延，出击冻结后不免费改型/补弹。此为 Astra 受委托后的设计裁定，不冒写为用户逐条原话。
- 本轮弹种设计：单体动能弹基线；集束以覆盖换单个命中作用；航迹仿真诱饵分实体/观测/判断且有限寿命、可识破。单体/集束轨道炮弹沿 railgun 不可拦截契约；射手使用有权获得的观测估计，低质量/陈旧估计本身不新增禁射门禁。未批准性能数字或实现状态。
- 静态旧项目证据：本机 `origin/main=4e75897ed32f8245f35c5ec584f0ec912ec919c6` 的 `docs/04_舰船设定.md`、`docs/05_技术手册.md`、`docs/12_军语规范.md`、`game_v17/docs/fleet_system.md`、`game_v17/docs/combat_ballistics.md`、`framework/content/fleet_roster.json`、`ships_friendly.json`、`weapons_l1.json`。这些是本轮能核对的固定旧树，不是最新工程执行基线或运行 PASS，也不能证明最新主线缺失某功能。
- Luna L-03 定向来源包：**已交并核对**，位于 `C:/Users/ASUS/.codex/visualizations/2026/10/29/01a18564-50a6-7372-a993-91278cbde0f0/writing-workflow-20261029/06_setting_integration/`；四份文件为 `sources.csv`、`conflicts.csv`、`evidence.md`、`README.md`。a-080 只局部阅读；a-079 为历史反馈；其他作品词汇重合不进 APSIS 事实。本包据此补了舰级/实例、发射架/弹药 ID、质量/点数和旧正典边界。2026-10-30 定向复核其 R1 增量：`MAIN-USER-CONFIRM-01`、C-04 和 evidence 结论已正确关闭计数；来源分层表的残留待定措辞与 C-01 新来源引用已由 Astra 收尾更正，原始来源记录保留。未重编全库。

## 适用与未覆盖

本包先处理舰船、武器、弹药和其战术角色；世界观人物命运、政治关系、完整舰池、具体平衡与制造细节未裁定。舰级与具名舰实例分开；历史设定与当前玩法、代码实现分开。旧文本保留可追溯，个人合集最后修改日期不是创作时间，废纸篓和来源疑点不自动进正典。

Astra 复核结果（2026-10-30）：R1–R5 文档审校关闭，接受为后续任务卡的设计输入；具体弹种规格、平台兼容及数值仍待对应窄卡，不是可直接实施的完整冻结规格。工程 Sol 已在 `D:/GHOST TRACK_APSIS/docs/tasks/joint_campaign/E-AMMO-00_依赖登记.md` 接收裁定，保持 **#45 在先、#63 随后、B1b 逐舰账本及相关接口再核**，不把本包设计当成 DeepSeek 已交功能。本轮未派 DeepSeek；运行、真实文件恢复、11舰规模、平衡与 HUD 视觉 **NOT RUN**。原合集哈希复核仍为 `C6C1EB494817C403F550E18055DEB2219D55F199F9B3B9B61DAAC8800CECA219`。

## R1–R5 窄修索引

| 项 | 本包关闭位置 |
|---|---|
| R1 旗舰计数 | `setting_registry.csv` SET-01/02/13；`conflict_decisions.md` C1/C2 及更正段；整合正文第1节；影响表编制行。 |
| R2 授权观测 | `ammunition_cards.md` AM-01/02 信息需求；整合正文玩家文字；影响表火控行。 |
| R3 railgun 拦截 | `ammunition_cards.md` AM-01/02 反制；`conflict_decisions.md` C4；`change_impact.md` 集束验收行。 |
| R4 风险与门禁 | `ammunition_cards.md` AM-01/02 用途、失败与 AI；整合正文第2节；影响表玩家文字及工程问题。 |
| R5 产品裁定与状态 | `conflict_decisions.md` C2/C6 及收口段；整合正文第1/3节；`change_impact.md` 分批与排程；本 README 证据状态。 |
