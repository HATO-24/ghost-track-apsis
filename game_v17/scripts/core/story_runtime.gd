extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3B：StoryRuntime（剧情运行时；新文件）
#
# - 读 teaching_l4_l1.json + story_transit_l4_l1.json（步骤/动作/文本 key/条件；
#   不写长文案、不接 UI）；
# - 状态机：chapter/phase/step；手动 note(action,target) 按 trigger 推进；
#   complete()/skip()/fail() 显式结束；不自动完成、不按时间推进；
# - 行动菜单按 gate 动态生成 available/locked/reason；输出 text_key；
# - 与 StoryState/GameSession 集成：apply effects(flags/evidence/choice/trust/...)；
#   内存 save/load（含绑定 StoryState 快照）；
# - 不实现 UI/物理；不写 world/V15。
# ═══════════════════════════════════════════════════════════════════

const StoryStateScript := preload("res://scripts/core/story_state.gd")

const STORY_SCHEMA := "v17.story_content.v1"
const TEACHING_SCHEMA := "teaching.l4_l1.v1"
const SCHEMA := "v17.story_runtime.v1"
const SAVE_SCHEMA := "v17.story_runtime_save.v1"
const VERSION := "1.0.0"
const DEFAULT_STORY_PATH := "res://framework/content/story_transit_l4_l1.json"
const DEFAULT_TEACHING_PATH := "res://framework/content/teaching_l4_l1.json"
const PHASES := ["prelude", "read", "command", "decision", "consequence", "report", "end"]
const STATUS_IDLE := "idle"
const STATUS_RUNNING := "running"
const STATUS_AWAITING := "awaiting_complete"
const STATUS_COMPLETE := "complete"
const STATUS_SKIPPED := "skipped"
const STATUS_FAILED := "failed"
const TERMINAL := [STATUS_COMPLETE, STATUS_SKIPPED, STATUS_FAILED]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var story_path := DEFAULT_STORY_PATH
var teaching_path := DEFAULT_TEACHING_PATH
var content: Dictionary = {}
var teaching: Dictionary = {}
var chapters: Array = []
var steps: Array = []
var endings: Array = []
var _step_by_id: Dictionary = {}
var _actions_by_step: Dictionary = {}
var _teaching_steps: Dictionary = {}

var chapter := ""
var phase := ""
var step_id := ""
var step_index := -1
var status := STATUS_IDLE
var ending := ""
var reason := ""
var t_s := 0.0
var history: Array = []

# 内部镜像（与 StoryState 同步；无 StoryState 时也可 gate）
var applied_flags: Dictionary = {}
var applied_evidence: Array = []
var applied_choices: Array = []
var trust := 50.0
var morality := 0.0
var reputation := 50.0
var threat := 1.0

var story_state = null
var session = null

func _init(opts := {}) -> void:
	setup(opts)

func setup(opts := {}) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	chapter = ""
	phase = ""
	step_id = ""
	step_index = -1
	status = STATUS_IDLE
	ending = ""
	reason = ""
	t_s = float(o.get("t_s", 0.0))
	history = []
	applied_flags = {}
	applied_evidence = []
	applied_choices = []
	trust = 50.0
	morality = 0.0
	reputation = 50.0
	threat = 1.0
	story_state = null
	session = null
	var sp := String(o.get("story_path", DEFAULT_STORY_PATH))
	var tp := String(o.get("teaching_path", DEFAULT_TEACHING_PATH))
	var lr: Dictionary = load_content(sp, tp)
	if not bool(lr.get("ok", false)):
		return false
	if o.get("story_state", null) != null:
		bind_story_state(o.get("story_state"))
	if o.get("session", null) != null:
		bind_session(o.get("session"))
	ready = true
	return true

# ── 内容 ────────────────────────────────────────────────────────

func load_content(path_story := DEFAULT_STORY_PATH, path_teach := DEFAULT_TEACHING_PATH) -> Dictionary:
	var story_data = _read_json(path_story)
	var teach_data = _read_json(path_teach)
	if not (story_data is Dictionary):
		errors.append("story content JSON 无效：" + path_story)
		return {"ok": false, "errors": errors.duplicate()}
	if not (teach_data is Dictionary):
		errors.append("teaching JSON 无效：" + path_teach)
		return {"ok": false, "errors": errors.duplicate()}
	var v: Dictionary = validate_content(story_data, teach_data)
	if not bool(v.get("ok", false)):
		errors.append_array(v.get("errors", []))
		warnings.append_array(v.get("warnings", []))
		return {"ok": false, "errors": errors.duplicate()}
	story_path = path_story
	teaching_path = path_teach
	content = (story_data as Dictionary).duplicate(true)
	teaching = (teach_data as Dictionary).duplicate(true)
	chapters = (content.get("chapters", []) as Array).duplicate(true)
	steps = (content.get("steps", []) as Array).duplicate(true)
	endings = (content.get("endings", []) as Array).duplicate(true)
	_step_by_id = {}
	_actions_by_step = {}
	for raw in steps:
		var s: Dictionary = raw
		_step_by_id[String(s.get("id", ""))] = s
		_actions_by_step[String(s.get("id", ""))] = (s.get("actions", []) as Array).duplicate(true)
	_teaching_steps = {}
	for raw_t in (teaching.get("steps", []) as Array):
		if raw_t is Dictionary:
			_teaching_steps[String((raw_t as Dictionary).get("id", ""))] = true
	ready = true
	return {"ok": true, "errors": [], "warnings": warnings.duplicate()}

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## 校验内容（公开；供内容 CI/probe）。
func validate_content(story_data: Dictionary, teach_data: Dictionary) -> Dictionary:
	var errs: Array[String] = []
	var warns: Array[String] = []
	if String(story_data.get("schema", "")) != STORY_SCHEMA:
		errs.append("story schema 必须为 " + STORY_SCHEMA)
	if String(story_data.get("version", "")) == "":
		errs.append("story version 不能为空")
	if String(story_data.get("scenario_id", "")) == "":
		errs.append("story scenario_id 不能为空")
	if not bool(story_data.get("manual_only", false)):
		errs.append("story manual_only 必须为 true（不得自动完成）")
	if bool(story_data.get("auto_complete", true)):
		errs.append("story auto_complete 必须为 false")
	if String(teach_data.get("schema", "")) != TEACHING_SCHEMA:
		errs.append("teaching schema 必须为 " + TEACHING_SCHEMA)
	# teaching steps
	var tids := {}
	if teach_data.get("steps") is Array:
		for raw in (teach_data.get("steps") as Array):
			if raw is Dictionary:
				var tid := String((raw as Dictionary).get("id", ""))
				if tid == "":
					errs.append("teaching step 缺 id")
				elif tids.has(tid):
					errs.append("teaching step id 重复：" + tid)
				else:
					tids[tid] = true
	else:
		errs.append("teaching steps 必须是数组")
	# chapters
	var ch_ids := {}
	var ch_phase := {}
	if story_data.get("chapters") is Array and not (story_data.get("chapters") as Array).is_empty():
		for raw_c in (story_data.get("chapters") as Array):
			if not (raw_c is Dictionary):
				errs.append("chapter 非对象")
				continue
			var c: Dictionary = raw_c
			var cid := String(c.get("id", ""))
			if cid == "" or ch_ids.has(cid):
				errs.append("chapter id 空/重复：" + cid)
				continue
			ch_ids[cid] = true
			var cp := String(c.get("phase", ""))
			if not (cp in PHASES):
				errs.append("chapter %s phase 非法：%s" % [cid, cp])
			ch_phase[cid] = cp
			if String(c.get("title_key", "")) == "":
				errs.append("chapter %s 缺 title_key" % cid)
	else:
		errs.append("chapters 必须是非空数组")
	# steps
	var step_ids := {}
	var seen_order := {}
	if story_data.get("steps") is Array and not (story_data.get("steps") as Array).is_empty():
		for raw_s in (story_data.get("steps") as Array):
			if not (raw_s is Dictionary):
				errs.append("step 非对象")
				continue
			var s: Dictionary = raw_s
			var sid := String(s.get("id", ""))
			if sid == "" or step_ids.has(sid):
				errs.append("step id 空/重复：" + sid)
				continue
			step_ids[sid] = true
			var ord := int(s.get("order", 0))
			if ord <= 0 or seen_order.has(ord):
				errs.append("step %s order 非法/重复：%d" % [sid, ord])
			seen_order[ord] = true
			var cid2 := String(s.get("chapter", ""))
			if not ch_ids.has(cid2):
				errs.append("step %s chapter 不存在：%s" % [sid, cid2])
			var ph := String(s.get("phase", ""))
			if not (ph in PHASES):
				errs.append("step %s phase 非法：%s" % [sid, ph])
			if String(s.get("title_key", "")) == "":
				errs.append("step %s 缺 title_key" % sid)
			for raw_tid in (s.get("teaching_step_ids", []) as Array) if s.get("teaching_step_ids") is Array else []:
				if not tids.has(String(raw_tid)):
					warns.append("step %s 引用未知 teaching step：%s" % [sid, String(raw_tid)])
			for raw_tk in (s.get("text_keys", []) as Array) if s.get("text_keys") is Array else []:
				if String(raw_tk) == "":
					errs.append("step %s text_keys 含空串" % sid)
			var acts = s.get("actions")
			if not (acts is Array) or (acts as Array).is_empty():
				errs.append("step %s actions 必须是非空数组" % sid)
				continue
			var aids := {}
			for raw_a in (acts as Array):
				if not (raw_a is Dictionary):
					errs.append("step %s action 非对象" % sid)
					continue
				var a: Dictionary = raw_a
				var aid := String(a.get("id", ""))
				if aid == "" or aids.has(aid):
					errs.append("step %s action id 空/重复：%s" % [sid, aid])
					continue
				aids[aid] = true
				if String(a.get("action", "")) == "":
					errs.append("action %s 缺 action 名" % aid)
				if String(a.get("label_key", "")) == "":
					errs.append("action %s 缺 label_key" % aid)
				if a.has("gate") and not (a.get("gate") is Dictionary):
					errs.append("action %s gate 必须是对象" % aid)
				if a.has("effects") and not (a.get("effects") is Dictionary):
					errs.append("action %s effects 必须是对象" % aid)
				if a.has("advance") and not (a.get("advance") is bool):
					errs.append("action %s advance 必须是 bool" % aid)
	else:
		errs.append("steps 必须是非空数组")
	# endings
	if story_data.get("endings") is Array:
		var eids := {}
		for raw_e in (story_data.get("endings") as Array):
			if raw_e is Dictionary:
				var eid := String((raw_e as Dictionary).get("id", ""))
				if eid == "" or eids.has(eid):
					errs.append("ending id 空/重复：" + eid)
				eids[eid] = true
	# action ending 引用
	for raw_s2 in (story_data.get("steps", []) as Array):
		if not (raw_s2 is Dictionary):
			continue
		for raw_a2 in ((raw_s2 as Dictionary).get("actions", []) as Array):
			if raw_a2 is Dictionary and String((raw_a2 as Dictionary).get("ending", "")) != "":
				if not (String((raw_a2 as Dictionary).get("ending", "")) in _ending_ids(story_data)):
					errs.append("action ending 不存在：" + String((raw_a2 as Dictionary).get("ending", "")))
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns}

func _ending_ids(data: Dictionary) -> Array:
	var out: Array = []
	for raw in (data.get("endings", []) as Array):
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("id", "")))
	return out

# ── 状态机 ──────────────────────────────────────────────────────

func start(from_chapter := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var idx := 0
	if from_chapter != "":
		idx = -1
		for i in range(steps.size()):
			if String((steps[i] as Dictionary).get("chapter", "")) == from_chapter:
				idx = i
				break
		if idx < 0:
			return {"ok": false, "reason": "unknown_chapter"}
	step_index = idx
	var s: Dictionary = steps[idx]
	chapter = String(s.get("chapter", ""))
	phase = String(s.get("phase", ""))
	step_id = String(s.get("id", ""))
	status = STATUS_RUNNING
	ending = ""
	reason = ""
	history = []
	_sync_internal_from_story()
	return {"ok": true, "chapter": chapter, "phase": phase, "step_id": step_id,
		"status": status, "step": current_step(), "menu": menu(),
		"text_keys": text_keys()}

func current_step() -> Dictionary:
	return (_step_by_id.get(step_id, {}) as Dictionary).duplicate(true)

func chapter_list() -> Array:
	return chapters.duplicate(true)

func step_list() -> Array:
	return steps.duplicate(true)

func ending_list() -> Array:
	return endings.duplicate(true)

func current_actions() -> Array:
	return (_actions_by_step.get(step_id, []) as Array).duplicate(true)

func text_keys() -> Array:
	var out: Array = []
	var s: Dictionary = _step_by_id.get(step_id, {})
	out.append(String(s.get("title_key", "")))
	var tks: Array = s.get("text_keys", []) if s.get("text_keys") is Array else []
	for raw in tks:
		if not (String(raw) in out):
			out.append(String(raw))
	for raw_a in current_actions():
		var lk := String((raw_a as Dictionary).get("label_key", ""))
		if lk != "" and not (lk in out):
			out.append(lk)
	return out

## 动态行动菜单：available/locked/reason（基于 gate）。
func menu() -> Array:
	var out: Array = []
	for raw in current_actions():
		var a: Dictionary = raw
		var g: Dictionary = eval_gate(a.get("gate", {}))
		var available := bool(g.get("ok", false)) and bool(g.get("passed", false)) and status == STATUS_RUNNING
		var why := ""
		if not available:
			if status != STATUS_RUNNING:
				why = "not_running"
			elif not bool(g.get("ok", false)):
				why = "gate_error"
			else:
				var failed: Array = g.get("failed", [])
				why = str(failed) if not failed.is_empty() else String(a.get("locked_reason", "locked"))
		out.append({
			"id": String(a.get("id", "")),
			"action": String(a.get("action", "")),
			"target": String(a.get("target", "")),
			"label_key": String(a.get("label_key", "")),
			"available": available,
			"locked": not available,
			"reason": why,
			"advance": bool(a.get("advance", false)),
		})
	return out

func available_actions() -> Array:
	var out: Array = []
	for row in menu():
		if bool((row as Dictionary).get("available", false)):
			out.append(row)
	return out

## 手动行动：只有当前 step 的可用 action 能推进；不自动完成。
func note(action: String, target := "") -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: runtime 未 ready")
	if status == STATUS_IDLE:
		return _fail("not_started", "precondition: 需先 start()")
	if status in TERMINAL:
		return _fail("already_terminal", "precondition: 已结束（" + status + "）")
	if status != STATUS_RUNNING:
		return _fail("not_running", "precondition: 状态 " + status)
	var step: Dictionary = _step_by_id.get(step_id, {})
	var action_row := {}
	var name_matched := false
	for raw in ((step.get("actions", []) as Array) if step.get("actions") is Array else []):
		var a: Dictionary = raw
		if String(a.get("action", "")) != action:
			continue
		name_matched = true
		var at := String(a.get("target", ""))
		if at == "" or at == target:
			action_row = a
			break
	if action_row.is_empty():
		if name_matched:
			return _fail("target_mismatch", "precondition: 目标不匹配（%s）" % target)
		return _fail("wrong_action", "precondition: 当前 step 无 action " + action)
	var gate: Dictionary = eval_gate(action_row.get("gate", {}))
	if not bool(gate.get("ok", false)) or not bool(gate.get("passed", false)):
		return {"ok": false, "reason": "action_locked",
			"failed": gate.get("failed", []), "menu": menu(),
			"locked_reason": String(action_row.get("locked_reason", ""))}
	var eff: Dictionary = apply_effects(action_row.get("effects", {}))
	if not bool(eff.get("ok", false)):
		return {"ok": false, "reason": "effects_failed", "errors": eff.get("errors", [])}
	var from_step := step_id
	if String(action_row.get("ending", "")) != "":
		ending = String(action_row.get("ending", ""))
	history.append({
		"t": _now_s(),
		"step_id": from_step,
		"action": action,
		"target": target,
		"choice": String(action_row.get("id", "")),
		"effects": (action_row.get("effects", {}) as Dictionary).duplicate(true),
		"text_keys": text_keys(),
	})
	var next_step := ""
	var advanced := false
	if bool(action_row.get("advance", false)):
		advanced = true
		if step_index + 1 < steps.size():
			step_index += 1
			var ns: Dictionary = steps[step_index]
			chapter = String(ns.get("chapter", ""))
			phase = String(ns.get("phase", ""))
			step_id = String(ns.get("id", ""))
			next_step = step_id
		else:
			status = STATUS_AWAITING
			next_step = ""
	_sync_internal_from_story()
	_check_contracts()
	return {"ok": true, "accepted": true, "step_id": from_step,
		"next_step_id": next_step, "advanced": advanced, "status": status,
		"ending": ending, "effects": eff.get("applied", {}),
		"menu": menu(), "text_keys": text_keys()}

## 显式完成（所有步骤推进后）；不自动完成。
func complete() -> Dictionary:
	if status != STATUS_AWAITING:
		return _fail("complete_not_ready", "precondition: 未到完成点（status=%s）" % status)
	status = STATUS_COMPLETE
	if ending == "":
		ending = _ending_from_flags()
	_sync_internal_from_story()
	_check_contracts()
	return {"ok": true, "status": status, "ending": ending,
		"flags": applied_flags.duplicate(true)}

func skip(reason_text := "skipped") -> Dictionary:
	if status in TERMINAL:
		return _fail("already_terminal", "precondition: 已结束（" + status + "）")
	if status == STATUS_IDLE:
		return _fail("not_started", "precondition: 需先 start()")
	status = STATUS_SKIPPED
	reason = String(reason_text)
	return {"ok": true, "status": status, "reason": reason}

func fail(reason_text := "failed") -> Dictionary:
	if status in TERMINAL:
		return _fail("already_terminal", "precondition: 已结束（" + status + "）")
	status = STATUS_FAILED
	reason = String(reason_text)
	return {"ok": true, "status": status, "reason": reason}

func _ending_from_flags() -> String:
	for raw in endings:
		var e: Dictionary = raw
		var ok := true
		for raw_f in (e.get("flags", []) as Array):
			if not applied_flags.has(String(raw_f)):
				ok = false
				break
		if ok:
			return String(e.get("id", ""))
	return ""

# ── gate / effects / 集成 ───────────────────────────────────────

## gate：绑定 StoryState 时用 StoryState.gate；否则用内部镜像做子集判定。
func eval_gate(conditions := {}) -> Dictionary:
	var c: Dictionary = conditions if conditions is Dictionary else {}
	if story_state != null and bool(story_state.ready):
		return story_state.gate(c)
	var failed: Array = []
	if c.get("flags") is Array:
		for name in (c.get("flags") as Array):
			if not applied_flags.has(String(name)):
				failed.append("flag_missing:" + String(name))
	if c.get("flags_any") is Array:
		var any_ok := false
		for name in (c.get("flags_any") as Array):
			if applied_flags.has(String(name)):
				any_ok = true
		if not any_ok:
			failed.append("flags_any_none")
	if c.get("flags_not") is Array:
		for name in (c.get("flags_not") as Array):
			if applied_flags.has(String(name)):
				failed.append("flag_present:" + String(name))
	if c.get("evidence") is Array:
		for eid in (c.get("evidence") as Array):
			if not (String(eid) in applied_evidence):
				failed.append("evidence_missing:" + String(eid))
	if c.has("trust_min") and trust < float(c.get("trust_min")):
		failed.append("trust_below_min")
	if c.has("trust_max") and trust > float(c.get("trust_max")):
		failed.append("trust_above_max")
	if c.has("morality_min") and morality < float(c.get("morality_min")):
		failed.append("morality_below_min")
	if c.has("morality_max") and morality > float(c.get("morality_max")):
		failed.append("morality_above_max")
	if c.has("reputation_min") and reputation < float(c.get("reputation_min")):
		failed.append("reputation_below_min")
	if c.has("reputation_max") and reputation > float(c.get("reputation_max")):
		failed.append("reputation_above_max")
	if c.has("threat_min") and threat < float(c.get("threat_min")):
		failed.append("threat_below_min")
	if c.has("threat_max") and threat > float(c.get("threat_max")):
		failed.append("threat_above_max")
	if c.has("chapter") and chapter != String(c.get("chapter", "")):
		failed.append("chapter_mismatch")
	if c.has("phase") and phase != String(c.get("phase", "")):
		failed.append("phase_mismatch")
	return {"ok": true, "passed": failed.is_empty(), "failed": failed, "details": {}}

## 应用效果（flags/evidence/choice/trust/morality/reputation/threat）；同步 StoryState。
func apply_effects(effects := {}) -> Dictionary:
	if not (effects is Dictionary):
		return {"ok": false, "errors": ["effects 必须是对象"]}
	var e: Dictionary = effects
	var applied := {"flags": [], "evidence": [], "choice": "", "stats": {}}
	var errs: Array[String] = []
	# flags
	if e.get("flags") is Array:
		for raw in (e.get("flags") as Array):
			var flag := String(raw)
			if flag == "":
				errs.append("空 flag")
				continue
			if story_state != null:
				var fr: Dictionary = story_state.set_flag(flag, true)
				if not bool(fr.get("ok", false)):
					errs.append("flag 失败：" + flag)
					continue
			applied_flags[flag] = true
			(applied["flags"] as Array).append(flag)
	# evidence
	if e.get("evidence") is Array:
		for raw_e in (e.get("evidence") as Array):
			var eid := String(raw_e)
			if eid == "":
				errs.append("空 evidence")
				continue
			if story_state != null:
				var er: Dictionary = story_state.add_evidence(eid)
				if not bool(er.get("ok", false)) and String(er.get("reason", "")) != "duplicate_evidence":
					errs.append("evidence 失败：" + eid)
					continue
			if not (eid in applied_evidence):
				applied_evidence.append(eid)
			(applied["evidence"] as Array).append(eid)
	# choice
	var choice_id := String(e.get("choice", ""))
	if choice_id != "":
		if story_state != null:
			var cr: Dictionary = story_state.record_choice(choice_id,
				{"step_id": step_id, "chapter": chapter, "phase": phase})
			if not bool(cr.get("ok", false)) and String(cr.get("reason", "")) != "duplicate_choice":
				errs.append("choice 失败：" + choice_id)
			else:
				applied["choice"] = choice_id
		else:
			applied["choice"] = choice_id
		if not (choice_id in applied_choices):
			applied_choices.append(choice_id)
	# stats deltas
	for pair in [["trust", trust], ["morality", morality], ["reputation", reputation],
			["threat", threat]]:
		var stat := String(pair[0])
		if not e.has(stat):
			continue
		var delta := float(e.get(stat))
		if story_state != null:
			match stat:
				"trust":
					var tr: Dictionary = story_state.adjust_trust(delta)
					applied["stats"][stat] = float(tr.get("after", 0.0))
					trust = float(tr.get("after", trust))
				"morality":
					var mr: Dictionary = story_state.adjust_morality(delta)
					applied["stats"][stat] = float(mr.get("after", 0.0))
					morality = float(mr.get("after", morality))
				"reputation":
					var rr: Dictionary = story_state.adjust_reputation(delta)
					applied["stats"][stat] = float(rr.get("after", 0.0))
					reputation = float(rr.get("after", reputation))
				"threat":
					var thr: Dictionary = story_state.adjust_threat(delta)
					applied["stats"][stat] = float(thr.get("after", 0.0))
					threat = float(thr.get("after", threat))
		else:
			_set_internal_stat(stat, delta, applied)
	# 同步 story 时间/统计
	_sync_internal_from_story()
	return {"ok": errs.is_empty(), "applied": applied, "errors": errs}

func _set_internal_stat(stat: String, delta: float, applied: Dictionary) -> void:
	var cur := 0.0
	var lo := 0.0
	var hi := 100.0
	match stat:
		"trust": cur = trust; lo = 0.0; hi = 100.0
		"morality": cur = morality; lo = -100.0; hi = 100.0
		"reputation": cur = reputation; lo = 0.0; hi = 100.0
		"threat": cur = threat; lo = 0.0; hi = 5.0
		_: return
	var after := clampf(cur + delta, lo, hi)
	match stat:
		"trust": trust = after
		"morality": morality = after
		"reputation": reputation = after
		"threat": threat = after
	(applied.get("stats", {}) as Dictionary)[stat] = after

## 绑定 StoryState（读/写 flags/evidence/choices/stats）。
func bind_story_state(ss) -> Dictionary:
	if ss == null or not ss.has_method("has_flag"):
		return {"ok": false, "reason": "invalid_story_state"}
	story_state = ss
	_sync_internal_from_story()
	return {"ok": true, "story_ready": bool(ss.ready)}

## 绑定 GameSession（取时间；若 session 有 story_state 则自动绑定）。
func bind_session(s) -> Dictionary:
	if s == null:
		return {"ok": false, "reason": "invalid_session"}
	session = s
	var ss = s.get("story_state") if s.has_method("get") else null
	if ss != null and story_state == null:
		bind_story_state(ss)
	t_s = _now_s()
	return {"ok": true, "bound": true, "has_story_state": story_state != null}

func _sync_internal_from_story() -> void:
	if story_state == null:
		return
	applied_flags = (story_state.flags as Dictionary).duplicate(true)
	applied_evidence = (story_state.evidence_ids as Array).duplicate()
	applied_choices = []
	for raw in (story_state.choices as Array):
		if raw is Dictionary:
			applied_choices.append(String((raw as Dictionary).get("choice_id", "")))
	trust = float(story_state.trust)
	morality = float(story_state.morality)
	reputation = float(story_state.reputation)
	threat = float(story_state.threat)

func _now_s() -> float:
	if session != null and session.has_method("now_s"):
		return float(session.now_s())
	return t_s

# ── DbC / 快照 ──────────────────────────────────────────────────

func _check_contracts() -> void:
	var v: Array = _violations()
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("runtime 不变量失败：" + str(v))

func _violations() -> Array[String]:
	var v: Array[String] = []
	if not (status in [STATUS_IDLE, STATUS_RUNNING, STATUS_AWAITING, STATUS_COMPLETE,
			STATUS_SKIPPED, STATUS_FAILED]):
		v.append("status 非法：" + status)
	if status != STATUS_IDLE and not _step_by_id.has(step_id):
		v.append("step_id 不存在：" + step_id)
	if status != STATUS_IDLE and step_index >= 0 and step_index < steps.size():
		var s: Dictionary = steps[step_index]
		if String(s.get("chapter", "")) != chapter:
			v.append("chapter 与 step 不一致")
		if String(s.get("phase", "")) != phase:
			v.append("phase 与 step 不一致")
	if story_state != null and bool(story_state.ready):
		if bool(story_state.check_contracts().get("ok", false)) == false:
			v.append("StoryState 不变量失败")
	if not is_finite(trust) or trust < 0.0 or trust > 100.0:
		v.append("trust 越界")
	if not is_finite(morality) or morality < -100.0 or morality > 100.0:
		v.append("morality 越界")
	if not is_finite(reputation) or reputation < 0.0 or reputation > 100.0:
		v.append("reputation 越界")
	if not is_finite(threat) or threat < 0.0 or threat > 5.0:
		v.append("threat 越界")
	return v

func check_contracts() -> Dictionary:
	return {"schema": SCHEMA, "ok": _violations().is_empty(), "violations": _violations()}

func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"ready": ready,
		"story_path": story_path,
		"teaching_path": teaching_path,
		"scenario_id": String(content.get("scenario_id", "")),
		"chapter": chapter,
		"phase": phase,
		"step_id": step_id,
		"step_index": step_index,
		"step_count": steps.size(),
		"status": status,
		"ending": ending,
		"reason": reason,
		"t_s": _now_s(),
		"history": history.duplicate(true),
		"step": current_step(),
		"menu": menu(),
		"available_actions": available_actions(),
		"text_keys": text_keys(),
		"applied": {
			"flags": applied_flags.duplicate(true),
			"evidence": applied_evidence.duplicate(),
			"choices": applied_choices.duplicate(),
			"trust": trust, "morality": morality,
			"reputation": reputation, "threat": threat,
		},
		"story": story_state.snapshot() if story_state != null else null,
		"bound_session": session != null,
		"contracts": check_contracts(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate(),
	}

func vm() -> Dictionary:
	return snapshot()

func to_dict() -> Dictionary:
	return snapshot()

func to_json() -> String:
	return JSON.stringify(snapshot())

# ── 内存 save/load ─────────────────────────────────────────────

func save_state() -> String:
	return JSON.stringify({
		"schema": SAVE_SCHEMA,
		"version": VERSION,
		"story_path": story_path,
		"teaching_path": teaching_path,
		"chapter": chapter, "phase": phase, "step_id": step_id,
		"step_index": step_index, "status": status, "ending": ending,
		"reason": reason, "t_s": _now_s(),
		"history": JSON.parse_string(JSON.stringify(history)),
		"flags": JSON.parse_string(JSON.stringify(applied_flags)),
		"evidence": applied_evidence.duplicate(),
		"choices": applied_choices.duplicate(),
		"trust": trust, "morality": morality,
		"reputation": reputation, "threat": threat,
		"story_save": story_state.save_state() if story_state != null else "",
	})

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		return _fail("empty_state", "load: 空 JSON")
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return _fail("invalid_json", "load: JSON 无效")
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if String(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	if not ready:
		return _fail("not_ready", "load: runtime 未 ready")
	var saved_step := String(d.get("step_id", ""))
	if saved_step != "" and not _step_by_id.has(saved_step):
		return _fail("invalid_step", "load: step 不存在：" + saved_step)
	var saved_status := String(d.get("status", ""))
	if not (saved_status in [STATUS_IDLE, STATUS_RUNNING, STATUS_AWAITING,
			STATUS_COMPLETE, STATUS_SKIPPED, STATUS_FAILED]):
		return _fail("invalid_status", "load: status 非法：" + saved_status)
	# 先校验 story 快照（不写状态）
	var saved_story := String(d.get("story_save", ""))
	if saved_story != "" and story_state != null:
		var probe_story = StoryStateScript.new()
		var sres: Dictionary = probe_story.load(saved_story)
		if not bool(sres.get("ok", false)):
			return _fail("invalid_story_save", "load: StoryState 快照无效")
	# 应用
	chapter = String(d.get("chapter", ""))
	phase = String(d.get("phase", ""))
	step_id = saved_step
	step_index = int(d.get("step_index", -1))
	status = saved_status
	ending = String(d.get("ending", ""))
	reason = String(d.get("reason", ""))
	t_s = float(d.get("t_s", 0.0))
	history = (d.get("history", []) as Array).duplicate(true) if d.get("history") is Array else []
	var f = d.get("flags", {})
	applied_flags = (f as Dictionary).duplicate(true) if f is Dictionary else {}
	applied_evidence = (d.get("evidence", []) as Array).duplicate() if d.get("evidence") is Array else []
	applied_choices = (d.get("choices", []) as Array).duplicate() if d.get("choices") is Array else []
	trust = float(d.get("trust", 50.0))
	morality = float(d.get("morality", 0.0))
	reputation = float(d.get("reputation", 50.0))
	threat = float(d.get("threat", 1.0))
	if saved_story != "" and story_state != null:
		var sr2: Dictionary = story_state.load(saved_story)
		if not bool(sr2.get("ok", false)):
			return _fail("story_restore_failed", "load: StoryState 恢复失败")
		_sync_internal_from_story()
	_check_contracts()
	return {"ok": true, "status": status, "step_id": step_id,
		"chapter": chapter, "phase": phase, "ending": ending, "errors": []}

func reset() -> Dictionary:
	chapter = ""
	phase = ""
	step_id = ""
	step_index = -1
	status = STATUS_IDLE
	ending = ""
	reason = ""
	history = []
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	return {"ok": true, "status": status}

# ── 内部 ────────────────────────────────────────────────────────

func _fail(reason_text: String, msg: String) -> Dictionary:
	reason = String(reason_text)
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": String(reason_text), "errors": [msg]}

func _now() -> float:
	return _now_s()
