class_name V2DamageProfileService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5C · 按舰级毁伤物理档案服务
#
# 内容：framework/content/damage_profiles.json（36 型：32 基础舰级 + 4 UEOF 变体原型，ShipCatalog class_id/变体 archetype）
# 职责：load/validate/profile_for(class_id 或 entity)/sections/armor/effects/
#       summary；未知 class 回退 default，不伪造舰级。
# 只读；不写 world/TrackTable/UI；不改旧 damage_l1.ships 显式覆盖。
# ═══════════════════════════════════════════════════════════════════

const ShipCatalog := preload("res://scripts/core/ship_catalog.gd")
const DEFAULT_PATH := "res://framework/content/damage_profiles.json"
const SCHEMA := "damage_profiles.v1"
const VERSION := "1.0.0"
const SECTION_IDS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]
const MATERIALS := ["steel", "composite", "ceramic", "whipple"]

var ready := false
var errors: Array = []
var warnings: Array = []
var content: Dictionary = {}
var content_path := DEFAULT_PATH
var classes: Dictionary = {}
var class_ids: Array = []
var default_class_id := ""
var materials: Dictionary = {}
var catalog = null
var catalog_enabled := true


func _init(cfg := {}) -> void:
	setup(cfg)


func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	content = {}
	classes = {}
	class_ids = []
	default_class_id = ""
	materials = {}
	content_path = DEFAULT_PATH
	catalog_enabled = true
	if cfg is Dictionary:
		var c: Dictionary = cfg
		content_path = String(c.get("content_path", DEFAULT_PATH))
		catalog_enabled = bool(c.get("catalog_enabled", true))
		if c.get("content") is Dictionary and not (c.get("content") as Dictionary).is_empty():
			content = (c.get("content") as Dictionary).duplicate(true)
		if c.get("catalog") != null:
			catalog = c.get("catalog")
	if content.is_empty():
		if not FileAccess.file_exists(content_path):
			errors.append("damage profiles 不存在: " + content_path)
			return false
		var f := FileAccess.open(content_path, FileAccess.READ)
		if f == null:
			errors.append("damage profiles 不可读: " + content_path)
			return false
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			errors.append("damage profiles JSON 无效: " + content_path)
			return false
		content = parsed
	var v := validate(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("profiles: " + String(e))
		return false
	classes = (content.get("classes", {}) as Dictionary).duplicate(true) if content.get("classes") is Dictionary else {}
	var expected := 36
	if cfg is Dictionary and (cfg as Dictionary).has("expected_classes"):
		expected = int((cfg as Dictionary).get("expected_classes", 36))
	if expected > 0 and classes.size() != expected:
		errors.append("profiles: class 数量 %d，预期 %d" % [classes.size(), expected])
		return false
	class_ids = classes.keys()
	class_ids.sort()
	default_class_id = String(content.get("default_class_id", ""))
	if default_class_id == "" or not classes.has(default_class_id):
		default_class_id = String(class_ids[0]) if not class_ids.is_empty() else ""
	materials = (content.get("materials", {}) as Dictionary).duplicate(true) if content.get("materials") is Dictionary else {}
	if catalog_enabled and catalog == null:
		catalog = ShipCatalog.new()
		if not bool(catalog.ready):
			warnings.append("ShipCatalog 未就绪，entity→class 映射退化为 class_id 精确匹配")
			catalog = null
	ready = true
	return true


# ── validate ────────────────────────────────────────────────

func validate(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["content 必须对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != SCHEMA:
		errs.append("schema 必须 " + SCHEMA)
	if String(d.get("version", "")) != VERSION:
		errs.append("version 必须 " + VERSION)
	var cls = d.get("classes", null)
	if not (cls is Dictionary) or (cls as Dictionary).is_empty():
		errs.append("classes 必须非空对象")
		return {"ok": false, "errors": errs}
	var mats: Dictionary = d.get("materials", {}) if d.get("materials") is Dictionary else {}
	for raw_mat in mats.keys():
		if not (String(raw_mat) in MATERIALS):
			errs.append("未知 material: " + String(raw_mat))
	var ids: Dictionary = {}
	for cid in (cls as Dictionary).keys():
		var c = (cls as Dictionary)[cid]
		if not (c is Dictionary):
			errs.append("class %s 非对象" % String(cid))
			continue
		var p: Dictionary = c
		var id := String(p.get("class_id", ""))
		if id != String(cid):
			errs.append("class key/id 不一致: %s/%s" % [String(cid), id])
		if ids.has(id):
			errs.append("class_id 重复: " + id)
		ids[id] = true
		if String(p.get("name", "")) == "":
			errs.append("class %s 缺 name" % id)
		var sections = p.get("sections", null)
		if not (sections is Array) or (sections as Array).is_empty():
			errs.append("class %s sections 必须非空" % id)
			continue
		var sec_ids: Dictionary = {}
		var mass_sum := 0.0
		for raw_s in (sections as Array):
			if not (raw_s is Dictionary):
				errs.append("class %s section 非对象" % id)
				continue
			var s: Dictionary = raw_s
			var sid := String(s.get("id", ""))
			if not (sid in SECTION_IDS):
				errs.append("class %s 未知 section: %s" % [id, sid])
			if sec_ids.has(sid):
				errs.append("class %s section 重复: %s" % [id, sid])
			sec_ids[sid] = true
			for k in ["label", "kind", "material"]:
				if String(s.get(k, "")) == "":
					errs.append("class %s section %s 缺 %s" % [id, sid, k])
			if not (String(s.get("material", "")) in MATERIALS):
				errs.append("class %s section %s material 非法" % [id, sid])
			for k2 in ["integrity", "mass_fraction", "armor_kinetic", "armor_energy",
					"fire_risk", "vacuum_risk", "repair_s"]:
				if not s.has(k2) or not is_finite(float(s.get(k2, NAN))):
					errs.append("class %s section %s 字段 %s 非法" % [id, sid, k2])
			mass_sum += float(s.get("mass_fraction", 0.0))
			var cs = s.get("critical_systems", null)
			if not (cs is Array) or (cs as Array).is_empty():
				errs.append("class %s section %s critical_systems 必须非空" % [id, sid])
			var adj = s.get("adjacent", null)
			if not (adj is Array):
				errs.append("class %s section %s adjacent 必须数组" % [id, sid])
		if absf(mass_sum - 1.0) > 0.05:
			errs.append("class %s mass_fraction 总和 %.3f != 1" % [id, mass_sum])
		if not p.get("effects") is Dictionary:
			errs.append("class %s 缺 effects 对象" % id)
	var def := String(d.get("default_class_id", ""))
	if def != "" and not (cls as Dictionary).has(def):
		errs.append("default_class_id 不在 classes: " + def)
	return {"ok": errs.is_empty(), "errors": errs}


# ── query ───────────────────────────────────────────────────

func profile_for(query: String) -> Dictionary:
	if query == "":
		return _fallback("")
	if classes.has(query):
		var p: Dictionary = (classes[query] as Dictionary).duplicate(true)
		p["fallback"] = false
		p["requested"] = query
		return p
	# entity / ship / hull → class via ShipCatalog（只读）
	if catalog != null and bool(catalog.ready):
		var cid2 := _resolve_catalog_class(query)
		if cid2 != "" and classes.has(cid2):
			var p2: Dictionary = (classes[cid2] as Dictionary).duplicate(true)
			p2["fallback"] = false
			p2["requested"] = query
			p2["resolved_class_id"] = cid2
			return p2
	return _fallback(query)


func _resolve_catalog_class(query: String) -> String:
	if catalog == null:
		return ""
	var cls: Dictionary = catalog.class_of(query)
	if not cls.is_empty():
		return String(cls.get("class_id", ""))
	# known ship / entity 大小写/别名匹配
	var q := query.to_lower()
	for row in (catalog.ships() as Array):
		if not (row is Dictionary):
			continue
		var r: Dictionary = row
		# 字段可能是数字（batch/hull_code），不能用 String(int)；用 str() 统一安全转换。
		var fields := [str(r.get("entity_id", "")), str(r.get("ship_id", "")),
			str(r.get("batch", "")), str(r.get("hull", "")), str(r.get("hull_code", "")),
			str(r.get("name", "")), str(r.get("name_en", ""))]
		for f in fields:
			if f != "" and f.to_lower() == q:
				var cid := String(r.get("class_id", ""))
				if cid == "":
					var c2: Dictionary = catalog.class_of(String(r.get("ship_id", "")))
					cid = String(c2.get("class_id", ""))
				if cid != "":
					return cid
	return ""


func profile_for_entity(entity_id: String) -> Dictionary:
	return profile_for(entity_id)


func _fallback(query: String) -> Dictionary:
	if default_class_id == "" or not classes.has(default_class_id):
		return {}
	var p: Dictionary = (classes[default_class_id] as Dictionary).duplicate(true)
	p["fallback"] = true
	p["requested"] = query
	p["reason"] = "unknown_class"
	return p


func headers() -> Array:
	return class_ids.duplicate()


func has_class(class_id: String) -> bool:
	return classes.has(class_id)


func sections(query: String) -> Array:
	var p := profile_for(query)
	return (p.get("sections", []) as Array).duplicate(true) if p.get("sections") is Array else []


func section(query: String, section_id: String) -> Dictionary:
	for raw in sections(query):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == section_id:
			return (raw as Dictionary).duplicate(true)
	return {}


func armor(query: String) -> Dictionary:
	var p := profile_for(query)
	var fx: Dictionary = p.get("effects", {}) if p.get("effects") is Dictionary else {}
	var a: Dictionary = fx.get("armor", {}) if fx.get("armor") is Dictionary else {}
	if not a.is_empty():
		return a.duplicate(true)
	# 无 effects.armor 时由分区平均
	var secs: Array = p.get("sections", []) if p.get("sections") is Array else []
	var k := 0.0
	var e := 0.0
	for raw in secs:
		if raw is Dictionary:
			k += float((raw as Dictionary).get("armor_kinetic", 0.0))
			e += float((raw as Dictionary).get("armor_energy", 0.0))
	if secs.is_empty():
		return {"kinetic_resist": 0.0, "energy_resist": 0.0}
	return {"kinetic_resist": k / float(secs.size()),
		"energy_resist": e / float(secs.size())}


func effects(query: String) -> Dictionary:
	var p := profile_for(query)
	return (p.get("effects", {}) as Dictionary).duplicate(true) if p.get("effects") is Dictionary else {}


func material(query: String, section_id: String) -> String:
	var s := section(query, section_id)
	return String(s.get("material", ""))


func hull_class(query: String) -> String:
	var p := profile_for(query)
	return String(p.get("hull_class", ""))


func summary() -> Dictionary:
	var by_hull: Dictionary = {}
	var by_material: Dictionary = {}
	var section_counts: Dictionary = {}
	for cid in class_ids:
		var p: Dictionary = classes[cid]
		var h := String(p.get("hull_class", ""))
		by_hull[h] = int(by_hull.get(h, 0)) + 1
		for raw in (p.get("sections", []) as Array):
			if raw is Dictionary:
				var m := String((raw as Dictionary).get("material", ""))
				by_material[m] = int(by_material.get(m, 0)) + 1
				var sid := String((raw as Dictionary).get("id", ""))
				section_counts[sid] = int(section_counts.get(sid, 0)) + 1
	return {"schema": SCHEMA, "ready": ready, "classes": class_ids.size(),
		"default_class_id": default_class_id, "by_hull": by_hull,
		"by_material": by_material, "section_counts": section_counts,
		"materials": materials.keys(),
		"writes": {"world": false, "track_table": false, "ui": false}}


func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "classes": classes.duplicate(true),
		"default_class_id": default_class_id, "materials": materials.duplicate(true),
		"summary": summary()}


func to_json() -> String:
	return JSON.stringify(to_dict())
