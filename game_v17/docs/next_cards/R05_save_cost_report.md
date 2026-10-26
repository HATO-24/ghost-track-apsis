# R05 · 成本报告使用真实字节与逐样本校验（返修）

> 基线：S7 = `af5b92471a0f12f1ab95c7defda88360e171e277`（A-07 交付）；本卡归属 #39。
> 测量代码 SHA：**`10a39052305654ab03cc3e6c194e40d966f53482`**（`git_head_source=env:A07_HEAD`）。
> 原始数据：[measurements.json](../../benchmarks/a07_save_cost/measurements.json) ·
> [samples.csv](../../benchmarks/a07_save_cost/samples.csv)（已移出 `res://`，避免被当翻译资源导入）。
> 旧数据保留为历史：[measurements_legacy_chars.json](../../benchmarks/a07_save_cost/measurements_legacy_chars.json)（`bytes` 为字符数）。

## 1. 本卡修正的四个报告缺陷

| # | 缺陷（审查指出） | 修正 |
|---|---|---|
| 1 | `bytes` 实为 `String.length()` 字符数，非 UTF-8 字节 | 分列 `chars` / `bytes_utf8` / `file_bytes`，并**逐样本**断言 `file_bytes == bytes_utf8`（落盘交叉核对） |
| 2 | `git_head` 取自空环境变量 → provenance 为空 | `_git_head()` 依次尝试 `GITHUB_SHA`/`A07_HEAD`/`CI_COMMIT_SHA`/`.git`，并记录 `git_head_source` |
| 3 | 仅首个样本做完整恢复校验 | **每一个**非预热样本都跑完整校验（12 样本全绿，150 断言） |
| 4 | 无故障注入证据，无法证明逐样本校验有效 | `A07_FAULT_SAMPLE=<run>` 注入恢复差异 → 驱动**必然 FAIL**（已验证） |
| 5 | CSV 位于 `game_v17/docs/`（res:// 内）可能被导入 | 移到仓库根 `docs/benchmarks/a07_save_cost/` |
| 6 | 「压缩无效 / 每操作 2.09KB 线性」属证据不足结论 | 已删除，改为仅陈述实测现象 |

## 2. 修正后的性能表（3 样本 median；min/max 与全部原始样本见 JSON/CSV）

| ticks | chars（旧口径） | **UTF-8 B（真实）** | 落盘 B | save_state ms | 构造+恢复 ms | 文件读 ms | 写 ms |
|---|---|---|---|---|---|---|---|
| 50 | 421,869 | **426,915** | 426,915 | 80 | 1,171 | 1 | 2 |
| 200 | 1,139,120 | **1,144,166** | 1,144,166 | 199 | 6,338 | 3 | 4 |
| 800 | 1,925,900 | **1,930,946** | 1,930,946 | 338 | 41,355 | 4 | 3 |
| 1000 | 2,160,472 | **2,165,518** | 2,165,518 | 386 | **59,010** | 5 | 5 |

- 与审查方独立核对数字一致（1000 tick = **2,165,518 B**）。
- 计时窗口沿用 A-07：`构造+恢复` 从 `GameSession.new()` 前开始计，**含会话构造**，不含引擎启动与文件读；本报告按此**精确命名**，未悄悄缩短窗口。
- 每规模 = 1 次预热 + 3 次正式样本；表内为 3 个正式样本的 median，**不声称 p95**。

## 3. 与 §3 工程预算的差距（本卡**不**实现优化）

| 项目 | 1000 tick 预算 | 实测 | 结论 |
|---|---|---|---|
| UTF-8 文件 | ≤1,500,000 B | 2,165,518 B | **超 44.4%** |
| `save_state` | ≤250 ms | 386 ms | **超 54%** |
| 构造+内存恢复 | ≤5,000 ms | 59,010 ms | **超 11.8 倍** |
| 文件读取 | ≤50 ms | 5 ms | 达标 |
| 正确性 | 全部保持 | 12/12 样本通过 | 达标 |

预算数字**未被本卡修改**；差距如实报告，由 S01 承接。

## 4. 逐样本恢复正确性（12/12 通过，150 断言）

每个非预热样本（4 规模 × 3）单独校验：
- 相对时间 ≤1e-6 s、frame=`bary_rot`
- physics r/v 全实体逐分量 ≤1e-9
- 事件 seq 为真 int、去重集合不缩小
- 传感器运行态（EMCON/radar/obs/evidence/event 分配器）精确一致
- 与未中断会话再跑 10 tick 后时间/seq 继续一致

**故障注入证据**（`A07_FAULT_SAMPLE=1`）：

```
[A0-A07] FAULT INJECTED at scale 50 run 1
[A0-A07] FAIL scale 50 run 1: FAULT INJECTION — per-sample validation must fail here
[A0-A07] FAULT INJECTED at scale 200 run 1 → FAIL
[A0-A07] FAULT INJECTED at scale 800 run 1 → FAIL
```
→ 注入第 1 个正式样本的恢复差异后驱动**非零退出**，证明逐样本校验不是摆设。

## 5. 测量负载与 provenance

| 项 | 值 |
|---|---|
| 装配入口 | `main_menu → v1_hud → ShellBinder → GameSession`（`DSH_BUILD=orbital_sim`） |
| scenario sha256 | `cdd46e8b074840f34369da415f821ff7247a0806f8b76d86c181c41d9ff3cbf1` |
| seed sha256 | `2de7681ffb1d7578105146d7b7005e7890710e72d9aa7a1512d5c93431333760`（28 key） |
| dt / scale / paused | 1.0 s / 1.0 / false |
| 控制操作 | 每 50 tick 固定序列（LD 发送→optical 通道→IR 通道→EMCON 翻转） |
| 规模 | 50 / 200 / 800 / 1000（`A07_SCALES` 可覆盖；Q03 复用） |
| 环境 | Windows 10.0.26200 / Ryzen 7 7435H (16) / Godot 4.7.2 headless / 静态内存 109.5 MB |
| 代码 SHA | `10a39052305654ab03cc3e6c194e40d966f53482` |
| 安全超时 | 1800 s（只防御失控，**不是**性能预算） |

## 6. 仍存在的限制

- 未运行 Linux/macOS、非 headless 渲染；未测 >1000 tick（Q03 承接）；
- 3 样本不足以声称 p95；
- `tick_total` 含传感器/物理/事件，不是纯存档成本；
- 109.5 MB 是进程静态内存读数，**不是**机器 RAM；
- 未实现 checkpoint/压缩（S01 承接），本卡只提供可信测量与报告。

## 7. 运行命令

```powershell
# 正式测量（代码 SHA 通过环境变量记录，避免空 provenance）
$env:A07_HEAD = (git rev-parse HEAD).Trim()
pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/next-cards/R05/benchmark

# 故障注入自检（故意让第 1 个正式样本失败）
$env:A07_SCALES = "50"; $env:A07_FAULT_SAMPLE = "1"
& $env:GODOT_BIN --headless --path ./game_v17 --script res://tests/a0_save_cost_probe.gd   # 期望非零退出
```
