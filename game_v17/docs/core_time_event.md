# 完整游戏-阶段2A · TimeService / EventBus / WorldState 内核

> 任务 完整游戏-阶段2A（task-118）。工程 `game_v17`。
> 新文件（不改其他；不接旧场景/UI；未 commit）：
> - `scripts/core/time_service.gd`
> - `scripts/core/event_bus.gd`
> - `scripts/core/world_state.gd`
> - `tests/core_time_event_probe.gd`（`PASS=197 FAIL=0`）
> - 本文件
> 不实现物理/UI/命令；不写旧场景。

## 1　TimeService（`v17.time_service.v1`）

### 1.1　状态/API

| 字段 / API | 说明 |
| --- | --- |
| `t_s` / `epoch_s` / `scale` | 仿真时间（s）/ epoch / 时标倍率 |
| `paused` / `mode()` | 暂停 / `running|paused` |
| `docked` / `docked_s` | 港内状态；`docked_s` 仅在 docked 时随 tick 推进 |
| `window_{active,duration_s,left_s,expired}` | 时间窗（倒计时；过期不阻止 tick） |
| `tick(dt) -> Dictionary` | 推进：`dt` 必须有限且 >=0；乘以 scale；`scaled>max_dt` 裁剪并 warning；暂停时 t 不变；**单调** |
| `pause()` / `resume()` / `set_scale()` / `set_docked()` | 控制（非法参数拒绝） |
| `set_window(duration_s)` / `clear_window()` | 时间窗 |
| `seek(new_t_s)` | 只允许向前（回退/负值拒绝，保证单调语义） |
| `now_s()` / `now_days()` / `epoch_abs_s()` | 查询 |
| `event_time()` | `{schema,t_s,t_days,epoch_s,epoch_abs_s,scale,paused,mode}`（供 EventBus） |
| `check_invariants()` / `snapshot()` / `to_dict()` / `reset()` | DbC/只读快照 |

### 1.2　DbC / 不变量

- 前置：`tick(dt)` dt 有限且 >=0；`setup` 参数（t_s/docked_s/scale/max_dt/window）有限合理；
  `docked_s <= t_s`；`scale >=0`；`max_dt_s >0`。
- 后置不变量：`t_s>=0`、`docked_s>=0`、`docked_s<=t_s`、`epoch_s` 有限、`scale>=0`、
  `window_left_s∈[0,duration]`。
- 失败：`ok=false` + `errors/contract_errors`；不改变 t（负/NaN tick 拒绝）。
- 失败不静默：`push_error` 记录；`snapshot().invariants` 返回当前检查。

## 2　EventBus（`v17.event.v1` / bus schema `v17.event_bus.v1`）

事件字段：`id/type/t/source/target/payload/text_key`（输出 + `seq/schema`）。

| API | 说明 |
| --- | --- |
| `publish(event) -> {ok,event,seq,dispatched,errors}` | 校验后分配单调 `seq`/自动 `id`（`evt-%06d`）；同步派发订阅者 |
| `validate_event(dict) -> errors` | 必需 type/source/t 有限非负/payload 对象/target 字符串/重复 id |
| `subscribe(type_prefix, cb) -> {token}` | 空前缀=全部；`entity` 匹配 `entity.*` |
| `unsubscribe(token)` | 未知 token 返回 ok=false |
| `recent(count, opts)` / `filter_events(opts)` | 按 seq 顺序；opts：`type`（前缀）/`type_exact`/`source`/`target`/`since_t`/`limit` |
| `last_event()` / `event_by_id()` / `count()` / `current_seq()` | 查询 |
| `check_invariants()` / `snapshot()` / `to_dict()` / `reset()` | DbC/只读快照 |

- 确定性：同发布序列 → 同 seq/同事件/id；环形缓冲上限 1000（丢最旧 + warning）；
  `snapshot().events` 深拷贝。
- 边界：bus **不直接写 world/V15**；订阅者只收只读副本；派发同步、按订阅顺序。

## 3　WorldState（`v17.world_state.v1`）

| API | 说明 |
| --- | --- |
| `WorldState.new({writer?,time?,bus?})` | writer 默认 `"world"`；可传 `""` 表示未认领；time 为 TimeService 引用（只读钟） |
| `claim_writer(token)` / `release_writer(token)` / `current_writer()` | **单一写者约束**：writer 为空或相同才可认领；冲突/错误 token 拒绝 |
| `apply(event, token) -> {ok,version,event_ref,...}` | 仅白名单事件；**先全量校验、后写入**；writer 必须匹配；postcondition 失败回滚 |
| `entity(id)` / `entity_count()` / `has_entity` / `entities_sorted()` | 只读实体 |
| `event_refs_since(seq)` | 已应用事件引用（seq/id/type/t/source/target/version） |
| `clock_t_s()` | 若注入 TimeService 则取其 t；否则最近事件 t |
| `check_invariants()` / `snapshot()` / `to_dict()` / `reset()` | DbC/只读快照 |

白名单事件（`ALLOWED_TYPES`）：
`entity.spawn`（payload.entity{id,kind,name?,pos_km?,vel_kmps?,flags?}）、`entity.despawn`、
`entity.move`（payload.pos_km[3], vel_kmps?）、`entity.flag`（payload.key/value 标量）、
`entity.rename`（payload.name）、`world.note`（不改实体）。

### 3.1　DbC

- 前置：`writer` 已认领且 token 匹配；事件类型在白名单；type/t/source/target/payload 合法；
  spawn 实体 id 合法且不重复；move/flag/rename/despawn 目标存在；位置/速度有限三元数组；
  flag key 非空、value 标量。
- 后置：实体键值一致、pos/vel 有限、flags 对象、version 非负；失败则恢复 apply 前
  entities/version/event_refs 并报 `postcondition_failed`。
- 拒绝事件无副作用（version/实体不变）；`errors/contract_errors` 记录；snapshot 只读深拷贝。

## 4　组合用法（示例；本任务不接旧场景）

```gdscript
var time = TimeService.new()
var bus = EventBus.new()
var world = WorldState.new({"writer": "world", "time": time})

time.tick(10.0)
var pub = bus.publish({"type": "entity.spawn", "t": time.now_s(), "source": "world",
    "payload": {"entity": {"id": "apsis", "kind": "ship"}}})
if pub.ok:
    world.apply(pub.event, "world")   # bus 不自动写 world；由写者显式应用
```

- 事件只是数据；是否应用由 WorldState 写者决定（bus 无 world 引用）。
- 时间/事件/世界三者独立可测；未接旧 V15/HUD/transit。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/core_time_event_probe.gd
# V17 CORE TIME EVENT PROBE RESULT: PASS=197 FAIL=0（exit 0，只跑一次）
```

覆盖（10 节）：TimeService 基础（tick 单调/负与 NaN 拒绝/tick0/epoch/event_time/不变量）；
控制（暂停/恢复/scale/max_dt 裁剪/docked 时间/非法 setup）；时间窗倒计时/过期/seek 单向/JSON/reset；
EventBus 发布（合法/显式 id/自动 id/重复 id/非法字段/顺序）；过滤（recent/前缀/exact/source/target/
since_t）+ 订阅/取消/派发顺序；WorldState 基础（spawn/move/flag/rename/note/despawn/snapshot 只读）；
单写者（claim 冲突/未认领/错误 token/release）；拒绝（重复/未知/非法 id/NaN/非白名单/缺 source/NaN t
且无副作用）；跨模块（time 引用、bus 发布不写 world、world 只接受白名单）；JSON/确定性（三内核
同输入快照一致）。

## 6　边界 / 未完成

- 只提供内核；**不实现物理/命令/传感器/UI**，不接旧场景/HUD/transit，不写旧 world/V15。
- 事件类型白名单仅 WorldState 用；EventBus 允许任意 type（由写者决定是否合法）。
- payload 仅做最小结构校验（object）；不做嵌套 schema 递归（后续可复用 `schema_loader`）。
- 无持久化/存档；无多线程；时间/事件均为内存确定性顺序。
- 未跑全量回归；未 commit。
