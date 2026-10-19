class_name V2ObservationBridge
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 观测适配层（sim → core）
#
#   sim/ 里的传感器模型（保留的 SensorModel 或 V2RadarModel/V2TwsModel/
#   V2OpticalModel）产出的是「传感器观测字典」；core/tracks.gd 只接受
#   V2 观测 schema。本文件负责格式适配，不做任何物理判定。
#
#   统一后的 V2 观测字段：
#     track_id / entity_id   二选一（都没有则新建匿名航迹，批号自动分配）
#     sensor  型号（如 CH-IR2）      source  观测平台（如 harmattan）
#     kind    ir/radar/optical/lidar/iff/elint/crossfix/...
#     t       观测时间（秒）          quality 0–1 观测质量
#     support 支撑级 1–4（可缺省，由 content/track_rules.json 的 sensor_support 推）
#     bearing_deg / bearing_sigma_deg / range_km / range_sigma_km / range_band
#     classification / identity / iff_status / signal / notes / detected
#
#   本框架不做雷达渲染；观测到航迹的融合规则在 core，不在 sim。
# ═══════════════════════════════════════════════════════════════════

## 把一条 sim 观测 / v15 SensorModel 观测转成 V2 观测。
static func to_core_observation(raw: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var obs: Dictionary = {}
	obs["detected"] = bool(raw.get("detected", false))
	obs["kind"] = String(raw.get("kind", opts.get("kind", "")))
	obs["sensor"] = String(raw.get("sensor", raw.get("sensor_id", opts.get("sensor", ""))))
	obs["source"] = String(opts.get("source", raw.get("source", raw.get("observer",
		raw.get("observer_id", "")))))
	obs["t"] = float(raw.get("t", opts.get("t", -1.0)))
	var q = raw.get("quality", null)
	if q != null:
		obs["quality"] = float(q)
	var support = raw.get("support", raw.get("level_support", null))
	if support != null:
		obs["support"] = int(support)
	elif opts.has("support"):
		obs["support"] = int(opts.get("support"))
	for k in ["bearing_deg", "bearing_sigma_deg", "range_km", "range_sigma_km",
			"range_band", "radial_vel_kmps", "speed_mps"]:
		if raw.has(k):
			obs[k] = raw[k]
	if raw.has("position") and raw.get("position") is Dictionary:
		obs["position"] = (raw.get("position") as Dictionary).duplicate(true)

	# 身份/分类/信号：sim 观测里直接透传。
	if raw.has("classification") and raw.get("classification") is Dictionary:
		obs["classification"] = (raw.get("classification") as Dictionary).duplicate(true)
	if raw.has("identity") and raw.get("identity") is Dictionary:
		obs["identity"] = (raw.get("identity") as Dictionary).duplicate(true)
	if raw.has("identity_kind"):
		obs["identity_kind"] = raw["identity_kind"]
	if raw.has("iff_status"):
		obs["iff_status"] = String(raw.get("iff_status", ""))
	if raw.has("signal") and raw.get("signal") is Dictionary:
		obs["signal"] = (raw.get("signal") as Dictionary).duplicate(true)
	if raw.has("threat"):
		obs["threat"] = String(raw.get("threat", ""))
	if raw.has("notes") and raw.get("notes") is Array:
		obs["notes"] = (raw.get("notes") as Array).duplicate()
	if raw.has("reason"):
		obs["reason"] = String(raw.get("reason", ""))

	# 目标标识：优先显式 entity_id / track_id，其次 target_id/batch 经映射。
	var entity_id := String(raw.get("entity_id", opts.get("entity_id", "")))
	var track_id := String(raw.get("track_id", opts.get("track_id", "")))
	var target_id := String(raw.get("target_id", raw.get("batch", "")))
	if target_id != "":
		var entity_ids: Array = (opts.get("entity_ids", []) as Array)
		var track_map: Dictionary = (opts.get("track_map", {}) as Dictionary)
		if track_map.has(target_id):
			track_id = String(track_map[target_id])
		elif target_id in entity_ids:
			entity_id = target_id
		elif track_id == "":
			track_id = target_id
	if entity_id != "":
		obs["entity_id"] = entity_id
	if track_id != "":
		obs["track_id"] = track_id
	return obs

## 一次扫描结果 → V2 观测数组（只保留 detected 的观测，其余保留 reason 供调试）。
static func scan_to_observations(scan: Dictionary, opts: Dictionary = {}) -> Array:
	var out: Array = []
	var list: Array = scan.get("observations", [])
	for raw in list:
		if not (raw is Dictionary):
			continue
		var obs := to_core_observation(raw, opts)
		if bool(obs.get("detected", false)):
			out.append(obs)
	return out

## 便捷入口：把一次扫描直接喂进 world（entity_id 目标优先）。
static func ingest_scan(world: V2World, scan: Dictionary, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for obs in scan_to_observations(scan, opts):
		var tr := world.ingest(obs)
		if tr != null:
			out.append(tr)
	return out

## TWS 通道处于这些状态时才有可注入的跟踪观测（失锁/SEARCH/DETECT 不注入）。
const TWS_ACTIVE_STATES := ["ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]

## TWS 通道 → core 观测（约定见 docs/34 §8.6，V2-SENSOR 提供通道字段）：
##   target_id / state / quality / bearing_deg / bearing_sigma_deg /
##   range_km / range_sigma_km / age_s / update_rate_hz / stable_track / fire_control
## 只给 L2 定位证据；fire_control 解算只透传供火控视图，不把等级抬到 L3/L4。
## 失锁（fire_control_lost / lock_lost）时返回 detected=false，由 core 证据有效期降级。
static func tws_channel_to_observation(ch: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var state := String(ch.get("state", ""))
	var active: Array = (opts.get("active_states", TWS_ACTIVE_STATES) as Array)
	var raw := {
		"detected": state in active,
		"kind": "radar.tws",
		"sensor": String(opts.get("sensor", ch.get("sensor", "TWS"))),
		"source": String(opts.get("source", ch.get("source", ""))),
		"t": float(ch.get("t", opts.get("t", -1.0))),
		"quality": float(ch.get("quality", 0.0)),
		"support": int(opts.get("support", 2)),
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 1.0)),
		"range_km": float(ch.get("range_km", -1.0)),
		"range_sigma_km": float(ch.get("range_sigma_km", -1.0)),
	}
	var tid := String(ch.get("target_id", ch.get("id", "")))
	if tid != "":
		raw["target_id"] = tid
	var notes: Array = ["TWS state=%s" % state]
	if ch.has("age_s"):
		notes.append("age=%.1fs" % float(ch.get("age_s", 0.0)))
	if ch.has("update_rate_hz"):
		notes.append("update=%.2fHz" % float(ch.get("update_rate_hz", 0.0)))
	if ch.has("stable_track"):
		notes.append("stable_track=%s" % str(bool(ch.get("stable_track", false))))
	raw["notes"] = notes
	var out := to_core_observation(raw, opts)
	out["channel_state"] = state
	# 火控解算只供火控视图；core 等级仍只吃 L2 位置证据。
	if ch.has("fire_control") and ch.get("fire_control") is Dictionary:
		out["fire_control"] = (ch.get("fire_control") as Dictionary).duplicate(true)
	return out

## 一次 TWS 多通道快照 → 只返回可注入的观测（失锁/未捕获通道被过滤）。
static func tws_channels_to_observations(channels: Array, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for raw in channels:
		if not (raw is Dictionary):
			continue
		var obs := tws_channel_to_observation(raw, opts)
		if bool(obs.get("detected", false)):
			out.append(obs)
	return out

## 便捷入口：把 TWS 通道快照直接喂进 world（只注入可跟踪通道）。
static func ingest_tws_channels(world: V2World, channels: Array, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for obs in tws_channels_to_observations(channels, opts):
		var tr := world.ingest(obs)
		if tr != null:
			out.append(tr)
	return out

## 把 core 侧的目标（实体/航迹）描述成 sim 快照 targets 行需要的字段。
## sim 的 snapshot target 字段（id/entity_id/position/r/v/rcs_m2/transponder/…）由
## 上层组装；core 只提供不写死的字段映射。
## 说明：`id` 保持 track.id（sim 一次扫描内的稳定标识）；需要实体 id 时用 `entity_id`，
## 或在上层组装 snapshot 时按自己的约定覆盖 `id`。`classification` 供光学 L3 使用。
static func target_row(entity: V2Entity, track: V2Track) -> Dictionary:
	var row := {
		"id": track.id if track != null else (entity.batch if entity != null and entity.batch != "" else ""),
		"track_id": track.id if track != null else "",
		"entity_id": entity.id if entity != null else "",
		"batch": entity.batch if entity != null else "",
		"side": entity.side if entity != null else "unknown",
		"kind": entity.kind if entity != null else "contact",
		"name": entity.name if entity != null else "",
		"class": entity.cls if entity != null else "",
		"sensor_sources": track.sources.duplicate() if track != null else [],
	}
	if entity != null:
		row["classification"] = {
			"ship_class": entity.cls,
			"role": entity.role,
			"faction": entity.faction,
		}
		if entity.meta.has("builder"):
			row["classification"]["builder"] = String(entity.meta.get("builder", ""))
		for extra in ["rcs_m2", "transponder", "iff_code", "temp_k", "area_m2"]:
			if entity.meta.has(extra):
				row[extra] = entity.meta[extra]
	if entity != null and not entity.orbit.is_empty():
		row["orbit"] = entity.orbit.duplicate(true)
		if entity.orbit.has("r"):
			row["r"] = (entity.orbit.get("r", []) as Array).duplicate()
		if entity.orbit.has("v"):
			row["v"] = (entity.orbit.get("v", []) as Array).duplicate()
	if track != null:
		row["range_km"] = track.range_km
		row["bearing_deg"] = track.bearing_deg
	return row
