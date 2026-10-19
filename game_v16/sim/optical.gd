class_name V2OpticalModel
extends RefCounted

## GHOST TRACK / APSIS · V2 光学 / 红外凝视通道（V2-SENSOR-1）
##
## 与 TWS 完全独立：本模型不读 radar/tws 状态，也不共享通道；core 可各自实例化。
## 只做「可见光凝视 / 红外凝视」的通道进度、锁定、距离/刷新与失锁，不画 UI、不做分类判定。
##
## 05 §S-03：光学需要光照 + 凝视时间；阴影区不可见；凝视期间大幅机动要重来。
## 05 §2.1：8,000 km 识别需 40 s（光学凝视基准）；所需时间按 R² 缩放（v15 公式）。
## 05 §S-01：IR 只给方位线 + 远/中/近三档，不给距离；IR 锁定 ≠ 分类（不升 L3）。
##
## 公开 API：
##   var opt = V2OpticalModel.new({"optical": rec, "ir": rec})
##   opt.start("optical", "9001")                       # 建立通道
##   opt.step(dt, world_snapshot) -> Dictionary          # 推进全部通道
##   opt.channel_status("9001") -> Dictionary            # {track_id, channels:{optical:{…}, ir:{…}}}
##   opt.stop("optical", "9001") / opt.stop_all()
##
## 通道状态：idle → acquiring → staring → locked；条件丢失 → lost（保留进度 lost_hold_s）。
## 输出中 `slant_range_km` 是几何距离（显示用），`measured_range_km` 是传感器实测距离
## （光学/IR 均为 -1：不给距离解，避免伪造测量）。

const SM := preload("res://scripts/sensor_model.gd")
const Types := preload("res://sim/sensor_types.gd")

const CH_OPTICAL := "optical"     # 可见光凝视
const CH_IR := "ir"               # 红外凝视通道
const CHANNEL_KINDS: Array = [CH_OPTICAL, CH_IR]

const STATUS_IDLE := "idle"
const STATUS_ACQUIRING := "acquiring"
const STATUS_STARING := "staring"
const STATUS_LOCKED := "locked"
const STATUS_LOST := "lost"

const IR_LOCK_S := 4.0            # [本文定值] IR 阵列锁定时间（≠ 分类，不升 L3）
const LOST_HOLD_S := 8.0          # [本文定值] 失锁后保留凝视进度的时间

var sensors: Dictionary = {CH_OPTICAL: null, CH_IR: null}
var channels: Dictionary = {}     # "optical:<target_id>" / "ir:<target_id>" -> channel dict
var enabled := true
var now_t := 0.0
var lost_hold_s := LOST_HOLD_S


func _init(opts: Dictionary = {}) -> void:
	if opts.has("optical") and opts["optical"] != null:
		sensors[CH_OPTICAL] = opts["optical"]
	if opts.has("ir") and opts["ir"] != null:
		sensors[CH_IR] = opts["ir"]
	if opts.has("lost_hold_s"):
		lost_hold_s = maxf(0.0, float(opts["lost_hold_s"]))


func set_sensor(kind: String, rec) -> void:
	if sensors.has(kind):
		sensors[kind] = rec


func has_sensor(kind: String) -> bool:
	return sensors.get(kind, null) != null


func set_enabled(on: bool) -> void:
	enabled = on


# ═══════════════════════════════════════════════════════════════════
# 1. 通道建立 / 停止
# ═══════════════════════════════════════════════════════════════════

## 建立凝视通道。返回 {ok, reason}；已有通道则不重置进度。
func start(kind: String, target_id: String, opts: Dictionary = {}) -> Dictionary:
	if not CHANNEL_KINDS.has(kind):
		return {"ok": false, "reason": "未知通道类型：%s" % kind}
	if not has_sensor(kind):
		return {"ok": false, "reason": "无可用%s传感器" % ("光学" if kind == CH_OPTICAL else "红外")}
	if target_id.is_empty():
		return {"ok": false, "reason": "target_id 为空"}
	var key := _key(kind, target_id)
	if channels.has(key):
		return {"ok": true, "reason": "通道已存在（保持进度）", "channel": _export_channel(channels[key])}
	var ch: Dictionary = {
		"kind": kind,
		"target_id": target_id,
		"status": STATUS_IDLE,
		"status_since_t": now_t,
		"stare_s": float(opts.get("elapsed_s", 0.0)),
		"required_s": 1.0,
		"progress": 0.0,
		"samples": 0,
		"sample_acc": 0.0,
		"refresh_s": float(sensors[kind].refresh_s),
		"slant_range_km": -1.0,
		"measured_range_km": -1.0,
		"range_band": "",
		"range_source": "none",
		"bearing_deg": -1.0,
		"elevation_deg": 0.0,
		"bearing_sigma_deg": float(sensors[kind].sigma_bearing_deg),
		"illum": 1.0,
		"contrast": 1.0,
		"effective_range_km": -1.0,
		"level_support": 0,
		"classification": {},
		"reason": "",
		"locked_t": -1.0,
		"lost_at": -1.0,
		"history": [],
	}
	if ch.stare_s > 0.0:
		ch.status = STATUS_ACQUIRING
	channels[key] = ch
	return {"ok": true, "reason": "", "channel": _export_channel(ch)}


## 停止通道：target_id 为空 = 停该类型全部。
func stop(kind: String, target_id: String = "") -> void:
	if target_id != "":
		channels.erase(_key(kind, target_id))
		return
	for key in channels.keys():
		if String(channels[key].get("kind", "")) == kind:
			channels.erase(key)


func stop_all() -> void:
	channels.clear()


func active_targets(kind: String = "") -> Array:
	var out: Array = []
	for raw in channels.values():
		var ch: Dictionary = raw
		if kind == "" or String(ch.get("kind", "")) == kind:
			out.append(String(ch.get("target_id", "")))
	return out


func channel(kind: String, target_id: String) -> Dictionary:
	return channels.get(_key(kind, target_id), {})


func _key(kind: String, target_id: String) -> String:
	return "%s:%s" % [kind, target_id]


# ═══════════════════════════════════════════════════════════════════
# 2. step(dt, world_snapshot)
# ═══════════════════════════════════════════════════════════════════

func step(dt: float, snapshot: Dictionary) -> Dictionary:
	var step_dt := maxf(0.0, dt)
	now_t += step_dt
	var events: Array = []
	if enabled:
		for key in channels.keys():
			var ch: Dictionary = channels[key]
			_step_channel(ch, step_dt, snapshot, events)
	return {
		"t": now_t,
		"dt": step_dt,
		"enabled": enabled,
		"channels": _export_channels(),
		"by_status": _count_by_status(),
		"events": events,
		"exposure": {"exposed": false, "emission_level": 0.0, "note": "光学/IR 被动，不暴露（05 §S-01/S-03）"},
	}


func _step_channel(ch: Dictionary, dt: float, snapshot: Dictionary, events: Array) -> void:
	var kind := String(ch["kind"])
	var target_id := String(ch["target_id"])
	var rec = sensors.get(kind, null)
	if rec == null:
		_fail(ch, "no_sensor", dt, events)
		return
	var target: Dictionary = Types.target_by_id(snapshot, target_id)
	if target.is_empty():
		_fail(ch, "target_missing", dt, events)
		return
	var obs_pos := Types.observer_pos_km(snapshot)
	var tgt_pos := Types.target_pos_km(target)
	var geom := Types.geometry_km(obs_pos, tgt_pos)
	ch["slant_range_km"] = geom["range_km"]
	ch["bearing_deg"] = geom["bearing_deg"]
	ch["elevation_deg"] = geom["elevation_deg"]
	ch["bearing_sigma_deg"] = rec.sigma_bearing_deg
	ch["refresh_s"] = rec.refresh_s

	if not Types.los_ok(snapshot, obs_pos, tgt_pos):
		_fail(ch, "occluded", dt, events)
		return

	var sensor_dict: Dictionary = rec.as_v15_sensor()
	var eff_range := 0.0
	var illum := Types.illum_of(snapshot, target)
	ch["illum"] = illum
	if kind == CH_OPTICAL:
		if illum < rec.illum_min:
			_fail(ch, "shadow", dt, events)
			return
		eff_range = rec.range_km * sqrt(clampf(illum, 0.0, 1.0))
		ch["contrast"] = 1.0
	else:
		var contrast := SM.ir_contrast(target, {"shadow": bool(snapshot.get("shadow", false))})
		ch["contrast"] = contrast
		eff_range = rec.range_km * sqrt(contrast)
	ch["effective_range_km"] = eff_range
	if geom["range_km"] > eff_range:
		_fail(ch, "out_of_range", dt, events)
		return

	# 光照/距离条件成立 → 推进凝视。
	if ch["status"] == STATUS_LOST or ch["status"] == STATUS_IDLE:
		_set_status(ch, STATUS_ACQUIRING, events, "acquire")
	var required := _required_s(rec, kind, float(geom["range_km"]))
	ch["required_s"] = required

	# 可见光凝视需要稳定平台：自舰机动超阈值 → 凝视重来（05 §S-03 缺陷）。
	if kind == CH_OPTICAL and Types.maneuver_of(snapshot) > rec.reset_maneuver_g:
		if float(ch["stare_s"]) > 0.0:
			ch["stare_s"] = 0.0
			ch["samples"] = 0
			ch["sample_acc"] = 0.0
			ch["progress"] = 0.0
			_emit(events, "stare_reset", ch, "自舰机动 > %.2f g，凝视中断重来（05 §S-03）" % rec.reset_maneuver_g)
		if ch["status"] == STATUS_LOCKED:
			_set_status(ch, STATUS_STARING, events, "maneuver_reset")
		if ch["status"] == STATUS_ACQUIRING:
			_set_status(ch, STATUS_STARING, events, "staring")
		return

	if ch["status"] == STATUS_ACQUIRING:
		_set_status(ch, STATUS_STARING, events, "staring")

	ch["stare_s"] = float(ch["stare_s"]) + dt
	ch["sample_acc"] = float(ch["sample_acc"]) + dt
	var refresh := maxf(0.25, rec.refresh_s)
	if float(ch["sample_acc"]) + 1.0e-9 >= refresh:
		ch["sample_acc"] = fposmod(float(ch["sample_acc"]), refresh)
		ch["samples"] = int(ch["samples"]) + 1
	ch["progress"] = clampf(float(ch["stare_s"]) / maxf(1.0e-6, required), 0.0, 1.0)

	# 物理/几何读数：光学与 IR 都不给距离解（measured_range_km = -1）。
	ch["measured_range_km"] = -1.0
	ch["range_source"] = "none"
	if kind == CH_OPTICAL:
		ch["level_support"] = 3 if float(ch["progress"]) >= 1.0 else 1
		ch["range_band"] = ""
	else:
		ch["level_support"] = 1
		ch["range_band"] = SM.ir_range_band(float(geom["range_km"]), eff_range,
			sensor_dict.get("band_edges", [0.333, 0.667]))

	if float(ch["stare_s"]) + 1.0e-9 >= required:
		ch["progress"] = 1.0
		if ch["status"] != STATUS_LOCKED:
			ch["locked_t"] = now_t
			ch["level_support"] = 3 if kind == CH_OPTICAL else 1
			if kind == CH_OPTICAL:
				var cls: Variant = target.get("classification", {})
				ch["classification"] = (cls as Dictionary).duplicate(true) if cls is Dictionary else {}
			_set_status(ch, STATUS_LOCKED, events, "stare_complete")
	elif ch["status"] == STATUS_LOCKED and float(ch["stare_s"]) < required:
		# 所需凝视时间随距离变大（目标远离）→ 掉回凝视中（罕见）。
		_set_status(ch, STATUS_STARING, events, "required_grew")


## 条件不成立：状态转 lost；进度保留 lost_hold_s 后清零。
func _fail(ch: Dictionary, reason: String, dt: float, events: Array) -> void:
	ch["reason"] = reason
	if ch["status"] != STATUS_LOST:
		if ch["status"] == STATUS_LOCKED:
			ch["locked_t"] = -1.0
		_set_status(ch, STATUS_LOST, events, reason)
		ch["lost_at"] = now_t
	ch["stare_s"] = maxf(0.0, float(ch["stare_s"]) - dt)
	ch["progress"] = 0.0
	ch["measured_range_km"] = -1.0
	ch["level_support"] = 0
	ch["classification"] = {}
	if float(ch["lost_at"]) >= 0.0 and now_t - float(ch["lost_at"]) > lost_hold_s and float(ch["stare_s"]) > 0.0:
		ch["stare_s"] = 0.0
		ch["samples"] = 0
		ch["sample_acc"] = 0.0
		_emit(events, "stare_lost", ch, "失锁超过 %.0f s，凝视进度清零" % lost_hold_s)


func _required_s(rec, kind: String, range_km: float) -> float:
	if kind == CH_OPTICAL:
		return SM.optical_stare_s(rec.as_v15_sensor(), range_km)
	return IR_LOCK_S


func _set_status(ch: Dictionary, status: String, events: Array, reason: String) -> void:
	if String(ch["status"]) == status:
		ch["reason"] = reason
		return
	var from := String(ch["status"])
	ch["status"] = status
	ch["status_since_t"] = now_t
	ch["reason"] = reason
	var ev: Dictionary = {
		"kind": "channel_status",
		"channel": String(ch["kind"]),
		"target_id": String(ch["target_id"]),
		"from": from,
		"to": status,
		"t": now_t,
		"reason": reason,
		"progress": float(ch["progress"]),
	}
	events.append(ev)
	var hist: Array = ch.get("history", [])
	hist.append({"t": now_t, "from": from, "to": status, "reason": reason})
	while hist.size() > 16:
		hist.pop_front()
	ch["history"] = hist


func _emit(events: Array, kind: String, ch: Dictionary, message: String) -> void:
	events.append({
		"kind": kind,
		"channel": String(ch["kind"]),
		"target_id": String(ch["target_id"]),
		"t": now_t,
		"message": message,
		"progress": float(ch["progress"]),
	})


# ═══════════════════════════════════════════════════════════════════
# 3. 查询 / 导出（供 core / UI 只读消费）
# ═══════════════════════════════════════════════════════════════════

## 兼容 docs/33 的通道查询形态：{track_id, channels:{optical:{…}, ir:{…}}}。
func channel_status(target_id: String = "") -> Dictionary:
	var out: Dictionary = {"track_id": target_id, "channels": {}}
	if target_id != "":
		for kind in CHANNEL_KINDS:
			var ch: Dictionary = channel(kind, target_id)
			if not ch.is_empty():
				out["channels"][kind] = _export_channel(ch)
		return out
	out["channels"] = _export_channels()
	return out


func _export_channels() -> Array:
	var out: Array = []
	for kind in CHANNEL_KINDS:
		for raw in channels.values():
			var ch: Dictionary = raw
			if String(ch.get("kind", "")) == kind:
				out.append(_export_channel(ch))
	return out


func _export_channel(ch: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"channel": String(ch.get("kind", "")),
		"target_id": String(ch.get("target_id", "")),
		"status": String(ch.get("status", STATUS_IDLE)),
		"progress": float(ch.get("progress", 0.0)),
		"stare_s": float(ch.get("stare_s", 0.0)),
		"required_s": float(ch.get("required_s", 0.0)),
		"refresh_s": float(ch.get("refresh_s", 0.0)),
		"samples": int(ch.get("samples", 0)),
		"slant_range_km": float(ch.get("slant_range_km", -1.0)),
		"measured_range_km": float(ch.get("measured_range_km", -1.0)),
		"range_band": String(ch.get("range_band", "")),
		"range_source": String(ch.get("range_source", "none")),
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"elevation_deg": float(ch.get("elevation_deg", 0.0)),
		"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 0.0)),
		"illum": float(ch.get("illum", 1.0)),
		"contrast": float(ch.get("contrast", 1.0)),
		"effective_range_km": float(ch.get("effective_range_km", -1.0)),
		"level_support": int(ch.get("level_support", 0)),
		"classification": (ch.get("classification", {}) as Dictionary).duplicate(true),
		"reason": String(ch.get("reason", "")),
		"locked": String(ch.get("status", "")) == STATUS_LOCKED,
		"locked_t": float(ch.get("locked_t", -1.0)),
		"status_since_t": float(ch.get("status_since_t", 0.0)),
		"history": (ch.get("history", []) as Array).duplicate(true),
	}
	return out


func _count_by_status() -> Dictionary:
	var counts: Dictionary = {
		STATUS_IDLE: 0, STATUS_ACQUIRING: 0, STATUS_STARING: 0,
		STATUS_LOCKED: 0, STATUS_LOST: 0,
	}
	for raw in channels.values():
		var st := String((raw as Dictionary).get("status", STATUS_IDLE))
		counts[st] = int(counts.get(st, 0)) + 1
	return counts


func to_dict() -> Dictionary:
	var opt = sensors.get(CH_OPTICAL, null)
	var ir = sensors.get(CH_IR, null)
	return {
		"enabled": enabled,
		"t": now_t,
		"sensors": {
			CH_OPTICAL: String(opt.model) if opt != null else "",
			CH_IR: String(ir.model) if ir != null else "",
		},
		"channels": _export_channels(),
		"by_status": _count_by_status(),
	}
