# P9a ENG 接口（窗口 / 相机 / 选中舰 / 桅杆 / 并行 / 导航）

> 任务：task-41（P9a-ENG 反馈第一批）。工作区 `D:\GHOST TRACK_APSIS`。
> 改动范围：`main.gd`、`plot.gd`、`state.gd`、`demo_director.gd`、两份 `scenario_l1.json`、`docs/`、`mockups/`；
> **未改 hud/intro**（UI 侧由 task-40 处理）。未 commit。
> 反馈台账见 [`31_Demo反馈修复台账.md`](31_Demo反馈修复台账.md)。

---

## 1　窗口适配（main.gd）

- 渲染：`SubViewport` 固定 **1920×1080**；`SubViewportContainer` 按窗口可用区域计算 **16:9 letterbox** 矩形并居中。
  任意缩放/最大化时不拉伸：`sc = min(win.x/1920, win.y/1080)`，容器尺寸 = 1920·sc × 1080·sc。
- 重排：`_layout_viewport()` 在 `_ready`、`NOTIFICATION_RESIZED`、`resized`、每帧窗口尺寸变化时调用。
- 鼠标：`_mouse_to_base(p) = (p - _vp_rect.position) * (1920×1080 / _vp_rect.size)`；letterbox 黑边不接收点击。
- 快捷键：
  - **F11**：独占全屏 ↔ 窗口（`Window.MODE_EXCLUSIVE_FULLSCREEN`），退出时恢复 1600×900 居中。
  - **F10**：无边框窗口 ↔ 有边框窗口。
  - 默认窗口 1600×900（保持）。
- 自检钩子：`DSH_WINDOW_TEST=1` 启动后打印 letterbox 矩形、F10/F11 结果与相机轴测试。

实测（`DSH_WINDOW_TEST=1`）：

```
WIN TEST size=(1600, 900) rect=(0,0,1600,900) scale=(0.8333,0.8333)
WIN TEST non16x9 size=(1280, 900) rect=(0,90,1280,720) scale=(0.6667,0.6667)  # 上下各 90px 黑边
WIN TEST F10 borderless=true
WIN TEST F11 mode=4 (EXCLUSIVE_FULLSCREEN) size=(1920,1080) rect 全屏
CAM TEST yaw_delta=... pitch_delta=0        # 横拖只改 yaw
CAM TEST pitch_delta=0.42 yaw_delta=0        # 竖拖只改 pitch
CAM TEST roll_effective=true                 # Q/E 横滚生效
```

## 2　相机轴（plot.gd）

- `rotate_map(dx, dy)`：
  - 3D：横拖 **只改 yaw**；竖拖 **只改 pitch**，限幅 `[-8°, +78°]`（不再 `fposmod` 翻面）；
    上拖 = 向前压（pitch 降低），下拖 = 抬高。
  - 压平：横拖只改 `yaw2d`，竖拖不改变指向。
  - 每次改变同步 `yaw2d = yaw3d`，保证 3D↔压平切换指向连续；`set_planar`/`force_planar` 保留 pitch。
- `main.gd`：**Q/E** 先自动 `toggle_roll_unlock()` 再 `rotate_roll(±5°)`，不再需要先按 Z 解锁。
- 相关常量：`PITCH_MIN/PITCH_MAX`（-8/78）、`yaw3d/yaw2d/pitch/roll3d`。

## 3　选中舰 / 基准 / 三维方位 / 轨道读数（state.gd + plot.gd）

- 基准策略：**基准锁本舰**；选中其他舰只读取其相对状态，不改变 datum（plot 右侧 `DATUM` 行与 `state.datum_note()` 明示）。
- `state.selected_track()` → 当前选中 track；`state.selected_info()` 返回：
  `id/batch/name/own/identity/threat/az_deg/el_deg/range_km/speed_mps/closing_mps/orbit`。
- `state.orbit_readout(id)`：以本舰为原点的**相对轨道读数**（a≈range、T≈2πr/vt、i≈相对轨道面倾角），
  明确标注“非地心根数”；绝对轨道根数需外部星历（第二批）。
- 显示位置：plot 右侧（光学窗/命令队列下方）画 `[batch] name · 身份 · 威胁` / `AZ/EL/RNG/Vc` / `相对轨道…` / `DATUM`；
  HUD 右侧面板由 task-40 读取上述字段（HUD 未在本任务改动）。

## 4　传感器桅杆（state.gd）

- 字段：`mast_deployed: {ship_id: bool}`（默认全部伸出）、`mast_note`。
- 方法：
  - `is_mast_deployed(ship_id) -> bool`
  - `set_mast(ship_id, deployed) -> bool` / `toggle_mast(ship_id) -> bool`
- 行为：桅杆收起时 `_plan_tick` 整架强制关断、`_sensor_is_on` 返回 false、`set_sensor` 拒绝并写日志；
  伸出后恢复脚本时序（清掉手动覆盖）。日志标签 `MAST`。
- 显示：plot 本舰旁 `MAST DOWN · 传感器架不可用`，传感器层标签追加“桅杆收起”。
- 完整架：`_sync_sensor_view` 返回 `SensorModel.sensor_rack(ship)` 全部模块（不截断）；滚动/翻页属 HUD UI（task-40）。

## 5　副官并行（state.gd）

- `ack_adjutant(choice)` 不再一次性关闭：选择 telemetry/blackbox/evacuate 后 **申请保持打开**，可连续选择；
  `decline` 才关闭。新增 `_adjutant_choices` 记录已选项。
- 占用规则：遥测（port_telemetry）与 ELINT 是远程/被动，**不占穿梭机**，可与黑匣子/撤人并行；
  黑匣子与撤人共享穿梭机（`_shuttle_busy`），互斥。
- 任务时长（scenario `story.evidence_tasks`）：遥测 30s、黑匣子 75s、ELINT 45s、撤人 60s；
  决策时刻 `decision_t=300s`，T+21 起可完成 2 项证据（实测 T+76 已 2/3）。

## 6　导航页（state.gd + scenario）

- 阶段由 prelude 提供，**兼容现有 prelude API**：
  `navigation_open()` / `navigation_step()`（0 目的地 / 1 变轨窗口 / 2 点火确认 / 3 航行）/
  `navigation_stage()` / `navigation_steps()` / `navigation_tutorial()`。
- scenario 新增 `story.navigation`（title/body/tutorial/stages）；prelude 的 routes/windows/dv/通信保持不变。
- 教学文案：错误目的地/窗口返回提示并停留当前步骤；确认点火扣 Δv 后进入“航行”阶段。
- UI 绑定建议（task-40）：按 `navigation_step()` 画四步进度，用 `prelude_data.routes/windows` 出选项，
  按钮调 `prelude_choose_route/window/confirm`；长按/解锁等交互由 UI 决定。

## 7　地图雷达/叠加语义（plot.gd）

- 3D 的**雷达扇形扫描**与**示意 EMIT 圆**已删除：视觉未建模，不再画假扇形/圆。
- 替代文本：`EMIT 暴露 · 主动传感器开机`（开机即暴露；若被截获追加“已被 ELINT 截获”）+
  “截获半径/扫描范围未建模（第二批 TWS）”。
- ELINT 点名：保留“对方截获我方发射”的虚线，删除假截获半径圆，标注“示意连线，范围未建模”。
- 平面图 EMIT 环保留（按 `elint_range_km` 真实比例），标签改为“EMIT 暴露 · 对方 ELINT 截获半径 X km（按比例）”。
- 图例新增“标记三层：身份（符号）· L级（L1–L4 识别等级）· 威胁（处置优先级，非身份）”，
  用于解释 AV-4412 的三角/等级徽标/威胁字三层标记；球体雷达范围/TWS 属第二批。
- 局部小图环标注“参考环 100/200/400 km”（真实距离标尺，不是雷达范围）。

## 8　demo / scenario / 测试

- `demo_director.gd`：航行段显示 `navigation_stage()` 字幕；新增桅杆收放演示、选中舰读数演示、
  副官“遥测 + 黑匣子并行”演示；不改现有 DSH 截图钩子。
- scenario 两份（`data/` 与 `game_v15/data/`）逐字节一致；新增 `story.navigation`。
- 截图：`mockups/p9a-map.png`（选中 2001 + 相对轨道读数）、`p9a-mast.png`（桅杆收起）、
  `p9a-cam.png`（Yaw/Pitch/Roll 相机）。日志：`mockups/p9a-tests.log`。
- headless：全脚本 parse OK；`--headless --quit` MAIN READY 无报错；capture 三图 `err=0`。
- 状态 probe：导航阶段、桅杆阻断/恢复、副官并行与穿梭机互斥、T+76 证据 2/3、selected_info/orbit_readout 均通过。

## 9　第二批（未实现，不硬造）

1. 地图右键分级操作菜单 + 元素隐藏。
2. 可见光/红外通道完整功能与弹窗。
3. 球形雷达范围、雷达凝视/跟踪状态机、真实 TWS。
4. 储罐/空间站/舰船空间线条模型。
5. 态势回放。
6. 教学门控（交叉比对/IFF 问答由玩家完成）与损管完整界面。
