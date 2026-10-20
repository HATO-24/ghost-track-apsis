# 完整游戏-阶段3E · PortService 港口/对接/资源服务

> 任务 完整游戏-阶段3E（task-138）。工程 `game_v17`。
> 新文件（不改其他；不做物理/UI；未 commit）：
> - `scripts/core/port_service.gd`
> - `tests/port_service_probe.gd`（`PASS=212 FAIL=0`）
> - 本文件
> 只做港口流程/资源状态机；不渲染 UI、不写 world/V15/物理。

## 1　定位

- 每个 `request` 是一条**手动推进**的港口事务（对接/拖曳/穿梭机），带状态机、
  预约窗、许可、进近走廊、泊位/船坞/拖船/燃料资源。
- 不自动许可、不自动对接、不自动开始/完成服务、不自动离港；
  `tick(dt)` 只推进时间/窗口/资源补充/过期，不改变服务状态（`no_auto` 全 0）。
- 资源按港统计，并汇总全局容量；队列按优先级+创建时间。

## 2　配置 schema

```json
{
  "ports": [{
    "id": "p1", "name": "L1 Meridian",
    "berths": ["B1", "B2"], "drydock_slots": 1, "tugs": ["TUG1"],
    "fuel_capacity_t": 1000.0, "fuel_available_t": 1000.0,
    "windows": [{"id":"W1","open_t":0.0,"close_t":1000.0}],
    "corridor": "C1",
    "require_permit": true,
    "services": ["refuel","repair","tow","shuttle"],
    "accepting": true, "hold_on_capacity": true,
    "fuel_refill_per_s": 0.0
  }]
}
```

- 校验：ports 非空、id/berth/tug 唯一、drydock_slots>=0、fuel 0..capacity、窗口 open<close、
  services 属于 `refuel/repair/tow/shuttle`；非法配置 `ready=false`。
- 默认配置含 2 个示例港（L1 Meridian / L4-02 Hammer）。

## 3　请求状态机（手动）

```
REQUESTED ──permit──► GRANTED ──approach──► APPROACH ──dock──► DOCKED
   │  └──deny/window──► DENIED                    │                │
   └──hold──► HOLD ──permit──► GRANTED/DENIED     │                ├──refuel/repair──► SERVICING
                                                  │                │                   │
                                                  │                └──undock──► DEPARTED
                                                  └──finish_service──► DOCKED
```

- `REQUESTED→GRANTED`：permit 校验许可/窗口/容量；分配泊位（dock/shuttle）或拖船（tow）。
- 容量不足且 `hold_on_capacity=true` → `HOLD`（进入队列）；false → `DENIED`。
- `window_not_open`/`no_permit`/`port_not_accepting` 等失败 reason；失败不改状态。
- `GRANTED→APPROACH`：窗口必须开；记录走廊。
- `APPROACH→DOCKED`：需已分配泊位（tow 在 dock 时分配泊位）。
- `DOCKED→SERVICING`：refuel/repair；`finish_service` 显式完成回 `DOCKED`（不自动）。
- `DOCKED→DEPARTED`：undock；释放泊位/拖船/船坞。
- 每请求 `history[]` 记录 `{t,status,reason}`；终态（DENIED/DEPARTED）不可再操作。

## 4　资源 / 队列

| 资源 | 字段/行为 |
| --- | --- |
| 泊位 | `berths[]`，permit 时占用；undock 释放；容量满 HOLD/DENIED |
| 船坞槽 | `drydock_slots`，repair 时占用 +1；finish_service 释放 |
| 拖船 | `tugs[]`，tow permit 时占用；undock 释放 |
| 燃料 | `fuel_available_t`，refuel 扣除；`fuel_refill_per_s` 由 tick 补充（上限 capacity） |
| 预约窗 | `windows[]`；`window_status()`；tick 后 permit 在闭窗时 HOLD `window_not_open` |
| 许可 | `require_permit=true` 时 `opts.clearance` 非空才可 grant |
| 走廊 | `corridor`；approach 返回值/事件记录 |
| 全局容量 | `summary().resources` / `resource_summary()` 汇总泊位/船坞/拖船/燃料 |

- 队列：`queue(port_id)` 返回 REQUESTED/HOLD，按 priority 降序、created_t 升序；不自动授予。
- 时刻过期：`request(..., opts.expire_in=秒)` → `tick` 到期后 `DENIED window_expired`。

## 5　API

| API | 说明 |
| --- | --- |
| `PortService.new(cfg)` / `setup(cfg)` / `validate_config(cfg)` | 创建/校验 |
| `request(kind, ship_id, port_id, opts={})` | kind ∈ dock/tow/shuttle；返回 REQUESTED（不自动许可） |
| `permit(request_id)` | 许可/重评估；REQUESTED/HOLD → GRANTED/DENIED/HOLD；分配资源 |
| `deny(request_id, reason)` | 显式拒绝（释放已占资源） |
| `approach(request_id)` / `dock(request_id)` / `undock(request_id)` | 进近/对接/离港 |
| `services(request_id="", port_id="")` | 可用服务列表（available/locked/reason/label_key） |
| `refuel(request_id, amount_t)` / `repair(request_id, opts={})` | 服务开始（DOCKED→SERVICING；扣燃料/占船坞） |
| `finish_service(request_id)` | 显式完成服务（SERVICING→DOCKED，不自动） |
| `tow(ship_id, port_id, opts)` / `shuttle(ship_id, port_id, opts)` | 创建拖曳/穿梭机请求 |
| `tick(dt)` | 推进时间/窗口/燃料补充/过期；不自动执行（`no_auto`） |
| `window_status(port_id)` / `queue(port_id)` / `resource_summary(port_id="")` / `port_summary(port_id)` | 查询 |
| `get_request(id)` / `summary()` / `vm()` / `to_dict()` / `to_json()` | 只读 |
| `events` / `events_since(seq)` / `take_events()` / `bind_event_bus(bus)` | 事件 |
| `save_state()`/`save()` / `load_state(json)`/`load(json)` / `check_contracts()` | 内存存档/DbC |

- 失败统一 `{ok:false, reason, errors}`（`wrong_state/invalid_kind/unknown_port/ship_busy/
  no_permit/no_berth/no_tug/no_drydock/insufficient_fuel/window_not_open/window_closed/
  service_unavailable/invalid_amount/invalid_dt/...`），不静默、不部分写入。

## 6　事件（`port_event.v1`）

`port.request_created`、`port.request_granted`、`port.request_denied`、`port.request_held`、
`port.request_expired`、`port.approach`、`port.docked`、`port.service_started`、
`port.service_finished`、`port.departed`；`seq/t/kind/detail/writes_v15:false`。
可选 EventBus 绑定后以同名 type 发布（`source="port_service"`）。

## 7　存档（内存 JSON）

```text
{
  schema:"v17.port_service_save.v1", version:"1.0.0",
  t_s, request_seq, event_seq,
  ports: {port_id: {资源/occupancy/config...}},
  requests: {request_id: 完整 request/history...},
  events[]
}
```

`load_state()` 校验 schema/version/ports/requests/资源（燃料非负、船坞占用合法、状态属于状态机）
后应用；非法 JSON/schema/version/资源/请求状态拒绝且不改当前状态；load 后可继续服务/离港。
不写磁盘，外层可交给 SaveService/GameSession。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/port_service_probe.gd
# V17 PORT PROBE RESULT: PASS=212 FAIL=0（exit 0，只跑一次）
```

覆盖（9 节）：配置/初始/非法配置；request 字段/无自动 grant/ship_busy/queue；
permit 许可/拒绝/HOLD 队列/释放后 grant/port_not_accepting/闭窗/容量满分支；对接全流程与资源占用；
refuel 扣油/服务互斥/维修占船坞/finish/燃料不足/服务不可用；tow 占拖船→dock→释放、shuttle 占泊位；
队列优先级/tick 不自动/过期/燃料补充/全局容量；各阶段 save/load VM 一致+继续+非法拒绝；
事件序列/EventBus/vm JSON/同操作确定性。

## 9　接入 / 边界

- 接入：可由 GameSession/上层调用 `tick`（或用 session 时间同步 t_s）、把 `events` 转 EventBus、
  由 UI 调 API；本服务不引用 GameSession/物理/轨道，不写 world/V15。
- 不做真实泊位几何/进近走廊轨迹/船体物理；资源为抽象计数；无舰船注册表（只按 ship_id 字符串）。
- 不自动许可/对接/服务/离港；所有服务需要显式开始与完成；tick 不改变请求状态（除过期）。
- 无 ROE/战斗/损伤；未接旧场景/HUD/bridge；存档仅内存 JSON；未跑全量回归；未 commit。
