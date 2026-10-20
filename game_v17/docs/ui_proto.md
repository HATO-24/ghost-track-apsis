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


---

## 8　阶段1C：UI 壳接真实 TimeService / EventBus（task-120）

### 8.1 数据流

```
ui_proto.gd
  ├─ TimeService.setup({epoch_s:760.8, scale:1.0})
  ├─ EventBus.setup({})
  ├─ top_bar.bind_services(time_service, event_bus)
  │    ├─ subscribe("tactical", _on_bus_event)
  │    └─ _process 只读 time_service.now_s() 判断 deadline；无本地倒计时
  ├─ _load_contacts() ← res://framework/content/scenario_transit_l4_l1.json:entities
  │    └─ ContactList.set_contacts(rows)
  └─ _seed_events() → EventBus.publish("tactical.timer", payload{label,duration_s,kind})

ui_proto._process(delta) → TimeService.tick(delta)
top bar 显示 T+now_s / L1 港内 epoch_abs_s / scale / paused
```

- 计时器由 EventBus `tactical.timer` 事件动态生成；`deadline_s = event.t + duration_s`；TopBar `_process` 用 `TimeService.now_s()` 过滤过期项（移除），不靠 UI 本地计时。
- 时标/暂停：`SPACE` 暂停/继续，`1/2/3/4` 切 ×1/×10/×60/×300；TopBar 显示 `RUNNING/PAUSED` 和时标。

### 8.2 事件 schema

```json
{"type":"tactical.timer","t":0.0,"source":"ui_proto","target":"top_bar",
 "payload":{"label":"变轨窗口 / BURN WINDOW","duration_s":30.0,"kind":"burn"}}
{"type":"contact.select","t":0.0,"source":"ui_proto.contact_list",
 "target":"1000","payload":{"index":0,"contact":{...}}}
{"type":"save.request","t":0.0,"source":"ui_proto.top_bar",
 "target":"save|menu|quit","payload":{"kind":"save","save_implemented":false}}
```

- 三色圆点点击仅 publish `save.request`；不实现存档。
- 接触列表：数据来自 scenario `entities`（9 条：5 ship + 4 station）；不硬编码；友军可折叠，no-threat 默认隐藏，选中 publish `contact.select`。
- 自定义指针沿用 `custom_cursor.gd`：hover Control→point，按住→drag，`set_disabled(true)`→disabled。

### 8.3 截图 / 验证

| 文件 | 分辨率 |
| --- | --- |
| `mockups/ui-proto-live-1920.png` | 1920×1080 |
| `mockups/ui-proto-live-1600.png` | 1600×900 |

- 均 `UI PROTO SHOT size=... err=0`；headless 场景加载一次。
- 顶栏显示真实 `MISSION T+...` / `L1 港内 ...` / `×1 RUNNING`；EventBus 计时器 `变轨窗口/入轨/链路` 有真实倒计时；底日志输出 CONTACTS/EVENTBUS 加载。

### 8.4 未完成 / 限制

1. TimeService 只驱动 UI 时间显示/计时器过期；未接剧情/物理/存档。
2. 示例计时事件由 UI 启动时发布，不是剧情时间线；过期后仅移除，不触发任务结果。
3. 接触数据来自 transit scenario entities，不是完整 track 表；无实时传感器/航迹更新。
4. 三色点只 publish `save.request`；没有任何存档实现。
5. 选接触只发 `contact.select`，不驱动任务/剧情。
6. 未跑全量 regression；未改核心/旧场景/project。


---

## 9　阶段1D：右栏舰船/目标页 + 底部命令队列/事件日志（task-125）

### 9.1 右栏（`right_panel.gd`，约 344×H）

- 顶部 `SHIP / TARGET` tab（可点击）；来源标签显示 `DEMO · NO SESSION`（无 GameSession 时明确 DEMO），有 session 时 `GAME SESSION`。
- 舰船页字段：舰名/批号/身份/BADGE、距离/CLASS、传感器摘要、损管摘要、ROE、Δv（DEP/ARR/TOT）、按钮槽位 `NAV / DAMAGE / OPTICAL / INFO OPS`。
- 目标页：`AV-4412 传唤者` 示例目标，UNKNOWN / IFF SHADOW / contact L0 / radar-off，明确 `DEMO TARGET · NO SESSION`；不伪造实时目标。
- 无 selected/无数据时字段显示 `NOT READY`；按钮仅发 `page_action` 信号 + 日志，不接剧情/物理/存档。
- 坐标：右栏容器 `PanelContainer` W344min；内部自绘 0..W，tab y4，标题 y36，字段 14–15px 行距，按钮槽位固定底部。

### 9.2 底部（`command_log.gd`，H132）

- 左：命令队列（DEMO，明确 `DEMO · NO GAMESESSION`）：`id / state / sender → receiver / action / mode / delay`；无数据 `NO COMMAND DATA · NOT READY`。
- 右：事件日志（真实 EventBus）：`t + type + text`，最多 4 条；无事件 `NO EVENT DATA · NOT READY`。
- 命令队列与事件日志分栏绘制，不重叠；只读。
- 数据源：`EventBus.recent(8)`（ui_proto `_refresh_command_log` 每 10 帧）；三色点仍 publish `save.request`。

### 9.3 截图 / 验证

- `mockups/ui-proto-panels-1920.png`（1920×1080）：右栏舰船页 + 命令队列/事件日志。
- `UI PROTO SHOT size=(1920,1080) err=0`；headless 场景加载一次；未跑全量 regression。

### 9.4 未完成 / 限制

1. 当前 ui_proto 未 boot GameSession；命令队列为 DEMO，右栏字段为 DEMO/NOT READY，不能宣称已接 session 实时数据。
2. 事件日志只读 EventBus recent；无 GameSession 时无命令/剧情事件。
3. 右栏按钮只发信号/日志，未接导航/损管/光学/信息作战。
4. 目标页为 DEMO 示例；无真实 target snapshot。
5. 未实现剧情/物理/存档；未跑全量。


---

## 10　阶段1E：UI 壳 boot GameSession + SaveService（task-126）

### 10.1 真实 session

- `ui_proto._ready()`：
  - `GameSession.boot({"orders":[{"action":"HOLD","issuer_id":"apsis","target_ids":["harmattan"],"issue":true,"opts":{"auth_required":false}}]})`；
  - `SaveService.setup("user://saves")`；**初始不写**，只有三色点或 `DSH_UI_SAVE_TEST=1` 才写。
- 真实字段（本次 boot）：
  - entities：`apsis`(1000, ship, flagship)、`harmattan`(1001, ship)、`l1_station`(3100, station)；
  - orders：`O-000001` / `HOLD` / `apsis → harmattan` / status `QUEUED` / mode `LD` / delay `1.0s`；
  - events：`order.issued`、`order.delayed`、`tactical.timer` 等来自 session bus。
- 顶栏时间/暂停/时标改读 `session.time`；计时器仍订阅 `session.bus tactical.timer`。
- 接触列表：session snapshot entities（3 条）+ `config/schema/track.json` example（1 条，badge `DEMO TRACK`，明确 DEMO）；点击 publish `contact.select`。
- 命令队列：`session.snapshot().components.orders.orders`；无订单时显示 `NO COMMAND DATA · NOT READY`（本 boot 有 1 条真实 order）。
- 事件日志：`session.bus.recent(8)`；显示 `t / type / text`。
- 右栏：按选中实体 `entity_id/batch` 从 session snapshot 查真实 name/batch/kind/flags/pos → 距离；传感器/损管/ROE/Δv 在 session 无对应组件时明确 `NOT IN SESSION · NOT READY`；track DEMO 单独标 `DEMO TRACK`。

### 10.2 三色圆点 / SaveService

- `top_bar` 点击三色点发 `dot_action`；`ui_proto._on_dot_action(kind)` 映射：
  - green `save` → `SaveService.save_with_intent(session,"save")`；
  - yellow `menu` → `save_and_menu`，返回 `should_show_menu=true`；**不切菜单**；
  - red `quit` → `save_and_quit`，返回 `should_exit=false`（SaveService 当前实现）；**不退出**。
- 顶栏绘制 `SAVED slot=... · bytes · checksum8` / `SAVE FAILED reason`。
- 写盘：`user://saves/save.json`；原子写 + `.bak`（SaveService）。
- 测试开关：
  - `DSH_UI_SAVE_TEST=1` 时 boot 后执行一次 save + `load_metadata("save")`，日志输出 `SAVE TEST`；默认不写。

### 10.3 截图 / 验证

- `mockups/ui-proto-session-1920.png`（1920×1080）：真实 session 接触、右栏、命令队列/事件日志 + 顶栏 `SAVED save`。
- 本次测试结果：`SAVE TEST save=OK slot=save path=user://saves/save.json`，`metadata=true`；截图 `UI PROTO SHOT size=(1920,1080) err=0`。
- 未跑全量 regression；未改核心/旧场景。

### 10.4 未完成 / 限制

1. 右栏只接 session 实体字段；sensors/damage/ROE/Δv 组件在 session demo 中无数据，显示 `NOT IN SESSION · NOT READY`，不是伪造。
2. 命令队列来自 session orders（本次 demo 仅 1 条 HOLD），无完整命令 UI/操作。
3. 黄/红点只保存并返回 `should_show_menu/should_exit`；未实际切菜单/退出。
4. 接触列表中的 track example 为 DEMO；session entities 3 条，不是完整关卡接触表。
5. 不实现剧情/物理；未跑全量。
