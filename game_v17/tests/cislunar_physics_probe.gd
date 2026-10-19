extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R6-PHYS-1 headless probe：地月物理核心（CR3BP / RK4 / 相对运动 / 对接）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/cislunar_physics_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
#
# 覆盖：常数/归一化、参考系转换、L1–L5、Jacobi/能量/NaN、RK4 传播与轨道闭合、
#       月球/GEO/LLO/转移轨道、相对运动/LVLH/CW、接近走廊、对接几何、实体采样、JSON、确定性。
# ═══════════════════════════════════════════════════════════════════

const P := preload("res://framework/sim/cislunar_physics.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R6-PHYS-1 PROBE · 地月物理核心（CR3BP / RK4 / 相对运动 / 对接）")
	print("════════════════════════════════════════════════════════════")
	_test_constants()
	_test_frames()
	_test_equilibria()
	_test_cr3bp()
	_test_two_body()
	_test_moon_geo_llo()
	_test_relative_cw()
	_test_corridor_docking()
	_test_instance_entities()
	_test_nan_json()
	_test_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("PHYSICS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("PHYSICS PROBE FAILED")
		quit(1)
	else:
		print("PHYSICS PROBE OK")
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


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	# Godot Vector3 为 float32：大数值位置的自然精度约 1e-7 相对量级；加数值地板
	var tol_eff := maxf(tol, absf(expected) * 2.0e-7 + 1.0e-7)
	_ok(diff <= tol_eff, label, "actual=%s expected=%s diff=%s tol_eff=%s" % [
		str(actual), str(expected), str(diff), str(tol_eff)])


func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	if txt.length() <= 2:
		return false
	var back = JSON.parse_string(txt)
	return back is Dictionary or back is Array


func _state(r: Vector3, v: Vector3) -> Dictionary:
	return {"r": r, "v": v}


func _as_state(res: Dictionary) -> Dictionary:
	return P.as_state(res.get("state", {}))


func _rel_dist(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b)


# ═══════════════════════════════════════════════════════════════════
# 1. 常数 / 归一化
# ═══════════════════════════════════════════════════════════════════

func _test_constants() -> void:
	_section_begin("1 常数 / 归一化")
	_near(P.MU_EARTH_KM3_S2, 398600.4418, 1.0e-6, "μ_earth=398600.4418")
	_near(P.MU_MOON_KM3_S2, 4902.800118, 1.0e-6, "μ_moon=4902.800118")
	_near(P.D_KM, 384400.0, 1.0e-9, "地月距离 384,400 km")
	_near(P.T_MOON_S, 2360591.51, 0.01, "月球恒星周期 2,360,591.51 s")
	_near(P.mu_moon_ratio(), 0.012150585, 1.0e-7, "μ = μ_moon/(μ_e+μ_m)")
	_near(P.moon_mean_motion(), TAU / P.T_MOON_S, 1.0e-15, "ω=2π/T_moon")
	var tc := P.canonical_time_s()
	var vc := P.canonical_velocity_kms()
	_ok(absf(tc - P.T_MOON_S / TAU) / tc < 0.01,
		"归一化时间 T_c 与 T_moon/(2π) 一致（<1%；GM 常数与观测周期舍入）")
	_near(vc, P.D_KM / tc, 1.0e-12, "归一化速度 V_c=D/T_c")
	_ok(tc > 300000.0 and tc < 400000.0, "T_c 量级 ~3.75e5 s")
	_ok(vc > 1.0 and vc < 1.1, "V_c 量级 ~1.0245 km/s")
	# 归一化往返
	var st := _state(Vector3(P.D_KM * 0.5, P.D_KM * 0.2, -3000.0), Vector3(0.1, -0.2, 0.05))
	var can := P.to_canonical(st)
	_ok(absf((can["r"] as Vector3).length() - 0.5385) < 1.0e-3, "归一化位置量级")
	var back := P.from_canonical(can)
	_near(_rel_dist(P.as_state(back)["r"], st["r"]), 0.0, 1.0e-9, "归一化往返位置一致")
	_near(P.as_state(back)["v"].distance_to(st["v"]), 0.0, 1.0e-12, "归一化往返速度一致")
	# 状态工具
	var arr := P.state_to_array_dict(st)
	_ok(arr.get("r") is Array and (arr.get("r") as Array).size() == 3, "state_to_array_dict r[3]")
	var st2 := P.as_state(arr)
	_near(_rel_dist(st2["r"], st["r"]), 0.0, 1.0e-9, "as_state 回读 r")
	_ok(P.is_finite_state(st), "合法状态 finite")
	_ok(not P.is_finite_state(_state(Vector3(NAN, 0, 0), Vector3.ZERO)), "NaN 状态 finite=false")
	var vcheck := P.validate_state(st)
	_ok(bool(vcheck.get("ok", false)), "validate_state 合法")
	_ok(not bool(P.validate_state(_state(Vector3.ZERO, Vector3.ZERO)).get("ok", true)),
		"validate_state 拒绝零半径")
	_data_line("constants", "μ=0.012150585 D=384400 T=2360591.51 Tc=%.1f Vc=%.6f" % [tc, vc])


# ═══════════════════════════════════════════════════════════════════
# 2. 参考系 / 状态转换
# ═══════════════════════════════════════════════════════════════════

func _test_frames() -> void:
	_section_begin("2 参考系 / 转换")
	var e_rot := P.earth_position_rot()
	var m_rot := P.moon_position_rot()
	var mu := P.mu_moon_ratio()
	_near(e_rot.x, -mu * P.D_KM, 1.0e-6, "地球旋转系 x=-μD")
	_near(m_rot.x, (1.0 - mu) * P.D_KM, 1.0e-6, "月球旋转系 x=(1-μ)D")
	_near((m_rot - e_rot).length(), P.D_KM, 1.0e-9, "地月旋转系距离 D")
	# 月球 ECI
	var m0 := P.moon_state_eci(0.0)
	_near((m0["r"] as Vector3).x, P.D_KM, 1.0e-6, "月球 t=0 在 +x")
	_near((m0["v"] as Vector3).y, P.moon_mean_motion() * P.D_KM, 1.0e-12, "月球 t=0 速度 +y")
	_near((m0["v"] as Vector3).length(), P.moon_mean_motion() * P.D_KM, 1.0e-12, "月球圆轨道速度 ωD")
	_near(float(m0.get("distance_km", 0.0)), P.D_KM, 1.0e-9, "月球距离 D")
	# 地心旋转/惯性
	var moon_erot := P.bary_rot_to_earth_rot(P.moon_state_rot())
	_near((moon_erot["r"] as Vector3).x, P.D_KM, 1.0e-6, "月球地心旋转系 x=D")
	var moon_back := P.earth_rot_to_bary_rot(moon_erot)
	_near(_rel_dist(P.as_state(moon_back)["r"], P.moon_position_rot()), 0.0, 1.0e-9,
		"地心旋转↔bary 旋转往返")
	# 月球 rot ↔ eci 往返
	for t in [0.0, 12345.0, P.T_MOON_S * 0.5]:
		var eci := P.bary_rot_to_earth_eci(P.moon_state_rot(), t)
		var expected := P.moon_state_eci(t)
		_near(_rel_dist(P.as_state(eci)["r"], expected["r"]), 0.0, 1.0e-6,
			"月球 rot→eci t=%.0f" % t)
		_near(P.as_state(eci)["v"].distance_to(expected["v"]), 0.0, 1.0e-9,
			"月球 rot→eci 速度 t=%.0f" % t)
		var rt := P.earth_eci_to_bary_rot(eci, t)
		_near(_rel_dist(P.as_state(rt)["r"], P.moon_position_rot()), 0.0, 0.01,
			"月球 eci→rot 往返 t=%.0f" % t)
	# 任意状态往返
	var st := _state(Vector3(200000.0, -90000.0, 30000.0), Vector3(0.5, 0.8, -0.1))
	for t2 in [0.0, 5000.0, 50000.0]:
		var eci2 := P.bary_rot_to_earth_eci(st, t2)
		var rot2 := P.earth_eci_to_bary_rot(eci2, t2)
		var rot_s := P.as_state(rot2)
		_near(_rel_dist(rot_s["r"], st["r"]), 0.0, 1.0e-6, "任意状态 eci→rot 位置往返 t=%.0f" % t2)
		_near((rot_s["v"] as Vector3).distance_to(st["v"]), 0.0, 1.0e-9,
			"任意状态 eci→rot 速度往返 t=%.0f" % t2)
	# 地球 ECI
	_near((P.earth_position_eci(0.0) as Vector3).x, -mu * P.D_KM, 1.0e-9, "地球 ECI t=0 x=-μD")
	var ev := P.earth_velocity_eci(0.0)
	_near(ev.length(), P.moon_mean_motion() * (mu * P.D_KM), 1.0e-12, "地球 ECI 速度 ω·μD")
	_data_line("frames", "bary rotating ↔ earth rotating ↔ earth ECI 位置/速度往返一致")


# ═══════════════════════════════════════════════════════════════════
# 3. 平衡点 L1–L5 / Jacobi
# ═══════════════════════════════════════════════════════════════════

func _test_equilibria() -> void:
	_section_begin("3 平衡点 L1–L5 / Jacobi")
	var lps := P.equilibrium_points()
	_eq(lps.size(), 5, "返回 5 个 L 点")
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		_ok(lps.has(lid), "含 " + lid)
		var lp: Dictionary = lps.get(lid, {})
		var pos: Vector3 = lp.get("pos_rot", Vector3.ZERO)
		_ok(P.is_finite_vec(pos), lid + " 位置有限")
		var jac := float(lp.get("jacobi", NAN))
		_ok(is_finite(jac), lid + " Jacobi 有限")
		var acc := P.acceleration_rot(P.lagrange_state(lid))
		_ok(acc.length() < 1.0e-5, lid + " 平衡点加速度≈0",
			"|a|=%s km/s²" % str(acc.length()))
		# 平衡点静止传播：位置漂移小
		var pr := P.propagate_state(P.lagrange_state(lid), 3600.0, {"step_s": 60.0})
		var pe := _as_state(pr)
		_near(_rel_dist(pe["r"], pos), 0.0, 1.0e-3, lid + " 3600 s 静止漂移 <1 m")
		_ok(float(pr.get("jacobi_drift", 1.0)) < 1.0e-8, lid + " 静止 Jacobi 漂移极小")
	var l1: Dictionary = lps.get("L1", {})
	var l2: Dictionary = lps.get("L2", {})
	var l3: Dictionary = lps.get("L3", {})
	var l4: Dictionary = lps.get("L4", {})
	var l5: Dictionary = lps.get("L5", {})
	_near(float(l1.get("moon_distance_km", 0.0)), 58100.0, 4000.0, "L1 距月球 ~58,000 km")
	_ok(float(l1.get("earth_distance_km", 0.0)) > 320000.0
		and float(l1.get("earth_distance_km", 0.0)) < 335000.0, "L1 距地球 320k–335k km")
	_ok(float(l2.get("moon_distance_km", 0.0)) > 60000.0
		and float(l2.get("moon_distance_km", 0.0)) < 70000.0, "L2 距月球 60k–70k km")
	_ok(float(l3.get("pos_rot", Vector3.ZERO).x) < 0.0, "L3 在月球反侧（x<0）")
	_near(float(l1.get("pos_rot", Vector3.ZERO).y), 0.0, 1.0e-9, "L1 y=0")
	_near(float(l2.get("pos_rot", Vector3.ZERO).y), 0.0, 1.0e-9, "L2 y=0")
	_near(float(l4.get("earth_distance_km", 0.0)), P.D_KM, 1.0e-6, "L4 距地球 = D")
	_near(float(l4.get("moon_distance_km", 0.0)), P.D_KM, 1.0e-6, "L4 距月球 = D")
	_near(float(l5.get("earth_distance_km", 0.0)), P.D_KM, 1.0e-6, "L5 距地球 = D")
	_near(float(l4.get("pos_rot", Vector3.ZERO).y),
		sqrt(3.0) * 0.5 * P.D_KM, 1.0e-6, "L4 y=+√3/2 D")
	_near(float(l5.get("pos_rot", Vector3.ZERO).y),
		-sqrt(3.0) * 0.5 * P.D_KM, 1.0e-6, "L5 y=-√3/2 D")
	_eq(String(l4.get("kind", "")), "triangular", "L4 kind=triangular")
	_eq(String(l1.get("kind", "")), "collinear", "L1 kind=collinear")
	_ok(float(l1.get("jacobi", 0.0)) > float(l4.get("jacobi", 0.0)),
		"L1 Jacobi > L4 Jacobi（稳定性差异）")
	_ok(float(l4.get("jacobi", 0.0)) < 3.0 and float(l4.get("jacobi", 0.0)) > 2.9,
		"L4 Jacobi ≈3-μ(1-μ)", "C=%.6f" % float(l4.get("jacobi", 0.0)))
	var lpos := (l4.get("pos_rot", Vector3.ZERO) as Vector3)
	_near((l5.get("pos_rot", Vector3.ZERO) as Vector3).x, lpos.x, 1.0e-6, "L4/L5 x 对称")
	# L 点偏移初始化
	var st_off := P.lagrange_state("L1", Vector3(100.0, -50.0, 20.0), Vector3(0.01, 0.0, 0.0))
	var l1pos: Vector3 = lps["L1"]["pos_rot"]
	_near(_rel_dist(P.as_state(st_off)["r"], l1pos + Vector3(100, -50, 20)), 0.0, 1.0e-9,
		"L1 偏移初始化")
	_near((P.as_state(st_off)["v"] as Vector3).x, 0.01, 1.0e-6, "L1 偏移速度初始化")
	_ok(P.lagrange_state("L9").is_empty(), "未知 L 点返回空")
	# Jacobi 与能量代理关系
	var st_test := P.lagrange_state("L4", Vector3(50.0, 20.0, 5.0), Vector3(0.001, -0.002, 0.0))
	var jac := P.jacobi_constant(st_test)
	var en := P.energy_proxy(st_test)
	var scale := P.moon_mean_motion() * P.moon_mean_motion() * P.D_KM * P.D_KM
	_near(jac, -2.0 * en / scale, 1.0e-12, "Jacobi 与能量代理一致")
	_ok(not is_finite(P.jacobi_constant(_state(Vector3(NAN, 0, 0), Vector3.ZERO))),
		"非法状态 Jacobi=NAN")
	# ECI 状态的 Jacobi
	var l4eci := P.bary_rot_to_earth_eci(P.lagrange_state("L4"), 777.0)
	_near(P.jacobi_from_earth_eci(l4eci, 777.0), P.jacobi_constant(P.lagrange_state("L4")),
		1.0e-9, "ECI→Jacobi 与旋转系一致")
	_data_line("L-points", "L1 dM=%.0f km C=%.6f · L4 C=%.6f" % [
		float(l1.get("moon_distance_km", 0.0)), float(l1.get("jacobi", 0.0)),
		float(l4.get("jacobi", 0.0))])


# ═══════════════════════════════════════════════════════════════════
# 4. CR3BP 传播 / 数值 / NaN
# ═══════════════════════════════════════════════════════════════════

func _test_cr3bp() -> void:
	_section_begin("4 CR3BP / RK4 / Jacobi / NaN")
	var st := P.lagrange_state("L1", Vector3(300.0, -120.0, 40.0), Vector3(0.01, 0.02, -0.004))
	var pr := P.propagate_state(st, 1800.0, {"step_s": 30.0})
	_ok(bool(pr.get("ok", false)), "CR3BP 传播成功", str(pr.get("reason", "")))
	_eq(int(pr.get("steps", 0)), 60, "1800 s / 30 s = 60 步")
	_near(float(pr.get("step_s", 0.0)), 30.0, 1.0e-9, "step_s=30")
	_ok(float(pr.get("jacobi_drift", 1.0)) < 1.0e-6, "Jacobi 守恒（漂移 <1e-6）",
		"drift=%s" % str(float(pr.get("jacobi_drift", 1.0))))
	_ok(is_finite(float(pr.get("jacobi", NAN))), "传播后 Jacobi 有限")
	_ok(bool(pr.get("finite", false)), "传播后状态有限")
	_ok((pr.get("warnings", []) as Array).is_empty(), "无漂移告警")
	# 零时长
	var p0 := P.propagate_state(st, 0.0)
	_eq(int(p0.get("steps", -1)), 0, "dt=0 steps=0")
	_near(_rel_dist(_as_state(p0)["r"], st["r"]), 0.0, 1.0e-12, "dt=0 状态不变")
	# 步长上限 60 s
	var pcap := P.propagate_state(st, 650.0, {"step_s": 120.0})
	_ok(float(pcap.get("step_s", 0.0)) <= 60.0 + 1.0e-9, "step_s 被 clamp 到 ≤60 s",
		"step_s=%.3f" % float(pcap.get("step_s", 0.0)))
	_eq(int(pcap.get("steps", 0)), 11, "650 s 按 60 s 上限 → 11 步")
	# 反向传播往返
	var fwd := _as_state(P.propagate_state(st, 600.0, {"step_s": 30.0}))
	var back := _as_state(P.propagate_state(fwd, -600.0, {"step_s": 30.0}))
	_ok(_rel_dist(back["r"], st["r"]) < 10.0, "正向+反向传播回到起点附近（<10 km）",
		"error=%.3f km" % _rel_dist(back["r"], st["r"]))
	# max_steps
	var pms := P.propagate_state(st, 1000.0, {"step_s": 60.0, "max_steps": 2})
	_ok(not bool(pms.get("ok", true)), "max_steps 限制触发失败")
	_eq(String(pms.get("reason", "")), "max_steps_exceeded", "reason=max_steps_exceeded")
	# 非法输入
	var pbad := P.propagate_state(_state(Vector3(NAN, 0, 0), Vector3.ZERO), 60.0)
	_ok(not bool(pbad.get("ok", true)), "NaN 状态传播被拒绝")
	_eq(String(pbad.get("reason", "")), "invalid_state", "reason=invalid_state")
	_ok(not bool(pbad.get("finite", true)), "非法输入 finite=false")
	var pzero := P.propagate_state(_state(Vector3.ZERO, Vector3.ZERO), 60.0)
	_ok(not bool(pzero.get("ok", true)), "零半径状态被拒绝")
	# sanitize
	var san := P.sanitize_state(_state(Vector3(NAN, INF, 1.0), Vector3(0.0, NAN, 0.0)))
	_ok(bool(san.get("changed", false)), "sanitize 标记 changed")
	_ok(bool(san.get("finite", false)), "sanitize 后 finite")
	_near((P.as_state(san.get("state", {}))["r"] as Vector3).x, 0.0, 1.0e-12, "sanitize NaN→0")
	# 批量
	var batch := P.propagate_states([st, P.lagrange_state("L4")], 120.0, {"step_s": 30.0})
	_eq(batch.size(), 2, "批量传播 2 条")
	_ok(bool((batch[0] as Dictionary).get("ok", false)), "批量[0] ok")
	_ok(bool((batch[1] as Dictionary).get("ok", false)), "批量[1] ok")
	_ok(_json_ok(pr), "传播结果 JSON 可序列化")
	# 加速度/有效势一致性：数值梯度检查 a ≈ -∇Ω（离心/科氏项按定义）
	var eps := 1.0
	var r0: Vector3 = st["r"]
	var pot0 := P.effective_potential(st)
	var grad := Vector3(
		(P.effective_potential(_state(r0 + Vector3(eps, 0, 0), Vector3.ZERO)) - pot0) / eps,
		(P.effective_potential(_state(r0 + Vector3(0, eps, 0), Vector3.ZERO)) - pot0) / eps,
		(P.effective_potential(_state(r0 + Vector3(0, 0, eps), Vector3.ZERO)) - pot0) / eps)
	var omega2 := P.moon_mean_motion() * P.moon_mean_motion()
	var a_grav := P.acceleration_rot(_state(r0, Vector3.ZERO)) + Vector3(-omega2 * r0.x, -omega2 * r0.y, 0.0)
	_ok((a_grav + grad).length() < 1.0e-3, "有效势梯度 = 引力+离心（数值校验）",
		"err=%s" % str((a_grav + grad).length()))
	_data_line("cr3bp", "1800 s / 30 s 步：Jacobi 漂移 %s；RK4 四阶；step ≤60 s" % str(float(pr.get("jacobi_drift", 0.0))))


# ═══════════════════════════════════════════════════════════════════
# 5. 两体 RK4 / 轨道闭合
# ═══════════════════════════════════════════════════════════════════

func _test_two_body() -> void:
	_section_begin("5 两体 RK4 / 轨道闭合")
	# LEO 400 km：周期闭合
	var r_leo := P.R_EARTH_KM + 400.0
	var st_leo := P.two_body_circular_state(P.MU_EARTH_KM3_S2, r_leo, 0.0)
	var v_circ := P.speed_for_circular_orbit(P.MU_EARTH_KM3_S2, r_leo)
	_near(float(st_leo.get("speed_kmps", 0.0)), v_circ, 1.0e-12, "LEO 圆轨道速度 √(μ/r)")
	_near(v_circ, 7.669, 0.01, "LEO 速度 ≈7.669 km/s")
	var per_leo := P.period_for_circular_orbit(P.MU_EARTH_KM3_S2, r_leo)
	_near(per_leo, 5553.5, 2.0, "LEO 周期 ≈5,553 s")
	var pr_leo := P.propagate_two_body(st_leo, P.MU_EARTH_KM3_S2, per_leo, {"step_s": 10.0})
	_ok(bool(pr_leo.get("ok", false)), "LEO 两体传播成功")
	var end_leo := _as_state(pr_leo)
	_ok(_rel_dist(end_leo["r"], st_leo["r"]) < 0.1, "LEO 一周期闭合误差 <100 m",
		"err=%.6f km" % _rel_dist(end_leo["r"], st_leo["r"]))
	_ok(int(pr_leo.get("steps", 0)) > 500, "LEO 步数 >500")
	# GEO 周期
	var st_geo := P.geo_state(0.0)
	_near((st_geo["r"] as Vector3).length(), 42164.0, 1.0e-6, "GEO 半径 42,164 km")
	_near((st_geo["v"] as Vector3).length(), P.speed_for_circular_orbit(P.MU_EARTH_KM3_S2, 42164.0),
		1.0e-9, "GEO 速度 √(μ/r)")
	var per_geo := float(st_geo.get("period_s", 0.0))
	_near(per_geo, 86163.6, 5.0, "GEO 周期 ≈86,164 s")
	_near(per_geo, 86164.0905, 5.0, "GEO 周期≈地球恒星日")
	var pr_geo := P.propagate_two_body(st_geo, P.MU_EARTH_KM3_S2, per_geo, {"step_s": 30.0})
	var end_geo := _as_state(pr_geo)
	_ok(_rel_dist(end_geo["r"], st_geo["r"]) < 5.0, "GEO 一周期闭合误差 <5 km",
		"err=%.3f km" % _rel_dist(end_geo["r"], st_geo["r"]))
	# LLO：绕月球两体闭合（把地心状态转成月心相对状态）
	var llo := P.llo_state(0.0)
	var moon0 := P.moon_state_eci(0.0)
	var rel_r: Vector3 = (llo["r"] as Vector3) - (moon0["r"] as Vector3)
	var rel_v: Vector3 = (llo["v"] as Vector3) - (moon0["v"] as Vector3)
	_near(rel_r.length(), P.llo_radius_km(), 0.02, "LLO 半径=R_moon+100 km")
	_near(rel_v.length(), P.speed_for_circular_orbit(P.MU_MOON_KM3_S2, P.llo_radius_km()),
		1.0e-9, "LLO 绕月速度 √(μ_moon/r)")
	var per_llo := P.period_for_circular_orbit(P.MU_MOON_KM3_S2, P.llo_radius_km())
	_near(per_llo, 7067.5, 5.0, "LLO 周期 ≈7,067 s")
	var pr_llo := P.propagate_two_body(_state(rel_r, rel_v), P.MU_MOON_KM3_S2, per_llo, {"step_s": 10.0})
	var end_llo := _as_state(pr_llo)
	_ok(_rel_dist(end_llo["r"], rel_r) < 0.5, "LLO 一周期闭合误差 <500 m",
		"err=%.6f km" % _rel_dist(end_llo["r"], rel_r))
	# LLO 倾角版本
	var llo_polar := P.llo_state(0.0, PI * 0.5, 90.0)
	_near(((llo_polar["r"] as Vector3) - (moon0["r"] as Vector3)).length(),
		P.llo_radius_km(), 0.02, "极轨 LLO 半径一致")
	_ok(absf((llo_polar["r"] as Vector3).z - (moon0["r"] as Vector3).z) > 1.0,
		"极轨 LLO 有 z 分量")
	# 转移椭圆
	var tr := P.transfer_state(6778.0, P.D_KM, 0.0)
	_near((tr["r"] as Vector3).length(), 6778.0, 1.0e-6, "转移轨道 ν=0 在近地点")
	_ok(float(tr.get("e", 0.0)) > 0.9 and float(tr.get("e", 0.0)) < 1.0, "转移轨道高偏心率")
	var v_expected := sqrt(P.MU_EARTH_KM3_S2 * (2.0 / 6778.0 - 1.0 / float(tr.get("a_km", 1.0))))
	_near((tr["v"] as Vector3).length(), v_expected, 1.0e-9, "转移轨道近地点速度 vis-viva")
	_ok(float(tr.get("period_s", 0.0)) > 0.0, "转移轨道周期 >0")
	# 月球圆轨道周期由 μ_total/D 推出
	var t_moon_calc := P.period_for_circular_orbit(P.mu_total(), P.D_KM)
	_ok(absf(t_moon_calc - P.T_MOON_S) / P.T_MOON_S < 0.01,
		"μ_total+D 反推月球周期与 T_moon 一致（<1%）",
		"calc=%.1f s T=%.1f s" % [t_moon_calc, P.T_MOON_S])
	_data_line("orbit-closure", "LEO %.3f km · GEO %.3f km · LLO %.3f km（RK4 一周期）" % [
		_rel_dist(end_leo["r"], st_leo["r"]), _rel_dist(end_geo["r"], st_geo["r"]),
		_rel_dist(end_llo["r"], rel_r)])


# ═══════════════════════════════════════════════════════════════════
# 6. 月球 / 地球 / 时间
# ═══════════════════════════════════════════════════════════════════

func _test_moon_geo_llo() -> void:
	_section_begin("6 月球 / 时间")
	var m0 := P.moon_state_eci(0.0)
	var mt := P.moon_state_eci(P.T_MOON_S * 0.25)
	var phase := float(mt.get("phase_rad", 0.0))
	_near(phase, PI * 0.5, 1.0e-9, "t=T/4 月球相位 π/2")
	_near((mt["r"] as Vector3).y, P.D_KM, 1.0e-6, "t=T/4 月球在 +y")
	var m_period := P.moon_state_eci(P.T_MOON_S)
	_ok(_rel_dist(m_period["r"], m0["r"]) < 0.01, "t=T 月球回到 t=0 位置（<10 m）",
		"err=%.6f km" % _rel_dist(m_period["r"], m0["r"]))
	_near(P.moon_phase(0.0), 0.0, 1.0e-12, "moon_phase(0)=0")
	_near(P.moon_phase(P.T_MOON_S), 0.0, 1.0e-9, "moon_phase(T)=0")
	var speed := (m0["v"] as Vector3).length()
	_near(speed, 1.0228, 0.01, "月球轨道速度 ≈1.023 km/s")
	# 地球/月球旋转系
	_eq((P.moon_state_rot()["v"] as Vector3).length(), 0.0, "月球旋转系速度 0")
	# 月球距离/周期字段
	_near(float(m0.get("period_s", 0.0)), P.T_MOON_S, 1.0e-6, "月球周期字段")
	_data_line("moon", "T=%.2f s · r=%.1f km · v=%.4f km/s" % [P.T_MOON_S, P.D_KM, speed])


# ═══════════════════════════════════════════════════════════════════
# 7. 相对运动 / LVLH / CW
# ═══════════════════════════════════════════════════════════════════

func _test_relative_cw() -> void:
	_section_begin("7 相对运动 / LVLH / CW")
	# 相对状态
	var chaser := _state(Vector3(7000, 0, 0), Vector3(0, 7.5, 0))
	var target := _state(Vector3(7001, 0, 0), Vector3(-0.1, 7.5, 0))
	var rel := P.relative_state(chaser, target)
	var dr: Vector3 = rel.get("dr", Vector3.ZERO)
	_near(dr.x, 1.0, 1.0e-12, "Δr x=1 km")
	_near(float(rel.get("range_km", 0.0)), 1.0, 1.0e-12, "range=1 km")
	_near(float(rel.get("range_rate_kmps", 0.0)), -0.1, 1.0e-12, "range_rate=-0.1 km/s")
	_near(float(rel.get("closing_kmps", 0.0)), 0.1, 1.0e-12, "closing=0.1 km/s")
	_near(float(rel.get("tca_s", 0.0)), 10.0, 1.0e-9, "TCA=10 s（线性近似）")
	_near(float(rel.get("relative_speed_kmps", 0.0)), 0.1, 1.0e-12, "相对速度 0.1 km/s")
	_near((rel.get("los_unit", Vector3.ZERO) as Vector3).x, 1.0, 1.0e-12, "LOS +x")
	var rel_same := P.relative_state(chaser, chaser)
	_near(float(rel_same.get("range_km", -1.0)), 0.0, 1.0e-12, "同点 range=0")
	_near(float(rel_same.get("tca_s", -2.0)), -1.0, 1.0e-12, "同点无 TCA")
	# LVLH 基
	var basis := P.lvlh_basis(Vector3(7000, 0, 0), Vector3(0, 7.5, 0))
	_near((basis["R"] as Vector3).x, 1.0, 1.0e-12, "LVLH R=+x")
	_near((basis["S"] as Vector3).y, 1.0, 1.0e-12, "LVLH S=+y")
	_near((basis["W"] as Vector3).z, 1.0, 1.0e-12, "LVLH W=+z")
	_near((basis["R"] as Vector3).dot(basis["S"] as Vector3), 0.0, 1.0e-12, "R·S=0")
	_near((basis["R"] as Vector3).dot(basis["W"] as Vector3), 0.0, 1.0e-12, "R·W=0")
	_near((basis["S"] as Vector3).length(), 1.0, 1.0e-12, "S 单位长度")
	var lvlh := P.to_lvlh(Vector3(1.0, 2.0, 3.0), basis)
	_near(lvlh.x, 1.0, 1.0e-12, "to_lvlh x")
	_near(lvlh.y, 2.0, 1.0e-12, "to_lvlh y")
	_near(lvlh.z, 3.0, 1.0e-12, "to_lvlh z")
	# CW 矩阵：t=0 为单位阵
	var m0 := P.cw_matrix(0.001, 0.0)
	var identity_ok := true
	for i in range(6):
		for j in range(6):
			var expect := 1.0 if i == j else 0.0
			if absf(float(m0[i][j]) - expect) > 1.0e-12:
				identity_ok = false
	_ok(identity_ok, "CW 矩阵 t=0 为单位阵")
	_eq((P.cw_matrix(0.001, 100.0) as Array).size(), 6, "CW 矩阵 6 行")
	_eq((((P.cw_matrix(0.001, 100.0) as Array)[0]) as Array).size(), 6, "CW 矩阵 6 列")
	# 零相对状态保持零
	var zero_rel := {"x": 0.0, "y": 0.0, "z": 0.0, "vx": 0.0, "vy": 0.0, "vz": 0.0}
	var zero_out := P.propagate_cw(zero_rel, 0.001, 1000.0)
	_near(float(zero_out.get("x", 1.0)), 0.0, 1.0e-15, "CW 零状态 → x=0")
	_near(float(zero_out.get("y", 1.0)), 0.0, 1.0e-15, "CW 零状态 → y=0")
	# 圆相对运动一周期闭合
	var n := TAU / 5553.5
	var rel0 := {"x": 1.0, "y": 0.0, "z": 0.0, "vx": 0.0, "vy": -2.0 * n, "vz": 0.0}
	var relT := P.propagate_cw(rel0, n, TAU / n)
	_near(float(relT.get("x", 0.0)), 1.0, 1.0e-9, "CW 圆相对运动一周期 x 闭合")
	_near(float(relT.get("y", 1.0)), 0.0, 1.0e-9, "CW 圆相对运动一周期 y 闭合")
	_near(float(relT.get("vx", 1.0)), 0.0, 1.0e-9, "CW 圆相对运动一周期 vx 闭合")
	_near(float(relT.get("vy", 0.0)), -2.0 * n, 1.0e-9, "CW 圆相对运动一周期 vy 闭合")
	# CW t=0 保持输入
	var out0 := P.propagate_cw(rel0, n, 0.0)
	_near(float(out0.get("x", 0.0)), 1.0, 1.0e-12, "CW t=0 保持 x")
	_near(float(out0.get("vy", 0.0)), -2.0 * n, 1.0e-12, "CW t=0 保持 vy")
	_data_line("relative", "Δr/Δv/closing/TCA/LVLH/CW（一周期闭合 <1e-9）")


# ═══════════════════════════════════════════════════════════════════
# 8. 接近走廊 / 对接几何
# ═══════════════════════════════════════════════════════════════════

func _test_corridor_docking() -> void:
	_section_begin("8 接近走廊 / 对接几何")
	var spec := P.default_corridor_spec()
	_ok(int(spec.get("half_angle_deg", 0)) > 0, "默认走廊有半角")
	_ok(float(spec.get("length_km", 0.0)) > 0.0, "默认走廊长度 >0")
	var pass_pos := Vector3(50.0, 0.0, 0.0)
	var pass_vel := Vector3(-0.02, 0.0, 0.0)
	var c_pass := P.approach_corridor_check(pass_pos, pass_vel, spec)
	_ok(bool(c_pass.get("ok", false)), "走廊内/对齐/减速 → ok")
	_ok(bool(c_pass.get("inside", false)), "走廊 inside")
	_near(float(c_pass.get("along_km", 0.0)), 50.0, 1.0e-9, "along=50 km")
	_near(float(c_pass.get("lateral_km", 0.0)), 0.0, 1.0e-9, "lateral=0")
	_near(float(c_pass.get("closing_mps", 0.0)), 20.0, 1.0e-9, "closing=20 m/s")
	_ok(float(c_pass.get("align_angle_deg", 99.0)) < 1.0e-6, "对齐角≈0")
	_eq(String(c_pass.get("status", "")), "in_corridor", "status=in_corridor")
	# 横向偏出
	var c_lat := P.approach_corridor_check(Vector3(50.0, 20.0, 0.0), pass_vel, spec)
	_ok(not bool(c_lat.get("inside", true)), "横向 20 km → 走廊外")
	_ok((c_lat.get("warnings", []) as Array).size() > 0, "走廊外有 warning")
	# 角度偏差
	var c_ang := P.approach_corridor_check(Vector3(20.0, 20.0, 0.0), Vector3(-0.02, 0.0, 0.0), spec)
	_ok(float(c_ang.get("align_angle_deg", 0.0)) > 15.0, "角度偏差 >15°")
	_ok(not bool(c_ang.get("angle_ok", true)), "角度超限 angle_ok=false")
	# 速度超限
	var c_spd := P.approach_corridor_check(pass_pos, Vector3(-0.1, 0.0, 0.0), spec)
	_ok(not bool(c_spd.get("speed_ok", true)), "接近速度 100 m/s → speed_ok=false")
	_ok(float(c_spd.get("closing_mps", 0.0)) > 50.0, "closing > 50 m/s")
	# 超出长度
	var c_len := P.approach_corridor_check(Vector3(200.0, 0.0, 0.0), pass_vel, spec)
	_ok(not bool(c_len.get("inside", true)), "超出走廊长度")
	# 自定义走廊轴
	var custom := {"axis": [0.0, 1.0, 0.0], "half_angle_deg": 20.0, "lateral_tol_km": 5.0,
		"max_closing_mps": 10.0, "max_angle_deg": 20.0}
	var c_custom := P.approach_corridor_check(Vector3(0.0, 30.0, 0.0), Vector3(0.0, -0.005, 0.0), custom)
	_ok(bool(c_custom.get("ok", false)), "自定义 +y 走廊通过")
	_near(float(c_custom.get("along_km", 0.0)), 30.0, 1.0e-9, "自定义 along=30")
	# 对接
	var ds := P.default_docking_spec()
	var d_aligned := P.docking_geometry(Vector3(5.0, 0.0, 0.0), Vector3(-0.01, 0.0, 0.0), Vector3.RIGHT, ds)
	_eq(String(d_aligned.get("status", "")), "aligned", "对接对齐 → aligned")
	_ok(bool(d_aligned.get("ok", false)), "aligned ok")
	_near(float(d_aligned.get("axial_km", 0.0)), 5.0, 1.0e-9, "轴向 5 km")
	_near(float(d_aligned.get("closing_mps", 0.0)), 10.0, 1.0e-9, "接近速度 10 m/s")
	var d_docked := P.docking_geometry(Vector3(0.03, 0.0, 0.0), Vector3(-0.00005, 0.0, 0.0),
		Vector3.RIGHT, ds)
	_eq(String(d_docked.get("status", "")), "docked", "接触范围/低速 → docked")
	_ok(bool(d_docked.get("ok", false)), "docked ok")
	var d_fast := P.docking_geometry(Vector3(0.5, 0.0, 0.0), Vector3(-0.1, 0.0, 0.0),
		Vector3.RIGHT, ds)
	_eq(String(d_fast.get("status", "")), "too_fast", "高速 → too_fast")
	var d_mis := P.docking_geometry(Vector3(0.5, 0.5, 0.0), Vector3(-0.001, 0.0, 0.0),
		Vector3.RIGHT, ds)
	_eq(String(d_mis.get("status", "")), "misaligned", "横向偏移 → misaligned")
	_ok(float(d_mis.get("lateral_km", 0.0)) > 0.2, "misaligned lateral>0.2 km")
	var d_ang := P.docking_geometry(Vector3(0.2, 0.1, 0.0), Vector3(-0.001, 0.0, 0.0),
		Vector3.RIGHT, ds)
	_eq(String(d_ang.get("status", "")), "misaligned", "角度偏差 → misaligned")
	# 对接序列
	var seq := P.docking_sequence([
		{"r": [20.0, 0.0, 0.0], "v": [-0.01, 0.0, 0.0]},
		{"r": [2.0, 0.0, 0.0], "v": [-0.005, 0.0, 0.0]},
		{"r": [0.03, 0.0, 0.0], "v": [-0.00005, 0.0, 0.0]},
	], Vector3.RIGHT, ds)
	_eq(seq.size(), 3, "对接序列 3 点")
	_eq(String((seq[0] as Dictionary).get("status", "")), "aligned", "序列[0] aligned")
	_eq(String((seq[2] as Dictionary).get("status", "")), "docked", "序列[2] docked")
	_ok(_json_ok(seq), "对接序列 JSON 可序列化")
	_data_line("corridor/docking", "走廊 inside/angle/speed；对接 aligned/docked/too_fast/misaligned")


# ═══════════════════════════════════════════════════════════════════
# 9. 实例实体 / sample_entity / JSON
# ═══════════════════════════════════════════════════════════════════

func _test_instance_entities() -> void:
	_section_begin("9 实例实体 / sample_entity")
	var sim = P.new({"step_s": 120.0})
	_ok(float(sim.config.get("step_s", 0.0)) <= 60.0 + 1.0e-9, "实例 step_s clamp ≤60")
	var add: Dictionary = sim.add_entity("probe-1", P.lagrange_state("L4", Vector3(10.0, 5.0, 2.0),
		Vector3(0.001, -0.001, 0.0)))
	_ok(bool(add.get("ok", false)), "add_entity 成功")
	_eq(sim.entity_ids().size(), 1, "entity_ids=1")
	var bad_add: Dictionary = sim.add_entity("bad", _state(Vector3(NAN, 0, 0), Vector3.ZERO))
	_ok(not bool(bad_add.get("ok", true)), "非法实体 add 失败")
	_eq(sim.entity_ids().size(), 1, "非法实体未加入")
	var pr: Dictionary = sim.propagate(3600.0)
	_ok(bool(pr.get("ok", false)), "实体推进 3600 s 成功")
	_eq(int(pr.get("steps", 0)), 60, "3600/60 = 60 步")
	var sample: Dictionary = sim.sample_entity("probe-1")
	_ok(not sample.is_empty(), "sample_entity 返回")
	for key in ["id", "t", "state_rot", "state_earth_eci", "state_earth_rot", "jacobi",
			"energy", "finite", "earth_distance_km", "moon_distance_km"]:
		_ok(sample.has(key), "sample 字段 " + key)
	_ok(bool(sample.get("finite", false)), "sample finite")
	_ok(is_finite(float(sample.get("jacobi", NAN))), "sample Jacobi 有限")
	_eq(((sample.get("state_rot", {}) as Dictionary).get("r", []) as Array).size(), 3,
		"state_rot.r[3]")
	_ok(float(sample.get("jacobi", 0.0)) > 2.0 and float(sample.get("jacobi", 0.0)) < 4.0,
		"实体 Jacobi 量级合理")
	var sample2: Dictionary = sim.sample_entity("probe-1")
	_near(float(sample2.get("jacobi", 0.0)), float(sample.get("jacobi", 0.0)), 1.0e-9,
		"sample 可重复")
	_ok(sim.sample_entity("unknown").is_empty(), "未知实体 sample 为空")
	_ok(sim.remove_entity("probe-1"), "remove_entity 成功")
	_eq(sim.entity_ids().size(), 0, "移除后实体 0")
	var dict: Dictionary = sim.to_dict()
	for key2 in ["schema", "model", "authoritative", "t", "config", "entities", "constants"]:
		_ok(dict.has(key2), "to_dict 字段 " + key2)
	_ok(not bool(dict.get("authoritative", true)), "to_dict authoritative=false")
	_ok(_json_ok(dict), "实例 to_dict JSON 可序列化/回读")
	_eq(String(dict.get("model", "")), "cr3bp_rk4_circular", "model 标识")
	var sim2 = P.new({"max_steps": 2})
	sim2.add_entity("e2", P.lagrange_state("L4"))
	var pr_fail: Dictionary = sim2.propagate(1000.0)
	_ok(not bool(pr_fail.get("ok", true)), "max_steps 超限 → 实例推进失败")
	# 多实体推进
	var sim3 = P.new()
	sim3.add_entity("a", P.lagrange_state("L1"))
	sim3.add_entity("b", P.lagrange_state("L5"))
	sim3.propagate(120.0)
	_eq(sim3.sample_all().size(), 2, "sample_all 2 实体")
	_ok(_json_ok(sim3.sample_all()), "sample_all JSON 可序列化")
	# 实体 ECI/旋转系采样关系
	var s3: Dictionary = sim3.sample_entity("a")
	var rot_r: Array = (s3.get("state_rot", {}) as Dictionary).get("r", [])
	var eci_r: Array = (s3.get("state_earth_eci", {}) as Dictionary).get("r", [])
	_ok((rot_r as Array).size() == 3 and (eci_r as Array).size() == 3, "实体旋转/ECI 状态 r[3]")
	_data_line("instance", "实体推进/采样；step≤60 s；JSON/多实体/移除/未知实体")


# ═══════════════════════════════════════════════════════════════════
# 10. NaN / JSON
# ═══════════════════════════════════════════════════════════════════

func _test_nan_json() -> void:
	_section_begin("10 NaN / JSON")
	var pr := P.propagate_state(_state(Vector3(1, 0, 0), Vector3(0, 0.1, 0)), 60.0)
	_ok(_json_ok(pr), "传播结果 JSON 可序列化")
	var bad := P.propagate_state(_state(Vector3(NAN, INF, 0), Vector3.ZERO), 60.0)
	_ok(not bool(bad.get("ok", true)), "非有限输入失败")
	_ok(_json_ok(bad), "失败结果 JSON 可序列化")
	_ok(not is_finite(P.jacobi_constant(_state(Vector3.ZERO, Vector3(NAN, 0, 0)))),
		"非有限速度 Jacobi=NAN")
	_ok(not is_finite(P.effective_potential(_state(Vector3(INF, 0, 0), Vector3.ZERO))),
		"有效势接口对 Inf 返回非有限")
	var san := P.sanitize_state(_state(Vector3(INF, NAN, -INF), Vector3(NAN, 0, NAN)))
	_ok(bool(san.get("finite", false)), "sanitize 后 finite")
	_ok(_json_ok(P.state_to_array_dict(san.get("state", {}))), "sanitize 状态 JSON")
	# 状态数组 JSON
	var st := _state(Vector3(1.5, 2.5, -3.5), Vector3(0.01, -0.02, 0.03))
	var arr := P.state_to_array_dict(st)
	var back := P.as_state(arr)
	_ok(_json_ok(arr), "state JSON")
	_near((back["r"] as Vector3).distance_to(st["r"]), 0.0, 1.0e-12, "state JSON 回读 r")
	_near((back["v"] as Vector3).distance_to(st["v"]), 0.0, 1.0e-12, "state JSON 回读 v")
	_data_line("nan/json", "NaN/Inf 输入拒绝；sanitize；状态/实例/传播 JSON 安全")


# ═══════════════════════════════════════════════════════════════════
# 11. 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("11 确定性")
	var st := P.lagrange_state("L1", Vector3(123.0, -45.0, 20.0), Vector3(0.002, 0.001, 0.0))
	var a := P.propagate_state(st, 900.0, {"step_s": 30.0})
	var b := P.propagate_state(st, 900.0, {"step_s": 30.0})
	_eq(str(a.get("state", {})), str(b.get("state", {})), "同输入传播结果逐位一致")
	_near(float(a.get("jacobi", 0.0)), float(b.get("jacobi", 0.0)), 1.0e-15, "Jacobi 确定性")
	var sim_a = P.new()
	var sim_b = P.new()
	sim_a.add_entity("x", st)
	sim_b.add_entity("x", st)
	sim_a.propagate(900.0)
	sim_b.propagate(900.0)
	_ok(str(sim_a.sample_entity("x")) == str(sim_b.sample_entity("x")), "实例推进确定性")
	# 两体 RFC
	var s1 := P.two_body_circular_state(P.MU_EARTH_KM3_S2, 7000.0, 0.3)
	var p1 := P.propagate_two_body(s1, P.MU_EARTH_KM3_S2, 600.0, {"step_s": 10.0})
	var p2 := P.propagate_two_body(s1, P.MU_EARTH_KM3_S2, 600.0, {"step_s": 10.0})
	_eq(str(p1.get("state", {})), str(p2.get("state", {})), "两体传播确定性")
	_data_line("determinism", "CR3BP/两体/实体推进同输入逐位一致")
