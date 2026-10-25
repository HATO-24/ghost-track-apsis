class_name V2OpticalIRChannel
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 完整光学 / 红外通道模型（R5-OPTICAL-IR-1）
#
# 只读模型：相机/望远镜参数、FOV/IFOV、地球/月球遮挡、太阳光照/地球反照、
# 目标角尺寸、相对角速度/运动模糊、凝视积分、曝光、SNR、锁定/分类条件。
#
# 设计边界：
#   * 不接 UI / bridge / sensor_authority；不写 TrackTable / V15 / world；
#   * 状态机（idle→acquiring→staring→locked→lost）与现有 optical.gd 语义兼容，
#     但本文件是**完整独立模型**，不修改现有 optical.gd；
#   * VIS 最高 L3（分类）且只输出 classification，不输出 identity；
#     IR 只到 L1（锁定 ≠ 分类）；两者均不给测量距离（measured_range_km = -1）；
#   * 无随机源：同输入/同 dt → 确定输出，可 JSON 序列化。
#
# 公式（docs/38 §5.2–5.5 / docs/11 §3.3/§3.4）：
#   FOV  = 2·atan(detector_px · pixel_pitch / (2·focal))
#   IFOV = pixel_pitch / focal；IFOV_eff = max(IFOV, 1.22λ/D)
#   θ_t  = size_m / R_m；N_px = θ_t / IFOV_eff
#   VIS 所需的凝视 = clamp(stare_ref · (R/stare_ref_km)² / quality, 4, 240)
#   smear_px = ω_rel · exposure_s / IFOV_eff
#   SNR(dB) ≈ ref_snr + 20log10(D/D_ref) + 20log10(R_ref/R)
#             + 10log10(exposure/exposure_ref) + 10log10(illum|contrast)
#   IR contrast = (T/300)⁴ · (A/1000 m²) · shadow_factor
# ═══════════════════════════════════════════════════════════════════

const Types := preload("res://framework/sim/sensor_types.gd")

const SCHEMA := "optical_ir.v1"
const K_OPTICAL := "optical"
const K_IR := "ir"
const KINDS: Array = [K_OPTICAL, K_IR]

const STATUS_IDLE := "idle"
const STATUS_ACQUIRING := "acquiring"
const STATUS_STARING := "staring"
const STATUS_LOCKED := "locked"
const STATUS_LOST := "lost"

const R_EARTH_KM := 6378.137
const R_MOON_KM := 1737.4
const LN10 := 2.302585092994046
const EPS := 1.0e-9
const MAX_CHANNELS_DEFAULT := 6
const MAX_EVENTS := 200


static func default_sensors() -> Dictionary:
	return {K_OPTICAL: default_sensor(K_OPTICAL), K_IR: default_sensor(K_IR)}


static func default_sensor(kind: String) -> Dictionary:
	if kind == K_IR:
		return {
			"kind": K_IR, "model": "CH-IR2", "band": "8-12 um", "wavelength_um": 10.0,
			"aperture_m": 0.35, "focal_m": 1.2, "detector_px": 1024,
			"pixel_pitch_um": 15.0, "range_km": 60000.0, "refresh_s": 1.0,
			"stare_s_ref": 4.0, "stare_ref_km": 0.0, "illum_min": 0.0,
			"min_snr_db": 8.0, "max_exposure_s": 0.25, "classification_px": 0.0,
			"reset_maneuver_g": 0.05, "reset_angular_rate_dps": 1.0,
			"track_rate_dps": 1.2, "slew_rate_dps": 6.0, "sun_avoid_deg": 0.0,
			"lost_hold_s": 8.0, "ref_snr_db": 20.0, "ref_range_km": 60000.0,
			"ref_aperture_m": 0.35, "ref_exposure_s": 0.25,
			"ref_temp_k": 300.0, "ref_area_m2": 1000.0, "shadow_contrast": 0.6,
			"sigma_bearing_deg": 1.2, "range_band_edges": [0.333, 0.667],
			"max_channels": 6,
		}
	return {
		"kind": K_OPTICAL, "model": "MS-OT2", "band": "0.4-0.7 um", "wavelength_um": 0.55,
		"aperture_m": 1.2, "focal_m": 4.8, "detector_px": 4096,
		"pixel_pitch_um": 5.0, "range_km": 15000.0, "refresh_s": 8.0,
		"stare_s_ref": 40.0, "stare_ref_km": 8000.0, "illum_min": 0.10,
		"min_snr_db": 8.0, "max_exposure_s": 1.0, "classification_px": 3.0,
		"reset_maneuver_g": 0.02, "reset_angular_rate_dps": 0.5,
		"track_rate_dps": 0.8, "slew_rate_dps": 5.0, "sun_avoid_deg": 5.0,
		"lost_hold_s": 8.0, "ref_snr_db": 16.0, "ref_range_km": 15000.0,
		"ref_aperture_m": 1.2, "ref_exposure_s": 1.0,
		"ref_temp_k": 300.0, "ref_area_m2": 1000.0, "shadow_contrast": 0.6,
		"sigma_bearing_deg": 0.05, "range_band_edges": [0.333, 0.667],
		"max_channels": 6,
	}


static func prepare_sensor(cfg: Dictionary, kind: String) -> Dictionary:
	var s := default_sensor(kind)
	for k in cfg.keys():
		s[str(k)] = cfg[k]
	s["kind"] = kind
	s["detector_px"] = maxi(1, int(s.get("detector_px", 1024)))
	s["pixel_pitch_um"] = maxf(0.1, float(s.get("pixel_pitch_um", 5.0)))
	s["focal_m"] = maxf(0.01, float(s.get("focal_m", 1.0)))
	s["aperture_m"] = maxf(0.01, float(s.get("aperture_m", 0.1)))
	s["wavelength_um"] = maxf(0.05, float(s.get("wavelength_um", 0.55)))
	s["detector_width_m"] = float(s["detector_px"]) * s["pixel_pitch_um"] * 1.0e-6
	s["fov_deg"] = rad_to_deg(2.0 * atan(float(s["detector_width_m"]) / (2.0 * float(s["focal_m"]))))
	s["ifov_rad"] = (float(s["pixel_pitch_um"]) * 1.0e-6) / float(s["focal_m"])
	s["diffraction_rad"] = 1.22 * (float(s["wavelength_um"]) * 1.0e-6) / float(s["aperture_m"])
	s["ifov_eff_rad"] = maxf(float(s["ifov_rad"]), float(s["diffraction_rad"]))
	s["ifov_urad"] = float(s["ifov_rad"]) * 1.0e6
	s["ifov_eff_urad"] = float(s["ifov_eff_rad"]) * 1.0e6
	s["fov_half_deg"] = float(s["fov_deg"]) * 0.5
	s["boresight_deg"] = float(s.get("boresight_deg", 0.0))
	s["boresight_el_deg"] = float(s.get("boresight_el_deg", 0.0))
	s["desired_target_id"] = str(s.get("desired_target_id", ""))
	s["pointing_mode"] = str(s.get("pointing_mode", "track"))
	s["max_channels"] = maxi(1, int(s.get("max_channels", MAX_CHANNELS_DEFAULT)))
	s["range_band_edges"] = (s.get("range_band_edges", [0.333, 0.667]) as Array).duplicate()
	return s


static func default_observer(observer_id := "harmattan") -> Dictionary:
	return {"id": observer_id, "pos_km": [7000.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
		"attitude_quat": [0.0, 0.0, 0.0, 1.0], "angular_rate_dps": [0.0, 0.0, 0.0],
		"maneuver_g": 0.0}


## 便捷构造 snapshot（目标位置为同一惯性/局部帧 km；与 V2 world_snapshot 同约定）。
static func make_snapshot(t_s: float, observer: Dictionary, targets: Array, env := {}) -> Dictionary:
	return {"t": t_s, "observer": observer.duplicate(true),
		"targets": targets.duplicate(true), "sun_illum": float(env.get("sun_illum", 1.0)),
		"shadow": bool(env.get("shadow", false)),
		"earth": (env.get("earth", {"pos_km": [0.0, 0.0, 0.0], "radius_km": R_EARTH_KM}) as Dictionary).duplicate(true),
		"moon": (env.get("moon", {}) as Dictionary).duplicate(true),
		"earth_albedo": float(env.get("earth_albedo", 0.03)),
		"sun_dir": (env.get("sun_dir", []) as Array).duplicate(),
		"los": bool(env.get("los", true)),
		"optics_transmittance": float(env.get("optics_transmittance", 1.0)),
	}


static func make_target(target_id: String, pos_km: Array, opts := {}) -> Dictionary:
	return {
		"id": target_id,
		"pos_km": pos_km.duplicate(),
		"vel_kmps": (opts.get("vel_kmps", [0.0, 0.0, 0.0]) as Array).duplicate(),
		"size_m": float(opts.get("size_m", 50.0)),
		"temp_k": float(opts.get("temp_k", 300.0)),
		"area_m2": float(opts.get("area_m2", 1000.0)),
		"illum": float(opts.get("illum", 1.0)),
		"classification": (opts.get("classification", {}) as Dictionary).duplicate(true),
		"identity": "unknown",
	}


var sensors: Dictionary = {}
var channels: Dictionary = {}       # "kind:target_id" -> channel
var enabled := true
var t := 0.0
var errors: Array[String] = []
var warnings: Array[String] = []
var events: Array = []
var _event_lock := false


func _init(opts := {}) -> void:
	setup(opts)


func setup(opts := {}) -> bool:
	errors.clear()
	warnings.clear()
	channels.clear()
	t = 0.0
	var cfg: Dictionary = opts if opts is Dictionary else {}
	enabled = bool(cfg.get("enabled", true))
	sensors.clear()
	var raw_sensors: Dictionary = {}
	if cfg.get("sensors") is Dictionary:
		raw_sensors = (cfg.get("sensors") as Dictionary)
	else:
		raw_sensors = default_sensors()
	for kind in KINDS:
		if raw_sensors.has(kind) and raw_sensors[kind] is Dictionary:
			sensors[kind] = prepare_sensor(raw_sensors[kind] as Dictionary, kind)
		else:
			warnings.append("sensor %s missing" % kind)
	if sensors.is_empty():
		errors.append("no sensors configured")
		return false
	# 校验必须字段/推导
	for kind in sensors.keys():
		var s: Dictionary = sensors[kind]
		if float(s.get("fov_deg", 0.0)) <= 0.0 or float(s.get("ifov_eff_rad", 0.0)) <= 0.0:
			errors.append("sensor %s invalid optics" % kind)
		if float(s.get("range_km", 0.0)) <= 0.0:
			errors.append("sensor %s invalid range_km" % kind)
	return errors.is_empty()


func set_sensor(kind: String, cfg: Dictionary) -> bool:
	if not KINDS.has(kind):
		errors.append("unknown sensor kind: %s" % kind)
		return false
	sensors[kind] = prepare_sensor(cfg, kind)
	return true


func has_sensor(kind: String) -> bool:
	return sensors.has(kind)


func set_enabled(on: bool) -> void:
	enabled = on


# ═══════════════════════════════════════════════════════════════════
# 1. 通道管理
# ═══════════════════════════════════════════════════════════════════

func _key(kind: String, target_id: String) -> String:
	return "%s:%s" % [kind, target_id]


func _sensor(kind: String) -> Dictionary:
	return sensors.get(kind, {}) if sensors.get(kind) is Dictionary else {}


func start_channel(kind: String, target_id: String, opts := {}) -> Dictionary:
	if not KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind", "kind": kind}
	if not enabled:
		return {"ok": false, "reason": "model_disabled"}
	if not sensors.has(kind):
		return {"ok": false, "reason": "no_sensor", "kind": kind}
	if target_id == "":
		return {"ok": false, "reason": "target_required"}
	var sensor: Dictionary = sensors[kind]
	var active := _channels_of(kind)
	if active.size() >= int(sensor.get("max_channels", MAX_CHANNELS_DEFAULT)):
		return {"ok": false, "reason": "capacity_full", "kind": kind}
	var key := _key(kind, target_id)
	if channels.has(key):
		return {"ok": true, "reason": "already_open", "channel": export_channel(channels[key])}
	# 新通道：默认把无活动通道的云台 slaves 到目标；已有活动通道时保持视轴（需 slew/aim）。
	var opt: Dictionary = opts if opts is Dictionary else {}
	if opt.has("boresight_deg") or opt.has("boresight_el_deg"):
		sensor["boresight_deg"] = float(opt.get("boresight_deg", sensor.get("boresight_deg", 0.0)))
		sensor["boresight_el_deg"] = float(opt.get("boresight_el_deg", sensor.get("boresight_el_deg", 0.0)))
		sensor["pointing_mode"] = "fixed"
	elif active.is_empty():
		sensor["pointing_mode"] = "track"
		sensor["desired_target_id"] = target_id
	sensor["desired_target_id"] = String(opt.get("desired_target", target_id))
	channels[key] = {
		"kind": kind, "target_id": target_id, "status": STATUS_IDLE,
		"status_since_t": t, "stare_s": float(opt.get("elapsed_s", 0.0)),
		"progress": 0.0, "samples": 0, "sample_acc": 0.0,
		"required_s": 0.0, "refresh_s": float(sensor.get("refresh_s", 1.0)),
		"slant_range_km": -1.0, "measured_range_km": -1.0, "range_band": "",
		"bearing_deg": -1.0, "elevation_deg": 0.0, "boresight_deg": float(sensor.get("boresight_deg", 0.0)),
		"boresight_el_deg": float(sensor.get("boresight_el_deg", 0.0)),
		"off_axis_deg": -1.0, "fov_deg": float(sensor.get("fov_deg", 0.0)),
		"ifov_urad": float(sensor.get("ifov_urad", 0.0)),
		"ifov_eff_urad": float(sensor.get("ifov_eff_urad", 0.0)),
		"illum": 1.0, "contrast": 1.0, "snr_db": -999.0, "min_snr_db": float(sensor.get("min_snr_db", 8.0)),
		"angular_size_rad": 0.0, "n_px": 0.0, "smear_px": 0.0,
		"omega_dps": 0.0, "track_rate_dps": float(sensor.get("track_rate_dps", 1.0)),
		"effective_range_km": -1.0, "exposure_s": float(sensor.get("max_exposure_s", 1.0)),
		"visible": false, "detected": false, "locked": false,
		"classify_ok": false, "level_support": 0, "classification": {},
		"identity": "unknown", "reason": "", "failures": [],
		"locked_t": -1.0, "lost_at": -1.0, "predicted_next_t": -1.0,
		"history": [],
	}
	var ch: Dictionary = channels[key]
	_set_status(ch, STATUS_ACQUIRING if float(ch["stare_s"]) > 0.0 else STATUS_IDLE, "open", events)
	events.append({"t": t, "kind": "channel_open", "channel": kind, "target_id": target_id})
	if not sensors.has(kind):
		errors.append("no sensor")
	return {"ok": true, "reason": "", "channel": export_channel(ch)}


func stop_channel(kind: String, target_id := "") -> void:
	if target_id != "":
		channels.erase(_key(kind, target_id))
		return
	for key in channels.keys():
		if String((channels[key] as Dictionary).get("kind", "")) == kind:
			channels.erase(key)


func stop_all() -> void:
	channels.clear()


func active_targets(kind := "") -> Array:
	var out: Array = []
	for raw in channels.values():
		var ch: Dictionary = raw
		if kind == "" or String(ch.get("kind", "")) == kind:
			out.append(String(ch.get("target_id", "")))
	return out


func channel(kind: String, target_id: String) -> Dictionary:
	var raw = channels.get(_key(kind, target_id), {})
	return raw if raw is Dictionary else {}


# ── A-05：运行态导出/导入（底层通道状态可续跑，不靠 UI 缓存伪造）──────
const STATE_SCHEMA := "v17.optical_ir.state.v1"
const POINTING_MODES := ["track", "fixed"]
const STATE_VERSION := 1


## 导出：enabled + 时钟 + 每个通道的完整运行态（kind/target/status/progress/...）。
func export_state() -> Dictionary:
	var chans: Array = []
	var keys: Array = channels.keys()
	keys.sort()
	for k in keys:
		var raw = channels.get(k)
		if raw is Dictionary:
			chans.append((raw as Dictionary).duplicate(true))
	# A00：`_slew_toward_targets()` 每 tick 把 sensors[kind] 的 boresight 朝 LOS 推进，
	# 属**运行态**；不持久化会让恢复会话从默认 0 重新慢速 slew，导致
	# fov_miss / obs_seq 与原始会话分歧（D1/D2 根因）。
	var pointing: Dictionary = {}
	for kind in sensors.keys():
		var srow: Dictionary = sensors[kind]
		# R6/G1：动态指向必须保存**目标与模式**，只存角度会在读档后停止跟踪
		#（desired_target_id 为空 → `_update_pointing` 直接 continue）。
		pointing[String(kind)] = {
			"boresight_deg": float(srow.get("boresight_deg", 0.0)),
			"boresight_el_deg": float(srow.get("boresight_el_deg", 0.0)),
			"pointing_mode": String(srow.get("pointing_mode", "track")),
			"desired_target_id": String(srow.get("desired_target_id", "")),
		}
	return {
		"schema": STATE_SCHEMA,
		"version": STATE_VERSION,
		"enabled": enabled,
		"t": t,
		"channels": JSON.parse_string(JSON.stringify(chans)),
		"mount_pointing": pointing,
	}


## R6/G2：只校验不改状态（供 authority 两阶段原子导入；失败不得半写）。
func validate_state(state: Dictionary) -> Dictionary:
	var errs: Array = []
	if String(state.get("schema", "")) != STATE_SCHEMA:
		errs.append("optical.schema mismatch: " + String(state.get("schema", "")))
	var ver = state.get("version", null)
	if not (ver is int or ver is float) or not is_finite(float(ver)) \
			or absf(float(ver) - roundf(float(ver))) > 0.0 \
			or int(roundf(float(ver))) != STATE_VERSION:
		errs.append("optical.version must be exact integer %d (got %s)" % [
			STATE_VERSION, str(ver)])
	var stt = state.get("t", null)
	if not (stt is int or stt is float) or not is_finite(float(stt)) \
			or float(stt) < 0.0:
		errs.append("optical.t must be finite >= 0")
	if state.get("enabled", null) != null and not (state.get("enabled") is bool):
		errs.append("optical.enabled must be bool")
	var raw_channels = state.get("channels", null)
	if not (raw_channels is Array):
		errs.append("optical.channels must be an array")
	else:
		var seen_keys: Dictionary = {}
		for raw_ch in (raw_channels as Array):
			if not (raw_ch is Dictionary):
				errs.append("optical.channels item must be an object")
				continue
			var ch2: Dictionary = raw_ch
			for req in ["kind", "target_id", "status"]:
				if String(ch2.get(req, "")) == "":
					errs.append("optical.channels item missing %s" % req)
			var key2 := "%s:%s" % [String(ch2.get("kind", "")),
				String(ch2.get("target_id", ""))]
			if seen_keys.has(key2):
				errs.append("optical.channels duplicate key: " + key2)
			seen_keys[key2] = true
	var raw_p = state.get("mount_pointing", null)
	if raw_p != null and not (raw_p is Dictionary):
		errs.append("optical.mount_pointing must be an object")
	elif raw_p is Dictionary:
		for kind_key in (raw_p as Dictionary).keys():
			var prow2 = (raw_p as Dictionary)[kind_key]
			if not (prow2 is Dictionary):
				errs.append("optical.mount_pointing.%s must be an object" % String(kind_key))
				continue
			for pf in ["boresight_deg", "boresight_el_deg"]:
				var pv = (prow2 as Dictionary).get(pf, null)
				if not (pv is int or pv is float) or not is_finite(float(pv)):
					errs.append("optical.mount_pointing.%s.%s must be finite" % [
						String(kind_key), pf])
			if not sensors.has(String(kind_key)):
				errs.append("optical.mount_pointing unknown kind: " + String(kind_key))
				continue
			var pm2 := String((prow2 as Dictionary).get("pointing_mode", "track"))
			if not (pm2 in POINTING_MODES):
				errs.append("optical.mount_pointing.%s.pointing_mode unsupported: %s" % [
					String(kind_key), pm2])
			var az2 := float((prow2 as Dictionary).get("boresight_deg", 0.0))
			var el2 := float((prow2 as Dictionary).get("boresight_el_deg", 0.0))
			if az2 < -180.0 or az2 > 180.0 or el2 < -90.0 or el2 > 90.0:
				errs.append("optical.mount_pointing.%s angle out of range (az=%s el=%s)" % [
					String(kind_key), str(az2), str(el2)])
	return {"ok": errs.is_empty(), "errors": errs}
## 导入：先完整校验，再一次性提交；失败不改后端。
func import_state(state: Dictionary) -> Dictionary:
	if String(state.get("schema", "")) != STATE_SCHEMA:
		return {"ok": false, "reason": "invalid_state_schema",
			"errors": ["expected " + STATE_SCHEMA]}
	if int(state.get("version", 0)) != STATE_VERSION:
		return {"ok": false, "reason": "invalid_state_version",
			"errors": ["expected version %d" % STATE_VERSION]}
	var st = state.get("t", null)
	if not (st is int or st is float) or not is_finite(float(st)) or float(st) < 0.0:
		return {"ok": false, "reason": "invalid_clock", "errors": ["t must be finite >= 0"]}
	var raw_chans = state.get("channels", null)
	if not (raw_chans is Array):
		return {"ok": false, "reason": "invalid_channels", "errors": ["channels must be array"]}
	var new_channels: Dictionary = {}
	var problems: Array = []
	var idx := 0
	for raw in (raw_chans as Array):
		if not (raw is Dictionary):
			problems.append("channels[%d]: not an object" % idx)
			idx += 1
			continue
		var ch: Dictionary = (raw as Dictionary).duplicate(true)
		var kind := String(ch.get("kind", ""))
		var tid := String(ch.get("target_id", ""))
		if kind == "":
			problems.append("channels[%d]: missing kind" % idx)
		if tid == "":
			problems.append("channels[%d]: missing target_id" % idx)
		var key := _key(kind, tid)
		if new_channels.has(key):
			problems.append("channels[%d]: duplicate key %s" % [idx, key])
		new_channels[key] = ch
		idx += 1
	if not problems.is_empty():
		return {"ok": false, "reason": "invalid_state", "errors": problems.slice(0, 20)}
	# A00：恢复挂载指向（与 channels 一起原子提交）；不合法则整体拒绝。
	var raw_point = state.get("mount_pointing", null)
	if raw_point != null and not (raw_point is Dictionary):
		return {"ok": false, "reason": "invalid_mount_pointing",
			"errors": ["mount_pointing must be an object"]}
	if raw_point is Dictionary:
		for kind_key in (raw_point as Dictionary).keys():
			var prow = (raw_point as Dictionary)[kind_key]
			if not (prow is Dictionary):
				return {"ok": false, "reason": "invalid_mount_pointing",
					"errors": ["mount_pointing.%s must be an object" % String(kind_key)]}
			for pf in ["boresight_deg", "boresight_el_deg"]:
				var pv = (prow as Dictionary).get(pf, null)
				if not (pv is int or pv is float) or not is_finite(float(pv)):
					return {"ok": false, "reason": "invalid_mount_pointing",
						"errors": ["mount_pointing.%s.%s must be a finite number" % [
							String(kind_key), pf]]}
			if not sensors.has(String(kind_key)):
				return {"ok": false, "reason": "unknown_sensor_kind",
					"errors": ["mount_pointing references unknown kind: "
						+ String(kind_key)]}
			var pm := String((prow as Dictionary).get("pointing_mode", "track"))
			if not (pm in POINTING_MODES):
				return {"ok": false, "reason": "invalid_mount_pointing",
					"errors": ["mount_pointing.%s.pointing_mode unsupported: %s" % [
						String(kind_key), pm]]}
			var azv := float((prow as Dictionary).get("boresight_deg", 0.0))
			var elv := float((prow as Dictionary).get("boresight_el_deg", 0.0))
			if azv < -180.0 or azv > 180.0 or elv < -90.0 or elv > 90.0:
				return {"ok": false, "reason": "invalid_mount_pointing",
					"errors": ["mount_pointing.%s angle out of range: az=%s el=%s" % [
						String(kind_key), str(azv), str(elv)]]}
	enabled = bool(state.get("enabled", true))
	t = float(st)
	channels = new_channels
	if raw_point is Dictionary:
		for kind_key2 in (raw_point as Dictionary).keys():
			var srow2: Dictionary = sensors[String(kind_key2)]
			var prow2: Dictionary = (raw_point as Dictionary)[kind_key2]
			srow2["boresight_deg"] = float(prow2.get("boresight_deg", 0.0))
			srow2["boresight_el_deg"] = float(prow2.get("boresight_el_deg", 0.0))
			srow2["pointing_mode"] = String(prow2.get("pointing_mode", "track"))
			srow2["desired_target_id"] = String(
				prow2.get("desired_target_id", ""))
	return {"ok": true, "channels": channels.size(), "t": t, "enabled": enabled}

func _channels_of(kind: String) -> Array:
	var out: Array = []
	for raw in channels.values():
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw)
	return out


func set_boresight(kind: String, az_deg: float, el_deg := 0.0) -> Dictionary:
	if not sensors.has(kind):
		return {"ok": false, "reason": "no_sensor"}
	var s: Dictionary = sensors[kind]
	s["boresight_deg"] = az_deg
	s["boresight_el_deg"] = el_deg
	s["pointing_mode"] = "fixed"
	return {"ok": true, "kind": kind, "boresight_deg": az_deg, "boresight_el_deg": el_deg}


func aim_at(kind: String, target_id: String) -> Dictionary:
	if not sensors.has(kind):
		return {"ok": false, "reason": "no_sensor"}
	(sensors[kind] as Dictionary)["desired_target_id"] = target_id
	(sensors[kind] as Dictionary)["pointing_mode"] = "track"
	return {"ok": true, "kind": kind, "target_id": target_id}


# ═══════════════════════════════════════════════════════════════════
# 2. 几何 / 物理工具
# ═══════════════════════════════════════════════════════════════════

static func log10(x: float) -> float:
	return log(maxf(1.0e-12, x)) / LN10


static func target_velocity(target: Dictionary) -> Vector3:
	for key in ["vel_kmps", "v", "velocity"]:
		if target.get(key) is Array and (target.get(key) as Array).size() >= 3:
			var a: Array = target.get(key)
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if target.get(key) is Vector3:
			return target.get(key)
	return Vector3.ZERO


static func observer_velocity(snapshot: Dictionary) -> Vector3:
	var obs = snapshot.get("observer", {})
	if obs is Dictionary:
		var o: Dictionary = obs
		for key in ["vel_kmps", "v", "velocity"]:
			if o.get(key) is Array and (o.get(key) as Array).size() >= 3:
				var a: Array = o.get(key)
				return Vector3(float(a[0]), float(a[1]), float(a[2]))
			if o.get(key) is Vector3:
				return o.get(key)
	return Vector3.ZERO


static func los_angles(los: Vector3) -> Array:
	# 0°=北（+y）、90°=东（+x）；与 V15/V2 传感器同口径。
	if los.length() < EPS:
		return [0.0, 0.0]
	var az := rad_to_deg(atan2(los.x, los.y))
	var el := rad_to_deg(atan2(los.z, sqrt(los.x * los.x + los.y * los.y)))
	return [az, el]


static func dir_from_angles(az_deg: float, el_deg: float) -> Vector3:
	var a := deg_to_rad(az_deg)
	var e := deg_to_rad(el_deg)
	return Vector3(sin(a) * cos(e), cos(a) * cos(e), sin(e))


static func angle_between_deg(a: Vector3, b: Vector3) -> float:
	if a.length() < EPS or b.length() < EPS:
		return 180.0
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


## 线段 AB 是否穿过球体（不含端点附近）；用于地球/月球遮挡。
static func segment_hits_sphere(a: Vector3, b: Vector3, center: Vector3, radius_km: float) -> bool:
	if radius_km <= 0.0:
		return false
	var d := b - a
	var len2 := d.length_squared()
	if len2 < EPS:
		return a.distance_to(center) < radius_km
	var f := a - center
	var t := -f.dot(d) / len2
	if t <= 1.0e-4 or t >= 1.0 - 1.0e-4:
		return false
	var closest := a + d * t
	return closest.distance_to(center) < radius_km - EPS


static func _target_illum(snapshot: Dictionary, target: Dictionary) -> float:
	var sun := clampf(float(snapshot.get("sun_illum", 1.0)), 0.0, 2.0)
	var shadow := bool(snapshot.get("shadow", false))
	var trans := clampf(float(snapshot.get("optics_transmittance", 1.0)), 0.0, 1.0)
	var base := sun * (0.0 if shadow else 1.0)
	var target_illum = target.get("illum", null)
	if target_illum != null:
		base = minf(base, float(target_illum) if not shadow else 0.0)
	var albedo := clampf(float(snapshot.get("earth_albedo", 0.03)), 0.0, 1.0)
	return clampf(base + albedo * 0.5, 0.0, 2.0) * trans


static func _ir_contrast(target: Dictionary, snapshot: Dictionary) -> float:
	var temp := maxf(1.0, float(target.get("temp_k", 300.0)))
	var area := maxf(0.0, float(target.get("area_m2", 1000.0)))
	var shadow_factor := float(snapshot.get("shadow_contrast", 0.6)) if bool(snapshot.get("shadow", false)) else 1.0
	return clampf(pow(temp / 300.0, 4.0) * (area / 1000.0) * shadow_factor, 0.0, 8.0)


# ═══════════════════════════════════════════════════════════════════
# 3. step
# ═══════════════════════════════════════════════════════════════════

func step(dt: float, snapshot := {}) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	var new_events: Array = []
	if enabled:
		_update_pointing(d, snapshot, new_events)
		for key in channels.keys():
			var ch: Dictionary = channels[key]
			_step_channel(ch, d, snapshot, new_events)
	for ev in new_events:
		events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return {"t": t, "dt": d, "enabled": enabled, "channels": export_channels(),
		"by_status": by_status(), "sensors": sensors_view(), "events": new_events}


func _update_pointing(dt: float, snapshot: Dictionary, events: Array) -> void:
	for kind in sensors.keys():
		var s: Dictionary = sensors[kind]
		if String(s.get("pointing_mode", "track")) != "track":
			continue
		var tid := String(s.get("desired_target_id", ""))
		if tid == "":
			continue
		var target := _target_by_id(snapshot, tid)
		if target.is_empty():
			continue
		var obs_pos := Types.observer_pos_km(snapshot)
		var los := Types.target_pos_km(target) - obs_pos
		var ang := los_angles(los)
		var desired_az := float(ang[0])
		var desired_el := float(ang[1])
		var max_step := maxf(0.01, float(s.get("slew_rate_dps", 5.0)) * dt)
		var az := float(s.get("boresight_deg", 0.0))
		var el := float(s.get("boresight_el_deg", 0.0))
		var daz := wrapf(desired_az - az, -180.0, 180.0)
		var del := desired_el - el
		az = wrapf(az + clampf(daz, -max_step, max_step), -180.0, 180.0)
		el = clampf(el + clampf(del, -max_step, max_step), -90.0, 90.0)
		s["boresight_deg"] = az
		s["boresight_el_deg"] = el
		if absf(daz) > 1.0e-6 or absf(del) > 1.0e-6:
			events.append({"t": t, "kind": "slew", "sensor": kind,
				"boresight_deg": az, "boresight_el_deg": el,
				"target_id": tid, "slew_step_deg": max_step})


func _target_by_id(snapshot: Dictionary, target_id: String) -> Dictionary:
	for raw in (snapshot.get("targets", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == target_id:
			return raw
	return {}


func _step_channel(ch: Dictionary, dt: float, snapshot: Dictionary, events: Array) -> void:
	var kind := String(ch.get("kind", ""))
	var target_id := String(ch.get("target_id", ""))
	var s: Dictionary = _sensor(kind)
	if s.is_empty():
		_fail(ch, "no_sensor", dt, events)
		return
	var target := _target_by_id(snapshot, target_id)
	if target.is_empty():
		_fail(ch, "target_missing", dt, events)
		return
	var obs_pos := Types.observer_pos_km(snapshot)
	var tgt_pos := Types.target_pos_km(target)
	var obs_vel := observer_velocity(snapshot)
	var tgt_vel := target_velocity(target)
	var rel := tgt_pos - obs_pos
	var range_km := rel.length()
	if range_km < 1.0e-6:
		_fail(ch, "target_missing", dt, events)
		return
	var los := rel
	var ang := los_angles(los)
	var obz := float(s.get("boresight_deg", 0.0))
	var obl := float(s.get("boresight_el_deg", 0.0))
	ch["bearing_deg"] = float(ang[0])
	ch["elevation_deg"] = float(ang[1])
	ch["boresight_deg"] = obz
	ch["boresight_el_deg"] = obl
	ch["fov_deg"] = float(s.get("fov_deg", 0.0))
	ch["ifov_urad"] = float(s.get("ifov_urad", 0.0))
	ch["ifov_eff_urad"] = float(s.get("ifov_eff_urad", 0.0))
	ch["slant_range_km"] = range_km
	var los_dir := los.normalized()
	var bore_dir := dir_from_angles(obz, obl)
	var off_axis := angle_between_deg(bore_dir, los_dir)
	ch["off_axis_deg"] = off_axis
	var fail := ""
	# 1) FOV
	if off_axis > float(s.get("fov_half_deg", 0.0)) + 1.0e-9:
		fail = "fov_miss"
	# 2) 遮挡（snapshot los 或 地球/月球球体）
	var env_los := bool(snapshot.get("los", true))
	var earth: Dictionary = snapshot.get("earth", {}) if snapshot.get("earth") is Dictionary else {}
	var earth_center := Types.to_vec3(earth.get("pos_km", [0.0, 0.0, 0.0]))
	var earth_radius := float(earth.get("radius_km", R_EARTH_KM))
	var observer_inside_earth := obs_pos.distance_to(earth_center) < earth_radius + 1.0
	var occluded := false
	if not env_los:
		occluded = true
	elif not observer_inside_earth and segment_hits_sphere(obs_pos, tgt_pos, earth_center, earth_radius):
		occluded = true
	var moon: Dictionary = snapshot.get("moon", {}) if snapshot.get("moon") is Dictionary else {}
	if not occluded and not moon.is_empty():
		var moon_center := Types.to_vec3(moon.get("pos_km", [0.0, 0.0, 0.0]))
		var moon_radius := float(moon.get("radius_km", R_MOON_KM))
		if segment_hits_sphere(obs_pos, tgt_pos, moon_center, moon_radius):
			occluded = true
	if fail == "" and occluded:
		fail = "occluded"
	# 3) 光照 / 热对比 / 太阳规避
	var illum := _target_illum(snapshot, target)
	var contrast := _ir_contrast(target, snapshot)
	ch["illum"] = illum
	ch["contrast"] = contrast
	if fail == "":
		var sun_dir_raw = snapshot.get("sun_dir", [])
		if sun_dir_raw is Array and (sun_dir_raw as Array).size() >= 3:
			var sun_dir := Types.to_vec3(sun_dir_raw).normalized()
			if sun_dir.length() > EPS:
				var sun_angle := angle_between_deg(los_dir, sun_dir)
				if float(s.get("sun_avoid_deg", 0.0)) > 0.0 \
						and sun_angle < float(s.get("sun_avoid_deg", 0.0)):
					fail = "dazzled"
	if fail == "" and kind == K_OPTICAL and illum < float(s.get("illum_min", 0.1)):
		fail = "too_dark"
	if fail == "" and kind == K_IR and contrast < 0.02:
		fail = "too_dark"
	# 4) 有效距离/曝光/角尺寸/SNR
	var exposure_s := clampf(float(s.get("max_exposure_s", 1.0)), 0.01, 10.0)
	ch["exposure_s"] = exposure_s
	var eff_range := float(s.get("range_km", 0.0)) * sqrt(maxf(0.01, illum if kind == K_OPTICAL else contrast))
	ch["effective_range_km"] = eff_range
	if fail == "" and range_km > eff_range + 1.0e-9:
		fail = "out_of_range"
	var target_size_m := maxf(0.1, float(target.get("size_m", 50.0)))
	var ifov := maxf(1.0e-12, float(s.get("ifov_eff_rad", 1.0e-6)))
	var angular_size := target_size_m / (range_km * 1000.0)
	var n_px := angular_size / ifov
	ch["angular_size_rad"] = angular_size
	ch["n_px"] = n_px
	var signal_factor := maxf(1.0e-6, illum if kind == K_OPTICAL else contrast)
	var snr_db := float(s.get("ref_snr_db", 12.0)) \
		+ 20.0 * log10(float(s.get("aperture_m", 0.1)) / float(s.get("ref_aperture_m", 0.1))) \
		+ 20.0 * log10(float(s.get("ref_range_km", 1000.0)) / maxf(1.0, range_km)) \
		+ 10.0 * log10(exposure_s / maxf(0.01, float(s.get("ref_exposure_s", 1.0)))) \
		+ 10.0 * log10(signal_factor)
	ch["snr_db"] = snr_db
	if fail == "" and snr_db < float(s.get("min_snr_db", 8.0)):
		fail = "low_snr"
	# 5) 相对角速度 / 运动模糊 / 跟瞄
	var r2 := rel.length_squared()
	var omega_radps := maxf(0.0, rel.cross(tgt_vel - obs_vel).length() / maxf(1.0, r2))
	var obs_rate := 0.0
	var obs_row = snapshot.get("observer", {})
	if obs_row is Dictionary and (obs_row as Dictionary).get("angular_rate_dps") is Array:
		var ar: Array = (obs_row as Dictionary).get("angular_rate_dps")
		if ar.size() >= 3:
			obs_rate = Vector3(float(ar[0]), float(ar[1]), float(ar[2])).length() / 57.2957795
	var omega_total := omega_radps + obs_rate
	var smear_px := omega_total * exposure_s / ifov
	var omega_dps := omega_total * 57.2957795
	ch["omega_dps"] = omega_dps
	ch["smear_px"] = smear_px
	if fail == "" and omega_dps > float(s.get("track_rate_dps", 1.0)) + 1.0e-9:
		fail = "too_fast"
	if fail == "" and smear_px > 1.0 + 1.0e-9:
		fail = "blurred"
	# 6) 平台机动/姿态重置（VIS 更敏感；仍记录失败原因）
	var obs_g := float(obs_row.get("maneuver_g", 0.0)) if obs_row is Dictionary else 0.0
	if fail == "" and float(obs_g) > float(s.get("reset_maneuver_g", 0.02)) + 1.0e-9:
		ch["stare_s"] = 0.0
		ch["progress"] = 0.0
		ch["samples"] = 0
		ch["sample_acc"] = 0.0
		fail = "maneuver"
	# 7) 凝视/锁定
	ch["refresh_s"] = float(s.get("refresh_s", 1.0))
	ch["predicted_next_t"] = t + maxf(0.25, float(s.get("refresh_s", 1.0)))
	if fail != "":
		_fail(ch, fail, dt, events)
		return
	var quality := 1.0
	if kind == K_OPTICAL:
		quality = clampf(illum, 0.1, 1.5)
		if smear_px > 0.5:
			quality *= 1.0 / (1.0 + smear_px)
	var required_s := 4.0
	if kind == K_OPTICAL:
		var ref_km := maxf(1.0, float(s.get("stare_ref_km", 8000.0)))
		required_s = clampf(float(s.get("stare_s_ref", 40.0)) * pow(range_km / ref_km, 2.0) / maxf(0.05, quality), 4.0, 240.0)
	else:
		required_s = 4.0
	ch["required_s"] = required_s
	if String(ch["status"]) == STATUS_LOST or String(ch["status"]) == STATUS_IDLE:
		_set_status(ch, STATUS_ACQUIRING, "acquire", events)
	if String(ch["status"]) == STATUS_ACQUIRING:
		_set_status(ch, STATUS_STARING, "staring", events)
	ch["stare_s"] = float(ch["stare_s"]) + dt
	ch["sample_acc"] = float(ch["sample_acc"]) + dt
	if float(ch["sample_acc"]) + 1.0e-9 >= float(s.get("refresh_s", 1.0)):
		ch["sample_acc"] = 0.0
		ch["samples"] = int(ch.get("samples", 0)) + 1
	ch["progress"] = clampf(float(ch["stare_s"]) / maxf(1.0e-6, required_s), 0.0, 1.0)
	ch["visible"] = true
	ch["detected"] = true
	ch["range_band"] = _ir_band(range_km, eff_range, s) if kind == K_IR else ""
	ch["measured_range_km"] = -1.0
	if float(ch["progress"]) + 1.0e-9 >= 1.0:
		if String(ch["status"]) != STATUS_LOCKED:
			ch["locked_t"] = t
			_set_status(ch, STATUS_LOCKED, "stare_complete", events)
		ch["locked"] = true
		var classify := false
		if kind == K_OPTICAL:
			classify = n_px >= float(s.get("classification_px", 3.0)) - 1.0e-9 \
				and snr_db >= float(s.get("min_snr_db", 8.0)) \
				and illum >= float(s.get("illum_min", 0.1)) \
				and smear_px <= 0.5 + 1.0e-9
			if classify:
				var cls = target.get("classification", {})
				ch["classification"] = (cls as Dictionary).duplicate(true) if cls is Dictionary else {}
				ch["level_support"] = 3
				ch["classify_ok"] = true
			else:
				ch["classification"] = {}
				ch["level_support"] = 1
				ch["classify_ok"] = false
		else:
			ch["classification"] = {}
			ch["level_support"] = 1
			ch["classify_ok"] = false
	else:
		ch["locked"] = false
		ch["level_support"] = 1 if kind == K_OPTICAL else 0
		ch["classification"] = {}
		ch["classify_ok"] = false
	ch["identity"] = "unknown"
	ch["reason"] = ""
	ch["failures"] = []


func _ir_band(range_km: float, eff_range: float, s: Dictionary) -> String:
	var frac := range_km / maxf(1.0, eff_range)
	var edges: Array = s.get("range_band_edges", [0.333, 0.667])
	if frac < float(edges[0]):
		return "near"
	if frac < float(edges[1]):
		return "mid"
	return "far"


func _fail(ch: Dictionary, reason: String, dt: float, events: Array) -> void:
	ch["visible"] = false
	ch["detected"] = false
	ch["locked"] = false
	ch["classify_ok"] = false
	ch["level_support"] = 0
	ch["classification"] = {}
	ch["reason"] = reason
	ch["measured_range_km"] = -1.0
	ch["range_band"] = ""
	var failures: Array = ch.get("failures", [])
	failures.append(reason)
	ch["failures"] = failures
	if String(ch["status"]) != STATUS_LOST:
		ch["lost_at"] = t
		_set_status(ch, STATUS_LOST, reason, events)
	# 失锁后进度保留 lost_hold_s；超时清零。
	var lost_at := float(ch.get("lost_at", t))
	if t - lost_at > float(_sensor(String(ch["kind"])).get("lost_hold_s", 8.0)):
		ch["stare_s"] = 0.0
		ch["progress"] = 0.0
		ch["samples"] = 0
		ch["sample_acc"] = 0.0


func _set_status(ch: Dictionary, status: String, reason: String, events: Array) -> void:
	var from := String(ch.get("status", STATUS_IDLE))
	if from == status:
		ch["reason"] = reason
		return
	ch["status"] = status
	ch["status_since_t"] = t
	ch["reason"] = reason
	var ev := {"t": t, "kind": "channel_status", "channel": String(ch.get("kind", "")),
		"target_id": String(ch.get("target_id", "")), "from": from, "to": status,
		"reason": reason, "progress": float(ch.get("progress", 0.0))}
	events.append(ev)
	var hist: Array = ch.get("history", [])
	hist.append({"t": t, "from": from, "to": status, "reason": reason})
	while hist.size() > 16:
		hist.pop_front()
	ch["history"] = hist


# ═══════════════════════════════════════════════════════════════════
# 4. 查询 / JSON
# ═══════════════════════════════════════════════════════════════════

func export_channel(ch: Dictionary) -> Dictionary:
	var s: Dictionary = _sensor(String(ch.get("kind", "")))
	return {
		"channel": String(ch.get("kind", "")),
		"target_id": String(ch.get("target_id", "")),
		"status": String(ch.get("status", STATUS_IDLE)),
		"status_since_t": float(ch.get("status_since_t", 0.0)),
		"progress": float(ch.get("progress", 0.0)),
		"stare_s": float(ch.get("stare_s", 0.0)),
		"required_s": float(ch.get("required_s", 0.0)),
		"refresh_s": float(ch.get("refresh_s", 1.0)),
		"samples": int(ch.get("samples", 0)),
		"exposure_s": float(ch.get("exposure_s", 1.0)),
		"model": String(s.get("model", "")), "band": String(s.get("band", "")),
		"aperture_m": float(s.get("aperture_m", 0.0)), "focal_m": float(s.get("focal_m", 0.0)),
		"detector_px": int(s.get("detector_px", 0)), "pixel_pitch_um": float(s.get("pixel_pitch_um", 0.0)),
		"fov_deg": float(ch.get("fov_deg", 0.0)),
		"ifov_urad": float(ch.get("ifov_urad", 0.0)),
		"ifov_eff_urad": float(ch.get("ifov_eff_urad", 0.0)),
		"boresight_deg": float(ch.get("boresight_deg", 0.0)),
		"boresight_el_deg": float(ch.get("boresight_el_deg", 0.0)),
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"elevation_deg": float(ch.get("elevation_deg", 0.0)),
		"off_axis_deg": float(ch.get("off_axis_deg", -1.0)),
		"slant_range_km": float(ch.get("slant_range_km", -1.0)),
		"measured_range_km": -1.0,
		"range_band": String(ch.get("range_band", "")),
		"effective_range_km": float(ch.get("effective_range_km", -1.0)),
		"illum": float(ch.get("illum", 0.0)), "contrast": float(ch.get("contrast", 1.0)),
		"snr_db": float(ch.get("snr_db", -999.0)), "min_snr_db": float(ch.get("min_snr_db", 8.0)),
		"angular_size_rad": float(ch.get("angular_size_rad", 0.0)),
		"n_px": float(ch.get("n_px", 0.0)),
		"classification_px": float(s.get("classification_px", 0.0)),
		"smear_px": float(ch.get("smear_px", 0.0)),
		"omega_dps": float(ch.get("omega_dps", 0.0)),
		"track_rate_dps": float(ch.get("track_rate_dps", 1.0)),
		"visible": bool(ch.get("visible", false)),
		"detected": bool(ch.get("detected", false)),
		"locked": bool(ch.get("locked", false)),
		"classify_ok": bool(ch.get("classify_ok", false)),
		"level_support": int(ch.get("level_support", 0)),
		"level_cap": "L3_optical_classify" if String(ch.get("kind", "")) == K_OPTICAL else "L1_ir_only",
		"classification": (ch.get("classification", {}) as Dictionary).duplicate(true),
		"identity": "unknown",
		"reason": String(ch.get("reason", "")),
		"failures": (ch.get("failures", []) as Array).duplicate(),
		"locked_t": float(ch.get("locked_t", -1.0)),
		"lost_at": float(ch.get("lost_at", -1.0)),
		"predicted_next_t": float(ch.get("predicted_next_t", -1.0)),
		"history": (ch.get("history", []) as Array).duplicate(true),
	}


func export_channels() -> Array:
	var out: Array = []
	for kind in KINDS:
		for raw in channels.values():
			var ch: Dictionary = raw
			if String(ch.get("kind", "")) == kind:
				out.append(export_channel(ch))
	return out


func by_status() -> Dictionary:
	var counts: Dictionary = {STATUS_IDLE: 0, STATUS_ACQUIRING: 0, STATUS_STARING: 0,
		STATUS_LOCKED: 0, STATUS_LOST: 0}
	for raw in channels.values():
		var st := String((raw as Dictionary).get("status", STATUS_IDLE))
		counts[st] = int(counts.get(st, 0)) + 1
	return counts


func sensors_view() -> Dictionary:
	var out: Dictionary = {}
	for kind in sensors.keys():
		var s: Dictionary = sensors[kind]
		out[kind] = {
			"kind": kind, "model": String(s.get("model", "")),
			"band": String(s.get("band", "")), "aperture_m": float(s.get("aperture_m", 0.0)),
			"focal_m": float(s.get("focal_m", 0.0)), "detector_px": int(s.get("detector_px", 0)),
			"pixel_pitch_um": float(s.get("pixel_pitch_um", 0.0)),
			"fov_deg": float(s.get("fov_deg", 0.0)), "fov_half_deg": float(s.get("fov_half_deg", 0.0)),
			"ifov_urad": float(s.get("ifov_urad", 0.0)),
			"ifov_eff_urad": float(s.get("ifov_eff_urad", 0.0)),
			"diffraction_urad": float(s.get("diffraction_rad", 0.0)) * 1.0e6,
			"range_km": float(s.get("range_km", 0.0)),
			"refresh_s": float(s.get("refresh_s", 1.0)),
			"max_exposure_s": float(s.get("max_exposure_s", 1.0)),
			"min_snr_db": float(s.get("min_snr_db", 8.0)),
			"reset_maneuver_g": float(s.get("reset_maneuver_g", 0.02)),
			"track_rate_dps": float(s.get("track_rate_dps", 1.0)),
			"slew_rate_dps": float(s.get("slew_rate_dps", 5.0)),
			"boresight_deg": float(s.get("boresight_deg", 0.0)),
			"boresight_el_deg": float(s.get("boresight_el_deg", 0.0)),
			"desired_target_id": String(s.get("desired_target_id", "")),
			"active_channels": _channels_of(kind).size(),
			"max_channels": int(s.get("max_channels", MAX_CHANNELS_DEFAULT)),
		}
	return out


func channel_status(target_id := "") -> Dictionary:
	var out: Dictionary = {"track_id": target_id, "channels": {}}
	if target_id != "":
		for kind in KINDS:
			var ch := channel(kind, target_id)
			if not ch.is_empty():
				out["channels"][kind] = export_channel(ch)
		return out
	for raw in export_channels():
		var row: Dictionary = raw
		out["channels"]["%s:%s" % [row.get("channel", ""), row.get("target_id", "")]] = row
	return out


func vm_optical_ir() -> Dictionary:
	return {
		"schema": SCHEMA, "model": "optical_ir_channel.v1", "mode": "shadow",
		"authoritative": false, "enabled": enabled, "t": t,
		"sensors": sensors_view(), "channels": export_channels(), "by_status": by_status(),
		"events": events.duplicate(true), "warnings": warnings.duplicate(),
		"writes": {"track_table": false, "v15": false},
		"summary": summary(),
	}


func summary() -> Dictionary:
	var st := by_status()
	var locked := int(st.get(STATUS_LOCKED, 0))
	var optical_l3 := 0
	var ir_l1 := 0
	for raw in channels.values():
		var ch: Dictionary = raw
		if String(ch.get("kind", "")) == K_OPTICAL and int(ch.get("level_support", 0)) >= 3:
			optical_l3 += 1
		if String(ch.get("kind", "")) == K_IR and int(ch.get("level_support", 0)) >= 1:
			ir_l1 += 1
	return {"channels": channels.size(), "locked": locked,
		"staring": int(st.get(STATUS_STARING, 0)), "acquiring": int(st.get(STATUS_ACQUIRING, 0)),
		"lost": int(st.get(STATUS_LOST, 0)), "optical_l3": optical_l3, "ir_l1": ir_l1,
		"writes_track_table": false, "writes_v15": false}


func to_dict() -> Dictionary:
	return vm_optical_ir()
