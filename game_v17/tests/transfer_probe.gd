extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 阶段2-CORE-A probe：L4-02 → L1 真实轨道转场（CR3BP/RK4 + Lambert/脉冲）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/transfer_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次，不做全量回归；不接 UI/bridge。
# ═══════════════════════════════════════════════════════════════════

const Planner := preload("res://framework/sim/transfer_planner.gd")
const Physics := preload("res://framework/sim/cislunar_physics.gd")
const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2-CORE-A PROBE · L4-02 → L1 真实轨道转场")
	print("════════════════════════════════════════════════════════════")
	var t0 := Time.get_ticks_msec()
	_test_scenario()
	_test_ports()
	_test_rk4()
	_test_lambert()
	var plan: Dictionary = _test_plan()
	_test_timeline(plan)
	_test_fleet(plan)
	_test_json_determinism(plan)
	_test_edges()
	var elapsed := Time.get_ticks_msec() - t0
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("probe elapsed_ms=%d" % elapsed)
	print("V17 TRANSFER PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 TRANSFER PROBE FAILED")
		quit(1)
	else:
		print("V17 TRANSFER PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f tol=%.6f" % [actual, expected, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _finite_num(v) -> bool:
	return (v is float or v is int) and is_finite(float(v))

func _arr3_finite(a) -> bool:
	if not (a is Array) or (a as Array).size() < 3:
		return false
	var arr: Array = a
	for i in range(3):
		if not _finite_num(arr[i]):
			return false
	return true

func _vec_like_finite(v) -> bool:
	if v is Vector3:
		return Physics.is_finite_vec(v)
	return _arr3_finite(v)

func _all_arrays_finite(state: Dictionary) -> bool:
	return _vec_like_finite(state.get("r")) and _vec_like_finite(state.get("v"))

# ═══════════════════════════════════════════════════════════════════
# 1. 新场景骨架
# ═══════════════════════════════════════════════════════════════════

func _test_scenario() -> void:
	_section_begin("1 场景骨架")
	_ok(FileAccess.file_exists(SCENARIO_PATH), "scenario 文件存在")
	var text := ""
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
	_ok(text.length() > 1000, "scenario 文本非空", "len=%d" % text.length())
	var parsed = JSON.parse_string(text)
	_ok(parsed is Dictionary, "scenario JSON 可解析")
	var sc: Dictionary = parsed if parsed is Dictionary else {}
	_eq(String(sc.get("schema", "")), "scenario.v2", "schema=scenario.v2")
	_eq(String(sc.get("id", "")), "transit_l4_l1", "id=transit_l4_l1")
	_eq(String(sc.get("own_entity", "")), "apsis", "own_entity=apsis")
	_ok(String(sc.get("title", "")).contains("L4-02"), "title 含 L4-02",
		String(sc.get("title", "")))
	_ok(float(sc.get("epoch", -1.0)) > 0.0, "epoch 有效")
	_eq(String(sc.get("datum", "")), "L4", "datum=L4")
	var transfer: Dictionary = sc.get("transfer", {}) if sc.get("transfer") is Dictionary else {}
	_eq(String(transfer.get("source_port", "")), "l4_02_hammer", "source_port")
	_eq(String(transfer.get("target_port", "")), "l1_meridian_05", "target_port")
	var cluster: Array = transfer.get("target_cluster", [])
	_eq(cluster.size(), 3, "L1 港群 3 个端口")
	_ok(String(transfer.get("planner", "")).contains("transfer_planner.gd"), "planner 路径")
	_eq(String(transfer.get("method", "")), "lambert_seed_cr3bp_shooting", "method")
	_eq(String(transfer.get("frame_rotating", "")), "bary_rot", "frame_rotating")
	_eq(String(transfer.get("frame_inertial", "")), "earth_eci", "frame_inertial")
	_ok((transfer.get("tof_days_candidates", []) as Array).size() >= 3, "TOF 候选 ≥3")
	var gate: Dictionary = transfer.get("arrival_gate", {}) if transfer.get("arrival_gate") is Dictionary else {}
	_ok(gate.has("radius_km") and gate.has("relative_speed_kmps") and gate.has("time_window_days"),
		"arrival_gate 字段齐全")
	var entities: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_ok(entities.size() >= 9, "entities ≥9", str(entities.size()))
	var ids := {}
	var fleet_ids: Array = []
	var port_ids: Array = []
	for raw in entities:
		var e: Dictionary = raw
		var eid := String(e.get("id", ""))
		ids[eid] = true
		_ok(eid != "", "entity id 非空")
		_ok(String(e.get("batch", "")) != "", "entity %s batch" % eid)
		_ok(String(e.get("kind", "")) != "", "entity %s kind" % eid)
		var orbit: Dictionary = e.get("orbit", {}) if e.get("orbit") is Dictionary else {}
		_ok(_arr3_finite(orbit.get("r", [])), "entity %s orbit.r 有限" % eid)
		_ok(_arr3_finite(orbit.get("v", [])), "entity %s orbit.v 有限" % eid)
		if String(e.get("kind", "")) == "ship":
			fleet_ids.append(eid)
		if String(e.get("kind", "")) in ["station", "tank", "berth", "drydock"]:
			port_ids.append(eid)
	for expected in ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]:
		_ok(ids.has(expected), "fleet entity: " + expected)
	for expected in ["l4_02_hammer", "l1_meridian_05", "l1_anchorage_02", "l1_drydock_01"]:
		_ok(ids.has(expected), "port entity: " + expected)
	for old_id in ["summons_4471", "ceres_2", "chronos_station", "tank_farm"]:
		_ok(not ids.has(old_id), "无旧关卡实体: " + old_id)
	_eq(fleet_ids.size(), 5, "fleet ships=5")
	_eq(port_ids.size(), 4, "ports entities=4")
	var ports: Array = sc.get("ports", []) if sc.get("ports") is Array else []
	_eq(ports.size(), 4, "ports 数组 4 个")
	for raw_p in ports:
		var p: Dictionary = raw_p
		_ok(String(p.get("port_id", "")) != "", "port_id 非空")
		_ok(_arr3_finite(p.get("offset_km", [])), "port offset finite")
	var meta: Dictionary = sc.get("meta", {}) if sc.get("meta") is Dictionary else {}
	_eq(String(meta.get("stage", "")), "stage2-core-A", "meta.stage")
	_eq(bool(meta.get("no_legacy_entities", false)), true, "meta.no_legacy_entities")
	_eq(bool(meta.get("default_start", true)), false, "不改默认启动")
	_ok(JSON.stringify(sc).length() > text.length() / 2, "scenario 可重新序列化")
	_data_line("scenario", "id=transit_l4_l1 entities=%d ports=%d fleet=%d" % [
		entities.size(), ports.size(), fleet_ids.size()])

# ═══════════════════════════════════════════════════════════════════
# 2. L4/L1 位置与港口
# ═══════════════════════════════════════════════════════════════════

func _test_ports() -> void:
	_section_begin("2 L4/L1 位置")
	var lps: Dictionary = Physics.equilibrium_points()
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		_ok(lps.has(lid), "平衡点存在: " + lid)
		if lps.has(lid):
			var row: Dictionary = lps[lid]
			_ok(row.get("pos_rot") is Vector3, "L %s pos_rot 类型" % lid)
			_ok(String(row.get("kind", "")) != "", "L %s kind" % lid)
	var l1: Dictionary = lps.get("L1", {})
	var l4: Dictionary = lps.get("L4", {})
	var l1_pos: Vector3 = l1.get("pos_rot", Vector3.ZERO)
	var l4_pos: Vector3 = l4.get("pos_rot", Vector3.ZERO)
	var earth_rot := Physics.earth_position_rot()
	_near((l1_pos - earth_rot).length(), 326381.0, 30.0, "L1 地心距 ≈326,381 km")
	_near((l4_pos - earth_rot).length(), 384400.0, 5.0, "L4 地心距 = 384,400 km")
	_ok((l1_pos - l4_pos).length() > 50000.0, "L4 与 L1 间距 > 5 万 km")
	var src: Dictionary = Planner.l4_port_state()
	var tgt: Dictionary = Planner.l1_port_state()
	_ok(_all_arrays_finite(src), "L4-02 母港状态有限")
	_ok(_all_arrays_finite(tgt), "L1 港状态有限")
	var src_off: Vector3 = (Physics.as_state(src)["r"] as Vector3) - l4_pos
	var tgt_off: Vector3 = (Physics.as_state(tgt)["r"] as Vector3) - l1_pos
	_ok(src_off.length() > 0.0, "L4-02 偏离 L4 点", "%.1f km" % src_off.length())
	_ok(src_off.length() < 3000.0, "L4-02 在 L4 附近", "%.1f km" % src_off.length())
	_ok(tgt_off.length() > 0.0, "L1 港偏离 L1 点", "%.1f km" % tgt_off.length())
	_ok(tgt_off.length() < 3000.0, "L1 港在 L1 附近", "%.1f km" % tgt_off.length())
	var cluster: Array = Planner.l1_cluster_offsets()
	_eq(cluster.size(), 3, "L1 港群 offsets=3")
	for raw in cluster:
		var p: Dictionary = raw
		_ok(String(p.get("port_id", "")) != "", "港群 port_id")
		var st: Dictionary = Physics.lagrange_state("L1",
			Physics.to_vec3(p.get("offset_km", []), Vector3.ZERO))
		_ok(_all_arrays_finite(st), "港 %s 状态有限" % String(p.get("port_id", "")))
	var l4_summary: Dictionary = Planner._port_summary("x", src, "L4")
	_ok(float(l4_summary.get("earth_distance_km", 0.0)) > 380000.0, "L4-02 地心距")
	var l1_summary: Dictionary = Planner._port_summary("y", tgt, "L1")
	_ok(float(l1_summary.get("earth_distance_km", 0.0)) > 320000.0, "L1 港地心距")
	_data_line("positions", "L1=%.1fkm L4=%.1fkm src_off=%.1f tgt_off=%.1f" % [
		(l1_pos - earth_rot).length(), (l4_pos - earth_rot).length(),
		src_off.length(), tgt_off.length()])

# ═══════════════════════════════════════════════════════════════════
# 3. RK4 / CR3BP 传播
# ═══════════════════════════════════════════════════════════════════

func _test_rk4() -> void:
	_section_begin("3 RK4 传播")
	var src: Dictionary = Physics.as_state(Planner.l4_port_state())
	var r: Vector3 = src["r"]
	var v: Vector3 = src["v"]
	var v_moving := Vector3(0.01, 0.005, -0.003)
	var p1: Dictionary = Physics.propagate_state(Physics.make_state(r, v_moving), 60.0, {"step_s": 60.0})
	_ok(bool(p1.get("ok", false)), "propagate 60s ok")
	_ok(int(p1.get("steps", 0)) >= 1, "propagate steps>=1", str(p1.get("steps", 0)))
	_ok(bool(p1.get("finite", false)), "propagate finite")
	var s1: Dictionary = Physics.as_state(p1.get("state", {}))
	_ok(_all_arrays_finite({"r": s1["r"], "v": s1["v"]}), "推进后状态有限")
	_ok((s1["r"] - r).length() > 0.1, "推进后位置变化",
		"delta=%.3f km" % (s1["r"] - r).length())
	_ok(_finite_num(p1.get("jacobi", NAN)), "Jacobi 有限")
	_near(float(p1.get("jacobi_drift", 9.0)), 0.0, 1.0e-4, "Jacobi 漂移小")
	var p0: Dictionary = Physics.propagate_state(Physics.make_state(r, v), 0.0)
	_ok(bool(p0.get("ok", false)), "propagate 0s ok")
	_eq(int(p0.get("steps", -1)), 0, "propagate 0s steps=0")
	var s0: Dictionary = Physics.as_state(p0.get("state", {}))
	_near((s0["r"] - r).length(), 0.0, 1.0e-12, "0s 位置不变")
	var batch: Array = Physics.propagate_states([Physics.make_state(r, v),
		Physics.make_state(r + Vector3(10, 0, 0), v)], 60.0)
	_eq(batch.size(), 2, "propagate_states 长度")
	for item in batch:
		_ok(bool((item as Dictionary).get("ok", false)), "批量传播 ok")
	var p2: Dictionary = Physics.propagate_state(Physics.make_state(r, v_moving), 60.0)
	var s2: Dictionary = Physics.as_state(p2.get("state", {}))
	_near((s2["r"] - s1["r"]).length(), 0.0, 1.0e-9, "传播确定性")
	var fwd: Dictionary = Physics.propagate_state(Physics.make_state(r, v), 300.0)
	_ok(bool(fwd.get("ok", false)), "前进 300s ok")
	var sf: Dictionary = Physics.as_state(fwd.get("state", {}))
	var back: Dictionary = Physics.propagate_state(Physics.make_state(sf["r"], sf["v"]), -300.0)
	_ok(bool(back.get("ok", false)), "反向传播 ok")
	var sb: Dictionary = Physics.as_state(back.get("state", {}))
	_ok((sb["r"] - r).length() < 5.0, "RK4 往返位置近似", "err=%.3f km" % (sb["r"] - r).length())
	var bad: Dictionary = Physics.propagate_state({"r": [NAN, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}, 60.0)
	_ok(not bool(bad.get("ok", true)), "非有限初值拒绝")
	_ok(_finite_num(p1.get("energy", NAN)), "能量代理有限")
	_data_line("rk4", "60s steps=%d jacobi_drift=%.8f roundtrip_err=%.4f km" % [
		int(p1.get("steps", 0)), float(p1.get("jacobi_drift", 0.0)),
		(sb["r"] - r).length()])

# ═══════════════════════════════════════════════════════════════════
# 4. Lambert 求解
# ═══════════════════════════════════════════════════════════════════

func _test_lambert() -> void:
	_section_begin("4 Lambert / 脉冲")
	var src: Dictionary = Physics.as_state(Planner.l4_port_state())
	var tgt: Dictionary = Physics.as_state(Planner.l1_port_state())
	var src_eci: Dictionary = Physics.bary_rot_to_earth_eci(src, 0.0)
	var tgt_eci: Dictionary = Physics.bary_rot_to_earth_eci(tgt, 6.0 * 86400.0)
	var lam: Dictionary = Planner.lambert(src_eci["r"], tgt_eci["r"], 6.0 * 86400.0,
		Physics.MU_EARTH_KM3_S2, true)
	_ok(bool(lam.get("ok", false)), "Lambert prograde ok", String(lam.get("reason", "")))
	if bool(lam.get("ok", false)):
		_ok(lam.get("v1") is Vector3, "Lambert v1 类型")
		_ok(lam.get("v2") is Vector3, "Lambert v2 类型")
		_ok(Physics.is_finite_vec(lam["v1"]), "v1 有限")
		_ok(Physics.is_finite_vec(lam["v2"]), "v2 有限")
		var dnu := float(lam.get("dnu_deg", -1.0))
		_ok(dnu > 0.0 and dnu < 360.0, "转移角 (0,360)", "%.3f°" % dnu)
		_ok(_finite_num(lam.get("z", NAN)), "Lambert z 有限")
		_ok(_finite_num(lam.get("f", NAN)) and _finite_num(lam.get("g", NAN))
			and _finite_num(lam.get("gdot", NAN)), "f/g/gdot 有限")
		_ok(absf(float(lam.get("g", 0.0))) > 1.0e-9, "g 非奇异")
		var seed: Dictionary = Physics.earth_eci_to_bary_rot(
			Physics.make_state(src_eci["r"], lam["v1"]), 0.0)
		_ok(_vec_like_finite(seed.get("v")), "Lambert v1 可转旋转系")
		var seed2: Dictionary = Physics.earth_eci_to_bary_rot(
			Physics.make_state(src_eci["r"], lam["v1"]), 0.0)
		var vel2: Vector3 = Physics.to_vec3(seed2.get("v", []))
		_near((Physics.to_vec3(seed.get("v", [])) - vel2).length(), 0.0, 1.0e-12,
			"Lambert 种子确定性")
	var lam_r: Dictionary = Planner.lambert(src_eci["r"], tgt_eci["r"],
		6.0 * 86400.0, Physics.MU_EARTH_KM3_S2, false)
	_ok(bool(lam_r.get("ok", false)), "Lambert retrograde 分支 ok")
	_ok(not bool(Planner.lambert(src_eci["r"], tgt_eci["r"], 0.0,
		Physics.MU_EARTH_KM3_S2, true).get("ok", true)), "tof=0 拒绝")
	_ok(not bool(Planner.lambert(src_eci["r"], src_eci["r"], 86400.0,
		Physics.MU_EARTH_KM3_S2, true).get("ok", true)), "同点几何拒绝")
	_ok(not bool(Planner.lambert(Vector3.ZERO, tgt_eci["r"], 86400.0,
		Physics.MU_EARTH_KM3_S2, true).get("ok", true)), "零半径拒绝")
	_data_line("lambert", "dnu=%.3f° r1=%.1f r2=%.1f" % [
		float(lam.get("dnu_deg", 0.0)), float(lam.get("r1_km", 0.0)),
		float(lam.get("r2_km", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 5. 转移方案
# ═══════════════════════════════════════════════════════════════════

func _test_plan() -> Dictionary:
	_section_begin("5 转移方案")
	var plan: Dictionary = Planner.plan()
	_ok(bool(plan.get("ok", false)), "plan ok", String(plan.get("reason", "")))
	_eq(String(plan.get("schema", "")), "v17_transfer_l4_l1.v1", "plan schema")
	_eq(String(plan.get("scenario_id", "")), "transit_l4_l1", "scenario_id")
	_eq(plan.get("reason", "x"), "", "无失败 reason")
	var frame: Dictionary = plan.get("frame", {})
	_eq(String(frame.get("inertial", "")), "earth_eci", "frame.inertial")
	_eq(String(frame.get("rotating", "")), "bary_rot", "frame.rotating")
	var source: Dictionary = plan.get("source", {})
	var target: Dictionary = plan.get("target", {})
	_eq(String(source.get("port_id", "")), "L4-02 Hammer", "source port")
	_eq(String(source.get("lpoint", "")), "L4", "source lpoint")
	_eq(String(target.get("port_id", "")), "L1-Meridian-05", "target port")
	_eq(String(target.get("lpoint", "")), "L1", "target lpoint")
	_ok(_arr3_finite(source.get("pos_rot_km", [])), "source pos 有限")
	_ok(_arr3_finite(target.get("pos_rot_km", [])), "target pos 有限")
	_ok(float(source.get("earth_distance_km", 0.0)) > 380000.0, "source 地心距")
	_ok(float(target.get("earth_distance_km", 0.0)) > 320000.0, "target 地心距")
	var transfer: Dictionary = plan.get("transfer", {})
	_eq(String(transfer.get("method", "")), "lambert_seed_cr3bp_shooting", "method")
	var tof_days := float(transfer.get("tof_days", -1.0))
	var tof_s := float(transfer.get("tof_s", -1.0))
	_ok(tof_days >= 1.0 and tof_days <= 15.0, "TOF 在时间窗", "%.2f days" % tof_days)
	_near(tof_s, tof_days * 86400.0, 1.0e-3, "tof_s = days*86400")
	_ok(tof_days in [3.0, 4.0, 5.0, 6.0], "TOF 来自候选", "%.1f" % tof_days)
	var lam: Dictionary = transfer.get("lambert", {})
	_ok(bool(lam.get("ok", false)), "Lambert 种子 ok")
	_ok(float(lam.get("dnu_deg", -1.0)) > 0.0, "Lambert 转移角>0")
	var shoot: Dictionary = transfer.get("shooting", {})
	_ok(int(shoot.get("iterations", 0)) >= 1, "打靶迭代≥1")
	_ok(bool(shoot.get("converged", false)), "打靶收敛")
	_ok(float(shoot.get("error_km", 99999.0)) <= 3000.0, "打靶误差≤3000km",
		"%.3f km" % float(shoot.get("error_km", 0.0)))
	_ok(_all_arrays_finite(transfer.get("depart_state_rot", {})), "depart 状态有限")
	_ok(_all_arrays_finite(transfer.get("arrival_state_rot", {})), "arrival 状态有限")
	var dep_mps := float(transfer.get("depart_dv_mps", -1.0))
	var arr_mps := float(transfer.get("arrival_dv_mps", -1.0))
	var mcc_mps := float(transfer.get("mcc_dv_mps", -1.0))
	var total_mps := float(transfer.get("total_dv_mps", -1.0))
	_ok(dep_mps > 0.0 and dep_mps < 5000.0, "departure Δv 合理", "%.1f m/s" % dep_mps)
	_ok(arr_mps > 0.0 and arr_mps < 5000.0, "arrival Δv 合理", "%.1f m/s" % arr_mps)
	_ok(mcc_mps >= 0.0, "MCC Δv≥0", "%.3f m/s" % mcc_mps)
	_near(total_mps, dep_mps + arr_mps + mcc_mps, 1.0e-6, "total Δv = 分解和")
	_ok(total_mps < 10000.0, "总 Δv < 10 km/s", "%.1f m/s" % total_mps)
	_ok(int(transfer.get("candidate_count", 0)) > 0, "候选数>0")
	_ok(transfer.get("mcc") is Dictionary, "mcc 字段")
	var mcc: Dictionary = transfer.get("mcc", {})
	_ok(mcc.has("applied"), "mcc.applied 字段")
	_ok(mcc.has("dv_mps"), "mcc.dv_mps 字段")
	var arrival: Dictionary = plan.get("arrival", {})
	_ok(arrival.has("radius_km") and arrival.has("relative_speed_kmps")
		and arrival.has("gate_radius_km") and arrival.has("gate_speed_kmps")
		and arrival.has("time_window_ok") and arrival.has("ok"), "arrival 字段齐全")
	_ok(float(arrival.get("radius_km", 99999.0)) <= float(arrival.get("gate_radius_km", -1.0)),
		"入轨半径达标", "%.3f / %.1f km" % [float(arrival.get("radius_km", 0.0)),
		float(arrival.get("gate_radius_km", 0.0))])
	_ok(float(arrival.get("relative_speed_kmps", 999.0)) <= float(arrival.get("gate_speed_kmps", -1.0)),
		"入轨相对速度达标", "%.3f / %.3f km/s" % [float(arrival.get("relative_speed_kmps", 0.0)),
		float(arrival.get("gate_speed_kmps", 0.0))])
	_eq(bool(arrival.get("time_window_ok", false)), true, "时间窗达标")
	_eq(bool(arrival.get("ok", false)), true, "arrival.ok")
	var budget: Dictionary = plan.get("budget", {})
	_near(float(budget.get("depart_dv_mps", 0.0)), dep_mps, 1.0e-6, "budget.depart")
	_near(float(budget.get("arrival_dv_mps", 0.0)), arr_mps, 1.0e-6, "budget.arrival")
	_near(float(budget.get("mcc_dv_mps", 0.0)), mcc_mps, 1.0e-6, "budget.mcc")
	_near(float(budget.get("total_dv_mps", 0.0)), total_mps, 1.0e-6, "budget.total")
	_eq((plan.get("errors", []) as Array).size(), 0, "errors 空")
	_ok(plan.get("warnings") is Array, "warnings 数组")
	_data_line("plan", "TOF=%.2fd Δv=%.1fm/s（dep %.1f + arr %.1f + mcc %.2f）候选=%d 入轨=%.3fkm/%.3fkm/s" % [
		tof_days, total_mps, dep_mps, arr_mps, mcc_mps, int(transfer.get("candidate_count", 0)),
		float(arrival.get("radius_km", 0.0)), float(arrival.get("relative_speed_kmps", 0.0))])
	return plan

func _test_timeline(plan: Dictionary) -> void:
	_section_begin("6 时间线")
	var timeline: Array = plan.get("timeline", [])
	_eq(timeline.size(), 11, "时间线 11 个采样")
	_ok(timeline.size() >= 2, "时间线至少 2 点")
	if timeline.is_empty():
		return
	var tof_s := float((plan.get("transfer", {}) as Dictionary).get("tof_s", 0.0))
	var first: Dictionary = timeline[0]
	var last: Dictionary = timeline[timeline.size() - 1]
	_near(float(first.get("t_s", -1.0)), 0.0, 1.0e-9, "首点 t=0")
	_near(float(last.get("t_s", -1.0)), tof_s, 1.0, "末点 t=TOF")
	var prev_t := -1.0
	for i in range(timeline.size()):
		var row: Dictionary = timeline[i]
		_ok(String(row.get("schema", "")) == "v17_transfer_timeline.v1",
			"row %d schema" % i)
		_ok(_finite_num(row.get("t_s", NAN)), "row %d t_s 有限" % i)
		_ok(float(row.get("t_days", -1.0)) >= 0.0, "row %d t_days>=0" % i)
		_near(float(row.get("t_days", 0.0)), float(row.get("t_s", 0.0)) / 86400.0,
			1.0e-9, "row %d t_days 换算" % i)
		_ok(_arr3_finite(row.get("pos_rot_km", [])), "row %d pos 有限" % i)
		_ok(_arr3_finite(row.get("vel_rot_kmps", [])), "row %d vel 有限" % i)
		_ok(_finite_num(row.get("range_to_target_km", NAN)), "row %d range 有限" % i)
		_ok(_finite_num(row.get("alt_km", NAN)), "row %d alt 有限" % i)
		_ok(float(row.get("range_to_target_km", -1.0)) >= 0.0, "row %d range>=0" % i)
		_near(float(row.get("error_km", -1.0)), float(row.get("range_to_target_km", -2.0)),
			1.0e-9, "row %d error=range" % i)
		var t := float(row.get("t_s", 0.0))
		if i > 0:
			_ok(t > prev_t, "row %d 时间单调" % i)
		prev_t = t
	_near(float(last.get("range_to_target_km", 99999.0)),
		float((plan.get("arrival", {}) as Dictionary).get("radius_km", -1.0)),
		1.0e-3, "末点范围=入轨半径")
	_ok(float(first.get("range_to_target_km", 0.0)) > 100000.0, "首点距目标远")
	_ok(float(last.get("range_to_target_km", 1.0e9)) < 3000.0, "末点到达 L1 附近")
	_data_line("timeline", "points=%d t=[0, %.1fs] 首距=%.1fkm 末距=%.3fkm" % [
		timeline.size(), tof_s, float(first.get("range_to_target_km", 0.0)),
		float(last.get("range_to_target_km", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 7. 舰队
# ═══════════════════════════════════════════════════════════════════

func _test_fleet(plan: Dictionary) -> void:
	_section_begin("7 舰队")
	var fleet: Array = plan.get("fleet", [])
	_eq(fleet.size(), 5, "舰队 5 舰")
	var expected_ids := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
	var expected_batches := ["1000", "1001", "1002", "1003", "1004"]
	var gate_radius := float((plan.get("arrival", {}) as Dictionary).get("gate_radius_km", 0.0))
	var seen := {}
	for i in range(fleet.size()):
		var s: Dictionary = fleet[i]
		var sid := String(s.get("id", ""))
		_ok(sid != "", "fleet[%d] id 非空" % i)
		_ok(not seen.has(sid), "fleet id 唯一: " + sid)
		seen[sid] = true
		_ok(sid in expected_ids, "fleet %s 在预期舰队" % sid)
		_ok(String(s.get("batch", "")) in expected_batches, "fleet %s batch" % sid)
		_ok(String(s.get("role", "")) != "", "fleet %s role" % sid)
		_ok(_arr3_finite(s.get("offset_km", [])), "fleet %s offset" % sid)
		_ok(_arr3_finite(s.get("offset_kmps", [])), "fleet %s offset_v" % sid)
		_ok(_all_arrays_finite(s.get("initial_state_rot", {})), "fleet %s initial 有限" % sid)
		_ok(_all_arrays_finite(s.get("depart_state_rot", {})), "fleet %s depart 有限" % sid)
		var arrival: Dictionary = s.get("arrival_state_rot", {})
		_ok(bool(arrival.get("ok", false)), "fleet %s arrival ok" % sid)
		_ok(_arr3_finite(arrival.get("r", [])), "fleet %s arrival.r 有限" % sid)
		_ok(_arr3_finite(arrival.get("v", [])), "fleet %s arrival.v 有限" % sid)
		var err := float(s.get("arrival_error_km", -1.0))
		var spd := float(s.get("arrival_speed_kmps", -1.0))
		_ok(err >= 0.0, "fleet %s 到达误差记录" % sid, "%.1f km" % err)
		_ok(spd >= 0.0, "fleet %s 到达速度记录" % sid, "%.3f km/s" % spd)
		_ok(err <= gate_radius, "fleet %s 到达误差达标" % sid, "%.1f / %.1f km" % [err, gate_radius])
		_ok(bool(s.get("within_gate", false)), "fleet %s within_gate" % sid)
		for j in range(expected_ids.size()):
			if sid == expected_ids[j]:
				_ok(String(s.get("batch", "")) == expected_batches[j],
					"fleet %s batch 匹配" % sid)
	if fleet.size() > 0:
		var flag: Dictionary = fleet[0]
		_eq(String(flag.get("id", "")), "apsis", "首位=旗舰 apsis")
		_near(Physics.to_vec3(flag.get("offset_km", [])).length(), 0.0, 1.0e-9,
			"旗舰 offset=0")
		_near(float(flag.get("arrival_error_km", -1.0)),
			float((plan.get("arrival", {}) as Dictionary).get("radius_km", -2.0)),
			1.0e-3, "旗舰到达误差=全局到达半径")
	_ok(JSON.stringify(fleet).length() > 500, "fleet JSON 可序列化")
	_ok(JSON.parse_string(JSON.stringify(fleet)) is Array, "fleet JSON 回读")
	_data_line("fleet", "ships=%d errs=%s" % [fleet.size(),
		str(fleet.map(func(s): return "%.0fkm" % float(s.get("arrival_error_km", 0.0))))])

# ═══════════════════════════════════════════════════════════════════
# 8. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism(plan: Dictionary) -> void:
	_section_begin("8 JSON / 确定性")
	var js := JSON.stringify(plan)
	_ok(js.length() > 5000, "plan JSON 较大", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "plan JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq(String(pd.get("schema", "")), "v17_transfer_l4_l1.v1", "回读 schema")
		_ok(pd.get("timeline") is Array, "回读 timeline")
		_ok(pd.get("fleet") is Array, "回读 fleet")
		_ok(pd.get("transfer") is Dictionary, "回读 transfer")
		_ok(pd.get("arrival") is Dictionary, "回读 arrival")
		_ok(pd.get("budget") is Dictionary, "回读 budget")
		_ok((pd.get("timeline", []) as Array).size() == 11, "回读 timeline 11 点")
	# 确定性：同 opts 两个实例 → JSON 完全一致
	var plan_a: Dictionary = Planner.plan({"tof_days": [6.0]})
	var plan_b: Dictionary = Planner.plan({"tof_days": [6.0]})
	var ja := JSON.stringify(plan_a)
	var jb := JSON.stringify(plan_b)
	_ok(ja.length() > 1000, "单 TOF plan JSON", "len=%d" % ja.length())
	_ok(ja == jb, "两次规划 JSON 完全一致（确定性）")
	_ok(bool(plan_a.get("ok", false)), "单 TOF plan ok")
	_ok(bool(plan_b.get("ok", false)), "单 TOF plan2 ok")
	_near(float((plan_a.get("transfer", {}) as Dictionary).get("tof_days", 0.0)),
		6.0, 1.0e-9, "单 TOF 固定 6 天")
	var json2 := Planner.to_json({"tof_days": [6.0]})
	_ok(json2.length() > 1000, "to_json 输出", "len=%d" % json2.length())
	_ok(JSON.parse_string(json2) is Dictionary, "to_json 可解析")
	var parsed2 = JSON.parse_string(json2)
	if parsed2 is Dictionary:
		_eq(String((parsed2 as Dictionary).get("schema", "")), "v17_transfer_l4_l1.v1",
			"to_json schema")
	_ok(int((plan.get("transfer", {}) as Dictionary).get("candidate_count", 0)) >
		int((plan_a.get("transfer", {}) as Dictionary).get("candidate_count", 0)),
		"多 TOF 候选数 > 单 TOF")
	_data_line("json", "plan_json=%d det_json=%d" % [js.length(), ja.length()])

# ═══════════════════════════════════════════════════════════════════
# 9. 边界
# ═══════════════════════════════════════════════════════════════════

func _test_edges() -> void:
	_section_begin("9 边界")
	var bad1: Dictionary = Planner.plan({"tof_days": []})
	_eq(bool(bad1.get("ok", true)), false, "空 TOF 候选拒绝")
	_eq(String(bad1.get("reason", "")), "invalid_tof_days", "空 TOF reason")
	var bad2: Dictionary = Planner.plan({"tof_days": [-1.0]})
	_eq(bool(bad2.get("ok", true)), false, "负 TOF 拒绝")
	var bad3: Dictionary = Planner.plan({"tof_days": [6.0], "arrival_radius_gate_km": 0.000001})
	_eq(bool(bad3.get("ok", true)), false, "不可达门限 → ok=false（不伪造）")
	_eq(String(bad3.get("reason", "")), "arrival_gate_failed", "失败 reason")
	var no_mcc: Dictionary = Planner.plan({"tof_days": [6.0], "include_mcc": false})
	_ok(bool(no_mcc.get("ok", false)), "include_mcc=false 仍可规划")
	_eq(bool(((no_mcc.get("transfer", {}) as Dictionary).get("mcc", {}) as Dictionary).get("applied", true)),
		false, "no_mcc 时 mcc.applied=false")
	_eq(String(((no_mcc.get("transfer", {}) as Dictionary).get("mcc", {}) as Dictionary).get("reason", "")),
		"not_requested", "no_mcc reason")
	var bad_lam: Dictionary = Planner.lambert(Vector3.ZERO, Vector3.ZERO, -1.0,
		Physics.MU_EARTH_KM3_S2, true)
	_eq(bool(bad_lam.get("ok", true)), false, "Lambert 非法输入拒绝")
	var bad_prop: Dictionary = Physics.propagate_state({"r": [NAN, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}, 60.0)
	_eq(bool(bad_prop.get("ok", true)), false, "非法状态传播拒绝")
	_ok(true, "边界测试无崩溃")
	_data_line("edges", "empty/negative tof、不可达门限、no_mcc、非法 Lambert/传播均安全拒绝")
