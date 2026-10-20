extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-AUTHORITY-DISPLAY-1 最小 probe：V2 传感器权威显示（可选路径）+ UNDOCK
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_sensor_authority_display_probe.gd
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
	print("R5-AUTHORITY-DISPLAY-1 PROBE · 传感器权威显示（最小）")
	print("════════════════════════════════════════════════════════════")
	_test_shadow_no_write()
	_test_authoritative_display()
	_test_missing_and_rv()
	_test_off_fallback()
	_test_undock()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SENSOR AUTHORITY DISPLAY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SENSOR AUTHORITY DISPLAY PROBE FAILED")
		quit(1)
	else:
		print("V17 SENSOR AUTHORITY DISPLAY PROBE OK")
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
	OS.set_environment("V17_SENSOR_AUTHORITY", "")
	OS.set_environment("V17_DOCKING", "")

func _set_authority(mode: String) -> void:
	OS.set_environment("V17_SENSOR_AUTHORITY", mode)

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
	return st

func _display_map(st) -> Dictionary:
	var out := {}
	for raw in st.tracks:
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		out[tid] = {
			"level": int(tr.get("level", 0)),
			"identity": String(tr.get("identity", "")),
			"sources": (tr.get("sources", []) as Array).duplicate(),
			"r": str(tr.get("r", Vector3.ZERO)),
			"v": str(tr.get("v", Vector3.ZERO)),
			"threat": String(tr.get("threat", "")),
			"side": String(tr.get("side", "")),
			"role": String(tr.get("role", "")),
			"own": bool(tr.get("own", false)),
		}
	return out

func _advisory_map(br) -> Dictionary:
	var out := {}
	for raw in (br.sensor_shadow_view().get("advisory_contacts", []) as Array):
		var ac: Dictionary = raw
		for key in [String(ac.get("batch", "")), String(ac.get("track_id", ""))]:
			if key != "" and not out.has(key):
				out[key] = ac
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. shadow（默认）不写
# ═══════════════════════════════════════════════════════════════════

func _test_shadow_no_write() -> void:
	_section_begin("1 shadow 不写")
	_clear_env()
	var br = _make_bridge()
	_eq(br.sensor_authority_mode, "shadow", "默认 authority=shadow")
	var disp: Dictionary = br.sensor_authority_display()
	_eq(bool(disp.get("active", true)), false, "shadow display.active=false")
	_eq(bool(disp.get("writes_track_table", true)), false, "display 不写 TrackTable")
	var st = _make_state(br)
	var before := _display_map(st)
	st.fw_sync(0.0)
	var after := _display_map(st)
	_eq(st.fw_sensor_authority, "legacy_v15", "shadow fw_sensor_authority=legacy_v15")
	_eq(st.fw_sensor_authority_diff.size(), 0, "shadow diff 为空")
	_ok(str(before) == str(after), "shadow 显示字段未被写")
	_clear_env()
	_data_line("shadow", "默认 shadow：不写 V15 显示字段，authority=legacy_v15，diff 空")

# ═══════════════════════════════════════════════════════════════════
# 2. authoritative 写显示字段
# ═══════════════════════════════════════════════════════════════════

func _test_authoritative_display() -> void:
	_section_begin("2 authoritative 显示")
	_set_authority("authoritative")
	var br = _make_bridge()
	_eq(br.sensor_authority_requested_mode, "authoritative", "requested=authoritative")
	_eq(br.sensor_authority_mode, "authoritative", "authority=authoritative")
	_eq(br.sensor_shadow_mode, "shadow", "模型仍 shadow（显示层权威）")
	var disp: Dictionary = br.sensor_authority_display()
	_eq(bool(disp.get("active", false)), true, "display.active=true")
	_eq(bool(disp.get("writes_track_table", true)), false, "display 不写 TrackTable")
	_eq(bool(disp.get("display_only", false)), true, "display_only=true")
	var st = _make_state(br)
	var before := _display_map(st)
	var adv := _advisory_map(br)
	st.fw_sync(0.0)
	var after := _display_map(st)
	_eq(st.fw_sensor_authority, "v2_display", "authoritative fw_sensor_authority=v2_display")
	var diff: Dictionary = st.fw_sensor_authority_diff
	_ok(int(diff.get("applied", 0)) > 0, "diff.applied>0", str(diff.get("applied", 0)))
	_ok(int(diff.get("changed", 0)) > 0, "diff.changed>0", str(diff.get("changed", 0)))
	_ok(bool((diff.get("writes_track_table", true)) == false), "diff 不写 TrackTable")
	# 选一个有 advisory 的 track 验证映射
	var target_id := ""
	for tid in after.keys():
		if adv.has(tid):
			target_id = tid
			break
	_ok(target_id != "", "找到可映射 track", target_id)
	if target_id != "":
		var ac: Dictionary = adv[target_id]
		var tr_after: Dictionary = after[target_id]
		_eq(int(tr_after.get("level", -1)), int(ac.get("level", -2)),
			"track %s level 映射" % target_id)
		_eq(String(tr_after.get("identity", "")), String(ac.get("identity", "")),
			"track %s identity 映射" % target_id)
		var adv_sources: Array = (ac.get("sources", []) as Array).duplicate()
		_eq(str(tr_after.get("sources", [])), str(adv_sources),
			"track %s sources(sensor) 映射" % target_id)
		# 不动 r/v/威胁/阵营/任务角色
		var tr_before: Dictionary = before[target_id]
		_eq(String(tr_after.get("r", "")), String(tr_before.get("r", "")),
			"track %s r 不变" % target_id)
		_eq(String(tr_after.get("v", "")), String(tr_before.get("v", "")),
			"track %s v 不变" % target_id)
		_eq(String(tr_after.get("threat", "")), String(tr_before.get("threat", "")),
			"track %s threat 不变" % target_id)
		_eq(String(tr_after.get("side", "")), String(tr_before.get("side", "")),
			"track %s side 不变" % target_id)
		_eq(String(tr_after.get("role", "")), String(tr_before.get("role", "")),
			"track %s role 不变" % target_id)
	# 每帧只改显示字段：再 fw_sync 一次 diff 应 changed 少/0（已映射）
	st.fw_sync(0.0)
	var diff2: Dictionary = st.fw_sensor_authority_diff
	_ok(int(diff2.get("applied", 0)) > 0, "二次 fw_sync 仍 applied>0")
	_eq(int(diff2.get("changed", -1)), 0, "二次 fw_sync changed=0（已映射）")
	_clear_env()
	_data_line("authoritative", "applied=%d changed=%d skipped=%d；level/identity/sources 映射；r/v/threat/side/role 不变" % [
		int(diff.get("applied", 0)), int(diff.get("changed", 0)),
		int(diff.get("skipped_missing", 0))])

# ═══════════════════════════════════════════════════════════════════
# 3. 缺失不写 / rv 保护
# ═══════════════════════════════════════════════════════════════════

func _test_missing_and_rv() -> void:
	_section_begin("3 缺失 / rv 保护")
	_set_authority("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	var before := _display_map(st)
	var rv_before := {}
	for tid in before.keys():
		rv_before[tid] = {"r": String(before[tid]["r"]), "v": String(before[tid]["v"])}
	st.fw_sync(0.0)
	var after := _display_map(st)
	var diff: Dictionary = st.fw_sensor_authority_diff
	_ok(int(diff.get("skipped_missing", 0)) >= 1, "存在缺失跳过（不伪造）",
		str(diff.get("skipped_missing", 0)))
	var missing_ids: Array = []
	for tid in after.keys():
		if not _advisory_map(br).has(tid):
			missing_ids.append(tid)
	_ok(missing_ids.size() >= 1, "缺失 track 列表", str(missing_ids))
	for tid in missing_ids:
		_eq(int(after[tid]["level"]), int(before[tid]["level"]), "缺失 track %s level 不变" % tid)
		_eq(String(after[tid]["identity"]), String(before[tid]["identity"]),
			"缺失 track %s identity 不变" % tid)
	# 所有 track r/v 不变
	for tid in after.keys():
		_eq(String(after[tid]["r"]), String(rv_before[tid]["r"]), "track %s r 不变" % tid)
		_eq(String(after[tid]["v"]), String(rv_before[tid]["v"]), "track %s v 不变" % tid)
	_clear_env()
	_data_line("missing", "skipped_missing=%d（缺失不写）；全 track r/v 不变" % int(diff.get("skipped_missing", 0)))

# ═══════════════════════════════════════════════════════════════════
# 4. off 回退
# ═══════════════════════════════════════════════════════════════════

func _test_off_fallback() -> void:
	_section_begin("4 off 回退")
	_set_authority("off")
	var br = _make_bridge()
	_eq(br.sensor_authority_mode, "off", "off authority=off")
	var st = _make_state(br)
	var before := _display_map(st)
	st.fw_sync(0.0)
	var after := _display_map(st)
	_eq(st.fw_sensor_authority, "off", "off fw_sensor_authority=off")
	_eq(st.fw_sensor_authority_diff.size(), 0, "off diff 空")
	_ok(str(before) == str(after), "off 不写显示字段")
	_clear_env()
	_data_line("off", "off：不写、diff 空、authority=off；不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 5. UNDOCK 包装
# ═══════════════════════════════════════════════════════════════════

func _test_undock() -> void:
	_section_begin("5 UNDOCK")
	_clear_env()
	var br = _make_bridge()
	var sel: Dictionary = br.docking_select_port("chronos-dock-a")
	_ok(bool(sel.get("ok", false)), "select chronos-dock-a")
	var u1: Dictionary = br.docking_undock()
	_ok(u1.has("ok"), "bridge.docking_undock 返回 ok 字段", str(u1.get("reason", "")))
	var st = _make_state(br)
	var u2: Dictionary = st.fw_docking_undock()
	_ok(u2.has("ok"), "state.fw_docking_undock 返回 ok 字段", str(u2.get("reason", "")))
	_ok(st.fw_docking.size() > 0, "undock 后 fw_docking 仍刷新")
	# off：无实例 → ok=false
	OS.set_environment("V17_DOCKING", "off")
	_clear_env()
	OS.set_environment("V17_DOCKING", "off")
	var br_off = _make_bridge()
	var u3: Dictionary = br_off.docking_undock()
	_eq(bool(u3.get("ok", true)), false, "docking=off 时 undock ok=false")
	var st_off = _make_state(br_off)
	var u4: Dictionary = st_off.fw_docking_undock()
	_eq(bool(u4.get("ok", true)), false, "docking=off 时 state undock ok=false")
	_clear_env()
	_data_line("undock", "有实例返回模型结果（not_docked 时 ok=false+state）；无实例 ok=false；不崩溃")

# ═══════════════════════════════════════════════════════════════════
# 6. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("6 JSON")
	_set_authority("authoritative")
	var br = _make_bridge()
	var st = _make_state(br)
	st.fw_sync(0.0)
	var djs := JSON.stringify(st.fw_sensor_authority_diff)
	_ok(djs.length() > 300, "diff JSON", "len=%d" % djs.length())
	_ok(JSON.parse_string(djs) is Dictionary, "diff JSON 回读")
	var ajs := JSON.stringify(st.fw_sensor_authority_display())
	_ok(ajs.length() > 500, "authority display JSON", "len=%d" % ajs.length())
	_ok(JSON.parse_string(ajs) is Dictionary, "authority display JSON 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 6000, "fw_bridge_state JSON", "len=%d" % bs.length())
	var bp = JSON.parse_string(bs)
	_ok(bp is Dictionary, "fw_bridge_state 回读")
	if bp is Dictionary:
		_ok(String((bp as Dictionary).get("sensor_authority", "")) == "v2_display",
			"bridge_state sensor_authority=v2_display")
		_ok((bp as Dictionary).get("sensor_authority_diff") is Dictionary,
			"bridge_state sensor_authority_diff")
	_clear_env()
	_data_line("json", "diff/authority display/fw_bridge_state JSON 可回读")
