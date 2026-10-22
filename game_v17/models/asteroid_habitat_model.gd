extends Node3D

# 方案B-38：A Baoa Qu 式小行星改造居住站（纯色、程序化、无贴图）。
# 双体小行星外壳 + 切面/中央塔/系泊塔/推进模块/散热鳍/太阳翼/对接口；
# 内部嵌入奥尼尔双圆柱或斯坦福环面（可见切面/窗带）。不复制高达资产/现实实体。

const OneillScene := preload("res://models/oneill_cylinder.tscn")
const StanfordScene := preload("res://models/stanford_torus.tscn")

@export_enum("asteroid_oneill", "asteroid_stanford", "asteroid_fortress") var asteroid_type := "asteroid_oneill"
@export var habitat_type := "oneill"
@export var habitat_label := "L5-07 SAVANNAH"
@export var habitat_scale := 1.0
@export var rotation_speed := 0.06
# 兼容 FacilityModelFactory 旧 probe 的模块字段（不用于外壳）
@export var station_type := "port"
@export var module_count := 4
@export var station_scale := 1.0

var _rock: StandardMaterial3D
var _rock_dark: StandardMaterial3D
var _hull: StandardMaterial3D
var _accent: StandardMaterial3D
var _window: StandardMaterial3D
var _radiator: StandardMaterial3D
var _solar: StandardMaterial3D
var _dark: StandardMaterial3D
var _inner: Node3D
var _shell: Node3D


func _ready() -> void:
	scale = Vector3.ONE * habitat_scale
	_build_materials()
	_shell = Node3D.new()
	add_child(_shell)
	_build_asteroid()
	_build_inner()
	_build_retrofit()


func _build_materials() -> void:
	_rock = _mat(Color(0.28, 0.27, 0.25), 1.0, 0.0)
	_rock_dark = _mat(Color(0.18, 0.18, 0.17), 1.0, 0.0)
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
	var big := asteroid_type == "asteroid_fortress"
	var lobe_scale := Vector3(1.10, 0.82, 0.76) * (1.25 if big else 1.0)
	# 双体小行星：盘状椭圆 + 锥状/较小椭球，中央切面开窗
	_sphere(_shell, Vector3(-0.86, 0.0, 0.02), 0.90, _rock, lobe_scale)
	_sphere(_shell, Vector3(0.82, 0.04, -0.06), 0.72, _rock_dark, Vector3(1.12, 0.68, 0.80))
	_sphere(_shell, Vector3(-0.22, 0.40, -0.30), 0.42, _rock, Vector3(0.62, 0.46, 0.48))
	_sphere(_shell, Vector3(0.34, -0.30, 0.36), 0.34, _rock_dark, Vector3(0.55, 0.40, 0.50))
	# 陨石坑（暗色扁球，确定性位置）
	for i in range(9):
		var a := TAU * float(i) / 9.0
		var p := Vector3(cos(a) * 0.94 - 0.80, sin(a) * 0.52, sin(a) * 0.30 + 0.10)
		_sphere(_shell, p, 0.10 + 0.03 * float(i % 3), _rock_dark, Vector3(1.0, 0.22, 1.0))
	# 双体接合结构：切面骨架 + 中央开口环
	for x in [-0.26, 0.20]:
		_torus(_shell, Vector3(x, 0.0, 0.0), Vector3(0, 0, PI * 0.5), 0.72, 0.82, _dark)
		_cyl(_shell, Vector3(x, 0.0, 0.0), Vector3.RIGHT, 0.035, 1.5, _accent, 8)
	for i in range(6):
		var a2 := TAU * float(i) / 6.0
		_cyl(_shell, Vector3(-0.03, cos(a2) * 0.72, sin(a2) * 0.72), Vector3.RIGHT, 0.022, 1.0, _hull, 6)
	# 中央塔基座/拖曳改造痕迹
	_cyl(_shell, Vector3(0.0, 0.95, 0.0), Vector3.UP, 0.12, 0.55, _hull, 12)
	# 切面内窗带与结构框
	_box(_shell, Vector3(0.0, 0.0, 0.62), Vector3(0.48, 0.05, 0.05), _window)
	_box(_shell, Vector3(0.0, 0.0, -0.62), Vector3(0.48, 0.05, 0.05), _window)


func _build_inner() -> void:
	_inner = Node3D.new()
	_inner.name = "InnerHabitat"
	add_child(_inner)
	var scene: PackedScene = OneillScene if habitat_type == "oneill" else StanfordScene
	var model = scene.instantiate()
	if model == null:
		return
	if habitat_type == "oneill":
		model.habitat_scale = 0.34
		model.position = Vector3(0.10, 0.0, 0.0)
	else:
		model.habitat_scale = 0.45
		model.position = Vector3(0.10, 0.0, 0.0)
	_inner.add_child(model)
	# 切面：把内部环/柱放到前侧开口，并加框梁/内圈（可见窗带）
	_inner.position = Vector3(0.0, 0.0, 0.78)
	_torus(_shell, Vector3(0.0, 0.0, 0.64), Vector3(PI * 0.5, 0.0, 0.0), 0.72, 0.84, _accent)
	_torus(_shell, Vector3(0.0, 0.0, 0.66), Vector3(PI * 0.5, 0.0, 0.0), 0.40, 0.46, _window)
	for i in range(4):
		var a3 := TAU * float(i) / 4.0
		_box(_shell, Vector3(cos(a3) * 0.78, sin(a3) * 0.78, 0.66), Vector3(0.12, 0.12, 0.10), _hull)
		_cyl(_shell, Vector3(cos(a3) * 0.82, sin(a3) * 0.82, 0.60), Vector3(0, 0, 1), 0.025, 0.32, _dark, 6)
	# 开口背后的暗色切口衬底，保证内部窗带可读
	_cyl(_shell, Vector3(0.0, 0.0, 0.50), Vector3(0, 0, 1), 0.70, 0.06, _dark, 24)


func _build_retrofit() -> void:
	# 推进模块/拖曳改造（尾部喷射簇）
	for y in [0.30, -0.30]:
		_cyl(_shell, Vector3(-1.65, y, 0.0), Vector3.RIGHT, 0.14, 0.38, _dark, 12)
		_cyl(_shell, Vector3(-1.88, y, 0.0), Vector3.RIGHT, 0.20, 0.10, _accent, 14)
	_box(_shell, Vector3(-1.55, 0.0, 0.0), Vector3(0.20, 0.80, 0.55), _hull)
	# 前部/侧面系泊塔与对接口
	_cyl(_shell, Vector3(1.38, 0.32, 0.0), Vector3.RIGHT, 0.18, 0.30, _hull, 12)
	_torus(_shell, Vector3(1.56, 0.32, 0.0), Vector3(0, 0, PI * 0.5), 0.12, 0.18, _accent)
	_cyl(_shell, Vector3(1.42, -0.30, 0.16), Vector3(0.4, 0.8, 0.3), 0.06, 0.32, _hull, 10)
	# 中央指挥塔/天线/散热鳍
	_cyl(_shell, Vector3(0.0, 1.26, 0.0), Vector3.UP, 0.10, 0.65, _hull, 12)
	_box(_shell, Vector3(0.0, 1.62, 0.0), Vector3(0.35, 0.20, 0.28), _hull)
	_cyl(_shell, Vector3(0.0, 1.86, 0.0), Vector3.UP, 0.02, 0.42, _dark, 6)
	_sphere(_shell, Vector3(0.0, 2.08, 0.0), 0.06, _accent)
	for z in [-1.0, 1.0]:
		_box(_shell, Vector3(-0.2, 0.22, z * 0.90), Vector3(0.62, 0.015, 0.46), _radiator, Vector3(0.0, 0.0, 0.12))
	# 太阳翼（静态）
	_box(_shell, Vector3(-0.55, 0.0, 1.35), Vector3(1.15, 0.015, 0.48), _solar)
	_box(_shell, Vector3(-0.55, 0.0, -1.35), Vector3(1.15, 0.015, 0.48), _solar)
	_cyl(_shell, Vector3(-0.55, 0.0, 1.1), Vector3(1, 0, 0), 0.03, 0.8, _dark, 6)
	_cyl(_shell, Vector3(-0.55, 0.0, -1.1), Vector3(1, 0, 0), 0.03, 0.8, _dark, 6)
	# 对接口/系泊
	for x2 in [-0.02, 0.30]:
		_torus(_shell, Vector3(x2, -0.94, 0.0), Vector3(0, 0, PI * 0.5), 0.08, 0.14, _accent)
		_cyl(_shell, Vector3(x2, -0.90, 0.0), Vector3.DOWN, 0.06, 0.22, _hull, 8)
	# 大型 UEG 站额外塔/防御
	if asteroid_type == "asteroid_fortress":
		for x3 in [-0.9, 0.9]:
			_cyl(_shell, Vector3(x3, 0.5, 0.0), Vector3.UP, 0.08, 0.75, _hull, 10)
			_cyl(_shell, Vector3(x3, 0.95, 0.0), Vector3.UP, 0.16, 0.18, _dark, 10)
		_cyl(_shell, Vector3(0.0, 0.6, 0.85), Vector3.FORWARD, 0.06, 0.8, _dark, 8)
		_cyl(_shell, Vector3(0.0, 0.6, -0.85), Vector3.BACK, 0.06, 0.8, _dark, 8)


func _process(delta: float) -> void:
	if _inner != null:
		_inner.rotation.y += rotation_speed * delta
	if _shell != null:
		_shell.rotation.y += rotation_speed * delta * 0.15
