# V17 数据桥字段 / 接口（HUD / plot 对接）

> V17-CORE-1（task-54）。工程 `game_v17` = V15 视觉（HUD/plot 原有）+ `framework/` 的 V2 core/sim
> 数据后端。本文件列出 HUD/plot 需要读取的字段与可调用方法；**视觉层不要反向改 core**。
> 相关文件：`scripts/framework_bridge.gd`（V17Bridge）、`scripts/state.gd`（WarState 的 fw_* 字段）、
> `scripts/main.gd`（每帧 `state.fw_sync(delta)`）、`tests/v17_bridge_probe.gd`。

## 0　启动 / 每帧

```gdscript
# main._ready()
framework = FrameworkBridge.new()
framework.boot()                # 装载 framework/content/scenario_l1_v2.json + world + mission
state.framework = framework
state.fw_sync(0.0)              # 首帧快照

# main._process(delta)
state.refresh(state.clock)      # V15 原流程（不改）
state.fw_sync(delta)            # V2 数据桥：暂停/冻结/截图时内部 dt=0
```

- boot 时默认 **跳过 V2 PRELUDE**（V15 自己拥有 PRELUDE 覆盖层），避免“执行前冻结”双门控；
  需要 V2 prelude 时设 `DSH_V2_PRELUDE=1`。
- 启动打印：`V17 FRAMEWORK ok=... summary={...}` 与 `V17 BRIDGE ready=... contacts=10 ...`。

## 1　state 上的只读字段（HUD/plot 直接读）

| 字段 | 类型 | 来源 / 说明 |
| --- | --- | --- |
| `state.fw_ready` | bool | bridge 是否就绪（未就绪时 HUD 应隐藏新块，不占位） |
| `state.fw_tutorial` | Dictionary | `world.vm_tutorial()`：`enabled/ready/title/hint/done_text/required_actions/min_required/completed[{id,label,at}]/missing[]/progress{done,need}/decision_pending/actions[{id,label,done,at,available,reason}]` |
| `state.fw_flow` | Dictionary | `world.vm_flow()`：`prelude/decision/report/end/mission/tutorial/exec_window_s/exec_left/exec_pct/reputation{ocu,meridian,ueg_doves,outer,reclaimers}/reputation_settled/damage/replay/flags` |
| `state.fw_damage` | Dictionary | `world.vm_damage()`：`entity_id/entity_name/sections[{id,label,state,severity,severity_pct,repair_eta_s,repair_remaining_s,progress,can_repair}]/queue/summary{total,damaged,degraded,repairing,repaired,needs_attention}/repair_rate_s` |
| `state.fw_replay` | Dictionary | `world.vm_replay()`：`recording/playing/paused/index/total/interval_s/t/current{帧}/frames[{index,t,phase,kind,decision_made,ended}]/pinned/frame_t`。**语义**：`t` = 录制时钟（世界时间），不是当前帧时间；当前帧时间看 `frames[index].t` 或 `current.t` / `frame_t`。`index` 是回放查看头；调用 `fw_replay_seek(t)` 或 `fw_replay_seek_index(i)` 后 `pinned=true`，录制继续追加帧不会移动查看头；`fw_replay_stop()` 解除固定。 |
| `state.fw_contacts` | Array | 10 条归一接触（V2 `vm_contacts()`；V15 `tracks` 仍独立保留） |
| `state.fw_actions` | Array | 当前选中目标的可用动作（`available/reason/reason_code`，含 actor_id/actor_name） |
| `state.fw_actions_target` | String | 上面 action 列表对应批号 |
| `state.fw_decision_reason` | String | V15 决策被教学门控阻塞的原因（"" = 未阻塞）；HUD 决策入口置灰时显示 |
| `state.fw_decision_deferred` | bool | 决策已到点但被门控挂起 |
| `state.fw_sync_count` | int | 同步次数（HUD 判定数据新鲜度用） |
| `state.fw_t` | float | V2 世界时间（秒） |
| `state.fw_last_action` | Dictionary | 最近一次 `fw_perform_action` 的返回（供 HUD 提示/日志） |
| `state.framework` | V17Bridge | 直接读 `framework.tutorial/damage/replay` 等快照或 `framework.world`（只读） |

补充字段（`state.fw_flow` 内）：`decision{open, prompt, options[{kind,label,hint,enabled,reason}], evidence_count, can_expose, decision, reply, consequence}`、
`report{available, submitted, ending_kind, audit_flag, report}`、`end{ok, ending_kind, report, reputation, reputation_settled, ...}`。

## 2　state 上的封装方法（HUD 只调这些写 V2）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `state.fw_sync(dt)` | void | 每帧同步；暂停/冻结/截图时内部 dt=0 |
| `state.fw_perform_action(action_id, target_id="")` | Dictionary | 调 V2 `world.perform_action`；`target_id` 空则用当前选中批号；返回 `{ok,action,level,level_name,identity,actor_id,actor_name,reason,reason_code,detail,tutorial,...}`；成功会记录教学门控进度 |
| `state.fw_start_repair(section_id)` | Dictionary | 启动 V2 损管维修（`{ok,reason,section}`） |
| `state.fw_apply_damage(id, severity, label="")` | Dictionary | 剧情/调试施加损伤 |
| `state.fw_open_decision()` / `state.fw_choose_ending(kind)` / `state.fw_submit_report(truth)` | Dictionary | V2 流程封装（V15 原 decision 流程保留，两者 best-effort 镜像） |
| `state.fw_evidence_start(id)` | Dictionary | V2 取证任务 |
| `state.fw_actions_for(track_id)` | Array | 指定目标的 V2 动作可用性 |
| `state.fw_replay_start/pause/stop/seek(t)/seek_index(i)/frame()` | Dictionary | 只读回放；`seek` 不推进世界；seek 后固定查看头（录制追加帧不移动播放头）；`frame()` 返回当前/固定帧 |
| `state.fw_restart()` | void | 重置 V2 世界（V15 `restart_demo()` 内部已调用） |
| `state.fw_tutorial_ready()` / `state.fw_tutorial_allows()` / `state.fw_decision_gate_reason()` | bool/String | 教学门控查询 |
| `state.fw_bridge_state()` | Dictionary | 一帧总览（见上表字段） |
| `state._fw_pull()` | void | 手动把 bridge 快照拉进 state.fw_*（HUD 内部已用，一般不要直接调） |

## 3　V15 决策门控（教学）

- V15 `_update_phase_gate` 在决策到点时调 `_open_decision()`；`_open_decision` 先检查
  `state.fw_tutorial_allows()`。未满足时：
  - 不打开决策、不自动完成识别；`state.fw_decision_deferred=true`，
  - `state.fw_decision_reason="教学门控：识别不足（x/2）— …"`，HUD 在决策入口置灰显示；
  - 玩家通过 `state.fw_perform_action(...)`（HUD 目标动作）完成关键识别后，
    `fw_sync`/`fw_perform_action` 会自动打开挂起的 V15 决策（`decision_open=true`）。
- 自动放行（不阻塞旧演示/截图）：
  - `DSH_SKIP_TUTORIAL=1`（V2 端门控禁用，`fw_tutorial.enabled=false`）；
  - `DSH_SIM` / `DSH_SHOT` 设置时（演示/截图）；
  - `state.capture=true`（截图冻结）。
- 放行后 V15 `choose_ending / authorize_fire / submit_report` 会 best-effort 镜像到 V2
  （`fw_flow` 的 decision/report/reputation 随之更新；V2 端拒绝不影响 V15 流程）。

## 4　HUD 现读字段（task-56 已接线，供核对）

- 教学：`state.fw_tutorial`（`actions/completed/progress/ready/enabled`）、`state.fw_decision_reason`；
- 损管：`state.fw_damage`（`sections/queue/summary`）、`state.fw_start_repair(id)`；
- 回放：`state.fw_replay`（`frames/playing/paused/index/total/t`）、
  `state.fw_replay_start/pause/seek(t)`；
- 兜底：`state.framework`（bridge 的 `tutorial/damage/replay` 快照、`world`）。

## 5　plot 可读字段（task-55 参考）

- 接触/站体：`state.fw_contacts` 行含 `track_id/entity_id/batch/level/identity/kind/display_kind/
  icon/size_km/fixed/entity_tags/orbit_source/range_km/bearing_deg/stale`；
  `fixed=true`（站体 0100 / 储罐 0101）不应画推进/预测，只画固定标记。
- 动作/目标：`state.fw_actions_for(track_id)`、`state.fw_actions`（右键菜单灰显原因）。
- 时间/阶段：`state.fw_flow`（phase、exec_left、decision/report/end）。
- 雷达/TWS 球体仍由 V15 state racks/sensor + `scripts/tws_bridge.gd`（V17-SENSOR）负责；
  bridge 不改 V15 tracks，plot 不需要直接读 `framework.world`。

## 6　测试

```powershell
# 启动（intro 场景，默认 headless 只打印 AUDIO）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --quit

# 主场景 8 帧（跳过 intro）：打印 V17 FRAMEWORK / V17 BRIDGE
$env:DSH_SKIP_INTRO='1'
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --quit-after 8

# 桥接 probe（全绿：PASS=131 FAIL=0；DSH_SKIP_TUTORIAL=1 时 PASS=107）
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path .\game_v17 --script res://tests/v17_bridge_probe.gd
```

覆盖：boot / 10 接触（含站体储罐 fixed）/ tutorial 字段与门控 / `fw_perform_action` 跨 2 动作后
ready / flow（exec_window 360、decision/report/end、五方声望）/ damage（3 项维修）/ replay（帧增长、
seek/pause/stop、只读）/ state.fw_* 归一字段 / V15 决策挂起→自动打开 / HOLD+TRUTH 镜像到 V2。

## 7　已知边界

- V2 flow 的 decision 计时（timeline T+75 / exec 360s）与 V15 的 `decision_t` 各自独立；
  HUD 覆盖层以 V15 `state.decision_open` 为准，`fw_flow` 仅作数据展示（镜像是 best-effort）。
- bridge 只读 `framework/*`；sim/tactical_snapshot、plot/TWS 由 V17-SENSOR 维护，core 不反向依赖。
- 回放为数据帧接口；HUD 回放期间应暂停仿真（`state.paused`/`sim_frozen` 或 UI 自行冻结）。
- 未 commit；与 V17 其他任务（hud/plot）按字段契约协作。
