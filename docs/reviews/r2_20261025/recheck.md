# R2派工前独立复核

日期：2026-10-25，Asia/Shanghai。复核者Sol；实现者DeepSeek。此处为测试与文档交付，不修改游戏运行时代码。

## 范围与来源

- 当前main=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`；返修候选PR #55=`30b8d33dae9787aadf89bb206757cafb2cad7bd3`，尚未合并。
- 阅读40号原审计、用户工作区56 R2，以及#55改动/报告/CI；R2 SHA256=`5ED8C0C7080860381731253324679F6E119CAE4AC6D87645BAD0727FAF7CABA1`，随本轮文档提交保留原文。
- 用户本轮明确确认：阶段性战区行动、自有舰队直控＋友军协同请求。具体阵容/阈值/日期/预算仍待具体方案审阅。
- 独立工作区以C55建立；引擎Godot `4.7.2.stable.official.ed1daf0bf`，Windows 10.0.26200，PowerShell7.6.6。原主工作区未重置/提交；运行产生的import/uid变更不入本PR。

## 本轮实际执行

仓库根目录执行：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(core_time_event|track_table_probe|a0_(event_continuity|legacy_save|sensor_persistence|comms_restore|integration_authority|save_roundtrip_authority))' -Ci -ResultsDir .test-results/r2-recheck/targeted
```

run_id=`20261025-221712-30b8d33d`；51.26s含22.71s导入；退出0、8/8 PASS、0 FAIL/TIMEOUT/NOT RUN。各probe断言PASS依次为197、161、59、86、60、89、65、41；详情以[原始summary](targeted-summary.json)、[runner报告](targeted-report.md)、[import日志](import.log)和[stdout/stderr目录](logs/)为准。summary内log_path保留运行时位置，在本归档中对应`logs/`同名文件。

这是断言与退出码结果，**stderr并非零错误**。core time契约拒绝、坏JSON等对应负例；sensor probe:235有字符串拼接/格式优先级错误，integration probe:234使用不支持的格式，均位于诊断输出；若干HUD probe退出时还有对象/资源残留。原始stderr一并保留，JC-A00需修正失效诊断并核对清理情况，不将未审清理问题隐称为全净，也不将负例push_error全部视为新增功能失败。

原S7审查脚本未修改，复制进隔离工作区后实际运行：

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script 'C:/Users/ASUS/.codex/worktrees/joint-campaign-r2-planning/GHOST TRACK_APSIS/.test-results/r2-recheck/boundary_repro.gd'
```

归档脚本为[boundary_repro.gd](boundary_repro.gd)；重新执行时可将`--script`换成本文件所在的绝对路径。退出0、`REVIEW_BOUNDARIES_RESULT violations=0`；[完整日志](boundary.log)、[提取JSON](boundary-results.json)。

| 原反例 | C55观测 |
| --- | --- |
| 显式/自动ID碰撞 | evt-000001 / evt-000002，不相同 |
| v2缺seen_ids后遗失去重 | import_ok=false，原子拒绝；随后在新bus发布可成功，不等于坏档被接受 |
| 玩家selected泄露batch | list/selected均不含batch |
| 未知outcome version被当旧档 | version999 load_ok=false、legacy_unverified=0 |
| sensor分数版本 | version1.5拒绝，invalid_state_version |
| 非空运行态丢backend | backend=null拒绝 |
| EMCON恢复后obs_seq偏差 | 原始/恢复34/34，继续10tick一致 |

此脚本只复测原7个反例，不是对所有恢复字段的完备证明。filtered_observations的30/20差异作为诊断计数如实保留，不能据此声称所有状态完全相同；R05需比较影响未来行为的完整状态和后续输出。

## 外部CI证据与未运行项

[Actions run40174245081](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40174245081)精确head=C55，Phase0/PhaseA/full三个job成功；full实际84case=77PASS/7历史FAIL，成功表示按既有基线核对，不是84项全绿。本轮没有独立重跑84项，也未重跑R05长时benchmark、Linux/macOS、非headless试玩或>1000tick。

代码复核确认R01–R04反例已有修复，不重复派工。R05已改字节/样本调用/provenance；仍需实际集合成员/完整运行态/继续行为比较及run2/run3真实篡改被比较器发现的证据。#55仍需与旧PR链及#54内容协调，JC-A00形成G0后由独立审查决定放行。

新联合战役尚无部署/逐舰账本/敌我AI/目标裁决/整场试玩证据，本轮不计算完成百分比或工期。下一批8张卡是交接材料，创建Issue不代表已启动DeepSeek。
