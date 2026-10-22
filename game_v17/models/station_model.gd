extends Node3D

# 方案B-36：参考 ISS / 天宫 T 字构型的空间站程序化模型。
# 纯色基础材质，无贴图、无外部下载；不对应现实实体，仅过渡资产。
# 参数：station_type(depot/port/otc/tank/fuel/research), station_label, station_scale, module_count。
# 结构：核心舱/节点舱/径向实验舱/桁架/分段太阳翼/散热器/对接环/气闸/天线/推进舱。

@export_enum("depot", "port", "otc", "tank", "fuel", "research") var station_type := "port"
@export var station_label := "L1 PORT"
@export var station_scale := 1.0
@export var module_count := 4

var _hull: StandardMaterial3D
var _hull_dark: StandardMaterial3D
var _accent: StandardMaterial3D
var _solar: StandardMaterial3D
var _solar_b: StandardMaterial3D
var _radiator: StandardMaterial3D
var _amber: StandardMaterial3D
var _dark: StandardMaterial3D


func _ready() -> void:
	scale = Vector3.ONE * station_scale
	_build_materials()
	match station_type:
		"otc":
			_build_otc()
		"tank":
			_build_tank()
		"fuel":
			_build_fuel()
		"depot":
			_build_depot()
		"research":
			_build_research()
		_:
			_build_port()


func _build_materials() -> void:
	_hull = _mat(Color(0.43, 0.46, 0.46), 0.82, 0.03)
	_hull_dark = _mat(Color(0.30, 0.33, 0.33), 0.86, 0.02)
	_accent = _mat(Color(0.30, 0.50, 0.47), 0.72, 0.05)
	_solar = _mat(Color(0.075, 0.135, 0.18), 0.50, 0.22)
	_solar_b = _mat(Color(0.10, 0.17, 0.21), 0.55, 0.18)
	_radiator = _mat(Color(0.58, 0.60, 0.59), 0.78, 0.01)
	_amber = _mat(Color(0.62, 0.49, 0.27), 0.78, 0.02)
	_dark = _mat(Color(0.13, 0.15, 0.15), 0.9, 0.0)


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


func _cyl(pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, segments := 16) -> MeshInstance3D:
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
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi


func _torus(pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 28
	tm.ring_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi


func _sphere(pos: Vector3, radius: float, mat: StandardMaterial3D, hemisphere := false) -> MeshInstance3D:
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
	add_child(mi)
	return mi


func _module(pos: Vector3, dir: Vector3, radius: float, length: float, mat: StandardMaterial3D) -> void:
	_cyl(pos, dir, radius, length, mat, 18)
	_sphere(pos - dir.normalized() * length * 0.5, radius, mat)
	_sphere(pos + dir.normalized() * length * 0.5, radius, mat)


func _docking_port(pos: Vector3, dir: Vector3) -> void:
	var nd := dir.normalized()
	_cyl(pos, nd, 0.085, 0.16, _hull_dark, 14)
	_torus(pos + nd * 0.10, _rot_for_dir(nd), 0.075, 0.105, _accent)
	_sphere(pos + nd * 0.17, 0.075, _hull, true)


func _rot_for_dir(dir: Vector3) -> Vector3:
	# Torus default lies in XZ plane (normal Y)；把 normal 旋到 dir。
	var y := dir.normalized()
	return Vector3(asin(clampf(-y.z, -1.0, 1.0)), atan2(y.x, y.y), 0.0)


func _solar_wing(anchor: Vector3, axis: Vector3, panel_count: int, panel_len: float, width: float, mat: StandardMaterial3D, spread := 1.0) -> void:
	var dir := axis.normalized()
	var mast := anchor
	_cyl(mast, dir, 0.018, panel_len * float(panel_count) + 0.08, _hull_dark, 8)
	for side in [-1.0, 1.0]:
		for i in range(panel_count):
			var d := (float(i) + 0.7) * panel_len
			var p := anchor + dir * (float(side) * d) + Vector3(0, 0.018, 0)
			var sz := Vector3(panel_len * 0.88, 0.012, width)
			_box(p, sz, mat)
			_box(p + Vector3(0, 0.011, 0), Vector3(panel_len * 0.88, 0.006, width + 0.012), _hull_dark if i % 2 == 0 else _hull_dark)
			_box(p, Vector3(panel_len * 0.06, 0.018, width + 0.03), _hull_dark)


func _add_radiator(anchor: Vector3, size: Vector3, tilt := 0.0) -> void:
	_box(anchor, size, _radiator, Vector3(0, 0, tilt))
	# 细加强筋
	var n := maxi(2, int(size.x / 0.24))
	for i in range(n):
		var x := -size.x * 0.5 + size.x * (float(i) + 0.5) / float(n)
		_box(anchor + Vector3(x, 0.0, size.z * 0.5 + 0.012), Vector3(0.008, 0.015, 0.018), _hull_dark)


func _truss_x(length: float, width: float, y := 0.0, z := 0.0) -> void:
	var hw := width * 0.5
	for dy in [-hw, hw]:
		for dz in [-hw, hw]:
			_box(Vector3(0, y + dy, z + dz), Vector3(length, 0.035, 0.035), _hull_dark)
	var bays := maxi(3, int(length / 0.35))
	for i in range(bays + 1):
		var x := -length * 0.5 + length * float(i) / float(bays)
		_box(Vector3(x, y, z), Vector3(0.035, width, 0.035), _hull_dark)
		_box(Vector3(x, y, z), Vector3(0.035, 0.035, width), _hull_dark)
		if i < bays:
			# X 形斜撑（用细圆柱近似）
			var x2 := -length * 0.5 + length * float(i + 1) / float(bays)
			_cyl(Vector3((x + x2) * 0.5, y, z + hw), Vector3(1, 0, 0.15), 0.012, (x2 - x) * 1.05, _accent, 6)
			_cyl(Vector3((x + x2) * 0.5, y, z - hw), Vector3(1, 0, -0.15), 0.012, (x2 - x) * 1.05, _accent, 6)


func _core_and_node(core_len := 2.0, core_r := 0.16) -> void:
	_module(Vector3.ZERO, Vector3.RIGHT, core_r, core_len, _hull)
	_module(Vector3(core_len * 0.5 + 0.18, 0, 0), Vector3.RIGHT, core_r * 1.35, 0.42, _hull)
	# 节点舱径向端口
	_docking_port(Vector3(core_len * 0.5 + 0.18, -core_r * 1.6, 0), Vector3.DOWN)
	_docking_port(Vector3(core_len * 0.5 + 0.18, core_r * 1.6, 0), Vector3.UP)
	# 核心舱后对接
	_docking_port(Vector3(-core_len * 0.5 - 0.20, 0, 0), Vector3.LEFT)
	# 推进舱
	_cyl(Vector3(-core_len * 0.5 - 0.40, 0, 0), Vector3.RIGHT, core_r * 0.9, 0.34, _hull_dark)
	_sphere(Vector3(-core_len * 0.5 - 0.58, 0, 0), core_r * 0.9, _hull_dark, true)


func _lab_radial(anchor: Vector3, dir: Vector3, length := 1.1, radius := 0.135) -> void:
	_module(anchor + dir.normalized() * (length * 0.5 + 0.20), dir, radius, length, _hull)
	_docking_port(anchor + dir.normalized() * (length + 0.24), dir)


func _build_port() -> void:
	# T 字：核心舱 + 节点舱 + 径向实验舱 + 端部太阳翼 + 对接环
	_core_and_node(2.15, 0.17)
	_lab_radial(Vector3(1.25, 0, 0), Vector3.DOWN, 1.05, 0.145)
	_lab_radial(Vector3(1.25, 0, 0), Vector3.BACK, 0.88, 0.12)
	_cyl(Vector3(0, 0, 0), Vector3.FORWARD, 0.035, 1.3, _hull_dark, 8)
	_solar_wing(Vector3(-0.82, 0, 0), Vector3.BACK, 4, 0.34, 0.52, _solar, 1.0)
	_solar_wing(Vector3(0.82, 0, 0), Vector3.BACK, 4, 0.34, 0.52, _solar, 1.0)
	_truss_x(1.2, 0.30, 0.30, 0.0)
	_add_radiator(Vector3(0.0, 0.46, 0.38), Vector3(0.72, 0.012, 0.36))
	_cyl(Vector3(0, -0.30, 0.25), Vector3.DOWN, 0.07, 0.22, _accent, 12)
	_sphere(Vector3(0, -0.45, 0.25), 0.11, _accent, true)


func _build_research() -> void:
	_core_and_node(1.85, 0.15)
	_lab_radial(Vector3(1.08, 0, 0), Vector3.DOWN, 1.15, 0.145)
	# 暴露平台：框架 + 载荷盒
	var base := Vector3(0.1, -0.95, 0.45)
	for i in range(4):
		_box(base + Vector3(-0.3 + float(i) * 0.2, 0, 0), Vector3(0.03, 0.03, 0.55), _hull_dark)
	for j in range(3):
		_box(base + Vector3(0, 0, -0.22 + float(j) * 0.22), Vector3(0.62, 0.03, 0.03), _hull_dark)
	_box(base + Vector3(-0.12, 0.05, 0), Vector3(0.12, 0.14, 0.12), _accent)
	_box(base + Vector3(0.14, 0.04, 0.1), Vector3(0.1, 0.10, 0.10), _amber)
	_solar_wing(Vector3(-0.75, 0, 0), Vector3.BACK, 3, 0.32, 0.42, _solar)
	_solar_wing(Vector3(0.0, 0.0, -0.65), Vector3.BACK, 2, 0.30, 0.38, _solar_b)
	_add_radiator(Vector3(-0.1, 0.35, -0.32), Vector3(0.52, 0.012, 0.28), 0.18)
	_cyl(Vector3(-1.2, 0, 0), Vector3.RIGHT, 0.055, 0.26, _hull_dark, 10)


func _build_depot() -> void:
	_core_and_node(1.55, 0.17)
	_truss_x(2.5, 0.44, 0.05, 0.0)
	for i in range(maxi(2, module_count)):
		var x := -0.85 + 1.7 * float(i) / float(maxi(1, module_count - 1))
		_cyl(Vector3(x, 0.36, 0.30), Vector3.RIGHT, 0.15, 0.44, _hull_dark, 12)
		_sphere(Vector3(x - 0.22, 0.36, 0.30), 0.15, _hull_dark, true)
		_sphere(Vector3(x + 0.22, 0.36, 0.30), 0.15, _hull_dark, true)
		_box(Vector3(x, 0.36, 0.30), Vector3(0.18, 0.04, 0.18), _amber)
	_solar_wing(Vector3(-1.15, 0.05, 0), Vector3.BACK, 4, 0.36, 0.58, _solar)
	_add_radiator(Vector3(0.75, -0.25, 0.42), Vector3(0.62, 0.012, 0.32), -0.12)
	_docking_port(Vector3(1.1, 0.05, 0), Vector3.RIGHT)
	_cyl(Vector3(0.2, -0.32, -0.25), Vector3.FORWARD, 0.04, 0.9, _hull_dark, 8)


func _build_tank() -> void:
	# 桁架基座 + 多圆柱储罐 + 加注管
	_truss_x(2.0, 0.50, 0.0, 0.0)
	for i in range(3):
		var x := -0.62 + 0.62 * float(i)
		var z := -0.38 if i % 2 == 0 else 0.38
		_module(Vector3(x, 0.2, z), Vector3.UP, 0.18, 0.78, _hull)
		_torus(Vector3(x, 0.6, z), Vector3.ZERO, 0.16, 0.195, _amber)
		_box(Vector3(x, 0.0, z), Vector3(0.10, 0.16, 0.10), _hull_dark)
		_cyl(Vector3(x, 0.0, z), Vector3.UP, 0.045, 0.30, _accent, 8)
	_cyl(Vector3(0.0, 0.18, 0), Vector3.RIGHT, 0.045, 1.7, _hull_dark, 8)
	_cyl(Vector3(0.0, 0.04, 0), Vector3.RIGHT, 0.035, 1.4, _amber, 8)
	_solar_wing(Vector3(-1.1, 0.32, 0), Vector3.BACK, 2, 0.28, 0.40, _solar_b)
	_docking_port(Vector3(1.22, 0.0, 0), Vector3.RIGHT)


func _build_fuel() -> void:
	# 储罐 + 加注臂 + 小核心 + 太阳翼
	_build_tank()
	# 加注臂：两段圆柱 + 喷嘴 + 软管
	_cyl(Vector3(1.45, 0.35, 0.45), Vector3(1, 0.3, 0.2), 0.045, 0.85, _hull, 10)
	_cyl(Vector3(1.85, 0.55, 0.65), Vector3(0.5, 0.4, 0.6), 0.04, 0.62, _hull_dark, 10)
	_cyl(Vector3(2.05, 0.70, 0.82), Vector3(0.2, 0.4, 1.0), 0.06, 0.20, _amber, 12)
	_box(Vector3(1.62, 0.48, 0.55), Vector3(0.10, 0.10, 0.10), _accent)
	_cyl(Vector3(0.9, 0.05, 0.28), Vector3.RIGHT, 0.025, 0.70, _amber, 6)
	_docking_port(Vector3(2.18, 0.74, 0.92), Vector3(0.2, 0.4, 1.0))
	_docking_port(Vector3(-1.25, 0.0, 0), Vector3.LEFT)


func _build_otc() -> void:
	# 天线阵 + 转台 + 核心舱（无大桁架）
	_module(Vector3(0, -0.15, 0), Vector3.UP, 0.13, 0.55, _hull)
	_cyl(Vector3(0, 0.18, 0), Vector3.UP, 0.10, 0.35, _hull_dark, 12)
	_torus(Vector3(0, 0.22, 0), Vector3.ZERO, 0.20, 0.30, _accent)
	_sphere(Vector3(0, 0.55, 0), 0.32, _hull, true)
	_sphere(Vector3(0, 0.50, 0), 0.17, _accent, true)
	# 相控阵天线板
	for i in range(3):
		_box(Vector3(-0.42 + 0.42 * float(i), 0.12, 0.30), Vector3(0.24, 0.32, 0.025), _solar)
	_box(Vector3(0, 0.80, 0.05), Vector3(0.04, 0.30, 0.04), _hull_dark)
	_sphere(Vector3(0, 0.98, 0.05), 0.07, _amber)
	_solar_wing(Vector3(-0.7, -0.18, 0), Vector3.BACK, 3, 0.30, 0.46, _solar)
	_solar_wing(Vector3(0.7, -0.18, 0), Vector3.BACK, 3, 0.30, 0.46, _solar)
	_docking_port(Vector3(0, -0.70, 0), Vector3.DOWN)
	_add_radiator(Vector3(0, -0.22, 0.42), Vector3(0.38, 0.012, 0.24))
