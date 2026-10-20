extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3V：ChronosChain（Chronos 港务/私人通信/行动链；新文件）
#
# 状态机（手动 advance，不自动推进剧情）：
#   WAIT_DOCK → PORT_COMM → ACTION_EVAC → PRIVATE_COMM → CHOICE
#     → ACTIONS → WINDOW_END → COMPLETE
# - 接受/拒绝互斥；接受提高 trust 并解锁 blackbox/telemetry/evidence；
#   拒绝降低 trust，但保留“后续仍可再建议”；
# - 行动：evac / blackbox / telemetry / evidence；输出 flags/evidence/
#   trust/reputation/events；窗口期结束只标记 handoff 4412，不自动推进；
# - 文本从 docs/44 原样抽取（story_chronos.json），不改写；
# - 不写 world/UI；与 CeresChain 输入解耦。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.chronos_chain.v1"
const SAVE_SCHEMA := "v17.chronos_chain_save.v1"
const CONTENT_SCHEMA := "v17.story_chronos.v1"
const EVENT_SCHEMA := "chronos_chain_event.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/story_chronos.json"
const STATES := ["WAIT_DOCK", "PORT_COMM", "ACTION_EVAC", "PRIVATE_COMM",
	"CHOICE", "ACTIONS", "WINDOW_END", "COMPLETE"]
const ACTIONS_BY_STATE := {
	"WAIT_DOCK": ["port_comm"],
	"PORT_COMM": ["action_evac"],
	"ACTION_EVAC": ["private_comm"],
	"PRIVATE_COMM": ["choose_accept", "choose_reject"],
	"CHOICE": ["open_actions"],
	"ACTIONS": ["evac", "blackbox", "telemetry", "evidence", "window_end"],
	"WINDOW_END": ["complete"],
	"COMPLETE": [],
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var source_path := ""
var entity_id := "chronos"
var exit_on_deny_keys: Array = []
var triggers_cfg: Dictionary = {}
var trust_cfg: Dictionary = {}
var actions_cfg: Dictionary = {}
var reputation_cfg: Dictionary = {}
var texts: Dictionary = {}
var text_keys: Array = []

var state := "WAIT_DOCK"
var trust := 0
var choice := ""
var flags: Dictionary = {}
var evidence: Array = []
var events: Array = []
var notes: Array = []
var emitted_triggers: Array = []
var reputation: Dictionary = {}
var done_actions: Dictionary = {}
var _event_seq := 0
var _evidence_seq := 0
var _note_seq := 0

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup / content ───────────────────────────────────────────

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	content = {}
	content_path = str(c.get("content_path", DEFAULT_CONTENT))
	if c.get("content") is Dictionary and not (c.get("content") as Dictionary).is_empty():
		content = (c.get("content") as Dictionary).duplicate(true)
	else:
		content = _read_json(content_path)
	if content.is_empty():
		errors.append("Chronos 链内容不可读：" + content_path)
		return false
	var v: Dictionary = validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("chronos: " + str(e))
		return false
	_apply_content(content)
	_reset_runtime()
	ready = true
	return true

func _apply_content(d: Dictionary) -> void:
	content = d.duplicate(true)
	source_path = str(d.get("source_path", ""))
	entity_id = str(d.get("entity_id", "chronos"))
	triggers_cfg = (d.get("triggers", {}) as Dictionary).duplicate(true)
	trust_cfg = (d.get("trust", {}) as Dictionary).duplicate(true)
	actions_cfg = (d.get("actions", {}) as Dictionary).duplicate(true)
	reputation_cfg = (d.get("reputation", {}) as Dictionary).duplicate(true)
	texts = {}
	text_keys = []
	for raw in (d.get("texts", []) as Array):
		if raw is Dictionary:
			var t: Dictionary = (raw as Dictionary).duplicate(true)
			texts[str(t.get("text_key", ""))] = t
			text_keys.append(str(t.get("text_key", "")))
	text_keys.sort()

func _reset_runtime() -> void:
	state = "WAIT_DOCK"
	trust = int(trust_cfg.get("initial", 0))
	choice = ""
	flags = {}
	evidence = []
	events = []
	notes = []
	emitted_triggers = []
	reputation = {}
	done_actions = {}
	_event_seq = 0
	_evidence_seq = 0
	_note_seq = 0

func validate_content(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != CONTENT_SCHEMA:
		errs.append("schema 必须为 " + CONTENT_SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	if str(d.get("entity_id", "")) == "":
		errs.append("entity_id 为空")
	var chain = d.get("chain", null)
	if not (chain is Array) or (chain as Array).size() != STATES.size():
		errs.append("chain 必须为 " + str(STATES))
	else:
		for i in range(STATES.size()):
			if str((chain as Array)[i]) != str(STATES[i]):
				errs.append("chain 顺序必须为 " + str(STATES))
				break
	var texts_in = d.get("texts", null)
	if not (texts_in is Array) or (texts_in as Array).is_empty():
		errs.append("texts 必须为非空数组")
	else:
		var keys: Dictionary = {}
		for raw in (texts_in as Array):
			if not (raw is Dictionary):
				errs.append("text 非对象")
				continue
			var t: Dictionary = raw
			var key := str(t.get("text_key", ""))
			if key == "":
				errs.append("text_key 为空")
			elif keys.has(key):
				errs.append("text_key 重复：" + key)
			keys[key] = true
			if str(t.get("zh", "")) == "":
				errs.append("text %s zh 为空" % key)
			if not (t.get("en") is String):
				errs.append("text %s en 必须是字符串" % key)
			var sl = t.get("source_lines", null)
			if not (sl is Array) or (sl as Array).is_empty():
				errs.append("text %s source_lines 为空" % key)
			else:
				for n in (sl as Array):
					if not (n is int or n is float) or int(float(n)) <= 0:
						errs.append("text %s source_lines 非法" % key)
	var tr = d.get("triggers", null)
	if not (tr is Dictionary):
		errs.append("triggers 必须是对象")
	else:
		for k in ["port_comm", "private_comm", "accept", "reject", "evac",
				"blackbox", "telemetry", "window_end"]:
			if str((tr as Dictionary).get(k, "")) == "":
				errs.append("triggers.%s 为空" % k)
	if not (d.get("trust", null) is Dictionary):
		errs.append("trust 必须是对象")
	if not (d.get("actions", null) is Dictionary):
		errs.append("actions 必须是对象")
	if not (d.get("reputation", null) is Dictionary):
		errs.append("reputation 必须是对象")
	return {"ok": errs.is_empty(), "errors": errs}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

# ── 查询 ────────────────────────────────────────────────────────

func current_state() -> String:
	return state

func is_complete() -> bool:
	return state == "COMPLETE"

func chosen_choice() -> String:
	return choice

func get_trust() -> int:
	return trust

func trust_state() -> String:
	if trust > 0:
		return "trusted"
	if trust < 0:
		return "cold"
	return "neutral"

func get_flags() -> Dictionary:
	return flags.duplicate(true)

func get_flag(key: String) -> Variant:
	return flags.get(key, null)

func get_evidence() -> Array:
	return evidence.duplicate(true)

func get_events() -> Array:
	return events.duplicate(true)

func get_notes() -> Array:
	return notes.duplicate(true)

func get_reputation() -> Dictionary:
	return reputation.duplicate(true)

func get_triggers() -> Array:
	return emitted_triggers.duplicate(true)

func trigger_ids() -> Array:
	var out: Array = []
	for t in emitted_triggers:
		var tid := str((t as Dictionary).get("trigger_id", ""))
		if tid != "" and not (tid in out):
			out.append(tid)
	return out

func text(text_key: String) -> Dictionary:
	return (texts.get(text_key, {}) as Dictionary).duplicate(true)

func text_keys_list() -> Array:
	return text_keys.duplicate()

# ── 行动可用性 ──────────────────────────────────────────────────

func available_actions() -> Array:
	if state != "ACTIONS":
		return (ACTIONS_BY_STATE.get(state, []) as Array).duplicate()
	var out: Array = []
	if not bool(done_actions.get("evac", false)):
		out.append("evac")
	if choice == "accept":
		if not bool(done_actions.get("blackbox", false)):
			out.append("blackbox")
		if not bool(done_actions.get("telemetry", false)):
			out.append("telemetry")
		if not bool(done_actions.get("evidence", false)):
			out.append("evidence")
	out.append("window_end")
	return out

func can_advance(action: String) -> bool:
	return action in available_actions()

## 动态行动详情（含未解锁原因），供 UI 读取；不改变状态。
func action_details() -> Array:
	var out: Array = []
	for a in ["evac", "blackbox", "telemetry", "evidence", "window_end"]:
		var enabled := false
		var reason := ""
		if not (state == "ACTIONS"):
			enabled = false
			reason = "not_in_actions"
		elif a == "evac":
			enabled = not bool(done_actions.get("evac", false))
			reason = "" if enabled else "already_done"
		elif a == "window_end":
			enabled = true
		elif choice != "accept":
			reason = "requires_accept"
		else:
			enabled = not bool(done_actions.get(a, false))
			reason = "" if enabled else "already_done"
		out.append({"action": a, "enabled": enabled, "done": bool(done_actions.get(a, false)),
			"reason": reason})
	return out

# ── note ────────────────────────────────────────────────────────

func note(text_key: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: ChronosChain 未 ready")
	if not texts.has(text_key):
		return _fail("unknown_text_key", "precondition: 未知 text_key：" + text_key)
	_note_seq += 1
	var row := {"schema": "chronos_chain_note.v1", "seq": _note_seq,
		"text_key": text_key, "zh": str((texts[text_key] as Dictionary).get("zh", "")),
		"source_lines": ((texts[text_key] as Dictionary).get("source_lines", []) as Array).duplicate(),
		"state": state, "opts": opts.duplicate(true) if opts is Dictionary else {}}
	notes.append(row)
	return {"ok": true, "text_key": text_key, "text": str(row["zh"])}

# ── 状态机 ──────────────────────────────────────────────────────

func advance(action: String, payload := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: ChronosChain 未 ready")
	var p: Dictionary = payload if payload is Dictionary else {}
	var allowed: Array = ACTIONS_BY_STATE.get(state, []) as Array
	if state == "ACTIONS":
		allowed = available_actions()
		if not (action in allowed):
			if action in ["blackbox", "telemetry", "evidence"] and choice != "accept":
				return _fail("requires_accept", "precondition: 未接受副官建议，行动未解锁")
			if bool(done_actions.get(action, false)):
				return _fail("already_done", "precondition: 行动已完成：" + action)
			return _fail("invalid_transition", "precondition: 状态 %s 不允许动作 %s" % [state, action])
	elif not (action in allowed):
		return _fail("invalid_transition",
			"precondition: 状态 %s 不允许动作 %s" % [state, action])
	var from := state
	var trigger := ""
	var rep_delta: Dictionary = {}
	var trust_delta := 0
	match action:
		"port_comm":
			state = "PORT_COMM"
			flags["port_comm_received"] = true
			flags["port_rdo"] = true
			trigger = str(triggers_cfg.get("port_comm", "chronos_port_comm"))
			_add_evidence("port_comm", "chronos.port_rdo", p)
		"action_evac":
			state = "ACTION_EVAC"
			flags["evac_option"] = true
			flags["action_menu_open"] = true
			_add_evidence("evac_option", "chronos.evac_option", p)
		"private_comm":
			state = "PRIVATE_COMM"
			flags["private_comm"] = true
			trigger = str(triggers_cfg.get("private_comm", "chronos_private_comm"))
			_add_evidence("private_comm", "chronos.private_comm", p)
		"choose_accept":
			state = "CHOICE"
			choice = "accept"
			flags["choice"] = "accept"
			flags["accepted"] = true
			flags["blackbox_unlocked"] = true
			flags["telemetry_unlocked"] = true
			flags["evidence_unlocked"] = true
			flags["future_suggestion_allowed"] = true
			trust_delta = int(trust_cfg.get("accept", 2))
			rep_delta = (reputation_cfg.get("accept", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("accept", "chronos_accept"))
			_add_evidence("choice_accept", "chronos.accept", p)
		"choose_reject":
			state = "CHOICE"
			choice = "reject"
			flags["choice"] = "reject"
			flags["rejected"] = true
			flags["blackbox_unlocked"] = false
			flags["telemetry_unlocked"] = false
			flags["evidence_unlocked"] = false
			flags["future_suggestion_allowed"] = true
			trust_delta = int(trust_cfg.get("reject", -1))
			rep_delta = (reputation_cfg.get("reject", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("reject", "chronos_reject"))
			_add_evidence("choice_reject", "chronos.reject", p)
		"open_actions":
			state = "ACTIONS"
			flags["actions_state"] = true
			flags["window_open"] = true
			_add_evidence("open_actions", "chronos.actions_menu", p)
		"evac":
			done_actions["evac"] = true
			flags["evac_done"] = true
			rep_delta = (reputation_cfg.get("evac", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("evac", "chronos_evac"))
			_add_evidence("evac", "chronos.evac_option", p)
		"blackbox":
			done_actions["blackbox"] = true
			flags["blackbox_done"] = true
			flags["evidence_blackbox"] = true
			trust_delta = int(trust_cfg.get("blackbox", 1))
			rep_delta = (reputation_cfg.get("blackbox", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("blackbox", "chronos_blackbox"))
			_add_evidence("blackbox", "chronos.private_comm", p)
		"telemetry":
			done_actions["telemetry"] = true
			flags["telemetry_done"] = true
			trust_delta = int(trust_cfg.get("telemetry", 1))
			rep_delta = (reputation_cfg.get("telemetry", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("telemetry", "chronos_telemetry"))
			_add_evidence("telemetry", "chronos.private_comm", p)
		"evidence":
			done_actions["evidence"] = true
			flags["evidence_done"] = true
			flags["evidence_optional"] = true
			rep_delta = (reputation_cfg.get("evidence", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("evidence", "chronos_evidence"))
			_add_evidence("evidence_optional", "chronos.private_comm", p)
		"window_end":
			state = "WINDOW_END"
			flags["window_ended"] = true
			flags["handoff_4412"] = true
			rep_delta = (reputation_cfg.get("window_end", {}) as Dictionary).duplicate(true)
			trigger = str(triggers_cfg.get("window_end", "chronos_window_end"))
			_add_evidence("window_end", "chronos.window_teaching", p)
		"complete":
			state = "COMPLETE"
			flags["complete"] = true
			trigger = str(triggers_cfg.get("complete", "chronos_complete"))
			_add_evidence("complete", "", p)
	if trust_delta != 0:
		trust += trust_delta
	_apply_reputation(rep_delta)
	if trigger != "":
		emitted_triggers.append({"trigger_id": trigger, "state": state,
			"choice": choice, "trust": trust})
	_emit_event(action, from, state, trigger, rep_delta, trust_delta)
	return {"ok": true, "action": action, "from_state": from, "state": state,
		"choice": choice, "trust": trust, "trigger_id": trigger,
		"flags": flags.duplicate(true),
		"evidence": evidence.back().duplicate(true) if not evidence.is_empty() else {},
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true)}

func _add_evidence(kind: String, text_key: String, payload: Dictionary) -> void:
	_evidence_seq += 1
	evidence.append({"schema": "chronos_chain_evidence.v1", "seq": _evidence_seq,
		"kind": kind, "text_key": text_key, "entity_id": entity_id,
		"state": state, "payload": payload.duplicate(true),
		"source": "chronos_chain"})

func _apply_reputation(delta: Dictionary) -> void:
	for k in delta.keys():
		reputation[str(k)] = int(reputation.get(str(k), 0)) + int(delta[k])

func _emit_event(action: String, from: String, to: String, trigger: String,
		rep_delta: Dictionary, trust_delta: int) -> void:
	_event_seq += 1
	events.append({"schema": EVENT_SCHEMA, "seq": _event_seq,
		"kind": "transition", "action": action, "from": from, "to": to,
		"trigger_id": trigger, "state": to, "choice": choice, "trust": trust,
		"trust_delta": trust_delta, "flags": flags.duplicate(true),
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true), "writes_v15": false})

# ── VM / save ──────────────────────────────────────────────────

func vm() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "states": STATES.duplicate(),
		"actions": available_actions(), "action_details": action_details(),
		"choice": choice, "trust": trust, "trust_state": trust_state(),
		"flags": flags.duplicate(true), "done_actions": done_actions.duplicate(true),
		"evidence": evidence.duplicate(true), "events": events.duplicate(true),
		"notes": notes.duplicate(true), "triggers": emitted_triggers.duplicate(true),
		"trigger_ids": trigger_ids(), "reputation": reputation.duplicate(true),
		"text_keys": text_keys.duplicate(),
		"writes": {"world": false, "ui": false, "v15": false, "ceres_chain": false}}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "choice": choice, "trust": trust,
		"trust_state": trust_state(), "complete": is_complete(),
		"events": events.size(), "evidence": evidence.size(),
		"triggers": trigger_ids(), "reputation": reputation.duplicate(true),
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"content_path": content_path, "state": state, "choice": choice,
		"trust": trust, "flags": flags.duplicate(true),
		"evidence": JSON.parse_string(JSON.stringify(evidence)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"notes": JSON.parse_string(JSON.stringify(notes)),
		"triggers": JSON.parse_string(JSON.stringify(emitted_triggers)),
		"reputation": reputation.duplicate(true),
		"done_actions": JSON.parse_string(JSON.stringify(done_actions)),
		"seq": {"event": _event_seq, "evidence": _evidence_seq, "note": _note_seq}})

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
	var st := str(d.get("state", ""))
	if not (st in STATES):
		return _fail("invalid_payload", "load: state 非法")
	var ch := str(d.get("choice", ""))
	if not (ch in ["", "accept", "reject"]):
		return _fail("invalid_payload", "load: choice 非法")
	var f = d.get("flags", null)
	if not (f is Dictionary):
		return _fail("invalid_payload", "load: flags 非法")
	var ev = d.get("evidence", null)
	if not (ev is Array):
		return _fail("invalid_payload", "load: evidence 非法")
	var evs = d.get("events", null)
	if not (evs is Array):
		return _fail("invalid_payload", "load: events 非法")
	state = st
	choice = ch
	trust = int(d.get("trust", 0))
	flags = (f as Dictionary).duplicate(true)
	evidence = (ev as Array).duplicate(true)
	events = (evs as Array).duplicate(true)
	notes = (d.get("notes", []) as Array).duplicate(true) if d.get("notes") is Array else []
	emitted_triggers = (d.get("triggers", []) as Array).duplicate(true) \
		if d.get("triggers") is Array else []
	reputation = (d.get("reputation", {}) as Dictionary).duplicate(true) \
		if d.get("reputation") is Dictionary else {}
	done_actions = (d.get("done_actions", {}) as Dictionary).duplicate(true) \
		if d.get("done_actions") is Dictionary else {}
	var seq: Dictionary = d.get("seq", {}) if d.get("seq") is Dictionary else {}
	_event_seq = int(seq.get("event", events.size()))
	_evidence_seq = int(seq.get("evidence", evidence.size()))
	_note_seq = int(seq.get("note", notes.size()))
	_check_contracts()
	return {"ok": true, "state": state, "choice": choice, "trust": trust}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("chain 未 ready")
	if not (state in STATES):
		v.append("state 非法")
	if choice == "reject" and not bool(flags.get("future_suggestion_allowed", false)):
		v.append("reject 应保留后续再建议")
	if state == "ACTIONS" and choice == "":
		v.append("ACTIONS 但无接受/拒绝选择")
	if state == "COMPLETE" and not bool(flags.get("complete", false)):
		v.append("COMPLETE 但 complete flag 缺失")
	if is_complete() and not bool(flags.get("handoff_4412", false)):
		v.append("COMPLETE 但未 handoff 4412")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("ChronosChain 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
