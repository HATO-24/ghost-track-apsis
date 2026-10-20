# 阶段2-TRANSIT-SENSOR-1/2 · 转场传感器数据层（雷达/IFF 控制）

> task-103（数据层）→ **task-107（TRANSIT-CONTROLS-1：雷达/EMCON + 真实 IFF）**。
> 工程 `game_v17`。只改三个文件：
> `scripts/transit_sensors.gd`、`tests/transit_sensors_probe.gd`、`docs/transit_sensors.md`。
> 未改 `transit.gd`/`transit_hud.gd`/`project.godot`、旧 HUD/state/bridge/core/sim；
> 未接 UI；未写 world/TrackTable/V15；未 commit。

## 1　目标与数据流

```
scenario_transit_l4_l1.json
  ├─ 5 舰 entities（apsis 1000 / harmattan 1001 / ferry 1002 / watchtower 1003 / deepwell 1004）
  └─ 4 港 ports（l4_02_hammer 3000；l1_meridian_05 3100、l1_anchorage_02 3101、l1_drydock_01 3102）
          │
          ▼
transfer_planner.plan()（静态缓存一次）
  timeline[]（t_s / pos_rot_km / vel_rot_kmps）
  fleet[]（offset_km / offset_kmps）
  source/target port states
          │  同一 bary_rot 帧；按 t/tof 线性插值 + 舰队偏移
          ▼
transit_sensors.gd（本层）
  observer ship / target ship或port → snapshot(observer, targets, env)
  set_radar_enabled / set_emcon / iff_query
          │
          ├──▶ V2SensorAuthority（shadow）
          │      ├─ YW-R9 球形雷达 → TWS 六态/接触等级 + exposure
          │      └─ optical_ir 后端（V2OpticalIRChannel）→ VIS/IR：FOV/IFOV/遮挡/光照/SNR/凝视/锁定/失败
          │
          └──▶ V2InformationWarfare（MK-12）
                 └─ interrogate_iff → friend / unknown / no_reply / faulty / out_of_range；不产生位置/接触
          │
          ▼
JSON VM：contacts / channels / optical / levels / events / warnings
          radar_enabled / emcon / exposure / radar / iff / ships / ports / targets
          writes={track_table:false, v15:false}
```

数据源全部只读；本层只推进自己的 `t`，不修改 `transit.gd` 的本地时间、场景、plan 或 V15。

## 2　坐标 / 位置生成

- 帧：**bary_rot（km, km/s, s）**，与 `transfer_planner` 输出一致；本层不换帧。
- 基准位置：`timeline` 按 `t/tof_s` 线性插值 `pos_rot_km/vel_rot_kmps`。
- 舰位：`base + fleet.offset_km`；速度使用共享 `base_vel`（`offset_kmps` 只作为数据元数据，不叠加相对速度；避免编队 1 m/s 差在 1 µrad IFOV 下被误判为拖影模糊）。
- 港位：
  - L4 源港：`plan.source.pos_rot_km`；
  - L1 三港：`plan.target.pos_rot_km + (scenario_port.offset_km − l1_meridian_05.offset_km)`。
- `step(dt)` 推进本地时间并 clamp 到 `tof_s`；`seek(t_s)` 直接定位（测试/将来 HUD 拖动时间轴用），
  `seek` 后建议再 `step(6.0)` 触发一次雷达扫描。
- 阶段：`departure`（t≤1）、`cruise`、`arrival`（t≥tof−1）。

## 3　API

```gdscript
const TransitSensors := preload("res://scripts/transit_sensors.gd")
var ts = TransitSensors.new({"observer_id": "harmattan", "target_id": "apsis"})

ts.step(dt: float) -> Dictionary          # 推进并返回 VM（同 vm()）
ts.vm() -> Dictionary                     # 当前只读 VM（无需先 step 即可看到 set_target 结果）
ts.select_ship(id: String) -> Dictionary  # 切换 observer；返回 {ok, observer, fallbacks, warnings}
ts.set_target(id: String) -> Dictionary   # 选目标；已有光学通道随目标重定向
ts.start_optical(kind: String, target: String, opts := {}) -> Dictionary
                                              # kind=optical|ir；opts 透传 authority（如 backend/boresight_deg）
ts.stop_optical(kind := "", target := "") -> Dictionary  # 空=全部停止
ts.seek(t_s: float) -> Dictionary         # 直接定位时间（只读测试/时间轴）
ts.set_radar_enabled(on: bool) -> Dictionary  # 真雷达/EMCON：on→接触+暴露；off→无主动接触
ts.set_emcon(on: bool) -> Dictionary          # 显式 EMCON（on 等价雷达关闭）
ts.iff_query(target_id: String) -> Dictionary # 真 IFF；friend/unknown/no_reply/faulty/out_of_range
ts.iff_state(target_id := "") -> Dictionary   # 最近/按目标 IFF 结果
ts.summary() -> Dictionary
ts.to_dict() -> Dictionary
```

- `select_ship`：5 舰均可选；observer 缺能力时数据层补 authority 默认挂载并写
  `CAPABILITY FALLBACK` warning，返回 `fallbacks` 列表（不冒充 V15 权威）。
- `start_optical`：目标必须是当前 observer 之外的有效舰/港；未知目标/非法 kind 返回
  `{ok:false,reason:...}`。默认 `optical_ir` 后端，`opts.backend="legacy"` 可回退。
- `stop_optical`：无匹配通道返回 `no_matching_channel`。
- `set_radar_enabled(false)` 同时进入 EMCON：authority 雷达/TWS 停、`exposure.exposed=false`、
  VM contacts 置空；`set_radar_enabled(true)` 恢复，需再 `step()` 产生新扫描/暴露。
- `iff_query`：真实 `V2InformationWarfare.interrogate_iff`（MK-12，2,000 km）；返回
  `status ∈ friend|unknown|no_reply|faulty|out_of_range|blocked|cooldown`；
  `identity` 只可能 friend/unknown，`hostile=false`、`never_hostile=true`、
  `produces_contact=false`、`level_support=0`；EMCON 下真实返回 `blocked`。
- 所有方法不写 world/V15；无 `apply`/`commit` API。

## 4　VM 字段（schema `transit_sensor_data.v1`，mode=`shadow`）

| 字段 | 说明 |
| --- | --- |
| `t` / `dt` / `step_count` / `tof_s` / `progress` / `phase` | 时间轴 |
| `observer_ship` / `observer` | 当前观测舰 id/name/batch/pos/vel |
| `selected_target` | 当前目标 id |
| `ships[5]` | id/batch/name/role/class/side/pos/vel/range/observer/selected/loadout_fallbacks |
| `ports[4]` | id/batch/name/lpoint/port_id/status/pos/vel/range/selected |
| `targets[8]` | 非 observer 4 舰 + 4 港；level/level_support/contact_level/optical_level/range/visible/vis_status/ir_status/reason |
| `contacts` | authority advisory contacts（含 target_id/level/level_support/range/bearing/identity/quality/level_evidence），附加 kind/name/selected |
| `channels` | authority 全部通道：`radar.tws` + `optical` + `ir`；含 status/progress/FOV/IFOV/off-axis/occlusion/SNR/level |
| `optical` | `backend` / `available_backends` / `selected_target` / `vis` / `ir` / `channels`(仅 optical|ir) / `summary` |
| `optical.vis` / `optical.ir` | 选中目标通道：status/level/reason/fov_deg/ifov_urad/snr_db/occluded/boresight/off_axis/n_px/... |
| `levels` | `schema=transit_sensor_levels.v1`；`by_target{level,contact_level,optical_level,range_km,reason}`、`counts{0..4}`、`max_level`、`labels` |
| `radar_enabled` / `emcon` | 当前 observer 真雷达开关状态（off + EMCON 时 contacts 清空） |
| `radar` | authority 雷达：enabled/sphere/exposure/scan_index/seconds_on/mount_enabled/emcon/mast_deployed |
| `exposure` | 被动暴露状态：`exposed`、`elint_intercept_range_km`、`fix_after_s`、`fix_progress`、`warning`；off/EMCON 时 `exposed=false` |
| `iff` | schema=`transit_iff.v1`：`available/model/range_km/last/results/by_target/summary{total,friend,unknown,no_reply,faulty,out_of_range,hostile}`、`hostile=0`、`never_hostile=true`、`produces_contact=false`、`writes*=false` |
| `events` | 最近 API/authority 事件（`kind/message/t`；JSON-safe） |
| `warnings` | shadow/姿态/IFF 范围/雷达首扫/fallback 等 |
| `errors` | setup/authority 错误（正常为空） |
| `writes` | `{"track_table": false, "v15": false}` |
| `authority` | authority schema/mode/backend/counts/summary/writes |

- 所有位置/速度均为普通数组；VM 可 `JSON.stringify`（无 Vector3/Object）。
- 确定性：同一输入顺序/时间 → 同一 VM（plan 缓存/authority 模型无随机源）。

## 5　转场传感器行为

| 场景 | 真实结果 |
| --- | --- |
| 默认 harmattan→apsis，起飞段 step 18 s | 雷达 contacts ≥5（4 舰 + L4 港）；TWS 通道 ≥5；VIS/IR 锁定 |
| VIS 锁定 | `status=locked`、`level_support=3`、classification、FOV≈0.244°、IFOV≈1.04 µrad、SNR>0 |
| IR 锁定 | `status=locked`、`level_support=1`（IR 不分类）、FOV≈0.733° |
| 超距/视轴外 | `lost` + `reason=out_of_range / fov_miss`（底层 optical_ir 真实判据） |
| 遮挡 | 底层 `optical_ir` 地球圆盘遮挡 → `reason=occluded`、`occluded=true`（probe 用真实 authority 几何验证） |
| FOV 竞争 | 同 kind 多通道共享云台视轴，非当前视轴目标 `fov_miss` |
| 抵达 L1 | `phase=arrival`；L1 Meridian 近距（<1000 km）、L4 远距（>100k km）；L1 港雷达接触 |
| 5 舰 observer | 每舰可 `select_ship`；缺能力用 fallback 并 warning，仍输出 contacts/channels/VM |
| 雷达开机 | `radar_enabled=true`、contacts≥5、`exposure.exposed=true`、ELINT 截获距离 45,000 km/20 s 定位字段 |
| 雷达关闭/EMCON | `radar_enabled=false`、`emcon=true`、contacts=0、`exposure.exposed=false`；IFF 真实返回 `blocked` |
| IFF friend | apsis/harmattan/ferry 的 `transponder=ok` → `status=friend`、identity=friend；L4 港 friend |
| IFF faulty/no_reply | watchtower `faulty_transponder` → `faulty`；deepwell `transponder=off` → `no_reply`；identity 均 unknown |
| IFF 超距 | 起飞段 L1 三港距离 >2,000 km → `out_of_range`（抵达后可 friend） |
| IFF 不产生接触 | `produces_contact=false`、`level_support=0`，contacts 数量前后不变；`hostile=0/never_hostile` |

雷达/TWS 来自 authority 的 YW-R9 球形模型；VIS/IR 来自 optical_ir 后端；IFF 来自
V2InformationWarfare（MK-12）。IFF 仅 identity 证据，不产生位置/接触、不自动判敌。

## 6　接入 `transit_hud.gd` 的方式（本任务不接）

```gdscript
var sensors = preload("res://scripts/transit_sensors.gd").new({
    "observer_id": "harmattan", "target_id": "apsis"})
func _process(delta):
    sensors.step(delta)              # 或按转场 speed 传入
    var vm = sensors.vm()
# 映射建议：
#   vm.contacts -> 接触列表（level/range/bearing/identity）
#   vm.optical.vis/ir -> SENSOR 面板 FOV/SNR/status/reason
#   vm.levels.counts -> L0–L4 统计
#   vm.radar_enabled / vm.exposure -> RADAR/EMCON 状态与暴露警示
#   vm.iff.last/summary -> IFF 询问结果（friend/unknown…；hostile=0）
#   vm.events/warnings -> 事件/warning 区
```
HUD 只需消费 VM；不修改 `transit.gd`/`transit_hud.gd` 时不存在依赖。需要时用
`select_ship`/`set_target`/`start_optical`/`stop_optical` 驱动，不在 HUD 内写模型。

## 7　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/transit_sensors_probe.gd
# TRANSIT SENSOR PROBE RESULT: PASS=312 FAIL=0
# TRANSIT SENSOR PROBE OK（退出码 0）
```

覆盖（312 checks）：
- 场景/plan：5 舰、4 港、批号、tof>0、VM schema/writes=false/JSON；
- 默认观测：contacts≥5、TWS 通道、VIS 锁定 L3、IR 锁定 L1、FOV/IFOV/SNR/off-axis、等级/事件/warnings；
- 5 舰逐一切 observer：observer 字段、5 ships/4 ports/8 targets、contacts/channels、fallback 列表、JSON；
- 目标：8 个目标可 set；未知目标/非法 kind/无匹配 stop 的失败；超距 VIS 失败 reason；
  同 kind 多通道 FOV 失败；地球遮挡（authority 真实几何）reason=occluded；stop 后光学通道清空；
- 抵达：seek 到 arrival、L1 港近距/L4 港远距、L1 港雷达接触、L1 港 VIS 通道状态/FOV/SNR；
- **雷达/EMCON**：on→contacts≥5 + exposure.exposed=true；off→radar_enabled=false/emcon=true/contacts=0/exposed=false；
  on 恢复后 step 重新产生 contacts/exposure；返回 reason/writes；
- **真实 IFF**：4 舰 + 4 港逐目标查询，friend / faulty / no_reply / out_of_range 状态；
  每结果 never_hostile、hostile=false、produces_contact=false、level_support=0、不写 V15；
  IFF 前后 contacts 数量不变；未知目标/自身目标 unknown_target；EMCON 下 blocked；
  VM iff schema/summary/by_target/hostile=0、JSON；
- 确定性：两实例同输入 VM 逐字节一致；JSON/summary；不写 TrackTable/V15。

## 8　边界 / 未完成

- 本任务**不接 HUD/UI**；`transit_hud.gd` 仍显示 `SENSOR BRIDGE NOT WIRED`，下一任务消费本 VM。
- 5 舰中 apsis/ferry/watchtower/deepwell 的场景能力不完整（尤其 watchtower/deepwell 仅通信）；
  数据层补 authority 默认挂载并**显式 warning + fallbacks**，不把补挂载写成 V15 能力。
- 转场自然几何没有地球背后的港群，故真实遮挡用底层 authority 几何在 probe 验证；
  transit VM 的 `reason` 会透传底层 `occluded`。
- 港群位置由 scenario port offset + plan target state 重建；L4 只一个港，L1 三港同簇。
- `set_radar_enabled(false)` 即 EMCON，真实阻断 IFF（blocked）；要恢复 IFF 先
  `set_radar_enabled(true)`（再 step 产生新雷达扫描/暴露）。这是本层演示语义，不是 V15 EMCON 权威写入。
- IFF 结果只作为身份证据，不产生位置/接触、不自动判敌；未接 ELINT/EW/世界航迹/V15。
- 未做 HUD 时间轴拖动/最终 exe 集成；plan 缓存为进程内静态；`restart`/新实例会复用（只读，无副作用）。