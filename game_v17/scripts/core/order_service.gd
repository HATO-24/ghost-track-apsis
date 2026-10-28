class_name V2OrderService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2B · 命令服务骨架（OrderService）
#
# 状态机（docs/07）：
#   DRAFT → ISSUED → TRANSMITTING → DELIVERED → QUEUED / PENDING_EFFECT
#         → AUTHORIZED → EXECUTING → DONE / ABORTED / REJECTED / STALE
#
# 职责：
#   * 数据驱动命令记录：issuer/target(s)/action/params/mode/text_key；
#   * 延迟、投递（可接 CommsService）、撤销、过期；不自动授权、不自动执行；
#   * 事件输出 order_event.v1；文本由 TextLibrary 的 text_key + 模板变量解析
#     （from/to/mode/content/delay/reason），服务不硬编码舰名/对白；
#   * 只留 ROE/authority 钩子（Callable），不实现 ROE/物理/UI。
# ═══════════════════════════════════════════════════════════════════

const CommsScript := preload("res://scripts/core/comms_service.gd")

const SCHEMA_EVENT := "order_event.v1"
const SCHEMA_ORDER := "order_record.v1"
const SCHEMA_VM := "order_service.v1"
const STATES := ["DRAFT", "ISSUED", "TRANSMITTING", "DELIVERED", "QUEUED",
	"PENDING_EFFECT", "AUTHORIZED", "EXECUTING", "DONE", "ABORTED", "REJECTED", "STALE"]
const TERMINAL := ["DONE", "ABORTED", "REJECTED", "STALE"]
const MAX_EVENTS := 300

const DEFAULT_TEXT_KEYS := {
	"DRAFTED": "ORDER_DRAFTED",
	"ISSUED": "ORDER_ISSUED",
	"DELAYED": "ORDER_DELAYED",
	"TRANSMITTING": "ORDER_TRANSMITTING",
	"DELIVERED": "ORDER_DELIVERED",
	"QUEUED": "ORDER_QUEUED",
	"PENDING_EFFECT": "ORDER_PENDING_EFFECT",
	"AUTHORIZED": "ORDER_AUTHORIZED",
	"REJECTED": "ORDER_REJECTED",
	"EXECUTING": "ORDER_EXECUTING",
	"DONE": "ORDER_DONE",
	"ABORTED": "ORDER_ABORTED",
	"STALE": "ORDER_STALE",
}

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var errors: Array = []
var warnings: Array = []
var config: Dictionary = {}
var orders: Dictionary = {}      # order_id -> order dict
var events: Array = []
var _outbox: Array = []
var text_library = null
var comms = null
var _order_seq := 0
var _event_seq := 0
var _auth_hook = null
var _comms_event_sink = null   # JC-A04：真实 DELIVERED/FAILED 结果旁路给 Session 回调
var _entities: Dictionary = {}
var _text_keys: Dictionary = {}
var _default_mode := "LD"
var _default_delay_s := 1.0
var _require_authorizer := false
var _auto_text_defaults := true


func _init(cfg := {}) -> void:
	setup(cfg)


func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	orders = {}
	events = []
	_outbox = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	_order_seq = 0
	_event_seq = 0
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	_entities = (config.get("entities", {}) as Dictionary).duplicate(true) if config.get("entities") is Dictionary else {}
	_text_keys = DEFAULT_TEXT_KEYS.duplicate(true)
	if config.get("text_keys") is Dictionary:
		for k in (config.get("text_keys") as Dictionary).keys():
			_text_keys[String(k)] = String((config.get("text_keys") as Dictionary)[k])
	_default_mode = String(config.get("mode", "LD"))
	_default_delay_s = maxf(0.0, float(config.get("delivery_delay_s", 1.0)))
	_require_authorizer = bool(config.get("require_authorizer", false))
	_auth_hook = config.get("auth_check", null)
	_comms_event_sink = config.get("comms_event_sink", null)
	if config.get("comms") is Object and (config.get("comms") as Object).has_method("send"):
		comms = config.get("comms")
	else:
		comms = null
	if config.get("text_library") is Object and (config.get("text_library") as Object).has_method("select"):
		text_library = config.get("text_library")
	else:
		text_library = CommsScript.TextLibrary.new()
	_auto_text_defaults = bool(config.get("add_default_text", true))
	if _auto_text_defaults:
		_add_default_text_entries()
	if config.get("text_entries") is Array:
		text_library.add_entries(config.get("text_entries") as Array)
	ready = true
	return true


func _add_default_text_entries() -> void:
	# 通用模板：只含变量，不含具体舰名/对白。
	text_library.add_entries([
		{"text_key": "ORDER_DRAFTED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令草案：{content}]", "channel": "order"},
		{"text_key": "ORDER_ISSUED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令已发出：{content}]", "channel": "order"},
		{"text_key": "ORDER_DELAYED",
			"template": "[{from} 至 {to}]-[{mode}]-[链路延迟，预计 {delay}s 后送达。]",
			"channel": "order"},
		{"text_key": "ORDER_TRANSMITTING",
			"template": "[{from} 至 {to}]-[{mode}]-[传输中：{content}]", "channel": "order"},
		{"text_key": "ORDER_DELIVERED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令已送达：{content}]", "channel": "order"},
		{"text_key": "ORDER_QUEUED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令入队待执行：{content}]", "channel": "order"},
		{"text_key": "ORDER_PENDING_EFFECT",
			"template": "[{from} 至 {to}]-[{mode}]-[待生效：{content}]", "channel": "order"},
		{"text_key": "ORDER_AUTHORIZED",
			"template": "[{from} 至 {to}]-[{mode}]-[授权通过：{content}]", "channel": "order"},
		{"text_key": "ORDER_REJECTED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令拒绝：{reason_text}]", "channel": "order"},
		{"text_key": "ORDER_EXECUTING",
			"template": "[{from} 至 {to}]-[{mode}]-[执行中：{content}]", "channel": "order"},
		{"text_key": "ORDER_DONE",
			"template": "[{from} 至 {to}]-[{mode}]-[执行完成：{content}]", "channel": "order"},
		{"text_key": "ORDER_ABORTED",
			"template": "[{from} 至 {to}]-[{mode}]-[命令撤销：{reason_text}]", "channel": "order"},
		{"text_key": "ORDER_STALE",
			"template": "[{from} 至 {to}]-[{mode}]-[命令过期，不执行：{content}]", "channel": "order"},
	])


func set_auth_hook(callable: Variant) -> void:
	_auth_hook = callable


func entity_name(id: String) -> String:
	var e = _entities.get(id, null)
	if e is Dictionary and String((e as Dictionary).get("name", "")) != "":
		return String((e as Dictionary).get("name", id))
	return id


func entity_role(id: String) -> String:
	var e = _entities.get(id, null)
	if e is Dictionary:
		return String((e as Dictionary).get("role", ""))
	return ""


func _ctx(order: Dictionary) -> Dictionary:
	var from_id := String(order.get("issuer_id", ""))
	var targets: Array = order.get("target_ids", []) if order.get("target_ids") is Array else []
	var to_names: Array = []
	var to_roles: Array = []
	for raw in targets:
		var tid := String(raw)
		to_names.append(entity_name(tid))
		to_roles.append(entity_role(tid))
	return {
		"channel": "order", "from": entity_name(from_id), "from_name": entity_name(from_id),
		"from_id": from_id, "from_role": entity_role(from_id),
		"to": ", ".join(to_names), "to_name": ", ".join(to_names),
		"to_id": String(targets[0]) if not targets.is_empty() else "",
		"to_role": String(to_roles[0]) if not to_roles.is_empty() else "",
		"mode": String(order.get("mode", "")),
		"content": String(order.get("action", "")),
		"delay": float(order.get("delivery_delay_s", 0.0)),
		"reason_text": String(order.get("reason", "")),
		"order_id": String(order.get("order_id", "")),
		"action": String(order.get("action", "")),
	}


func _text_key_for(event: String) -> String:
	return String(_text_keys.get(event, "ORDER_" + event))


func _emit(order: Dictionary, event: String, from_state: String, reason := "",
		extra := {}) -> Dictionary:
	_event_seq += 1
	var status := String(order.get("status", ""))
	var ctx := _ctx(order)
	if reason != "":
		ctx["reason_text"] = reason
		ctx["reason"] = reason
	for k in extra.keys():
		ctx[String(k)] = extra[k]
	var key := _text_key_for(event)
	var text := ""
	if text_library != null and text_library.has(key):
		var r: Dictionary = text_library.select(key, ctx)
		if bool(r.get("ok", false)):
			text = String(r.get("text", ""))
		else:
			warnings.append("order text render failed %s: %s" % [key, String(r.get("reason", ""))])
	else:
		warnings.append("order text_key 缺失: " + key)
	var ev := {
		"schema": SCHEMA_EVENT, "seq": _event_seq, "t": t,
		"order_id": String(order.get("order_id", "")),
		"event": event, "from_state": from_state, "status": status,
		"issuer_id": String(order.get("issuer_id", "")),
		"target_ids": (order.get("target_ids", []) as Array).duplicate(),
		"action": String(order.get("action", "")),
		"from": String(ctx.get("from", "")), "to": String(ctx.get("to", "")),
		"from_id": String(ctx.get("from_id", "")), "to_id": String(ctx.get("to_id", "")),
		"to_role": String(ctx.get("to_role", "")),
		"mode": String(ctx.get("mode", "")), "text_key": key, "text": text,
		"reason": reason, "delay_s": float(ctx.get("delay", 0.0)),
		"relay_count": int(order.get("relay_count", 0)),
		"delivery_id": String(order.get("delivery_id", "")),
		"shadow": true, "writes_v15": false, "writes_track_table": false,
	}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))
	return ev


func _transition(order: Dictionary, to: String, event: String, reason := "",
		extra := {}) -> Dictionary:
	var from_state := String(order.get("status", ""))
	order["status"] = to
	order["reason"] = reason
	if not (order.get("history") is Array):
		order["history"] = []
	(order["history"] as Array).append({"t": t, "from": from_state, "to": to, "reason": reason})
	return _emit(order, event, from_state, reason, extra)


func create_draft(action: String, issuer_id: String, target_ids: Variant,
		params := {}, opts := {}) -> Dictionary:
	if String(action).strip_edges() == "":
		return {"ok": false, "reason": "empty_action"}
	if issuer_id == "":
		return {"ok": false, "reason": "empty_issuer"}
	var targets: Array = []
	if target_ids is Array:
		targets = (target_ids as Array).duplicate()
	elif target_ids is String and target_ids != "":
		targets = [target_ids]
	targets = targets.filter(func(x): return String(x) != "")
	if targets.is_empty():
		return {"ok": false, "reason": "empty_targets"}
	var o: Dictionary = opts if opts is Dictionary else {}
	_order_seq += 1
	var oid := "O-%06d" % _order_seq
	var order := {
		"schema": SCHEMA_ORDER, "order_id": oid, "issuer_id": issuer_id,
		"target_ids": targets, "action": String(action),
		"params": (params as Dictionary).duplicate(true) if params is Dictionary else {},
		"mode": String(o.get("mode", _default_mode)),
		"text_key": String(o.get("text_key", "")),
		"status": "DRAFT", "reason": "",
		"issued_t": -1.0, "deliver_t": -1.0, "exec_t": -1.0, "expire_t": -1.0,
		"delivered_t": -1.0, "executed_t": -1.0, "ended_t": -1.0,
		"delivery_delay_s": float(o.get("delivery_delay") if o.has("delivery_delay") else _default_delay_s),
		"exec_delay_s": float(o.get("exec_delay", 0.0)),
		"expire_in_s": float(o.get("expire_in", 0.0)),
		"auth_required": bool(o.get("auth_required", true)),
		"authorized_by": "", "delivery_id": "", "relay_count": 0,
		"result": {}, "history": [],
	}
	orders[oid] = order
	_transition(order, "DRAFT", "DRAFTED")
	return {"ok": true, "reason": "", "order": order.duplicate(true)}


func issue(order_id: String) -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	if String(order.get("status", "")) != "DRAFT":
		return {"ok": false, "reason": "invalid_state", "status": String(order.get("status", ""))}
	order["issued_t"] = t
	var from_t := t
	var delay := maxf(0.0, float(order.get("delivery_delay_s", 0.0)))
	order["deliver_t"] = from_t + delay
	if float(order.get("expire_in_s", 0.0)) > 0.0:
		order["expire_t"] = from_t + float(order.get("expire_in_s", 0.0))
	var delivery_ok := true
	var delivery_reason := ""
	if comms != null:
		var targets: Array = order.get("target_ids", [])
		var to_id := String(targets[0]) if not targets.is_empty() else ""
		var ctx_payload := {
			"content": String(order.get("action", "")),
			"action": String(order.get("action", "")),
			"order_id": order_id,
			"reason_text": "",
			"delay": delay,
		}
		var sr: Dictionary = comms.send(String(order.get("issuer_id", "")), to_id,
			String(order.get("mode", _default_mode)), String(config.get("comms_text_key", "COMMS_SENT")),
			ctx_payload, {})
		if bool(sr.get("ok", false)):
			order["delivery_id"] = String(sr.get("delivery_id", ""))
			order["deliver_t"] = t + float(sr.get("latency_s", 0.0))
			order["relay_count"] = int(sr.get("relay_count", 0))
		else:
			delivery_ok = false
			delivery_reason = String(sr.get("reason", "comms_failed"))
	order["dispatched_t"] = t
	_transition(order, "ISSUED", "ISSUED")
	if not delivery_ok:
		order["reason"] = "comms_" + delivery_reason
		_transition(order, "REJECTED", "REJECTED", order["reason"])
		return {"ok": false, "reason": order["reason"], "order": order.duplicate(true)}
	if delay > 0.0:
		_emit(order, "DELAYED", "ISSUED", "", {"delay": delay})
	return {"ok": true, "reason": "", "order": order.duplicate(true),
		"delivery_id": String(order.get("delivery_id", ""))}


func _find_delivery_events(comms_events: Array) -> Dictionary:
	var out := {"delivered": {}, "failed": {}}
	for raw in comms_events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var did := String(ev.get("delivery_id", ""))
		if did == "":
			continue
		var kind := String(ev.get("kind", ""))
		if kind == "DELIVERED":
			out["delivered"][did] = true
		elif kind == "FAILED":
			out["failed"][did] = String(ev.get("reason", "comms_failed"))
	return out


# JC-A04：设置真实 comms 结果回调（Session 侧分发 delivered/failed/共享）。
func set_comms_event_sink(fn) -> void:
	if fn is Callable or fn == null:
		_comms_event_sink = fn

func tick(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	var start_out := _outbox.size()
	var comms_ev: Array = []
	if comms != null and comms.has_method("tick"):
		comms.tick(d)
		if comms.has_method("take_events"):
			comms_ev = comms.take_events()
		# JC-A04：Session 需要同一批真实结果（成功只投递一次/失败不冒充）；
		# 仍由 OrderService.tick 唯一推进 Comms，不另加 Session 推进。
		if _comms_event_sink != null and _comms_event_sink is Callable \
				and (_comms_event_sink as Callable).is_valid():
			(_comms_event_sink as Callable).call(comms_ev.duplicate(true))
	var deliv := _find_delivery_events(comms_ev)
	for oid in orders.keys():
		var order: Dictionary = orders[oid]
		var st := String(order.get("status", ""))
		if st in TERMINAL:
			continue
		# 过期优先（EXECUTING 不自动过期，避免吞掉已开始执行）
		var exp_t := float(order.get("expire_t", -1.0))
		if exp_t >= 0.0 and t + 1.0e-9 >= exp_t and st != "EXECUTING":
			_transition(order, "STALE", "STALE", "expired")
			continue
		if st == "ISSUED":
			_transition(order, "TRANSMITTING", "TRANSMITTING")
			st = "TRANSMITTING"
		if st == "TRANSMITTING":
			var delivered := false
			var fail_reason := ""
			if comms != null:
				var did := String(order.get("delivery_id", ""))
				if deliv["delivered"].has(did):
					delivered = true
				elif deliv["failed"].has(did):
					fail_reason = String(deliv["failed"][did])
			elif t + 1.0e-9 >= float(order.get("deliver_t", 0.0)):
				delivered = true
			if fail_reason != "":
				order["reason"] = "comms_" + fail_reason
				_transition(order, "REJECTED", "REJECTED", order["reason"])
				continue
			if not delivered:
				continue
			order["delivered_t"] = t
			_transition(order, "DELIVERED", "DELIVERED")
			st = "DELIVERED"
		if st == "DELIVERED":
			var exec_t := t + maxf(0.0, float(order.get("exec_delay_s", 0.0)))
			order["exec_t"] = exec_t
			if exec_t > t + 1.0e-9:
				_transition(order, "PENDING_EFFECT", "PENDING_EFFECT")
				st = "PENDING_EFFECT"
			else:
				_transition(order, "QUEUED", "QUEUED")
				st = "QUEUED"
		if st == "PENDING_EFFECT":
			var et := float(order.get("exec_t", -1.0))
			if et >= 0.0 and t + 1.0e-9 >= et:
				_transition(order, "QUEUED", "QUEUED")
				st = "QUEUED"
		# QUEUED/AUTHORIZED/EXECUTING 不自动授权/执行
	_replay_emits()
	var new_events: Array = []
	for i in range(start_out, _outbox.size()):
		new_events.append((_outbox[i] as Dictionary).duplicate(true))
	return {"ok": true, "t": t, "dt": dt_last, "events": new_events,
		"counts": status_counts()}


func _replay_emits() -> void:
	pass


func authorize(order_id: String, authorizer_id := "") -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	var st := String(order.get("status", ""))
	if not (st in ["QUEUED", "PENDING_EFFECT", "DELIVERED"]):
		return {"ok": false, "reason": "invalid_state", "status": st}
	if _require_authorizer and authorizer_id == "":
		order["reason"] = "authorizer_required"
		_transition(order, "REJECTED", "REJECTED", "authorizer_required")
		return {"ok": false, "reason": "authorizer_required", "order": order.duplicate(true)}
	var allowed := true
	var reason := ""
	if _auth_hook is Callable:
		var res = (_auth_hook as Callable).call(order.duplicate(true), authorizer_id)
		if res is Dictionary:
			allowed = bool((res as Dictionary).get("allowed", (res as Dictionary).get("ok", true)))
			reason = String((res as Dictionary).get("reason", ""))
		else:
			allowed = bool(res)
	if not allowed:
		order["reason"] = reason if reason != "" else "authority_denied"
		_transition(order, "REJECTED", "REJECTED", order["reason"])
		return {"ok": false, "reason": order["reason"], "order": order.duplicate(true)}
	order["authorized_by"] = authorizer_id
	_transition(order, "AUTHORIZED", "AUTHORIZED")
	return {"ok": true, "reason": "", "order": order.duplicate(true)}


func reject(order_id: String, reason := "rejected", by := "") -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	if String(order.get("status", "")) in TERMINAL:
		return {"ok": false, "reason": "already_terminal", "status": String(order.get("status", ""))}
	order["authorized_by"] = by
	_transition(order, "REJECTED", "REJECTED", reason)
	return {"ok": true, "reason": reason, "order": order.duplicate(true)}


func begin_execute(order_id: String) -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	var st := String(order.get("status", ""))
	var auth_required := bool(order.get("auth_required", true))
	if st == "QUEUED" and not auth_required:
		_transition(order, "EXECUTING", "EXECUTING")
		return {"ok": true, "reason": "", "order": order.duplicate(true)}
	if st != "AUTHORIZED":
		return {"ok": false, "reason": "not_authorized", "status": st}
	_transition(order, "EXECUTING", "EXECUTING")
	return {"ok": true, "reason": "", "order": order.duplicate(true)}


func complete(order_id: String, result := {}) -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	if String(order.get("status", "")) != "EXECUTING":
		return {"ok": false, "reason": "not_executing", "status": String(order.get("status", ""))}
	order["result"] = (result as Dictionary).duplicate(true) if result is Dictionary else {}
	order["executed_t"] = t
	order["ended_t"] = t
	_transition(order, "DONE", "DONE")
	return {"ok": true, "reason": "", "order": order.duplicate(true)}


func abort(order_id: String, reason := "aborted") -> Dictionary:
	var order = orders.get(order_id, null)
	if not (order is Dictionary):
		return {"ok": false, "reason": "unknown_order", "order_id": order_id}
	if String(order.get("status", "")) in TERMINAL:
		return {"ok": false, "reason": "already_terminal", "status": String(order.get("status", ""))}
	order["ended_t"] = t
	_transition(order, "ABORTED", "ABORTED", reason)
	return {"ok": true, "reason": reason, "order": order.duplicate(true)}


func order(id: String) -> Dictionary:
	var o = orders.get(id, null)
	return (o as Dictionary).duplicate(true) if o is Dictionary else {}


func status_counts() -> Dictionary:
	var counts: Dictionary = {}
	for st in STATES:
		counts[st] = 0
	for k in orders.keys():
		var st2 := String((orders[k] as Dictionary).get("status", ""))
		counts[st2] = int(counts.get(st2, 0)) + 1
	return counts


func pending_orders() -> Array:
	var out: Array = []
	for k in orders.keys():
		var o: Dictionary = orders[k]
		if String(o.get("status", "")) not in TERMINAL:
			out.append(o.duplicate(true))
	out.sort_custom(func(a, b): return String(a.get("order_id", "")) < String(b.get("order_id", "")))
	return out


func _is_terminal(st: String) -> bool:
	return st in TERMINAL


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func vm() -> Dictionary:
	var list: Array = []
	for k in orders.keys():
		list.append((orders[k] as Dictionary).duplicate(true))
	list.sort_custom(func(a, b): return String(a.get("order_id", "")) < String(b.get("order_id", "")))
	var ev_rows: Array = []
	for raw in events:
		if raw is Dictionary:
			ev_rows.append((raw as Dictionary).duplicate(true))
	var comms_vm: Dictionary = {}
	if comms != null and comms.has_method("summary"):
		comms_vm = comms.summary()
	return {
		"schema": SCHEMA_VM, "mode": "shadow", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"orders": list, "pending_orders": pending_orders(),
		"events": ev_rows, "status_counts": status_counts(),
		"comms": comms_vm,
		"text_library": text_library.to_dict() if text_library != null else {},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"track_table": false, "v15": false},
	}


func summary() -> Dictionary:
	return {
		"schema": SCHEMA_VM, "ready": ready, "t": t, "orders": orders.size(),
		"pending": pending_orders().size(), "events": events.size(),
		"comms": comms != null, "text_keys": text_library.keys() if text_library != null else [],
		"writes_v15": false,
	}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())
