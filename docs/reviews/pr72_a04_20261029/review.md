# PR72 / JC-A04 首轮独立复核

日期：2026-10-29（Asia/Shanghai）。**RETURNED，继续原 #61；PR72暂缓合并，A4未冻结。** 保留已接好的三发送入口、唯一推进、真实失败回调、失败订单不执行及合法共享只融合一次；只收尾普通发送边界、确定性状态恢复/严格校验及相应正式反例。不新增AI/UI/RF或重新打开A3。

## 1. 版本与运行证据

HEAD `1de99a85c4f69dca706509648450487197523ab5`，base/main `4e4f90f9eb4964503a61dd915cb1c445294b10a5`，Windows / Godot 4.7.2.stable.official.ed1daf0bf。根独立专项 **8/8 PASS、79/0，62.9s含33.4s import，退出0**；order137/0、EW252/0、CIC925/0、comms restore59/0、legacy60/0、event89/0、save41/0。[report](targeted/report.md) / [summary](targeted/summary.json)。

[CI run40726415498](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40726415498)三个job SUCCESS；full实际checkout合成merge `dd292794e42c0da4a5005ac0d10f1524c63c6fa2`，**91=84PASS/7历史FAIL、new_fail0、drift0、unverified0、unselected0、complete=true、FULL_MATRIX_EXIT=0**，346.1s。[原始日志](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。本轮根未重复完整C；已确认的实际入口反例仍阻止放行。最终修复HEAD仍须同40位HEAD专项+原C。

根只写`.test-results`诊断及根docs，未改生产、正式probe、matrix、baseline或退出码包装。诊断exit0代表结果成功记录，不代表A04通过；原日志保留teardown提示。七项baseline SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4` 未刷新。耗时仅为本次记录，不当作规模/性能验收。[机器记录](verification.json) / [字节校验](manifest.sha256)。

## 2. 已关闭的实现：保留，不返工

| 合同 | 本轮真实证据 | 处置 |
| --- | --- | --- |
| 三入口与唯一推进 | Session.send_comms、OrderService.issue、Session.queue_intel_share均经同一Comms；Comms只由OrderService.tick推进，并旁路同一批真实结果 | CLOSED |
| 纯jam fixture与冻结 | jam=.5→基础2s+额外20s/.4；正常draw=.1消息即使t2提前expire EW，仍t22真实FAILED/comms_jam | CLOSED |
| 失败订单不执行 | t21 TRANSMITTING；恰好t22 FAILED→REJECTED；begin_execute拒绝，complete=not_executing，再3tick无DONE/executed_t仍-1 | CLOSED |
| 合法共享成功只一次 | 新鲜观测、正确owner授权player_intel，t21接收obs0/pending1；t22真实delivered后ally obs0→1，后3tick仍1、delivered总1 | CLOSED |
| 已有兼容和拒绝正例 | v1兼容、原no_route失败重放、普通send_comms日志场景的文件续行/下一draw；pending.ew=null及version99服务级拒绝且state不变 | 保留；不扩大为所有入口都已恢复 |

[回调诊断源码](delivery/callback_diagnostic.gd) / [完整状态](delivery/callback_diagnostic.json) / [日志](delivery/callback_diagnostic.log)。这些是有界独立补证，不计入正式79断言。下面的正式成功共享夹具需修正确认断言，但**实际成功融合实现已好，不要求重做生产链**。

## 3. 继续原卡的四组收尾

### R1 [P2] 已登记sender仍可与调用方权限上下文错配

普通`send_comms`只把opts交给Comms；新链路仍主要检查节点/路由，没有校验actor/controller/fleet/owner与真实sender的归属。一条已登记的舰不是任意调用方可冒用的身份。独立同一fixture：

| sender / 调用上下文 | 实际结果 |
| --- | --- |
| own_ship / player，ally_ship / ally | 合法正例均成功并t2 DELIVERED |
| ally_ship / player | 成功并t2 DELIVERED |
| enemy_ship / player | 成功并t2 DELIVERED |
| own_ship / opfor | 成功并t2 DELIVERED |
| 未登记ghost_issuer / player | 仅此项被unknown_from拒绝 |

`issue_order('hold','enemy_ship',['own_ship'],...,player_context)`同样ok并在t2进入QUEUED。此处没有authorize/begin执行，**不声称自动执行或授开火权**。原卡明确要求合法sender/controller/fleet/owner与不冒充/跨域发令，未知ghost负例不能替代已登记身份的错配反例。

最小修复：在现有受权上下文与真实sender之间建立校验，覆盖实际消息/订单/共享入口，拒绝错配并给明确原因；保留本方、独立友军各自合法上下文与既定旧seed兼容，不把“友军”改成玩家直控或禁止正常友军通信。[入口](https://github.com/HATO-24/ghost-track-apsis/blob/1de99a85c4f69dca706509648450487197523ab5/game_v17/scripts/core/game_session.gd#L3107)；[详细输入/结果](transport/transport_audit.json) / [摘要](transport/summary.json)。

### R2 [P2] 普通消息可以使用迁移用ignore_ew逃过真实干扰

[Comms.send:599](https://github.com/HATO-24/ghost-track-apsis/blob/1de99a85c4f69dca706509648450487197523ab5/game_v17/scripts/core/comms_service.gd#L599)无条件读取普通opts.ignore_ew。真实active jam=.5时：正常消息冻结22s/.4/draw.1并t22 FAILED；同入口只加`ignore_ew=true`，变为额外0s/失败率0/ignored=true并t2 DELIVERED。

最小修复：EW忽略语义限于已验证的v1迁移/内部重放，普通发送不能把请求字段当作绕过开关；保留真实v1旧outcome兼容，不删除迁移能力或引入新玩家流程。测试用draw注入仍按原卡限制。[一次诊断与原始事件](transport/transport_audit.json) / [说明](transport/findings.md) / [源码](transport/transport_audit.gd) / [日志](transport/transport_audit.log)。未证明玩家已有UI按钮，缺陷是普通受支持发送API接受了迁移旁路。

### R3 [P2] RNG实际没有恢复，无send日志的共享文件暴露后续消息分歧

[Comms.load_state:856](https://github.com/HATO-24/ghost-track-apsis/blob/1de99a85c4f69dca706509648450487197523ab5/game_v17/scripts/core/comms_service.gd#L856)计算new_ew_seed/new_ew_seq，但提交阶段没有赋回实际成员。服务级有效v2状态保存seq1，load后仍seq0；Session层的真实文件补证如下：

1. 正常`queue_intel_share`发出C-000001，消耗EW seq1；此入口没有send_comms日志（count0）。
2. 真实写/读user://文件，以fresh公开load_state加载，返回ok。
3. 连续实例rng为`{seed:0,seq:1}`，恢复实例却为`{seed:0,seq:0}`。
4. 下一条普通send draw分别`.30996977738569`与`.928304756026857`，之后seq2与1，不一致。

正式文件绿例只用记录了send_comms的入口，重放恰好补回seq，掩盖了state自身未恢复。另`_normalize_seed`allowlist丢弃新comms_ew_seed，配置123/456实际都变0；不能按交付报告宣称此配置已经决定采样。

最小修复：有效保存的PRNG状态确实提交，初始化/配置与恢复的seed/seq语义明确；覆盖普通send与无send日志入口，不靠重放巧合或重抽样补齐。按原确定性合同保留v1兼容/原失败与下一新消息一致，不扩新存档架构。[服务级源码](time_restore/comms_state_edges.gd) / [服务结果](time_restore/result.json)；[公开Session真实文件源码](time_restore/queue_share_file_rng.gd) / [文件结果](time_restore/queue_share_file_rng.result.json) / [日志](time_restore/queue_share_file_rng.log)。

### R4 [P2] v2冻结字段删除会改写结果，版本校验与正式正例也需等强

[state验证:896](https://github.com/HATO-24/ghost-track-apsis/blob/1de99a85c4f69dca706509648450487197523ab5/game_v17/scripts/core/comms_service.gd#L896)只在pending项“有ew键”时检查。对真实冻结失败的v2在途项（draw.1/.4、will_fail=true、arrive_t22），仅删除该项ew对象，load仍ok/full，到期实际发出DELIVERED，失败变成功。state version先int转换，2.5也被当2接受。与之对照，present ew=null和version99已明确拒绝，服务状态不变，须保留这些正例。

最小修复：v2必需冻结字段缺失/无效不能静默降级到旧默认，按version先严格校验后提交，拒绝时不改变该状态；真正v1迁移继续有明确旧语义。补相应实际结果反例。[完整结果](time_restore/result.json) / [日志](time_restore/comms_state_edges.log)。这里的删除字段反例通过Comms公开state入口验证；不把它混写为已经另跑了Session整文件的同一篡改。

正式S3“成功共享”使用`share_authorized_by=player_ctrl`，但既有A01接收合同要求原observer owner `player_intel`，所以日志obs为0→0且只INFO、不assert融合。应改为合法且新鲜正例，断言到达前不可见、到达后0→1、重复/后续tick不再增加；保留失败不融合。真实生产融合已由本轮独立正例关闭，此处修验收，不重做其实现。原79绿项继续保留，新增注册ID不删旧项，七历史baseline不刷新。

## 4. 交付与范围限制

继续原#61按上面四组返修，保留已关闭链路。最终同40位修复HEAD跑原专项和C，附合法/非法sender表、普通/迁移EW边界、真实文件PRNG与v2无损坏/损坏对照。v1实际接受但服务返回mode仍full；报告不要虚称已返回migrated_v1标签。

comms_spoof目前查询层可给suspicious/requires_confirmation/auto_execute=false等字段；新采样没有接真实spoof消息。本轮未验证实际欺骗消息到达/待确认流程，交付报告应区分effect查询和真实能力，不要求本卡扩完整欺骗协议。低质量仍能射击不自动等于缺陷；A3闭环保持。A04未放行、B01A最终接入仍等A4；UI设计文档GPT/Sol，代码DeepSeek。Linux/macOS、非headless、真实RF/光学、>1000tick成本NOT RUN。
