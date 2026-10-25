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
	# A-03：达到安全整数上限时明确拒绝继续分配（不溢出、不四舍五入）。
	if float(seq) >= SAFE_INT_MAX:
		return {"ok": false, "reason": "seq_exhausted",
			"errors": ["event seq reached the safe integer maximum %s" % str(SAFE_INT_MAX)]}
	if float(_id_seq) >= SAFE_INT_MAX:
		return {"ok": false, "reason": "id_exhausted",
			"errors": ["auto event id allocator reached the safe integer maximum"]}
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
		# R02：自动 ID 必须**跳过**任何已用 ID（显式 ID 可能已占用 evt-* 形式）。
		var assigned := false
		var guard := 0
		while not assigned:
			_id_seq += 1
			var cand := "evt-%06d" % _id_seq
			if not _seen_ids.has(cand):
				event["id"] = cand
				assigned = true
			guard += 1
			if guard > 1000000:
				return {"ok": false, "reason": "id_alloc_failed",
					"errors": ["auto id allocator cannot find a free id"]}
	else:
		# R02：显式 ID 若占用 evt-* 形式，抬高分配器高水位，避免后续自动分配撞车。
		var explicit_num := _evt_id_number(String(event["id"]))
		if explicit_num > 0 and explicit_num > _id_seq:
			_id_seq = explicit_num
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

# ── A-03：版本化导出/导入（历史恢复 = 导入，绝不 publish/派发）──────
const STATE_SCHEMA := "v17.event_bus.state.v2"
const STATE_VERSION := 2
# 本批 numeric JSON 兼容范围：安全整数 2^53-1
const SAFE_INT_MAX := 9007199254740991.0


## A-03：把「一个原始 JSON 数字」按整数契约归一为 int。
## 规则：有限、整数值、落在 [min_v, max_v]；接受 int 或 float（JSON 解析结果），
## 拒绝字符串/布尔/分数/越界。不依赖 JSON 数字的 Variant 类型。
func _int_contract(value, min_v: float, max_v: float, label: String) -> Dictionary:
	if value == null:
		return {"ok": false, "reason": "%s: missing" % label}
	var f := 0.0
	if value is int:
		f = float(value)
	elif value is float:
		f = float(value)
	else:
		return {"ok": false, "reason": "%s: not a number (type %s)" % [
			label, type_string(typeof(value))]}
	if is_nan(f) or is_inf(f):
		return {"ok": false, "reason": "%s: not finite" % label}
	if absf(f - roundf(f)) > 0.0:
		return {"ok": false, "reason": "%s: not an integer value (%s)" % [label, str(f)]}
	if f < min_v:
		return {"ok": false, "reason": "%s: below %s" % [label, str(min_v)]}
	if f > max_v:
		return {"ok": false, "reason": "%s: above safe integer max %s" % [label, str(max_v)]}
	return {"ok": true, "value": int(round(f))}


## R02：解析 `evt-NNNNNN` 形式的显式 ID 序号（非该形式返回 0）。
func _evt_id_number(event_id: String) -> int:
	if not event_id.begins_with("evt-"):
		return 0
	var suffix := event_id.substr(4)
	if not suffix.is_valid_int():
		return 0
	var n := int(suffix)
	return n if n > 0 else 0


## A-03：导出完整恢复状态（可见环形历史 + 当前 seq + 自动 ID 分配器 + **完整**已用 ID 集合）。
## 注意：`seen_ids` 是完整去重集合，不等于可见历史（可能远大于 MAX_EVENTS）。
func export_state() -> Dictionary:
	var seen: Array = []
	for k in _seen_ids.keys():
		seen.append(String(k))
	seen.sort()
	return {
		"schema": STATE_SCHEMA,
		"version": STATE_VERSION,
		"seq": seq,
		"id_seq": _id_seq,
		"seen_ids": seen,
		"events": JSON.parse_string(JSON.stringify(events)),
		"max_events": MAX_EVENTS,
	}


## A-03：导入恢复状态。**先完整校验，再一次提交**；失败不半写 bus。
## 不调用 publish、不派发历史事件、不改订阅者。
func import_state(state: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var problems: Array = []
	var require_legacy := false
	# 1) schema/version
	var s_schema := String(state.get("schema", ""))
	if s_schema == "":
		require_legacy = true
	elif s_schema != STATE_SCHEMA:
		return {"ok": false, "reason": "invalid_state_schema", "schema": s_schema,
			"errors": ["unsupported event_bus state schema: " + s_schema]}
	var s_version := 0
	if not require_legacy:
		var ver: Dictionary = _int_contract(state.get("version", null), 0.0, 1.0e6, "version")
		if not bool(ver.get("ok", false)):
			return {"ok": false, "reason": "invalid_state_version",
				"errors": [String(ver.get("reason", ""))]}
		s_version = int(ver.get("value", 0))
		if s_version != STATE_VERSION:
			return {"ok": false, "reason": "invalid_state_version",
				"errors": ["unsupported version %d (expected %d)" % [s_version, STATE_VERSION]]}
	# R02：**新格式必需字段严格校验**。v2 state 缺 seq/id_seq/events/seen_ids 中任一
	# 即属于损坏/不支持，必须明确拒绝；不能以默认值静默接受（否则 >1000 条历史时
	# 会丢掉被裁出可见缓冲的旧 ID，导致去重失效）。仅无 schema 的真实旧格式走迁移。
	if not require_legacy:
		var missing: Array = []
		for required in ["seq", "id_seq", "events", "seen_ids"]:
			if not state.has(required):
				missing.append(required)
		if not missing.is_empty():
			return {"ok": false, "reason": "invalid_state_missing_fields",
				"errors": ["v2 state 缺少必需字段：" + str(missing)]}
	# 2) seq / id_seq 整数契约（bus seq 允许 0；事件 seq 必须 >=1）
	var seq_res: Dictionary = _int_contract(state.get("seq", null), 0.0, SAFE_INT_MAX, "seq")
	if not bool(seq_res.get("ok", false)):
		return {"ok": false, "reason": "invalid_seq",
			"errors": [String(seq_res.get("reason", ""))]}
	var new_seq := int(seq_res.get("value", 0))
	var id_res: Dictionary = _int_contract(state.get("id_seq", 0), 0.0, SAFE_INT_MAX, "id_seq")
	if not bool(id_res.get("ok", false)):
		return {"ok": false, "reason": "invalid_id_seq",
			"errors": [String(id_res.get("reason", ""))]}
	var new_id_seq := int(id_res.get("value", 0))
	# 3) 可见历史：逐条校验 seq（>=1、严格递增）、id 唯一、payload 类型
	var raw_events = state.get("events", null)
	if not (raw_events is Array):
		return {"ok": false, "reason": "invalid_events",
			"errors": ["events must be an array"]}
	var new_events: Array = []
	var new_seen: Dictionary = {}
	var last_seq := 0
	var idx := 0
	for raw in (raw_events as Array):
		if not (raw is Dictionary):
			problems.append("events[%d]: not an object" % idx)
			idx += 1
			continue
		var ev: Dictionary = (raw as Dictionary).duplicate(true)
		var ev_seq_res: Dictionary = _int_contract(ev.get("seq", null), 1.0,
			SAFE_INT_MAX, "events[%d].seq" % idx)
		if not bool(ev_seq_res.get("ok", false)):
			problems.append(String(ev_seq_res.get("reason", "")))
			idx += 1
			continue
		var ev_seq := int(ev_seq_res.get("value", 0))
		if ev_seq <= last_seq:
			problems.append("events[%d].seq 非严格递增 (%d <= %d)" % [idx, ev_seq, last_seq])
		last_seq = ev_seq
		ev["seq"] = ev_seq
		var ev_id := String(ev.get("id", ""))
		if ev_id == "":
			problems.append("events[%d]: missing id" % idx)
		elif new_seen.has(ev_id):
			problems.append("events[%d]: duplicate id %s" % [idx, ev_id])
		else:
			new_seen[ev_id] = true
		if not (ev.get("payload", {}) is Dictionary):
			problems.append("events[%d]: payload must be an object" % idx)
		if not (ev.get("t", 0.0) is int or ev.get("t", 0.0) is float):
			problems.append("events[%d]: t must be a number" % idx)
		new_events.append(ev)
		idx += 1
	# 4) last event seq <= 当前 seq
	if last_seq > new_seq:
		problems.append("history tail seq %d > current seq %d" % [last_seq, new_seq])
	# 5) seen_ids：完整已用 ID 集合（可以远大于可见历史）；可见历史每个 id 必须在内
	var raw_seen = state.get("seen_ids", null)
	var imported_seen_count := 0
	if raw_seen is Array:
		for raw_id in (raw_seen as Array):
			var sid := String(raw_id)
			if sid == "":
				problems.append("seen_ids: empty id")
				continue
			new_seen[sid] = true
			imported_seen_count += 1
	elif raw_seen != null:
		problems.append("seen_ids must be an array")
	# 6) 自动 ID 分配器不得与已用 evt-* ID 冲突：
	#    `id_seq` 是**最后已分配**的序号，因此必须 >= 已用 evt-* 的最大序号；
	#    小于则下一次分配会重发一个已存在的 ID。
	var evt_prefix := "evt-"
	var max_evt_num := 0
	for sid2 in new_seen.keys():
		var key := String(sid2)
		if key.begins_with(evt_prefix):
			var suffix := key.substr(evt_prefix.length())
			if suffix.is_valid_int() and int(suffix) > max_evt_num:
				max_evt_num = int(suffix)
	if new_id_seq < max_evt_num:
		problems.append("allocator collision: id_seq=%d < max used evt id %d" % [
			new_id_seq, max_evt_num])
	if not problems.is_empty():
		# 失败：bus 状态**完全不变**（不半写）
		return {"ok": false, "reason": "invalid_state", "errors": problems.slice(0, 20)}
	# 7) 一次提交（导入 = 导入，绝不 publish/dispatch）
	events = new_events
	seq = new_seq
	_id_seq = new_id_seq
	_seen_ids = new_seen
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return {"ok": true, "mode": ("legacy_partial" if require_legacy else "v2"),
		"seq": seq, "id_seq": _id_seq, "events": events.size(),
		"seen_ids": _seen_ids.size(), "seen_ids_imported": imported_seen_count}

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
