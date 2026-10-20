extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R6-DISPLAY-CORE-1 headless probe：物理显示数据接口（state 只读）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_physics_display_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
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
	print("R6-DISPLAY-CORE-1 PROBE · 物理显示数据接口（state 只读）")
	print("════════════════════════════════════════════════════════════")
	_test_available_enabled()
	_test_frame_own_flagship()
	_test_targets_and_helpers()
	_test_mapping_and_missing()
	_test_display_override()
	_test_modes()
	_test_refresh_and_v15_unchanged()
	_test_json_and_status()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PHYSICS DISPLAY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PHYSICS DISPLAY PROBE FAILED")
		quit(1)
	else:
		print("V17 PHYSICS DISPLAY PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f diff=%.6f" % [actual, expected, diff])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _set_physics_mode(mode: String) -> void:
	OS.set_environment("V17_PHYSICS", mode)

func _set_display(flag: String) -> void:
	OS.set_environment("DSH_PHYSICS_DISPLAY", flag)

func _clear_env() -> void:
	OS.set_environment("V17_PHYSICS", "")
	OS.set_environment("DSH_PHYSICS_DISPLAY", "")

func _make_state(mode := "authoritative", display := ""):
	_set_physics_mode(mode)
	_set_display(display)
	var br = BridgeScript.new()
	var ok: bool = br.boot()
	_ok(ok, "bridge.boot", str(br.errors))
	var st = StateScript.new()
	if st.prelude_open:
		st.prelude_skip()
	st.framework = br
	st.fw_sync(0.0)
	return st

func _vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO

func _track_snapshot(st) -> Dictionary:
	var tr: Dictionary = st.tracks[st.selected] if not st.tracks.is_empty() else {}
	return {
		"r": str(tr.get("r", Vector3.ZERO)),
		"v": str(tr.get("v", Vector3.ZERO)),
		"level": int(tr.get("level", 0)),
		"clock": float(st.clock),
		"count": st.tracks.size(),
	}

func _auth_view(st) -> Dictionary:
	return st.fw_physics_authoritative

# ═══════════════════════════════════════════════════════════════════
# 1. available / enabled
# ═══════════════════════════════════════════════════════════════════

func _test_available_enabled() -> void:
	_section_begin("1 available / enabled")
	var st = _make_state("authoritative", "")
	_eq(st.physics_display_available(), true, "authoritative 且 ready → available=true")
	_eq(st.physics_display_enabled(), true, "默认 enabled=true")
	_ok(st.fw_physics_display.size() > 0, "state.fw_physics_display 非空（fw_sync 刷新）")
	var frame: Dictionary = st.physics_display_frame()
	for key in ["schema", "available", "enabled", "mode", "requested_mode", "display_switched",
			"source", "frame", "tau", "physics_t", "delta_t_s", "replay_ok", "note",
			"mapping_note", "own", "flagship", "entries", "missing", "warnings"]:
		_ok(frame.has(key), "frame 含字段: " + key)
	_eq(String(frame.get("schema", "")), "v17_physics_display.v1", "schema")
	_eq(String(frame.get("mode", "")), "authoritative", "frame.mode=authoritative")
	_eq(bool(frame.get("display_switched", true)), false, "display_switched=false（未切换）")
	_eq(bool(frame.get("replay_ok", true)), false, "replay_ok=false（不用于回放）")
	_ok(String(frame.get("note", "")).contains("回放"), "note 明示不用于回放")
	_ok(String(frame.get("mapping_note", "")).contains("missing"), "mapping_note 说明缺失")
	_ok(frame.get("frame", {}) is Dictionary, "frame.frame 坐标系信息")
	_ok(float(frame.get("tau", -1.0)) >= 0.0, "tau 有效")
	_ok(frame.get("physics_t") != null, "physics_t 存在")
	_clear_env()
	_data_line("available", "authoritative ready → available/enabled=true；frame 字段齐全")

# ═══════════════════════════════════════════════════════════════════
# 2. own / flagship
# ═══════════════════════════════════════════════════════════════════

func _test_frame_own_flagship() -> void:
	_section_begin("2 own / flagship")
	var st = _make_state("authoritative", "")
	var frame: Dictionary = st.physics_display_frame()
	var own: Dictionary = frame.get("own", {})
	_eq(String(own.get("track_id", "")), "1001", "own track_id=1001")
	_eq(String(own.get("entity_id", "")), "harmattan", "own entity_id=harmattan")
	_eq(String(own.get("role", "")), "own", "own role")
	_near(_vec(own.get("board_r", [])).length(), 0.0, 1.0e-6, "own board_r=(0,0,0)")
	_near(_vec(own.get("board_v", [])).length(), 0.0, 1.0e-6, "own board_v=0")
	_near(float(own.get("range_km", -1.0)), 0.0, 1.0e-6, "own range=0")
	var flag: Dictionary = frame.get("flagship", {})
	_eq(String(flag.get("track_id", "")), "1000", "flagship track_id=1000")
	_eq(String(flag.get("entity_id", "")), "apsis", "flagship entity=apsis")
	_eq(String(flag.get("role", "")), "flagship", "flagship role")
	var view: Dictionary = _auth_view(st)
	var vflag: Dictionary = view.get("flagship", {})
	_near((_vec(flag.get("board_r", [])) - _vec(vflag.get("board_r", []))).length(), 0.0, 1.0e-6,
		"flagship board_r 与 authoritative view 一致")
	_clear_env()
	_data_line("own/flagship", "own 1001(harmattan) board=0；flagship 1000(apsis) 与 view 一致")

# ═══════════════════════════════════════════════════════════════════
# 3. targets / 辅助
# ═══════════════════════════════════════════════════════════════════

func _test_targets_and_helpers() -> void:
	_section_begin("3 targets / helpers")
	var st = _make_state("authoritative", "")
	var frame: Dictionary = st.physics_display_frame()
	var entries: Dictionary = frame.get("entries", {})
	_ok(entries.size() >= 3, "entries ≥3", str(entries.size()))
	var e: Dictionary = entries.get("2001", {})
	_ok(not e.is_empty(), "entries 含 2001(summons_4471)")
	_eq(String(e.get("entity_id", "")), "summons_4471", "2001 entity_id=summons_4471")
	_eq(String(e.get("role", "")), "target", "2001 role=target")
	_eq(String(e.get("batch", "")), "2001", "2001 batch")
	var view: Dictionary = _auth_view(st)
	var targets: Dictionary = {}
	for raw in (view.get("targets", []) as Array):
		targets[String((raw as Dictionary).get("entity_id", ""))] = raw
	var vt: Dictionary = targets.get("summons_4471", {})
	_near((_vec(e.get("board_r", [])) - _vec(vt.get("board_r", []))).length(), 0.0, 1.0e-6,
		"2001 board_r 与 view 一致")
	_near(float(e.get("range_km", 0.0)), float(vt.get("range_km", -1.0)), 1.0e-6,
		"2001 range 与 view 一致")
	_near(_vec(e.get("board_r", [])).length(), float(e.get("range_km", 0.0)), 1.0e-3,
		"|board_r|=range")
	var bearing := float(e.get("bearing_deg", -1.0))
	_ok(bearing >= 0.0 and bearing < 360.0, "2001 bearing∈[0,360)", str(bearing))
	# helpers
	var brd: Array = st.physics_display_board_for("2001")
	_near((_vec(brd) - _vec(e.get("board_r", []))).length(), 0.0, 1.0e-6,
		"physics_display_board_for(2001)")
	var vel: Array = st.physics_display_velocity_for("2001")
	_near((_vec(vel) - _vec(e.get("board_v", []))).length(), 0.0, 1.0e-6,
		"physics_display_velocity_for(2001)")
	var brd_entity: Array = st.physics_display_board_for("summons_4471")
	_near((_vec(brd_entity) - _vec(e.get("board_r", []))).length(), 0.0, 1.0e-6,
		"board_for(entity_id) 同样可取")
	var own_brd: Array = st.physics_display_board_for("1001")
	_near(_vec(own_brd).length(), 0.0, 1.0e-6, "board_for(1001) 本舰=0")
	var flag_brd: Array = st.physics_display_board_for("apsis")
	_ok(flag_brd.size() >= 3, "board_for(apsis) 可用")
	var entry_apsis: Dictionary = st.physics_display_entry_for("apsis")
	_eq(String(entry_apsis.get("role", "")), "flagship", "entry_for(apsis).role=flagship")
	_clear_env()
	_data_line("targets", "2001(summons_4471) board/range/bearing 与 view 一致；board_for/velocity_for/entry_for")

# ═══════════════════════════════════════════════════════════════════
# 4. 映射 / 缺失
# ═══════════════════════════════════════════════════════════════════

func _test_mapping_and_missing() -> void:
	_section_begin("4 映射 / 缺失")
	var st = _make_state("authoritative", "")
	var frame: Dictionary = st.physics_display_frame()
	var entries: Dictionary = frame.get("entries", {})
	var missing: Array = frame.get("missing", [])
	for tid in ["1000", "1001", "2001"]:
		_ok(entries.has(tid) or missing.has(tid), "track %s 有映射或明确缺失" % tid)
	_ok(missing.size() > 0, "存在明确缺失条目（不伪造）", str(missing))
	# 无实体/非 ship 的 track 应缺失
	_ok(("9002" in missing) or (not entries.has("9002")), "9002 不伪造（缺失/无对应）")
	_eq(st.physics_display_board_for("9002"), [], "board_for(9002) 空")
	_eq(st.physics_display_velocity_for("9002"), [], "velocity_for(9002) 空")
	_eq(st.physics_display_entry_for("no_such_id"), {}, "entry_for(未知) 空")
	_eq(st.physics_display_board_for("no_such_id"), [], "board_for(未知) 空")
	# 映射表：entries 的 track_id/batch/entity_id 字段
	for raw in entries.values():
		var e: Dictionary = raw
		_ok(String(e.get("track_id", "")) != "", "entry.track_id 非空")
		_ok(String(e.get("entity_id", "")) != "", "entry.entity_id 非空")
		_ok(String(e.get("role", "")) in ["own", "flagship", "target"], "entry.role 合法")
	_clear_env()
	_data_line("mapping", "entries=%d missing=%d（9002 等不伪造）" % [entries.size(), missing.size()])

# ═══════════════════════════════════════════════════════════════════
# 5. DSH_PHYSICS_DISPLAY 覆盖
# ═══════════════════════════════════════════════════════════════════

func _test_display_override() -> void:
	_section_begin("5 显示开关覆盖")
	var st = _make_state("authoritative", "0")
	_eq(st.physics_display_available(), true, "override=0 时 available 仍 true")
	_eq(st.physics_display_enabled(), false, "DSH_PHYSICS_DISPLAY=0 → enabled=false")
	_eq(st.physics_display_frame(), {}, "disabled 时 frame 为空")
	_eq(st.fw_physics_display.size(), 0, "disabled 时 fw_physics_display 为空")
	_eq(st.physics_display_board_for("2001"), [], "disabled 时 board_for 空")
	var status: Dictionary = st.physics_display_status()
	_eq(status.get("enabled"), false, "status.enabled=false")
	_ok(String(status.get("reason", "")).contains("关闭"), "status.reason 说明关闭",
		String(status.get("reason", "")))
	# 再启用
	_set_display("1")
	st.fw_sync(0.0)
	_eq(st.physics_display_enabled(), true, "DSH_PHYSICS_DISPLAY=1 → enabled=true")
	_ok(st.fw_physics_display.size() > 0, "重新启用后 fw_physics_display 非空")
	_ok(st.physics_display_board_for("2001").size() >= 3, "重新启用后 board_for 可用")
	_clear_env()
	_data_line("override", "0 关闭（空/[]/reason）/ 1 重新开启；available 与开关解耦")

# ═══════════════════════════════════════════════════════════════════
# 6. 模式（shadow / off）
# ═══════════════════════════════════════════════════════════════════

func _test_modes() -> void:
	_section_begin("6 模式")
	var shadow = _make_state("shadow", "")
	_eq(shadow.physics_display_available(), false, "shadow → available=false")
	_eq(shadow.physics_display_enabled(), false, "shadow → enabled=false")
	_eq(shadow.physics_display_frame(), {}, "shadow frame 空")
	_eq(shadow.fw_physics_display.size(), 0, "shadow fw_physics_display 空")
	_ok(String(shadow.physics_display_status().get("reason", "")).contains("authoritative"),
		"shadow status.reason 说明需要 authoritative")
	var off = _make_state("off", "")
	_eq(off.physics_display_available(), false, "off → available=false")
	_eq(off.physics_display_enabled(), false, "off → enabled=false")
	_eq(off.physics_display_frame(), {}, "off frame 空")
	_clear_env()
	_data_line("modes", "shadow/off 均 available/enabled=false、frame 空、不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 7. 刷新 / V15 不变
# ═══════════════════════════════════════════════════════════════════

func _test_refresh_and_v15_unchanged() -> void:
	_section_begin("7 刷新 / V15 不变")
	var st = _make_state("authoritative", "")
	var snap0 := _track_snapshot(st)
	var t0 := float(st.physics_display_frame().get("physics_t", -1.0))
	st.framework.sync(60.0)
	st.fw_sync(0.0)
	var frame: Dictionary = st.physics_display_frame()
	_near(float(frame.get("physics_t", 0.0)), 60.0, 1.0e-9, "fw_sync 后 physics_t=60（frame 刷新）")
	_ok(float(frame.get("physics_t", 0.0)) > t0, "frame 随时间刷新")
	_ok(st.fw_physics_display.size() > 0, "fw_physics_display 刷新")
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_eq(snap1.get("count"), snap0.get("count"), "V15 航迹数不变")
	_clear_env()
	_data_line("refresh/v15", "frame/字段随时间刷新；V15 tracks/等级/clock 不变")

# ═══════════════════════════════════════════════════════════════════
# 8. JSON / status
# ═══════════════════════════════════════════════════════════════════

func _test_json_and_status() -> void:
	_section_begin("8 JSON / status")
	var st = _make_state("authoritative", "")
	var frame: Dictionary = st.physics_display_frame()
	var js := JSON.stringify(frame)
	_ok(js.length() > 1000, "frame JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "frame JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("own") is Dictionary, "回读 own")
		_ok(pd.get("entries") is Dictionary, "回读 entries")
		_ok(pd.get("missing") is Array, "回读 missing")
		_ok(pd.get("frame") is Dictionary, "回读 frame")
	var status: Dictionary = st.physics_display_status()
	for key in ["available", "enabled", "mode", "requested_mode", "display_switched",
			"override", "reason"]:
		_ok(status.has(key), "status 含 " + key)
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	var bp = JSON.parse_string(bs)
	_ok(bp is Dictionary, "fw_bridge_state 回读")
	if bp is Dictionary:
		_ok((bp.get("physics_display", {}) as Dictionary).has("entries"),
			"fw_bridge_state 含 physics_display.entries")
	_clear_env()
	_data_line("json/status", "frame/status/fw_bridge_state JSON 可回读")
