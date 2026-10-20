extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3W：Av4412Chain（AV-4412 轨道/窗口/对峙/谈判链；新文件）
#
# 状态机（手动 advance，不自动开火）：
#   ORBIT_DEPARTURE → WINDOW_OPEN → EARLY_RADAR / PASSIVE_CONTACT
#     → COMMS → NEGOTIATION → STRONG/STANDARD/QUESTION/RETREAT
#     → RESOLUTION → REPORT_HANDOFF
# - 真实轨道输入：update_orbit(av4412_track:{t,pos,vel,window_open,radar_active})
#   输出 detected/window_closed；不伪造轨道；不自动推进；
# - 窗口期结束/提前雷达二选一；谈判四选一（退让需副官多次劝阻）；
# - 强硬：roe_tight + fire_control_illumination 事件（不自动开火）；
#   质疑：证据/上级叫停；标准：威胁；退让：劝阻计数/死亡结局标记；
# - 输出 flags/evidence/threat/reputation/trust/triggers；不写 world/UI；
# - 文本从 docs/44 原样抽取；缺失文本用 TBD key，不伪造。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.av4412_chain.v1"
const SAVE_SCHEMA := "v17.av4412_chain_save.v1"
const CONTENT_SCHEMA := "v17.story_av4412.v1"
const EVENT_SCHEMA := "av4412_chain_event.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/story_av4412.json"
const STATES := ["ORBIT_DEPARTURE", "WINDOW_OPEN", "EARLY_RADAR",
	"PASSIVE_CONTACT", "COMMS", "NEGOTIATION", "STRONG", "STANDARD",
	"QUESTION", "RETREAT", "RESOLUTION", "REPORT_HANDOFF"]
const CONTACT_STATES := ["EARLY_RADAR", "PASSIVE_CONTACT", "COMMS",
	"NEGOTIATION", "STRONG", "STANDARD", "QUESTION", "RETREAT",
	"RESOLUTION", "REPORT_HANDOFF"]
const HANDOFF_STATE := "REPORT_HANDOFF"

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var source_path := ""
var entity_id := "av_4412"
var triggers_cfg: Dictionary = {}
var options_cfg: Array = []
var threat_cfg: Dictionary = {}
var trust_cfg: Dictionary = {}
var reputation_cfg: Dictionary = {}
var retreat_required_warnings := 3
var texts: Dictionary = {}
var text_keys: Array = []

var state := "ORBIT_DEPARTURE"
var orbit: Dictionary = {}
var window_open := false
var radar_active := false
var contact_mode := ""
var chosen_option := ""
var resolution := ""
var retreat_warnings := 0
var threat := 0
var trust := 0
var flags: Dictionary = {}
var evidence: Array = []
var events: Array = []
var notes: Array = []
var emitted_triggers: Array = []
var reputation: Dictionary = {}
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
		errors.append("AV-4412 链内容不可读：" + content_path)
		return false
	var v: Dictionary = validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("av4412: " + str(e))
		return false
	_apply_content(content)
	_reset_runtime()
	ready = true
	return true

func _apply_content(d: Dictionary) -> void:
	content = d.duplicate(true)
	source_path = str(d.get("source_path", ""))
	entity_id = str(d.get("entity_id", "av_4412"))
	triggers_cfg = (d.get("triggers", {}) as Dictionary).duplicate(true)
	options_cfg = (d.get("options", []) as Array).duplicate()
	threat_cfg = (d.get("threat", {}) as Dictionary).duplicate(true)
	trust_cfg = (d.get("trust", {}) as Dictionary).duplicate(true)
	reputation_cfg = (d.get("reputation", {}) as Dictionary).duplicate(true)
	retreat_required_warnings = maxi(1, int(d.get("retreat_required_warnings", 3)))
	texts = {}
	text_keys = []
	for raw in (d.get("texts", []) as Array):
		if raw is Dictionary:
			var t: Dictionary = (raw as Dictionary).duplicate(true)
			texts[str(t.get("text_key", ""))] = t
			text_keys.append(str(t.get("text_key", "")))
	text_keys.sort()

func _reset_runtime() -> void:
	state = "ORBIT_DEPARTURE"
	orbit = {}
	window_open = false
	radar_active = false
	contact_mode = ""
	chosen_option = ""
	resolution = ""
	retreat_warnings = 0
	threat = 0
	trust = 0
	flags = {}
	evidence = []
	events = []
	notes = []
	emitted_triggers = []
	reputation = {}
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
	var opts = d.get("options", null)
	if not (opts is Array) or (opts as Array).size() != 4:
		errs.append("options 必须为 4 项")
	else:
		for o in ["strong", "standard", "question", "retreat"]:
			if not (str(o) in (opts as Array)):
				errs.append("options 缺 " + str(o))
	if int(d.get("retreat_required_warnings", 0)) < 1:
		errs.append("retreat_required_warnings 必须 >=1")
	for k in ["threat", "trust", "reputation", "triggers"]:
		if not (d.get(k) is Dictionary):
			errs.append(k + " 必须是对象")
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
			if not (sl is Array):
				errs.append("text %s source_lines 必须是数组" % key)
			elif not bool(t.get("tbd", false)):
				if (sl as Array).is_empty():
					errs.append("text %s 非 TBD 需 source_lines" % key)
				for n in (sl as Array):
					if not (n is int or n is float) or int(float(n)) <= 0:
						errs.append("text %s source_lines 非法" % key)
			if bool(t.get("tbd", false)) and str(t.get("zh", "")) != "TBD":
				errs.append("text %s TBD 必须 zh=TBD（不伪造）" % key)
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
	return state == HANDOFF_STATE

func contact() -> String:
	return contact_mode

func chosen() -> String:
	return chosen_option

func get_resolution() -> String:
	return resolution

func get_threat() -> int:
	return threat

func get_trust() -> int:
	return trust

func get_retreat_warnings() -> int:
	return retreat_warnings

func get_orbit_track() -> Dictionary:
	return orbit.duplicate(true)

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

## 当前检测/窗口闭合状态（来自真实轨道输入/已发生接触，不伪造）。
func detection_status() -> Dictionary:
	var detected := bool(radar_active) or (state in CONTACT_STATES)
	var window_closed := bool(orbit.get("window_open", false)) == false \
		or contact_mode != "" or state == "EARLY_RADAR" or state == "PASSIVE_CONTACT"
	return {"detected": detected, "window_closed": window_closed,
		"contact": contact_mode, "radar_active": radar_active,
		"window_open": window_open}

## 接受真实轨道输入（不自动推进；不产生假轨道/假检测）。
func update_orbit(track: Variant) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: Av4412Chain 未 ready")
	if not (track is Dictionary):
		return _fail("invalid_track", "precondition: av4412_track 必须是对象")
	var tr: Dictionary = track
	if not (tr.get("t") is int or tr.get("t") is float) or \
			not is_finite(float(tr.get("t", NAN))):
		return _fail("invalid_track", "precondition: track.t 非法")
	for k in ["pos", "vel"]:
		var arr = tr.get(k, null)
		if not (arr is Array) or (arr as Array).size() != 3:
			return _fail("invalid_track", "precondition: track.%s 必须三维数组" % k)
		for x in (arr as Array):
			if not (x is int or x is float) or not is_finite(float(x)):
				return _fail("invalid_track", "precondition: track.%s 非有限" % k)
	if not (tr.get("window_open") is bool):
		return _fail("invalid_track", "precondition: track.window_open 必须是 bool")
	if not (tr.get("radar_active") is bool):
		return _fail("invalid_track", "precondition: track.radar_active 必须是 bool")
	orbit = {"t": float(tr.get("t", 0.0)),
		"pos": (tr.get("pos") as Array).duplicate(),
		"vel": (tr.get("vel") as Array).duplicate(),
		"window_open": bool(tr.get("window_open", false)),
		"radar_active": bool(tr.get("radar_active", false))}
	window_open = bool(orbit["window_open"])
	radar_active = bool(orbit["radar_active"])
	_add_evidence("orbit_track", "", {"t": orbit["t"],
		"pos": (orbit["pos"] as Array).duplicate(),
		"window_open": window_open, "radar_active": radar_active})
	var ds := detection_status()
	return {"ok": true, "track": orbit.duplicate(true),
		"detected": bool(ds.get("detected", false)),
		"window_closed": bool(ds.get("window_closed", false)),
		"state": state, "writes_v15": false}

# ── note ────────────────────────────────────────────────────────

func note(text_key: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: Av4412Chain 未 ready")
	if not texts.has(text_key):
		return _fail("unknown_text_key", "precondition: 未知 text_key：" + text_key)
	_note_seq += 1
	var row := {"schema": "av4412_chain_note.v1", "seq": _note_seq,
		"text_key": text_key, "zh": str((texts[text_key] as Dictionary).get("zh", "")),
		"tbd": bool((texts[text_key] as Dictionary).get("tbd", false)),
		"source_lines": ((texts[text_key] as Dictionary).get("source_lines", []) as Array).duplicate(),
		"state": state, "opts": opts.duplicate(true) if opts is Dictionary else {}}
	notes.append(row)
	return {"ok": true, "text_key": text_key, "text": str(row["zh"]),
		"tbd": bool(row["tbd"])}

# ── 状态机 ──────────────────────────────────────────────────────

func available_actions() -> Array:
	match state:
		"ORBIT_DEPARTURE":
			return ["window_open"]
		"WINDOW_OPEN":
			return ["early_radar", "passive_contact"]
		"EARLY_RADAR", "PASSIVE_CONTACT":
			return ["comms"]
		"COMMS":
			return ["negotiation"]
		"NEGOTIATION":
			var out: Array = ["strong", "standard", "question", "deputy_warn"]
			if retreat_warnings >= retreat_required_warnings:
				out.append("retreat")
			return out
		"STRONG", "STANDARD", "QUESTION", "RETREAT":
			return ["resolve"]
		"RESOLUTION":
			return ["report_handoff"]
		_:
			return []

func can_advance(action: String) -> bool:
	return action in available_actions()

func advance(action: String, payload := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: Av4412Chain 未 ready")
	var p: Dictionary = payload if payload is Dictionary else {}
	if not (action in available_actions()):
		if action == "retreat" and state == "NEGOTIATION":
			return _fail("missing_retreat_warnings",
				"precondition: 退让需副官多次劝阻（%d/%d）" % [retreat_warnings,
					retreat_required_warnings])
		return _fail("invalid_transition",
			"precondition: 状态 %s 不允许动作 %s" % [state, action])
	var from := state
	var trigger := ""
	var rep_delta: Dictionary = {}
	var trust_delta := 0
	var threat_delta := 0
	match action:
		"window_open":
			if orbit.is_empty():
				return _fail("missing_orbit", "precondition: 需要先输入 av4412_track 真实轨道")
			if not bool(orbit.get("window_open", false)):
				return _fail("window_closed", "precondition: 轨道窗口未打开")
			state = "WINDOW_OPEN"
			flags["window_open"] = true
			_add_evidence("window_open", "av4412.contact_rules", p)
		"early_radar":
			if not bool(radar_active):
				return _fail("radar_inactive", "precondition: 未开启雷达，不能提前接触")
			state = "EARLY_RADAR"
			contact_mode = "early_radar"
			flags["early_radar"] = true
			flags["window_closed_early"] = true
			flags["detected"] = true
			trigger = str(triggers_cfg.get("early_radar", "av4412_early_radar"))
			_add_evidence("early_radar", "av4412.contact_rules", p)
		"passive_contact":
			if bool(radar_active):
				return _fail("radar_active_mutually_exclusive",
					"precondition: 雷达已开启，提前雷达与被动接触互斥")
			state = "PASSIVE_CONTACT"
			contact_mode = "passive"
			flags["passive_contact"] = true
			flags["window_closed"] = true
			flags["detected"] = true
			trigger = str(triggers_cfg.get("passive_contact", "av4412_passive_contact"))
			_add_evidence("passive_contact", "av4412.contact_rules", p)
		"comms":
			state = "COMMS"
			flags["comms"] = true
			trigger = str(triggers_cfg.get("comms", "av4412_comms"))
			_add_evidence("comms", "av4412.opening", p)
		"negotiation":
			state = "NEGOTIATION"
			flags["negotiation"] = true
			trigger = str(triggers_cfg.get("negotiation", "av4412_negotiation"))
			_add_evidence("negotiation", "av4412.negotiation_rules", p)
		"deputy_warn":
			if retreat_warnings >= retreat_required_warnings:
				return _fail("already_warned", "precondition: 副官劝阻已到最大次数")
			retreat_warnings += 1
			trust_delta = int(trust_cfg.get("retreat_warning", -1))
			flags["deputy_warn_count"] = retreat_warnings
			flags["deputy_warn_%d" % retreat_warnings] = true
			var warn_key := "av4412.retreat_deputy_warn_%d_tbd" % retreat_warnings
			_add_evidence("deputy_warn", warn_key, {"count": retreat_warnings})
			# 不改变大状态；只累计劝阻
			_apply_trust(trust_delta)
			_emit_event(action, from, state, "", {}, trust_delta, 0,
				{"warning_index": retreat_warnings, "warning_key": warn_key})
			return {"ok": true, "action": action, "from_state": from,
				"state": state, "retreat_warnings": retreat_warnings,
				"trust": trust, "warning_key": warn_key, "tbd": true,
				"flags": flags.duplicate(true),
				"trigger_id": ""}
		"strong":
			state = "STRONG"
			chosen_option = "strong"
			threat_delta = int(threat_cfg.get("strong", 2))
			trust_delta = int(trust_cfg.get("strong", 0))
			rep_delta = (reputation_cfg.get("strong", {}) as Dictionary).duplicate(true)
			flags["roe_tight"] = true
			flags["fire_control_illumination"] = true
			flags["auto_fire"] = false
			flags["av4412_withdraw"] = true
			trigger = str(triggers_cfg.get("strong", "av4412_strong"))
			_add_evidence("strong", "av4412.strong", p)
			_emit_special_event("roe_tight", {"from": from, "action": action})
			_emit_special_event("fire_control_illumination",
				{"from": from, "action": action, "auto_fire": false})
		"standard":
			state = "STANDARD"
			chosen_option = "standard"
			threat_delta = int(threat_cfg.get("standard", 1))
			trust_delta = int(trust_cfg.get("standard", 0))
			rep_delta = (reputation_cfg.get("standard", {}) as Dictionary).duplicate(true)
			flags["av4412_threatened"] = true
			flags["standard_av_reply_tbd"] = true
			trigger = str(triggers_cfg.get("standard", "av4412_standard"))
			_add_evidence("standard", "av4412.standard", p)
		"question":
			state = "QUESTION"
			chosen_option = "question"
			threat_delta = int(threat_cfg.get("question", 0))
			trust_delta = int(trust_cfg.get("question", 1))
			rep_delta = (reputation_cfg.get("question", {}) as Dictionary).duplicate(true)
			flags["evidence_presented"] = true
			flags["superior_recall"] = true
			flags["av4412_recalled"] = true
			flags["question_av_reply_tbd"] = true
			trigger = str(triggers_cfg.get("question", "av4412_question"))
			_add_evidence("question", "av4412.question", p)
		"retreat":
			if retreat_warnings < retreat_required_warnings:
				return _fail("missing_retreat_warnings",
					"precondition: 退让需副官多次劝阻（%d/%d）" % [retreat_warnings,
						retreat_required_warnings])
			state = "RETREAT"
			chosen_option = "retreat"
			threat_delta = int(threat_cfg.get("retreat", -1))
			trust_delta = int(trust_cfg.get("retreat", -3))
			rep_delta = (reputation_cfg.get("retreat", {}) as Dictionary).duplicate(true)
			flags["retreat_chosen"] = true
			flags["death_ending"] = true
			flags["demo_end"] = true
			flags["retreat_once"] = true
			trigger = str(triggers_cfg.get("retreat", "av4412_retreat"))
			_add_evidence("retreat", "av4412.retreat_rules", p)
			var death_trigger := str(triggers_cfg.get("death_ending", "av4412_death_ending"))
			if death_trigger != "":
				emitted_triggers.append({"trigger_id": death_trigger, "state": state,
					"option": chosen_option, "threat": threat, "trust": trust})
			_emit_special_event("death_ending", {"ending": "death", "demo_end": true})
		"resolve":
			state = "RESOLUTION"
			resolution = _resolution_for(chosen_option)
			flags["resolution"] = resolution
			trigger = str(triggers_cfg.get("resolution", "av4412_resolution"))
			_add_evidence("resolution", "", {"resolution": resolution})
		"report_handoff":
			state = "REPORT_HANDOFF"
			flags["report_handoff"] = true
			trigger = str(triggers_cfg.get("report_handoff", "av4412_report_handoff"))
			_add_evidence("report_handoff", "", {})
	threat += threat_delta
	_apply_trust(trust_delta)
	_apply_reputation(rep_delta)
	if trigger != "":
		emitted_triggers.append({"trigger_id": trigger, "state": state,
			"option": chosen_option, "threat": threat, "trust": trust})
	_emit_event(action, from, state, trigger, rep_delta, trust_delta, threat_delta)
	return {"ok": true, "action": action, "from_state": from, "state": state,
		"contact": contact_mode, "option": chosen_option,
		"resolution": resolution, "threat": threat, "trust": trust,
		"retreat_warnings": retreat_warnings, "trigger_id": trigger,
		"flags": flags.duplicate(true),
		"evidence": evidence.back().duplicate(true) if not evidence.is_empty() else {},
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true),
		"auto_fire": false}

func _resolution_for(option: String) -> String:
	match option:
		"strong":
			return "av4412_withdraw"
		"standard":
			return "av4412_threat"
		"question":
			return "av4412_recall"
		"retreat":
			return "death_ending"
	return "unknown"

func _apply_trust(delta: int) -> void:
	if delta != 0:
		trust += delta

func _apply_reputation(delta: Dictionary) -> void:
	for k in delta.keys():
		reputation[str(k)] = int(reputation.get(str(k), 0)) + int(delta[k])

func _add_evidence(kind: String, text_key: String, payload: Dictionary) -> void:
	_evidence_seq += 1
	evidence.append({"schema": "av4412_chain_evidence.v1", "seq": _evidence_seq,
		"kind": kind, "text_key": text_key, "entity_id": entity_id,
		"state": state, "payload": payload.duplicate(true),
		"source": "av4412_chain"})

func _emit_special_event(kind: String, payload: Dictionary) -> void:
	_event_seq += 1
	events.append({"schema": EVENT_SCHEMA, "seq": _event_seq, "kind": kind,
		"state": state, "payload": payload.duplicate(true),
		"writes_v15": false, "auto_fire": false})

func _emit_event(action: String, from: String, to: String, trigger: String,
		rep_delta: Dictionary, trust_delta: int, threat_delta: int,
		extra := {}) -> void:
	_event_seq += 1
	var ev := {"schema": EVENT_SCHEMA, "seq": _event_seq, "kind": "transition",
		"action": action, "from": from, "to": to, "trigger_id": trigger,
		"state": to, "contact": contact_mode, "option": chosen_option,
		"resolution": resolution, "threat": threat, "trust": trust,
		"trust_delta": trust_delta, "threat_delta": threat_delta,
		"flags": flags.duplicate(true),
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true),
		"writes_v15": false, "auto_fire": false}
	for k in extra.keys():
		ev[str(k)] = extra[k]
	events.append(ev)

# ── VM / save ──────────────────────────────────────────────────

func vm() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "states": STATES.duplicate(),
		"actions": available_actions(), "contact": contact_mode,
		"option": chosen_option, "resolution": resolution,
		"retreat_warnings": retreat_warnings,
		"retreat_required_warnings": retreat_required_warnings,
		"threat": threat, "trust": trust, "flags": flags.duplicate(true),
		"orbit": orbit.duplicate(true), "detection": detection_status(),
		"evidence": evidence.duplicate(true), "events": events.duplicate(true),
		"notes": notes.duplicate(true), "triggers": emitted_triggers.duplicate(true),
		"trigger_ids": trigger_ids(), "reputation": reputation.duplicate(true),
		"text_keys": text_keys.duplicate(),
		"writes": {"world": false, "ui": false, "v15": false},
		"auto_fire": false}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "contact": contact_mode, "option": chosen_option,
		"resolution": resolution, "threat": threat, "trust": trust,
		"retreat_warnings": retreat_warnings, "complete": is_complete(),
		"events": events.size(), "evidence": evidence.size(),
		"triggers": trigger_ids(), "reputation": reputation.duplicate(true),
		"auto_fire": false, "writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"content_path": content_path, "state": state, "orbit": orbit.duplicate(true),
		"window_open": window_open, "radar_active": radar_active,
		"contact_mode": contact_mode, "chosen_option": chosen_option,
		"resolution": resolution, "retreat_warnings": retreat_warnings,
		"threat": threat, "trust": trust, "flags": flags.duplicate(true),
		"evidence": JSON.parse_string(JSON.stringify(evidence)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"notes": JSON.parse_string(JSON.stringify(notes)),
		"triggers": JSON.parse_string(JSON.stringify(emitted_triggers)),
		"reputation": reputation.duplicate(true),
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
	var ch := str(d.get("chosen_option", ""))
	if not (ch in ["", "strong", "standard", "question", "retreat"]):
		return _fail("invalid_payload", "load: chosen_option 非法")
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
	chosen_option = ch
	resolution = str(d.get("resolution", ""))
	orbit = (d.get("orbit", {}) as Dictionary).duplicate(true) \
		if d.get("orbit") is Dictionary else {}
	window_open = bool(d.get("window_open", false))
	radar_active = bool(d.get("radar_active", false))
	contact_mode = str(d.get("contact_mode", ""))
	retreat_warnings = int(d.get("retreat_warnings", 0))
	threat = int(d.get("threat", 0))
	trust = int(d.get("trust", 0))
	flags = (f as Dictionary).duplicate(true)
	evidence = (ev as Array).duplicate(true)
	events = (evs as Array).duplicate(true)
	notes = (d.get("notes", []) as Array).duplicate(true) if d.get("notes") is Array else []
	emitted_triggers = (d.get("triggers", []) as Array).duplicate(true) \
		if d.get("triggers") is Array else []
	reputation = (d.get("reputation", {}) as Dictionary).duplicate(true) \
		if d.get("reputation") is Dictionary else {}
	var seq: Dictionary = d.get("seq", {}) if d.get("seq") is Dictionary else {}
	_event_seq = int(seq.get("event", events.size()))
	_evidence_seq = int(seq.get("evidence", evidence.size()))
	_note_seq = int(seq.get("note", notes.size()))
	_check_contracts()
	return {"ok": true, "state": state, "option": chosen_option,
		"contact": contact_mode}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("chain 未 ready")
	if not (state in STATES):
		v.append("state 非法")
	if bool(flags.get("fire_control_illumination", false)) and bool(flags.get("auto_fire", false)):
		v.append("火控照射但 auto_fire=true（禁止自动开火）")
	if state in ["NEGOTIATION", "ORBIT_DEPARTURE", "WINDOW_OPEN"] and chosen_option != "":
		v.append("未谈判但已记录选项")
	if state == "RETREAT" and not bool(flags.get("death_ending", false)):
		v.append("RETREAT 缺 death_ending")
	if state == "REPORT_HANDOFF" and not bool(flags.get("report_handoff", false)):
		v.append("REPORT_HANDOFF 缺 flag")
	if threat < -10 or threat > 10:
		v.append("threat 越界")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("Av4412Chain 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
