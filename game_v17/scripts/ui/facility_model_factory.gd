extends RefCounted

# 方案B-35：FacilityModelFactory
# FacilityRegistry/facility dict → station_model 3D 基型；纯读、确定性、无贴图。
# 已知 facility_class 映射到 station_model 的 6 个基型；未知 class 明确 fallback（port）并标注。

const StationModel := preload("res://models/station_model.gd")
const OneillScene := preload("res://models/oneill_cylinder.tscn")
const StanfordScene := preload("res://models/stanford_torus.tscn")

# facility_class -> station_model.station_type（基型）
const CLASS_TO_MODEL := {
	"station": "port", "port": "port", "depot": "depot",
	"otc": "otc", "tank": "tank", "fuel": "fuel",
	"relay": "otc", "research": "research",
	"commercial": "port", "logistics": "depot", "industrial": "depot",
	"shipyard": "port", "observation": "research", "residential": "port",
	"agricultural": "tank", "water_utility": "tank", "salvage": "depot",
	"food_processing": "tank", "cultural": "port", "tourism": "port",
}
const FALLBACK_MODEL := "port"
# 大型居住站映射（docs/44 第51行）：Savannah/Eko/Aurora → O'Neill；Saturnus → Stanford。
const HABITAT_BY_ID := {
	"L5-07": "oneill", "L5-01": "oneill", "L3-01": "oneill",
	"NESOSS-05": "stanford",
}
const HABITAT_BY_NAME := {
	"savannah": "oneill", "eko": "oneill", "aurora": "oneill",
	"saturnus": "stanford",
}
const HABITAT_CLASS_HINTS := ["residential", "tourism", "agricultural", "habitat"]
const HABITAT_RADIUS_MIN_KM := 2.0
const HABITAT_LARGE_RADIUS_KM := 3.2
const BASE_SCALE := {
	"port": 1.15, "depot": 1.05, "otc": 0.82, "tank": 0.72,
	"fuel": 0.78, "research": 0.92,
}
const BASE_MODULES := {
	"port": 4, "depot": 4, "otc": 3, "tank": 3,
	"fuel": 3, "research": 4,
}
const SCALE_MIN := 0.55
const SCALE_MAX := 1.65
const MODULES_MIN := 2
const MODULES_MAX := 8


static func mapping_for_class(facility_class: String) -> Dictionary:
	var cls := facility_class.to_lower()
	var model_type := String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL))
	var supported := CLASS_TO_MODEL.has(cls)
	return {"facility_class": cls, "model_type": model_type,
		"supported": supported, "fallback": not supported,
		"mapping": (cls + "→" + model_type) if supported else (cls + "→fallback/" + model_type)}


static func supports(facility_class: String) -> bool:
	return CLASS_TO_MODEL.has(facility_class.to_lower())


static func habitat_for(facility: Dictionary) -> Dictionary:
	# 已知 lore 映射；未知“大型居住/生态站”按半径 fallback（>=3.2 oneill，否则 stanford），并标注。
	var fid := String(facility.get("facility_id", ""))
	if HABITAT_BY_ID.has(fid):
		var ht := String(HABITAT_BY_ID[fid])
		return {"habitat_type": ht, "known": true, "fallback": false,
			"label": (ht.to_upper() + " · " + String(facility.get("name", fid)))}
	var nm := String(facility.get("name", facility.get("name_en", ""))).to_lower()
	if HABITAT_BY_NAME.has(nm):
		var ht2 := String(HABITAT_BY_NAME[nm])
		return {"habitat_type": ht2, "known": true, "fallback": false,
			"label": (ht2.to_upper() + " · " + String(facility.get("name", nm)))}
	var cls := _class_of(facility)
	var radius := _radius_km(facility)
	if cls in HABITAT_CLASS_HINTS and radius >= HABITAT_RADIUS_MIN_KM:
		var ht3 := "oneill" if radius >= HABITAT_LARGE_RADIUS_KM else "stanford"
		return {"habitat_type": ht3, "known": false, "fallback": true,
			"label": (ht3.to_upper() + " · RADIUS FALLBACK " + ("%.1f km" % radius))}
	return {"habitat_type": "", "known": false, "fallback": false, "label": ""}


static func _class_of(facility: Dictionary) -> String:
	var cls := String(facility.get("facility_class", "")).to_lower()
	if cls == "":
		cls = String(facility.get("transponder_type", "")).to_lower()
	if cls == "":
		cls = String(facility.get("facility_kind", "")).to_lower()
	return cls


static func _radius_km(facility: Dictionary) -> float:
	var phys: Dictionary = facility.get("physical", {}) if facility.get("physical", {}) is Dictionary else {}
	if float(phys.get("radius_km", 0.0)) > 0.0:
		return float(phys.get("radius_km"))
	if float(facility.get("radius_km", 0.0)) > 0.0:
		return float(facility.get("radius_km"))
	return 0.0


static func _scale_for(cls: String, radius_km: float) -> float:
	var base := float(BASE_SCALE.get(String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL)), 1.0))
	var rf := 1.0
	if radius_km > 0.0:
		rf = clampf(0.82 + log(1.0 + radius_km) * 0.22, 0.82, 1.35)
	return clampf(base * rf, SCALE_MIN, SCALE_MAX)


static func _modules_for(cls: String, radius_km: float) -> int:
	var base := int(BASE_MODULES.get(String(CLASS_TO_MODEL.get(cls, FALLBACK_MODEL)), 3))
	var extra := 0
	if radius_km > 0.0:
		extra = int(minf(3.0, radius_km))
	return clampi(base + extra, MODULES_MIN, MODULES_MAX)


static func describe(facility: Dictionary) -> Dictionary:
	var cls := _class_of(facility)
	var mapping := mapping_for_class(cls)
	var radius := _radius_km(facility)
	var scale := _scale_for(cls, radius)
	var modules := _modules_for(cls, radius)
	var hab := habitat_for(facility)
	var is_habitat := String(hab.get("habitat_type", "")) != ""
	var family := "habitat" if is_habitat else "module_station"
	var hab_scale := 1.0
	if is_habitat and bool(hab.get("fallback", false)):
		hab_scale = clampf(radius / 3.0, 0.80, 1.30)
	return {"facility_id": String(facility.get("facility_id", "")),
		"name": String(facility.get("name", "")),
		"facility_class": cls, "model_type": String(mapping["model_type"]),
		"supported": bool(mapping["supported"]), "fallback": bool(mapping["fallback"]),
		"mapping": String(mapping["mapping"]), "radius_km": radius,
		"scale": scale, "module_count": modules,
		"model_family": family, "habitat_type": String(hab.get("habitat_type", "")),
		"habitat_label": String(hab.get("label", "")), "habitat_known": bool(hab.get("known", false)),
		"habitat_fallback": bool(hab.get("fallback", false)), "habitat_scale": hab_scale,
		"material": "StandardMaterial3D solid · procedural · no texture"}


static func create(facility: Dictionary) -> Node3D:
	var d := describe(facility)
	if String(d.get("model_family", "")) == "habitat":
		var scene: PackedScene = OneillScene if String(d.get("habitat_type", "")) == "oneill" else StanfordScene
		var hnode = scene.instantiate()
		if hnode is Node3D:
			hnode.habitat_label = String(d.get("habitat_label", d.get("name", "")))
			hnode.habitat_scale = float(d.get("habitat_scale", 1.0))
			hnode.station_type = String(d.get("model_type", FALLBACK_MODEL))
			hnode.station_scale = float(d.get("scale", 1.0))
			hnode.module_count = int(d.get("module_count", 3))
			hnode.set_meta("facility_model_mapping", d)
			hnode.set_meta("facility_model_fallback", bool(d.get("fallback", false)) or bool(d.get("habitat_fallback", false)))
			hnode.set_meta("facility_model_supported", true)
		return hnode
	var st = StationModel.new()
	st.station_type = String(d.get("model_type", FALLBACK_MODEL))
	st.station_label = String(d.get("name", d.get("facility_id", "FACILITY")))
	st.station_scale = float(d.get("scale", 1.0))
	st.module_count = int(d.get("module_count", 3))
	st.set_meta("facility_model_mapping", d)
	st.set_meta("facility_model_fallback", bool(d.get("fallback", false)))
	st.set_meta("facility_model_supported", bool(d.get("supported", false)))
	return st


static func summary(facilities: Array) -> Dictionary:
	var counts: Dictionary = {}
	var classes: Dictionary = {}
	var fallbacks := 0
	var total := 0
	var families: Dictionary = {}
	var habitats: Dictionary = {}
	for raw in facilities:
		if not (raw is Dictionary):
			continue
		total += 1
		var d := describe(raw)
		var mt := String(d.get("model_type", FALLBACK_MODEL))
		counts[mt] = int(counts.get(mt, 0)) + 1
		var cls := String(d.get("facility_class", ""))
		classes[cls] = int(classes.get(cls, 0)) + 1
		var fam := String(d.get("model_family", "module_station"))
		families[fam] = int(families.get(fam, 0)) + 1
		var ht := String(d.get("habitat_type", ""))
		if ht != "":
			habitats[ht] = int(habitats.get(ht, 0)) + 1
		if bool(d.get("fallback", false)) or bool(d.get("habitat_fallback", false)):
			fallbacks += 1
	return {"total": total, "by_model": counts, "by_class": classes,
		"by_family": families, "habitats": habitats,
		"fallbacks": fallbacks, "supported_classes": CLASS_TO_MODEL.keys(),
		"writes": {"world": false, "physics": false, "truth": false}}


static func mapping_table() -> Dictionary:
	var out: Dictionary = {}
	for cls in CLASS_TO_MODEL.keys():
		out[String(cls)] = mapping_for_class(String(cls))
	return out
