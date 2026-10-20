extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2A：WorldState（世界状态内核；新文件）
#
# - 实体表 + 时钟引用 + 已应用事件引用；单一写者约束（writer token）；
# - apply(event) 仅接受白名单合法事件；先全量校验，再写入；后置不变量失败回滚；
# - 只读 snapshot()/entity()/to_dict()；不实现物理/命令/UI；不直接写旧场景。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.world_state.v1"
const DEFAULT_WRITER := "world"
const ALLOWED_TYPES := ["entity.spawn", "entity.despawn", "entity.move",
	"entity.flag", "entity.rename", "world.note"]
const MAX_EVENT_REFS := 512
const ENTITY_ID_PATTERN := "^[a-z][a-z0-9_]*$"

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []
var writer := DEFAULT_WRITER
var entities: Dictionary = {}          # id -> entity dict
var event_refs: Array = []
var version := 0
var _last_event_t := 0.0
var _time = null
var _bus = null

func _init(opts := {}) -> void:
	setup(opts)

func setup(opts := {}) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	entities = {}
	event_refs = []
	version = 0
	_last_event_t = 0.0
	writer = String(o.get("writer", DEFAULT_WRITER))
	_time = o.get("time", null)
	_bus = o.get("bus", null)
	if not _writer_ok(writer):
		_contract("precondition: writer token 非法")
		return false
	ready = true
	var inv: Array = _invariants()
	contract_errors.append_array(inv)
	if not inv.is_empty():
		ready = false
		return false
	return true

func _writer_ok(token: String) -> bool:
	return token == "" or token.length() > 0

# ── 单写者 ──────────────────────────────────────────────────────

## 认领写者：writer 为空或相同则成功；已被其他写者占用则拒绝。
func claim_writer(token: String) -> Dictionary:
	if token == "":
		return {"ok": false, "reason": "empty_token"}
	if writer == "" or writer == token:
		writer = token
		return {"ok": true, "writer": writer}
	_contract("precondition: writer 冲突（当前 %s，请求 %s）" % [writer, token])
	return {"ok": false, "reason": "writer_conflict", "writer": writer,
		"errors": contract_errors.duplicate()}

func release_writer(token: String) -> Dictionary:
	if writer != token:
		return {"ok": false, "reason": "writer_mismatch", "writer": writer}
	writer = ""
	return {"ok": true, "writer": writer}

func current_writer() -> String:
	return writer

# ── 应用事件 ────────────────────────────────────────────────────

## 应用事件（合法白名单 + 单写者 token）。失败不改变状态。
func apply(event: Dictionary, token := "") -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: WorldState 未初始化")
	var before_entities: Dictionary = entities.duplicate(true)
	var before_version := version
	var before_refs: Array = event_refs.duplicate(true)
	# DbC 前置：writer 约束（必须已认领且 token 匹配）
	if writer == "":
		return _fail("no_writer", "precondition: WorldState 未认领 writer（先 claim_writer）")
	if token != writer:
		return _fail("writer_mismatch", "precondition: writer token 不匹配（当前 %s，收到 %s）" % [writer, token])
	# DbC 前置：事件结构
	var pre: Array[String] = _validate_event(event)
	if not pre.is_empty():
		return _fail("invalid_event", "; ".join(pre))
	var etype := String(event.get("type", ""))
	var payload: Dictionary = event.get("payload", {}) if event.get("payload") is Dictionary else {}
	var target := String(event.get("target", ""))
	# 仅合法白名单事件；先校验全部，再变更
	match etype:
		"entity.spawn":
			var ent: Dictionary = payload.get("entity", {}) if payload.get("entity") is Dictionary else {}
			var eid := String(ent.get("id", ""))
			var errs := _validate_entity(eid, ent)
			if not errs.is_empty():
				return _fail("invalid_entity", "; ".join(errs))
			if entities.has(eid):
				return _fail("duplicate_entity", "precondition: 实体已存在：" + eid)
			entities[eid] = _normalize_entity(eid, ent)
		"entity.despawn":
			if not entities.has(target):
				return _fail("unknown_entity", "precondition: 实体不存在：" + target)
			entities.erase(target)
		"entity.move":
			if not entities.has(target):
				return _fail("unknown_entity", "precondition: 实体不存在：" + target)
			var pos = payload.get("pos_km", null)
			if not _finite_vec3(pos):
				return _fail("invalid_payload", "precondition: move.pos_km 必须有限三元数组")
			var cur: Dictionary = entities[target]
			cur["pos_km"] = (pos as Array).duplicate()
			if payload.has("vel_kmps"):
				if not _finite_vec3(payload.get("vel_kmps", null)):
					return _fail("invalid_payload", "precondition: move.vel_kmps 必须有限三元数组")
				cur["vel_kmps"] = (payload.get("vel_kmps") as Array).duplicate()
			cur["version"] = int(cur.get("version", 0)) + 1
			entities[target] = cur
		"entity.flag":
			if not entities.has(target):
				return _fail("unknown_entity", "precondition: 实体不存在：" + target)
			var key := String(payload.get("key", ""))
			if key == "":
				return _fail("invalid_payload", "precondition: flag.key 非空")
			var value = payload.get("value", null)
			if not _json_scalar(value):
				return _fail("invalid_payload", "precondition: flag.value 必须是标量")
			var cur2: Dictionary = entities[target]
			var flags: Dictionary = cur2.get("flags", {}) if cur2.get("flags") is Dictionary else {}
			flags[key] = value
			cur2["flags"] = flags
			cur2["version"] = int(cur2.get("version", 0)) + 1
			entities[target] = cur2
		"entity.rename":
			if not entities.has(target):
				return _fail("unknown_entity", "precondition: 实体不存在：" + target)
			var new_name := String(payload.get("name", ""))
			if new_name == "":
				return _fail("invalid_payload", "precondition: rename.name 非空")
			var cur3: Dictionary = entities[target]
			cur3["name"] = new_name
			cur3["version"] = int(cur3.get("version", 0)) + 1
			entities[target] = cur3
		"world.note":
			pass
		_:
			return _fail("illegal_event_type", "precondition: 非法事件类型：" + etype)
	version += 1
	_last_event_t = float(event.get("t", 0.0))
	event_refs.append({
		"seq": int(event.get("seq", 0)),
		"id": String(event.get("id", "")),
		"type": etype,
		"t": float(event.get("t", 0.0)),
		"source": String(event.get("source", "")),
		"target": target,
		"version": version,
	})
	while event_refs.size() > MAX_EVENT_REFS:
		event_refs.pop_front()
	# DbC 后置：不变量失败则回滚
	var post: Array = _invariants()
	if not post.is_empty():
		entities = before_entities
		version = before_version
		event_refs = before_refs
		_contract("postcondition 失败，已回滚：" + "; ".join(post))
		return _fail("postcondition_failed", "; ".join(post))
	return {"ok": true, "version": version, "event_ref": event_refs[event_refs.size() - 1].duplicate(true),
		"entity_count": entities.size(), "errors": []}

func _validate_event(event: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var etype := String(event.get("type", ""))
	if not (etype in ALLOWED_TYPES):
		e.append("type 不在白名单：" + etype)
	if not event.has("t") or not _is_num(event.get("t")) or not is_finite(float(event.get("t", -1.0))):
		e.append("t 必须是有限数字")
	elif float(event.get("t", -1.0)) < 0.0:
		e.append("t 必须 >=0")
	if not (event.get("source", null) is String) or String(event.get("source", "")) == "":
		e.append("source 必须是非空字符串")
	if event.has("target") and not (event.get("target") is String):
		e.append("target 必须是字符串")
	if event.has("payload") and not (event.get("payload") is Dictionary):
		e.append("payload 必须是对象")
	return e

func _validate_entity(eid: String, ent: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not _id_ok(eid):
		e.append("entity.id 非法：'%s'" % eid)
	var kind := String(ent.get("kind", ""))
	if kind == "":
		e.append("entity.kind 不能为空")
	if ent.has("pos_km") and not _finite_vec3(ent.get("pos_km")):
		e.append("entity.pos_km 必须有限三元数组")
	if ent.has("vel_kmps") and not _finite_vec3(ent.get("vel_kmps")):
		e.append("entity.vel_kmps 必须有限三元数组")
	if ent.has("flags") and not (ent.get("flags") is Dictionary):
		e.append("entity.flags 必须是对象")
	return e

func _normalize_entity(eid: String, ent: Dictionary) -> Dictionary:
	return {
		"id": eid,
		"kind": String(ent.get("kind", "")),
		"name": String(ent.get("name", eid)),
		"pos_km": (ent.get("pos_km", [0.0, 0.0, 0.0]) as Array).duplicate(),
		"vel_kmps": (ent.get("vel_kmps", [0.0, 0.0, 0.0]) as Array).duplicate(),
		"flags": (ent.get("flags", {}) as Dictionary).duplicate(true) if ent.get("flags") is Dictionary else {},
		"alive": true,
		"version": 1,
	}

func _fail(reason: String, message: String) -> Dictionary:
	errors.append(message)
	contract_errors.append(message)
	return {"ok": false, "reason": reason, "errors": [message],
		"contract_errors": contract_errors.duplicate()}

# ── 只读视图 ────────────────────────────────────────────────────

func entity_count() -> int:
	return entities.size()

func has_entity(eid: String) -> bool:
	return entities.has(eid)

func entity(eid: String) -> Dictionary:
	return (entities.get(eid, {}) as Dictionary).duplicate(true)

## 实体数组（按 id 排序；只读副本）。
func entities_sorted() -> Array:
	var ids: Array = entities.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append((entities[id] as Dictionary).duplicate(true))
	return out

func event_refs_since(since_seq := 0) -> Array:
	var out: Array = []
	for raw in event_refs:
		if int((raw as Dictionary).get("seq", 0)) >= since_seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func clock_t_s() -> float:
	if _time != null and _time.has_method("now_s"):
		return float(_time.now_s())
	return _last_event_t

func check_invariants() -> Dictionary:
	var violations: Array = _invariants()
	return {"ok": violations.is_empty(), "violations": violations, "schema": SCHEMA}

func _invariants() -> Array[String]:
	var e: Array[String] = []

	if version < 0:
		e.append("postcondition: version 不能为负")
	for raw_id in entities.keys():
		var id := String(raw_id)
		var ent: Dictionary = entities[raw_id]
		if String(ent.get("id", "")) != id:
			e.append("postcondition: 实体键值不一致：" + id)
		if not _finite_vec3(ent.get("pos_km", null)):
			e.append("postcondition: 实体位置非有限：" + id)
		if not _finite_vec3(ent.get("vel_kmps", null)):
			e.append("postcondition: 实体速度非有限：" + id)
		if not (ent.get("flags", {}) is Dictionary):
			e.append("postcondition: 实体 flags 非对象：" + id)
	return e

func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"ready": ready,
		"writer": writer,
		"version": version,
		"t_s": clock_t_s(),
		"entity_count": entities.size(),
		"entities": entities_sorted(),
		"event_refs": event_refs.duplicate(true),
		"event_ref_count": event_refs.size(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate(),
		"invariants": check_invariants(),
	}

func to_dict() -> Dictionary:
	return snapshot()

func reset() -> void:
	var keep_writer := writer
	setup({"writer": keep_writer})

func _writer_token_ok(token: String) -> bool:
	return token == writer or writer == ""

# ── 工具 ────────────────────────────────────────────────────────

func _contract(msg: String) -> void:
	contract_errors.append(msg)
	errors.append(msg)
	push_error("WorldState: " + msg)

func _is_num(v) -> bool:
	return (v is int) or (v is float)

func _json_scalar(v) -> bool:
	return (v is String) or (v is bool) or _is_num(v)

func _finite_vec3(v) -> bool:
	if not (v is Array) or (v as Array).size() < 3:
		return false
	var arr: Array = v
	for i in range(3):
		if not _is_num(arr[i]) or not is_finite(float(arr[i])):
			return false
	return true

func _id_ok(id: String) -> bool:
	var re := RegEx.new()
	re.compile(ENTITY_ID_PATTERN)
	return re.search(id) != null
