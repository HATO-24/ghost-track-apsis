extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2A：EventBus（事件内核；新文件，不直接写 world）
#
# - 事件 schema：id/type/t/source/target/payload/text_key（+seq/schema）；
# - 发布校验（必需字段/类型/t 有限非负/payload 对象/重复 id 拒绝）；
# - 确定性单调 seq；订阅/取消（同序同步派发）；最近事件/过滤（type 前缀、source、target、since_t）；
# - 不写 world/V15/UI；snapshot() 只读 JSON。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.event.v1"
const BUS_SCHEMA := "v17.event_bus.v1"
const MAX_EVENTS := 1000
const MAX_SUBSCRIBERS := 128
const DEFAULT_TYPE_PREFIX := ""

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var events: Array = []
var seq := 0
var _id_seq := 0
var _subs: Array = []      # [{token,type,callable,order}]
var _sub_seq := 0
var _seen_ids: Dictionary = {}
var _dispatch_count := 0
var _listener_errors: Array[String] = []

func _init(opts := {}) -> void:
	setup(opts)

func setup(opts := {}) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	events = []
	seq = 0
	_id_seq = 0
	_subs = []
	_sub_seq = 0
	_seen_ids = {}
	errors.clear()
	warnings.clear()
	_listener_errors.clear()
	_dispatch_count = 0
	ready = true
	var initial: Array = o.get("events", []) if o.get("events") is Array else []
	for raw in initial:
		if raw is Dictionary:
			publish(raw)
	return ready

# ── 发布 / 校验 ────────────────────────────────────────────────

func validate_event(raw: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not (raw.get("type", null) is String) or String(raw.get("type", "")) == "":
		e.append("type 必须是非空字符串")
	if not raw.has("t"):
		e.append("缺 t")
	elif not _is_num(raw.get("t")) or not is_finite(float(raw.get("t"))):
		e.append("t 必须是有限数字")
	elif float(raw.get("t")) < 0.0:
		e.append("t 必须 >=0")
	if not (raw.get("source", null) is String) or String(raw.get("source", "")) == "":
		e.append("source 必须是非空字符串")
	if raw.has("target") and not (raw.get("target") is String):
		e.append("target 必须是字符串")
	if raw.has("payload") and not (raw.get("payload") is Dictionary):
		e.append("payload 必须是对象")
	if raw.has("text_key") and not (raw.get("text_key") is String):
		e.append("text_key 必须是字符串")
	if raw.has("id") and String(raw.get("id", "")) != "":
		if _seen_ids.has(String(raw.get("id", ""))):
			e.append("重复事件 id: " + String(raw.get("id", "")))
	return e

## 发布事件；合法则分配 seq/id 并同步派发订阅者。返回 {ok, event, errors, dispatched}。
func publish(raw: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var input: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	var errs: Array[String] = validate_event(input)
	if not errs.is_empty():
		errors.append_array(errs)
		return {"ok": false, "reason": "invalid_event", "errors": errs}
	seq += 1
	var event := {
		"schema": SCHEMA,
		"id": String(input.get("id", "")),
		"seq": seq,
		"type": String(input.get("type", "")),
		"t": float(input.get("t", 0.0)),
		"source": String(input.get("source", "")),
		"target": String(input.get("target", "")),
		"payload": (input.get("payload", {}) as Dictionary).duplicate(true) if input.get("payload") is Dictionary else {},
		"text_key": String(input.get("text_key", "")),
	}
	if event["id"] == "":
		_id_seq += 1
		event["id"] = "evt-%06d" % _id_seq
	_seen_ids[event["id"]] = true
	events.append(event)
	while events.size() > MAX_EVENTS:
		events.pop_front()
		warnings.append("事件环形缓冲丢最旧事件（max=%d）" % MAX_EVENTS)
	var dispatched := _dispatch(event)
	_dispatch_count += 1
	if _listener_errors.size() > 0:
		warnings.append("派发期监听器错误：" + str(_listener_errors))
	return {"ok": true, "event": event.duplicate(true), "seq": seq,
		"dispatched": dispatched, "count": events.size(),
		"errors": []}

func _dispatch(event: Dictionary) -> int:
	var count := 0
	var dead: Array = []
	for raw in _subs:
		var sub: Dictionary = raw
		if not Callable(sub.get("callable", Callable())).is_valid():
			dead.append(raw)
			continue
		var prefix := String(sub.get("type", ""))
		if prefix != "" and event["type"] != prefix and not String(event["type"]).begins_with(prefix + "."):
			continue
		var cb: Callable = sub.get("callable")
		cb.call((event as Dictionary).duplicate(true))
		count += 1
	for d in dead:
		_subs.erase(d)
	return count

# ── 订阅 ────────────────────────────────────────────────────────

## 订阅：type_prefix 为空=全部；"entity" 匹配 entity.*；返回 token。
func subscribe(type_prefix: String, cb: Callable) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not cb.is_valid():
		return {"ok": false, "reason": "invalid_callable"}
	if _subs.size() >= MAX_SUBSCRIBERS:
		return {"ok": false, "reason": "too_many_subscribers"}
	_sub_seq += 1
	var sub := {"token": _sub_seq, "type": type_prefix, "callable": cb}
	_subs.append(sub)
	return {"ok": true, "token": _sub_seq}

func unsubscribe(token: int) -> Dictionary:
	for i in range(_subs.size()):
		if int((_subs[i] as Dictionary).get("token", -1)) == token:
			_subs.remove_at(i)
			return {"ok": true, "token": token}
	return {"ok": false, "reason": "unknown_token"}

func subscribers_count() -> int:
	return _subs.size()

# ── 查询 ────────────────────────────────────────────────────────

## 最近事件（按 seq 顺序取尾部）；opts: type(前缀)、source、target、since_t、limit。
func recent(count := 10, opts := {}) -> Array:
	return filter_events(opts, count, true)

## 过滤事件；opts: type(前缀)/source/target/since_t/limit；last=true 表示取尾部。
func filter_events(opts := {}, count := -1, last := false) -> Array:
	var o: Dictionary = opts if opts is Dictionary else {}
	var limit := count if count >= 0 else int(o.get("limit", -1))
	var out: Array = []
	for raw in events:
		var e: Dictionary = raw
		if o.has("type") and not _type_match(String(e.get("type", "")), String(o.get("type", ""))):
			continue
		if o.has("type_exact") and String(e.get("type", "")) != String(o.get("type_exact", "")):
			continue
		if o.has("source") and String(e.get("source", "")) != String(o.get("source", "")):
			continue
		if o.has("target") and String(e.get("target", "")) != String(o.get("target", "")):
			continue
		if o.has("since_t") and float(e.get("t", 0.0)) < float(o.get("since_t", 0.0)):
			continue
		out.append((e as Dictionary).duplicate(true))
	if last and limit >= 0 and out.size() > limit:
		out = out.slice(out.size() - limit)
	elif limit >= 0 and out.size() > limit:
		out = out.slice(0, limit)
	return out

func _type_match(event_type: String, prefix: String) -> bool:
	if prefix == "":
		return true
	return event_type == prefix or event_type.begins_with(prefix + ".")

func last_event() -> Dictionary:
	if events.is_empty():
		return {}
	return (events[events.size() - 1] as Dictionary).duplicate(true)

func event_by_id(id: String) -> Dictionary:
	for raw in events:
		if String((raw as Dictionary).get("id", "")) == id:
			return (raw as Dictionary).duplicate(true)
	return {}

func count() -> int:
	return events.size()

func current_seq() -> int:
	return seq

func check_invariants() -> Dictionary:
	var violations: Array = []
	if seq < 0:
		violations.append("seq 不能为负")
	if events.size() > MAX_EVENTS:
		violations.append("事件数超过 MAX_EVENTS")
	var last_seq := -1
	for raw in events:
		var e: Dictionary = raw
		if int(e.get("seq", -1)) <= last_seq:
			violations.append("事件 seq 非单调")
			break
		last_seq = int(e.get("seq", -1))
	return {"ok": violations.is_empty(), "violations": violations, "schema": BUS_SCHEMA}

func snapshot() -> Dictionary:
	return {
		"schema": BUS_SCHEMA,
		"ready": ready,
		"seq": seq,
		"count": events.size(),
		"dispatch_count": _dispatch_count,
		"subscribers": subscribers_count(),
		"events": events.duplicate(true),
		"last_event": last_event(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"invariants": check_invariants(),
	}

func to_dict() -> Dictionary:
	return snapshot()

func reset() -> void:
	setup({})

func _is_num(v) -> bool:
	return (v is int) or (v is float)
