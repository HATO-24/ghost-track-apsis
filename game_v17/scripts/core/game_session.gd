extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2C：GameSession（编排层；新文件）
#
# - 组合 TimeService / EventBus / WorldState / OrderService / CommsService；
# - boot(config)（含示例 seed：实体/链路/订单；不进入关卡）；
# - tick(dt)（时间→订单/通信推进；事件发布；bus 不自动写 world）；
# - 包装 issue_order/authorize/begin/complete/abort、send_comms、set_link；
# - snapshot() 只读；save_state()/load_state() **内存 JSON**（seed+操作日志重放，不写盘）；
# - DbC：单写者/时间单调/订单-通信一致；失败不伪造。
# 不实现物理/UI/剧情；不接旧场景。
# ═══════════════════════════════════════════════════════════════════

const TimeService := preload("res://scripts/core/time_service.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")
const WorldState := preload("res://scripts/core/world_state.gd")
const OrderService := preload("res://scripts/core/order_service.gd")
const CommsService := preload("res://scripts/core/comms_service.gd")

const SCHEMA := "v17.game_session.v1"
const SAVE_SCHEMA := "v17.game_session_save.v1"
const VERSION := "1.0.0"
const WRITER_DEFAULT := "session"
const ACTIVE_ORDER_STATES := ["ISSUED", "TRANSMITTING", "DELIVERED", "QUEUED",
	"PENDING_EFFECT", "AUTHORIZED", "EXECUTING"]

var ready := false
var booted := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var writer := WRITER_DEFAULT
var time = null
var bus = null
var world = null
var orders = null
var comms = null

var _seed: Dictionary = {}
var _log: Array = []
var _replaying := false
var _standalone: Dictionary = {}   # delivery_id -> {from,to,mode,text_key,sent_t}
var _tick_events: Array = []
var _last_time_s := 0.0

func _init(config := {}) -> void:
	boot(config)

# ── 示例 seed（不进入关卡）──────────────────────────────────────

func _demo_seed() -> Dictionary:
	return {
		"time": {"t_s": 0.0, "epoch_s": 760.8, "scale": 1.0},
		"writer": WRITER_DEFAULT,
		"entities": [
			{"id": "apsis", "batch": "1000", "kind": "ship", "name": "远地点",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
				"flags": {"flagship": true}},
			{"id": "harmattan", "batch": "1001", "kind": "ship", "name": "哈马丹",
				"pos_km": [20.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0], "flags": {}},
			{"id": "l1_station", "batch": "3100", "kind": "station", "name": "L1 港",
				"pos_km": [0.0, 0.0, 10.0], "vel_kmps": [0.0, 0.0, 0.0],
				"flags": {"fixed": true}},
		],
		"nodes": [
			{"id": "apsis", "name": "远地点", "role": "flagship"},
			{"id": "harmattan", "name": "哈马丹", "role": "escort"},
			{"id": "l1_station", "name": "L1 港", "role": "station"},
		],
		"links": [
			{"a": "apsis", "b": "harmattan", "mode": "LD"},
			{"a": "harmattan", "b": "l1_station", "mode": "LR"},
		],
		"orders": [],
		"order_mode": "LD",
		"comms_text_key": "COMMS_SENT",
		"delivery_delay_s": 1.0,
	}

func _normalize_seed(config: Dictionary) -> Dictionary:
	if config.is_empty():
		return _demo_seed()
	var seed := _demo_seed()
	for key in ["time", "writer", "entities", "nodes", "links", "orders",
			"order_mode", "comms_text_key", "delivery_delay_s", "auth_required"]:
		if config.has(key):
			seed[key] = config[key]
	return seed

# ── boot ────────────────────────────────────────────────────────

func boot(config := {}) -> Dictionary:
	ready = false
	booted = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	_tick_events = []
	_standalone = {}
	_log = []
	_last_time_s = 0.0
	_seed = _normalize_seed(config if config is Dictionary else {})
	_seed = _json_norm(_seed)
	writer = String(_seed.get("writer", WRITER_DEFAULT))
	time = TimeService.new(_seed.get("time", {}) if _seed.get("time") is Dictionary else {})
	bus = EventBus.new()
	world = WorldState.new({"writer": writer, "time": time, "bus": bus})
	comms = CommsService.new({
		"nodes": (_seed.get("nodes", []) as Array).duplicate(true),
		"links": (_seed.get("links", []) as Array).duplicate(true),
	})
	orders = OrderService.new({
		"entities": _entities_map(),
		"comms": comms,
		"mode": String(_seed.get("order_mode", "LD")),
		"delivery_delay_s": float(_seed.get("delivery_delay_s", 1.0)),
		"require_authorizer": false,
		"comms_text_key": String(_seed.get("comms_text_key", "COMMS_SENT")),
	})
	if not bool(time.ready) or not bool(bus.ready) or not bool(world.ready) \
			or not bool(orders.ready) or not bool(comms.ready):
		errors.append("session 组件未就绪：time=%s bus=%s world=%s orders=%s comms=%s" % [
			str(time.ready), str(bus.ready), str(world.ready),
			str(orders.ready), str(comms.ready)])
		return _result(false)
	# seed 实体（session 是唯一写者：bus 发事件 + world 显式 apply）
	for raw in (_seed.get("entities", []) as Array):
		if not (raw is Dictionary):
			continue
		var ent: Dictionary = (raw as Dictionary).duplicate(true)
		var eid := String(ent.get("id", ""))
		var ev: Dictionary = _mk_event("entity.spawn", "", {"entity": ent})
		var pub: Dictionary = bus.publish(ev)
		if not bool(pub.get("ok", false)):
			errors.append("seed 实体事件失败：" + eid)
			continue
		var ap: Dictionary = world.apply(pub.get("event", {}), writer)
		if not bool(ap.get("ok", false)):
			errors.append("seed 实体应用失败：%s（%s）" % [eid, str(ap.get("reason", ""))])
	# seed 订单（可选）
	for raw_o in (_seed.get("orders", []) as Array):
		if not (raw_o is Dictionary):
			continue
		var spec: Dictionary = raw_o
		var draft: Dictionary = orders.create_draft(
			String(spec.get("action", "hold")), String(spec.get("issuer_id", "")),
			spec.get("target_ids", []), spec.get("params", {}),
			spec.get("opts", {}))
		if not bool(draft.get("ok", false)):
			errors.append("seed 订单创建失败：" + str(draft.get("reason", "")))
			continue
		if bool(spec.get("issue", false)):
			var iss: Dictionary = orders.issue(String((draft.get("order", {}) as Dictionary).get("order_id", "")))
			if not bool(iss.get("ok", false)):
				warnings.append("seed 订单 issue 失败：" + str(iss.get("reason", "")))
	_flush_order_events()
	_last_time_s = time.now_s()
	booted = true
	ready = errors.is_empty()
	return _result(ready)

func _entities_map() -> Dictionary:
	var out := {}
	for raw in (_seed.get("entities", []) as Array):
		if raw is Dictionary:
			var ent: Dictionary = raw
			out[String(ent.get("id", ""))] = {"name": String(ent.get("name", ent.get("id", ""))),
				"role": String(ent.get("kind", ""))}
	return out

func _mk_event(event_type: String, target := "", payload := {}) -> Dictionary:
	return {"type": event_type, "t": time.now_s() if time != null else 0.0,
		"source": writer, "target": target,
		"payload": payload if payload is Dictionary else {}, "text_key": ""}

# ── 时间控制 ────────────────────────────────────────────────────

func pause() -> Dictionary:
	var r: Dictionary = time.pause()
	_record({"op": "pause"})
	return {"ok": bool(r.get("ok", false)), "paused": true}

func resume() -> Dictionary:
	var r: Dictionary = time.resume()
	_record({"op": "resume"})
	return {"ok": bool(r.get("ok", false)), "paused": false}

func set_scale(new_scale: float) -> Dictionary:
	var r: Dictionary = time.set_scale(new_scale)
	if bool(r.get("ok", false)):
		_record({"op": "set_scale", "scale": float(new_scale)})
	return r

func now_s() -> float:
	return float(time.now_s()) if time != null else 0.0

func now_days() -> float:
	return now_s() / 86400.0

# ── tick（核心编排）─────────────────────────────────────────────

## 推进：time.tick(dt) → 订单/通信 tick（scaled dt）→ 事件发布。bus 不自动写 world。
func tick(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	if not is_finite(float(dt)) or float(dt) < 0.0:
		_contract("precondition: tick(dt) 要求 dt 有限且 >=0")
		return {"ok": false, "reason": "invalid_dt", "errors": contract_errors.duplicate()}
	_tick_events = []
	_record({"op": "tick", "dt": float(dt)})
	if bool(time.paused):
		_check_post()
		return {"ok": true, "t_s": now_s(), "paused": true, "events": [],
			"dt_scaled_s": 0.0, "order_counts": orders.status_counts(),
			"contracts": check_contracts()}
	var pending_before := _standalone_ids()
	var tr: Dictionary = time.tick(float(dt))
	if not bool(tr.get("ok", false)):
		return {"ok": false, "reason": "time_tick_failed", "errors": time.errors.duplicate()}
	var sim_dt := float(tr.get("dt_scaled_s", 0.0))
	var ot: Dictionary = orders.tick(sim_dt)
	if not bool(ot.get("ok", false)):
		warnings.append("orders tick 失败：" + str(ot.get("reason", "")))
	_flush_order_events()
	_reconcile_standalone(pending_before)
	var contracts := check_contracts()
	if not bool(contracts.get("ok", false)):
		_contract("postcondition: " + str(contracts.get("violations", [])))
		return {"ok": false, "reason": "contract_violation", "t_s": now_s(),
			"events": _tick_events.duplicate(true),
			"errors": contract_errors.duplicate(), "contracts": contracts}
	return {"ok": true, "t_s": now_s(), "paused": false, "dt_scaled_s": sim_dt,
		"order_counts": orders.status_counts(),
		"events": _tick_events.duplicate(true),
		"contracts": contracts}

func _check_post() -> void:
	if bool(time.paused) and not bool(orders.t == orders.t):
		return
	var contracts := check_contracts()
	if not bool(contracts.get("ok", false)):
		_contract("postcondition: " + str(contracts.get("violations", [])))

# ── 订单包装 ────────────────────────────────────────────────────

## 创建并发出订单（依赖通信投递；失败/拒绝会体现在 order/status）。
func issue_order(action: String, issuer_id: String, target_ids, params := {},
		opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var p_norm = _json_norm(params)
	var o_norm = _json_norm(opts)
	var t_norm = _json_norm(target_ids)
	_record({"op": "issue_order", "action": action, "issuer_id": issuer_id,
		"target_ids": t_norm, "params": p_norm, "opts": o_norm})
	var draft: Dictionary = orders.create_draft(action, issuer_id, t_norm, p_norm, o_norm)
	if not bool(draft.get("ok", false)):
		_flush_order_events()
		return {"ok": false, "reason": String(draft.get("reason", "")), "errors": [String(draft.get("reason", ""))]}
	var order_id := String((draft.get("order", {}) as Dictionary).get("order_id", ""))
	var res: Dictionary = orders.issue(order_id)
	_flush_order_events()
	return {"ok": bool(res.get("ok", false)), "order_id": order_id,
		"delivery_id": String(res.get("delivery_id", "")),
		"order": res.get("order", {}), "reason": String(res.get("reason", "")),
		"events": _tick_events.duplicate(true)}

func authorize_order(order_id: String, authorizer_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "authorize_order", "order_id": order_id, "authorizer_id": authorizer_id})
	var res: Dictionary = orders.authorize(order_id, authorizer_id)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func begin_execute_order(order_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "begin_execute_order", "order_id": order_id})
	var res: Dictionary = orders.begin_execute(order_id)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func complete_order(order_id: String, result := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var r_norm = _json_norm(result)
	_record({"op": "complete_order", "order_id": order_id, "result": r_norm})
	var res: Dictionary = orders.complete(order_id, r_norm)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func abort_order(order_id: String, reason := "aborted") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "abort_order", "order_id": order_id, "reason": reason})
	var res: Dictionary = orders.abort(order_id, reason)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func reject_order(order_id: String, reason := "rejected", by := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "reject_order", "order_id": order_id, "reason": reason, "by": by})
	var res: Dictionary = orders.reject(order_id, reason, by)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func order(order_id: String) -> Dictionary:
	return orders.order(order_id)

# ── 通信/链路包装 ──────────────────────────────────────────────

func send_comms(from_id: String, to_id: String, mode := "LD",
		text_key := "COMMS_SENT", payload := {}, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var pl_norm = _json_norm(payload)
	var po_norm = _json_norm(opts)
	_record({"op": "send_comms", "from_id": from_id, "to_id": to_id, "mode": mode,
		"text_key": text_key, "payload": pl_norm, "opts": po_norm})
	var res: Dictionary = comms.send(from_id, to_id, mode, text_key, pl_norm, po_norm)
	var ev_type := "comms.sent" if bool(res.get("ok", false)) else "comms.failed"
	_publish(_mk_event(ev_type, to_id, {
		"delivery_id": String(res.get("delivery_id", "")),
		"from": from_id, "to": to_id, "mode": mode,
		"text_key": text_key, "reason": String(res.get("reason", "")),
		"latency_s": float(res.get("latency_s", 0.0)),
		"relay_count": int(res.get("relay_count", 0)),
	}))
	if bool(res.get("ok", false)):
		var did := String(res.get("delivery_id", ""))
		_standalone[did] = {"from": from_id, "to": to_id, "mode": mode,
			"text_key": text_key, "sent_t": now_s()}
	res["events"] = _tick_events.duplicate(true)
	return res

func set_link(a: String, b: String, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	var o: Dictionary = opts if opts is Dictionary else {}
	_tick_events = []
	o = _json_norm(o)
	_record({"op": "set_link", "a": a, "b": b, "opts": o})
	var applied := {}
	if o.has("enabled"):
		applied["enabled"] = comms.set_link_enabled(a, b, bool(o.get("enabled")))
	if o.has("occluded"):
		applied["occluded"] = comms.set_link_occluded(a, b, bool(o.get("occluded")))
	if o.has("jam"):
		applied["jam"] = comms.set_link_jam(a, b, float(o.get("jam")))
	_publish(_mk_event("comms.link", b, {"a": a, "b": b, "applied": applied}))
	var ok := true
	for k in applied.keys():
		if not bool(applied[k]):
			ok = false
	return {"ok": ok, "applied": applied, "events": _tick_events.duplicate(true)}

## 直接查询通信 pending（只读；用于上层观察，不改变状态）。
func comms_pending() -> Array:
	return (comms.pending as Array).duplicate(true) if comms != null else []

# ── 事件发布 / 事件一致性 ───────────────────────────────────────

func _publish(ev: Dictionary) -> void:
	var pub: Dictionary = bus.publish(ev)
	if not bool(pub.get("ok", false)):
		warnings.append("bus publish 失败：" + str(pub.get("errors", [])))
		return
	_tick_events.append((pub.get("event", {}) as Dictionary).duplicate(true))

func _flush_order_events() -> void:
	if orders == null:
		return
	var evs: Array = orders.take_events()
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var typ := "order." + String(ev.get("event", "")).to_lower()
		var targets: Array = ev.get("target_ids", []) if ev.get("target_ids") is Array else []
		_publish({
			"type": typ,
			"t": now_s(),
			"source": "order_service",
			"target": String(targets[0]) if not targets.is_empty() else "",
			"payload": {
				"order_id": String(ev.get("order_id", "")),
				"status": String(ev.get("status", "")),
				"event": String(ev.get("event", "")),
				"reason": String(ev.get("reason", "")),
				"delivery_id": String(ev.get("delivery_id", "")),
				"action": String(ev.get("action", "")),
				"issuer_id": String(ev.get("issuer_id", "")),
			},
			"text_key": String(ev.get("text_key", "")),
		})

func _standalone_ids() -> Array:
	var ids: Array = _standalone.keys()
	ids.sort()
	return ids

func _pending_ids() -> Dictionary:
	var out := {}
	for raw in (comms.pending as Array) if comms != null else []:
		if raw is Dictionary:
			out[String((raw as Dictionary).get("delivery_id", ""))] = true
	return out

func _reconcile_standalone(before_ids: Array) -> void:
	if comms == null:
		return
	var pending_now := _pending_ids()
	for did in before_ids:
		var id := String(did)
		if not _standalone.has(id):
			continue
		if pending_now.has(id):
			continue
		var info: Dictionary = _standalone[id]
		_publish(_mk_event("comms.delivered", String(info.get("to", "")), {
			"delivery_id": id, "from": String(info.get("from", "")),
			"to": String(info.get("to", "")), "mode": String(info.get("mode", "")),
			"text_key": String(info.get("text_key", "")),
		}))
		_standalone.erase(id)

# ── DbC ─────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("session 未 ready")
	if time != null:
		if time.now_s() + 1.0e-9 < _last_time_s:
			v.append("时间回退：%.6f < %.6f" % [time.now_s(), _last_time_s])
		if absf(time.now_s() - _last_time_s) > 1.0e-9:
			_last_time_s = time.now_s()
		if not bool(time.check_invariants().get("ok", false)):
			v.append("TimeService 不变量失败：" + str(time.check_invariants().get("violations", [])))
	if world != null:
		if world.current_writer() != writer:
			v.append("单写者冲突：world writer=%s session writer=%s" % [world.current_writer(), writer])
		if absf(float(world.clock_t_s()) - now_s()) > 1.0e-6:
			v.append("world 时钟不一致：%s != %s" % [str(world.clock_t_s()), str(now_s())])
	if orders != null:
		if absf(float(orders.t) - now_s()) > 1.0e-6 and not bool(time.paused):
			v.append("orders 时间不一致：%s != %s" % [str(orders.t), str(now_s())])
		if comms != null:
			for oid in orders.orders.keys():
				var o: Dictionary = orders.orders[oid]
				var st := String(o.get("status", ""))
				if st in ACTIVE_ORDER_STATES and String(o.get("delivery_id", "")) == "":
					v.append("订单-通信不一致：order %s status=%s 无 delivery_id" % [String(oid), st])
				if float(o.get("issued_t", -1.0)) > now_s() + 1.0e-6:
					v.append("订单 issuance 时间超过会话时间：" + String(oid))
	var out := {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}
	return out

func _contract(msg: String) -> void:
	contract_errors.append(msg)
	errors.append(msg)
	push_error("GameSession: " + msg)

# ── 只读快照 ───────────────────────────────────────────────────

func snapshot() -> Dictionary:
	if not booted:
		return {"schema": SCHEMA, "version": VERSION, "ready": false,
			"errors": errors.duplicate()}
	var order_vm: Dictionary = orders.vm() if orders != null else {}
	var bus_events: Array = bus.recent(32) if bus != null else []
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"ready": ready,
		"writer": writer,
		"t_s": now_s(),
		"t_days": now_days(),
		"paused": bool(time.paused) if time != null else true,
		"scale": float(time.scale) if time != null else 1.0,
		"time": time.snapshot() if time != null else {},
		"components": {
			"world": world.snapshot() if world != null else {},
			"orders": order_vm,
			"comms": comms.vm() if comms != null else {},
			"event_bus": {
				"seq": bus.current_seq() if bus != null else 0,
				"count": bus.count() if bus != null else 0,
				"last_event": bus.last_event() if bus != null else {},
			},
		},
		"entities": world.entities_sorted() if world != null else [],
		"orders_summary": orders.summary() if orders != null else {},
		"comms_summary": comms.summary() if comms != null else {},
		"events": bus_events,
		"contracts": check_contracts(),
		"contract_errors": contract_errors.duplicate(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}

func to_dict() -> Dictionary:
	return snapshot()

func to_json() -> String:
	return JSON.stringify(snapshot())

# ── 内存 save/load（seed + 操作日志重放；不写盘） ───────────────

func save_state() -> String:
	if not ready:
		return ""
	var payload := {
		"schema": SAVE_SCHEMA,
		"version": VERSION,
		"seed": JSON.parse_string(JSON.stringify(_seed)),
		"log": JSON.parse_string(JSON.stringify(_log)),
	}
	return JSON.stringify(payload)

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		errors.append("load_state: 空 JSON")
		return {"ok": false, "reason": "empty_state", "errors": errors.duplicate()}
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		errors.append("load_state: JSON 无效")
		return {"ok": false, "reason": "invalid_json"}
	var data: Dictionary = parsed
	if String(data.get("schema", "")) != SAVE_SCHEMA:
		errors.append("load_state: schema 无效")
		return {"ok": false, "reason": "invalid_schema"}
	var seed = data.get("seed", {})
	var log = data.get("log", [])
	if not (seed is Dictionary) or not (log is Array):
		errors.append("load_state: seed/log 类型无效")
		return {"ok": false, "reason": "invalid_payload"}
	boot(seed)
	if not ready:
		return {"ok": false, "reason": "boot_failed", "errors": errors.duplicate()}
	_replaying = true
	var replay_errors: Array = []
	for raw in (log as Array):
		if not (raw is Dictionary):
			replay_errors.append("log 项非对象")
			continue
		var res: Dictionary = _replay_op(raw as Dictionary)
		if not bool(res.get("ok", false)):
			replay_errors.append("replay %s 失败：%s" % [str((raw as Dictionary).get("op", "")),
				str(res.get("reason", ""))])
	_replaying = false
	_log = (log as Array).duplicate(true)
	_last_time_s = now_s()
	ready = replay_errors.is_empty() and errors.is_empty()
	return {"ok": ready, "errors": replay_errors, "result_errors": errors.duplicate()}

func _replay_op(op: Dictionary) -> Dictionary:
	var kind := String(op.get("op", ""))
	match kind:
		"tick":
			return tick(float(op.get("dt", 0.0)))
		"issue_order":
			return issue_order(String(op.get("action", "")), String(op.get("issuer_id", "")),
				op.get("target_ids", []), op.get("params", {}), op.get("opts", {}))
		"authorize_order":
			return authorize_order(String(op.get("order_id", "")),
				String(op.get("authorizer_id", "")))
		"begin_execute_order":
			return begin_execute_order(String(op.get("order_id", "")))
		"complete_order":
			return complete_order(String(op.get("order_id", "")), op.get("result", {}))
		"abort_order":
			return abort_order(String(op.get("order_id", "")), String(op.get("reason", "aborted")))
		"reject_order":
			return reject_order(String(op.get("order_id", "")), String(op.get("reason", "rejected")),
				String(op.get("by", "")))
		"send_comms":
			return send_comms(String(op.get("from_id", "")), String(op.get("to_id", "")),
				String(op.get("mode", "LD")), String(op.get("text_key", "COMMS_SENT")),
				op.get("payload", {}), op.get("opts", {}))
		"set_link":
			return set_link(String(op.get("a", "")), String(op.get("b", "")), op.get("opts", {}))
		"pause":
			return pause()
		"resume":
			return resume()
		"set_scale":
			return set_scale(float(op.get("scale", 1.0)))
		_:
			return {"ok": false, "reason": "unknown_op"}

func _record(entry: Dictionary) -> void:
	if _replaying:
		return
	_log.append(_json_norm(entry))

func _json_norm(value):
	var s := JSON.stringify(value)
	if s == "" or s == "null":
		return value
	return JSON.parse_string(s)

func reset() -> Dictionary:
	return boot(_seed)

func _result(ok: bool) -> Dictionary:
	return {"ok": ok, "ready": ready, "booted": booted,
		"writer": writer, "t_s": now_s(), "errors": errors.duplicate(),
		"warnings": warnings.duplicate(), "snapshot": snapshot()}
