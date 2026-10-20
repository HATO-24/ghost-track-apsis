extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3C 最小 probe：PrologueController 序章流程
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/prologue_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI/物理。
# ═══════════════════════════════════════════════════════════════════

const Prologue := preload("res://scripts/core/prologue_controller.gd")
const StoryState := preload("res://scripts/core/story_state.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")

const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"
const FLEET_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3C PROBE · PrologueController")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_setup_name()
	_test_wrong_states()
	_test_full_flow()
	_test_window_failures()
	_test_save_load()
	_test_events_effects()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PROLOGUE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PROLOGUE PROBE FAILED")
		quit(1)
	else:
		print("V17 PROLOGUE PROBE OK")
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
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _new_prologue(ss = null):
	var p = Prologue.new({"story_state": ss})
	_ok(bool(p.ready), "prologue ready", str(p.errors))
	return p

func _core(p) -> String:
	var vm: Dictionary = p.snapshot()
	return _norm_json({
		"state": vm.get("state", ""), "player_name": vm.get("player_name", ""),
		"destination": vm.get("destination", ""),
		"request_id": vm.get("request_id", ""),
		"burn_authorized": vm.get("burn_authorized", false),
		"t_s": vm.get("t_s", 0.0), "ignition_t": vm.get("ignition_t", -1.0),
		"arrival_t": vm.get("arrival_t", -1.0),
		"history": vm.get("history", []), "events": vm.get("events", []),
		"applied": vm.get("applied", {}),
	})

func _to_navigation(p, name := "远地点") -> void:
	p.submit_name(name)
	p.confirm_briefing()
	p.accept_handover()

func _to_burn_window(p, name := "远地点") -> void:
	_to_navigation(p, name)
	p.set_destination("l1_meridian_05")
	p.request_departure()
	p.authorize_burn()

func _to_cruise(p, name := "远地点") -> void:
	_to_burn_window(p, name)
	p.advance_time(18.0 * 3600.0)
	p.ignite()

# ═══════════════════════════════════════════════════════════════════
# 1. 内容文件（scenario + fleet cache）
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容/舰队")
	_ok(FileAccess.file_exists(SCENARIO_PATH), "scenario 文件存在")
	_ok(FileAccess.file_exists(FLEET_PATH), "fleet cache 文件存在")
	var sc = _read_json(SCENARIO_PATH)
	var fl = _read_json(FLEET_PATH)
	_ok(sc is Dictionary, "scenario JSON 可解析")
	_ok(fl is Dictionary, "fleet cache JSON 可解析")
	if not (sc is Dictionary) or not (fl is Dictionary):
		return
	_eq(String((sc as Dictionary).get("schema", "")), "scenario.v2", "scenario schema")
	_eq(String((sc as Dictionary).get("id", "")), "transit_l4_l1", "scenario id")
	var tr: Dictionary = (sc as Dictionary).get("transfer", {})
	_eq(String(tr.get("source_port", "")), "l4_02_hammer", "scenario source")
	_eq(String(tr.get("target_port", "")), "l1_meridian_05", "scenario target")
	_ok((tr.get("target_cluster", []) as Array).size() >= 2, "target_cluster")
	_ok(tr.get("arrival_gate") is Dictionary, "arrival_gate")
	_eq(String((fl as Dictionary).get("schema", "")), "v17_fleet_transfer_cache.v1", "cache schema")
	_eq(String((fl as Dictionary).get("fleet", "")), "transit_l4_l1", "cache fleet")
	_near(float((fl as Dictionary).get("tof_s", 0.0)), 6.0 * 86400.0, 1.0e-6, "cache TOF=6d")
	_eq(String((fl as Dictionary).get("source_port", "")), "L4-02 Hammer", "cache source display")
	_eq(String((fl as Dictionary).get("target_port", "")), "L1-Meridian-05", "cache target display")
	_eq(((fl as Dictionary).get("ships", []) as Array).size(), 5, "cache 5 ships")
	var dv: Dictionary = (fl as Dictionary).get("dv", {})
	_near(float(dv.get("avg_total_mps", 0.0)), 1822.44135141373, 1.0e-6, "dv avg_total")
	_near(float(dv.get("sum_total_mps", 0.0)), 9112.20675706863, 1.0e-6, "dv sum_total")
	_near(float(dv.get("max_arrival_mps", 0.0)), 969.567537307739, 1.0e-6, "dv max arrival")
	var arrival: Dictionary = (fl as Dictionary).get("arrival", {})
	_eq(bool(arrival.get("all_within_gate", false)), true, "arrival all_within_gate")
	_near(float(arrival.get("gate_radius_km", 0.0)), 3000.0, 1.0e-9, "gate radius")
	_eq(((fl as Dictionary).get("samples", []) as Array).size(), 11, "cache samples 11")
	# runtime 内容摘要
	var p = _new_prologue()
	_eq(String(p.source_id), "l4_02_hammer", "runtime source id")
	_eq(String(p.target_id), "l1_meridian_05", "runtime target id")
	_eq(String(p.source_display), "L4-02 Hammer", "runtime source display")
	_eq(String(p.target_display), "L1-Meridian-05", "runtime target display")
	_near(float(p.tof_s), 518400.0, 1.0e-6, "runtime TOF")
	_eq(p.fleet().size(), 5, "runtime fleet 5")
	var first: Dictionary = (p.fleet() as Array)[0]
	_eq(String(first.get("ship_id", "")), "apsis", "fleet flagship apsis")
	_ok(float(first.get("total_dv_mps", 0.0)) > 0.0, "fleet total_dv")
	_eq(p.timeline().size(), 15, "timeline 11 采样+4 里程碑")
	_ok(p.allowed_destinations.size() >= 2, "allowed destinations")
	_ok(p.state == "NAME_INPUT", "初始 NAME_INPUT")
	_ok(p.check_contracts().get("ok", false), "初始 contracts ok")
	_ok(not p.snapshot().is_empty(), "snapshot 非空")
	_data_line("content", "source/target/TOF=6d/dv=1822.44 avg/fleet=5/samples=11")

# ═══════════════════════════════════════════════════════════════════
# 2. setup / 玩家名
# ═══════════════════════════════════════════════════════════════════

func _test_setup_name() -> void:
	_section_begin("2 setup/玩家名")
	var ss = StoryState.new()
	var p = _new_prologue(ss)
	_eq(p.errors.size(), 0, "无 errors")
	_eq(p.state, "NAME_INPUT", "初始状态 NAME_INPUT")
	_eq(p.state_index(), 0, "state_index 0")
	_eq(p.next_state(), "BRIEFING", "next_state BRIEFING")
	_eq(p.player_name, "", "初始名字空")
	# 非法名字
	var e1: Dictionary = p.submit_name("")
	_eq(bool(e1.get("ok", true)), false, "空名字拒绝")
	_eq(String(e1.get("reason", "")), "empty_name", "empty_name")
	var e2: Dictionary = p.submit_name("   ")
	_eq(bool(e2.get("ok", true)), false, "空白名字拒绝")
	_eq(String(e2.get("reason", "")), "empty_name", "空白 name 视为空")
	var e3: Dictionary = p.submit_name("x".repeat(25))
	_eq(bool(e3.get("ok", true)), false, "超长名字拒绝")
	_eq(String(e3.get("reason", "")), "name_too_long", "name_too_long")
	var e4: Dictionary = p.submit_name("a\nb")
	_eq(bool(e4.get("ok", true)), false, "控制字符名字拒绝")
	_eq(String(e4.get("reason", "")), "invalid_chars", "control invalid_chars")
	var e5: Dictionary = p.submit_name(" 远地点 ")
	_eq(bool(e5.get("ok", true)), false, "首尾空白拒绝")
	_eq(p.player_name, "", "非法名字不写入")
	_eq(p.state, "NAME_INPUT", "非法名字不改变状态")
	# 合法名字（CJK，IME 提交）
	var ok: Dictionary = p.submit_name("远地点", {"ime": true})
	_eq(bool(ok.get("ok", false)), true, "合法名字提交 ok")
	_eq(String(ok.get("name", "")), "远地点", "名字保存")
	_eq(p.player_name, "远地点", "player_name")
	_eq(p.state, "BRIEFING", "提交名字 → BRIEFING")
	_eq(p.next_state(), "HANDOVER", "next HANDOVER")
	_ok(int(p.history.size()) == 1, "history 1")
	_eq(bool((p.history[0] as Dictionary).get("ime", false)), true, "history 记录 ime")
	_ok((p.events.size()) == 1, "事件 1")
	_eq(String((p.events[0] as Dictionary).get("kind", "")), "prologue.name_submitted",
		"name_submitted 事件")
	_ok(bool(ss.flags.get("prologue_name_set", false)), "StoryState flag prologue_name_set")
	# 重复提交
	var dup: Dictionary = p.submit_name("另一个名字")
	_eq(bool(dup.get("ok", true)), false, "重复提交拒绝")
	_eq(String(dup.get("reason", "")), "wrong_state", "重复提交 wrong_state")
	_eq(p.player_name, "远地点", "重复不覆盖名字")
	# ASCII 名字另一实例
	var p2 = _new_prologue()
	var a: Dictionary = p2.submit_name("Commander_01")
	_eq(bool(a.get("ok", false)), true, "ASCII 名字 ok")
	_eq(p2.player_name, "Commander_01", "ASCII 名字保存")
	# 24 字符边界
	var p3 = _new_prologue()
	var n24 := "A".repeat(24)
	_eq(bool(p3.submit_name(n24).get("ok", false)), true, "24 字符名字 ok")
	var p4 = _new_prologue()
	_eq(bool(p4.submit_name("A".repeat(25)).get("ok", true)), false, "25 字符拒绝")
	_data_line("name", "空/空白/超长/控制字符拒绝 · CJK/ASCII/IME/24 字符通过")

# ═══════════════════════════════════════════════════════════════════
# 3. 乱序 / wrong_state
# ═══════════════════════════════════════════════════════════════════

func _test_wrong_states() -> void:
	_section_begin("3 乱序/wrong_state")
	var p = _new_prologue()
	# NAME_INPUT 阶段不能直接推进
	_eq(String(p.confirm_briefing().get("reason", "")), "wrong_state", "NAME_INPUT confirm 拒绝")
	_eq(String(p.accept_handover().get("reason", "")), "wrong_state", "NAME_INPUT handover 拒绝")
	_eq(String(p.set_destination("l1_meridian_05").get("reason", "")), "wrong_state",
		"NAME_INPUT destination 拒绝")
	_eq(String(p.request_departure().get("reason", "")), "wrong_state", "NAME_INPUT request 拒绝")
	_eq(String(p.authorize_burn().get("reason", "")), "wrong_state", "NAME_INPUT authorize 拒绝")
	_eq(String(p.ignite().get("reason", "")), "wrong_state", "NAME_INPUT ignite 拒绝")
	_eq(String(p.arrive().get("reason", "")), "wrong_state", "NAME_INPUT arrive 拒绝")
	_eq(String(p.complete().get("reason", "")), "wrong_state", "NAME_INPUT complete 拒绝")
	# BRIEFING
	p.submit_name("远地点")
	_eq(String(p.accept_handover().get("reason", "")), "wrong_state", "BRIEFING handover 拒绝")
	_eq(String(p.request_departure().get("reason", "")), "wrong_state", "BRIEFING request 拒绝")
	p.confirm_briefing()
	# HANDOVER
	_eq(String(p.set_destination("l1_meridian_05").get("reason", "")), "wrong_state",
		"HANDOVER destination 拒绝")
	_eq(String(p.request_departure().get("reason", "")), "wrong_state", "HANDOVER request 拒绝")
	p.accept_handover()
	# NAVIGATION
	_eq(String(p.request_departure().get("reason", "")), "no_destination", "无目的地 request 拒绝")
	_eq(String(p.authorize_burn().get("reason", "")), "wrong_state", "NAVIGATION authorize 拒绝")
	_eq(String(p.ignite().get("reason", "")), "wrong_state", "NAVIGATION ignite 拒绝")
	# destination 非法 / 合法
	_eq(String(p.set_destination("earth").get("reason", "")), "invalid_destination",
		"非法目的地拒绝")
	_eq(bool(p.set_destination("l1_meridian_05").get("ok", false)), true, "合法目的地 set")
	# DEPARTURE_REQUEST
	p.request_departure()
	_eq(bool(p.authorize_burn().get("ok", false)), true, "DEPARTURE_REQUEST authorize ok")
	# BURN_WINDOW：重复 authorize
	_eq(String(p.authorize_burn().get("reason", "")), "wrong_state", "重复 authorize 拒绝")
	_eq(String(p.arrive().get("reason", "")), "wrong_state", "BURN_WINDOW arrive 拒绝")
	# CRUISE 前提前 complete
	_eq(String(p.complete().get("reason", "")), "wrong_state", "BURN_WINDOW complete 拒绝")
	_data_line("wrong_states", "NAME/BRIEFING/HANDOVER/NAVIGATION/DEPARTURE/BURN 乱序均拒绝")

# ═══════════════════════════════════════════════════════════════════
# 4. 全流程
# ═══════════════════════════════════════════════════════════════════

func _test_full_flow() -> void:
	_section_begin("4 全流程")
	var ss = StoryState.new()
	var p = _new_prologue(ss)
	_eq(p.state, "NAME_INPUT", "0 NAME_INPUT")
	p.submit_name("远地点")
	_eq(p.state, "BRIEFING", "1 BRIEFING")
	p.confirm_briefing()
	_eq(p.state, "HANDOVER", "2 HANDOVER")
	p.accept_handover()
	_eq(p.state, "NAVIGATION", "3 NAVIGATION")
	_eq(p.state_index(), 3, "state_index 3")
	p.set_destination("l1_meridian_05")
	_eq(p.destination, "l1_meridian_05", "目的地保存")
	_ok(bool(ss.flags.get("destination_set", false)), "flag destination_set")
	p.request_departure()
	_eq(p.state, "DEPARTURE_REQUEST", "4 DEPARTURE_REQUEST")
	_ok(String(p.request_id).begins_with("REQ-"), "request_id 生成")
	p.authorize_burn()
	_eq(p.state, "BURN_WINDOW", "5 BURN_WINDOW")
	_eq(bool(p.burn_authorized), true, "burn_authorized")
	_ok(bool(ss.flags.get("burn_authorized", false)), "flag burn_authorized")
	_ok(bool(p.window().get("is_open", true)) == false, "初始窗口未开")
	_eq(String(p.ignite().get("reason", "")), "window_not_open", "窗口前 ignite 拒绝")
	# 手动推进时间（不自动改状态）
	var adv: Dictionary = p.advance_time(18.0 * 3600.0)
	_eq(bool(adv.get("ok", false)), true, "advance_time ok")
	_eq(p.state, "BURN_WINDOW", "advance_time 不自动改状态")
	_ok(bool(p.window().get("is_open", false)), "窗口已开")
	var ig: Dictionary = p.ignite()
	_eq(bool(ig.get("ok", false)), true, "ignite ok")
	_eq(p.state, "CRUISE", "6 CRUISE")
	_near(float(p.ignition_t), 64800.0, 1.0e-9, "ignition_t=18h")
	_near(float(p.arrival_t), 64800.0 + 518400.0, 1.0e-9, "arrival_t=ignition+TOF")
	_ok(bool(ss.flags.get("burn_ignited", false)), "flag burn_ignited")
	# 抵达时间前
	_eq(String(p.arrive().get("reason", "")), "too_early", "提前 arrive 拒绝")
	var adv2: Dictionary = p.advance_time(518400.0)
	_eq(p.state, "CRUISE", "advance 到抵达时间不自动改状态")
	_ok(bool(adv2.get("arrival_ready", false)), "arrival_ready true")
	var ar: Dictionary = p.arrive()
	_eq(bool(ar.get("ok", false)), true, "arrive ok")
	_eq(p.state, "ARRIVAL", "7 ARRIVAL")
	_ok(bool(ss.flags.get("arrived_l1", false)), "flag arrived_l1")
	_ok(ss.has_evidence("ev_arrival_l1"), "evidence ev_arrival_l1")
	_ok(float(ar.get("arrival_error_km", 99999.0)) <= 3000.0, "arrival_error <= gate")
	# 不自动完成
	_eq(String(p.state), "ARRIVAL", "到达后不自动 complete")
	var co: Dictionary = p.complete()
	_eq(bool(co.get("ok", false)), true, "complete ok")
	_eq(p.state, "COMPLETE", "8 COMPLETE")
	_ok(bool(ss.flags.get("prologue_complete", false)), "flag prologue_complete")
	_near(ss.trust, 60.0, 1.0e-9, "trust 50+2+3+5=60")
	# 终态重复操作拒绝
	_eq(String(p.complete().get("reason", "")), "wrong_state", "COMPLETE 重复 complete 拒绝")
	_eq(String(p.submit_name("x").get("reason", "")), "wrong_state", "COMPLETE submit_name 拒绝")
	_ok(p.history.size() == 9, "history 9 步", str(p.history.size()))
	_ok(p.events.size() == 9, "events 9", str(p.events.size()))
	_ok(p.check_contracts().get("ok", false), "全流程 contracts ok")
	_data_line("full_flow", "NAME→BRIEFING→HANDOVER→NAVIGATION→DEPARTURE→BURN→CRUISE→ARRIVAL→COMPLETE")

# ═══════════════════════════════════════════════════════════════════
# 5. 点火窗口失败
# ═══════════════════════════════════════════════════════════════════

func _test_window_failures() -> void:
	_section_begin("5 窗口失败")
	var p = _new_prologue()
	_to_burn_window(p)
	# 窗口前
	_eq(String(p.ignite().get("reason", "")), "window_not_open", "窗口前 ignite")
	# 越过窗口关闭
	p.advance_time(25.0 * 3600.0)
	_eq(String(p.ignite().get("reason", "")), "window_closed", "窗口关闭后 ignite")
	_eq(p.state, "BURN_WINDOW", "失败不改变状态")
	# 负 dt / NaN
	_eq(String(p.advance_time(-1.0).get("reason", "")), "invalid_dt", "负 dt 拒绝")
	_eq(String(p.advance_time(NAN).get("reason", "")), "invalid_dt", "NaN dt 拒绝")
	# 窗口边界（open/close 含端点）
	var p2 = _new_prologue()
	_to_burn_window(p2)
	p2.advance_time(18.0 * 3600.0)
	_ok(bool(p2.window().get("is_open", false)), "窗口 open 边界含")
	_eq(bool(p2.ignite().get("ok", false)), true, "窗口 open 可点火")
	var p3 = _new_prologue()
	_to_burn_window(p3)
	p3.advance_time(24.0 * 3600.0)
	_ok(bool(p3.window().get("is_open", false)), "窗口 close 边界含")
	_eq(bool(p3.ignite().get("ok", false)), true, "窗口 close 可点火")
	# 未授权 ignite
	var p4 = _new_prologue()
	_to_navigation(p4)
	p4.set_destination("l1_meridian_05")
	p4.request_departure()
	p4.advance_time(18.0 * 3600.0)
	# 状态仍 DEPARTURE_REQUEST；直接 ignite 是 wrong_state
	_eq(String(p4.ignite().get("reason", "")), "wrong_state", "未 authorize ignite wrong_state")
	_data_line("window", "未开/已关/负 dt/NaN/边界 open-close/未授权")

# ═══════════════════════════════════════════════════════════════════
# 6. 存档 / 中断
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("6 存档/中断")
	# 各阶段中断保存/load
	for target_state in ["NAVIGATION", "BURN_WINDOW", "CRUISE", "ARRIVAL"]:
		var ss = StoryState.new()
		var p = _new_prologue(ss)
		p.submit_name("远地点")
		p.confirm_briefing()
		p.accept_handover()
		if target_state != "NAVIGATION":
			p.set_destination("l1_meridian_05")
			p.request_departure()
		if target_state in ["BURN_WINDOW", "CRUISE", "ARRIVAL"]:
			p.authorize_burn()
		if target_state in ["CRUISE", "ARRIVAL"]:
			p.advance_time(18.0 * 3600.0)
			p.ignite()
		if target_state == "ARRIVAL":
			p.advance_time(518400.0)
			p.arrive()
		var save := p.save_state()
		var d = JSON.parse_string(save)
		_ok(d is Dictionary, "save JSON 可解析：" + target_state)
		if d is Dictionary:
			_eq(String((d as Dictionary).get("schema", "")), "v17.prologue_save.v1",
				"save schema：" + target_state)
			_eq(String((d as Dictionary).get("state", "")), target_state,
				"save state：" + target_state)
		var ss2 = StoryState.new()
		var p2 = _new_prologue(ss2)
		var lr: Dictionary = p2.load_state(save)
		_eq(bool(lr.get("ok", false)), true, "load ok：" + target_state, str(lr.get("errors", [])))
		_eq(p2.state, target_state, "load state：" + target_state)
		_ok(_norm_json(p.snapshot()) == _norm_json(p2.snapshot()),
			"load snapshot 一致：" + target_state)
		_ok(JSON.stringify(ss.snapshot()) == JSON.stringify(ss2.snapshot()),
			"load StoryState 一致：" + target_state)
		_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(p2.save_state())),
			"load 后再次 save 一致：" + target_state)
	# 中途继续：BURN_WINDOW load 后继续点火/抵达/完成
	var ss = StoryState.new()
	var p = _new_prologue(ss)
	_to_burn_window(p)
	var save := p.save_state()
	var ss2 = StoryState.new()
	var p2 = _new_prologue(ss2)
	p2.load_state(save)
	p2.advance_time(18.0 * 3600.0)
	_eq(bool(p2.ignite().get("ok", false)), true, "load 后继续 ignite")
	p2.advance_time(518400.0)
	_eq(bool(p2.arrive().get("ok", false)), true, "load 后继续 arrive")
	_eq(bool(p2.complete().get("ok", false)), true, "load 后继续 complete")
	# 非法存档拒绝且不改状态
	var before := _core(p2)
	for bad in ["", "{bad", JSON.stringify({"schema": "bad"}),
			JSON.stringify({"schema": "v17.prologue_save.v1", "version": "1.0.0",
				"state": "BOGUS"}),
			JSON.stringify({"schema": "v17.prologue_save.v1", "version": "1.0.0",
				"state": "NAVIGATION", "player_name": ""}),
			JSON.stringify({"schema": "v17.prologue_save.v1", "version": "1.0.0",
				"state": "NAVIGATION", "player_name": "x", "destination": "earth"})]:
		var br: Dictionary = p2.load_state(String(bad))
		_eq(bool(br.get("ok", true)), false, "非法存档拒绝：" + String(bad).substr(0, 40))
	_eq(_core(p2), before, "非法存档不改状态")
	_ok(bool(p2.check_contracts().get("ok", false)), "存档后 contracts ok")
	_data_line("save_load", "各阶段中断 load snapshot+StoryState 一致 · 中途继续 · 非法拒绝")

# ═══════════════════════════════════════════════════════════════════
# 7. 事件 / 效果
# ═══════════════════════════════════════════════════════════════════

func _test_events_effects() -> void:
	_section_begin("7 事件/效果")
	var ss = StoryState.new()
	var bus = EventBus.new()
	var p = Prologue.new({"story_state": ss, "event_bus": bus})
	_ok(bool(p.ready), "事件 probe ready")
	p.submit_name("远地点")
	p.confirm_briefing()
	p.accept_handover()
	p.set_destination("l1_meridian_05")
	p.request_departure()
	p.authorize_burn()
	p.advance_time(18.0 * 3600.0)
	p.ignite()
	p.advance_time(518400.0)
	p.arrive()
	p.complete()
	_eq(p.events.size(), 9, "9 个 prologue 事件")
	var kinds: Array = []
	for e in p.events:
		var ev: Dictionary = e
		kinds.append(String(ev.get("kind", "")))
		_ok(String(ev.get("schema", "")) == "prologue_event.v1", "事件 schema")
		_ok(bool(ev.get("writes_v15", true)) == false, "事件不写 V15")
	for k in ["prologue.name_submitted", "prologue.briefing_confirmed",
			"prologue.handover_accepted", "prologue.destination_set",
			"prologue.departure_requested", "prologue.burn_authorized",
			"prologue.burn_ignited", "prologue.arrived", "prologue.completed"]:
		_ok(k in kinds, "事件存在：" + k)
	_eq(bus.current_seq(), 9, "EventBus 收到 9 事件")
	var bus_types: Array = []
	for raw in bus.recent(20):
		bus_types.append(String((raw as Dictionary).get("type", "")))
	_ok("prologue.name_submitted" in bus_types, "bus 收到 name_submitted")
	_ok("prologue.completed" in bus_types, "bus 收到 completed")
	_ok(p.events_since(5).size() == 4, "events_since(5)=4")
	var taken: Array = p.take_events()
	_eq(taken.size(), 9, "take_events 9")
	_eq(p.events.size(), 0, "take 后 events 空")
	# StoryState 效果
	_ok(bool(ss.has_flag("prologue_name_set")), "flag name_set")
	_ok(bool(ss.has_flag("handover_done")), "flag handover_done")
	_ok(bool(ss.has_flag("destination_set")), "flag destination_set")
	_ok(bool(ss.has_flag("burn_authorized")), "flag burn_authorized")
	_ok(bool(ss.has_flag("burn_ignited")), "flag burn_ignited")
	_ok(ss.has_evidence("ev_arrival_l1"), "evidence arrival")
	_ok(bool(ss.has_flag("prologue_complete")), "flag complete")
	_near(ss.trust, 60.0, 1.0e-9, "trust 60")
	# 无 StoryState / 无 bus 也工作
	var p2 = _new_prologue()
	p2.submit_name("NoStory")
	_eq(p2.state, "BRIEFING", "无 StoryState 仍推进")
	p2.confirm_briefing()
	p2.accept_handover()
	_ok(p2.applied_flags.size() == 3, "内部 flags 记录", str(p2.applied_flags.keys()))
	# apply_effects 直接接口
	var p3 = _new_prologue(StoryState.new())
	var eff: Dictionary = p3.apply_effects({"flags": ["custom_flag"],
		"evidence": ["ev_custom"], "trust": 3.0})
	_eq(bool(eff.get("ok", false)), true, "apply_effects ok")
	_ok(bool(p3.story_state.has_flag("custom_flag")), "apply_effects flag")
	_ok(p3.story_state.has_evidence("ev_custom"), "apply_effects evidence")
	_near(p3.story_state.trust, 53.0, 1.0e-9, "apply_effects trust")
	_data_line("events", "9 prologue.* + EventBus 发布 + StoryState flags/evidence/trust")

# ═══════════════════════════════════════════════════════════════════
# 8. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("8 JSON/确定性")
	var p = _new_prologue(StoryState.new())
	_to_burn_window(p)
	var js := p.to_json()
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "runtime JSON 可解析")
	if parsed is Dictionary:
		var d: Dictionary = parsed
		_eq(String(d.get("schema", "")), "v17.prologue.v1", "JSON schema")
		_eq(String(d.get("state", "")), "BURN_WINDOW", "JSON state")
		_ok(d.get("fleet") is Array, "JSON fleet")
		_ok(d.get("timeline") is Array, "JSON timeline")
		_ok(d.get("window") is Dictionary, "JSON window")
		_ok(d.get("story") is Dictionary, "JSON story")
		_ok(d.get("contracts") is Dictionary, "JSON contracts")
	# 确定性：两实例同操作
	var a = _new_prologue(StoryState.new())
	var b = _new_prologue(StoryState.new())
	for c in [a, b]:
		c.submit_name("远地点")
		c.confirm_briefing()
		c.accept_handover()
		c.set_destination("l1_meridian_05")
		c.request_departure()
		c.authorize_burn()
		c.advance_time(18.0 * 3600.0)
		c.ignite()
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "同操作 snapshot 一致")
	_ok(a.save_state() == b.save_state(), "同操作 save 一致")
	# 时间轴/里程碑确定性
	_ok(_norm_json(a.timeline()) == _norm_json(b.timeline()), "timeline 一致")
	_ok(_norm_json(a.fleet()) == _norm_json(b.fleet()), "fleet 一致")
	# 状态列表
	_eq(Prologue.STATES.size(), 9, "9 状态")
	_eq(Prologue.STATES[0], "NAME_INPUT", "首状态 NAME_INPUT")
	_eq(Prologue.STATES[8], "COMPLETE", "末状态 COMPLETE")
	_data_line("json_det", "JSON 可解析 · 9 状态 · 同操作 snapshot/save/timeline 一致")
