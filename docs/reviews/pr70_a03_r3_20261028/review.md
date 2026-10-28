# PR70 / JC-A03 第三轮独立复核

日期：2026-10-28（Asia/Shanghai）。**RETURNED，本轮只剩R1发射前预测与R3旧档覆盖两个入口；R2全部关闭。** 低质量仍可发射不作为缺陷，不恢复硬禁射或新增强制射击/盲射产品规则。

## 1. 版本与验证

HEAD `022a7e0e6b0ab2ce65f228f98b4a1146d18792f8`，上轮 `ea29da7138ad353c4198f76547f57c4e0b07142d`，base/main仍 `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。

根独立专项 **11/11 PASS，165.8s含65.8s import，退出0**：EW102/0、A02 122/0、A1 90/0、combat255/0、EW252/0、sensor128/0、track161/0、CIC925/0、sensor persistence86/0、authority65/0、save41/0。[report](targeted/report.md) / [summary](targeted/summary.json)。耗时是本次运行记录，不是规模/性能验收。

[CI run40695377143](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40695377143)关联同head；本轮后续回读确认三个job success。实际full checkout为合成merge `aad544e3e6e538c3f126009ecbabb24f7f29bc47`（022a7e0合入3845852），**90=83PASS/7历史FAIL、new_fail0、drift0、complete=true、FULL_MATRIX_EXIT=0**，355.5s。[原始日志](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。根本轮未重复本地full90；剩余真实入口反例仍阻止A3放行。

本轮没有修改生产、正式probe、matrix、baseline或退出码包装，只写诊断与根docs。matrix及baseline blob与上轮/main相同。import生成的.import/.uid保留，不交付。观察型诊断的退出0不表示验收通过；原始结束日志含fixture清理提示，不能称零stderr。

## 2. 已关闭：保留本轮实现

| 原组 | 已证明完成的部分 | 本轮处置 |
|---|---|---|
| R1射后真实消费者 | request_fire将规范化质量/误差传入真实Ballistics prediction与launch，射后预测与接口值一致；非共线正例中实际速度和后续位置发生差异 | **真实发射链CLOSED，不重做** |
| R2拒绝项写者守卫 | share_not_authorized项不再写global TrackTable/map；原OBS重投/非空候选重投均幂等，正常新观测继续 | **R2全部CLOSED** |
| R3部分新段转换 | 缺ew_combat_quality现在ok=true/partial，missing列出该键且合法队列保留；null仍invalid/ok=false，full正常 | **这些子项CLOSED，不返工** |
| R4注册/W7 | 90个注册ID及A02正常；W7正常文件10tick的已强化队列/捕获几何质量/投递/owner/实际解算对照继续通过 | **保持CLOSED** |

### R1实际运动的补充正例与边界

原沿+Y、600km几何中，clean q=.90849375/error=.735，moderate q=.7994745/error=1.52475。新代码确实向aim加了误差，但偏移也沿+Y，与视线共线，所以归一化后的初始速度同为(0,8,0)，t25–27位置/速度/closest相同。**这不能推出所有几何都无效，也不将其单独判成新物理功能缺陷。**

为避免把已实现接线误派返工，补充同seed、同t24、目标同时含X/Y相对分量、约600km的非退化对照（world与sensor目标配置一致，实际物理range约599.98999km，双方相同）。真实Sensor clean/moderate质量仍为.90849375/.7994745，真实发射成功；初始velocity分别为：

- clean：(5.6518630981, 5.6618409157, 0)
- moderate：(5.6466050148, 5.6670846939, 0)

t25的y位置分别5.7679853439与5.7733278275，t26/27位置和速度也不同。由此确认输入已进入实际运动，**不再要求重做launch/真实误差接线**；只观察到FLIGHT，不声称命中或统计命中率。当前采用确定性世界+Y偏移，是抽象近似；保留非退化正例，不把共线退化解释成未消费，也不要求完整制导/RF模型。

[原轴线数据](fire/quality_motion_comparison.json) / [非共线源码](fire/quality_motion_offaxis.gd) / [完整结果](fire/quality_motion_offaxis.json) / [正常完成日志](fire/quality_motion_offaxis.log) / [根离线比较摘要](fire/comparison_summary.json)。非共线补充的退出码未单独归档，结论依据可检查的完整状态与实际调用链；不把它计入正式102条断言或重复宣称根专项。

### R2完整关闭证据

原OBS-000008重投后，measurement/combat/cache仍为.90849375@21，owner observations/accepted audit保持19；非空deception候选重投1→1，identity evidence和.82@1质量不变；各自只增加允许的拒绝审计。owner错投仍报告share_not_authorized，而global tracks **0→0**、map **空→空**，两owner无观测/measurement。10项操作字段前后均相同。正常own观测10→19，ally1→4/player0，证明没有用拒绝全部新数据换取幂等。

[分项说明](observation/findings.md) / [检查摘要](observation/summary.json) / [真实输入及前后状态](observation/replay_audit.json)。只运行一次原诊断、exit0，无新范围。

## 3. 仅剩两个原入口

### R1 [P2] 普通HUD发射前预测没有一致读取/应用质量

这次射后预测和实际发射链已好，残项是玩家**射击前**的普通预测。实际HUD调用[v1_hud.gd:2982](https://github.com/HATO-24/ghost-track-apsis/blob/022a7e0e6b0ab2ce65f228f98b4a1146d18792f8/game_v17/scripts/ui/v1_hud.gd#L2982)进入Session.combat_predict_track，不是仅供测试的辅助getter。

同t24/600km原几何：

| 入口 | clean | moderate |
|---|---|---|
| owner实体质量 | .90849375 | .7994745 |
| 实体键发射前predict返回measurement/mult | .90849375 / 1 | .7994745 / .85 |
| 实体键发射前predict probability/error | .8775 / .735 | **仍.8775 / .735** |
| HUD T0001发射前predict measurement/mult | 1 / 1 | **仍回默认1 / 1** |
| 射后实际prediction probability/error | .8775 / .735 | 已正确.745875 / 1.52475 |

原因有两个相连的小分支：[combat_predict_track:3523](https://github.com/HATO-24/ghost-track-apsis/blob/022a7e0e6b0ab2ce65f228f98b4a1146d18792f8/game_v17/scripts/core/game_session.gd#L3523)直接按传入T0001查owner质量，没有复用既有实体映射；实体键虽找到质量，但只传measurement_quality。[CombatBallistics.predict:882–891](https://github.com/HATO-24/ghost-track-apsis/blob/022a7e0e6b0ab2ce65f228f98b4a1146d18792f8/game_v17/scripts/core/combat_ballistics.gd#L882)计算acc_mult后未在“仅mq、无显式quality/error”分支实际应用，故只改了附带字段。

**最小收尾**：正常发射前路径按owner合法映射读同一质量；没有已规范化显式quality/error时应用既定因子并生成相应误差。保留射后完整opts直接采用的正例，避免再次乘.85造成双重惩罚；无测量旧字段兼容不变。验收用实体键与实际HUD匿名键的正常predict入口，保持只读，不新增禁射或新UI流程。现已关闭的真实launch接线不重做。

[轴线完整数据](fire/quality_motion_comparison.json)内pre_fire_prediction_entity_route、pre_fire_prediction_hud_route及fire_result可直接对照；[根摘要](fire/comparison_summary.json)提取相同值。

### R3 [P2] 旧文件覆盖活跃Session，保留了前一会话的EW运行态

原partial转换已关闭：缺ew_combat_quality现在partial/ok=true，missing准确列出，队列仍1；queue=null仍invalid/ok=false且有字段原因；完整新档full/ok=true。

剩余是同一旧文件的公开load状态替换：

1. 使用真实apply_ew与tick，当前Session在t2有自然pending队列1、samples1。
2. 另一个干净Session生成无全部A03 EW字段的兼容文件，实际写入user://、再读取。
3. 将**同一文件**分别load到当前活跃实例与新实例，均返回ok=true/legacy_absent且now=0。
4. 新实例queue/samples为0/0，活跃实例却仍为**1/1**，same_state_as_fresh=false。

[GameSession._ew_restore_state:2885–2887](https://github.com/HATO-24/ghost-track-apsis/blob/022a7e0e6b0ab2ce65f228f98b4a1146d18792f8/game_v17/scripts/core/game_session.gd#L2885)全字段缺失时在重置EW成员前直接return，而boot也未重置这些新成员。旧档状态因此取决于加载前当前会话；这不是null已拒绝的问题。未继续断言旧项后来已经投递或造成命中。

**最小收尾**：初始化/覆盖恢复时清除加载前EW运行态，再按同一文件的字段及既定legacy/partial规则恢复或重建；同文件加载到fresh和active应有一致默认语义。保留完整新档中的合法在途队列、partial/missing与present-invalid拒绝，不将“清空一切”用于正常full恢复，也不扩新存档体系。

[诊断源码](time_restore/r3_legacy_runtime_restore.gd) / [结果](time_restore/result.json) / [真实公开load日志](time_restore/r3_legacy_runtime_restore.log)。一次有界运行exit0，未重跑W7。

## 4. 下一次交付及回归

只继续原#60两处：R1发射前实体/匿名键预测与mq-only分支，R3旧档覆盖会话初始化。真实launch/非退化运动、R2全部守卫/重投、partial/null/full以及R4/W7均保留关闭，不重派。补两个实际入口对照，最终同40位变更HEAD专项+原C，七历史baseline不刷新。

根命令保持原11项：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip)|cic_view_probe|jc_identity_pipeline|jc_authority_intel)' -Ci -ResultsDir .test-results/sol-a03-r3/targeted
```

PR70暂缓合并、A3不冻结。A1/A2/G0/K0完成不变，A04/B01A核心接入仍按原依赖等待；UI设计/文档GPT/Sol，主要代码DeepSeek。Linux/macOS、非headless渲染、真实RF/光学、>1000tick成本NOT RUN。前轮关闭表及口径纠正见[第二轮](../pr70_a03_r2_20261028/review.md)与[首轮历史](../pr70_a03_20261028/review.md)，原始字节校验见[manifest.sha256](manifest.sha256)。

