extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 阶段2-TEACHING-1 最小 probe：07 教学目标手动控制器
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/teaching_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 HUD。
# ═══════════════════════════════════════════════════════════════════

const Controller := preload("res://scripts/teaching_controller.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2-TEACHING-1 PROBE · 07 教学目标手动控制器")
	print("════════════════════════════════════════════════════════════")
	_test_load_initial()
	_test_g1()
	_test_g2()
	_test_g3()
	_test_g4()
	_test_manual_and_reset()
	_test_direct_kinds()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 TEACHING PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 TEACHING PROBE FAILED")
		quit(1)
	else:
		print("V17 TEACHING PROBE OK")
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

func _progress(c) -> Dictionary:
	return c.vm().get("progress", {})

func _completed(c) -> int:
	return int(_progress(c).get("completed", -1))

func _skipped(c) -> int:
	return int(_progress(c).get("skipped", -1))

func _note_ok(c, action: String, target := "", extra := {}) -> Dictionary:
	var r: Dictionary = c.note(action, target, extra)
	_ok(bool(r.get("ok", false)), "动作 %s 成功" % action, str(r.get("reason", "")))
	return r

# ═══════════════════════════════════════════════════════════════════
# 1. 加载 / 初始
# ═══════════════════════════════════════════════════════════════════

func _test_load_initial() -> void:
	_section_begin("1 加载 / 初始")
	var c = Controller.new()
	_ok(c.ready, "controller ready", str(c.errors))
	_eq(c.errors.size(), 0, "无 load errors")
	_eq(c.goals.size(), 4, "goals=4")
	_eq(c.steps.size(), 20, "steps=20")
	_eq(c.manual_only, true, "manual_only=true")
	_eq(c.auto_complete, false, "auto_complete=false")
	_eq(String(c.scenario_id), "l1_supervision_v2", "scenario_id=l1_supervision_v2")
	_ok(String(c.story_file) != "", "story_file 非空")
	_ok(c.status_vocabulary.size() >= 3, "status_vocabulary")
	var goal_ids: Array = []
	for g in c.goals:
		var gd: Dictionary = g
		goal_ids.append(String(gd.get("id", "")))
		_ok(String(gd.get("title", "")) != "", "goal %s title" % String(gd.get("id", "")))
		_ok(int((gd.get("step_ids", []) as Array).size()) > 0,
			"goal %s step_ids 非空" % String(gd.get("id", "")))
	_eq(goal_ids, ["G1", "G2", "G3", "G4"], "goal 顺序 G1-G4")
	var step_ids := {}
	var orders := {}
	for raw in c.steps:
		var s: Dictionary = raw
		var sid := String(s.get("id", ""))
		_ok(sid != "", "step id 非空")
		_ok(not step_ids.has(sid), "step id 唯一: " + sid)
		step_ids[sid] = true
		var order := int(s.get("order", -1))
		_ok(order >= 1, "step %s order>=1" % sid)
		_ok(not orders.has(order), "order 唯一: %d" % order)
		orders[order] = true
		_ok(String(s.get("goal_id", "")) in goal_ids, "step %s goal 合法" % sid)
		_ok(String(s.get("title", "")) != "", "step %s title" % sid)
		_ok(String(s.get("player_action", "")) != "", "step %s player_action" % sid)
		_ok(s.get("trigger_condition") is Dictionary, "step %s trigger" % sid)
		_eq(bool(s.get("manual_only", false)), true, "step %s manual_only" % sid)
		_eq(bool(s.get("auto_complete", true)), false, "step %s auto_complete=false" % sid)
	_eq(step_ids.size(), 20, "step id 总数 20")
	var vm: Dictionary = c.vm()
	_eq(String(vm.get("schema", "")), "v17_teaching_controller.v1", "vm schema")
	_eq(bool(vm.get("manual_only", false)), true, "vm.manual_only")
	_eq(bool(vm.get("auto_complete", true)), false, "vm.auto_complete")
	var prog: Dictionary = vm.get("progress", {})
	_eq(int(prog.get("completed", -1)), 0, "初始 completed=0")
	_eq(int(prog.get("skipped", -1)), 0, "初始 skipped=0")
	_eq(int(prog.get("total", -1)), 20, "总步骤 20")
	_eq(int(prog.get("goals_completed", -1)), 0, "初始 goals_completed=0")
	var current: Dictionary = vm.get("current", {})
	_eq(String(current.get("step_id", "")), "T07-G1-S1", "初始 current=T07-G1-S1")
	_ok(String(current.get("player_action", "")) != "", "current 有 player_action")
	_ok(current.get("hint") != null, "current 有 hint")
	_eq((vm.get("hints", []) as Array).size(), 4, "初始 hints=4")
	_eq((vm.get("completed", []) as Array).size(), 0, "初始 completed 数组空")
	_eq((vm.get("skipped", []) as Array).size(), 0, "初始 skipped 数组空")
	_eq((vm.get("last_event", {}) as Dictionary).size(), 0, "初始 last_event 空")
	for g2 in (vm.get("goals", []) as Array):
		_eq(String((g2 as Dictionary).get("status", "")), "pending", "初始 goal pending")
	_data_line("load", "goals=4 steps=20 current=T07-G1-S1 progress=0/20")

# ═══════════════════════════════════════════════════════════════════
# 2. G1 轨道航行（顺序 / 失败 / 重复）
# ═══════════════════════════════════════════════════════════════════

func _test_g1() -> void:
	_section_begin("2 G1 轨道航行")
	var c = Controller.new()
	# 错误目标 / 失败动作不触发
	var wrong: Dictionary = c.note("set_destination", "wrong_target")
	_ok(not bool(wrong.get("ok", true)), "错误目的地不触发", String(wrong.get("reason", "")))
	_eq(_completed(c), 0, "错误目的地后 completed=0")
	var failed: Dictionary = c.note("confirm_burn", "", {"success": false})
	_ok(not bool(failed.get("ok", true)), "失败动作不触发", String(failed.get("reason", "")))
	_eq(_completed(c), 0, "失败动作后 completed=0")
	var fail_alias: Dictionary = c.note("fail_open_prelude")
	_ok(not bool(fail_alias.get("ok", true)), "fail_ 前缀不触发")
	# 顺序 5 步
	var r1: Dictionary = _note_ok(c, "open_prelude", "", {"phase": "prelude"})
	_eq(String(r1.get("matched_step_id", "")), "T07-G1-S1", "open_prelude→S1")
	var r2: Dictionary = _note_ok(c, "set_destination", "meridian")
	_eq(String(r2.get("matched_step_id", "")), "T07-G1-S2", "destination→S2")
	var r3: Dictionary = _note_ok(c, "select_window", "t1800")
	_eq(String(r3.get("matched_step_id", "")), "T07-G1-S3", "window→S3")
	var r4: Dictionary = _note_ok(c, "confirm_burn")
	_eq(String(r4.get("matched_step_id", "")), "T07-G1-S4", "burn→S4")
	var r5: Dictionary = _note_ok(c, "arrive_l1")
	_eq(String(r5.get("matched_step_id", "")), "T07-G1-S5", "arrive→S5")
	_eq(_completed(c), 5, "G1 完成后 completed=5")
	_ok(c.is_goal_completed("G1"), "G1 completed")
	_eq(String(c.goal_state("G1").get("status", "")), "completed", "G1 status")
	_eq(String(c.vm().get("current", {}).get("step_id", "")), "T07-G2-S1", "当前 G2-S1")
	# 重复同一动作
	var dup: Dictionary = c.note("confirm_burn")
	_eq(bool(dup.get("duplicate", false)), true, "重复动作 duplicate")
	_eq(_completed(c), 5, "重复动作不增加进度")
	_eq(c.note("arrive_l1").get("reason", ""), "duplicate_action", "重复 arrive duplicate")
	# 未知动作
	var unk: Dictionary = c.note("unknown_action_xyz")
	_eq(String(unk.get("reason", "")), "unknown_action", "未知动作 reason")
	_ok(c.vm().get("last_event") is Dictionary, "last_event 结构")
	_data_line("g1", "5 步顺序完成 · 错误/失败/重复不增加进度 · goal completed")

# ═══════════════════════════════════════════════════════════════════
# 3. G2 接触身份（含动作结果等级门限）
# ═══════════════════════════════════════════════════════════════════

func _test_g2() -> void:
	_section_begin("3 G2 接触身份")
	var c = Controller.new()
	for a in ["open_prelude", "set_destination", "select_window", "confirm_burn", "arrive_l1"]:
		_ok(bool(c.note(a, {"set_destination": "meridian",
			"select_window": "t1800"}.get(a, "")).get("ok", false)), "G1 前置 %s" % a)
	_eq(_completed(c), 5, "G2 前置后 completed=5")
	var open_res: Dictionary = _note_ok(c, "open_contact_list", "9001")
	_eq(String(open_res.get("matched_step_id", "")), "T07-G2-S1", "contact_list→S1")
	var low1: Dictionary = c.note("crossfix", "", {"track": "9002", "track_level": 1})
	_ok(not bool(low1.get("ok", true)), "crossfix L1 不触发", String(low1.get("reason", "")))
	var xf: Dictionary = _note_ok(c, "crossfix", "", {"track": "9002", "track_level": 2})
	_eq(String(xf.get("matched_step_id", "")), "T07-G2-S2", "crossfix L2→S2")
	var low2: Dictionary = c.note("model_ident", "", {"track": "9002", "track_level": 2})
	_ok(not bool(low2.get("ok", true)), "model_ident L2 不触发")
	var mi: Dictionary = _note_ok(c, "model_ident", "", {"track": "9002", "track_level": 3})
	_eq(String(mi.get("matched_step_id", "")), "T07-G2-S3", "model_ident L3→S3")
	var iff_low: Dictionary = c.note("iff_query", "9002")
	_ok(not bool(iff_low.get("ok", true)), "iff_query 9002 不匹配")
	var iff: Dictionary = _note_ok(c, "iff_query", "9001")
	_eq(String(iff.get("matched_step_id", "")), "T07-G2-S4", "iff 9001→S4")
	var ack: Dictionary = _note_ok(c, "ack_identity")
	_eq(String(ack.get("matched_step_id", "")), "T07-G2-S5", "ack_identity→S5")
	_ok(c.is_goal_completed("G2"), "G2 completed")
	_eq(_completed(c), 10, "G2 后 completed=10")
	_eq(String(c.vm().get("current", {}).get("step_id", "")), "T07-G3-S1", "当前 G3-S1")
	_data_line("g2", "接触/交叉定位/型号识别/IFF/图例 5 步完成 · 等级门限生效")

# ═══════════════════════════════════════════════════════════════════
# 4. G3 传感器（选舰/开关/命令序列/暴露）
# ═══════════════════════════════════════════════════════════════════

func _test_g3() -> void:
	_section_begin("4 G3 传感器")
	var c = Controller.new()
	# 直接补触发 G3（乱序补触发：跳过 G1/G2 也可命中 G3 步骤）
	var wrong_ship: Dictionary = c.note("select_ship", "ferry")
	_ok(not bool(wrong_ship.get("ok", true)), "错误选舰不触发")
	var ship: Dictionary = _note_ok(c, "select_ship", "harmattan")
	_eq(String(ship.get("matched_step_id", "")), "T07-G3-S1", "select_ship→S1")
	_ok(not bool(c.note("sensor_toggle", "harmattan/YW-R9", {"value": "off"}).get("ok", true)),
		"sensor off 不触发")
	var tog: Dictionary = _note_ok(c, "sensor_toggle", "harmattan/YW-R9", {"value": "on"})
	_eq(String(tog.get("matched_step_id", "")), "T07-G3-S2", "sensor_toggle on→S2")
	# 命令序列不完整
	var partial: Dictionary = c.note("command_event", "",
		{"sequence": ["command.queued"], "link": "LR"})
	_ok(not bool(partial.get("ok", true)), "命令序列不完整不触发")
	var wrong_link: Dictionary = c.note("command_event", "",
		{"sequence": ["command.queued", "command.aborted"], "link": "DIRECT"})
	_ok(not bool(wrong_link.get("ok", true)), "错误链路不触发")
	var cmd: Dictionary = _note_ok(c, "command_event", "",
		{"sequence": ["command.queued", "command.aborted"], "link": "LR"})
	_eq(String(cmd.get("matched_step_id", "")), "T07-G3-S3", "command_event→S3")
	_ok(not bool(c.note("state", "emission_state.harmattan.exposed",
		{"equals": false}).get("ok", true)), "暴露=false 不触发")
	var st: Dictionary = _note_ok(c, "state", "emission_state.harmattan.exposed",
		{"equals": true})
	_eq(String(st.get("matched_step_id", "")), "T07-G3-S4", "state exposed→S4")
	_ok(c.is_goal_completed("G3"), "G3 completed")
	_eq(_completed(c), 4, "仅 G3：completed=4（乱序补触发）")
	_eq(String(c.vm().get("current", {}).get("step_id", "")), "T07-G1-S1",
		"乱序后 current 仍为最早 pending")
	var hints: Array = c.vm().get("hints", [])
	_ok(hints.size() >= 3, "hints 覆盖未完成 goals", str(hints.size()))
	_data_line("g3", "选舰/YW-R9 开关/命令序列/暴露 4 步 · 乱序补触发完成 G3")

# ═══════════════════════════════════════════════════════════════════
# 5. G4 政治红线（需求门限 / 互斥分支 / 报告）
# ═══════════════════════════════════════════════════════════════════

func _test_g4() -> void:
	_section_begin("5 G4 政治红线")
	var c = Controller.new()
	var roe: Dictionary = _note_ok(c, "open_roe_card")
	_eq(String(roe.get("matched_step_id", "")), "T07-G4-S1", "roe_card→S1")
	# EXPOSE 需证据 >=2 / FIRE 需武器释放确认
	var expose_bad: Dictionary = c.note("decision", "EXPOSE")
	_eq(String(expose_bad.get("reason", "")), "requirements_not_met",
		"EXPOSE 无证据被门控")
	_eq(_completed(c), 1, "被门控不增加进度")
	var fire_bad: Dictionary = c.note("decision", "FIRE")
	_eq(String(fire_bad.get("reason", "")), "requirements_not_met",
		"FIRE 未确认被门控")
	var hold: Dictionary = _note_ok(c, "decision", "HOLD")
	_eq(String(hold.get("matched_step_id", "")), "T07-G4-S2", "HOLD→S2")
	var skipped_branch: Array = hold.get("skipped_branch", [])
	_eq(skipped_branch.size(), 3, "HOLD 后跳过其余 3 决策分支")
	for sid in ["T07-G4-S3", "T07-G4-S4", "T07-G4-S5"]:
		_ok(sid in skipped_branch, "互斥跳过: " + sid)
	_eq(_skipped(c), 3, "skipped=3")
	var bad_report: Dictionary = c.note("report_submit", "WRONG_REPORT")
	_ok(not bool(bad_report.get("ok", true)), "错误报告不触发")
	var rep: Dictionary = _note_ok(c, "report_submit", "INTERNAL_AFTER_ACTION")
	_eq(String(rep.get("matched_step_id", "")), "T07-G4-S6", "report→S6")
	_ok(c.is_goal_completed("G4"), "G4 completed（互斥分支 skipped）")
	_eq(int(c.goal_state("G4").get("pending_steps", -1)), 0, "G4 pending_steps=0（互斥+完成）")
	_eq(_completed(c), 3, "仅 G4：completed=3 skipped=3")
	_eq(_skipped(c), 3, "G4 skipped=3")
	_eq(String(c.vm().get("current", {}).get("step_id", "")), "T07-G1-S1",
		"G4 完成后仍有 G1 pending")
	_data_line("g4", "ROE→门控 EXPOSE/FIRE→HOLD（跳过3分支）→报告 · 互斥+需求门限")

# ═══════════════════════════════════════════════════════════════════
# 6. 手动边界 / tick / skip / reset
# ═══════════════════════════════════════════════════════════════════

func _test_manual_and_reset() -> void:
	_section_begin("6 手动边界 / reset")
	var c = Controller.new()
	c.tick(99999.0)
	_eq(_completed(c), 0, "tick 不自动完成")
	_eq(float(c.vm().get("t_s", -1.0)), 99999.0, "tick 仅记录时间")
	c.tick(-10.0)
	_eq(float(c.vm().get("t_s", -1.0)), 0.0, "负 tick clamp 0")
	var sk: Dictionary = c.skip_step("T07-G1-S1", "content_missing")
	_eq(bool(sk.get("ok", false)), true, "skip_step ok")
	_eq(_skipped(c), 1, "skip 后 skipped=1")
	_eq(String(c.vm().get("current", {}).get("step_id", "")), "T07-G1-S2",
		"skip 后 current 前进")
	_eq(String(c.goal_state("G1").get("status", "")), "in_progress", "goal in_progress")
	_eq(bool(c.skip_step("T07-G1-S1").get("ok", true)), false, "重复 skip 拒绝")
	_eq(bool(c.skip_step("no_such").get("ok", true)), false, "未知 skip 拒绝")
	# 完整通关（用新实例）
	var full = Controller.new()
	var script := [
		["open_prelude", "", {}], ["set_destination", "meridian", {}],
		["select_window", "t1800", {}], ["confirm_burn", "", {}],
		["arrive_l1", "", {}], ["open_contact_list", "9001", {}],
		["crossfix", "", {"track": "9002", "track_level": 2}],
		["model_ident", "", {"track": "9002", "track_level": 3}],
		["iff_query", "2001", {}], ["ack_identity", "", {}],
		["select_ship", "harmattan", {}],
		["sensor_toggle", "harmattan/YW-R9", {"value": "on"}],
		["command_event", "", {"sequence": ["command.queued", "command.aborted"], "link": "LR"}],
		["state", "emission_state.harmattan.exposed", {"equals": true}],
		["open_roe_card", "", {}], ["decision", "HOLD", {}],
		["report_submit", "INTERNAL_AFTER_ACTION", {}],
	]
	for row in script:
		_ok(bool(full.note(row[0], row[1], row[2]).get("ok", false)),
			"通关动作 " + String(row[0]))
	_eq(int(_progress(full).get("completed", -1)), 17, "通关 completed=17")
	_eq(int(_progress(full).get("skipped", -1)), 3, "通关 skipped=3")
	_eq(int(_progress(full).get("resolved", -1)), 20, "通关 resolved=20")
	_eq(int(_progress(full).get("pending", -1)), 0, "通关 pending=0")
	_eq(int(_progress(full).get("goals_completed", -1)), 4, "通关 goals_completed=4")
	_ok(full.is_complete(), "is_complete=true")
	_eq((full.vm().get("current", {}) as Dictionary).size(), 0, "current 空")
	_eq((full.vm().get("hints", []) as Array).size(), 0, "hints 空")
	_eq((full.vm().get("completed", []) as Array).size(), 17, "completed 数组 17")
	_eq((full.vm().get("skipped", []) as Array).size(), 3, "skipped 数组 3")
	# reset
	full.reset()
	_eq(_completed(full), 0, "reset completed=0")
	_eq(_skipped(full), 0, "reset skipped=0")
	_eq(String(full.vm().get("current", {}).get("step_id", "")), "T07-G1-S1",
		"reset current 复位")
	_ok(not full.is_complete(), "reset 后未完成")
	_data_line("manual", "tick 不自动推进；skip/reset 正常；手动通关 17 完成+3 互斥跳过=20")

# ═══════════════════════════════════════════════════════════════════
# 7. 直接 trigger kind 兼容
# ═══════════════════════════════════════════════════════════════════

func _test_direct_kinds() -> void:
	_section_begin("7 直接 trigger kind")
	var c = Controller.new()
	var r1: Dictionary = c.note("ui_event", "prelude.opened", {"phase": "prelude"})
	_eq(String(r1.get("matched_step_id", "")), "T07-G1-S1", "ui_event 直接匹配")
	var r2: Dictionary = c.note("selection", "prelude.routes", {"value": "meridian"})
	_eq(String(r2.get("matched_step_id", "")), "T07-G1-S2", "selection 直接匹配")
	var r3: Dictionary = c.note("player_action", "prelude.confirm_burn")
	_eq(String(r3.get("matched_step_id", "")), "T07-G1-S4", "player_action 直接匹配（乱序）")
	# S3 仍 pending，S4 完成（乱序补触发）
	_eq(String(c.step_state("T07-G1-S4").get("status", "")), "completed", "S4 completed")
	_eq(String(c.step_state("T07-G1-S3").get("status", "")), "pending", "S3 pending")
	var r4: Dictionary = c.note("state", "prelude.transit_done", {"equals": true})
	_eq(String(r4.get("matched_step_id", "")), "T07-G1-S5", "state 直接匹配")
	var r5: Dictionary = c.note("manual_ack", "identity_legend")
	_eq(String(r5.get("matched_step_id", "")), "T07-G2-S5", "manual_ack 直接匹配（乱序）")
	var r6: Dictionary = c.note("report_submit", "INTERNAL_AFTER_ACTION")
	_eq(String(r6.get("matched_step_id", "")), "T07-G4-S6", "report_submit 直接匹配")
	var bad: Dictionary = c.note("selection", "prelude.routes", {"value": "wrong"})
	_ok(not bool(bad.get("ok", true)), "错误 selection 不触发")
	_data_line("direct", "ui_event/selection/player_action/state/manual_ack/report_submit 直接转发")

# ═══════════════════════════════════════════════════════════════════
# 8. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("8 JSON")
	var c = Controller.new()
	var vm: Dictionary = c.vm()
	var js := JSON.stringify(vm)
	_ok(js.length() > 5000, "vm JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "vm JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq(String(pd.get("schema", "")), "v17_teaching_controller.v1", "回读 schema")
		_ok(pd.get("goals") is Array, "回读 goals")
		_ok(pd.get("steps") is Array, "回读 steps")
		_ok(pd.get("current") is Dictionary, "回读 current")
		_ok(pd.get("hints") is Array, "回读 hints")
		_ok(pd.get("progress") is Dictionary, "回读 progress")
		_eq((pd.get("goals", []) as Array).size(), 4, "回读 goals=4")
		_eq((pd.get("steps", []) as Array).size(), 20, "回读 steps=20")
	var j2 := c.to_json()
	_ok(j2.length() > 5000, "to_json 输出", "len=%d" % j2.length())
	_ok(JSON.parse_string(j2) is Dictionary, "to_json 回读")
	var c2 = Controller.new()
	_ok(JSON.stringify(c2.vm()) == JSON.stringify(Controller.new().vm()),
		"两个新实例初始 VM 完全一致（确定性）")
	var c3 = Controller.new()
	c3.note("open_prelude", "", {"phase": "prelude"})
	var vm3: Dictionary = c3.vm()
	_ok((vm3.get("events", []) as Array).size() > 0, "events 记录")
	_ok(vm3.get("last_event") is Dictionary, "last_event 结构")
	_ok(String((vm3.get("last_event", {}) as Dictionary).get("action", "")) == "open_prelude",
		"last_event.action")
	_data_line("json", "vm=%d bytes · goals/steps/current/hints/progress 可回读 · 确定性" % js.length())
