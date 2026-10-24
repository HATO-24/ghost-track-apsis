# DS-A-00｜现有 PR 依赖与契约协调

状态：READY；优先级：P0；父需求：#2/#4；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

让实现与测试检验同一套设计。当前 P17/P19/P20 实现链与 T22 独立发展；T22 有“静态字段必须复制到所有容器”和“原始 JSON 数字必须是 int”的口径冲突。先协调再修缺陷，避免把错误测试当需求。

当前基线为 [总队列](../../57_DeepSeek_PhaseA_任务队列与首批任务卡.md) §1 的 S0/P17/P19/P20/T22 五个精确 SHA。重新读取远端 main、PR head/base/changed files/reviews/comments；变化逐项记录后再构建。输出候选提交称 I0，必须在报告中给完整 SHA；本卡不合并远端 main。

## 范围与契约

允许：`game_v17/tests/a0_*_probe.gd`、`probe_matrix.json`、`phasea_baseline_failures.json`、`.github/workflows/tests.yml`、runner 的必要兼容、相关测试文档与执行报告。仅为保持现行语义协调；不改游戏源码、不改默认 profile，不把 Phase A 并入 Phase 0。

PhysicsWorld 写运动学；EntityCatalog 存静态信息；WorldState 是事件状态/运动投影；玩家信息由证据决定。运动/时间/可见性与数值阈值遵守总队列 §3。

必须输出断言映射表，每行有：旧断言位置→产品语义→权威字段/读者→新断言→保留/新增负例→改变理由。至少覆盖：

| 旧要求 | 协调后要求 | 等强度负例 |
| --- | --- | --- |
| physics/world/snapshot 全复制 side/batch/rcs/radius/has_pd | catalog 真值完整，按稳定 ID 查得；弹道实际读取；合成 snapshot 明确来源 | 字段丢失、ID 互换、radius 兜底冒充 catalog 均失败 |
| contacts/track 无条件带全部真值 | 无证据匿名化；有证据只公开允许字段；本舰/公开设施有来源例外 | 未知目标变 friend、batch/尺寸/PD/RCS 泄漏、嵌套 source_id 泄漏均失败 |
| JSON.parse 后 seq is int | 有限整数数值、范围、严格递增；不依赖 JSON 数字 Variant 类型 | 负数、分数、越界、重复/逆序失败 |
| 恢复后 seq is int | 保留实际 int、顺序、allocator 与继续发布检查 | 类型漂移、ID 冲突、恢复重复派发失败 |

bus/event JSON 数值范围由 A-03 的明确契约承接；不要删除恢复后的类型断言。P17 已修过嵌套 source_id，保留该生产事件回归，不重复实现。

## 实施与提交

1. 保存原始 PR/CI 清单和未解决意见；按 P20 已包含 P17/P19 的事实构建候选，再接入 T22。对修改文件逐项合并，防止 matrix/workflow 丢失分支用例。记录所纳入的完整 SHAs 和 merge parents。
2. 在改断言前运行三项 Phase A 探针，保存原失败及日志。把每个失败归为“实际实现缺陷 / 测试契约不匹配 / 尚未验证”；历史报告不能代替候选复现。
3. 单独提交契约映射和探针调整，完成上表所有负例；确认去重后矩阵预计 78 cases（实际枚举为准），phase0 仍 6、phaseA 仍 3。更新 `test_matrix.md` 中过期 72 的表述。
4. 核对 CI Phase A job 中硬编码“必须三个 expected FAIL”的历史逻辑。独立 job 应由当前 probe 的真实退出码决定红绿、总是上传实际报告；完整 baseline job 继续严格核对既有失败。保留历史红灯证据；不能删失败 probe 或使 runner 的非零状态成功。
5. 契约协调后重跑专项及完整矩阵，逐项解释计数变化；确有口径变更的 Phase A baseline 只能在证据审查后独立提交。交付 I0 和失败台账，留实现缺陷给后卡。

## 命令与验收

仓库根目录运行：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-00/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-00/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-00/full
```

期望：Phase 0 6/6；矩阵无丢项/重复项；每条失败有类别、源代码/断言位置、复现日志及后续卡；负例可检出字段错位和真值泄漏。**本卡允许 Phase A 因真实未修缺陷为红，不能以红灯代表协调失败或把红灯涂绿。** 完整矩阵若出现旧失败转绿/计数变化，按总队列 §4 保留原报告并审查。本卡引入的新回归阻塞 I0；新增负例揭示的既有缺陷须在未改源码的基线上复现、归入后续卡并保留红灯，不能冒称本卡已修复，也不要求本卡越界改源码。

交付：I0 完整 SHA、PR 依赖图、逐项契约映射、failure-ledger、真实命令/日志/CI artifact、允许进入 A-01 的结论。独立审查重点为断言强度、可见性及 JSON/运行时分界；未完成物理实现和整个 Phase A。
