extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-AUTO-SENSOR-1 最小 probe：bridge 自动光学/对接数据
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_optical_docking_auto_probe.gd
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
	print("R5-AUTO-SENSOR-1 PROBE · 自动光学/对接数据（最小）")
	print("════════════════════════════════════════════════════════════")
	_test_auto_default()
	_test_manual_override()
	_test_state_and_v15()
	_test_on_mode()
	_test_off_mode()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 OPTICAL DOCKING AUTO PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 OPTICAL DOCKING AUTO PROBE FAILED")
		quit(1)
	else:
		print("V17 OPTICAL DOCKING AUTO PROBE OK")
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

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _clear_env() -> void:
	OS.set_environment("V17_OPTICAL_IR", "")
	OS.set_environment("V17_DOCKING", "")

func _set_env(opt: String, dock: String) -> void:
	OS.set_environment("V17_OPTICAL_IR", opt)
	OS.set_environment("V17_DOCKING", dock)

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

func _channels_statuses(view: Dictionary) -> Array:
	var out: Array = []
	for raw in (view.get("channels", []) as Array):
		out.append(String((raw as Dictionary).get("status", "")))
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. 默认 auto
# ═══════════════════════════════════════════════════════════════════

func _test_auto_default() -> void:
	_section_begin("1 默认 auto")
	_clear_env()
	var br = _make_bridge()
	_eq(br.optical_ir_auto_enabled, true, "默认 optical auto=true")
	_eq(br.docking_auto_enabled, true, "默认 docking auto=true")
	_eq(br.optical_ir_auto_step_count, 0, "auto step 初值 0")
	br.sync(30.0)
	_ok(br.optical_ir_auto_step_count > 0, "sync 后 optical auto steps>0",
		str(br.optical_ir_auto_step_count))
	_ok(br.docking_auto_step_count > 0, "sync 后 docking auto steps>0",
		str(br.docking_auto_step_count))
	_ok(br.optical_ir_auto_target != "", "auto 选择光学目标", br.optical_ir_auto_target)
	var ov: Dictionary = br.optical_ir_view()
	var channels: Array = ov.get("channels", [])
	_ok(channels.size() >= 2, "auto channels ≥2", str(channels.size()))
	var statuses := _channels_statuses(ov)
	var good := 0
	for s in statuses:
		if s in ["acquiring", "staring", "locked"]:
			good += 1
	_ok(good >= 1, "auto 通道 acquiring/staring/locked", str(statuses))
	_eq(bool((ov.get("writes", {}) as Dictionary).get("v15", true)), false,
		"optical writes.v15=false")
	var dv: Dictionary = br.docking_view()
	_ok(String(dv.get("state", "")) in ["far", "approach", "corridor", "hold",
		"alignment", "final", "docked"], "auto docking 状态合法", String(dv.get("state", "")))
	var last: Dictionary = dv.get("last", {})
	_ok(float(last.get("range_km", -1.0)) > 0.0, "docking last range>0",
		str(last.get("range_km", -1.0)))
	_ok(String(dv.get("target_port_id", "")) != "", "auto 选择对接端口",
		String(dv.get("target_port_id", "")))
	_eq(bool((dv.get("writes", {}) as Dictionary).get("v15", true)), false,
		"docking writes.v15=false")
	var bs: Dictionary = br.bridge_state()
	for key in ["optical_ir_auto", "docking_auto", "optical_ir_auto_step_count",
			"docking_auto_step_count"]:
		_ok(bs.has(key), "bridge_state 含 " + key)
	_clear_env()
	_data_line("auto", "steps optical=%d docking=%d · channels=%s · docking=%s range=%.1fkm" % [
		br.optical_ir_auto_step_count, br.docking_auto_step_count, str(statuses),
		String(dv.get("state", "")), float(last.get("range_km", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 2. 手动覆盖
# ═══════════════════════════════════════════════════════════════════

func _test_manual_override() -> void:
	_section_begin("2 手动覆盖")
	_clear_env()
	var br = _make_bridge()
	br.sync(10.0)
	var steps0: int = br.optical_ir_auto_step_count
	br.optical_ir_stop("optical", "")
	_eq(br.optical_ir_auto_suppressed, true, "stop 后 auto 抑制")
	br.sync(10.0)
	_eq(br.optical_ir_auto_step_count, steps0, "抑制后 optical auto 不步进")
	br.optical_ir_start("optical", br.optical_ir_auto_target)
	_eq(br.optical_ir_auto_suppressed, false, "start 后 auto 恢复")
	br.sync(5.0)
	_ok(br.optical_ir_auto_step_count > steps0, "恢复后 optical auto 继续步进")
	var dsteps: int = br.docking_auto_step_count
	br.docking_update({"dr": [0.0, 0.0, 120.0], "dv": [0.0, 0.0, -0.3]},
		{"chaser_port_axis": [0.0, 0.0, -1.0]}, 0.5)
	_eq(br.docking_auto_suppressed, true, "手动 update 后 docking auto 抑制")
	br.sync(10.0)
	_eq(br.docking_auto_step_count, dsteps, "抑制后 docking auto 不步进")
	br.docking_reset()
	_eq(br.docking_auto_suppressed, false, "reset 后 docking auto 恢复")
	br.sync(5.0)
	_ok(br.docking_auto_step_count > dsteps, "恢复后 docking auto 继续步进")
	_clear_env()
	_data_line("override", "stop/update 抑制 auto；start/reset 恢复；不写 V15")

# ═══════════════════════════════════════════════════════════════════
# 3. state / V15 不变
# ═══════════════════════════════════════════════════════════════════

func _test_state_and_v15() -> void:
	_section_begin("3 state / V15 不变")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	var snap0 := _track_snapshot(st)
	var tracks0 := str(st.tracks)
	st.fw_sync(30.0)
	_eq(st.fw_optical_ir_auto, true, "state.fw_optical_ir_auto=true")
	_eq(st.fw_docking_auto, true, "state.fw_docking_auto=true")
	_ok(st.fw_optical_ir.size() > 0, "state.fw_optical_ir 非空")
	_ok(st.fw_docking.size() > 0, "state.fw_docking 非空")
	_ok((st.fw_optical_ir.get("channels", []) as Array).size() >= 1,
		"state fw_optical_ir auto channels 已刷新")
	_ok(st.fw_docking.get("last") is Dictionary, "state fw_docking.last 已刷新")
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("identity"), snap0.get("identity"), "V15 身份不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_ok(str(st.tracks) == tracks0, "V15 tracks 未被写")
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["optical_ir_auto", "docking_auto"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	_clear_env()
	_data_line("state/v15", "fw_optical_ir/fw_docking 每帧刷新；fw_*_auto=true；V15 不变")

# ═══════════════════════════════════════════════════════════════════
# 4. 显式 on（只手动）
# ═══════════════════════════════════════════════════════════════════

func _test_on_mode() -> void:
	_section_begin("4 显式 on")
	_set_env("on", "on")
	var br = _make_bridge()
	_eq(br.optical_ir_auto_enabled, false, "on 模式 auto=false")
	_eq(br.docking_auto_enabled, false, "on 模式 docking auto=false")
	_eq(br.optical_ir_ready, true, "on 模式 optical ready")
	br.sync(10.0)
	_eq((br.optical_ir_view().get("channels", []) as Array).size(), 0,
		"on 模式 auto 不启动通道")
	_eq((br.docking_view().get("last", {}) as Dictionary).size(), 0,
		"on 模式 auto 不 update")
	# 显式仍可用
	var sel: Dictionary = br.docking_select_port("chronos-dock-a")
	_ok(bool(sel.get("ok", false)), "on 模式显式 select 可用")
	_clear_env()
	_data_line("on", "显式 on：auto=false，不自动起通道/update；显式 API 可用")

# ═══════════════════════════════════════════════════════════════════
# 5. off 降级
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("5 off 降级")
	_set_env("off", "off")
	var br = _make_bridge()
	_eq(br.optical_ir_enabled, false, "off optical enabled=false")
	_eq(br.optical_ir_auto_enabled, false, "off optical auto=false")
	_eq(br.docking_enabled, false, "off docking enabled=false")
	_eq(br.docking_auto_enabled, false, "off docking auto=false")
	br.sync(10.0)
	_eq(br.optical_ir_auto_step_count, 0, "off optical auto steps=0")
	_eq(br.docking_auto_step_count, 0, "off docking auto steps=0")
	_eq(br.optical_ir_view().size(), 0, "off optical view 空")
	_eq(br.docking_view().size(), 0, "off docking view 空")
	var st = _make_state(br)
	_eq(st.fw_optical_ir_auto, false, "off state fw_optical_ir_auto=false")
	_eq(st.fw_docking_auto, false, "off state fw_docking_auto=false")
	_eq(st.fw_optical_ir.size(), 0, "off state optical 空")
	_clear_env()
	_data_line("off", "off：auto 全停、view/state 空、不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 6. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("6 JSON")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	st.fw_sync(20.0)
	var js := JSON.stringify(st.fw_optical_ir)
	_ok(js.length() > 1000, "auto optical JSON", "len=%d" % js.length())
	_ok(JSON.parse_string(js) is Dictionary, "optical JSON 回读")
	var djs := JSON.stringify(st.fw_docking)
	_ok(djs.length() > 1000, "auto docking JSON", "len=%d" % djs.length())
	_ok(JSON.parse_string(djs) is Dictionary, "docking JSON 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	_ok(JSON.parse_string(bs) is Dictionary, "fw_bridge_state 回读")
	_clear_env()
	_data_line("json", "auto optical/docking/fw_bridge_state JSON 可回读")