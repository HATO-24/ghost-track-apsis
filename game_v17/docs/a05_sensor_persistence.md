# DS-A-05 · 传感器运行态持久化与续跑（I5）

> 服务基线 **I1** = `26f1d5398a4ed6654b057f23a27819e4bf700b31`；Session 接入基线 **I4** = `b04726641057aa80ccc83829e8da00b973f2f733`；交付 **I5** 见执行报告。

## 1. 复现的真实缺陷（修复前，来自 A0-T3 修复前日志）

```
[A0-T3] INFO SENSOR fixture: save_has_sensor_service=false
[A0-T3] FAIL SensorService runtime state persists across save/load
        (violations=[{"field":"radar_enabled","actual":true,"expected":false},
                     {"field":"emcon","actual":false,"expected":true}, …])
[A0-T3] BASELINE: saved emcon=true radar=false; loaded emcon=false radar=true; save_has_sensor=false
```

即：存档里**没有** sensor 运行段；读档后 EMCON/雷达回到 seed 默认，通道丢失。

## 2. 状态契约（新增）

### 2.1 `optical_ir_channel.export_state()/import_state()`（`v17.optical_ir.state.v1`）
持久化：`enabled`、`t`、每个通道的**完整后端运行态**（`kind`/`target_id`/`status`/`progress`/
`samples`/`sample_acc`/…）。
导入：先校验 schema/version/时钟/通道数组（`kind`、`target_id` 必填、key 不重复），
再一次提交；失败不改后端。

### 2.2 `sensor_authority.export_backend_state()/import_backend_state()`
委托给 `optical_ir` 后端；`legacy` 后端显式返回 `backend=legacy`（无可续跑通道状态，不伪装）。

### 2.3 `sensor_service.export_state()/import_state()`（`v17.sensor_service.state.v1`）
```
{t, dt_last, step_count,
 controls:{selected_target, radar_enabled, emcon, optical_backend},
 allocators:{obs_seq, evidence_seq, event_seq},
 dedup:{optical_evidence_seen:[keys]},
 backend:<optical_ir state | null>,
 channels_view:[…],           # UI 视图，仅交叉校验
 history:{observations, evidence, events}}   # 作为数据保存，读档后不重放
```

## 3. 字段分类（持久化 / 重建 / 可丢弃及理由）

| 字段 | 处理 | 理由 |
|---|---|---|
| `emcon`、`radar_enabled`、`selected_target`、`optical_backend` | **持久化** | 直接决定下一次输出 |
| `t`、`dt_last`、`step_count` | **持久化** | 时钟连续性；与 geometry 同刻校验 |
| `_obs_seq`/`_evidence_seq`/`_event_seq` | **持久化**（整数契约） | 避免恢复后 ID 重复 |
| `_optical_evidence_seen`（去重键） | **持久化** | 避免恢复后重复证据 |
| `optical_ir.channels`（status/progress/samples/…） | **持久化** | 通道可续跑；比 UI 缓存更底层 |
| `observations`/`evidence`/`events` 历史 | **持久化为数据，不重放** | 诊断视图一致；避免把已恢复证据再喂 TrackTable |
| `observer`、`mounts`、`targets`、`snapshot`、`config` | **重建**（原权威） | 静态元数据不能变成第二份可写真值 |
| `_authority`、`_iff`、geometry provider | **重新注入** | 对象/Callable 不可 JSON 化 |
| `_last_channels`（UI 缓存） | 保存为 `channels_view` 仅交叉校验 | 不作为恢复依据（禁止靠画面列表伪造） |

## 4. 恢复顺序（Session）

`boot(seed)` → `replay(log)` → `world_physics_sync("load")` →
`sensor_service.import_state()` → **静默**重绑定 geometry provider（`_bind_sensor_geometry(true)`）→
同刻校验（geometry `t` vs session `t_s` ≤1e-6 s）。
`ready` 之后才允许产生新的传感器输出。已恢复的证据/观测**不**路由进 TrackTable。

> 重绑定使用 `quiet` 路径：读档期的审计事件不写入已恢复的历史/分配器，否则
> `save→load→save` 会出现额外事件（实测曾 +1 `geometry_bind`）。

## 5. 探针与结果

新增 `integration.a0_sensor_persistence`（`a0_sensor_persistence_probe.gd`，**69 断言**）：

| 组 | 断言 |
|---|---|
| 主动变更 | EMCON 翻到 seed 相反值、雷达随之反向、optical+IR 启动、3 tick 后通道 `progress/status` 非初始 |
| 内存 + 真实文件往返 | 控制值/选择目标/时钟/step_count/三个分配器/去重键数全部恢复；**后端通道内容逐字段一致**；geometry 重新绑定到 physics、frame=bary_rot、同刻 ≤1e-6 s；恢复报告 `time_ok=true` |
| 续跑 10 tick | 时钟对齐、分配器单调不回退、无重复观测 ID；**EMCON 开启期间雷达发射事件=0**；关闭后输出恢复 |
| 负例（7 组） | 缺目标启动通道、非法时钟、非法 counter、损坏通道（缺 kind）、版本不符、不同 frame（`frame_mismatch` + `unavailable` + 0 观测）、失败导入不改运行态 |
| 可选 profile | 无 sensor 组件的会话 save→load 正常 |
| 旧档局限 | 删掉 sensor 段的旧档仍能读（A-04 矩阵），但 `unrecoverable[]` 明示**未保存过运行态**、`sensor_restore_report.saved=false` |
| 可见性 | 恢复运行态不扩大匿名 contacts 可见字段 |

**真实结果**（I5）：

```
Phase A gate:  total=3 pass=2 fail=1   (A0-T1 45/0、A0-T2 30/0、A0-T3 40/1)
Phase 0 gate:  total=6 pass=6 fail=0
Full matrix:   total=83 pass=75 fail=8
  BASELINE CHECK:         known_fail=7 new_fail=0 drift=0 complete=true
  PHASE A BASELINE CHECK: known_fail=1 new_fail=0 drift=0 complete=true
```

## 6. 基线证据更新

| 条目 | 变化 | 说明 |
|---|---|---|
| `integration.a0_save_roundtrip_authority` | 38/3 → **40/1** | 传感器持久化与通道内容断言已通过；**仅剩**真实 HUD 会话 `replay send_comms no_route`（**DS-A-06** 范围，不属本卡） |

> 本卡**未**修改任何期望值以掩盖回归；A0-T3 的 `_canonical_diff` 采用 A-00 的**数值值语义**
> （JSON 数字往返后 `int↔float` 不算漂移），整数分配器仍单独断言为真 int。

## 7. 未覆盖 / 尚未验证

- `replay send_comms 失败：no_route` → **DS-A-06**（保持红，不声称已修）；
- 长时存档成本 → DS-A-07；
- 只覆盖 `optical_ir` 与 `legacy` 两种后端；`legacy` 后端无可续跑通道状态（显式标注）；
- 未验证 Linux/macOS、非 headless 渲染、真实 RF/光学物理。

## 8. 命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_sensor_persistence|sensor_service|optical_ir|a0_sensor_geometry|a0_save_roundtrip_authority|save_probe|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-05/full
```
