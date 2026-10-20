extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 阶段2-CORE-A：L4-02 → L1 真实轨道转场模型（新文件；不接 UI/bridge）
#
# - 动力学：地月 CR3BP，使用 framework/sim/cislunar_physics.gd 的 RK4
#   （propagate_state；步长 ≤60s，非二体近似/非直线/非脚本插值）。
# - 转移解：两体 Lambert 求解（Earth ECI 种子，短/长程两分支）
#   → 旋转系初速 → CR3BP 打靶（有限差分 Newton，固定 TOF，命中 L1 港位置）
#   → departure burn + arrival burn；可选中途修正（MCC）。
# - 输出：时间线（T+/位置/速度/Δv/距离/误差）、入轨判定（L1 半径/相对速度/时间窗）、
#   舰队多舰（旗舰/哈马丹/渡口/望楼/深井，共享转移 + 小偏移）状态、JSON、确定性。
#
# 单位：km、km/s、s（JSON 中位置/速度数组）。frame：
#   rotating = 地月质心旋转系（bary_rot）；inertial = Earth ECI（Lambert 种子用）。
# 边界：CR3BP（忽略 J2/太阳/月球偏心率/倾角）；Lambert 为两体种子，最终轨迹由 CR3BP
#       打靶收敛；港站视为旋转系固定站保持（v_rot=0）；不是 JPL 星历。
# ═══════════════════════════════════════════════════════════════════

const Physics := preload("res://framework/sim/cislunar_physics.gd")

const SCHEMA := "v17_transfer_l4_l1.v1"
const SCHEMA_PORT := "v17_transfer_port.v1"
const SCHEMA_TIMELINE := "v17_transfer_timeline.v1"

const L4_PORT_ID := "L4-02 Hammer"
const L1_PORT_ID := "L1-Meridian-05"
const L4_PORT_OFFSET_ARRAY := [-520.0, 310.0, 40.0]
const L1_PORT_OFFSET_ARRAY := [160.0, -90.0, 15.0]

const FLEET := [
	{"id": "apsis", "batch": "1000", "role": "flagship",
		"offset_km": [0.0, 0.0, 0.0], "offset_kmps": [0.0, 0.0, 0.0]},
	{"id": "harmattan", "batch": "1001", "role": "command",
		"offset_km": [18.0, -12.0, 3.0], "offset_kmps": [0.001, -0.0005, 0.0]},
	{"id": "ferry", "batch": "1002", "role": "escort",
		"offset_km": [-24.0, 15.0, -4.0], "offset_kmps": [-0.001, 0.0007, 0.0]},
	{"id": "watchtower", "batch": "1003", "role": "relay",
		"offset_km": [12.0, 26.0, 6.0], "offset_kmps": [0.0006, 0.0012, 0.0]},
	{"id": "deepwell", "batch": "1004", "role": "tanker",
		"offset_km": [-30.0, -18.0, -6.0], "offset_kmps": [-0.0014, -0.0009, 0.0002]},
]

const TOF_DAYS_DEFAULT := [3.0, 4.0, 5.0, 6.0]
const ARRIVAL_RADIUS_GATE_KM := 3000.0
const ARRIVAL_SPEED_GATE_KMPS := 3.0
const MAX_TOTAL_DV_MPS := 10000.0
const TIME_WINDOW_MIN_DAYS := 1.0
const TIME_WINDOW_MAX_DAYS := 15.0
const SHOOT_ITERATIONS := 4
const SHOOT_TOL_KM := 1.0
const FD_DV_KMPS := 0.001
const TIMELINE_SEGMENTS := 10

# ── 工具 ─────────────────────────────────────────────────────────

static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _vec3(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	return Physics.to_vec3(value, fallback)

static func _state_arrays(state: Variant) -> Dictionary:
	var s: Dictionary = Physics.as_state(state)
	return {"r": _arr(s["r"]), "v": _arr(s["v"])}

static func _state_dict(r: Vector3, v: Vector3) -> Dictionary:
	return {"r": _arr(r), "v": _arr(v)}

static func _propagate(r: Vector3, v: Vector3, dt: float) -> Dictionary:
	var res: Dictionary = Physics.propagate_state(Physics.make_state(r, v), dt,
		{"step_s": 60.0})
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": String(res.get("reason", "propagate_failed")),
			"res": res}
	var s: Dictionary = Physics.as_state(res["state"])
	return {"ok": true, "r": s["r"], "v": s["v"], "res": res}

static func _stumpff_c(z: float) -> float:
	if z > 1.0e-6:
		var sz := sqrt(z)
		return (1.0 - cos(sz)) / z
	if z < -1.0e-6:
		var sz2 := sqrt(-z)
		return (cosh(sz2) - 1.0) / (-z)
	return 0.5

static func _stumpff_s(z: float) -> float:
	if z > 1.0e-6:
		var sz := sqrt(z)
		return (sz - sin(sz)) / (sz * sz * sz)
	if z < -1.0e-6:
		var sz2 := sqrt(-z)
		return (sinh(sz2) - sz2) / (sz2 * sz2 * sz2)
	return 1.0 / 6.0

static func _lambert_f(z: float, r1: float, r2: float, a_val: float,
		tof_s: float, sqrt_mu: float) -> float:
	var c := _stumpff_c(z)
	var s := _stumpff_s(z)
	if c <= 1.0e-12:
		return NAN
	var y := r1 + r2 + a_val * (z * s - 1.0) / sqrt(c)
	if y <= 0.0:
		return NAN
	var x := sqrt(y / c)
	var t_calc := (x * x * x * s + a_val * sqrt(y)) / sqrt_mu
	return t_calc - tof_s

## 两体 Lambert（Earth ECI 位置 + 飞行时间；prograde 控制短/长程分支）。
static func lambert(r1v: Vector3, r2v: Vector3, tof_s: float, mu_km3_s2: float,
		prograde := true) -> Dictionary:
	if tof_s <= 0.0 or mu_km3_s2 <= 0.0:
		return {"ok": false, "reason": "invalid_time_or_mu"}
	var r1 := r1v.length()
	var r2 := r2v.length()
	if r1 < 1.0e-6 or r2 < 1.0e-6:
		return {"ok": false, "reason": "invalid_radius"}
	var cos_dnu := clampf(r1v.dot(r2v) / (r1 * r2), -1.0, 1.0)
	var cross := r1v.cross(r2v)
	var dnu := acos(cos_dnu)
	if prograde:
		if cross.z < 0.0:
			dnu = TAU - dnu
	else:
		if cross.z >= 0.0:
			dnu = TAU - dnu
	var sin_dnu := sin(dnu)
	if dnu < 1.0e-3 or absf(sin_dnu) < 1.0e-9 or absf(1.0 - cos_dnu) < 1.0e-15:
		return {"ok": false, "reason": "degenerate_geometry"}
	var a_val := sin_dnu * sqrt(r1 * r2 / (1.0 - cos_dnu))
	var sqrt_mu := sqrt(mu_km3_s2)
	# 在 z ∈ (-4π², 4π²) 扫描 F(z) 符号变化，再二分
	var z_lo := -4.0 * PI * PI + 1.0e-4
	var z_hi := 4.0 * PI * PI - 1.0e-4
	var n_scan := 2048
	var prev_z := z_lo
	var prev_f := _lambert_f(z_lo, r1, r2, a_val, tof_s, sqrt_mu)
	var bracket_lo := NAN
	var bracket_hi := NAN
	for i in range(1, n_scan + 1):
		var z := lerpf(z_lo, z_hi, float(i) / float(n_scan))
		var f := _lambert_f(z, r1, r2, a_val, tof_s, sqrt_mu)
		if is_finite(prev_f) and is_finite(f) and prev_f * f <= 0.0:
			bracket_lo = prev_z
			bracket_hi = z
			break
		if is_finite(f):
			prev_f = f
			prev_z = z
	if not is_finite(bracket_lo):
		return {"ok": false, "reason": "no_bracket"}
	var lo := bracket_lo
	var hi := bracket_hi
	var f_lo := _lambert_f(lo, r1, r2, a_val, tof_s, sqrt_mu)
	for i in range(120):
		var mid := 0.5 * (lo + hi)
		var f_mid := _lambert_f(mid, r1, r2, a_val, tof_s, sqrt_mu)
		if not is_finite(f_mid):
			lo = mid
			continue
		if f_lo * f_mid <= 0.0:
			hi = mid
		else:
			lo = mid
			f_lo = f_mid
	var z_sol := 0.5 * (lo + hi)
	var c_sol := _stumpff_c(z_sol)
	var s_sol := _stumpff_s(z_sol)
	var y_sol := r1 + r2 + a_val * (z_sol * s_sol - 1.0) / sqrt(c_sol)
	if y_sol <= 0.0 or not is_finite(y_sol):
		return {"ok": false, "reason": "invalid_y"}
	var f_val := 1.0 - y_sol / r1
	var g_val := a_val * sqrt(y_sol / mu_km3_s2)
	var gdot := 1.0 - y_sol / r2
	if absf(g_val) < 1.0e-12:
		return {"ok": false, "reason": "singular_g"}
	var v1 := (r2v - f_val * r1v) / g_val
	var v2 := (gdot * r2v - r1v) / g_val
	if not Physics.is_finite_vec(v1) or not Physics.is_finite_vec(v2):
		return {"ok": false, "reason": "non_finite_velocity"}
	return {
		"ok": true,
		"v1": v1, "v2": v2,
		"dnu_deg": rad_to_deg(dnu),
		"prograde": prograde,
		"z": z_sol,
		"y": y_sol,
		"f": f_val, "g": g_val, "gdot": gdot,
		"r1_km": r1, "r2_km": r2,
	}

# 3×3 线性求解（列向量数组 cols；解 J·x = b）。
static func _solve3(cols: Array, b: Vector3) -> Vector3:
	var a11: float = (cols[0] as Vector3).x
	var a21: float = (cols[0] as Vector3).y
	var a31: float = (cols[0] as Vector3).z
	var a12: float = (cols[1] as Vector3).x
	var a22: float = (cols[1] as Vector3).y
	var a32: float = (cols[1] as Vector3).z
	var a13: float = (cols[2] as Vector3).x
	var a23: float = (cols[2] as Vector3).y
	var a33: float = (cols[2] as Vector3).z
	var det := a11 * (a22 * a33 - a23 * a32) \
		- a12 * (a21 * a33 - a23 * a31) \
		+ a13 * (a21 * a32 - a22 * a31)
	if absf(det) < 1.0e-14 or not is_finite(det):
		return Vector3.ZERO
	var inv_det := 1.0 / det
	var x := inv_det * (b.x * (a22 * a33 - a23 * a32) \
		- a12 * (b.y * a33 - a23 * b.z) \
		+ a13 * (b.y * a32 - a22 * b.z))
	var y := inv_det * (a11 * (b.y * a33 - a23 * b.z) \
		- b.x * (a21 * a33 - a23 * a31) \
		+ a13 * (a21 * b.z - b.y * a31))
	var z := inv_det * (a11 * (a22 * b.z - b.y * a32) \
		- a12 * (a21 * b.z - b.y * a31) \
		+ b.x * (a21 * a32 - a22 * a31))
	return Vector3(x, y, z)

## CR3BP 打靶：固定 TOF，未知出发旋转系速度，命中目标旋转系位置。
static func _shoot(r0: Vector3, v0: Vector3, target_r: Vector3, tof_s: float,
		iterations := SHOOT_ITERATIONS) -> Dictionary:
	var v := v0
	var last: Dictionary = {}
	var err := INF
	var iters := 0
	for i in range(iterations):
		iters = i + 1
		last = _propagate(r0, v, tof_s)
		if not bool(last.get("ok", false)):
			return {"ok": false, "reason": "propagate_failed", "iterations": iters}
		err = ((last["r"] as Vector3) - target_r).length()
		if err < SHOOT_TOL_KM:
			break
		var res_vec: Vector3 = (last["r"] as Vector3) - target_r
		var cols: Array = []
		for j in range(3):
			var dv := v
			dv[j] += FD_DV_KMPS
			var trial: Dictionary = _propagate(r0, dv, tof_s)
			if not bool(trial.get("ok", false)):
				return {"ok": false, "reason": "fd_propagate_failed", "iterations": iters}
			var trial_res: Vector3 = (trial["r"] as Vector3) - target_r
			cols.append((trial_res - res_vec) / FD_DV_KMPS)
		var dx := _solve3(cols, -res_vec)
		if dx.length() < 1.0e-12:
			break
		if dx.length() > 0.5:
			dx = dx.normalized() * 0.5
		v += dx
	return {
		"ok": true,
		"v": v,
		"error_km": err,
		"iterations": iters,
		"final": last,
		"converged": err <= SHOOT_TOL_KM,
		"final_r": last.get("r", Vector3.ZERO),
		"final_v": last.get("v", Vector3.ZERO),
	}

# ── 港口 / 场景状态 ───────────────────────────────────────────────

static func l4_port_state() -> Dictionary:
	return Physics.lagrange_state("L4", _vec3(L4_PORT_OFFSET_ARRAY),
		Vector3.ZERO)

static func l1_port_state() -> Dictionary:
	return Physics.lagrange_state("L1", _vec3(L1_PORT_OFFSET_ARRAY),
		Vector3.ZERO)

static func l1_cluster_offsets() -> Array:
	return [
		{"port_id": "L1-Meridian-05", "offset_km": [160.0, -90.0, 15.0],
			"kind": "port", "status": "open"},
		{"port_id": "L1-Anchorage-02", "offset_km": [-220.0, 120.0, -25.0],
			"kind": "berth", "status": "open"},
		{"port_id": "L1-Drydock-01", "offset_km": [40.0, 260.0, 30.0],
			"kind": "drydock", "status": "reserved"},
	]

static func _port_summary(port_id: String, state: Variant, lpoint: String) -> Dictionary:
	var s: Dictionary = Physics.as_state(state)
	var eci: Dictionary = Physics.bary_rot_to_earth_eci(s, 0.0)
	return {
		"schema": SCHEMA_PORT,
		"port_id": port_id,
		"lpoint": lpoint,
		"frame": "bary_rot",
		"pos_rot_km": _arr(s["r"]),
		"vel_rot_kmps": _arr(s["v"]),
		"earth_distance_km": (eci["r"] as Vector3).length(),
		"moon_distance_km": (s["r"] - Physics.moon_position_rot()).length(),
	}

# ── 主规划 ───────────────────────────────────────────────────────

## 规划 L4-02 → L1 转移（默认扫描多个 TOF × 短/长程 Lambert 种子 → CR3BP 打靶）。
static func plan(opts := {}) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	var tof_days: Array = o.get("tof_days", TOF_DAYS_DEFAULT)
	if not (tof_days is Array) or (tof_days as Array).is_empty():
		return _fail_plan("invalid_tof_days")
	var source := l4_port_state()
	var target := l1_port_state()
	if source.is_empty() or target.is_empty():
		return _fail_plan("lpoint_unavailable")
	var src: Dictionary = Physics.as_state(source)
	var tgt: Dictionary = Physics.as_state(target)
	var src_r: Vector3 = src["r"]
	var src_v: Vector3 = src["v"]
	var tgt_r: Vector3 = tgt["r"]
	var tgt_v: Vector3 = tgt["v"]
	var source_eci: Dictionary = Physics.bary_rot_to_earth_eci(src, 0.0)
	var mu_earth := Physics.MU_EARTH_KM3_S2
	var candidates: Array = []
	var errors: Array = []
	for raw_td in tof_days:
		var td := float(raw_td)
		if td <= 0.0:
			errors.append("invalid_tof_days_value")
			continue
		var tof_s := td * 86400.0
		var target_eci: Dictionary = Physics.bary_rot_to_earth_eci(tgt, tof_s)
		for prograde in [true, false]:
			var lam: Dictionary = lambert(source_eci["r"] as Vector3,
				target_eci["r"] as Vector3, tof_s, mu_earth, prograde)
			if not bool(lam.get("ok", false)):
				continue
			var seed_rot: Dictionary = Physics.earth_eci_to_bary_rot(
				Physics.make_state(source_eci["r"] as Vector3, lam["v1"] as Vector3), 0.0)
			var shoot: Dictionary = _shoot(src_r, seed_rot["v"] as Vector3, tgt_r, tof_s)
			if not bool(shoot.get("ok", false)):
				continue
			var arr_state := {"r": shoot["final_r"], "v": shoot["final_v"]}
			var dep_dv: Vector3 = (shoot["v"] as Vector3) - src_v
			var arr_dv: Vector3 = tgt_v - (arr_state["v"] as Vector3)
			var dep_mps := dep_dv.length() * 1000.0
			var arr_mps := arr_dv.length() * 1000.0
			var radius := ((arr_state["r"] as Vector3) - tgt_r).length()
			var rel_speed := ((arr_state["v"] as Vector3) - tgt_v).length()
			var total := dep_mps + arr_mps
			var feasible := radius <= float(o.get("arrival_radius_gate_km", ARRIVAL_RADIUS_GATE_KM)) \
				and rel_speed <= float(o.get("arrival_speed_gate_kmps", ARRIVAL_SPEED_GATE_KMPS)) \
				and td >= TIME_WINDOW_MIN_DAYS and td <= TIME_WINDOW_MAX_DAYS \
				and total <= float(o.get("max_total_dv_mps", MAX_TOTAL_DV_MPS))
			candidates.append({
				"tof_days": td, "tof_s": tof_s, "prograde": prograde,
				"lambert": lam, "shoot": shoot,
				"depart_v": shoot["v"], "arrival_state": arr_state,
				"depart_dv": dep_dv, "arrival_dv": arr_dv,
				"depart_mps": dep_mps, "arrival_mps": arr_mps,
				"total_mps": total,
				"arrival_radius_km": radius, "arrival_speed_kmps": rel_speed,
				"feasible": feasible,
			})
	if candidates.is_empty():
		return _fail_plan("no_transfer_solution", errors)
	var best: Dictionary = {}
	for cand in candidates:
		if bool(cand.get("feasible", false)):
			if best.is_empty() or float(cand["total_mps"]) < float(best["total_mps"]):
				best = cand
	if best.is_empty():
		# 无可行解：选总 Δv 最小者并标记不可行（不伪造可行）
		for cand in candidates:
			if best.is_empty() or float(cand["total_mps"]) < float(best["total_mps"]):
				best = cand
	return _build_plan(best, source, target, candidates.size(), o)

static func _fail_plan(reason: String, errors := []) -> Dictionary:
	return {
		"schema": SCHEMA, "ok": false, "reason": reason,
		"errors": (errors as Array).duplicate(),
		"source": {}, "target": {}, "transfer": {}, "timeline": [], "fleet": [],
		"budget": {}, "warnings": [],
		"note": "L4-02 → L1 转场规划失败；未伪造轨迹。",
	}

static func _build_plan(best: Dictionary, source: Dictionary, target: Dictionary,
		candidate_count: int, opts: Dictionary) -> Dictionary:
	var src: Dictionary = Physics.as_state(source)
	var tgt: Dictionary = Physics.as_state(target)
	var src_r: Vector3 = src["r"]
	var src_v: Vector3 = src["v"]
	var tgt_r: Vector3 = tgt["r"]
	var tgt_v: Vector3 = tgt["v"]
	var tof_s := float(best["tof_s"])
	var depart_v: Vector3 = best["depart_v"]
	var gate_radius := float(opts.get("arrival_radius_gate_km", ARRIVAL_RADIUS_GATE_KM))
	var gate_speed := float(opts.get("arrival_speed_gate_kmps", ARRIVAL_SPEED_GATE_KMPS))
	var warnings: Array = []
	var errors: Array = []
	# 可选 MCC：在半程做一次小修正（固定 TOF，剩余半程打靶）
	var mcc := {"applied": false, "dv_mps": 0.0, "dv": [0.0, 0.0, 0.0],
		"reason": "not_requested"}
	var include_mcc := bool(opts.get("include_mcc", true))
	var mid_r := Vector3.ZERO
	var mid_v := Vector3.ZERO
	var mid_t := 0.5 * tof_s
	if include_mcc:
		var mid_prop: Dictionary = _propagate(src_r, depart_v, mid_t)
		if bool(mid_prop.get("ok", false)):
			mid_r = mid_prop["r"] as Vector3
			mid_v = mid_prop["v"] as Vector3
			var half := 0.5 * tof_s
			var mcc_shoot: Dictionary = _shoot(mid_r, mid_v, tgt_r, half, 2)
			if bool(mcc_shoot.get("ok", false)):
				var corr: Vector3 = (mcc_shoot["v"] as Vector3) - mid_v
				var mcc_mps := corr.length() * 1000.0
				if mcc_mps > 0.001:
					mcc = {"applied": true, "dv_mps": mcc_mps,
						"dv": _arr(corr), "mid_t_s": mid_t,
						"mid_state_rot": _state_dict(mid_r, mid_v),
						"reason": "halfway_targeting_correction"}
					mid_v = mid_v + corr
					warnings.append("已施加中途修正 %.3f m/s（半程，固定 TOF）" % mcc_mps)
				else:
					mcc = {"applied": false, "dv_mps": 0.0, "dv": [0.0, 0.0, 0.0],
						"reason": "primary_error_within_tolerance"}
			else:
				mcc = {"applied": false, "dv_mps": 0.0, "dv": [0.0, 0.0, 0.0],
					"reason": "mcc_solve_failed"}
		else:
			mcc = {"applied": false, "dv_mps": 0.0, "dv": [0.0, 0.0, 0.0],
				"reason": "mid_propagation_failed"}
	# 时间线（含 MCC 时半程后使用修正速度）
	var timeline: Array = []
	var seg := tof_s / float(TIMELINE_SEGMENTS)
	var r := src_r
	var v := depart_v
	var t := 0.0
	timeline.append(_timeline_row(0, r, v, tgt_r))
	for i in range(TIMELINE_SEGMENTS):
		if bool(mcc.get("applied", false)) and i == TIMELINE_SEGMENTS / 2:
			r = mid_r
			v = mid_v
		var prop: Dictionary = _propagate(r, v, seg)
		if not bool(prop.get("ok", false)):
			errors.append("timeline_propagation_failed")
			break
		r = prop["r"] as Vector3
		v = prop["v"] as Vector3
		t += seg
		timeline.append(_timeline_row(t, r, v, tgt_r))
	var arrival_state: Dictionary = _state_dict(r, v)
	var arrival_radius := (r - tgt_r).length()
	var arrival_speed := (v - tgt_v).length()
	var dep_dv: Vector3 = depart_v - src_v
	var arr_dv: Vector3 = tgt_v - v
	var dep_mps := dep_dv.length() * 1000.0
	var arr_mps := arr_dv.length() * 1000.0
	var mcc_mps := float(mcc.get("dv_mps", 0.0))
	var total_mps := dep_mps + arr_mps + mcc_mps
	var window_ok := float(best["tof_days"]) >= TIME_WINDOW_MIN_DAYS \
		and float(best["tof_days"]) <= TIME_WINDOW_MAX_DAYS
	var arrival_ok := arrival_radius <= gate_radius and arrival_speed <= gate_speed and window_ok
	if not arrival_ok:
		warnings.append("入轨判定未通过（见 arrival 字段；不伪造 ok）")
	# 舰队：共享转移 + 小偏移
	var fleet: Array = []
	for raw_ship in FLEET:
		var ship: Dictionary = raw_ship
		var off := _vec3(ship.get("offset_km", [0.0, 0.0, 0.0]))
		var offv := _vec3(ship.get("offset_kmps", [0.0, 0.0, 0.0]))
		var ship_r := src_r + off
		var ship_v := depart_v + offv
		var ship_init := {"r": _arr(ship_r + Vector3.ZERO), "v": _arr(src_v + offv)}
		var prop2: Dictionary = _propagate(ship_r, ship_v, tof_s)
		var arrival_entry: Dictionary = {"ok": false, "r": [], "v": []}
		var ship_err := -1.0
		var ship_speed := -1.0
		var within := false
		if bool(prop2.get("ok", false)):
			var ar: Vector3 = prop2["r"] as Vector3
			var av: Vector3 = prop2["v"] as Vector3
			ship_err = (ar - tgt_r).length()
			ship_speed = (av - tgt_v).length()
			within = ship_err <= gate_radius and ship_speed <= gate_speed
			arrival_entry = {"ok": true, "r": _arr(ar), "v": _arr(av)}
		fleet.append({
			"id": String(ship.get("id", "")), "batch": String(ship.get("batch", "")),
			"role": String(ship.get("role", "")),
			"offset_km": _arr(off), "offset_kmps": _arr(offv),
			"initial_state_rot": ship_init,
			"depart_state_rot": _state_dict(ship_r, ship_v),
			"arrival_state_rot": arrival_entry,
			"arrival_error_km": ship_err,
			"arrival_speed_kmps": ship_speed,
			"within_gate": within,
		})
	var source_summary := _port_summary(L4_PORT_ID, source, "L4")
	var target_summary := _port_summary(L1_PORT_ID, target, "L1")
	var timeline_ok := timeline.size() == TIMELINE_SEGMENTS + 1
	if not timeline_ok:
		errors.append("timeline_incomplete")
	return {
		"schema": SCHEMA,
		"ok": bool(best.get("ok", true)) and arrival_ok and timeline_ok,
		"reason": "" if arrival_ok else "arrival_gate_failed",
		"scenario_id": "transit_l4_l1",
		"frame": {"inertial": "earth_eci", "rotating": "bary_rot",
			"units": "km,km/s,s",
			"note": "Lambert 两体种子在 Earth ECI；最终轨迹 CR3BP/RK4 旋转系打靶"},
		"source": source_summary,
		"target": target_summary,
		"transfer": {
			"method": "lambert_seed_cr3bp_shooting",
			"tof_s": tof_s,
			"tof_days": float(best["tof_days"]),
			"prograde": bool(best["prograde"]),
			"lambert": {
				"ok": bool((best["lambert"] as Dictionary).get("ok", false)),
				"dnu_deg": float((best["lambert"] as Dictionary).get("dnu_deg", 0.0)),
				"prograde": bool(best["prograde"]),
				"z": float((best["lambert"] as Dictionary).get("z", 0.0)),
			},
			"shooting": {
				"iterations": int((best["shoot"] as Dictionary).get("iterations", 0)),
				"converged": bool((best["shoot"] as Dictionary).get("converged", false)),
				"error_km": float((best["shoot"] as Dictionary).get("error_km", 0.0)),
			},
			"depart_state_rot": _state_dict(src_r, depart_v),
			"arrival_state_rot": arrival_state,
			"depart_dv_rot": _arr(dep_dv),
			"arrival_dv_rot": _arr(arr_dv),
			"depart_dv_mps": dep_mps,
			"arrival_dv_mps": arr_mps,
			"mcc_dv_mps": mcc_mps,
			"total_dv_mps": total_mps,
			"mcc": mcc,
			"candidate_count": candidate_count,
		},
		"arrival": {
			"radius_km": arrival_radius,
			"relative_speed_kmps": arrival_speed,
			"gate_radius_km": gate_radius,
			"gate_speed_kmps": gate_speed,
			"time_window_ok": window_ok,
			"time_window_days": [TIME_WINDOW_MIN_DAYS, TIME_WINDOW_MAX_DAYS],
			"ok": arrival_ok,
		},
		"timeline": timeline,
		"fleet": fleet,
		"budget": {
			"depart_dv_mps": dep_mps,
			"arrival_dv_mps": arr_mps,
			"mcc_dv_mps": mcc_mps,
			"total_dv_mps": total_mps,
		},
		"warnings": warnings,
		"errors": errors,
		"deterministic": true,
		"note": "真实转移：Lambert 两体种子 + CR3BP/RK4 打靶；departure/arrival burn；可选中途修正；不接 UI/bridge。",
	}

static func _timeline_row(t: float, r: Vector3, v: Vector3, target_r: Vector3) -> Dictionary:
	return {
		"schema": SCHEMA_TIMELINE,
		"t_s": t,
		"t_days": t / 86400.0,
		"pos_rot_km": _arr(r),
		"vel_rot_kmps": _arr(v),
		"range_to_target_km": (r - target_r).length(),
		"alt_km": r.length() - Physics.R_EARTH_KM,
		"error_km": (r - target_r).length(),
	}

## JSON（确定性：同一输入 → 同一输出）。
static func to_json(opts := {}) -> String:
	return JSON.stringify(plan(opts))
