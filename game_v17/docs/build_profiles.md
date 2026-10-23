# 版本划分 · 正式本体 / 正式拟真模拟器 / 开发测试 / 旧作战演示

> 工程 `game_v17`。配置：`framework/content/build_profiles.json`；
> 加载器：`scripts/core/build_profile.gd`；启动装配：`scripts/ui/shell_binder.gd`；
> 场景：`framework/content/scenario_orbital_sim.json`（正式拟真）、
> `framework/content/scenario_combat_sandbox.json`（旧演示，向后兼容）。
> 四个剖面**共用同一套系统代码与存档 schema**，只在「开机时装什么」上分叉。

## 1　为什么要分（Phase 0：模拟器优先）

一个交付物要同时满足几件事：

1. **正式本体**：剧情 + 事件状态机，玩家从主菜单进序章，逐步推进；
2. **正式拟真模拟器**：不演剧情，开机即战术台，用真实地月系轨道 + 完整系统
   （物理/传感器/识别/EW/战斗/弹道/损管/交通/港口/目录/改装）验收；
   不允许靠无限弹药/免授权制造「看起来能打」的假象；
3. **开发测试沙盒**：开发调试需要连续演示与快速重开，作弊项只能出现在这里；
4. **旧作战演示**：`combat_sim` 是历史入口，仅为向后兼容保留（deprecated）。

硬塞进一个入口会让两边都别扭。所以拆成**四个版本剖面（build profile）**，
而不是四份代码。**Phase 0 起以 `orbital_sim` 为交付验收目标**；剧情扩写暂停，
但剧情系统与接入契约原样保留（见 §7）。

## 2　四个剖面

| | `full`（正式本体） | `orbital_sim`（正式拟真） | `sandbox`（开发测试） | `combat_sim`（旧演示，弃用） |
| --- | --- | --- | --- | --- |
| label | GHOST TRACK // APSIS | GHOST TRACK // APSIS — ORBITAL SIM | GHOST TRACK // DEV TEST SANDBOX | GHOST TRACK // ORBITAL COMBAT SIM |
| 入口 | `res://main_menu.tscn` | `res://v1_hud.tscn`（主菜单自动跳过） | `res://v1_hud.tscn`（自动跳过） | `res://v1_hud.tscn`（自动跳过） |
| boot_mode | `prelude` | `simulator` | `sandbox` | `sandbox` |
| 实体来源 | `PreludeScenario`（序章内容） | `scenario_orbital_sim.json` | `scenario_orbital_sim.json` | `scenario_combat_sandbox.json` |
| 存档根 | `user://saves` | `user://saves_sim` | `user://saves_sandbox` | `user://saves_sim`（未改） |
| story / prelude / triggers | ✅ | ❌ | ❌ | ❌ |
| identification / signal | ✅ | ✅ | ✅ | ✅ |
| traffic / port | ✅ | ✅ | ✅ | ❌ |
| combat / ballistics / damage / physics_world | ✅ | ✅ | ✅ | ✅ |
| ship_catalog / refit | ✅ | ✅ | ✅ | ❌（旧矩阵不变） |
| sandbox_opts（无限弹药/免授权/快速重开） | ❌ 恒关 | ❌ **禁止，配置写了也强制关闭** | ✅ 三项全开 | ✅ 三项全开（旧行为） |
| limitations | — | 7 条｜见 §9 | 允许省略 | — |
| deprecated | ❌ | ❌ | ❌ | ✅ |

- 存档根分开是**故意的**：各剖面各玩各的，不会互相覆盖；schema 完全一致，
  存档本身互通（复制文件即可迁移）。
- `orbital_sim` 与 `combat_sim` 共用 `user://saves_sim` 是**固定兼容契约**
  （旧条目存档根禁止改动）；`sandbox` 单独用 `user://saves_sandbox`，
  避免测试档污染正式档。
- 默认剖面仍是 `full`（`build_profiles.json` 的 `"default": "full"`），
  `main_menu.tscn` 仍是主场景——**没有静默改变默认构建**。开发时用
  `DSH_BUILD=orbital_sim` 显式启动模拟器。

## 3　选择方式与启动命令

优先级从高到低：

1. `BuildProfile.new({"id": "orbital_sim"})` —— 代码显式指定（测试用）
2. 环境变量 `DSH_BUILD`
3. 配置里的 `"default"`（当前 `full`）

Godot：`Godot_v4.7.2-stable_win64_console.exe`（日志版本行
`Godot Engine v4.7.2.stable.official.ed1daf0bf`）。

```powershell
# ① 正式本体（序章 + 剧情，默认）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17

# ② 正式拟真模拟器（主菜单自动跳过，直接进战术台；无剧情、无作弊项）
$env:DSH_BUILD="orbital_sim"
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17

# ③ 开发测试沙盒（便利项全开，仅开发测试）
$env:DSH_BUILD="sandbox"
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17

# ④ 旧作战演示（deprecated，启动日志会打印弃用告警）
$env:DSH_BUILD="combat_sim"
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17
# 用完清掉：$env:DSH_BUILD=""
```

主菜单自动跳过只对**模拟类剖面**（`boot_mode=simulator|sandbox`）生效，
且 `DSH_SHOT`（截图模式）或 `DSH_NO_AUTOSKIP=1` 会阻止自动跳过，
方便给模拟器版本截主菜单图。真实本体（`full`）永不自动跳过。

## 4　启动日志契约

`ShellBinder.boot()` 是唯一真实启动装配点，按固定格式打印（测试/CI 按行 grep）：

```text
[BUILD PROFILE] id=<id> mode=<boot_mode> scene=<entry_scene> scenario=<scenario> save_root=<save_root>
[BUILD PROFILE] SYSTEM <feature>=ON                       # 每个 FEATURE 一行
[BUILD PROFILE] SYSTEM <feature>=OFF reason=<短原因>        # 关闭项必须带原因
[BUILD PROFILE][LIMITATION] <能力边界文本>                  # limitations 逐条
[BUILD PROFILE] WARN <校验告警>                              # 如 deprecated / 强制关闭
[BUILD PROFILE] ERROR <校验错误>                             # 如核心系统被关
[SHELL BINDER] SANDBOX entities=<n> scenario=<path>        # 模拟类剖面
[SHELL BINDER] SYSTEMS physics=<t/f> sensors=<t/f> track_table=<t/f> combat=<t/f> \
    ballistics=<t/f> damage=<t/f> ew=<t/f> identification=<t/f> traffic=<t/f> \
    port=<t/f> ship_catalog=<t/f> refit=<t/f> story=<disabled|ready|false>
```

- `SYSTEM` 状态来自 `build_profile.feature_status_vm()`：每个 `FEATURES` 键都有
  `enabled` 与 OFF 原因（story/prelude/triggers →「剧情扩写暂停（Phase 0）」，
  sandbox →「非测试剖面」，其余 →「未启用」）。
- `SYSTEMS` 行**只从真实服务对象读取**（service 存在且 `ready` 才 true，
  缺服务就是 false），不是配置回显。`story=disabled` 表示剖面关闭剧情
  （与「装了但没就绪 = false」「装了且就绪 = ready」区分）。
- `binder.systems_vm()` 返回与 `SYSTEMS` 日志同源的数据（探针/测试用），
  含 `schema/profile/mode/scenario/*就绪布尔*/story/writes{...}`。

## 5　加载器 API（`build_profile.gd`）

```gdscript
const BuildProfile := preload("res://scripts/core/build_profile.gd")
var bp = BuildProfile.new()                      # 按 config → env → default 选
var bp2 = BuildProfile.new({"id": "orbital_sim"})
var bp3 = BuildProfile.new({"content": {...}})   # 内联配置（测试用）

bp.ready                         # 读不到也 true —— 回退 full
bp.id / bp.label / bp.subtitle
bp.boot_mode                     # "prelude" | "sandbox" | "simulator"
bp.entry_scene / bp.scenario / bp.save_root
bp.enabled("story")              # 功能开关；FEATURES 见下
bp.sandbox_opt("unlimited_ammo") # 沙盒便利项；非 sandbox 剖面恒 false
bp.is_sandbox()                  # boot_mode == sandbox
bp.is_simulator()                # boot_mode == simulator（正式拟真）
bp.is_simulation()               # simulator 或 sandbox（跳过主菜单/装场景 seed）
bp.limitations                   # Array[String]：本剖面诚实的能力边界
bp.deprecated / bp.deprecated_reason
bp.feature_status_vm()           # {feature: {enabled, reason}}
bp.select("full")                # 运行时切换（只换开关，不重建服务）
bp.vm() / bp.summary()           # JSON-safe；均含 limitations/deprecated
```

`FEATURES`（配置缺项按 `false`）：`story, prelude, triggers, identification,
traffic, port, signal, combat, ballistics, damage, physics_world, sandbox,
ship_catalog, refit`。

`SANDBOX_OPTS`：`unlimited_ammo, auto_authorize, quick_restart`。

## 6　启动装配（`shell_binder.gd`）

`ShellBinder.boot()` 先加载剖面，再分支：

| 剖面 | 装配路径 |
| --- | --- |
| `full`（prelude） | `PreludeScenario.boot_config()` + story_state；行为与旧版本一致 |
| `orbital_sim` / `sandbox` / `combat_sim` | `_scenario_seed()`：读场景 JSON → session seed |

`_scenario_seed()` 装的东西（全部按剖面开关）：

- `entities / nodes / links`（来自场景，真实地月系几何）、`own_entity`；
- `track_table`、`sensor_service`、`physics_world`（`seed_frame/frame_origin`
  显式 `bary_rot`，禁止再套序章 L1 相对帧偏移）；
- `combat_service`（`roe/own_id/fleet_id` 来自场景 `combat`；
  `unlimited_ammo/auto_authorize` **只**来自 `sandbox_opt()`，`orbital_sim` 恒 false）、
- `combat_ballistics`（`pd_platform_id` 来自场景）、`damage_service`、`ew_service`、
  `identification_service`、`signal_service`、`traffic_control`、`port_service`、
  `ship_catalog`、`refit`、`facility_registry`（港口/交通需要的设施映射）；
- `story_state` **仅当** `build_profile.enabled("story")` 为真时装载。
  模拟器没有 story 时不报错、不产生伪造剧情 VM（`story_vm` 为空）。

旧 `combat_sim` 的入口/场景/存档根/便利项行为全部保持不变；`_sandbox_seed()`
作为 `_scenario_seed()` 的薄兼容包装保留。**full 的序章/剧情路径未删除、未改写。**

## 7　剧情保留声明（Phase 0）

- **暂停的是剧情扩写**（新章节/分支/对话/CG），不是删除剧情系统：
  `StoryState`、`PreludeScenario`、触发器、报告、信任等代码与 schema 原样保留；
- `full` 剖面仍按原行为加载序章与 `story_state`，启动 smoke 实测
  `prelude ready=true entities=9 triggers=3 used=true`；
- `orbital_sim` 通过 `features.story=false` 不装 story，但读取剧情状态的接口
  （`binder.story_vm`、`session.story_vm()`）仍存在，只是返回空——不报错；
- 没有任何剧情内容被写入模拟器场景；剧情接入契约见 `game_v17/docs/` 相关文档。

## 8　拟真约束（orbital_sim 无作弊项）

- 拟真剖面**不提供**无限弹药、自动授权、快速重开：
  `sandbox_opt()` 对非 sandbox 剖面恒 `false`；配置里给 `orbital_sim` 写了
  `sandbox_opts=true` 也会被**强制关闭并留告警**（`build_profile_probe` 有断言）。
- `sandbox` 剖面的便利项**只在 `boot_mode=="sandbox"` 时生效**；`full` 与
  `orbital_sim` 一律 false（防手滑给本体开作弊口子）。
- 拟真剖面校验（只 warning/error，不崩溃、不自动改配置去「凑绿」）：
  - `story/prelude/triggers` 必须关闭（配置写错则强制关 + 告警）；
  - 核心系统 `combat/ballistics/physics_world/traffic/port/identification`
    被关闭 → **error**（核心系统不得关闭后开机），且不自动开启；
  - 缺 `scenario` → error（实体表为空无法开机）；
  - `sandbox_opts` 被配置开启 → 强制 false + 告警；
  - `combat_sim` 等 `deprecated` 剖面被选中 → 告警。
- 例外：`unlimited_ammo` 只放宽弹药，不绕过冷却/射程/授权/解算门禁（见 §11）。

## 9　能力边界（`orbital_sim.limitations`，启动日志逐条打印）

正式拟真剖面必须诚实声明当前「未实现/近似」项（配置 `limitations` 数组，
≥6 条；`[BUILD PROFILE][LIMITATION]` 日志逐条输出）：

1. 轨道为 **CR3BP/RK4 近似**，不是 JPL 星历；高阶摄动/星历修正尚未完成（Phase A #2）。
2. EW 为**抽象效果服务**，不做 RF/波形/射频物理仿真（Phase A #4）。
3. 传感器/IFF/ELINT/EW 的证据写入者尚有 legacy 路径，唯一权威管线待收敛（Phase A #4）。
4. 交会/对接为几何与业务模型，尚未与真实推进、质量、Δv 完全耦合（Phase C #6）。
5. 交通管制/OTC 为业务模型：许可/队列/窗口尚未消费完整真实 RF 与交通流物理（Phase C #6）。
6. 舰船改装尚未完全影响权威物理/火控/战斗能力（Phase D #7）。
7. UI 高密度四区态势图的部分历史图层尚未恢复并通过验收（Phase D #8）。

这些边界来自审计文档 `docs/40_系统完成度复核与开发任务队列.md`，随对应 Issue
（#2/#4/#6/#7/#8）推进时应同步收缩该列表——**能力提升后要删条目，而不是只加功能**。

## 10　场景（`scenario_orbital_sim.json`）

正式拟真剖面场景，坐标系 **CR3BP 旋转系 bary_rot**，单位 km / km/s：

- 地球在 x ≈ −4671 km，月球在 x ≈ 379729 km；
- 态势位置在 **EML1**（x ≈ 321719 km）附近，7 个实体（APSIS / HAMATTAN /
  SABRE / CUTLASS / L1 MERIDIAN / WATCHTOWER / TENACITY）；
- 交战尺度覆盖三档：`skiff` ~117 km（点防）、`harmattan` ~420 km（实弹/导弹）、
  `raider_2` ~2500 km（仅导弹）；
- `combat.roe = "TIGHT"`（真实授权流程；无自动授权）、`own_id/pd_platform_id = apsis`；
- **不携带任何测试便利项**：无 `sandbox_opts`、无 `unlimited_ammo`/`auto_authorize`/
  `quick_restart` 字样；产品元数据含 `id/title/subtitle/description`。

**注意**：旋转系里「速度为 0」等于随系共转，不是惯性系静止。静止实体的
`vel_kmps` 写 0 是合理的，但它们在物理世界里的轨迹仍然是曲线。

**帧转换**：场景 seed 显式带 `seed_frame: "bary_rot"` / `frame_origin: "bary_rot"`，
禁止再套用序章的「L1 相对帧」偏移——否则整张图会被平移 32 万公里。

旧 `scenario_combat_sandbox.json` 保留给 `combat_sim`，几何相同，行为不变。

## 11　沙盒便利项（sandbox_opts）与旧演示兼容

| 便利项 | 效果 | 落点 |
| --- | --- | --- |
| `unlimited_ammo` | 弹药不扣减（railgun/missile/pd/decoy/jammer 全部），也不因弹药耗尽把 ROE 降级 | `combat_service.unlimited_ammo` |
| `auto_authorize` | FIRE 免授权（`confirmed` 仍必须），演示时可自由选目标 | `combat_service.auto_authorize` |
| `quick_restart` | HUD `F5` 一键按原场景重开（走 `shell_binder.quick_restart()` → 完整 `boot()`） | `v1_hud._sandbox_restart_enabled()` |

**刻意不做的**：`unlimited_ammo` 只放宽弹药，**不绕过**冷却、射程、ROE 降级之外的
任何门禁——`unknown_track`/`out_of_range`/`cooldown`/`no_ready_solution` 照旧拒绝。
`auto_authorize` 通过时 `_action_allowed()` 返回 `reason = "sandbox_auto_authorize"`
且 `sandbox = true`，事件流里能明确区分「真授权」和「沙盒放行」。

**旧 `combat_sim`**：入口/场景/`user://saves_sim`/三项便利项全部保持原样，
新增 `deprecated: true` + `deprecated_reason`，选中时会打印
`[BUILD PROFILE] WARN 选中的剖面 'combat_sim' 已弃用（deprecated）：...`。
新开发一律用 `orbital_sim`（正式拟真）或 `sandbox`（开发测试）。

## 12　验证（2026-10-22 本次实际运行）

环境：worktree `D:\gt_phase0`，分支 `feat/phase0-simulator-first`，
Godot `4.7.2.stable.official.ed1daf0bf`（命令统一为
`D:\gt_phase0\tools\godot\Godot_v4.7.2-stable_win64_console.exe`）。
以下均为**本次会话真实运行结果**，不是历史文档 PASS 数的复制。

### 12.1 剖面探针（配置/开关/校验/回退/场景/JSON）

```powershell
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/build_profile_probe.gd
# EXIT=0
# BUILD PROFILE PROBE RESULT: PASS=553 FAIL=0
# BUILD PROFILE PROBE OK
```

覆盖：四剖面存在与开关矩阵、`orbital_sim` 无便利项、`limitations≥6`、
`deprecated` 标记与告警、simulator 校验负例（关 traffic/port → error；
配 sandbox_opts → 强制 false + 告警；开 story → 强制关）、未知 boot_mode
回退 prelude、坏配置/缺配置回退 full、场景几何（旧/新）、vm/summary JSON 安全、
`writes` 全 false、同配置 VM 确定性。

### 12.2 四个剖面真实启动 smoke

```powershell
# orbital_sim（真实主场景 main_menu → 自动跳过 → v1_hud）
$env:DSH_BUILD="orbital_sim"; $env:DSH_FLOW_SMOKE="1"
& .\tools\godot\...console.exe --headless --path .\game_v17 --quit-after 5000
# EXIT=0

# full（正式本体序章 + HUD 流程 smoke，直接指定 HUD 场景）
$env:DSH_FLOW_SMOKE="1"
& .\tools\godot\...console.exe --headless --path .\game_v17 res://v1_hud.tscn --quit-after 5000
# EXIT=0

# sandbox（开发测试剖面）
$env:DSH_BUILD="sandbox"; $env:DSH_FLOW_SMOKE="1"
& .\tools\godot\...console.exe --headless --path .\game_v17 --quit-after 5000
# EXIT=0

# combat_sim（旧演示，向后兼容）
$env:DSH_BUILD="combat_sim"; $env:DSH_FLOW_SMOKE="1"
& .\tools\godot\...console.exe --headless --path .\game_v17 --quit-after 5000
# EXIT=0
```

实测关键日志行：

`orbital_sim`（EXIT=0）：

```text
[MAIN MENU] BUILD=orbital_sim → skip to res://v1_hud.tscn
[BUILD PROFILE] id=orbital_sim mode=simulator scene=res://v1_hud.tscn scenario=res://framework/content/scenario_orbital_sim.json save_root=user://saves_sim
[BUILD PROFILE] SYSTEM story=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM prelude=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM triggers=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM sandbox=OFF reason=非测试剖面
[BUILD PROFILE] SYSTEM identification=ON ... combat=ON ... traffic=ON ... port=ON ... ship_catalog=ON ... refit=ON
[BUILD PROFILE][LIMITATION] ...（7 条）
[SHELL BINDER] SANDBOX entities=7 scenario=res://framework/content/scenario_orbital_sim.json
[SHELL BINDER] SYSTEMS physics=true sensors=true track_table=true combat=true ballistics=true damage=true ew=true identification=true traffic=true port=true ship_catalog=true refit=true story=disabled
[V1 HUD] COMBAT source=session sandbox={ "unlimited_ammo": false, "auto_authorize": false }
[V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=7 commands=0
```

无剧情状态证明（本次实测 grep）：orbital_sim 日志中 `story_state` 出现 **0** 次；
`"unlimited_ammo": true` / `"auto_authorize": true` / `sandbox={...true...}` **0** 次；
`SCRIPT ERROR` / 未就绪 warning **0** 条。

`full`（EXIT=0）：

```text
[BUILD PROFILE] id=full mode=prelude scene=res://main_menu.tscn scenario= save_root=user://saves
[BUILD PROFILE] SYSTEM story=ON
[SHELL BINDER] prelude ready=true entities=9 triggers=3 used=true
[SHELL BINDER] SYSTEMS physics=true sensors=true track_table=true combat=false ballistics=true damage=false ew=true identification=true traffic=true port=false ship_catalog=true refit=true story=ready
[V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=9 commands=1
```

> `full` 的 `combat=false / damage=false` 是**诚实结果**：本体序章路径的服务由
> HUD 自建影子组件（`v1_hud._load_data()`），在 `ShellBinder.boot()` 时刻
> session 里确实还没有这两个服务；SYSTEMS 行只认真实对象，不硬编码 true。
> 该行为与改动前一致（未改变 full 路径）。

`sandbox`（EXIT=0）：`[BUILD PROFILE] id=sandbox mode=sandbox ... save_root=user://saves_sandbox`、
`SANDBOX entities=7`、`SYSTEMS ... story=disabled`、
`[V1 HUD] COMBAT source=session sandbox={ "unlimited_ammo": true, "auto_authorize": true }`。

`combat_sim`（EXIT=0，向后兼容）：

```text
[MAIN MENU] BUILD=combat_sim → skip to res://v1_hud.tscn
[BUILD PROFILE] id=combat_sim mode=sandbox scene=res://v1_hud.tscn scenario=res://framework/content/scenario_combat_sandbox.json save_root=user://saves_sim
[BUILD PROFILE] WARN 选中的剖面 'combat_sim' 已弃用（deprecated）：旧作战模拟器演示 profile；新正式模拟器请用 orbital_sim，开发测试请用 sandbox
[SHELL BINDER] SANDBOX entities=7 scenario=res://framework/content/scenario_combat_sandbox.json
[V1 HUD] COMBAT source=session sandbox={ "unlimited_ammo": true, "auto_authorize": true }
[V1 HUD] FLOW SMOKE COMPLETE ... contacts=7
```

### 12.3 自动跳过守卫

```powershell
$env:DSH_BUILD="orbital_sim"; $env:DSH_NO_AUTOSKIP="1"
& .\tools\godot\...console.exe --headless --path .\game_v17 --quit-after 300
# EXIT=0，日志无 [SHELL BINDER] BUILD / [V1 HUD]（停在主菜单，未自动跳过）
```

### 12.4 统一回归矩阵（跨任务，`run_tests.ps1` + `probe_matrix.json`）

本次已用真实命令核对 `probe_matrix.json` 中本任务相关的 boot 用例标记均存在：
`[MAIN MENU] BUILD=orbital_sim|sandbox`、`[SHELL BINDER] BUILD profile=orbital_sim|sandbox|full|combat_sim`、
`[SHELL BINDER] prelude ready=true`、`[V1 HUD] FLOW SMOKE COMPLETE`。
T1 落地后，测试任务（T5）已解除 `e2e.orbital_sim` / `boot.orbital_sim` / `boot.sandbox` 的
`blocked` 标记，并跑通全量矩阵（72 cases：`profile=1`、`content=8`、`unit=37`、
`integration=21`、`e2e=1`、`boot=4`；实测 64 PASS / 8 pre-existing FAIL / 0 TIMEOUT /
0 NOT RUN，矩阵 exit 1 由既有内容漂移失败造成）。本任务相关的 4 个 boot smoke 与 e2e
用例全部 PASS；独立验证（task-4）在干净 worktree 复跑结果一致。

### 12.5 端到端探针现状（跨任务，非本任务交付）

T3 的真实入口 e2e 探针（`tests/e2e_orbital_sim_probe.gd`）现为 **GREEN**
（由 task-3 运行/维护）：

```powershell
& .\tools\godot\...console.exe --headless --path .\game_v17 --script res://tests/e2e_orbital_sim_probe.gd
# E2E ORBITAL SIM PROBE RESULT: PASS=153 FAIL=0 · target=orbital_sim · EXIT=0
```

覆盖：真实入口 main_menu→v1_hud、剖面契约、12 个系统真实 ready 对象 +
`binder.systems_vm()` 一致性、`story_state==null`、limitations=7、无便利项、
quick_restart 被拒、弹药 120→119（真实扣减）、真实弹道 impact+damage、交通/港口实时查询。
T1 收尾时本任务曾运行到 `PASS=114 FAIL=1`（唯一失败项为「从真实航迹选中可交战目标」，
属 T3 战斗身份闭环域）；该失败已由 task-3 以真实证据路径修复/闭环。
**不在 profile seed 里伪造 threat**（违反审计 §3.3「信息状态不互相替代 / UI 不得
重做识别结果」）。

### 12.6 已知集成缺口（NOT FIXED · 不在 Phase 0 修复，转 Phase A）

以下为 e2e 探针中以 `[E2E] INFO` 形式如实输出、**本轮明确不修**的预置接线问题
（Phase 0 范围只做 profile/启动基线；修复分别由 Phase A #4 / #2 负责）：

1. **轨道融合距离 ≠ 物理真值（Phase A #4 传感器/识别权威收敛）**：
   `orbital_sim`/`sandbox` 仍复用旧 `_sensor_config()` 的演示装订几何，e2e 实测
   `apsis→harmattan 融合距离 20.0 km vs 物理真值 420.0 km`。火控门禁用
   `track.range_km`，弹道/物理用真值，二者暂不一致。修复方向：Phase A #4 统一
   传感器目标 schema 后从场景真值装订；**本任务未改**。
2. **接触列表丢失真实 side/identity 元数据（Phase A #2 权威世界实体状态）**：
   `WorldState._normalize_entity()` 只保留
   id/kind/name/pos_km/vel_kmps/flags/alive/version，丢掉 side/identity/batch 等，
   `_build_contacts()` 只能回退 side="friend"。e2e 实测 `CONTACT SIDE MISMATCH n=5`：
   harmattan(truth=hostile→contact=unknown)、ferry(neutral→friend)、
   raider_2(hostile→friend)、skiff(hostile→friend)、watchtower(neutral→friend)。
   修复方向：Phase A #2 让 WorldState 规范化保留实体元数据并补 probe；
   **本任务未改**（binder 侧补丁会造成第二展示事实源，违反审计 §3.3，故不做）。

以上两项不影响 T1 交付门槛：e2e 断言未放宽，均以 `[E2E] INFO` 记录在案。

### 12.7 本次 NOT RUN

- `run_tests.ps1` 全量矩阵（T5 任务）：未由本任务运行；本任务只逐项验证相关用例。
- `DSH_SHOT` 截图模式、窗口化渲染路径：未运行（任务为 headless profile/boot 验证）。
- `orbital_sim` 存档写入/读回 round-trip：未运行（存档 schema 未改，SaveService 单测另属任务）。
- 性能/帧率：未测量（本任务不涉及渲染与逐帧性能）。

## 13　边界

- 不做多套可执行文件/资源分包（Godot 侧仍是单工程）；版本差异是**运行时开关**，
  后续要真打包再用 export preset + feature tag 落地；
- 不做「模拟器专属 UI 皮肤」——四剖面共用同一套 HUD；
- 便利项只覆盖「演示连续性」（弹药/授权/重开），**不做无敌、不做跳过门禁**；
- 便利项不改变存档 schema，也不写进 save 的 seed（重开/读档后按当前剖面重新判定）；
- `build_profile` 不写 world/TrackTable/UI，不持有时序状态；
- 校验只 warning/error，**不会自动开启被关掉的核心系统**来让冒烟测试变绿。
