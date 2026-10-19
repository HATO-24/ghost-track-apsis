extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# CISLUNAR-MODEL-1 headless probe（地月圆轨道 / L1–L5 / 站点 / 环 / JSON）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\cislunar_explorer" --script res://tests/cislunar_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const Model := preload("res://sim/cislunar_model.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("CISLUNAR MODEL PROBE · 地月圆轨道 / L1–L5 / 站点 / 环")
	print("════════════════════════════════════════════════════════════")
	_test_constants_and_moon()
	_test_earth_and_time()
	_test_lagrange()
	_test_geo()
	_test_lunar_sync()
	_test_orbits_and_ports()
	_test_stations()
	_test_sample_and_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("CISLUNAR PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("CISLUNAR PROBE FAILED")
		quit(1)
	else:
		print("CISLUNAR PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

## 绝对容差
func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%.9f expected=%.9f diff=%.3f tol=%.3f" % [actual, expected, diff, tol])

## 相对容差（expected 不能为 0）
func _near_rel(actual: float, expected: float, rtol: float, label: String) -> void:
	var denom := maxf(absf(expected), 1.0e-12)
	var rel := absf(actual - expected) / denom
	_ok(rel <= rtol, label, "actual=%.9f expected=%.9f rel=%.3f rtol=%.3f" % [actual, expected, rel, rtol])

func _num(d: Dictionary, key: String, def := 0.0) -> float:
	return float(d.get(key, def))

func _vec(d: Dictionary, key: String) -> Array:
	return (d.get(key, []) as Array)

func _vec_len(arr: Array) -> float:
	if arr.size() < 3:
		return -1.0
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2])).length()

func _vec_dist(a: Array, b: Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return -1.0
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(
		Vector3(float(b[0]), float(b[1]), float(b[2])))

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

# ═══════════════════════════════════════════════════════════════════
# 1. 常数 / 月球圆轨道
# ═══════════════════════════════════════════════════════════════════

func _test_constants_and_moon() -> void:
	_section_begin("1 月球圆轨道")
	_near(Model.EARTH_MOON_DIST_KM, 384400.0, 1.0e-9, "地月距离 = 384,400 km")
	_near(Model.MOON_PERIOD_S, 27.321661 * 86400.0, 1.0e-6, "月球恒星周期 = 27.321661 d")
	_near(Model.MU, 0.012150585, 1.0e-12, "μ = 0.012150585")
	_ok(Model.mu_derived() > 0.0121 and Model.mu_derived() < 0.0122, "μ 由 μ_M/(μ_E+μ_M) 可验证",
		"derived=%.9f" % Model.mu_derived())
	_near(Model.mu_derived(), Model.MU, 1.0e-6, "μ 常数与推导值一致（相对 1e-6）")
	# t=0 月球在 +X
	var m0: Dictionary = Model.moon_state(0.0)
	var p0: Array = _vec(m0, "position")
	_near(_vec_len(p0), Model.EARTH_MOON_DIST_KM, 1.0e-6, "t=0 月球半径 384,400 km")
	_near(float(p0[0]), Model.EARTH_MOON_DIST_KM, 1.0e-6, "t=0 月球 x=+R")
	_near(float(p1_y(p0)), 0.0, 1.0e-6, "t=0 月球 y=0")
	# 速度 = 2πR/T（圆轨道）
	var speed := _num(m0, "speed_kmps")
	var expected_speed := TAU * Model.EARTH_MOON_DIST_KM / Model.MOON_PERIOD_S
	_near_rel(speed, expected_speed, 1.0e-6, "月球速度 = 2πR/T")
	# t=T/4：在 +Y
	var mq: Dictionary = Model.moon_state(Model.MOON_PERIOD_S / 4.0)
	var pq: Array = _vec(mq, "position")
	_near(float(pq[0]), 0.0, 1.0, "T/4 月球 x≈0")
	_near(float(pq[1]), Model.EARTH_MOON_DIST_KM, 1.0, "T/4 月球 y≈+R")
	# 周期/速度一致性：n²R³ = μ_total
	var nn := Model.moon_mean_motion()
	var implied := Model.implied_mu_km3_s2()
	_near_rel(implied, nn * nn * pow(Model.EARTH_MOON_DIST_KM, 3.0), 1.0e-12,
		"implied μ = n²R³（由 R/T 推）")
	var rel_err := Model.mu_consistency_rel_err()
	_ok(rel_err < 5.0e-3, "给定 R/T 与 μ_total 自洽误差 <0.5%（模型边界，见 docs）",
		"μ_implied=%.3f rel_err=%.4f%%" % [implied, rel_err * 100.0])
	_near(_num(m0, "period_s"), Model.MOON_PERIOD_S, 1.0e-6, "月球状态含 period_s")
	_data_line("moon", "R=384400 km  T=%.3f s  v=%.6f km/s" % [Model.MOON_PERIOD_S, speed])

func p1_y(a: Array) -> float:
	return float(a[1]) if a.size() > 1 else 0.0

func _test_earth_and_time() -> void:
	_section_begin("2 地球状态 / 时间可设")
	var e: Dictionary = Model.earth_state(0.0)
	_near(_vec_len(_vec(e, "position")), 0.0, 1.0e-9, "地球固定在惯性原点")
	_near(_num(e, "angular_velocity_rad_s"), TAU / Model.EARTH_SIDEREAL_DAY_S, 1.0e-15,
		"地球自转角速度 = 2π/恒星日")
	var e2: Dictionary = Model.earth_state(Model.EARTH_SIDEREAL_DAY_S / 4.0)
	_near_rel(_num(e2, "rotation_angle_rad"), PI / 2.0, 1.0e-6, "地球自转 1/4 恒星日 = 90°")
	# 时间可设：set_time 生效；sample() 不带参数时用 model.t
	var m = Model.new()
	m.set_time(Model.MOON_PERIOD_S / 2.0)
	_near(m.get_time(), Model.MOON_PERIOD_S / 2.0, 1.0e-9, "set_time/get_time")
	var sm: Dictionary = m.sample()
	var moon_pos: Array = ((sm.get("moon", {}) as Dictionary).get("position", []) as Array)
	_near(float(moon_pos[0]), -Model.EARTH_MOON_DIST_KM, 1.0e-3, "sample() 使用 model.t（T/2 → x=-R）")
	var sm0: Dictionary = m.sample(0.0)
	var moon0: Array = ((sm0.get("moon", {}) as Dictionary).get("position", []) as Array)
	_near(float(moon0[0]), Model.EARTH_MOON_DIST_KM, 1.0e-3, "sample(t) 显式时间优先")
	_near(m.get_time(), Model.MOON_PERIOD_S / 2.0, 1.0e-9, "sample() 不修改 model.t")
	var s1: Dictionary = m.sample(10.0)
	var s2: Dictionary = m.sample(20.0)
	_ok(str(s1.get("moon")) != str(s2.get("moon")), "不同时刻月球状态不同")
	_data_line("time", "set_time/sample(t) 语义、Earth 自转 2π/86164.0905")

# ═══════════════════════════════════════════════════════════════════
# 3. L1–L5（CR3BP 驻点 + 旋转/惯性系）
# ═══════════════════════════════════════════════════════════════════

func _test_lagrange() -> void:
	_section_begin("3 L1–L5")
	var lag: Dictionary = Model.lagrange_state(0.0)
	for pid in ["L1", "L2", "L3", "L4", "L5"]:
		_ok(lag.has(pid), "存在 " + pid)
	var l1: Dictionary = lag.get("L1", {})
	var l2: Dictionary = lag.get("L2", {})
	var l3: Dictionary = lag.get("L3", {})
	var l4: Dictionary = lag.get("L4", {})
	var l5: Dictionary = lag.get("L5", {})
	var r := Model.EARTH_MOON_DIST_KM
	# L1：地月之间
	var d1e := _num(l1, "distance_earth_km")
	var d1m := _num(l1, "distance_moon_km")
	_ok(d1e > 0.8 * r and d1e < 0.9 * r, "L1 在地月之间（0.8R~0.9R）", "d_earth=%.0f" % d1e)
	_ok(d1m > 0.1 * r and d1m < 0.2 * r, "L1 离月球 0.1R~0.2R", "d_moon=%.0f" % d1m)
	_near_rel(d1e + d1m, r, 1.0e-6, "L1 共线：d_E+d_M=R")
	# L2：月球外侧
	var d2e := _num(l2, "distance_earth_km")
	var d2m := _num(l2, "distance_moon_km")
	_ok(d2e > r, "L2 在月球外侧（d_earth > R）", "d_earth=%.0f" % d2e)
	_ok(d2m < 0.2 * r, "L2 离月球 <0.2R", "d_moon=%.0f" % d2m)
	_near_rel(d2e - d2m, r, 1.0e-6, "L2 共线：d_E-d_M=R")
	# L3：地球外侧反月点
	var l3pos: Array = _vec(l3, "position")
	var l3moon: Array = _vec(Model.moon_state(0.0), "position")
	_ok(float(l3pos[0]) < 0.0, "L3 在反月侧（x<0）")
	_ok(float(l3pos[0]) * float(l3moon[0]) < 0.0, "L3 与月球分居地球两侧")
	_ok(_num(l3, "distance_moon_km") > r, "L3 离月球 > R", "d_moon=%.0f" % _num(l3, "distance_moon_km"))
	# L4/L5：等边三角形
	_near_rel(_num(l4, "distance_earth_km"), r, 1.0e-6, "L4 到地球 = R")
	_near_rel(_num(l4, "distance_moon_km"), r, 1.0e-6, "L4 到月球 = R")
	_near_rel(_num(l5, "distance_earth_km"), r, 1.0e-6, "L5 到地球 = R")
	_near_rel(_num(l5, "distance_moon_km"), r, 1.0e-6, "L5 到月球 = R")
	_near(_num(l4, "rot_angle_deg"), 60.0, 1.0e-4, "L4 旋转系角 = +60°")
	_near(_num(l5, "rot_angle_deg"), -60.0, 1.0e-4, "L5 旋转系角 = -60°")
	_near(_num(l4, "angle_from_moon_deg"), 60.0, 1.0e-3, "L4 与月球惯性夹角 60°")
	_near(_num(l5, "angle_from_moon_deg"), 60.0, 1.0e-3, "L5 与月球惯性夹角 60°（另一侧）")
	# 共线点验证：归一化方程 f(x)≈0（不是写死数值）
	var norm: Dictionary = Model.collinear_points_normalized()
	for pid in ["L1", "L2", "L3"]:
		var x := float(norm[pid])
		var f := Model.collinear_equation(x)
		_ok(absf(f) < 1.0e-9, "%s 满足 CR3BP 共线平衡方程" % pid,
			"x=%.12f f=%.3f" % [x, f])
	# 旋转/惯性：惯性位置 = Rz(phase)·旋转位置；T/4 时 L4 相位 +90°
	var quarter := Model.MOON_PERIOD_S / 4.0
	var lagq: Dictionary = Model.lagrange_state(quarter)
	var l4q: Dictionary = lagq.get("L4", {})
	var l4r: Dictionary = Model.lagrange_rotating_km()
	var expect_q := Model.rot_to_inertial(l4r["L4"], Model.moon_phase(quarter))
	_near(_vec_dist(_vec(l4q, "position"), Model.arr(expect_q)), 0.0, 1.0,
		"L4 惯性位置 = Rz(phase)·旋转位置（float32 容差 1 km）")
	var l4_phase := atan2(float(_vec(l4q, "position")[1]), float(_vec(l4q, "position")[0]))
	var expect_angle := Model.moon_phase(quarter) + deg_to_rad(60.0)
	var dphi := fposmod(l4_phase - expect_angle + PI, TAU) - PI
	_near(absf(dphi), 0.0, 1.0e-4, "T/4 时 L4 惯性角 = phase+60°")
	# 共转速度
	var l4v: Array = _vec(l4q, "velocity")
	var expect_v := Model.corotation_velocity(expect_q, Model.moon_mean_motion())
	_near(_vec_dist(l4v, Model.arr(expect_v)), 0.0, 0.01, "L 点速度为共转速度 ω×r（float32 容差）")
	_data_line("lagrange", "L1 d_E=%.0f d_M=%.0f | L2 d_E=%.0f | L3 x=%.0f | L4/L5 angle=±60°" % [
		d1e, d1m, d2e, float(l3pos[0])])

# ═══════════════════════════════════════════════════════════════════
# 4. GEO 环
# ═══════════════════════════════════════════════════════════════════

func _test_geo() -> void:
	_section_begin("4 GEO 环")
	_near(Model.GEO_RADIUS_KM, 42164.0, 1.0e-9, "GEO 半径 = 42,164 km")
	var tp := Model.geo_period_s()
	_near_rel(tp, Model.EARTH_SIDEREAL_DAY_S, 5.0e-3, "GEO 周期 ≈ 地球恒星日（Kepler）")
	# 独立 Kepler 公式复算
	var tp2 := TAU * sqrt(pow(Model.GEO_RADIUS_KM, 3.0) / Model.MU_EARTH)
	_near_rel(tp, tp2, 1.0e-12, "GEO 周期与 Kepler 公式一致")
	var ring: Dictionary = Model.geo_ring(0.0, 24)
	_eq(int(ring.get("count", 0)), 24, "GEO 环采样 24 点")
	var points: Array = ring.get("points", [])
	_eq(points.size(), 24, "points 24")
	var max_err := 0.0
	var v_exp := Model.circular_speed_kmps(Model.GEO_RADIUS_KM, Model.MU_EARTH)
	var max_v_err := 0.0
	for raw in points:
		var p: Array = raw
		var r_pt := sqrt(float(p[0]) * float(p[0]) + float(p[1]) * float(p[1]))
		max_err = maxf(max_err, absf(r_pt - Model.GEO_RADIUS_KM))
	for raw in (ring.get("velocities", []) as Array):
		var v: Array = raw
		max_v_err = maxf(max_v_err, absf(_vec_len(v) - v_exp))
	_ok(max_err < 0.1, "GEO 采样点半径误差 <0.1 km（Vector3 float32）", "max_err=%.3f" % max_err)
	_ok(max_v_err < 1.0e-3, "GEO 采样点速度 ≈ Kepler 圆速度（42,164 取整误差 <0.001 km/s）", "max_v_err=%.7f" % max_v_err)
	# 环随时间旋转
	var ring2: Dictionary = Model.geo_ring(Model.EARTH_SIDEREAL_DAY_S / 4.0, 24)
	var p1: Array = (points[0] as Array)
	var p2: Array = ((ring2.get("points", []) as Array)[0] as Array)
	var ang1 := atan2(float(p1[1]), float(p1[0]))
	var ang2 := atan2(float(p2[1]), float(p2[0]))
	var dgeo := fposmod(ang2 - ang1 - PI / 2.0 + PI, TAU) - PI
	_near(absf(dgeo), 0.0, 1.0e-5, "GEO 环 1/4 恒星日转 90°")
	_data_line("geo", "R=42164 km  T=%.1f s  v=%.4f km/s" % [tp, v_exp])

# ═══════════════════════════════════════════════════════════════════
# 5. 月球同步环
# ═══════════════════════════════════════════════════════════════════

func _test_lunar_sync() -> void:
	_section_begin("5 月球同步环")
	var radius := Model.lunar_sync_radius_km()
	var expected := pow(Model.MOON_MU() * Model.MOON_PERIOD_S * Model.MOON_PERIOD_S
		/ (4.0 * PI * PI), 1.0 / 3.0)
	_near_rel(radius, expected, 1.0e-12, "同步环半径 = (G·M_moon·T²/4π²)^(1/3)")
	_near(Model.lunar_sync_period_s(), Model.MOON_PERIOD_S, 1.0e-9, "同步环周期 = 月球恒星日")
	var hill := Model.hill_radius_km()
	_ok(radius > hill, "同步环半径在月球 Hill 球外（演示数据，文档标注）",
		"r=%.0f km > Hill=%.0f km" % [radius, hill])
	var ring: Dictionary = Model.lunar_sync_ring(0.0, 24)
	_eq(bool(ring.get("outside_hill_sphere", false)), true, "ring.outside_hill_sphere=true")
	var moon0: Dictionary = Model.moon_state(0.0)
	var moon_pos: Array = _vec(moon0, "position")
	var max_err := 0.0
	for raw in (ring.get("points", []) as Array):
		max_err = maxf(max_err, absf(_vec_dist(raw, moon_pos) - radius))
	_ok(max_err < 0.1, "同步环采样点到月球距离 = 半径（float32 容差）", "max_err=%.3f" % max_err)
	# 随月球共转（相对月球相位固定）
	var ring_q: Dictionary = Model.lunar_sync_ring(Model.MOON_PERIOD_S / 4.0, 24)
	var moon_q: Array = _vec(Model.moon_state(Model.MOON_PERIOD_S / 4.0), "position")
	var rel0a: Array = [float((ring.get("points", []) as Array)[0][0]) - float(moon_pos[0]),
		float((ring.get("points", []) as Array)[0][1]) - float(moon_pos[1]), 0.0]
	var rel0b: Array = [float((ring_q.get("points", []) as Array)[0][0]) - float(moon_q[0]),
		float((ring_q.get("points", []) as Array)[0][1]) - float(moon_q[1]), 0.0]
	# 共转：相对月球的惯性方向旋转 90°
	var a1 := atan2(float(rel0a[1]), float(rel0a[0]))
	var a2 := atan2(float(rel0b[1]), float(rel0b[0]))
	var dls := fposmod(a2 - a1 - PI / 2.0 + PI, TAU) - PI
	_near(absf(dls), 0.0, 1.0e-5, "同步环随月球共转（1/4 周期 90°）")
	_data_line("lunar_sync", "r=%.3f km  T=%.3f s  Hill=%.1f km（环在 Hill 外）" % [
		radius, Model.MOON_PERIOD_S, hill])

# ═══════════════════════════════════════════════════════════════════
# 6. 月球低轨/极轨 + 港口 + orbits()
# ═══════════════════════════════════════════════════════════════════

func _test_orbits_and_ports() -> void:
	_section_begin("6 低轨/极轨/港口/orbits")
	var leo_radius := Model.MOON_RADIUS_KM + Model.LUNAR_LEO_ALTITUDE_KM
	var leo_period := Model.period_s(leo_radius, Model.MOON_MU())
	_near(leo_radius, 1837.4, 1.0e-9, "月球低轨半径 = R_moon+100 km")
	var leo_period_check := TAU * sqrt(pow(leo_radius, 3.0) / Model.MOON_MU())
	_near_rel(leo_period, leo_period_check, 1.0e-12, "低轨周期 = 2π√(r³/μ_moon)")
	_ok(leo_period > 6000.0 and leo_period < 8000.0, "低轨周期量级正确（~118 min）",
		"T=%.1f s" % leo_period)
	# 站点数据：低轨/极轨
	var stations: Array = Model.stations_state(0.0)
	var st_leo: Dictionary = {}
	var st_pol: Dictionary = {}
	var st_ep: Dictionary = {}
	var st_mp: Dictionary = {}
	for raw in stations:
		var st: Dictionary = raw
		match String(st.get("id", "")):
			"lunar_leo":
				st_leo = st
			"lunar_polar":
				st_pol = st
			"earth_port":
				st_ep = st
			"lunar_port":
				st_mp = st
	_ok(not st_leo.is_empty(), "存在 lunar_leo")
	_ok(not st_pol.is_empty(), "存在 lunar_polar")
	_ok(not st_ep.is_empty(), "存在 earth_port")
	_ok(not st_mp.is_empty(), "存在 lunar_port")
	_near_rel(_num(st_leo, "distance_moon_km"), leo_radius, 1.0e-6, "低轨站到月球 = 低轨半径")
	_near(_num((st_leo.get("orbit", {}) as Dictionary), "period_s"), leo_period, 1.0e-6,
		"低轨站 orbit.period_s")
	_eq(_num((st_pol.get("orbit", {}) as Dictionary), "inclination_deg"), 90.0, "极轨倾角 90°")
	_near_rel(_num(st_ep, "distance_earth_km"), Model.EARTH_RADIUS_KM, 1.0e-6,
		"地球港在地球表面（6378.137 km）")
	_near_rel(_num(st_mp, "distance_moon_km"), Model.MOON_RADIUS_KM, 1.0e-6,
		"月球港在月球表面（1737.4 km）")
	# 月球港在近地面（朝向地球）
	var moon0: Array = _vec(Model.moon_state(0.0), "position")
	var mp_pos: Array = _vec(st_mp, "position")
	var dot := float(moon0[0]) * (float(mp_pos[0]) - float(moon0[0])) \
		+ float(moon0[1]) * (float(mp_pos[1]) - float(moon0[1]))
	_ok(dot < 0.0, "月球港位于近地面（朝向地球）", "dot=%.1f" % dot)
	# 极轨站确实出平面：多个时刻 z 振幅
	var max_z := 0.0
	for k in range(12):
		var tk := Model.MOON_PERIOD_S * float(k) / 12.0
		for raw in Model.stations_state(tk):
			var st: Dictionary = raw
			if String(st.get("id", "")) == "lunar_polar":
				var pz: Array = _vec(st, "position")
				var moon_z: Array = _vec(Model.moon_state(tk), "position")
				max_z = maxf(max_z, absf(float(pz[2]) - float(moon_z[2])))
	_ok(max_z > 0.8 * leo_radius, "极轨站有显著出平面 z 分量", "max_z=%.0f km" % max_z)
	# orbits()
	var model_inst = Model.new()
	var ob: Dictionary = model_inst.orbits(64)
	_eq(int(ob.get("samples", 0)), 64, "orbits.samples=64")
	var moon_pts: Array = ((ob.get("moon", {}) as Dictionary).get("points", []) as Array)
	var geo_pts: Array = ((ob.get("geo", {}) as Dictionary).get("points", []) as Array)
	var ls_pts: Array = ((ob.get("lunar_sync", {}) as Dictionary).get("points", []) as Array)
	_eq(moon_pts.size(), 64, "月球轨道采样 64 点")
	_eq(geo_pts.size(), 64, "GEO 轨道采样 64 点")
	_eq(ls_pts.size(), 64, "同步环采样 64 点")
	var moon_r_err := 0.0
	for p in moon_pts:
		moon_r_err = maxf(moon_r_err, absf(_vec_len(p) - Model.EARTH_MOON_DIST_KM))
	_ok(moon_r_err < 0.1, "月球轨道点半径全部 = R（float32 容差）", "max_err=%.3f" % moon_r_err)
	var geo_r_err := 0.0
	for p in geo_pts:
		var arrp: Array = p
		geo_r_err = maxf(geo_r_err, absf(sqrt(float(arrp[0]) * float(arrp[0])
			+ float(arrp[1]) * float(arrp[1])) - Model.GEO_RADIUS_KM))
	_ok(geo_r_err < 0.1, "GEO 轨道点半径全部 = 42,164 km（float32 容差）", "max_err=%.3f" % geo_r_err)
	_ok(ob.has("periods") and (ob.get("periods", {}) as Dictionary).size() >= 4, "orbits.periods")
	_data_line("leo/ports", "低轨 r=%.1f km T=%.1f s；极轨 max_z=%.0f km；月球港 dot=%.0f" % [
		leo_radius, leo_period, max_z, dot])

# ═══════════════════════════════════════════════════════════════════
# 7. 站点全集 / 相对距离
# ═══════════════════════════════════════════════════════════════════

func _test_stations() -> void:
	_section_begin("7 站点全集 / 相对距离")
	var stations: Array = Model.stations_state(1234.5)
	_eq(stations.size(), 10, "站点数 10")
	var ids: Array = []
	var kinds: Dictionary = {}
	for raw in stations:
		var st: Dictionary = raw
		ids.append(String(st.get("id", "")))
		kinds[String(st.get("kind", ""))] = int(kinds.get(String(st.get("kind", "")), 0)) + 1
		for key in ["id", "name", "kind", "parent", "position", "velocity", "orbit", "distances"]:
			_ok(st.has(key), "%s 有字段 %s" % [String(st.get("id", "")), key])
		var orbit: Dictionary = st.get("orbit", {})
		_ok(orbit.has("radius_km") and orbit.has("period_s") and orbit.has("inclination_deg"),
			"%s orbit 字段完整" % String(st.get("id", "")))
		var pos: Array = _vec(st, "position")
		var vel: Array = _vec(st, "velocity")
		_ok(pos.size() == 3 and vel.size() == 3, "%s 状态向量 [3]" % String(st.get("id", "")))
		var spd := _vec_len(vel)
		_ok(spd > 0.0 and spd < 20.0, "%s 速度量级合理" % String(st.get("id", "")),
			"speed=%.4f km/s" % spd)
	for need in Model.STATION_IDS:
		_ok(need in ids, "站点存在: " + String(need))
	_eq(int(kinds.get("lagrange_station", 0)), 4, "L 点站 4 个")
	_eq(int(kinds.get("ring_station", 0)), 2, "环站 2 个（GEO/月同步）")
	_eq(int(kinds.get("lunar_orbit_station", 0)), 2, "月球轨道站 2 个")
	_eq(int(kinds.get("port", 0)), 2, "港口 2 个")
	# 相对距离：站内 distances 与 sample.distances 一致
	var s: Dictionary = Model.new().sample(1234.5)
	var distances: Dictionary = s.get("distances", {})
	_ok(distances.has("earth|moon"), "distances 含 earth|moon")
	_near(float(distances.get("earth|moon", 0.0)), Model.EARTH_MOON_DIST_KM, 1.0e-6,
		"distances[earth|moon] = R")
	_ok(distances.has("l1_station|l4_station"), "distances 含站点两两距离")
	var st_map: Dictionary = {}
	for raw in stations:
		var st: Dictionary = raw
		st_map[String(st.get("id", ""))] = st
	var d_pair := float(distances.get("l1_station|l4_station", -1.0))
	var manual := _vec_dist(_vec(st_map["l1_station"], "position"), _vec(st_map["l4_station"], "position"))
	_near_rel(d_pair, manual, 1.0e-6, "站点两两距离与位置一致")
	for raw in stations:
		var st: Dictionary = raw
		var dd: Dictionary = st.get("distances", {})
		_near_rel(float(dd.get("earth_center_km", -1.0)), _num(st, "distance_earth_km"), 1.0e-9,
			"%s distances.earth_center 一致" % String(st.get("id", "")))
	# distance() 辅助支持多种输入
	_near(Model.distance([0.0, 0.0, 0.0], [Model.EARTH_MOON_DIST_KM, 0.0, 0.0]),
		Model.EARTH_MOON_DIST_KM, 1.0e-6, "distance([..],[..]) = R")
	_near(Model.distance(st_map["earth_port"], st_map["lunar_port"]),
		_vec_dist(_vec(st_map["earth_port"], "position"), _vec(st_map["lunar_port"], "position")),
		1.0e-6, "distance(Dictionary) 与位置一致")
	_near(Model.distance(Vector3.ZERO, Vector3(0.0, 0.0, 100.0)), 100.0, 1.0e-9,
		"distance(Vector3,Vector3)")
	_data_line("stations", "10 站（L×4/环×2/月球轨道×2/港×2），samples@t=1234.5")

# ═══════════════════════════════════════════════════════════════════
# 8. sample / JSON / epoch
# ═══════════════════════════════════════════════════════════════════

func _test_sample_and_json() -> void:
	_section_begin("8 sample / JSON")
	var m = Model.new()
	var s: Dictionary = m.sample(1234.5)
	for key in ["model", "units", "epoch", "constants", "earth", "moon", "lagrange",
			"stations", "rings", "distances", "mu", "mu_derived"]:
		_ok(s.has(key), "sample 含字段: " + key)
	_eq((s.get("units", {}) as Dictionary).get("distance", ""), "km", "单位 distance=km")
	_eq((s.get("units", {}) as Dictionary).get("velocity", ""), "km_per_s", "单位 velocity=km/s")
	var epoch: Dictionary = s.get("epoch", {})
	_near(_num(epoch, "t_s"), 1234.5, 1.0e-9, "epoch.t_s")
	_near_rel(_num(epoch, "t_days"), 1234.5 / 86400.0, 1.0e-12, "epoch.t_days")
	_ok(String(epoch.get("t0_iso", "")) != "", "epoch.t0_iso")
	var rings: Dictionary = s.get("rings", {})
	_ok(rings.has("geo") and rings.has("lunar_sync"), "rings 含 geo/lunar_sync")
	_eq(((rings.get("geo", {}) as Dictionary).get("points", []) as Array).size(), 24,
		"rings.geo 24 点")
	_eq(((rings.get("lunar_sync", {}) as Dictionary).get("points", []) as Array).size(), 24,
		"rings.lunar_sync 24 点")
	# JSON 可序列化 + 回读
	var js := JSON.stringify(s)
	_ok(js.length() > 1000, "JSON.stringify(sample) 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "JSON.parse_string 回读为 Dictionary")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.has("moon") and pd.has("lagrange") and pd.has("stations") and pd.has("rings"),
			"回读含 moon/lagrange/stations/rings")
		_eq(((pd.get("stations", []) as Array)).size(), 10, "回读 stations 10")
		_eq((((pd.get("lagrange", {}) as Dictionary).get("L1", {}) as Dictionary)
			.get("position", []) as Array).size(), 3, "回读 L1.position [3]")
		var pdm: Dictionary = pd.get("moon", {})
		_ok(pdm.has("position") and pdm.has("velocity"), "回读 moon position/velocity")
		var pdr: Dictionary = pd.get("rings", {})
		_eq(((pdr.get("geo", {}) as Dictionary).get("points", []) as Array).size(), 24,
			"回读 rings.geo 24 点")
		_near(float((pd.get("distances", {}) as Dictionary).get("earth|moon", 0.0)),
			Model.EARTH_MOON_DIST_KM, 1.0e-6, "回读 distances earth|moon")
	_data_line("json", "sample(1234.5) JSON 可序列化/回读；stations=10, rings=24+24")
