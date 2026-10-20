class_name V2SignalService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3K · ELINT / 可见光灯语服务
#
# ELINT：
#   * 被动截获 emitter（雷达/通信/数据链）、单站 DF(L1)、多站交叉候选；
#   * 指纹/型号/置信度、LPI/加密元数据；不判身份；
#   * 输出 observation/evidence/事件，不写 TrackTable/world。
# 可见光灯语：
#   * 内容驱动代码表（四位/模式/含义），发送/接收/确认/超时/遮挡/误读；
#   * 与通信服务（CommsService）区分；输出 light_signal 事件。
# ═══════════════════════════════════════════════════════════════════

const InfoWarfare := preload("res://framework/sim/information_warfare.gd")
const DEFAULT_CODES := "res://framework/content/light_codes_l1.json"
const SCHEMA_VM := "signal_service.v1"
const SCHEMA_OBS := "sensor_observation.v1"
const SCHEMA_EVIDENCE := "track_evidence.v1"
const SCHEMA_LIGHT := "light_signal.v1"
const SCHEMA_EVENT := "signal_event.v1"
const SAVE_SCHEMA := "v17.signal_service_save.v1"
const SAVE_VERSION := "1.0.0"
const MAX_SIGNALS := 400
const MAX_EVENTS := 600
const MAX_TX := 200

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var observer: Dictionary = {}
var stations: Array = []
var targets: Array = []
var config: Dictionary = {}
var errors: Array = []
var warnings: Array = []

var code_content: Dictionary = {}
var codes: Dictionary = {}
var code_ids: Array = []
var defaults: Dictionary = {}
var transmissions: Array = []
var elint_signals: Array = []
var comms_signals: Array = []
var fingerprints: Array = []
var candidates: Array = []
var observations: Array = []
var evidence: Array = []
var misses: Array = []
var events: Array = []

var _iw = null
var _seen_signal_ids: Dictionary = {}
var _seen_fingerprints: Dictionary = {}
var _seen_comint: Dictionary = {}
var _seq_obs := 0
var _seq_evidence := 0
var _seq_event := 0
var _seq_fix := 0
var _seq_tx := 0
var _outbox: Array = []
var _last_df_l1: Array = []
var _targets_by_id: Dictionary = {}


func _init(cfg := {}) -> void:
	setup(cfg)


# ── setup / content ───────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	elint_signals = []
	comms_signals = []
	fingerprints = []
	candidates = []
	observations = []
	evidence = []
	misses = []
	events = []
	transmissions = []
	_outbox = []
	_seen_signal_ids = {}
	_seen_fingerprints = {}
	_seen_comint = {}
	_seq_obs = 0
	_seq_evidence = 0
	_seq_event = 0
	_seq_fix = 0
	_seq_tx = 0
	_last_df_l1 = []
	_targets_by_id = {}
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
	_reindex_targets()
	stations = []
	if config.get("stations") is Array:
		for raw in (config.get("stations") as Array):
			if raw is Dictionary:
				stations.append((raw as Dictionary).duplicate(true))
	if stations.is_empty():
		stations = [_default_station(String(observer.get("id", "observer")) + "-ELINT",
			observer.get("pos_km", [0.0, 0.0, 0.0]))]
	# 内容：灯语代码表
	var path := String(config.get("codes_path", DEFAULT_CODES))
	code_content = {}
	if config.get("codes_content") is Dictionary and not (config.get("codes_content") as Dictionary).is_empty():
		code_content = (config.get("codes_content") as Dictionary).duplicate(true)
	else:
		if not FileAccess.file_exists(path):
			errors.append("light codes content 不存在: " + path)
			return false
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			errors.append("light codes content 不可读: " + path)
			return false
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			errors.append("light codes JSON 无效: " + path)
			return false
		code_content = parsed
	var cv := validate_codes(code_content)
	if not bool(cv.get("ok", false)):
		for e in (cv.get("errors", []) as Array):
			errors.append("light codes: " + String(e))
		return false
	defaults = (code_content.get("defaults", {}) as Dictionary).duplicate(true) if code_content.get("defaults") is Dictionary else {}
	for raw in (code_content.get("codes", []) as Array):
		if raw is Dictionary:
			var c: Dictionary = (raw as Dictionary).duplicate(true)
			codes[String(c.get("id", ""))] = c
			code_ids.append(String(c.get("id", "")))
	if code_ids.is_empty():
		errors.append("light codes 无有效 code")
		return false
	# ELINT（复用 V2InformationWarfare：只启用被动 ELINT，关闭 IFF 主动询问）
	_iw = InfoWarfare.new()
	var elint_cfg: Dictionary = (config.get("elint", {}) as Dictionary).duplicate(true) if config.get("elint") is Dictionary else {}
	if not elint_cfg.has("enabled"):
		elint_cfg["enabled"] = true
	var ok: bool = _iw.setup({
		"observer_id": String(observer.get("id", "harmattan")),
		"observer": observer.duplicate(true),
		"targets": targets.duplicate(true),
		"stations": stations.duplicate(true),
		"iff": {"enabled": false},
		"elint": elint_cfg,
	})
	if not ok:
		errors.append("ELINT setup 失败: " + str(_iw.errors))
		warnings.append("signal service 仍可提供灯语接口，但无 ELINT")
	ready = errors.is_empty()
	if ready:
		# 初始化时主动/被动扫描一次（后续 step/intercept 再采集新信号）
		_iw.scan_elint(true)
		_iw.step(0.0)
		_collect_elint()
		_push_event("service_ready", {"elint": elint_signals.size(), "codes": codes.size()})
	return ready


func _default_station(id: String, pos: Array) -> Dictionary:
	return {"id": id, "model": "ELINT", "pos_km": pos,
		"enabled": true, "sigma_bearing_deg": 1.0}


func validate_codes(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["light codes 必须是对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != "light_codes.v1":
		errs.append("schema 必须 light_codes.v1")
	var arr = d.get("codes", null)
	if not (arr is Array) or (arr as Array).is_empty():
		errs.append("codes 必须为非空数组")
		return {"ok": false, "errors": errs}
	var modes: Array = ["blink", "steady"]
	if d.get("defaults") is Dictionary and (d.get("defaults") as Dictionary).get("modes") is Array:
		modes = (d.get("defaults") as Dictionary).get("modes") as Array
	var ids: Dictionary = {}
	for i in range((arr as Array).size()):
		var raw = (arr as Array)[i]
		if not (raw is Dictionary):
			errs.append("codes[%d] 必须对象" % i)
			continue
		var c: Dictionary = raw
		var cid := String(c.get("id", ""))
		if cid == "":
			errs.append("codes[%d] 缺 id" % i)
		elif ids.has(cid):
			errs.append("codes 重复 id: " + cid)
		else:
			ids[cid] = true
		var code := String(c.get("code", ""))
		if code.length() != 4 or not code.is_valid_int():
			errs.append("code %s 必须是 4 位数字" % cid)
		if not (String(c.get("mode", "")) in modes):
			errs.append("code %s mode 非法" % cid)
		if String(c.get("meaning", "")) == "":
			errs.append("code %s 缺 meaning" % cid)
	return {"ok": errs.is_empty(), "errors": errs}


func _reindex_targets() -> void:
	_targets_by_id = {}
	for raw in targets:
		if raw is Dictionary:
			var d: Dictionary = raw
			_targets_by_id[String(d.get("id", d.get("target_id", "")))] = d


func _target(id: String) -> Dictionary:
	if _targets_by_id.has(id):
		return _targets_by_id[id]
	return {}


# ── ELINT ─────────────────────────────────────────────────────

## 被动截获：雷达/IFF/LIDAR（ELINT）+ 通信/数据链元数据（COMINT）。
func intercept(target_id := "", _opts := {}) -> Dictionary:
	if _iw == null:
		return {"ok": false, "reason": "elint_unavailable", "signals": []}
	_iw.t = t
	_iw.scan_elint(true)
	_iw.step(0.0)
	_collect_elint()
	var out: Array = []
	for raw in elint_signals:
		if raw is Dictionary and (target_id == "" or String((raw as Dictionary).get("source_id", "")) == target_id):
			out.append((raw as Dictionary).duplicate(true))
	var comms_out: Array = []
	for raw in comms_signals:
		if raw is Dictionary and (target_id == "" or String((raw as Dictionary).get("source_id", "")) == target_id):
			comms_out.append((raw as Dictionary).duplicate(true))
	if out.is_empty() and comms_out.is_empty():
		var reason := "no_signal"
		for raw in misses:
			if raw is Dictionary and String((raw as Dictionary).get("source_id", "")) == target_id:
				reason = String(raw.get("reason", "no_signal"))
				break
		return {"ok": false, "reason": reason, "target_id": target_id,
			"signals": [], "observations": [], "fingerprints": [], "misses": misses.duplicate(true)}
	var obs_out: Array = []
	var fp_out: Array = []
	for raw in out:
		for o in observations:
			if o is Dictionary and String((o as Dictionary).get("target_id", "")) == String((raw as Dictionary).get("source_id", "")):
				obs_out.append((o as Dictionary).duplicate(true))
		for f in fingerprints:
			if f is Dictionary and String((f as Dictionary).get("target_id", "")) == String((raw as Dictionary).get("source_id", "")):
				fp_out.append((f as Dictionary).duplicate(true))
	return {"ok": true, "reason": "", "target_id": target_id,
		"signals": out, "comms": comms_out, "observations": obs_out, "fingerprints": fp_out,
		"count": out.size() + comms_out.size(), "misses": []}


## DF：单站 L1 方位线 + 多站交叉候选（不自动成为 contact）。
func df(target_id := "") -> Dictionary:
	if _iw == null:
		return {"ok": false, "reason": "elint_unavailable", "l1": [], "candidates": []}
	var l1: Array = []
	for raw in elint_signals:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		if target_id != "" and String(s.get("source_id", "")) != target_id:
			continue
		l1.append({"kind": "df_l1", "source_id": String(s.get("source_id", "")),
			"station_id": String(s.get("station_id", "")),
			"bearing_deg": float(s.get("bearing_deg", 0.0)),
			"bearing_sigma_deg": float(s.get("bearing_sigma_deg", 1.0)),
			"freq_mhz": float(s.get("freq_mhz", 0.0)),
			"fingerprint": String(s.get("signature", "")),
			"confidence": float(s.get("confidence", 0.0)),
			"level_support": 1, "position_km": [], "produces_contact": false,
			"identity": "unknown"})
	_last_df_l1 = l1.duplicate(true)
	var new_candidates: Array = []
	var raw_cands: Array = _iw.triangulate_all()
	for raw in raw_cands:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if target_id != "" and String(c.get("source_id", "")) != target_id:
			continue
		var known := false
		for old in candidates:
			if old is Dictionary and JSON.stringify(old.get("raw", {})) == JSON.stringify(c):
				known = true
				break
		if known:
			continue
		_seq_fix += 1
		var f: Dictionary = c.duplicate(true)
		f["fix_id"] = "FIX-%06d" % _seq_fix
		f["candidate"] = true
		f["provisional"] = true
		f["requires_confirmation"] = true
		f["identity"] = "unknown"
		f["raw"] = c.duplicate(true)
		f["level_support"] = 2
		f["produces_contact"] = false
		candidates.append(f)
		new_candidates.append(f.duplicate(true))
		_emit_evidence({
			"evidence_type": "elint_fix", "support": 2, "target_id": String(f.get("source_id", "")),
			"fix_id": String(f.get("fix_id", "")), "position_km": f.get("pos_km", []),
			"sigma_range_km": float(f.get("sigma_range_km", 0.0)),
			"confidence": float(f.get("confidence", 0.0)),
			"identity": "unknown", "requires_confirmation": true,
			"produces_contact": false, "produces_position": false,
			"raw": f.get("raw", {}),
		})
	if l1.is_empty() and candidates.is_empty():
		return {"ok": false, "reason": "no_signal", "l1": [], "candidates": []}
	return {"ok": true, "reason": "", "target_id": target_id,
		"l1": l1, "candidates": new_candidates,
		"candidate_count": candidates.size(),
		"single_station": l1.size() > 0 and candidates.is_empty(),
		"multi_station": candidates.size() > 0}


## 解析 FIX 候选 → evidence（只给候选/证据，不建立 contact/身份）。
func resolve(id: String) -> Dictionary:
	if id == "":
		return {"ok": false, "reason": "empty_id"}
	for raw in candidates:
		if raw is Dictionary and String((raw as Dictionary).get("fix_id", "")) == id:
			var f: Dictionary = raw
			return {"ok": true, "reason": "", "type": "elint_fix",
				"fix_id": id, "target_id": String(f.get("source_id", "")),
				"position_km": f.get("pos_km", []),
				"identity": "unknown", "level_support": 2,
				"requires_confirmation": true,
				"produces_contact": false, "produces_position": false}
	for raw in transmissions:
		if raw is Dictionary and String((raw as Dictionary).get("tx_id", "")) == id:
			return resolve_light(id)
	return {"ok": false, "reason": "unknown_id", "id": id}


func _collect_elint() -> void:
	if _iw == null:
		return
	if _iw.misses is Array:
		misses = (_iw.misses as Array).duplicate(true)
	for raw in _iw.signals:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		if not bool(s.get("detected", false)):
			continue
		var sid := String(s.get("id", ""))
		if sid == "" or _seen_signal_ids.has(sid):
			continue
		_seen_signal_ids[sid] = true
		elint_signals.append(s.duplicate(true))
		while elint_signals.size() > MAX_SIGNALS:
			elint_signals.pop_front()
		_emit_observation({
			"sensor": "elint", "target_id": String(s.get("source_id", "")),
			"station_id": String(s.get("station_id", "")),
			"bearing_deg": float(s.get("bearing_deg", 0.0)),
			"bearing_sigma_deg": float(s.get("bearing_sigma_deg", 1.0)),
			"freq_mhz": float(s.get("freq_mhz", 0.0)),
			"band": String(s.get("band", "")),
			"signature": String(s.get("signature", "")),
			"class_hint": String(s.get("class_hint", "")),
			"matched": bool(s.get("matched", false)),
			"confidence": float(s.get("confidence", 0.0)),
			"lpi": bool(s.get("lpi", false)),
			"spoof_flags": s.get("spoof_flags", []),
			"snr_db": float(s.get("snr_db", 0.0)),
			"level_support": 1, "produces_contact": false,
			"provenance": "signal_service/elint",
		})
		var fp := String(s.get("signature", ""))
		var fp_key := String(s.get("source_id", "")) + "|" + fp
		if fp != "" and not _seen_fingerprints.has(fp_key):
			_seen_fingerprints[fp_key] = true
			var fpe := {"fingerprint": fp, "target_id": String(s.get("source_id", "")),
				"emitter_model": String(s.get("emitter_model", "")),
				"class_hint": String(s.get("class_hint", "")),
				"confidence": float(s.get("confidence", 0.0)),
				"level_support": int(s.get("level_support", 3)),
				"matched": true, "identity": "unknown", "produces_contact": false}
			fingerprints.append(fpe)
			_emit_evidence({
				"evidence_type": "elint", "support": int(s.get("level_support", 3)),
				"target_id": String(s.get("source_id", "")),
				"fingerprint": fp, "emitter_model": String(s.get("emitter_model", "")),
				"class_hint": String(s.get("class_hint", "")),
				"confidence": float(s.get("confidence", 0.0)),
				"identity": "unknown", "produces_contact": false,
				"produces_position": false, "matched": true,
			})
	# COMINT（通信/数据链）：只给元数据；加密不解码
	for raw in _iw.comint_events:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := String(c.get("id", ""))
		if cid == "" or _seen_comint.has(cid):
			continue
		_seen_comint[cid] = true
		var meta: Dictionary = c.get("comms_content", {}) if c.get("comms_content") is Dictionary else {}
		comms_signals.append({"source_id": String(c.get("from", "")),
			"comms_mode": String(c.get("comms_mode", "")),
			"frequency_mhz": float(c.get("frequency_mhz", 0.0)),
			"encrypted": bool(c.get("encrypted", false)),
			"sensor": "elint.comms", "detected": true,
			"content_redacted": bool(c.get("encrypted", false)),
			"metadata_only": bool(meta.get("metadata_only", false))})
		_emit_observation({
			"sensor": "elint.comms", "target_id": String(c.get("from", "")),
			"comms_mode": String(c.get("comms_mode", "")),
			"frequency_mhz": float(c.get("frequency_mhz", 0.0)),
			"distance_km": float(c.get("distance_km", 0.0)),
			"encrypted": bool(c.get("encrypted", false)),
			"decode_attempted": false,
			"metadata_only": bool(meta.get("metadata_only", false)),
			"content_redacted": bool(c.get("encrypted", false)),
			"level_support": 1, "produces_contact": false,
			"provenance": "signal_service/comint",
		})


func _emit_observation(extra: Dictionary) -> void:
	_seq_obs += 1
	var obs := {"schema": SCHEMA_OBS, "kind": "observation",
		"event_id": "SOBS-%06d" % _seq_obs, "t": t,
		"observer_id": String(observer.get("id", "")), "level_decided": false,
		"produces_contact": false, "writes_v15": false,
		"relay": false, "comms_content": null}
	for k in extra.keys():
		obs[k] = extra[k]
	observations.append(obs)
	while observations.size() > MAX_SIGNALS:
		observations.pop_front()
	events.append(obs.duplicate(true))
	_outbox.append(obs.duplicate(true))


func _emit_evidence(extra: Dictionary) -> void:
	_seq_evidence += 1
	var ev := {"schema": SCHEMA_EVIDENCE, "kind": "evidence",
		"event_id": "SEVD-%06d" % _seq_evidence, "evidence_id": "SEVD-%06d" % _seq_evidence,
		"t": t, "observer_id": String(observer.get("id", "")),
		"support": 3, "identity": "unknown", "level_decided": false,
		"produces_contact": false, "writes_v15": false}
	for k in extra.keys():
		ev[k] = extra[k]
	if String(ev.get("evidence_type", "")) == "elint_fix":
		ev["support"] = 2
	evidence.append(ev.duplicate(true))
	while evidence.size() > MAX_SIGNALS:
		evidence.pop_front()
	events.append(ev.duplicate(true))
	_outbox.append(ev.duplicate(true))


# ── 可见光灯语 ─────────────────────────────────────────────────

func _code(code_id: String) -> Dictionary:
	return (codes.get(code_id, {}) as Dictionary).duplicate(true) if codes.get(code_id) is Dictionary else {}


func _range_to_target(target_id: String) -> float:
	var tr := _target(target_id)
	if tr.is_empty() or not (tr.get("pos_km") is Array):
		return -1.0
	var pos := tr.get("pos_km") as Array
	if pos.size() < 3:
		return -1.0
	var a := Vector3(float(observer.get("pos_km", [0, 0, 0])[0]),
		float(observer.get("pos_km", [0, 0, 0])[1]),
		float(observer.get("pos_km", [0, 0, 0])[2])) if observer.get("pos_km") is Array else Vector3.ZERO
	var b := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return a.distance_to(b)


func light_send(code_id: String, target_id: String, opts := {}) -> Dictionary:
	var c := _code(code_id)
	if c.is_empty():
		return {"ok": false, "reason": "unknown_code", "code_id": code_id}
	if target_id == "":
		return {"ok": false, "reason": "empty_target"}
	var tr := _target(target_id)
	if tr.is_empty():
		return {"ok": false, "reason": "unknown_target", "target_id": target_id}
	var o: Dictionary = opts if opts is Dictionary else {}
	var range_km := _range_to_target(target_id)
	var max_range := float(o.get("range_km", defaults.get("range_km", 50.0)))
	if range_km > max_range + 1.0e-9:
		return {"ok": false, "reason": "out_of_range", "range_km": range_km,
			"max_range_km": max_range}
	if bool(o.get("occluded", false)) or bool(tr.get("occluded", false)) or not bool(o.get("los", true)):
		return {"ok": false, "reason": "occluded", "target_id": target_id}
	var timeout := float(o.get("timeout_s", defaults.get("timeout_s", 30.0)))
	_seq_tx += 1
	var tx := {
		"schema": SCHEMA_LIGHT, "tx_id": "TX-%06d" % _seq_tx,
		"code_id": code_id, "code": String(c.get("code", "")),
		"mode": String(c.get("mode", "")), "meaning": String(c.get("meaning", "")),
		"category": String(c.get("category", "")),
		"scenario_tags": c.get("scenario_tags", []),
		"target_id": target_id, "sender_id": String(observer.get("id", "")),
		"sent_t": t, "expires_t": t + maxf(1.0, timeout),
		"timeout_s": timeout, "range_km": range_km,
		"ack_required": bool(c.get("ack_required", defaults.get("ack_required", true))),
		"status": "SENT", "received_t": -1.0, "acked_t": -1.0,
		"received_code": "", "misread": false, "reason": "",
	}
	transmissions.append(tx)
	while transmissions.size() > MAX_TX:
		transmissions.pop_front()
	_push_event("light_send", {"tx_id": tx["tx_id"], "code_id": code_id,
		"target_id": target_id, "mode": tx["mode"]})
	return {"ok": true, "reason": "", "tx": tx.duplicate(true), "tx_id": String(tx["tx_id"])}


func light_receive(tx_id: String, opts := {}) -> Dictionary:
	var tx = _find_tx(tx_id)
	if tx == null:
		return {"ok": false, "reason": "unknown_tx", "tx_id": tx_id}
	var rec: Dictionary = tx
	if String(rec.get("status", "")) != "SENT":
		return {"ok": false, "reason": "not_sent", "status": String(rec.get("status", ""))}
	if t + 1.0e-9 >= float(rec.get("expires_t", 0.0)):
		rec["status"] = "TIMEOUT"
		rec["reason"] = "timeout"
		_push_event("light_timeout", {"tx_id": tx_id, "reason": "timeout"})
		return {"ok": false, "reason": "timeout", "tx": rec.duplicate(true)}
	var o: Dictionary = opts if opts is Dictionary else {}
	if bool(o.get("occluded", false)):
		rec["status"] = "OCCLUDED"
		rec["reason"] = "occluded"
		_push_event("light_occluded", {"tx_id": tx_id})
		return {"ok": false, "reason": "occluded", "tx": rec.duplicate(true)}
	var misread_chance := float(o.get("misread_chance", defaults.get("misread_chance", 0.02)))
	var misread := bool(o.get("misread", false))
	if not misread and misread_chance > 0.0:
		misread = _roll("LIGHT|" + tx_id) < misread_chance
	if misread:
		rec["status"] = "MISREAD"
		rec["misread"] = true
		rec["received_code"] = "????"
		rec["reason"] = "misread"
		_push_event("light_misread", {"tx_id": tx_id, "expected": String(rec.get("code", ""))})
		return {"ok": false, "reason": "misread", "misread": true,
			"received_code": "????", "tx": rec.duplicate(true)}
	var code := String(rec.get("code", ""))
	rec["status"] = "RECEIVED"
	rec["received_t"] = t
	rec["received_code"] = code
	rec["reason"] = ""
	_push_event("light_receive", {"tx_id": tx_id, "code_id": String(rec.get("code_id", "")),
		"target_id": String(rec.get("target_id", "")), "code": code})
	return {"ok": true, "reason": "", "code": code,
		"meaning": String(rec.get("meaning", "")), "tx": rec.duplicate(true)}


func light_ack(tx_id: String) -> Dictionary:
	var tx = _find_tx(tx_id)
	if tx == null:
		return {"ok": false, "reason": "unknown_tx"}
	var rec: Dictionary = tx
	if String(rec.get("status", "")) != "RECEIVED":
		return {"ok": false, "reason": "not_received", "status": String(rec.get("status", ""))}
	if bool(rec.get("ack_required", false)) and t + 1.0e-9 >= float(rec.get("expires_t", 0.0)):
		rec["status"] = "TIMEOUT"
		rec["reason"] = "ack_timeout"
		_push_event("light_timeout", {"tx_id": tx_id, "reason": "ack_timeout"})
		return {"ok": false, "reason": "timeout", "tx": rec.duplicate(true)}
	rec["status"] = "ACKED"
	rec["acked_t"] = t
	rec["reason"] = ""
	_push_event("light_ack", {"tx_id": tx_id, "code_id": String(rec.get("code_id", ""))})
	return {"ok": true, "reason": "", "tx": rec.duplicate(true)}


func resolve_light(tx_id: String) -> Dictionary:
	var tx = _find_tx(tx_id)
	if tx == null:
		return {"ok": false, "reason": "unknown_tx"}
	var rec: Dictionary = tx
	if String(rec.get("status", "")) in ["SENT", "RECEIVED"] and t + 1.0e-9 >= float(rec.get("expires_t", 0.0)):
		rec["status"] = "TIMEOUT"
		rec["reason"] = "timeout"
		_push_event("light_timeout", {"tx_id": tx_id, "reason": "timeout"})
	return {"ok": true, "tx": rec.duplicate(true), "status": String(rec.get("status", "")),
		"requires_ack": bool(rec.get("ack_required", false)),
		"ack_pending": String(rec.get("status", "")) == "RECEIVED" and bool(rec.get("ack_required", false))}


func _find_tx(tx_id: String):
	for raw in transmissions:
		if raw is Dictionary and String((raw as Dictionary).get("tx_id", "")) == tx_id:
			return raw
	return null


func light_transmissions() -> Array:
	var out: Array = []
	for raw in transmissions:
		out.append((raw as Dictionary).duplicate(true))
	return out


# ── step / 超时 ────────────────────────────────────────────────

func step(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	if _iw != null:
		_iw.t = t
		_iw.step(0.0)
		_iw.scan_elint(true)
		_collect_elint()
	_update_timeouts()
	return vm()


func _update_timeouts() -> void:
	for raw in transmissions:
		if not (raw is Dictionary):
			continue
		var tx: Dictionary = raw
		if String(tx.get("status", "")) in ["SENT", "RECEIVED"] \
				and t + 1.0e-9 >= float(tx.get("expires_t", 0.0)):
			tx["status"] = "TIMEOUT"
			tx["reason"] = "timeout"
			_push_event("light_timeout", {"tx_id": String(tx.get("tx_id", "")), "reason": "timeout"})


# ── VM / save ─────────────────────────────────────────────────

func vm() -> Dictionary:
	var elint := {
		"signals": elint_signals.duplicate(true),
		"fingerprints": fingerprints.duplicate(true),
		"misses": misses.duplicate(true),
		"df_l1": _last_df_l1.duplicate(true),
		"candidates": candidates.duplicate(true),
		"observations": observations.duplicate(true),
		"evidence": evidence.duplicate(true),
		"comms": comms_signals.duplicate(true),
		"counts": {"signals": elint_signals.size(), "comms": comms_signals.size(), "fingerprints": fingerprints.size(),
			"candidates": candidates.size(), "observations": observations.size(),
			"evidence": evidence.size()},
	}
	var light := {
		"codes": code_ids.duplicate(),
		"codes_count": code_ids.size(),
		"example_codes": _example_codes(),
		"transmissions": light_transmissions(),
		"defaults": defaults.duplicate(true),
		"counts": {"transmissions": transmissions.size(),
			"sent": _count_tx("SENT"), "received": _count_tx("RECEIVED"),
			"acked": _count_tx("ACKED"), "timeout": _count_tx("TIMEOUT"),
			"occluded": _count_tx("OCCLUDED"), "misread": _count_tx("MISREAD")},
	}
	return {
		"schema": SCHEMA_VM, "mode": "shadow", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"observer": observer.duplicate(true), "stations": stations.duplicate(true),
		"targets": targets.duplicate(true),
		"elint": elint, "light": light,
		"observations": observations.duplicate(true), "evidence": evidence.duplicate(true),
		"events": events.duplicate(true),
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"track_table": false, "world": false, "v15": false, "ui": false},
	}


func _example_codes() -> Array:
	var out: Array = []
	for id in code_ids:
		var c: Dictionary = codes[id]
		if (c.get("scenario_tags", []) as Array).has("gushen2"):
			out.append({"id": id, "code": String(c.get("code", "")),
				"mode": String(c.get("mode", "")), "meaning": String(c.get("meaning", ""))})
	return out


func _count_tx(status: String) -> int:
	var n := 0
	for raw in transmissions:
		if raw is Dictionary and String((raw as Dictionary).get("status", "")) == status:
			n += 1
	return n


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t,
		"elint_signals": elint_signals.size(), "fingerprints": fingerprints.size(),
		"candidates": candidates.size(), "observations": observations.size(),
		"evidence": evidence.size(), "transmissions": transmissions.size(),
		"codes": code_ids.size(),
		"writes": {"track_table": false, "world": false, "v15": false}}


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


func _push_event(kind: String, payload := {}) -> void:
	_seq_event += 1
	var ev := {"schema": SCHEMA_EVENT, "seq": _seq_event, "t": t, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))


func _roll(seed_text: String) -> float:
	var h := int(hash(seed_text))
	return float((h & 0x7fffffff) % 1000000) / 1000000.0


func save_state() -> String:
	var payload := {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "t": t,
		"transmissions": light_transmissions(),
		"elint_signals": elint_signals.duplicate(true),
		"comms_signals": comms_signals.duplicate(true),
		"fingerprints": fingerprints.duplicate(true),
		"candidates": candidates.duplicate(true),
		"observations": observations.duplicate(true), "evidence": evidence.duplicate(true),
		"events": JSON.parse_string(JSON.stringify(events)),
		"seq": {"obs": _seq_obs, "evidence": _seq_evidence, "event": _seq_event,
			"fix": _seq_fix, "tx": _seq_tx},
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
	if not (p.get("transmissions") is Array) or not (p.get("elint_signals") is Array):
		return {"ok": false, "reason": "invalid_payload"}
	t = float(p.get("t", 0.0))
	transmissions = (p.get("transmissions") as Array).duplicate(true)
	elint_signals = (p.get("elint_signals") as Array).duplicate(true)
	comms_signals = (p.get("comms_signals") as Array).duplicate(true) if p.get("comms_signals") is Array else []
	fingerprints = (p.get("fingerprints") as Array).duplicate(true) if p.get("fingerprints") is Array else []
	candidates = (p.get("candidates") as Array).duplicate(true) if p.get("candidates") is Array else []
	observations = (p.get("observations") as Array).duplicate(true) if p.get("observations") is Array else []
	evidence = (p.get("evidence") as Array).duplicate(true) if p.get("evidence") is Array else []
	events = (p.get("events") as Array).duplicate(true) if p.get("events") is Array else []
	var seq: Dictionary = p.get("seq", {}) if p.get("seq") is Dictionary else {}
	_seq_obs = int(seq.get("obs", 0))
	_seq_evidence = int(seq.get("evidence", 0))
	_seq_event = int(seq.get("event", 0))
	_seq_fix = int(seq.get("fix", 0))
	_seq_tx = int(seq.get("tx", 0))
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	_outbox = []
	return {"ok": true, "reason": "", "t": t, "transmissions": transmissions.size()}
