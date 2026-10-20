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
