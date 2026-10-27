# PR66 / JC-A01 第五轮：独立通过与A1冻结

日期：2026-10-27（Asia/Shanghai）。**PASS，原#58全部收尾完成，A1冻结为 `845584733df619feb3e372e8c06a7caa9f3fdaba`。** [PR66](https://github.com/HATO-24/ghost-track-apsis/pull/66)已合入main，合并提交 `f62e5e6f48b3faf1098cbb44b2801c5c8fde394e`。下一张核心实现卡为[JC-A02 / #59](../../tasks/joint_campaign/JC-A02_identity.md)。

## 1. 被审版本与范围

HEAD84558473的测试/诊断代码来自 `00cdc2976516febb0d8fa0f571568bea104edaa1`；其后仅证据与报告更新。独立运行全部使用完整HEAD84558473，不将作者旧提交结果当新提交实跑。Windows / Godot `4.7.2.stable.official.ed1daf0bf`。

本轮只复核原T1/T2：已获证据目标掉行必须红；同一目标的隐藏移动必须真实发生，无新观测时保持旧获准信息，新合法观测后才能更新。owner老化、在途共享恢复、光学显示及前轮授权等已关闭实现不返工。Sol没有改生产代码、正式probe、矩阵或baseline。

相对上轮eb4b9853，业务实现唯一脚本差异是在已有测试钩子增加PhysicsWorld前后读数和physics_changed返回字段；授权、owner、Comms、HUD/Binder、矩阵和baseline对象完全相同，见[对象对照](unchanged-contracts.json)。原三项实现闭环与内存/真实文件各10tick证据继续保留在[第四轮报告](../pr66_a01_r4_20261027/review.md)，没有冒称本轮重跑全部旧诊断。

## 2. 原两组测试保护关闭

| 项目 | 正式正例 | 独立红灯控制 |
|---|---|---|
| T1已观测contact必须存在 | metadata从可信owner.tracks导出必须出现的内部track_id集合，逐项匹配contact；原source/owner/匿名显示、实际HUD与内部路由检查保留。A01也明确要求target_a行、可信owner及匿名显示 | 删除一条已获证据harmattan行，**281/1、退出1**，失败明确为every acquired-evidence target has a contact row |
| T2同目标真实移动与合法更新 | world-sync对harmattan观测、移动、比较；核验truth_changed、physics_changed和真实physics坐标；旧plot/采样时间保持，新观测后位置/时间更新。A01对raider_2也做同实体contact/plot对照 | no-op变更，**104/3、退出1**，失败为实际变更、PhysicsWorld变化及目标坐标；不再能以原100/0假绿 |

[分项审校](test-closure.md)、[结构化控制结果](test-closure.json)、[T1日志](controls/negctl_a1_missing_contact.stdout.txt)、[T2日志](controls/negctl_ws_noop_mutation.stdout.txt)。两份脚本副本直接复制本候选交付材料后运行，SHA256和退出码均保留。有效运行无解析/加载错误；退出清理stderr原样保留。一次因含空格路径未正确引用而未加载脚本的启动尝试未计作有效控制，详见分项记录。

没有删除正式case、放宽精度/负例、刷新历史baseline或恢复全真值UI。未观测目标仍可缺席；显示ID仍匿名，内部track_id不改写。内部7实体、同刻位置/速度精度及PhysicsWorld→WorldState单向权威检查保持。

## 3. 根代理实际运行

| 专项 | PASS/FAIL | 退出 |
|---|---|---|
| integration.a1_entity_metadata_authority | 359/0 | 0 |
| integration.a0_world_physics_sync | 107/0 | 0 |
| integration.jc_authority_intel | 90/0 | 0 |
| integration.a0_integration_authority | 65/0 | 0 |
| integration.a0_save_roundtrip_authority | 41/0 | 0 |

专项**5/5 PASS**，49.0s含23.1s导入，整体退出0。[专项report](targeted/report.md) / [summary](targeted/summary.json)。

完整原C矩阵本轮独立实跑：**88=81 PASS/7历史FAIL，new_fail0、drift0、unverified0、unselected0、complete=true，退出0**；341.5s，无TIMEOUT/NOT RUN。[full report](full/report.md) / [summary](full/summary.json)。full/selected-logs归档七项历史FAIL及本轮三项关键probe，其余原始日志保留本地 `.test-results/sol-a01-r5/full/20261027-192223-84558473`，不声称本归档含全部88项原始log。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_authority_intel|a1_entity_metadata_authority|a0_world_physics_sync|a0_integration_authority|a0_save_roundtrip)' -Ci -ResultsDir .test-results/sol-a01-r5/targeted
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Baseline game_v17/tests/known_baseline_failures.json -Ci -NoImport -ResultsDir .test-results/sol-a01-r5/full
```

第二条复用首条完成的同版本导入，strict无partial/无筛选。七项历史FAIL仍保持原计数和FAIL状态，baseline SHA256仍为 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`。继承的资源退出清理诊断未隐藏；不以有stderr否认明确的断言/退出结果，也不声称零引擎诊断。

[同HEAD的CI](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40493987784) Phase0、PhaseA、full三个job均success，见[检查元数据](ci-checks.json)。本轮没有另行本地重复Phase0/PhaseA子集，以上full包含它们的正式case；本地结果与CI结果分开记录。

## 4. 合并核对与下一卡

合并前核实PR66 head=84558473、base=3045311、三个CI检查成功，使用expected_head_sha保护合并。GitHub返回合并提交f62e5e6f。其整个tree为 `1e6650950d35db19219431c58619f3932392bfdc`，**逐对象等于被审候选84558473**，不是只看提交说明；game_v17子树为 `82c99ebaa16a676e447c693d71b73b39df5fdeca`。核对元数据见[合并记录](merge66.json)。

#58完成，A1冻结；主要代码下一步交DeepSeek按原[#59](https://github.com/HATO-24/ghost-track-apsis/issues/59)做多来源身份/IFF闭环。从包含f62e5e6f的main开始，记录实际40位执行SHA，保留A1 owner隔离、授权、共享与恢复；不能只更新旧全局assessment而绕过新owner可见读路径。核心接入仍A02→A03→A04→B01A，不同时重写GameSession。

UI文档、文案和交互规格由GPT/Sol维护；A1等待已经解除，UI-01仍需有限文案设计核对及HUD/Binder文件排程，避免与A02接入互相覆盖。其余UI卡按[《61_UI文案台账与实施队列》](../../61_UI文案台账与实施队列.md)推进；没有新UI运行时或实机视觉验收。

Linux/macOS、非headless真实渲染、真实RF/光学物理、>1000tick成本均NOT RUN，原专项任务/预算保留。A1完成不是完整联合战役Demo完成；逐舰战斗、友军AI与战役裁决仍按原后续卡。

本轮新证据SHA256见[清单](manifest.sha256)。前四轮RETURNED记录保留为历史，以本轮PASS及A1冻结为准。
