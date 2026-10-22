extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5F：FleetFormationService（舰队编制）
#
# 自由 add/remove/move 舰只到固定槽位；校验必需 command、每槽上限、
# 角色兼容、重复、总 mass/dv/crew、燃料/维修坞容量。
# 可选链接 FleetRefitService：编队统计使用改装后的 current stats。
# 不写 world/TrackTable/UI/V15；不生成实体。
# ═══════════════════════════════════════════════════════════════════

const ShipCatalogScript := preload("res://scripts/core/ship_catalog.gd")
const ROSTER_PATH := "res://framework/content/fleet_roster.json"
const SCHEMA := "v17.fleet_formation.v1"
const VERSION := "1.0.0"
const SAVE_SCHEMA := "v17.fleet_formation_save.v1"
const SAVE_VERSION := "1.0.0"

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var catalog = null
var fleet_refit = null
var roster: Dictionary = {}
var slot_defs: Dictionary = {}
var limits: Dictionary = {}
var ships: Array = []
var ships_by_id: Dictionary = {}
var assignments: Dictionary = {}
var _initial_assignments: Dictionary = {}
var _roster_path := ROSTER_PATH

func _init(catalog_arg = null, roster_arg = null, cfg := {}) -> void:
	setup(catalog_arg, roster_arg, cfg)

func setup(catalog_arg = null, roster_arg = null, cfg = {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	if catalog_arg is Dictionary and roster_arg == null:
		var c0: Dictionary = catalog_arg
		catalog_arg = c0.get("catalog", null)
		roster_arg = c0.get("roster", c0.get("roster_path", null))
		cfg = c0.get("cfg", c0)
	catalog = catalog_arg
	if catalog == null:
		catalog = ShipCatalogScript.new()
	if catalog == null or not catalog.has_method("class_of"):
		errors.append("缺少 ShipCatalog")
		return false
	if not bool(catalog.ready):
		errors.append("ShipCatalog 未 ready：" + str(catalog.errors))
		return false
	var rdata = roster_arg
	if rdata == null:
		var rr: Dictionary = _read_json(_roster_path)
		if not bool(rr.get("ok", false)):
			errors.append(str(rr.get("reason", "")))
			return false
		rdata = rr.get("value")
	elif rdata is String:
		var rr2: Dictionary = _read_json(String(rdata))
		if not bool(rr2.get("ok", false)):
			errors.append(str(rr2.get("reason", "")))
			return false
		rdata = rr2.get("value")
	var vr: Dictionary = validate_roster(rdata)
	if not bool(vr.get("ok", false)):
		for e in (vr.get("errors", []) as Array):
			errors.append(str(e))
		return false
	roster = (rdata as Dictionary).duplicate(true)
	slot_defs = (roster.get("slots", {}) as Dictionary).duplicate(true)
	limits = (roster.get("limits", {}) as Dictionary).duplicate(true)
	ships = []
	ships_by_id = {}
	assignments = {}
	for raw in (roster.get("ships", []) as Array):
		if not (raw is Dictionary):
			continue
		var sh: Dictionary = (raw as Dictionary).duplicate(true)
		sh["formation_roles"] = (sh.get("formation_roles", []) as Array).duplicate() \
			if sh.get("formation_roles") is Array else []
		sh["assigned_slot"] = sh.get("assigned_slot", null)
		var sid := str(sh.get("ship_id", ""))
		if sid == "":
			continue
		ships.append(sh)
		ships_by_id[sid] = sh
	ships.sort_custom(func(a, b): return str(a.get("ship_id", "")) < str(b.get("ship_id", "")))
	if cfg is Dictionary and (cfg as Dictionary).get("refit") != null:
		fleet_refit = (cfg as Dictionary).get("refit")
	if fleet_refit != null and not bool(fleet_refit.ready):
		warnings.append("FleetRefitService 未 ready，编队用 catalog 基础 stats")
		fleet_refit = null
	# 初始编制来自 roster 的 assigned_slot
	_initial_assignments = {}
	for raw2 in ships:
		var sh2: Dictionary = raw2
		var slot := str(sh2.get("assigned_slot", ""))
		if slot != "" and slot_defs.has(slot):
			assignments[str(sh2.get("ship_id", ""))] = slot
	_initial_assignments = assignments.duplicate(true)
	ready = true
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file_not_found: " + path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "file_unreadable: " + path}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json: " + path}
	return {"ok": true, "value": parsed}

func validate_roster(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["roster 必须是对象"]}
	var d: Dictionary = data
	if str(d.get("schema", "")) != "v17.fleet_roster.v1":
		errs.append("schema 必须 v17.fleet_roster.v1")
	if not (d.get("slots") is Dictionary) or (d.get("slots", {}) as Dictionary).is_empty():
		errs.append("slots 必须是非空对象")
	if not (d.get("limits") is Dictionary):
		errs.append("limits 必须是对象")
	if not (d.get("ships") is Array) or (d.get("ships", []) as Array).is_empty():
		errs.append("ships 必须是非空数组")
	var ids: Dictionary = {}
	for raw in (d.get("ships", []) as Array):
		if not (raw is Dictionary):
			errs.append("ship 必须是对象")
			continue
		var sh: Dictionary = raw
		var sid := str(sh.get("ship_id", ""))
		if sid == "":
			errs.append("ship_id 不能为空")
		elif ids.has(sid):
			errs.append("ship_id 重复：" + sid)
		ids[sid] = true
		var cid := str(sh.get("class_id", ""))
		if cid == "":
			errs.append("ship class_id 不能为空：" + sid)
		elif catalog != null and bool(catalog.ready) and catalog.class_of(cid).is_empty():
			errs.append("ShipCatalog 未知 class：" + cid)
		if not (sh.get("formation_roles") is Array) or (sh.get("formation_roles") as Array).is_empty():
			errs.append("formation_roles 必须非空：" + sid)
		var slot0 = sh.get("assigned_slot", null)
		if slot0 != null and str(slot0) != "":
			if not (d.get("slots", {}) as Dictionary).has(str(slot0)):
				errs.append("assigned_slot 未知：" + str(slot0))
	for sk in (d.get("slots", {}) as Dictionary).keys():
		var sd: Dictionary = (d.get("slots", {}) as Dictionary)[sk]
		if not (sd.get("cap") is int or sd.get("cap") is float):
			errs.append("slot cap 必须是数字：" + str(sk))
		if not (sd.get("roles") is Array):
			errs.append("slot roles 必须是数组：" + str(sk))
	for lk in ["max_ships", "max_mass_t", "min_total_dv_kmps", "max_total_dv_kmps",
			"max_crew", "fuel_capacity_t", "repair_dock_capacity"]:
		if not ((d.get("limits", {}) as Dictionary).get(lk, null) is int or (d.get("limits", {}) as Dictionary).get(lk, null) is float):
			errs.append("limits 缺数字字段：" + str(lk))
	return {"ok": errs.is_empty(), "errors": errs}

# ── 统计 ───────────────────────────────────────────────────────

func _ship_stats(ship_id: String) -> Dictionary:
	var sh: Dictionary = ships_by_id.get(ship_id, {})
	if sh.is_empty():
		return {}
	var out: Dictionary = {"mass_t": 0.0, "dv_kmps": 0.0, "accel_g": 0.0,
		"crew": 0, "fuel_t": float(sh.get("fuel_t", 0.0)),
		"repair_slots_required": int(sh.get("repair_slots_required", 0))}
	if fleet_refit != null and bool(fleet_refit.ready):
		var st: Dictionary = fleet_refit.stats(ship_id)
		var cur: Dictionary = st.get("current", {}) as Dictionary
		if not cur.is_empty():
			out["mass_t"] = float(cur.get("mass_t", 0.0))
			out["dv_kmps"] = float(cur.get("dv_kmps", 0.0))
			out["accel_g"] = float(cur.get("accel_g", 0.0))
			out["crew"] = int(cur.get("crew", 0))
			out["refit_linked"] = true
			return out
	var cls: Dictionary = catalog.class_of(str(sh.get("class_id", "")))
	out["mass_t"] = float(cls.get("displacement_t", 0.0))
	out["dv_kmps"] = float(cls.get("dv_kmps", 0.0))
	out["accel_g"] = float(cls.get("accel_g", 0.0))
	out["crew"] = int(cls.get("crew", 0))
	return out

func _slot_role_ok(ship_id: String, slot: String) -> bool:
	var sh: Dictionary = ships_by_id.get(ship_id, {})
	var sd: Dictionary = slot_defs.get(slot, {})
	if sh.is_empty() or sd.is_empty():
		return false
	var roles: Array = sh.get("formation_roles", []) as Array
	var slot_roles: Array = sd.get("roles", []) as Array
	for r in roles:
		if str(r) in slot_roles:
			return true
	return false

func _totals(assign_map: Dictionary) -> Dictionary:
	var out := {"ships": 0, "mass_t": 0.0, "dv_kmps": 0.0, "crew": 0,
		"fuel_t": 0.0, "repair_slots_required": 0}
	for sid in assign_map.keys():
		var ss: Dictionary = _ship_stats(str(sid))
		if ss.is_empty():
			continue
		out["ships"] = int(out["ships"]) + 1
		out["mass_t"] = float(out["mass_t"]) + float(ss.get("mass_t", 0.0))
		out["dv_kmps"] = float(out["dv_kmps"]) + float(ss.get("dv_kmps", 0.0))
		out["crew"] = int(out["crew"]) + int(ss.get("crew", 0))
		out["fuel_t"] = float(out["fuel_t"]) + float(ss.get("fuel_t", 0.0))
		out["repair_slots_required"] = int(out["repair_slots_required"]) + int(ss.get("repair_slots_required", 0))
	return out

func _validate_assignments(assign_map: Dictionary) -> Dictionary:
	var errs: Array = []
	for sid in assign_map.keys():
		if not ships_by_id.has(str(sid)):
			errs.append("未知 ship：" + str(sid))
			continue
		var slot := str(assign_map[sid])
		if not slot_defs.has(slot):
			errs.append("未知 slot：%s/%s" % [str(sid), slot])
			continue
		if not _slot_role_ok(str(sid), slot):
			errs.append("角色不兼容：%s → %s" % [str(sid), slot])
	var used: Dictionary = {}
	for sid2 in assign_map.keys():
		var slot2 := str(assign_map[sid2])
		used[slot2] = int(used.get(slot2, 0)) + 1
	for sk in slot_defs.keys():
		var sd: Dictionary = slot_defs[sk]
		var n := int(used.get(str(sk), 0))
		var cap := int(sd.get("cap", 0))
		if n > cap:
			errs.append("槽位超限：%s %d/%d" % [str(sk), n, cap])
		if bool(sd.get("required", false)) and n < 1:
			errs.append("必需槽位为空：" + str(sk))
	var t: Dictionary = _totals(assign_map)
	if int(t["ships"]) > int(limits.get("max_ships", 0)):
		errs.append("舰数超限：" + str(t["ships"]))
	if float(t["mass_t"]) > float(limits.get("max_mass_t", 0.0)):
		errs.append("总质量超限：%.2f/%.2f" % [float(t["mass_t"]), float(limits.get("max_mass_t", 0.0))])
	if float(t["dv_kmps"]) < float(limits.get("min_total_dv_kmps", 0.0)):
		errs.append("总 Δv 不足：%.2f" % float(t["dv_kmps"]))
	if float(t["dv_kmps"]) > float(limits.get("max_total_dv_kmps", 999999.0)):
		errs.append("总 Δv 超限：%.2f" % float(t["dv_kmps"]))
	if int(t["crew"]) > int(limits.get("max_crew", 0)):
		errs.append("总编制超限：" + str(t["crew"]))
	if float(t["fuel_t"]) > float(limits.get("fuel_capacity_t", 0.0)):
		errs.append("燃料容量超限：%.1f/%.1f" % [float(t["fuel_t"]), float(limits.get("fuel_capacity_t", 0.0))])
	if int(t["repair_slots_required"]) > int(limits.get("repair_dock_capacity", 0)):
		errs.append("维修坞容量超限：" + str(t["repair_slots_required"]))
	return {"ok": errs.is_empty(), "errors": errs, "totals": t}

func validate() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": ["FleetFormationService 未 ready"]}
	var v: Dictionary = _validate_assignments(assignments)
	v["schema"] = SCHEMA
	v["stats"] = stats()
	return v

# ── 编组 ───────────────────────────────────────────────────────

func slots() -> Dictionary:
	var used: Dictionary = {}
	for sid in assignments.keys():
		var slot := str(assignments[sid])
		if not used.has(slot):
			used[slot] = []
		(used[slot] as Array).append(str(sid))
	var out: Dictionary = {}
	for sk in slot_defs.keys():
		var sd: Dictionary = slot_defs[sk]
		var ids: Array = used.get(str(sk), []) as Array
		out[str(sk)] = {"cap": int(sd.get("cap", 0)),
			"required": bool(sd.get("required", false)),
			"roles": (sd.get("roles", []) as Array).duplicate(),
			"label": str(sd.get("label", "")),
			"used": ids.size(), "free": int(sd.get("cap", 0)) - ids.size(),
			"ships": ids.duplicate()}
	return {"schema": SCHEMA, "slots": out, "total_cap": _sum_cap(), "assigned": assignments.size()}

func _sum_cap() -> int:
	var n := 0
	for sk in slot_defs.keys():
		n += int((slot_defs[sk] as Dictionary).get("cap", 0))
	return n

func roster_view() -> Array:
	var out: Array = []
	for raw in ships:
		var sh: Dictionary = (raw as Dictionary).duplicate(true)
		var sid := str(sh.get("ship_id", ""))
		sh["assigned_slot"] = assignments.get(sid, null)
		sh["stats"] = _ship_stats(sid)
		out.append(sh)
	return out

func assign(ship_id: String, slot: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not ships_by_id.has(ship_id):
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	if not slot_defs.has(slot):
		return {"ok": false, "reason": "unknown_slot", "slot": slot}
	if assignments.has(ship_id):
		return {"ok": false, "reason": "already_assigned", "ship_id": ship_id,
			"slot": str(assignments[ship_id])}
	if not _slot_role_ok(ship_id, slot):
		return {"ok": false, "reason": "role_mismatch", "ship_id": ship_id, "slot": slot,
			"roles": (ships_by_id[ship_id].get("formation_roles", []) as Array).duplicate()}
	var used := _slot_used(slot)
	if used + 1 > int((slot_defs[slot] as Dictionary).get("cap", 0)):
		return {"ok": false, "reason": "slot_full", "slot": slot,
			"used": used, "cap": slot_defs[slot].get("cap")}
	var cand: Dictionary = assignments.duplicate(true)
	cand[ship_id] = slot
	var v: Dictionary = _validate_assignments(cand)
	if not bool(v.get("ok", false)):
		return {"ok": false, "reason": "constraint_failed", "errors": v.get("errors", []),
			"ship_id": ship_id, "slot": slot}
	assignments = cand
	return {"ok": true, "ship_id": ship_id, "slot": slot, "slots": slots(),
		"stats": stats()}

func _slot_used(slot: String) -> int:
	var n := 0
	for sid in assignments.keys():
		if str(assignments[sid]) == slot:
			n += 1
	return n

func unassign(ship_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not assignments.has(ship_id):
		return {"ok": false, "reason": "not_assigned", "ship_id": ship_id}
	var slot := str(assignments[ship_id])
	assignments.erase(ship_id)
	return {"ok": true, "ship_id": ship_id, "from": slot, "slots": slots(),
		"stats": stats()}

func move(ship_id: String, slot: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not assignments.has(ship_id):
		return {"ok": false, "reason": "not_assigned", "ship_id": ship_id}
	if not slot_defs.has(slot):
		return {"ok": false, "reason": "unknown_slot", "slot": slot}
	if str(assignments[ship_id]) == slot:
		return {"ok": true, "unchanged": true, "ship_id": ship_id, "slot": slot}
	if not _slot_role_ok(ship_id, slot):
		return {"ok": false, "reason": "role_mismatch", "ship_id": ship_id, "slot": slot}
	var cand: Dictionary = assignments.duplicate(true)
	cand[ship_id] = slot
	var v: Dictionary = _validate_assignments(cand)
	if not bool(v.get("ok", false)):
		return {"ok": false, "reason": "constraint_failed", "errors": v.get("errors", [])}
	var old := str(assignments[ship_id])
	assignments = cand
	return {"ok": true, "ship_id": ship_id, "from": old, "to": slot,
		"slots": slots(), "stats": stats()}

func add(ship_id: String, slot: String) -> Dictionary:
	return assign(ship_id, slot)

func remove(ship_id: String) -> Dictionary:
	return unassign(ship_id)

func stats() -> Dictionary:
	var t: Dictionary = _totals(assignments)
	var v: Dictionary = _validate_assignments(assignments)
	return {"schema": SCHEMA, "ok": bool(v.get("ok", false)), "valid": bool(v.get("ok", false)),
		"assignments": assignments.duplicate(true), "totals": t,
		"limits": limits.duplicate(true), "slots": slots(),
		"assigned": assignments.size(), "unassigned": ships.size() - assignments.size(),
		"errors": v.get("errors", []), "refit_linked": fleet_refit != null,
		"proposal": true, "truth": false,
		"writes": {"world": false, "ui": false, "v15": false}}

func summary() -> Dictionary:
	var st: Dictionary = stats()
	return {"schema": SCHEMA, "ready": ready, "ships": ships.size(),
		"assigned": int(st.get("assigned", 0)),
		"unassigned": int(st.get("unassigned", 0)),
		"valid": bool(st.get("valid", false)),
		"totals": st.get("totals", {}), "limits": limits.duplicate(true),
		"slots": st.get("slots", {}), "refit_linked": fleet_refit != null,
		"proposal": true, "truth": false,
		"writes": {"world": false, "ui": false, "v15": false}}

func link_refit(service) -> Dictionary:
	if service == null or not bool(service.ready):
		return {"ok": false, "reason": "refit_not_ready"}
	fleet_refit = service
	return {"ok": true, "linked": true, "stats": stats()}

func save_state() -> Dictionary:
	return {"schema": SAVE_SCHEMA, "version": SAVE_VERSION,
		"assignments": assignments.duplicate(true)}

func save_json() -> String:
	return JSON.stringify(save_state())

func save() -> Dictionary:
	return save_state()

func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		if String(data).strip_edges() == "":
			return {"ok": false, "reason": "empty_state"}
		parsed = JSON.parse_string(String(data))
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json"}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var p: Dictionary = parsed
	if str(p.get("schema", "")) != SAVE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if str(p.get("version", "")) != SAVE_VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	var a: Dictionary = p.get("assignments", {}) if p.get("assignments") is Dictionary else {}
	for sid in a.keys():
		if not ships_by_id.has(str(sid)):
			return {"ok": false, "reason": "unknown_ship", "ship_id": str(sid)}
		if not slot_defs.has(str(a[sid])):
			return {"ok": false, "reason": "unknown_slot", "slot": str(a[sid])}
	var v: Dictionary = _validate_assignments(a)
	if not bool(v.get("ok", false)):
		return {"ok": false, "reason": "invalid_assignments", "errors": v.get("errors", [])}
	assignments = a.duplicate(true)
	return {"ok": true, "assignments": assignments.size(), "stats": stats()}

func reset() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	assignments = _initial_assignments.duplicate(true)
	return {"ok": true, "reset": true, "stats": stats()}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("FleetFormationService 未 ready")
	if slot_defs.is_empty():
		v.append("slot_defs 为空")
	if ships.is_empty():
		v.append("ships 为空")
	for sid in assignments.keys():
		if not ships_by_id.has(str(sid)):
			v.append("assignment 未知 ship：" + str(sid))
		if not slot_defs.has(str(assignments[sid])):
			v.append("assignment 未知 slot：" + str(assignments[sid]))
	var cv: Dictionary = _validate_assignments(assignments)
	if not bool(cv.get("ok", false)):
		v.append("编制不变量失败：" + str(cv.get("errors", [])))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "ready": ready,
		"summary": summary(), "roster": roster_view(),
		"save_state": save_state()}
