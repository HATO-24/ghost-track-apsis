extends Node3D

# 方案B-40：UEG 军用小行星要塞（A Baoa Qu 式双体小行星）。
# 双体岩壳 + 中央指挥塔 + 要塞火力/机库/装甲/系泊；纯色程序化，不是民用居住站。
# 兼容 FacilityModelFactory/probe 的 station_type/station_scale/module_count。
@export var fortress_label := "L2-07 HORIZON"
@export var fortress_scale := 1.0
@export var station_type := "station"
@export var station_scale := 1.0
@export var module_count := 6

var _rock: StandardMaterial3D
var _rock_dark: StandardMaterial3D
var _hull: StandardMaterial3D
var _armor: StandardMaterial3D
var _accent: StandardMaterial3D
var _weapon: StandardMaterial3D
var _window: StandardMaterial3D
var _dark: StandardMaterial3D
var _tower: Node3D


func _ready() -> void:
	scale = Vector3.ONE * fortress_scale
	_build_materials()
	_build_asteroid()
	_build_towers()
	_build_weapons()


func _build_materials() -> void:
	_rock = _mat(Color(0.26, 0.25, 0.23), 1.0, 0.0)
	_rock_dark = _mat(Color(0.16, 0.16, 0.15), 1.0, 0.0)
	_hull = _mat(Color(0.36, 0.39, 0.39), 0.82, 0.04)
	_armor = _mat(Color(0.29, 0.31, 0.31), 0.88, 0.06)
	_accent = _mat(Color(0.53, 0.44, 0.28), 0.72, 0.05)
	_weapon = _mat(Color(0.13, 0.15, 0.15), 0.86, 0.12)
	_window = _mat(Color(0.58, 0.48, 0.30), 0.50, 0.02)
	_dark = _mat(Color(0.12, 0.13, 0.13), 0.9, 0.02)


func _mat(c: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _orient_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _cyl(pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg := 14) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = seg
	cm.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.transform = Transform3D(_orient_y(dir), pos)
	mi.material_override = mat
	add_child(mi)


func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)


func _sphere(pos: Vector3, radius: float, mat: StandardMaterial3D, scl := Vector3.ONE) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 7
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	add_child(mi)


func _torus(pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D) -> void:
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


func _build_asteroid() -> void:
	# 盘 + 锥双体岩壳；中央接合环
	_sphere(Vector3(-1.05, 0.0, 0.0), 1.05, _rock, Vector3(1.10, 0.80, 0.86))
	_sphere(Vector3(0.95, 0.02, 0.0), 0.82, _rock_dark, Vector3(1.18, 0.66, 0.84))
	_sphere(Vector3(-0.1, 0.42, -0.38), 0.46, _rock, Vector3(0.85, 0.48, 0.58))
	_sphere(Vector3(0.35, -0.34, 0.42), 0.34, _rock_dark, Vector3(0.76, 0.40, 0.52))
	for i in range(11):
		var a := TAU * float(i) / 11.0
		_sphere(Vector3(cos(a) * 0.95 - 0.85, sin(a) * 0.55, sin(a) * 0.38 + 0.05), 0.09 + 0.025 * float(i % 3), _rock_dark, Vector3(1.0, 0.22, 1.0))
	_torus(Vector3(-0.02, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.86, 0.98, _armor)
	for i in range(8):
		var a2 := TAU * float(i) / 8.0
		_cyl(Vector3(-0.02, cos(a2) * 0.90, sin(a2) * 0.90), Vector3.RIGHT, 0.035, 1.7, _accent, 6)
	# 装甲/固定炮座基座
	for x in [-1.55, 1.35]:
		_box(Vector3(x, 0.0, 0.0), Vector3(0.34, 0.65, 0.62), _armor)
		_cyl(Vector3(x, 0.0, 0.0), Vector3.RIGHT, 0.14, 0.36, _dark, 12)


func _build_towers() -> void:
	# 中央塔/机库/系泊
	_cyl(Vector3(0.0, 1.15, 0.0), Vector3.UP, 0.17, 1.20, _hull, 12)
	_cyl(Vector3(0.0, 1.83, 0.0), Vector3.UP, 0.26, 0.22, _armor, 14)
	_box(Vector3(0.0, 2.05, 0.0), Vector3(0.46, 0.30, 0.38), _hull)
	for x in [-0.22, 0.22]:
		_box(Vector3(x, 2.05, 0.22), Vector3(0.08, 0.08, 0.02), _window)
	_cyl(Vector3(0.0, 2.35, 0.0), Vector3.UP, 0.025, 0.50, _dark, 6)
	_sphere(Vector3(0.0, 2.62, 0.0), 0.06, _accent)
	# 机库/机库门
	_box(Vector3(0.0, -0.35, 0.88), Vector3(1.10, 0.42, 0.22), _hull)
	_box(Vector3(0.0, -0.35, 1.00), Vector3(0.72, 0.24, 0.02), _window)
	for i in range(5):
		_box(Vector3(-0.42 + 0.21 * float(i), -0.35, 1.02), Vector3(0.06, 0.24, 0.02), _dark)
	# 系泊/对接口
	for x2 in [-0.55, 0.55]:
		_cyl(Vector3(x2, -0.82, 0.0), Vector3.DOWN, 0.10, 0.30, _hull, 10)
		_torus(Vector3(x2, -0.98, 0.0), Vector3.ZERO, 0.08, 0.12, _accent)
	# L2 系泊桁架/散热鳍
	_cyl(Vector3(1.65, 0.0, 0.0), Vector3.RIGHT, 0.06, 0.55, _dark, 8)
	_box(Vector3(1.65, 0.0, 0.0), Vector3(0.32, 0.50, 0.08), _armor)
	for z in [-1.0, 1.0]:
		_box(Vector3(-0.35, 0.25, z), Vector3(0.60, 0.014, 0.36), _armor, Vector3(0.0, 0.0, 0.16))
		_box(Vector3(-0.35, 0.25, z * 1.22), Vector3(0.08, 0.020, 0.24), _dark)


func _build_weapons() -> void:
	# 炮塔/轨道炮/激光/导弹舱
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var bp := Vector3(cos(a) * 0.62, 0.42 + sin(a) * 0.18, sin(a) * 0.62)
		_cyl(bp, Vector3.UP, 0.075, 0.16, _armor, 10)
		_cyl(bp + Vector3(0, 0.15, 0), Vector3.UP, 0.035, 0.34, _weapon, 8)
		_sphere(bp + Vector3(0, 0.33, 0), 0.09, _armor)
	for x in [-0.78, 0.42]:
		_box(Vector3(x, 0.48, -0.42), Vector3(0.40, 0.18, 0.22), _armor)
		_cyl(Vector3(x, 0.55, -0.62), Vector3(0, 0, -1), 0.035, 0.58, _weapon, 8)
	for z in [-0.8, 0.8]:
		_box(Vector3(0.55, -0.10, z), Vector3(0.28, 0.16, 0.16), _weapon)
		_box(Vector3(0.55, -0.10, z * 1.15), Vector3(0.20, 0.10, 0.02), _window)
	# 装甲板/Whipple 层
	for i in range(3):
		_box(Vector3(-1.8 + 0.15 * float(i), 0.45, 0.0), Vector3(0.25, 0.015, 0.62), _armor, Vector3(0.0, 0.0, 0.20))
