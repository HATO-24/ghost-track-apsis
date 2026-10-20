extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-SENSOR-BRIDGE-1 最小 probe：传感器 shadow 接 V17 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_sensor_shadow_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。不跑全量回归。
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
	print("R5-SENSOR-BRIDGE-1 PROBE · 传感器 shadow（bridge/state，最小）")
	print("════════════════════════════════════════════════════════════")
	_test_boot()
	_test_step_and_pause()
	_test_compare_and_v15_unchanged()
	_test_authoritative_request()
	_test_off_mode()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SENSOR SHADOW PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SENSOR SHADOW PROBE FAILED")
		quit(1)
	else:
		print("V17 SENSOR SHADOW PROBE OK")
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
	OS.set_environment("V17_SENSOR_AUTHORITY", mode)

func _clear_env() -> void:
	OS.set_environment("V17_SENSOR_AUTHORITY", "")

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
# 1. boot / advisory vm
# ═══════════════════════════════════════════════════════════════════

func _test_boot() -> void:
	_section_begin("1 boot")
	_clear_env()
	var br = _make_bridge()
	_eq(br.sensor_shadow_mode, "shadow", "默认 mode=shadow")
	_eq(br.sensor_authority_requested_mode, "shadow", "requested=shadow")
	_eq(br.sensor_shadow_ready, true, "sensor_shadow_ready")
	_ok(br.sensor_shadow != null, "sensor shadow 实例存在")
	var view: Dictionary = br.sensor_shadow_view()
	for key in ["schema", "mode", "authoritative", "ready", "t", "observer", "mounts",
			"radar", "channels", "advisory_contacts", "advisory_observations",
			"warnings", "writes", "shadow", "counts"]:
		_ok(view.has(key), "view 含字段: " + key)
	_eq(String(view.get("schema", "")), "sensor_shadow.v1", "schema=sensor_shadow.v1")
	_eq(String(view.get("mode", "")), "shadow", "view.mode=shadow")
	_eq(bool(view.get("authoritative", true)), false, "view.authoritative=false")
	_eq(bool(view.get("ready", false)), true, "view.ready=true")
	_eq(String((view.get("observer", {}) as Dictionary).get("id", "")), "harmattan", "observer=harmattan")
	var writes: Dictionary = view.get("writes", {})
	_eq(bool(writes.get("track_table", true)), false, "writes.track_table=false")
	_eq(bool(writes.get("v15", true)), false, "writes.v15=false")
	var counts: Dictionary = view.get("counts", {})
	_ok(int(counts.get("contacts", 0)) > 0, "advisory_contacts>0", str(counts.get("contacts")))
	_ok(int(counts.get("channels", 0)) > 0, "channels>0", str(counts.get("channels")))
	_ok((view.get("advisory_contacts", []) as Array).size() > 0, "advisory_contacts 数组非空")
	_ok((view.get("channels", []) as Array).size() > 0, "channels 数组非空")
	_ok(view.get("radar", {}) is Dictionary, "radar 结构")
	var sum: Dictionary = br.sensor_shadow_summary()
	_eq(sum.get("mode"), "shadow", "summary.mode=shadow")
	_eq(sum.get("ready"), true, "summary.ready")
	_eq(sum.get("writes_track_table"), false, "summary.writes_track_table=false")
	_ok(int(sum.get("contacts", 0)) > 0, "summary.contacts>0")
	var bs: Dictionary = br.bridge_state()
	for key in ["sensor_shadow", "sensor_shadow_summary", "sensor_shadow_ready",
			"sensor_shadow_mode", "sensor_compare"]:
		_ok(bs.has(key), "bridge_state 含 " + key)
	_clear_env()
	_data_line("boot", "mode=shadow ready · contacts=%d channels=%d writes=false" % [
		int(counts.get("contacts", 0)), int(counts.get("channels", 0))])

# ═══════════════════════════════════════════════════════════════════
# 2. step / dt=0 暂停
# ═══════════════════════════════════════════════════════════════════

func _test_step_and_pause() -> void:
	_section_begin("2 step / 暂停")
	_clear_env()
	var br = _make_bridge()
	var t0 := float(br.sensor_shadow_view().get("t", -1.0))
	br.sync(10.0)
	var t1 := float(br.sensor_shadow_view().get("t", -1.0))
	_near(t1, t0 + 10.0, 1.0e-6, "sync(10) 推进 shadow t")
	br.sync(0.0)
	_near(float(br.sensor_shadow_view().get("t", -1.0)), t1, 1.0e-6, "sync(0) 暂停不推进")
	_clear_env()
	_data_line("step", "sync(10) t+10；sync(0) 不推进")

# ═══════════════════════════════════════════════════════════════════
# 3. compare / V15 不变
# ═══════════════════════════════════════════════════════════════════

func _test_compare_and_v15_unchanged() -> void:
	_section_begin("3 compare / V15 不变")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	_eq(st.fw_sensor_shadow_ready, true, "state.fw_sensor_shadow_ready")
	_ok(st.fw_sensor_shadow.size() > 0, "state.fw_sensor_shadow 非空")
	_ok(st.fw_sensor_compare.size() > 0, "state.fw_sensor_compare 非空（fw_sync 自动）")
	_eq(bool(st.fw_sensor_compare.get("ok", false)), true, "state fw_sensor_compare.ok")
	var snap0 := _track_snapshot(st)
	var tracks0 := str(st.tracks)
	var v15_rows: Array = []
	for raw in st.tracks:
		var tr: Dictionary = raw
		if bool(tr.get("own", false)):
			continue
		v15_rows.append({"id": String(tr.get("id", "")), "batch": String(tr.get("batch", tr.get("id", ""))),
			"level": int(tr.get("level", 0)), "identity": String(tr.get("identity", "")),
			"range_km": float(tr.get("range_3d_km", tr.get("range", -1.0))),
			"bearing_deg": float(tr.get("bearing", tr.get("az_deg", -1.0)))})
	var tracks_before := str(br.world.vm_tracks())
	var cmp: Dictionary = br.sensor_compare(v15_rows)
	_eq(bool(cmp.get("ok", false)), true, "bridge.sensor_compare.ok")
	_eq(bool(cmp.get("read_only", false)), true, "compare.read_only=true")
	_eq(bool(cmp.get("authoritative", true)), false, "compare.authoritative=false")
	_eq(String(cmp.get("mode", "")), "shadow", "compare.mode=shadow")
	_ok(int(cmp.get("advisory_count", 0)) > 0, "compare.advisory_count>0")
	for key in ["legacy_count", "matched_count", "only_advisory", "only_legacy", "diffs",
			"summary", "warnings"]:
		_ok(cmp.has(key), "compare 含字段: " + key)
	var sum: Dictionary = cmp.get("summary", {})
	for key in ["level_equal", "level_advisory_higher", "level_advisory_lower",
			"identity_diff_unscoped", "only_advisory", "only_legacy",
			"avg_range_delta_km", "avg_bearing_delta_deg", "level_gate_pass", "within_tolerance"]:
		_ok(sum.has(key), "compare.summary 含 " + key)
	var warns: Array = cmp.get("warnings", [])
	var read_only_warn := false
	for raw in warns:
		if String(raw).contains("READ-ONLY"):
			read_only_warn = true
	_ok(read_only_warn, "compare warnings 明示 READ-ONLY")
	# V15/V2 未被写
	_eq(str(st.tracks), tracks0, "V15 tracks 未被 compare 修改")
	_eq(str(br.world.vm_tracks()), tracks_before, "V2 world vm_tracks 未被修改")
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	# compare 失败路径（非法输入）
	var bad: Dictionary = br.sensor_compare("not_an_array")
	_eq(bool(bad.get("ok", true)), false, "非法 legacy 输入 compare.ok=false")
	_clear_env()
	_data_line("compare", "ok/read_only · legacy_skipped_own=%d matched=%d · V15/V2 未写" % [
		int(cmp.get("legacy_skipped_own", 0)), int(cmp.get("matched_count", 0))])

# ═══════════════════════════════════════════════════════════════════
# 4. authoritative 请求 → 只 shadow + reason
# ═══════════════════════════════════════════════════════════════════

func _test_authoritative_request() -> void:
	_section_begin("4 authoritative 请求")
	_set_mode("authoritative")
	var br = _make_bridge()
	_eq(br.sensor_authority_requested_mode, "authoritative", "requested=authoritative")
	_eq(br.sensor_authority_mode, "authoritative", "authority 模式=authoritative（显示层）")
	_eq(br.sensor_shadow_mode, "shadow", "模型有效模式仍 shadow（显示层权威）")
	_eq(br.sensor_shadow_fallback_reason, "", "无回落 reason（R5-AUTHORITY-DISPLAY-1 已支持）")
	var view: Dictionary = br.sensor_shadow_view()
	_eq(bool(view.get("authoritative", true)), false, "view.authoritative=false（模型 shadow）")
	_eq(String(view.get("mode", "")), "shadow", "view.mode=shadow")
	_eq(br.sensor_shadow_ready, true, "shadow 仍 ready")
	var disp: Dictionary = br.sensor_authority_display()
	_eq(bool(disp.get("active", false)), true, "authority display active")
	_eq(bool(disp.get("writes_track_table", true)), false, "display 不写 TrackTable")
	_clear_env()
	_data_line("authoritative", "authoritative 显示层：模型 shadow，state 映射显示字段，bridge 不写 TrackTable")

# ═══════════════════════════════════════════════════════════════════
# 5. off 降级
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("5 off 降级")
	_set_mode("off")
	var br = _make_bridge()
	_eq(br.sensor_shadow_mode, "off", "mode=off")
	_eq(br.sensor_shadow_ready, false, "ready=false")
	_eq(br.sensor_shadow_view().size(), 0, "view 空")
	_eq(br.sensor_shadow_summary().size(), 0, "summary 空")
	var cmp: Dictionary = br.sensor_compare([])
	_eq(bool(cmp.get("ok", true)), false, "off 时 compare.ok=false")
	var st = _make_state(br)
	_eq(st.fw_sensor_shadow_ready, false, "state.fw_sensor_shadow_ready=false")
	_eq(st.fw_sensor_shadow.size(), 0, "state.fw_sensor_shadow 空")
	_eq(st.fw_sensor_compare.size(), 0, "state.fw_sensor_compare 空")
	_clear_env()
	_data_line("off", "V17_SENSOR_AUTHORITY=off：无 shadow；compare 不可用；不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 6. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("6 JSON")
	_clear_env()
	var br = _make_bridge()
	var st = _make_state(br)
	var js := JSON.stringify(br.sensor_shadow_view())
	_ok(js.length() > 2000, "sensor_shadow_view JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "view JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("advisory_contacts") is Array, "回读 advisory_contacts")
		_ok(pd.get("channels") is Array, "回读 channels")
		_ok(pd.get("writes") is Dictionary, "回读 writes")
	var cjs := JSON.stringify(st.fw_sensor_compare)
	_ok(cjs.length() > 500, "fw_sensor_compare JSON", "len=%d" % cjs.length())
	_ok(JSON.parse_string(cjs) is Dictionary, "compare JSON 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	var bp = JSON.parse_string(bs)
	_ok(bp is Dictionary, "fw_bridge_state 回读")
	if bp is Dictionary:
		_ok((bp.get("sensor_shadow", {}) as Dictionary).get("counts") is Dictionary,
			"bridge_state 含 sensor_shadow.counts")
	_clear_env()
	_data_line("json", "view/compare/bridge_state JSON 可回读")
