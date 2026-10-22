extends Node3D

# 方案B-32：程序化 3D 模型预览场景（纯色材质、无贴图、无外部下载）。
# 加载 Earth/Moon + L1 Port/OTC/Fuel Tank 预制，旋转展示；DSH_SHOT 截图。

const MODEL_PATHS := [
	"res://models/earth.tscn",
	"res://models/moon.tscn",
	"res://models/l1_port.tscn",
	"res://models/otc_satellite.tscn",
	"res://models/fuel_tank_farm.tscn",
]
const AsteroidScene := preload("res://models/asteroid_habitat_model.gd")
const ShipModel := preload("res://models/ship_model.gd")
const ASTEROID_PLACEMENTS := [
	{"path": "res://models/asteroid_oneill.tscn", "pos": Vector3(-4.2, 0.0, 0.0), "label": "ASTEROID O'NEILL · SAVANNAH"},
	{"path": "res://models/asteroid_stanford.tscn", "pos": Vector3(0.0, 0.0, 0.0), "label": "ASTEROID STANFORD · SATURNUS"},
	{"path": "res://models/asteroid_fortress.tscn", "pos": Vector3(4.2, 0.0, 0.0), "label": "ASTEROID FORTRESS · UEG"},
]
const HABITAT_PLACEMENTS := [
	{"path": "res://models/oneill_cylinder.tscn", "pos": Vector3(-1.7, 0.0, 0.0), "label": "O'NEILL TWIN CYLINDER · 30×7.5 km"},
	{"path": "res://models/stanford_torus.tscn", "pos": Vector3(2.9, 0.0, 0.0), "label": "STANFORD TORUS · Ø1.8 km"},
]
const STATION_PATHS := [
	"res://models/l1_port.tscn",
	"res://models/depot_station.tscn",
	"res://models/otc_satellite.tscn",
	"res://models/tank_cluster.tscn",
	"res://models/fuel_tank_farm.tscn",
	"res://models/research_lab.tscn",
]
const STATION_PLACEMENTS := [
	{"path": "res://models/l1_port.tscn", "pos": Vector3(-6.2, 2.3, 0.0), "label": "PORT · T-CORE"},
	{"path": "res://models/depot_station.tscn", "pos": Vector3(0.0, 2.3, 0.0), "label": "DEPOT · TRUSS"},
	{"path": "res://models/otc_satellite.tscn", "pos": Vector3(6.2, 2.3, 0.0), "label": "OTC · ANTENNA"},
	{"path": "res://models/tank_cluster.tscn", "pos": Vector3(-6.2, -2.3, 0.0), "label": "TANK · MULTI-CYL"},
	{"path": "res://models/fuel_tank_farm.tscn", "pos": Vector3(0.0, -2.3, 0.0), "label": "FUEL · ARM"},
	{"path": "res://models/research_lab.tscn", "pos": Vector3(6.2, -2.3, 0.0), "label": "RESEARCH · LAB"},
]
const PLACEMENTS := [
	{"path": "res://models/earth.tscn", "pos": Vector3(-3.25, 0.25, 0.00), "label": "EARTH · R 6371"},
	{"path": "res://models/moon.tscn", "pos": Vector3(-1.55, 0.18, 0.30), "label": "MOON · R 1737"},
	{"path": "res://models/l1_port.tscn", "pos": Vector3(0.55, 0.10, 0.10), "label": "L1 PORT · port"},
	{"path": "res://models/otc_satellite.tscn", "pos": Vector3(3.10, 0.55, -0.15), "label": "OTC SATELLITE"},
	{"path": "res://models/fuel_tank_farm.tscn", "pos": Vector3(5.40, 0.10, 0.20), "label": "FUEL TANK FARM"},
]

var _pivot: Node3D
var _camera: Camera3D
var _shot_path := ""
var _preview_mode := "default"
var _frames := 0
var _loaded: Array[String] = []
var _failed: Array[String] = []


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	_preview_mode = OS.get_environment("DSH_PREVIEW_VIEW")
	if _preview_mode not in ["stations", "habitats", "asteroid_habitats", "ships"]:
		_preview_mode = "default"
	var target := Vector2i(1920, 1080)
	var sz := OS.get_environment("DSH_HUD_SIZE")
	if sz != "":
		var parts := sz.split("x")
		if parts.size() == 2:
			target = Vector2i(int(parts[0]), int(parts[1]))
	var win := get_window()
	if win != null:
		win.size = target
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	_build_world()
	_build_models()
	if _shot_path != "":
		get_window().size = target
		Input.warp_mouse(Vector2(target) * 0.5)
	print("[MODEL PREVIEW] loaded=", _loaded.size(), " failed=", _failed.size(), " models=", str(_loaded), " errors=", str(_failed))





func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.022, 0.020)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.26, 0.24)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if _preview_mode == "stations":
		_camera.size = 13.0
		_camera.position = Vector3(0.0, 1.0, 12.0)
		add_child(_camera)
		_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	elif _preview_mode == "habitats":
		_camera.size = 6.4
		_camera.position = Vector3(0.0, 1.2, 12.0)
		add_child(_camera)
		_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	elif _preview_mode == "asteroid_habitats":
		_camera.size = 7.8
		_camera.position = Vector3(0.0, 1.3, 12.0)
		add_child(_camera)
		_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	elif _preview_mode == "ships":
		_camera.size = 6.6
		_camera.position = Vector3(0.0, 1.0, 12.0)
		add_child(_camera)
		_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	else:
		_camera.size = 8.2
		_camera.position = Vector3(1.15, 2.8, 11.0)
		add_child(_camera)
		_camera.look_at(Vector3(1.15, 0.05, 0.0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(-2.0, 2.0, 5.0)
	fill.light_color = Color(0.45, 0.66, 0.70)
	fill.light_energy = 0.9
	fill.omni_range = 18.0
	add_child(fill)
	# 2D 标题/说明
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "GHOST TRACK // APSIS · 3D MODEL PREVIEW"
	title.position = Vector2(36, 26)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 0.82, 0.74))
	layer.add_child(title)
	var sub := Label.new()
	sub.text = ("ASTEROID HABITATS · A BAOA QU-STYLE ROCK SHELL + INNER O'NEILL/STANFORD · PROCEDURAL · NO TEXTURES" if _preview_mode == "asteroid_habitats" else ("HARD-SCIFI SHIPS · CDE/SFHD MODULES · 8 FRIENDLY + BB/CA/CL/DD/FF/AV · PROCEDURAL · NO TEXTURES" if _preview_mode == "ships" else ("HABITAT STRUCTURES · O'NEILL TWIN CYLINDER / STANFORD TORUS · VISUAL ROTATION · PROCEDURAL · NO TEXTURES" if _preview_mode == "habitats" else ("STATION STRUCTURES · T-CORE / TRUSS / SOLAR WINGS / RADIATORS / DOCKS · PROCEDURAL · NO TEXTURES" if _preview_mode == "stations" else "PROCEDURAL GEOMETRY · SOLID MATERIALS · NO TEXTURES · GL COMPATIBILITY"))))
	sub.position = Vector2(38, 56)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.42, 0.52, 0.49))
	layer.add_child(sub)
	var foot := Label.new()
	foot.text = "EARTH 6371 km · MOON 1737 km · STATION TYPES: port / depot / otc / tank / fuel / research"
	foot.position = Vector2(38, 1030)
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", Color(0.38, 0.46, 0.44))
	layer.add_child(foot)


func _build_ship_preview() -> void:
	var specs: Array = []
	var fp := "res://framework/content/ships_friendly.json"
	var ep := "res://framework/content/ships_enemy.json"
	if FileAccess.file_exists(fp) and FileAccess.file_exists(ep):
		var fj = JSON.parse_string(FileAccess.get_file_as_string(fp))
		var ej = JSON.parse_string(FileAccess.get_file_as_string(ep))
		if fj is Dictionary and ej is Dictionary:
			var fclasses: Array = (fj as Dictionary).get("classes", []) if (fj as Dictionary).get("classes", []) is Array else []
			var eclasses: Array = (ej as Dictionary).get("classes", []) if (ej as Dictionary).get("classes", []) is Array else []
			var all_specs: Array = ShipModel.variant_specs(fclasses, eclasses)
			var wanted := {"BB": false, "CA": false, "CL": false, "DD": false, "FF": false, "AV": false}
			for raw in all_specs:
				if raw is Dictionary and String((raw as Dictionary).get("faction", "")) == "friendly":
					specs.append(raw)
			for raw2 in all_specs:
				if raw2 is Dictionary and String((raw2 as Dictionary).get("faction", "")) == "enemy":
					var sc := String((raw2 as Dictionary).get("ship_class", ""))
					if wanted.has(sc) and not bool(wanted[sc]):
						wanted[sc] = true
						specs.append(raw2)
	if specs.is_empty():
		specs = ShipModel.variant_specs([], [])
	var cols := 4
	var row_gap := 1.45
	var col_gap := 2.75
	var start_x := -float(cols - 1) * col_gap * 0.5
	var rows := int(ceil(float(specs.size()) / float(cols)))
	var start_y := float(rows - 1) * row_gap * 0.5
	for i in range(mini(14, specs.size())):
		var spec: Dictionary = specs[i]
		var sm = ShipModel.new()
		sm.ship_class = String(spec.get("ship_class", "DD"))
		sm.ship_role = String(spec.get("ship_role", "escort"))
		sm.ship_size = float(spec.get("ship_size", 3.2))
		sm.radiator_count = int(spec.get("radiator_count", 3))
		sm.weapon_fit = String(spec.get("weapon_fit", "railgun"))
		sm.faction = String(spec.get("faction", "friendly"))
		sm.ship_label = String(spec.get("class_id", ""))
		var col := i % cols
		var row := int(i / cols)
		sm.position = Vector3(start_x + float(col) * col_gap, start_y - float(row) * row_gap, 0.0)
		sm.scale = Vector3.ONE * 0.35
		_pivot.add_child(sm)
		_loaded.append(String(spec.get("class_id", "ship")))
		var slbl := Label3D.new()
		slbl.text = String(spec.get("ship_class", "?")) + " · " + String(spec.get("ship_role", ""))
		slbl.font_size = 20
		slbl.pixel_size = 0.0030
		slbl.modulate = Color(0.58, 0.80, 0.72) if String(spec.get("faction", "")) == "friendly" else Color(0.82, 0.67, 0.45)
		slbl.outline_size = 6
		slbl.outline_modulate = Color(0.01, 0.02, 0.02, 0.9)
		slbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slbl.no_depth_test = true
		slbl.position = sm.position + Vector3(0.0, 0.45, 0.0)
		_pivot.add_child(slbl)


func _build_models() -> void:
	_pivot = Node3D.new()
	_pivot.name = "ShowcasePivot"
	add_child(_pivot)
	if _preview_mode == "asteroid_habitats":
		for spec in ASTEROID_PLACEMENTS:
			var apath := String((spec as Dictionary).get("path", ""))
			var apacked = load(apath)
			if apacked == null or not (apacked is PackedScene):
				_failed.append(apath)
				continue
			var anode = (apacked as PackedScene).instantiate()
			if anode == null:
				_failed.append(apath)
				continue
			_pivot.add_child(anode)
			anode.scale = anode.scale * 0.85
			anode.position = (spec as Dictionary).get("pos", Vector3.ZERO)
			_loaded.append(apath)
			var albl := Label3D.new()
			albl.text = String((spec as Dictionary).get("label", ""))
			albl.font_size = 26
			albl.pixel_size = 0.0035
			albl.modulate = Color(0.58, 0.80, 0.72)
			albl.outline_size = 8
			albl.outline_modulate = Color(0.01, 0.02, 0.02, 0.9)
			albl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			albl.no_depth_test = true
			albl.position = (spec as Dictionary).get("pos", Vector3.ZERO) + Vector3(0.0, 2.0, 0.0)
			_pivot.add_child(albl)
		return
	if _preview_mode == "ships":
		_build_ship_preview()
		return
	if _preview_mode == "habitats":
		for spec in HABITAT_PLACEMENTS:
			var hpath := String((spec as Dictionary).get("path", ""))
			var hpacked = load(hpath)
			if hpacked == null or not (hpacked is PackedScene):
				_failed.append(hpath)
				continue
			var hnode = (hpacked as PackedScene).instantiate()
			if hnode == null:
				_failed.append(hpath)
				continue
			_pivot.add_child(hnode)
			hnode.position = (spec as Dictionary).get("pos", Vector3.ZERO)
			_loaded.append(hpath)
			var hlbl := Label3D.new()
			hlbl.text = String((spec as Dictionary).get("label", ""))
			hlbl.font_size = 30
			hlbl.pixel_size = 0.0035
			hlbl.modulate = Color(0.58, 0.80, 0.72)
			hlbl.outline_size = 8
			hlbl.outline_modulate = Color(0.01, 0.02, 0.02, 0.9)
			hlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			hlbl.no_depth_test = true
			hlbl.position = (spec as Dictionary).get("pos", Vector3.ZERO) + Vector3(0.0, 1.55, 0.0)
			_pivot.add_child(hlbl)
		return
	if _preview_mode == "stations":
		for spec in STATION_PLACEMENTS:
			var stpath := String((spec as Dictionary).get("path", ""))
			var spacked = load(stpath)
			if spacked == null or not (spacked is PackedScene):
				_failed.append(stpath)
				continue
			var snode = (spacked as PackedScene).instantiate()
			if snode == null:
				_failed.append(stpath)
				continue
			snode.scale = snode.scale * 0.30
			_pivot.add_child(snode)
			snode.position = (spec as Dictionary).get("pos", Vector3.ZERO)
			_loaded.append(stpath)
			var slbl := Label3D.new()
			slbl.text = String((spec as Dictionary).get("label", ""))
			slbl.font_size = 30
			slbl.pixel_size = 0.0038
			slbl.modulate = Color(0.58, 0.80, 0.72)
			slbl.outline_size = 8
			slbl.outline_modulate = Color(0.01, 0.02, 0.02, 0.9)
			slbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			slbl.no_depth_test = true
			slbl.position = (spec as Dictionary).get("pos", Vector3.ZERO) + Vector3(0.0, 1.55, 0.0)
			_pivot.add_child(slbl)
		return
	for spec in PLACEMENTS:
		var path := String((spec as Dictionary).get("path", ""))
		var packed = load(path)
		if packed == null or not (packed is PackedScene):
			_failed.append(path)
			continue
		var node = (packed as PackedScene).instantiate()
		if node == null:
			_failed.append(path)
			continue
		_pivot.add_child(node)
		node.position = (spec as Dictionary).get("pos", Vector3.ZERO)
		_loaded.append(path)
		var lbl := Label3D.new()
		lbl.text = String((spec as Dictionary).get("label", ""))
		lbl.font_size = 30
		lbl.pixel_size = 0.0038
		lbl.modulate = Color(0.58, 0.80, 0.72)
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0.01, 0.02, 0.02, 0.9)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = (spec as Dictionary).get("pos", Vector3.ZERO) + Vector3(0.0, 1.48, 0.0)
		_pivot.add_child(lbl)


func _process(delta: float) -> void:
	if _pivot != null:
		_pivot.rotation.y += delta * 0.06
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("[MODEL PREVIEW] SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()
