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
var _frames := 0
var _loaded: Array[String] = []
var _failed: Array[String] = []


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
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
	sub.text = "PROCEDURAL GEOMETRY · SOLID MATERIALS · NO TEXTURES · GL COMPATIBILITY"
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


func _build_models() -> void:
	_pivot = Node3D.new()
	_pivot.name = "ShowcasePivot"
	add_child(_pivot)
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
