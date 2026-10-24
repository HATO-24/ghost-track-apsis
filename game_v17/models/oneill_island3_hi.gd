extends Node3D

# 方案B-48：O'Neill Island Three 高精度单圆柱外景（30×7.5 km，4:1）。
# 128 周向段 × 48 轴向段外壳；3 采光窗带/3 外壳带/分板线/加强环/检修口；
# 窗内陆地/水面/云层；一端端盖环伸出 3 片长反射板；双端不同端盖。
# 纯色/半透明材质，无贴图；不接物理。

@export var habitat_label := "L5-07 SAVANNAH"
@export var habitat_scale := 1.0
@export var station_type := "port"
@export var station_scale := 1.0
@export var module_count := 4

const LENGTH := 4.4
const RADIUS := 0.55
const SEGS := 128
const RINGS := 48
const WIN_CENTERS := [0.0, 120.0, 240.0]
const WIN_HALF_DEG := 17.0

# ── 结构审计标记（task-232）────────────────────────────────────────────
# 只写 name/group/meta，不改几何/材质/位置；供 tests/model_structure_probe.gd 读取。
# role 命名与容忍规则见 docs/model_audit.md；新增外部件必须带 audit_role。
const AUDIT_SCHEMA := 1
var _audit_seq := 0

var _hull: StandardMaterial3D
var _hull_dark: StandardMaterial3D
var _panel: StandardMaterial3D
var _dark: StandardMaterial3D
var _glass: StandardMaterial3D
var _frame: StandardMaterial3D
var _mirror: StandardMaterial3D
var _radiator: StandardMaterial3D
var _solar: StandardMaterial3D
var _accent: StandardMaterial3D
var _land_green: StandardMaterial3D
var _land_brown: StandardMaterial3D
var _land_gray: StandardMaterial3D
var _water: StandardMaterial3D
var _cloud: StandardMaterial3D
var _tree: StandardMaterial3D


func _ready() -> void:
	scale = Vector3.ONE * habitat_scale
	_stamp_audit_contract()
	_build_materials()
	_build_hull()
	_build_windows()
	_build_interior()
	_build_panel_details()
	_build_reflectors()
	_build_endcaps()
	_build_outboard()


func _stamp_audit_contract() -> void:
	# 审计契约：probe 只读这些 meta，不把模型尺寸复制进测试。
	set_meta("audit_schema", AUDIT_SCHEMA)
	set_meta("audit_length", LENGTH)
	set_meta("audit_radius", RADIUS)
	set_meta("audit_window_centers_deg", WIN_CENTERS)
	set_meta("audit_window_half_deg", WIN_HALF_DEG)
	set_meta("audit_reflector_count", 3)
	set_meta("audit_reflector_azimuths_deg", [60.0, 180.0, 300.0])
	set_meta("audit_reflector_open_deg", 25.0)
	set_meta("audit_reflector_root_standoff", 0.30)
	set_meta("audit_reflector_len_factor", 1.06)
	set_meta("audit_reflector_width", 0.62)


func _attach(mi: MeshInstance3D, role: String, side := 0, index := -1) -> MeshInstance3D:
	# 统一标记：唯一 name + group + meta；_audit_seq 保证同级节点名唯一。
	_audit_seq += 1
	var nm := role
	if index >= 0:
		nm += "_%d" % index
	mi.name = "%s_%03d" % [nm, _audit_seq]
	add_child(mi)
	mi.add_to_group("audit_" + role)
	mi.set_meta("audit_schema", AUDIT_SCHEMA)
	mi.set_meta("audit_role", role)
	mi.set_meta("audit_side", side)
	mi.set_meta("audit_index", index)
	return mi


func _mat(c: Color, rough := 0.82, metallic := 0.02) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _trans(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.35
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_materials() -> void:
	_hull = _mat(Color(0.62, 0.65, 0.64), 0.78, 0.02)
	_hull_dark = _mat(Color(0.34, 0.36, 0.35), 0.88, 0.04)
	_panel = _mat(Color(0.52, 0.54, 0.53), 0.84, 0.02)
	_dark = _mat(Color(0.13, 0.15, 0.15), 0.92, 0.03)
	_glass = _trans(Color(0.03, 0.07, 0.10, 0.30))
	_frame = _mat(Color(0.44, 0.47, 0.45), 0.7, 0.12)
	_mirror = _mat(Color(0.64, 0.69, 0.68), 0.26, 0.16)
	_mirror.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mirror.emission_enabled = true
	_mirror.emission = Color(0.26, 0.31, 0.30)
	_mirror.emission_energy_multiplier = 0.28
	_radiator = _mat(Color(0.57, 0.59, 0.58), 0.72, 0.01)
	_solar = _mat(Color(0.08, 0.15, 0.20), 0.52, 0.22)
	_accent = _mat(Color(0.30, 0.49, 0.45), 0.72, 0.05)
	_land_green = _mat(Color(0.20, 0.32, 0.16), 0.98, 0.0)
	_land_brown = _mat(Color(0.31, 0.25, 0.16), 1.0, 0.0)
	_land_gray = _mat(Color(0.24, 0.25, 0.23), 1.0, 0.0)
	_water = _mat(Color(0.07, 0.21, 0.30), 0.40, 0.04)
	_cloud = _trans(Color(0.76, 0.81, 0.80, 0.30))
	_cloud.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tree = _mat(Color(0.16, 0.29, 0.17), 1.0, 0.0)


func _orient_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _cyl(pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg := 16, role := "misc", side := 0, index := -1) -> void:
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
	_attach(mi, role, side, index)


func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO, role := "misc", side := 0, index := -1) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	_attach(mi, role, side, index)


func _torus(pos: Vector3, rot: Vector3, inner: float, outer: float, mat: StandardMaterial3D, role := "misc", side := 0, index := -1) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 64
	tm.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	_attach(mi, role, side, index)


func _sphere(pos: Vector3, radius: float, mat: StandardMaterial3D, scl := Vector3.ONE, role := "misc", side := 0, index := -1) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	_attach(mi, role, side, index)


func _in_window(angle: float) -> bool:
	var a := fposmod(rad_to_deg(angle), 360.0)
	for c in WIN_CENTERS:
		var d := absf(fposmod(a - float(c) + 180.0, 360.0) - 180.0)
		if d < WIN_HALF_DEG:
			return true
	return false


func _build_hull() -> void:
	# 128×48 外壳网格；跳过 3 个采光窗扇区
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGS):
		var a0 := TAU * float(i) / float(SEGS)
		var a1 := TAU * float(i + 1) / float(SEGS)
		if _in_window((a0 + a1) * 0.5):
			continue
		for j in range(RINGS):
			var x0 := -LENGTH * 0.5 + LENGTH * float(j) / float(RINGS)
			var x1 := -LENGTH * 0.5 + LENGTH * float(j + 1) / float(RINGS)
			var p00 := Vector3(x0, cos(a0) * RADIUS, sin(a0) * RADIUS)
			var p01 := Vector3(x0, cos(a1) * RADIUS, sin(a1) * RADIUS)
			var p10 := Vector3(x1, cos(a0) * RADIUS, sin(a0) * RADIUS)
			var p11 := Vector3(x1, cos(a1) * RADIUS, sin(a1) * RADIUS)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _hull
	_attach(mi, "hull_shell")


func _band(center_deg: float, width_deg: float, radius: float, mat: StandardMaterial3D, rows := 16, cols := 20, role := "misc", index := -1, x0 := -LENGTH * 0.5, x1 := LENGTH * 0.5) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cx := deg_to_rad(center_deg)
	var half := deg_to_rad(width_deg) * 0.5
	for j in range(rows):
		var za := x0 + (x1 - x0) * float(j) / float(rows)
		var zb := x0 + (x1 - x0) * float(j + 1) / float(rows)
		for i in range(cols):
			var a0 := cx - half + 2.0 * half * float(i) / float(cols)
			var a1 := cx - half + 2.0 * half * float(i + 1) / float(cols)
			var p00 := Vector3(za, cos(a0) * radius, sin(a0) * radius)
			var p01 := Vector3(za, cos(a1) * radius, sin(a1) * radius)
			var p10 := Vector3(zb, cos(a0) * radius, sin(a0) * radius)
			var p11 := Vector3(zb, cos(a1) * radius, sin(a1) * radius)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_attach(mi, role, 0, index)


func _rib(x: float, center_deg: float, width_deg: float, radius: float, thickness: float, mat: StandardMaterial3D, role := "misc", index := -1) -> void:
	_band(center_deg, width_deg, radius, mat, 1, 16, role, index, x - thickness, x + thickness)


func _build_windows() -> void:
	for idx in range(WIN_CENTERS.size()):
		var cc := float(WIN_CENTERS[idx])
		# 凹框/暗色内唇 + 玻璃
		_band(cc, WIN_HALF_DEG * 2.0 + 5.0, RADIUS * 0.982, _dark, 18, 18, "window_frame", idx)
		_band(cc, WIN_HALF_DEG * 2.0, RADIUS * 1.004, _glass, 18, 22, "window_glass", idx)
		# 边梁
		for s in [-1.0, 1.0]:
			var aa := deg_to_rad(cc + s * WIN_HALF_DEG)
			_box(Vector3(0, cos(aa) * RADIUS * 1.018, sin(aa) * RADIUS * 1.018), Vector3(LENGTH, 0.032, 0.045), _frame, Vector3.ZERO, "window_frame", 0, idx)
		# 横向肋
		for k in range(9):
			var x := -LENGTH * 0.5 + LENGTH * (float(k) + 0.5) / 9.0
			_rib(x, cc, WIN_HALF_DEG * 2.0, RADIUS * 1.014, 0.018, _frame, "window_frame", idx)


func _build_interior() -> void:
	# 窗内内容：3 条陆地/水面/云；只在窗内可见，不外露（interior_* 允许位于壳体内部）
	var bands := [[0.0, _land_green], [120.0, _land_brown], [240.0, _land_gray]]
	for idx in range(bands.size()):
		var pair: Array = bands[idx]
		var cc := float(pair[0])
		_band(cc, WIN_HALF_DEG * 2.0, RADIUS * 0.72, pair[1], 14, 16, "interior_terrain", idx)
		# 水面/河流
		_band(cc + 5.0, WIN_HALF_DEG * 1.1, RADIUS * 0.715, _water, 10, 8, "interior_water", idx, -LENGTH * 0.35, LENGTH * 0.35)
		# 低模树/丘陵
		for k in range(10):
			var z := -LENGTH * 0.42 + LENGTH * 0.084 * float(k)
			var a2 := deg_to_rad(cc + (-10.0 + 20.0 * float((k * 31) % 100) / 100.0))
			var p := Vector3(z, cos(a2) * RADIUS * 0.70, sin(a2) * RADIUS * 0.70)
			if k % 3 == 0:
				_sphere(p, 0.018, _tree, Vector3(0.8, 1.0, 0.8), "interior_terrain", 0, idx)
			else:
				_sphere(p, 0.012, _land_brown if cc == 120.0 else _tree, Vector3(1.5, 0.4, 0.7), "interior_terrain", 0, idx)
	# 云层/薄雾（半透明，窗内）
	for i in range(9):
		var cc2 := float(WIN_CENTERS[i % 3])
		var a3 := deg_to_rad(cc2 + (-12.0 + 24.0 * float((i * 17) % 100) / 100.0))
		_sphere(Vector3(-LENGTH * 0.35 + LENGTH * 0.7 * float((i * 23) % 100) / 100.0, cos(a3) * RADIUS * 0.68, sin(a3) * RADIUS * 0.68), 0.05, _cloud, Vector3(2.0, 0.20, 0.55), "interior_clouds")


func _build_panel_details() -> void:
	# 加强环（环向）+ 纵向梁 + 分板线 + 检修口（hull_detail 为壳体表面件）
	for k in range(1, 12):
		var x := -LENGTH * 0.5 + LENGTH * float(k) / 12.0
		_torus(Vector3(x, 0, 0), Vector3(0, 0, PI * 0.5), RADIUS * 0.995, RADIUS * 1.016, _frame, "hull_ring")
	for a in [30.0, 90.0, 150.0, 210.0, 270.0, 330.0]:
		var aa := deg_to_rad(a)
		_box(Vector3(0, cos(aa) * RADIUS * 1.006, sin(aa) * RADIUS * 1.006), Vector3(LENGTH, 0.012, 0.012), _frame, Vector3.ZERO, "hull_stringer")
		# 分段板线（沿轴短缝）
		for k2 in range(1, 11):
			var x2 := -LENGTH * 0.5 + LENGTH * float(k2) / 11.0
			_box(Vector3(x2, cos(aa) * RADIUS * 1.008, sin(aa) * RADIUS * 1.008), Vector3(0.018, 0.008, 0.035), _dark, Vector3.ZERO, "hull_seam")
	# 检修口
	for i in range(6):
		var a4 := deg_to_rad(35.0 + 45.0 * float(i % 4))
		var x4 := -LENGTH * 0.30 + LENGTH * 0.12 * float(i)
		var p4 := Vector3(x4, cos(a4) * RADIUS * 1.008, sin(a4) * RADIUS * 1.008)
		_box(p4, Vector3(0.10, 0.02, 0.12), _hull_dark, Vector3.ZERO, "hull_hatch")
		_box(p4 + Vector3(0, 0.012, 0), Vector3(0.06, 0.012, 0.08), _accent, Vector3.ZERO, "hull_hatch")
	# 外壳分板：3 条外壳带内浅色 panel 线
	for a5 in [60.0, 180.0, 300.0]:
		var ar := deg_to_rad(a5)
		for s in [-1.0, 1.0]:
			var aa5: float = ar + float(s) * 0.10
			_box(Vector3(0, cos(aa5) * RADIUS * 1.01, sin(aa5) * RADIUS * 1.01), Vector3(LENGTH, 0.010, 0.010), _panel, Vector3.ZERO, "hull_panel_line")


func _strut(a: Vector3, b: Vector3, radius: float, mat: StandardMaterial3D, role := "misc", side := 0, index := -1) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	_cyl((a + b) * 0.5, d.normalized(), radius, d.length(), mat, 8, role, side, index)


func _build_reflectors() -> void:
	# 3 片长反射板：+X 端盖环伸出，向 -X；张开角25°；镜面前层、结构背面
	var panel_len := LENGTH * 1.06
	var open_rad := deg_to_rad(25.0)
	var root_x := LENGTH * 0.5 + 0.30
	var root_r := RADIUS * 1.08
	var tip_x := root_x - panel_len * cos(open_rad)
	var tip_r := root_r + panel_len * sin(open_rad)
	for i in range(3):
		var ang := TAU * (float(i) / 3.0 + 1.0 / 6.0)
		var radial := Vector3(0, cos(ang), sin(ang)).normalized()
		var tangent := Vector3(0, -sin(ang), cos(ang)).normalized()
		var root := Vector3(root_x, radial.y * root_r, radial.z * root_r)
		var tip := Vector3(tip_x, radial.y * tip_r, radial.z * tip_r)
		var axis_x := (tip - root).normalized()
		var axis_z := tangent
		var axis_y := axis_z.cross(axis_x).normalized()
		var back := -axis_y * 0.052
		var basis := Basis(axis_x, axis_y, axis_z)
		var length := (tip - root).length()
		var width := 0.62
		# 镜面前层（3段），无正面框架
		var seg_n := 3
		for k in range(seg_n):
			var t0 := float(k) / float(seg_n)
			var t1 := float(k + 1) / float(seg_n)
			var c := root.lerp(tip, (t0 + t1) * 0.5)
			var seg_len := length / float(seg_n) * 0.96
			var panel := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(seg_len, 0.018, width)
			panel.mesh = bm; panel.transform = Transform3D(basis, c); panel.material_override = _mirror
			_attach(panel, "reflector_panel", 0, i)
			# 背面框（随板走，低于镜面）
			var cb := c + back
			_box_basis(cb, Vector3(seg_len * 0.94, 0.010, width * 0.74), _frame, basis, "reflector_frame", 0, i)
			for sz in [-1.0, 1.0]:
				_box_basis(cb + tangent * (width * 0.40 * float(sz)), Vector3(seg_len * 0.94, 0.008, 0.020), _frame, basis, "reflector_rail", 0, i)
			# 背面横肋
			var cr := cb - axis_x * (seg_len * 0.42)
			_box_basis(cr, Vector3(0.020, 0.010, width * 0.98), _frame, basis, "reflector_rib", 0, i)
		# 根部横梁/扭力管：跨板宽，位于背面
		var root_back := root + back
		_cyl(root_back, tangent, 0.040, width * 1.02, _frame, 12, "reflector_hinge", 0, i)
		_box_basis(root_back, Vector3(0.08, 0.035, width * 1.04), _hull_dark, basis, "reflector_hinge", 0, i)
		# 端盖环双铰座/耳片/轴承壳；两个铰点位于板根横梁两端
		var x_ring: float = LENGTH * 0.5 + 0.02
		for sz2 in [-1.0, 1.0]:
			var edge_off := width * 0.50 * float(sz2)
			var hinge_root := root_back + tangent * edge_off
			var ring_pt := Vector3(x_ring, radial.y * root_r, radial.z * root_r) + tangent * (edge_off * 0.92)
			# 端盖环耳片/铰座
			_box_basis((ring_pt + hinge_root) * 0.5, Vector3(0.20, 0.14, 0.055), _hull_dark, basis, "reflector_hinge", 0, i)
			_box_basis(ring_pt + back * 0.4, Vector3(0.12, 0.20, 0.09), _frame, basis, "reflector_hinge", 0, i)
			# 轴承壳/转轴（轴向沿切向）
			_cyl(hinge_root, tangent, 0.075, 0.16, _hull_dark, 10, "reflector_hinge", 0, i)
			_cyl(hinge_root, tangent, 0.045, 0.20, _accent, 10, "reflector_hinge", 0, i)
			# 限位块
			_box_basis(hinge_root + back * 0.5 + axis_x * 0.08, Vector3(0.08, 0.05, 0.07), _frame, basis, "reflector_hinge", 0, i)
		# A 字背撑：主杆/背面锚点；端盖环连接杆走板轮廓外 |u|>0.31，再绕到背锚点
		var attach_a := root.lerp(tip, 0.15) + back * 2.2
		for sz3 in [-1.0, 1.0]:
			var anchor_a := root + back * 1.2 + tangent * (width * 0.34 * float(sz3))
			var out_a := root + back * 1.2 + tangent * (width * 0.50 + 0.08) * float(sz3)
			var ring_a := Vector3(x_ring, radial.y * root_r, radial.z * root_r) + tangent * (width * 0.50 + 0.08) * float(sz3)
			_strut(anchor_a, attach_a, 0.032, _accent, "reflector_strut", 0, i)
			_strut(out_a, anchor_a, 0.024, _hull_dark, "reflector_strut", 0, i)
			_strut(ring_a, out_a, 0.024, _hull_dark, "endcap_mount", 1, i)
			_box_basis(anchor_a, Vector3(0.08, 0.07, 0.07), _hull_dark, basis, "reflector_strut", 0, i)
			_box_basis(out_a, Vector3(0.06, 0.06, 0.06), _hull_dark, basis, "reflector_strut", 0, i)
		# 两根线性作动器：主杆/背面锚点；连接杆同样从板轮廓外绕入
		var attach_b := root.lerp(tip, 0.25) + back * 2.0
		for sz4 in [-1.0, 1.0]:
			var anchor_b := root + back * 1.1 + tangent * (width * 0.22 * float(sz4))
			var out_b := root + back * 1.1 + tangent * (width * 0.50 + 0.06) * float(sz4)
			var ring_b := Vector3(x_ring, radial.y * root_r, radial.z * root_r) + tangent * (width * 0.50 + 0.06) * float(sz4)
			var mid_act := (anchor_b + attach_b) * 0.5
			_strut(anchor_b, attach_b, 0.030, _dark, "reflector_actuator", 0, i)
			_strut(out_b, anchor_b, 0.020, _hull_dark, "reflector_strut", 0, i)
			_strut(ring_b, out_b, 0.020, _hull_dark, "endcap_mount", 1, i)
			_cyl(mid_act, (attach_b - anchor_b).normalized(), 0.046, 0.18, _accent, 10, "reflector_actuator", 0, i)
			_box_basis(anchor_b, Vector3(0.08, 0.06, 0.07), _hull_dark, basis, "reflector_actuator", 0, i)
			_box_basis(attach_b + tangent * 0.02, Vector3(0.07, 0.05, 0.07), _accent, basis, "reflector_actuator", 0, i)
		# 根部限位/止挡
		_box_basis(root_back + axis_x * 0.12 + back * 0.4, Vector3(0.10, 0.06, width * 0.86), _hull_dark, basis, "reflector_hinge", 0, i)


func _build_endcaps() -> void:
	for side in [-1.0, 1.0]:
		var side_i := int(side)
		var x: float = side * (LENGTH * 0.5 + 0.02)
		# 大圆盘 + 暗色环
		_cyl(Vector3(x, 0, 0), Vector3.RIGHT, RADIUS * 1.05, 0.10, _hull_dark, 64, "endcap", side_i)
		_cyl(Vector3(x, 0, 0), Vector3.RIGHT, RADIUS * 0.92, 0.16, _dark, 64, "endcap", side_i)
		_torus(Vector3(x, 0, 0), Vector3(0, 0, PI * 0.5), RADIUS * 0.86, RADIUS * 1.07, _frame, "endcap", side_i)
		_torus(Vector3(x, 0, 0), Vector3(0, 0, PI * 0.5), RADIUS * 0.34, RADIUS * 0.46, _accent, "endcap", side_i)
		# 放射肋
		for i in range(12):
			var a := TAU * float(i) / 12.0
			var rpos := Vector3(x + side * 0.10, cos(a) * RADIUS * 0.58, sin(a) * RADIUS * 0.58)
			_box(rpos, Vector3(0.045, RADIUS * 0.55, 0.028), _frame, Vector3(a, 0, 0), "endcap", side_i)
		# 中央枢纽/对接轴
		_cyl(Vector3(x + side * 0.12, 0, 0), Vector3.RIGHT, RADIUS * 0.26, 0.30, _hull, 24, "endcap", side_i)
		_cyl(Vector3(x + side * 0.18, 0, 0), Vector3.RIGHT, RADIUS * 0.16, 0.22, _dark, 20, "endcap", side_i)
		_torus(Vector3(x + side * 0.18, 0, 0), Vector3(0, 0, PI * 0.5), RADIUS * 0.19, RADIUS * 0.28, _accent, "endcap", side_i)
		_sphere(Vector3(x + side * 0.26, 0, 0), 0.035, _accent, Vector3.ONE, "endcap", side_i)
		# 对接口/端口环：两端不同（+X 仅反射板安装件；-X 才有港口）
		if side > 0:
			# +X：反射板环/转轴支撑
			for i in range(3):
				var a2 := TAU * float(i) / 3.0
				var hpos := Vector3(x, cos(a2) * RADIUS * 0.72, sin(a2) * RADIUS * 0.72)
				_torus(hpos, Vector3(0, 0, 0), 0.045, 0.075, _frame, "endcap_mount", side_i)
				_box(hpos, Vector3(0.04, 0.14, 0.04), _frame, Vector3.ZERO, "endcap_mount", side_i)
		else:
			# -X：港口环/多个对接口
			for i in range(6):
				var a3 := TAU * float(i) / 6.0
				var dpos := Vector3(x + side * 0.12, cos(a3) * RADIUS * 0.62, sin(a3) * RADIUS * 0.62)
				_cyl(dpos, Vector3.RIGHT, 0.055, 0.14, _hull, 12, "dock_port", side_i, i)
				_torus(dpos + Vector3(-0.08, 0, 0), Vector3(0, 0, PI * 0.5), 0.035, 0.055, _accent, "dock_port", side_i, i)


func _box_basis(pos: Vector3, size: Vector3, mat: StandardMaterial3D, basis: Basis, role := "misc", side := 0, index := -1) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.transform = Transform3D(basis, pos)
	mi.material_override = mat
	_attach(mi, role, side, index)


func _build_outboard() -> void:
	# B-49：散热鳍=两端端盖环各4组；太阳能/系泊/交通艇全部集中 -X 端
	# 1) 两端端盖环外侧放射状散热鳍（避开窗带角度 0/120/240）
	for side in [-1.0, 1.0]:
		var side_i := int(side)
		var x: float = float(side) * (LENGTH * 0.5 + (0.55 if side > 0 else 0.16))
		for i in range(4):
			var ang := deg_to_rad(45.0 + 90.0 * float(i))
			var radial := Vector3(0, cos(ang), sin(ang)).normalized()
			var tangent := Vector3(0, -sin(ang), cos(ang)).normalized()
			var base := Vector3(x, radial.y * RADIUS * 1.04, radial.z * RADIUS * 1.04)
			var fin_center := Vector3(x + float(side) * 0.06, radial.y * RADIUS * 1.58, radial.z * RADIUS * 1.58)
			var basis := Basis(Vector3.RIGHT, radial, tangent)
			_box_basis(fin_center, Vector3(0.26, 0.52, 0.018), _radiator, basis, "radiator", side_i, i)
			_box_basis(fin_center, Vector3(0.28, 0.54, 0.006), _frame, basis, "radiator", side_i, i)
			# 根部支臂
			_cyl(base + radial * 0.34, radial, 0.028, 0.52, _dark, 8, "radiator", side_i, i)
			_torus(base, Vector3(0, 0, PI * 0.5), 0.045, 0.075, _accent, "radiator", side_i, i)
	# 2) 太阳能阵列：仅 -X 端，4 象限展开
	var x_solar: float = -LENGTH * 0.5 - 0.85
	for i in range(4):
		var ang2 := deg_to_rad(22.5 + 90.0 * float(i))
		var rad2 := Vector3(0, cos(ang2), sin(ang2)).normalized()
		var tan2 := Vector3(0, -sin(ang2), cos(ang2)).normalized()
		var root2 := Vector3(x_solar, rad2.y * RADIUS * 1.15, rad2.z * RADIUS * 1.15)
		var center2 := Vector3(x_solar - 0.30, rad2.y * RADIUS * 1.78, rad2.z * RADIUS * 1.78)
		var basis2 := Basis(rad2, Vector3.LEFT, rad2.cross(Vector3.LEFT).normalized())
		_box_basis(center2, Vector3(0.68, 0.015, 0.34), _solar, basis2, "solar", -1, i)
		_box_basis(center2, Vector3(0.70, 0.006, 0.36), _frame, basis2, "solar", -1, i)
		_cyl(root2, rad2, 0.020, 0.78, _dark, 6, "solar", -1, i)
		_torus(root2, Vector3(0, 0, PI * 0.5), 0.055, 0.085, _frame, "solar", -1, i)
		_cyl(root2 + rad2 * 0.22, Vector3.LEFT, 0.018, 0.42, _dark, 6, "solar", -1, i)
	# 3) 系泊塔/泊位：-X 端盖环，5 个均布、朝轴向外侧
	# 系泊塔角度 0/72/144/216/288，根部在 -X 端盖环外缘
	var x_moor: float = -LENGTH * 0.5 - 0.42
	for i in range(5):
		var ang3 := TAU * float(i) / 5.0
		var rad3 := Vector3(0, cos(ang3), sin(ang3)).normalized()
		var base3 := Vector3(x_moor, rad3.y * RADIUS * 0.98, rad3.z * RADIUS * 0.98)
		var tip3 := base3 + Vector3(-0.30, rad3.y * 0.10, rad3.z * 0.10)
		# 端盖环 → 外侧系泊根部（完全在端盖外侧）
		_cyl(Vector3(-LENGTH * 0.5 - 0.26, rad3.y * RADIUS * 0.98, rad3.z * RADIUS * 0.98), Vector3.LEFT, 0.024, 0.32, _hull_dark, 8, "endcap_mount", -1, i)
		_cyl((base3 + tip3) * 0.5, tip3 - base3, 0.030, (tip3 - base3).length(), _hull, 8, "mooring", -1, i)
		_torus(tip3, Vector3(0, 0, PI * 0.5), 0.055, 0.095, _accent, "mooring", -1, i)
		_box(Vector3(x_moor + 0.02, rad3.y * RADIUS * 1.04, rad3.z * RADIUS * 1.04), Vector3(0.10, 0.08, 0.10), _hull_dark, Vector3.ZERO, "mooring", -1, i)
	# 4) 交通艇接口/机库口：-X 中央枢纽附近，5 个朝外小对接口
	var x_port: float = -LENGTH * 0.5 - 0.28
	for i in range(5):
		var ang4 := TAU * float(i) / 5.0 + 0.25
		var rad4 := Vector3(0, cos(ang4), sin(ang4)).normalized()
		var p4 := Vector3(x_port, rad4.y * RADIUS * 0.30, rad4.z * RADIUS * 0.30)
		_cyl(p4, Vector3.LEFT, 0.058, 0.20, _hull, 10, "dock_interface", -1, i)
		_torus(p4 + Vector3(-0.11, 0, 0), Vector3(0, 0, PI * 0.5), 0.038, 0.062, _accent, "dock_interface", -1, i)
		_box(p4 + Vector3(-0.06, 0, 0), Vector3(0.10, 0.07, 0.09), _hull_dark, Vector3.ZERO, "dock_interface", -1, i)
