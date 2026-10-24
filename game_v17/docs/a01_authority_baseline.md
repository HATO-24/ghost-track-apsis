# Phase A-01 · 物理与信息权威回归基线（A0-T1/T2/T3）

> 基线：GitHub `main` 提交 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`
> （`Merge Phase A0 physics and information authority audit`）。
> 分支 `phase-a01/authority-baseline`，worktree `D:\gt_a01`。
>
> 关联：Issue #2、Issue #4、`docs/55_PhaseA0_物理与信息权威基线调查.md`
>
> **本任务只建测试与独立门禁，不修运行时代码。** 三个探针编码的是 Phase A0 已定位的
> 权威链缺陷；它们**当前按设计失败**，供 Issue #2/#4 逐项转绿。

## 1　三个 integration 探针

全部从**真实产品入口** `main_menu → v1_hud → ShellBinder → GameSession`
（`DSH_BUILD=orbital_sim`）驱动，不使用手工拼装的服务替代。单项超时 180 s。

| Probe | 矩阵 id | 断言 | 当前结果 | 覆盖 |
|---|---|---|---|---|
| `a0_track_truth_authority_probe.gd` | `integration.a0_track_truth_authority` | 40 | **PASS=39 / FAIL=1**，exit 1 | A0-T1 航迹 vs 物理真值 |
| `a0_entity_metadata_pipeline_probe.gd` | `integration.a0_entity_metadata_pipeline` | 22 | **PASS=14 / FAIL=8**，exit 1 | A0-T2 元数据管道 |
| `a0_save_roundtrip_authority_probe.gd` | `integration.a0_save_roundtrip_authority` | 33 | **PASS=29 / FAIL=4**，exit 1 | A0-T3 存档往返 |

### 1.1 A0-T1 · 航迹 vs 物理真值权威

检查项：
- 同一 tick：`track_table.t == physics.t == session now_s`（容差 1e-6 s）；
- 最新观测批次的 `t == physics.t`（同刻）；
- **航迹距离 vs PhysicsWorld 真值距离，误差 ≤ 0.5 km**；
- 身份/威胁 vs scenario truth（证据派生，不得凭空等于 truth）；
- 来源/batch/entity_id 可追溯；
- TrackTable 单写者（`current_writer()` 唯一，二次 claim 必须 `writer_conflict`）；
- 帧与单位：`bary_rot` / km / km/s / s。

**预期失败（1 项）**：航迹 range 仍来自 `ShellBinder._sensor_config()` 的静态传感器几何
（harmattan 20 km、l1_station 10 km），而 PhysicsWorld 真值是 420.20 km / 90.00 km，
误差 ~400 km / ~80 km。

### 1.2 A0-T2 · 实体元数据管道

对 7 个 scenario 实体逐项检查 `side / identity / batch / rcs_m2 / radius_km / has_pd`
在 5 个层级（PhysicsWorld → WorldState → snapshot → track → contacts）的传递，
共 5×7×6 = 210 个单元格。

规则：
- 缺失值必须显示为明确的 `unknown`（或空 + 明确 reason）；
- **禁止静默回退为 `friend`**。

**预期失败（8 项）**：
- WorldState / snapshot 实体不含这些字段（只保留核心 8 键）；
- contacts 对 6/7 实体静默回退 `side=friend` / `identity=friend`
  （ferry、raider_2、skiff、watchtower 等，truth 分别是 neutral/hostile）；
- contacts 无 batch（7/7）；
- 元数据传递矩阵 203 处违例。

### 1.3 A0-T3 · 存档往返权威

检查项：
- physics/world/track 数值往返误差 ≤ 1e-9；
- **整数类型不漂移**（事件 `seq` 读回后仍是 int）；
- SensorService 运行态（EMCON / radar / channels）持久化；
- `save → load → save` canonical equality；
- 1000 tick 存档性能（体积/耗时，INFO 证据）。

**预期失败（4 项）**：
- 真实 HUD session `save→load` 失败（`replay send_comms 失败：no_route`，独立的 comms replay 缺陷）；
- 事件 `seq` int→float 漂移（`1.0/2.0/...`，save payload + loaded bus 共 10 处）；
- 存档 payload 无 `sensor_service` 运行态；
- 因此 EMCON/radar 读档后丢失（存 emcon=true/radar=false，读回 emcon=false/radar=true）。

> 注：为不让 live session 的 comms replay 缺陷掩盖 physics/world/track 往返结论，
> 探针另用同 scenario seed 的干净 session 完成 1e-9 往返检查；live session 的失败
> 作为独立断言保留可见。

## 2　独立 Phase A 门禁

### 2.1 `gates.phaseA`（与 `gates.phase0` 分开）

`game_v17/tests/probe_matrix.json` 新增：

```json
"phaseA": [
  "integration.a0_track_truth_authority",
  "integration.a0_entity_metadata_pipeline",
  "integration.a0_save_roundtrip_authority"
]
```

`gates.phase0` **完全未改**（仍是 6 个 case）。

运行：
```powershell
pwsh ./run_tests.ps1 -Gate phaseA -Ci
```

### 2.2 独立的 Phase A 预期失败基线

新增 `game_v17/tests/phasea_baseline_failures.json`（schema 仍是
`known_baseline_failures.v1`，但**独立文件**）：

| case | expected_exit | expected_pass | expected_fail |
|---|---|---|---|
| `integration.a0_track_truth_authority` | 1 | 39 | 1 |
| `integration.a0_entity_metadata_pipeline` | 1 | 14 | 8 |
| `integration.a0_save_roundtrip_authority` | 1 | 29 | 4 |

**`game_v17/tests/known_baseline_failures.json` 完全未改**（仍是 8 项 Phase 0 历史失败）。

### 2.3 runner 新增 `-BaselineExtra`

`run_tests.ps1` 新增可选的**第二份** baseline 文件参数：

```powershell
pwsh ./run_tests.ps1 -Ci `
  -Baseline game_v17/tests/known_baseline_failures.json `
  -BaselineExtra game_v17/tests/phasea_baseline_failures.json
```

- 两份基线**互相排除**对方声明的 case（不会把对方的预期失败算成自己的 `new_fail`）；
- 计数分开输出：`known_phase_a / new_fail_phase_a / drift_phase_a / unverified_phase_a /
  unselected_phase_a / phase_a_baseline_complete`；
- 判定同样 fail-closed：Phase A 预期失败必须**精确匹配**计数，否则红灯；
- `-BaselineExtra` 必须与 `-Baseline` 同时使用；
- **Phase 0 语义完全未变**：`-Gate phase0` 不读任何基线文件。

summary.json 新增独立 `phase_a_baseline` 块（`baseline` 块结构未变）。

## 3　CI

`.github/workflows/tests.yml` 新增第三个 job：

```
Phase A gate (A0-T1/T2/T3 authority probes; RED BY DESIGN on the current baseline)
```

- 运行 `-Gate phaseA` + 两份基线 + `-AllowPartialBaseline`（gate 只选 3 个 case，
  所以 Phase 0 基线必然 unselected；partial 仅用于本地等价语义，**不改变** Phase A 的
  fail-closed 判定）；
- 然后**断言预期失败形状**：3 个探针必须都执行、都 exit 1、pass/fail 计数精确匹配
  声明基线；任一偏差（NOT RUN / 计数漂移 / 悄悄转绿）→ 该 step 抛错；
- 断言通过后显式 `exit 1`（**故意红**，因为权威链未修）；
- artifacts：`phasea-gate-results-<run_id>-<attempt>`；
- **没有** `continue-on-error`、没有跳过、没有放宽断言。

`full-matrix` job 现在同时传两份基线，因此全量矩阵可同时复核：
- Phase 0：`known_fail=8 new_fail=0 drift=0 complete=true`；
- Phase A：`known_phase_a=3 new_fail_phase_a=0 drift_phase_a=0 complete=true`。

## 4　本地真实运行结果（base `4b0b102`）

### 4.1 Phase A gate

```
total=3  pass=0  fail=3  timeout=0  not_run=0  duration=13.5s
integration.a0_track_truth_authority   FAIL exit=1  39/1
integration.a0_entity_metadata_pipeline FAIL exit=1  14/8
integration.a0_save_roundtrip_authority FAIL exit=1  29/4
```

### 4.2 Phase 0 gate（未受影响）

```
total=6  pass=6  fail=0  timeout=0  not_run=0
RESULT: ALL RUN CASES PASS
```

### 4.3 全量矩阵（两份基线）

```
total=75  pass=64  fail=11  timeout=0  not_run=0
BASELINE CHECK: known_fail=8 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
PHASE A BASELINE CHECK: known_fail=3 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```

矩阵规模：75 = 72 原有 case + 3 个 A0 探针。
**11 个 FAIL = 8 个 Phase 0 历史失败 + 3 个 Phase A 预期失败**，逐条可见。
**不是「全部通过」**；Phase 0 历史失败没有增加、没有被隐藏。

## 5　边界与禁止事项

- ✅ 不修改游戏运行时代码或场景（`git diff` 只含 tests/docs/runner/workflow）
- ✅ 不删除测试、不放宽断言、不跳过失败
- ✅ 不改变 Phase 0 gate 语义与 `gates.phase0` 成员
- ✅ 不改变默认 `full` profile
- ✅ 不修改 `known_baseline_failures.json`（8 项历史失败保持原样）
- ✅ 不接入 O'Neill 模型归档 PR #21 的文件
- ✅ 未做 #2/#4 的实际修复

## 6　未覆盖 / 尚未验证

- **未验证**：Linux/macOS 运行、非 headless 渲染、真实 RF/光学模型；
- **未覆盖**：IFF 状态机、EW 效果、传感器整体重构、O'Neill 模型归档；
- 三个探针的 180 s 超时只在本地实测（最长 ~2.8 s），CI 上未单独验证超时行为；
- Phase A gate 的「预期失败形状」断言依赖精确 pass/fail 计数；任何运行时修复都会
  使该断言失败，**这是设计意图**——修好后必须同步刷新 `phasea_baseline_failures.json`
  的期望值（并在 PR 中说明计数变化原因）。

## 7　验证命令

```powershell
# 三个探针（Phase A gate）
pwsh ./run_tests.ps1 -Gate phaseA -Ci

# Phase A gate + 两份基线（可复核预期失败形状）
pwsh ./run_tests.ps1 -Gate phaseA -Ci `
  -Baseline game_v17/tests/known_baseline_failures.json `
  -BaselineExtra game_v17/tests/phasea_baseline_failures.json `
  -AllowPartialBaseline

# Phase 0 gate（必须仍是 6/6）
pwsh ./run_tests.ps1 -Gate phase0 -Ci

# 全量矩阵（8 个历史失败 + 3 个 Phase A 预期失败，逐条可见）
pwsh ./run_tests.ps1 -Ci `
  -Baseline game_v17/tests/known_baseline_failures.json `
  -BaselineExtra game_v17/tests/phasea_baseline_failures.json
```
