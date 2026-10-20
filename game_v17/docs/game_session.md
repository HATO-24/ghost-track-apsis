# 完整游戏-阶段2C/2H · GameSession 编排层（含 TrackTable/StoryState）

> 任务 完整游戏-阶段2C（task-121）+ 阶段2H（task-129）。工程 `game_v17`。
> 修改（不改其他；不接旧场景/UI；未 commit）：
> - `scripts/core/game_session.gd`
> - `tests/session_probe.gd`（`PASS=296 FAIL=0`）
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
 └─ StoryState（可选） 剧情 flags/evidence/choices/trust/morality/reputation/threat/gate
```

- **依赖方向**：OrderService 内部持有 CommsService；`tick` 时订单服务推进通信并消费其投递事件。
- **事件方向**：session 把订单/通信/链路事件发布到 EventBus；**bus 不自动写 world**；
  world 仅由 session 写者显式 apply（seed 实体、或调用方显式事件）。
- **单写者**：session 的 writer（默认 `"session"`）是 WorldState 唯一写者；TrackTable 自己是
  独立单写者（默认 `session_fusion`）；外部 token 写两处均拒绝。
- **bus → TrackTable/StoryState**：只按**显式白名单** `story.flag/story.evidence/story.choice/
  track.observation/track.evidence` 路由；其它事件不写组件（不让 bus 偷写）。
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
| `order(id)` / `comms_pending()` | 只读查询 |
| `snapshot()` / `to_dict()` / `to_json()` | 只读快照（time/world/orders/comms/bus 最近 32 事件/track/story/contracts/errors） |
| `save_state() -> String` / `load_state(json) -> Dictionary` | **内存 JSON**：seed + 操作日志重放 + track/story/bus 快照 |
| `check_contracts()` / `reset()` | DbC 检查/按原 seed 重开 |

### 3.1　tick 语义

1. 非有限/负 dt 拒绝；暂停时返回 `paused=true`，时间/订单/通信/轨道/剧情均不推进；
2. `TimeService.tick(dt)` 乘以 scale 得 `sim_dt`；`orders.tick(sim_dt)`（内部推进 comms）；
3. `orders.take_events()` → 发布 `order.<event>`；
4. `track_table.tick(sim_dt)`（stale/forget 过期）；`story_state.set_time(now_s)`；
5. 白名单总线路由：tick 处理 bus 中未被路由且类型在白名单的事件（`track.observation` 等）；
6. standalone `send_comms` 的投递对账：tick 后 pending 消失 → 发布 `comms.delivered`；
7. 事件 bus 只接收发布；不改变 world 实体（probe 断言 tick 前后 world 不变）。

### 3.2　事件类型

- session 发布：`entity.spawn`（seed）、`order.*`、`comms.sent/delivered/failed`、`comms.link`。
- **可路由白名单（bus → 组件）**：`story.flag`（payload flag/value）、`story.evidence`（evidence_id）、
  `story.choice`（choice_id/meta）、`track.observation`（observation 对象）、`track.evidence`（证据对象）。
- 非白名单类型（如 `entity.move`、`order.*`、`comms.*`）**不写** TrackTable/StoryState。

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
  bus: {seq, events[]}
}
```

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
# V17 SESSION PROBE RESULT: PASS=296 FAIL=0（exit 0，只跑一次）
```

覆盖（16 节）：boot（5 组件/seed 实体/节点链路/contracts/snapshot schema）；订单流
（ISSUED→…→DONE、事件类型、delivery_id、订单-通信一致、终态拒绝）；通信/链路；失败/过期/
撤销/拒绝；暂停/时标/时间单调；bus-world 分离与单写者；save/load snapshot 一致+二次 save；
错误路径；JSON/确定性；**可选组件**（无配置/false 退化、true 启用、退化 save/load）；
**TrackTable L1-L4**（单/多源观测 L1/L2、光学证据 L3、IFF L4、重复/非法/未授权拒绝、
stale/forget、filter、track t 同步）；**StoryState 集成**（story evidence/flag/choice 路由、
非白名单不写、gate/t_s/revision）；**组件存档**（track/story/bus 快照、load 后 VM/t/contracts
一致、继续操作、再次 save、无组件存档被启用会话读取兼容）；**旧存档缺字段兼容**；
**组件非法事件/确定性**（失败不改状态、总线路由失败 warning、同操作 snapshot/save 一致、
world/track 外部写拒绝）。

## 7　边界 / 未完成

- 只做**编排**：不实现物理/传感器/武器/ROE/UI/剧情文本；不接旧场景/HUD/transit；不写 V15。
- TrackTable/StoryState 为**可选组合**；未配置时相关 API 返回空/`no_*`，session 退化运行。
- bus 只按显式白名单路由，不自动把订单/通信事件写成剧情/航迹；world 变更仍必须 session 写者显式 apply。
- demo seed 为示例（3 实体/3 节点/2 链路），**不是关卡内容**。
- standalone `comms.delivered` 仅按 pending 消失对账；若在途链路失败，原因未从 comms 事件取回
  （订单路径的 comms 失败仍由 OrderService 处理并体现在 order.reason）。
- save/load 为内存 JSON（seed+log 重放 + 组件快照），不是完整序列化；log 随操作增长；
  组件快照 JSON 数值/整数按浮点往返（规范化比较）；无文件槽位（SaveService 负责）。
- 未跑全量回归；未 commit。
