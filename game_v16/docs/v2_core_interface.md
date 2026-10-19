# V2 core 接口契约（UI / sim 对接用）

> 状态：V2-CORE-1（task-44）+ V2-CORE-2（task-47，第一关端到端流程）实现完成。
> 文件：`game_v16/core/*`、`content/*.json`、`sim/observation_bridge.gd`、
> `tests/core_probe.gd`、`tests/flow_probe.gd`。
> 本文件是 UI（V2-3）与 sim（V2-SENSOR）对接 core 的唯一接口说明。
> 原则：UI 只读 view-model / 明确命令方法；core 不引用 UI、不做传感器数学、不模拟武器。

## 0　装载流程（UI 启动）

```gdscript
var scenario := V2Scenario.load_file("res://content/scenario_l1_v2.json")  # V2 schema
# 或 V2Scenario.load_file("res://content/scenario_l1.json")                # v15 旧场景（自动迁移）

var world := V2World.new()
var ok: bool = world.load_scenario(scenario)     # false 时看 world.errors / world.warnings

var mission := V2Mission.from_scenario(scenario) # 数据驱动阶段
world.attach_mission(mission)                    # 绑定后 flow flag 自动同步给 mission

# 每帧：
var out := world.advance(delta)   # 时间线 + 证据任务 + 命令队列 + 航迹衰减 + mission 自动推进一格
# mission 也可由 world.advance_mission(n) 显式推进；mission_auto=false 关闭自动推进。
```

- `world.advance()` 返回 `{orders, tracks, events, radio, tasks, phase, frozen}`；
  `frozen=true` 时世界不推进（前置航行未完成 / 任务已结束）。
- **前置航行门控**：`world.vm_state().prelude_open==true` 时时间冻结，需先走
  `prelude_choose_route/window → prelude_confirm → prelude_execute`（或 `prelude_skip()`）。
  自动化/截图钩子：环境变量 `DSH_SKIP_PRELUDE=1` 会在装载时自动跳过并置 `prelude_executed`。
- `world.errors` 是致命问题（场景/内容/规则校验失败），`world.warnings` 是迁移默认值等提示。
- `V2Mission.new()` 仍可用（无场景的 7 阶段骨架，只保证 V2-0 app.gd 的 TAB 兼容）；
  正式流程必须用 `V2Mission.from_scenario()` + `world.attach_mission()`。

## 1　V2World：容器 + 只读 view-model

容器字段（只读；改动请走方法）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `scenario` | V2Scenario | 来源场景 |
| `entities` / `by_id` | Array[V2Entity] / Dictionary | 实体 |
| `own_id` / `selected_id` | String | 己方 / 当前选中（实体 id 或航迹 id） |
| `t` | float | 世界时间（秒，相对 epoch） |
| `layers` | Dictionary | contacts/labels/predictions/radar/stations/grid |
| `tracks` | V2TrackTable | 航迹表 |
| `orders` | V2Orders | 命令队列 |
| `evidence` | Dictionary | 证据容器（id → {id,label,duration_s,shuttle,state,started_t,done_t}） |
| `evidence_policy` | Dictionary | 例：`{"min_for_expose": 2}` |
| `phase_context` | String | mission 可写入当前阶段 kind，供动作/UI 过滤 |
| `events` / `radio` | Array | 事件流 / 通信流（`push_radio(line)` 写入） |

只读查询（UI 首选，返回普通 Dictionary/Array）：

```gdscript
world.vm_state()            # t/own_id/selected_id/实体数/航迹数/命令数/证据数/can_expose/errors…
world.vm_contacts()         # 接触行数组（航迹 + 实体资料合并）
world.vm_contact("2001")    # 单行（实体 id 或航迹 id 均可）
world.vm_selected()         # 当前选中行（无实体接触也可选）
world.vm_entity("harmattan")# 实体详情 + track 快照
world.vm_actions("2001")    # 目标动作可用性数组（右栏/右键菜单直接渲染）
world.vm_orders()           # 命令快照（含 history/timestamps）
world.vm_orders_summary()   # {total, counts{8态}, pending, queued, executing, config}
world.vm_evidence()         # 证据数组
world.vm_layers() / world.vm_tracks() / world.vm_snapshot()  # 调试/存档
world.recent_events(n) / world.recent_radio(n)
```

接触行字段（`vm_contacts()/vm_contact()/vm_selected()`）：

```
track_id, entity_id, batch, level, level_name(L1..L4 的英文 id), level_label(中文),
identity(身份 id), identity_label(中文), threat, stale, age_s,
bearing_deg, range_km, bearing_only, sources(sensor 型号), quality, observation_count,
name, name_en, "class", role, side, faction, kind, has_entity, selected, tags, notes
```

旧 V2-0 兼容 API 全部保留：`entities/by_id/own_id/selected_id/own()/selected()/entity(id)/
select(id)/select_batch(batch)/visible_entities()/advance(dt)/set_layer()/log→push_log()`；
`V2Entity.track_level/identity/threat` 是由 world 从航迹同步的快照（旧 UI 不用改）。

## 2　V2TrackTable / V2Track：航迹状态机

- 等级：`L0 UNKNOWN → L1 BEARING → L2 POSITION → L3 CLASSIFIED → L4 IDENTIFIED`。
- 等级由观测证据时间戳推：拿到支撑级 S 的观测会刷新 1..S；超过有效期逐级衰减
  （默认 L4 30s / L3 90s / L2 210s / L1 记忆地板，全部在 `content/track_rules.json`）。
- **身份与等级分离**：`track.identity_kind` 独立更新（IFF/光学/剧情），不会直接把等级顶到 L4；
  IFF 无应答 → `unknown`，不自动判敌。
- 批号不写死：航迹 id 来自数据（如 "2001"）或自动分配（`T0001`，前缀/位数在规则里）。

```gdscript
var tr: V2Track = world.track_for("2001")      # 先按航迹 id，再按 entity id
tr.level / tr.level_name() / tr.level_label()  # 1..4 / "BEARING" / "方位"
tr.identity_kind / tr.identity_label()         # 身份与等级分开
tr.bearing_deg / tr.range_km / tr.is_bearing_only()
tr.sources / tr.observers / tr.observation_count / tr.stale / tr.age_s
tr.classification / tr.iff_status / tr.signal_data / tr.notes / tr.tags
tr.to_dict()                                   # 完整快照
```

写入（只走 world / 事件，不让 UI 直接改等级）：
`world.ingest(obs)`、`world.observe_entity(eid, obs)`、`world.observe_track(tid, obs)`、
`world.set_track_identity(id, kind, details)`、`world.set_track_level(id, level, note)`。

### 观测 schema（sim → core）

`world.ingest()` / `V2ObservationBridge.to_core_observation()` 接受：

```
{track_id | entity_id | target_id(可选), sensor, source, kind, t, quality(0–1),
 support(=level_support 1–4, 可缺省由 kind 推),
 bearing_deg, bearing_sigma_deg, range_km, range_sigma_km, range_band,
 classification:{}, identity:{kind?,name?,hull?,faction?,via?,confidence?},
 iff_status, signal:{}, notes:[], detected:bool}
```

- `support` 语义：1=方位、2=定位、3=分类、4=身份；缺省时由规则 `sensor_support[kind]` 推。
- 支撑级会做一致性校验：声称 L2 但无位置 → 降 L1；L3 无分类 → 降 L2；L4 无身份/IFF → 降 L3。
- `quality < min_quality`（默认 0.05）的观测不刷新证据。
- sim 的 `V2RadarModel.step()/scan_now()` 输出 `observations` 数组可直接
  `V2ObservationBridge.scan_to_observations(scan, {"source": "harmattan"})` 转换后 `world.ingest`；
  `V2ObservationBridge.ingest_scan(world, scan, opts)` 是一步版。
- 目标行（组装 sim snapshot 用）：`V2ObservationBridge.target_row(entity, track)`——含
  `id/track_id/entity_id/batch/r/v/orbit/classification{ship_class,role,faction,builder?}`；
  sim 需要实体 id 时用 `entity_id`（`id` 保持航迹 id，上层组装 snapshot 可自行覆盖）。
- TWS 通道映射（v2-sensor 约定，字段见 docs/34 §8.6）：`tws_channel_to_observation(ch, opts)` /
  `tws_channels_to_observations(channels, opts)` / `ingest_tws_channels(world, channels, opts)`；
  只在 `state ∈ {ACQUIRE,TRACK,STARE,FIRE_CONTROL}` 时注入（`kind="radar.tws"`、支撑 L2），
  失锁不注入、降级交给 core 证据有效期；`fire_control{}` 只透传供火控视图，不抬 L3/L4。
  光学锁定由 sim/上层按 `kind="optical.classification"` + `support=3` + `classification` 注入（L3），
  IR 用 `kind="ir"` + `support=1`（L1），两者都不带距离解。

## 3　V2Actions：动作注册表（内容驱动）

动作全部来自 `content/actions.json`（`schema: actions.v1`），core 不写死清单。

```gdscript
var acts := world.vm_actions(target_id)          # 推荐：自带 phase_context
var acts2 := V2Actions.available(actor, target, track, {"phase": "DECISION", "flags": {}})
var one := V2Actions.available_one("radar_illum", actor, target, track)
var def := V2Actions.definition("crossfix")      # 原始定义
```

每项返回：`{id,label,label_en,available,reason,reason_code,requires_all,requires_any,levels,
track_required,max_range_km,supported,duration_s,effect,hint,target_track_id,target_level}`。

- `reason` 在 `available=false` 时必定非空，UI 直接显示；`reason_code` 供灰显逻辑：
  `unsupported / no_actor / no_track / level / capability / no_range / range / phase / flag`。
- 支持动作（内容）：`crossfix / radar_illum / model_ident / radar_track / iff_query /
  optical_channel / ir_channel`；武器类 `fire_control / missile_solve / weapons_hold`
  在内容里 `supported=false`，永远 `available=false`（显式不伪造）。
- 动作定义字段：`requires_all / requires_any / levels(允许等级集合) / track_required /
  max_range_km / phases / requires_flags / forbidden_flags / duration_s / effect / supported`。
- 兼容：`V2Actions.actions_for(actor, target)`（V2-0 app.gd 的两参数用法）仍可用。

## 4　V2Orders：预命令 / 授权 / 队列 / 撤销

状态：`PRE_ORDER → AUTHORIZED → QUEUED → TRANSMITTED → EXECUTING → DONE`
（旁路 `ABORTED` / `REJECTED`）。预命令不推进世界时间、不入队。

```gdscript
var r := world.issue_order("radar_illum", "2001", {})   # 校验动作可用性 → PRE_ORDER
r.ok / r.reason / r.order
world.authorize_order(order_id)   # → AUTHORIZED
world.enqueue_order(order_id)     # → QUEUED
# 之后由 world.advance(dt) 驱动：
#   QUEUED --tx_delay_s--> TRANSMITTED --exec_delay_s/exec_t--> EXECUTING --duration_s--> DONE
world.transmit_order(id) / world.begin_order(id) / world.complete_order(id)
world.abort_order(id, reason)     # 仅执行前可撤；EXECUTING 撤销返回 ok=false + reason
world.reject_order(id, reason)    # 授权阶段驳回 → REJECTED
world.abort_latest_order(reason)
world.order_of(id)                # V2Orders.Order
```

- 延迟来自场景 `orders` 配置（V2 schema）或默认 `{tx_delay_s:8.0, exec_delay_s:0.0}`；
  单条命令可用 `params.exec_delay_s / params.exec_t / params.duration_s` 覆盖。
- `V2Orders.Order`：`state/history/created_t/authorized_t/queued_t/tx_t/exec_t/done_t/
  closed_t/reason/note/to_dict()`；`orders.summary()/snapshot()/pending()/queued()/executing()`。

## 5　V2Mission：数据驱动阶段

```gdscript
var m := V2Mission.from_scenario(scenario)
m.attach(world, scenario)          # 或 attach_world(world) / attach_scenario(scenario)
var r := m.advance(world.t)        # {ok, phase, kind, from, skipped, reason}
m.set_flag("prelude_executed")     # 剧情/流程置位 flag
m.phase / m.kind / m.prompt() / m.snapshot(world.t)
m.is_phase("DECISION")             # 同时匹配 phase id 与 kind
m.can_enter_phase(i, world.t) / m.available_action_ids()
```

- 阶段来自场景 `phases[]`：`id/kind/title/enter/prompt_ref/options_ref/actions/optional`。
  `kind ∈ PRELUDE/READ/COMMAND/DECISION/CONSEQUENCE/REPORT/END`。
- `enter` 条件（数据）：`always / min_t / max_t / flags_all|any|none / evidence_min /
  track_level / order_state / all / any`；未知条件键在场景校验阶段报错。
- `optional: true` 的阶段条件不满足时 `advance` 自动跳过（`r.skipped`），例如开火分支 `consequence`。
- `prompt_ref/options_ref` 指向 `scenario.story` 内的文本路径（`story.decision_prompt`、
  `story.endings` 等）；取不到时 `mission.errors` 记录，不伪造文本。

## 6　V2Scenario：V2 schema 与 v15 迁移

- V2 schema：`"schema": "scenario.v2"`，必有 `id/title/epoch/entities[]/tracks[]/phases[]`；
  可选 `own_entity/datum/story/story_file/endings/evidence/orders/timeline`。
  校验错误逐条带路径写入 `errors`（重复 id、非法 side/kind、悬空 entity_id、level 越界、
  未知进入条件键、缺字段…），不做静默兜底。
- v15 旧场景（`scenario_l1.json`，含 `ships/tracks/sensors/story/false_alarm`）自动迁移：
  - `ships+tracks` → `entities`（实体 id 沿用四位数批号，保持 V1.5 UI/日志兼容），能力由
    按舰传感器架推出（`meta.capability_source = migrated_from_sensor_rack`）；
  - `tracks.r/v` → 航迹种子的 `orbit`（距离/方位由几何换算，不伪造）；
  - `story.evidence_tasks` → `evidence_defs`；`story.endings` → `endings`；
  - `story.prelude/notice/decision/...` → 7 个数据驱动阶段（prompt_ref 指向 story.*）；
  - `false_alarm`（9002 虚警回波）→ 无实体航迹（`tags: [phantom, false_alarm]`）；
  - 默认值（证据门槛 2、命令链路 8s）写入 `warnings`，提示是迁移口径。

## 7　内容文件（数据驱动入口）

| 文件 | schema | 说明 |
| --- | --- | --- |
| `content/scenario_l1_v2.json` | `scenario.v2` | V2 场景：实体/初始航迹/阶段/证据/命令配置，文本引用 story 文件 |
| `content/story_l1.json` | `story.v1` | 第一关文本（自 v15 场景 story 拆出，`story.*` 被 prompt_ref 引用） |
| `content/actions.json` | `actions.v1` | 动作定义 + 能力/等级/距离/阶段/flag 条件 + unsupported 武器类 |
| `content/track_rules.json` | `track_rules.v1` | 等级/衰减/质量门槛/身份分类/观测支撑级映射 |
| `content/scenario_l1.json` | `scenario.v0` | v15 旧场景（迁移测试/回退用，勿改数据结构） |

## 8　测试

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game_v16 --quit
# V2 UI BOOT src=CORE contacts=8 own=1001 … ；UI SELFCHECK checks=20 fail=0

tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game_v16 --script res://tests/core_probe.gd
# V2-1 CORE PROBE RESULT: PASS=277 FAIL=0

tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game_v16 --script res://tests/flow_probe.gd
# V2-CORE-2 FLOW PROBE RESULT: PASS=179 FAIL=0

# sim 侧探针（V2-SENSOR 维护）：sensor_probe 105/0、sensor_bridge_probe 38/0、snapshot_probe 117/0。
# 注意：core 现在在 PRELUDE 未执行时冻结 advance；做老化/时间推进的探针先 world.prelude_skip()
# 或设 DSH_SKIP_PRELUDE=1。
```

## 9　已知边界（V2-CORE-1 不做）

- 不做渲染/雷达 TWS/UI；不做武器、火控、毁伤（显式 unsupported）。
- `sim/` 的传感器模型（V2RadarModel/V2TwsModel/V2OpticalModel/V2SensorTypes）由 V2-SENSOR 维护；
  core 只通过观测 schema + `sim/observation_bridge.gd` 消费，不反向依赖 sim。
- 剧情 flag（`prelude_executed/decision_open/decision_made/report_submitted/fire_release`）
  由 V2-CORE-2 流程置位；V2-CORE-1 只定义条件与推进机制。

## 10　V2-CORE-2：第一关端到端流程 API（UI 覆盖层用）

UI 覆盖层判断顺序（全部来自 `world.vm_flow()`，不要自己改流程状态）：

```
prelude.open            → PRELUDE 覆盖层（目的地/变轨窗口/执行）
decision.open           → DECISION 覆盖层（HOLD/EVACUATE/EXPOSE/FIRE；EXPOSE 看 enabled/reason）
report.available        → REPORT 覆盖层（truth/fake）
end.ok / flow.ended     → END 归档页
否则                    → 游戏界面（战术/接触/动作/证据/命令/通信）
```

### 10.1　前置航行 PRELUDE

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `world.vm_prelude()` | Dictionary | open/executed/step/route/window/confirmed/dv_spent_ms/title/body/routes/windows/route_def/window_def/confirm_text/execute_text/can_execute/time_frozen |
| `world.prelude_choose_route(id)` | `{ok,reason,step,route_def}` | 目的地；错误选择返回 `ok=false` + story.hint（不推进步骤） |
| `world.prelude_choose_window(id)` | `{ok,reason,step,window_def}` | 变轨窗口；需先选目的地 |
| `world.prelude_confirm()` | `{ok,confirm_text}` | 二次确认（可选，execute 不强制） |
| `world.prelude_execute()` | `{ok,dv_spent_ms,execute_text,radio_count,flags}` | 执行点火：置 `prelude_executed`，写离港通信，时间开始流动 |
| `world.prelude_skip()` | 同 execute + `skipped=true` | 自动化/跳过 |
| `world.prelude_open()` | bool | 是否处于前置航行 |

### 10.2　动作 perform_action（7 个支持动作）

`world.perform_action(action_id, target_id, params={})` →

```
{ok, action, action_label, target_id, level, level_name, identity, identity_label,
 actor_id, actor_name, detail, reason, reason_code, order_id, observation_count,
 sensor, support}
```

- 动作可用性仍由 `content/actions.json` + `V2Actions.available_one` 决定（等级/能力/距离/阶段/flag）；
  本舰能力不足时自动选舰队内能执行的友军平台（例如 IFF 由远地点执行，`actor_id/actor_name` 指明）。
- 观测用动作 effect 支撑级 + 目标真实轨道几何（`entity.orbit.r`）+ 平台传感器参数生成；
  `level` 为动作后航迹等级。武器类（fire_control/missile_solve/weapons_hold）返回
  `ok=false, reason_code="unsupported"`，不产生命令/不改等级。
- 每个成功动作在命令队列留一条 `DONE` 审计记录（`order_id`）。
- 不伪造 L4：IFF 仅对友方给 L4 身份；2001/9001 等无应答只到未知/可疑。

### 10.3　证据任务

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `world.start_evidence(id)` | `{ok,reason,task}` | 开始取证；穿梭机任务互斥（reason 写占用），远程任务可并行 |
| `world.advance(dt)` / `world.advance_tasks(dt)` | `{tasks,...}` | 任务随世界时间自动完成（到 duration_s） |
| `world.evidence_remaining(id)` | float | 剩余秒数 |
| `world.vm_evidence()` | Array | id/label/duration_s/shuttle/state/started_t/done_t/remaining_s/progress |
| `world.evidence_count()` / `world.can_expose()` | int / bool | 证据数 / 是否达 `evidence.policy.min_for_expose` |
| `world.evidence_complete(id)` | bool | 调试/剧情直接完成 |

任务完成效果来自内容：`evidence.items[].flags_on_done`（例：evacuation → `civilians_evacuated`）；
v15 旧场景迁移时 `evacuation` 自动带该 flag。

### 10.4　决策 / 报告 / 结束 / 重开

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `world.open_decision()` | `{ok,prompt,evidence_count,can_expose}` | 打开决策（时间线 `type="decision"` 事件也会自动调用） |
| `world.vm_decision()` | `{open,prompt,options,evidence_count,can_expose,decision,reply,consequence}` | options 含 `kind/label/hint/enabled/reason`；EXPOSE 证据不足时 `enabled=false` |
| `world.choose_ending(kind)` | `{ok,kind,ending,reply,fire_release,consequence,reason}` | kind ∈ HOLD/EVACUATE/EXPOSE/FIRE；EXPOSE 需 `can_expose`；FIRE 置灾难分支 |
| `world.vm_report()` | `{available,prompt,options,audit_flag,report,fake_available,recommend}` | 报告覆盖层 |
| `world.submit_report(truth)` | `{ok,report,audit_flag,ended,mission_phase}` | truth=false → 伪造记录 + `audit_flag` / `audit_count`，文本优先 story.report_fake |
| `world.vm_end()` / `world.end_summary()` | Dictionary | 结局/报告正文/审计/证据/平民撤离/灾难后果/reputation/flag |
| `world.restart()` | `{ok,phase,prelude_open,t,evidence_count}` | 从场景原始数据重载世界、复位流程、mission.reset() |
| `world.mission_snapshot()` | Dictionary | mission.snapshot（phase/kind/prompt/flags/history/phases） |

流程 flag（自动同步给 mission）：`prelude_executed / decision_open / decision_made /
fire_release / report_submitted / audit_flag / civilians_evacuated`。
阶段进入条件与提示/选项文本全部来自 `scenario.phases[]` + `story.*`（不写死结局）。

### 10.5　自动时间线

`world.advance(dt)` 会：

- 触发 `story.events` / `story.radio_lines` 中 `t <= world.t` 的条目（各一次；event kind = `timeline:<type>`）；
  `type="decision"` 的事件自动 `open_decision()`；
- 推进证据任务；自动推进一格 mission（`mission_auto` 可关）；推进命令队列与航迹衰减；
- **不自动做任何识别动作**（教学门控：等级只能由玩家 `perform_action` 或外部 sim 观测推进）。

UI 读取：`world.recent_events(n)` / `world.recent_radio(n)` / `world.vm_state()`（含
phase/phase_kind/prelude_open/decision_open/report_submitted/ended/time_frozen/audit_flag）。
