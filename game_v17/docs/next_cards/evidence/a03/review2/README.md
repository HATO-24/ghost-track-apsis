# JC-A03 PR70 复核返修证据（R1修订/R2/R3/R4）

| 文件 | 内容 |
|---|---|
| targeted-summary.json / *.log.txt | 卡指定 11 执行行 PASS：jc_ew_observation 83/0（含修订R1、R2、R3与强化W7） |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict **90 = 83 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true** |

修订R1（产品口径）：撤回低质量旧解算硬禁射；新建q<0.5拒绝保留为fixture；READY/射击消费当前测量质量（精度×0.85）并记录数据时刻/有效性/误差，实际发射仅作观察口径。
R2：投递接纳覆盖 owner/质量/火控/候选全部副作用，重投不覆盖当前质量、不增投递审计。
R3：present-invalid 新 EW 段明确拒绝（ew_restore_mode=invalid），有效新段 full、真正缺段 legacy_absent。
R4：恢复 integration.jc_identity_pipeline 注册ID（总90）；W7 全量比较队列/捕获几何/投递审计/owner质量/实际解算行。
