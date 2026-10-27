# JC-A01：指挥权限与分方情报隔离

执行Issue：[JC-A01 #58](https://github.com/HATO-24/ghost-track-apsis/issues/58)。

状态：实现原缺口CLOSED；仅两组验收测试RETURNED，A1未冻结。

## 2026-10-27 PR #66第四轮：三项实现关闭，仅补两组正式测试

被审HEAD `eb4b98530b589dd5c452a78d46549660985557d3`，代码`c704f85952eb33ec44c1ac21dfef95d2f8b6a032`；二者仅报告头不同。[独立复核、控制实验及证据](../../reviews/pr66_a01_r4_20261027/review.md)。**不重做三项实现，继续原#58验收收尾；PR66暂缓合并、A1尚未冻结。**

原owner老化、在途共享恢复、光学标签均已独立关闭：t31 stale/t301忘却；内存/公开文件各继续10tick，20对完整view相等、ETA5才可见、重投1→1；真实光学文本匿名且内部路由保留。selected及此前关闭项继续保持。

根代理五专项5/5 PASS（metadata357/0、world100/0、A01 76/0、integration65/0、save41/0）；完整原C **88=81PASS/7历史FAIL，new_fail0、drift0、complete=true、退出0**，340.45s。正式矩阵确实通过基线检查；余下不是三项运行时修复仍失败。

仅原R6等强度测试两组：

1. **T1指定合法contact正例**：metadata只检查数量，再允许任意缺行；诊断副本过滤已知harmattan后仍280/0。按可信owner已获证据明确至少一目标必须有contact及匿名HUD，用内部track_id匹配，不硬比匿名显示ID。未观测对象仍不显示，不恢复7实体全真值；可在已有A01正例补足，不要求重复整套。
2. **T2同目标隐藏移动/更新**：world probe观测ws_target却改harmattan，未核验变更；关闭变更的诊断副本仍100/0。用真实已观测同一目标，证明隐藏真值确变但真实HUD/plot仍读旧采样，再有合法新观测才更新。声称physics移动则实际核对physics，内部全7实体/精度/单向权威负例不放宽。A01当前改raider_2、比target_a view不能替代。

仅补正式测试、逐项映射及同最终SHA的原C结果；不因测试收尾预先改写已通过服务。不扩SIGNAL新任务或AI/EW/B1b。实现三项已CLOSED，不在下一轮重派。UI文档由GPT/Sol维护，DS接明确实现卡；UI运行时仍等待A1。下方前轮均为历史。

## 2026-10-27 PR #66第三轮：三项实现收尾＋等强度旧probe映射

候选 `8b4cf990021bafe0f5b2945039c850b5c985cf5a`。[第三轮独立复核与原始证据](../../reviews/pr66_a01_r3_20261027/review.md)。**继续原#58，PR66不合并，A1不冻结。** 下方前轮是历史，不重新派发其已关闭问题。

已关闭：实际来源授权/伪runtime借账本、正常有限8弹真发射与context字段；contacts/空plot不退真值；selected/详情owner绕过；共享正常到达与同键重投幂等；旧来源迁移、畸形/999/null拒绝；probe注册/合法夹具、空contacts越界、full退出码传递。保留绿证据，不整项返工。

仅本卡内收尾：

1. **原R3 owner生命周期**：t0一次观测后，真实tick31/301s，全局表已stale/forget，owner仍原range500/quality0.8无老化。落实各owner融合/衰减/忘却及恢复等价，不要求固定类名，不另立新产品阈值。
2. **原R4在途继续**：t2发ETA5，save/load后共享索引在但实际Comms.pending为空，恢复t3提前融合而连续会话t5才到。恢复实际在途队列/ETA/投递结果，逐tick对照并继续原卡至少10tick；正常投递与幂等不重做。
3. **原R3光学实际文本**：`_optical_entity_line`输出匿名标签后又拼接harmattan/l1_station内部ID。修显示，保留内部路由ID，不能放宽no-truth负例；此项不等待UI-01。
4. **两probe等强度映射**：[逐项修正表](../../reviews/pr66_a01_r3_20261027/contracts/findings.md)。metadata7条FAIL中的旧source/显示ID4条、signal无观测1条可改合同，另2条须先修真实泄漏；world-sync3条玩家plot旧全真值断言换owner观测正负对照，内部7实体与物理精度/单向权威检查保留。不删case、不加历史baseline、不靠空列表或只放宽source消红。

独立5项=3PASS/2FAIL：A01 **63/0**，metadata342/7，world-sync94/3，integration65/0，save41/0，整体退出1。CI关联同head、实际PR merge1196fdb1，Phase0/PhaseA成功，full **88=79PASS/9FAIL（7旧+2新）、drift0、complete=false、退出1**；旧退出码包装问题已修。本地未重跑完整88项。最终同40位SHA跑原C回归与真实文件/共享继续，不新增AI/EW/B1b范围。

新[60/61 UI材料](../../61_UI文案台账与实施队列.md)已拆文案/字体组件/层级/Phase B视图卡，设计可并行，运行时等待A1及设计核对；不得与本卡争改HUD/Binder。主要代码继续DeepSeek，Sol复核。

## 2026-10-27 PR #66第二轮：保留关闭项，仅收尾剩余

候选 `61f27fc8e841666705b5fd2e843824a03bf6c0b8`。[第二轮独立复核与证据](../../reviews/pr66_a01_r2_20261027/review.md)。**进度提交未完成，继续原#58，A1不冻结、#66不合并。**

**已关闭，不再重修**：敌actor/错controller/fleet/legacy敌actor拒绝；伪runtime第二舰不借账本；真实有限8弹合法射击；日志/审计context字段；HUD空情报不退回真值；contacts不混入盟军未共享观测；实际旧来源迁player不迁盟军；broken/999拒绝与公开恢复模式。动态重放随最终验收继续验证。

仅剩：

1. 原R3的**selected/详情/导出与每owner融合/衰减/选择**，当前selected(T0001)仍读盟军私有range456；保留contacts/plot修复。
2. 原R4**真实到达回调**：2779处String构造异常使首次共享未融合；先修实际成功投递，再查幂等和在途文件继续，不把首次未成功后的首次手工接收误认作新的去重根因。
3. 原R5 **present-null**：真正缺段旧档已通过，显式authority_intel:null仍被当legacy，补拒绝而非重做全部旧档。
4. 原R6 **有效验收/集成回归**：用主审正常TIGHT/真实grant/有限弹夹具修新probe正例和库存读取；新probe的所谓旧档先送未来t=1观测、再tick造成table/session错时，修夹具而非跳过旧log重放。恢复A01探针注册。空contacts处理UI index0越界；owner适配后的门禁断言按等强度契约映射，不恢复真值泄漏。修继承的full workflow缺少LASTEXITCODE捕获，不能把实际失败包装成绿job。

独立结果：新probe **45/12 exit1**（作者旧摘要43/13）；基础专项4/5、Phase0 4/6、PhaseA 1/3。CI full原始87=71/16、7旧+9新，页面绿色不代表通过。最终同40位SHA跑原C回归，7旧失败不刷新，不新增AI/EW/B1b范围。下方首轮清单及R8记录均为历史，关闭项以上表为准。

## 2026-10-26 PR #66首轮复核：继续原卡返修

候选 `1d1e8399da438b77b74acee40d753711c8d2a8f9`；独立8专项通过，但真实入口负例未通过，**A1不冻结，PR66暂缓合并**。[复核、最小反例与证据](../../reviews/pr66_a01_20261026/review.md)。保留已修未知/敌/盟shooter拒绝、合法本舰真发射、有效文件往返。

原卡内仅六组闭环：

1. **R1 授权**：实际校验请求actor/controller/fleet→shooter；legacy不能抹去显式非法context；没有真正独立运行态的其他本方舰必须unavailable，不能凭bool借旗舰账本。
2. **R2 Context**：规范化actor/controller/fleet/shooter进入操作/事件/审计与重放，含模拟时刻和兼容来源。
3. **R3 实际情报消费**：每owner融合/衰减/selected与HUD/list/plot/玩家导出统一；空情报不回退PhysicsWorld/snapshot全量真值，盟军未共享观测不进玩家全局表。
4. **R4 共享到达**：合法来源/授权/接收域、真实到达、observed/received/delay和去重；至少一个基本共享走实际投递链。EW/完整AI协议留后续，基本到达门属于本卡。
5. **R5 恢复**：旧全局航迹只迁可信本舰owner；存在但畸形的新段拒绝，不能静默当legacy；公开authority恢复模式；新旧文件对照。
6. **R6 验收**：隐藏真值须先证明确实变更，再测真实HUD；有效有限库存射击＋拒绝零副作用；三个owner、真实文件/在途共享恢复后继续10tick。现有生产测试钩子实际没改真值，不能据它宣布不泄漏。

不新增AI/EW/B1b范围、不重做已通过修复；根本生产代码继续由DeepSeek实现。先保存上述红证据，再最小修复、证据/报告分提交，最终同一40位SHA按原C回归核对。下方R8解锁记录为历史；G0/K0仍已完成，#59–#62按原依赖等待。

## 2026-10-26 R8独立复核更新

**READY：G0=K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。** 先fetch main并确认包含该候选；若后续main有代码变化先审差异，记录实际40位执行基线。按本卡原八段先做红例，再落指挥授权和每owner情报/读取/存档，主要代码由DeepSeek实现。此轮只启动这一张核心卡，不并行重写GameSession。P0产品待确认不阻塞本卡。见[解锁依据](../../reviews/pr65_r8_20261026/review.md)。

## 1. 目标与复现

C55的`GameSession.request_fire`在显式shooter_id无效时回退本舰，CombatService仍单一；系统`plot_positions`等真值接口也未形成可验收的多owner读域。先堵住错误授权与情报混流，为后续逐舰战斗/AI建立边界。

## 2. 基线与范围

解锁时将G0、K0填为实际40位SHA，并核对整链；C55仅为调查来源。范围为授权入口、owner隔离的观测/TrackTable访问、HUD/ViewModel/绘图的读取适配、命令日志及必要恢复。不得同时实现完整AI或逐舰战斗账本，不将系统物理解算内部真值接口删除后再从UI取代。

## 3. 写者、读者与可见域

部署/控制注册表写归属与授权；Sensor/合法消息投递写接收owner的证据入口；每owner的TrackTable写其融合结果；玩家UI和未来AI只能读对应context。真实弹体碰撞/物理解算可读内部真值，但不得随快照交玩家/AI。阵营关系只能影响许可检查，不能隐式复制航迹或武器控制权。

命令保留actor/controller/fleet/shooter及模拟秒；显式未知或非授权shooter在消耗资源、排弹、成功事件前拒绝，拒绝审计可记录。无context的兼容调用仅指旧本舰；已授权其他本方舰若尚无独立战斗运行态，返回`shooter_runtime_unavailable`，绝不借旗舰发射。friend盟军的直接命令拒绝，未来协同请求走另一协议。

## 4. 实施与提交拆分

1. 红例：无效shooter触发旗舰路径；同一隐藏敌方真值变化影响未经观测的玩家视图；三owner观测串域。先记录现状，已有正确项保留绿证据。
2. 按K0落授权检查与明确拒绝，补输入/事件/重放context；不要用到处if friend代替统一授权。
3. 落owner隔离的证据入口、融合与读取facade，覆盖list/selected、HUD、plot、导出日志/诊断视图。共享观测必须经受权链路实际到达，带来源与观测/接收时间，接收后才融合。
4. 补存档/恢复各域航迹与context；旧档迁入legacy本舰域，不能复制到盟军。提交顺序为红probe、服务/入口、UI读路径、恢复与证据。

## 5. 验收

正例：自有舰授权检查、合法本舰旧调用、三个owner独立观测，链路投递后只有接收方获得共享证据。负例：未知/敌方/友军shooter均无资源变化；未实现的其他本方舰战斗返回不可用；隐藏目标改名/改坐标但保持相同合法观测时，玩家视图与测试决策输入不变；无观测的owner仍未知。不得把测试用决策器当已完成AI。

覆盖selected/list/plot/导出、重复共享、非法owner、延迟到达、同tick顺序、旧seed/旧档。内存＋真实文件恢复再继续至少10tick，事件context、owner航迹与在途共享一致；共享几何使用observed_t，received_t单调，单位/容差按公共契约。

## 6. 命令与证据

注册新probe `integration.jc_authority_intel`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_authority_intel|track_table_probe|fleet_probe|a0_(track_truth|event_continuity|integration_authority|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_authority_intel|track_table_probe|fleet_probe|a0_(track_truth|event_continuity|integration_authority|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A01/targeted
```

加C回归；日志列每条输入context、拒绝原因、前后资源差、每owner可见字段、未来10tick对比、真实SHA/退出码/断言与CI。

## 7. 旧失败

特别核对#46本舰ID/TWS/显示来源，但不以权限修复掩盖原问题；7项full旧失败转绿/漂移单列，无新失败。保留orbital_sim有限资源/正常ROE，不通过改profile消除拒绝。

## 8. 交付与复核

A1提供授权/情报接口表、调用者迁移清单、兼容语义、独立证据及未接入点。独立审查应尝试直接调用Session、selected、plot与存档导出绕过facade。此卡完成不等于逐舰战斗或友军AI已完成。
