extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3U 最小 probe：CeresChain（谷神-2 识别/救援链）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/ceres_chain_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 UI/world。
# ═══════════════════════════════════════════════════════════════════

const CeresChain := preload("res://scripts/core/ceres_chain.gd")

const STATES := ["L1", "L2", "L3", "LIGHT_READ", "L4_TYPE", "RESCUE_PROMPT",
	"RESCUED", "IGNORED", "COMPLETE"]
const TEXT_KEYS := ["ceres.fault", "ceres.l2", "ceres.l3_l4",
	"ceres.identify_prompt", "ceres.vis_read", "ceres.rescue_prompt",
	"ceres.rescue_yes", "ceres.rescue_no", "ceres.optional_note"]
const DOCS44 := "../docs/44_新剧本_2193.md"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3U PROBE · CeresChain")
	print("════════════════════════════════════════════════════════════")
	_test_setup_texts()
	_test_happy_paths()
	_test_transition_matrix()
	_test_evidence_inputs()
	_test_notes()
	_test_save_load()
	_test_invalid_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 CERES CHAIN PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 CERES CHAIN PROBE FAILED")
		quit(1)
	else:
		print("V17 CERES CHAIN PROBE OK")
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
	var c = CeresChain.new()
	_ok(bool(c.ready), "CeresChain ready", str(c.errors))
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

func _drive(data := {}) -> Object:
	var c = _fresh()
	c.advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	c.advance("identify_l3", {"level": "L2"})
	c.advance("read_light", {"light_code": "7700"})
	c.advance("classify_l4")
	c.advance("rescue_prompt")
	if str(data.get("choice", "")) == "rescue":
		c.advance("rescue")
	elif str(data.get("choice", "")) == "ignore":
		c.advance("ignore")
	return c

func _to(state: String) -> Object:
	var c = _drive()
	match state:
		"L1":
			return _fresh()
		"L2":
			var c2 = _fresh(); c2.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}); return c2
		"L3":
			var c3 = _fresh(); c3.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}); c3.advance("identify_l3", {"level": "L2"}); return c3
		"LIGHT_READ":
			var c4 = _fresh(); c4.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}); c4.advance("identify_l3", {"level": "L2"}); c4.advance("read_light", {"light_code": "7700"}); return c4
		"L4_TYPE":
			var c5 = _fresh(); c5.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}); c5.advance("identify_l3", {"level": "L2"}); c5.advance("read_light", {"light_code": "7700"}); c5.advance("classify_l4"); return c5
		"RESCUE_PROMPT":
			return _drive()
		"RESCUED":
			return _drive({"choice": "rescue"})
		"IGNORED":
			return _drive({"choice": "ignore"})
		"COMPLETE":
			var c9 = _drive({"choice": "rescue"}); c9.advance("complete"); return c9
	return c

# ═══════════════════════════════════════════════════════════════════
# 1. setup / texts
# ═══════════════════════════════════════════════════════════════════

func _test_setup_texts() -> void:
	_section_begin("1 setup/文本")
	var c = _fresh()
	_eq(c.current_state(), "L1", "初始 L1")
	_eq(c.chosen_action(), "", "初始未选择")
	_eq(c.available_actions(), ["data_link_l2"], "L1 actions")
	_eq(c.get_reputation(), {}, "初始声望空")
	_eq((c.get_events() as Array).size(), 0, "初始无事件")
	_eq((c.get_evidence() as Array).size(), 0, "初始无证据")
	_ok(bool(c.check_contracts().get("ok", false)), "初始 contracts ok")
	var sum: Dictionary = c.summary()
	_eq(str(sum.get("schema", "")), "v17.ceres_chain.v1", "summary schema")
	_eq(str(sum.get("entity_id", "")), "ceres_2", "entity_id=ceres_2")
	_eq(str(sum.get("state", "")), "L1", "summary state")
	_eq(bool(sum.get("writes_v15", true)), false, "不写 v15")
	_eq((c.text_keys_list() as Array).size(), 9, "9 文本 key")
	for key in TEXT_KEYS:
		_ok(str(key) in c.text_keys_list(), "含文本 " + str(key))
		var t: Dictionary = c.text(str(key))
		_ok(not t.is_empty(), "text 存在 " + str(key))
		_ok(str(t.get("zh", "")) != "", "zh 非空 " + str(key))
		_ok(t.get("en") is String, "en 字符串 " + str(key))
		_eq(str(t.get("en", "x")), "", "en 不伪译 " + str(key))
		_ok((t.get("source_lines", []) as Array).size() > 0, "source_lines " + str(key))
		_ok(bool(t.get("draft", false)), "draft=true " + str(key))
	# 原文逐字 vs docs/44（清理 > / - / ** 标记后）
	var doc: Array = _doc_lines()
	_ok(doc.size() > 150, "docs/44 可读")
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
	# 关键内容
	_ok(str(c.text("ceres.fault").get("zh", "")).contains("应答机不工作"), "fault 应答机")
	_ok(str(c.text("ceres.fault").get("zh", "")).contains("可见光灯语"), "fault 灯语")
	_ok(str(c.text("ceres.l2").get("zh", "")).contains("L2"), "L2 教学")
	_ok(str(c.text("ceres.l3_l4").get("zh", "")).contains("VIS"), "L3/L4 VIS")
	_ok(str(c.text("ceres.vis_read").get("zh", "")).contains("自动读取灯号"), "VIS 自动读灯")
	_ok(str(c.text("ceres.vis_read").get("zh", "")).contains("谷神-2型作业船"), "型号识别")
	_ok(str(c.text("ceres.rescue_prompt").get("zh", "")).contains("是否派遣拖船"), "救援问句")
	_ok(str(c.text("ceres.rescue_yes").get("zh", "")).begins_with("是："), "救援是")
	_ok(str(c.text("ceres.rescue_no").get("zh", "")).begins_with("否："), "救援否")
	# content schema 字段
	_eq(str(c.content.get("schema", "")), "v17.story_ceres.v1", "content schema")
	_eq(str(c.content.get("chain", [])), str(STATES), "chain 顺序")
	_eq(str(c.content.get("emergency_light_code", "")), "7700", "light code")
	_eq((c.content.get("chain", []) as Array).size(), 9, "9 状态")
	_data_line("setup/texts", "9 状态 · 9 文本逐字匹配 docs/44 · 应答机/灯语/VIS/救援是/否 · en 空")

# ═══════════════════════════════════════════════════════════════════
# 2. happy paths / rescue
# ═══════════════════════════════════════════════════════════════════

func _test_happy_paths() -> void:
	_section_begin("2 happy path")
	var c = _fresh()
	var r1: Dictionary = c.advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	_eq(bool(r1.get("ok", false)), true, "L1→L2 ok")
	_eq(str(r1.get("from_state", "")), "L1", "L2 from")
	_eq(str(r1.get("state", "")), "L2", "L2 state")
	_eq(str(c.current_state()), "L2", "current L2")
	_eq(bool(c.get_flag("l2_data_link")), true, "L2 flag")
	var r2: Dictionary = c.advance("identify_l3", {"level": "L2"})
	_eq(bool(r2.get("ok", false)), true, "L2→L3 ok")
	_eq(str(c.current_state()), "L3", "current L3")
	_eq(bool(c.get_flag("l3_identified")), true, "L3 flag")
	var r3: Dictionary = c.advance("read_light", {"light_code": "7700"})
	_eq(bool(r3.get("ok", false)), true, "L3→LIGHT_READ ok")
	_eq(str(c.current_state()), "LIGHT_READ", "current LIGHT_READ")
	_eq(str(r3.get("trigger_id", "")), "ceres_light_read", "light trigger")
	_eq(bool(c.get_flag("light_read")), true, "light flag")
	var r4: Dictionary = c.advance("classify_l4")
	_eq(bool(r4.get("ok", false)), true, "LIGHT→L4 ok")
	_eq(str(c.current_state()), "L4_TYPE", "current L4_TYPE")
	_eq(bool(c.get_flag("type_identified")), true, "type flag")
	_eq(str(c.get_flag("l4_type")), "ceres_2", "l4 type")
	var r5: Dictionary = c.advance("rescue_prompt")
	_eq(bool(r5.get("ok", false)), true, "L4→RESCUE_PROMPT ok")
	_eq(str(r5.get("trigger_id", "")), "ceres_rescue_prompt", "prompt trigger")
	var r6: Dictionary = c.advance("rescue")
	_eq(bool(r6.get("ok", false)), true, "rescue ok")
	_eq(str(c.current_state()), "RESCUED", "current RESCUED")
	_eq(str(r6.get("trigger_id", "")), "ceres_rescued", "rescued trigger")
	_eq(str(c.chosen_action()), "rescue", "chosen rescue")
	var rep: Dictionary = c.get_reputation()
	_eq(int(rep.get("meridian", 0)), 2, "rescued meridian rep")
	_eq(int(rep.get("outer", 0)), 1, "rescued outer rep")
	_eq(int(rep.get("ocu", 0)), 1, "rescued ocu rep")
	# 互斥/只能一次
	_eq(bool(c.advance("ignore").get("ok", true)), false, "rescue 后 ignore 拒绝")
	_eq(bool(c.advance("rescue").get("ok", true)), false, "rescue 重复拒绝")
	_eq(str(c.current_state()), "RESCUED", "拒绝后状态不变")
	# 完成需手动
	_eq(bool(c.advance("complete").get("ok", false)), true, "complete ok")
	_eq(str(c.current_state()), "COMPLETE", "COMPLETE")
	_eq(bool(c.is_complete()), true, "is_complete")
	_eq(c.available_actions(), [], "COMPLETE 无 actions")
	_eq(bool(c.advance("complete").get("ok", true)), false, "重复 complete 拒绝")
	# 事件/触发/证据
	var events: Array = c.get_events()
	_ok(events.size() >= 7, "事件 >=7", str(events.size()))
	for raw in events:
		var e: Dictionary = raw
		_eq(str(e.get("schema", "")), "ceres_chain_event.v1", "事件 schema")
		_ok(str(e.get("action", "")) != "", "事件 action")
		_ok(str(e.get("from", "")) != "", "事件 from")
		_ok(str(e.get("to", "")) != "", "事件 to")
		_ok(str(e.get("writes_v15", true)) == "false" or e.get("writes_v15") == false,
			"事件不写 v15")
	var trigs: Array = c.trigger_ids()
	for t in ["ceres_light_read", "ceres_rescue_prompt", "ceres_rescued", "ceres_complete"]:
		_ok(str(t) in trigs, "触发 " + str(t))
	_ok((c.get_evidence() as Array).size() >= 6, "证据 >=6")
	_ok(bool(c.check_contracts().get("ok", false)), "final contracts ok")
	# ignore 路径
	var ci = _fresh()
	ci.advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	ci.advance("identify_l3", {"level": "L2"})
	ci.advance("read_light", {"light_code": "7700"})
	ci.advance("classify_l4")
	ci.advance("rescue_prompt")
	var ri: Dictionary = ci.advance("ignore")
	_eq(bool(ri.get("ok", false)), true, "ignore ok")
	_eq(str(ci.current_state()), "IGNORED", "IGNORED")
	_eq(str(ri.get("trigger_id", "")), "ceres_ignored", "ignored trigger")
	var repi: Dictionary = ci.get_reputation()
	_eq(int(repi.get("meridian", 0)), -1, "ignore meridian -1")
	_eq(int(repi.get("outer", 0)), -2, "ignore outer -2")
	_eq(bool(ci.advance("rescue").get("ok", true)), false, "ignore 后 rescue 拒绝")
	_eq(bool(ci.advance("complete").get("ok", false)), true, "ignore complete")
	_eq(str(ci.current_state()), "COMPLETE", "ignore COMPLETE")
	_ok("ceres_ignored" in ci.trigger_ids(), "ignore trigger 记录")
	_data_line("happy", "L1→L2→L3→LIGHT_READ→L4→RESCUE_PROMPT→RESCUED/IGNORED→COMPLETE · 声望/触发")

# ═══════════════════════════════════════════════════════════════════
# 3. 乱序/矩阵
# ═══════════════════════════════════════════════════════════════════

func _test_transition_matrix() -> void:
	_section_begin("3 乱序/矩阵")
	var all_actions: Array = ["data_link_l2", "identify_l3", "read_light",
		"classify_l4", "rescue_prompt", "rescue", "ignore", "complete"]
	for state in STATES:
		var c: Object = _to(str(state))
		_eq(str(c.current_state()), str(state), "到达状态 " + str(state))
		var allowed: Array = c.available_actions()
		for action in all_actions:
			if action in allowed:
				_ok(c.can_advance(str(action)), "允许动作 " + str(state) + "/" + str(action))
			else:
				var before := str(c.current_state())
				var r: Dictionary = c.advance(str(action))
				_eq(bool(r.get("ok", true)), false, "乱序拒绝 " + str(state) + "/" + str(action))
				_eq(str(c.current_state()), before, "乱序不改状态 " + str(state))
				_ok((r.get("reason", "") in ["invalid_transition", "invalid_action"]),
					"乱序 reason " + str(state) + "/" + str(action))
	# 手动：初始不自动
	var c2 = _fresh()
	_eq(str(c2.current_state()), "L1", "手动初始 L1")
	c2.available_actions()
	_eq(str(c2.current_state()), "L1", "查 actions 不自动推进")
	# 重复 L2
	var c3 = _fresh()
	c3.advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	_eq(bool(c3.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}).get("ok", true)),
		false, "重复 L2 拒绝")
	_eq(str(c3.current_state()), "L2", "重复 L2 状态不变")
	_data_line("matrix", "9 状态 × 8 动作乱序拒绝 · state 不变 · 手动不自动")

# ═══════════════════════════════════════════════════════════════════
# 4. 证据输入满足条件
# ═══════════════════════════════════════════════════════════════════

func _test_evidence_inputs() -> void:
	_section_begin("4 证据输入")
	var c = _fresh()
	# L2 无数据链
	_eq(bool(c.advance("data_link_l2").get("ok", true)), false, "无数据链 L2 拒绝")
	_eq(str(c.advance("data_link_l2").get("reason", "")), "missing_data_link",
		"missing_data_link reason")
	# ingest 数据链 + 传感器后可 L2
	_eq(bool(c.ingest({"kind": "data_link", "data_link": true,
		"sensor_sources": 2, "source": "datalink"}).get("ok", false)), true,
		"ingest data_link")
	_eq(bool(c.ingest({"kind": "sensor", "sensors": 2, "source": "ir"}).get("ok", false)),
		true, "ingest sensor")
	_eq(bool(c.advance("data_link_l2").get("ok", false)), true, "证据满足 L2")
	# L3 无证据（直接加载状态 L2 无 level 证据？构造 fresh 用 advance 带 level）
	var c2 = _fresh()
	c2.advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	_eq(bool(c2.advance("identify_l3").get("ok", false)), true, "L2 证据可 L3")
	# ingest level 输入
	var c3 = _fresh()
	c3.ingest({"kind": "level", "level": "L2", "source": "sensor"})
	_eq(bool(c3.advance("data_link_l2", {"data_link": true, "sensor_sources": 2}).get("ok", false)),
		true, "ingest level + L2")
	_eq(bool(c3.advance("identify_l3").get("ok", false)), true, "ingest level L3")
	# 非法 ingest
	var c4 = _fresh()
	_eq(bool(c4.ingest({}).get("ok", true)), false, "空 input 拒绝")
	_eq(bool(c4.ingest({"kind": "text", "text_key": "NOPE"}).get("ok", true)), false,
		"未知 text_key ingest 拒绝")
	_eq(bool(c4.ingest({"kind": "level", "level": "L9"}).get("ok", true)), false,
		"非法 level ingest 拒绝")
	# ingest text 不影响状态
	var c5 = _fresh()
	var ir: Dictionary = c5.ingest({"kind": "text", "text_key": "ceres.fault"})
	_eq(bool(ir.get("ok", false)), true, "ingest text ok")
	_eq(str(c5.current_state()), "L1", "ingest text 不改状态")
	# 可见光代码
	var c6 = _to("L3")
	_eq(str(c6.advance("read_light").get("reason", "")), "missing_light_code",
		"缺灯语码")
	_eq(str(c6.advance("read_light", {"light_code": "0000"}).get("reason", "")),
		"wrong_light_code", "错误灯语码")
	_eq(str(c6.current_state()), "L3", "灯语失败不改状态")
	_eq(bool(c6.advance("read_light", {"light_code": "7700"}).get("ok", false)), true,
		"正确灯语码")
	# 未读灯语不可 L4（构造 L3 后直接 classify 是乱序 invalid_transition；验证 can_advance）
	_eq(c6.can_advance("classify_l4"), true, "读灯后可 L4")
	_data_line("evidence", "L2 需数据链/多传感器 · L3 需 level 证据 · 灯语码校验 · 非法 ingest")

# ═══════════════════════════════════════════════════════════════════
# 5. note 文本
# ═══════════════════════════════════════════════════════════════════

func _test_notes() -> void:
	_section_begin("5 note")
	var c = _fresh()
	var n: Dictionary = c.note("ceres.fault")
	_eq(bool(n.get("ok", false)), true, "note ok")
	_eq(str(n.get("text_key", "")), "ceres.fault", "note key")
	_ok(str(n.get("text", "")).contains("应答机"), "note text")
	_eq(str(c.current_state()), "L1", "note 不改状态")
	_eq((c.get_notes() as Array).size(), 1, "notes 1")
	_ok(bool(c.note("NOPE").get("ok", true)) == false, "未知 text_key note 拒绝")
	_ok(str(c.note("NOPE").get("reason", "")) == "unknown_text_key", "unknown_text_key reason")
	_eq((c.get_notes() as Array).size(), 1, "失败 note 不记录")
	# 所有文本均可 note
	for key in TEXT_KEYS:
		_eq(bool(c.note(str(key)).get("ok", false)), true, "note " + str(key))
	_eq((c.get_notes() as Array).size(), 10, "10 notes（fault 已看过一次）")
	# notes 不改 flags/evidence/reputation
	_eq(str(c.current_state()), "L1", "notes 后状态")
	_eq(c.get_flags(), {}, "notes 后 flags 空")
	_eq((c.get_evidence() as Array).size(), 0, "notes 后 evidence 空")
	_eq(c.get_reputation(), {}, "notes 后 reputation 空")
	_data_line("note", "9 文本可 note · 未知 key 拒绝 · 不改变状态/flags/evidence/reputation")

# ═══════════════════════════════════════════════════════════════════
# 6. save/load
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("6 save/load")
	# 中间态
	var mid = _to("L3")
	var save_mid := str(mid.save_state())
	var m2 = _fresh()
	var lr: Dictionary = m2.load_state(save_mid)
	_eq(bool(lr.get("ok", false)), true, "mid load ok", str(lr.get("errors", [])))
	_eq(str(m2.current_state()), "L3", "mid state")
	_eq(_norm(mid.vm()), _norm(m2.vm()), "mid VM 一致")
	# load 后继续
	_eq(bool(m2.advance("read_light", {"light_code": "7700"}).get("ok", false)), true,
		"load 后继续")
	# 终态
	var fin = _drive({"choice": "rescue"})
	fin.advance("complete")
	var fin2 = _fresh()
	_eq(bool(fin2.load_state(str(fin.save_state())).get("ok", false)), true, "final load ok")
	_eq(str(fin2.current_state()), "COMPLETE", "final state")
	_eq(str(fin2.chosen_action()), "rescue", "final chosen")
	_eq(_norm(fin2.get_reputation()), _norm(fin.get_reputation()), "final reputation")
	_eq(_norm(fin.vm()), _norm(fin2.vm()), "final VM 一致")
	# 非法存档
	var before := _norm(fin2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.ceres_chain_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.ceres_chain_save.v1", "version": "1.0.0",
			"state": "BAD", "flags": {}}),
		JSON.stringify({"schema": "v17.ceres_chain_save.v1", "version": "1.0.0",
			"state": "L1", "flags": "bad", "evidence": [], "events": []}),
		JSON.stringify({"schema": "v17.ceres_chain_save.v1", "version": "1.0.0",
			"state": "L1", "flags": {}, "evidence": "bad", "events": []}),
		JSON.stringify({"schema": "v17.ceres_chain_save.v1", "version": "1.0.0",
			"state": "L1", "flags": {}, "evidence": [], "events": [], "chosen": "bad"})]
	for bad in bads:
		_eq(bool(fin2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 28))
	_eq(_norm(fin2.vm()), before, "非法存档不改状态")
	_data_line("save", "mid/final save-load VM/state 一致 · load 后继续 · 非法存档原子拒绝")

# ═══════════════════════════════════════════════════════════════════
# 7. 非法输入 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_invalid_determinism() -> void:
	_section_begin("7 非法/确定性")
	var c = _fresh()
	# 非法 action
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
	var b5 := base.duplicate(true); ((b5["texts"] as Array)[1] as Dictionary)["text_key"] = "ceres.fault"; bads.append(b5)
	var b6 := base.duplicate(true); b6["chain"] = ["L1"]; bads.append(b6)
	var b7 := base.duplicate(true); b7["emergency_light_code"] = "12"; bads.append(b7)
	var b8 := base.duplicate(true); (b8["triggers"] as Dictionary)["light_read"] = ""; bads.append(b8)
	for i in range(bads.size()):
		var v: Dictionary = c.validate_content(bads[i])
		_eq(bool(v.get("ok", true)), false, "非法内容拒绝 #" + str(i))
	# 不存在文件
	var badc = CeresChain.new({"content_path": "/no/such.json"})
	_ok(not bool(badc.ready), "不存在内容拒绝")
	# 确定性
	var a = _drive({"choice": "rescue"})
	a.advance("complete")
	var b = _drive({"choice": "rescue"})
	b.advance("complete")
	_eq(_norm(a.vm()), _norm(b.vm()), "同路径 VM 一致")
	_eq(_norm(JSON.parse_string(a.save_state())),
		_norm(JSON.parse_string(b.save_state())), "同路径 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("invalid", "非法 action/内容拒绝 · 不存在文件拒绝 · 同路径确定")
