# 阶段3D · 导航/离港页（nav_page.tscn）

> 任务 task-137。新增：
> `game_v17/nav_page.tscn`、`scripts/ui/navigation_page.gd`、`scripts/ui/flight_map.gd`、本文件。
> 不改其他场景/project；未 commit；不接物理/剧情分支/存档。

## 1 入口 / boot

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
& $godot --path "D:\GHOST TRACK_APSIS\game_v17" res://nav_page.tscn
```

- `PrologueController.new({})` 读取 `scenario_transit_l4_l1.json` + `transfer_l4_l1_fleet_cached.json`。
- 玩家名：`DSH_PLAYER_NAME` → root meta `player_name` → 默认 `沧澜`。
- 为到达导航页，页面 boot 按前置顺序调用 `submit_name → confirm_briefing → accept_handover`（前置脚手架，不是玩法自动推进）；之后 state=`NAVIGATION`，所有操作需手动按钮。
- 真实数据：`tof_s=518400`（6 天）、fleet=5、timeline=15 点、target=`l1_meridian_05`（L1 Meridian-05）。

## 2 主图 / 时间轴

- `flight_map.gd`：
  - 真实 timeline `flagship_pos_km`（15 点）绘制折线；L4-02 / L1 Meridian 标签；
  - 5 舰从 `fleet_cache.samples` 按当前 t_s 插值真实 `pos_rot_km` 绘制，批号/舰名标签分离；
  - 底部时间轴：T+ / TOF、WINDOW OPEN 18:00:00 与 CLOSE 24:00:00 标记、当前时间线；
  - 明确 `REAL FLEET CACHE SAMPLE · SCHEMATIC FRAME`；无假地图。
- 顶部显示 `T+ / TOF / WINDOW / PAUSED`；`advance_time` 只在 state ∈ {NAVIGATION, DEPARTURE_REQUEST, BURN_WINDOW, CRUISE} 时允许。

## 3 操作按钮（真实 PrologueController API）

| 按钮 | 调用 | 实测（DSH_NAV_TEST=1） |
| --- | --- | --- |
| SET DEST L1 | `set_destination(target_id)` | OK（l1_meridian_05） |
| REQUEST DEPARTURE | `request_departure()` | OK |
| AUTHORIZE BURN | `authorize_burn()` | OK |
| IGNITE | `ignite()` | 首次 t=0 → FAILED `window_not_open`；推进到 18h 窗口后 OK |
| ARRIVE | `arrive()` | OK（推进到 arrival_t） |
| COMPLETE | `complete()` | OK → state=COMPLETE |

- 每次结果写入右栏/底部日志；失败显示 `reason`；点击不自动推进下一步。
- 时间控制：PLAY/PAUSE、×1/×60/×3600；播放只调 `advance_time`，不会自动点按钮/推进状态。

## 4 教学提示

- 从 `framework/content/teaching_l4_l1.json` 读取步骤文本，按 state 映射：
  - NAVIGATION → T07-G1-S2（设定目的地）
  - DEPARTURE_REQUEST / BURN_WINDOW → T07-G1-S4（确认到达/授权）
  - CRUISE / ARRIVAL / COMPLETE → T07-G1-S5（抵达）
- 只显示 title/player_action，手动完成；不自动推进/勾选。

## 5 截图 / 验证

- `mockups/nav-page-1920.png`（1920×1080）：真实轨迹、5 舰、时间轴/窗口、教学、操作按钮。
- `NAV PAGE SHOT err=0`；headless boot `name=沧澜 state=NAVIGATION t=0 tof=518400 fleet=5 timeline=15`；
  `navigation_page.gd/flight_map.gd --check-only` 通过。

## 6 边界 / 未完成

1. 页面 boot 自动完成 name→briefing→handover 仅为到达导航页的前置；未接剧情分支/序章 UI 状态保存。
2. 轨迹/舰队来自 `transfer_l4_l1_fleet_cached.json` 的 timeline/samples；非实时物理积分；不自动推进、不写 world/V15。
3. IGNITE 必须满足窗口（T+18h–24h）；未实现真实推力/燃料/姿态。
4. ARRIVE/COMPLETE 可手动推进；不接剧情后果/存档。
5. 星图/时间轴为示意 frame，不是导航权威图；未跑全量 regression。


---

## 方案B-15：离港通信（task-171）

- 导航页加载 `StoryTextLibrary`；真实 controller 操作成功后追加通信：
  - `REQUEST DEPARTURE` 成功 → `comms.hammer`，格式 `[Hammer Port Control 至 APSIS]-[RDO]-[原文]`；
  - `AUTHORIZE BURN` / `IGNITE` 成功 → `comms.formation`，格式 `[APSIS 至 ALL]-[LD]-[原文]`；
  - 失败不追加，不复用旧文本；不伪造额外台词。
- 右侧新增 `通信 / COMMS` 区显示通信原文；日志同步记录 `COMMS comms.hammer/formation`。
- 本次截图样例：`DSH_NAV_COMMS_TEST=1` 真实执行 SET DEST/REQUEST DEPARTURE/AUTHORIZE BURN/advance window/IGNITE，显示 Hammer 与 formation 两条；`IGNITE · OK`。
- 截图 `mockups/nav-comms-1920.png`。
- 边界：不实现完整教学高亮/剧情分支；通信为文本展示，不写剧情/物理。
