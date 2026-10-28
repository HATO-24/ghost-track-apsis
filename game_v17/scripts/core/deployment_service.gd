extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# JC-B01A 部署服务：选择→校验→冻结 revision/稳定实例→同源部署 seed
# 纯服务：不写 world/physics；Session 在 boot 或预部署 t==0 时应用。
# ═══════════════════════════════════════════════════════════════════

const ShipCatalogScript := preload("res://scripts/core/ship_catalog.gd")
const SCHEMA := "v17.deployment.v1"
const STATE_SCHEMA := "v17.deployment_state.v1"
const STATE_VERSION := 1
const DEFAULT_ROSTER := "res://framework/content/fleet_roster.json"
const MASS_T_TO_KG := 1000.0

var ready := false
var errors: Array = []
var catalog = null
var roster: Dictionary = {}
var ships_by_id: Dictionary = {}
var slot_defs: Dictionary = {}
var limits: Dictionary = {}
var scenario_id := ""
var deployment_seed := 0
var _committed: Dictionary = {}
var _resources: Dictionary = {}
var _cfg: Dictionary = {}

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	_committed = {}
	_resources = {}
	_cfg = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	scenario_id = String(_cfg.get("scenario_id", "default"))
	deployment_seed = int(_cfg.get("deployment_seed", 0))
	var sccfg: Dictionary = {}
	if _cfg.get("ship_catalog") is Dictionary:
		sccfg = (_cfg.get("ship_catalog") as Dictionary).duplicate(true)
	catalog = ShipCatalogScript.new(sccfg)
	if not bool(catalog.ready):
		errors.append("部署 ship_catalog 未就绪：" + str(catalog.errors))
		return false
	var roster_path := String(_cfg.get("roster", DEFAULT_ROSTER))
	var txt := ""
	if FileAccess.file_exists(roster_path):
		txt = FileAccess.get_file_as_string(roster_path)
	if txt.strip_edges() == "":
		errors.append("部署 roster 不可读：" + roster_path)
		return false
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		errors.append("部署 roster 非对象")
		return false
	roster = parsed
	slot_defs = roster.get("slots", {}) if roster.get("slots") is Dictionary else {}
	limits = roster.get("limits", {}) if roster.get("limits") is Dictionary else {}
	for raw in (roster.get("ships", []) as Array):
		if raw is Dictionary:
			var sid := String((raw as Dictionary).get("ship_id", ""))
			if sid != "":
				ships_by_id[sid] = (raw as Dictionary).duplicate(true)
	ready = true
	return true

## 兼容 Formations 的 assignments（ship_id→slot）或 {"ships":[{...}]}。
func normalize_selection(selection) -> Array:
	var rows: Array = []
	if selection is Dictionary:
		if selection.get("ships") is Array:
			for raw in (selection.get("ships") as Array):
				if raw is Dictionary:
					rows.append((raw as Dictionary).duplicate(true))
		elif selection.get("assignments") is Dictionary:
			for sid in (selection.get("assignments") as Dictionary).keys():
				rows.append({"ship_id": String(sid),
					"slot": String((selection.get("assignments") as Dictionary)[sid])})
		return rows
	if selection is Array:
		for raw2 in selection:
			if raw2 is Dictionary:
				var r: Dictionary = (raw2 as Dictionary).duplicate(true)
				if not r.has("slot") and String(r.get("assigned_slot", "")) != "":
					r["slot"] = String(r.get("assigned_slot", ""))
				rows.append(r)
	return rows

func plan(selection) -> Dictionary:
	var rows := normalize_selection(selection)
	var result := {"ok": false, "reason": "", "errors": [], "warnings": [],
		"schema": SCHEMA, "scenario_id": scenario_id,
		"deployment_seed": deployment_seed, "revision": "",
		"instance_ids": [], "entities": [], "instances": []}
	if rows.is_empty():
		result["reason"] = "empty_selection"
		result["errors"].append("empty_selection")
		return result
	var instances: Array = []
	var entities: Array = []
	var seen_instance: Dictionary = {}
	var seen_ship: Dictionary = {}
	var slot_used: Dictionary = {}
	var slot_cap_total := 0
	for idx in range(rows.size()):
		var row: Dictionary = rows[idx]
		var ship_id := String(row.get("ship_id", ""))
		var slot := String(row.get("slot", ""))
		if ship_id == "":
			result["errors"].append("missing_ship_id")
			continue
		if not ships_by_id.has(ship_id):
			result["errors"].append("unknown_ship:" + ship_id)
			continue
		var r: Dictionary = ships_by_id[ship_id]
		var class_id := String(r.get("class_id", ""))
		if not (catalog.classes_by_id as Dictionary).has(class_id):
			result["errors"].append("unknown_class:%s:%s" % [ship_id, class_id])
			continue
		var inst_id := String(row.get("instance_id", ship_id.to_lower()))
		if inst_id == "" or not _id_ok(inst_id):
			result["errors"].append("invalid_instance_id:" + inst_id)
			continue
		if seen_instance.has(inst_id):
			result["errors"].append("duplicate_instance_id:" + inst_id)
			continue
		if seen_ship.has(ship_id):
			result["errors"].append("duplicate_named_hull:" + ship_id)
			continue
		if not slot_defs.has(slot):
			result["errors"].append("unknown_slot:" + slot)
			continue
		var sdef: Dictionary = slot_defs[slot] if slot_defs[slot] is Dictionary else {}
		var cap := int(sdef.get("cap", 0))
		var used := int(slot_used.get(slot, 0))
		if cap > 0 and used + 1 > cap:
			result["errors"].append("slot_overflow:" + slot)
			continue
		var roles: Array = sdef.get("roles", []) if sdef.get("roles") is Array else []
		var fr: Array = r.get("formation_roles", []) if \
			r.get("formation_roles") is Array else []
		var role := String(r.get("role", ""))
		if roles.size() > 0 and not (role in roles) and not _any_in(fr, roles):
			result["errors"].append("role_mismatch:%s:%s" % [ship_id, slot])
			continue
		var cls: Dictionary = catalog.classes_by_id[class_id] if \
			catalog.classes_by_id[class_id] is Dictionary else {}
		var mass_t := float(cls.get("displacement_t", 0.0))
		if mass_t <= 0.0:
			result["errors"].append("invalid_mass:" + ship_id)
			continue
		var fuel_t := float(r.get("fuel_t", 0.0))
		if fuel_t < 0.0:
			result["errors"].append("invalid_fuel:" + ship_id)
			continue
		seen_instance[inst_id] = true
		seen_ship[ship_id] = true
		slot_used[slot] = used + 1
		slot_cap_total += 1
		var pos: Array = [0.0, 0.0, 0.0]
		var vel: Array = [0.0, 0.0, 0.0]
		var pos_map: Dictionary = _cfg.get("positions", {}) if \
			_cfg.get("positions") is Dictionary else {}
		if pos_map.has(ship_id) and pos_map[ship_id] is Dictionary:
			var pm: Dictionary = pos_map[ship_id]
			if pm.get("pos_km") is Array:
				pos = (pm.get("pos_km") as Array).duplicate()
			if pm.get("vel_kmps") is Array:
				vel = (pm.get("vel_kmps") as Array).duplicate()
		else:
			pos = [float(idx) * 10.0, 0.0, 0.0]
		if not _vec3_ok(pos):
			result["errors"].append("invalid_position:" + ship_id)
			continue
		if not _vec3_ok(vel):
			result["errors"].append("invalid_velocity:" + ship_id)
			continue
		var ent := {
			"id": inst_id, "kind": "ship", "name": String(r.get("name_en", ship_id)),
			"class_id": class_id, "ship_id": ship_id, "hull_code":
				String(r.get("hull_code", "")), "slot": slot,
			"pos_km": pos, "vel_kmps": vel,
			"mass_kg": mass_t * MASS_T_TO_KG, "mass_t": mass_t,
			"fuel_kg": fuel_t * MASS_T_TO_KG, "fuel_t": fuel_t,
			"dv_kmps": float(cls.get("dv_kmps", 0.0)),
			"controller_id": String(row.get("controller_id",
				_cfg.get("controller_id", "player_ctrl"))),
			"owner_id": String(row.get("owner_id",
				_cfg.get("owner_id", "player_intel"))),
			"fleet_id": String(row.get("fleet_id",
				_cfg.get("fleet_id", "own_fleet"))),
			"domain_id": String(row.get("domain_id",
				_cfg.get("domain_id", "player"))),
		}
		entities.append(ent)
		instances.append({"instance_id": inst_id, "ship_id": ship_id,
			"class_id": class_id, "slot": slot,
			"mass_t": mass_t, "mass_kg": mass_t * MASS_T_TO_KG,
			"fuel_t": fuel_t, "fuel_kg": fuel_t * MASS_T_TO_KG,
			"controller_id": String(ent["controller_id"]),
			"owner_id": String(ent["owner_id"]),
			"fleet_id": String(ent["fleet_id"]),
			"domain_id": String(ent["domain_id"])})
	# 预算/槽位
	var total_mass_t := 0.0
	for ins in instances:
		total_mass_t += float((ins as Dictionary).get("mass_t", 0.0))
	var max_ships := int(limits.get("max_ships", 0))
	if max_ships > 0 and slot_cap_total > max_ships:
		result["errors"].append("over_max_ships:%d>%d" % [slot_cap_total, max_ships])
	var max_mass := float(limits.get("max_mass_t", 0.0))
	if max_mass > 0.0 and total_mass_t > max_mass + 1.0e-9:
		result["errors"].append("over_max_mass:%.3f>%.3f" % [total_mass_t, max_mass])
	if bool(slot_defs.get("command", {}).get("required", false)) \
			and int(slot_used.get("command", 0)) < 1:
		result["errors"].append("missing_required_slot:command")
	if not (result["errors"] as Array).is_empty():
		result["reason"] = String((result["errors"] as Array)[0])
		return result
	instances.sort_custom(func(a, b):
		return String((a as Dictionary).get("instance_id", "")) < \
			String((b as Dictionary).get("instance_id", "")))
	entities.sort_custom(func(a, b):
		return String((a as Dictionary).get("id", "")) < \
			String((b as Dictionary).get("id", "")))
	var rev_payload := {"scenario_id": scenario_id,
		"deployment_seed": deployment_seed,
		"instances": instances.duplicate(true)}
	result["revision"] = "rev-%08x" % (hash(JSON.stringify(rev_payload)) & 0xffffffff)
	result["instance_ids"] = _ids(instances)
	result["instances"] = instances
	result["entities"] = entities
	result["total_mass_t"] = total_mass_t
	result["ok"] = true
	return result

func deploy(selection, opts := {}) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	if not bool(o.get("confirm", false)):
		return {"ok": false, "reason": "confirm_required"}
	var p: Dictionary = plan(selection)
	if not bool(p.get("ok", false)):
		return {"ok": false, "reason": String(p.get("reason", "invalid_selection")),
			"errors": (p.get("errors", []) as Array).duplicate()}
	var rev := String(p.get("revision", ""))
	if not _committed.is_empty():
		if String(_committed.get("revision", "")) == rev:
			return {"ok": true, "reason": "already_deployed",
				"revision": rev, "deployment": _committed.duplicate(true),
				"already": true}
		return {"ok": false, "reason": "deployment_locked",
			"revision": rev, "deployed_revision": String(_committed.get("revision", ""))}
	_committed = {"schema": SCHEMA, "scenario_id": scenario_id,
		"deployment_seed": deployment_seed, "revision": rev,
		"instance_ids": (p.get("instance_ids", []) as Array).duplicate(),
		"instances": (p.get("instances", []) as Array).duplicate(true),
		"entities": (p.get("entities", []) as Array).duplicate(true),
		"total_mass_t": float(p.get("total_mass_t", 0.0)),
		"deployed_t": 0.0}
	_resources = {}
	for raw in (p.get("instances", []) as Array):
		var ins: Dictionary = raw
		var iid := String(ins.get("instance_id", ""))
		_resources[iid] = {"instance_id": iid,
			"ship_id": String(ins.get("ship_id", "")),
			"class_id": String(ins.get("class_id", "")),
			"resources": {"fuel_kg": float(ins.get("fuel_kg", 0.0)),
				"ammo": int(ins.get("ammo", 0)),
				"damage_taken": 0.0, "loadout": {}}}
	return {"ok": true, "reason": "", "revision": rev,
		"deployment": _committed.duplicate(true), "already": false}

func committed() -> Dictionary:
	return _committed.duplicate(true)

func is_committed() -> bool:
	return not _committed.is_empty()

func resources(instance_id: String) -> Dictionary:
	if not _resources.has(instance_id):
		return {"ok": false, "reason": "unknown_instance", "instance_id": instance_id}
	var row: Dictionary = (_resources[instance_id] as Dictionary).duplicate(true)
	# 附带冻结实例静态字段（mass_t/mass_kg/fuel_kg/槽位等），资源仍在独立桶内。
	for raw in (_committed.get("instances", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get(
				"instance_id", "")) == instance_id:
			for k in ["ship_id", "class_id", "slot", "mass_t", "mass_kg",
					"fuel_t", "fuel_kg", "controller_id", "owner_id",
					"fleet_id", "domain_id"]:
				if (raw as Dictionary).has(k):
					row[k] = (raw as Dictionary)[k]
			break
	row["ok"] = true
	return row

func patch(instance_id: String, patch_row: Dictionary) -> Dictionary:
	if not _resources.has(instance_id):
		return {"ok": false, "reason": "unknown_instance"}
	var row: Dictionary = _resources[instance_id]
	if patch_row.get("resources") is Dictionary:
		var res: Dictionary = row.get("resources", {})
		for k in (patch_row.get("resources") as Dictionary).keys():
			res[String(k)] = (patch_row.get("resources") as Dictionary)[k]
		row["resources"] = res
	return {"ok": true, "instance": row.duplicate(true)}

func vm() -> Dictionary:
	var inst_rows: Array = []
	for raw in (roster.get("ships", []) as Array):
		pass
	for iid in (_committed.get("instance_ids", []) as Array):
		inst_rows.append(_resources.get(String(iid), {}).duplicate(true))
	return {"schema": SCHEMA, "ok": true, "enabled": true,
		"scenario_id": scenario_id, "deployment_seed": deployment_seed,
		"revision": String(_committed.get("revision", "")),
		"deployed": not _committed.is_empty(),
		"instance_ids": (_committed.get("instance_ids", []) as Array).duplicate(),
		"instances": inst_rows,
		"limits": limits.duplicate(true), "units": {"mass": "kg", "fuel": "kg",
			"dv": "km/s", "time": "s"}}

func export_state() -> Dictionary:
	return {"schema": STATE_SCHEMA, "version": STATE_VERSION,
		"scenario_id": scenario_id, "deployment_seed": deployment_seed,
		"committed": JSON.parse_string(JSON.stringify(_committed)),
		"resources": JSON.parse_string(JSON.stringify(_resources))}

func load_state(data) -> Dictionary:
	if data == null:
		return {"ok": true, "restore_mode": "absent"}
	if not (data is Dictionary):
		return {"ok": false, "reason": "invalid_state_type"}
	var s: Dictionary = data
	if String(s.get("schema", "")) != STATE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	var ver = s.get("version", null)
	if not (ver is int or ver is float) or not is_finite(float(ver)) \
			or absf(float(ver) - roundf(float(ver))) > 0.0 \
			or int(roundf(float(ver))) != STATE_VERSION:
		return {"ok": false, "reason": "invalid_version", "version": ver}
	var com = s.get("committed", {})
	var res = s.get("resources", {})
	if not (com is Dictionary) or not (res is Dictionary):
		return {"ok": false, "reason": "invalid_state", "errors": ["committed/resources"]}
	if not (com as Dictionary).is_empty():
		if String((com as Dictionary).get("revision", "")) == "":
			return {"ok": false, "reason": "invalid_state", "errors": ["revision"]}
		if not ((com as Dictionary).get("instance_ids", []) is Array):
			return {"ok": false, "reason": "invalid_state", "errors": ["instance_ids"]}
	_committed = (com as Dictionary).duplicate(true)
	_resources = (res as Dictionary).duplicate(true)
	return {"ok": true, "restore_mode": "full",
		"revision": String(_committed.get("revision", ""))}

func _ids(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		out.append(String((raw as Dictionary).get("instance_id", "")))
	out.sort()
	return out

func _any_in(a: Array, b: Array) -> bool:
	for x in a:
		if b.has(x):
			return true
	return false

func _id_ok(id: String) -> bool:
	if id == "":
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*$")
	return re.search(id) != null

func _vec3_ok(v) -> bool:
	if not (v is Array) or (v as Array).size() != 3:
		return false
	for x in (v as Array):
		if not (x is int or x is float) or not is_finite(float(x)):
			return false
	return true
