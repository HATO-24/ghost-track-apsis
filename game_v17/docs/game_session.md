# 完整游戏-阶段2C · GameSession 编排层

> 任务 完整游戏-阶段2C（task-121）。工程 `game_v17`。
> 新文件（不改其他；不接旧场景/UI；未 commit）：
> - `scripts/core/game_session.gd`
> - `tests/session_probe.gd`（`PASS=164 FAIL=0`）
> - 本文件
> 不实现物理/UI/剧情/ROE；组合既有内核并做内存 save/load。

## 1　角色与依赖

```
GameSession
 ├─ TimeService      时间/epoch/scale/pause/docked
 ├─ EventBus          事件 id/type/t/source/target/payload/text_key + seq
 ├─ WorldState        实体表 + TimeService 钟引用 + 已应用事件引用（单写者）
 ├─ OrderService      命令状态机（依赖 CommsService 投递）
 └─ CommsService      节点/链路/路由/延迟/丢包/遮挡/干扰
```

- **依赖方向**：OrderService 内部持有 CommsService；`tick` 时订单服务推进通信并消费其投递事件。
- **事件方向**：session 把订单/通信/链路事件发布到 EventBus；**bus 不自动写 world**；
  world 仅由 session 写者显式 apply（seed 实体、或调用方显式事件）。
- **单写者**：session 的 writer（默认 `"session"`）是 WorldState 唯一写者；外部 token 写 world 被拒。
- seed/demo 数据仅示例，**不进入关卡**。

## 2　boot(config)

`boot(config := {})` 返回 `{ok,ready,booted,writer,t_s,errors,warnings,snapshot}`；
空 config 使用 demo seed（3 实体：apsis/harmattan/l1_station；节点 3；链路 2：apsis↔harmattan LD、
harmattan↔l1_station LR；无订单）。

config 可覆盖字段（省略用 demo）：

| 字段 | 说明 |
| --- | --- |
| `time` | TimeService 参数（t_s/epoch_s/scale/max_dt_s/paused…） |
| `writer` | WorldState 写者 token（默认 `session`） |
| `entities[]` | seed 实体（id/batch/kind/name/pos_km/vel_kmps/flags） |
| `nodes[]` / `links[]` | CommsService 节点/链路（a/b/mode/latency_s/range_km/packet_loss/jam/occluded/enabled） |
| `orders[]` | seed 订单（action/issuer_id/target_ids/params/opts/issue:bool） |
| `order_mode` / `comms_text_key` / `delivery_delay_s` | 订单默认通信模式/发送文本键/本地延迟 |

- boot 先建 5 组件；失败（任一 `ready=false`）→ `ok=false` + errors，不伪造。
- seed 实体：bus 发布 `entity.spawn` + world.apply（session 写者）；seed 订单可选 `issue:true`。
- seed 实体的 bus 事件与 world 应用都由 session 编排（不是 bus 偷写 world）。

## 3　API

| API | 说明 |
| --- | --- |
| `tick(dt) -> Dictionary` | 时间推进 → 订单/通信 tick（使用 time 的 **scaled dt**）→ 订单事件发布 → 独立通信投递对账；返回 `{ok,t_s,paused,dt_scaled_s,events,order_counts,contracts}` |
| `pause()` / `resume()` / `set_scale(s)` | 时间控制；暂停时 tick 不推进订单/通信 |
| `issue_order(action, issuer, targets, params={}, opts={})` | 创建草稿 + 发出（依赖通信投递）；返回 `{ok,order_id,delivery_id,order,reason,events}` |
| `authorize_order / begin_execute_order / complete_order / abort_order / reject_order` | 订单生命周期包装，均返回含 `events` |
| `send_comms(from,to,mode,text_key,payload={},opts={})` | 通信发送包装；成功记录 standalone 投递；返回 `{ok,...,events}` |
| `set_link(a,b,opts={enabled/occluded/jam})` | 链路控制包装；返回 `{ok,applied,events}` |
| `order(id)` / `comms_pending()` | 只读查询 |
| `snapshot()` / `to_dict()` / `to_json()` | 只读快照（time/world/orders/comms/bus 最近 32 事件/contracts/errors） |
| `save_state() -> String` / `load_state(json) -> Dictionary` | **内存 JSON**（不写盘）：seed + 操作日志重放 |
| `check_contracts()` / `reset()` | DbC 检查/按原 seed 重开 |

### 3.1　tick 语义

1. 非有限/负 dt 拒绝；暂停时返回 `paused=true`，时间/订单/通信均不推进；
2. `TimeService.tick(dt)` 乘以 scale 得 `sim_dt`；`orders.tick(sim_dt)`（内部推进 comms）；
3. `orders.take_events()` → 发布 `order.<event>`（drafted/issued/transmitting/delivered/queued/
   authorized/executing/done/rejected/aborted/stale…）；
4. standalone `send_comms` 的投递对账：tick 后 pending 消失 → 发布 `comms.delivered`；
5. 事件 bus 只接收发布；不改变 world 实体（probe 断言订单 tick 前后 world 不变）。

### 3.2　事件类型（session 发布）

`entity.spawn`（seed）、`order.drafted/issued/transmitting/delivered/queued/pending_effect/
authorized/executing/done/rejected/aborted/stale`、`comms.sent/delivered/failed`、
`comms.link`（链路变更）。payload 为精简字段（order_id/status/delivery_id/reason/from/to/…）；
text_key 来自订单/通信文本键。

## 4　DbC / 一致性

`check_contracts()` 返回 `{ok, violations[]}`：

- **单写者**：`world.current_writer() == session.writer`；外部 token apply 返回 `writer_mismatch`。
- **时间单调**：session 记录 last_time_s，回退即 violation；time.invariants。
- **订单-通信一致**：活动订单（ISSUED…EXECUTING）必须有 `delivery_id`；
  订单 `issued_t` 不得超过会话时间；`orders.t` 与 `time.now_s()` 同步（非暂停）。
- **世界时钟**：`world.clock_t_s() == session.now_s()`。
- tick 失败/拒绝路径不静默：返回 `ok=false` + `errors/contract_errors`；失败订单不伪造状态。

## 5　内存 save/load（不写盘）

- `save_state()` 返回 JSON 字符串：`{schema:"v17.game_session_save.v1", version, seed, log[]}`；
  seed 与 log 经 JSON 规范化（数值 JSON 浮点一致性）。
- `load_state(json)`：校验 schema → `boot(seed)` → 依序重放 log（tick/issue/authorize/begin/complete/
  abort/reject/send_comms/set_link/pause/resume/set_scale）；恢复 `_log`；返回 ok/errors。
- 重放为确定性（无随机/无外部输入）；probe 断言 load 后 `snapshot()` 与原会话一致、
  二次 `save_state()` 完全相同。**仅内存**，不写文件/存档槽。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/session_probe.gd
# V17 SESSION PROBE RESULT: PASS=164 FAIL=0（exit 0，只跑一次）
```

覆盖（9 节）：boot（5 组件/seed 实体/节点链路/contracts/snapshot schema）；订单流
（ISSUED→TRANSMITTING→DELIVERED→QUEUED→AUTHORIZED→EXECUTING→DONE、事件类型、delivery_id、
订单-通信一致、终态拒绝）；通信/链路（send/delivered、无效 mode/未知节点、链路禁用→订单
REJECTED、恢复/遮挡/干扰/未知链路）；失败/过期/撤销/拒绝；暂停/时标 2x/时间单调/负值拒绝；
bus-world 分离与单写者、snapshot 只读；save/load snapshot 一致+二次 save 相同；错误路径；
JSON/两次同操作确定性。

## 7　边界 / 未完成

- 只做**编排**：不实现物理/传感器/武器/ROE/UI/剧情；不接旧场景/HUD/transit；不写 V15。
- demo seed 为示例（3 实体/3 节点/2 链路），**不是关卡内容**；复杂编队/物理坐标由后续接入。
- 事件 bus 不自动写 world；需要 world 变更时必须本 session 写者显式 apply。
- standalone `comms.delivered` 仅按 pending 消失对账；若在途链路失败，原因未从 comms 事件取回
  （订单路径的 comms 失败仍由 OrderService 处理并体现在 order.reason）。
- save/load 仅内存 JSON（seed+log 重放），不是完整状态序列化；大量操作时 log 增长；无文件/存档槽。
- 未跑全量回归；未 commit。
