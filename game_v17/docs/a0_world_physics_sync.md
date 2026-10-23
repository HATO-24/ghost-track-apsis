# A0-T1 · WorldState 位置副本与 PhysicsWorld 权威同步（Issue #2.2）

> 分支 `phase-a1/worldstate-physics-sync`，堆叠在 PR #17 head `5bb763d` 之上。
> 本任务只解决「tick 后 `WorldState` 位置/速度副本陈旧」，**不**处理传感器目标几何绑定
> （#4.1）、存档 schema 漂移（#2.5）、EW 消费者（#4）、HUD 视觉验收。

## 1　问题（A0 调查 C3）

A0 调查确认：`PhysicsWorld.step()` 推进位置/速度，但 `WorldState` 不会在业务 tick 中自动
同步；`GameSession.snapshot().entities` 从 `WorldState` 读取，因此对外快照呈现旧位置。

修复前实测（本任务探针，`orbital_sim` 真实入口，10×60 s tick）：

| 实体 | `snapshot().entities.pos_km` | `physics_state().r` | 差 |
|---|---|---|---|
| harmattan | `[322139.0, 0.0, 0.0]`（seed 原值） | `[322139.024289241, 12.0019525223206, 0.0]` | **12.0 km** |
| apsis | `[321719.0, 0.0, 0.0]` | `[321718.999011987, 0.00000105209203, 0.0]` | 1e-3 km |
| raider_2 | `[324200.0, 300.0, -100.0]` | `[324182.033190946, 300.026948521532, -99.9992828233063]` | **18.0 km** |

`world.version` 在 10 次 tick 后仍为 7（仅 boot 的 7 条 spawn），证明 tick 中**没有任何**
world 写入；`world.event_refs` 的 source 全部是 `session`（seed spawn），没有 `physics_world`。

## 2　位置/速度读写路径（本任务涉及范围）

```
                ┌──────────────────────────── 写入 ────────────────────────────┐
scenario JSON ──► ShellBinder._scenario_seed ──► GameSession.boot
                                                     │
                                    ┌────────────────┴─────────────────┐
                                    ▼                                  ▼
                          PhysicsWorld.upsert_entity          WorldState.apply(entity.spawn)
                          （唯一位置/速度权威）                  （boot 时的初始副本）
                                    │                                  ▲
                     PhysicsWorld.step(dt)  RK4 推进 r/v             │
                                    │                                  │
                     GameSession.tick: world_physics_sync("tick")  ───┘
                     （只读副本：physics r/v → entity.move, source=physics_world）
                                    │
                ┌───────────────────┼────────────────────┬───────────────────┐
                ▼                   ▼                    ▼                   ▼
      snapshot().entities   plot_positions()      save_state()        world.entity()
      （对外快照）           （物理分支）           （physics 段）       （只读副本）
```

- **唯一写者**：只有 `PhysicsWorld` 在运行时推进位置/速度（`step/state_at/set_time`）。
  `WorldState` 不反向写 physics；`GameSession` 是 `WorldState` 的唯一写者（`writer="session"`）。
- **读取方**：`snapshot().entities`、`plot_positions()`（物理分支）、`signal_sync_from_world()`
  （元数据/位置）、`_build_contacts()`（元数据 fallback）都从 `WorldState` 读副本；
  `position_of()/physics_state()/physics_positions()/`_ballistics_states()` 直接读 physics。

## 3　策略选择：GameSession 在 tick 边界同步只读副本

两种候选策略：

| 策略 | 结论 |
|---|---|
| **A. tick 边界同步只读副本**（选定） | `GameSession.tick()` 在 `physics.step()` 之后立刻把 physics 的 r/v 写成 world 的 `entity.move` 事件（`source="physics_world"`）。改动集中、保留 `WorldState` 的既有职责与 `snapshot()` 形状、存档兼容、不改变任何服务契约。 |
| B. 让所有读取方从 PhysicsWorld 派生 | 需要改 `snapshot()` 形状（或加双读路径）、改每个消费者、破坏「world 是实体表」的既有契约；且存档/旧档路径仍需 world 副本。改动面过大，本任务不做。 |

选定 A 的理由：**保持 `WorldState` 作为实体表 + 单一写者**，把「副本陈旧」变成「副本在
明确边界刷新」，不引入第二个位置真相，也不让任何读取方猜测来源。

### 3.1 同步点

| 时机 | 行为 |
|---|---|
| `boot()` 末尾 | `world_physics_sync("boot")`：把 seed 灌入后的 physics 状态写成 world 副本（此时两边同值，通常 0 写入）。 |
| `tick()` 中 `_advance_physics` 之后 | `world_physics_sync("tick")`：把 physics 当前时刻 r/v 写为 world 副本；返回 `world_sync` 段。 |
| `load_state()` replay 之后 | `world_physics_sync("load")`：用恢复的 physics 快照重新对齐 world 副本（replay 不重放 physics）。 |
| 显式 `sync_world_from_physics()` | 保留原有全量同步语义（全量写一遍并发布 `physics.world_synced`），供外部/调试/存档路径使用。 |

tick 边界同步**不逐实体发 bus 事件**（避免每 tick 7 条噪声）；显式入口仍发事件。

### 3.2 帧门禁（不做隐式跨帧搬运）

`physics_frame_meta.applied=true` 表示 boot 时 seed 做过 L1 相对 → `bary_rot` 的平移
（4F 契约）。这类会话的 `WorldState` 副本仍是 L1 相对语义，与 physics 的 bary_rot 不是同一
坐标空间。策略：

- `mode = "frame_mismatch"`，**显式不同步**，`world_physics_sync_status().reason` 记录原因；
- 不参与 `check_contracts()` 的「副本==physics」不变量；
- 不做隐式转换（不把 bary 数值写进 L1 语义的 world 实体，也不反向把 L1 值喂给 physics）。

这样既修复了 orbital_sim/full 等 bary 场景的 C3，又不破坏序章 L1 帧契约。

### 3.3 单向性

副本写入**绝不**反向覆盖 physics：调用方手写 world 位置后，physics 不变；下一次 tick 边界
会用 physics 覆盖回来（副本自愈）。探针断言了该行为。

## 4　新增/修改的 API

| API | 说明 |
|---|---|
| `GameSession.world_physics_sync(reason)` | tick 边界/显式同步入口；返回 `{ok,enabled,in_sync,frame,mode,reason,synced,compared,updated,mismatched,failures,skipped,sync_reason}`。**字段语义**：`updated` = 本次成功写回的实体 id（被修复对象）；`mismatched` = **同步之后仍未对齐**的实体（正常应为空，仅在写入失败/被拒时非空）；`synced` = `updated.size()`；`in_sync` = `mismatched` 与 `failures` 均为空。 |
| `GameSession.world_physics_sync_status()` | 只读诊断（不写任何状态）：`{enabled,mode,frame,in_sync,compared,mismatched,sync_count,last,reason}`；其中 `mismatched` 为**当前**未对齐实体。 |
| `tick()` 返回值 | 新增 `world_sync` 段（与 `physics_tick` 并列）。 |
| `load_state()` 返回值 | 新增 `world_sync` 段。 |
| `check_contracts()` | `mode=tick` 时新增「world 位置副本与 physics 一致」不变量。 |
| `sync_world_from_physics()` | 语义不变（显式全量），文档更新。 |

策略常量：`WORLD_SYNC_MODE_TICK`/`WORLD_SYNC_MODE_FRAME_MISMATCH`/
`WORLD_SYNC_MODE_NO_PHYSICS`/`WORLD_SYNC_MODE_DISABLED`。

## 5　回归探针

`game_v17/tests/a0_world_physics_sync_probe.gd`（matrix id `integration.a0_world_physics_sync`，
不加入 `gates.phase0`）。真实入口 `main_menu → v1_hud → ShellBinder → GameSession`
（`DSH_BUILD=orbital_sim`）。

断言组（**97 断言**）：

1. 真实入口 + physics/world 实体清点（scenario 7 实体）；
2. boot 时 world 副本 == physics（同 seed、同帧）；
3. **多次 tick（10×60 s）后 `snapshot().entities` 位置/速度 == physics 同一时刻**
   （逐位一致；容差仅吸收序列化噪声）+ `world_physics_sync_status()` 自检 + 反证 C3
   （harmattan 移动 > 1 km、snapshot 不是 seed 旧值、world version 增长、source=physics_world）；
4. **一次确实发生同步的 tick 的返回值语义**（审查修正）：`updated` 非空且等于
   `synced`；`mismatched` 在同步后为空；`updated` 与 `mismatched` 不相交；已对齐的
   no-op tick 报告 `updated=[]` 且仍 `in_sync`；
5. 坐标系/单位/容差：`frame=bary_rot`、`km`/`s`/`km/s`、地月量级 sanity；
6. 消费者：`plot_positions()` 走 physics 分支且数值 == physics − apsis 参考；
7. 消费者：save → load 后 `snapshot` == 恢复的 physics == 保存前 physics；存档不推进 physics；
8. 单向性：手写 world 位置不改变 physics；sync status 检测到分歧；tick 边界自愈；
9. 帧门禁：L1 转换会话 `mode=frame_mismatch`、显式不同步、world 副本不被跨帧污染；
10. 确定性：无 tick 的重复 `snapshot()` 完全一致。

红/绿证据见 PR 描述（红 `PASS=62 FAIL=16` → 绿 `PASS=78 FAIL=0`；审查修正轮
`updated/mismatched` 语义红 `PASS=87 FAIL=3` → 绿 `PASS=97 FAIL=0`）。

## 6　位置消费者清单（本任务后）

| 消费者 | 来源 | 本任务状态 |
|---|---|---|
| `snapshot().entities` | `WorldState` 副本 | **已修复**：tick 边界同步，与 physics 同刻 |
| `plot_positions()`（物理分支） | `physics_positions()` 直读 physics | 已正确（修复前已是 physics） |
| `plot_positions()`（无 physics 回退） | `snapshot().entities` | 无 physics 时 world 是唯一来源，自洽 |
| `_ballistics_states()` / `_entity_kinematics()` | physics 优先，缺失回退 world | 已正确 |
| `signal_sync_from_world()` | `world.entities_sorted()` | 随副本同步而获得当前位置 |
| `_build_contacts()` 元数据 fallback | `snapshot().entities` | 随副本同步（元数据非本任务范围） |
| 存档 `save_state()` | `physics_world.save_state()` + seed/log | physics 段正确；world 副本在 load 后重新对齐 |
| `CICView` 位置 | `ownship + bearing + range` 派生，`position_truth=false` | **不在本任务范围**（信息战设计：不读 truth） |
| contacts `range_km` | TrackTable 观测几何 | **不在本任务范围**（保留航迹作为观测信息；#4.1 传感器几何绑定） |
| `SensorService` 目标几何 | 静态配置（`_sensor_config()`） | **不在本任务范围**（#4.1） |
| `v1_hud` 战术台目标行 | `track_vm`（观测） | **不在本任务范围**（保留观测语义） |

## 7　未覆盖 / NOT RUN

- **传感器目标几何绑定**（#4.1）：`SensorService` 目标位置仍是静态配置，航迹 `range_km` 仍是
  观测值（e2e 的 20 km vs 420 km 差异不变）。本任务**刻意不**把 TrackTable 距离改成物理真值。
- **存档 schema 漂移**（#2.5）：`save_probe` 的 3 条既有失败（事件 `seq` int→float 等）保持
  FAIL，未在本任务修复。
- **EW 消费者**（#4）、**HUD 视觉验收**（无渲染）、**CICView 位置派生**（设计如此）、
  **`SensorService` 运行态持久化**（C5）：均未处理。
- **未验证**：非 headless 渲染、Linux/macOS、长时间（>10⁴ tick）漂移、多会话并发。
- 本任务**不**声称 Phase A 整体门槛通过；Phase A 仍有 #2.3/#2.5/#4/#6 等任务。

## 8　验证命令

```powershell
pwsh ./run_tests.ps1 -Only '^integration\.a0_world_physics_sync$' -NoImport -Ci
pwsh ./run_tests.ps1 -Gate phase0 -Ci
pwsh ./run_tests.ps1 -Baseline game_v17/tests/known_baseline_failures.json -Ci
```
