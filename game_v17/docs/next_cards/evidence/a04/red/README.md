# JC-A04 EW 通信链路红例（实现前，HEAD 4e4f90f）

- 探针：`game_v17/tests/jc_ew_comms_probe.gd`
- 注册：`integration.jc_ew_comms`（matrix 91 项）
- 结果：`PASS=39 FAIL=39`，退出 1（见 log）
- 覆盖：EW=0 基线、jam=.5→+20s/.4 fixture、draw 两边界、三真实入口、同 seed/文件恢复、outcome/state 版本、原失败与鉴权、旧 seed 兼容
- 失败根因（实现前）：Comms.send 未消费 EW effect；无发送时冻结采样/确定性 draw；arrive 不区分 EW 预定失败；session/order/intel 仍用 pending 消失推断送达；outcome/state 无 EW 版本与恢复。
