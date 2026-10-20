extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3U：CeresChain（谷神-2 识别/救援链；新文件）
#
# 状态机（手动 advance，不自动完成）：
#   L1 → L2 → L3 → LIGHT_READ → L4_TYPE → RESCUE_PROMPT
#     → RESCUED / IGNORED → COMPLETE
# - 输入解耦：只接受证据/等级/文本 key（ingest）；不依赖
#   TrackTable/transponder/signal，不写 world/UI；
# - 输出 events/flags/evidence/reputation；
# - 文本从 docs/44 原样抽取（本内容 story_ceres.json），不改写；
# - 触发：ceres_light_read / ceres_rescue_prompt / ceres_rescued /
#   ceres_ignored（及 complete）。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.ceres_chain.v1"
const SAVE_SCHEMA := "v17.ceres_chain_save.v1"
const CONTENT_SCHEMA := "v17.story_ceres.v1"
const EVENT_SCHEMA := "ceres_chain_event.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/story_ceres.json"
const STATES := ["L1", "L2", "L3", "LIGHT_READ", "L4_TYPE", "RESCUE_PROMPT",
	"RESCUED", "IGNORED", "COMPLETE"]
const ACTIONS := {
	"L1": ["data_link_l2"],
	"L2": ["identify_l3"],
	"L3": ["read_light"],
	"LIGHT_READ": ["classify_l4"],
	"L4_TYPE": ["rescue_prompt"],
	"RESCUE_PROMPT": ["rescue", "ignore"],
	"RESCUED": ["complete"],
	"IGNORED": ["complete"],
	"COMPLETE": [],
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var source_path := ""
var entity_id := "ceres_2"
var emergency_light_code := ""
var triggers_cfg: Dictionary = {}
var reputation_cfg: Dictionary = {}
var texts: Dictionary = {}
var text_keys: Array = []

var state := "L1"
var flags: Dictionary = {}
var evidence: Array = []
var events: Array = []
var notes: Array = []
var emitted_triggers: Array = []
var chosen := ""
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
		errors.append("谷神链内容不可读：" + content_path)
		return false
	var v: Dictionary = validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("ceres: " + str(e))
		return false
	_apply_content(content)
	_reset_runtime()
	ready = true
	return true

func _apply_content(d: Dictionary) -> void:
	content = d.duplicate(true)
	source_path = str(d.get("source_path", ""))
	entity_id = str(d.get("entity_id", "ceres_2"))
	emergency_light_code = str(d.get("emergency_light_code", ""))
	triggers_cfg = (d.get("triggers", {}) as Dictionary).duplicate(true)
	reputation_cfg = (d.get("reputation", {}) as Dictionary).duplicate(true)
	texts = {}
	text_keys = []
	for raw in (d.get("texts", []) as Array):
		if raw is Dictionary:
			var t: Dictionary = (raw as Dictionary).duplicate(true)
			var key := str(t.get("text_key", ""))
			texts[key] = t
			text_keys.append(key)
	text_keys.sort()

func _reset_runtime() -> void:
	state = "L1"
	flags = {}
	evidence = []
	events = []
	notes = []
	emitted_triggers = []
	chosen = ""
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
	if str(d.get("emergency_light_code", "")).length() != 4:
		errs.append("emergency_light_code 必须四位")
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
		for k in ["light_read", "rescue_prompt", "rescued", "ignored"]:
			if str((tr as Dictionary).get(k, "")) == "":
				errs.append("triggers.%s 为空" % k)
	var rep = d.get("reputation", null)
	if rep is Dictionary:
		for choice in ["rescue", "ignore"]:
			if not ((rep as Dictionary).get(choice) is Dictionary):
				errs.append("reputation.%s 必须是对象" % choice)
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

func actions() -> Array:
	return (ACTIONS.get(state, []) as Array).duplicate()

func available_actions() -> Array:
	return actions()

func can_advance(action: String) -> bool:
	return action in (ACTIONS.get(state, []) as Array)

func is_complete() -> bool:
	return state == "COMPLETE"

func chosen_action() -> String:
	return chosen

func text_keys_list() -> Array:
	return text_keys.duplicate()

func text(text_key: String) -> Dictionary:
	return (texts.get(text_key, {}) as Dictionary).duplicate(true)

func get_flag(key: String) -> Variant:
	return flags.get(key, null)

func get_flags() -> Dictionary:
	return flags.duplicate(true)

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

# ── 手动输入：证据 / 等级 / 文本 key ───────────────────────────

## 输入与 TrackTable/transponder/signal 解耦的通用证据/等级/文本 key。
## input: {kind,source,level,text_key,data_link,sensor_sources,light_code,...}
func ingest(input: Dictionary) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: CeresChain 未 ready")
	if not (input is Dictionary) or input.is_empty():
		return _fail("invalid_input", "precondition: input 必须为非空对象")
	var kind := str(input.get("kind", "evidence"))
	if kind == "text":
		var key := str(input.get("text_key", ""))
		if not texts.has(key):
			return _fail("unknown_text_key", "precondition: 未知 text_key：" + key)
		_evidence_seq += 1
		var tev := {"schema": "ceres_chain_evidence.v1", "seq": _evidence_seq,
			"kind": "text", "text_key": key, "source": "text_library",
			"entity_id": entity_id}
		evidence.append(tev)
		return {"ok": true, "evidence": tev.duplicate(true)}
	if kind == "level":
		var lvl := str(input.get("level", ""))
		if not (lvl in ["L1", "L2", "L3", "L4"]):
			return _fail("invalid_level", "precondition: level 非法：" + lvl)
		_evidence_seq += 1
		var lev := {"schema": "ceres_chain_evidence.v1", "seq": _evidence_seq,
			"kind": "level", "level": lvl,
			"source": str(input.get("source", "manual")),
			"entity_id": entity_id,
			"identity": str(input.get("identity", "unknown"))}
		evidence.append(lev)
		return {"ok": true, "evidence": lev.duplicate(true)}
	# 通用证据
	var ev := {"schema": "ceres_chain_evidence.v1", "seq": _evidence_seq + 1,
		"kind": kind, "source": str(input.get("source", "manual")),
		"level": str(input.get("level", "")),
		"identity": str(input.get("identity", "unknown")),
		"data_link": bool(input.get("data_link", false)),
		"sensor_sources": int(input.get("sensor_sources", 0)),
		"light_code": str(input.get("light_code", "")),
		"entity_id": entity_id}
	if kind == "sensor":
		var sens := int(input.get("sensors", 1))
		ev["sensors"] = maxi(0, sens)
	_evidence_seq += 1
	ev["seq"] = _evidence_seq
	evidence.append(ev)
	return {"ok": true, "evidence": ev.duplicate(true)}

## 记录玩家查看的文本 key（不改变状态，不自动完成）。
func note(text_key: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: CeresChain 未 ready")
	if not texts.has(text_key):
		return _fail("unknown_text_key", "precondition: 未知 text_key：" + text_key)
	_note_seq += 1
	var row := {"schema": "ceres_chain_note.v1", "seq": _note_seq,
		"text_key": text_key, "zh": str((texts[text_key] as Dictionary).get("zh", "")),
		"source_lines": ((texts[text_key] as Dictionary).get("source_lines", []) as Array).duplicate(),
		"state": state, "opts": opts.duplicate(true) if opts is Dictionary else {}}
	notes.append(row)
	return {"ok": true, "text_key": text_key, "text": str(row["zh"]),
		"source_lines": row["source_lines"].duplicate()}

# ── 状态机 ──────────────────────────────────────────────────────

## 手动推进：每次只走一步；不自动完成；失败不改状态。
func advance(action: String, payload := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: CeresChain 未 ready")
	var p: Dictionary = payload if payload is Dictionary else {}
	if not (action in (ACTIONS.get(state, []) as Array)):
		return _fail("invalid_transition",
			"precondition: 状态 %s 不允许动作 %s" % [state, action])
	# 各动作前置校验（全部通过后才写入）
	match action:
		"data_link_l2":
			if not _l2_ready(p):
				return _fail("missing_data_link",
					"precondition: L2 需要数据链/多传感器定位证据")
		"identify_l3":
			if not _l3_ready(p):
				return _fail("missing_evidence",
					"precondition: L3 需要 L2 证据/识别输入")
		"read_light":
			var code := str(p.get("light_code", ""))
			if code == "":
				return _fail("missing_light_code", "precondition: 缺少可见光代码")
			if code != emergency_light_code:
				return _fail("wrong_light_code",
					"precondition: 可见光代码不匹配：%s" % code)
		"classify_l4":
			if not bool(flags.get("light_read", false)):
				return _fail("missing_light_read", "precondition: L4 需先读取可见光灯语")
		"rescue":
			if chosen != "":
				return _fail("already_chosen", "precondition: 救援选项已选择")
		"ignore":
			if chosen != "":
				return _fail("already_chosen", "precondition: 救援选项已选择")
		"complete":
			if chosen == "":
				return _fail("rescue_not_chosen", "precondition: 尚未选择救援/忽略")
	var from := state
	var trigger := ""
	var rep_delta: Dictionary = {}
	match action:
		"data_link_l2":
			state = "L2"
			flags["data_link_l2"] = true
			flags["l2_data_link"] = true
			_add_evidence("data_link_l2", 2, "data_link", p)
		"identify_l3":
			state = "L3"
			flags["l3_identified"] = true
			_add_evidence("l3_identification", 3, "identification", p)
		"read_light":
			state = "LIGHT_READ"
			flags["light_read"] = true
			trigger = str(triggers_cfg.get("light_read", "ceres_light_read"))
			_add_evidence("light_read", 3, "visible_light", p)
		"classify_l4":
			state = "L4_TYPE"
			flags["type_identified"] = true
			flags["l4_type"] = "ceres_2"
			_add_evidence("type_identified", 4, "visible_light", p)
		"rescue_prompt":
			state = "RESCUE_PROMPT"
			flags["rescue_prompted"] = true
			trigger = str(triggers_cfg.get("rescue_prompt", "ceres_rescue_prompt"))
			_add_evidence("rescue_prompt", 4, "prompt", p)
		"rescue":
			state = "RESCUED"
			chosen = "rescue"
			flags["rescue_chosen"] = true
			flags["rescued"] = true
			rep_delta = (reputation_cfg.get("rescue", {}) as Dictionary).duplicate(true)
			_apply_reputation(rep_delta)
			trigger = str(triggers_cfg.get("rescued", "ceres_rescued"))
			_add_evidence("rescued", 4, "command", p)
		"ignore":
			state = "IGNORED"
			chosen = "ignore"
			flags["ignore_chosen"] = true
			flags["ignored"] = true
			rep_delta = (reputation_cfg.get("ignore", {}) as Dictionary).duplicate(true)
			_apply_reputation(rep_delta)
			trigger = str(triggers_cfg.get("ignored", "ceres_ignored"))
			_add_evidence("ignored", 4, "command", p)
		"complete":
			state = "COMPLETE"
			flags["complete"] = true
			trigger = str(triggers_cfg.get("complete", "ceres_complete"))
	if trigger != "":
		emitted_triggers.append({"trigger_id": trigger, "state": state,
			"chosen": chosen})
	_emit_event(action, from, state, trigger, rep_delta)
	return {"ok": true, "action": action, "from_state": from,
		"state": state, "trigger_id": trigger,
		"flags": flags.duplicate(true),
		"evidence": evidence.back().duplicate(true) if not evidence.is_empty() else {},
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true)}

func _l2_ready(p: Dictionary) -> bool:
	if bool(p.get("data_link", false)) and int(p.get("sensor_sources", 0)) >= 2:
		return true
	var sensors := 0
	var dl := false
	for raw in evidence:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if bool(e.get("data_link", false)) or str(e.get("kind", "")) == "data_link":
			dl = true
		if str(e.get("kind", "")) == "sensor":
			sensors += maxi(1, int(e.get("sensors", 1)))
		if str(e.get("source", "")) in ["radar", "ir", "elint", "sensor"]:
			sensors += 1
	return dl and sensors >= 2

func _l3_ready(p: Dictionary) -> bool:
	var level := str(p.get("level", ""))
	if level in ["L2", "L3", "L4"]:
		return true
	if int(p.get("sensor_sources", 0)) >= 1 and bool(p.get("identification", true)):
		return true
	for raw in evidence:
		if raw is Dictionary:
			var e: Dictionary = raw
			var lv = e.get("level", "")
			if str(lv) in ["L2", "L3", "L4"]:
				return true
			if (lv is int or lv is float) and int(float(lv)) >= 2:
				return true
			if str(e.get("kind", "")) in ["l3_identification", "identification", "vis", "elint"]:
				return true
	return false

func _add_evidence(kind: String, level: int, source: String, payload: Dictionary) -> void:
	_evidence_seq += 1
	evidence.append({"schema": "ceres_chain_evidence.v1", "seq": _evidence_seq,
		"kind": kind, "level": level, "source": source, "entity_id": entity_id,
		"payload": payload.duplicate(true)})

func _apply_reputation(delta: Dictionary) -> void:
	for k in delta.keys():
		reputation[str(k)] = int(reputation.get(str(k), 0)) + int(delta[k])

func _emit_event(action: String, from: String, to: String, trigger: String,
		rep_delta: Dictionary) -> void:
	_event_seq += 1
	events.append({"schema": EVENT_SCHEMA, "seq": _event_seq,
		"kind": "transition", "action": action, "from": from, "to": to,
		"trigger_id": trigger, "state": to, "chosen": chosen,
		"flags": flags.duplicate(true),
		"reputation_delta": rep_delta.duplicate(true),
		"reputation": reputation.duplicate(true),
		"writes_v15": false})

# ── VM / summary / save ─────────────────────────────────────────

func vm() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "states": STATES.duplicate(), "actions": actions(),
		"can_complete": state in ["RESCUED", "IGNORED"],
		"chosen": chosen, "flags": flags.duplicate(true),
		"evidence": evidence.duplicate(true), "events": events.duplicate(true),
		"notes": notes.duplicate(true), "triggers": emitted_triggers.duplicate(true),
		"trigger_ids": trigger_ids(), "reputation": reputation.duplicate(true),
		"text_keys": text_keys.duplicate(),
		"writes": {"world": false, "track_table": false, "ui": false, "v15": false}}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "entity_id": entity_id,
		"state": state, "chosen": chosen, "complete": is_complete(),
		"events": events.size(), "evidence": evidence.size(),
		"triggers": trigger_ids(), "reputation": reputation.duplicate(true),
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"content_path": content_path, "state": state, "flags": flags.duplicate(true),
		"evidence": JSON.parse_string(JSON.stringify(evidence)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"notes": JSON.parse_string(JSON.stringify(notes)),
		"triggers": JSON.parse_string(JSON.stringify(emitted_triggers)),
		"chosen": chosen, "reputation": reputation.duplicate(true),
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
	var f = d.get("flags", null)
	if not (f is Dictionary):
		return _fail("invalid_payload", "load: flags 非法")
	var ev = d.get("evidence", null)
	if not (ev is Array):
		return _fail("invalid_payload", "load: evidence 非法")
	var evs = d.get("events", null)
	if not (evs is Array):
		return _fail("invalid_payload", "load: events 非法")
	var chosen_v := str(d.get("chosen", ""))
	if not (chosen_v in ["", "rescue", "ignore"]):
		return _fail("invalid_payload", "load: chosen 非法")
	state = st
	flags = (f as Dictionary).duplicate(true)
	evidence = (ev as Array).duplicate(true)
	events = (evs as Array).duplicate(true)
	notes = (d.get("notes", []) as Array).duplicate(true) if d.get("notes") is Array else []
	emitted_triggers = (d.get("triggers", []) as Array).duplicate(true) \
		if d.get("triggers") is Array else []
	chosen = chosen_v
	reputation = (d.get("reputation", {}) as Dictionary).duplicate(true) \
		if d.get("reputation") is Dictionary else {}
	var seq: Dictionary = d.get("seq", {}) if d.get("seq") is Dictionary else {}
	_event_seq = int(seq.get("event", events.size()))
	_evidence_seq = int(seq.get("evidence", evidence.size()))
	_note_seq = int(seq.get("note", notes.size()))
	_check_contracts()
	return {"ok": true, "state": state, "chosen": chosen}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("chain 未 ready")
	if not (state in STATES):
		v.append("state 非法")
	if state == "COMPLETE" and chosen == "":
		v.append("COMPLETE 但未选择救援/忽略")
	if chosen == "rescue" and not bool(flags.get("rescued", false)):
		v.append("chosen=rescue 但 rescued flag 缺失")
	if chosen == "ignore" and not bool(flags.get("ignored", false)):
		v.append("chosen=ignore 但 ignored flag 缺失")
	if state in ["RESCUED", "IGNORED"] and chosen == "":
		v.append("结束路径未记录 chosen")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("CeresChain 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
