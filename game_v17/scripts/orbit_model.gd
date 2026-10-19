extends RefCounted

# 轨道 / 相对运动模型（P1a）
#
# 两套传播器：
#  1) 二体开普勒（Earth / Moon 中心）
#       kepler_propagate(r, v, dt, mu) -> {r, v}
#     由状态矢量求根数 → 解 Kepler 方程 → 回转 ECI；e >= 0.98 时退化为 RK4 数值积分。
#  2) L1 站心局部相对运动（CR3BP 线性化 + 科氏项）
#       local_propagate(r, v, dt) -> {r, v}
#     以 L1 站点为原点的旋转系。线性化方程（单位长度 = 地月距离，单位时间 = 1/n）：
#       x'' = 2n·y' + Ωxx·n²·x
#       y'' = -2n·x' + Ωyy·n²·y
#       z'' = Ωzz·n²·z
#     其中 x = 地月连线（+x 指向月球）、y = 面内横向、z = 轨道法向。
#     潮汐系数由 CR3BP 有效势在 L1 的二阶导给出；n = 地月会合系平均角速度。
#
# 局部板的坐标约定（与 plot.gd 一致）：km / km/s，x 东 / y 北 / z 天顶；
# L1 站心时把 +x 当地月连线（指向月球）即可，方向由 state.gd 的场景数据决定。
#
# 明确忽略：J2、太阳光压、第三体（地月转移段）、相对论（见 docs/02 §10）。
# 300 s 量级的预测里，L1 局部运动的曲率来自潮汐项，量级 mm–m；视觉上是近直线，
# 这是物理结果，不是简化。

# ── 常数（docs/02 §2.1 / §11）──────────────────────────
const MU_EARTH := 398600.4418      # km³/s²
const MU_MOON := 4902.800          # km³/s²
const R_EARTH := 6378.137          # km
const R_MOON := 1737.4             # km
const EARTH_MOON_KM := 384400.0    # km（平均地月距离）
const L1_FROM_MOON_KM := 58400.0   # km（docs/07：环一·斛 的 L1 位置）
const LUNAR_PERIOD_S := 27.321661 * 86400.0
const N_LUNAR := TAU / LUNAR_PERIOD_S   # 2.6617e-6 rad/s

# L1 线性化系数（CR3BP 有效势二阶导，归一化单位）
# Ωxx = 1 + 2(1-μ)/d1³ + 2μ/d2³    （沿地月轴不稳定，鞍点）
# Ωyy = 1 - (1-μ)/d1³ - μ/d2³      （面内横向振荡）
# Ωzz = -(1-μ)/d1³ - μ/d2³         （法向振荡）
const OMEGA_XX := 11.1703
const OMEGA_YY := -4.0850
const OMEGA_ZZ := -5.0849
const KX := N_LUNAR * N_LUNAR * OMEGA_XX   # ≈ 7.9e-11 1/s²
const KY := N_LUNAR * N_LUNAR * OMEGA_YY   # ≈ -2.9e-11
const KZ := N_LUNAR * N_LUNAR * OMEGA_ZZ   # ≈ -3.6e-11

# 局部传播用 2 阶解析解（a 视为常值）：x(t)=x0+v0t+½a t²。
# 误差 ~ |K v| t³/6：t=2000 s 时约 1e-2 km（10 m），对仪表显示足够；
# selftest() 里用 RK4 对照给出实测值。
const TAYLOR_MAX_DT := 4000.0

# ── 二体开普勒传播 ─────────────────────────────────────

static func _solve_kepler(M: float, e: float) -> float:
	var E := M if e < 0.8 else PI
	E = fposmod(M + e * sin(M), TAU) if e < 0.3 else E
	for k in range(60):
		var f := E - e * sin(E) - M
		var fp := 1.0 - e * cos(E)
		var dE := -f / fp
		E += dE
		if absf(dE) < 1.0e-12:
			break
	return E

static func orbital_period(a: float, mu: float) -> float:
	if a <= 0.0:
		return 0.0
	return TAU * sqrt(a * a * a / mu)

# 由 (r, v) 求经典根数。返回 {h, e, a, i, raan, argp, nu, p, n, valid}
static func elements(r: Vector3, v: Vector3, mu: float) -> Dictionary:
	var h := r.cross(v)
	var hlen := h.length()
	var rlen := r.length()
	var v2 := v.dot(v)
	if hlen < 1.0e-9 or rlen < 1.0e-9:
		return {"valid": false}
	var energy := 0.5 * v2 - mu / rlen
	var evec := v.cross(h) / mu - r / rlen
	var e := evec.length()
	var p := hlen * hlen / mu
	var a := -mu / (2.0 * energy)
	var inc := acos(clampf(h.z / hlen, -1.0, 1.0))
	var raan := atan2(h.x, -h.y)
	# 近地点幅角 & 真近点角
	var argp := 0.0
	var nu := 0.0
	if e > 1.0e-8:
		var ehat := evec / e
		var hhat := h / hlen
		var qhat := hhat.cross(ehat)
		var cosnu := clampf((p / rlen - 1.0) / e, -1.0, 1.0)
		var sinnu := r.dot(v) * hlen / (mu * rlen * e)
		nu = atan2(sinnu, cosnu)
		var node := Vector3(cos(raan), sin(raan), 0.0)
		var cosw := clampf(node.dot(ehat), -1.0, 1.0)
		argp = acos(cosw)
		if ehat.z < 0.0:
			argp = TAU - argp
	return {"valid": true, "h": h, "e": e, "a": a, "i": rad_to_deg(inc),
		"raan": rad_to_deg(raan), "argp": rad_to_deg(argp), "nu": rad_to_deg(nu),
		"p": p, "n": sqrt(mu / (a * a * a)) if a > 0.0 else 0.0}

# 二体传播：椭圆轨道用根数解析传播；高偏心/双曲/直线退化时用 RK4。
static func kepler_propagate(r: Vector3, v: Vector3, dt: float, mu: float) -> Dictionary:
	if absf(dt) < 1.0e-9:
		return {"r": r, "v": v}
	var h := r.cross(v)
	var hlen := h.length()
	var rlen := r.length()
	if hlen < 1.0e-9 or rlen < 1.0e-9:
		return {"r": r, "v": v}
	var energy := 0.5 * v.dot(v) - mu / rlen
	var evec := v.cross(h) / mu - r / rlen
	var e := evec.length()
	if energy >= 0.0 or e >= 0.98:
		return _two_body_rk4(r, v, dt, mu)
	var a := -mu / (2.0 * energy)
	var hhat := h / hlen
	if e < 1.0e-5:
		# 近圆轨道：ehat = 当前位置方向（地心距不变），θ = n·t
		var ehat0 := r / rlen
		var qhat0 := hhat.cross(ehat0).normalized()
		var n0 := sqrt(mu / (a * a * a))
		var theta := n0 * dt
		var rnew0 := (cos(theta) * ehat0 + sin(theta) * qhat0) * a
		var vmag := sqrt(mu / a)
		var vnew0 := (-sin(theta) * ehat0 + cos(theta) * qhat0) * vmag
		return {"r": rnew0, "v": vnew0}
	var ehat := evec / e
	var qhat := hhat.cross(ehat)
	var p := hlen * hlen / mu
	var n := sqrt(mu / (a * a * a))
	var cosnu0 := clampf((p / rlen - 1.0) / e, -1.0, 1.0)
	var sinnu0 := r.dot(v) * hlen / (mu * rlen * e)
	var cosE0 := (e + cosnu0) / (1.0 + e * cosnu0)
	var sinE0 := sqrt(maxf(1.0 - e * e, 0.0)) * sinnu0 / (1.0 + e * cosnu0)
	var M0 := atan2(sinE0, cosE0) - e * sin(atan2(sinE0, cosE0))
	var M := M0 + n * dt
	var E := _solve_kepler(M, e)
	var cosnu := (cos(E) - e) / (1.0 - e * cos(E))
	var sinnu := sqrt(maxf(1.0 - e * e, 0.0)) * sin(E) / (1.0 - e * cos(E))
	var nu := atan2(sinnu, cosnu)
	var rr := p / (1.0 + e * cosnu)
	var rnew := (cos(nu) * ehat + sin(nu) * qhat) * rr
	var vnew := (qhat * (e + cosnu) - ehat * sinnu) * sqrt(mu / p)
	return {"r": rnew, "v": vnew}

# 二体 RK4（只用于高偏心/双曲/数值对照）
static func _two_body_accel(r: Vector3, mu: float) -> Vector3:
	var d := r.length()
	if d < 1.0:
		return Vector3.ZERO
	return -r * (mu / (d * d * d))

static func _two_body_rk4(r: Vector3, v: Vector3, dt: float, mu: float) -> Dictionary:
	var n := maxi(1, int(ceil(absf(dt) / 10.0)))
	var h := dt / float(n)
	var rr := r
	var vv := v
	for i in range(n):
		var k1v := _two_body_accel(rr, mu)
		var k1r := vv
		var k2v := _two_body_accel(rr + k1r * (h * 0.5), mu)
		var k2r := vv + k1v * (h * 0.5)
		var k3v := _two_body_accel(rr + k2r * (h * 0.5), mu)
		var k3r := vv + k2v * (h * 0.5)
		var k4v := _two_body_accel(rr + k3r * h, mu)
		var k4r := vv + k3v * h
		rr += (k1r + 2.0 * k2r + 2.0 * k3r + k4r) * (h / 6.0)
		vv += (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * (h / 6.0)
	return {"r": rr, "v": vv}

# ── L1 站心局部相对运动 ────────────────────────────────

static func l1_accel(r: Vector3, v: Vector3) -> Vector3:
	# 潮汐（线性化 CR3BP）+ 科氏项；旋转轴 = 轨道法向 +z
	return Vector3(
		KX * r.x + 2.0 * N_LUNAR * v.y,
		KY * r.y - 2.0 * N_LUNAR * v.x,
		KZ * r.z
	)

# 二阶梯泰勒解析传播：r(t) = r0 + v0 t + ½ a0 t²，v(t) = v0 + a0 t
static func local_propagate(r: Vector3, v: Vector3, dt: float) -> Dictionary:
	if absf(dt) < 1.0e-9:
		return {"r": r, "v": v}
	var adt := clampf(dt, -TAYLOR_MAX_DT, TAYLOR_MAX_DT)
	var a := l1_accel(r, v)
	var r2 := r + v * adt + a * (0.5 * adt * adt)
	var v2 := v + a * adt
	return {"r": r2, "v": v2}

# RK4 版（校验用；步长 ≤ 5 s）
static func local_propagate_rk4(r: Vector3, v: Vector3, dt: float) -> Dictionary:
	if absf(dt) < 1.0e-9:
		return {"r": r, "v": v}
	var n := maxi(1, int(ceil(absf(dt) / 5.0)))
	var h := dt / float(n)
	var rr := r
	var vv := v
	for i in range(n):
		var k1v := l1_accel(rr, vv)
		var k1r := vv
		var k2v := l1_accel(rr + k1r * (h * 0.5), vv + k1v * (h * 0.5))
		var k2r := vv + k1v * (h * 0.5)
		var k3v := l1_accel(rr + k2r * (h * 0.5), vv + k2v * (h * 0.5))
		var k3r := vv + k2v * (h * 0.5)
		var k4v := l1_accel(rr + k3r * h, vv + k3v * h)
		var k4r := vv + k3v * h
		rr += (k1r + 2.0 * k2r + 2.0 * k3r + k4r) * (h / 6.0)
		vv += (k1v + 2.0 * k2v + 2.0 * k3v + k4v) * (h / 6.0)
	return {"r": rr, "v": vv}

# 目标在 tau 时刻、相对本舰的站心局部位置（km）。tau 是相对场景 epoch 的秒数。
static func local_separation(track: Dictionary, own: Dictionary, tau: float) -> Vector3:
	var tr: Vector3 = track["r"]
	var tv: Vector3 = track["v"]
	var orr: Vector3 = own["r"]
	var ov: Vector3 = own["v"]
	var tst := local_propagate(tr, tv, tau)
	var ost := local_propagate(orr, ov, tau)
	var a: Vector3 = tst["r"]
	var b: Vector3 = ost["r"]
	return a - b

# 目标在 tau 时刻相对本舰的站心速度（km/s）
static func local_velocity(track: Dictionary, own: Dictionary, tau: float) -> Vector3:
	var tv: Vector3 = track["v"]
	var ov: Vector3 = own["v"]
	var tst := local_propagate(track["r"], tv, tau)
	var ost := local_propagate(own["r"], ov, tau)
	var a: Vector3 = tst["v"]
	var b: Vector3 = ost["v"]
	return a - b

# 位置不确定度（1σ，km）：等级基线 + 数据陈旧 + 预测时间外推
static func sigma_km(track: Dictionary, dt: float) -> float:
	var base := 2.0
	match int(track.get("level", 1)):
		4:
			base = 1.2
		3:
			base = 3.0
		2:
			base = 9.0
		_:
			base = 18.0
	var age := float(track.get("age", 0.0))
	var growth := 0.12      # km/s：越往后预测越糙
	var age_rate := 0.20    # km/s：陈旧数据也在漂
	return sqrt(base * base + pow(growth * absf(dt), 2.0) + pow(age_rate * age, 2.0))

# 预测折线：tau0..tau1（相对 epoch 的绝对值），返回
#   {"pts": Array[Vector3] 站心局部 km, "tau": Array[float], "rel": Array[float] 相对当前秒,
#    "sigma": Array[float] km}
static func predict_polyline(track: Dictionary, own: Dictionary, tau0: float, tau1: float, steps: int) -> Dictionary:
	var n := maxi(1, steps)
	var tau_now := 0.0
	# 用传入区间起点当"当前"由调用方保证；这里只做标记（rel = tau - tau0 的语义由 plot 决定）
	var pts: Array[Vector3] = []
	var taus: Array[float] = []
	var rels: Array[float] = []
	var sigmas: Array[float] = []
	for i in range(n + 1):
		var tau := tau0 + (tau1 - tau0) * float(i) / float(n)
		pts.append(local_separation(track, own, tau))
		taus.append(tau)
		rels.append(tau - tau_now)
		sigmas.append(sigma_km(track, tau - tau0))
	return {"pts": pts, "tau": taus, "rel": rels, "sigma": sigmas}

# 本舰点火计划折线：先在 now_tau 滑行到 burn_t 秒，施加 burn_dv，再滑到 horizon。
# 返回 {pts, rel, burn_index}；位置相对"当前本舰位置"（即局部板原点）。
static func own_plan(own: Dictionary, now_tau: float, burn_t: float, burn_dv: Vector3, horizon: float, steps: int) -> Dictionary:
	var orr: Vector3 = own["r"]
	var ov: Vector3 = own["v"]
	var cur := local_propagate(orr, ov, now_tau)
	var cur_r: Vector3 = cur["r"]
	var burn_abs := now_tau + burn_t
	var pre := local_propagate(orr, ov, burn_abs)
	var pre_r: Vector3 = pre["r"]
	var pre_v: Vector3 = pre["v"]
	var v2 := pre_v + burn_dv
	var n := maxi(2, steps)
	var pts: Array[Vector3] = []
	var rels: Array[float] = []
	var burn_index := 0
	for i in range(n + 1):
		var t := burn_t + (horizon - burn_t) * float(i) / float(n)
		var abs_t := now_tau + t
		var r: Vector3
		if abs_t <= burn_abs:
			var st := local_propagate(orr, ov, abs_t)
			r = st["r"]
			burn_index = i
		else:
			var st2 := local_propagate(pre_r, v2, abs_t - burn_abs)
			r = st2["r"]
		pts.append(r - cur_r)
		rels.append(t)
	return {"pts": pts, "rel": rels, "burn_index": burn_index}

# 本舰历史折线（相对当前位置）
static func own_history(own: Dictionary, now_tau: float, from_s: float, steps: int) -> Dictionary:
	var orr: Vector3 = own["r"]
	var ov: Vector3 = own["v"]
	var cur := local_propagate(orr, ov, now_tau)
	var cur_r: Vector3 = cur["r"]
	var n := maxi(1, steps)
	var pts: Array[Vector3] = []
	var rels: Array[float] = []
	for i in range(n + 1):
		var t := from_s * (1.0 - float(i) / float(n))
		var st := local_propagate(orr, ov, now_tau + t)
		pts.append(st["r"] - cur_r)
		rels.append(t)
	return {"pts": pts, "rel": rels}

# ── 自检（headless 启动时打印）─────────────────────────
# 1) 400 km 圆轨道传播一个周期，检查回到起点误差
# 2) L1 局部解析传播 vs RK4，300 s / 2000 s 的最大误差
static func selftest() -> Dictionary:
	var r0 := Vector3(R_EARTH + 400.0, 0.0, 0.0)
	var vc := sqrt(MU_EARTH / (R_EARTH + 400.0))
	var v0 := Vector3(0.0, vc, 0.0)
	var period := orbital_period(R_EARTH + 400.0, MU_EARTH)
	var st := kepler_propagate(r0, v0, period, MU_EARTH)
	var dr: Vector3 = st["r"]
	var dv: Vector3 = st["v"]
	var pos_err_m := (dr - r0).length() * 1000.0
	var vel_err_mps := (dv - v0).length() * 1000.0

	# L1 局部：解析 2 阶 vs RK4
	var r1 := Vector3(120.0, -40.0, 12.0)
	var v1 := Vector3(0.6, 0.9, -0.05)
	var e300 := 0.0
	var e2000 := 0.0
	for dt in [60.0, 120.0, 300.0]:
		var a := local_propagate(r1, v1, dt)
		var b := local_propagate_rk4(r1, v1, dt)
		var ar: Vector3 = a["r"]
		var br: Vector3 = b["r"]
		e300 = maxf(e300, (ar - br).length() * 1000.0)
	for dt2 in [600.0, 1200.0, 2000.0]:
		var a2 := local_propagate(r1, v1, dt2)
		var b2 := local_propagate_rk4(r1, v1, dt2)
		var ar2: Vector3 = a2["r"]
		var br2: Vector3 = b2["r"]
		e2000 = maxf(e2000, (ar2 - br2).length() * 1000.0)
	return {
		"period_s": period,
		"two_body_pos_err_m": pos_err_m,
		"two_body_vel_err_mps": vel_err_mps,
		"local_err_300s_m": e300,
		"local_err_2000s_m": e2000,
		"kx": KX,
		"ky": KY,
		"kz": KZ,
		"n_lunar": N_LUNAR
	}
