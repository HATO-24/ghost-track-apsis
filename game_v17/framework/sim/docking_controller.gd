# R6-DOCKING-1 · 交会/对接几何控制器（纯模型，不接 UI/world/物理积分）
#
# 职责：
#   - 端口模型（站体/舰船端口：位置/朝向/半径/类型/状态/兼容性）
#   - 接近走廊（轴向/横向/角度/接近速度；复用 cislunar_physics.approach_corridor_check）
#   - 相对制导（建议 Δv / 姿态指向 / 距离/速度门限；不执行物理）
#   - 对接判定（轴向/横向/对齐角/接触速度；失败原因；docked 后可 undock）
#   - 显式状态机：far/approach/corridor/hold/alignment/final/docked/aborted/failed
#
# 坐标/单位：LVLH（R/S/W 或协议由调用方保证），位置 km、速度 km/s、角度 deg；
# 相对状态 rel 约定为 `rel_pos = target - chaser`、`rel_vel = target_vel - chaser_vel`
# （与 cislunar_physics.relative_state 一致）。port_axis 为端口朝外方向。
# 本文件只读调用 cislunar_physics 的纯数学函数，不写 world/state/tracks/physics。

extends RefCounted

const Physics := preload("res://framework/sim/cislunar_physics.gd")

const SCHEMA := "v17_docking.v1"
const PORT_SCHEMA := "v17_docking_port.v1"
const SNAPSHOT_SCHEMA := "v17_docking_snapshot.v1"
const STATES: Array[String] = ["far", "approach", "corridor", "hold", "alignment",
	"final", "docked", "aborted", "failed"]
const TERMINAL_STATES: Array[String] = ["docked", "aborted", "failed"]

static func default_config() -> Dictionary:
	return {
	"far_km": 250.0,
	"align_range_km": 2.0,
	"final_km": 0.25,
	"hold_range_km": 5.0,
	"contact_tol_km": 0.05,
	"final_standoff_km": 0.02,
	"align_tol_deg": 5.0,
	"align_lateral_km": 0.2,
	"hard_align_deg": 15.0,
	"hard_lateral_km": 0.5,
	"hard_max_closing_mps": 2.0,
	"final_closing_mps": 0.5,
	"dock_speed_mps": 0.1,
	"guidance_max_dv_mps": 3.0,
	"guidance_base_closing_mps": 0.5,
	"guidance_range_gain": 0.02,
	"guidance_lateral_gain": 0.5,
	"guidance_max_closing_mps": 5.0,
	"corridor": Physics.default_corridor_spec(),
	"docking": Physics.default_docking_spec(),
}

var ports: Array = []
var target_port_id := ""
var state := "far"
var cfg: Dictionary = {}
var errors: Array[String] = []
var events: Array = []
var last: Dictionary = {}

var _t := 0.0
var _hold_requested := false
var _hold_reason := ""
var _failure_reason := ""
var _docked_t := -1.0
var _undocked_t := -1.0
var _selected_port: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════
# 0. 端口模型
# ═══════════════════════════════════════════════════════════════════

## 构造端口定义（静态；id/owner/kind/axis 必填）。
static func make_port(port_id: String, owner_id: String, kind: String, axis: Variant,
		radius_m := 2.4, opts := {}) -> Dictionary:
	var ax := Physics.to_vec3(axis, Vector3.RIGHT)
	if ax.length() < 1.0e-9:
		ax = Vector3.RIGHT
	ax = ax.normalized()
	var o: Dictionary = opts if opts is Dictionary else {}
	return {
		"schema": PORT_SCHEMA,
		"port_id": port_id,
		"owner_id": owner_id,
		"owner_kind": String(o.get("owner_kind", "station")),
		"kind": kind,
		"axis": Physics.vec3_to_array(ax),
		"radius_m": maxf(0.0, float(radius_m)),
		"status": String(o.get("status", "open")),
		"compatible": (o.get("compatible", ["ship"]) as Array).duplicate() if o.get("compatible", ["ship"]) is Array else ["ship"],
		"name": String(o.get("name", port_id)),
		"meta": (o.get("meta", {}) as Dictionary).duplicate(true) if o.get("meta", {}) is Dictionary else {},
	}


## 默认端口集（L1 Chronos 站/储罐 + 本舰/旗舰舰体；只做模型样例，不写 world）。
static func default_ports() -> Array:
	return [
		make_port("chronos-dock-a", "chronos_station", "dock", [1.0, 0.0, 0.0], 2.4,
			{"owner_kind": "station", "name": "Chronos DOCK-A · 主对接环", "status": "open",
			 "compatible": ["ship"], "meta": {"side": "outer", "truss": "A"}}),
		make_port("chronos-dock-b", "chronos_station", "dock", [-1.0, 0.0, 0.0], 2.4,
			{"owner_kind": "station", "name": "Chronos DOCK-B · 辅助对接环", "status": "occupied",
			 "compatible": ["ship"], "meta": {"side": "outer", "truss": "B"}}),
		make_port("chronos-berth-1", "tank_farm", "berth", [0.0, 0.0, 1.0], 3.2,
			{"owner_kind": "tank", "name": "Chronos 储罐停泊位", "status": "damaged",
			 "compatible": ["ship"], "meta": {"side": "nadir"}}),
		make_port("harmattan-port", "harmattan", "dock", [-1.0, 0.0, 0.0], 1.2,
			{"owner_kind": "ship", "name": "哈马丹主对接环", "status": "open",
			 "compatible": ["ship"], "meta": {"side": "fore"}}),
	]


func _init() -> void:
	cfg = default_config()
	errors = []
	events = []
	last = {}
	state = "far"


## 初始化端口与配置；ports 为空使用默认端口集。返回 true 表示可用。
func setup(ports_in: Array = [], opts := {}) -> bool:
	errors.clear()
	ports.clear()
	cfg = default_config()
	if opts is Dictionary:
		cfg = _merge(cfg, opts)
	var source: Array = ports_in if ports_in is Array and not ports_in.is_empty() else default_ports()
	for raw in source:
		var p := _normalize_port(raw)
		if p.is_empty():
			errors.append("invalid_port:" + str(raw))
			continue
		if _find_port(String(p.get("port_id", ""))).is_empty():
			ports.append(p)
		else:
			errors.append("duplicate_port:" + String(p.get("port_id", "")))
	_validate_cfg()
	target_port_id = ""
	state = "far"
	last = {}
	events.clear()
	_t = 0.0
	_hold_requested = false
	_hold_reason = ""
	_failure_reason = ""
	_docked_t = -1.0
	_undocked_t = -1.0
	_selected_port = {}
	return errors.is_empty() and not ports.is_empty()


func _validate_cfg() -> void:
	if float(cfg.get("far_km", 0.0)) <= 0.0:
		errors.append("cfg:far_km")
	if float(cfg.get("align_range_km", 0.0)) <= 0.0:
		errors.append("cfg:align_range_km")
	if float(cfg.get("final_km", 0.0)) <= 0.0:
		errors.append("cfg:final_km")
	if float(cfg.get("align_tol_deg", 0.0)) <= 0.0:
		errors.append("cfg:align_tol_deg")
	if float(cfg.get("guidance_max_dv_mps", 0.0)) <= 0.0:
		errors.append("cfg:guidance_max_dv_mps")


func _deep_copy(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


func _merge(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in overlay.keys():
		var key := String(k)
		if out.get(key) is Dictionary and overlay[k] is Dictionary:
			out[key] = _merge(out[key], overlay[k])
		else:
			out[key] = overlay[k]
	return out


func _normalize_port(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var p: Dictionary = (raw as Dictionary).duplicate(true)
	var pid := String(p.get("port_id", p.get("id", ""))).strip_edges()
	var owner := String(p.get("owner_id", "")).strip_edges()
	var kind := String(p.get("kind", "dock")).strip_edges()
	if pid == "" or owner == "":
		return {}
	var axis := Physics.to_vec3(p.get("axis", [1.0, 0.0, 0.0]), Vector3.RIGHT)
	if axis.length() < 1.0e-9:
		return {}
	var status := String(p.get("status", "open"))
	if not status in ["open", "occupied", "damaged", "closed"]:
		status = "open"
	var compatible: Array = []
	var raw_comp = p.get("compatible", ["ship"])
	if raw_comp is Array:
		for c in raw_comp:
			compatible.append(String(c))
	elif raw_comp is String:
		compatible = [String(raw_comp)]
	if compatible.is_empty():
		compatible = ["ship"]
	return {
		"schema": PORT_SCHEMA,
		"port_id": pid,
		"owner_id": owner,
		"owner_kind": String(p.get("owner_kind", "station")),
		"kind": kind,
		"axis": Physics.vec3_to_array(axis.normalized()),
		"radius_m": maxf(0.0, float(p.get("radius_m", 2.4))),
		"status": status,
		"compatible": compatible,
		"name": String(p.get("name", pid)),
		"meta": (p.get("meta", {}) as Dictionary).duplicate(true) if p.get("meta", {}) is Dictionary else {},
	}


func _find_port(port_id: String) -> Dictionary:
	for raw in ports:
		var p: Dictionary = raw
		if String(p.get("port_id", "")) == port_id:
			return p.duplicate(true)
	return {}


func add_port(raw: Variant) -> Dictionary:
	var p := _normalize_port(raw)
	if p.is_empty():
		return {"ok": false, "reason": "invalid_port"}
	if not _find_port(String(p.get("port_id", ""))).is_empty():
		return {"ok": false, "reason": "duplicate_port", "port_id": String(p.get("port_id", ""))}
	ports.append(p)
	events.append({"t": _t, "kind": "port_added", "text": String(p.get("port_id", ""))})
	return {"ok": true, "port": p}


func remove_port(port_id: String) -> Dictionary:
	for i in range(ports.size()):
		var p: Dictionary = ports[i]
		if String(p.get("port_id", "")) == port_id:
			ports.remove_at(i)
			if target_port_id == port_id:
				target_port_id = ""
				_selected_port = {}
				_transition("far", "target_port_removed")
			return {"ok": true, "port_id": port_id}
	return {"ok": false, "reason": "unknown_port"}


## 选择目标端口：优先显式 port_id；否则可选 owner_id 下第一个 open 且兼容 ship 的端口。
func select_target_port(port_id := "", owner_id := "", chaser_kind := "ship") -> Dictionary:
	if state == "docked":
		return {"ok": false, "reason": "docked_undock_first"}
	if port_id != "":
		var p := _find_port(port_id)
		if p.is_empty():
			return {"ok": false, "reason": "unknown_port", "port_id": port_id}
		if not _compatible(p, chaser_kind):
			return {"ok": false, "reason": "incompatible_port", "port_id": port_id,
				"compatible": (p.get("compatible", []) as Array)}
		if String(p.get("status", "")) != "open":
			return {"ok": false, "reason": "port_" + String(p.get("status", "closed")), "port_id": port_id}
		return _apply_target(p)
	var best: Dictionary = {}
	for raw in ports:
		var p: Dictionary = raw
		if owner_id != "" and String(p.get("owner_id", "")) != owner_id:
			continue
		if String(p.get("status", "")) != "open":
			continue
		if not _compatible(p, chaser_kind):
			continue
		best = p
		break
	if best.is_empty():
		return {"ok": false, "reason": "no_open_port"}
	return _apply_target(best)


func _compatible(p: Dictionary, chaser_kind: String) -> bool:
	var comp: Array = p.get("compatible", []) if p.get("compatible", []) is Array else []
	return comp.has(chaser_kind) or comp.has("ship") and chaser_kind == "ship" or comp.has("*")


func _apply_target(p: Dictionary) -> Dictionary:
	target_port_id = String(p.get("port_id", ""))
	_selected_port = p.duplicate(true)
	state = "far"
	last = {}
	_hold_requested = false
	_hold_reason = ""
	_failure_reason = ""
	_docked_t = -1.0
	events.append({"t": _t, "kind": "port_selected", "text": target_port_id})
	return {"ok": true, "port": p.duplicate(true), "state": state}


func target_port() -> Dictionary:
	return _find_port(target_port_id)


func _target_axis() -> Vector3:
	var p := target_port()
	if p.is_empty():
		return Vector3.RIGHT
	return Physics.to_vec3(p.get("axis", [1.0, 0.0, 0.0]), Vector3.RIGHT).normalized()


# ═══════════════════════════════════════════════════════════════════
# 1. 相对状态 / 姿态输入
# ═══════════════════════════════════════════════════════════════════

func _rel_vecs(rel: Variant) -> Dictionary:
	if rel is Dictionary:
		var d: Dictionary = rel
		var r := Physics.to_vec3(d.get("dr", d.get("r", d.get("pos", d.get("relative_pos", null)))), Vector3(NAN, NAN, NAN))
		var v := Physics.to_vec3(d.get("dv", d.get("v", d.get("vel", d.get("relative_vel", null)))), Vector3(NAN, NAN, NAN))
		if not Physics.is_finite_vec(r) or not Physics.is_finite_vec(v):
			return {"ok": false, "reason": "invalid_relative_state"}
		return {"ok": true, "r": r, "v": v}
	if rel is Array and (rel as Array).size() >= 6:
		var a: Array = rel
		var r2 := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var v2 := Vector3(float(a[3]), float(a[4]), float(a[5]))
		if not Physics.is_finite_vec(r2) or not Physics.is_finite_vec(v2):
			return {"ok": false, "reason": "invalid_relative_state"}
		return {"ok": true, "r": r2, "v": v2}
	return {"ok": false, "reason": "invalid_relative_state"}


func _attitude_axis(attitude: Variant) -> Dictionary:
	if attitude is Dictionary:
		var d: Dictionary = attitude
		for k in ["chaser_port_axis", "chaser_axis", "port_axis", "axis"]:
			if d.has(k):
				var ax := Physics.to_vec3(d.get(k), Vector3(NAN, NAN, NAN))
				if Physics.is_finite_vec(ax) and ax.length() > 1.0e-9:
					return {"available": true, "axis": ax.normalized()}
	return {"available": false, "axis": Vector3.ZERO}


func _angle_deg(a: Vector3, b: Vector3) -> float:
	if a.length() < 1.0e-9 or b.length() < 1.0e-9:
		return 180.0
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


# ═══════════════════════════════════════════════════════════════════
# 2. 走廊 / 制导 / 对接判定（纯计算）
# ═══════════════════════════════════════════════════════════════════

func _corridor_spec() -> Dictionary:
	var spec: Dictionary = (cfg.get("corridor", {}) as Dictionary).duplicate(true) if cfg.get("corridor", {}) is Dictionary else {}
	spec["axis"] = Physics.vec3_to_array(_target_axis())
	return spec


func _docking_spec() -> Dictionary:
	var spec: Dictionary = (cfg.get("docking", {}) as Dictionary).duplicate(true) if cfg.get("docking", {}) is Dictionary else {}
	spec["dock_speed_mps"] = float(cfg.get("dock_speed_mps", spec.get("dock_speed_mps", 0.1)))
	spec["lateral_tol_km"] = float(cfg.get("align_lateral_km", spec.get("lateral_tol_km", 0.2)))
	spec["align_tol_deg"] = float(cfg.get("align_tol_deg", spec.get("align_tol_deg", 5.0)))
	spec["max_closing_mps"] = float(cfg.get("corridor", {}).get("max_closing_mps", 50.0)) if cfg.get("corridor", {}) is Dictionary else 50.0
	return spec


func _guidance(rel_pos: Vector3, rel_vel: Vector3, axis: Vector3, chaser_axis: Vector3,
		chaser_available: bool, corr: Dictionary, dock: Dictionary) -> Dictionary:
	var range_km := rel_pos.length()
	var standoff := float(cfg.get("final_standoff_km", 0.02))
	var range_err := maxf(0.0, range_km - standoff)
	var base := float(cfg.get("guidance_base_closing_mps", 0.5))
	var gain := float(cfg.get("guidance_range_gain", 0.02))
	var max_close := float(cfg.get("guidance_max_closing_mps", 5.0))
	var closing_desired_mps := clampf(base + gain * range_err, 0.05, max_close)
	var along := rel_pos.dot(axis)
	var lateral_vec := rel_pos - axis * along
	var lateral_km := lateral_vec.length()
	var lat_rate_mps := clampf(lateral_km * float(cfg.get("guidance_lateral_gain", 0.5)) * 1000.0, 0.0, 1.0)
	var v_des_kmps := -axis * (closing_desired_mps * 0.001)
	if lateral_km > 1.0e-9:
		v_des_kmps -= lateral_vec.normalized() * (lat_rate_mps * 0.001)
	var dv_mps := (v_des_kmps - rel_vel) * 1000.0
	var dv_limit := float(cfg.get("guidance_max_dv_mps", 3.0))
	var dv_mag := dv_mps.length()
	if dv_mag > dv_limit and dv_mag > 1.0e-9:
		dv_mps = dv_mps * (dv_limit / dv_mag)
	var desired_axis := -axis
	var att_err := _angle_deg(chaser_axis, desired_axis) if chaser_available else -1.0
	var tgo := -1.0
	var closing_actual := float(corr.get("closing_mps", 0.0)) if corr is Dictionary else 0.0
	var closing_for_tgo := maxf(closing_actual, closing_desired_mps)
	if closing_for_tgo > 1.0e-6 and range_err > 1.0e-9:
		tgo = range_err / (closing_for_tgo * 0.001)
	return {
		"schema": "v17_docking_guidance.v1",
		"available": range_km > 1.0e-9,
		"range_km": range_km,
		"standoff_km": standoff,
		"range_error_km": range_err,
		"closing_actual_mps": closing_actual,
		"closing_desired_mps": closing_desired_mps,
		"time_to_go_s": tgo,
		"lateral_km": lateral_km,
		"lateral_rate_cmd_mps": lat_rate_mps,
		"dv_mps": Physics.vec3_to_array(dv_mps),
		"dv_magnitude_mps": dv_mps.length(),
		"attitude_available": chaser_available,
		"attitude_desired_axis": Physics.vec3_to_array(desired_axis),
		"attitude_error_deg": att_err,
		"gates": {
			"far_km": float(cfg.get("far_km", 250.0)),
			"align_range_km": float(cfg.get("align_range_km", 2.0)),
			"final_km": float(cfg.get("final_km", 0.25)),
			"contact_tol_km": float(cfg.get("contact_tol_km", 0.05)),
			"align_tol_deg": float(cfg.get("align_tol_deg", 5.0)),
			"final_closing_mps": float(cfg.get("final_closing_mps", 0.5)),
			"dock_speed_mps": float(cfg.get("dock_speed_mps", 0.1)),
		},
		"warnings": (corr.get("warnings", []) as Array).duplicate() if corr.get("warnings", []) is Array else [],
	}


func _evaluate(rel: Variant, attitude: Variant = {}) -> Dictionary:
	var rr := _rel_vecs(rel)
	if not bool(rr.get("ok", false)):
		return _snap_error(String(rr.get("reason", "invalid_relative_state")))
	var port := target_port()
	if port.is_empty():
		return _snap_error("no_target_port")
	var rp: Vector3 = rr["r"]
	var rv: Vector3 = rr["v"]
	var axis := _target_axis()
	var range_km := rp.length()
	var along := rp.dot(axis)
	var lateral_vec := rp - axis * along
	var lateral_km := lateral_vec.length()
	var att := _attitude_axis(attitude)
	var chaser_axis: Vector3 = att.get("axis", Vector3.ZERO)
	var chaser_available := bool(att.get("available", false))
	var desired_axis := -rp.normalized() if range_km > 1.0e-9 else -axis
	var chaser_angle := _angle_deg(chaser_axis, desired_axis) if chaser_available else -1.0
	var corr := Physics.approach_corridor_check(rp, rv, _corridor_spec())
	var dock := Physics.docking_geometry(rp, rv, axis, _docking_spec())
	var align_ok := float(dock.get("align_angle_deg", 180.0)) <= float(cfg.get("align_tol_deg", 5.0)) + 1.0e-9
	var chaser_ok := (not chaser_available) or chaser_angle <= float(cfg.get("align_tol_deg", 5.0)) + 1.0e-9
	var lateral_ok := lateral_km <= float(cfg.get("align_lateral_km", 0.2)) + 1.0e-9
	var align_ready := align_ok and chaser_ok and lateral_ok
	var closing_mps := float(dock.get("closing_mps", 0.0))
	var final_ready := range_km <= float(cfg.get("final_km", 0.25)) + 1.0e-9 \
		and align_ready and closing_mps <= float(cfg.get("final_closing_mps", 0.5)) + 1.0e-9
	var docking_ok := String(dock.get("status", "")) == "docked" \
		and chaser_available and chaser_angle <= float(cfg.get("align_tol_deg", 5.0)) + 1.0e-9
	var hard_fail := ""
	if range_km <= float(cfg.get("final_km", 0.25)) + 1.0e-9:
		if closing_mps > float(cfg.get("hard_max_closing_mps", 2.0)) + 1.0e-9:
			hard_fail = "contact_speed"
		elif lateral_km > float(cfg.get("hard_lateral_km", 0.5)) + 1.0e-9:
			hard_fail = "lateral_misalignment"
		elif chaser_available and chaser_angle > float(cfg.get("hard_align_deg", 15.0)) + 1.0e-9:
			hard_fail = "attitude_misalignment"
	var gd := _guidance(rp, rv, axis, chaser_axis, chaser_available, corr, dock)
	var warnings: Array = []
	if corr.get("warnings", []) is Array:
		for w in (corr.get("warnings", []) as Array):
			warnings.append(String(w))
	if dock.get("warnings", []) is Array:
		for w2 in (dock.get("warnings", []) as Array):
			warnings.append(String(w2))
	if chaser_available and not chaser_ok:
		warnings.append("本舰端口轴偏差 %.1f° > %.1f°" % [chaser_angle, float(cfg.get("align_tol_deg", 5.0))])
	if hard_fail != "":
		warnings.append("硬失败：" + hard_fail)
	return {
		"schema": SNAPSHOT_SCHEMA,
		"t": _t,
		"state": state,
		"target_port_id": target_port_id,
		"port": port.duplicate(true),
		"rel_pos_km": Physics.vec3_to_array(rp),
		"rel_vel_kmps": Physics.vec3_to_array(rv),
		"range_km": range_km,
		"axial_km": along,
		"lateral_km": lateral_km,
		"closing_mps": closing_mps,
		"align_angle_deg": float(dock.get("align_angle_deg", 180.0)),
		"chaser_axis_available": chaser_available,
		"chaser_axis": Physics.vec3_to_array(chaser_axis),
		"chaser_align_angle_deg": chaser_angle,
		"chaser_aligned": chaser_ok,
		"corridor": corr.duplicate(true),
		"docking": dock.duplicate(true),
		"guidance": gd,
		"align_ready": align_ready,
		"final_ready": final_ready,
		"docking_ok": docking_ok,
		"hard_fail": hard_fail,
		"warnings": warnings,
		"writes": {"world": false, "physics": false, "track_table": false, "v15": false},
		"authoritative": false,
	}


## 只读评估（不推进状态；供 UI/预览/上层决策）。
func evaluate(rel: Variant, attitude: Variant = {}) -> Dictionary:
	return _evaluate(rel, attitude)


## evaluate 的别名（文档/调用方兼容）。
func preview(rel: Variant, attitude: Variant = {}) -> Dictionary:
	return evaluate(rel, attitude)


func _snap_error(reason: String) -> Dictionary:
	return {
		"schema": SNAPSHOT_SCHEMA,
		"t": _t,
		"state": state,
		"target_port_id": target_port_id,
		"ok": false,
		"reason": reason,
		"warnings": [reason],
		"writes": {"world": false, "physics": false, "track_table": false, "v15": false},
		"authoritative": false,
	}


# ═══════════════════════════════════════════════════════════════════
# 3. 状态机（显式调用 update；不执行物理）
# ═══════════════════════════════════════════════════════════════════

func _snap_out() -> Dictionary:
	var out: Dictionary = last.duplicate(true) if last is Dictionary else {}
	out["state"] = state
	out["failure_reason"] = _failure_reason
	out["docked_t"] = _docked_t
	out["undocked_t"] = _undocked_t
	out["hold_requested"] = _hold_requested
	return out


func update(rel: Variant, attitude: Variant = {}, dt := 0.0) -> Dictionary:
	_t += maxf(0.0, dt)
	var ev := _evaluate(rel, attitude)
	last = ev.duplicate(true)
	if not bool(ev.get("ok", true)):
		return _snap_out()
	if TERMINAL_STATES.has(state) and state != "docked":
		# aborted/failed 终态，需 reset；docked 也保持，但 docked 由 undock 解除
		return _snap_out()
	if TERMINAL_STATES.has(state) and state == "docked":
		return _snap_out()
	if _hold_requested:
		_transition("hold", _hold_reason)
		last["state"] = state
		return _snap_out()
	var range_km := float(ev.get("range_km", 0.0))
	var corr: Dictionary = ev.get("corridor", {}) if ev.get("corridor", {}) is Dictionary else {}
	var hard := String(ev.get("hard_fail", ""))
	if hard != "":
		_transition("failed", hard)
	elif bool(ev.get("docking_ok", false)):
		if state != "docked":
			_docked_t = _t
			_transition("docked", "docking_criteria")
	elif range_km > float(cfg.get("far_km", 250.0)) + 1.0e-9:
		_transition("far", "out_of_range")
	elif bool(ev.get("final_ready", false)):
		_transition("final", "final_gates")
	elif bool(ev.get("align_ready", false)) and range_km <= float(cfg.get("align_range_km", 2.0)) + 1.0e-9:
		_transition("alignment", "alignment_gates")
	elif bool(corr.get("ok", false)):
		_transition("corridor", "in_corridor")
	elif bool(corr.get("inside", false)) and (
			not bool(corr.get("speed_ok", false)) or not bool(corr.get("angle_ok", false))):
		if range_km <= float(cfg.get("hold_range_km", 5.0)) + 1.0e-9:
			_transition("hold", "corridor_violation")
		else:
			_transition("approach", "outside_corridor")
	else:
		_transition("approach", "outside_corridor")
	last["state"] = state
	last["failure_reason"] = _failure_reason
	last["docked_t"] = _docked_t
	return _snap_out()


func _transition(next: String, reason: String) -> void:
	if not STATES.has(next):
		return
	if state == next:
		if next == "hold" and _hold_reason != "":
			_hold_reason = reason
		return
	state = next
	_hold_reason = reason if next == "hold" else ""
	if next == "failed":
		_failure_reason = reason
	events.append({"t": _t, "kind": "state_" + next, "text": reason})
	while events.size() > 64:
		events.pop_front()



func hold(reason := "commander_hold") -> Dictionary:
	if state in ["docked", "aborted", "failed"]:
		return {"ok": false, "reason": "terminal_state", "state": state}
	_hold_requested = true
	_hold_reason = reason
	_transition("hold", reason)
	last["state"] = state
	return vm()


func resume() -> Dictionary:
	_hold_requested = false
	_hold_reason = ""
	if state == "hold":
		_transition("approach", "resume")
		last["state"] = state
	return vm()


func abort(reason := "commander_abort") -> Dictionary:
	if state in ["aborted", "failed"]:
		return {"ok": false, "reason": "terminal_state", "state": state}
	_hold_requested = false
	_failure_reason = reason
	_transition("aborted", reason)
	last["state"] = state
	return vm()


func fail(reason := "docking_failed") -> Dictionary:
	_hold_requested = false
	_failure_reason = reason
	_transition("failed", reason)
	last["state"] = state
	return vm()


func undock(reason := "commander_undock") -> Dictionary:
	if state != "docked":
		return {"ok": false, "reason": "not_docked", "state": state}
	_undocked_t = _t
	state = "approach"
	_docked_t = -1.0
	_failure_reason = ""
	events.append({"t": _t, "kind": "undocked", "text": reason})
	last["state"] = state
	return vm()


func reset() -> void:
	state = "far"
	target_port_id = ""
	_selected_port = {}
	last = {}
	events.clear()
	_t = 0.0
	_hold_requested = false
	_hold_reason = ""
	_failure_reason = ""
	_docked_t = -1.0
	_undocked_t = -1.0


# ═══════════════════════════════════════════════════════════════════
# 4. 只读 view-model / JSON
# ═══════════════════════════════════════════════════════════════════

func vm() -> Dictionary:
	return {
		"schema": SCHEMA,
		"state": state,
		"state_order": STATES.duplicate(),
		"t": _t,
		"target_port_id": target_port_id,
		"target_port": target_port(),
		"ports": ports.duplicate(true),
		"config": cfg.duplicate(true),
		"last": last.duplicate(true),
		"events": events.duplicate(true),
		"hold_requested": _hold_requested,
		"hold_reason": _hold_reason,
		"failure_reason": _failure_reason,
		"docked_t": _docked_t,
		"undocked_t": _undocked_t,
		"writes": {"world": false, "physics": false, "track_table": false, "v15": false},
		"authoritative": false,
	}


func to_dict() -> Dictionary:
	return vm()


func state_signature() -> String:
	return JSON.stringify({
		"state": state, "target": target_port_id, "t": _t,
		"hold": _hold_requested, "failed": _failure_reason, "docked_t": _docked_t,
		"events": events.size(),
	})
