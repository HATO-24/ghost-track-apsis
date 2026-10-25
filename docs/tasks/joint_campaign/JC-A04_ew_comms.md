# JC-A04：EW进入通信链路并保持确定性恢复

执行Issue：[JC-A04 #61](https://github.com/HATO-24/ghost-track-apsis/issues/61)。

状态：服务可在A1后开发，Session集成WAIT A3；交付A4。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 1. 目标与缺口

C55已有真实Comms投递和版本化outcome恢复，但EW通信effect未被消费。让干扰影响实际到达/失败，且读档不能重新抽样改变结果，为B2友军协同提供可信的通信基础。

## 2. 基线与范围

服务开发基于已审A1/K0；最终接入以A3整链SHA为底。记录两个精确SHA与合并差异，按A03→A04的Session顺序集成。范围为EW链路适配、确定性随机、消息/结果版本与恢复；不开发AI任务/目标系统或新通信UI，不重写A03观测队列。

## 3. 写者、时间与安全边界

Comms写路由/在途消息/投递状态，EW提供发送时刻链路effect；冻结采样时点并记录本次实际使用值。纯comms jam=0.5的当前fixture预期extra_latency=20s、failure_chance=0.4；与正常路由基础时延分列。伪随机种子/状态/抽样顺序可保存、可重放；测试注入draw=0.1/0.9分别失败/成功，注入依赖限测试，不成为玩家任意选结果的公开选项。

所有消息带合法sender/controller/fleet/owner，不能冒充友军或跨域发令。通信欺骗只能形成不可信消息/待确认请求，不直接执行命令/授开火权/改身份。模拟发送/到达时间为秒；未来协同请求须沿同一实际投递语义。

## 4. 实施与提交拆分

1. 先写EW开/关未影响实际Comms的红例和固定抽样fixture。
2. 接发送时effect与确定性抽样，保留no_route等原失败原因；不要每个tick或读档时重新抽样。
3. 明确outcome所需EW字段/版本。新增版本须提供严格校验与既有v1迁移；缺outcome的旧日志才标legacy_unverified，未知版本仍拒绝。保存发送上下文、sent_t/arrive_t、path、latency、outcome及必要PRNG态。
4. 独立提交服务、版本/重放、Session接线、证据；同一消息成功投递只一次，due边界规则清楚，恢复不重发历史成功事件。

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
