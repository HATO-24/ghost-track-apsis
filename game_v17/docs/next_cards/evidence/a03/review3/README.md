# JC-A03 PR70 第二轮复核返修证据（R1 Ballistics 消费 / R2 拒绝守卫 / R3 部分新段）

| 文件 | 内容 |
|---|---|
| targeted-summary.json / *.log.txt | 卡指定 11 执行行 PASS：jc_ew_observation 102/0 |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict **90 = 83 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true** |

R1：真实 CombatBallistics.predict/launch 消费抽象测量质量/误差；Session launch_opts 与射后 prediction 传入接口 quality/error；弹体 pplied_error_km = 接口 error（1e-9），有测量 vs 无测量对照的预测/弹体误差与初始瞄准不同。
R2：owner 拒绝/去重项在写全局 TrackTable/映射前直接返回，仅记 rejected 审计。
R3：可选 EW 字段缺失时有意默认 + w_restore_mode=partial/w_restore_missing，不再触发 null 转换异常；present-invalid 仍明确失败。
