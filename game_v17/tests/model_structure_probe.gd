extends SceneTree

# ══════════════════════════════════════════════════════════════════════════════
# task-232 · O'Neill Island Three 高精度单圆柱 · 结构合理性与穿模自动审计
#
# 目标模型：res://models/oneill_island3_hi.tscn（程序化，_ready() 内建模）
# 审计内容（README 见 docs/model_audit.md）：
#   [A] 契约/标记      audit_schema + 关键 meta（probe 不复制模型尺寸）
#   [B] 部件清单       role 分类、必需部件数量、未标记 mesh
#   [C] 主尺度         L≈4.4、D≈1.1（30×7.5 → 4:1），圆柱截面
#   [D] 采光窗         hull 角向缺口 = 3 条、中心 0/120/240°、宽度≈34°
#   [E] 反射板         3 片 / 每片 3 段 / 120° 分布 / 25° 张开 / 1.06L / 0.62 宽
#   [F] 反射板穿模     板 vs 筒体/端盖/其他板/外部件
#   [G] 镜面正面       框架/导轨/横肋/支撑/作动器不得越过镜面正面（法向 +）
#   [H] -X 端外部件    散热鳍/太阳能/系泊塔/交通艇接口互不穿插、不穿壳体/窗带
#   [I] +X 端规则      无港口/系泊/太阳能；反射板根部结构与散热鳍不冲突
#   [J] 数值/AABB      无 NaN/零尺寸；全部外部件在合理包围范围内
#
# 运行（工作区根目录 D:\GHOST TRACK_APSIS）：
#   & "tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game_v17 \
#       --script res://tests/model_structure_probe.gd
# 退出码：0 = PASS（允许 WARN）；1 = FAIL。
# 只读：实例化场景触发一次 _ready()，不写文件、不写 world/session、不排队帧。
# 几何近似：AABB/OBB 采样（每 mesh 27 点：角点 + 棱中点 + 面心）。
# AABB 不是精确碰撞；复杂曲面（环面/圆柱）用包围盒近似，见 docs/model_audit.md 边界。
# ══════════════════════════════════════════════════════════════════════════════

const SCENE_PATH := "res://models/oneill_island3_hi.tscn"
const AUDIT_SCHEMA := 1

# 接触/采样容差（世界单位；模型 1.0 单位 ≈ 6.818 km）
const TOUCH_EPS := 0.004
const HULL_END_MARGIN := 0.03     # 距筒体端面的轴向余量（端盖/挂点接触区豁免）
const MIRROR_HALF_T := 0.009      # 镜面板厚 0.018 → 半厚
const MIRROR_FRONT_TOL := 0.011   # 采样点越过镜面“正面”（内法向）即判穿模
const MIRROR_BACK_TOL := 0.010    # 框架允许贴背面（back 偏移 -0.052）

const ROLES_MIRROR_BACK := ["reflector_frame", "reflector_rail", "reflector_rib", "reflector_strut", "reflector_actuator"]
const ROLES_OUTBOARD_NEG := ["radiator", "solar", "mooring", "dock_interface"]
const ROLES_PLUS_X_FORBIDDEN := ["solar", "mooring", "dock_interface", "dock_port"]
const ROLES_KNOWN := [
	"hull_shell", "window_glass", "window_frame",
	"hull_ring", "hull_stringer", "hull_seam", "hull_hatch", "hull_panel_line",
	"interior_terrain", "interior_water", "interior_clouds",
	"reflector_panel", "reflector_frame", "reflector_rail", "reflector_rib",
	"reflector_hinge", "reflector_strut", "reflector_actuator",
	"endcap", "endcap_mount", "dock_port",
	"radiator", "solar", "mooring", "dock_interface",
]

var _holder: Node3D
var _root: Node3D
var _parts: Array = []
var _contract: Dictionary = {}
var _scale := 1.0
var _hull_verts: PackedVector3Array = PackedVector3Array()

var _checks := 0
var _fails := 0
var _warns := 0
var _failures: Array[String] = []
var _warnings: Array[String] = []
var _untagged: Array[String] = []
var _null_meshes: Array[String] = []

var _sec_title := ""
var _sec_check0 := 0
var _sec_fail0 := 0


func _initialize() -> void:
	_print_header()
	var packed: PackedScene = load(SCENE_PATH)
	_check(packed != null, "场景可载入 " + SCENE_PATH)
	if packed == null:
		_finish()
		return
	_root = packed.instantiate() as Node3D
	_check(_root != null, "场景根节点为 Node3D")
	if _root == null:
		_finish()
		return
	_holder = Node3D.new()
	_holder.name = "AuditHolder"
	get_root().add_child(_holder)
	_holder.add_child(_root)  # 触发 _ready()，程序化模型构建完成
	# SceneTree 脚本的 _initialize 早于 root 进树；等一帧确保 _ready() 已执行。
	await process_frame

	_scale = _root.global_transform.basis.get_scale().x
	_collect_contract()
	_collect_parts(_root)
	if OS.get_environment("DSH_PROBE_DEBUG") == "1":
		_dump_parts()

	_section("A", "契约 / 审计标记", _section_contract)
	_section("B", "部件清单 / role 分类", _section_inventory)
	_section("C", "主尺度（L/D）", _section_primary_scale)
	_section("D", "采光窗（3 条窗带）", _section_windows)
	_section("E", "反射板几何（3/120°/25°）", _section_reflector_geometry)
	_section("F", "反射板穿模（板 vs 主体/端盖/其他板/外部件）", _section_reflector_clipping)
	_section("G", "镜面正面保护（框架/导轨/支撑）", _section_mirror_front)
	_section("H", "-X 端外部件（散热/太阳能/系泊/交通艇）", _section_outboard_neg)
	_section("I", "+X 端规则（无港口/系泊/太阳能）", _section_plus_x)
	_section("J", "数值 / AABB / 包围范围", _section_sanity)

	_finish()


# ── 框架 ────────────────────────────────────────────────────────────────────

func _print_header() -> void:
	print("════════════════════════════════════════════════════════════════════")
	print("task-232 · O'NEILL ISLAND THREE HI · MODEL STRUCTURE PROBE")
	print("scene=" + SCENE_PATH + "  schema=" + str(AUDIT_SCHEMA))
	print("════════════════════════════════════════════════════════════════════")


func _section(tag: String, title: String, fn: Callable) -> void:
	_sec_title = tag + " · " + title
	_sec_check0 = _checks
	_sec_fail0 = _fails
	print("────────────────────────────────────────────────────────────────")
	print("[" + tag + "] " + title)
	fn.call()
	print("[%s] checks=%d fails=%d %s" % [tag, _checks - _sec_check0, _fails - _sec_fail0,
		"OK" if _fails == _sec_fail0 else "FAIL"])


func _check(ok: bool, msg: String) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
		_failures.append("[" + _sec_title + "] " + msg)
	return ok


func _warn(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_warns += 1
		_warnings.append("[" + _sec_title + "] " + msg)


func _finish() -> void:
	print("════════════════════════════════════════════════════════════════════")
	print("[DATA] meshes=%d checks=%d fails=%d warns=%d scale=%.4f" % [_parts.size(), _checks, _fails, _warns, _scale])
	if _warns > 0:
		print("────────────────────────────────────────────────────────────────")
		for w in _warnings:
			print("[WARN] " + w)
	if _fails > 0:
		print("────────────────────────────────────────────────────────────────")
		for f in _failures:
			print("[FAILED] " + f)
		print("MODEL STRUCTURE PROBE FAILED · %d/%d checks failed" % [_fails, _checks])
		quit(1)
	else:
		print("MODEL STRUCTURE PROBE OK · checks=%d warns=%d meshes=%d" % [_checks, _warns, _parts.size()])
		quit(0)


# ── 采集 ────────────────────────────────────────────────────────────────────

func _collect_contract() -> void:
	for key in ["audit_length", "audit_radius", "audit_window_centers_deg", "audit_window_half_deg",
			"audit_reflector_count", "audit_reflector_azimuths_deg", "audit_reflector_open_deg",
			"audit_reflector_root_standoff", "audit_reflector_len_factor", "audit_reflector_width"]:
		_contract[key] = _root.get_meta(key) if _root.has_meta(key) else null


func _collect_parts(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				_null_meshes.append(String(mi.name))
				continue
			var role := String(mi.get_meta("audit_role", ""))
			if role == "" or role == "misc":
				_untagged.append(String(mi.name))
				role = "untagged"
			var la: AABB = mi.mesh.get_aabb()
			var xf: Transform3D = mi.global_transform
			var pts := _sample_surface_points(mi, xf)
			_parts.append({
				"node": mi,
				"name": String(mi.name),
				"role": role,
				"side": int(mi.get_meta("audit_side", 0)),
				"index": int(mi.get_meta("audit_index", -1)),
				"local_aabb": la,
				"aabb": xf * la,
				"basis": xf.basis,
				"xf": xf,
				"center": xf.origin,
				"shape": _shape_of(mi.mesh),
				"points": pts,
			})
		_collect_parts(child)


func _shape_of(mesh: Mesh) -> Dictionary:
	# 精确点-实体检测用；未识别的自定义网格退化为局部 AABB。
	if mesh is BoxMesh:
		var bm := mesh as BoxMesh
		return {"type": "box", "size": bm.size}
	if mesh is CylinderMesh:
		var cm := mesh as CylinderMesh
		return {"type": "cyl", "radius": maxf(cm.top_radius, cm.bottom_radius), "height": cm.height}
	if mesh is SphereMesh:
		var sm := mesh as SphereMesh
		return {"type": "sphere", "radius": sm.radius}
	if mesh is TorusMesh:
		var tm := mesh as TorusMesh
		return {"type": "torus", "inner": tm.inner_radius, "outer": tm.outer_radius}
	return {"type": "aabb"}


func _sample_surface_points(mi: MeshInstance3D, xf: Transform3D, max_n := 48) -> Array:
	# 取真实网格表面顶点（最多 ~48 个），避免 AABB 角点对圆柱/环面的假穿模。
	var arrays := mi.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	if n == 0:
		return []
	var stride := 1
	if n > max_n:
		stride = int(ceil(float(n) / float(max_n)))
	var out: Array = []
	var i := 0
	while i < n:
		out.append(xf * verts[i])
		i += stride
	return out


func _role_parts(role: String) -> Array:
	var out: Array = []
	for p in _parts:
		if String(p["role"]) == role:
			out.append(p)
	return out


func _role_count(role: String, side := 99) -> int:
	var n := 0
	for p in _parts:
		if String(p["role"]) == role and (side == 99 or int(p["side"]) == side):
			n += 1
	return n


func _role_index_parts(role: String, idx: int) -> Array:
	var out: Array = []
	for p in _parts:
		if String(p["role"]) == role and int(p["index"]) == idx:
			out.append(p)
	return out


func _label(p: Dictionary) -> String:
	var s := String(p["name"]) + " [" + String(p["role"])
	if int(p["side"]) != 0:
		s += " " + ("+X" if int(p["side"]) > 0 else "-X")
	if int(p["index"]) >= 0:
		s += " #" + str(int(p["index"]))
	return s + "]"


func _dump_parts() -> void:
	# DSH_PROBE_DEBUG=1 时打印部件清单（角色/方位/索引/世界 AABB），供人工复核。
	for p in _parts:
		var aa: AABB = p["aabb"]
		print("[PART] %s role=%s side=%d idx=%d aabb_pos=%s aabb_size=%s shape=%s" % [
			String(p["name"]), String(p["role"]), int(p["side"]), int(p["index"]),
			str(aa.position), str(aa.size), str(p["shape"])])


func _cfg_f(key: String, fallback: float) -> float:
	var v = _contract.get(key, null)
	if v == null:
		return fallback
	return float(v)


func _cfg_a(key: String, fallback: Array) -> Array:
	var v = _contract.get(key, null)
	if v == null:
		return fallback
	return v


func _L() -> float:
	return _cfg_f("audit_length", 4.4)


func _R() -> float:
	return _cfg_f("audit_radius", 0.55)


func _window_centers() -> Array:
	return _cfg_a("audit_window_centers_deg", [0.0, 120.0, 240.0])


func _window_half_deg() -> float:
	return _cfg_f("audit_window_half_deg", 17.0)


func _radial(p: Vector3) -> float:
	return sqrt(p.y * p.y + p.z * p.z)


func _finite_f(v: float) -> bool:
	return not (is_nan(v) or is_inf(v))


func _finite_v(v: Vector3) -> bool:
	return _finite_f(v.x) and _finite_f(v.y) and _finite_f(v.z)


func _ang_diff_deg(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func _mean_azimuth(p: Dictionary) -> float:
	var c: Vector3 = (p["aabb"] as AABB).get_center()
	return fposmod(rad_to_deg(atan2(c.z, c.y)), 360.0)


func _mesh_verts(p: Dictionary) -> PackedVector3Array:
	var mi := p["node"] as MeshInstance3D
	var arrays := mi.mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


func _point_in_part(p: Dictionary, world_pt: Vector3, shrink := 0.0) -> bool:
	# 精确 primitive 点-实体检测：BoxMesh/CylinderMesh/SphereMesh/TorusMesh；
	# 自定义网格退化为局部 AABB。shrink 为世界单位接触容差。
	var inv: Transform3D = (p["xf"] as Transform3D).affine_inverse()
	var lp: Vector3 = inv * world_pt
	var sh: float = shrink / maxf(_scale, 1.0e-6)
	var shape: Dictionary = p["shape"]
	var st := String(shape["type"])
	if st == "box":
		var bs: Vector3 = shape["size"]
		var h: Vector3 = bs * 0.5
		var sv := Vector3(minf(sh, h.x * 0.5), minf(sh, h.y * 0.5), minf(sh, h.z * 0.5))
		return absf(lp.x) <= h.x - sv.x and absf(lp.y) <= h.y - sv.y and absf(lp.z) <= h.z - sv.z
	if st == "cyl":
		var cr: float = float(shape["radius"])
		var ch: float = float(shape["height"])
		var rr: float = cr - minf(sh, cr * 0.5)
		var hh: float = ch * 0.5 - minf(sh, ch * 0.25)
		return sqrt(lp.x * lp.x + lp.z * lp.z) <= rr and absf(lp.y) <= hh
	if st == "sphere":
		var sr: float = float(shape["radius"])
		return lp.length() <= sr - minf(sh, sr * 0.5)
	if st == "torus":
		var inner: float = float(shape["inner"])
		var outer: float = float(shape["outer"])
		var ring_r: float = (inner + outer) * 0.5
		var tube: float = (outer - inner) * 0.5
		var q := Vector2(sqrt(lp.x * lp.x + lp.z * lp.z) - ring_r, lp.y)
		return q.length() <= tube - minf(sh, tube * 0.5)
	var la: AABB = p["local_aabb"]
	var d: Vector3 = (lp - la.get_center()).abs()
	var hf: Vector3 = la.size * 0.5
	var shf := Vector3(minf(sh, maxf(hf.x * 0.5, 0.0)), minf(sh, maxf(hf.y * 0.5, 0.0)), minf(sh, maxf(hf.z * 0.5, 0.0)))
	return d.x <= hf.x - shf.x and d.y <= hf.y - shf.y and d.z <= hf.z - shf.z


func _aabb_touch(a: Dictionary, b: Dictionary, shrink := TOUCH_EPS) -> bool:
	# 允许薄板（AABB 某轴 < 2*shrink）参与邻近检测；按轴要求重叠深度 > shrink。
	var aa: AABB = a["aabb"]
	var bb: AABB = b["aabb"]
	if aa.position.x >= bb.position.x + bb.size.x - shrink:
		return false
	if bb.position.x >= aa.position.x + aa.size.x - shrink:
		return false
	if aa.position.y >= bb.position.y + bb.size.y - shrink:
		return false
	if bb.position.y >= aa.position.y + aa.size.y - shrink:
		return false
	if aa.position.z >= bb.position.z + bb.size.z - shrink:
		return false
	if bb.position.z >= aa.position.z + aa.size.z - shrink:
		return false
	return true


func _parts_interfere(a: Dictionary, b: Dictionary, shrink := TOUCH_EPS) -> bool:
	if not _aabb_touch(a, b, shrink):
		return false
	for pt in a["points"]:
		if _point_in_part(b, pt, shrink):
			return true
	for pt in b["points"]:
		if _point_in_part(a, pt, shrink):
			return true
	return false


func _point_inside_hull_core(pt: Vector3, shrink := 0.0) -> bool:
	# 筒体“压力壳内部”近似：轴向去掉端盖/挂点接触区（HULL_END_MARGIN），径向 < R。
	var half_l: float = (_L() * 0.5 - HULL_END_MARGIN) * _scale
	var r: float = _R() * _scale
	if absf(pt.x) > half_l - shrink:
		return false
	return _radial(pt) < r - shrink


func _point_in_window_band(pt: Vector3, shrink := 0.0) -> bool:
	var half_l: float = _L() * _scale * 0.5
	var r: float = _R() * _scale
	# 端面附近（|x| 距壳体端 < 容差）不计入窗带，避免端盖/挂点边界误报。
	if absf(pt.x) > half_l - shrink:
		return false
	var rad := _radial(pt)
	if rad < r * 0.95 - shrink or rad > r * 1.08 + shrink:
		return false
	var deg := fposmod(rad_to_deg(atan2(pt.z, pt.y)), 360.0)
	for c in _window_centers():
		if _ang_diff_deg(deg, float(c)) <= _window_half_deg() + 1.0:
			return true
	return false


# ── [A] 契约 / 标记 ─────────────────────────────────────────────────────────

func _section_contract() -> void:
	_check(int(_root.get_meta("audit_schema", 0)) == AUDIT_SCHEMA,
		"根节点 audit_schema=%d（期望 %d）" % [int(_root.get_meta("audit_schema", 0)), AUDIT_SCHEMA])
	for key in ["audit_length", "audit_radius", "audit_window_centers_deg", "audit_window_half_deg",
			"audit_reflector_count", "audit_reflector_azimuths_deg", "audit_reflector_open_deg",
			"audit_reflector_root_standoff", "audit_reflector_len_factor", "audit_reflector_width"]:
		_check(_contract.get(key, null) != null, "契约 meta 存在 " + key)

	var L := _L()
	var R := _R()
	_check(absf(L - 4.4) <= 1.0e-4, "契约 LENGTH=4.4，实为 %.4f" % L)
	_check(absf(R - 0.55) <= 1.0e-4, "契约 RADIUS=0.55，实为 %.4f" % R)
	var ld := L / (2.0 * R)
	_check(absf(ld - 4.0) <= 1.0e-3, "契约 L/D=4.0（30×7.5），实为 %.4f" % ld)
	var centers := _window_centers()
	_check(centers.size() == 3, "窗带中心数=3，实为 %d" % centers.size())
	for i in range(centers.size()):
		_check(absf(float(centers[i]) - float([0.0, 120.0, 240.0][i])) <= 1.0e-3,
			"窗带中心[%d]=%.1f（期望 %.1f）" % [i, float(centers[i]), float([0.0, 120.0, 240.0][i])])
	_check(absf(_window_half_deg() - 17.0) <= 1.0e-3, "窗带半角=17°，实为 %.2f" % _window_half_deg())
	_check(int(_cfg_f("audit_reflector_count", 0.0)) == 3, "反射板数=3，实为 %d" % int(_cfg_f("audit_reflector_count", 0.0)))
	var az := _cfg_a("audit_reflector_azimuths_deg", [])
	_check(az.size() == 3, "反射板方位角元数据 3 个，实为 %d" % az.size())
	if az.size() == 3:
		for i in range(3):
			_check(absf(float(az[i]) - float([60.0, 180.0, 300.0][i])) <= 1.0e-3,
				"反射板方位[%d]=%.1f（期望 %.1f）" % [i, float(az[i]), float([60.0, 180.0, 300.0][i])])
	_check(absf(_cfg_f("audit_reflector_open_deg", 0.0) - 25.0) <= 1.0e-3,
		"反射板张开角=25°，实为 %.2f" % _cfg_f("audit_reflector_open_deg", 0.0))
	_check(absf(_cfg_f("audit_reflector_len_factor", 0.0) - 1.06) <= 1.0e-3,
		"反射板长度系数=1.06，实为 %.3f" % _cfg_f("audit_reflector_len_factor", 0.0))
	_check(absf(_cfg_f("audit_reflector_width", 0.0) - 0.62) <= 1.0e-3,
		"反射板宽=0.62，实为 %.3f" % _cfg_f("audit_reflector_width", 0.0))
	_check(absf(_cfg_f("audit_reflector_root_standoff", 0.0) - 0.30) <= 1.0e-3,
		"反射板根部外伸=0.30，实为 %.3f" % _cfg_f("audit_reflector_root_standoff", 0.0))

	var root_scale := _root.global_transform.basis.get_scale()
	_check(root_scale.is_equal_approx(Vector3.ONE * _scale) and _scale > 0.0,
		"根节点缩放均匀且 >0，实为 " + str(root_scale))
	print("[DATA] contract L=%.3f R=%.3f L/D=%.3f scale=%.4f windows=%s" % [L, R, ld, _scale, str(centers)])


# ── [B] 部件清单 ────────────────────────────────────────────────────────────

func _section_inventory() -> void:
	var total := _parts.size()
	_check(total >= 350, "MeshInstance3D 数量=%d（期望 >=350，模型完整构建）" % total)
	_check(total <= 700, "MeshInstance3D 数量=%d（期望 <=700，未失控膨胀）" % total)
	_check(_null_meshes.is_empty(), "无 mesh=null 的 MeshInstance3D：%s" % _list_summary(_null_meshes))
	_check(_untagged.is_empty(), "全部 MeshInstance3D 带 audit_role：未标记 %d 个 %s" % [_untagged.size(), _list_summary(_untagged)])

	var required := {
		"hull_shell": 1, "window_glass": 3, "window_frame": 30,
		"hull_ring": 11, "hull_stringer": 6, "hull_seam": 60, "hull_hatch": 12, "hull_panel_line": 6,
		"interior_terrain": 30, "interior_water": 3, "interior_clouds": 9,
		"reflector_panel": 9, "reflector_frame": 9, "reflector_rail": 18, "reflector_rib": 9,
		"reflector_hinge": 36, "reflector_strut": 12, "reflector_actuator": 24,
		"endcap": 30, "endcap_mount": 6, "dock_port": 12,
		"radiator": 32, "solar": 20, "mooring": 15, "dock_interface": 15,
	}
	for role in required:
		_check(_role_count(String(role)) >= int(required[role]),
			"role %s 数量=%d（期望 >=%d）" % [role, _role_count(String(role)), int(required[role])])
	_check(_role_count("hull_shell") == 1, "外壳 hull_shell 唯一，实为 %d" % _role_count("hull_shell"))
	_check(_role_count("window_glass") == 3, "采光窗玻璃 3 条，实为 %d" % _role_count("window_glass"))
	_check(_role_count("reflector_panel") == 9, "反射板 3 片×3 段=9，实为 %d" % _role_count("reflector_panel"))
	for side in [-1, 1]:
		_check(_role_count("radiator", side) == 16, "散热鳍 %s 端 16 件（4 组），实为 %d" % [_side_name(side), _role_count("radiator", side)])
		_check(_role_count("endcap", side) >= 20, "端盖 %s 端部件 >=20，实为 %d" % [_side_name(side), _role_count("endcap", side)])

	var unknown: Array[String] = []
	for p in _parts:
		var role := String(p["role"])
		if role != "untagged" and not (role in ROLES_KNOWN):
			unknown.append(_label(p))
	_check(unknown.is_empty(), "role 均在审计分类表内：未知 %s" % _list_summary(unknown))

	var names: Dictionary = {}
	var dup: Array[String] = []
	for p in _parts:
		var n := String(p["name"])
		names[n] = int(names.get(n, 0)) + 1
		if int(names[n]) == 2:
			dup.append(n)
	_check(dup.is_empty(), "MeshInstance3D name 唯一：重复 %s" % _list_summary(dup))

	var counts: Dictionary = {}
	for p in _parts:
		var role := String(p["role"])
		counts[role] = int(counts.get(role, 0)) + 1
	print("[DATA] roles=" + str(counts))


func _side_name(side: int) -> String:
	return "+X" if side > 0 else "-X"


func _list_summary(items: Array) -> String:
	if items.is_empty():
		return "[]"
	var shown: Array[String] = []
	for i in range(mini(int(items.size()), 8)):
		shown.append(String(items[i]))
	var s := str(shown)
	if items.size() > 8:
		s += " …(+%d)" % (items.size() - 8)
	return s


# ── [C] 主尺度 ──────────────────────────────────────────────────────────────

func _section_primary_scale() -> void:
	var hull := _role_parts("hull_shell")
	_check(hull.size() == 1, "外壳 hull_shell 唯一（尺度测量样本）")
	if hull.size() != 1:
		return
	_hull_verts = _mesh_verts(hull[0])
	_check(_hull_verts.size() > 1000, "外壳网格顶点数=%d（>=1000）" % _hull_verts.size())
	var xmin := INF
	var xmax := -INF
	var rmax := 0.0
	for v in _hull_verts:
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
		rmax = maxf(rmax, _radial(v))
	var length_w: float = (xmax - xmin) * _scale
	var diameter_w: float = rmax * 2.0 * _scale
	var expect_l: float = _L() * _scale
	var expect_d: float = _R() * 2.0 * _scale
	_check(absf(length_w - expect_l) <= 0.02 * _scale,
		"外壳轴向长度=%.4f（契约 %.4f ±0.02）" % [length_w, expect_l])
	_check(absf(diameter_w - expect_d) <= 0.015 * _scale,
		"外壳直径=%.4f（契约 %.4f ±0.015，128 段圆）" % [diameter_w, expect_d])
	var ratio := length_w / maxf(diameter_w, 1.0e-6)
	_check(absf(ratio - 4.0) <= 0.05, "L/D=%.4f（30×7.5 km → 4:1 ±0.05）" % ratio)
	_check(absf(xmin * _scale + _L() * _scale * 0.5) <= 0.01 * _scale,
		"圆柱 -X 端 x=%.4f（对称于原点）" % (xmin * _scale))
	_check(absf(xmax * _scale - _L() * _scale * 0.5) <= 0.01 * _scale,
		"圆柱 +X 端 x=%.4f（对称于原点）" % (xmax * _scale))
	print("[DATA] hull L=%.4f D=%.4f ratio=%.4f (world units, scale=%.3f)" % [length_w, diameter_w, ratio, _scale])


# ── [D] 采光窗 ──────────────────────────────────────────────────────────────

func _section_windows() -> void:
	var gaps := _hull_angle_gaps()
	_check(gaps.size() == 3, "外壳角向缺口数=3（3 条采光窗），实为 %d" % gaps.size())
	var centers := _window_centers()
	if gaps.size() == 3:
		for i in range(3):
			var g: Dictionary = gaps[i]
			var width: float = float(g["width"])
			var center: float = float(g["center"])
			_check(width >= 30.0 and width <= 37.0,
				"窗带[%d]角宽=%.2f°（期望 34°±3°，含分段量化）" % [i, width])
			var best := 999.0
			var best_center := 0.0
			for c in centers:
				var d := _ang_diff_deg(center, float(c))
				if d < best:
					best = d
					best_center = float(c)
			_check(best <= 2.0, "窗带[%d]中心=%.2f°（最接近契约中心 %.1f°，偏差 %.2f°<=2°）" % [i, center, best_center, best])
			_check(_in_any_window(center), "窗带[%d]中心 %.2f° 落在契约窗带内" % [i, center])
		var pair_ok := true
		for i in range(3):
			var d0 := _ang_diff_deg(float(gaps[i]["center"]), float(gaps[(i + 1) % 3]["center"]))
			if absf(d0 - 120.0) > 3.0:
				pair_ok = false
		_check(pair_ok, "3 条窗带近似 120° 均布（±3°）")

	var glass := _role_parts("window_glass")
	_check(glass.size() == 3, "window_glass 3 条，实为 %d" % glass.size())
	var centers_ok := true
	for p in glass:
		var idx := int(p["index"])
		if idx < 0 or idx >= centers.size():
			centers_ok = false
			continue
		var az := _mean_azimuth(p)
		var d := _ang_diff_deg(az, float(centers[idx]))
		if d > 2.0:
			centers_ok = false
			_check(false, "window_glass #%d 方位=%.2f°（期望 %.1f°±2°）" % [idx, az, float(centers[idx])])
		var verts := _mesh_verts(p)
		var rsum := 0.0
		for v in verts:
			rsum += _radial(v)
		var rmean: float = (rsum / maxf(float(verts.size()), 1.0)) * _scale
		_check(absf(rmean - _R() * 1.004 * _scale) <= 0.01 * _scale,
			"window_glass #%d 半径=%.4f（期望 1.004R=%.4f）" % [idx, rmean, _R() * 1.004 * _scale])
	_check(centers_ok, "window_glass 方位与契约窗带中心一致（±2°）")
	print("[DATA] window gaps=" + str(gaps.size()) + " centers=" + str(_window_centers()))


func _hull_angle_gaps() -> Array:
	var angles: Array = []
	for v in _hull_verts:
		angles.append(fposmod(rad_to_deg(atan2(v.z, v.y)), 360.0))
	angles.sort()
	var uniq: Array = []
	for a in angles:
		var fa := float(a)
		if uniq.is_empty() or fa - float(uniq[-1]) > 0.01:
			uniq.append(fa)
	if uniq.size() < 4:
		return []
	var gaps: Array = []
	for i in range(uniq.size()):
		var a0: float = float(uniq[i])
		var a1: float = float(uniq[(i + 1) % uniq.size()])
		var d := fposmod(a1 - a0, 360.0)
		if i == uniq.size() - 1:
			d = fposmod(float(uniq[0]) + 360.0 - a0, 360.0)
		if d > 5.0:
			gaps.append({"start": a0, "end": fposmod(a0 + d, 360.0), "width": d, "center": fposmod(a0 + d * 0.5, 360.0)})
	return gaps


func _in_any_window(deg: float) -> bool:
	for c in _window_centers():
		if _ang_diff_deg(deg, float(c)) <= _window_half_deg() + 1.0:
			return true
	return false


# ── [E] 反射板几何 ──────────────────────────────────────────────────────────

func _reflector_frame(idx: int) -> Dictionary:
	var segs := _role_index_parts("reflector_panel", idx)
	if segs.size() < 2:
		return {}
	var basis: Basis = segs[0]["basis"]
	var axis: Vector3 = basis.x.normalized()
	var normal: Vector3 = basis.y.normalized()
	var tangent: Vector3 = basis.z.normalized()
	segs = _sort_by_projection(segs, axis)
	var c0: Vector3 = segs[0]["center"]
	var c2: Vector3 = segs[-1]["center"]
	# 3 段中心分别位于全长 t=1/6、1/2、5/6；两端外推得到真实 root/tip。
	var full_len: float = c0.distance_to(c2) * 1.5
	var root: Vector3 = c0 - axis * (full_len / 6.0)
	var tip: Vector3 = c2 + axis * (full_len / 6.0)
	var width: float = (segs[0]["local_aabb"] as AABB).size.z * _scale
	# 正面 = 朝向筒轴一侧（结构 back = -normal 在外侧）
	var radial_dir := Vector3(0, root.y, root.z)
	if radial_dir.length() < 1.0e-5:
		radial_dir = Vector3.UP
	radial_dir = radial_dir.normalized()
	if normal.dot(radial_dir) > 0.0:
		normal = -normal
	return {
		"idx": idx,
		"segs": segs,
		"axis": axis,
		"normal": normal,
		"tangent": tangent,
		"root": root,
		"tip": tip,
		"span": root.distance_to(tip),
		"width": width,
		"full_len": c0.distance_to(c2) * 1.5,
	}


func _sort_by_projection(items: Array, axis: Vector3) -> Array:
	var out: Array = []
	for p in items:
		var key := (p["center"] as Vector3).dot(axis)
		var at := 0
		for j in range(out.size()):
			if key < float(out[j]["_key"]):
				break
			at += 1
		out.insert(at, {"_key": key, "p": p})
	var result: Array = []
	for row in out:
		result.append(row["p"])
	return result


func _section_reflector_geometry() -> void:
	var count := int(_cfg_f("audit_reflector_count", 3.0))
	var open_deg := _cfg_f("audit_reflector_open_deg", 25.0)
	var len_factor := _cfg_f("audit_reflector_len_factor", 1.06)
	var width_model := _cfg_f("audit_reflector_width", 0.62)
	var standoff := _cfg_f("audit_reflector_root_standoff", 0.30)
	var azimuths := _cfg_a("audit_reflector_azimuths_deg", [60.0, 180.0, 300.0])
	var seen := {}
	for p in _role_parts("reflector_panel"):
		var idx := int(p["index"])
		seen[idx] = int(seen.get(idx, 0)) + 1
	_check(seen.size() == count, "反射板片数=%d（期望 %d）" % [seen.size(), count])
	for idx in range(count):
		_check(int(seen.get(idx, 0)) == 3, "反射板 #%d 分段数=%d（期望 3）" % [idx, int(seen.get(idx, 0))])

	var root_azimuths: Array = []
	for idx in range(count):
		var fr := _reflector_frame(idx)
		if fr.is_empty():
			_check(false, "反射板 #%d 无法从几何推断（缺 reflector_panel 段）" % idx)
			continue
		var segs: Array = fr["segs"]
		var axis: Vector3 = fr["axis"]
		var normal: Vector3 = fr["normal"]
		var root: Vector3 = fr["root"]
		var span: float = fr["span"]
		var full_len: float = fr["full_len"]
		var width: float = fr["width"]

		# 3 段共面 / 法线一致
		var normal_ok := true
		for p in segs:
			var n: Vector3 = (p["basis"] as Basis).y.normalized()
			if absf(absf(n.dot(normal)) - 1.0) > 1.0e-3:
				normal_ok = false
			var w: float = (p["center"] - (segs[0]["center"] as Vector3)).dot(normal)
			if absf(w) > 0.002 * _scale:
				normal_ok = false
		_check(normal_ok, "反射板 #%d 的 3 段共面且法线一致" % idx)

		var axis_deg := rad_to_deg(acos(clampf(axis.dot(Vector3.LEFT), -1.0, 1.0)))
		_check(absf(axis_deg - open_deg) <= 2.0,
			"反射板 #%d 张开角=%.2f°（期望 %.1f°±2°）" % [idx, axis_deg, open_deg])

		var az := fposmod(rad_to_deg(atan2(root.z, root.y)), 360.0)
		root_azimuths.append(az)
		var best_az := 999.0
		for a in azimuths:
			best_az = minf(best_az, _ang_diff_deg(az, float(a)))
		_check(best_az <= 3.0, "反射板 #%d 根部方位=%.2f°（契约 %.1f° 系，偏差 %.2f°<=3°）" % [idx, az, float(azimuths[idx]), best_az])

		var root_r := _radial(root) / _scale
		_check(absf(root_r - _R() * 1.08) <= 0.02 * _R(),
			"反射板 #%d 根部半径=%.4f（期望 1.08R=%.4f ±0.02R）" % [idx, root_r, _R() * 1.08])
		var root_standoff := root.x / _scale - _L() * 0.5
		_check(absf(root_standoff - standoff) <= 0.02,
			"反射板 #%d 根部外伸=%.4f（期望 %.2f ±0.02）" % [idx, root_standoff, standoff])
		var len_ratio := full_len / (_L() * _scale)
		_check(absf(len_ratio - len_factor) <= 0.03,
			"反射板 #%d 长度=%.4fL（期望 %.2fL ±0.03）" % [idx, len_ratio, len_factor])
		_check(span > 0.0 and span / (_L() * _scale) >= 1.0 and span / (_L() * _scale) <= 1.1,
			"反射板 #%d 端到端跨度=%.4fL（期望 1.0–1.1L）" % [idx, span / (_L() * _scale)])
		var width_ratio := width / (2.0 * _R() * _scale)
		_check(absf(width_ratio - width_model / (2.0 * _R())) <= 0.02,
			"反射板 #%d 宽=%.4f（模型 %.2f; 宽/直径=%.4f 期望 %.4f）" % [idx, width, width_model, width_ratio, width_model / (2.0 * _R())])
		# 根部不得进入筒体（板内缘与外壳留 0.03+ 间隙）
		var min_rad := INF
		for p in segs:
			for pt in p["points"]:
				if absf(pt.x) <= _L() * _scale * 0.5:
					min_rad = minf(min_rad, _radial(pt))
		_check(min_rad > _R() * _scale + 0.01 * _scale,
			"反射板 #%d 与筒体间隙：最小半径=%.4f > R+0.01=%.4f" % [idx, min_rad, _R() * _scale + 0.01 * _scale])
		print("[DATA] reflector #%d angle=%.2f° az=%.2f° len=%.3fL span=%.3fL width=%.3f root_r=%.3f standoff=%.3f" % [
			idx, axis_deg, az, len_ratio, span / (_L() * _scale), width, root_r, root_standoff])

	# 120° 分布
	if root_azimuths.size() == 3:
		var spacing_ok := true
		for i in range(3):
			var d := _ang_diff_deg(float(root_azimuths[i]), float(root_azimuths[(i + 1) % 3]))
			if fposmod(float(root_azimuths[i]) - float(root_azimuths[(i + 1) % 3]), 360.0) < 0.0:
				d = _ang_diff_deg(float(root_azimuths[(i + 1) % 3]), float(root_azimuths[i]))
			if absf(d - 120.0) > 3.0:
				spacing_ok = false
		_check(spacing_ok, "反射板 3 片绕轴 120° 均布（±3°），方位=" + str(root_azimuths))
	# 与窗带错开（避免遮挡采光窗）
	for i in range(root_azimuths.size()):
		var clear := true
		for c in _window_centers():
			if _ang_diff_deg(float(root_azimuths[i]), float(c)) < 20.0:
				clear = false
		_check(clear, "反射板 #%d 方位 %.2f° 与窗带中心错开 >=20°" % [i, float(root_azimuths[i])])


# ── [F] 反射板穿模 ──────────────────────────────────────────────────────────

func _section_reflector_clipping() -> void:
	var count := int(_cfg_f("audit_reflector_count", 3.0))
	var endcap_like := ["endcap", "endcap_mount", "dock_port"]
	var outboard_like := ROLES_OUTBOARD_NEG
	# 1) 板 vs 筒体
	for idx in range(count):
		var segs := _role_index_parts("reflector_panel", idx)
		var hits: Array[String] = []
		for p in segs:
			for pt in p["points"]:
				if _point_inside_hull_core(pt, TOUCH_EPS):
					hits.append(_label(p))
					break
			if not hits.is_empty():
				break
		_check(hits.is_empty(), "反射板 #%d 未穿入筒体壳体%s" % [idx, "" if hits.is_empty() else "：" + _list_summary(hits)])
	# 2) 板 vs 端盖 / 对接口（允许根部铰座接触，但镜面板本身不得插入端盖）
	for idx in range(count):
		var segs := _role_index_parts("reflector_panel", idx)
		var hits: Array[String] = []
		for p in segs:
			for ep in _parts:
				if not (String(ep["role"]) in endcap_like):
					continue
				for pt in p["points"]:
					if _point_in_part(ep, pt, TOUCH_EPS):
						hits.append(_label(p) + " ∩ " + _label(ep))
						break
				if not hits.is_empty():
					break
			if not hits.is_empty():
				break
		_check(hits.is_empty(), "反射板 #%d 未穿入端盖/对接口%s" % [idx, "" if hits.is_empty() else "：" + _list_summary(hits)])
	# 3) 板 vs 板（不同片）
	for ia in range(count):
		for ib in range(ia + 1, count):
			var a := _role_index_parts("reflector_panel", ia)
			var b := _role_index_parts("reflector_panel", ib)
			var hit := ""
			for pa in a:
				for pb in b:
					if _parts_interfere(pa, pb, TOUCH_EPS):
						hit = _label(pa) + " ∩ " + _label(pb)
						break
				if hit != "":
					break
			_check(hit == "", "反射板 #%d 与 #%d 不互相穿插%s" % [ia, ib, "" if hit == "" else "：" + hit])
	# 4) 板 vs 外部件（散热/太阳能/系泊/交通艇）
	for idx in range(count):
		var segs := _role_index_parts("reflector_panel", idx)
		var hits: Array[String] = []
		for p in segs:
			for op in _parts:
				if not (String(op["role"]) in outboard_like):
					continue
				for pt in p["points"]:
					if _point_in_part(op, pt, TOUCH_EPS):
						hits.append(_label(p) + " ∩ " + _label(op))
						break
				if not hits.is_empty():
					break
			if not hits.is_empty():
				break
		_check(hits.is_empty(), "反射板 #%d 未穿入外部件%s" % [idx, "" if hits.is_empty() else "：" + _list_summary(hits)])
	# 5) 反射板根部结构（铰座/背撑/作动器）不得穿入筒体壳体（端盖接触允许）
	var hardware_roles := ["reflector_hinge", "reflector_strut", "reflector_actuator"]
	var hw_hits: Array[String] = []
	for p in _parts:
		if not (String(p["role"]) in hardware_roles):
			continue
		for pt in p["points"]:
			if _point_inside_hull_core(pt, TOUCH_EPS):
				hw_hits.append(_label(p))
				break
	_check(hw_hits.is_empty(), "反射板根部结构未穿入筒体壳体%s" % ("" if hw_hits.is_empty() else "：" + _list_summary(hw_hits)))
	# 6) 根部结构允许接触端盖，但不得穿入 +X 端散热鳍（在 [I] 复查）
	var hinge_count := _role_count("reflector_hinge")
	_check(hinge_count >= 36, "根部铰座/转轴部件数=%d（>=36，每片双铰）" % hinge_count)


# ── [G] 镜面正面保护 ────────────────────────────────────────────────────────

func _section_mirror_front() -> void:
	var count := int(_cfg_f("audit_reflector_count", 3.0))
	for idx in range(count):
		var fr := _reflector_frame(idx)
		if fr.is_empty():
			continue
		var root: Vector3 = fr["root"]
		var axis: Vector3 = fr["axis"]
		var normal: Vector3 = fr["normal"]
		var tangent: Vector3 = fr["tangent"]
		var span: float = fr["span"]
		var width: float = fr["width"]
		var half_w: float = width * 0.5 + 0.02 * _scale
		var frame_total := 0
		var front_hits: Array[String] = []
		var close_hits: Array[String] = []
		for role in ROLES_MIRROR_BACK:
			for p in _role_index_parts(String(role), idx):
				frame_total += 1
				var worst_w := -INF
				var worst_t := 0.0
				var worst_u := 0.0
				var close := false
				for pt in p["points"]:
					var rel: Vector3 = pt - root
					var t: float = rel.dot(axis) / maxf(span, 1.0e-6)
					var u: float = rel.dot(tangent)
					var w: float = rel.dot(normal)
					if t >= -0.05 and t <= 1.05 and absf(u) <= half_w:
						if w > worst_w:
							worst_w = w
							worst_t = t
							worst_u = u
				if worst_w > MIRROR_FRONT_TOL * _scale:
					front_hits.append("%s 法向 w=%+.4f (t=%.3f u=%+.3f)" % [_label(p), worst_w, worst_t, worst_u])
				elif worst_w > -MIRROR_HALF_T * _scale:
					close_hits.append("%s w=%+.4f" % [_label(p), worst_w])
		_check(frame_total >= 8, "反射板 #%d 背面框架/导轨/支撑部件数=%d（>=8）" % [idx, frame_total])
		var front_detail := ""
		for i in range(mini(front_hits.size(), 12)):
			front_detail += "\n      " + front_hits[i]
		if front_hits.size() > 12:
			front_detail += "\n      …(+%d)" % (front_hits.size() - 12)
		_check(front_hits.is_empty(), "反射板 #%d 镜面正面无穿越（框架/导轨/支撑）%s" % [idx, "" if front_hits.is_empty() else "：" + front_detail])
		_warn(close_hits.is_empty(), "反射板 #%d 框架贴近/进入镜面厚度（应位于背面）%s" % [idx, "" if close_hits.is_empty() else "：" + _list_summary(close_hits)])
		# 框架必须整体在镜面背面（允许贴背面接触）
		var worst_frame_w := -INF
		for role in ["reflector_frame", "reflector_rail", "reflector_rib"]:
			for p in _role_index_parts(String(role), idx):
				for pt in p["points"]:
					var rel2: Vector3 = pt - root
					var t2: float = rel2.dot(axis) / maxf(span, 1.0e-6)
					if t2 < -0.02 or t2 > 1.02:
						continue
					worst_frame_w = maxf(worst_frame_w, rel2.dot(normal))
		_check(worst_frame_w <= -MIRROR_HALF_T * _scale + TOUCH_EPS,
			"反射板 #%d 背框层整体在镜面背面（最大法向 %.4f <= %.4f）" % [idx, worst_frame_w, -MIRROR_HALF_T * _scale + TOUCH_EPS])
		print("[DATA] mirror #%d frame_parts=%d frame_max_w=%+.4f front_hits=%d close_hits=%d" % [idx, frame_total, worst_frame_w, front_hits.size(), close_hits.size()])


# ── [H] -X 端外部件 ─────────────────────────────────────────────────────────

func _section_outboard_neg() -> void:
	var outboard: Array = []
	for p in _parts:
		var role := String(p["role"])
		if role == "solar" or role == "mooring" or role == "dock_interface" or role == "dock_port":
			outboard.append(p)
		elif role == "radiator" and int(p["side"]) == -1:
			outboard.append(p)
	_check(outboard.size() == 78, "-X 端外部件数=%d（散热16+太阳能20+系泊15+交通艇15+对接口12=78）" % outboard.size())
	var side_bad: Array[String] = []
	for p in outboard:
		if String(p["role"]) != "radiator" and int(p["side"]) != -1:
			side_bad.append(_label(p))
	_check(side_bad.is_empty(), "太阳能/系泊/交通艇/对接口 side 元数据均为 -1%s" % ("" if side_bad.is_empty() else "：" + _list_summary(side_bad)))

	# 1) 不穿入筒体壳体（对接口单独在下面查“必须在端盖外侧”）
	var hull_roles := ["radiator", "solar", "mooring", "dock_interface"]
	var hull_hits: Array[String] = []
	for p in outboard:
		if not (String(p["role"]) in hull_roles):
			continue
		for pt in p["points"]:
			if _point_inside_hull_core(pt, TOUCH_EPS):
				hull_hits.append(_label(p))
				break
	_check(hull_hits.is_empty(), "-X 外部件（散热/太阳能/系泊/交通艇）不穿入筒体壳体%s" % ("" if hull_hits.is_empty() else "：" + _list_summary(hull_hits)))

	# 2) 不穿入采光窗带
	var win_hits: Array[String] = []
	for p in outboard:
		if not (String(p["role"]) in hull_roles):
			continue
		for pt in p["points"]:
			if _point_in_window_band(pt, TOUCH_EPS):
				win_hits.append(_label(p))
				break
	_check(win_hits.is_empty(), "-X 外部件（散热/太阳能/系泊/交通艇）不穿入采光窗带%s" % ("" if win_hits.is_empty() else "：" + _list_summary(win_hits)))

	# 3) -X 对接口必须挂在端盖外侧（不得退回筒体内部）
	var port_bad: Array[String] = []
	var max_allowed_x: float = -_L() * _scale * 0.5 + 0.02 * _scale
	for p in _role_parts("dock_port"):
		var aa: AABB = p["aabb"]
		var x_max: float = aa.position.x + aa.size.x
		if x_max > max_allowed_x:
			port_bad.append("%s x_max=%+.3f（应 <= %+.3f）" % [_label(p), x_max, max_allowed_x])
	_check(port_bad.is_empty(), "-X 端 6 个对接口全部位于端盖外侧%s" % ("" if port_bad.is_empty() else "：" + _list_summary(port_bad)))
	var port_idx := {}
	for p in _role_parts("dock_port"):
		port_idx[int(p["index"])] = true
	_check(port_idx.size() == 6, "-X 对接口组数=%d（6 个方位）" % port_idx.size())

	# 4) 互相不穿插（同一 assembly：同 role+同 index+同 side 视为装配接触，跳过）
	var pair_hits: Array[String] = []
	var pair_candidates := 0
	for ia in range(outboard.size()):
		for ib in range(ia + 1, outboard.size()):
			var a: Dictionary = outboard[ia]
			var b: Dictionary = outboard[ib]
			if String(a["role"]) == String(b["role"]) and int(a["index"]) == int(b["index"]) and int(a["side"]) == int(b["side"]):
				continue
			if not _aabb_touch(a, b, TOUCH_EPS):
				continue
			pair_candidates += 1
			if _parts_interfere(a, b, TOUCH_EPS):
				pair_hits.append(_label(a) + " ∩ " + _label(b))
	_check(pair_hits.is_empty(), "-X 外部件互不穿插（AABB 近邻 %d 对）%s" % [pair_candidates, "" if pair_hits.is_empty() else "：" + _list_summary(pair_hits)])
	print("[DATA] outboard_neg parts=%d near_pairs=%d" % [outboard.size(), pair_candidates])

	# 5) 各 role 数量
	_check(_role_count("radiator", -1) == 16, "散热鳍 -X 端 4 组×4 件=16，实为 %d" % _role_count("radiator", -1))
	_check(_role_count("solar", -1) == 20, "太阳能 -X 端 4 组×5 件=20，实为 %d" % _role_count("solar", -1))
	_check(_role_count("mooring", -1) == 15, "系泊塔 -X 端 5 个×3 件=15，实为 %d" % _role_count("mooring", -1))
	_check(_role_count("dock_interface", -1) == 15, "交通艇接口 -X 端 5 个×3 件=15，实为 %d" % _role_count("dock_interface", -1))
	_check(_role_count("dock_port") == 12, "港口对接口 6 个×2 件=12，实为 %d" % _role_count("dock_port"))


# ── [I] +X 端规则 ───────────────────────────────────────────────────────────

func _section_plus_x() -> void:
	var half_l: float = _L() * _scale * 0.5
	var bad_side: Array[String] = []
	var bad_pos: Array[String] = []
	for p in _parts:
		var role := String(p["role"])
		# dock_port 的位置正确性在 [H] 已按“必须在端盖外侧”检查，这里只查 +X 禁止项。
		if not (role in ["solar", "mooring", "dock_interface"]):
			continue
		if int(p["side"]) > 0:
			bad_side.append(_label(p))
		var c: Vector3 = (p["aabb"] as AABB).get_center()
		if c.x > -half_l + 0.05 * _scale:
			bad_pos.append(_label(p) + " x=%+.3f" % c.x)
	_check(bad_side.is_empty(), "+X 端无港口/系泊/太阳能/交通艇（side 均为 -1）%s" % ("" if bad_side.is_empty() else "：" + _list_summary(bad_side)))
	_check(bad_pos.is_empty(), "太阳能/系泊/交通艇均位于 -X 端（中心 x <= -L/2+0.05）%s" % ("" if bad_pos.is_empty() else "：" + _list_summary(bad_pos)))
	_check(_role_count("endcap_mount", 1) >= 6, "+X 端反射板安装件=%d（>=6，3 组）" % _role_count("endcap_mount", 1))
	_check(_role_count("dock_port", 1) == 0, "+X 端对接口数=%d（=0）" % _role_count("dock_port", 1))
	_check(_role_count("solar", 1) == 0, "+X 端太阳能数=%d（=0）" % _role_count("solar", 1))
	_check(_role_count("mooring", 1) == 0, "+X 端系泊塔数=%d（=0）" % _role_count("mooring", 1))
	_check(_role_count("dock_interface", 1) == 0, "+X 端交通艇接口数=%d（=0）" % _role_count("dock_interface", 1))

	# 反射板根部结构 vs +X 端散热鳍：不得冲突
	var root_hw: Array = []
	for p in _parts:
		if String(p["role"]) in ["reflector_hinge", "reflector_strut", "reflector_actuator"]:
			root_hw.append(p)
	var fin_plus: Array = []
	for p in _role_parts("radiator"):
		if int(p["side"]) > 0:
			fin_plus.append(p)
	_check(root_hw.size() >= 36, "反射板根部结构零件数=%d（>=36）" % root_hw.size())
	_check(fin_plus.size() == 16, "+X 端散热鳍零件数=%d（=16）" % fin_plus.size())
	var hits: Array[String] = []
	var cand := 0
	for a in root_hw:
		for b in fin_plus:
			if not _aabb_touch(a, b, TOUCH_EPS):
				continue
			cand += 1
			if _parts_interfere(a, b, TOUCH_EPS):
				hits.append(_label(a) + " ∩ " + _label(b))
	_check(hits.is_empty(), "反射板根部结构（铰座/背撑/作动器）不与 +X 端散热鳍冲突（近邻 %d 对）%s" % [cand, "" if hits.is_empty() else "：" + _list_summary(hits)])
	print("[DATA] +X: mounts=%d fins=%d root_hw=%d near_pairs=%d" % [_role_count("endcap_mount", 1), fin_plus.size(), root_hw.size(), cand])


# ── [J] 数值 / AABB / 包围范围 ──────────────────────────────────────────────

func _section_sanity() -> void:
	var nan_parts: Array[String] = []
	var zero_parts: Array[String] = []
	var bounds_parts: Array[String] = []
	var point_bad: Array[String] = []
	var max_x := 0.0
	var max_rad := 0.0
	var bound_x: float = 6.0 * maxf(_scale, 0.001)
	var bound_r: float = 5.0 * maxf(_scale, 0.001)
	for p in _parts:
		var wa: AABB = p["aabb"]
		var ok_finite := _finite_v(wa.position) and _finite_v(wa.size) and _finite_v(wa.get_center())
		if not ok_finite:
			nan_parts.append(_label(p))
			continue
		if wa.size.x <= 1.0e-4 or wa.size.y <= 1.0e-4 or wa.size.z <= 1.0e-4:
			zero_parts.append(_label(p) + " size=" + str(wa.size))
		var bad := false
		for pt in p["points"]:
			if not _finite_v(pt):
				point_bad.append(_label(p))
				bad = true
				break
			max_x = maxf(max_x, absf(pt.x))
			max_rad = maxf(max_rad, _radial(pt))
			if absf(pt.x) > bound_x or _radial(pt) > bound_r:
				bounds_parts.append(_label(p) + " pt=" + str(pt))
				bad = true
				break
		if bad:
			continue
	_check(nan_parts.is_empty(), "无 NaN/Inf 世界 AABB：%s" % _list_summary(nan_parts))
	_check(zero_parts.is_empty(), "无零尺寸世界 AABB（3 轴均 >1e-4）：%s" % _list_summary(zero_parts))
	_check(point_bad.is_empty(), "采样点均为有限数值：%s" % _list_summary(point_bad))
	_check(bounds_parts.is_empty(), "全部部件在合理包围范围内（|x|<=%.1f, r<=%.1f）%s" % [bound_x, bound_r, _list_summary(bounds_parts)])
	_check(max_x <= bound_x and max_rad <= bound_r, "模型整体包围 |x|max=%.3f r_max=%.3f（限制 %.1f/%.1f）" % [max_x, max_rad, bound_x, bound_r])
	_check(_parts.size() > 0 and _fails >= 0, "采集部件数=%d" % _parts.size())
	print("[DATA] bounds |x|max=%.3f r_max=%.3f (%.2fL / %.2fL)" % [max_x, max_rad, max_x / maxf(_L() * _scale, 1.0e-6), max_rad / maxf(_L() * _scale, 1.0e-6)])
