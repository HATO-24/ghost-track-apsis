class_name V2TwsModel
extends RefCounted

## GHOST TRACK / APSIS · V2 TWS 状态机（V2-SENSOR-1）
##
## 每目标航迹一个状态机：SEARCH → DETECT → ACQUIRE → TRACK → STARE → FIRE_CONTROL；
## 支持多通道（默认 6，取 record.track_capacity），带 track quality / age / 更新率 / 失锁。
##
## 设计边界：
##   * 完全 RefCounted，不依赖 Node / UI；所有输出是 Dictionary（core 后续适配）。
##   * **只读** world_snapshot，不修改 core 状态（不会往 snapshot/target 里写字段）。
##   * 搜索雷达用 radar.gd：球形范围 + 距离衰减 + 刷新率 + 暴露风险；本文件只做状态机。
##   * 与 optical.gd 独立：TWS 不驱动光学通道，光学也不看 TWS 状态。
##
## 阈值（[本文定值]，05/07 未给 TWS 具体数值；按第一关 6 s 扫描周期校准）：
##   连续 2 次检测 → ACQUIRE；3 次且 quality≥0.6 → TRACK；quality≥0.7 → STARE；
##   STARE 完成（≥max(刷新周期, 8 s)）且 quality≥0.85 → FIRE_CONTROL；
##   漏刷新 → 质量按 8 s 时间常数衰减；失锁 12 s / 30 s 未更新 → 降级 / 移除。
##
## 公开 API：
##   var tws = V2TwsModel.new(record, {"max_channels": 6})
##   var out = tws.step(dt, world_snapshot)      # {channels, events, exposure, sphere, …}
##   tws.ingest(observations)                     # core 若已有观测，可直接注入
##   tws.set_enabled(false)                       # EMCON
##   tws.to_dict() / tws.channel("2001")

const Types := preload("res://framework/sim/sensor_types.gd")
const RadarModel := preload("res://framework/sim/radar.gd")

# ── 状态机（docs/34 §4）───────────────────────────────────────────
const STATE_SEARCH := "SEARCH"
const STATE_DETECT := "DETECT"
const STATE_ACQUIRE := "ACQUIRE"
const STATE_TRACK := "TRACK"
const STATE_STARE := "STARE"
const STATE_FIRE_CONTROL := "FIRE_CONTROL"
const STATES: Array = [
	STATE_SEARCH, STATE_DETECT, STATE_ACQUIRE,
	STATE_TRACK, STATE_STARE, STATE_FIRE_CONTROL,
]

# ── 状态机阈值（[本文定值]）───────────────────────────────────────
const ACQUIRE_HITS := 2            # 连续检测次数 → ACQUIRE
const TRACK_HITS := 3              # 累计检测次数 → TRACK
const QUALITY_GAIN := 0.45         # 每次命中的 quality 增益
const QUALITY_DECAY_TAU_S := 8.0   # 漏刷新后的 quality 衰减时间常数
const Q_ACQUIRE := 0.30
const Q_TRACK := 0.60
const Q_STARE := 0.70
const Q_FIRE := 0.85
const LOCK_LOST_AFTER_MIN_S := 12.0     # 失锁判定下限（实际取 max(2×扫描周期, 该值)）
const FIRE_DROP_AFTER_REFRESH := 1.2    # 火控解算允许的最大漏刷新倍数
const STARE_MIN_S := 8.0                # STARE 最短驻留
const DROP_AFTER_S := 30.0              # 长时间无更新 → 移出通道
const LOCK_DROP_QUALITY := 0.10

var record
var radar                       # RadarModel 实例
var max_channels := 6
var now_t := 0.0
var channels: Dictionary = {}   # target_id -> channel dict
var last_exposure: Dictionary = {}
var scan_period_s := 6.0
var stare_required_s := STARE_MIN_S


func _init(rec = null, opts: Dictionary = {}) -> void:
	record = rec
	var cap := 0
	if rec != null:
		cap = int(rec.track_capacity)
		scan_period_s = maxf(0.25, float(rec.refresh_s))
	max_channels = maxi(1, int(opts.get("max_channels", cap if cap > 0 else Types.DEFAULT_TWS_CHANNELS)))
	stare_required_s = maxf(scan_period_s, float(opts.get("stare_required_s", STARE_MIN_S)))
	radar = RadarModel.new(rec, {"id": String(opts.get("id", "tws_radar"))})
	radar.set_enabled(bool(opts.get("enabled", true)))


func set_enabled(on: bool) -> void:
	radar.set_enabled(on)


func is_enabled() -> bool:
	return radar.enabled


# ═══════════════════════════════════════════════════════════════════
# 1. step(dt, world_snapshot)
# ═══════════════════════════════════════════════════════════════════

func step(dt: float, snapshot: Dictionary) -> Dictionary:
	var step_dt := maxf(0.0, dt)
	now_t += step_dt
	var events: Array = []

	var radar_out: Dictionary = radar.step(step_dt, snapshot)
	last_exposure = radar_out.get("exposure", {})

	var scanned := false
	var observations: Array = []
	if snapshot.has("radar_observations") and snapshot["radar_observations"] is Array:
		# core 适配模式：已有观测直接注入，TWS 只做状态机（仍按扫描周期节流由调用方负责）。
		scanned = true
		observations = snapshot["radar_observations"]
	elif bool(radar_out.get("scanned", false)):
		scanned = true
		observations = radar_out.get("observations", [])

	var scan_index := int(radar_out.get("scan_index", 0))
	for raw in observations:
		if raw is Dictionary:
			_apply_observation(raw, events, scan_index)
	_advance_channels(step_dt, events)

	var exported := _export_channels()
	return {
		"t": now_t,
		"dt": step_dt,
		"scanned": scanned,
		"scan_index": scan_index,
		"scan_period_s": scan_period_s,
		"enabled": radar.enabled,
		"max_channels": max_channels,
		"sphere": radar_out.get("sphere", {}),
		"exposure": last_exposure,
		"channels": exported,
		"channel_count": exported.size(),
		"by_state": _count_by_state(),
		"events": events,
		"radar": {
			"scan_index": scan_index,
			"scan_period_s": scan_period_s,
			"seconds_on": radar.seconds_on,
			"tws_capacity": int(record.track_capacity) if record != null else 0,
		},
	}


## 外部观测注入（core 自己算完探测后使用）。t < 0 时沿用内部时钟。
func ingest(observations: Array, t: float = -1.0) -> Dictionary:
	if t >= 0.0:
		now_t = t
	var events: Array = []
	var scan_index := int(radar.scan_index)
	for raw in observations:
		if raw is Dictionary:
			_apply_observation(raw, events, scan_index)
	_advance_channels(0.0, events)
	return {"t": now_t, "channels": _export_channels(), "events": events}


# ═══════════════════════════════════════════════════════════════════
# 2. 观测 → 通道 / 状态迁移
# ═══════════════════════════════════════════════════════════════════

func _apply_observation(obs: Dictionary, events: Array, scan_index: int) -> void:
	var tid := String(obs.get("target_id", obs.get("id", "")))
	if tid.is_empty():
		return
	var detected := bool(obs.get("detected", false))
	var ch: Dictionary = channels.get(tid, {})

	if not detected:
		if not ch.is_empty():
			ch["misses"] = int(ch["misses"]) + 1
			ch["consecutive_hits"] = 0
			ch["last_miss_t"] = now_t
		return

	if ch.is_empty():
		ch = _create_channel(tid, obs, events)
		if ch.is_empty():
			return
		channels[tid] = ch

	# ── 命中：quality / 几何 / 更新率 ─────────────────────────────
	ch["consecutive_hits"] = int(ch["consecutive_hits"]) + 1
	ch["hits"] = int(ch["hits"]) + 1
	ch["update_count"] = int(ch["update_count"]) + 1
	var last_update := float(ch["last_update_t"])
	if last_update >= 0.0:
		var inst_dt := maxf(0.05, now_t - last_update)
		ch["update_rate_hz"] = lerp(float(ch["update_rate_hz"]), 1.0 / inst_dt, 0.4)
	else:
		ch["update_rate_hz"] = 1.0 / maxf(0.1, scan_period_s)
	ch["last_update_t"] = now_t
	ch["age_s"] = 0.0
	var pd := float(obs.get("pd", 1.0))
	ch["pd"] = pd
	ch["quality"] = clampf(
		float(ch["quality"]) + QUALITY_GAIN * maxf(pd, 0.05) * (1.0 - float(ch["quality"])),
		0.0, 1.0)
	ch["range_km"] = float(obs.get("range_3d_km", obs.get("range_km", -1.0)))
	ch["bearing_deg"] = float(obs.get("bearing_deg", -1.0))
	ch["elevation_deg"] = float(obs.get("elevation_deg", 0.0))
	ch["range_sigma_km"] = float(obs.get("range_sigma_km", -1.0))
	ch["bearing_sigma_deg"] = float(obs.get("bearing_sigma_deg", 0.0))
	ch["stable_track"] = bool(obs.get("stable_track", false))
	ch["in_sphere"] = bool(obs.get("in_sphere", false))
	ch["effective_radius_km"] = float(obs.get("effective_radius_km", 0.0))
	ch["scan_index"] = int(obs.get("scan_index", scan_index))
	ch["exposure"] = (obs.get("exposure", {}) as Dictionary).duplicate(true)

	# ── 状态推进（一次观测最多推进一级，保持可观察序列）───────────
	var st := String(ch["state"])
	if st == STATE_SEARCH:
		_transition(ch, STATE_DETECT, "detected", events)
		st = String(ch["state"])
	if st == STATE_DETECT and int(ch["consecutive_hits"]) >= ACQUIRE_HITS \
			and float(ch["quality"]) >= Q_ACQUIRE:
		_transition(ch, STATE_ACQUIRE, "stable_detections", events)
		st = String(ch["state"])
	if st == STATE_ACQUIRE and int(ch["hits"]) >= TRACK_HITS \
			and float(ch["quality"]) >= Q_TRACK and bool(ch["stable_track"]):
		_transition(ch, STATE_TRACK, "track_established", events)
		st = String(ch["state"])
	if st == STATE_TRACK and float(ch["quality"]) >= Q_STARE and bool(ch["stable_track"]):
		ch["stare_s"] = 0.0
		ch["stare_required_s"] = stare_required_s
		ch["stare_progress"] = 0.0
		_transition(ch, STATE_STARE, "dwell_requested", events)


## 新目标：占用一个 TWS 通道；通道满时按 score 淘汰最弱通道。
func _create_channel(tid: String, obs: Dictionary, events: Array) -> Dictionary:
	var score := _obs_score(obs)
	if channels.size() >= max_channels:
		var victim_id := ""
		var victim_score := INF
		for raw in channels.values():
			var c: Dictionary = raw
			var cst := String(c["state"])
			if cst == STATE_STARE or cst == STATE_FIRE_CONTROL:
				continue
			var s := _channel_score(c)
			if s < victim_score:
				victim_score = s
				victim_id = String(c["target_id"])
		if victim_id == "" or score <= victim_score:
			events.append({
				"kind": "channel_full",
				"target_id": tid,
				"t": now_t,
				"candidate_score": score,
				"reason": "TWS 通道已满（%d）" % max_channels,
			})
			return {}
		_drop_channel(victim_id, "reassigned:%s" % tid, events)
	var slot := _free_slot()
	var ch: Dictionary = {
		"target_id": tid,
		"state": STATE_SEARCH,
		"state_since_t": now_t,
		"slot": slot,
		"quality": 0.0,
		"age_s": 0.0,
		"pd": 0.0,
		"hits": 0,
		"consecutive_hits": 0,
		"misses": 0,
		"update_count": 0,
		"update_rate_hz": 0.0,
		"last_update_t": -1.0,
		"last_miss_t": -1.0,
		"range_km": -1.0,
		"bearing_deg": -1.0,
		"elevation_deg": 0.0,
		"range_sigma_km": -1.0,
		"bearing_sigma_deg": 0.0,
		"stable_track": false,
		"in_sphere": false,
		"effective_radius_km": 0.0,
		"scan_index": 0,
		"stare_s": 0.0,
		"stare_required_s": stare_required_s,
		"stare_progress": 0.0,
		"fire_control": {},
		"lost_lock_count": 0,
		"exposure": {},
		"history": [],
	}
	events.append({
		"kind": "target_detected",
		"target_id": tid,
		"t": now_t,
		"slot": slot,
		"range_km": float(obs.get("range_3d_km", -1.0)),
		"pd": float(obs.get("pd", 0.0)),
	})
	return ch


func _free_slot() -> int:
	var used: Dictionary = {}
	for raw in channels.values():
		used[int((raw as Dictionary).get("slot", -1))] = true
	for i in range(max_channels):
		if not used.has(i):
			return i
	return max_channels


func _drop_channel(tid: String, reason: String, events: Array) -> void:
	if not channels.has(tid):
		return
	var ch: Dictionary = channels[tid]
	channels.erase(tid)
	events.append({
		"kind": "target_dropped",
		"target_id": tid,
		"from": String(ch.get("state", "")),
		"t": now_t,
		"reason": reason,
		"quality": float(ch.get("quality", 0.0)),
	})


# ═══════════════════════════════════════════════════════════════════
# 3. 每步维护：STARE 进度 / 火控解算 / 失锁 / 老化移除
# ═══════════════════════════════════════════════════════════════════

func _advance_channels(dt: float, events: Array) -> void:
	var drop_ids: Array = []
	var lost_after := maxf(scan_period_s * 2.0, LOCK_LOST_AFTER_MIN_S)
	for tid in channels.keys():
		var ch: Dictionary = channels[tid]
		var last_update := float(ch["last_update_t"])
		var age := now_t - last_update if last_update >= 0.0 else now_t
		ch["age_s"] = age

		# quality 只在“漏掉一次刷新”之后才衰减：稳定跟踪期间不掉分。
		if age > scan_period_s + 0.01:
			ch["quality"] = clampf(
				float(ch["quality"]) * exp(-dt / QUALITY_DECAY_TAU_S), 0.0, 1.0)

		# STARE：驻留照射累积，完成后进入火控解算。
		if String(ch["state"]) == STATE_STARE:
			if age <= scan_period_s + 0.5:
				ch["stare_s"] = float(ch["stare_s"]) + dt
			ch["stare_progress"] = clampf(
				float(ch["stare_s"]) / maxf(0.001, float(ch["stare_required_s"])), 0.0, 1.0)
			if float(ch["stare_progress"]) >= 1.0 \
					and float(ch["quality"]) >= Q_FIRE \
					and age <= scan_period_s * 1.5:
				ch["fire_control"] = _fire_solution(ch)
				_transition(ch, STATE_FIRE_CONTROL, "fire_solution_ready", events)
				events.append({
					"kind": "fire_control_ready",
					"target_id": tid,
					"t": now_t,
					"quality": float(ch["quality"]),
					"range_km": float(ch["range_km"]),
					"range_sigma_km": float(ch["range_sigma_km"]),
					"bearing_sigma_deg": float(ch["bearing_sigma_deg"]),
					"age_s": age,
				})

		# FIRE_CONTROL：解算随每次刷新更新；漏刷新则掉回 TRACK。
		if String(ch["state"]) == STATE_FIRE_CONTROL:
			ch["fire_control"] = _fire_solution(ch)
			if age > scan_period_s * FIRE_DROP_AFTER_REFRESH:
				_transition(ch, STATE_TRACK, "fire_control_lost", events)
				events.append({
					"kind": "fire_control_lost",
					"target_id": tid,
					"t": now_t,
					"age_s": age,
					"quality": float(ch["quality"]),
				})

		# 失锁：超过 max(2×刷新, 12 s) 未更新 → 降级；再一倍时间 → 回到 SEARCH。
		var st := String(ch["state"])
		if age > lost_after and st != STATE_SEARCH and st != STATE_DETECT:
			var previous := st
			_transition(ch, STATE_DETECT, "lock_lost", events)
			ch["lost_lock_count"] = int(ch["lost_lock_count"]) + 1
			events.append({
				"kind": "lock_lost",
				"target_id": tid,
				"t": now_t,
				"previous": previous,
				"age_s": age,
				"quality": float(ch["quality"]),
				"lost_after_s": lost_after,
			})
			st = STATE_DETECT
		elif age > lost_after * 2.0 and st == STATE_DETECT:
			_transition(ch, STATE_SEARCH, "lock_lost_search", events)

		# 长时间无更新且质量见底 → 释放通道。
		if age > DROP_AFTER_S and float(ch["quality"]) < LOCK_DROP_QUALITY:
			drop_ids.append(tid)
	for tid in drop_ids:
		_drop_channel(tid, "stale_drop", events)


func _transition(ch: Dictionary, to: String, reason: String, events: Array) -> void:
	var from := String(ch["state"])
	if from == to:
		return
	ch["state"] = to
	ch["state_since_t"] = now_t
	events.append({
		"kind": "state_change",
		"target_id": String(ch["target_id"]),
		"from": from,
		"to": to,
		"t": now_t,
		"reason": reason,
		"quality": float(ch["quality"]),
		"scan_index": int(radar.scan_index),
	})
	var hist: Array = ch.get("history", [])
	hist.append({"t": now_t, "from": from, "to": to, "reason": reason})
	while hist.size() > 24:
		hist.pop_front()
	ch["history"] = hist


func _fire_solution(ch: Dictionary) -> Dictionary:
	return {
		"target_id": String(ch["target_id"]),
		"range_km": float(ch["range_km"]),
		"bearing_deg": float(ch["bearing_deg"]),
		"elevation_deg": float(ch["elevation_deg"]),
		"range_sigma_km": float(ch["range_sigma_km"]),
		"bearing_sigma_deg": float(ch["bearing_sigma_deg"]),
		"track_quality": float(ch["quality"]),
		"update_rate_hz": float(ch["update_rate_hz"]),
		"age_s": float(ch["age_s"]),
		"t": now_t,
	}


func _obs_score(obs: Dictionary) -> float:
	var pd := clampf(float(obs.get("pd", 0.5)), 0.0, 1.0)
	var eff := maxf(1.0, float(obs.get("effective_radius_km", 1.0)))
	var ratio := clampf(float(obs.get("range_3d_km", eff)) / eff, 0.0, 1.0)
	return QUALITY_GAIN * pd * (2.0 - ratio)


func _channel_score(ch: Dictionary) -> float:
	var eff := maxf(1.0, float(ch.get("effective_radius_km", 1.0)))
	var ratio := clampf(float(ch.get("range_km", eff)) / eff, 0.0, 1.0)
	return float(ch.get("quality", 0.0)) * (2.0 - ratio)


# ═══════════════════════════════════════════════════════════════════
# 4. 查询 / 导出
# ═══════════════════════════════════════════════════════════════════

func channel(target_id: String) -> Dictionary:
	if not channels.has(target_id):
		return {}
	return _export_channel(channels[target_id])


func channels_export() -> Array:
	return _export_channels()


func _export_channels() -> Array:
	var out: Array = []
	for tid in channels.keys():
		out.append(_export_channel(channels[tid]))
	return out


func _export_channel(ch: Dictionary) -> Dictionary:
	return {
		"target_id": String(ch.get("target_id", "")),
		"state": String(ch.get("state", STATE_SEARCH)),
		"state_since_t": float(ch.get("state_since_t", 0.0)),
		"slot": int(ch.get("slot", -1)),
		"quality": float(ch.get("quality", 0.0)),
		"age_s": float(ch.get("age_s", 0.0)),
		"update_rate_hz": float(ch.get("update_rate_hz", 0.0)),
		"update_count": int(ch.get("update_count", 0)),
		"hits": int(ch.get("hits", 0)),
		"misses": int(ch.get("misses", 0)),
		"consecutive_hits": int(ch.get("consecutive_hits", 0)),
		"lost_lock_count": int(ch.get("lost_lock_count", 0)),
		"pd": float(ch.get("pd", 0.0)),
		"range_km": float(ch.get("range_km", -1.0)),
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"elevation_deg": float(ch.get("elevation_deg", 0.0)),
		"range_sigma_km": float(ch.get("range_sigma_km", -1.0)),
		"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 0.0)),
		"stable_track": bool(ch.get("stable_track", false)),
		"in_sphere": bool(ch.get("in_sphere", false)),
		"stare_s": float(ch.get("stare_s", 0.0)),
		"stare_required_s": float(ch.get("stare_required_s", 0.0)),
		"stare_progress": float(ch.get("stare_progress", 0.0)),
		"fire_control": (ch.get("fire_control", {}) as Dictionary).duplicate(true),
		"history": (ch.get("history", []) as Array).duplicate(true),
	}


func _count_by_state() -> Dictionary:
	var counts: Dictionary = {}
	for st in STATES:
		counts[st] = 0
	for raw in channels.values():
		var st := String((raw as Dictionary).get("state", STATE_SEARCH))
		counts[st] = int(counts.get(st, 0)) + 1
	return counts


func to_dict() -> Dictionary:
	return {
		"model": String(record.model) if record != null else "",
		"t": now_t,
		"scan_period_s": scan_period_s,
		"max_channels": max_channels,
		"stare_required_s": stare_required_s,
		"state_machine": STATES.duplicate(),
		"thresholds": {
			"acquire_hits": ACQUIRE_HITS,
			"track_hits": TRACK_HITS,
			"quality_gain": QUALITY_GAIN,
			"quality_decay_tau_s": QUALITY_DECAY_TAU_S,
			"q_acquire": Q_ACQUIRE,
			"q_track": Q_TRACK,
			"q_stare": Q_STARE,
			"q_fire": Q_FIRE,
			"lock_lost_after_s": maxf(scan_period_s * 2.0, LOCK_LOST_AFTER_MIN_S),
			"drop_after_s": DROP_AFTER_S,
		},
		"radar": radar.to_dict(),
		"channels": _export_channels(),
		"by_state": _count_by_state(),
		"exposure": last_exposure.duplicate(true),
	}
# ── A00：运行态导出/导入（通道/记忆/雷达扫描相位）──
const STATE_SCHEMA := "v17.tws.state.v1"


func export_state() -> Dictionary:
	return {
		"schema": STATE_SCHEMA, "version": 1,
		"now_t": now_t,
		"scan_period_s": scan_period_s,
		"stare_required_s": stare_required_s,
		"channels": JSON.parse_string(JSON.stringify(channels)),
		"last_exposure": JSON.parse_string(JSON.stringify(last_exposure)),
		"radar": radar.export_state() if radar != null else null,
	}


func import_state(st: Dictionary) -> Dictionary:
	var vres: Dictionary = validate_state(st)
	if not bool(vres.get("ok", false)):
		return {"ok": false, "reason": "invalid_state",
			"errors": vres.get("errors", [])}
	# 校验全部通过后才提交（含雷达子状态）
	var raw_radar = st.get("radar", null)
	if raw_radar is Dictionary and radar != null:
		var chk: Dictionary = radar.import_state(raw_radar)
		if not bool(chk.get("ok", false)):
			return chk
	now_t = float(st.get("now_t", 0.0))
	scan_period_s = float(st.get("scan_period_s", scan_period_s))
	stare_required_s = float(st.get("stare_required_s", stare_required_s))
	channels = (st.get("channels", {}) as Dictionary).duplicate(true)
	last_exposure = (st.get("last_exposure", {}) as Dictionary).duplicate(true)
	return {"ok": true, "channels": channels.size()}
# ── R6/G2：只校验不改状态（供 authority 两阶段原子导入）──
const STATE_VERSION := 1
const SAFE_INT_MAX := 9007199254740991.0
const CHANNEL_REQUIRED_FIELDS := ["target_id", "state", "quality", "last_update_t"]
const KNOWN_STATES := [STATE_SEARCH, STATE_DETECT, STATE_ACQUIRE, STATE_TRACK,
	STATE_STARE, STATE_FIRE_CONTROL]


func validate_state(st: Dictionary) -> Dictionary:
	var errs: Array = []
	if String(st.get("schema", "")) != STATE_SCHEMA:
		errs.append("tws.schema mismatch: " + String(st.get("schema", "")))
	var ver = st.get("version", null)
	if not _is_exact_int(ver) or int(roundf(float(ver))) != STATE_VERSION:
		errs.append("tws.version must be exact integer %d (got %s)" % [
			STATE_VERSION, str(ver)])
	for fld in ["now_t", "scan_period_s", "stare_required_s"]:
		var v = st.get(fld, null)
		if not _is_finite_num(v) or float(v) < 0.0:
			errs.append("tws.%s must be finite >= 0" % fld)
	for df in ["channels", "last_exposure"]:
		if not (st.get(df, null) is Dictionary):
			errs.append("tws.%s must be an object" % df)
	# 通道完整字段：缺 last_update_t/state 会在下一次 step 触发 SCRIPT ERROR
	var chans = st.get("channels", null)
	if chans is Dictionary:
		for tid in (chans as Dictionary).keys():
			var ch = (chans as Dictionary)[tid]
			if not (ch is Dictionary):
				errs.append("tws.channels[%s] must be an object" % String(tid))
				continue
			for rf in CHANNEL_REQUIRED_FIELDS:
				if not (ch as Dictionary).has(rf):
					errs.append("tws.channels[%s] missing required field %s" % [
						String(tid), rf])
			if String((ch as Dictionary).get("target_id", "")) != String(tid):
				errs.append("tws.channels[%s] target_id mismatch" % String(tid))
			var cstate := String((ch as Dictionary).get("state", ""))
			if not (cstate in KNOWN_STATES):
				errs.append("tws.channels[%s] unknown state: %s" % [
					String(tid), cstate])
			var lut = (ch as Dictionary).get("last_update_t", null)
			if not _is_finite_num(lut):
				errs.append("tws.channels[%s].last_update_t must be finite" % String(tid))
			var q = (ch as Dictionary).get("quality", null)
			if not _is_finite_num(q) or float(q) < 0.0 or float(q) > 1.0:
				errs.append("tws.channels[%s].quality must be finite in [0,1]" % String(tid))
	# 新格式必须带完整 radar 子状态（不允许静默拼接 TWS t=200 / Radar t=0）
	var raw_radar = st.get("radar", null)
	if raw_radar == null:
		errs.append("tws.radar sub-state is required (missing = incomplete restore)")
	elif not (raw_radar is Dictionary):
		errs.append("tws.radar must be an object")
	elif radar == null:
		errs.append("tws.radar provided but no radar model")
	else:
		var rv: Dictionary = radar.validate_state(raw_radar)
		for e in (rv.get("errors", []) as Array):
			errs.append(String(e))
	return {"ok": errs.is_empty(), "errors": errs}


func _is_finite_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


func _is_exact_int(v) -> bool:
	if not _is_finite_num(v):
		return false
	return absf(float(v) - roundf(float(v))) <= 0.0
