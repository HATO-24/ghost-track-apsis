class_name V2SensorService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2I · 传感器服务管道（Observation / Evidence 事件）
#
# 输入：observer / mounts / targets snapshot / environment
# 输出：sensor_observation.v1 / track_evidence.v1 事件
#
# 边界：
#   * 只产生观测/证据，**不写 TrackTable/world/V15/UI**；
#   * L1/L2 融合与等级判定由上层 fusion/TrackTable 决定，本服务不判等级；
#   * 雷达/TWS/VIS/IR 复用 V2SensorAuthority；IFF 复用 V2InformationWarfare；
#   * 开关/EMCON/目标/光学通道可显式控制；事件 JSON-safe、确定性。
# ═══════════════════════════════════════════════════════════════════

const Authority := preload("res://framework/sim/sensor_authority.gd")
const InfoWarfare := preload("res://framework/sim/information_warfare.gd")

const SCHEMA_VM := "sensor_service.v1"
const SCHEMA_OBS := "sensor_observation.v1"
const SCHEMA_EVIDENCE := "track_evidence.v1"
const SCHEMA_EVENT := "sensor_service_event.v1"
const MODE := "shadow"
const MAX_OBS := 200
const MAX_EVIDENCE := 100
const MAX_EVENTS := 500
const SENSOR_KINDS := ["radar", "radar.tws", "optical", "ir", "iff", "datalink"]

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var observer: Dictionary = {}
var mounts: Array = []
var targets: Array = []
var snapshot: Dictionary = {}
var selected_target := ""
var radar_enabled := true
var emcon := false
var optical_backend := "optical_ir"
var errors: Array = []
var warnings: Array = []
var observations: Array = []
var evidence: Array = []
var events: Array = []
var config: Dictionary = {}

var _authority = null
var _iff = null
var _radar_mount_id := ""
var _obs_seq := 0
var _evidence_seq := 0
var _event_seq := 0
var _optical_evidence_seen: Dictionary = {}
var _outbox: Array = []
var _last_channels: Array = []
var _last_iff_targets: Dictionary = {}


func _init(cfg := {}) -> void:
	setup(cfg)


# ── setup ──────────────────────────────────────────────────────

## config:
## {observer:{...}, mounts:[...], targets:[...], snapshot:{...},
##  options:{radar_enabled, emcon, optical_backend, iff_enabled}}
func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	observations = []
	evidence = []
	events = []
	_outbox = []
	_obs_seq = 0
	_evidence_seq = 0
	_event_seq = 0
	_optical_evidence_seen = {}
	_last_channels = []
	_last_iff_targets = {}
	selected_target = ""
	radar_enabled = true
	emcon = false
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	var obs_cfg: Dictionary = config.get("observer", {}) if config.get("observer") is Dictionary else {}
	var obs_id := String(obs_cfg.get("id", config.get("observer_id", "harmattan")))
	observer = Authority.default_observer(obs_id)
	for k in obs_cfg.keys():
		observer[String(k)] = obs_cfg[k]
	mounts = []
	if config.get("mounts") is Array and not (config.get("mounts") as Array).is_empty():
		for raw in (config.get("mounts") as Array):
			if raw is Dictionary:
				mounts.append((raw as Dictionary).duplicate(true))
	else:
		mounts = Authority.default_mounts(obs_id)
	var opts: Dictionary = config.get("options", {}) if config.get("options") is Dictionary else {}
	radar_enabled = bool(opts.get("radar_enabled", config.get("radar_enabled", true)))
	emcon = bool(opts.get("emcon", config.get("emcon", false)))
	optical_backend = String(opts.get("optical_backend", config.get("optical_backend", "optical_ir")))
	targets = []
	if config.get("targets") is Array:
		for raw in (config.get("targets") as Array):
			if raw is Dictionary:
				targets.append((raw as Dictionary).duplicate(true))
	snapshot = (config.get("snapshot") as Dictionary).duplicate(true) if config.get("snapshot") is Dictionary else {}
	# authority（雷达/TWS/VIS/IR）
	_authority = Authority.new()
	var auth_cfg: Dictionary = {
		"observer_id": obs_id, "observer": observer, "mounts": mounts,
		"targets": targets, "optical_backend": optical_backend,
	}
	if not snapshot.is_empty():
		auth_cfg["snapshot"] = snapshot
	if not mounts.is_empty():
		var ok: bool = _authority.setup(auth_cfg)
		if not ok:
			errors.append("sensor_authority setup 失败: " + str(_authority.errors))
			warnings.append("sensor_authority 不可用；服务只保留错误/JSON 接口")
	_radar_mount_id = ""
	for raw in _authority.mounts:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == "search_radar":
			_radar_mount_id = String((raw as Dictionary).get("mount_id", ""))
			break
	_apply_controls()
	# IFF（身份证据，不产生位置/接触）
	_init_iff()
	ready = errors.is_empty() and _authority != null and bool(_authority.ready)
	if not ready:
		warnings.append("SENSOR SERVICE NOT READY: " + str(errors))
		return false
	return true


func _init_iff() -> void:
	_iff = null
	if config.get("options") is Dictionary and bool((config.get("options") as Dictionary).get("iff_enabled", true)) == false:
		warnings.append("IFF disabled by options")
		_apply_controls()
		return
	_iff = InfoWarfare.new()
	var rows := _iff_target_rows()
	var ok: bool = _iff.setup({
		"observer_id": String(observer.get("id", "harmattan")),
		"observer": {"id": String(observer.get("id", "harmattan")),
			"pos_km": observer.get("pos_km", [0.0, 0.0, 0.0]),
			"vel_kmps": observer.get("vel_kmps", [0.0, 0.0, 0.0]),
			"emcon": emcon, "mast_deployed": true,
			"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0}},
		"targets": rows,
		"iff": {"enabled": true, "range_km": 2000.0, "crypto_epoch": "epoch-1"},
	})
	if not ok:
		warnings.append("IFF 初始化失败: " + str(_iff.errors))
		_iff = null
		return
	if emcon:
		_iff.set_emcon(true)


func _apply_controls() -> void:
	if _authority != null and _radar_mount_id != "":
		_authority.set_mount_enabled(_radar_mount_id, radar_enabled)
		_authority.set_observer({"emcon": emcon})
	if _iff != null:
		var active := bool((_iff.emcon_state() as Dictionary).get("active", false))
		if active != emcon:
			_iff.set_emcon(emcon)


func _iff_target_rows() -> Array:
	var rows: Array = []
	var list: Array = targets
	if snapshot.get("targets") is Array and not (snapshot.get("targets") as Array).is_empty():
		list = snapshot.get("targets") as Array
	for raw in list:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		var tid := String(d.get("id", d.get("target_id", "")))
		if tid == "":
			continue
		if not d.has("iff_codes"):
			var code := String(d.get("iff_code", "CMP-%s" % tid))
			d["iff_codes"] = {"3/A": code}
		if not d.has("transponder"):
			d["transponder"] = "off"
		if not d.has("registered"):
			d["registered"] = String(d.get("side", "")) == "friend"
		if not d.has("crypto_epoch"):
			d["crypto_epoch"] = "epoch-1"
		rows.append(d)
	return rows


# ── 显式控制 ────────────────────────────────────────────────────

func set_target(target_id: String) -> Dictionary:
	if _find_target(target_id).is_empty() and _target_from_snapshot(target_id).is_empty():
		return {"ok": false, "reason": "unknown_target", "target_id": target_id}
	selected_target = target_id
	return {"ok": true, "reason": "", "target_id": target_id}


func start_channel(kind: String, target: String, opts := {}) -> Dictionary:
	if _authority == null or not bool(_authority.ready):
		return {"ok": false, "reason": "not_ready"}
	if not (String(kind) in ["optical", "ir"]):
		return {"ok": false, "reason": "invalid_kind", "kind": kind}
	if target == "" or (_find_target(target).is_empty() and _target_from_snapshot(target).is_empty()):
		return {"ok": false, "reason": "unknown_target", "target_id": target}
	var r: Dictionary = _authority.start_channel(String(kind), target, opts if opts is Dictionary else {})
	if bool(r.get("ok", false)):
		selected_target = target
		_push_event("channel_start", {"kind": kind, "target_id": target,
			"reason": String(r.get("reason", ""))})
	return r


func stop_channel(kind := "", target := "") -> Dictionary:
	if _authority == null or not bool(_authority.ready):
		return {"ok": false, "reason": "not_ready"}
	var stopped: Array = []
	for k in ["optical", "ir"]:
		if kind != "" and String(k) != kind:
			continue
		var ch = _authority.channel(k, target) if target != "" else null
		if target != "" and (ch == null or (ch is Dictionary and (ch as Dictionary).is_empty())):
			continue
		_authority.stop_channel(String(k), target)
		stopped.append(String(k))
	if stopped.is_empty():
		return {"ok": false, "reason": "no_matching_channel"}
	_push_event("channel_stop", {"kind": kind, "target_id": target,
		"reason": ",".join(stopped)})
	return {"ok": true, "reason": "", "stopped": stopped}


func set_radar_enabled(on: bool) -> Dictionary:
	radar_enabled = bool(on)
	emcon = not radar_enabled
	_apply_controls()
	_push_event("radar", {"on": radar_enabled, "emcon": emcon,
		"reason": "" if radar_enabled else "radar_off_emcon"})
	return {"ok": true, "reason": "" if radar_enabled else "radar_off_emcon",
		"radar_enabled": radar_enabled, "emcon": emcon,
		"writes": {"track_table": false, "v15": false}}


func set_emcon(on: bool) -> Dictionary:
	emcon = bool(on)
	radar_enabled = not emcon
	_apply_controls()
	_push_event("emcon", {"emcon": emcon, "reason": "emcon" if emcon else "emcon_off"})
	return {"ok": true, "radar_enabled": radar_enabled, "emcon": emcon,
		"writes": {"track_table": false, "v15": false}}


# ── step ───────────────────────────────────────────────────────

## 输入：dt、可选 world snapshot；输出 VM（observations/evidence/events）。
func step(dt: float, snap := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	var input: Dictionary = snap if snap is Dictionary else {}
	if not input.is_empty():
		snapshot = input.duplicate(true)
		if snapshot.get("observer") is Dictionary:
			for k in (snapshot.get("observer") as Dictionary).keys():
				observer[String(k)] = (snapshot.get("observer") as Dictionary)[k]
		if snapshot.get("targets") is Array:
			targets = (snapshot.get("targets") as Array).duplicate(true)
	var model_snap := _build_snapshot()
	var new_events: Array = []
	if _authority != null and bool(_authority.ready):
		var av: Dictionary = _authority.step(d, model_snap)
		_collect_observations(av, new_events)
		_collect_optical_evidence(av, new_events)
		_last_channels = (av.get("channels", []) as Array).duplicate(true)
	# IFF 模型只推进位置/状态；IFF 证据由 query_iff 显式产生
	if _iff != null:
		_iff.set_targets(_iff_target_rows())
		_iff.step(d)
	vm({})
	return _vm_current()


func _build_snapshot() -> Dictionary:
	var out: Dictionary = {
		"t": t,
		"observer": observer.duplicate(true),
		"targets": targets.duplicate(true),
		"sun_illum": float(snapshot.get("sun_illum", 1.0)),
		"sun_dir": snapshot.get("sun_dir", [1.0, 0.0, 0.0]),
		"earth_albedo": float(snapshot.get("earth_albedo", 0.03)),
		"jamming": float(snapshot.get("jamming", 0.0)),
		"shadow": bool(snapshot.get("shadow", false)),
		"los": bool(snapshot.get("los", true)),
	}
	return out


func _sensor_name(o: Dictionary, model: String) -> String:
	var s := String(o.get("sensor", o.get("sensor_kind", o.get("sensor_type", ""))))
	if s != "":
		return s
	var src := String(o.get("source", ""))
	if model == "YW-R9" or src.find("tws") >= 0:
		return "radar.tws" if src.find("tws") >= 0 or src == "" else "radar"
	if model == "MS-OT2" or src.find("optical") >= 0:
		return "optical"
	if model == "CH-IR2" or src.find("ir") >= 0:
		return "ir"
	if model == "MK-12" or src.find("iff") >= 0:
		return "iff"
	return "unknown"


func _collect_observations(av: Dictionary, new_events: Array) -> void:
	var rows: Array = av.get("advisory_observations", []) if av.get("advisory_observations") is Array else []
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = (raw as Dictionary).duplicate(true)
		_obs_seq += 1
		var model := String(o.get("sensor_model", o.get("model", "")))
		var sensor := _sensor_name(o, model)
		# 雷达/EMCON 关闭：不产生主动雷达观测；被动光学仍可
		if (not radar_enabled or emcon) and sensor in ["radar", "radar.tws"]:
			continue
		var ev := {
			"schema": SCHEMA_OBS, "kind": "observation",
			"event_id": "OBS-%06d" % _obs_seq,
			"t": t, "observer_id": String(observer.get("id", "")),
			"target_id": String(o.get("target_id", o.get("id", ""))),
			"sensor": sensor,
			"support": int(o.get("support", o.get("level_support", 1))),
			"quality": float(o.get("quality", 0.0)),
			"range_km": float(o.get("range_km", -1.0)),
			"bearing_deg": float(o.get("bearing_deg", -1.0)),
			"position_km": o.get("position_km", o.get("pos_km", [])),
			"sensor_model": model,
			"reason": String(o.get("reason", "")),
			"provenance": "sensor_service/authority",
			"level_decided": false,
			"produces_contact": false,
			"writes_v15": false,
		}
		observations.append(ev)
		while observations.size() > MAX_OBS:
			observations.pop_front()
		events.append(ev.duplicate(true))
		_outbox.append(ev.duplicate(true))
		new_events.append(ev.duplicate(true))


func _collect_optical_evidence(av: Dictionary, new_events: Array) -> void:
	var chans: Array = av.get("channels", []) if av.get("channels") is Array else []
	for raw in chans:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		if String(ch.get("channel", "")) != "optical":
			continue
		if String(ch.get("status", "")) != "locked":
			continue
		var cls: Dictionary = ch.get("classification", {}) if ch.get("classification") is Dictionary else {}
		if cls.is_empty():
			continue
		var tid := String(ch.get("target_id", ""))
		var key := tid + "|locked"
		if _optical_evidence_seen.has(key):
			continue
		_optical_evidence_seen[key] = true
		_evidence_seq += 1
		var ev := {
			"schema": SCHEMA_EVIDENCE, "kind": "evidence",
			"event_id": "EVD-%06d" % _evidence_seq,
			"evidence_id": "EVD-%06d" % _evidence_seq,
			"t": t, "observer_id": String(observer.get("id", "")),
			"target_id": tid, "evidence_type": "optical",
			"support": 3, "identity": "unknown",
			"classification": cls.duplicate(true),
			"sensor": "optical", "level_decided": false,
			"produces_contact": false, "produces_position": false,
			"writes_v15": false,
		}
		evidence.append(ev)
		while evidence.size() > MAX_EVIDENCE:
			evidence.pop_front()
		events.append(ev.duplicate(true))
		_outbox.append(ev.duplicate(true))
		new_events.append(ev.duplicate(true))


# ── IFF 证据 ───────────────────────────────────────────────────

## 显式 IFF 询问：只产生 track_evidence，不产生 observation/位置/接触。
func query_iff(target_id := "") -> Dictionary:
	if _iff == null:
		return {"ok": false, "reason": "iff_unavailable", "target_id": target_id}
	var tid := target_id if target_id != "" else selected_target
	if tid == "":
		return {"ok": false, "reason": "no_target"}
	var row := _iff_target_rows()
	var found := false
	for raw in row:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			found = true
			break
	if not found:
		return {"ok": false, "reason": "unknown_target", "target_id": tid}
	var code := ""
	for raw in row:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			code = String((raw as Dictionary).get("iff_code", ""))
			break
	var res: Dictionary = _iff.interrogate_iff(tid, ["3/A"],
		{"expected_codes": {"3/A": code}})
	var raw_status := String(res.get("status", "unknown"))
	var identity := String(res.get("identity", "unknown"))
	var status := "friend" if identity == "friend" else raw_status
	var ev := {
		"schema": SCHEMA_EVIDENCE, "kind": "evidence",
		"event_id": "EVD-%06d" % (_evidence_seq + 1),
		"evidence_id": "EVD-%06d" % (_evidence_seq + 1),
		"t": t, "observer_id": String(observer.get("id", "")),
		"target_id": tid, "evidence_type": "iff",
		"support": 4, "identity": identity,
		"status": status, "iff_status": raw_status, "raw_status": raw_status,
		"friend": identity == "friend",
		"hostile": false, "never_hostile": true,
		"produces_contact": false, "produces_position": false,
		"level_decided": false,
		"range_km": float(res.get("range_km", -1.0)),
		"reason": String(res.get("reason", "")),
		"writes_v15": false,
	}
	_evidence_seq += 1
	evidence.append(ev)
	while evidence.size() > MAX_EVIDENCE:
		evidence.pop_front()
	events.append(ev.duplicate(true))
	_outbox.append(ev.duplicate(true))
	_optical_evidence_seen["iff|" + tid] = true
	_push_event("iff", {"target_id": tid, "status": status, "identity": identity})
	return {"ok": true, "reason": "", "evidence": ev.duplicate(true),
		"status": status, "identity": identity, "never_hostile": true,
		"writes_v15": false}


func iff(target_id := "") -> Dictionary:
	return query_iff(target_id)


# ── 查询 / VM ─────────────────────────────────────────────────

func _vm_current() -> Dictionary:
	var av: Dictionary = _authority.vm_sensor() if _authority != null else {}
	var channels: Array = av.get("channels", []) if av.get("channels") is Array else _last_channels.duplicate(true)
	var ev_rows: Array = []
	for raw in events:
		ev_rows.append((raw as Dictionary).duplicate(true))
	return {
		"schema": SCHEMA_VM, "mode": MODE, "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"observer": observer.duplicate(true),
		"mounts": mounts.duplicate(true),
		"selected_target": selected_target,
		"targets": targets.duplicate(true),
		"radar_enabled": radar_enabled, "emcon": emcon,
		"optical_backend": optical_backend,
		"observations": observations.duplicate(true),
		"evidence": evidence.duplicate(true),
		"events": ev_rows,
		"channels": channels,
		"authority": {
			"ready": bool(av.get("ready", false)),
			"optical_backend": String(av.get("optical_backend", optical_backend)),
			"counts": (av.get("counts", {}) as Dictionary).duplicate(true) if av.get("counts") is Dictionary else {},
		},
		"counts": {
			"observations": observations.size(), "evidence": evidence.size(),
			"events": events.size(), "channels": channels.size(),
			"radar_obs": _count_obs_sensor("radar"),
			"tws_obs": _count_obs_sensor("radar.tws"),
			"optical_evidence": _count_evidence("optical"),
			"iff_evidence": _count_evidence("iff"),
		},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"track_table": false, "v15": false, "world": false},
	}


func _count_obs_sensor(sensor: String) -> int:
	var n := 0
	for raw in observations:
		if raw is Dictionary and String((raw as Dictionary).get("sensor", "")) == sensor:
			n += 1
	return n


func _count_evidence(etype: String) -> int:
	var n := 0
	for raw in evidence:
		if raw is Dictionary and String((raw as Dictionary).get("evidence_type", "")) == etype:
			n += 1
	return n


func vm(_opts := {}) -> Dictionary:
	return _vm_current()


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t,
		"observer_id": String(observer.get("id", "")),
		"observations": observations.size(), "evidence": evidence.size(),
		"events": events.size(), "radar_enabled": radar_enabled,
		"emcon": emcon, "writes": {"track_table": false, "v15": false}}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())


func events_since(seq := 0) -> Array:
	var out: Array = []
	for i in range(seq, events.size()):
		if events[i] is Dictionary:
			out.append((events[i] as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


# ── 工具 ──────────────────────────────────────────────────────

func _find_target(id: String) -> Dictionary:
	for raw in targets:
		if raw is Dictionary and String((raw as Dictionary).get("id", (raw as Dictionary).get("target_id", ""))) == id:
			return raw
	return {}


func _target_from_snapshot(id: String) -> Dictionary:
	if not (snapshot.get("targets") is Array):
		return {}
	for raw in (snapshot.get("targets") as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", (raw as Dictionary).get("target_id", ""))) == id:
			return raw
	return {}


func _push_event(kind: String, detail: Dictionary) -> void:
	_event_seq += 1
	var ev := {"schema": SCHEMA_EVENT, "kind": kind, "seq": _event_seq, "t": t,
		"observer_id": String(observer.get("id", "")), "detail": detail.duplicate(true),
		"shadow": true, "writes_v15": false}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))
