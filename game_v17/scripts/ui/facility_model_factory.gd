extends RefCounted

# 方案B-40：空间站四族独立匹配 + 小型模块站。
# 四族：oneill / stanford / asteroid_habitat / asteroid_fortress，互不拼合替代。
# habitat_profiles.json 给出已知站人口/资源/功能/族；未知站按 class 默认 + 阈值匹配。

const StationModel := preload("res://models/station_model.gd")
const OneillScene := preload("res://models/oneill_cylinder.tscn")
const StanfordScene := preload("res://models/stanford_torus.tscn")
const AsteroidHabitatScene := preload("res://models/asteroid_habitat.tscn")
const AsteroidFortressScene := preload("res://models/asteroid_fortress.tscn")

const PROFILE_PATH := "res://framework/content/habitat_profiles.json"
const FALLBACK_MODEL := "port"
const CLASS_TO_MODEL := {
	"station": "port", "port": "port", "depot": "depot",
	"otc": "otc", "tank": "tank", "fuel": "fuel",
	"relay": "otc", "research": "research",
	"commercial": "port", "logistics": "depot", "industrial": "depot",
	"shipyard": "port", "observation": "research", "residential": "port",
	"agricultural": "tank", "water_utility": "tank", "salvage": "depot",
	"food_processing": "tank", "cultural": "port", "tourism": "port",
}
const BASE_SCALE := {"port": 1.15, "depot": 1.05, "otc": 0.82, "tank": 0.72, "fuel": 0.78, "research": 0.92}
const BASE_MODULES := {"port": 4, "depot": 4, "otc": 3, "tank": 3, "fuel": 3, "research": 4}
const SCALE_MIN := 0.55
const SCALE_MAX := 1.65
const MODULES_MIN := 2
const MODULES_MAX := 8
const FAMILIES := ["oneill", "stanford", "asteroid_habitat", "asteroid_fortress", "module_station"]
const HABITAT_CLASSES := ["residential", "tourism", "agricultural"]
const MODULE_CLASSES := ["station", "port", "depot", "otc", "tank", "fuel", "relay", "research", "commercial", "logistics", "industrial", "shipyard", "observation", "salvage", "water_utility", "food_processing", "cultural"]

static var _profiles_cache: Dictionary = {}


static func _profiles() -> Dictionary:
	if not _profiles_cache.is_empty():
		return _profiles_cache
	if FileAccess.file_exists(PROFILE_PATH):
		var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_profiles_cache = parsed
	if _profiles_cache.is_empty():
		_profiles_cache = {"known": {}, "class_defaults": {}, "thresholds": {"oneill_population_min": 200000, "stanford_population_min": 10000}}
	return _profiles_cache


static func _class_of(facility: Dictionary) -> String:
	var cls := String(facility.get("facility_class", "")).to_lower()
	if cls == "":
		cls = String(facility.get("transponder_type", "")).to_lower()
	return cls


static func _radius_km(facility: Dictionary) -> float:
	var phys: Dictionary = facility.get("physical", {}) if facility.get("physical") is Dictionary else {}
	if float(phys.get("radius_km", 0.0)) > 0.0:
		return float(phys.get("radius_km"))
	return float(facility.get("radius_km", 0.0))


static func _is_military(facility: Dictionary, prof: Dictionary) -> bool:
	var fn := String(prof.get("function", "")).to_lower()
	var tt := String(facility.get("transponder_type", "")).to_lower()
	var svc: Array = facility.get("services", []) if facility.get("services", []) is Array else []
	if fn.contains("military") or tt.contains("military"):
		return true
	for s in svc:
		if String(s).to_lower().contains("military"):
			return true
	return false


static func profile_for(facility: Dictionary) -> Dictionary:
	var p := _profiles()
	var known: Dictionary = p.get("known", {}) if p.get("known", {}) is Dictionary else {}
	var defaults: Dictionary = p.get("class_defaults", {}) if p.get("class_defaults", {}) is Dictionary else {}
	var fid := String(facility.get("facility_id", ""))
	if known.has(fid) and known[fid] is Dictionary:
		var row: Dictionary = (known[fid] as Dictionary).duplicate(true)
		row["source"] = "known_profile"
		row["profile_id"] = fid
		return row
	var cls := _class_of(facility)
	if defaults.has(cls) and defaults[cls] is Dictionary:
		var row2: Dictionary = (defaults[cls] as Dictionary).duplicate(true)
		row2["source"] = "class_default"
		row2["profile_id"] = cls
		return row2
	return {"population": 0, "resources": "unknown", "function": cls, "source": "none", "profile_id": ""}


static func match_family(facility: Dictionary) -> Dictionary:
	var p := _profiles()
	var thr: Dictionary = p.get("thresholds", {}) if p.get("thresholds", {}) is Dictionary else {}
	var oneill_min := int(thr.get("oneill_population_min", 200000))
	var stanford_min := int(thr.get("stanford_population_min", 10000))
	var prof := profile_for(facility)
	var cls := _class_of(facility)
	var pop := int(prof.get("population", 0))
	var res := String(prof.get("resources", "unknown")).to_lower()
	var fn := String(prof.get("function", cls))
	if _is_military(facility, prof):
		return {"family": "asteroid_fortress", "reason": "military→fortress", "population": pop, "resources": res, "function": fn, "profile": prof}
	if String(prof.get("source", "")) == "known_profile" and String(prof.get("family", "")) != "":
		var fam := String(prof.get("family", ""))
		if fam in FAMILIES:
			return {"family": fam, "reason": "known_profile:" + String(prof.get("profile_id", "")), "population": pop, "resources": res, "function": fn, "profile": prof}
	if cls in MODULE_CLASSES:
		return {"family": "module_station", "reason": "small_module_class:" + cls, "population": pop, "resources": res, "function": fn, "profile": prof}
	if res == "low" or (pop > 0 and pop < stanford_min):
		return {"family": "asteroid_habitat", "reason": "low_resource/under_%d" % stanford_min, "population": pop, "resources": res, "function": fn, "profile": prof}
	if pop >= oneill_min:
		return {"family": "oneill", "reason": "population>=%d" % oneill_min, "population": pop, "resources": res, "function": fn, "profile": prof}
	if pop >= stanford_min:
		return {"family": "stanford", "reason": "population %d..%d" % [stanford_min, oneill_min - 1], "population": pop, "resources": res, "function": fn, "profile": prof}
	if cls in HABITAT_CLASSES:
		return {"family": "stanford", "reason": "class_default_habitat:" + cls, "population": pop, "resources": res, "function": fn, "profile": prof}
	return {"family": "module_station", "reason": "no_habitat_profile", "population": pop, "resources": res, "function": fn, "profile": prof}


static func mapping_for_class(facility_class: String) -> Dictionary:
	var cls := facility_class.to_lower()
	var model_type := String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL))
	var supported := CLASS_TO_MODEL.has(cls)
	return {"facility_class": cls, "model_type": model_type, "supported": supported,
		"fallback": not supported, "mapping": (cls + "→" + model_type) if supported else (cls + "→fallback/" + model_type)}


static func supports(facility_class: String) -> bool:
	return CLASS_TO_MODEL.has(facility_class.to_lower())


static func _scale_for(cls: String, radius_km: float) -> float:
	var base := float(BASE_SCALE.get(String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL)), 1.0))
	var rf := 1.0
	if radius_km > 0.0:
		rf = clampf(0.82 + log(1.0 + radius_km) * 0.22, 0.82, 1.35)
	return clampf(base * rf, SCALE_MIN, SCALE_MAX)


static func _modules_for(cls: String, radius_km: float) -> int:
	var base := int(BASE_MODULES.get(String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL)), 3))
	return clampi(base + int(minf(3.0, radius_km)), MODULES_MIN, MODULES_MAX)


static func describe(facility: Dictionary) -> Dictionary:
	var cls := _class_of(facility)
	var mapping := mapping_for_class(cls)
	var radius := _radius_km(facility)
	var family_match := match_family(facility)
	var family := String(family_match.get("family", "module_station"))
	var scale := _scale_for(cls, radius)
	var modules := _modules_for(cls, radius)
	return {"facility_id": String(facility.get("facility_id", "")),
		"name": String(facility.get("name", "")), "facility_class": cls,
		"model_family": family, "model_type": String(mapping["model_type"]),
		"family_reason": String(family_match.get("reason", "")),
		"population": int(family_match.get("population", 0)),
		"resources": String(family_match.get("resources", "unknown")),
		"function": String(family_match.get("function", cls)),
		"profile_source": String((family_match.get("profile", {}) as Dictionary).get("source", "none")),
		"profile_id": String((family_match.get("profile", {}) as Dictionary).get("profile_id", "")),
		"supported": bool(mapping["supported"]), "fallback": bool(mapping["fallback"]),
		"mapping": String(mapping["mapping"]), "radius_km": radius,
		"scale": scale, "module_count": modules,
		"material": "StandardMaterial3D solid · procedural · no texture"}


static func _apply_compat(node: Node3D, d: Dictionary) -> void:
	if node == null:
		return
	if node.get("station_type") != null:
		node.set("station_type", String(d.get("model_type", FALLBACK_MODEL)))
	if node.get("station_scale") != null:
		node.set("station_scale", float(d.get("scale", 1.0)))
	if node.get("module_count") != null:
		node.set("module_count", int(d.get("module_count", 3)))
	node.set_meta("facility_model_mapping", d)
	node.set_meta("facility_model_fallback", bool(d.get("fallback", false)))
	node.set_meta("facility_model_supported", bool(d.get("supported", false)))


static func create(facility: Dictionary) -> Node3D:
	var d := describe(facility)
	var family := String(d.get("model_family", "module_station"))
	var node: Node3D = null
	match family:
		"oneill":
			node = OneillScene.instantiate() as Node3D
			if node != null:
				node.set("habitat_label", String(d.get("name", "")))
		"stanford":
			node = StanfordScene.instantiate() as Node3D
			if node != null:
				node.set("habitat_label", String(d.get("name", "")))
		"asteroid_habitat":
			node = AsteroidHabitatScene.instantiate() as Node3D
			if node != null:
				node.set("habitat_label", String(d.get("name", "")))
		"asteroid_fortress":
			node = AsteroidFortressScene.instantiate() as Node3D
			if node != null:
				node.set("fortress_label", String(d.get("name", "")))
		_:
			var st = StationModel.new()
			st.station_type = String(d.get("model_type", FALLBACK_MODEL))
			st.station_label = String(d.get("name", d.get("facility_id", "FACILITY")))
			st.station_scale = float(d.get("scale", 1.0))
			st.module_count = int(d.get("module_count", 3))
			node = st
	if node == null:
		node = StationModel.new()
	_apply_compat(node, d)
	return node


static func summary(facilities: Array) -> Dictionary:
	var by_family: Dictionary = {}
	var by_class: Dictionary = {}
	var fallbacks := 0
	var known := 0
	var total := 0
	var families: Dictionary = {}
	for raw in facilities:
		if not (raw is Dictionary):
			continue
		total += 1
		var d := describe(raw)
		var fam := String(d.get("model_family", "module_station"))
		by_family[fam] = int(by_family.get(fam, 0)) + 1
		var cls := String(d.get("facility_class", ""))
		by_class[cls] = int(by_class.get(cls, 0)) + 1
		if String(d.get("profile_source", "")) == "known_profile":
			known += 1
		if bool(d.get("fallback", false)):
			fallbacks += 1
		families[fam] = true
	return {"total": total, "by_family": by_family, "by_class": by_class,
		"known_profiles": known, "fallbacks": fallbacks, "families": by_family.keys(),
		"writes": {"world": false, "physics": false, "truth": false}}


static func mapping_table() -> Dictionary:
	var out: Dictionary = {}
	for cls in CLASS_TO_MODEL.keys():
		out[String(cls)] = mapping_for_class(String(cls))
	return out
