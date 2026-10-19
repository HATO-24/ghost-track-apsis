class_name V2World
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 世界状态容器（纯数据；UI 只能通过只读 view-model 或明确命令方法修改）
#
#   容器：实体 / 航迹 / 选中 / 时间 / 图层 / 命令 / 证据 / 事件流
#   只读查询：vm_* 系列返回普通 Dictionary，UI 不需要碰内部对象。
#   数据来源：V2Scenario（V2 schema 或 v15 迁移），规则来自 content/*.json。
#   本类不做传感器数学、不做渲染、不模拟武器。
#
#   V2-CORE-2（V2-3 第一关端到端）追加：
#     perform_action（7 个支持动作 → 观测/状态）、prelude_*、start_evidence/任务推进、
#     open_decision/choose_ending/submit_report/end_summary/restart、自动时间线（story events/radio）、
#     mission flag 联动。时间在前置航行完成/任务结束时会冻结（不自动做玩家识别动作）。
# ═══════════════════════════════════════════════════════════════════

signal state_changed(reason: String)
signal log_event(kind: String, text: String)
signal track_changed(track_id: String, reason: String)
signal order_changed(order_data: Dictionary)
signal evidence_changed(id: String, state: String)
signal flow_changed(reason: String)

const TRACK_RULES_PATH := "res://content/track_rules.json"
const MAX_EVENT_LOG := 256

var scenario: V2Scenario = null
var entities: Array[V2Entity] = []
var by_id: Dictionary = {}
var own_id := ""
var selected_id := ""
var t := 0.0
var layers := {
	"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true,
}

var tracks: V2TrackTable = null
var orders: V2Orders = null
var evidence: Dictionary = {}
var evidence_policy: Dictionary = {}
var phase_context := ""          # mission 可写入当前阶段 kind，供动作/UI 过滤
var errors: Array[String] = []
var warnings: Array[String] = []
var events: Array = []
var radio: Array = []

# —— V2-CORE-2 流程状态 ——
var mission = null               # V2Mission（不写类型标注：避免与 mission.gd 的循环依赖）
var mission_auto := true         # advance() 时自动推进一格任务阶段（false 时由 UI 调 advance_mission）
var prelude: Dictionary = {}     # 前置航行状态（route/window/execute/skip）
var flow: Dictionary = {}        # decision / report / end / consequence
var flow_flags: Dictionary = {}  # 流程 flag（自动同步给 mission）
var civilians_evacuated := false
var audit_count := 0
var story_events_data: Array = []   # 时间线事件（story.events）
var story_radio_data: Array = []    # 时间线通信（story.radio_lines）
var _fired_events: Dictionary = {}
var _fired_radio: Dictionary = {}

# ── 场景装载 ─────────────────────────────────────────────────────

func load_scenario(s: V2Scenario) -> bool:
	errors.clear()
	warnings.clear()
	events.clear()
	radio.clear()
	t = 0.0
	scenario = s
	if s == null:
		errors.append("load_scenario: scenario 为空")
		return false
	for e in s.errors:
		errors.append(String(e))
	for w in s.warnings:
		warnings.append(String(w))
	_load_entities(s)
	_load_tracks(s)
	_load_orders(s)
	_load_evidence(s)
	_init_flow(s)
	# 自动化钩子（headless 探针/截图）：DSH_SKIP_PRELUDE=1 时跳过前置航行，时间立即可流动。
	if OS.get_environment("DSH_SKIP_PRELUDE") == "1" and prelude_open():
		prelude_skip()
	sync_entities()
	selected_id = own_id
	if selected_id != "":
		state_changed.emit("select")
	state_changed.emit("load")
	push_log(("load"), "场景装载：%s · entities=%d tracks=%d phases=%d migrated=%s" % [
		s.id, entities.size(), tracks.count() if tracks != null else 0,
		s.phases.size(), str(s.migrated)])
	if mission != null:
		mission.attach_scenario(s)
	return errors.is_empty()

func _load_entities(s: V2Scenario) -> void:
	entities.clear()
	by_id.clear()
	own_id = ""
	for e in s.entities:
		entities.append(e)
		by_id[e.id] = e
	if by_id.has(s.own_entity_id):
		own_id = s.own_entity_id
	if own_id == "":
		for e in entities:
			if "own" in e.tags or "own_fleet" in e.tags:
				own_id = e.id
				break
	if own_id == "":
		for e in entities:
			if e.side == "friend":
				own_id = e.id
				break
	if own_id == "" and entities.size() > 0:
		own_id = entities[0].id
		warnings.append("世界装载：无己方实体，默认选中第一实体 " + own_id)

func _load_tracks(s: V2Scenario) -> void:
	var rule_errors: Array = []
	var rules := V2TrackTable.load_rules(TRACK_RULES_PATH, rule_errors)
	for e in rule_errors:
		errors.append(String(e))
	tracks = V2TrackTable.new(rules)
	for raw_seed in s.initial_tracks:
		if raw_seed is Dictionary:
			tracks.seed(raw_seed, t)
	for e in tracks.errors:
		errors.append("track: " + String(e))

func _load_orders(s: V2Scenario) -> void:
	orders = V2Orders.new(s.orders_config)
	if not orders.order_changed.is_connected(_on_order_changed):
		orders.order_changed.connect(_on_order_changed)

func _load_evidence(s: V2Scenario) -> void:
	evidence.clear()
	evidence_policy = s.evidence_policy.duplicate(true)
	for raw_id in s.evidence_defs.keys():
		var id := String(raw_id)
		var def: Dictionary = (s.evidence_defs[id] as Dictionary).duplicate(true)
		evidence[id] = {
			"id": id,
			"label": String(def.get("label", id)),
			"duration_s": float(def.get("duration_s", 0.0)),
			"shuttle": bool(def.get("shuttle", false)),
			"flags_on_done": (def.get("flags_on_done", []) as Array).duplicate(),
			"risk": String(def.get("risk", "")),
			"start_text": String(def.get("start_text", "")),
			"done_text": String(def.get("done_text", "")),
			"state": "unknown",
			"started_t": -1.0,
			"done_t": -1.0,
			"def": def,
		}

## 初始化流程状态（前置航行 / 决策 / 报告 / 时间线 / flag），全部来自场景数据。
func _init_flow(s: V2Scenario) -> void:
	flow = {
		"decision_open": false, "decision": {}, "decision_t": -1.0,
		"report": {}, "report_open": false, "report_available": false,
		"ended": false, "fire_release": false, "consequence": "", "ending": {},
		"reputation": s.reputation_base(),
	}
	flow_flags.clear()
	civilians_evacuated = false
	audit_count = 0
	_fired_events.clear()
	_fired_radio.clear()
	story_events_data = s.story_events()
	story_radio_data = s.story_radio()
	var pd := s.prelude_data()
	var enabled := s.prelude_enabled() and not pd.is_empty()
	prelude = {
		"open": enabled,
		"executed": false,
		"step": 0,
		"route": "",
		"window": "",
		"confirmed": false,
		"dv_spent_ms": 0.0,
		"data": pd,
		"title": String(pd.get("title", "前置航行 / PRELUDE")),
		"body": String(pd.get("body", "")),
		"routes": (pd.get("routes", []) as Array).duplicate(true),
		"windows": (pd.get("windows", []) as Array).duplicate(true),
	}
	if mission != null:
		phase_context = String(mission.kind)

func _on_order_changed(order_data: Dictionary) -> void:
	order_changed.emit(order_data)
	state_changed.emit("order")
	var oid := String(order_data.get("id", ""))
	var st := String(order_data.get("state", ""))
	push_log("order", "命令 %s · %s → %s%s" % [oid, String(order_data.get("action", "")), st,
		("（%s）" % String(order_data.get("reason", ""))) if String(order_data.get("reason", "")) != "" else ""])

# ── 旧 V2-0 兼容查询 ─────────────────────────────────────────────

func selected() -> V2Entity:
	return by_id.get(selected_id)

func own() -> V2Entity:
	return by_id.get(own_id)

func entity(eid: String) -> V2Entity:
	return by_id.get(eid)

func visible_entities() -> Array[V2Entity]:
	var out: Array[V2Entity] = []
	for e in entities:
		if e.side == "unknown" and not bool(layers.get("contacts", true)):
			continue
		out.append(e)
	return out

# ── 选择 ─────────────────────────────────────────────────────────

## 接受实体 id 或航迹 id（虚警/纯回波没有实体，只能按航迹选中）。
func select(id: String) -> bool:
	var known := by_id.has(id) or (tracks != null and tracks.find(id) != null)
	if not known:
		return false
	selected_id = id
	state_changed.emit("select")
	return true

func select_batch(batch: String) -> bool:
	for e in entities:
		if e.id == batch or e.batch == batch:
			return select(e.id)
	return false

func selected_entity() -> V2Entity:
	var e: V2Entity = by_id.get(selected_id)
	if e != null:
		return e
	if tracks != null:
		var tr := tracks.find(selected_id)
		if tr != null and tr.entity_id != "":
			return by_id.get(tr.entity_id)
	return null

func selected_track() -> V2Track:
	if tracks == null:
		return null
	var tr := tracks.find(selected_id)
	if tr != null:
		return tr
	var e: V2Entity = by_id.get(selected_id)
	if e != null:
		return tracks.find_by_entity(e.id)
	return null

func track_for(id: String) -> V2Track:
	if tracks == null:
		return null
	var tr := tracks.find(id)
	if tr != null:
		return tr
	return tracks.find_by_entity(id)

# ── 时间推进 / 图层 / 日志 ───────────────────────────────────────

## 推进世界时间：自动时间线 + 证据任务 + 命令队列 + 航迹衰减 + 任务阶段。
## 前置航行未完成 / 任务已结束时冻结时间（dt 被忽略，返回 frozen=true）。
func advance(dt: float) -> Dictionary:
	var out := {"orders": [], "tracks": [], "events": [], "radio": [], "tasks": [], "phase": {}, "frozen": false}
	if dt <= 0.0:
		return out
	var frozen := _time_frozen()
	if frozen:
		out["frozen"] = true
		return out
	t += dt
	out["events"] = _tick_timeline_events()
	out["radio"] = _tick_timeline_radio()
	out["tasks"] = _tick_evidence_tasks()
	if orders != null:
		out["orders"] = orders.tick(t)
	if tracks != null:
		out["tracks"] = tracks.expire(t)
	sync_entities()
	for raw in (out["tracks"] as Array):
		var tr: Dictionary = raw
		track_changed.emit(String(tr.get("track_id", "")), "decay")
		push_log("track", "航迹 %s 等级衰减 L%d → L%d" % [
			String(tr.get("track_id", "")), int(tr.get("from", 0)), int(tr.get("to", 0))])
	if mission_auto:
		out["phase"] = _advance_mission_once()
	state_changed.emit("tick")
	return out

## 任务/前置航行是否冻结世界时间。
func _time_frozen() -> bool:
	if bool(prelude.get("open", false)) and not bool(prelude.get("executed", false)):
		return true
	if bool(flow.get("ended", false)):
		return true
	return false

## 证据任务推进入口（任务随 world.advance 自动推进；此方法为流程/测试的明确入口，等价 advance）。
func advance_tasks(dt: float) -> Dictionary:
	return advance(dt)

func set_layer(name: String, on: bool) -> void:
	if layers.has(name):
		layers[name] = on
		state_changed.emit("layer")

func push_log(kind: String, text: String) -> void:
	events.append({"kind": kind, "text": text, "t": t})
	while events.size() > MAX_EVENT_LOG:
		events.pop_front()
	log_event.emit(kind, text)

func push_radio(line: Dictionary) -> void:
	var d: Dictionary = line.duplicate(true)
	if not d.has("t"):
		d["t"] = t
	radio.append(d)
	while radio.size() > MAX_EVENT_LOG:
		radio.pop_front()
	state_changed.emit("radio")

func recent_events(n := 8) -> Array:
	var out: Array = []
	var start := maxi(0, events.size() - n)
	for i in range(start, events.size()):
		out.append((events[i] as Dictionary).duplicate(true))
	return out

func recent_radio(n := 8) -> Array:
	var out: Array = []
	var start := maxi(0, radio.size() - n)
	for i in range(start, radio.size()):
		out.append((radio[i] as Dictionary).duplicate(true))
	return out

# ── 航迹/观测 ────────────────────────────────────────────────────

## 融合一条观测（sim 层产出，core 只消费）。返回 V2Track。
func ingest(obs: Dictionary) -> V2Track:
	if tracks == null:
		errors.append("ingest: 世界未装载航迹表")
		return null
	var tr := tracks.ingest(obs, t)
	if tr != null:
		sync_entities()
		track_changed.emit(tr.id, "observation")
		state_changed.emit("observation")
	return tr

func observe_entity(entity_id: String, obs: Dictionary) -> V2Track:
	var o: Dictionary = obs.duplicate(true)
	o["entity_id"] = entity_id
	return ingest(o)

func observe_track(track_id: String, obs: Dictionary) -> V2Track:
	var o: Dictionary = obs.duplicate(true)
	o["track_id"] = track_id
	return ingest(o)

## 脚本/剧情设定身份（例如光学分类后判可疑）；与等级分开。
func set_track_identity(id: String, kind: String, details: Dictionary = {}) -> bool:
	var tr := track_for(id)
	if tr == null:
		return false
	tr.set_identity(kind, details, t)
	sync_entities()
	track_changed.emit(tr.id, "identity")
	state_changed.emit("identity")
	return true

func set_track_level(id: String, level: int, note := "") -> bool:
	if tracks == null:
		return false
	var tr := track_for(id)
	if tr == null:
		return false
	tracks.set_level(tr.id, level, t, note)
	sync_entities()
	track_changed.emit(tr.id, "level")
	state_changed.emit("level")
	return true

## 把航迹等级/身份/威胁同步到实体快照（V2-0 UI 兼容层，逻辑仍以航迹为准）。
func sync_entities() -> void:
	if tracks == null:
		return
	for e in entities:
		var tr := tracks.find_by_entity(e.id)
		if tr == null and e.batch != "":
			tr = tracks.find(e.batch)
		if tr == null:
			tr = tracks.find(e.id)
		if tr == null:
			continue
		e.track_level = tr.level
		e.identity = tr.identity_kind
		e.threat = tr.threat

# ── 命令 ─────────────────────────────────────────────────────────

## 发预命令：校验动作可用性后创建 PRE_ORDER（不推进时间、不入队）。
func issue_order(action_id: String, target_id := "", params: Dictionary = {}) -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var actor := own()
	if actor == null:
		return {"ok": false, "reason": "无己方实体（actor 为空）"}
	var target: V2Entity = by_id.get(target_id)
	var tr := track_for(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	if target == null and tr == null:
		return {"ok": false, "reason": "目标不存在: " + target_id}
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var eval := V2Actions.available_one(action_id, actor, target, tr, ctx)
	if eval.is_empty():
		return {"ok": false, "reason": "未知动作: " + action_id}
	if not bool(eval.get("available", false)):
		# 本舰能力不足时，命令可由舰队内可执行该动作的平台承接（如 IFF 由远地点执行）。
		var alt := _find_fleet_actor(action_id, target, tr, ctx)
		if not alt.is_empty():
			actor = alt.get("actor", actor)
			eval = alt.get("eval", eval)
	if not bool(eval.get("available", false)):
		return {"ok": false, "reason": String(eval.get("reason", "不可用")),
			"reason_code": String(eval.get("reason_code", "")), "action": eval}
	var p: Dictionary = params.duplicate(true)
	if not p.has("duration_s"):
		p["duration_s"] = float(eval.get("duration_s", 0.0))
	var o := orders.issue(action_id, target_id, p, actor.id, tr.id if tr != null else "", t)
	push_log("order", "预命令 %s · %s → %s（%s，不推进仿真）" % [o.id, action_id, target_id, actor.display_name()])
	state_changed.emit("order")
	return {"ok": true, "reason": "", "order": o, "action": eval, "actor_id": actor.id}

func authorize_order(order_id: String) -> Dictionary:
	return _order_action("authorize", order_id)

func enqueue_order(order_id: String) -> Dictionary:
	return _order_action("enqueue", order_id)

func transmit_order(order_id: String) -> Dictionary:
	return _order_action("transmit", order_id)

func begin_order(order_id: String) -> Dictionary:
	return _order_action("begin_exec", order_id)

func complete_order(order_id: String) -> Dictionary:
	return _order_action("complete", order_id)

func abort_order(order_id: String, reason := "指挥官撤销") -> Dictionary:
	return _order_action("abort", order_id, reason)

func reject_order(order_id: String, reason := "授权驳回") -> Dictionary:
	return _order_action("reject", order_id, reason)

func abort_latest_order(reason := "指挥官撤销") -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var r := orders.abort_latest(t, reason)
	if bool(r.get("ok", false)):
		state_changed.emit("order")
	return r

func _order_action(method: String, order_id: String, reason := "") -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var r: Dictionary
	match method:
		"authorize":
			r = orders.authorize(order_id, t)
		"enqueue":
			r = orders.enqueue(order_id, t)
		"transmit":
			r = orders.transmit(order_id, t)
		"begin_exec":
			r = orders.begin_exec(order_id, t)
		"complete":
			r = orders.complete(order_id, t, reason)
		"abort":
			r = orders.abort(order_id, t, reason)
		"reject":
			r = orders.reject(order_id, t, reason)
		_:
			r = {"ok": false, "reason": "未知命令操作: " + method}
	state_changed.emit("order")
	return r

func order_of(order_id: String) -> V2Orders.Order:
	return orders.find(order_id) if orders != null else null

# ── 证据 / 取证任务 ──────────────────────────────────────────────

## 开始取证任务。穿梭机任务互斥（遥测/ELINT 等远程任务可并行）。
## 返回 {ok, reason, task}。
func start_evidence(id: String) -> Dictionary:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return {"ok": false, "reason": "未知证据任务: " + id, "task": null}
	var d: Dictionary = ev
	var state := String(d.get("state", ""))
	if state == "done":
		return {"ok": false, "reason": "任务已完成: " + String(d.get("label", id)), "task": d.duplicate(true)}
	if state == "in_progress":
		return {"ok": false, "reason": "任务已在进行: " + String(d.get("label", id)), "task": d.duplicate(true)}
	if bool(d.get("shuttle", false)):
		var busy := _shuttle_task()
		if busy != "":
			return {"ok": false, "reason": "穿梭机占用中（%s），需等待其完成" % String((evidence[busy] as Dictionary).get("label", busy)),
				"task": d.duplicate(true), "busy_with": busy}
	d["state"] = "in_progress"
	d["started_t"] = t
	evidence_change_emit(id, "in_progress")
	push_log("evidence", "开始取证：%s%s" % [String(d.get("label", id)),
		"（穿梭机）" if bool(d.get("shuttle", false)) else ""])
	flow_changed.emit("evidence_start")
	return {"ok": true, "reason": "", "task": d.duplicate(true)}

func evidence_start(id: String) -> bool:
	return bool(start_evidence(id).get("ok", false))

func evidence_complete(id: String) -> bool:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return false
	var d: Dictionary = ev
	if String(d.get("state", "")) == "done":
		return false
	d["state"] = "done"
	d["done_t"] = t
	for raw_flag in (d.get("flags_on_done", []) as Array):
		_set_flag(String(raw_flag), true)
	evidence_change_emit(id, "done")
	push_log("evidence", "证据取得：%s" % String(d.get("label", id)))
	flow_changed.emit("evidence_done")
	return true

## 当前占用的穿梭机任务 id（"" 表示空闲）。
func _shuttle_task() -> String:
	for k in evidence.keys():
		var d: Dictionary = evidence[k]
		if bool(d.get("shuttle", false)) and String(d.get("state", "")) == "in_progress":
			return String(k)
	return ""

## 任务推进：到期的进行中任务自动完成（在 advance 内调用，需 prior t 已推进）。
func _tick_evidence_tasks() -> Array:
	var done: Array = []
	for k in evidence.keys():
		var d: Dictionary = evidence[k]
		if String(d.get("state", "")) != "in_progress":
			continue
		var dur := float(d.get("duration_s", 0.0))
		if dur <= 0.0:
			continue
		var started := float(d.get("started_t", t))
		if t - started >= dur - 1.0e-6:
			if evidence_complete(String(k)):
				done.append({"id": String(k), "label": String(d.get("label", k)),
					"flags": (d.get("flags_on_done", []) as Array).duplicate()})
	return done

func evidence_remaining(id: String) -> float:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return -1.0
	var d: Dictionary = ev
	if String(d.get("state", "")) != "in_progress":
		return 0.0
	return maxf(0.0, float(d.get("duration_s", 0.0)) - (t - float(d.get("started_t", t))))

func evidence_add(id: String) -> bool:
	return evidence_complete(id)

func evidence_change_emit(id: String, new_state: String) -> void:
	state_changed.emit("evidence")
	evidence_changed.emit(id, new_state)

func evidence_count() -> int:
	var n := 0
	for k in evidence.keys():
		if String((evidence[k] as Dictionary).get("state", "")) == "done":
			n += 1
	return n

func can_expose() -> bool:
	var need := int(evidence_policy.get("min_for_expose", 2))
	return evidence_count() >= need

func evidence_ids() -> Array:
	var out: Array = []
	for k in evidence.keys():
		out.append(String(k))
	return out

# ── 只读 view-model（UI 消费）────────────────────────────────────

func vm_state() -> Dictionary:
	var phase := String(mission.phase) if mission != null else ""
	var phase_kind := String(mission.kind) if mission != null else ""
	return {
		"t": t, "scenario_id": scenario.id if scenario != null else "",
		"title": scenario.title if scenario != null else "",
		"own_id": own_id, "selected_id": selected_id, "phase_context": phase_context,
		"phase": phase, "phase_kind": phase_kind,
		"prelude_open": bool(prelude.get("open", false)),
		"prelude_executed": bool(prelude.get("executed", false)),
		"decision_open": bool(flow.get("decision_open", false)),
		"decision_made": not (flow.get("decision", {}) as Dictionary).is_empty(),
		"report_submitted": not (flow.get("report", {}) as Dictionary).is_empty(),
		"ended": bool(flow.get("ended", false)),
		"fire_release": bool(flow.get("fire_release", false)),
		"civilians_evacuated": civilians_evacuated,
		"time_frozen": _time_frozen(),
		"audit_flag": bool(flow.get("report", {}).get("audit_flag", false)),
		"entity_count": entities.size(),
		"track_count": tracks.count() if tracks != null else 0,
		"order_count": orders.orders.size() if orders != null else 0,
		"evidence_count": evidence_count(),
		"evidence_total": evidence.size(),
		"can_expose": can_expose(),
		"layers": layers.duplicate(true),
		"migrated": scenario.migrated if scenario != null else false,
		"flags": flow_flags.duplicate(true),
		"errors": errors.duplicate(), "warnings": warnings.duplicate(),
	}

## 接触列表行（航迹 + 实体资料合并；UI 不写死批号）。
func vm_contacts() -> Array:
	var out: Array = []
	if tracks == null:
		return out
	for raw in tracks.tracks:
		var tr: V2Track = raw
		var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
		out.append(_contact_row(tr, e))
	return out

func vm_contact(id: String) -> Dictionary:
	var tr := track_for(id)
	if tr == null:
		return {}
	var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
	return _contact_row(tr, e)

func _contact_row(tr: V2Track, e: V2Entity) -> Dictionary:
	var row := {
		"track_id": tr.id, "entity_id": tr.entity_id,
		"batch": (e.batch if e != null and e.batch != "" else tr.id),
		"level": tr.level, "level_name": tr.level_name(), "level_label": tr.level_label(),
		"identity": tr.identity_kind, "identity_label": tr.identity_label(),
		"threat": tr.threat, "stale": tr.stale, "age_s": tr.age_s,
		"bearing_deg": tr.bearing_deg, "range_km": tr.range_km,
		"bearing_only": tr.is_bearing_only(), "sources": tr.sources.duplicate(),
		"quality": tr.quality, "observation_count": tr.observation_count,
		"selected": tr.id == selected_id or (e != null and e.id == selected_id),
		"tags": tr.tags.duplicate(), "notes": tr.notes.duplicate(),
	}
	if e != null:
		row["name"] = e.name
		row["name_en"] = e.name_en
		row["class"] = e.cls
		row["role"] = e.role
		row["side"] = e.side
		row["faction"] = e.faction
		row["kind"] = e.kind
		row["has_entity"] = true
	else:
		row["name"] = "无实体接触"
		row["name_en"] = ""
		row["class"] = ""
		row["role"] = ""
		row["side"] = "unknown"
		row["faction"] = ""
		row["kind"] = "contact"
		row["has_entity"] = false
	return row

func vm_selected() -> Dictionary:
	if selected_id == "":
		return {}
	var tr := selected_track()
	if tr != null:
		var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
		return _contact_row(tr, e)
	var e2: V2Entity = selected_entity()
	if e2 != null:
		return {"track_id": "", "entity_id": e2.id, "batch": e2.display_batch(),
			"name": e2.name, "class": e2.cls, "side": e2.side, "level": e2.track_level,
			"identity": e2.identity, "threat": e2.threat, "has_entity": true,
			"selected": true, "capabilities": e2.capabilities.duplicate()}
	return {}

func vm_entity(id: String) -> Dictionary:
	var e: V2Entity = by_id.get(id)
	if e == null:
		return {}
	var d: Dictionary = e.to_dict()
	var tr: V2Track = tracks.find_by_entity(e.id) if tracks != null else null
	d["track"] = tr.to_dict() if tr != null else {}
	return d

## 目标可用动作（右栏/右键菜单直接用）。舰队内其它平台能执行的动作也会标为可用，
## 并给出 actor_id/actor_name（UI 可显示“由远地点号执行”）。
func vm_actions(target_id: String) -> Array:
	var actor := own()
	var target: V2Entity = by_id.get(target_id)
	var tr := track_for(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var out := V2Actions.available(actor, target, tr, ctx)
	if actor == null:
		return out
	for i in range(out.size()):
		var a: Dictionary = out[i]
		if bool(a.get("available", false)):
			a["actor_id"] = actor.id
			a["actor_name"] = actor.display_name()
			continue
		if not bool(a.get("supported", true)):
			continue
		var alt := _find_fleet_actor(String(a.get("id", "")), target, tr, ctx)
		if alt.is_empty():
			continue
		var ev: Dictionary = (alt.get("eval", {}) as Dictionary).duplicate(true)
		var alt_actor: V2Entity = alt.get("actor", null)
		ev["actor_id"] = alt_actor.id if alt_actor != null else ""
		ev["actor_name"] = alt_actor.display_name() if alt_actor != null else ""
		ev["by_fleet"] = true
		out[i] = ev
	return out

func vm_orders() -> Array:
	return orders.snapshot() if orders != null else []

func vm_orders_summary() -> Dictionary:
	return orders.summary() if orders != null else {}

func vm_evidence() -> Array:
	var out: Array = []
	for k in evidence.keys():
		var d: Dictionary = (evidence[k] as Dictionary).duplicate(true)
		d.erase("def")
		var state := String(d.get("state", ""))
		d["remaining_s"] = evidence_remaining(String(k))
		var dur := float(d.get("duration_s", 0.0))
		if state == "in_progress" and dur > 0.0:
			d["progress"] = clampf(1.0 - evidence_remaining(String(k)) / dur, 0.0, 1.0)
		elif state == "done":
			d["progress"] = 1.0
		else:
			d["progress"] = 0.0
		d["color"] = "amber" if state == "in_progress" else ("ph" if state == "done" else "dim")
		out.append(d)
	return out

func vm_layers() -> Dictionary:
	return layers.duplicate(true)

func vm_tracks() -> Array:
	return tracks.summary() if tracks != null else []

## 完整只读快照（调试/存档/探针）。
func vm_snapshot() -> Dictionary:
	return {
		"state": vm_state(),
		"contacts": vm_contacts(),
		"orders": vm_orders(),
		"evidence": vm_evidence(),
		"tracks": vm_tracks(),
		"flow": vm_flow(),
		"recent_events": recent_events(16),
		"recent_radio": recent_radio(8),
	}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：自动时间线
#   story.events / story.radio_lines 按 t 触发一次；type=="decision" 的事件自动打开决策。
#   不做任何自动识别动作（教学门控：等级只能由玩家 perform_action / 外部观测推进）。
# ═══════════════════════════════════════════════════════════════════

func _tick_timeline_events() -> Array:
	var fired: Array = []
	for i in range(story_events_data.size()):
		if _fired_events.has(i):
			continue
		var raw = story_events_data[i]
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var due := float(ev.get("t", 0.0))
		if t + 1.0e-9 < due:
			continue
		_fired_events[i] = true
		var typ := String(ev.get("type", "event"))
		var text := String(ev.get("text", ""))
		push_log("timeline:" + typ, text)
		var item := {"t": due, "fired_t": t, "type": typ, "text": text}
		fired.append(item)
		if typ == "decision":
			open_decision()
	return fired

func _tick_timeline_radio() -> Array:
	var fired: Array = []
	for i in range(story_radio_data.size()):
		if _fired_radio.has(i):
			continue
		var raw = story_radio_data[i]
		if not (raw is Dictionary):
			continue
		var line: Dictionary = raw
		if t + 1.0e-9 < float(line.get("t", 0.0)):
			continue
		_fired_radio[i] = true
		var d: Dictionary = line.duplicate(true)
		radio.append(d)
		while radio.size() > MAX_EVENT_LOG:
			radio.pop_front()
		fired.append(d.duplicate(true))
	if not fired.is_empty():
		state_changed.emit("radio")
	return fired

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：V2Mission 联动
#   - attach_mission：绑定后阶段条件可读 world；flow flag 自动同步给 mission。
#   - advance 内自动推进一格（mission_auto，可由 UI 关闭）；advance_mission 供显式推进。
# ═══════════════════════════════════════════════════════════════════

func attach_mission(m) -> void:
	mission = m
	if mission == null:
		return
	mission.attach_world(self)
	if scenario != null:
		mission.attach_scenario(scenario)
	_sync_mission_flags()
	phase_context = String(mission.kind)
	state_changed.emit("mission")
	flow_changed.emit("mission_attach")

func _set_flag(name: String, value := true) -> void:
	flow_flags[name] = value
	if name == "civilians_evacuated":
		civilians_evacuated = bool(value)
	if mission != null:
		mission.set_flag(name, value)

func _sync_mission_flags() -> void:
	if mission == null:
		return
	for k in flow_flags.keys():
		mission.set_flag(String(k), bool(flow_flags[k]))

func _advance_mission_once() -> Dictionary:
	if mission == null:
		return {"ok": false, "reason": "未绑定 mission"}
	var r = mission.advance(t)
	if not (r is Dictionary):
		return {"ok": false, "reason": "任务推进返回异常"}
	var rd: Dictionary = r
	if bool(rd.get("ok", false)):
		phase_context = String(mission.kind)
		state_changed.emit("phase")
		flow_changed.emit("phase")
		push_log("phase", "任务阶段 → %s（%s）" % [String(mission.phase), String(mission.kind)])
	return rd

## 连续推进最多 steps 格（遇到条件不满足即停止）。返回每步结果。
func advance_mission(steps := 1) -> Array:
	var out: Array = []
	for i in range(maxi(1, int(steps))):
		var r := _advance_mission_once()
		out.append(r)
		if not bool(r.get("ok", false)):
			break
	return out

func mission_snapshot() -> Dictionary:
	if mission == null:
		return {}
	return mission.snapshot(t)

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：前置航行（PRELUDE）
#   数据来自 story.prelude（routes/windows/confirm/execute/done_comm）；
#   执行前世界时间冻结；执行/跳过后置 prelude_executed，时间开始流动。
# ═══════════════════════════════════════════════════════════════════

func prelude_open() -> bool:
	return bool(prelude.get("open", false)) and not bool(prelude.get("executed", false))

func prelude_state() -> Dictionary:
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	var route := String(prelude.get("route", ""))
	var window := String(prelude.get("window", ""))
	return {
		"open": bool(prelude.get("open", false)), "executed": bool(prelude.get("executed", false)),
		"step": int(prelude.get("step", 0)), "route": route, "window": window,
		"confirmed": bool(prelude.get("confirmed", false)),
		"dv_spent_ms": float(prelude.get("dv_spent_ms", 0.0)),
		"title": String(prelude.get("title", "")), "body": String(prelude.get("body", "")),
		"routes": (prelude.get("routes", []) as Array).duplicate(true),
		"windows": (prelude.get("windows", []) as Array).duplicate(true),
		"route_def": _find_def(prelude.get("routes", []), route),
		"window_def": _find_def(prelude.get("windows", []), window),
		"confirm_text": String(data.get("confirm_text", "")),
		"execute_text": String(data.get("execute_text", "")),
		"can_execute": int(prelude.get("step", 0)) >= 2,
		"time_frozen": _time_frozen(),
	}

func prelude_choose_route(id: String) -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	var def := _find_def(prelude.get("routes", []), id)
	if def.is_empty():
		return {"ok": false, "reason": "未知目的地: " + id}
	if not bool(def.get("ok", false)):
		return {"ok": false, "reason": String(def.get("hint", "该目的地不适用")), "route_def": def}
	prelude["route"] = id
	prelude["window"] = ""
	prelude["confirmed"] = false
	prelude["step"] = 1
	push_log("prelude", "前置航行：目的地 %s（Δv %.0f m/s）" % [String(def.get("label", id)), float(def.get("dv_ms", 0.0))])
	flow_changed.emit("prelude_route")
	return {"ok": true, "step": 1, "route_def": def}

func prelude_choose_window(id: String) -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if String(prelude.get("route", "")) == "":
		return {"ok": false, "reason": "先选择目的地"}
	var def := _find_def(prelude.get("windows", []), id)
	if def.is_empty():
		return {"ok": false, "reason": "未知变轨窗口: " + id}
	if not bool(def.get("ok", false)):
		return {"ok": false, "reason": String(def.get("hint", "该窗口不适用")), "window_def": def}
	prelude["window"] = id
	prelude["confirmed"] = false
	prelude["step"] = 2
	push_log("prelude", "前置航行：变轨窗口 %s（Δv %.0f m/s）" % [String(def.get("label", id)), float(def.get("dv_ms", 0.0))])
	flow_changed.emit("prelude_window")
	return {"ok": true, "step": 2, "window_def": def}

func prelude_confirm() -> Dictionary:
	if int(prelude.get("step", 0)) < 2:
		return {"ok": false, "reason": "先选择目的地与变轨窗口"}
	prelude["confirmed"] = true
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	flow_changed.emit("prelude_confirm")
	return {"ok": true, "confirmed": true, "confirm_text": String(data.get("confirm_text", ""))}

func prelude_execute() -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	if String(prelude.get("route", "")) == "" or String(prelude.get("window", "")) == "":
		return {"ok": false, "reason": "未选择目的地与变轨窗口"}
	var route_def := _find_def(prelude.get("routes", []), String(prelude.get("route", "")))
	var window_def := _find_def(prelude.get("windows", []), String(prelude.get("window", "")))
	var dv := float(route_def.get("dv_ms", 0.0)) + float(window_def.get("dv_ms", 0.0))
	prelude["executed"] = true
	prelude["open"] = false
	prelude["step"] = 3
	prelude["confirmed"] = true
	prelude["dv_spent_ms"] = dv
	_set_flag("prelude_executed")
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	for raw in (data.get("done_comm", []) as Array):
		if raw is Dictionary:
			var line: Dictionary = (raw as Dictionary).duplicate(true)
			line["t"] = t
			push_radio(line)
	push_log("prelude", "前置航行执行：点火完成，Δv %.0f m/s（时间开始流动）" % dv)
	flow_changed.emit("prelude_executed")
	state_changed.emit("prelude")
	return {"ok": true, "dv_spent_ms": dv, "execute_text": String(data.get("execute_text", "")),
		"radio_count": (data.get("done_comm", []) as Array).size(), "flags": flow_flags.duplicate(true)}

## 跳过前置航行（默认取第一个可用目的地/窗口，等价于执行）。
func prelude_skip() -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	var route_def := _first_ok(prelude.get("routes", []))
	var window_def := _first_ok(prelude.get("windows", []))
	if route_def.is_empty() or window_def.is_empty():
		return {"ok": false, "reason": "场景未提供可用的目的地/窗口"}
	prelude["route"] = String(route_def.get("id", ""))
	prelude["window"] = String(window_def.get("id", ""))
	var r := prelude_execute()
	r["skipped"] = true
	return r

func _find_def(list_raw, id: String) -> Dictionary:
	for raw in (list_raw as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
			return (raw as Dictionary).duplicate(true)
	return {}

func _first_ok(list_raw) -> Dictionary:
	for raw in (list_raw as Array):
		if raw is Dictionary and bool((raw as Dictionary).get("ok", false)):
			return (raw as Dictionary).duplicate(true)
	return {}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：决策 / 报告 / 结束 / 重开
#   结局与文本全部来自 story（endings/decision_replies/report_*/consequence_fire）。
# ═══════════════════════════════════════════════════════════════════

func open_decision() -> Dictionary:
	if bool(flow.get("decision_open", false)):
		return {"ok": false, "reason": "决策已打开"}
	if not (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "已作出决策"}
	if bool(prelude.get("open", false)) and not bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行未完成"}
	flow["decision_open"] = true
	flow["decision_t"] = t
	_set_flag("decision_open")
	push_log("decision", "决策打开：执行窗口剩余，证据 %d/%d" % [evidence_count(), evidence.size()])
	flow_changed.emit("decision_open")
	state_changed.emit("decision")
	return {"ok": true, "prompt": scenario.decision_prompt() if scenario != null else "",
		"evidence_count": evidence_count(), "can_expose": can_expose(),
		"time_frozen": _time_frozen()}

## 决策选项（UI 覆盖层用）：来自 story.endings + story.fire_option/FIRE 灾难分支。
func vm_decision() -> Dictionary:
	var options: Array = []
	if scenario != null:
		for raw in scenario.endings:
			if not (raw is Dictionary):
				continue
			var e: Dictionary = (raw as Dictionary).duplicate(true)
			var enabled := true
			var reason := ""
			if String(e.get("kind", "")) == "EXPOSE" and not can_expose():
				enabled = false
				reason = "证据不足（%d/%d 件）" % [evidence_count(), int(evidence_policy.get("min_for_expose", 2))]
			e["enabled"] = enabled
			e["reason"] = reason
			options.append(e)
		var fire_raw = scenario.story.get("fire_option", null)
		var fire: Dictionary = {}
		if fire_raw is Dictionary:
			fire = (fire_raw as Dictionary).duplicate(true)
		else:
			fire = {"kind": "FIRE", "label": "武器释放 / FIRE",
				"hint": "授权武器释放：灾难分支，将造成储罐区二次火灾与平民伤亡。"}
		fire["enabled"] = true
		fire["reason"] = ""
		options.append(fire)
	return {
		"open": bool(flow.get("decision_open", false)),
		"prompt": scenario.decision_prompt() if scenario != null else "",
		"options": options,
		"evidence_count": evidence_count(),
		"can_expose": can_expose(),
		"decision": (flow.get("decision", {}) as Dictionary).duplicate(true),
		"reply": (((flow.get("decision", {}) as Dictionary).get("reply", {}) as Dictionary)).duplicate(true),
		"consequence": String(flow.get("consequence", "")),
		"fire_release": bool(flow.get("fire_release", false)),
	}

func choose_ending(kind: String) -> Dictionary:
	var k := kind.strip_edges().to_upper()
	if not bool(flow.get("decision_open", false)):
		return {"ok": false, "reason": "决策未打开（先 open_decision）", "kind": k}
	if not (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "已作出决策", "kind": k}
	var ending: Dictionary = {}
	if k == "FIRE":
		ending = {"kind": "FIRE", "code": "F", "label": "武器释放 / FIRE"}
	else:
		if scenario == null:
			return {"ok": false, "reason": "无场景数据", "kind": k}
		ending = scenario.ending_by_kind(k)
		if ending.is_empty():
			return {"ok": false, "reason": "未知结局: " + k, "kind": k}
	if k == "EXPOSE" and not can_expose():
		return {"ok": false, "reason": "证据不足（%d/%d 件），无法曝光" % [
			evidence_count(), int(evidence_policy.get("min_for_expose", 2))],
			"kind": k, "evidence_count": evidence_count()}
	var reply: Dictionary = {}
	if scenario != null:
		reply = (scenario.decision_replies().get(k, {}) as Dictionary).duplicate(true)
	flow["decision"] = {
		"kind": k, "code": String(ending.get("code", "")), "label": String(ending.get("label", k)),
		"hint": String(ending.get("hint", "")), "chosen_t": t, "ending": ending.duplicate(true),
		"reply": reply.duplicate(true),
	}
	flow["ending"] = ending.duplicate(true)
	flow["decision_open"] = false
	_set_flag("decision_made")
	if k == "FIRE":
		flow["fire_release"] = true
		flow["consequence"] = scenario.consequence_text() if scenario != null else ""
		_set_flag("fire_release")
	if not reply.is_empty():
		var line: Dictionary = reply.duplicate(true)
		line["t"] = t
		push_radio(line)
	push_log("decision", "指挥官决策：%s%s" % [k, "（武器释放/灾难分支）" if k == "FIRE" else ""])
	flow_changed.emit("decision")
	state_changed.emit("decision")
	return {"ok": true, "kind": k, "ending": ending, "reply": reply,
		"fire_release": bool(flow.get("fire_release", false)), "consequence": String(flow.get("consequence", ""))}

func report_state() -> Dictionary:
	var dec: Dictionary = (flow.get("decision", {}) as Dictionary)
	var kind := String(dec.get("kind", ""))
	var report: Dictionary = (flow.get("report", {}) as Dictionary)
	var fakes: Dictionary = scenario.report_fake() if scenario != null else {}
	return {
		"available": (not kind.is_empty()) and report.is_empty(),
		"submitted": not report.is_empty(),
		"ending_kind": kind,
		"prompt": String(scenario.story.get("report_event", "")) if scenario != null else "",
		"options": [
			{"mode": "truth", "label": "如实提交 / TRUTH", "hint": "按实际决策与证据提交内部事后报告。"},
			{"mode": "fake", "label": "伪造记录 / FALSIFY", "hint": "修改报告正文；被发现将留下 AUDIT FLAG。"},
		],
		"audit_flag": bool(report.get("audit_flag", false)),
		"report": report.duplicate(true),
		"fake_available": fakes.has(kind),
		"recommend": String((scenario.report_recommend() as Dictionary).get(kind, "")) if scenario != null else "",
	}

## 提交内部事后报告。truth=false 时置 audit flag（伪造记录）。
func submit_report(truth := true) -> Dictionary:
	if (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "尚未作出决策"}
	if not (flow.get("report", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "报告已提交"}
	var kind := String((flow.get("decision", {}) as Dictionary).get("kind", ""))
	var bodies: Dictionary = scenario.report_bodies() if scenario != null else {}
	var fakes: Dictionary = scenario.report_fake() if scenario != null else {}
	var recs: Dictionary = scenario.report_recommend() if scenario != null else {}
	var body := String(bodies.get(kind, ""))
	var fake_text := String(fakes.get(kind, ""))
	var text := body if truth else (fake_text if fake_text != "" else body)
	var audit := not truth
	var report := {
		"mode": "truth" if truth else "fake", "truth": truth,
		"submitted_t": t, "text": text, "body": body, "fake_text": fake_text,
		"unit": String(scenario.story.get("report_unit", "")) if scenario != null else "",
		"event": String(scenario.story.get("report_event", "")) if scenario != null else "",
		"evidence": String(scenario.story.get("report_evidence", "")) if scenario != null else "",
		"recommend": String(recs.get(kind, "")),
		"audit_flag": audit, "ending_kind": kind,
	}
	flow["report"] = report
	flow["report_open"] = true
	flow["report_available"] = false
	flow["ended"] = true
	if audit:
		audit_count += 1
		_set_flag("audit_flag")
	_set_flag("report_submitted")
	advance_mission(3)
	push_log("report", "内部事后报告提交（%s）%s" % [
		"如实" if truth else "伪造", " · AUDIT FLAG" if audit else ""])
	flow_changed.emit("report")
	state_changed.emit("report")
	return {"ok": true, "report": report.duplicate(true), "audit_flag": audit,
		"mission_phase": String(mission.phase) if mission != null else "", "ended": true}

func end_summary() -> Dictionary:
	var dec: Dictionary = (flow.get("decision", {}) as Dictionary)
	var kind := String(dec.get("kind", ""))
	var report: Dictionary = (flow.get("report", {}) as Dictionary).duplicate(true)
	var data := {
		"ok": not report.is_empty(),
		"t": t,
		"ending_kind": kind,
		"ending_code": String(dec.get("code", "")),
		"ending_label": String(dec.get("label", "")),
		"decision": dec.duplicate(true),
		"report": report,
		"audit_flag": bool(report.get("audit_flag", false)),
		"audit_count": audit_count,
		"evidence_count": evidence_count(),
		"evidence_total": evidence.size(),
		"can_expose": can_expose(),
		"civilians_evacuated": civilians_evacuated,
		"fire_release": bool(flow.get("fire_release", false)),
		"consequence": String(flow.get("consequence", "")),
		"reputation": (flow.get("reputation", {}) as Dictionary).duplicate(true),
		"recommend": String(report.get("recommend", "")),
		"flags": flow_flags.duplicate(true),
		"mission_phase": String(mission.phase) if mission != null else "",
		"mission_kind": String(mission.kind) if mission != null else "",
	}
	if civilians_evacuated and scenario != null:
		var dock = scenario.story.get("av4412_dock", null)
		if dock is Dictionary:
			data["dock_line"] = String((dock as Dictionary).get("report_line", ""))
	if scenario != null:
		data["report_fake_available"] = (scenario.report_fake() as Dictionary).has(kind)
	return data

## 重开：从场景原始数据重新装载（含实体/航迹/证据/时间/流程/mission flags）。
func restart() -> Dictionary:
	if scenario == null:
		return {"ok": false, "reason": "无场景"}
	var m = mission
	var s2 := scenario.clone()
	if s2 == null or not s2.errors.is_empty():
		return {"ok": false, "reason": "场景重载失败", "errors": s2.errors}
	var ok := load_scenario(s2)
	if m != null:
		attach_mission(m)
		m.reset()
		_sync_mission_flags()
		phase_context = String(m.kind)
	push_log("flow", "任务重开：时间/航迹/证据/流程已复位")
	state_changed.emit("restart")
	flow_changed.emit("restart")
	return {"ok": ok, "errors": errors.duplicate(), "warnings": warnings.duplicate(),
		"phase": String(m.phase) if m != null else "", "prelude_open": bool(prelude.get("open", false)),
		"t": t, "evidence_count": evidence_count()}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：perform_action —— 7 个支持动作 → 观测/状态（不伪造 L4）
#   动作可用性仍由 content/actions.json + V2Actions 决定；本方法只在可用时执行，
#   用动作 effect 的支撑级 + 目标真实轨道几何 + 平台传感器参数生成观测。
#   武器类（supported=false）一律返回 unsupported，不产生任何状态。
# ═══════════════════════════════════════════════════════════════════

func perform_action(action_id: String, target_id: String, params: Dictionary = {}) -> Dictionary:
	var tr := track_for(target_id)
	var target: V2Entity = by_id.get(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	var level_before := int(tr.level) if tr != null else (int(target.track_level) if target != null else 0)
	if bool(flow.get("ended", false)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "任务已结束"}
	if prelude_open():
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "前置航行未完成（时间冻结）"}
	var actor := own()
	if actor == null:
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "无己方实体（actor 为空）"}
	if tr == null and target == null:
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "目标不存在: " + target_id}
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var eval := V2Actions.available_one(action_id, actor, target, tr, ctx)
	if eval.is_empty():
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "未知动作: " + action_id}
	if not bool(eval.get("supported", true)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": String(eval.get("reason", "未实现")), "reason_code": "unsupported", "supported": false}
	if not bool(eval.get("available", false)):
		# 本舰能力不足时，按舰队传感器能力找能执行该动作的友军平台（如 IFF 由远地点执行）。
		var alt := _find_fleet_actor(action_id, target, tr, ctx)
		if not alt.is_empty():
			actor = alt.get("actor", actor)
			eval = alt.get("eval", eval)
	if not bool(eval.get("available", false)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": String(eval.get("reason", "不可用")),
			"reason_code": String(eval.get("reason_code", "")), "action_def": eval}
	var result: Dictionary = {}
	match action_id:
		"crossfix":
			result = _act_crossfix(actor, target, tr)
		"radar_illum":
			result = _act_radar(actor, target, tr)
		"radar_track":
			result = _act_radar(actor, target, tr)
		"model_ident":
			result = _act_optical(actor, target, tr)
		"optical_channel":
			result = _act_optical(actor, target, tr)
		"iff_query":
			result = _act_iff(actor, target, tr)
		"ir_channel":
			result = _act_ir(actor, target, tr)
		_:
			return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
				"reason": "动作未实现: " + action_id, "reason_code": "unsupported"}
	if not bool(result.get("ok", false)):
		return {"ok": false, "action": action_id, "target_id": target_id,
			"level": int(tr.level) if tr != null else level_before,
			"reason": String(result.get("reason", "不可用")),
			"reason_code": String(result.get("reason_code", "")), "detail": String(result.get("detail", ""))}
	var obs: Dictionary = (result.get("observation", {}) as Dictionary)
	var tr2: V2Track = null
	if not obs.is_empty():
		tr2 = ingest(obs)
	var tr3: V2Track = tr2 if tr2 != null else tr
	var level_after := int(tr3.level) if tr3 != null else level_before
	var order := _record_action_done(action_id, target_id, tr3, actor)
	push_log("action", "动作：%s → %s · L%d %s · %s（执行：%s）" % [
		String(eval.get("label", action_id)), target_id, level_after,
		tr3.level_name() if tr3 != null else "", String(result.get("detail", "")),
		actor.display_name()])
	flow_changed.emit("action")
	state_changed.emit("action")
	return {
		"ok": true, "action": action_id, "action_label": String(eval.get("label", action_id)),
		"target_id": target_id, "level": level_after,
		"actor_id": actor.id, "actor_name": actor.display_name(),
		"level_name": tr3.level_name() if tr3 != null else "",
		"identity": tr3.identity_kind if tr3 != null else "",
		"identity_label": tr3.identity_label() if tr3 != null else "",
		"reason": "", "detail": String(result.get("detail", "")),
		"order_id": order.id if order != null else "",
		"observation_count": tr3.observation_count if tr3 != null else 0,
		"sensor": String(obs.get("sensor", "")),
		"support": int(obs.get("support", 0)),
	}

## 立即动作的命令审计记录（DONE）：让命令队列/日志能追溯玩家做过的识别动作。
func _record_action_done(action_id: String, target_id: String, tr: V2Track,
		actor: V2Entity = null) -> V2Orders.Order:
	if orders == null:
		return null
	var actor_id := own_id
	if actor != null:
		actor_id = actor.id
	var o := orders.issue(action_id, target_id,
		{"immediate": true, "duration_s": 0.0, "tx_delay_s": 0.0, "exec_delay_s": 0.0},
		actor_id, tr.id if tr != null else "", t)
	orders.authorize(o.id, t)
	orders.enqueue(o.id, t)
	orders.transmit(o.id, t)
	orders.begin_exec(o.id, t)
	orders.complete(o.id, t, "即时动作完成")
	return o

# —— 动作实现（观测生成）────────────────────────────────────────

func _act_crossfix(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["ir", "optical", "elint"])
	var rb := _range_bearing(actor, tr, target)
	var obs := _obs_base(actor, tr, target, "crossfix", sensor)
	var notes: Array = ["交叉定位：双平台方位线"]
	if rb.has("range_km") and rb.has("bearing_deg"):
		obs["support"] = 2
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
		obs["bearing_sigma_deg"] = maxf(0.05, float(sensor.get("sigma_bearing_deg", 0.5)))
		obs["range_km"] = float(rb.get("range_km", 0.0))
		obs["range_sigma_km"] = maxf(0.5, float(rb.get("range_km", 0.0)) * 0.03)
		obs["quality"] = 0.75
		notes.append("方位交叉 → L2 定位（σr≈3% R）")
		obs["notes"] = notes
		return {"ok": true, "observation": obs, "detail": "交叉定位 → L2"}
	obs["support"] = 1
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["quality"] = 0.5
	notes.append("无第二方位线：仅刷新方位（不伪造 L2）")
	obs["notes"] = notes
	return {"ok": true, "observation": obs, "detail": "仅方位（无实体/无第二线）"}

func _act_radar(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["radar"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少雷达传感器", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无目标距离/几何数据，雷达无法解算", "reason_code": "no_range"}
	var eff := float(sensor.get("range_km", 30000.0))
	var pd := SensorModel.detection_pd(range_km, eff, 4.0)
	if pd < 0.5:
		return {"ok": false, "reason": "超出雷达探测距离（%.0f km > 有效 %.0f km，Pd=%.2f）" % [range_km, eff, pd],
			"reason_code": "range"}
	var stable := range_km <= float(sensor.get("track_range_km", eff * 0.5))
	var obs := _obs_base(actor, tr, target, "radar", sensor)
	obs["support"] = 2
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	elif tr != null and tr.bearing_deg >= 0.0:
		obs["bearing_deg"] = tr.bearing_deg
	obs["bearing_sigma_deg"] = maxf(0.01, float(sensor.get("sigma_bearing_deg", 0.15)))
	var sigr := maxf(float(sensor.get("sigma_range_floor_km", 0.5)),
		range_km * float(sensor.get("sigma_range_frac", 0.0025)))
	if not stable:
		sigr *= 3.0
	obs["range_km"] = range_km
	obs["range_sigma_km"] = sigr
	obs["quality"] = clampf(pd * (1.0 if stable else 0.4), 0.0, 1.0)
	obs["notes"] = ["雷达照射：" + ("稳定跟踪" if stable else "探测（超出稳定跟踪距离）"),
		"开机即暴露（ELINT 可截获）"]
	return {"ok": true, "observation": obs,
		"detail": "雷达 %s → L2（%.0f km，σr=%.1f km）" % [
			"稳定跟踪" if stable else "探测", range_km, sigr]}

func _act_optical(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_optical(actor)
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少光学传感器（非激光测距）", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无距离数据（需先 L2 定位）", "reason_code": "no_range"}
	var max_km := float(sensor.get("range_km", 15000.0))
	if range_km > max_km:
		return {"ok": false, "reason": "超出光学作用距离（%.0f km > %.0f km）" % [range_km, max_km],
			"reason_code": "range"}
	var obs := _obs_base(actor, tr, target, "optical", sensor)
	obs["support"] = 3
	var cls := {"ship_class": target.cls, "role": target.role, "faction": target.faction,
		"confidence": 0.85}
	if target.meta.has("builder"):
		cls["builder"] = String(target.meta.get("builder", ""))
	obs["classification"] = cls
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["quality"] = 0.8
	obs["notes"] = ["光学凝视 + 数据库比对 → L3 分类", "不给距离解（光学仅方位/分类）"]
	return {"ok": true, "observation": obs,
		"detail": "光学分类 → L3（%s）" % String(cls.get("ship_class", ""))}

func _act_iff(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["iff"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少 IFF 询问机能力", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无距离数据（需先 L2 定位）", "reason_code": "no_range"}
	var max_km := float(sensor.get("range_km", 2000.0))
	if range_km > max_km:
		return {"ok": false, "reason": "超出 IFF 询问距离（%.0f km > %.0f km）" % [range_km, max_km],
			"reason_code": "range"}
	var obs := _obs_base(actor, tr, target, "iff", sensor)
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	var friendly := target != null and (target.side == "friend" or "own_fleet" in target.tags or "own" in target.tags)
	if friendly:
		obs["support"] = 4
		obs["identity"] = {"kind": "friend", "name": target.name, "hull": target.hull,
			"faction": target.faction, "via": "iff", "confidence": 0.9}
		obs["iff_status"] = "friend"
		obs["quality"] = 0.95
		obs["notes"] = ["IFF 应答正确 → 友军（L4 证据）"]
		return {"ok": true, "observation": obs, "detail": "IFF 应答：友军 → L4 证据"}
	var tp := String(target.meta.get("transponder", "")) if target != null else ""
	var status := "faulty_transponder" if tp == "faulty" else "no_reply"
	obs["support"] = 1
	obs["iff_status"] = status
	obs["quality"] = 0.5
	obs["notes"] = ["IFF 无应答 / 应答机故障 → 身份未知（不明≠敌意，不判敌、不升 L4）"]
	return {"ok": true, "observation": obs, "detail": "IFF 无应答：身份未知（不伪造 L4）"}

func _act_ir(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["ir"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少红外传感器", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var obs := _obs_base(actor, tr, target, "ir", sensor)
	obs["support"] = 1
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["bearing_sigma_deg"] = maxf(0.05, float(sensor.get("sigma_bearing_deg", 1.2)))
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	var band := "UNKNOWN"
	if range_km >= 0.0:
		band = SensorModel.ir_range_band(range_km, float(sensor.get("range_km", 60000.0)),
			sensor.get("band_edges", [0.333, 0.667]))
		obs["range_band"] = band
	obs["quality"] = 0.6
	obs["notes"] = ["被动红外：方位线 + 距离档（%s），无距离解 → L1" % band, "不暴露"]
	return {"ok": true, "observation": obs, "detail": "红外通道（方位/档位 %s）" % band}

# —— 动作辅助 ——

func _obs_base(actor: V2Entity, tr: V2Track, target: V2Entity, kind: String, sensor: Dictionary) -> Dictionary:
	var obs := {
		"detected": true, "kind": kind,
		"sensor": String(sensor.get("model", "")),
		"source": (actor.id if actor != null else own_id), "t": t, "quality": 0.5,
	}
	if tr != null:
		obs["track_id"] = tr.id
		if tr.entity_id != "":
			obs["entity_id"] = tr.entity_id
	if target != null and not obs.has("entity_id"):
		obs["entity_id"] = target.id
	return obs

func _range_bearing(actor: V2Entity, tr: V2Track, target: V2Entity) -> Dictionary:
	var geom := _geometry_between(actor, target)
	if not geom.is_empty():
		return geom
	var out := {}
	if tr != null:
		if tr.range_km >= 0.0:
			out["range_km"] = tr.range_km
		if tr.bearing_deg >= 0.0:
			out["bearing_deg"] = tr.bearing_deg
		if out.has("range_km") and tr.range_sigma_km > 0.0:
			out["range_sigma_km"] = tr.range_sigma_km
	return out

## 目标相对执行平台的真实几何（L1 站心 km；来自场景轨道状态，只做换算，不伪造）。
func _geometry_between(actor: V2Entity, target: V2Entity) -> Dictionary:
	if actor == null or target == null:
		return {}
	var rs: Array = (actor.orbit.get("r", []) as Array)
	var rt: Array = (target.orbit.get("r", []) as Array)
	if rs.size() < 3 or rt.size() < 3:
		return {}
	var rel := Vector3(float(rt[0]) - float(rs[0]), float(rt[1]) - float(rs[1]), float(rt[2]) - float(rs[2]))
	var rng := rel.length()
	if rng <= 0.001:
		return {}
	var horiz := sqrt(rel.x * rel.x + rel.y * rel.y)
	return {
		"range_km": rng,
		"bearing_deg": fposmod(rad_to_deg(atan2(rel.x, rel.y)), 360.0),
		"elevation_deg": rad_to_deg(atan2(rel.z, maxf(0.001, horiz))),
		"range_sigma_km": maxf(0.5, rng * 0.01),
	}

## 按能力类型找平台传感器（型号参数来自保留的 SensorModel 型号库；缺数据时给保守回退）。
func _actor_sensor(actor: V2Entity, types: Array) -> Dictionary:
	if actor == null:
		return {}
	var ship_key := String(actor.meta.get("ship_key", actor.id))
	for raw in (actor.meta.get("sensors", []) as Array):
		var model := String(raw)
		if model == "":
			continue
		var s: Dictionary = SensorModel.rack_sensor(ship_key, model)
		if s.is_empty():
			continue
		var stype := String(s.get("type", ""))
		if stype in types:
			return s
	return {}

func _actor_optical(actor: V2Entity) -> Dictionary:
	if actor == null:
		return {}
	var ship_key := String(actor.meta.get("ship_key", actor.id))
	for raw in (actor.meta.get("sensors", []) as Array):
		var model := String(raw)
		if model == "":
			continue
		var s: Dictionary = SensorModel.rack_sensor(ship_key, model)
		if s.is_empty():
			continue
		if String(s.get("type", "")) == "optical" and String(s.get("subtype", "")) != "lidar":
			return s
	if actor.has("sensor.optical"):
		return {"model": "", "type": "optical", "range_km": 15000.0, "refresh_s": 8.0,
			"sigma_bearing_deg": 0.05}
	return {}

## 舰队内找能执行该动作的友军平台（本舰能力不足时使用，如 IFF 由远地点执行）。
## 返回 {actor, eval}；没有可用平台返回 {}。
func _find_fleet_actor(action_id: String, target: V2Entity, tr: V2Track,
		ctx: Dictionary) -> Dictionary:
	for e in entities:
		if e == null or e.id == own_id:
			continue
		if e.side != "friend":
			continue
		var ev := V2Actions.available_one(action_id, e, target, tr, ctx)
		if bool(ev.get("available", false)):
			return {"actor": e, "eval": ev}
	return {}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：流程 view-model（UI 覆盖层）
# ═══════════════════════════════════════════════════════════════════

func vm_prelude() -> Dictionary:
	return prelude_state()

func vm_report() -> Dictionary:
	return report_state()

func vm_end() -> Dictionary:
	return end_summary()

## 流程总览：UI 根据 prelude.open/decision.open/report.submitted/ended 决定显示哪层。
func vm_flow() -> Dictionary:
	return {
		"t": t,
		"time_frozen": _time_frozen(),
		"prelude": prelude_state(),
		"decision": vm_decision(),
		"report": report_state(),
		"end": end_summary(),
		"mission": mission_snapshot(),
		"flags": flow_flags.duplicate(true),
		"civilians_evacuated": civilians_evacuated,
		"audit_count": audit_count,
	}


func _with(d: Dictionary, key: String, value) -> Dictionary:
	var o: Dictionary = d
	o[key] = value
	return o
