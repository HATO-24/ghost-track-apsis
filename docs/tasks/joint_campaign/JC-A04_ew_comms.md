# JC-A04：EW进入通信链路并保持确定性恢复

执行Issue：[JC-A04 #61](https://github.com/HATO-24/ghost-track-apsis/issues/61)。

状态：READY，A1/A3前置已满足；下一张核心实现卡，交付A4。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

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
