extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5A：ShipCatalog（友军/敌军舰船目录）
#
# 内容（proposal，缺失 TBD，不伪造官方定案）：
#   - framework/content/ships_friendly.json
#     OCUVF-ID13 8 型（远地点/托盘-5改/赤铁-6改/龙门-3M/月港-4/
#     安海-1/绞盘-2/咏叹-1），已知 APSIS=001、HARMATTAN=114
#   - framework/content/ships_enemy.json
#     33OSID 6 级 + 每级 2 个改装包；UEGAF-ORBFLT 6 级；
#     UEOF 7th/3rd 各 2 级
#
# 只读目录：load/validate/classes/class_of/ships/name_pool/resolve/
# known_ship/by_batch/entity_binding/summary。不接 UI/战斗/实体生成。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.ship_catalog.v1"
const VERSION := "1.0.0"
const FRIENDLY_PATH := "res://framework/content/ships_friendly.json"
const ENEMY_PATH := "res://framework/content/ships_enemy.json"
const FRIENDLY_SCHEMA := "v17.ships_friendly.v1"
const ENEMY_SCHEMA := "v17.ships_enemy.v1"
const FRIENDLY_FACTION := "ocuvf_id13"
const ENEMY_FACTIONS := ["33osid", "uegaf_orbflt", "ueof_7th", "ueof_3rd"]
const FRIENDLY_ROLES := ["depot", "picket", "gun", "missile", "tanker", "relay",
	"tug", "shuttle"]
const REQUIRED_FIELDS := ["class_id", "name", "role", "faction",
	"displacement_t", "dv_kmps", "accel_g", "crew", "sensors", "weapons",
	"armor", "dimensions_m", "sections", "known_ships", "name_pool"]
const NUMERIC_FIELDS := ["displacement_t", "dv_kmps", "accel_g", "crew"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var friendly_path := FRIENDLY_PATH
var enemy_path := ENEMY_PATH
var friendly: Dictionary = {}
var enemy: Dictionary = {}
var classes_by_id: Dictionary = {}
var class_order: Array = []
var known_by_ship: Dictionary = {}
var known_order: Array = []
var entity_bindings: Dictionary = {}

func _init(cfg := {}) -> void:
	setup(cfg)

# ── load / setup ───────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	friendly = {}
	enemy = {}
	classes_by_id = {}
	class_order = []
	known_by_ship = {}
	known_order = []
	entity_bindings = {}
	if not (cfg is Dictionary):
		errors.append("config 必须是对象")
		return false
	var c: Dictionary = cfg
	friendly_path = str(c.get("friendly_path", FRIENDLY_PATH))
	enemy_path = str(c.get("enemy_path", ENEMY_PATH))
	var lr: Dictionary = load_catalog(c.get("friendly_content", null),
		c.get("enemy_content", null))
	return bool(lr.get("ok", false))

## 读取两份内容并校验；失败不改当前状态。因 GDScript 全局 load() 冲突，
## 方法名为 load_catalog()，reload() 为别名。
func load_catalog(friendly_override = null, enemy_override = null) -> Dictionary:
	var old_errors: Array[String] = errors.duplicate()
	errors.clear()
	warnings.clear()
	var f: Variant = friendly_override
	var e: Variant = enemy_override
	if f == null:
		var fr: Dictionary = _read_json(friendly_path)
		if not bool(fr.get("ok", false)):
			errors.append("friendly: " + str(fr.get("reason", "")))
			errors = _merge_err(old_errors)
			return {"ok": false, "reason": "friendly_load_failed", "errors": errors}
		f = fr.get("value")
	if e == null:
		var er: Dictionary = _read_json(enemy_path)
		if not bool(er.get("ok", false)):
			errors.append("enemy: " + str(er.get("reason", "")))
			errors = _merge_err(old_errors)
			return {"ok": false, "reason": "enemy_load_failed", "errors": errors}
		e = er.get("value")
	var vf: Dictionary = validate_file(f, "friendly")
	var ve: Dictionary = validate_file(e, "enemy")
	for x in (vf.get("errors", []) as Array):
		errors.append("friendly: " + str(x))
	for x2 in (ve.get("errors", []) as Array):
		errors.append("enemy: " + str(x2))
	if f is Dictionary and e is Dictionary:
		var pre_u: Dictionary = _check_uniqueness_static(f, e)
		for x0 in (pre_u.get("errors", []) as Array):
			errors.append(str(x0))
	if not errors.is_empty():
		errors = _merge_err(old_errors)
		return {"ok": false, "reason": "content_invalid", "errors": errors}
	# commit atomically
	friendly = (f as Dictionary).duplicate(true)
	enemy = (e as Dictionary).duplicate(true)
	classes_by_id = {}
	class_order = []
	known_by_ship = {}
	known_order = []
	entity_bindings = {}
	_ingest(friendly, "friendly")
	_ingest(enemy, "enemy")
	var uniq: Dictionary = _check_uniqueness()
	for x3 in (uniq.get("errors", []) as Array):
		errors.append(str(x3))
	if not errors.is_empty():
		ready = false
		return {"ok": false, "reason": "uniqueness_failed", "errors": errors}
	ready = true
	return {"ok": true, "schema": SCHEMA, "ready": true,
		"friendly_classes": (friendly.get("classes", []) as Array).size(),
		"enemy_classes": (enemy.get("classes", []) as Array).size(),
		"known_ships": known_by_ship.size(), "errors": []}

func reload() -> Dictionary:
	return load_catalog(null, null)

func _merge_err(old: Array[String]) -> Array[String]:
	var out: Array[String] = errors.duplicate()
	for x in old:
		out.append(x)
	return out

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file_not_found: " + path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "file_unreadable: " + path}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json: " + path}
	return {"ok": true, "value": parsed}

func _ingest(data: Dictionary, which: String) -> void:
	for raw in (data.get("classes", []) as Array):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		var cid := str(row.get("class_id", ""))
		row["content_file"] = which
		classes_by_id[cid] = row
		class_order.append(cid)
		for sh_raw in (row.get("known_ships", []) as Array):
			if not (sh_raw is Dictionary):
				continue
			var sh: Dictionary = (sh_raw as Dictionary).duplicate(true)
			var sid := str(sh.get("ship_id", sh.get("hull_code", "")))
			if sid == "":
				continue
			sh["ship_id"] = sid
			sh["class_id"] = cid
			sh["faction"] = str(row.get("faction", ""))
			sh["class_name"] = str(row.get("name", ""))
			known_by_ship[sid] = sh
			known_order.append(sid)
	var eb: Dictionary = data.get("entity_bindings", {}) if data.get("entity_bindings") is Dictionary else {}
	for ek in eb.keys():
		entity_bindings[str(ek)] = str(eb[ek])
	class_order.sort()
	known_order.sort()

# ── validate ──────────────────────────────────────────────────

## 校验已加载内容；或校验传入的 {friendly,enemy} 候选（不改状态）。
func validate(candidate = null) -> Dictionary:
	var f = friendly
	var e = enemy
	if candidate is Dictionary and (candidate as Dictionary).get("friendly") is Dictionary:
		f = (candidate as Dictionary)["friendly"]
		e = (candidate as Dictionary).get("enemy", {})
	var vf: Dictionary = validate_file(f, "friendly")
	var ve: Dictionary = validate_file(e, "enemy")
	var errs: Array = []
	errs.append_array(vf.get("errors", []))
	errs.append_array(ve.get("errors", []))
	if f is Dictionary and e is Dictionary:
		var u: Dictionary = _check_uniqueness_static(f, e)
		errs.append_array(u.get("errors", []))
	return {"ok": errs.is_empty(), "errors": errs,
		"friendly_classes": (f.get("classes", []) as Array).size() if f is Dictionary else 0,
		"enemy_classes": (e.get("classes", []) as Array).size() if e is Dictionary else 0}

func validate_file(data, which: String) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = data
	var expected_schema := FRIENDLY_SCHEMA if which == "friendly" else ENEMY_SCHEMA
	if str(d.get("schema", "")) != expected_schema:
		errs.append("schema 必须为 " + expected_schema)
	if not bool(d.get("proposal", false)):
		errs.append("proposal 必须为 true")
	if not (d.get("classes") is Array) or (d.get("classes", []) as Array).is_empty():
		return {"ok": false, "errors": errs + ["classes 必须是非空数组"]}
	if not (d.get("name_pools") is Dictionary):
		errs.append("name_pools 必须是对象")
	var cids: Dictionary = {}
	var hulls: Dictionary = {}
	var names: Dictionary = {}
	for raw in (d.get("classes", []) as Array):
		if not (raw is Dictionary):
			errs.append("class 必须是对象")
			continue
		var row: Dictionary = raw
		var cid := str(row.get("class_id", ""))
		if cid == "":
			errs.append("class_id 不能为空")
		elif cids.has(cid):
			errs.append("class_id 重复：" + cid)
		cids[cid] = true
		for k in REQUIRED_FIELDS:
			if not row.has(k):
				errs.append("缺字段 " + k + "：" + cid)
		if not bool(row.get("proposal", false)):
			errs.append("class proposal 必须 true：" + cid)
		var name := str(row.get("name", ""))
		if name != "" and name != "TBD":
			if names.has(name):
				errs.append("class name 重复：" + name)
			names[name] = true
		for nk in NUMERIC_FIELDS:
			var v = row.get(nk, null)
			if not (v is int or v is float or (v is String and String(v) == "TBD")):
				errs.append("数值字段必须是数字或 TBD：" + cid + "." + str(nk))
		var hull := str(row.get("hull_code", row.get("hull_code_prefix", "")))
		if hull == "":
			errs.append("缺 hull_code/hull_code_prefix：" + cid)
		elif not (hull is String and String(hull) == "TBD"):
			if hulls.has(hull):
				errs.append("hull 重复：" + hull)
			hulls[hull] = true
		for af in ["sensors", "weapons", "dimensions_m", "sections", "known_ships", "name_pool"]:
			if not (row.get(af) is Array):
				errs.append("必须是数组：" + cid + "." + af)
		if row.get("weapons") is Array and (row.get("weapons") as Array).is_empty() \
				and which == "enemy":
			errs.append("enemy weapons 不能为空（可用 TBD）：" + cid)
		if row.get("known_ships") is Array:
			for sh in (row.get("known_ships") as Array):
				if not (sh is Dictionary):
					errs.append("known_ships 行必须是对象：" + cid)
					continue
				if str((sh as Dictionary).get("ship_id", "")) == "":
					errs.append("known ship 缺 ship_id：" + cid)
		if which == "friendly":
			if str(row.get("faction", "")) != FRIENDLY_FACTION:
				errs.append("friendly faction 必须为 " + FRIENDLY_FACTION + "：" + cid)
			if not str(row.get("role", "")) in FRIENDLY_ROLES:
				errs.append("friendly role 非法：" + cid)
		else:
			var fac := str(row.get("faction", ""))
			if not fac in ENEMY_FACTIONS:
				errs.append("enemy faction 非法：" + cid)
			if row.get("signature") is not Dictionary:
				errs.append("enemy signature 必须是对象：" + cid)
	# 结构数量
	if which == "friendly":
		if (d.get("classes", []) as Array).size() != 8:
			errs.append("友军必须 8 型，实际 " + str((d.get("classes", []) as Array).size()))
	if which == "enemy":
		var by_fac: Dictionary = {}
		var bases: Array = []
		var variants: Dictionary = {}
		for raw2 in (d.get("classes", []) as Array):
			if not (raw2 is Dictionary):
				continue
			var r2: Dictionary = raw2
			var fac2 := str(r2.get("faction", ""))
			by_fac[fac2] = int(by_fac.get(fac2, 0)) + 1
			var vo := str(r2.get("variant_of", ""))
			if vo == "":
				if fac2 == "33osid":
					bases.append(str(r2.get("class_id", "")))
			else:
				variants[vo] = int(variants.get(vo, 0)) + 1
		if int(by_fac.get("33osid", 0)) < 6:
			errs.append("33OSID 至少 6 级")
		for b in bases:
			var n := int(variants.get(b, 0))
			if n < 2 or n > 4:
				errs.append("33OSID " + str(b) + " 亚种数量必须 2..4，实际 " + str(n))
		if int(by_fac.get("uegaf_orbflt", 0)) < 4:
			errs.append("ORBFLT 至少 4 级")
		if int(by_fac.get("ueof_7th", 0)) < 2:
			errs.append("UEOF 第7舰队至少 2 级")
		if int(by_fac.get("ueof_3rd", 0)) < 2:
			errs.append("UEOF 第三远征舰队至少 2 级")
	return {"ok": errs.is_empty(), "errors": errs}

func _check_uniqueness() -> Dictionary:
	return _check_uniqueness_static(friendly, enemy)

func _check_uniqueness_static(f: Dictionary, e: Dictionary) -> Dictionary:
	var errs: Array = []
	var cids: Dictionary = {}
	var names: Dictionary = {}
	var ship_ids: Dictionary = {}
	var hulls: Dictionary = {}
	for pair in [[f, "friendly"], [e, "enemy"]]:
		var d: Dictionary = pair[0]
		for raw in (d.get("classes", []) as Array):
			if not (raw is Dictionary):
				continue
			var row: Dictionary = raw
			var cid := str(row.get("class_id", ""))
			if cids.has(cid):
				errs.append("class_id 全局重复：" + cid)
			cids[cid] = true
			var nm := str(row.get("name", ""))
			if nm != "" and nm != "TBD":
				if names.has(nm):
					errs.append("class name 全局重复：" + nm)
				names[nm] = true
			var hull := str(row.get("hull_code", ""))
			if hull != "" and hull != "TBD":
				if hulls.has(hull):
					errs.append("class hull 全局重复：" + hull)
				hulls[hull] = true
			for sh_raw in (row.get("known_ships", []) as Array):
				if not (sh_raw is Dictionary):
					continue
				var sh: Dictionary = sh_raw
				var sid := str(sh.get("ship_id", ""))
				var shull := str(sh.get("hull_code", ""))
				var snm := str(sh.get("name", ""))
				if ship_ids.has(sid):
					errs.append("known ship_id 重复：" + sid)
				ship_ids[sid] = true
				if shull != "" and shull != "TBD":
					if hulls.has(shull):
						errs.append("known ship hull 重复：" + shull)
					hulls[shull] = true
				if snm != "" and snm != "TBD":
					if names.has(snm):
						errs.append("known ship name 重复：" + snm)
					names[snm] = true
	return {"ok": errs.is_empty(), "errors": errs}

# ── 查询 ─────────────────────────────────────────────────────

func classes(faction := "") -> Array:
	var out: Array = []
	for cid in class_order:
		var row: Dictionary = (classes_by_id[cid] as Dictionary).duplicate(true)
		if faction != "" and str(row.get("faction", "")) != String(faction):
			continue
		out.append(row)
	return out

func class_of(query: String) -> Dictionary:
	if query == "":
		return {}
	if classes_by_id.has(query):
		return (classes_by_id[query] as Dictionary).duplicate(true)
	var sh := _find_known(query)
	if not sh.is_empty():
		return (classes_by_id.get(str(sh.get("class_id", "")), {}) as Dictionary).duplicate(true)
	for cid in class_order:
		var row: Dictionary = classes_by_id[cid]
		for k in ["name", "name_en", "hull_code", "hull_code_prefix"]:
			if str(row.get(k, "")) == query:
				return row.duplicate(true)
	return {}

func ships(faction := "") -> Array:
	var out: Array = []
	for sid in known_order:
		var row: Dictionary = (known_by_ship[sid] as Dictionary).duplicate(true)
		if faction != "" and str(row.get("faction", "")) != String(faction):
			continue
		out.append(row)
	return out

func name_pool(target: String) -> Array:
	if classes_by_id.has(target):
		return (classes_by_id[target] as Dictionary).get("name_pool", []).duplicate()
	if friendly.get("name_pools") is Dictionary and (friendly.get("name_pools") as Dictionary).has(target):
		return _pool_array(friendly["name_pools"][target])
	if enemy.get("name_pools") is Dictionary and (enemy.get("name_pools") as Dictionary).has(target):
		return _pool_array(enemy["name_pools"][target])
	var sh2 := _find_known(target)
	if not sh2.is_empty():
		return (classes_by_id.get(str(sh2.get("class_id", "")), {}) as Dictionary) \
			.get("name_pool", []).duplicate()
	return []

func _pool_array(v: Variant) -> Array:
	if v is Array:
		return (v as Array).duplicate()
	if v is Dictionary:
		var out: Array = []
		for k in (v as Dictionary).keys():
			out.append(str(k))
		out.sort()
		return out
	return []

func resolve(query: String) -> Dictionary:
	if query == "":
		return {"ok": false, "reason": "empty_query"}
	if classes_by_id.has(query):
		return {"ok": true, "kind": "class", "class": classes_by_id[query].duplicate(true),
			"class_id": query}
	var sh := _find_known(query)
	if not sh.is_empty():
		return {"ok": true, "kind": "ship", "ship": sh.duplicate(true),
			"class": (classes_by_id.get(str(sh.get("class_id", "")), {}) as Dictionary).duplicate(true),
			"class_id": str(sh.get("class_id", ""))}
	for cid in class_order:
		var row: Dictionary = classes_by_id[cid]
		for k in ["hull_code", "hull_code_prefix", "name", "name_en"]:
			if str(row.get(k, "")) == query:
				return {"ok": true, "kind": "class_" + str(k),
					"class": row.duplicate(true), "class_id": cid}
	for eid in entity_bindings.keys():
		if str(eid) == query:
			return _binding_result(str(eid))
	return {"ok": false, "reason": "not_found", "query": query}

func known_ship(query: String) -> Dictionary:
	var sh := _find_known(query)
	return sh.duplicate(true) if not sh.is_empty() else {}

func by_batch(batch: String) -> Dictionary:
	if batch == "":
		return {}
	for sid in known_order:
		var row: Dictionary = known_by_ship[sid]
		if str(row.get("batch", "")) == batch:
			return row.duplicate(true)
	return {}

func entity_binding(entity_id: String) -> Dictionary:
	if entity_id == "" or not entity_bindings.has(entity_id):
		return {}
	return _binding_result(entity_id)

func _binding_result(entity_id: String) -> Dictionary:
	var sid := str(entity_bindings.get(entity_id, ""))
	var sh := _find_known(sid)
	var out := {"ok": not sh.is_empty(), "entity_id": entity_id, "ship_id": sid,
		"ship": sh.duplicate(true)}
	if not sh.is_empty():
		out["class_id"] = str(sh.get("class_id", ""))
		out["class"] = (classes_by_id.get(str(sh.get("class_id", "")), {}) as Dictionary).duplicate(true)
	if sh.is_empty():
		out["reason"] = "unknown_binding"
	return out

func _find_known(query: String) -> Dictionary:
	if query == "":
		return {}
	if known_by_ship.has(query):
		return (known_by_ship[query] as Dictionary).duplicate(true)
	for sid in known_order:
		var row: Dictionary = known_by_ship[sid]
		for k in ["hull_code", "name", "name_en", "batch"]:
			if str(row.get(k, "")) == query:
				return row.duplicate(true)
	return {}

func summary() -> Dictionary:
	var fac_counts: Dictionary = {}
	var variant_counts: Dictionary = {}
	var tbd_count := 0
	var roles: Dictionary = {}
	for cid in class_order:
		var row: Dictionary = classes_by_id[cid]
		var fac := str(row.get("faction", ""))
		fac_counts[fac] = int(fac_counts.get(fac, 0)) + 1
		var vo := str(row.get("variant_of", ""))
		if vo != "":
			variant_counts[vo] = int(variant_counts.get(vo, 0)) + 1
		roles[str(row.get("role", ""))] = true
		if row.get("tbd") is Array:
			tbd_count += (row.get("tbd") as Array).size()
	var base_33: Array = []
	for cid2 in class_order:
		var r2: Dictionary = classes_by_id[cid2]
		if str(r2.get("faction", "")) == "33osid" and str(r2.get("variant_of", "")) == "":
			base_33.append(cid2)
	base_33.sort()
	return {"schema": SCHEMA, "ready": ready,
		"classes": class_order.size(), "friendly_classes": classes(FRIENDLY_FACTION).size(),
		"enemy_classes": class_order.size() - classes(FRIENDLY_FACTION).size(),
		"factions": fac_counts, "base_33osid": base_33,
		"variants_33osid": variant_counts,
		"orbflt_classes": classes("uegaf_orbflt").size(),
		"ueof_7th_classes": classes("ueof_7th").size(),
		"ueof_3rd_classes": classes("ueof_3rd").size(),
		"known_ships": known_by_ship.size(), "friendly_ships": ships(FRIENDLY_FACTION).size(),
		"enemy_ships": known_by_ship.size() - ships(FRIENDLY_FACTION).size(),
		"name_pools": (friendly.get("name_pools", {}) as Dictionary).size()
			+ (enemy.get("name_pools", {}) as Dictionary).size(),
		"roles": roles.keys(), "tbd_fields": tbd_count,
		"proposal": true, "truth": false,
		"writes": {"ui": false, "combat": false, "world": false, "v15": false}}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "ready": ready,
		"friendly": friendly.duplicate(true), "enemy": enemy.duplicate(true),
		"summary": summary()}

func to_json() -> String:
	return JSON.stringify(to_dict())

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("ShipCatalog 未 ready")
	var fcount := classes(FRIENDLY_FACTION).size()
	if fcount != 8:
		v.append("友军必须 8 型，实际 " + str(fcount))
	var e33: int = classes("33osid").size()
	if e33 < 18:
		v.append("33OSID 至少 18 条（6 base + 12 variants），实际 " + str(e33))
	if classes("uegaf_orbflt").size() < 4:
		v.append("ORBFLT 至少 4 级")
	if classes("ueof_7th").size() < 2 or classes("ueof_3rd").size() < 2:
		v.append("UEOF 7th/3rd 各至少 2 级")
	for cid in class_order:
		var row: Dictionary = classes_by_id[cid]
		if bool(row.get("proposal", false)) != true:
			v.append("proposal 必须 true：" + cid)
		if not row.has("name_pool") or (row.get("name_pool") as Array).is_empty():
			v.append("name_pool 不能为空：" + cid)
	if entity_binding("apsis").is_empty():
		v.append("APSIS entity_binding 缺失")
	if known_ship("AV-4412").is_empty():
		v.append("AV-4412 known_ship 缺失")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	return {"ok": false, "reason": reason_text, "errors": [msg]}
