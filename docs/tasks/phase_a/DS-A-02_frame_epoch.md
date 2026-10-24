# DS-A-02｜frame、历元和消费者时间来源

状态：WAIT I1；优先级：P0；父需求：#2.3；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

同一模拟时刻的空间状态在各消费者处有一致、可解释的坐标和时间。55 的 C8 记录 scenario `2193-04-11T08:00:00Z` 未被主线消费、TimeService 默认 epoch_s=760.8、prelude/L1 与 bary_rot 语义交叉；I1 是否仍有这些缺口必须先检查。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`，实现链参见总队列 §1；执行基线为 A-01 的 I1 完整 SHA。输出 I2。若 I1 已修某项，附证据后从本卡修复范围移除。

## 边界与契约

允许：`time_service.gd`、`game_session.gd` 的 seed/frame/meta/kinematics/snapshot 与相应 save/load 元数据小段、`shell_binder.gd` 适配、相关 schema/docs/probes。需要改集中转换器时只修已复现的适配缺陷，不改 CR3BP/RK4 积分、物理常数、时步、轨道相位模型，不引入 JPL 星历。事件和 SensorService 持久化由后卡负责。

TimeService 写相对 `t_s`；PhysicsWorld 写状态，物理 `t` 与 session `t_s` 误差 ≤`1e-6 s`。scenario UTC 历元经验证后只由一个会话元数据来源持有；绝对日历时刻=该历元+相对秒。先查 `epoch_s` 现有用途，不能把 760.8 猜成 Unix epoch，也不能用 UTC 秒数直接替换 CR3BP 的相位时刻。日历历元与动力学相位基准分别标明，后者沿用当前模型。

运行态位置 `bary_rot`、km、km/s；`earth_eci/earth_rot` 通过既有集中转换器；L1 相对 seed 仅在初始化适配层转换一次，并标 applied/source。带 physics 的产品路径不得把未转换 world 位置标为 bary_rot。无 physics 的 legacy 使用其声明语义。稳定 ID 贯穿内部链，新增来源字段不得把 truth 坐标交给未知 contacts。

同帧投影阈值沿总队列 §3。集中转换器的独立往返 fixture 在原点附近及 EML1 大坐标各测试：位置误差 ≤`1e-6 km`、速度 ≤`1e-9 km/s`，理由为双精度确定性转换，不适用于 Vector3 单精度显示值；如现有转换确有量化缺陷，先红证据并修适配精度，禁止扩大门槛。UTC 字符串和整数历元标签精确一致，时间增量误差 ≤`1e-6 s`。

## 步骤与验收

1. 先输出 I1 实测的 frame/time/epoch 表，覆盖 scenario、session clock、physics、world 投影、sensor 输入、ballistics 初始输入、snapshot 与 HUD/火控 VM；每项有取值、来源和采样阶段。
2. 增加独立 `a0_frame_epoch_probe.gd` 并登记矩阵（不改 phase0 的 6 项）。明确缺历元旧 seed 的兼容策略：保留原时间行为并标 `epoch_unknown/legacy`；显式非法 UTC/未知 frame 拒绝，不能静默变成默认坐标或伪造日期。
3. 分别提交“历元元数据”“frame/来源适配”“Session 读取和存档元数据”，保持后续 save 卡有明确接口。
4. 正例：scenario UTC+60s 精确对应，模拟暂停/scale 后相对时间单调；同一 seed/命令重复运行一致；bary_rot 与两种支持 frame 往返；L1 初始化只转换一次；存读档保留相同历元、相对时间、frame 和来源，并再推进 10 ticks 验证。
5. 负例：缺失/未知 frame、混合 frame、过期 snapshot、非法历元、重复初始化；必须明确失败/兼容标记，不向观测路由旧演示值。验证 full/prelude 仍可启动，且未知玩家目标不会取得新增 truth 字段。

## 命令与交付

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_frame_epoch|core_time_event|cislunar_physics|physics_world|a0_track_truth|a0_sensor_geometry|session_probe|save_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-02/full
```

新 frame/epoch probe 及受影响既有物理/时间用例应通过；存档未修缺陷仍逐项登记。所有回归/计数漂移按总队列 §4 处理。交付 I2 完整 SHA、时间基准/转换文档、旧 seed 策略、红→绿证据、消费者字段表和同提交全量报告，日志目录如命令。Astra 独立审查 UTC 与动力学相位未混用、跨档和大坐标精度；本卡没有提升模型为高精度星历。
