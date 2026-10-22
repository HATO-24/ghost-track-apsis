# 版本划分 · 正式本体 / 作战模拟器 DEMO

> 工程 `game_v17`。配置：`framework/content/build_profiles.json`；
> 加载器：`scripts/core/build_profile.gd`；场景：`framework/content/scenario_combat_sandbox.json`。
> 两版本**共用同一套系统代码与存档 schema**，只在「开机时装什么」上分叉。

## 1　为什么要分

一个交付物要同时满足两件事：

1. **正式本体**：剧情 + 事件状态机，玩家从主菜单进序章，逐步推进；
2. **作战模拟器 DEMO**：不演剧情，开机即战术台，用来展示"真实地月系轨道作战"这个概念。

硬塞进一个入口会让两边都别扭：本体要序章/触发器/报告，模拟器要的是"立刻能打、
可以反复重开验证机制"。所以拆成**两个版本剖面（build profile）**，
而不是两份代码。

## 2　两个剖面

| | `full`（正式本体） | `combat_sim`（作战模拟器） |
| --- | --- | --- |
| label | GHOST TRACK // APSIS | GHOST TRACK // ORBITAL COMBAT SIM |
| 入口 | `res://main_menu.tscn` | `res://v1_hud.tscn`（主菜单自动跳过） |
| boot_mode | `prelude` | `sandbox` |
| 实体来源 | `PreludeScenario`（序章内容） | `scenario_combat_sandbox.json` |
| 存档根 | `user://saves` | `user://saves_sim` |
| story / prelude / triggers | ✅ | ❌ |
| identification / signal | ✅ | ✅ |
| traffic / port | ✅ | ❌ |
| combat / ballistics / damage / physics_world | ✅ | ✅ |

> 存档根分开是**故意的**：两版本各玩各的，不会互相覆盖。schema 完全一致，
> 所以存档本身是互通的（想搬过去直接复制文件即可）。

## 3　选择方式

优先级从高到低：

1. `BuildProfile.new({"id": "combat_sim"})` —— 代码显式指定（测试用）
2. 环境变量 `DSH_BUILD=combat_sim`
3. 配置里的 `"default"`（当前 `full`）

```powershell
# 本体
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17

# 作战模拟器（跳过主菜单直接进战术台）
$env:DSH_BUILD="combat_sim"
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path .\game_v17
```

主菜单里 `DSH_SHOT`（截图模式）或 `DSH_NO_AUTOSKIP=1` 会阻止自动跳过，
方便给模拟器版本截主菜单图。

## 4　sandbox 场景（真实地月系几何）

`scenario_combat_sandbox.json`，坐标系 **CR3BP 旋转系 bary_rot**，单位 km / km/s：

- 地球在 x ≈ −4671 km，月球在 x ≈ 379 729 km；
- 演练位置在 **EML1**（x ≈ 321 719 km）附近；
- 交战尺度刻意覆盖三档：

| 实体 | 距本舰 | 演示什么 |
| --- | --- | --- |
| `skiff`（CUTLASS） | ~117 km | 落在 PD 180 km 射程内 → 点防拦截 |
| `harmattan`（HAMATTAN） | ~420 km | 实弹（1200 km）与导弹（6000 km）都能打 → 对比两种弹道 |
| `raider_2`（SABRE） | ~2500 km | 只有导弹够得着 → 巡航剖面/引导头开机时序 |

其它：`l1_station`（友方空间站，带 PD）、`watchtower`（中立哨舰）、
`ferry`（民用渡船）。

**注意**：旋转系里"速度为 0"等于随系共转，不是惯性系静止。所以静止实体的
`vel_kmps` 写 0 是合理的，但它们在物理世界里的轨迹仍然是曲线。

**帧转换**：sandbox seed 显式带 `seed_frame: "bary_rot"` / `frame_origin: "bary_rot"`，
禁止再套用序章的「L1 相对帧」偏移——否则整张图会被平移 32 万公里。

## 5　加载器 API

```gdscript
const BuildProfile := preload("res://scripts/core/build_profile.gd")
var bp = BuildProfile.new()                 # 按 env → default 选
var bp2 = BuildProfile.new({"id": "combat_sim"})
var bp3 = BuildProfile.new({"content": {...}})   # 内联配置（测试用）

bp.ready                    # 读不到也 true —— 回退 full
bp.id / bp.label / bp.subtitle
bp.boot_mode                # "prelude" | "sandbox"
bp.entry_scene / bp.scenario / bp.save_root
bp.enabled("story")         # 功能开关
bp.sandbox_opt("unlimited_ammo")   # 沙盒便利项（非 sandbox 剖面恒 false）
bp.is_sandbox() / bp.is_combat_sim()
bp.select("full")           # 运行时切换（只换开关，不重建服务）
bp.vm() / bp.summary()
```

**回退原则**：配置缺失、schema 不符、profiles 为空、default 指向不存在的剖面、
环境变量写错——**全部回退 `full` 并留告警**，绝不因为版本配置把游戏打死。

## 6　接入点

| 位置 | 行为 |
| --- | --- |
| `shell_binder.boot()` | 先加载剖面；`sandbox` 时走 `_sandbox_seed()`，否则走序章 |
| `shell_binder.save_root` | 由剖面决定，`SaveService` 用它 |
| `main_menu._ready()` | 剖面是 sandbox 且非截图模式 → `change_scene_to_file(entry_scene)` |

`sandbox` seed 里装的东西：`entities/nodes/links`（来自场景）、`own_entity`、
`track_table`、`sensor_service`、`physics_world`、`combat_service`、
`combat_ballistics`（`pd_platform_id` 来自场景 `combat`）、`damage_service`、
`ew_service`、`identification_service`、`signal_service`（观测者=本舰）、
`traffic_control`（按开关）、`seed_frame`。
**不装** `story_state`（模拟器没有剧情状态机）。

## 7　沙盒便利项（sandbox_opts）

模拟器要能"连续演示"，本体不能有这些口子。所以便利项**单独一组开关**，
且**只在 `boot_mode == "sandbox"` 时生效**——配置里就算给 `full` 写了 `true`，
`build_profile.sandbox_opt()` 也一律返回 `false`（`build_profile_probe` 有专门断言）。

| 便利项 | 效果 | 落点 |
| --- | --- | --- |
| `unlimited_ammo` | 弹药不扣减（railgun/missile/pd/decoy/jammer 全部），也不因弹药耗尽把 ROE 降级 | `combat_service.unlimited_ammo` |
| `auto_authorize` | FIRE 免授权（`confirmed` 仍必须），演示时可自由选目标 | `combat_service.auto_authorize` |
| `quick_restart` | HUD `F5` 一键按原场景重开（走 `shell_binder.quick_restart()` → 完整 `boot()`） | `v1_hud._sandbox_restart_enabled()` |

**刻意不做的**：`unlimited_ammo` 只放宽弹药，**不绕过**冷却、射程、ROE 降级之外的
任何门禁——`unknown_track`/`out_of_range`/`cooldown`/`no_ready_solution` 照旧拒绝，
这样模拟器演示的仍是真实交战流程，而不是"无敌模式"。

`auto_authorize` 通过时 `_action_allowed()` 返回 `reason = "sandbox_auto_authorize"`
且 `sandbox = true`，事件流里能明确区分"真授权"和"沙盒放行"。

**为什么 `quick_restart` 走完整 `boot()` 而不是 `session.reset()`**：
`reset()` 只重建 session 内部服务，`shell_binder` 缓存的 `traffic_service`/
`track_vm`/`contacts` 等仍指向旧对象，HUD 会读到陈旧数据。完整 `boot()` 会连缓存
一起重建；HUD 不缓存 `session`（一律经 `binder.session` 取），所以换掉 session 对象是安全的。
重开前会清掉 `DSH_LOAD_SLOT` 与 root meta `load_slot`，避免"重开"变成"把刚才的存档读回来"。

## 8　开发互通

- 服务层、内容格式、存档 schema、UI 组件全部共用；
- 新增机制只要在 `build_profiles.json` 里给它一个开关，两个版本都能用；
- 沙盒便利项走独立的 `sandbox_opts` 组，**不混进 `features`**——`features` 是
  "装不装这个系统"，`sandbox_opts` 是"演示时放不放宽"，两者语义不同，
  混在一起会让本体也有机会读到放宽项；
- 今后开发重心放在 `combat_sim`：机制完整度 → 系统间不冲突 → UI 适配；
  本体只需要保证"开关关掉的东西不会拖累模拟器"。

## 9　验证

```powershell
# 剖面加载/开关/回退/场景几何
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/build_profile_probe.gd
# BUILD PROFILE PROBE RESULT: PASS=191 FAIL=0

# 两版本各自的实机自测
$env:DSH_V1_TEST="1";                        ... res://v1_hud.tscn   # full
$env:DSH_BUILD="combat_sim"; $env:DSH_V1_TEST="1"; ... res://v1_hud.tscn
```

`combat_sim` 自测实测：`BUILD profile=combat_sim mode=sandbox`、
`SANDBOX entities=7`、`COMBAT source=session sandbox={ "unlimited_ammo": true, "auto_authorize": true }`、
`COMBAT FIRE ... launched=1`、`COMBAT BALLISTICS active=0 impacts=1`。
`full` 自测实测：`BUILD profile=full mode=prelude`，且**没有** `COMBAT source=session`
（序章仍走影子组件），`COMBAT FIRE ... launched=1`、`INTERACTION TEST` 全 OK。

已知差异（都是 sandbox 的合理结果，不是 bug）：
- `command=NO COMMAND SELECTED`：模拟器没有预置命令；
- `optical=LIGHT ... out_of_range`：420 km 超出灯语可视距离。

## 10　边界

- 不做多套可执行文件/资源分包（Godot 侧仍是单工程）；版本差异是**运行时开关**，
  后续要真打包再用 export preset + feature tag 落地；
- 不做"模拟器专属 UI 皮肤"——目前两版本共用同一套 HUD；
- 便利项只覆盖"演示连续性"（弹药/授权/重开），**不做无敌、不做跳过门禁**：
  冷却、射程、解算、目标存在性全部照旧，模拟器演示的是真实交战流程；
- 便利项不改变存档 schema，也不写进 save 的 seed（重开/读档后按当前剖面重新判定）；
- `build_profile` 不写 world/TrackTable/UI，不持有时序状态。
