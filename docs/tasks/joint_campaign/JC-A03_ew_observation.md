# JC-A03：EW实际影响观测、航迹与火控

执行Issue：[JC-A03 #60](https://github.com/HATO-24/ghost-track-apsis/issues/60)。

状态：DONE（第四轮独立放行）；A3已冻结并合入，#60完成，下一张核心卡A04/#61。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 2026-10-28 PR70第四轮：PASS，A3放行

A3冻结 `5d372ea2df7c49badeea3846c16b839b1f6faef1`，PR70合入main `c3fca1c52a4158f374661f1906b32103dab5360c`，整个tree等于被审候选。[本轮独立证据与交接](../../reviews/pr70_a03_r4_20261028/review.md)。普通实体/HUD匿名键的发射前预测现在读取同一owner质量，mq-only实际应用既定因子，显式规范化输入不双重惩罚；旧档覆盖会清除前会话EW运行态，正式pending反例与独立真实文件fresh/active对照均关闭。原R2/R4及射后真实运动/partial/full/null结论保留，不再返工。

根专项11/11、新EW126/0、A02 122/0；原C Phase0 6/6、PhaseA 3/3、full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true、退出0。七历史baseline未刷新。低质量仍能发射本身不是缺陷，硬禁射推断不恢复。

#60完成，下一张核心卡为[A04/#61](JC-A04_ew_comms.md)，从包含上述main合入提交的最新main开始。UI设计/文档GPT/Sol，主要代码DeepSeek，核心A04→B01A。下方前三轮是复核历史，以本轮放行与关闭表为准，不重复派发已关闭工作。

## 2026-10-28 PR70第三轮：真实发射/R2/partial已好，仅两处入口

被审 `022a7e0e6b0ab2ce65f228f98b4a1146d18792f8`，main `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。[本轮关闭表与真实入口证据](../../reviews/pr70_a03_r3_20261028/review.md)。根11/11 PASS、新EW102/0、A02 122/0、A1 90/0；CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true，根未重复本地全量。

**不再返工**：射后真实prediction/launch已消费规范化误差；非共线同seed正例实际velocity和后续position发生差异，不能用原+Y共线退化把它判成无效，不新增完整制导/禁射模型。R2 owner拒绝不再写TT/map、原重投/候选及正常新观测全部关闭。R3 partial/missing、null拒绝、完整full加载已过。R4注册/W7继续关闭。低质量仍能发射本身不算问题。

只剩：

1. **原R1 [P2] 发射前普通预测**：实际HUD走combat_predict_track(T0001)，owner质量未映射到raider_2而回默认1。实体键虽收到q=.7994745/mult.85，仅mq分支仍给旧probability=.8775/error=.735；射后完整opts已经正确.745875/1.52475。统一合法内部键，补mq-only实际计算；显式quality/error不重复乘.85，保留射后/旧无字段正例。只读预测入口验收，不重做已过实际发射链。
2. **原R3 [P2] 旧档覆盖活跃会话**：真实pending实例t2 queue/samples=1/1，load同一无EW旧文件后now=0、ok/legacy_absent却仍1/1；fresh实例load相同文件是0/0。初始化/覆盖时清除先前会话EW运行态，再按同档字段/default规则恢复，fresh/active语义一致。保留正常full在途、partial/missing和invalid拒绝，不以清空合法新档来通过。

保留本轮非退化实际运动正例，补两个入口对照，最终同40位HEAD专项+原C，七历史baseline不刷新。PR70暂缓合并，继续原#60；A04/B01A核心接入仍等待A3，代码DeepSeek，UI设计/任务文档GPT/Sol。下方前轮为历史，以本轮关闭/剩余表优先。

## 2026-10-28 PR70第二轮：关闭大部分原反例，只剩三个连接/错误边界

被审 `ea29da7138ad353c4198f76547f57c4e0b07142d`，main `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。[本轮关闭表与原始数据](../../reviews/pr70_a03_r2_20261028/review.md)。根11/11专项PASS，新EW83/0、A02 122/0、A1 90/0；CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true，根未重复本地全量。PR70暂缓合并，继续原#60。

**保留已过**：CombatService READY/预测/射击字段的精度因子和measurement时刻/状态；真实原观测/非空候选重投幂等及正常own/ally新观测；完整文件full、null队列invalid且有字段原因、全EW缺段legacy_absent；A02注册恢复、90个ID非空唯一和W7真实文件10tick队列/捕获几何质量/投递/owner/实际解算对照。原R4完全关闭，不再派发。低质量仍可发射本身不是缺陷，硬禁射推断不恢复。

只补原三组的剩余边界：

1. **R1 [P2] 真实Ballistics输入**：同seed、同t24/600km几何，clean q=.90849375、moderate q=.7994745；CombatService已正确.8775/.735→.745875/1.52475，但最终Ballistics prediction仍双方.8775/.735，弹体初始aim/velocity也相同。Session launch_opts/真实predict没有传测量质量或误差。把既有抽象精度/误差接入真正发射/弹道路径，保持风险返回与实际输入一致；不要求单发必然脱靶、完整制导或禁射新策略，已过接口层不重做。
2. **R2 [P2] owner拒绝前拦写者**：原重投已不回滚。仅错投接收owner的真实条目被share_not_authorized拒绝，measurement/owner observations无写入，却仍在拒绝return前创建全局TrackTable 0→1和map。拦住这些写入，保留已过重投/候选及新观测；不扩通用事务架构。
3. **R3 [P2] 部分新段规范化**：原queue=null已明确拒绝。只缺ew_combat_quality仍触发Dictionary转换SCRIPT ERROR；公开load虽失败，但mode=absent、错误field空。按字段必需/可选合同给明确缺失拒绝或有意兼容默认，避免运行时异常并解释字段原因；不重写存档或重做正常10tick。

补上述真实残例和原正例，最终同40位HEAD专项+原C，七历史baseline不刷新。A04/B01A核心接入仍等A3；UI设计文档GPT/Sol，代码DeepSeek。下面首轮/口径纠正为历史，优先按本轮关闭/剩余表执行。

## 2026-10-28 PR70首轮：保留正常链路，只补实际消费者边界

**产品口径纠正**：原卡要求情报质量影响解算/耗时/误差，不等于低质量一律禁射。q<0.5拒绝新建解算是本候选fixture，不能自行外推为已有解算必须禁止发射。原R1的P1硬禁射推断撤回，收窄为P2精度消费与解算语义；下面以此修订后的R1为准。是否自动禁射/强制射击尚未获用户确认，本卡不新增这些产品规则。

被审 `6bd919aa19898bbf31f5dd7c3287befc47392877`，base/main `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。[独立复核与真实反例](../../reviews/pr70_a03_20261028/review.md)。PR70暂缓合并，继续原#60，不新开功能卡。

保留：真实采样乘数/延迟；own/ally正常owner路由、未登记observer拒绝归入玩家、错误target/kind排除；current与历史max分离；真实文件在途队列及完整状态/几何/解算行10tick语义一致；缺七新段旧档可load。JSON数字2与2.0的表示差异不当作恢复失败，不做全局转int。

仅四组返修：

1. **R1 [P2] 精度消费与解算语义**：持续moderate READY当前q=.7994745时，已声明精度×.85未进入实际输出，补实际精度/误差消费。三例低质量下旧解算仍发射仅保留为观察，不作为失败标准；明确继续用历史解算时所用数据时刻、质量、误差及有效性，保持新建与既有解算策略一致可解释。保留正常授权、高质量、恢复和旧字段兼容，不新增硬禁射、强制射击或完整盲射功能。
2. **R2 [P2] 全消费者投递幂等**：真实旧OBS-000008原样重投，底层去重但measurement从.90849375@21回滚.7@7。把接纳/去重覆盖measurement、combat及候选副作用；明确接纳结果，保留正常新观测。此为一次明确重投，不声称自然阶段自行重复。
3. **R3 [P2] 新EW坏段拒绝**：真实在途1项存档仅将已有ew_observation_queue改null，load却ok/errors=[]且队列清空。区分present-invalid与真正缺段旧档，验证新EW字段必要类型/值并明确拒绝；保留有效文件10tick继续，不重写存档体系。
4. **R4 [P2] 注册与等强验收**：插入新EW case时丢失旧A02的integration.jc_identity_pipeline，旧脚本虽匿名122/0仍运行，按原ID选择已0项。恢复旧ID，保留EW唯一ID及总90项；补R1真实COMPUTING/READY/射击的精度/误差策略消费，以及W7完整队列/捕获值/实际解算对照，不以还能发射判失败，不只看末尾ID/质量或自报字段。七历史baseline不刷新。

根专项11执行行PASS（含匿名A02问题），新EW47/0、A2脚本122/0、A1 90/0。CI同head合成merge full90=83PASS/7历史FAIL、new_fail0、drift0、complete=true；根本轮未重复本地全量。最终同40位变更HEAD专项+原C，逐项关闭，不重做上列正常服务。

采样相位按候选先采后步记录，不把t_end边界单列新增bug。错target/kind已测，独立接收方/频段上下文未定义；报告应明确支持的抽象作用域负例与限制，不把band标签切换说成已验错频，也不扩真实RF/完整接收机。A04/B01A核心接入继续等待A3；UI设计文档GPT/Sol，代码DeepSeek。下方A2开工交接与八段合同继续有效。

## 2026-10-28 A2放行后的开工交接

执行基线：A2冻结 `755ab5ed629165656a566427523b01045775fc0f`，已审main合入提交 `82bf6a531042961f0d5fe5d948c7004a15cd20cf`，整个tree等于被审候选。A1=`845584733df619feb3e372e8c06a7caa9f3fdaba`，G0/K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。先fetch main，确认包含本卡顶部记录的A2合入提交，再记录实际40位执行SHA；不可用C55或旧A1覆盖已落A2。

这是下一张核心实现卡，代码交DeepSeek；Astra保留需求权，GPT/Sol维护任务卡与UI设计文档。核心接入继续A03→A04→B01A，HUD/Binder共享文件与UI-01串行；A04通信和B01A部署仅按原依赖准备独立服务。

当前真实缺口仍在：GameSession.tick先_advance_sensors后_advance_ew；_advance_sensors调用SensorService.step并即时送owner情报和TrackTable，authority.receive_observation当前received_t=t、delay_s=0。_advance_ew仅推进和发事件；ew_observation_effect是查询包装，尚未接实际采样。CombatService.request_solution/tick的质量仍主要来自武器精度和距离。先用真实API同seed开/关对照保存这些缺口，不能只断effect字典。

按现有链路分提交：明确同tick的effect采样时刻/一次推进→真实观测质量与延迟→owner航迹当前measurement quality→实际解算/射击结果→真实文件在途继续。复用原_sensor_track_map与A2统一身份出口。纯测量质量/航迹观测走Sensor→TrackTable；只有产生身份判断证据的欺骗候选走A2 identity_ingest及普通证据验证，保留owner/source/event/observed_t/received_t/TTL及单次消费，不直接改身份、权限或隐藏side。保留实际HUD航迹键（如T0001）到实体键解析、实体键兼容、过期显示/火控及A2来源/审计回归，不重做已落算法。

在首个实现提交前交写者/读者及时序/单位表，并冻结当前fixture的质量→解算可用性/耗时/误差规则。按原0.7乘数、effect实际delay与1e-9/1e-6容差验收；延迟期间不提前可见，保存再从真实文件恢复后至少10tick队列/ID/质量/解算与连续运行一致。最终A03变更HEAD的同一40位SHA跑专项和原C，七历史baseline不刷新；不新增Comms接入、AI、真实RF/光学传播或完整军用协议。

以下八段原合同继续有效；C55仅为缺口历史来源，当前行为以上述A2基线为准。

放行依据：[A2第三轮独立报告及完整C](../../reviews/pr68_a02_r3_20261028/review.md)。

## 1. 目标与缺口

C55的EW effect接口没有真实Sensor/Comms消费者，CombatService解算质量主要由武器精度与距离决定。把EW接进实际观测及火控，必须在相同真值、相同合法输入下看到可解释的作战差异，而非只多一个HUD状态。

## 2. 基线、依赖与范围

以已审A2/K0的40位SHA开工。范围为EW→Sensor/延迟队列→TrackTable→实际火控质量消费，以及小范围Session时序/存档接入。Comms属于A04，友军AI属B2；真实RF/光学传播研究仍为#53。不要做另一个直接写敌身份或损伤的EW系统。

## 3. 权威与数值契约

EWService写干扰运行态和抽象effect，Sensor采样并应用一次，TrackTable按owner融合，CombatService消费操作性测量质量/误差。同tick先取得规定时刻effect再生成观测；当前Session sensors先于EW，须明确调整采样顺序或提供等价时刻查询，不能双步进EW。

保留采样几何/observed_t，延迟只改变received_t与投递，不用后来的真值重新生成旧观测。`.t`等既有单调入口如何兼容由K0明确。队列按稳定次序投递并保存，质量[0,1]。以当前模型fixture：原质量1、仅noise_jam=0.5时confidence乘数0.7，误差≤1e-9；实际delay与`observation_effect`返回值一致，误差≤1e-6s。内部`_iw`也可能增加delay，不能只硬编码3s。

不能让TrackTable历史max质量吞掉当前干扰退化；区分历史证据与当前measurement quality，火控实际消费后者。冻结fixture中质量→可解算/需更久/射击误差等实际规则与阈值；不能只改显示数值。EW不直接赋阵营/权限/伤害；欺骗若生成候选证据，必须留在被影响owner并走普通验证融合，不自动成确认目标。

## 4. 实施与提交拆分

1. 红例：同seed与同观测条件开/关EW，真实Sensor与火控输出仍无差异；记录既有effect数值作为对照。
2. 接观测适配、稳定延迟队列、capture/delivery双时间及质量语义，保留未受影响链路与EW=0原行为。
3. 让实际火控消费已授权航迹质量/误差，明确不足时的拒绝/降级原因；不能拉真值补全不确定性。
4. 接保存/恢复及Session顺序，按服务、队列、消费者、集成证据分提交。只新增真实存在的运行态，不预置空AI/目标段。

## 5. 验收

EW关/开/到期/错误observer或频段、噪声/已支持的欺骗/诱饵渠道分别测；正常航迹不会被其他owner干扰篡改。检查同tick只应用一次、延迟期间不提前显示、重复消息不重复融合、旧观测不换成当前真值、质量确实影响火控结果。未支持的效果明确标限制，不以返回effect字典算已接入。

旧seed/旧档EW=0兼容；在途观测真实文件恢复并继续至少10tick，同seed队列/ID/质量/实际解算一致。无有效航迹返回不可用，不回退系统真值。几何与数值容差按公共契约，不放宽已有精度。

## 6. 命令与证据

注册`integration.jc_ew_observation`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A03/targeted
```

加C回归；保留一组固定seed开/关对照，列effect采样时刻、原始/最终质量、observed/received时间、TrackTable及火控结果、恢复后10tick、退出码与断言。日志标记抽象近似模型，不声称真实RF已验证。

## 7. 旧失败

旧7失败逐项保留/解释；不以削弱默认传感器、关闭正常授权、修改baseline或删除不利观测消除失败。若#46相关航迹显示由本卡真正修复，附原case绿证据后独立调整。

## 8. 交付与复核

A3交付实际消费者表、时序/质量/延迟契约、红绿对照、保存继续证据与未支持效果清单。独立审查追踪从effect到真实观测/火控的完整链，并尝试更换owner/观测时间绕过约束。
