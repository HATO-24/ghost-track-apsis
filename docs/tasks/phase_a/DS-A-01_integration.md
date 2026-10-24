# DS-A-01｜已有实现链的同提交整合验收

状态：WAIT DS-A-00；优先级：P0；父需求：#2/#4；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

玩家看到的观测应由当前模拟几何产生，弹道、快照和 HUD 使用的来源可追溯。P17/P19/P20 的局部成功尚未与 T22 在同一提交验收；现有几何 probe 未明确主动移动 observer，且 noisy 容差缺 sigma 时实际回退到 4 km/4°。

当前来源提交为总队列 §1 的 S0/P17/P19/P20/T22；启动基线必须是 A-00 交付 I0 的完整 SHA。先核对 I0 failure-ledger，只处理尚存缺口，输出 I1。若所需行为已有证据，保留实现并补整合证据。

## 范围与数据契约

允许：A0/既有 integration probes，以及证据指向的 `game_session.gd`（tick、snapshot、geometry provider、kinematics/ballistics 读取段）、`sensor_service.gd` 几何适配、`shell_binder.gd` 的只读消费者适配。catalog/WorldState 只允许修已复现接口缺陷；每项源码修复另提交。frame/epoch 系统化工作留 A-02；存档修复留 A-03～06；不做身份/EW 重构、UI 改版或整类重写。

PhysicsWorld 写位置/速度；EntityCatalog 给内部消费者静态特征；WorldState 只投影。采样顺序为 physics 推进后立即更新 world 投影，再让后续消费者读取同一 tick；需要子时刻的弹体/积分必须标明子步时刻，不能伪装为同 tick。参考系 `bary_rot`，km/km/s/s。

阈值：world 副本位置 `1e-9 km`、速度 `1e-12 km/s`；provider 与独立几何距离 `1e-6 km`、方位圆周差 `1e-6 deg`；采样时差 `1e-6 s`。理由是同源 double 复制/确定性公式，不是拟真传感器精度。为避免大绝对坐标的 Vector3 单精度量化，无噪声 fixture 使用能精确表达的局部数值，独立期望用标量 double 计算。

## 实施与验收矩阵

先保存 I0 上失败证据，再分成“测试/fixture → 最小实现 → 整合报告”提交。

| 场景 | 必须证明 |
| --- | --- |
| 无噪声 geometry fixture | 同一提供者快照：observer `[0,0,0]`、target `[3,4,0]` km，距离为 5；方位按现有 atan2 轴向定义用独立标量公式计算；明确非零速度输入，并核对 provider 速度保留 |
| 观察者与目标分别移动 | 分别经授权的物理 API 改变 observer、target 状态；下一次 tick 的距离/方位/速度输入相应改变。至少 10×60 s，移动前后不能沿用旧 geometry；不能只证明目标在动 |
| 不确定观测 fixture | 注入固定测量（真距离 5 km，测量 5.25 km；方位为真值+0.05°），fixture 明确声明 sigma 为 0.1 km/0.02°；TrackTable/消费者保留当前 schema 支持的测量字段，不将其拉回真值。传递容差 `1e-9`；sigma 在模型/fixture 报告中核对，不在本卡新增 TrackTable sigma 字段，不宣称验证了生产噪声分布 |
| 生产误差参数 | 沿实际 radar/optical backend 取得有来源的 sigma/模型范围；若已有 4σ 判据，必须使用实际 sigma 并记录单位，缺 sigma 明确失败/尚未验证，禁止继续用默认 1 冒充模型参数。若模型未实现随机扰动，只验收它声明的误差量与确定性输出，不捏造统计精度 |
| 实际消费者 | 同一实体 ID 的 physics、world、合成 snapshot、sensor 输入、ballistics 初始状态和 HUD/火控输入逐项列出 source/frame/t。HUD 显示观测/估计，不要求复制 truth；火控授权/威胁仍按既有证据语义 |
| 失败与降级 | 缺实体、observer_missing、target_missing、provider 未就绪、过期 t、未知 frame、physics 失败均有 reason；新观测不得来自未标明的演示值。orbital_sim 无效几何停止本 tick 相关路由；显式 legacy/static 模式允许测试但须标 ADVISORY/不可冒充 LIVE |
| 可见性 | 7 个 scenario 实体在 catalog 归属正确；匿名 contacts 无 friend fallback、无 batch/rcs/radius/has_pd 泄漏；保留 P17 安全事件负例 |

P20 当前 `mark_geometry_unavailable()` 会移除 provider，而 `_geometry_usable()` 的无 provider 分支允许静态观测；这是**待在最终入口复现的分支风险**。先以 orbital_sim 缺 physics/frame mismatch 负例确认实际路由和标签，再决定是否需最小修复；不能把此前“已绑定 provider 失败”修复重复派工，也不能只看 VM reason 就证明消费者安全。

## 命令、交付与限制

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_|a1_entity_metadata|e2e_orbital_sim|physics_world|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-01/full
```

确认 `-Only` 实际选中的 case 列表并记录；0 case/NOT RUN/timeout 不算通过。确定性服务 fixture 之外，必须从正式 `main_menu → v1_hud → ShellBinder → GameSession` 装配，覆盖移动 observer/target、实际消费者及失效几何路由；服务函数通过不能代替这些集成证据。元数据与几何切片应绿；A0-T3 的待修存档项可继续红且逐条列出。Phase 0 6/6、完整回归和 baseline 变化按总队列 §4 报告。

交付 I1 完整 SHA、consumer-source 表、误差参数来源/数值、逐缺陷红→绿日志、矩阵全量报告及未修列表。原日志在 `.test-results/phase-a/cards/DS-A-01/`，PR 带 artifact。Astra 独立核对误差依据、失败路由与玩家真值边界；本卡不宣布整个 Phase A 完成。
