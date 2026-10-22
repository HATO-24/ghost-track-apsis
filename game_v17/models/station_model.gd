extends Node3D

# 程序化空间站基础模型（无贴图）：圆柱/环/箱体/太阳能板组合。
# 参数：station_type, station_scale, module_count；preview 只读展示，不接 world。

@export_enum("depot", "port", "otc", "tank", "fuel", "research") var station_type := "port"
@export var station_label := "L1 PORT"
@export var station_scale := 1.0
@export var module_count := 4

var _hull: StandardMaterial3D
var _accent: StandardMaterial3D
var _solar: StandardMaterial3D
var _amber: StandardMaterial3D
var _dark: StandardMaterial3D


func _ready() -> void:
	scale = Vector3.ONE * station_scale
	_build_materials()
	match station_type:
		"otc":
			_build_otc()
		"tank", "fuel":
			_build_tank()
		"depot":
			_build_depot()
		"research":
			_build_research()
		_:
			_build_port()


func _build_materials() -> void:
	_hull = _mat(Color(0.40, 0.44, 0.45), 0.82, 0.02)
	_accent = _mat(Color(0.30, 0.52, 0.49), 0.70, 0.05)
	_solar = _mat(Color(0.10, 0.18, 0.23), 0.55, 0.20)
	_amber = _mat(Color(0.64, 0.50, 0.28), 0.78, 0.02)
	_dark = _mat(Color(0.16, 0.18, 0.18), 0.9, 0.0)


func _mat(c: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _add_cyl(pos: Vector3, rot: Vector3, radius: float, height: float, mat: StandardMaterial3D, segments := 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_torus(pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_solar(pos: Vector3, rot: Vector3, size: Vector3) -> void:
	_add_box(pos, size, _solar)
	# 1px 框架（薄箱体）
	_add_box(pos + Vector3(0, 0.012, 0), Vector3(size.x, 0.008, 0.012), _hull)
	_add_box(pos + Vector3(0, 0.012, 0), Vector3(0.012, 0.008, size.z), _hull)


func _build_spine(mat: StandardMaterial3D, length: float, radius: float) -> void:
	_add_cyl(Vector3.ZERO, Vector3(0, 0, PI * 0.5), radius, length, mat, 14)
	for i in range(maxi(2, module_count)):
		var x := -length * 0.5 + length * (float(i) + 0.5) / float(maxi(2, module_count))
		_add_box(Vector3(x, 0.0, 0.0), Vector3(0.22, 0.24, 0.24), _dark)
		_add_box(Vector3(x, 0.0, 0.0), Vector3(0.18, 0.18, 0.18), _accent)


func _build_port() -> void:
	_build_spine(_hull, 1.9, 0.09)
	_add_torus(Vector3(0.0, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.55, 0.68, _hull)
	_add_torus(Vector3(0.0, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.32, 0.10, _accent)
	_add_solar(Vector3(0.0, 0.0, -0.62), Vector3.ZERO, Vector3(1.35, 0.02, 0.42))
	_add_solar(Vector3(0.0, 0.0, 0.62), Vector3.ZERO, Vector3(1.35, 0.02, 0.42))
	_add_cyl(Vector3(-1.05, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.16, 0.24, _accent, 10)
	_add_cyl(Vector3(1.05, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.16, 0.24, _accent, 10)
	_add_box(Vector3(0.0, 0.38, 0.0), Vector3(0.30, 0.24, 0.30), _hull)


func _build_otc() -> void:
	_add_cyl(Vector3.ZERO, Vector3.ZERO, 0.16, 1.0, _hull, 14)
	_add_torus(Vector3(0.0, 0.15, 0.0), Vector3.ZERO, 0.52, 0.67, _hull)
	_add_solar(Vector3(-0.95, 0.1, 0.0), Vector3(0, 0, 0.15), Vector3(1.15, 0.02, 0.40))
	_add_solar(Vector3(0.95, 0.1, 0.0), Vector3(0, 0, -0.15), Vector3(1.15, 0.02, 0.40))
	var dish := SphereMesh.new()
	dish.radius = 0.46
	dish.height = 0.92
	dish.is_hemisphere = true
	dish.radial_segments = 24
	dish.rings = 8
	var dmi := MeshInstance3D.new()
	dmi.mesh = dish
	dmi.position = Vector3(0.0, 0.72, 0.0)
	dmi.rotation = Vector3(0.0, 0.0, PI)
	dmi.material_override = _accent
	add_child(dmi)
	_add_cyl(Vector3(0.0, 1.02, 0.0), Vector3.ZERO, 0.025, 0.62, _accent, 6)
	_add_box(Vector3(0.0, -0.45, 0.0), Vector3(0.26, 0.25, 0.26), _dark)


func _build_tank() -> void:
	_add_torus(Vector3(0.0, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.68, 0.82, _hull)
	for i in range(3):
		var x := -0.55 + float(i) * 0.55
		_add_cyl(Vector3(x, 0.0, 0.0), Vector3.ZERO, 0.20, 1.05, _accent, 12)
		_add_cyl(Vector3(x, 0.52, 0.0), Vector3.ZERO, 0.205, 0.03, _amber, 12)
		_add_box(Vector3(x, -0.30, 0.0), Vector3(0.10, 0.32, 0.10), _dark)
	_add_cyl(Vector3(0.0, 0.10, 0.0), Vector3(0, 0, PI * 0.5), 0.035, 1.45, _hull, 8)
	_add_cyl(Vector3(0.0, -0.12, 0.0), Vector3(0, 0, PI * 0.5), 0.025, 1.15, _amber, 8)
	_add_box(Vector3(0.0, -0.55, 0.0), Vector3(1.7, 0.10, 0.62), _hull)


func _build_depot() -> void:
	_build_spine(_hull, 1.5, 0.10)
	_add_torus(Vector3(0.0, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.45, 0.58, _accent)
	_add_box(Vector3(0.0, 0.34, 0.0), Vector3(0.75, 0.36, 0.55), _hull)
	for i in range(maxi(2, module_count)):
		var x := -0.55 + 1.1 * float(i) / float(maxi(1, module_count - 1))
		_add_box(Vector3(x, -0.36, 0.20), Vector3(0.24, 0.22, 0.34), _amber if i % 2 == 0 else _accent)
	_add_solar(Vector3(0.0, 0.0, -0.62), Vector3.ZERO, Vector3(1.0, 0.02, 0.36))


func _build_research() -> void:
	_add_torus(Vector3.ZERO, Vector3.ZERO, 0.64, 0.78, _hull)
	_add_cyl(Vector3(0.0, -0.25, 0.0), Vector3.ZERO, 0.13, 0.55, _hull, 10)
	_add_solar(Vector3(-0.95, 0.0, 0.0), Vector3.ZERO, Vector3(1.1, 0.02, 0.42))
	_add_solar(Vector3(0.95, 0.0, 0.0), Vector3.ZERO, Vector3(1.1, 0.02, 0.42))
	for i in range(maxi(2, module_count)):
		var a := TAU * float(i) / float(maxi(2, module_count))
		_add_box(Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55), Vector3(0.18, 0.20, 0.18), _accent)
