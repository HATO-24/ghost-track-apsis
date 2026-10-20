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


---

## 10　方案B-4：自绘命令/通信页（task-148）

### 10.1 COMMS/ORDERS overlay

- 右栏 `COMMS / 命令` 按钮或 `DSH_V1_VIEW=comms` 打开自绘 overlay。
- 左侧：
  - 频道条 `LD / LR / RDO / IR / VIS`（CommsService.MODES；不伪造频道）；
  - MESSAGE STREAM：读 `binder.session.comms.vm().events`，格式 `[from_name 至 to_name]-[mode]-[content]`；
  - `from/to/mode` 全部取事件字段（不硬编码舰名）；`content` 优先事件 `text`，否则 `text_key`，再否则结构化 fallback（kind/reason），不伪造具体台词。
- 启动时若无消息，`_seed_comms_sample()` 用真实 `session.send_comms` 从 `binder.contacts` 的 entity_id 生成 LD/LR 两条（不是硬编码舰名）；本次实测成功，MESSAGE STREAM 显示 2 条。
- 右侧 COMMAND PANEL：
  - 类型 `HOLD / NAV / EMCON / IFF / ROE`；目标来自当前接触 `entity_id`（默认 harmattan），`ISSUER apsis`；
  - `SEND / 发送`：
    - HOLD/NAV → `session.issue_order(action,"apsis",[target])`；
    - EMCON/IFF → ShellBinder.sensor_command；
    - ROE → 若 prelude 锁定则拒绝，否则 `session.set_roe("HOLD")`。
  - 发送后 `binder.refresh()` 刷新消息流/命令队列；结果显示在面板。
- 命令队列（overlay + 底栏）可点击选中，显示详情；`ABORT→session.abort_order`，`REVOKE→session.reject_order`，失败 reason 可见。
- 全部控件走 LayoutTokens/PanelPainter；无 Control 面板。

### 10.2 实测

`DSH_V1_TEST=1`：
- damage FIX/PRI/CANCEL OK；ROE set_roe HOLD OK；COMMAND REVOKE `O-000001` OK；
- `COMMS SEND HOLD → harmattan · OK`；消息流/队列刷新。

### 10.3 截图 / 验证

- `mockups/v1-hud-comms-1920.png`（1920×1080）：频道条、2 条真实消息、命令类型 HOLD/NAV/EMCON/IFF/ROE、target harmattan、命令队列、ABORT/REVOKE。
- `V1 HUD SHOT err=0`；headless interaction test 一次；`v1_hud.gd --check-only` 通过。

### 10.4 边界 / 未完成

1. 消息正文仅用 text_key / 结构化 fallback；无完整剧本对白/文本库定制。
2. COMMS seed 仅为 UI 演示产生的真实 session 事件（LD/LR 两条），非剧情消息。
3. HOLD/NAV 走 order API；EMCON/IFF/ROE 走 sensor/combat API；无完整命令录入/权限流。
4. ROE 默认 prelude 锁定；未接正式授权/战斗。
5. 不实现剧情/物理/完整通信；未跑全量 regression。


---

## 11　方案B-5：通信页布局/旗舰默认修复（task-149）

### 11.1 默认目标/接触排序

- 接触排序：`_normalize_contacts()` 将旗舰 entity/id=`apsis` 归一为 batch `1000` 并固定第一；其余接触保持原顺序（友军/站体/未知规则不变）。
- 初始 selected = `1000`（若刷新已选则保持 selected id；`_select_preserving(old_sel)`）。
- `COMMS` 默认 target = 当前选中 contact 的 `entity_id`；不再写死 `harmattan`（本次选中旗舰后 target=`apsis`）。
- HOLD/NAV/EMCON/IFF/ROE 命令面板显示当前 target；点击接触列表同步 target。

### 11.2 通信页布局

- COMMAND PANEL 固定宽 380px；左侧 MESSAGE STREAM 宽度 `r.size.x - 380 - 28`，不压左侧。
- 消息每条一行：`[from 至 to]-[mode]-[content]`；按行高 14px、`TextMetrics.fit` 截断；最多按可用高度截取；交替行底；无消息显示 `NO MESSAGES · NOT READY`。
- 命令队列/ABORT/REVOKE 固定在右侧面板底部，不与消息区重叠；消息区高度扣除底部按钮区。
- 命令类型/目标/发送保留；发送后刷新 binder。

### 11.3 截图 / 验证

- `mockups/v1-hud-comms-fixed-1920.png`：旗舰 `[1000]` 第一/选中；COMMS target `apsis`；消息流两行不叠；右侧固定面板；命令队列/ABORT/REVOKE 不重叠。
- `mockups/v1-hud-live-1920.png` 重截：旗舰 1000 置顶且默认选中。
- 均 `V1 HUD SHOT err=0`；headless v1_hud 加载一次；`v1_hud.gd --check-only` 通过。

### 11.4 边界 / 未完成

1. 消息内容仍为 text_key/结构化 fallback，无完整剧本文本。
2. COMMS 默认目标随选中接触；当前默认旗舰 apsis（批号1000），不是 harmattan。
3. 命令/ROE/损管仍为最小交互，不接完整剧情/授权/物理。
4. 未跑全量 regression。


---

## 12　方案B-6：光学/识别 overlay + 通信页压缩（task-150）

### 12.1 OPTICAL/识别

- 右栏 `OPTICAL / 光学` 或 `DSH_V1_VIEW=optical` 打开；`DSH_V1_VIEW=optical` 样张自动选中第一个有 track 的接触（当前 harmattan），target=当前选中 entity。
- 目标字段：
  - target/entity/TRACK、LEVEL L1–L4（`track_vm` level）、identity、SOURCES、EVIDENCE、RANGE/BRG；
  - FOV/SNR 从 `sensor_vm.channels` 查，缺失显示 `—`；
  - 不伪造 L3/L4：本次 track 为 L2，L3/L4 格显示未激活。
- 右侧 V1 光学小窗/瞄准框：FOV、SNR、TRACK level、准心+目标框；无假图像。
- 按钮真实 API：
  - VIS → `sensor_service.start_channel("optical", target)`；
  - IR → `start_channel("ir", target)`；
  - IFF QUERY → `query_iff(target)`；
  - LIGHT SIGNAL → `session.send_comms(...,"VIS",...)`（真实链路；无 route 显示 reason）；
  - ELINT → 当前无 sensor API，明确返回 `FAILED · elint_not_wired`，不伪造。
- 操作后 `binder.refresh()`，证据/等级/消息刷新。

实测：`VIS harmattan · OK`、`IR harmattan · OK`、`IFF harmattan · OK`、`ELINT · FAILED elint_not_wired`、`LIGHT · FAILED no_route`（真实链路原因）。

### 12.2 通信页压缩

- COMMS overlay 高度限制 `min(body,560)`，不再占满；消息区最多 8 行（14px/行），`TextMetrics.fit` 截断，无叠字。
- COMMAND PANEL 固定宽 380px；命令队列/ABORT/REVOKE 固定在面板底部；空状态 `NO MESSAGES · NOT READY`。
- 默认 target 仍为当前选中旗舰（本次 apsis/1000）；HOLD/NAV/EMCON/IFF/ROE 显示 target。

### 12.3 截图 / 验证

- `mockups/v1-hud-optical-1920.png`（L1–L4/identity/sources/evidence/range/FOV/SNR + 光学瞄准框 + 五按钮）
- `mockups/v1-hud-comms-compact-1920.png`（高度 560、消息不叠、固定命令面板、ABORT/REVOKE 不重叠）
- 均 `V1 HUD SHOT err=0`；headless interaction test 一次；`v1_hud.gd --check-only` 通过。

### 12.4 边界 / 未完成

1. ELINT 未接 sensor API，固定失败 reason；LIGHT 走 comms VIS 链路，无 route 时真实失败。
2. 光学无真实图像/姿态；小窗为 V1 瞄准框示意；FOV/SNR 仅 sensor vm 有则显示。
3. track 当前 L2；不伪造 L3/L4。
4. 通信页消息仍 text_key/fallback；命令最小交互；不实现剧情/物理/完整战斗。
5. 未跑全量 regression。


---

## 13　方案B-7：自绘战斗终端（task-152）

### 13.1 数据源

- 右栏 `COMBAT / 战斗` 或 `DSH_V1_VIEW=combat` 打开自绘 overlay。
- `CombatService` 为 session 可选服务（v1_hud 已把可选 CombatService 注入 `binder.session.combat_service`）。
- 目标：将 `binder.track_vm.tracks` 通过 `register_track` 注册到 CombatService，取 `combat vm.tracks`；显示 level/identity/threat/range。当前两条 track T0001/T0002。
- 武器：`combat vm.weapons`（decoy/jammer/missile/pd/railgun），显示 ammo/cooldown/range/kind；点击武器切换选中。
- ROE/授权：`vm.roe` 四档 + `session.combat_authorization(TRACK/SOLUTION/FIRE,target,weapon)` 状态；缺授权显示 LOCKED/reason。
- 预测：仅 `CombatService.predict_shot(target,weapon)`，显示 `PREDICTION / INTERFACE · NO PHYSICS`、TOF/HIT%/ERR；不执行物理/命中。
- 战斗事件：`combat vm.events`。

### 13.2 交互 / 实测

- 按钮：`TRACK`、`SOLUTION`、`AUTHORIZE FIRE`、`FIRE`；ROE 四档也在此页可点。
  - TRACK → `_combat.request_track(target,true)`；实测 OK。
  - SOLUTION → `_combat.request_solution(target,weapon,true)`；实测 T0001/missile FAILED `inside_min_range`（真实原因）。
  - AUTHORIZE FIRE → `session.grant_authorization("FIRE","target",target)`；实测 OK。
  - FIRE → `_combat.request_fire(target,weapon,true)`；实测 FAILED `no_ready_solution`（无 solution 不命中，真实原因）。
  - ROE → `_combat.set_roe`（同一 CombatService）。
- FIRE 通过后也只记录 CombatService 事件/消耗，不做物理命中/世界写入；本次截图无伪造命中。

### 13.3 截图 / 验证

- `mockups/v1-hud-combat-1920.png`（1920×1080：目标列表 L2/identity/threat/range、武器架、ROE 四档、TRACK/SOLUTION/FIRE 授权、预测 TOF/HIT%/ERR、战斗事件、TRACK/SOLUTION/AUTHORIZE FIRE/FIRE）。
- `V1 HUD SHOT err=0`；headless interaction test 一次；`v1_hud.gd --check-only` 通过。

### 13.4 边界 / 未完成

1. CombatService 为 shadow；无真实弹道/命中/伤害/世界写入；敌方/威胁数据来自 track_vm，目标默认 T0001。
2. 本页 `SOLUTION` 因 inside_min_range 失败、`FIRE` 因 no_ready_solution 失败，均显示原因，不伪造成功。
3. 武器架授权需求/冷却由内容与 service 状态决定；无完整武器选择/载荷 UI。
4. 不实现剧情/物理/完整战斗；未跑全量 regression。
