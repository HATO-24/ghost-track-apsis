# JC-A04：EW进入通信链路并保持确定性恢复

执行Issue：[JC-A04 #61](https://github.com/HATO-24/ghost-track-apsis/issues/61)。

状态：RETURNED，第三轮仅剩R1现代缺省上下文入口；R2/R3/R4关闭，A4未冻结。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 2026-10-29 PR72第三轮：R2/R4关闭，仅现代缺省发送一处

被审`563e97a61bc00d31104ad6db969edfe87f2fc25f`，[本轮关闭表与原始证据](../../reviews/pr72_a04_r3_20261029/review.md)。根8/8专项、新131/0、退出0；同head CI三个job成功，full91=84PASS/7历史FAIL、new_fail0/drift0/complete=true、退出0。

**不再返工**：R1显式ally/player、enemy/player、own/opfor三错配与原非法订单已拒绝；R2普通ignore_ew拒绝且无pending，v1内部重放保持2s旧语义；R4缺pending.ew/version2.5拒绝不改服务状态，正式合法fresh共享精确due 0→1/后续不增；R3 RNG/seed/真实文件及所有已过callback继续关闭。

仅原R1缺省分支：同一现代command_domains/fleet_instances seed下，ally_ship+opts{}、enemy_ship+省略opts仍成功并t2投递；没有load/replay。_authorize_comms_sender只凭缺ctx提前legacy放行。现代新发送应从可信本方锚点解析合法上下文或明确拒绝缺少所需上下文，不能因省略字段降为旧兼容。保留现代own默认、独立ally显式合法上下文、真正旧seed/已验证旧日志及v1迁移，不扩B2或全禁旧调用。

补此入口的实际对照，最终同40位修复HEAD专项+原C；已关闭R1子项/R2/R3/R4与实际链路不重派，七历史baseline和旧ID不动。PR72暂缓合并、A4未冻结，B01A仍等A4。下面前两轮为历史，以最新关闭表为准；代码DeepSeek，任务/UI设计文档GPT/Sol。

## 2026-10-29 PR72第二轮：关闭RNG恢复，仅三组原残项

被审`bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72`（交付前加固版），[本轮关闭表与独立证据](../../reviews/pr72_a04_r2_20261029/review.md)。根8/8专项、新106/0、退出0；同head CI后续回读三个job成功、full91=84PASS/7历史FAIL、new_fail0/drift0/complete=true；独立实际残例仍阻止放行。

**R3整组CLOSED，不再返工**：v2实际提交RNG，seed123/seq1恢复与下一draw一致；queue_intel_share无send日志的真实文件fresh load后seq1、下一draw.3099697774一致；配置seed已保留、v1实际migrated_v1。三入口/唯一推进/真实回调、失败订单不执行、合法fresh共享精确due只融合一次，以及已补的冻结字段/时延一致性校验全部保留。

仅继续原三组：

1. **R1**：已登记ally/player、enemy/player、own/opfor错配仍送达，enemy→own订单带player上下文仍QUEUED。校验sender对应actor/controller/fleet/owner，保留own/player、ally/ally与旧seed；不夸大自动执行、不扩B2策略。
2. **R2**：普通ignore_ew仍把22s/.4改为2s/0成功；限制到已验证v1内部迁移/重放，保留旧outcome兼容。
3. **R4剩余**：删除v2 pending.ew仍ok并将原失败改DELIVERED；version2.5仍接受。区分真正v1与损坏v2，严格版本拒绝不改该状态。正式success share改正确owner授权/fresh row并断言obs0→1与后续不增，实际生产融合已关闭，仅补验收。保留null/version99拒绝及已补单字段一致性校验。

新S8/S9确实执行、正式106/0，不因它放在_info内另派缺陷。最终同40位修复HEAD专项+原C；七历史baseline和旧ID不刷新/删除。PR72暂缓合并、A4不冻结，继续原#61。下方首轮为历史，以本轮关闭表为准，R3不重派。代码DeepSeek，任务/UI设计文档GPT/Sol。

## 2026-10-29 PR72首轮：保留真实链路，只补发送边界与恢复

被审`1de99a85c4f69dca706509648450487197523ab5`，base/main`4e4f90f9eb4964503a61dd915cb1c445294b10a5`。[独立关闭表与原始证据](../../reviews/pr72_a04_20261029/review.md)。根8/8专项PASS、新probe79/0；同head合成merge CI full91=84PASS/7历史FAIL、new_fail0、drift0、complete=true。仍有真实API/文件反例，PR72暂缓合并、A4不冻结。

**已关闭、不返工**：三入口共用Comms与唯一推进；纯jam=.5额外20s/.4及发送后effect消失不改冻结结果；真实失败回调；失败订单精确due后拒绝执行；合法新鲜共享精确due融合0→1且后续只一次；现有v1兼容、原no_route失败重放、null/未知版本的服务级拒绝正例。

仅继续原卡四组：

1. **R1 sender权限上下文**：已登记ally/player、enemy/player、own/opfor错配都accepted并实际送达，enemy发出的player上下文订单进QUEUED。校验真实sender与actor/controller/fleet/owner，不仅拒绝未知ghost；保留own/player、ally/ally与旧seed正例。不声称已自动执行或授开火权，不扩B2策略。
2. **R2 迁移开关边界**：普通send opts.ignore_ew=true可将active jam的22s/.4失败消息变2s/0成功。限于已验证v1内部迁移/重放，普通请求不能绕过；保留旧outcome兼容。
3. **R3 RNG实际恢复**：Comms.load_state计算新seed/seq未提交；queue_intel_share无send日志的真实文件保存seq1、load后seq0，下一draw .3099697774/.9283047560不一致；配置comms_ew_seed也被normalize丢弃。修实际状态提交/初始化与配置保留，覆盖不同入口，不靠send日志重放巧合通过。
4. **R4 v2严格校验及正式正例**：删真实pending.ew仍ok/full，把冻结失败改DELIVERED；state version2.5也接受。区分真正v1与损坏v2，拒绝不改该状态。保留null/version99拒绝；正式success share改合法owner授权与fresh row，明确obs0→1/后续不增，不能只INFO 0→0。实际生产成功融合已关闭，只补验收。

最终同40位修复HEAD专项+原C，原79绿项/注册ID保留，七历史baseline不刷新。交付报告须区分effect层spoof查询与未接真实消息，不虚称migrated_v1模式。下面A3开工交接与原八段合同保持，不新增AI/UI/RF/禁射范围。代码及返修DeepSeek，任务/UI设计文档GPT/Sol。

## 2026-10-28 A3放行后的开工交接

A3冻结 `5d372ea2df7c49badeea3846c16b839b1f6faef1`，PR70已审合入main `c3fca1c52a4158f374661f1906b32103dab5360c`，完整tree `25c0fc001934a09371e61ccf3d5d484374d9683d` 与被审候选一致。A1=`845584733df619feb3e372e8c06a7caa9f3fdaba`，G0/K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。[A3独立放行](../../reviews/pr70_a03_r4_20261028/review.md)。先fetch最新main、确认包含上述A3合入提交，记录实际40位执行HEAD；已有服务分支须合入最终A3再接Session，不能用旧A1/C55覆盖A2/A3的owner、质量、幂等或恢复改动。

当前真实发送入口有三条：`GameSession.send_comms`、`OrderService.issue`、`GameSession.queue_intel_share`均会调用`Comms.send`。EW采样与结果冻结须覆盖三条，不只接Session包装。保持现有`OrderService.tick`对Comms的唯一推进，避免另加一次Session推进造成重复投递。

`Comms.tick`已有DELIVERED/FAILED结果，订单消费两者；`GameSession._reconcile_standalone`目前用pending消失推断送达。接入EW失败后须按实际结果分发回调，失败订单不执行、失败共享不融合、不发布假delivered；保留成功只消费一次、合法sender/controller/fleet/owner及原失败原因。此为原卡实际投递/失败合同的接线说明，不扩AI/UI。

固定fixture仍为comms_jam=.5→额外20s、failure_chance=.4，draw=.1失败/.9成功；是抽象测试合同，不冒充真实RF统计。先以三条真实入口的EW开/关/固定draw保存红例，再接发送冻结、outcome版本和真实文件继续。主要代码DeepSeek；GPT/Sol维护卡与UI设计，核心A04→B01A串行。

## 1. 目标与缺口

C55已有真实Comms投递和版本化outcome恢复，但EW通信effect未被消费。让干扰影响实际到达/失败，且读档不能重新抽样改变结果，为B2友军协同提供可信的通信基础。

## 2. 基线与范围

服务开发的A1/K0依据保留；最终接入基于顶部已放行A3及其main合入提交。记录实际40位执行HEAD、服务开发基线与合并差异，按A03→A04的Session顺序集成。范围为EW链路适配、确定性随机、消息/结果版本与恢复；不开发AI任务/目标系统或新通信UI，不重写A03观测队列。

## 3. 写者、时间与安全边界

Comms写路由/在途消息/投递状态，EW提供发送时刻链路effect；冻结采样时点并记录本次实际使用值。纯comms jam=0.5的当前fixture预期extra_latency=20s、failure_chance=0.4；与正常路由基础时延分列。伪随机种子/状态/抽样顺序可保存、可重放；测试注入draw=0.1/0.9分别失败/成功，注入依赖限测试，不成为玩家任意选结果的公开选项。

所有消息带合法sender/controller/fleet/owner，不能冒充友军或跨域发令。通信欺骗只能形成不可信消息/待确认请求，不直接执行命令/授开火权/改身份。模拟发送/到达时间为秒；未来协同请求须沿同一实际投递语义。

## 4. 实施与提交拆分

1. 先写EW开/关未影响实际Comms的红例和固定抽样fixture。
2. 接发送时effect与确定性抽样，保留no_route等原失败原因；不要每个tick或读档时重新抽样。
3. 明确outcome所需EW字段/版本。新增版本须提供严格校验与既有v1迁移；缺outcome的旧日志才标legacy_unverified，未知版本仍拒绝。保存发送上下文、sent_t/arrive_t、path、latency、outcome及必要PRNG态。
4. 独立提交服务、版本/重放、Session接线、证据；同一消息成功投递只一次，due边界规则清楚，恢复不重发历史成功事件；独立消息按实际DELIVERED/FAILED回调，pending消失不能代替成功结果。

## 5. 验收

固定seed重复得到相同结果；EW=0保持旧路由；干扰增强带来规定delay/failure；draw两边界、无路由、无效sender、伪造友军、过期链路均有明确原因。真假请求都不得绕过A01；不要求本卡做B2的任务接受策略。

即时/在途、到达前一tick/恰好到达tick、原发送失败、重放、重复投递、篡改EW/outcome版本/字段逐项测。真实文件恢复再继续至少10tick，原失败仍失败、成功只交付一次、PRNG与后续新消息一致。旧seed/旧outcome支持、未知version拒绝且不变状态；不能降级成旧档来跳过验证。

## 6. 命令与证据

注册`integration.jc_ew_comms`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_comms|order_comms_probe|ew_probe|a0_(comms_restore|event_continuity|legacy_save|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_comms|order_comms_probe|ew_probe|a0_(comms_restore|event_continuity|legacy_save|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A04/targeted
```

加C回归；日志输出固定fixture抽样/结果、发送与到达时刻、实际route/outcome、owner、恢复前后投递与PRNG比较、断言/退出码及同提交CI。不要将测试seed的成功率当真实RF统计。

## 7. 旧失败

重点保留R04未知outcome拒绝与原失败重放证据；旧7项full失败绿化/漂移逐项解释，不自动刷新baseline，不以移除失败消息掩盖恢复问题。

## 8. 交付与复核

A4提供effect→Comms→实际投递/失败完整证据、版本迁移/恢复表、受权上下文与未支持欺骗能力。独立审查用读档改变抽样、伪造sender和未来版本三种方式挑战。Session最终提交须包含A3，不能覆盖其时序/保存改动。
