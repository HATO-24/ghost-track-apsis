# 方案B · 自绘 V1 HUD（LayoutTokens / TextMetrics / PanelPainter）

> 任务 task-144。新增：
> `scripts/ui/layout_tokens.gd`、`text_metrics.gd`、`panel_painter.gd`、`v1_hud.gd`、`v1_hud.tscn`、本文件。
> 不改旧 HUD/transit/Control 壳/core/project；未 commit；不实现 IME/剧情/物理。

## 1 token / 布局

`layout_tokens.gd`：
- 读取 `config/ui_tokens.json`；缺文件/缺键用内置同值 `FALLBACK`。
- 提供 `size / line_height / baseline / padding / gap / metric / color / layout / fonts`。
- **V1 色板固定**在 `V1_COLORS`（pal.gd 磷光绿/冰蓝/琥珀/朱红）；config 只提供尺寸/行高/间距 token，避免现代蓝 palette 覆盖 V1。
- `layout(w,h)` 计算五区 rect，面板本身不写死坐标：
  - top H72；left W ≈16.6%（286–340）；right W ≈18%（300–360）；bottom H132；gap 6–8；center 为剩余区域。
  - 1920/1600 均走同一 layout 函数。

## 2 text_metrics.gd

- `font(mono)`；`width(text,mono,size)`（带缓存）；`line_height/baseline`；`fit(text,max_width,...)` 二分椭圆省略；`align_right`。
- CJK 使用 `fonts.gd` 的 Microsoft YaHei/SystemFont；等宽 Consolas/Courier New；无新字体文件。

## 3 panel_painter.gd

- `panel(rect,title,accent)`：1px 外框 + 标题基线 + 分割线。
- `sub_panel/divider/label/label_right/button/list_row/target_card/key_value/section`。
- 统一 V1 颜色/字号/内边距；自绘 HUD 不依赖 Control Theme/StyleBox。

## 4 v1_hud.gd 自绘 HUD

- 五区：顶栏 / 接触 / 战术图 / 右栏 / 命令日志。
  - 顶栏：`GHOST TRACK // APSIS`、指挥官、MISSION T+、L1 港内、3 条动态计时、链路/时标/Δv/ROE、三色点。
  - 接触：`友军 / FRIENDLY` 组标题、可折叠（▾/▸）、类型底色/选中左条、目标牌缩高（unknown 42 vs 48）。
  - 中图：V1 星图/真实内容路线示意（L4-02→L1）、5 舰点、时间轴窗口段；明确 `DEMO SAMPLE`。
  - 右栏：SHIP/TARGET tab、名称/批号/类型/身份、传感器/损管/ROE/Δv、四个按钮槽。
  - 底栏：命令队列 vs 事件日志分栏。
- 数据：从 `scenario_transit_l4_l1.json`/`transfer_l4_l1_cached.json` 读取内容；**无 GameSession → 明确 DEMO**（接触最后一条 `DEMO-2001`、命令/事件/传感器均 `DEMO` 标签）。不伪造实时 session。
- 交互：三色点仅 print；接触行选中；折叠；右栏 tab；不写状态。
- 入口/截图：`DSH_SHOT`、`DSH_HUD_SIZE=1920x1080|1600x900`，40 帧后保存退出。

## 5 与 Control 壳的可对比点

| 维度 | 自绘 V1 HUD（本任务） | Control 壳（ui_proto/game_shell） |
| --- | --- | --- |
| 布局 | LayoutTokens 五区，无面板硬编码坐标 | Container/Theme 自适应 |
| 文本 | TextMetrics 手动基线/省略 | Label/Font 自动 |
| 面板 | PanelPainter 1px 自绘 | StyleBoxTexture 9-slice |
| 视觉 | 磷光绿高密度、无控件皮肤 | 同色板但控件边框/间距更松 |
| 数据 | 内容快照 + DEMO 标注 | GameSession 真实数据 |

## 6 截图 / 验证

| 文件 | 分辨率 |
| --- | --- |
| `mockups/v1-hud-1920.png` | 1920×1080 |
| `mockups/v1-hud-1600.png` | 1600×900 |

- 均 `V1 HUD SHOT err=0`；headless 场景加载一次；四个脚本 `--check-only` 通过。

## 7 边界 / 未完成

1. 本样张未 boot GameSession；接触/命令/事件/传感器为内容快照 + 明确 DEMO，不能宣称实时。
2. 自绘 HUD 为视觉样张：点击仅选中/折叠/tab/print，不接玩法；无 IME/剧情/存档。
3. TextMetrics 基线为 token 校准（CJK baseline = size+3px），未做真实字形 metrics/kerning。
4. 地图为内容路线示意，不是权威导航图；5 舰点未做真实逐帧插值。
5. 未跑全量 regression；未改 project/main_scene。


---

## 8　方案B-2：V1 HUD 接真实 Session（task-145）

### 8.1 数据流

```
v1_hud.gd
  ├─ ShellBinder.boot()
  │   ├─ GameSession.boot({track_table:true, story_state:true, sensor_service:true})
  │   ├─ _seed_tracks / sensor step / track_vm
  │   ├─ SaveService user://saves
  │   └─ contacts/commands/events/sensor_vm/story_vm
  ├─ 玩家名：flow_state.player_name → DSH_PLAYER_NAME → fallback「沧澜」
  ├─ 接触：binder.contacts（track_vm + entities）；默认选中 id=1000（旗舰 APSIS）
  ├─ 右栏：binder.ship_fields / sensor_state；真实 track/session 字段
  ├─ 顶栏：binder.session.now_s、binder.timers、binder.roe_text、binder.delta_v
  ├─ 底栏：binder.commands / binder.events
  └─ 三色点：ShellBinder.save(intent) → SaveService；显示 SAVED/失败
```

- 真实字段：旗舰 `[1000] 远地点` 默认选中；接触列表 `[1001] 哈马丹`、`[3100] L1 港`；右侧 SENSOR RADAR/EMCON/OBS、ROE phase prelude、Δv 1822.6 m/s、命令 `O-000001 QUEUED`、事件 `order.issued/order.delayed/order.transmitting/order.delivered`。
- 另保留 fallback：无 session/track 时显示 `NO SESSION / NO TRACK`，不伪造。
- `t` / 会话 tick 来自 binder；不自动推进剧情/物理。

### 8.2 替换流程 Shell

- 流程改为：`prologue → nav_page → port_page → v1_hud.tscn`。
- `port_page.DEPART` 现在写 flow phase=shell 后切 `v1_hud.tscn`；`game_shell.tscn` 文件保留但流程不再进入。
- 手动入口：`game_shell.tscn`（旧 Control 壳）仍可直接运行；正常流程以 v1_hud 为准。
- Control 仅用于 IME/系统弹窗；v1_hud 页面为纯自绘。

### 8.3 截图 / 验证

- `mockups/v1-hud-live-1920.png`（1920×1080，SESSION LIVE + `[1000]` 旗舰 + SAVE 结果 + 真实命令/事件）。
- `V1 HUD SHOT err=0`；headless 主流程 smoke：
  `prologue(briefing/navigation) → nav restore COMPLETE → port（phase=port）→ v1_hud`，
  最终 `[V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=3 commands=1`。
- Save test：`SAVED slot=save · 15811B · cfc9fed3`，metadata=true。

### 8.4 边界 / 未完成

1. 右栏 sensors 未接 damage_service；DAMAGE 行显示 session 无组件 `NOT READY`，不伪造。
2. 命令队列只有 demo seed 1 条 HOLD；无完整命令操作。
3. 三色点 SaveService 实际写 `user://saves/save.json`；黄/红返回菜单/退出意图但不切 UI/退出。
4. 地图仍为路线示意，不是实时导航权威图；无 IME/剧情/物理。
5. `game_shell.tscn` 保留但不再进入流程；未跑全量 regression。


---

## 9　方案B-3：自绘损管/ROE四档/命令队列最小交互（task-147）

### 9.1 右栏页面

- `DAMAGE` → 自绘损管 overlay：
  - 7 分区（hull/power/propulsion/sensors/comms/tanks/docking），每行显示 integrity/state/fire/decomp；点击选中；
  - 右侧 RESOURCES（teams/spares/personnel）、QUEUE、EVENTS；
  - 底部 `FIX / PRI / CANCEL` 调 `V2DamageModel.assign_repair/set_priority/cancel_repair`；失败 reason。
  - 数据源：当前 GameSession 无内置 `damage_vm`；本页直接挂 `V2DamageModel`（content damage_l1，ship apsis，7 sections），明确 `SOURCE · V2DamageModel shadow (session 无 damage_vm)`，不伪造。
- `ROE` → 四档 overlay：`DEFEND/HOLD/TIGHT/FREE`，显示当前档位（TIGHT）、授权提示；默认序章 prelude 时锁定；`DSH_V1_ROE_UNLOCK=1` 解锁用于测试。解锁后按钮调 `binder.session.set_roe(level)`；当前 CombatService 由 v1_hud 以可选服务注入 session（真实 `set_roe` API）。
- `NAV` → `nav_page.tscn`；`OPTICAL/INFO` → 明确占位信号，不接玩法。

### 9.2 命令队列

- 底栏命令行可点击选中（默认第一条）；选中高亮；显示 DETAIL（id/actor/target/action/mode/delay/state）。
- `ABORT` → `session.abort_order(id,"ui_abort")`；`REVOKE` → `session.reject_order(id,"ui_revoke","commander")`；成功/失败 reason 写底栏/日志。
- 数据 source `binder.commands`（session.components.orders.orders）。

### 9.3 实测

`DSH_V1_TEST=1`：
- `DAMAGE FIX hull · OK` → `PRI hull · OK` → `CANCEL hull · OK`（V2DamageModel 7 sections）。
- `ROE set_roe HOLD · OK`（测试解锁；默认 prelude locked）。
- `COMMAND REVOKE O-000001 · OK`（session reject_order 真实 API）。
- `DAMAGE/ROE` 页面、命令选中均只自绘 Painter/LayoutTokens，无 Control 面板。

### 9.4 截图 / 验证

- `mockups/v1-hud-damage-1920.png`（1920×1080，选中 hull，7 分区/资源/队列/事件/FIX/PRI/CANCEL，底部 ABORT/REVOKE）
- `mockups/v1-hud-roe-1920.png`（四档 + 当前 TIGHT + 授权提示；测试环境解锁）
- 均 `V1 HUD SHOT err=0`；headless interaction test 一次；`v1_hud.gd --check-only` 通过。

### 9.5 边界 / 未完成

1. GameSession 无内置 damage_vm；损管为 V2DamageModel shadow，不宣称 session 原生损管。
2. ROE 默认 prelude 锁定；测试用 `DSH_V1_ROE_UNLOCK=1`；授权提示明确 ROE 不授予开火许可。
3. 命令只有 demo seed 1 条；ABORT/REVOKE 状态/原因由 session API 返回，无完整命令录入 UI。
4. No Control panels；IME/系统弹窗仍保留 Control 边界。
5. 不实现剧情/物理/完整战斗；未跑全量 regression。
