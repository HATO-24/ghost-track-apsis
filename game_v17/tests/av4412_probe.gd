extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3W 最小 probe：Av4412Chain（轨道/窗口/对峙/谈判）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/av4412_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 UI/world。
# ═══════════════════════════════════════════════════════════════════

const Av4412Chain := preload("res://scripts/core/av4412_chain.gd")

const STATES := ["ORBIT_DEPARTURE", "WINDOW_OPEN", "EARLY_RADAR",
	"PASSIVE_CONTACT", "COMMS", "NEGOTIATION", "STRONG", "STANDARD",
	"QUESTION", "RETREAT", "RESOLUTION", "REPORT_HANDOFF"]
const ALL_ACTIONS := ["window_open", "early_radar", "passive_contact",
	"comms", "negotiation", "strong", "standard", "question", "retreat",
	"deputy_warn", "resolve", "report_handoff"]
const TEXT_KEYS := ["av4412.contact_rules", "av4412.negotiation_rules",
	"av4412.opening", "av4412.strong", "av4412.strong_aftermath",
	"av4412.standard", "av4412.standard_aftermath", "av4412.question",
	"av4412.question_aftermath", "av4412.retreat_rules",
	"av4412.retreat_ending", "av4412.standard_av_reply_tbd",
	"av4412.question_av_reply_tbd", "av4412.av_return_threat_tbd",
	"av4412.retreat_deputy_warn_1_tbd", "av4412.retreat_deputy_warn_2_tbd",
	"av4412.retreat_deputy_warn_3_tbd", "av4412.retreat_deputy_warn_4_tbd", "av4412.retreat_deputy_warn_5_tbd"]
const DOCS44 := "../docs/44_新剧本_2193.md"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3W PROBE · Av4412Chain")
	print("════════════════════════════════════════════════════════════")
	_test_setup_texts()
	_test_orbit_window()
	_test_four_options()
	_test_state_matrix()
	_test_retreat_warnings()
	_test_notes_save()
	_test_invalid_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 AV4412 CHAIN PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 AV4412 CHAIN PROBE FAILED")
		quit(1)
	else:
		print("V17 AV4412 CHAIN PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
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
		"actual=%.9f expected=%.9f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _fresh() -> Object:
	var c = Av4412Chain.new()
	_ok(bool(c.ready), "Av4412Chain ready", str(c.errors))
	return c

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

func _track(window_open := true, radar := false) -> Dictionary:
	return {"t": 10.0, "pos": [1.0, 2.0, 3.0], "vel": [0.0, 0.0, 0.0],
		"window_open": window_open, "radar_active": radar}

func _clean_doc_line(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with("> "):
		t = t.substr(2).strip_edges()
	if t.begins_with("- "):
		t = t.substr(2).strip_edges()
	t = t.replace("**", "")
	return t.strip_edges()

func _doc_lines() -> Array:
	var abs_path := ProjectSettings.globalize_path("res://").path_join(DOCS44).simplify_path()
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return []
	var ls: Array = f.get_as_text().split("\n")
	f.close()
	return ls

func _drive(option: String, radar := false, warnings := 5) -> Object:
	var c = _fresh()
	c.update_orbit(_track(true, radar))
	c.advance("window_open")
	c.advance("early_radar" if radar else "passive_contact")
	c.advance("comms")
	c.advance("negotiation")
	for i in range(warnings):
		c.advance("deputy_warn")
	c.advance(option)
	c.advance("resolve")
	c.advance("report_handoff")
	return c

func _to_option(option: String, warnings := 5) -> Object:
	var c = _fresh()
	c.update_orbit(_track(true, false))
	c.advance("window_open")
	c.advance("passive_contact")
	c.advance("comms")
	c.advance("negotiation")
	for i in range(warnings):
		c.advance("deputy_warn")
	c.advance(option)
	return c

func _to(state: String) -> Object:
	match state:
		"ORBIT_DEPARTURE":
			return _fresh()
		"WINDOW_OPEN":
			var c1 = _fresh(); c1.update_orbit(_track(true, false)); c1.advance("window_open"); return c1
		"EARLY_RADAR":
			var c2 = _fresh(); c2.update_orbit(_track(true, true)); c2.advance("window_open"); c2.advance("early_radar"); return c2
		"PASSIVE_CONTACT":
			var c3 = _fresh(); c3.update_orbit(_track(true, false)); c3.advance("window_open"); c3.advance("passive_contact"); return c3
		"COMMS":
			var c4 = _fresh(); c4.update_orbit(_track(true, false)); c4.advance("window_open"); c4.advance("passive_contact"); c4.advance("comms"); return c4
		"NEGOTIATION":
			var c5 = _fresh(); c5.update_orbit(_track(true, false)); c5.advance("window_open"); c5.advance("passive_contact"); c5.advance("comms"); c5.advance("negotiation"); return c5
		"STRONG":
			return _to_option("strong")
		"STANDARD":
			return _to_option("standard")
		"QUESTION":
			return _to_option("question")
		"RETREAT":
			return _to_option("retreat")
		"RESOLUTION":
			var c6 = _drive("strong")
			var clone = _fresh()
			# 通过保存/加载构造 RESOLUTION（避免重复 handoff）
			var st = c6.state
			c6.advance("report_handoff")
			var save = c6.save_state()
			var d = JSON.parse_string(save)
			d["state"] = "RESOLUTION"
			d["flags"].erase("report_handoff")
			clone.load_state(JSON.stringify(d))
			return clone
		"REPORT_HANDOFF":
			return _drive("strong")
	return _fresh()

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 文本
# ═══════════════════════════════════════════════════════════════════

func _test_setup_texts() -> void:
	_section_begin("1 setup/文本")
	var c = _fresh()
	_eq(c.current_state(), "ORBIT_DEPARTURE", "初始 ORBIT_DEPARTURE")
	_eq(c.contact(), "", "初始无接触")
	_eq(c.chosen(), "", "初始无选项")
	_eq(c.get_threat(), 0, "初始 threat 0")
	_eq(c.get_trust(), 0, "初始 trust 0")
	_eq(c.get_retreat_warnings(), 0, "初始 warnings 0")
	_eq(c.available_actions(), ["window_open"], "初始 actions")
	_eq((c.get_events() as Array).size(), 0, "初始无事件")
	_ok(bool(c.check_contracts().get("ok", false)), "初始 contracts ok")
	var sum: Dictionary = c.summary()
	_eq(str(sum.get("schema", "")), "v17.av4412_chain.v1", "summary schema")
	_eq(str(sum.get("entity_id", "")), "av_4412", "entity_id")
	_eq(bool(sum.get("auto_fire", true)), false, "不自动开火")
	_eq(bool(sum.get("writes_v15", true)), false, "不写 v15")
	_eq((c.text_keys_list() as Array).size(), 19, "19 文本 key")
	_eq((c.content.get("chain", []) as Array).size(), 12, "12 状态")
	_eq((c.content.get("options", []) as Array).size(), 4, "4 谈判选项")
	_eq(int(c.content.get("retreat_required_warnings", 0)), 5, "退让劝阻 5 次")
	# 文本结构 / TBD
	var doc: Array = _doc_lines()
	_ok(doc.size() > 250, "docs/44 可读")
	var tbd_count := 0
	for key in TEXT_KEYS:
		_ok(str(key) in c.text_keys_list(), "含文本 " + str(key))
		var t: Dictionary = c.text(str(key))
		_ok(not t.is_empty(), "text 存在 " + str(key))
		_ok(str(t.get("zh", "")) != "", "zh 非空 " + str(key))
		_ok(t.get("en") is String, "en 字符串 " + str(key))
		_eq(str(t.get("en", "x")), "", "en 不伪译 " + str(key))
		_ok(bool(t.get("draft", false)), "draft=true " + str(key))
		if bool(t.get("tbd", false)):
			tbd_count += 1
			_eq(str(t.get("zh", "")), "TBD", "TBD 不伪造 " + str(key))
		else:
			var zh := str(t.get("zh", ""))
			var matched := false
			for n in (t.get("source_lines", []) as Array):
				var idx := int(float(n)) - 1
				if idx >= 0 and idx < doc.size() and _clean_doc_line(str(doc[idx])) == zh:
					matched = true
					break
			_ok(matched, "逐字匹配 docs/44 " + str(key))
	_eq(tbd_count, 8, "8 个 TBD 占位")
	# 关键句
	_ok(str(c.text("av4412.opening").get("zh", "")).contains("远地点号，AV-4412 传唤者"), "开场喊话")
	_ok(str(c.text("av4412.opening").get("zh", "")).contains("接管 Chronos 加注站"), "接管条文")
	_ok(str(c.text("av4412.strong").get("zh", "")).contains("不会首先开火"), "强硬不开火")
	_ok(str(c.text("av4412.strong").get("zh", "")).contains("ROE至TIGHT"), "强硬 ROE TIGHT")
	_ok(str(c.text("av4412.standard").get("zh", "")).contains("标准回应"), "标准回应")
	_ok(str(c.text("av4412.question").get("zh", "")).contains("遥测数据"), "质疑遥测")
	_ok(str(c.text("av4412.retreat_rules").get("zh", "")).contains("多次弹出信息窗口劝阻"), "退让劝阻")
	_ok(str(c.text("av4412.retreat_ending").get("zh", "")).contains("彩蛋结局"), "退让彩蛋结局")
	_data_line("setup/texts", "12 状态/4 选项 · 19 文本（11 原文+8 TBD）· 开场/强硬/标准/质疑/退让 · TBD 不伪造")

# ═══════════════════════════════════════════════════════════════════
# 2. 轨道 / 窗口 / 雷达
# ═══════════════════════════════════════════════════════════════════

func _test_orbit_window() -> void:
	_section_begin("2 轨道/窗口/雷达")
	# 无轨道不能开窗
	var c = _fresh()
	_eq(str(c.advance("window_open").get("reason", "")), "missing_orbit", "无轨道 missing_orbit")
	# 非法轨道
	for bad in [{}, {"t": NAN, "pos": [0, 0, 0], "vel": [0, 0, 0],
			"window_open": true, "radar_active": false},
			{"t": 1.0, "pos": [0, 0], "vel": [0, 0, 0],
				"window_open": true, "radar_active": false},
			{"t": 1.0, "pos": [0, 0, NAN], "vel": [0, 0, 0],
				"window_open": true, "radar_active": false},
			{"t": 1.0, "pos": [0, 0, 0], "vel": [0, 0, 0],
				"window_open": "yes", "radar_active": false},
			{"t": 1.0, "pos": [0, 0, 0], "vel": [0, 0, 0],
				"window_open": true, "radar_active": 1}]:
		_eq(bool(c.update_orbit(bad).get("ok", true)), false, "非法轨道拒绝")
	_eq(str(c.current_state()), "ORBIT_DEPARTURE", "非法轨道不改状态")
	# 有效轨道原样保存
	var ur: Dictionary = c.update_orbit(_track(true, false))
	_eq(bool(ur.get("ok", false)), true, "轨道输入 ok")
	_eq(bool(ur.get("detected", true)), false, "未雷达/未接触 detected=false")
	_eq(bool(ur.get("window_closed", true)), false, "窗口未关")
	var tr: Dictionary = c.get_orbit_track()
	_eq((tr.get("pos", []) as Array), [1.0, 2.0, 3.0], "轨道 pos 原样")
	_eq((tr.get("vel", []) as Array), [0.0, 0.0, 0.0], "轨道 vel 原样")
	_near(float(tr.get("t", 0.0)), 10.0, 1.0e-9, "轨道 t 原样")
	_eq(str(c.current_state()), "ORBIT_DEPARTURE", "输入轨道不自动推进")
	# 窗口关闭轨道不能开窗
	var c2 = _fresh()
	c2.update_orbit(_track(false, false))
	_eq(str(c2.advance("window_open").get("reason", "")), "window_closed", "窗口关闭拒绝")
	# 开窗
	var c3 = _fresh()
	c3.update_orbit(_track(true, false))
	_eq(bool(c3.advance("window_open").get("ok", false)), true, "开窗 ok")
	_eq(str(c3.current_state()), "WINDOW_OPEN", "WINDOW_OPEN")
	# 雷达关闭：early 拒绝；passive 成功
	_eq(str(c3.advance("early_radar").get("reason", "")), "radar_inactive", "雷达未开 early 拒绝")
	c3.update_orbit(_track(true, true))
	_eq(str(c3.advance("passive_contact").get("reason", "")),
		"radar_active_mutually_exclusive", "雷达开 passive 拒绝")
	_eq(str(c3.current_state()), "WINDOW_OPEN", "拒绝后仍窗口")
	# 提前雷达
	var c4 = _fresh()
	c4.update_orbit(_track(true, true))
	c4.advance("window_open")
	var er: Dictionary = c4.advance("early_radar")
	_eq(bool(er.get("ok", false)), true, "early_radar ok")
	_eq(str(c4.current_state()), "EARLY_RADAR", "EARLY_RADAR")
	_eq(str(c4.contact()), "early_radar", "contact early")
	_eq(bool(c4.get_flag("window_closed_early")), true, "window_closed_early")
	var ds: Dictionary = c4.detection_status()
	_eq(bool(ds.get("detected", false)), true, "early detected")
	_eq(bool(ds.get("window_closed", false)), true, "early window_closed")
	# 被动
	var c5 = _fresh()
	c5.update_orbit(_track(true, false))
	c5.advance("window_open")
	var pc: Dictionary = c5.advance("passive_contact")
	_eq(bool(pc.get("ok", false)), true, "passive ok")
	_eq(str(c5.contact()), "passive", "contact passive")
	_eq(bool(c5.get_flag("passive_contact")), true, "passive flag")
	# 互斥：early/passive 二选一后另一动作不允许
	_eq(bool(c5.advance("early_radar").get("ok", true)), false, "被动后 early 拒绝")
	_eq(bool(c4.advance("passive_contact").get("ok", true)), false, "提前雷达后 passive 拒绝")
	_data_line("orbit", "真实轨道原样/非法拒绝 · 窗口开/关 · early/passive 互斥 · detected/window_closed")

# ═══════════════════════════════════════════════════════════════════
# 3. 四选项
# ═══════════════════════════════════════════════════════════════════

func _test_four_options() -> void:
	_section_begin("3 四选项")
	# strong
	var s = _drive("strong")
	_eq(str(s.current_state()), "REPORT_HANDOFF", "strong handoff")
	_eq(str(s.chosen()), "strong", "strong chosen")
	_eq(str(s.get_resolution()), "av4412_withdraw", "strong withdraw")
	_eq(int(s.get_threat()), 2, "strong threat+2")
	_eq(bool(s.get_flag("roe_tight")), true, "strong roe_tight")
	_eq(bool(s.get_flag("fire_control_illumination")), true, "strong 火控照射")
	_eq(s.get_flag("auto_fire"), false, "strong 不自动开火")
	var kinds: Array = []
	for raw in (s.get_events() as Array):
		kinds.append(str((raw as Dictionary).get("kind", "")))
	_ok("roe_tight" in kinds, "roe_tight 事件")
	_ok("fire_control_illumination" in kinds, "fire_control_illumination 事件")
	_ok(not ("weapon_launch" in kinds), "无 weapon_launch")
	_ok("av4412_strong" in s.trigger_ids(), "strong trigger")
	# standard
	var st = _drive("standard")
	_eq(str(st.get_resolution()), "av4412_threat", "standard threat resolution")
	_eq(int(st.get_threat()), 1, "standard threat+1")
	_eq(bool(st.get_flag("av4412_threatened")), true, "standard threatened")
	_eq(bool(st.get_flag("standard_av_reply_tbd")), true, "standard TBD flag")
	_ok("av4412_standard" in st.trigger_ids(), "standard trigger")
	# question
	var q = _drive("question")
	_eq(str(q.get_resolution()), "av4412_recall", "question recall")
	_eq(int(q.get_threat()), 0, "question threat 0")
	_eq(bool(q.get_flag("evidence_presented")), true, "question 证据")
	_eq(bool(q.get_flag("superior_recall")), true, "question 上级叫停")
	_eq(bool(q.get_flag("question_av_reply_tbd")), true, "question TBD flag")
	_ok("av4412_question" in q.trigger_ids(), "question trigger")
	# retreat
	var r = _drive("retreat", false, 5)
	_eq(str(r.current_state()), "REPORT_HANDOFF", "retreat handoff")
	_eq(str(r.get_resolution()), "death_ending", "retreat death ending")
	_eq(bool(r.get_flag("death_ending")), true, "retreat death flag")
	_eq(bool(r.get_flag("demo_end")), true, "retreat demo_end")
	_eq(bool(r.get_flag("retreat_once")), true, "retreat 仅一次")
	_eq(int(r.get_threat()), -1, "retreat threat-1")
	_ok(int(r.get_trust()) <= -6, "retreat trust 大幅下降", str(r.get_trust()))
	_ok("av4412_retreat" in r.trigger_ids(), "retreat trigger")
	_ok("av4412_death_ending" in r.trigger_ids(), "death trigger")
	var rrep: Dictionary = r.get_reputation()
	_eq(int(rrep.get("ocu", 0)), -3, "retreat ocu rep")
	_eq(int(rrep.get("meridian", 0)), -2, "retreat meridian rep")
	# 互斥：选择后不可改选
	var c = _fresh()
	c.update_orbit(_track(true, false)); c.advance("window_open"); c.advance("passive_contact"); c.advance("comms"); c.advance("negotiation")
	c.advance("strong")
	_eq(bool(c.advance("standard").get("ok", true)), false, "strong 后 standard 拒绝")
	_eq(str(c.current_state()), "STRONG", "互斥后状态不变")
	_data_line("options", "strong ROE TIGHT/火控 no-fire · standard 威胁 · question 证据/叫停 · retreat 死亡/trust")

# ═══════════════════════════════════════════════════════════════════
# 4. 状态/动作矩阵
# ═══════════════════════════════════════════════════════════════════

func _test_state_matrix() -> void:
	_section_begin("4 乱序矩阵")
	for st in STATES:
		var c: Object = _to(str(st))
		_eq(str(c.current_state()), str(st), "到达状态 " + str(st))
		var allowed: Array = c.available_actions()
		for action in ALL_ACTIONS:
			if action in allowed:
				_ok(c.can_advance(str(action)), "允许 " + str(st) + "/" + str(action))
			else:
				var before := str(c.current_state())
				var r: Dictionary = c.advance(str(action))
				_eq(bool(r.get("ok", true)), false, "乱序拒绝 " + str(st) + "/" + str(action))
				_eq(str(c.current_state()), before, "乱序不改状态 " + str(st))
				_ok(str(r.get("reason", "")) in ["invalid_transition", "missing_retreat_warnings"],
					"乱序 reason " + str(st) + "/" + str(action))
	# 手动：查询不推进
	var c2 = _fresh()
	c2.available_actions()
	c2.detection_status()
	_eq(str(c2.current_state()), "ORBIT_DEPARTURE", "手动查询不推进")
	_data_line("matrix", "12 状态 × 12 动作乱序拒绝 · state 不变 · 手动不自动")

# ═══════════════════════════════════════════════════════════════════
# 5. 退让劝阻
# ═══════════════════════════════════════════════════════════════════

func _test_retreat_warnings() -> void:
	_section_begin("5 退让劝阻")
	var c = _to("NEGOTIATION")
	# 未劝阻不可退让
	_eq(str(c.advance("retreat").get("reason", "")), "missing_retreat_warnings",
		"未劝阻 retreat 拒绝")
	_eq(c.get_retreat_warnings(), 0, "warnings 0")
	# 逐次劝阻 → TBD 文本 key
	var w1: Dictionary = c.advance("deputy_warn")
	_eq(bool(w1.get("ok", false)), true, "warn1 ok")
	_eq(int(w1.get("retreat_warnings", 0)), 1, "warn1 count")
	_eq(str(w1.get("warning_key", "")), "av4412.retreat_deputy_warn_1_tbd", "warn1 key")
	_eq(bool(w1.get("tbd", false)), true, "warn1 tbd")
	var w2: Dictionary = c.advance("deputy_warn")
	_eq(int(w2.get("retreat_warnings", 0)), 2, "warn2 count")
	_eq(str(w2.get("warning_key", "")), "av4412.retreat_deputy_warn_2_tbd", "warn2 key")
	var w3: Dictionary = c.advance("deputy_warn")
	_eq(int(w3.get("retreat_warnings", 0)), 3, "warn3 count")
	_eq(str(w3.get("warning_key", "")), "av4412.retreat_deputy_warn_3_tbd", "warn3 key")
	var w4: Dictionary = c.advance("deputy_warn")
	_eq(int(w4.get("retreat_warnings", 0)), 4, "warn4 count")
	_eq(str(w4.get("warning_key", "")), "av4412.retreat_deputy_warn_4_tbd", "warn4 key")
	var w5: Dictionary = c.advance("deputy_warn")
	_eq(int(w5.get("retreat_warnings", 0)), 5, "warn5 count")
	_eq(str(w5.get("warning_key", "")), "av4412.retreat_deputy_warn_5_tbd", "warn5 key")
	_eq(int(c.get_trust()), -5, "warnings trust 降低")
	# 已到最大再劝阻拒绝
	_eq(bool(c.advance("deputy_warn").get("ok", true)), false, "warn 超限拒绝")
	# 可退让
	var rr: Dictionary = c.advance("retreat")
	_eq(bool(rr.get("ok", false)), true, "劝阻后 retreat ok")
	_eq(str(c.current_state()), "RETREAT", "RETREAT")
	_eq(bool(c.get_flag("death_ending")), true, "death flag")
	_eq(bool(c.get_flag("demo_end")), true, "demo_end flag")
	# RESOLUTION/REPORT_HANDOFF 仍可手动
	_eq(bool(c.advance("resolve").get("ok", false)), true, "retreat resolve")
	_eq(str(c.get_resolution()), "death_ending", "retreat resolution")
	_eq(bool(c.advance("report_handoff").get("ok", false)), true, "retreat handoff")
	_eq(str(c.current_state()), "REPORT_HANDOFF", "retreat REPORT_HANDOFF")
	# 退让仅一次（到报告后无选项）
	_eq(c.available_actions(), [], "REPORT_HANDOFF 无 actions")
	_eq(bool(c.advance("retreat").get("ok", true)), false, "再次 retreat 拒绝")
	_data_line("retreat", "需 5 次劝阻 · TBD 文本 key · trust 降低 · death/demo_end · 仅一次")

# ═══════════════════════════════════════════════════════════════════
# 6. note / save-load
# ═══════════════════════════════════════════════════════════════════

func _test_notes_save() -> void:
	_section_begin("6 note/save")
	var c = _fresh()
	var n: Dictionary = c.note("av4412.opening")
	_eq(bool(n.get("ok", false)), true, "note ok")
	_ok(str(n.get("text", "")).contains("AV-4412"), "note text")
	var tn: Dictionary = c.note("av4412.av_return_threat_tbd")
	_eq(bool(tn.get("ok", false)), true, "TBD note ok")
	_eq(bool(tn.get("tbd", false)), true, "TBD note tbd")
	_ok(not bool(c.note("NOPE").get("ok", true)), "未知 note 拒绝")
	_eq((c.get_notes() as Array).size(), 2, "notes 2")
	_eq(str(c.current_state()), "ORBIT_DEPARTURE", "note 不改状态")
	# mid save/load
	var mid = _drive("strong")
	var save_mid := str(mid.save_state())
	var m2 = _fresh()
	_eq(bool(m2.load_state(save_mid).get("ok", false)), true, "mid load ok")
	_eq(_norm(mid.vm()), _norm(m2.vm()), "mid VM 一致")
	# final 四选项 save/load
	for opt in ["strong", "standard", "question"]:
		var fin = _drive(str(opt))
		var f2 = _fresh()
		_eq(bool(f2.load_state(str(fin.save_state())).get("ok", false)), true,
			"final load " + str(opt))
		_eq(_norm(fin.vm()), _norm(f2.vm()), "final VM " + str(opt))
	# retreat save/load
	var ret = _drive("retreat")
	var r2 = _fresh()
	_eq(bool(r2.load_state(str(ret.save_state())).get("ok", false)), true, "retreat load")
	_eq(str(r2.get_resolution()), "death_ending", "retreat load resolution")
	_eq(bool(r2.get_flag("demo_end")), true, "retreat load demo_end")
	# 非法存档
	var before := _norm(r2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.av4412_chain_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.av4412_chain_save.v1", "version": "1.0.0",
			"state": "BAD", "flags": {}, "evidence": [], "events": []}),
		JSON.stringify({"schema": "v17.av4412_chain_save.v1", "version": "1.0.0",
			"state": "COMMS", "flags": "bad", "evidence": [], "events": []}),
		JSON.stringify({"schema": "v17.av4412_chain_save.v1", "version": "1.0.0",
			"state": "COMMS", "flags": {}, "evidence": "bad", "events": []}),
		JSON.stringify({"schema": "v17.av4412_chain_save.v1", "version": "1.0.0",
			"state": "COMMS", "flags": {}, "evidence": [], "events": [], "chosen_option": "bad"})]
	for bad in bads:
		_eq(bool(r2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 30))
	_eq(_norm(r2.vm()), before, "非法存档不改状态")
	_data_line("note/save", "note 原文/TBD · mid/final/retreat save-load VM 一致 · 非法存档原子拒绝")

# ═══════════════════════════════════════════════════════════════════
# 7. 非法 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_invalid_determinism() -> void:
	_section_begin("7 非法/确定性")
	var c = _fresh()
	var before := _norm(c.vm())
	_eq(bool(c.advance("bogus").get("ok", true)), false, "非法 action 拒绝")
	_eq(str(c.advance("bogus").get("reason", "")), "invalid_transition", "非法 action reason")
	_eq(_norm(c.vm()), before, "非法 action 不改状态")
	# 非法内容
	var base := (c.content as Dictionary).duplicate(true)
	var bads: Array = []
	var b1 := base.duplicate(true); b1["schema"] = "bad"; bads.append(b1)
	var b2 := base.duplicate(true); b2["version"] = "9.9.9"; bads.append(b2)
	var b3 := base.duplicate(true); b3["texts"] = []; bads.append(b3)
	var b4 := base.duplicate(true); ((b4["texts"] as Array)[0] as Dictionary)["zh"] = ""; bads.append(b4)
	var b5 := base.duplicate(true); ((b5["texts"] as Array)[1] as Dictionary)["text_key"] = "av4412.contact_rules"; bads.append(b5)
	var b6 := base.duplicate(true); b6["chain"] = ["ORBIT_DEPARTURE"]; bads.append(b6)
	var b7 := base.duplicate(true); b7["options"] = ["strong"]; bads.append(b7)
	var b8 := base.duplicate(true); b8["retreat_required_warnings"] = 0; bads.append(b8)
	var b9 := base.duplicate(true); ((b9["texts"] as Array)[0] as Dictionary)["tbd"] = true; bads.append(b9)
	for i in range(bads.size()):
		var v: Dictionary = c.validate_content(bads[i])
		_eq(bool(v.get("ok", true)), false, "非法内容拒绝 #" + str(i))
	# 不存在文件
	var badc = Av4412Chain.new({"content_path": "/no/such.json"})
	_ok(not bool(badc.ready), "不存在内容拒绝")
	# 确定性
	var a = _drive("strong")
	var b = _drive("strong")
	_eq(_norm(a.vm()), _norm(b.vm()), "同路径 VM 一致")
	_eq(_norm(JSON.parse_string(a.save_state())),
		_norm(JSON.parse_string(b.save_state())), "同路径 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	# 无自动开火
	_eq(a.get_flag("auto_fire"), false, "无自动开火 flag")
	_data_line("invalid", "非法 action/内容/不存在文件拒绝 · 同路径确定 · 无自动开火")
