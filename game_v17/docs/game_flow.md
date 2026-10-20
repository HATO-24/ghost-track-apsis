# 完整游戏流程：序章 → 导航 → Shell

> 任务 task-139。改动：
> `scripts/ui/prologue_flow.gd`（briefing → nav_page）、`scripts/ui/navigation_page.gd`（COMPLETE → game_shell + 名字写回）、`scripts/ui/game_shell.gd`（读取玩家名）、`project.godot`（仅 main_scene）、本文件、`mockups/`。
> 未改核心/transit；未 commit；不实现物理/剧情分支。

## 1 主流程

```
project.godot main_scene = res://prologue.tscn

prologue.tscn
  name（ImeInput/候选）→ briefing（DRAFT）
    CONTINUE / SKIP ──→ nav_page.tscn        （不自动跳过）
nav_page.tscn
  SET DEST L1 → REQUEST DEPARTURE → AUTHORIZE BURN → IGNITE
  → ARRIVE → COMPLETE（手动）
    COMPLETE ──→ game_shell.tscn              （手动，不自动）
game_shell.tscn
  读取 DSH_PLAYER_NAME / root meta player_name
  顶栏显示真实玩家名；无名字 fallback「沧澜」
```

- 玩家名写入：root meta `player_name` + OS env `DSH_PLAYER_NAME`。
- `PrologueFlow` 提交名字后进入 briefing；briefing 的 CONTINUE/SKIP 都进入 `nav_page.tscn`；不自动跳过。
- `nav_page` 的 COMPLETE 按钮成功（state=COMPLETE）后写名字并 `change_scene_to_file("res://game_shell.tscn")`；其余状态下按钮失败只显示 reason。
- `game_shell` 重新读 env/meta；`ShellBinder.commander` 用于顶栏显示。
- `transit.tscn` 保留为旧技术验证场景，非主场景。手动打开：
  ```powershell
  & $godot --path "D:\GHOST TRACK_APSIS\game_v17" res://transit.tscn
  ```

## 2 入口 / 回退

- 正常启动：`& $godot --path game_v17`（主场景 prologue）。
- 直接看导航页：`& $godot --path game_v17 res://nav_page.tscn`（可带 `DSH_PLAYER_NAME`）。
- 直接看 Shell：`& $godot --path game_v17 res://game_shell.tscn`，`DSH_PLAYER_NAME=沧澜`。
- 旧 transit 技术验证：`res://transit.tscn`，不影响主流程。

## 3 截图

| 文件 | 说明 |
| --- | --- |
| `mockups/prologue-flow-briefing.png` | 序章简报（DRAFT + CONTINUE/SKIP） |
| `mockups/nav-page-flow.png` | 导航/离港页（真实 timeline/fleet/timeline 窗口 + 操作按钮） |
| `mockups/game-shell-flow.png` | Shell；顶栏 `指挥官 · 沧澜`（从 env/meta 传入） |

- 均 1920×1080；`PROLOGUE SHOT` / `NAV PAGE SHOT` / `GAME SHELL SHOT err=0`；headless 主场景加载一次。

## 4 未完成 / 边界

1. 序章简报 CONTINUE/SKIP 都直接切 nav_page，没有过场/异步加载。
2. 导航页 COMPLETE 后才切 Shell；当前 nav 前置 name/briefing/handover 仍为脚手架（不继承序章真实 controller 状态，页面自行 boot）。
3. 名字传递只靠 env/root meta；无存档持久化；刷新/重启后需重新输入。
4. game_shell 的顶栏玩家名已接；Shell 内其他模块仍用固定指挥官/默认身份。
5. 不实现物理/剧情分支/存档；`transit.tscn` 仅技术验证；未跑全量 regression。


---

## 5　阶段3H：港口/入港接入（task-141）

- 导航页 `COMPLETE`（手动）→ `res://port_page.tscn`（此前直接 game_shell）。
- `port_page` 使用真实 `PortService` 配置：
  - `l1_meridian_05`（L1 Meridian）+ `chronos` / `greenwich` / `sextant`；
  - berth/drydock/tug/fuel/window/require_permit/corridor 来自页面配置（shadow service）。
- 操作全部手动：REQUEST DOCK（request+permit）、APPROACH、DOCK、REFUEL、REPAIR、FINISH SERVICE、UNDOCK、DEPART；失败显示 reason。
- `DEPART` 仅在 `UNDOCK` 且 request status=`DEPARTED` 时把名字写回 env/meta 并切 `game_shell.tscn`。
- 3 号罐泄漏/救援目标以 `EXAMPLE` 标签显示，不伪造剧情事实。
- 截图：`mockups/port-page-1920.png`。


---

## 6　阶段3J：流程状态连续性（task-143）

### 6.1 流程状态容器（root meta）

键：`Root.get_meta("flow_state")` → Dictionary：

```json
{
  "player_name": "沧澜",
  "controller_save": "<PrologueController.save_state() JSON>",
  "phase": "briefing|navigation|port|shell",
  "updated_utc": "YYYY-MM-DDTHH:MM:SS"
}
```

- 另保留 `Root.get_meta("player_name")` 与 OS env `DSH_PLAYER_NAME` 便于兼容旧页面。
- 切场景前写入；写入失败/状态非法不切：
  - prologue：name 提交后写 `briefing`（controller 状态 BRIEFING）；CONTINUE/SKIP 执行 controller `confirm_briefing/accept_handover` 到 NAVIGATION，写 `navigation` 后切 nav。
  - nav：优先从 `flow_state.controller_save` `load_state`；只有缺失/加载失败才明确 fallback 自行 boot。COMPLETE 成功后写 `port`（controller 状态 COMPLETE）再切 port。
  - port：读取 `flow_state`（name/phase/controller_save），不重新 boot controller；DEPART（需 status=DEPARTED）写 `shell` 后切 game_shell。
  - shell：读取 `flow_state.player_name`/phase；顶栏显示真实名字。

### 6.2 Headless 主流程 smoke

```powershell
$env:DSH_FLOW_SMOKE="1"
& $godot --headless --path game_v17
```

本次实测日志：

```
[PROLOGUE] FLOW write phase=briefing saved_bytes=725
[PROLOGUE] FLOW write phase=navigation saved_bytes=1162
[NAV PAGE] FLOW restore ok=true state=NAVIGATION name=沧澜
[NAV PAGE] ... SET DEST/REQUEST/AUTHORIZE/IGNITE/ARRIVE/COMPLETE OK
[NAV PAGE] FLOW write phase=port state=COMPLETE bytes=3082
[PORT PAGE] FLOW phase=port saved_bytes=3082 name=沧澜
[PORT PAGE] FLOW write phase=shell name=沧澜
[GAME SHELL] FLOW phase=shell name=沧澜 saved_bytes=3082
[GAME SHELL] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 phase=shell
```

- 正常启动不自动跳过；smoke 仅 env 显式触发。
- 正常截图仍可用 `prologue-flow-briefing.png` / `nav-page-flow.png` / `port-page-1920.png` / `game-shell-flow.png`。

### 6.3 边界 / 未完成

1. 流程状态只存在 root meta（进程内）；不写盘/不跨重启。
2. nav/port/shell 各自仍有自身业务 boot（GameSession/PortService）；本任务只保证 PrologueController 状态与名字连续，不是全组件持久化。
3. 缺失 flow_state 时 fallback 到页面自 boot；日志明确 `FLOW fallback`。
4. smoke 使用显式 UI API 链，不代表手动点击事件测试；正常按钮仍手动。
5. 不实现物理/剧情分支；未跑全量 regression。
