class_name V2TransitSensors
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 阶段2-TRANSIT-SENSOR-1 · 转场场景传感器数据层（只读 shadow）
#
# 数据源（只读）：
#   * framework/content/scenario_transit_l4_l1.json（5 舰 / 4 港 / 转移场景）
#   * framework/sim/transfer_planner.gd::plan()（缓存一次；真实 CR3BP/Lambert timeline）
#   * framework/sim/sensor_authority.gd（V2SensorAuthority：球形雷达/TWS/VIS/IR）
#   * framework/sim/optical_ir_channel.gd（authority 内部 optical_ir 后端）
#
# 职责：
#   * 把转场 timeline + 舰队偏移换算成同一 bary_rot 帧内的观测者/目标位置；
#   * 对 5 舰与 L1/L4 港群调用真实 authority 模型，输出 contacts/channels/
#     optical/levels/events/warnings；
#   * **只读**：不写 world/TrackTable/V15，不接 HUD/state/bridge。
#
# 坐标：bary_rot（km, km/s, s）；场景/planner 原样；本层不换帧。
# 目标：5 舰（apsis 1000、harmattan 1001、ferry 1002、watchtower 1003、
# deepwell 1004）+ 4 港（l4_02_hammer 3000、L1 Meridian/Anchorage/Drydock 3100–3102）。
# 传感器：V2SensorAuthority shadow；默认 observer=harmattan（YW-R9/MS-OT2/CH-IR2）。
# 舰载能力不足的舰作为 observer 时，数据层补充 authority 默认挂载并广播 warning，
# 确保 5 舰都可 select_ship；warning 明确标 capability_fallback，不冒充 V15 权威。
# ═══════════════════════════════════════════════════════════════════

const ScenarioPath := "res://framework/content/scenario_transit_l4_l1.json"
const Planner := preload("res://framework/sim/transfer_planner.gd")
const Authority := preload("res://framework/sim/sensor_authority.gd")
const InfoWarfare := preload("res://framework/sim/information_warfare.gd")

const SCHEMA_VM := "transit_sensor_data.v1"
const SCHEMA_IFF := "transit_iff.v1"
const MODE := "shadow"
const EXPECTED_SHIP_IDS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const SHIP_TRANSPONDER := {
	"apsis": "ok", "harmattan": "ok", "ferry": "ok",
	"watchtower": "faulty", "deepwell": "off",
}
const SHIP_IFF_CODE := {
	"apsis": "CMP-1000", "harmattan": "CMP-1001", "ferry": "CMP-1002",
	"watchtower": "OCU-1003", "deepwell": "CMP-1004",
}
const PORT_IFF_CODE := {
	"l4_02_hammer": "PORT-3000", "l1_meridian_05": "PORT-3100",
	"l1_anchorage_02": "PORT-3101", "l1_drydock_01": "PORT-3102",
}
const IFF_RANGE_KM := 2000.0
const SHIP_NAMES := {
	"apsis": "远地点", "harmattan": "哈马丹", "ferry": "渡口",
	"watchtower": "望楼", "deepwell": "深井",
}
const SHIP_BATCH := {
	"apsis": "1000", "harmattan": "1001", "ferry": "1002",
	"watchtower": "1003", "deepwell": "1004",
}
const SHIP_ROLE := {
	"apsis": "flagship", "harmattan": "command", "ferry": "escort",
	"watchtower": "relay", "deepwell": "tanker",
}
const SHIP_RCS := {
	"apsis": 2200.0, "harmattan": 900.0, "ferry": 500.0,
	"watchtower": 380.0, "deepwell": 1400.0,
}
const PORT_RCS := 6000.0
const SHIP_SIZE_M := {
	"apsis": 180.0, "harmattan": 90.0, "ferry": 70.0,
	"watchtower": 120.0, "deepwell": 160.0,
}
const PORT_SIZE_M := 300.0
const MAX_EVENTS := 80

static var _plan_cache: Dictionary = {}

var ready := false
var errors: Array = []
var warnings: Array = []
var notes: Array = []
var scenario: Dictionary = {}
var plan: Dictionary = {}
var t := 0.0
var tof_s := 0.0
var dt_last := 0.0
var step_count := 0

var ships: Array = []          # [{id, batch, name, role, offset_km, capabilities}]
var ports: Array = []          # [{id, batch, name, lpoint, port_id, offset_km, status}]
var ship_by_id: Dictionary = {}
var target_defs: Dictionary = {}  # target_id -> normalized target def
var selected_ship := "harmattan"
var selected_target := "apsis"

var _authority = null
var _iff = null
var _radar_mount_id := ""
var _radar_enabled := true
var _emcon := false
var _iff_last: Dictionary = {}
var _iff_results: Array = []
var _iff_by_target: Dictionary = {}
var _loadout_by_ship: Dictionary = {}
var _fallback_mounts: Dictionary = {}
var _active_channels: Dictionary = {}  # "optical"/"ir" -> target_id
var _last_vm: Dictionary = {}
var _events: Array = []
var _event_log: Array = []
var _last_snapshot: Dictionary = {}
var _warn_seen: Dictionary = {}


func _init(opts := {}) -> void:
	setup(opts)


# ═══════════════════════════════════════════════════════════════════
# 0. setup / 数据装载
# ═══════════════════════════════════════════════════════════════════

func setup(opts := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	notes = []
	events = []
	_event_log = []
	ships = []
	ports = []
	ship_by_id = {}
	target_defs = {}
	selected_ship = "harmattan"
	selected_target = "apsis"
	_authority = null
	_iff = null
	_radar_mount_id = ""
	_radar_enabled = true
	_emcon = false
	_iff_last = {}
	_iff_results = []
	_iff_by_target = {}
	_loadout_by_ship = {}
	_fallback_mounts = {}
	_active_channels = {}
	_last_vm = {}
	_last_snapshot = {}
	_warn_seen = {}
	t = 0.0
	tof_s = 0.0
	dt_last = 0.0
	step_count = 0
	_load_scenario()
	if scenario.is_empty():
		errors.append("scenario_load_failed: " + ScenarioPath)
		return false
	plan = _get_plan()
	tof_s = float((plan.get("transfer", {}) as Dictionary).get("tof_s", 0.0))
	if not bool(plan.get("ok", false)):
		warnings.append("TRANSFER PLANNER NOT OK: %s（不伪造 timeline；传感器层仍尝试用场景 offset）" % String(plan.get("reason", "")))
	if tof_s <= 0.0:
		warnings.append("timeline/tof 为空：转场传感器只保留场景静态几何")
	_build_ships()
	_build_ports()
	var want_obs := String(opts.get("observer_id", "harmattan")) if opts is Dictionary else "harmattan"
	if not ship_by_id.has(want_obs):
		want_obs = "harmattan" if ship_by_id.has("harmattan") else String((ships[0] as Dictionary).get("id", "")) if not ships.is_empty() else ""
	selected_ship = want_obs
	var want_tgt := String(opts.get("target_id", "apsis")) if opts is Dictionary else "apsis"
	if want_tgt == selected_ship or not target_defs.has(want_tgt):
		want_tgt = _first_target_id()
	selected_target = want_tgt
	_select_observer_internal(selected_ship, true)
	ready = true
	_ensure_auto_channels()
	_rebuild(_empty_step_events())
	return true


func _load_scenario() -> void:
	scenario = {}
	if not FileAccess.file_exists(ScenarioPath):
		return
	var f := FileAccess.open(ScenarioPath, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		scenario = parsed


func _get_plan() -> Dictionary:
	if not _plan_cache.is_empty():
		return _plan_cache.duplicate(true)
	var p: Dictionary = Planner.plan({})
	_plan_cache = p.duplicate(true)
	return _plan_cache.duplicate(true)


func _build_ships() -> void:
	var ent_by_id: Dictionary = {}
	for raw in (scenario.get("entities", []) as Array):
		if raw is Dictionary:
			ent_by_id[String((raw as Dictionary).get("id", ""))] = (raw as Dictionary)
	var fleet: Array = []
	var plan_fleet: Array = plan.get("fleet", []) if plan.get("fleet") is Array else []
	var plan_off: Dictionary = {}
	for raw in plan_fleet:
		if raw is Dictionary:
			plan_off[String((raw as Dictionary).get("id", ""))] = raw
	for sid in EXPECTED_SHIP_IDS:
		var e: Dictionary = ent_by_id.get(sid, {})
		var meta: Dictionary = (e.get("meta", {}) as Dictionary) if e.get("meta") is Dictionary else {}
		var off: Array = (meta.get("fleet_offset_km", []) as Array) if meta.get("fleet_offset_km") is Array else []
		if off.size() != 3 and plan_off.has(sid):
			off = (plan_off[sid].get("offset_km", []) as Array)
		if off.size() != 3:
			off = [0.0, 0.0, 0.0]
		var offv: Array = []
		if plan_off.has(sid) and (plan_off[sid] as Dictionary).get("offset_kmps") is Array:
			offv = ((plan_off[sid] as Dictionary).get("offset_kmps", []) as Array)
		if offv.size() != 3:
			offv = [0.0, 0.0, 0.0]
		var caps: Array = (e.get("capabilities", []) as Array) if e.get("capabilities") is Array else []
		var row := {
			"id": sid, "batch": SHIP_BATCH.get(sid, ""),
			"name": String(e.get("name", SHIP_NAMES.get(sid, sid))),
			"role": String(meta.get("transfer_role", SHIP_ROLE.get(sid, "ship"))),
			"class": String(e.get("class", "")), "faction": String(e.get("faction", "")),
			"offset_km": [float(off[0]), float(off[1]), float(off[2])],
			"offset_kmps": [float(offv[0]), float(offv[1]), float(offv[2])],
			"capabilities": caps.duplicate(),
			"side": String(e.get("side", "friend")),
		}
		fleet.append(row)
		ship_by_id[sid] = row
	ships = fleet
	# 港群
	var port_entities: Array = []
	for raw in (scenario.get("entities", []) as Array):
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var tags: Array = e.get("tags", []) if e.get("tags") is Array else []
		if "port" in tags or String(e.get("kind", "")) == "station":
			port_entities.append(e)
	var owner_defs: Dictionary = {}
	for raw in (scenario.get("ports", []) as Array):
		if raw is Dictionary:
			owner_defs[String((raw as Dictionary).get("owner_id", ""))] = raw
	for raw in port_entities:
		var e: Dictionary = raw
		var sid := String(e.get("id", ""))
		var pd: Dictionary = owner_defs.get(sid, {}) if owner_defs.get(sid) is Dictionary else {}
		var off: Array = (pd.get("offset_km", []) as Array) if pd.get("offset_km") is Array else []
		if off.size() != 3:
			var orb: Dictionary = (e.get("orbit", {}) as Dictionary) if e.get("orbit") is Dictionary else {}
			off = (orb.get("r", [0.0, 0.0, 0.0]) as Array)
		ports.append({
			"id": sid, "batch": String(e.get("batch", "")),
			"name": String(e.get("name", sid)),
			"lpoint": String(e.get("lpoint", (e.get("meta", {}) as Dictionary).get("lpoint", ""))) if e.get("meta") is Dictionary else "",
			"port_id": String(pd.get("port_id", (e.get("meta", {}) as Dictionary).get("port_id", sid))) if e.get("meta") is Dictionary else "",
			"offset_km": [float(off[0]), float(off[1]), float(off[2])],
			"status": String(pd.get("status", "open")),
			"side": String(e.get("side", "friend")),
		})
	# 目标集合 = 非 observer 舰 + 港
	for raw in ships:
		var sh: Dictionary = raw
		target_defs[String(sh.get("id", ""))] = _ship_target_def(sh)
	for raw in ports:
		var pt: Dictionary = raw
		target_defs[String(pt.get("id", ""))] = _port_target_def(pt)


func _build_ports() -> void:
	# _build_ships 中已构造 ports；此函数保留给固定旧数据兼容（不重复添加）。
	pass


func _ship_target_def(sh: Dictionary) -> Dictionary:
	var sid := String(sh.get("id", ""))
	var code := String(SHIP_IFF_CODE.get(sid, "CMP-0000"))
	return {
		"id": sid, "entity_id": sid, "batch": String(sh.get("batch", "")),
		"name": String(sh.get("name", sid)), "kind": "ship",
		"side": String(sh.get("side", "friend")), "faction": String(sh.get("faction", "")),
		"rcs_m2": float(SHIP_RCS.get(sid, 500.0)), "size_m": float(SHIP_SIZE_M.get(sid, 80.0)),
		"temp_k": 300.0, "area_m2": 1200.0, "illum": 1.0,
		"transponder": String(SHIP_TRANSPONDER.get(sid, "off")),
		"registered": true, "crypto_epoch": "epoch-1", "reply_delay_s": 0.2,
		"iff_code": code, "iff_codes": {"3/A": code},
		"classification": {"ship_class": String(sh.get("class", "")),
			"role": String(sh.get("role", "")), "faction": String(sh.get("faction", ""))},
		"emissions": [],
	}


func _port_target_def(pt: Dictionary) -> Dictionary:
	var pid := String(pt.get("id", ""))
	var code := String(PORT_IFF_CODE.get(pid, "PORT-0000"))
	return {
		"id": pid, "entity_id": pid, "batch": String(pt.get("batch", "")),
		"name": String(pt.get("name", pid)), "kind": "port",
		"side": String(pt.get("side", "friend")), "faction": "OCUVF · ID13",
		"rcs_m2": PORT_RCS, "size_m": PORT_SIZE_M, "temp_k": 290.0, "area_m2": 8000.0,
		"illum": 1.0, "transponder": "ok", "registered": true,
		"crypto_epoch": "epoch-1", "reply_delay_s": 0.2,
		"iff_code": code, "iff_codes": {"3/A": code},
		"classification": {"ship_class": "station", "role": "port", "faction": "OCUVF · ID13"},
		"emissions": [],
	}


func _first_target_id() -> String:
	for sid in EXPECTED_SHIP_IDS:
		if sid != selected_ship and target_defs.has(sid):
			return sid
	for raw in target_defs.keys():
		return String(raw)
	return ""


# ═══════════════════════════════════════════════════════════════════
# 1. 位置：真实 timeline + 舰队偏移 / 港群偏移
# ═══════════════════════════════════════════════════════════════════

func _base_state_at(t_s: float) -> Dictionary:
	var tl: Array = plan.get("timeline", []) if plan.get("timeline") is Array else []
	if tl.size() < 2:
		var src: Dictionary = plan.get("source", {}) if plan.get("source") is Dictionary else {}
		return {"pos": _arr3(src.get("pos_rot_km", [0.0, 0.0, 0.0])),
			"vel": _arr3(src.get("vel_rot_kmps", [0.0, 0.0, 0.0]))}
	var f := clampf(t_s / maxf(1.0e-9, tof_s), 0.0, 1.0)
	var x := f * float(tl.size() - 1)
	var i := clampi(int(floor(x)), 0, tl.size() - 2)
	var a := x - float(i)
	var r0: Dictionary = tl[i]
	var r1: Dictionary = tl[i + 1]
	var p0 := _arr3(r0.get("pos_rot_km", []))
	var p1 := _arr3(r1.get("pos_rot_km", []))
	var v0 := _arr3(r0.get("vel_rot_kmps", []))
	var v1 := _arr3(r1.get("vel_rot_kmps", []))
	return {"pos": [p0[0] + (p1[0] - p0[0]) * a, p0[1] + (p1[1] - p0[1]) * a,
			p0[2] + (p1[2] - p0[2]) * a],
		"vel": [v0[0] + (v1[0] - v0[0]) * a, v0[1] + (v1[1] - v0[1]) * a,
			v0[2] + (v1[2] - v0[2]) * a]}


func _observer_pos() -> Array:
	var base := _base_state_at(t)
	var sh: Dictionary = ship_by_id.get(selected_ship, {})
	if sh.is_empty():
		return base.get("pos", [0.0, 0.0, 0.0])
	return _add3(base.get("pos", [0.0, 0.0, 0.0]), _arr3(sh.get("offset_km", [0.0, 0.0, 0.0])))


func ship_state(id: String) -> Dictionary:
	var sh: Dictionary = ship_by_id.get(id, {})
	if sh.is_empty():
		return {}
	var base := _base_state_at(t)
	var off := _arr3(sh.get("offset_km", [0.0, 0.0, 0.0]))
	var pos := _add3(base.get("pos", []), off)
	return {"pos_km": pos, "vel_kmps": _velocity_state(id),
		"range_km": _dist3(pos, _observer_pos())}


func port_state(id: String) -> Dictionary:
	for raw in ports:
		if not (raw is Dictionary):
			continue
		var pt: Dictionary = raw
		if String(pt.get("id", "")) != id:
			continue
		var pos: Array = []
		if String(pt.get("lpoint", "")) == "L4" or String(pt.get("id", "")) == "l4_02_hammer":
			var src: Dictionary = plan.get("source", {}) if plan.get("source") is Dictionary else {}
			pos = _arr3(src.get("pos_rot_km", pt.get("offset_km", [0.0, 0.0, 0.0])))
		else:
			var tgt: Dictionary = plan.get("target", {}) if plan.get("target") is Dictionary else {}
			var base := _arr3(tgt.get("pos_rot_km", [0.0, 0.0, 0.0]))
			var off := _arr3(pt.get("offset_km", [0.0, 0.0, 0.0]))
			var tgt_port_off := _target_port_offset()
			pos = _add3(base, _sub3(off, tgt_port_off))
		return {"pos_km": pos, "vel_kmps": _arr3((plan.get("target", {}) as Dictionary).get("vel_rot_kmps", [0.0, 0.0, 0.0])) if String(pt.get("lpoint", "")) != "L4" else [0.0, 0.0, 0.0],
			"range_km": _dist3(pos, _observer_pos())}
	return {}


func target_state(id: String) -> Dictionary:
	if ship_by_id.has(id):
		return ship_state(id)
	for raw in ports:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
			return port_state(id)
	return {}


func _target_port_offset() -> Array:
	for raw in ports:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "l1_meridian_05":
			return _arr3((raw as Dictionary).get("offset_km", [0.0, 0.0, 0.0]))
	return [160.0, -90.0, 15.0]


func _velocity_state(id: String) -> Array:
	if ship_by_id.has(id):
		# 共享转移基线速度；舰队 offset_kmps 仅作数据元数据，不叠加到相对速度，
		# 避免 1 m/s 量级的编队差在 1 µrad IFOV 下被误判为运动模糊（演示几何口径见 docs）。
		var base := _base_state_at(t)
		return base.get("vel", [0.0, 0.0, 0.0])
	return [0.0, 0.0, 0.0]

# ═══════════════════════════════════════════════════════════════════
# 2. Authority 装配 / 舰载挂载
# ═══════════════════════════════════════════════════════════════════

func _select_observer_internal(sid: String, initial := false) -> void:
	var sh: Dictionary = ship_by_id.get(sid, {})
	if sh.is_empty():
		errors.append("unknown_ship: " + sid)
		return
	selected_ship = sid
	if selected_target == sid or not target_defs.has(selected_target):
		selected_target = _first_target_id()
	_active_channels = {}
	_build_authority()
	if not initial:
		_push_event("ship", "observer → %s (%s)" % [sid, String(sh.get("name", sid))])
	_ensure_auto_channels()


func _build_authority() -> void:
	_authority = Authority.new()
	var sh: Dictionary = ship_by_id.get(selected_ship, {})
	var loadout := _loadout_for(sh)
	_loadout_by_ship[selected_ship] = loadout
	var mounts: Array = loadout.get("mounts", [])
	var obs_state := ship_state(selected_ship)
	var obs := {
		"id": selected_ship, "pos_km": obs_state.get("pos_km", [0.0, 0.0, 0.0]),
		"vel_kmps": obs_state.get("vel_kmps", [0.0, 0.0, 0.0]),
		"attitude_quat": [0.0, 0.0, 0.0, 1.0], "attitude_source": "default_not_modeled",
		"angular_rate_dps": [0.0, 0.0, 0.0], "maneuver_g": 0.0,
		"mast_deployed": true, "emcon": _emcon,
		"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0},
	}
	var targets := _authority_targets()
	var ok: bool = _authority.setup({
		"observer_id": selected_ship, "observer": obs, "mounts": mounts,
		"targets": targets, "sun_illum": 1.0,
		"optical_channels": [],
	})
	_last_snapshot = _build_snapshot()
	_radar_mount_id = ""
	for raw in _authority.mounts:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == "search_radar":
			_radar_mount_id = String((raw as Dictionary).get("mount_id", ""))
			break
	if not ok:
		errors.append("authority_setup_failed: " + selected_ship + " " + str(_authority.errors))
		return
	_authority.set_mount_enabled(_radar_mount_id, _radar_enabled)
	_authority.set_observer({"emcon": _emcon})
	var warnings_out: Array = []
	for raw in _authority.warnings:
		var w := String(raw)
		if not (w in warnings_out):
			warnings_out.append(w)
	if warnings_out.is_empty():
		pass
	for w in warnings_out:
		_add_warning(w)
	for fm in (loadout.get("fallbacks", []) as Array):
		_add_warning("CAPABILITY FALLBACK: %s %s（场景未列该能力；数据层用 authority 默认挂载）" % [selected_ship, String(fm)])
	_fallback_mounts[selected_ship] = (loadout.get("fallbacks", []) as Array).duplicate()
	_build_iff()


func _build_iff() -> void:
	_iff = null
	_iff_last = {}
	_iff_results = []
	_iff_by_target = {}
	if _authority == null:
		return
	_iff = InfoWarfare.new()
	var obs_state := ship_state(selected_ship)
	var rows := _iff_target_rows()
	var ok: bool = _iff.setup({
		"observer_id": selected_ship,
		"observer": {"id": selected_ship,
			"pos_km": obs_state.get("pos_km", [0.0, 0.0, 0.0]),
			"vel_kmps": obs_state.get("vel_kmps", [0.0, 0.0, 0.0]),
			"emcon": _emcon, "mast_deployed": true,
			"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0}},
		"targets": rows,
		"iff": {"enabled": true, "range_km": IFF_RANGE_KM, "crypto_epoch": "epoch-1"},
		"stations": [{"id": "%s-ELINT" % selected_ship,
			"pos_km": obs_state.get("pos_km", [0.0, 0.0, 0.0]),
			"enabled": true, "sigma_bearing_deg": 1.0}],
	})
	if not ok:
		_add_warning("IFF 初始化失败: " + str(_iff.errors))
		return
	if _emcon:
		_iff.set_emcon(true)
	for raw in _iff.warnings:
		_add_warning("IFF: " + String(raw))


func _iff_target_rows() -> Array:
	var out: Array = []
	for tid in target_defs.keys():
		var id := String(tid)
		if id == selected_ship:
			continue
		var d: Dictionary = (target_defs[id] as Dictionary).duplicate(true)
		var st := target_state(id)
		if not st.is_empty():
			d["pos_km"] = st.get("pos_km", [])
			d["vel_kmps"] = _velocity_state(id) if ship_by_id.has(id) else st.get("vel_kmps", [])
		out.append(d)
	return out


func _apply_controls() -> void:
	if _authority != null and _radar_mount_id != "":
		_authority.set_mount_enabled(_radar_mount_id, _radar_enabled)
		_authority.set_observer({"emcon": _emcon})
	if _iff != null:
		var cur := bool((_iff.emcon_state() as Dictionary).get("active", false))
		if cur != _emcon:
			_iff.set_emcon(_emcon)


func _loadout_for(sh: Dictionary) -> Dictionary:
	var caps: Array = sh.get("capabilities", []) if sh.get("capabilities") is Array else []
	var sid := String(sh.get("id", ""))
	var want := {
		"search_radar": "sensor.radar.active",
		"optical": "sensor.optical",
		"ir": "sensor.ir",
	}
	var model_by_kind := {"search_radar": "YW-R9", "optical": "MS-OT2", "ir": "CH-IR2"}
	var mounts: Array = []
	var fallbacks: Array = []
	for kind in ["search_radar", "optical", "ir"]:
		var cap := String(want[kind])
		var has_cap := cap in caps
		if not has_cap:
			fallbacks.append(kind)
		mounts.append({
			"mount_id": "%s/%s" % [sid, kind], "ship_id": sid,
			"model": model_by_kind[kind], "kind": kind, "enabled": true,
			"destroyed": false, "mast_dependent": kind == "search_radar",
			"fallback": not has_cap,
			"notes": "transit sensor layer；fallback=%s" % str(not has_cap),
		})
	return {"mounts": mounts, "fallbacks": fallbacks}


func _authority_targets() -> Array:
	var out: Array = []
	for sid in EXPECTED_SHIP_IDS:
		if sid == selected_ship:
			continue
		var sh: Dictionary = ship_by_id.get(sid, {})
		if sh.is_empty():
			continue
		var st := ship_state(sid)
		var d: Dictionary = _ship_target_def(sh).duplicate(true)
		d["pos_km"] = st.get("pos_km", [])
		d["vel_kmps"] = _velocity_state(sid)
		out.append(d)
	for raw in ports:
		var pt: Dictionary = raw
		if String(pt.get("id", "")) == selected_ship:
			continue
		var ps := port_state(String(pt.get("id", "")))
		var d2: Dictionary = _port_target_def(pt).duplicate(true)
		d2["pos_km"] = ps.get("pos_km", [])
		d2["vel_kmps"] = ps.get("vel_kmps", [])
		out.append(d2)
	return out


func _build_snapshot() -> Dictionary:
	var obs_state := ship_state(selected_ship) if ship_by_id.has(selected_ship) else {}
	var targets := _authority_targets()
	return {
		"t": t,
		"observer": {"id": selected_ship,
			"pos_km": obs_state.get("pos_km", [0.0, 0.0, 0.0]),
			"vel_kmps": obs_state.get("vel_kmps", [0.0, 0.0, 0.0]),
			"attitude_quat": [0.0, 0.0, 0.0, 1.0],
			"attitude_source": "default_not_modeled",
			"angular_rate_dps": [0.0, 0.0, 0.0], "maneuver_g": 0.0,
			"mast_deployed": true, "emcon": false,
			"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0}},
		"targets": targets,
		"sun_illum": 1.0, "sun_dir": [1.0, 0.0, 0.0], "earth_albedo": 0.03,
		"jamming": 0.0, "shadow": false, "los": true,
	}


# ═══════════════════════════════════════════════════════════════════
# 3. 显式 API
# ═══════════════════════════════════════════════════════════════════

func select_ship(id: String) -> Dictionary:
	if not ship_by_id.has(id):
		_push_event("error", "select_ship unknown: " + id)
		return {"ok": false, "reason": "unknown_ship", "ship_id": id}
	_select_observer_internal(id)
	return {"ok": true, "reason": "", "observer": selected_ship,
		"warnings": (warnings.duplicate() as Array),
		"fallbacks": (_fallback_mounts.get(id, []) as Array).duplicate()}


func set_target(id: String) -> Dictionary:
	if not target_defs.has(id) or id == selected_ship:
		return {"ok": false, "reason": "unknown_target", "target_id": id}
	selected_target = id
	# 已存在的光学通道随目标重定向（显式 start_optical/stop_optical 仍可覆盖）。
	for kind in ["optical", "ir"]:
		if _active_channels.has(kind):
			_restart_channel(kind)
	_push_event("target", "target → %s (%s)" % [id, String((target_defs.get(id, {}) as Dictionary).get("name", id))])
	return {"ok": true, "reason": "", "target_id": id,
		"channels": _authority.channels_cache.duplicate(true) if _authority != null else []}


func start_optical(kind: String, target: String, opts := {}) -> Dictionary:
	if _authority == null:
		return {"ok": false, "reason": "not_ready"}
	var k := String(kind)
	if not (k in ["optical", "ir"]):
		return {"ok": false, "reason": "invalid_kind", "kind": kind}
	if target == "" or not target_defs.has(target) or target == selected_ship:
		return {"ok": false, "reason": "unknown_target", "target_id": target}
	var r: Dictionary = _authority.start_channel(k, target, opts if opts is Dictionary else {})
	if bool(r.get("ok", false)):
		_active_channels[k] = target
		if selected_target == "" or selected_target == selected_ship:
			selected_target = target
		_push_event("optical", "%s start → %s" % [k, target])
	return r


func stop_optical(kind := "", target := "") -> Dictionary:
	if _authority == null:
		return {"ok": false, "reason": "not_ready"}
	var stopped: Array = []
	for key in ["optical", "ir"]:
		var k := String(key)
		if kind != "" and k != kind:
			continue
		if target != "" and String(_active_channels.get(k, "")) != target:
			continue
		if _active_channels.has(k):
			_authority.stop_channel(k)
			_active_channels.erase(k)
			stopped.append(k)
	if stopped.is_empty():
		return {"ok": false, "reason": "no_matching_channel", "stopped": []}
	_push_event("optical", "stop → " + ",".join(stopped))
	return {"ok": true, "reason": "", "stopped": stopped}


## 真实雷达/EMCON 开关（shadow；只改本层 authority 挂载状态，不写 V15 sensor_on/emcon）。
func set_radar_enabled(on: bool) -> Dictionary:
	if _authority == null:
		return {"ok": false, "reason": "not_ready", "radar_enabled": false,
			"emcon": _emcon, "writes": {"track_table": false, "v15": false}}
	_radar_enabled = bool(on)
	_emcon = not _radar_enabled
	_apply_controls()
	_push_event("radar", "RADAR %s · EMCON=%s（shadow）" % [
		"ON" if _radar_enabled else "OFF", str(_emcon)])
	_rebuild(_empty_step_events())
	var exp: Dictionary = _exposure_view()
	return {"ok": true, "reason": "" if _radar_enabled else "radar_off_emcon",
		"radar_enabled": _radar_enabled, "emcon": _emcon,
		"exposure": exp, "writes": {"track_table": false, "v15": false}}


## 显式 EMCON（off 时恢复雷达，on 时等价 radar off）。
func set_emcon(on: bool) -> Dictionary:
	_emcon = bool(on)
	_radar_enabled = not _emcon
	_apply_controls()
	_push_event("emcon", "EMCON %s" % ("ON" if _emcon else "OFF"))
	_rebuild(_empty_step_events())
	return {"ok": true, "radar_enabled": _radar_enabled, "emcon": _emcon,
		"exposure": _exposure_view(), "writes": {"track_table": false, "v15": false}}


## 真实 IFF 询问（V2InformationWarfare MK-12）；不产生位置/接触，不自动判敌。
func iff_query(target_id: String) -> Dictionary:
	if _iff == null:
		return {"ok": false, "status": "not_ready", "target_id": target_id,
			"never_hostile": true, "writes_v15": false}
	if target_id == selected_ship or not target_defs.has(target_id):
		var miss := {"schema": SCHEMA_IFF, "ok": false, "target_id": target_id,
			"status": "unknown_target", "reason": "unknown_target",
			"identity": "unknown", "friend": false, "hostile": false,
			"never_hostile": true, "produces_contact": false,
			"writes_v15": false, "writes_track_table": false}
		return miss
	var td: Dictionary = target_defs.get(target_id, {})
	var code := String(td.get("iff_code", ""))
	var raw: Dictionary = _iff.interrogate_iff(target_id, ["3/A"],
		{"expected_codes": {"3/A": code}})
	var raw_status := String(raw.get("status", "unknown"))
	var identity := String(raw.get("identity", "unknown"))
	var status_norm := "unknown"
	if identity == "friend":
		status_norm = "friend"
	elif raw_status == "no_reply":
		status_norm = "no_reply"
	elif raw_status == "out_of_range":
		status_norm = "out_of_range"
	elif raw_status == "faulty_transponder":
		status_norm = "faulty"
	elif raw_status in ["blocked", "cooldown", "not_ready", "unknown_target"]:
		status_norm = raw_status if raw_status != "unknown_target" else "unknown"
	elif raw_status in ["captured", "crypto_mismatch", "timeout", "invalid_mode"]:
		status_norm = "unknown"
	var dist := 0.0
	var st := target_state(target_id)
	var ost := ship_state(selected_ship)
	if not st.is_empty() and not ost.is_empty():
		dist = _dist3(st.get("pos_km", []), ost.get("pos_km", []))
	var rec := {
		"schema": SCHEMA_IFF, "ok": status_norm != "not_ready",
		"ok_query": true,
		"target_id": target_id, "target_name": String(td.get("name", target_id)),
		"kind": String(td.get("kind", "ship")),
		"status": status_norm, "raw_status": raw_status,
		"identity": identity, "friend": identity == "friend",
		"hostile": false, "never_hostile": true,
		"level_support": 0, "produces_contact": false,
		"range_km": dist, "range_max_km": IFF_RANGE_KM,
		"reason": String(raw.get("reason", "")),
		"confidence": float(raw.get("confidence", 0.0)),
		"source": "V2InformationWarfare/MK-12",
		"shadow": true, "writes_v15": false, "writes_track_table": false,
		"t": t,
	}
	_iff_last = rec.duplicate(true)
	var replaced := false
	for i in range(_iff_results.size()):
		if _iff_results[i] is Dictionary and String((_iff_results[i] as Dictionary).get("target_id", "")) == target_id:
			_iff_results[i] = rec.duplicate(true)
			replaced = true
			break
	if not replaced:
		_iff_results.append(rec.duplicate(true))
	while _iff_results.size() > 32:
		_iff_results.pop_front()
	_iff_by_target[target_id] = rec.duplicate(true)
	if status_norm in ["no_reply", "faulty", "out_of_range", "blocked", "unknown"]:
		_add_warning("IFF %s: %s（不自动判敌）" % [target_id, status_norm])
	_push_event("iff", "%s → %s · identity=%s（never_hostile）" % [
		target_id, status_norm, identity])
	return rec


func iff_state(target_id := "") -> Dictionary:
	if target_id == "":
		return _iff_last.duplicate(true)
	return ((_iff_by_target.get(target_id, {}) as Dictionary).duplicate(true))


func step(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	var was_t := t
	t = minf(t + d, tof_s) if tof_s > 0.0 else t + d
	dt_last = t - was_t
	step_count += 1
	var events: Array = []
	if _authority != null:
		var snap := _build_snapshot()
		_last_snapshot = snap
		var av: Dictionary = _authority.step(d, snap)
		events = (av.get("events", []) as Array).duplicate(true)
	else:
		_build_authority()
		events = []
	if _iff != null:
		_iff.set_targets(_iff_target_rows())
		_iff.step(d)
	_rebuild(events)
	return _last_vm.duplicate(true)


func vm() -> Dictionary:
	# 只读构建当前 VM；确保 set_target/select_ship/start_optical 后无需 step 即可见。
	_rebuild(_empty_step_events())
	return _last_vm.duplicate(true)


func seek(t_s: float) -> Dictionary:
	t = clampf(float(t_s), 0.0, maxf(0.0, tof_s))
	dt_last = 0.0
	var vm_out := step(0.0)
	return vm_out


# ═══════════════════════════════════════════════════════════════════
# 4. VM 组装
# ═══════════════════════════════════════════════════════════════════

func _rebuild(step_events: Array) -> void:
	var av: Dictionary = _authority.vm_sensor() if _authority != null else {}
	var contacts_src: Array = av.get("advisory_contacts", []) if av.get("advisory_contacts") is Array else []
	var chans: Array = av.get("channels", []) if av.get("channels") is Array else []
	var radar_on := _radar_enabled and not _emcon
	if not radar_on:
		# 雷达关闭/EMCON：不展示旧雷达 advisory contacts；被动 VIS/IR 通道仍保留。
		contacts_src = []
	var ship_rows: Array = []
	for sid in EXPECTED_SHIP_IDS:
		var sh: Dictionary = ship_by_id.get(sid, {})
		if sh.is_empty():
			continue
		var st := ship_state(sid)
		ship_rows.append({
			"id": sid, "batch": String(sh.get("batch", "")),
			"name": String(sh.get("name", sid)), "role": String(sh.get("role", "")),
			"class": String(sh.get("class", "")), "side": String(sh.get("side", "friend")),
			"pos_km": st.get("pos_km", [0.0, 0.0, 0.0]),
			"vel_kmps": st.get("vel_kmps", [0.0, 0.0, 0.0]),
			"range_km": float(st.get("range_km", 0.0)),
			"observer": sid == selected_ship,
			"selected": sid == selected_target,
			"loadout_fallbacks": (_fallback_mounts.get(sid, []) as Array).duplicate(),
		})
	var port_rows: Array = []
	for raw in ports:
		var pt: Dictionary = raw
		var st2 := port_state(String(pt.get("id", "")))
		port_rows.append({
			"id": String(pt.get("id", "")), "batch": String(pt.get("batch", "")),
			"name": String(pt.get("name", "")), "lpoint": String(pt.get("lpoint", "")),
			"port_id": String(pt.get("port_id", "")), "status": String(pt.get("status", "")),
			"pos_km": st2.get("pos_km", [0.0, 0.0, 0.0]),
			"vel_kmps": st2.get("vel_kmps", [0.0, 0.0, 0.0]),
			"range_km": float(st2.get("range_km", 0.0)),
			"selected": String(pt.get("id", "")) == selected_target,
		})
	var target_rows: Array = _target_rows(contacts_src, chans)
	var contacts: Array = []
	for raw in contacts_src:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = (raw as Dictionary).duplicate(true)
		var tid := _target_id_of(c)
		c["target_id"] = tid
		c["kind"] = _kind_of(tid)
		c["name"] = String((target_defs.get(tid, {}) as Dictionary).get("name", tid))
		c["level_support"] = int(c.get("level", 0))
		c["selected"] = tid == selected_target
		contacts.append(c)
	var channels: Array = []
	for raw in chans:
		if raw is Dictionary:
			var ch: Dictionary = (raw as Dictionary).duplicate(true)
			var tid2 := String(ch.get("target_id", ""))
			ch["kind"] = "port" if _is_port(tid2) else "ship"
			ch["name"] = String((target_defs.get(tid2, {}) as Dictionary).get("name", tid2))
			ch["selected"] = tid2 == selected_target
			channels.append(ch)
	var levels := _levels(target_rows, channels)
	var vis := _find_channel(channels, "optical", selected_target)
	var ir := _find_channel(channels, "ir", selected_target)
	var opt_channels: Array = []
	for raw in channels:
		if raw is Dictionary:
			var k := String((raw as Dictionary).get("channel", ""))
			if k in ["optical", "ir"]:
				opt_channels.append((raw as Dictionary).duplicate(true))
	var opt_summary: Dictionary = av.get("optical_summary", {}) if av.get("optical_summary") is Dictionary else {}
	var optical := {
		"backend": String(opt_summary.get("backend", "optical_ir")),
		"available_backends": (opt_summary.get("available_backends", []) as Array).duplicate() if opt_summary.get("available_backends") is Array else [],
		"selected_target": selected_target,
		"vis": vis, "ir": ir,
		"summary": opt_summary,
		"channels": opt_channels,
	}
	var iff_vm: Dictionary = _iff_vm()
	var exposure: Dictionary = _exposure_view(av)
	var recent: Array = []
	for raw in _event_log:
		recent.append(raw)
	if recent.size() > MAX_EVENTS:
		recent = recent.slice(recent.size() - MAX_EVENTS, recent.size())
	for raw in step_events:
		if raw is Dictionary:
			var ev: Dictionary = (raw as Dictionary).duplicate(true)
			ev["t"] = t
			recent.append(ev)
			_event_log.append(ev)
	while _event_log.size() > MAX_EVENTS:
		_event_log.pop_front()
	_last_vm = {
		"schema": SCHEMA_VM,
		"mode": MODE,
		"authoritative": false,
		"ready": ready,
		"t": t, "dt": dt_last, "step_count": step_count,
		"tof_s": tof_s, "progress": clampf(t / maxf(1.0, tof_s), 0.0, 1.0) if tof_s > 0.0 else 0.0,
		"phase": _phase(),
		"frame": "bary_rot", "units": "km,km/s,s",
		"observer_ship": selected_ship,
		"observer": {
			"id": selected_ship,
			"name": String((ship_by_id.get(selected_ship, {}) as Dictionary).get("name", selected_ship)),
			"batch": String((ship_by_id.get(selected_ship, {}) as Dictionary).get("batch", "")),
			"pos_km": (ship_state(selected_ship).get("pos_km", []) as Array),
			"vel_kmps": (ship_state(selected_ship).get("vel_kmps", []) as Array),
		},
		"selected_target": selected_target,
		"ships": ship_rows, "ports": port_rows, "targets": target_rows,
		"contacts": contacts, "channels": channels,
		"optical": optical, "levels": levels,
		"radar_enabled": radar_on, "emcon": _emcon,
		"radar": (av.get("radar", {}) as Dictionary).duplicate(true) if av.get("radar") is Dictionary else {},
		"exposure": exposure,
		"iff": iff_vm,
		"events": recent, "warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"notes": notes.duplicate(),
		"counts": {
			"contacts": contacts.size(), "channels": channels.size(),
			"locked": _count_status(channels, "locked"),
			"vis": _count_channel(channels, "optical"), "ir": _count_channel(channels, "ir"),
			"ports": ports.size(), "ships": ships.size(),
		},
		"writes": {"track_table": false, "v15": false},
		"authority": {
			"schema": String(av.get("schema", "")),
			"mode": String(av.get("mode", "")),
			"optical_backend": String(av.get("optical_backend", "")),
			"counts": (av.get("counts", {}) as Dictionary).duplicate() if av.get("counts") is Dictionary else {},
			"summary": _authority_summary(av),
		},
	}


func _iff_vm() -> Dictionary:
	var results: Array = []
	for raw in _iff_results:
		if raw is Dictionary:
			results.append((raw as Dictionary).duplicate(true))
	var by_target: Dictionary = {}
	for raw in results:
		var r: Dictionary = raw
		by_target[String(r.get("target_id", ""))] = r.duplicate(true)
	var counts := {"friend": 0, "unknown": 0, "no_reply": 0, "faulty": 0,
		"out_of_range": 0, "blocked": 0, "hostile": 0}
	for raw in results:
		var r2: Dictionary = raw
		var st := String(r2.get("status", "unknown"))
		if counts.has(st):
			counts[st] = int(counts.get(st, 0)) + 1
		else:
			counts["unknown"] = int(counts.get("unknown", 0)) + 1
	return {
		"schema": SCHEMA_IFF,
		"available": _iff != null,
		"model": "MK-12",
		"range_km": IFF_RANGE_KM,
		"enabled": _iff != null,
		"last": _iff_last.duplicate(true),
		"results": results,
		"by_target": by_target,
		"summary": {
			"total": results.size(), "friend": int(counts.get("friend", 0)),
			"unknown": int(counts.get("unknown", 0)),
			"no_reply": int(counts.get("no_reply", 0)),
			"faulty": int(counts.get("faulty", 0)),
			"out_of_range": int(counts.get("out_of_range", 0)),
			"hostile": 0,
		},
		"hostile": 0, "hostile_allowed": false, "never_hostile": true,
		"auto_hostile": false, "produces_contact": false, "produces_position": false,
		"writes_v15": false, "writes_track_table": false,
	}


func _exposure_view(av: Dictionary = {}) -> Dictionary:
	var on := _radar_enabled and not _emcon
	if not on:
		return {"exposed": false, "radar_on": false, "emcon": _emcon,
			"reason": "radar_off_emcon", "shadow": true, "writes_v15": false}
	var radar: Dictionary = av.get("radar", {}) if av.get("radar") is Dictionary else {}
	var exp: Dictionary = radar.get("exposure", {}) if radar.get("exposure") is Dictionary else {}
	var out: Dictionary = exp.duplicate(true)
	out["radar_on"] = true
	out["emcon"] = _emcon
	out["shadow"] = true
	out["writes_v15"] = false
	if not out.has("exposed"):
		out["exposed"] = bool(out.get("elint_detectable", false))
	return out


func _target_rows(contacts: Array, channels: Array) -> Array:
	var rows: Array = []
	for sid in EXPECTED_SHIP_IDS:
		if sid == selected_ship:
			continue
		rows.append(_target_row(sid, contacts, channels))
	for raw in ports:
		var pid := String((raw as Dictionary).get("id", ""))
		rows.append(_target_row(pid, contacts, channels))
	return rows


func _target_row(id: String, contacts: Array, channels: Array) -> Dictionary:
	var d: Dictionary = target_defs.get(id, {}) if target_defs.get(id) is Dictionary else {}
	var st := target_state(id)
	var contact := _find_contact(contacts, id)
	var vis := _find_channel(channels, "optical", id)
	var ir := _find_channel(channels, "ir", id)
	var level := int(contact.get("level_support", contact.get("level", 0)))
	if not vis.is_empty():
		level = maxi(level, int(vis.get("level_support", 0)))
	if not ir.is_empty():
		level = maxi(level, int(ir.get("level_support", 0)))
	var reason := ""
	if contact.is_empty() and vis.is_empty() and ir.is_empty():
		reason = "no_contact"
	if not vis.is_empty() and String(vis.get("status", "")) == "lost":
		reason = String(vis.get("reason", "lost"))
	return {
		"id": id, "batch": String(d.get("batch", "")), "name": String(d.get("name", id)),
		"kind": String(d.get("kind", "ship")), "side": String(d.get("side", "friend")),
		"pos_km": st.get("pos_km", [0.0, 0.0, 0.0]),
		"vel_kmps": _velocity_state(id),
		"range_km": float(_dist3(st.get("pos_km", []), ship_state(selected_ship).get("pos_km", []))),
		"level": level, "level_support": level,
		"contact_level": int(contact.get("level_support", contact.get("level", 0))),
		"optical_level": int(vis.get("level_support", 0)) if not vis.is_empty() else 0,
		"visible": not vis.is_empty() or not ir.is_empty(),
		"vis_status": String(vis.get("status", "off")) if not vis.is_empty() else "off",
		"ir_status": String(ir.get("status", "off")) if not ir.is_empty() else "off",
		"selected": id == selected_target,
		"reason": reason,
	}


func _levels(targets: Array, channels: Array) -> Dictionary:
	var by_target: Dictionary = {}
	var counts: Dictionary = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	var max_level := 0
	for raw in targets:
		var tr: Dictionary = raw
		var lv := int(tr.get("level", 0))
		by_target[String(tr.get("id", ""))] = {
			"level": lv, "contact_level": int(tr.get("contact_level", 0)),
			"optical_level": int(tr.get("optical_level", 0)),
			"range_km": float(tr.get("range_km", 0.0)),
			"reason": String(tr.get("reason", "")),
		}
		counts[str(lv)] = int(counts.get(str(lv), 0)) + 1
		max_level = maxi(max_level, lv)
	return {"schema": "transit_sensor_levels.v1", "by_target": by_target,
		"counts": counts, "max_level": max_level,
		"labels": {0: "UNKNOWN", 1: "BEARING", 2: "POSITION", 3: "CLASSIFIED", 4: "IDENTIFIED"}}


func _authority_summary(av: Dictionary) -> Dictionary:
	if av.is_empty():
		return {}
	return {
		"ready": bool(av.get("ready", false)),
		"observer": String((av.get("observer", {}) as Dictionary).get("id", "")) if av.get("observer") is Dictionary else "",
		"contacts": (av.get("counts", {}) as Dictionary).get("contacts", 0) if av.get("counts") is Dictionary else 0,
		"channels": (av.get("counts", {}) as Dictionary).get("channels", 0) if av.get("counts") is Dictionary else 0,
		"optical_backend": String(av.get("optical_backend", "")),
		"writes": (av.get("writes", {}) as Dictionary).duplicate() if av.get("writes") is Dictionary else {"track_table": false, "v15": false},
	}


func _phase() -> String:
	if tof_s <= 0.0:
		return "not_ready"
	if t <= 1.0:
		return "departure"
	if t >= tof_s - 1.0:
		return "arrival"
	return "cruise"


func _find_contact(contacts: Array, id: String) -> Dictionary:
	for raw in contacts:
		if raw is Dictionary and _target_id_of(raw as Dictionary) == id:
			return raw as Dictionary
	return {}


func _target_id_of(c: Dictionary) -> String:
	if c.has("target_id"):
		return String(c.get("target_id", ""))
	if c.has("entity_id"):
		return String(c.get("entity_id", ""))
	return String(c.get("id", ""))


func _kind_of(id: String) -> String:
	for raw in ports:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
			return "port"
	return "ship"


func _is_port(id: String) -> bool:
	return _kind_of(id) == "port"


func _find_channel(channels: Array, kind: String, id: String) -> Dictionary:
	for raw in channels:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		if String(ch.get("channel", ch.get("kind", ""))) == kind and String(ch.get("target_id", "")) == id:
			return ch
	return {}


func _count_status(channels: Array, status: String) -> int:
	var n := 0
	for raw in channels:
		if raw is Dictionary and String((raw as Dictionary).get("status", "")) == status:
			n += 1
	return n


func _count_channel(channels: Array, kind: String) -> int:
	var n := 0
	for raw in channels:
		if raw is Dictionary and String((raw as Dictionary).get("channel", "")) == kind:
			n += 1
	return n


func _ensure_auto_channels() -> void:
	if _authority == null:
		return
	if selected_target == "" or selected_target == selected_ship:
		var tid := _first_target_id()
		if tid == "":
			return
		selected_target = tid
	if _active_channels.is_empty():
		start_optical("optical", selected_target)
		start_optical("ir", selected_target)


func _restart_channel(kind: String) -> void:
	if _authority == null or not _active_channels.has(kind):
		return
	_authority.stop_channel(kind)
	var target := selected_target
	var r: Dictionary = _authority.start_channel(kind, target)
	if bool(r.get("ok", false)):
		_active_channels[kind] = target
	else:
		_active_channels.erase(kind)


# ═══════════════════════════════════════════════════════════════════
# 5. 事件 / 警告 / 工具
# ═══════════════════════════════════════════════════════════════════

var events: Array = []

func _empty_step_events() -> Array:
	return []


func _push_event(kind: String, msg: String) -> void:
	var ev := {"t": t, "kind": kind, "message": msg}
	_events.append(ev)
	_event_log.append(ev)
	while _event_log.size() > MAX_EVENTS:
		_event_log.pop_front()
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()


func _add_warning(msg: String) -> void:
	var m := String(msg)
	if _warn_seen.has(m):
		return
	_warn_seen[m] = true
	warnings.append(m)


# ── JSON / 几何工具 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return vm()


func summary() -> Dictionary:
	var v := vm()
	return {
		"schema": SCHEMA_VM, "ready": ready, "mode": MODE,
		"observer_ship": selected_ship, "selected_target": selected_target,
		"t": t, "tof_s": tof_s, "phase": _phase(),
		"contacts": v.get("counts", {}).get("contacts", 0),
		"channels": v.get("counts", {}).get("channels", 0),
		"writes_track_table": false, "writes_v15": false,
	}


func _arr3(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return [float(a[0]), float(a[1]), float(a[2])]
		if a.size() == 2:
			return [float(a[0]), float(a[1]), 0.0]
	if v is Vector3:
		var vv: Vector3 = v
		return [vv.x, vv.y, vv.z]
	return [0.0, 0.0, 0.0]


func _add3(a: Variant, b: Variant) -> Array:
	var x := _arr3(a)
	var y := _arr3(b)
	return [x[0] + y[0], x[1] + y[1], x[2] + y[2]]


func _sub3(a: Variant, b: Variant) -> Array:
	var x := _arr3(a)
	var y := _arr3(b)
	return [x[0] - y[0], x[1] - y[1], x[2] - y[2]]


func _len3(a: Variant) -> float:
	var x := _arr3(a)
	return sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2])


func _dist3(a: Variant, b: Variant) -> float:
	return _len3(_sub3(a, b))
