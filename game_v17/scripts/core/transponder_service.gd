extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3P：TransponderService（应答机行为层；新文件）
#
# - 实体：ship/station/port/fuel/tank/otc/relay；station/设施绑定 FacilityRegistry，
#   ship 绑定 world entity；
# - 模式：mode_a/mode_c/mode_s/mode_5/station_beacon/adsb_like（按 profile 能力）；
# - 状态：normal/off/faulty/captured/spoofed/crypto_fail/expired/no_reply/wrong_code；
# - 码：registration/transponder/facility code 唯一/未注册检测；
# - 加密：crypto_epoch/valid/captured；Mode 5 需 challenge/reply（普通模式不需要）；
# - 询问：source/target/mode/range/occlusion/jam/latency → reply/evidence/trigger；
# - 广播/被动监听：station_beacon/adsb_like 自动广播；舰只可静默；
# - 输出 transponder_event.v1 / track_evidence.v1；不写 world/TrackTable；
# - 触发 trigger_id/event 供 StoryRuntime 消费，不硬编码剧情文本。
# ═══════════════════════════════════════════════════════════════════

const FacilityRegistryScript := preload("res://scripts/core/facility_registry.gd")

const SCHEMA := "v17.transponder_service.v1"
const SAVE_SCHEMA := "v17.transponder_service_save.v1"
const CONTENT_SCHEMA := "v17.transponders_prologue.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/transponders_prologue.json"
const EVENT_SCHEMA := "transponder_event.v1"
const EVIDENCE_SCHEMA := "track_evidence.v1"
const REPLY_SCHEMA := "transponder_reply.v1"
const ENTITY_TYPES := ["ship", "station", "port", "fuel", "tank", "otc", "relay"]
const MODES := ["mode_a", "mode_c", "mode_s", "mode_5", "station_beacon", "adsb_like"]
const STATUSES := ["normal", "off", "faulty", "captured", "spoofed", "crypto_fail",
	"expired", "no_reply", "wrong_code"]
const CRYPTO_MODES := ["mode_5"]
const MAX_EVENTS := 600
const MAX_OUTBOX := 600

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var t := 0.0
var profiles: Dictionary = {}
var profile_order: Array = []
var events: Array = []
var evidence: Array = []
var outbox: Array = []
var _outbox: Array = []
var triggers: Array = []
var jam: Dictionary = {}
var occlusion: Dictionary = {}
var jam_global := 0.0
var occlusion_global := false
var max_range_km := 10000.0
var max_latency_s := 5.0
var crypto_required := true

var facility_registry = null
var content_path := DEFAULT_CONTENT
var content: Dictionary = {}
var _event_seq := 0
var _evidence_seq := 0
var _profile_seq := 0

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup / content ─────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	t = float(c.get("t", 0.0))
	profiles = {}
	profile_order = []
	events = []
	evidence = []
	outbox = []
	_outbox = []
	triggers = []
	jam = {}
	occlusion = {}
	jam_global = clampf(float(c.get("jam", 0.0)), 0.0, 1.0)
	occlusion_global = bool(c.get("occluded", false))
	max_range_km = maxf(0.0, float(c.get("max_range_km", 10000.0)))
	max_latency_s = maxf(0.0, float(c.get("max_latency_s", 5.0)))
	crypto_required = bool(c.get("crypto_required", true))
	facility_registry = c.get("facility_registry", null)
	if facility_registry == null and c.get("facility_content_path", "") != "":
		facility_registry = FacilityRegistryScript.new({"content_path":
			str(c.get("facility_content_path"))})
	content_path = str(c.get("content_path", DEFAULT_CONTENT))
	content = {}
	if c.get("content") is Dictionary and not (c.get("content") as Dictionary).is_empty():
		content = (c.get("content") as Dictionary).duplicate(true)
	else:
		content = _load_json(content_path)
	if content.is_empty():
		errors.append("transponder 内容不可读：" + content_path)
		return false
	var v: Dictionary = validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("transponder: " + str(e))
		return false
	_apply_content(content)
	ready = true
	return true

func _load_json(path: String) -> Dictionary:
	var parsed = null
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			parsed = JSON.parse_string(f.get_as_text())
			f.close()
	if parsed is Dictionary:
		return parsed
	return {}

## 校验 content；返回 {ok,errors}，不修改状态。
func validate_content(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != CONTENT_SCHEMA:
		errs.append("schema 必须为 " + CONTENT_SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	if not (d.get("profiles") is Array) or (d.get("profiles") as Array).is_empty():
		errs.append("profiles 必须为非空数组")
		return {"ok": false, "errors": errs}
	var ids: Dictionary = {}
	var txps: Dictionary = {}
	var regs: Dictionary = {}
	for raw in (d.get("profiles") as Array):
		if not (raw is Dictionary):
			errs.append("profile 非对象")
			continue
		var p: Dictionary = raw
		var pid := str(p.get("profile_id", ""))
		if pid == "" or pid.strip_edges() != pid:
			errs.append("profile_id 非法")
		elif ids.has(pid):
			errs.append("profile_id 重复：" + pid)
		ids[pid] = true
		var et := str(p.get("entity_type", ""))
		if not (et in ENTITY_TYPES):
			errs.append("profile %s entity_type 非法：%s" % [pid, et])
		if str(p.get("name", "")) == "":
			errs.append("profile %s name 为空" % pid)
		var txp := str(p.get("transponder_code", ""))
		var reg := str(p.get("registration_code", ""))
		if txp == "":
			errs.append("profile %s transponder_code 为空" % pid)
		elif txps.has(txp):
			errs.append("transponder_code 重复：" + txp)
		txps[txp] = true
		if reg == "":
			errs.append("profile %s registration_code 为空" % pid)
		elif regs.has(reg):
			errs.append("registration_code 重复：" + reg)
		regs[reg] = true
		var modes = p.get("modes", [])
		if not (modes is Array) or (modes as Array).is_empty():
			errs.append("profile %s modes 为空" % pid)
		else:
			for m in (modes as Array):
				if not (str(m) in MODES):
					errs.append("profile %s mode 非法：%s" % [pid, str(m)])
			var dm := str(p.get("default_mode", ""))
			if not (dm in (modes as Array)):
				errs.append("profile %s default_mode 不在 modes：%s" % [pid, dm])
		var status := str(p.get("status", "normal"))
		if not (status in STATUSES):
			errs.append("profile %s status 非法：%s" % [pid, status])
		if not (p.get("range_km") is int or p.get("range_km") is float) \
				or not is_finite(float(p.get("range_km", NAN))) \
				or float(p.get("range_km", -1.0)) < 0.0:
			errs.append("profile %s range_km 非法" % pid)
		if p.has("crypto"):
			if not (p.get("crypto") is Dictionary):
				errs.append("profile %s crypto 必须是对象" % pid)
			else:
				var cr: Dictionary = p.get("crypto")
				if not (cr.get("epoch") is int or cr.get("epoch") is float) \
						or not is_finite(float(cr.get("epoch", NAN))):
					errs.append("profile %s crypto.epoch 非法" % pid)
				if not (cr.get("valid") is bool):
					errs.append("profile %s crypto.valid 非法" % pid)
		if p.has("broadcast"):
			if not (p.get("broadcast") is Dictionary):
				errs.append("profile %s broadcast 必须是对象" % pid)
		if p.has("trigger_map"):
			if not (p.get("trigger_map") is Dictionary):
				errs.append("profile %s trigger_map 必须是对象" % pid)
			else:
				for k in (p.get("trigger_map") as Dictionary).keys():
					if str((p.get("trigger_map") as Dictionary)[k]) == "":
						errs.append("profile %s trigger_map %s 空" % [pid, str(k)])
		var et2 := str(p.get("entity_type", ""))
		if et2 == "ship" and str(p.get("entity_id", "")) == "":
			errs.append("profile %s ship 需要 entity_id" % pid)
		if et2 in ["station", "port", "fuel", "tank", "otc", "relay"]:
			if str(p.get("facility_id", "")) == "":
				errs.append("profile %s %s 需要 facility_id" % [pid, et2])
			if facility_registry != null and facility_registry.ready:
				var fid := str(p.get("facility_id", ""))
				var fac: Dictionary = facility_registry.facility(fid)
				if fac.is_empty():
					errs.append("profile %s facility 不存在：%s" % [pid, fid])
				else:
					var fcode := str(p.get("facility_code", ""))
					if fcode != "" and fcode != str(fac.get("facility_code", "")):
						errs.append("profile %s facility_code 与注册表不符：%s" % [pid, fcode])
	return {"ok": errs.is_empty(), "errors": errs}

func _apply_content(d: Dictionary) -> void:
	content = d.duplicate(true)
	profiles = {}
	profile_order = []
	for raw in (d.get("profiles") as Array):
		if raw is Dictionary:
			_apply_profile(raw as Dictionary)
	# 若绑定 FacilityRegistry，补齐/校正 facility_code
	if facility_registry != null and facility_registry.ready:
		for pid in profiles.keys():
			var p: Dictionary = profiles[pid]
			var fid := str(p.get("facility_id", ""))
			if fid != "":
				var fac: Dictionary = facility_registry.facility(fid)
				if not fac.is_empty():
					p["facility_code"] = str(fac.get("facility_code", ""))
					p["facility_name"] = str(fac.get("name", ""))
					p["parent_cluster"] = str(fac.get("parent_cluster", ""))
	profile_order.sort()

func _apply_profile(raw: Dictionary) -> void:
	var p: Dictionary = raw.duplicate(true)
	p["status"] = str(p.get("status", "normal"))
	var cr: Dictionary = (p.get("crypto", {}) as Dictionary).duplicate(true) \
		if p.get("crypto") is Dictionary else {}
	if not cr.has("epoch"):
		cr["epoch"] = 1
	if not cr.has("valid"):
		cr["valid"] = true
	if not cr.has("captured"):
		cr["captured"] = false
	if not cr.has("key_id"):
		cr["key_id"] = ""
	p["crypto"] = cr
	var bc: Dictionary = (p.get("broadcast", {}) as Dictionary).duplicate(true) \
		if p.get("broadcast") is Dictionary else {}
	if not bc.has("enabled"):
		bc["enabled"] = false
	if not bc.has("interval_s"):
		bc["interval_s"] = 30.0
	if not bc.has("modes"):
		bc["modes"] = []
	p["broadcast"] = bc
	if not p.has("trigger_map"):
		p["trigger_map"] = {}
	if not p.has("silent"):
		p["silent"] = false
	var pid := str(p.get("profile_id", ""))
	if not profiles.has(pid):
		profile_order.append(pid)
	profiles[pid] = p

# ── profile 管理 ───────────────────────────────────────────────

func profile_ids() -> Array:
	var out: Array = profile_order.duplicate()
	out.sort()
	return out

func profile(profile_id: String) -> Dictionary:
	return (profiles.get(profile_id, {}) as Dictionary).duplicate(true)

func upsert_profile(raw: Variant) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: TransponderService 未 ready")
	if not (raw is Dictionary):
		return _fail("invalid_profile", "precondition: profile 必须是对象")
	# 校验单 profile（走同一 validate，先放临时列表）
	var tmp: Array = []
	for pid in profile_order:
		tmp.append((profiles[pid] as Dictionary).duplicate(true))
	var candidate := (raw as Dictionary).duplicate(true)
	var idx := -1
	for i in range(tmp.size()):
		if str((tmp[i] as Dictionary).get("profile_id", "")) == \
				str(candidate.get("profile_id", "")):
			idx = i
			break
	if idx >= 0:
		tmp[idx] = candidate
	else:
		tmp.append(candidate)
	var test := {"schema": CONTENT_SCHEMA, "version": VERSION, "profiles": tmp}
	var v: Dictionary = validate_content(test)
	if not bool(v.get("ok", false)):
		return _fail("invalid_profile", "profile 校验失败：" + str(v.get("errors", [])))
	_apply_profile(candidate)
	profile_order.sort()
	_emit("profile_upserted", {"profile_id": str(candidate.get("profile_id", "")),
		"created": idx < 0})
	return {"ok": true, "created": idx < 0, "profile": profile(str(
		candidate.get("profile_id", "")))}

func remove_profile(profile_id: String) -> Dictionary:
	if not profiles.has(profile_id):
		return _fail("unknown_profile", "precondition: 未知 profile：" + profile_id)
	profiles.erase(profile_id)
	profile_order.erase(profile_id)
	_emit("profile_removed", {"profile_id": profile_id})
	return {"ok": true, "removed": true, "profile_id": profile_id}

# ── 码注册表 / 加密 ───────────────────────────────────────────

## 注册码查询：匹配 transponder_code / registration_code / facility_code。
func lookup_code(code: String) -> Dictionary:
	var c := code.strip_edges()
	if c == "":
		return {"ok": false, "matched": false, "reason": "empty_code"}
	var matches: Array = []
	for pid in profile_ids():
		var p: Dictionary = profiles[pid]
		if c == str(p.get("transponder_code", "")) \
				or c == str(p.get("registration_code", "")) \
				or (str(p.get("facility_code", "")) != "" and c == str(p.get("facility_code", ""))):
			matches.append({"profile_id": str(pid),
				"transponder_code": str(p.get("transponder_code", "")),
				"registration_code": str(p.get("registration_code", "")),
				"facility_code": str(p.get("facility_code", "")),
				"status": str(p.get("status", "")),
				"entity_type": str(p.get("entity_type", ""))})
	if matches.is_empty():
		return {"ok": false, "matched": false, "reason": "unknown_code",
			"code": c, "duplicate": false}
	return {"ok": true, "matched": true, "code": c,
		"profile_id": str((matches[0] as Dictionary).get("profile_id", "")),
		"matches": matches, "duplicate": matches.size() > 1,
		"count": matches.size()}

## 只读加密状态。
func crypto_state(profile_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(profile_id, {})
	if p.is_empty():
		return {}
	return {"profile_id": profile_id,
		"crypto": (p.get("crypto", {}) as Dictionary).duplicate(true),
		"modes": (p.get("modes", []) as Array).duplicate(),
		"challenge_required": _has_crypto_mode(p)}

func _has_crypto_mode(p: Dictionary) -> bool:
	for m in (p.get("modes", []) as Array):
		if str(m) in CRYPTO_MODES:
			return true
	return false

func set_crypto(profile_id: String, patch: Dictionary) -> Dictionary:
	if not profiles.has(profile_id):
		return _fail("unknown_profile", "precondition: 未知 profile：" + profile_id)
	var p: Dictionary = profiles[profile_id]
	var cr: Dictionary = (p.get("crypto", {}) as Dictionary).duplicate(true)
	for k in patch.keys():
		if str(k) in ["epoch", "valid", "captured", "key_id"]:
			cr[str(k)] = patch[k]
	if not (cr.get("epoch") is int or cr.get("epoch") is float) \
			or not is_finite(float(cr.get("epoch", NAN))):
		return _fail("invalid_crypto", "epoch 必须有限数值")
	cr["valid"] = bool(cr.get("valid", true))
	cr["captured"] = bool(cr.get("captured", false))
	p["crypto"] = cr
	profiles[profile_id] = p
	_emit("crypto_changed", {"profile_id": profile_id,
		"crypto": cr.duplicate(true)})
	var trig := _trigger_for(p, "crypto_changed")
	return {"ok": true, "profile_id": profile_id, "crypto": cr.duplicate(true),
		"trigger": trig}

func set_status(profile_id: String, status: String) -> Dictionary:
	if not profiles.has(profile_id):
		return _fail("unknown_profile", "precondition: 未知 profile：" + profile_id)
	if not (status in STATUSES):
		return _fail("invalid_status", "precondition: 非法状态：" + status)
	var p: Dictionary = profiles[profile_id]
	p["status"] = status
	profiles[profile_id] = p
	_emit("status_changed", {"profile_id": profile_id, "status": status})
	var trig := _trigger_for(p, status)
	return {"ok": true, "profile_id": profile_id, "status": status,
		"trigger": trig}

func set_jam(target_id: String, severity: float) -> Dictionary:
	if not is_finite(severity) or severity < 0.0 or severity > 1.0:
		return _fail("invalid_jam", "precondition: jam severity 必须在 0..1")
	if target_id == "":
		jam_global = severity
	else:
		jam[target_id] = severity
	_emit("jam_changed", {"target_id": target_id, "severity": severity})
	return {"ok": true, "target_id": target_id, "severity": severity}

func set_occlusion(target_id: String, occluded: bool) -> Dictionary:
	if target_id == "":
		occlusion_global = occluded
	else:
		occlusion[target_id] = occluded
	_emit("occlusion_changed", {"target_id": target_id, "occluded": occluded})
	return {"ok": true, "target_id": target_id, "occluded": occluded}

func set_time(new_t: float) -> void:
	if is_finite(new_t) and new_t >= 0.0:
		t = new_t

# ── 询问 ───────────────────────────────────────────────────────

## source 询问 target：返回 {ok,reply,evidence,trigger,events}。
func interrogate(source_id: String, target_id: String, mode := "", opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: TransponderService 未 ready")
	if source_id == "" or target_id == "":
		return _fail("invalid_ids", "precondition: source/target 必填")
	var o: Dictionary = opts if opts is Dictionary else {}
	if not profiles.has(target_id):
		var trig := {"trigger_id": "unknown_code", "event": "unknown_target",
			"target_id": target_id, "reason": "unregistered_target"}
		_emit("no_reply", {"source_id": source_id, "target_id": target_id,
			"reason": "unknown_target", "trigger_id": "unknown_code"})
		return {"ok": false, "reason": "unknown_target", "reply": null,
			"evidence": [], "trigger": trig, "events": take_events()}
	var p: Dictionary = profiles[target_id]
	var use_mode := mode
	if use_mode == "":
		use_mode = str(p.get("default_mode", "mode_s"))
	if not (use_mode in (p.get("modes", []) as Array)):
		return _no_reply(source_id, target_id, p, use_mode, "mode_unsupported", o)
	# 距离/遮挡/干扰/延迟
	var range_km := 0.0
	if o.has("range_km"):
		range_km = maxf(0.0, float(o.get("range_km", 0.0)))
	else:
		range_km = 0.0
	var eff_range := float(p.get("range_km", max_range_km))
	if range_km > eff_range + 1.0e-9:
		return _no_reply(source_id, target_id, p, use_mode, "out_of_range", o)
	if bool(o.get("occluded", false)) or occlusion_global \
			or bool(occlusion.get(target_id, false)):
		return _no_reply(source_id, target_id, p, use_mode, "occluded", o)
	var jv := jam_global
	if o.has("jam"):
		jv = clampf(float(o.get("jam", 0.0)), 0.0, 1.0)
	elif jam.has(target_id):
		jv = maxf(jv, clampf(float(jam[target_id]), 0.0, 1.0))
	if jv > 0.5 + 1.0e-9:
		return _no_reply(source_id, target_id, p, use_mode, "jammed", o)
	var latency := float(o.get("latency_s", 0.0))
	if latency > max_latency_s + 1.0e-9:
		return _no_reply(source_id, target_id, p, use_mode, "latency_exceeded", o)
	# 状态处理
	var status := str(p.get("status", "normal"))
	if status in ["off", "no_reply", "faulty", "expired", "wrong_code", "crypto_fail"]:
		return _no_reply(source_id, target_id, p, use_mode, status, o)
	var spoofed := status == "captured" or status == "spoofed"
	# Mode 5 / crypto
	var challenge := ""
	var challenge_response := ""
	var crypto: Dictionary = (p.get("crypto", {}) as Dictionary).duplicate(true)
	if use_mode in CRYPTO_MODES or not crypto.is_empty():
		if bool(crypto.get("captured", false)) and use_mode in CRYPTO_MODES:
			return _no_reply(source_id, target_id, p, use_mode, "captured_crypto", o)
		if not bool(crypto.get("valid", true)):
			if use_mode in CRYPTO_MODES:
				return _no_reply(source_id, target_id, p, use_mode, "crypto_fail", o)
			# 普通模式不要求 challenge，但 crypto_fail 状态记录
		else:
			if use_mode in CRYPTO_MODES:
				challenge = str(o.get("challenge", "CH-%06d" % (_event_seq + 1)))
				var epoch := int(crypto.get("epoch", 0))
				challenge_response = "RSP-%d-%d" % [_event_seq + 1, epoch]
	var confidence := 1.0
	if jv > 0.0:
		confidence = maxf(0.1, 1.0 - jv * 0.8)
	var binding: Dictionary = _binding_of(p)
	var identity := str(p.get("identity", "unknown"))
	if spoofed:
		identity = "unknown"
		confidence = minf(confidence, 0.4)
	var reply: Dictionary = {"schema": REPLY_SCHEMA, "ok": true,
		"t": t, "source_id": source_id, "target_id": target_id,
		"profile_id": target_id, "entity_type": str(p.get("entity_type", "")),
		"mode": use_mode, "status": status, "spoofed": spoofed,
		"binding": binding.duplicate(true),
		"transponder_code": str(p.get("transponder_code", "")),
		"registration_code": str(p.get("registration_code", "")),
		"facility_code": str(p.get("facility_code", "")),
		"identity": identity, "side": str(p.get("side", "unknown")),
		"crypto": crypto.duplicate(true),
		"challenge": challenge, "challenge_response": challenge_response,
		"range_km": range_km, "occluded": false, "jam": jv,
		"latency_s": latency, "confidence": confidence,
		"trigger": null, "writes_v15": false}
	var trig := _trigger_for(p, status)
	if spoofed and trig.is_empty():
		trig = _trigger_for(p, "spoofed")
	reply["trigger"] = trig
	var ev := _make_evidence(p, binding, use_mode, status, identity,
		confidence, spoofed, trig)
	var event := _emit("interrogation", {"source_id": source_id,
		"target_id": target_id, "profile_id": target_id, "mode": use_mode,
		"status": status, "spoofed": spoofed,
		"trigger_id": str(trig.get("trigger_id", "")) if trig is Dictionary else "",
		"confidence": confidence})
	reply["event_id"] = str(event.get("event_id", ""))
	return {"ok": true, "reply": reply, "evidence": [ev], "trigger": trig,
		"events": take_events()}

func _no_reply(source_id: String, target_id: String, p: Dictionary,
		mode: String, reason: String, o: Dictionary) -> Dictionary:
	var binding: Dictionary = _binding_of(p)
	var trig: Dictionary = _trigger_for(p, reason)
	if trig.is_empty() and reason in ["unknown_target", "wrong_code"]:
		trig = {"trigger_id": "unknown_code", "event": "unknown_code",
			"target_id": target_id, "reason": reason}
	var event := _emit("no_reply", {"source_id": source_id, "target_id": target_id,
		"profile_id": target_id, "mode": mode, "reason": reason,
		"range_km": float(o.get("range_km", 0.0)),
		"occluded": bool(o.get("occluded", false)),
		"jam": float(o.get("jam", jam_global)),
		"latency_s": float(o.get("latency_s", 0.0)),
		"trigger_id": str(trig.get("trigger_id", "")) if trig is Dictionary else "",
		"binding": binding})
	return {"ok": false, "reason": reason,
		"reply": {"schema": REPLY_SCHEMA, "ok": false, "status": "no_reply",
			"reason": reason, "source_id": source_id, "target_id": target_id,
			"profile_id": target_id, "mode": mode, "binding": binding.duplicate(true),
			"trigger": trig, "writes_v15": false},
		"evidence": [], "trigger": trig,
		"events": take_events()}

func _binding_of(p: Dictionary) -> Dictionary:
	return {"entity_id": str(p.get("entity_id", "")),
		"facility_id": str(p.get("facility_id", "")),
		"facility_code": str(p.get("facility_code", "")),
		"parent_cluster": str(p.get("parent_cluster", ""))}

func _trigger_for(p: Dictionary, reason: String) -> Dictionary:
	var tm: Dictionary = p.get("trigger_map", {}) if p.get("trigger_map") is Dictionary else {}
	var candidates: Array = [reason]
	if reason in ["faulty", "off", "no_reply", "expired", "crypto_fail"]:
		candidates.append("no_reply")
	if reason in ["spoofed", "captured", "captured_crypto"]:
		candidates.append("spoofed")
	for c in candidates:
		if tm.has(str(c)) and str(tm.get(str(c))) != "":
			return {"trigger_id": str(tm.get(str(c))),
				"event": str(c), "profile_id": str(p.get("profile_id", "")),
				"reason": reason}
	return {}

func _make_evidence(p: Dictionary, binding: Dictionary, mode: String,
		status: String, identity: String, confidence: float, spoofed: bool,
		trig: Dictionary) -> Dictionary:
	var support := 4
	if spoofed or str(p.get("status", "")) in ["captured", "spoofed"]:
		support = 3
	elif confidence < 0.6:
		support = 3
	var target_id := str(binding.get("entity_id", ""))
	if target_id == "":
		target_id = str(binding.get("facility_id", ""))
	if target_id == "":
		target_id = str(p.get("profile_id", ""))
	_evidence_seq += 1
	var ev := {"schema": EVIDENCE_SCHEMA, "kind": "evidence",
		"evidence_id": "TEV-%06d" % _evidence_seq,
		"event_id": "TEV-%06d" % _evidence_seq,
		"t": t, "evidence_type": "iff", "target_id": target_id,
		"support": support, "identity": identity, "threat": "",
		"spoofed": spoofed, "confidence": confidence,
		"transponder_code": str(p.get("transponder_code", "")),
		"registration_code": str(p.get("registration_code", "")),
		"facility_id": str(binding.get("facility_id", "")),
		"facility_code": str(binding.get("facility_code", "")),
		"mode": mode, "status": status,
		"trigger_id": str(trig.get("trigger_id", "")) if trig is Dictionary else "",
		"source": "transponder_service", "writes_v15": false,
		"level_decided": false, "produces_contact": false}
	evidence.append(ev.duplicate(true))
	while evidence.size() > MAX_EVENTS:
		evidence.pop_front()
	_outbox.append(ev.duplicate(true))
	return ev

# ── 广播 / 被动监听 ───────────────────────────────────────────

## 广播（station_beacon/adsb_like）；舰只可静默。opts.profile_id 过滤。
func broadcast(opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: TransponderService 未 ready")
	var o: Dictionary = opts if opts is Dictionary else {}
	var only := str(o.get("profile_id", ""))
	var rows: Array = []
	var evs: Array = []
	for pid in profile_ids():
		if only != "" and str(pid) != only:
			continue
		var p: Dictionary = profiles[pid]
		if bool(p.get("silent", false)):
			continue
		var bc: Dictionary = p.get("broadcast", {}) if p.get("broadcast") is Dictionary else {}
		if not bool(bc.get("enabled", false)):
			continue
		if str(p.get("status", "")) != "normal":
			continue
		var bmodes: Array = bc.get("modes", []) if bc.get("modes") is Array else []
		var mode := ""
		for m in bmodes:
			if str(m) in (p.get("modes", []) as Array):
				mode = str(m)
				break
		if mode == "":
			continue
		var binding: Dictionary = _binding_of(p)
		var row := {"schema": "transponder_broadcast.v1", "t": t,
			"profile_id": str(pid), "entity_type": str(p.get("entity_type", "")),
			"mode": mode, "status": "normal",
			"binding": binding.duplicate(true),
			"transponder_code": str(p.get("transponder_code", "")),
			"registration_code": str(p.get("registration_code", "")),
			"facility_code": str(p.get("facility_code", "")),
			"identity": str(p.get("identity", "unknown")),
			"trigger": null, "writes_v15": false}
		rows.append(row)
		evs.append(_make_evidence(p, binding, mode, "normal",
			str(p.get("identity", "unknown")), 1.0, false, {}))
		_emit("broadcast", {"profile_id": str(pid), "mode": mode,
			"transponder_code": str(p.get("transponder_code", ""))})
	return {"ok": true, "broadcasts": rows, "evidence": evs,
		"events": take_events()}

## 被动监听：等同广播采集（不主动询问）；opts.profile_id 过滤。
func passive_listen(opts := {}) -> Dictionary:
	var r: Dictionary = broadcast(opts)
	r["passive"] = true
	return r

# ── 事件 / VM / save ──────────────────────────────────────────

func _emit(kind: String, payload: Dictionary) -> Dictionary:
	_event_seq += 1
	var trig_id := str(payload.get("trigger_id", ""))
	if trig_id != "":
		triggers.append({"trigger_id": trig_id, "event": kind,
			"target_id": str(payload.get("target_id", "")),
			"reason": str(payload.get("reason", ""))})
		while triggers.size() > MAX_EVENTS:
			triggers.pop_front()
	var ev := {"schema": EVENT_SCHEMA, "seq": _event_seq,
		"event_id": "TXP-EV-%06d" % _event_seq, "t": t, "kind": kind,
		"payload": payload.duplicate(true), "trigger_id": trig_id,
		"shadow": true, "writes_v15": false}
	events.append(ev.duplicate(true))
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))
	while _outbox.size() > MAX_OUTBOX:
		_outbox.pop_front()
	return ev

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out: Array = _outbox.duplicate(true)
	_outbox = []
	return out

func trigger_ids() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for raw in triggers:
		if raw is Dictionary:
			var tid := str((raw as Dictionary).get("trigger_id", ""))
			if tid != "" and not seen.has(tid):
				seen[tid] = true
				out.append(tid)
	out.sort()
	return out

func vm() -> Dictionary:
	var profiles_out: Array = []
	for pid in profile_ids():
		profiles_out.append((profiles[pid] as Dictionary).duplicate(true))
	var events_out: Array = []
	var start := maxi(0, events.size() - 64)
	for i in range(start, events.size()):
		events_out.append((events[i] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "ready": ready, "t": t,
		"profiles": profiles_out, "profile_count": profiles_out.size(),
		"jam": jam.duplicate(true), "jam_global": jam_global,
		"occlusion": occlusion.duplicate(true), "occlusion_global": occlusion_global,
		"events": events_out, "evidence": evidence.duplicate(true),
		"triggers": triggers.duplicate(true), "trigger_ids": trigger_ids(),
		"writes": {"world": false, "track_table": false, "v15": false, "ui": false}}

func summary() -> Dictionary:
	var by_type: Dictionary = {}
	for pid in profile_ids():
		var et := str((profiles[pid] as Dictionary).get("entity_type", ""))
		by_type[et] = int(by_type.get(et, 0)) + 1
	return {"schema": SCHEMA, "ready": ready, "t": t,
		"profiles": profiles.size(), "by_type": by_type,
		"events": events.size(), "evidence": evidence.size(),
		"triggers": trigger_ids(), "writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	var profs: Array = []
	for pid in profile_ids():
		profs.append((profiles[pid] as Dictionary).duplicate(true))
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION, "t": t,
		"profiles": JSON.parse_string(JSON.stringify(profs)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"evidence": JSON.parse_string(JSON.stringify(evidence)),
		"triggers": JSON.parse_string(JSON.stringify(triggers)),
		"jam": JSON.parse_string(JSON.stringify(jam)),
		"jam_global": jam_global,
		"occlusion": JSON.parse_string(JSON.stringify(occlusion)),
		"occlusion_global": occlusion_global,
		"seq": {"event": _event_seq, "evidence": _evidence_seq},
		"content_path": content_path})

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
	var profs = d.get("profiles", null)
	if not (profs is Array) or (profs as Array).is_empty():
		return _fail("invalid_payload", "load: profiles 缺失")
	# 校验所有 profile；成功后再应用
	var test := {"schema": CONTENT_SCHEMA, "version": VERSION, "profiles": profs}
	var v: Dictionary = validate_content(test)
	if not bool(v.get("ok", false)):
		return _fail("invalid_payload", "load: profile 校验失败：" + str(v.get("errors", [])))
	var new_profiles: Dictionary = {}
	var new_order: Array = []
	for raw in (profs as Array):
		if raw is Dictionary:
			var p: Dictionary = raw
			var pid := str(p.get("profile_id", ""))
			new_profiles[pid] = p.duplicate(true)
			new_order.append(pid)
	new_order.sort()
	profiles = new_profiles
	profile_order = new_order
	t = float(d.get("t", 0.0))
	events = (d.get("events", []) as Array).duplicate(true) if d.get("events") is Array else []
	evidence = (d.get("evidence", []) as Array).duplicate(true) if d.get("evidence") is Array else []
	triggers = (d.get("triggers", []) as Array).duplicate(true) if d.get("triggers") is Array else []
	jam = (d.get("jam", {}) as Dictionary).duplicate(true) if d.get("jam") is Dictionary else {}
	jam_global = clampf(float(d.get("jam_global", 0.0)), 0.0, 1.0)
	occlusion = (d.get("occlusion", {}) as Dictionary).duplicate(true) \
		if d.get("occlusion") is Dictionary else {}
	occlusion_global = bool(d.get("occlusion_global", false))
	var seq: Dictionary = d.get("seq", {}) if d.get("seq") is Dictionary else {}
	_event_seq = int(seq.get("event", events.size()))
	_evidence_seq = int(seq.get("evidence", evidence.size()))
	_outbox = []
	_check_contracts()
	return {"ok": true, "profiles": profiles.size(),
		"events": events.size(), "evidence": evidence.size()}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	for pid in profiles.keys():
		var p: Dictionary = profiles[pid]
		if not (str(p.get("status", "")) in STATUSES):
			v.append("profile %s status 非法" % str(pid))
		if not (str(p.get("entity_type", "")) in ENTITY_TYPES):
			v.append("profile %s entity_type 非法" % str(pid))
		if str(p.get("transponder_code", "")) == "":
			v.append("profile %s code 空" % str(pid))
		if not (p.get("modes") is Array) or (p.get("modes") as Array).is_empty():
			v.append("profile %s modes 空" % str(pid))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("TransponderService 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
