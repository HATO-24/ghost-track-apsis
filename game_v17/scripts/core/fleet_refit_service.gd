extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5F：FleetRefitService（全舰队改装）
#
# 复用已提交 RefitService：每艘友舰独立实例、独立 planned/queue/installed，
# 共享 credits/materials/location；按 roster 的 class_refit_policies 参数化
# 平台 stats/槽位/模块类别可用性。
# 不写 world/TrackTable/UI/V15；不生成实体。
# ═══════════════════════════════════════════════════════════════════

const RefitServiceScript := preload("res://scripts/core/refit_service.gd")
const ShipCatalogScript := preload("res://scripts/core/ship_catalog.gd")
const ROSTER_PATH := "res://framework/content/fleet_roster.json"
const REFIT_OPTIONS_PATH := "res://framework/content/refit_options.json"
const SCHEMA := "v17.fleet_refit.v1"
const VERSION := "1.0.0"
const SAVE_SCHEMA := "v17.fleet_refit_save.v1"
const SAVE_VERSION := "1.0.0"
const CATEGORIES := ["hull", "sensor", "weapon", "defense", "utility", "dock"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var catalog = null
var roster: Dictionary = {}
var ships: Array = []
var ships_by_id: Dictionary = {}
var services: Dictionary = {}
var service_order: Array = []
var policies: Dictionary = {}
var resources: Dictionary = {}
var location := "L4_ANVIL"
var selected_ship := ""
var _initial_resources: Dictionary = {}
var _roster_path := ROSTER_PATH
var _options_path := REFIT_OPTIONS_PATH

func _init(catalog_arg = null, roster_arg = null, options_arg = null, resources_arg = {}) -> void:
	setup(catalog_arg, roster_arg, options_arg, resources_arg)

func setup(catalog_arg = null, roster_arg = null, options_arg = null, resources_arg = {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	# dict 形式 setup({catalog,roster,options,resources})
	if catalog_arg is Dictionary and roster_arg == null:
		var cfg: Dictionary = catalog_arg
		catalog_arg = cfg.get("catalog", null)
		roster_arg = cfg.get("roster", cfg.get("roster_path", null))
		options_arg = cfg.get("options", cfg.get("options_path", null))
		resources_arg = cfg.get("resources", {})
	catalog = catalog_arg
	if catalog == null:
		catalog = ShipCatalogScript.new()
	if catalog == null or not catalog.has_method("class_of"):
		errors.append("缺少 ShipCatalog")
		return false
	if not bool(catalog.ready):
		errors.append("ShipCatalog 未 ready：" + str(catalog.errors))
		return false
	# roster
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
	var rres: Dictionary = resources_arg if resources_arg is Dictionary else {}
	resources = {"credits": int(rres.get("credits", 300000)),
		"materials": int(rres.get("materials", 1000))}
	location = str(rres.get("location", rres.get("location_tag", "L4_ANVIL")))
	_initial_resources = resources.duplicate(true)
	policies = (roster.get("class_refit_policies", {}) as Dictionary).duplicate(true)
	ships = []
	ships_by_id = {}
	services = {}
	service_order = []
	for raw in (roster.get("ships", []) as Array):
		if not (raw is Dictionary):
			continue
		var sh: Dictionary = (raw as Dictionary).duplicate(true)
		var sid := str(sh.get("ship_id", ""))
		if sid == "":
			continue
		sh["formation_roles"] = (sh.get("formation_roles", []) as Array).duplicate() \
			if sh.get("formation_roles") is Array else []
		sh["assigned_slot"] = sh.get("assigned_slot", null)
		if not sh.has("refit_state") or not (sh.get("refit_state") is Dictionary):
			sh["refit_state"] = {}
		var policy: Dictionary = (policies.get(str(sh.get("class_id", "")), {}) as Dictionary)
		var serv = RefitServiceScript.new(catalog, _options_arg(options_arg),
			resources.duplicate(true))
		if not bool(serv.ready):
			errors.append("舰只 %s RefitService 失败：%s" % [sid, str(serv.errors)])
			continue
		_apply_ship_platform(serv, sh, policy)
		serv.location = location
		serv.resources = resources.duplicate(true)
		services[sid] = serv
		service_order.append(sid)
		ships.append(sh)
		ships_by_id[sid] = sh
	service_order.sort()
	ships.sort_custom(func(a, b): return str(a.get("ship_id", "")) < str(b.get("ship_id", "")))
	if services.size() != ships.size():
		errors.append("部分舰只 RefitService 初始化失败")
		return false
	if service_order.is_empty():
		errors.append("roster 没有可用舰只")
		return false
	selected_ship = str(ships_by_id.get("APSIS", {}).get("ship_id", service_order[0])) \
		if ships_by_id.has("APSIS") else service_order[0]
	ready = errors.is_empty()
	return ready

func _options_arg(v: Variant) -> Variant:
	if v == null:
		return REFIT_OPTIONS_PATH
	return v

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
		errs.append("roster schema 必须 v17.fleet_roster.v1")
	if not bool(d.get("proposal", false)):
		errs.append("roster proposal 必须 true")
	if not (d.get("slots") is Dictionary):
		errs.append("缺 slots")
	if not (d.get("limits") is Dictionary):
		errs.append("缺 limits")
	if not (d.get("class_refit_policies") is Dictionary):
		errs.append("缺 class_refit_policies")
	if not (d.get("ships") is Array) or (d.get("ships", []) as Array).is_empty():
		errs.append("ships 必须是非空数组")
	var ship_ids: Dictionary = {}
	var class_ids: Dictionary = {}
	for raw in (d.get("ships", []) as Array):
		if not (raw is Dictionary):
			errs.append("ship 必须是对象")
			continue
		var sh: Dictionary = raw
		var sid := str(sh.get("ship_id", ""))
		if sid == "":
			errs.append("ship_id 不能为空")
		elif ship_ids.has(sid):
			errs.append("ship_id 重复：" + sid)
		ship_ids[sid] = true
		var cid := str(sh.get("class_id", ""))
		if cid == "":
			errs.append("class_id 不能为空：" + sid)
		elif catalog != null and bool(catalog.ready):
			if catalog.class_of(cid).is_empty():
				errs.append("ShipCatalog 未知 class：" + cid)
		class_ids[cid] = true
		for f in ["name", "role", "status"]:
			if str(sh.get(f, "")) == "":
				errs.append("ship 缺字段 %s：%s" % [str(f), sid])
		if not (sh.get("formation_roles") is Array) or (sh.get("formation_roles") as Array).is_empty():
			errs.append("formation_roles 必须非空：" + sid)
		for nf in ["fuel_t", "repair_slots_required"]:
			if not (sh.get(nf) is int or sh.get(nf) is float):
				errs.append("ship 数值字段必须是数字：" + sid + "." + str(nf))
	# policies 必须覆盖所有 class
	for cid2 in class_ids.keys():
		if not ((d.get("class_refit_policies", {}) as Dictionary).has(str(cid2))):
			errs.append("缺 class_refit_policies：" + str(cid2))
	for pcid in (d.get("class_refit_policies", {}) as Dictionary).keys():
		var pol: Dictionary = (d.get("class_refit_policies", {}) as Dictionary)[pcid]
		if not (pol.get("slots") is Dictionary):
			errs.append("policy slots 必须是对象：" + str(pcid))
			continue
		for cat in CATEGORIES:
			if not (pol.get("slots", {}) as Dictionary).has(cat):
				errs.append("policy 缺槽位类别 %s：%s" % [str(cat), str(pcid)])
		if not (pol.get("allowed_categories") is Array):
			errs.append("policy allowed_categories 必须是数组：" + str(pcid))
	return {"ok": errs.is_empty(), "errors": errs}

func _apply_ship_platform(serv, ship: Dictionary, policy: Dictionary) -> void:
	var cls: Dictionary = catalog.class_of(str(ship.get("class_id", "")))
	if cls.is_empty():
		return
	var mass := float(cls.get("displacement_t", 1.0))
	serv.base_stats = {
		"mass_t": mass,
		"dv_kmps": float(cls.get("dv_kmps", 0.0)),
		"accel_g": float(cls.get("accel_g", 0.0)),
		"crew": int(cls.get("crew", 0)),
		"power_kw": float(policy.get("power_kw", 100.0)),
		"max_mass_t": float(policy.get("max_mass_t", mass * 1.35)),
		"max_power_kw": float(policy.get("max_power_kw", 500.0)),
		"min_dv_kmps": 0.1,
		"min_accel_g": 0.001,
		"dock_bays": int(policy.get("dock_bays", 0))}
	serv.base_slots = {}
	for cat in CATEGORIES:
		serv.base_slots[cat] = int((policy.get("slots", {}) as Dictionary).get(cat, 0))
	serv.platform = {"ship_id": str(ship.get("ship_id", "")),
		"class_id": str(ship.get("class_id", "")), "name": str(ship.get("name", "")),
		"dock_bays": int(policy.get("dock_bays", 0)), "base_slots": serv.base_slots.duplicate()}
	serv.location = location

func _policy(ship_id: String) -> Dictionary:
	var sh: Dictionary = ships_by_id.get(ship_id, {})
	return (policies.get(str(sh.get("class_id", "")), {}) as Dictionary).duplicate(true)

func _allowed(ship_id: String, module_id: String) -> bool:
	var pol := _policy(ship_id)
	var m: Dictionary = _module(ship_id, module_id)
	if m.is_empty():
		return false
	var allowed: Array = pol.get("allowed_categories", []) as Array
	if not allowed.is_empty() and not str(m.get("category", "")) in allowed:
		return false
	return true

func _module(ship_id: String, module_id: String) -> Dictionary:
	var serv = services.get(ship_id, null)
	if serv == null:
		return {}
	return serv.module(module_id)

func select_ship(ship_id: String) -> Dictionary:
	if not ships_by_id.has(ship_id):
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	selected_ship = ship_id
	return {"ok": true, "selected": ship_id, "stats": stats(ship_id)}

func selected() -> String:
	return selected_ship

func ships_list() -> Array:
	var out: Array = []
	for raw in ships:
		var sh: Dictionary = (raw as Dictionary).duplicate(true)
		sh["refit"] = refit_state(str(sh.get("ship_id", "")))
		out.append(sh)
	return out

func roster_view() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "ships": ships_list(),
		"policies": policies.duplicate(true), "resources": resources.duplicate(true),
		"location": location, "selected": selected_ship,
		"truth": false, "writes": {"world": false, "ui": false, "v15": false}}

func options(ship_id := "", category := "") -> Array:
	var sid := _sid(ship_id)
	if sid == "":
		return []
	var serv = services.get(sid, null)
	if serv == null:
		return []
	var out: Array = []
	for raw in (serv.options(category) as Array):
		if raw is Dictionary:
			if _allowed(sid, str((raw as Dictionary).get("module_id", ""))):
				out.append(raw)
	return out

func quote(a: Variant = "", b: Variant = "") -> Dictionary:
	var pair: Array = _args(a, b)
	var sid := str(pair[0])
	var module = pair[1]
	if sid == "":
		return {"ok": false, "reason": "no_ship_selected"}
	if not services.has(sid):
		return {"ok": false, "reason": "unknown_ship", "ship_id": sid}
	var mid := str(module if not (module is Dictionary) else (module as Dictionary).get("module_id", ""))
	if not _allowed(sid, mid):
		return {"ok": false, "reason": "module_not_available_for_class",
			"ship_id": sid, "module_id": mid}
	return services[sid].quote(module)

func can_install(a: Variant = "", b: Variant = "") -> Dictionary:
	var pair: Array = _args(a, b)
	var sid := str(pair[0])
	var module = pair[1]
	if sid == "":
		return {"ok": false, "reason": "no_ship_selected"}
	if not services.has(sid):
		return {"ok": false, "reason": "unknown_ship", "ship_id": sid}
	var mid := str(module if not (module is Dictionary) else (module as Dictionary).get("module_id", ""))
	if not _allowed(sid, mid):
		return {"ok": false, "reason": "module_not_available_for_class",
			"ship_id": sid, "module_id": mid}
	var serv = services[sid]
	serv.resources = resources.duplicate(true)
	return serv.can_install(module)

func install(a: Variant = "", b: Variant = "", opts := {}) -> Dictionary:
	var pair: Array = _args(a, b)
	var sid := str(pair[0])
	var module = pair[1]
	if sid == "":
		return {"ok": false, "reason": "no_ship_selected"}
	if not services.has(sid):
		return {"ok": false, "reason": "unknown_ship", "ship_id": sid}
	var mid := str(module if not (module is Dictionary) else (module as Dictionary).get("module_id", ""))
	if not _allowed(sid, mid):
		return {"ok": false, "reason": "module_not_available_for_class",
			"ship_id": sid, "module_id": mid}
	var serv = services[sid]
	serv.resources = resources.duplicate(true)
	var res: Dictionary = serv.install(module, opts)
	if bool(res.get("ok", false)):
		selected_ship = sid
	return res

func remove(a: Variant = "", b: Variant = "") -> Dictionary:
	var pair: Array = _args(a, b)
	var sid := str(pair[0])
	var module = pair[1]
	if sid == "":
		return {"ok": false, "reason": "no_ship_selected"}
	if not services.has(sid):
		return {"ok": false, "reason": "unknown_ship", "ship_id": sid}
	var res: Dictionary = services[sid].remove(module)
	return res

func commit(ship_id := "") -> Dictionary:
	var sid := _sid(ship_id)
	if sid == "":
		return {"ok": false, "reason": "no_ship_selected"}
	if not services.has(sid):
		return {"ok": false, "reason": "unknown_ship", "ship_id": sid}
	var serv = services[sid]
	serv.resources = resources.duplicate(true)
	var res: Dictionary = serv.commit()
	if bool(res.get("ok", false)):
		resources = serv.resources.duplicate(true)
		if bool(res.get("committed", []) is Array) and not (res.get("committed", []) as Array).is_empty():
			res["ship_id"] = sid
	return res

func commit_all() -> Dictionary:
	var out: Array = []
	for sid in service_order:
		var res: Dictionary = commit(sid)
		if bool(res.get("ok", false)):
			out.append({"ship_id": sid, "committed": res.get("committed", []),
				"costs": res.get("costs", {})})
		elif res.get("committed", []) is Array and not (res.get("committed", []) as Array).is_empty():
			out.append({"ship_id": sid, "error": res.get("reason", "")})
	return {"ok": true, "commits": out, "resources": resources.duplicate(true)}

func tick(days: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not is_finite(days) or days < 0.0:
		return {"ok": false, "reason": "invalid_days"}
	var out: Array = []
	for sid in service_order:
		var serv = services[sid]
		serv.resources = resources.duplicate(true)
		var r: Dictionary = serv.tick(days)
		out.append({"ship_id": sid, "ok": bool(r.get("ok", false)),
			"completed": r.get("completed", []), "queue": r.get("queue", [])})
	return {"ok": true, "days": days, "ships": out,
		"completed": _completed_from(out)}

func _completed_from(rows: Array) -> Array:
	var all: Array = []
	for raw in rows:
		for c in ((raw as Dictionary).get("completed", []) as Array):
			all.append(str((raw as Dictionary).get("ship_id", "")) + ":" + str(c))
	return all

func stats(ship_id := "") -> Dictionary:
	var sid := _sid(ship_id)
	if sid == "":
		return {}
	var serv = services.get(sid, null)
	if serv == null:
		return {}
	var st: Dictionary = serv.stats()
	st["ship_id"] = sid
	st["class_id"] = str(ships_by_id[sid].get("class_id", ""))
	st["name"] = str(ships_by_id[sid].get("name", ""))
	st["shared_resources"] = resources.duplicate(true)
	st["location"] = location
	return st

func ship_stats(ship_id: String) -> Dictionary:
	return stats(ship_id)

func refit_state(ship_id: String) -> Dictionary:
	var serv = services.get(ship_id, null)
	if serv == null:
		return {}
	return serv.save_state()

func all_stats() -> Array:
	var out: Array = []
	for sid in service_order:
		out.append(stats(sid))
	return out

func summary() -> Dictionary:
	var rows: Array = []
	var total_mass := 0.0
	var total = 0
	for sid in service_order:
		var st: Dictionary = stats(sid)
		var cur: Dictionary = st.get("current", {}) as Dictionary
		rows.append({"ship_id": sid, "mass_t": cur.get("mass_t", 0.0),
			"installed": (st.get("installed", []) as Array).size(),
			"planned": (st.get("planned", []) as Array).size(),
			"queue": (st.get("queue", []) as Array).size()})
		total_mass += float(cur.get("mass_t", 0.0))
		total += 1
	return {"schema": SCHEMA, "ready": ready, "ships": total, "selected": selected_ship,
		"resources": resources.duplicate(true), "location": location,
		"ships_summary": rows, "total_mass_t": snappedf(total_mass, 0.001),
		"proposal": true, "truth": false,
		"writes": {"world": false, "ui": false, "v15": false}}

func save_state() -> Dictionary:
	var ship_states: Dictionary = {}
	for sid in service_order:
		ship_states[sid] = (services[sid] as Object).save_state()
	return {"schema": SAVE_SCHEMA, "version": SAVE_VERSION,
		"selected": selected_ship, "resources": resources.duplicate(true),
		"location": location, "ship_states": ship_states}

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
	var states: Dictionary = p.get("ship_states", {}) if p.get("ship_states") is Dictionary else {}
	for sid in states.keys():
		if not services.has(str(sid)):
			return {"ok": false, "reason": "unknown_ship", "ship_id": str(sid)}
	# 全部先校验到临时服务不可行；先校验 payload 类型再逐个恢复（RefitService 内部原子）
	for sid2 in states.keys():
		if not (states[sid2] is Dictionary):
			return {"ok": false, "reason": "invalid_ship_state", "ship_id": str(sid2)}
	var new_res: Dictionary = p.get("resources", {}) if p.get("resources") is Dictionary else {}
	if not (new_res.get("credits", null) is int or new_res.get("credits", null) is float):
		return {"ok": false, "reason": "invalid_resources"}
	if not (new_res.get("materials", null) is int or new_res.get("materials", null) is float):
		return {"ok": false, "reason": "invalid_resources"}
	# 逐舰 restore；任一失败则回滚已恢复的舰（通过旧状态）
	var old_states: Dictionary = {}
	for sid3 in service_order:
		old_states[sid3] = (services[sid3] as Object).save_state()
	for sid4 in states.keys():
		var r: Dictionary = (services[str(sid4)] as Object).load_state(states[sid4])
		if not bool(r.get("ok", false)):
			for sid5 in old_states.keys():
				(services[sid5] as Object).load_state(old_states[sid5])
			return {"ok": false, "reason": "ship_state_invalid", "ship_id": str(sid4),
				"detail": r.get("reason", "")}
	resources = {"credits": int(new_res.get("credits", 0)),
		"materials": int(new_res.get("materials", 0))}
	location = str(p.get("location", location))
	selected_ship = str(p.get("selected", selected_ship))
	if not services.has(selected_ship):
		selected_ship = service_order[0]
	for sid6 in service_order:
		(services[sid6] as Object).resources = resources.duplicate(true)
		(services[sid6] as Object).location = location
	return {"ok": true, "ships": states.size(), "selected": selected_ship,
		"resources": resources.duplicate(true)}

func reset() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	for sid in service_order:
		(services[sid] as Object).reset()
		(services[sid] as Object).resources = _initial_resources.duplicate(true)
	resources = _initial_resources.duplicate(true)
	selected_ship = "APSIS" if services.has("APSIS") else service_order[0]
	return {"ok": true, "reset": true, "summary": summary()}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("FleetRefitService 未 ready")
	if services.size() != ships.size():
		v.append("services 数与 ships 数不一致")
	for sid in service_order:
		if not services.has(sid):
			v.append("缺 service：" + sid)
			continue
		var serv = services[sid]
		if not bool(serv.ready):
			v.append("ship service 未 ready：" + sid)
		var pol := _policy(sid)
		if pol.is_empty():
			v.append("缺 policy：" + sid)
		if (pol.get("allowed_categories", []) as Array).is_empty():
			v.append("policy 无 allowed_categories：" + sid)
	if int(resources.get("credits", 0)) < 0:
		v.append("共享 credits 为负")
	if int(resources.get("materials", 0)) < 0:
		v.append("共享 materials 为负")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "ready": ready,
		"roster": roster_view(), "summary": summary(),
		"save_state": save_state()}

func _sid(ship_id: Variant) -> String:
	if ship_id is String and String(ship_id) != "":
		return String(ship_id)
	return selected_ship

## 兼容 quote(module) 与 quote(ship_id,module) 两种调用。
func _looks_like_module(v: Variant) -> bool:
	if not (v is String):
		return false
	for sid in service_order:
		if services.has(sid) and not (services[sid] as Object).module(String(v)).is_empty():
			return true
	return false

func _args(a: Variant, b: Variant) -> Array:
	if a is String and ships_by_id.has(a):
		if b != "":
			return [String(a), b]
		return [String(a), ""]
	if b is String and ships_by_id.has(b):
		return [String(b), a]
	# quote/install("NOPE","module")：a 像 ship id、b 是已知模块 → 保持未知 ship
	if a is String and b is String and _looks_like_module(b) and not _looks_like_module(a):
		return [String(a), b]
	return [selected_ship, a]
