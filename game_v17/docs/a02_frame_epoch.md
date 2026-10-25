# DS-A-02 · frame、历元与消费者时间来源（I2）

> 基线：**I1** = `26f1d5398a4ed6654b057f23a27819e4bf700b31`（A-01 交付）。
> 交付 **I2**：见执行报告给出的完整 SHA。
> 入口：`main_menu → v1_hud → ShellBinder → GameSession`（`DSH_BUILD=orbital_sim`）。

## 1. 时间基准（本卡确立）

| 基准 | 含义 | 来源 | 禁止 |
|---|---|---|---|
| `t_s` | **相对模拟秒**（会话时钟） | `TimeService.tick()` | 不得当作日历/绝对时间 |
| `calendar_epoch_utc` | 场景日历历元（`2193-04-11T08:00:00Z`） | **scenario JSON 唯一来源**，经 `_parse_utc_epoch()` 校验 | 不得从 760.8 猜出 |
| `calendar_epoch_unix_s` | 上述历元的 Unix 秒 | 由 UTC 字符串解析 | 不得与相位秒混用 |
| `epoch_s`（=760.8） | **CR3BP 动力学相位基准** | 既有模型常数 | **不是** Unix epoch |
| `phase_basis` | `cr3bp_phase_s`（显式标签） | `epoch_meta()` | 不得被 UTC 秒替换 |

绝对日历时刻 = `calendar_epoch_utc + t_s`；动力学相位 = `epoch_s + t_s`。
两者在 `epoch_meta()` 中分别标为 `calendar_*` 与 `phase_*`，并带
`raw_epoch_s_is_unix=false` 与 `calendar_vs_phase_note` 说明。

### 1.1 旧 seed / 非法输入策略

| 输入 | 行为 | 标记 |
|---|---|---|
| scenario 有合法 UTC | 正常解析 | `epoch_source=scenario`、`epoch_known=true` |
| 无 UTC（旧 seed） | **保留原时间行为**，不伪造日期 | `epoch_source=legacy_unknown`、`epoch_unknown=true`、`calendar_now_utc=""` |
| 非法 UTC | `TimeService` **not ready** + 显式错误 | `epoch_source=invalid` |
| 未知 frame | 转换返回 `ok=false, reason=invalid_frame` | 不静默当成 `bary_rot` |

## 2. 修复的真实缺陷：集中转换器单精度量化

**红证据**（修复前，`physics_world._to_bary_rot/_from_bary_rot` 走 `Vector3`）：

```
case=eml1 axis=v1 err_kmps=0.00000001907349   (阈值 1e-9 km/s)
```

EML1 大坐标（~3.2e5 km）经 `Vector3`（单精度）往返后速度误差 ~1.9e-5 km/s，
不满足「双精度确定性转换」阈值。

**修复**（`e689ecc`）：在集中转换器 `cislunar_physics.gd` 增加**双精度标量**路径
（`*_arrays()`，公式与既有 Vector3 版一致），`physics_world` 适配层改用它；
**Vector3 版本保留给显示层，阈值未扩大**。

**绿证据**：`origin` / `near` / `eml1` 三个坐标的原点与大坐标往返均
位置 ≤1e-6 km、速度 ≤1e-9 km/s（`earth_eci` 与 `earth_rot` 两条路径都测）。

## 3. 消费者 frame/source 表（`session_time_frame_meta()`）

| 消费者 | frame | source | 采样阶段 |
|---|---|---|---|
| PhysicsWorld | `bary_rot` | `physics_world`（唯一运动学权威） | tick 内推进后 |
| WorldState 投影 | `bary_rot` | `physics_world(copy)` | physics 推进后立即 |
| 合成 snapshot | `bary_rot`（`physics_frame` 块） | `session.snapshot` | 读取时 |
| Sensor 几何 | `bary_rot` | `physics_world` | step 后按当前 t |
| Ballistics 初始状态 | `bary_rot` | `physics_world` | 发射时读 `state_source()` |

另有 `physics_time_ok`（physics t 与 `t_s` 差 ≤1e-6 s）、`runtime_units`
（km / km/s / s）、`seed_frame`、`frame_conversion`
（`applied`/`source`/`conversion_count`/`converted`/`skipped`/`origin`/`reason`）。

## 4. L1 初始化转换只做一次

`frame_conversion.conversion_count == 1`、`applied == true`、`source == seed`，
且 `runtime_frame` 仍为 `bary_rot`（L1 相对 seed 只在初始化适配层转换一次）。

## 5. 存读档元数据

`TimeService.snapshot()` 携带 `epoch`（`epoch_meta()`），`GameSession.save_state()`
保存 `_seed`（含 `epoch` 与 `time`），因此读档后：

- `calendar_epoch_utc` / `epoch_source` / `calendar_epoch_unix_s` **精确一致**；
- `t_s` 一致、`runtime_frame` / `seed_frame` 一致；
- 读档后再推进 10 tick，相对时间**恰好 +600 s**（≤1e-6 s）。

> **真实 HUD 会话的 `save→load` 仍受 `replay send_comms 失败：no_route` 影响**
> （DS-A-06 范围）。本卡在探针中**显式记录该限制**（INFO），并用同 seed 的干净 fixture
> 验证历元/frame 元数据往返；不把该缺陷写成已验证。

## 6. 探针与结果

新增 `integration.a0_frame_epoch`（`a0_frame_epoch_probe.gd`，61 断言）：

| 组 | 断言 |
|---|---|
| 历元单一来源 | scenario UTC 精确匹配、`epoch_source=scenario`、unix 秒精确、`epoch_known` |
| 相位基准分离 | `phase_basis=cr3bp_phase_s`、`phase_epoch_s=760.8`、`raw_epoch_s_is_unix=false`、`phase_abs ≠ cal_unix` |
| 绝对日历时间 | `calendar_now == epoch + t_s`（精确 UTC 串）；+60 s 后精确对应 |
| 同刻与单位 | `physics_t == t_s`（1e-6 s）、`bary_rot`/km/km/s/s |
| 消费者表 | 5 个消费者均声明 frame + source |
| L1 转换 | `conversion_count==1`、`applied`、`source=seed`、运行态仍 bary_rot |
| 转换器精度 | origin/near/EML1 × (eci, rot) 往返 1e-6 km / 1e-9 km/s |
| 存读档 | 历元/相对时间/frame/source 保留；+10 tick 精确 +600 s |
| 可重复性 | 同 seed 同命令 → 相同 `t_s`/epoch/frame meta |
| 暂停/缩放 | 暂停不推进；`scale=2` 恰好 +120 s；单调 |
| 负例 | 非法 UTC 拒绝（`invalid`）、旧 seed `legacy_unknown` 且不伪造日期、未知 frame 拒绝、未知玩家目标无 truth 坐标 |

**真实结果**（提交见执行报告）：

```
Phase A gate:  total=3 pass=2 fail=1   (A0-T1 45/0、A0-T2 30/0、A0-T3 37/4)
Phase 0 gate:  total=6 pass=6 fail=0
Full matrix:   total=80 pass=71 fail=9
  BASELINE CHECK:         known_fail=8 new_fail=0 drift=0 complete=true
  PHASE A BASELINE CHECK: known_fail=1 new_fail=0 drift=0 complete=true
```

矩阵规模 **80 cases**（75 常规 probe + 1 e2e + 4 boot smoke），无重复；`phase0=6`、`phaseA=3` 未变。
**9 个 FAIL = 8 个 Phase 0 历史失败 + 1 个 Phase A 待修（A0-T3 存档切片）**，逐条可见；
**不是「全部通过」**。

## 7. 提交拆分（任务卡要求）

| 提交 | 内容 |
|---|---|
| `ce10168` | **历元元数据**：`time_service.gd` 解析/校验/元数据/旧 seed 策略 |
| `e689ecc` | **frame/来源适配**：集中转换器双精度路径 + physics 适配层 + binder 传历元 |
| `8058d07` | **Session 读取和存档元数据**：seed 白名单 + `session_time_frame_meta()` + 快照随存 |
| （本提交） | 探针 + 矩阵登记 + 本报告 + `test_matrix.md` |

## 8. 未覆盖 / 尚未验证

- 真实 HUD 会话存读档（`no_route`）→ DS-A-06；
- 事件 seq 类型、传感器运行态 → DS-A-03 / A-05；
- 旧档迁移与超环形缓冲去重 → DS-A-04；
- 长时存档成本 → DS-A-07；
- 未验证：Linux/macOS、非 headless 渲染、JPL 星历（本卡**没有**提升模型精度）。

## 9. 命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_frame_epoch|core_time_event|cislunar_physics|physics_world|a0_track_truth|a0_sensor_geometry|session_probe|save_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-02/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-02/full
```
