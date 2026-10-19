class_name V2TrackTable
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 航迹表：id/实体双索引、自动批号、观测入口、衰减、迁移种子。
# 单条航迹的状态机在 core/tracks.gd（V2Track）；本文件只做容器/规则/查询。
# 规则来自 content/track_rules.json（缺失时回退内置默认值并报错）。
# ═══════════════════════════════════════════════════════════════════

var rules: Dictionary = {}
var tracks: Array = []
var by_id: Dictionary = {}
var by_entity: Dictionary = {}
var errors: Array[String] = []
var next_seq := 1

func _init(p_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else V2TrackTable.default_rules()

# —— 规则加载 ——

static func default_rules() -> Dictionary:
	return {
		"levels": [
			{"level": 0, "id": "UNKNOWN", "label": "未发现", "label_en": "UNKNOWN", "valid_s": 0},
			{"level": 1, "id": "BEARING", "label": "方位", "label_en": "BEARING", "valid_s": -1},
			{"level": 2, "id": "POSITION", "label": "定位", "label_en": "POSITION", "valid_s": 210},
			{"level": 3, "id": "CLASSIFIED", "label": "分类", "label_en": "CLASSIFIED", "valid_s": 90},
			{"level": 4, "id": "IDENTIFIED", "label": "识别", "label_en": "IDENTIFIED", "valid_s": 30},
		],
		"default_quality": 1.0, "min_quality": 0.05,
		"stale_after_s": 30.0, "memory_keep_s": 300.0,
		"keep_observations": 64, "validate_support": true,
		"track_id_prefix": "T", "track_id_pad": 4,
		"sensor_support": {"ir": 1, "optical": 1, "optical.classification": 3,
			"lidar": 2, "radar": 2, "radar.tws": 2, "crossfix": 2, "triangulation": 2,
			"iff": 4, "elint": 3, "datalink": 4, "manual": 1, "visual": 1},
		"identity": {
			"default": "pending",
			"classes": [
				{"id": "pending", "label": "待定", "label_en": "Pending"},
				{"id": "unknown", "label": "未知", "label_en": "Unknown"},
				{"id": "assumed_friend", "label": "假定友好", "label_en": "Assumed Friend"},
				{"id": "friend", "label": "友方", "label_en": "Friend"},
				{"id": "neutral", "label": "中立", "label_en": "Neutral"},
				{"id": "suspect", "label": "可疑", "label_en": "Suspect"},
				{"id": "hostile", "label": "敌方", "label_en": "Hostile"},
			],
			"iff_status_map": {"friend": "assumed_friend", "wrong_code": "unknown",
				"no_reply": "unknown", "faulty_transponder": "unknown", "unknown": "unknown"},
		},
	}

## 读内容规则文件（错误写进 out_errors；失败时回退内置默认值并报错）。
static func load_rules(path: String, out_errors: Array) -> Dictionary:
	var fallback := V2TrackTable.default_rules()
	if not FileAccess.file_exists(path):
		out_errors.append("missing track rules: " + path + "（回退内置默认规则）")
		return fallback
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		out_errors.append("invalid track rules json: " + path + "（回退内置默认规则）")
		return fallback
	var d: Dictionary = parsed
	var schema := String(d.get("schema", ""))
	if not schema.begins_with("track_rules"):
		out_errors.append("track rules schema 不匹配: " + schema + "（回退内置默认规则）")
		return fallback
	var lv: Array = d.get("levels", [])
	for need in [1, 2, 3, 4]:
		var found := false
		for raw in lv:
			if raw is Dictionary and int((raw as Dictionary).get("level", -1)) == int(need):
				found = true
				break
		if not found:
			out_errors.append("track rules 缺少 level %d（回退内置默认规则）" % int(need))
			return fallback
	var out := fallback.duplicate(true)
	for k in d.keys():
		out[k] = d[k]
	var idn: Dictionary = (out.get("identity", {}) as Dictionary)
	if (idn.get("classes", []) as Array).is_empty():
		out_errors.append("track rules identity.classes 为空（回退内置默认值）")
		out["identity"] = (fallback.get("identity", {}) as Dictionary).duplicate(true)
	return out

# —— 查询 ——

func find(track_id: String) -> V2Track:
	return by_id.get(track_id)

func find_by_entity(entity_id: String) -> V2Track:
	var t = by_entity.get(entity_id)
	return t

func all() -> Array:
	return tracks.duplicate()

func count() -> int:
	return tracks.size()

func active() -> Array:
	var out: Array = []
	for raw in tracks:
		var t: V2Track = raw
		if not t.retire_hint:
			out.append(t)
	return out

func level_info(level: int) -> Dictionary:
	for raw in (rules.get("levels", []) as Array):
		var d: Dictionary = raw
		if int(d.get("level", -1)) == level:
			return d.duplicate(true)
	return {"level": level, "id": "L%d" % level, "label": "L%d" % level, "label_en": "L%d" % level}

func level_name(level: int) -> String:
	return String(level_info(level).get("id", "L%d" % level))

func identity_info(kind: String) -> Dictionary:
	for raw in (((rules.get("identity", {}) as Dictionary).get("classes", [])) as Array):
		var d: Dictionary = raw
		if String(d.get("id", "")) == kind:
			return d.duplicate(true)
	return {"id": kind, "label": kind, "label_en": kind}

func identity_label(kind: String) -> String:
	return String(identity_info(kind).get("label", kind))

func default_identity() -> String:
	return String((rules.get("identity", {}) as Dictionary).get("default", "pending"))

# —— 创建 / 种子 ——

func _new_id() -> String:
	var prefix := String(rules.get("track_id_prefix", "T"))
	var pad := int(rules.get("track_id_pad", 4))
	var tid := ""
	var guard := 0
	while guard < 100000:
		tid = "%s%0*d" % [prefix, pad, next_seq]
		next_seq += 1
		if not by_id.has(tid):
			break
		guard += 1
	return tid

func _create(track_id: String, entity_id: String, now: float) -> V2Track:
	var t := V2Track.new()
	t.id = track_id if track_id != "" else _new_id()
	t.entity_id = entity_id
	t._rules = rules
	t.identity_kind = default_identity()
	t.first_seen_t = now
	t.last_update_t = now
	tracks.append(t)
	by_id[t.id] = t
	if entity_id != "":
		by_entity[entity_id] = t
	return t

## 从场景/迁移数据播种航迹（不是观测，用于开局初始态势）。
func seed(seed_data: Dictionary, now: float) -> V2Track:
	var tid := String(seed_data.get("id", ""))
	if tid == "":
		errors.append("track seed 缺少 id: %s" % str(seed_data))
		return null
	if by_id.has(tid):
		errors.append("track seed 重复 id: " + tid)
		return null
	var t := _create(tid, String(seed_data.get("entity_id", "")), now)
	t.level = clampi(int(seed_data.get("level", V2Track.LEVEL_BEARING)), V2Track.LEVEL_BEARING, V2Track.LEVEL_IDENTIFIED)
	var age_s := maxf(0.0, float(seed_data.get("age_s", 0.0)))
	var base_t := now - age_s
	for lv in range(V2Track.LEVEL_BEARING, t.level + 1):
		t.level_evidence[lv] = base_t
	t.last_update_t = base_t
	t.first_seen_t = base_t
	t.age_s = age_s
	t.stale = age_s > float(rules.get("stale_after_s", 30.0))
	t.retire_hint = age_s > float(rules.get("memory_keep_s", 300.0))
	t.identity_kind = String(seed_data.get("identity", default_identity()))
	t.identity = (seed_data.get("identity_details", {}) as Dictionary).duplicate(true)
	t.threat = String(seed_data.get("threat", "pending"))
	t.quality = float(seed_data.get("quality", 0.0))
	t.quality_avg = t.quality
	t.bearing_deg = float(seed_data.get("bearing_deg", -1.0))
	t.bearing_sigma_deg = float(seed_data.get("bearing_sigma_deg", 180.0))
	t.range_km = float(seed_data.get("range_km", -1.0))
	t.range_sigma_km = float(seed_data.get("range_sigma_km", -1.0))
	t.range_band = String(seed_data.get("range_band", ""))
	t.bearing_only = bool(seed_data.get("bearing_only", false)) or t.range_km < 0.0
	# 没有显式方位/距离时，从轨道状态派生（只做几何换算，不伪造数据）。
	if t.bearing_deg < 0.0:
		var orbit: Dictionary = (seed_data.get("orbit", {}) as Dictionary)
		var r: Array = (orbit.get("r", []) as Array)
		if r.size() >= 3:
			var rv := Vector3(float(r[0]), float(r[1]), float(r[2]))
			t.range_km = rv.length()
			t.bearing_deg = fposmod(rad_to_deg(atan2(rv.x, rv.y)), 360.0)
			t.range_sigma_km = maxf(0.5, t.range_km * 0.1)
			t.bearing_only = t.range_km <= 0.0
	t.classification = (seed_data.get("classification", {}) as Dictionary).duplicate(true)
	for raw in (seed_data.get("sources", []) as Array):
		t.sources.append(String(raw))
	for tg in (seed_data.get("tags", []) as Array):
		t.add_tag(String(tg))
	for nt in (seed_data.get("notes", []) as Array):
		t.notes.append(String(nt))
	# 播种后按证据年龄立即衰减（L4 播种 age>30s 会掉级，符合规则）。
	t.level = t.level_from_evidence(now)
	t.level_max_seen = t.level
	return t

# —— 观测入口 ——

## 融合一条观测；按 track_id → entity_id 查找，找不到就新建航迹。
func ingest(obs: Dictionary, now: float) -> V2Track:
	var t := _resolve_or_create(obs, now)
	if t == null:
		return null
	t.apply_observation(obs, now)
	return t

func ingest_all(obs_list: Array, now: float) -> Array:
	var out: Array = []
	for raw in obs_list:
		if raw is Dictionary:
			var t := ingest(raw, now)
			if t != null:
				out.append(t)
	return out

func _resolve_or_create(obs: Dictionary, now: float) -> V2Track:
	var tid := String(obs.get("track_id", obs.get("track", obs.get("batch", ""))))
	var eid := String(obs.get("entity_id", obs.get("entity", "")))
	var t: V2Track = null
	if tid != "":
		t = find(tid)
		if t != null and eid != "" and t.entity_id == "":
			t.entity_id = eid
			by_entity[eid] = t
	if t == null and eid != "":
		t = find_by_entity(eid)
	if t == null:
		t = _create(tid if tid != "" else _new_id(), eid, now)
	return t

func observe(track_id: String, obs: Dictionary, now: float) -> V2Track:
	var t := find(track_id)
	if t == null:
		errors.append("observe: 航迹不存在 " + track_id)
		return null
	var o := obs.duplicate(true)
	o["track_id"] = track_id
	t.apply_observation(o, now)
	return t

func ensure(track_id: String, entity_id: String, now: float) -> V2Track:
	var t := find(track_id)
	if t != null:
		if entity_id != "" and t.entity_id == "":
			t.entity_id = entity_id
			by_entity[entity_id] = t
		return t
	return _create(track_id, entity_id, now)

# —— 衰减 / 脚本设定 ——

## 推进所有航迹的衰减；返回等级变化列表 [{track_id, from, to, t}]。
func expire(now: float) -> Array:
	var transitions: Array = []
	for raw in tracks:
		var t: V2Track = raw
		var old := t.age(now)
		if old >= 0:
			transitions.append({"track_id": t.id, "from": old, "to": t.level, "t": now, "reason": "decay"})
	return transitions

func set_identity(track_id: String, kind: String, details: Dictionary = {}, now: float = -1.0) -> bool:
	var t := find(track_id)
	if t == null:
		return false
	t.set_identity(kind, details, now)
	return true

func set_level(track_id: String, new_level: int, now: float, note_text := "") -> bool:
	var t := find(track_id)
	if t == null:
		return false
	t.force_level(new_level, now, note_text)
	return true

func set_threat(track_id: String, kind: String) -> bool:
	var t := find(track_id)
	if t == null:
		return false
	t.set_threat(kind)
	return true

## UI/存档用的扁平视图。
func summary() -> Array:
	var out: Array = []
	for raw in tracks:
		var t: V2Track = raw
		out.append({
			"id": t.id, "entity_id": t.entity_id, "level": t.level,
			"level_name": t.level_name(), "level_label": t.level_label(),
			"identity": t.identity_kind, "identity_label": t.identity_label(),
			"threat": t.threat, "stale": t.stale, "bearing_only": t.is_bearing_only(),
			"bearing_deg": t.bearing_deg, "range_km": t.range_km,
			"age_s": t.age_s, "sources": t.sources.duplicate(),
			"quality": t.quality, "observation_count": t.observation_count,
			"notes": t.notes.duplicate(),
		})
	return out

func to_dicts() -> Array:
	var out: Array = []
	for raw in tracks:
		var t: V2Track = raw
		out.append(t.to_dict())
	return out