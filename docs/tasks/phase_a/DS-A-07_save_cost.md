# DS-A-07｜正式会话的长时存档成本标定

状态：WAIT I6；优先级：P0 设计预算；父需求：#2.5；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

用同一正式会话量化日志重放造成的体积/延迟增长，为下一张优化卡提供有依据的预算。55 曾测 50/200/800 tick 为 310899/794249/1656569 B、load 1.1/5.3/38.5 s；T22 的 1000×1s 性能段是默认 demo seed，37ms/25213B 属不同轻量负载。两组历史数字不直接比较，也不作为本轮通过证据。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`、T22=`8bf7517cef32ca14699cca1b048ef3398b9eb88d`。执行基线必须为 A-06 的 I6 完整 SHA。本卡只测量、提交预算建议和下一卡规格；不引入 checkpoint、压缩或跳过 tick replay，不声称已满足尚未制定的产品性能预算。

## 范围与固定负载

允许测试/benchmark driver、独立 benchmark manifest、测量文档。运行时只允许必要的只读观测接口，若需源码接口单独提交并解释。新增 `a0_save_cost_probe.gd`，在 `game_v17/tests/benchmark_matrix.json` 登记 case=`integration.a0_save_cost`；复用 runner 已有 `-Matrix` 参数，不加入默认 `probe_matrix.json`，不给普通全量矩阵增加长时负担。manifest 沿用现行 schema，登记实际脚本、PASS/FAIL 标记和超时。

基准从正式 HUD orbital_sim 入口装配，固定 scenario 文件 hash、完整 seed 内容/hash、引擎版本、`dt=1.0 s`、time scale=1、无暂停，系统/传感器状态和每 N ticks 的控制操作序列写入 fixture。使用有限弹药、正常授权。50/200/800/1000 tick 每个规模从全新同 seed 会话独立开始；默认 demo 可作为第二负载，独立列报。

权威/单位/可见性沿用 I6：TimeService 模拟秒，PhysicsWorld bary_rot/km/km/s，EventBus/传感器各自分配器，计时用单调时钟的 ms。测量输出不进入玩家信息；不可通过关系统或删事件达到性能目标。

## 测量、正确性和预算交付

1. 每规模先预热一次，再做 3 次独立测量；同机同构建，记录 CPU/RAM/OS/磁盘、渲染/headless、Godot 标识、环境开关、完整 SHA、fixture hash。报告原始样本、median/min/max，不用 3 样本声称可靠 p95。
2. 记录实体数、bus 可见事件/已用 ID 数、log 操作数、序列化字节，分开计 save_state、文件写入、文件读取、load_state/replay 耗时，以及 tick 总耗时；测量是否含导入/启动说明清楚。不要把引擎启动时间混入 load_state。
3. 每次恢复后检查 frame/t、physics/world、事件 seq/去重、传感器状态，并与未中断会话再运行相同 10 ticks；数值阈值沿总队列 §3、A-03/A-05。性能样本即使快速，正确性失败也标 FAIL。
4. 产出成本曲线/表（CSV/JSON），按规模比较增长和主要贡献；超时和失败样本保留，不删慢样本。驱动安全超时先设 1800s，仅用于终止失控测试，**不等于产品性能预算**。
5. 基于测量提交下一优化卡的具体建议：明确参考硬件、目标负载/时长、存档 bytes、save/load 最大耗时、正确性门槛与依据，并区分“观察到的基线”和“待审查预算”。经项目负责人/Astra 取舍后把具体数字冻结到优化卡，再进入实现；本卡不自行承诺几秒读档。

## 命令与验收

新增 driver 并确认 `-Only` 实际选择 1 个 benchmark 后运行：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-07/benchmark
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-07/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-07/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-07/full
```

先用同样的 `-Matrix/-Only` 配合 `-List` 确认恰好选中 1 case，再去掉 `-List` 实跑；默认 `-List` 必须不包含该 benchmark。0 case 或静默 NOT RUN 不算完成。正确性 probes 仍全执行。

交付 benchmark 完整 SHA、fixture/provenance、原始 JSON/CSV、环境与命令、体积/耗时表、恢复正确性、预算建议和下一优化卡的进入条件。记录未运行平台/渲染/长于1000 ticks的限制。所有代码/测量对应同提交；回归和 baseline 变化按总队列 §4 留证。Astra 独立核对负载可比、计时分项和预算依据；通过本卡只表示测量完成。
