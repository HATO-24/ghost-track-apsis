# 阶段1F · 正式 Game Shell（game_shell.tscn）

> 任务 task-132。新增：
> `game_v17/game_shell.tscn`、`scripts/ui/game_shell.gd`、`scripts/ui/shell_binder.gd`、本文件。
> 不改旧场景/project；未切换 main_scene；不实现剧情/物理。

## 1 入口

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
& $godot --path "D:\GHOST TRACK_APSIS\game_v17" res://game_shell.tscn
```

- `project.godot` 的 main_scene 仍是 transit；本场景独立加载。
- 截图：
  - `DSH_SHOT=.../mockups/game-shell-1920.png`、`DSH_SHELL_SIZE=1920x1080`
  - `DSH_SHOT=.../mockups/game-shell-1600.png`、`DSH_SHELL_SIZE=1600x900`
  - `DSH_SHELL_SAVE_TEST=1` 时启动后执行一次真实 SaveService save + load metadata（默认不写）。

## 2 数据流

```
game_shell.gd
  ├─ ShellBinder.boot()
  │   ├─ GameSession.boot({track_table:true, story_state:true, orders:[HOLD...]})
  │   ├─ SaveService.setup("user://saves")
  │   ├─ _seed_tracks(): session entities → session.handle_observation(radar L2)
  │   ├─ _load_delta_v(): transfer_l4_l1_cached.json budget.total_dv_mps
  │   └─ refresh(): session.snapshot / track_vm / story_vm / orders / bus.events
  ├─ ProdTop: session now_s / time.scale / paused；binder.timers()（session.bus tactical.timer）；
  │           Δv（transfer cache）；ROE（story_state phase）；三色点 SaveService
  ├─ ContactList: binder.contacts ← track_vm.tracks + session entities（无硬编码）
  ├─ ProdRight: binder.ship_fields(selected, ship|target) ← entity/track 真实字段
  ├─ CommandLog: binder.commands ← snapshot.components.orders.orders；
  │              binder.events ← session.bus.recent(8)
  └─ CustomCursor: hover point / 按住 drag / set_disabled
```

## 3 布局 / 坐标

- Control + Theme + 9-slice；窗口自适应 1920/1600。
- 顶栏 H72（指挥官/任务 T+/L1 港内/×scale RUNNING/3 条 EventBus 计时器/LINK/Δv/ROE/三色点）。
- 左接触 W320min、中图 expanding、右栏 W344min、底日志 H132；右栏 tab SHIP/TARGET，按钮槽 `NAV / DAMAGE / OPTICAL / INFO OPS`。
- 底部：命令队列（id/state/issuer→targets/action/mode/delay）与事件日志（t/type/text），来源 `GAME SESSION · ORDERS` / `SESSION BUS`。
- 无 `DEMO` 标记；无数据时明确 `NOT READY` / `NO COMMAND DATA` / `NO EVENT DATA`。

## 4 真实数据（本次）

- entities：`apsis` 1000 FLAGSHIP、`harmattan` 1001、`l1_station` 3100。
- tracks：T0001 (apsis L2)、T0002 (harmattan L2)，sources radar；由 session entities 观测生成。
- orders：`O-000001` HOLD，`apsis → harmattan`，QUEUED，LD，1.0s。
- events：`order.issued`、`order.delayed`、`tactical.timer`。
- Δv：transfer cache `1822.6 m/s`；ROE：`WEAPONS HOLD / 仅自衛 · phase prelude`。
- 三色点：SaveService `user://saves/save.json`；测试结果 `SAVED save · 12941B · bc28b053`，metadata=true；黄/红返回 should_show_menu/should_exit，不真正切菜单/退出。

## 5 截图 / 验证

| 文件 | 分辨率 |
| --- | --- |
| `mockups/game-shell-1920.png` | 1920×1080，含 SAVED save |
| `mockups/game-shell-1600.png` | 1600×900 |

- 均 `GAME SHELL SHOT err=0`；headless 启动一次 boot=true contacts=3 orders=1；`shell_binder.gd/game_shell.gd --check-only` 通过。

## 6 未完成 / 限制

1. 正式壳 boot track_table/story_state；SensorService 未 boot（session 无 sensor 组件），右栏传感器摘要来自 track sources，非实时传感器。
2. 剧情只读 story_vm/phase；未实现剧情推进/物理。
3. commands 仅 session demo seed 的 1 条 HOLD；未接完整关卡订单/命令操作。
4. 三色点已实际写 user://saves；黄/红只返回菜单/退出意图，不切 UI/退出。
5. 页面按钮只发信号/log，未接玩法。
6. 未跑全量 regression；未修改 project main_scene。
