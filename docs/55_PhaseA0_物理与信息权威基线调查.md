# Phase A0 — 物理权威与信息权威架构基线调查

> 任务性质：**只调查，不修改实现**（Phase A0）。
> 基线：Phase 0 最终 head `7d8a60f525f8550b242dd53b34dc011aa26b6b14`（PR #15 head，基于 PR #13 分支；#12/#13/#15 均仍为 OPEN，未合并 `main`）。
> 调查 worktree：`D:\gt_a0`（分支 `phase-a0/physics-info-authority-audit`）。
> 运行环境：Windows，Godot `4.7.2.stable.official.ed1daf0bf`。
> 上游材料：`docs/40_系统完成度复核与开发任务队列.md`（审计）、`docs/54_Phase0_验收报告.md`、`game_v17/docs/game_session.md`、`physics_world.md`、`sensor_service.md`、`track_table.md`、`sensor_authority*.md`、`identification_service.md`、`transponder_service.md`、`ew_service.md`、`signal_service.md`。
> 调查方法：三路独立只读调查（物理链 / 信息链 / 测试矩阵）+ Lead 代码复核与真实 probe 运行；三路结论交叉一致。
> 证据分级：**CONFIRMED** = 代码位置 + 本轮真实运行证据；**RISK/HYPOTHESIS** = 静态推断，未运行验证；**TO-VERIFY** = 需要新增/重跑测试才能定论。本文不把静态阅读描述为运行时验证。
> 过程证据（gitignored，可复现）：`.test-results/a0/physics_chain.md`（724 行）、`.test-results/a0/sensor_chain.md`（581 行）、`.test-results/a0/test_plan.md`（574 行）、`.test-results/a0/evidence/`、`.test-results/a0/logs_physics/`、`.test-results/a0/probe_logs/`。

---

## 0. 执行摘要

当前仓库已具备“单一权威物理世界”（PhysicsWorld）与“单写者航迹表”（TrackTable）的**组件级骨架**，但二者**尚未在运行时形成同一条权威链**。本轮已把每一处断裂定位到代码行并做运行时量化：

1. **传感器观测的输入几何不是物理真值**：`ShellBinder._sensor_config()` 用演示坐标（`harmattan [20,0,0]`）配置 SensorService；`GameSession._advance_sensors()` 调 `sensor_service.step(sim_dt)`（`game_session.gd:1075`，**不传 physics snapshot**）。`SensorService.step(dt, snap)` 的输入覆盖机制存在但主线从未使用。⇒ 同一目标 **融合航迹 20.0 km vs PhysicsWorld 真值 420.0 km**；600 s 后实测 `track.range_km=20.000` vs `physics.range=420.203`，**差 400.203 km**。火控门禁读航迹、弹道解算读真值。（CONFIRMED，最高严重度）
2. **实体静态元数据没有权威承载层**：`WorldState._normalize_entity()` 只保留 8 键（`id/kind/name/pos_km/vel_kmps/flags/alive/version`）；`PhysicsWorld.upsert_entity()` 只保留运动学+质量+姿态。⇒ side/identity/batch/rcs/radius/has_pd/facility_id/transponder_profile 在运行时两个容器都丢失。实测 `_ballistics_states[harmattan]` 得到 `side="" rcs_m2=0.0 ir=0.0 has_pd=false radius_km=0.06`（scenario 真值 0.09）；e2e 实测 **5 处** CONTACT SIDE MISMATCH，逐实体复核实际 **6/7 行** side/type 不正确（含未被 e2e 计数的 `l1_station`）。（CONFIRMED，Issue #2/#4 共同核心）
3. **WorldState 位置副本在 tick 中永不更新**：`GameSession.tick()` 只推进 PhysicsWorld，不调用 `sync_world_from_physics()`（全仓 grep：仅显式 API、command-dispatch、tests 引用）。实测 10×60 s 后 `world moved_km=0.000000` vs `physics harmattan moved_km=11.999993`。⇒ `snapshot().entities`、contacts、存档读回的 world 位置均落后于真值，而 `plot_positions()`/弹道读真值 → **同一屏位置语义分裂**。（CONFIRMED 设计边界；影响已量化）
4. **存档/读档保留双状态，且成本随 tick 线性膨胀**：`save_state()` 存 seed+log+physics/track/identification 等组件，**不存 world 快照**；`load_state()` = boot(seed)+重放全部 log+覆盖组件快照。实测 harmattan physics r 往返误差 `<1e-6 km`，但 world 仍是 seed/重放位置。实测 50/200/800 tick：存档 **310,899 B / 794,249 B / 1,656,569 B**，读档 **1.1 s / 5.3 s / 38.5 s**（≈ 重放全部 tick）。`save_probe` 153/3 根因已定位：恢复 bus 事件时 `JSON.parse_string(JSON.stringify(evs))`（`game_session.gd:4494`）把 `seq` 由 int 变 float（`1`→`1.0`）。（CONFIRMED，Issue #2.5）
5. **SensorService 运行态完全未持久化**：`save_state()` 无 sensor 运行态段（仅 seed 静态配置）、服务无 save/load API。实测保存前 `emcon=true radar=false`，读档后 `emcon=false`。（CONFIRMED，A0 新发现）
6. **身份链是“证据驱动”的 advisory 管线，且存在双身份与真值冲突**：TrackTable 单写者只接收 observation(support≤2)/evidence 白名单事件；identity 只能来自 evidence；IdentificationService 只输出评估、不写 TrackTable；manual_confirm 只写 assessment、不回写 TrackTable。`_sensor_config()` 又把 harmattan 配成 `side=friend / iff_code=FRIEND-1001`，与 scenario truth=hostile 冲突，运行时 `IDENT IFF harmattan OK identity friend` 与 track identity=unknown、truth=hostile **三态并存**。（CONFIRMED）
7. **EW 为开环、orbital_sim 未装 transponder**：`ew_service` 的 `observation_effect/comms_effect/transponder_effect` 在 SensorService/TrackTable/IdentificationService/Combat 中**无任何消费者**；`_scenario_seed()` 未装 `transponder_service` → 运行时 INTERROGATE 返回 `no_transponder_service`。身份证据只剩 IFF/光学/手动。（CONFIRMED）
8. **frame/epoch 契约不统一**：WorldState 实体无 frame 字段；prelude 路径 world apsis `[0,0,0]` vs physics bary_rot `[321710.1875,0,0]`（差 **321,710.188 km**，同一实体两个语义空间）；orbital_sim 因显式 `frame_origin=bary_rot` 未转换（`converted=0`），但 `_is_prelude_seed()` 的 id 列表启发式仍因 `ferry/watchtower` 命中而报 `auto_prelude=true`（当前被显式 origin 短路，若缺省则是风险）。scenario `"epoch":"2193-04-11T08:00:00Z"` 在 mainline 无消费者，TimeService 默认 `epoch_s=760.8`。（CONFIRMED）
9. **契约系统检测不到上述漂移**：`GameSession.check_contracts()` 只校验 physics **时间**==now 等，没有“world 位置==physics 位置/消费者同源”不变量 → C1/C2/C3 缺陷存在时，`physics_world`（217/0）、`session`（1534/0）、`e2e`（153/0）等关键 probe 仍保持 green；另有 8 个 Phase 0 已登记 FAIL（save/display 等）与本条无关、保持可见。（CONFIRMED）
10. **权威语义自相矛盾**：TrackTable VM 自报 `authoritative=false`、CIC `truth=false`、ident `truth=false`，但火控/UI 把 TrackTable 当操作性真值消费。（CONFIRMED，架构语义）
11. **legacy V15 平行事实源不可达当前产品入口，但仍被 probe 使用**：`main.tscn`→`main.gd`（state.gd + framework_bridge V2World）只被 orphan `intro.gd` 引用；产品路径 main_menu→prologue→nav/port→v1_hud。`v17_physics_*`/`v17_sensor_authority_display` 测的是 legacy bridge。其中 display probe 71/3 的根因已定位为 bridge 的 own-track 跳过 + `world.own_id=harmattan` 与 own track 1000 APSIS 错位（非内容漂移）。（CONFIRMED 于 bridge 路径；对产品主线的可达性为 RISK）

**结论**：Phase A 不应从“改 UI/加功能”开始，而应按以下顺序：**(a) 建立 truth→observation→track→identity 的分级与同 tick 回归探针（先红后绿）；(b) 为实体静态元数据确定唯一权威承载（不塞进 PhysicsWorld/WorldState 的演化状态）；(c) 把 SensorService 输入绑定到 PhysicsWorld/实体权威且保留可回退 profile；(d) 收敛 world/契约/存档/身份/EW 的边界。** 详见 §7–§9。

---

## 1. 仓库/基线状态核对

| 项 | 实际值 |
|---|---|
| 调查分支 | `phase-a0/physics-info-authority-audit`（从 `origin/phase0/issue-14-ci-closeout` `7d8a60f` 建立） |
| `main` | `62356da 方案B-40…`（**未包含** Phase 0 改动；#12/#13/#15 均 OPEN） |
| Phase 0 验收 | `docs/54_Phase0_验收报告.md`：独立验收 APPROVE；**最终实现 head `66ac179`** 的 clean run 39801912830（gate 6/6、完整矩阵 64 PASS / 8 FAIL / 0 TIMEOUT / 0 NOT RUN）。本 A0 worktree 的 head `7d8a60f` 是 PR #15 的 docs-only head：其 run 39805951992 两 check pass（记录在 PR #15 描述中，**不在 docs/54 内**）。 |
| 工作区 | tracked diff 为空（仅 `.import` CRLF stat-dirty 属噪音）；非噪音项仅为**未跟踪**的新报告 `docs/55_PhaseA0_…md`；提交前无游戏/测试/profile 改动。 |
| 引擎 | Godot `4.7.2.stable.official.ed1daf0bf`（`tools/godot/Godot_v4.7.2-stable_win64_console.exe`） |
| 探测总量 | A0 三路调查共实跑 **48 个 probe 次**（29 + 11 + 8，含重叠），**0 TIMEOUT**；FAIL 全部为 Phase 0 已记录的 8 个 pre-existing FAIL 中与 A0 相关者（`save 153/3`、`sensor_authority_display 71/3`、`plot_tws 58/1` 等），计数与 `docs/54` §2.1 一致，**无新增失败** |

---

## 2. 真实调用链

### 2.1 启动/装配链（当前 orbital_sim / sandbox）

```text
main_menu.tscn（BuildProfile.is_simulation() 自动跳过）
  └─ v1_hud.tscn :: V1HUD._ready()
       └─ ShellBinder.boot()                                   [shell_binder.gd:120]
            ├─ BuildProfile.setup()                           build_profiles.json
            ├─ PreludeScenario.new().setup()                  （模拟器路径不使用）
            ├─ _sensor_config()                               [shell_binder.gd:387-411] ← 演示静态几何
            └─ _scenario_seed(sensor_cfg)                      [shell_binder.gd:417-488]
                 ├─ entities = scenario.entities.duplicate()   [:432] ← 完整元数据仅存 seed
                 ├─ sensor_service = sensor_cfg                [:438] ← 演示静态几何
                 ├─ physics_world = true                       [:439]
                 └─ seed_frame/frame_origin = "bary_rot"       [:459-460]
                 └─ GameSession.boot(seed)                     [game_session.gd:173]
                      ├─ world = WorldState.new(...)           [:234]
                      ├─ _setup_optional_components()          [:378 → :648]
                      │    └─ physics_world_service = PhysicsWorld.new({})   [:648]
                      │    └─ _seed_physics_entities({})       [:653 → :750-802]
                      │         └─ PhysicsWorld.upsert_entity  [physics_world.gd:127-186]
                      │              ⚠ 只保留 r/v/mass/attitude/frame/时间戳
                      ├─ seed 实体 → bus.publish(entity.spawn) → world.apply(...)  [:295-308]
                      │    └─ WorldState._normalize_entity()   [world_state.gd:217-227]
                      │         ⚠ 只保留 8 键（丢 side/identity/batch/…）
                      ├─ 各组件 t = now_s()（physics.set_time :342-343）
                      └─ booted = true
```

**三份位置/元数据载体**：`seed`（完整 JSON，存档保留）→ `WorldState.entities`（8 键副本，tick 不更新）→ `PhysicsWorld.entities`（运动学真值，tick 推进）。**不是单一权威链。**

### 2.2 每 tick 物理/编排链

```text
GameSession.tick(dt)                                          [game_session.gd:964-1045]
  ├─ time.tick(dt) → sim_dt                                   [:978]
  ├─ _advance_physics(sim_dt)                                 [:983 → :1436-1444]
  │    └─ PhysicsWorld.step(sim_dt)                           [physics_world.gd:218-269]
  │         └─ RK4 积分每实体；t += dt；Jacobi 诊断            [:235-269] ← 唯一位置/速度推进点
  │    ✗ 不写 WorldState（sync_world_from_physics 不在 tick 内）
  ├─ orders.tick / _advance_components(track_table.tick/story) [:984-988]
  ├─ _advance_ballistics(sim_dt)                              [:989 → :1684-1751]
  │    └─ _ballistics_states()                                [:1616-1665]
  │         ├─ _entity_kinematics(): physics 优先，否则 world  [:1591-1613] ← 位置/速度=truth
  │         └─ world.entity() 取 side/has_pd/rcs/ir/kind/radius [:1645-1664] ← 元数据已丢
  ├─ _advance_sensors(sim_dt)                                 [:990 → :1072-1136]
  │    └─ sensor_service.step(sim_dt)（无 snapshot 实参）      [sensor_service.gd:268-296] ← 静态输入
  │         └─ 用 boot 时静态 observer/targets 出 observation/evidence
  ├─ signal/ew/port+combat/damage/transponder/identification/legal/traffic tick
  └─ snapshot()                                               [:4187-4247]
       ├─ "entities":  world.entities_sorted()                [:4213] ← 8 键副本（tick 后仍是 seed 位置）
       ├─ "physics":   physics_world_service.snapshot()       [:4220] ← 运动学真值 + b64 双精度
       └─ "physics_frame": physics_frame_meta()               [:4221]
```

### 2.3 信息链（Sensor → Observation/Evidence → Track → Identity → UI）

```text
shell_binder._sensor_config()                                  [shell_binder.gd:387-411]
  observer apsis [0,0,0]；harmattan [20,0,0] side=friend iff=FRIEND-1001；l1_station [0,0,10]
        │（静态演示几何；与 scenario_orbital_sim.json 的 EML1 bary_rot 真值无关）
        ▼
SensorService.step(dt)（无 snapshot 覆盖）                     [sensor_service.gd:268]
  ├─ V2SensorAuthority（shadow：authoritative=false）          [framework/sim/sensor_authority.gd:20/48]
  │     → sensor_observation.v1（support 1-2，L1/L2）          [sensor_service.gd:329-360]
  └─ IFF/optical 仅显式 query/lock → track_evidence.v1         [sensor_service.gd:409-445]
        │（IFF 模型 never_hostile；identity 只会 friend/unknown）
        ▼  GameSession._advance_sensors 白名单路由              [game_session.gd:1072-1136]
  ├─ observation(support 1..2) → track_table.handle_observation
  │      track.range_km = observation.range_km（来自静态目标几何） [track_table.gd:268-269]
  └─ evidence → track_table.handle_evidence → identity/level    [track_table.gd:287-549]
        └─ _bridge_identity_evidence → identification_service.ingest
              assessment（advisory；手动确认只写 assessment，不回写 TrackTable）[game_session.gd:3267-3305]
        │
        ▼
ShellBinder.refresh() → track_vm + contacts                    [shell_binder.gd:562-583]
  ├─ _build_contacts(): track 行 side = entity.side（缺）→ track.identity；ENTITY 行 side 缺省 "friend"  [shell_binder.gd:586-660]
  ├─ ident_view(row) = identification assessment（advisory）    [shell_binder.gd:1789]
  └─ plot_positions(): physics 优先（truth）；否则 snapshot/world fallback [shell_binder.gd:1438-1474]
CICView（truth=false，ownship+bearing+range 派生，不读 Physics truth）[cic_view.gd:11/232-233]
```

### 2.4 存档/加载链

```text
GameSession.save_state()                                       [game_session.gd:4257-4295]
  = seed(JSON，保留完整 scenario 实体字段) + log(操作重放) + track_table.snapshot()
    + physics_world.save_state() + identification/transponder/signal/ew/legal/traffic/ballistics/port/combat/damage…
    ✗ 不含 world.snapshot()；✗ 不含 sensor 运行态
GameSession.load_state(json)                                   [game_session.gd:4297-4509]
  = schema 校验 → boot(seed)（world 从 seed 重建；physics 先按 seed 灌入）
    → replay(log)（≈ 重放每个 tick；bus 事件 seq 经 JSON 后 int→float）
    → 覆盖组件快照（track/physics/identification…）
    ✗ 读档后不做 physics → world 同步；world 位置保持 seed/重放值
```

---

## 3. 状态读写责任矩阵（现状）

图例：✅ 唯一权威写者；⚠️ 派生/副本；❌ 无权威承载；— 不适用。

| 状态域 | 当前权威写者 | 副本/派生 | 读者 | 持久化 | 状态 |
|---|---|---|---|---|---|
| 位置/速度（运动学） | `PhysicsWorld.step()`（bary_rot） | WorldState（boot 后不更新）；seed entities（初始） | `_entity_kinematics`/`_ballistics_states`（physics 优先）、`plot_positions`（physics 优先）、`snapshot().entities`（world，非 physics）、UI fallback | physics save/load（b64 双精度） | ✅/⚠️ 双副本、无自动同步 |
| 实体 ID/kind/name | seed → WorldState spawn（normalize 保留） | PhysicsWorld id 集合 | contacts/ballistics/UI | seed 完整保留 | ✅（ID 稳定） |
| side/faction | ❌ 无权威承载（scenario 有、world/physics 均丢） | `_sensor_config` targets 的 side（friend，演示值）；facility_registry 的 side（仅设施） | `_build_contacts`（回退 track identity/“friend”）、`_ballistics_states`（取不到） | seed JSON 有；运行时无 | ❌ 丢失/默认值 |
| identity（身份） | `TrackTable` 单写者（只由 evidence 事件写；support 3-4） | IdentificationService assessment（advisory，`manual_confirm` 不回写 track）；legacy state.gd（V15，非产品入口） | UI contacts/ident overlay、combat `_is_hostile` | track_table snapshot + identification save | ✅（track）/⚠️（assessment 独立、无优先级） |
| batch/rcs/radius/has_pd/facility_id | ❌ world 规范化丢失；facility 映射从 facility_registry 补 | seed JSON；`_default_radius_km` 兜底 | contacts 显示、ballistics 命中/PD 判定 | seed 有 | ❌ 丢失 |
| track level/range/bearing/confidence | TrackTable（observation/evidence 更新；range=观测值） | CICView 派生位置（ownship+bearing+range） | 火控（out_of_range/tof/accuracy）、UI/CIC | track_table snapshot | ✅（单写者）/⚠️（与 physics 不同源） |
| 时间/epoch/frame | TimeService（epoch_s + t） | PhysicsWorld t（相对）；world clock_t_s | 所有组件 | time/physics save | ⚠️ scenario.epoch 未被消费；无统一 epoch 契约；world 无 frame 标记 |
| EW 效果 | EWService（效果表/事件） | — | **无消费者**（仅 session 包装/probe） | ew save | ❌ 开环 |
| 损伤/弹药/港口/交通 | 各自服务（单写者） | — | UI/VM | 各自 save_state | ✅（组件级） |
| story | StoryState（仅 full profile） | — | UI/触发器 | story snapshot | ✅（模拟器不装） |

---

## 4. 已证实问题清单（CONFIRMED）

> 每条：现象 → 代码位置 → 运行证据 → 影响。运行证据均来自本轮 A0 worktree；证据文件路径见 §10。

### C1. 传感器观测输入几何与物理真值脱钩（Phase A #4 核心，最高严重度）
- **代码**：`ShellBinder._sensor_config()`（`shell_binder.gd:387-411`）硬编码 observer `[0,0,0]`、`harmattan [20,0,0]`、`l1_station [0,0,10]`；`GameSession._advance_sensors()` 调 `sensor_service.step(sim_dt)`（`game_session.gd:1075`，**无 snapshot 实参**）；`SensorService.step(dt, snap := {})` 的 snapshot 覆盖机制存在（`sensor_service.gd:268-282`）但主线未使用；观测的 `range_km` 直接写入 track（`track_table.gd:268-269`）。
- **运行证据**：
  - e2e（exit 0，PASS=153）：`[E2E] INFO physics truth range apsis→harmattan = 420.0 km（航迹融合值 20.0 km）`；
  - A0 物理链诊断脚本（600 s）：`[A0-PC] GATE-RANGE track.range_km=20.000 physics.range_km=420.203 delta_km=400.203`；
  - 真值几何注入诊断：`[B] SAME-TICK track.range_km=420.0 vs physics truth=420.0 km`（同 tick 完全一致）。
- **影响**：火控 `SOLUTION/FIRE` 门禁使用 track.range（`combat_service.gd:472-475/532-541/570-572`），弹道初始状态使用 physics truth（`game_session.gd:1591-1665`）→ 同一目标在两套几何下交战；UI 距离显示 20 km。**这是 Issue #4 的最高优先级缺陷，也是 #3（真实战斗闭环）的前置。**
- **修复可行性（已运行验证）**：把 scenario/physics 真值几何注入 SensorService 后，同 tick track.range == physics truth（420==420）。⇒ 只需把“传感器目标几何”绑定到场景/物理真值（仍需处理观测误差/帧/时间戳契约），融合数学无需重写。

### C2. 实体静态元数据无权威承载层（Phase A #2/#4 共同核心）
- **代码**：`WorldState._normalize_entity()`（`world_state.gd:217-227`）只保留 `id/kind/name/pos_km/vel_kmps/flags/alive/version`；`GameSession.boot()` 的 seed spawn 走 `world.apply()`（`game_session.gd:295-308`）；`PhysicsWorld.upsert_entity()`（`physics_world.gd:127-186`）只存运动学/质量/姿态。⇒ scenario 的 `side/identity/batch/rcs_m2/radius_km/has_pd/facility_id/transponder_profile` 在两个**运行时容器**都没有承载（说明：scenario 文件/`seed` 仍保留完整字段；facility_registry 只对设施提供 side；缺口在 PhysicsWorld/WorldState 及之后的 contacts/ballistics 读取）。
- **运行证据**：
  - `world.harmattan keys=[alive, flags, id, kind, name, pos_km, vel_kmps, version]`；`WorldState harmattan side?=false identity?=false batch?=false`（两个 session 均 false）；
  - `physics_state(harmattan)` keys 无静态元数据（只有 kinematics/jacobi/energy）；
  - `_ballistics_states[harmattan]` 实测：`side="" rcs_m2=0.0 ir=0.0 has_pd=false radius_km=0.06`（scenario 真值 `0.09`）；
  - e2e `CONTACT SIDE MISMATCH n=5`：`harmattan(truth=hostile,contact=unknown,badge=TRACK)`、`ferry(neutral→friend,ENTITY)`、`raider_2(hostile→friend,ENTITY)`、`skiff(hostile→friend,ENTITY)`、`watchtower(neutral→friend,ENTITY)`；A0 逐实体复核实际 **6/7 行** side/type 错误（另含 `l1_station`：truth friend→contact unknown；6/7 由 contacts 构造路径 + `track_vm` 实际值推导，逐实体 dump 见 `sensor_chain.md`）。
- **派生影响**：`_ballistics_states()` 从 `world.entity()` 取 side/has_pd/rcs/radius（`game_session.gd:1645-1664`）→ 默认/兜底；`_build_contacts()` 对无 track 实体 `side` 缺省 `"friend"`（`shell_binder.gd:649`）；track 行 side 回退 track.identity（`shell_binder.gd:603`）。**身份显示/PD/命中特征不能依赖真实平台配置。**

### C3. World 位置副本在 tick 中永不更新（“显式同步边界”）
- **代码**：`GameSession.tick()`（`game_session.gd:964-1045`）调用 `_advance_physics` 后不再写 world；`sync_world_from_physics()`（`game_session.gd:2883`）只在显式 API/command/tests 被调用（全仓 grep；业务路径 0 调用）。`snapshot().entities = world.entities_sorted()`（`:4213`）；`plot_positions()` 在 physics ready 时用 physics，否则用 `snapshot`（`shell_binder.gd:1438-1474`）。
- **运行证据**：10×60 s 后 `world harmattan moved_km=0.000000` vs `physics harmattan moved_km=11.999993`（apsis：world 0 vs physics 0.000001）；`session_probe` PASS=1534 且 DATA 行明示 `tick 先 physics · world 不自动同步 · 显式 sync`。
- **定性**：这是文档化设计（`game_session.md` §3.1/§7：不自动同步、不双写），**不是隐藏 bug**；但它意味着 `snapshot().entities` 位置/`_build_contacts` 元数据 fallback/存档后 world 位置**不是当前物理真值**，而 UI fallback 与存档消费者并未显式区分。**影响已量化，TO-VERIFY 仅剩“每个消费者是否显式选择 truth”清单化。**

### C4. 存档/读档：双状态 + 类型漂移 + 线性成本（Phase A #2.5）
- **代码 + 失败断言**：`save_probe.gd:180/399/423` 三条 `loaded.snapshot()` 与保存前不一致；`save_state()` 不含 `world.snapshot()`（`game_session.gd:4257-4295`），`load_state()` 以 seed+log 重建 world 后不再同步 physics（`:4297-4509`）。
- **运行证据**：A0 worktree 实跑 `save_probe` → **exit 1，PASS=153 FAIL=3**；Phase 0 基线同 probe 153/3，内容一致。
- **根因（已定位，CONFIRMED）**：恢复 bus 事件时 `JSON.parse_string(JSON.stringify(evs))`（`game_session.gd:4494`）把事件 `seq` 由 int 变 float：`[A0-DIFF] roundtrip.events[0].seq TYPE a=2 b=3 a=1 b=1.0`；identification 同类漂移（`max_requests_per_tick 4→4.0`）。`session_probe` 的 `_norm_json` 归一化会掩盖该类型漂移。physics/track 服务级往返本身通过（physics b64 双精度，harmattan r 往返误差 `<1e-6 km`）。
- **规模成本（运行实测）**：50/200/800 tick → 存档 **310,899 B / 794,249 B / 1,656,569 B**；读档 **1.1 s / 5.3 s / 38.5 s**（≈ 重放全部 tick，load≈tick 总耗时）。**存档体积与读档时间随 tick 线性增长**，需纳入 Phase A 设计预算。

### C5. SensorService 运行态未持久化（A0 新发现，CONFIRMED）
- **代码/证据**：`GameSession.save_state()`（`game_session.gd:4257-4295`）没有 `sensor_service` 的**运行态快照**（`sensor_service` 字符串仅因 `seed` 里含静态 sensor 配置而出现在存档 JSON 中，不是运行态）；`SensorService`（`sensor_service.gd`）没有 `save_state/load_state` API（对比 track/physics/identification 均有）。
- **运行证据**：保存前 `emcon=true radar=false` → 读档后 `emcon=false`；`save_state has sensor_service=false`（运行态）；sensor 组件 DIFF 长度变化 9542→9193。
- **影响**：读档后传感器行为静默改变（EMCON/雷达开闭/通道），且不会报错；对 Phase A #4 的“可重复/可审计信息链”构成直接风险。

### C6. 双身份链 + IFF 配置与真值冲突（Phase A #4）
- **代码**：`TrackTable.vm()` 自报 `"authoritative": false`（`track_table.gd:876`）；track.identity 只由 evidence 写（`track_table.gd:287-549`）；`ShellBinder.ident_view()` 只读 IdentificationService assessment（`shell_binder.gd:1789-1850`）；`manual_confirm` 只写 assessment、不回写 TrackTable；contacts 行同时带 track `identity` 与 assessment `ident`（`shell_binder.gd:602-633`）。`_sensor_config()` 给 harmattan 配 `side=friend / iff_code=FRIEND-1001`（`shell_binder.gd:390-401`），与 scenario truth=hostile 冲突；IFF 模型 `never_hostile=true`。
- **运行证据**：
  - HUD 自测（既有 env hook，headless 行为观察非 PASS/FAIL）：`[V1 HUD] IDENT IFF harmattan OK identity friend`；同场景 e2e `fusion_identity=unknown`、`truth_side=hostile` → **三态并存**；
  - `v17_sensor_authority_display_probe` exit 1（PASS=71 FAIL=3）：`track 1000 level actual=4 expected=2`、`identity actual=friend expected=unknown`、`sources actual=[] expected=["YW-R9"]`。根因（A0 定位）：legacy bridge 的 `_fw_apply_sensor_authority_display()` 跳过 own track（`state.gd:2954-2957`），且 V15 `world.own_id=harmattan` 与 own track 1000 APSIS 错位 → advisory 把本舰当 unknown。属 **bridge 架构性失败**，非内容漂移（证据：`sensor_chain.md` §471-475）。
- **影响**：玩家看到的“身份”可能来自 assessment（advisory），火控/PD 读 track.identity/世界侧数据；同一实体可能存在 truth、IFF、track、assessment 四个不一致的“身份”。必须建立来源标签与优先级契约（LIVE/ADVISORY/UNAVAILABLE）。

### C7. 显示层存在两套位置语义
- **代码**：`plot_positions()` 物理优先（`shell_binder.gd:1441-1457`，source=physics）；`CICView` 明确不读 Physics truth，位置由 `ownship+bearing+range` 派生且 `position_truth=false`（`cic_view.gd:11/18/232-233`）；contacts.range_km 来自 track（观测几何）。
- **运行证据**：e2e `fusion 20 km vs truth 420 km`；plot 与 CIC 对同一目标使用不同来源。
- **定性**：CIC 的“不读 truth”是设计声明（信息战游戏应显示不确定信息），**但必须由同一观测管线的真实量派生**；当前观测几何是静态配置值，因此 CIC/TWS 的“非真值”并非来自物理世界。

### C8. frame/epoch/时间契约未统一（Phase A #2.3）
- **代码**：PhysicsWorld 只存相对 `t`（秒），FRAME=bary_rot，ALT_FRAMES=earth_eci/earth_rot（`physics_world.gd:21-23`）；WorldState 实体无 frame 字段；scenario `"epoch":"2193-04-11T08:00:00Z"` 未被 session/physics 消费（grep：仅 legacy `framework/core/scenario.gd` 读取）；TimeService 默认 `epoch_s=760.8`（`time_service.gd:16/48`）。
- **运行证据**：prelude 路径 world apsis `[0,0,0]` vs physics bary_rot `[321710.1875,0,0]` → 差 **321,710.188 km**（同一实体两个语义空间）。orbital_sim 因显式 `frame_origin=bary_rot` 未转换（`converted=0`）；但 `_is_prelude_seed()` 的 id 列表启发式因 `ferry/watchtower` 命中而报 `auto_prelude=true`（当前被显式 origin 短路；若未来缺省则触发 L1↔bary 转换）。
- **影响**：跨系统“同一时刻/同一位置”的含义依赖各服务自带的 epoch_s/t/frame，而不是 scenario；存档/多会话/未来星历接入时可能出现时间/坐标基准漂移。

### C9. 契约系统检测不到 world/physics/消费者漂移（Phase A #2.6）
- **代码**：`GameSession.check_contracts()`（`game_session.gd:4016`）只校验 physics **时间**==now、world 时钟、单写者等（physics 段 `:4078-4085`），**没有**“world 位置==physics 位置”“消费者读到同一来源”的不变量。
- **运行证据**：C1/C2/C3 缺陷存在的同时，`physics_world_probe`（217/0）、`session_probe`（1534/0）、`e2e`（153/0）等关键 probe 仍 exit 0；另有 Phase 0 已登记的 8 个 pre-existing FAIL（save/display 等）与本条无关、保持可见。⇒ **关键 probe 全绿 ≠ 权威链一致**。
- **影响**：Phase A 若不加不变量，修复可能回归且不可见。

### C10. EW 开环 + orbital_sim 未装 transponder（Phase A #4 信息链不完整）
- **代码**：`ew_service.observation_effect/comms_effect/transponder_effect` 在 SensorService/TrackTable/IdentificationService/Combat 中**无任何消费者**（仅 session 事件包装与 probe）；`_scenario_seed()`（`shell_binder.gd:417-488`）未装 `transponder_service`，orbital_sim 下 INTERROGATE 返回 `no_transponder_service`。
- **运行证据**：HUD 自测捕获 `OPTICAL IFF harmattan FAILED no_transponder_service`、`IDENT IFF harmattan OK identity friend`、`IDENT SUSPECT OK L4`、`COMBAT BALLISTICS impacts=1`；ew probe 252/0 只证明服务自身行为，不证明被集成。
- **影响**：EW 对“信息链”的影响没有进入观测/身份/火控；orbital_sim 默认身份证据只剩 IFF/光学/手动 → Phase A #4 的 ELINT/EW 验收不能建立在现有开环之上。

### C11. 权威语义自相矛盾（架构契约）
- **代码**：`TrackTable.vm()` `authoritative=false`（`track_table.gd:876`）、CICView `truth=false`（`cic_view.gd:11/132`）、ident assessment `truth=false`；但火控 `_is_hostile`/range 门禁与 UI 操作性消费 TrackTable。
- **运行证据**：`combat_service.gd` 直接按 track.range 判 out_of_range（C1 的 20 km 门禁即此路径）；e2e 用 track 选目标/开火。
- **影响**：没有“哪一层可以授权战斗/身份”的显式契约；修复 #4 时必须同时定义 truth/advisory/operational 三档语义，否则“advisory 被当权威用”会持续。

### C12. legacy V15 平行事实源：产品入口不可达，但 probe/bridge 仍活跃
- **代码**：`main.tscn`→`main.gd`（`state.gd` + `framework_bridge.gd` 的 V2World + shadow/authoritative adapter）只被 orphan `intro.gd` 引用（`intro.gd:34/208/384`）；产品路径为 main_menu→prologue→nav/port→v1_hud（`project.godot` 主场景 main_menu；`intro.tscn` 无产品入口引用）。`cislunar_physics.gd` 是两侧共用的纯数学库（非第二写者）。
- **运行证据**：`v17_physics_authoritative/display/shadow_probe` 全 exit 0（159/197/277）——它们测的是 legacy bridge；`v17_sensor_authority_display_probe` 71/3 的根因即 bridge 行为（C6）。未观察到产品主线实例化 state.gd（静态可达性核对）。
- **影响**：静态核对下当前产品入口无 world/physics 双写（运行时 hook 仍未做，见 R6）；但 Phase A 必须明确“legacy bridge 仅测试/演示，不得进入产品链路”，否则未来接入会形成第二事实源。

---

## 5. 风险假设清单（RISK / HYPOTHESIS）

| ID | 假设 | 依据 | 验证方式 |
|---|---|---|---|
| R1 | 每个 UI/战斗消费者是否显式选择 truth 副本尚未清单化；部分 fallback 可能长期显示旧位置 | C3 + `snapshot().entities` 读 world | A0-T1 扩展：消费者来源枚举 + tick N 后位置差 |
| R2 | 除已定位的 `seq`/`max_requests_per_tick` 外，存档中还有其它 int→float 字段 | C4 | A0-T3 类型稳定 canonical 断言全覆盖 |
| R3 | 传感器 targets 的 side/identity 与 scenario 真值冲突（harmattan friend vs hostile）会随“修几何”一起暴露为不一致 | `_sensor_config` L390-401 vs scenario truth | A0-T2 端到端断言（identity 三元组） |
| R4 | identification assessment 与 track.identity 长期分叉；manual 确认无法进入火控 | C6 | 固定证据序列 + manual_confirm 后比较 track/assessment/combat |
| R5 | `v17_sensor_authority_display_probe` 的 3 失败已定位为 legacy bridge own-track/`world.own_id` 错位；但产品主线是否也应支持该显示语义待确认 | C6/C12 | 不弱化断言的前提下，判断是修 bridge 还是迁移到 V17 authority；补产品入口显示探针 |
| R6 | legacy `state.gd`/`main.tscn`/`intro.tscn` 当前产品入口不可达（静态核对），但工具/演示入口仍可能被误接 | C12 | 入口枚举 + 运行时 hook（当前无运行时证据表明被实例化） |
| R7 | `sensor_authority.gd` shadow 模型与 SensorService 使用不同输入/姿态假设，切换 authoritative 会产生行为跳变 | shadow 注释 `authoritative=false`、attitude default | shadow vs live 只读对比探针 |
| R8 | FacilityRegistry 的 side 覆盖 contacts（`shell_binder.gd:674`）掩盖 world 元数据缺失，导致“部分实体有 side、部分默认 friend” | C2 + facility 映射逻辑 | A0-T2 对全实体断言 side 来源一致（同 loader） |
| R9 | ELINT-only / signal-only 目标可能绑定到 unknown_track（signal 目标注册表与 sensor target meta 不一致） | T12 A0-9 | 新增 ELINT-only 负例探针 |
| R10 | TrackTable 身份“最后写入者获胜”，无时间衰减/矛盾合并 | T12 A0-10 | 构造冲突证据序列 + 时间衰减断言 |
| R11 | 存档体积/读档时间随 tick 线性增长（1.66 MB / 38.5 s @800 tick）不可接受或会超时 | C4 实测 | 设计预算 + 读档优化（有快照时跳过 tick replay） |

---

## 6. 待运行验证事项（TO-VERIFY）

已由 A0 诊断闭环（不再列为 TO-VERIFY）：world/physics 冻结差（已量化 0 vs 11.999993 km）、save_probe 3 失败根因（int→float）、save 规模（已量化）、sensor 真值几何注入可行性（420==420）、SensorService 无持久化、legacy bridge display 失败根因。仍需验证：

1. 每个消费者（plot/contacts/ballistics/save/UI fallback）对 truth/advisory 的选择是否显式、是否有遗漏（R1）。
2. 存档中全部 int→float 漂移字段清单（R2）。
3. 产品主线是否需要、以及如何修复 legacy display 语义（R5）——先证明差异来源，再决定修 bridge 或迁移，不改写弱化断言。
4. legacy 入口是否被任何工具/自动化实际实例化（R6）——静态“产品不可达”已确认，运行时 hook 待做。
5. scenario epoch/frame 统一后的跨系统时间基准（C8/R7 相关）。
6. ELINT-only 绑定与 TrackTable 身份冲突合并（R9/R10）。
7. 1000+ tick 存档预算/读档性能是否满足 Phase A 验收（R11）。
8. 非 headless/渲染、文件级 SaveService round-trip、Linux/macOS wrapper：本 A0 未重跑（NOT RUN）。

---

## 7. 最小回归测试方案（方案，未实现；不修改现有测试）

> 原则：复用现有 probes；新增测试必须在当前代码上先红后绿（先证明缺陷，再修复）。所有 PASS/FAIL 来自真实运行。

### 7.1 现有覆盖与真实运行（本轮）

| 现有 probe | A0 实跑结果 | 与 A0 的关系 |
|---|---|---|
| `physics_world_probe.gd` | exit 0，PASS=217/0 | PhysicsWorld 单测：setup/帧/step/save-load/能量 |
| `cislunar_physics_probe.gd` | exit 0，PASS=269/0 | 物理数学/帧/单位 |
| `session_probe.gd` | exit 0，PASS=1534/0 | session 编排；含 physics 可选/显式 sync/save-load；DATA 明示 world 不自动同步 |
| `v17_physics_authoritative/display/shadow_probe.gd` | exit 0，PASS=159/197/277 | legacy bridge 子路径（非产品主线） |
| `e2e_orbital_sim_probe.gd` | exit 0，PASS=153/0 | 真实入口；20 vs 420 km、side mismatch 仅 INFO |
| `sensor_service_probe` / `track_table_probe` | exit 0，PASS=128/0、153/0 | 组件级观测/航迹管线 |
| `sensor_authority_probe` / `identification_probe` / `transponder_probe` / `ew_probe` / `signal_probe` / `info_warfare_probe` | exit 0，PASS=333/0、310/0、272/0、252/0、257/0、456/0 | 组件服务自测（不证明产品集成） |
| `v17_sensor_shadow_probe` | exit 0，PASS=108/0 | shadow 输出 |
| `save_probe.gd` | **exit 1，PASS=153 FAIL=3** | 存档/读档整快照一致性 |
| `v17_sensor_authority_display_probe.gd` | **exit 1，PASS=71 FAIL=3** | legacy display bridge（C6 根因） |
| `plot_tws_probe` / `v17_nav_integration` / `damage_integration` | FAIL 58/1、181/1、198/6 | Phase 0 pre-existing；与 A0 核心无关（T13 归 content/damage） |

> A0 三路调查共 **48 probe 次**（29 + 11 + 8，含重叠），**0 TIMEOUT / 0 新增失败**；FAIL 均为 Phase 0 已登记的 8 个 pre-existing（计数一致，`docs/54` §2.1/§13）。`save_probe` 与 `v17_sensor_authority_display_probe` 在 Phase 0 基线中即为 FAIL，A0 已定位根因（C4/C6）。

### 7.2 覆盖缺口矩阵（四个 A0 关键断言）

| # | 关键断言 | 现状 | 证据 |
|---|---|---|---|
| a | 融合航迹 range vs PhysicsWorld truth（同 tick） | **MISSING 断言**；e2e 仅 INFO（20 vs 420）；A0 诊断真值注入得 420==420 | `_sensor_config` L387-391；`track_table.gd:268-269` |
| b | side/identity/batch 从 scenario → PhysicsWorld → WorldState → snapshot → contacts 端到端保留 | **MISSING** | `world_state.gd:217`；`shell_binder.gd:603/649`；e2e mismatch n=5（实际 6/7） |
| c | physics/world/track/sensor/identity save→load 往返一致 | **PARTIAL + 真实失败** | `save_probe` 153/3（int→float）；sensor 无持久化；physics/track 服务级 PASS |
| d | 同 tick observation 与 truth 的误差/帧/时间戳一致性 | **PARTIAL** | physics 帧/单位有测；observation 输入几何无绑定断言 |
| e | 权威语义/来源标签（LIVE/ADVISORY/OPERATIONAL）与消费者一致性 | **MISSING** | C6/C11；display probe 失败 |
| f | EW/ELINT/transponder 对信息链的实际影响 | **MISSING** | C10；ew probe 未接产品链路 |

### 7.3 建议新增的最小回归（方案；未实现）

新增 3 个 `game_v17/tests/a0_*_probe.gd`，`category=integration`，timeout 180s；**不加入 `gates.phase0`、不加入 `known_baseline_failures.json`**。

| ID | 建议文件 | 关键断言（先红后绿） | 容差/依赖 | 覆盖 |
|---|---|---|---|---|
| A0-T1 | `a0_track_truth_authority_probe.gd` | 真实入口 session 每 tick：`track.range_km` == physics 距离；`track.t == physics.t == session t`；identity/threat 与 scenario truth 对照；sources/batch 可追溯；TrackTable 单写者；frame=bary_rot/km；消费者来源枚举 | ≤0.5 km；t ≤1e-6 s；真实 `main_menu→v1_hud→ShellBinder` | (a)(d)(e) |
| A0-T2 | `a0_entity_metadata_pipeline_probe.gd` | 7 个 scenario 实体的 side/identity/batch/rcs/radius/has_pd 在 PhysicsWorld→WorldState→snapshot→track/contact rows 逐项保留；缺失必须显式 `unknown`+原因，禁止静默 friend；6/7 错误行必须消失 | 按 entity_id 映射；facility 行允许 registry 来源但须一致 | (b) |
| A0-T3 | `a0_save_roundtrip_authority_probe.gd` | physics+world+track+sensor+identification save→load：数值 1e-9、整数类型稳定（seq/max_requests_per_tick 等）、sensor emcon/radar/channels 持久化、save→load→save canonical equality、1000 tick 预算/耗时记录 | 1e-9 / 类型断言；依赖 C4/C5 修复 | (c) |
| A0-T4（可选） | `a0_info_authority_provenance_probe.gd` | IFF/ELINT/EW/transponder 证据链：truth→evidence→track→assessment 的来源/时间戳/置信度/矛盾；包含 ELINT-only 负例、hostile-IFF 负例、EW effect 消费者断言 | 需 #4 设计；先只读记录 | (e)(f) |
| Phase 0 e2e（暂不改） | `e2e_orbital_sim_probe.gd` | **当前含 INFO 的 20 vs 420、side mismatch 暂不直接改 FAIL**（e2e 属 `gates.phase0`，Phase 0 已验收）；A0-T1 用独立探针复用真实入口承载 FAIL 断言。待项目负责人批准 gate 拆分后，再决定是否将 e2e INFO 升级为断言 | Phase 0 gate 语义保持不变 | (a)(b)(f) |

- **门禁与生命周期（与 Phase 0 隔离）**：
  - A0-T1..T4 注册到**Phase A 专用 gate**（建议 `gates.phaseA`），**不加入 `gates.phase0`**、不加入 `known_baseline_failures.json`；
  - #2/#4 实现前，这些探针在 Phase A 工作分支上应为 **expected-fail 基线**（证明缺陷存在）；`blocked:true` 仅表示“依赖 #2/#4 实现”，**不得作为跳过/不运行的借口，也不得标 PASS**；
  - e2e 的 INFO→FAIL 升级会改变现有 Phase 0 gate 结果：当前 e2e 属 `gates.phase0` 且 Phase 0 已验收，A0 不直接改 e2e；先由 A0-T1 用独立探针复用真实入口承载 FAIL 断言，保留 Phase 0 e2e 原样，待项目负责人批准 gate 拆分/Phase A 门禁后再迁移或加严；
  - CI 过渡期：新探针以独立 job/step 运行并如实报告红/绿，不得合并进 Phase 0 摘要或以 skip 造绿。
- 去重：physics save 单测复用 `physics_world_probe`；track 内部契约复用 `track_table_probe`；identification 证据复用 `identification_probe`；authority display 复用/重审 `v17_sensor_authority_display_probe`；真实入口复用 `e2e`。新增仅断言**跨组件权威不变量**，不重复组件单测。

---

## 8. Issue #2 / #4 建议拆分与依赖

> 以下为建议拆分，需项目负责人确认后另行开卡；A0 不实现。

### Issue #2（物理世界权威）建议子任务
| 子任务 | 内容 | 依赖 | 验收要点 |
|---|---|---|---|
| 2.1 | **实体身份/元数据权威承载**：定义 `EntityRecord`/entity metadata 唯一来源（建议独立 content/registry 或 world 静态属性，不塞进 PhysicsWorld 运动学）；scenario→physics→track/UI 全链引用同一 id+metadata | A0-T2 | 7/7 实体 side/identity/batch/rcs/radius/has_pd 保留；contacts 无 fallback |
| 2.2 | **位置/速度唯一权威与同步边界**：明确 PhysicsWorld 为唯一运动写者；world 仅为只读派生视图（或删除世界副本）；tick 后所有消费者（plot/contacts/ballistics/save）同源 | A0-T1/T3 | 同 tick 位置一致；无 world 副本歧义；消费者来源清单 |
| 2.3 | **frame/epoch/unit/time 契约**：scenario epoch、PhysicsWorld t、TimeService epoch、world frame 标记统一；存档/读档时间基准一致 | 2.2 | 帧/单位/时间断言；跨档一致 |
| 2.4 | **控制写路径收敛**：机动/对接/港口/交通对位置的写入必须经 PhysicsWorld API（禁止直接改 pos/vel） | 2.2 | 单一写者探针；命令取消/Δv 记账 |
| 2.5 | **save/load 一致性**：physics 位级 b64 + **类型稳定的 JSON 编码（C4：int 保持 int）** + world/snapshot 契约 + 旧档迁移 + 读档性能预算 | 2.2/2.3 | A0-T3 全绿；1000 tick 预算通过；旧档兼容 |
| 2.6 | **运行态持久化（跨组件）**：SensorService（C5）等缺 save/load 的服务补齐，或明确声明“可丢弃状态”并从 seed 重建；读档不得静默改变 EMCON/雷达/通道 | 2.2/2.5 | sensor emcon/radar/channels 往返一致 |
| 2.7 | **契约与门禁**：`check_contracts()` 增加 world/physics/消费者同源不变量；e2e 关键 INFO 升级为 FAIL 断言 | 2.2 | C9 探针；A0-T1 |
| 2.8 | **回归门禁**：A0-T1/T2/T3 + 现有 8 pre-existing FAIL 对照，不弱化 | 全部 | 真实运行证据 |

### Issue #4（传感器/航迹/IFF/ELINT/EW 信息权威）建议子任务
| 子任务 | 内容 | 依赖 | 验收要点 |
|---|---|---|---|
| 4.1 | **传感器输入绑定物理世界**：`_advance_sensors` 用 PhysicsWorld 真值 + 统一 entity metadata 构造 observer/targets；移除 `_sensor_config` 演示坐标；保留 profile 回退 | #2（2.1/2.2） | A0-T1 绿；track range 与 truth 一致（含噪声模型） |
| 4.2 | **observation/evidence schema 与 provenance**：明确来源（sensor/model/scenario）、support/level、时间戳、帧；把 e2e INFO 变成断言 | 4.1 | A0-T1/T4；无演示配置进入运行时 |
| 4.3 | **TrackTable 单写者/等级/身份权威**：identity 只由 evidence 写；track vs assessment 边界与 UI 契约；manual_confirm 回写规则 | 4.2 | track vs assessment 同源测试；UI 来源标签 |
| 4.4 | **IFF/ELINT/EW/transponder 证据收敛**：IFF 配置与场景 truth 对齐；transponder 在 orbital_sim 装配；EW effect 至少有明确消费者或显式标注“无消费者”；禁止直接写 track.identity | 4.3 | C6/C10；ELINT-only/hostile-IFF/EW 集成探针 |
| 4.5 | **UI 只读 VM / LIVE-ADVISORY-UNAVAILABLE**：CICView 派生量来自 4.2 的观测/航迹；contacts/ident 标注来源；plot truth 与 CIC 信息显示分层 | 4.3/4.4 | A0-T4；视觉/语义对照 |
| 4.6 | **显示权威语义修复**：`v17_sensor_authority_display_probe` 的 legacy bridge own-track/`world.own_id` 错位要么修 bridge、要么显式迁移并更新期望（先证明差异来源，不得弱化断言） | 4.3 | display probe 重新定义并通过 |
| 4.7 | **回归与门禁**：A0-T1/T2/T4 + e2e；现有 e2e 不回归 | 全部 | 真实运行证据 |

### 依赖关系（建议执行顺序）
```text
A0（本调查）
  └─ #2.1 元数据权威 + #2.2 物理单一权威 + A0-T1/T2/T3
        └─ 4.1 传感器输入绑定 + A0-T1
              └─ 4.2/4.3 证据 schema & TrackTable 权威 + A0-T4
                    └─ 4.4 IFF/ELINT/EW/transponder 收敛
                          └─ #3 战斗闭环（依赖 #2/#4）
                                └─ #6 交通/对接/港口物理联动（依赖 #2）
                                      └─ #8 UI 态势图、#7 改装真实效果（后续）
```
- 不建议先做 #8 UI：当前 CIC/plot 的差异根源是输入几何与元数据权威，不是 UI 绘制选择。
- #7 改装、#6 交通/对接均依赖 #2.2 的“位置唯一写者”与 #2.1 的实体元数据；否则会出现“改装参数/泊位状态与物理世界不一致”的同类问题。

---

## 9. 下一步最小修复方案（建议；本轮不实现）

排序原则：先测后改；先权威后 UI；每步可回退 profile + 回归门禁。

1. **先落 A0 回归探针（A0-T1..T3 + 可选 A0-T4）**：在现有代码上复现 C1/C2/C4/C5/C6，作为 **Phase A 专用门禁（`gates.phaseA`）** 的 expected-fail 基线；Phase 0 gate 保持原样（e2e 不直接加严，由独立 A0-T1 复用真实入口）。CI 区分“新探针（预期红→绿）”与“8 个历史遗留 FAIL”，不得 skip。
   - 影响：仅 tests + matrix + docs（不改运行时）；风险低。
2. **实体元数据权威层（#2.1）**：定义 entity 静态元数据唯一来源并通过 seed/loader 注入；`WorldState._normalize_entity` 保留/引用该元数据（或明确 world 不承载、由 registry 读）；`_build_contacts`/`_ballistics_states` 改读 registry，删除 `"friend"` fallback。
   - 影响文件：`world_state.gd`、`shell_binder.gd`、`game_session.gd`（`_ballistics_states`）、scenario/schema、相关 probes；风险中（多入口读取）。
3. **传感器输入绑定（4.1）**：`GameSession._advance_sensors` 从 PhysicsWorld + entity registry 构造 `{observer,targets}` 传入 `sensor_service.step(dt, snap)`；`_sensor_config` 降级为 dev fallback（仅 sandbox/测试 profile），orbital_sim 禁用；新增 profile 开关与回退；保留 TrackTable 单写者；同时对齐 IFF/side 配置（C6）。
   - 影响：`game_session.gd`、`shell_binder.gd`、`sensor_service.gd`（输入适配）、scenario；风险中高（track range/level 行为会变，UI/combat 需同步）。
4. **World 副本与同步/消费者策略（2.2）**：二选一：a) world 成为只读派生视图（tick 末同步或在读取时派生）；b) 删除 world 位置副本，snapshot 从 physics 派生。建议 a) 分阶段：先在 tick 末同步 world（由 session 单写者），再评估删除；同步后 `plot_positions` fallback/存档快照一致。
   - 影响：`game_session.gd`、`world_state.gd`、`shell_binder.gd`、save/load probes；风险中（tick 顺序/存档 schema 兼容）。
5. **存档一致性 + 持久化（2.5/2.6）**：修复 int→float 类型漂移（C4）；为 SensorService 补 save/load 或显式声明可丢弃状态并重建（C5）；决定 world 是否入档/读档后 sync；引入 1000 tick 性能预算；A0-T3 绿。
6. **身份/IFF/EW/UI 来源契约（4.3/4.4/4.5/4.6）**：IFF 配置与 truth 对齐；transponder 装配；EW 消费者/显式无消费者标注；contacts/ident 增加来源标签（LIVE/ADVISORY/UNKNOWN），track 与 assessment 字段在 VM 中分离但不互相覆盖；修/重审 legacy display bridge（先证明差异，不弱化断言）。
7. **契约与门禁（2.7/4.7）**：`check_contracts()` 增加同源不变量；e2e 关键 INFO 升级为 FAIL；把 8 pre-existing FAIL 继续隔离为 known-baseline（不隐藏）。
8. **清理/隔离 legacy 链（可选，低优先）**：确认 `state.gd`/`main.tscn`/`framework_bridge.gd` 不在产品入口可达后，标记 legacy/加隔离；不删除以免破坏旧能力。

**Phase A 放行门槛（建议）**：A0-T1/T2/T3（+A0-T4）全绿 + 真实入口 A0-T1 的 20km/420km、side mismatch、IFF/transponder 断言绿（Phase 0 e2e 在 gate 拆分批准前保持原样、仍 153/0）+ 现有 8 pre-existing FAIL 不变差 + Phase 0 gate 仍 6/6 + 默认 profile 不变 + 1000 tick 存档预算通过。

---

## 10. 证据附录（本轮真实运行）

环境：`D:\gt_a0`，Godot `4.7.2.stable.official.ed1daf0bf`；命令模板：`Godot_v4.7.2-stable_win64_console.exe --headless --path D:\gt_a0\game_v17 --script res://tests/<probe>.gd`；runner 命令见 T13 证据。

### 10.1 probe 实跑（三路调查汇总；日志在 gitignored `.test-results/a0/`）

| probe | exit | 结果摘要 |
|---|---|---|
| `physics_world_probe.gd` | 0 | PASS=217/0 |
| `cislunar_physics_probe.gd` | 0 | PASS=269/0 |
| `session_probe.gd` | 0 | PASS=1534/0；DATA：`tick 先 physics · world 不自动同步 · 显式 sync` |
| `v17_physics_authoritative_probe.gd` | 0 | PASS=159/0 |
| `v17_physics_display_probe.gd` | 0 | PASS=197/0 |
| `v17_physics_shadow_probe.gd` | 0 | PASS=277/0 |
| `e2e_orbital_sim_probe.gd` | 0 | PASS=153/0；INFO `420.0 km vs 20.0 km`；`CONTACT SIDE MISMATCH n=5` |
| `sensor_service_probe.gd` | 0 | PASS=128/0 |
| `track_table_probe.gd` | 0 | PASS=153/0 |
| `sensor_authority_probe.gd` | 0 | PASS=333/0 |
| `identification_probe.gd` | 0 | PASS=310/0 |
| `transponder_probe.gd` | 0 | PASS=272/0 |
| `ew_probe.gd` | 0 | PASS=252/0 |
| `signal_probe.gd` | 0 | PASS=257/0 |
| `info_warfare_probe.gd` | 0 | PASS=456/0 |
| `v17_sensor_shadow_probe.gd` | 0 | PASS=108/0 |
| `save_probe.gd` | **1** | PASS=153 FAIL=3：`往返 snapshot 一致`(:180)、`0.9 迁移后 snapshot 一致`(:399)、`缺 version 迁移一致`(:423) |
| `v17_sensor_authority_display_probe.gd` | **1** | PASS=71 FAIL=3：level 4≠2、identity friend≠unknown、sources []≠["YW-R9"] |
| `plot_tws_probe.gd` | **1** | PASS=58 FAIL=1（Phase 0 pre-existing，A0 非核心） |
| `v17_nav_integration_probe.gd` | **1** | PASS=181 FAIL=1（Phase 0 pre-existing，damage/nav） |
| `damage_integration_probe.gd` | **1** | PASS=198 FAIL=6（Phase 0 pre-existing，damage profile） |

> 合计 48 probe 次（含跨调查重叠），0 TIMEOUT；FAIL 全部为 Phase 0 已登记的 8 个 pre-existing（计数一致），**无新增失败**。

### 10.2 只读诊断脚本与量化输出（TEMP/gitignored，不属于仓库测试）

| 诊断 | 输出/证据 |
|---|---|
| `diag_authority.gd` | scenario truth 表（7 实体 side/identity/batch/pos）；`[A0-PC] GATE-RANGE track.range_km=20.000 physics.range_km=420.203 delta_km=400.203`；world 无 side/identity/batch；sensor emcon 未持久化；identification `max_requests_per_tick 4→4.0`；真值几何注入得 `[B] SAME-TICK track.range_km=420.0 vs physics truth=420.0 km` |
| `a0_physics_chain_inspect.gd` | 10×60 s：`world harmattan moved_km=0.000000` vs `physics harmattan moved_km=11.999993`；prelude frame 差 321,710.188 km |
| `a0_save_diff.gd` | `[A0-DIFF] roundtrip.events[0].seq TYPE a=2 b=3 a=1 b=1.0`（根因） |
| `a0_save_scale_inspect.gd` | 50/200/800 tick：310,899 B/1.1 s、794,249 B/5.3 s、1,656,569 B/38.5 s |
| `a0_contacts_inspect.gd` | contacts 逐实体 side/type（实际 6/7 错误）、`world.own_id=harmattan` |
| `a0_sensor_inspect.gd` | advisory/TRK 1000 状态（own 跳过、level 4/friend、batch 1000/apsis） |
| HUD 自测（既有 env hook；headless 行为观察，非 PASS/FAIL） | `OPTICAL IFF harmattan FAILED no_transponder_service`、`IDENT IFF harmattan OK identity friend`、`IDENT SUSPECT OK L4`、`COMBAT BALLISTICS impacts=1`；headless 绘制极慢，采集到所需行后手动终止 |

完整证据文件（gitignored）：
- `.test-results/a0/physics_chain.md`（物理链，724 行）
- `.test-results/a0/sensor_chain.md`（信息链，581 行）
- `.test-results/a0/test_plan.md`（测试/回归，574 行）
- `.test-results/a0/diag_authority.log`、`.test-results/a0/logs_physics/`、`.test-results/a0/probe_logs/`、`.test-results/a0/evidence/`

### 10.3 关键代码索引
- `game_v17/scripts/core/game_session.gd`：`boot` :173、`tick` :964、`_advance_physics` :1436、`_advance_sensors` :1072、`_seed_physics_entities` :750、`_entity_kinematics` :1591、`_ballistics_states` :1616、`sync_world_from_physics` :2883、`snapshot` :4187、`save_state` :4257、`load_state` :4297（bus 恢复 :4494）、`check_contracts`（physics 时间 :4078-4085）、`_bridge_identity_evidence` :3267。
- `game_v17/scripts/core/physics_world.gd`：`upsert_entity` :127、`step` :218、`state` :287（无 ok 字段）、`save_state` :699、`load_state` :724。
- `game_v17/scripts/core/world_state.gd`：`apply` :85、`_normalize_entity` :217、`snapshot` :289。
- `game_v17/scripts/core/sensor_service.gd`：`setup` :70、`step` :268、`_collect_observations` :329、`query_iff` :409。
- `game_v17/scripts/core/track_table.gd`：公开 `handle_observation` :203 / 私有 `_handle_observation` :226（`range_km` :268-269）、公开 `handle_evidence` :207 / 私有 `_handle_evidence` :287、`_set_identity` :543、`vm` :868（`authoritative:false` :876）。
- `game_v17/scripts/ui/shell_binder.gd`：`_sensor_config` :387、`_scenario_seed` :417、`refresh` :562、`_build_contacts` :586、`_refresh_cic` :1258、`plot_positions` :1438、`ident_view` :1789。
- `game_v17/scripts/core/cic_view.gd`：truth=false :11/:132；`position_source=ownship+bearing+range` :232-233。
- `game_v17/framework/sim/sensor_authority.gd`：shadow/authoritative=false :20/:48。
- `game_v17/scripts/core/combat_service.gd`：`register_track` :390、range 门禁 :472-475/:532-541/:570-572。
- `game_v17/scripts/core/identification_service.gd`：`ingest` :124、`assess`/`_recompute` :213/:277。
- `game_v17/scripts/core/transponder_service.gd`：`interrogate` :424、`_make_evidence` :566。
- `game_v17/scripts/core/ew_service.gd`：effect API（无消费者）。
- `game_v17/tests/save_probe.gd`：失败断言 :180/:399/:423。
- `docs/54_Phase0_验收报告.md` §2.1/§12/§13（Phase 0 基线、8 pre-existing FAIL、clean runs）。

---

## 11. 与 Phase 0 报告 / 审计文档的对照（精度修正，不构成矛盾）

1. `docs/54` 把 8 个 baseline FAIL 概括为“内容/契约漂移”：A0 精度化分出两类——`save_probe` 是 **JSON 类型契约漂移**（event `seq` int→float，C4）；`v17_sensor_authority_display_probe` 是 **legacy bridge 架构性不一致**（C6），不是内容同步。建议分别归入 #2.5 与 #4。
2. `docs/40` §3.1 将 PhysicsWorld 与 Sensor models 画为 GameSession 的**两条并行分支**；其目标意图是传感器消费权威物理状态，但 A0 证实 **V17 中这条输入边并不存在**（`_advance_sensors` 不传 snapshot）；#4 必须**新建**该输入边，而不只是收敛写入者。
3. `docs/54` §8 的两项 known gaps（20 km vs 420 km、`_normalize_entity` 丢 side）方向正确、无矛盾；A0 补齐精确代码行 + 量化：门禁差 400.203 km、world 冻结 0 vs 12 km、ballistics 默认 radius 0.06/rsc/ir 0、实际 6/7 contact 行错误、IFF 配置与 truth 冲突。
4. `docs/54` §9 “orbital_sim save round-trip NOT RUN”：A0 已做 **in-memory GameSession** round-trip（T11）；文件级 SaveService round-trip 仍未重跑（NOT RUN）。
5. `docs/54` e2e/boot 证据（e2e 153/0、12 系统 ready）在 A0 环境复跑仍成立。

---

## 12. 限制与未执行事项

- 本轮为**静态审计 + 现有 probe 运行 + 只读诊断脚本**：A0-T1..T4 为方案、尚未实现/入矩阵，因此 R1/R2/R4/R5/R9/R10 等仍需新测试定论（其余已闭环的量化见 §6）。
- 未执行：非 headless/渲染、文件级 SaveService round-trip、Linux/macOS wrapper、V15 旧场景实际运行、1000+ tick 全矩阵、UI/视觉验收。
- HUD 自测为 headless 行为观察（headless 绘制极慢，采集到所需行后手动终止），**不作为 PASS/FAIL 证据**。
- 未修改任何游戏实现/测试/默认 profile；`docs/54` 等只读；A0 worktree 的 **tracked diff 为空**，唯一新增是**未跟踪**的报告文件（待提交）。未进入 Phase B/C/D/E。

---

## 13. Phase A0 交付状态

- ✅ 当前真实调用链与数据流图（§2）
- ✅ 状态读写责任矩阵（§3）
- ✅ 已证实问题（CONFIRMED C1–C12）与风险清单（RISK R1–R11）（§4/§5）
- ✅ 最小回归测试方案（§7，A0-T1..T4 + e2e 隔离/后续升级策略 + 覆盖缺口矩阵）
- ✅ Issue #2 / #4 建议拆分与依赖（§8）
- ✅ 下一步最小修复方案与影响范围（§9）
- ✅ 证据附录（§10）与分类口径（CONFIRMED/RISK/TO-VERIFY）
- ✅ 与 Phase 0 报告/审计对照（§11，精度修正）
- ✅ **独立 verifier 审查：APPROVE**（必须修正项 M1–M6 已全部落实；审查证据 `.test-results/a0/verification.md`，独立复跑 e2e 153/0、save 153/3、session 1534/0、physics_world 217/0、display 71/3，并核验 ≥20 条 file:line 断言）
- ⏸ 待项目负责人与独立审查者确认后再开始实现；**不进入 Phase B。**
