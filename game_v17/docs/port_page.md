# 阶段3H · 港口/入港页（port_page.tscn）

> 任务 task-141。新增：
> `game_v17/port_page.tscn`、`scripts/ui/port_page.gd`、本文件。
> 改 `scripts/ui/navigation_page.gd`（COMPLETE → port_page）；不改核心/project/其他；未 commit。

## 1 流程

```
prologue → briefing → nav_page
nav_page COMPLETE（手动） → port_page.tscn
port_page DEPART（需先 UNDOCK；status=DEPARTED） → game_shell.tscn
```

- 玩家名：`DSH_PLAYER_NAME` / root meta `player_name` / fallback「沧澜」；port DEPART 时写回 env/meta 再切 Shell。
- port_page 独立入口：`& $godot --path game_v17 res://port_page.tscn`；`DSH_PLAYER_NAME` 可覆盖。
- `request/refuel/...` 全部手动；失败显示 reason；不自动许可/对接/服务。

## 2 PortService 配置 / 真实资源

`port_page.gd::_config()` 显式配置（shadow PortService，不写 V15/world）：

| 港 | berth | drydock | tug | fuel avail/cap |
| --- | --- | --- | --- | --- |
| L1 Meridian (`l1_meridian_05`) | B1,B2,B3 | 2 | TUG1 | 1900/2400 t |
| Chronos 站 | CH-1 | 1 | CH-TUG | 420/600 t |
| Greenwich 船坞 | G-1,G-2 | 2 | G-TUG | 700/900 t |
| Sextant 泊位 | S-1 | 0 | S-TUG | 260/300 t |

- 总资源：7 berth / 5 drydock / 4 tug / fuel 3280/4200 t（boot 日志实测）。
- 请求窗：L1 Meridian `W1 0..1,000,000s`，`require_permit=true`，corridor C1；页面显示 OPEN/CLOSED。
- **3 号罐泄漏 / 救援目标**为明确 `EXAMPLE` 配置标签（TANK 3 LEAK / 12 CREW），不伪造剧情事实/伤亡/裁决。

## 3 操作（真实 PortService API）

| 按钮 | API |
| --- | --- |
| REQUEST DOCK | `request("dock", apsis, l1_meridian_05,{priority:2,clearance})` + `permit(request_id)` |
| APPROACH | `approach(request_id)` |
| DOCK | `dock(request_id)` |
| REFUEL | `refuel(request_id,100.0)` |
| REPAIR | `repair(request_id)` |
| FINISH SERVICE | `finish_service(request_id)`（REFUEL/REPAIR 后回 DOCKED） |
| UNDOCK | `undock(request_id)` |
| DEPART | 检查 status=DEPARTED 后写名字并切 `game_shell.tscn` |

- 实测（`DSH_PORT_TEST=1`）：request/permit → approach → dock → refuel → finish → repair → finish → undock，最终 `state=DEPARTED`；失败均显示 reason。
- 无请求/无泊位/窗口关闭等错误由 PortService 返回，不伪造成功。

## 4 截图 / 验证

- `mockups/port-page-1920.png`（1920×1080）：港口列表资源、EXAMPLE 3 号罐/救援、窗口/请求、入港操作。
- `PORT PAGE SHOT err=0`；headless boot `ports=4 resources berths 7/7 drydock 5/5 tug 4/4 fuel 3280/4200`；`port_page.gd --check-only` 通过。

## 5 边界 / 未完成

1. PortService 端口配置为页面示例（Chronos/Greenwich/Sextant + L1 Meridian）；不是完整关卡港口经营/动态交通。
2. 3 号罐泄漏/救援目标只是 EXAMPLE 标签，不接剧情/伤亡/裁决。
3. 操作只调 shadow PortService；不写 world/V15、不实现物理/拖船真实运动。
4. DEPART 前必须 UNDOCK 到 DEPARTED；错误会显示 reason。
5. 未跑全量 regression；未改 project main_scene。
