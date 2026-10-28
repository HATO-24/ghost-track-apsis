# JC-A04 EW 通信链路最终证据（R1/R2/R4 返修版）

| 文件 | 内容 |
|---|---|
| ../red/ | 实现前真实 API 红例：39 PASS / 39 FAIL，退出 1 |
| targeted-summary.json / *.log.txt | 卡指定通信专项 8/8 PASS：jc_ew_comms 131/0、order_comms 137/0、ew_probe 252/0、a0_comms_restore 59/0、event_continuity 89/0、legacy_save 60/0、save_roundtrip 41/0、cic_view 925/0 |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict 91 = 84 PASS / 7 历史 FAIL，new_fail=0、drift=0、unverified=0、unselected=0、complete=true |

R1：三个真实入口（send_comms/issue_order/queue_intel_share）校验 sender 与 actor/controller/domain/fleet/owner 上下文；已登记 ally/player、enemy/player、own/opfor 错配拒绝（sender_context_mismatch），共享 owner 与接收域错配拒绝（owner_context_mismatch）；own/player、ally/ally、旧 seed 无上下文的 legacy 正例保留。
R2：普通 opts.ignore_ew 明确拒绝（ew_bypass_forbidden）；只有 v1 outcome 内部迁移/重放走 send_legacy_v1，保留旧档兼容。
R4：v2 必须携带 pending.ew；state version 2.5 严格拒绝（2.0 整数等价接受），拒绝不改服务状态；正式成功共享改为合法 owner player_intel + fresh row：到达前 0、due tick 0→1、后续不增；EW 失败共享仍不融合。
