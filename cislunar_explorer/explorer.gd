extends Node3D

## CISLUNAR EXPLORER · 地月系自由探索技术演示（CISLUNAR-UI-1）
##
## 视觉：V1 薄荷绿线框 / 1px 线 / 7–11pt 终端字体 / Palette；3D 全部用 ImmediateMesh 线段，
## 不使用任何贴图或 PBR 材质。HUD 由 ui/ce_hud.gd 绘制，本文件负责场景、相机、时间、选择、截图。
##
## 数据来源（诚实标注）：
##   * 若 `res://sim/cislunar_model.gd` 存在且 `sample(t)` 返回合法快照 → 使用模型数据
##     （HAZE 团队模型：惯性系 XY=月球轨道面；本文件转成场景 XZ 平面 +Y 向上显示）。
##   * 否则使用**公开常量占位**：地球半径 6,378.137 km、月球半径 1,737.4 km、地月距离
##     384,400 km、月球圆轨道 27.321661 d、GEO 42,164 km、月球同步环 ≈88,300 km，
##     L1–L5 由 CR3BP 共线方程数值求根 + L4/L5 ±60° 得到（不是手填假位置）。
##     HUD 明确标 `PLACEHOLDER CONSTANTS · sim/cislunar_model.gd NOT READY`。
##   * 展示口径：`EARTH-MOON CIRCULAR MODEL / CR3BP L-POINTS`；场景单位 1 unit = 1,000 km。
##
## 控制：
##   LMB 拖拽旋转（yaw/pitch）· RMB/MMB 拖拽平移 · 滚轮缩放
##   1 地球焦点 · 2 月球焦点 · 3 L1 焦点 · 4 选中对象焦点 · TAB 循环选择 · F 循环焦点
##   R 重置（相机/时间/速率）· SPACE 暂停/播放 · -/= 时间速率 1×/10×/100×/1000×
##   鼠标点击：左侧对象列表行 / 屏幕上的投影标签（就近 18px）选中
##
## 截图（headless 可启动；截图用窗口模式）：
##   DSH_CE_SHOT=<png> · DSH_CE_VIEW=earth|moon|l1|overview
##   可选 DSH_CE_TIME=<秒>、DSH_CE_SPEED=<1|10|100|1000>、DSH_CE_PAUSE=1
##   窗口固定 1920×1080 后在第 36 帧保存截图并退出。

const Pal := preload("res://scripts/pal.gd")
const UiFonts := preload("res://scripts/fonts.gd")
const MODEL_PATH := "res://sim/cislunar_model.gd"

# ── 占位常量（公开物理/几何数据；不是伪造状态）──────────────────
const KM_PER_UNIT := 1000.0
const R_EARTH_KM := 6378.137
const R_MOON_KM := 1737.4
const D_KM := 384400.0
const MU := 0.012150585
const T_MOON_S := 27.321661 * 86400.0
const GEO_R_KM := 42164.0
const MOON_SYNC_R_KM := 88300.0
const LUNAR_LEO_ALT_KM := 100.0
const T_GEO_S := 86164.0905

const SPEEDS := [1.0, 10.0, 100.0, 1000.0]
const FRAME_CAPTURE := 36

const FOCUS_EARTH := "earth"
const FOCUS_MOON := "moon"
const FOCUS_L1 := "l1"
const FOCUS_SELECTED := "selected"
const FOCUS_OVERVIEW := "overview"

var camera: Camera3D
var mesh_instance: MeshInstance3D
var hud: Control
var _line_material: StandardMaterial3D

var _model = null
var _model_ready := false
var _model_note := ""
var _source := "placeholder"

var _t := 0.0
var _speed_idx := 1
var _paused := false

# 相机（环绕焦点）
var _focus_mode := FOCUS_OVERVIEW
var _cam_yaw := deg_to_rad(-38.0)
var _cam_pitch := deg_to_rad(30.0)
var _cam_dist := 1080.0
var _cam_target := Vector3.ZERO
var _pan_offset := Vector3.ZERO
var _drag_left := false
var _drag_pan := false
var _press_pos := Vector2.ZERO
var _drag_moved := 0.0

var _selected_id := "l1_station"
var _object_order: Array[String] = []

# 数据（每帧刷新）
var _data: Dictionary = {}
var _objects: Array = []
var _circle_pts: Dictionary = {}
var _vm: Dictionary = {}

# 截图
var _shot_path := ""
var _shot_view := ""
var _frames := 0


func _ready() -> void:
	_build_material()
	camera = get_node_or_null("Camera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		add_child(camera)
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 30000.0
	camera.current = true
	mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		add_child(mesh_instance)
	hud = get_node_or_null("HUDLayer/HUD") as Control
	_shot_path = OS.get_environment("DSH_CE_SHOT")
	_shot_view = OS.get_environment("DSH_CE_VIEW")
	var tt := OS.get_environment("DSH_CE_TIME")
	if tt != "":
		_t = maxf(0.0, float(tt))
	var ss := OS.get_environment("DSH_CE_SPEED")
	if ss != "":
		var sv := float(ss)
		for i in range(SPEEDS.size()):
			if absf(float(SPEEDS[i]) - sv) < 0.5:
				_speed_idx = i
	if OS.get_environment("DSH_CE_PAUSE") == "1":
		_paused = true
	_load_model()
	_apply_view(_shot_view if _shot_view != "" else FOCUS_OVERVIEW)
	_refresh_data()
	_update_camera(1.0)
	_rebuild_mesh()
	# 视图预设等对象建好后立刻收敛相机，截图/启动首帧即构图正确
	_cam_target = _focus_position()
	_update_camera(1.0)
	_update_vm()
	if hud != null:
		hud.set_vm(_vm)
		hud.queue_redraw()
	if _shot_path != "":
		get_window().borderless = true
		get_window().size = Vector2i(1920, 1080)
		get_window().position = Vector2i(0, 0)
		print("[CE] SHOT mode path=%s view=%s t=%.1f model=%s objects=%d note=%s" % [
			_shot_path, _shot_view, _t, _source, _objects.size(), _model_note])
	else:
		print("[CE] boot t=%.1f view=%s model=%s objects=%d note=%s" % [
			_t, _focus_mode, _source, _objects.size(), _model_note])


# ═══════════════════════════════════════════════════════════════════
# 0. 模型装载 / 数据（模型优先；未就绪 → 公开常量占位）
# ═══════════════════════════════════════════════════════════════════

func _load_model() -> void:
	_model = null
	_model_ready = false
	_model_note = ""
	if not ResourceLoader.exists(MODEL_PATH):
		_model_note = "sim/cislunar_model.gd 未就绪 → 公开常量占位（非实时模型状态）"
		return
	var script = load(MODEL_PATH)
	if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
		_model_note = "sim/cislunar_model.gd 无法实例化 → 公开常量占位"
		return
	_model = script.new()
	if _model == null or not _model.has_method("sample"):
		_model_note = "sim/cislunar_model.gd 无 sample(t) → 公开常量占位"
		_model = null
		return
	_model_ready = true
	_model_note = "sim/cislunar_model.sample(t) 已接入（模型坐标 XY 轨道面 → 场景 XZ）"


func _refresh_data() -> void:
	if _model_ready:
		var raw = _model.call("sample", _t)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var adapted := _adapt_model(raw)
			if not adapted.is_empty():
				_data = adapted
				_source = "model"
				return
		_data = _placeholder_data(_t)
		_source = "placeholder"
		_model_note = "sim/cislunar_model.sample(t) 无效 → 公开常量占位"
		return
	_data = _placeholder_data(_t)
	_source = "placeholder"


# ── 模型坐标 (XY 轨道面, +Z 法向, km) → 场景 (XZ 轨道面, +Y 上, 1000 km/unit) ──
func _m2s(v: Variant) -> Vector3:
	var arr_in: Array = []
	if v is Vector3:
		arr_in = [v.x, v.y, v.z]
	elif v is Array and (v as Array).size() >= 3:
		arr_in = v as Array
	elif v is Dictionary:
		for k in ["position", "pos", "r", "position_km", "position_inertial_km", "center"]:
			if (v as Dictionary).has(k):
				return _m2s((v as Dictionary).get(k))
	if arr_in.size() < 3:
		return Vector3.ZERO
	# 模块坐标 z 是轨道法向 → 场景 y（上）；模块 y 面内 → 场景 z
	return Vector3(float(arr_in[0]), float(arr_in[2]), float(arr_in[1])) / KM_PER_UNIT


func _m2s_points(pts: Variant) -> Array:
	var out: Array = []
	if pts is Array:
		for raw in (pts as Array):
			out.append(_m2s(raw))
	return out


## 把模型 sample(t) 适配为内部统一数据：
##   earth/moon{pos,radius_km}；lagrange{L1..L5:{pos,period_s}}；
##   stations[{id,name,name_en,kind,pos,orbit_radius_km,period_s,note,lagrange_id,parent}]
##   rings[{id,name,name_en,points:[scene],radius_km,period_s,color}]
##   ports 归到 stations（kind="port"）。
func _adapt_model(raw: Dictionary) -> Dictionary:
	var earth_raw: Dictionary = (raw.get("earth", {}) as Dictionary) if raw.get("earth") is Dictionary else {}
	var moon_raw: Dictionary = (raw.get("moon", {}) as Dictionary) if raw.get("moon") is Dictionary else {}
	if not earth_raw.has("position") or not moon_raw.has("position"):
		return {}
	var cons: Dictionary = (raw.get("constants", {}) as Dictionary) if raw.get("constants") is Dictionary else {}
	var d := {
		"source": "model",
		"earth": {
			"pos": _m2s(earth_raw.get("position", [0, 0, 0])),
			"radius_km": float(earth_raw.get("radius_km", cons.get("earth_radius_km", R_EARTH_KM))),
		},
		"moon": {
			"pos": _m2s(moon_raw.get("position", [0, 0, 0])),
			"radius_km": float(moon_raw.get("radius_km", cons.get("moon_radius_km", R_MOON_KM))),
			"phase": float(moon_raw.get("phase_rad", 0.0)),
		},
		"constants": cons.duplicate(true),
		"lagrange": {},
		"stations": [],
		"rings": [],
	}
	var lag: Dictionary = raw.get("lagrange", {}) if raw.get("lagrange") is Dictionary else {}
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		if not lag.has(lid) or not (lag[lid] is Dictionary):
			continue
		var ld: Dictionary = lag[lid]
		(d["lagrange"] as Dictionary)[lid] = {
			"pos": _m2s(ld.get("position", [])),
			"distance_earth_km": float(ld.get("distance_earth_km", 0.0)),
			"distance_moon_km": float(ld.get("distance_moon_km", 0.0)),
			"period_s": T_MOON_S,
			"lagrange_type": String(ld.get("lagrange_type", "")),
		}
	# 站点
	var stations_raw: Array = raw.get("stations", []) if raw.get("stations") is Array else []
	for raw_st in stations_raw:
		if not (raw_st is Dictionary):
			continue
		var st: Dictionary = raw_st
		var sid := String(st.get("id", ""))
		var kind := String(st.get("kind", ""))
		if kind == "ring_station":
			continue   # 环对象由 rings 单独绘制
		var orbit: Dictionary = (st.get("orbit", {}) as Dictionary) if st.get("orbit") is Dictionary else {}
		var kind_out := "station"
		var note := ""
		match kind:
			"lagrange_station":
				kind_out = "l_station"
				note = "CR3BP L 点站 · 旋转系静止（共转）"
			"lunar_orbit_station":
				kind_out = "lunar_station"
				note = "月球轨道站 · %s° 倾角" % str(orbit.get("inclination_deg", 0.0))
			"port":
				kind_out = "port"
				note = "港口/地表标记"
			_:
				kind_out = "station"
		(d["stations"] as Array).append({
			"id": sid,
			"name": String(st.get("name", sid)),
			"name_en": _station_en(sid),
			"kind": kind_out,
			"pos": _m2s(st.get("position", [])),
			"orbit_radius_km": float(orbit.get("radius_km", 0.0)),
			"period_s": float(orbit.get("period_s", 0.0)),
			"inclination_deg": float(orbit.get("inclination_deg", 0.0)),
			"lagrange_id": String(st.get("lagrange_id", "")),
			"distance_earth_km": float(st.get("distance_earth_km", 0.0)),
			"distance_moon_km": float(st.get("distance_moon_km", 0.0)),
			"note": note,
			"parent": String(st.get("parent", "")),
		})
	# 环（GEO / 月球同步）：模型给采样点列 → 直接画折线
	var rings_raw: Dictionary = raw.get("rings", {}) if raw.get("rings") is Dictionary else {}
	for rid in ["geo", "lunar_sync"]:
		if not rings_raw.has(rid) or not (rings_raw[rid] is Dictionary):
			continue
		var rr: Dictionary = rings_raw[rid]
		var pts := _m2s_points(rr.get("points", []))
		if pts.is_empty():
			continue
		(d["rings"] as Array).append({
			"id": String(rr.get("id", rid)),
			"name": "地球静止环" if rid == "geo" else "月球同步环",
			"name_en": "GEO RING" if rid == "geo" else "LUNAR-SYNC RING",
			"points": pts,
			"radius_km": float(rr.get("radius_km", 0.0)),
			"period_s": float(rr.get("period_s", 0.0)),
			"color": "BLUE",
			"note": "圆轨道环（模型采样点列）",
		})
	# 月球轨道环（用 moon 位置 + 地月距离画圆即可）
	d["rings"].append({
		"id": "moon_orbit", "name": "月球轨道", "name_en": "LUNAR ORBIT",
		"center": Vector3.ZERO,
		"radius_km": float(cons.get("earth_moon_distance_km", D_KM)),
		"period_s": float(cons.get("moon_period_s", T_MOON_S)),
		"color": "PH_DIM", "note": "月球圆轨道（视觉参考）",
	})
	return d


func _station_en(sid: String) -> String:
	var map := {
		"l1_station": "L1 STATION", "l2_station": "L2 STATION",
		"l4_station": "L4 STATION", "l5_station": "L5 STATION",
		"lunar_leo": "LUNAR LEO", "lunar_polar": "LUNAR POLAR",
		"earth_port": "PORT / EARTH", "lunar_port": "PORT / MOON",
	}
	return String(map.get(sid, sid.to_upper()))


# ── 占位数据（公开常量；CR3BP 共线点数值求根）──────────────────

func _placeholder_data(t: float) -> Dictionary:
	var mu := MU
	var x1 := _collinear_root(-0.9, 0.9)
	var x2 := _collinear_root(1.0 - mu + 0.001, 2.2)
	var x3 := _collinear_root(-2.2, -mu - 0.001)
	var ang := TAU * fposmod(t, T_MOON_S) / T_MOON_S
	var ca := cos(ang)
	var sa := sin(ang)
	var moon_km := Vector3(D_KM * ca, 0.0, D_KM * sa)
	var rot_pts := {
		"L1": Vector3((x1 + mu) * D_KM, 0.0, 0.0),
		"L2": Vector3((x2 + mu) * D_KM, 0.0, 0.0),
		"L3": Vector3((x3 + mu) * D_KM, 0.0, 0.0),
		"L4": Vector3(0.5 * D_KM, 0.0, 0.5 * sqrt(3.0) * D_KM),
		"L5": Vector3(0.5 * D_KM, 0.0, -0.5 * sqrt(3.0) * D_KM),
	}
	var lag: Dictionary = {}
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		var rp: Vector3 = rot_pts[lid]
		var u := rp.x * ca - rp.z * sa
		var v := rp.x * sa + rp.z * ca
		var ip := Vector3(u, 0.0, v)
		lag[lid] = {
			"pos": ip / KM_PER_UNIT,
			"distance_earth_km": ip.length(),
			"distance_moon_km": ip.distance_to(moon_km),
			"period_s": T_MOON_S,
			"note": "CR3BP 平动点（无实体）",
		}
	var stations: Array = []
	for lid2 in ["L1", "L2", "L4", "L5"]:
		var lp: Dictionary = lag[lid2]
		stations.append({
			"id": "%s_station" % lid2.to_lower(), "name": "%s 站" % lid2,
			"name_en": "%s STATION" % lid2, "kind": "l_station",
			"pos": lp.get("pos", Vector3.ZERO),
			"orbit_radius_km": float(lp.get("distance_earth_km", 0.0)),
			"period_s": T_MOON_S, "lagrange_id": lid2,
			"note": "CR3BP L 点站（占位常量）", "parent": "earth",
		})
	# 月球轨道站（低轨 100 km / 极轨 90°）：占位展示
	var leo_r := R_MOON_KM + LUNAR_LEO_ALT_KM
	var leo_period := TAU * sqrt(pow(leo_r, 3.0) / 4902.800118)
	var leo_phase := 0.35
	var pol_phase := 1.10
	var leo_rel := Vector3(cos(leo_phase) * leo_r, 0.0, sin(leo_phase) * leo_r)
	var pol_rel := Vector3(cos(pol_phase) * leo_r, sin(pol_phase) * leo_r, 0.0)
	stations.append({"id": "lunar_leo", "name": "月球低轨站", "name_en": "LUNAR LEO",
		"kind": "lunar_station", "pos": _m2s(moon_km + leo_rel),
		"orbit_radius_km": leo_r, "period_s": leo_period, "inclination_deg": 0.0,
		"note": "月球轨道站（占位常量 100 km）", "parent": "moon"})
	stations.append({"id": "lunar_polar", "name": "月球极轨站", "name_en": "LUNAR POLAR",
		"kind": "lunar_station", "pos": _m2s(moon_km + pol_rel),
		"orbit_radius_km": leo_r, "period_s": leo_period, "inclination_deg": 90.0,
		"note": "月球极轨站（占位常量 90°）", "parent": "moon"})
	# 港口
	var ep_dir := Vector3(cos(deg_to_rad(28.0)), 0.0, sin(deg_to_rad(28.0)))
	var ep := ep_dir * (R_EARTH_KM + 20.0)
	var to_earth := (Vector3.ZERO - moon_km).normalized()
	var mp := moon_km + to_earth * (R_MOON_KM + 20.0)
	stations.append({"id": "earth_port", "name": "地球港", "name_en": "PORT / EARTH",
		"kind": "port", "pos": ep / KM_PER_UNIT, "orbit_radius_km": R_EARTH_KM + 20.0,
		"period_s": T_GEO_S, "note": "地表标记（占位常量）", "parent": "earth"})
	stations.append({"id": "lunar_port", "name": "月球港", "name_en": "PORT / MOON",
		"kind": "port", "pos": mp / KM_PER_UNIT, "orbit_radius_km": R_MOON_KM + 20.0,
		"period_s": T_MOON_S, "note": "近地面标记（占位常量）", "parent": "moon"})
	var rings: Array = [
		{"id": "moon_orbit", "name": "月球轨道", "name_en": "LUNAR ORBIT",
			"center": Vector3.ZERO, "radius_km": D_KM, "period_s": T_MOON_S,
			"color": "PH_DIM", "note": "月球圆轨道"},
		{"id": "geo_ring", "name": "GEO 环", "name_en": "GEO RING",
			"center": Vector3.ZERO, "radius_km": GEO_R_KM, "period_s": T_GEO_S,
			"color": "BLUE", "note": "地球静止环"},
		{"id": "lunar_sync_ring", "name": "月球同步环", "name_en": "LUNAR-SYNC",
			"center": moon_km / KM_PER_UNIT, "radius_km": MOON_SYNC_R_KM,
			"period_s": T_MOON_S, "color": "BLUE", "note": "月球同步环（占位常量）"},
	]
	return {
		"source": "placeholder",
		"constants": {"earth_radius_km": R_EARTH_KM, "moon_radius_km": R_MOON_KM,
			"earth_moon_distance_km": D_KM, "moon_period_s": T_MOON_S, "mu": MU},
		"earth": {"pos": Vector3.ZERO, "radius_km": R_EARTH_KM},
		"moon": {"pos": moon_km / KM_PER_UNIT, "radius_km": R_MOON_KM, "phase": ang},
		"lagrange": lag,
		"stations": stations,
		"rings": rings,
	}


func _cr3bp_x_accel(x: float, mu: float) -> float:
	var r1 := absf(x + mu)
	var r2 := absf(x - (1.0 - mu))
	if r1 < 1.0e-9 or r2 < 1.0e-9:
		return 0.0
	return x - (1.0 - mu) * (x + mu) / (r1 * r1 * r1) - mu * (x - (1.0 - mu)) / (r2 * r2 * r2)


func _collinear_root(a: float, b: float) -> float:
	var pa := a
	var pb := b
	var fa := _cr3bp_x_accel(pa, MU)
	for i in range(600):
		var mid := pa + (pb - pa) * float(i + 1) / 600.0
		var fm := _cr3bp_x_accel(mid, MU)
		if (fa <= 0.0 and fm >= 0.0) or (fa >= 0.0 and fm <= 0.0):
			var lo := pa
			var hi := mid
			for j in range(80):
				var m := (lo + hi) * 0.5
				var vm := _cr3bp_x_accel(m, MU)
				if (fa <= 0.0 and vm <= 0.0) or (fa >= 0.0 and vm >= 0.0):
					lo = m
				else:
					hi = m
			return (lo + hi) * 0.5
		pa = mid
		fa = fm
	return (a + b) * 0.5


# ═══════════════════════════════════════════════════════════════════
# 1. 场景几何（ImmediateMesh 线段；无贴图）
# ═══════════════════════════════════════════════════════════════════

func _build_material() -> void:
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_material.albedo_color = Color(1, 1, 1, 1)


func _col(name: String) -> Color:
	match name:
		"PH":
			return Pal.PH
		"PH_DIM":
			return Pal.PH_DIM
		"PH_FAINT":
			return Pal.PH_FAINT
		"BLUE":
			return Pal.BLUE
		"AMBER":
			return Pal.AMBER
		"RED":
			return Pal.RED
		"ID_SUSPECT":
			return Pal.ID_SUSPECT
		"DIM":
			return Pal.DIM
		"GRID":
			return Pal.GRID
		"TXT":
			return Pal.TXT
		_:
			return Pal.PH


## 统一对象列表（投影标签/列表/点击/选中都用它）：
##   L1–L5：优先用模型站（l1_station…），无站则用平动点；然后环、月轨站、地球/月球、港口。
func _build_objects() -> void:
	_objects = []
	var lag: Dictionary = _data.get("lagrange", {})
	var stations: Array = _data.get("stations", [])
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		var st := _find_station_by_lagrange(stations, lid)
		if not st.is_empty():
			var stk := st.duplicate(true)
			stk["kind_label"] = "L-STATION"
			stk["color"] = "AMBER"
			stk["model_kind"] = "l_station"
			stk["modules"] = ["核心舱 CORE", "居住舱 HAB×2", "推进储罐 TANK×2",
				"对接桁架 TRUSS", "散热板 RADIATOR×2", "太阳翼 SOLAR×2",
				"通信桅杆 COMMS", "停泊港 DOCK×2"]
			stk["ports"] = ["DOCK-A", "DOCK-B"]
			stk["visual_text"] = "视觉尺度 ~2.8 units（非实体尺寸，仅可视化）"
			stk["status_text"] = "NOMINAL · 共转系静止（技术演示，无碰撞/对接物理）"
			_objects.append(stk)
			continue
		if not lag.has(lid):
			continue
		var lp: Dictionary = lag[lid]
		_objects.append({
			"id": lid, "name": "%s 平动点" % lid, "name_en": lid,
			"kind": "l_point", "kind_label": "L-POINT",
			"pos": lp.get("pos", Vector3.ZERO),
			"orbit_radius_km": float(lp.get("distance_earth_km", 0.0)),
			"radius_km": 0.0, "period_s": float(lp.get("period_s", T_MOON_S)),
			"color": "AMBER",
			"note": "CR3BP 平动点（无实体）· 随月球共转",
			"distance_earth_km": float(lp.get("distance_earth_km", 0.0)),
			"distance_moon_km": float(lp.get("distance_moon_km", 0.0)),
		})
	for raw in (_data.get("rings", []) as Array):
		var r: Dictionary = raw
		_objects.append({
			"id": String(r.get("id", "")), "name": String(r.get("name", "")),
			"name_en": String(r.get("name_en", "")),
			"kind": "ring", "kind_label": "RING",
			"pos": _ring_marker(r), "orbit_radius_km": float(r.get("radius_km", 0.0)),
			"radius_km": float(r.get("radius_km", 0.0)),
			"period_s": float(r.get("period_s", 0.0)),
			"color": String(r.get("color", "BLUE")),
			"note": String(r.get("note", "圆轨道环")),
			"ring": r,
		})
	for raw2 in stations:
		var s: Dictionary = raw2
		var k := String(s.get("kind", ""))
		if k != "lunar_station":
			continue
		var s2 := s.duplicate(true)
		s2["kind_label"] = "LUNAR-STATION"
		s2["color"] = "BLUE"
		s2["model_kind"] = "lunar_station"
		s2["modules"] = ["核心舱 CORE", "电池组 BAT×2", "太阳翼 SOLAR×2",
			"通信桅杆 COMMS", "姿控推进 RCS"]
		s2["ports"] = ["DOCK-L1"]
		s2["visual_text"] = "视觉尺度 ~1.1 units（非实体尺寸）"
		s2["status_text"] = "NOMINAL · 月球轨道站（技术演示）"
		_objects.append(s2)
	var earth: Dictionary = _data.get("earth", {})
	var moon: Dictionary = _data.get("moon", {})
	_objects.append({
		"id": "earth", "name": "地球", "name_en": "EARTH",
		"kind": "body", "kind_label": "BODY",
		"pos": earth.get("pos", Vector3.ZERO), "radius_km": float(earth.get("radius_km", R_EARTH_KM)),
		"period_s": T_GEO_S, "color": "PH", "note": "线框球 · 1 unit = 1,000 km",
	})
	_objects.append({
		"id": "moon", "name": "月球", "name_en": "MOON",
		"kind": "body", "kind_label": "BODY",
		"pos": moon.get("pos", Vector3.ZERO), "radius_km": float(moon.get("radius_km", R_MOON_KM)),
		"period_s": T_MOON_S, "color": "PH_DIM", "note": "线框球 · 圆轨道近似",
	})
	for raw3 in stations:
		var p: Dictionary = raw3
		if String(p.get("kind", "")) != "port":
			continue
		var p2 := p.duplicate(true)
		p2["kind_label"] = "PORT"
		p2["color"] = "ID_SUSPECT"
		p2["model_kind"] = "port"
		p2["modules"] = ["系泊平台 PLATFORM", "系泊臂 ARM×2", "推进剂储罐 TANK×2",
			"信标塔 BEACON", "航道标记 APPROACH×4"]
		p2["ports"] = ["BERTH-1", "BERTH-2"]
		p2["visual_text"] = "视觉尺度 ~2.4 units（非实体尺寸）"
		p2["status_text"] = "OPEN · 技术演示（无碰撞/对接物理）"
		_objects.append(p2)

	# ── 技术演示舰船（视觉几何；位置相对真实站/港，非 sim 航迹）─────────
	var st_by_id: Dictionary = {}
	for raw_s in stations:
		if raw_s is Dictionary:
			st_by_id[String((raw_s as Dictionary).get("id", ""))] = raw_s
	var ep: Dictionary = st_by_id.get("earth_port", {})
	if not ep.is_empty():
		var ep_pos: Vector3 = ep.get("pos", Vector3.ZERO)
		var earth_dir := ep_pos.normalized() if ep_pos.length() > 1.0e-6 else Vector3.RIGHT
		var tan := Vector3.UP.cross(earth_dir).normalized()
		var fpos := ep_pos + earth_dir * 0.80 + tan * 0.42 + Vector3(0.0, 0.22, 0.0)
		_objects.append({
			"id": "ship_freighter", "name": "HAZE-1 补给船", "name_en": "HAZE-1 FREIGHTER",
			"kind": "ship", "kind_label": "SHIP", "pos": fpos,
			"radius_km": 0.0, "period_s": 0.0, "color": "PH_DIM", "model_kind": "ship_freighter",
			"modules": ["舰体 HULL", "货舱 CARGO×3", "推进段 ENGINE×2", "舰桥 BRIDGE",
				"姿控 RCS", "通信桅杆 COMMS"],
			"ports": ["BERTH-E1"],
			"visual_text": "舰体视觉长度 ~2.6 units（技术演示，非实体尺寸）",
			"status_text": "DOCKED · 地球港外泊位（技术演示，无对接物理）",
			"parent_id": "earth_port",
			"note": "技术演示船 · 位置相对地球港（视觉偏移，非 sim 航迹）",
		})
	var l1r: Dictionary = st_by_id.get("l1_station", {})
	if not l1r.is_empty():
		var l1p: Vector3 = l1r.get("pos", Vector3.ZERO)
		var e_dir := (-l1p).normalized() if l1p.length() > 1.0e-6 else Vector3.LEFT
		var tan2 := Vector3.UP.cross(e_dir).normalized()
		var cpos := l1p + tan2 * 4.2 + Vector3(0.0, 0.9, 0.0) + e_dir * 0.6
		_objects.append({
			"id": "ship_corvette", "name": "KESTREL 巡逻舰", "name_en": "KESTREL CORVETTE",
			"kind": "ship", "kind_label": "SHIP", "pos": cpos,
			"radius_km": 0.0, "period_s": 0.0, "color": "BLUE", "model_kind": "ship_corvette",
			"modules": ["舰体 HULL", "推进段 ENGINE×2", "传感器桅杆 SENSOR",
				"散热板 RADIATOR×2", "任务舱 MISSION", "通信桅杆 COMMS"],
			"ports": ["BERTH-L1"],
			"visual_text": "舰体视觉长度 ~1.9 units（技术演示，非实体尺度）",
			"status_text": "STATION KEEPING · L1 站泊位外（技术演示）",
			"parent_id": "l1_station",
			"note": "技术演示船 · 位置相对 L1 站（视觉偏移，非 sim 航迹）",
		})
	var mp: Dictionary = st_by_id.get("lunar_port", {})
	if not mp.is_empty():
		var mp_pos: Vector3 = mp.get("pos", Vector3.ZERO)
		var m_dir := mp_pos.normalized() if mp_pos.length() > 1.0e-6 else Vector3.RIGHT
		var tan3 := Vector3.UP.cross(m_dir).normalized()
		var tpos := mp_pos + m_dir * 0.26 + tan3 * 0.18 + Vector3(0.0, 0.10, 0.0)
		_objects.append({
			"id": "ship_tug", "name": "月港拖船 S-03", "name_en": "MOONPORT TUG S-03",
			"kind": "ship", "kind_label": "SHIP", "pos": tpos,
			"radius_km": 0.0, "period_s": 0.0, "color": "PH", "model_kind": "ship_tug",
			"modules": ["舰体 HULL", "推进段 ENGINE×2", "拖曳绞盘 WINCH", "驾驶舱 BRIDGE"],
			"ports": ["BERTH-M1"],
			"visual_text": "舰体视觉长度 ~1.2 units（技术演示，非实体尺寸）",
			"status_text": "DOCKED · 月球港（技术演示）",
			"parent_id": "lunar_port",
			"note": "技术演示船 · 位置相对月球港（视觉偏移，非 sim 航迹）",
		})
	_object_order = []
	for o in _objects:
		_object_order.append(String((o as Dictionary).get("id", "")))


func _find_station_by_lagrange(stations: Array, lid: String) -> Dictionary:
	for raw in stations:
		if raw is Dictionary and String((raw as Dictionary).get("lagrange_id", "")) == lid:
			return raw
	return {}


func _ring_marker(r: Dictionary) -> Vector3:
	if r.has("points") and (r.get("points", []) as Array).size() > 0:
		return (r.get("points", []) as Array)[0]
	var c: Vector3 = r.get("center", Vector3.ZERO)
	return c + Vector3(float(r.get("radius_km", 0.0)) / KM_PER_UNIT, 0.0, 0.0)


func _rebuild_mesh() -> void:
	if mesh_instance == null:
		return
	_build_objects()
	var verts: Array = []
	# 环
	for raw in (_data.get("rings", []) as Array):
		var r: Dictionary = raw
		var col := _col(String(r.get("color", "BLUE")))
		if r.has("points"):
			var pts: Array = r.get("points", [])
			for i in range(pts.size()):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[(i + 1) % pts.size()]
				_add_line(verts, a, b, col, 0.60)
				if i % 4 == 0:
					var radial := (a - _ring_center(r)).normalized()
					_add_line(verts, a, a + radial * 1.8, col, 0.45)
		else:
			var center: Vector3 = r.get("center", Vector3.ZERO)
			var rad := float(r.get("radius_km", 0.0)) / KM_PER_UNIT
			var a2 := 0.48 if String(r.get("id", "")) == "moon_orbit" else 0.58
			_add_circle(verts, center, rad, col, 128, a2)
			var ticks := 18 if String(r.get("id", "")) == "moon_orbit" else 12
			for i in range(ticks):
				var ang := TAU * float(i) / float(ticks)
				var dirv := Vector3(cos(ang), 0.0, sin(ang))
				_add_line(verts, center + dirv * rad, center + dirv * (rad + 1.8), col, 0.45)
	# 线框球（真实半径）+ 远近自适应目标环（不放大实体，只让中心可见）
	var earth: Dictionary = _data.get("earth", {})
	var moon: Dictionary = _data.get("moon", {})
	_add_wire_sphere(verts, earth.get("pos", Vector3.ZERO),
		float(earth.get("radius_km", R_EARTH_KM)) / KM_PER_UNIT, 0.16, Pal.PH)
	_add_wire_sphere(verts, moon.get("pos", Vector3.ZERO),
		float(moon.get("radius_km", R_MOON_KM)) / KM_PER_UNIT, 0.32, Pal.PH_DIM)
	_add_body_reticle(verts, earth.get("pos", Vector3.ZERO), Pal.PH)
	_add_body_reticle(verts, moon.get("pos", Vector3.ZERO), Pal.PH_DIM)
	# 月轨站轨道圈（低轨/极轨）
	for o in _objects:
		var ob: Dictionary = o
		if String(ob.get("kind", "")) == "lunar_station":
			var inc := float(ob.get("inclination_deg", 0.0))
			var rr := float(ob.get("orbit_radius_km", 0.0)) / KM_PER_UNIT
			_add_orbit_ring(verts, moon.get("pos", Vector3.ZERO), rr, inc, _col("BLUE"), 0.20)
	# 对象标记 / R3-MODEL 模块化几何（近距 detail，远距剪影 LOD）
	var detail := _cam_dist < 55.0
	for o2 in _objects:
		var ob2: Dictionary = o2
		match String(ob2.get("kind", "")):
			"l_station":
				_draw_station_model(verts, ob2, detail)
			"l_point":
				_add_octahedron(verts, ob2.get("pos", Vector3.ZERO), 1.2, _col("AMBER"), 0.50)
			"lunar_station":
				_draw_lunar_station_model(verts, ob2, detail)
			"port":
				_draw_port_model(verts, ob2, detail)
			"ship":
				_draw_ship_model(verts, ob2, detail)
			_:
				pass
	# 选中高亮十字（有模型的站体/港口/舰船用短十字，避免压住模块细节）
	for o3 in _objects:
		if String((o3 as Dictionary).get("id", "")) != _selected_id:
			continue
		var p: Vector3 = (o3 as Dictionary).get("pos", Vector3.ZERO)
		var col2 := _col(String((o3 as Dictionary).get("color", "PH")))
		var s2 := 3.4
		if String((o3 as Dictionary).get("model_kind", "")) != "":
			s2 = 0.55
		_add_line(verts, p + Vector3(s2, 0, 0), p + Vector3(s2 * 1.7, 0, 0), col2, 0.9)
		_add_line(verts, p - Vector3(s2, 0, 0), p - Vector3(s2 * 1.7, 0, 0), col2, 0.9)
		_add_line(verts, p + Vector3(0, s2, 0), p + Vector3(0, s2 * 1.7, 0), col2, 0.7)
		_add_line(verts, p - Vector3(0, s2, 0), p - Vector3(0, s2 * 1.7, 0), col2, 0.7)
		_add_line(verts, p + Vector3(0, 0, s2), p + Vector3(0, 0, s2 * 1.7), col2, 0.7)
		_add_line(verts, p - Vector3(0, 0, s2), p - Vector3(0, 0, s2 * 1.7), col2, 0.7)
	var im := ImmediateMesh.new()
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for pair in verts:
		var vc: Array = pair
		im.surface_set_color(vc[1])
		im.surface_add_vertex(vc[0])
	im.surface_end()
	mesh_instance.mesh = im


func _ring_center(r: Dictionary) -> Vector3:
	if r.has("center"):
		return r.get("center", Vector3.ZERO)
	if r.has("points") and (r.get("points", []) as Array).size() > 0:
		var sum := Vector3.ZERO
		for p in (r.get("points", []) as Array):
			sum += p
		return sum / float((r.get("points", []) as Array).size())
	return Vector3.ZERO


func _add_line(arr: Array, a: Vector3, b: Vector3, col: Color, alpha: float) -> void:
	var c := col
	c.a = alpha
	arr.append([a, c])
	arr.append([b, c])


func _add_circle(arr: Array, center: Vector3, radius: float, col: Color, segments: int, alpha: float) -> void:
	if radius <= 0.0:
		return
	var prev := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, segments + 1):
		var ang := TAU * float(i) / float(segments)
		var p := center + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
		_add_line(arr, prev, p, col, alpha)
		prev = p


func _add_orbit_ring(arr: Array, center: Vector3, radius: float, inc_deg: float,
		col: Color, alpha: float) -> void:
	if radius <= 0.0:
		return
	var inc := deg_to_rad(inc_deg)
	var prev := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, 97):
		var a := TAU * float(i) / 96.0
		var local := Vector3(cos(a) * radius, sin(a) * radius * sin(inc), sin(a) * radius * cos(inc))
		var p := center + local
		_add_line(arr, prev, p, col, alpha)
		prev = p


func _add_wire_sphere(arr: Array, center: Vector3, radius: float, alpha: float, col: Color) -> void:
	if radius <= 0.0:
		return
	for lat_deg in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var lat := deg_to_rad(lat_deg)
		_add_circle(arr, center + Vector3(0.0, radius * sin(lat), 0.0),
			radius * cos(lat), col, 48, alpha)
	for i in range(6):
		var ang := PI * float(i) / 6.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var prev := center + dir * radius
		for j in range(1, 33):
			var t := TAU * float(j) / 32.0
			var p := center + dir * (radius * cos(t)) + Vector3(0.0, radius * sin(t), 0.0)
			_add_line(arr, prev, p, col, alpha * 0.8)
			prev = p


func _add_body_reticle(arr: Array, center: Vector3, col: Color) -> void:
	# 屏幕尺寸近似恒定的目标环/十字：半径随相机距离缩放，不改变实体真实半径
	var s := maxf(2.2, _cam_dist * 0.014)
	_add_line(arr, center + Vector3(s, 0, 0), center + Vector3(s * 1.6, 0, 0), col, 0.55)
	_add_line(arr, center - Vector3(s, 0, 0), center - Vector3(s * 1.6, 0, 0), col, 0.55)
	_add_line(arr, center + Vector3(0, s, 0), center + Vector3(0, s * 1.6, 0), col, 0.45)
	_add_line(arr, center - Vector3(0, s, 0), center - Vector3(0, s * 1.6, 0), col, 0.45)
	# 斜向四点小环
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		var d := Vector3(cos(ang), sin(ang), 0.0) * s
		var d2 := Vector3(cos(ang + TAU / 4.0), sin(ang + TAU / 4.0), 0.0) * s
		_add_line(arr, center + d, center + d2, col, 0.30)


func _add_octahedron(arr: Array, center: Vector3, s: float, col: Color, alpha: float) -> void:
	var pts := [Vector3(s, 0, 0), Vector3(-s, 0, 0), Vector3(0, s, 0),
		Vector3(0, -s, 0), Vector3(0, 0, s), Vector3(0, 0, -s)]
	var edges := [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5],
		[2, 4], [4, 3], [3, 5], [5, 2]]
	for e in edges:
		_add_line(arr, center + (pts[e[0]] as Vector3), center + (pts[e[1]] as Vector3), col, alpha)


func _add_port_marker(arr: Array, center: Vector3, col: Color) -> void:
	var s := 1.6
	_add_line(arr, center + Vector3(0, s, 0), center + Vector3(s, -s, 0), col, 0.85)
	_add_line(arr, center + Vector3(0, s, 0), center + Vector3(-s, -s, 0), col, 0.85)
	_add_line(arr, center + Vector3(-s, -s, 0), center + Vector3(s, -s, 0), col, 0.85)
	_add_line(arr, center, center + Vector3(0, s * 1.8, 0), col, 0.40)


# ═══════════════════════════════════════════════════════════════════
# R3-MODEL：可见模块化线框几何（纯视觉层；不实现碰撞/对接物理）
#   * 全部 ImmediateMesh 1px 线段，无贴图；V1 色板。
#   * 尺寸为**视觉尺度**（单位=1,000 km 的场景单位），不是实体物理尺寸；
#     近距（相机 <55 units）画完整模块，远距画简化剪影（LOD）。
#   * 站体/港口位置仍来自 sim/cislunar_model.sample(t)；舰船为技术演示船，
#     位置相对真实港/站做视觉偏移（非 sim 航迹）。
# ═══════════════════════════════════════════════════════════════════

## 站体本地坐标：fwd = 轨道切向，up = 场景天顶，right = fwd×up。
func _model_axes(obj: Dictionary) -> Array:
	var p: Vector3 = obj.get("pos", Vector3.ZERO)
	var fwd := Vector3.RIGHT
	if p.length() > 1.0e-6:
		fwd = Vector3(-p.z, 0.0, p.x).normalized()
	if fwd.length() < 1.0e-6:
		fwd = Vector3.RIGHT
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length() < 1.0e-6:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	return [right, up, fwd]


func _perp_axes(axis: Vector3) -> Array:
	var f := axis.normalized()
	if f.length() < 1.0e-6:
		f = Vector3.RIGHT
	var hint := Vector3.UP
	if absf(f.dot(hint)) > 0.95:
		hint = Vector3.RIGHT
	var r := f.cross(hint).normalized()
	var u := r.cross(f).normalized()
	return [r, u, f]


func _add_path(arr: Array, pts: Array, col: Color, alpha: float) -> void:
	for i in range(1, pts.size()):
		_add_line(arr, pts[i - 1], pts[i], col, alpha)


func _add_box(arr: Array, center: Vector3, axes: Array, size: Vector3,
		col: Color, alpha: float) -> void:
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var fwd: Vector3 = axes[2]
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(center + right * hx * sx + up * hy * sy + fwd * hz * sz)
	var edges := [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6],
		[3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]
	for e in edges:
		_add_line(arr, corners[e[0]], corners[e[1]], col, alpha)


func _add_circle_face(arr: Array, center: Vector3, normal: Vector3, radius: float,
		segments: int, col: Color, alpha: float) -> void:
	if radius <= 0.0:
		return
	var ax := _perp_axes(normal)
	var r: Vector3 = ax[0]
	var u: Vector3 = ax[1]
	var pts: Array = []
	for i in range(segments + 1):
		var ang := TAU * float(i) / float(segments)
		pts.append(center + (r * cos(ang) + u * sin(ang)) * radius)
	_add_path(arr, pts, col, alpha)


func _add_cylinder_wire(arr: Array, a: Vector3, b: Vector3, radius: float,
		segments: int, col: Color, alpha: float) -> void:
	if radius <= 0.0 or a.distance_to(b) < 1.0e-6:
		return
	var ax := _perp_axes(b - a)
	var r: Vector3 = ax[0]
	var u: Vector3 = ax[1]
	var ra: Array = []
	var rb: Array = []
	for i in range(segments + 1):
		var ang := TAU * float(i) / float(segments)
		var off := (r * cos(ang) + u * sin(ang)) * radius
		ra.append(a + off)
		rb.append(b + off)
	_add_path(arr, ra, col, alpha)
	_add_path(arr, rb, col, alpha)
	for i in range(0, segments, maxi(1, segments / 4)):
		_add_line(arr, ra[i], rb[i], col, alpha * 0.8)


func _add_panel(arr: Array, center: Vector3, right: Vector3, up: Vector3,
		w: float, h: float, gx: int, gy: int, col: Color, alpha: float) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	var hw := w * 0.5
	var hh := h * 0.5
	var c := [
		center - right * hw - up * hh, center + right * hw - up * hh,
		center + right * hw + up * hh, center - right * hw + up * hh,
	]
	for i in range(4):
		_add_line(arr, c[i], c[(i + 1) % 4], col, alpha)
	for i in range(1, gx):
		var t := float(i) / float(gx)
		_add_line(arr, c[0].lerp(c[1], t), c[3].lerp(c[2], t), col, alpha * 0.5)
	for j in range(1, gy):
		var t2 := float(j) / float(gy)
		_add_line(arr, c[0].lerp(c[3], t2), c[1].lerp(c[2], t2), col, alpha * 0.5)


func _add_truss(arr: Array, a: Vector3, b: Vector3, half_w: float, up_hint: Vector3,
		col: Color, alpha: float, rungs: int) -> void:
	var axis := b - a
	if axis.length() < 1.0e-6:
		return
	var ax := _perp_axes(axis)
	var r: Vector3 = ax[0]
	var u := up_hint - axis.normalized() * up_hint.dot(axis.normalized())
	if u.length() < 1.0e-6:
		u = ax[1]
	u = u.normalized()
	var offsets := [r * half_w + u * half_w, -r * half_w + u * half_w,
		-r * half_w - u * half_w, r * half_w - u * half_w]
	for off in offsets:
		_add_line(arr, a + off, b + off, col, alpha)
	var n := maxi(2, rungs)
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		for k in range(4):
			_add_line(arr, p + (offsets[k] as Vector3), p + (offsets[(k + 1) % 4] as Vector3),
				col, alpha * 0.6)
		# 斜撑（交替方向，V1 桁架感）
		var sgn := 1.0 if i % 2 == 0 else -1.0
		_add_line(arr, p + (offsets[0] as Vector3),
			p.lerp(b, t + 1.0 / float(n)) + (offsets[2] as Vector3) * sgn, col, alpha * 0.4)


func _add_dish(arr: Array, center: Vector3, normal: Vector3, radius: float,
		col: Color, alpha: float) -> void:
	var ax := _perp_axes(normal)
	_add_circle_face(arr, center, normal, radius, 14, col, alpha)
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		var r: Vector3 = ax[0]
		var u: Vector3 = ax[1]
		var rim := center + (r * cos(ang) + u * sin(ang)) * radius
		_add_line(arr, center, rim, col, alpha * 0.7)
	_add_line(arr, center, center + normal.normalized() * radius * 1.3, col, alpha)


func _add_marker_cross(arr: Array, p: Vector3, size: float, col: Color, alpha: float) -> void:
	_add_line(arr, p - Vector3(size, 0, 0), p + Vector3(size, 0, 0), col, alpha)
	_add_line(arr, p - Vector3(0, size, 0), p + Vector3(0, size, 0), col, alpha)
	_add_line(arr, p - Vector3(0, 0, size), p + Vector3(0, 0, size), col, alpha)


## L1–L5 站：核心舱/居住舱/储罐/桁架/太阳翼/散热板/通信桅杆/停泊港。
func _draw_station_model(arr: Array, obj: Dictionary, detail: bool) -> void:
	var p: Vector3 = obj.get("pos", Vector3.ZERO)
	var ax := _model_axes(obj)
	var right: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var fwd: Vector3 = ax[2]
	var col := _col("AMBER")
	var id := String(obj.get("id", ""))
	var s := 1.0
	if id == "l2_station":
		s = 0.9
	elif id == "l4_station" or id == "l5_station":
		s = 0.82
	_add_marker_cross(arr, p, 0.18 * s, col, 0.85)
	if not detail:
		# LOD-1：远距剪影（仍可见，不是单点）
		_add_box(arr, p, ax, Vector3(0.5, 0.4, 2.0) * s, col, 0.8)
		_add_line(arr, p - right * 1.35 * s, p + right * 1.35 * s, col, 0.6)
		for side in [-1.0, 1.0]:
			_add_box(arr, p + right * side * 1.35 * s, ax,
				Vector3(0.06, 0.55, 0.95) * s, col, 0.55)
		_add_line(arr, p + up * 0.2 * s, p + up * 1.3 * s, col, 0.6)
		return
	# 核心舱（沿 fwd）+ 端盖环
	var core_a := p - fwd * 1.05 * s
	var core_b := p + fwd * 1.05 * s
	_add_cylinder_wire(arr, core_a, core_b, 0.20 * s, 10, col, 0.9)
	for t in [0.0, 0.5, 1.0]:
		_add_circle_face(arr, core_a.lerp(core_b, t), fwd, 0.22 * s, 10, col, 0.55)
	# 居住舱 ×2（左右）
	for side in [-1.0, 1.0]:
		var hb: Vector3 = p + right * side * 0.55 * s + up * 0.04 * s
		_add_cylinder_wire(arr, hb - fwd * 0.42 * s, hb + fwd * 0.42 * s,
			0.26 * s, 8, col, 0.8)
		_add_circle_face(arr, hb + fwd * 0.42 * s, fwd, 0.26 * s, 8, col, 0.55)
		_add_box(arr, p + right * side * 0.32 * s, ax,
			Vector3(0.22, 0.16, 0.18) * s, col, 0.65)
	# 推进储罐 ×2（上方）
	for side2 in [-1.0, 1.0]:
		var tp: Vector3 = p + right * side2 * 0.34 * s + up * 0.46 * s - fwd * 0.25 * s
		_add_cylinder_wire(arr, tp - right * 0.28 * s, tp + right * 0.28 * s,
			0.20 * s, 8, col, 0.7)
		_add_circle_face(arr, tp, right, 0.20 * s, 8, col, 0.5)
	# 对接桁架（横向）
	var ta := p - right * 1.35 * s + fwd * 0.45 * s
	var tb := p + right * 1.35 * s + fwd * 0.45 * s
	_add_truss(arr, ta, tb, 0.11 * s, up, col, 0.7, 6)
	# 太阳翼（桁架两端，fwd/up 平面）
	for side3 in [-1.0, 1.0]:
		var wb: Vector3 = p + right * side3 * 1.62 * s + fwd * 0.45 * s
		_add_panel(arr, wb + fwd * 0.25 * s, fwd, up, 0.85 * s, 0.55 * s, 3, 2, col, 0.65)
		_add_panel(arr, wb - fwd * 0.30 * s, fwd, up, 0.85 * s, 0.55 * s, 3, 2, col, 0.65)
		_add_line(arr, wb, wb + right * side3 * 0.28 * s, col, 0.6)
	# 散热板 ×2（上方，fwd/up 平面）
	for side4 in [-0.42, 0.42]:
		_add_panel(arr, p + right * side4 * s + up * 0.95 * s, fwd, right,
			0.75 * s, 0.5 * s, 2, 2, col, 0.5)
	# 通信桅杆 + 天线
	var mast_a := p + up * 0.25 * s
	var mast_b := p + up * 1.30 * s + fwd * 0.15 * s
	_add_line(arr, mast_a, mast_b, col, 0.8)
	_add_dish(arr, mast_b + up * 0.10 * s, fwd, 0.20 * s, col, 0.7)
	_add_line(arr, mast_b, mast_b + up * 0.28 * s, col, 0.55)
	# 端部停泊港 ×2（法向 fwd / -fwd）
	for end in [-1.0, 1.0]:
		var dp: Vector3 = p + fwd * end * 1.15 * s
		_add_circle_face(arr, dp, fwd * end, 0.30 * s, 10, col, 0.8)
		_add_circle_face(arr, dp + fwd * end * 0.18 * s, fwd * end, 0.16 * s, 8, col, 0.55)
		for k in range(4):
			var ang2 := TAU * float(k) / 4.0
			var rax := _perp_axes(fwd * end)
			var rv: Vector3 = rax[0]
			var uv: Vector3 = rax[1]
			_add_line(arr, dp + (rv * cos(ang2) + uv * sin(ang2)) * 0.16 * s,
				dp + (rv * cos(ang2) + uv * sin(ang2)) * 0.30 * s, col, 0.55)
	# 停泊的小型舱段
	_add_box(arr, p + fwd * 1.42 * s, ax, Vector3(0.24, 0.20, 0.34) * s, col, 0.6)


## 地球港/月球港：系泊平台环 + 系泊臂 + 储罐 + 信标塔 + 航道标记。
func _draw_port_model(arr: Array, obj: Dictionary, detail: bool) -> void:
	var p: Vector3 = obj.get("pos", Vector3.ZERO)
	var ax := _model_axes(obj)
	var right: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var fwd: Vector3 = ax[2]
	var col := _col("ID_SUSPECT")
	var s := 1.0
	_add_marker_cross(arr, p, 0.2, col, 0.8)
	if not detail:
		_add_circle_face(arr, p, up, 1.2, 20, col, 0.75)
		_add_line(arr, p, p + up * 1.3, col, 0.7)
		for side in [-1.0, 1.0]:
			_add_line(arr, p + right * side * 1.2, p + right * side * 1.2 + fwd * 2.6, col, 0.45)
		return
	# 平台环 + 内环 + 辐条
	_add_circle_face(arr, p, up, 1.15 * s, 20, col, 0.85)
	_add_circle_face(arr, p, up, 0.42 * s, 12, col, 0.6)
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var d := right * cos(ang) + fwd * sin(ang)
		_add_line(arr, p + d * 0.42 * s, p + d * 1.15 * s, col, 0.6)
	# 中央信标塔
	_add_cylinder_wire(arr, p - up * 0.1, p + up * 1.25 * s, 0.13 * s, 8, col, 0.8)
	_add_box(arr, p + up * 1.33 * s, ax, Vector3(0.18, 0.14, 0.18) * s, col, 0.9)
	for i2 in range(4):
		var ang2 := TAU * float(i2) / 4.0
		var d2 := right * cos(ang2) + fwd * sin(ang2)
		_add_line(arr, p + up * 1.40 * s, p + up * 1.40 * s + d2 * 0.30 * s + up * 0.12 * s, col, 0.5)
	# 储罐 ×2（平台外侧）
	for side2 in [-1.0, 1.0]:
		var tp: Vector3 = p + right * side2 * 0.78 * s
		_add_cylinder_wire(arr, tp - up * 0.24 * s, tp + up * 0.24 * s, 0.24 * s, 8, col, 0.7)
		_add_circle_face(arr, tp + up * 0.24 * s, up, 0.24 * s, 8, col, 0.5)
	# 系泊臂 ×2（外伸，带端部缓冲环）
	for side3 in [-1.0, 1.0]:
		var arm_end: Vector3 = p + right * side3 * 1.55 * s + fwd * 0.35 * s + up * 0.15 * s
		_add_line(arr, p + right * side3 * 1.05 * s, arm_end, col, 0.85)
		_add_line(arr, p + right * side3 * 1.05 * s + up * 0.18 * s,
			arm_end + up * 0.18 * s, col, 0.6)
		_add_line(arr, p + right * side3 * 1.05 * s - up * 0.18 * s,
			arm_end - up * 0.18 * s, col, 0.6)
		_add_circle_face(arr, arm_end, fwd, 0.22 * s, 10, col, 0.7)
		for k2 in range(3):
			_add_line(arr, arm_end, arm_end + right * side3 * (0.10 + 0.08 * float(k2)), col, 0.5)
	# 航道：两条平行引导线 + 人字标记 + 航道灯标
	var corr_a := p + up * 0.4 * s + fwd * 1.4 * s
	for side4 in [-1.0, 1.0]:
		_add_line(arr, corr_a + right * side4 * 0.55 * s,
			corr_a + fwd * 1.7 * s + right * side4 * 0.55 * s, col, 0.55)
	for i3 in range(3):
		var c := corr_a + fwd * (0.45 + 0.50 * float(i3))
		_add_line(arr, c - right * 0.55 * s, c + right * 0.30 * s + fwd * 0.18 * s, col, 0.45)
		_add_line(arr, c + right * 0.55 * s, c + right * 0.30 * s + fwd * 0.18 * s, col, 0.45)
		_add_marker_cross(arr, c + right * 0.78 * s, 0.10, col, 0.5)


## 月球低轨/极轨站：小型模块（核心舱 + 电池 + 太阳翼 + 天线）。
func _draw_lunar_station_model(arr: Array, obj: Dictionary, detail: bool) -> void:
	var p: Vector3 = obj.get("pos", Vector3.ZERO)
	var ax := _model_axes(obj)
	var right: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var fwd: Vector3 = ax[2]
	var col := _col("BLUE")
	_add_marker_cross(arr, p, 0.12, col, 0.8)
	if not detail:
		_add_box(arr, p, ax, Vector3(0.28, 0.22, 0.85), col, 0.8)
		_add_line(arr, p - right * 0.75, p + right * 0.75, col, 0.6)
		return
	_add_cylinder_wire(arr, p - fwd * 0.42, p + fwd * 0.42, 0.11, 8, col, 0.9)
	_add_circle_face(arr, p + fwd * 0.42, fwd, 0.12, 8, col, 0.6)
	for side in [-1.0, 1.0]:
		_add_box(arr, p + right * side * 0.22 + up * 0.06, ax,
			Vector3(0.20, 0.13, 0.24), col, 0.6)
		_add_panel(arr, p + right * side * 0.62, fwd, up, 0.62, 0.32, 2, 1, col, 0.55)
		_add_line(arr, p, p + right * side * 0.62, col, 0.5)
	_add_cylinder_wire(arr, p + up * 0.18, p + up * 0.38, 0.07, 6, col, 0.6)
	_add_dish(arr, p + up * 0.42, fwd, 0.10, col, 0.65)


## 舰船：低模线框舰体 + 推进段 + 传感器桅杆（3 种尺度；技术演示几何）。
func _draw_ship_model(arr: Array, obj: Dictionary, detail: bool) -> void:
	var p: Vector3 = obj.get("pos", Vector3.ZERO)
	var ax := _model_axes(obj)
	var right: Vector3 = ax[0]
	var up: Vector3 = ax[1]
	var fwd: Vector3 = ax[2]
	var mk := String(obj.get("model_kind", "ship_freighter"))
	var col := _col(String(obj.get("color", "PH")))
	_add_marker_cross(arr, p, 0.10, col, 0.85)
	if not detail:
		_add_box(arr, p, ax, Vector3(0.45, 0.30, 1.8), col, 0.85)
		_add_line(arr, p + up * 0.15, p + up * 0.9, col, 0.65)
		_add_line(arr, p - fwd * 0.9, p - fwd * 1.2, col, 0.5)
		return
	match mk:
		"ship_corvette":
			_draw_hull(arr, p, right, up, fwd, 1.9, 0.34, 0.26, col, true)
			_add_engine_pair(arr, p, right, up, fwd, 0.95, 0.13, col)
			_add_box(arr, p + fwd * 0.35 + up * 0.20, ax, Vector3(0.22, 0.16, 0.42), col, 0.7)
			_add_line(arr, p + up * 0.12, p + up * 0.85, col, 0.8)
			_add_dish(arr, p + up * 0.88 + fwd * 0.10, fwd, 0.16, col, 0.7)
			for side in [-1.0, 1.0]:
				_add_panel(arr, p + right * side * 0.42 - fwd * 0.15, fwd, up,
					0.55, 0.34, 2, 1, col, 0.55)
				_add_line(arr, p, p + right * side * 0.42, col, 0.55)
			_add_line(arr, p - fwd * 0.95, p - fwd * 0.95 + up * 0.12, col, 0.5)
		"ship_tug":
			_draw_hull(arr, p, right, up, fwd, 1.05, 0.38, 0.26, col, false)
			_add_engine_pair(arr, p, right, up, fwd, 0.55, 0.12, col)
			_add_box(arr, p + fwd * 0.18 + up * 0.20, ax, Vector3(0.20, 0.15, 0.26), col, 0.7)
			_add_circle_face(arr, p - fwd * 0.18 + up * 0.05, right, 0.20, 10, col, 0.7)
			_add_circle_face(arr, p - fwd * 0.18 + up * 0.05, right, 0.10, 8, col, 0.5)
			_add_line(arr, p + up * 0.10, p + up * 0.48, col, 0.65)
		_:
			# HAZE-1 补给船：长舰体 + 3 货舱 + 双推进 + 舰桥 + 桅杆
			_draw_hull(arr, p, right, up, fwd, 2.55, 0.52, 0.38, col, false)
			for i in range(3):
				var off := -0.62 + 0.52 * float(i)
				_add_box(arr, p + fwd * off + up * 0.32, ax,
					Vector3(0.36, 0.22, 0.40), col, 0.6)
			_add_engine_pair(arr, p, right, up, fwd, 1.30, 0.17, col)
			_add_box(arr, p + fwd * 0.92 + up * 0.30, ax, Vector3(0.34, 0.26, 0.42), col, 0.8)
			_add_line(arr, p + fwd * 0.92 + up * 0.42, p + fwd * 0.92 + up * 1.0, col, 0.7)
			_add_dish(arr, p + fwd * 0.92 + up * 1.02, fwd, 0.14, col, 0.65)
			for side in [-1.0, 1.0]:
				_add_panel(arr, p + right * side * 0.62 - fwd * 0.35, fwd, up,
					0.72, 0.38, 2, 1, col, 0.5)
				_add_line(arr, p, p + right * side * 0.62 - fwd * 0.35, col, 0.5)
			_add_line(arr, p + up * 0.2, p + up * 0.55, col, 0.55)


## 舰体：箱式主体 + 舰艏收束线 + 尾部框。
func _draw_hull(arr: Array, p: Vector3, right: Vector3, up: Vector3, fwd: Vector3,
		length: float, beam: float, height: float, col: Color, sharp: bool) -> void:
	var hl := length * 0.5
	var hb := beam * 0.5
	var hh := height * 0.5
	var corners: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			corners.append(p + right * hb * sx + up * hh * sy)
	var front: Array = []
	for sx2 in [-1.0, 1.0]:
		for sy2 in [-1.0, 1.0]:
			front.append(p + fwd * hl + right * hb * 0.75 * sx2 + up * hh * 0.75 * sy2)
	var nose := p + fwd * (hl + (0.55 if sharp else 0.35))
	for i in range(4):
		_add_line(arr, corners[i] - fwd * hl, corners[i] + fwd * hl, col, 0.9)
		_add_line(arr, corners[i] + fwd * (hl - 0.04), front[i], col, 0.7)
		_add_line(arr, front[i], nose, col, 0.55)
	for i in range(4):
		_add_line(arr, corners[i] - fwd * hl, corners[(i + 1) % 4] - fwd * hl, col, 0.9)
		_add_line(arr, front[i], front[(i + 1) % 4], col, 0.8)
	_add_line(arr, p + up * hh, p + up * hh + fwd * hl, col, 0.4)


## 双推进段 + 喷管（锥形线框）+ 尾焰虚线。
func _add_engine_pair(arr: Array, p: Vector3, right: Vector3, up: Vector3, fwd: Vector3,
		hl: float, radius: float, col: Color) -> void:
	for side in [-1.0, 1.0]:
		var off: Vector3 = right * side * radius * 1.4 + up * 0.02
		var a: Vector3 = p - fwd * (hl - 0.18) + off
		var b: Vector3 = p - fwd * (hl + 0.30) + off
		_add_cylinder_wire(arr, a, b, radius * 0.6, 8, col, 0.75)
		_add_circle_face(arr, b, fwd, radius, 10, col, 0.8)
		_add_circle_face(arr, b, fwd, radius * 0.55, 8, col, 0.6)
		for k in range(4):
			var ang := TAU * float(k) / 4.0
			var ax2 := _perp_axes(fwd)
			var rv: Vector3 = ax2[0]
			var uv: Vector3 = ax2[1]
			var d := (rv * cos(ang) + uv * sin(ang))
			_add_line(arr, b + d * radius * 0.55, b + d * radius, col, 0.55)
		_add_line(arr, b, b - fwd * 0.35, col, 0.3)


# ═══════════════════════════════════════════════════════════════════
# 2. 相机（自由环绕 / 平移 / 缩放 / 焦点）
# ═══════════════════════════════════════════════════════════════════

func _focus_position() -> Vector3:
	match _focus_mode:
		FOCUS_EARTH:
			return (_data.get("earth", {}) as Dictionary).get("pos", Vector3.ZERO)
		FOCUS_MOON:
			return (_data.get("moon", {}) as Dictionary).get("pos", Vector3.ZERO)
		FOCUS_L1:
			for o in _objects:
				if String((o as Dictionary).get("id", "")) == "l1_station" \
						or String((o as Dictionary).get("id", "")) == "L1":
					return o.get("pos", Vector3.ZERO)
			return Vector3.ZERO
		FOCUS_SELECTED:
			var so := _selected_object()
			return so.get("pos", Vector3.ZERO) if not so.is_empty() else Vector3.ZERO
		_:
			return (_data.get("moon", {}) as Dictionary).get("pos", Vector3.ZERO) * 0.5


func _focus_distance(mode: String) -> float:
	match mode:
		FOCUS_EARTH:
			return 150.0
		FOCUS_MOON:
			return 90.0
		FOCUS_L1:
			return 130.0
		FOCUS_SELECTED:
			var o := _selected_object()
			if o.is_empty():
				return 260.0
			var kind := String(o.get("kind", ""))
			if kind == "body":
				return maxf(60.0, float(o.get("radius_km", 0.0)) / KM_PER_UNIT * 12.0)
			if kind == "ring":
				return maxf(80.0, float(o.get("radius_km", 0.0)) / KM_PER_UNIT * 2.4)
			if kind == "l_station":
				return 8.5
			if kind == "lunar_station":
				return 5.5
			if kind == "port":
				return 7.5
			if kind == "ship":
				return 6.5
			if kind == "l_point":
				return 40.0
			return 30.0
		_:
			return 860.0


func _apply_view(mode: String) -> void:
	match mode:
		"earth":
			_selected_id = "earth"
			_set_focus(FOCUS_EARTH)
		"moon":
			_selected_id = "moon"
			_set_focus(FOCUS_MOON)
		"l1":
			_selected_id = "l1_station"
			_set_focus(FOCUS_L1)
		"station":
			_selected_id = "l1_station"
			_set_focus(FOCUS_SELECTED)
		"port":
			_selected_id = "earth_port"
			_set_focus(FOCUS_SELECTED)
		"ship":
			_selected_id = "ship_freighter"
			_set_focus(FOCUS_SELECTED)
		"overview", "":
			_selected_id = "l1_station"
			_set_focus(FOCUS_OVERVIEW)
		_:
			if _object_order.has(mode):
				_selected_id = mode
				_set_focus(FOCUS_SELECTED)
			else:
				_set_focus(FOCUS_OVERVIEW)
	_cam_pitch = deg_to_rad(30.0 if mode != "overview" else 34.0)
	_cam_yaw = deg_to_rad(-38.0)
	if mode == "station" or mode == "port" or mode == "ship":
		_cam_pitch = deg_to_rad(18.0)
		_cam_yaw = deg_to_rad(-34.0)
		_cam_dist = {"station": 9.0, "port": 8.0, "ship": 8.5}.get(mode, 8.0)


func _set_focus(mode: String) -> void:
	_focus_mode = mode
	_cam_dist = _focus_distance(mode)
	_pan_offset = Vector3.ZERO


func _update_camera(delta: float) -> void:
	var want := _focus_position() + _pan_offset
	var k := clampf(delta * 7.0, 0.0, 1.0)
	if _cam_target.length() < 1.0e-6:
		_cam_target = want
	else:
		_cam_target = _cam_target.lerp(want, k)
	var cp := cos(_cam_pitch)
	var sp := sin(_cam_pitch)
	var dir := Vector3(cp * sin(_cam_yaw), sp, cp * cos(_cam_yaw))
	if camera == null:
		return
	camera.position = _cam_target + dir * _cam_dist
	camera.look_at(_cam_target, Vector3.UP)


func _selected_object() -> Dictionary:
	for o in _objects:
		if String((o as Dictionary).get("id", "")) == _selected_id:
			return o
	return {}


func _select(id: String) -> void:
	if id == "":
		return
	for o in _objects:
		if String((o as Dictionary).get("id", "")) == id:
			_selected_id = id
			_update_vm()
			return


func _cycle_selection(dir: int = 1) -> void:
	if _object_order.is_empty():
		return
	var i := _object_order.find(_selected_id)
	i = (i + dir + _object_order.size()) % _object_order.size()
	_selected_id = _object_order[i]
	_update_vm()


func _cycle_focus() -> void:
	var modes := [FOCUS_OVERVIEW, FOCUS_EARTH, FOCUS_MOON, FOCUS_L1, FOCUS_SELECTED]
	var i := modes.find(_focus_mode)
	_set_focus(String(modes[(i + 1) % modes.size()]))


func reset_view() -> void:
	_t = 0.0
	_speed_idx = 1
	_paused = false
	_selected_id = "l1_station"
	_focus_mode = FOCUS_OVERVIEW
	_cam_yaw = deg_to_rad(-38.0)
	_cam_pitch = deg_to_rad(34.0)
	_cam_dist = _focus_distance(FOCUS_OVERVIEW)
	_cam_target = Vector3.ZERO
	_pan_offset = Vector3.ZERO
	_refresh_data()


# ═══════════════════════════════════════════════════════════════════
# 3. 每帧 / HUD view-model / 截图
# ═══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_frames += 1
	if not _paused:
		_t += delta * float(SPEEDS[_speed_idx])
	_refresh_data()
	_update_camera(delta)
	_rebuild_mesh()
	_update_vm()
	if hud != null:
		hud.set_vm(_vm)
		hud.queue_redraw()
	if _shot_path != "" and _frames >= FRAME_CAPTURE:
		_capture_and_quit()


func rebuild_vm() -> void:
	_update_vm()
	if hud != null:
		hud.set_vm(_vm)
		hud.queue_redraw()


func _update_vm() -> void:
	var earth_km := ((_data.get("earth", {}) as Dictionary).get("pos", Vector3.ZERO) as Vector3) * KM_PER_UNIT
	var moon_km := ((_data.get("moon", {}) as Dictionary).get("pos", Vector3.ZERO) as Vector3) * KM_PER_UNIT
	var objs: Array = []
	for raw in _objects:
		var o: Dictionary = raw
		var pos: Vector3 = o.get("pos", Vector3.ZERO)
		var screen := Vector2(-9999.0, -9999.0)
		var on_screen := false
		if camera != null and not camera.is_position_behind(pos):
			screen = camera.unproject_position(pos)
			on_screen = screen.x > 0.0 and screen.y > 0.0 and screen.x < 1920.0 and screen.y < 1080.0
		var sel := String(o.get("id", "")) == _selected_id
		var kind := String(o.get("kind", ""))
		var name := String(o.get("name", ""))
		var en := String(o.get("name_en", ""))
		var label_txt := name
		if kind == "body":
			label_txt = name
		elif kind == "ring":
			label_txt = name
		elif kind == "l_station" or kind == "l_point":
			label_txt = en
		elif kind == "port" or kind == "ship":
			label_txt = name
		else:
			label_txt = "%s · %s" % [en, name]
		if sel:
			label_txt = "▣ " + label_txt
		objs.append({
			"id": String(o.get("id", "")),
			"name": name,
			"name_en": en,
			"label": label_txt,
			"kind": kind,
			"kind_label": String(o.get("kind_label", "")),
			"color": _col(String(o.get("color", "PH"))),
			"screen": screen,
			"on_screen": on_screen,
			"selected": sel,
			"radius_km": float(o.get("radius_km", 0.0)),
		})
	var sel_obj := _selected_object()
	var selected: Dictionary = {}
	if not sel_obj.is_empty():
		var pos_scene: Vector3 = sel_obj.get("pos", Vector3.ZERO)
		var pos_km := pos_scene * KM_PER_UNIT
		var kind2 := String(sel_obj.get("kind", ""))
		var period_s := float(sel_obj.get("period_s", 0.0))
		var radius_text := "—"
		var orbit_r := float(sel_obj.get("orbit_radius_km", 0.0))
		match kind2:
			"body":
				radius_text = "实体半径 %.1f km" % float(sel_obj.get("radius_km", 0.0))
			"ring":
				radius_text = "环半径 %.1f km" % orbit_r
			"l_station":
				radius_text = "站体模型 · 轨道 %.0f km" % orbit_r
			"lunar_station":
				radius_text = "站体模型 · 轨道 %.0f km" % orbit_r
			"port":
				radius_text = "港口平台（视觉模型）"
			"ship":
				radius_text = "视觉模型（非实体尺寸）"
			_:
				radius_text = "无实体（平动点）"
		var period_text := "—"
		if period_s > 0.0:
			period_text = "%.3f d（%.0f s）" % [period_s / 86400.0, period_s]
			if kind2 == "ring" and String(sel_obj.get("id", "")) == "geo_ring":
				period_text = "地球恒星日 23h56m04s（%.2f h）" % (period_s / 3600.0)
		var note := String(sel_obj.get("note", ""))
		if _source == "placeholder":
			note += " · 占位常量（模型未就绪）"
		selected = {
			"id": String(sel_obj.get("id", "")),
			"name": String(sel_obj.get("name", "")),
			"name_en": String(sel_obj.get("name_en", "")),
			"kind": String(sel_obj.get("kind_label", kind2)),
			"color": _col(String(sel_obj.get("color", "PH"))),
			"radius_text": radius_text,
			"period_text": period_text,
			"dist_earth_text": "%.0f km" % pos_km.distance_to(earth_km),
			"dist_moon_text": "%.0f km" % pos_km.distance_to(moon_km),
			"modules": (sel_obj.get("modules", []) as Array).duplicate(),
			"ports": (sel_obj.get("ports", []) as Array).duplicate(),
			"visual_text": String(sel_obj.get("visual_text", "")),
			"status_text": String(sel_obj.get("status_text", "")),
			"model_kind": String(sel_obj.get("model_kind", "")),
			"parent_id": String(sel_obj.get("parent_id", "")),
			"note": note,
		}
	_vm = {
		"t": _t,
		"speed": SPEEDS[_speed_idx],
		"paused": _paused,
		"focus": _focus_mode,
		"source": _source,
		"model_note": _model_note,
		"objects": objs,
		"selected": selected,
	}


# ═══════════════════════════════════════════════════════════════════
# 4. 输入
# ═══════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist * 0.88, 3.0, 4000.0)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist * 1.12, 3.0, 4000.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_left = mb.pressed
			if mb.pressed:
				_press_pos = mb.position
				_drag_moved = 0.0
			else:
				if _drag_moved < 6.0:
					_click_select(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_pan = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
			return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag_left:
			_drag_moved += mm.relative.length()
			_cam_yaw = fposmod(_cam_yaw - mm.relative.x * 0.005, TAU)
			_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.004,
				deg_to_rad(-80.0), deg_to_rad(80.0))
			return
		if _drag_pan:
			_drag_moved += mm.relative.length()
			if camera != null:
				var basis := camera.global_transform.basis
				var scale := _cam_dist * 0.0016
				_pan_offset -= basis.x * mm.relative.x * scale + basis.y * mm.relative.y * scale
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var kk: InputEventKey = event
		match kk.keycode:
			KEY_1:
				_set_focus(FOCUS_EARTH)
			KEY_2:
				_set_focus(FOCUS_MOON)
			KEY_3:
				_set_focus(FOCUS_L1)
			KEY_4:
				_set_focus(FOCUS_SELECTED)
			KEY_R:
				reset_view()
			KEY_SPACE:
				_paused = not _paused
			KEY_TAB:
				_cycle_selection(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_speed_idx = maxi(0, _speed_idx - 1)
			KEY_EQUAL, KEY_KP_ADD:
				_speed_idx = mini(SPEEDS.size() - 1, _speed_idx + 1)
			KEY_F:
				_cycle_focus()
			KEY_5:
				_apply_view("station")
			KEY_6:
				_apply_view("ship")
			KEY_7:
				_apply_view("port")


func _click_select(pos: Vector2) -> void:
	if hud != null and hud.has_method("row_at"):
		var rid := String(hud.call("row_at", pos))
		if rid != "":
			_select(rid)
			return
	var best := ""
	var best_d := 18.0
	for o in _objects:
		var p := _project(o.get("pos", Vector3.ZERO))
		if p.x < 0.0:
			continue
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = String((o as Dictionary).get("id", ""))
	if best != "":
		_select(best)


func _project(pos: Vector3) -> Vector2:
	if camera == null or camera.is_position_behind(pos):
		return Vector2(-9999, -9999)
	return camera.unproject_position(pos)


# ═══════════════════════════════════════════════════════════════════
# 5. 截图
# ═══════════════════════════════════════════════════════════════════

func _capture_and_quit() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("[CE] SHOT %s err=%d view=%s t=%.1f source=%s objects=%d → %s" % [
		str(img.get_size()), err, _shot_view, _t, _source, _objects.size(), _shot_path])
	get_tree().quit(0 if err == OK else 1)
