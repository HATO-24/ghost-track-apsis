class_name V2FusedTrackTable
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2F · TrackTable 单写者 / 观测·证据融合
#
# 数据流（docs/06 §1）：
#   Observation / Evidence / TrackUpdate 事件 → 唯一 writer（sensor/fusion authority）
#   → V2FusedTrackTable → 只读 VM（tracks/filter/selected/summary）
#
# 规则：
#   * 单写者：任何写事件必须带当前 writer_id；UI 只读，无写入 API；
#   * 等级 L1–L4 只增不减；观测自动融合最高到 L2；L3/L4 必须 Evidence；
#   * 身份六级：unknown/assumed_friend/friend/neutral/suspect/hostile；
#     **不明不判敌**：hostile 仅在显式 authoritative 证据/玩家授权时写入；
#   * 去重/合并：同 entity_id/batch 归并；event_id 去重；证据可追溯；
#   * 过期：stale_after_s 标记 stale，forget_after_s 移除；
#   * 不写 world/V15；不接传感器/物理/UI。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA_TABLE := "fused_track_table.v1"
const SCHEMA_TRACK := "fused_track.v1"
const SCHEMA_EVENT := "fused_track_event.v1"
const SAVE_SCHEMA := "v17.fused_track_table_save.v1"
const SAVE_VERSION := "1.0.0"
const INPUT_OBS := "sensor_observation.v1"
const INPUT_EVIDENCE := "track_evidence.v1"
const INPUT_UPDATE := "track_update.v1"

const LEVELS := [1, 2, 3, 4]
const LEVEL_NAMES := {1: "L1_BEARING", 2: "L2_POSITION", 3: "L3_CLASSIFIED",
	4: "L4_IDENTIFIED"}
const LEVEL_LABELS := {1: "方位", 2: "定位", 3: "分类", 4: "识别"}
const IDENTITIES := ["unknown", "assumed_friend", "friend", "neutral", "suspect", "hostile"]
const IDENTITY_LABELS := {
	"unknown": "未知", "assumed_friend": "假定友好", "friend": "友方",
	"neutral": "中立", "suspect": "可疑", "hostile": "敌方",
}
const THREATS := ["none", "unknown", "suspect", "hostile"]
const EVIDENCE_TYPES := ["optical", "elint", "iff", "datalink", "visual",
	"manual", "database", "track_update"]
const OBS_SENSORS := ["radar", "radar.tws", "optical", "ir", "elint", "crossfix",
	"datalink", "visual"]
const IFF_STATUS_MAP := {
	"friend": "friend", "neutral": "neutral", "no_reply": "unknown",
	"faulty_transponder": "unknown", "wrong_code": "unknown",
	"crypto_mismatch": "unknown", "captured": "suspect",
	"unknown": "unknown", "blocked": "unknown", "emcon_active": "unknown",
}
const MAX_EVIDENCE := 100
const MAX_EVENTS := 300

const DEFAULT_CONFIG := {
	"writer_id": "fusion_authority",
	"stale_after_s": 30.0,
	"forget_after_s": 300.0,
	"track_id_prefix": "T",
	"track_id_pad": 4,
	"max_tracks": 256,
	"allow_observation_level2": true,
}
const KEYS := {
	"writer_id": "writer_id", "stale_after_s": "stale_after_s",
	"forget_after_s": "forget_after_s", "track_id_prefix": "track_id_prefix",
	"track_id_pad": "track_id_pad", "max_tracks": "max_tracks",
	"allow_observation_level2": "allow_observation_level2",
}

var ready := false
var t := 0.0
var writer_id := "fusion_authority"
var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var tracks: Dictionary = {}        # id -> track dict
var by_entity: Dictionary = {}
var by_batch: Dictionary = {}
var next_id := 1
var errors: Array = []
var warnings: Array = []
var events: Array = []
var _outbox: Array = []
var _event_seq := 0
var _seen_event_ids: Dictionary = {}
var _subscribers: Array = []


func _init(cfg := {}) -> void:
	setup(cfg)


func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	writer_id = "fusion_authority"
	config = DEFAULT_CONFIG.duplicate(true)
	if cfg is Dictionary:
		for k in (cfg as Dictionary).keys():
			var key := String(k)
			if config.has(key):
				config[key] = (cfg as Dictionary)[k]
	writer_id = String(config.get("writer_id", "fusion_authority"))
	if writer_id.strip_edges() == "":
		errors.append("writer_id 不能为空")
		return false
	for k in ["stale_after_s", "forget_after_s"]:
		var v := float(config.get(k, 0.0))
		if not is_finite(v) or v < 0.0:
			errors.append("%s 非法" % k)
	if float(config.get("forget_after_s", 0.0)) < float(config.get("stale_after_s", 0.0)):
		errors.append("forget_after_s 必须 >= stale_after_s")
	if int(config.get("track_id_pad", 4)) < 1:
		errors.append("track_id_pad 非法")
	tracks = {}
	by_entity = {}
	by_batch = {}
	next_id = 1
	events = []
	_outbox = []
	_event_seq = 0
	_seen_event_ids = {}
	_subscribers = []
	ready = errors.is_empty()
	return ready


func _reset_tracks_only() -> void:
	tracks = {}
	by_entity = {}
	by_batch = {}
	next_id = 1
	events = []
	_outbox = []
	_event_seq = 0
	_seen_event_ids = {}


# ── 单写者 / 只读订阅 ───────────────────────────────────────────

func current_writer() -> String:
	return writer_id


## 首次 claim 可设 writer；之后不同 writer 一律冲突（单写者）。
func claim_writer(id: String) -> Dictionary:
	if id.strip_edges() == "":
		return {"ok": false, "reason": "empty_writer"}
	if writer_id == "":
		writer_id = id
		return {"ok": true, "reason": "", "writer_id": writer_id}
	if id == writer_id:
		return {"ok": true, "reason": "", "writer_id": writer_id}
	return {"ok": false, "reason": "writer_conflict", "writer_id": writer_id,
		"requested": id}


## UI/观察者可订阅只读事件（收到的都是副本，不得回写）。
func subscribe(handler: Callable) -> bool:
	if not (handler.is_valid()):
		return false
	_subscribers.append(handler)
	return true


func unsubscribe(handler: Callable) -> bool:
	for i in range(_subscribers.size()):
		if _subscribers[i] == handler:
			_subscribers.remove_at(i)
			return true
	return false


func _authorized(writer: String) -> bool:
	return ready and writer != "" and writer == writer_id


# ── 输入入口 ───────────────────────────────────────────────────

func handle_event(event: Dictionary, writer := "") -> Dictionary:
	if not _authorized(writer):
		return _reject("unauthorized_writer", event, writer, "writer_id 不是当前单写者")
	var kind := String(event.get("kind", ""))
	var schema := String(event.get("schema", ""))
	var eid := String(event.get("event_id", ""))
	if eid != "" and _seen_event_ids.has(eid):
		return _reject("duplicate_event", event, writer, "event_id 已处理")
	if schema == "":
		return _reject("missing_schema", event, writer, "事件缺 schema")
	var out: Dictionary
	if schema == INPUT_OBS or kind == "observation":
		out = _handle_observation(event, writer)
	elif schema == INPUT_EVIDENCE or kind == "evidence":
		out = _handle_evidence(event, writer)
	elif schema == INPUT_UPDATE or kind == "track_update":
		out = _handle_track_update(event, writer)
	else:
		return _reject("unknown_event_schema", event, writer, "未知 schema/kind")
	if eid != "":
		_seen_event_ids[eid] = true
	return out


func handle_observation(event: Dictionary, writer := "") -> Dictionary:
	return handle_event(_with_schema(event, INPUT_OBS, "observation"), writer)


func handle_evidence(event: Dictionary, writer := "") -> Dictionary:
	return handle_event(_with_schema(event, INPUT_EVIDENCE, "evidence"), writer)


func handle_track_update(event: Dictionary, writer := "") -> Dictionary:
	return handle_event(_with_schema(event, INPUT_UPDATE, "track_update"), writer)


func _with_schema(event: Dictionary, schema: String, kind: String) -> Dictionary:
	var e: Dictionary = event.duplicate(true)
	if not e.has("schema"):
		e["schema"] = schema
	if not e.has("kind"):
		e["kind"] = kind
	return e


# ── Observation 融合（最高 L2）──────────────────────────────────

func _handle_observation(ev: Dictionary, writer: String) -> Dictionary:
	var et := float(ev.get("t", t))
	if not _check_event_time(et, ev, writer):
		return _reject("time_regression", ev, writer, "事件时间早于表时间")
	var sensor := String(ev.get("sensor", ""))
	if sensor == "" or not (sensor in OBS_SENSORS):
		return _reject("invalid_sensor", ev, writer, "sensor 非法: " + sensor)
	var support := int(ev.get("support", ev.get("level_support", 1)))
	if support < 1 or support > 4:
		return _reject("invalid_support", ev, writer, "support 必须在 1..4")
	if support > 2:
		return _reject("observation_level_too_high", ev, writer,
			"观测自动融合最高 L2；L3/L4 必须 Evidence")
	var key := _resolve_track_key(ev)
	if key.is_empty():
		return _reject("missing_track_identity", ev, writer,
			"需要 track_id/entity_id/batch 至少一个")
	var tr = _find_track(event_key(ev))
	var created := false
	if tr.is_empty():
		tr = _create_track(ev, et)
		if tr.is_empty():
			return _reject("track_limit", ev, writer, "tracks 容量已满")
		created = true
	var track: Dictionary = tr
	var srcs: Array = track.get("sources", []) as Array
	var had_other_source := false
	for s in srcs:
		if String(s) != sensor:
			had_other_source = true
	var candidate := 1
	if support >= 2 or had_other_source or bool(config.get("allow_observation_level2", true)) and _distinct_sources_after(track, sensor) >= 2:
		candidate = 2
	var new_level := maxi(int(track.get("level", 1)), candidate)
	# Observation 最多 L2；不自动 L3/L4
	new_level = mini(new_level, 2)
	_apply_level(track, new_level, et, "observation:" + sensor)
	_add_source(track, sensor)
	var qual := clampf(float(ev.get("quality", track.get("quality", 1.0))), 0.0, 1.0)
	track["quality"] = maxf(float(track.get("quality", 0.0)), qual)
	track["last_update"] = et
	track["bearing_deg"] = float(ev.get("bearing_deg", track.get("bearing_deg", 0.0)))
	if ev.has("range_km"):
		track["range_km"] = float(ev.get("range_km", 0.0))
	_update_batch_entity(track, ev)
	var evd := _add_evidence(track, {
		"type": "observation", "sensor": sensor, "support": new_level,
		"t": et, "quality": qual, "source": sensor,
		"detail": String(ev.get("detail", "")),
	})
	var action := "track_created" if created else "track_updated"
	_emit(action, track, et, {"input": "observation", "sensor": sensor,
		"level": new_level, "evidence_id": String(evd.get("evidence_id", "")),
		"reason": ""})
	return {"ok": true, "reason": "", "action": action, "created": created,
		"track": _track_copy(track), "level": new_level,
		"event": (events[-1] as Dictionary).duplicate(true)}


# ── Evidence 融合（L3/L4 / 身份）──────────────────────────────

func _handle_evidence(ev: Dictionary, writer: String) -> Dictionary:
	var et := float(ev.get("t", t))
	if not _check_event_time(et, ev, writer):
		return _reject("time_regression", ev, writer, "事件时间早于表时间")
	var etype := String(ev.get("evidence_type", ev.get("type", "")))
	if etype == "" or not (etype in EVIDENCE_TYPES):
		return _reject("invalid_evidence_type", ev, writer, "evidence_type 非法: " + etype)
	var key := _resolve_track_key(ev)
	if key.is_empty():
		return _reject("missing_track_identity", ev, writer, "需要 track_id/entity_id/batch")
	var tr = _find_track(event_key(ev))
	if tr.is_empty():
		return _reject("unknown_track", ev, writer, "Evidence 目标航迹不存在")
	var track: Dictionary = tr
	var support := int(ev.get("support", ev.get("level_support", _default_evidence_support(etype))))
	if support < 1 or support > 4:
		return _reject("invalid_support", ev, writer, "support 必须在 1..4")
	if support < 3 and support < int(track.get("level", 1)):
		support = int(track.get("level", 1))
	var identity := String(ev.get("identity", ""))
	if identity == "" and ev.get("iff") is Dictionary:
		identity = _identity_from_iff(ev.get("iff") as Dictionary)
	var threat := String(ev.get("threat", ""))
	# DbC：先校验身份/威胁，再改等级/证据（拒绝时不产生部分写入）
	if identity != "":
		var ic := _check_identity(identity, ev)
		if not bool(ic.get("ok", false)):
			return _reject(String(ic.get("reason", "invalid_identity")), ev, writer,
				String(ic.get("detail", "")))
	if threat != "":
		var tc := _check_threat(threat, ev)
		if not bool(tc.get("ok", false)):
			return _reject(String(tc.get("reason", "invalid_threat")), ev, writer,
				String(tc.get("detail", "")))
	var new_level := maxi(int(track.get("level", 1)), support)
	_apply_level(track, new_level, et, "evidence:" + etype)
	if identity != "":
		_set_identity(track, identity, ev, et)
	if threat != "":
		_set_threat(track, threat, ev, et)
	_add_source(track, etype)
	track["last_update"] = et
	var evd := _add_evidence(track, {
		"type": etype, "sensor": etype, "support": support, "t": et,
		"identity": identity, "threat": threat,
		"source": String(ev.get("source", etype)),
		"detail": String(ev.get("detail", "")),
	})
	_emit("track_updated", track, et, {"input": "evidence", "evidence_type": etype,
		"level": new_level, "identity": identity, "threat": threat,
		"evidence_id": String(evd.get("evidence_id", "")), "reason": ""})
	return {"ok": true, "reason": "", "action": "track_updated", "created": false,
		"track": _track_copy(track), "level": new_level,
		"event": (events[-1] as Dictionary).duplicate(true)}


func _default_evidence_support(etype: String) -> int:
	if etype in ["optical", "elint", "database"]:
		return 3
	if etype in ["iff", "datalink", "visual", "manual"]:
		return 4
	return 3


func _identity_from_iff(iff: Dictionary) -> String:
	var st := String(iff.get("status", iff.get("iff_status", "")))
	if IFF_STATUS_MAP.has(st):
		return String(IFF_STATUS_MAP[st])
	return "unknown"


# ── TrackUpdate（仅融合 authority）────────────────────────────

func _handle_track_update(ev: Dictionary, writer: String) -> Dictionary:
	var et := float(ev.get("t", t))
	if not _check_event_time(et, ev, writer):
		return _reject("time_regression", ev, writer, "事件时间早于表时间")
	var tr = _find_track(event_key(ev))
	if tr.is_empty():
		return _reject("unknown_track", ev, writer, "TrackUpdate 目标不存在")
	var track: Dictionary = tr
	var level_before := int(track.get("level", 1))
	var new_level := level_before
	if ev.has("level"):
		var lv := int(ev.get("level", level_before))
		if not (lv in LEVELS):
			return _reject("invalid_level", ev, writer, "level 必须在 1..4")
		if lv < level_before:
			return _reject("level_regression", ev, writer,
				"等级不可倒退（%d→%d）" % [level_before, lv])
		new_level = lv
	var identity := String(ev.get("identity", "")) if ev.has("identity") else ""
	var threat := String(ev.get("threat", "")) if ev.has("threat") else ""
	if identity != "":
		var ic := _check_identity(identity, ev)
		if not bool(ic.get("ok", false)):
			return _reject(String(ic.get("reason", "invalid_identity")), ev, writer,
				String(ic.get("detail", "")))
	if threat != "":
		var tc := _check_threat(threat, ev)
		if not bool(tc.get("ok", false)):
			return _reject(String(tc.get("reason", "invalid_threat")), ev, writer,
				String(tc.get("detail", "")))
	if ev.has("level"):
		_apply_level(track, new_level, et, "track_update")
	if identity != "":
		_set_identity(track, identity, ev, et)
	if threat != "":
		_set_threat(track, threat, ev, et)
	if ev.has("quality"):
		track["quality"] = clampf(float(ev.get("quality", track.get("quality", 1.0))), 0.0, 1.0)
	if ev.get("sources") is Array:
		for s in (ev.get("sources") as Array):
			_add_source(track, String(s))
	track["last_update"] = et
	var evd := _add_evidence(track, {"type": "track_update", "support": int(track.get("level", 1)),
		"t": et, "source": writer, "detail": String(ev.get("reason", ""))})
	_emit("track_updated", track, et, {"input": "track_update",
		"level": int(track.get("level", 1)), "evidence_id": String(evd.get("evidence_id", "")),
		"reason": ""})
	return {"ok": true, "reason": "", "action": "track_updated", "created": false,
		"track": _track_copy(track), "level": int(track.get("level", 1)),
		"event": (events[-1] as Dictionary).duplicate(true)}


# ── track 辅助 / 等级 / 身份 ───────────────────────────────────

func _create_track(ev: Dictionary, et: float) -> Dictionary:
	if tracks.size() >= int(config.get("max_tracks", 256)):
		return {}
	var id := _generate_id()
	var batch := String(ev.get("batch", ""))
	var entity_id := String(ev.get("entity_id", ""))
	var identity := "unknown"
	var threat := "none"
	var quality := clampf(float(ev.get("quality", 1.0)), 0.0, 1.0)
	var track := {
		"schema": SCHEMA_TRACK, "id": id, "track_id": id,
		"batch": batch, "entity_id": entity_id,
		"level": 0, "level_name": "L0", "identity": identity,
		"identity_label": IDENTITY_LABELS.get(identity, identity),
		"threat": threat, "quality": quality,
		"sources": [], "evidence": [], "evidence_ids": [],
		"created_t": et, "last_update": et, "stale": false,
		"bearing_deg": -1.0, "range_km": -1.0, "merged_from": [],
	}
	tracks[id] = track
	if batch != "":
		by_batch[batch] = id
	if entity_id != "":
		by_entity[entity_id] = id
	return track


func _generate_id() -> String:
	var pad := maxi(1, int(config.get("track_id_pad", 4)))
	var prefix := String(config.get("track_id_prefix", "T"))
	var num := str(next_id)
	while num.length() < pad:
		num = "0" + num
	var id := prefix + num
	while tracks.has(id):
		next_id += 1
		num = str(next_id)
		while num.length() < pad:
			num = "0" + num
		id = prefix + num
	next_id += 1
	return id


func _resolve_track_key(ev: Dictionary) -> String:
	return event_key(ev)


func event_key(ev: Dictionary) -> String:
	var tid := String(ev.get("track_id", ev.get("target_id", "")))
	if tid != "":
		return tid
	var eid := String(ev.get("entity_id", ""))
	if eid != "":
		return eid
	var b := String(ev.get("batch", ""))
	if b != "":
		return b
	return ""


func _find_track(key: String) -> Dictionary:
	if key == "":
		return {}
	if tracks.has(key):
		return tracks[key]
	if by_entity.has(key):
		return tracks.get(by_entity[key], {})
	if by_batch.has(key):
		return tracks.get(by_batch[key], {})
	return {}


func _update_batch_entity(track: Dictionary, ev: Dictionary) -> void:
	if String(track.get("batch", "")) == "" and String(ev.get("batch", "")) != "":
		track["batch"] = String(ev.get("batch", ""))
		by_batch[String(ev.get("batch", ""))] = String(track.get("id", ""))
	if String(track.get("entity_id", "")) == "" and String(ev.get("entity_id", "")) != "":
		track["entity_id"] = String(ev.get("entity_id", ""))
		by_entity[String(ev.get("entity_id", ""))] = String(track.get("id", ""))


func _distinct_sources_after(track: Dictionary, sensor: String) -> int:
	var seen: Dictionary = {}
	for s in (track.get("sources", []) as Array):
		seen[String(s)] = true
	seen[sensor] = true
	return seen.size()


func _apply_level(track: Dictionary, new_level: int, et: float, reason: String) -> void:
	var clamped := clampi(new_level, 1, 4)
	var old := int(track.get("level", 0))
	if clamped < old:
		return
	track["level"] = clamped
	track["level_name"] = String(LEVEL_NAMES.get(clamped, "L%d" % clamped))
	track["last_update"] = et
	# 等级证据时间戳（可追溯）
	if not (track.get("level_evidence") is Dictionary):
		track["level_evidence"] = {}
	(track["level_evidence"] as Dictionary)[str(clamped)] = et
	if clamped > old:
		var evid: Array = track.get("evidence", []) as Array
		evid.append({"type": "level", "level": clamped, "t": et, "reason": reason,
			"evidence_id": "E%06d" % (_event_seq + 1)})
		_trim_evidence(track)


func _check_identity(kind: String, ev: Dictionary) -> Dictionary:
	if not (kind in IDENTITIES):
		return {"ok": false, "reason": "invalid_identity",
			"detail": "身份必须是 " + ", ".join(IDENTITIES)}
	if kind == "hostile" and not _hostile_authorized(ev):
		return {"ok": false, "reason": "hostile_requires_authority",
			"detail": "不明不判敌：hostile 需要显式 authoritative/玩家授权"}
	return {"ok": true, "reason": "", "detail": ""}


func _check_threat(threat: String, ev: Dictionary) -> Dictionary:
	if not (threat in THREATS):
		return {"ok": false, "reason": "invalid_threat",
			"detail": "threat 必须是 " + ", ".join(THREATS)}
	if threat == "hostile" and not _hostile_authorized(ev):
		return {"ok": false, "reason": "hostile_requires_authority",
			"detail": "不明不判敌：threat=hostile 需要显式授权"}
	return {"ok": true, "reason": "", "detail": ""}


func _set_identity(track: Dictionary, kind: String, ev: Dictionary, et: float) -> Dictionary:
	var chk := _check_identity(kind, ev)
	if not bool(chk.get("ok", false)):
		return chk
	track["identity"] = kind
	track["identity_label"] = String(IDENTITY_LABELS.get(kind, kind))
	track["identity_t"] = et
	track["last_update"] = et
	return {"ok": true, "reason": "", "detail": ""}


func _set_threat(track: Dictionary, threat: String, ev: Dictionary, et: float) -> Dictionary:
	var chk := _check_threat(threat, ev)
	if not bool(chk.get("ok", false)):
		return chk
	track["threat"] = threat
	track["last_update"] = et
	return {"ok": true, "reason": "", "detail": ""}


func _hostile_authorized(ev: Dictionary) -> bool:
	if bool(ev.get("authoritative", false)) or bool(ev.get("explicit_hostile", false)):
		return true
	var src := String(ev.get("source", ev.get("evidence_type", ev.get("sensor", ""))))
	return src in ["manual", "player", "authority", "command"]


func _add_source(track: Dictionary, source: String) -> void:
	if source == "":
		return
	var srcs: Array = track.get("sources", []) as Array
	if not (source in srcs):
		srcs.append(source)
		srcs.sort()
		track["sources"] = srcs


func _add_evidence(track: Dictionary, base: Dictionary) -> Dictionary:
	var evid: Array = track.get("evidence", []) as Array
	var e: Dictionary = base.duplicate(true)
	_event_seq += 1
	e["evidence_id"] = "E%06d" % _event_seq
	e["seq"] = _event_seq
	if not evid.is_empty():
		var last: Dictionary = evid[evid.size() - 1]
		if String(last.get("type", "")) == String(e.get("type", "")) \
				and String(last.get("sensor", "")) == String(e.get("sensor", "")) \
				and absf(float(last.get("t", -1.0)) - float(e.get("t", -2.0))) < 1.0e-9 \
				and int(last.get("support", 0)) == int(e.get("support", 0)):
			return last
	evid.append(e)
	if not (track.get("evidence_ids") is Array):
		track["evidence_ids"] = []
	(track["evidence_ids"] as Array).append(String(e.get("evidence_id", "")))
	_trim_evidence(track)
	return e


func _trim_evidence(track: Dictionary) -> void:
	var evid: Array = track.get("evidence", []) as Array
	while evid.size() > MAX_EVIDENCE:
		evid.pop_front()
	track["evidence"] = evid


func _check_event_time(et: float, ev: Dictionary, writer: String) -> bool:
	if not is_finite(et):
		return false
	if et + 1.0e-9 < t:
		return false
	t = maxf(t, et)
	return true


func _track_copy(track: Dictionary) -> Dictionary:
	return track.duplicate(true)


# ── 过期 / 合并 / 去重 ──────────────────────────────────────────

## 推进时间并标记过期/移除；等级不倒退，只标记 stale/forget。
func tick(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	var stale_n := 0
	var forgotten: Array = []
	for id in tracks.keys():
		var tr: Dictionary = tracks[id]
		var age := t - float(tr.get("last_update", t))
		var stale_after := float(config.get("stale_after_s", 30.0))
		var forget_after := float(config.get("forget_after_s", 300.0))
		if age >= stale_after:
			if not bool(tr.get("stale", false)):
				tr["stale"] = true
				stale_n += 1
				_emit("track_stale", tr, t, {"reason": "age>stale_after_s",
					"level": int(tr.get("level", 1))})
		if forget_after > 0.0 and age >= forget_after:
			forgotten.append(id)
	for id in forgotten:
		var tr2: Dictionary = tracks[id]
		_remove_track(id)
		_emit("track_forgotten", tr2, t, {"reason": "age>forget_after_s",
			"level": int(tr2.get("level", 1))})
	return {"ok": true, "t": t, "stale": stale_n, "forgotten": forgotten,
		"events": _outbox.duplicate(true)}


func advance(now: float) -> Dictionary:
	if not is_finite(now):
		return {"ok": false, "reason": "non_finite_time"}
	if now + 1.0e-9 < t:
		return {"ok": false, "reason": "time_regression", "t": t, "requested": now}
	return tick(maxf(0.0, now - t))


## 合并同 entity_id/batch 的重复航迹（保留最早 id，等级取高，证据合并）。
func merge_duplicates() -> Array:
	var groups: Dictionary = {}
	for id in tracks.keys():
		var tr: Dictionary = tracks[id]
		var key := ""
		if String(tr.get("entity_id", "")) != "":
			key = "e:" + String(tr.get("entity_id", ""))
		elif String(tr.get("batch", "")) != "":
			key = "b:" + String(tr.get("batch", ""))
		if key == "":
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(id)
	var merged: Array = []
	for key in groups.keys():
		var ids: Array = groups[key]
		if ids.size() <= 1:
			continue
		ids.sort()
		var keep: Dictionary = tracks[ids[0]]
		for i in range(1, ids.size()):
			var drop: Dictionary = tracks[ids[i]]
			_merge_track(keep, drop)
			_remove_track(String(drop.get("id", "")))
			merged.append({"keep": String(keep.get("id", "")), "drop": String(drop.get("id", ""))})
	return merged


func _merge_track(keep: Dictionary, drop: Dictionary) -> void:
	keep["level"] = maxi(int(keep.get("level", 1)), int(drop.get("level", 1)))
	keep["level_name"] = String(LEVEL_NAMES.get(int(keep.get("level", 1)), "L%d" % int(keep.get("level", 1))))
	keep["level_evidence"] = _merge_dict(keep.get("level_evidence", {}), drop.get("level_evidence", {}))
	keep["quality"] = maxf(float(keep.get("quality", 0.0)), float(drop.get("quality", 0.0)))
	for s in (drop.get("sources", []) as Array):
		_add_source(keep, String(s))
	var ke: Array = keep.get("evidence", []) as Array
	for r in (drop.get("evidence", []) as Array):
		if r is Dictionary:
			ke.append((r as Dictionary).duplicate(true))
	keep["evidence"] = ke
	_trim_evidence(keep)
	keep["last_update"] = maxf(float(keep.get("last_update", 0.0)), float(drop.get("last_update", 0.0)))
	var mf: Array = keep.get("merged_from", []) as Array
	mf.append(String(drop.get("id", "")))
	for m in (drop.get("merged_from", []) as Array):
		mf.append(String(m))
	keep["merged_from"] = mf
	var bp := String(keep.get("batch", ""))
	var dp := String(drop.get("batch", ""))
	if bp == "":
		bp = dp
	keep["batch"] = bp
	if bp != "":
		by_batch[bp] = String(keep.get("id", ""))
	for eid in [String(drop.get("entity_id", "")), String(keep.get("entity_id", ""))]:
		if eid != "":
			by_entity[eid] = String(keep.get("id", ""))


func _merge_dict(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for k in b.keys():
		if not out.has(String(k)) or float(out[String(k)]) < float(b[k]):
			out[String(k)] = b[k]
	return out


func _remove_track(id: String) -> void:
	var tr = tracks.get(id, null)
	if not (tr is Dictionary):
		return
	var track: Dictionary = tr
	if String(track.get("batch", "")) != "" and String(by_batch.get(String(track.get("batch", "")), "")) == id:
		by_batch.erase(String(track.get("batch", "")))
	if String(track.get("entity_id", "")) != "" and String(by_entity.get(String(track.get("entity_id", "")), "")) == id:
		by_entity.erase(String(track.get("entity_id", "")))
	tracks.erase(id)


# ── 事件 / 拒绝 ────────────────────────────────────────────────

func _reject(reason: String, ev: Dictionary, writer: String, detail: String) -> Dictionary:
	errors.append(reason)
	_emit("rejected", {}, t, {"input": String(ev.get("kind", ev.get("schema", ""))),
		"reason": reason, "detail": detail, "writer_id": writer})
	return {"ok": false, "reason": reason, "detail": detail, "writer_id": writer,
		"writes_v15": false}


func _emit(action: String, track: Dictionary, et: float, extra: Dictionary) -> Dictionary:
	_event_seq += 1
	var ev := {
		"schema": SCHEMA_EVENT, "seq": _event_seq, "t": et, "action": action,
		"track_id": String(track.get("id", "")),
		"level": int(track.get("level", 0)),
		"identity": String(track.get("identity", "unknown")),
		"threat": String(track.get("threat", "none")),
		"reason": String(extra.get("reason", "")),
		"detail": String(extra.get("detail", "")),
		"input": String(extra.get("input", "")),
		"evidence_id": String(extra.get("evidence_id", "")),
		"level_after": int(track.get("level", 0)),
		"writes_v15": false,
		"writes_track_table": false,
		"shadow": true,
	}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))
	for raw in _subscribers:
		if raw is Callable and (raw as Callable).is_valid():
			(raw as Callable).call(ev.duplicate(true))
	return ev


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


# ── 只读查询 / VM ─────────────────────────────────────────────

func find(track_id: String) -> Dictionary:
	return _track_copy(_find_track(track_id))


func all_tracks() -> Array:
	var out: Array = []
	for id in tracks.keys():
		out.append(_track_copy(tracks[id]))
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


func active_count() -> int:
	var n := 0
	for id in tracks.keys():
		if not bool((tracks[id] as Dictionary).get("stale", false)):
			n += 1
	return n


func filter(where := {}) -> Array:
	var q: Dictionary = where if where is Dictionary else {}
	var out: Array = []
	for raw in all_tracks():
		var tr: Dictionary = raw
		if q.has("level_min") and int(tr.get("level", 0)) < int(q.get("level_min", 0)):
			continue
		if q.has("level_max") and int(tr.get("level", 0)) > int(q.get("level_max", 4)):
			continue
		if q.has("identity") and String(tr.get("identity", "")) != String(q.get("identity", "")):
			continue
		if q.has("stale") and bool(tr.get("stale", false)) != bool(q.get("stale", false)):
			continue
		if q.has("batch") and String(tr.get("batch", "")) != String(q.get("batch", "")):
			continue
		if q.has("source") and not (String(q.get("source", "")) in (tr.get("sources", []) as Array)):
			continue
		if q.has("id") and String(tr.get("id", "")) != String(q.get("id", "")):
			continue
		out.append(tr)
	return out


func selected(track_id: String) -> Dictionary:
	return _track_copy(_find_track(track_id))


func summary() -> Dictionary:
	var levels: Dictionary = {"1": 0, "2": 0, "3": 0, "4": 0}
	var idents: Dictionary = {}
	var stale_n := 0
	for id in tracks.keys():
		var tr: Dictionary = tracks[id]
		var lv := str(int(tr.get("level", 0)))
		levels[lv] = int(levels.get(lv, 0)) + 1
		var ik := String(tr.get("identity", "unknown"))
		idents[ik] = int(idents.get(ik, 0)) + 1
		if bool(tr.get("stale", false)):
			stale_n += 1
	return {
		"schema": SCHEMA_TABLE, "t": t, "writer_id": writer_id,
		"tracks": tracks.size(), "active": active_count(), "stale": stale_n,
		"by_level": levels, "by_identity": idents,
		"evidence": _count_evidence(),
		"writes": {"track_table": false, "v15": false},
	}


func _count_evidence() -> int:
	var n := 0
	for id in tracks.keys():
		n += ((tracks[id] as Dictionary).get("evidence", []) as Array).size()
	return n


func vm(opts := {}) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	var rows: Array = all_tracks()
	var query: Dictionary = o.get("filter", {}) if o.get("filter") is Dictionary else {}
	var filtered: Array = filter(query) if not query.is_empty() else rows
	var sel_id := String(o.get("selected_id", ""))
	var sel: Dictionary = selected(sel_id) if sel_id != "" else {}
	return {
		"schema": SCHEMA_TABLE, "mode": "single_writer", "authoritative": false,
		"ready": ready, "t": t, "writer_id": writer_id,
		"tracks": filtered, "all_count": rows.size(),
		"filter": query.duplicate(true), "selected": sel,
		"summary": summary(), "events": events.duplicate(true),
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"track_table": false, "v15": false},
		"notes": ["TrackTable 单写者：仅 writer_id 可写；UI 只读",
			"身份六级；不明不判敌（hostile 需显式授权）"],
	}


## 保存快照（Dictionary；JSON-safe，可直接放进 SaveService payload）。
func snapshot() -> Dictionary:
	var seen: Array = []
	for k in _seen_event_ids.keys():
		seen.append(String(k))
	seen.sort()
	return {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION,
		"table_schema": SCHEMA_TABLE, "t": t, "writer_id": writer_id,
		"config": config.duplicate(true),
		"tracks": all_tracks(),
		"next_id": next_id, "event_seq": _event_seq,
		"seen_event_ids": seen,
		"events": JSON.parse_string(JSON.stringify(events)),
		"outbox": JSON.parse_string(JSON.stringify(_outbox)),
		"errors": errors.duplicate(true), "warnings": warnings.duplicate(true),
	}


## 保存为 JSON 字符串（与 SaveService 的 JSON payload 兼容）。
func save_state() -> String:
	return JSON.stringify(snapshot())


func save_payload() -> Dictionary:
	return snapshot()


## 恢复快照（String 或 Dictionary）；先完整校验，失败不改当前状态。
func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		var txt := String(data)
		if txt.strip_edges() == "":
			return {"ok": false, "reason": "empty_state", "errors": ["空快照"]}
		parsed = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json", "errors": ["快照 JSON 无效"]}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload", "errors": ["快照必须是对象"]}
	var payload: Dictionary = parsed
	var errs := _validate_save_payload(payload)
	if not errs.is_empty():
		return {"ok": false, "reason": "invalid_payload", "errors": errs,
			"from_version": String(payload.get("version", ""))}
	_apply_save_payload(payload)
	var out := {"ok": true, "reason": "", "errors": [], "version": SAVE_VERSION,
		"from_version": String(payload.get("version", "")), "migrated": false,
		"tracks": tracks.size(), "events": events.size(),
		"writes_v15": false, "writes_track_table": false}
	return out


func restore(data: Variant) -> Dictionary:
	return load_state(data)


func load_save_payload(data: Variant) -> Dictionary:
	return load_state(data)


func _validate_save_payload(p: Dictionary) -> Array:
	var errs: Array = []
	if String(p.get("schema", "")) != SAVE_SCHEMA:
		errs.append("save schema 必须为 " + SAVE_SCHEMA)
	var ver := String(p.get("version", ""))
	if ver == "":
		errs.append("缺 version")
	elif ver != SAVE_VERSION:
		var cmp := _compare_version(ver, SAVE_VERSION)
		if cmp > 0:
			errs.append("不支持未来版本: " + ver)
		else:
			errs.append("不支持的旧版本（无迁移路径）: " + ver)
	if String(p.get("table_schema", "")) != SCHEMA_TABLE:
		errs.append("table_schema 不匹配")
	if not (p.get("config") is Dictionary):
		errs.append("config 必须是对象")
	else:
		var cfg: Dictionary = p.get("config")
		var stale := float(cfg.get("stale_after_s", -1.0))
		var forget := float(cfg.get("forget_after_s", -1.0))
		if not is_finite(stale) or stale < 0.0:
			errs.append("config.stale_after_s 非法")
		if not is_finite(forget) or forget < stale:
			errs.append("config.forget_after_s 非法")
		if int(cfg.get("track_id_pad", 0)) < 1:
			errs.append("config.track_id_pad 非法")
	var wt := String(p.get("writer_id", ""))
	if wt.strip_edges() == "":
		errs.append("writer_id 不能为空")
	var tt := float(p.get("t", NAN))
	if not is_finite(tt) or tt < 0.0:
		errs.append("t 非法")
	if int(p.get("next_id", 0)) < 1:
		errs.append("next_id 非法")
	if int(p.get("event_seq", -1)) < 0:
		errs.append("event_seq 非法")
	if not (p.get("seen_event_ids") is Array):
		errs.append("seen_event_ids 必须是数组")
	if not (p.get("events") is Array):
		errs.append("events 必须是数组")
	if not (p.get("outbox") is Array):
		errs.append("outbox 必须是数组")
	var raw_tracks = p.get("tracks", null)
	if not (raw_tracks is Array):
		errs.append("tracks 必须是数组")
		return errs
	var ids: Dictionary = {}
	for i in range((raw_tracks as Array).size()):
		var one = (raw_tracks as Array)[i]
		if not (one is Dictionary):
			errs.append("tracks[%d] 必须为对象" % i)
			continue
		var tr: Dictionary = one
		var tid := String(tr.get("id", ""))
		if tid == "":
			errs.append("tracks[%d] 缺 id" % i)
		elif ids.has(tid):
			errs.append("tracks 重复 id: " + tid)
		else:
			ids[tid] = true
		if not (int(tr.get("level", 0)) in LEVELS):
			errs.append("track %s level 非法" % tid)
		if not (String(tr.get("identity", "")) in IDENTITIES):
			errs.append("track %s identity 非法" % tid)
		if not (String(tr.get("threat", "")) in THREATS):
			errs.append("track %s threat 非法" % tid)
		if not (tr.get("sources") is Array):
			errs.append("track %s sources 非法" % tid)
		if not (tr.get("evidence") is Array):
			errs.append("track %s evidence 非法" % tid)
		var q := float(tr.get("quality", NAN))
		if not is_finite(q) or q < 0.0 or q > 1.0:
			errs.append("track %s quality 非法" % tid)
		if not is_finite(float(tr.get("last_update", NAN))):
			errs.append("track %s last_update 非法" % tid)
	return errs


func _compare_version(a: String, b: String) -> int:
	var aa := _version_parts(a)
	var bb := _version_parts(b)
	for i in range(3):
		var x := int(aa[i]) if i < aa.size() else 0
		var y := int(bb[i]) if i < bb.size() else 0
		if x < y:
			return -1
		if x > y:
			return 1
	return 0


func _version_parts(v: String) -> Array:
	var out: Array = []
	for part in v.split("."):
		out.append(int(part))
	return out


func _apply_save_payload(p: Dictionary) -> void:
	config = (p.get("config", {}) as Dictionary).duplicate(true)
	writer_id = String(p.get("writer_id", "fusion_authority"))
	t = float(p.get("t", 0.0))
	next_id = int(p.get("next_id", 1))
	_event_seq = int(p.get("event_seq", 0))
	_seen_event_ids = {}
	for raw in (p.get("seen_event_ids", []) as Array):
		_seen_event_ids[String(raw)] = true
	tracks = {}
	by_entity = {}
	by_batch = {}
	for raw in (p.get("tracks", []) as Array):
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = (raw as Dictionary).duplicate(true)
		var tid := String(tr.get("id", ""))
		tracks[tid] = tr
		var eid := String(tr.get("entity_id", ""))
		if eid != "" and not by_entity.has(eid):
			by_entity[eid] = tid
		var b := String(tr.get("batch", ""))
		if b != "" and not by_batch.has(b):
			by_batch[b] = tid
	events = JSON.parse_string(JSON.stringify(p.get("events", [])))
	if not (events is Array):
		events = []
	_outbox = JSON.parse_string(JSON.stringify(p.get("outbox", [])))
	if not (_outbox is Array):
		_outbox = []
	_normalize_loaded_types()
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	_subscribers = []
	ready = true


## JSON 会把整数解析成 float；恢复时把有契约的整数字段归一，保证 VM/save 往返一致。
func _normalize_loaded_types() -> void:
	next_id = int(next_id)
	_event_seq = int(_event_seq)
	config["track_id_pad"] = int(config.get("track_id_pad", 4))
	config["max_tracks"] = int(config.get("max_tracks", 256))
	for raw in events:
		if raw is Dictionary:
			_normalize_event_dict(raw as Dictionary)
	for raw in _outbox:
		if raw is Dictionary:
			_normalize_event_dict(raw as Dictionary)
	for tid in tracks.keys():
		var tr: Dictionary = tracks[tid]
		tr["level"] = int(tr.get("level", 0))
		if tr.get("level_evidence") is Dictionary:
			var le: Dictionary = {}
			for k in (tr.get("level_evidence") as Dictionary).keys():
				le[String(k)] = float((tr.get("level_evidence") as Dictionary)[k])
			tr["level_evidence"] = le
		if tr.get("evidence") is Array:
			for raw_e in (tr.get("evidence") as Array):
				if raw_e is Dictionary:
					var e: Dictionary = raw_e
					if e.has("seq"):
						e["seq"] = int(e.get("seq", 0))
					if e.has("support"):
						e["support"] = int(e.get("support", 0))
					if e.has("level"):
						e["level"] = int(e.get("level", 0))
					if e.has("t"):
						e["t"] = float(e.get("t", 0.0))
					if e.has("quality"):
						e["quality"] = float(e.get("quality", 0.0))


func _normalize_event_dict(e: Dictionary) -> void:
	for k in ["seq", "level", "level_after", "relay_count", "track_id"]:
		if k == "track_id":
			continue
		if e.has(k):
			e[k] = int(e.get(k, 0))
	if e.has("t"):
		e["t"] = float(e.get("t", 0.0))
	if e.has("delay_s"):
		e["delay_s"] = float(e.get("delay_s", 0.0))
	if e.has("level"):
		e["level"] = int(e.get("level", 0))
	if e.has("level_after"):
		e["level_after"] = int(e.get("level_after", 0))





func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())
