# A0-T2 · 传感器目标几何绑定 PhysicsWorld（Issue #4.1）

> 分支 `phase-a1/sensor-geometry-physics`，堆叠在 **PR #19 head `8c1483a`** 之上
> （PR #19 base = PR #17 head `5bb763d`；PR #17 base = PR #16 head `f3f5158`）。
> **PR #17 / #19 均未合并**，因此本 PR 的 base = `phase-a1/worldstate-physics-sync`。
>
> 本任务**只**处理传感器目标几何来源与时间一致性，**不**完成整个 Issue #4：
> 不扩展 IFF 状态机、不实现 EW 效果、不做传感器全系统重构。

## 1　问题（A0 调查 C1 / e2e 20 km vs 420 km）

`orbital_sim` 入口的 `SensorService` 目标几何来自 `ShellBinder._sensor_config()` 的**静态配置**：

```gdscript
"targets": [
  {"id": "harmattan",  "pos_km": [20.0, 0.0, 0.0], ...},   # L1 相对语义
  {"id": "l1_station", "pos_km": [0.0, 0.0, 10.0], ...},
]
"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0], ...}
```

而 `scenario_orbital_sim.json` 的实体是 **bary_rot 绝对坐标**（apsis `[321719,0,0]`、
harmattan `[322139,0,0]`），PhysicsWorld 也在此空间推进。结果：

| 量 | 静态配置 | PhysicsWorld（真实） | 差 |
|---|---|---|---|
| apsis→harmattan | 20 km | **420.20 km**（10×60 s 后） | 400.20 km |
| apsis→l1_station | 10 km | **90.00 km** | 80.00 km |
| 静态 vs 物理绝对位置（harmattan） | `[20,0,0]` | `[322139.000, 0.002, 0]` | **322,119.000 km** |
| 静态 vs 物理绝对位置（l1_station） | `[0,0,10]` | `[321719.000, 90.000, 0]` | **321,719.013 km** |

> 注：这些差值来自**当前 demo 场景**的具体配置（两套不同语义的坐标被并列），
> **不是**普遍规律；换场景/换配置后差值会变。探针在运行时实测并打印，不硬编码期望差值。

**影响**：传感器/航迹的 `range_km` 与 `bearing_deg` 长期基于错误几何 → e2e 观测到的
`fusion 20 km vs truth 420 km` 差异；`TrackTable.range_km` 与物理真值脱节。

## 2　策略：几何绑定 + 采样时刻一致 + 显式降级

### 2.1 分工

| 类别 | 来源 | 是否被本任务改变 |
|---|---|---|
| **几何**（observer/targets 的 pos/vel） | **PhysicsWorld**（绑定后） | ✅ 改为物理世界当前时刻 |
| **静态元数据**（rcs_m2/side/iff_code/classification/batch/transponder…） | 原权威（EntityCatalog / 配置） | ❌ 保持不变 |
| **观测结果**（range_km/bearing_deg/support/quality） | SensorService 计算（含噪声） | ❌ 仍是**观测值**，不替换为真值 |

### 2.2 绑定与刷新

```
GameSession.boot() 末尾
  └─ _bind_sensor_geometry()
       ├─ physics 未启用 / seed 做过 L1→bary_rot 转换 → 不绑定（source=static + 原因）
       └─ 否则 sensor_service.bind_geometry_provider(_SensorGeometryProvider.new(self))

GameSession.tick()
  ├─ _advance_physics(sim_dt)            # PhysicsWorld 推进（唯一位置/速度权威）
  ├─ world_physics_sync("tick")           # A0-T1：world 副本同步
  ├─ _advance_sensors(sim_dt)
  │    └─ SensorService.step()
  │         ├─ t += dt
  │         └─ refresh_geometry(t)         # 按当前 t 读 physics r/v
  │              ├─ observer.pos_km/vel_kmps  ← physics state
  │              ├─ targets[i].pos_km/vel_kmps ← physics state
  │              ├─ 静态元数据字段保持不变
  │              └─ authority.set_snapshot(...)  # 让雷达/光学用新几何算 range/bearing
  └─ ... 其余组件
```

### 2.3 采样时刻一致性

- `refresh_geometry(t)` 校验 `|provider.geometry_t() - t| <= 1e-6 s`；
  不一致 → `ok=false, reason="time_mismatch"`，**不使用旧几何**（不静默）。
- **时间不匹配时不生成观测/证据**：`step()` 用 `_geometry_usable()` 判定；不可用时
  跳过 `_collect_observations` / `_collect_optical_evidence`，只记一次
  `geometry_unavailable` 事件并累加 `suppressed_steps`（可审计）。**不会**用上一次
  observer/target 坐标产出「当前时刻」观测。
- 观测行的 `t` == 生成它的 `physics t` == `session t`（探针断言最新批次）。
- 几何行携带 `geometry_t`/`geometry_frame`/`geometry_source` 供审计。

### 2.4 显式降级（不静默把旧静态位置当物理真值）

`geometry_status()` 的公开字段：

| 字段 | 语义 |
|---|---|
| `source` | `physics_world` / `static` / `unavailable` / `none` |
| `authoritative` | **仅当** source=physics_world 且 complete 时为 true |
| `complete` / `available` | 时间一致 + observer 绑定 + targets 全部绑定 + 无帧不匹配 |
| `reason` | 精确原因：`time_mismatch` / `observer_missing` / `target_missing` / `frame_mismatch` / `no_physics_world` / `no_sensor_service` / `provider_not_ready`（成功时为空） |
| `missing` | observer 缺失的实体 id 列表 |
| `skipped` | 未取得当前物理状态的 target id 列表 |
| `mismatched_frame` | 帧不匹配的 target id 列表 |
| `suppressed_steps` | 因几何不可用而抑制观测生成的 step 次数 |
| `observer_bound` / `bound` | observer 是否绑定 / 本次绑定成功的 target 数 |
| `geometry_t` / `t` | 几何采样时刻 / 传感器当前时刻 |

| 条件 | `source` | `authoritative` | `reason` | 行为 |
|---|---|---|---|---|
| physics 已启用且同坐标语义、全部绑定成功 | `physics_world` | `true` | `""` | 正常生成观测 |
| **provider 时间与传感器时间不一致** | `physics_world` | `false` | `time_mismatch` | **不生成观测**（旧坐标不参与） |
| **observer 在 PhysicsWorld 中缺失** | `physics_world` | `false` | `observer_missing` | **不生成观测**；`missing` 记录 id |
| **单个 target 缺失** | `physics_world` | `false` | `target_missing` | **不生成观测**；`skipped` 记录 id；该行 `pos_km/vel_kmps` 清空并标 `geometry_source=unavailable` |
| 无 PhysicsWorld | `static` | `false` | `no_physics_world` | 静态配置位置（**非**物理真值） |
| 4F 帧转换会话 | `static` | `false` | `frame_mismatch` | 显式不绑定；`mark_geometry_unavailable("frame_mismatch")` |
| provider 未就绪 | `static` | `false` | `provider_not_ready` | 静态几何 |
| 无 sensor_service | `none` | `false` | `no_sensor_service` | — |

**关键约束**：部分绑定失败时**不写混合坐标快照**到 authority（否则旧坐标会被当成
当前真值参与观测）；`authoritative` 不会因为「部分成功」而误报为 true。

## 3　修改文件

| 文件 | 类型 | 内容 |
|---|---|---|
| `game_v17/scripts/core/sensor_service.gd` | 修改 | 几何来源常量/状态；`bind_geometry_provider()` / `refresh_geometry()` / `geometry_status()`；`step()` 内按当前 t 刷新几何；静态元数据不被覆盖 |
| `game_v17/scripts/core/game_session.gd` | 修改 | `_bind_sensor_geometry()` / `_sensor_geometry_bind_allowed()` / `_SensorGeometryProvider`（只读 provider）；boot 末尾绑定；`sensor_geometry_status()` 公开诊断 |
| `game_v17/tests/a0_sensor_geometry_probe.gd` | 新增 | 真实入口集成探针（**143 断言**） |
| `game_v17/tests/probe_matrix.json` | 修改 | 新增 `integration.a0_sensor_geometry`（**不加入** `gates.phase0`）；75 cases |
| `game_v17/docs/sensor_service.md` | 修改 | §2A 几何绑定契约（来源分工/采样时刻/降级/诊断/边界） |
| `game_v17/docs/game_session.md` | 修改 | tick 编排中的 sensor 几何绑定段 |
| `game_v17/docs/a0_sensor_geometry.md` | 新增 | 本文档 |

**未改动**：`known_baseline_failures.json`、`gates.phase0`、默认 profile、
`TrackTable` 融合逻辑、`CombatService`、HUD 显示契约、`ShellBinder._sensor_config()` 的静态值。

## 4　保留的语义边界（本任务刻意不做）

- **`TrackTable.range_km` 仍是观测值**：由 observation 融合得到（含传感器噪声），
  **不**替换为物理真值。探针断言 track range ≈ 最新 observation range（同一观测管线），
  而不是等于 physics 距离。
- **HUD 不读传感器内部真值**：contacts 只带 display 字段与 track 观测值；
  探针断言 contact 无 `truth_pos_km` 之类字段。
- **CombatService 不越权**：其 track 行不含 `pos_km`；弹道走自己的 `_ballistics_states()`。
- **不做 IFF 状态机 / EW 效果 / 传感器全系统重构**。

## 5　回归探针

`game_v17/tests/a0_sensor_geometry_probe.gd`（matrix id `integration.a0_sensor_geometry`，
不加入 `gates.phase0`）。真实入口 `main_menu → v1_hud → ShellBinder → GameSession`
（`DSH_BUILD=orbital_sim`）。

断言组（**143 断言**）：

1. 真实入口 + sensor/physics 启用清点；
2. **静态配置基线**：实测静态 target 位置与 physics 位置的差值（打印 `GEOMETRY GAP`，
   不硬编码）；静态 observer/target 位置与 physics 不同（反证修复前几何来源）；
3. boot 后几何来源 = `physics_world`、`authoritative=true`、frame=`bary_rot`、
   单位 km / km/s / s、`last.ok`、`time_ok`、`bound` 数量、observer 已绑定、无 missing/mismatch；
4. **目标机动后（10×60 s）**：sensor target 的 pos == physics pos（逐值）、
   `geometry_source=physics_world`、`geometry_t == session t`、`geometry_frame=bary_rot`；
   静态元数据（rcs_m2/side/iff_code/classification/batch）仍在；至少一个目标确实移动；
5. **观测几何 == physics 几何**（在传感器噪声容差内，容差来自观测行自身 sigma）；
   观测 range **不是**静态配置几何（反证）；观测 `t` == physics `t`（同一仿真时刻）；
   观测行带 support/quality/sensor/range/bearing 等观测属性；
6. **观测语义保留**：track 有 observation sources、identity 来自证据、
   `track.range_km ≈ 最新 observation.range_km`；CombatService track 行无 pos_km；
   HUD contact 无 truth 位置字段、使用 safe display；
7. **降级（精确 reason）**：无 physics → `source=static, authoritative=false,
   reason=no_physics_world, complete=false`；帧转换会话 → `source=static,
   authoritative=false, reason=frame_mismatch, complete=false, last.ok=false,
   last.time_ok=false`（**不再接受空原因或 provider_not_ready**）；
8. **时间不匹配失败路径**（可控 provider 人为制造）：`reason=time_mismatch`、
   `authoritative=false`、`complete=false`、`available=false`、`last.time_ok=false`；
   **观测数量不增加**（旧几何不产出当前观测）；`suppressed_steps > 0`；
   时间恢复一致后 `authoritative=true` 且观测继续生成（非永久关死）；
9. **observer 缺失失败路径**：`reason=observer_missing`、`authoritative=false`、
   `complete=false`、`observer_bound=false`、`missing` 含该 id、**观测数 0**；
10. **单个 target 缺失失败路径**：`reason=target_missing`、`authoritative=false`、
    `complete=false`、`skipped` 含该 id、**观测数 0**（混合坐标被抑制）、
    缺失行 `geometry_source=unavailable` 且 `pos_km` 已清空（不沿用旧静态坐标）；
11. **失败路径确定性**：相同缺失场景两次运行的 geometry status / 观测数一致；
12. **正常路径确定性**：同一操作序列的 geometry status / observations / TrackTable 完全一致。

红/绿证据见 PR 描述（初版红 `PASS=74 FAIL=33` → 绿 `PASS=107 FAIL=0`；
失败路径轮 红 `PASS=116 FAIL=27` → 绿 `PASS=143 FAIL=0`）。

## 6　未覆盖 / NOT RUN

- **IFF 状态机**（Issue #4 其余部分）：`never_hostile=true` 等既有行为未改。
- **EW 效果消费**（Issue #4 / A0 C10）：`ew_service` 的 effect 仍未被传感器/航迹消费。
- **传感器全系统重构 / legacy bridge 收敛**：`v17_sensor_authority_display` 的 3 条既有失败
  （bridge 架构性）保持 FAIL，未在本任务修复。
- **`SensorService` 运行态持久化**（A0 C5）：存档不含 sensor 运行态，未在本任务处理。
- **传感器目标几何的存档往返**：geometry 绑定状态不入存档（boot 重新绑定）。
- **`TrackTable.range_km` 的物理一致性**：刻意保持观测语义，未与物理真值对齐。
- **CICView / HUD 视觉验收**：无渲染验证。
- **未验证**：非 headless 渲染、Linux/macOS、>10⁴ tick 漂移、多会话并发、真实 RF/光学模型。
- 本任务**不**声称 Issue #4 完成，也**不**声称 Phase A 整体验收完成。

## 7　验证命令

```powershell
pwsh ./run_tests.ps1 -Only '^integration\.a0_sensor_geometry$' -NoImport -Ci
pwsh ./run_tests.ps1 -Gate phase0 -Ci
pwsh ./run_tests.ps1 -Baseline game_v17/tests/known_baseline_failures.json -Ci
```
