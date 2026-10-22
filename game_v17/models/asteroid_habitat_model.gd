extends Node3D

# 方案B-40：低资源小行星居住改造（民用）。独立于 O'Neill/Stanford 与军用要塞。
# 无内部 O'Neill/Stanford：切面露出小舱段/隧道/生活模块；纯色、程序化、无贴图。
@export_enum("asteroid_habitat", "asteroid_fortress", "asteroid_oneill", "asteroid_stanford") var asteroid_type := "asteroid_habitat"
@export var habitat_label := "L5-11 VICTORIA"
@export var habitat_scale := 1.0
@export var rotation_speed := 0.04
# 兼容 FacilityModelFactory/probe 字段（不用于外壳设计）
@export var station_type := "station"
@export var module_count := 3
@export var station_scale := 1.0
@export var habitat_type := "asteroid_habitat"

var _rock: StandardMaterial3D
var _rock_dark: StandardMaterial3D
var _hull: StandardMaterial3D
var _accent: StandardMaterial3D
var _window: StandardMaterial3D
var _radiator: StandardMaterial3D
var _solar: StandardMaterial3D
var _dark: StandardMaterial3D
var _shell: Node3D
var _civil: Node3D


func _ready() -> void:
	scale = Vector3.ONE * habitat_scale
	_build_materials()
	_shell = Node3D.new()
	add_child(_shell)
	_build_asteroid()
	_build_civilian_cutaway()
	_build_retrofit()


func _build_materials() -> void:
	_rock = _mat(Color(0.28, 0.27, 0.25), 1.0, 0.0)
	_rock_dark = _mat(Color(0.17, 0.17, 0.16), 1.0, 0.0)
	_hull = _mat(Color(0.43, 0.46, 0.45), 0.80, 0.04)
	_accent = _mat(Color(0.30, 0.50, 0.47), 0.70, 0.06)
	_window = _mat(Color(0.33, 0.64, 0.68), 0.42, 0.04)
	_radiator = _mat(Color(0.60, 0.62, 0.60), 0.72, 0.01)
	_solar = _mat(Color(0.09, 0.16, 0.20), 0.55, 0.20)
	_dark = _mat(Color(0.14, 0.16, 0.16), 0.9, 0.02)


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


func _cyl(parent: Node3D, pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg := 14) -> MeshInstance3D:
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
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, scl := Vector3.ONE) -> MeshInstance3D:
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
	parent.add_child(mi)
	return mi


func _torus(parent: Node3D, pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 20
	tm.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_asteroid() -> void:
	# 双体小型不规则岩壳：盘状 + 锥状/椭球，切面开口
	_sphere(_shell, Vector3(-0.78, 0.0, 0.02), 0.78, _rock, Vector3(1.15, 0.82, 0.78))
	_sphere(_shell, Vector3(0.70, 0.04, -0.06), 0.62, _rock_dark, Vector3(1.10, 0.68, 0.80))
	_sphere(_shell, Vector3(-0.22, 0.34, -0.28), 0.34, _rock, Vector3(0.62, 0.46, 0.48))
	_sphere(_shell, Vector3(0.30, -0.26, 0.32), 0.28, _rock_dark, Vector3(0.55, 0.40, 0.50))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		_sphere(_shell, Vector3(cos(a) * 0.80 - 0.70, sin(a) * 0.48, sin(a) * 0.26 + 0.10), 0.08 + 0.02 * float(i % 3), _rock_dark, Vector3(1.0, 0.20, 1.0))
	# 切面结构环/框梁（普通改造，不是 O'Neill/Stanford）
	_torus(_shell, Vector3(0.0, 0.0, 0.62), Vector3(PI * 0.5, 0.0, 0.0), 0.55, 0.66, _accent)
	_torus(_shell, Vector3(0.0, 0.0, 0.64), Vector3(PI * 0.5, 0.0, 0.0), 0.28, 0.34, _window)
	for i in range(4):
		var a2 := TAU * float(i) / 4.0
		_box(_shell, Vector3(cos(a2) * 0.59, sin(a2) * 0.59, 0.64), Vector3(0.08, 0.08, 0.09), _hull)
		_cyl(_shell, Vector3(cos(a2) * 0.64, sin(a2) * 0.64, 0.58), Vector3(0, 0, 1), 0.02, 0.24, _dark, 6)
	_cyl(_shell, Vector3(0.0, 0.0, 0.48), Vector3(0, 0, 1), 0.54, 0.05, _dark, 20)


func _build_civilian_cutaway() -> void:
	# 低资源改造：小舱段/隧道/生活模块，直接露出切面；不嵌入大型环/柱
	_civil = Node3D.new()
	_civil.name = "CivilianCutaway"
	add_child(_civil)
	_cyl(_civil, Vector3(0.0, 0.0, 0.72), Vector3.RIGHT, 0.15, 0.72, _hull, 12)
	_cyl(_civil, Vector3(-0.30, 0.0, 0.72), Vector3.BACK, 0.10, 0.42, _dark, 10)
	_cyl(_civil, Vector3(0.30, 0.0, 0.72), Vector3.BACK, 0.10, 0.42, _dark, 10)
	for x in [-0.26, 0.0, 0.26]:
		_sphere(_civil, Vector3(x, 0.22, 0.73), 0.12, _hull, Vector3(0.8, 0.8, 1.0))
		_box(_civil, Vector3(x, 0.22, 0.78), Vector3(0.14, 0.10, 0.02), _window)
	for z in [-0.24, 0.24]:
		_box(_civil, Vector3(0.0, -0.18, 0.72 + z), Vector3(0.40, 0.12, 0.12), _hull)
	# 小型隧道/生活舱段（可见灯带）
	_cyl(_civil, Vector3(-0.05, -0.28, 0.74), Vector3.RIGHT, 0.07, 0.48, _accent, 8)
	_box(_civil, Vector3(-0.05, -0.28, 0.82), Vector3(0.38, 0.015, 0.015), _window)
	_box(_civil, Vector3(0.0, 0.0, 0.84), Vector3(0.52, 0.02, 0.015), _window)
	# 一个小型散热片和太阳能板，符合“低资源改造”
	_box(_civil, Vector3(0.0, -0.38, 0.66), Vector3(0.44, 0.012, 0.22), _radiator)
	_box(_civil, Vector3(0.36, 0.34, 0.64), Vector3(0.30, 0.012, 0.16), _solar)


func _build_retrofit() -> void:
	# 拖曳改造：尾部推进模块/系泊塔/中央指挥塔/散热鳍/太阳翼/对接口
	for y in [0.24, -0.24]:
		_cyl(_shell, Vector3(-1.42, y, 0.0), Vector3.RIGHT, 0.12, 0.32, _dark, 12)
		_cyl(_shell, Vector3(-1.60, y, 0.0), Vector3.RIGHT, 0.17, 0.09, _accent, 12)
	_box(_shell, Vector3(-1.34, 0.0, 0.0), Vector3(0.16, 0.66, 0.44), _hull)
	_cyl(_shell, Vector3(1.15, 0.25, 0.0), Vector3.RIGHT, 0.15, 0.26, _hull, 12)
	_torus(_shell, Vector3(1.32, 0.25, 0.0), Vector3(0, 0, PI * 0.5), 0.10, 0.15, _accent)
	# 中央塔/天线
	_cyl(_shell, Vector3(0.0, 0.98, 0.0), Vector3.UP, 0.09, 0.55, _hull, 10)
	_box(_shell, Vector3(0.0, 1.30, 0.0), Vector3(0.28, 0.18, 0.24), _hull)
	_cyl(_shell, Vector3(0.0, 1.52, 0.0), Vector3.UP, 0.018, 0.32, _dark, 6)
	_sphere(_shell, Vector3(0.0, 1.70, 0.0), 0.05, _accent)
	# 散热鳍/太阳翼
	for z in [-0.95, 0.95]:
		_box(_shell, Vector3(-0.15, 0.18, z), Vector3(0.50, 0.012, 0.40), _radiator, Vector3(0.0, 0.0, 0.10))
		_box(_shell, Vector3(-0.62, 0.0, z * 1.35), Vector3(0.78, 0.012, 0.36), _solar)
		_cyl(_shell, Vector3(-0.62, 0.0, z * 1.12), Vector3(1, 0, 0), 0.022, 0.62, _dark, 6)
	# 对接口/系泊塔
	for x2 in [-0.05, 0.26]:
		_torus(_shell, Vector3(x2, -0.72, 0.0), Vector3(0, 0, PI * 0.5), 0.07, 0.12, _accent)
		_cyl(_shell, Vector3(x2, -0.68, 0.0), Vector3.DOWN, 0.05, 0.18, _hull, 8)
	_cyl(_shell, Vector3(0.78, -0.42, 0.0), Vector3.UP, 0.05, 0.44, _hull, 8)


func _process(delta: float) -> void:
	if _civil != null:
		_civil.rotation.y += rotation_speed * delta
	if _shell != null:
		_shell.rotation.y += rotation_speed * delta * 0.10
