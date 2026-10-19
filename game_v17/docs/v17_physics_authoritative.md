# R6-AUTH-1 · authoritative 物理适配层说明（V17）

> 任务 R6-AUTH-1（task-76）。工程 `game_v17`。
> 物理核心：`framework/sim/cislunar_physics.gd`（R6-PHYS-1）。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读）。
> 本文件说明三模式、相对板坐标、V15 对比（switch 阈值）、导航 provider、回退与边界。

## 1　定位

- 在 **不破坏 V15/HUD** 的前提下建立 **authoritative 位置适配层**：物理状态可作为下一步
  位置源，但本任务**仍不写 V15 `state.tracks`/plot/HUD**，显示层未切换（`display_switched=false`）。
- 三种模式（`V17_PHYSICS`）：
  - `shadow`（默认）：只读影子，行为同 R6-SHADOW-1；
  - `authoritative`：额外提供 `physics_authoritative_view()`（own/flagship/targets 的 ECI +
    相对本舰 board_r/board_v、range/bearing/elevation、age、warnings）与
    `physics_adapter_compare()`（物理相对状态 vs V15 board 差异）；
  - `off`：不创建物理，导航回退 abstract 坐标。
- `authoritative` 必须有 `ready`/来源/坐标系/误差/warnings 明示；初始化失败自动回落
  `shadow`（`fallback_reason` 记录），不崩溃。
- 导航仍使用内容中的**抽象转移成本**；authoritative 只让导航节点位置来自真实物理/地月模型。

## 2　模式解析与回退

```
V17_PHYSICS=off            → requested=off,      mode=off
V17_PHYSICS=authoritative  → requested=auth,     mode=auth（成功） / mode=shadow + fallback_reason（失败）
其他/未设置                 → requested=shadow,  mode=shadow
```

失败回落条件：物理实例无法创建、L1 平衡点不可用、实体集合为空、物理模型 errors 非空。
调试钩子 `V17_PHYSICS_FORCE_FAIL=1` 可模拟 authoritative 初始化失败（probe 用，正常流程不受影响）。

## 3　authoritative 视图（`physics_authoritative_view()`）

```
{
  "schema":"v17_physics_authoritative.v1",
  "requested_mode":"authoritative","mode":"authoritative",
  "authoritative":true,"ready":true,"display_switched":false,
  "display_note":"显示层尚未切换：V15 tracks/HUD/plot 仍用 V15 数据；本视图只读。",
  "fallback_reason":"",
  "source":"cr3bp_rk4_circular · 实体初始 V2 L1 局部近似/固定占位（非 JPL 星历）",
  "frame":{"inertial":"earth_eci","rotating":"earth_rot",
           "board":"earth_rot 相对本舰（+x/+y 面内、+z 法向；bearing=atan2(x,y)、elevation=atan2(z,horiz)，与 V15 _derive 同式）"},
  "t":<shadow/authoritative 秒>,
  "own":{ entity_id,role,state_earth_eci,state_earth_rot,board_r:[0,0,0],board_v:[0,0,0],
          range_km:0,bearing_deg:0,elevation_deg:0,age_s,source,finite,... },
  "flagship":{同上（相对 own，旗舰=apsis）},
  "targets":[ {entity_id,role,side,name,source,age_s,state_earth_eci,state_earth_rot,
               board_r,board_v,range_km,bearing_deg,elevation_deg,
               range_rate_kmps,closing_kmps,finite,earth_distance_km,moon_distance_km} ],
  "flags":{"authoritative_ready":true,"display_switched":false,"own_id","flagship_id",
           "target_ids":[...],"fallback_reason":""},
  "warnings":[...],
  "error":""
}
```

- 相对板坐标：`board_r = state_earth_rot(target).r − state_earth_rot(own).r`；
  `board_v` 同理；`range=|board_r|`；`bearing=atan2(x,y)`、`elevation=atan2(z,horiz)`
  （与 V15 `_derive` 同式，便于对比）。
- `age_s`：物理当前步采样（与同步时间一致，0）；`source` 明示 L1 局部近似/固定占位/默认。
- shadow 模式下该视图 `ready=false` 且 `error` 说明“未启用”；off 同理；不崩溃。

## 4　V15 对比（`physics_adapter_compare(v15_own, v15_tracks)`）

- 入参：
  - `v15_own`：`state.own_at(tau())` → `{r:Vector3, v:Vector3}`（只读）；
  - `v15_tracks`：`[{track_id, entity_id?, board_r:[x,y,z], board_v:[x,y,z]}]`；
    state 自动生成（`board_pos/board_vel`），也可由调用方提供。
- 输出（只读；不写 V15）：
  - `own`：physics earth_rot 位置 vs V15 own；
  - `tracks`：每行 `{track_id, entity_id, role, physics{range/bearing/elevation/board_r},
    v15{range/bearing/elevation/board_r/board_v}, errors{range_km,bearing_deg,position_km}}`；
  - `summary`：`tracks_input/compared/skipped/max_range_err_km/max_bearing_err_deg/
    max_position_err_km/within_threshold`；
  - `thresholds`：`{range_km:5, bearing_deg:5, position_km:50}`（bridge 常量，切阈值评估用）；
  - `frame_mismatch_note`：V15 board=L1 局部差，physics board=地心旋转差（未切换），range 直接
    可比，bearing/位置误差含坐标系旋转差异，仅作阈值参考。
- state 在 `fw_sync()` 中自动以当前 V15 `own_at/board_pos/board_vel` 调 compare：
  `state.fw_physics_adapter` 每帧更新（只读）。

## 5　state / bridge 字段

| 位置 | 字段 | 说明 |
| --- | --- | --- |
| bridge | `physics_requested_mode` / `physics_mode` / `physics_fallback_reason` | 请求/有效/回落原因 |
| bridge | `physics_authoritative_view()` | 只读 authoritative 视图 |
| bridge | `physics_adapter_compare(v15_own, v15_tracks)` | 只读对比（返回结果并缓存 `physics_adapter_last`） |
| bridge | `physics_summary()` | 增 `requested_mode/authoritative/fallback_reason/display_switched/compare_thresholds` |
| bridge | `bridge_state()` | 增 `physics_requested_mode/physics_fallback_reason/physics_authoritative/physics_adapter` |
| state | `fw_physics_authoritative` | bridge authoritative 视图深拷贝 |
| state | `fw_physics_adapter` | 最近一次 V15 对比（`fw_sync` 更新） |
| state | 方法 | `fw_physics_authoritative_view()` / `fw_physics_adapter_view()` |
| state | `fw_bridge_state()` | 增上述两个字段 |

旧字段（`fw_physics/fw_physics_ready/fw_physics_summary/fw_physics_mode/fw_nav/fw_damage/...`）
不变。

## 6　导航 provider

- shadow/authoritative 且物理 ready 时：`bind_position_provider` 用物理/地月模型位置
  （地心旋转系 km）；off/失败回退 abstract。
- authoritative 下导航节点位置与物理一致（L1≈326,381、GEO=42,164、L4/L5=384,400、
  moon_port 到月≈1,737.4、lunar_leo≈1,837.4）；**成本仍抽象**、不自动执行机动。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_physics_authoritative_probe.gd
# V17 PHYSICS AUTH PROBE RESULT: PASS=154 FAIL=0（exit 0）
```

覆盖（10 节）：shadow/authoritative/off 三模式；authoritative 视图（own/flagship/targets、
ECI + earth_rot + board_r/board_v、range/bearing/elevation/age/source/warnings）；board 与
physics earth_rot 差值一致；compare 结构/阈值/误差/坐标系未切换说明；state
`fw_physics_authoritative`/`fw_physics_adapter` 与旧字段；authoritative 导航 provider（l1=326,381）
且成本抽象/不自动执行；**V15 tracks/等级/身份/clock 不变**；authoritative 初始化失败回落 shadow
（fallback_reason、不崩溃）；off 降级；JSON 回读；restart 复位（t=0/ready/provider 重绑）。

回归（同任务）：`v17_physics_shadow_probe` 277/0、`v17_bridge_probe` 138/0、
`v17_nav_integration_probe` 182/0、`v17_core3_probe` 171/0、boot/main headless exit 0。

## 8　边界 / 未完成

- **显示层未切换**：不写 V15 `state.tracks`/HUD/plot；V15 位置源仍是权威。
- 物理非 JPL 星历：圆轨道 + CR3BP；实体初始状态为 V2 L1 局部近似/固定占位（source 标注）；
  Godot Vector3 float32（~0.03 km@38 万 km）。
- 对比的 bearing/位置误差包含坐标系差异，不能直接当“物理误差”；切换前需统一坐标/门限。
- 导航仍用抽象成本；未接姿态/推力/质量/传感器几何；不生成武器/伤害；不自动执行。
- `V17_PHYSICS_FORCE_FAIL=1` 仅调试回落用；正常流程无影响。
- 未 commit。
