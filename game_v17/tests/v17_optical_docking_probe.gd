extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-OPT-DOCK-BRIDGE-1 最小 probe：光学/IR + 对接接 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_optical_docking_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次，不做全量回归。
# ═══════════════════════════════════════════════════════════════════

const BridgeScript := preload("res://scripts/framework_bridge.gd")
const StateScript := preload("res://scripts/state.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R5-OPT-DOCK-BRIDGE-1 PROBE · 光学/IR + 对接（最小）")
	print("════════════════════════════════════════════════════════════")
	_test_boot()
	_test_optical_ir()
	_test_docking()
	_test_state_and_v15()
	_test_off_mode()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 OPTICAL DOCKING PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 OPTICAL DOCKING PROBE FAILED")
		quit(1)
	else:
		print("V17 OPTICAL DOCKING PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _clear_env() -> void:
	OS.set_environment("V17_OPTICAL_IR", "")
	OS.set_environment("V17_DOCKING", "")

func _set_off() -> void:
	OS.set_environment("V17_OPTICAL_IR", "off")
	OS.set_environment("V17_DOCKING", "off")

func _make_bridge():
	var br = BridgeScript.new()
	var ok: bool = br.boot()
	_ok(ok, "bridge.boot", str(br.errors))
	return br

func _make_state(br):
	var st = StateScript.new()
	if st.prelude_open:
		st.prelude_skip()
	st.framework = br
	st.fw_sync(0.0)
	return st

func _track_snapshot(st) -> Dictionary:
	var tr: Dictionary = st.tracks[st.selected] if not st.tracks.is_empty() else {}
	return {
		"r": str(tr.get("r", Vector3.ZERO)),
		"v": str(tr.get("v", Vector3.ZERO)),
		"level": int(tr.get("level", 0)),
		"identity": String(tr.get("identity", "")),
		"clock": float(st.clock),
		"count": st.tracks.size(),
	}

# ═══════════════════════════════════════════════════════════════════
# 1. boot
# ═══════════════════════════════════════════════════════════════════

func _test_boot() -> void:
	_section_begin("1 boot")
	_clear_env()
	var br = _make_bridge()
	# 光学/IR
	_eq(br.optical_ir_enabled, true, "默认 optical_ir_enabled")
	_eq(br.optical_ir_ready, true, "optical_ir_ready")
	_ok(br.optical_ir != null, "optical_ir 实例存在")
	var ov: Dictionary = br.optical_ir_view()
	for key in ["schema", "mode", "authoritative", "enabled", "t", "sensors",
			"channels", "by_status", "events", "warnings", "writes", "summary"]:
		_ok(ov.has(key), "optical view 含字段: " + key)
	_eq(String(ov.get("schema", "")), "optical_ir.v1", "optical schema")
	_eq(bool(ov.get("authoritative", true)), false, "optical authoritative=false")
	var owrites: Dictionary = ov.get("writes", {})
	_eq(bool(owrites.get("track_table", true)), false, "optical writes.track_table=false")
	_eq(bool(owrites.get("v15", true)), false, "optical writes.v15=false")
	var sensors: Dictionary = ov.get("sensors", {})
	_ok(sensors.has("optical") or sensors.has("ir"), "sensors 含 optical/ir")
	_ok(br.optical_ir_summary().has("channels"), "optical summary.channels")
	# 对接
	_eq(br.docking_enabled, true, "默认 docking_enabled")
	_eq(br.docking_ready, true, "docking_ready")
	_ok(br.docking != null, "docking 实例存在")
	var dv: Dictionary = br.docking_view()
	for key in ["schema", "state", "ports", "target_port", "t", "last", "events",
			"config", "writes", "authoritative"]:
		_ok(dv.has(key), "docking view 含字段: " + key)
	_eq(String(dv.get("schema", "")), "v17_docking.v1", "docking schema")
	_eq(String(dv.get("state", "")), "far", "docking 初始 state=far")
	_ok((dv.get("ports", []) as Array).size() >= 4, "docking ports ≥4",
		str((dv.get("ports", []) as Array).size()))
	_eq(bool(dv.get("authoritative", true)), false, "docking authoritative=false")
	var dwrites: Dictionary = dv.get("writes", {})
	for k in ["world", "physics", "track_table", "v15"]:
		_eq(bool(dwrites.get(k, true)), false, "docking writes.%s=false" % k)
	var bs: Dictionary = br.bridge_state()
	for key in ["optical_ir", "optical_ir_summary", "optical_ir_ready", "optical_ir_enabled",
			"docking", "docking_ready", "docking_enabled", "docking_update_last"]:
		_ok(bs.has(key), "bridge_state 含 " + key)
	_clear_env()
	_data_line("boot", "optical ready（sensors=%d）· docking ready（ports=%d state=far）" % [
		sensors.size(), (dv.get("ports", []) as Array).size()])

# ═══════════════════════════════════════════════════════════════════
# 2. 光学/IR 显式 API
# ═══════════════════════════════════════════════════════════════════

func _test_optical_ir() -> void:
	_section_begin("2 光学/IR")
	_clear_env()
	var br = _make_bridge()
	var target := "2001"
	var point: Dictionary = br.optical_ir_point(target)
	_eq(bool(point.get("ok", false)), true, "optical_ir_point ok", str(point.get("reason", "")))
	var st_opt: Dictionary = br.optical_ir_start("optical", target)
	_eq(bool(st_opt.get("ok", false)), true, "start VIS 通道", String(st_opt.get("reason", "")))
	var st_ir: Dictionary = br.optical_ir_start("ir", target)
	_eq(bool(st_ir.get("ok", false)), true, "start IR 通道", String(st_ir.get("reason", "")))
	# 视轴从 0° 起以 slew_rate 转向目标，多步收敛（明确 shadow，不写 V15）
	br.optical_ir_point(target)
	for i in range(12):
		br.optical_ir_step(1.0)
	var step: Dictionary = br.optical_ir_view()
	_ok(step.has("channels"), "optical_ir_step 返回 VM")
	var view: Dictionary = br.optical_ir_view()
	var channels: Array = view.get("channels", [])
	_ok(channels.size() >= 2, "channels ≥2", str(channels.size()))
	var kinds := {}
	for raw in channels:
		var ch: Dictionary = raw
		kinds[String(ch.get("channel", ""))] = String(ch.get("status", ""))
		_ok(ch.has("off_axis_deg") and ch.has("slant_range_km") and ch.has("snr_db"),
			"channel 含核心字段 channel=" + String(ch.get("channel", "")))
		_ok(String(ch.get("status", "")) != "", "channel status 非空")
	_ok(kinds.has("optical"), "含 VIS 通道")
	_ok(kinds.has("ir"), "含 IR 通道")
	var sum: Dictionary = br.optical_ir_summary()
	_ok(int(sum.get("channels", 0)) >= 2, "summary.channels ≥2", str(sum.get("channels", 0)))
	_eq(bool(sum.get("writes_v15", true)), false, "summary.writes_v15=false")
	# 停止并确认清理（不写 V15）
	br.optical_ir_stop("optical", target)
	br.optical_ir_stop("ir", target)
	var view2: Dictionary = br.optical_ir_view()
	_eq((view2.get("channels", []) as Array).size(), 0, "stop 后 channels=0")
	_clear_env()
	_data_line("optical", "point/start(optical+ir)/step：channels=%d statuses=%s · writes=false" % [
		channels.size(), str(kinds)])

# ═══════════════════════════════════════════════════════════════════
# 3. 对接显式 API
# ═══════════════════════════════════════════════════════════════════

func _test_docking() -> void:
	_section_begin("3 对接")
	_clear_env()
	var br = _make_bridge()
	var sel: Dictionary = br.docking_select_port("chronos-dock-a")
	_eq(bool(sel.get("ok", false)), true, "选择端口 chronos-dock-a", String(sel.get("reason", "")))
	var view: Dictionary = br.docking_view()
	_eq(String((view.get("target_port", {}) as Dictionary).get("port_id", "")), "chronos-dock-a",
		"target_port=chronos-dock-a")
	# 远距离 update
	var far_res: Dictionary = br.docking_update({"dr": [0.0, 0.0, 200.0], "dv": [0.0, 0.0, -0.5]},
		{"chaser_port_axis": [0.0, 0.0, -1.0]}, 1.0)
	_ok(not far_res.has("reason"), "远距离 docking_update 无错误",
		String(far_res.get("reason", "")))
	_near(float(far_res.get("range_km", -1.0)), 200.0, 1.0e-6, "far range=200km")
	_ok(String(far_res.get("state", "")) in ["far", "approach", "corridor", "hold"],
		"far 后状态合法", String(far_res.get("state", "")))
	_ok(far_res.get("guidance") is Dictionary, "输出 guidance")
	_ok(br.docking_update_last.size() > 0, "bridge docking_update_last 缓存")
	# 近距离预览 + update（沿端口轴 +x，chaser 轴 -x）
	var prev: Dictionary = br.docking.preview({"dr": [0.1, 0.0, 0.0], "dv": [-0.001, 0.0, 0.0]},
		{"chaser_port_axis": [-1.0, 0.0, 0.0]})
	_ok(not prev.has("reason"), "preview 近距无错误", String(prev.get("reason", "")))
	_ok(float(prev.get("range_km", -1.0)) > 0.0, "preview range>0")
	_ok(prev.get("corridor", {}) is Dictionary, "preview corridor")
	var near_res: Dictionary = br.docking_update({"dr": [0.1, 0.0, 0.0], "dv": [-0.001, 0.0, 0.0]},
		{"chaser_port_axis": [-1.0, 0.0, 0.0]}, 0.1)
	_ok(not near_res.has("reason"), "近距 docking_update 无错误", String(near_res.get("reason", "")))
	_ok(String(near_res.get("state", "")) in ["far", "approach", "corridor", "hold",
		"alignment", "final", "docked"], "near 后状态合法", String(near_res.get("state", "")))
	_near(float(near_res.get("range_km", -1.0)), 0.1, 1.0e-6, "near range=0.1km")
	_ok(near_res.get("docking") is Dictionary, "near docking geometry")
	_ok(near_res.get("guidance", {}) is Dictionary, "near guidance")
	# hold / resume / reset
	var hold_res: Dictionary = br.docking_hold("probe_hold")
	_eq(String(br.docking_view().get("state", "")), "hold", "hold → state=hold")
	_ok(hold_res.has("state") or hold_res.get("ok", false) != null, "hold 返回可用")
	var resume_res: Dictionary = br.docking_resume()
	_ok(String(br.docking_view().get("state", "")) != "hold", "resume 后离开 hold",
		String(br.docking_view().get("state", "")))
	var reset_res: Dictionary = br.docking_reset()
	_eq(bool(reset_res.get("ok", false)), true, "docking_reset ok")
	_eq(String(br.docking_view().get("state", "")), "far", "reset 后 state=far")
	_clear_env()
	_data_line("docking", "select/update(far→near)/hold/resume/reset：state=%s · writes=false" % [
		String(view.get("state", ""))])

# ═══════════════════════════════════════════════════════════════════
# 4. state / V15 不变
# ═══════════════════════════════════════════════════════════════════

func _test_state_and_v15() -> void:
	_section_begin("4 state / V15 不变")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	_ok(st.fw_optical_ir.size() > 0, "state.fw_optical_ir 非空")
	_ok(st.fw_docking.size() > 0, "state.fw_docking 非空")
	_eq(String(st.fw_optical_ir.get("schema", "")), "optical_ir.v1", "fw_optical_ir schema")
	_eq(String(st.fw_docking.get("schema", "")), "v17_docking.v1", "fw_docking schema")
	var snap0 := _track_snapshot(st)
	var tracks0 := str(st.tracks)
	var info0: Dictionary = st.fw_info_warfare.duplicate(true)
	# 显式 API（state 包装）
	var point: Dictionary = st.fw_optical_ir_point("2001")
	_eq(bool(point.get("ok", false)), true, "state.fw_optical_ir_point ok")
	var start_res: Dictionary = st.fw_optical_ir_start("optical", "2001")
	_eq(bool(start_res.get("ok", false)), true, "state.fw_optical_ir_start ok")
	st.fw_optical_ir_step(0.5)
	_ok((st.fw_optical_ir.get("channels", []) as Array).size() >= 1,
		"state fw_optical_ir 已刷新 channels")
	st.fw_optical_ir_stop("optical", "2001")
	var sel: Dictionary = st.fw_docking_select_port("chronos-dock-a")
	_eq(bool(sel.get("ok", false)), true, "state.fw_docking_select_port ok")
	var up: Dictionary = st.fw_docking_update({"dr": [0.0, 0.0, 100.0], "dv": [0.0, 0.0, -0.3]},
		{"chaser_port_axis": [0.0, 0.0, -1.0]}, 0.5)
	_ok(not up.has("reason"), "state.fw_docking_update 无错误", String(up.get("reason", "")))
	_ok(st.fw_docking.get("last") is Dictionary, "state fw_docking.last 已刷新")
	st.fw_sync(0.0)
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("identity"), snap0.get("identity"), "V15 身份不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_ok(str(st.tracks) == tracks0, "V15 tracks 未被写")
	if info0.size() > 0:
		_eq(str(st.fw_info_warfare), str(info0), "旧 fw_info_warfare 不变")
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["optical_ir", "docking"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	_clear_env()
	_data_line("state/v15", "fw_optical_ir/fw_docking 刷新 · V15 tracks/等级/身份/clock 不变")

# ═══════════════════════════════════════════════════════════════════
# 5. off 降级
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("5 off 降级")
	_set_off()
	var br = _make_bridge()
	_eq(br.optical_ir_enabled, false, "V17_OPTICAL_IR=off → enabled=false")
	_eq(br.optical_ir_ready, false, "optical_ir_ready=false")
	_eq(br.optical_ir_view().size(), 0, "optical view 空")
	_eq(br.optical_ir_step(1.0).get("ok", true), false, "off 时 optical_ir_step ok=false")
	_eq(br.docking_enabled, false, "V17_DOCKING=off → enabled=false")
	_eq(br.docking_ready, false, "docking_ready=false")
	_eq(br.docking_view().size(), 0, "docking view 空")
	_eq(br.docking_update({"dr": [0, 0, 1], "dv": [0, 0, 0]}).get("ok", true), false,
		"off 时 docking_update ok=false")
	var st = _make_state(br)
	_eq(st.fw_optical_ir.size(), 0, "state fw_optical_ir 空")
	_eq(st.fw_docking.size(), 0, "state fw_docking 空")
	# 旧字段仍正常
	_ok(st.fw_sensor_shadow_ready, "off 时 sensor shadow 不受影响")
	_ok(st.fw_info_warfare_ready, "off 时 info warfare 不受影响")
	_clear_env()
	_data_line("off", "V17_OPTICAL_IR=off + V17_DOCKING=off：view 空/API ok=false/state 空；不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 6. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("6 JSON")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	var ojs := JSON.stringify(br.optical_ir_view())
	_ok(ojs.length() > 1000, "optical view JSON", "len=%d" % ojs.length())
	_ok(JSON.parse_string(ojs) is Dictionary, "optical view JSON 回读")
	var djs := JSON.stringify(br.docking_view())
	_ok(djs.length() > 1000, "docking view JSON", "len=%d" % djs.length())
	var dp = JSON.parse_string(djs)
	_ok(dp is Dictionary, "docking view JSON 回读")
	if dp is Dictionary:
		_ok((dp.get("ports", []) as Array).size() >= 4, "回读 ports")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	_ok(JSON.parse_string(bs) is Dictionary, "fw_bridge_state 回读")
	_clear_env()
	_data_line("json", "optical/docking/fw_bridge_state JSON 可回读")
