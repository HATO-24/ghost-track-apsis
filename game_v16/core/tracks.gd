class_name V2Track
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 航迹/识别状态机（纯数据，不引用 UI / 不引用传感器数学）
#
#   等级 L0 UNKNOWN → L1 BEARING（仅方位）→ L2 POSITION（定位）
#        → L3 CLASSIFIED（分类）→ L4 IDENTIFIED（识别）
#
#   - 等级来自「观测证据」的时间戳：拿到支撑级 S 的观测，同时刷新 1..S 的
#     全部下级证据（与 docs/11 §4 一致）；证据超过 valid_s 就逐级衰减。
#   - 观测字段：sensor / source / time / quality（+ kind/support/bearing/range/
#     classification/identity/iff_status/signal）。支持级可由观测显式给，也可由
#     内容规则 content/track_rules.json 的 sensor_support 按 kind 推出。
#   - 身份（pending/unknown/assumed_friend/friend/neutral/suspect/hostile）与
#     等级分开存储、分开更新：身份可以在 L2 就更新，等级不会因为身份而跳级。
#   - 批号不写死：航迹 id 可由数据给（如 "1000"/"2001"），也可自动分配（T0001）；
#     实体关联用 entity_id，没有实体的接触（虚警/纯方位回波）也可以存在。
#
# 数值口径：docs/11 §4（L4 30s / L3 90s / L2 210s / L1 记忆地板）、
#           docs/19 §2.5（六级身份）。这些数值在 content/track_rules.json。
# ═══════════════════════════════════════════════════════════════════

const LEVEL_NONE := 0
const LEVEL_BEARING := 1
const LEVEL_POSITION := 2
const LEVEL_CLASSIFIED := 3
const LEVEL_IDENTIFIED := 4

var id := ""
var entity_id := ""

var level := LEVEL_BEARING
var level_max_seen := LEVEL_BEARING
var level_evidence: Dictionary = {}      # int(等级) -> 最近一次证据时间（秒）
var first_seen_t := 0.0
var last_update_t := 0.0
var age_s := 0.0
var stale := false
var retire_hint := false

var bearing_deg := -1.0
var bearing_sigma_deg := 180.0
var range_km := -1.0
var range_sigma_km := -1.0
var range_band := ""
var bearing_only := true
var radial_vel_kmps := 0.0
var covariance: Dictionary = {}

var classification: Dictionary = {}
var identity_kind := "pending"
var identity: Dictionary = {}
var iff_status := ""
var signal_data: Dictionary = {}
var threat := "pending"

var sources: Array[String] = []
var observers: Array[String] = []
var observation_count := 0
var observation_history: Array = []
var quality := 0.0
var quality_avg := 0.0

var tags: Array[String] = []
var notes: Array[String] = []
var flags: Dictionary = {}

var _rules: Dictionary = {}

# ── 描述性查询（标签全部来自规则内容，不在代码里写死中文）──────────────

func rules() -> Dictionary:
	return _rules

func level_info() -> Dictionary:
	for raw in (_rules.get("levels", []) as Array):
		var d: Dictionary = raw
		if int(d.get("level", -1)) == level:
			return d.duplicate(true)
	return {"level": level, "id": "L%d" % level, "label": "L%d" % level, "label_en": "L%d" % level}

func level_name() -> String:
	return String(level_info().get("id", "L%d" % level))

func level_label() -> String:
	return String(level_info().get("label", level_name()))

func level_label_en() -> String:
	return String(level_info().get("label_en", level_name()))

func identity_info() -> Dictionary:
	var idcs := ((_rules.get("identity", {}) as Dictionary).get("classes", []) as Array)
	for raw in idcs:
		var d: Dictionary = raw
		if String(d.get("id", "")) == identity_kind:
			return d.duplicate(true)
	return {"id": identity_kind, "label": identity_kind, "label_en": identity_kind}

func identity_label() -> String:
	return String(identity_info().get("label", identity_kind))

func identity_label_en() -> String:
	return String(identity_info().get("label_en", identity_kind))

func has_position() -> bool:
	return range_km >= 0.0

func is_bearing_only() -> bool:
	return bearing_only or not has_position()

func has_classification() -> bool:
	return not classification.is_empty()

func has_identity() -> bool:
	return not identity.is_empty() or identity_kind != String((_rules.get("identity", {}) as Dictionary).get("default", "pending"))

func latest_age(now: float) -> float:
	return maxf(0.0, now - last_update_t)

# ── 状态推进 ─────────────────────────────────────────────────────────

## 融合一条观测。返回 true 表示有数据更新（detected=false 或 quality 过低返回 false）。
func apply_observation(obs: Dictionary, now: float) -> bool:
	if not bool(obs.get("detected", true)):
		return false
	if String(id) == "":
		return false
	var t := float(obs.get("t", now))
	if t <= 0.0:
		t = now
	var q := float(obs.get("quality", float(_rules.get("default_quality", 1.0))))
	var min_q := float(_rules.get("min_quality", 0.05))
	if q < min_q:
		_add_note("观测质量过低（%.3f < %.3f），不刷新证据" % [q, min_q])
		return false

	var kind := String(obs.get("kind", ""))
	var cls_in: Dictionary = (obs.get("classification", {}) as Dictionary)
	var identity_in: Dictionary = (obs.get("identity", {}) as Dictionary)
	var iff_in := String(obs.get("iff_status", ""))
	var support := int(obs.get("support", obs.get("level_support", -1)))
	if support < 0:
		support = _support_from_rules(kind, not cls_in.is_empty())
	support = clampi(support, LEVEL_BEARING, LEVEL_IDENTIFIED)
	if bool(_rules.get("validate_support", true)):
		support = _validate_support(support, obs, cls_in, identity_in, iff_in)

	# —— 位置/几何 ——
	var has_loc := false
	if obs.has("position") and obs.get("position") is Dictionary:
		var pos: Dictionary = obs.get("position", {})
		has_loc = true
		bearing_deg = float(pos.get("bearing_deg", bearing_deg))
		bearing_sigma_deg = float(pos.get("bearing_sigma_deg", bearing_sigma_deg))
		range_km = float(pos.get("range_km", range_km))
		range_sigma_km = float(pos.get("range_sigma_km", range_sigma_km))
	var obs_bearing := float(obs.get("bearing_deg", -1.0))
	if obs_bearing >= 0.0:
		bearing_deg = obs_bearing
		bearing_sigma_deg = maxf(0.001, float(obs.get("bearing_sigma_deg", 1.0)))
		has_loc = true
	var obs_range := float(obs.get("range_km", -1.0))
	if obs_range >= 0.0:
		range_km = obs_range
		range_sigma_km = maxf(0.001, float(obs.get("range_sigma_km", -1.0)))
		if range_sigma_km <= 0.0:
			range_sigma_km = maxf(0.5, range_km * 0.1)
		has_loc = true
	var band := String(obs.get("range_band", ""))
	if band != "":
		range_band = band
	if obs.has("radial_vel_kmps"):
		radial_vel_kmps = float(obs.get("radial_vel_kmps", 0.0))
	bearing_only = range_km < 0.0
	if has_loc:
		covariance = _covariance_from_observation()
	if obs.has("speed_mps"):
		# 兼容旧数据；新模型不给速度时保持 0。
		pass

	# —— 分类 / 身份 / 信号（身份与等级分开更新）——
	if not cls_in.is_empty():
		classification = _merge_dict(classification, cls_in)
	if not identity_in.is_empty():
		identity = _merge_dict(identity, identity_in)
		var ik := String(identity_in.get("kind", ""))
		if ik != "":
			identity_kind = ik
	if obs.has("identity_kind"):
		identity_kind = String(obs.get("identity_kind", identity_kind))
	if iff_in != "":
		iff_status = iff_in
		# 没有显式身份时，按内容规则里的 iff_status_map 推一个（不自动判敌）。
		if not obs.has("identity_kind") and identity_in.is_empty() and String(identity.get("via", "")) == "":
			var mapped := _map_identity_from_iff(iff_in)
			if mapped != "":
				identity_kind = mapped
	if obs.has("signal") and (obs.get("signal") as Dictionary).size() > 0:
		signal_data = _merge_dict(signal_data, obs.get("signal", {}))
	if obs.has("threat"):
		threat = String(obs.get("threat", threat))

	# —— 证据时间戳：S 级观测刷新 1..S（docs/11 §4）——
	for lv in range(LEVEL_BEARING, support + 1):
		level_evidence[lv] = t

	var sensor := String(obs.get("sensor", ""))
	if sensor != "" and not (sensor in sources):
		sources.append(sensor)
	var source := String(obs.get("source", ""))
	if source != "" and not (source in observers):
		observers.append(source)

	observation_count += 1
	if q >= 0.0:
		quality = clampf(q, 0.0, 1.0)
		if quality_avg <= 0.0:
			quality_avg = quality
		else:
			quality_avg = lerpf(quality_avg, quality, 0.25)
	var hist := obs.duplicate(true)
	hist["t"] = t
	hist["quality"] = q
	hist["support"] = support
	observation_history.append(hist)
	var keep := int(_rules.get("keep_observations", 64))
	while observation_history.size() > maxi(1, keep):
		observation_history.pop_front()

	last_update_t = maxf(last_update_t, t)
	if first_seen_t <= 0.0:
		first_seen_t = t
	age_s = latest_age(now)
	stale = age_s > float(_rules.get("stale_after_s", 30.0))
	retire_hint = age_s > float(_rules.get("memory_keep_s", 300.0))
	level = level_from_evidence(now)
	level_max_seen = maxi(level_max_seen, level)
	return true

## 由证据时间戳计算当前等级（L1 是记忆地板：失去跟踪不删除）。
func level_from_evidence(now: float) -> int:
	var lv := LEVEL_BEARING
	for target in [LEVEL_POSITION, LEVEL_CLASSIFIED, LEVEL_IDENTIFIED]:
		if not level_evidence.has(target):
			continue
		var valid := _valid_s(target)
		if valid < 0.0 or (now - float(level_evidence[target])) <= valid:
			lv = maxi(lv, target)
	return lv

## 时间推进：更新陈旧度并逐级衰减。返回旧等级（未变返回 -1）。
func age(now: float) -> int:
	var old := level
	age_s = latest_age(now)
	stale = age_s > float(_rules.get("stale_after_s", 30.0))
	retire_hint = age_s > float(_rules.get("memory_keep_s", 300.0))
	level = level_from_evidence(now)
	level_max_seen = maxi(level_max_seen, level)
	return old if old != level else -1

## 脚本/事件强制设定等级（迁移/剧情用；正常流程应走 apply_observation）。
func force_level(new_level: int, now: float, note_text := "") -> void:
	var target := clampi(new_level, LEVEL_BEARING, LEVEL_IDENTIFIED)
	for lv in range(LEVEL_BEARING, target + 1):
		level_evidence[lv] = now
	level = target
	level_max_seen = maxi(level_max_seen, target)
	last_update_t = now
	age_s = 0.0
	stale = false
	if note_text != "":
		_add_note(note_text)

func set_identity(kind: String, details: Dictionary = {}, now: float = -1.0) -> void:
	identity_kind = kind
	if not details.is_empty():
		identity = _merge_dict(identity, details)
	if now >= 0.0:
		identity["t"] = now

func set_threat(kind: String) -> void:
	threat = kind

func add_tag(tag: String) -> void:
	if not (tag in tags):
		tags.append(tag)

func _add_note(text: String) -> void:
	if text == "" or notes.has(text):
		return
	notes.append(text)
	var cap := int(_rules.get("keep_observations", 64))
	while notes.size() > cap:
		notes.pop_front()

func _valid_s(level: int) -> float:
	for raw in (_rules.get("levels", []) as Array):
		var d: Dictionary = raw
		if int(d.get("level", -1)) == level:
			return float(d.get("valid_s", -1))
	return -1.0

func _support_from_rules(kind: String, classified: bool) -> int:
	var map: Dictionary = (_rules.get("sensor_support", {}) as Dictionary)
	var key := kind
	if kind == "optical" and classified:
		key = "optical.classification"
	if map.has(key):
		return int(map[key])
	return LEVEL_BEARING

func _map_identity_from_iff(iff_status: String) -> String:
	var idn: Dictionary = (_rules.get("identity", {}) as Dictionary)
	var map: Dictionary = (idn.get("iff_status_map", {}) as Dictionary)
	return String(map.get(iff_status, ""))

func _validate_support(support: int, obs: Dictionary, cls_in: Dictionary,
		identity_in: Dictionary, iff_in: String) -> int:
	# L2 需要定位（本次观测给距离，或航迹已有距离解）
	if support >= LEVEL_POSITION and not (obs.has("range_km") or obs.has("position") or has_position()):
		_add_note("观测声称 L%d 但无位置解，降为 L1（仅方位）" % support)
		support = LEVEL_BEARING
	# L3 需要分类
	if support >= LEVEL_CLASSIFIED and cls_in.is_empty() and not has_classification():
		_add_note("观测声称 L%d 但无分类数据，降为 L2" % support)
		support = mini(support, LEVEL_POSITION)
	# L4 需要身份/敌我识别
	if support >= LEVEL_IDENTIFIED and identity_in.is_empty() and iff_in == "" and identity.is_empty():
		_add_note("观测声称 L4 但无身份/敌我识别数据，降为 L3")
		support = mini(support, LEVEL_CLASSIFIED)
	return support

func _covariance_from_observation() -> Dictionary:
	var rng_km := maxf(0.0, range_km)
	var b_sigma := maxf(0.0, deg_to_rad(bearing_sigma_deg)) * rng_km
	var r_sigma := maxf(0.0, range_sigma_km)
	var major := maxf(b_sigma, r_sigma)
	var minor := minf(b_sigma, r_sigma) if rng_km > 0.0 else 0.0
	return {
		"semi_major_km": major,
		"semi_minor_km": minor,
		"bearing_deg": bearing_deg,
		"radial_sigma_km": r_sigma,
		"cross_sigma_km": b_sigma,
	}

func _merge_dict(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in extra.keys():
		out[k] = extra[k]
	return out

func to_dict() -> Dictionary:
	return {
		"id": id, "entity_id": entity_id, "level": level,
		"level_name": level_name(), "level_label": level_label(),
		"level_max_seen": level_max_seen, "level_evidence": level_evidence.duplicate(true),
		"first_seen_t": first_seen_t, "last_update_t": last_update_t,
		"age_s": age_s, "stale": stale, "retire_hint": retire_hint,
		"bearing_deg": bearing_deg, "bearing_sigma_deg": bearing_sigma_deg,
		"range_km": range_km, "range_sigma_km": range_sigma_km,
		"range_band": range_band, "bearing_only": is_bearing_only(),
		"radial_vel_kmps": radial_vel_kmps, "covariance": covariance.duplicate(true),
		"classification": classification.duplicate(true),
		"identity": identity.duplicate(true), "identity_kind": identity_kind,
		"identity_label": identity_label(), "iff_status": iff_status,
		"signal_data": signal_data.duplicate(true), "threat": threat,
		"sources": sources.duplicate(), "observers": observers.duplicate(),
		"observation_count": observation_count, "quality": quality,
		"quality_avg": quality_avg, "tags": tags.duplicate(),
		"notes": notes.duplicate(), "flags": flags.duplicate(true),
	}

