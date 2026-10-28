# PR68 / JC-A02 第三轮独立放行

日期：2026-10-28（Asia/Shanghai）。**PASS，A2冻结为 `755ab5ed629165656a566427523b01045775fc0f`。** 原R3/R4两处实际消费者已关闭；前轮关闭项保持，不再派发A02返工。

## 1. 版本及合入

- 被审HEAD：`755ab5ed629165656a566427523b01045775fc0f`；上一轮：`4a658699868b8d046ec5472f9c4b9ea204af6be9`。
- 原base：`1738a5e41509c09e04dc34da382dc07f4b8982e9`。
- [PR68](https://github.com/HATO-24/ghost-track-apsis/pull/68)已按精确HEAD合入main：`82bf6a531042961f0d5fe5d948c7004a15cd20cf`。
- 候选与合入的**整个tree相同**：`cefff3064c078375764c38b59bf892959b7887b9`；game_v17子树同为 `af82e94883acfae7881b8861ad16fa21b4e33027`。合入提交父级为原base与被审HEAD。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`。引擎路径：`D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe`。

连接器合并调用返回传输错误后，先用GitHub CLI读取状态而未重复合并；读取确认PR为MERGED，再fetch并完成上述树校验。[机器可读记录](merge-provenance.json)。

## 2. 原反例及关闭证据

| 原残项 | 独立实际入口结果 | 结论 |
|---|---|---|
| R3 HUD航迹键→实体身份 | 实际radar tick6s→Binder.refresh→**实际HUD._seed_combat_tracks**。T0001前置entity_id/ship_id均空；已有sensor map raider_2→T0001。合法manual friend后，无hint的combat_identity(T0001)为friend/resolved_key=raider_2/via=sensor_map；实际request_fire后同一空字段combat行成为friend。实体键与预填T0009正例均friend | CLOSED |
| R4 普通HUD有效性 | t0有效friend时普通contact为friend/friend/friendly。TTL5到t11，操作记录保留raw friend，effective为unknown；Binder显示identity=unknown、last_known=friend、warn与EXPIRED，普通contact identity/side/type均unknown，row.ident同样有EXPIRED告警，火控unknown/history friend | CLOSED |

R3独立一次Godot诊断退出0、13/13有界观察检查通过。火控仍返回needs_authorization，**未证明实际弹体发射，也未绕过独立开火授权**。[分项说明](sources/source_consumer_findings.md) / [JSON](sources/source_consumer_audit.json) / [检查摘要](sources/summary.json)。

新正式R12现在使用真实radar映射及空字段combat行，覆盖了原先被手工预填掩盖的条件；它仍通过register_track模拟HUD行。本轮独立诊断补足实际_seed_combat_tracks调用，不因方法调用形式不同重开等价且已验证的空字段回归。

R4诊断一次退出0，包含有效/过期正反对照及stale维度；普通联系人实际绘制使用type/颜色及row.ident.tag，详情读取ident_view.identity，因此本轮返回值已进入实际读者。stale样本仍可state=valid、validity=stale且effective friend，继续按两个维度解释，不要求stale一律unknown。[读者与运行说明](hud_validity/findings.md) / [完整数据](hud_validity/result.json)。

两份诊断退出时各有82 ObjectDB实例/22资源清理提示，原始日志保留；退出0是取证完成，关闭判断来自上述值和真实读者核对。没有扩跑已关闭R5自然恢复诊断；其上轮证据及R1/R2/R4其余关闭项仍见[第二轮](../pr68_a02_r2_20261028/review.md)。

## 3. 根代理独立专项与完整C回归

全部在同一被审HEAD运行，未修改生产、正式probe、matrix、baseline或测试退出码包装。生成的.import/.uid保留在工作区，不交付。根代理独立运行如下：

| 运行 | 实际结果 | 耗时 |
|---|---|---|
| 七专项 | 7/7 PASS；identity122/0，identification310/0，track161/0，transponder272/0，sensor86/0，event89/0，save41/0 | 44.8s，含25.5s import |
| Phase 0 | 6/6 PASS | 29.7s |
| Phase A | 3/3 PASS | 22.4s |
| 原C全量strict | **89=82PASS/7历史FAIL，new_fail=0、drift=0、unverified=0、unselected=0、complete=true，退出0**；无TIMEOUT/NOT RUN | 404.5s |

[专项](targeted/report.md) / [Phase0](phase0/report.md) / [PhaseA](phaseA/report.md) / [完整C](full/report.md) / [C机器摘要](full/summary.json)。本轮不是仅引用DeepSeek或CI全量。

七项历史FAIL原样执行，退出码均1，PASS/FAIL计数依次为：

| case | PASS/FAIL |
|---|---|
| content.damage_profile_probe | 554/4 |
| content.story_text_probe | 469/13 |
| unit.incident_record_probe | 2761/1 |
| integration.damage_integration_probe | 198/6 |
| integration.plot_tws_probe | 58/1 |
| integration.v17_nav_integration_probe | 181/1 |
| integration.v17_sensor_authority_display_probe | 71/3 |

baseline未刷新，SHA256仍 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`；旧红项没有改名为PASS。

实际命令（仓库根目录，沿原C合同）：

```powershell
$taskGodotBin = 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin $taskGodotBin -Only '(jc_identity_pipeline|identification_probe|transponder_probe|track_table_probe|a0_(sensor_persistence|event_continuity|save_roundtrip))' -Ci -ResultsDir .test-results/sol-a02-r3/targeted
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin $taskGodotBin -Gate phase0 -Ci -ResultsDir .test-results/sol-a02-r3/phase0
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin $taskGodotBin -Gate phaseA -Ci -ResultsDir .test-results/sol-a02-r3/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin $taskGodotBin -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/sol-a02-r3/full
```

全部运行保留summary/report/import及每case原始log；上述目录中的run-id分别记录170648、170830、170900、170923与755ab5ed。

## 4. 精确HEAD的CI

[run40644344521](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40644344521)关联head755ab5ed，三个job success。full实际checkout为合成merge `5cb245cbaf295455115d32361d18255bcc3288fe`（755ab5ed合入1738a5e），**89=82/7、new_fail0、drift0、complete=true、FULL_MATRIX_EXIT=0**，377.1s。它与本地404.5s是不同运行，不互相冒充。[原始CI日志](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。日志后段的预期红灯自测另列，不能误当主矩阵失败。

## 5. 交接与限制

#59完成；下一张核心卡为[JC-A03 / #60](../../tasks/joint_campaign/JC-A03_ew_observation.md)，从包含82bf6a5的main开始。A3只接EW→真实Sensor/延迟队列→owner航迹当前测量质量→实际火控，保留A2统一身份、映射、审计与恢复；A04通信、B01A部署和B2友军AI依赖不提前扩张。A1/G0/K0结论不变。

UI设计与任务文档仍由GPT/Sol维护，主要代码交DeepSeek；HUD/Binder文件与UI-01串行。本次属于实际消费者接线验收，不是完整UI视觉交付。

Linux/macOS、非headless渲染/人工可读性、真实RF/光学物理、>1000tick成本本轮NOT RUN；不把A2完成写成联合战役Demo完成。校验见[manifest.sha256](manifest.sha256)。

