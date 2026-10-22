extends Node3D

# 程序化行星基础模型（无贴图）：SphereMesh + StandardMaterial3D + 可选经纬网。
# 尺度单位：preview 场景单位；radius 为场景半径，真实半径比例由实例参数体现。

@export var body_name := "EARTH"
@export var radius := 1.25
@export var base_color := Color(0.18, 0.38, 0.42)
@export var grid_color := Color(0.48, 0.72, 0.68, 0.30)
@export var atmosphere := true
@export var grid_lines := true


func _ready() -> void:
	_build()


func _mat(color: Color, rough := 0.95, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


func _build() -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	var mi := MeshInstance3D.new()
	mi.name = body_name + "_SPHERE"
	mi.mesh = sm
	mi.material_override = _mat(base_color, 1.0, 0.0)
	add_child(mi)
	if atmosphere:
		var am := SphereMesh.new()
		am.radius = radius * 1.035
		am.height = radius * 2.07
		am.radial_segments = 48
		am.rings = 24
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(base_color.r * 1.35, base_color.g * 1.35, base_color.b * 1.4, 0.10)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		var ami := MeshInstance3D.new()
		ami.name = body_name + "_ATMO"
		ami.mesh = am
		ami.material_override = mat
		add_child(ami)
	if grid_lines:
		_build_grid()


func _build_grid() -> void:
	var im := ImmediateMesh.new()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = grid_color
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_begin(Mesh.PRIMITIVE_LINES, gm)
	var rr := radius * 1.002
	for lat_deg in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var lat := deg_to_rad(lat_deg)
		var y := sin(lat) * rr
		var rr2 := cos(lat) * rr
		for i in range(48):
			var a0 := TAU * float(i) / 48.0
			var a1 := TAU * float(i + 1) / 48.0
			im.surface_add_vertex(Vector3(cos(a0) * rr2, y, sin(a0) * rr2))
			im.surface_add_vertex(Vector3(cos(a1) * rr2, y, sin(a1) * rr2))
	for lon_deg in [0.0, 45.0, 90.0, 135.0]:
		var lon := deg_to_rad(lon_deg)
		for i in range(48):
			var a0 := -PI * 0.5 + PI * float(i) / 48.0
			var a1 := -PI * 0.5 + PI * float(i + 1) / 48.0
			im.surface_add_vertex(Vector3(cos(a0) * cos(lon) * rr, sin(a0) * rr, cos(a0) * sin(lon) * rr))
			im.surface_add_vertex(Vector3(cos(a1) * cos(lon) * rr, sin(a1) * rr, cos(a1) * sin(lon) * rr))
	im.surface_end()
	var gmi := MeshInstance3D.new()
	gmi.name = body_name + "_GRID"
	gmi.mesh = im
	gmi.material_override = gm
	add_child(gmi)
