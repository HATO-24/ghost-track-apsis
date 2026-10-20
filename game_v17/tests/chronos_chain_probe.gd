extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3V 最小 probe：ChronosChain（港务/私人通信/行动链）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/chronos_chain_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 UI/world。
# ═══════════════════════════════════════════════════════════════════

const ChronosChain := preload("res://scripts/core/chronos_chain.gd")

const STATES := ["WAIT_DOCK", "PORT_COMM", "ACTION_EVAC", "PRIVATE_COMM",
	"CHOICE", "ACTIONS", "WINDOW_END", "COMPLETE"]
const TEXT_KEYS := ["chronos.port_header", "chronos.port_rdo",
	"chronos.evac_option", "chronos.private_comm", "chronos.accept",
	"chronos.reject", "chronos.trust_note", "chronos.actions_menu",
	"chronos.window_teaching"]
const ALL_ACTIONS := ["port_comm", "action_evac", "private_comm",
	"choose_accept", "choose_reject", "open_actions", "evac", "blackbox",
	"telemetry", "evidence", "window_end", "complete"]
const DOCS44 := "../docs/44_新剧本_2193.md"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3V PROBE · ChronosChain")
	print("════════════════════════════════════════════════════════════")
	_test_setup_texts()
	_test_accept_path()
	_test_reject_path()
	_test_state_matrix()
	_test_actions_repeat()
	_test_notes()
	_test_save_load()
	_test_invalid_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 CHRONOS CHAIN PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 CHRONOS CHAIN PROBE FAILED")
		quit(1)
	else:
		print("V17 CHRONOS CHAIN PROBE OK")
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

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _fresh() -> Object:
	var c = ChronosChain.new()
	_ok(bool(c.ready), "ChronosChain ready", str(c.errors))
	return c

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

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

func _drive(choice := "accept") -> Object:
	var c = _fresh()
	c.advance("port_comm")
	c.advance("action_evac")
	c.advance("private_comm")
	if choice == "reject":
		c.advance("choose_reject")
	else:
		c.advance("choose_accept")
	c.advance("open_actions")
	return c

func _to(state: String) -> Object:
	match state:
		"WAIT_DOCK":
			return _fresh()
		"PORT_COMM":
			var c1 = _fresh(); c1.advance("port_comm"); return c1
		"ACTION_EVAC":
			var c2 = _fresh(); c2.advance("port_comm"); c2.advance("action_evac"); return c2
		"PRIVATE_COMM":
			var c3 = _fresh(); c3.advance("port_comm"); c3.advance("action_evac"); c3.advance("private_comm"); return c3
		"CHOICE":
			var c4 = _fresh(); c4.advance("port_comm"); c4.advance("action_evac"); c4.advance("private_comm"); c4.advance("choose_accept"); return c4
		"ACTIONS":
			return _drive("accept")
		"WINDOW_END":
			var c6 = _drive("accept"); c6.advance("evac"); c6.advance("window_end"); return c6
		"COMPLETE":
			var c7 = _drive("accept"); c7.advance("evac"); c7.advance("window_end"); c7.advance("complete"); return c7
	return _fresh()

# ═══════════════════════════════════════════════════════════════════
# 1. setup / texts
# ═══════════════════════════════════════════════════════════════════

func _test_setup_texts() -> void:
	_section_begin("1 setup/文本")
	var c = _fresh()
	_eq(c.current_state(), "WAIT_DOCK", "初始 WAIT_DOCK")
	_eq(c.chosen_choice(), "", "初始未选择")
	_eq(c.get_trust(), 0, "初始 trust 0")
	_eq(c.trust_state(), "neutral", "初始 trust_state")
	_eq(c.available_actions(), ["port_comm"], "WAIT_DOCK actions")
	_eq((c.get_events() as Array).size(), 0, "初始无事件")
	_eq((c.get_evidence() as Array).size(), 0, "初始无证据")
	_ok(bool(c.check_contracts().get("ok", false)), "初始 contracts ok")
	var sum: Dictionary = c.summary()
	_eq(str(sum.get("schema", "")), "v17.chronos_chain.v1", "summary schema")
	_eq(str(sum.get("entity_id", "")), "chronos", "entity_id")
	_eq(bool(sum.get("writes_v15", true)), false, "不写 v15")
	_eq((c.text_keys_list() as Array).size(), 9, "9 文本 key")
	# state chain / actions content
	_eq((c.content.get("chain", []) as Array).size(), 8, "8 状态")
	_eq(int(float(c.content.get("trust", {}).get("accept", 0))), 2, "trust accept")
	_eq(int(float(c.content.get("trust", {}).get("reject", 0))), -1, "trust reject")
	# 文本结构
	for key in TEXT_KEYS:
		_ok(str(key) in c.text_keys_list(), "含文本 " + str(key))
		var t: Dictionary = c.text(str(key))
		_ok(not t.is_empty(), "text 存在 " + str(key))
		_ok(str(t.get("zh", "")) != "", "zh 非空 " + str(key))
		_ok(t.get("en") is String, "en 字符串 " + str(key))
		_eq(str(t.get("en", "x")), "", "en 不伪译 " + str(key))
		_ok((t.get("source_lines", []) as Array).size() > 0, "source_lines " + str(key))
		_ok(bool(t.get("draft", false)), "draft=true " + str(key))
	# 原文逐字 vs docs/44
	var doc: Array = _doc_lines()
	_ok(doc.size() > 190, "docs/44 可读")
	for key2 in TEXT_KEYS:
		var t2: Dictionary = c.text(str(key2))
		var zh := str(t2.get("zh", ""))
		var matched := false
		for n in (t2.get("source_lines", []) as Array):
			var idx := int(float(n)) - 1
			if idx >= 0 and idx < doc.size() and _clean_doc_line(str(doc[idx])) == zh:
				matched = true
				break
		_ok(matched, "逐字匹配 docs/44 " + str(key2))
	# 关键句
	_ok(str(c.text("chronos.port_rdo").get("zh", "")).contains("三号罐持续泄漏"), "港务三号罐")
	_ok(str(c.text("chronos.port_rdo").get("zh", "")).contains("不要拖走储罐"), "港务不要拖罐")
	_ok(str(c.text("chronos.private_comm").get("zh", "")).contains("黑匣子"), "私人通信黑匣子")
	_ok(str(c.text("chronos.private_comm").get("zh", "")).contains("港务遥测调度"), "私人通信遥测")
	_ok(str(c.text("chronos.accept").get("zh", "")).begins_with("是："), "接受文本")
	_ok(str(c.text("chronos.reject").get("zh", "")).begins_with("否："), "拒绝文本")
	_ok(str(c.text("chronos.trust_note").get("zh", "")).contains("信任度机制"), "信任度机制")
	_ok(str(c.text("chronos.window_teaching").get("zh", "")).contains("窗口期"), "窗口期教学")
	_data_line("setup/texts", "8 状态 · 9 文本逐字匹配 docs/44 · 港务/私人通信/接受拒绝/信任/窗口")

# ═══════════════════════════════════════════════════════════════════
# 2. accept 路径
# ═══════════════════════════════════════════════════════════════════

func _test_accept_path() -> void:
	_section_begin("2 accept 路径")
	var c = _fresh()
	var r1: Dictionary = c.advance("port_comm")
	_eq(bool(r1.get("ok", false)), true, "WAIT→PORT ok")
	_eq(str(c.current_state()), "PORT_COMM", "PORT_COMM")
	_eq(str(r1.get("trigger_id", "")), "chronos_port_comm", "port trigger")
	var r2: Dictionary = c.advance("action_evac")
	_eq(bool(r2.get("ok", false)), true, "PORT→ACTION_EVAC ok")
	_eq(bool(c.get_flag("evac_option")), true, "evac option flag")
	var r3: Dictionary = c.advance("private_comm")
	_eq(bool(r3.get("ok", false)), true, "ACTION→PRIVATE ok")
	_eq(str(c.current_state()), "PRIVATE_COMM", "PRIVATE_COMM")
	_eq(bool(c.get_flag("private_comm")), true, "private flag")
	var r4: Dictionary = c.advance("choose_accept")
	_eq(bool(r4.get("ok", false)), true, "accept ok")
	_eq(str(c.current_state()), "CHOICE", "CHOICE")
	_eq(str(c.chosen_choice()), "accept", "choice accept")
	_eq(int(c.get_trust()), 2, "accept trust +2")
	_eq(c.trust_state(), "trusted", "trust trusted")
	for k in ["blackbox_unlocked", "telemetry_unlocked", "evidence_unlocked",
			"future_suggestion_allowed", "accepted"]:
		_eq(bool(c.get_flag(k)), true, "accept flag " + k)
	# 互斥：accept 后 reject 不允许
	_eq(bool(c.advance("choose_reject").get("ok", true)), false, "accept 后 reject 拒绝")
	_eq(str(c.current_state()), "CHOICE", "拒绝后状态不变")
	# 打开行动
	var r5: Dictionary = c.advance("open_actions")
	_eq(bool(r5.get("ok", false)), true, "open_actions ok")
	_eq(str(c.current_state()), "ACTIONS", "ACTIONS")
	var acts: Array = c.available_actions()
	for a in ["evac", "blackbox", "telemetry", "evidence", "window_end"]:
		_ok(str(a) in acts, "accept 解锁 " + str(a))
	# 行动执行与输出
	var re: Dictionary = c.advance("evac")
	_eq(bool(re.get("ok", false)), true, "evac ok")
	_eq(bool(c.get_flag("evac_done")), true, "evac flag")
	var rb: Dictionary = c.advance("blackbox")
	_eq(bool(rb.get("ok", false)), true, "blackbox ok")
	_eq(bool(c.get_flag("evidence_blackbox")), true, "blackbox evidence flag")
	var rt: Dictionary = c.advance("telemetry")
	_eq(bool(rt.get("ok", false)), true, "telemetry ok")
	_eq(bool(c.get_flag("telemetry_done")), true, "telemetry flag")
	var rv: Dictionary = c.advance("evidence")
	_eq(bool(rv.get("ok", false)), true, "evidence ok")
	_eq(bool(c.get_flag("evidence_optional")), true, "evidence flag")
	# trust：accept+2 + blackbox+1 + telemetry+1 = 4
	_eq(int(c.get_trust()), 4, "行动后 trust=4")
	var rep: Dictionary = c.get_reputation()
	_eq(int(rep.get("ocu", 0)), 5, "ocu rep")
	_eq(int(rep.get("meridian", 0)), 2, "meridian rep")
	# 窗口结束：只标记 handoff，不自动开始 4412
	var rw: Dictionary = c.advance("window_end")
	_eq(bool(rw.get("ok", false)), true, "window_end ok")
	_eq(str(c.current_state()), "WINDOW_END", "WINDOW_END")
	_eq(bool(c.get_flag("window_ended")), true, "window flag")
	_eq(bool(c.get_flag("handoff_4412")), true, "handoff 4412 flag")
	_eq(str(rw.get("trigger_id", "")), "chronos_window_end", "window trigger")
	_eq(bool(c.is_complete()), false, "WINDOW_END 未自动完成")
	# 完成需手动
	var rc: Dictionary = c.advance("complete")
	_eq(bool(rc.get("ok", false)), true, "complete ok")
	_eq(str(c.current_state()), "COMPLETE", "COMPLETE")
	_eq(bool(c.is_complete()), true, "is_complete")
	_eq(c.available_actions(), [], "COMPLETE 无 actions")
	# 触发/事件/证据
	var trigs: Array = c.trigger_ids()
	for t in ["chronos_port_comm", "chronos_private_comm", "chronos_accept",
			"chronos_evac", "chronos_blackbox", "chronos_telemetry",
			"chronos_evidence", "chronos_window_end", "chronos_complete"]:
		_ok(str(t) in trigs, "触发 " + str(t))
	var events: Array = c.get_events()
	_ok(events.size() >= 9, "事件 >=9", str(events.size()))
	for raw in events:
		var e: Dictionary = raw
		_eq(str(e.get("schema", "")), "chronos_chain_event.v1", "事件 schema")
		_ok(str(e.get("action", "")) != "", "事件 action")
		_ok(str(e.get("from", "")) != "", "事件 from")
		_ok(str(e.get("to", "")) != "", "事件 to")
		_ok(int(e.get("trust", -999)) >= -10, "事件 trust 字段")
	var last_ev: Dictionary = events[events.size() - 1]
	_eq(int(last_ev.get("trust", -999)), int(c.get_trust()), "末事件 trust 一致")
	_ok((c.get_evidence() as Array).size() >= 8, "证据 >=8")
	_ok(bool(c.check_contracts().get("ok", false)), "final contracts ok")
	_data_line("accept", "全链路 · trust 0→2→4 · 解锁 blackbox/telemetry/evidence · 声望 · handoff · events")

# ═══════════════════════════════════════════════════════════════════
# 3. reject 路径
# ═══════════════════════════════════════════════════════════════════

func _test_reject_path() -> void:
	_section_begin("3 reject 路径")
	var c = _fresh()
	c.advance("port_comm")
	c.advance("action_evac")
	c.advance("private_comm")
	var rr: Dictionary = c.advance("choose_reject")
	_eq(bool(rr.get("ok", false)), true, "reject ok")
	_eq(str(c.current_state()), "CHOICE", "reject → CHOICE")
	_eq(str(c.chosen_choice()), "reject", "choice reject")
	_eq(int(c.get_trust()), -1, "reject trust -1")
	_eq(c.trust_state(), "cold", "trust cold")
	_eq(bool(c.get_flag("future_suggestion_allowed")), true, "reject 保留后续再建议")
	_eq(bool(c.get_flag("blackbox_unlocked")), false, "reject 不解锁黑匣子")
	# accept 后 reject 互斥
	_eq(bool(c.advance("choose_accept").get("ok", true)), false, "reject 后 accept 拒绝")
	# 打开行动：仅 evac/window_end
	c.advance("open_actions")
	_eq(str(c.current_state()), "ACTIONS", "reject ACTIONS")
	var acts: Array = c.available_actions()
	_ok("evac" in acts, "reject 仍可 evac")
	_ok(not ("blackbox" in acts), "reject 无 blackbox")
	_ok(not ("telemetry" in acts), "reject 无 telemetry")
	_ok(not ("evidence" in acts), "reject 无 evidence")
	# 尝试未解锁行动，失败不改状态
	var before := _norm(c.vm())
	var rb: Dictionary = c.advance("blackbox")
	_eq(bool(rb.get("ok", true)), false, "reject blackbox 拒绝")
	_eq(str(rb.get("reason", "")), "requires_accept", "requires_accept reason")
	_eq(_norm(c.vm()), before, "未解锁行动不改状态")
	# evac 可执行
	_eq(bool(c.advance("evac").get("ok", false)), true, "reject evac ok")
	# 声望：reject meridian-1 + evac meridian+1/ocu+1 = meridian0 ocu1
	var rep: Dictionary = c.get_reputation()
	_eq(int(rep.get("meridian", 0)), 0, "reject+evac meridian 0")
	_eq(int(rep.get("ocu", 0)), 1, "reject+evac ocu 1")
	# 窗口/完成
	_eq(bool(c.advance("window_end").get("ok", false)), true, "reject window ok")
	_eq(bool(c.get_flag("handoff_4412")), true, "reject handoff")
	_eq(bool(c.advance("complete").get("ok", false)), true, "reject complete")
	_eq(str(c.current_state()), "COMPLETE", "reject COMPLETE")
	_ok("chronos_reject" in c.trigger_ids(), "reject trigger")

	_data_line("reject", "trust -1 · future_suggestion_allowed · 未解锁行动拒绝 · evac/窗口/完成")

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
				_ok(str(r.get("reason", "")) in ["invalid_transition", "requires_accept", "already_done"],
					"乱序 reason " + str(st) + "/" + str(action))
	# 手动：查 actions 不推进
	var c2 = _fresh()
	c2.available_actions()
	c2.action_details()
	_eq(str(c2.current_state()), "WAIT_DOCK", "手动初始不自动推进")
	_data_line("matrix", "8 状态 × 12 动作乱序拒绝 · state 不变 · 不自动推进")

# ═══════════════════════════════════════════════════════════════════
# 5. 行动重复 / 详情
# ═══════════════════════════════════════════════════════════════════

func _test_actions_repeat() -> void:
	_section_begin("5 行动重复")
	var c = _drive("accept")
	# action_details 全部可用
	for d in c.action_details():
		_ok(bool((d as Dictionary).get("enabled", false)), "action_details enabled " + str(d.get("action", "")))
	# 每个行动只一次
	for act in ["evac", "blackbox", "telemetry", "evidence"]:
		_eq(bool(c.advance(str(act)).get("ok", false)), true, "执行 " + str(act))
		_eq(bool(c.advance(str(act)).get("ok", true)), false, "重复拒绝 " + str(act))
		_ok(str(c.advance(str(act)).get("reason", "")) in ["already_done", "invalid_transition"],
			"重复 reason " + str(act))
	# 完成后 window_end 用一次
	_eq(bool(c.advance("window_end").get("ok", false)), true, "window_end 一次")
	_eq(bool(c.advance("window_end").get("ok", true)), false, "window_end 重复拒绝")
	_eq(bool(c.advance("complete").get("ok", false)), true, "complete")
	_eq(bool(c.advance("complete").get("ok", true)), false, "complete 重复拒绝")
	# reject 路径 action_details 显示 requires_accept
	var r = _drive("reject")
	for d2 in r.action_details():
		var item: Dictionary = d2
		if str(item.get("action", "")) in ["blackbox", "telemetry", "evidence"]:
			_eq(bool(item.get("enabled", true)), false, "reject action disabled " + str(item.get("action", "")))
			_eq(str(item.get("reason", "")), "requires_accept", "reject reason " + str(item.get("action", "")))
		else:
			_ok(bool(item.get("enabled", false)), "reject 可用 " + str(item.get("action", "")))
	_data_line("repeat", "每个行动只一次 · window_end/complete 只一次 · reject 行动 requires_accept")

# ═══════════════════════════════════════════════════════════════════
# 6. note
# ═══════════════════════════════════════════════════════════════════

func _test_notes() -> void:
	_section_begin("6 note")
	var c = _fresh()
	var n: Dictionary = c.note("chronos.port_rdo")
	_eq(bool(n.get("ok", false)), true, "note ok")
	_ok(str(n.get("text", "")).contains("三号罐"), "note text")
	_eq(str(c.current_state()), "WAIT_DOCK", "note 不改状态")
	_eq((c.get_notes() as Array).size(), 1, "notes 1")
	_ok(not bool(c.note("NOPE").get("ok", true)), "未知 note 拒绝")
	_eq(str(c.note("NOPE").get("reason", "")), "unknown_text_key", "unknown reason")
	for key in TEXT_KEYS:
		_eq(bool(c.note(str(key)).get("ok", false)), true, "note " + str(key))
	_eq((c.get_notes() as Array).size(), 10, "10 notes")
	_eq(c.get_trust(), 0, "note 不改 trust")
	_eq(c.get_flags(), {}, "note 不改 flags")
	_eq((c.get_evidence() as Array).size(), 0, "note 不改 evidence")
	_data_line("note", "9 文本可 note · 未知拒绝 · 不改状态/trust/flags/evidence")

# ═══════════════════════════════════════════════════════════════════
# 7. save/load
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("7 save/load")
	var mid = _drive("accept")
	mid.advance("evac")
	var save_mid := str(mid.save_state())
	var m2 = _fresh()
	var lr: Dictionary = m2.load_state(save_mid)
	_eq(bool(lr.get("ok", false)), true, "mid load ok", str(lr.get("errors", [])))
	_eq(str(m2.current_state()), "ACTIONS", "mid state")
	_eq(int(m2.get_trust()), int(mid.get_trust()), "mid trust")
	_eq(_norm(mid.vm()), _norm(m2.vm()), "mid VM 一致")
	_eq(bool(m2.advance("blackbox").get("ok", false)), true, "load 后继续行动")
	# 终态
	var fin = _drive("accept")
	fin.advance("evac"); fin.advance("blackbox"); fin.advance("window_end"); fin.advance("complete")
	var fin2 = _fresh()
	_eq(bool(fin2.load_state(str(fin.save_state())).get("ok", false)), true, "final load ok")
	_eq(str(fin2.current_state()), "COMPLETE", "final state")
	_eq(str(fin2.chosen_choice()), "accept", "final choice")
	_eq(_norm(fin.vm()), _norm(fin2.vm()), "final VM 一致")
	# reject 存档
	var rej = _drive("reject")
	var rej2 = _fresh()
	_eq(bool(rej2.load_state(str(rej.save_state())).get("ok", false)), true, "reject load ok")
	_eq(str(rej2.chosen_choice()), "reject", "reject load choice")
	# 非法存档
	var before := _norm(fin2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.chronos_chain_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.chronos_chain_save.v1", "version": "1.0.0",
			"state": "BAD", "flags": {}, "choice": ""}),
		JSON.stringify({"schema": "v17.chronos_chain_save.v1", "version": "1.0.0",
			"state": "ACTIONS", "flags": "bad", "choice": "accept", "evidence": [], "events": []}),
		JSON.stringify({"schema": "v17.chronos_chain_save.v1", "version": "1.0.0",
			"state": "ACTIONS", "flags": {}, "choice": "bad", "evidence": [], "events": []}),
		JSON.stringify({"schema": "v17.chronos_chain_save.v1", "version": "1.0.0",
			"state": "ACTIONS", "flags": {}, "choice": "accept", "evidence": "bad", "events": []})]
	for bad in bads:
		_eq(bool(fin2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 30))
	_eq(_norm(fin2.vm()), before, "非法存档不改状态")
	_data_line("save", "mid/final/reject save-load VM 一致 · load 后继续 · 非法存档原子拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. 非法 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_invalid_determinism() -> void:
	_section_begin("8 非法/确定性")
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
	var b5 := base.duplicate(true); ((b5["texts"] as Array)[1] as Dictionary)["text_key"] = "chronos.port_header"; bads.append(b5)
	var b6 := base.duplicate(true); b6["chain"] = ["WAIT_DOCK"]; bads.append(b6)
	var b7 := base.duplicate(true); (b7["triggers"] as Dictionary)["port_comm"] = ""; bads.append(b7)
	var b8 := base.duplicate(true); b8["trust"] = "bad"; bads.append(b8)
	for i in range(bads.size()):
		var v: Dictionary = c.validate_content(bads[i])
		_eq(bool(v.get("ok", true)), false, "非法内容拒绝 #" + str(i))
	# 不存在文件
	var badc = ChronosChain.new({"content_path": "/no/such.json"})
	_ok(not bool(badc.ready), "不存在内容拒绝")
	# 确定性
	var a = _drive("accept")
	a.advance("evac"); a.advance("blackbox"); a.advance("telemetry"); a.advance("window_end"); a.advance("complete")
	var b = _drive("accept")
	b.advance("evac"); b.advance("blackbox"); b.advance("telemetry"); b.advance("window_end"); b.advance("complete")
	_eq(_norm(a.vm()), _norm(b.vm()), "同路径 VM 一致")
	_eq(_norm(JSON.parse_string(a.save_state())),
		_norm(JSON.parse_string(b.save_state())), "同路径 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("invalid", "非法 action/内容/不存在文件拒绝 · 同路径确定")
