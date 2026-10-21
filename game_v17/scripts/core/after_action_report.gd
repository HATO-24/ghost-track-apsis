extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4C：AfterActionReport（事后报告/分支判定/序章完成；新文件）
#
# - 输入：Ceres 救援/忽略、Chronos 行动（evac/blackbox/telemetry/choice）、
#   AV-4412 谈判选择、证据（黑匣子/遥测/ELINT/通信）、报告选择
#   （submit_evidence/withhold_evidence）、ID13 legal status/threat/trust、
#   政治倾向；
# - 判定：程序正义 / GHOST TRACK / 错付正义 / 守口如瓶 / 标准报告；
# - 文本从 docs/44 原文抽取（story_report.json），缺失文本显式 TBD，不伪造；
# - demo 只输出 branch_hint + PROLOGUE_COMPLETE，不触发完整结局；
# - 不写 world/UI/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.after_action_report.v1"
const SAVE_SCHEMA := "v17.after_action_report_save.v1"
const CONTENT_SCHEMA := "v17.story_report.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/story_report.json"
const CHOICES := ["submit_evidence", "withhold_evidence"]
const AV_OPTIONS := ["strong", "standard", "question", "retreat"]
const CERES_STATUSES := ["rescued", "ignored"]
const LEGAL_STATUSES := ["UNLISTED", "WATCHLIST", "RESTRICTED",
	"DESIGNATED_ILLEGAL", "HUNTED", "CLEARED"]
const EVIDENCE_ALIASES := {
	"blackbox": "blackbox", "black_box": "blackbox", "blackbox_data": "blackbox",
	"telemetry": "telemetry", "port_telemetry": "telemetry",
	"chronos_telemetry": "telemetry", "elint": "elint", "sensor_logs": "elint",
	"comms": "comms", "communications": "comms", "comms_record": "comms",
	"communication": "comms",
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var source_path := ""
var report_templates: Dictionary = {}
var branch_texts: Dictionary = {}
var branches: Dictionary = {}
var branch_order: Array = []
var rules: Dictionary = {}
var missing_labels: Dictionary = {}
var reuse_notes: Array = []

var inputs: Dictionary = {}
var report_choice := ""
var composed: Dictionary = {}
var _branch_hint := ""
var _missing: Array = []
var _status := "READY"
var _dirty := false

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	content = {}
	content_path = str(cfg.get("content_path", DEFAULT_CONTENT)) if cfg is Dictionary else DEFAULT_CONTENT
	if cfg is Dictionary and cfg.get("content") is Dictionary:
		content = (cfg.get("content") as Dictionary).duplicate(true)
	else:
		content = _read_json(content_path)
	if content.is_empty():
		errors.append("报告内容不可读：" + content_path)
		return false
	var v := validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("report: " + str(e))
		return false
	_apply_content(content)
	_reset_state()
	ready = true
	return true

func _apply_content(d: Dictionary) -> void:
	source_path = str(d.get("source_path", ""))
	report_templates = {}
	for raw in (d.get("report_templates", []) as Array):
		if raw is Dictionary:
			var t: Dictionary = (raw as Dictionary).duplicate(true)
			report_templates[str(t.get("text_key", ""))] = t
	branch_texts = {}
	for raw2 in (d.get("branch_texts", []) as Array):
		if raw2 is Dictionary:
			var b: Dictionary = (raw2 as Dictionary).duplicate(true)
			branch_texts[str(b.get("text_key", ""))] = b
	branches = {}
	branch_order = []
	for raw3 in (d.get("branches", []) as Array):
		if raw3 is Dictionary:
			var br: Dictionary = (raw3 as Dictionary).duplicate(true)
			branches[str(br.get("branch_id", ""))] = br
			branch_order.append(str(br.get("branch_id", "")))
	rules = (d.get("rules", {}) as Dictionary).duplicate(true) if d.get("rules") is Dictionary else {}
	missing_labels = (d.get("missing_labels", {}) as Dictionary).duplicate(true) \
		if d.get("missing_labels") is Dictionary else {}
	reuse_notes = (d.get("reuse_notes", []) as Array).duplicate(true)

func _reset_state() -> void:
	inputs = {"ceres": "", "chronos": {"evac": false, "blackbox": false,
		"telemetry": false, "choice": ""}, "av4412": "",
		"evidence": [], "report_choice": "", "legal_status": "UNLISTED",
		"threat": 0, "trust": 0.5, "political": 0.5}
	report_choice = ""
	composed = {}
	_branch_hint = ""
	_missing = []
	_status = "READY"
	_dirty = false

func validate_content(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != CONTENT_SCHEMA:
		errs.append("schema 必须为 " + CONTENT_SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	var reps = d.get("report_templates", null)
	if not (reps is Array) or (reps as Array).is_empty():
		errs.append("report_templates 必须为非空数组")
	else:
		var keys: Dictionary = {}
		for raw in (reps as Array):
			if not (raw is Dictionary):
				errs.append("report_template 非对象")
				continue
			var r: Dictionary = raw
			var key := str(r.get("text_key", ""))
			if key == "":
				errs.append("report_template text_key 为空")
			elif keys.has(key):
				errs.append("report_template text_key 重复：" + key)
			keys[key] = true
			if str(r.get("zh", "")) == "":
				errs.append("report_template %s zh 为空" % key)
			if bool(r.get("tbd", false)):
				if str(r.get("zh", "")) != "TBD":
					errs.append("report_template %s TBD 必须 zh=TBD" % key)
			else:
				_check_source_lines(r, errs, "report_template " + key)
	var bkeys: Dictionary = {}
	var bts = d.get("branch_texts", null)
	if not (bts is Array) or (bts as Array).is_empty():
		errs.append("branch_texts 必须为非空数组")
	else:
		for raw2 in (bts as Array):
			if not (raw2 is Dictionary):
				errs.append("branch_text 非对象")
				continue
			var b: Dictionary = raw2
			var bk := str(b.get("text_key", ""))
			if bk == "":
				errs.append("branch_text text_key 为空")
			elif bkeys.has(bk):
				errs.append("branch_text text_key 重复：" + bk)
			bkeys[bk] = true
			if str(b.get("zh", "")) == "":
				errs.append("branch_text %s zh 为空" % bk)
			_check_source_lines(b, errs, "branch_text " + bk)
	var brs = d.get("branches", null)
	if not (brs is Array) or (brs as Array).is_empty():
		errs.append("branches 必须为非空数组")
	else:
		var ids: Dictionary = {}
		for raw3 in (brs as Array):
			if not (raw3 is Dictionary):
				errs.append("branch 非对象")
				continue
			var br: Dictionary = raw3
			var bid := str(br.get("branch_id", ""))
			if bid == "":
				errs.append("branch_id 为空")
			elif ids.has(bid):
				errs.append("branch_id 重复：" + bid)
			ids[bid] = true
			var tk := str(br.get("text_key", ""))
			if tk == "":
				errs.append("branch %s text_key 为空" % bid)
			elif not bkeys.has(tk):
				errs.append("branch %s text_key 不存在：%s" % [bid, tk])
	for k in ["rules", "missing_labels"]:
		if not (d.get(k) is Dictionary):
			errs.append(k + " 必须是对象")
	return {"ok": errs.is_empty(), "errors": errs}

func _check_source_lines(v: Dictionary, errs: Array[String], label: String) -> void:
	var sl = v.get("source_lines", null)
	if not (sl is Array) or (sl as Array).is_empty():
		errs.append(label + " source_lines 为空")
	else:
		for n in (sl as Array):
			if not (n is int or n is float) or int(float(n)) <= 0:
				errs.append(label + " source_lines 非法")

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

# ── ingest / choose ─────────────────────────────────────────────

func ingest(value: Variant) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: AfterActionReport 未 ready")
	if not (value is Dictionary):
		return _fail("invalid_input", "precondition: ingest 必须是对象")
	var patch: Dictionary = value
	var next := inputs.duplicate(true)
	var warns: Array = []
	# Ceres
	if patch.has("ceres"):
		var c = patch["ceres"]
		var cs := str(c.get("status", c.get("rescued", ""))) if c is Dictionary else str(c)
		if cs == "true":
			cs = "rescued"
		elif cs == "false":
			cs = "ignored"
		if cs != "" and not (cs in CERES_STATUSES):
			return _fail("invalid_ceres", "ceres 必须为 rescued/ignored")
		if cs != "":
			next["ceres"] = cs
	if patch.has("ceres_status"):
		var cs2 := str(patch["ceres_status"])
		if not (cs2 in CERES_STATUSES):
			return _fail("invalid_ceres", "ceres_status 非法")
		next["ceres"] = cs2
	# Chronos
	if patch.get("chronos") is Dictionary:
		var ch: Dictionary = patch["chronos"]
		for k in ["evac", "blackbox", "telemetry"]:
			if ch.has(k):
				next["chronos"][k] = bool(ch[k])
		if ch.has("choice"):
			var cc := str(ch["choice"])
			if not (cc in ["", "accept", "reject"]):
				return _fail("invalid_chronos_choice", "chronos choice 非法")
			next["chronos"]["choice"] = cc
	for pair in [["chronos_evac", "evac"], ["chronos_blackbox", "blackbox"],
			["chronos_telemetry", "telemetry"]]:
		if patch.has(pair[0]):
			next["chronos"][pair[1]] = bool(patch[pair[0]])
	if patch.has("chronos_choice"):
		var cc2 := str(patch["chronos_choice"])
		if not (cc2 in ["", "accept", "reject"]):
			return _fail("invalid_chronos_choice", "chronos_choice 非法")
		next["chronos"]["choice"] = cc2
	# AV4412
	if patch.has("av4412"):
		var a = patch["av4412"]
		var av := str(a.get("choice", a.get("option", ""))) if a is Dictionary else str(a)
		if av != "" and not (av in AV_OPTIONS):
			return _fail("invalid_av4412", "av4412 必须为 strong/standard/question/retreat")
		if av != "":
			next["av4412"] = av
	if patch.has("av4412_choice"):
		var av2 := str(patch["av4412_choice"])
		if not (av2 in AV_OPTIONS):
			return _fail("invalid_av4412", "av4412_choice 非法")
		next["av4412"] = av2
	# evidence
	if patch.has("evidence"):
		var ev = patch["evidence"]
		var arr: Array = []
		if ev is Array:
			for x in (ev as Array):
				var norm := _norm_evidence(str(x))
				if norm == "":
					return _fail("invalid_evidence", "未知 evidence：" + str(x))
				if not (norm in arr):
					arr.append(norm)
		elif ev is Dictionary:
			for k in (ev as Dictionary).keys():
				if bool((ev as Dictionary)[k]):
					var norm2 := _norm_evidence(str(k))
					if norm2 == "":
						return _fail("invalid_evidence", "未知 evidence：" + str(k))
					if not (norm2 in arr):
						arr.append(norm2)
		else:
			return _fail("invalid_evidence", "evidence 必须是数组/对象")
		arr.sort()
		next["evidence"] = arr
	for ek in ["evidence_blackbox", "evidence_telemetry", "evidence_elint",
			"evidence_comms"]:
		if patch.has(ek):
			var nm: String = str(ek).substr(9)
			var arr2: Array = (next["evidence"] as Array).duplicate()
			if bool(patch[ek]):
				if not (nm in arr2):
					arr2.append(nm)
			else:
				arr2.erase(nm)
			arr2.sort()
			next["evidence"] = arr2
	# legal / threat / trust / political
	if patch.has("legal_status"):
		var ls := str(patch["legal_status"])
		if not (ls in LEGAL_STATUSES):
			return _fail("invalid_legal_status", "legal_status 非法")
		next["legal_status"] = ls
	if patch.has("threat"):
		if not (patch["threat"] is int or patch["threat"] is float) \
				or not is_finite(float(patch["threat"])):
			return _fail("invalid_threat", "threat 必须是有限数值")
		next["threat"] = int(patch["threat"])
	if patch.has("trust"):
		if not (patch["trust"] is int or patch["trust"] is float) \
				or not is_finite(float(patch["trust"])):
			return _fail("invalid_trust", "trust 必须是有限数值")
		next["trust"] = clampf(float(patch["trust"]), 0.0, 1.0)
	if patch.has("political"):
		var pol = patch["political"]
		if pol is int or pol is float:
			next["political"] = clampf(float(pol), 0.0, 1.0)
		else:
			var ps := str(pol).to_lower()
			if ps in ["aeug", "pro_aeug", "strong", "independent", "pro_independent"]:
				next["political"] = 1.0
			elif ps in ["ueg", "loyal", "weak", "pro_ueg"]:
				next["political"] = 0.0
			elif ps in ["neutral", "unknown"]:
				next["political"] = 0.5
			else:
				return _fail("invalid_political", "political 非法")
	if patch.has("political_aeug"):
		next["political"] = 1.0 if bool(patch["political_aeug"]) else 0.0
	# report choice via ingest
	if patch.has("report_choice"):
		var rc := _norm_choice(str(patch["report_choice"]))
		if rc == "":
			return _fail("invalid_choice", "report_choice 非法")
		next["report_choice"] = rc
		report_choice = rc
	# 未知键 -> warning，不失败
	for k2 in patch.keys():
		if not (str(k2) in ["ceres", "ceres_status", "chronos", "chronos_evac",
				"chronos_blackbox", "chronos_telemetry", "chronos_choice", "av4412",
				"av4412_choice", "evidence", "evidence_blackbox",
				"evidence_telemetry", "evidence_elint", "evidence_comms",
				"legal_status", "threat", "trust", "political", "political_aeug",
				"report_choice"]):
			warns.append("忽略未知输入：" + str(k2))
	inputs = next
	_dirty = true
	return {"ok": true, "inputs": inputs.duplicate(true), "warnings": warns,
		"changed": true}

func _norm_choice(choice: String) -> String:
	match choice:
		"submit_evidence", "submit", "report_submit", "report":
			return "submit_evidence"
		"withhold_evidence", "withhold", "report_withhold", "secret", "suppress":
			return "withhold_evidence"
	return ""

func _norm_evidence(x: String) -> String:
	return str(EVIDENCE_ALIASES.get(x.strip_edges().to_lower(), ""))

func choose_report(choice: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: AfterActionReport 未 ready")
	var c := _norm_choice(str(choice))
	if c == "":
		return _fail("invalid_choice", "precondition: report choice 必须为 submit_evidence/withhold_evidence")
	report_choice = c
	inputs["report_choice"] = c
	_dirty = true
	return {"ok": true, "report_choice": c, "inputs": inputs.duplicate(true)}

func report_choice_value() -> String:
	return report_choice

# ── 判定 / compose ─────────────────────────────────────────────

func _has_ev(name: String) -> bool:
	return name in (inputs.get("evidence", []) as Array)

func _core_missing() -> Array:
	var out: Array = []
	if str(inputs.get("ceres", "")) != "rescued":
		out.append("ceres_rescued")
	var ch: Dictionary = inputs.get("chronos", {}) as Dictionary
	for k in [["evac", "chronos_evac"], ["blackbox", "chronos_blackbox"],
			["telemetry", "chronos_telemetry"]]:
		if not bool(ch.get(str(k[0]), false)):
			out.append(str(k[1]))
	return out

func _evidence_missing() -> Array:
	var out: Array = []
	for pair in [["blackbox", "evidence_blackbox"], ["telemetry", "evidence_telemetry"],
			["elint", "evidence_elint"], ["comms", "evidence_comms"]]:
		if not _has_ev(str(pair[0])):
			out.append(str(pair[1]))
	return out

func _choose_branch(core_ok: bool, evidence_ok: bool) -> String:
	if not core_ok:
		return "standard"
	var pol := float(inputs.get("political", 0.5))
	var trust := float(inputs.get("trust", 0.5))
	var pol_th := float(rules.get("political_threshold", 0.6))
	var tr_th := float(rules.get("trust_threshold", 0.6))
	var pol_strong := pol >= pol_th
	var trust_high := trust >= tr_th
	if pol_strong and trust_high and evidence_ok:
		return "ghost_track"
	if pol_strong and (not trust_high or not evidence_ok):
		return "wrong_justice"
	if (not pol_strong) and trust_high:
		return "sleeping"
	return "ghost_track"

func compose() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: AfterActionReport 未 ready")
	var choice := report_choice
	if choice == "":
		choice = str(inputs.get("report_choice", ""))
	var core_missing := _core_missing()
	var ev_missing := _evidence_missing()
	var core_ok := core_missing.is_empty()
	var evidence_ok := ev_missing.is_empty()
	var program := core_ok and str(inputs.get("av4412", "")) == "question" \
		and choice == "submit_evidence" and evidence_ok
	var ghost := core_ok and choice == "withhold_evidence" \
		and str(inputs.get("av4412", "")) in ["strong", "standard", "question"]
	var branch := "standard"
	var report_key := "report.standard_missing_tbd"
	var missing: Array = []
	if program:
		branch = "program_justice"
		report_key = "report.program_justice"
		missing = []
	elif ghost:
		branch = _choose_branch(true, evidence_ok)
		report_key = "report.ghost_track"
		missing = ev_missing.duplicate()
	else:
		branch = "standard"
		missing = core_missing.duplicate()
		if str(inputs.get("av4412", "")) != "question":
			missing.append("av4412_question")
		if choice == "":
			missing.append("report_choice")
		elif choice == "submit_evidence":
			# 未满足程序正义：把证据缺口与报告选择纳入缺失
			for m in ev_missing:
				missing.append(m)
		else:
			# 已保密但核心/谈判不完整：缺失核心/谈判项
			if str(inputs.get("av4412", "")) not in ["strong", "standard", "question"]:
				missing.append("report_withhold")
			for m2 in ev_missing:
				missing.append(m2)
		missing = _unique(missing)
	# 选报告文本（TBD 不伪造）
	var tmpl: Dictionary = report_templates.get(report_key, {}) as Dictionary
	var zh := str(tmpl.get("zh", ""))
	var tbd := bool(tmpl.get("tbd", false))
	var report := {
		"schema": "v17.after_action_report_entry.v1",
		"text_key": report_key, "zh": zh, "en": str(tmpl.get("en", "")),
		"source_lines": (tmpl.get("source_lines", []) as Array).duplicate(),
		"tbd": tbd, "branch_hint": branch,
		"missing_items": missing.duplicate(), "evidence": (inputs.get("evidence", []) as Array).duplicate(),
		"report_choice": choice, "prologue_complete": true,
		"ending_executed": false, "writes": {"world": false, "ui": false, "v15": false}}
	_branch_hint = branch
	_missing = missing.duplicate()
	_status = "PROLOGUE_COMPLETE"
	composed = {"ok": true, "schema": SCHEMA, "branch_hint": branch,
		"prologue_status": _status, "prologue_complete": true,
		"ending_executed": false, "report": report.duplicate(true),
		"missing_items": missing.duplicate(), "inputs": inputs.duplicate(true),
		"candidates": _candidate_branch_ids(program, ghost, evidence_ok)}
	_dirty = false
	return composed.duplicate(true)

func _unique(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		if not (str(x) in out):
			out.append(str(x))
	return out

func _candidate_branch_ids(program: bool, ghost: bool, evidence_ok: bool) -> Array:
	if program:
		return ["program_justice"]
	if not ghost:
		return ["standard"]
	var out := ["ghost_track"]
	var pol := float(inputs.get("political", 0.5))
	var trust := float(inputs.get("trust", 0.5))
	if pol >= float(rules.get("political_threshold", 0.6)):
		out.append("wrong_justice")
		out.append("butterfly")
	if trust >= float(rules.get("trust_threshold", 0.6)):
		out.append("sleeping")
	if not evidence_ok:
		out.append("wrong_justice")
	out.append("colonial_savior")
	return _unique(out)

func report() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: AfterActionReport 未 ready")
	if composed.is_empty() or _dirty:
		compose()
	return (composed.get("report", {}) as Dictionary).duplicate(true)

func branch_hint() -> String:
	if not ready:
		return ""
	if composed.is_empty() or _dirty:
		compose()
	return _branch_hint

func missing_items() -> Array:
	if composed.is_empty() or _dirty:
		compose()
	return _missing.duplicate()

func report_text() -> String:
	return str(report().get("zh", ""))

# ── 文本查询 ───────────────────────────────────────────────────

func report_template(text_key: String) -> Dictionary:
	return (report_templates.get(text_key, {}) as Dictionary).duplicate(true)

func branch_text(branch_id: String) -> Dictionary:
	var br: Dictionary = branches.get(branch_id, {}) as Dictionary
	if br.is_empty():
		return {}
	return (branch_texts.get(str(br.get("text_key", "")), {}) as Dictionary).duplicate(true)

func branch_info(branch_id: String) -> Dictionary:
	return (branches.get(branch_id, {}) as Dictionary).duplicate(true)

func branch_ids() -> Array:
	return branch_order.duplicate()

func text_keys() -> Array:
	var out: Array = report_templates.keys() + branch_texts.keys()
	out.sort()
	return out

# ── VM / summary / DB ─────────────────────────────────────────

func vm() -> Dictionary:
	if _dirty and ready:
		compose()
	return {"schema": SCHEMA, "ready": ready, "status": _status,
		"prologue_complete": _status == "PROLOGUE_COMPLETE",
		"ending_executed": false, "branch_hint": _branch_hint,
		"missing_items": _missing.duplicate(),
		"report": (composed.get("report", {}) as Dictionary).duplicate(true),
		"inputs": inputs.duplicate(true), "report_choice": report_choice,
		"candidates": (["standard"] if composed.is_empty()
			else (composed.get("candidates", []) as Array).duplicate()),
		"branch_ids": branch_order.duplicate(),
		"writes": {"world": false, "ui": false, "v15": false}}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "status": _status,
		"prologue_complete": _status == "PROLOGUE_COMPLETE",
		"branch_hint": _branch_hint, "report_text_key": str(
			(composed.get("report", {}) as Dictionary).get("text_key", "")),
		"missing_items": _missing.size(), "inputs": inputs.duplicate(true),
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	if _status == "PROLOGUE_COMPLETE":
		if composed.is_empty():
			v.append("PROLOGUE_COMPLETE 无 compose 结果")
		if _branch_hint == "":
			v.append("PROLOGUE_COMPLETE 无 branch_hint")
		if bool(composed.get("ending_executed", true)):
			v.append("demo 不应执行完整结局")
		var rep: Dictionary = composed.get("report", {}) as Dictionary
		if rep.is_empty():
			v.append("PROLOGUE_COMPLETE 无 report")
		elif str(rep.get("text_key", "")) != "" \
				and not report_templates.has(str(rep.get("text_key", ""))):
			v.append("report text_key 不存在")
	if report_choice != "" and not (report_choice in CHOICES):
		v.append("report_choice 非法")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

# ── save/load ─────────────────────────────────────────────────

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"content_path": content_path, "inputs": inputs.duplicate(true),
		"report_choice": report_choice, "composed": composed.duplicate(true),
		"branch_hint": _branch_hint, "missing": _missing.duplicate(),
		"status": _status, "dirty": _dirty})

func load_state(value: Variant) -> Dictionary:
	var parsed: Variant = value
	if value is String:
		if str(value).strip_edges() == "":
			return _fail("empty_state", "load: 空 JSON")
		parsed = JSON.parse_string(str(value))
	if not (parsed is Dictionary):
		return _fail("invalid_payload", "load: JSON 无效")
	var d: Dictionary = parsed
	if str(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if str(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	if not (d.get("inputs", null) is Dictionary):
		return _fail("invalid_payload", "load: inputs 非法")
	if not (d.get("composed", null) is Dictionary):
		return _fail("invalid_payload", "load: composed 非法")
	var rch := str(d.get("report_choice", ""))
	if not (rch in ["", "submit_evidence", "withhold_evidence"]):
		return _fail("invalid_payload", "load: report_choice 非法")
	var st := str(d.get("status", "READY"))
	if not (st in ["READY", "PROLOGUE_COMPLETE"]):
		return _fail("invalid_payload", "load: status 非法")
	inputs = (d.get("inputs") as Dictionary).duplicate(true)
	report_choice = rch
	composed = (d.get("composed") as Dictionary).duplicate(true)
	_branch_hint = str(d.get("branch_hint", ""))
	_missing = (d.get("missing", []) as Array).duplicate(true) if d.get("missing") is Array else []
	_status = st
	_dirty = bool(d.get("dirty", false))
	return {"ok": true, "status": _status, "branch_hint": _branch_hint}

func reset() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_reset_state()
	return {"ok": true, "status": _status, "branch_hint": ""}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
