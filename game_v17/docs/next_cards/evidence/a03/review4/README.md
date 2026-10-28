# JC-A03 PR70 第三轮复核返修证据（R1 发射前预测 / R3 旧档覆盖会话）

| 文件 | 内容 |
|---|---|
| targeted-summary.json / *.log.txt | 卡指定 11 执行行 PASS：jc_ew_observation 126/0 |
| phase0/phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict **90 = 83 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true** |

R1：combat_predict_track（真实 HUD 入口）按 owner 合法映射（实体键→owner 质量、匿名航迹键经 _entity_for_track/identity 解析）读取同一质量，并以接口同一冻结规则生成显式 quality/error 传入弹道预测；CombatBallistics.predict 在仅 mq、无显式 quality/error 时实际应用 ×0.85 并生成对应误差。探针覆盖实体键、HUD 匿名键、mq-only 分支，均与 combat_service.predict_shot 接口值一致（1e-9），且 HUD 键与实体键一致。
R3：旧档（全 EW 段缺失）覆盖活跃会话时先 _ew_reset_runtime() 清除加载前队列/采样/投递/候选/seq/质量历史，fresh 与 active 加载同一旧档语义一致（queue/samples/delivered 均 0/0/0）；full/partial/present-invalid 行为保留。
