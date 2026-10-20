# 完整游戏-阶段2B · 命令服务 / 通信服务 / 独立文本库

> 任务 task-119（TRANSIT-CONTROLS 之后的新阶段）。工程 `game_v17`。
> **只新增 4 个文件**：
> `scripts/core/order_service.gd`、`scripts/core/comms_service.gd`、
> `tests/order_comms_probe.gd`、`docs/order_comms_core.md`。
> 未改旧 HUD/state/bridge/core/sim/project；不接 UI/物理/ROE 实现；不写 world/V15；未 commit。
>
> 设计依据：[`docs/07_命令通信与ROE.md`](../docs/07_命令通信与ROE.md)、
> [`docs/09_系统架构与数据契约.md`](../docs/09_系统架构与数据契约.md) §5 DbC。

## 1　定位

- **OrderService**：命令记录/状态机/延迟/撤销/过期/失败，事件输出；
  **不自动授权、不自动执行、不判定 ROE**（只留 `auth_check` Callable 钩子）。
- **CommsService**：节点/链路/路由/延迟/丢包/遮挡/干扰/中继/发送失败；事件输出。
  不读物理/轨道，距离/遮挡由链路参数或 `send(... opts.distance_km/...)` 提供。
- **TextLibrary**（内嵌在 `comms_service.gd`，可被 OrderService 复用）：
  `text_key` 选择 + 模板变量替换；`from/to/mode` 从运行时事件上下文解析；
  服务代码不硬编码舰名/对白；示例内容只用于 probe/演示。
- 两个服务均为纯 `RefCounted`、JSON-safe、确定性、无随机源、JSON VM 带
  `writes={track_table:false,v15:false}`。

## 2　OrderService

### 2.1 状态机（docs/07 §1.1）

```text
DRAFT → ISSUED → TRANSMITTING → DELIVERED → QUEUED / PENDING_EFFECT
      → AUTHORIZED → EXECUTING → DONE
任意未终态 → ABORTED / REJECTED / STALE（过期）
```

- `tick(dt)` 只推进时间/投递/入队/待生效到点/过期：
  **不会**自动 `AUTHORIZED`、`EXECUTING`、`DONE`。
- `AUTHORIZE`/`BEGIN_EXECUTE`/`COMPLETE` 必须显式 API。
- `PENDING_EFFECT` 在 `exec_t` 到点后转 `QUEUED`（仍等玩家授权/执行）。
- 过期：`expire_in_s>0` 且 `t>=expire_t` 且未 EXECUTING → `STALE`；不执行。
- 撤销：`abort()` 对任意未终态；已投递/传输中的在途通信不回收，命令不再执行。

### 2.2 命令记录

```text
order_id, issuer_id, target_ids[], action, params,
mode, text_key, status, reason,
issued_t, deliver_t, exec_t, expire_t, delivered_t, executed_t, ended_t,
delivery_delay_s, exec_delay_s, expire_in_s,
auth_required, authorized_by, delivery_id, relay_count, result, history[]
```

- action/params/命令类型数据驱动；服务不写死关卡命令。
- `history[]` 记录每次合法状态迁移 `{t,from,to,reason}`。
- `mode` 作为文本/通信模式（LD/LR/RDO/IR/VIS），不是物理链路。

### 2.3 API

```gdscript
const Orders := preload("res://scripts/core/order_service.gd")
var s = Orders.new({
    "entities": {"a": {"name": "ALPHA", "role": "command"},
                 "b": {"name": "BETA", "role": "escort"}},
    "delivery_delay_s": 2.0,
    # 可选：comms = CommsService 实例；text_library = 自定义 TextLibrary；
    # mode / require_authorizer / auth_check Callable / text_keys 覆盖
})

s.create_draft(action, issuer_id, target_ids, params := {}, opts := {})
s.issue(order_id) -> {ok, order, delivery_id}
s.tick(dt) -> {ok, t, events[], counts}
s.authorize(order_id, authorizer_id := "") -> {ok, order}
s.reject(order_id, reason, by := "") -> {ok, order}
s.begin_execute(order_id) -> {ok, order}   # AUTHORIZED；或 auth_required=false 的 QUEUED
s.complete(order_id, result := {}) -> {ok, order}  # 只在 EXECUTING
s.abort(order_id, reason := "aborted") -> {ok, order}
s.order(order_id) / s.pending_orders() / s.status_counts()
s.events / s.events_since(seq) / s.take_events()
s.set_auth_hook(Callable)
s.vm() / s.summary() / s.to_dict() / s.to_json()
```

失败返回 `{ok:false,reason}`，不静默改状态：未知 order/非法状态/未授权执行/
非 EXECUTING 完成/终态再操作等。

### 2.4 事件 schema `order_event.v1`

```text
{schema,seq,t,order_id,event,from_state,status,
 issuer_id,target_ids[],action,
 from,to,from_id,to_id,to_role,mode,
 text_key,text,reason,delay_s,relay_count,delivery_id,
 shadow:true,writes_v15:false,writes_track_table:false}
```

事件文本由 `text_key`（默认 `ORDER_*`，可 `text_keys` 覆盖）与 TextLibrary 解析；
`from/to/mode/content/delay/reason_text` 从命令实体/时间上下文动态生成。

### 2.5 通信集成

- `config.comms` 为 `V2CommsService` 实例时：`issue()` 调 `comms.send(...)`，
  用其 `delivery_id/latency/relay_count` 驱动 `TRANSMITTING→DELIVERED`；
  `tick()` 内部推进 comms 并消费其 `DELIVERED/FAILED`。
- comms 发送失败 → order `REJECTED`，reason=`comms_*`。
- 无 comms 时用本地 `delivery_delay_s` 模拟延迟；不伪造通信投递。
- 默认发送文本键 `COMMS_SENT`（可 `config.comms_text_key` 覆盖）。

## 3　CommsService

### 3.1 节点 / 链路

- Node：`{id,name,role,type,antenna,power,encryption,status,enabled,damage}`。
- Link：`{a,b,mode,latency_s,range_km,bandwidth_kbps,packet_loss,jam,occluded,
  requires_los,enabled,relay_penalty_s}`。
- 模式默认：

| mode | 默认延迟 | 默认距离 | LOS |
| --- | --- | --- | --- |
| LD | 0.1 s | 150,000 km | 是 |
| LR | 0.35 s | 200,000 km | 是 |
| RDO | 2.0 s | 300,000 km | 否 |
| IR | 0.2 s | 12,000 km | 是 |
| VIS | 0.05 s | 2,000 km | 是 |

- 遮挡/干扰/距离不在此做物理；由 link 字段或 `send(opts.distance_km)` 提供，
  适合测试/上层物理接入。
- 路由：直连优先；否则单中继（A→R→B，同 mode 两段）；延迟为链路和+中继惩罚；
  `relay_count` 进入事件/VM。多跳中继未实现（单中继足够阶段2B）。

### 3.2 发送 / 投递 / 失败

```gdscript
var c = CommsService.new({
    "nodes": [{"id":"a","name":"ALPHA"},{"id":"b","name":"BETA"}],
    "links": [{"a":"a","b":"b","mode":"LD","latency_s":0.1}],
})
c.send(from, to, mode, text_key, payload := {}, opts := {}) -> {ok,delivery_id,...,text,...}
c.tick(dt) -> new_events[]
c.set_link_enabled/set_link_occluded/set_link_jam/set_node_status
c.find_route(from,to,mode,opts)  # {ok,path,links,latency_s,relay_count,reason}
c.node(id) / c.pending_count() / c.events / c.events_since(seq) / c.take_events()
c.vm() / c.summary() / c.to_dict() / c.to_json()
```

失败原因：`invalid_mode`、`unknown_from/to`、`unknown_text_key`、`no_route`、
`out_of_range`、`occluded`、`jammed`、`node_unavailable`、`link_disabled`；
到达时丢包 → `packet_lost`（确定性 hash 抽样，无随机源）。
`send` 成功即生成 `SENT`；`tick` 到 `arrive_t` 时生 `DELIVERED` 或 `FAILED`。

### 3.3 事件 schema `comms_event.v1`

```text
{schema,seq,t,kind(SENT|DELIVERED|FAILED),
 delivery_id,from,to,from_name,to_name,mode,
 text_key,text,reason,path[],relay_count,latency_s,
 shadow:true,writes_v15:false,writes_track_table:false}
```

`text` 在发送时由 TextLibrary 解析（含动态 from/to/mode/content）；
失败事件用 `COMMS_FAILED` 模板 + `{reason_text}`。

## 4　独立文本库 TextLibrary

### 4.1 数据结构

```json
{
  "text_key": "ORDER_ISSUED",
  "template": "[{from} 至 {to}]-[{mode}]-[{content}]",
  "channel": "order|comms|*",
  "mode": "LD|LR|RDO|IR|VIS|空=不限",
  "speaker_role": "command",
  "listener_role": "escort",
  "template_by_role": {"command": "... {content} ..."},
  "variants": ["首次...", "重复..."],
  "priority": 0
}
```

- 选择：同 text_key 多条目按 `channel`/`mode`/`speaker_role`/`listener_role`
  过滤，`priority` 高者；`template_by_role` 优先，其次 `variants` 轮换，再次
  `template`。同一事件可多模板（首次/重复/失败/紧张度），本骨架实现变体轮换。
- 变量：`{from}` `{to}` `{mode}` `{content}` `{delay}` `{reason_text}`
  以及上下文任意键；**缺变量/未知 text_key 返回 ok=false**（DbC，不静默）。
- `from/to` 解析：优先上下文 `from/to`，否则 `from_name/from_id/from_role`；
  实际实体名/角色由调用方传入；服务内**不硬编码舰名/对白**。
- API：

```gdscript
var lib = CommsService.TextLibrary.new()
lib.add_entry({...}); lib.add_entries([...])
lib.has(key) / lib.keys()
lib.select(key, ctx) -> {ok,text,text_key,template,from,to,mode,from_role,to_role}
lib.render_template(template, vars) -> {ok,text,missing[]}
lib.to_dict()  # JSON：keys/entry_count/errors/warnings
```

- OrderService/CommsService 均可注入自定义 `TextLibrary`；`add_default_text` 可关。
- 示例模板（`COMMS_SENT`/`COMMS_DELIVERED`/`COMMS_FAILED`/`COMMS_RELAYED`、
  `ORDER_*`）只作最小演示；测试内容/名称由 probe 提供。

## 5　DbC（Design by Contract）

| 入口 | Preconditions | Postconditions / Invariants |
| --- | --- | --- |
| `OrderService.create_draft` | action/issuer/targets 非空 | 唯一 order_id、DRAFT、history/事件追加 |
| `issue` | 状态 DRAFT | ISSUED；事件文本；不推进物理/不执行 |
| `tick` | dt>=0、时间单调 | 只推进传输/入队/过期；EXECUTING 不自动 DONE |
| `authorize` | 状态 QUEUED/PENDING/DELIVERED；授权人/钩子允许 | AUTHORIZED 或 REJECTED；不执行 |
| `begin_execute` | AUTHORIZED 或未授权需求的 QUEUED | EXECUTING；不自动完成 |
| `complete` | EXECUTING | DONE + result；重复操作报错 |
| `abort/reject` | 未终态 | ABORTED/REJECTED；后续 tick 不执行 |
| `CommsService.send` | 节点存在、mode 合法、text_key 存在 | SENT 或 FAILED；不伪造投递 |
| `tick` | dt>=0 | DELIVERED/FAILED；pending 清理；JSON 事件 |
| TextLibrary.select | key 存在、模板变量齐全 | 文本/上下文一致；缺变量/缺 key 报错 |

所有错误写 `errors/warnings` 并返回 `{ok:false,reason}`；没有静默吞错。

## 6　最小整合流程

```gdscript
var comms = CommsService.new({...})
var orders = OrderService.new({"comms": comms, "entities": {...}})
var d = orders.create_draft("set_destination", "a", ["b"], {}, {"mode": "RDO"})
orders.issue(d.order.order_id)
orders.tick(0.0)          # ISSUED → TRANSMITTING
orders.tick(2.5)          # comms 送达 → QUEUED/PENDING（不自动授权）
orders.authorize(oid, "a")
orders.begin_execute(oid)
orders.complete(oid)
```

## 7　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/order_comms_probe.gd
# ORDER COMMS PROBE RESULT: PASS=137 FAIL=0
# ORDER COMMS PROBE OK（退出码 0）
```

覆盖（137 checks）：
- **文本库**：动态 from/to/mode/content、角色模板、variants 轮换、缺 key/缺变量、
  JSON；
- **通信**：直连发送/延迟/DELIVERED、LD/LR/RDO/IR/VIS 五模式、VIS 超距、
  中继路径/relay_count、遮挡、干扰、节点损坏、无路由、未知 key、非法 mode、
  丢包到达失败、事件 schema、JSON；
- **命令**：DRAFT→ISSUED→TRANSMITTING→DELIVERED→PENDING_EFFECT→QUEUED→
  AUTHORIZED→EXECUTING→DONE 全状态序列；延迟、tick 长时间不自动执行、
  撤销、过期 STALE、auth hook 拒绝、require_authorizer、未授权不可执行、
  非法转移、事件文本动态；
- **整合**：OrderService↔CommsService 投递/延迟送达、comms 失败→order REJECTED；
- **JSON/确定性/不写**：两实例相同操作 VM 逐字节一致；text library/JSON；
  writes track_table/v15=false。

## 8　边界 / 未完成

- 本任务不接 UI/HUD/bridge/state/world；不写 V15/TrackTable。
- 不实现物理/轨道/遮挡几何/链路质量仿真：距离/遮挡/干扰由调用方传入；
  丢包为确定性 hash 抽样，不是随机信道仿真。
- ROE 仅 `auth_check` Callable 钩子，不实现四档 ROE/自动降级/武器授权；
  这些留给后续阶段。
- 通信只支持单中继（A→R→B）；多跳/带宽排队/加密解密/COMINT 未实现。
- 文本库 variants 只做轮换/角色模板；未做 cooldown/优先级队列/多语言资源包；
  `speaker_role/listener_role` 仅选择匹配，不作为完整关系系统。
- 存档恢复：VM/事件 JSON 可序列化，但未实现 save/load 在途命令/通信。
- 命令事件按状态迁移产生；同一秒多命令顺序由调用顺序/order_id 决定（确定），
  未接入固定 tick 排序器。
- 未跑全量回归；只单次跑本 probe。
