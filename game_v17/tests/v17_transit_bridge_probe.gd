extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 阶段2-CORE-B 最小 probe：transit 场景 + L4→L1 转移接 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_transit_bridge_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；默认 legacy，不接 HUD。
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
	print("STAGE2-CORE-B PROBE · transit 场景 + 转移接 bridge/state")
	print("════════════════════════════════════════════════════════════")
	var t0 := Time.get_ticks_msec()
	_test_legacy()
	_test_transit()
	_test_ticks()
	_test_fallback()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("probe elapsed_ms=%d" % (Time.get_ticks_msec() - t0))
	print("V17 TRANSIT BRIDGE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 TRANSIT BRIDGE PROBE FAILED")
		quit(1)
	else:
		print("V17 TRANSIT BRIDGE PROBE OK")
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

func _arr3_finite(a) -> bool:
	if not (a is Array) or (a as Array).size() < 3:
		return false
	var arr: Array = a
	for i in range(3):
		if not is_finite(float(arr[i])):
			return false
	return true

func _set_scenario(mode: String) -> void:
	OS.set_environment("V17_SCENARIO", mode)

func _clear_env() -> void:
	OS.set_environment("V17_SCENARIO", "")

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

func _scenario_entity_ids(br) -> Array:
	var ids: Array = []
	for raw in br.scenario_entity_list():
		ids.append(String((raw as Dictionary).get("id", "")))
	return ids

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

# ═══════════════════════════════════════════════════════════════════
# 1. legacy 默认
# ═══════════════════════════════════════════════════════════════════

func _test_legacy() -> void:
	_section_begin("1 legacy 默认")
	_clear_env()
	var br = _make_bridge()
	_eq(br.scenario_mode, "legacy", "默认 scenario_mode=legacy")
	_eq(br.scenario_requested_mode, "legacy", "requested=legacy")
	_eq(br.scenario_fallback_reason, "", "legacy 无回落 reason")
	_ok(br.scenario != null, "legacy 场景对象存在")
	_eq(String(br.scenario.id), "l1_supervision_v2", "legacy 场景 id 不变")
	_eq(br.transfer_ready, false, "legacy transfer_ready=false")
	_eq(br.transfer_plan().size(), 0, "legacy 无 transfer 计划")
	_eq(br.transfer_tick(0.0).get("ok", true), false, "legacy transfer_tick ok=false")
	var view: Dictionary = br.scenario_view()
	_eq(String(view.get("mode", "")), "legacy", "scenario_view.mode=legacy")
	_eq(String(view.get("scenario_id", "")), "l1_supervision_v2", "scenario_view id")
	_ok(int(view.get("entity_count", 0)) > 0, "legacy entities >0", str(view.get("entity_count", 0)))
	_ok(int(view.get("station_count", 0)) > 0, "legacy stations >0", str(view.get("station_count", 0)))
	var own: Dictionary = br.own_reference()
	_eq(String(own.get("own_entity", "")), "harmattan", "legacy own=harmattan")
	_eq(String(own.get("batch", "")), "1001", "legacy own batch=1001")
	var st = _make_state(br)
	_eq(st.fw_transfer_ready, false, "state fw_transfer_ready=false")
	_eq(st.fw_transfer.size(), 0, "state fw_transfer 空")
	_ok(st.fw_scenario.size() > 0, "state fw_scenario 非空")
	_eq(String(st.fw_scenario.get("mode", "")), "legacy", "state fw_scenario.mode=legacy")
	_ok(st.fw_scenario_entities.size() > 0, "state fw_scenario_entities 非空")
	_ok(st.fw_scenario_stations.size() > 0, "state fw_scenario_stations 非空")
	# 旧字段不破坏
	_ok(st.fw_sensor_shadow_ready, "legacy 旧 sensor 字段正常")
	_ok(st.fw_physics_ready, "legacy 旧 physics 字段正常")
	_clear_env()
	_data_line("legacy", "id=l1_supervision_v2 own=harmattan(1001) transfer_ready=false entities=%d stations=%d" % [
		int(view.get("entity_count", 0)), int(view.get("station_count", 0))])

# ═══════════════════════════════════════════════════════════════════
# 2. transit
# ═══════════════════════════════════════════════════════════════════

func _test_transit() -> void:
	_section_begin("2 transit")
	_set_scenario("transit")
	var br = _make_bridge()
	_eq(br.scenario_mode, "transit", "transit scenario_mode")
	_eq(br.scenario_requested_mode, "transit", "requested=transit")
	_eq(String(br.scenario.id), "transit_l4_l1", "transit 场景 id")
	_eq(br.transfer_ready, true, "transit transfer_ready=true")
	var plan: Dictionary = br.transfer_plan()
	_ok(plan.size() > 0, "transfer plan 非空")
	_eq(String(plan.get("schema", "")), "v17_transfer_l4_l1.v1", "transfer schema")
	_eq(bool(plan.get("ok", false)), true, "transfer plan.ok")
	var transfer: Dictionary = plan.get("transfer", {})
	_ok(float(transfer.get("tof_days", 0.0)) > 0.0, "tof_days>0")
	_ok(float(transfer.get("total_dv_mps", 0.0)) > 0.0, "total_dv>0")
	_eq(String(transfer.get("method", "")), "lambert_seed_cr3bp_shooting", "method")
	_ok(plan.get("timeline", []) is Array and (plan.get("timeline", []) as Array).size() == 11,
		"timeline 11 点")
	_ok(plan.get("fleet", []) is Array and (plan.get("fleet", []) as Array).size() == 5,
		"fleet 5 舰")
	_ok(plan.get("arrival", {}) is Dictionary, "arrival 字段")
	_eq(bool((plan.get("arrival", {}) as Dictionary).get("ok", false)), true, "arrival.ok")
	# 场景视图
	var sv: Dictionary = br.scenario_view()
	_eq(String(sv.get("mode", "")), "transit", "scenario_view.mode=transit")
	_eq(String(sv.get("scenario_id", "")), "transit_l4_l1", "scenario_view id")
	_eq(String(sv.get("datum", "")), "L4", "datum=L4")
	_eq(String(sv.get("own_entity", "")), "apsis", "own=apsis")
	_ok(int(sv.get("entity_count", 0)) >= 9, "entities ≥9", str(sv.get("entity_count", 0)))
	_ok(int(sv.get("station_count", 0)) >= 4, "stations ≥4", str(sv.get("station_count", 0)))
	_eq(String(sv.get("source_port", "")), "l4_02_hammer", "source_port")
	_eq(String(sv.get("target_port", "")), "l1_meridian_05", "target_port")
	# own reference
	var own: Dictionary = br.own_reference()
	_eq(String(own.get("own_entity", "")), "apsis", "own_reference own=apsis")
	_eq(String(own.get("batch", "")), "1000", "own_reference batch=1000")
	_eq(String(own.get("scenario_mode", "")), "transit", "own_reference mode")
	_eq(String(own.get("source_port", "")), "l4_02_hammer", "own_reference source")
	_eq(String(own.get("target_port", "")), "l1_meridian_05", "own_reference target")
	# 场景实体映射
	var ids := _scenario_entity_ids(br)
	for eid in ["apsis", "harmattan", "ferry", "watchtower", "deepwell",
			"l4_02_hammer", "l1_meridian_05", "l1_anchorage_02", "l1_drydock_01"]:
		_ok(eid in ids, "scenario entity: " + eid)
	for old_id in ["summons_4471", "ceres_2", "chronos_station", "tank_farm"]:
		_ok(not (old_id in ids), "transit 无旧实体: " + old_id)
	_ok(br.scenario_station_list().size() >= 4, "station 列表 ≥4")
	# state
	var st = _make_state(br)
	_ok(st.fw_transfer.size() > 0, "state fw_transfer 非空")
	_eq(st.fw_transfer_ready, true, "state fw_transfer_ready=true")
	_eq(String(st.fw_transfer.get("schema", "")), "v17_transfer_l4_l1.v1", "state transfer schema")
	_eq(String(st.fw_scenario.get("mode", "")), "transit", "state fw_scenario.mode")
	_eq(String(st.fw_scenario.get("scenario_id", "")), "transit_l4_l1", "state scenario id")
	_eq(String(st.fw_own_reference.get("own_entity", "")), "apsis", "state own_reference")
	_ok(st.fw_scenario_entities.size() >= 9, "state scenario_entities ≥9")
	_ok(st.fw_scenario_stations.size() >= 4, "state scenario_stations ≥4")
	# V15 不被写
	var snap0 := _track_snapshot(st)
	var tracks0 := str(st.tracks)
	st.fw_sync(0.0)
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨迹 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 轨迹 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 等级不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_ok(str(st.tracks) == tracks0, "V15 tracks 未被写（transit）")
	# bridge_state
	var bs: Dictionary = br.bridge_state()
	for key in ["scenario_mode", "scenario", "own_reference", "scenario_entities",
			"scenario_stations", "transfer", "transfer_ready"]:
		_ok(bs.has(key), "bridge_state 含 " + key)
	_clear_env()
	_data_line("transit", "TOF=%.2fd Δv=%.1fm/s 入轨=%.3fkm/%.3fkm/s entities=%d stations=%d" % [
		float(transfer.get("tof_days", 0.0)), float(transfer.get("total_dv_mps", 0.0)),
		float((plan.get("arrival", {}) as Dictionary).get("radius_km", 0.0)),
		float((plan.get("arrival", {}) as Dictionary).get("relative_speed_kmps", 0.0)),
		int(sv.get("entity_count", 0)), int(sv.get("station_count", 0))])

# ═══════════════════════════════════════════════════════════════════
# 3. transfer_tick 只读插值
# ═══════════════════════════════════════════════════════════════════

func _test_ticks() -> void:
	_section_begin("3 transfer_tick")
	_set_scenario("transit")
	var br = _make_bridge()
	var plan: Dictionary = br.transfer_plan()
	var transfer: Dictionary = plan.get("transfer", {})
	var timeline: Array = plan.get("timeline", [])
	var tof := float(transfer.get("tof_s", 0.0))
	_ok(tof > 0.0, "tof>0")
	# t=0 departure
	var tick0: Dictionary = br.transfer_tick(0.0)
	_eq(bool(tick0.get("ok", false)), true, "tick(0) ok")
	_eq(String(tick0.get("phase", "")), "departure", "tick(0) phase=departure")
	_near(float(tick0.get("progress", -1.0)), 0.0, 1.0e-9, "tick(0) progress=0")
	_ok(_arr3_finite(tick0.get("pos_rot_km", [])), "tick(0) pos 有限")
	_ok(_arr3_finite(tick0.get("vel_rot_kmps", [])), "tick(0) vel 有限")
	var first_gap := 0.0
	if timeline.size() > 0:
		var first_pos: Array = (timeline[0] as Dictionary).get("pos_rot_km", [])
		var tp: Array = tick0.get("pos_rot_km", [])
		if first_pos.size() >= 3 and tp.size() >= 3:
			first_gap = sqrt(pow(float(tp[0]) - float(first_pos[0]), 2.0)
				+ pow(float(tp[1]) - float(first_pos[1]), 2.0)
				+ pow(float(tp[2]) - float(first_pos[2]), 2.0))
	_near(first_gap, 0.0, 1.0e-6, "tick(0) = timeline[0]")
	# mid cruise
	var tickm: Dictionary = br.transfer_tick(tof * 0.5)
	_eq(String(tickm.get("phase", "")), "cruise", "tick(mid) phase=cruise")
	_near(float(tickm.get("progress", -1.0)), 0.5, 1.0e-9, "tick(mid) progress=0.5")
	_ok(float(tickm.get("range_to_target_km", -1.0)) > 0.0, "mid range>0")
	_ok(_arr3_finite(tickm.get("pos_rot_km", [])), "mid pos 有限")
	# end arrival
	var ticke: Dictionary = br.transfer_tick(tof)
	_eq(String(ticke.get("phase", "")), "arrival", "tick(tof) phase=arrival")
	_near(float(ticke.get("progress", -1.0)), 1.0, 1.0e-9, "tick(tof) progress=1")
	_ok(float(ticke.get("range_to_target_km", 99999.0)) < 3000.0, "arrival range<3000km")
	# clamp
	var tick_over: Dictionary = br.transfer_tick(tof + 86400.0)
	_eq(bool(tick_over.get("clamped", false)), true, "超时 clamp=true")
	_eq(String(tick_over.get("phase", "")), "arrival", "超时 phase=arrival")
	_near(float(tick_over.get("t_s", -1.0)), tof, 1.0e-6, "超时 clamp 到 tof")
	var tick_neg: Dictionary = br.transfer_tick(-100.0)
	_eq(bool(tick_neg.get("clamped", false)), true, "负时间 clamp=true")
	_eq(String(tick_neg.get("phase", "")), "departure", "负时间 phase=departure")
	_near(float(tick_neg.get("t_s", -1.0)), 0.0, 1.0e-9, "负时间 clamp 到 0")
	# 在 timeline 采样点精确还原
	if timeline.size() >= 5:
		var row: Dictionary = timeline[3]
		var t_sample := float(row.get("t_s", 0.0))
		var tick_s: Dictionary = br.transfer_tick(t_sample)
		_near(float(tick_s.get("progress", -1.0)), t_sample / tof, 1.0e-6,
			"采样点 progress")
		var row_pos: Array = row.get("pos_rot_km", [])
		var tick_pos: Array = tick_s.get("pos_rot_km", [])
		var gap := sqrt(pow(float(tick_pos[0]) - float(row_pos[0]), 2.0)
			+ pow(float(tick_pos[1]) - float(row_pos[1]), 2.0)
			+ pow(float(tick_pos[2]) - float(row_pos[2]), 2.0))
		_near(gap, 0.0, 1.0e-6, "采样点位置一致")
	# state 包装一致
	var st = _make_state(br)
	var tick_state: Dictionary = st.fw_transfer_tick(tof * 0.5)
	_eq(String(tick_state.get("phase", "")), "cruise", "state fw_transfer_tick phase")
	_near(float(tick_state.get("t_s", -1.0)), float(tickm.get("t_s", -2.0)), 1.0e-6,
		"state tick = bridge tick")
	# JSON
	var js := JSON.stringify(tickm)
	_ok(js.length() > 200, "tick JSON", "len=%d" % js.length())
	_ok(JSON.parse_string(js) is Dictionary, "tick JSON 回读")
	_clear_env()
	_data_line("tick", "tof=%.1fs phases departure/cruise/arrival clamp ok" % tof)

# ═══════════════════════════════════════════════════════════════════
# 4. legacy / 回退
# ═══════════════════════════════════════════════════════════════════

func _test_fallback() -> void:
	_section_begin("4 legacy / 回退")
	_set_scenario("legacy")
	var br = _make_bridge()
	_eq(br.scenario_mode, "legacy", "显式 legacy")
	_eq(br.transfer_ready, false, "显式 legacy transfer_ready=false")
	_eq(String(br.scenario.id), "l1_supervision_v2", "显式 legacy 场景 id")
	_set_scenario("foo")
	var br2 = _make_bridge()
	_eq(br2.scenario_mode, "legacy", "未知 V17_SCENARIO → legacy")
	_eq(br2.transfer_ready, false, "未知值 transfer_ready=false")
	_eq(String(br2.scenario.id), "l1_supervision_v2", "未知值场景 id=legacy")
	_clear_env()
	_data_line("fallback", "legacy/未知值 → legacy 场景，transfer_ready=false")

# ═══════════════════════════════════════════════════════════════════
# 5. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("5 JSON")
	_set_scenario("transit")
	var br = _make_bridge()
	var st = _make_state(br)
	var js := JSON.stringify(st.fw_transfer)
	_ok(js.length() > 5000, "fw_transfer JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "fw_transfer 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("timeline") is Array, "回读 timeline")
		_ok(pd.get("fleet") is Array, "回读 fleet")
		_ok(pd.get("arrival") is Dictionary, "回读 arrival")
	var sjs := JSON.stringify(st.fw_scenario)
	_ok(sjs.length() > 100, "fw_scenario JSON", "len=%d" % sjs.length())
	_ok(JSON.parse_string(sjs) is Dictionary, "fw_scenario 回读")
	var ojs := JSON.stringify(st.fw_own_reference)
	_ok(ojs.length() > 100, "fw_own_reference JSON", "len=%d" % ojs.length())
	_ok(JSON.parse_string(ojs) is Dictionary, "fw_own_reference 回读")
	var bs := JSON.stringify(st.fw_bridge_state())
	_ok(bs.length() > 8000, "fw_bridge_state JSON", "len=%d" % bs.length())
	var bp = JSON.parse_string(bs)
	_ok(bp is Dictionary, "fw_bridge_state 回读")
	if bp is Dictionary:
		var bd: Dictionary = bp
		_eq(String(bd.get("scenario", {}).get("mode", "")), "transit", "回读 scenario.mode")
		_ok(bd.get("transfer") is Dictionary, "回读 transfer")
		_ok(bd.get("own_reference") is Dictionary, "回读 own_reference")
		_ok(bd.get("scenario_entities") is Array, "回读 scenario_entities")
	_clear_env()
	_data_line("json", "transfer=%d scenario=%d own=%d bridge=%d" % [
		js.length(), sjs.length(), ojs.length(), bs.length()])
