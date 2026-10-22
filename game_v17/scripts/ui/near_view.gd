extends Node

# 方案B-34：V1 HUD NEAR VIEW（SubViewport 3D）。
# 只读展示 Earth/Moon/选中设施模型；纯色材质，无贴图；不接物理/truth 位置。

const StationModel := preload("res://models/station_model.gd")
const FacilityModelFactory := preload("res://scripts/ui/facility_model_factory.gd")
const EARTH := preload("res://models/earth.tscn")
const MOON := preload("res://models/moon.tscn")

const CLASS_TO_TYPE := {
	"station": "port", "port": "port", "depot": "depot", "otc": "otc",
	"tank": "tank", "fuel": "fuel", "relay": "otc", "research": "research",
	"commercial": "port", "logistics": "depot", "industrial": "depot",
	"shipyard": "port", "observation": "research", "residential": "port",
	"agricultural": "tank", "water_utility": "tank", "salvage": "depot",
	"food_processing": "tank", "cultural": "station", "tourism": "station",
}
const CLASS_LABEL := {
	"station": "STATION", "port": "PORT", "depot": "DEPOT", "otc": "OTC",
	"tank": "TANK", "fuel": "FUEL", "relay": "RELAY", "research": "RESEARCH",
}

var viewport: SubViewport
var _camera: Camera3D
var _subject_root: Node3D
var _model: Node3D
var _subject := "earth"
var _facility_class := "port"
var _facility_label := "L1 PORT"
var _facility_radius_km := 0.0
var _info: Dictionary = {}


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "NearViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.own_world_3d = true
	add_child(viewport)
	_build_world()
	set_subject("earth", "station", "EARTH", 6371.0)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.24, 0.22)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	_camera = Camera3D.new()
	_camera.name = "NearCamera"
	_camera.position = Vector3(0.0, 0.45, 4.6)
	_camera.fov = 38.0
	viewport.add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.78)
	sun.light_energy = 1.45
	viewport.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 1.5, 3.5)
	fill.light_color = Color(0.38, 0.62, 0.66)
	fill.light_energy = 0.8
	fill.omni_range = 12.0
	viewport.add_child(fill)
	_subject_root = Node3D.new()
	_subject_root.name = "SubjectRoot"
	viewport.add_child(_subject_root)


func set_subject(subject: String, facility_class := "station", facility_label := "", facility_radius_km := 0.0, facility: Dictionary = {}) -> void:
	_subject = subject
	_facility_class = facility_class
	_facility_label = facility_label if facility_label != "" else ("L1 PORT" if facility_class == "port" else facility_class.to_upper())
	_facility_radius_km = facility_radius_km
	if _subject_root == null:
		return
	for ch in _subject_root.get_children():
		ch.queue_free()
	_model = null
	if subject == "earth":
		_model = EARTH.instantiate()
		_camera.position = Vector3(0.0, 0.42, 4.7)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		_info = {"subject": "EARTH", "facility_class": "", "model": "planet_model.gd / earth.tscn", "radius_km": 6371.0, "source": "LOCAL MODEL ASSET", "material": "StandardMaterial3D solid · grid · no texture"}
	elif subject == "moon":
		_model = MOON.instantiate()
		_camera.position = Vector3(0.0, 0.30, 1.75)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		_info = {"subject": "MOON", "facility_class": "", "model": "planet_model.gd / moon.tscn", "radius_km": 1737.0, "source": "LOCAL MODEL ASSET", "material": "StandardMaterial3D solid · grid · no texture"}
	else:
		var fac: Dictionary = facility.duplicate(true) if not facility.is_empty() else {
			"facility_class": facility_class, "name": _facility_label,
			"physical": {"radius_km": facility_radius_km},
		}
		if String(fac.get("facility_class", "")) == "":
			fac["facility_class"] = facility_class
		var mapping: Dictionary = FacilityModelFactory.describe(fac)
		var st = FacilityModelFactory.create(fac)
		_model = st
		var family := String(mapping.get("model_family", "module_station"))
		var habitat_type := String(mapping.get("habitat_type", ""))
		var framing := clampf(5.8 + float(mapping.get("scale", 1.0)) * 0.5, 5.8, 7.2)
		if family == "habitat":
			framing = 8.6 if habitat_type == "oneill" else 5.8
		_camera.position = Vector3(0.0, 1.25, framing)
		_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
		_info = {"subject": "FACILITY", "facility_class": String(mapping.get("facility_class", facility_class)),
			"model": ("habitat_model.gd / " + habitat_type) if family == "habitat" else ("station_model.gd / " + String(mapping.get("model_type", "port"))),
			"radius_km": float(mapping.get("radius_km", facility_radius_km)),
			"scale": (float(mapping.get("habitat_scale", 1.0)) if family == "habitat" else float(mapping.get("scale", 1.0))),
			"module_count": int(mapping.get("module_count", 3)),
			"mapping": String(mapping.get("habitat_label", mapping.get("mapping", ""))),
			"fallback": bool(mapping.get("fallback", true)) or bool(mapping.get("habitat_fallback", false)),
			"supported": bool(mapping.get("supported", false)),
			"family": family, "habitat_type": habitat_type,
			"habitat_known": bool(mapping.get("habitat_known", false)),
			"facility_type": habitat_type if family == "habitat" else String(mapping.get("model_type", "port")),
			"source": ("SELECTED HABITAT / LORE MAPPING" if family == "habitat" else "SELECTED FACILITY / DEFAULT L1 PORT / FACTORY"),
			"material": "StandardMaterial3D solid · procedural · no texture"}
	_subject_root.add_child(_model)
	_info["facility_label"] = _facility_label
	if subject == "facility":
		_info["facility_type"] = String(_info.get("habitat_type", "")) if String(_info.get("family", "")) == "habitat" else String(_info.get("model_type", "port"))
	else:
		_info["facility_type"] = ""


func get_info() -> Dictionary:
	return _info.duplicate(true)


func get_texture() -> Texture2D:
	return viewport.get_texture() if viewport != null else null


func set_view_size(px: Vector2i) -> void:
	if viewport != null:
		viewport.size = Vector2i(maxi(64, px.x), maxi(64, px.y))


func tick(delta: float) -> void:
	if _subject_root != null:
		_subject_root.rotation.y += delta * 0.16


static func facility_model_types() -> Array:
	return ["station", "depot", "port", "otc", "tank", "fuel", "relay", "research"]
