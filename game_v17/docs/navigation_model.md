# R4-NAV-CORE-1 · 导航 / 交通管制 / 机动规划模型

> 任务 R4-NAV-CORE-1（task-67）。工程 `game_v17` framework 层。
> **规划模型，不接物理**：路线、许可、机动只产出「计划/许可/状态机」，不修改任何轨道/世界状态；
> 真实地月物理在 R6 接入（schema 不变，只替换节点位置与边成本来源）。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `framework/core/navigation_model.gd`（新） | `V2NavigationModel`：节点/路线候选/交通许可队列/机动状态机/Δv 预算/只读 vm |
| `framework/content/navigation_l1.json`（新） | 8 节点、15 条抽象转移边、3 类路线权重、交通规则、6 种机动、Δv 预算 |
| `tests/nav_probe.gd`（新） | headless probe：372 断言，覆盖内容校验/候选/许可/状态机/预算/JSON/无自动执行/确定性/内容驱动 |
| `docs/navigation_model.md`（本文件） | API、内容 schema、R6 接入接口、边界 |

未修改 `hud.gd` / `plot.gd` / `main.gd` / `state.gd` / `world.gd` / `framework_bridge` / project；未 commit。

## 2　数据模型与口径

- 单位：Δv **m/s**、时间 **s**、距离 **km**、exposure/risk **0..1**（抽象风险，不是传感器实测概率）。
- **节点**（8）：`earth_port`、`geo`、`l1`、`l2`、`l4`、`l5`、`moon_port`、`lunar_leo`；
  字段 `name/kind/position_source/abstract_pos_km/authority/traffic_class/capacity`。
  `position_source` 形如 `cislunar:l1_station` —— 与 `cislunar_explorer/sim/cislunar_model.gd` 的站体 id 对应；
  本模型**不硬加载 cislunar**，由集成层通过 `bind_position_provider(callable)` 注入真实位置。
- **边**（15）：`transfer_type`（high_thrust / low_energy / covert）、`dv_ms`、`duration_s`、
  `exposure`、`risk`、`traffic_required`、`bidirectional`、`corridor`。
  内容示例：
  - 高推力快线：`e_ep_geo_fast`（3,800 m/s / 5,400 s / 暴露 0.55 / 需许可）
  - 低能经济线：`e_ep_geo_econ`（2,600 m/s / 432,000 s / 暴露 0.25 / 无需许可）
  - 隐蔽绕行：`e_ep_l4_cover` / `e_l4_l2_cover` / `e_l2_moon_cover`（暴露 0.05–0.08）
  - 直接地月：`e_ep_moon_direct`（3,900 m/s / 259,200 s / 暴露 0.70）
  这些是**抽象转移成本**，不是轨道积分结果；R6 用真实 Lambert/CR3BP 结果替换 dv/duration 即可。
- **路线 profile**：内容中 `route_limits.profile_weights` 定义 fast（时间 0.7/Δv 0.2/暴露 0.1）、
  economy（Δv 0.7/时间 0.2/暴露 0.1）、covert（暴露 0.55/风险 0.15/Δv 0.1/时间 0.2）。
  `plan_routes` 对每个 profile 在可行路径中按加权归一化分数取最优；优先选可行路径。

## 3　公开 API（`V2NavigationModel`）

```gdscript
# 静态
V2NavigationModel.load_content(path)                  # JSON → Dictionary
V2NavigationModel.validate_content(content)           # Array[String] 错误列表；空=通过
V2NavigationModel.node_ids(content) / list_nodes(content)

# 实例
var nav = V2NavigationModel.new()
nav.setup(content_override := {})                     # true=ready；errors 说明原因
nav.reset()

# 节点位置（只读；provider 可选）
nav.bind_position_provider(func(source, node_id): ...) # R6/集成层注入真实位置
nav.node_position_km(node_id) -> [x,y,z]              # provider 优先，回退 abstract_pos_km
nav.resolve_positions() -> {node_id: [x,y,z]}

# 路线（只规划）
nav.plan_routes(from, to, constraints := {}) -> {
  ok, from, to, constraints, profiles,
  candidates: [fast/economy/covert 三条], recommended
}
# constraints: max_dv_ms / max_duration_s / max_exposure / avoid_traffic /
#              exclude_transfer_types:[...] / max_hops
nav.select_route(candidate_id_or_dict)                # 只写 selected_route
nav.last_routes / nav.selected_route                  # 只读字段

# 交通管制（批准/拒绝/保持/过期；不自动执行）
nav.request_clearance(route := null, window := {}, priority := 3) -> {
  ok, request_id, status(granted/hold/denied), reason, reason_text, position, authority, window, expires_t
}
nav.grant_clearance(request_id) / deny_clearance(request_id, reason) / hold_clearance(request_id, until_t)
nav.clearance_status(request_id) / active_clearance() / active_clearances()
nav.expire_clearances(now := -1.0) -> [expired_ids]
nav.requests / nav.queue                             # 只读字段

# 机动（状态机；不修改轨道物理）
nav.plan_maneuver(kind, target := "", opts := {}) -> {ok, plan_id, plan}
#   kind: hold / approach / retreat / evade / point / burn
#   burn 可用 opts.dv_ms 覆盖（clamp 1..budget_total）
nav.authorize_maneuver(plan_id)   # PRE_ORDER→AUTHORIZED（检查可用 Δv，预留 committed）
nav.queue_maneuver(plan_id, clearance_id := "")  # AUTHORIZED→QUEUED（需要许可的 kind 必须持有效 granted）
nav.execute_maneuver(plan_id)     # QUEUED→EXECUTING
nav.abort_maneuver(plan_id, reason) # 非终态→ABORTED；EXECUTING 按 progress 部分消耗 Δv
nav.step(dt)                      # 推进时间/执行进度/许可过期；不改轨道
nav.budget_vm()                   # total/reserve/used/committed/available/used_ratio/warning/exhausted

# 只读 view-model
nav.vm_navigation() -> {
  schema,id,title,ready,model_kind:"planning_abstract",authoritative:false,t,
  nodes, routes, selected, clearance, clearances, queue,
  planned_maneuvers, budget, limits, events, summary
}
nav.summary() / nav.state_signature() / nav.to_dict()
```

### 3.1　关键语义

- **不自动执行**：`plan_routes` / `select_route` / `request_clearance` / `grant_clearance`
  不创建也不推进任何机动，不消耗 Δv，不改变时间；`execute_maneuver` 必须显式调用，
  且要求 `QUEUED` 前置状态。交通规则 `auto_grant=false`、`auto_execute=false`。
- **交通队列**：`request_clearance` 对低暴露路线直接 `granted`；高暴露路线
  （`exposure ≥ traffic.hold_exposure_threshold`）进入 `hold` 并排队。队列按
  **priority 升序（1 最高）→ request_t → id** 排序；队列满（`max_queue`）只拒绝
  会进入等待队列的 hold 请求，已可 grant 的请求不受影响。
- **拒绝原因**：`unknown_route` / `route_infeasible` / `priority_range` / `window_in_past` /
  `window_closed` / `queue_full` / `authority_denied` / `clearance_required` / `stale_clearance`。
  请求记录始终保留（`requests`），`status` 含 `granted/hold/denied/expired`。
- **许可有效期**：granted 的 `expires_t = granted_t + traffic.validity_s`；hold 的
  `hold_until_t = t + traffic.hold_s`；`step(dt)`/`expire_clearances` 到期转 `expired` 并移出队列。
- **机动状态机**：`PRE_ORDER → AUTHORIZED → QUEUED → EXECUTING → DONE`，
  任意非终态可 `ABORTED`；非法迁移返回 `wrong_state`。`authorize` 预留 Δv（committed），
  `step(dt)` 完成时计入 used 并释放 committed；执行中中断按 progress 消耗部分 Δv。
- **预算**：`available = total − reserve − used − committed`；授权/重规划不改 used；
  执行完成才 used。预算不足 → `dv_budget`（授权阶段拒绝）。
- **位置/物理只读**：节点位置只由 provider/abstract 坐标给出；规划/许可/机动流程不修改位置、
  不调用 provider、不写任何轨道状态；`vm_navigation()` 返回深拷贝，修改返回值不影响模型。

## 4　内容 schema（`navigation_l1.json`）

```
{
  "schema":"navigation.v1", "id":"navigation_l1", "title":...,
  "nodes": { "<id>": {name, kind, position_source, abstract_pos_km:[x,y,z],
                       authority, traffic_class, capacity, notes} },
  "edges": [ {id, from, to, bidirectional, transfer_type, dv_ms, duration_s,
              exposure, risk, traffic_required, corridor, notes} ],
  "route_limits": { max_hops, max_paths, profiles:[fast,economy,covert],
                    profile_weights:{...}, profile_labels:{...}, constraints_default:{...} },
  "traffic": { authority_default, max_queue, priority_range:[1,5], priority_labels:{},
               min_lead_s, window_slot_s, validity_s, hold_s, hold_exposure_threshold,
               auto_grant:false, auto_execute:false, deny_reasons:{...} },
  "maneuvers": { state_order:[...], terminal_states:[DONE,ABORTED],
                 kinds:{ hold:{dv_ms,duration_s,exposure,risk,requires_target,requires_clearance},
                         approach:{...}, retreat:{...}, evade:{...}, point:{...}, burn:{...} } },
  "budget": { dv_total_ms, dv_reserve_ms, warn_ratio, initial_fuel_kg }
}
```

`validate_content` 会检查：schema/id、nodes 非空与 3D 抽象坐标、edges 引用存在/数量、
重复 id、dv/duration/exposure/risk/traffic_required 类型与范围、profiles/weights、
traffic 队列与优先级范围、6 类机动 + 状态顺序、budget 正负关系。probe 用 12 份篡改副本验证拒绝。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/nav_probe.gd
# 末行 NAV PROBE RESULT: PASS=372 FAIL=0 / NAV PROBE OK，退出码 0
```

覆盖（21 节）：
1. 内容 schema/字段/默认自检 + 12 类篡改拒绝；
2. setup / nodes / summary / 未知节点 / 未初始化失败；
3. 位置 provider 绑定/覆盖/清除（抽象坐标回退）；
4. 路线候选 3 类：fast 最短时间、economy 最小 Δv、covert 最低暴露；路径边连通校验；
5. 约束：max_dv / max_duration / max_exposure / avoid_traffic / exclude_transfer_types / max_hops；
6. 规划无自动执行（时间/预算/机动/执行签名不变）；
7. 交通基础：fast→hold、economy→granted、covert→granted（无需许可）；
8. 优先级队列：priority 1 → 3 → 4 排序、vm.queue 顺序/标签；
9. 拒绝原因：priority_range / window_in_past / window_closed / unknown_route / route_infeasible；
10. 手动 grant / deny / hold，重复动作失败；
11. hold 超时、granted 有效期到期 → expired；
12. max_queue=1 → queue_full（内容驱动）；
13. 6 种机动计划、target 校验、burn opts.dv_ms；
14. 状态机 PRE_ORDER→…→DONE、progress、consumed、非法迁移；
15. 中断：排队中断 0 消耗、执行中断按进度部分消耗；
16. 机动 × 许可：burn/evade 无许可拒绝、持 granted 许可排队执行、过期许可失效；
17. 预算：total/reserve/available、授权预留、小预算拒绝、burn clamp；
18. vm 字段/JSON 可序列化/回读、机动状态；
19. 只读：修改 vm 不影响模型；规划/许可/授权不改节点位置/时间/预算；
20. 确定性：两个独立实例同序列 → 相同 vm JSON；
21. 内容驱动：节点名/坐标、边 Δv、预算、机动成本、max_queue 全部来自 JSON 覆盖。

## 6　R6 / 集成接口

1. **位置来源**：R6 或 `cislunar_model.sample(t)` 适配器通过
   `nav.bind_position_provider(func(source, node_id) -> Vector3|Array)` 注入；
   `source` 即内容中的 `cislunar:*` 字符串（可直接映射 `sample(t).stations[].id`）。
   provider 只在 `node_position_km` / `vm_navigation` 被调用，不参与规划副作用。
2. **边成本替换**：R6 用真实 Lambert/CR3BP/低能流形结果生成或更新 `edges` 数据（同 schema）；
   `plan_routes` 不需要改动。
3. **时间推进**：由 core 每帧/每个 sim tick 调 `nav.step(dt)`；只推进许可有效期与机动执行进度，
   不做轨道积分。R6 的轨道积分在独立物理模块中运行，执行完成事件（`maneuver_done`）再交给物理层施加 Δv。
4. **事件总线**：`nav.events` 的 kind（`routes_planned/route_selected/clearance_*/maneuver_*`）
   可直接转发到 core 事件/日志；`vm_navigation()` 供 R4 导航页渲染（routes/selected/clearance/queue/
   planned_maneuvers/budget/limits）。
5. **命令层**：R4 导航页把玩家「确认路线/授权机动」映射到 `select_route`、`authorize_maneuver`、
   `queue_maneuver`（携带许可 id）、`execute_maneuver`；HUD 只读 vm，不直接改模型内部状态。
6. **物理权威**：本模型 `authoritative=false`；R6 接入后由物理世界状态为权威，导航模型只做规划/许可/
   状态机与预算记账；具体边界见 `docs/37` §3/§6。

## 7　限制 / 未完成

- 抽象转移成本：不是轨道积分；边 Δv/时间/暴露/风险来自内容文件，R6 前不保证物理可达性。
- 路线枚举为简单路径 DFS（最多 `max_hops` 条边、`max_paths` 条路径）；不做 A*/连续优化/发射窗口求解。
- 交通管制为规则版：无真实频谱/进近走廊容量模型、无对手伪造许可/ELINT 联动（后续接信息战）。
- 机动只做状态机/预算/时间，不改变轨道、不消耗燃料质量（`initial_fuel_kg` 仅内容占位）。
- 无 UI/HUD 接入（本任务明确不接 HUD）；导航页在 R4-UI 任务接 `vm_navigation`。
- `position_source` 目前指向 cislunar demo id；V17 关卡真实站体 id 在 R6 数据源接入时统一。
- `step(dt)` 的许可过期与机动进度是确定性推进；未做多单位并行仲裁/抢占队列。
