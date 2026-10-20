# R5-INFO-BRIDGE-1 · 信息作战 shadow 接入 V17 bridge/state

> 任务 R5-INFO-BRIDGE-1（task-85）。工程 `game_v17`。
> 模型：`framework/sim/information_warfare.gd`（`V2InformationWarfare`，R5-INFO-1）。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读）。
> **shadow advisory only：不写 TrackTable/V15；不接 HUD/plot；authoritative 不实现。**
> 按任务要求只做最小 probe（PASS=116/0），未跑全量回归；未 commit。

## 1　定位与不变量

- bridge 启动创建 `V2InformationWarfare`（shadow），每帧用 **V2 world/entity 输入**
  （observer / targets 的 emitters / comms / contacts / advisory）驱动 `step(dt)`；
  只读输出 IFF/ELINT/COMINT/EW effects/events/alerts。
- `V17_INFO_WARFARE=shadow|off`（默认 shadow）：
  - `off`：不创建模型，view/summary/recent 为空；
  - 传入 `authoritative`/`auth`/`v2`：**不实现 authoritative**，仍只 shadow，并在
    `info_warfare_fallback_reason` 明示“authoritative 未实现：保持 shadow advisory”，不伪称。
- 初始化失败不阻塞 bridge（world/nav/physics/sensor 等照常），置 `info_warfare_ready=false` + warning。
- 模型不写轨道/不自动判敌（`never_auto_hostile=true`、`hostile_auto_determination=false`）；
  **不接 HUD/plot**；不改变 V15 现有权威。

## 2　输入（bridge 构造；只读）

| 输入 | 来源 |
| --- | --- |
| observer | `default_observer(world.own_id)`（harmattan，L1 板原点 `[0,0,0]`）；`damage.sensors/comms` = `world.vm_damage_full().effects.*.mult`；`emcon=false` |
| targets | `world.vm_contacts()` 中 `bearing_only=false、range>0、entity_id 非空/非本舰` 的行：`make_target(track_id, range_km, bearing_deg, {entity_id,batch,name, transponder:"ok"(友)/"off", registered(友), iff_codes(友，默认库), emissions[雷达], comms[radio 一条]})` |
| stations | 两个 ELINT 站：`<own>-ELINT-A`（原点）、`<own>-ELINT-B`（5000 km 基线）用于交叉定位（fix_candidates） |
| advisory_contacts | 若 sensor shadow 就绪，透传其 `advisory_contacts`（track_id/batch 关联；只读） |
| 帧 | L1 局部板；不做 ECI/姿态/跨帧转换 |

## 3　推进

- `bridge.sync(dt)`：`dt>0` 时 `info_warfare.step(dt)`；`dt=0` 不推进。
- setup 内 ELINT/COMINT 首次扫描已发生（ELINT signals/事件随 boot 可读）；
  IFF 由调用方显式 `interrogate_iff` 触发，EW 由调用方显式注入（见 §5 probe 用法）。
- 每帧 `refresh()` 更新 view/summary + 最近事件/告警缓存。

## 4　bridge API（只读）

| API / 字段 | 说明 |
| --- | --- |
| `info_warfare` | V2InformationWarfare 实例（off/失败 null；probe/未来 adapter 可直接调用显式 IFF/EW 接口） |
| `info_warfare_mode` / `info_warfare_requested_mode` / `info_warfare_ready` / `info_warfare_fallback_reason` | shadow|off 有效/请求/就绪/回落说明 |
| `info_warfare_view()` | `vm_information_warfare()`：`schema=information_warfare.v1`、mode=shadow、authoritative=false、ready、t、observer、mounts、iff{available,results,by_target,summary,hostile_allowed:false}、elint{state,signals,misses,fix_candidates,summary,single_station_contact:false,elint_level_cap}、comint{events,summary,produces_contact:false,auto_decode:false}、ew{effects,active_count,radar,comms,optical,emcon,phantom,suspicious_commands,summary}、effects、events、alerts、advisory_contacts、summary、writes{track_table:false,v15:false}、shadow{never_auto_hostile:true,...} |
| `info_warfare_summary()` | 顶层 summary：`iff/iff_identity_friend/unknown/hostile=0/signals/fix_candidates/comint/effects/events/alerts/phantom_active/suspicious_commands/hostile_auto_determination=false` |
| `info_warfare_events()` / `info_warfare_alerts()` | 最近 ≤8 条事件/告警（完整列表见 view.events/alerts） |
| `bridge_state()` | 增 `info_warfare/info_warfare_summary/info_warfare_ready/info_warfare_mode/info_warfare_requested_mode/info_warfare_fallback_reason/info_warfare_recent_events/info_warfare_recent_alerts` |
| `info_warfare_warnings`（view.warnings） | 模型 warnings（shadow/attitude/identity/EMCON 等标注） |

事件类型：`emitter.signal`（ELINT）、`iff.reply`/`exposure.fix`（IFF）、`comms.link`（COMINT）、
`ew.effect`（EW）；全部走同一事件总线（shadow authority，只读）。

## 5　state API（不接 HUD）

| 字段 / 方法 | 说明 |
| --- | --- |
| `fw_info_warfare` | bridge view 深拷贝；`fw_sync` 每帧刷新 |
| `fw_info_warfare_ready` | bool |
| `fw_info_warfare_summary` | 顶层 summary 深拷贝 |
| `fw_info_warfare_view()` 等 | 直接读字段；`fw_bridge_state()` 增上述字段 |
| 旧字段 | `fw_sensor_shadow/fw_physics*/fw_nav*/fw_damage*` 等全部不变 |

off/未就绪时三个字段为空/false；`fw_sync`/restart 后自动刷新；不写 state.tracks。

## 6　最小验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_info_warfare_probe.gd
# V17 INFO WARFARE PROBE RESULT: PASS=116 FAIL=0（exit 0，只跑一次）
```

覆盖：
1. boot：mode=shadow/ready/schema/authoritative=false/writes=false/summary 键/最近缓存；
2. 事件：ELINT `emitter.signal`、IFF `iff.reply`（interrogate_iff 友军）、EW `ew.effect`
   （inject_noise_jamming）+ exposure.fix/alerts；COMINT summary 可读；
3. state：`fw_info_warfare/ready/summary`、旧 sensor 字段不变、V15 tracks/等级/身份/clock 不变、
   V2 vm_tracks 可读、recent events/alerts 缓存；
4. authoritative 请求 → 仍 shadow + fallback_reason（不伪称）；
5. off 降级：view/summary/recent 空、state 空、不崩溃、sensor shadow 不受影响；
6. JSON：view/state summary/bridge_state 可回读。

## 7　边界 / 未完成

- **shadow advisory only**：不写 TrackTable/V15、不改显示层；不自动融合/不自动判敌/不自动裁决。
- **authoritative 不实现**：环境请求也只 shadow，`authoritative=false`，reason 明示。
- 不接 HUD/plot（后续任务）；IFF/EW 当前需显式调用（bridge 不自动询问/注入；后续 adapter 接决策流）。
- 模型输入为 L1 局部板近似：transponder/iff_codes/emissions/comms 由 bridge 按 V2 contacts 合成
  （友军 transponder=ok + 默认代码库；其余 off；雷达/通信发射为占位），非真实电子战环境。
- EMCON/姿态/真实 IFF 加密纪元/LPI 等未接；ELINT/COMINT 仅 shadow 证据，不产生接触（模型保证）。
- 未跑全量回归；未 commit。
