class_name V2CislunarPhysics
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 地月物理核心（R6-PHYS-1）
#
# **可验证的物理模型，先不替换游戏**：圆轨道 + CR3BP 近似，不是 JPL 星历。
#
# 覆盖：
#   * 参考系：地月惯性系（Earth-centered ECI）、地月旋转系（barycenter rotating）、
#     地心旋转系（Earth-centered rotating）；地月惯性/旋转相互转换（位置+速度）。
#   * 三体：地球 + 月球 + 测试粒子，CR3BP 旋转系方程（含 Coriolis/离心），
#     固定步长 RK4（步长上限 60 s），输出惯性/旋转位置/速度。
#   * 平衡点：L1–L5 共线点二分求解 + L4/L5 等边；Jacobi 常数、能量代理、NaN 检查。
#   * 初始化：GEO、月球低轨（LLO，可倾角）、地月转移椭圆、L 点附近测试粒子。
#   * 交会辅助（纯数学，不接武器/伤害）：
#     - 相对状态（Δr/Δv/距离/接近率/TCA/LVLH 基）
#     - Hill/CW 相对运动解析传播
#     - 接近走廊（轴向/横向/半角/接近速度）
#     - 对接端口几何（轴向/横向/对齐角/接触速度/状态）
#   * `propagate_state(state, dt)` / `propagate_states(states, dt)` /
#     `sample_entity(id)`（实例实体推进与采样），全部 JSON 可序列化。
#
# 单位：km、km/s、s；CR3BP 归一化长度 D=384,400 km、时间 1/ω（ω=2π/T_moon）。
# 边界：忽略地球扁率/J2、太阳引力、月球偏心率与倾角、质心摆动；
#       地球固定在 barycenter 旋转系 (-μD,0,0)、月球在 ((1-μ)D,0,0)。
# ═══════════════════════════════════════════════════════════════════

# ── 物理常数（km / km³/s² / s）────────────────────────────────────
const MU_EARTH_KM3_S2 := 398600.4418
const MU_MOON_KM3_S2 := 4902.800118
const R_EARTH_KM := 6378.137
const R_MOON_KM := 1737.4
const D_KM := 384400.0                     # 地月平均距离
const T_MOON_S := 27.321661 * 86400.0     # 月球恒星周期 ≈ 2,360,591.51 s
const GEO_RADIUS_KM := 42164.0
const LLO_ALTITUDE_KM := 100.0
const MOON_ROTATION_PERIOD_S := T_MOON_S  # 同步自转

# ── 数值 / 安全限制 ─────────────────────────────────────────────
const MAX_STEP_S := 60.0                  # 固定步长上限（任务要求 ≤60 s）
const DEFAULT_STEP_S := 60.0
const DEFAULT_MAX_STEPS := 2000000
const JACOBI_DRIFT_WARN := 1.0e-6         # 归一化 Jacobi 漂移告警阈值
const MIN_RADIUS_KM := 1.0                # 奇异半径保护
const EPS := 1.0e-12

# ── 派生量（不能 const 折叠的用 static func）────────────────────
static func mu_total() -> float:
	return MU_EARTH_KM3_S2 + MU_MOON_KM3_S2


static func mu_moon_ratio() -> float:
	return MU_MOON_KM3_S2 / mu_total()


static func moon_mean_motion() -> float:
	return TAU / T_MOON_S


## CR3BP 归一化时间单位 T_c = sqrt(D³/μ_total) = T_moon/(2π)。
static func canonical_time_s() -> float:
	return sqrt(D_KM * D_KM * D_KM / mu_total())


static func canonical_velocity_kms() -> float:
	return D_KM / canonical_time_s()


static func geo_radius_km() -> float:
	return GEO_RADIUS_KM


static func llo_radius_km() -> float:
	return R_MOON_KM + LLO_ALTITUDE_KM


# ═══════════════════════════════════════════════════════════════════
# 0. 向量 / 状态工具
# ═══════════════════════════════════════════════════════════════════

static func to_vec3(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if value is Dictionary:
		var d: Dictionary = value
		for k in ["r", "pos", "position", "pos_km", "position_km"]:
			if d.has(k):
				return to_vec3(d.get(k), fallback)
	return fallback


## 内部状态：{"r": Vector3, "v": Vector3}；接受 {r,v}、{pos,vel}、[x,y,z,vx,vy,vz]。
static func make_state(r: Vector3, v: Vector3) -> Dictionary:
	return {"r": r, "v": v}


static func as_state(value: Variant) -> Dictionary:
	if value is Dictionary:
		var d: Dictionary = value
		var r := to_vec3(d.get("r", d.get("pos", d.get("position"))), Vector3.ZERO)
		var v := to_vec3(d.get("v", d.get("vel", d.get("velocity"))), Vector3.ZERO)
		return {"r": r, "v": v}
	if value is Array and (value as Array).size() >= 6:
		var a: Array = value
		return {"r": Vector3(float(a[0]), float(a[1]), float(a[2])),
			"v": Vector3(float(a[3]), float(a[4]), float(a[5]))}
	return {"r": Vector3.ZERO, "v": Vector3.ZERO}


## 状态数组形式（JSON 安全）：{r:[x,y,z], v:[vx,vy,vz]}。
static func state_to_array_dict(state: Variant) -> Dictionary:
	var s := as_state(state)
	return {"r": [s["r"].x, s["r"].y, s["r"].z],
		"v": [s["v"].x, s["v"].y, s["v"].z]}


static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func is_finite_state(state: Variant) -> bool:
	var s := as_state(state)
	return is_finite_vec(s["r"]) and is_finite_vec(s["v"])


## 状态合法性检查：{ok, errors:[...], radius_km, speed_kmps, finite}。
static func validate_state(state: Variant, opts := {}) -> Dictionary:
	var s := as_state(state)
	var errors: Array[String] = []
	if not is_finite_vec(s["r"]):
		errors.append("position_not_finite")
	if not is_finite_vec(s["v"]):
		errors.append("velocity_not_finite")
	var r: Vector3 = s["r"]
	var rad := r.length()
	if rad < MIN_RADIUS_KM:
		errors.append("radius_too_small(%.3f km)" % rad)
	var max_r := float(opts.get("max_radius_km", 2.0e6))
	if rad > max_r:
		errors.append("radius_too_large(%.6f km)" % rad)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"finite": is_finite_vec(r) and is_finite_vec(s["v"]),
		"radius_km": rad,
		"speed_kmps": (s["v"] as Vector3).length(),
	}


## 把非有限状态安全化（NaN/Inf → 0），返回 {state, changed, finite}。
static func sanitize_state(state: Variant) -> Dictionary:
	var s := as_state(state)
	var r: Vector3 = s["r"]
	var v: Vector3 = s["v"]
	var changed := false
	if not is_finite(r.x):
		r.x = 0.0
		changed = true
	if not is_finite(r.y):
		r.y = 0.0
		changed = true
	if not is_finite(r.z):
		r.z = 0.0
		changed = true
	if not is_finite(v.x):
		v.x = 0.0
		changed = true
	if not is_finite(v.y):
		v.y = 0.0
		changed = true
	if not is_finite(v.z):
		v.z = 0.0
		changed = true
	return {"state": make_state(r, v), "changed": changed,
		"finite": is_finite_vec(r) and is_finite_vec(v)}


# ═══════════════════════════════════════════════════════════════════
# 1. 参考系 / 几何位置
# ═══════════════════════════════════════════════════════════════════

## 旋转系中地球/月球位置（barycenter origin，月球在 +x）。
static func earth_position_rot() -> Vector3:
	return Vector3(-mu_moon_ratio() * D_KM, 0.0, 0.0)


static func moon_position_rot() -> Vector3:
	return Vector3((1.0 - mu_moon_ratio()) * D_KM, 0.0, 0.0)


static func earth_position_eci(t: float) -> Vector3:
	var theta := moon_mean_motion() * t
	var ep := earth_position_rot()
	return Vector3(ep.x * cos(theta) - ep.y * sin(theta),
		ep.x * sin(theta) + ep.y * cos(theta), 0.0)


static func earth_velocity_eci(t: float) -> Vector3:
	return Vector3(0.0, 0.0, moon_mean_motion()).cross(earth_position_eci(t))


## 月球相位 θ = ω·t（rad，t=0 时月球在 +x）。
static func moon_phase(t: float) -> float:
	return fposmod(moon_mean_motion() * t, TAU)


## 月球地心惯性状态（地球中心 ECI；t=0 时月球在 +x）。
static func moon_state_eci(t: float) -> Dictionary:
	var theta := moon_mean_motion() * t
	var pos := Vector3(cos(theta), sin(theta), 0.0) * D_KM
	var vel := Vector3(-sin(theta), cos(theta), 0.0) * (moon_mean_motion() * D_KM)
	return {"r": pos, "v": vel, "phase_rad": theta, "period_s": T_MOON_S,
		"distance_km": D_KM, "speed_kmps": vel.length()}


static func moon_state_rot() -> Dictionary:
	return {"r": moon_position_rot(), "v": Vector3.ZERO, "distance_km": D_KM}


# 旋转系 → 地心 ECI / 地心旋转系，反之亦然
## A-02：**双精度标量**帧转换路径（集中转换器）。
## 既有 Vector3 实现在 EML1 大坐标（~3.2e5 km）处会引入单精度量化误差
## （实测速度往返误差 ~1.9e-5 km/s），不满足 Phase A 的「双精度确定性转换」阈值
## （位置 ≤1e-6 km、速度 ≤1e-9 km/s）。这里用 GDScript double 标量实现同一公式，
## 供物理适配层使用；Vector3 版本保留给显示层，阈值不扩大。
static func earth_position_rot_array() -> Array:
	return [-mu_moon_ratio() * D_KM, 0.0, 0.0]


static func bary_rot_to_earth_eci_arrays(r: Array, v: Array, at_t: float) -> Dictionary:
	var e := earth_position_rot_array()
	var rx := float(r[0]) - float(e[0])
	var ry := float(r[1]) - float(e[1])
	var rz := float(r[2]) - float(e[2])
	var theta := moon_mean_motion() * at_t
	var c := cos(theta)
	var sn := sin(theta)
	var om := moon_mean_motion()
	# v_rot = v + omega x r_rel（omega = (0,0,om)）
	var vx := float(v[0]) + (-om * ry)
	var vy := float(v[1]) + (om * rx)
	var vz := float(v[2])
	return {
		"r": [rx * c - ry * sn, rx * sn + ry * c, rz],
		"v": [vx * c - vy * sn, vx * sn + vy * c, vz],
	}


static func earth_eci_to_bary_rot_arrays(r: Array, v: Array, at_t: float) -> Dictionary:
	var rx := float(r[0])
	var ry := float(r[1])
	var rz := float(r[2])
	var vx := float(v[0])
	var vy := float(v[1])
	var vz := float(v[2])
	var theta := moon_mean_motion() * at_t
	var c := cos(theta)
	var sn := sin(theta)
	# 逆旋转（-theta）
	var rrx := rx * c + ry * sn
	var rry := -rx * sn + ry * c
	var vrx := vx * c + vy * sn
	var vry := -vx * sn + vy * c
	var om := moon_mean_motion()
	# v = v_rot - omega x r_rel
	var bx := vrx - (-om * rry)
	var by := vry - (om * rrx)
	var e := earth_position_rot_array()
	return {
		"r": [rrx + float(e[0]), rry + float(e[1]), rz + float(e[2])],
		"v": [bx, by, vz],
	}


static func bary_rot_to_earth_rot_arrays(r: Array, v: Array) -> Dictionary:
	var e := earth_position_rot_array()
	return {
		"r": [float(r[0]) - float(e[0]), float(r[1]) - float(e[1]), float(r[2]) - float(e[2])],
		"v": [float(v[0]), float(v[1]), float(v[2])],
	}


static func earth_rot_to_bary_rot_arrays(r: Array, v: Array) -> Dictionary:
	var e := earth_position_rot_array()
	return {
		"r": [float(r[0]) + float(e[0]), float(r[1]) + float(e[1]), float(r[2]) + float(e[2])],
		"v": [float(v[0]), float(v[1]), float(v[2])],
	}

static func bary_rot_to_earth_rot(state: Variant) -> Dictionary:
	var s := as_state(state)
	var rel: Vector3 = s["r"] - earth_position_rot()
	return {"r": rel, "v": s["v"]}


static func earth_rot_to_bary_rot(state: Variant) -> Dictionary:
	var s := as_state(state)
	return {"r": s["r"] + earth_position_rot(), "v": s["v"]}


static func bary_rot_to_earth_eci(state: Variant, t: float) -> Dictionary:
	var s := as_state(state)
	var theta := moon_mean_motion() * t
	var c := cos(theta)
	var sn := sin(theta)
	var r_rel: Vector3 = s["r"] - earth_position_rot()
	var omega_vec := Vector3(0.0, 0.0, moon_mean_motion())
	var v_rot: Vector3 = s["v"] + omega_vec.cross(r_rel)
	var r_eci := Vector3(r_rel.x * c - r_rel.y * sn, r_rel.x * sn + r_rel.y * c, r_rel.z)
	var v_eci := Vector3(v_rot.x * c - v_rot.y * sn, v_rot.x * sn + v_rot.y * c, v_rot.z)
	return {"r": r_eci, "v": v_eci}


static func earth_eci_to_bary_rot(state: Variant, t: float) -> Dictionary:
	var s := as_state(state)
	var theta := moon_mean_motion() * t
	var c := cos(theta)
	var sn := sin(theta)
	var r_eci: Vector3 = s["r"]
	var v_eci: Vector3 = s["v"]
	var r_rel := Vector3(r_eci.x * c + r_eci.y * sn, -r_eci.x * sn + r_eci.y * c, r_eci.z)
	var v_rel_i := Vector3(v_eci.x * c + v_eci.y * sn, -v_eci.x * sn + v_eci.y * c, v_eci.z)
	var r_bary := r_rel + earth_position_rot()
	var omega_vec := Vector3(0.0, 0.0, moon_mean_motion())
	var v_rot := v_rel_i - omega_vec.cross(r_bary - earth_position_rot())
	return {"r": r_bary, "v": v_rot}


# ── 归一化（CR3BP canonical units）────────────────────────────────
static func to_canonical(state: Variant) -> Dictionary:
	var s := as_state(state)
	var tc := canonical_time_s()
	return {"r": (s["r"] as Vector3) / D_KM, "v": (s["v"] as Vector3) * (tc / D_KM)}


static func from_canonical(state: Variant) -> Dictionary:
	var s := as_state(state)
	var tc := canonical_time_s()
	return {"r": (s["r"] as Vector3) * D_KM, "v": (s["v"] as Vector3) * (D_KM / tc)}


static func speed_for_circular_orbit(mu_km3_s2: float, radius_km: float) -> float:
	if radius_km <= 0.0 or mu_km3_s2 <= 0.0:
		return 0.0
	return sqrt(mu_km3_s2 / radius_km)


static func period_for_circular_orbit(mu_km3_s2: float, radius_km: float) -> float:
	if radius_km <= 0.0 or mu_km3_s2 <= 0.0:
		return 0.0
	return TAU * sqrt(radius_km * radius_km * radius_km / mu_km3_s2)


# ═══════════════════════════════════════════════════════════════════
# 2. CR3BP：方程 / RK4 / Jacobi
# ═══════════════════════════════════════════════════════════════════

## CR3BP 旋转系加速度（barycenter rotating）：地球/月球 + Coriolis + 离心。
static func acceleration_rot(state: Variant) -> Vector3:
	var s := as_state(state)
	var r: Vector3 = s["r"]
	var v: Vector3 = s["v"]
	var r1 := r - earth_position_rot()
	var r2 := r - moon_position_rot()
	var d1 := maxf(MIN_RADIUS_KM, r1.length())
	var d2 := maxf(MIN_RADIUS_KM, r2.length())
	var grav := -MU_EARTH_KM3_S2 * r1 / (d1 * d1 * d1) \
		- MU_MOON_KM3_S2 * r2 / (d2 * d2 * d2)
	var omega_vec := Vector3(0.0, 0.0, moon_mean_motion())
	var coriolis := -2.0 * omega_vec.cross(v)
	var centrifugal := -omega_vec.cross(omega_vec.cross(r))
	return grav + coriolis + centrifugal


## 单步 RK4（CR3BP 旋转系）。
static func rk4_step(state: Variant, dt: float) -> Dictionary:
	return rk4_step_accel(state, dt, Vector3.ZERO)


## 单步 RK4（CR3BP 旋转系）+ 常值附加加速度。
## `extra_accel` 在单步内视为常向量（km/s²）：用于弹丸推力、阻力等非引力项。
## 步长须足够小（弹道调用方按 1 s 子步），否则常值假设失效。
static func rk4_step_accel(state: Variant, dt: float, extra_accel: Vector3) -> Dictionary:
	var s := as_state(state)
	var r: Vector3 = s["r"]
	var v: Vector3 = s["v"]
	if dt == 0.0:
		return make_state(r, v)
	var k1r := v
	var k1v := acceleration_rot(make_state(r, v)) + extra_accel
	var v2 := v + k1v * (dt * 0.5)
	var r2 := r + k1r * (dt * 0.5)
	var k2r := v2
	var k2v := acceleration_rot(make_state(r2, v2)) + extra_accel
	var v3 := v + k2v * (dt * 0.5)
	var r3 := r + k2r * (dt * 0.5)
	var k3r := v3
	var k3v := acceleration_rot(make_state(r3, v3)) + extra_accel
	var v4 := v + k3v * dt
	var r4 := r + k3r * dt
	var k4r := v4
	var k4v := acceleration_rot(make_state(r4, v4)) + extra_accel
	var new_r := r + (k1r + 2.0 * k2r + 2.0 * k3r + k4r) * (dt / 6.0)
	var new_v := v + (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * (dt / 6.0)
	return make_state(new_r, new_v)


## 旋转系有效势 Ω（物理单位 km²/s²）。
static func effective_potential(state: Variant) -> float:
	var s := as_state(state)
	var r: Vector3 = s["r"]
	var r1 := (r - earth_position_rot()).length()
	var r2 := (r - moon_position_rot()).length()
	var omega2 := moon_mean_motion() * moon_mean_motion()
	return 0.5 * omega2 * (r.x * r.x + r.y * r.y) \
		+ MU_EARTH_KM3_S2 / maxf(MIN_RADIUS_KM, r1) \
		+ MU_MOON_KM3_S2 / maxf(MIN_RADIUS_KM, r2)


## Jacobi 常数（归一化；CR3BP 守恒量）：C = 2Ω/(ω²D²) − v²/(ω²D²)。
static func jacobi_constant(state: Variant) -> float:
	var s := as_state(state)
	if not is_finite_state(s):
		return NAN
	var scale := moon_mean_motion() * moon_mean_motion() * D_KM * D_KM
	return 2.0 * effective_potential(s) / scale \
		- (s["v"] as Vector3).length_squared() / scale


## 能量代理（守恒量，与 Jacobi 等价）：0.5|v|² − Ω（km²/s²）。
static func energy_proxy(state: Variant) -> float:
	var s := as_state(state)
	if not is_finite_state(s):
		return NAN
	return 0.5 * (s["v"] as Vector3).length_squared() - effective_potential(s)


## 固定步长 RK4 传播（CR3BP 旋转系）。步长 ≤ 60 s；返回结果与诊断。
## opts: {step_s, max_steps, jacobi_tol}
static func propagate_state(state: Variant, dt: float, opts := {}) -> Dictionary:
	var s := as_state(state)
	var check := validate_state(s)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": "invalid_state", "errors": check.get("errors", []),
			"state": state_to_array_dict(s), "finite": false}
	if absf(dt) < EPS:
		return {"ok": true, "state": state_to_array_dict(s), "steps": 0,
			"jacobi": jacobi_constant(s), "jacobi_drift": 0.0,
			"energy": energy_proxy(s), "finite": true, "warnings": []}
	var step_req := float(opts.get("step_s", DEFAULT_STEP_S))
	var step := clampf(step_req, 1.0e-6, MAX_STEP_S)
	var max_steps := maxi(1, int(opts.get("max_steps", DEFAULT_MAX_STEPS)))
	var n := int(ceil(absf(dt) / step))
	if n > max_steps:
		return {"ok": false, "reason": "max_steps_exceeded",
			"requested_steps": n, "max_steps": max_steps,
			"state": state_to_array_dict(s), "finite": true}
	var sign := 1.0 if dt > 0.0 else -1.0
	var h := absf(dt) / float(n) * sign
	var cur := s
	var jac0 := jacobi_constant(cur)
	var warnings: Array = []
	for i in range(n):
		cur = rk4_step(cur, h)
		if not is_finite_state(cur):
			var safe := sanitize_state(cur)
			return {"ok": false, "reason": "non_finite_state", "state": state_to_array_dict(safe["state"]),
				"finite": false, "steps": i + 1, "jacobi": NAN,
				"jacobi_start": jac0, "warnings": ["RK4 发散：出现 NaN/Inf（已安全化返回）"]}
	var jac1 := jacobi_constant(cur)
	var drift := absf(jac1 - jac0) if is_finite(jac1) and is_finite(jac0) else NAN
	var tol := float(opts.get("jacobi_tol", JACOBI_DRIFT_WARN))
	if is_finite(drift) and drift > tol:
		warnings.append("Jacobi 漂移 %.6f > 阈值 %.6f" % [drift, tol])
	return {
		"ok": true,
		"state": state_to_array_dict(cur),
		"steps": n,
		"step_s": absf(h),
		"t_start": 0.0,
		"t_end": dt,
		"jacobi_start": jac0,
		"jacobi": jac1,
		"jacobi_drift": drift,
		"energy_start": energy_proxy(s),
		"energy": energy_proxy(cur),
		"finite": true,
		"warnings": warnings,
	}


## 批量传播：states 数组 → 每个元素同 propagate_state 结果（不改变输入）。
static func propagate_states(states: Array, dt: float, opts := {}) -> Array:
	var out: Array = []
	for raw in states:
		out.append(propagate_state(raw, dt, opts))
	return out


# ═══════════════════════════════════════════════════════════════════
# 3. 两体 RK4（验证轨道闭合 / GEO / LLO / 转移初始化）
# ═══════════════════════════════════════════════════════════════════

static func acceleration_two_body(r: Vector3, mu_km3_s2: float) -> Vector3:
	var d := r.length()
	if d < MIN_RADIUS_KM:
		return Vector3.ZERO
	return -mu_km3_s2 * r / (d * d * d)


static func rk4_step_two_body(state: Variant, mu_km3_s2: float, dt: float) -> Dictionary:
	var s := as_state(state)
	var r: Vector3 = s["r"]
	var v: Vector3 = s["v"]
	if dt == 0.0:
		return make_state(r, v)
	var a1 := acceleration_two_body(r, mu_km3_s2)
	var v2 := v + a1 * (dt * 0.5)
	var r2 := r + v * (dt * 0.5)
	var a2 := acceleration_two_body(r2, mu_km3_s2)
	var v3 := v + a2 * (dt * 0.5)
	var r3 := r + v2 * (dt * 0.5)
	var a3 := acceleration_two_body(r3, mu_km3_s2)
	var v4 := v + a3 * dt
	var r4 := r + v3 * dt
	var a4 := acceleration_two_body(r4, mu_km3_s2)
	return make_state(r + (v + 2.0 * v2 + 2.0 * v3 + v4) * (dt / 6.0),
		v + (a1 + 2.0 * a2 + 2.0 * a3 + a4) * (dt / 6.0))


## 两体固定步长 RK4 传播（用于轨道闭合误差验证；步长 ≤ 60 s）。
static func propagate_two_body(state: Variant, mu_km3_s2: float, dt: float, opts := {}) -> Dictionary:
	var s := as_state(state)
	var check := validate_state(s)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": "invalid_state", "errors": check.get("errors", [])}
	if absf(dt) < EPS:
		return {"ok": true, "state": state_to_array_dict(s), "steps": 0}
	var step := clampf(float(opts.get("step_s", DEFAULT_STEP_S)), 1.0e-6, MAX_STEP_S)
	var n := maxi(1, int(ceil(absf(dt) / step)))
	var h := dt / float(n)
	var cur := s
	for i in range(n):
		cur = rk4_step_two_body(cur, mu_km3_s2, h)
		if not is_finite_state(cur):
			return {"ok": false, "reason": "non_finite_state", "steps": i + 1,
				"state": state_to_array_dict(s), "finite": false}
	return {"ok": true, "state": state_to_array_dict(cur), "steps": n, "step_s": absf(h)}


## 两体圆轨道状态（惯性系，XY 面；phase 从 +x 起逆时针）。
static func two_body_circular_state(mu_km3_s2: float, radius_km: float, phase_rad: float,
		inclination_deg := 0.0) -> Dictionary:
	var inc := deg_to_rad(inclination_deg)
	var r_plane := Vector3(cos(phase_rad) * radius_km, sin(phase_rad) * radius_km, 0.0)
	var v_mag := speed_for_circular_orbit(mu_km3_s2, radius_km)
	var v_plane := Vector3(-sin(phase_rad), cos(phase_rad), 0.0) * v_mag
	# 绕 x 轴倾角
	var r_inc := Vector3(r_plane.x, r_plane.y * cos(inc), r_plane.y * sin(inc))
	var v_inc := Vector3(v_plane.x, v_plane.y * cos(inc), v_plane.y * sin(inc))
	return {"r": r_inc, "v": v_inc, "radius_km": radius_km, "speed_kmps": v_mag,
		"period_s": period_for_circular_orbit(mu_km3_s2, radius_km),
		"mu_km3_s2": mu_km3_s2, "frame": "earth_eci" if mu_km3_s2 == MU_EARTH_KM3_S2 else "central_eci"}


## 地球同步轨道状态（地心 ECI；phase 从 +x 起；t=0 相位 phase0）。
static func geo_state(t: float, phase0 := 0.0) -> Dictionary:
	var period := period_for_circular_orbit(MU_EARTH_KM3_S2, GEO_RADIUS_KM)
	var phase := phase0 + TAU * fposmod(t, period) / period
	var st := two_body_circular_state(MU_EARTH_KM3_S2, GEO_RADIUS_KM, phase)
	st["phase_rad"] = phase
	st["t"] = t
	st["id"] = "geo"
	return st


## 月球低轨（LLO）状态：月球 ECI 位置 + 绕月圆轨道（可倾角），地心 ECI 输出。
static func llo_state(t: float, phase0 := 0.0, inclination_deg := 0.0, altitude_km := LLO_ALTITUDE_KM) -> Dictionary:
	var radius := R_MOON_KM + altitude_km
	var moon := moon_state_eci(t)
	var moon_pos: Vector3 = moon["r"]
	var moon_vel: Vector3 = moon["v"]
	var inc := deg_to_rad(inclination_deg)
	# 轨道法向：默认沿地月轨道法向 +z，绕 x 倾角
	var normal := Vector3(0.0, 0.0, 1.0)
	normal = Vector3(normal.x, normal.y * cos(inc) - normal.z * sin(inc),
		normal.y * sin(inc) + normal.z * cos(inc)).normalized()
	var u := moon_pos.normalized()
	if absf(u.dot(normal)) > 0.95:
		u = Vector3.RIGHT
	var w := normal.cross(u).normalized()
	var u2 := w.cross(normal).normalized()
	var period := period_for_circular_orbit(MU_MOON_KM3_S2, radius)
	var phase := phase0 + TAU * fposmod(t, period) / period
	var rel_r := (u2 * cos(phase) + w * sin(phase)) * radius
	var speed := speed_for_circular_orbit(MU_MOON_KM3_S2, radius)
	var rel_v := (u2 * -sin(phase) + w * cos(phase)) * speed
	return {"r": moon_pos + rel_r, "v": moon_vel + rel_v,
		"radius_km": radius, "speed_kmps": speed, "period_s": period,
		"phase_rad": phase, "inclination_deg": inclination_deg, "frame": "earth_eci", "id": "lunar_leo"}


## 地月转移椭圆初始化（地心两体；perigee/apogee 半径，ν=真近点角）。
static func transfer_state(perigee_km: float, apogee_km: float, true_anomaly_deg := 0.0) -> Dictionary:
	var rp := maxf(MIN_RADIUS_KM, perigee_km)
	var ra := maxf(rp, apogee_km)
	var a := (rp + ra) * 0.5
	var e := (ra - rp) / (ra + rp)
	var nu := deg_to_rad(true_anomaly_deg)
	var r := a * (1.0 - e * e) / (1.0 + e * cos(nu))
	var speed := sqrt(MU_EARTH_KM3_S2 * (2.0 / r - 1.0 / a))
	var pos := Vector3(cos(nu) * r, sin(nu) * r, 0.0)
	var vel := Vector3(-sin(nu), cos(nu) + e, 0.0).normalized() * speed
	return {"r": pos, "v": vel, "a_km": a, "e": e, "perigee_km": rp, "apogee_km": ra,
		"period_s": TAU * sqrt(a * a * a / MU_EARTH_KM3_S2), "frame": "earth_eci"}


# ═══════════════════════════════════════════════════════════════════
# 4. CR3BP 平衡点 L1–L5 / Jacobi
# ═══════════════════════════════════════════════════════════════════

static func _collinear_equation(x: float) -> float:
	var mu := mu_moon_ratio()
	var d1 := absf(x + mu)
	var d2 := absf(x - 1.0 + mu)
	if d1 < 1.0e-14 or d2 < 1.0e-14:
		return NAN
	return x - (1.0 - mu) * (x + mu) / (d1 * d1 * d1) \
		- mu * (x - 1.0 + mu) / (d2 * d2 * d2)


static func _bisect(lo: float, hi: float, mu := 0.012150585, iterations := 200) -> float:
	var a := lo
	var b := hi
	var fa := _collinear_equation(a)
	var fb := _collinear_equation(b)
	if is_nan(fa) or is_nan(fb) or fa * fb > 0.0:
		return NAN
	var norm_a := a
	var norm_b := b
	for i in range(iterations):
		var mid := 0.5 * (norm_a + norm_b)
		var fm := _collinear_equation(mid)
		if is_nan(fm):
			return mid
		if fm * fa <= 0.0:
			norm_b = mid
			fb = fm
		else:
			norm_a = mid
			fa = fm
		if absf(norm_b - norm_a) < 1.0e-15:
			break
	return 0.5 * (norm_a + norm_b)


## L1–L5（barycenter rotating 归一化位置）；同时给出物理位置/km/距离/Jacobi。
static func equilibrium_points() -> Dictionary:
	var mu := mu_moon_ratio()
	var x1 := _bisect(-mu + 1.0e-6, 1.0 - mu - 1.0e-6)
	var x2 := _bisect(1.0 - mu + 1.0e-6, 2.0)
	var x3 := _bisect(-2.0, -mu - 1.0e-6)
	var out: Dictionary = {}
	var ids := ["L1", "L2", "L3", "L4", "L5"]
	var positions: Array = []
	if is_nan(x1) or is_nan(x2) or is_nan(x3):
		return {}
	positions.append(Vector3(x1, 0.0, 0.0))
	positions.append(Vector3(x2, 0.0, 0.0))
	positions.append(Vector3(x3, 0.0, 0.0))
	positions.append(Vector3(0.5 - mu, sqrt(3.0) * 0.5, 0.0))
	positions.append(Vector3(0.5 - mu, -sqrt(3.0) * 0.5, 0.0))
	var earth_rot := earth_position_rot()
	var moon_rot := moon_position_rot()
	for i in range(ids.size()):
		var id := String(ids[i])
		var pos_norm: Vector3 = positions[i]
		var pos_phys := pos_norm * D_KM
		var st := make_state(pos_phys, Vector3.ZERO)
		out[id] = {
			"id": id,
			"pos_rot_norm": pos_norm,
			"pos_rot": pos_phys,
			"vel_rot": Vector3.ZERO,
			"earth_distance_km": (pos_phys - earth_rot).length(),
			"moon_distance_km": (pos_phys - moon_rot).length(),
			"jacobi": jacobi_constant(st),
			"kind": "collinear" if id in ["L1", "L2", "L3"] else "triangular",
		}
	return out


## L 点测试粒子初始化（barycenter rotating 物理状态，可加偏移/速度）。
static func lagrange_state(lpoint_id: String, offset_km := Vector3.ZERO, velocity_kmps := Vector3.ZERO) -> Dictionary:
	var lps := equilibrium_points()
	if not lps.has(lpoint_id):
		return {}
	var lp: Dictionary = lps[lpoint_id]
	return make_state((lp.get("pos_rot", Vector3.ZERO) as Vector3) + offset_km,
		velocity_kmps)


## 从地球 ECI 状态求 Jacobi（先转 barycenter rotating 再算）。
static func jacobi_from_earth_eci(state: Variant, t: float) -> float:
	return jacobi_constant(earth_eci_to_bary_rot(state, t))


# ═══════════════════════════════════════════════════════════════════
# 5. 相对运动 / Hill-CW
# ═══════════════════════════════════════════════════════════════════

static func relative_state(chaser: Variant, target: Variant) -> Dictionary:
	var c := as_state(chaser)
	var t := as_state(target)
	var dr: Vector3 = (t["r"] as Vector3) - (c["r"] as Vector3)
	var dv: Vector3 = (t["v"] as Vector3) - (c["v"] as Vector3)
	var range_km := dr.length()
	var range_rate := 0.0
	var closing := 0.0
	var tca := -1.0
	if range_km > EPS:
		range_rate = dr.dot(dv) / range_km
		closing = -range_rate
		if closing > EPS:
			tca = range_km / closing
	var los := dr / range_km if range_km > EPS else Vector3.ZERO
	return {
		"dr": dr, "dv": dv,
		"range_km": range_km,
		"range_rate_kmps": range_rate,
		"closing_kmps": closing,
		"relative_speed_kmps": dv.length(),
		"tca_s": tca,
		"los_unit": los,
	}


## LVLH 基：R 径向、S 沿迹、W 轨道法向（右手）。
static func lvlh_basis(r: Vector3, v: Vector3) -> Dictionary:
	var R := r.normalized()
	if R.length() < EPS:
		R = Vector3.RIGHT
	var W := r.cross(v).normalized()
	if W.length() < EPS:
		W = Vector3.UP
	var S := W.cross(R).normalized()
	return {"R": R, "S": S, "W": W}


static func to_lvlh(vec_eci: Vector3, basis: Dictionary) -> Vector3:
	return Vector3(vec_eci.dot(basis["R"]), vec_eci.dot(basis["S"]), vec_eci.dot(basis["W"]))


## Hill/CW 6×6 状态转移矩阵（LVLH，状态序 [x,y,z,vx,vy,vz]；x=R, y=S, z=W）。
static func cw_matrix(n: float, t: float) -> Array:
	var nt := n * t
	var c := cos(nt)
	var s := sin(nt)
	var one_c := 1.0 - c
	var m: Array = []
	for i in range(6):
		m.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	m[0][0] = 4.0 - 3.0 * c
	m[0][1] = 0.0
	m[0][2] = 0.0
	m[0][3] = s / n
	m[0][4] = 2.0 * one_c / n
	m[0][5] = 0.0
	m[1][0] = 6.0 * (s - nt)
	m[1][1] = 1.0
	m[1][2] = 0.0
	m[1][3] = -2.0 * one_c / n
	m[1][4] = (4.0 * s - 3.0 * nt) / n
	m[1][5] = 0.0
	m[2][0] = 0.0
	m[2][1] = 0.0
	m[2][2] = c
	m[2][3] = 0.0
	m[2][4] = 0.0
	m[2][5] = s / n
	m[3][0] = 3.0 * n * s
	m[3][1] = 0.0
	m[3][2] = 0.0
	m[3][3] = c
	m[3][4] = 2.0 * s
	m[3][5] = 0.0
	m[4][0] = 6.0 * n * (c - 1.0)
	m[4][1] = 0.0
	m[4][2] = 0.0
	m[4][3] = -2.0 * s
	m[4][4] = 4.0 * c - 3.0
	m[4][5] = 0.0
	m[5][0] = 0.0
	m[5][1] = 0.0
	m[5][2] = -n * s
	m[5][3] = 0.0
	m[5][4] = 0.0
	m[5][5] = c
	return m


## 相对状态（CW）解析传播。rel 支持 {x,y,z,vx,vy,vz} 或 {r,v}（LVLH 分量）。
static func propagate_cw(rel: Variant, n: float, t: float) -> Dictionary:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	if rel is Dictionary:
		var d: Dictionary = rel
		x = float(d.get("x", 0.0))
		y = float(d.get("y", 0.0))
		z = float(d.get("z", 0.0))
		vx = float(d.get("vx", 0.0))
		vy = float(d.get("vy", 0.0))
		vz = float(d.get("vz", 0.0))
	var m := cw_matrix(n, t)
	var out: Dictionary = {}
	var labels := ["x", "y", "z", "vx", "vy", "vz"]
	var vals := [x, y, z, vx, vy, vz]
	for i in range(6):
		var acc := 0.0
		for j in range(6):
			acc += float(m[i][j]) * float(vals[j])
		out[labels[i]] = acc
	out["n"] = n
	out["t"] = t
	return out


# ═══════════════════════════════════════════════════════════════════
# 6. 接近走廊 / 对接端口几何（纯数学）
# ═══════════════════════════════════════════════════════════════════

static func default_corridor_spec() -> Dictionary:
	return {
		"axis": [1.0, 0.0, 0.0],
		"length_km": 100.0,
		"half_angle_deg": 10.0,
		"lateral_tol_km": 2.0,
		"max_closing_mps": 50.0,
		"max_angle_deg": 15.0,
		"min_along_km": 0.0,
	}


## 接近走廊：给定相对位置/速度（同一 LVLH 系），检查轴向/横向/半角/接近速度。
static func approach_corridor_check(rel_pos: Vector3, rel_vel: Vector3, spec := {}) -> Dictionary:
	var sp := default_corridor_spec()
	if spec is Dictionary:
		for k in (spec as Dictionary).keys():
			sp[String(k)] = (spec as Dictionary)[k]
	var axis := to_vec3(sp.get("axis", [1.0, 0.0, 0.0]), Vector3.RIGHT).normalized()
	if axis.length() < EPS:
		axis = Vector3.RIGHT
	var range_km := rel_pos.length()
	var along := rel_pos.dot(axis)
	var lateral_vec := rel_pos - axis * along
	var lateral := lateral_vec.length()
	var half_angle := deg_to_rad(float(sp.get("half_angle_deg", 10.0)))
	var corridor_radius := tan(half_angle) * maxf(along, 0.0) + float(sp.get("lateral_tol_km", 2.0))
	var closing := 0.0
	if range_km > EPS:
		closing = -rel_pos.dot(rel_vel) / range_km
	var align_angle := 180.0
	if range_km > EPS:
		align_angle = rad_to_deg(acos(clampf(axis.dot(rel_pos.normalized()), -1.0, 1.0)))
	var inside := along >= float(sp.get("min_along_km", 0.0)) \
		and along <= float(sp.get("length_km", 100.0)) \
		and lateral <= corridor_radius + 1.0e-9
	var angle_ok := align_angle <= float(sp.get("max_angle_deg", 15.0)) + 1.0e-9
	var speed_ok := closing <= float(sp.get("max_closing_mps", 50.0)) * 0.001 + 1.0e-12
	var warnings: Array = []
	if not inside:
		warnings.append("超出接近走廊（along=%.1f km lateral=%.1f km 允许 %.1f km）" % [
			along, lateral, corridor_radius])
	if not angle_ok:
		warnings.append("接近轴偏差 %.1f° > %.1f°" % [align_angle,
			float(sp.get("max_angle_deg", 15.0))])
	if not speed_ok:
		warnings.append("接近速度 %.2f m/s > %.1f m/s" % [closing * 1000.0,
			float(sp.get("max_closing_mps", 50.0)) * 1000.0])
	return {
		"ok": inside and angle_ok and speed_ok,
		"inside": inside,
		"range_km": range_km,
		"along_km": along,
		"lateral_km": lateral,
		"corridor_radius_km": corridor_radius,
		"half_angle_deg": float(sp.get("half_angle_deg", 10.0)),
		"align_angle_deg": align_angle,
		"closing_mps": closing * 1000.0,
		"angle_ok": angle_ok,
		"speed_ok": speed_ok,
		"warnings": warnings,
		"status": "in_corridor" if inside and angle_ok and speed_ok else "out_of_corridor",
	}


static func default_docking_spec() -> Dictionary:
	return {
		"docking_tol_km": 0.05,
		"lateral_tol_km": 0.2,
		"align_tol_deg": 5.0,
		"max_closing_mps": 50.0,
		"max_lateral_mps": 5.0,
		"dock_speed_mps": 0.1,
	}


## 对接端口几何：port_axis 为目标端口朝外方向；返回轴向/横向/对齐/速度/状态。
static func docking_geometry(rel_pos: Vector3, rel_vel: Vector3, port_axis: Vector3, spec := {}) -> Dictionary:
	var sp := default_docking_spec()
	if spec is Dictionary:
		for k in (spec as Dictionary).keys():
			sp[String(k)] = (spec as Dictionary)[k]
	var axis := port_axis.normalized()
	if axis.length() < EPS:
		axis = Vector3.RIGHT
	var range_km := rel_pos.length()
	var along := rel_pos.dot(axis)
	var lateral_vec := rel_pos - axis * along
	var lateral_km := lateral_vec.length()
	var approach_dir := rel_pos.normalized() if range_km > EPS else Vector3.ZERO
	var align_angle := rad_to_deg(acos(clampf(axis.dot(approach_dir), -1.0, 1.0)))
	var closing := -rel_pos.dot(rel_vel) / range_km if range_km > EPS else 0.0
	var lateral_vel := rel_vel - axis * rel_vel.dot(axis)
	var lateral_mps := lateral_vel.length() * 1000.0
	var status := "approach"
	var ok := false
	if range_km <= float(sp.get("docking_tol_km", 0.05)) \
			and closing * 1000.0 <= float(sp.get("dock_speed_mps", 0.1)) + 1.0e-9 \
			and lateral_km <= float(sp.get("lateral_tol_km", 0.2)) \
			and align_angle <= float(sp.get("align_tol_deg", 5.0)):
		status = "docked"
		ok = true
	elif lateral_km > float(sp.get("lateral_tol_km", 0.2)) \
			or lateral_mps > float(sp.get("max_lateral_mps", 0.1)) * 1000.0:
		status = "misaligned"
	elif closing * 1000.0 > float(sp.get("max_closing_mps", 50.0)) + 1.0e-9:
		status = "too_fast"
	elif align_angle > float(sp.get("align_tol_deg", 5.0)):
		status = "misaligned"
	else:
		status = "aligned"
		ok = true
	var warnings: Array = []
	if status == "misaligned":
		warnings.append("对接轴/横向偏差超限")
	if status == "too_fast":
		warnings.append("接触速度超限")
	return {
		"ok": ok,
		"status": status,
		"range_km": range_km,
		"axial_km": along,
		"lateral_km": lateral_km,
		"align_angle_deg": align_angle,
		"closing_mps": closing * 1000.0,
		"lateral_mps": lateral_mps,
		"warnings": warnings,
	}


## 对接进近序列检查：states（LVLH rel_pos/vel 数组）逐点给出状态/通过。
static func docking_sequence(states: Array, port_axis := Vector3.RIGHT, spec := {}) -> Array:
	var out: Array = []
	for raw in states:
		if raw is Dictionary:
			var d: Dictionary = raw
			var r := to_vec3(d.get("r", d.get("pos")), Vector3.ZERO)
			var v := to_vec3(d.get("v", d.get("vel")), Vector3.ZERO)
			var geo := docking_geometry(r, v, port_axis, spec)
			geo["index"] = out.size()
			out.append(geo)
	return out


# ═══════════════════════════════════════════════════════════════════
# 7. 实例：实体推进 / sample_entity
# ═══════════════════════════════════════════════════════════════════

var config: Dictionary = {}
var t := 0.0
var entities: Dictionary = {}      # id -> {state_rot:Dictionary, jacobi0, added_t}
var errors: Array[String] = []


func _init(opts := {}) -> void:
	config = {
		"step_s": float(opts.get("step_s", DEFAULT_STEP_S)) if opts is Dictionary else DEFAULT_STEP_S,
		"max_steps": int(opts.get("max_steps", DEFAULT_MAX_STEPS)) if opts is Dictionary else DEFAULT_MAX_STEPS,
		"jacobi_tol": float(opts.get("jacobi_tol", JACOBI_DRIFT_WARN)) if opts is Dictionary else JACOBI_DRIFT_WARN,
	}
	if float(config["step_s"]) <= 0.0 or float(config["step_s"]) > MAX_STEP_S:
		config["step_s"] = DEFAULT_STEP_S


func reset() -> void:
	t = 0.0
	entities.clear()
	errors.clear()


## 加入测试粒子（barycenter rotating 物理状态）。
func add_entity(entity_id: String, state: Variant) -> Dictionary:
	var s := as_state(state)
	var check := validate_state(s)
	if not bool(check.get("ok", false)):
		errors.append("entity %s invalid: %s" % [entity_id, str(check.get("errors", []))])
		return {"ok": false, "reason": "invalid_state", "errors": check.get("errors", [])}
	entities[entity_id] = {
		"id": entity_id,
		"state_rot": s,
		"jacobi0": jacobi_constant(s),
		"added_t": t,
	}
	return {"ok": true, "id": entity_id}


func remove_entity(entity_id: String) -> bool:
	return entities.erase(entity_id)


func entity_ids() -> Array:
	var out: Array = []
	for k in entities.keys():
		out.append(String(k))
	out.sort()
	return out


## 推进所有实体 dt 秒（固定步长 RK4；步长由 config 限制 ≤60 s）。
func propagate(dt: float) -> Dictionary:
	if absf(dt) < EPS:
		return {"ok": true, "t": t, "entities": sample_all(), "warnings": []}
	var step := clampf(float(config.get("step_s", DEFAULT_STEP_S)), 1.0e-6, MAX_STEP_S)
	var n := int(ceil(absf(dt) / step))
	var max_steps := maxi(1, int(config.get("max_steps", DEFAULT_MAX_STEPS)))
	if n > max_steps:
		return {"ok": false, "reason": "max_steps_exceeded", "requested_steps": n}
	var h := dt / float(n)
	var warnings: Array = []
	for i in range(n):
		for raw in entities.values():
			var ent: Dictionary = raw
			var cur: Dictionary = ent["state_rot"]
			var nxt := rk4_step(cur, h)
			if not is_finite_state(nxt):
				ent["state_rot"] = sanitize_state(cur)["state"]
				warnings.append("entity %s RK4 发散（NaN/Inf）" % String(ent.get("id", "")))
				continue
			ent["state_rot"] = nxt
	t += dt
	var tol := float(config.get("jacobi_tol", JACOBI_DRIFT_WARN))
	for raw2 in entities.values():
		var ent2: Dictionary = raw2
		var j1 := jacobi_constant(ent2["state_rot"])
		ent2["jacobi"] = j1
		var drift := absf(j1 - float(ent2.get("jacobi0", j1)))
		ent2["jacobi_drift"] = drift
		if drift > tol:
			warnings.append("entity %s Jacobi 漂移 %.6f" % [String(ent2.get("id", "")), drift])
	return {"ok": true, "t": t, "steps": n, "step_s": absf(h),
		"entities": sample_all(), "warnings": warnings}


## 采样实体：旋转系 + 地心惯性 + 地心旋转系 + Jacobi/能量，JSON 安全。
func sample_entity(entity_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var ent: Dictionary = entities[entity_id]
	var s: Dictionary = ent["state_rot"]
	var eci := bary_rot_to_earth_eci(s, t)
	var erot := bary_rot_to_earth_rot(s)
	var jac := jacobi_constant(s)
	return {
		"id": entity_id,
		"t": t,
		"state_rot": state_to_array_dict(s),
		"state_earth_eci": state_to_array_dict(eci),
		"state_earth_rot": state_to_array_dict(erot),
		"jacobi": jac,
		"energy": energy_proxy(s),
		"finite": is_finite_state(s),
		"earth_distance_km": (s["r"] as Vector3).distance_to(earth_position_rot()),
		"moon_distance_km": (s["r"] as Vector3).distance_to(moon_position_rot()),
	}


func sample_all() -> Array:
	var out: Array = []
	for eid in entity_ids():
		var sample := sample_entity(String(eid))
		if not sample.is_empty():
			out.append(sample)
	return out


func to_dict() -> Dictionary:
	return {
		"schema": "cislunar_physics.v1",
		"model": "cr3bp_rk4_circular",
		"authoritative": false,
		"t": t,
		"config": config.duplicate(true),
		"entities": sample_all(),
		"constants": {
			"mu_earth_km3_s2": MU_EARTH_KM3_S2,
			"mu_moon_km3_s2": MU_MOON_KM3_S2,
			"mu_moon_ratio": mu_moon_ratio(),
			"earth_moon_distance_km": D_KM,
			"moon_period_s": T_MOON_S,
			"canonical_time_s": canonical_time_s(),
			"canonical_velocity_kms": canonical_velocity_kms(),
			"geo_radius_km": GEO_RADIUS_KM,
			"lunar_leo_radius_km": llo_radius_km(),
		},
	}
