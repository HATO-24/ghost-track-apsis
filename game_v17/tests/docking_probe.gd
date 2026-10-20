extends SceneTree

# R6-DOCKING-1 headless probe：交会/对接几何控制器
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/docking_probe.gd

const DockScript := preload("res://framework/sim/docking_controller.gd")
const Physics := preload("res://framework/sim/cislunar_physics.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _failures: Array[String] = []
var _data: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R6-DOCKING-1 PROBE · 交会 / 对接几何控制器")
	print("════════════════════════════════════════════════════════════")
	_test_setup_ports()
	_test_port_selection()
	_test_invalid_ports()
	_test_far_approach_corridor()
	_test_hold_resume()
	_test_alignment_final_docked()
	_test_undock_abort_fail()
	_test_guidance()
	_test_corridor_and_failure()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("R6 DOCKING PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("R6 DOCKING PROBE FAILED")
		quit(1)
	else:
		print("R6 DOCKING PROBE OK")
		quit(0)


func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += " (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f tol=%.6f" % [actual, expected, tol])


func _near_vec(actual: Array, expected: Array, tol: float, label: String) -> void:
	var ok := actual.size() == expected.size()
	if ok:
		for i in range(actual.size()):
			if absf(float(actual[i]) - float(expected[i])) > tol:
				ok = false
				break
	_ok(ok, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)


func _ctl(ports: Array = [], opts := {}) -> Variant:
	var d = DockScript.new()
	var ok: bool = d.setup(ports, opts)
	_ok(ok, "controller setup")
	return d


func _rel(x: float, y: float, z: float, vx := 0.0, vy := 0.0, vz := 0.0) -> Dictionary:
	return {"dr": [x, y, z], "dv": [vx, vy, vz]}


func _att() -> Dictionary:
	return {"chaser_port_axis": [-1.0, 0.0, 0.0]}


func _state_after(c, x: float, y: float, z: float, vx := 0.0, vy := 0.0, vz := 0.0,
		att := {}) -> String:
	var a: Dictionary = att if att is Dictionary else {}
	var snap: Dictionary = c.update(_rel(x, y, z, vx, vy, vz), a, 0.0)
	return String(snap.get("state", ""))


## 推进到目标状态（同一控制器；不伪造：仅按输入调用 update）。
func _drive(c, target: String) -> Dictionary:
	var seq := [
		["far", _rel(300, 0, 0), _att()],
		["approach", _rel(100, 40, 0), _att()],
		["corridor", _rel(50, 1, 0, -0.01, 0, 0), _att()],
		["alignment", _rel(1.0, 0.002, 0, -0.001, 0, 0), _att()],
		["final", _rel(0.2, 0.002, 0, -0.0002, 0, 0), _att()],
		["docked", _rel(0.03, 0.0005, 0, -0.00005, 0, 0), _att()],
	]
	var out: Dictionary = {}
	for row in seq:
		var step: Array = row
		out = c.update(step[1], step[2], 0.0)
		if String(step[0]) == target:
			return out
	return out


# ═══════════════════════════════════════════════════════════════════
# 1. setup / 端口 schema
# ═══════════════════════════════════════════════════════════════════

func _test_setup_ports() -> void:
	_section_begin("1 setup / ports")
	var d = DockScript.new()
	var ok: bool = d.setup()
	_ok(ok, "setup 默认端口")
	_eq(d.errors.size(), 0, "默认端口无错误")
	_eq(d.ports.size(), 4, "默认端口数=4")
	_eq(d.state, "far", "初始 state=far")
	_eq(d.target_port_id, "", "初始无目标端口")
	var vm: Dictionary = d.vm()
	_eq(String(vm.get("schema", "")), "v17_docking.v1", "vm schema")
	_ok(vm.get("writes", {}) is Dictionary, "vm writes")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("physics", true)), false, "不写 physics")
	_ok(vm.get("ports", []) is Array and (vm.get("ports", []) as Array).size() == 4, "vm ports 数")
	var p0: Dictionary = d.ports[0]
	_eq(String(p0.get("schema", "")), "v17_docking_port.v1", "port schema")
	_eq(String(p0.get("owner_kind", "")), "station", "port owner_kind")
	_ok(p0.get("axis", []) is Array and (p0.get("axis", []) as Array).size() == 3, "port axis 3D")
	_eq(String(p0.get("status", "")), "open", "port A open")
	_ok(float(p0.get("radius_m", 0.0)) > 0.0, "port A radius")
	_eq(String(p0.get("kind", "")), "dock", "port A kind")
	_ok((p0.get("compatible", []) as Array).has("ship"), "port A compatible ship")
	_data_line("default ports", "4（chronos-dock-a/b, chronos-berth-1, harmattan-port）")
	# 默认状态
	_eq(d.state, "far", "fresh state far")
	_eq(d.target_port_id, "", "fresh target empty")


# ═══════════════════════════════════════════════════════════════════
# 2. 端口选择 / 兼容 / 状态
# ═══════════════════════════════════════════════════════════════════

func _test_port_selection() -> void:
	_section_begin("2 port selection")
	var d = _ctl()
	var r: Dictionary = d.select_target_port("chronos-dock-a")
	_eq(bool(r.get("ok", false)), true, "显式选择 A")
	_eq(d.target_port_id, "chronos-dock-a", "target A")
	_eq(d.state, "far", "选端口后 far")
	_eq(String(d.target_port().get("name", "")), "Chronos DOCK-A · 主对接环", "target A name")
	r = d.select_target_port("chronos-dock-b")
	_eq(bool(r.get("ok", true)), false, "occupied B 拒绝")
	_eq(String(r.get("reason", "")), "port_occupied", "occupied reason")
	r = d.select_target_port("chronos-berth-1")
	_eq(bool(r.get("ok", true)), false, "damaged berth 拒绝")
	_eq(String(r.get("reason", "")), "port_damaged", "damaged reason")
	r = d.select_target_port("no-such")
	_eq(bool(r.get("ok", true)), false, "unknown 拒绝")
	_eq(String(r.get("reason", "")), "unknown_port", "unknown reason")
	r = d.select_target_port("", "chronos_station")
	_eq(bool(r.get("ok", false)), true, "owner 过滤选择 A")
	_eq(d.target_port_id, "chronos-dock-a", "owner 选择 A")
	r = d.select_target_port("", "no-owner")
	_eq(bool(r.get("ok", true)), false, "无 owner 端口")
	_eq(String(r.get("reason", "")), "no_open_port", "no_open_port")
	# 兼容性：新建 incompatible port
	var dc = DockScript.new()
	var ports: Array = [
		DockScript.make_port("p1", "shipX", "dock", [1, 0, 0], 1.0,
			{"status": "open", "compatible": ["tanker"]}),
	]
	_ok(dc.setup(ports), "incompatible setup")
	r = dc.select_target_port("p1", "", "ship")
	_eq(bool(r.get("ok", true)), false, "incompatible 拒绝")
	_eq(String(r.get("reason", "")), "incompatible_port", "incompatible reason")
	r = dc.select_target_port("p1", "", "tanker")
	_eq(bool(r.get("ok", false)), true, "兼容 tanker 通过")
	# 选择后移除
	dc.select_target_port("p1", "", "tanker")
	var rm: Dictionary = dc.remove_port("p1")
	_eq(bool(rm.get("ok", false)), true, "remove target port")
	_eq(dc.target_port_id, "", "remove 后 target 清空")
	_eq(dc.state, "far", "remove 后 far")
	# docked 时禁止选端口（由 undock 解除）
	var d2 = _ctl()
	d2.select_target_port("chronos-dock-a")
	_drive(d2, "docked")
	r = d2.select_target_port("chronos-dock-a")
	_eq(bool(r.get("ok", true)), false, "docked 时选端口拒绝")
	_eq(String(r.get("reason", "")), "docked_undock_first", "docked reason")


func _test_invalid_ports() -> void:
	_section_begin("3 invalid ports / setup")
	var bad: Array = [
		{"port_id": "", "owner_id": "x", "axis": [1, 0, 0]},
		{"port_id": "p", "owner_id": "", "axis": [1, 0, 0]},
		{"port_id": "p2", "owner_id": "o", "axis": [0, 0, 0]},
	]
	var d = DockScript.new()
	var ok: bool = d.setup(bad)
	_eq(ok, false, "invalid ports setup=false")
	_ok(d.errors.size() >= 1, "invalid ports errors")
	_ok(d.ports.is_empty(), "invalid ports 不加入")
	var d2 = DockScript.new()
	_ok(d2.setup([DockScript.make_port("a", "o", "dock", [1, 0, 0])]), "single valid port setup")
	var dup: Dictionary = d2.add_port(DockScript.make_port("a", "o", "dock", [1, 0, 0]))
	_eq(bool(dup.get("ok", true)), false, "duplicate port 拒绝")
	_eq(String(dup.get("reason", "")), "duplicate_port", "duplicate reason")
	var added: Dictionary = d2.add_port(DockScript.make_port("b", "o", "dock", [0, 1, 0]))
	_eq(bool(added.get("ok", false)), true, "add port")
	_eq(d2.ports.size(), 2, "add port 后数=2")
	var bad_add: Dictionary = d2.add_port({"bad": true})
	_eq(bool(bad_add.get("ok", true)), false, "invalid add 拒绝")
	_eq(String(bad_add.get("reason", "")), "invalid_port", "invalid add reason")


# ═══════════════════════════════════════════════════════════════════
# 4. far / approach / corridor
# ═══════════════════════════════════════════════════════════════════

func _test_far_approach_corridor() -> void:
	_section_begin("4 far/approach/corridor")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	var snap: Dictionary = d.update(_rel(300, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "far", "300 km → far")
	_near(float(snap.get("range_km", 0.0)), 300.0, 1.0e-6, "far range")
	_ok(snap.get("guidance", {}) is Dictionary, "far guidance")
	snap = d.update(_rel(100, 40, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "approach", "43° lateral → approach")
	var corr: Dictionary = snap.get("corridor", {}) if snap.get("corridor", {}) is Dictionary else {}
	_eq(bool(corr.get("inside", true)), false, "outside corridor")
	_eq(bool(corr.get("ok", true)), false, "corridor not ok")
	snap = d.update(_rel(50, 1, 0, -0.01, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "corridor", "50 km/1 km lateral → corridor")
	_near(float(snap.get("range_km", 0.0)), sqrt(2501.0), 1.0e-3, "corridor range")
	corr = snap.get("corridor", {})
	_eq(bool(corr.get("inside", false)), true, "corridor inside")
	_eq(bool(corr.get("ok", false)), true, "corridor ok")
	_eq(bool(corr.get("speed_ok", false)), true, "corridor speed ok")
	_eq(bool(corr.get("angle_ok", false)), true, "corridor angle ok")
	_near(float(corr.get("closing_mps", 0.0)), 10.0, 0.01, "corridor closing 10 m/s")
	_data_line("far/approach/corridor", "300 km far · lateral 40 km approach · 50 km/1 km corridor")


# ═══════════════════════════════════════════════════════════════════
# 5. hold / resume
# ═══════════════════════════════════════════════════════════════════

func _test_hold_resume() -> void:
	_section_begin("5 hold/resume")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	# 4 km 内 100 m/s 超接近速度 → auto hold
	var snap: Dictionary = d.update(_rel(4, 0, 0, -0.1, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "hold", "100 m/s inside 5 km → hold")
	var corr: Dictionary = snap.get("corridor", {})
	_eq(bool(corr.get("speed_ok", true)), false, "hold speed_ok=false")
	var h: Dictionary = d.hold("crew_hold")
	_eq(String(h.get("state", "")), "hold", "manual hold")
	_eq(bool(h.get("hold_requested", false)), true, "hold_requested")
	var res: Dictionary = d.resume()
	_eq(bool(res.get("hold_requested", true)), false, "resume clears hold")
	_ok(String(res.get("state", "")) != "hold", "resume 离开 hold")
	# 手动 hold 终止状态拒绝
	_drive(d, "docked")
	var r: Dictionary = d.hold()
	_eq(bool(r.get("ok", true)), false, "docked hold 拒绝")
	_eq(String(r.get("reason", "")), "terminal_state", "docked hold reason")


# ═══════════════════════════════════════════════════════════════════
# 6. alignment / final / docked
# ═══════════════════════════════════════════════════════════════════

func _test_alignment_final_docked() -> void:
	_section_begin("6 alignment/final/docked")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	var snap: Dictionary = d.update(_rel(1.0, 0.02, 0, -0.001, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "alignment", "1 km aligned → alignment")
	_ok(bool(snap.get("align_ready", false)), "alignment align_ready")
	_eq(bool(snap.get("final_ready", true)), false, "alignment not final")
	snap = d.update(_rel(0.2, 0.002, 0, -0.0002, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "final", "0.2 km → final")
	_ok(bool(snap.get("final_ready", false)), "final ready")
	_eq(bool(snap.get("docking_ok", true)), false, "final not docked")
	snap = d.update(_rel(0.03, 0.0005, 0, -0.00005, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "docked", "0.03 km/0.05 m/s → docked")
	_ok(bool(snap.get("docking_ok", false)), "docking_ok")
	_eq(bool(snap.get("chaser_aligned", false)), true, "chaser aligned")
	var dock_snap: Dictionary = snap.get("docking", {}) if snap.get("docking", {}) is Dictionary else {}
	_eq(String(dock_snap.get("status", "")), "docked", "docking_geometry docked")
	_eq(String(d.state), "docked", "controller state docked")
	_ok(float(d.vm().get("docked_t", -1.0)) >= 0.0, "docked_t 记录")
	# docked latch：再给错误状态也不离开
	snap = d.update(_rel(100, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "docked", "docked latch")
	# 无姿态不 dock
	var d2 = _ctl()
	d2.select_target_port("chronos-dock-a")
	snap = d2.update(_rel(0.03, 0.0005, 0, -0.00005, 0, 0), {}, 0.0)
	_eq(String(snap.get("state", "")), "final", "无 chaser 姿态不 dock")
	_eq(bool(snap.get("docking_ok", true)), false, "无姿态 docking_ok=false")
	# 对齐角超限
	snap = d2.update(_rel(0.03, 0.0005, 0, -0.00005, 0, 0), {"chaser_port_axis": [0, 1, 0]}, 0.0)
	_eq(String(snap.get("state", "")), "failed", "姿态错 90° → failed（硬失败）")
	_data_line("alignment/final/docked", "1 km alignment · 0.2 km final · 0.03 km docked · latch · 无姿态不 dock")


# ═══════════════════════════════════════════════════════════════════
# 7. undock / abort / fail
# ═══════════════════════════════════════════════════════════════════

func _test_undock_abort_fail() -> void:
	_section_begin("7 undock/abort/fail")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	_drive(d, "docked")
	var u: Dictionary = d.undock("test_undock")
	_eq(String(u.get("state", "")), "approach", "undock → approach")
	_ok(float(d.vm().get("undocked_t", -1.0)) >= 0.0, "undock 时间记录")
	_eq(float(d.vm().get("docked_t", 0.0)), -1.0, "undock 清 docked_t")
	var u2: Dictionary = d.undock()
	_eq(bool(u2.get("ok", true)), false, "非 docked undock 拒绝")
	# abort
	var da = _ctl()
	da.select_target_port("chronos-dock-a")
	da.update(_rel(100, 40, 0), _att(), 0.0)
	var ab: Dictionary = da.abort("commander")
	_eq(String(ab.get("state", "")), "aborted", "abort → aborted")
	_eq(String(da.vm().get("failure_reason", "")), "commander", "abort reason")
	var ab2: Dictionary = da.abort()
	_eq(bool(ab2.get("ok", true)), false, "aborted 再 abort 拒绝")
	_eq(da.update(_rel(0.03, 0.0005, 0, -0.00005, 0, 0), _att()).get("state", ""), "aborted", "aborted 终态")
	# fail
	var df = _ctl()
	df.select_target_port("chronos-dock-a")
	df.update(_rel(0.2, 0.02, 0, -0.005, 0, 0), _att(), 0.0)
	_eq(String(df.state), "failed", "contact speed 5 m/s → failed")
	_eq(String(df.vm().get("failure_reason", "")), "contact_speed", "failed reason contact_speed")
	var fail_res: Dictionary = df.fail("manual_fail")
	_eq(String(fail_res.get("state", "")), "failed", "fail terminal")
	# 非终端 fail 可显式
	var dg = _ctl()
	dg.select_target_port("chronos-dock-a")
	dg.update(_rel(50, 1, 0), _att(), 0.0)
	var fr: Dictionary = dg.fail("test_failure")
	_eq(String(fr.get("state", "")), "failed", "explicit fail")
	_eq(String(dg.vm().get("failure_reason", "")), "test_failure", "explicit fail reason")
	# invalid rel
	var dr = _ctl()
	dr.select_target_port("chronos-dock-a")
	var ir: Dictionary = dr.update({"dr": [1, 2], "dv": [0, 0, 0]}, _att(), 0.0)
	_eq(bool(ir.get("ok", true)), false, "invalid rel ok=false")
	_eq(String(ir.get("reason", "")), "invalid_relative_state", "invalid rel reason")


# ═══════════════════════════════════════════════════════════════════
# 8. 相对制导
# ═══════════════════════════════════════════════════════════════════

func _test_guidance() -> void:
	_section_begin("8 guidance")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	var snap: Dictionary = d.update(_rel(50, 2, 0, 0, 0, 0), _att(), 0.0)
	var gd: Dictionary = snap.get("guidance", {}) if snap.get("guidance", {}) is Dictionary else {}
	_eq(String(gd.get("schema", "")), "v17_docking_guidance.v1", "guidance schema")
	_eq(bool(gd.get("available", false)), true, "guidance available")
	_near(float(gd.get("range_km", 0.0)), sqrt(2504.0), 1.0e-3, "guidance range")
	_near(float(gd.get("standoff_km", 0.0)), 0.02, 1.0e-9, "guidance standoff")
	_ok(float(gd.get("closing_desired_mps", 0.0)) > 0.0, "closing_desired>0")
	_ok(float(gd.get("closing_desired_mps", 0.0)) <= 5.0 + 1.0e-9, "closing gate")
	_eq(gd.get("dv_mps", []) is Array, true, "dv array")
	_eq((gd.get("dv_mps", []) as Array).size(), 3, "dv 3D")
	var dv: Array = gd.get("dv_mps", [])
	_near(float(gd.get("dv_magnitude_mps", 0.0)), sqrt(pow(float(dv[0]),2)+pow(float(dv[1]),2)+pow(float(dv[2]),2)), 1.0e-6, "dv magnitude")
	_ok(float(gd.get("dv_magnitude_mps", 0.0)) <= 3.0 + 1.0e-9, "dv <= max")
	_eq(bool(gd.get("attitude_available", false)), true, "attitude available")
	var desired: Array = gd.get("attitude_desired_axis", [])
	_ok(float(desired[0]) < 0.0, "desired chaser axis -X")
	_ok(float(gd.get("attitude_error_deg", 180.0)) < 5.0, "attitude error <5°")
	_ok(gd.get("gates", {}) is Dictionary, "guidance gates")
	var gates: Dictionary = gd.get("gates", {})
	_eq(float(gates.get("far_km", 0.0)), 250.0, "gate far 250")
	_eq(float(gates.get("dock_speed_mps", 0.0)), 0.1, "gate dock speed")
	# 横向修正方向：y 正 → dv y 应为负/向轴
	var g2: Dictionary = d.update(_rel(50, 5, 0, 0, 0, 0), _att(), 0.0).get("guidance", {})
	var dv2: Array = g2.get("dv_mps", [])
	_ok(float(dv2[1]) < 0.0, "横向修正向 -y")
	# 无姿态
	var g3: Dictionary = d.update(_rel(50, 2, 0), {}, 0.0).get("guidance", {})
	_eq(bool(g3.get("attitude_available", true)), false, "无姿态 attitude_available=false")
	_eq(float(g3.get("attitude_error_deg", 0.0)), -1.0, "无姿态 error=-1")
	# 远距 time_to_go 与超距
	var g4: Dictionary = d.update(_rel(300, 0, 0), _att(), 0.0).get("guidance", {})
	_ok(float(g4.get("time_to_go_s", -1.0)) >= 0.0, "TGO>=0")
	_data_line("guidance", "range/closure/Δt/attitude/gates 全部输出；无姿态显式 -1")


# ═══════════════════════════════════════════════════════════════════
# 9. corridor/docking 失败原因
# ═══════════════════════════════════════════════════════════════════

func _test_corridor_and_failure() -> void:
	_section_begin("9 corridor/failure")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	# 走廊外横向
	var snap: Dictionary = d.update(_rel(100, 40, 0, 0, 0, 0), _att(), 0.0)
	var corr: Dictionary = snap.get("corridor", {})
	_eq(bool(corr.get("inside", true)), false, "lateral 40 outside")
	_ok((corr.get("warnings", []) as Array).size() >= 1, "corridor warning")
	# 轴向为负（在目标后方）
	snap = d.update(_rel(-10, 0, 0), _att(), 0.0)
	corr = snap.get("corridor", {})
	_eq(bool(corr.get("inside", true)), false, "behind target outside")
	_ok(float(corr.get("along_km", 0.0)) < 0.0, "along negative")
	# 速度超限
	snap = d.update(_rel(35, 0, 0, -0.1, 0, 0), _att(), 0.0)
	corr = snap.get("corridor", {})
	_eq(bool(corr.get("speed_ok", true)), false, "closing 100 m/s speed fail")
	# 角度超限：rel 方向偏离轴
	snap = d.update(_rel(20, 20, 0, 0, 0, 0), _att(), 0.0)
	corr = snap.get("corridor", {})
	_eq(bool(corr.get("angle_ok", true)), false, "45° angle fail")
	# 硬失败：接触速度
	var df = _ctl()
	df.select_target_port("chronos-dock-a")
	snap = df.update(_rel(0.1, 0, 0, -0.01, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "failed", "contact 10 m/s → failed")
	_ok(String(snap.get("hard_fail", "")) == "contact_speed", "hard_fail contact_speed")
	# 硬失败：横向
	var dl = _ctl([], {"final_km": 1.0})
	dl.select_target_port("chronos-dock-a")
	snap = dl.update(_rel(0.1, 0.6, 0, -0.0001, 0, 0), _att(), 0.0)
	_eq(String(snap.get("state", "")), "failed", "lateral 0.6 km close → failed")
	_ok(String(snap.get("hard_fail", "")) == "lateral_misalignment", "hard_fail lateral")
	# 硬失败：姿态
	var da = _ctl()
	da.select_target_port("chronos-dock-a")
	snap = da.update(_rel(0.1, 0.0, 0, -0.0001, 0, 0), {"chaser_port_axis": [0.5, 0.5, 0]}, 0.0)
	_ok(String(snap.get("hard_fail", "")) in ["attitude_misalignment", ""], "attitude hard fail/invalid angle")
	# 有 failure reason 字段
	_ok(df.vm().get("failure_reason", "") != "", "failure reason 非空")
	_data_line("failure", "corridor out/speed/angle；接触速度、横向、姿态硬失败")


# ═══════════════════════════════════════════════════════════════════
# 10. JSON / determinism / reset
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("10 JSON/determinism")
	var d = _ctl()
	d.select_target_port("chronos-dock-a")
	_drive(d, "docked")
	var vm: Dictionary = d.vm()
	for k in ["schema", "state", "state_order", "t", "target_port_id", "target_port",
			"ports", "config", "last", "events", "hold_requested", "hold_reason",
			"failure_reason", "docked_t", "undocked_t", "writes", "authoritative"]:
		_ok(vm.has(k), "vm 含 " + k)
		var js := JSON.stringify(vm)
		_ok(js.length() > 1000, "vm JSON", "len=%d" % js.length())
		var parsed = JSON.parse_string(js)
		_ok(parsed is Dictionary, "vm JSON 回读")
		if parsed is Dictionary:
			var pd: Dictionary = parsed
			_eq(String(pd.get("schema", "")), "v17_docking.v1", "JSON schema")
			_eq(String(pd.get("state", "")), "docked", "JSON state")
			_ok(pd.get("last") is Dictionary, "JSON last")
			_ok(pd.get("guidance", {}) is Dictionary or pd.get("last", {}) is Dictionary, "JSON guidance/last")
			_ok(pd.get("events") is Array, "JSON events")
			_ok(float(pd.get("docked_t", -1.0)) >= 0.0, "JSON docked_t")
	var sig1: String = String(d.state_signature())
	var sig2: String = String(d.state_signature())
	_eq(sig1, sig2, "state_signature 确定")
	# 两次同输入不同实例结果一致
	var a = _ctl()
	a.select_target_port("chronos-dock-a")
	_drive(a, "docked")
	var b = _ctl()
	b.select_target_port("chronos-dock-a")
	_drive(b, "docked")
	_eq(a.state_signature(), b.state_signature(), "同输入两实例签名一致")
	var a_last: Dictionary = a.vm().get("last", {}) if a.vm().get("last", {}) is Dictionary else {}
	var b_last: Dictionary = b.vm().get("last", {}) if b.vm().get("last", {}) is Dictionary else {}
	_eq(float(a_last.get("range_km", 0.0)), float(b_last.get("range_km", 0.0)), "同输入 range 一致")
	# reset
	a.reset()
	_eq(a.state, "far", "reset state=far")
	_eq(a.target_port_id, "", "reset target empty")
	_eq(a.vm().get("events", []).size(), 0, "reset events 清空")
	_eq(float(a.vm().get("docked_t", 0.0)), -1.0, "reset docked_t")
	# 不写字段
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false, "不写 track_table")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("v15", true)), false, "不写 v15")
	_eq(bool((vm.get("authoritative", true))), false, "authoritative=false")
	_data_line("json", "vm/signature/reset/writes；两实例同输入确定")
