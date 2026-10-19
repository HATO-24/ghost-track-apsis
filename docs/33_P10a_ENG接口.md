# P10a ENG 接口（目标动作 / 图层 / 平面地图 / AV-4412 对接）

> 任务：task-43（P10a-ENG 第二批交互后端）。工作区 `D:\GHOST TRACK_APSIS`。
> 改动：`state.gd`、`main.gd`、`plot.gd`、两份 `scenario_l1.json`、`docs/`、`mockups/`；
> 未改 hud/intro/sensor_model（sensor_model 现有架数据已够用）。未 commit。
> 第一批接口见 [`32_P9a_ENG接口.md`](32_P9a_ENG接口.md)。

---

## 1　目标动作 API（state.gd）

### 1.1 等级与动作目录

`target_actions(track_id) -> Array`，按该批号当前识别等级返回全部动作（含不可用原因）：

| 动作 id | 标签 | 最低等级 | 实现状态 |
| --- | --- | --- | --- |
| `crossfix` | 交叉定位 | L1 | 已实现（基于现有被动方位，写状态/日志） |
| `radar_illum` | 雷达照射识别 | L1 | 已实现（命令哈马丹 YW-R9 开机；受桅杆/EMCON 限制） |
| `model_ident` | 型号识别 | L2 | 已实现（写该批号分类确认状态） |
| `radar_track` | 雷达跟踪 | L3 | 已实现（写跟踪状态；TWS 状态机第二批） |
| `iff_query` | IFF 问答 | L3 | 已实现（写应答状态；无应答不能自动判敌） |
| `optical_channel` | 光学通道 | L3 | 已实现（调用 start_optical_track） |
| `ir_channel` | 红外通道 | L3 | 已实现（调用 start_ir_track） |
| `fire_control` | 火控解算 | L4 | **unsupported**：尚无武器系统（第二批） |
| `missile_path` | 导弹路径解算 | L4 | **unsupported**：尚无导弹系统（第二批） |
| `armed_standby` | 武装待命 | L4 | **unsupported**：尚无武器系统（第二批） |

每个动作返回：

```json
{ "id": "radar_track", "label": "雷达跟踪", "min_level": 3, "level": 3,
  "available": true, "unsupported": false, "reason": "" }
```

- 等级不足：`available=false`、`reason="需 L4 识别（当前 L3）"`。
- 未实现：`unsupported=true`、`reason="未实现：…（第二批）"`。
- 光学/红外还要求传感器可用且桅杆伸出；否则 `available=false` 并给出原因。

### 1.2 执行

`perform_target_action(track_id, action) -> Dictionary`：

- 成功：`{ok:true, status:"ok", track_id, action, message, level, actions}`，并写日志 `ACTION` / flags。
- 等级不足：`{ok:false, status:"unavailable", message:"需 Lx…"}`。
- 未实现：`{ok:false, status:"unsupported", message:"未实现：…"}`。
- 未知目标/动作：`{ok:false, status:"error"}`。

### 1.3 右键菜单与 HUD 接口

- `plot.pick_track(p) -> String`：右键屏幕坐标命中接触（3D 用投影、平面用 `_p2`；14–18px 半径；L1 取 300 km 方位线中点）。
- `state.open_target_menu(track_id)`：设置并返回动作列表，同时 `select_track_by_id()`。
  状态字段：`target_menu_open` / `target_menu_track` / `target_menu_actions` / `target_menu_hud_handled`。
- `main.gd` 右键流程：右键 → `plot.pick_track` → `_open_target_menu(id)`；若 HUD 实现
  `open_target_menu(track_id, actions)` 则调用并置 `target_menu_hud_handled=true`；否则由 plot 绘制
  fallback 菜单（仅在后端/HUD 未接管时显示）。右键不进入左键拖拽状态。
- `state.close_target_menu()` 关闭。

## 2　光学 / 红外通道（state.gd）

| API | 说明 |
| --- | --- |
| `start_optical_track(track_id, elapsed_s=0.0)` | 光学凝视，需 L2+ 且有可用光学传感器；默认 6 s 锁定 |
| `start_ir_track(track_id, elapsed_s=0.0)` | 红外跟踪，需 L2+ 且有可用红外传感器；默认 4 s 锁定 |
| `stop_track()` | 停止全部通道 |
| `channel_status(track_id="")` | 返回 `{track_id, channels:{optical:{status,progress,elapsed_s,required_s,...}}}`；空参返回全部 |

- 状态：`running → locked`（`status`）、`progress` 0–1、`elapsed_s`/`required_s`；目标 track 写
  `optical_locked`/`ir_locked` 并写日志 `CHANNEL`。
- 数据在 `state.track_channels`；plot 画目标环 + `OPT/IR 跟踪 n%`，HUD 可读 `channel_status()`。

## 3　图层显隐（state.gd + plot.gd）

- `set_layer_visible(name, on) -> bool`、`is_layer_visible(name)`、`toggle_layer(name)`。
- 键：`contacts`（接触/符号）、`labels`（标签）、`predictions`（历史/预测/轨道）、`radar`（传感器层）、
  `stations`（站点/基准标记）、`grid`（网格）；别名 `contact/track/label/prediction/orbit/sensor/station/grid`。
- plot 按 `_layer_on(key)` 跳过对应绘制；隐藏接触/标签/预测、雷达层、站点、网格任意多类。

## 4　平面地图坐标（plot.gd）

- L1 仅方位端点：改为 `_p2(Vector3(sin(b), cos(b), 0) * 450 km)`，扇区顶点同样 map space。
- 9002 无威胁目标方位端点：`_p2(... * 315 km)`。
- 近场编队框：按 cluster 接触的 `_p2` 地图位置外接矩形（随 yaw/zoom 旋转缩放），符号画在各自 map 位置，
  标签引线从符号拉到框外侧（不再把符号钉在固定屏幕像素）。
- 接触符号/标签已用 `_p2`/`_p3`；标签只是引线，不是坐标。

## 5　AV-4412 与 Chronos 对接（EVACUATE 后）

- 触发：`choose_ending("EVACUATE")`；或撤人任务完成（`civilians_evacuated`）。
- 状态字段：
  - `state.av4412_dock = {active, state: "approach"|"docked", target:"Chronos", started_t, docked_t, reason}`；
  - track `2001` 写 `dock_target="Chronos"`、`dock_state="approach"|"docked"`；
  - flags：`av4412_dock`、`av4412_docked`、`chronos_handover`；
  - 日志/通信（`DOCK`）；`report_text` 追加“后续：2001 … 已与 Chronos 对接（…）”；
  - `end_summary.av4412_dock` 可读。
- 时序：`approach` 后 `story.av4412_dock.approach_after_s`（默认 45 s）转 `docked`；
  `force_av4412_dock()` / `av4412_dock_state()` 供测试/DSH 钩子。
- 文案在 scenario `story.av4412_dock`（approach_text/docked_text/report_line）两份数据一致。

## 6　DSH 测试钩子（main.gd）

| 环境变量 | 作用 |
| --- | --- |
| `DSH_RCLICK=<batch>` | 按批号找屏幕位置，走 `plot.pick_track` → 打开目标菜单；打印动作清单 |
| `DSH_TARGET_ACTION=<batch>:<action>` | 执行目标动作并打印 status/ok/message |
| `DSH_LAYER=<name>:<0|1>` | 设置图层显隐并打印 |
| `DSH_OPTICAL=<batch>` | 以 5 s 已用时间启动光学通道并刷新，打印 channel_status |
| `DSH_IR=<batch>` | 同上（红外，2 s） |
| `DSH_DOCK=1` | 强制 AV-4412 进入对接并打印状态 |

旧钩子（DSH_SHOT/DSH_SCENE/DSH_SIM/DSH_CLOCK/DSH_SELECT/DSH_MAST 等）未变。

## 7　测试 / 产物

- `mockups/p10a-rclick.png`：右键 2001，选中括号 + 目标动作 fallback 菜单（10 项，L3 可用 7 项，L4 三项标注不可用）。
- `mockups/p10a-optical.png`：2001 光学通道 83% 进度环。
- `mockups/p10a-dock.png`：`DSH_DOCK=1`，2001 对接 Chronos（状态/标签）。
- `mockups/p10a-layers.png`：`DSH_LAYER=contacts:0` 隐藏接触层。
- 日志：`mockups/p10a-tests.log`（动作清单、通道状态、图层、对接、报告文本）。
- probe：等级 2001=L3；动作 available/unsupported 正确；crossfix/radar_illum/optical 执行 ok；
  fire_control 返回 unsupported；通道 6 s 锁定；图层切换成功；EVACUATE 后 dock=approach/45 s 后 docked；
  `report_text` 含“对接”；end_summary 含 av4412_dock。
- headless：全部脚本 parse OK；main.tscn capture 四图 `err=0`。

## 8　未完成（按范围明确不做）

- 球形雷达范围 / 真实 TWS 状态机、教学门控、完整损管、态势回放。
- 火控/导弹/武装待命真实功能（当前 unsupported，不伪造）。
- 右键菜单的正式 HUD 视觉/键位（HUD 未改；ENG 提供 `open_target_menu` 接口 + plot fallback）。
- 绝对轨道根数、储罐/空间站线条模型（前一批已列第二批）。
