extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3A 最小 probe：StoryState 剧情状态服务
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/story_state_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不做 UI/文本/物理。
# ═══════════════════════════════════════════════════════════════════

const StoryState := preload("res://scripts/core/story_state.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3A PROBE · StoryState")
	print("════════════════════════════════════════════════════════════")
	_test_init()
	_test_flags()
	_test_evidence()
	_test_choices()
	_test_stats()
	_test_chapter_phase_time()
	_test_gate()
	_test_branches()
	_test_save_load()
	_test_errors_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 STORY STATE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 STORY STATE PROBE FAILED")
		quit(1)
	else:
		print("V17 STORY STATE PROBE OK")
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

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _state_json(s) -> String:
	return _norm_json({
		"flags": s.flags, "evidence_ids": s.evidence_ids, "choices": s.choices,
		"trust": s.trust, "morality": s.morality, "reputation": s.reputation,
		"threat": s.threat, "chapter": s.chapter, "phase": s.phase,
		"t_s": s.t_s, "revision": s.revision,
	})

func _fresh():
	var s = StoryState.new()
	_ok(bool(s.ready), "story state ready", str(s.errors))
	return s

# ═══════════════════════════════════════════════════════════════════
# 1. 初始 / VM
# ═══════════════════════════════════════════════════════════════════

func _test_init() -> void:
	_section_begin("1 初始/VM")
	var s = _fresh()
	_eq(s.errors.size(), 0, "无 errors")
	_eq(String(s.snapshot().get("schema", "")), "v17.story_state.v1", "schema")
	_eq(String(s.snapshot().get("version", "")), "1.0.0", "version")
	_eq(s.flags.size(), 0, "初始 flags 空")
	_eq(s.evidence_ids.size(), 0, "初始 evidence 空")
	_eq(s.choices.size(), 0, "初始 choices 空")
	_near(s.trust, 50.0, 1.0e-9, "trust 默认 50")
	_near(s.morality, 0.0, 1.0e-9, "morality 默认 0")
	_near(s.reputation, 50.0, 1.0e-9, "reputation 默认 50")
	_near(s.threat, 1.0, 1.0e-9, "threat 默认 1")
	_eq(s.chapter, "prelude", "chapter 默认 prelude")
	_eq(s.phase, "prelude", "phase 默认 prelude")
	_eq(s.revision, 1, "revision 初始 1")
	var vm: Dictionary = s.vm()
	_ok(vm.get("ranges") is Dictionary, "VM ranges")
	_eq((vm.get("branches", []) as Array).size(), 5, "VM 分支 5")
	_ok(bool(s.check_contracts().get("ok", false)), "初始 contracts ok")
	var snap: Dictionary = s.snapshot()
	_ok(snap.get("flags") is Dictionary, "VM flags 深拷贝")
	snap["flags"]["hack"] = true
	_ok(not s.has_flag("hack"), "VM 修改不影响内部")
	var before := _norm_json(s.snapshot())
	var json := s.to_json()
	_ok(JSON.parse_string(json) is Dictionary, "to_json 可回读")
	_eq(_norm_json(JSON.parse_string(json)), before, "to_json 与 snapshot 一致")
	_data_line("init", "defaults trust50/mor0/rep50/threat1 · branches5 · VM 只读")

# ═══════════════════════════════════════════════════════════════════
# 2. flags
# ═══════════════════════════════════════════════════════════════════

func _test_flags() -> void:
	_section_begin("2 flags")
	var s = _fresh()
	var r: Dictionary = s.set_flag("aeug_contact")
	_eq(bool(r.get("ok", false)), true, "set_flag ok")
	_ok(s.has_flag("aeug_contact"), "has_flag true")
	_eq(bool(s.flag_value("aeug_contact")), true, "flag value true")
	_ok(s.revision > 1, "set_flag 增加 revision")
	var r2: Dictionary = s.set_flag("count", 3)
	_eq(bool(r2.get("ok", false)), true, "flag 数值 ok")
	_eq(int(s.flag_value("count", -1)), 3, "flag 数值 3")
	_eq(bool(s.set_flag("count", false).get("ok", false)), true, "覆盖 flag")
	_eq(bool(s.has_flag("count")), true, "覆盖后仍存在")
	# 清除
	var c: Dictionary = s.clear_flag("count")
	_eq(bool(c.get("ok", false)), true, "clear_flag ok")
	_ok(not s.has_flag("count"), "clear 后不存在")
	# 未知 flag 清除拒绝
	var cu: Dictionary = s.clear_flag("no_such_flag")
	_eq(bool(cu.get("ok", true)), false, "未知 flag 清除拒绝")
	_eq(String(cu.get("reason", "")), "unknown_flag", "unknown_flag reason")
	# 非法名 / 非法值
	var bad_name: Dictionary = s.set_flag("Bad-Name")
	_eq(bool(bad_name.get("ok", true)), false, "非法 flag 名拒绝")
	var bad_val: Dictionary = s.set_flag("ok_name", [1, 2])
	_eq(bool(bad_val.get("ok", true)), false, "非标量 flag 值拒绝")
	_ok(not s.has_flag("ok_name"), "非法值不写入")
	_ok(bool(s.check_contracts().get("ok", false)), "flags 操作 contracts ok")
	_data_line("flags", "set/覆盖/清/未知拒绝/非法名/非法值")

# ═══════════════════════════════════════════════════════════════════
# 3. evidence
# ═══════════════════════════════════════════════════════════════════

func _test_evidence() -> void:
	_section_begin("3 evidence")
	var s = _fresh()
	var r: Dictionary = s.add_evidence("ev_ghost_track")
	_eq(bool(r.get("ok", false)), true, "add_evidence ok")
	_ok(s.has_evidence("ev_ghost_track"), "has_evidence true")
	_eq(s.evidence_ids.size(), 1, "evidence 数量 1")
	var dup: Dictionary = s.add_evidence("ev_ghost_track")
	_eq(bool(dup.get("ok", true)), false, "重复证据拒绝")
	_eq(String(dup.get("reason", "")), "duplicate_evidence", "duplicate reason")
	_eq(s.evidence_ids.size(), 1, "重复不增加")
	var bad: Dictionary = s.add_evidence("Bad-ID")
	_eq(bool(bad.get("ok", true)), false, "非法 evidence id 拒绝")
	_ok(not s.has_evidence("no_such"), "has_evidence 未知 false")
	_eq(bool(s.add_evidence("ev_a").get("ok", false)), true, "add ev_a")
	_eq(bool(s.add_evidence("ev_b").get("ok", false)), true, "add ev_b")
	_eq(s.evidence_ids.size(), 3, "evidence 3")
	_ok(bool(s.check_contracts().get("ok", false)), "evidence contracts ok")
	_data_line("evidence", "唯一/重复拒绝/非法 id 拒绝/排序")

# ═══════════════════════════════════════════════════════════════════
# 4. choices
# ═══════════════════════════════════════════════════════════════════

func _test_choices() -> void:
	_section_begin("4 choices")
	var s = _fresh()
	s.set_time(10.0)
	var ch: Dictionary = s.record_choice("ch_help", {"target": "apsis"})
	_eq(bool(ch.get("ok", false)), true, "record_choice ok")
	_ok(s.has_choice("ch_help"), "has_choice true")
	_eq(s.choices.size(), 1, "choices 1")
	var rec: Dictionary = s.choices[0]
	_eq(String(rec.get("choice_id", "")), "ch_help", "choice id")
	_near(float(rec.get("t_s", -1.0)), 10.0, 1.0e-9, "choice t_s")
	_eq(String(rec.get("chapter", "")), "prelude", "choice chapter")
	_eq(String(rec.get("phase", "")), "prelude", "choice phase")
	_eq(String((rec.get("meta", {}) as Dictionary).get("target", "")), "apsis", "choice meta")
	var dup: Dictionary = s.record_choice("ch_help")
	_eq(bool(dup.get("ok", true)), false, "重复 choice 拒绝")
	_eq(String(dup.get("reason", "")), "duplicate_choice", "duplicate choice reason")
	var bad: Dictionary = s.record_choice("Bad Choice")
	_eq(bool(bad.get("ok", true)), false, "非法 choice id 拒绝")
	_ok(not s.has_choice("Bad Choice"), "非法 choice 不写入")
	_eq(s.choices.size(), 1, "choices 仍 1")
	_ok(bool(s.check_contracts().get("ok", false)), "choices contracts ok")
	_data_line("choices", "唯一/重复拒绝/非法 id 拒绝/t-chapter-phase-meta 记录")

# ═══════════════════════════════════════════════════════════════════
# 5. 数值边界
# ═══════════════════════════════════════════════════════════════════

func _test_stats() -> void:
	_section_begin("5 数值边界")
	var s = _fresh()
	var t1: Dictionary = s.adjust_trust(10.0)
	_eq(bool(t1.get("ok", false)), true, "adjust_trust +10")
	_near(s.trust, 60.0, 1.0e-9, "trust=60")
	var t2: Dictionary = s.adjust_trust(1000.0)
	_near(s.trust, 100.0, 1.0e-9, "trust 上限 100")
	_eq(bool(t2.get("clamped", false)), true, "trust clamped")
	var t3: Dictionary = s.adjust_trust(-1000.0)
	_near(s.trust, 0.0, 1.0e-9, "trust 下限 0")
	_eq(bool(t3.get("clamped", false)), true, "trust 下限 clamped")
	var m1: Dictionary = s.adjust_morality(-250.0)
	_near(s.morality, -100.0, 1.0e-9, "morality 下限 -100")
	var m2: Dictionary = s.adjust_morality(500.0)
	_near(s.morality, 100.0, 1.0e-9, "morality 上限 100")
	var r1: Dictionary = s.adjust_reputation(-500.0)
	_near(s.reputation, 0.0, 1.0e-9, "reputation 下限 0")
	var r2: Dictionary = s.adjust_reputation(500.0)
	_near(s.reputation, 100.0, 1.0e-9, "reputation 上限 100")
	var th1: Dictionary = s.adjust_threat(0.5)
	_near(s.threat, 1.5, 1.0e-9, "threat +0.5")
	var th2: Dictionary = s.adjust_threat(100.0)
	_near(s.threat, 5.0, 1.0e-9, "threat 上限 5")
	var th3: Dictionary = s.adjust_threat(-100.0)
	_near(s.threat, 0.0, 1.0e-9, "threat 下限 0")
	# NaN / 非法
	var before: float = float(s.trust)
	var nan: Dictionary = s.adjust_trust(NAN)
	_eq(bool(nan.get("ok", true)), false, "NaN delta 拒绝")
	_near(s.trust, before, 1.0e-9, "NaN 不改变数值")
	var rev_before: int = s.revision
	var inf_res2: Dictionary = s.adjust_morality(INF)
	_eq(bool(inf_res2.get("ok", true)), false, "INF delta 拒绝")
	_ok(s.revision >= rev_before, "revision 单调")
	_ok(bool(s.check_contracts().get("ok", false)), "数值后 contracts ok")
	_data_line("stats", "trust[0,100]/morality[-100,100]/rep[0,100]/threat[0,5] clamp")

# ═══════════════════════════════════════════════════════════════════
# 6. chapter / phase / time
# ═══════════════════════════════════════════════════════════════════

func _test_chapter_phase_time() -> void:
	_section_begin("6 chapter/phase/time")
	var s = _fresh()
	_eq(bool(s.set_chapter("ch1_l1").get("ok", false)), true, "set_chapter ok")
	_eq(s.chapter, "ch1_l1", "chapter 更新")
	_eq(bool(s.set_phase("decision").get("ok", false)), true, "set_phase decision")
	_eq(s.phase, "decision", "phase 更新")
	var bad_phase: Dictionary = s.set_phase("no_such_phase")
	_eq(bool(bad_phase.get("ok", true)), false, "非法 phase 拒绝")
	_eq(String(bad_phase.get("reason", "")), "invalid_phase", "invalid_phase reason")
	_eq(s.phase, "decision", "非法 phase 不变")
	var bad_ch: Dictionary = s.set_chapter("")
	_eq(bool(bad_ch.get("ok", true)), false, "空 chapter 拒绝")
	# time 单调
	_eq(bool(s.set_time(100.0).get("ok", false)), true, "set_time 100")
	_near(s.t_s, 100.0, 1.0e-9, "t_s=100")
	var back: Dictionary = s.set_time(50.0)
	_eq(bool(back.get("ok", true)), false, "时间回退拒绝")
	_eq(String(back.get("reason", "")), "time_backwards", "time_backwards reason")
	_near(s.t_s, 100.0, 1.0e-9, "回退不改变 t_s")
	var neg: Dictionary = s.set_time(-1.0)
	_eq(bool(neg.get("ok", true)), false, "负时间拒绝")
	var nan: Dictionary = s.set_time(NAN)
	_eq(bool(nan.get("ok", true)), false, "NaN 时间拒绝")
	_ok(bool(s.check_contracts().get("ok", false)), "时间后 contracts ok")
	_data_line("chapter_phase_time", "chapter/phase 校验 · 时间单调")

# ═══════════════════════════════════════════════════════════════════
# 7. gate
# ═══════════════════════════════════════════════════════════════════

func _test_gate() -> void:
	_section_begin("7 gate")
	var s = _fresh()
	s.set_flag("aeug_contact", true)
	s.adjust_trust(10.0)   # 60
	s.add_evidence("ev_ghost_track")
	s.record_choice("ch_help")
	s.set_chapter("ch1")
	s.set_phase("decision")
	# 通过
	var g1: Dictionary = s.gate({"flags": ["aeug_contact"], "trust_min": 60.0})
	_eq(bool(g1.get("ok", false)), true, "gate 评估 ok")
	_eq(bool(g1.get("passed", false)), true, "gate flags+trust 通过")
	_eq((g1.get("failed", []) as Array).size(), 0, "gate failed 空")
	# 失败
	var g2: Dictionary = s.gate({"flags": ["aeug_contact"], "trust_min": 61.0})
	_eq(bool(g2.get("passed", true)), false, "trust_min 61 不通过")
	_ok((g2.get("failed", []) as Array).size() > 0, "失败有 failed 原因")
	var g3: Dictionary = s.gate({"flags": ["no_flag"]})
	_eq(bool(g3.get("passed", true)), false, "缺失 flag 不通过")
	_ok(str(g3.get("failed", [])).contains("flag_missing:no_flag"), "缺失 flag 原因")
	# flags_any / flags_not
	_eq(bool(s.gate({"flags_any": ["no_a", "aeug_contact"]}).get("passed", false)), true,
		"flags_any 通过")
	_eq(bool(s.gate({"flags_any": ["no_a", "no_b"]}).get("passed", true)), false,
		"flags_any 全无失败")
	_eq(bool(s.gate({"flags_not": ["no_a"]}).get("passed", false)), true, "flags_not 通过")
	_eq(bool(s.gate({"flags_not": ["aeug_contact"]}).get("passed", true)), false,
		"flags_not 存在失败")
	# evidence / choices / chapter / phase
	_eq(bool(s.gate({"evidence": ["ev_ghost_track"]}).get("passed", false)), true, "evidence 通过")
	_eq(bool(s.gate({"evidence": ["ev_no"]}).get("passed", true)), false, "缺证据失败")
	_eq(bool(s.gate({"choices": ["ch_help"]}).get("passed", false)), true, "choice 通过")
	_eq(bool(s.gate({"chapter": "ch1", "phase": "decision"}).get("passed", false)), true,
		"chapter+phase 通过")
	_eq(bool(s.gate({"chapter_in": ["ch1", "ch2"], "phase_in": ["decision", "read"]}).get("passed", false)),
		true, "chapter_in/phase_in 通过")
	_eq(bool(s.gate({"chapter_in": ["ch9"]}).get("passed", true)), false, "chapter_in 失败")
	# 数值边界 gate
	_eq(bool(s.gate({"morality_max": 0.0, "reputation_min": 50.0, "threat_max": 5.0}).get("passed", false)),
		true, "数值范围通过")
	_eq(bool(s.gate({"threat_max": 0.5}).get("passed", true)), false, "threat_max 0.5 失败")
	# 未知条件
	var bad: Dictionary = s.gate({"no_such_condition": 1})
	_eq(bool(bad.get("ok", true)), false, "未知 gate 条件拒绝")
	_eq(String(bad.get("reason", "")), "unknown_condition", "unknown_condition reason")
	var non_dict: Dictionary = s.gate([])
	_eq(bool(non_dict.get("ok", true)), false, "非对象 conditions 拒绝")
	_ok(bool(s.check_contracts().get("ok", false)), "gate contracts ok")
	_data_line("gate", "flags/any/not/evidence/choices/chapter/phase/数值范围 · 未知条件拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. 分支（数据化）
# ═══════════════════════════════════════════════════════════════════

func _test_branches() -> void:
	_section_begin("8 分支")
	var s = _fresh()
	_eq(s.branch_ids().size(), 5, "分支 5")
	for bid in ["aeug", "ghost_track", "procedural_justice", "misplaced_trust", "silence"]:
		_ok(bid in s.branch_ids(), "分支存在: " + bid)
	var initial: Array = s.evaluate_branches()
	_eq(initial.size(), 5, "evaluate_branches 5")
	for raw in initial:
		_ok(bool((raw as Dictionary).get("ok", false)), "分支评估 ok: " + String((raw as Dictionary).get("branch_id", "")))
		_ok(not bool((raw as Dictionary).get("passed", true)),
			"初始分支不通过: " + String((raw as Dictionary).get("branch_id", "")))
		_ok(String((raw as Dictionary).get("branch_name", "")) != "", "分支有 name")
	# AEUG
	s.set_flag("aeug_contact", true)
	s.adjust_trust(10.0)
	var aeug: Dictionary = s.evaluate_branch("aeug")
	_eq(bool(aeug.get("passed", false)), true, "AEUG 条件通过")
	_eq(String(aeug.get("branch_name", "")), "AEUG", "AEUG name")
	# GHOST TRACK
	s.set_flag("ghost_track_found", true)
	s.add_evidence("ev_ghost_track")
	_eq(bool(s.evaluate_branch("ghost_track").get("passed", false)), true, "GHOST TRACK 通过")
	# 程序正义
	s.set_flag("procedural_justice", true)
	s.adjust_reputation(10.0)   # 60
	_eq(bool(s.evaluate_branch("procedural_justice").get("passed", false)), true, "程序正义 通过")
	# 错付
	s.set_flag("misplaced_trust", true)
	s.adjust_trust(10.0)        # 70
	_eq(bool(s.evaluate_branch("misplaced_trust").get("passed", false)), true, "错付 通过")
	# 守口如瓶
	s.set_flag("silence_pact", true)
	s.adjust_threat(-100.0)     # 0 <=3
	_eq(bool(s.evaluate_branch("silence").get("passed", false)), true, "守口如瓶 通过")
	# 未知分支
	var unk: Dictionary = s.evaluate_branch("no_such_branch")
	_eq(bool(unk.get("ok", true)), false, "未知分支拒绝")
	_eq(String(unk.get("reason", "")), "unknown_branch", "unknown_branch reason")
	# 失败明细
	var s2 = _fresh()
	var fail: Dictionary = s2.evaluate_branch("aeug")
	_eq(bool(fail.get("passed", true)), false, "空状态 AEUG 不通过")
	_ok((fail.get("failed", []) as Array).size() > 0, "失败分支有 failed 明细")
	_ok(bool(s.check_contracts().get("ok", false)), "分支后 contracts ok")
	_data_line("branches", "AEUG/GHOST TRACK/程序正义/错付/守口如瓶 最小条件通过 · 未知分支拒绝")

# ═══════════════════════════════════════════════════════════════════
# 9. 存档
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("9 存档")
	var s = _fresh()
	s.set_flag("aeug_contact", true)
	s.set_flag("count", 2)
	s.add_evidence("ev_ghost_track")
	s.record_choice("ch_help", {"a": 1})
	s.adjust_trust(10.0)
	s.adjust_morality(-5.0)
	s.set_chapter("ch1")
	s.set_phase("decision")
	s.set_time(42.0)
	var saved := s.save_state()
	_ok(saved.length() > 200, "save_state 长度", "len=%d" % saved.length())
	var parsed = JSON.parse_string(saved)
	_ok(parsed is Dictionary, "save_state JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.story_state.v1", "save schema")
		_eq(String((parsed as Dictionary).get("version", "")), "1.0.0", "save version")
	var s2 = StoryState.new()
	var lr: Dictionary = s2.load(saved)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_eq(_norm_json(s.snapshot()), _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_eq(s2.flags.size(), s.flags.size(), "load flags 数量")
	_eq(s2.evidence_ids, s.evidence_ids, "load evidence")
	_eq(s2.choices.size(), s.choices.size(), "load choices")
	_near(s2.trust, s.trust, 1.0e-9, "load trust")
	_near(s2.morality, s.morality, 1.0e-9, "load morality")
	_eq(s2.chapter, s.chapter, "load chapter")
	_eq(s2.phase, s.phase, "load phase")
	_near(s2.t_s, s.t_s, 1.0e-9, "load t_s")
	_eq(s2.revision, s.revision, "load revision")
	# load 后可继续操作
	_eq(bool(s2.set_flag("loaded_flag").get("ok", false)), true, "load 后可写")
	# reset 回初始默认
	var s3 = _fresh()
	s3.set_flag("x", true)
	s3.adjust_trust(10.0)
	s3.reset()
	_eq(s3.flags.size(), 0, "reset flags 空")
	_near(s3.trust, 50.0, 1.0e-9, "reset trust 50")
	# 初始 seed
	var seeded = StoryState.new({"flags": {"aeug_contact": true}, "trust": 70.0,
		"evidence_ids": ["ev_a"], "chapter": "ch2", "phase": "decision", "t_s": 5.0})
	_ok(bool(seeded.ready), "seed 初始化 ready", str(seeded.errors))
	_ok(seeded.has_flag("aeug_contact"), "seed flag")
	_near(seeded.trust, 70.0, 1.0e-9, "seed trust")
	_ok(seeded.has_evidence("ev_a"), "seed evidence")
	_eq(seeded.chapter, "ch2", "seed chapter")
	_eq(seeded.phase, "decision", "seed phase")
	_data_line("save_load", "save/load snapshot 一致 · reset/seed")

# ═══════════════════════════════════════════════════════════════════
# 10. 非法 / JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_errors_json() -> void:
	_section_begin("10 非法/JSON/确定性")
	var s = _fresh()
	s.set_flag("aeug_contact", true)
	var before := _state_json(s)
	# 非法 load 不改变状态
	var cases := {
		"invalid_json": "{not json",
		"invalid_schema": JSON.stringify({"schema": "bad", "version": "1.0.0"}),
		"future": JSON.stringify({"schema": "v17.story_state.v1", "version": "9.0.0"}),
		"old": JSON.stringify({"schema": "v17.story_state.v1", "version": "0.9.0"}),
		"bad_trust": JSON.stringify({"schema": "v17.story_state.v1", "version": "1.0.0", "trust": 200.0}),
		"bad_phase": JSON.stringify({"schema": "v17.story_state.v1", "version": "1.0.0", "phase": "nope"}),
		"dup_evidence": JSON.stringify({"schema": "v17.story_state.v1", "version": "1.0.0",
			"evidence_ids": ["ev_a", "ev_a"]}),
	}
	for key in cases.keys():
		var br: Dictionary = s.load(cases[key])
		_eq(bool(br.get("ok", true)), false, "非法 load 拒绝：" + String(key), str(br.get("reason", "")))
		_eq(_state_json(s), before, "非法 load 不改变状态：" + String(key))
	# 非字符串/对象 load
	var bad_type: Dictionary = s.load(42)
	_eq(bool(bad_type.get("ok", true)), false, "非 JSON/对象 load 拒绝")
	# 拒绝操作不改变状态
	var v0: int = s.revision
	s.clear_flag("no_such")
	s.add_evidence("Bad-ID")
	s.record_choice("Bad ID")
	s.adjust_trust(NAN)
	_eq(s.revision, v0, "拒绝操作不增加 revision")
	_ok(s.errors.size() > 0, "拒绝记录 errors")
	_ok(s.contract_errors.size() > 0, "拒绝记录 contract_errors")
	_ok(bool(s.check_contracts().get("ok", false)), "拒绝后 contracts ok")
	# 确定性
	var a = _fresh()
	var b = _fresh()
	for st in [a, b]:
		st.set_flag("aeug_contact", true)
		st.add_evidence("ev_ghost_track")
		st.record_choice("ch_help")
		st.adjust_trust(10.0)
		st.set_phase("decision")
		st.set_time(10.0)
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "两次同操作 snapshot 一致")
	_ok(a.save_state() == b.save_state(), "两次同操作 save_state 一致")
	# 全分支 JSON / VM
	var vm: Dictionary = a.vm()
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "VM JSON 可解析")
	_ok(JSON.stringify(vm).length() > 500, "VM JSON 长度")
	_data_line("errors_json", "非法 load 不改变状态 · 拒绝无副作用 · 确定性一致")
