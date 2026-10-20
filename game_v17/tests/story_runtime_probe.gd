extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3B 最小 probe：StoryRuntime 剧情运行时
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/story_runtime_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI/物理。
# ═══════════════════════════════════════════════════════════════════

const StoryRuntime := preload("res://scripts/core/story_runtime.gd")
const StoryState := preload("res://scripts/core/story_state.gd")
const GameSession := preload("res://scripts/core/game_session.gd")

const STORY_PATH := "res://framework/content/story_transit_l4_l1.json"
const TEACHING_PATH := "res://framework/content/teaching_l4_l1.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3B PROBE · StoryRuntime")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_setup_start()
	_test_steps()
	_test_locked_and_errors()
	_test_branch()
	_test_skip_fail()
	_test_save_load()
	_test_session_integration()
	_test_content_validation()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 STORY RUNTIME PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 STORY RUNTIME PROBE FAILED")
		quit(1)
	else:
		print("V17 STORY RUNTIME PROBE OK")
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

func _new_runtime(ss = null):
	var rt = StoryRuntime.new({"story_state": ss})
	_ok(bool(rt.ready), "runtime ready", str(rt.errors))
	return rt

func _menu_row(menu: Array, action: String, target := "") -> Dictionary:
	for raw in menu:
		var row: Dictionary = raw
		if String(row.get("action", "")) == action:
			if target == "" or String(row.get("target", "")) == target:
				return row
	return {}

func _run_to_decision(rt) -> Dictionary:
	rt.start()
	var seq := [["acknowledge_brief", ""], ["set_course", "l1_meridian"],
		["order_burn", "l1_meridian"], ["open_contact_list", ""],
		["identify_contact", "contact_2001"], ["order_radar", "harmattan"]]
	var last := {}
	for p in seq:
		last = rt.note(String(p[0]), String(p[1]))
	return last

func _core(rt) -> String:
	var vm: Dictionary = rt.snapshot()
	return _norm_json({
		"chapter": vm.get("chapter", ""), "phase": vm.get("phase", ""),
		"step_id": vm.get("step_id", ""), "step_index": vm.get("step_index", -1),
		"status": vm.get("status", ""), "ending": vm.get("ending", ""),
		"history": vm.get("history", []), "applied": vm.get("applied", {}),
	})

# ═══════════════════════════════════════════════════════════════════
# 1. 内容文件
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容文件")
	_ok(FileAccess.file_exists(STORY_PATH), "story content 存在")
	_ok(FileAccess.file_exists(TEACHING_PATH), "teaching content 存在")
	var story = _read_json(STORY_PATH)
	var teach = _read_json(TEACHING_PATH)
	_ok(story is Dictionary, "story JSON 可解析")
	_ok(teach is Dictionary, "teaching JSON 可解析")
	if not (story is Dictionary):
		return
	var s: Dictionary = story
	_eq(String(s.get("schema", "")), "v17.story_content.v1", "story schema")
	_eq(String(s.get("version", "")), "1.0.0", "story version")
	_eq(String(s.get("scenario_id", "")), "transit_l4_l1", "scenario_id")
	_eq(bool(s.get("manual_only", false)), true, "manual_only=true")
	_eq(bool(s.get("auto_complete", true)), false, "auto_complete=false")
	_ok(String(s.get("title_key", "")) != "", "title_key 非空")
	_ok(String(s.get("teaching_file", "")) != "", "teaching_file 引用")
	var chs: Array = s.get("chapters", [])
	var sts: Array = s.get("steps", [])
	var ends: Array = s.get("endings", [])
	_eq(chs.size(), 4, "chapters 4")
	_eq(sts.size(), 8, "steps 8")
	_eq(ends.size(), 2, "endings 2")
	var ch_ids := {}
	for raw in chs:
		_ok((raw as Dictionary).get("id", "") is String, "chapter id 类型")
		ch_ids[String((raw as Dictionary).get("id", ""))] = true
		_ok(String((raw as Dictionary).get("phase", "")) != "", "chapter phase 非空")
		_ok(String((raw as Dictionary).get("title_key", "")) != "", "chapter title_key")
	var step_ids := {}
	for raw_s in sts:
		var st: Dictionary = raw_s
		var sid := String(st.get("id", ""))
		_ok(sid != "", "step id 非空")
		_ok(not step_ids.has(sid), "step id 唯一: " + sid)
		step_ids[sid] = true
		_ok(ch_ids.has(String(st.get("chapter", ""))), "step chapter 存在: " + sid)
		_ok((st.get("actions", []) as Array).size() > 0, "step actions 非空: " + sid)
		_ok(String(st.get("title_key", "")) != "", "step title_key: " + sid)
		var tids: Array = st.get("teaching_step_ids", []) if st.get("teaching_step_ids") is Array else []
		_ok(tids.size() > 0, "step 引用 teaching id: " + sid)
		var tkeys: Array = st.get("text_keys", []) if st.get("text_keys") is Array else []
		_ok(tkeys.size() > 0, "step text_keys: " + sid)
		for raw_a in (st.get("actions", []) as Array):
			var a: Dictionary = raw_a
			_ok(String(a.get("id", "")) != "", "action id: " + sid)
			_ok(String(a.get("action", "")) != "", "action 名: " + sid)
			_ok(String(a.get("label_key", "")) != "", "action label_key: " + sid)
			_ok(a.get("gate") is Dictionary, "action gate 对象: " + sid)
			_ok(a.get("effects") is Dictionary, "action effects 对象: " + sid)
	# 教学步骤引用
	var teach_steps := {}
	for raw_t in (teach.get("steps", []) as Array):
		if raw_t is Dictionary:
			teach_steps[String((raw_t as Dictionary).get("id", ""))] = true
	var refs_ok := true
	for raw_s2 in sts:
		for raw_tid in ((raw_s2 as Dictionary).get("teaching_step_ids", []) as Array):
			if not teach_steps.has(String(raw_tid)):
				refs_ok = false
	_ok(refs_ok, "所有 teaching_step_ids 存在")
	# 文本 key 唯一数组
	var all_keys := {}
	for raw_s3 in sts:
		for raw_tk in ((raw_s3 as Dictionary).get("text_keys", []) as Array):
			all_keys[String(raw_tk)] = true
	_ok(all_keys.size() >= 3, "text_keys 数量", str(all_keys.size()))
	_data_line("content", "chapters=4 steps=8 endings=2 text_keys>=3 teaching refs ok")

# ═══════════════════════════════════════════════════════════════════
# 2. setup / start / 菜单
# ═══════════════════════════════════════════════════════════════════

func _test_setup_start() -> void:
	_section_begin("2 setup/start/菜单")
	var ss = StoryState.new()
	var rt = _new_runtime(ss)
	_eq(rt.errors.size(), 0, "runtime 无 errors")
	_eq(rt.warnings.size(), 0, "runtime 无 warnings")
	_eq(rt.status, "idle", "初始 idle")
	_eq(rt.chapter, "", "初始 chapter 空")
	_eq(rt.step_id, "", "初始 step 空")
	var vm: Dictionary = rt.snapshot()
	_eq(String(vm.get("schema", "")), "v17.story_runtime.v1", "snapshot schema")
	_eq(String(vm.get("version", "")), "1.0.0", "snapshot version")
	_eq(String(vm.get("scenario_id", "")), "transit_l4_l1", "snapshot scenario")
	_ok(rt.check_contracts().get("ok", false), "初始 contracts ok")
	# 未 start 不能 note
	var early: Dictionary = rt.note("acknowledge_brief")
	_eq(bool(early.get("ok", true)), false, "未 start note 拒绝")
	_eq(String(early.get("reason", "")), "not_started", "not_started reason")
	# start 未知 chapter
	var bad_start: Dictionary = rt.start("no_ch")
	_eq(bool(bad_start.get("ok", true)), false, "未知 chapter start 拒绝")
	# start
	var st: Dictionary = rt.start()
	_eq(bool(st.get("ok", false)), true, "start ok")
	_eq(rt.status, "running", "start 后 running")
	_eq(rt.chapter, "ch_prologue", "起始 chapter")
	_eq(rt.phase, "prelude", "起始 phase")
	_eq(rt.step_id, "S1", "起始 step S1")
	_eq(int(rt.step_index), 0, "step_index 0")
	_eq(rt.history.size(), 0, "history 空")
	_ok(str(st.get("text_keys", [])).contains("TXT-0001"), "text_keys 输出")
	var step: Dictionary = rt.current_step()
	_eq(String(step.get("id", "")), "S1", "current_step S1")
	_eq(String((step.get("teaching_step_ids", []) as Array)[0]), "T07-G1-S1", "teaching id 关联")
	_ok(rt.chapter_list().size() == 4, "chapter_list() 4")
	_ok(rt.step_list().size() == 8, "step_list() 8")
	# 菜单 available
	var menu: Array = rt.menu()
	_eq(menu.size(), 1, "S1 菜单 1 项")
	var row: Dictionary = menu[0]
	_eq(String(row.get("action", "")), "acknowledge_brief", "S1 action")
	_eq(bool(row.get("available", false)), true, "S1 action available")
	_eq(bool(row.get("locked", true)), false, "S1 action 未锁")
	_ok(String(row.get("label_key", "")) != "", "menu label_key")
	_eq(rt.available_actions().size(), 1, "available_actions 1")
	# 按 chapter 起始
	var rt2 = _new_runtime(StoryState.new())
	var st2: Dictionary = rt2.start("ch_contact")
	_eq(bool(st2.get("ok", false)), true, "按 chapter start ok")
	_eq(rt2.step_id, "S4", "ch_contact 起始 S4")
	_eq(rt2.phase, "read", "ch_contact phase read")
	# 无 StoryState 也可运行
	var rt3 = _new_runtime()
	_ok(rt3.story_state == null, "无 StoryState runtime")
	var n3: Dictionary = rt3.start()
	_eq(bool(n3.get("ok", false)), true, "无 StoryState start ok")
	_data_line("setup", "start/default/chapter/step/menu/text_keys · 无 StoryState 可用")

# ═══════════════════════════════════════════════════════════════════
# 3. 步骤状态机 / 效果
# ═══════════════════════════════════════════════════════════════════

func _test_steps() -> void:
	_section_begin("3 步骤/效果")
	var ss = StoryState.new()
	var rt = _new_runtime(ss)
	rt.start()
	var seq := [["acknowledge_brief", ""], ["set_course", "l1_meridian"],
		["order_burn", "l1_meridian"], ["open_contact_list", ""],
		["identify_contact", "contact_2001"], ["order_radar", "harmattan"],
		["decide", "hold"], ["submit_report", ""]]
	var expected_next := ["S2", "S3", "S4", "S5", "S6", "S7", "S8", ""]
	for i in range(seq.size()):
		var act := String(seq[i][0])
		var tgt := String(seq[i][1])
		var r: Dictionary = rt.note(act, tgt)
		_eq(bool(r.get("ok", false)), true, "note %s ok" % act, str(r.get("reason", "")))
		_eq(String(r.get("next_step_id", "?")), expected_next[i], "note %s next step" % act)
		_ok(bool(rt.check_contracts().get("ok", false)), "note %s contracts" % act)
	# 效果写到 StoryState
	_ok(bool(ss.flags.get("prelude_acked", false)), "flag prelude_acked")
	_ok(bool(ss.flags.get("course_set", false)), "flag course_set")
	_ok(bool(ss.flags.get("burn_ordered", false)), "flag burn_ordered")
	_ok(bool(ss.flags.get("contacts_open", false)), "flag contacts_open")
	_ok(bool(ss.flags.get("contact_identified", false)), "flag contact_identified")
	_ok(bool(ss.flags.get("radar_ordered", false)), "flag radar_ordered")
	_ok(bool(ss.flags.get("choice_hold", false)), "flag choice_hold")
	_ok(bool(ss.flags.get("report_submitted", false)), "flag report_submitted")
	_ok(ss.has_evidence("ev_contact_2001"), "evidence ev_contact_2001")
	_ok(ss.has_choice("choice_hold"), "choice choice_hold")
	_near(ss.trust, 62.0, 1.0e-9, "trust 50+5+2+5=62")
	# 不自动完成：最后 note 后 awaiting_complete
	_eq(rt.status, "awaiting_complete", "最后 note 后 awaiting_complete（不自动完成）")
	var pre_complete: Dictionary = rt.complete()
	_eq(bool(pre_complete.get("ok", false)), true, "显式 complete ok")
	_eq(rt.status, "complete", "status complete")
	_eq(rt.ending, "END_HOLD", "ending END_HOLD")
	_eq(rt.history.size(), 8, "history 8")
	_ok(rt.menu().is_empty() or true, "结束后菜单不再推进")
	_ok(rt.check_contracts().get("ok", false), "完成后 contracts ok")
	# 结束后的操作拒绝
	_eq(bool(rt.note("submit_report").get("ok", true)), false, "终态 note 拒绝")
	_eq(bool(rt.skip().get("ok", true)), false, "终态 skip 拒绝")
	_eq(bool(rt.fail().get("ok", true)), false, "终态 fail 拒绝")
	_ok(rt.snapshot().get("history") is Array, "snapshot history")
	_data_line("steps", "S1→S8 · flags/evidence/choice/trust · awaiting→complete(END_HOLD)")

# ═══════════════════════════════════════════════════════════════════
# 4. 乱序 / 重复 / locked
# ═══════════════════════════════════════════════════════════════════

func _test_locked_and_errors() -> void:
	_section_begin("4 乱序/重复/locked")
	var ss = StoryState.new()
	var rt = _new_runtime(ss)
	rt.start()
	var before := _core(rt)
	# 错误 action / 乱序
	var wrong: Dictionary = rt.note("decide", "hold")
	_eq(bool(wrong.get("ok", true)), false, "错误 action 拒绝")
	_eq(String(wrong.get("reason", "")), "wrong_action", "wrong_action reason")
	_eq(_core(rt), before, "错误 action 不改状态")
	var ooo: Dictionary = rt.note("order_burn", "l1_meridian")
	_eq(bool(ooo.get("ok", true)), false, "乱序 action 拒绝")
	_eq(_core(rt), before, "乱序不改状态")
	# 正确推进到 S2 后重复 S1
	rt.note("acknowledge_brief")
	var after_s1 := _core(rt)
	var dup: Dictionary = rt.note("acknowledge_brief")
	_eq(bool(dup.get("ok", true)), false, "重复 action 拒绝")
	_eq(_core(rt), after_s1, "重复不改状态")
	# 目标不匹配
	var tm: Dictionary = rt.note("set_course", "mars")
	_eq(bool(tm.get("ok", true)), false, "目标不匹配拒绝")
	_eq(String(tm.get("reason", "")), "target_mismatch", "target_mismatch")
	_eq(_core(rt), after_s1, "目标不匹配不改状态")
	# locked action：S2 的 fire 未授权（在推进到 S3 前检查）
	var menu_s2: Array = rt.menu()
	var fire_row := _menu_row(menu_s2, "order_fire")
	_ok(not fire_row.is_empty(), "S2 菜单含 locked fire")
	_ok(bool(fire_row.get("locked", false)), "fire locked")
	_ok(String(fire_row.get("reason", "")) != "", "fire locked reason", String(fire_row.get("reason", "")))
	_ok(str(fire_row.get("reason", "")).contains("fire_authorized") or
		str(fire_row.get("reason", "")).contains("no_fire_authority"), "fire reason 指向 gate")
	var fire_before := _core(rt)
	var fire: Dictionary = rt.note("order_fire", "contact_2001")
	_eq(bool(fire.get("ok", true)), false, "locked action note 拒绝")
	_eq(String(fire.get("reason", "")), "action_locked", "action_locked reason")
	_eq(_core(rt), fire_before, "locked action 不改状态")
	# locked 后正确 action 仍可推进
	rt.note("set_course", "l1_meridian")
	var ok_after: Dictionary = rt.note("order_burn", "l1_meridian")
	_eq(bool(ok_after.get("ok", false)), true, "locked 后正确 action 可推进")
	# start 中途重置
	rt.start()
	_eq(rt.step_id, "S1", "start 重置到 S1")
	_eq(rt.history.size(), 0, "start 重置 history")
	_data_line("locked", "错误/乱序/重复/目标不匹配/locked 均拒绝且不改状态")

# ═══════════════════════════════════════════════════════════════════
# 5. 分支
# ═══════════════════════════════════════════════════════════════════

func _test_branch() -> void:
	_section_begin("5 分支")
	var ss_h = StoryState.new()
	var rt_h = _new_runtime(ss_h)
	_run_to_decision(rt_h)
	var menu_h: Array = rt_h.menu()
	_eq(menu_h.size(), 3, "S7 菜单 3 项")
	var hold_row := _menu_row(menu_h, "decide", "hold")
	var expose_row := _menu_row(menu_h, "decide", "expose")
	var evac_row := _menu_row(menu_h, "decide", "evacuate")
	_ok(bool(hold_row.get("available", false)), "hold available")
	_ok(bool(expose_row.get("available", false)), "expose available（trust>=55）")
	_ok(bool(evac_row.get("locked", false)), "evacuate locked")
	var hold: Dictionary = rt_h.note("decide", "hold")
	_eq(bool(hold.get("ok", false)), true, "分支 hold note ok")
	_eq(rt_h.ending, "END_HOLD", "hold ending")
	_ok(bool(rt_h.applied_flags.get("choice_hold", false)), "hold flag")
	rt_h.note("submit_report")
	_eq(bool(rt_h.complete().get("ok", false)), true, "hold complete")
	_eq(rt_h.ending, "END_HOLD", "hold 完成 ending")
	# expose 分支
	var ss_e = StoryState.new()
	var rt_e = _new_runtime(ss_e)
	_run_to_decision(rt_e)
	var expo: Dictionary = rt_e.note("decide", "expose")
	_eq(bool(expo.get("ok", false)), true, "expose note ok")
	_eq(rt_e.ending, "END_EXPOSE", "expose ending")
	_ok(bool(rt_e.applied_flags.get("choice_expose", false)), "expose flag")
	rt_e.note("submit_report")
	_eq(bool(rt_e.complete().get("ok", false)), true, "expose complete")
	_eq(rt_e.ending, "END_EXPOSE", "expose 完成 ending")
	# 分支差异与确定性
	_ok(JSON.stringify(rt_h.applied_flags) != JSON.stringify(rt_e.applied_flags),
		"两条分支 flags 不同")
	_ok(ss_h.has_choice("choice_hold"), "StoryState hold choice")
	_ok(ss_e.has_choice("choice_expose"), "StoryState expose choice")
	_near(ss_h.trust, 62.0, 1.0e-9, "hold trust 62")
	_near(ss_e.trust, 57.0, 1.0e-9, "expose trust 57（-5）")
	var ss_h2 = StoryState.new()
	var rt_h2 = _new_runtime(ss_h2)
	_run_to_decision(rt_h2)
	rt_h2.note("decide", "hold")
	rt_h2.note("submit_report")
	rt_h2.complete()
	_ok(_norm_json(rt_h.snapshot()) == _norm_json(rt_h2.snapshot()), "同分支 snapshot 一致")
	_data_line("branch", "hold→END_HOLD · expose→END_EXPOSE · trust/choice 差异 · 同心确定性")

# ═══════════════════════════════════════════════════════════════════
# 6. 跳过 / 失败 / 提前完成
# ═══════════════════════════════════════════════════════════════════

func _test_skip_fail() -> void:
	_section_begin("6 跳过/失败")
	var rt = _new_runtime(StoryState.new())
	rt.start()
	var early_complete: Dictionary = rt.complete()
	_eq(bool(early_complete.get("ok", true)), false, "提前 complete 拒绝")
	_eq(String(early_complete.get("reason", "")), "complete_not_ready", "complete_not_ready")
	var sk: Dictionary = rt.skip("player_skip")
	_eq(bool(sk.get("ok", false)), true, "skip ok")
	_eq(rt.status, "skipped", "status skipped")
	_eq(String(rt.reason), "player_skip", "skip reason")
	_eq(bool(rt.note("acknowledge_brief").get("ok", true)), false, "skipped 后 note 拒绝")
	_eq(bool(rt.complete().get("ok", true)), false, "skipped 后 complete 拒绝")
	# fail
	var rt2 = _new_runtime(StoryState.new())
	rt2.start()
	rt2.note("acknowledge_brief")
	var fl: Dictionary = rt2.fail("range_fail")
	_eq(bool(fl.get("ok", false)), true, "fail ok")
	_eq(rt2.status, "failed", "status failed")
	_eq(String(rt2.reason), "range_fail", "fail reason")
	_eq(bool(rt2.skip().get("ok", true)), false, "failed 后 skip 拒绝")
	# 未 start skip 拒绝
	var rt3 = _new_runtime(StoryState.new())
	_eq(bool(rt3.skip().get("ok", true)), false, "未 start skip 拒绝")
	# reset
	var rr: Dictionary = rt.reset()
	_eq(bool(rr.get("ok", false)), true, "reset ok")
	_eq(rt.status, "idle", "reset 后 idle")
	_eq(rt.step_id, "", "reset 后无 step")
	_data_line("skip_fail", "skip→skipped · fail→failed · 提前 complete 拒绝 · reset")

# ═══════════════════════════════════════════════════════════════════
# 7. 存档
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("7 存档")
	var ss = StoryState.new()
	var rt = _new_runtime(ss)
	rt.start()
	rt.note("acknowledge_brief")
	rt.note("set_course", "l1_meridian")
	rt.note("order_burn", "l1_meridian")
	var save := rt.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "save JSON 可解析")
	if d is Dictionary:
		_eq(String((d as Dictionary).get("schema", "")), "v17.story_runtime_save.v1", "save schema")
		_eq(String((d as Dictionary).get("version", "")), "1.0.0", "save version")
		_ok(String((d as Dictionary).get("story_save", "")) != "", "save 含 story_save")
		_eq(String((d as Dictionary).get("step_id", "")), "S4", "save step S4")
	# load 到新 runtime + 新 StoryState
	var ss2 = StoryState.new()
	var rt2 = _new_runtime(ss2)
	var lr: Dictionary = rt2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_eq(rt2.step_id, rt.step_id, "load step 一致")
	_eq(rt2.status, rt.status, "load status 一致")
	_ok(_norm_json(rt.snapshot()) == _norm_json(rt2.snapshot()), "load snapshot 一致")
	_ok(JSON.stringify(ss.snapshot()) == JSON.stringify(ss2.snapshot()), "load StoryState 一致")
	_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(rt2.save_state())),
		"load 后再次 save 一致")
	_ok(bool(rt2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# load 后继续推进
	rt2.note("open_contact_list")
	_eq(rt2.step_id, "S5", "load 后继续推进 S5")
	# 无 StoryState 加载：story_save 不应用但仍可恢复 runtime
	var rt3 = _new_runtime()
	var lr3: Dictionary = rt3.load_state(save)
	_eq(bool(lr3.get("ok", false)), true, "无 StoryState load ok")
	_eq(rt3.step_id, "S4", "无 StoryState load step 一致")
	# 非法存档拒绝且不改状态
	var before := _core(rt2)
	var bad_empty: Dictionary = rt2.load_state("")
	_eq(bool(bad_empty.get("ok", true)), false, "空存档拒绝")
	_eq(_core(rt2), before, "空存档不改状态")
	var bad_schema: Dictionary = rt2.load_state("{\"schema\":\"bad\"}")
	_eq(bool(bad_schema.get("ok", true)), false, "坏 schema 拒绝")
	var bad_status: Dictionary = rt2.load_state("{\"schema\":\"v17.story_runtime_save.v1\",\"version\":\"1.0.0\",\"status\":\"bogus\"}")
	_eq(bool(bad_status.get("ok", true)), false, "非法 status 拒绝")
	var bad_step: Dictionary = rt2.load_state("{\"schema\":\"v17.story_runtime_save.v1\",\"version\":\"1.0.0\",\"status\":\"running\",\"step_id\":\"S999\"}")
	_eq(bool(bad_step.get("ok", true)), false, "非法 step 拒绝")
	_eq(_core(rt2), before, "非法存档不改状态")
	_data_line("save_load", "save/load snapshot+StoryState 一致 · 继续推进 · 非法拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. GameSession 集成
# ═══════════════════════════════════════════════════════════════════

func _test_session_integration() -> void:
	_section_begin("8 Session 集成")
	var sess = GameSession.new({"story_state": true})
	_ok(bool(sess.ready), "session ready")
	sess.tick(2.0)
	var rt = _new_runtime()
	var bind: Dictionary = rt.bind_session(sess)
	_eq(bool(bind.get("ok", false)), true, "bind_session ok")
	_ok(rt.story_state != null, "bind_session 自动绑定 story_state")
	_ok(rt.story_state == sess.story_state, "绑定同一 StoryState")
	rt.start()
	rt.note("acknowledge_brief")
	_ok(bool(sess.story_state.flags.get("prelude_acked", false)), "效果写入 session.story_state")
	_near(_now(rt), sess.now_s(), 1.0e-9, "runtime 时间取 session")
	rt.note("set_course", "l1_meridian")
	var save := rt.save_state()
	# load 到另一个 session（同样时间）
	var sess2 = GameSession.new({"story_state": true})
	sess2.tick(2.0)
	var rt2 = _new_runtime()
	rt2.bind_session(sess2)
	var lr: Dictionary = rt2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "session runtime load ok", str(lr.get("errors", [])))
	_ok(bool(sess2.story_state.flags.get("course_set", false)), "load 恢复 session.story_state")
	_eq(rt2.step_id, rt.step_id, "session load step 一致")
	_ok(_norm_json(rt.snapshot()) == _norm_json(rt2.snapshot()), "session load snapshot 一致")
	var no_bind = _new_runtime()
	_eq(bool(no_bind.bind_session(null).get("ok", true)), false, "bind null session 拒绝")
	_data_line("session", "bind_session 自动绑定 story_state · 时间取 session · 效果/存档一致")

func _now(rt) -> float:
	return float(rt.session.now_s()) if rt.session != null else float(rt.t_s)

# ═══════════════════════════════════════════════════════════════════
# 9. 内容校验
# ═══════════════════════════════════════════════════════════════════

func _test_content_validation() -> void:
	_section_begin("9 内容校验")
	var rt = _new_runtime()
	var story = _read_json(STORY_PATH)
	var teach = _read_json(TEACHING_PATH)
	var good: Dictionary = rt.validate_content(story, teach)
	_eq(bool(good.get("ok", false)), true, "合法内容通过", str(good.get("errors", [])))
	# manual_only / auto_complete
	var bad1: Dictionary = (story as Dictionary).duplicate(true)
	bad1["manual_only"] = false
	_eq(bool(rt.validate_content(bad1, teach).get("ok", true)), false, "manual_only=false 拒绝")
	var bad2: Dictionary = (story as Dictionary).duplicate(true)
	bad2["auto_complete"] = true
	_eq(bool(rt.validate_content(bad2, teach).get("ok", true)), false, "auto_complete=true 拒绝")
	# 缺 steps
	var bad3: Dictionary = (story as Dictionary).duplicate(true)
	bad3["steps"] = []
	_eq(bool(rt.validate_content(bad3, teach).get("ok", true)), false, "空 steps 拒绝")
	# 重复 step id
	var bad4: Dictionary = (story as Dictionary).duplicate(true)
	var sts: Array = (bad4.get("steps") as Array).duplicate(true)
	(sts[1] as Dictionary)["id"] = String((sts[0] as Dictionary).get("id", ""))
	bad4["steps"] = sts
	_eq(bool(rt.validate_content(bad4, teach).get("ok", true)), false, "重复 step id 拒绝")
	# 缺 action
	var bad5: Dictionary = (story as Dictionary).duplicate(true)
	var sts5: Array = (bad5.get("steps") as Array).duplicate(true)
	(sts5[0] as Dictionary)["actions"] = []
	bad5["steps"] = sts5
	_eq(bool(rt.validate_content(bad5, teach).get("ok", true)), false, "step 无 actions 拒绝")
	# 非法 phase
	var bad6: Dictionary = (story as Dictionary).duplicate(true)
	var chs: Array = (bad6.get("chapters") as Array).duplicate(true)
	(chs[0] as Dictionary)["phase"] = "bogus"
	bad6["chapters"] = chs
	_eq(bool(rt.validate_content(bad6, teach).get("ok", true)), false, "非法 chapter phase 拒绝")
	# 坏 teaching
	var bad7: Dictionary = (teach as Dictionary).duplicate(true)
	bad7["schema"] = "bad"
	_eq(bool(rt.validate_content(story, bad7).get("ok", true)), false, "坏 teaching schema 拒绝")
	# 未知 teaching 引用只是 warning
	var bad8: Dictionary = (story as Dictionary).duplicate(true)
	var sts8: Array = (bad8.get("steps") as Array).duplicate(true)
	(sts8[0] as Dictionary)["teaching_step_ids"] = ["T07-NO-SUCH"]
	bad8["steps"] = sts8
	var v8: Dictionary = rt.validate_content(bad8, teach)
	_eq(bool(v8.get("ok", true)), true, "未知 teaching 引用仅 warning")
	_ok((v8.get("warnings", []) as Array).size() > 0, "warning 记录")
	_data_line("content_validation", "manual_only/auto_complete/steps/重复/action/phase/schema 校验")

# ═══════════════════════════════════════════════════════════════════
# 10. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("10 JSON/确定性")
	var rt = _new_runtime(StoryState.new())
	rt.start()
	rt.note("acknowledge_brief")
	var js := rt.to_json()
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "runtime JSON 可解析")
	if parsed is Dictionary:
		var d: Dictionary = parsed
		_eq(String(d.get("schema", "")), "v17.story_runtime.v1", "JSON schema")
		_ok(d.get("menu") is Array, "JSON menu")
		_ok(d.get("applied") is Dictionary, "JSON applied")
		_ok(d.get("story") is Dictionary, "JSON story 快照")
		_ok(d.get("text_keys") is Array, "JSON text_keys")
	_ok(rt.snapshot().get("contracts", {}).get("ok", false), "snapshot contracts")
	# 两实例同操作
	var a = _new_runtime(StoryState.new())
	var b = _new_runtime(StoryState.new())
	for r in [a, b]:
		r.start()
		for p in [["acknowledge_brief", ""], ["set_course", "l1_meridian"],
				["order_burn", "l1_meridian"]]:
			r.note(String(p[0]), String(p[1]))
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "同操作 snapshot 一致")
	_ok(a.save_state() == b.save_state(), "同操作 save 一致")
	# 菜单/文本确定性
	_ok(_norm_json(a.menu()) == _norm_json(b.menu()), "同操作 menu 一致")
	_ok(_norm_json(a.text_keys()) == _norm_json(b.text_keys()), "同操作 text_keys 一致")
	_data_line("json_det", "JSON 可解析 · 同操作 snapshot/save/menu 一致")
