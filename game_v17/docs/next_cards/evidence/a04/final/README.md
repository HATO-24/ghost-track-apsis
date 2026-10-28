# JC-A04 EW 通信链路最终证据（R1 缺省分支收尾版）

| 文件 | 内容 |
|---|---|
| ../red/ | 实现前真实 API 红例：39 PASS / 39 FAIL，退出 1 |
| targeted-summary.json / *.log.txt | 卡指定通信专项 8/8 PASS：jc_ew_comms 141/0、order_comms 137/0、ew_probe 252/0、a0_comms_restore 59/0、event_continuity 89/0、legacy_save 60/0、save_roundtrip 41/0、cic_view 925/0 |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict 91 = 84 PASS / 7 历史 FAIL，new_fail=0、drift=0、unverified=0、unselected=0、complete=true |

本轮 R1 缺省分支：显式现代 command_domains/fleet_instances seed 下，无 load/replay 的新 send：
- own 缺省上下文按可信本方锚点解析并放行（现代 own 默认）；
- ally/enemy 等非本方缺少上下文 → sender_context_required 明确拒绝；显式但缺字段 → sender_context_incomplete；
- 合法来源 owner 授权（row.share_authorized_by == 发送域 owner）作为可信锚点，可解析共享缺省上下文（A01 生产共享路径保留）；
- 真正旧 seed（无显式 command_domains/fleet_instances）缺省保持 legacy；已验证旧日志在 replay 中不重新鉴权；v1 内部迁移保持。
