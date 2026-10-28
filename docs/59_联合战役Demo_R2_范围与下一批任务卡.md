# 联合战役 Demo R2：范围、复核与下一批任务卡

日期：2026-10-25（Asia/Shanghai）；需求：Astra；规划：Sol；实现目标：DeepSeek v4.1 Flash。

延续[40号审计与原路线图](40_系统完成度复核与开发任务队列.md)的权威/测试契约；以下以56 R2更新产品范围，并用当前提交和本轮复核替换40号文档的历史状态判断。

## 2026-10-29 JC-A04第二轮：R3关闭，继续原R1/R2/R4

[本轮独立关闭表](reviews/pr72_a04_r2_20261029/review.md)，head`bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72`。根通信专项8/8、新106/0；同head CI后续确认三个job成功、full91=84/7历史FAIL、new_fail0/drift0/complete=true。RNG实际恢复、无send日志共享的真实文件下一draw、配置seed与v1模式已关闭；真实callback/失败订单不执行/合法共享只一次等保留。只继续[A04/#61](tasks/joint_campaign/JC-A04_ew_comms.md)发送上下文、普通ignore_ew旁路、缺pending.ew/非整数版本和正式成功融合断言。R3不返工，不扩AI/UI/RF/禁射。

PR72暂缓合并、A4未冻结；B01A最终接入仍等A4，既有A1/A2/A3/G0/K0不变。最终修复HEAD专项+原C，七历史baseline不刷新。下方首轮为历史，以最新关闭表为准。

## 2026-10-29 JC-A04首轮：RETURNED，继续原#61

[PR72独立复核与关闭表](reviews/pr72_a04_20261029/review.md)，head`1de99a85c4f69dca706509648450487197523ab5`。根通信专项8/8、新79/0；同head合成merge CI full91=84PASS/7历史FAIL、new_fail0、drift0、complete=true。但已登记sender上下文未校验、普通ignore_ew旁路、实际PRNG恢复以及v2删除冻结字段/版本等反例仍在，正式成功共享夹具也需补合法融合断言。继续[A04/#61](tasks/joint_campaign/JC-A04_ew_comms.md)，保留三入口/唯一推进/真实回调、失败订单不执行、合法共享只融合一次及其他兼容正例，不重做已关闭链路。

PR72暂缓合并，A4未冻结；B01A最终集成仍等A4。A1/A2/A3/G0/K0完成不变，低质量仍能射击不作自动禁射缺陷。UI设计文档GPT/Sol，代码DeepSeek。最终修复HEAD专项+原C，七历史baseline不刷新。

## 2026-10-28 JC-A03第四轮：PASS，A3合入，A04解锁

[独立放行与原始证据](reviews/pr70_a03_r4_20261028/review.md)：A3冻结 `5d372ea2df7c49badeea3846c16b839b1f6faef1`，PR70合入main `c3fca1c52a4158f374661f1906b32103dab5360c`，整个tree等于被审候选。原R1发射前实际HUD/实体键质量与误差消费、R3旧档覆盖活跃Session两项均关闭；此前真实射后运动、R2守卫/幂等、partial/null/full与R4/W7关闭结论保留。低质量仍能发射不作为缺陷，不恢复硬禁射推断。

根独立11专项11/11、新EW126/0、A02 122/0；完整原C Phase0 6/6、PhaseA3/3、full **90=83PASS/7历史FAIL、new_fail0、drift0、complete=true、退出0**。七历史baseline不刷新。#60完成，下一张核心卡为[A04/#61](tasks/joint_campaign/JC-A04_ew_comms.md)，从包含上述A3合入提交的最新main开始；现有服务分支须合入A3后再接Session。B01A最终集成仍等A4，核心顺序不变。UI设计/文档GPT/Sol，代码DeepSeek。下方前三轮为历史，不重派已关闭工作。

## 2026-10-28 JC-A03第三轮：只剩发射前预测与旧档覆盖

[第三轮关闭表和独立证据](reviews/pr70_a03_r3_20261028/review.md)，head `022a7e0e6b0ab2ce65f228f98b4a1146d18792f8`。根11/11 PASS、新EW102/0、A02 122/0；CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true。射后真实预测/launch及非共线实际运动、R2全部拒绝/重投守卫、partial/null/full恢复和R4/W7均保留关闭，不新增禁射规则。

只继续原#60两处：普通HUD/实体键的发射前mq预测未一致应用质量，以及同一旧文件覆盖活跃Session残留前会话EW队列/样本。PR70暂缓合并、A3不冻结；A1/A2/G0/K0不变，A04/B01A核心接入仍按原依赖等待。下方前轮为历史，不重复派发已关闭工作。

## 2026-10-28 JC-A03第二轮：大部分关闭，继续#60三处边界

[本轮关闭表与真实证据](reviews/pr70_a03_r2_20261028/review.md)，head `ea29da7138ad353c4198f76547f57c4e0b07142d`。根11/11 PASS、新EW83/0、A02 ID恢复122/0，CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true。接口精度、原重投/候选幂等、null拒绝/full及legacy兼容、R4注册/W7均保留关闭。

仅收尾真实Ballistics未接质量/误差、owner已拒绝仍写全局Track/map、部分EW新段缺dict触发非规范化转换异常。低质量仍可发射不作为缺陷；不恢复硬禁射规则。PR70暂缓合并、A3不冻结，继续原#60，A04/B01A核心接入按原依赖等待；A1/A2/G0/K0完成不变。下方首轮为历史，以本轮关闭/剩余表为准。

## 2026-10-28 JC-A03首轮：RETURNED，继续原#60四组收尾

[PR70独立复核与原始证据](reviews/pr70_a03_20261028/review.md)，head `6bd919aa19898bbf31f5dd7c3287befc47392877`。根专项11执行行通过、新EW47/0，但旧A02注册ID被删，122/0为匿名行；CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、complete=true，不能替代实际消费者验收。

保留真实采样/正常owner/延迟/current与历史分离、有效文件完整状态10tick语义一致与缺段兼容。只补：已声明中等精度消费与既有解算语义；旧观测重投后measurement回滚；新EW队列null静默丢失；恢复旧A02注册ID并补等强真实回归。R1原“低质量仍发射即P1缺陷”的外推已撤回，收窄为P2：低质量不自动等于禁射，既有解算可按明确的历史数据/误差/有效性规则继续使用，本卡不新增自动禁射或强制射击产品规则。PR70暂缓合并、A3不冻结，#60继续，A04/B01A核心接入依原依赖等待；A1/A2/G0/K0完成不变。UI设计/文档GPT/Sol，主要代码DeepSeek。

## 2026-10-28 JC-A02第三轮：PASS，A2已合入，A03解锁

[独立放行与本轮实际证据](reviews/pr68_a02_r3_20261028/review.md)：A2冻结 `755ab5ed629165656a566427523b01045775fc0f`，PR68合入main `82bf6a531042961f0d5fe5d948c7004a15cd20cf`；整个tree等于被审候选。实际HUD空字段T0001→实体身份和普通HUD过期有效性两处均关闭，原R1/R2/R4其余/R5关闭保留。根独立7专项7/7、identity122/0；原C Phase0 6/6、PhaseA3/3、full **89=82PASS/7历史FAIL、new_fail0、drift0、complete=true、退出0**。七历史baseline未刷新。

#59完成，下一张核心卡为[A03 / #60](tasks/joint_campaign/JC-A03_ew_observation.md)，从包含82bf6a5的main开始。A03只接EW对真实观测/延迟/owner航迹当前测量质量及火控的作用；A04通信、B01A部署按原依赖准备，核心集成顺序不变。UI设计/文档继续GPT/Sol，代码DeepSeek，HUD/Binder文件串行。下方前两轮为历史，已关闭项不再派发。

## 2026-10-28 JC-A02第二轮：大部分关闭，仅真实消费者两处

[本轮复核与证据](reviews/pr68_a02_r2_20261028/review.md)，head `4a658699868b8d046ec5472f9c4b9ea204af6be9`。根七专项7/7、新110/0，CI合成merge full89=82/7、new_fail0、complete=true。R1/R2/R5与R4时钟、迟到、火控/自然文件继续均关闭，不再返工。只收尾原R3真实HUD T0001→entity映射，以及原R4实际HUD消费过期有效性；测试手工预填映射/只验helper字段不能替代实际路径。继续原#59，PR68不合并、A2不冻结、#60等待；A1完成不变。下方首轮为历史。

## 2026-10-27 JC-A02首轮：真实入口RETURNED，继续#59

[PR68独立复核与证据](reviews/pr68_a02_20261027/review.md)，head `7293058d1c0d3cdedceff1fae6233523e7f8b313`。根七专项7/7、新probe66/0；CI合成merge full89=82/7、new_fail0、complete=true。但盟军回复串player、旧Binder人工绕审计、T0001火控键、TTL/迟到及IFF状态仍未闭环。只在原#59按五组返修，保留owner存储/合法来源/文件10tick绿项；PR68不合并、A2不冻结、#60不提前解锁。A1与PR66/67完成不变，UI文档仍由GPT维护，DS做代码。

## 2026-10-27 JC-A01第五轮：PASS，A1合入，解锁A02

[独立放行与本轮证据](reviews/pr66_a01_r5_20261027/review.md)：A1冻结 `845584733df619feb3e372e8c06a7caa9f3fdaba`，PR66已合main `f62e5e6f48b3faf1098cbb44b2801c5c8fde394e`，整个tree等于被审候选。T1已知contact缺行红灯、T2同目标真实移动/合法更新红灯均关闭；原实现关闭结论保持。根五专项5/5；完整原C **88=81PASS/7历史FAIL、new_fail0、drift0、complete=true、退出0**。

#58完成，下一张核心卡为[JC-A02 / #59](tasks/joint_campaign/JC-A02_identity.md)，从包含A1合并提交的main开始。#60等待A2，#61/#62仅按原依赖准备独立服务，核心仍A02→A03→A04→B01A。新UI文档由GPT/Sol维护；A1等待解除，UI-01仍按61号文案核对和HUD/Binder文件排程执行，不与A02同时改同文件。下方前四轮为历史，不再派发其已关闭残项。

## 2026-10-27 JC-A01第四轮：实现缺口关闭，仅验收测试收尾

[独立复核与控制实验](reviews/pr66_a01_r4_20261027/review.md)，HEAD `eb4b98530b589dd5c452a78d46549660985557d3`、代码c704f859（差异仅报告）。owner老化、内存/公开文件10tick在途共享继续、光学标签三项均CLOSED，selected及前轮修复保留。根五专项5/5通过；完整C **88=81PASS/7历史FAIL、new_fail0、drift0、complete=true、退出0**。不再派发三项实现返工。

只继续原#58两组等强度测试：指定合法观测contact不能缺行仍绿；隐藏移动须与被比较的已观测实体相同、证明真值实变，再验证合法新观测更新。控制副本分别过滤已知harmattan仍280/0、关闭移动仍100/0；并非正式probe或生产代码被改。A1暂不冻结、PR66不合并，#59–#62不提前解锁；UI文档继续GPT/Sol维护，DS只接明确代码实现卡，UI运行时按61等待A1。下方前轮为历史。

## 2026-10-27 JC-A01第三轮与UI指引拆卡

[PR66第三轮复核](reviews/pr66_a01_r3_20261027/review.md)，head `8b4cf990021bafe0f5b2945039c850b5c985cf5a`。selected/详情隔离、正常共享到达和重投幂等、null拒绝、probe有效性与退出码包装已关闭。**继续原#58**窄修owner老化、在途恢复提前融合、实际光学内部ID泄漏，并按逐项等强度映射修两旧probe。本地5项3PASS/2FAIL、A01 63/0；CI关联同head的合成merge full88=79/9（7旧+2新）、drift0、complete=false、退出1。A1不冻结、PR66不合并，#59–#62依赖不提前解锁。下方前轮为历史，不重开已修项。

新[60 Astra UI规范](60_Astra_UI与文案设计规范_交Sol.md)原样收录，不覆盖56 R2或当前底层卡。[61 UI实施队列](61_UI文案台账与实施队列.md)已交40条文案台账、术语表、五状态规格、UI-01至04细卡：有限文案→真实字体/组件→层级与反馈→并入B1/B2视图。设计审校可并行，运行时等待A1及相应设计/接口条件；现有#8作为范围索引，不重复开全屏重写任务。没有新UI实机验收；A01光学泄漏在#58修，不推给UI-01。

## 2026-10-27 JC-A01第二轮复核

[PR66第二轮关闭项与剩余](reviews/pr66_a01_r2_20261027/review.md)：被审 `61f27fc8e841666705b5fd2e843824a03bf6c0b8`。真实发射授权/运行态与context字段、空绘图/contacts、真正旧来源迁移已有关闭证据。**继续原#58**，只剩selected/owner融合、真实共享回调及成功后的幂等/在途继续、present-null和有效probe/门禁适配。主probe45/12、Phase0 4/6、PhaseA 1/3；full日志87=71/16（7旧+9新），绿色job有退出码包装缺陷。A1不冻结、#59–#62不提前解锁；不重开已修项、不新增AI/EW/B1b范围。下方首轮和R8为历史。

## 2026-10-26 JC-A01首轮交付复核

[PR #66独立复核](reviews/pr66_a01_20261026/review.md)：被审 `1d1e8399da438b77b74acee40d753711c8d2a8f9`。8专项通过；真实有限资源射击仍接受敌actor/错controller/fleet，HUD仍能回退物理真值、盟军观测进入玩家全局融合；基础共享与新旧档迁移未闭环。**继续原#58返修，A1尚未冻结，PR66暂缓合并，#59–#62不提前解锁。** G0/K0与此前12个PR合并结论保留；已通过的shooter拒绝、正常本舰射击和有效文件往返保留。范围限原卡授权/情报/共享/恢复及真实消费者验证，不新增完整AI/EW/逐舰账本。下方R8为此前完成状态。

## 2026-10-26 R8独立复核更新

**R8技术复核通过：G0与K0冻结为同一候选 `9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。** #56/#57原残项全部关闭。#58 JC-A01解除G0/K0等待，作为下一张核心实现卡；#59–#62仍按原依赖等待。#63只剩旗舰口径及反事实战报两项非阻塞文本校正，产品数字/内容尚未获批。顺序合并记录和独立全量结果见[本轮报告](reviews/pr65_r8_20261026/review.md)，下方R7/R6/R5均为历史。

## 2026-10-26 R7独立复核更新

[本轮关闭项与窄收尾清单](reviews/pr65_r7_20261026/review.md)：被审 `2ae7bf7cba8af32ff4456cefe28efa3650b868dd`。allocator值、非满历史真实投递、原STARE缺字段、K0核心参战/共享/部署负例均关闭；底层C55迁移现partial可用。剩余null拒绝、公共partial报告、满载输出比较和原日志归档；K0归一字段/版本/共享合同；P0归一命名映射、自由组合边界与具体文案。**继续原#56/#57/#63，G0/K0尚未放行；不新增功能范围。** 下方R6/R5为历史。

## 2026-10-26 R6独立复核更新

[PR #65 R6已关闭项与剩余返修](reviews/pr65_r6_20261026/review.md)：被审`5d7208b82ebae81da874e059c2d88286317c6483`。11专项通过；旧150tick移动跟踪、原八条导入反例、K0主要旧反例与P0三条变异已关闭，保留修复。TWS完整状态/旧档策略、比较器allocator和投递输出、K0参战资格/共享来源及P0旗舰预算/友军能力/主案归一仍需收尾。**G0/K0尚未放行，P0先归一后产品核对，继续原#56/#57/#63**。下方R5和2026-10-25记录为历史，不代表本候选状态。

## 2026-10-26 返修复核更新

[PR #65 第五轮独立复核与原卡返修清单](reviews/pr65_r5_20261026/review.md)：被审候选`dc3821eda91d25f14e44dd9f57e6f5a985e04a9c`。原200/400tick反例转绿，10专项通过；持续跟踪、原子导入、比较器仍有缺口，K0权限/引用及P0目录/目标轨迹语义也未通过。**G0/K0尚未获独立放行，P0保留草案**；继续原#56/#57/#63，#58–#62核心集成未解锁。下方2026-10-25表格保留历史起点，不作为本次候选已冻结的证明。

## 1. 一页范围表

本轮以 [56 R2 原文](56_Astra_开发需求_交6Sol.md) 为需求依据。该文件来自用户更新后的主工作区，SHA256=`5ED8C0C7080860381731253324679F6E119CAE4AC6D87645BAD0727FAF7CABA1`；源文件未由 Sol 改写。R2 与本次用户明确答复优先于旧版57/58的产品口径；旧工程证据保留其原提交背景。

| 分类 | 项目 | 本轮明确口径 |
| --- | --- | --- |
| 用户已确认 | 产品 | 主线剧情之外、全面战争背景下的一场联合战役；单人＋AI友军 |
| 用户已确认 | 玩家循环 | 简报→自由组舰→部署→协调→交战/撤离→结束→战报；组舰和协同实际改变结果 |
| 用户已确认 | 胜利范围 | **阶段性战区行动**；解除第33舰队某战区部队的有组织作战能力，不宣告整个第33舰队已去军事化 |
| 用户已确认 | 指挥权 | **自有舰队直控＋友军协同请求**；独立AI友军按任务、资源和链路接受或拒绝 |
| 用户已确认 | 基础约束 | 有限弹药/燃料、正常授权、不完整且有延迟的情报；战役内存档与继续运行；至少两套有效编制 |
| 用户已确认 | 剧情边界 | 暂停主线扩写；战役简报、目标、协同通信和结算属于必需内容；story=false不关闭战役裁决 |
| Sol首版建议 | 技术场景 | `jc_sector_01` 独立架空模拟场景；复用舰型和基础资产；主线存档与模拟器存档分域 |
| Sol首版建议 | 组舰 | 从批准的舰级/可用舰池选择，采用指挥容量＋资源预算；角色作为能力标签，不强制填满旧8槽；命名舰唯一，重复通用舰体需生成独立实例ID |
| Sol首版建议 | 规模起点 | 标定档位：玩家2–4舰、友军1支/2–3舰、敌方3–5舰，加至多2个目标/保护节点；这是性能提案，不是用户已批准兵力或正典 |
| Sol首版建议 | 协同原语 | 支援指定目标、掩护本舰组、协助撤离三类请求；先不做任意战术计划编辑器 |
| 待用户决定 | 内容 | 战区/参战单位名称、架空年月、选择池与预算具体点数、最终目标对象和失能阈值；由JC-B03P提交具体方案后核对 |
| 待测后冻结 | 性能 | 总舰数、弹体上限、时间跨度、AI频率与发布预算；不得用建议档位冒称已跑过的联合战役 |
| 后续范围 | 扩展 | 跨战役持续损失/补给、持续战略地图、经济生产、联网多人、完整港口/船坞/政治外交、完整投降/占领系统、资产细化 |

两项新增产品确认来自本次聊天中的明确选择：阶段性战区行动、自有舰队直控＋友军请求。本批不再就这两点请求确认。具体兵力、目标判据和剧情时间尚未获批，执行卡不得将提案写成既定设定。

## 2. 上一批交付复核与剩余缺口

| 基线 | 精确值 | 使用方式 |
| --- | --- | --- |
| GitHub main | `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea` | 本轮已刷新，仍未包含联合战役与上一批堆叠实现 |
| S7旧候选 | `af5b92471a0f12f1ab95c7defda88360e171e277` | 原审查7个反例的来源，保留为历史 |
| C55返修候选 | **`30b8d33dae9787aadf89bb206757cafb2cad7bd3`** | [PR #55](https://github.com/HATO-24/ghost-track-apsis/pull/55)，本批读代码/设计/隔离服务工作的起点，不等同已合并main |
| #55当前base | `codex/phase-a-review-next-batch-20261025` @ `c558f30846fcd9ab7e5943684e31311debb55ac0` | 描述中承认尚未将返修分散回原PR，也未整合#54审查分支；须用实际祖先和树核对 |
| 当前CI | [run 40174245081](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40174245081) | 精确head=C55，Phase0/PhaseA/full三个job成功；full仍有7项历史FAIL |

本轮在C55/Godot4.7.2隔离工作区独立执行8个相关probe：**8/8 PASS、0 TIMEOUT/NOT RUN**；用原审查诊断脚本复跑，**violations=0、退出0**，原seq64/68已变为34/34。证据见 [复核报告](reviews/r2_20261025/recheck.md) 和 [专项摘要](reviews/r2_20261025/targeted-summary.json)。完整84项本轮未独立重跑；84=77 PASS/7历史FAIL来自上述CI。R05长时测量本轮未重跑，不复制其报告为本轮运行结果。

8/8指断言/退出码结果，不等于stderr为空：两个probe仍有诊断字符串格式错误，若干HUD probe有退出时对象/资源残留；其余可见拒绝/坏JSON日志与负例对应。原始stderr全部归档，JC-A00补格式/失效说明并核对资源残留，不因这些日志抹掉已通过断言或声称零错误。

当前PR依赖快照（均为open，顺序不是已合并记录）：

| PR | head | 声明base |
| --- | --- | --- |
| #32 | `882e058e2a0550684ade73f6978122fef46d42d7` | main |
| #33 | `26f1d5398a4ed6654b057f23a27819e4bf700b31` | #32分支 |
| #34 | `7b5691482929d493467aec12eddbe20f3782f35e` | #33分支 |
| #35 | `f842b3db6158d08bb6da5221252745882a2cc858` | #34分支 |
| #36 | `b04726641057aa80ccc83829e8da00b973f2f733` | #35分支 |
| #37 | `0a66ea2ca45e36739e3c92da80f742526b8b24cb` | #36分支 |
| #38 | `10a48653f9ff5b07517d6eb39c06dbdffb09104e` | #37分支 |
| #39 | `af5b92471a0f12f1ab95c7defda88360e171e277` | #38分支 |
| #54 | `c558f30846fcd9ab7e5943684e31311debb55ac0` | #39分支 |
| #55 | `30b8d33dae9787aadf89bb206757cafb2cad7bd3` | #54分支；实际返修从S7派生，须协调树内容 |

```mermaid
flowchart LR
  M[main] --> P32[#32] --> P33[#33] --> P34[#34] --> P35[#35] --> P36[#36] --> P37[#37] --> P38[#38] --> P39[#39 S7]
  P39 --> P54[#54 审查文档]
  P39 --> P55[#55 返修 C55]
  P54 -.声明base.-> P55
  P54 --> G0[G0 待协调冻结]
  P55 --> G0
```

#31仍携带旧版R1派工材料，不将其直接覆盖本轮R2；旧文档可作历史证据，不作为最新产品定义。

**不再派工重做** R01玩家selected过滤、R02显式/自动ID碰撞与缺seen_ids、R03分数版本/丢backend及观测序号差、R04未知outcome降为旧档等已复现修复。R05已修字节口径、逐样本调用与provenance，但代码仍主要检查ID集合大小/seq下界、少量sensor字段；故障钩子直接调用FAIL，不能充分证明第二/第三样本的真实状态差异会被比较器发现。JC-A00只补这些验收缺口和整链基线。

其余待做事项已有代码依据，不能因模块同名视作完成：

- `fleet_formation.gd` 管理名册/编制，`fleet_assign/move`发事件，尚未把选择转为完整参战实体部署。
- `request_fire(opts.shooter_id)`已有入口，但显式无效ID会退回旗舰；弹药/解算仍取单一`combat_service`，操作日志未完整保留发射上下文。多舰战斗尚未完成。
- `plot_positions`/snapshot有系统真值用途，不能直接交给不同情报拥有者；当前缺少可验收的指挥权/分方情报域。
- IdentityService有冲突/衰减逻辑，TrackTable也直接写身份；assessment目前不回写统一操作性结果，`manual_confirm`及多来源仍需收敛。
- EW三个effect接口目前仅有Session包装，未发现实际Sensor/Comms消费者；CombatService解算质量主要由武器精度和距离计算，尚无相应信息质量消费。
- 旧Mission阶段机绑定scenario/world/story参考，不能直接当story=false下的联合战役目标运行层。

## 3. 本批队列与依赖

G0、K0等是未来任务交付物的名字，当前不是有效SHA。每张卡解锁时必须将前置交付物写成40位SHA并记录执行基线；远端head有变化先审diff，不使用“最新分支”作为证据。

| 卡 | 状态 | 前置/输出 | 目标 |
| --- | --- | --- | --- |
| [JC-A00](tasks/joint_campaign/JC-A00_integration_closeout.md) · [#56](https://github.com/HATO-24/ghost-track-apsis/issues/56) | DONE（R8） | G0=`9d0f3b4…`，完整SHA见上文 | 返修整链冻结及验收补齐，复用#55 |
| [JC-B00](tasks/joint_campaign/JC-B00_contracts.md) · [#57](https://github.com/HATO-24/ghost-track-apsis/issues/57) | DONE（R8） | K0=`9d0f3b4…`，完整SHA见上文 | 多舰队数据、指挥与情报契约，B0规格与schema fixtures |
| [JC-A01](tasks/joint_campaign/JC-A01_authority_intel.md) · [#58](https://github.com/HATO-24/ghost-track-apsis/issues/58) | DONE（第五轮） | A1=84558473，main=f62e5e6f，完整SHA见上文 | 指挥权限及分方情报读写隔离 |
| [JC-A02](tasks/joint_campaign/JC-A02_identity.md) · [#59](https://github.com/HATO-24/ghost-track-apsis/issues/59) | DONE（第三轮） | A2=755ab5ed，main=82bf6a53，完整SHA见上文 | 身份证据单一出口、IFF/ELINT/光学/人工一致性 |
| [JC-A03](tasks/joint_campaign/JC-A03_ew_observation.md) · [#60](https://github.com/HATO-24/ghost-track-apsis/issues/60) | DONE（第四轮） | A3=5d372ea2，main=c3fca1c5，完整SHA见上文 | EW进入真实观测与火控消费者 |
| [JC-A04](tasks/joint_campaign/JC-A04_ew_comms.md) · [#61](https://github.com/HATO-24/ghost-track-apsis/issues/61) | RETURNED（第二轮，R3关闭） | A1/A3已满足，A4未冻结 | EW进入实际通信，保留恢复与权限语义 |
| [JC-B01A](tasks/joint_campaign/JC-B01A_deployment.md) · [#62](https://github.com/HATO-24/ghost-track-apsis/issues/62) | 独立服务前置已满足；最终集成WAIT A4 | →D1 | 两套合法编制转为独立、可恢复的部署实例；多舰发射仍属后续B1b |
| [JC-B03P](tasks/joint_campaign/JC-B03P_scenario_proposal.md) · [#63](https://github.com/HATO-24/ghost-track-apsis/issues/63) | P0草案；产品核对前文字校正 | K0已冻结→待核对P0 | 具体战区、目标判据、简报/战报方案，交用户核对 |

```mermaid
flowchart TD
  C[C55 已交付返修] --> G[JC-A00 整链 G0]
  C --> K[JC-B00 契约 K0]
  K --> P[JC-B03P 具体战役提案]
  G --> A1[JC-A01 权限与情报]
  K --> A1
  A1 --> A2[JC-A02 身份证据]
  A2 --> A3[JC-A03 EW观测火控]
  A1 --> ES[JC-A04 通信服务开发]
  A3 --> A4[JC-A04 Session集成]
  ES --> A4
  A1 --> DS[JC-B01A 部署服务开发]
  A4 --> D[JC-B01A Session集成 D1]
  DS --> D
  D --> B1b[B1b 逐舰战斗与账本]
  B1b --> B2[B2 AI与协同]
  P --> B3[B3 目标与结算]
  B2 --> B3
  B3 --> B4[B4 同版本联合战役验收]
```

可并行的是B00规格、B03P内容提案、独立的Comms/部署服务；不是同时修改大段GameSession。核心接入顺序固定：**A00→A01→A02→A03→A04→B01A**。事件/消息共享字段先冻结，再在独立提交中接入；禁止两张卡各自重写save/load。

## 4. 共同行为、单位与回归契约

PhysicsWorld写运动学；EntityCatalog写静态来源；编制/部署服务写参战实例与归属；TrackTable/指定证据入口写操作性航迹；EventBus分配ID；各服务写自己的资源/运行态。阵营关系、指挥授权、情报拥有者、交战许可分开，friend不等于直控或获得全部观测。

运动学用bary_rot、km、km/s、模拟秒；与scene UTC历元分开。physics后采样；同一采样时刻差≤1e-6s；同源投影位置≤1e-9km、速度≤1e-12km/s；确定性几何≤1e-6km/deg。新延迟链必须分`observed_t`与`received_t`：几何保留采样时刻，融合/路由时间单调，不能用投递时真值替换旧观测。延迟/ETA/到期为秒；质量/置信度在[0,1]，确定性数值比较≤1e-9。阈值用于复制/路由检验，不冒充传感器物理精度。

旧舰队名册mass/fuel为t，PhysicsWorld为kg，转换明确为×1000且只做一次；Δv统一km/s。稳定entity_id关联单舰，fleet_id不是entity_id替代品；实例字典/资源容器不得共享可变引用。JSON数字按语义/安全范围校验，恢复后契约整数是真int，不全局转int。

每卡从规定基线保存红证据（或证明行为已实现），再提交最小实现；正负例、旧seed/旧档、同tick/连续运行与可见性按卡执行。下面称**C回归**，均在执行仓库根目录运行，Godot4.7.2；`<卡号>`仅为结果目录占位：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/jc-r2/<卡号>/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/jc-r2/<卡号>/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/jc-r2/<卡号>/full
```

专项`-Only`不带全量baseline；先`-List`确认选择，0 case/NOT RUN/超时不能算通过。结果自动包含run-id目录内summary.json/report.md/import.log/logs。每卡报告完整SHA、实际命令、退出码、断言计数、环境及CI/artifact；保存原红灯和日志。源码/断言/基线最终证据指向同一最终提交。

旧失败转绿、FAIL数漂移和新失败逐项报告。只有证明原条目被修复才独立删除/调整对应baseline，不能自动刷新；新增缺陷不能登记为历史。所有旧条目清零后去掉-Baseline而非传空failures[]。保持默认full、orbital_sim有限资源/正常授权、Phase0仍6个case；不跳过失败、不吞异常、不放宽精度、不continue-on-error。

## 5. 与已有卡的衔接

| 既有卡 | 处理 |
| --- | --- |
| #40–#44 R01–R05 | 实现已在#55；由JC-A00关闭整链/证据残项，不重做已有修复，不依据报告直接自动关闭 |
| #45 H01毁伤/舰级 | 保留并提高为B1逐舰战斗前依赖；包含3个共同档案契约case，不另开重复任务 |
| #46 H02 legacy TWS/显示 | 保留；A01/A02核对其与产品链关系，必要的本舰ID/来源修复并入明确服务边界，历史证据不抹掉 |
| #47 H03设施事故、#48 H04旧主线文本 | 保留后排维护；不因主线暂停而删除，但不挡无关联的联合战役实现 |
| #49 S01恢复优化 | 保留固定A-07负载的1500000B/250ms/5000ms目标，不重开；新战役负载另测，不偷换fixture |
| #50平台、#51渲染、#52长时成本 | 保留；#51与B4实际游玩接轨，#52复用已参数化的测量器；平台范围未确认前不宣称全平台完成 |
| #53真实RF/光学研究 | 后续规格研究；当前EW采用可测抽象模型并标明近似，不挡首版联合战役 |

## 6. B0–B4待细化包与成本判断

以下成本为基于代码复用情况的**相对复杂度**，不是工期/完成百分比；开发、联调、测试和内容分列。G0/K0出来后再用明确切片与实际执行耗时排工程日，避免把模块存在直接算成已完成。

| 包 | 拆分与已有复用 | 开发 | 联调 | 测试 | 内容/调优 | 进入/退出条件 |
| --- | --- | --- | --- | --- | --- | --- |
| B0 | 本批B00；复用EntityCatalog/Formation/事件schema，新增舰队/指挥/情报/目标契约 | 中 | 中 | 中 | 低 | K0独立审查；三方/两套编制/旧档fixture可校验 |
| B1 | B01A部署；后续B1b逐舰火控/授权/弹药/冷却/预测/重放；B1c舰组跟随/护卫与最小操作UI | 高 | 高 | 高 | 中 | 不再共享旗舰账本；有效选择逐舰出击；非法发射者拒绝；H01相关缺陷关闭 |
| B2 | B2a规则型敌我任务执行；B2b请求/回执/失联/受损；B2c按链路共享情报与最低协同UI | 高 | 高 | 高 | 中 | 至少1支独立友军真实行动；敌我AI只读各自情报，协同改变态势 |
| B3 | 本批B03P提案；后续B3a目标运行层与裁决/玩家视图分离，B3b简报/阶段/战报 | 中 | 高 | 高 | 高 | 目标对象/阈值获用户核对；story=false仍可胜/败/撤离，不重复裁决/发奖 |
| B4 | 两套编制、协同正负例、敌方响应、战斗中读档、性能、非headless实际试玩及交付 | 低 | 高 | 高 | 高 | 同一版本正式入口完整流程、性能与人审证据齐全；不能只看probe数量 |

主要风险在逐舰CombatService账本、分方情报融合、AI任务执行与战役裁决的交汇，预计联调和负例验证不能压缩成一次最终冒烟。多人、持续战争经济和全套港口/资产不计入本表。

## 7. 首版建议与测量预算

建议标定档位为总计≤14个活动舰/目标实体、≤32个在途弹体、3个指挥域，AI决策周期2模拟秒；两套玩家编制用2–4舰体现传感器/火力取舍。具体舰型/组合点数由B00/B03P对照ShipCatalog提出，未实测前不承诺最大规模。

联合战役的**待测预算提案**：参考机与引擎记录完整，1×时每1模拟秒推进耗时≤100ms、3指挥域每次AI决策总耗时≤10ms；1080p实际渲染p95帧耗时≤33.3ms，命令本地受理反馈≤100ms（不含模拟通信延迟）。B4须留足样本再评价p95；当前AI/联合战役尚未实现，相关数值均NOT RUN。

存档沿#49保留旧fixture的硬目标；新战役另记UTF-8体积、保存/恢复、完整状态与恢复后行为，建议恢复体验目标仍≤5s，但新负载大小/保存预算须在部署与AI接入后依据实测冻结。不能把当前7实体的结果当成14实体＋AI＋目标的已达标证据，也不能通过删历史ID或关系统降成本。

JC-B03P先提交可审查的目标组合：例如解除2个指定军事作战单位的本场有效射击能力，并解除1个明确军事指挥节点的行动能力；只有已实现且本场不可自行恢复的机制才可计入，暂时干扰/失联不算永久失能。对象、阈值、友军阵容、失败/撤离/时限和保护目标均为提案，待用户核对后才进入B3实现。

首版验收口径始终是“自组舰队＋独立AI友军＋阶段性去军事化目标的一场联合战役”，不退回单旗舰开火测试，也不扩大成持续战略战争。
