# JC-A04 EW 通信链路最终证据（交付前加固版）

| 文件 | 内容 |
|---|---|
| ../red/ | 实现前真实 API 红例：39 PASS / 39 FAIL，退出 1 |
| targeted-summary.json / *.log.txt | 卡指定通信专项 8/8 PASS：jc_ew_comms 106/0、order_comms 137/0、ew_probe、a0_comms_restore 59/0、event_continuity 89/0、legacy_save 60/0、save_roundtrip 41/0 |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict **91 = 84 PASS / 7 历史 FAIL，new_fail=0、drift=0、unselected=0、complete=true** |

交付前加固（同分支）：
- 链路两端 EW 采样（发送/接收任一被干扰均生效，一次发送只抽一次 draw）。
- 确定性失败/成功双 seed 臂：真实文件保存→恢复→24 tick，失败仍失败/成功恰好一次，下一消息 draw/seq 与连续运行一致。
- 篡改检测：改 outcome.ew.draw → replay divergence；改 pending.ew.draw（破坏冻结结果）→ invalid_state，原因字段明确。
- 旧残留 standalone 无真实结果 → comms.unknown_outcome，绝不冒充 delivered。
