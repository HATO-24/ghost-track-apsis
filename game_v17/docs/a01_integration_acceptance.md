# DS-A-01 · 实现链同提交整合验收（I1）

> 基线：A-00 交付 **I0 候选** `b9101c8369c44dc293e579701efa0a4029d28dec`
> （A-00 最终 head `882e058e2a0550684ade73f6978122fef46d42d7`）。
> 交付 **I1** = `da7d9ba` 起的整合提交（完整 SHA 见执行报告）。
> 入口：`main_menu → v1_hud → ShellBinder → GameSession`（`DSH_BUILD=orbital_sim`）。

## 1. 本卡范围与结果

| 项 | 结果 |
|---|---|
| 新增整合探针 `integration.a0_integration_authority` | **PASS 61/0** |
| Phase A 专项 | **2 PASS / 1 FAIL**（A0-T1 45/0、A0-T2 30/0、A0-T3 37/4） |
| Phase 0 门禁 | **6/6 PASS**（语义未改） |
| 全量矩阵 | **79 = 70 PASS / 9 FAIL / 0 TIMEOUT / 0 NOT RUN** |
| 双 baseline | legacy `known_fail=8 new_fail=0 drift=0 complete=true`；Phase A `known_fail=1 new_fail=0 drift=0 complete=true` |

**9 个 FAIL = 8 个 Phase 0 历史失败 + 1 个 Phase A 待修（A0-T3 存档/传感器/comms，属 A-03/A-05/A-06）**。
**不是「全部通过」**；本卡未修任何存档/通信路径。

## 2. 已修的真实缺陷（本卡源码修复，逐项独立提交）

| # | 缺陷（红→绿证据） | 修复 | 提交 |
|---|---|---|---|
| 1 | **无效几何仍然路由观测**：`mark_geometry_unavailable()` 清空 provider 后 `_geometry_usable()` 的「无 provider」分支返回 true → frame_mismatch 会话仍产出 4 条静态观测并建出 1 条航迹（P20 遗留分支风险，任务卡点名）。同时 legacy static 模式无任何 ADVISORY 标注，可与 LIVE 混淆。 | 引入几何可用性分级 `live / advisory / unavailable`：`unavailable`（期望 physics 但不可用）**抑制本 tick 全部观测**；`advisory`（显式 legacy，无 physics 设计）允许产出但每条观测带 `geometry_mode=advisory` + `geometry_advisory=true`；`geometry_status()` 暴露 `mode/advisory/unavailable`。 | `c2114ea` |
| 2 | **弹道无 catalog 权威**：`CombatBallistics` 无 EntityCatalog 引用，`_target_rcs()` 用 `RCS_DEFAULT_M2=800` 静默兜底；弹道初始状态无可追溯 source。 | 注入 `catalog`/`physics` **只读**引用；新增 `state_source(entity_id)`（返回 source/frame/t/r/v + catalog 特征）；`_target_rcs/_target_ir` 优先取 catalog，仅在 catalog 不认识实体时退回缺省并记录 `_last_feature_fallback`（不静默）。 | `debcc96` |
| 3 | **玩家视图泄漏 truth-only 字段**：`track_table.vm()` 直接返回内部航迹（含 `batch`），CICView 行以玩家字段名 `batch` 暴露。 | `vm()` 改为玩家投影（扣留 `batch/rcs_m2/radius_km/has_pd`，并标 `truth_fields_withheld=true`）；**内部航迹与 `snapshot()` 不变**（去重/合并/存档仍用 batch）；CICView 行移除 batch。 | `bfb01ae` |
| 4 | **snapshot 无静态字段来源声明** | `snapshot()` 新增 `entity_catalog` 块（`source=entity_catalog`、`authoritative=true`、按稳定 ID 的 7 实体）。 | 随 `c2114ea` |

> 这 4 项修复使 **A0-T2 从 26/4 转为 30/0 PASS**（DS-A-00 的 4 项遗留缺陷全部关闭）。

## 3. 阈值与实测（任务卡 §阈值）

| 量 | 阈值 | 实测 |
|---|---|---|
| world 副本位置 | 1e-9 km | 通过（A0-T3 + A-01 consumer 表） |
| world 副本速度 | 1e-12 km/s | 通过（A-01 fixture velocity 保留） |
| provider 几何 vs 独立标量 | 1e-6 km / 1e-6 deg | 通过（真实 session 移动 observer/target 后仍通过） |
| 采样时差 | 1e-6 s | 通过（`geometry_status().t == physics.t`） |

**无噪声 fixture 使用标量 double 计算**，不使用 `Vector3`（避免大绝对坐标单精度量化）：
局部 `[0,0,0] → [3,4,0] km` 距离**恰为 5.0**，方位按现有 `atan2(dx,dy)` 轴向定义。

## 4. 移动 observer 与 target（任务卡第 2 行）

- 通过**授权物理 API** `physics_world.upsert_entity()` 修改状态；
- 先只移动 observer（读回权威位置 + 固定偏移），推进 **10×60 s**，距离/方位随之改变且与独立标量期望一致；
- 再只移动 target，推进 **10×60 s**，距离/方位再次改变且一致；
- 两次移动都断言「确实改变了观测几何」——**不是只证明目标在动**。

## 5. 不确定观测（任务卡第 3 行）

fixture 声明：真值 5.0 km / 测量 5.25 km / 方位 真值 + 0.05° / sigma = 0.1 km、0.02°。
用 `TrackTable.handle_observation()` 注入真实 schema 的观测行：
- track `range_km` == **5.25**（容差 1e-9），**未被拉回真值 5.0**；
- fixture 的 sigma 在报告中显式声明，**未**新增 TrackTable sigma 字段，**未**声称验证了生产噪声分布。

## 6. 生产误差参数（任务卡第 4 行）

沿真实 backend 记录（`sensor_types.record()`）取得，单位显式记录：

| 型号 | range_km | sigma_bearing_deg | sigma_range_frac | sigma_range_floor_km | 测距误差量 |
|---|---|---|---|---|---|
| YW-R9（radar） | 见实测 | >0 | 见实测 | 见实测 | 声明（可追溯） |
| MS-OT2（optical） | 见实测 | >0 | 0 | 0 | **未验证（该模型不声明测距）** |
| CH-IR2（IR） | 见实测 | >0 | 0 | 0 | **未验证（该模型不声明测距）** |

> 缺测距 sigma 的模型被**显式列入 UNVERIFIED 清单**，绝不用默认 1 冒充模型参数，
> 也不声称它们有测距精度。

## 7. 消费者 source/frame/t 表（任务卡第 5 行）

同一实体 `harmattan`，逐项核对可追溯来源（探针断言全绿）：

| 消费者 | source | frame | t / 其他 | 备注 |
|---|---|---|---|---|
| PhysicsWorld | 唯一运动学权威 | `bary_rot` | 与 session `t_s` 差 ≤1e-6 s | 位置/速度 |
| WorldState 投影 | physics 副本 | `bary_rot` | 同 tick | 位置误差 ≤1e-9 km |
| 合成 snapshot | `world.entities_sorted()` + `entity_catalog` 块 | `physics_frame` 块 | 同 tick | **静态字段来源显式声明** |
| 传感器几何输入 | `physics_world` | `bary_rot` | geometry `t` == physics `t` | provider 几何 == 标量期望 |
| 弹道初始状态 | `physics_world`（`state_source()`） | `bary_rot` | 带 catalog 特征来源 | 修复后新增 |
| HUD / 火控输入 | track/contact 玩家投影 | — | 声明 `side_source`/`identity_source` | 显示观测/估计，不复制 truth |

## 8. 失败与降级（任务卡第 6 行）

| 场景 | 行为 | reason |
|---|---|---|
| 缺 target | 无观测、无航迹；`skipped` 记录 ID | `target_missing` |
| 缺 observer | 无观测；`missing` 记录 ID | `observer_missing` |
| frame 不匹配（期望 physics） | **抑制**本 tick 全部观测 | `frame_mismatch`（mode=unavailable） |
| 无 physics 的 legacy 会话 | 允许产出，但每条观测 `geometry_advisory=true` | `no_physics_world`（mode=advisory） |
| 无 sensor service | 明确 reason | `no_sensor_service` |

**观测绝不来自未标明的演示值**：`unavailable` 时 0 观测；`advisory` 时逐条带标签。

## 9. 可见性（任务卡第 7 行）

- 7 个 scenario 实体在 catalog 归属正确（side/batch/rcs/radius/has_pd 与 scenario truth 逐项相等）；
- 匿名 contacts：无 silent friend fallback、无 `batch/rcs_m2/radius_km/has_pd` 泄漏；
- 玩家 track/CIC 视图均扣留 truth-only 字段；
- 保留 P17 安全事件负例（`a1_entity_metadata_authority_probe` 未改动，仍通过）。

## 10. 未修列表（留给后续卡）

| 缺陷 | 后续卡 |
|---|---|
| 真实 HUD 会话 save→load `replay send_comms 失败：no_route` | DS-A-06 |
| 恢复后事件 `seq` 为 float（27 处） | DS-A-03 |
| 存档无 `sensor_service` 运行段、EMCON/channels 丢失 | DS-A-05 |
| 历元/frame 系统化、旧 seed 兼容 | DS-A-02 |
| 旧档迁移与超环形缓冲去重 | DS-A-04 |

## 11. 命令与日志

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_|a1_entity_metadata|e2e_orbital_sim|physics_world|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-01/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-01/full
```

## 12. 未覆盖 / 尚未验证

- 不宣称整个 Phase A 完成；A0-T3 存档切片仍红；
- 未验证 Linux/macOS、非 headless 渲染、真实 RF/光学物理；
- 未量化生产噪声分布（只验收模型声明的误差量与确定性输出）；
- 未做 LD/中继通信恢复（DS-A-06）、长时存档成本（DS-A-07）。
