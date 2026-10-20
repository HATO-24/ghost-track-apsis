extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3Y：IncidentRecordService（未来事故记录生成器；新文件）
#
# - 输入 FacilityRegistry/设施内容、2193-11-07 起时间窗、seed、各港群/设施
#   “33OSID 接管意愿强度” pressure 0..1；**NESOSS 全部排除**；
# - 确定性 RNG 不规则排程：间隔/站点/类型加权；高 pressure → 更高频率/
#   更短间隔；同一站点可多次事故；从开场时间向后延伸；
# - 每次事故生成三类记录：accident_log / telemetry（前后采样/缺口/异常/
#   编辑痕迹/hash）/ OTC traffic（track/transponder/clearance/handoff、
#   删除/改写/重复码），并派生 ghost_track_clues；
# - format_accident_text / format_telemetry_text / format_otc_text；
# - 不写 world/UI/V15；不伪造具体人物台词；只生成记录/日志格式文本。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.incident_record_service.v1"
const SAVE_SCHEMA := "v17.incident_record_save.v1"
const TEMPLATE_SCHEMA := "v17.incident_templates.v1"
const VERSION := "1.0.0"
const DEFAULT_TEMPLATES := "res://framework/content/incident_templates.json"
const DEFAULT_FACILITIES := "res://framework/content/facilities_system.json"
const OPENING_DATE := "2193-11-07"
const NESOSS_CLUSTER := "NESOSS"
const NESOSS_PREFIX := "FC-NESOSS"
const STANDARD_CHANNELS := ["pressure_kpa", "temperature_c", "power_kw", "flow_tph"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var templates: Dictionary = {}
var templates_path := DEFAULT_TEMPLATES
var facilities_content_path := DEFAULT_FACILITIES
var facilities: Array = []
var facilities_by_id: Dictionary = {}
var facilities_by_code: Dictionary = {}
var excluded: Array = []
var pressure_cfg: Dictionary = {}
var default_pressure := 0.5
var start_date := OPENING_DATE
var start_unix := 0
var horizon_days := 365.0
var seed_value := 2193

var _incidents: Array = []
var _clues: Array = []
var _by_id: Dictionary = {}
var _clue_seq := 0
var _incident_seq := 0
var _generated := false
var _rng := RandomNumberGenerator.new()
var _type_map: Dictionary = {}
var _schedule: Dictionary = {}
var _class_weights: Dictionary = {}
var _anomaly_patterns: Dictionary = {}
var _record_schema: Dictionary = {}

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup / load content ───────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	_incidents = []
	_clues = []
	_by_id = {}
	_clue_seq = 0
	_incident_seq = 0
	_generated = false
	var c: Dictionary = cfg if cfg is Dictionary else {}
	templates_path = str(c.get("templates_path", DEFAULT_TEMPLATES))
	facilities_content_path = str(c.get("facilities_content_path", DEFAULT_FACILITIES))
	templates = _read_json(templates_path)
	if templates.is_empty():
		errors.append("事故模板不可读：" + templates_path)
		return false
	var tv := validate_templates(templates)
	if not bool(tv.get("ok", false)):
		for e in (tv.get("errors", []) as Array):
			errors.append("templates: " + str(e))
		return false
	_apply_templates()
	# 设施：FacilityRegistry / facilities 数组 / 内容文件
	var facs: Array = []
	if c.get("facility_registry") != null:
		var reg = c.get("facility_registry")
		var rf = reg.get("facilities") if reg != null else null
		if rf is Array:
			facs = (rf as Array).duplicate(true)
		elif reg != null and reg.has_method("to_dict"):
			var rd: Dictionary = reg.to_dict()
			if rd.get("facilities") is Array:
				facs = (rd["facilities"] as Array).duplicate(true)
		if facs.is_empty():
			errors.append("facility_registry 无 facilities")
	elif c.get("facilities") is Array:
		facs = (c.get("facilities") as Array).duplicate(true)
	else:
		var fd: Dictionary = _read_json(facilities_content_path)
		if fd.get("facilities") is Array:
			facs = (fd["facilities"] as Array).duplicate(true)
		else:
			errors.append("设施内容不可读：" + facilities_content_path)
			return false
	if facs.is_empty():
		errors.append("设施列表为空")
		return false
	facilities = []
	facilities_by_id = {}
	facilities_by_code = {}
	excluded = []
	for raw in facs:
		if not (raw is Dictionary):
			continue
		var f: Dictionary = (raw as Dictionary).duplicate(true)
		var parent := str(f.get("parent_cluster", ""))
		var code := str(f.get("facility_code", ""))
		if parent == NESOSS_CLUSTER or code.begins_with(NESOSS_PREFIX) or code.contains("NESOSS"):
			excluded.append({"facility_id": str(f.get("facility_id", "")),
				"facility_code": code, "parent_cluster": parent,
				"reason": "NESOSS excluded"})
			continue
		if str(f.get("facility_id", "")) == "" or code == "":
			warnings.append("跳过无 id/code 的设施")
			continue
		facilities.append(f)
		facilities_by_id[str(f.get("facility_id", ""))] = f
		facilities_by_code[code] = f
	if facilities.is_empty():
		errors.append("排除 NESOSS 后无可用设施")
		return false
	start_date = str(c.get("start_date", OPENING_DATE))
	start_unix = int(Time.get_unix_time_from_datetime_string(start_date + "T00:00:00"))
	if start_unix <= 0:
		errors.append("start_date 非法：" + start_date)
		return false
	horizon_days = float(c.get("horizon_days", 365.0))
	if not is_finite(horizon_days) or horizon_days <= 0.0:
		errors.append("horizon_days 必须 >0")
		return false
	seed_value = int(c.get("seed", 2193))
	pressure_cfg = {}
	default_pressure = float(_schedule.get("default_pressure", 0.5))
	var pc = c.get("pressure", null)
	if pc is Dictionary:
		for k in (pc as Dictionary).keys():
			var v := float((pc as Dictionary)[k])
			if not is_finite(v) or v < 0.0 or v > 1.0:
				errors.append("pressure[%s] 必须在 0..1" % str(k))
			else:
				pressure_cfg[str(k)] = v
	elif pc is int or pc is float:
		var v2 := float(pc)
		if not is_finite(v2) or v2 < 0.0 or v2 > 1.0:
			errors.append("pressure 必须在 0..1")
		else:
			default_pressure = v2
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	ready = errors.is_empty()
	return ready

func _apply_templates() -> void:
	_type_map = {}
	for raw in (templates.get("types", []) as Array):
		if raw is Dictionary:
			var t: Dictionary = raw
			_type_map[str(t.get("code", ""))] = t
	_schedule = (templates.get("schedule", {}) as Dictionary).duplicate(true) \
		if templates.get("schedule") is Dictionary else {}
	_class_weights = (templates.get("facility_class_weights", {}) as Dictionary).duplicate(true) \
		if templates.get("facility_class_weights") is Dictionary else {}
	_anomaly_patterns = (templates.get("anomaly_patterns", {}) as Dictionary).duplicate(true) \
		if templates.get("anomaly_patterns") is Dictionary else {}
	_record_schema = (templates.get("record_schema", {}) as Dictionary).duplicate(true) \
		if templates.get("record_schema") is Dictionary else {}

func validate_templates(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["模板必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != TEMPLATE_SCHEMA:
		errs.append("schema 必须为 " + TEMPLATE_SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	var types = d.get("types", null)
	if not (types is Array) or (types as Array).size() != 9:
		errs.append("types 必须为 9 类 A1-A9")
	else:
		var codes: Dictionary = {}
		for raw in (types as Array):
			if not (raw is Dictionary):
				errs.append("type 非对象")
				continue
			var t: Dictionary = raw
			var code := str(t.get("code", ""))
			if not (code in ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"]):
				errs.append("非法 type code：" + code)
			if codes.has(code):
				errs.append("type code 重复：" + code)
			codes[code] = true
			for k in ["key", "name", "severity", "classes", "impact",
					"disposition", "anomalies", "telemetry_channels"]:
				if not t.has(k):
					errs.append("type %s 缺 %s" % [code, k])
			var sev = t.get("severity", null)
			if not (sev is Array) or (sev as Array).size() != 2:
				errs.append("type %s severity 必须 [min,max]" % code)
			var an = t.get("anomalies", null)
			if not (an is Array) or (an as Array).is_empty():
				errs.append("type %s anomalies 为空" % code)
	if not (d.get("facility_class_weights", null) is Dictionary):
		errs.append("facility_class_weights 必须为对象")
	elif not ((d.get("facility_class_weights") as Dictionary).get("default", null) is Dictionary):
		errs.append("facility_class_weights.default 缺失")
	if not (d.get("anomaly_patterns", null) is Dictionary):
		errs.append("anomaly_patterns 必须为对象")
	elif not ((d.get("anomaly_patterns") as Dictionary).get("gap", null) is Dictionary):
		errs.append("anomaly_patterns.gap 缺失")
	if not (d.get("record_schema", null) is Dictionary):
		errs.append("record_schema 必须为对象")
	if not (d.get("schedule", null) is Dictionary):
		errs.append("schedule 必须为对象")
	elif float((d.get("schedule") as Dictionary).get("base_interval_days", 0.0)) <= 0.0:
		errs.append("schedule.base_interval_days 必须 >0")
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

# ── pressure / schedule helpers ────────────────────────────────

func _pressure_for(fac: Dictionary) -> float:
	for k in [str(fac.get("facility_code", "")), str(fac.get("facility_id", "")),
			str(fac.get("parent_cluster", ""))]:
		if k != "" and pressure_cfg.has(k):
			return clampf(float(pressure_cfg[k]), 0.0, 1.0)
	if pressure_cfg.has("default"):
		return clampf(float(pressure_cfg["default"]), 0.0, 1.0)
	return clampf(default_pressure, 0.0, 1.0)

func pressure_map() -> Dictionary:
	var out: Dictionary = {}
	for raw in facilities:
		var f: Dictionary = raw
		out[str(f.get("facility_code", ""))] = _pressure_for(f)
	return out

func _weighted_pick(items: Array, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return int(_rng.randi_range(0, items.size() - 1)) if not items.is_empty() else -1
	var r := _rng.randf() * total
	var acc := 0.0
	for i in range(items.size()):
		acc += maxf(0.0, float(weights[i]))
		if r <= acc:
			return i
	return items.size() - 1

func _class_weight_for(fac: Dictionary) -> Dictionary:
	var cls := str(fac.get("facility_class", ""))
	if _class_weights.get(cls) is Dictionary:
		return (_class_weights[cls] as Dictionary)
	if _class_weights.get("default") is Dictionary:
		return (_class_weights["default"] as Dictionary)
	return {}

func _pick_type(fac: Dictionary, pressure: float) -> Dictionary:
	var cw := _class_weight_for(fac)
	var codes: Array = []
	var weights: Array = []
	for code in ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"]:
		var w := float(cw.get(code, 0.0))
		if w > 0.0:
			codes.append(code)
			# 高 pressure 轻微偏向更严重类型（A3/A5/A9），仍保留类别权重
			if code in ["A3", "A5", "A9"]:
				w *= 1.0 + 0.25 * pressure
			weights.append(w)
	if codes.is_empty():
		for code2 in ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"]:
			codes.append(code2)
			weights.append(1.0)
	var idx := _weighted_pick(codes, weights)
	if idx < 0:
		return {}
	return _type_map.get(str(codes[idx]), {})

# ── generate ───────────────────────────────────────────────────

func generate(opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: IncidentRecordService 未 ready")
	var o: Dictionary = opts if opts is Dictionary else {}
	if o.has("seed"):
		seed_value = int(o["seed"])
		_rng = RandomNumberGenerator.new()
		_rng.seed = seed_value
	if o.has("horizon_days"):
		horizon_days = float(o["horizon_days"])
	if not is_finite(horizon_days) or horizon_days <= 0.0:
		return _fail("invalid_horizon", "precondition: horizon_days 必须 >0")
	# 重新排程：清空记录，从开场后 0 开始
	_incidents = []
	_clues = []
	_by_id = {}
	_clue_seq = 0
	_incident_seq = 0
	_generated = false
	var total_s := horizon_days * 86400.0
	var t := 0.0
	var guard := 0
	var max_n := int(_schedule.get("max_incidents", 400))
	while t < total_s and _incidents.size() < max_n:
		guard += 1
		if guard > max_n * 10:
			errors.append("排程 guard 超限")
			break
		# 站点加权：pressure 越高越可能被选中
		var fweights: Array = []
		for raw in facilities:
			fweights.append(0.5 + _pressure_for(raw as Dictionary))
		var fi := _weighted_pick(facilities, fweights)
		if fi < 0:
			break
		var fac: Dictionary = facilities[fi]
		var pr := _pressure_for(fac)
		var base := float(_schedule.get("base_interval_days", 16.0))
		var min_days := float(_schedule.get("min_interval_days", 2.0))
		var scale := float(_schedule.get("pressure_scale", 0.65))
		var jmin := float(_schedule.get("jitter_min", 0.75))
		var jmax := float(_schedule.get("jitter_max", 1.30))
		var interval_days := base * (1.0 - scale * pr) * _rng.randf_range(jmin, jmax)
		interval_days = maxf(min_days, interval_days)
		t += interval_days * 86400.0
		if t >= total_s:
			break
		var typ := _pick_type(fac, pr)
		if typ.is_empty():
			continue
		var inc := _build_incident(t, fac, typ, pr)
		if inc.is_empty():
			continue
		_incidents.append(inc)
		_by_id[str(inc.get("incident_id", ""))] = inc
	_generated = true
	return {"ok": true, "generated": _incidents.size(), "clues": _clues.size(),
		"start_date": start_date, "horizon_days": horizon_days, "seed": seed_value,
		"excluded_nesoss": excluded.size(), "eligible_facilities": facilities.size(),
		"pressure": pressure_map(), "last_t_s": float((_incidents[-1] as Dictionary).get("t_s", 0.0)) if not _incidents.is_empty() else 0.0}

func _build_incident(t_s: float, fac: Dictionary, typ: Dictionary, pressure: float) -> Dictionary:
	_incident_seq += 1
	var code := str(typ.get("code", ""))
	var id := "INC-%04d" % _incident_seq
	var sev_range: Array = typ.get("severity", [1, 3]) as Array
	var sev := _rng.randi_range(int(sev_range[0]), int(sev_range[1]))
	var anomalies: Array = []
	var pool: Array = typ.get("anomalies", []) as Array
	var count := _rng.randi_range(1, mini(3, pool.size()))
	var idxs: Array = []
	while idxs.size() < count:
		var idx := _rng.randi_range(0, pool.size() - 1)
		if not (idx in idxs):
			idxs.append(idx)
	for i in idxs:
		anomalies.append(str(pool[i]))
	anomalies.sort()
	var integrity := _integrity_for(anomalies)
	var impact: Dictionary = (typ.get("impact", {}) as Dictionary).duplicate(true)
	if impact.has("berths_closed"):
		impact["berths_closed"] = int(impact.get("berths_closed", 0)) + _rng.randi_range(0, 1)
	if impact.has("cargo_lost_t"):
		impact["cargo_lost_t"] = float(impact.get("cargo_lost_t", 0.0)) * _rng.randf_range(0.5, 1.5)
	var disposition: Dictionary = (typ.get("disposition", {}) as Dictionary).duplicate(true)
	var facility_code := str(fac.get("facility_code", ""))
	var facility_id := str(fac.get("facility_id", ""))
	var cluster_id := str(fac.get("parent_cluster", ""))
	var operator := {"role": str(disposition.get("response", "facility_ops")),
		"source": "facility_operations", "generic": true}
	var summary := "%s 发生 %s（%s），严重度 %d；处置：%s；记录完整性：%s。" % [
		str(fac.get("name", facility_code)), str(typ.get("name", code)), code,
		sev, str(disposition.get("status", "unknown")),
		str(integrity.get("status", "unknown"))]
	var t_iso := _iso_at(t_s)
	var accident_log := {
		"schema": str(_record_schema.get("accident_log", "incident_accident_log.v1")),
		"incident_id": id, "t_s": t_s, "t_iso": t_iso,
		"facility_id": facility_id, "facility_code": facility_code,
		"facility_name": str(fac.get("name", "")), "cluster_id": cluster_id,
		"type": code, "type_key": str(typ.get("key", "")),
		"type_name": str(typ.get("name", "")),
		"severity": sev, "severity_scale": "1-5",
		"impact": impact.duplicate(true), "disposition": disposition.duplicate(true),
		"record_integrity": integrity.duplicate(true),
		"operator": operator.duplicate(true), "summary": summary,
		"writes_v15": false}
	var telemetry := _build_telemetry(id, fac, typ, t_s, anomalies, integrity)
	var otc := _build_otc(id, fac, t_s, anomalies, integrity)
	var inc := {
		"schema": SCHEMA, "incident_id": id, "t_s": t_s, "t_iso": t_iso,
		"day": int(t_s / 86400.0), "facility_id": facility_id,
		"facility_code": facility_code, "facility_name": str(fac.get("name", "")),
		"cluster_id": cluster_id, "type": code, "type_name": str(typ.get("name", "")),
		"severity": sev, "impact": impact.duplicate(true),
		"disposition": disposition.duplicate(true),
		"record_integrity": integrity.duplicate(true),
		"operator": operator.duplicate(true), "summary": summary,
		"accident_log": accident_log, "telemetry": telemetry, "otc": otc,
		"clue_ids": []}
	# ghost_track_clues：异常模式逐条派生
	for an in anomalies:
		var patt: Dictionary = _anomaly_patterns.get(str(an), {}) as Dictionary
		_clue_seq += 1
		var clue := {
			"schema": str(_record_schema.get("clue", "incident_ghost_track_clue.v1")),
			"clue_id": "GTC-%04d" % _clue_seq, "incident_id": id,
			"facility_id": facility_id, "facility_code": facility_code,
			"t_s": t_s, "t_iso": t_iso, "kind": str(patt.get("clue_kind", an)),
			"label": str(patt.get("clue_label", an)),
			"severity": int(patt.get("severity", 1)),
			"evidence_ref": {"record": "telemetry" if an != "duplicate_track" else "otc",
				"anomaly": str(an)},
			"description": str(patt.get("description", "")),
			"confidence": clampf(0.55 + 0.1 * float(integrity.get("score", 50)) / 100.0
				+ pressure * 0.1, 0.0, 1.0),
			"writes_v15": false}
		_clues.append(clue)
		(inc["clue_ids"] as Array).append(str(clue["clue_id"]))
	return inc

func _integrity_for(anomalies: Array) -> Dictionary:
	var edited := "edit" in anomalies
	var gaps := anomalies.filter(func(x): return str(x) == "gap").size()
	var jumps := anomalies.filter(func(x): return str(x) == "timestamp_jump").size()
	var dup := anomalies.filter(func(x): return str(x) == "duplicate_track").size()
	var status := "intact"
	if edited:
		status = "edited"
	elif gaps > 0 or jumps > 0 or dup > 0:
		status = "gaps"
	var score := 100 - 12 * anomalies.size() - (15 if edited else 0)
	return {"status": status, "score": clampi(score, 0, 100),
		"gaps": gaps, "time_jumps": jumps, "duplicate_codes": dup,
		"edited": edited, "anomalies": anomalies.duplicate()}

# ── records ────────────────────────────────────────────────────

func _channel_values(base: Dictionary, channel: String, i: int) -> float:
	var b := float(base.get(channel, 1.0))
	var jitter := _rng.randf_range(-0.05, 0.05)
	return b * (1.0 + jitter) + float(i) * 0.01

func _build_telemetry(id: String, fac: Dictionary, typ: Dictionary, t_s: float,
		anomalies: Array, integrity: Dictionary) -> Dictionary:
	var before := int(_schedule.get("telemetry_samples_before", 4))
	var after := int(_schedule.get("telemetry_samples_after", 4))
	var step := float(_schedule.get("telemetry_sample_interval_s", 60.0))
	var channels: Array = STANDARD_CHANNELS.duplicate()
	for ch in (typ.get("telemetry_channels", []) as Array):
		if not (str(ch) in channels):
			channels.append(str(ch))
	var bases := {"pressure_kpa": 101.0, "temperature_c": 22.0, "power_kw": 300.0,
		"flow_tph": 60.0, "coolant_pressure_kpa": 180.0, "core_temp_c": 640.0,
		"cabin_pressure_kpa": 101.0, "bus_voltage_kv": 11.0, "frequency_hz": 50.0,
		"tank_pressure_kpa": 101.0, "leak_rate": 0.0, "berth_load_kn": 120.0,
		"packet_loss_pct": 0.1, "latency_ms": 12.0, "cargo_mass_t": 300.0,
		"pos_error_km": 0.02, "range_rate_kmps": 0.1, "smoke_density": 0.0}
	var samples: Array = []
	var idx := 0
	for i in range(-before, after + 1):
		var st := t_s + float(i) * step
		var vals: Dictionary = {}
		for ch in channels:
			var v := _channel_values(bases, str(ch), idx)
			if str(ch) == "pressure_kpa" and "gap" in anomalies and i > 0:
				v *= 0.72
			if str(ch) == "temperature_c" and "power_spike" in anomalies and i >= 0:
				v += 12.0
			vals[str(ch)] = snappedf(v, 0.001)
		samples.append({"t_s": st, "offset_s": float(i) * step, "values": vals})
		idx += 1
	var gaps: Array = []
	if "gap" in anomalies:
		gaps.append({"channel": "pressure_kpa", "from_t_s": t_s - step,
			"to_t_s": t_s + step, "missing_samples": 2,
			"reason": "telemetry_gap"})
	var anomalies_out: Array = anomalies.duplicate()
	var edit_marks: Array = []
	if "edit" in anomalies:
		edit_marks.append({"target": "telemetry.samples", "action": "rewrite",
			"fields": ["temperature_c", "power_kw"], "source": "post_incident_edit"})
	if "timestamp_jump" in anomalies:
		edit_marks.append({"target": "telemetry.timestamps", "action": "jump",
			"delta_s": 180.0, "source": "unknown"})
	var payload := {"incident_id": id, "facility_code": str(fac.get("facility_code", "")),
		"t_s": t_s, "samples": samples, "gaps": gaps, "anomalies": anomalies_out,
		"edit_marks": edit_marks}
	return {"schema": str(_record_schema.get("telemetry", "incident_telemetry.v1")),
		"incident_id": id, "facility_code": str(fac.get("facility_code", "")),
		"window": {"start_s": t_s - before * step, "end_s": t_s + after * step},
		"channels": channels, "samples": samples, "gaps": gaps,
		"anomalies": anomalies_out, "edit_marks": edit_marks,
		"hash": _sha256(payload), "record_integrity": integrity.duplicate(true),
		"writes_v15": false}

func _build_otc(id: String, fac: Dictionary, t_s: float, anomalies: Array,
		integrity: Dictionary) -> Dictionary:
	var tracks: Array = []
	var n := _rng.randi_range(1, 3)
	for i in range(n):
		var trk := "TRK-%s-%02d" % [id.substr(4), i + 1]
		var txp := "TXP-%s-%02d" % [str(fac.get("facility_code", "UNKNOWN")).replace("FC-", ""), i + 1]
		var clr := "CLR-%s-%02d" % [id.substr(4), i + 1]
		tracks.append({"track_id": trk, "transponder": txp, "clearance": clr,
			"handoff": {"from": "traffic_control", "to": "port_ops",
				"t_s": t_s + float(i + 1) * 60.0}})
	var clearances: Array = []
	for tr in tracks:
		clearances.append({"track_id": str((tr as Dictionary).get("track_id", "")),
			"clearance": str((tr as Dictionary).get("clearance", "")),
			"state": "issued"})
	var handoffs: Array = []
	for tr in tracks:
		handoffs.append((tr as Dictionary).get("handoff", {}))
	var deleted: Array = []
	var rewritten: Array = []
	var duplicate_codes: Array = []
	if "gap" in anomalies or "edit" in anomalies:
		deleted.append({"target": "otc.tracks", "track_id": str((tracks[0] as Dictionary).get("track_id", "")),
			"reason": "record_deleted"})
	if "edit" in anomalies or "timestamp_jump" in anomalies:
		rewritten.append({"target": "otc.handoff", "field": "t_s",
			"reason": "post_incident_rewrite"})
	if "duplicate_track" in anomalies:
		var dup := str((tracks[0] as Dictionary).get("track_id", ""))
		duplicate_codes.append({"track_id": dup, "code": str((tracks[0] as Dictionary).get("transponder", "")),
			"count": 2, "reason": "duplicate_transponder"})
	var payload := {"incident_id": id, "tracks": tracks, "clearances": clearances,
		"handoffs": handoffs, "deleted": deleted, "rewritten": rewritten,
		"duplicates": duplicate_codes}
	return {"schema": str(_record_schema.get("otc", "incident_otc_record.v1")),
		"incident_id": id, "facility_code": str(fac.get("facility_code", "")),
		"tracks": tracks, "clearances": clearances, "handoffs": handoffs,
		"deleted_records": deleted, "rewritten_records": rewritten,
		"duplicate_codes": duplicate_codes, "hash": _sha256(payload),
		"record_integrity": integrity.duplicate(true), "writes_v15": false}

func _sha256(v) -> String:
	return "sha256:" + JSON.stringify(v).sha256_text()

func _iso_at(t_s: float) -> String:
	return Time.get_datetime_string_from_unix_time(start_unix + int(t_s), true)

# ── 查询 ────────────────────────────────────────────────────────

func incidents_list() -> Array:
	return _incidents.duplicate(true)

func incidents() -> Array:
	return _incidents.duplicate(true)

func incident_ids() -> Array:
	var out: Array = []
	for raw in _incidents:
		out.append(str((raw as Dictionary).get("incident_id", "")))
	return out

func _resolve(ref: Variant) -> Dictionary:
	if ref is String:
		return (_by_id.get(ref, {}) as Dictionary).duplicate(true)
	if ref is Dictionary:
		var id := str((ref as Dictionary).get("incident_id", ""))
		if id != "" and _by_id.has(id):
			return (_by_id[id] as Dictionary).duplicate(true)
		return (ref as Dictionary).duplicate(true)
	return {}

func records(incident_id: Variant) -> Dictionary:
	var id := str(incident_id.get("incident_id", "")) if incident_id is Dictionary else str(incident_id)
	var inc: Dictionary = _by_id.get(id, {}) as Dictionary
	if inc.is_empty():
		return {}
	return {"incident_id": id,
		"accident_log": (inc.get("accident_log", {}) as Dictionary).duplicate(true),
		"telemetry": (inc.get("telemetry", {}) as Dictionary).duplicate(true),
		"otc": (inc.get("otc", {}) as Dictionary).duplicate(true),
		"clues": clues_for(id)}

func clues_for(incident_id: String) -> Array:
	var out: Array = []
	for raw in _clues:
		if str((raw as Dictionary).get("incident_id", "")) == incident_id:
			out.append((raw as Dictionary).duplicate(true))
	return out

func clues(incident_id := "") -> Array:
	if incident_id == "":
		return _clues.duplicate(true)
	return clues_for(incident_id)

func in_between(t0: Variant, t1: Variant) -> Array:
	var out: Array = []
	var lo := minf(_to_relative_t(t0), _to_relative_t(t1))
	var hi := maxf(_to_relative_t(t0), _to_relative_t(t1))
	for raw in _incidents:
		var t := float((raw as Dictionary).get("t_s", 0.0))
		if t >= lo and t <= hi:
			out.append((raw as Dictionary).duplicate(true))
	return out

# ── 文本格式化（日志/黑匣子/UI；无具体人物台词）────────────────

func _to_relative_t(v: Variant) -> float:
	if v is int or v is float:
		return float(v)
	var s := str(v)
	if s.strip_edges() == "":
		return 0.0
	var unix := int(Time.get_unix_time_from_datetime_string(s.replace(" ", "T")))
	if unix <= 0:
		return 0.0
	return float(unix - start_unix)

func format_accident_text(ref: Variant) -> String:
	var inc := _resolve(ref)
	if inc.is_empty():
		return ""
	var a: Dictionary = inc.get("accident_log", {}) as Dictionary
	if a.is_empty():
		return ""
	var lines: Array = []
	lines.append("[事故记录] %s  %s" % [str(a.get("incident_id", "")), str(a.get("t_iso", ""))])
	lines.append("设施：%s（%s / %s）" % [str(a.get("facility_code", "")),
		str(a.get("facility_name", "")), str(a.get("cluster_id", ""))])
	lines.append("类型：%s %s  严重度：%d/5" % [str(a.get("type", "")),
		str(a.get("type_name", "")), int(a.get("severity", 0))])
	lines.append("影响：%s" % JSON.stringify(a.get("impact", {})))
	lines.append("处置：%s  操作者：%s" % [JSON.stringify(a.get("disposition", {})),
		JSON.stringify(a.get("operator", {}))])
	lines.append("记录完整性：%s" % JSON.stringify(a.get("record_integrity", {})))
	lines.append("摘要：%s" % str(a.get("summary", "")))
	return "\n".join(lines)

func format_telemetry_text(ref: Variant) -> String:
	var inc := _resolve(ref)
	if inc.is_empty():
		return ""
	var t: Dictionary = inc.get("telemetry", {}) as Dictionary
	if t.is_empty():
		return ""
	var lines: Array = []
	lines.append("[遥测记录] %s  %s  设施：%s" % [str(t.get("incident_id", "")),
		str(inc.get("t_iso", "")), str(t.get("facility_code", ""))])
	lines.append("窗口：%s  通道：%s" % [JSON.stringify(t.get("window", {})),
		str(t.get("channels", []))])
	var samples: Array = t.get("samples", []) as Array
	for raw in samples:
		if raw is Dictionary:
			var s: Dictionary = raw
			lines.append("  t=%+.1fs %s" % [float(s.get("offset_s", 0.0)),
				JSON.stringify(s.get("values", {}))])
	lines.append("缺口：%s" % JSON.stringify(t.get("gaps", [])))
	lines.append("异常：%s" % JSON.stringify(t.get("anomalies", [])))
	lines.append("编辑痕迹：%s" % JSON.stringify(t.get("edit_marks", [])))
	lines.append("hash：%s  完整性：%s" % [str(t.get("hash", "")),
		JSON.stringify(t.get("record_integrity", {}))])
	return "\n".join(lines)

func format_otc_text(ref: Variant) -> String:
	var inc := _resolve(ref)
	if inc.is_empty():
		return ""
	var o: Dictionary = inc.get("otc", {}) as Dictionary
	if o.is_empty():
		return ""
	var lines: Array = []
	lines.append("[OTC/交通记录] %s  %s  设施：%s" % [str(o.get("incident_id", "")),
		str(inc.get("t_iso", "")), str(o.get("facility_code", ""))])
	for raw in (o.get("tracks", []) as Array):
		if raw is Dictionary:
			lines.append("  track=%s transponder=%s clearance=%s" % [
				str((raw as Dictionary).get("track_id", "")),
				str((raw as Dictionary).get("transponder", "")),
				str((raw as Dictionary).get("clearance", ""))])
	lines.append("handoff：%s" % JSON.stringify(o.get("handoffs", [])))
	lines.append("删除记录：%s" % JSON.stringify(o.get("deleted_records", [])))
	lines.append("改写记录：%s" % JSON.stringify(o.get("rewritten_records", [])))
	lines.append("重复码：%s" % JSON.stringify(o.get("duplicate_codes", [])))
	lines.append("hash：%s  完整性：%s" % [str(o.get("hash", "")),
		JSON.stringify(o.get("record_integrity", {}))])
	return "\n".join(lines)

# ── VM / save / load ───────────────────────────────────────────

func vm() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "generated": _generated,
		"start_date": start_date, "horizon_days": horizon_days, "seed": seed_value,
		"eligible_facilities": facilities.size(), "excluded_nesoss": excluded.size(),
		"pressure": pressure_map(), "incidents": _incidents.size(), "clues": _clues.size(),
		"incident_ids": incident_ids(), "writes": {"world": false, "ui": false,
			"v15": false}}

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "generated": _generated,
		"start_date": start_date, "horizon_days": horizon_days, "seed": seed_value,
		"eligible_facilities": facilities.size(), "excluded_nesoss": excluded.size(),
		"incidents": _incidents.size(), "clues": _clues.size(),
		"writes_v15": false}

func to_json() -> String:
	return JSON.stringify(vm())

func save_state() -> String:
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"templates_path": templates_path, "facilities_content_path": facilities_content_path,
		"start_date": start_date, "start_unix": start_unix,
		"horizon_days": horizon_days, "seed": seed_value,
		"pressure_cfg": pressure_cfg.duplicate(true), "default_pressure": default_pressure,
		"facilities": JSON.parse_string(JSON.stringify(facilities)),
		"excluded": excluded.duplicate(true),
		"incidents": JSON.parse_string(JSON.stringify(_incidents)),
		"clues": JSON.parse_string(JSON.stringify(_clues)),
		"clue_seq": _clue_seq, "incident_seq": _incident_seq,
		"generated": _generated, "rng_state": _rng.state})

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
	if not (d.get("incidents", null) is Array) or not (d.get("clues", null) is Array) \
			or not (d.get("facilities", null) is Array):
		return _fail("invalid_payload", "load: incidents/clues/facilities 非法")
	if not (d.get("pressure_cfg", null) is Dictionary):
		return _fail("invalid_payload", "load: pressure_cfg 非法")
	# 校验完再应用
	start_date = str(d.get("start_date", OPENING_DATE))
	start_unix = int(d.get("start_unix", 0))
	horizon_days = float(d.get("horizon_days", 365.0))
	seed_value = int(d.get("seed", 2193))
	pressure_cfg = (d.get("pressure_cfg") as Dictionary).duplicate(true)
	default_pressure = float(d.get("default_pressure", 0.5))
	facilities = (d.get("facilities") as Array).duplicate(true)
	excluded = (d.get("excluded", []) as Array).duplicate(true) if d.get("excluded") is Array else []
	_incidents = (d.get("incidents") as Array).duplicate(true)
	_clues = (d.get("clues") as Array).duplicate(true)
	_clue_seq = int(d.get("clue_seq", _clues.size()))
	_incident_seq = int(d.get("incident_seq", _incidents.size()))
	_generated = bool(d.get("generated", false))
	facilities_by_id = {}
	facilities_by_code = {}
	for raw in facilities:
		if raw is Dictionary:
			facilities_by_id[str((raw as Dictionary).get("facility_id", ""))] = raw
			facilities_by_code[str((raw as Dictionary).get("facility_code", ""))] = raw
	_by_id = {}
	for raw2 in _incidents:
		if raw2 is Dictionary:
			_by_id[str((raw2 as Dictionary).get("incident_id", ""))] = raw2
	_rng = RandomNumberGenerator.new()
	_rng.state = int(d.get("rng_state", 0))
	ready = true
	return {"ok": true, "incidents": _incidents.size(), "clues": _clues.size()}

func reset() -> Dictionary:
	_incidents = []
	_clues = []
	_by_id = {}
	_clue_seq = 0
	_incident_seq = 0
	_generated = false
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	return {"ok": true, "incidents": 0, "clues": 0}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	if facilities.is_empty():
		v.append("无可用设施")
	for raw in facilities:
		var code := str((raw as Dictionary).get("facility_code", ""))
		if code.contains("NESOSS"):
			v.append("NESOSS 设施未排除：" + code)
	for raw2 in _incidents:
		var inc: Dictionary = raw2
		var id := str(inc.get("incident_id", ""))
		if _by_id.get(id, null) == null:
			v.append("incident 索引缺失：" + id)
		for k in ["accident_log", "telemetry", "otc"]:
			if not (inc.get(k) is Dictionary):
				v.append("incident %s 缺 %s" % [id, k])
	if _generated and _incidents.is_empty():
		v.append("generate 后无事故")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
