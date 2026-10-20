extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2C：GameSession（编排层；新文件）
#
# - 组合 TimeService / EventBus / WorldState / OrderService / CommsService；
# - boot(config)（含示例 seed：实体/链路/订单；不进入关卡）；
# - tick(dt)（时间→订单/通信推进；事件发布；bus 不自动写 world）；
# - 包装 issue_order/authorize/begin/complete/abort、send_comms、set_link；
# - snapshot() 只读；save_state()/load_state() **内存 JSON**（seed+操作日志重放，不写盘）；
# - DbC：单写者/时间单调/订单-通信一致；失败不伪造。
# 不实现物理/UI/剧情；不接旧场景。
# ═══════════════════════════════════════════════════════════════════

const TimeService := preload("res://scripts/core/time_service.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")
const WorldState := preload("res://scripts/core/world_state.gd")
const OrderService := preload("res://scripts/core/order_service.gd")
const CommsService := preload("res://scripts/core/comms_service.gd")
const TrackTableScript := preload("res://scripts/core/track_table.gd")
const StoryStateScript := preload("res://scripts/core/story_state.gd")
const SensorServiceScript := preload("res://scripts/core/sensor_service.gd")
const PortServiceScript := preload("res://scripts/core/port_service.gd")
const CombatServiceScript := preload("res://scripts/core/combat_service.gd")
const DamageServiceScript := preload("res://scripts/core/damage_service.gd")
const PhysicsWorldScript := preload("res://scripts/core/physics_world.gd")
const SignalServiceScript := preload("res://scripts/core/signal_service.gd")
const FacilityRegistryScript := preload("res://scripts/core/facility_registry.gd")
const TransponderServiceScript := preload("res://scripts/core/transponder_service.gd")

const SCHEMA := "v17.game_session.v1"
const SAVE_SCHEMA := "v17.game_session_save.v1"
const VERSION := "1.0.0"
const WRITER_DEFAULT := "session"
const ACTIVE_ORDER_STATES := ["ISSUED", "TRANSMITTING", "DELIVERED", "QUEUED",
	"PENDING_EFFECT", "AUTHORIZED", "EXECUTING"]

var ready := false
var booted := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var writer := WRITER_DEFAULT
var time = null
var bus = null
var world = null
var orders = null
var comms = null
var track_table = null
var story_state = null
var sensor_service = null
var port_service = null
var combat_service = null
var damage_service = null
var physics_world_service = null
var signal_service = null
var facility_registry = null
var transponder_service = null

var _track_enabled := false
var _sensor_enabled := false
var _port_enabled := false
var _combat_enabled := false
var _damage_enabled := false
var _physics_enabled := false
var _signal_enabled := false
var _facility_enabled := false
var _transponder_enabled := false
var _last_signal_route: Dictionary = {}
var _signal_missing_meta_warned: Dictionary = {}
var _damage_applied_shots: Dictionary = {}
var _story_enabled := false
var _track_writer := ""
var _last_track_t := 0.0
var _last_story_revision := 0
var _last_bus_routed_index := 0
var _routed_seqs: Dictionary = {}
var _sensor_track_map: Dictionary = {}
var _sensor_target_meta: Dictionary = {}

var _seed: Dictionary = {}
var _log: Array = []
var _replaying := false
var _standalone: Dictionary = {}   # delivery_id -> {from,to,mode,text_key,sent_t}
var _tick_events: Array = []
var _last_time_s := 0.0

func _init(config := {}) -> void:
	boot(config)

# ── 示例 seed（不进入关卡）──────────────────────────────────────

func _demo_seed() -> Dictionary:
	return {
		"time": {"t_s": 0.0, "epoch_s": 760.8, "scale": 1.0},
		"writer": WRITER_DEFAULT,
		"entities": [
			{"id": "apsis", "batch": "1000", "kind": "ship", "name": "远地点",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
				"flags": {"flagship": true}},
			{"id": "harmattan", "batch": "1001", "kind": "ship", "name": "哈马丹",
				"pos_km": [20.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0], "flags": {}},
			{"id": "l1_station", "batch": "3100", "kind": "station", "name": "L1 港",
				"pos_km": [0.0, 0.0, 10.0], "vel_kmps": [0.0, 0.0, 0.0],
				"flags": {"fixed": true}},
		],
		"nodes": [
			{"id": "apsis", "name": "远地点", "role": "flagship"},
			{"id": "harmattan", "name": "哈马丹", "role": "escort"},
			{"id": "l1_station", "name": "L1 港", "role": "station"},
		],
		"links": [
			{"a": "apsis", "b": "harmattan", "mode": "LD"},
			{"a": "harmattan", "b": "l1_station", "mode": "LR"},
		],
		"orders": [],
		"order_mode": "LD",
		"comms_text_key": "COMMS_SENT",
		"delivery_delay_s": 1.0,
	}

func _normalize_seed(config: Dictionary) -> Dictionary:
	if config.is_empty():
		return _demo_seed()
	var seed := _demo_seed()
	for key in ["time", "writer", "entities", "nodes", "links", "orders",
			"order_mode", "comms_text_key", "delivery_delay_s", "auth_required",
			"track_table", "story_state", "sensor_service", "port_service", "combat_service", "damage_service", "physics_world", "signal_service", "facility_registry", "transponder_service"]:
		if config.has(key):
			seed[key] = config[key]
	return seed

# ── boot ────────────────────────────────────────────────────────

func boot(config := {}) -> Dictionary:
	ready = false
	booted = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	_tick_events = []
	_standalone = {}
	_log = []
	_last_time_s = 0.0
	track_table = null
	story_state = null
	sensor_service = null
	port_service = null
	combat_service = null
	damage_service = null
	physics_world_service = null
	signal_service = null
	facility_registry = null
	transponder_service = null
	_last_signal_route = {}
	_signal_missing_meta_warned = {}
	_damage_applied_shots = {}
	_track_enabled = false
	_story_enabled = false
	_sensor_enabled = false
	_port_enabled = false
	_combat_enabled = false
	_damage_enabled = false
	_track_writer = ""
	_last_track_t = 0.0
	_last_story_revision = 0
	_last_bus_routed_index = 0
	_routed_seqs = {}
	_sensor_track_map = {}
	_sensor_target_meta = {}
	_seed = _normalize_seed(config if config is Dictionary else {})
	_seed = _json_norm(_seed)
	writer = String(_seed.get("writer", WRITER_DEFAULT))
	time = TimeService.new(_seed.get("time", {}) if _seed.get("time") is Dictionary else {})
	bus = EventBus.new()
	world = WorldState.new({"writer": writer, "time": time, "bus": bus})
	comms = CommsService.new({
		"nodes": (_seed.get("nodes", []) as Array).duplicate(true),
		"links": (_seed.get("links", []) as Array).duplicate(true),
	})
	orders = OrderService.new({
		"entities": _entities_map(),
		"comms": comms,
		"mode": String(_seed.get("order_mode", "LD")),
		"delivery_delay_s": float(_seed.get("delivery_delay_s", 1.0)),
		"require_authorizer": false,
		"comms_text_key": String(_seed.get("comms_text_key", "COMMS_SENT")),
	})
	_setup_optional_components()
	var extra_ok := true
	if _track_enabled and track_table != null and not bool(track_table.ready):
		extra_ok = false
	if _story_enabled and story_state != null and not bool(story_state.ready):
		extra_ok = false
	if _sensor_enabled and sensor_service != null and not bool(sensor_service.ready):
		extra_ok = false
	if _port_enabled and port_service != null and not bool(port_service.ready):
		extra_ok = false
	if _combat_enabled and combat_service != null and not bool(combat_service.ready):
		extra_ok = false
	if _damage_enabled and damage_service != null and not bool(damage_service.ready):
		extra_ok = false
	if _physics_enabled and physics_world_service != null and not bool(physics_world_service.ready):
		extra_ok = false
	if _signal_enabled and signal_service != null and not bool(signal_service.ready):
		extra_ok = false
	if _facility_enabled and facility_registry != null and not bool(facility_registry.ready):
		extra_ok = false
	if _transponder_enabled and transponder_service != null and not bool(transponder_service.ready):
		extra_ok = false
	if not bool(time.ready) or not bool(bus.ready) or not bool(world.ready) \
			or not bool(orders.ready) or not bool(comms.ready) or not extra_ok:
		errors.append("session 组件未就绪：time=%s bus=%s world=%s orders=%s comms=%s" % [
			str(time.ready), str(bus.ready), str(world.ready),
			str(orders.ready), str(comms.ready)])
		return _result(false)
	# seed 实体（session 是唯一写者：bus 发事件 + world 显式 apply）
	for raw in (_seed.get("entities", []) as Array):
		if not (raw is Dictionary):
			continue
		var ent: Dictionary = (raw as Dictionary).duplicate(true)
		var eid := String(ent.get("id", ""))
		var ev: Dictionary = _mk_event("entity.spawn", "", {"entity": ent})
		var pub: Dictionary = bus.publish(ev)
		if not bool(pub.get("ok", false)):
			errors.append("seed 实体事件失败：" + eid)
			continue
		var ap: Dictionary = world.apply(pub.get("event", {}), writer)
		if not bool(ap.get("ok", false)):
			errors.append("seed 实体应用失败：%s（%s）" % [eid, str(ap.get("reason", ""))])
	# seed 订单（可选）
	for raw_o in (_seed.get("orders", []) as Array):
		if not (raw_o is Dictionary):
			continue
		var spec: Dictionary = raw_o
		var draft: Dictionary = orders.create_draft(
			String(spec.get("action", "hold")), String(spec.get("issuer_id", "")),
			spec.get("target_ids", []), spec.get("params", {}),
			spec.get("opts", {}))
		if not bool(draft.get("ok", false)):
			errors.append("seed 订单创建失败：" + str(draft.get("reason", "")))
			continue
		if bool(spec.get("issue", false)):
			var iss: Dictionary = orders.issue(String((draft.get("order", {}) as Dictionary).get("order_id", "")))
			if not bool(iss.get("ok", false)):
				warnings.append("seed 订单 issue 失败：" + str(iss.get("reason", "")))
	_flush_order_events()
	if story_state != null and now_s() > 0.0:
		story_state.set_time(now_s())
	if track_table != null:
		_track_writer = String(track_table.current_writer())
		_last_track_t = float(track_table.t)
		_routed_seqs = {}
	if story_state != null:
		_last_story_revision = int(story_state.revision)
	if sensor_service != null:
		sensor_service.t = now_s()
	if port_service != null:
		port_service.t_s = now_s()
	if combat_service != null:
		combat_service.t = now_s()
	if damage_service != null:
		damage_service.t = now_s()
	if physics_world_service != null:
		physics_world_service.set_time(now_s()) if now_s() > 0.0 else null
	if signal_service != null:
		signal_service.t = now_s()
	if transponder_service != null:
		transponder_service.set_time(now_s())
	_damage_applied_shots = {}
	_last_bus_routed_index = bus.count()
	_flush_component_events()
	_last_bus_routed_index = bus.count()
	_last_time_s = time.now_s()
	booted = true
	ready = errors.is_empty()
	return _result(ready)

func _entities_map() -> Dictionary:
	var out := {}
	for raw in (_seed.get("entities", []) as Array):
		if raw is Dictionary:
			var ent: Dictionary = raw
			out[String(ent.get("id", ""))] = {"name": String(ent.get("name", ent.get("id", ""))),
				"role": String(ent.get("kind", ""))}
	return out

## 可选组件：boot config 里 track_table / story_state 为 true 或配置字典才创建；
## 缺省（或无）则退化为不组合。
func _setup_optional_components() -> void:
	_track_enabled = false
	_story_enabled = false
	var tt = _seed.get("track_table", null)
	var tt_on := (tt is Dictionary) or (tt is bool and bool(tt))
	if tt_on:
		var cfg: Dictionary = {}
		if tt is Dictionary:
			cfg = (tt as Dictionary).duplicate(true)
		if not cfg.has("writer_id"):
			cfg["writer_id"] = writer + "_fusion"
		track_table = TrackTableScript.new(cfg)
		if not bool(track_table.ready):
			errors.append("track_table 未就绪")
		else:
			_track_enabled = true
			_track_writer = String(track_table.current_writer())
	var ss = _seed.get("story_state", null)
	var ss_on := (ss is Dictionary) or (ss is bool and bool(ss))
	if ss_on:
		var scfg: Dictionary = {} if (ss is bool) else (ss as Dictionary).duplicate(true)
		story_state = StoryStateScript.new(scfg)
		if not bool(story_state.ready):
			errors.append("story_state 未就绪：" + str(story_state.errors))
		else:
			_story_enabled = true
	var sn = _seed.get("sensor_service", null)
	var sn_on := (sn is Dictionary) or (sn is bool and bool(sn))
	if sn_on:
		var sncfg: Dictionary = {} if (sn is bool) else (sn as Dictionary).duplicate(true)
		sensor_service = SensorServiceScript.new(sncfg)
		if not bool(sensor_service.ready):
			errors.append("sensor_service 未就绪：" + str(sensor_service.errors))
		else:
			_sensor_enabled = true
			var tlist: Array = sncfg.get("targets", []) if sncfg.get("targets") is Array else []
			for raw_t in tlist:
				if not (raw_t is Dictionary):
					continue
				var tm: Dictionary = raw_t
				var tid := String(tm.get("id", tm.get("target_id", "")))
				if tid == "":
					continue
				_sensor_target_meta[tid] = {
					"entity_id": String(tm.get("entity_id", "")),
					"batch": String(tm.get("batch", "")),
				}
	var po = _seed.get("port_service", null)
	var po_on := (po is Dictionary) or (po is bool and bool(po))
	if po_on:
		var pcfg: Dictionary = _demo_port_config() if (po is bool) else (po as Dictionary).duplicate(true)
		port_service = PortServiceScript.new(pcfg)
		if not bool(port_service.ready):
			errors.append("port_service 未就绪：" + str(port_service.errors))
		else:
			_port_enabled = true
	var co = _seed.get("combat_service", null)
	var co_on := (co is Dictionary) or (co is bool and bool(co))
	if co_on:
		var ccfg: Dictionary = {} if (co is bool) else (co as Dictionary).duplicate(true)
		combat_service = CombatServiceScript.new(ccfg)
		if not bool(combat_service.ready):
			errors.append("combat_service 未就绪：" + str(combat_service.errors))
		else:
			_combat_enabled = true
	var dmg = _seed.get("damage_service", null)
	var dmg_on := (dmg is Dictionary) or (dmg is bool and bool(dmg))
	if dmg_on:
		var dcfg: Dictionary = _demo_damage_config() if (dmg is bool) else (dmg as Dictionary).duplicate(true)
		damage_service = DamageServiceScript.new(dcfg)
		if not bool(damage_service.ready):
			errors.append("damage_service 未就绪：" + str(damage_service.errors))
		else:
			_damage_enabled = true
	var sig = _seed.get("signal_service", null)
	var sig_on := (sig is Dictionary) or (sig is bool and bool(sig))
	if sig_on:
		var scfg: Dictionary = _demo_signal_config() if (sig is bool) else _signal_config(sig as Dictionary)
		signal_service = SignalServiceScript.new(scfg)
		if not bool(signal_service.ready):
			errors.append("signal_service 未就绪：" + str(signal_service.errors))
		else:
			_signal_enabled = true
			# 允许 signal targets 自带 entity_id/batch：并入 target_meta（sensor 元数据优先，不覆盖）
			for raw_st in (scfg.get("targets", []) as Array):
				if not (raw_st is Dictionary):
					continue
				var sm: Dictionary = raw_st
				var sid := String(sm.get("id", sm.get("target_id", "")))
				if sid == "":
					continue
				var meta_cur: Dictionary = _sensor_target_meta.get(sid, {})
				var e_new := String(sm.get("entity_id", ""))
				var b_new := String(sm.get("batch", ""))
				if String(meta_cur.get("entity_id", "")) == "" and e_new != "":
					meta_cur["entity_id"] = e_new
				if String(meta_cur.get("batch", "")) == "" and b_new != "":
					meta_cur["batch"] = b_new
				if not meta_cur.is_empty():
					_sensor_target_meta[sid] = meta_cur
	var fac = _seed.get("facility_registry", null)
	var fac_on := (fac is Dictionary) or (fac is bool and bool(fac))
	if fac_on:
		var fcfg: Dictionary = {} if (fac is bool) else (fac as Dictionary).duplicate(true)
		facility_registry = FacilityRegistryScript.new(fcfg)
		if not bool(facility_registry.ready):
			errors.append("facility_registry 未就绪：" + str(facility_registry.errors))
		else:
			_facility_enabled = true
	var txp = _seed.get("transponder_service", null)
	var txp_on := (txp is Dictionary) or (txp is bool and bool(txp))
	if txp_on:
		var tcfg: Dictionary = {} if (txp is bool) else (txp as Dictionary).duplicate(true)
		if facility_registry != null:
			tcfg["facility_registry"] = facility_registry
		transponder_service = TransponderServiceScript.new(tcfg)
		if not bool(transponder_service.ready):
			errors.append("transponder_service 未就绪：" + str(transponder_service.errors))
		else:
			_transponder_enabled = true
	var pw = _seed.get("physics_world", null)
	var pw_on := (pw is Dictionary) or (pw is bool and bool(pw))
	if pw_on:
		var pwcfg: Dictionary = {} if (pw is bool) else (pw as Dictionary).duplicate(true)
		physics_world_service = PhysicsWorldScript.new(pwcfg)
		if not bool(physics_world_service.ready):
			errors.append("physics_world 未就绪：" + str(physics_world_service.errors))
		else:
			_physics_enabled = true
			_seed_physics_entities(pwcfg)

## 示例港口配置（boot 时 port_service=true 使用；不进入关卡）。
func _demo_port_config() -> Dictionary:
	return {"ports": [
		{"id": "l1_meridian_05", "name": "L1 Meridian", "berths": ["B1", "B2"],
			"drydock_slots": 1, "tugs": ["TUG1"],
			"fuel_capacity_t": 1000.0, "fuel_available_t": 1000.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C1", "require_permit": true,
			"services": ["refuel", "repair", "tow", "shuttle"]},
	]}

## 示例损管配置（boot damage_service=true 使用；按 damage_l1 档案）。
func _demo_damage_config() -> Dictionary:
	return {"content_path": "res://framework/content/damage_l1.json",
		"ships": ["apsis", "harmattan", "ferry", "watchtower", "deepwell"],
		"default_ship": "apsis"}

## 示例 SignalService 配置（boot signal_service=true）：observer/targets 来自 seed 实体；
## 再加一个照明目标 L1（可见光灯语用）与一个遮挡目标 O1。
func _demo_signal_config() -> Dictionary:
	var ents: Array = _seed.get("entities", [])
	var observer_pos: Array = [0.0, 0.0, 0.0]
	var observer_id := "session_ship"
	var targets: Array = []
	for raw in ents:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var id := String(e.get("id", ""))
		if id == "":
			continue
		var pos = e.get("pos_km", [0.0, 0.0, 0.0])
		if not (pos is Array) or (pos as Array).size() < 3:
			pos = [0.0, 0.0, 0.0]
		if id == "apsis":
			observer_pos = (pos as Array).duplicate()
			observer_id = "apsis"
		else:
			targets.append({"id": id, "pos_km": (pos as Array).duplicate(),
				"emissions": [{"type": "radar", "model": "YW-R9",
					"signature_name": "YW-R9", "active": true, "silent": false,
					"lpi": false, "frequency_mhz": 9500.0, "power_dbm": 90.0,
					"gain_tx_dbi": 30.0, "prf_hz": 1200.0, "scan_period_s": 1.0}]})
	targets.append({"id": "L1", "pos_km": [observer_pos[0], observer_pos[1] + 20.0,
		observer_pos[2]]})
	targets.append({"id": "O1", "pos_km": [observer_pos[0], observer_pos[1] + 20.0,
		observer_pos[2]], "occluded": true})
	return {"observer": {"id": observer_id, "pos_km": observer_pos},
		"targets": targets,
		"elint": {"enabled": true, "range_km": 60000.0, "refresh_s": 1.0}}

## 兼容 boot config：emitters[] → 目标 emissions；light_codes → codes_content；
## month/time 原样保留（服务端可扩展），不写 UI。
func _signal_config(raw: Dictionary) -> Dictionary:
	var c: Dictionary = raw.duplicate(true)
	if c.get("light_codes") is Dictionary and not c.has("codes_content"):
		c["codes_content"] = (c.get("light_codes") as Dictionary).duplicate(true)
	var emitters = c.get("emitters", null)
	if emitters is Array:
		var targets: Array = c.get("targets", []) if c.get("targets") is Array else []
		for raw_e in (emitters as Array):
			if not (raw_e is Dictionary):
				continue
			var em: Dictionary = (raw_e as Dictionary).duplicate(true)
			var tid := String(em.get("id", em.get("target_id", "")))
			if tid == "":
				continue
			var found := false
			for i in range(targets.size()):
				if targets[i] is Dictionary and String((targets[i] as Dictionary).get("id", "")) == tid:
					var tgt: Dictionary = targets[i]
					var ems: Array = tgt.get("emissions", []) if tgt.get("emissions") is Array else []
					ems.append(em)
					tgt["emissions"] = ems
					targets[i] = tgt
					found = true
					break
			if not found:
				var ne: Dictionary = {"id": tid, "pos_km": em.get("pos_km", [0.0, 0.0, 0.0]),
					"emissions": [em]}
				targets.append(ne)
		c["targets"] = targets
	return c

## 把实体位置权威移入 PhysicsWorld：优先 config.entities；否则从 session seed entities 自动灌入
## （auto_seed=false 可关闭）。位置/速度数组按 bary_rot 解释；失败记录 error 不伪造。
func _seed_physics_entities(pwcfg: Dictionary) -> void:
	if physics_world_service == null:
		return
	var source: Array = []
	if pwcfg.get("entities") is Array:
		source = (pwcfg.get("entities") as Array)
	elif bool(pwcfg.get("auto_seed", true)):
		source = (_seed.get("entities", []) as Array)
	for raw in source:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var id := String(d.get("id", ""))
		if id == "":
			continue
		var st = d.get("state", null)
		var r = d.get("r", d.get("pos_km", null))
		var v = d.get("v", d.get("vel_kmps", null))
		var body: Dictionary = d.duplicate(true)
		if st is Dictionary:
			body = (st as Dictionary).duplicate(true)
			body["id"] = id
			if not body.has("mass_kg"):
				body["mass_kg"] = float(d.get("mass_kg", 1000.0))
		else:
			body["r"] = r
			body["v"] = v
			body["frame"] = String(d.get("frame", "bary_rot"))
			body["mass_kg"] = float(d.get("mass_kg", 1000.0))
		if body.get("r", null) == null or body.get("v", null) == null:
			continue
		var res: Dictionary = physics_world_service.upsert_entity(id, body)
		if not bool(res.get("ok", false)):
			warnings.append("physics seed 失败 %s：%s" % [id, str(res.get("reason", ""))])

func _mk_event(event_type: String, target := "", payload := {}) -> Dictionary:
	return {"type": event_type, "t": time.now_s() if time != null else 0.0,
		"source": writer, "target": target,
		"payload": payload if payload is Dictionary else {}, "text_key": ""}

# ── 时间控制 ────────────────────────────────────────────────────

func pause() -> Dictionary:
	var r: Dictionary = time.pause()
	_record({"op": "pause"})
	return {"ok": bool(r.get("ok", false)), "paused": true}

func resume() -> Dictionary:
	var r: Dictionary = time.resume()
	_record({"op": "resume"})
	return {"ok": bool(r.get("ok", false)), "paused": false}

func set_scale(new_scale: float) -> Dictionary:
	var r: Dictionary = time.set_scale(new_scale)
	if bool(r.get("ok", false)):
		_record({"op": "set_scale", "scale": float(new_scale)})
	return r

func now_s() -> float:
	return float(time.now_s()) if time != null else 0.0

func now_days() -> float:
	return now_s() / 86400.0

# ── tick（核心编排）─────────────────────────────────────────────

## 推进：time.tick(dt) → 订单/通信 tick（scaled dt）→ 事件发布。bus 不自动写 world。
func tick(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	if not is_finite(float(dt)) or float(dt) < 0.0:
		_contract("precondition: tick(dt) 要求 dt 有限且 >=0")
		return {"ok": false, "reason": "invalid_dt", "errors": contract_errors.duplicate()}
	_tick_events = []
	_record({"op": "tick", "dt": float(dt)})
	if bool(time.paused):
		_check_post()
		return {"ok": true, "t_s": now_s(), "paused": true, "events": [],
			"dt_scaled_s": 0.0, "order_counts": orders.status_counts(),
			"contracts": check_contracts()}
	var pending_before := _standalone_ids()
	var tr: Dictionary = time.tick(float(dt))
	if not bool(tr.get("ok", false)):
		return {"ok": false, "reason": "time_tick_failed", "errors": time.errors.duplicate()}
	var sim_dt := float(tr.get("dt_scaled_s", 0.0))
	# tick 顺序：time → physics（位置权威）→ world/sensor/track/orders（见文档）
	var physics_tick: Dictionary = _advance_physics(sim_dt)
	var ot: Dictionary = orders.tick(sim_dt)
	if not bool(ot.get("ok", false)):
		warnings.append("orders tick 失败：" + str(ot.get("reason", "")))
	_flush_order_events()
	_advance_components(sim_dt)
	var sensor_route: Dictionary = _advance_sensors(sim_dt)
	var signal_step: Dictionary = _advance_signal(sim_dt)
	var port_combat: Dictionary = _advance_port_combat(sim_dt)
	_flush_component_events()
	var signal_route: Dictionary = _last_signal_route.duplicate(true)
	var damage_tick: Dictionary = _advance_damage(sim_dt)
	var transponder_tick: Dictionary = _advance_transponder(sim_dt)
	_flush_component_events()
	var routed: Array = _route_pending_bus_events()
	_reconcile_standalone(pending_before)
	var contracts := check_contracts()
	if not bool(contracts.get("ok", false)):
		_contract("postcondition: " + str(contracts.get("violations", [])))
		return {"ok": false, "reason": "contract_violation", "t_s": now_s(),
			"events": _tick_events.duplicate(true),
			"errors": contract_errors.duplicate(), "contracts": contracts}
	return {"ok": true, "t_s": now_s(), "paused": false, "dt_scaled_s": sim_dt,
		"order_counts": orders.status_counts(),
		"events": _tick_events.duplicate(true),
		"routed": routed,
		"components": {
			"track": track_table != null,
			"story": story_state != null,
			"sensor": sensor_service != null,
			"physics": physics_world_service != null,
			"signal": signal_service != null,
			"facility": facility_registry != null,
			"transponder": transponder_service != null,
		},
		"sensor_route": sensor_route,
		"port_combat": port_combat,
		"damage_tick": damage_tick,
		"physics_tick": physics_tick,
		"signal_step": signal_step,
		"signal_route": signal_route,
		"transponder_tick": transponder_tick,
		"contracts": contracts}

func _check_post() -> void:
	if bool(time.paused) and not bool(orders.t == orders.t):
		return
	var contracts := check_contracts()
	if not bool(contracts.get("ok", false)):
		_contract("postcondition: " + str(contracts.get("violations", [])))

## tick 内推进可选组件：TrackTable 过期/story 时间。
func _advance_components(sim_dt: float) -> Dictionary:
	var out := {}
	if track_table != null:
		var tr: Dictionary = track_table.tick(sim_dt)
		out["track"] = tr
		if not bool(tr.get("ok", false)):
			warnings.append("track_table tick 失败：" + str(tr.get("reason", "")))
		_last_track_t = maxf(_last_track_t, float(track_table.t))
	if story_state != null:
		var sr: Dictionary = story_state.set_time(now_s())
		out["story"] = sr
		if not bool(sr.get("ok", false)):
			warnings.append("story_state set_time 失败：" + str(sr.get("reason", "")))
		_last_story_revision = int(story_state.revision)
	return out

## tick 内推进传感器：step → 观测/证据经显式白名单路由到 TrackTable。
func _advance_sensors(sim_dt: float) -> Dictionary:
	if sensor_service == null:
		return {"enabled": false, "observations": 0, "evidence": 0, "failed": 0}
	var sv: Dictionary = sensor_service.step(sim_dt)
	# VM 无显式 ok（传感器正常时用 ready）；只有明确失败才停止路由
	var step_ok := bool(sv.get("ok", true))
	var out := {"enabled": true, "observations": 0, "evidence": 0, "failed": 0,
		"ok": step_ok}
	if not step_ok:
		warnings.append("sensor_service step 失败：" + str(sv.get("reason", "")))
		return out
	var evs: Array = sensor_service.take_events()
	if track_table == null:
		out["skipped"] = evs.size()
		return out
	var reasons: Array = []
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var schema := String(ev.get("schema", ""))
		var kind := String(ev.get("kind", ""))
		# 显式白名单：只路由 observation / evidence；控制事件忽略
		if schema == "sensor_observation.v1" and kind == "observation":
			# sensor service 会输出 support=0 / >2 的非 L1-L2 行；不是本层写事件，忽略
			var obs_support := int(ev.get("support", 0))
			if obs_support < 1 or obs_support > 2:
				out["ignored"] = int(out.get("ignored", 0)) + 1
				continue
			var obs_ev: Dictionary = ev.duplicate(true)
			var tid_obs := String(obs_ev.get("target_id", ""))
			if _sensor_track_map.has(tid_obs) and not obs_ev.has("track_id"):
				obs_ev["track_id"] = String(_sensor_track_map[tid_obs])
			elif _sensor_target_meta.has(tid_obs):
				var meta: Dictionary = _sensor_target_meta[tid_obs]
				if String(obs_ev.get("entity_id", "")) == "":
					obs_ev["entity_id"] = String(meta.get("entity_id", ""))
				if String(obs_ev.get("batch", "")) == "":
					obs_ev["batch"] = String(meta.get("batch", ""))
			var r: Dictionary = track_table.handle_observation(obs_ev, _track_writer)
			if bool(r.get("ok", false)):
				out["observations"] = int(out["observations"]) + 1
				var tr = r.get("track", {})
				if tr is Dictionary and String((tr as Dictionary).get("id", "")) != "":
					_sensor_track_map[String(ev.get("target_id", ""))] = String((tr as Dictionary).get("id", ""))
			else:
				out["failed"] = int(out["failed"]) + 1
				reasons.append("observation:" + str(r.get("reason", "")))
				warnings.append("sensor observation 路由失败：" + str(r.get("reason", "")))
		elif schema == "track_evidence.v1" and kind == "evidence":
			var ev2: Dictionary = ev.duplicate(true)
			_enrich_track_id(ev2)
			var r2: Dictionary = track_table.handle_evidence(ev2, _track_writer)
			if bool(r2.get("ok", false)):
				out["evidence"] = int(out["evidence"]) + 1
				var tr2 = r2.get("track", {})
				if tr2 is Dictionary and String((tr2 as Dictionary).get("id", "")) != "":
					_sensor_track_map[String(ev2.get("target_id", ""))] = String((tr2 as Dictionary).get("id", ""))
			else:
				out["failed"] = int(out["failed"]) + 1
				reasons.append("evidence:" + str(r2.get("reason", "")))
				warnings.append("sensor evidence 路由失败：" + str(r2.get("reason", "")))
	out["reasons"] = reasons
	return out

## sensor 事件 target_id → TrackTable track_id 映射（先有观测航迹）。
func _enrich_track_id(ev: Dictionary) -> void:
	var tid := String(ev.get("target_id", ""))
	if tid != "" and _sensor_track_map.has(tid) and not ev.has("track_id"):
		ev["track_id"] = String(_sensor_track_map[tid])

## tick 驱动 SignalService（ELINT/灯语超时）；输出由 _flush_component_events 白名单路由。
func _advance_signal(sim_dt: float) -> Dictionary:
	if signal_service == null:
		return {"enabled": false}
	signal_service.step(sim_dt)
	return {"enabled": true, "t": float(signal_service.t),
		"step_count": int(signal_service.step_count)}

## 白名单路由 SignalService outbox：observation/evidence → TrackTable（共享 target→track 映射，
## 不重复建 track）；light_* → EventBus（light_signal.*）；不写 world/UI。
## Signal target → entity 绑定：优先 _sensor_target_meta[target_id] 的 entity_id/batch；
## 其次 world 同名实体（id/batch/name/kind/side）；不硬编码具体舰名；缺失留空并 warning。
func _signal_binding(target_id: String) -> Dictionary:
	var entity_id := ""
	var batch := ""
	var source := ""
	if _sensor_target_meta.has(target_id):
		var meta: Dictionary = _sensor_target_meta[target_id]
		entity_id = String(meta.get("entity_id", ""))
		batch = String(meta.get("batch", ""))
		if entity_id != "" or batch != "":
			source = "sensor_target_meta"
	if world != null and world.has_entity(target_id):
		var we: Dictionary = world.entity(target_id)
		if entity_id == "":
			entity_id = String(we.get("id", target_id))
			source = "world" if source == "" else source
		if batch == "":
			batch = String(we.get("batch", ""))
		return {"entity_id": entity_id, "batch": batch, "source": source,
			"name": String(we.get("name", we.get("label", ""))),
			"kind": String(we.get("kind", "")), "side": String(we.get("side", ""))}
	return {"entity_id": entity_id, "batch": batch, "source": source,
		"name": "", "kind": "", "side": ""}

## 给 signal observation/evidence 补 entity_id/batch（TrackTable 写入前；不改写已有非空值）。
func _enrich_signal_binding(ev: Dictionary, out: Dictionary) -> void:
	var tid := String(ev.get("target_id", ""))
	var bind: Dictionary = _signal_binding(tid)
	if String(ev.get("entity_id", "")) == "" and String(bind.get("entity_id", "")) != "":
		ev["entity_id"] = String(bind.get("entity_id", ""))
	if String(ev.get("batch", "")) == "" and String(bind.get("batch", "")) != "":
		ev["batch"] = String(bind.get("batch", ""))
	# 供 UI/诊断的实体元数据（TrackTable 只取 entity_id/batch，其余字段忽略）
	if String(ev.get("entity_name", "")) == "" and String(bind.get("name", "")) != "":
		ev["entity_name"] = String(bind.get("name", ""))
	if String(ev.get("entity_kind", "")) == "" and String(bind.get("kind", "")) != "":
		ev["entity_kind"] = String(bind.get("kind", ""))
	if String(ev.get("side", "")) == "" and String(bind.get("side", "")) != "":
		ev["side"] = String(bind.get("side", ""))
	var bound_entity := String(ev.get("entity_id", ""))
	var bound_batch := String(ev.get("batch", ""))
	if bound_entity == "" and bound_batch == "":
		out["missing_meta"] = int(out.get("missing_meta", 0)) + 1
		if not _signal_missing_meta_warned.has(tid):
			_signal_missing_meta_warned[tid] = true
			warnings.append("signal target 缺少 entity/batch 绑定：" + tid)
	else:
		out["bound"] = int(out.get("bound", 0)) + 1
		if String(bind.get("source", "")) == "world":
			out["world_bound"] = int(out.get("world_bound", 0)) + 1

func _flush_signal_events() -> Dictionary:
	if signal_service == null:
		return {"enabled": false}
	var evs: Array = signal_service.take_events()
	var obs: Array = []
	var evid: Array = []
	var light: Array = []
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var schema := String(ev.get("schema", ""))
		var kind := String(ev.get("kind", ""))
		if schema == "sensor_observation.v1" and kind == "observation":
			obs.append(ev)
		elif schema == "track_evidence.v1" and kind == "evidence":
			evid.append(ev)
		elif schema == "signal_event.v1" and kind.begins_with("light_"):
			light.append(ev)
	var out := {"enabled": true, "observations": 0, "evidence": 0,
		"light": 0, "ignored": 0, "failed": 0, "skipped": 0,
		"reasons": [], "track_created": 0, "bound": 0,
		"world_bound": 0, "missing_meta": 0}
	if track_table == null:
		out["skipped"] = obs.size() + evid.size()
	else:
		for raw_obs in obs:
			var o: Dictionary = (raw_obs as Dictionary).duplicate(true)
			var sensor := String(o.get("sensor", ""))
			if sensor == "elint.comms":
				o["sensor"] = "elint"
				o["detail"] = String(o.get("detail", "")) + "|comint"
			elif not (sensor in ["radar", "radar.tws", "optical", "ir", "elint",
					"crossfix", "datalink", "visual"]):
				out["ignored"] = int(out["ignored"]) + 1
				continue
			var support := int(o.get("support", o.get("level_support", 1)))
			if support < 1 or support > 2:
				out["ignored"] = int(out["ignored"]) + 1
				continue
			var tid := String(o.get("target_id", ""))
			if _sensor_track_map.has(tid) and not o.has("track_id"):
				o["track_id"] = String(_sensor_track_map[tid])
			_enrich_signal_binding(o, out)
			var r: Dictionary = track_table.handle_observation(o, _track_writer)
			if bool(r.get("ok", false)):
				out["observations"] = int(out["observations"]) + 1
				var tr = r.get("track", {})
				if tr is Dictionary and String((tr as Dictionary).get("id", "")) != "":
					_sensor_track_map[tid] = String((tr as Dictionary).get("id", ""))
				if bool(r.get("created", false)):
					out["track_created"] = int(out["track_created"]) + 1
			else:
				out["failed"] = int(out["failed"]) + 1
				out["reasons"].append("observation:" + str(r.get("reason", "")))
		for raw_ev in evid:
			var e: Dictionary = (raw_ev as Dictionary).duplicate(true)
			var etype := String(e.get("evidence_type", e.get("type", "elint")))
			if not (etype in ["optical", "elint", "iff", "datalink", "visual",
					"manual", "database", "track_update"]):
				e["evidence_type"] = "elint"
			var tid2 := String(e.get("target_id", ""))
			if _sensor_track_map.has(tid2) and not e.has("track_id"):
				e["track_id"] = String(_sensor_track_map[tid2])
			_enrich_signal_binding(e, out)
			var r2: Dictionary = track_table.handle_evidence(e, _track_writer)
			if bool(r2.get("ok", false)):
				out["evidence"] = int(out["evidence"]) + 1
			else:
				out["failed"] = int(out["failed"]) + 1
				out["reasons"].append("evidence:" + str(r2.get("reason", "")))
	for raw_l in light:
		var le: Dictionary = raw_l
		var lkind := String(le.get("kind", "light_event"))
		var payload: Dictionary = le.get("payload", {}) if le.get("payload") is Dictionary else {}
		_publish({"type": "light_signal." + lkind.substr(6), "t": now_s(),
			"source": "signal_service", "target": String(payload.get("target_id", "")),
			"payload": payload.duplicate(true), "text_key": ""})
		out["light"] = int(out["light"]) + 1
	if out["skipped"] > 0:
		out["note"] = "track_table 未启用，signal observation/evidence 已跳过"
	_last_signal_route = out.duplicate(true)
	return out

## tick 驱动 PortService/CombatService（手动状态机本身不自动执行）。
func _advance_port_combat(sim_dt: float) -> Dictionary:
	var out := {"port": false, "combat": false}
	if port_service != null:
		var pr: Dictionary = port_service.tick(sim_dt)
		out["port"] = bool(pr.get("ok", false))
		if not bool(pr.get("ok", false)):
			warnings.append("port_service tick 失败：" + str(pr.get("reason", "")))
	if combat_service != null:
		var cr: Dictionary = combat_service.tick(sim_dt)
		out["combat"] = bool(cr.get("ok", true))
		if not bool(cr.get("ok", true)):
			warnings.append("combat_service tick 失败：" + str(cr.get("reason", "")))
	return out

## 把 Port/Combat 服务的 outbox 事件发布到 EventBus（只读事件，不改 world/组件）。
func _flush_component_events() -> void:
	var n := 0
	if port_service != null:
		for raw in port_service.take_events():
			if not (raw is Dictionary):
				continue
			var ev: Dictionary = raw
			var detail: Dictionary = ev.get("detail", {}) if ev.get("detail") is Dictionary else {}
			_publish({"type": String(ev.get("kind", "port.event")), "t": now_s(),
				"source": "port_service", "target": String(detail.get("port_id", "")),
				"payload": detail.duplicate(true), "text_key": ""})
			n += 1
	if combat_service != null:
		for raw2 in combat_service.take_events():
			if not (raw2 is Dictionary):
				continue
			var cev: Dictionary = raw2
			var kind := String(cev.get("kind", "event"))
			var payload: Dictionary = cev.get("payload", {}) if cev.get("payload") is Dictionary else {}
			payload = payload.duplicate(true)
			# 白名单：combat_damage_event（内嵌 damage_event）→ DamageService
			if damage_service != null and payload.get("damage_event") is Dictionary:
				var dmg_ev: Dictionary = (payload.get("damage_event") as Dictionary).duplicate(true)
				var route: Dictionary = _route_combat_damage(dmg_ev)
				if bool(route.get("applied", false)):
					dmg_ev["applied"] = true
					payload["damage_event"] = dmg_ev
			_publish({"type": "combat." + kind, "t": now_s(),
				"source": "combat_service", "target": String(payload.get("target_id", "")),
				"payload": payload, "text_key": ""})
			n += 1
	if damage_service != null:
		for raw3 in damage_service.take_events():
			if not (raw3 is Dictionary):
				continue
			var dev: Dictionary = raw3
			var detail3: Dictionary = dev.get("detail", {}) if dev.get("detail") is Dictionary else {}
			_publish({"type": String(dev.get("kind", "damage.event")), "t": now_s(),
				"source": "damage_service", "target": String(detail3.get("ship_id", "")),
				"payload": detail3.duplicate(true), "text_key": ""})
			n += 1
	if signal_service != null:
		var sres: Dictionary = _flush_signal_events()
		n += int(sres.get("light", 0))
	if physics_world_service != null:
		for raw4 in physics_world_service.take_events():
			if not (raw4 is Dictionary):
				continue
			var pev: Dictionary = raw4
			var pdet: Dictionary = pev.get("detail", {}) if pev.get("detail") is Dictionary else {}
			_publish({"type": String(pev.get("kind", "physics.event")), "t": now_s(),
				"source": "physics_world", "target": String(pdet.get("id", "")),
				"payload": pdet.duplicate(true), "text_key": ""})
			n += 1
	if transponder_service != null:
		var tres: Dictionary = _flush_transponder_outputs()
		n += int(tres.get("events", 0))
	if n > 0:
		_last_bus_routed_index = bus.events.size()

## tick 推进损管（火灾/失压/断电/维修队列）；伤害事件已在 _flush_component_events 应用。
func _advance_damage(sim_dt: float) -> Dictionary:
	if damage_service == null:
		return {"enabled": false}
	var res: Dictionary = damage_service.tick(sim_dt)
	if not bool(res.get("ok", false)):
		warnings.append("damage_service tick 失败：" + str(res.get("reason", "")))
	return {"enabled": true, "ok": bool(res.get("ok", false)),
		"t": float(damage_service.t), "summary": res.get("summary", {})}

## 路由 combat_damage_event → DamageService（applied=true）；按 shot_id 去重，避免同一次开火
## 在 request_fire 立即应用后又在 tick flush 二次应用。
func _route_combat_damage(dmg_ev: Dictionary) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var shot := String(dmg_ev.get("shot_id", ""))
	if shot != "" and _damage_applied_shots.has(shot):
		return {"ok": true, "applied": true, "duplicate": true}
	var ship := _damage_ship_for_target(String(dmg_ev.get("target_id", "")))
	var ev2: Dictionary = dmg_ev.duplicate(true)
	ev2["target_ship"] = ship
	var res: Dictionary = damage_service.apply_combat_damage(ev2, {"ship_id": ship})
	if bool(res.get("ok", false)):
		if shot != "":
			_damage_applied_shots[shot] = true
		res["applied"] = true
		res["ship_id"] = ship
		return res
	warnings.append("damage 路由失败：" + str(res.get("reason", "")))
	return {"ok": false, "reason": String(res.get("reason", "")), "applied": false}

## combat target_id → damage ship_id（combat track.ship_id；否则 default_ship）。
func _damage_ship_for_target(target_id: String) -> String:
	if damage_service == null:
		return ""
	var ship := ""
	if combat_service != null:
		var tr = combat_service.track(target_id)
		if tr is Dictionary:
			ship = String((tr as Dictionary).get("ship_id", ""))
	if ship != "" and (damage_service.ships as Dictionary).has(ship):
		return ship
	return String(damage_service.default_ship)

## tick 内推进 PhysicsWorld（时间→physics 固定步长；在 orders/world/sensor/track 之前）。
func _advance_physics(sim_dt: float) -> Dictionary:
	if physics_world_service == null:
		return {"enabled": false}
	var res: Dictionary = physics_world_service.step(sim_dt)
	if not bool(res.get("ok", false)):
		warnings.append("physics_world step 失败：" + str(res.get("reason", "")))
	return {"enabled": true, "ok": bool(res.get("ok", false)),
		"steps": int(res.get("steps", 0)), "t": float(physics_world_service.t),
		"entities": physics_world_service.entity_count()}

## tick：应答机只同步时间，不自动询问/广播；事件由 _flush_component_events 路由。
func _advance_transponder(sim_dt: float) -> Dictionary:
	if transponder_service == null:
		return {"enabled": false}
	transponder_service.set_time(now_s())
	return {"enabled": true, "t": float(transponder_service.t),
		"profiles": transponder_service.profiles.size()}

## 应答机输出路由：track_evidence.v1 → TrackTable（白名单）；transponder_event.v1 →
## EventBus（transponder.<kind>）。不写 world；track_table 未启用时 evidence skipped。
func _flush_transponder_outputs(extra_events := [], extra_evidence := []) -> Dictionary:
	if transponder_service == null:
		return {"enabled": false}
	var evs: Array = []
	for raw in extra_events:
		evs.append(raw)
	for raw2 in transponder_service.take_events():
		evs.append(raw2)
	var evid: Array = []
	for raw3 in extra_evidence:
		evid.append(raw3)
	for raw4 in evs:
		if not (raw4 is Dictionary):
			continue
		var ev: Dictionary = raw4
		if String(ev.get("schema", "")) == "track_evidence.v1":
			evid.append(ev)
	var out := {"enabled": true, "evidence": 0, "events": 0, "failed": 0,
		"skipped": 0, "reasons": []}
	if track_table == null:
		out["skipped"] = evid.size()
	else:
		for raw_ev in evid:
			var e: Dictionary = (raw_ev as Dictionary).duplicate(true)
			var support := int(e.get("support", 3))
			if support < 1 or support > 4:
				out["skipped"] = int(out["skipped"]) + 1
				continue
			var tid := String(e.get("target_id", ""))
			if _sensor_track_map.has(tid) and not e.has("track_id"):
				e["track_id"] = String(_sensor_track_map[tid])
			var r: Dictionary = track_table.handle_evidence(e, _track_writer)
			if bool(r.get("ok", false)):
				out["evidence"] = int(out["evidence"]) + 1
			else:
				out["failed"] = int(out["failed"]) + 1
				out["reasons"].append("evidence:" + str(r.get("reason", "")))
	for raw5 in evs:
		if not (raw5 is Dictionary):
			continue
		var tev: Dictionary = raw5
		if String(tev.get("schema", "")) != "transponder_event.v1":
			continue
		var payload: Dictionary = tev.get("payload", {}) if tev.get("payload") is Dictionary else {}
		_publish({"type": "transponder." + str(tev.get("kind", "event")), "t": now_s(),
			"source": "transponder_service",
			"target": str(payload.get("target_id", "")),
			"payload": {"event_id": str(tev.get("event_id", "")),
				"kind": str(tev.get("kind", "")),
				"trigger_id": str(tev.get("trigger_id", "")),
				"data": payload.duplicate(true)},
			"text_key": ""})
		out["events"] = int(out["events"]) + 1
	return out

const ROUTABLE_TYPES := ["story.flag", "story.evidence", "story.choice",
	"track.observation", "track.evidence"]

func _is_routable_type(event_type: String) -> bool:
	return event_type in ROUTABLE_TYPES

## 显式白名单路由：事件总线 → StoryState / TrackTable；非白名单不路由。
func _route_pending_bus_events() -> Array:
	var routed: Array = []
	if bus == null:
		return routed
	var all_events: Array = bus.events
	var i := _last_bus_routed_index
	while i < all_events.size():
		var ev: Dictionary = all_events[i]
		var seq := int(ev.get("seq", 0))
		var typ := String(ev.get("type", ""))
		if not _routed_seqs.has(seq) and _is_routable_type(typ):
			var res: Dictionary = _apply_routed_event(ev)
			res["type"] = typ
			routed.append(res.duplicate(true))
			if bool(res.get("ok", false)):
				_routed_seqs[seq] = true
			else:
				warnings.append("bus 路由失败 %s：%s" % [typ, str(res.get("reason", ""))])
		i += 1
	_last_bus_routed_index = all_events.size()
	return routed

## 路由实现：先校验组件存在/载荷，再写入（失败不改状态）。
func _apply_routed_event(ev: Dictionary, publish := false) -> Dictionary:
	var typ := String(ev.get("type", ""))
	var payload: Dictionary = ev.get("payload", {}) if ev.get("payload") is Dictionary else {}
	if typ == "story.flag":
		if story_state == null:
			return {"ok": false, "reason": "no_story_state"}
		var res: Dictionary = story_state.set_flag(String(payload.get("flag", "")),
			payload.get("value", true))
		if publish and bool(res.get("ok", false)):
			_publish(ev)
		return res
	if typ == "story.evidence":
		if story_state == null:
			return {"ok": false, "reason": "no_story_state"}
		var res2: Dictionary = story_state.add_evidence(String(payload.get("evidence_id", "")))
		if publish and bool(res2.get("ok", false)):
			_publish(ev)
		return res2
	if typ == "story.choice":
		if story_state == null:
			return {"ok": false, "reason": "no_story_state"}
		var res3: Dictionary = story_state.record_choice(String(payload.get("choice_id", "")),
			payload.get("meta", {}))
		if publish and bool(res3.get("ok", false)):
			_publish(ev)
		return res3
	if typ == "track.observation":
		if track_table == null:
			return {"ok": false, "reason": "no_track_table"}
		var obs: Dictionary = payload.get("observation", payload) if payload.get("observation") is Dictionary else payload
		var evn := obs.duplicate(true)
		if not evn.has("t"):
			evn["t"] = now_s()
		var res4: Dictionary = track_table.handle_observation(evn, _track_writer)
		if publish and bool(res4.get("ok", false)):
			_publish(ev)
		return res4
	if typ == "track.evidence":
		if track_table == null:
			return {"ok": false, "reason": "no_track_table"}
		var evd: Dictionary = payload.get("evidence", payload) if payload.get("evidence") is Dictionary else payload
		var evd2 := evd.duplicate(true)
		if not evd2.has("t"):
			evd2["t"] = now_s()
		var res5: Dictionary = track_table.handle_evidence(evd2, _track_writer)
		if publish and bool(res5.get("ok", false)):
			_publish(ev)
		return res5
	return {"ok": false, "reason": "not_routable"}

## 订单/通信之外的显式事件发布+路由（只允许白名单 story.*/track.*）。
func route_event(event: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not (event is Dictionary):
		return {"ok": false, "reason": "invalid_event"}
	var evn: Dictionary = (event as Dictionary).duplicate(true)
	var typ := String(evn.get("type", ""))
	if not _is_routable_type(typ):
		return {"ok": false, "reason": "not_routable", "type": typ,
			"errors": ["不在显式白名单：" + typ]}
	if not evn.has("t"):
		evn["t"] = now_s()
	if not evn.has("source"):
		evn["source"] = "session"
	var res: Dictionary = _apply_routed_event(evn, false)
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": String(res.get("reason", "")),
			"type": typ, "errors": res.get("errors", [])}
	var pub: Dictionary = bus.publish(evn)
	if not bool(pub.get("ok", false)):
		return {"ok": false, "reason": "bus_publish_failed", "type": typ,
			"errors": pub.get("errors", [])}
	var seq := int((pub.get("event", {}) as Dictionary).get("seq", 0))
	_routed_seqs[seq] = true
	_record({"op": "route_event", "event": evn})
	return {"ok": true, "routed": true, "type": typ, "seq": seq,
		"event": pub.get("event", {}), "result": res}

## 观测（TrackTable）：需 boot 配置 track_table。
func handle_observation(observation: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if track_table == null:
		return {"ok": false, "reason": "no_track_table",
			"errors": ["未配置 track_table"]}
	if not (observation is Dictionary):
		return {"ok": false, "reason": "invalid_observation"}
	var evn: Dictionary = (observation as Dictionary).duplicate(true)
	if not evn.has("t"):
		evn["t"] = now_s()
	var res: Dictionary = track_table.handle_observation(evn, _track_writer)
	if bool(res.get("ok", false)):
		_record({"op": "handle_observation", "event": evn})
	return res

## 证据（TrackTable track_evidence.v1）；不是 StoryState 证据（用 handle_story_evidence）。
func handle_evidence(evidence: Dictionary) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if track_table == null:
		return {"ok": false, "reason": "no_track_table",
			"errors": ["未配置 track_table"]}
	if not (evidence is Dictionary):
		return {"ok": false, "reason": "invalid_evidence"}
	var evn: Dictionary = (evidence as Dictionary).duplicate(true)
	if not evn.has("t"):
		evn["t"] = now_s()
	var res: Dictionary = track_table.handle_evidence(evn, _track_writer)
	if bool(res.get("ok", false)):
		_record({"op": "handle_evidence", "event": evn})
	return res

## StoryState 证据（独立于 TrackTable 证据）。
func handle_story_evidence(evidence_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if story_state == null:
		return {"ok": false, "reason": "no_story_state",
			"errors": ["未配置 story_state"]}
	var res: Dictionary = story_state.add_evidence(evidence_id)
	if bool(res.get("ok", false)):
		_record({"op": "handle_story_evidence", "evidence_id": evidence_id})
	return res

## 只读 Track VM/过滤（未配置时返回空对象）。
func track_vm(opts := {}) -> Dictionary:
	if track_table == null:
		return {}
	return track_table.vm(opts)

func track_filter(where := {}) -> Array:
	if track_table == null:
		return []
	return track_table.filter(where)

## 只读 Story VM/条件判定。
func story_vm() -> Dictionary:
	if story_state == null:
		return {}
	return story_state.snapshot()

func gate(conditions = {}) -> Dictionary:
	if story_state == null:
		return {"ok": false, "reason": "no_story_state", "passed": false,
			"errors": ["未配置 story_state"], "failed": []}
	return story_state.gate(conditions)

# ── SensorService 包装（可选）──────────────────────────────────

func sensor_vm() -> Dictionary:
	if sensor_service == null:
		return {}
	return sensor_service.vm()

func set_sensor_target(target_id: String) -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.set_target(target_id)
	if bool(res.get("ok", false)):
		_record({"op": "set_sensor_target", "target_id": target_id})
	return res

func start_sensor_channel(kind: String, target := "", opts := {}) -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.start_channel(kind, target, opts)
	if bool(res.get("ok", false)):
		_record({"op": "start_sensor_channel", "kind": kind, "target": target,
			"opts": opts})
	return res

func stop_sensor_channel(kind := "", target := "") -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.stop_channel(kind, target)
	if bool(res.get("ok", false)):
		_record({"op": "stop_sensor_channel", "kind": kind, "target": target})
	return res

func set_radar_enabled(on: bool) -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.set_radar_enabled(on)
	if bool(res.get("ok", false)):
		_record({"op": "set_radar_enabled", "on": on})
	return res

func set_emcon(on: bool) -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.set_emcon(on)
	if bool(res.get("ok", false)):
		_record({"op": "set_emcon", "on": on})
	return res

## IFF 询问；成功后把 iff evidence 显式路由到 TrackTable（若启用）。
func query_iff(target_id := "") -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service"}
	var res: Dictionary = sensor_service.query_iff(target_id)
	if not bool(res.get("ok", false)):
		return res
	var routed := false
	if track_table != null and res.get("evidence") is Dictionary:
		var iff_ev: Dictionary = (res.get("evidence") as Dictionary).duplicate(true)
		_enrich_track_id(iff_ev)
		var rr: Dictionary = track_table.handle_evidence(iff_ev, _track_writer)
		res["routed"] = bool(rr.get("ok", false))
		if not bool(rr.get("ok", false)):
			res["route_reason"] = String(rr.get("reason", ""))
			warnings.append("IFF evidence 路由失败：" + String(rr.get("reason", "")))
		else:
			routed = true
	res["routed"] = routed
	_record({"op": "query_iff", "target_id": String(res.get("target_id", target_id))})
	return res

# ── 订单包装 ────────────────────────────────────────────────────

## 创建并发出订单（依赖通信投递；失败/拒绝会体现在 order/status）。
func issue_order(action: String, issuer_id: String, target_ids, params := {},
		opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var p_norm = _json_norm(params)
	var o_norm = _json_norm(opts)
	var t_norm = _json_norm(target_ids)
	_record({"op": "issue_order", "action": action, "issuer_id": issuer_id,
		"target_ids": t_norm, "params": p_norm, "opts": o_norm})
	var draft: Dictionary = orders.create_draft(action, issuer_id, t_norm, p_norm, o_norm)
	if not bool(draft.get("ok", false)):
		_flush_order_events()
		return {"ok": false, "reason": String(draft.get("reason", "")), "errors": [String(draft.get("reason", ""))]}
	var order_id := String((draft.get("order", {}) as Dictionary).get("order_id", ""))
	var res: Dictionary = orders.issue(order_id)
	_flush_order_events()
	return {"ok": bool(res.get("ok", false)), "order_id": order_id,
		"delivery_id": String(res.get("delivery_id", "")),
		"order": res.get("order", {}), "reason": String(res.get("reason", "")),
		"events": _tick_events.duplicate(true)}

func authorize_order(order_id: String, authorizer_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "authorize_order", "order_id": order_id, "authorizer_id": authorizer_id})
	var res: Dictionary = orders.authorize(order_id, authorizer_id)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func begin_execute_order(order_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "begin_execute_order", "order_id": order_id})
	var res: Dictionary = orders.begin_execute(order_id)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func complete_order(order_id: String, result := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var r_norm = _json_norm(result)
	_record({"op": "complete_order", "order_id": order_id, "result": r_norm})
	var res: Dictionary = orders.complete(order_id, r_norm)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func abort_order(order_id: String, reason := "aborted") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "abort_order", "order_id": order_id, "reason": reason})
	var res: Dictionary = orders.abort(order_id, reason)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func reject_order(order_id: String, reason := "rejected", by := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	_record({"op": "reject_order", "order_id": order_id, "reason": reason, "by": by})
	var res: Dictionary = orders.reject(order_id, reason, by)
	_flush_order_events()
	res["events"] = _tick_events.duplicate(true)
	return res

func order(order_id: String) -> Dictionary:
	return orders.order(order_id)

# ── 通信/链路包装 ──────────────────────────────────────────────

func send_comms(from_id: String, to_id: String, mode := "LD",
		text_key := "COMMS_SENT", payload := {}, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	_tick_events = []
	var pl_norm = _json_norm(payload)
	var po_norm = _json_norm(opts)
	_record({"op": "send_comms", "from_id": from_id, "to_id": to_id, "mode": mode,
		"text_key": text_key, "payload": pl_norm, "opts": po_norm})
	var res: Dictionary = comms.send(from_id, to_id, mode, text_key, pl_norm, po_norm)
	var ev_type := "comms.sent" if bool(res.get("ok", false)) else "comms.failed"
	_publish(_mk_event(ev_type, to_id, {
		"delivery_id": String(res.get("delivery_id", "")),
		"from": from_id, "to": to_id, "mode": mode,
		"text_key": text_key, "reason": String(res.get("reason", "")),
		"latency_s": float(res.get("latency_s", 0.0)),
		"relay_count": int(res.get("relay_count", 0)),
	}))
	if bool(res.get("ok", false)):
		var did := String(res.get("delivery_id", ""))
		_standalone[did] = {"from": from_id, "to": to_id, "mode": mode,
			"text_key": text_key, "sent_t": now_s()}
	res["events"] = _tick_events.duplicate(true)
	return res

func set_link(a: String, b: String, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	var o: Dictionary = opts if opts is Dictionary else {}
	_tick_events = []
	o = _json_norm(o)
	_record({"op": "set_link", "a": a, "b": b, "opts": o})
	var applied := {}
	if o.has("enabled"):
		applied["enabled"] = comms.set_link_enabled(a, b, bool(o.get("enabled")))
	if o.has("occluded"):
		applied["occluded"] = comms.set_link_occluded(a, b, bool(o.get("occluded")))
	if o.has("jam"):
		applied["jam"] = comms.set_link_jam(a, b, float(o.get("jam")))
	_publish(_mk_event("comms.link", b, {"a": a, "b": b, "applied": applied}))
	var ok := true
	for k in applied.keys():
		if not bool(applied[k]):
			ok = false
	return {"ok": ok, "applied": applied, "events": _tick_events.duplicate(true)}

## 直接查询通信 pending（只读；用于上层观察，不改变状态）。
func comms_pending() -> Array:
	return (comms.pending as Array).duplicate(true) if comms != null else []

# ── 事件发布 / 事件一致性 ───────────────────────────────────────

func _publish(ev: Dictionary) -> void:
	var pub: Dictionary = bus.publish(ev)
	if not bool(pub.get("ok", false)):
		warnings.append("bus publish 失败：" + str(pub.get("errors", [])))
		return
	_tick_events.append((pub.get("event", {}) as Dictionary).duplicate(true))

func _flush_order_events() -> void:
	if orders == null:
		return
	var evs: Array = orders.take_events()
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var typ := "order." + String(ev.get("event", "")).to_lower()
		var targets: Array = ev.get("target_ids", []) if ev.get("target_ids") is Array else []
		_publish({
			"type": typ,
			"t": now_s(),
			"source": "order_service",
			"target": String(targets[0]) if not targets.is_empty() else "",
			"payload": {
				"order_id": String(ev.get("order_id", "")),
				"status": String(ev.get("status", "")),
				"event": String(ev.get("event", "")),
				"reason": String(ev.get("reason", "")),
				"delivery_id": String(ev.get("delivery_id", "")),
				"action": String(ev.get("action", "")),
				"issuer_id": String(ev.get("issuer_id", "")),
			},
			"text_key": String(ev.get("text_key", "")),
		})

func _standalone_ids() -> Array:
	var ids: Array = _standalone.keys()
	ids.sort()
	return ids

func _pending_ids() -> Dictionary:
	var out := {}
	for raw in (comms.pending as Array) if comms != null else []:
		if raw is Dictionary:
			out[String((raw as Dictionary).get("delivery_id", ""))] = true
	return out

func _reconcile_standalone(before_ids: Array) -> void:
	if comms == null:
		return
	var pending_now := _pending_ids()
	for did in before_ids:
		var id := String(did)
		if not _standalone.has(id):
			continue
		if pending_now.has(id):
			continue
		var info: Dictionary = _standalone[id]
		_publish(_mk_event("comms.delivered", String(info.get("to", "")), {
			"delivery_id": id, "from": String(info.get("from", "")),
			"to": String(info.get("to", "")), "mode": String(info.get("mode", "")),
			"text_key": String(info.get("text_key", "")),
		}))
		_standalone.erase(id)

# ── PortService 委托（可选）─────────────────────────────────────

func port_request(kind: String, ship_id: String, port_id: String, opts := {}) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service", "errors": ["未配置 port_service"]}
	var res: Dictionary = port_service.request(kind, ship_id, port_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "port_request", "kind": kind, "ship_id": ship_id,
			"port_id": port_id, "opts": opts})
	return res

func port_permit(request_id: String) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.permit(request_id)
	if bool(res.get("ok", false)):
		_record({"op": "port_permit", "request_id": request_id})
	return res

func port_approach(request_id: String) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.approach(request_id)
	if bool(res.get("ok", false)):
		_record({"op": "port_approach", "request_id": request_id})
	return res

func port_dock(request_id: String) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.dock(request_id)
	if bool(res.get("ok", false)):
		_record({"op": "port_dock", "request_id": request_id})
	return res

func port_refuel(request_id: String, amount_t: float) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.refuel(request_id, amount_t)
	if bool(res.get("ok", false)):
		_record({"op": "port_refuel", "request_id": request_id,
			"amount_t": amount_t})
	return res

func port_repair(request_id: String, opts := {}) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.repair(request_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "port_repair", "request_id": request_id, "opts": opts})
	return res

func port_finish_service(request_id: String) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.finish_service(request_id)
	if bool(res.get("ok", false)):
		_record({"op": "port_finish_service", "request_id": request_id})
	return res

func port_undock(request_id: String) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.undock(request_id)
	if bool(res.get("ok", false)):
		_record({"op": "port_undock", "request_id": request_id})
	return res

func port_tow(ship_id: String, port_id: String, opts := {}) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.tow(ship_id, port_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "port_tow", "ship_id": ship_id, "port_id": port_id,
			"opts": opts})
	return res

func port_shuttle(ship_id: String, port_id: String, opts := {}) -> Dictionary:
	if port_service == null:
		return {"ok": false, "reason": "no_port_service"}
	var res: Dictionary = port_service.shuttle(ship_id, port_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "port_shuttle", "ship_id": ship_id, "port_id": port_id,
			"opts": opts})
	return res

func port_services(request_id := "", port_id := "") -> Array:
	if port_service == null:
		return []
	return port_service.services(request_id, port_id)

func port_vm() -> Dictionary:
	if port_service == null:
		return {}
	return port_service.vm()

func port_summary() -> Dictionary:
	if port_service == null:
		return {}
	return port_service.summary()

# ── CombatService 委托（可选）───────────────────────────────────

func set_roe(level: String) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.set_roe(level)
	if bool(res.get("ok", false)):
		_record({"op": "set_roe", "level": level})
	return res

func combat_register_track(track_id: String, data := {}) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.register_track(track_id, data)
	if bool(res.get("ok", false)):
		_record({"op": "combat_register_track", "track_id": track_id, "data": data})
	return res

func combat_request_solution(target_id: String, weapon_id: String, confirmed := false) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.request_solution(target_id, weapon_id, confirmed)
	if bool(res.get("ok", false)):
		_record({"op": "combat_request_solution", "target_id": target_id,
			"weapon_id": weapon_id, "confirmed": confirmed})
	return res

func grant_authorization(level: String, scope_type := "target", scope_id := "",
		duration_s := 0.0, until_destroyed := false) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.grant_authorization(level, scope_type,
		scope_id, duration_s, until_destroyed)
	if bool(res.get("ok", false)):
		_record({"op": "grant_authorization", "level": level,
			"scope_type": scope_type, "scope_id": scope_id,
			"duration_s": duration_s, "until_destroyed": until_destroyed})
	return res

func revoke_authorization(grant_id := "") -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.revoke_authorization(grant_id)
	if bool(res.get("ok", false)):
		_record({"op": "revoke_authorization", "grant_id": grant_id})
	return res

func request_fire(target_id: String, weapon_id: String, confirmed := false) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.request_fire(target_id, weapon_id, confirmed)
	if bool(res.get("ok", false)):
		_record({"op": "request_fire", "target_id": target_id,
			"weapon_id": weapon_id, "confirmed": confirmed})
		# 命中时立即把 combat_damage_event 白名单路由到 DamageService（去重 shot_id）
		if damage_service != null and res.get("damage_event") is Dictionary:
			var ev: Dictionary = (res.get("damage_event") as Dictionary).duplicate(true)
			var route: Dictionary = _route_combat_damage(ev)
			res["damage_applied"] = bool(route.get("applied", false))
			if bool(route.get("applied", false)):
				ev["applied"] = true
				res["damage_event"] = ev
				res["damage_result"] = route
	return res

## 手动推进战斗服务（通常由 session tick 驱动；此接口供测试/上层显式推进）。
func combat_tick(dt: float) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.tick(dt)
	if bool(res.get("ok", true)):
		_record({"op": "combat_tick", "dt": dt})
	_flush_component_events()
	return res

func combat_vm() -> Dictionary:
	if combat_service == null:
		return {}
	return combat_service.vm()

func combat_summary() -> Dictionary:
	if combat_service == null:
		return {}
	return combat_service.summary()

func combat_authorization(level := "FIRE", target := "", weapon := "") -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	return combat_service.check_authorization(level, target, weapon)

## 立即把 Port/Combat outbox 事件发布到 bus（通常 tick 会自动 flush；此接口供 UI/测试显式拉取）。
func flush_events() -> int:
	_flush_component_events()
	return bus.current_seq() if bus != null else 0
# ── DamageService 委托（可选）───────────────────────────────────

func damage_apply_event(event: Dictionary, opts := {}) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service", "errors": ["未配置 damage_service"]}
	var res: Dictionary = damage_service.apply_combat_damage(event, opts)
	if bool(res.get("ok", false)):
		_record({"op": "damage_apply_event", "event": event, "opts": opts})
	return res

func damage_apply_hit(ship_id: String, section: String, energy: float,
		penetration := 0.5, direction := "fore", source := "manual") -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var res: Dictionary = damage_service.apply_hit(ship_id, section, energy,
		penetration, direction, source)
	if bool(res.get("ok", false)):
		_record({"op": "damage_apply_hit", "ship_id": ship_id, "section": section,
			"energy": energy, "penetration": penetration,
			"direction": direction, "source": source})
	return res

func damage_repair(ship_id: String, section: String, priority := 2) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var res: Dictionary = damage_service.repair(ship_id, section, priority)
	if bool(res.get("ok", false)):
		_record({"op": "damage_repair", "ship_id": ship_id, "section": section,
			"priority": priority})
	return res

func damage_fix(ship_id: String, section: String, priority := 2) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var res: Dictionary = damage_service.fix(ship_id, section, priority)
	if bool(res.get("ok", false)):
		_record({"op": "damage_fix", "ship_id": ship_id, "section": section,
			"priority": priority})
	return res

func damage_cancel_repair(ship_id: String, section: String) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var res: Dictionary = damage_service.cancel_repair(ship_id, section)
	if bool(res.get("ok", false)):
		_record({"op": "damage_cancel_repair", "ship_id": ship_id,
			"section": section})
	return res

func damage_set_priority(ship_id: String, section: String, priority: int) -> Dictionary:
	if damage_service == null:
		return {"ok": false, "reason": "no_damage_service"}
	var res: Dictionary = damage_service.set_priority(ship_id, section, priority)
	if bool(res.get("ok", false)):
		_record({"op": "damage_set_priority", "ship_id": ship_id,
			"section": section, "priority": priority})
	return res

func damage_vm(ship_id := "") -> Dictionary:
	if damage_service == null:
		return {}
	return damage_service.vm(ship_id)

func damage_ship_vm(ship_id: String) -> Dictionary:
	if damage_service == null:
		return {}
	return damage_service.ship_vm(ship_id)

func damage_summary() -> Dictionary:
	if damage_service == null:
		return {}
	return damage_service.summary()

func damage_ships() -> Array:
	if damage_service == null:
		return []
	return damage_service.ship_ids_list()
# ── PhysicsWorld 委托（位置权威；可选）──────────────────────────

func physics_vm() -> Dictionary:
	if physics_world_service == null:
		return {}
	return physics_world_service.snapshot()

func physics_summary() -> Dictionary:
	if physics_world_service == null:
		return {}
	return physics_world_service.summary()

func physics_state(entity_id: String, frame := "bary_rot") -> Dictionary:
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world"}
	return physics_world_service.state(entity_id, frame)

func physics_entity_ids() -> Array:
	if physics_world_service == null:
		return []
	return physics_world_service.entity_ids()

func physics_positions(frame := "bary_rot") -> Dictionary:
	var out: Dictionary = {}
	if physics_world_service == null:
		return out
	for id in physics_world_service.entity_ids():
		out[String(id)] = physics_world_service.state(String(id), frame)
	return out

## 位置权威读取：启用 physics 时读 physics；否则退回 world 实体位置（只读）。
func position_of(entity_id: String, frame := "bary_rot") -> Dictionary:
	if physics_world_service != null:
		return physics_world_service.state(entity_id, frame)
	if world != null and world.has_entity(entity_id):
		return {"ok": true, "source": "world", "frame": "world_entity",
			"r": (world.entity(entity_id).get("pos_km", []) as Array).duplicate(),
			"v": (world.entity(entity_id).get("vel_kmps", []) as Array).duplicate()}
	return {"ok": false, "reason": "unknown_entity"}

func upsert_physics_entity(entity_id: String, data: Dictionary) -> Dictionary:
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world"}
	var res: Dictionary = physics_world_service.upsert_entity(entity_id, data)
	if bool(res.get("ok", false)):
		_record({"op": "upsert_physics_entity", "entity_id": entity_id, "data": data})
	return res

func remove_physics_entity(entity_id: String) -> Dictionary:
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world"}
	var res: Dictionary = physics_world_service.remove_entity(entity_id)
	if bool(res.get("ok", false)):
		_record({"op": "remove_physics_entity", "entity_id": entity_id})
	return res

## 显式设置物理时间（只允许向前）：推进整个 session（time→physics→world/sensor/track/orders）
## 到目标时间，再对齐 physics 时间，保持全部组件时间一致；暂停时拒绝。
func set_physics_time(new_t: float) -> Dictionary:
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world"}
	if not is_finite(new_t) or new_t < 0.0:
		return {"ok": false, "reason": "invalid_time"}
	if bool(time.paused):
		return {"ok": false, "reason": "paused"}
	if new_t + 1.0e-9 < now_s():
		return {"ok": false, "reason": "time_regression"}
	var delta := new_t - now_s()
	if delta > 1.0e-9:
		var tr: Dictionary = tick(delta)
		if not bool(tr.get("ok", false)):
			return tr
	var pr: Dictionary = physics_world_service.set_time(new_t)
	if not bool(pr.get("ok", true)):
		return pr
	_record({"op": "set_physics_time", "t": new_t})
	_check_post()
	return {"ok": true, "t": now_s(), "physics_t": float(physics_world_service.t)}

## 显式同步边界：把 physics 实体位置/速度应用到 world（session 是唯一 world 写者；
## 不自动同步、不双写）。返回 {ok, synced, skipped, failures}。
func sync_world_from_physics() -> Dictionary:
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world", "synced": 0}
	if world == null:
		return {"ok": false, "reason": "no_world", "synced": 0}
	var synced: Array = []
	var skipped: Array = []
	var failures: Array = []
	for id in physics_world_service.entity_ids():
		var eid := String(id)
		if not world.has_entity(eid):
			skipped.append(eid)
			continue
		var st: Dictionary = physics_world_service.state(eid, "bary_rot")
		if not bool(st.get("ok", true)):
			failures.append({"id": eid, "reason": String(st.get("reason", ""))})
			continue
		var ev: Dictionary = {"type": "entity.move", "t": now_s(),
			"source": "physics_world", "target": eid,
			"payload": {"pos_km": (st.get("r", []) as Array).duplicate(),
				"vel_kmps": (st.get("v", []) as Array).duplicate()}}
		var res: Dictionary = world.apply(ev, writer)
		if bool(res.get("ok", false)):
			synced.append(eid)
			_emit_physics_sync_event(eid, st)
		else:
			failures.append({"id": eid, "reason": String(res.get("reason", ""))})
	var ok := failures.is_empty()
	if not synced.is_empty():
		_record({"op": "sync_world_from_physics"})
	return {"ok": ok, "synced": synced, "skipped": skipped,
		"failures": failures, "count": synced.size()}

func _emit_physics_sync_event(entity_id: String, st: Dictionary) -> void:
	_publish({"type": "physics.world_synced", "t": now_s(),
		"source": "physics_world", "target": entity_id,
		"payload": {"id": entity_id, "r": (st.get("r", []) as Array).duplicate(),
			"v": (st.get("v", []) as Array).duplicate(), "frame": "bary_rot"},
		"text_key": ""})
# ── SignalService 委托（ELINT / 可见光灯语；可选）──────────────

func signal_intercept(target_id := "", opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.intercept(target_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "signal_intercept", "target_id": target_id, "opts": opts})
	_flush_component_events()
	return res

func signal_df(target_id := "") -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.df(target_id)
	if bool(res.get("ok", false)):
		_record({"op": "signal_df", "target_id": target_id})
	_flush_component_events()
	return res

func signal_resolve(entity_or_fix_id: String) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.resolve(entity_or_fix_id)
	if bool(res.get("ok", false)):
		_record({"op": "signal_resolve", "id": entity_or_fix_id})
	return res

func light_send(code_id: String, target_id: String, opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.light_send(code_id, target_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "light_send", "code_id": code_id,
			"target_id": target_id, "opts": opts})
	_flush_component_events()
	return res

func light_receive(tx_id: String, opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.light_receive(tx_id, opts)
	if bool(res.get("ok", false)):
		_record({"op": "light_receive", "tx_id": tx_id, "opts": opts})
	_flush_component_events()
	return res

func light_ack(tx_id: String) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.light_ack(tx_id)
	if bool(res.get("ok", false)):
		_record({"op": "light_ack", "tx_id": tx_id})
	_flush_component_events()
	return res

func signal_vm() -> Dictionary:
	if signal_service == null:
		return {}
	return signal_service.vm()

func signal_summary() -> Dictionary:
	if signal_service == null:
		return {}
	return signal_service.summary()

func signal_flush_events() -> Dictionary:
	return _flush_signal_events()
# ── Signal 动态目标包装（灯语/ELINT；不写 world）────────────────

func signal_upsert_target(target) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.upsert_target(target)
	if bool(res.get("ok", false)):
		_record({"op": "signal_upsert_target", "target": target})
		_flush_component_events()
	return res

func signal_remove_target(target_id: String) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.remove_target(target_id)
	if bool(res.get("ok", false)):
		_record({"op": "signal_remove_target", "target_id": target_id})
		_flush_component_events()
	return res

func signal_set_targets(rows) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.set_targets(rows)
	if bool(res.get("ok", false)):
		_record({"op": "signal_set_targets", "targets": rows})
		_flush_component_events()
	return res

func signal_sync_targets(rows, opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	var res: Dictionary = signal_service.sync_targets(rows, opts)
	if bool(res.get("ok", false)):
		_record({"op": "signal_sync_targets", "targets": rows, "opts": opts})
		_flush_component_events()
	return res

func signal_target_ids() -> Array:
	if signal_service == null:
		return []
	return signal_service.target_ids()

func signal_target(target_id: String) -> Dictionary:
	if signal_service == null:
		return {}
	return signal_service.target(target_id)

## 从 world 实体同步目标（只读 world；不写 world）。opts: replace_metadata/light_capable/
## receiver_facing/default_side。
func signal_sync_from_world(opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	if world == null:
		return {"ok": false, "reason": "no_world"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var rows: Array = []
	for raw in world.entities_sorted():
		if not (raw is Dictionary):
			continue
		var we: Dictionary = raw
		var eid := String(we.get("id", ""))
		if eid == "":
			continue
		var pos = we.get("pos_km", [0.0, 0.0, 0.0])
		if not (pos is Array) or (pos as Array).size() != 3:
			pos = [0.0, 0.0, 0.0]
		rows.append({
			"id": eid, "entity_id": eid,
			"batch": String(we.get("batch", "")),
			"side": _scene_side(String(we.get("side", we.get("identity",
				o.get("default_side", "unknown"))))),
			"pos_km": (pos as Array).duplicate(),
			"occluded": bool(we.get("occluded", false)),
			"light_capable": bool(we.get("light_capable", o.get("light_capable", true))),
			"receiver_facing": bool(we.get("receiver_facing", o.get("receiver_facing", true))),
			"active": bool(we.get("active", true)),
			"destroyed": bool(we.get("destroyed", false)),
			"source": "world"})
	var res: Dictionary = signal_sync_targets(rows, {"replace_metadata": bool(o.get("replace_metadata", false))})
	res["source"] = "world"
	return res

## 从 TrackTable 接触（track_vm）同步目标：id 优先 entity_id，其次 track_id。
func signal_sync_from_contacts(opts := {}) -> Dictionary:
	if signal_service == null:
		return {"ok": false, "reason": "no_signal_service"}
	if track_table == null:
		return {"ok": false, "reason": "no_track_table"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var rows: Array = []
	for raw in track_table.vm().get("tracks", []):
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var entity_id := String(tr.get("entity_id", ""))
		var tid := entity_id if entity_id != "" else String(tr.get("id", ""))
		if tid == "":
			continue
		rows.append({
			"id": tid, "entity_id": entity_id,
			"batch": String(tr.get("batch", "")),
			"side": _track_side(tr), "identity": String(tr.get("identity", "unknown")),
			"pos_km": [0.0, 0.0, 0.0],
			"light_capable": bool(o.get("light_capable", true)),
			"receiver_facing": bool(o.get("receiver_facing", true)),
			"source": "contact", "track_id": String(tr.get("id", "")),
			"track_level": int(tr.get("level", 0))})
	var res: Dictionary = signal_sync_targets(rows, {"replace_metadata": bool(o.get("replace_metadata", false))})
	res["source"] = "contacts"
	return res

func _scene_side(side: String) -> String:
	var s := side.to_lower()
	if s in ["friend", "friendly", "assumed_friend"]:
		return "friend"
	if s in ["neutral"]:
		return "neutral"
	if s in ["hostile", "enemy", "suspect"]:
		return "hostile"
	return "unknown"

func _track_side(tr: Dictionary) -> String:
	var ident := String(tr.get("identity", "unknown")).to_lower()
	if ident in ["friend", "assumed_friend"]:
		return "friend"
	if ident == "neutral":
		return "neutral"
	if ident in ["hostile", "suspect"]:
		return "hostile"
	var threat := String(tr.get("threat", "none")).to_lower()
	if threat == "hostile":
		return "hostile"
	return "unknown"
# ── FacilityRegistry 委托（只读设施注册表；可选）────────────────

func facility_lookup(facility_id: String) -> Dictionary:
	if facility_registry == null:
		return {}
	return facility_registry.facility_card(facility_id)

func facility_by_transponder(transponder_code: String) -> Dictionary:
	if facility_registry == null:
		return {"ok": false, "reason": "no_facility_registry"}
	return facility_registry.classify_transponder(transponder_code)

func facility_for_entity(entity_id: String) -> Dictionary:
	if facility_registry == null:
		return {}
	return facility_registry.facility_for_entity(entity_id)

func facilities_by_cluster(cluster_id: String) -> Array:
	if facility_registry == null:
		return []
	return facility_registry.facilities_by_cluster(cluster_id)

func facility_vm() -> Dictionary:
	if facility_registry == null:
		return {}
	return facility_registry.to_dict()

func facility_summary() -> Dictionary:
	if facility_registry == null:
		return {}
	return facility_registry.summary()
# ── TransponderService 委托（应答机行为层；可选）────────────────

func transponder_interrogate(source_id: String, target_id: String,
		mode := "", opts := {}) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.interrogate(source_id, target_id, mode, opts)
	_flush_transponder_outputs(res.get("events", []), res.get("evidence", []))
	if bool(res.get("ok", false)):
		_record({"op": "transponder_interrogate", "source_id": source_id,
			"target_id": target_id, "mode": mode, "opts": opts})
	return res

func transponder_broadcast(opts := {}) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.broadcast(opts)
	_flush_transponder_outputs(res.get("events", []), res.get("evidence", []))
	return res

func transponder_passive_listen(opts := {}) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.passive_listen(opts)
	_flush_transponder_outputs(res.get("events", []), res.get("evidence", []))
	return res

func transponder_lookup_code(code: String) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	return transponder_service.lookup_code(code)

func transponder_set_status(profile_id: String, status: String) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.set_status(profile_id, status)
	_flush_transponder_outputs()
	if bool(res.get("ok", false)):
		_record({"op": "transponder_set_status", "profile_id": profile_id,
			"status": status})
	return res

func transponder_set_crypto(profile_id: String, patch: Dictionary) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.set_crypto(profile_id, patch)
	_flush_transponder_outputs()
	if bool(res.get("ok", false)):
		_record({"op": "transponder_set_crypto", "profile_id": profile_id,
			"patch": patch})
	return res

func transponder_set_jam(target_id: String, severity: float) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.set_jam(target_id, severity)
	_flush_transponder_outputs()
	if bool(res.get("ok", false)):
		_record({"op": "transponder_set_jam", "target_id": target_id,
			"severity": severity})
	return res

func transponder_set_occlusion(target_id: String, occluded: bool) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.set_occlusion(target_id, occluded)
	_flush_transponder_outputs()
	if bool(res.get("ok", false)):
		_record({"op": "transponder_set_occlusion", "target_id": target_id,
			"occluded": occluded})
	return res

func transponder_upsert_profile(profile: Dictionary) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.upsert_profile(profile)
	if bool(res.get("ok", false)):
		_record({"op": "transponder_upsert_profile", "profile": profile})
	return res

func transponder_remove_profile(profile_id: String) -> Dictionary:
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var res: Dictionary = transponder_service.remove_profile(profile_id)
	if bool(res.get("ok", false)):
		_record({"op": "transponder_remove_profile", "profile_id": profile_id})
	return res

func transponder_profile(profile_id: String) -> Dictionary:
	if transponder_service == null:
		return {}
	return transponder_service.profile(profile_id)

func transponder_vm() -> Dictionary:
	if transponder_service == null:
		return {}
	return transponder_service.vm()

func transponder_summary() -> Dictionary:
	if transponder_service == null:
		return {}
	return transponder_service.summary()

func transponder_trigger_ids() -> Array:
	if transponder_service == null:
		return []
	return transponder_service.trigger_ids()
# ── DbC ─────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("session 未 ready")
	if time != null:
		if time.now_s() + 1.0e-9 < _last_time_s:
			v.append("时间回退：%.6f < %.6f" % [time.now_s(), _last_time_s])
		if absf(time.now_s() - _last_time_s) > 1.0e-9:
			_last_time_s = time.now_s()
		if not bool(time.check_invariants().get("ok", false)):
			v.append("TimeService 不变量失败：" + str(time.check_invariants().get("violations", [])))
	if world != null:
		if world.current_writer() != writer:
			v.append("单写者冲突：world writer=%s session writer=%s" % [world.current_writer(), writer])
		if absf(float(world.clock_t_s()) - now_s()) > 1.0e-6:
			v.append("world 时钟不一致：%s != %s" % [str(world.clock_t_s()), str(now_s())])
	if orders != null:
		if absf(float(orders.t) - now_s()) > 1.0e-6 and not bool(time.paused):
			v.append("orders 时间不一致：%s != %s" % [str(orders.t), str(now_s())])
		if comms != null:
			for oid in orders.orders.keys():
				var o: Dictionary = orders.orders[oid]
				var st := String(o.get("status", ""))
				if st in ACTIVE_ORDER_STATES and String(o.get("delivery_id", "")) == "":
					v.append("订单-通信不一致：order %s status=%s 无 delivery_id" % [String(oid), st])
				if float(o.get("issued_t", -1.0)) > now_s() + 1.0e-6:
					v.append("订单 issuance 时间超过会话时间：" + String(oid))
	if track_table != null:
		if String(track_table.current_writer()) != _track_writer:
			v.append("track_table 单写者冲突")
		if absf(float(track_table.t) - now_s()) > 1.0e-6:
			v.append("track_table 时间与会话不一致：%s != %s" % [str(track_table.t), str(now_s())])
		if float(track_table.t) + 1.0e-9 < _last_track_t:
			v.append("track_table 时间回退")
		else:
			_last_track_t = float(track_table.t)
	if sensor_service != null:
		if not bool(sensor_service.ready):
			v.append("sensor_service 未就绪")
		if absf(float(sensor_service.t) - now_s()) > 1.0e-6:
			v.append("sensor 时间与会话不一致：%s != %s" % [str(sensor_service.t), str(now_s())])
	if port_service != null:
		if not bool(port_service.ready):
			v.append("port_service 未就绪")
		if absf(float(port_service.t_s) - now_s()) > 1.0e-6:
			v.append("port 时间与会话不一致：%s != %s" % [str(port_service.t_s), str(now_s())])
		if not bool(port_service.check_contracts().get("ok", false)):
			v.append("port 不变量失败")
	if combat_service != null:
		if not bool(combat_service.ready):
			v.append("combat_service 未就绪")
		if absf(float(combat_service.t) - now_s()) > 1.0e-6:
			v.append("combat 时间与会话不一致：%s != %s" % [str(combat_service.t), str(now_s())])
		if not (String(combat_service.roe) in ["DEFEND", "HOLD", "TIGHT", "FREE"]):
			v.append("combat ROE 非法：" + String(combat_service.roe))
	if damage_service != null:
		if not bool(damage_service.ready):
			v.append("damage_service 未就绪")
		if absf(float(damage_service.t) - now_s()) > 1.0e-6:
			v.append("damage 时间与会话不一致：%s != %s" % [str(damage_service.t), str(now_s())])
		if not bool(damage_service.check_contracts().get("ok", false)):
			v.append("damage 不变量失败")
	if physics_world_service != null:
		if not bool(physics_world_service.ready):
			v.append("physics_world 未就绪")
		if absf(float(physics_world_service.t) - now_s()) > 1.0e-6:
			v.append("physics 时间与会话不一致：%s != %s" % [
				str(physics_world_service.t), str(now_s())])
		if not bool(physics_world_service.check_contracts().get("ok", false)):
			v.append("physics 不变量失败")
	if signal_service != null:
		if not bool(signal_service.ready):
			v.append("signal_service 未就绪")
		if absf(float(signal_service.t) - now_s()) > 1.0e-6:
			v.append("signal 时间与会话不一致：%s != %s" % [
				str(signal_service.t), str(now_s())])
	if facility_registry != null:
		if not bool(facility_registry.ready):
			v.append("facility_registry 未就绪")
		if not bool(facility_registry.check_contracts().get("ok", false)):
			v.append("facility_registry 不变量失败")
	if transponder_service != null:
		if not bool(transponder_service.ready):
			v.append("transponder_service 未就绪")
		if absf(float(transponder_service.t) - now_s()) > 1.0e-6:
			v.append("transponder 时间与会话不一致：%s != %s" % [
				str(transponder_service.t), str(now_s())])
		if not bool(transponder_service.check_contracts().get("ok", false)):
			v.append("transponder 不变量失败")
	if story_state != null:
		if absf(float(story_state.t_s) - now_s()) > 1.0e-6:
			v.append("story 时间与会话不一致：%s != %s" % [str(story_state.t_s), str(now_s())])
		if int(story_state.revision) < _last_story_revision:
			v.append("story revision 回退")
		else:
			_last_story_revision = int(story_state.revision)
		if not bool(story_state.check_contracts().get("ok", false)):
			v.append("story 不变量失败：" + str(story_state.check_contracts().get("violations", [])))
	var out := {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}
	return out

func _contract(msg: String) -> void:
	contract_errors.append(msg)
	errors.append(msg)
	push_error("GameSession: " + msg)

# ── 只读快照 ───────────────────────────────────────────────────

func snapshot() -> Dictionary:
	if not booted:
		return {"schema": SCHEMA, "version": VERSION, "ready": false,
			"errors": errors.duplicate()}
	var order_vm: Dictionary = orders.vm() if orders != null else {}
	var bus_events: Array = bus.recent(32) if bus != null else []
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"ready": ready,
		"writer": writer,
		"t_s": now_s(),
		"t_days": now_days(),
		"paused": bool(time.paused) if time != null else true,
		"scale": float(time.scale) if time != null else 1.0,
		"time": time.snapshot() if time != null else {},
		"components": {
			"world": world.snapshot() if world != null else {},
			"orders": order_vm,
			"comms": comms.vm() if comms != null else {},
			"event_bus": {
				"seq": bus.current_seq() if bus != null else 0,
				"count": bus.count() if bus != null else 0,
				"last_event": bus.last_event() if bus != null else {},
			},
		},
		"entities": world.entities_sorted() if world != null else [],
		"track_table": track_table.snapshot() if track_table != null else null,
		"story": story_state.snapshot() if story_state != null else null,
		"sensor": sensor_service.vm() if sensor_service != null else null,
		"port": port_service.vm() if port_service != null else null,
		"combat": combat_service.vm() if combat_service != null else null,
		"damage": damage_service.vm() if damage_service != null else null,
		"physics": physics_world_service.snapshot() if physics_world_service != null else null,
		"signal": signal_service.vm() if signal_service != null else null,
		"facilities": facility_registry.summary() if facility_registry != null else null,
		"transponder": transponder_service.vm() if transponder_service != null else null,
		"track_writer": _track_writer,
		"orders_summary": orders.summary() if orders != null else {},
		"comms_summary": comms.summary() if comms != null else {},
		"events": bus_events,
		"contracts": check_contracts(),
		"contract_errors": contract_errors.duplicate(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}

func to_dict() -> Dictionary:
	return snapshot()

func to_json() -> String:
	return JSON.stringify(snapshot())

# ── 内存 save/load（seed + 操作日志重放；不写盘） ───────────────

func save_state() -> String:
	if not ready:
		return ""
	var payload := {
		"schema": SAVE_SCHEMA,
		"version": VERSION,
		"seed": JSON.parse_string(JSON.stringify(_seed)),
		"log": JSON.parse_string(JSON.stringify(_log)),
		"track_table": track_table.snapshot() if track_table != null else null,
		"story": story_state.snapshot() if story_state != null else null,
		"port_service": port_service.save_state() if port_service != null else "",
		"combat_service": combat_service.save_state() if combat_service != null else "",
		"damage_service": damage_service.save_state() if damage_service != null else "",
		"physics_world": physics_world_service.save_state() if physics_world_service != null else "",
		"signal_service": signal_service.save_state() if signal_service != null else "",
		"facility_registry": facility_registry.to_dict() if facility_registry != null else null,
		"transponder_service": transponder_service.save_state() if transponder_service != null else "",
		"bus": {
			"seq": bus.current_seq(),
			"events": JSON.parse_string(JSON.stringify(bus.events)),
		},
	}
	return JSON.stringify(payload)

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		errors.append("load_state: 空 JSON")
		return {"ok": false, "reason": "empty_state", "errors": errors.duplicate()}
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		errors.append("load_state: JSON 无效")
		return {"ok": false, "reason": "invalid_json"}
	var data: Dictionary = parsed
	if String(data.get("schema", "")) != SAVE_SCHEMA:
		errors.append("load_state: schema 无效")
		return {"ok": false, "reason": "invalid_schema"}
	var seed = data.get("seed", {})
	var log = data.get("log", [])
	if not (seed is Dictionary) or not (log is Array):
		errors.append("load_state: seed/log 类型无效")
		return {"ok": false, "reason": "invalid_payload"}
	boot(seed)
	if not ready:
		return {"ok": false, "reason": "boot_failed", "errors": errors.duplicate()}
	_replaying = true
	var replay_errors: Array = []
	for raw in (log as Array):
		if not (raw is Dictionary):
			replay_errors.append("log 项非对象")
			continue
		var res: Dictionary = _replay_op(raw as Dictionary)
		if not bool(res.get("ok", false)):
			replay_errors.append("replay %s 失败：%s" % [str((raw as Dictionary).get("op", "")),
				str(res.get("reason", ""))])
	# 恢复可选组件快照（新存档才有；旧存档缺字段 → 兼容、组件保持退化）
	var saved_track = data.get("track_table", null)
	var saved_story = data.get("story", null)
	if saved_track != null:
		if track_table == null:
			replay_errors.append("存档含 track_table 快照但 boot 未启用 track_table")
		elif not (saved_track is Dictionary):
			replay_errors.append("track_table 快照必须是对象")
		else:
			var tr: Dictionary = track_table.load_state(saved_track)
			if not bool(tr.get("ok", false)):
				replay_errors.append("track_table 快照恢复失败：" + str(tr.get("errors", [])))
			else:
				_track_writer = String(track_table.current_writer())
	if saved_story != null:
		if story_state == null:
			replay_errors.append("存档含 story 快照但 boot 未启用 story_state")
		elif not (saved_story is Dictionary):
			replay_errors.append("story 快照必须是对象")
		else:
			var sr: Dictionary = story_state.load(saved_story)
			if not bool(sr.get("ok", false)):
				replay_errors.append("story 快照恢复失败：" + str(sr.get("errors", [])))
	var saved_port = data.get("port_service", null)
	if saved_port != null and String(saved_port) != "":
		if port_service == null:
			replay_errors.append("存档含 port_service 快照但 boot 未启用 port_service")
		else:
			var pr: Dictionary = port_service.load_state(saved_port)
			if not bool(pr.get("ok", false)):
				replay_errors.append("port_service 快照恢复失败：" + str(pr.get("errors", [])))
	var saved_combat = data.get("combat_service", null)
	if saved_combat != null and String(saved_combat) != "":
		if combat_service == null:
			replay_errors.append("存档含 combat_service 快照但 boot 未启用 combat_service")
		else:
			var cr: Dictionary = combat_service.load_state(saved_combat)
			if not bool(cr.get("ok", false)):
				replay_errors.append("combat_service 快照恢复失败：" + str(cr.get("errors", [])))
	var saved_damage = data.get("damage_service", null)
	if saved_damage != null and String(saved_damage) != "":
		if damage_service == null:
			replay_errors.append("存档含 damage_service 快照但 boot 未启用 damage_service")
		else:
			var dr: Dictionary = damage_service.load_state(saved_damage)
			if not bool(dr.get("ok", false)):
				replay_errors.append("damage_service 快照恢复失败：" + str(dr.get("errors", [])))
	var saved_physics = data.get("physics_world", null)
	if saved_physics != null and String(saved_physics) != "":
		if physics_world_service == null:
			replay_errors.append("存档含 physics_world 快照但 boot 未启用 physics_world")
		else:
			var pr: Dictionary = physics_world_service.load_state(saved_physics)
			if not bool(pr.get("ok", false)):
				replay_errors.append("physics_world 快照恢复失败：" + str(pr.get("errors", [])))
	var saved_signal = data.get("signal_service", null)
	if saved_signal != null and String(saved_signal) != "":
		if signal_service == null:
			replay_errors.append("存档含 signal_service 快照但 boot 未启用 signal_service")
		else:
			var sr: Dictionary = signal_service.load_state(saved_signal)
			if not bool(sr.get("ok", false)):
				replay_errors.append("signal_service 快照恢复失败：" + str(sr.get("errors", [])))
	var saved_fac = data.get("facility_registry", null)
	if saved_fac != null:
		if facility_registry == null:
			replay_errors.append("存档含 facility_registry 快照但 boot 未启用 facility_registry")
		elif not (saved_fac is Dictionary):
			replay_errors.append("facility_registry 快照必须是对象")
		else:
			var fac_ok: bool = facility_registry.load_data(saved_fac)
			if not fac_ok:
				replay_errors.append("facility_registry 快照恢复失败：" + str(facility_registry.errors))
	var saved_txp = data.get("transponder_service", null)
	if saved_txp != null and String(saved_txp) != "":
		if transponder_service == null:
			replay_errors.append("存档含 transponder_service 快照但 boot 未启用 transponder_service")
		else:
			var txr: Dictionary = transponder_service.load_state(saved_txp)
			if not bool(txr.get("ok", false)):
				replay_errors.append("transponder_service 快照恢复失败：" + str(txr.get("errors", [])))
	# 恢复事件总线历史（旧存档无 bus 字段 → 兼容）
	var saved_bus = data.get("bus", null)
	if saved_bus is Dictionary:
		var evs = (saved_bus as Dictionary).get("events", [])
		if evs is Array:
			bus.events = JSON.parse_string(JSON.stringify(evs))
			bus.seq = int((saved_bus as Dictionary).get("seq", bus.events.size()))
			for raw_ev in bus.events:
				if raw_ev is Dictionary:
					bus._seen_ids[String((raw_ev as Dictionary).get("id", ""))] = true
	_replaying = false
	_log = (log as Array).duplicate(true)
	if track_table != null:
		_last_track_t = float(track_table.t)
	if story_state != null:
		_last_story_revision = int(story_state.revision)
	_last_bus_routed_index = bus.events.size()
	_routed_seqs = {}
	_last_time_s = now_s()
	ready = replay_errors.is_empty() and errors.is_empty()
	return {"ok": ready, "errors": replay_errors, "result_errors": errors.duplicate()}

func _replay_op(op: Dictionary) -> Dictionary:
	var kind := String(op.get("op", ""))
	match kind:
		"tick":
			return tick(float(op.get("dt", 0.0)))
		"issue_order":
			return issue_order(String(op.get("action", "")), String(op.get("issuer_id", "")),
				op.get("target_ids", []), op.get("params", {}), op.get("opts", {}))
		"authorize_order":
			return authorize_order(String(op.get("order_id", "")),
				String(op.get("authorizer_id", "")))
		"begin_execute_order":
			return begin_execute_order(String(op.get("order_id", "")))
		"complete_order":
			return complete_order(String(op.get("order_id", "")), op.get("result", {}))
		"abort_order":
			return abort_order(String(op.get("order_id", "")), String(op.get("reason", "aborted")))
		"reject_order":
			return reject_order(String(op.get("order_id", "")), String(op.get("reason", "rejected")),
				String(op.get("by", "")))
		"send_comms":
			return send_comms(String(op.get("from_id", "")), String(op.get("to_id", "")),
				String(op.get("mode", "LD")), String(op.get("text_key", "COMMS_SENT")),
				op.get("payload", {}), op.get("opts", {}))
		"set_link":
			return set_link(String(op.get("a", "")), String(op.get("b", "")), op.get("opts", {}))
		"handle_observation":
			return handle_observation(op.get("event", {}))
		"handle_evidence":
			return handle_evidence(op.get("event", {}))
		"handle_story_evidence":
			return handle_story_evidence(String(op.get("evidence_id", "")))
		"route_event":
			return route_event(op.get("event", {}))
		"set_sensor_target":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return set_sensor_target(String(op.get("target_id", "")))
		"start_sensor_channel":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return start_sensor_channel(String(op.get("kind", "")),
				String(op.get("target", "")), op.get("opts", {}))
		"stop_sensor_channel":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return stop_sensor_channel(String(op.get("kind", "")),
				String(op.get("target", "")))
		"set_radar_enabled":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return set_radar_enabled(bool(op.get("on", true)))
		"set_emcon":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return set_emcon(bool(op.get("on", false)))
		"query_iff":
			if sensor_service == null:
				return {"ok": true, "skipped": "no_sensor_service"}
			return query_iff(String(op.get("target_id", "")))
		"port_request":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_request(String(op.get("kind", "")), String(op.get("ship_id", "")),
				String(op.get("port_id", "")), op.get("opts", {}))
		"port_permit":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_permit(String(op.get("request_id", "")))
		"port_approach":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_approach(String(op.get("request_id", "")))
		"port_dock":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_dock(String(op.get("request_id", "")))
		"port_refuel":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_refuel(String(op.get("request_id", "")), float(op.get("amount_t", 0.0)))
		"port_repair":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_repair(String(op.get("request_id", "")), op.get("opts", {}))
		"port_finish_service":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_finish_service(String(op.get("request_id", "")))
		"port_undock":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_undock(String(op.get("request_id", "")))
		"port_tow":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_tow(String(op.get("ship_id", "")), String(op.get("port_id", "")),
				op.get("opts", {}))
		"port_shuttle":
			if port_service == null:
				return {"ok": true, "skipped": "no_port_service"}
			return port_shuttle(String(op.get("ship_id", "")), String(op.get("port_id", "")),
				op.get("opts", {}))
		"set_roe":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return set_roe(String(op.get("level", "")))
		"combat_register_track":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return combat_register_track(String(op.get("track_id", "")), op.get("data", {}))
		"combat_request_solution":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return combat_request_solution(String(op.get("target_id", "")),
				String(op.get("weapon_id", "")), bool(op.get("confirmed", false)))
		"grant_authorization":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return grant_authorization(String(op.get("level", "")),
				String(op.get("scope_type", "target")), String(op.get("scope_id", "")),
				float(op.get("duration_s", 0.0)), bool(op.get("until_destroyed", false)))
		"revoke_authorization":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return revoke_authorization(String(op.get("grant_id", "")))
		"request_fire":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return request_fire(String(op.get("target_id", "")),
				String(op.get("weapon_id", "")), bool(op.get("confirmed", false)))
		"combat_tick":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return combat_tick(float(op.get("dt", 0.0)))
		"damage_apply_event":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_apply_event(op.get("event", {}), op.get("opts", {}))
		"damage_apply_hit":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_apply_hit(String(op.get("ship_id", "")),
				String(op.get("section", "")), float(op.get("energy", 0.0)),
				float(op.get("penetration", 0.5)), String(op.get("direction", "fore")),
				String(op.get("source", "manual")))
		"damage_repair":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_repair(String(op.get("ship_id", "")),
				String(op.get("section", "")), int(op.get("priority", 2)))
		"damage_fix":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_fix(String(op.get("ship_id", "")),
				String(op.get("section", "")), int(op.get("priority", 2)))
		"damage_cancel_repair":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_cancel_repair(String(op.get("ship_id", "")),
				String(op.get("section", "")))
		"damage_set_priority":
			if damage_service == null:
				return {"ok": true, "skipped": "no_damage_service"}
			return damage_set_priority(String(op.get("ship_id", "")),
				String(op.get("section", "")), int(op.get("priority", 2)))
		"upsert_physics_entity":
			if physics_world_service == null:
				return {"ok": true, "skipped": "no_physics_world"}
			return upsert_physics_entity(String(op.get("entity_id", "")), op.get("data", {}))
		"remove_physics_entity":
			if physics_world_service == null:
				return {"ok": true, "skipped": "no_physics_world"}
			return remove_physics_entity(String(op.get("entity_id", "")))
		"set_physics_time":
			if physics_world_service == null:
				return {"ok": true, "skipped": "no_physics_world"}
			return set_physics_time(float(op.get("t", 0.0)))
		"sync_world_from_physics":
			if physics_world_service == null:
				return {"ok": true, "skipped": "no_physics_world"}
			return sync_world_from_physics()
		"signal_intercept":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_intercept(String(op.get("target_id", "")), op.get("opts", {}))
		"signal_df":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_df(String(op.get("target_id", "")))
		"signal_resolve":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_resolve(String(op.get("id", "")))
		"light_send":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return light_send(String(op.get("code_id", "")),
				String(op.get("target_id", "")), op.get("opts", {}))
		"light_receive":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return light_receive(String(op.get("tx_id", "")), op.get("opts", {}))
		"light_ack":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return light_ack(String(op.get("tx_id", "")))
		"signal_upsert_target":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_upsert_target(op.get("target", {}))
		"signal_remove_target":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_remove_target(String(op.get("target_id", "")))
		"signal_set_targets":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_set_targets(op.get("targets", []))
		"signal_sync_targets":
			if signal_service == null:
				return {"ok": true, "skipped": "no_signal_service"}
			return signal_sync_targets(op.get("targets", []), op.get("opts", {}))
		"transponder_interrogate":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_interrogate(str(op.get("source_id", "")),
				str(op.get("target_id", "")), str(op.get("mode", "")), op.get("opts", {}))
		"transponder_set_status":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_set_status(str(op.get("profile_id", "")),
				str(op.get("status", "")))
		"transponder_set_crypto":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_set_crypto(str(op.get("profile_id", "")), op.get("patch", {}))
		"transponder_set_jam":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_set_jam(str(op.get("target_id", "")),
				float(op.get("severity", 0.0)))
		"transponder_set_occlusion":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_set_occlusion(str(op.get("target_id", "")),
				bool(op.get("occluded", false)))
		"transponder_upsert_profile":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_upsert_profile(op.get("profile", {}))
		"transponder_remove_profile":
			if transponder_service == null:
				return {"ok": true, "skipped": "no_transponder_service"}
			return transponder_remove_profile(str(op.get("profile_id", "")))
		"pause":
			return pause()
		"resume":
			return resume()
		"set_scale":
			return set_scale(float(op.get("scale", 1.0)))
		_:
			return {"ok": false, "reason": "unknown_op"}

func _record(entry: Dictionary) -> void:
	if _replaying:
		return
	_log.append(_json_norm(entry))

func _json_norm(value):
	var s := JSON.stringify(value)
	if s == "" or s == "null":
		return value
	return JSON.parse_string(s)

func reset() -> Dictionary:
	return boot(_seed)

func _result(ok: bool) -> Dictionary:
	return {"ok": ok, "ready": ready, "booted": booted,
		"writer": writer, "t_s": now_s(), "errors": errors.duplicate(),
		"warnings": warnings.duplicate(), "snapshot": snapshot()}
