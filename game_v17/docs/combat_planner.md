# 完整游戏-阶段4H · 交战规划辅助

> 工程 `game_v17`。核心文件：`scripts/core/combat_planner.gd`、
> `tests/combat_planner_probe.gd`、本文件。
> 只做算术与校验：不改弹道状态、不写 world/TrackTable/UI。

## 1　定位

玩家在发射前需要回答两个问题：**"这么打飞得过去吗？"** 和 **"要花多少 Δv？"**

`V2CombatPlanner` 把"我想怎么打"翻译成弹道服务能吃的巡航剖面（Δv 时序点），
并提前给出 Δv 预算/可行性。真实可行性仍由 `CombatBallistics.launch()` 兜底
（`insufficient_dv`）——规划器只是让玩家在**按下去之前**就知道。

```
intent（玩家意图）
   │
   ▼
V2CombatPlanner.plan()  ── 调 ball.predict() 取 range/TOF/Δv 预算
   │
   ├─ profile{waypoints[], terminal_acquire_km, seeker_off_until_km}
   ├─ dv_planned_kmps / dv_budget_kmps / feasible
   └─ notes[]（人话解释）
   │
   ▼
to_launch_opts() → {profile} 或 {profiles}
   │
   ▼
CombatBallistics.launch(..., opts)  → 真实弹丸
```

## 2　四种意图

| intent | 语义 | 剖面 | 战术价值 |
| --- | --- | --- | --- |
| `direct` | 直射 | 无航路点 | 最快到达，弹道可预测 |
| `silent` | 静默接近 | `seeker_off_until_km > 0` | 末段才开引导头，降低被 ESM/点防提前发现 |
| `offset` | 侧向迂回 | 起手一次横向 Δv，半程反向消掉 | 横偏后回正，避开对方点防主轴 |
| `multi_axis` | 多轴同时到达 | 同 `offset`，但横偏轴按 `bearing_deg` 旋转 | 齐射时压缩点防通道，效率最高 |

- `silent` 的静默距离默认 `min(600, max(20, range × 0.5))`，可用 `opts.silent_km` 覆盖；
- `offset` 的横偏默认 `min(200, max(20, range × 0.08))`，可用 `opts.offset_km` 覆盖；
- `multi_axis` 在 `plan_salvo` 里按 `360°/n × i` 均分方位角。

**为什么 `offset` 是两个脉冲**：起手给一个横向速度，滑行 `t_half` 后横偏约
`dv × t_half`；此时再给等值反向脉冲把横向速度消掉，弹道回到目标连线方向——
形成"侧向进场"。净横偏不改变到达时间（脉冲等值反向，纵向分量不变）。

## 3　API

```gdscript
const Planner := preload("res://scripts/core/combat_planner.gd")
var p = Planner.new()

p.plan(ball, shooter_state, target_state, weapon_id, intent, opts)
  -> {ok, schema:"combat_plan.v1", intent, weapon_id,
      range_km, time_of_flight_s, aim_km,
      profile{waypoints[], terminal_acquire_km, seeker_off_until_km},
      waypoints[], dv_planned_kmps, dv_budget_kmps,
      feasible, seeker{}, notes[]}

p.plan_salvo(ball, shooter_state, target_state, weapon_id, n, intent, opts)
  -> {ok, schema:"combat_plan_set.v1", intent, count,
      plans[], max_dv_planned_kmps, feasible}

p.to_launch_opts(plan_or_set) -> {"profile": {...}} | {"profiles": [...], "intent": ...}
p.estimate_dv(waypoints) -> float
p.summary() -> {schema:"combat_planner.v1", intents[], defaults, writes{...}}
```

失败 reason：`no_ballistics / unknown_intent / predict_failed / no_geometry /
partial_plan_failed`。

`opts`：`silent_km`、`offset_km`、`bearing_deg`、`terminal_acquire_km`。

## 4　接入点

- **UI**：战斗终端 `PLAN <INTENT>` 按钮循环四种意图；读数显示
  `Δv planned / budget`、`feasible`、`TOF`；
- **发射**：`GameSession.request_fire(..., {"intent": "silent"})` 会现场规划并
  把 profile 塞进 `launch_opts`；也可直接传 `{"plan": <plan_dict>}` 复用手动预演结果；
- **齐射**：`plan_salvo` 产出逐发剖面，`to_launch_opts` 转成 `profiles` 数组，
  弹道服务按 `salvo_index` 取用。

## 5　边界

- 不写 world/TrackTable/UI；不持有状态（每次 `plan()` 无副作用）；
- 不判命中、不算拦截概率——那是弹道服务的事；
- `feasible=false` 只是**提示**，发射仍会被弹道服务以 `insufficient_dv` 拒绝，
  两者口径一致（同一 `dv_budget = max_accel × fuel_s`）；
- 不实现：多弹协同时间对齐（只按方位均分）、地形/遮挡规避、
  对方点防射界的主动规避（`offset` 只是几何横偏，不感知对方 PD 参数）。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/combat_planner_probe.gd
# COMBAT PLANNER PROBE RESULT: PASS=94 FAIL=0
```

覆盖：意图集合/未知意图拒绝、四种意图的剖面形状、等值反向脉冲、
Δv 记账与预算、不可行标记、齐射逐发方位均分、`to_launch_opts` 与
`launch()` 的 profile/profiles 覆盖打通（四发都带两段航路点且方向不同）、
确定性与 JSON 安全。
