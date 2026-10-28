# JC-B01A：两套编制转为独立、可恢复的参战部署

执行Issue：[JC-B01A #62](https://github.com/HATO-24/ghost-track-apsis/issues/62)。

状态：RETURNED / 第四轮；首次时钟锁和手动快照子项关闭，原R5运行态三层一致及R4自动配置冻结仍待修。D1未放行，继续原#62。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 2026-10-29 第四轮：关闭时钟/手动快照，只收尾原R4/R5两处

候选`db3bef90420178ba246a54b13efd7a342bb6c013`，[本轮关闭表和实际三层集合](../../reviews/b01a_r4_20261029/review.md)。根部署probe83/0；首次确认成功、plan/commit一致、手动实际快照匹配均关闭。确认后catalog5舰、world6实体含legacy、physics仅legacy仍未通过；auto=true实际配置冻结仍为空。只修原运行接线target/seed应用及自动冻结顺序，已有关闭项不重派。用户转交，D1不放行。

## 2026-10-29 第三轮：原R4/R5入口仍阻塞

PR75候选`3ea9e8ceb9f247acd4a24641277c621146730d8f`，[独立复核与真实Binder记录](../../reviews/b01a_r3_20261029/review.md)。根专项7/7、新83/0，但交付auto=true只证明already_deployed；同场景auto=false在Binder.boot后已t0.1，首次DEPLOY立即deployment_locked。原auto冻结早于FleetRefit就绪，PLAN与DEPLOY返回不同revision，当前配置非空而冻结为空。继续原R4/R5；不重派第二轮已关闭子项，不以CI绿或83/0替代入口证明。交接由用户转发。

## 2026-10-29 第二轮：原五个窄观察关闭，继续R4配置与R5交付

候选`323018ac4c13c9815c6b56d7e32c14976000d38e`：[独立关闭表与证据](../../reviews/b01a_r2_20261029/review.md)。原R1物理名单、R2非法controller、R3旧seed覆盖与缺资源恢复、R4几何revision均由原诊断复测关闭；部署专项72/0。已关闭子项不重复派发。实际玩家装备配置冻结与原HUD/非headless/正式负例、事件连续性、最终同HEAD专项+原C及新B01A PR继续。D1未放行；下面首轮记录为历史，以本轮关闭表为准。交接由用户转发。

## 2026-10-29 首轮：核心里程碑2，原卡继续

核心候选`7185b92e83482b731ca7d15da7765ae41eda7c4c`，基线`4e75897ed32f8245f35c5ec584f0ec912ec919c6`。[独立复核与原始证据](../../reviews/b01a_r1_20261029/review.md)：根专项7/7、新72/0；显式旧physics名单、无授权controller、旧seed文件覆盖活跃部署、缺资源恢复和几何未进revision等窄反例仍在。已有默认部署/单位转换/资源独立/合法恢复正例保留。原Binder最小部署入口、非headless证据、完整负例/事件连续性、最终同HEAD专项+原C及新交付PR待完成。

继续本卡返修收尾；七历史baseline不刷新，不扩B1b/AI/RF/预算产品参数。UI设计合同GPT/Sol，主要代码DeepSeek。下方A4交接与八节原验收均保留，本轮不冻结D1。

## 2026-10-29 A4放行后的开工交接

A4冻结`af924d09f5c1d763f8d2556cd94062134ef3c456`，PR72获审合入main`1b483e0f2f2a9bfdaa100caf2ee6742091193204`，完整tree`7576df59d39feb86fff7073240d0f8bdcfc99587`与被审候选相同。[A4独立放行](../../reviews/pr72_a04_r4_20261029/review.md)。A1=`845584733df619feb3e372e8c06a7caa9f3fdaba`，G0/K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。开始时fetch最新main，确认包含上述A4合入，再记录实际40位执行HEAD；已有服务分支须先合入最终A4，不覆盖owner、身份、EW时序、发送权限或恢复合同。

现有Formation只写assignments，Session fleet_assign/unassign/move只改选择/发事件，Binder仅ASSIGN/UNASSIGN/MOVE/VALIDATE，不是参战部署。沿原卡接完整的选择校验→配置revision/稳定实例/幂等冻结→同源deployment seed→catalog/world/physics/每实例资源，未选舰不得残留于任何一层。

按实际boot顺序接线：catalog从seed注册；_setup_optional_components内初始化PhysicsWorld并seed物理实体；随后entity.spawn发布并apply到WorldState。不要另造顺序或在boot后仅upsert_physics_entity：该函数只写物理，而world_physics_sync对world不存在的ID跳过。physics_world.entities配置优先于seed.entities，部署时不能遗留旧全名册覆盖；质量/燃料t→kg只转换一次，坐标/速度/参考系/历元同源。

部署实例同步接入own_entity/fleet_instances/command_domains及既有sensor/owner/EW链。生成实体不等于向玩家生成已知敌航迹；编制VALID不等于已出击。冻结选择与实例资源分开保存，恢复不重复生成、不在交战中重boot抹损伤；B1b前其他本方舰战斗运行态仍明确不可用。

最小确认→部署结果/拒绝原因UI按[UI-04a原设计合同](../ui/UI-04_phase_b_views.md)和[61文案/组件排程](../../61_UI文案台账与实施队列.md)，核心与Binder共享文件串行，不扩全屏重写或协同页。保留本卡原最小非headless操作/截图验收，不能用headless probe替代实际可见入口。UI设计文档GPT/Sol，运行代码DeepSeek。舰池/预算/命名继续待B03P核对，旧13舰/8槽不是批准参数，不在本卡扩B1b/AI/目标结算。

## 1. 目标与缺口

C55的FleetFormation管理选择/名册，但尚未把自由组舰变成完整的参战世界实体。建立“选择→校验→冻结部署→真实生成”的最小链，确保未选舰不出战、每舰资源独立，两套选择产生可解释差异。

## 2. 基线与范围

服务的A1/K0依据保留；最终接线以顶部获审A4及其main合入为底，记录实际40位执行HEAD，按顺序集成，不同时重写GameSession。范围为既有Formation/ShipCatalog复用、deployment seed/实体映射、独立单舰初始运行态、必要部署入口/存档。舰池/点数/命名由B03P提案；旧13舰/8槽不是固定产品要求。

本卡不开发完整Refit/港口、舰队AI、目标结算或多舰发射。其他本方舰在B1b逐舰火控账本完成前明确返回战斗运行态不可用；绝不能借旗舰service展示“多舰开火已完成”。

## 3. 写者、资源与生命周期

Formation写选择，部署服务原子校验/冻结实例；EntityCatalog在boot按部署seed注册静态来源，PhysicsWorld写各实体运动学；单舰运行态容器按K0持独立装备/弹药/燃料/损伤/命令。选择/config snapshot与运行态分开，禁止共享可变Dictionary/Array。

实例ID稳定且全局唯一，named hull唯一、通用舰体重复要不同ID；fleet_id/controller/owner分开。mass/fuel从名册t到物理kg仅×1000一次，Δv用km/s，部署坐标/速度/参考系/历元同源。不能boot后绕开catalog临时生成无元数据舰。

## 4. 实施与提交拆分

1. 先写选A/B但world仍旧实体、未选舰仍存在、两个实例共享资源等红例；列实际可用舰型与需要用户批准的命名/预算。
2. 实现纯选择校验与部署seed生成：全部合法才提交，重复请求幂等，失败不半生成；以预部署阶段冻结/明确重置为边界，不在交战中重boot抹掉损伤。
3. 从同一seed构造catalog/physics/单舰初始容器，接最小编制确认→部署入口，呈现合法/拒绝原因；无目标运行层就显示未就绪，不伪造胜利结算。
4. 保存选择、冻结配置revision、实例映射及已存在的独立资源；恢复不能再次生成重复实体。提交按纯服务、boot接线、最小UI、恢复与证据拆开。

## 5. 验收

两套合法编制在实体集合、装备配置/质量/传感器输入等方面有可解释差异；实际火力差异留B1b验证，不以纸面数字宣称战斗已通。未选舰不在catalog、world、physics或资源账本；至少两个实例互不共享资源，改一舰燃料/损伤不改另一舰。自有直控/友军请求边界继续成立。

负例：重复命名舰/实例ID、未知舰级、越预算、无授权控制者、缺配置、质量转换错/无效坐标、重复部署；失败原子且理由明确。旧单舰seed/旧档可用；部署前/后真实文件恢复、同tick映射与至少10tick运动/事件一致，无重复实体。需最小非headless确认选择→部署可见，完整战斗试玩仍在B4。

## 6. 命令与证据

注册`integration.jc_deployment`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_deployment|fleet_probe|ship_catalog|a1_entity_metadata|a0_(world_physics|entity_metadata|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_deployment|fleet_probe|ship_catalog|a1_entity_metadata|a0_(world_physics|entity_metadata|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-B01A/targeted
```

加C回归。保存两套seed/实例清单、前后资源diff、catalog/physics来源表、拒绝对照、读档继续日志与非headless截图/操作步骤/环境；不能以probe通过替代UI存在。记录精确SHA、计数、退出码与限制。

## 7. 旧失败

#45仍为后续B1逐舰战斗必要依赖，本卡不靠关毁伤绕开；若部署触发其既有红例，按历史记录并分清新失败。#49预算保持固定旧负载，新战役规模另测，不修改fixture凑合格；不自动刷新baseline。

## 8. 交付与复核

D1提供可复现最小部署入口、两套编制、独立资源/实体映射、恢复与UI证据；独立审查尝试重按部署、换编制读旧档、修改一个实例后观察另一个。完成状态注明“B1部署切片完成”，后续B1b火控账本/B1c舰组控制未完成。
