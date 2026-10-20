class_name V2InformationWarfare
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 信息作战 · IFF / ELINT / COMINT / EW（R5-INFO-1，shadow）
#
# 统一模型（不接 UI/bridge，不写 TrackTable/V15）：
#   * IFF：Mode 1/2/3/A/C/S/5，询问/应答/加密/缴获码/无应答/故障/超距/超时；
#     只写 identity evidence（L4），不产生位置；**从不输出 hostile**（不明 ≠ 敌意）。
#   * ELINT：被动截获（链路预算/灵敏度/频段/LOS/静默/LPI）、测向、指纹；
#     单站 only signals（produces_contact=false）；多站交叉 only SIGNAL FIX 候选
#     （provisional，不自动成为接触）；ELINT 不写 L4/hostile。
#   * COMINT：与 ELINT 分离；拦截通信元数据/明文（由脚本提供）；加密只给元数据，
#     不自动解码；不产生位置/等级。
#   * EW：noise_jam / deception / chaff / false_target / comms_jam / comms_spoof /
#     emcon / lwr / laser_dazzle，统一为 EWEffect 进单一内部 EventBus（schema event.v1），
#     由本模型结算；提供 environment 效果给 SensorAuthority 读取（不写 world）。
#   * 输出 vm_information_warfare()：iff/elint/comint/ew/effects/events/alerts/summary；
#     mode="shadow"，authoritative=false，writes={track_table:false,v15:false}。
#
# 参考：docs/38 §3.4–3.8、§4.4、§6、§7、§8、§11；docs/11 §3.5–3.7、§6；
#       docs/05 S-05/S-06、E-01/E-02/E-03；sensor_authority.gd 的 shadow 约定。
# 单位：km / km/s / s / deg / MHz / dBm / dB；JSON 安全；无随机源（确定性）。
# ═══════════════════════════════════════════════════════════════════

const Types := preload("res://sim/sensor_types.gd")

const SCHEMA_VM := "information_warfare.v1"
const SCHEMA_IFF := "iff_result.v1"
const SCHEMA_EVENT := "event.v1"
const SCHEMA_SIGNAL := "emitter_signal.v1"
const SCHEMA_COMINT := "comms_observation.v1"
const SCHEMA_EFFECT := "ew_effect.v1"
const SCHEMA_FIX := "signal_fix_candidate.v1"
const SCHEMA_PHANTOM := "phantom_candidate.v1"

const MODE := "shadow"
const LN10 := 2.302585092994046
const IFF_MODES := ["1", "2", "3/A", "C", "S", "5"]
const IFF_RANGE_KM := 2000.0
const IFF_COOLDOWN_S := 2.0
const IFF_TIMEOUT_S := 2.0
const IFF_ELINT_RANGE_KM := 4000.0
const IFF_FIX_AFTER_S := 12.0
const IFF_EXPOSURE_WEIGHT := 0.6
const ELINT_RANGE_KM := 60000.0
const ELINT_SENSITIVITY_DBM := -90.0
const ELINT_NOISE_FLOOR_DBM := -110.0
const ELINT_SNR_THRESHOLD_DB := 10.0
const ELINT_GAIN_RX_DBI := 6.0
const ELINT_LOSS_DB := 3.0
const COMMS_RANGE_KM := 120000.0
const LASER_SCATTER_RANGE_KM := 7700.0
const JAM_FLOOR := 0.30
const JAM_RESIST_DEFAULT := 0.2
const COMMS_LATENCY_MIN_S := 2.0
const COMMS_LATENCY_MAX_S := 40.0
const MAX_EVENTS := 1000
const MAX_ALERTS := 200
const EW_TYPES := ["noise_jam", "deception", "chaff", "false_target", "comms_jam",
	"comms_spoof", "emcon", "lwr", "laser_dazzle", "decoy"]
const SIGNATURE_DB := {
	"YW-R9": {"signature": "search-radar", "class_hint": "R-9 搜索雷达",
		"platform_hint": "UEG 第33舰队 / 搜索雷达", "level_support": 3, "confidence": 0.8},
	"KD-R6": {"signature": "lpi-radar", "class_hint": "红隼低截获雷达",
		"platform_hint": "UEG 第33舰队 / 高端分遣队舰", "level_support": 3, "confidence": 0.7},
	"MS-R4": {"signature": "search-radar", "class_hint": "明视 R-4 雷达",
		"platform_hint": "OCUVF / 联合轨道军舰", "level_support": 3, "confidence": 0.6},
	"SC-R2": {"signature": "civil-radar", "class_hint": "南十字 R-2 雷达",
		"platform_hint": "民用 / 改装船", "level_support": 2, "confidence": 0.5},
	"CH-R0": {"signature": "radio", "class_hint": "车肆无线电",
		"platform_hint": "车肆改装船 / 民用", "level_support": 2, "confidence": 0.4},
	"MK-12": {"signature": "iff-interrogator", "class_hint": "MK-12 询问",
		"platform_hint": "联合轨道军 / 标准件", "level_support": 2, "confidence": 0.5},
	"MS-L2": {"signature": "lasercom-scatter", "class_hint": "激光通信侧向散射",
		"platform_hint": "中继舰 / 指挥链", "level_support": 2, "confidence": 0.2},
}

var ready := false
var mode := MODE
var authoritative := false
var writes_track_table := false
var writes_v15 := false
var t := 0.0

var observer: Dictionary = {}
var targets: Array = []
var stations: Array = []
var iff_cfg: Dictionary = {}
var elint_cfg: Dictionary = {}
var ew_cfg: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []

var iff_results: Array = []
var signals: Array = []
var misses: Array = []
var fix_candidates: Array = []
var comint_events: Array = []
var effects: Array = []
var phantom_candidates: Array = []
var suspicious_commands: Array = []
var events: Array = []
var alerts: Array = []
var advisory_contacts: Array = []

var _targets_by_id: Dictionary = {}
var _advisory_by_target: Dictionary = {}
var _iff_by_target: Dictionary = {}
var _iff_cooldowns: Dictionary = {}
var _comint_seen: Dictionary = {}
var _last_scan_t := -1.0e9
var _emcon: Dictionary = {}
var _seq_event := 0
var _seq_iff := 0
var _seq_signal := 0
var _seq_comint := 0
var _seq_effect := 0
var _seq_phantom := 0


# ═══════════════════════════════════════════════════════════════════
# 0. 默认输入
# ═══════════════════════════════════════════════════════════════════

static func default_observer(observer_id := "harmattan") -> Dictionary:
	return {
		"id": observer_id,
		"pos_km": [0.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0],
		"attitude_quat": [0.0, 0.0, 0.0, 1.0],
		"attitude_source": "default_not_modeled",
		"emcon": false,
		"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0},
	}


static func default_iff_config() -> Dictionary:
	return {
		"enabled": true,
		"model": "MK-12",
		"range_km": IFF_RANGE_KM,
		"cooldown_s": IFF_COOLDOWN_S,
		"timeout_s": IFF_TIMEOUT_S,
		"crypto_epoch": "epoch-1",
		"library": {"1": "M1", "2": "M2", "3/A": "CMP1234", "C": "25000", "S": "A1B2C3", "5": "FRIEND5"},
		"expose_self": {"weight": IFF_EXPOSURE_WEIGHT, "kind": "elint",
			"elint_range_km": IFF_ELINT_RANGE_KM, "fix_after_s": IFF_FIX_AFTER_S},
	}


static func default_elint_config() -> Dictionary:
	return {
		"enabled": true,
		"model": "ELINT",
		"range_km": ELINT_RANGE_KM,
		"comms_range_km": COMMS_RANGE_KM,
		"sensitivity_dbm": ELINT_SENSITIVITY_DBM,
		"noise_floor_dbm": ELINT_NOISE_FLOOR_DBM,
		"snr_threshold_db": ELINT_SNR_THRESHOLD_DB,
		"gain_rx_dbi": ELINT_GAIN_RX_DBI,
		"loss_db": ELINT_LOSS_DB,
		"refresh_s": 1.0,
		"max_time_skew_s": 2.0,
		"fix_gate_km": 300.0,
		"min_baseline_km": 200.0,
		"min_cross_angle_deg": 10.0,
	}


static func default_ew_config() -> Dictionary:
	return {
		"comms_latency_min_s": COMMS_LATENCY_MIN_S,
		"comms_latency_max_s": COMMS_LATENCY_MAX_S,
		"comms_packet_loss_max": 0.9,
		"jam_floor": JAM_FLOOR,
		"jam_resist_default": JAM_RESIST_DEFAULT,
		"emcon_settle_s": 1.5,
		"phantom_lifetime_s": 30.0,
		"laser_lwr_sigma_deg": 10.0,
	}


static func make_target(target_id: String, range_km: float, bearing_deg: float,
		opts := {}) -> Dictionary:
	var b := deg_to_rad(bearing_deg)
	var pos := Vector3(sin(b) * range_km, cos(b) * range_km, 0.0)
	var out: Dictionary = {
		"id": target_id,
		"entity_id": str(opts.get("entity_id", target_id)),
		"name": str(opts.get("name", target_id)),
		"pos_km": [pos.x, pos.y, pos.z],
		"vel_kmps": [0.0, 0.0, 0.0],
		"rcs_m2": float(opts.get("rcs_m2", 10.0)),
		"transponder": str(opts.get("transponder", "off")),
		"registered": bool(opts.get("registered", false)),
		"registry_match": bool(opts.get("registry_match", false)),
		"reply_delay_s": float(opts.get("reply_delay_s", 0.2)),
		"crypto_epoch": str(opts.get("crypto_epoch", "")),
		"iff_codes": (opts.get("iff_codes", {}) as Dictionary).duplicate(true) if opts.get("iff_codes") is Dictionary else {},
		"alt_ft": float(opts.get("alt_ft", 0.0)),
		"emissions": (opts.get("emissions", []) as Array).duplicate(true) if opts.get("emissions") is Array else [],
		"comms": (opts.get("comms", []) as Array).duplicate(true) if opts.get("comms") is Array else [],
	}
	return out


static func normalize_mode(raw: String) -> String:
	var s := raw.strip_edges().to_upper()
	s = s.replace("MODE", "").strip_edges()
	s = s.replace(" ", "")
	if s == "3A" or s == "III" or s == "3":
		return "3/A"
	if s == "3/A":
		return "3/A"
	if s == "M1":
		return "1"
	if s == "M2":
		return "2"
	if s == "M3":
		return "3/A"
	if s == "M4":
		return "5"
	return s


static func log10(x: float) -> float:
	return log(maxf(1.0e-12, x)) / LN10


## 自由空间路径损耗（dB）；freq_mhz，distance_km。
static func fspl_db(freq_mhz: float, distance_km: float) -> float:
	if freq_mhz <= 0.0 or distance_km <= 0.0:
		return 999.0
	var d_m := maxf(1.0, distance_km * 1000.0)
	var lambda_m := 299792458.0 / (freq_mhz * 1.0e6)
	return 20.0 * log10(4.0 * PI * d_m / lambda_m)


static func bearing_between(pos_a: Vector3, pos_b: Vector3) -> float:
	# 0°=北（+y）、90°=东（+x）；与 V15 sensor_model.triangulate 同口径。
	return rad_to_deg(atan2(pos_b.x - pos_a.x, pos_b.y - pos_a.y))


static func range_km_between(pos_a: Vector3, pos_b: Vector3) -> float:
	return pos_a.distance_to(pos_b)


## 噪声干扰因子（docs/11 §6.1 E-01）：0.7 → 0.608 @ resist 0.2；1.0 → 0.30。
static func radar_jam_factor(jamming: float, jamming_resist: float = JAM_RESIST_DEFAULT) -> float:
	var j := clampf(jamming, 0.0, 1.0)
	var r := clampf(jamming_resist, 0.0, 1.0)
	return 1.0 - j * (1.0 - JAM_FLOOR) * (1.0 - r)


## 通信干扰延迟：radio 2→40 s（docs/38 §8.4）。
static func comms_latency_s(jamming: float, base := COMMS_LATENCY_MIN_S) -> float:
	var j := clampf(jamming, 0.0, 1.0)
	return lerpf(base, COMMS_LATENCY_MAX_S, j)


# ═══════════════════════════════════════════════════════════════════
# 1. 初始化
# ═══════════════════════════════════════════════════════════════════

func setup(config := {}) -> bool:
	reset()
	if not (config is Dictionary):
		errors.append("setup config 必须是 Dictionary")
		return false
	var cfg: Dictionary = config
	observer = default_observer(str(cfg.get("observer_id", "harmattan")))
	if cfg.get("observer") is Dictionary:
		for k in (cfg.get("observer") as Dictionary).keys():
			observer[str(k)] = (cfg.get("observer") as Dictionary)[k]
	iff_cfg = default_iff_config()
	if cfg.get("iff") is Dictionary:
		for k in (cfg.get("iff") as Dictionary).keys():
			iff_cfg[str(k)] = (cfg.get("iff") as Dictionary)[k]
	elint_cfg = default_elint_config()
	if cfg.get("elint") is Dictionary:
		for k in (cfg.get("elint") as Dictionary).keys():
			elint_cfg[str(k)] = (cfg.get("elint") as Dictionary)[k]
	ew_cfg = default_ew_config()
	if cfg.get("ew") is Dictionary:
		for k in (cfg.get("ew") as Dictionary).keys():
			ew_cfg[str(k)] = (cfg.get("ew") as Dictionary)[k]
	_emcon = {"active": bool(observer.get("emcon", false)), "since": 0.0,
		"settle_s": float(ew_cfg.get("emcon_settle_s", 1.5))}
	targets = []
	if cfg.get("targets") is Array:
		for raw in (cfg.get("targets") as Array):
			if raw is Dictionary:
				targets.append(_normalize_target(raw))
	_reindex_targets()
	_advisory_reindex(cfg.get("advisory_contacts", []) if cfg.get("advisory_contacts") is Array else [])
	stations = []
	if cfg.get("stations") is Array:
		for raw_st in (cfg.get("stations") as Array):
			if raw_st is Dictionary:
				stations.append(_normalize_station(raw_st))
	if stations.is_empty():
		stations.append(_normalize_station({
			"id": "%s-ELINT" % str(observer.get("id", "observer")),
			"model": "ELINT", "pos_km": observer.get("pos_km", [0.0, 0.0, 0.0]),
			"enabled": true, "sigma_bearing_deg": 1.0,
		}))
	# 校验装配
	if not bool(iff_cfg.get("enabled", true)) and not bool(elint_cfg.get("enabled", true)):
		errors.append("IFF 与 ELINT 均未启用")
	if bool(iff_cfg.get("enabled", true)):
		if not _sensor_damage_ok():
			warnings.append("DAMAGE: sensors<0.5 → IFF/ELINT shadow 降级")
	if float(elint_cfg.get("range_km", 0.0)) <= 0.0:
		errors.append("ELINT range_km 必须 >0")
	ready = errors.is_empty()
	if ready:
		scan_elint(true)
		_scan_comint()
		_rebuild_alerts()
	return ready


func reset() -> void:
	ready = false
	t = 0.0
	observer = {}
	targets = []
	stations = []
	iff_cfg = {}
	elint_cfg = {}
	ew_cfg = {}
	errors.clear()
	warnings.clear()
	iff_results = []
	signals = []
	misses = []
	fix_candidates = []
	comint_events = []
	effects = []
	phantom_candidates = []
	suspicious_commands = []
	events = []
	alerts = []
	advisory_contacts = []
	_targets_by_id = {}
	_advisory_by_target = {}
	_iff_by_target = {}
	_iff_cooldowns = {}
	_comint_seen = {}
	_last_scan_t = -1.0e9
	_emcon = {}
	_seq_event = 0
	_seq_iff = 0
	_seq_signal = 0
	_seq_comint = 0
	_seq_effect = 0
	_seq_phantom = 0


func _sensor_damage_ok() -> bool:
	var dmg: Dictionary = observer.get("damage", {}) if observer.get("damage") is Dictionary else {}
	return float(dmg.get("sensors", 1.0)) >= 0.5


func _comms_damage_ok() -> bool:
	var dmg: Dictionary = observer.get("damage", {}) if observer.get("damage") is Dictionary else {}
	return float(dmg.get("comms", 1.0)) >= 0.5


func _normalize_target(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	var tid := str(out.get("id", out.get("entity_id", "")))
	out["id"] = tid
	if not out.has("entity_id"):
		out["entity_id"] = tid
	if not out.has("name"):
		out["name"] = tid
	if not out.has("pos_km"):
		out["pos_km"] = [0.0, 0.0, 0.0]
	var pos := Types.to_vec3(out.get("pos_km"))
	out["pos_km"] = [pos.x, pos.y, pos.z]
	if not out.has("transponder"):
		out["transponder"] = "off"
	if not out.has("iff_codes") or not (out.get("iff_codes") is Dictionary):
		out["iff_codes"] = {}
	if not out.has("reply_delay_s"):
		out["reply_delay_s"] = 0.2
	if not out.has("crypto_epoch"):
		out["crypto_epoch"] = ""
	if not out.has("registered"):
		out["registered"] = false
	if not out.has("registry_match"):
		out["registry_match"] = false
	if not out.has("emissions") or not (out.get("emissions") is Array):
		out["emissions"] = []
	if not out.has("comms") or not (out.get("comms") is Array):
		out["comms"] = []
	return out


func _normalize_station(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	var pos := Types.to_vec3(out.get("pos_km", [0.0, 0.0, 0.0]))
	out["pos_km"] = [pos.x, pos.y, pos.z]
	if not out.has("id"):
		out["id"] = "station-%d" % (stations.size() + 1)
	if not out.has("model"):
		out["model"] = "ELINT"
	if not out.has("enabled"):
		out["enabled"] = true
	if not out.has("sigma_bearing_deg"):
		out["sigma_bearing_deg"] = 1.0
	return out


func _reindex_targets() -> void:
	_targets_by_id.clear()
	for raw in targets:
		if raw is Dictionary:
			_targets_by_id[str((raw as Dictionary).get("id", ""))] = raw


func set_advisory_contacts(contacts: Array) -> void:
	_advisory_reindex(contacts)


func _advisory_reindex(contacts: Array) -> void:
	advisory_contacts = contacts.duplicate(true)
	_advisory_by_target.clear()
	for raw in advisory_contacts:
		if raw is Dictionary:
			var c: Dictionary = raw
			var keys := [str(c.get("id", "")), str(c.get("track_id", "")),
				str(c.get("entity_id", "")), str(c.get("batch", ""))]
			for k in keys:
				if k != "":
					_advisory_by_target[k] = c


func target(target_id: String) -> Dictionary:
	return _targets_by_id.get(target_id, {}) if _targets_by_id.has(target_id) else {}


func set_targets(rows: Array) -> void:
	targets = []
	for raw in rows:
		if raw is Dictionary:
			targets.append(_normalize_target(raw))
	_reindex_targets()


# ═══════════════════════════════════════════════════════════════════
# 2. step / 事件 / alert
# ═══════════════════════════════════════════════════════════════════

func step(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var d := maxf(0.0, float(dt))
	t += d
	_expire_effects()
	var refresh := float(elint_cfg.get("refresh_s", 1.0))
	if t - _last_scan_t >= refresh - 1.0e-9:
		scan_elint(false)
	_scan_comint()
	_rebuild_alerts()
	return vm_information_warfare()


func _expire_effects() -> void:
	var kept: Array = []
	for raw in effects:
		if raw is Dictionary:
			var e: Dictionary = raw
			var t_end := float(e.get("t_end", -1.0))
			if t_end > 0.0 and t >= t_end:
				e["active"] = false
				e["ended_t"] = t_end
				_push_event("ew.effect", str(e.get("target_id", "")), e, "info")
				continue
		kept.append(raw)
	effects = kept
	# phantom 生命周期
	var keep_ph: Array = []
	for raw_p in phantom_candidates:
		if raw_p is Dictionary:
			var p: Dictionary = raw_p
			var life := float(p.get("lifetime_s", 30.0))
			var born := float(p.get("t_start", t))
			p["age_s"] = t - born
			if life > 0.0 and t - born > life:
				p["removed"] = true
				p["removed_reason"] = "lifetime_expired"
				continue
		keep_ph.append(raw_p)
	phantom_candidates = keep_ph


func _push_event(event_type: String, target_id: String, payload: Dictionary,
		severity := "info") -> Dictionary:
	_seq_event += 1
	var ev: Dictionary = {
		"schema": SCHEMA_EVENT,
		"seq": _seq_event,
		"t": t,
		"type": event_type,
		"source": "sim/information_warfare.shadow",
		"entity_id": str(observer.get("id", "observer")),
		"target_id": target_id,
		"severity": severity,
		"payload": payload.duplicate(true),
		"authority": "shadow",
		"consumers": ["core.event_bus", "state.adapter", "hud.log", "replay.recorder"],
		"shadow": true,
	}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return ev


func _alert(kind: String, severity: String, text: String, target_id := "",
		requires_confirmation := false, data := {}) -> void:
	alerts.append({
		"t": t,
		"kind": kind,
		"severity": severity,
		"text": text,
		"target_id": target_id,
		"requires_confirmation": requires_confirmation,
		"data": (data as Dictionary).duplicate(true) if data is Dictionary else {},
		"no_hostile_determination": true,
	})


func events_since(since_t := -1.0, types: Array = []) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary:
			var e: Dictionary = raw
			if since_t >= 0.0 and float(e.get("t", 0.0)) < since_t:
				continue
			if not types.is_empty() and not types.has(str(e.get("type", ""))):
				continue
			out.append(e.duplicate(true))
	return out


# ═══════════════════════════════════════════════════════════════════
# 3. IFF
# ═══════════════════════════════════════════════════════════════════

func _iff_available() -> bool:
	if not bool(iff_cfg.get("enabled", true)):
		return false
	if not _sensor_damage_ok():
		return false
	if bool(_emcon.get("active", false)):
		return false
	return true


func interrogate_iff(target_id: String, modes: Variant = null, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "status": "not_ready", "reason": "not_ready"}
	var target_row := target(target_id)
	if target_row.is_empty():
		return {"ok": false, "status": "unknown_target", "reason": "unknown_target",
			"target_id": target_id}
	if not _iff_available():
		var reason := "mount_disabled"
		if bool(_emcon.get("active", false)):
			reason = "emcon_active"
		elif not _sensor_damage_ok():
			reason = "damage"
		elif not bool(iff_cfg.get("enabled", true)):
			reason = "mount_disabled"
		var blocked := _iff_result(target_id, "blocked", [], {}, 0.0, "unknown", [],
			reason, false)
		_commit_iff(blocked)
		return blocked
	# 模式归一/校验（先校验 API 入参，再判几何/冷却）
	var requested: Array = []
	var raw_modes: Array = []
	if modes == null:
		raw_modes = ["3/A"]
	elif modes is String:
		raw_modes = [modes]
	elif modes is Array:
		raw_modes = (modes as Array)
	for raw_m in raw_modes:
		var m := normalize_mode(str(raw_m))
		if IFF_MODES.has(m) and not requested.has(m):
			requested.append(m)
	if requested.is_empty():
		var inv := _iff_result(target_id, "invalid_mode", [], {}, 0.0, "unknown", [],
			"invalid_mode", false)
		_commit_iff(inv)
		return inv
	var dist := range_km_between(Types.observer_pos_km({"observer": observer}),
		Types.target_pos_km(target_row))
	var range_km := float(iff_cfg.get("range_km", IFF_RANGE_KM))
	if dist > range_km + 1.0e-9:
		var oor := _iff_result(target_id, "out_of_range", [], {}, dist, "unknown", [],
			"out_of_range", false)
		_commit_iff(oor)
		return oor
	if opts is Dictionary and opts.has("los") and not bool((opts as Dictionary).get("los", true)):
		var bol := _iff_result(target_id, "blocked", [], {}, dist, "unknown", [],
			"los_blocked", false)
		_commit_iff(bol)
		return bol
	# 冷却
	var cooldown_until := float(_iff_cooldowns.get(target_id, -1.0))
	if t < cooldown_until:
		var cd := _iff_result(target_id, "cooldown", [], {}, dist, "unknown", [],
			"cooldown_active", false)
		cd["cooldown_remaining_s"] = cooldown_until - t
		_commit_iff(cd)
		return cd
	# 应答机
	var transponder := str(target_row.get("transponder", "off"))
	var reply_delay := float(target_row.get("reply_delay_s", 0.2))
	var timeout := float(iff_cfg.get("timeout_s", IFF_TIMEOUT_S))
	var status := "reply_ok"
	var reply_ok := false
	var crypto_ok := true
	var spoof_flags: Array = []
	var code_out: Dictionary = {}
	var confidence := 0.0
	if transponder == "off":
		status = "no_reply"
	elif transponder == "faulty":
		status = "faulty_transponder"
	elif transponder == "captured":
		status = "captured"
		reply_ok = true
		spoof_flags.append("captured_code")
		confidence = 0.5
	elif reply_delay > timeout:
		status = "timeout"
	else:
		reply_ok = true
	# 加密模式
	var crypto_epoch := str(iff_cfg.get("crypto_epoch", ""))
	var target_epoch := str(target_row.get("crypto_epoch", ""))
	var crypto_mismatch := false
	if requested.has("5"):
		crypto_ok = crypto_epoch != "" and crypto_epoch == target_epoch
		if not crypto_ok:
			crypto_mismatch = true
			var only_crypto := requested.size() == 1
			if only_crypto:
				status = "crypto_mismatch"
				reply_ok = false
			else:
				requested.erase("5")
	# 代码校验
	var expected: Dictionary = iff_cfg.get("library", {})
	if opts is Dictionary and (opts as Dictionary).get("expected_codes") is Dictionary:
		expected = (opts as Dictionary).get("expected_codes") as Dictionary
	var target_codes: Dictionary = target_row.get("iff_codes", {}) if target_row.get("iff_codes") is Dictionary else {}
	if reply_ok and status != "captured":
		var all_match := true
		for m in requested:
			var exp := str(expected.get(m, ""))
			var act := str(target_codes.get(m, target_row.get("iff_code", "")))
			if exp == "" or act != exp:
				all_match = false
			code_out[m] = act
		if not all_match:
			status = "wrong_code"
			reply_ok = false
	# captured 也视为“应答被接受”，但代码可选
	if status == "captured":
		for m in requested:
			code_out[m] = str(target_codes.get(m, ""))
	# 身份：仅 registered + reply_ok 才 friend；其余 unknown；**永不 hostile**
	var registered := bool(target_row.get("registered", false)) or bool(target_row.get("registry_match", false))
	var identity := "unknown"
	var level_support := 0
	var evidence: Array = []
	if status == "reply_ok" and reply_ok and registered and not crypto_mismatch:
		identity = "friend"
		level_support = 4
		confidence = 0.95
		evidence.append({"kind": "iff", "mode": requested[0] if not requested.is_empty() else "3/A",
			"code": code_out, "confidence": confidence, "registered": true,
			"spoof_flags": [], "t": t, "level_support": 4})
	elif spoof_flags.has("captured_code"):
		identity = "unknown"
		confidence = minf(confidence, 0.5)
		evidence.append({"kind": "iff", "mode": requested[0] if not requested.is_empty() else "3/A",
			"code": code_out, "confidence": confidence, "registered": registered,
			"spoof_flags": spoof_flags.duplicate(), "t": t, "level_support": 0})
	elif reply_ok and status == "reply_ok":
		# 应答正确但未注册：不给 L4，不判敌
		identity = "unknown"
		confidence = 0.4
		evidence.append({"kind": "iff", "mode": requested[0] if not requested.is_empty() else "3/A",
			"code": code_out, "confidence": confidence, "registered": false,
			"spoof_flags": [], "t": t, "level_support": 0})
	var reason := status
	var result := _iff_result(target_id, status, requested, code_out, dist, identity, evidence,
		reason, reply_ok)
	result["reply"] = {
		"received": reply_ok,
		"modes": requested.duplicate(),
		"codes": code_out.duplicate(true),
		"height_ft": float(target_row.get("alt_ft", 0.0)),
		"crypto_ok": crypto_ok,
		"crypto_epoch": target_epoch,
	}
	result["crypto_ok"] = crypto_ok
	result["registered"] = registered
	result["confidence"] = confidence
	result["spoof_flags"] = spoof_flags.duplicate()
	result["level_support"] = level_support
	result["iff_status"] = status
	result["warnings"] = _iff_warnings(status, identity, crypto_mismatch, registered)
	result["expose_self"] = {
		"model": str(iff_cfg.get("model", "MK-12")), "type": "iff", "kind": "elint",
		"weight": IFF_EXPOSURE_WEIGHT,
		"elint_range_km": IFF_ELINT_RANGE_KM, "fix_after_s": IFF_FIX_AFTER_S,
		"warning": "询问即暴露：ELINT 可截获 4,000 km，12 s 后可定位",
	}
	var adv: Dictionary = _advisory_by_target.get(target_id, {}) if _advisory_by_target.get(target_id) is Dictionary else {}
	result["track_id"] = str(adv.get("track_id", adv.get("id", "")))
	result["batch"] = str(adv.get("batch", ""))
	result["advisory_linked"] = not adv.is_empty()
	_commit_iff(result)
	return result


func _iff_warnings(status: String, identity: String, crypto_mismatch: bool,
		registered: bool) -> Array:
	var out: Array = []
	match status:
		"no_reply":
			out.append("无应答：可能敌军/故障/静默友军/超距/遮挡；**不明 ≠ 敌意**（docs/38 §6.2）")
		"faulty_transponder":
			out.append("应答机故障：技术告警；不判敌（docs/07 谷神-2 / docs/38 §6.2）")
		"wrong_code":
			out.append("代码不匹配：identity=unknown；不得直接 hostile（docs/38 §6.2）")
		"captured":
			out.append("缴获码/复制码：confidence≤0.5、spoof_flags=[captured_code]；不得单独升 L4")
		"crypto_mismatch":
			out.append("Mode 5 密钥/时间失配：unknown；不泄露是否为敌")
		"out_of_range":
			out.append("超出 IFF 2,000 km：无身份证据，不判敌")
		"cooldown":
			out.append("IFF 冷却中：本次不产生新证据")
		_:
			if identity == "friend":
				out.append("正确应答 + 注册库确认：identity evidence 支持 L4（仍不是开火授权）")
			elif registered:
				out.append("应答正确但未注册：unknown；不自动判敌")
			else:
				out.append("应答正确但未注册/未确认：unknown；**不明 ≠ 敌意**")
	if crypto_mismatch:
		out.append("Mode 5 crypto mismatch：需要密钥轮换/时间同步（docs/38 §6.3）")
	return out


func _iff_result(target_id: String, status: String, modes: Array, codes: Dictionary,
		distance_km: float, identity: String, evidence: Array, reason: String,
		reply_ok: bool) -> Dictionary:
	_seq_iff += 1
	return {
		"schema": SCHEMA_IFF,
		"id": "iff-%05d" % _seq_iff,
		"ok": status in ["reply_ok", "captured", "no_reply", "faulty_transponder",
			"wrong_code", "out_of_range", "timeout", "invalid_mode", "blocked", "cooldown",
			"crypto_mismatch"],
		"t": t,
		"observer_id": str(observer.get("id", "observer")),
		"target_id": target_id,
		"status": status,
		"state": "resolved",
		"state_history": [
			{"state": "idle", "t": maxf(0.0, t - 0.01)},
			{"state": "interrogating", "t": maxf(0.0, t - 0.005)},
			{"state": "waiting_reply", "t": maxf(0.0, t - 0.002)},
			{"state": "resolved", "t": t, "status": status},
			{"state": "cooldown", "t": t},
		],
		"modes_requested": modes.duplicate(),
		"modes_replied": modes.duplicate() if reply_ok else [],
		"code": codes.duplicate(true),
		"distance_km": distance_km,
		"identity": identity,
		"identity_evidence": evidence.duplicate(true),
		"iff_status": status,
		"confidence": 0.0,
		"spoof_flags": [],
		"level_support": 0,
		"produces_contact": false,
		"produces_position": false,
		"bearing_deg": -1.0,
		"range_km": -1.0,
		"reply": {"received": reply_ok},
		"cooldown_s": float(iff_cfg.get("cooldown_s", IFF_COOLDOWN_S)),
		"reason": reason,
		"warnings": [],
		"never_hostile": true,
		"hostile_allowed": false,
		"mode": MODE,
		"authoritative": false,
		"provenance": "v2_information_warfare.shadow",
	}


func _commit_iff(result: Dictionary) -> void:
	iff_results.append(result)
	_iff_by_target[str(result.get("target_id", ""))] = result
	_iff_cooldowns[str(result.get("target_id", ""))] = t \
		+ float(result.get("cooldown_s", IFF_COOLDOWN_S))
	_push_event("iff.reply", str(result.get("target_id", "")), result,
		"warn" if str(result.get("identity", "unknown")) == "unknown" else "info")
	_push_event("exposure.fix", str(result.get("target_id", "")),
		(result.get("expose_self", {}) as Dictionary), "info")
	if str(result.get("identity", "unknown")) != "friend":
		_alert("iff_unknown", "info",
			"IFF %s：%s；不明 ≠ 敌意（IFF 不产生 hostile）" % [
				str(result.get("status", "")), str(result.get("target_id", ""))],
			str(result.get("target_id", "")), false, {"status": str(result.get("status", ""))})


func iff_state(target_id: String) -> Dictionary:
	return (_iff_by_target.get(target_id, {}) as Dictionary).duplicate(true) if _iff_by_target.has(target_id) else {}


func iff_all() -> Array:
	var out: Array = []
	for raw in iff_results:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


# ═══════════════════════════════════════════════════════════════════
# 4. ELINT（单站信号 / 多站候选）
# ═══════════════════════════════════════════════════════════════════

func _emission_defaults(raw: Dictionary, target_row: Dictionary) -> Dictionary:
	var e: Dictionary = raw.duplicate(true)
	var typ := str(e.get("type", e.get("kind", "radar")))
	e["type"] = typ
	if not e.has("model"):
		e["model"] = str(e.get("signature", typ))
	if not e.has("active"):
		e["active"] = true
	if not e.has("silent"):
		e["silent"] = false
	if not e.has("lpi"):
		e["lpi"] = false
	if not e.has("spoof"):
		e["spoof"] = false
	if not e.has("frequency_mhz") and not e.has("freq_mhz"):
		match typ:
			"iff": e["frequency_mhz"] = 1090.0
			"radio": e["frequency_mhz"] = 300.0
			"lasercom": e["frequency_mhz"] = 300000.0
			_: e["frequency_mhz"] = 9500.0
	e["frequency_mhz"] = float(e.get("frequency_mhz", e.get("freq_mhz", 9500.0)))
	if not e.has("power_dbm"):
		match typ:
			"radar": e["power_dbm"] = 90.0
			"iff": e["power_dbm"] = 60.0
			"radio": e["power_dbm"] = 60.0
			_: e["power_dbm"] = 50.0
	e["power_dbm"] = float(e["power_dbm"])
	if not e.has("gain_tx_dbi"):
		e["gain_tx_dbi"] = 30.0 if typ == "radar" else 6.0
	if not e.has("prf_hz"):
		e["prf_hz"] = 1200.0
	if not e.has("pulse_width_us"):
		e["pulse_width_us"] = 1.2
	if not e.has("scan_period_s"):
		e["scan_period_s"] = 6.0
	if not e.has("source_id"):
		e["source_id"] = str(target_row.get("id", ""))
	if not e.has("signature_name"):
		e["signature_name"] = str(e.get("signature", e.get("model", "")))
	return e


func _is_elint_emitter(em: Dictionary) -> bool:
	var typ := str(em.get("type", ""))
	return typ in ["radar", "iff", "lidar"] or typ.begins_with("radar")


func scan_elint(force := false) -> Array:
	if not ready or not bool(elint_cfg.get("enabled", true)):
		return []
	if not force and t - _last_scan_t < float(elint_cfg.get("refresh_s", 1.0)) - 1.0e-9:
		return []
	if not _sensor_damage_ok():
		return []
	_last_scan_t = t
	var new_signals: Array = []
	var station_ok: Array = []
	for raw_st in stations:
		if raw_st is Dictionary and bool((raw_st as Dictionary).get("enabled", true)):
			station_ok.append(raw_st)
	if station_ok.is_empty():
		warnings.append("ELINT: 无可用接收站")
		return []
	for raw_tr in targets:
		if not (raw_tr is Dictionary):
			continue
		var target_row: Dictionary = raw_tr
		var emissions: Array = target_row.get("emissions", []) if target_row.get("emissions") is Array else []
		for raw_em in emissions:
			if not (raw_em is Dictionary):
				continue
			var em := _emission_defaults(raw_em, target_row)
			if not _is_elint_emitter(em):
				continue
			if bool(em.get("silent", false)) or not bool(em.get("active", true)):
				misses.append({"t": t, "station_id": "", "source_id": str(target_row.get("id", "")),
					"reason": "no_emission", "model": str(em.get("model", ""))})
				continue
			for raw_st2 in station_ok:
				var station: Dictionary = raw_st2
				var sig := _intercept_emission(station, target_row, em)
				if bool(sig.get("detected", false)):
					signals.append(sig)
					new_signals.append(sig)
					_push_event("emitter.signal", str(sig.get("source_id", "")), sig,
						"warn")
				else:
					misses.append({"t": t, "station_id": str(station.get("id", "")),
						"source_id": str(target_row.get("id", "")),
						"reason": str(sig.get("reason", "")), "model": str(em.get("model", ""))})
	return new_signals


func _intercept_emission(station: Dictionary, target_row: Dictionary, em: Dictionary) -> Dictionary:
	_seq_signal += 1
	var station_pos := Types.to_vec3(station.get("pos_km"))
	var target_pos := Types.target_pos_km(target_row)
	var dist := range_km_between(station_pos, target_pos)
	var base_range := float(elint_cfg.get("range_km", ELINT_RANGE_KM))
	var lpi := bool(em.get("lpi", false))
	var eff_range := base_range * (0.5 if lpi else 1.0)
	var freq := float(em.get("frequency_mhz", 9500.0))
	var band := _band_for(freq)
	var power_dbm := float(em.get("power_dbm", 90.0))
	var gain_tx := float(em.get("gain_tx_dbi", 30.0))
	var gain_rx := float(elint_cfg.get("gain_rx_dbi", ELINT_GAIN_RX_DBI))
	var loss := float(elint_cfg.get("loss_db", ELINT_LOSS_DB))
	var fspl := fspl_db(freq, maxf(1.0, dist))
	var p_r := power_dbm + gain_tx + gain_rx - fspl - loss
	var noise_floor := float(elint_cfg.get("noise_floor_dbm", ELINT_NOISE_FLOOR_DBM))
	var snr := p_r - noise_floor
	if lpi:
		snr -= 6.0
	var threshold := float(elint_cfg.get("snr_threshold_db", ELINT_SNR_THRESHOLD_DB))
	var reason := ""
	var detected := true
	if freq < 500.0 or freq > 18000.0:
		detected = false
		reason = "out_of_band"
	elif dist > eff_range:
		detected = false
		reason = "out_of_range"
	elif snr < threshold:
		detected = false
		reason = "weak_signal"
	var bearing := bearing_between(station_pos, target_pos)
	var sigma := float(station.get("sigma_bearing_deg", 1.0))
	var sig_db: Dictionary = {}
	var matched := false
	var signature := ""
	var class_hint := ""
	var confidence := 0.0
	var level_support := 0
	var spoof_flags: Array = []
	if detected:
		var sig_name := str(em.get("signature_name", em.get("model", "")))
		if SIGNATURE_DB.has(sig_name) and not bool(em.get("spoof", false)):
			sig_db = SIGNATURE_DB[sig_name]
			matched = true
			signature = str(sig_db.get("signature", ""))
			class_hint = str(sig_db.get("class_hint", ""))
			confidence = float(sig_db.get("confidence", 0.5))
			level_support = int(sig_db.get("level_support", 3))
		else:
			signature = ""
			class_hint = "未知信号特征"
			confidence = 0.2
			level_support = 1
			if bool(em.get("spoof", false)):
				spoof_flags.append("spoofed_signature")
				confidence = 0.1
				level_support = 0
		if lpi:
			sigma *= 2.0
	return {
		"schema": SCHEMA_SIGNAL,
		"id": "sig-%05d" % _seq_signal,
		"t": t,
		"observer_id": str(station.get("id", observer.get("id", "observer"))),
		"station_id": str(station.get("id", "")),
		"station_pos_km": [station_pos.x, station_pos.y, station_pos.z],
		"mount_id": "%s/ELINT" % str(station.get("id", observer.get("id", "observer"))),
		"source_id": str(target_row.get("id", "")),
		"emitter_model": str(em.get("model", "")),
		"bearing_deg": bearing,
		"bearing_sigma_deg": sigma,
		"range_km": -1.0,
		"distance_km": dist,
		"detected": detected,
		"pd": 1.0 / (1.0 + exp(-(snr - threshold) / 4.0)) if is_finite(snr) else 0.0,
		"freq_mhz": freq,
		"band": band,
		"prf_hz": float(em.get("prf_hz", 1200.0)),
		"pulse_width_us": float(em.get("pulse_width_us", 1.2)),
		"scan_period_s": float(em.get("scan_period_s", 6.0)),
		"power_db": p_r,
		"snr_db": snr,
		"signature": signature,
		"matched": matched,
		"confidence": confidence,
		"class_hint": class_hint,
		"level_support": level_support,
		"lpi": lpi,
		"effective_range_km": eff_range,
		"produces_contact": false,
		"is_contact": false,
		"fix_candidate": false,
		"comms_content": null,
		"spoof_flags": spoof_flags,
		"reason": reason if not detected else "",
		"notes": ["单站 ELINT 只有方位，不产生接触（docs/38 §7.2）"] if detected else [],
		"mode": MODE,
		"authoritative": false,
		"provenance": "v2_information_warfare.shadow",
	}


func _band_for(freq_mhz: float) -> String:
	if freq_mhz < 500.0:
		return "UHF"
	if freq_mhz < 2000.0:
		return "L"
	if freq_mhz < 4000.0:
		return "S"
	if freq_mhz < 8000.0:
		return "C"
	if freq_mhz < 12000.0:
		return "X"
	if freq_mhz < 18000.0:
		return "Ku"
	return "Ka"


func latest_signals() -> Array:
	var latest: Dictionary = {}
	for raw in signals:
		if raw is Dictionary:
			var s: Dictionary = raw
			if not bool(s.get("detected", false)):
				continue
			var key := "%s|%s|%s" % [str(s.get("station_id", "")),
				str(s.get("source_id", "")), str(s.get("freq_mhz", ""))]
			latest[key] = s
	var out: Array = []
	for k in latest.keys():
		out.append(latest[k])
	return out


## 单站信号 → 多站交叉 SIGNAL FIX 候选（纯函数，只读）。
static func triangulate_signals(sig_a: Dictionary, sig_b: Dictionary, opts := {}) -> Dictionary:
	var gate_km := float((opts as Dictionary).get("fix_gate_km", 300.0)) if opts is Dictionary else 300.0
	var max_skew := float((opts as Dictionary).get("max_time_skew_s", 2.0)) if opts is Dictionary else 2.0
	var min_baseline := float((opts as Dictionary).get("min_baseline_km", 200.0)) if opts is Dictionary else 200.0
	var min_angle := float((opts as Dictionary).get("min_cross_angle_deg", 10.0)) if opts is Dictionary else 10.0
	var reasons: Array = []
	if not bool(sig_a.get("detected", false)) or not bool(sig_b.get("detected", false)):
		reasons.append("signal_not_detected")
	var station_a := str(sig_a.get("station_id", ""))
	var station_b := str(sig_b.get("station_id", ""))
	if station_a == "" or station_b == "" or station_a == station_b:
		reasons.append("needs_two_stations")
	if str(sig_a.get("source_id", "")) != str(sig_b.get("source_id", "")):
		reasons.append("source_mismatch")
	if absf(float(sig_a.get("t", 0.0)) - float(sig_b.get("t", 0.0))) > max_skew + 1.0e-9:
		reasons.append("time_skew")
	var fp_a := str(sig_a.get("signature", ""))
	var fp_b := str(sig_b.get("signature", ""))
	if fp_a != "" and fp_b != "" and fp_a != fp_b:
		reasons.append("fingerprint_mismatch")
	var pos_a := Types.to_vec3(sig_a.get("station_pos_km", [0, 0, 0]))
	var pos_b := Types.to_vec3(sig_b.get("station_pos_km", [0, 0, 0]))
	var baseline := range_km_between(pos_a, pos_b)
	if baseline < min_baseline - 1.0e-9:
		reasons.append("baseline_too_short")
	var b1 := deg_to_rad(float(sig_a.get("bearing_deg", 0.0)))
	var b2 := deg_to_rad(float(sig_b.get("bearing_deg", 0.0)))
	var d1 := Vector2(sin(b1), cos(b1))
	var d2 := Vector2(sin(b2), cos(b2))
	var denom := d1.cross(d2)
	var crossing := rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0)))
	if absf(denom) < 1.0e-4:
		reasons.append("parallel_rays")
		crossing = 0.0
	elif crossing < min_angle - 1.0e-9:
		reasons.append("cross_angle_too_small")
	var delta := Vector2(pos_b.x - pos_a.x, pos_b.y - pos_a.y)
	var t1 := 0.0
	var t2 := 0.0
	if absf(denom) >= 1.0e-4:
		t1 = delta.cross(d2) / denom
		t2 = delta.cross(d1) / denom
		if t1 <= 0.0 or t2 <= 0.0:
			if not reasons.has("intersection_behind_station"):
				reasons.append("intersection_behind_station")
	var pos_2d := Vector2(pos_a.x, pos_a.y) + d1 * t1
	var sigma_1 := deg_to_rad(float(sig_a.get("bearing_sigma_deg", 1.0)))
	var sigma_2 := deg_to_rad(float(sig_b.get("bearing_sigma_deg", 1.0)))
	var cross_sigma := 0.0
	if t1 > 0.0 and t2 > 0.0:
		cross_sigma = sqrt(pow(t1 * sigma_1, 2.0) + pow(t2 * sigma_2, 2.0)) \
			/ maxf(0.01, absf(sin(deg_to_rad(crossing))))
		if cross_sigma > gate_km:
			reasons.append("fix_error_exceeds_gate")
	var gates_pass := reasons.is_empty()
	return {
		"schema": SCHEMA_FIX,
		"ok": gates_pass,
		"candidate": gates_pass,
		"provisional": true,
		"is_contact": false,
		"produces_contact": false,
		"requires_confirmation": true,
		"source_id": str(sig_a.get("source_id", "")),
		"station_ids": [station_a, station_b],
		"t": maxf(float(sig_a.get("t", 0.0)), float(sig_b.get("t", 0.0))),
		"pos_km": [pos_2d.x, pos_2d.y, 0.0],
		"range_from_a_km": t1,
		"range_from_b_km": t2,
		"baseline_km": baseline,
		"cross_angle_deg": crossing,
		"sigma_range_km": cross_sigma,
		"covariance": {"pos_sigma_km": cross_sigma, "semi_major_km": cross_sigma * 1.2,
			"semi_minor_km": cross_sigma * 0.8},
		"level_support": 2 if gates_pass else 0,
		"level_cap": "L2_candidate_only",
		"confidence": 0.7 if gates_pass else 0.0,
		"fingerprint": fp_a if fp_a != "" else fp_b,
		"identity": "",
		"fingerprint_matched": fp_a != "" and fp_a == fp_b,
		"gates": {"fix_gate_km": gate_km, "max_time_skew_s": max_skew,
			"min_baseline_km": min_baseline, "min_cross_angle_deg": min_angle},
		"reasons": reasons,
		"warnings": ["SIGNAL FIX 只是候选：不自动成为接触/航迹，需融合/雷达/光学确认（docs/38 §7.2）"],
		"mode": MODE,
		"authoritative": false,
		"provenance": "v2_information_warfare.shadow",
	}


func triangulate_all(opts := {}) -> Array:
	var out: Array = []
	var sigs := latest_signals()
	for i in range(sigs.size()):
		for j in range(i + 1, sigs.size()):
			var a: Dictionary = sigs[i]
			var b: Dictionary = sigs[j]
			var candidate := triangulate_signals(a, b, opts)
			if bool(candidate.get("candidate", false)) and not _candidate_duplicate(out, candidate):
				out.append(candidate)
				fix_candidates.append(candidate)
				_push_event("emitter.signal", str(candidate.get("source_id", "")), candidate,
					"info")
	return out


func _candidate_duplicate(existing: Array, cand: Dictionary) -> bool:
	var key := "%s|%s" % [str(cand.get("source_id", "")), str(cand.get("station_ids", []))]
	for raw in existing:
		if raw is Dictionary:
			var c: Dictionary = raw
			var k := "%s|%s" % [str(c.get("source_id", "")), str(c.get("station_ids", []))]
			if k == key:
				return true
	return false


# ═══════════════════════════════════════════════════════════════════
# 5. COMINT（与 ELINT 分离；加密不解码）
# ═══════════════════════════════════════════════════════════════════

func _all_comms() -> Array:
	var out: Array = []
	for raw in targets:
		if not (raw is Dictionary):
			continue
		var target_row: Dictionary = raw
		for raw_c in (target_row.get("comms", []) as Array):
			if raw_c is Dictionary:
				var c: Dictionary = (raw_c as Dictionary).duplicate(true)
				if not c.has("from"):
					c["from"] = str(target_row.get("id", ""))
				out.append(c)
	return out


func _scan_comint() -> void:
	if not ready or not bool(elint_cfg.get("enabled", true)):
		return
	if not _sensor_damage_ok() or not _comms_damage_ok():
		return
	var found := false
	for raw_c in _all_comms():
		var c: Dictionary = raw_c
		var key := "%s|%s|%s|%s|%s" % [str(c.get("from", "")), str(c.get("to", "")),
			str(c.get("mode", "radio")), str(c.get("encrypted", false)),
			str(c.get("text", ""))]
		if _comint_seen.has(key):
			continue
		_comint_seen[key] = true
		var mode := str(c.get("mode", "radio"))
		var encrypted := bool(c.get("encrypted", false))
		var freq := float(c.get("frequency_mhz", 300.0 if mode == "radio" else 300000.0))
		var range_limit := float(elint_cfg.get("comms_range_km", COMMS_RANGE_KM))
		if mode == "lasercom":
			range_limit = LASER_SCATTER_RANGE_KM
		var station_pos := Types.to_vec3(stations[0].get("pos_km", [0, 0, 0])) if not stations.is_empty() else Vector3.ZERO
		var source_pos := Vector3.ZERO
		var source_known := false
		if _targets_by_id.has(str(c.get("from", ""))):
			source_pos = Types.target_pos_km(_targets_by_id[str(c.get("from", ""))])
			source_known = true
		elif c.get("pos_km") is Array:
			source_pos = Types.to_vec3(c.get("pos_km"))
			source_known = true
		if not source_known:
			continue
		var dist := range_km_between(station_pos, source_pos)
		if dist > range_limit:
			continue
		_seq_comint += 1
		var obs: Dictionary = {
			"schema": SCHEMA_COMINT,
			"id": "comint-%05d" % _seq_comint,
			"t": t,
			"observer_id": str(observer.get("id", "observer")),
			"station_id": str(stations[0].get("id", "")) if not stations.is_empty() else "",
			"from": str(c.get("from", "")),
			"to": str(c.get("to", "")),
			"comms_mode": mode,
			"frequency_mhz": freq,
			"distance_km": dist,
			"range_limit_km": range_limit,
			"detected": true,
			"produces_contact": false,
			"level_support": 0,
			"encrypted": encrypted,
			"decode_attempted": false,
			"comms_content": {
				"text": "" if encrypted else str(c.get("text", "")),
				"mode": mode,
				"encryption": "encrypted" if encrypted else "plaintext",
				"from": str(c.get("from", "")),
				"to": str(c.get("to", "")),
				"confidence": 0.9 if not encrypted else 0.5,
				"metadata_only": encrypted,
			},
			"signature": str(c.get("callsign", "")),
			"notes": ["COMINT：通信内容侦察，不是传感器观测（docs/38 §7.3）"] +
				(["加密：可拦截但不可解码，只给元数据/流量分析"] if encrypted else []),
			"mode": MODE,
			"authoritative": false,
			"provenance": "v2_information_warfare.shadow",
		}
		comint_events.append(obs)
		found = true
		_push_event("comms.link", str(c.get("from", "")), obs, "info")
		if encrypted:
			_alert("comint_encrypted", "info",
				"COMINT 截获加密通信：只给元数据，不自动解码（docs/38 §7.3）",
				str(c.get("from", "")), false, {"encrypted": true})
	if found:
		pass


func _comms_source_pos(c: Dictionary) -> Variant:
	var sid := str(c.get("from", ""))
	if _targets_by_id.has(sid):
		return Types.target_pos_km(_targets_by_id[sid])
	if c.get("pos_km") is Array:
		return Types.to_vec3(c.get("pos_km"))
	return null


# ═══════════════════════════════════════════════════════════════════
# 6. EW（统一 EWEffect / 事件总线 / 结算）
# ═══════════════════════════════════════════════════════════════════

func apply_ew_effect(raw: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	var e: Dictionary = raw.duplicate(true)
	var effect_type := str(e.get("effect", ""))
	if not EW_TYPES.has(effect_type):
		return {"ok": false, "reason": "invalid_effect_type", "effect": effect_type}
	_seq_effect += 1
	var severity := clampf(float(e.get("severity", 0.5)), 0.0, 1.0)
	var duration := float(e.get("duration_s", 30.0))
	var t_end := t + duration if duration > 0.0 else -1.0
	e["schema"] = SCHEMA_EFFECT
	e["id"] = str(e.get("id", "ew-%05d" % _seq_effect))
	e["t_start"] = t
	e["t_end"] = t_end
	e["severity"] = severity
	e["active"] = true
	e["source"] = "sim/information_warfare.shadow"
	e["authority"] = "shadow"
	e["mode"] = MODE
	e["authoritative"] = false
	if not e.has("target_id"):
		e["target_id"] = str(observer.get("id", ""))
	if not e.has("target_kinds"):
		e["target_kinds"] = ["radar"] if effect_type in ["noise_jam", "deception", "chaff",
			"false_target"] else ["comms"] if effect_type in ["comms_jam", "comms_spoof"] else ["optical"]
	if not e.has("visible_to"):
		e["visible_to"] = ["own", "enemy_elint"]
	if not e.has("evidence"):
		e["evidence"] = {"source": "script", "confidence": 0.8}
	effects.append(e)
	_push_event("ew.effect", str(e.get("target_id", "")), e,
		"warn" if severity >= 0.6 else "info")
	_alert("ew_" + effect_type, "warn" if severity >= 0.6 else "info",
		"EW %s：severity=%.2f（统一事件总线；不自动判敌）" % [effect_type, severity],
		str(e.get("target_id", "")), false, {"effect_id": str(e.get("id", ""))})
	return {"ok": true, "effect": e.duplicate(true)}


func inject_noise_jamming(source_id: String, target_id: String, severity: float,
		duration := 60.0) -> Dictionary:
	return apply_ew_effect({"effect": "noise_jam", "source_id": source_id,
		"target_id": target_id, "severity": severity, "duration_s": duration,
		"target_kinds": ["radar"], "params": {"band": "X"}})


func inject_comms_jamming(source_id: String, target_id: String, severity: float,
		duration := 60.0) -> Dictionary:
	return apply_ew_effect({"effect": "comms_jam", "source_id": source_id,
		"target_id": target_id, "severity": severity, "duration_s": duration,
		"target_kinds": ["comms", "radio"], "params": {"latency_s_add": 0.0}})


func inject_deception(source_id: String, target_id: String, severity := 0.7,
		duration := 30.0, phantom_count := 1) -> Dictionary:
	var res := apply_ew_effect({"effect": "deception", "source_id": source_id,
		"target_id": target_id, "severity": severity, "duration_s": duration,
		"target_kinds": ["radar"], "params": {"phantom_count": phantom_count}})
	if bool(res.get("ok", false)):
		_add_phantoms(phantom_count, str((res.get("effect", {}) as Dictionary).get("id", "")))
	return res


func inject_false_target(source_id: String, target_id: String, count := 1,
		duration := 30.0) -> Dictionary:
	var res := apply_ew_effect({"effect": "false_target", "source_id": source_id,
		"target_id": target_id, "severity": 0.6, "duration_s": duration,
		"target_kinds": ["radar"], "params": {"phantom_count": count}})
	if bool(res.get("ok", false)):
		_add_phantoms(count, str((res.get("effect", {}) as Dictionary).get("id", "")))
	return res


func inject_chaff(source_id: String, target_id: String, count := 4,
		duration := 20.0) -> Dictionary:
	var res := apply_ew_effect({"effect": "chaff", "source_id": source_id,
		"target_id": target_id, "severity": 0.5, "duration_s": duration,
		"target_kinds": ["radar"], "params": {"phantom_count": count}})
	if bool(res.get("ok", false)):
		_add_phantoms(count, str((res.get("effect", {}) as Dictionary).get("id", "")))
	return res


func inject_comms_spoof(source_id: String, target_id: String, text: String,
		duration := 30.0) -> Dictionary:
	var res := apply_ew_effect({"effect": "comms_spoof", "source_id": source_id,
		"target_id": target_id, "severity": 0.7, "duration_s": duration,
		"target_kinds": ["comms", "radio"], "params": {"text": text,
			"requires_confirmation": true}})
	if bool(res.get("ok", false)):
		var e: Dictionary = res.get("effect", {})
		_seq_effect += 0
		suspicious_commands.append({
			"id": "cmd-%04d" % suspicious_commands.size(),
			"t": t,
			"source_id": source_id,
			"target_id": target_id,
			"text": text,
			"suspicious": true,
			"requires_confirmation": true,
			"applied": false,
			"reason": "通信欺骗：来源/呼号可疑；不得自动执行",
			"effect_id": str(e.get("id", "")),
			"no_auto_decision": true,
		})
		_alert("comms_spoof", "critical",
			"通信欺骗：可疑命令需玩家/审计确认，不自动执行（docs/38 §8.3/§8.4）",
			target_id, true, {"text": text})
	return res


func inject_laser_dazzle(source_id: String, target_id: String, severity := 0.8,
		duration := 5.0) -> Dictionary:
	return apply_ew_effect({"effect": "laser_dazzle", "source_id": source_id,
		"target_id": target_id, "severity": severity, "duration_s": duration,
		"target_kinds": ["optical", "ir"], "params": {"lwr_only": true}})


func set_emcon(on: bool) -> Dictionary:
	_emcon["active"] = bool(on)
	_emcon["since"] = t
	if bool(on):
		apply_ew_effect({"effect": "emcon", "source_id": str(observer.get("id", "")),
			"target_id": str(observer.get("id", "")), "severity": 1.0,
			"duration_s": -1.0, "target_kinds": ["radar", "iff"],
			"params": {"settle_s": float(ew_cfg.get("emcon_settle_s", 1.5))}})
		_alert("emcon", "info", "EMCON：主动传感器/IFF 关闭；被动 ELINT/COMINT 仍工作（docs/38 §8.4）",
			str(observer.get("id", "")), false, {"passive_ok": true})
	else:
		var kept: Array = []
		for raw in effects:
			if raw is Dictionary and str((raw as Dictionary).get("effect", "")) == "emcon":
				continue
			kept.append(raw)
		effects = kept
		_alert("emcon_off", "info", "EMCON 解除：主动传感器可恢复（切换有 settle 延迟）",
			str(observer.get("id", "")), false, {})
	return {"ok": true, "active": bool(on), "since_t": t, "settle_s": float(ew_cfg.get("emcon_settle_s", 1.5)),
		"settled": t - float(_emcon.get("since", t)) >= float(ew_cfg.get("emcon_settle_s", 1.5)),
		"passive_ok": true, "shadow": true, "writes_v15": false}


func active_effects(target_id := "", kind := "") -> Array:
	var out: Array = []
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if target_id != "" and str(e.get("target_id", "")) != target_id:
			continue
		if kind != "" and not (e.get("target_kinds", []) as Array).has(kind):
			continue
		out.append(e.duplicate(true))
	return out


func _max_severity(effect_type: String, target_id: String, kind: String) -> float:
	var sev := 0.0
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if str(e.get("effect", "")) != effect_type:
			continue
		if target_id != "" and str(e.get("target_id", "")) != target_id:
			continue
		if kind != "" and not (e.get("target_kinds", []) as Array).has(kind):
			continue
		sev = maxf(sev, float(e.get("severity", 0.0)))
	return sev


func radar_effect(base_range_km := 30000.0, jamming_resist := JAM_RESIST_DEFAULT) -> Dictionary:
	var jam := _max_severity("noise_jam", str(observer.get("id", "")), "radar")
	var factor := radar_jam_factor(jam, jamming_resist)
	var floor_range := float(base_range_km) * JAM_FLOOR
	var eff := maxf(floor_range, float(base_range_km) * factor)
	return {
		"jamming": jam,
		"jamming_resist": clampf(jamming_resist, 0.0, 1.0),
		"jam_factor": factor,
		"base_range_km": float(base_range_km),
		"effective_radius_km": eff,
		"floor_radius_km": floor_range,
		"suppressed": jam > 0.0,
		"sources": _effect_sources("noise_jam", "radar"),
		"warning": "噪声干扰：R_eff ×%.3f（下限 30%%；docs/38 §8.2）" % factor if jam > 0.0 else "",
		"mode": MODE, "authoritative": false,
	}


func comms_effect(mode := "radio", base_latency := 4.0, los := true) -> Dictionary:
	var jam := _max_severity("comms_jam", str(observer.get("id", "")), "comms")
	var latency := float(base_latency)
	var packet_loss := 0.0
	var jammed := false
	var laser_immune := false
	if mode == "lasercom":
		laser_immune = true
		if not los:
			return {"mode": mode, "latency_s": base_latency, "packet_loss": 1.0,
				"jammed": false, "laser_immune": true, "los": false,
				"reason": "laser_los_blocked", "sources": [], "mode_shadow": MODE}
	else:
		# docs/38 §8.4：comms_jamming 0/0.5/1 → 2/21/40 s（不把 nominal 4 s 当线性下界）
		latency = comms_latency_s(jam, COMMS_LATENCY_MIN_S)
		packet_loss = clampf(jam * float(ew_cfg.get("comms_packet_loss_max", 0.9)), 0.0, 0.95)
		jammed = jam > 0.0
	return {
		"mode": mode,
		"jamming": jam,
		"nominal_latency_s": float(base_latency),
		"latency_s": latency,
		"packet_loss": packet_loss,
		"jammed": jammed,
		"laser_immune": laser_immune,
		"los": los,
		"sources": _effect_sources("comms_jam", "comms"),
		"warning": "通信干扰：延迟 %.1f s / 丢包 %.0f%%（docs/38 §8.4）" % [latency, packet_loss * 100.0]
			if jammed else "",
		"authoritative": false,
	}


func _effect_sources(effect_type: String, kind: String) -> Array:
	var out: Array = []
	for raw in effects:
		if raw is Dictionary:
			var e: Dictionary = raw
			if str(e.get("effect", "")) == effect_type and (e.get("target_kinds", []) as Array).has(kind):
				out.append(str(e.get("source_id", "")))
	return out


func optical_effects() -> Dictionary:
	var dazzle := _max_severity("laser_dazzle", str(observer.get("id", "")), "optical")
	var lwr := _max_severity("lwr", str(observer.get("id", "")), "optical")
	return {
		"dazzled": dazzle > 0.0,
		"dazzle_severity": dazzle,
		"lwr": lwr > 0.0,
		"lwr_bearing_sigma_deg": float(ew_cfg.get("laser_lwr_sigma_deg", 10.0)),
		"optical_blocked": dazzle >= 0.7,
		"sources": _effect_sources("laser_dazzle", "optical"),
		"note": "LWR 只给告警方位（±10°），不产生接触（docs/38 §8.1）",
		"authoritative": false,
	}


func environment_effects() -> Dictionary:
	return {
		"jamming": _max_severity("noise_jam", str(observer.get("id", "")), "radar"),
		"comms_jamming": _max_severity("comms_jam", str(observer.get("id", "")), "comms"),
		"radar": radar_effect(),
		"comms": comms_effect(),
		"optical": optical_effects(),
		"emcon": bool(_emcon.get("active", false)),
		"source": "information_warfare.shadow",
		"authoritative": false,
	}


func emcon_state() -> Dictionary:
	return {
		"active": bool(_emcon.get("active", false)),
		"since_t": float(_emcon.get("since", 0.0)),
		"settle_s": float(ew_cfg.get("emcon_settle_s", 1.5)),
		"settled": t - float(_emcon.get("since", 0.0)) >= float(ew_cfg.get("emcon_settle_s", 1.5)),
		"active_emitters_disabled": ["iff"] if bool(_emcon.get("active", false)) else [],
		"passive_available": true,
		"shadow": true,
	}


func _add_phantoms(count: int, effect_id: String) -> void:
	for i in range(maxi(1, count)):
		_seq_phantom += 1
		phantom_candidates.append({
			"schema": SCHEMA_PHANTOM,
			"id": "ph-%05d" % _seq_phantom,
			"t_start": t,
			"lifetime_s": float(ew_cfg.get("phantom_lifetime_s", 30.0)),
			"source_effect": effect_id,
			"phantom": true,
			"is_contact": false,
			"produces_contact": false,
			"level": 0,
			"identity": "",
			"threat": "none",
			"inconsistent": true,
			"inconsistency": ["range_power_mismatch", "no_maneuver_history", "no_thermal_signature"],
			"cross_validated": false,
			"removed": false,
			"warnings": ["假目标/诱饵：不得产生真实航迹等级/身份（docs/38 §8.2）"],
			"authoritative": false,
		})
	_alert("phantom", "warn", "欺骗/诱饵：新增 %d 个 phantom 候选；不产生真实等级/身份" % count,
		str(observer.get("id", "")), false, {"count": count, "effect_id": effect_id})


func cross_validate_phantom(phantom_id: String, confirmed_by := "optical") -> Dictionary:
	for raw in phantom_candidates:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == phantom_id:
			var p: Dictionary = raw
			p["cross_validated"] = true
			p["confirmed_by"] = confirmed_by
			p["removed"] = true
			p["removed_reason"] = "cross_sensor_confirmation"
			_alert("phantom_removed", "info", "phantom 被 %s 交叉验证移除（不产生真实航迹）" % confirmed_by,
				str(p.get("id", "")), false, {"phantom_id": phantom_id})
			return {"ok": true, "phantom_id": phantom_id, "removed": true,
				"confirmed_by": confirmed_by, "shadow": true}
	return {"ok": false, "reason": "unknown_phantom", "phantom_id": phantom_id}


# ═══════════════════════════════════════════════════════════════════
# 7. 告警 / VM / JSON
# ═══════════════════════════════════════════════════════════════════

func _rebuild_alerts() -> void:
	var out: Array = []
	for raw in alerts:
		if raw is Dictionary:
			out.append(raw)
	# 保持最近 MAX_ALERTS
	while out.size() > MAX_ALERTS:
		out.pop_front()
	alerts = out


func vm_information_warfare() -> Dictionary:
	var iff_rows: Array = []
	var iff_by_target: Dictionary = {}
	for raw in iff_results:
		if raw is Dictionary:
			var r: Dictionary = raw
			iff_by_target[str(r.get("target_id", ""))] = r
	for tid in iff_by_target.keys():
		iff_rows.append((iff_by_target[tid] as Dictionary).duplicate(true))
	var signal_rows: Array = []
	for raw_s in signals:
		if raw_s is Dictionary:
			var s: Dictionary = raw_s
			if bool(s.get("detected", false)):
				signal_rows.append(s.duplicate(true))
	var comint_rows: Array = []
	for raw_c in comint_events:
		if raw_c is Dictionary:
			comint_rows.append((raw_c as Dictionary).duplicate(true))
	var active_effects: Array = []
	for raw_e in effects:
		if raw_e is Dictionary:
			active_effects.append((raw_e as Dictionary).duplicate(true))
	var phantom_rows: Array = []
	for raw_p in phantom_candidates:
		if raw_p is Dictionary:
			phantom_rows.append((raw_p as Dictionary).duplicate(true))
	var suspicious: Array = []
	for raw_sc in suspicious_commands:
		if raw_sc is Dictionary:
			suspicious.append((raw_sc as Dictionary).duplicate(true))
	var event_rows: Array = events.duplicate(true)
	var alert_rows: Array = alerts.duplicate(true)
	var iff_unknown := 0
	var iff_friend := 0
	for r2 in iff_rows:
		if str(r2.get("identity", "unknown")) == "friend":
			iff_friend += 1
		else:
			iff_unknown += 1
	var signal_detected := signal_rows.size()
	var fix_count := fix_candidates.size()
	var phantom_active := 0
	for p2 in phantom_rows:
		if not bool(p2.get("removed", false)):
			phantom_active += 1
	return {
		"schema": SCHEMA_VM,
		"mode": MODE,
		"authoritative": false,
		"ready": ready,
		"t": t,
		"observer": _observer_view(),
		"mounts": {
			"iff": {"model": str(iff_cfg.get("model", "MK-12")),
				"enabled": bool(iff_cfg.get("enabled", true)) and _sensor_damage_ok()
					and not bool(_emcon.get("active", false)),
				"range_km": float(iff_cfg.get("range_km", IFF_RANGE_KM))},
			"elint": {"model": str(elint_cfg.get("model", "ELINT")),
				"enabled": bool(elint_cfg.get("enabled", true)) and _sensor_damage_ok(),
				"range_km": float(elint_cfg.get("range_km", ELINT_RANGE_KM))},
			"comms": {"model": "CH-R0",
				"enabled": _comms_damage_ok(),
				"note": "COMINT 接收；发射状态由脚本/实体给出"},
		},
		"iff": {
			"available": _iff_available(),
			"model": str(iff_cfg.get("model", "MK-12")),
			"range_km": float(iff_cfg.get("range_km", IFF_RANGE_KM)),
			"results": iff_rows,
			"by_target": iff_by_target,
			"summary": {"total": iff_rows.size(), "friend": iff_friend,
				"unknown": iff_unknown, "hostile": 0},
			"hostile_allowed": false,
		},
		"elint": {
			"state": {"enabled": bool(elint_cfg.get("enabled", true)) and _sensor_damage_ok(),
				"model": str(elint_cfg.get("model", "ELINT")),
				"range_km": float(elint_cfg.get("range_km", ELINT_RANGE_KM)),
				"snr_threshold_db": float(elint_cfg.get("snr_threshold_db", ELINT_SNR_THRESHOLD_DB)),
				"stations": stations.duplicate(true)},
			"signals": signal_rows,
			"misses": misses.duplicate(true),
			"fix_candidates": fix_candidates.duplicate(true),
			"summary": {"signals": signal_detected,
				"stations": stations.size(), "fix_candidates": fix_count,
				"detected_contact": 0},
			"single_station_contact": false,
			"elint_level_cap": "L3_fingerprint_evidence_only",
		},
		"comint": {
			"events": comint_rows,
			"summary": {"events": comint_rows.size(),
				"encrypted": _count_encrypted(comint_rows)},
			"produces_contact": false,
			"auto_decode": false,
		},
		"ew": {
			"effects": active_effects,
			"active_count": active_effects.size(),
			"radar": radar_effect(),
			"comms": comms_effect(),
			"optical": optical_effects(),
			"emcon": emcon_state(),
			"phantom": {"candidates": phantom_rows, "active": phantom_active,
				"produces_real_track": false, "auto_hostile": false},
			"suspicious_commands": suspicious,
			"summary": {"effects": active_effects.size(), "phantom_active": phantom_active,
				"phantoms_removed": phantom_rows.size() - phantom_active,
				"suspicious_commands": suspicious.size(),
				"dazzled": bool(optical_effects().get("dazzled", false)),
				"emcon": bool(_emcon.get("active", false))},
		},
		"effects": active_effects,
		"events": event_rows,
		"alerts": alert_rows,
		"advisory_contacts": advisory_contacts.duplicate(true),
		"summary": {
			"iff": iff_rows.size(),
			"iff_identity_friend": iff_friend,
			"iff_identity_unknown": iff_unknown,
			"iff_identity_hostile": 0,
			"signals": signal_detected,
			"fix_candidates": fix_count,
			"comint": comint_rows.size(),
			"effects": active_effects.size(),
			"events": event_rows.size(),
			"alerts": alert_rows.size(),
			"phantom_active": phantom_active,
			"suspicious_commands": suspicious.size(),
			"hostile_auto_determination": false,
		},
		"writes": {"track_table": false, "v15": false},
		"shadow": {
			"mode": MODE,
			"authoritative": false,
			"writes_track_table": false,
			"writes_v15": false,
			"never_auto_hostile": true,
			"elint_writes_contact": false,
			"comint_writes_contact": false,
		},
	}


func _count_encrypted(rows: Array) -> int:
	var n := 0
	for raw in rows:
		if raw is Dictionary and bool((raw as Dictionary).get("encrypted", false)):
			n += 1
	return n


func _observer_view() -> Dictionary:
	var o := observer.duplicate(true)
	if o.get("pos_km") is Vector3:
		var p: Vector3 = o.get("pos_km")
		o["pos_km"] = [p.x, p.y, p.z]
	return o


func summary() -> Dictionary:
	var vm := vm_information_warfare()
	return vm.get("summary", {}).duplicate(true) if vm.get("summary") is Dictionary else {}


func to_dict() -> Dictionary:
	return vm_information_warfare()


func has_write_target() -> bool:
	return writes_track_table or writes_v15


# 兼容静态辅助（probe/上层可直接调用）
static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
