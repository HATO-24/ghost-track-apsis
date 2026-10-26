# R7 长测原始证据（JC-A00 / #56 · G0-4）

- 被审/测量代码 SHA（40 位）：`a51e19f2e2609b69f4e90a87da7855538de205c4`
- 运行时间：2026-10-26；Godot 4.7.2；Windows；headless
- 命令：`pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/jc-r2/JC-A00/r7/benchmark`
- 结果：**PASS 90/0，860.5 s**，12 个样本（4 规模 × 1 warmup + 3 measured）

## 文件

| 文件 | 内容 |
|---|---|
| `summary.json` | run 摘要（退出码/耗时/断言数/逐 case 结果） |
| `measurements.json` | 机器可读测量（`environment.git_head = a51e19f2e2609b69f4e90a87da7855538de205c4`，逐样本） |
| `a0_save_cost.stdout.txt` | **原始 stdout**（逐样本 SAMPLE、SCALE DONE、RESULT） |
| `a0_save_cost.stderr.txt` | **原始 stderr**（无格式错误、无 SCRIPT ERROR） |

> 原始输出以 `.txt` 归档，因为仓库忽略 `*.log`；内容与运行时的 stdout/stderr 一致，未做改写。

## 与旧数据的关系

`../a00_g0_measurements.json` 是**上一轮**（`eaf953286fe388f1013d0ef7cd2062ab535016b8`）数据，
仅作历史对照，**不能**作为本轮修复后的证明。本轮以本目录为准。

## 预算（#49 固定，未刷新）

要求逐样本：≤1,500,000 UTF-8 B / 保存 ≤250 ms / 构造+恢复 ≤5000 ms / 读盘 ≤50 ms。
本轮 1000 tick 三个 measured 样本：2,172,752 B，save 374–495 ms，恢复 57,707–69,618 ms，读盘 4–5 ms → **不达标**，交 #49。
