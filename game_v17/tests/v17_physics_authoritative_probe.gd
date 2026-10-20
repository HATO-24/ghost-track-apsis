extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R6-AUTH-1 headless probe：authoritative 物理适配层（三模式/相对板/compare/回退）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_physics_authoritative_probe.gd
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
	OS.set_environment("V17_PHYSICS", "authoritative")
	print("════════════════════════════════════════════════════════════")
	print("R6-AUTH-1 PROBE · authoritative 物理适配层")
	print("════════════════════════════════════════════════════════════")
	_test_modes()
	_test_authoritative_view()
	_test_compare()
	_test_state_fields()
	_test_nav_provider()
	_test_v15_unchanged()
	_test_fallback()
	_test_off_mode()
	_test_json()
	_test_restart()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PHYSICS AUTH PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PHYSICS AUTH PROBE FAILED")
		quit(1)
	else:
		print("V17 PHYSICS AUTH PROBE OK")
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

func _set_mode(mode: String) -> void:
	OS.set_environment("V17_PHYSICS", mode)

func _clear_env() -> void:
	OS.set_environment("V17_PHYSICS", "")
	OS.set_environment("V17_PHYSICS_FORCE_FAIL", "")

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

func _vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO

func _view_targets(view: Dictionary) -> Dictionary:
	var map := {}
	for raw in (view.get("targets", []) as Array):
		map[String((raw as Dictionary).get("entity_id", ""))] = raw
	return map

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
# 1. 三模式
# ═══════════════════════════════════════════════════════════════════

func _test_modes() -> void:
	_section_begin("1 三模式")
	_clear_env()
	var br = _make_bridge()
	_eq(br.physics_requested_mode, "authoritative", "默认 requested=authoritative")
	_eq(br.physics_mode, "authoritative", "默认 mode=authoritative")
	var av: Dictionary = br.physics_authoritative_view()
	_eq(bool(av.get("ready", true)), true, "默认 authoritative.ready=true")
	_eq(String(av.get("mode", "")), "authoritative", "默认 view.mode=authoritative")
	_set_mode("shadow")
	var bs = _make_bridge()
	_eq(bs.physics_requested_mode, "shadow", "shadow requested=shadow")
	_eq(bs.physics_mode, "shadow", "shadow mode=shadow")
	var sv: Dictionary = bs.physics_authoritative_view()
	_eq(bool(sv.get("ready", true)), false, "shadow 下 authoritative.ready=false")
	_eq(String(sv.get("mode", "")), "shadow", "shadow 下 view.mode=shadow")
	_ok(String(sv.get("error", "")).contains("未启用"), "shadow 下 error 明示未启用",
		String(sv.get("error", "")))
	# authoritative
	_set_mode("authoritative")
	var ba = _make_bridge()
	_eq(ba.physics_requested_mode, "authoritative", "requested=authoritative")
	_eq(ba.physics_mode, "authoritative", "mode=authoritative")
	_eq(ba.physics_ready, true, "authoritative ready")
	var va: Dictionary = ba.physics_authoritative_view()
	_eq(bool(va.get("ready", false)), true, "authoritative view.ready=true")
	_eq(bool(va.get("authoritative", false)), true, "view.authoritative=true")
	_eq(bool(va.get("display_switched", true)), false, "display_switched=false（显示层未切换）")
	_eq(va.get("fallback_reason", "x"), "", "authoritative 无回落原因")
	for key in ["schema", "mode", "requested_mode", "ready", "display_switched", "source",
			"frame", "t", "own", "flagship", "targets", "flags", "warnings", "error"]:
		_ok(va.has(key), "authoritative view 含字段: " + key)
	_clear_env()
	_data_line("modes", "authoritative（默认）/ shadow / off 三模式")

# ═══════════════════════════════════════════════════════════════════
# 2. authoritative 相对板状态
# ═══════════════════════════════════════════════════════════════════

func _test_authoritative_view() -> void:
	_section_begin("2 相对板状态")
	_set_mode("authoritative")
	var br = _make_bridge()
	var view: Dictionary = br.physics_authoritative_view()
	var own: Dictionary = view.get("own", {})
	_eq(String(own.get("entity_id", "")), "harmattan", "own=harmattan")
	_eq(String(own.get("role", "")), "own", "own.role=own")
	_near(_vec(own.get("board_r", [])).length(), 0.0, 1.0e-6, "own board_r=0")
	_near(float(own.get("range_km", -1.0)), 0.0, 1.0e-6, "own range=0")
	var flagship: Dictionary = view.get("flagship", {})
	_eq(String(flagship.get("entity_id", "")), "apsis", "flagship=apsis")
	_ok(flagship.get("state_earth_eci") is Dictionary, "flagship 有 ECI 状态")
	var targets: Dictionary = _view_targets(view)
	_ok(targets.has("summons_4471"), "targets 含 summons_4471")
	for eid in ["summons_4471", "ceres_2", "ferry"]:
		_ok(targets.has(eid), "target 存在: " + eid)
	var tgt: Dictionary = targets.get("summons_4471", {})
	for key in ["entity_id", "role", "source", "age_s", "state_earth_eci", "state_earth_rot",
			"board_r", "board_v", "range_km", "bearing_deg", "elevation_deg", "finite"]:
		_ok(tgt.has(key), "target 含字段: " + key)
	_ok(float(tgt.get("range_km", 0.0)) > 0.0, "target range>0",
		str(tgt.get("range_km")))
	_near(_vec(tgt.get("board_r", [])).length(), float(tgt.get("range_km", 0.0)), 1.0e-3,
		"|board_r| = range_km")
	var bearing := float(tgt.get("bearing_deg", -1.0))
	_ok(bearing >= 0.0 and bearing < 360.0, "bearing 在 [0,360)", str(bearing))
	_ok(absf(float(tgt.get("elevation_deg", 0.0))) <= 90.0, "elevation 在 [-90,90]")
	# 与 physics_view 的 earth_rot 相对差一致
	var phys_by_id := {}
	for raw in (br.physics_view().get("entities", []) as Array):
		phys_by_id[String((raw as Dictionary).get("id", ""))] = raw
	var own_rot: Dictionary = (phys_by_id.get("harmattan", {}) as Dictionary).get("state_earth_rot", {})
	var tgt_rot: Dictionary = (phys_by_id.get("summons_4471", {}) as Dictionary).get("state_earth_rot", {})
	var dr := _vec(tgt_rot.get("r", [])) - _vec(own_rot.get("r", []))
	_near((_vec(tgt.get("board_r", [])) - dr).length(), 0.0, 1.0e-3,
		"board_r = target earth_rot - own earth_rot")
	_eq(String(view.get("frame", {}).get("inertial", "")), "earth_eci", "frame.inertial")
	_eq(String(view.get("frame", {}).get("rotating", "")), "earth_rot", "frame.rotating")
	_clear_env()
	_data_line("relative", "own/flagship=apsis/targets=%d · board=earth_rot 相对 own · bearing/elev/age" % targets.size())

# ═══════════════════════════════════════════════════════════════════
# 3. compare（物理 vs V15，只读）
# ═══════════════════════════════════════════════════════════════════

func _test_compare() -> void:
	_section_begin("3 compare")
	_set_mode("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	var t_now: float = st.tau()
	var v15_own: Dictionary = st.own_at(t_now)
	var rows: Array = []
	for raw in st.tracks:
		var tr: Dictionary = raw
		if bool(tr.get("own", false)):
			continue
		var bp: Vector3 = st.board_pos(tr, t_now)
		var bv: Vector3 = st.board_vel(tr, t_now)
		rows.append({"track_id": String(tr.get("id", "")), "entity_id": String(tr.get("entity_id", "")),
			"board_r": [bp.x, bp.y, bp.z], "board_v": [bv.x, bv.y, bv.z]})
	var cmp: Dictionary = br.physics_adapter_compare(v15_own, rows)
	_eq(bool(cmp.get("ok", false)), true, "compare.ok")
	_eq(bool(cmp.get("authoritative_ready", false)), true, "compare.authoritative_ready")
	_eq(bool(cmp.get("display_switched", true)), false, "compare.display_switched=false")
	for key in ["schema", "mode", "requested_mode", "thresholds", "own", "tracks", "summary",
			"frame_mismatch_note", "source"]:
		_ok(cmp.has(key), "compare 含字段: " + key)
	var cmp_rows: Array = cmp.get("tracks", [])
	var sum: Dictionary = cmp.get("summary", {})
	_ok(int(sum.get("compared", 0)) > 0, "compared>0", str(sum.get("compared")))
	_eq(int(sum.get("compared", 0)), cmp_rows.size(), "summary.compared=rows")
	_ok(cmp_rows.size() > 0, "有对比行", str(cmp_rows.size()))
	var first: Dictionary = cmp_rows[0]
	for key in ["track_id", "entity_id", "physics", "v15", "errors"]:
		_ok(first.has(key), "行含字段: " + key)
	_ok(first.get("errors", {}) is Dictionary, "errors 为 Dictionary")
	var errors: Dictionary = first.get("errors", {})
	for key in ["range_km", "bearing_deg", "position_km"]:
		_ok(errors.has(key), "errors 含 " + key)
		_ok(float(errors.get(key, -1.0)) >= 0.0, "errors." + key + " >=0")
	_ok(sum.has("max_range_err_km") and sum.has("max_bearing_err_deg") and sum.has("max_position_err_km"),
		"summary 含 max 误差")
	_ok(sum.get("within_threshold") is bool, "within_threshold 为 bool")
	for key in ["range_km", "bearing_deg", "position_km"]:
		_ok((cmp.get("thresholds", {}) as Dictionary).has(key), "thresholds 含 " + key)
	_ok(String(cmp.get("frame_mismatch_note", "")).contains("未切换"), "compare 明示坐标系未切换")
	_clear_env()
	_data_line("compare", "compared=%d max_range_err=%.3f km · thresholds · 只读" % [
		int(sum.get("compared", 0)), float(sum.get("max_range_err_km", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 4. state 字段
# ═══════════════════════════════════════════════════════════════════

func _test_state_fields() -> void:
	_section_begin("4 state 字段")
	_set_mode("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	_ok(st.fw_physics_authoritative.size() > 0, "state.fw_physics_authoritative 非空")
	_eq(bool(st.fw_physics_authoritative.get("ready", false)), true,
		"fw_physics_authoritative.ready")
	_ok(st.fw_physics_adapter.size() > 0, "state.fw_physics_adapter 非空（fw_sync 自动对比）")
	_eq(bool(st.fw_physics_adapter.get("ok", false)), true, "fw_physics_adapter.ok")
	_ok(int(st.fw_physics_adapter.get("summary", {}).get("compared", 0)) > 0,
		"fw_physics_adapter.compared>0")
	# 旧字段不变
	_eq(st.fw_physics_ready, true, "旧 fw_physics_ready")
	_eq(st.fw_nav_ready, true, "旧 fw_nav_ready")
	_eq(st.fw_physics_mode, "authoritative", "fw_physics_mode=authoritative")
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["physics_authoritative", "physics_adapter"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	_clear_env()
	_data_line("state", "fw_physics_authoritative/fw_physics_adapter 只读；旧字段不变")

# ═══════════════════════════════════════════════════════════════════
# 5. 导航 provider（authoritative 下用物理位置）
# ═══════════════════════════════════════════════════════════════════

func _test_nav_provider() -> void:
	_section_begin("5 导航 provider")
	_set_mode("authoritative")
	var br = _make_bridge()
	var pos: Dictionary = br.nav.resolve_positions()
	_near(_vec(pos.get("l1", [])).length(), 326381.0, 5.0,
		"authoritative nav l1≈physics 326,381")
	_near(_vec(pos.get("geo", [])).length(), 42164.0, 2.0, "authoritative nav geo=42,164")
	_near(_vec(pos.get("l4", [])).length(), 384400.0, 5.0, "authoritative nav l4=384,400")
	var routes: Dictionary = br.nav_plan_routes("l1", "geo")
	_eq(bool(routes.get("ok", false)), true, "provider 下路线规划仍正常（抽象成本）")
	_eq((br.navigation_view().get("planned_maneuvers", []) as Array).size(), 0,
		"不自动创建/执行机动")
	_clear_env()
	_data_line("nav", "authoritative：节点位置=physics（l1=326,381）；成本仍抽象；不自动执行")

# ═══════════════════════════════════════════════════════════════════
# 6. V15 tracks 不被写
# ═══════════════════════════════════════════════════════════════════

func _test_v15_unchanged() -> void:
	_section_begin("6 V15 tracks 不变")
	_set_mode("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	var snap0 := _track_snapshot(st)
	var tr0: Dictionary = st.tracks[st.selected]
	var r0 := str(tr0.get("r", Vector3.ZERO))
	br.sync(120.0)
	st.fw_sync(0.0)
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("identity"), snap0.get("identity"), "V15 身份不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_eq(snap1.get("count"), snap0.get("count"), "V15 航迹数不变")
	_ok(st.fw_physics_authoritative.get("ready", false), "authoritative 仍 ready")
	_ok(st.fw_physics_adapter.size() > 0, "fw_sync 后 adapter 更新")
	_clear_env()
	_data_line("v15", "authoritative sync 120s：V15 tracks/等级/身份/clock 不变")

# ═══════════════════════════════════════════════════════════════════
# 7. 回退（authoritative 初始化失败 → shadow）
# ═══════════════════════════════════════════════════════════════════

func _test_fallback() -> void:
	_section_begin("7 回退")
	OS.set_environment("V17_PHYSICS", "authoritative")
	OS.set_environment("V17_PHYSICS_FORCE_FAIL", "1")
	var br = _make_bridge()
	_eq(br.physics_requested_mode, "authoritative", "requested=authoritative")
	_eq(br.physics_mode, "shadow", "初始化失败回落 mode=shadow")
	_ok(String(br.physics_fallback_reason).contains("回落"), "fallback_reason 明示回落",
		br.physics_fallback_reason)
	var av: Dictionary = br.physics_authoritative_view()
	_eq(bool(av.get("ready", true)), false, "回退后 authoritative.ready=false")
	_eq(String(av.get("mode", "")), "shadow", "回退后 view.mode=shadow")
	_ok(String(av.get("fallback_reason", "")).contains("回落"), "view 带 fallback_reason")
	# 不崩溃且基本能力可用
	_ok(br.ready, "回退后 bridge 仍 ready")
	_ok(br.nav_ready, "回退后 nav 仍 ready")
	_clear_env()
	# 恢复后再次 boot 正常
	var br2 = _make_bridge()
	_eq(br2.physics_mode, "authoritative", "默认模式恢复 authoritative")
	_data_line("fallback", "authoritative 初始化失败 → shadow 回落，有 fallback_reason，不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 8. off 模式
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("8 off 模式")
	_set_mode("off")
	var br = _make_bridge()
	_eq(br.physics_mode, "off", "off mode")
	_eq(br.physics_ready, false, "off physics_ready=false")
	_eq(br.physics_view().size(), 0, "off physics_view 空")
	var av: Dictionary = br.physics_authoritative_view()
	_eq(bool(av.get("ready", true)), false, "off authoritative.ready=false")
	_eq(bool(av.get("authoritative", true)), false, "off authoritative flag=false")
	var pos: Dictionary = br.nav.resolve_positions()
	_near(_vec(pos.get("l1", [])).length(), 326283.0, 2.0, "off nav l1 回退 abstract")
	var st = _make_state(br)
	_eq(st.fw_physics_ready, false, "off state.fw_physics_ready=false")
	_eq(st.fw_physics_mode, "off", "off state.fw_physics_mode=off")
	_eq(st.fw_physics_adapter.size(), 0, "off fw_physics_adapter 空")
	_clear_env()
	_data_line("off", "off：无物理、导航回退 abstract、state 字段空，不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 9. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("9 JSON")
	_set_mode("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	var js := JSON.stringify(st.fw_physics_authoritative)
	_ok(js.length() > 1000, "fw_physics_authoritative JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "authoritative JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("own") is Dictionary, "回读 own")
		_ok(pd.get("targets") is Array, "回读 targets")
		_ok(pd.get("flags") is Dictionary, "回读 flags")
	var aj := JSON.stringify(st.fw_physics_adapter)
	_ok(aj.length() > 500, "fw_physics_adapter JSON", "len=%d" % aj.length())
	_ok(JSON.parse_string(aj) is Dictionary, "adapter JSON 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	_clear_env()
	_data_line("json", "authoritative/adapter/bridge_state JSON 可回读")

# ═══════════════════════════════════════════════════════════════════
# 10. restart
# ═══════════════════════════════════════════════════════════════════

func _test_restart() -> void:
	_section_begin("10 restart")
	_set_mode("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	br.sync(120.0)
	st.fw_sync(0.0)
	_ok(float(st.fw_physics.get("t", 0.0)) > 0.0, "restart 前 physics t>0")
	st.fw_restart()
	_eq(st.fw_physics_mode, "authoritative", "restart 后仍 authoritative")
	_eq(bool(st.fw_physics_authoritative.get("ready", false)), true,
		"restart 后 authoritative ready")
	_near(float(st.fw_physics.get("t", -1.0)), 0.0, 1.0e-9, "restart 后 physics t=0")
	var pos: Dictionary = br.nav.resolve_positions()
	_near(_vec(pos.get("l1", [])).length(), 326381.0, 5.0, "restart 后 nav provider 仍用 physics")
	_clear_env()
	_data_line("restart", "authoritative t=0/ready/provider 重绑，不崩溃")
