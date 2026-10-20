extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3R：IdentificationService（识别自动化/证据融合；新文件）
#
# - 自动/半自动询问策略：interval/priority/mode；仅 range/LOS/EMCON 允许；
#   只产生 query_request，不自动发射武器；
# - 身份证据融合：transponder/sensor/track evidence（source/t/mode/status/
#   confidence/spoofed）；identity unknown/friend/neutral/suspect/hostile/station，
#   confidence 0..1、sources、contradictions、spoof_suspicion、age；
#   IFF/应答单独不能到 hostile；自动分类最高 suspect/L3；L4 需人工/授权或
#   至少两类独立证据；冲突/欺骗降级；时间衰减/重复抑制；
# - 输出 identity_assessment 事件；不写 world/TrackTable/UI/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.identification_service.v1"
const SAVE_SCHEMA := "v17.identification_service_save.v1"
const ASSESS_SCHEMA := "identity_assessment.v1"
const EVENT_SCHEMA := "identification_event.v1"
const VERSION := "1.0.0"
const IDENTITIES := ["unknown", "friend", "neutral", "suspect", "hostile", "station"]
const MANUAL_IDENTITIES := ["friend", "neutral", "suspect", "hostile", "station", "unknown"]
const CATEGORY_BY_SOURCE := {
	"transponder": "iff", "iff": "iff", "elint": "elint", "signal": "elint",
	"radar": "sensor", "sensor": "sensor", "optical": "sensor", "ir": "sensor",
	"track": "track", "track_table": "track", "manual": "manual",
	"authorization": "manual", "database": "database",
}
const MAX_EVENTS := 600
const MAX_OUTBOX := 600
const MAX_EVIDENCE_PER_TARGET := 120

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var t := 0.0
var evidence_by_target: Dictionary = {}
var assessments: Dictionary = {}
var target_states: Dictionary = {}
var events: Array = []
var outbox: Array = []
var query_requests: Array = []
var query_seq := 0
var _event_seq := 0
var _evidence_seq := 0
var _seen_evidence: Dictionary = {}

var cfg_evidence_ttl_s := 120.0
var cfg_decay_half_life_s := 60.0
var cfg_auto_level_max := 3
var cfg_auto: Dictionary = {}
var cfg_observer_id := "identification"

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup / 配置 ───────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	t = float(c.get("t", 0.0))
	evidence_by_target = {}
	assessments = {}
	target_states = {}
	events = []
	outbox = []
	query_requests = []
	query_seq = 0
	_event_seq = 0
	_evidence_seq = 0
	_seen_evidence = {}
	cfg_evidence_ttl_s = maxf(1.0, float(c.get("evidence_ttl_s", 120.0)))
	cfg_decay_half_life_s = maxf(1.0, float(c.get("decay_half_life_s", 60.0)))
	cfg_auto_level_max = clampi(int(c.get("auto_level_max", 3)), 1, 3)
	cfg_observer_id = str(c.get("observer_id", "identification"))
	var a: Dictionary = c.get("auto", {}) if c.get("auto") is Dictionary else {}
	cfg_auto = {"enabled": bool(a.get("enabled", false)),
		"interval_s": maxf(1.0, float(a.get("interval_s", 5.0))),
		"modes": (a.get("modes", ["mode_s"]) as Array).duplicate(),
		"max_range_km": maxf(0.0, float(a.get("max_range_km", 5000.0))),
		"min_confidence": clampf(float(a.get("min_confidence", 0.75)), 0.0, 1.0),
		"min_age_s": maxf(0.0, float(a.get("min_age_s", 3.0))),
		"max_requests_per_tick": maxi(1, int(a.get("max_requests_per_tick", 4))),
		"next_t": 0.0}
	if not is_finite(t) or t < 0.0:
		errors.append("t 必须有限且 >=0")
		return false
	ready = true
	return true

func set_time(new_t: float) -> void:
	if is_finite(new_t) and new_t >= t:
		t = new_t

func set_auto(enabled: bool, opts := {}) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	cfg_auto["enabled"] = enabled
	if o.has("interval_s"):
		cfg_auto["interval_s"] = maxf(1.0, float(o.get("interval_s", 5.0)))
	if o.has("modes") and (o.get("modes") is Array):
		cfg_auto["modes"] = (o.get("modes") as Array).duplicate()
	if o.has("max_range_km"):
		cfg_auto["max_range_km"] = maxf(0.0, float(o.get("max_range_km", 5000.0)))
	if o.has("min_confidence"):
		cfg_auto["min_confidence"] = clampf(float(o.get("min_confidence", 0.75)), 0.0, 1.0)
	if o.has("min_age_s"):
		cfg_auto["min_age_s"] = maxf(0.0, float(o.get("min_age_s", 3.0)))
	if o.has("max_requests_per_tick"):
		cfg_auto["max_requests_per_tick"] = maxi(1, int(o.get("max_requests_per_tick", 4)))
	_emit("auto_config", {"enabled": enabled, "auto": cfg_auto.duplicate(true)})
	return {"ok": true, "auto": cfg_auto.duplicate(true)}

# ── 证据输入 ─────────────────────────────────────────────────

## 输入一条证据（不写 world/TrackTable）：
## {target_id, source, t?, mode?, status?, identity?, confidence?, spoofed?,
##  evidence_type?, category?, range_km?, los?, emcon?, note?}
func ingest(raw: Variant) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: IdentificationService 未 ready")
	if not (raw is Dictionary):
		return _fail("invalid_evidence", "precondition: evidence 必须是对象")
	var ev: Dictionary = (raw as Dictionary).duplicate(true)
	var target_id := str(ev.get("target_id", ""))
	if target_id == "":
		return _fail("invalid_target", "precondition: target_id 必填")
	var source := str(ev.get("source", ""))
	if source == "":
		return _fail("invalid_source", "precondition: source 必填")
	var et := t
	if ev.has("t"):
		if not (ev.get("t") is int or ev.get("t") is float) or not is_finite(float(ev.get("t"))):
			return _fail("invalid_time", "precondition: evidence.t 非法")
		et = float(ev.get("t"))
	var identity := str(ev.get("identity", "unknown")).to_lower()
	if not (identity in IDENTITIES):
		return _fail("invalid_identity", "precondition: identity 非法：" + identity)
	var confidence := clampf(float(ev.get("confidence", 0.5)), 0.0, 1.0)
	if not is_finite(confidence):
		return _fail("invalid_confidence", "precondition: confidence 非法")
	var category := str(ev.get("category", ""))
	if category == "":
		category = str(CATEGORY_BY_SOURCE.get(source.to_lower(), "other"))
	var mode := str(ev.get("mode", ""))
	var status := str(ev.get("status", ""))
	var key := "%s|%s|%s|%s|%s|%s|%s" % [target_id, source, identity, mode, status,
		str(et), str(bool(ev.get("spoofed", false)))]
	if _seen_evidence.has(key):
		return {"ok": true, "duplicate": true, "target_id": target_id,
			"assessment": get_assessment(target_id)}
	_seen_evidence[key] = true
	_evidence_seq += 1
	var norm := {"schema": "identity_evidence.v1", "evidence_id": "IEV-%06d" % _evidence_seq,
		"target_id": target_id, "source": source, "category": category,
		"t": et, "mode": mode, "status": status, "identity": identity,
		"confidence": confidence, "spoofed": bool(ev.get("spoofed", false)),
		"range_km": float(ev.get("range_km", 0.0)),
		"los": bool(ev.get("los", true)), "emcon": bool(ev.get("emcon", false)),
		"evidence_type": str(ev.get("evidence_type", category)),
		"note": str(ev.get("note", "")), "ingested_t": t}
	if not evidence_by_target.has(target_id):
		evidence_by_target[target_id] = []
	(evidence_by_target[target_id] as Array).append(norm)
	while (evidence_by_target[target_id] as Array).size() > MAX_EVIDENCE_PER_TARGET:
		(evidence_by_target[target_id] as Array).pop_front()
	if bool(ev.has("range_km")) or bool(ev.has("los")) or bool(ev.has("emcon")):
		var st: Dictionary = target_states.get(target_id, {})
		if ev.has("range_km"):
			st["range_km"] = float(ev.get("range_km", 0.0))
		if ev.has("los"):
			st["los"] = bool(ev.get("los", true))
		if ev.has("emcon"):
			st["emcon"] = bool(ev.get("emcon", false))
		target_states[target_id] = st
	var a: Dictionary = _recompute(target_id)
	_emit("evidence_ingested", {"target_id": target_id, "source": source,
		"identity": identity, "confidence": confidence, "category": category})
	_emit_assessment(a, "evidence")
	return {"ok": true, "duplicate": false, "target_id": target_id,
		"evidence": norm, "assessment": a.duplicate(true)}

func set_target_state(target_id: String, state: Dictionary) -> Dictionary:
	if target_id == "":
		return _fail("invalid_target", "target_id 必填")
	var st: Dictionary = (target_states.get(target_id, {}) as Dictionary).duplicate(true)
	for k in state.keys():
		if str(k) in ["range_km", "los", "emcon", "priority", "manual_locked"]:
			st[str(k)] = state[k]
	target_states[target_id] = st
	return {"ok": true, "target_id": target_id, "state": st.duplicate(true)}

# ── 评估 / 融合 ───────────────────────────────────────────────

func step(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: IdentificationService 未 ready")
	if not is_finite(dt) or dt < 0.0:
		return _fail("invalid_dt", "precondition: dt 必须有限且 >=0")
	t += dt
	for tid in evidence_by_target.keys():
		_recompute(str(tid))
	_emit("step", {"dt": dt, "t": t})
	return {"ok": true, "t": t, "targets": assessments.size(),
		"assessments": _assessment_list()}

## 只重算并返回指定目标评估。
func assess(target_id: String) -> Dictionary:
	if not evidence_by_target.has(target_id):
		return {"ok": false, "reason": "unknown_target", "target_id": target_id}
	var a: Dictionary = _recompute(target_id)
	_emit_assessment(a, "assess")
	return {"ok": true, "assessment": a.duplicate(true)}

func get_assessment(target_id: String) -> Dictionary:
	return (assessments.get(target_id, {}) as Dictionary).duplicate(true)

## 人工确认/授权：L4；hostile 只允许此路径或 authorize_hostile。
func manual_confirm(target_id: String, identity: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: IdentificationService 未 ready")
	if target_id == "":
		return _fail("invalid_target", "target_id 必填")
	if not (identity in MANUAL_IDENTITIES):
		return _fail("invalid_identity", "precondition: identity 非法：" + identity)
	var o: Dictionary = opts if opts is Dictionary else {}
	var a: Dictionary = (assessments.get(target_id, {}) as Dictionary).duplicate(true)
	if a.is_empty():
		a = _empty_assessment(target_id)
	a["manual_identity"] = identity
	a["manual_authority"] = str(o.get("authority", "manual"))
	a["manual_confidence"] = clampf(float(o.get("confidence", 1.0)), 0.0, 1.0)
	a["manual"] = true
	a["authorized"] = bool(o.get("authorized", identity == "hostile"))
	a["manual_t"] = t
	assessments[target_id] = a
	assessments[target_id] = _recompute(target_id)
	_emit_assessment(assessments[target_id], "manual_confirm")
	_emit("manual_confirm", {"target_id": target_id, "identity": identity,
		"authority": str(a.get("manual_authority", "")),
		"authorized": bool(a.get("authorized", false))})
	return {"ok": true, "assessment": (assessments[target_id] as Dictionary).duplicate(true)}

func authorize_hostile(target_id: String, authority := "command", opts := {}) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	o["authority"] = authority
	o["authorized"] = true
	return manual_confirm(target_id, "hostile", o)

func clear_manual(target_id: String) -> Dictionary:
	if not assessments.has(target_id):
		return _fail("unknown_target", "precondition: 未知目标：" + target_id)
	var a: Dictionary = assessments[target_id]
	a.erase("manual_identity")
	a.erase("manual_authority")
	a.erase("manual_confidence")
	a["manual"] = false
	a["authorized"] = false
	assessments[target_id] = _recompute(target_id)
	_emit_assessment(assessments[target_id], "manual_clear")
	return {"ok": true, "assessment": (assessments[target_id] as Dictionary).duplicate(true)}

func _empty_assessment(target_id: String) -> Dictionary:
	return {"schema": ASSESS_SCHEMA, "target_id": target_id,
		"identity": "unknown", "confidence": 0.0, "level": 1,
		"level_name": "L1_BEARING", "sources": [], "categories": [],
		"contradictions": [], "spoof_suspicion": 0.0,
		"evidence_count": 0, "last_update": t, "age": 0.0,
		"auto": true, "manual": false, "authorized": false,
		"trigger_hint": "", "notes": [], "writes_v15": false}

func _recompute(target_id: String) -> Dictionary:
	var arr: Array = evidence_by_target.get(target_id, [])
	var now := t
	var valid: Array = []
	var sources: Array = []
	var categories: Array = []
	var contradiction_ids: Array = []
	var spoof := 0.0
	var weighted: Dictionary = {}
	var manual_prev: Dictionary = (assessments.get(target_id, {}) as Dictionary).duplicate(true)
	for raw in arr:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var age := now - float(ev.get("t", now))
		if age < 0.0:
			age = 0.0
		if age > cfg_evidence_ttl_s:
			continue
		var decay := pow(0.5, age / cfg_decay_half_life_s)
		var eff := clampf(float(ev.get("confidence", 0.5)) * decay, 0.0, 1.0)
		ev["effective_confidence"] = eff
		ev["age_s"] = age
		valid.append(ev)
		var src := str(ev.get("source", ""))
		if not (src in sources):
			sources.append(src)
		var cat := str(ev.get("category", "other"))
		if not (cat in categories):
			categories.append(cat)
		var ident := str(ev.get("identity", "unknown"))
		weighted[ident] = float(weighted.get(ident, 0.0)) + eff
		if bool(ev.get("spoofed", false)):
			spoof += 0.25
		if str(ev.get("status", "")) in ["captured", "spoofed", "crypto_fail"]:
			spoof += 0.25
		elif str(ev.get("status", "")) in ["wrong_code", "faulty"]:
			spoof += 0.15
	# 矛盾：非 unknown 身份 >=2 种
	var known_ids: Array = []
	for ident2 in weighted.keys():
		if str(ident2) != "unknown":
			known_ids.append(str(ident2))
	if known_ids.size() >= 2:
		spoof += 0.2 * float(known_ids.size() - 1)
		contradiction_ids.append("identity_conflict:" + ",".join(known_ids))
	var a: Dictionary = _empty_assessment(target_id)
	if not manual_prev.is_empty():
		a["manual"] = bool(manual_prev.get("manual", false))
		a["authorized"] = bool(manual_prev.get("authorized", false))
		a["manual_identity"] = str(manual_prev.get("manual_identity", ""))
		a["manual_authority"] = str(manual_prev.get("manual_authority", ""))
		a["manual_confidence"] = float(manual_prev.get("manual_confidence", 0.0))
		a["manual_t"] = float(manual_prev.get("manual_t", 0.0))
	var last_t := 0.0
	for ev2 in valid:
		last_t = maxf(last_t, float(ev2.get("t", 0.0)))
	var total_weight := 0.0
	var top_identity := "unknown"
	var top_weight := 0.0
	for ident3 in weighted.keys():
		var w := float(weighted[ident3])
		total_weight += w
		if w > top_weight:
			top_weight = w
			top_identity = str(ident3)
	var confidence := 0.0
	if total_weight > 0.0:
		var top_count := 0
		var top_sum := 0.0
		for ev3 in valid:
			if str((ev3 as Dictionary).get("identity", "")) == top_identity:
				top_count += 1
				top_sum += float((ev3 as Dictionary).get("effective_confidence", 0.0))
		var avg_top := top_sum / float(maxi(1, top_count))
		var purity := clampf(top_weight / total_weight, 0.0, 1.0)
		confidence = purity * avg_top
	# 置信度校准：独立证据类别加成 + 时间衰减（单源/陈旧更保守）
	confidence *= (0.6 + 0.15 * minf(3.0, float(categories.size())))
	var age_all := maxf(0.0, t - last_t)
	confidence *= clampf(1.0 - age_all / maxf(1.0, cfg_evidence_ttl_s * 2.0), 0.3, 1.0)
	confidence = clampf(confidence, 0.0, 1.0)
	# IFF/transponder 单独 hostile → suspect（不自动 hostile）
	var iff_only := not categories.is_empty()
	for cat2 in categories:
		if str(cat2) != "iff":
			iff_only = false
	if top_identity == "hostile" and iff_only:
		top_identity = "suspect"
		spoof += 0.15
		contradiction_ids.append("iff_alone_no_hostile")
	# 冲突/欺骗降级
	if not contradiction_ids.is_empty():
		confidence = minf(confidence, 0.7)
		if top_identity != "unknown" and top_identity != "suspect":
			top_identity = "suspect"
	spoof = clampf(spoof, 0.0, 1.0)
	if spoof >= 0.5:
		confidence = minf(confidence, 0.6)
	# 自动身份：从不存在 hostile；默认 manual 覆盖
	var auto_identity := top_identity
	if auto_identity == "hostile":
		auto_identity = "suspect"
	if auto_identity == "":
		auto_identity = "unknown"
	if confidence <= 0.0 and valid.is_empty():
		auto_identity = "unknown"
	# level / L3-L4 边界
	var level := 1
	var level_name := "L1_BEARING"
	if valid.size() > 0:
		level = 2
		level_name = "L2_POSITION"
	if auto_identity != "unknown" and confidence > 0.25:
		level = mini(3, cfg_auto_level_max)
		level_name = "L3_CLASSIFIED"
	# L4：manual/授权，或至少两类独立证据 + 高置信 + 非 hostile 自动
	var manual_identity := str(a.get("manual_identity", ""))
	var manual := bool(a.get("manual", false))
	var authorized := bool(a.get("authorized", false))
	var independent := categories.size()
	if manual and manual_identity != "":
		auto_identity = manual_identity if manual_identity != "hostile" or authorized else "suspect"
		confidence = maxf(confidence, float(a.get("manual_confidence", 0.8)))
		level = 4
		level_name = "L4_IDENTIFIED"
		if manual_identity == "hostile" and authorized:
			auto_identity = "hostile"
	elif independent >= 2 and confidence >= 0.75 and not (auto_identity in ["unknown", "suspect"]):
		level = 4
		level_name = "L4_IDENTIFIED"
	# hostile 自动永不通过：非授权时降为 suspect
	if auto_identity == "hostile" and not authorized:
		auto_identity = "suspect"
		confidence = minf(confidence, 0.65)
		level = mini(level, 3)
		level_name = "L3_CLASSIFIED"
	a["identity"] = auto_identity
	a["confidence"] = roundf(confidence * 1000.0) / 1000.0
	a["level"] = level
	a["level_name"] = level_name
	a["sources"] = sources.duplicate()
	a["categories"] = categories.duplicate()
	a["contradictions"] = contradiction_ids.duplicate()
	a["spoof_suspicion"] = roundf(spoof * 1000.0) / 1000.0
	a["evidence_count"] = valid.size()
	a["last_update"] = last_t
	a["age"] = maxf(0.0, t - last_t)
	a["auto"] = not manual
	a["trigger_hint"] = ""
	if spoof >= 0.5:
		a["trigger_hint"] = "spoof_suspicion"
	elif auto_identity == "suspect":
		a["trigger_hint"] = "suspect_identity"
	a["notes"] = []
	if iff_only and known_ids.has("hostile"):
		(a["notes"] as Array).append("iff_alone_downgraded")
	assessments[target_id] = a
	return a

func _emit_assessment(a: Dictionary, reason: String) -> void:
	var payload := {"reason": reason, "assessment": a.duplicate(true)}
	_emit("assessment", payload)

# ── 自动/半自动询问 ──────────────────────────────────────────

## 推进时间并（若开启 auto）产生 query_request；只计划询问，不发射武器。
func auto_query_tick(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: IdentificationService 未 ready")
	var sr: Dictionary = step(dt)
	var out: Dictionary = {"ok": true, "t": t, "requests": [],
		"step": sr, "enabled": bool(cfg_auto.get("enabled", false))}
	if not bool(cfg_auto.get("enabled", false)):
		return out
	var interval := float(cfg_auto.get("interval_s", 5.0))
	if t + 1.0e-9 < float(cfg_auto.get("next_t", 0.0)):
		return out
	cfg_auto["next_t"] = t + interval
	var max_req := int(cfg_auto.get("max_requests_per_tick", 4))
	var candidates: Array = []
	for tid in assessments.keys():
		var a: Dictionary = assessments[tid]
		if bool(a.get("manual", false)):
			continue
		var st: Dictionary = target_states.get(str(tid), {})
		if bool(st.get("manual_locked", false)):
			continue
		var range_km := float(st.get("range_km", 0.0))
		if range_km > float(cfg_auto.get("max_range_km", 5000.0)) + 1.0e-9:
			continue
		if not bool(st.get("los", true)) or bool(st.get("emcon", false)):
			continue
		var age := float(a.get("age", 0.0))
		var conf := float(a.get("confidence", 0.0))
		var spoof := float(a.get("spoof_suspicion", 0.0))
		var need := conf < float(cfg_auto.get("min_confidence", 0.75)) \
			or age >= float(cfg_auto.get("min_age_s", 3.0)) \
			or spoof >= 0.4 or str(a.get("identity", "unknown")) in ["unknown", "suspect"]
		if not need:
			continue
		var priority := (1.0 - conf) + spoof + minf(1.0, age / maxf(1.0, interval))
		candidates.append({"target_id": str(tid), "priority": priority,
			"confidence": conf, "spoof": spoof})
	candidates.sort_custom(func(x, y): return float((x as Dictionary).get("priority", 0.0)) > float((y as Dictionary).get("priority", 0.0)))
	var modes: Array = cfg_auto.get("modes", ["mode_s"]) as Array
	for i in range(mini(max_req, candidates.size())):
		var cand: Dictionary = candidates[i]
		var tid2 := str(cand.get("target_id", ""))
		query_seq += 1
		var req := {"schema": "identification_query_request.v1",
			"request_id": "IQR-%06d" % query_seq, "t": t,
			"source_id": cfg_observer_id, "target_id": tid2,
			"mode": str(modes[i % maxi(1, modes.size())]),
			"priority": roundf(float(cand.get("priority", 0.0)) * 1000.0) / 1000.0,
			"reason": "need_identification", "auto": true,
			"state": (target_states.get(tid2, {}) as Dictionary).duplicate(true),
			"writes_v15": false, "weapon": false}
		query_requests.append(req)
		out["requests"].append(req.duplicate(true))
		_emit("query_request", {"request_id": req["request_id"],
			"target_id": tid2, "mode": req["mode"], "priority": req["priority"],
			"auto": true})
	return out

## 读取并清空 query_request 队列（供上层执行）。
func take_query_requests() -> Array:
	var out := query_requests.duplicate(true)
	query_requests = []
	return out

# ── VM / events / save ────────────────────────────────────────

func _emit(kind: String, payload: Dictionary) -> Dictionary:
	_event_seq += 1
	var ev := {"schema": EVENT_SCHEMA, "seq": _event_seq,
		"event_id": "ID-EV-%06d" % _event_seq, "t": t, "kind": kind,
		"payload": payload.duplicate(true), "writes_v15": false}
	events.append(ev.duplicate(true))
	while events.size() > MAX_EVENTS:
		events.pop_front()
	outbox.append(ev.duplicate(true))
	while outbox.size() > MAX_OUTBOX:
		outbox.pop_front()
	return ev

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out := outbox.duplicate(true)
	outbox = []
	return out

func _assessment_list() -> Array:
	var out: Array = []
	for tid in assessments.keys():
		out.append((assessments[tid] as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str((a as Dictionary).get("target_id", "")) < str((b as Dictionary).get("target_id", "")))
	return out

func vm() -> Dictionary:
	var events_out: Array = []
	var start := maxi(0, events.size() - 64)
	for i in range(start, events.size()):
		events_out.append((events[i] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "ready": ready, "t": t,
		"auto": cfg_auto.duplicate(true), "assessments": _assessment_list(),
		"assessment_count": assessments.size(),
		"evidence_counts": _evidence_counts(),
		"query_requests": query_requests.duplicate(true),
		"events": events_out, "writes": {"world": false, "track_table": false,
			"v15": false, "ui": false, "weapon": false}}

func _evidence_counts() -> Dictionary:
	var out: Dictionary = {}
	for tid in evidence_by_target.keys():
		out[str(tid)] = (evidence_by_target[tid] as Array).size()
	return out

func summary() -> Dictionary:
	var by_id: Dictionary = {}
	for tid in assessments.keys():
		var ident := str((assessments[tid] as Dictionary).get("identity", "unknown"))
		by_id[ident] = int(by_id.get(ident, 0)) + 1
	return {"schema": SCHEMA, "ready": ready, "t": t,
		"targets": assessments.size(), "by_identity": by_id,
		"auto_enabled": bool(cfg_auto.get("enabled", false)),
		"events": events.size(), "queries": query_seq,
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	var ev_by: Dictionary = {}
	for tid in evidence_by_target.keys():
		ev_by[str(tid)] = JSON.parse_string(JSON.stringify(evidence_by_target[tid]))
	var ass: Dictionary = {}
	for tid2 in assessments.keys():
		ass[str(tid2)] = JSON.parse_string(JSON.stringify(assessments[tid2]))
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION, "t": t,
		"auto": cfg_auto.duplicate(true), "evidence": ev_by,
		"assessments": ass, "target_states": JSON.parse_string(JSON.stringify(target_states)),
		"query_requests": JSON.parse_string(JSON.stringify(query_requests)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"seq": {"event": _event_seq, "evidence": _evidence_seq, "query": query_seq},
		"config": {"evidence_ttl_s": cfg_evidence_ttl_s,
			"decay_half_life_s": cfg_decay_half_life_s,
			"auto_level_max": cfg_auto_level_max,
			"observer_id": cfg_observer_id}})

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
	if not (d.get("evidence") is Dictionary) or not (d.get("assessments") is Dictionary):
		return _fail("invalid_payload", "load: evidence/assessments 缺失")
	var ev_by: Dictionary = {}
	for tid in (d.get("evidence") as Dictionary).keys():
		if not ((d.get("evidence") as Dictionary)[tid] is Array):
			return _fail("invalid_payload", "load: evidence 非数组")
		ev_by[str(tid)] = ((d.get("evidence") as Dictionary)[tid] as Array).duplicate(true)
	var ass: Dictionary = {}
	for tid2 in (d.get("assessments") as Dictionary).keys():
		if not ((d.get("assessments") as Dictionary)[tid2] is Dictionary):
			return _fail("invalid_payload", "load: assessment 非对象")
		ass[str(tid2)] = ((d.get("assessments") as Dictionary)[tid2] as Dictionary).duplicate(true)
	evidence_by_target = ev_by
	assessments = ass
	t = float(d.get("t", 0.0))
	if d.get("auto") is Dictionary:
		var a: Dictionary = d.get("auto")
		for k in a.keys():
			cfg_auto[str(k)] = a[k]
	target_states = (d.get("target_states", {}) as Dictionary).duplicate(true) \
		if d.get("target_states") is Dictionary else {}
	query_requests = (d.get("query_requests", []) as Array).duplicate(true) \
		if d.get("query_requests") is Array else []
	events = (d.get("events", []) as Array).duplicate(true) if d.get("events") is Array else []
	var seq: Dictionary = d.get("seq", {}) if d.get("seq") is Dictionary else {}
	_event_seq = int(seq.get("event", events.size()))
	_evidence_seq = int(seq.get("evidence", 0))
	query_seq = int(seq.get("query", 0))
	outbox = []
	# 重建去重集合
	_seen_evidence = {}
	for tid3 in evidence_by_target.keys():
		for raw in (evidence_by_target[tid3] as Array):
			if raw is Dictionary:
				var e: Dictionary = raw
				var key := "%s|%s|%s|%s|%s|%s|%s" % [str(e.get("target_id", "")),
					str(e.get("source", "")), str(e.get("identity", "")),
					str(e.get("mode", "")), str(e.get("status", "")),
					str(float(e.get("t", 0.0))), str(bool(e.get("spoofed", false)))]
				_seen_evidence[key] = true
	_check_contracts()
	return {"ok": true, "targets": assessments.size(), "t": t}

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	for tid in assessments.keys():
		var a: Dictionary = assessments[tid]
		if not (str(a.get("identity", "")) in IDENTITIES):
			v.append("assessment %s identity 非法" % str(tid))
		if float(a.get("confidence", -1.0)) < 0.0 or float(a.get("confidence", 2.0)) > 1.0:
			v.append("assessment %s confidence 越界" % str(tid))
		if int(a.get("level", 0)) < 1 or int(a.get("level", 0)) > 4:
			v.append("assessment %s level 越界" % str(tid))
		if str(a.get("identity", "")) == "hostile" and not bool(a.get("authorized", false)):
			v.append("assessment %s hostile 未授权" % str(tid))
		if int(a.get("level", 0)) >= 4 and str(a.get("identity", "")) == "hostile" \
				and not bool(a.get("authorized", false)):
			v.append("assessment %s L4 hostile 未授权" % str(tid))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("IdentificationService 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
