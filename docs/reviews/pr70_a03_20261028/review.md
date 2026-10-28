# PR70 / JC-A03 首轮独立复核

日期：2026-10-28（Asia/Shanghai）。**RETURNED，继续原#60，A3不冻结，PR70暂缓合并。** 已接通的真实EW采样、正常owner路由、延迟投递及有效文件10tick继续保留；只收尾下面四组，不重做整项EW。

## 1. 被审版本与运行

HEAD `6bd919aa19898bbf31f5dd7c3287befc47392877`，base/main `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。

根代理独立专项运行 **11个执行行均PASS**，58.9s含23.5s import，退出0：新EW47/0、combat255/0、EW252/0、sensor128/0、track161/0、CIC925/0、A1 90/0、sensor persistence86/0、authority65/0、save41/0，另A2脚本122/0实际执行但**注册ID丢失，报告为匿名行**（见R4）。[report](targeted/report.md) / [summary](targeted/summary.json)。不把这称为11个命名注册项都正常。

[CI run40667024336](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40667024336)关联同head；实际checkout合成merge `438b6f1a2a9a126a921c937057f572c2b154a2fb`（6bd919a合入3845852）。三个job success；主矩阵 **90=83PASS/7历史FAIL、new_fail0、drift0、complete=true、FULL_MATRIX_EXIT=0**，255.7s。[原始日志](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。根本轮未再跑本地完整90项；真实反例仍阻止放行。

全部诊断仅写新的.test-results取证目录，没有修改生产、正式probe、matrix、baseline或测试包装。导入产生.import/.uid保留且不交付。诊断exit0表示取证完成，不能代替验收；fixture退出资源清理提示保留在原始日志。

## 2. 保留已通过工作

| 实际对照 | 结果 |
|---|---|
| 正常EW采样及延迟 | 真实apply_ew→Sensor→采样；首次raw1按noise=.5变.7、delay3，EW=0为1/0且即时到达；后续raw变化保留原值乘数，不硬定每次都.7 |
| owner/抽象作用域 | own_ship仅进player，ally_ship仅进ally；物理存在但未登记observer不回退player；错误target及optical target_kinds对radar均不降质、不延迟 |
| 当前质量与历史max | 先clean后jam，aggregate仍1，current=.48825（实际raw .6975×.7），没有以历史max替代当前 |
| 正常真实文件恢复 | 自然在途OBS-000001，observed1/arrive4，t3未到、t4按ETA到达，保存前后队列均1；源/恢复t3..12完整队列、捕获观测/几何、样本、投递ID/双时间、owner质量及实际解算行10/10语义相等 |
| 缺新段旧档 | 删除七个A03新字段的真实文件仍可加载并继续，按兼容合同给空EW新段 |

[观测分项](observation/findings.md) / [数据](observation/observation_audit.json)；[时间/文件继续说明](time_restore/findings.md) / [原始数据](time_restore/result.json) / [离线比较](time_restore/comparison.json)。JSON的2与2.0导致GDScript严格相等标志不同，但数值1e-9、其余字符串/布尔/顺序/键精确比较为0语义差异，**不是恢复失败，不要求全局强转整数**。

时间对照实际启动SOL-000001（t4，ready_t19），t12结束仍COMPUTING，证明这段在途解算继续相同；没有冒称完成帧或命中。上述服务和恢复绿项不再派发实现重做。

## 3. 四组原卡收尾

### R1 [P1] 已有解算绕过后来降质，实际发射；中等精度因子未消费

合法触发：真实tick获得q1→合法本舰FIRE授权→实际apply_ew(noise severity1)→创建解算→真实延迟观测到达q=.279→重试新解算→实际request_fire。

| 对照 | 结果 |
|---|---|
| 新建/重试解算 | 正确返回insufficient_quality |
| HUD形状T0001，降质到达时旧解算已READY | 旧解算仍能request_fire ok=true、launched=1 |
| 实体键raider_2同路径 | 同样实际发射 |
| T0001晚2tick创建，降质到达时仍COMPUTING | 旧解算继续变READY，仍实际发射 |
| 资源/弹道 | 三例各ammo8→7，PRJ-00001处于FLIGHT；launch时hit=false，不声称命中 |

旧解算捕获measurement_quality=1，quality=.88125/error=.59375，当前航迹实际q已.279。Session在射击边界已投影新质量，但[CombatService.request_fire:576](https://github.com/HATO-24/ghost-track-apsis/blob/6bd919aa19898bbf31f5dd7c3287befc47392877/game_v17/scripts/core/combat_service.gd#L576)只找READY解算；[tick:787](https://github.com/HATO-24/ghost-track-apsis/blob/6bd919aa19898bbf31f5dd7c3287befc47392877/game_v17/scripts/core/combat_service.gd#L787)推进也不按当前质量拒绝/降级。新门只在request_solution创建/请求时生效。

补充持续moderate对照：noise=.2/duration60，创建q=.6138，READY时owner及combat当前q仍.7994745；combat range固定500，最终quality=.88125/error=.59375，与创建q1的clean对照相同。冻结writer-reader §4承诺中等q精度×.85，相应quality应为.7490625；常量QUALITY_ACC_MULT定义后未被实际解算/预测消费。clean对照READY时自身本底质量也已变化，不能把它说成该时刻q1；这里比较的是同range的实际输出及持续moderate条件，不将不同物理距离的弹道误差混作严格对照。

**收尾**：让COMPUTING/READY/实际射击都按已冻结当前质量规则失效、重算或降级；q低于门槛不能靠旧解算发射。接入已承诺中等质量精度/误差消费，保留正常高质量、恢复、实体键/真实HUD键和旧字段兼容。补实际生命周期反例，不能只断新solution_s或一个同步字段。

[四例完整数据](fire/results.json) / [实际调用脚本](fire/fire_quality_lifecycle.gd) / [原始log](fire/run.log) / [持续moderate数据](fire/moderate_quality_ready.json)。

### R2 [P2] 底层已拒绝重投，新measurement仍被旧观测覆盖

从真实队列捕获OBS-000008（observed7/q.7），先正常投递、正常expire EW并恢复；t21 current=.90849375@21。随后**一次明确消息重投**该原始快照至生产投递边界：

- owner观测数19→19，底层已去重；TrackTable明确duplicate_event。
- 新measurement却变成.7@7、degraded=true，投递审计19→20，回滚已恢复质量。
- 正常未干预阶段10个投递/10个唯一ID；不声称自然运行已自行重复。

[game_session.gd:2640](https://github.com/HATO-24/ghost-track-apsis/blob/6bd919aa19898bbf31f5dd7c3287befc47392877/game_v17/scripts/core/game_session.gd#L2640)丢弃owner receive返回，随后即使TrackTable拒绝仍在2659写measurement/combat/candidate副作用。**接纳/幂等必须覆盖整个新增消费者边界**，不能仅依靠底层历史去重；明确正常新观测与合法共享的接纳规则，不靠忽略所有新观测变绿。

[重投原始输入/前后数据](observation/replay_audit.json) / [log](observation/replay_audit.log) / [分项说明](observation/findings.md)。

### R3 [P2] 损坏的新EW队列静默清空且加载成功

根代理用真实API建立在途队列1项，真实save_state为有效正例；完整文件load恢复队列仍1。只把已存在的ew_observation_queue改为null、写实际user://文件再读回：load返回ok=true/errors=[]，队列却1→0，已有恢复维度仍报告full，无EW损坏说明。与真正缺少七个新字段的旧档兼容正例必须区分。

[恢复器:2833](https://github.com/HATO-24/ghost-track-apsis/blob/6bd919aa19898bbf31f5dd7c3287befc47392877/game_v17/scripts/core/game_session.gd#L2833)把present-invalid与absent都默认空数组。**只补新增EW状态的类型/必要值校验与可解释拒绝**，不把损坏新段冒充旧档/完整恢复；保留有效新档10tick继续与真正缺段兼容，不重写整个save/load。

[根诊断](save_contract/diag.gd) / [完整load返回](save_contract/result.json) / [stdout](save_contract/run.log) / [stderr](save_contract/run.stderr.log)。

### R4 [P2] 插入EW case时删掉A02注册ID，并补合同对应的验收

probe_matrix.json:797新增EW case后，:809原A02对象已无id（script仍存在）。因此本轮匿名行122/0确实运行，但原命令：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '^integration\.jc_identity_pipeline$' -List
```

实际选择0项，旧注册名及日志定位失效。**恢复原integration.jc_identity_pipeline，保留新EW唯一ID，预期总数仍90**；不删旧case、不刷新baseline，不要求借机重构整个runner。

正式W4只查新建解算/耗时/低q拒绝，未挡R1旧解算实际发射；W7仅可见ID/质量及末尾数量/ID，不比较完整队列/捕获几何或实际解算（标题却称解算继续）。按原卡补等强真实消费者与文件继续比较，复用已证明正常实现，不用更多自报truth_regenerated=false字段代替真实捕获值。

[注册表审计](matrix/result.json) / [按原ID选择0项的输出](matrix/a02-id-list.log)。原baseline blob与main相同。

## 4. 抽象模型及证据边界

已证明的是observer归属拒绝和target/target_kinds排除。当前effect查询只有target/sensor_kind，没有独立接收方或接收频段上下文；band=X/S只是标签，均产生.7/3s。没有已知接收机band的合法错频夹具，**不把它判成测得的X/S穿透，也不把原错observer/频段排除笼统标绿**。返修交付须明确本抽象模型支持的作用域/类别负例与未支持范围；不临时新增真实RF或完整接收机模型。

极小到期诊断：t_end=1，sampled_t=observed_t=1时仍取EW step前active值.7/3s，随后EW一步到t1并inactive，step_count=1。按候选声明的先采后步记录相位；没有观察到已标inactive仍被使用，也未生成严格晚于t_end的下一条观测。本轮不另立到期bug或强制双step。[边界数据](time_restore/expiry.json)。comparison.json中的expiry未测标志只描述首次10tick夹具，补充以独立expiry文件为准。

Linux/macOS、非headless渲染、真实RF/光学传播、>1000tick成本本轮NOT RUN。A1/A2/G0/K0完成结论不变；A04通信及B01A部署按原独立服务规则准备，核心Session接入仍等待A3，不提前推进整合。

## 5. 下一次交付

只继续原#60四组：实际火控生命周期/精度、全投递副作用幂等、新EW损坏段拒绝、旧ID及等强验收。先保留红例，再小改生产接线，关闭项逐项对照。最终同40位HEAD专项+原C，七历史失败不刷新；正常采样/owner/延迟/有效文件继续不返工。UI任务/文档GPT/Sol，主要代码DeepSeek。

实际根专项命令：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip)|cic_view_probe|jc_identity_pipeline|jc_authority_intel)' -Ci -ResultsDir .test-results/sol-a03/targeted
```

根额外save_contract一次、观测两次（首轮重投跳过，次轮真实重投有效）、时间两次、火控两次（四例+持续moderate），均为有界取证，不算新增正式probe。所有原始脚本与数据随本报告归档；完整性见[manifest.sha256](manifest.sha256)。

