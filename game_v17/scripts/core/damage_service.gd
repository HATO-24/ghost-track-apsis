extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2K：DamageService（损管服务；新文件）
#
# - 每舰一个 V2DamageModel（framework/core/damage_model.gd），内容来源
#   damage_l1.json（ships 档案）；
# - apply combat_damage_event（combat_damage_event.v1）→ 分区伤害/火灾/失压/断电；
# - repair/fix/priority/cancel；tick 推进火灾/失压/断电/维修队列；
# - VM/summary/events；内存 save/load（每舰模型状态快照）；
# - 不写 UI/物理/world/V15。
# ═══════════════════════════════════════════════════════════════════

const DamageModel := preload("res://framework/core/damage_model.gd")

const SCHEMA := "v17.damage_service.v1"
const SAVE_SCHEMA := "v17.damage_service_save.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/damage_l1.json"
const DAMAGE_EVENT_SCHEMA := "combat_damage_event.v1"
const MAX_EVENTS := 400
const SECTION_IDS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]
const KIND_SECTION := {
	"kinetic": "hull", "explosive": "power", "energy": "sensors",
	"thermal": "tanks", "fire": "tanks", "fragmentation": "hull",
}
## 命中方位 → 部位（按伤害类型分表）。无目标姿态时以入射相对速度几何推导方位，
## 让"从尾部命中打推进、从背侧命中打天线"成立，而不是永远打 hull。
const DIR_SECTION := {
	"kinetic": {"fore": "hull", "aft": "propulsion", "port": "hull",
		"starboard": "hull", "dorsal": "sensors", "ventral": "tanks"},
	"fragmentation": {"fore": "hull", "aft": "propulsion", "port": "hull",
		"starboard": "hull", "dorsal": "sensors", "ventral": "tanks"},
	"explosive": {"fore": "hull", "aft": "propulsion", "port": "tanks",
		"starboard": "tanks", "dorsal": "comms", "ventral": "tanks"},
	"energy": {"fore": "sensors", "aft": "power", "port": "sensors",
		"starboard": "sensors", "dorsal": "sensors", "ventral": "hull"},
	"thermal": {"fore": "tanks", "aft": "tanks", "port": "tanks",
		"starboard": "tanks", "dorsal": "tanks", "ventral": "tanks"},
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var ships: Dictionary = {}          # ship_id -> V2DamageModel
var ship_ids: Array = []
var default_ship := ""
var t := 0.0
var events: Array = []
var applied_damage: Array = []
var _event_seq := 0

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	ships = {}
	ship_ids = []
	default_ship = ""
	t = float(c.get("t", 0.0))
	events = []
	applied_damage = []
	_event_seq = 0
	content_path = String(c.get("content_path", DEFAULT_CONTENT))
	content = {}
	if c.has("content"):
		if not (c.get("content") is Dictionary) or (c.get("content") as Dictionary).is_empty():
			errors.append("content 覆盖不能为空")
			return false
		content = (c.get("content") as Dictionary).duplicate(true)
	else:
		content = DamageModel.load_content(content_path)
	if content.is_empty():
		errors.append("damage 内容未加载：" + content_path)
		return false
	var v: Dictionary = validate_content(content)
	if not bool(v.get("ok", false)):
		errors.append_array(v.get("errors", []))
		return false
	var wanted: Array = []
	if c.get("ships") is Array and not (c.get("ships") as Array).is_empty():
		for raw in (c.get("ships") as Array):
			wanted.append(String(raw))
	else:
		wanted = DamageModel.list_ships(content)
	for sid in wanted:
		var m = DamageModel.new()
		if not m.setup(content, sid):
			errors.append("舰船模型初始化失败：%s（%s）" % [sid, str(m.errors)])
			continue
		m.t = t
		ships[sid] = m
		ship_ids.append(sid)
	ship_ids.sort()
	if ships.is_empty():
		errors.append("没有可用舰船模型")
		return false
	default_ship = String(c.get("default_ship", ship_ids[0]))
	if not ships.has(default_ship):
		errors.append("default_ship 不在 ships：" + default_ship)
		return false
	ready = true
	return true

func validate_content(data: Dictionary) -> Dictionary:
	var errs: Array[String] = []
	if String(data.get("schema", "")) != "damage.v1":
		errs.append("damage content schema 必须为 damage.v1")
	var profiles: Dictionary = data.get("ships", {}) if data.get("ships") is Dictionary else {}
	if profiles.is_empty():
		errs.append("damage content ships 不能为空")
	for sid in profiles.keys():
		var p: Dictionary = profiles[sid]
		if String(p.get("id", "")) != String(sid):
			errs.append("ship %s id 不一致" % String(sid))
		var secs: Array = p.get("sections", []) if p.get("sections") is Array else []
		if secs.is_empty():
			errs.append("ship %s sections 为空" % String(sid))
		var seen := {}
		for raw in secs:
			if not (raw is Dictionary):
				errs.append("ship %s section 非对象" % String(sid))
				continue
			var sid2 := String((raw as Dictionary).get("id", ""))
			if not (sid2 in SECTION_IDS):
				errs.append("ship %s 未知 section id：%s" % [String(sid), sid2])
			if seen.has(sid2):
				errs.append("ship %s section 重复：%s" % [String(sid), sid2])
			seen[sid2] = true
	if not (data.get("repair") is Dictionary):
		errs.append("damage content repair 缺失")
	if not (data.get("effects") is Dictionary):
		errs.append("damage content effects 缺失")
	return {"ok": errs.is_empty(), "errors": errs}

func ship_ids_list() -> Array:
	return ship_ids.duplicate()

func model(ship_id: String):
	return ships.get(ship_id, null)

func is_operational(ship_id: String) -> bool:
	var m = ships.get(ship_id, null)
	return m != null and bool(m.is_operational())

# ── 伤害输入 ────────────────────────────────────────────────────

## 应用 combat_damage_event.v1：分区伤害/火灾/失压/断电（applied=true）。
## target_ship / opts.ship_id 指定舰；target_id 若就是 ship id 也可。
## 命中部位推导：方位优先（几何），无方位退回伤害类型默认表。
## 优先级：显式 section > 显式 suggested_section > 方位表 > 类型表 > hull。
func _section_from_hit(event: Dictionary) -> String:
	var kind := String(event.get("damage_kind", "kinetic"))
	var dir := String(event.get("direction", ""))
	var table: Dictionary = DIR_SECTION.get(kind, {}) if DIR_SECTION.get(kind) is Dictionary else {}
	if dir != "" and table.has(dir):
		var sid := String(table[dir])
		if sid in SECTION_IDS:
			return sid
	return String(KIND_SECTION.get(kind, "hull"))


func apply_combat_damage(event: Dictionary, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: DamageService 未 ready")
	if event.is_empty():
		return _fail("invalid_event", "precondition: 空伤害事件")
	var ev_schema := String(event.get("schema", ""))
	if ev_schema != "" and ev_schema != DAMAGE_EVENT_SCHEMA:
		return _fail("invalid_event", "precondition: 伤害事件 schema 非法")
	if ev_schema == "" and String(event.get("kind", "")) != "damage":
		return _fail("invalid_event", "precondition: 伤害事件 kind 非法")
	var damage := float(event.get("damage", 0.0))
	if not is_finite(damage) or damage <= 0.0:
		return _fail("invalid_damage", "precondition: damage 必须 >0")
	var o: Dictionary = opts if opts is Dictionary else {}
	var ship_id := String(event.get("target_ship", event.get("ship_id", "")))
	if ship_id == "":
		var tid := String(event.get("target_id", ""))
		if ships.has(tid):
			ship_id = tid
		else:
			ship_id = String(o.get("ship_id", default_ship))
	if not ships.has(ship_id):
		return _fail("unknown_ship", "precondition: 未知舰船：" + ship_id)
	var m = ships[ship_id]
	var section := String(event.get("section", event.get("suggested_section", "")))
	if section == "":
		section = _section_from_hit(event)
	if not (section in SECTION_IDS) or m.section(section).is_empty():
		return _fail("invalid_section", "precondition: 非法分区：" + section)
	var pen := clampf(float(event.get("penetration", 0.5)), 0.0, 1.0)
	if not is_finite(pen):
		pen = 0.5
	var direction := String(event.get("direction", o.get("direction", "fore")))
	var source := String(event.get("source", event.get("source_id", "combat")))
	var res: Dictionary = m.apply_hit(section, damage, pen, direction, source)
	if not bool(res.get("ok", false)):
		return _fail("apply_failed", String(res.get("reason", "apply_hit 失败")))
	var rec := {
		"t": t, "ship_id": ship_id, "target_id": String(event.get("target_id", "")),
		"shot_id": String(event.get("shot_id", "")),
		"weapon_id": String(event.get("weapon_id", "")),
		"section": section, "damage": damage, "penetration": pen,
		"hit": (res.get("hit", {}) as Dictionary).duplicate(true),
		"new_events": (res.get("events", []) as Array).size(),
		"summary": (res.get("summary", {}) as Dictionary).duplicate(true),
		"effects": (res.get("effects", {}) as Dictionary).duplicate(true),
		"applied": true,
	}
	applied_damage.append(rec)
	while applied_damage.size() > 200:
		applied_damage.pop_front()
	_emit("damage.applied", {"ship_id": ship_id, "section": section,
		"damage": damage, "penetration": pen,
		"shot_id": String(event.get("shot_id", "")),
		"new_events": int(rec["new_events"]),
		"summary": rec["summary"]})
	var out := {
		"ok": true, "applied": true, "ship_id": ship_id, "section": section,
		"hit": rec["hit"], "summary": rec["summary"],
		"effects": rec["effects"],
		"new_events": (res.get("events", []) as Array).duplicate(true),
		"damage_event": event.duplicate(true),
	}
	return out

## 直接造成分区伤害（probe/工具；等价于 apply_hit 的 service 包装）。
func apply_hit(ship_id: String, section: String, energy: float,
		penetration := 0.5, direction := "fore", source := "manual") -> Dictionary:
	var ev := {"schema": DAMAGE_EVENT_SCHEMA, "kind": "damage",
		"target_ship": ship_id, "suggested_section": section,
		"damage": energy, "penetration": penetration,
		"damage_kind": "kinetic", "direction": direction, "source": source}
	return apply_combat_damage(ev, {"ship_id": ship_id})

# ── 损管 ────────────────────────────────────────────────────────

func repair(ship_id: String, section: String, priority := 2) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: DamageService 未 ready")
	if not ships.has(ship_id):
		return _fail("unknown_ship", "precondition: 未知舰船：" + ship_id)
	var m = ships[ship_id]
	var res: Dictionary = m.assign_repair(section, priority)
	if bool(res.get("ok", false)):
		_emit("damage.repair_queued", {"ship_id": ship_id, "section": section,
			"priority": int(priority), "job": (res.get("job", {}) as Dictionary).duplicate(true)})
	return res

## fix：与 repair 相同（现场维修指派；完成由 tick 推进/显式维修流程）。
func fix(ship_id: String, section: String, priority := 2) -> Dictionary:
	return repair(ship_id, section, priority)

func cancel_repair(ship_id: String, section: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: DamageService 未 ready")
	if not ships.has(ship_id):
		return _fail("unknown_ship", "precondition: 未知舰船：" + ship_id)
	var res: Dictionary = (ships[ship_id] as Object).cancel_repair(section)
	if bool(res.get("ok", false)):
		_emit("damage.repair_cancelled", {"ship_id": ship_id, "section": section})
	return res

func set_priority(ship_id: String, section: String, priority: int) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: DamageService 未 ready")
	if not ships.has(ship_id):
		return _fail("unknown_ship", "precondition: 未知舰船：" + ship_id)
	var res: Dictionary = (ships[ship_id] as Object).set_priority(section, priority)
	if bool(res.get("ok", false)):
		_emit("damage.repair_priority", {"ship_id": ship_id, "section": section,
			"priority": int(priority)})
	return res

func tick(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: DamageService 未 ready")
	if not is_finite(dt) or dt < 0.0:
		return _fail("invalid_dt", "precondition: dt 必须有限且 >=0")
	t += dt
	var rows: Array = []
	for sid in ship_ids:
		var m = ships[sid]
		var res: Dictionary = m.step(dt)
		if not bool(res.get("ok", false)):
			warnings.append("ship %s step 失败：%s" % [sid, str(res.get("reason", ""))])
		rows.append({"ship_id": sid, "t": float(m.t),
			"summary": (res.get("summary", {}) as Dictionary).duplicate(true)})
	_emit("damage.tick", {"dt": dt, "ships": rows.size()})
	return {"ok": true, "t": t, "ships": rows, "summary": summary()}

# ── 查询 ────────────────────────────────────────────────────────

func ship_vm(ship_id: String) -> Dictionary:
	if not ships.has(ship_id):
		return {}
	return (ships[ship_id] as Object).vm_damage()

func vm(ship_id := "") -> Dictionary:
	if not ready:
		return {"schema": SCHEMA, "ready": false, "errors": errors.duplicate()}
	var rows: Array = []
	var ids: Array = [ship_id] if ship_id != "" else ship_ids
	for sid in ids:
		if not ships.has(sid):
			continue
		var m = ships[sid]
		rows.append({"ship_id": sid, "vm": m.vm_damage()})
	var out_events: Array = []
	var start := maxi(0, events.size() - 64)
	for i in range(start, events.size()):
		out_events.append((events[i] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "ready": true, "t": t,
		"content_id": String(content.get("id", "")),
		"ships": rows, "applied_damage": applied_damage.duplicate(true),
		"events": out_events, "summary": summary(),
		"writes": {"world": false, "v15": false, "ui": false, "physics": false}}

func summary() -> Dictionary:
	var per_ship: Array = []
	var operational := 0
	var total_fire := 0
	var total_decompressed := 0
	var total_unpowered := 0
	var total_repairing := 0
	var total_queued := 0
	for sid in ship_ids:
		var m = ships[sid]
		var sm: Dictionary = m.summary()
		per_ship.append({"ship_id": sid, "name": String(m.name),
			"operational": bool(m.is_operational()), "summary": sm.duplicate(true)})
		if bool(m.is_operational()):
			operational += 1
		total_fire += int(sm.get("on_fire", 0))
		total_decompressed += int(sm.get("decompressed", 0))
		total_unpowered += int(sm.get("unpowered", 0))
		total_repairing += int(sm.get("repairing", 0))
		total_queued += int(sm.get("queued", 0))
	return {"schema": SCHEMA, "t": t, "ships": ship_ids.size(),
		"operational": operational, "on_fire": total_fire,
		"decompressed": total_decompressed, "unpowered": total_unpowered,
		"repairing": total_repairing, "queued": total_queued,
		"per_ship": per_ship, "writes_v15": false}

# ── 事件 ────────────────────────────────────────────────────────

func _emit(kind: String, detail: Dictionary) -> void:
	_event_seq += 1
	events.append({"schema": "damage_service_event.v1", "seq": _event_seq,
		"t": t, "kind": kind, "detail": detail.duplicate(true),
		"writes_v15": false})
	while events.size() > MAX_EVENTS:
		events.pop_front()

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out := events.duplicate(true)
	events = []
	return out

# ── 存档（内存 JSON） ──────────────────────────────────────────

func save_state() -> String:
	var ship_states: Dictionary = {}
	for sid in ship_ids:
		var m = ships[sid]
		ship_states[sid] = {
			"t": float(m.t), "sections": JSON.parse_string(JSON.stringify(m.sections)),
			"events": JSON.parse_string(JSON.stringify(m.events)),
			"queue": JSON.parse_string(JSON.stringify(m.queue)),
			"resources": JSON.parse_string(JSON.stringify(m.resources)),
			"last_effects": JSON.parse_string(JSON.stringify(m.last_effects)),
			"team_seq": int(m._team_seq), "hit_seq": int(m._hit_seq),
		}
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"content_path": content_path, "t": t, "event_seq": _event_seq,
		"ship_ids": ship_ids.duplicate(), "default_ship": default_ship,
		"ships": ship_states,
		"applied_damage": JSON.parse_string(JSON.stringify(applied_damage)),
		"events": JSON.parse_string(JSON.stringify(events))})

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		return _fail("empty_state", "load: 空 JSON")
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return _fail("invalid_json", "load: JSON 无效")
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if String(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	if not ready:
		return _fail("not_ready", "load: DamageService 未 ready")
	var st_ships = d.get("ships", null)
	if not (st_ships is Dictionary):
		return _fail("invalid_payload", "load: ships 快照缺失")
	# 校验
	for sid in st_ships.keys():
		if not ships.has(String(sid)):
			return _fail("unknown_ship", "load: 快照舰船不存在：" + String(sid))
		var sd: Dictionary = (st_ships as Dictionary)[sid]
		if not (sd.get("sections") is Array):
			return _fail("invalid_payload", "load: ship sections 无效")
		for raw in (sd.get("sections") as Array):
			if not (raw is Dictionary):
				return _fail("invalid_payload", "load: section 非对象")
			if not (String((raw as Dictionary).get("id", "")) in SECTION_IDS):
				return _fail("invalid_payload", "load: 未知 section")
			var integ := float((raw as Dictionary).get("integrity", -1.0))
			if not is_finite(integ) or integ < 0.0 or integ > 1.0:
				return _fail("invalid_payload", "load: integrity 越界")
		if not (sd.get("resources") is Dictionary):
			return _fail("invalid_payload", "load: resources 无效")
	# 所有已配置舰必须有快照（先全量校验，避免部分写入）
	for sid2 in ship_ids:
		if not (st_ships as Dictionary).has(sid2) or not ((st_ships as Dictionary)[sid2] is Dictionary):
			return _fail("invalid_payload", "load: 缺舰船快照：" + sid2)
	# 应用
	for sid in ship_ids:
		var m = ships[sid]
		var sd2 = (st_ships as Dictionary).get(sid, null)
		if not (sd2 is Dictionary):
			return _fail("invalid_payload", "load: 缺舰船快照：" + sid)
		var m2: Dictionary = sd2
		m.sections = (m2.get("sections", []) as Array).duplicate(true)
		m.events = (m2.get("events", []) as Array).duplicate(true)
		m.queue = (m2.get("queue", []) as Array).duplicate(true)
		m.resources = (m2.get("resources", {}) as Dictionary).duplicate(true)
		m.t = float(m2.get("t", 0.0))
		m._team_seq = int(m2.get("team_seq", 0))
		m._hit_seq = int(m2.get("hit_seq", 0))
		m._recompute_effects()
	t = float(d.get("t", 0.0))
	_event_seq = int(d.get("event_seq", 0))
	if d.get("events") is Array:
		events = (d.get("events") as Array).duplicate(true)
	if d.get("applied_damage") is Array:
		applied_damage = (d.get("applied_damage") as Array).duplicate(true)
	_check_contracts()
	return {"ok": true, "t": t, "ships": ships.size(), "errors": []}

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	for sid in ship_ids:
		var m = ships[sid]
		if not bool(m.ready):
			v.append("模型未 ready：" + sid)
		if absf(float(m.t) - t) > 1.0e-6:
			v.append("模型时间不一致：" + sid)
		for raw in (m.sections as Array):
			var sec: Dictionary = raw
			var integ := float(sec.get("integrity", -1.0))
			if not is_finite(integ) or integ < 0.0 or integ > 1.0:
				v.append("integrity 越界：%s/%s" % [sid, String(sec.get("id", ""))])
		var r: Dictionary = m.resources
		if int(r.get("teams_busy", 0)) < 0 or int(r.get("spares_used", 0)) < 0:
			v.append("维修资源为负：" + sid)
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("DamageService 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": String(reason_text), "errors": [msg]}
