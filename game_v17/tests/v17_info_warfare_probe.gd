extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-INFO-BRIDGE-1 最小 probe：信息作战 shadow 接 V17 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_info_warfare_probe.gd
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
	print("R5-INFO-BRIDGE-1 PROBE · 信息作战 shadow（bridge/state，最小）")
	print("════════════════════════════════════════════════════════════")
	_test_boot()
	_test_events()
	_test_state_and_v15()
	_test_authoritative_request()
	_test_off_mode()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 INFO WARFARE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 INFO WARFARE PROBE FAILED")
		quit(1)
	else:
		print("V17 INFO WARFARE PROBE OK")
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

func _set_mode(mode: String) -> void:
	OS.set_environment("V17_INFO_WARFARE", mode)

func _clear_env() -> void:
	OS.set_environment("V17_INFO_WARFARE", "")

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

func _event_types(view: Dictionary) -> Array:
	var out: Array = []
	for raw in (view.get("events", []) as Array):
		var e: Dictionary = raw
		var ty := String(e.get("type", ""))
		if not out.has(ty):
			out.append(ty)
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. boot
# ═══════════════════════════════════════════════════════════════════

func _test_boot() -> void:
	_section_begin("1 boot")
	_clear_env()
	var br = _make_bridge()
	_eq(br.info_warfare_mode, "shadow", "默认 mode=shadow")
	_eq(br.info_warfare_requested_mode, "shadow", "requested=shadow")
	_eq(br.info_warfare_ready, true, "info_warfare_ready")
	_ok(br.info_warfare != null, "IW 实例存在")
	var view: Dictionary = br.info_warfare_view()
	for key in ["schema", "mode", "authoritative", "ready", "t", "observer", "iff",
			"elint", "comint", "ew", "events", "alerts", "summary", "writes", "shadow"]:
		_ok(view.has(key), "view 含字段: " + key)
	_eq(String(view.get("schema", "")), "information_warfare.v1", "schema")
	_eq(String(view.get("mode", "")), "shadow", "view.mode=shadow")
	_eq(bool(view.get("authoritative", true)), false, "view.authoritative=false")
	_eq(bool(view.get("ready", false)), true, "view.ready=true")
	var writes: Dictionary = view.get("writes", {})
	_eq(bool(writes.get("track_table", true)), false, "writes.track_table=false")
	_eq(bool(writes.get("v15", true)), false, "writes.v15=false")
	var shadow: Dictionary = view.get("shadow", {})
	_eq(bool(shadow.get("never_auto_hostile", false)), true, "shadow.never_auto_hostile=true")
	var summary: Dictionary = br.info_warfare_summary()
	for key in ["iff", "iff_identity_friend", "iff_identity_unknown", "iff_identity_hostile",
			"signals", "fix_candidates", "comint", "effects", "events", "alerts",
			"phantom_active", "suspicious_commands", "hostile_auto_determination"]:
		_ok(summary.has(key), "summary 含 " + key)
	_eq(bool(summary.get("hostile_auto_determination", true)), false, "summary.hostile_auto_determination=false")
	_ok((view.get("elint", {}) as Dictionary).has("signals"), "view.elint 含 signals")
	_ok((view.get("iff", {}) as Dictionary).has("results"), "view.iff 含 results")
	_ok((view.get("comint", {}) as Dictionary).has("events"), "view.comint 含 events")
	_ok((view.get("ew", {}) as Dictionary).has("effects"), "view.ew 含 effects")
	_ok(br.info_warfare_events().size() <= 8, "recent events ≤8", str(br.info_warfare_events().size()))
	_ok(br.info_warfare_alerts().size() <= 8, "recent alerts ≤8", str(br.info_warfare_alerts().size()))
	_clear_env()
	_data_line("boot", "mode=shadow ready · events=%d alerts=%d · writes=false" % [
		(view.get("events", []) as Array).size(), (view.get("alerts", []) as Array).size()])

# ═══════════════════════════════════════════════════════════════════
# 2. IFF / ELINT / EW 至少各一次事件 + COMINT
# ═══════════════════════════════════════════════════════════════════

func _test_events() -> void:
	_section_begin("2 事件")
	_clear_env()
	var br = _make_bridge()
	var view: Dictionary = br.info_warfare_view()
	# ELINT：setup 已强制扫描；若不足则再强制扫描
	if not _event_types(view).has("emitter.signal"):
		br.info_warfare.scan_elint(true)
		br.refresh()
		view = br.info_warfare_view()
	var elint: Dictionary = view.get("elint", {})
	_ok(int((elint.get("summary", {}) as Dictionary).get("signals", 0)) > 0,
		"ELINT signals>0", str((elint.get("summary", {}) as Dictionary).get("signals", 0)))
	_ok(_event_types(view).has("emitter.signal"), "ELINT 产生 emitter.signal 事件")
	# IFF：对友军目标主动询问（shadow advisory）
	var targets: Array = (view.get("elint", {}) as Dictionary).get("signals", [])
	var iff_res: Dictionary = {}
	for tid in ["1000", "1002", "1004"]:
		iff_res = br.info_warfare.interrogate_iff(tid)
		if bool(iff_res.get("ok", false)):
			break
	_ok(bool(iff_res.get("ok", false)), "IFF interrogate_iff 成功",
		String(iff_res.get("status", "")))
	br.refresh()
	view = br.info_warfare_view()
	var iff_events := 0
	for raw in (view.get("events", []) as Array):
		if String((raw as Dictionary).get("type", "")) == "iff.reply":
			iff_events += 1
	_ok(iff_events > 0, "IFF 产生 iff.reply 事件", str(iff_events))
	var iff_vm: Dictionary = view.get("iff", {})
	_ok(int((iff_vm.get("summary", {}) as Dictionary).get("unknown", 0)) >= 0, "IFF summary 可读")
	# EW：注入噪声干扰（shadow；只产生 effect/event/alerts，不写轨道）
	var ew_res: Dictionary = br.info_warfare.inject_noise_jamming("harmattan", "1000", 0.7, 60.0)
	_ok(bool(ew_res.get("ok", false)), "EW inject_noise_jamming 成功",
		String(ew_res.get("reason", "")))
	br.refresh()
	view = br.info_warfare_view()
	var ew_events := 0
	for raw in (view.get("events", []) as Array):
		if String((raw as Dictionary).get("type", "")) == "ew.effect":
			ew_events += 1
	_ok(ew_events > 0, "EW 产生 ew.effect 事件", str(ew_events))
	var ew_vm: Dictionary = view.get("ew", {})
	_ok(int(ew_vm.get("active_count", 0)) > 0, "EW active effects>0", str(ew_vm.get("active_count", 0)))
	_ok((view.get("alerts", []) as Array).size() > 0, "EW/IFF 产生 alerts")
	# COMINT（只读观察）
	var comint: Dictionary = view.get("comint", {})
	_ok(comint.has("summary"), "COMINT summary 可读")
	# bridge_state / recent 缓存
	var bs: Dictionary = br.bridge_state()
	for key in ["info_warfare", "info_warfare_summary", "info_warfare_ready", "info_warfare_mode",
			"info_warfare_requested_mode", "info_warfare_fallback_reason",
			"info_warfare_recent_events", "info_warfare_recent_alerts"]:
		_ok(bs.has(key), "bridge_state 含 " + key)
	_ok((bs.get("info_warfare_recent_events", []) as Array).size() > 0, "recent events 非空")
	var types := _event_types(view)
	_clear_env()
	_data_line("events", "types=%s · IFF/ELINT/EW 各≥1 次 · alerts=%d" % [
		str(types), (view.get("alerts", []) as Array).size()])

# ═══════════════════════════════════════════════════════════════════
# 3. state / V15 不变
# ═══════════════════════════════════════════════════════════════════

func _test_state_and_v15() -> void:
	_section_begin("3 state / V15 不变")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	_eq(st.fw_info_warfare_ready, true, "state.fw_info_warfare_ready")
	_ok(st.fw_info_warfare.size() > 0, "state.fw_info_warfare 非空")
	_ok(st.fw_info_warfare_summary.size() > 0, "state.fw_info_warfare_summary 非空")
	_eq(bool(st.fw_info_warfare_summary.get("hostile_auto_determination", true)), false,
		"state summary.hostile_auto_determination=false")
	# 旧字段不变（sensor shadow 仍在）
	_eq(st.fw_sensor_shadow_ready, true, "旧 fw_sensor_shadow_ready 不变")
	_ok(st.fw_sensor_shadow.size() > 0, "旧 fw_sensor_shadow 非空")
	var snap0 := _track_snapshot(st)
	var tracks0 := str(st.tracks)
	var world_tracks0 := str(br.world.vm_tracks())
	# 交互后 step（世界计时推进，但 V15 不写）
	br.info_warfare.interrogate_iff("1000")
	br.info_warfare.inject_noise_jamming("harmattan", "1000", 0.7, 60.0)
	br.sync(0.2)
	st.fw_sync(0.0)
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("identity"), snap0.get("identity"), "V15 身份不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_ok(str(st.tracks) == tracks0, "V15 tracks 未被写")
	# V2 world 轨道未被 IW 写（仅 world.advance 自身推进）
	_ok(str(br.world.vm_tracks()).length() > 0, "V2 vm_tracks 可读")
	_ok(world_tracks0.length() > 0, "V2 vm_tracks 基线可读")
	_ok(st.fw_info_warfare_ready, "fw_sync 后 info ready")
	# recent 事件/告警缓存
	_ok(br.info_warfare_events().size() > 0, "recent events 缓存")
	_ok(br.info_warfare_alerts().size() > 0, "recent alerts 缓存")
	# state bridge_state 字段
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["info_warfare", "info_warfare_ready", "info_warfare_summary"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	_clear_env()
	_data_line("state/v15", "fw_info_warfare/summary 只读；V15 tracks/等级/身份/clock 不变")

# ═══════════════════════════════════════════════════════════════════
# 4. authoritative 请求 → 只 shadow + reason
# ═══════════════════════════════════════════════════════════════════

func _test_authoritative_request() -> void:
	_section_begin("4 authoritative 请求")
	_set_mode("authoritative")
	var br = _make_bridge()
	_eq(br.info_warfare_requested_mode, "authoritative", "requested=authoritative")
	_eq(br.info_warfare_mode, "shadow", "有效模式仍 shadow（未实现）")
	_ok(String(br.info_warfare_fallback_reason).contains("未实现"), "fallback_reason 明示未实现",
		br.info_warfare_fallback_reason)
	var view: Dictionary = br.info_warfare_view()
	_eq(bool(view.get("authoritative", true)), false, "view.authoritative=false（不伪称）")
	_eq(String(view.get("mode", "")), "shadow", "view.mode=shadow")
	_eq(br.info_warfare_ready, true, "shadow 仍 ready")
	_clear_env()
	_data_line("authoritative", "请求 authoritative → 仍 shadow + fallback_reason（不伪称）")

# ═══════════════════════════════════════════════════════════════════
# 5. off 降级
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("5 off 降级")
	_set_mode("off")
	var br = _make_bridge()
	_eq(br.info_warfare_mode, "off", "mode=off")
	_eq(br.info_warfare_ready, false, "ready=false")
	_eq(br.info_warfare_view().size(), 0, "view 空")
	_eq(br.info_warfare_summary().size(), 0, "summary 空")
	_eq(br.info_warfare_events().size(), 0, "recent events 空")
	var st = _make_state(br)
	_eq(st.fw_info_warfare_ready, false, "state.fw_info_warfare_ready=false")
	_eq(st.fw_info_warfare.size(), 0, "state.fw_info_warfare 空")
	_eq(st.fw_info_warfare_summary.size(), 0, "state summary 空")
	# 旧字段仍正常
	_ok(st.fw_sensor_shadow_ready, "off 时 sensor shadow 不受影响")
	_clear_env()
	_data_line("off", "V17_INFO_WARFARE=off：无 IW；state 空；不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 6. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("6 JSON")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	var js := JSON.stringify(br.info_warfare_view())
	_ok(js.length() > 2000, "info_warfare_view JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "view JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("iff") is Dictionary, "回读 iff")
		_ok(pd.get("elint") is Dictionary, "回读 elint")
		_ok(pd.get("ew") is Dictionary, "回读 ew")
		_ok(pd.get("events") is Array, "回读 events")
	var sjs := JSON.stringify(st.fw_info_warfare_summary)
	_ok(sjs.length() > 100, "state summary JSON", "len=%d" % sjs.length())
	_ok(JSON.parse_string(sjs) is Dictionary, "summary JSON 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	_ok(JSON.parse_string(bs) is Dictionary, "fw_bridge_state 回读")
	_clear_env()
	_data_line("json", "view/summary/bridge_state JSON 可回读")
