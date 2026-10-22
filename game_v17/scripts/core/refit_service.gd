extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5B：RefitService（APSIS 船坞改装服务）
#
# 依赖 ShipCatalog（ships_friendly.json 的 APSIS=远地点级 001）。
# 内容：framework/content/refit_options.json（24+ 模块；本版 30）。
# 只读/事务式改装：安装先进入 planned；commit 扣资源并进入 queue；
# tick 完成队列后进入 installed，派生新 stats。非法操作原子拒绝。
# 不接 UI、不写 world/TrackTable/V15、不生成实体。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.refit_service.v1"
const VERSION := "1.0.0"
const SAVE_SCHEMA := "v17.refit_save.v1"
const SAVE_VERSION := "1.0.0"
const OPTIONS_PATH := "res://framework/content/refit_options.json"
const PLATFORM_ID := "APSIS"
const CATEGORIES := ["hull", "sensor", "weapon", "defense", "utility", "dock"]
const REQUIRED_MODULE_FIELDS := ["module_id", "name", "category", "slots",
	"mass_t", "power_kw", "dv_penalty_kmps", "accel_penalty_g", "crew",
	"cost_credits", "cost_materials", "cost_days", "availability",
	"location_tags", "effects", "conflicts", "requires"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var catalog = null
var options_data: Dictionary = {}
var modules: Dictionary = {}
var module_order: Array = []
var platform: Dictionary = {}
var base_stats: Dictionary = {}
var base_slots: Dictionary = {}
var installed: Array = []
var planned: Array = []
var queue_jobs: Array = []
var resources: Dictionary = {}
var location := "L4_ANVIL"
var t_days := 0.0
var _initial_resources: Dictionary = {}

func _init(catalog_arg = null, options_arg = null, resources_arg = {}) -> void:
	setup(catalog_arg, options_arg, resources_arg)

# ── setup / load content ───────────────────────────────────────

func setup(catalog_arg = null, options_arg = null, resources_arg = {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	installed = []
	planned = []
	queue_jobs = []
	t_days = 0.0
	# 兼容 setup({catalog,options,resources}) 字典形式
	if catalog_arg is Dictionary and options_arg == null:
		var cfg: Dictionary = catalog_arg
		catalog_arg = cfg.get("catalog", null)
		options_arg = cfg.get("options", cfg.get("options_path", null))
		resources_arg = cfg.get("resources", {})
	# catalog
	catalog = catalog_arg
	if catalog == null:
		var ShipCatalogScript := load("res://scripts/core/ship_catalog.gd")
		catalog = ShipCatalogScript.new()
	if catalog == null or not (catalog.has_method("class_of")):
		errors.append("缺少 ShipCatalog")
		return false
	if not bool(catalog.ready):
		errors.append("ShipCatalog 未 ready：" + str(catalog.errors))
		return false
	# options
	var data = options_arg
	if data == null:
		var rr: Dictionary = _read_json(OPTIONS_PATH)
		if not bool(rr.get("ok", false)):
			errors.append(str(rr.get("reason", "")))
			return false
		data = rr.get("value")
	elif data is String:
		var rr2: Dictionary = _read_json(String(data))
		if not bool(rr2.get("ok", false)):
			errors.append(str(rr2.get("reason", "")))
			return false
		data = rr2.get("value")
	var vr: Dictionary = validate_options(data)
	if not bool(vr.get("ok", false)):
		for e in (vr.get("errors", []) as Array):
			errors.append(str(e))
		return false
	options_data = (data as Dictionary).duplicate(true)
	modules = {}
	module_order = []
	for raw in (options_data.get("modules", []) as Array):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		var mid := str(row.get("module_id", ""))
		modules[mid] = row
		module_order.append(mid)
	module_order.sort()
	platform = (options_data.get("platforms", {}) as Dictionary).get(PLATFORM_ID, {}) \
		as Dictionary
	var cls: Dictionary = catalog.class_of(PLATFORM_ID)
	if cls.is_empty():
		cls = catalog.class_of(str(platform.get("class_id", "")))
		if cls.is_empty():
			errors.append("ShipCatalog 找不到 APSIS 舰级")
			return false
	var pb: Dictionary = platform.get("base", {}) if platform.get("base") is Dictionary else {}
	var base_slots_raw: Dictionary = platform.get("base_slots", {}) \
		if platform.get("base_slots") is Dictionary else {}
	base_stats = {
		"mass_t": float(cls.get("displacement_t", pb.get("mass_t", 0.0))),
		"dv_kmps": float(cls.get("dv_kmps", pb.get("dv_kmps", 0.0))),
		"accel_g": float(cls.get("accel_g", pb.get("accel_g", 0.0))),
		"crew": int(cls.get("crew", pb.get("crew", 0))),
		"power_kw": float(pb.get("power_kw", 400.0)),
		"max_mass_t": float(pb.get("max_mass_t", base_stats_mass_cap(cls))),
		"max_power_kw": float(pb.get("max_power_kw", 1200.0)),
		"min_dv_kmps": float(pb.get("min_dv_kmps", 0.5)),
		"min_accel_g": float(pb.get("min_accel_g", 0.005)),
		"dock_bays": int(platform.get("dock_bays", 2))}
	base_slots = {}
	for cat in CATEGORIES:
		base_slots[cat] = int(base_slots_raw.get(cat, 0))
	var r: Dictionary = resources_arg if resources_arg is Dictionary else {}
	resources = {"credits": int(r.get("credits", 200000)),
		"materials": int(r.get("materials", 500))}
	location = str(r.get("location", r.get("location_tag", "L4_ANVIL")))
	_initial_resources = resources.duplicate(true)
	ready = true
	return true

func base_stats_mass_cap(cls: Dictionary) -> float:
	return float(cls.get("displacement_t", 9000.0)) * 1.35

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

func validate_options(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["options 必须是对象"]}
	var d: Dictionary = data
	if str(d.get("schema", "")) != "v17.refit_options.v1":
		errs.append("options schema 必须为 v17.refit_options.v1")
	if not (d.get("platforms") is Dictionary):
		errs.append("缺少 platforms")
	elif not ((d.get("platforms") as Dictionary).get(PLATFORM_ID) is Dictionary):
		errs.append("缺少平台 APSIS")
	if not (d.get("modules") is Array) or (d.get("modules", []) as Array).size() < 24:
		errs.append("modules 至少 24 个")
	var ids: Dictionary = {}
	for raw in (d.get("modules", []) as Array) if d.get("modules") is Array else []:
		if not (raw is Dictionary):
			errs.append("module 必须是对象")
			continue
		var m: Dictionary = raw
		var mid := str(m.get("module_id", ""))
		if mid == "":
			errs.append("module_id 不能为空")
		elif ids.has(mid):
			errs.append("module_id 重复：" + mid)
		ids[mid] = true
		if not str(m.get("category", "")) in CATEGORIES:
			errs.append("category 非法：" + mid)
		for f in ["slots", "mass_t", "power_kw", "dv_penalty_kmps",
				"accel_penalty_g", "crew", "cost_credits", "cost_materials", "cost_days"]:
			var v = m.get(f, null)
			if not (v is int or v is float):
				errs.append("字段必须是数字：" + mid + "." + str(f))
		if not (m.get("location_tags") is Array):
			errs.append("location_tags 必须是数组：" + mid)
		if not (m.get("effects") is Dictionary):
			errs.append("effects 必须是对象：" + mid)
		if not bool(m.get("proposal", false)):
			errs.append("module proposal 必须 true：" + mid)
	# conflicts/requires 目标必须存在
	for raw2 in (d.get("modules", []) as Array) if d.get("modules") is Array else []:
		if not (raw2 is Dictionary):
			continue
		var m2: Dictionary = raw2
		var mid2 := str(m2.get("module_id", ""))
		for fld in ["conflicts", "requires"]:
			if not (m2.get(fld) is Array):
				errs.append(m2.get("module_id", "") + "." + str(fld) + " 必须是数组")
				continue
			for rel in (m2.get(fld) as Array):
				if not ids.has(str(rel)):
					errs.append(str(mid2) + "." + str(fld) + " 引用未知模块：" + str(rel))
	return {"ok": errs.is_empty(), "errors": errs}

# ── 查询 ─────────────────────────────────────────────────────

func options(category := "") -> Array:
	var out: Array = []
	for mid in module_order:
		var row: Dictionary = modules[mid]
		if category != "" and str(row.get("category", "")) != String(category):
			continue
		out.append(row.duplicate(true))
	return out

func _module_id_of(v: Variant) -> String:
	if v is Dictionary:
		return str((v as Dictionary).get("module_id", (v as Dictionary).get("id", "")))
	return str(v)

func module(module_id = "") -> Dictionary:
	module_id = _module_id_of(module_id)
	if not modules.has(module_id):
		return {}
	return (modules[module_id] as Dictionary).duplicate(true)

func slots() -> Dictionary:
	var base: Dictionary = {}
	var used: Dictionary = {}
	var reserved: Dictionary = {}
	var used_map: Dictionary = _used_slots(installed)
	var planned_map: Dictionary = _used_slots(planned)
	for cat in CATEGORIES:
		base[cat] = int(base_slots.get(cat, 0))
		used[cat] = int(used_map.get(cat, 0))
		reserved[cat] = int(planned_map.get(cat, 0))
	var free: Dictionary = {}
	var projected: Dictionary = {}
	for cat2 in CATEGORIES:
		free[cat2] = int(base[cat2]) - int(used[cat2]) - int(reserved[cat2])
		projected[cat2] = int(base[cat2]) - int(used[cat2])
	return {"schema": SCHEMA, "base": base, "used": used, "planned": reserved,
		"reserved": reserved, "free": free, "projected_free": projected,
		"total_base": _sum_slots(base), "total_used": _sum_slots(used),
		"total_free": _sum_slots(free)}

func _used_slots(list: Array) -> Dictionary:
	var out: Dictionary = {}
	for mid in list:
		var m: Dictionary = modules.get(str(mid), {})
		if m.is_empty():
			continue
		var cat := str(m.get("category", ""))
		out[cat] = int(out.get(cat, 0)) + int(m.get("slots", 0))
	return out

func _sum_slots(d: Dictionary) -> int:
	var n := 0
	for k in d.keys():
		n += int(d[k])
	return n

func _module_ids_in(list: Array) -> Array:
	var out: Array = []
	for mid in list:
		out.append(str(mid))
	return out

func _set_union() -> Array:
	var out: Array = _module_ids_in(installed)
	for mid in planned:
		if not str(mid) in out:
			out.append(str(mid))
	return out

func _costs(list: Array) -> Dictionary:
	var credits := 0
	var materials := 0
	var days := 0
	for mid in list:
		var m: Dictionary = modules.get(str(mid), {})
		credits += int(m.get("cost_credits", 0))
		materials += int(m.get("cost_materials", 0))
		days += int(m.get("cost_days", 0))
	return {"credits": credits, "materials": materials, "days": days}

func _derived(module_ids: Array) -> Dictionary:
	var mass := float(base_stats.get("mass_t", 0.0))
	var dv := float(base_stats.get("dv_kmps", 0.0))
	var accel := float(base_stats.get("accel_g", 0.0))
	var crew := int(base_stats.get("crew", 0))
	var power_gen := float(base_stats.get("power_kw", 0.0))
	var power_use := 0.0
	var effects: Dictionary = {}
	var slots_used: Dictionary = {}
	for mid in module_ids:
		var m: Dictionary = modules.get(str(mid), {})
		if m.is_empty():
			continue
		mass += float(m.get("mass_t", 0.0))
		dv -= float(m.get("dv_penalty_kmps", 0.0))
		accel -= float(m.get("accel_penalty_g", 0.0))
		crew += int(m.get("crew", 0))
		var pk := float(m.get("power_kw", 0.0))
		if pk >= 0.0:
			power_use += pk
		else:
			power_gen += -pk
		var cat := str(m.get("category", ""))
		slots_used[cat] = int(slots_used.get(cat, 0)) + int(m.get("slots", 0))
		if m.get("effects") is Dictionary:
			for ek in (m.get("effects") as Dictionary).keys():
				effects[str(ek)] = float(effects.get(str(ek), 0.0)) + float((m.get("effects") as Dictionary)[ek])
	# effects 中的 Δv bonus
	dv += float(effects.get("dv_bonus", 0.0))
	var min_dv := float(base_stats.get("min_dv_kmps", 0.5))
	var min_acc := float(base_stats.get("min_accel_g", 0.005))
	return {"mass_t": snappedf(mass, 0.001),
		"dv_kmps": snappedf(maxf(min_dv, dv), 0.001),
		"accel_g": snappedf(maxf(min_acc, accel), 0.001),
		"crew": crew, "power_generation_kw": snappedf(power_gen, 0.001),
		"power_used_kw": snappedf(power_use, 0.001),
		"power_headroom_kw": snappedf(power_gen - power_use, 0.001),
		"effects": effects, "slots_used": slots_used,
		"mass_cap_t": float(base_stats.get("max_mass_t", 0.0)),
		"power_cap_kw": float(base_stats.get("max_power_kw", 0.0))}

func stats() -> Dictionary:
	var current: Dictionary = _derived(_module_ids_in(installed))
	var projected: Dictionary = _derived(_set_union())
	var out := {"schema": SCHEMA, "ok": true, "t_days": t_days,
		"location": location, "resources": resources.duplicate(true),
		"base": base_stats.duplicate(true), "current": current,
		"projected": projected, "slots": slots(),
		"installed": _module_ids_in(installed), "planned": _module_ids_in(planned),
		"queue": queue_jobs.duplicate(true), "dock_bays": int(base_stats.get("dock_bays", 2))}
	# 便捷顶层 current 字段
	for k in ["mass_t", "dv_kmps", "accel_g", "crew", "power_generation_kw",
			"power_used_kw", "power_headroom_kw"]:
		out[k] = current.get(k)
	return out

func quote(module_id = "") -> Dictionary:
	module_id = _module_id_of(module_id)
	if not modules.has(module_id):
		return {"ok": false, "reason": "unknown_module", "module_id": module_id}
	var m: Dictionary = modules[module_id]
	var c: Dictionary = _costs([module_id])
	var with_planned: Array = _set_union()
	return {"ok": true, "module_id": module_id, "costs": c,
		"slots": {"category": m.get("category"), "slots": m.get("slots")},
		"mass_delta_t": m.get("mass_t"), "power_delta_kw": m.get("power_kw"),
		"cost_days": m.get("cost_days"),
		"resource_after": {"credits": int(resources.get("credits", 0)) - int(c["credits"]),
			"materials": int(resources.get("materials", 0)) - int(c["materials"])},
		"stats_after_install": _derived(with_planned + [module_id])}

func can_install(module_id = "") -> Dictionary:
	module_id = _module_id_of(module_id)
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not modules.has(module_id):
		return {"ok": false, "reason": "unknown_module", "module_id": module_id}
	var m: Dictionary = modules[module_id]
	if str(module_id) in installed or str(module_id) in planned:
		return {"ok": false, "reason": "already_installed_or_planned", "module_id": module_id}
	for job in queue_jobs:
		if str((job as Dictionary).get("module_id", "")) == module_id:
			return {"ok": false, "reason": "already_in_queue", "module_id": module_id}
	# availability
	var avail := str(m.get("availability", "unavailable"))
	if avail in ["unavailable", "locked", "TBD"]:
		return {"ok": false, "reason": "unavailable", "availability": avail}
	# 地点
	if not _location_ok(m):
		return {"ok": false, "reason": "wrong_location", "location": location,
			"location_tags": (m.get("location_tags", []) as Array)}
	# conflicts / requires（在 installed+planned 中）
	var union: Array = _set_union()
	var mod_conflicts: Array = m.get("conflicts", []) as Array
	for other in union:
		if str(other) in mod_conflicts:
			return {"ok": false, "reason": "conflict", "with": str(other)}
		var om: Dictionary = modules.get(str(other), {})
		if om.get("conflicts") is Array and str(module_id) in (om.get("conflicts") as Array):
			return {"ok": false, "reason": "conflict", "with": str(other)}
	for req in (m.get("requires", []) as Array):
		if not str(req) in union:
			return {"ok": false, "reason": "missing_requirement", "requires": str(req)}
	# slots
	var used: Dictionary = _used_slots(union + [module_id])
	for cat in CATEGORIES:
		if int(used.get(cat, 0)) > int(base_slots.get(cat, 0)):
			return {"ok": false, "reason": "no_slot", "category": cat,
				"used": int(used.get(cat, 0)), "base": int(base_slots.get(cat, 0))}
	# mass / power / dv / accel
	var d: Dictionary = _derived(union + [module_id])
	if float(d.get("mass_t", 0.0)) > float(base_stats.get("max_mass_t", 0.0)):
		return {"ok": false, "reason": "mass_limit", "mass_t": d.get("mass_t"),
			"max_mass_t": base_stats.get("max_mass_t")}
	if float(d.get("power_used_kw", 0.0)) > float(d.get("power_generation_kw", 0.0)) \
			or float(d.get("power_headroom_kw", 0.0)) < 0.0:
		return {"ok": false, "reason": "power_limit",
			"power_headroom_kw": d.get("power_headroom_kw")}
	if float(d.get("dv_kmps", 0.0)) < float(base_stats.get("min_dv_kmps", 0.0)):
		return {"ok": false, "reason": "dv_floor"}
	if float(d.get("accel_g", 0.0)) < float(base_stats.get("min_accel_g", 0.0)):
		return {"ok": false, "reason": "accel_floor"}
	# 成本（包含已 planned 的）
	var total_cost: Dictionary = _costs(union + [module_id])
	if int(resources.get("credits", 0)) < int(total_cost.get("credits", 0)):
		return {"ok": false, "reason": "insufficient_credits",
			"need": total_cost.get("credits"), "have": resources.get("credits")}
	if int(resources.get("materials", 0)) < int(total_cost.get("materials", 0)):
		return {"ok": false, "reason": "insufficient_materials",
			"need": total_cost.get("materials"), "have": resources.get("materials")}
	return {"ok": true, "reason": "", "module_id": module_id,
		"costs": _costs([module_id]), "total_planned_costs": total_cost,
		"stats_after": d, "slots_after": used}

func _location_ok(m: Dictionary) -> bool:
	var tags: Array = m.get("location_tags", []) as Array
	if tags.is_empty():
		return false
	if str("*") in tags:
		return true
	return location in tags

func install(module_id = "", opts := {}) -> Dictionary:
	module_id = _module_id_of(module_id)
	var o: Dictionary = opts if opts is Dictionary else {}
	var chk: Dictionary = can_install(module_id)
	if not bool(chk.get("ok", false)):
		return chk
	planned.append(module_id)
	var res := {"ok": true, "planned": true, "module_id": module_id,
		"costs": chk.get("costs", {}), "slots": slots(),
		"stats_projected": _derived(_set_union())}
	if bool(o.get("immediate", false)):
		var cr: Dictionary = commit()
		res["commit"] = cr
		res["ok"] = bool(cr.get("ok", false))
		res["installed"] = bool(cr.get("ok", false))
	return res

func install_now(module_id: String) -> Dictionary:
	return install(module_id, {"immediate": true})

func can_remove(module_id = "") -> Dictionary:
	module_id = _module_id_of(module_id)
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if str(module_id) in planned:
		return {"ok": true, "where": "planned"}
	if str(module_id) in installed:
		for other in installed:
			if str(other) == module_id:
				continue
			var om: Dictionary = modules.get(str(other), {})
			if om.get("requires") is Array and str(module_id) in (om.get("requires") as Array):
				return {"ok": false, "reason": "required_by_installed", "by": str(other)}
		return {"ok": true, "where": "installed"}
	for job in queue_jobs:
		if str((job as Dictionary).get("module_id", "")) == module_id:
			return {"ok": true, "where": "queue"}
	return {"ok": false, "reason": "not_installed", "module_id": module_id}

func remove(module_id = "") -> Dictionary:
	module_id = _module_id_of(module_id)
	var chk: Dictionary = can_remove(module_id)
	if not bool(chk.get("ok", false)):
		return chk
	var where := str(chk.get("where", ""))
	if where == "planned":
		planned.erase(module_id)
		return {"ok": true, "removed": true, "where": "planned", "module_id": module_id,
			"slots": slots()}
	if where == "installed":
		installed.erase(module_id)
		return {"ok": true, "removed": true, "where": "installed",
			"module_id": module_id, "stats": stats()}
	if where == "queue":
		for i in range(queue_jobs.size() - 1, -1, -1):
			if str((queue_jobs[i] as Dictionary).get("module_id", "")) == module_id:
				queue_jobs.remove_at(i)
				return {"ok": true, "removed": true, "where": "queue",
					"module_id": module_id, "queue": queue_jobs.duplicate(true)}
	return {"ok": false, "reason": "not_installed"}

func commit() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if planned.is_empty():
		return {"ok": true, "committed": [], "queue": queue_jobs.duplicate(true), "costs": {}}
	# 提交前整体校验（以 installed+planned 为最终集合）
	var union: Array = _set_union()
	var slots_used: Dictionary = _used_slots(union)
	for cat in CATEGORIES:
		if int(slots_used.get(cat, 0)) > int(base_slots.get(cat, 0)):
			return {"ok": false, "reason": "no_slot", "category": cat}
	var d: Dictionary = _derived(union)
	if float(d.get("mass_t", 0.0)) > float(base_stats.get("max_mass_t", 0.0)):
		return {"ok": false, "reason": "mass_limit"}
	if float(d.get("power_headroom_kw", 0.0)) < 0.0:
		return {"ok": false, "reason": "power_limit"}
	if float(d.get("dv_kmps", 0.0)) < float(base_stats.get("min_dv_kmps", 0.0)):
		return {"ok": false, "reason": "dv_floor"}
	if float(d.get("accel_g", 0.0)) < float(base_stats.get("min_accel_g", 0.0)):
		return {"ok": false, "reason": "accel_floor"}
	# requires 全部满足
	for mid in union:
		var m: Dictionary = modules.get(str(mid), {})
		for req in (m.get("requires", []) as Array):
			if not str(req) in union:
				return {"ok": false, "reason": "missing_requirement",
					"module_id": str(mid), "requires": str(req)}
	# 冲突（含双向）
	for i in range(union.size()):
		for j in range(i + 1, union.size()):
			var a := str(union[i])
			var b := str(union[j])
			var ma: Dictionary = modules.get(a, {})
			var mb: Dictionary = modules.get(b, {})
			if (ma.get("conflicts") is Array and b in (ma.get("conflicts") as Array)) \
					or (mb.get("conflicts") is Array and a in (mb.get("conflicts") as Array)):
				return {"ok": false, "reason": "conflict", "a": a, "b": b}
	var cost: Dictionary = _costs(planned)
	if int(resources.get("credits", 0)) < int(cost.get("credits", 0)):
		return {"ok": false, "reason": "insufficient_credits",
			"need": cost.get("credits"), "have": resources.get("credits")}
	if int(resources.get("materials", 0)) < int(cost.get("materials", 0)):
		return {"ok": false, "reason": "insufficient_materials",
			"need": cost.get("materials"), "have": resources.get("materials")}
	# 扣资源并入队
	resources["credits"] = int(resources.get("credits", 0)) - int(cost.get("credits", 0))
	resources["materials"] = int(resources.get("materials", 0)) - int(cost.get("materials", 0))
	var committed: Array = _module_ids_in(planned)
	for mid2 in committed:
		var m2: Dictionary = modules.get(mid2, {})
		queue_jobs.append({"module_id": mid2, "days_remaining": int(m2.get("cost_days", 0)),
			"total_days": int(m2.get("cost_days", 0)),
			"started_t_days": t_days,
			"category": str(m2.get("category", "")),
			"credits": int(m2.get("cost_credits", 0)),
			"materials": int(m2.get("cost_materials", 0))})
	planned = []
	return {"ok": true, "reason": "", "committed": committed,
		"costs": cost, "resources": resources.duplicate(true),
		"queue": queue_jobs.duplicate(true), "t_days": t_days}

func tick(days: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not is_finite(days) or days < 0.0:
		return {"ok": false, "reason": "invalid_days"}
	t_days += days
	var completed: Array = []
	var remaining: Array = []
	for raw in queue_jobs:
		if not (raw is Dictionary):
			continue
		var job: Dictionary = raw
		job["days_remaining"] = float(job.get("days_remaining", 0.0)) - days
		if float(job["days_remaining"]) <= 1.0e-9:
			completed.append(str(job.get("module_id", "")))
			installed.append(str(job.get("module_id", "")))
		else:
			remaining.append(job)
	queue_jobs = remaining
	return {"ok": true, "t_days": t_days, "completed": completed,
		"queue": queue_jobs.duplicate(true), "installed": _module_ids_in(installed),
		"stats": stats()}

## 已完成提交、等待 tick 的改装作业队列。
func queue() -> Array:
	return queue_jobs.duplicate(true)

## 兼容别名。
func queue_list() -> Array:
	return queue_jobs.duplicate(true)

func reset() -> Dictionary:
	installed = []
	planned = []
	queue_jobs = []
	t_days = 0.0
	resources = _initial_resources.duplicate(true)
	return {"ok": true, "reset": true, "stats": stats()}

func summary() -> Dictionary:
	var cats: Dictionary = {}
	for cat in CATEGORIES:
		cats[cat] = (options(cat) as Array).size()
	return {"schema": SCHEMA, "ready": ready, "platform": PLATFORM_ID,
		"location": location, "t_days": t_days,
		"modules": modules.size(), "categories": cats,
		"base_slots": base_slots.duplicate(), "slots": slots(),
		"installed": _module_ids_in(installed), "planned": _module_ids_in(planned),
		"queue": queue_jobs.duplicate(true), "resources": resources.duplicate(true),
		"stats": stats(), "proposal": true, "truth": false,
		"writes": {"ui": false, "world": false, "combat": false, "v15": false}}

func save_state() -> Dictionary:
	return {"schema": SAVE_SCHEMA, "version": SAVE_VERSION,
		"platform": PLATFORM_ID, "location": location, "t_days": t_days,
		"resources": resources.duplicate(true), "installed": _module_ids_in(installed),
		"planned": _module_ids_in(planned), "queue": queue_jobs.duplicate(true)}

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
	var inst: Array = p.get("installed", []) as Array if p.get("installed") is Array else []
	var plan: Array = p.get("planned", []) as Array if p.get("planned") is Array else []
	var q: Array = p.get("queue", []) as Array if p.get("queue") is Array else []
	var all: Dictionary = {}
	for mid in inst + plan:
		if not modules.has(str(mid)):
			return {"ok": false, "reason": "unknown_module", "module_id": str(mid)}
		if all.has(str(mid)):
			return {"ok": false, "reason": "duplicate_module", "module_id": str(mid)}
		all[str(mid)] = true
	for job in q:
		if not (job is Dictionary):
			return {"ok": false, "reason": "invalid_queue"}
		var jmid := str((job as Dictionary).get("module_id", ""))
		if not modules.has(jmid):
			return {"ok": false, "reason": "unknown_module", "module_id": jmid}
		if all.has(jmid):
			return {"ok": false, "reason": "duplicate_module", "module_id": jmid}
		all[jmid] = true
	var r: Dictionary = p.get("resources", {}) if p.get("resources") is Dictionary else {}
	if not (r.get("credits", null) is int or r.get("credits", null) is float):
		return {"ok": false, "reason": "invalid_resources"}
	if not (r.get("materials", null) is int or r.get("materials", null) is float):
		return {"ok": false, "reason": "invalid_resources"}
	# commit atomically
	installed = []
	for mid2 in inst:
		installed.append(str(mid2))
	planned = []
	for mid3 in plan:
		planned.append(str(mid3))
	queue_jobs = []
	for rawj in q:
		var job2: Dictionary = (rawj as Dictionary).duplicate(true)
		queue_jobs.append(job2)
	resources = {"credits": int(r.get("credits", 0)),
		"materials": int(r.get("materials", 0))}
	location = str(p.get("location", location))
	t_days = float(p.get("t_days", 0.0))
	return {"ok": true, "reason": "", "installed": installed.size(),
		"planned": planned.size(), "queue": queue_jobs.size(), "t_days": t_days}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("RefitService 未 ready")
	var seen: Dictionary = {}
	for group in [installed, planned]:
		for mid in group:
			if not modules.has(str(mid)):
				v.append("未知模块：" + str(mid))
			if seen.has(str(mid)):
				v.append("模块重复：" + str(mid))
			seen[str(mid)] = true
	for job in queue_jobs:
		if not (job is Dictionary):
			v.append("queue 行必须是对象")
			continue
		var mid2 := str((job as Dictionary).get("module_id", ""))
		if not modules.has(mid2):
			v.append("queue 未知模块：" + str(mid2))
		if seen.has(mid2):
			v.append("queue 模块重复：" + str(mid2))
		seen[mid2] = true
	var slots_used: Dictionary = _used_slots(installed + planned)
	for cat in CATEGORIES:
		if int(slots_used.get(cat, 0)) > int(base_slots.get(cat, 0)):
			v.append("槽位超限：" + str(cat))
	var d: Dictionary = _derived(_set_union())
	if float(d.get("mass_t", 0.0)) > float(base_stats.get("max_mass_t", 0.0)):
		v.append("超过质量上限")
	if float(d.get("power_headroom_kw", 0.0)) < 0.0:
		v.append("功率不足")
	if int(resources.get("credits", 0)) < 0:
		v.append("credits 为负")
	if int(resources.get("materials", 0)) < 0:
		v.append("materials 为负")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "ready": ready,
		"summary": summary(), "save_state": save_state()}
