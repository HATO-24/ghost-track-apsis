# PR72 / JC-A04 第三轮独立复核

日期：2026-10-29（Asia/Shanghai）。**RETURNED，只剩原R1的现代缺省上下文入口。R2/R4已全部关闭，R3继续关闭。** PR72暂缓合并，A4未冻结；不重做已关闭通信、恢复或真实回调，不扩AI/UI/RF/禁射。

## 1. 版本与验证

HEAD `563e97a61bc00d31104ad6db969edfe87f2fc25f`，前轮bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72，base/main仍`4e4f90f9eb4964503a61dd915cb1c445294b10a5`。Windows / Godot4.7.2.stable.official.ed1daf0bf。根独立专项 **8/8 PASS、新131/0、61.3s含30.7s import、退出0**；EW252/0、order137/0、CIC925/0、restore59/0、legacy60/0、event89/0、save41/0。[report](targeted/report.md) / [summary](targeted/summary.json)。

[CI run40738920608](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40738920608)三个job SUCCESS；full checkout为合成merge`8f20c95a7687157d9bdb5299d57066c3bf443d44`，**91=84PASS/7历史FAIL、new_fail0、drift0、unverified0、unselected0、complete=true、FULL_MATRIX_EXIT=0**，368.2s。[原始CI](ci/full.log) / [关键行](ci/full-relevant.txt) / [checks](ci/checks.json)。根本轮未重复完整C；一个实际入口反例仍阻止放行。最终修复HEAD仍须原专项+原C。

根只写诊断及根docs，未改生产、正式probe、matrix、baseline或退出码包装。三项有界诊断均exit0，表示记录/窄断言完成，不等于A04验收通过；teardown提示保留在原日志。baseline SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`未刷新，本机.import/.uid不交付，耗时不当性能预算。[机器记录](verification.json) / [字节校验](manifest.sha256)。

## 2. 本轮关闭表：保留，不返工

| 原组 | 已验证事实 | 处置 |
| --- | --- | --- |
| R1显式错配 | ally/player、enemy/player、own/opfor三错配均sender_context_mismatch；原enemy/player订单拒绝且无order_id；own/player、ally/ally各正常送达 | 显式上下文子项CLOSED |
| R2普通旁路 | 普通Session.send_comms(opts.ignore_ew=true)返回ew_bypass_forbidden，pending=0 | CLOSED |
| R2 v1重放 | 受jam的v2 live发送22s；构造v1 outcome/state恢复后，真实replay row为legacy/matched、divergence=[]、latency2s，内部迁移保留旧语义 | CLOSED；这是重放对照，不扩大声称另跑全legacy在途续存 |
| R4 state严格拒绝 | v2缺pending.ew→invalid_state/pending.ew，version2.5→invalid_version，服务导出状态均不变；合法v2、v1无EW migrated_v1、null/99控制保留 | CLOSED |
| R4正式成功共享 | 正式S3改成合法observer owner授权和fresh row，精确due前0、due后0→1、后5tick仍1，真实delivered；失败共享仍不融合 | CLOSED，实际生产融合此前已好 |
| R3及原链路 | RNG实际恢复/seed配置/无send日志共享真实文件、三入口/唯一推进/真实回调、失败订单拒执行、合法共享只一次 | 保持CLOSED，不重测/重做 |

[R1完整结果](authority/authority_audit.json) / [摘要](authority/summary.json)；[R2源码](legacy_boundary/r2_legacy_boundary.gd) / [结果](legacy_boundary/results.json) / [日志](legacy_boundary/r2_legacy_boundary.log.txt)；[R4结果](time_restore/result.json) / [正式131日志](targeted/logs/integration.jc_ew_comms.log)。

## 3. 仅剩原R1 [P2]：现代新发送缺ctx，被提前标成legacy

[GameSession._authorize_comms_sender:3270](https://github.com/HATO-24/ghost-track-apsis/blob/563e97a61bc00d31104ad6db969edfe87f2fc25f/game_v17/scripts/core/game_session.gd#L3270)仅因opts没有六个ctx字段就返回ok/legacy=true，尚未核对当前seed已有的现代command_domains/fleet_instances/own_entity归属。**缺调用字段不等于正在加载旧档。**

同一显式现代authority seed、真实新发送、没有load/replay：

| 调用 | 实际结果 |
| --- | --- |
| ally_ship＋显式player上下文 | 正确拒绝sender_context_mismatch |
| enemy_ship＋显式player上下文 | 正确拒绝sender_context_mismatch |
| own_ship＋显式opfor上下文 | 正确拒绝sender_context_mismatch |
| **ally_ship＋opts={}** | **ok，C-000002，t2真实DELIVERED** |
| **enemy_ship＋省略opts** | **ok，C-000003，t2真实DELIVERED** |
| 现代own默认、真正旧seed own默认 | 正常，保留为兼容正例 |

这是原sender边界的缺省分支，未增加新的AI/认证体系要求；仅证明消息被接受/送达，**不声称自动执行、授开火权或身份改变**。显式三错配及其订单原反例已经修好，不再派发。

最小收尾：现代会话缺ctx时应从可信本方锚点解析合法上下文，或明确拒绝需要权限却缺失的请求；不能仅凭调用者省略字段就降为旧版兼容。区分真正旧seed/已验证旧日志迁移与现代新发送，保留现代本方默认、独立友军显式合法上下文、真正旧seed/旧档和v1内部迁移。不要把“无ctx全放行”换成“所有旧调用全禁用”，不扩完整B2任务策略。

按同一现代seed测试省略opts/空opts与显式错配、合法own/ally、真正旧seed；覆盖同一普通API及共享/订单实际接线，给出拒绝原因和不创建投递/订单的证据。无需重做R2/R3/R4、真实回调或其已过正例。[原始输入与实际事件](authority/authority_audit.json) / [说明](authority/findings.md) / [源码](authority/authority_audit.gd) / [运行信息](authority/run.json) / [日志](authority/authority_audit.log)。一次运行exit0，3.17s。

## 4. 交付边界

只继续原#61这一处，最终同40位修复HEAD专项+原C，七历史baseline及原注册ID不动。PR72暂缓合并、A4不冻结；B01A仅已有只读交接准备，最终接入仍等A4。A1/A2/A3/G0/K0不变；低质量仍能射击不作自动禁射缺陷。任务/UI设计文档GPT/Sol，主要代码/返修DeepSeek。

Linux/macOS、非headless、真实RF/光学、>1000tick成本NOT RUN。既有spoof查询层与实际消息能力的限制保持。前轮历史：[首轮](../pr72_a04_20261029/review.md)、[第二轮](../pr72_a04_r2_20261029/review.md)。
