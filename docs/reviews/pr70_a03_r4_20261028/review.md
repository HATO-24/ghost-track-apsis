# PR70 / JC-A03 第四轮独立复核与 A04 交接

日期：2026-10-28（Asia/Shanghai）。**PASS：原 R1 发射前预测与 R3 旧档覆盖均关闭，A3 放行。** PR70 已合入 main，#60 完成；下一张核心实现卡为 [JC-A04 / #61](../../tasks/joint_campaign/JC-A04_ew_comms.md)。低质量仍可发射本身不作为缺陷，不恢复硬禁射或新增强制射击/盲射规则。

## 1. 冻结与合并依据

| 项目 | 精确值 |
| --- | --- |
| 独立验证 HEAD / A3 冻结 | `5d372ea2df7c49badeea3846c16b839b1f6faef1` |
| 原 main / base | `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6` |
| PR70 main 合入 | `c3fca1c52a4158f374661f1906b32103dab5360c` |
| 候选与合入的完整 tree | `25c0fc001934a09371e61ccf3d5d484374d9683d`，两者相同 |
| 候选与合入的 game_v17 tree | `a7cb6afbe7df380d560a6dda07d371a66e6fc92e`，两者相同 |
| 环境 | Windows / Godot 4.7.2.stable.official.ed1daf0bf / headless |

原 A1、A2、G0/K0 冻结结论保持。根审查只写 `.test-results` 诊断与根 `docs`，未修改生产、正式 probe、matrix、baseline 或退出码包装。Godot 自动产生的 `.import/.uid` 保留在本地且不交付；C 启动时记录的 tracked dirty 来自导入元数据，不是被测运行代码变化。90 个注册 ID 非空且唯一，A02/EW ID 均保留；七项 baseline 原始 SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`，未刷新。[机器记录](verification.json)。

## 2. 本轮关闭证据

### R1：实际 HUD 与实体键的发射前预测一致消费质量

独立最小诊断使用真实 Sensor、正常 Session 与 `CombatBallistics.predict`，同 seed、t24、600km；传入 `raider_2` 和普通 HUD 匿名键 `T0001` 都解析到同一合法 owner 测量。结果如下：

| 场景 | owner 测量质量 | accuracy 因子 | 两个 Session 入口的 probability | error / applied_error km |
| --- | --- | --- | --- | --- |
| clean | .90849375 | 1 | .8775 | .735 |
| moderate | .7994745 | .85 | .745875 | 1.52475 |

直接 Ballistics 的 mq-only 与显式规范化 `mq+quality+error+mult` 给出同值，显式输入没有再乘 .85。无 Sensor 的旧兼容臂 owner 查询仍为 unknown_target、无测量字段，默认 mq=1/mult=1，概率 .8775、误差 .735。此处仅用质量影响误差与概率，不将它解释为禁射。

[诊断源码](fire/prediction_quality_contract.gd) / [完整结果](fire/prediction_quality_contract.json) / [原始日志](fire/prediction_quality_contract.log)。一次最小运行 exit0；本轮不重复此前已经关闭的 launch/运动试验。真实射后 opts 与非共线 velocity/position 差异的证据保留在[第三轮](../pr70_a03_r3_20261028/review.md)，不把原 +Y 共线退化扩大为新物理需求。正式 R23 在本轮根专项也实际执行并通过。

### R3：旧档覆盖会清除前一 Session 的 EW 状态

证据分工如下，避免把两个 fixture 混写：

- **正式 R24，本轮根实际运行**：t2 加载前 pending queue=1、samples=1；同一旧文本加载 active/fresh 后为 legacy_absent，queue/samples/delivered 均为0，前后断言通过。[日志](targeted/logs/integration.jc_ew_observation.log)。
- **独立真实 user:// 文件对照**：活跃实例已运行6tick，加载前 queue=0、samples=1、delivered=1、seq=1、quality history 含 `player_intel|raider_2=.7`；加载与 fresh 相同的旧文件后，samples/queue/delivered/rejected/seq 为0、history/cache/candidates 为空，`same_state_as_fresh=true`。此例加载前队列已经投递，不单独声称它覆盖 pending 清空。
- 独立控制仍为：完整新档保留真实在途 queue=1/samples=1；缺 `ew_combat_quality` 为 ok/partial 且准确列 missing、queue 保留1；present `queue=null` 为 invalid/ok=false，错误包含 `field=ew_observation_queue`。

[诊断源码](time_restore/r3_legacy_runtime_restore.gd) / [结果](time_restore/result.json) / [原始日志](time_restore/r3_legacy_runtime_restore.log)。一次运行 exit0；日志保留 ObjectDB/resource teardown warnings，不能称零 stderr。结合正式 R24 的 pending 覆盖，原 R3 关闭，不重写存档体系或重复 W7。

### 已关闭项继续保留

原 R2 owner 拒绝的 TrackTable/map 写入守卫、原观测及欺骗候选重投幂等与正常新观测，R3 partial/null/full，R4 旧 A02 注册 ID 与强化 W7 真实文件10tick，均保留关闭。正式 `jc_ew_observation` 本轮 **126/0**，A02 **122/0**、A1 **90/0**；没有把低质量旧解算仍能发射重新列为失败。

## 3. 同一冻结 HEAD 的独立回归

| 运行 | 总项 | PASS/FAIL | 耗时（含 import） | exit | 原始结果 |
| --- | --- | --- | --- | --- | --- |
| targeted | 11 | 11/0 | 69.3s | 0 | [report](targeted/report.md) / [summary](targeted/summary.json) |
| phase0 | 6 | 6/0 | 37.12s | 0 | [report](phase0/report.md) / [summary](phase0/summary.json) |
| phaseA | 3 | 3/0 | 26.7s | 0 | [report](phaseA/report.md) / [summary](phaseA/summary.json) |
| full | 90 | 83/7 | 464.34s | 0 | [report](full/report.md) / [summary](full/summary.json) |

Full 的七项 FAIL 全部与既有 baseline 匹配：**known_fail=7、new_fail=0、drift=0、unverified=0、unselected=0、complete=true，退出0**。耗时只记录本次运行，不充当 >1000tick 成本或性能预算验收。

| 历史项 | pass/fail 断言 |
| --- | --- |
| `content.damage_profile_probe` | 554/4 |
| `content.story_text_probe` | 469/13 |
| `unit.incident_record_probe` | 2761/1 |
| `integration.damage_integration_probe` | 198/6 |
| `integration.plot_tws_probe` | 58/1 |
| `integration.v17_nav_integration_probe` | 181/1 |
| `integration.v17_sensor_authority_display_probe` | 71/3 |

[同 head 的 CI run 40714308154](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40714308154) 三个 job SUCCESS；full 实际 checkout 为合成 merge `387ad78fa1aeb10aeaa9291cad1226a2bc4f2589`（5d372ea2 合入 3845852），90=83PASS/7历史FAIL、无新增/漂移、complete=true、FULL_MATRIX_EXIT=0，263.6s。[原始 CI](ci/full.log) / [关键行](ci/full-relevant.txt)。本地 C 直接跑冻结 HEAD，两类证据分别记录，不混称 CI checkout 为源分支 HEAD。

命令沿原卡：11 项 `-Only` 专项；`-Gate phase0 -Ci`；`-Gate phaseA -Ci`；全量 `-Ci -Baseline game_v17/tests/known_baseline_failures.json`。统一使用上述 GodotBin，四个 ResultsDir 为 `.test-results/sol-a03-r4/{targeted,phase0,phaseA,full}`，完整参数在各 summary.invocation。原始字节校验见 [manifest.sha256](manifest.sha256)。

## 4. 下一张交 DeepSeek：A04 / #61

从包含 `c3fca1c52a4158f374661f1906b32103dab5360c` 的最新 main 开始，记录实际40位执行 HEAD；保留 A3 已落质量、owner、幂等和恢复合同。只交 EW 通信适配、确定性结果与版本化恢复：`comms_jam=.5` fixture 仍为额外20秒、失败率.4，draw=.1/.9 分别失败/成功，发送时采样并冻结，tick/读档不重抽。

卡中补清现有三条真实入口 `Session.send_comms`、`OrderService.issue`、`Session.queue_intel_share`，避免只接包装函数漏掉订单/情报；Comms 仍由现有 OrderService.tick 推进一次。独立消息回调应读实际 DELIVERED/FAILED，不能从 pending 消失推断成功后执行失败订单或融合失败情报。其余 outcome v1 迁移、未知版本拒绝、原失败重放、同消息只交付一次、真实文件继续至少10tick均为原卡合同。

核心顺序继续 A04→B01A；不提前宣称联合战役 demo 完成。UI设计/文档由 GPT/Sol，主要代码由 DeepSeek。Linux/macOS、非 headless 渲染、真实 RF/光学物理和 >1000tick 成本本轮 **NOT RUN**。
