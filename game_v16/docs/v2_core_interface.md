# V2-1 core 接口契约（UI / sim 对接用）

> 状态：V2-CORE-1 实现完成（task-44）。文件：`game_v16/core/*`、`content/*.json`、
> `sim/observation_bridge.gd`、`tests/core_probe.gd`。
> 本文件是 UI（V2-2）与 sim（V2-SENSOR）对接 core 的唯一接口说明。
> 原则：UI 只读 view-model / 明确命令方法；core 不引用 UI、不做传感器数学、不模拟武器。

## 0　装载流程（UI 启动）

```gdscript
var scenario := V2Scenario.load_file("res://content/scenario_l1_v2.json")  # V2 schema
# 或 V2Scenario.load_file("res://content/scenario_l1.json")                # v15 旧场景（自动迁移）

var world := V2World.new()
var ok: bool = world.load_scenario(scenario)     # false 时看 world.errors / world.warnings

var mission := V2Mission.from_scenario(scenario) # 数据驱动阶段
mission.attach_world(world)                      # 进入条件需要读 world 时必须绑定

# 每帧：
world.advance(delta)                             # 推进时间 + 命令队列 + 航迹衰减
mission.advance(world.t)                         # 条件满足才进入下一阶段
```

- `world.errors` 是致命问题（场景/内容/规则校验失败），`world.warnings` 是迁移默认值等提示。
- `V2Mission.new()` 仍可用（无场景的 7 阶段骨架，只保证 V2-0 app.gd 的 TAB 兼容）；
  正式流程必须用 `V2Mission.from_scenario()`。

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
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game_v16 --script res://tests/core_probe.gd
# 末行 V2-1 CORE PROBE RESULT: PASS=277 FAIL=0；退出码 0
# sensor_probe 由 V2-SENSOR 维护（tests/sensor_probe.gd），两者互不引用。
```

## 9　已知边界（V2-1 不做）

- 不做渲染/雷达 TWS/UI（V2-2/V2-3）；不做武器、火控、毁伤（显式 unsupported）。
- `sim/` 的传感器模型（V2RadarModel/V2TwsModel/V2OpticalModel/V2SensorTypes）由 V2-SENSOR 维护；
  core 只通过观测 schema + `sim/observation_bridge.gd` 消费，不反向依赖 sim。
- 迁移默认值（证据门槛 2 / 链路 8s）需要 V2-3 第一关迁移时用 V2 场景显式覆盖。
- 剧情 flag（`prelude_executed/decision_open/decision_made/report_submitted/fire_release`）
  由后续关卡流程置位；V2-1 只定义条件与推进机制。
