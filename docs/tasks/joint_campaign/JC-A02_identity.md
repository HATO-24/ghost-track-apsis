# JC-A02：多来源身份收敛与IFF状态闭环

执行Issue：[JC-A02 #59](https://github.com/HATO-24/ghost-track-apsis/issues/59)。

状态：RETURNED，PR68首轮真实入口未闭环；A1已完成，A2不冻结。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 2026-10-27 PR68首轮复核：继续原#59五组收尾

候选 `7293058d1c0d3cdedceff1fae6233523e7f8b313`，main `1738a5e41509c09e04dc34da382dc07f4b8982e9`。[复核与真实反例](../../reviews/pr68_a02_20261027/review.md)。根七专项7/7（新66/0）；CI合成merge full89=82PASS/7历史FAIL、new_fail0、complete=true。绿色probe未覆盖真实路径，PR68暂缓合并。

保留：直接owner存储隔离、未知owner拒绝、真实本舰IFF/光学/ELINT已有接线、正常新人工正例；非本舰owner真实文件10tick身份/置信度/事件ID一致。手工pending行只证明序列化。A1完成不重开，不整项重做。

1. **R1真实来源/owner/单次消费**：盟军IFF回复未共享却写player；默认mode同回复两条证据/confidence0.563，显式mode_s一条/0.75；ELINT类别变iff。保留可信owner、原始事件/实际mode/时间/TTL/类别，修同一来源链，不靠UI过滤。
2. **R2人工权限/兼容/审计**：真实Binder走旧wrapper绕新门变authorized hostile、审计空；新口能自报command写盟军，撤销无actor，operator丢失。新旧入口/重放统一可信权限和审计，保留合法指挥员正例。
3. **R3实际消费者键**：HUD为T0001、身份键为raider_2，HUD friend但火控unknown。按owner合法映射统一内部键，保留匿名显示/实体键兼容；当前请求停needs_authorization，不声称实际发射。
4. **R4有效性/迟到**：TTL过期字段未被HUD/火控消费，state别名冲突；合法t2迟到证据即时late_ignored，下一tick仍改结论。修实际TTL/消费者策略和迟到接纳，不另设阈值或硬定过期皆unknown。
5. **R5查询/评估状态**：IFF valid覆盖conflict，遮挡被请求jam改报；区分查询与评估/人工状态，按原卡补实际等待/过期及查询继续，不用手工容器冒充运行链。

先真实红例再修，逐项对照，不只新API自比较；最终同SHA原C回归，七历史失败不刷新，不扩AI/EW/逐舰/真实RF。#60继续WAIT A2，UI接入与本卡共享文件串行。下方A1解锁是历史前置，原八段契约保留。

## 2026-10-27 A1独立放行后的开工交接

这是DeepSeek下一张核心实现卡。A1=`845584733df619feb3e372e8c06a7caa9f3fdaba`，已审main合并=`f62e5e6f48b3faf1098cbb44b2801c5c8fde394e`；G0/K0仍 `9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。先fetch main，确认包含f62e5e6f并记录实际40位执行SHA，不能从旧C55/main3045311覆盖A1。[放行与完整回归证据](../../reviews/pr66_a01_r5_20261027/review.md)。

已刷新当前接入点：`GameSession._advance_identification`推进既有计算器，`_flush_identification_outputs`目前发布assessment事件；Binder的contacts/plot已改为owner facade，`ident_view`仍经旧识别读取口。**A02须让相同owner的最终操作性身份统一进入当前真实UI/火控消费者**，不能只写旧全局TrackTable或单例assessment便宣告完成。按原卡做owner隔离、唯一写入/防重复、兼容和在途查询/衰减恢复；不要求改成指定类名或重做A1服务。

先交写者/读者与四来源字段表并保存有效红例，再分提交接服务→owner操作结果→IFF配置/查询回执→真实消费者→文件继续与证据。保留A01 90/0、metadata359/0、world-sync107/0及对应缺行/no-op红灯保护；不将计数当永久硬编码期望。七项历史FAIL不刷新；同最终SHA按原C回归。

核心只启动本卡；#60仍WAIT A2，#61/#62按原规则可准备独立服务但不得提前接GameSession。若改HUD/Binder，在PR登记文件归属，UI-01文案显示接入与本卡串行。UI文档/术语/交互由GPT维护；本卡代码由DeepSeek实现。原八段范围与验收如下，不增加完整AI/EW/逐舰账本。

## 1. 目标与缺口

C55已有IdentificationService的冲突/TTL/衰减/人工逻辑，但Session的assessment仅发事件，TrackTable也直接接受身份来源，操作结果未形成可验证的统一出口。收敛IFF、ELINT、光学与人工证据，使HUD/火控读取一致，来源冲突和过期确实改变结果。

## 2. 基线与范围

以已审A1及K0精确SHA开工；不直接从C55覆盖A01。范围为现有身份服务的接线/必要状态、transponder安装、证据标准化、TrackTable操作性身份、HUD/火控读取及恢复。复用既有推理算法；不开发真实RF/密码学或强制实现完整军用IFF模式，不更改阵营/指挥权来“确认身份”。

## 3. 权威、时间与可见性

原始证据入口带owner/source/observed_t/received_t/TTL与可信度；IdentificationService计算assessment；TrackTable为指定owner的操作性身份唯一写者，Session只路由一次。原始探测融合继续保留，不能重复消费assessment形成正反馈。人工确认是可审计的授权证据，有撤销/过期规则，不直接覆写隐藏真值或ROE。

IFF至少可表达未查询/等待/有效回应/无回应/过期/冲突/受干扰；无回应不等于敌对，回应声明不等于真实阵营，未知不回退friend。查询/回应依据可见应答配置，不能直接用catalog真实side替玩家解谜。orbital_sim按实体装入应答配置，旧配置缺失给明确状态，不能静默全友军。

## 4. 实施与提交拆分

1. 先定位所有写identity/manual_confirm与读取点，写冲突、TTL及重复路由红例。
2. 归一化四来源证据并接入既有计算器；收敛重复写路径，保留历史schema迁移与来源标签。
3. 接IFF查询/回执/无回应与人工撤销；把最终assessment经受权入口写TrackTable，HUD/火控读同一操作结果。诊断assessment若保留须明确advisory。
4. 分提交补安装配置、运行态恢复/待处理查询、探针及来源到消费者对照表。

## 5. 验收

四来源分别有效、冲突、过期、重复、不同到达顺序；相同证据集合在规定时间语义下得到一致结果。IFF单独有效不自动赋开火许可或友军直控权；人工未授权拒绝，撤销后恢复正常推断。伪装/弱证据降低可信度，不能凭单个字符串成确定友军。两个owner各有相同目标不同证据，不串域。

覆盖TTL边界同tick、迟到证据与原观测时刻、旧seed/旧档未知状态、UI与火控一致、真实文件恢复后至少10tick查询/衰减/事件ID一致。比较置信度误差≤1e-9，时间/几何按公共契约；不以显示标签通过代替实际消费者。

## 6. 命令与证据

注册`integration.jc_identity_pipeline`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_identity_pipeline|identification_probe|transponder_probe|track_table_probe|a0_(sensor_persistence|event_continuity|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_identity_pipeline|identification_probe|transponder_probe|track_table_probe|a0_(sensor_persistence|event_continuity|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A02/targeted
```

加C回归。日志须能追踪原始证据ID→assessment→TrackTable→HUD/火控，列owner/时间/来源/拒绝原因；保存红绿证据、恢复对比及同一最终SHA的CI。

## 7. 历史失败

#46相关显示来源差异单列；旧7失败绿化/漂移按公共规则处理，未知身份不能靠放宽ROE变绿，不刷新整份baseline。

## 8. 交付与复核

A2提交唯一写者图、IFF状态与旧档迁移表、所有写入/消费点、正负例与限制。独立审查检查重复证据是否虚增置信度、真实side是否穿透、人工确认是否跨owner或绕过授权。为EW接入保留正常证据通道。
