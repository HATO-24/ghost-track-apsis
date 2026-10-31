extends Node3D

# 方案B-37/41：大型居住站程序化模型（奥尼尔 Island Three / 斯坦福环面）。
# 纯色基础材质、无贴图；旋转仅视觉示意，不接物理。尺度为预览单位，不是真实 km。
const OneillModel := preload("res://models/oneill_island3_hi.gd")

@export_enum("oneill", "stanford") var habitat_type := "oneill"
@export var habitat_label := "L5-07 SAVANNAH"
@export var habitat_scale := 1.0
@export var rotation_speed := 0.28
# 兼容 FacilityModelFactory/probe 的模块字段；居住站不使用这些值。
@export var station_type := "port"
@export var module_count := 4
@export var station_scale := 1.0

var _hull: StandardMaterial3D
var _window: StandardMaterial3D
var _land: StandardMaterial3D
var _radiator: StandardMaterial3D
var _solar: StandardMaterial3D
var _dark: StandardMaterial3D
var _accent: StandardMaterial3D
var _rotor_a: Node3D
var _rotor_b: Node3D
var _rotor: Node3D


func _ready() -> void:
	scale = Vector3.ONE * habitat_scale
	_build_materials()
	if habitat_type == "stanford":
		_build_stanford()
	else:
		_build_oneill()


func _build_materials() -> void:
	_hull = _mat(Color(0.44, 0.47, 0.46), 0.80, 0.03)
	_window = _mat(Color(0.33, 0.64, 0.68), 0.42, 0.05)
	_land = _mat(Color(0.27, 0.44, 0.31), 0.95, 0.0)
	_radiator = _mat(Color(0.59, 0.61, 0.59), 0.78, 0.01)
	_solar = _mat(Color(0.09, 0.16, 0.20), 0.52, 0.22)
	_dark = _mat(Color(0.14, 0.16, 0.16), 0.9, 0.0)
	_accent = _mat(Color(0.29, 0.50, 0.46), 0.72, 0.05)


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


func _cyl(parent: Node3D, pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, segments := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
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


func _torus(parent: Node3D, pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 36
	tm.ring_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, hemisphere := false) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	sm.is_hemisphere = hemisphere
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _surface_strips(parent: Node3D, radius: float, length: float) -> void:
	# 窗带/陆地带/散热条：沿圆柱表面的纵向条带（随圆柱自转）
	for i in range(6):
		var ang := TAU * float(i) / 6.0
		var y := cos(ang) * radius * 1.004
		var z := sin(ang) * radius * 1.004
		var mat: StandardMaterial3D = _window if i % 3 == 0 else (_land if i % 3 == 1 else _radiator)
		var w := 0.11 if i % 3 == 0 else (0.24 if i % 3 == 1 else 0.08)
		_box(parent, Vector3(0, y, z), Vector3(length * 0.82, w, 0.018), mat)
	for i in range(4):
		var ang2 := TAU * float(i) / 4.0
		var y2 := cos(ang2) * radius * 1.005
		var z2 := sin(ang2) * radius * 1.005
		_box(parent, Vector3(0, y2, z2), Vector3(length * 0.72, 0.016, 0.05), _dark)


func _build_oneill() -> void:
	# B-48：委托给高精度 oneill_island3_hi。
	var om = OneillModel.new()
	om.habitat_label = habitat_label
	om.habitat_scale = 1.0
	om.station_type = station_type
	om.station_scale = station_scale
	om.module_count = module_count
	add_child(om)


func _build_stanford() -> void:
	# 环面：直径 1.8，轮辐+中央枢纽+对接端口+镜面/太阳翼
	_rotor = Node3D.new()
	_rotor.name = "TorusRotor"
	add_child(_rotor)
	var ring_r := 0.90
	var tube_r := 0.14
	var tm := TorusMesh.new()
	tm.inner_radius = ring_r - tube_r
	tm.outer_radius = ring_r + tube_r
	tm.rings = 48
	tm.ring_segments = 12
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = _hull
	_rotor.add_child(ring)
	# 窗带/陆地带：细环带
	_torus(_rotor, Vector3(0, 0.01, 0), Vector3.ZERO, ring_r - tube_r * 0.35, ring_r + tube_r * 0.35, _window)
	_torus(_rotor, Vector3(0, -0.01, 0), Vector3.ZERO, ring_r - tube_r * 0.85, ring_r - tube_r * 0.55, _land)
	# 轮辐 6 根
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var end := Vector3(cos(a) * ring_r, 0, sin(a) * ring_r)
		_cyl(_rotor, end * 0.5, end, 0.035, ring_r * 0.92, _dark, 8)
		_box(_rotor, end * 0.82, Vector3(0.07, 0.05, 0.07), _dark)
	# 中央枢纽/对接
	_cyl(self, Vector3.ZERO, Vector3.UP, 0.24, 0.60, _hull, 18)
	_torus(self, Vector3(0, -0.34, 0), Vector3.ZERO, 0.16, 0.25, _accent)
	_cyl(self, Vector3(0, -0.55, 0), Vector3.UP, 0.10, 0.28, _accent, 14)
	_torus(self, Vector3(0, -0.70, 0), Vector3.ZERO, 0.09, 0.13, _dark)
	_cyl(self, Vector3(0, 0.40, 0), Vector3.UP, 0.07, 0.25, _dark, 10)
	# 镜面/太阳翼
	_box(self, Vector3(0, 1.15, 0.25), Vector3(1.35, 0.018, 0.48), _radiator, Vector3(-0.38, 0, 0))
	_cyl(self, Vector3(0, 0.7, 0.10), Vector3(0, 0.5, 0.2), 0.025, 0.82, _dark, 6)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 1.35, 0.45, 0), Vector3(0.88, 0.018, 0.42), _solar)
		_cyl(self, Vector3(side * 0.85, 0.35, 0), Vector3(1, 0.15, 0), 0.022, 0.7, _dark, 6)
	# 外环对接/维护环
	_torus(self, Vector3.ZERO, Vector3.ZERO, ring_r + tube_r * 0.7, ring_r + tube_r * 1.15, _accent)


func _process(delta: float) -> void:
	var rate := rotation_speed * delta
	if _rotor_a != null:
		_rotor_a.rotation.x += rate
		_rotor_b.rotation.x -= rate
	if _rotor != null:
		_rotor.rotation.y += rate * 0.8
