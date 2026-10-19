class_name V2World
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 世界状态容器（纯数据；UI 只能通过只读 view-model 或明确命令方法修改）
#
#   容器：实体 / 航迹 / 选中 / 时间 / 图层 / 命令 / 证据 / 事件流
#   只读查询：vm_* 系列返回普通 Dictionary，UI 不需要碰内部对象。
#   数据来源：V2Scenario（V2 schema 或 v15 迁移），规则来自 content/*.json。
#   本类不做传感器数学、不做渲染、不模拟武器。
# ═══════════════════════════════════════════════════════════════════

signal state_changed(reason: String)
signal log_event(kind: String, text: String)
signal track_changed(track_id: String, reason: String)
signal order_changed(order_data: Dictionary)
signal evidence_changed(id: String, state: String)

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

# ── 场景装载 ─────────────────────────────────────────────────────

func load_scenario(s: V2Scenario) -> bool:
	errors.clear()
	warnings.clear()
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
	sync_entities()
	selected_id = own_id
	if selected_id != "":
		state_changed.emit("select")
	state_changed.emit("load")
	push_log(("load"), "场景装载：%s · entities=%d tracks=%d phases=%d migrated=%s" % [
		s.id, entities.size(), tracks.count() if tracks != null else 0,
		s.phases.size(), str(s.migrated)])
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
			"state": "unknown",
			"started_t": -1.0,
			"done_t": -1.0,
			"def": def,
		}

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

## 推进世界时间：命令队列传输/执行 + 航迹衰减。返回本次迁移列表。
func advance(dt: float) -> Dictionary:
	var out := {"orders": [], "tracks": []}
	if dt <= 0.0:
		return out
	t += dt
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
	state_changed.emit("tick")
	return out

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
	var ctx := {"phase": phase_context, "flags": {}}
	var eval := V2Actions.available_one(action_id, actor, target, tr, ctx)
	if eval.is_empty():
		return {"ok": false, "reason": "未知动作: " + action_id}
	if not bool(eval.get("available", false)):
		return {"ok": false, "reason": String(eval.get("reason", "不可用")),
			"reason_code": String(eval.get("reason_code", "")), "action": eval}
	var p: Dictionary = params.duplicate(true)
	if not p.has("duration_s"):
		p["duration_s"] = float(eval.get("duration_s", 0.0))
	var o := orders.issue(action_id, target_id, p, own_id, tr.id if tr != null else "", t)
	push_log("order", "预命令 %s · %s → %s（不推进仿真）" % [o.id, action_id, target_id])
	state_changed.emit("order")
	return {"ok": true, "reason": "", "order": o, "action": eval}

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

# ── 证据 ─────────────────────────────────────────────────────────

func evidence_start(id: String) -> bool:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return false
	var d: Dictionary = ev
	if String(d.get("state", "")) == "done":
		return false
	d["state"] = "in_progress"
	d["started_t"] = t
	evidence_change_emit(id, "in_progress")
	return true

func evidence_complete(id: String) -> bool:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return false
	var d: Dictionary = ev
	if String(d.get("state", "")) == "done":
		return false
	d["state"] = "done"
	d["done_t"] = t
	evidence_change_emit(id, "done")
	push_log("evidence", "证据取得：%s" % String(d.get("label", id)))
	return true

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
	return {
		"t": t, "scenario_id": scenario.id if scenario != null else "",
		"title": scenario.title if scenario != null else "",
		"own_id": own_id, "selected_id": selected_id, "phase_context": phase_context,
		"entity_count": entities.size(),
		"track_count": tracks.count() if tracks != null else 0,
		"order_count": orders.orders.size() if orders != null else 0,
		"evidence_count": evidence_count(),
		"evidence_total": evidence.size(),
		"can_expose": can_expose(),
		"layers": layers.duplicate(true),
		"migrated": scenario.migrated if scenario != null else false,
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

## 目标可用动作（右栏/右键菜单直接用）。
func vm_actions(target_id: String) -> Array:
	var actor := own()
	var target: V2Entity = by_id.get(target_id)
	var tr := track_for(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	return V2Actions.available(actor, target, tr, {"phase": phase_context, "flags": {}})

func vm_orders() -> Array:
	return orders.snapshot() if orders != null else []

func vm_orders_summary() -> Dictionary:
	return orders.summary() if orders != null else {}

func vm_evidence() -> Array:
	var out: Array = []
	for k in evidence.keys():
		var d: Dictionary = (evidence[k] as Dictionary).duplicate(true)
		d.erase("def")
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
		"recent_events": recent_events(16),
	}

func _with(d: Dictionary, key: String, value) -> Dictionary:
	var o: Dictionary = d
	o[key] = value
	return o
