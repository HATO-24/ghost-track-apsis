extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4C 最小 probe：AfterActionReport（事后报告/分支/序章完成）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/report_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const AfterActionReport := preload("res://scripts/core/after_action_report.gd")
const DOCS44 := "../docs/44_新剧本_2193.md"
const BRANCH_IDS := ["program_justice", "ghost_track", "colonial_savior",
	"wrong_justice", "butterfly", "sleeping"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE4C PROBE · AfterActionReport")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_ingest()
	_test_program_branch()
	_test_ghost_branches()
	_test_combinations()
	_test_text_source()
	_test_save_reset()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 REPORT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 REPORT PROBE FAILED")
		quit(1)
	else:
		print("V17 REPORT PROBE OK")
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

func _svc(cfg := {}) -> Object:
	var r = AfterActionReport.new(cfg)
	_ok(bool(r.ready), "AfterActionReport ready", str(r.errors))
	return r

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

func _base_input() -> Dictionary:
	return {"ceres": "rescued",
		"chronos": {"evac": true, "blackbox": true, "telemetry": true,
			"choice": "accept"},
		"av4412": "question",
		"evidence": ["blackbox", "telemetry", "elint", "comms"],
		"report_choice": "submit_evidence", "legal_status": "WATCHLIST",
		"threat": 2, "trust": 0.8, "political": 0.8}

func _clean_doc_line(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with("> "):
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

func _expect_branch(r, inp: Dictionary, expected: String, label: String) -> Dictionary:
	var ri: Dictionary = r.ingest(inp)
	if not bool(ri.get("ok", false)):
		_ok(false, label + " ingest", str(ri.get("reason", "")))
		return {}
	var res: Dictionary = r.compose()
	_eq(str(res.get("branch_hint", "")), expected, label + " branch")
	_eq(bool(res.get("prologue_complete", false)), true, label + " PROLOGUE_COMPLETE")
	_eq(bool(res.get("ending_executed", true)), false, label + " 不执行结局")
	return res

# ═══════════════════════════════════════════════════════════════════
# 1. 内容 / schema
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容/schema")
	var r = _svc()
	_eq(str(r.content.get("schema", "")), "v17.story_report.v1", "content schema")
	_eq(r.report_templates.size(), 3, "3 报告模板")
	_eq(r.branch_texts.size(), 5, "5 分支文本")
	_eq(r.branch_order.size(), 6, "6 分支描述")
	for bid in BRANCH_IDS:
		_ok(str(bid) in r.branch_ids(), "分支 " + str(bid))
		_ok(not r.branch_info(str(bid)).is_empty(), "分支信息 " + str(bid))
	for tk in r.text_keys():
		_ok(str(tk) != "", "text key 非空")
	for raw in (r.content.get("report_templates", []) as Array):
		var t: Dictionary = raw
		_ok(str(t.get("text_key", "")) != "", "report text_key")
		_ok(str(t.get("zh", "")) != "", "report zh " + str(t.get("text_key", "")))
		_ok(t.get("en") is String, "report en " + str(t.get("text_key", "")))
		_eq(str(t.get("en", "x")), "", "report en 空 " + str(t.get("text_key", "")))
		if bool(t.get("tbd", false)):
			_eq(str(t.get("zh", "")), "TBD", "TBD 明示 " + str(t.get("text_key", "")))
		else:
			_ok((t.get("source_lines", []) as Array).size() > 0,
				"report source_lines " + str(t.get("text_key", "")))
	for raw2 in (r.content.get("branch_texts", []) as Array):
		var b: Dictionary = raw2
		_ok(str(b.get("zh", "")) != "", "branch zh " + str(b.get("text_key", "")))
		_ok((b.get("source_lines", []) as Array).size() > 0,
			"branch source_lines " + str(b.get("text_key", "")))
	_eq((r.content.get("reuse_notes", []) as Array).size(), 3, "reuse_notes 3")
	_ok(str(r.report_template("report.program_justice").get("zh", "")).contains("ID13"),
		"程序正义报告含 ID13")
	_ok(str(r.report_template("report.program_justice").get("zh", "")).contains(
		"OCJC 监察"), "程序正义报告含 OCJC")
	_ok(str(r.report_template("report.ghost_track").get("zh", "")).contains("ID13"),
		"GHOST 报告含 ID13")
	_ok(str(r.branch_text("program_justice").get("zh", "")).contains("程序正义线"),
		"程序正义分支文本")
	_ok(str(r.branch_text("ghost_track").get("zh", "")).contains("GHOST TRACK"),
		"GHOST 分支文本")
	_ok(str(r.branch_text("sleeping").get("zh", "")).contains("守口如瓶"),
		"守口如瓶分支文本")
	_ok(str(r.branch_text("wrong_justice").get("zh", "")).contains("错付的正义"),
		"错付正义分支文本")
	_ok(str(r.branch_text("butterfly").get("zh", "")).contains("蝴蝶效应"),
		"蝴蝶效应分支文本")
	_ok(str(r.branch_text("colonial_savior").get("zh", "")).contains("殖民地的救世主"),
		"殖民地救世主分支文本")
	_ok(bool(r.check_contracts().get("ok", false)), "初始 contracts ok")
	_data_line("content", "3 报告模板（含 TBD）/5 分支文本/6 分支描述/3 reuse notes · 原文关键句")

# ═══════════════════════════════════════════════════════════════════
# 2. ingest / choose
# ═══════════════════════════════════════════════════════════════════

func _test_ingest() -> void:
	_section_begin("2 ingest/choose")
	var r = _svc()
	var base := _base_input()
	var ir: Dictionary = r.ingest(base)
	_eq(bool(ir.get("ok", false)), true, "base ingest ok")
	_eq(str(r.inputs.get("ceres", "")), "rescued", "ceres saved")
	_eq(bool((r.inputs.get("chronos", {}) as Dictionary).get("evac", false)), true,
		"chronos evac saved")
	_eq(str(r.inputs.get("av4412", "")), "question", "av saved")
	_eq((r.inputs.get("evidence", []) as Array).size(), 4, "evidence 4")
	_eq(str(r.inputs.get("report_choice", "")), "submit_evidence", "choice saved")
	# 别名/合并
	var r2 = _svc()
	_ok(bool(r2.ingest({"ceres_status": "rescued",
		"chronos_evac": true, "chronos_blackbox": true, "chronos_telemetry": true,
		"chronos_choice": "accept", "av4412_choice": "strong",
		"evidence": ["black_box", "port_telemetry", "sensor_logs", "communications"],
		"political": "aeug", "trust": 0.9, "threat": 4,
		"legal_status": "RESTRICTED"}).get("ok", false)), "别名 ingest ok")
	_eq(str(r2.inputs.get("ceres", "")), "rescued", "别名 ceres")
	_eq(str(r2.inputs.get("av4412", "")), "strong", "别名 av")
	_eq((r2.inputs.get("evidence", []) as Array), ["blackbox", "comms", "elint", "telemetry"],
		"别名 evidence 归一")
	_eq(float(r2.inputs.get("political", 0.0)), 1.0, "political aeug")
	_eq(float(r2.inputs.get("trust", 0.0)), 0.9, "trust")
	_eq(str(r2.inputs.get("legal_status", "")), "RESTRICTED", "legal status")
	# dict evidence
	var r3 = _svc()
	_ok(bool(r3.ingest({"evidence": {"blackbox": true, "telemetry": true,
		"elint": false, "comms": true}}).get("ok", false)), "dict evidence ok")
	_eq((r3.inputs.get("evidence", []) as Array), ["blackbox", "comms", "telemetry"], "dict evidence 归一")
	# 二次 ingest 合并
	var r4 = _svc()
	r4.ingest({"ceres": "rescued"})
	r4.ingest({"av4412": "standard", "chronos": {"evac": true}})
	_eq(str(r4.inputs.get("ceres", "")), "rescued", "二次 ingest ceres 保留")
	_eq(str(r4.inputs.get("av4412", "")), "standard", "二次 ingest av")
	_eq(bool((r4.inputs.get("chronos", {}) as Dictionary).get("evac", false)), true,
		"二次 ingest evac")
	# 非法输入原子拒绝
	var before := _norm(r4.inputs)
	var bads: Array = [
		{"ceres": "unknown"}, {"ceres_status": "x"},
		{"av4412": "bogus"}, {"av4412_choice": "bogus"},
		{"chronos": {"choice": "bogus"}}, {"chronos_choice": "bogus"},
		{"evidence": ["bogus"]}, {"evidence": "bad"},
		{"legal_status": "BOGUS"}, {"threat": "high"}, {"trust": "high"},
		{"political": "bogus"}, {"report_choice": "bogus"}]
	for i in range(bads.size()):
		_eq(bool(r4.ingest(bads[i]).get("ok", true)), false, "非法 ingest 拒绝 #" + str(i))
	_eq(_norm(r4.inputs), before, "非法 ingest 不改状态")
	# 未知键只 warning
	var un: Dictionary = r4.ingest({"unknown_key": 1})
	_eq(bool(un.get("ok", false)), true, "未知键不失败")
	_ok((un.get("warnings", []) as Array).size() >= 1, "未知键 warning")
	# choose_report
	var c = _svc()
	for pair in [["submit", "submit_evidence"], ["submit_evidence", "submit_evidence"],
			["withhold", "withhold_evidence"], ["report_withhold", "withhold_evidence"]]:
		_eq(str(c.choose_report(str(pair[0])).get("report_choice", "")),
			str(pair[1]), "choose " + str(pair[0]))
	_eq(bool(c.choose_report("bogus").get("ok", true)), false, "非法 choose 拒绝")
	_eq(bool(c.choose_report("").get("ok", true)), false, "空 choose 拒绝")
	_data_line("ingest", "base/别名/dict evidence/二次合并 · 13 类非法原子拒绝 · 未知键 warning · choose 别名")

# ═══════════════════════════════════════════════════════════════════
# 3. 程序正义分支
# ═══════════════════════════════════════════════════════════════════

func _test_program_branch() -> void:
	_section_begin("3 程序正义")
	var r = _svc()
	var res = _expect_branch(r, _base_input(), "program_justice", "完整+上报")
	_eq(str(res.get("prologue_status", "")), "PROLOGUE_COMPLETE", "status")
	_eq((res.get("missing_items", []) as Array).size(), 0, "program 无缺失")
	var rep: Dictionary = res.get("report", {})
	_eq(str(rep.get("text_key", "")), "report.program_justice", "program 报告 key")
	_ok(str(rep.get("zh", "")).contains("ID13 于执行窗口内"), "program 报告原文")
	_eq(bool(rep.get("tbd", true)), false, "program 非 TBD")
	_eq((rep.get("source_lines", []) as Array).size(), 1, "program source_lines")
	_eq((res.get("candidates", []) as Array), ["program_justice"], "program candidates")
	_eq(str(r.report().get("text_key", "")), "report.program_justice", "report 自动 compose")
	_eq(r.branch_hint(), "program_justice", "branch_hint")
	_eq(r.report_text(), str(rep.get("zh", "")), "report_text")
	# 缺失逐项 → 标准报告/TBD
	var misses := {
		"ceres": {"ceres": "ignored"},
		"evac": {"chronos": {"evac": false}},
		"blackbox": {"chronos": {"blackbox": false}},
		"telemetry": {"chronos": {"telemetry": false}},
		"question": {"av4412": "standard"},
		"evidence_blackbox": {"evidence": ["telemetry", "elint", "comms"]},
		"evidence_telemetry": {"evidence": ["blackbox", "elint", "comms"]},
		"evidence_elint": {"evidence": ["blackbox", "telemetry", "comms"]},
		"evidence_comms": {"evidence": ["blackbox", "telemetry", "elint"]},
	}
	for key in misses.keys():
		var inp := _base_input()
		for k in (misses[key] as Dictionary).keys():
			inp[k] = (misses[key] as Dictionary)[k]
		var rr = _svc()
		var out: Dictionary = rr.compose() if false else {}
		rr.ingest(inp)
		out = rr.compose()
		_eq(str(out.get("branch_hint", "")), "standard", "缺 " + str(key) + " → standard")
		_eq(str((out.get("report", {}) as Dictionary).get("text_key", "")),
			"report.standard_missing_tbd", "缺 " + str(key) + " TBD")
		var mi: Array = out.get("missing_items", []) as Array
		var expect_missing := {"ceres": "ceres_rescued", "evac": "chronos_evac",
			"blackbox": "chronos_blackbox", "telemetry": "chronos_telemetry",
			"question": "av4412_question", "evidence_blackbox": "evidence_blackbox",
			"evidence_telemetry": "evidence_telemetry", "evidence_elint": "evidence_elint",
			"evidence_comms": "evidence_comms"}
		_ok(str(expect_missing.get(str(key), str(key))) in mi,
			"missing 含 " + str(key), str(mi))
	# 未上报但有 core → GHOST（不是 program）
	var w := _base_input(); w["report_choice"] = "withhold_evidence"
	var rw = _svc()
	var rwres = _expect_branch(rw, w, "ghost_track", "核心+未上报")
	_eq(str((rwres.get("report", {}) as Dictionary).get("text_key", "")),
		"report.ghost_track", "未上报报告 key")
	# 核心完成但上报+非质疑 → standard
	var st := _base_input(); st["av4412"] = "standard"
	var rs = _svc()
	var stres = _expect_branch(rs, st, "standard", "上报+标准回应")
	_ok("av4412_question" in (stres.get("missing_items", []) as Array),
		"standard 缺质疑")
	_data_line("program", "完整→program_justice/原文 · 9 类缺失→standard/TBD · 未上报→GHOST")

# ═══════════════════════════════════════════════════════════════════
# 4. GHOST / 错付 / 守口如瓶
# ═══════════════════════════════════════════════════════════════════

func _test_ghost_branches() -> void:
	_section_begin("4 GHOST 分支")
	var cases := [
		{"political": 0.5, "trust": 0.5, "ev": ["blackbox", "telemetry", "elint", "comms"],
			"expect": "ghost_track", "label": "中性→GHOST"},
		{"political": 0.9, "trust": 0.9, "ev": ["blackbox", "telemetry", "elint", "comms"],
			"expect": "ghost_track", "label": "高政治+高信任→GHOST"},
		{"political": 0.9, "trust": 0.1, "ev": ["blackbox", "telemetry", "elint", "comms"],
			"expect": "wrong_justice", "label": "高政治+低信任→错付正义"},
		{"political": 0.1, "trust": 0.9, "ev": ["blackbox", "telemetry", "elint", "comms"],
			"expect": "sleeping", "label": "低政治+高信任→守口如瓶"},
		{"political": 0.1, "trust": 0.1, "ev": ["blackbox", "telemetry", "elint", "comms"],
			"expect": "ghost_track", "label": "低政治+低信任→GHOST hint"},
		{"political": 0.9, "trust": 0.9, "ev": ["blackbox", "telemetry"],
			"expect": "wrong_justice", "label": "高政治+证据不全→错付正义"},
	]
	for case in cases:
		var r = _svc()
		var inp := _base_input()
		inp["av4412"] = "standard"
		inp["report_choice"] = "withhold_evidence"
		inp["political"] = case["political"]
		inp["trust"] = case["trust"]
		inp["evidence"] = case["ev"]
		var res = _expect_branch(r, inp, str(case["expect"]), str(case["label"]))
		var rep: Dictionary = res.get("report", {})
		_eq(str(rep.get("text_key", "")), "report.ghost_track",
			str(case["label"]) + " 报告模板")
		_ok(str(rep.get("zh", "")).contains("ID13"), str(case["label"]) + " 原文")
		_eq(bool(rep.get("tbd", true)), false, str(case["label"]) + " 非 TBD")
	# 分支文本
	var g = _svc()
	g.ingest(_base_input())
	g.choose_report("withhold_evidence")
	_ok(str(g.branch_text("ghost_track").get("zh", "")).contains("GHOST TRACK"),
		"GHOST 分支文本")
	_ok(str(g.branch_text("wrong_justice").get("zh", "")).contains("错付的正义"),
		"错付分支文本")
	_ok(str(g.branch_text("butterfly").get("zh", "")).contains("蝴蝶效应"),
		"蝴蝶分支文本")
	_ok(str(g.branch_text("sleeping").get("zh", "")).contains("守口如瓶"),
		"守口分支文本")
	# core 不完整 → standard
	var m = _svc()
	m.ingest({"ceres": "ignored", "av4412": "strong",
		"report_choice": "withhold_evidence"})
	var mr: Dictionary = m.compose()
	_eq(str(mr.get("branch_hint", "")), "standard", "core 缺失→standard")
	_ok((mr.get("missing_items", []) as Array).size() >= 3, "core 缺失项")
	# retreat → standard
	var rt = _svc()
	var ri := _base_input(); ri["av4412"] = "retreat"
	rt.ingest(ri)
	_eq(str(rt.compose().get("branch_hint", "")), "standard", "retreat→standard")
	# 上报/保密互斥覆盖
	var sw = _svc()
	sw.ingest(_base_input())
	sw.choose_report("withhold_evidence")
	_eq(sw.report_choice_value(), "withhold_evidence", "choose 后保密")
	sw.choose_report("submit_evidence")
	_eq(sw.report_choice_value(), "submit_evidence", "可改选上报")
	_data_line("ghost", "6 政治/信任/证据组合 · GHOST/错付/守口 · core缺失/retreat→standard · 分支文本")

# ═══════════════════════════════════════════════════════════════════
# 5. 组合枚举
# ═══════════════════════════════════════════════════════════════════

func _test_combinations() -> void:
	_section_begin("5 组合枚举")
	var r = _svc()
	var count := 0
	for ci in range(2):
		for mask in range(8):
			for av in ["strong", "standard", "question", "retreat"]:
				for choice in ["submit_evidence", "withhold_evidence"]:
					var inp := {"ceres": "rescued" if ci == 0 else "ignored",
						"chronos": {"evac": (mask & 1) != 0,
							"blackbox": (mask & 2) != 0,
							"telemetry": (mask & 4) != 0, "choice": "accept"},
						"av4412": av,
						"evidence": ["blackbox", "telemetry", "elint", "comms"],
						"report_choice": choice,
						"political": 0.7, "trust": 0.7}
					var rr = _svc()
					rr.ingest(inp)
					var res: Dictionary = rr.compose()
					count += 1
					_ok(str(res.get("branch_hint", "")) in [
						"program_justice", "ghost_track", "wrong_justice",
						"sleeping", "standard"], "组合 branch 合法 #" + str(count))
					_eq(bool(res.get("prologue_complete", false)), true, "组合完成 #" + str(count))
					_eq(bool(res.get("ending_executed", true)), false, "组合不执行结局 #" + str(count))
					_ok((res.get("report", {}) as Dictionary).has("text_key"),
						"组合 report #" + str(count))
	_eq(count, 128, "128 组合")
	# political/trust 网格
	var grid := 0
	for pi in range(5):
		for ti in range(5):
			var pol := float(pi) / 4.0
			var tr := float(ti) / 4.0
			var r2 = _svc()
			var inp2 := _base_input()
			inp2["av4412"] = "strong"
			inp2["report_choice"] = "withhold_evidence"
			inp2["political"] = pol
			inp2["trust"] = tr
			r2.ingest(inp2)
			var res2: Dictionary = r2.compose()
			var expected := "ghost_track"
			if pol >= 0.6 and tr >= 0.6:
				expected = "ghost_track"
			elif pol >= 0.6 and tr < 0.6:
				expected = "wrong_justice"
			elif pol < 0.6 and tr >= 0.6:
				expected = "sleeping"
			_eq(str(res2.get("branch_hint", "")), expected,
				"网格 %.2f/%.2f" % [pol, tr])
			grid += 1
	_eq(grid, 25, "25 政治/信任网格")
	_data_line("combos", "128 行动组合 + 25 政治/信任网格 · branch 合法/PROLOGUE_COMPLETE/无结局")

# ═══════════════════════════════════════════════════════════════════
# 6. 文本原文
# ═══════════════════════════════════════════════════════════════════

func _test_text_source() -> void:
	_section_begin("6 文本原文")
	var r = _svc()
	var doc := _doc_lines()
	_ok(doc.size() > 290, "docs/44 可读")
	# 报告与分支文本逐字匹配 source_lines
	for raw in (r.content.get("report_templates", []) as Array):
		var t: Dictionary = raw
		if bool(t.get("tbd", false)):
			_ok(str(t.get("zh", "")) == "TBD", "TBD 报告 " + str(t.get("text_key", "")))
			continue
		var zh := str(t.get("zh", ""))
		var matched := false
		for n in (t.get("source_lines", []) as Array):
			var idx := int(float(n)) - 1
			if idx >= 0 and idx < doc.size() and _clean_doc_line(str(doc[idx])) == zh:
				matched = true
				break
		_ok(matched, "报告逐字 " + str(t.get("text_key", "")))
	for raw2 in (r.content.get("branch_texts", []) as Array):
		var b: Dictionary = raw2
		var zh2 := str(b.get("zh", ""))
		var matched2 := false
		for n2 in (b.get("source_lines", []) as Array):
			var idx2 := int(float(n2)) - 1
			if idx2 >= 0 and idx2 < doc.size() and _clean_doc_line(str(doc[idx2])) == zh2:
				matched2 = true
				break
		_ok(matched2, "分支逐字 " + str(b.get("text_key", "")))
	# reuse notes
	for note in (r.content.get("reuse_notes", []) as Array):
		_ok(str(note) != "", "reuse note 非空")
		var found := false
		for line in doc:
			if _clean_doc_line(str(line)) == str(note):
				found = true
				break
		_ok(found, "reuse note 原文")
	# 原文关键句
	_ok(str(r.report_template("report.program_justice").get("zh", "")).contains(
		"向 OCJC 监察与 UEG 轨道事务委员会提交联合调查请求"), "报告关键句")
	_ok(str(r.report_template("report.ghost_track").get("zh", "")).contains(
		"人员伤亡：无"), "GHOST 报告关键句")
	_ok(str(r.branch_text("program_justice").get("zh", "")).contains(
		"不谙世事的愚忠"), "程序正义分支关键句")
	_ok(str(r.branch_text("wrong_justice").get("zh", "")).contains("蝴蝶效应"),
		"错付/蝴蝶原文")
	_data_line("text", "报告/分支逐字匹配 docs/44 · TBD 明示 · reuse notes 原文 · 关键句")

# ═══════════════════════════════════════════════════════════════════
# 7. save / reset / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_save_reset() -> void:
	_section_begin("7 save/reset")
	var r = _svc()
	r.ingest(_base_input())
	r.compose()
	var save := str(r.save_state())
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).get("schema", "") ==
		"v17.after_action_report_save.v1", "save schema")
	for k in ["inputs", "composed", "branch_hint", "status", "report_choice"]:
		_ok((d as Dictionary).has(k), "save 字段 " + str(k))
	var r2 = _svc()
	var lr: Dictionary = r2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_eq(_norm(r.vm()), _norm(r2.vm()), "load VM 一致")
	_eq(r2.branch_hint(), "program_justice", "load branch")
	_eq(str(r2.report().get("text_key", "")), "report.program_justice", "load report")
	# 继续修改后重新 compose
	_ok(bool(r2.ingest({"trust": 0.2}).get("ok", false)), "load 后 ingest")
	_eq(bool(r2.check_contracts().get("ok", false)), true, "load 后 contracts")
	# 非法存档
	var keep := _norm(r2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.after_action_report_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.after_action_report_save.v1", "version": "1.0.0",
			"inputs": "bad", "composed": {}}),
		JSON.stringify({"schema": "v17.after_action_report_save.v1", "version": "1.0.0",
			"inputs": {}, "composed": "bad"}),
		JSON.stringify({"schema": "v17.after_action_report_save.v1", "version": "1.0.0",
			"inputs": {}, "composed": {}, "report_choice": "bad"}),
		JSON.stringify({"schema": "v17.after_action_report_save.v1", "version": "1.0.0",
			"inputs": {}, "composed": {}, "status": "BAD"})]
	for b in bads:
		_eq(bool(r2.load_state(str(b)).get("ok", true)), false,
			"非法存档拒绝：" + str(b).substr(0, 30))
	_eq(_norm(r2.vm()), keep, "非法存档不改状态")
	# reset
	var rr: Dictionary = r.reset()
	_eq(bool(rr.get("ok", false)), true, "reset ok")
	_eq(str(r.vm().get("status", "")), "READY", "reset READY")
	_eq(r.vm().get("branch_hint", "x"), "", "reset branch 空")
	# 确定性
	var a = _svc()
	var b = _svc()
	a.ingest(_base_input()); b.ingest(_base_input())
	a.compose(); b.compose()
	_eq(_norm(a.vm()), _norm(b.vm()), "同输入 VM 一致")
	_eq(a.save_state(), b.save_state(), "同输入 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts")
	_data_line("save/reset", "save 字段/load VM/继续修改 · 非法存档原子拒绝 · reset · 同输入确定")
