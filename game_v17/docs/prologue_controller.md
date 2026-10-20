# 完整游戏-阶段3C · PrologueController 序章流程控制器

> 任务 完整游戏-阶段3C（task-135）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/物理；未 commit）：
> - `scripts/core/prologue_controller.gd`
> - `tests/prologue_probe.gd`（`PASS=272 FAIL=0`）
> - 本文件
> 只控制序章流程与数据，不渲染 UI、不写 world/V15。

## 1　状态机（手动，不自动）

```
NAME_INPUT → BRIEFING → HANDOVER → NAVIGATION → DEPARTURE_REQUEST
           → BURN_WINDOW → CRUISE → ARRIVAL → COMPLETE
```

| 状态 | 进入方式 / API | 关键约束 |
| --- | --- | --- |
| NAME_INPUT | 初始 | 只接受合法玩家名 |
| BRIEFING | `submit_name(name)` | 名字非空/≤24/无控制字符 |
| HANDOVER | `confirm_briefing()` | 只能在 BRIEFING |
| NAVIGATION | `accept_handover()` | — |
| DEPARTURE_REQUEST | `request_departure()` | 需先 `set_destination()`（合法目的地在 scenario target_cluster） |
| BURN_WINDOW | `authorize_burn()` | 记录点火窗口（T+18h..T+24h） |
| CRUISE | `ignite()` | 需授权且 `t_s` 在窗口内；`arrival_t = ignition_t + TOF` |
| ARRIVAL | `arrive()` | 需 `t_s >= arrival_t`；使用 fleet cache arrival gate |
| COMPLETE | `complete()` | 只能在 ARRIVAL；**不自动完成** |

- 全部由显式 API 推进；`advance_time(dt)` 只推进仿真时间，**不自动改变状态**（跨过窗口/抵达时间后仍需手动）。
- 失败 reason：`not_ready/wrong_state/empty_name/invalid_chars/name_too_long/invalid_destination/
  no_destination/not_authorized/window_not_open/window_closed/too_early/invalid_dt/...`；
  失败不改状态、不改 StoryState。

## 2　内容 / 舰队数据

读取（只读）：

- `framework/content/scenario_transit_l4_l1.json`（`scenario.v2`）：`transfer.source_port/target_port/
  target_cluster/arrival_gate/tof_days_candidates`；ports。
- `framework/content/transfer_l4_l1_fleet_cached.json`（`v17_fleet_transfer_cache.v1`）：
  `source_port/target_port/tof_s/tof_days/dv/ships[5]/samples[11]/arrival/deterministic`。

运行时提供：

| 数据 | 说明 |
| --- | --- |
| `source_id` / `target_id` | scenario id（`l4_02_hammer` / `l1_meridian_05`） |
| `source_display` / `target_display` | fleet cache display（`L4-02 Hammer` / `L1-Meridian-05`） |
| `tof_s` / `tof_days` | 518400 s（6 天） |
| `dv()` | `{rows,sum/avg/max departure/arrival/total}`（avg_total≈1822.44 m/s） |
| `fleet()` | 5 舰独立传播行（apsis 旗舰 + harmattan/ferry/watchtower/deepwell） |
| `timeline()` | 11 采样摘要（t/progress/flagship pos/distance）+ 4 里程碑（窗口开/关/点火/抵达） |
| `allowed_destinations` | scenario target_port + target_cluster（L1 港/锚地/干船坞） |
| `window()` | `{open_t:64800, close_t:86400, authorized, is_open, t_s}` |
| `milestones()` / `time_to_window_s()` / `time_to_arrival_s()` | 时间轴查询 |

- 到达校验使用 fleet cache `arrival.all_within_gate` 的 gate 半径/速度（3000 km / 3 km/s）；
  probe 断言 `arrival_error_km <= gate`。

## 3　玩家名

- `submit_name(name, opts={})` 接收 ImeInput 提交（`opts.ime` 仅记录，不做输入法逻辑）。
- 规则：`strip_edges()` 非空；长度 1..24；首尾不能有空白；不允许控制字符（code<32/127）；
  合法 CJK/ASCII/下划线等；成功后进入 BRIEFING 并保存 `player_name`。
- 失败：`empty_name`（空/全空白）、`invalid_chars`（首尾空白/控制字符）、`name_too_long`；
  非 NAME_INPUT 状态 → `wrong_state`。

## 4　API

| API | 说明 |
| --- | --- |
| `PrologueController.new(opts)` / `setup(opts)` | opts：scenario_path/fleet_path/story_state/event_bus |
| `load_content(scenario_path, fleet_path)` / `validate_content(sc, fl)` | 加载/校验内容 |
| `submit_name(name, opts)` | 玩家名 → BRIEFING |
| `confirm_briefing()` / `accept_handover()` | 手动推进 |
| `set_destination(dest_id)` | 合法目的地在 target_cluster；非法 `invalid_destination` |
| `request_departure()` | 需已设目的地；生成 `REQ-xxxxxx` request_id |
| `authorize_burn()` | 授权点火 → BURN_WINDOW |
| `ignite()` | 窗口内点火 → CRUISE，记录 ignition_t/arrival_t |
| `advance_time(dt)` | 手动推进时间（不自动状态）；非法 dt 拒绝 |
| `arrive()` / `complete()` | 抵达/显式完成 |
| `window()` / `milestones()` / `time_to_*` | 时间轴查询 |
| `fleet()` / `timeline()` / `dv()` / `source_*/target_*/tof_*` | 只读舰队/轨道数据 |
| `events` / `events_since(seq)` / `take_events()` | `prologue.*` 事件 |
| `apply_effects(effects)` / `bind_story_state(ss)` / `bind_event_bus(bus)` | flag/evidence/trust 效果与可选集成 |
| `snapshot()/vm()/to_dict()/to_json()` | 只读快照 |
| `save_state()` / `load_state(json)` | 内存 JSON（含绑定 StoryState 快照） |
| `reset()` / `check_contracts()` | 复位/不变量检查 |

## 5　事件 / 效果

- 每个成功转换追加 `prologue_event.v1` 事件：`prologue.name_submitted/briefing_confirmed/
  handover_accepted/destination_set/departure_requested/burn_authorized/burn_ignited/arrived/completed`；
  `seq/t/state/detail/writes_v15:false`。
- 绑定 EventBus 时同名事件发布到 bus（`type=prologue.*`，`source="prologue"`）。
- 绑定 StoryState（可选）时通过 `set_flag/add_evidence/adjust_*` 应用效果：
  `prologue_name_set`、`briefing_confirmed`、`handover_done`、`destination_set`、
  `departure_requested`、`burn_authorized`（trust+2）、`burn_ignited`（trust+3）、
  `arrived_l1` + `ev_arrival_l1`（trust+5）、`prologue_complete`。
- 失败路径不发布成功事件、不改 StoryState；无 StoryState 时使用内部镜像。

## 6　存档（内存 JSON）

```text
{
  schema:"v17.prologue_save.v1", version:"1.0.0",
  scenario_path, fleet_path,
  state, player_name, destination, request_id, burn_authorized,
  t_s, ignition_t, arrival_t,
  history[], events[], event_seq, flags{}, evidence[],
  trust, morality, reputation, threat,
  story_save: <StoryState.save_state()> | ""
}
```

- `load_state(json)`：校验 schema/version/state/name/destination/StoryState 快照 → 应用并重建 timeline；
  非法 JSON/schema/state/name/destination 拒绝，失败不改当前核心状态。
- 可在任意阶段中断保存/加载（NAVIGATION/BURN_WINDOW/CRUISE/ARRIVAL），load 后可继续手动推进；
  未绑定 StoryState 时忽略 story_save，仍恢复 controller 状态。
- 不写磁盘；外层可交给 SaveService/GameSession 存档。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/prologue_probe.gd
# V17 PROLOGUE PROBE RESULT: PASS=272 FAIL=0（exit 0，只跑一次）
```

覆盖（8 节）：内容/舰队（scenario/fleet cache/source/target/TOF/Δv/fleet/timeline/arrival gate）；
setup/玩家名（空/空白/超长/控制字符/首尾空白拒绝，CJK/ASCII/IME/24 字符通过，重复提交拒绝）；
乱序/wrong_state（各状态非法操作拒绝）；全流程 9 状态（窗口前/抵达前失败、手动时间、ARRIVAL 不自动
完成、COMPLETE 后拒绝）；点火窗口失败（未开/已关/负 dt/NaN/边界 open-close/未授权）；
存档/中断（各阶段 snapshot+StoryState 一致、中途继续、非法存档拒绝不改状态）；事件/效果
（9 个 prologue.*、EventBus、StoryState flags/evidence/trust、直接 apply_effects）；
JSON/确定性（9 状态、snapshot/save/timeline 同操作一致）。

## 8　边界 / 未完成

- 只做流程/数据/状态机：**不做 UI/文本渲染/物理**；不写 world/V15。
- 点火窗口固定 T+18h..T+24h（常量）；示例舰队/轨道来自既有 cache；不重新规划轨道。
- 事件只输出数据；EventBus/StoryState 为可选绑定；不自动完成、不按时间自动推进。
- 玩家名只做基础校验（不做敏感词/账号唯一性/输入法组合态）。
- 到达判定依赖 fleet cache 的 arrival gate；不重新传播物理。
- 存档仅内存 JSON；无文件槽位；未跑全量回归；未 commit。
