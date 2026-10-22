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
var variants_by_id: Dictionary = {}
var variant_order: Array = []
var variants_by_base: Dictionary = {}
var variants_by_operator: Dictionary = {}

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
	variants_by_id = {}
	variant_order = []
	variants_by_base = {}
	variants_by_operator = {}
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
	variants_by_id = {}
	variant_order = []
	variants_by_base = {}
	variants_by_operator = {}
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
		# 5E：展开 fleet_variants / operator_variants（不占独立 class）
		for group in ["fleet_variants", "operator_variants"]:
			if not (row.get(group) is Array):
				continue
			for vraw in (row.get(group) as Array):
				if not (vraw is Dictionary):
					continue
				var var_rec: Dictionary = _derive_variant(row, vraw, group)
				var vid := str(var_rec.get("variant_id", ""))
				if vid == "":
					continue
				variants_by_id[vid] = var_rec
				variant_order.append(vid)
				var bkey := str(var_rec.get("derive_from", cid))
				if not variants_by_base.has(bkey):
					variants_by_base[bkey] = []
				(variants_by_base[bkey] as Array).append(vid)
				var okey := str(var_rec.get("operator", ""))
				if okey != "":
					if not variants_by_operator.has(okey):
						variants_by_operator[okey] = []
					(variants_by_operator[okey] as Array).append(vid)
	var eb: Dictionary = data.get("entity_bindings", {}) if data.get("entity_bindings") is Dictionary else {}
	for ek in eb.keys():
		entity_bindings[str(ek)] = str(eb[ek])
	class_order.sort()
	known_order.sort()
	variant_order.sort()
	for bk in variants_by_base.keys():
		(variants_by_base[bk] as Array).sort()
	for ok2 in variants_by_operator.keys():
		(variants_by_operator[ok2] as Array).sort()

## 由 base + modifiers 自动推算 variant 数据（proposal；不写回 base）。
func _derive_variant(base: Dictionary, vraw: Dictionary, group: String) -> Dictionary:
	var v: Dictionary = vraw.duplicate(true)
	var base_id := str(v.get("derive_from", base.get("class_id", "")))
	var out: Dictionary = base.duplicate(true)
	for k in ["class_id", "name", "name_en", "role", "faction", "hull_code",
			"hull_code_prefix", "known_ships", "name_pool", "fleet_variants",
			"operator_variants", "displacement_t", "dv_kmps", "accel_g", "crew",
			"sensors", "weapons", "armor", "signature", "dimensions_m", "tbd",
			"derived_stats", "naming_scheme", "content_file"]:
		out.erase(k)
	for k2 in v.keys():
		out[k2] = v[k2]
	out["kind"] = "variant"
	out["class_id"] = base_id
	out["variant_of"] = base_id
	out["derive_from"] = base_id
	out["variant_group"] = group
	out["operator"] = str(v.get("operator", base.get("faction", "")))
	out["faction"] = str(v.get("faction", v.get("operator", base.get("faction", ""))))
	out["base_class_id"] = base_id
	out["base_name"] = str(base.get("name", ""))
	out["hull_code"] = "%s-%s" % [str(base.get("hull_code", "")),
		str(v.get("hull_suffix", str(v.get("variant_id", "VAR"))))]
	out["sections"] = (base.get("sections", []) as Array).duplicate()
	out["name_pool"] = (v.get("name_pool", base.get("name_pool", [])) as Array).duplicate()
	out["known_ships"] = (v.get("known_ships", []) as Array).duplicate()
	out["proposal"] = true
	out["truth"] = false
	out["derived"] = true
	out["derived_from"] = base_id
	out["derivation"] = {"source": "base+modifiers", "modifiers": v.get("modifiers", {}).duplicate(true)}
	out["tbd"] = []
	out["source"] = str(v.get("source", base.get("source", "")))
	var mod: Dictionary = v.get("modifiers", {}) if v.get("modifiers") is Dictionary else {}
	# 数值推算
	for pair in [["displacement_t", "mass_factor", "displacement_factor"],
			["dv_kmps", "dv_factor", "dv_mult"],
			["accel_g", "accel_factor", "accel_mult"],
			["crew", "crew_factor", "crew_mult"]]:
		var field := str(pair[0])
		var key1 := str(pair[1])
		var key2 := str(pair[2])
		var base_v = base.get(field, null)
		var factor := 1.0
		if mod.has(key1):
			factor = float(mod.get(key1, 1.0))
		elif mod.has(key2):
			factor = float(mod.get(key2, 1.0))
		if base_v is int or base_v is float:
			var val := float(base_v) * factor
			if field == "crew":
				out[field] = int(round(val))
			else:
				out[field] = snappedf(val, 0.001)
	# 传感器/武器 = base + *_add
	for pair2 in [["sensors", "sensors_add"], ["weapons", "weapons_add"]]:
		var f2 := str(pair2[0])
		var arr: Array = (base.get(f2, []) as Array).duplicate()
		if mod.get(pair2[1]) is Array:
			for x in (mod.get(pair2[1]) as Array):
				if not str(x) in arr:
					arr.append(str(x))
		out[f2] = arr
	out["armor"] = str(v.get("armor", base.get("armor", "")))
	out["signature"] = (base.get("signature", {}) as Dictionary).duplicate(true) if base.get("signature") is Dictionary else {}
	out["dimensions_m"] = (base.get("dimensions_m", []) as Array).duplicate()
	out["effects"] = {}
	out["stats_derived"] = {"displacement_t": out.get("displacement_t"),
		"dv_kmps": out.get("dv_kmps"), "accel_g": out.get("accel_g"),
		"crew": out.get("crew")}
	return out

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
		var bases_33: Array = []
		var bases_orb: Array = []
		var variants_33: Dictionary = {}
		for raw2 in (d.get("classes", []) as Array):
			if not (raw2 is Dictionary):
				continue
			var r2: Dictionary = raw2
			var fac2 := str(r2.get("faction", ""))
			by_fac[fac2] = int(by_fac.get(fac2, 0)) + 1
			if fac2 == "ueof_7th" or fac2 == "ueof_3rd":
				errs.append("UEOF 不应拥有独立舰级（共用 ORBFLT base）：" + str(r2.get("class_id", "")))
			var vo := str(r2.get("variant_of", ""))
			if fac2 == "33osid":
				if vo == "":
					bases_33.append(str(r2.get("class_id", "")))
				else:
					variants_33[vo] = int(variants_33.get(vo, 0)) + 1
			if fac2 == "uegaf_orbflt":
				if vo != "":
					errs.append("ORBFLT base 不应以 variant_of 独立成类：" + str(r2.get("class_id", "")))
					continue
				bases_orb.append(str(r2.get("class_id", "")))
				for nf in NUMERIC_FIELDS:
					if not (r2.get(nf) is int or r2.get(nf) is float):
						errs.append("ORBFLT base 数值必须自动可用（不可 TBD）：%s.%s" % [str(r2.get("class_id", "")), str(nf)])
				_validate_variant_group(r2, "operator_variants", 2, 3, errs)
				_validate_variant_group(r2, "fleet_variants", 1, 4, errs)
		if int(by_fac.get("33osid", 0)) < 6:
			errs.append("33OSID 至少 6 级")
		if bases_33.size() != 6:
			errs.append("33OSID 必须 6 个 base，实际 " + str(bases_33.size()))
		for b in bases_33:
			var n := int(variants_33.get(b, 0))
			if n < 2 or n > 4:
				errs.append("33OSID " + str(b) + " 亚种数量必须 2..4，实际 " + str(n))
		if bases_orb.size() != 6:
			errs.append("ORBFLT 必须 6 个 base，实际 " + str(bases_orb.size()))
		for b2 in bases_orb:
			var base_row: Dictionary = {}
			for raw3 in (d.get("classes", []) as Array):
				if raw3 is Dictionary and str((raw3 as Dictionary).get("class_id", "")) == b2:
					base_row = raw3
					break
			var opv: Array = (base_row.get("operator_variants", []) as Array)
			var seen_ops: Dictionary = {}
			for ov in opv:
				if ov is Dictionary:
					seen_ops[str((ov as Dictionary).get("operator", ""))] = true
			if not bool(seen_ops.get("ueof_7th", false)) or not bool(seen_ops.get("ueof_3rd", false)):
				errs.append("ORBFLT " + b2 + " operator_variants 必须覆盖 ueof_7th/ueof_3rd")
			if not (base_row.get("fleet_variants") is Array) or (base_row.get("fleet_variants") as Array).is_empty():
				errs.append("ORBFLT " + b2 + " 缺 fleet_variants")
		# CA-4471 batch 语义
		for raw4 in (d.get("classes", []) as Array):
			if not (raw4 is Dictionary):
				continue
			var cr: Dictionary = raw4
			for sh4 in (cr.get("known_ships", []) as Array):
				if sh4 is Dictionary and str((sh4 as Dictionary).get("ship_id", "")) == "CA-4471":
					if (sh4 as Dictionary).get("batch", "x") != null:
						errs.append("CA-4471 batch 必须为 null/unassigned")
					if str((sh4 as Dictionary).get("batch_source", "")) == "":
						errs.append("CA-4471 缺 batch_source")
		if d.get("audit") is not Dictionary:
			errs.append("缺 33OSID audit 元数据")
	return {"ok": errs.is_empty(), "errors": errs}

## 校验 base 上的变体组：数量/字段/唯一 variant_id/derive_from/operator。
func _validate_variant_group(base: Dictionary, group: String, min_n: int, max_n: int,
		errs: Array) -> void:
	var base_id := str(base.get("class_id", ""))
	if not (base.get(group) is Array):
		errs.append("缺 " + group + "：" + base_id)
		return
	var arr: Array = base.get(group) as Array
	if arr.size() < min_n or arr.size() > max_n:
		errs.append("%s.%s 数量必须 %d..%d，实际 %d" % [base_id, group, min_n, max_n, arr.size()])
	for v in arr:
		if not (v is Dictionary):
			errs.append(base_id + "." + group + " 行必须是对象")
			continue
		var vr: Dictionary = v
		for f in ["variant_id", "name", "role", "refit", "derive_from", "modifiers"]:
			if not vr.has(f) or (str(vr.get(f, "")) == "" and f != "modifiers"):
				errs.append(base_id + "." + group + " 缺字段 " + str(f))
		if str(vr.get("derive_from", "")) != base_id:
			errs.append(base_id + "." + group + " derive_from 必须指向 base")
		if not bool(vr.get("proposal", false)):
			errs.append(base_id + "." + group + " proposal 必须 true")
		if not (vr.get("modifiers") is Dictionary):
			errs.append(base_id + "." + group + " modifiers 必须是对象")

func _check_uniqueness() -> Dictionary:
	return _check_uniqueness_static(friendly, enemy)

func _check_uniqueness_static(f: Dictionary, e: Dictionary) -> Dictionary:
	var errs: Array = []
	var cids: Dictionary = {}
	var names: Dictionary = {}
	var ship_ids: Dictionary = {}
	var variant_ids: Dictionary = {}
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
			# 5E：变体唯一性
			for group in ["fleet_variants", "operator_variants"]:
				if not (row.get(group) is Array):
					continue
				for vraw in (row.get(group) as Array):
					if not (vraw is Dictionary):
						continue
					var vv: Dictionary = vraw
					var vid := str(vv.get("variant_id", ""))
					if vid == "":
						continue
					if variant_ids.has(vid):
						errs.append("variant_id 重复：" + vid)
					variant_ids[vid] = true
					var vnm := str(vv.get("name", ""))
					if vnm != "":
						if names.has(vnm):
							errs.append("variant name 重复：" + vnm)
						names[vnm] = true
					var vhull := "%s-%s" % [str(row.get("hull_code", "")),
						str(vv.get("hull_suffix", "VAR"))]
					if hulls.has(vhull):
						errs.append("variant hull 重复：" + vhull)
					hulls[vhull] = true
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
	var var_hit: Dictionary = _find_variant(query)
	if not var_hit.is_empty():
		return (classes_by_id.get(str(var_hit.get("derive_from", "")), {}) as Dictionary).duplicate(true)
	var sh := _find_known(query)
	if not sh.is_empty():
		return (classes_by_id.get(str(sh.get("class_id", "")), {}) as Dictionary).duplicate(true)
	for cid in class_order:
		var row: Dictionary = classes_by_id[cid]
		for k in ["name", "name_en", "hull_code", "hull_code_prefix"]:
			if str(row.get(k, "")) == query:
				return row.duplicate(true)
	return {}

## 5E：共用舰级下的亚种展开。query 可为 base class_id / operator / faction；
## 空串返回全部变体。
func variants_of(query := "") -> Array:
	var out: Array = []
	if query == "":
		for vid in variant_order:
			out.append((variants_by_id[vid] as Dictionary).duplicate(true))
		return out
	var q := str(query)
	var ids: Array = []
	if variants_by_base.has(q):
		ids = (variants_by_base[q] as Array).duplicate()
	elif variants_by_operator.has(q):
		ids = (variants_by_operator[q] as Array).duplicate()
	elif variants_by_id.has(q):
		ids = [q]
	for vid2 in ids:
		if variants_by_id.has(str(vid2)):
			out.append((variants_by_id[str(vid2)] as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str(a.get("variant_id", "")) < str(b.get("variant_id", "")))
	return out

func _find_variant(query: String) -> Dictionary:
	if query == "":
		return {}
	if variants_by_id.has(query):
		return (variants_by_id[query] as Dictionary).duplicate(true)
	for vid in variant_order:
		var row: Dictionary = variants_by_id[vid]
		for k in ["name", "name_en", "hull_code"]:
			if str(row.get(k, "")) == query:
				return row.duplicate(true)
	return {}

func resolve_variant(query: String) -> Dictionary:
	var v: Dictionary = _find_variant(query)
	if v.is_empty():
		return {"ok": false, "reason": "unknown_variant", "query": query}
	return {"ok": true, "kind": "variant", "variant": v,
		"variant_id": str(v.get("variant_id", "")),
		"base_class_id": str(v.get("derive_from", "")),
		"operator": str(v.get("operator", ""))}

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
	var var_hit: Dictionary = _find_variant(query)
	if not var_hit.is_empty():
		return {"ok": true, "kind": "variant", "variant": var_hit.duplicate(true),
			"variant_id": str(var_hit.get("variant_id", "")),
			"base_class_id": str(var_hit.get("derive_from", "")),
			"operator": str(var_hit.get("operator", ""))}
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
	var base_orbflt: Array = []
	for cid3 in class_order:
		var r3: Dictionary = classes_by_id[cid3]
		if str(r3.get("faction", "")) == "uegaf_orbflt":
			base_orbflt.append(cid3)
	base_orbflt.sort()
	var op_counts: Dictionary = {}
	var fleet_count := 0
	for vid in variant_order:
		var vr: Dictionary = variants_by_id[vid]
		var op := str(vr.get("operator", ""))
		op_counts[op] = int(op_counts.get(op, 0)) + 1
		if str(vr.get("variant_group", "")) == "fleet_variants":
			fleet_count += 1
	return {"schema": SCHEMA, "ready": ready,
		"classes": class_order.size(), "friendly_classes": classes(FRIENDLY_FACTION).size(),
		"enemy_classes": class_order.size() - classes(FRIENDLY_FACTION).size(),
		"factions": fac_counts, "base_33osid": base_33,
		"variants_33osid": variant_counts,
		"variants": variant_order.size(), "variant_classes": variant_order.size(),
		"operator_variants": op_counts, "fleet_variants": fleet_count,
		"base_orbflt": base_orbflt,
		"orbflt_classes": classes("uegaf_orbflt").size(),
		"ueof_7th_classes": classes("ueof_7th").size(),
		"ueof_3rd_classes": classes("ueof_3rd").size(),
		"ueof_7th_variants": (variants_by_operator.get("ueof_7th", []) as Array).size(),
		"ueof_3rd_variants": (variants_by_operator.get("ueof_3rd", []) as Array).size(),
		"known_ships": known_by_ship.size(), "friendly_ships": ships(FRIENDLY_FACTION).size(),
		"enemy_ships": known_by_ship.size() - ships(FRIENDLY_FACTION).size(),
		"name_pools": (friendly.get("name_pools", {}) as Dictionary).size()
			+ (enemy.get("name_pools", {}) as Dictionary).size(),
		"auto_derived_variants": variant_order.size(),
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
	if e33 != 18:
		v.append("33OSID 应为 18 条（6 base + 12 variants），实际 " + str(e33))
	var orb_n: int = classes("uegaf_orbflt").size()
	if orb_n != 6:
		v.append("ORBFLT 应为 6 个基础级，实际 " + str(orb_n))
	if classes("ueof_7th").size() != 0 or classes("ueof_3rd").size() != 0:
		v.append("UEOF 不应拥有独立舰级（应共用 ORBFLT base）")
	if (variants_by_operator.get("ueof_7th", []) as Array).size() != 6:
		v.append("UEOF 7th 变体应为 6（每 base 1）")
	if (variants_by_operator.get("ueof_3rd", []) as Array).size() != 6:
		v.append("UEOF 3rd 变体应为 6（每 base 1）")
	for oid in variants_by_operator.keys():
		if str(oid) not in ["uegaf_orbflt", "ueof_7th", "ueof_3rd"]:
			v.append("未知变体 operator：" + str(oid))
	for vid in variant_order:
		var vr: Dictionary = variants_by_id[vid]
		if not bool(vr.get("proposal", false)):
			v.append("variant proposal 必须 true：" + vid)
		if str(vr.get("derive_from", "")) == "":
			v.append("variant 缺 derive_from：" + vid)
		for nf in NUMERIC_FIELDS:
			if not (vr.get(nf) is int or vr.get(nf) is float):
				v.append("variant 数值未自动推算：" + vid + "." + str(nf))
	var ca := known_ship("CA-4471")
	if ca.is_empty():
		v.append("CA-4471 缺失")
	elif ca.has("batch") and ca.get("batch") != null:
		v.append("CA-4471 batch 应为 null/unassigned")
	elif str(ca.get("batch_source", "")) == "":
		v.append("CA-4471 缺 batch_source")
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
