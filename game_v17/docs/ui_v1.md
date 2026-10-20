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


---

## 14　方案B-8：通信页双栏定稿（task-153）

### 14.1 布局

- COMMS overlay 固定高度 **600px**；在 center+right 区域顶部（不覆盖底部 command log，留出间隔）。
- 明确双栏，独立面板边框：
  - 左 58%：CHANNELS 表（LD/LR/RDO/IR/VIS，MODE/STATUS/LATENCY/EVENTS，来自 `session.comms.vm().links/events`）+ MESSAGE STREAM（最多 10 行、行高 16、`TextMetrics.fit`、交替行底）+ LINK DETAIL 填充下部；
  - 右 42%：COMMAND PANEL（HOLD/NAV/EMCON/IFF/ROE、TARGET/ISSUER/MODE、SEND）+ AUTH TRACK/SOLUTION/FIRE + COMMAND QUEUE + SELECTED COMMAND 详情 + ABORT/REVOKE；
  - 左右各 1px 边框，间距 12px；无大片连续空白（左栏 LINK DETAIL，右栏 SELECTED COMMAND/ROE/AUTH）。
- 空状态：`NO MESSAGES · NOT READY`，NO COMMAND 情况有明确文本。
- 默认 target = 当前选中旗舰（apsis/1000）；点击接触同步。

### 14.2 数据 / 边界

- CHANNELS 状态来自 comms vm links：disabled/occluded/jam>=0.7 → CLOSED/OCCLUDED/JAMMED；延迟/事件数真实。
- 消息 from/to/mode/content 来自 comms 事件；content text→text_key→结构化 fallback。
- SEND 仍调真实 session/CombatService API；AUTH 状态来自 `session.combat_authorization`；ROE 行来自 CombatService。
- 不实现剧情/物理；不伪造消息或授权。

### 14.3 截图 / 验证

- `mockups/v1-hud-comms-dual-1920.png`（1920×1080：600h 双栏、独立边框、CHANNELS 表、消息 2 行、命令/队列/详情/ABORT/REVOKE）
- `V1 HUD SHOT err=0`；headless v1_hud 加载一次；`v1_hud.gd --check-only` 通过。

### 14.4 未完成

1. 消息/频道为当前 session 演示数据；无完整通讯录/剧情对白。
2. 命令仍最小交互；授权/发送真实 API；无完整权限流。
3. 双栏固定 600h，极端窄窗口未测；不实现剧情/物理；未跑全量 regression。


---

## 15　方案B-9：存档/读档菜单（task-156）

### 15.1 三色点行为

- 绿 `save`：`SaveService.save_with_intent(session,"save")`，写 save 槽；顶栏显示 `SAVED slot=... · bytes · time · path` 或 FAILED reason。
- 黄 `menu`：写 menu 槽并打开 SAVE/MENU overlay；显示 SAVE+MENU 意图（不切场景）。
- 红 `quit`：写 quit 槽并显示 `EXIT INTENT ONLY · 不真正退出`；不调用 quit。
- 槽位/路径来自 `SaveService.slot_path / save_with_intent`；不伪造。

### 15.2 SAVE/MENU overlay

- 四槽列表 `save/menu/quit/autosave`：
  - 存在/EMPTY/CORRUPTED（load_metadata 失败 reason）；
  - UPDATED 时间、CHAPTER、LOCATION、SIZE bytes、t_s、PATH；
  - 存在且元数据有效时显示 `LOAD / 读档`；空/损坏 `LOAD · N/A`。
- LOAD：
  - 优先 `SaveService._read_slot_raw` 取 `session_save`，在当前已 boot track/story/sensor/combat 的 session 上 `load_state`（保留可选组件）；
  - load_state 的 seed 缺 combat_service 时由 UI 补 `combat_service:{}` 供快照恢复；
  - 失败 fallback 标准 `load_session`，仍失败显示 reason；
  - 成功替换/恢复 session 后 `binder.refresh()`，接触/命令/事件/顶栏刷新。
- 新建/继续：明确占位文案；不覆盖主菜单/退出。
- 全部自绘 LayoutTokens/PanelPainter。

### 15.3 实测

`DSH_V1_SAVE_TEST=1`：
- save `SAVED slot=save · 19231B · 2026-10-20T19:54:13 · user://saves/save.json`；
- metadata=true；
- `LOADED save · name=session · t=0s`（真实 load，非假加载）。

### 15.4 截图 / 验证

- `mockups/v1-hud-save-1920.png`（1920×1080：save 槽 EXISTS + path/size/time/chapter/location + LOAD；menu/quit/autosave EMPTY；ACTIONS 占位）
- `V1 HUD SHOT err=0`；headless save/load test 一次；`v1_hud.gd --check-only` 通过。

### 15.5 边界 / 未完成

1. 新建/继续只是占位；未接主菜单/新游戏剧情。
2. load 使用 UI 侧 raw payload + 当前 session 恢复（因 SaveService.load_session 新 session 缺少可选组件）；标准 load_session 仍作为 fallback；失败 reason 可见。
3. 无 autosave 写入；autosave 槽仅展示/读取。
4. 三色点只写文件/显示意图，不真正切菜单/退出；不实现剧情/物理；未跑全量 regression。


---

## 16　方案B-10：ELINT / 灯语接真实信号服务（task-158）

### 16.1 数据源 / boot

- `ShellBinder.boot()` 增加 `signal_service: true`；GameSession `_demo_signal_config` 生成 ELINT emitters（harmattan 等）与灯语 targets；v1_hud 可通过 `binder.session.signal_service` 读取。
- 光学/识别页新增真实 SIGNAL 小面板：`signal_service.vm()` → ELINT signals/fingerprints/candidates/observations/evidence、light codes/transmissions counts、last TX status/reason。
- 无 signal_service 时明确 `NO SIGNAL · signal_service NOT READY`。

### 16.2 按钮真实 API / 实测

- `ELINT`：`session.signal_intercept(target)` + `session.signal_df(target)`；调用后 `session.tick(0.1)` 路由，`binder.refresh()`。实测 `ELINT harmattan · OK`。
- `LIGHT TX`：`session.light_send(selected_code,target)`，保存 tx_id；实测 `LIGHT harmattan · OK`。
- `LIGHT RECV`：`session.light_receive(tx_id)`；实测 `OK`。
- `LIGHT ACK`：`session.light_ack(tx_id)`；实测 `OK`。
- 失败一律显示 reason；`SIGNAL DEMO` 使用真实 API 链，不伪造。
- 灯语码来自 `framework/content/light_codes_l1.json`（APPROACH_REQ 等），codes count/selected 显示在面板。

### 16.3 识别 / 边界

- 光学页 target 从 signal vm 的真实 emitters 选择（样张 harmattan），不是硬编码舰名。
- 当前 track_vm 的 signal tracks（T0001/T0002）存在，但其 track_table `entity_id/batch` 为空，无法可靠映射回 harmattan entity；因此光学页 TRACK 显示 `TRACK NOT READY` 是真实数据状态，未伪造 L3/L4。
- ELINT evidence 已在 signal vm 中（evidence 2），但不虚构 track 等级/身份。

### 16.4 截图 / 验证

- `mockups/v1-hud-signal-1920.png`（1920×1080：ELINT/LIGHT/SIGNAL 小面板、TX/ACK 状态、真实 ELINT counts/evidence、按钮 VIS/IR/IFF/ELINT/LIGHT TX/RECV/ACK）
- `V1 HUD SHOT err=0`；headless signal demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。
- 实测：ELINT OK → LIGHT OK → RECV OK → ACK OK，message `SIGNAL DEMO ACK harmattan · OK`。

### 16.5 未完成 / 边界

1. signal tracks 与 entity 映射缺失，光学页无法展示对应 L3/L4；不伪造。
2. 灯语选中码为第一个 real code；无完整选码/码表交互（面板显示 codes/TX）。
3. signal_service 为 shadow；不写 world/V15；不实现剧情/物理。
4. 未跑全量 regression。


---

## 17　方案B-11：动态目标/灯语全目标 UI（task-161）

### 17.1 ShellBinder 同步动态 targets

- `ShellBinder.refresh()` 每次构建 contacts 后调用 `_sync_signal_targets()`：
  - 把当前 contacts/world 实体写入 `session.signal_sync_targets(rows, {"replace_metadata": false})`；
  - 行字段：id/target_id/entity_id/batch/side/identity/pos_km/light_capable/active/destroyed；
  - `replace_metadata=false` 保留 core signal target 的已有 emissions/occlusion/light_capable 元数据；
  - 空/失败写 warning（`signal_service 未启用` / `signal targets 同步失败：reason`），不伪造。
- core `signal_service.targets` 中的动态 L1/O1（side unknown）补入接触列表，badge=`SIGNAL`，供任意 side 选择；非伪造 world 实体，明确来源 signal target。

### 17.2 光学/信号页

- target = 当前选中接触（可为任意 side）；SIGNAL 面板显示 `TARGET side=... identity=...`、ELINT counts、codes/selected、TX counts/状态、last TX reason；无 signal_service 显示 NO SIGNAL。
- LIGHT TX：`session.light_send(selected_code,target)`；CODE ◀/▶ 在 `signal_service.code_ids` 中切换真实选码；RECV/ACK：`light_receive/light_ack(tx_id)`；失败 reason 显示。
- ELINT：`signal_intercept` + `signal_df`；显示 observations/evidence/fingerprints/candidates；ELINT evidence 已在 signal vm 中，track 若无可映射 entity 显示 TRACK NOT READY，不伪造 L3/L4。
- 任意 side 不阻止发送；ACK 是否成功由 target `light_capable/active/occluded` 等 capability 决定，无 ACK 时显示真实 reason。

### 17.3 实测（DSH_V1_VIEW=signal）

- binder：`signal targets synced added=1 updated=2 count=5`（后续 updated=3）。
- 样张 target=L1（动态 SIGNAL target，side=unknown）：
  - `ELINT L1 · FAILED · no_signal`（L1 无 emitter，真实原因）；
  - `LIGHT L1 · OK` → `RECV L1 · OK` → `ACK L1 · OK`；
  - SIGNAL 面板 ELINT signals 81 / evidence 2 / codes 10 / selected APPROACH_REQ / last TX ACKED。
- 联系人列表：[1000] 旗舰、[1001]、[3100]、L1 SIGNAL、O1 SIGNAL。

### 17.4 截图 / 验证

- `mockups/v1-hud-signal-all-sides-1920.png`（1920×1080：target L1 side=unknown、SIGNAL 面板、CODE ◀/▶、LIGHT TX/RECV/ACK、SIGNAL contacts）
- `V1 HUD SHOT err=0`；headless signal demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 17.5 未完成 / 边界

1. 当前 world 没有敌方实体；样张用 core 动态 SIGNAL target L1（side unknown）演示任意 side；敌方/中立流程同一 API，未另行造实体。
2. L1 无 emitter，所以 ELINT 失败 reason 真实；harmattan ELINT 在上一版已实测 OK。
3. 无完整码表交互（仅 ◀/▶ 切换 10 个 real codes）；无完整 ACK 重试流程。
4. signal_service 为 shadow；不写 world/V15；不实现剧情/物理；未跑全量 regression。


---

## 18　方案B-12：设施识别 / 港口注册表（task-163）

### 18.1 ShellBinder / FacilityRegistry

- `ShellBinder.boot()` 增加 `"facility_registry": true`；core ready 时创建 7 cluster / 29 facilities / 57 ports。
- 每次 refresh 构建 contacts 后：
  - station 实体通过 `session.facility_for_entity(entity_id)` 映射到 FacilityRegistry；
  - 所有 track/entity contacts 再次补 facility 映射，避免 track 行覆盖 entity 行导致漏挂；
  - 接触行新增 facility_id/facility_name/facility_code/transponder_code/transponder_type/facility_class/owner/side/cluster_id/cluster_name/services/ports/physical；badge=FACILITY。
- 无 registry/映射时明确 NOT READY，不伪造。

### 18.2 V1 HUD FACILITY 页

- 右栏新增 `FACILITY` tab（SHIP / TARGET / FACILITY）；选中设施接触后切到该页。
- 显示：名称、ID/CODE、TRANSPONDER、CLUSTER、OWNER/SIDE、SERVICES、PORTS、ORBIT、MASS/RADIUS、STATION-KEEPING；来源标注 `GameSession.facility_for_entity → FacilityRegistry.facility_card`。
- 本次 `[3100] L1 港` → `L1-05 Chronos · FC-L1-05 · TXP-L1-05 · L1_MERIDIAN · depot`；PORTS PORT-L1-05-1/PORT-L1-05-2。
- 无映射显示 `NO FACILITY DATA · NOT READY`。

### 18.3 port_page

- 直接加载 `FacilityRegistry`（29 设施 / 7 cluster）；L1 `facilities_by_cluster("L1_MERIDIAN")` 读取 Greenwich/Sextant/Chronos/Astrolabe。
- `_config()` 从注册表每个 facility.ports 生成 PortService 配置，port_id 使用注册表真实值（PORT-L1-01-1 等）；PortService boot 后默认绑定第一个 port_id。
- 左栏显示 4 个 L1 设施（facility_code/name/transponder/ports）+ PortService 各 port 的 berth/tug/fuel 资源；无 registry 显示 `NO FACILITY REGISTRY · NOT READY`。
- 实测：`facility_registry ready=true count=29 clusters=7`，`boot=true ports=8`。

### 18.4 截图 / 验证

- `mockups/v1-hud-facility-1920.png`（1920×1080：FACILITY tab + Chronos 卡片字段 + 接触设施 badge）
- `mockups/port-page-facility-1920.png`（1920×1080：FacilityRegistry L1 设施/port_id 列表 + PortService 资源）
- 均 `SHOT err=0`；headless v1_hud/port_page 一次；`v1_hud.gd/shell_binder.gd/port_page.gd --check-only` 通过。

### 18.5 未完成 / 边界

1. FACILITY 页为只读卡片；未接设施交互/服务请求。
2. port_page 仍用旧 Control 布局；仅数据源切到 FacilityRegistry；PortService 资源为 8 个 registry port 的示例容量，不写剧情/物理/存档。
3. 设施实体仅 l1_station→Chronos；其余 L1 设施在 port_page 列表展示，无 world entity 绑定。
4. 不实现剧情/物理/完整港务流程；未跑全量 regression。


---

## 19　方案B-13：应答机 IFF/TRANSPONDER UI（task-165）

### 19.1 数据 / boot

- `ShellBinder.boot()` 增加 `"transponder_service": true`；GameSession 创建 TransponderService（facility_registry 内容 + `transponders_prologue.json` profiles）。
- ShellBinder 提供 `transponder_query(target, mode="mode_s", opts={})`，内部 `session.transponder_interrogate("apsis", target, mode, opts)`，保存 `last_transponder_reply`，不伪造。

### 19.2 光学/识别页 IFF QUERY

- IFF QUERY → `binder.transponder_query(target,"mode_s")`（当前选中 target，可为 ship/station/facility）。
- 显示真实 reply 字段：
  - `ok`：entity_type（ship/station/port/fuel/tank/otc/relay）/status/identity/transponder_code/registration_code/facility_code/crypto(valid)/confidence/trigger_id；
  - 无应答：`NO REPLY · reason`；captured/spoofed 由 reply.status/identity 显示；失败不伪造。
- 结果进入 SIGNAL/IDENT 小面板（IFF 两行），证据由 session.flush transponder evidence 路由到 track；本次 L4 IDENTITY、EVIDENCE 5 ids。
- 查询后 `binder.refresh()`；设施页 `TRANSPONDER` 行显示最近应答（注册码/设施码/status/crypto）或 `NOT QUERIED`。

### 19.3 实测

- 样张 target=`l1_station`（L1 港/Chronos 设施）：
  - `IFF l1_station · OK`
  - reply: `station / neutral / TXP-L1-05 / REG-L1-05-ELINT / FC-L1-05 / crypto OK / conf 1.00 / trigger (none)`
  - 光学页 L4 IDENTITY，EVIDENCE 5 ids，SIGNAL 面板显示真实 IFF 行。

### 19.4 截图 / 验证

- `mockups/v1-hud-transponder-1920.png`（1920×1080：IFF QUERY、L4 IDENTITY、SIGNAL/IDENT IFF 两行、contact FACILITY）
- `V1 HUD SHOT err=0`；headless transponder demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 19.5 未完成 / 边界

1. trigger 为空表示服务未触发规则，UI 显示空；不伪造 trigger。
2. IFF 结果只做最小展示；无 spoof/captured 交互切换（服务状态可产生，UI 会显示 status/identity）。
3. facility 页 TRANSPONDER 行只在有最近应答时显示；当前截图被 overlay 覆盖。
4. 不实现剧情/物理/完整 IFF 权限流；未跑全量 regression。


---

## 20　方案B-14：Shell 接序章场景（task-169）

### 20.1 PreludeScenario boot

- ShellBinder 新增 `PreludeScenario` preload；boot 优先 `prelude.setup({}) → prelude.boot_config()`：
  - 用 boot_config 的 entities（9：apsis/harmattan/ferry/watchtower/deepwell/ceres_2/av_4412/l1_station/chronos）、facility_registry、transponder_service、signal_service；
  - 追加 track_table/story_state/sensor_service/orders；
  - `PreludeScenario` 未 ready 或 boot 失败才回退旧 demo seed，并 warning。
- 实测：`prelude ready=true entities=9 triggers=3 used=true`；contacts=9；默认 selected 旗舰 `[1000] apsis`。
- 不重复建实体：seed 只来自 boot_config；signal target sync 后 9 targets。

### 20.2 光学/识别 + IFF

- IFF QUERY 通过 `binder.transponder_query`；profile_id 与 entity_id 不同时（ceres_2_demo）按 entity_id 反查 profile_id，仍走真实 `transponder_interrogate`。
- 选中 Ceres-2：`IFF ceres_2 · FAILED · faulty`；reply status=no_reply，crypto FAIL，reason=faulty，trigger=`ceres_no_reply`；顶部 `TRIGGER ceres_no_reply · ceres_2 · faulty`；L4 不伪造（TRACK NOT READY）。
- AV-4412：IFF 走 mode_5；显示 entity_type/identity/crypto；不做假 L4。
- 灯语发给 Ceres-2：CODE 切到 `GUSHEN2_REQ`，LIGHT TX 真实失败 `out_of_range`（Ceres 超出灯语范围），RECV/ACK 显示 no_tx；不伪造 ACK。失败 reason/trigger 可在 SIGNAL/IDENT 面板看到。
- 灯语码来自 PreludeScenario merged_codes；signal 配置与场景内容一致。

### 20.3 触发横幅/日志

- transponder reply trigger 或 binder.events 中出现 `ceres_no_reply/av4412_arrival/chronos_unrest` 时，顶栏显示 `TRIGGER ...`；不自动推进剧情。
- 本次 Ceres IFF 真实收到 `ceres_no_reply`；AV/Chronos 触发为条件事件，未由 UI 自动触发，不伪造。

### 20.4 截图 / 验证

- `mockups/v1-hud-prelude-1920.png`（9 contacts，旗舰 [1000] selected，Ceres-2/AV-4412/Chronos 进入）
- `mockups/v1-hud-ceres2-1920.png`（Ceres target、IFF faulty/no_reply、trigger banner、SIGNAL/IDENT、LIGHT out_of_range）
- 均 `V1 HUD SHOT err=0`；headless prelude/ceres demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 20.5 未完成 / 边界

1. 9 实体 contact 名称使用 entity id（Prelude 内容无中文名），非硬编码舰名。
2. Ceres-2 灯语 out_of_range 是真实距离失败；未伪造发送/ACK。
3. AV-4412 mode_5 显示真实 profile 字段；未做完整军用 IFF 权限/交战。
4. 触发横幅只展示已收到事件；不自动推进剧情/物理；未跑全量 regression。


---

## 21　方案B-16：谷神-2 识别/救援链 UI（task-173）

### 21.1 数据 / API

- ShellBinder 新增 `CeresChain`（`framework/content/story_ceres.json`，entity_id=ceres_2）：
  - `ceres_state()` / `ceres_vm()` / `ceres_text(key)` / `ceres_emergency_code()`；
  - `ceres_ingest(input)` / `ceres_advance(action,payload)` / `ceres_rescue(choice)`；
  - 启动日志：`CeresChain ready state=L1 entity=ceres_2 texts=9 code=7700`。
- 阶段：`L1 → L2 → L3 → LIGHT_READ → L4_TYPE → RESCUE_PROMPT → RESCUED/IGNORED → COMPLETE`；文本全部来自 story_ceres 原文。

### 21.2 V1 HUD CERES 面板

- 选中 ceres_2 时光学页显示 CERES 链面板：阶段条、当前阶段原文、EMERGENCY CODE 7700、EVIDENCE/TRIGGERS、REPUTATION、结果行；顶部 trigger 横幅。
- 按钮（真实 chain 输入，不自动完成）：
  - `DATA LINK`：先 `ceres_ingest` 真实传感器/数据链状态，再 `ceres_advance("data_link_l2",...)`；
  - `VIS / ELINT / IFF`：L2 时 `ceres_advance("identify_l3",...)`，不足/阶段错显示 reason；
  - `READ LIGHT`：用真实应急码 `7700` 执行 `read_light`，触发 `ceres_light_read`；
  - `TYPE L4` / `RESCUE PROMPT`：`classify_l4` / `rescue_prompt`，触发 `ceres_rescue_prompt`；
  - `RESCUE` / `IGNORE`：`ceres_rescue`，互斥，进入 RESCUED/IGNORED 并写声望；失败 reason 显示。
- 触发横幅接 `ceres_light_read/ceres_rescue_prompt/ceres_rescued/ceres_ignored`；不自动选择救援。

### 21.3 实测 / 截图

- 真实链实测：`data_link_l2 OK → identify_l3 OK → read_light OK (ceres_light_read) → classify_l4 OK → rescue_prompt OK (ceres_rescue_prompt)`，最终 `state=RESCUE_PROMPT`。
- `mockups/v1-hud-ceres-chain-1920.png`（1920×1080：CERES 面板、阶段、原文、EMERGENCY CODE 7700、EVIDENCE 5/TRIGGERS、DATA LINK…IGNORE 按钮、trigger 横幅）
- `V1 HUD SHOT err=0`；headless ceres_chain demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 21.4 未完成 / 边界

1. 截图为真实 chain 推进到 RESCUE_PROMPT 的样张；RESCUE/IGNORE 未在截图选择，避免自动完成。
2. 文本为 story_ceres 原文；无完整剧情分支/教学高亮。
3. VIS/ELINT/IFF 在本页作为链输入（真实 `identify_l3`）；无完整传感器证据 UI。
4. 不写 world/物理/存档；未跑全量 regression。


---

## 22　方案B-17：Chronos 通信/行动 UI（task-175）

### 22.1 数据 / API

- ShellBinder 新增 `ChronosChain`（`framework/content/story_chronos.json`，entity_id=chronos，绑定 chronos/l1_station 目标逻辑）：
  - `chronos_state()` / `chronos_vm()` / `chronos_text(key)` / `chronos_actions()` / `chronos_trust()`；
  - `chronos_advance(action,payload)`（接受/拒绝/blackbox/telemetry/window_end 均真实 chain）；
  - 启动：`ChronosChain ready state=WAIT_DOCK entity=chronos texts=9 trust=0`。
- 阶段：`WAIT_DOCK → PORT_COMM → ACTION_EVAC → PRIVATE_COMM → CHOICE → ACTIONS → WINDOW_END → COMPLETE`；文本全部来自 story_chronos 原文。

### 22.2 CHRONOS 面板

- 右栏 `CHRONOS / 行动` 或 `DSH_V1_VIEW=chronos` 打开 V1 自绘 overlay；显示阶段条、当前状态原文、TRUST/STATE、FLAGS、REPUTATION、TRIGGERS、WINDOW。
- 按钮：PORT COMM、EVAC、PRIVATE、ACCEPT、REJECT、OPEN ACTIONS、BLACKBOX、TELEMETRY、WINDOW END；全部映射真实 `chronos_advance`。
  - ACCEPT/REJECT 互斥；未接受时 blackbox/telemetry/evidence 返回 `requires_accept`；
  - 失败 reason 显示；不自动完成、不自动开 4412。
- `chronos_comms_lines` 追加真实文本：
  - `[Chronos 港务 至 ID13]-[RDO]-[chronos.port_rdo]`
  - `[副官 至 指挥官]-[PRIVATE]-[chronos.private_comm]`
  - COMMS 页面 MESSAGE STREAM 下方显示 `CHRONOS CHAIN COMMS`。

### 22.3 实测 / 截图

- 真实链：`port_comm → action_evac → private_comm → choose_accept → open_actions → blackbox → telemetry`，最终 `state=ACTIONS · trust=4`；触发 `chronos_telemetry`；未执行 WINDOW END/4412。
- `mockups/v1-hud-chronos-1920.png`（1920×1080：阶段、原文、TRUST 4/trusted/choice accept、FLAGS/REPUTATION/TRIGGERS、WINDOW OPEN、九按钮、trigger 横幅）
- `V1 HUD SHOT err=0`；headless chronos demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 22.4 未完成 / 边界

1. L1/chonros 选中后的按钮点击输入/自动弹面板为最小路径（本页通过 CHRONOS 按钮/DSH_V1_VIEW 打开）。
2. 接受/拒绝分支只写 trust/reputation/flags/证据，不接完整剧情分支/未来建议。
3. WINDOW END 未在截图执行，避免自动开 4412；不写 world/物理/存档。
4. 未跑全量 regression。


---

## 23　方案B-18：AV-4412 对峙/谈判 UI（task-178）

### 23.1 数据 / API

- ShellBinder 新增 `AV4412Chain`（`framework/content/story_av4412.json`，entity=av_4412）：
  - `av4412_state/vm/text/actions/update_orbit/advance`；
  - 启动：`AV4412Chain ready state=ORBIT_DEPARTURE entity=av_4412 texts=17 threat=0 trust=0`。
- 阶段：ORBIT_DEPARTURE→WINDOW_OPEN→EARLY_RADAR/PASSIVE_CONTACT→COMMS→NEGOTIATION→STRONG/STANDARD/QUESTION/RETREAT→RESOLUTION→REPORT_HANDOFF；原文 story_av4412，TBD key 保持 `TBD`。

### 23.2 V1 HUD AV-4412 面板

- 右栏 `AV-4412 / 对峙` 或 `DSH_V1_VIEW=av4412` 打开；状态条、当前原文、四选项原文（strong/standard/question/retreat）、TBD keys 明示。
- 按钮：TRACK/WINDOW/ADVANCE + STRONG/STANDARD/QUESTION/RETREAT；全部真实 `av4412_advance`；退让不足劝阻返回 `missing_retreat_warnings` reason。
- TRACK 使用真实 session 快照 av_4412 pos/vel + 当前 t/window/radar `update_orbit`；WINDOW 真实 `window_open`；ADVANCE 按状态推进。
- STRONG 实测写 `roe_tight=true`、`fire_control_illumination=true`、`auto_fire=false`；不自动开火。
- 显示 THREAT/TRUST/REPUTATION/FLAGS/TRIGGERS、TRACK/WINDOW/DETECTED、EVENTS/COMMS；ROE TIGHT 行。
- 通信日志追加 `[AV-4412 至 APSIS]-[LD]-[opening]`、`[APSIS 至 AV-4412]-[LD]-[option]`；COMMS 页 AV-4412 COMMS。

### 23.3 实测 / 截图

- 真实链：`update_orbit OK → window_open OK → early_radar OK（雷达为 ON）→ comms OK → negotiation OK → strong OK`；最终 `state=STRONG · threat=2 · trigger av4412_strong · ROE TIGHT/fire_control_illumination · auto_fire=false`；未 resolve/handoff。
- `mockups/v1-hud-av4412-1920.png`（1920×1080：状态条、原文、四选项、TBD keys、TRACK/WINDOW、THREAT/TRUST/FLAGS/TRIGGERS、ROE TIGHT、七按钮、trigger 横幅）
- `V1 HUD SHOT err=0`；headless av4412 demo 一次；`v1_hud.gd/shell_binder.gd --check-only` 通过。

### 23.4 未完成 / 边界

1. 截图选 STRONG 后状态为 STRONG，四选项按钮仍展示（非全部可执行）。
2. TBD 文本只显示 TBD/key，不生成假台词；报告/结局/handoff 未执行。
3. 轨道来自 session snapshot 的 av_4412 真实 pos/vel；不写物理/世界。
4. 不实现完整剧情分支/结局/物理；未跑全量 regression。
