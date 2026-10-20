# 阶段1A · Control + Theme + 9-Slice UI 壳原型

> 任务 task-116。新文件：
> `game_v17/ui_proto.tscn`、`scripts/ui/{ui_proto,ui_theme,top_bar,contact_list,custom_cursor}.gd`、本文件。
> 不改旧场景/transit/project；不 commit；只做壳与视觉，不实现玩法/物理。

## 1 入口

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
$env:DSH_SHOT="D:\GHOST TRACK_APSIS\mockups\ui-proto-1920.png"
$env:DSH_PROTO_SIZE="1920x1080"
& $godot --path "D:\GHOST TRACK_APSIS\game_v17" res://ui_proto.tscn
```

- 独立场景，不运行旧 HUD/plot/transit；截图脚本 36 帧后保存并退出。
- 1600 用 `DSH_PROTO_SIZE=1600x900`，输出 `ui-proto-1600.png`。

## 2 Control / Theme / 9-Slice

- `ui_theme.gd`：程序化 24×24 边框纹理 → `StyleBoxTexture`（8px texture margin）作为 `Panel/PanelContainer` 9-slice；按钮同纹理色调 hot/normal；默认字体 `fonts.gd` CJK/mono，色板 `pal.gd`。
- `ui_proto.gd` 用 `MarginContainer → VBoxContainer → HBoxContainer` + `PanelContainer` 布局；不沿用旧 HUD 的绝对像素坐标；窗口缩放时容器自动重排（1920/1600 均实测）。
- 四区：顶栏 72、左侧接触 320min、中图 expanding、右侧任务 344min、底日志 96。

## 3 顶栏

- `top_bar.gd`（Control 自绘）：
  - 指挥官示例名 `指挥官 · 沧澜`（`@export` 可配置）；任务时间/港内时间；3 条动态计时器（TRANSIT WINDOW/PORT SLOT/IFF ACK，自动倒计时/EXPIRED/进度条）；
  - 槽位：LINK（無線電 8s/LINK OK）、TIMESCALE ×1、Δv 8,420 m/s、ROE 僅自衛；
  - 右侧三色圆点（放大/悬停显示 tip；点击仅 `print + dot_action` 信号，不实现存档）：SAVE / SAVE+MENU / SAVE+QUIT；
  - 文字通过 `_tokens` token 表加载（COMMANDER/MISSION/LINK/...）。

## 4 接触列表

- `contact_list.gd`（Control 自绘，320min）：
  - 友军组头 `▾/▸` 可折叠；默认隐藏 no-threat 非友军；示例 8 条；
  - 类型底色（friendly/unknown/neutral/station）；unknown/station 目标牌缩小（44 vs 50）；friend 行 50；
  - 选中高亮 + 2px 左边条 + 威胁底条；点击 `contact_selected` 信号/日志。

## 5 自定义指针

- `custom_cursor.gd`：隐藏系统指针，V1 准心；状态 default/point/disabled/drag：
  - hover 任意 Control → point；左键按住 → drag；`set_disabled(true)` → disabled（红色斜线）；
  - 只做视觉，不改变输入语义。

## 6 截图 / 验证

| 文件 | 分辨率 |
| --- | --- |
| `mockups/ui-proto-1920.png` | 1920×1080 |
| `mockups/ui-proto-1600.png` | 1600×900 |

- 均 `UI PROTO SHOT size=... err=0`；headless 场景加载一次；未跑全量 regression。
- 坐标：容器布局，无固定旧 HUD 像素；顶栏约 H72、接触 W320、右栏 W344、底 H96；9-slice 面板边距 8。

## 7 未完成 / 限制

1. 仅壳/视觉：无玩法、物理、存档、真实计时/事件。
2. 三色点点击仅信号/日志；未接存档/回主菜单/退出实现。
3. contact 数据为示例；无真实 state 接入。
4. custom cursor 的 point/drag 为视觉推断（hover/按住），未接具体控件命令。
5. 9-slice 为程序化纹理；无 atlas/DPI 多倍图。
6. 未跑全量 regression；未接入旧场景。
