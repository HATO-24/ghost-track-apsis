# PR72 / JC-A04 第二轮独立复核

日期：2026-10-29（Asia/Shanghai）。**RETURNED：R3已关闭，只继续原R1、R2与R4。** 候选`bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72`（交付前加固版），上轮`1de99a85c4f69dca706509648450487197523ab5`，base/main仍`4e4f90f9eb4964503a61dd915cb1c445294b10a5`。A4不冻结，PR72暂缓合并，继续原#61。

## 1. 本轮验证

Windows / Godot4.7.2.stable.official.ed1daf0bf。根独立专项**8/8 PASS，新106/0，57.5s含31.6s import，退出0**；EW252/0、order137/0、CIC925/0、restore59/0、legacy60/0、event89/0、save41/0。[report](targeted/report.md) / [summary](targeted/summary.json)。

[同head CI run40728509817](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40728509817)在归档快照中Phase0、PhaseA SUCCESS，**full仍IN_PROGRESS**；[checks](ci/checks.json)。不把交付报告自报91=84/7替代本轮CI完成状态。上轮1de99a85的CI完整91=84/7已归档，但不是本轮结果。根本轮未重复完整C，实际剩余反例仍阻止放行；最终修复HEAD须专项+原C。

三次有界诊断运行均exit0（transport一次、原两个恢复脚本各一次），exit0表示记录完成而非A04已通过。根未改生产、正式probe、matrix、baseline或退出码包装；导入元数据不交付。baseline SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4` 未刷新。耗时不是规模/性能验收。[机器记录](verification.json) / [原始字节校验](manifest.sha256)。

## 2. R3关闭：保留本轮修复，不再派发

| 原入口 | 本轮实际结果 |
| --- | --- |
| Comms v2直接恢复 | 保存seed123/seq1，load后仍123/1；下一draw同为.285678160509876 |
| queue_intel_share无send日志的真实文件 | 真正user://写/读、fresh公开load；send_comms log count0，连续与恢复均seed0/seq1，下一draw均.30996977738569 |
| comms_ew_seed配置 | 非默认123已实际保留，normalize allowlist已接入 |
| v1恢复模式 | 新源码实际返回migrated_v1，不再只在报告中声称 |

原缺口是计算了new RNG但没赋回；现在实际状态已提交，真实文件无重放补齐的场景也一致。**原R3整组CLOSED，不重做RNG/配置/真实文件修复。** 已补的冻结字段一致性、时延和sent/arrive校验保留。null和version99继续明确拒绝且服务导出state不变。

[恢复结果](time_restore/result.json) / [服务级源码](time_restore/comms_state_edges.gd) / [日志](time_restore/comms_state_edges.log)；[公开Session真实文件源码](time_restore/queue_share_file_rng.gd) / [日志](time_restore/queue_share_file_rng.log)。两个原脚本各重跑一次；不重跑此前已好的10tick/W7或扩大schema fuzz。

## 3. 已关闭链路保留

三入口共用Comms、OrderService唯一推进、同一批真实DELIVERED/FAILED回调，失败订单精确due后拒绝执行、合法fresh共享t22融合0→1且只一次，仍保持关闭。本轮diff没有改变这些消费者，复用[上轮真实callback证据](../pr72_a04_20261029/review.md)，不重复跑或要求重做。

正常jam=.5仍额外20s/.4；即使发送后EW提前expire，原消息仍按冻结结果t22 FAILED。own/player与ally/ally合法上下文、ghost拒绝正例继续通过。v1及原no_route失败重放保留。

## 4. 只剩原三组

### R1 [P2] 已登记身份与调用上下文未校验

同原诊断重跑：ally/player、enemy/player、own/opfor错配仍被接受并真实送达；enemy→own订单带player上下文仍QUEUED。合法own/player、ally/ally也成功，ghost才unknown_from。没有调用授权/开始执行，**不声称自动执行或授火权**。

仍按原卡校验实际sender与actor/controller/fleet/owner，覆盖三入口；保留正常友军独立上下文和旧seed兼容，不把已知节点当作授权，也不扩B2 AI策略。[精确输入/事件](transport/transport_audit.json) / [本轮摘要](transport/summary.json)。

### R2 [P2] 普通发送仍能使用ignore_ew旁路

普通send opts.ignore_ew=true仍将active jam下22s/.4的消息变为2s/0并实际DELIVERED；正常draw.1消息仍t22 FAILED。[Comms:606](https://github.com/HATO-24/ghost-track-apsis/blob/bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72/game_v17/scripts/core/comms_service.gd#L606)仍直接信任此普通opts。

将忽略EW限制在已验证的v1内部迁移/重放；普通发送不得请求旁路。保留v1兼容，不删除迁移能力，不新增玩家流程。这里证明的是普通API旁路，不声称已经存在玩家UI按钮。[说明](transport/findings.md) / [诊断源码](transport/transport_audit.gd) / [日志](transport/transport_audit.log)。

### R4 [P2] 缺失冻结块/非整数版本仍接受，正式共享成功正例仍需断言

新增单字段篡改一致性校验保留，不重新派发。仅剩：

1. v2真实在途项原will_fail=true；删除pending.ew仍ok/full，到期DELIVERED，失败变成功。[Comms:903](https://github.com/HATO-24/ghost-track-apsis/blob/bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72/game_v17/scripts/core/comms_service.gd#L903)仍先以rec.has(ew)包住整段验证。真正v1兼容不能让损坏v2静默跳过。
2. state version2.5仍被int截为2并接受；[版本入口:859](https://github.com/HATO-24/ghost-track-apsis/blob/bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72/game_v17/scripts/core/comms_service.gd#L859)。先严格确认合法版本再转换/提交，拒绝时不改变该状态。null/version99拒绝不变状态的正例保留。
3. 正式S3仍以player_ctrl作share_authorized_by，最新根日志obs为0→0；只INFO、无成功融合断言。用既有合法owner player_intel和fresh row断言到达前不可见、到达后0→1、后续/重复不增，保留失败不融合。**实际生产成功融合已关闭，仅补正式验收，不重写其实现。**

[本轮恢复反例及正例](time_restore/result.json) / [正式106日志](targeted/logs/integration.jc_ew_comms.log)。S8/S9缩进在_info内，但_run的S3末尾确实调用一次，日志显示两段实际执行并106/0；放置不佳不作新缺陷，不把它说成未运行或虚报。

## 5. 下一步

只继续原#61的R1/R2/R4，R3与上表关闭项不重派。最终同40位修复HEAD专项+原C，七历史baseline和旧注册ID不动。PR72暂缓合并、A4未冻结，B01A最终集成仍等A4。A1/A2/A3/G0/K0结论不变；低质量仍能射击不作自动禁射缺陷。UI设计文档GPT/Sol，主要代码/返修DeepSeek。

comms_spoof仍需区分effect查询层与未验证的真实消息接入，不扩新欺骗协议。Linux/macOS、非headless、真实RF/光学、>1000tick成本NOT RUN。上轮历史与证据见[首轮](../pr72_a04_20261029/review.md)。
