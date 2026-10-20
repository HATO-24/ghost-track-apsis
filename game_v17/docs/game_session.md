# 完整游戏-阶段2C/2H · GameSession 编排层（含 TrackTable/StoryState）

> 任务 完整游戏-阶段2C（task-121）+ 2H（task-129）+ 2J（task-131）+ 3I（task-142）。工程 `game_v17`。
> 修改（不改其他；不接旧场景/UI；未 commit）：
> - `scripts/core/game_session.gd`
> - `tests/session_probe.gd`（`PASS=520 FAIL=0`）
> - 本文件
> 不实现物理/UI/剧情/ROE；组合既有内核并做内存 save/load。

## 1　角色与依赖

```
GameSession
 ├─ TimeService      时间/epoch/scale/pause/docked
 ├─ EventBus          事件 id/type/t/source/target/payload/text_key + seq
 ├─ WorldState        实体表 + TimeService 钟引用 + 已应用事件引用（单写者）
 ├─ OrderService      命令状态机（依赖 CommsService 投递）
 ├─ CommsService      节点/链路/路由/延迟/丢包/遮挡/干扰
 ├─ TrackTable（可选） 观测/证据融合（L1-L4，单写者）= V2FusedTrackTable
 ├─ StoryState（可选） 剧情 flags/evidence/choices/trust/morality/reputation/threat/gate
 ├─ SensorService（可选） 传感器管道 → observation/evidence，经 session 显式白名单路由到 TrackTable
 ├─ PortService（可选） 港口/对接/加注/维修/拖曳/穿梭机状态机与资源
 └─ CombatService（可选） ROE/授权/火控/武器/点防御（damage event 不直接应用）
```

- **依赖方向**：OrderService 内部持有 CommsService；`tick` 时订单服务推进通信并消费其投递事件。
- **事件方向**：session 把订单/通信/链路事件发布到 EventBus；**bus 不自动写 world**；
  world 仅由 session 写者显式 apply（seed 实体、或调用方显式事件）。
- **单写者**：session 的 writer（默认 `"session"`）是 WorldState 唯一写者；TrackTable 自己是
  独立单写者（默认 `session_fusion`）；外部 token 写两处均拒绝。
- **bus → TrackTable/StoryState**：只按**显式白名单** `story.flag/story.evidence/story.choice/
  track.observation/track.evidence` 路由；其它事件不写组件（不让 bus 偷写）。
- **Sensor → TrackTable**：SensorService 只输出 observation/evidence（不写 TrackTable/world/UI）；
  session 在 tick 中取走其事件，按 schema/kind 白名单（`sensor_observation.v1` support 1..2、
  `track_evidence.v1`）路由到 TrackTable；support=0/>2 的非 L1/L2 行忽略。
- **Port/Combat → EventBus**：session tick 驱动二者 step；其 outbox 事件映射为 `port.*`/`combat.*`
  发布到 bus（只读事件）；Port/Combat 不写 world/TrackTable/物理/UI，damage event 由上层决
  定是否应用（`applied=false`）。
- seed/demo 数据仅示例，**不进入关卡**。

## 2　boot(config)

`boot(config := {})` 返回 `{ok,ready,booted,writer,t_s,errors,warnings,snapshot}`；
空 config 使用 demo seed（3 实体：apsis/harmattan/l1_station；节点 3；链路 2：apsis↔harmattan LD、
harmattan↔l1_station LR；无订单；**不启用** TrackTable/StoryState）。

config 可覆盖字段（省略用 demo）：

| 字段 | 说明 |
| --- | --- |
| `time` | TimeService 参数（t_s/epoch_s/scale/max_dt_s/paused…） |
| `writer` | WorldState 写者 token（默认 `session`） |
| `entities[]` | seed 实体（id/batch/kind/name/pos_km/vel_kmps/flags） |
| `nodes[]` / `links[]` | CommsService 节点/链路（a/b/mode/latency_s/range_km/packet_loss/jam/occluded/enabled） |
| `orders[]` | seed 订单（action/issuer_id/target_ids/params/opts/issue:bool） |
| `order_mode` / `comms_text_key` / `delivery_delay_s` | 订单默认通信模式/发送文本键/本地延迟 |
| `track_table` | **可选**：`true` 或配置字典（writer_id/stale_after_s/forget_after_s/max_tracks…）；缺省/`false` → 不组合 |
| `story_state` | **可选**：`true` 或 StoryState seed 字典（flags/evidence_ids/trust…）；缺省/`false` → 不组合 |
| `sensor_service` | **可选**：`true` 或 SensorService 配置字典（`observer`/`mounts`/`targets`/`snapshot`/`options`）；缺省/`false` → 不组合 |
| `port_service` | **可选**：`true` 或 PortService 配置（`ports[]` 泊位/船坞/拖船/燃料/窗口/许可/services）；缺省/`false` → 不组合 |
| `combat_service` | **可选**：`true` 或 CombatService 配置（`content_path`(weapons_l1)/`roe`/`own_id`/`fleet_id`）；缺省/`false` → 不组合 |

- boot 建 5 个必需组件 + 可选 TrackTable/StoryState；任一启用组件 `ready=false` → `ok=false` + errors，不伪造。
- TrackTable 默认 writer = `<session writer>_fusion`；StoryState 时间在 boot 时对齐 session 时间。
- seed 实体：bus 发布 `entity.spawn` + world.apply（session 写者）；seed 订单可选 `issue:true`。

## 3　API

| API | 说明 |
| --- | --- |
| `tick(dt) -> Dictionary` | 时间推进 → 订单/通信 tick（scaled dt）→ 订单事件发布 → **TrackTable.tick/story.set_time** → 白名单总线路由 → 通信投递对账；返回 `{ok,t_s,paused,dt_scaled_s,events,routed,components,order_counts,contracts}` |
| `pause()` / `resume()` / `set_scale(s)` | 时间控制；暂停时 tick 不推进订单/通信/轨道/剧情时间 |
| `issue_order` / `authorize_order` / `begin_execute_order` / `complete_order` / `abort_order` / `reject_order` | 订单包装（含 events） |
| `send_comms` / `set_link` | 通信/链路包装 |
| `handle_observation(observation)` | 观测 → TrackTable（需启用；自动补 t；单写者 writer；失败不改状态） |
| `handle_evidence(evidence)` | **TrackTable 证据**（`track_evidence.v1`）→ L3/L4 |
| `handle_story_evidence(evidence_id)` | **StoryState 证据**（独立于 TrackTable 证据） |
| `route_event(event)` | 显式白名单事件：应用组件 + 发布 bus；不在白名单 → `not_routable`，不写组件 |
| `track_vm(opts={})` / `track_filter(where={})` | 只读 TrackTable VM/过滤（未启用返回空） |
| `story_vm()` / `gate(conditions)` | 只读 StoryState 快照/条件判定（未启用返回空/`no_story_state`） |
| `sensor_vm()` | 只读 SensorService VM（未启用返回空） |
| `set_sensor_target(target_id)` | 选中传感器目标（未知目标 `unknown_target`，失败不改状态） |
| `start_sensor_channel(kind, target, opts={})` / `stop_sensor_channel(kind, target)` | 启停 optical/ir 通道 |
| `set_radar_enabled(on)` / `set_emcon(on)` | 雷达开关/EMCON（关闭主动雷达观测；被动光学/IR 继续） |
| `query_iff(target_id="")` | 显式 IFF 询问：产生 iff evidence（support 4），成功后显式路由到 TrackTable；`never_hostile=true` |
| `port_request/port_permit/port_approach/port_dock/port_refuel/port_repair/port_finish_service/port_undock` | PortService 委托（失败不改状态；成功记录 log） |
| `port_tow/port_shuttle/port_services/port_vm/port_summary` | 拖曳/穿梭机委托与只读 VM |
| `set_roe/combat_register_track/combat_request_solution/grant_authorization/revoke_authorization/request_fire` | CombatService 委托（FIRE 需 confirmed+授权；失败不改状态） |
| `combat_authorization/combat_vm/combat_summary/flush_events` | 授权查询/只读 VM/立即 flush Port+Combat bus 事件 |
| `order(id)` / `comms_pending()` | 只读查询 |
| `snapshot()` / `to_dict()` / `to_json()` | 只读快照（time/world/orders/comms/bus 最近 32 事件/track/story/contracts/errors） |
| `save_state() -> String` / `load_state(json) -> Dictionary` | **内存 JSON**：seed + 操作日志重放 + track/story/bus 快照 |
| `check_contracts()` / `reset()` | DbC 检查/按原 seed 重开 |

### 3.1　tick 语义

1. 非有限/负 dt 拒绝；暂停时返回 `paused=true`，时间/订单/通信/轨道/剧情均不推进；
2. `TimeService.tick(dt)` 乘以 scale 得 `sim_dt`；`orders.tick(sim_dt)`（内部推进 comms）；
3. `orders.take_events()` → 发布 `order.<event>`；
4. `track_table.tick(sim_dt)`（stale/forget 过期）；`story_state.set_time(now_s)`；
5. `sensor_service.step(sim_dt)` → `take_events()` → 只路由 observation（support 1..2）/evidence
   到 TrackTable（target_id 映射到已建 track；support=0/>2 忽略；控制事件忽略）；
6. `port_service.tick(sim_dt)` / `combat_service.tick(sim_dt)`；各自 outbox 事件 → `port.*`/`combat.*`
   发布到 EventBus（tick 自动 flush；也可 `flush_events()` 显式拉取）；
7. 白名单总线路由：tick 处理 bus 中未被路由且类型在白名单的事件（`track.observation` 等）；
8. standalone `send_comms` 的投递对账：tick 后 pending 消失 → 发布 `comms.delivered`；
9. 事件 bus 只接收发布；不改变 world 实体（probe 断言 tick 前后 world 不变）。

### 3.2　事件类型

- session 发布：`entity.spawn`（seed）、`order.*`、`comms.sent/delivered/failed`、`comms.link`。
- **可路由白名单（bus → 组件）**：`story.flag`（payload flag/value）、`story.evidence`（evidence_id）、
  `story.choice`（choice_id/meta）、`track.observation`（observation 对象）、`track.evidence`（证据对象）。
- 非白名单类型（如 `entity.move`、`order.*`、`comms.*`）**不写** TrackTable/StoryState。
- SensorService 输出不经过 bus（session 直接 take_events 并显式过滤）；其 observation/evidence
  与 TrackTable 输入 schema 一致，控制事件不路由。
- PortService 事件：`port.request_created/granted/denied/held/expired/approach/docked/service_started/
  service_finished/departed`；CombatService 事件：`combat.<kind>`（weapon_launch/combat_hit/combat_miss/
  point_defense/authorization_*/roe_* 等），均为只读事件。

## 4　DbC / 一致性

`check_contracts()` 返回 `{ok, violations[]}`：

- **单写者**：`world.current_writer() == session.writer`；TrackTable `current_writer()==_track_writer`；
  外部 token 写 world → `writer_mismatch`，写 track → `unauthorized_writer`。
- **时间单调**：session last_time_s；TimeService 不变量；`orders.t`、`track_table.t`、
  `story_state.t_s` 均与 `now_s()` 同步（非暂停）。
- **版本单调**：story `revision` 不回退（track 以 t/等级单调 + 事件 seq 保证）。
- **订单-通信一致**：活动订单必须有 `delivery_id`；`issued_t` 不超过会话时间。
- **世界时钟**：`world.clock_t_s() == session.now_s()`。
- **组件失败不改状态**：observation/evidence/route 非法时返回 `{ok:false,reason}`，TrackTable/StoryState
  不部分写入；tick 路由失败写 warnings（不静默）。
- **传感器一致**：`sensor_service.t == now_s()`；失败控制（未知目标/非法通道/非法 stop/无传感器）
  返回 `{ok:false,reason}`，sensor 计数/状态不变；IFF 只给 friend/unknown，不自动判敌。
- **Port/Combat 一致**：`port_service.t_s == combat_service.t == now_s()`；两者 ready 且内部
  contracts/ROE 合法；失败委托（无服务/错误状态/非法 ROE/冷却/未授权）不改组件状态。
- tick 失败/拒绝路径不静默：返回 `ok=false` + `errors/contract_errors`；失败订单不伪造状态。

## 5　内存 save/load（不写盘）

`save_state()` 返回 JSON：

```text
{
  schema:"v17.game_session_save.v1", version:"1.0.0",
  seed: {time/writer/entities/nodes/links/orders/.../track_table/story_state},
  log: [ {op:"tick"/"issue_order"/.../ "handle_observation"/"handle_evidence"/
          "handle_story_evidence"/"route_event", ...} ],
  track_table: <V2FusedTrackTable.snapshot()> | null,
  story: <StoryState.snapshot()> | null,
  port_service: <PortService.save_state() JSON> | "",
  combat_service: <CombatService.save_state() JSON> | "",
  bus: {seq, events[]}
}
```

**Port/Combat 存档**：save 嵌入二者 `save_state()` JSON；load 时先 boot(seed) 重建并按 log 重放
（port/combat 委托操作 + tick），再恢复快照；load 后 VM/snapshot 一致、时间与 session 同步、
可继续操作/再次 save。旧存档缺 `port_service/combat_service` 字段与 seed 配置时，replay 对应操作
被跳过（`skipped:no_port_service/no_combat_service`），组件退化、不报错。

**Sensor 重建**：save **不写 sensor 快照**；seed 保留 sensor_service 配置，log 记录控制操作
（set_sensor_target/start_sensor_channel/stop_sensor_channel/set_radar_enabled/set_emcon/query_iff）；
`load_state` 时 boot 重建 SensorService 并按 log 重放，tick 重放重新 step/路由 → sensor VM/计数/
summary 与保存前一致。旧存档 seed 无 sensor_service 时，log 中 sensor 操作 replay 被跳过
（`skipped:no_sensor_service`），不报错、组件退化。

- `load_state(json)`：校验 schema → `boot(seed)` → 重放 log → 恢复 `track_table/story/bus` 快照 →
  设置 writer/时间/事件索引 → 返回 ok/errors。
- 恢复后：track/story VM 与原状态一致、`track.t`/`story.t_s` 与 session 时间一致、contracts ok；
  可继续 tick/观测且再次 `save_state()` 规范化一致。
- **旧存档兼容**：缺 `track_table/story/bus` 字段、seed 无组件配置的旧 JSON → 正常 load，
  组件保持退化（不伪造）；旧存档核心时间/订单/世界/事件可恢复。
- JSON 数值往返按浮点（快照一致性用 JSON 规范化比较）；组件快照恢复失败 → `ok=false` + errors。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/session_probe.gd
# V17 SESSION PROBE RESULT: PASS=520 FAIL=0（exit 0，只跑一次）
```

覆盖（24 节）：boot（5 组件/seed 实体/节点链路/contracts/snapshot schema）；订单流
（ISSUED→…→DONE、事件类型、delivery_id、订单-通信一致、终态拒绝）；通信/链路；失败/过期/
撤销/拒绝；暂停/时标/时间单调；bus-world 分离与单写者；save/load snapshot 一致+二次 save；
错误路径；JSON/确定性；**可选组件**（无配置/false 退化、true 启用、退化 save/load）；
**TrackTable L1-L4**（单/多源观测 L1/L2、光学证据 L3、IFF L4、重复/非法/未授权拒绝、
stale/forget、filter、track t 同步）；**StoryState 集成**（story evidence/flag/choice 路由、
非白名单不写、gate/t_s/revision）；**组件存档**（track/story/bus 快照、load 后 VM/t/contracts
一致、继续操作、再次 save、无组件存档被启用会话读取兼容）；**旧存档缺字段兼容**；
**组件非法事件/确定性**（失败不改状态、总线路由失败 warning、同操作 snapshot/save 一致、
world/track 外部写拒绝）；**Sensor 可选/API**（无/false 退化、true 默认、空目标 ready、无传感器
API 返回 no_sensor_service）；**Sensor 管道**（雷达观测→track L1/L2、optical→L3、IFF→L4、
EMCON/雷达开关/通道启停、unknown_target/非法通道拒绝、sensor t 同步、不写 track_table/v15/world）；
**Sensor 存档**（seed+log 重建、load 后 sensor_vm/summary/track/snapshot/save 一致、继续控制 tick、
旧存档缺 sensor 配置兼容）；**Sensor 失败/确定性**（失败控制不改状态、support=0 忽略、
同操作 VM/snapshot/save 一致）；**Port/Combat 可选**（无配置退化、单启用、true 默认、
无服务 API 拒绝）；**Port 集成**（request→permit→approach→dock→refuel/repair→finish→undock、
tow/shuttle、port.* 事件进 bus、tick 不自动、失败不改状态）；**Combat 集成**（set_roe/register/
solution/READY/grant/check/confirmed fire/冷却拒绝/未知目标/友方拒绝/非法 ROE、combat.* 事件）；
**Port/Combat 存档**（save 嵌入两快照、load 后 VM/snapshot 一致、继续操作、旧档兼容、同操作确定性）。

## 7　边界 / 未完成

- 只做**编排**：不实现物理/传感器/武器/ROE/UI/剧情文本；不接旧场景/HUD/transit；不写 V15。
- TrackTable/StoryState/SensorService/PortService/CombatService 为**可选组合**；未配置时相关 API 返回空/`no_*`，session 退化运行。
- PortService/CombatService 只输出状态/事件；session 不自动许可/对接/服务/开火；FIRE 永不自动，
  需 confirmed + 授权；combat damage event `applied=false`，由上层损管决定应用。
- SensorService 只产生 observation/evidence（不直接写 TrackTable/world/UI）；routing 由 session
  显式白名单完成；传感器不判等级/身份，等级由 TrackTable 融合规则决定；IFF 不自动判敌。
- 传感器 target_id → TrackTable track 的内部分配在 session 记录（观测后映射）；无观测的目标
  evidence 会 `unknown_track` 拒绝（不伪造航迹）。
- bus 只按显式白名单路由，不自动把订单/通信事件写成剧情/航迹；world 变更仍必须 session 写者显式 apply。
- demo seed 为示例（3 实体/3 节点/2 链路），**不是关卡内容**。
- standalone `comms.delivered` 仅按 pending 消失对账；若在途链路失败，原因未从 comms 事件取回
  （订单路径的 comms 失败仍由 OrderService 处理并体现在 order.reason）。
- save/load 为内存 JSON（seed+log 重放 + 组件快照），不是完整序列化；log 随操作增长；
  组件快照 JSON 数值/整数按浮点往返（规范化比较）；无文件槽位（SaveService 负责）。
- 未跑全量回归；未 commit。
