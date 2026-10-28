# PR70 / JC-A03 第二轮独立复核

日期：2026-10-28（Asia/Shanghai）。**RETURNED，只剩原R1/R2/R3各一处窄收尾；R4关闭。** 延续已纠正的产品口径：低质量仍可发射本身不算缺陷，不新增硬禁射、强制射击或盲射规则。

## 1. 被审版本与结果

HEAD `ea29da7138ad353c4198f76547f57c4e0b07142d`，上轮 `6bd919aa19898bbf31f5dd7c3287befc47392877`，base/main仍 `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。PR70保持open，A3不冻结。

根独立专项 **11/11 PASS，62.3s含28.9s import，退出0**：新EW83/0、A02 122/0、A1 90/0、combat255/0、EW252/0、sensor128/0、track161/0、CIC925/0、sensor persistence86/0、authority65/0、save41/0。11项现均有正常ID。[report](targeted/report.md) / [summary](targeted/summary.json)。

[CI run40675971131](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40675971131)关联同head，三个job success。实际full checkout为合成merge `82e2e87cb505a5ba5c0842b252a4b41b096d4ca5`（ea29da7合入3845852），**90=83PASS/7历史FAIL、new_fail0、drift0、complete=true、FULL_MATRIX_EXIT=0**，375.4s。[原始日志](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。根本轮未重复本地full90；消费者反例仍阻止放行。

没有修改生产、正式probe、matrix、baseline或退出码包装；只写有界诊断及根docs。导入生成.import/.uid保留，不交付。三个诊断各退出0，表示记录完成；恢复诊断的目标SCRIPT ERROR以及fixture退出资源提示如实保留，不能称全无错误。

## 2. 关闭表：保留这轮已完成工作

| 原组 | 本轮已关闭 | 仅剩 |
|---|---|---|
| 修订R1 | CombatService READY/预测/射击的精度因子、误差、measurement时刻/状态字段已消费；低质量已有解算仍可发射按纠正口径保留；高质量及旧无字段兼容正常 | 实际Ballistics消费者未接这份不确定性 |
| R2 | 原OBS-000008原样重投不再回滚measurement/combat/cache，不增正常投递；非空真实候选重投也幂等；正常own/ally新观测继续接纳 | owner拒绝后仍写全局TrackTable/map |
| R3 | 完整新档公开load full成功；queue=null明确ok=false/invalid且有字段原因；所有EW字段缺失的旧档legacy_absent成功 | 只缺ew_combat_quality时触发运行时转换错误，而非规范化失败 |
| R4 | A02注册恢复；90项ID均非空且唯一，按原ID命中1项；W7真实文件后10tick比较队列/捕获几何质量/投递/owner质量/实际解算行 | **CLOSED，不重派** |

[观测/接纳分项](observation/findings.md) / [检查摘要](observation/summary.json)；[恢复公开返回](time_restore/result.json)；[注册检查](matrix/result.json) / [按原ID列表](matrix/a02-id-list.log)。baseline blob与main相同，不刷新七历史失败。

W7本轮正式83/0中已强化：保存前自然队列非空、真实FileAccess读写恢复、再继续10tick，比已知队列签名的ID/owner/target/双时间/delay/quality/捕获pos-range-bearing、投递记录、owner质量及实际solution状态/quality/error/measurement_t。保留这段正常续存，不要求重做存档实现或把JSON 2/2.0转换成新的故障。

## 3. 仅三处原消费者/错误路径收尾

### R1 [P2] 精度在接口层生效，真实弹道预测与弹体没有收到输入

**此项与能否发射无关。** 单次有界诊断的clean与moderate使用同一Sensor seed、同t24、相同实体状态/几何、同600km combat range与合法本舰FIRE上下文。clean来自正常真实Sensor q=.90849375；moderate来自真实apply_ew(noise=.2,duration60)后的q=.7994745，没有手造质量或删owner数据。

| 消费层 | clean | moderate |
|---|---|---|
| CombatService解算/门面预测 | quality=.8775，error=.735，mult1 | quality=.745875，error=1.52475，mult.85 |
| 最终Session返回中被覆盖的Ballistics prediction | probability=.8775，error=.735，range600 | **仍完全相同**，没有measurement_quality |
| 实际弹体初始状态 | aim=(321719,600,0)，vel=(0,8,0)，FLIGHT | **仍完全相同** |
| 资源 | ammo8→7，正常发射 | ammo8→7，正常发射 |

只观察发射/FLIGHT，hit=false，不声称命中或统计命中率。附加旧无Sensor/无measurement兼容例也能正常射击，明确是另一兼容fixture，不混作同Sensor对照。

静态链路与动态值相符：[GameSession:3424](https://github.com/HATO-24/ghost-track-apsis/blob/ea29da7138ad353c4198f76547f57c4e0b07142d/game_v17/scripts/core/game_session.gd#L3424)建launch_opts只带salvo/profile/intent等，:3445调用真实launch，没有传测量质量/误差；射后把res.prediction重新设为_ballistics_predict，后者[3585](https://github.com/HATO-24/ghost-track-apsis/blob/ea29da7138ad353c4198f76547f57c4e0b07142d/game_v17/scripts/core/game_session.gd#L3585)仍只传物理状态和武器。[CombatBallistics.predict:841](https://github.com/HATO-24/ghost-track-apsis/blob/ea29da7138ad353c4198f76547f57c4e0b07142d/game_v17/scripts/core/combat_ballistics.gd#L841)及launch/弹体初始化不消费该measurement数据。因此结论不只来自“单发轨迹相同”，还来自实际消费者完全没有相关输入。

**最小收尾**：把已声明的抽象质量/误差作用接到真正发射/弹道预测使用的路径，保持返回的风险和实际采用的误差一致；可复用既有近似模型，不要求真实RF、完整制导或新盲射系统。固定seed/几何的对照须证明相关输入被实际使用，不以换一个显示字段、改返回字典或单发必须脱靶代替。继续保留允许旧解算射击的口径及正常授权。

[诊断源码](fire/ballistics_quality_consumer.gd) / [完整三例数据](fire/ballistics_quality_consumer.json) / [log](fire/ballistics_quality_consumer.log)。

### R2 [P2] 原重投已好，owner拒绝的条目仍先改全局航迹与映射

原OBS-000008/observed7/q.7重投后，measurement/combat/cache均保持.90849375@21，owner observations和accepted audit仍19；另记rejected1允许。真实deception重投candidate1→1、identity evidence不变、measurement/combat .82@1不变、accepted audit1→1。正常own10→19、ally1→4/player0。这些均**CLOSED**。

残项是一次明确的错投控制：新同seed receiver合法关闭radar并到t7，初始全局TrackTable0、map空、两owner无观测；重用真实捕获项，仅将接收owner改为ally（observer仍own_ship，无共享授权）再送生产投递入口。

- owner intake及rejected audit正确报告share_not_authorized，两owner观测仍0，measurement均不可用。
- 全局TrackTable却0→1，新增T0001；sensor map从空变raider_2→T0001。
- 未声称玩家owner已得到非法measurement或正常路由自行错投。

[GameSession:2657–2680](https://github.com/HATO-24/ghost-track-apsis/blob/ea29da7138ad353c4198f76547f57c4e0b07142d/game_v17/scripts/core/game_session.gd#L2657)先标accepted=false，但:2667仍调用TrackTable并在:2674更新map，直到:2675才检查拒绝。**在这些写入前拦住owner拒绝项，或等价窄守卫即可**；不要求通用事务架构。保留现已绿的重投/候选/新观测接纳。

[真实输入及前后数据](observation/replay_audit.json) / [说明](observation/findings.md) / [log](observation/replay_audit.log)。

### R3 [P2] 原null已拒绝，部分新段仍触发非规范化转换异常

本轮公开load的完整文件full/ok=true、全EW段缺失legacy_absent/ok=true、queue=null invalid/ok=false且带field原因均通过，不再派发这三项返工。

只删除序列化中的ew_combat_quality，其余新段保留，公开load会在[game_session.gd:2925](https://github.com/HATO-24/ghost-track-apsis/blob/ea29da7138ad353c4198f76547f57c4e0b07142d/game_v17/scripts/core/game_session.gd#L2925)触发SCRIPT ERROR Invalid cast: could not convert value to Dictionary。load最终确实ok=false，**不是又一次静默成功**；但ew_restore_mode仍absent，错误只有“EW状态恢复失败： field=”，缺规范化原因/字段。

新校验对dict只在has时查类型，之后无缺省地get并cast/duplicate。**按现有字段的必需/可选合同明确验证缺失或采用有意兼容默认**，避免未处理转换异常，返回可解释的模式/字段原因。只修新增EW字段错误路径，不扩全schema fuzz、新存档体系或全局数字转换。

[诊断源码](time_restore/r3_restore_validation.gd) / [结果](time_restore/result.json) / [实际异常堆栈及全部公开返回](time_restore/r3_restore_validation.log)。

## 4. 下一次交付边界

继续原#60，只收尾R1真实Ballistics质量/误差输入、R2拒绝项写者守卫、R3部分新段规范化处理。原R4、已修重投/候选、null拒绝/有效full/全缺段兼容、W7正常10tick及接口层精度均保留，不重开。加原真实残例并保留相应正例，最终同40位变更HEAD专项+原C，七历史baseline不刷新。

本轮根命令：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip)|cic_view_probe|jc_identity_pipeline|jc_authority_intel)' -Ci -ResultsDir .test-results/sol-a03-r2/targeted
```

A1/A2/G0/K0完成不变；A04通信/B01A部署仅按原规则准备独立服务，Session整合不提前解锁。UI设计/任务文档GPT/Sol，主要代码DeepSeek。Linux/macOS、非headless渲染、真实RF/光学、>1000tick成本本轮NOT RUN。前轮及产品口径纠正见[历史](../pr70_a03_20261028/review.md)，原始字节校验见[manifest.sha256](manifest.sha256)。

