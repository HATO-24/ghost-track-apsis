# R5-OPT-DOCK-BRIDGE-1 · 光学/IR + 对接接入 V17 bridge/state

> 任务 R5-OPT-DOCK-BRIDGE-1（task-89）。工程 `game_v17`。
> 模型：`framework/sim/optical_ir_channel.gd`（`V2OpticalIRChannel`，VIS/IR）、
> `framework/sim/docking_controller.gd`（`V2DockingController`）。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读 VM / 显式 API）。
> **不自动写 world/physics/TrackTable/V15；不接 HUD/plot；不 commit。**
> 按任务要求只做最小 probe（PASS=128/0），未跑全量回归。

## 1　定位与不变量

- bridge 启动创建 `V2OpticalIRChannel`（VIS + IR 双通道）与 `V2DockingController`
  （默认端口样例：chronos-dock-a/b、chronos-berth-1、harmattan-port）。
- 开关（默认 on）：`V17_OPTICAL_IR=on|off`、`V17_DOCKING=on|off`；
  `off`/`0` 不创建实例，view 为空、显式 API 返回 `ok=false`；失败不阻塞 bridge。
- **不自动**：光学不自动 aim/step（sync 只刷新只读 VM）；对接不自动 update，需调用方喂
  `rel/attitude`。两者均不写 world/physics/TrackTable/V15、不接 HUD/plot。
- 模型边界沿用各自文档：光学 `level_support` VIS≤L3/IR≤L1、identity=unknown、无真实姿态
  （默认 LOS）；对接不落实体、不生成推力，`authoritative=false`。

## 2　输入

- 光学 snapshot（bridge 构造，`optical_ir_snapshot()`）：observer = 本舰（L1 板原点）；
  targets 取 `world.vm_contacts()` 中非 bearing-only、range>0、有 entity_id 的行，
  由 `range_km/bearing_deg/alt` 转为 `pos_km`（`make_target`）；env `sun_illum=1/shadow=false/los=true`。
- 对接输入由调用方提供（不取自 world，避免落实体）：
  ```gdscript
  rel = {"dr": [x,y,z], "dv": [vx,vy,vz]}   # km, km/s；target - chaser（LVLH）
  或   = [x,y,z,vx,vy,vz]
  attitude = {"chaser_port_axis": [x,y,z]}  # 可选；未提供时不能 docked
  ```

## 3　bridge API（只读 VM / 显式操作）

| API / 字段 | 说明 |
| --- | --- |
| `optical_ir` / `docking` | 模型实例（off/失败 null） |
| `optical_ir_enabled` / `optical_ir_ready` | 开关/就绪；`docking_enabled` / `docking_ready` 同理 |
| `optical_ir_view()` | `vm_optical_ir()`：`schema=optical_ir.v1、mode=shadow、authoritative=false、enabled、t、sensors{optical,ir}、channels[]、by_status、events、warnings、summary{channels,locked,staring,acquiring,lost,optical_l3,ir_l1,writes_*:false}、writes{track_table:false,v15:false}` |
| `optical_ir_summary()` | 上述 summary |
| `optical_ir_point(target_id)` | 双通道 `aim_at`（显式；不 step） |
| `optical_ir_start(kind, target_id, opts={})` | 启动 `kind=optical|ir` 通道 |
| `optical_ir_step(dt)` | 用 bridge snapshot 推进通道，返回 VM（显式） |
| `optical_ir_stop(kind, target_id="")` | 停止通道 |
| `docking_view()` | `vm()`：`schema=v17_docking.v1、state、state_order、t、target_port_id/target_port、ports[]（v17_docking_port.v1）、config、last（v17_docking_snapshot.v1）、events、hold_requested/hold_reason/failure_reason/docked_t/undocked_t、writes{world,physics,track_table,v15=false}、authoritative=false` |
| `docking_select_port(port_id)` | 选择目标端口（默认样例；不落实体） |
| `docking_update(rel, attitude={}, dt=0)` | 相对状态/姿态驱动状态机；返回 snapshot（含 guidance/corridor/docking/align/final/hard_fail/warnings） |
| `docking_hold/resume/abort/reset` | 显式控制；终态需 reset |
| `bridge_state()` | 增 `optical_ir/optical_ir_summary/optical_ir_ready/optical_ir_enabled/docking/docking_ready/docking_enabled/docking_update_last` |

光学通道导出字段（关键）：`channel/target_id/status/progress/stare_s/required_s/
boresight_deg/boresight_el_deg/bearing_deg/elevation_deg/off_axis_deg/slant_range_km/
snr_db/min_snr_db/n_px/smear_px/detected/locked/classify_ok/level_support/level_cap/
classification/identity=unknown/reason/failures`（状态 idle/acquiring/staring/locked/lost）。

## 4　state API（不接 HUD）

| 字段 / 方法 | 说明 |
| --- | --- |
| `fw_optical_ir` | bridge optical VM 深拷贝；`fw_sync` 刷新 |
| `fw_docking` | bridge docking VM 深拷贝；`fw_sync` 刷新 |
| `fw_optical_ir_view()` / `fw_docking_view()` | getter |
| `fw_optical_ir_point/start/step/stop` | 包装 bridge 显式 API；调用后自动 `_fw_pull()` 刷新字段 |
| `fw_docking_select_port/update/hold/resume/abort/reset` | 同上 |
| `fw_bridge_state()` | 增 `optical_ir`/`docking` |
| 旧字段 | `fw_sensor_shadow/fw_info_warfare/fw_physics*/fw_nav*/fw_damage*` 等全部不变 |

off 时 `fw_optical_ir`/`fw_docking` 为空；显式 API 返回 `{ok:false,reason:"…not_ready"}`。

## 5　最小验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_optical_docking_probe.gd
# V17 OPTICAL DOCKING PROBE RESULT: PASS=128 FAIL=0（exit 0，只跑一次）
```

覆盖：
1. boot：optical/docking ready、schema/sensors/ports=4、writes=false、bridge_state 字段；
2. 光学：point/start(optical+ir)/多次 step → channels=2、status={optical:locked, ir:locked}、
   summary/writes_v15=false；stop 后 channels=0；
3. 对接：select chronos-dock-a、远距 update(200 km)→guidance、近距 preview/update(0.1 km)、
   hold/resume/reset；`docking_update_last` 缓存；writes 全 false；
4. state：fw_optical_ir/fw_docking 刷新、state 包装 API、旧 info/sensor 字段不变、
   **V15 tracks/等级/身份/clock 不变**；
5. off 降级：V17_OPTICAL_IR=off + V17_DOCKING=off → view 空/API ok=false/state 空、不崩溃；
6. JSON：optical/docking/fw_bridge_state 可回读。

## 6　边界 / 未完成

- 光学/对接均为 **shadow 只读/显式**；不自动步进、不写 world/physics/TrackTable/V15、不接 HUD/plot。
- 光学：无真实姿态/云台物理（默认 LOS/姿态）；VIS 分类仅 L3、IR 仅 L1；测距恒 -1。
- 对接：仅模型状态机/制导建议，不落实体、不执行推力/姿态；`rel/attitude` 由调用方提供；
  docked 需显式 chaser 端口轴，缺失不伪造。
- 环境开关默认 on；失败不阻塞 bridge（记录 warnings）。
- 未跑全量回归；未 commit。
