class_name V2SensorAuthority
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 传感器权威 · SHADOW 模式（R5-SHADOW-1）
#
# 职责：
#   * 输入 world/entity snapshots + sensor mounts；
#   * 调用 V2 Radar / TWS / Optical 模型计算**完整 advisory 结果**；
#   * 输出 advisory_contacts / advisory_observations / channels / radar sphere / exposure /
#     warnings / vm_sensor；
#   * **绝不写 TrackTable / V15 state**（无 core/state 依赖，无写入 API）；
#   * `compare(legacy_tracks)` 只读比较 V2 advisory 与 V15 legacy 的 level/identity/距离/方位差异。
#
# 当前覆盖（R5.2/R5.3 shadow 子集）：
#   harmattan YW-R9 球形雷达 + TWS 六态、MS-OT2 VIS、CH-IR2 IR；
#   无真实姿态 → 使用显式默认姿态并标注（ATTITUDE NOT MODELED）；
#   IFF/ELINT/EW 不在本次 shadow 范围（identity 恒 unknown，不判敌）。
#
# 模式：`mode="shadow"`，`authoritative=false`，`writes_track_table=false`，`writes_v15=false`。
# 单位：km / km/s / s；角度 deg；RCS m²；JSON 可序列化；确定性（无随机源）。
# ═══════════════════════════════════════════════════════════════════

const Types := preload("res://framework/sim/sensor_types.gd")
const RadarModel := preload("res://framework/sim/radar.gd")
const TwsModel := preload("res://framework/sim/tws.gd")
const OpticalModel := preload("res://framework/sim/optical.gd")

const SCHEMA_VM := "sensor_shadow.v1"
const SCHEMA_OBS := "sensor_observation.v1"
const SCHEMA_CONTACT := "advisory_contact.v1"
const SCHEMA_COMPARE := "sensor_shadow_compare.v1"
const MODE := "shadow"
const SHADOW_MODE_NOTE := "SHADOW MODE: advisory only；不写 TrackTable/V15（Writes: track_table=false v15=false）"
const ATTITUDE_DEFAULT_NOTE := "ATTITUDE NOT MODELED: 使用显式默认姿态 quat=[0,0,0,1]；光学视轴默认 = 本舰→目标 LOS（shadow 标注，非真实姿态）"
const IDENTITY_SCOPE_NOTE := "IDENTITY NOT ASSERTED: shadow 仅覆盖雷达/TWS/VIS/IR；IFF/ELINT 未接入，advisory identity=unknown（不判敌）"
const ACTIVE_TWS_STATES := ["ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const OPTICAL_STATES_DETECTED := ["acquiring", "staring", "locked"]
const LEVEL_LABELS := {0: "UNKNOWN", 1: "BEARING", 2: "POSITION", 3: "CLASSIFIED", 4: "IDENTIFIED"}
const REF_RCS_M2 := 10.0
const STALE_AFTER_S := 30.0

var ready := false
var mode := MODE
var authoritative := false
var writes_track_table := false
var writes_v15 := false

var t := 0.0
var dt_last := 0.0
var observer: Dictionary = {}
var mounts: Array = []
var records: Dictionary = {}
var snapshot: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var events: Array = []
var notes: Array[String] = []

var advisory_contacts: Array = []
var advisory_observations: Array = []
var radar_sphere: Dictionary = {}
var exposure_state: Dictionary = {}
var channels_cache: Array = []
var optical_summary_cache: Dictionary = {}
var step_count := 0

var _tws = null
var _optical = null
var _obs_seq := 0
var _last_compare: Dictionary = {}
var _last_radar_scan: Dictionary = {}
var _step_events: Array = []
var _config: Dictionary = {}
var _level_tolerance := 0
var _range_tolerance_km := 5.0


# ═══════════════════════════════════════════════════════════════════
# 0. 默认输入（harmattan + YW-R9 / MS-OT2 / CH-IR2）
# ═══════════════════════════════════════════════════════════════════

static func default_observer(observer_id := "harmattan") -> Dictionary:
	return {
		"id": observer_id,
		"pos_km": [0.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0],
		"attitude_quat": [0.0, 0.0, 0.0, 1.0],
		"attitude_source": "default_not_modeled",
		"angular_rate_dps": [0.0, 0.0, 0.0],
		"maneuver_g": 0.0,
		"mast_deployed": true,
		"emcon": false,
		"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0},
	}


static func default_mounts(observer_id := "harmattan") -> Array:
	return [
		{
			"mount_id": "%s/YW-R9" % observer_id, "ship_id": observer_id,
			"model": "YW-R9", "kind": "search_radar", "enabled": true,
			"destroyed": false, "mast_dependent": true,
			"notes": "球形搜索雷达；shadow 只读，不写 V15 sensor_on",
		},
		{
			"mount_id": "%s/MS-OT2" % observer_id, "ship_id": observer_id,
			"model": "MS-OT2", "kind": "optical", "enabled": true,
			"destroyed": false, "mast_dependent": false,
			"notes": "可见光凝视；无真实姿态 → 默认 LOS 视轴（shadow 标注）",
		},
		{
			"mount_id": "%s/CH-IR2" % observer_id, "ship_id": observer_id,
			"model": "CH-IR2", "kind": "ir", "enabled": true,
			"destroyed": false, "mast_dependent": false,
			"notes": "被动红外阵列；shadow 只读",
		},
	]


## 构造测试目标行（V2 world_snapshot targets 契约；km / km/s / 角度 deg）。
static func make_target(target_id: String, range_km: float, bearing_deg: float,
		opts := {}) -> Dictionary:
	var b := deg_to_rad(bearing_deg)
	var pos := Vector3(sin(b) * range_km, cos(b) * range_km, 0.0)
	var out: Dictionary = {
		"id": target_id,
		"entity_id": String(opts.get("entity_id", target_id)),
		"batch": String(opts.get("batch", target_id)),
		"name": String(opts.get("name", target_id)),
		"pos_km": [pos.x, pos.y, pos.z],
		"vel_kmps": [0.0, 0.0, 0.0],
		"rcs_m2": float(opts.get("rcs_m2", REF_RCS_M2)),
		"temp_k": float(opts.get("temp_k", 300.0)),
		"area_m2": float(opts.get("area_m2", 1000.0)),
		"illum": float(opts.get("illum", 1.0)),
		"classification": (opts.get("classification", {}) as Dictionary) if opts.get("classification") is Dictionary else {},
		"transponder": String(opts.get("transponder", "off")),
		"iff_code": String(opts.get("iff_code", "")),
		"faction": String(opts.get("faction", "unknown")),
		"emissions": (opts.get("emissions", []) as Array) if opts.get("emissions") is Array else [],
	}
	return out


## 构造 world_snapshot（V2 传感器模型输入；只读）。
static func make_snapshot(t_s: float, observer_row: Dictionary, targets: Array,
		env := {}) -> Dictionary:
	var obs := observer_row.duplicate(true)
	return {
		"t": t_s,
		"observer": obs,
		"targets": targets.duplicate(true),
		"sun_illum": float(env.get("sun_illum", 1.0)),
		"jamming": float(env.get("jamming", 0.0)),
		"shadow": bool(env.get("shadow", false)),
		"los": bool(env.get("los", true)),
	}


# ═══════════════════════════════════════════════════════════════════
# 1. 初始化
# ═══════════════════════════════════════════════════════════════════

func setup(config := {}) -> bool:
	reset()
	_config = config.duplicate(true) if config is Dictionary else {}
	var observer_id := String(_config.get("observer_id", "harmattan"))
	var base_obs := default_observer(observer_id)
	if _config.get("observer") is Dictionary:
		for k in (_config.get("observer") as Dictionary).keys():
			base_obs[String(k)] = (_config.get("observer") as Dictionary)[k]
	observer = base_obs
	_level_tolerance = int(_config.get("level_tolerance", 0))
	_range_tolerance_km = float(_config.get("range_tolerance_km", 5.0))
	t = float(_config.get("t", 0.0))
	mounts = []
	var raw_mounts: Array = _config.get("mounts", []) if _config.get("mounts") is Array else []
	if raw_mounts.is_empty():
		mounts = default_mounts(observer_id)
	else:
		for raw in raw_mounts:
			if raw is Dictionary:
				mounts.append((raw as Dictionary).duplicate(true))
	if mounts.is_empty():
		errors.append("no sensor mounts")
		ready = false
		return false
	_build_models()
	if not errors.is_empty():
		ready = false
		return false
	# 初始 snapshot：config.snapshot 优先，否则用 targets 构造
	if _config.get("snapshot") is Dictionary and not (_config.get("snapshot") as Dictionary).is_empty():
		set_snapshot(_config.get("snapshot") as Dictionary)
	else:
		var targets: Array = _config.get("targets", []) if _config.get("targets") is Array else []
		snapshot = make_snapshot(t, observer, targets,
			{"sun_illum": float(_config.get("sun_illum", 1.0)),
			 "jamming": float(_config.get("jamming", 0.0)),
			 "shadow": bool(_config.get("shadow", false)),
			 "los": bool(_config.get("los", true))})
		_normalize_snapshot()
	# 初始光学/IR 通道
	var chans: Array = _config.get("optical_channels", []) if _config.get("optical_channels") is Array else []
	for raw_ch in chans:
		if raw_ch is Dictionary:
			start_channel(String((raw_ch as Dictionary).get("kind", "optical")),
				String((raw_ch as Dictionary).get("target_id", "")))
	ready = true
	_rebuild()
	_build_warnings()
	notes = _shadow_notes()
	return true


func reset() -> void:
	ready = false
	t = 0.0
	dt_last = 0.0
	observer = {}
	mounts = []
	records = {}
	snapshot = {}
	errors.clear()
	warnings.clear()
	events.clear()
	notes.clear()
	advisory_contacts = []
	advisory_observations = []
	radar_sphere = {}
	exposure_state = {}
	channels_cache = []
	optical_summary_cache = {}
	step_count = 0
	_tws = null
	_optical = null
	_obs_seq = 0
	_last_compare = {}
	_last_radar_scan = {}
	_step_events = []
	_config = {}
	_level_tolerance = 0
	_range_tolerance_km = 5.0


func _build_models() -> void:
	records.clear()
	var radar_mount := _mount_by_kind("search_radar")
	var optical_mount := _mount_by_kind("optical")
	var ir_mount := _mount_by_kind("ir")
	if radar_mount.is_empty():
		errors.append("缺少 search_radar 挂载（YW-R9）")
	if optical_mount.is_empty():
		errors.append("缺少 optical 挂载（MS-OT2）")
	if ir_mount.is_empty():
		errors.append("缺少 ir 挂载（CH-IR2）")
	if not errors.is_empty():
		return
	var radar_rec = Types.record(String(radar_mount.get("model", "YW-R9")))
	var optical_rec = Types.record(String(optical_mount.get("model", "MS-OT2")))
	var ir_rec = Types.record(String(ir_mount.get("model", "CH-IR2")))
	if radar_rec == null or float(radar_rec.range_km) <= 0.0:
		errors.append("YW-R9 型号记录无效")
		return
	if optical_rec == null or float(optical_rec.range_km) <= 0.0:
		errors.append("MS-OT2 型号记录无效")
		return
	if ir_rec == null or float(ir_rec.range_km) <= 0.0:
		errors.append("CH-IR2 型号记录无效")
		return
	records["radar"] = radar_rec
	records["optical"] = optical_rec
	records["ir"] = ir_rec
	var cap := maxi(1, int(radar_rec.track_capacity))
	if radar_mount.has("max_channels"):
		cap = maxi(1, int(radar_mount.get("max_channels", cap)))
	_tws = TwsModel.new(radar_rec, {"id": String(radar_mount.get("model", "YW-R9")),
		"max_channels": cap, "enabled": true})
	_optical = OpticalModel.new({"optical": optical_rec, "ir": ir_rec, "lost_hold_s": 8.0})


func _mount_by_kind(kind: String) -> Dictionary:
	for raw in mounts:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			return raw
	return {}


func _mount_by_id(mount_id: String) -> Dictionary:
	for raw in mounts:
		if raw is Dictionary and String((raw as Dictionary).get("mount_id", "")) == mount_id:
			return raw
	return {}


func _mount_id_for_kind(kind: String) -> String:
	var m := _mount_by_kind(kind)
	return String(m.get("mount_id", ""))


func _mount_enabled(kind: String) -> bool:
	var m := _mount_by_kind(kind)
	if m.is_empty() or bool(m.get("destroyed", false)):
		return false
	return bool(m.get("enabled", false))


func _damage_ok() -> bool:
	var dmg: Dictionary = observer.get("damage", {}) if observer.get("damage") is Dictionary else {}
	return float(dmg.get("sensors", 1.0)) >= 0.5


func is_radar_enabled() -> bool:
	var m := _mount_by_kind("search_radar")
	if m.is_empty() or bool(m.get("destroyed", false)) or not bool(m.get("enabled", false)):
		return false
	if bool(observer.get("emcon", false)):
		return false
	if bool(m.get("mast_dependent", true)) and not bool(observer.get("mast_deployed", true)):
		return false
	return _damage_ok()


func _optical_enabled(kind: String) -> bool:
	if not _mount_enabled(kind) or not _damage_ok():
		return false
	var m := _mount_by_kind(kind)
	if bool(m.get("mast_dependent", false)) and not bool(observer.get("mast_deployed", true)):
		return false
	return true


func set_mount_enabled(mount_id: String, on: bool) -> Dictionary:
	var m := _mount_by_id(mount_id)
	if m.is_empty():
		return {"ok": false, "reason": "unknown_mount", "mount_id": mount_id,
			"shadow": true, "writes_v15": false}
	m["enabled"] = bool(on)
	# shadow：只改自身挂载状态，不写 V15 sensor_on / EMCON
	if String(m.get("kind", "")) == "optical":
		if not bool(on):
			stop_channel("optical")
	if String(m.get("kind", "")) == "ir":
		if not bool(on):
			stop_channel("ir")
	_rebuild()
	_build_warnings()
	return {"ok": true, "mount_id": mount_id, "enabled": bool(on),
		"shadow": true, "writes_v15": false}


func start_channel(kind: String, target_id: String, opts := {}) -> Dictionary:
	if kind != "optical" and kind != "ir":
		return {"ok": false, "reason": "unknown_kind", "kind": kind}
	if target_id == "":
		return {"ok": false, "reason": "target_required"}
	if not _optical_enabled(kind):
		return {"ok": false, "reason": "mount_disabled_or_damaged", "kind": kind}
	var res: Dictionary = _optical.start(kind, target_id, opts if opts is Dictionary else {})
	_resync_channel_cache()
	return {"ok": bool(res.get("ok", false)), "reason": String(res.get("reason", "")),
		"kind": kind, "target_id": target_id, "shadow": true, "writes_v15": false}


func stop_channel(kind: String, target_id := "") -> void:
	if _optical != null:
		_optical.stop(kind, target_id)
	_resync_channel_cache()


## 从当前 OpticalModel 重新生成 VIS/IR 通道缓存（保留 TWS 通道）。
func _resync_channel_cache() -> void:
	var kept: Array = []
	for raw in channels_cache:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var k := String(ch.get("channel", ch.get("kind", "")))
		if k != "optical" and k != "ir":
			kept.append(ch.duplicate(true))
	if _optical != null:
		var opt_export: Dictionary = _optical.to_dict()
		for raw_opt in (opt_export.get("channels", []) as Array):
			if not (raw_opt is Dictionary):
				continue
			var oc: Dictionary = (raw_opt as Dictionary).duplicate(true)
			var kind := String(oc.get("channel", "optical"))
			oc["mount_id"] = _mount_id_for_kind(kind)
			var rec = records.get(kind, null)
			oc["sensor_model"] = String(rec.model) if rec != null else ""
			oc["shadow"] = true
			kept.append(oc)
		optical_summary_cache = {
			"by_status": (opt_export.get("by_status", {}) as Dictionary).duplicate(true),
			"channels": (opt_export.get("channels", []) as Array).duplicate(true),
			"enabled": bool(opt_export.get("enabled", false)),
			"attitude_source": String(observer.get("attitude_source", "default_not_modeled")),
		}
	channels_cache = kept


func set_observer(observer_row: Dictionary) -> void:
	for k in observer_row.keys():
		observer[String(k)] = observer_row[k]
	_rebuild()
	_build_warnings()


func set_snapshot(snap: Dictionary) -> void:
	snapshot = snap.duplicate(true)
	_normalize_snapshot()


func set_snapshot_targets(targets: Array) -> void:
	var snap := snapshot.duplicate(true)
	snap["targets"] = targets.duplicate(true)
	set_snapshot(snap)


func _normalize_snapshot() -> void:
	if not (snapshot.get("targets") is Array):
		snapshot["targets"] = []
	# observer：snapshot 缺省时用 authority observer
	var snap_obs = snapshot.get("observer", null)
	if not (snap_obs is Dictionary):
		snap_obs = {}
	var obs: Dictionary = (snap_obs as Dictionary).duplicate(true)
	if not obs.has("pos_km"):
		obs["pos_km"] = (observer.get("pos_km", [0.0, 0.0, 0.0]) as Array).duplicate()
	var pos := Types.to_vec3(obs.get("pos_km", [0.0, 0.0, 0.0]))
	obs["pos_km"] = [pos.x, pos.y, pos.z]
	if not obs.has("v_kmps"):
		obs["v_kmps"] = (observer.get("vel_kmps", [0.0, 0.0, 0.0]) as Array).duplicate()
	if not obs.has("id"):
		obs["id"] = String(observer.get("id", "harmattan"))
	snapshot["observer"] = obs
	var clean: Array = []
	var seen: Dictionary = {}
	for raw in (snapshot.get("targets", []) as Array):
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = (raw as Dictionary).duplicate(true)
		var tid := String(tr.get("id", tr.get("entity_id", tr.get("track_id", ""))))
		if tid == "" or seen.has(tid):
			continue
		var pos_v := Types.target_pos_km(tr)
		if pos_v.length() < 1.0e-6 and not (tr.has("pos_km") or tr.has("pos") or tr.has("position") or tr.has("r")):
			continue
		seen[tid] = true
		tr["id"] = tid
		if not tr.has("entity_id"):
			tr["entity_id"] = tid
		if not tr.has("batch"):
			tr["batch"] = tid
		if not tr.has("rcs_m2"):
			tr["rcs_m2"] = REF_RCS_M2
		if not tr.has("illum"):
			tr["illum"] = 1.0
		if not tr.has("temp_k"):
			tr["temp_k"] = 300.0
		if not tr.has("area_m2"):
			tr["area_m2"] = 1000.0
		if not tr.has("classification"):
			tr["classification"] = {}
		tr["pos_km"] = [pos_v.x, pos_v.y, pos_v.z]
		clean.append(tr)
	snapshot["targets"] = clean
	snapshot["t"] = float(snapshot.get("t", t))
	if not snapshot.has("sun_illum"):
		snapshot["sun_illum"] = 1.0
	if not snapshot.has("jamming"):
		snapshot["jamming"] = 0.0
	if not snapshot.has("los"):
		snapshot["los"] = true
	if not snapshot.has("shadow"):
		snapshot["shadow"] = false


# ═══════════════════════════════════════════════════════════════════
# 2. step：调用 V2 模型（shadow；绝不写 TrackTable/V15）
# ═══════════════════════════════════════════════════════════════════

func step(dt: float, snap := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	if snap is Dictionary and not (snap as Dictionary).is_empty():
		set_snapshot(snap)
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	snapshot["t"] = t
	_normalize_snapshot()
	_tws.set_enabled(is_radar_enabled())
	# 光学/IR：挂载关闭则停掉对应通道（shadow 自身状态；不改 V15）
	if not _optical_enabled("optical"):
		_optical.stop("optical")
	if not _optical_enabled("ir"):
		_optical.stop("ir")
	_optical.set_enabled(_optical_enabled("optical") or _optical_enabled("ir"))
	_step_events = []
	var snap_for_model: Dictionary = snapshot.duplicate(true)
	var tws_out: Dictionary = _tws.step(d, snap_for_model)
	_step_events.append_array((tws_out.get("events", []) as Array).duplicate(true))
	var opt_out: Dictionary = _optical.step(d, snap_for_model)
	_step_events.append_array((opt_out.get("events", []) as Array).duplicate(true))
	_last_radar_scan = _tws.radar.last_scan.duplicate(true) if _tws.radar != null else {}
	_build_models_view(tws_out, opt_out)
	_build_observations(tws_out, opt_out)
	_build_advisory_contacts()
	_build_warnings()
	_rebuild()
	return vm_sensor()


func _build_models_view(tws_out: Dictionary, opt_out: Dictionary) -> void:
	var radar_rec = records.get("radar", null)
	var obs_pos := Types.observer_pos_km(snapshot)
	var jamming := Types.jamming_of(snapshot)
	var active := is_radar_enabled()
	if radar_rec != null:
		var sph: Dictionary = RadarModel.sphere_for(radar_rec, obs_pos, REF_RCS_M2, jamming)
		var seconds_on := 0.0
		var scan_index := 0
		if _tws != null and _tws.radar != null:
			seconds_on = float(_tws.radar.seconds_on)
			scan_index = int(_tws.radar.scan_index)
		var in_sphere := 0
		var total := 0
		var eff := float(sph.get("effective_radius_km", 0.0))
		for raw in (snapshot.get("targets", []) as Array):
			if not (raw is Dictionary):
				continue
			var tr: Dictionary = raw
			total += 1
			var rng := obs_pos.distance_to(Types.target_pos_km(tr))
			if rng <= eff + 1.0e-9:
				in_sphere += 1
		sph["active"] = active
		sph["scan_index"] = scan_index
		sph["seconds_on"] = seconds_on
		sph["targets_total"] = total
		sph["targets_in_sphere"] = in_sphere
		sph["no_sector"] = true
		sph["scan_volume"] = "sphere"
		sph["authoritative"] = false
		radar_sphere = sph
		exposure_state = RadarModel.exposure_state(radar_rec, seconds_on, {"on": active})
	else:
		radar_sphere = {}
		exposure_state = {}
	var chans: Array = []
	if _tws != null:
		for raw_ch in _tws.channels_export():
			if raw_ch is Dictionary:
				var ch: Dictionary = (raw_ch as Dictionary).duplicate(true)
				ch["kind"] = "radar.tws"
				ch["channel"] = "radar.tws"
				ch["mount_id"] = _mount_id_for_kind("search_radar")
				ch["sensor_model"] = String(_mount_by_kind("search_radar").get("model", "YW-R9"))
				ch["shadow"] = true
				chans.append(ch)
	var opt_export: Dictionary = _optical.to_dict() if _optical != null else {"channels": [], "by_status": {}}
	for raw_opt in (opt_export.get("channels", []) as Array):
		if raw_opt is Dictionary:
			var oc: Dictionary = (raw_opt as Dictionary).duplicate(true)
			var kind := String(oc.get("channel", "optical"))
			oc["mount_id"] = _mount_id_for_kind(kind)
			oc["sensor_model"] = String((records.get(kind, null) as Object).model) if records.get(kind, null) != null else ""
			oc["shadow"] = true
			chans.append(oc)
	channels_cache = chans
	optical_summary_cache = {
		"by_status": (opt_export.get("by_status", {}) as Dictionary).duplicate(true),
		"channels": (opt_export.get("channels", []) as Array).duplicate(true),
		"enabled": bool(opt_export.get("enabled", false)),
		"attitude_source": String(observer.get("attitude_source", "default_not_modeled")),
	}
	if not _step_events.is_empty():
		for raw_ev in _step_events:
			if raw_ev is Dictionary:
				var ev := (raw_ev as Dictionary).duplicate(true)
				ev["shadow"] = true
				events.append(ev)
	while events.size() > 200:
		events.pop_front()
	_step_events = []


func _make_observation(target_id: String, mount_id: String, sensor_model: String,
		kind: String, detected: bool, level_support: int, bearing_deg: float,
		range_km: float, range_sigma_km: float, quality: float,
		classification: Dictionary, notes: Array, reason := "", pd := 0.0,
		extra := {}) -> Dictionary:
	_obs_seq += 1
	var obs: Dictionary = {
		"schema": SCHEMA_OBS,
		"id": "obs-%05d" % _obs_seq,
		"t": t,
		"observer_id": String(observer.get("id", "harmattan")),
		"mount_id": mount_id,
		"sensor_model": sensor_model,
		"target_id": target_id,
		"kind": kind,
		"detected": detected,
		"pd": pd,
		"level_support": int(level_support),
		"produces_contact": detected and level_support > 0,
		"bearing_deg": bearing_deg,
		"bearing_sigma_deg": float(extra.get("bearing_sigma_deg", 0.0)),
		"range_km": range_km,
		"range_sigma_km": range_sigma_km,
		"range_band": String(extra.get("range_band", "")),
		"quality": quality,
		"classification": classification.duplicate(true),
		"identity": {},
		"iff_status": "",
		"signal": {},
		"notes": notes.duplicate(),
		"reason": reason,
		"expose_self": {},
		"authority": "v2_sensor_shadow",
		"provenance": "v2_sensor_shadow",
		"mode": MODE,
		"authoritative": false,
		"shadow": true,
		"source": "framework/sim/sensor_authority.shadow",
	}
	if extra is Dictionary:
		for k in (extra as Dictionary).keys():
			obs[String(k)] = (extra as Dictionary)[k]
	return obs


func _build_observations(tws_out: Dictionary, opt_out: Dictionary) -> void:
	advisory_observations = []
	# 1) 雷达扫描观测（按扫描节拍；含 detected=false/reason）
	var radar_rec = records.get("radar", null)
	var radar_on := is_radar_enabled()
	if radar_rec != null and bool(tws_out.get("scanned", false)):
		for raw_obs in (_last_radar_scan.get("observations", []) as Array):
			if not (raw_obs is Dictionary):
				continue
			var ro: Dictionary = raw_obs
			var tid := String(ro.get("target_id", ro.get("id", "")))
			if tid == "":
				continue
			var detected := bool(ro.get("detected", false))
			var obs := _make_observation(tid, _mount_id_for_kind("search_radar"),
				String(radar_rec.model), "radar", detected, 2 if detected else 0,
				float(ro.get("bearing_deg", -1.0)), float(ro.get("range_3d_km", -1.0)),
				float(ro.get("range_sigma_km", -1.0)), float(ro.get("pd", 0.0)),
				{}, ["雷达 R_eff=%.0f km" % float(ro.get("effective_radius_km", 0.0))],
				String(ro.get("reason", "")), float(ro.get("pd", 0.0)),
				{"bearing_sigma_deg": float(ro.get("bearing_sigma_deg", 0.0)),
				 "expose_self": (ro.get("exposure", {}) as Dictionary).duplicate(true),
				 "in_sphere": bool(ro.get("in_sphere", false)),
				 "stable_track": bool(ro.get("stable_track", false)),
				 "scan_index": int(ro.get("scan_index", 0))})
			advisory_observations.append(obs)
	# 2) TWS 六态通道观测
	var tws_model := ""
	if not _mount_by_kind("search_radar").is_empty():
		tws_model = String(_mount_by_kind("search_radar").get("model", "YW-R9"))
	for raw_ch in (tws_out.get("channels", []) as Array):
		if not (raw_ch is Dictionary):
			continue
		var ch: Dictionary = raw_ch
		var tid2 := String(ch.get("target_id", ""))
		if tid2 == "":
			continue
		var st := String(ch.get("state", "SEARCH"))
		var active := st in ACTIVE_TWS_STATES
		var obs2 := _make_observation(tid2, _mount_id_for_kind("search_radar"),
			tws_model, "radar.tws", active, 2 if active else 0,
			float(ch.get("bearing_deg", -1.0)), float(ch.get("range_km", -1.0)),
			float(ch.get("range_sigma_km", -1.0)), float(ch.get("quality", 0.0)),
			{}, ["TWS state=%s slot=%d" % [st, int(ch.get("slot", -1))],
				"age=%.1fs" % float(ch.get("age_s", 0.0))],
			"" if active else "channel_state=%s" % st, float(ch.get("pd", 0.0)),
			{"channel_state": st, "lost_lock_count": int(ch.get("lost_lock_count", 0)),
			 "update_rate_hz": float(ch.get("update_rate_hz", 0.0)),
			 "stare_progress": float(ch.get("stare_progress", 0.0)),
			 "fire_control": (ch.get("fire_control", {}) as Dictionary).duplicate(true)})
		advisory_observations.append(obs2)
	# 3) VIS/IR 通道观测
	for raw_opt in (opt_out.get("channels", []) as Array):
		if not (raw_opt is Dictionary):
			continue
		var oc: Dictionary = raw_opt
		var kind := String(oc.get("channel", "optical"))
		var tid3 := String(oc.get("target_id", ""))
		if tid3 == "":
			continue
		var status := String(oc.get("status", "idle"))
		var detected_opt := status in OPTICAL_STATES_DETECTED
		var level := 0
		if detected_opt:
			level = 3 if (kind == "optical" and status == "locked") else 1
		var rec = records.get(kind, null)
		var sensor_model := String(rec.model) if rec != null else ""
		var notes := ["status=%s" % status,
			"progress=%.0f%%" % (float(oc.get("progress", 0.0)) * 100.0),
			"illum=%.2f contrast=%.2f" % [float(oc.get("illum", 1.0)), float(oc.get("contrast", 1.0))]]
		if String(oc.get("reason", "")) != "":
			notes.append("reason=" + String(oc.get("reason", "")))
		var obs3 := _make_observation(tid3, _mount_id_for_kind(kind),
			sensor_model, kind, detected_opt, level, float(oc.get("bearing_deg", -1.0)),
			-1.0, -1.0, float(oc.get("progress", 0.0)),
			(oc.get("classification", {}) as Dictionary) if oc.get("classification") is Dictionary else {},
			notes, String(oc.get("reason", "")), float(oc.get("progress", 0.0)),
			{"status": status, "progress": float(oc.get("progress", 0.0)),
			 "required_s": float(oc.get("required_s", 0.0)),
			 "slant_range_km": float(oc.get("slant_range_km", -1.0)),
			 "range_band": String(oc.get("range_band", "")),
			 "bearing_sigma_deg": float(oc.get("bearing_sigma_deg", 0.0)),
			 "illum": float(oc.get("illum", 1.0)),
			 "contrast": float(oc.get("contrast", 1.0))})
		advisory_observations.append(obs3)


func _build_advisory_contacts() -> void:
	var groups: Dictionary = {}
	for raw in advisory_observations:
		if not (raw is Dictionary):
			continue
		var obs: Dictionary = raw
		if not bool(obs.get("detected", false)):
			continue
		if int(obs.get("level_support", 0)) <= 0:
			continue
		var tid := String(obs.get("target_id", ""))
		if tid == "":
			continue
		if not groups.has(tid):
			groups[tid] = []
		(groups[tid] as Array).append(obs)
	var target_meta: Dictionary = {}
	for raw_t in (snapshot.get("targets", []) as Array):
		if raw_t is Dictionary:
			target_meta[String((raw_t as Dictionary).get("id", ""))] = raw_t
	var out: Array = []
	for tid in groups.keys():
		var obs_list: Array = groups[tid]
		var best_level := 0
		var evidence: Array = []
		var sources: Array = []
		var best_bearing := -1.0
		var best_range := -1.0
		var best_range_sigma := -1.0
		var best_quality := 0.0
		var range_band := ""
		var classification: Dictionary = {}
		var age := 0.0
		var identity := "unknown"
		var meta: Dictionary = target_meta.get(String(tid), {}) if target_meta.get(String(tid)) is Dictionary else {}
		for raw_o in obs_list:
			var o: Dictionary = raw_o
			var lv := int(o.get("level_support", 0))
			var kind := String(o.get("kind", ""))
			if lv > best_level:
				best_level = lv
			if lv > 0:
				evidence.append({"level": lv, "source": String(o.get("sensor_model", "")),
					"kind": kind, "t": float(o.get("t", t))})
			var m := String(o.get("sensor_model", ""))
			if m != "" and not sources.has(m):
				sources.append(m)
			if kind == "radar" or kind == "radar.tws":
				if best_bearing < 0.0:
					best_bearing = float(o.get("bearing_deg", -1.0))
				if best_range < 0.0 and float(o.get("range_km", -1.0)) > 0.0:
					best_range = float(o.get("range_km", -1.0))
					best_range_sigma = float(o.get("range_sigma_km", -1.0))
			elif best_bearing < 0.0:
				best_bearing = float(o.get("bearing_deg", -1.0))
			best_quality = maxf(best_quality, float(o.get("quality", 0.0)))
			if String(o.get("range_band", "")) != "":
				range_band = String(o.get("range_band", ""))
			if kind == "optical" and lv >= 3:
				classification = (o.get("classification", {}) as Dictionary).duplicate(true)
			age = maxf(age, float(o.get("age_s", 0.0)))
		if best_level <= 0:
			continue
		var batch := String(meta.get("batch", tid))
		out.append({
			"schema": SCHEMA_CONTACT,
			"id": String(tid),
			"track_id": String(tid),
			"entity_id": String(meta.get("entity_id", tid)),
			"batch": batch,
			"name": String(meta.get("name", tid)),
			"level": int(best_level),
			"level_label": String(LEVEL_LABELS.get(best_level, "L%d" % best_level)),
			"identity": identity,
			"identity_evidence": [],
			"iff_status": "",
			"classification": classification.duplicate(true),
			"signal": {},
			"bearing_deg": best_bearing,
			"range_km": best_range,
			"range_sigma_km": best_range_sigma,
			"range_band": range_band,
			"quality": best_quality,
			"age_s": age,
			"stale": age > STALE_AFTER_S,
			"sources": sources.duplicate(),
			"level_evidence": evidence.duplicate(true),
			"phantom": false,
			"spoof_flags": [],
			"threat": "none",
			"off": false,
			"occluded": false,
			"mode": MODE,
			"authoritative": false,
			"provenance": "v2_sensor_shadow",
			"source": "framework/sim/sensor_authority.shadow",
			"identity_scope": "shadow_no_iff_elint",
		})
	out.sort_custom(func(a, b): return String(a.get("batch", "")) < String(b.get("batch", "")))
	advisory_contacts = out


func _build_warnings() -> void:
	var w: Array[String] = []
	w.append(SHADOW_MODE_NOTE)
	if String(observer.get("attitude_source", "default_not_modeled")) == "default_not_modeled":
		w.append(ATTITUDE_DEFAULT_NOTE)
	w.append(IDENTITY_SCOPE_NOTE)
	var radar_mount := _mount_by_kind("search_radar")
	if not _damage_ok():
		w.append("DAMAGE: sensors integrity < 0.5 → 所有传感器 shadow 结果降级（V15 未改）")
	if bool(observer.get("emcon", false)):
		w.append("EMCON: 主动雷达/TWS shadow 未运行（shadow 挂载状态，不改 V15 emcon）")
	if bool(radar_mount.get("mast_dependent", true)) and not bool(observer.get("mast_deployed", true)):
		w.append("MAST: 桅杆收起 → 主动雷达/TWS shadow 未运行")
	for raw in mounts:
		if not (raw is Dictionary):
			continue
		var m: Dictionary = raw
		if bool(m.get("destroyed", false)):
			w.append("MOUNT DESTROYED: %s（shadow 跳过）" % String(m.get("mount_id", "")))
		elif not bool(m.get("enabled", true)):
			w.append("MOUNT DISABLED: %s（shadow 跳过；V15 未改）" % String(m.get("mount_id", "")))
	var outside := 0
	if not radar_sphere.is_empty() and bool(radar_sphere.get("active", false)):
		var eff := float(radar_sphere.get("effective_radius_km", 0.0))
		var obs_pos := Types.observer_pos_km(snapshot)
		for raw_t in (snapshot.get("targets", []) as Array):
			if raw_t is Dictionary:
				if obs_pos.distance_to(Types.target_pos_km(raw_t)) > eff + 1.0e-9:
					outside += 1
		if outside > 0:
			w.append("RADAR: %d 个目标在 R_eff=%.0f km 球外（未探测）" % [
				outside, eff])
	if _tws != null and _tws.radar != null:
		var scan_index := int(_tws.radar.scan_index)
		if scan_index <= 0:
			w.append("RADAR: 尚未完成首次扫描（shadow 等待 scan_index>0）")
	if _last_compare.is_empty():
		w.append("COMPARE: 尚未调用 compare(legacy_tracks)（只读对比）")
	warnings = w


func _shadow_notes() -> Array[String]:
	return [
		"SRC: framework/sim/{sensor_types,radar,tws,optical}.gd（只读调用）",
		"MODE: shadow；authoritative=false；writes_track_table=false；writes_v15=false",
		"SCOPE: YW-R9 spherical radar/TWS · MS-OT2 VIS · CH-IR2 IR；IFF/ELINT/EW 未接入",
		"NOTE: 目标来自 V2 world/entity snapshot；站体/实体位置由调用方提供（本模型不写世界）",
	]


func _rebuild() -> void:
	# 只重建只读快照/挂载视图；不写任何外部状态
	notes = _shadow_notes()


# ═══════════════════════════════════════════════════════════════════
# 3. 只读查询 API（channel 窗 / optical summary）
# ═══════════════════════════════════════════════════════════════════

func channels(kind := "") -> Array:
	var out: Array = []
	for raw in channels_cache:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var k := String(ch.get("channel", ch.get("kind", "")))
		if kind != "" and k != kind:
			continue
		out.append(ch.duplicate(true))
	return out


func channel(kind: String, target_id: String) -> Dictionary:
	for raw in channels_cache:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var k := String(ch.get("channel", ch.get("kind", "")))
		if k != kind:
			continue
		if String(ch.get("target_id", "")) == target_id:
			return ch.duplicate(true)
	return {}


func optical_summary() -> Dictionary:
	return optical_summary_cache.duplicate(true)


func has_radar_write() -> bool:
	return writes_track_table or writes_v15


# ═══════════════════════════════════════════════════════════════════
# 4. 只读 compare：V2 advisory vs V15 legacy tracks
# ═══════════════════════════════════════════════════════════════════

func compare(legacy_tracks: Variant) -> Dictionary:
	var legs: Array = []
	if legacy_tracks is Array:
		legs = legacy_tracks.duplicate(true)
	elif legacy_tracks is Dictionary and (legacy_tracks as Dictionary).get("tracks") is Array:
		legs = ((legacy_tracks as Dictionary).get("tracks") as Array).duplicate(true)
	else:
		return {"ok": false, "reason": "invalid_legacy_tracks", "mode": MODE,
			"authoritative": false, "read_only": true}
	var own_id := String(observer.get("id", "harmattan"))
	var leg_map: Dictionary = {}
	var legacy_skipped_own := 0
	for raw in legs:
		if not (raw is Dictionary):
			continue
		var lt: Dictionary = raw
		if bool(lt.get("own", false)) or String(lt.get("id", lt.get("track_id", ""))) == own_id:
			legacy_skipped_own += 1
			continue
		var key := _track_key(lt)
		if key != "":
			leg_map[key] = lt
	var adv_map: Dictionary = {}
	for raw2 in advisory_contacts:
		if raw2 is Dictionary:
			var ac: Dictionary = raw2
			adv_map[_track_key(ac)] = ac
	var diffs: Array = []
	var only_advisory: Array = []
	var only_legacy: Array = []
	var level_equal := 0
	var advisory_higher := 0
	var advisory_lower := 0
	var identity_unscoped := 0
	var range_deltas: Array = []
	var bearing_deltas: Array = []
	var matched_keys: Dictionary = {}
	for key in adv_map.keys():
		var ac: Dictionary = adv_map[key]
		if not leg_map.has(key):
			only_advisory.append(String(key))
			continue
		var lt: Dictionary = leg_map[key]
		matched_keys[key] = true
		var adv_level := int(ac.get("level", 0))
		var leg_level := int(lt.get("level", 0))
		var delta := adv_level - leg_level
		if delta == 0:
			level_equal += 1
		elif delta > 0:
			advisory_higher += 1
		else:
			advisory_lower += 1
		var adv_identity := String(ac.get("identity", "unknown"))
		var leg_identity := _legacy_identity(lt)
		var identity_diff := adv_identity != leg_identity
		if identity_diff:
			identity_unscoped += 1
		var adv_range := float(ac.get("range_km", -1.0))
		var leg_range := float(lt.get("range_km", -1.0))
		var range_delta: Variant = adv_range - leg_range if adv_range > 0.0 and leg_range > 0.0 else null
		if range_delta != null:
			range_deltas.append(float(range_delta))
		var adv_bearing := float(ac.get("bearing_deg", -1.0))
		var leg_bearing := float(lt.get("bearing_deg", -1.0))
		var bearing_delta: Variant = null
		if adv_bearing >= 0.0 and leg_bearing >= 0.0:
			var bd := fposmod(adv_bearing - leg_bearing + 180.0, 360.0) - 180.0
			bearing_delta = bd
			bearing_deltas.append(float(bd))
		diffs.append({
			"key": String(key),
			"batch": String(ac.get("batch", "")),
			"id": String(ac.get("id", "")),
			"advisory_level": adv_level,
			"legacy_level": leg_level,
			"level_delta": delta,
			"level_agree": delta == 0,
			"advisory_identity": adv_identity,
			"legacy_identity": leg_identity,
			"identity_diff": identity_diff,
			"identity_scope": "shadow_no_iff_elint",
			"advisory_range_km": adv_range,
			"legacy_range_km": leg_range,
			"range_delta_km": range_delta,
			"advisory_bearing_deg": adv_bearing,
			"legacy_bearing_deg": leg_bearing,
			"bearing_delta_deg": bearing_delta,
			"reason_guess": _compare_reason(delta, identity_diff),
		})
	for key2 in leg_map.keys():
		if not matched_keys.has(key2):
			only_legacy.append(String(key2))
	var avg_range := 0.0
	if not range_deltas.is_empty():
		var s := 0.0
		for v in range_deltas:
			s += float(v)
		avg_range = s / float(range_deltas.size())
	var avg_bearing := 0.0
	if not bearing_deltas.is_empty():
		var s2 := 0.0
		for v2 in bearing_deltas:
			s2 += float(v2)
		avg_bearing = s2 / float(bearing_deltas.size())
	var level_ok := advisory_higher == 0 and advisory_lower == 0
	var within_tol := true
	for d in diffs:
		if absf(float((d as Dictionary).get("level_delta", 0))) > _level_tolerance:
			within_tol = false
		var rd = (d as Dictionary).get("range_delta_km", null)
		if rd != null and absf(float(rd)) > _range_tolerance_km:
			within_tol = false
	_last_compare = {
		"schema": SCHEMA_COMPARE,
		"ok": true,
		"mode": MODE,
		"authoritative": false,
		"read_only": true,
		"t": t,
		"advisory_count": advisory_contacts.size(),
		"legacy_count": leg_map.size(),
		"legacy_skipped_own": legacy_skipped_own,
		"matched_count": diffs.size(),
		"only_advisory": only_advisory,
		"only_legacy": only_legacy,
		"diffs": diffs,
		"summary": {
			"level_equal": level_equal,
			"level_advisory_higher": advisory_higher,
			"level_advisory_lower": advisory_lower,
			"identity_diff_unscoped": identity_unscoped,
			"only_advisory": only_advisory.size(),
			"only_legacy": only_legacy.size(),
			"avg_range_delta_km": avg_range,
			"avg_bearing_delta_deg": avg_bearing,
			"level_gate_pass": level_ok,
			"within_tolerance": within_tol,
		},
		"scope": {
			"level_tolerance": _level_tolerance,
			"range_tolerance_km": _range_tolerance_km,
			"identity": "shadow 仅雷达/TWS/VIS/IR；IFF/ELINT 未接入，identity 差异不参与门禁",
		},
		"tolerances": {"level": _level_tolerance, "range_km": _range_tolerance_km},
		"warnings": [
			"COMPARE READ-ONLY: legacy_tracks 与 advisory 均未被修改",
			"IDENTITY SCOPE: advisory identity=unknown（不判敌）；identity 差异仅记录，不作为 shadow 失败",
		],
	}
	return _last_compare.duplicate(true)


func _track_key(row: Dictionary) -> String:
	var batch := String(row.get("batch", ""))
	if batch != "":
		return batch
	for k in ["track_id", "id", "entity_id"]:
		var v := String(row.get(k, ""))
		if v != "":
			return v
	return ""


func _legacy_identity(row: Dictionary) -> String:
	var idv = row.get("identity", row.get("side", "unknown"))
	if idv is Dictionary:
		var d: Dictionary = idv
		for k in ["kind", "id", "identity", "label"]:
			if d.has(k) and String(d.get(k, "")) != "":
				return String(d.get(k))
		return "unknown"
	return String(idv) if String(idv) != "" else "unknown"


func _compare_reason(level_delta: int, identity_diff: bool) -> String:
	if level_delta > 0:
		return "advisory_higher: V2 VIS/TWS 证据更高（shadow 上游未融合/未降级）"
	if level_delta < 0:
		return "advisory_lower: V2 缺少 ELINT/IFF/融合老化或目标在球外"
	if identity_diff:
		return "identity_scope: shadow IFF/ELINT 未接入，不判定身份"
	return "agree"


# ═══════════════════════════════════════════════════════════════════
# 5. 只读 view-model / JSON
# ═══════════════════════════════════════════════════════════════════

func vm_sensor() -> Dictionary:
	return {
		"schema": SCHEMA_VM,
		"mode": MODE,
		"authoritative": false,
		"ready": ready,
		"t": t,
		"dt": dt_last,
		"step_count": step_count,
		"observer": _observer_view(),
		"mounts": mounts.duplicate(true),
		"records": {
			"radar": String((records.get("radar", null) as Object).model) if records.get("radar", null) != null else "",
			"optical": String((records.get("optical", null) as Object).model) if records.get("optical", null) != null else "",
			"ir": String((records.get("ir", null) as Object).model) if records.get("ir", null) != null else "",
		},
		"radar": {
			"enabled": is_radar_enabled(),
			"sphere": radar_sphere.duplicate(true),
			"exposure": exposure_state.duplicate(true),
			"scan_index": int(radar_sphere.get("scan_index", 0)),
			"seconds_on": float(radar_sphere.get("seconds_on", 0.0)),
			"mount_enabled": _mount_enabled("search_radar"),
			"emcon": bool(observer.get("emcon", false)),
			"mast_deployed": bool(observer.get("mast_deployed", true)),
		},
		"channels": channels_cache.duplicate(true),
		"optical_summary": optical_summary_cache.duplicate(true),
		"advisory_contacts": advisory_contacts.duplicate(true),
		"advisory_observations": advisory_observations.duplicate(true),
		"warnings": warnings.duplicate(),
		"notes": notes.duplicate(),
		"events": events.duplicate(true),
		"writes": {"track_table": false, "v15": false},
		"shadow": {
			"mode": MODE,
			"authoritative": false,
			"writes_track_table": false,
			"writes_v15": false,
			"attitude_source": String(observer.get("attitude_source", "default_not_modeled")),
			"identity_scope": "shadow_no_iff_elint",
			"last_compare": _last_compare.duplicate(true),
		},
		"counts": {
			"contacts": advisory_contacts.size(),
			"observations": advisory_observations.size(),
			"channels": channels_cache.size(),
			"warnings": warnings.size(),
		},
	}


func _observer_view() -> Dictionary:
	var o := observer.duplicate(true)
	if o.get("pos_km") is Vector3:
		var pv: Vector3 = o.get("pos_km")
		o["pos_km"] = [pv.x, pv.y, pv.z]
	if o.get("vel_kmps") is Vector3:
		var vv: Vector3 = o.get("vel_kmps")
		o["vel_kmps"] = [vv.x, vv.y, vv.z]
	return o


func to_dict() -> Dictionary:
	return vm_sensor()


func summary() -> Dictionary:
	return {
		"mode": MODE,
		"authoritative": false,
		"ready": ready,
		"t": t,
		"observer": String(observer.get("id", "")),
		"mounts": mounts.size(),
		"contacts": advisory_contacts.size(),
		"observations": advisory_observations.size(),
		"channels": channels_cache.size(),
		"warnings": warnings.size(),
		"radar_active": is_radar_enabled(),
		"writes_track_table": false,
		"writes_v15": false,
	}
