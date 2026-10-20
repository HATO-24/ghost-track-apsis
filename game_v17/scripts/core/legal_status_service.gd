extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3X：LegalStatusService（ID13 法律状态机制；新文件）
#
# 状态：UNLISTED → WATCHLIST → RESTRICTED → DESIGNATED_ILLEGAL → HUNTED
#       CLEARED 为极少数（显式 cleared/vindicated 或 set_status；锁定）
# - 触发因素：对清算者强硬/火控照射、公开黑匣子/证据、袭击 UEG/NESOSS、
#   谈判选择、报告、副官信任/政治倾向、AEUG 行为；
# - API：apply_event(trigger,payload) / set_status / tick / vm /
#   save_state / load_state；阈值/权重按配置可调；重复去重；
# - 影响接口（只输出标志，不改 world side/法律文本）：
#   port_access(UEG/共管港) / iff_watch_flag / combat_roe_modifier /
#   ending_branch_hint；
# - 所有变化记录 reason/log，不静默；不写 world/UI/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.legal_status.v1"
const SAVE_SCHEMA := "v17.legal_status_save.v1"
const VERSION := "1.0.0"
const STATES := ["UNLISTED", "WATCHLIST", "RESTRICTED", "DESIGNATED_ILLEGAL",
	"HUNTED", "CLEARED"]
const ESCALATION := ["UNLISTED", "WATCHLIST", "RESTRICTED", "DESIGNATED_ILLEGAL",
	"HUNTED"]
const CLEAR_TRIGGERS := ["cleared", "vindicated", "exonerated"]
const DEFAULT_THRESHOLDS := {"WATCHLIST": 2.0, "RESTRICTED": 4.0,
	"DESIGNATED_ILLEGAL": 7.0, "HUNTED": 10.0}
const DEFAULT_WEIGHTS := {
	"strong": 1.0, "strong_negotiator": 1.0, "negotiation_strong": 1.0,
	"roe_tight": 1.0, "fire_control_illumination": 2.0,
	"blackbox": 2.0, "blackbox_public": 2.0, "blackbox_recovered": 1.0,
	"evidence": 1.0, "evidence_public": 2.0, "evidence_presented": 1.0,
	"attack_ueg": 4.0, "attack_nesoss": 5.0, "attack": 3.0,
	"negotiation_standard": 0.5, "standard": 0.5,
	"negotiation_question": 1.0, "question": 1.0,
	"negotiation_retreat": -1.0, "retreat": -1.0,
	"report_public": 2.0, "report": 1.0, "report_suppress": -1.0,
	"deputy_trust_low": 1.0, "deputy_trust_high": -1.0, "deputy_trust": 1.0,
	"political_aeug": 2.0, "political_ueg": 1.0, "aeug_action": 2.0,
	"cleared": 0.0, "vindicated": 0.0, "exonerated": 0.0,
}
const DEFAULT_IMPACTS := {
	"UNLISTED": {"port_access": {"ueg": "NORMAL", "joint": "NORMAL"},
		"iff_watch_flag": false, "combat_roe_modifier": 1.0,
		"ending_branch_hint": "standard"},
	"WATCHLIST": {"port_access": {"ueg": "WATCHED", "joint": "NORMAL"},
		"iff_watch_flag": true, "combat_roe_modifier": 1.05,
		"ending_branch_hint": "watchlist"},
	"RESTRICTED": {"port_access": {"ueg": "RESTRICTED", "joint": "WATCHED"},
		"iff_watch_flag": true, "combat_roe_modifier": 1.15,
		"ending_branch_hint": "restricted"},
	"DESIGNATED_ILLEGAL": {"port_access": {"ueg": "DENIED", "joint": "RESTRICTED"},
		"iff_watch_flag": true, "combat_roe_modifier": 1.30,
		"ending_branch_hint": "designated_illegal"},
	"HUNTED": {"port_access": {"ueg": "DENIED", "joint": "DENIED"},
		"iff_watch_flag": true, "combat_roe_modifier": 1.50,
		"ending_branch_hint": "hunted"},
	"CLEARED": {"port_access": {"ueg": "CLEARED", "joint": "CLEARED"},
		"iff_watch_flag": false, "combat_roe_modifier": 1.0,
		"ending_branch_hint": "cleared"},
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var status := "UNLISTED"
var heat := 0.0
var t := 0.0
var ticks := 0
var log: Array = []
var dedupe: Dictionary = {}
var enabled := true

var thresholds: Dictionary = DEFAULT_THRESHOLDS.duplicate(true)
var weights: Dictionary = DEFAULT_WEIGHTS.duplicate(true)
var impacts: Dictionary = DEFAULT_IMPACTS.duplicate(true)
var decay_per_day := 0.0
var allow_deescalation := false
var _seq := 0

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	status = "UNLISTED"
	heat = 0.0
	t = 0.0
	ticks = 0
	log = []
	dedupe = {}
	_seq = 0
	thresholds = DEFAULT_THRESHOLDS.duplicate(true)
	weights = DEFAULT_WEIGHTS.duplicate(true)
	impacts = DEFAULT_IMPACTS.duplicate(true)
	decay_per_day = 0.0
	allow_deescalation = false
	var c: Dictionary = cfg if cfg is Dictionary else {}
	if c.get("thresholds") is Dictionary:
		for k in (c.get("thresholds") as Dictionary).keys():
			thresholds[str(k)] = float((c.get("thresholds") as Dictionary)[k])
	if c.get("weights") is Dictionary:
		for k in (c.get("weights") as Dictionary).keys():
			weights[str(k)] = float((c.get("weights") as Dictionary)[k])
	if c.get("impacts") is Dictionary:
		for k in (c.get("impacts") as Dictionary).keys():
			if (c.get("impacts") as Dictionary)[k] is Dictionary:
				impacts[str(k)] = ((c.get("impacts") as Dictionary)[k] as Dictionary).duplicate(true)
	decay_per_day = float(c.get("decay_per_day", 0.0))
	allow_deescalation = bool(c.get("allow_deescalation", false))

	var v := _validate_config()
	if not bool(v.get("ok", false)):
		errors.append_array(v.get("errors", []))
		return false
	ready = true
	_log_change("init", "UNLISTED", "UNLISTED", 0.0, "initial")
	return true

func _validate_config() -> Dictionary:
	var errs: Array[String] = []
	var last := 0.0
	for st in ESCALATION:
		if st == "UNLISTED":
			continue
		if not thresholds.has(st):
			errs.append("thresholds 缺 " + st)
			continue
		elif not (thresholds[st] is int or thresholds[st] is float):
			errs.append("thresholds.%s 必须是数值" % st)
		elif float(thresholds[st]) <= 0.0:
			errs.append("thresholds.%s 必须 >0" % st)
		var val := float(thresholds.get(st, 0.0))
		if val < last:
			errs.append("thresholds 必须递增：" + st)
		last = val
	for k in weights.keys():
		if not (weights[k] is int or weights[k] is float):
			errs.append("weights.%s 必须是数值" % str(k))
		if float(weights[k]) < -20.0 or float(weights[k]) > 20.0:
			# 只警告，不阻止用户配置
			warnings.append("weights.%s 超出 [-20,20]" % str(k))
	if not is_finite(decay_per_day) or decay_per_day < 0.0:
		errs.append("decay_per_day 必须有限且 >=0")
	if not (impacts.get("UNLISTED") is Dictionary):
		errs.append("impacts.UNLISTED 缺失")
	return {"ok": errs.is_empty(), "errors": errs}

# ── 状态推导 ────────────────────────────────────────────────────

func _status_from_heat() -> String:
	if heat >= float(thresholds.get("HUNTED", 10.0)):
		return "HUNTED"
	if heat >= float(thresholds.get("DESIGNATED_ILLEGAL", 7.0)):
		return "DESIGNATED_ILLEGAL"
	if heat >= float(thresholds.get("RESTRICTED", 4.0)):
		return "RESTRICTED"
	if heat >= float(thresholds.get("WATCHLIST", 2.0)):
		return "WATCHLIST"
	return "UNLISTED"

func _index(st: String) -> int:
	return STATES.find(st)

# ── 事件入口 ────────────────────────────────────────────────────

## trigger：见 DEFAULT_WEIGHTS/CLEAR_TRIGGERS，或配置自定义；
## payload 可含 event_id/id 用于显式去重（否则按 trigger+payload 去重）。
func apply_event(trigger: String, payload := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: LegalStatusService 未 ready")
	if trigger.strip_edges() == "":
		return _fail("invalid_trigger", "precondition: trigger 为空")
	if status == "CLEARED":
		return _fail("cleared_locked", "precondition: CLEARED 状态锁定")
	var p: Dictionary = payload if payload is Dictionary else {}
	var key := _dedupe_key(trigger, p)
	if dedupe.has(key) and not bool(p.get("force", false)):
		_seq += 1
		var dup := {"schema": "legal_status_log.v1", "seq": _seq, "kind": "dedupe",
			"trigger": trigger, "reason": "duplicate_event", "heat": heat,
			"status": status, "duplicate": true, "t": t}
		log.append(dup)
		return {"ok": true, "duplicate": true, "reason": "duplicate_event",
			"status": status, "heat": heat, "log_entry": dup.duplicate(true)}
	# 清除类触发：显式进入 CLEARED
	if trigger in CLEAR_TRIGGERS:
		var prev_clear := status
		status = "CLEARED"
		dedupe[key] = true
		var entry := _log_change(trigger, prev_clear, "CLEARED", 0.0,
			str(p.get("reason", "cleared")))
		return {"ok": true, "duplicate": false, "status": status, "heat": heat,
			"previous": prev_clear, "reason": str(p.get("reason", "cleared")),
			"log_entry": entry}
	if not weights.has(trigger):
		return _fail("unknown_trigger", "precondition: 未知 trigger：" + trigger)
	var weight := float(weights[trigger])
	if p.has("weight") and (p.get("weight") is int or p.get("weight") is float) \
			and is_finite(float(p["weight"])):
		weight = float(p["weight"])
	var prev := status
	heat = maxf(0.0, heat + weight)
	var target := _status_from_heat()
	if not allow_deescalation and _index(target) < _index(prev):
		target = prev
	status = target
	dedupe[key] = true
	var reason := str(p.get("reason", "trigger=" + trigger))
	var entry := _log_change(trigger, prev, status, weight, reason)
	return {"ok": true, "duplicate": false, "status": status, "heat": heat,
		"previous": prev, "weight": weight, "reason": reason,
		"log_entry": entry}

func _dedupe_key(trigger: String, p: Dictionary) -> String:
	for k in ["event_id", "id", "uid"]:
		if p.has(k) and str(p[k]) != "":
			return "id:" + str(p[k])
	return "sig:" + trigger + "|" + _norm(p)

func _norm(v) -> String:
	var s := JSON.stringify(v)
	if s == "" or s == "null":
		return "null"
	return JSON.stringify(JSON.parse_string(s))

## 显式设置状态（仍记录 log；CLEARED 为极少数，设置后锁定）。
func set_status(new_status: String, reason := "") -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: LegalStatusService 未 ready")
	if not (new_status in STATES):
		return _fail("invalid_status", "precondition: 非法状态：" + new_status)
	if status == "CLEARED" and new_status != "CLEARED":
		return _fail("cleared_locked", "precondition: CLEARED 状态锁定")
	var prev := status
	status = new_status
	var why := reason if reason != "" else "explicit"
	var entry := _log_change("set_status", prev, status, 0.0, why)
	return {"ok": true, "status": status, "previous": prev, "heat": heat,
		"reason": why, "log_entry": entry}

## 推演时间：可选 decay_per_day 降低 heat；状态变化记录；CLEARED 锁定。
func tick(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: LegalStatusService 未 ready")
	if not is_finite(float(dt)) or float(dt) < 0.0:
		return _fail("invalid_dt", "precondition: tick(dt) 要求有限且 >=0")
	t += float(dt)
	ticks += 1
	var prev := status
	var decayed := 0.0
	if status != "CLEARED" and decay_per_day > 0.0 and heat > 0.0:
		decayed = minf(heat, decay_per_day * float(dt) / 86400.0)
		heat = maxf(0.0, heat - decayed)
		if allow_deescalation:
			status = _status_from_heat()
	var changed := status != prev
	var entry := {"schema": "legal_status_log.v1", "seq": _seq + 1,
		"kind": "tick" if not changed else "transition", "trigger": "tick",
		"reason": "tick dt=%s decayed=%s" % [str(dt), str(decayed)],
		"from": prev, "to": status, "heat": heat, "status": status,
		"decayed": decayed, "t": t, "duplicate": false}
	_seq += 1
	log.append(entry)
	return {"ok": true, "t": t, "ticks": ticks, "heat": heat, "status": status,
		"changed": changed, "decayed": decayed, "log_entry": entry.duplicate(true)}

func _log_change(kind: String, from: String, to: String, weight: float,
		reason: String) -> Dictionary:
	_seq += 1
	var entry := {"schema": "legal_status_log.v1", "seq": _seq, "kind": kind,
		"trigger": kind if kind in ["init", "set_status"] else kind,
		"from": from, "to": to, "weight": weight, "heat": heat,
		"status": status, "reason": reason, "t": t, "duplicate": false}
	# apply_event 传入 trigger 作为 kind（保持日志可读）
	if kind not in ["init", "set_status", "tick"]:
		entry["trigger"] = kind
	log.append(entry)
	return entry.duplicate(true)

# ── 影响接口（只输出标志，不改 world/法律文本）────────────────

func impact() -> Dictionary:
	var base = (impacts.get(status, impacts.get("UNLISTED", {})) as Dictionary)
	var out := (base as Dictionary).duplicate(true) if base is Dictionary else {}
	out["legal_status"] = status
	out["heat"] = heat
	out["writes"] = {"world": false, "side": false, "legal_text": false, "ui": false}
	return out

func port_access() -> Dictionary:
	return (impact().get("port_access", {}) as Dictionary).duplicate(true)

func iff_watch_flag() -> bool:
	return bool(impact().get("iff_watch_flag", false))

func combat_roe_modifier() -> float:
	return float(impact().get("combat_roe_modifier", 1.0))

func ending_branch_hint() -> String:
	return str(impact().get("ending_branch_hint", "standard"))

# ── VM / summary / contracts ───────────────────────────────────

func vm() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "enabled": enabled,
		"status": status, "heat": heat, "t": t, "ticks": ticks,
		"states": STATES.duplicate(), "thresholds": thresholds.duplicate(true),
		"weights": weights.duplicate(true), "decay_per_day": decay_per_day,
		"allow_deescalation": allow_deescalation,
		"impact": impact(), "log": log.duplicate(true),
		"dedupe_count": dedupe.size(),
		"writes": {"world": false, "ui": false, "v15": false}}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "status": status,
		"heat": heat, "t": t, "ticks": ticks, "impact": impact(),
		"log_count": log.size(), "dedupe_count": dedupe.size(),
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	if not (status in STATES):
		v.append("status 非法：" + status)
	if not is_finite(heat) or heat < 0.0:
		v.append("heat 非法")
	if not is_finite(t) or t < 0.0:
		v.append("t 非法")
	var last := 0.0
	for st in ESCALATION:
		if st == "UNLISTED":
			continue
		if not thresholds.has(st):
			v.append("thresholds 缺 " + st)
			continue
		var val := float(thresholds.get(st, 0.0))
		if val < last:
			v.append("thresholds 非递增：" + st)
		last = val
	if status == "CLEARED" and bool(impact().get("iff_watch_flag", true)):
		v.append("CLEARED 仍有 iff_watch_flag")
	if log.is_empty():
		v.append("log 为空（变化必须记录）")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

# ── save/load ──────────────────────────────────────────────────

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"status": status, "heat": heat, "t": t, "ticks": ticks,
		"thresholds": thresholds.duplicate(true), "weights": weights.duplicate(true),
		"impacts": impacts.duplicate(true), "decay_per_day": decay_per_day,
		"allow_deescalation": allow_deescalation,
		"log": JSON.parse_string(JSON.stringify(log)),
		"dedupe": dedupe.duplicate(true), "seq": _seq})

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
	var st := str(d.get("status", ""))
	if not (st in STATES):
		return _fail("invalid_payload", "load: status 非法")
	if not (d.get("log", null) is Array):
		return _fail("invalid_payload", "load: log 非法")
	if not (d.get("dedupe", null) is Dictionary):
		return _fail("invalid_payload", "load: dedupe 非法")
	if not (d.get("thresholds", null) is Dictionary):
		return _fail("invalid_payload", "load: thresholds 非法")
	if not (d.get("weights", null) is Dictionary):
		return _fail("invalid_payload", "load: weights 非法")
	# 全部校验通过后再替换
	status = st
	heat = maxf(0.0, float(d.get("heat", 0.0)))
	t = maxf(0.0, float(d.get("t", 0.0)))
	ticks = maxi(0, int(d.get("ticks", 0)))
	thresholds = (d.get("thresholds") as Dictionary).duplicate(true)
	weights = (d.get("weights") as Dictionary).duplicate(true)
	impacts = (d.get("impacts", impacts) as Dictionary).duplicate(true) \
		if d.get("impacts") is Dictionary else impacts
	decay_per_day = float(d.get("decay_per_day", 0.0))
	allow_deescalation = bool(d.get("allow_deescalation", false))
	log = (d.get("log") as Array).duplicate(true)
	dedupe = (d.get("dedupe") as Dictionary).duplicate(true)
	_seq = int(d.get("seq", log.size()))
	ready = true
	return {"ok": true, "status": status, "heat": heat, "t": t}

func reset() -> Dictionary:
	var ok := setup({})
	return {"ok": ok, "status": status, "heat": heat}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
