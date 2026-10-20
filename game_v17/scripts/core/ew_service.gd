class_name V2EWService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3Q · EW 效果服务（统一效果层）
#
# 包装/复用 framework/sim/information_warfare.gd，对上层提供可观测的
# EW 效果接口；不写 world/TrackTable/UI，不执行波形/射频仿真。
#
# 效果：noise_jam / deception / chaff / false_target / comms_jam /
#       comms_spoof / emcon / lwr / laser_dazzle / decoy
# 字段：source/target/band/severity/duration/decay；step 过期/衰减。
# 输出：observation_effect（置信度降级/延迟/假观测候选）、
#       comms_effect（延迟/失败/伪造事件）、transponder_effect（伪造应答）、
#       active/query/vm/events；候选不直接建 track。
# ═══════════════════════════════════════════════════════════════════

const InfoWarfare := preload("res://framework/sim/information_warfare.gd")
const SCHEMA_VM := "ew_service.v1"
const SCHEMA_EFFECT := "ew_effect.v1"
const SCHEMA_OBS_EFFECT := "ew_observation_effect.v1"
const SCHEMA_COMMS_EFFECT := "ew_comms_effect.v1"
const SCHEMA_TRANSPONDER_EFFECT := "ew_transponder_effect.v1"
const SCHEMA_EVENT := "ew_event.v1"
const SAVE_SCHEMA := "v17.ew_service_save.v1"
const SAVE_VERSION := "1.0.0"
const EFFECT_TYPES := ["noise_jam", "deception", "chaff", "false_target",
	"comms_jam", "comms_spoof", "emcon", "lwr", "laser_dazzle", "decoy"]
const CATEGORIES := {
	"noise_jam": "radar", "deception": "radar", "chaff": "radar",
	"false_target": "radar", "comms_jam": "comms", "comms_spoof": "comms",
	"emcon": "emission", "lwr": "optical", "laser_dazzle": "optical",
	"decoy": "countermeasure",
}
const DEFAULT_KINDS := {
	"noise_jam": ["radar"], "deception": ["radar"], "chaff": ["radar"],
	"false_target": ["radar"], "comms_jam": ["comms"], "comms_spoof": ["comms"],
	"emcon": ["radar", "iff"], "lwr": ["optical"], "laser_dazzle": ["optical", "ir"],
	"decoy": ["radar"],
}
const MAX_EFFECTS := 200
const MAX_EVENTS := 600

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var observer: Dictionary = {}
var targets: Array = []
var effects: Array = []
var events: Array = []
var emcon_active := false
var errors: Array = []
var warnings: Array = []
var config: Dictionary = {}

var _iw = null
var _seq_effect := 0
var _seq_event := 0
var _outbox: Array = []


func _init(cfg := {}) -> void:
	setup(cfg)


# ── setup ─────────────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	effects = []
	events = []
	_outbox = []
	_seq_effect = 0
	_seq_event = 0
	emcon_active = false
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	observer = InfoWarfare.default_observer(String(config.get("observer_id", "harmattan")))
	if config.get("observer") is Dictionary:
		for k in (config.get("observer") as Dictionary).keys():
			observer[String(k)] = (config.get("observer") as Dictionary)[k]
	targets = []
	if config.get("targets") is Array:
		for raw in (config.get("targets") as Array):
			if raw is Dictionary:
				targets.append((raw as Dictionary).duplicate(true))
	_iw = InfoWarfare.new()
	var ok: bool = _iw.setup({
		"observer_id": String(observer.get("id", "harmattan")),
		"observer": observer.duplicate(true),
		"targets": targets.duplicate(true),
		"stations": [{"id": String(observer.get("id", "harmattan")) + "-EW",
			"pos_km": observer.get("pos_km", [0.0, 0.0, 0.0])}],
		"elint": {"enabled": true},
		"iff": {"enabled": true},
	})
	if not ok:
		warnings.append("InfoWarfare setup 失败，EW 效果仍可用但无波形包装：" + str(_iw.errors))
	# emcon 内容（可选）
	if config.get("emcon") is bool:
		emcon_active = bool(config.get("emcon"))
		if _iw != null:
			_iw.set_emcon(emcon_active)
	ready = true
	return true


# ── apply / step / expire ────────────────────────────────────

## effect:
## {effect,source_id,target_id,band,severity,duration_s,decay_per_s,params}
func apply(raw := {}) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var e: Dictionary = (raw as Dictionary).duplicate(true)
	var etype := String(e.get("effect", e.get("kind", "")))
	if not (etype in EFFECT_TYPES):
		return {"ok": false, "reason": "invalid_effect_type", "effect": etype}
	var severity := clampf(float(e.get("severity", e.get("strength", 0.5))), 0.0, 1.0)
	var duration := float(e.get("duration_s", e.get("duration", 30.0)))
	if not is_finite(duration) or duration < -1.0:
		return {"ok": false, "reason": "invalid_duration"}
	var source := String(e.get("source_id", e.get("source", "")))
	var target := String(e.get("target_id", ""))
	if source == "":
		return {"ok": false, "reason": "missing_source"}
	# 先复用 InformationWarfare 的统一 EWEffect（波形层只作包装/兼容）
	var iw_raw: Dictionary = {
		"effect": etype, "source_id": source, "target_id": target,
		"severity": severity, "duration_s": duration,
		"band": String(e.get("band", "")),
		"params": e.get("params", {}),
	}
	if etype == "emcon":
		if _iw != null:
			_iw.set_emcon(severity > 0.0)
		emcon_active = severity > 0.0
	if _iw != null:
		var iwr: Dictionary = _iw.apply_ew_effect(iw_raw)
		if not bool(iwr.get("ok", false)) and String(iwr.get("reason", "")) != "not_ready":
			return {"ok": false, "reason": String(iwr.get("reason", "iw_rejected"))}
	_seq_effect += 1
	var decay := maxf(0.0, float(e.get("decay_per_s", 0.0)))
	var t_end := t + duration if duration >= 0.0 else -1.0
	var ev := {
		"schema": SCHEMA_EFFECT, "id": "EW-%05d" % _seq_effect,
		"effect": etype, "category": String(CATEGORIES.get(etype, "")),
		"source_id": source, "target_id": target,
		"band": String(e.get("band", "")),
		"target_kinds": (e.get("target_kinds", DEFAULT_KINDS.get(etype, [])) as Array).duplicate(),
		"severity": severity, "initial_severity": severity,
		"duration_s": duration, "t_start": t, "t_end": t_end,
		"decay_per_s": decay, "age_s": 0.0,
		"remaining_severity": severity, "active": true,
		"params": (e.get("params", {}) as Dictionary).duplicate(true) if e.get("params") is Dictionary else {},
		"requires_confirmation": etype in ["deception", "false_target", "chaff", "comms_spoof"],
		"visible_to": e.get("visible_to", ["own", "enemy_elint"]),
		"authoritative": false, "writes_v15": false,
	}
	effects.append(ev)
	while effects.size() > MAX_EFFECTS:
		effects.pop_front()
	_push_event("ew_applied", ev.duplicate(true), target)
	return {"ok": true, "reason": "", "effect": ev.duplicate(true),
		"writes": {"world": false, "track_table": false, "v15": false}}


func step(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	if _iw != null:
		_iw.t = t
		_iw.step(0.0)
	var keep: Array = []
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if not bool(e.get("active", true)):
			continue
		e["age_s"] = t - float(e.get("t_start", 0.0))
		var remaining := float(e.get("severity", 0.0)) - float(e.get("decay_per_s", 0.0)) * float(e["age_s"])
		if remaining <= 0.0 or (float(e.get("t_end", -1.0)) >= 0.0 and t + 1.0e-9 >= float(e.get("t_end", 0.0))):
			e["active"] = false
			e["remaining_severity"] = 0.0
			e["expired_t"] = t
			_push_event("ew_expired", {"effect_id": String(e.get("id", "")),
				"effect": String(e.get("effect", "")),
				"target_id": String(e.get("target_id", "")),
				"reason": "expired" if float(e.get("t_end", -1.0)) >= 0.0 else "decayed"})
			continue
		e["remaining_severity"] = maxf(0.0, remaining)
		keep.append(e)
	effects = keep
	return {"ok": true, "t": t, "dt": dt_last, "effects": effects.size(),
		"counts": _counts(), "events": events.duplicate(true)}


func expire(effect_id := "") -> Dictionary:
	if effect_id == "":
		var n := 0
		for raw in effects:
			if raw is Dictionary and bool((raw as Dictionary).get("active", true)):
				(raw as Dictionary)["active"] = false
				(raw as Dictionary)["remaining_severity"] = 0.0
				(raw as Dictionary)["expired_t"] = t
				n += 1
		effects = []
		_push_event("ew_expired_all", {"count": n})
		return {"ok": true, "expired": n}
	for raw in effects:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == effect_id \
				and bool((raw as Dictionary).get("active", true)):
			(raw as Dictionary)["active"] = false
			(raw as Dictionary)["remaining_severity"] = 0.0
			(raw as Dictionary)["expired_t"] = t
			_push_event("ew_expired", {"effect_id": effect_id, "reason": "manual"})
			return {"ok": true, "expired": 1, "effect_id": effect_id}
	return {"ok": false, "reason": "unknown_effect", "effect_id": effect_id}


func active(target_id := "", kind := "") -> Array:
	var out: Array = []
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if not bool(e.get("active", true)):
			continue
		if target_id != "" and String(e.get("target_id", "")) != target_id:
			continue
		if kind != "" and not (e.get("target_kinds", []) as Array).has(kind):
			continue
		out.append(e.duplicate(true))
	return out


func query_effect(effect_type := "", target_id := "", kind := "") -> Dictionary:
	if effect_type != "" and not (effect_type in EFFECT_TYPES):
		return {"ok": false, "reason": "invalid_effect_type"}
	var rows: Array = []
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if not bool(e.get("active", true)):
			continue
		if effect_type != "" and String(e.get("effect", "")) != effect_type:
			continue
		if target_id != "" and String(e.get("target_id", "")) != target_id:
			continue
		if kind != "" and not (e.get("target_kinds", []) as Array).has(kind):
			continue
		rows.append(e.duplicate(true))
	var sev := 0.0
	for raw2 in rows:
		if raw2 is Dictionary:
			sev = maxf(sev, float((raw2 as Dictionary).get("remaining_severity", 0.0)))
	return {"ok": true, "effect": effect_type, "target_id": target_id,
		"kind": kind, "active": not rows.is_empty(), "count": rows.size(),
		"severity": sev, "effects": rows, "reason": "" if not rows.is_empty() else "no_effect"}


# ── 可观测影响接口 ────────────────────────────────────────────

## 对观测/识别链：置信度降级、延迟/无应答、假观测候选（不建 track）。
func observation_effect(target_id := "", sensor_kind := "radar") -> Dictionary:
	var noise := _max_sev("noise_jam", target_id, sensor_kind)
	var deception := _max_sev("deception", target_id, sensor_kind)
	var chaff := _max_sev("chaff", target_id, sensor_kind)
	var false_target := _max_sev("false_target", target_id, sensor_kind)
	var dazzle := _max_sev("laser_dazzle", target_id, sensor_kind)
	var decoy := _max_sev("decoy", target_id, sensor_kind)
	var emcon := _max_sev("emcon", target_id, sensor_kind)
	var lwr := _max_sev("lwr", target_id, sensor_kind)
	var conf_mult := clampf(1.0 - 0.6 * noise - 0.3 * deception - 0.15 * chaff
		- 0.2 * dazzle - 0.1 * decoy, 0.0, 1.0)
	var delay := 6.0 * noise + 2.0 * deception + 1.0 * chaff
	if _iw != null and noise > 0.0:
		var re: Dictionary = _iw.radar_effect()
		delay = maxf(delay, float(re.get("extra_delay_s", 0.0)))
	var no_reply := clampf(0.5 * noise + 0.2 * deception + 0.1 * chaff, 0.0, 1.0)
	var false_n := int(round(2.0 * deception + 1.5 * chaff + 2.0 * false_target
		+ 2.0 * decoy))
	var candidates: Array = []
	for i in range(false_n):
		candidates.append({
			"candidate_id": "EWC-%04d-%02d" % [_seq_effect, i + 1],
			"target_id": target_id, "fake": true, "identity": "unknown",
			"confidence": maxf(0.05, 0.6 - 0.5 * float(i)),
			"source_effect": "deception/chaff/false_target/decoy",
			"produces_contact": false, "requires_confirmation": true,
			"writes_track_table": false,
		})
	if bool(query_effect("noise_jam", target_id, sensor_kind).get("active", false)):
		pass
	return {
		"schema": SCHEMA_OBS_EFFECT, "ok": true, "target_id": target_id,
		"sensor_kind": sensor_kind,
		"jammed": noise > 0.0, "noise_severity": noise,
		"deception_severity": deception, "chaff_severity": chaff,
		"false_target_severity": false_target, "decoy_severity": decoy,
		"laser_dazzle_severity": dazzle, "emcon": emcon > 0.0 or emcon_active,
		"lwr_alert": lwr > 0.0, "dazzled": dazzle > 0.0,
		"confidence_mult": conf_mult, "confidence_degraded": conf_mult < 0.999,
		"delay_s": delay, "no_reply_chance": no_reply,
		"false_observations": candidates,
		"false_candidate_count": candidates.size(),
		"requires_confirmation": not candidates.is_empty(),
		"produces_contact": false, "writes_track_table": false,
	}


## 对通信：延迟/失败/伪造；comms_spoof 只给可疑事件/文本，不自动执行。
func comms_effect(target_id := "") -> Dictionary:
	var jam := _max_sev("comms_jam", target_id, "comms")
	var spoof := _max_sev("comms_spoof", target_id, "comms")
	var latency := 40.0 * jam
	var fail := clampf(0.8 * jam, 0.0, 1.0)
	var spoof_events: Array = []
	var text := ""
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if String(e.get("effect", "")) != "comms_spoof" or not bool(e.get("active", true)):
			continue
		if target_id != "" and String(e.get("target_id", "")) != target_id:
			continue
		var params: Dictionary = e.get("params", {}) if e.get("params") is Dictionary else {}
		text = String(params.get("text", text))
		spoof_events.append({"event": "comms_spoof", "target_id": target_id,
			"source_id": String(e.get("source_id", "")), "text": text,
			"suspicious": true, "requires_confirmation": true,
			"auto_execute": false, "effect_id": String(e.get("id", ""))})
	return {"schema": SCHEMA_COMMS_EFFECT, "ok": true, "target_id": target_id,
		"jammed": jam > 0.0, "jam_severity": jam, "latency_add_s": latency,
		"failure_chance": fail, "spoofed": spoof > 0.0,
		"spoof_text": text, "spoof_events": spoof_events,
		"suspicious": not spoof_events.is_empty(),
		"requires_confirmation": not spoof_events.is_empty(),
		"auto_execute": false, "produces_contact": false, "writes_v15": false}


## 对应答机/识别：伪造/置信度降低；不直接判身份，不写 transponder。
func transponder_effect(target_id := "") -> Dictionary:
	var spoof := maxf(_max_sev("comms_spoof", target_id, "comms"),
		_max_sev("deception", target_id, "radar"))
	var chaff := _max_sev("chaff", target_id, "radar")
	var false_target := _max_sev("false_target", target_id, "radar")
	var forged := spoof > 0.0
	var conf := clampf(1.0 - 0.5 * spoof - 0.2 * chaff - 0.2 * false_target, 0.0, 1.0)
	return {"schema": SCHEMA_TRANSPONDER_EFFECT, "ok": true, "target_id": target_id,
		"reply_forged": forged, "confidence_mult": conf,
		"confidence_degraded": conf < 0.999,
		"spoof_severity": spoof,
		"requires_confirmation": forged,
		"identity": "unknown", "hostile": false,
		"produces_contact": false, "writes_v15": false}


func sensor_effect(target_id := "", sensor_kind := "radar") -> Dictionary:
	return observation_effect(target_id, sensor_kind)


func _max_sev(effect_type: String, target_id: String, kind: String) -> float:
	var sev := 0.0
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if String(e.get("effect", "")) != effect_type or not bool(e.get("active", true)):
			continue
		if target_id != "" and String(e.get("target_id", "")) != target_id:
			continue
		if kind != "" and not (e.get("target_kinds", []) as Array).has(kind):
			continue
		sev = maxf(sev, float(e.get("remaining_severity", 0.0)))
	return sev


# ── emcon / events / VM ─────────────────────────────────────

func set_emcon(on: bool) -> Dictionary:
	emcon_active = bool(on)
	if _iw != null:
		_iw.set_emcon(emcon_active)
	if on:
		var r: Dictionary = apply({"effect": "emcon", "source_id": String(observer.get("id", "")),
			"target_id": String(observer.get("id", "")), "severity": 1.0,
			"duration_s": -1.0, "target_kinds": ["radar", "iff"],
			"params": {"settle_s": 1.5}})
		if not bool(r.get("ok", false)):
			return r
		return {"ok": true, "active": true, "emcon": true, "settle_s": 1.5,
			"passive_ok": true, "writes": {"world": false, "v15": false}}
	# off：移除 emcon 效果
	var kept: Array = []
	var removed := 0
	for raw in effects:
		if raw is Dictionary and String((raw as Dictionary).get("effect", "")) == "emcon":
			removed += 1
			continue
		kept.append(raw)
	effects = kept
	_push_event("ew_emcon_off", {"removed": removed})
	return {"ok": true, "active": false, "emcon": false, "removed": removed,
		"passive_ok": true, "writes": {"world": false, "v15": false}}


func _counts() -> Dictionary:
	var by_type: Dictionary = {}
	for raw in effects:
		if raw is Dictionary and bool((raw as Dictionary).get("active", true)):
			var k := String((raw as Dictionary).get("effect", ""))
			by_type[k] = int(by_type.get(k, 0)) + 1
	return {"active": active().size(), "total": effects.size(),
		"by_type": by_type, "emcon": emcon_active}


func vm() -> Dictionary:
	return {
		"schema": SCHEMA_VM, "mode": "shadow", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"observer": observer.duplicate(true), "targets": targets.duplicate(true),
		"effects": effects.duplicate(true),
		"active_effects": active(),
		"emcon": emcon_active,
		"counts": _counts(),
		"events": events.duplicate(true),
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"world": false, "track_table": false, "v15": false, "ui": false},
	}


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t,
		"active": active().size(), "effects": effects.size(),
		"emcon": emcon_active, "events": events.size(),
		"writes": {"world": false, "track_table": false, "v15": false}}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func _push_event(kind: String, payload := {}, target_id := "") -> void:
	_seq_event += 1
	var ev := {"schema": SCHEMA_EVENT, "seq": _seq_event, "t": t, "kind": kind,
		"target_id": target_id, "payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))


# ── save / load ──────────────────────────────────────────────

func save_state() -> String:
	var payload := {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "t": t,
		"observer": observer.duplicate(true), "targets": targets.duplicate(true),
		"effects": JSON.parse_string(JSON.stringify(effects)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"emcon": emcon_active,
		"seq": {"effect": _seq_effect, "event": _seq_event},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
	}
	return JSON.stringify(payload)


func snapshot() -> Dictionary:
	return JSON.parse_string(save_state())


func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		if String(data).strip_edges() == "":
			return {"ok": false, "reason": "empty_state"}
		parsed = JSON.parse_string(String(data))
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json"}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var p: Dictionary = parsed
	if String(p.get("schema", "")) != SAVE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if String(p.get("version", "")) != SAVE_VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	if not (p.get("effects") is Array):
		return {"ok": false, "reason": "invalid_payload"}
	t = float(p.get("t", 0.0))
	effects = (p.get("effects") as Array).duplicate(true)
	events = (p.get("events") as Array).duplicate(true) if p.get("events") is Array else []
	observer = (p.get("observer", observer) as Dictionary).duplicate(true) if p.get("observer") is Dictionary else observer
	targets = (p.get("targets", targets) as Array).duplicate(true) if p.get("targets") is Array else targets
	emcon_active = bool(p.get("emcon", false))
	var seq: Dictionary = p.get("seq", {}) if p.get("seq") is Dictionary else {}
	_seq_effect = int(seq.get("effect", effects.size()))
	_seq_event = int(seq.get("event", events.size()))
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	_outbox = []
	if _iw != null:
		_iw.t = t
		_iw.set_emcon(emcon_active)
	return {"ok": true, "reason": "", "t": t, "effects": effects.size()}
