class_name V17TwsBridge
extends RefCounted

## GHOST TRACK / APSIS · V17 传感器桥（V17-SENSOR-1）
##
## 用途：让 V15 视觉层（plot.gd）消费 V2 传感器模型 —— 球形搜索雷达 R_eff / TWS 通道状态 /
## 光学通道 —— 数据只读 V15 `state`，**不修改 state / 不画 UI**。
##
## 数据来源：
##   * V15 `state.racks` / `state.sensor_on` / `state.tracks`（id / r / v / level / side / stare）；
##   * V2 `framework/sim/radar.gd`（球形半径、R_eff、暴露）；
##   * V2 `framework/sim/tws.gd`（SEARCH→…→FIRE_CONTROL 通道状态机）；
##   * V2 `framework/sim/optical.gd`（可见光/IR 凝视通道，供后续 HUD/plot 使用）。
##
## 公开 API：
##   var bridge = V17TwsBridge.new(state, {"ship": "harmattan", "radar_model": "YW-R9"})
##   bridge.step(dt)               # dt < 0：按 state.tau() 差值自动追帧（模拟时间）；
##                                 # 返回 {ok, active, channels, sphere, exposure, optical, events, …}
##   bridge.channels()             # TWS 通道（已 join 航迹 batch/name/side/level）
##   bridge.radar_sphere()         # {shape:"sphere", center_km, nominal/effective/track radius, exposure, …}
##   bridge.optical_channels()     # 光学/IR 凝视通道
##   bridge.start_optical(track_id)/start_ir(track_id)/stop_optical()
##   bridge.snapshot()             # 给 V2 模型的 world_snapshot（只读 state 生成）
##
## 边界：
##   * 不调用 state 的任何写方法（set_sensor/set_emcon/refresh/clock/...），只读字段；
##   * 雷达开关/EMCON/桅杆等判定沿用 V15 state 的当前值（state.sensor_on / is_emcon / mast）；
##   * R_eff 以 V2 型号记录的基准 RCS 10 m² 计算（与 SensorModel §3.2 口径一致）；
##   * 本文件不绘制，plot.gd 只拿数据画 1px 线框。

const Types := preload("res://framework/sim/sensor_types.gd")
const RadarModel := preload("res://framework/sim/radar.gd")
const TwsModel := preload("res://framework/sim/tws.gd")
const OpticalModel := preload("res://framework/sim/optical.gd")
const SensorModel := preload("res://scripts/sensor_model.gd")

const SCHEMA := "v17_tws_bridge.v1"
const REF_RCS_M2 := 10.0                    # R_eff 基准 RCS（05 §S-02 / SensorModel §3.2）
const ACTIVE_STATES := ["ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const STATE_ORDER := ["SEARCH", "DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const SPHERE_STATE_SHORT := {
	"SEARCH": "SRCH",
	"DETECT": "DET",
	"ACQUIRE": "ACQ",
	"TRACK": "TRK",
	"STARE": "STARE",
	"FIRE_CONTROL": "FC",
}
const CATCHUP_LIMIT_S := 600.0              # 单次 step 最多补算的模拟秒数（防止卡顿）
const CATCHUP_CHUNK_S := 0.5                # V2 TWS 扫描节拍 6 s，0.5 s 步长足够平滑

var state = null
var ship := "harmattan"
var radar_model := "YW-R9"
var optical_model := "MS-OT2"
var ir_model := "CH-IR2"

var radar_record = null                     # V2SensorTypes.SensorRecord
var optical_record = null
var ir_record = null
var tws = null                              # V2TwsModel
var optical = null                          # V2OpticalModel

var _last_tau := -1.0
var _events: Array = []
var _last_step: Dictionary = {}
var _initialized := false
var _warned := false


func _init(state_ref = null, opts: Dictionary = {}) -> void:
	state = state_ref
	if opts.has("ship"):
		ship = String(opts.get("ship", ship))
	if opts.has("radar_model"):
		radar_model = String(opts.get("radar_model", radar_model))
	if opts.has("optical_model"):
		optical_model = String(opts.get("optical_model", optical_model))
	if opts.has("ir_model"):
		ir_model = String(opts.get("ir_model", ir_model))
	_rebuild()


## 重新绑定 state（V15 restart/重开后调用；不修改 state）。
func bind(state_ref) -> void:
	state = state_ref
	_last_tau = -1.0
	_events.clear()
	_last_step = {}
	_rebuild()


func _rebuild() -> void:
	radar_record = _record_for(radar_model)
	var cap := 1
	if radar_record != null:
		cap = maxi(1, int(radar_record.track_capacity))
	tws = TwsModel.new(radar_record, {"id": radar_model, "max_channels": cap, "enabled": false})
	optical_record = _record_for(optical_model)
	ir_record = _record_for(ir_model)
	optical = OpticalModel.new({"optical": optical_record, "ir": ir_record})
	_initialized = true


# ═══════════════════════════════════════════════════════════════════
# 1. V15 state 只读适配
# ═══════════════════════════════════════════════════════════════════

func _sensor_dict(model: String) -> Dictionary:
	if state == null:
		return {}
	var racks = state.get("racks")
	if racks is Dictionary:
		var arr = (racks as Dictionary).get(ship, [])
		if arr is Array:
			for raw in (arr as Array):
				if raw is Dictionary and String((raw as Dictionary).get("model", "")) == model:
					return (raw as Dictionary).duplicate(true)
	return SensorModel.rack_sensor(ship, model)


func _record_for(model: String) -> Variant:
	var sensor := _sensor_dict(model)
	if not sensor.is_empty():
		var rec = Types.record_from_rack_sensor(sensor)
		if rec != null and float(rec.range_km) > 0.0:
			return rec
	var fallback = Types.record(model)
	return fallback


func _now() -> float:
	if state != null and state.has_method("tau"):
		return float(state.call("tau"))
	return 0.0


func _tracks() -> Array:
	if state == null:
		return []
	var t = state.get("tracks")
	if t is Array:
		return t
	return []


func _track(track_id: String) -> Dictionary:
	for raw in _tracks():
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == track_id:
			return raw
	return {}


func _own_track() -> Dictionary:
	for raw in _tracks():
		if raw is Dictionary and bool((raw as Dictionary).get("own", false)):
			return raw
	return {}


## V2 world_snapshot（只读 state 生成；坐标 = L1 局部板 km，由 state.board_pos 提供）。
func snapshot() -> Dictionary:
	var now := _now()
	var own := _own_track()
	var own_km := _track_position(own, now)
	var targets: Array = []
	for raw in _tracks():
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		if bool(tr.get("own", false)) or bool(tr.get("phantom", false)) or bool(tr.get("occluded", false)):
			continue
		var pos := _track_position(tr, now)
		if pos.length() < 1.0e-6:
			continue
		var cls := {
			"ship_class": String(tr.get("cls", "")),
			"role": String(tr.get("role", "")),
			"faction": String(tr.get("side", "unknown")),
		}
		targets.append({
			"id": String(tr.get("id", "")),
			"pos_km": _arr(pos),
			"rcs_m2": REF_RCS_M2,
			"temp_k": 300.0,
			"area_m2": 1000.0,
			"classification": cls,
		})
	return {
		"t": now,
		"observer": {
			"id": String(own.get("id", ship)),
			"pos_km": _arr(own_km),
			"maneuver_g": 0.0,
		},
		"targets": targets,
		"sun_illum": 1.0,
		"jamming": 0.0,
		"shadow": false,
		"los": true,
	}


func _track_position(tr: Dictionary, tau: float) -> Vector3:
	if tr.is_empty() or state == null or not state.has_method("board_pos"):
		return Vector3.ZERO
	var pos = state.call("board_pos", tr, tau)
	if pos is Vector3:
		return pos
	return Vector3.ZERO


# ═══════════════════════════════════════════════════════════════════
# 2. 雷达开关 / 球形范围
# ═══════════════════════════════════════════════════════════════════

## 主动雷达当前是否开机（沿用 V15：EMCON / 桅杆 / 手动覆盖都算数）。
func is_radar_on() -> bool:
	if state == null:
		return false
	if state.has_method("is_emcon") and bool(state.call("is_emcon", ship)):
		return false
	if state.has_method("is_mast_deployed") and not bool(state.call("is_mast_deployed", ship)):
		return false
	var son = state.get("sensor_on")
	if son is Dictionary:
		var m: Dictionary = (son as Dictionary).get(ship, {})
		if m.has(radar_model):
			return bool(m[radar_model])
	return false


## 球形雷达数据（V2 R_eff；不是扇形）。plot 用它画球壳线框 + 标注。
func radar_sphere() -> Dictionary:
	var now := _now()
	var active := is_radar_on()
	var center := Vector3.ZERO
	for raw in _tracks():
		if raw is Dictionary and bool((raw as Dictionary).get("own", false)):
			center = _track_position(raw, now)
			break
	var out: Dictionary = {
		"available": radar_record != null,
		"active": active,
		"shape": "sphere",
		"no_sector": true,
		"ship": ship,
		"model": radar_model,
		"center_km": _arr(center),
		"nominal_radius_km": 0.0,
		"effective_radius_km": 0.0,
		"track_radius_km": 0.0,
		"refresh_s": 0.0,
		"scan_index": 0,
		"seconds_on": 0.0,
		"targets_total": 0,
		"targets_in_sphere": 0,
		"exposure": {},
	}
	if radar_record == null:
		return out
	out["nominal_radius_km"] = RadarModel.nominal_radius_km(radar_record)
	out["effective_radius_km"] = RadarModel.effective_radius_km(radar_record, REF_RCS_M2, 0.0)
	out["track_radius_km"] = RadarModel.effective_track_radius_km(radar_record, REF_RCS_M2, 0.0)
	out["refresh_s"] = float(radar_record.refresh_s)
	var seconds_on := 0.0
	var scan_index := 0
	if tws != null and tws.radar != null:
		seconds_on = float(tws.radar.seconds_on)
		scan_index = int(tws.radar.scan_index)
	out["seconds_on"] = seconds_on
	out["scan_index"] = scan_index
	out["sphere"] = RadarModel.sphere_for(radar_record, center, REF_RCS_M2, 0.0)
	out["exposure"] = RadarModel.exposure_state(radar_record, seconds_on, {"on": active})
	var total := 0
	var in_sphere := 0
	var eff := float(out["effective_radius_km"])
	for raw in _tracks():
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		if bool(tr.get("own", false)) or bool(tr.get("phantom", false)):
			continue
		total += 1
		var pos := _track_position(tr, now)
		if pos.length() > 1.0e-6 and pos.distance_to(center) <= eff + 1.0e-6:
			in_sphere += 1
	out["targets_total"] = total
	out["targets_in_sphere"] = in_sphere
	return out


## 暴露的一行说明（给 plot 的 EMIT 状态行复用 V2 数据）。
func exposure_line() -> String:
	var sph := radar_sphere()
	var exp: Dictionary = sph.get("exposure", {})
	if not bool(sph.get("active", false)):
		return "EMCON · 主动雷达关闭（不暴露）"
	return "球面搜索 · R_eff %s km · ELINT 截获 %s km" % [
		_fmt_km(float(sph.get("effective_radius_km", 0.0))),
		_fmt_km(float(exp.get("elint_intercept_range_km", 0.0))),
	]


# ═══════════════════════════════════════════════════════════════════
# 3. TWS 通道
# ═══════════════════════════════════════════════════════════════════

## TWS 通道数组（已 join V15 航迹资料的只读视图，供 plot 画状态环/短标签）。
func channels() -> Array:
	var out: Array = []
	if tws == null:
		return out
	for raw in tws.channels_export():
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var tid := String(ch.get("target_id", ch.get("target_track_id", "")))
		var tr := _track(tid)
		var st := String(ch.get("state", "SEARCH"))
		out.append({
			"target_track_id": tid,
			"batch": String(tr.get("batch", tid)),
			"name": String(tr.get("name", tid)),
			"en": String(tr.get("en", "")),
			"side": String(tr.get("side", "unknown")),
			"level": int(tr.get("level", 1)),
			"state": st,
			"short": String(SPHERE_STATE_SHORT.get(st, st)),
			"state_index": STATE_ORDER.find(st),
			"active": st in ACTIVE_STATES,
			"fire_control_ready": st == "FIRE_CONTROL",
			"lost_lock": st == "SEARCH" or st == "DETECT",
			"quality": float(ch.get("quality", 0.0)),
			"age_s": float(ch.get("age_s", 0.0)),
			"update_rate_hz": float(ch.get("update_rate_hz", 0.0)),
			"update_count": int(ch.get("update_count", 0)),
			"range_km": float(ch.get("range_km", -1.0)),
			"bearing_deg": float(ch.get("bearing_deg", -1.0)),
			"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 0.0)),
			"range_sigma_km": float(ch.get("range_sigma_km", -1.0)),
			"stable_track": bool(ch.get("stable_track", false)),
			"lost_lock_count": int(ch.get("lost_lock_count", 0)),
			"stare_progress": float(ch.get("stare_progress", 0.0)),
			"slot": int(ch.get("slot", -1)),
			"fire_control": _dict(ch.get("fire_control", {})),
		})
	return out


func _count_active(chans: Array) -> int:
	var n := 0
	for raw in chans:
		if raw is Dictionary and bool((raw as Dictionary).get("active", false)):
			n += 1
	return n


## 六态计数（供 plot/截图报告；SEARCH/DETECT 即失锁/搜索）。
func state_counts(chans: Array) -> Dictionary:
	var counts: Dictionary = {}
	for st in STATE_ORDER:
		counts[st] = 0
	for raw in chans:
		if raw is Dictionary:
			var st2 := String((raw as Dictionary).get("state", "SEARCH"))
			counts[st2] = int(counts.get(st2, 0)) + 1
	return counts


# ═══════════════════════════════════════════════════════════════════
# 4. 光学 / IR 通道（V2OpticalModel；plot 暂沿用 V15 光学语义，预留）
# ═══════════════════════════════════════════════════════════════════

func start_optical(track_id: String) -> Dictionary:
	if optical == null:
		return {"ok": false, "reason": "no optical model"}
	return optical.start("optical", track_id)


func start_ir(track_id: String) -> Dictionary:
	if optical == null:
		return {"ok": false, "reason": "no optical model"}
	return optical.start("ir", track_id)


func stop_optical() -> void:
	if optical != null:
		optical.stop_all()


func optical_channels() -> Array:
	var out: Array = []
	if optical == null:
		return out
	var data: Dictionary = optical.to_dict()
	for raw in _list(data.get("channels", [])):
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


# ═══════════════════════════════════════════════════════════════════
# 5. step：推进 V2 模型（只读 state 生成快照，绝不写 state）
# ═══════════════════════════════════════════════════════════════════

## dt < 0：按 state.tau() 差值自动追帧（plot 每帧调用；截图时 DSH_CLOCK 会一次补齐）；
## dt >= 0：显式推进（probe / 外部时钟）。
func step(dt: float = -1.0) -> Dictionary:
	if state == null or not _initialized:
		return {"ok": false, "schema": SCHEMA, "reason": "bridge 未绑定 state"}
	var now := _now()
	var active := is_radar_on()
	var target_dt := 0.0
	if dt < 0.0:
		if _last_tau < 0.0:
			target_dt = maxf(0.0, now)
		else:
			target_dt = maxf(0.0, now - _last_tau)
	else:
		target_dt = maxf(0.0, dt)
	target_dt = minf(target_dt, CATCHUP_LIMIT_S)
	# 追帧时只把「雷达开机之后」的模拟时间喂给 TWS（避免把开机前的历史补成已跟踪）。
	var radar_dt := target_dt
	if dt < 0.0 and active and state != null:
		var on_t := 0.0
		var raw_on = state.get("radar_on_t")
		if raw_on != null:
			on_t = float(raw_on)
		var start_tau := now - target_dt
		if now < on_t:
			# 手动提前开机（set_sensor 截图/演示钩子）：整段都按开机处理。
			radar_dt = target_dt
		else:
			radar_dt = maxf(0.0, target_dt - maxf(0.0, on_t - start_tau))
	_last_tau = now
	if tws != null:
		tws.set_enabled(active)
	_events.clear()
	var sim_dt := 0.0
	var sim_radar := 0.0
	var max_iter := int(ceil(target_dt / CATCHUP_CHUNK_S)) + 2
	var iter := 0
	while sim_dt < target_dt - 1.0e-9 and iter < max_iter:
		iter += 1
		var d := minf(CATCHUP_CHUNK_S, target_dt - sim_dt)
		var snap := snapshot()
		if tws != null and active and sim_radar < radar_dt - 1.0e-9:
			var td := minf(d, radar_dt - sim_radar)
			var out: Dictionary = tws.step(td, snap)
			_events.append_array(_list(out.get("events", [])).duplicate(true))
			sim_radar += td
		if optical != null:
			var oo: Dictionary = optical.step(d, snap)
			_events.append_array(_list(oo.get("events", [])).duplicate(true))
		sim_dt += d
	var sphere := radar_sphere()
	var chans := channels()
	var opt_ch := optical_channels()
	_last_step = {
		"ok": true,
		"schema": SCHEMA,
		"tau": now,
		"simulated_dt": sim_dt,
		"active": active,
		"channels": chans,
		"channel_count": chans.size(),
		"active_channels": _count_active(chans),
		"by_state": state_counts(chans),
		"sphere": sphere,
		"exposure": _dict(sphere.get("exposure", {})),
		"optical": opt_ch,
		"optical_locked": _count_locked(opt_ch),
		"events": _events.duplicate(true),
		"state_modified": false,
	}
	return _last_step


func last_step() -> Dictionary:
	return _last_step.duplicate(true)


func summary() -> String:
	var sph := radar_sphere()
	var chans := channels()
	return "TWS %s · %s · %d CH (%d active) · R_eff %.0f km · %s" % [
		ship, radar_model, chans.size(), _count_active(chans),
		float(sph.get("effective_radius_km", 0.0)),
		"RADAR ON" if bool(sph.get("active", false)) else "EMCON/OFF",
	]


func _count_locked(opt_ch: Array) -> int:
	var n := 0
	for raw in opt_ch:
		if raw is Dictionary and String((raw as Dictionary).get("status", "")) == "locked":
			n += 1
	return n


# ═══════════════════════════════════════════════════════════════════
# 6. 工具
# ═══════════════════════════════════════════════════════════════════

func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}


func _list(v: Variant) -> Array:
	if v is Array:
		return v
	return []


func _fmt_km(km: float) -> String:
	var n := int(roundf(km))
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	if n >= 100:
		return "%d" % n
	return "%.1f" % km
