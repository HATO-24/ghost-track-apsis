# R7 长测原始证据（JC-A00 / #56）

- 被审/测量代码 SHA（40 位）：`a51e19f2e2609b69f4e90a87da7855538de205c4`
- 运行时间：2026-10-26；Godot 4.7.2；Windows；headless
- 命令：`pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/jc-r2/JC-A00/r7/benchmark`
- 结果：**PASS 90/0，860.5 s**，12 个样本（4 规模 × 1 warmup + 3 measured）
- 证据文件：
  - `summary.json`：run 摘要（含退出码/耗时/断言数）
  - `measurements.json`：机器可读测量（含 environment.git_head=`a51e19f2e2609b69f4e90a87da7855538de205c4`）
  - `a0_save_cost.log`：完整 stdout（含逐样本 SAMPLE、SCALE DONE、RESULT）
  - `a0_save_cost.stderr.log`：stderr（无格式错误/无 SCRIPT ERROR）
- 与旧数据的关系：`../a00_g0_measurements.json` 是**上一轮**（`eaf953286fe388f1013d0ef7cd2062ab535016b8`）的数据，
  仅作历史对照，**不能**作为本轮修复后的证明。本轮以本目录为准。
- 预算（#49 固定）：≤1,500,000 B / 保存 ≤250 ms / 构造+恢复 ≤5000 ms / 读盘 ≤50 ms。
  本轮仍不达标（见 measurements.json），交 #49，未刷新阈值。
