# JC-B00：联合战役多舰队、指挥与情报契约

执行Issue：[JC-B00 #57](https://github.com/HATO-24/ghost-track-apsis/issues/57)。

状态：R7独立复核后收尾，G0/K0尚未放行。公共规则与C回归见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 2026-10-26 R7复核后的当前执行范围

候选 `2ae7bf7cba8af32ff4456cefe28efa3650b868dd`。[独立复核及证据](../../reviews/pr65_r7_20261026/review.md)。

**R7独立复核：核心授权/引用负例已关闭，K0最后归一合同。** 独立probe78/0；未部署shooter、敌方自授权、部署负时/终态、缺command_id和错误request关联均已正确拒绝，OBS-3合法共享通过。只补：seq必需性/合法省略策略；受支持lifecycle版本及未知版本策略；跨owner receiver是否必须显式（实现默认、报告却称必需）；同步canonical合同的原始owner→授权→接收owner语义和新字段写者/读者/单位/时间/可见域、旧单舰适配口径。不要重做已修权限链，不要求提前实现AI/战斗。额外生命周期时序组合仅非阻塞观察，详见复核报告§3。

下方八段保留原交付契约；已关闭问题不再整项返工，新一轮按剩余输入留红绿证据并对齐最终40位SHA。

## 1. 目标与缺口

将“一场联合战役”拆成可实施的契约，消除friend=直控、单一旗舰资源、全局航迹融合后再过滤等隐含前提。复用Formation/EntityCatalog/TrackTable/Comms，不以模块存在算完成。

## 2. 基线、依赖与范围

设计起点C55=`30b8d33dae9787aadf89bb206757cafb2cad7bd3`；运行态接口冻结前对齐JC-A00的G0，记录实际40位SHA。范围为规格、字段/schema、有效与无效fixtures、最小契约校验探针；不实现部署/战斗/AI/裁决，不改默认profile或剧情。G0未出可先写文档；K0须经独立技术复核后才解锁A01。

## 3. 读写、单位与可见性

提交一张字段表，逐项列类型/版本、唯一写者、读者、单位、时间、可见域、存档迁移与拒绝原因，至少覆盖：

- campaign_id、fleet_id、独立entity_instance_id、ship_class/config_revision；命名舰唯一与可重复舰体实例分开。静态舰级数据不保存运行态，部署实例不以fleet_id替代entity_id。
- faction关系、controller_id/直控授权、intel_owner_id、ROE授权分别建模。玩家仅直控自有舰队；AI友军独立执行请求，可接受/拒绝；friend不赋予直控或全情报。
- 单舰装备/弹药/燃料/冷却/损伤/命令账本、世界运动学及部署生命周期DRAFT→VALIDATED→DEPLOYED，重复请求幂等。t→kg仅×1000一次；位置km、速度km/s、时间模拟秒及UTC历元明确。
- 观测的source/observer/owner、observed_t/received_t、共享路径及延迟。比较每owner独立TrackTable与显式分区方案，选择一种保留各自融合/衰减状态；不能在全知融合后仅过滤UI行。
- 命令actor/controller/fleet/shooter、事件ID/seq、通信请求/回执/执行生命周期；无效显式shooter拒绝，旧调用缺context只映射旧本舰，不能扩成所有友舰。
- 目标运行态、权威裁决与玩家获知的目标状态分开；AI只持授权读接口，不持可任意取敌真值的Session指针。story=false仍保留战役目标。

## 4. 实施与提交拆分

1. 用当前代码文件/函数定位权威来源、缺口和兼容调用者，先写契约冲突fixtures及失败原因。
2. 提交`docs/contracts/joint_campaign_r2.md`、必要`config/schema`定义与JSON fixtures；说明现有schema校验能力及新增语义校验器，不能声称已有完整JSON Schema引擎。
3. 增加`jc_contracts_probe.gd`并注册`integration.jc_contracts`，只校验结构/引用/权限语义及可逆序列化，不引入假AI、空的“已完成”战役快照。
4. 冻结接口签名、事件/存档版本、未来B1–B3新增字段的增量方式；既有历史存档缺新段明确legacy scope，不制造虚构部署/任务。

## 5. 验收

正例：玩家/独立友军/敌方三指挥域，两套合法且不同的自有编制；选择→实例关系明确，未选择舰不在部署清单；各owner各自观测及合法延迟共享。负例：重复实例ID、跨域指挥、无效shooter、资源引用别舰、单位缺失、未知版本、越界/非整数ID计数、先收到后观测等时序错误，逐项明确拒绝。

存档fixtures按版本往返；旧seed/旧调用保留本舰语义，不能因此授权盟军。合同层同tick和继续事件轨迹验证只证明数据契约，不声称真实舰队已运行。明确哪些字段尚待内容确认。

## 6. 命令与记录

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_contracts|fleet_probe|ship_catalog)' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_contracts|fleet_probe|ship_catalog)' -Ci -ResultsDir .test-results/jc-r2/JC-B00/targeted
```

新probe入matrix后执行上述专项及C回归；仅设计提交则如实写未运行运行态验收。保存schema/fixture哈希、具体反例原因、断言计数、退出码与完整SHA，0 case不通过。

## 7. 历史失败

保持7项旧失败记录；若schema/调用兼容变化使其转绿或漂移，逐项解释，不顺手刷新baseline。#45/#46关联字段须列入复用/迁移表；#47/#48不因本卡重写旧剧情。

## 8. 交付与复核

K0包含契约、接口/权威表、schema/fixtures/probe、B0退出检查和G0对应SHA。已确认的战区范围/友军请求无需再问；兵力、目标阈值、舰池点数仍为提案，交B03P形成具体内容后给用户核对。独立审查特别核对“阵营、直控、情报、ROE”四者是否真正分开。
