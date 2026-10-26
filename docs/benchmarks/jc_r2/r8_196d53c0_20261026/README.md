# R8 长测与满载边界原始证据（JC-A00 / #56）

- 测量代码 SHA（40 位）：`196d53c04b85ef46305e96e88477588b54820bc0`
- 环境：Godot 4.7.2；Windows；headless；2026-10-26
- 长测命令：`pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/jc-r2/JC-A00/r8/benchmark`
- 长测结果：**PASS 90/0，1047.6 s**，12 样本（4 规模 × 1 warmup + 3 measured）

## 文件

| 文件 | 内容 |
|---|---|
| `summary.json` | run 摘要 |
| `measurements.json` | 机器可读测量（`environment.git_head = 196d53c04b85ef46305e96e88477588b54820bc0`） |
| `a0_save_cost.stdout.txt` | 原始 stdout（.txt 以纳入 Git；仓库忽略 *.log） |
| `a0_save_cost.stderr.txt` | 原始 stderr |
| `saturation/saturation.stdout.txt` | **G0-3 满载边界**：50 tick + `A07_SATURATION_CHECK=1`，PASS 29/0 |
| `saturation/saturation.stderr.txt` | 对应 stderr |

## G0-3 满载边界结论

- 「满载历史下正文篡改仍被逐 tick 比较发现」→ PASS，violations 含
  `comms.events.new` 且 first 明确显示 `SAT_ORIGINAL` vs `SATURATED_TAMPERED`；
- 对照「满载历史 + 正文一致 → 逐 tick 比较为空」→ PASS（violations=[]）。
- 说明按稳定序号水位（`seq`/`id`/`event_id`）提取新增记录，不再依赖滚动数组长度。

## 预算（#49 固定，未刷新）

逐样本要求 ≤1,500,000 UTF-8 B / 保存 ≤250 ms / 构造+恢复 ≤5000 ms / 读盘 ≤50 ms。
本轮 1000 tick 中位：2,172,752 B / save 374 ms / 恢复 60,244 ms / 读盘 5 ms → **不达标**，交 #49。

旧数据 `../r7_a51e19f2_20261026/` 与 `../a00_g0_measurements.json` 保留为历史对照。
