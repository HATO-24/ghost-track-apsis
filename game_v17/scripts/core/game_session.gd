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
const EntityCatalogScript := preload("res://scripts/core/entity_catalog.gd")
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
const EWServiceScript := preload("res://scripts/core/ew_service.gd")
const FacilityRegistryScript := preload("res://scripts/core/facility_registry.gd")
const TransponderServiceScript := preload("res://scripts/core/transponder_service.gd")
const IdentificationServiceScript := preload("res://scripts/core/identification_service.gd")
const LegalStatusServiceScript := preload("res://scripts/core/legal_status_service.gd")
const TrafficControlServiceScript := preload("res://scripts/core/traffic_control_service.gd")
const PhysicsScript := preload("res://framework/sim/cislunar_physics.gd")
const CombatBallisticsScript := preload("res://scripts/core/combat_ballistics.gd")
const CombatPlannerScript := preload("res://scripts/core/combat_planner.gd")
const AuthorityIntelScript := preload("res://scripts/core/authority_intel.gd")
const ShipCatalogScript := preload("res://scripts/core/ship_catalog.gd")
const RefitServiceScript := preload("res://scripts/core/refit_service.gd")
const DamageProfileServiceScript := preload("res://scripts/core/damage_profile_service.gd")
const FleetRefitServiceScript := preload("res://scripts/core/fleet_refit_service.gd")
const FleetFormationServiceScript := preload("res://scripts/core/fleet_formation.gd")

const SCHEMA := "v17.game_session.v1"
const SAVE_SCHEMA := "v17.game_session_save.v1"
const VERSION := "1.0.0"
const WRITER_DEFAULT := "session"
const FRAME_BARY_ROT := "bary_rot"
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
var entity_catalog = null
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
var ew_service = null
var facility_registry = null
var transponder_service = null
var identification_service = null
var legal_status_service = null
var traffic_control = null
var combat_ballistics = null
var ship_catalog = null
var refit_service = null
var damage_profile_service = null
var fleet_refit = null
var fleet_formation = null

## 交战时间膨胀：有弹在飞时把时间倍速压到该上限，交战结束恢复原倍速。
const COMBAT_SCALE_CAP := 60.0
var _combat_scale_cap_active := false
var _scale_before_combat := 1.0

var _track_enabled := false
var _sensor_enabled := false
var _port_enabled := false
var _combat_enabled := false
var _damage_enabled := false
var _physics_enabled := false
var _physics_frame_meta: Dictionary = {}
# A0-T1：WorldState 位置/速度副本同步策略（PhysicsWorld 唯一写入者）。
#   "tick"   — 每个业务 tick 边界把 physics 只读副本写入 world（默认，仅当
#              seed 与 physics 同坐标空间时启用）；
#   "frame_mismatch" — seed 经过 L1→bary_rot 帧转换，world 副本仍是另一坐标
#              语义，显式不同步并记录原因（不猜测、不做隐式转换）；
#   "no_physics" / "disabled" — 无 physics 或显式关闭。
const WORLD_SYNC_MODE_TICK := "tick"
const WORLD_SYNC_MODE_FRAME_MISMATCH := "frame_mismatch"
const WORLD_SYNC_MODE_NO_PHYSICS := "no_physics"
const WORLD_SYNC_MODE_DISABLED := "disabled"
var _world_sync_mode := WORLD_SYNC_MODE_NO_PHYSICS
var _world_sync_last: Dictionary = {}
var _world_sync_total := 0
var _signal_enabled := false
var _ew_enabled := false
var _facility_enabled := false
var _transponder_enabled := false
var _identification_enabled := false
var _legal_enabled := false
var _traffic_enabled := false
var _ballistics_enabled := false
# JC-A01：指挥权限与分方情报（授权门 + owner 隔离读入口）
var authority_intel = null
var _authority_enabled := false
# JC-A01：经 Comms 链路在途的情报共享（发出→到达→仅接收方融合）
var _pending_intel_shares: Dictionary = {}
# JC-A01/R5：授权/情报恢复模式与原因（公开披露，不污染 snapshot）
var _authority_restore_mode := ""
var _authority_restore_reasons: Array = []
# JC-A01/R4：最近一次共享到达的判定结果（诊断用，不写 snapshot）
var _last_intel_share_result: Dictionary = {}
var _ship_catalog_enabled := false
var _refit_enabled := false
var _fleet_refit_enabled := false
var _fleet_formation_enabled := false
var _last_signal_route: Dictionary = {}
var _signal_missing_meta_warned: Dictionary = {}
var _damage_applied_shots: Dictionary = {}
var _story_enabled := false
var _track_writer := ""
var _last_track_t := 0.0
var _last_story_revision := 0
var _last_bus_routed_index := 0
var _routed_seqs: Dictionary = {}
# A-04：旧档迁移报告（支持矩阵 + 可恢复范围 + 无法恢复项，诚实标注）
var _legacy_migration: Dictionary = {}
# A-05：传感器运行态恢复报告（重绑定结果 + 几何同刻复核）
var _sensor_restore_report: Dictionary = {}
# A-06：通信操作重放核对记录（原始 outcome vs 重放 outcome，逐项）
var _comms_restore: Array = []
var _sensor_track_map: Dictionary = {}
var _sensor_target_meta: Dictionary = {}

var _seed: Dictionary = {}
var _log: Array = []
var _replaying := false
var _standalone: Dictionary = {}   # delivery_id -> {from,to,mode,text_key,sent_t}
var _comms_event_ids: Dictionary = {}   # 本 tick 已收到真实结果的 delivery_id
var _comms_legacy_unknown := 0
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
			"track_table", "story_state", "sensor_service", "port_service", "combat_service", "damage_service", "physics_world", "signal_service", "ew_service", "facility_registry", "transponder_service", "identification_service", "legal_status", "traffic_control", "combat_ballistics", "ship_catalog", "refit", "fleet_refit", "fleet_formation", "damage_profiles", "prelude", "seed_frame", "frame_origin", "own_entity", "epoch", "command_domains", "fleet_instances", "own_fleet", "comms_ew_seed"]:
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
	entity_catalog = null
	signal_service = null
	ew_service = null
	facility_registry = null
	transponder_service = null
	identification_service = null
	legal_status_service = null
	traffic_control = null
	combat_ballistics = null
	ship_catalog = null
	refit_service = null
	damage_profile_service = null
	fleet_refit = null
	fleet_formation = null
	_last_signal_route = {}
	_signal_missing_meta_warned = {}
	_damage_applied_shots = {}
	_track_enabled = false
	_story_enabled = false
	_sensor_enabled = false
	_port_enabled = false
	_combat_enabled = false
	_damage_enabled = false
	_identification_enabled = false
	_legal_enabled = false
	_traffic_enabled = false
	_ballistics_enabled = false
	_ship_catalog_enabled = false
	_refit_enabled = false
	_fleet_refit_enabled = false
	_fleet_formation_enabled = false
	_physics_enabled = false
	_physics_frame_meta = {}
	_world_sync_mode = WORLD_SYNC_MODE_NO_PHYSICS
	_world_sync_last = {}
	_world_sync_total = 0
	_track_writer = ""
	_last_track_t = 0.0
	_last_story_revision = 0
	_last_bus_routed_index = 0
	_routed_seqs = {}
	_sensor_track_map = {}
	_sensor_target_meta = {}
	_seed = _normalize_seed(config if config is Dictionary else {})
	_seed = _json_norm(_seed)
	# Phase A1.1：静态元数据唯一权威（scenario/seed → EntityCatalog）。
	# 只保存静态资料；位置/速度仍归 PhysicsWorld，world 保持既有职责。
	entity_catalog = EntityCatalogScript.new({
		"entities": _seed.get("entities", []),
		"source": "seed",
	})
	if not bool(entity_catalog.ready):
		errors.append("entity_catalog 未就绪：" + str(entity_catalog.errors))
	writer = String(_seed.get("writer", WRITER_DEFAULT))
	# A-02：把 scenario 日历历元（UTC）作为**唯一来源**交给 TimeService；
	# 与 CR3BP 相位基准（time.epoch_s）分开，不互相替换。
	var time_cfg: Dictionary = _seed.get("time", {}) if _seed.get("time") is Dictionary else {}
	var time_cfg2: Dictionary = time_cfg.duplicate(true)
	var scenario_epoch := String(_seed.get("epoch", "")).strip_edges()
	if scenario_epoch != "" and not time_cfg2.has("epoch_utc"):
		time_cfg2["epoch_utc"] = scenario_epoch
	time = TimeService.new(time_cfg2)
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
	# JC-A04：三条真实发送入口共用同一 Comms；EW 采样/确定性 RNG 在此接线。
	if comms != null and ew_service != null:
		comms.set_ew_service(ew_service)
	if comms != null:
		comms.set_ew_rng(int(_seed.get("comms_ew_seed", 0)))
	if orders != null:
		orders.set_comms_event_sink(Callable(self, "_on_comms_events"))
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
	if _ew_enabled and ew_service != null and not bool(ew_service.ready):
		extra_ok = false
	if _facility_enabled and facility_registry != null and not bool(facility_registry.ready):
		extra_ok = false
	if _transponder_enabled and transponder_service != null and not bool(transponder_service.ready):
		extra_ok = false
	if _identification_enabled and identification_service != null and not bool(identification_service.ready):
		extra_ok = false
	if _legal_enabled and legal_status_service != null and not bool(legal_status_service.ready):
		extra_ok = false
	if _traffic_enabled and traffic_control != null and not bool(traffic_control.ready):
		extra_ok = false
	if _ballistics_enabled and combat_ballistics != null and not bool(combat_ballistics.ready):
		extra_ok = false
	if _ship_catalog_enabled and ship_catalog != null and not bool(ship_catalog.ready):
		extra_ok = false
	if _refit_enabled and refit_service != null and not bool(refit_service.ready):
		extra_ok = false
	if _fleet_refit_enabled and fleet_refit != null and not bool(fleet_refit.ready):
		extra_ok = false
	if _fleet_formation_enabled and fleet_formation != null and not bool(fleet_formation.ready):
		extra_ok = false
	if damage_profile_service != null and not bool(damage_profile_service.ready):
		extra_ok = false
	if not bool(time.ready) or not bool(bus.ready) or not bool(world.ready) \
			or not bool(orders.ready) or not bool(comms.ready) \
			or not bool(entity_catalog.ready) or not extra_ok:
		errors.append("session 组件未就绪：time=%s bus=%s world=%s orders=%s comms=%s catalog=%s" % [
			str(time.ready), str(bus.ready), str(world.ready),
			str(orders.ready), str(comms.ready), str(entity_catalog.ready)])
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
	if ew_service != null:
		ew_service.t = now_s()
	if transponder_service != null:
		transponder_service.set_time(now_s())
	if identification_service != null:
		identification_service.set_time(now_s())
	if legal_status_service != null:
		legal_status_service.t = now_s()
	if traffic_control != null:
		traffic_control.t = now_s()
	if combat_ballistics != null:
		combat_ballistics.t = now_s()
	_damage_applied_shots = {}
	_last_bus_routed_index = bus.count()
	_flush_component_events()
	_last_bus_routed_index = bus.count()
	_last_time_s = time.now_s()
	# A0-T1：确定 world 位置副本同步策略，并在 boot 时把同一时刻的 physics 只读
	# 副本写入 world（world 只由 session 写；PhysicsWorld 仍是位置/速度唯一权威）。
	_world_sync_mode = _resolve_world_sync_mode()
	world_physics_sync("boot")
	# A0-T2：把传感器几何绑定到同一物理世界（失败/异帧时显式退化为静态几何）。
	var sensor_geom: Dictionary = _bind_sensor_geometry()
	# A-01：把静态特征与运动状态的只读权威注入弹道，保证弹道初始状态可追溯。
	var ballistics_authority: Dictionary = _wire_ballistics_authority()
	booted = true
	ready = errors.is_empty()
	var boot_res: Dictionary = _result(ready)
	boot_res["sensor_geometry"] = sensor_geom.duplicate(true)
	boot_res["ballistics_authority"] = ballistics_authority.duplicate(true)
	return boot_res


## A0-T1：WorldState 位置副本同步策略判定（只读；不推进任何服务时间）。
## 只有 seed 与 physics 处于同一坐标语义（未做 L1→bary_rot 帧转换）时才自动同步，
## 否则显式不同步并记录 frame_mismatch —— 不做隐式跨帧搬运。
func _resolve_world_sync_mode() -> String:
	if not _physics_enabled or physics_world_service == null:
		return WORLD_SYNC_MODE_NO_PHYSICS
	if world == null:
		return WORLD_SYNC_MODE_NO_PHYSICS
	if bool(_physics_frame_meta.get("applied", false)):
		return WORLD_SYNC_MODE_FRAME_MISMATCH
	return WORLD_SYNC_MODE_TICK


## A0-T1：tick 边界同步入口。把 PhysicsWorld 当前时刻的 r/v 作为**只读副本**写入
## WorldState（world 写者仍是 session）；绝不反向写 physics，也不推进 physics 时间。
## reason 仅用于区分触发点（boot/tick/explicit），不改变语义。
##
## 返回字段语义（审查修正：成功写回 ≠ 未对齐）：
##   updated      — 本次同步**成功写回**的实体 id 列表（本次被修复的对象）
##   mismatched   — 同步**之后**仍未与 physics 对齐的实体（正常情况下应为空；
##                  仅当写入失败/被拒时才有内容，此时同时出现在 failures）
##   failures     — 写入失败的 {id, reason}
##   skipped      — physics 有但 world 没有的实体（不在副本范围）
##   compared     — 本次参与比较的实体数
##   in_sync      — 同步后整体是否逐位一致（== mismatched 为空且 failures 为空）
func world_physics_sync(reason := "tick") -> Dictionary:
	var out := {"ok": true, "enabled": false, "in_sync": false, "frame": "",
		"mode": _world_sync_mode, "reason": reason, "synced": 0, "compared": 0,
		"updated": [], "mismatched": [], "failures": [], "skipped": []}
	if _world_sync_mode != WORLD_SYNC_MODE_TICK:
		out["enabled"] = false
		out["sync_reason"] = _world_sync_mode
		if _world_sync_mode == WORLD_SYNC_MODE_FRAME_MISMATCH:
			out["in_sync"] = false
		else:
			# 无 physics：world 是唯一来源，视作自洽（不比较）。
			out["in_sync"] = true
		_world_sync_last = out.duplicate(true)
		return out
	if world == null or physics_world_service == null:
		out["ok"] = false
		out["sync_reason"] = "missing_component"
		_world_sync_last = out.duplicate(true)
		return out
	out["enabled"] = true
	out["frame"] = FRAME_BARY_ROT
	var updated: Array = []
	var failures: Array = []
	var skipped: Array = []
	for id in physics_world_service.entity_ids():
		var eid := String(id)
		if not world.has_entity(eid):
			skipped.append(eid)
			continue
		var st: Dictionary = physics_world_service.state(eid, FRAME_BARY_ROT)
		var r = st.get("r", null)
		var v = st.get("v", null)
		if not (r is Array) or (r as Array).size() < 3 \
				or not (v is Array) or (v as Array).size() < 3:
			failures.append({"id": eid, "reason": "non_finite_state"})
			continue
		out["compared"] = int(out["compared"]) + 1
		var cur: Dictionary = world.entity(eid)
		var cur_r: Array = cur.get("pos_km", []) if cur.get("pos_km") is Array else []
		var cur_v: Array = cur.get("vel_kmps", []) if cur.get("vel_kmps") is Array else []
		if _vec3_equal(cur_r, r) and _vec3_equal(cur_v, v):
			continue
		var ev: Dictionary = {"type": "entity.move", "t": now_s(),
			"source": "physics_world", "target": eid,
			"payload": {"pos_km": (r as Array).duplicate(),
				"vel_kmps": (v as Array).duplicate()}}
		var res: Dictionary = world.apply(ev, writer)
		if bool(res.get("ok", false)):
			updated.append(eid)
			# 注意：tick 边界同步是机械副本写入，不逐实体发 bus 事件（避免每 tick
			# 7 条噪声）；显式 sync_world_from_physics() 仍发布 physics.world_synced。
		else:
			failures.append({"id": eid, "reason": String(res.get("reason", ""))})
	# 同步后再全量复核一次：mismatched 只装「同步后仍未对齐」的实体。
	var mismatched: Array = []
	for id2 in physics_world_service.entity_ids():
		var eid2 := String(id2)
		if not world.has_entity(eid2):
			continue
		var st2: Dictionary = physics_world_service.state(eid2, FRAME_BARY_ROT)
		var cur2: Dictionary = world.entity(eid2)
		var cur_r2: Array = cur2.get("pos_km", []) if cur2.get("pos_km") is Array else []
		var cur_v2: Array = cur2.get("vel_kmps", []) if cur2.get("vel_kmps") is Array else []
		if not _vec3_equal(cur_r2, st2.get("r", [])) \
				or not _vec3_equal(cur_v2, st2.get("v", [])):
			mismatched.append({"id": eid2, "world_pos_km": cur_r2,
				"physics_pos_km": st2.get("r", [])})
	out["synced"] = updated.size()
	out["updated"] = updated
	out["mismatched"] = mismatched
	out["failures"] = failures
	out["skipped"] = skipped
	out["ok"] = failures.is_empty()
	out["in_sync"] = out["ok"] and mismatched.is_empty()
	if not updated.is_empty():
		_world_sync_total += 1
	_world_sync_last = out.duplicate(true)
	return out


## A0-T1：当前 world 副本是否与 physics 同一时刻一致（只读比较，不写入）。
func _world_copy_in_sync() -> bool:
	if world == null or physics_world_service == null:
		return false
	for id in physics_world_service.entity_ids():
		var eid := String(id)
		if not world.has_entity(eid):
			continue
		var st: Dictionary = physics_world_service.state(eid, FRAME_BARY_ROT)
		var cur: Dictionary = world.entity(eid)
		var cur_r: Array = cur.get("pos_km", []) if cur.get("pos_km") is Array else []
		var cur_v: Array = cur.get("vel_kmps", []) if cur.get("vel_kmps") is Array else []
		if not _vec3_equal(cur_r, st.get("r", [])) or not _vec3_equal(cur_v, st.get("v", [])):
			return false
	return true


func _vec3_equal(a: Array, b: Array) -> bool:
	if not (a is Array) or not (b is Array) or a.size() < 3 or b.size() < 3:
		return false
	for i in range(3):
		var x = a[i]
		var y = b[i]
		if not ((x is int or x is float) and (y is int or y is float)):
			return false
		# 逐位相等：副本就是 physics 同一 double 的拷贝，任何差异都值得写入。
		if float(x) != float(y):
			return false
	return true


## A0-T1：world/physics 同步状态（只读诊断；不写任何状态）。
## 供探针/运维核对「副本是否与 physics 同一时刻」；不推进时间。
func world_physics_sync_status() -> Dictionary:
	var out := {"enabled": _world_sync_mode == WORLD_SYNC_MODE_TICK,
		"mode": _world_sync_mode, "frame": FRAME_BARY_ROT if _physics_enabled else "",
		"in_sync": false, "compared": 0, "mismatched": [], "last": _world_sync_last,
		"sync_count": _world_sync_total, "reason": ""}
	if _world_sync_mode == WORLD_SYNC_MODE_FRAME_MISMATCH:
		out["reason"] = "frame_mismatch"
		out["frame"] = String(_physics_frame_meta.get("frame_origin", ""))
		return out
	if _world_sync_mode != WORLD_SYNC_MODE_TICK:
		out["reason"] = _world_sync_mode
		out["in_sync"] = true
		return out
	var mismatched: Array = []
	for id in physics_world_service.entity_ids():
		var eid := String(id)
		if not world.has_entity(eid):
			continue
		out["compared"] = int(out["compared"]) + 1
		var st: Dictionary = physics_world_service.state(eid, FRAME_BARY_ROT)
		var cur: Dictionary = world.entity(eid)
		var cur_r: Array = cur.get("pos_km", []) if cur.get("pos_km") is Array else []
		var cur_v: Array = cur.get("vel_kmps", []) if cur.get("vel_kmps") is Array else []
		if not _vec3_equal(cur_r, st.get("r", [])) or not _vec3_equal(cur_v, st.get("v", [])):
			mismatched.append({"id": eid, "world_pos_km": cur_r,
				"physics_pos_km": st.get("r", [])})
	out["mismatched"] = mismatched
	out["in_sync"] = mismatched.is_empty()
	return out


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
	var sc = _seed.get("ship_catalog", null)
	var sc_on := (sc is Dictionary) or (sc is bool and bool(sc))
	if sc_on:
		var sccfg: Dictionary = {} if (sc is bool) else (sc as Dictionary).duplicate(true)
		ship_catalog = ShipCatalogScript.new(sccfg)
		if not bool(ship_catalog.ready):
			errors.append("ship_catalog 未就绪：" + str(ship_catalog.errors))
		else:
			_ship_catalog_enabled = true
	var dp = _seed.get("damage_profiles", null)
	var dp_on := (dp is Dictionary) or (dp is bool and bool(dp)) or _ship_catalog_enabled
	if dp_on:
		var dpcfg: Dictionary = {} if (dp is bool or dp == null) else (dp as Dictionary).duplicate(true)
		if ship_catalog != null and bool(ship_catalog.ready):
			dpcfg["catalog"] = ship_catalog
		damage_profile_service = DamageProfileServiceScript.new(dpcfg)
		if not bool(damage_profile_service.ready):
			warnings.append("damage_profile_service 未就绪：" + str(damage_profile_service.errors))
			damage_profile_service = null
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
		# 5D：带舰级建档（entity→class），旧 damage_l1.ships 显式档案仍优先
		if _ship_catalog_enabled and ship_catalog != null and bool(ship_catalog.ready):
			if dcfg.get("ships") is Array:
				dcfg["ships"] = _damage_ships_with_class(dcfg.get("ships"))
			dcfg["profiles_enabled"] = true
			dcfg["catalog_enabled"] = true
			if damage_profile_service != null and damage_profile_service.ready:
				dcfg["profile_content"] = damage_profile_service.content.duplicate(true)
		damage_service = DamageServiceScript.new(dcfg)
		if not bool(damage_service.ready):
			errors.append("damage_service 未就绪：" + str(damage_service.errors))
		else:
			_damage_enabled = true
			if damage_profile_service == null and damage_service.profile_service != null:
				damage_profile_service = damage_service.profile_service
			elif damage_profile_service != null and damage_profile_service.ready:
				damage_service.profile_service = damage_profile_service
			# 旧 damage_l1 显式档案保持属性优先，但补 class_id 元数据（5D）
			for sid_cls in (damage_service.ship_ids as Array):
				var mdl = (damage_service.ships as Dictionary).get(str(sid_cls), null)
				if mdl == null:
					continue
				if str(mdl.class_id) == "":
					var cid_cls: String = entity_class_id(str(sid_cls))
					if cid_cls != "TBD" and cid_cls != "":
						mdl.class_id = cid_cls
	var rf = _seed.get("refit", null)
	var rf_on := (rf is Dictionary) or (rf is bool and bool(rf))
	if rf_on:
		if ship_catalog == null:
			ship_catalog = ShipCatalogScript.new()
			if bool(ship_catalog.ready):
				_ship_catalog_enabled = true
			else:
				errors.append("refit 需要 ShipCatalog：" + str(ship_catalog.errors))
		if bool(ship_catalog.ready):
			var rcfg: Dictionary = {} if (rf is bool) else (rf as Dictionary).duplicate(true)
			var ropt = rcfg.get("options", rcfg.get("options_path", null))
			var rres: Dictionary = (rcfg.get("resources", {}) as Dictionary).duplicate(true) \
				if rcfg.get("resources") is Dictionary else {}
			if rcfg.has("location") and not rres.has("location"):
				rres["location"] = rcfg.get("location")
			refit_service = RefitServiceScript.new(ship_catalog, ropt, rres)
			if not bool(refit_service.ready):
				errors.append("refit_service 未就绪：" + str(refit_service.errors))
			else:
				_refit_enabled = true
	# 5G：FleetRefit / FleetFormation（依赖 ShipCatalog；缺省互相联动启用）
	var frq = _seed.get("fleet_refit", null)
	var ffq = _seed.get("fleet_formation", null)
	var fleet_any := (frq != null) or (ffq != null)
	var fr_on := (frq is Dictionary) or (frq is bool and bool(frq)) \
		or (fleet_any and not (frq is bool and not bool(frq)))
	var ff_on := (ffq is Dictionary) or (ffq is bool and bool(ffq)) \
		or (fleet_any and not (ffq is bool and not bool(ffq)))
	if fleet_any:
		if ship_catalog == null:
			ship_catalog = ShipCatalogScript.new()
			if bool(ship_catalog.ready):
				_ship_catalog_enabled = true
			else:
				errors.append("fleet 需要 ShipCatalog：" + str(ship_catalog.errors))
		if bool(ship_catalog.ready):
			var frcfg: Dictionary = {} if (frq is bool or frq == null) else (frq as Dictionary).duplicate(true)
			var fr_roster = frcfg.get("roster", frcfg.get("roster_path", null))
			var fr_opt = frcfg.get("options", frcfg.get("options_path", null))
			var fr_res: Dictionary = (frcfg.get("resources", {}) as Dictionary).duplicate(true) \
				if frcfg.get("resources") is Dictionary else {}
			if frcfg.has("location") and not fr_res.has("location"):
				fr_res["location"] = frcfg.get("location")
			if fr_on:
				fleet_refit = FleetRefitServiceScript.new(ship_catalog, fr_roster, fr_opt, fr_res)
				if not bool(fleet_refit.ready):
					errors.append("fleet_refit 未就绪：" + str(fleet_refit.errors))
				else:
					_fleet_refit_enabled = true
			if ff_on:
				var ffc: Dictionary = {} if (ffq is bool or ffq == null) else (ffq as Dictionary).duplicate(true)
				var ff_roster = ffc.get("roster", ffc.get("roster_path", fr_roster))
				var ff_cfg: Dictionary = {}
				if fleet_refit != null and bool(fleet_refit.ready):
					ff_cfg["refit"] = fleet_refit
				fleet_formation = FleetFormationServiceScript.new(ship_catalog, ff_roster, ff_cfg)
				if not bool(fleet_formation.ready):
					errors.append("fleet_formation 未就绪：" + str(fleet_formation.errors))
				else:
					_fleet_formation_enabled = true
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
	var ew = _seed.get("ew_service", null)
	var ew_on := (ew is Dictionary) or (ew is bool and bool(ew))
	if ew_on:
		var ewcfg: Dictionary = {} if (ew is bool) else (ew as Dictionary).duplicate(true)
		ew_service = EWServiceScript.new(ewcfg)
		if not bool(ew_service.ready):
			errors.append("ew_service 未就绪：" + str(ew_service.errors))
		else:
			_ew_enabled = true
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
			# JC-A02：按 scenario 实体的 transponder_profile 装入应答配置（缺失保留明确 unavailable）
			_install_scenario_transponders()
	var idf = _seed.get("identification_service", null)
	var idf_on := (idf is Dictionary) or (idf is bool and bool(idf))
	if idf_on:
		var icfg: Dictionary = {} if (idf is bool) else (idf as Dictionary).duplicate(true)
		identification_service = IdentificationServiceScript.new(icfg)
		if not bool(identification_service.ready):
			errors.append("identification_service 未就绪：" + str(identification_service.errors))
		else:
			_identification_enabled = true
			# JC-A02：owner 身份管道配置（每 owner 复用同一计算器配置）
			_identity_cfg = icfg.duplicate(true)
			_identity_enabled = true
	var legal = _seed.get("legal_status", null)
	var legal_on := (legal is Dictionary) or (legal is bool and bool(legal))
	if legal_on:
		var lcfg: Dictionary = {} if (legal is bool) else (legal as Dictionary).duplicate(true)
		legal_status_service = LegalStatusServiceScript.new(lcfg)
		if not bool(legal_status_service.ready):
			errors.append("legal_status_service 未就绪：" + str(legal_status_service.errors))
		else:
			_legal_enabled = true
	var traffic = _seed.get("traffic_control", null)
	var traffic_on := (traffic is Dictionary) or (traffic is bool and bool(traffic))
	if traffic_on:
		var tcfg: Dictionary = {} if (traffic is bool) else (traffic as Dictionary).duplicate(true)
		traffic_control = TrafficControlServiceScript.new(tcfg)
		if not bool(traffic_control.ready):
			errors.append("traffic_control 未就绪：" + str(traffic_control.errors))
		else:
			_traffic_enabled = true
	var cb = _seed.get("combat_ballistics", null)
	var cb_on := (cb is Dictionary) or (cb is bool and bool(cb))
	if cb_on:
		var bcfg: Dictionary = {} if (cb is bool) else (cb as Dictionary).duplicate(true)
		combat_ballistics = CombatBallisticsScript.new(bcfg)
		if not bool(combat_ballistics.ready):
			errors.append("combat_ballistics 未就绪：" + str(combat_ballistics.errors))
		else:
			_ballistics_enabled = true
	# JC-A01：授权/情报服务（不依赖球体/战斗运行态即可建立边界）
	authority_intel = AuthorityIntelScript.new()
	if not bool(authority_intel.setup(_seed)):
		errors.append("authority_intel 未就绪：" + str(authority_intel.errors))
	else:
		_authority_enabled = true
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

## A0-T2 / A-01：传感器几何绑定统一物理世界。
## 只在 physics 已启用、且 seed 未做 L1→bary_rot 帧转换时绑定（同坐标语义）。
## 降级分两级（A-01）：
##   * **advisory**  — 无 physics 的显式 legacy/static 模式：允许产出观测，但每条观测
##                     必须标 `geometry_advisory=true`，不得冒充 LIVE；
##   * **unavailable** — 期望 physics 但不可用（帧不匹配 / provider 未就绪等）：
##                     本 tick 停止相关路由，**不生成**观测/证据。
func _bind_sensor_geometry(quiet := false) -> Dictionary:
	if sensor_service == null:
		return {"ok": false, "reason": "no_sensor_service", "source": "static"}
	if physics_world_service == null or not _physics_enabled:
		# 显式 legacy：该会话没有 physics 设计 → advisory（允许测试，但必须标注）。
		if sensor_service.has_method("mark_geometry_unavailable"):
			sensor_service.mark_geometry_unavailable("no_physics_world",
				{"severity": "advisory"}, quiet)
		return {"ok": false, "reason": "no_physics_world", "source": "static",
			"mode": "advisory"}
	if not _sensor_geometry_bind_allowed():
		# 4F 帧转换会话：坐标语义不匹配 → 不可用（抑制观测），给出精确 reason。
		var frame := String(_physics_frame_meta.get("frame_origin", "l1"))
		var detail := {"frame": frame, "mismatched_frame": [frame],
			"severity": "unavailable"}
		if sensor_service.has_method("mark_geometry_unavailable"):
			sensor_service.mark_geometry_unavailable("frame_mismatch", detail, quiet)
		warnings.append("sensor geometry 不可用（坐标系不匹配，本 tick 停止传感器路由）")
		return {"ok": false, "reason": "frame_mismatch", "source": "static",
			"mode": "unavailable", "bound": 0}
	var res: Dictionary = sensor_service.bind_geometry_provider(_SensorGeometryProvider.new(self), quiet)
	if not bool(res.get("ok", false)):
		warnings.append("sensor geometry 绑定失败：" + str(res.get("reason", "")))
	return res

## A-01：把 EntityCatalog（静态特征权威）与 PhysicsWorld（运动学权威）以**只读**引用
## 注入 CombatBallistics，使弹道初始状态可追溯（source/frame/t），并让 RCS/IR 优先取
## catalog 而不是静默缺省。本函数不写任何权威状态。
func _wire_ballistics_authority() -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics_service"}
	if entity_catalog == null or not bool(entity_catalog.ready):
		return {"ok": false, "reason": "no_entity_catalog"}
	if physics_world_service == null:
		return {"ok": false, "reason": "no_physics_world"}
	combat_ballistics.catalog = entity_catalog
	combat_ballistics.physics = physics_world_service
	return {"ok": true, "catalog": "entity_catalog", "physics": "physics_world",
		"catalog_entities": int(entity_catalog.count())}


func _sensor_geometry_bind_allowed() -> bool:
	if not _physics_enabled or physics_world_service == null:
		return false
	if sensor_service == null:
		return false
	# 4F 帧转换后的 seed 是 bary_rot，但配置的静态 target 仍是 L1 相对语义；
	# 不同坐标空间不能混用，显式退化为静态几何。
	if bool(_physics_frame_meta.get("applied", false)):
		return false
	return true

## A0-T2：GameSession 侧的几何提供者（只读；不写 world/TrackTable/UI）。
## sensor_service 通过该对象读取「同一仿真时刻」的 physics 位置/速度。
class _SensorGeometryProvider:
	var _session = null

	func _init(sess) -> void:
		_session = sess

	func geometry_ready() -> bool:
		return _session != null and _session.physics_world_service != null \
			and bool(_session.physics_world_service.ready)

	func geometry_frame() -> String:
		return "bary_rot"

	func geometry_t() -> float:
		if _session == null or _session.physics_world_service == null:
			return -1.0
		return float(_session.physics_world_service.t)

	func geometry_state(entity_id: String) -> Dictionary:
		if _session == null or _session.physics_world_service == null:
			return {"ok": false, "reason": "no_physics_world"}
		if not _session.physics_world_service.has_entity(entity_id):
			return {"ok": false, "reason": "unknown_entity", "id": entity_id}
		var st: Dictionary = _session.physics_world_service.state(entity_id, "bary_rot")
		var r = st.get("r", null)
		var v = st.get("v", null)
		if not (r is Array) or (r as Array).size() < 3 \
				or not (v is Array) or (v as Array).size() < 3:
			return {"ok": false, "reason": "non_finite_state", "id": entity_id}
		return {"ok": true, "id": entity_id, "frame": String(st.get("frame", "bary_rot")),
			"t": float(st.get("t", -1.0)),
			"r": (r as Array).duplicate(), "v": (v as Array).duplicate(),
			"units": {"length": "km", "velocity": "km/s", "time": "s"}}

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
## （auto_seed=false 可关闭）。
##
## 帧语义（4F）：
## - Prelude/scenario_prologue 的 pos/vel 是 **L1 相对 km**；PhysicsWorld 是 bary_rot。
##   默认 seed_frame="auto"：检测到 prelude seed（prelude 标记/特定实体 id）时，
##   把 r 平移到 L1 bary 位置（CR3BP μ/D 常数），v 保持；否则按 bary_rot 直灌。
## - seed_frame = auto/l1/bary_rot/none；frame_origin = auto/l1/数组[km]/bary_rot/none；
##   显式 frame_origin 可覆盖 L1 原点或显式关闭转换；非法配置 warning 并回退 bary。
## - 只转换本次 boot 的 seed 实体，不重复转换；显式 physics_world.entities 视为
##   已 bary_rot（除非显式 seed_frame=l1/frame_origin 要求转换）。
func _seed_physics_entities(pwcfg: Dictionary) -> void:
	if physics_world_service == null:
		return
	var source: Array = []
	var source_is_seed := false
	if pwcfg.get("entities") is Array:
		source = (pwcfg.get("entities") as Array)
	elif bool(pwcfg.get("auto_seed", true)):
		source = (_seed.get("entities", []) as Array)
		source_is_seed = true
	var frame := _resolve_seed_frame(pwcfg, source_is_seed)
	var offset: Array = (frame.get("offset_km", [0.0, 0.0, 0.0]) as Array)
	var apply := bool(frame.get("applied", false))
	var converted := 0
	var skipped := 0
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
		if apply and (source_is_seed or bool(frame.get("explicit", false))):
			if _apply_physics_frame_offset(body, offset):
				converted += 1
			else:
				skipped += 1
				warnings.append("physics seed 帧转换跳过 %s：r 非有限三维" % id)
		var res: Dictionary = physics_world_service.upsert_entity(id, body)
		if not bool(res.get("ok", false)):
			warnings.append("physics seed 失败 %s：%s" % [id, str(res.get("reason", ""))])
	_physics_frame_meta = frame.duplicate(true)
	_physics_frame_meta["source_is_seed"] = source_is_seed
	_physics_frame_meta["converted"] = converted
	_physics_frame_meta["skipped"] = skipped
	_physics_frame_meta["conversion_count"] = 1 if converted > 0 else 0
	_physics_frame_meta["entities"] = source.size()

## 解析 seed_frame/frame_origin；返回 {seed_frame,frame_origin,offset_km,applied,
## explicit,auto_prelude,reason}。
func _resolve_seed_frame(pwcfg: Dictionary, source_is_seed: bool) -> Dictionary:
	var raw_seed := str(pwcfg.get("seed_frame",
		_seed.get("seed_frame", "auto"))).strip_edges().to_lower()
	var raw_origin = pwcfg.get("frame_origin", _seed.get("frame_origin", ""))
	var auto_prelude := _is_prelude_seed()
	var explicit_entities := not source_is_seed
	var out := {"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"offset_km": [0.0, 0.0, 0.0], "applied": false, "explicit": false,
		"auto_prelude": auto_prelude, "reason": "default_bary_rot"}
	if raw_seed in ["none", "off", "disabled", "bary_rot", "barycenter"]:
		out["reason"] = "explicit_bary_rot"
		return out
	var origin_l1 := false
	var origin_array: Array = []
	var origin_explicit := false
	if raw_origin is Array and (raw_origin as Array).size() == 3:
		var okv := true
		for x in (raw_origin as Array):
			if not (x is int or x is float) or not is_finite(float(x)):
				okv = false
		if okv:
			origin_array = [(raw_origin as Array)[0], (raw_origin as Array)[1],
				(raw_origin as Array)[2]]
			origin_explicit = true
		else:
			warnings.append("physics frame_origin 数组非法，按 bary_rot 处理")
	elif raw_origin is String:
		var os := (raw_origin as String).strip_edges().to_lower()
		if os in ["l1", "l1_bary", "meridian_l1"]:
			origin_l1 = true
		elif os in ["bary_rot", "barycenter", "none", "off", "disabled"]:
			out["reason"] = "explicit_bary_rot"
			return out
		elif os != "" and os != "auto":
			warnings.append("physics frame_origin 非法：" + os + "，按 bary_rot 处理")
			out["reason"] = "invalid_origin"
			return out
	var want_l1 := false
	var reason := ""
	if raw_seed == "l1":
		want_l1 = true
		reason = "seed_frame_l1"
	elif raw_seed == "auto":
		if origin_explicit or origin_l1:
			want_l1 = true
			reason = "frame_origin"
		elif auto_prelude:
			want_l1 = true
			reason = "auto_prelude"
		else:
			out["reason"] = "auto_bary_rot"
			return out
	else:
		warnings.append("physics seed_frame 非法：" + raw_seed + "，按 bary_rot 处理")
		out["reason"] = "invalid_seed_frame"
		return out
	var off: Array = [0.0, 0.0, 0.0]
	if origin_array.size() == 3:
		off = origin_array.duplicate()
	elif origin_l1 or raw_seed == "l1" or (raw_seed == "auto" and auto_prelude):
		off = _l1_bary_position()
		if off.size() != 3:
			warnings.append("physics L1 bary 位置不可用，按 bary_rot 处理")
			out["reason"] = "l1_unavailable"
			return out
	if explicit_entities and not origin_explicit and not origin_l1 \
			and not (raw_seed == "l1"):
		# 显式 physics entities 默认视为 bary_rot；仅当显式请求 l1 才转换
		out["reason"] = "explicit_entities_bary_rot"
		return out
	out["seed_frame"] = "l1"
	out["frame_origin"] = "explicit" if origin_explicit else "l1"
	out["offset_km"] = [float(off[0]), float(off[1]), float(off[2])]
	out["applied"] = true
	out["explicit"] = origin_explicit or origin_l1 or raw_seed == "l1"
	out["reason"] = reason
	return out

func _is_prelude_seed() -> bool:
	if _seed.get("prelude") is Dictionary and not (_seed.get("prelude") as Dictionary).is_empty():
		return true
	var origin := str(_seed.get("scenario_origin", "")).to_lower()
	if origin == "l1" or origin == "l1_local":
		return true
	for raw in (_seed.get("entities", []) as Array):
		if raw is Dictionary:
			var id := String((raw as Dictionary).get("id", ""))
			if id in ["ceres_2", "av_4412", "ferry", "watchtower", "deepwell",
					"chronos"]:
				return true
	return false

func _l1_bary_position() -> Array:
	var eq: Dictionary = PhysicsScript.equilibrium_points()
	if eq.has("L1") and (eq["L1"] as Dictionary).get("pos_rot", null) is Vector3:
		var p: Vector3 = (eq["L1"] as Dictionary)["pos_rot"]
		return [p.x, p.y, p.z]
	return []

func _apply_physics_frame_offset(body: Dictionary, offset: Array) -> bool:
	if offset.size() != 3:
		return false
	var r = body.get("r", null)
	if not (r is Array) or (r as Array).size() != 3:
		return false
	for x in (r as Array):
		if not (x is int or x is float) or not is_finite(float(x)):
			return false
	var new_r := [float((r as Array)[0]) + float(offset[0]),
		float((r as Array)[1]) + float(offset[1]),
		float((r as Array)[2]) + float(offset[2])]
	body["r"] = new_r
	if body.has("pos_km"):
		body["pos_km"] = new_r.duplicate()
	body["frame"] = "bary_rot"
	body["seed_frame_input"] = "l1"
	body["seed_frame_converted"] = true
	return true

## 4F 帧转换只读元数据（转换/未转换/偏移/原因）。
func physics_frame_meta() -> Dictionary:
	return _physics_frame_meta.duplicate(true)


## A-04：旧档迁移报告（只读）。诚实列出采用的迁移版本、可恢复范围与**无法恢复**项，
## 便于审查「重放集合合并」而非「尾部替换」，以及部分恢复的显式标注。
## A-05：传感器运行态恢复报告（重绑定/几何来源/frame/同刻复核）。
func sensor_restore_report() -> Dictionary:
	return _sensor_restore_report.duplicate(true)


func legacy_migration_report() -> Dictionary:
	if _legacy_migration.is_empty():
		return {"schema": "v17.legacy_migration.v1", "applied": false}
	return _legacy_migration.duplicate(true)


## A-02：时间与坐标语义的**单一元数据来源**（只读）。
## 明确区分日历历元（scenario UTC，仅一个来源）与动力学相位基准（CR3BP epoch_s），
## 并给出各消费者的 frame / source / 采样阶段，供整合验收逐项核对。
func session_time_frame_meta() -> Dictionary:
	var epoch: Dictionary = time.epoch_meta() if time != null else {}
	var frame_meta := physics_frame_meta()
	var snapshot_frame := FRAME_BARY_ROT
	if booted:
		var snap: Dictionary = snapshot()
		var pf: Dictionary = snap.get("physics_frame", {}) \
			if snap.get("physics_frame") is Dictionary else {}
		snapshot_frame = String(pf.get("frame", FRAME_BARY_ROT))
	var sens: Dictionary = sensor_geometry_status() if sensor_service != null else {}
	return {
		"schema": "v17.session_time_frame.v1",
		"t_s": now_s(),
		"epoch": epoch,
		"calendar_epoch_source": String(epoch.get("epoch_source", "")),
		"phase_basis": String(epoch.get("phase_basis", "")),
		"physics_time_ok": absf(float(physics_world_service.t) - now_s()) <= 1.0e-6 \
			if physics_world_service != null else false,
		"physics_t": float(physics_world_service.t) if physics_world_service != null else -1.0,
		"runtime_frame": FRAME_BARY_ROT,
		"runtime_units": {"length": "km", "velocity": "km/s", "time": "s"},
		"seed_frame": String(_seed.get("seed_frame", "")),
		"frame_conversion": {
			"applied": bool(frame_meta.get("applied", false)),
			"source": "seed" if bool(frame_meta.get("source_is_seed", false)) else "explicit",
			"conversion_count": int(frame_meta.get("conversion_count", 0)),
			"converted": int(frame_meta.get("converted", 0)),
			"skipped": int(frame_meta.get("skipped", 0)),
			"origin": String(frame_meta.get("frame_origin", "")),
			"reason": String(frame_meta.get("reason", "")),
		},
		"consumers": {
			"physics": {"frame": FRAME_BARY_ROT,
				"t_s": float(physics_world_service.t) if physics_world_service != null else -1.0,
				"source": "physics_world"},
			"world_projection": {"frame": FRAME_BARY_ROT, "source": "physics_world(copy)"},
			"snapshot": {"frame": snapshot_frame, "source": "session.snapshot"},
			"sensor_geometry": {"frame": String(sens.get("frame", "")),
				"source": String(sens.get("source", ""))},
			"ballistics": {"frame": FRAME_BARY_ROT, "source": "physics_world"},
		},
		"writes": {"world": false, "track_table": false, "v15": false},
	}

func physics_l1_position() -> Array:
	return _l1_bary_position()

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
	# tick 顺序：time → physics（位置权威）→ world 副本同步 → sensor/track/orders
	# （见文档）。A0-T1：physics 推进后立刻把只读副本同步进 WorldState，保证同一
	# tick 内后续消费者与对外 snapshot 看到同一仿真时刻的位置/速度。
	var physics_tick: Dictionary = _advance_physics(sim_dt)
	var world_sync: Dictionary = world_physics_sync("tick")
	var ot: Dictionary = orders.tick(sim_dt)
	if not bool(ot.get("ok", false)):
		warnings.append("orders tick 失败：" + str(ot.get("reason", "")))
	_flush_order_events()
	_advance_components(sim_dt)
	# JC-A01/R3 剩余：每 owner 航迹老化/忘却（与 TrackTable 同一合同，只作用于该 owner）
	if _authority_enabled and authority_intel != null:
		authority_intel.advance(now_s())
	var ballistics_step: Dictionary = _advance_ballistics(sim_dt)
	var sensor_route: Dictionary = _advance_sensors(sim_dt)
	# JC-A03：投递已到达的延迟观测（采样在 sensors；EW 之后同一 tick 不重复采样）
	_ew_deliver_due_count = _deliver_due_ew_observations()
	var signal_step: Dictionary = _advance_signal(sim_dt)
	var ew_step: Dictionary = _advance_ew(sim_dt)
	var port_combat: Dictionary = _advance_port_combat(sim_dt)
	_flush_component_events()
	var signal_route: Dictionary = _last_signal_route.duplicate(true)
	var damage_tick: Dictionary = _advance_damage(sim_dt)
	var transponder_tick: Dictionary = _advance_transponder(sim_dt)
	var identification_tick: Dictionary = _advance_identification(sim_dt)
	var legal_tick: Dictionary = _advance_legal_status(sim_dt)
	var traffic_step: Dictionary = _advance_traffic(sim_dt)
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
			"ew": ew_service != null,
			"facility": facility_registry != null,
			"transponder": transponder_service != null,
			"identification": identification_service != null,
			"legal_status": legal_status_service != null,
			"traffic": traffic_control != null,
			"combat_ballistics": combat_ballistics != null,
			"ship_catalog": ship_catalog != null,
			"refit": refit_service != null,
			"fleet_refit": fleet_refit != null,
			"fleet_formation": fleet_formation != null,
			"damage_profile": damage_profile_service != null,
		},
		"sensor_route": sensor_route,
		"port_combat": port_combat,
		"damage_tick": damage_tick,
		"physics_tick": physics_tick,
		"world_sync": world_sync,
		"signal_step": signal_step,
		"ew_step": ew_step,
		"signal_route": signal_route,
		"transponder_tick": transponder_tick,
		"identification_tick": identification_tick,
		"legal_status_tick": legal_tick,
		"traffic_step": traffic_step,
		"ballistics_step": ballistics_step,
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
			# JC-A02/A03：观测按观察者域投递；EW 质量/延迟在采样点决定，
			# 延迟期间不入 owner 情报/TrackTable（由投递器统一处理）。
			var obs_owner := ""
			if _authority_enabled and authority_intel != null:
				obs_owner = authority_intel.owner_of_entity(
					String(obs_ev.get("observer_id", "")))
			var staged: Dictionary = _ew_stage_observation(obs_owner, obs_ev)
			out["observations"] = int(out["observations"]) + 1
			if bool(staged.get("queued", false)):
				out["ew_delayed"] = int(out.get("ew_delayed", 0)) + 1
		elif schema == "track_evidence.v1" and kind == "evidence":
			var ev2: Dictionary = ev.duplicate(true)
			_enrich_track_id(ev2)
			var r2: Dictionary = track_table.handle_evidence(ev2, _track_writer)
			if bool(r2.get("ok", false)):
				out["evidence"] = int(out["evidence"]) + 1
				_bridge_identity_evidence(ev2)
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

## tick 驱动 EWService：效果过期/衰减 + 事件发布到 bus；不写 world/TrackTable/UI。
func _advance_ew(sim_dt: float) -> Dictionary:
	if ew_service == null:
		return {"enabled": false}
	var r: Dictionary = ew_service.step(sim_dt)
	var n := 0
	for raw in ew_service.take_events():
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var payload: Dictionary = ev.get("payload", {}) if ev.get("payload") is Dictionary else {}
		_publish({"type": "ew." + String(ev.get("kind", "event")), "t": now_s(),
			"source": "ew_service", "target": String(ev.get("target_id", "")),
			"payload": payload.duplicate(true), "text_key": ""})
		n += 1
	return {"enabled": true, "ok": bool(r.get("ok", true)), "events": n,
		"active": int((r.get("counts", {}) as Dictionary).get("active", 0)),
		"emcon": bool(ew_service.emcon_active), "t": float(ew_service.t)}
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
				_bridge_identity_evidence(e)
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
	if identification_service != null:
		var ires: Dictionary = _flush_identification_outputs()
		n += int(ires.get("events", 0))
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
	# ballistics/world 目标 id 直接是 damage ship 时优先（4H）
	if target_id != "" and (damage_service.ships as Dictionary).has(target_id):
		return target_id
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
func _flush_transponder_outputs(extra_events := [], extra_evidence := [], owner_id := "") -> Dictionary:
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
			if owner_id != "":
				e["owner_id"] = owner_id
			var r: Dictionary = track_table.handle_evidence(e, _track_writer)
			if bool(r.get("ok", false)):
				out["evidence"] = int(out["evidence"]) + 1
			else:
				out["failed"] = int(out["failed"]) + 1
				out["reasons"].append("evidence:" + str(r.get("reason", "")))
			# 身份证据独立于 TrackTable 原始融合是否接受（一次事件仍只消费一次）
			_bridge_identity_evidence(e, owner_id)
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

## tick 推进识别：auto 开启时产生 query_request 并由 transponder 执行；否则仅 step。
func _advance_identification(sim_dt: float) -> Dictionary:
	if identification_service == null:
		return {"enabled": false}
	# 时钟对齐：证据 t 来自 now_s()（应答机/传感器同一时基），识别服务若只按 dt 累加
	# 会落后于任务时钟，导致证据 age 被 clamp 成 0、时间衰减失效。
	# step 内部会把 t 再加 sim_dt，所以先对齐到 (now - sim_dt)，step 后正好等于 now_s()。
	identification_service.set_time(now_s() - maxf(0.0, float(sim_dt)))
	var auto_enabled := bool(identification_service.cfg_auto.get("enabled", false))
	var res: Dictionary = {}
	if auto_enabled:
		res = identification_service.auto_query_tick(sim_dt)
	else:
		res = identification_service.step(sim_dt)
	var executed: Array = []
	var requests: Array = res.get("requests", []) if res.get("requests") is Array else []
	if auto_enabled and transponder_service != null:
		for raw in requests:
			if raw is Dictionary:
				var ex: Dictionary = _execute_identification_query(raw as Dictionary)
				if bool(ex.get("ok", false)):
					executed.append(ex)
	_flush_identification_outputs()
	_flush_identification_outputs()
	# JC-A02：其余 owner 计算器推进；所有 owner 的 assessment 只在此路由一次
	_identity_advance_owners(sim_dt)
	return {"enabled": true, "t": float(identification_service.t),
		"auto": auto_enabled, "requests": requests.size(),
		"executed": executed.size(), "targets": identification_service.assessments.size()}

## tick 推进 ID13 法律状态：时间/可选 decay；仅输出状态/影响，不写 world。
func _advance_legal_status(sim_dt: float) -> Dictionary:
	if legal_status_service == null:
		return {"enabled": false}
	var res: Dictionary = legal_status_service.tick(sim_dt)
	if not bool(res.get("ok", false)):
		warnings.append("legal_status tick 失败：" + str(res.get("reason", "")))
		return {"enabled": true, "ok": false, "reason": str(res.get("reason", ""))}
	return {"enabled": true, "ok": true, "status": str(res.get("status", "")),
		"heat": float(res.get("heat", 0.0)), "changed": bool(res.get("changed", false)),
		"t": float(legal_status_service.t)}

## tick 推进 OTC/交通管制：step 驱动 NPC/窗口/队列；白名单事件发布 bus；
## 不写 world/TrackTable/UI。
func _advance_traffic(sim_dt: float) -> Dictionary:
	if traffic_control == null:
		return {"enabled": false}
	var step: Dictionary = traffic_control.step(sim_dt)
	if not bool(step.get("ok", true)):
		warnings.append("traffic_control step 失败：" + str(step.get("reason", "")))
		return {"enabled": true, "ok": false, "reason": str(step.get("reason", ""))}
	var routed := 0
	for raw in traffic_control.take_events():
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := str(ev.get("kind", ""))
		if not (kind in ["lane_record", "otc_event", "clue"]):
			continue
		var payload := (ev.get("payload", {}) as Dictionary).duplicate(true) \
			if ev.get("payload") is Dictionary else {}
		var out := _mk_event("traffic." + kind, str(payload.get("lane_id",
			payload.get("track_id", ""))), {
				"schema": str(ev.get("schema", "traffic_event.v1")),
				"kind": kind, "seq": int(ev.get("seq", 0)), "t": float(ev.get("t", 0.0)),
				"shadow": bool(ev.get("shadow", true)),
				"writes_v15": false, "payload": payload})
		var pub: Dictionary = bus.publish(out)
		if bool(pub.get("ok", false)):
			routed += 1
			_tick_events.append(pub.get("event", {}))
		else:
			warnings.append("traffic 事件发布失败：" + kind)
	return {"enabled": true, "ok": true, "t": float(traffic_control.t),
		"events": (traffic_control.events as Array).size(),
		"routed": routed, "counts": traffic_control._counts()}

## 从 session 实体（physics 优先，否则 world）构造 Ballistics states；
## 只读，不写世界；has_pd 来自实体 has_pd/配置 pd_platform_id。
## 实体运动学取态：物理世界优先，物理世界没有该实体时回退剧情世界。
## 注意 position_of() 在 physics_world_service 非空时会短路，空物理世界会遮蔽剧情世界，
## 因此弹道取态必须走这里，不能直接用 position_of()。
func _entity_kinematics(entity_id: String) -> Dictionary:
	if entity_id == "":
		return {"ok": false, "reason": "empty_id"}
	if physics_world_service != null and physics_world_service.has_entity(entity_id):
		# 注意：physics_world.state() 不返回 "ok" 字段，判成功要看 r/v 是否可用
		var st = physics_world_service.state(entity_id, "bary_rot")
		if st is Dictionary:
			var sr: Array = (st as Dictionary).get("r", []) if (st as Dictionary).get("r") is Array else []
			if sr.size() >= 3:
				# 归一化成调用方约定的形状（补 ok，保留原始字段）
				var norm: Dictionary = (st as Dictionary).duplicate(true)
				norm["ok"] = true
				norm["source"] = "physics_world"
				norm["frame"] = "bary_rot"
				return norm
	if world != null and world.has_entity(entity_id):
		var e: Dictionary = world.entity(entity_id)
		var r: Array = e.get("pos_km", []) if e.get("pos_km") is Array else []
		var v: Array = e.get("vel_kmps", []) if e.get("vel_kmps") is Array else []
		if r.size() >= 3:
			return {"ok": true, "source": "world", "frame": "bary_rot",
				"r": r.duplicate(), "v": v.duplicate()}
	return {"ok": false, "reason": "unknown_entity"}


func _ballistics_states() -> Dictionary:
	var ids: Dictionary = {}
	if physics_world_service != null:
		for id in physics_world_service.entity_ids():
			ids[String(id)] = true
	if world != null:
		for raw in world.entities_sorted():
			if raw is Dictionary:
				ids[String((raw as Dictionary).get("id", ""))] = true
	var pd_platform := ""
	if combat_ballistics != null and combat_ballistics.config is Dictionary:
		pd_platform = str(combat_ballistics.config.get("pd_platform_id", "own"))
	# 哨兵值 "own" = 玩家本舰，需解析成真实实体 id（config 里写死 id 亦可）
	if pd_platform == "own":
		pd_platform = String(_seed.get("own_entity", ""))
		if pd_platform == "" and combat_service != null:
			pd_platform = String(combat_service.own_id)
	if pd_platform == "own":
		pd_platform = ""
	var out: Dictionary = {}
	for id in ids.keys():
		var pos: Dictionary = _entity_kinematics(str(id))
		if not bool(pos.get("ok", false)):
			continue
		var r = pos.get("r", pos.get("pos_km", []))
		var v = pos.get("v", pos.get("vel_kmps", []))
		if not (r is Array) or (r as Array).size() < 3:
			continue
		var meta: Dictionary = entity_metadata(str(id))
		var metadata_found := bool(meta.get("found", false))
		var side := str(meta.get("side", ""))
		var has_pd := bool(meta.get("has_pd", false))
		if pd_platform != "" and str(id) == pd_platform:
			has_pd = true
		# 引导头/PD 需要的目标特征来自静态元数据权威（A1.1）；缺失时显式兜底并标记
		# radius_source=default，避免把兜底尺寸误当真实尺寸。
		var rcs := float(meta.get("rcs_m2", 0.0))
		var ir := float(meta.get("ir_signature", 0.0))
		var kind := str(meta.get("kind", ""))
		if kind == "" and world != null and world.has_entity(str(id)):
			var went: Dictionary = world.entity(str(id))
			kind = str(went.get("kind", went.get("ship_class", "")))
		var radius_km := float(meta.get("radius_km", 0.0))
		var radius_source := "catalog"
		if not metadata_found or radius_km <= 0.0:
			radius_source = "default"
			radius_km = _default_radius_km(kind)
		out[str(id)] = {"id": str(id), "pos_km": (r as Array).duplicate(),
			"vel_kmps": (v as Array).duplicate() if v is Array else [0.0, 0.0, 0.0],
			"radius_km": radius_km, "radius_source": radius_source,
			"metadata_found": metadata_found,
			"has_pd": has_pd, "side": side,
			"kind": kind,
			"rcs_m2": rcs, "ir_signature": ir}
	return out


## 场景漏填 radius_km 时按实体类型兜底；避免命中判定退化成战斗部半径（R6/P1）。
func _default_radius_km(kind: String) -> float:
	match kind.to_lower():
		"station", "facility", "port", "depot":
			return 0.30
		"fuel", "tank":
			return 0.20
		"otc", "relay":
			return 0.04
		"ship", "warship", "corvette", "frigate", "destroyer", "cruiser":
			return 0.06
		_:
			return 0.05

## tick 推进弹道：step 用 session 状态；outbox 事件 → bus（ballistics.<kind>）；
## impact.damage_event 白名单 → DamageService（shot_id 去重）。不写 world/TrackTable/UI。
func _advance_ballistics(sim_dt: float) -> Dictionary:
	if combat_ballistics == null:
		return {"enabled": false}
	var states: Dictionary = _ballistics_states()
	# PD 平台兜底：配置的 pd_platform_id 不在实体表里时，落到本舰实体
	if not states.has(String(combat_ballistics._pd_platform_id)):
		var own := _own_ballistics_entity(states)
		if own != "":
			combat_ballistics._pd_platform_id = own
	var step: Dictionary = combat_ballistics.step(sim_dt, states)
	if not bool(step.get("ok", false)):
		warnings.append("combat_ballistics step 失败：" + str(step.get("reason", "")))
		return {"enabled": true, "ok": false, "reason": str(step.get("reason", ""))}
	var routed := 0
	var applied := 0
	var duplicates := 0
	var damage_failed := 0
	for raw in combat_ballistics.take_events():
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := str(ev.get("kind", ""))
		var payload := (ev.get("payload", {}) as Dictionary).duplicate(true) \
			if ev.get("payload") is Dictionary else {}
		if kind == "impact" and payload.get("damage_event") is Dictionary:
			var dmg: Dictionary = (payload.get("damage_event") as Dictionary).duplicate(true)
			if damage_service != null:
				var route: Dictionary = _route_combat_damage(dmg)
				if bool(route.get("applied", false)):
					dmg["applied"] = true
					if bool(route.get("duplicate", false)):
						duplicates += 1
					else:
						applied += 1
						# 航迹级战果汇总（实体级账本仍是 DamageModel）
						if combat_service != null:
							combat_service.note_damage(
								_track_for_entity(str(dmg.get("target_id", ""))),
								float(dmg.get("damage", 0.0)))
				else:
					dmg["applied"] = false
					damage_failed += 1
			else:
				dmg["applied"] = false
				damage_failed += 1
			payload["damage_event"] = dmg
		var out := _mk_event("ballistics." + kind,
			str(payload.get("target_id", payload.get("shooter_id", ""))), {
				"schema": str(ev.get("schema", "ballistics_event.v1")),
				"kind": kind, "seq": int(ev.get("seq", 0)), "t": float(ev.get("t", 0.0)),
				"shadow": bool(ev.get("shadow", true)), "writes_v15": false,
				"payload": payload})
		var pub: Dictionary = bus.publish(out)
		if bool(pub.get("ok", false)):
			routed += 1
			_tick_events.append(pub.get("event", {}))
		else:
			warnings.append("ballistics 事件发布失败：" + kind)
	return {"enabled": true, "ok": true, "t": float(combat_ballistics.t),
		"active": (combat_ballistics.active_projectiles() as Array).size(),
		"intercepts": (combat_ballistics.intercept_records() as Array).size(),
		"impacts": (combat_ballistics.impact_records() as Array).size(),
		"substeps": int(step.get("substeps", 0)),
		"time_cap": _apply_combat_time_cap(),
		"routes": routed, "damage_applied": applied, "damage_duplicates": duplicates,
		"damage_failed": damage_failed}


## 实体 id → 航迹 id（note_damage 用；找不到就返回原 id，让 note_damage 自己判 unknown）。
func _track_for_entity(entity_id: String) -> String:
	if combat_service == null or entity_id == "":
		return entity_id
	if not combat_service.track(entity_id).is_empty():
		return entity_id
	for row in combat_service.track_rows():
		if String((row as Dictionary).get("entity_id", "")) == entity_id:
			return String((row as Dictionary).get("id", entity_id))
	return entity_id

## 自动询问执行：transponder 询问 → 把 reply 作为证据回灌识别；不写 world。
func _execute_identification_query(req: Dictionary) -> Dictionary:
	var target := String(req.get("target_id", ""))
	if target == "" or transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service"}
	var prof_id := _transponder_profile_id_for(target)
	if prof_id == "":
		return {"ok": false, "reason": "no_transponder_profile", "target_id": target}
	# JC-A02：真实查询统一走 owner 管道（一次证据、owner 保留、状态分离）
	if _identity_enabled:
		var owner := _identity_own_owner()
		if owner == "":
			return {"ok": false, "reason": "unknown_owner"}
		var opts := {"range_km": float(req.get("range_km", 0.0)),
			"occluded": bool(req.get("occluded", false)),
			"jam": float(req.get("jam", 0.0)),
			"mode": String(req.get("mode", "")),
			"latency_s": 0.0}
		var qres: Dictionary = _identity_execute_iff(owner, target, prof_id, opts)
		return {"ok": bool(qres.get("ok", false)), "target_id": target,
			"profile_id": prof_id,
			"reply_status": String(qres.get("reply_status", "")),
			"iff_state": String(qres.get("state", ""))}
	var state: Dictionary = req.get("state", {}) if req.get("state") is Dictionary else {}
	var opts2 := {"range_km": float(state.get("range_km", 0.0)),
		"occluded": false, "jam": 0.0, "latency_s": 0.0}
	var r: Dictionary = transponder_service.interrogate(String(req.get("source_id", "identification")),
		prof_id, String(req.get("mode", "")), opts2)
	_flush_transponder_outputs(r.get("events", []), r.get("evidence", []))
	var reply = r.get("reply", null)
	var ingest_ev: Dictionary = {"target_id": target, "source": "transponder",
		"t": now_s(), "mode": String(req.get("mode", "")),
		"range_km": float(state.get("range_km", 0.0)),
		"los": bool(state.get("los", true)), "emcon": bool(state.get("emcon", false))}
	if reply is Dictionary and bool((reply as Dictionary).get("ok", false)):
		var rp: Dictionary = reply
		ingest_ev["identity"] = String(rp.get("identity", "unknown"))
		ingest_ev["confidence"] = clampf(float(rp.get("confidence", 0.5)), 0.0, 1.0)
		ingest_ev["status"] = String(rp.get("status", ""))
		ingest_ev["spoofed"] = bool(rp.get("spoofed", false))
		ingest_ev["evidence_type"] = "transponder"
	else:
		ingest_ev["identity"] = "unknown"
		ingest_ev["confidence"] = 0.2
		ingest_ev["status"] = String(r.get("reason", "no_reply"))
	var ir: Dictionary = identification_service.ingest(ingest_ev)
	return {"ok": bool(ir.get("ok", false)), "target_id": target,
		"profile_id": prof_id, "reply_status": String((reply as Dictionary).get("status", "")) if reply is Dictionary else "no_reply"}

func _transponder_profile_id_for(target: String) -> String:
	if transponder_service == null:
		return ""
	if not transponder_service.profile(target).is_empty():
		return target
	for pid in transponder_service.profile_ids():
		var p: Dictionary = transponder_service.profile(String(pid))
		if String(p.get("entity_id", "")) == target or String(p.get("facility_id", "")) == target:
			return String(pid)
	return ""

## 识别事件 → EventBus（identification.<kind>）；不写 TrackTable/world。
func _flush_identification_outputs() -> Dictionary:
	if identification_service == null:
		return {"enabled": false, "events": 0}
	var out := {"enabled": true, "events": 0}
	for raw in identification_service.take_events():
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var payload: Dictionary = ev.get("payload", {}) if ev.get("payload") is Dictionary else {}
		var assessment: Dictionary = payload.get("assessment", {}) if payload.get("assessment") is Dictionary else {}
		_publish({"type": "identification." + str(ev.get("kind", "event")),
			"t": now_s(), "source": "identification_service",
			"target": str(assessment.get("target_id", payload.get("target_id", ""))),
			"payload": {"event_id": str(ev.get("event_id", "")),
				"kind": str(ev.get("kind", "")),
				"data": payload.duplicate(true)},
			"text_key": ""})
		out["events"] = int(out["events"]) + 1
	return out

# A-06：通信操作 outcome 记录版本（读档重放时逐项核对）
# JC-A04：v2 增加发送时刻 EW 采样；v1 作为合法旧档迁移（EW 接线前语义）。
const COMMS_OUTCOME_SCHEMA := "v17.comms_outcome.v2"
const COMMS_OUTCOME_SCHEMA_V1 := "v17.comms_outcome.v1"
const COMMS_OUTCOME_VERSION := 2
const COMMS_OUTCOME_VERSION_LEGACY := 1

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
		# JC-A02：真实身份证据先入身份管道；TrackTable 拒绝不应吞掉证据（去重防重复消费）
		_bridge_identity_evidence(evd2)
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
		_bridge_identity_evidence(evn)
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

## A0-T2（Issue #4.1）：传感器几何来源/采样时刻只读诊断。
## source=physics_world 表示几何来自统一物理世界；static 表示退化（含原因）。
func sensor_geometry_status() -> Dictionary:
	if sensor_service == null:
		return {"schema": "sensor_geometry_status.v1", "source": "none",
			"authoritative": false, "reason": "no_sensor_service", "targets": 0}
	if sensor_service.has_method("geometry_status"):
		return sensor_service.geometry_status()
	return {"schema": "sensor_geometry_status.v1", "source": "static",
		"authoritative": false, "reason": "no_geometry_api", "targets": 0}

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
			_bridge_identity_evidence(iff_ev)
	res["routed"] = routed
	_record({"op": "query_iff", "target_id": String(res.get("target_id", target_id))})
	return res

## ── JC-A03：EW 观测采样 / 延迟队列 / 当前测量质量 ────────────────
## 唯一采样点：_advance_sensors 生成观测时查询 ew_service（EW 尚未 step），
## 质量与延迟在此计算；延迟投递后才进入 owner 情报/TrackTable/火控。
var _ew_samples: Array = []
var _ew_obs_queue: Array = []
var _ew_delivered: Array = []
var _ew_candidates: Array = []
var _ew_obs_seq := 0
var _ew_restore_mode := "absent"
var _ew_restore_missing: Array = []
var _ew_rejected_deliveries: Array = []
var _ew_quality_history: Dictionary = {}   # "<owner>|<target>" -> max quality
var _ew_combat_quality: Dictionary = {}    # target -> {quality, t, source}
var _ew_deliver_due_count := 0


func _ew_sensor_kind(sensor: String) -> String:
	var s := sensor.to_lower()
	if s in ["radar", "rwr", "esm"]:
		return "radar"
	if s in ["optical", "ir", "vis", "visual", "laser"]:
		return "optical"
	return s if s != "" else "radar"


## 同 tick 采样：只查询 effect，不推进 EW；返回可持久化快照。
func _ew_sample_for(target_id: String, sensor_kind: String) -> Dictionary:
	if ew_service == null:
		return {}
	var eff: Dictionary = ew_service.observation_effect(target_id, sensor_kind)
	var out := {"schema": "ew_observation_sample.v1", "target_id": target_id,
		"sensor_kind": sensor_kind, "sampled_t": now_s(),
		"confidence_mult": float(eff.get("confidence_mult", 1.0)),
		"delay_s": float(eff.get("delay_s", 0.0)),
		"jammed": bool(eff.get("jammed", false)),
		"noise_severity": float(eff.get("noise_severity", 0.0)),
		"deception_severity": float(eff.get("deception_severity", 0.0)),
		"chaff_severity": float(eff.get("chaff_severity", 0.0)),
		"false_observations": (eff.get("false_observations", []) as Array).duplicate(true) \
			if eff.get("false_observations") is Array else [],
		"effect": eff.duplicate(true)}
	return out


func _ew_quality_aggregate(owner_id: String, target_id: String, quality: float) -> float:
	var key := owner_id + "|" + target_id
	var prev := float(_ew_quality_history.get(key, 0.0))
	var agg := maxf(prev, float(quality))
	_ew_quality_history[key] = agg
	return agg


## 生成观测时调用：有延迟则入队（到达前不可见），否则立即投递。
func _ew_stage_observation(owner_id: String, obs_ev: Dictionary) -> Dictionary:
	var target := String(obs_ev.get("target_id", ""))
	var sensor := String(obs_ev.get("sensor", "radar"))
	var kind := _ew_sensor_kind(sensor)
	var snap := _ew_sample_for(target, kind)
	if snap.is_empty():
		snap = {"schema": "ew_observation_sample.v1", "target_id": target,
			"sensor_kind": kind, "sampled_t": now_s(),
			"confidence_mult": 1.0, "delay_s": 0.0, "jammed": false,
			"noise_severity": 0.0, "deception_severity": 0.0,
			"chaff_severity": 0.0, "false_observations": [], "effect": {}}
	var q0 := float(obs_ev.get("quality", 0.0))
	var q1 := clampf(q0 * float(snap.get("confidence_mult", 1.0)), 0.0, 1.0)
	var sample := snap.duplicate(true)
	sample["quality_before"] = q0
	sample["quality_after"] = q1
	sample["observed_t"] = float(obs_ev.get("t", now_s()))
	(_ew_samples as Array).append(sample)
	while (_ew_samples as Array).size() > 400:
		(_ew_samples as Array).pop_front()
	obs_ev["quality_original"] = q0
	obs_ev["quality"] = q1
	obs_ev["ew_effect"] = snap.get("effect", {}) if snap.get("effect") is Dictionary else {}
	(_ew_obs_seq) += 1
	var oid := String(obs_ev.get("event_id", ""))
	if oid == "":
		oid = "EWOBS-%06d" % _ew_obs_seq
		obs_ev["event_id"] = oid
	var delay := float(snap.get("delay_s", 0.0))
	var entry := {"schema": "ew_pending_observation.v1", "seq": _ew_obs_seq,
		"observation_id": oid, "owner_id": owner_id,
		"target_id": target, "sensor": sensor, "sensor_kind": kind,
		"observed_t": float(obs_ev.get("t", now_s())),
		"delay_s": delay, "arrive_t": float(obs_ev.get("t", now_s())) + delay,
		"obs": obs_ev.duplicate(true),
		"effect": snap.get("effect", {}) if snap.get("effect") is Dictionary else {},
		"confidence_mult": float(snap.get("confidence_mult", 1.0)),
		"quality_original": q0, "quality": q1,
		"false_observations": (snap.get("false_observations", []) as Array).duplicate(true) \
			if snap.get("false_observations") is Array else [],
		"truth_regenerated": false}
	if delay > 1.0e-9:
		(_ew_obs_queue as Array).append(entry)
		return {"queued": true, "arrive_t": entry["arrive_t"], "sample": sample}
	_deliver_ew_observation(entry)
	return {"queued": false, "arrive_t": entry["observed_t"], "sample": sample}


## 投递：owner 情报 + TrackTable + 当前测量质量 + 欺骗候选；不使用后来真值。
func _deliver_ew_observation(entry: Dictionary) -> void:
	var owner_id := String(entry.get("owner_id", ""))
	var target := String(entry.get("target_id", ""))
	var obs: Dictionary = (entry.get("obs", {}) as Dictionary).duplicate(true)
	var observed_t := float(entry.get("observed_t", now_s()))
	var received_t := now_s()
	var delay := maxf(0.0, received_t - observed_t)
	var q := float(entry.get("quality", 0.0))
	# R2：接纳/幂等必须覆盖整个新增消费者边界；底层已去重时不写任何副作用
	var accepted := true
	var reject_reason := ""
	if _authority_enabled and authority_intel != null and owner_id != "":
		var ar: Dictionary = authority_intel.receive_observation(owner_id, {
			"observation_id": String(entry.get("observation_id", "")),
			"observer_id": String(obs.get("observer_id", "")),
			"target_id": target,
			"sensor": String(obs.get("sensor", "")),
			"source": String(obs.get("sensor", "")),
			"observed_t": observed_t, "received_t": received_t,
			"delay_s": delay, "path": "ew_delayed" if delay > 1.0e-9 else "direct",
			"quality": q,
			"range_km": float(obs.get("range_km", -1.0)),
			"bearing_deg": float(obs.get("bearing_deg", -1.0))})
		if not bool(ar.get("ok", false)):
			accepted = false
			reject_reason = String(ar.get("reason", "owner_rejected"))
		elif bool(ar.get("duplicated", false)):
			accepted = false
			reject_reason = "duplicate_delivery"
	# R2：owner 拒绝/去重项不得再写全局 TrackTable 与映射（窄守卫）
	if not accepted:
		(_ew_rejected_deliveries as Array).append({
			"observation_id": String(entry.get("observation_id", "")),
			"owner_id": owner_id, "target_id": target,
			"reason": reject_reason, "t": now_s()})
		return
	if track_table != null:
		# TrackTable 事件时间 = 到达时间；原始观测时刻/几何仍保留（不重生成旧观测）
		var tbl_obs: Dictionary = obs.duplicate(true)
		tbl_obs["observed_t"] = observed_t
		tbl_obs["t"] = received_t
		var r: Dictionary = track_table.handle_observation(tbl_obs, _track_writer)
		if not bool(r.get("ok", false)):
			accepted = false
			reject_reason = String(r.get("reason", "track_rejected"))
		else:
			var tr = r.get("track", {})
			if tr is Dictionary and String((tr as Dictionary).get("id", "")) != "":
				_sensor_track_map[target] = String((tr as Dictionary).get("id", ""))
	if not accepted:
		(_ew_rejected_deliveries as Array).append({
			"observation_id": String(entry.get("observation_id", "")),
			"owner_id": owner_id, "target_id": target,
			"reason": reject_reason, "t": now_s()})
		return
	if authority_intel != null and owner_id != "":
		var agg := _ew_quality_aggregate(owner_id, target, q)
		authority_intel.apply_measurement(owner_id, target, {
			"measurement_quality": q,
			"measurement_original": float(entry.get("quality_original", q)),
			"measurement_t": observed_t,
			"measurement_source": String(obs.get("sensor", "")),
			"measurement_degraded": float(entry.get("confidence_mult", 1.0)) < 0.999,
			"measurement_effect": entry.get("effect", {}),
			"aggregate_quality": agg})
	if owner_id == _identity_own_owner():
		_ew_update_combat_quality(target, q, observed_t, entry)
	# 欺骗候选：只在被影响 owner 内走普通证据验证，不自动确认
	for raw_c in (entry.get("false_observations", []) as Array):
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		var rec := {"owner_id": owner_id, "target_id": target,
			"candidate_id": String(c.get("candidate_id", "")),
			"identity": "unknown", "confidence": float(c.get("confidence", 0.0)),
			"received_t": received_t, "observed_t": observed_t}
		(_ew_candidates as Array).append(rec)
		if _identity_enabled and _identity_owner_ok(owner_id):
			identity_ingest(owner_id, {
				"target_id": target, "source": "sensor",
				"identity": "unknown",
				"confidence": float(c.get("confidence", 0.0)),
				"category": "sensor", "evidence_type": "deception_candidate",
				"event_id": String(c.get("candidate_id", "")),
				"observed_t": observed_t, "received_t": received_t,
				"note": "ew_deception_candidate"})
	(_ew_delivered as Array).append({"observation_id": String(
		entry.get("observation_id", "")), "owner_id": owner_id,
		"target_id": target, "observed_t": observed_t,
		"received_t": received_t, "delay_s": delay,
		"quality": q, "quality_original": float(entry.get("quality_original", q)),
		"confidence_mult": float(entry.get("confidence_mult", 1.0)),
		"truth_regenerated": false})
	while (_ew_delivered as Array).size() > 400:
		(_ew_delivered as Array).pop_front()


func _deliver_due_ew_observations() -> int:
	if _ew_obs_queue.is_empty():
		return 0
	var due: Array = []
	var kept: Array = []
	for raw in (_ew_obs_queue as Array):
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if float(e.get("arrive_t", 0.0)) <= now_s() + 1.0e-9:
			due.append(e)
		else:
			kept.append(e)
	_ew_obs_queue = kept
	# 稳定次序：arrive_t 优先，其次 seq
	due.sort_custom(func(a, b):
		var ta := float((a as Dictionary).get("arrive_t", 0.0))
		var tb := float((b as Dictionary).get("arrive_t", 0.0))
		if absf(ta - tb) > 1.0e-9:
			return ta < tb
		return int((a as Dictionary).get("seq", 0)) < int((b as Dictionary).get("seq", 0)))
	for raw2 in due:
		_deliver_ew_observation(raw2)
	return due.size()


func _ew_update_combat_quality(target_id: String, quality: float, observed_t: float,
		entry: Dictionary) -> void:
	if combat_service == null:
		return
	var patch := {"measurement_quality": quality,
		"measurement_original": float(entry.get("quality_original", quality)),
		"measurement_t": observed_t,
		"measurement_source": String(entry.get("sensor", "")),
		"measurement_degraded": float(entry.get("confidence_mult", 1.0)) < 0.999}
	_ew_combat_quality[target_id] = {"quality": quality, "t": observed_t,
		"source": String(entry.get("sensor", ""))}
	var keys: Array = [target_id]
	var mapped := String(_sensor_track_map.get(target_id, ""))
	if mapped != "" and mapped != target_id:
		keys.append(mapped)
	var ent := _entity_for_track(target_id)
	if ent != "" and ent != target_id:
		keys.append(ent)
	for k in keys:
		var tr = combat_service.track(String(k))
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			combat_service.update_track(String(k), patch)


## 火控边界：把 owner 当前测量质量投影到实际 combat 航迹（缺省 1.0 兼容）。
func _sync_ew_quality_to_combat(target_id: String) -> void:
	var owner := _identity_own_owner()
	var key := target_id
	var mq: Dictionary = owner_measurement_quality(owner, target_id)
	if not bool(mq.get("ok", false)):
		var res: Dictionary = _identity_resolve_target(owner, target_id)
		if bool(res.get("ok", false)):
			key = String(res.get("target_id", target_id))
			mq = owner_measurement_quality(owner, key)
	if not bool(mq.get("ok", false)):
		return
	var patch := {"measurement_quality": float(mq.get("measurement_quality", 1.0)),
		"measurement_original": float(mq.get("measurement_original", 1.0)),
		"measurement_t": float(mq.get("measurement_t", 0.0)),
		"measurement_source": String(mq.get("measurement_source", "")),
		"measurement_degraded": bool(mq.get("degraded", false)),
		"measurement_aggregate": float(mq.get("aggregate_quality", 1.0))}
	for k2 in [target_id, key]:
		var tr = combat_service.track(String(k2)) if combat_service != null else null
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			combat_service.update_track(String(k2), patch)


# ── 只读访问器（探针/审计/HUD 诊断）────────────────────────────
func ew_observation_samples() -> Array:
	return (_ew_samples as Array).duplicate(true)


func ew_delivery_queue() -> Array:
	return (_ew_obs_queue as Array).duplicate(true)


func ew_delivered_observations() -> Array:
	return (_ew_delivered as Array).duplicate(true)


func ew_rejected_deliveries() -> Array:
	return (_ew_rejected_deliveries as Array).duplicate(true)


func ew_candidate_evidence(owner_id: String) -> Array:
	var out: Array = []
	for raw in (_ew_candidates as Array):
		if raw is Dictionary and String((raw as Dictionary).get(
				"owner_id", "")) == owner_id:
			out.append((raw as Dictionary).duplicate(true))
	return out


func ew_visible_tracks(owner_id: String) -> Array:
	var v: Dictionary = intel_view(owner_id)
	return (v.get("tracks", []) as Array).duplicate(true) \
		if v.get("tracks") is Array else []


func owner_measurement_quality(owner_id: String, target_id: String) -> Dictionary:
	if authority_intel == null:
		return {"ok": false, "reason": "no_authority_intel"}
	return authority_intel.measurement_quality(owner_id, target_id)


func combat_measurement_quality(target_id: String) -> Dictionary:
	var key := target_id
	var res: Dictionary = _identity_resolve_target(_identity_own_owner(), target_id) \
		if _identity_enabled else {"ok": false}
	if bool(res.get("ok", false)):
		key = String(res.get("target_id", target_id))
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var tr = combat_service.track(key)
	if not (tr is Dictionary) or (tr as Dictionary).is_empty():
		return {"ok": false, "reason": "no_combat_track", "target_id": key}
	if not (tr as Dictionary).has("measurement_quality"):
		return {"ok": false, "reason": "no_measurement_quality",
			"target_id": key}
	return {"ok": true, "target_id": key,
		"measurement_quality": float((tr as Dictionary).get("measurement_quality", 1.0)),
		"measurement_original": float((tr as Dictionary).get(
			"measurement_original", 1.0)),
		"measurement_t": float((tr as Dictionary).get("measurement_t", 0.0)),
		"degraded": bool((tr as Dictionary).get("measurement_degraded", false)),
		"aggregate_quality": float((tr as Dictionary).get(
			"measurement_aggregate", 1.0)),
		"source": String((tr as Dictionary).get("measurement_source", ""))}


## JC-A03：EW 观测状态恢复（旧档缺省为空 → EW=0 兼容）
## JC-A03/R3：新 EW 段类型/必要字段校验；present-invalid 明确失败，
## 只有真正缺段（旧档）才按空段兼容。
## JC-A03/R3：新 EW 段验证——present-invalid 明确失败；可选字段缺失给出
## 可解释的 partial 模式（有意兼容默认），不全缺（旧档）才算 legacy_absent。

## R3：清除 EW 运行态；用于旧档覆盖/新会话初始化。
func _ew_reset_runtime() -> void:
	_ew_samples = []
	_ew_obs_queue = []
	_ew_delivered = []
	_ew_candidates = []
	_ew_rejected_deliveries = []
	_ew_obs_seq = 0
	_ew_quality_history = {}
	_ew_combat_quality = {}

func _ew_restore_state(data: Dictionary) -> Dictionary:
	_ew_restore_missing = []
	var array_fields := ["ew_observation_samples", "ew_observation_queue",
		"ew_delivered_observations", "ew_candidates",
		"ew_rejected_deliveries"]
	var dict_fields := ["ew_quality_history", "ew_combat_quality"]
	var all_fields := array_fields + dict_fields + ["ew_observation_seq"]
	var present := 0
	for k in all_fields:
		if data.has(k):
			present += 1
	if present == 0:
		# R3：旧档覆盖时清除加载前的 EW 运行态，fresh/active 语义一致
		_ew_reset_runtime()
		_ew_restore_mode = "legacy_absent"
		return {"ok": true, "mode": _ew_restore_mode}
	for k2 in array_fields:
		if data.has(k2) and not (data.get(k2) is Array):
			_ew_restore_mode = "invalid"
			return {"ok": false, "reason": "invalid_ew_state",
				"field": k2, "detail": "必须是数组"}
	for k3 in dict_fields:
		if data.has(k3) and not (data.get(k3) is Dictionary):
			_ew_restore_mode = "invalid"
			return {"ok": false, "reason": "invalid_ew_state",
				"field": k3, "detail": "必须是对象"}
	if data.has("ew_observation_seq"):
		var seq_v = data.get("ew_observation_seq")
		if not (seq_v is int or seq_v is float) or float(seq_v) < 0.0 \
				or not is_finite(float(seq_v)):
			_ew_restore_mode = "invalid"
			return {"ok": false, "reason": "invalid_ew_state",
				"field": "ew_observation_seq", "detail": "必须是非负有限数"}
	# 队列条目必要值与类型（只有 present 时才校验）
	if data.has("ew_observation_queue"):
		for raw in (data.get("ew_observation_queue") as Array):
			if not (raw is Dictionary):
				_ew_restore_mode = "invalid"
				return {"ok": false, "reason": "invalid_ew_state",
					"field": "ew_observation_queue", "detail": "条目必须是对象"}
			var e: Dictionary = raw
			for req in ["observation_id", "owner_id", "target_id", "observed_t",
					"arrive_t", "obs"]:
				if not e.has(req):
					_ew_restore_mode = "invalid"
					return {"ok": false, "reason": "invalid_ew_state",
						"field": "ew_observation_queue",
						"detail": "条目缺少 " + req}
			if not (e.get("obs") is Dictionary):
				_ew_restore_mode = "invalid"
				return {"ok": false, "reason": "invalid_ew_state",
					"field": "ew_observation_queue", "detail": "obs 必须是对象"}
			for tf in ["observed_t", "arrive_t"]:
				var tv = e.get(tf)
				if not (tv is int or tv is float) or not is_finite(float(tv)):
					_ew_restore_mode = "invalid"
					return {"ok": false, "reason": "invalid_ew_state",
						"field": "ew_observation_queue", "detail": tf + " 非法"}
	# 未出现的字段：有意兼容默认并记录（partial），不触发未处理转换异常
	for k4 in all_fields:
		if not data.has(k4):
			_ew_restore_missing.append(k4)
	_ew_samples = (data.get("ew_observation_samples", []) as Array).duplicate(true) \
		if data.has("ew_observation_samples") else []
	_ew_obs_queue = (data.get("ew_observation_queue", []) as Array).duplicate(true) \
		if data.has("ew_observation_queue") else []
	_ew_delivered = (data.get("ew_delivered_observations", []) as Array) \
		.duplicate(true) if data.has("ew_delivered_observations") else []
	_ew_candidates = (data.get("ew_candidates", []) as Array).duplicate(true) \
		if data.has("ew_candidates") else []
	_ew_rejected_deliveries = (data.get("ew_rejected_deliveries", []) as Array) \
		.duplicate(true) if data.has("ew_rejected_deliveries") else []
	if data.has("ew_observation_seq"):
		_ew_obs_seq = int(data.get("ew_observation_seq"))
	else:
		_ew_obs_seq = 0
	_ew_quality_history = (data.get("ew_quality_history") as Dictionary) \
		.duplicate(true) if data.has("ew_quality_history") else {}
	_ew_combat_quality = (data.get("ew_combat_quality") as Dictionary) \
		.duplicate(true) if data.has("ew_combat_quality") else {}
	_ew_restore_mode = "full" if _ew_restore_missing.is_empty() else "partial"
	return {"ok": true, "mode": _ew_restore_mode,
		"missing": _ew_restore_missing.duplicate(),
		"queue": (_ew_obs_queue as Array).size()}
# ── EWService 包装（可选；效果只读接口 + 显式 apply/emcon）──────

func ew_vm() -> Dictionary:
	return ew_service.vm() if ew_service != null else {}


func apply_ew(effect: Dictionary) -> Dictionary:
	if ew_service == null:
		return {"ok": false, "reason": "no_ew_service"}
	var res: Dictionary = ew_service.apply(effect)
	if bool(res.get("ok", false)):
		_record({"op": "apply_ew", "effect": effect.duplicate(true)})
	return res


func set_ew_emcon(on: bool) -> Dictionary:
	if ew_service == null:
		return {"ok": false, "reason": "no_ew_service"}
	var res: Dictionary = ew_service.set_emcon(bool(on))
	if bool(res.get("ok", false)):
		_record({"op": "ew_emcon", "on": bool(on)})
	return res


## 显式效果查询（不写 world/TrackTable）：观测/通信/应答机。
func ew_observation_effect(target_id := "", sensor_kind := "radar") -> Dictionary:
	if ew_service == null:
		return {"ok": false, "reason": "no_ew_service"}
	return ew_service.observation_effect(target_id, sensor_kind)


func ew_comms_effect(target_id := "") -> Dictionary:
	if ew_service == null:
		return {"ok": false, "reason": "no_ew_service"}
	return ew_service.comms_effect(target_id)


func ew_transponder_effect(target_id := "") -> Dictionary:
	if ew_service == null:
		return {"ok": false, "reason": "no_ew_service"}
	return ew_service.transponder_effect(target_id)


func ew_active(target_id := "", kind := "") -> Array:
	return ew_service.active(target_id, kind) if ew_service != null else []
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
	var res: Dictionary = comms.send(from_id, to_id, mode, text_key, pl_norm, po_norm)
	# A-06：操作记录带**版本化 outcome**。原始失败（例如 orbital_sim 无 LR 链 → no_route）
	# 必须在读档重放后仍是同一失败，而不能被当成恢复错误。
	# 先执行再记录，保证 outcome 是原始执行的实测值。
	_record({"op": "send_comms", "from_id": from_id, "to_id": to_id, "mode": mode,
		"text_key": text_key, "payload": pl_norm, "opts": po_norm,
		"outcome": {
			"schema": COMMS_OUTCOME_SCHEMA, "version": COMMS_OUTCOME_VERSION,
			"ok": bool(res.get("ok", false)),
			"reason": String(res.get("reason", "")),
			"mode": String(res.get("mode", mode)),
			"delivery_id": String(res.get("delivery_id", "")),
			"path": (res.get("path", []) as Array).duplicate() \
				if res.get("path") is Array else [],
			"latency_s": float(res.get("latency_s", 0.0)),
			"relay_count": int(res.get("relay_count", 0)),
			"latency_base_s": float(res.get("latency_base_s", 0.0)),
			"latency_ew_add_s": float(res.get("latency_ew_add_s", 0.0)),
			"ew": (res.get("ew", {}) as Dictionary).duplicate(true) \
				if res.get("ew") is Dictionary else {},
			"arrive_t": float(res.get("arrive_t", -1.0)),
			"sent_t": now_s(),
		}})
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


# JC-A04：确定性 EW 抽样状态（seed/seq）与测试注入入口（仅测试用，不公开）。
func comms_ew_state() -> Dictionary:
	return comms.ew_rng_state() if comms != null else {}


func comms_debug_force_draw(x: float) -> bool:
	if comms == null or not comms.has_method("debug_force_draw"):
		return false
	comms.debug_force_draw(x)
	return true


func comms_legacy_unknown_count() -> int:
	return _comms_legacy_unknown

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

# JC-A04：真实 comms 结果回调（由 OrderService.tick 在唯一 Comms 推进后转发）。
# delivered/failed 决定 session 事件、共享融合与成功只消费一次；pending 消失不再当送达。
func _on_comms_events(events: Array) -> void:
	for raw in events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := String(ev.get("kind", "")).to_lower()
		var did := String(ev.get("delivery_id", ""))
		if did == "":
			continue
		_comms_event_ids[did] = true
		if not _standalone.has(did):
			# 非 standalone 投递（订单）由 OrderService 自行按真实结果消费；
			# 这里只清理可能残留的共享登记，且不发布假 delivered。
			if kind == "failed":
				_pending_intel_shares.erase(did)
			continue
		var info: Dictionary = _standalone[did]
		if kind == "delivered":
			_publish(_mk_event("comms.delivered", String(info.get("to", "")), {
				"delivery_id": did, "from": String(info.get("from", "")),
				"to": String(info.get("to", "")), "mode": String(info.get("mode", "")),
				"text_key": String(info.get("text_key", "")),
				"latency_s": float(info.get("latency_s", 0.0)),
				"ew": (ev.get("ew", {}) as Dictionary).duplicate(true) \
					if ev.get("ew") is Dictionary else {},
			}))
			# JC-A01/R4：共享只在**真实 delivered** 后融合一次。
			_deliver_intel_share(did, info)
		elif kind == "failed":
			_publish(_mk_event("comms.failed", String(info.get("to", "")), {
				"delivery_id": did, "from": String(info.get("from", "")),
				"to": String(info.get("to", "")), "mode": String(info.get("mode", "")),
				"text_key": String(info.get("text_key", "")),
				"reason": String(ev.get("reason", "comms_failed")),
				"ew": (ev.get("ew", {}) as Dictionary).duplicate(true) \
					if ev.get("ew") is Dictionary else {},
			}))
			_pending_intel_shares.erase(did)
		else:
			continue
		_standalone.erase(did)


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
		if _comms_event_ids.has(id):
			continue
		# 旧档/历史无真实结果：明确标记未验证，绝不发布假 delivered。
		var info: Dictionary = _standalone[id]
		_comms_legacy_unknown += 1
		_publish(_mk_event("comms.unknown_outcome", String(info.get("to", "")), {
			"delivery_id": id, "from": String(info.get("from", "")),
			"to": String(info.get("to", "")), "mode": String(info.get("mode", "")),
			"reason": "no_delivery_outcome",
		}))
		_pending_intel_shares.erase(id)
		_standalone.erase(id)
	_comms_event_ids.clear()

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
	# JC-A03：火控消费 owner 当前测量质量（消费者边界投影）
	_sync_ew_quality_to_combat(target_id)
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

## 统一交战入口：先过 CombatService 门禁（ROE/授权/解算/射程/弹药/齐射），
## 再交给 CombatBallistics 发射真实弹丸。命中不再同步返回 —— 要等 impact 事件。
## 返回 {ok, launched, projectile_ids, salvo, ...}；调用方不得再假设 hit/miss。
## 物理前置检查在门禁之前：打不出去就明确失败，绝不白扣弹药。
func request_fire(target_id: String, weapon_id: String, confirmed := false, opts := {}) -> Dictionary:
	# JC-A01：**授权门必须在任何资源/弹道/成功事件之前**。
	# 显式无效 shooter 不再回退本舰；敌方/盟军直接命令拒绝；本方无运行态返回 unavailable。
	var gate_opts: Dictionary = opts if opts is Dictionary else {}
	var auth: Dictionary = authorize_fire(gate_opts)
	if not bool(auth.get("ok", false)):
		_record_fire_audit(target_id, weapon_id, gate_opts, auth, true)
		var denied: Dictionary = auth.duplicate(true)
		denied["ok"] = false
		denied["target_id"] = target_id
		denied["weapon_id"] = weapon_id
		denied["gate"] = "authority"
		return denied
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var known = combat_service.track(target_id)
	if not (known is Dictionary) or (known as Dictionary).is_empty():
		return {"ok": false, "reason": "unknown_track", "target_id": target_id,
			"weapon_id": weapon_id}
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics", "physics": "unavailable",
			"target_id": target_id, "weapon_id": weapon_id}
	# 解出 shooter / target 实体与物理状态（失败即拒绝，不进门禁）
	var entity := String(o.get("target_entity", ""))
	if entity == "":
		entity = _entity_for_track(target_id)
	var states: Dictionary = _ballistics_states()
	# 授权门已解析出合法 shooter；以它为准（不再让下游空 shooter 再猜）
	var resolved_shooter := String(auth.get("shooter_id", ""))
	if resolved_shooter != "":
		o["shooter_id"] = resolved_shooter
	var shooter := String(o.get("shooter_id", ""))
	var ss: Dictionary = states.get(shooter, {}) if states.get(shooter) is Dictionary else {}
	if ss.is_empty():
		shooter = _own_ballistics_entity(states)
		ss = states.get(shooter, {}) if states.get(shooter) is Dictionary else {}
	var ts: Dictionary = states.get(entity, {}) if states.get(entity) is Dictionary else {}
	if ss.is_empty() or ts.is_empty():
		warnings.append("request_fire 无物理状态：shooter=%s target=%s" % [shooter, entity])
		return {"ok": false, "reason": "no_physics_state", "physics": "unavailable",
			"target_id": target_id, "weapon_id": weapon_id,
			"missing": {"shooter": ss.is_empty(), "target": ts.is_empty(),
				"target_entity": entity, "states": states.keys()}}
	# JC-A02：火控读取 owner 操作性身份（消费者边界投影，不新建真值）
	# 真实 HUD 航迹键可能无实体字段，故带上 request_fire 已合法解析出的目标实体
	_sync_combat_identity(target_id, entity)
	# JC-A03：火控消费 owner 当前测量质量（消费者边界投影）
	_sync_ew_quality_to_combat(target_id)
	var gate: Dictionary = combat_service.request_fire(target_id, weapon_id, confirmed, o)
	if not bool(gate.get("ok", false)):
		return gate
	# R2：日志必须保存**同一份规范化授权 context**（供重放按同样语义恢复）
	_record({"op": "request_fire", "target_id": target_id,
		"weapon_id": weapon_id, "confirmed": confirmed, "salvo": int(gate.get("salvo", 1)),
		"actor_id": String(auth.get("actor_id", "")),
		"controller_id": String(auth.get("controller_id", "")),
		"domain_id": String(auth.get("domain_id", "")),
		"fleet_id": String(auth.get("fleet_id", "")),
		"shooter_id": String(auth.get("shooter_id", "")),
		"legacy_context": String(auth.get("legacy_context", "")),
		"context_source": String(auth.get("context_source", "")),
		"t_s": float(now_s())})
	var res: Dictionary = gate.duplicate(true)
	# R2：把同一份规范化授权 context 透出到返回值（与日志一致）
	res["authority_context"] = {
		"actor_id": String(auth.get("actor_id", "")),
		"controller_id": String(auth.get("controller_id", "")),
		"domain_id": String(auth.get("domain_id", "")),
		"fleet_id": String(auth.get("fleet_id", "")),
		"shooter_id": String(auth.get("shooter_id", "")),
		"legacy_context": String(auth.get("legacy_context", "")),
		"context_source": String(auth.get("context_source", "")),
		"t_s": float(now_s()),
	}
	res["launched"] = 0
	res["projectile_ids"] = []
	res["physics"] = "none"
	var launch_opts: Dictionary = {
		"salvo": int(gate.get("salvo", 1)),
		"profile": o.get("profile", {}),
		"intent": String(o.get("intent", "direct")),
		"measurement_quality": float(gate.get("measurement_quality", 1.0)),
		"error_km": float(gate.get("error_km", 0.0)),
		"quality_accuracy_mult": float(gate.get("quality_accuracy_mult", 1.0)),
	}
	# 规划辅助：显式 plan 优先，否则按 intent 现场规划（direct 不规划）
	if o.get("plan") is Dictionary:
		var po: Dictionary = CombatPlannerScript.new().to_launch_opts(o.get("plan"))
		for k in po.keys():
			launch_opts[k] = po[k]
	elif String(launch_opts["intent"]) != "direct":
		var pl: Dictionary = combat_plan(target_id, weapon_id, String(launch_opts["intent"]), o)
		res["plan"] = pl
		if bool(pl.get("ok", false)):
			var po2: Dictionary = CombatPlannerScript.new().to_launch_opts(pl)
			for k2 in po2.keys():
				launch_opts[k2] = po2[k2]
		else:
			res["plan_error"] = String(pl.get("reason", ""))
	if o.get("force_pd") != null:
		launch_opts["force_pd"] = bool(o.get("force_pd"))
	var lr: Dictionary = combat_ballistics.launch(shooter, entity, weapon_id, ss, ts, launch_opts)
	res["launch"] = lr
	res["physics"] = "ballistics"
	res["shooter_id"] = shooter
	res["target_entity"] = entity
	# JC-A01：授权 context 透出（legacy 调用明确 own_ship 与本舰锚点）
	res["domain_id"] = String(auth.get("domain_id", ""))
	res["controller_id"] = String(auth.get("controller_id", ""))
	if String(auth.get("legacy_context", "")) != "":
		res["legacy_context"] = String(auth.get("legacy_context", ""))
		res["own_entity_instance_id"] = String(
			auth.get("own_entity_instance_id", ""))
	_record_fire_audit(target_id, weapon_id, gate_opts, auth, false)
	res["launched"] = int(lr.get("salvo_launched", 1 if bool(lr.get("ok", false)) else 0))
	var pids: Array = lr.get("projectile_ids", []) if lr.get("projectile_ids") is Array else []
	if pids.is_empty() and bool(lr.get("ok", false)) and String(lr.get("projectile_id", "")) != "":
		pids = [String(lr.get("projectile_id", ""))]
	res["projectile_ids"] = pids
	if not bool(lr.get("ok", false)):
		res["ok"] = false
		res["reason"] = String(lr.get("reason", "launch_failed"))
		return res
	res["prediction"] = _ballistics_predict(shooter, entity, weapon_id, {
		"measurement_quality": float(gate.get("measurement_quality", 1.0)),
		"error_km": float(gate.get("error_km", 0.0)),
		"quality": float(gate.get("quality", -1.0)),
		"quality_accuracy_mult": float(gate.get("quality_accuracy_mult", 1.0))})
	var cap: Dictionary = _apply_combat_time_cap()
	res["time_cap"] = cap
	return res


## 玩家设置齐射数（UI 调用）。
func set_weapon_salvo(weapon_id: String, n: int) -> Dictionary:
	if combat_service == null:
		return {"ok": false, "reason": "no_combat_service"}
	var res: Dictionary = combat_service.set_salvo(weapon_id, n)
	if bool(res.get("ok", false)):
		_record({"op": "set_weapon_salvo", "weapon_id": weapon_id, "salvo": int(res.get("salvo", 1))})
	return res


## 按航迹 id 做真实弹道预测（UI 用；不发射）。
func combat_predict_track(target_id: String, weapon_id: String) -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics"}
	var states: Dictionary = _ballistics_states()
	var entity := _entity_for_track(target_id)
	var shooter := _own_ballistics_entity(states)
	if shooter == "" or entity == "" or not states.has(entity):
		return {"ok": false, "reason": "no_physics_state",
			"shooter": shooter, "target_entity": entity}
	# R1：正常发射前路径按 owner 合法映射读同一质量（实体键/匿名 HUD 航迹键）
	var owner := _identity_own_owner()
	var mq_pred: Dictionary = owner_measurement_quality(owner, entity)
	if not bool(mq_pred.get("ok", false)):
		mq_pred = owner_measurement_quality(owner, target_id)
	if not bool(mq_pred.get("ok", false)) and _identity_enabled:
		var rr: Dictionary = _identity_resolve_target(owner, target_id)
		if bool(rr.get("ok", false)):
			mq_pred = owner_measurement_quality(owner, String(rr.get("target_id", "")))
	var popts: Dictionary = {}
	if bool(mq_pred.get("ok", false)):
		popts["measurement_quality"] = float(mq_pred.get("measurement_quality", 1.0))
		# 与接口层同一冻结规则：显式 quality/error 供弹道预测直接采用
		var ckey := String(mq_pred.get("target_id", entity))
		var ctr = combat_service.track(ckey) if combat_service != null else null
		if not (ctr is Dictionary) or (ctr as Dictionary).is_empty():
			ctr = combat_service.track(entity) if combat_service != null else null
		var wdef: Dictionary = combat_service.weapon_def(weapon_id) \
			if combat_service != null else {}
		if ctr is Dictionary and not (ctr as Dictionary).is_empty() \
				and not wdef.is_empty():
			var rng := float((ctr as Dictionary).get("range_km", 0.0))
			var qbase := clampf(float(wdef.get("accuracy", 0.5)) * (1.0 - clampf(
				rng / maxf(1.0, float(wdef.get("range_km", 1.0))), 0.0, 1.0) * 0.25),
				0.0, 1.0)
			var mqv := float(popts["measurement_quality"])
			var mult := 0.85 if mqv < 0.9 - 1.0e-9 else 1.0
			var qif := clampf(qbase * mult, 0.0, 1.0)
			popts["quality"] = qif
			popts["quality_accuracy_mult"] = mult
			popts["error_km"] = maxf(0.0, rng * (1.0 - qif) * 0.01)
	return combat_ballistics.predict(states[shooter], states[entity], weapon_id, popts)


## 交战规划辅助：把意图翻译成巡航剖面，并给出 Δv 预算/可行性（发射前可预演）。
func combat_plan(target_id: String, weapon_id: String, intent := "direct", opts := {}) -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics"}
	var states: Dictionary = _ballistics_states()
	var entity := _entity_for_track(target_id)
	var shooter := _own_ballistics_entity(states)
	if shooter == "" or entity == "" or not states.has(entity):
		return {"ok": false, "reason": "no_physics_state",
			"shooter": shooter, "target_entity": entity}
	var planner = CombatPlannerScript.new()
	var salvo := 1
	if combat_service != null:
		salvo = combat_service.salvo_of(weapon_id)
	var plan: Dictionary
	if salvo > 1:
		plan = planner.plan_salvo(combat_ballistics, states[shooter], states[entity],
			weapon_id, salvo, intent, opts)
	else:
		plan = planner.plan(combat_ballistics, states[shooter], states[entity],
			weapon_id, intent, opts)
	plan["shooter_id"] = shooter
	plan["target_entity"] = entity
	plan["salvo"] = salvo
	return plan


## 航迹 id → 物理实体 id（track.entity_id 优先，其次 ship_id，最后同名实体）。
func _entity_for_track(track_id: String) -> String:
	var cands: Array = []
	# JC-A02/R3：真实 HUD 种入的 combat 行常无 entity_id/ship_id；
	# 用已验证 sensor target→track 映射反查稳定实体（不读隐藏真值）。
	for k in _sensor_track_map.keys():
		if String(_sensor_track_map[k]) == track_id:
			cands.append(String(k))
	if combat_service != null:
		var tr = combat_service.track(track_id)
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			cands.append(String((tr as Dictionary).get("entity_id", "")))
			cands.append(String((tr as Dictionary).get("ship_id", "")))
	cands.append(track_id)
	for c in cands:
		var id := String(c)
		if id != "" and _has_physics_entity(id):
			return id
	return ""


func _has_physics_entity(id: String) -> bool:
	if id == "":
		return false
	if physics_world_service != null:
		for eid in physics_world_service.entity_ids():
			if String(eid) == id:
				return true
	if world != null and world.has_entity(id):
		return true
	return false


func _own_ballistics_entity(states: Dictionary) -> String:
	## 本舰实体：seed.own_entity → combat_service.own_id → tags(own/own_fleet) →
	## 第一个带 PD 的实体 → 第一个 friend。全空则无法发射（明确失败，不猜）。
	var cands: Array = [String(_seed.get("own_entity", "")),
		String(combat_service.own_id) if combat_service != null else ""]
	for c in cands:
		if String(c) != "" and states.has(String(c)):
			return String(c)
	if world != null:
		for raw in world.entities_sorted():
			if not (raw is Dictionary):
				continue
			var e: Dictionary = raw
			var eid := String(e.get("id", ""))
			if not states.has(eid):
				continue
			var tags: Array = e.get("tags", []) if e.get("tags") is Array else []
			if "own" in tags or "own_fleet" in tags:
				return eid
	for k in states.keys():
		if bool((states[k] as Dictionary).get("has_pd", false)):
			return String(k)
	for k2 in states.keys():
		if String((states[k2] as Dictionary).get("side", "")) == "friend":
			return String(k2)
	return ""


## 物理层预测（真实积分，替代 CombatService 的接口层估算）。
func _ballistics_predict(shooter: String, entity: String,
		weapon_id: String, opts := {}) -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics"}
	var states: Dictionary = _ballistics_states()
	if not states.has(shooter) or not states.has(entity):
		return {"ok": false, "reason": "no_physics_state"}
	return combat_ballistics.predict(states[shooter], states[entity], weapon_id, opts)


## 交战时间膨胀：有弹在飞时把时间倍速压到 COMBAT_SCALE_CAP，交战结束恢复。
## 否则 900 s 导弹寿命在 3600× 下只有 0.25 实秒，玩家看不到交战过程。
func _apply_combat_time_cap() -> Dictionary:
	if time == null or combat_ballistics == null:
		return {"ok": false, "reason": "unavailable"}
	var engaged := (combat_ballistics.active_projectiles() as Array).size() > 0
	if engaged and not _combat_scale_cap_active and float(time.scale) > COMBAT_SCALE_CAP:
		_scale_before_combat = float(time.scale)
		time.set_scale(COMBAT_SCALE_CAP)
		_combat_scale_cap_active = true
		warnings.append("交战时间膨胀：倍速 %.0f× → %.0f×" % [_scale_before_combat, COMBAT_SCALE_CAP])
		return {"ok": true, "capped": true, "scale": float(time.scale),
			"restore_to": _scale_before_combat}
	if not engaged and _combat_scale_cap_active:
		time.set_scale(_scale_before_combat)
		_combat_scale_cap_active = false
		return {"ok": true, "capped": false, "scale": float(time.scale)}
	return {"ok": true, "capped": _combat_scale_cap_active, "scale": float(time.scale)}


func combat_time_cap_state() -> Dictionary:
	return {"active": _combat_scale_cap_active, "restore_to": _scale_before_combat,
		"cap": COMBAT_SCALE_CAP, "scale": float(time.scale) if time != null else 0.0}




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
# ── EntityCatalog 委托（静态元数据权威；只读）────────────────────

func entity_catalog_ready() -> bool:
	return entity_catalog != null and bool(entity_catalog.ready)

## 按 entity_id 返回静态元数据只读副本；未知实体返回 {found:false,id}。
## 这些是**世界内部真值/静态资料**，不得自动写入玩家航迹/UI；玩家可见结论
## 必须来自观测/证据/人工授权链路。
func entity_metadata(entity_id: String) -> Dictionary:
	if entity_catalog == null:
		return {"found": false, "id": entity_id, "reason": "no_entity_catalog"}
	return entity_catalog.get_entity(entity_id)

func entity_metadata_ids() -> Array:
	if entity_catalog == null:
		return []
	return entity_catalog.entity_ids()

func entity_metadata_all() -> Array:
	if entity_catalog == null:
		return []
	return entity_catalog.all_entities()

func entity_catalog_snapshot() -> Dictionary:
	if entity_catalog == null:
		return {"schema": "v17.entity_catalog.v1", "ready": false, "entities": []}
	return entity_catalog.snapshot()

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
# ── IdentificationService 委托（识别自动化/证据融合；可选）──────

## 识别证据桥：track_evidence.v1 → IdentificationService（身份融合）。
## 只搬运证据自带字段（identity/confidence/status/spoofed/mode），不做任何身份推断；
## TrackTable 仍是航迹权威，识别服务只输出评估，不写 world/TrackTable。
func _bridge_identity_evidence(ev: Dictionary, owner_hint := "") -> void:
	if not _identity_enabled or identification_service == null:
		return
	var tid := str(ev.get("target_id", ""))
	if tid == "":
		return
	var et := str(ev.get("evidence_type", ev.get("type", "")))
	var raw_source := str(ev.get("source", ""))
	var ident_source := "track"
	if raw_source == "transponder_service":
		ident_source = "transponder"
	elif et == "iff":
		ident_source = "iff"
	elif et in ["optical", "visual", "ir"]:
		ident_source = "optical"
	elif et == "elint":
		ident_source = "elint"
	elif et == "database":
		ident_source = "database"
	elif raw_source == "sensor_service":
		ident_source = "sensor"
	# 证据的 owner 优先取事件内可信 owner（真实查询/会话内注入），
	# 无 owner 的 legacy 才回退本舰 owner；显式跨 owner 绝不被本舰吞掉。
	var owner := String(ev.get("owner_id", ""))
	if owner == "":
		owner = String(owner_hint)
	if owner == "":
		owner = _identity_own_owner()
	if owner == "" or not _identity_owner_ok(owner):
		return
	if _identity_enabled:
		identity_ingest(owner, {
			"target_id": tid, "source": ident_source,
			"observed_t": float(ev.get("t", now_s())),
			"identity": str(ev.get("identity", "unknown")),
			"confidence": float(ev.get("confidence", 0.5)),
			"spoofed": bool(ev.get("spoofed", false)),
			"status": str(ev.get("status", "")),
			"mode": str(ev.get("mode", "")),
			"category": _identity_category_for(ident_source),
			"evidence_type": et if et != "" else ident_source,
			"event_id": String(ev.get("event_id", ev.get("evidence_id", ""))),
			"note": "track_evidence_bridge"})
	else:
		identification_service.ingest({
			"target_id": tid, "source": ident_source,
			"t": float(ev.get("t", now_s())),
			"identity": str(ev.get("identity", "unknown")),
			"confidence": float(ev.get("confidence", 0.5)),
			"spoofed": bool(ev.get("spoofed", false)),
			"status": str(ev.get("status", "")),
			"mode": str(ev.get("mode", "")),
			"evidence_type": et if et != "" else ident_source})

## 识别服务是否可用（未在 seed 启用时为 false，UI 必须显示 NOT READY）。
## ── JC-A02：多来源身份管道（owner 维度）────────────────────────
## 唯一写者：Session 归一化四来源证据 → owner 计算器 → authority_intel.apply_identity。
## HUD/火控只读该操作结果；不在此处改写隐藏真值。
const IDENTITY_SOURCES := ["transponder", "iff", "elint", "ew", "optical",
	"sensor", "manual", "track", "database"]
const IDENTITY_SOURCE_ALIAS := {"iff": "transponder", "ew": "elint"}
const IDENTITY_CATEGORY_BY_SOURCE := {"transponder": "iff", "iff": "iff",
	"elint": "elint", "ew": "elint", "optical": "sensor",
	"sensor": "sensor", "track": "sensor", "manual": "manual",
	"database": "database"}
const IDENTITY_MANUAL_AUTHORITIES := ["command", "co", "captain",
	"tactical", "watch_officer", "cic_operator"]

var _identity_owners: Dictionary = {}       # owner -> IdentificationService
var _identity_enabled := false
var _identity_cfg: Dictionary = {}
var _identity_restore_mode := "absent"
var _identity_pending_queries: Dictionary = {}  # owner -> [query]
var _identity_query_queue: Array = []       # 真实延迟查询：{owner,target,profile,mode,opts,arrive_t,query_id}
var _identity_query_seq := 0
var _identity_seen_events: Dictionary = {}  # "<event_id>|<owner>" -> true
var _last_identity_audit_id := ""
var identity_operational_writes := 0


func _identity_own_owner() -> String:
	if authority_intel != null and String(authority_intel.own_owner) != "":
		return String(authority_intel.own_owner)
	if authority_intel != null and String(_seed.get("own_entity", "")) != "":
		return String(authority_intel.owner_of_entity(
			String(_seed.get("own_entity", ""))))
	return ""


func _identity_domain_for_owner(owner_id: String) -> Dictionary:
	if authority_intel == null or owner_id == "":
		return {}
	for did in authority_intel.domains.keys():
		var d: Dictionary = authority_intel.domains[did]
		if String(d.get("intel_owner_id", "")) == owner_id:
			var out := d.duplicate(true)
			out["domain_id"] = String(did)
			return out
	return {}


func _identity_default_actor(owner_id: String) -> String:
	var d := _identity_domain_for_owner(owner_id)
	if d.is_empty():
		return ""
	var ctrl := String(d.get("controller_id", ""))
	if ctrl != "":
		return ctrl
	var actors: Array = d.get("authorized_actors", []) if d.get("authorized_actors") is Array else []
	return String(actors[0]) if actors.size() > 0 else ""


## 受信 actor/authority 校验：人工确认权与 FIRE/ROE 许可分开，不互相授予。
func _identity_actor_trusted(owner_id: String, actor_id: String,
		authority: String) -> Dictionary:
	if not (authority in IDENTITY_MANUAL_AUTHORITIES):
		return {"ok": false, "reason": "unauthorized",
			"detail": "authority 不受信：" + authority}
	var d := _identity_domain_for_owner(owner_id)
	if d.is_empty():
		return {"ok": false, "reason": "unknown_owner"}
	var actor := actor_id
	if actor == "":
		actor = String(d.get("controller_id", ""))
	var allowed: Array = (d.get("authorized_actors", []) as Array) \
		if d.get("authorized_actors") is Array else []
	allowed = allowed.duplicate()
	var ctrl := String(d.get("controller_id", ""))
	if ctrl != "" and not (ctrl in allowed):
		allowed.append(ctrl)
	if not (actor in allowed):
		return {"ok": false, "reason": "actor_not_authorized",
			"detail": "actor 不在该 owner 域授权名单：" + actor}
	return {"ok": true, "actor_id": actor, "domain_id": String(
		d.get("domain_id", "")), "authority": authority}


func _identity_service_for(owner_id: String):
	if not _identity_enabled or owner_id == "":
		return null
	if owner_id == _identity_own_owner() and identification_service != null:
		_identity_owners[owner_id] = identification_service
		return identification_service
	if _identity_owners.has(owner_id):
		return _identity_owners[owner_id]
	var svc = IdentificationServiceScript.new(_identity_cfg.duplicate(true))
	if not bool(svc.ready):
		errors.append("identity owner 计算器未就绪：" + owner_id)
		return null
	svc.set_time(now_s())
	_identity_owners[owner_id] = svc
	return svc


func _identity_owner_ok(owner_id: String) -> bool:
	return owner_id != "" and authority_intel != null \
		and bool(authority_intel.owner_known(owner_id))


func identity_enabled() -> bool:
	return _identity_enabled


func _identity_category_for(source: String) -> String:
	return String(IDENTITY_CATEGORY_BY_SOURCE.get(source.to_lower(), "other"))


## 四来源归一化入口：校验 owner/来源/时间区间/TTL 后写入该 owner 计算器。
func identity_ingest(owner_id: String, raw: Variant) -> Dictionary:
	if not _identity_enabled:
		return {"ok": false, "reason": "identity_disabled"}
	if not _identity_owner_ok(owner_id):
		return {"ok": false, "reason": "unknown_owner", "owner_id": owner_id}
	if not (raw is Dictionary):
		return {"ok": false, "reason": "invalid_evidence"}
	var svc = _identity_service_for(owner_id)
	if svc == null:
		return {"ok": false, "reason": "no_identity_service"}
	var r: Dictionary = raw
	var target := String(r.get("target_id", ""))
	if target == "":
		return {"ok": false, "reason": "invalid_target"}
	var source := String(r.get("source", "")).to_lower()
	if source == "":
		return {"ok": false, "reason": "invalid_source"}
	if not (source in IDENTITY_SOURCES):
		return {"ok": false, "reason": "unsupported_source", "source": source}
	var now := now_s()
	var obs_t := now
	if r.has("observed_t"):
		var ov = r.get("observed_t")
		if not (ov is int or ov is float) or not is_finite(float(ov)):
			return {"ok": false, "reason": "invalid_observed_t"}
		obs_t = float(ov)
	if obs_t > now + 1.0e-9:
		return {"ok": false, "reason": "observed_in_future"}
	var recv_t := now
	if r.has("received_t"):
		var rv = r.get("received_t")
		if not (rv is int or rv is float) or not is_finite(float(rv)):
			return {"ok": false, "reason": "invalid_received_t"}
		recv_t = float(rv)
	if recv_t + 1.0e-9 < obs_t:
		return {"ok": false, "reason": "received_before_observed"}
	var ttl_s := float(_identity_cfg.get("evidence_ttl_s", 120.0))
	if r.get("ttl_s") is int or r.get("ttl_s") is float:
		ttl_s = maxf(0.0, float(r.get("ttl_s")))
	var identity := String(r.get("identity", "unknown")).to_lower()
	var confidence := clampf(float(r.get("confidence", 0.5)), 0.0, 1.0)
	var mode := String(r.get("mode", ""))
	var status := String(r.get("status", ""))
	var category := String(r.get("category", ""))
	if category == "":
		category = _identity_category_for(source)
	var evidence_type := String(r.get("evidence_type", source))
	var event_id := String(r.get("event_id", ""))
	# 同一来源事件只消费一次（owner 维度）
	if event_id != "" and _identity_seen_events.has(event_id + "|" + owner_id):
		return {"ok": true, "duplicate": true, "owner_id": owner_id,
			"target_id": target, "evidence_id": event_id}
	# 迟到证据（观测时刻早于该 owner 已采纳最新证据）：只记审计，不进入计算器，
	# 避免下一 tick 重算被污染。
	var latest_t := -1.0e18
	var ev_list = svc.evidence_by_target.get(target, [])
	if ev_list is Array:
		for raw_e in (ev_list as Array):
			if raw_e is Dictionary:
				latest_t = maxf(latest_t,
					float((raw_e as Dictionary).get("t", -1.0e18)))
	if latest_t > -1.0e17 and obs_t + 1.0e-9 < latest_t:
		_identity_audit(owner_id, target, "late_evidence_ignored",
			identity, source, {"observed_t": obs_t, "latest_t": latest_t})
		return {"ok": true, "owner_id": owner_id, "target_id": target,
			"late_ignored": true, "duplicate": false,
			"evidence_id": "", "assessment": {}, "operational":
				authority_intel.identity_operational(owner_id, target)}
	var service_source := String(IDENTITY_SOURCE_ALIAS.get(source, source))
	var env := {"target_id": target, "source": service_source,
		"t": obs_t, "identity": identity, "confidence": confidence,
		"mode": mode, "status": status, "category": category,
		"spoofed": bool(r.get("spoofed", false)),
		"range_km": float(r.get("range_km", 0.0)),
		"los": bool(r.get("los", true)), "emcon": bool(r.get("emcon", false)),
		"evidence_type": evidence_type,
		"note": String(r.get("note", ""))}
	var ir: Dictionary = svc.ingest(env)
	if not bool(ir.get("ok", false)):
		return ir
	if event_id != "":
		_identity_seen_events[event_id + "|" + owner_id] = true
	var ev_rec: Dictionary = ir.get("evidence", {}) \
		if ir.get("evidence") is Dictionary else {}
	if not ev_rec.is_empty():
		ev_rec["owner_id"] = owner_id
		ev_rec["received_t"] = recv_t
		ev_rec["ttl_s"] = ttl_s
		ev_rec["raw_source"] = source
		ev_rec["category"] = category
		ev_rec["evidence_type"] = evidence_type
	var assessment: Dictionary = ir.get("assessment", {}) \
		if ir.get("assessment") is Dictionary else {}
	var routed := _route_identity_assessment(owner_id, target, assessment, {
		"source": source, "observed_t": obs_t, "ttl_s": ttl_s})
	return {"ok": true, "owner_id": owner_id, "target_id": target,
		"duplicate": bool(ir.get("duplicate", false)),
		"late_ignored": false,
		"evidence_id": String(ev_rec.get("evidence_id", event_id)),
		"assessment": assessment.duplicate(true),
		"operational": routed}


## 唯一路由：assessment 状态（valid/conflict/manual/unknown）由计算器决定；
## IFF 传输状态另存，不互相覆盖。
func _route_identity_assessment(owner_id: String, target_id: String,
		assessment: Dictionary, meta := {}) -> Dictionary:
	if authority_intel == null:
		return {}
	var identity := String(assessment.get("identity", "unknown"))
	var confidence := float(assessment.get("confidence", 0.0))
	var manual := bool(assessment.get("manual", false))
	var authorized := bool(assessment.get("authorized", false))
	var sources: Array = (assessment.get("sources", []) as Array).duplicate() \
		if assessment.get("sources") is Array else []
	var contradictions: Array = (assessment.get("contradictions", []) as Array) \
		.duplicate() if assessment.get("contradictions") is Array else []
	var state := "valid"
	if contradictions.size() > 0 or identity == "suspect":
		state = "conflict"
	elif identity == "unknown":
		state = "unknown"
	if manual:
		state = "manual"
	var prev: Dictionary = authority_intel.identity_operational(owner_id, target_id)
	var changed := prev.is_empty() \
		or String(prev.get("identity", "")) != identity \
		or absf(float(prev.get("identity_confidence", 0.0)) - confidence) > 1.0e-12 \
		or String(prev.get("identity_state", "")) != state \
		or bool(prev.get("identity_manual", false)) != manual
	if not changed and not bool(meta.get("force", false)):
		return prev
	var patch := {"identity": identity,
		"identity_confidence": confidence,
		"identity_state": state,
		"identity_manual": manual,
		"identity_authorized": authorized,
		"identity_sources": sources,
		"identity_evidence_count": int(assessment.get("evidence_count", 0)),
		"identity_observed_t": float(meta.get("observed_t", now_s())),
		"identity_updated_t": float(now_s()),
		"identity_ttl_s": float(meta.get("ttl_s", 0.0)),
		"identity_level": int(assessment.get("level", 1)),
		"identity_audited": bool(meta.get("audited", false)),
		"identity_audit_ids": (meta.get("audit_ids", []) as Array).duplicate() \
			if meta.get("audit_ids") is Array else []}
	var wr: Dictionary = authority_intel.apply_identity(owner_id, target_id, patch)
	if bool(wr.get("ok", false)):
		identity_operational_writes += 1
		_publish({"type": "identity.operational", "t": now_s(),
			"source": "identity_pipeline", "target": target_id,
			"payload": {"owner_id": owner_id, "target_id": target_id,
				"identity": identity, "state": state,
				"confidence": confidence, "manual": manual,
				"authorized": authorized, "source": String(meta.get("source", ""))},
			"text_key": ""})
	return authority_intel.identity_operational(owner_id, target_id)


func identity_operational(owner_id: String, target_id: String) -> Dictionary:
	if authority_intel == null:
		return {}
	var rec: Dictionary = authority_intel.identity_operational(owner_id, target_id)
	if rec.is_empty():
		return {"ok": false, "reason": "unknown_target", "owner_id": owner_id,
			"target_id": target_id, "identity": "unknown", "state": "",
			"validity": "unknown", "valid": false,
			"effective_identity": "unknown",
			"iff_state": "not_queried"}
	var out := rec.duplicate(true)
	out["ok"] = true
	# 先算 TTL/有效性，再统一别名字段（此前别名先复制导致 stale vs valid 并存）
	var ttl := float(out.get("identity_ttl_s", 0.0))
	var obs := float(out.get("identity_observed_t", 0.0))
	var validity := "valid"
	var age := 0.0
	if ttl > 0.0:
		age = maxf(0.0, now_s() - obs)
		if age > ttl * 2.0 + 1.0e-9:
			validity = "expired"
		elif age > ttl + 1.0e-9:
			validity = "stale"
	out["identity_age_s"] = age
	out["identity_validity"] = validity
	out["validity"] = validity
	out["valid"] = validity == "valid"
	out["identity_effective"] = "unknown" if validity == "expired" \
		else String(out.get("identity", "unknown"))
	out["effective_identity"] = String(out.get("identity_effective", "unknown"))
	var st := String(out.get("identity_state", ""))
	out["state"] = st
	out["confidence"] = float(out.get("identity_confidence", 0.0))
	out["manual"] = bool(out.get("identity_manual", false))
	out["authorized"] = bool(out.get("identity_authorized", false))
	out["sources"] = (out.get("identity_sources", []) as Array).duplicate() \
		if out.get("identity_sources") is Array else []
	out["evidence_count"] = int(out.get("identity_evidence_count", 0))
	out["audited"] = bool(out.get("identity_audited", false))
	out["audit_ids"] = (out.get("identity_audit_ids", []) as Array).duplicate() \
		if out.get("identity_audit_ids") is Array else []
	# IFF 传输状态独立字段：未查询/等待/有效/无回应/过期/受干扰/缺配置
	var iff := String(out.get("identity_iff_state", "not_queried"))
	if iff == "":
		iff = "not_queried"
	if iff == "valid" and validity == "expired":
		iff = "expired"
	out["iff_state"] = iff
	out["iff_reason"] = String(out.get("identity_iff_reason", ""))
	out["iff_reply_status"] = String(out.get("identity_iff_reply_status", ""))
	return out


## owner 证据读数（审计/探针/诊断）：保留 source/category/evidence_type/时间。
func identity_evidence_for(owner_id: String, target_id: String) -> Array:
	var svc = _identity_service_for(owner_id)
	if svc == null:
		return []
	var rows = svc.evidence_by_target.get(target_id, [])
	return (rows as Array).duplicate(true) if rows is Array else []

func identity_get_for(owner_id: String, target_id: String) -> Dictionary:
	var svc = _identity_service_for(owner_id)
	if svc == null:
		return {}
	return svc.get_assessment(target_id)


## owner 限定的内部 target/track/entity 解析（匿名显示 ID 不参与路由）。
func _identity_resolve_target(owner_id: String, key: String,
		entity_hint := "") -> Dictionary:
	if key == "":
		return {"ok": false, "reason": "empty_key"}
	# request_fire 已合法解析出的目标实体优先（真实合法来源，非隐藏真值）
	if entity_hint != "" and authority_intel != null \
			and not authority_intel.identity_operational(owner_id,
				entity_hint).is_empty():
		return {"ok": true, "target_id": entity_hint, "via": "entity_hint"}
	if authority_intel != null \
			and not authority_intel.identity_operational(owner_id, key).is_empty():
		return {"ok": true, "target_id": key, "via": "identity"}
	var view: Dictionary = authority_intel.intel_view(owner_id) \
		if authority_intel != null else {}
	for raw in (view.get("tracks", []) as Array):
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		if tid == "":
			continue
		if tid == key or String(tr.get("track_id", "")) == key \
				or String(tr.get("entity_id", "")) == key \
				or String(tr.get("target_id", "")) == key:
			return {"ok": true, "target_id": tid, "via": "owner_track"}
	if combat_service != null:
		var ctr = combat_service.track(key)
		if ctr is Dictionary and not (ctr as Dictionary).is_empty():
			for fld in ["entity_id", "track_id", "target_id", "ship_id"]:
				var cand := String((ctr as Dictionary).get(fld, ""))
				if cand != "" and cand != key:
					var nxt := _identity_resolve_target(owner_id, cand)
					if bool(nxt.get("ok", false)):
						return {"ok": true,
							"target_id": String(nxt.get("target_id", "")),
							"via": "combat_track"}
	var mapped := _entity_for_track(key)
	if mapped != "" and mapped != key:
		var nxt2 := _identity_resolve_target(owner_id, mapped)
		if bool(nxt2.get("ok", false)):
			return {"ok": true,
				"target_id": String(nxt2.get("target_id", "")),
				"via": "sensor_map"}
	return {"ok": false, "reason": "unresolved", "key": key}


func identity_iff_query(owner_id: String, target_id: String,
		opts := {}) -> Dictionary:
	if not _identity_enabled:
		return {"ok": false, "reason": "identity_disabled", "state": "unavailable"}
	if not _identity_owner_ok(owner_id):
		return {"ok": false, "reason": "unknown_owner", "state": "unavailable"}
	if transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service",
			"state": "unavailable"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var prof_id := _transponder_profile_id_for(target_id)
	if prof_id == "":
		# 缺应答配置 → 明确 unavailable，绝不静默当友军
		authority_intel.apply_identity(owner_id, target_id, {
			"identity_iff_state": "unavailable",
			"identity_iff_reason": "no_transponder_profile",
			"identity_iff_t": now_s()})
		return {"ok": false, "reason": "no_transponder_profile",
			"state": "unavailable", "target_id": target_id}
	var latency := float(o.get("latency_s", 0.0))
	if latency > 1.0e-9:
		_identity_query_seq += 1
		var qid := "IFFQ-%06d" % _identity_query_seq
		(_identity_query_queue as Array).append({"query_id": qid,
			"owner_id": owner_id, "target_id": target_id,
			"profile_id": prof_id, "mode": String(o.get("mode", "")),
			"opts": o.duplicate(true), "arrive_t": now_s() + latency})
		authority_intel.apply_identity(owner_id, target_id, {
			"identity_iff_state": "pending", "identity_iff_reason": "pending",
			"identity_iff_query_id": qid, "identity_iff_t": now_s()})
		return {"ok": true, "state": "pending", "target_id": target_id,
			"owner_id": owner_id, "query_id": qid,
			"arrive_t": now_s() + latency}
	return _identity_execute_iff(owner_id, target_id, prof_id, o)


## 真实查询执行：状态来自实际 transponder 结果/原因，请求参数不冒充实际阻断原因。
func _identity_execute_iff(owner_id: String, target_id: String,
		prof_id: String, o: Dictionary) -> Dictionary:
	var mode := String(o.get("mode", ""))
	var tq: Dictionary = transponder_service.interrogate("identification",
		prof_id, mode, {"range_km": float(o.get("range_km", 0.0)),
			"occluded": bool(o.get("occluded", false)),
			"jam": float(o.get("jam", 0.0)),
			"latency_s": float(o.get("latency_s", 0.0))})
	_flush_transponder_outputs(tq.get("events", []), tq.get("evidence", []),
		owner_id)
	var reply = tq.get("reply", null)
	var state := "no_reply"
	var reason := "no_reply"
	var reply_identity := "unknown"
	var status := ""
	var spoofed := false
	if reply is Dictionary and bool((reply as Dictionary).get("ok", false)):
		var rp: Dictionary = reply
		reply_identity = String(rp.get("identity", "unknown"))
		status = String(rp.get("status", "normal"))
		spoofed = bool(rp.get("spoofed", false))
		if status == "normal":
			state = "valid"
			reason = "reply"
		else:
			state = "no_reply"
			reason = status
	else:
		status = String(tq.get("reason", "no_reply"))
		reason = status
		state = "jammed" if status == "jammed" else "no_reply"
	# 无回应也形成一条证据（unknown），这本身就是实际查询结果
	if not (reply is Dictionary and bool((reply as Dictionary).get("ok", false))):
		identity_ingest(owner_id, {
			"target_id": target_id, "source": "transponder",
			"identity": "unknown", "confidence": 0.2, "status": status,
			"mode": mode, "observed_t": now_s(),
			"event_id": "IFFQ-NOREPLY-" + target_id + "-" + str(
				int(now_s() * 1.0e6)),
			"note": "iff_query_no_reply"})
	authority_intel.apply_identity(owner_id, target_id, {
		"identity_iff_state": state, "identity_iff_reason": reason,
		"identity_iff_reply_status": status,
		"identity_iff_mode": mode,
		"identity_iff_spoofed": spoofed,
		"identity_iff_t": now_s()})
	var rec: Dictionary = authority_intel.identity_operational(owner_id, target_id)
	return {"ok": true, "state": state, "identity": reply_identity,
		"profile_id": prof_id, "reply_status": status, "reason": reason,
		"target_id": target_id, "owner_id": owner_id,
		"operational": rec.duplicate(true)}


func _identity_process_query_queue() -> int:
	if _identity_query_queue.is_empty():
		return 0
	var due: Array = []
	var kept: Array = []
	for raw in (_identity_query_queue as Array):
		if not (raw is Dictionary):
			continue
		var q: Dictionary = raw
		if float(q.get("arrive_t", 0.0)) <= now_s() + 1.0e-9:
			due.append(q)
		else:
			kept.append(q)
	_identity_query_queue = kept
	for raw2 in due:
		var q2: Dictionary = raw2
		_identity_execute_iff(String(q2.get("owner_id", "")),
			String(q2.get("target_id", "")),
			String(q2.get("profile_id", "")),
			q2.get("opts", {}) if q2.get("opts") is Dictionary else {})
	return due.size()


func identity_manual_confirm(owner_id: String, target_id: String,
		identity: String, opts := {}) -> Dictionary:
	if not _identity_enabled:
		return {"ok": false, "reason": "identity_disabled"}
	if not _identity_owner_ok(owner_id):
		return {"ok": false, "reason": "unknown_owner"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var authority := String(o.get("authority", ""))
	var actor := String(o.get("actor_id", ""))
	# 非本舰 owner 必须显式 actor（不允许默认继承）
	if actor == "" and owner_id != _identity_own_owner():
		return {"ok": false, "reason": "actor_required"}
	var tr: Dictionary = _identity_actor_trusted(owner_id, actor, authority)
	if not bool(tr.get("ok", false)):
		return tr
	var svc = _identity_service_for(owner_id)
	if svc == null:
		return {"ok": false, "reason": "no_identity_service"}
	var mo: Dictionary = {"authority": authority,
		"operator": String(o.get("operator", "")) if String(
			o.get("operator", "")) != "" else String(tr.get("actor_id", "")),
		"actor_id": String(tr.get("actor_id", "")),
		"authorized": true, "confidence": float(o.get("confidence", 1.0))}
	var mr: Dictionary = svc.manual_confirm(target_id, identity, mo)
	if not bool(mr.get("ok", false)):
		return mr
	var aid := _identity_audit(owner_id, target_id, "manual_confirm", identity,
		authority, {"actor_id": String(tr.get("actor_id", "")),
			"operator": String(mo.get("operator", "")),
			"identity": identity})
	var a: Dictionary = mr.get("assessment", {}) \
		if mr.get("assessment") is Dictionary else {}
	var routed := _route_identity_assessment(owner_id, target_id, a,
		{"source": "manual", "force": true, "audited": true,
			"audit_ids": [aid]})
	return {"ok": true, "assessment": a, "operational": routed,
		"audit_ids": [aid], "actor_id": String(tr.get("actor_id", ""))}


func identity_manual_clear(owner_id: String, target_id: String,
		opts := {}) -> Dictionary:
	if not _identity_enabled:
		return {"ok": false, "reason": "identity_disabled"}
	if not _identity_owner_ok(owner_id):
		return {"ok": false, "reason": "unknown_owner"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var authority := String(o.get("authority", ""))
	var actor := String(o.get("actor_id", ""))
	if actor == "" and owner_id != _identity_own_owner():
		return {"ok": false, "reason": "actor_required"}
	var tr: Dictionary = _identity_actor_trusted(owner_id, actor, authority)
	if not bool(tr.get("ok", false)):
		return tr
	var svc = _identity_service_for(owner_id)
	if svc == null:
		return {"ok": false, "reason": "no_identity_service"}
	var cr: Dictionary = svc.clear_manual(target_id)
	if not bool(cr.get("ok", false)):
		return cr
	var aid := _identity_audit(owner_id, target_id, "manual_clear", "",
		authority, {"actor_id": String(tr.get("actor_id", "")),
			"operator": String(o.get("operator", ""))})
	var a: Dictionary = cr.get("assessment", {}) \
		if cr.get("assessment") is Dictionary else {}
	var routed := _route_identity_assessment(owner_id, target_id, a,
		{"source": "manual", "force": true, "audited": true,
			"audit_ids": [aid]})
	return {"ok": true, "assessment": a, "operational": routed,
		"audit_ids": [aid]}


func _identity_audit(owner_id: String, target_id: String, kind: String,
		identity: String, authority: String, extra := {}) -> String:
	if authority_intel == null:
		return ""
	_last_identity_audit_id = "IDA-%06d" % (
		int((authority_intel.identity_audit as Array).size()) + 1)
	var row := {"id": _last_identity_audit_id, "kind": kind,
		"owner_id": owner_id, "target_id": target_id,
		"identity": identity, "authority": authority,
		"actor_id": String(extra.get("actor_id", "")),
		"operator": String(extra.get("operator", "")), "t": now_s()}
	for k in extra.keys():
		if not row.has(k):
			row[str(k)] = extra[k]
	(authority_intel.identity_audit as Array).append(row)
	return String(_last_identity_audit_id)


func combat_identity(target_id: String, entity_hint := "") -> Dictionary:
	var owner := _identity_own_owner()
	var res: Dictionary = _identity_resolve_target(owner, target_id, entity_hint)
	var key := String(res.get("target_id", "")) if bool(res.get("ok", false)) \
		else target_id
	var op: Dictionary = identity_operational(owner, key)
	if bool(op.get("ok", false)):
		# 火控只消费有效身份；过期只保留历史，不当作有效好友/未知
		var validity := String(op.get("validity", "valid"))
		var eff := String(op.get("effective_identity", "unknown"))
		return {"identity": eff, "last_known_identity":
				String(op.get("identity", "unknown")),
			"source": "operational_identity", "owner_id": owner,
			"state": String(op.get("state", "")), "validity": validity,
			"valid": bool(op.get("valid", false)),
			"resolved_key": key, "via": String(res.get("via", "identity")),
			"iff_state": String(op.get("iff_state", ""))}
	if combat_service != null:
		var tr = combat_service.track(target_id)
		if tr is Dictionary and not (tr as Dictionary).is_empty():
			return {"identity": String(
				(tr as Dictionary).get("identity", "unknown")),
				"source": "combat_track", "validity": "unknown",
				"valid": false, "resolved_key": ""}
	return {"identity": "unknown", "source": "none", "validity": "unknown",
		"valid": false, "resolved_key": ""}


## 火控消费者边界：把 owner 有效操作性身份投影到 combat track（不新增真值库）。
func _sync_combat_identity(target_id: String, entity_hint := "") -> void:
	if combat_service == null:
		return
	var ci: Dictionary = combat_identity(target_id, entity_hint)
	if String(ci.get("source", "")) != "operational_identity":
		return
	var tr = combat_service.track(target_id)
	if not (tr is Dictionary) or (tr as Dictionary).is_empty():
		return
	var want := String(ci.get("identity", "unknown"))
	if String((tr as Dictionary).get("identity", "")) != want:
		combat_service.update_track(target_id, {"identity": want})


func identity_report() -> Dictionary:
	var owners: Dictionary = {}
	for owner_id in _identity_owners.keys():
		var svc = _identity_owners[owner_id]
		owners[owner_id] = {"assessments": svc.assessments.size(),
			"evidence_targets": svc.evidence_by_target.size()}
	var ar: Dictionary = authority_intel.identity_report() \
		if authority_intel != null else {"writes": {}}
	return {"ok": true, "schema": "v17.identity_pipeline.v1",
		"enabled": _identity_enabled, "owners": owners,
		"writes": ar.get("writes", {}), "restore_mode": _identity_restore_mode,
		"pending_queries": (_identity_query_queue as Array).size(),
		"audit": ar.get("audit", 0), "own_owner": _identity_own_owner()}


## 推进所有 owner 计算器，并只在此处路由一次 assessment → 操作性身份。
func _identity_advance_owners(sim_dt: float) -> Dictionary:
	if not _identity_enabled:
		return {"enabled": false}
	var own := _identity_own_owner()
	if own != "" and identification_service != null:
		_identity_owners[own] = identification_service
	var advanced := 0
	for owner_id in _identity_owners.keys():
		var svc = _identity_owners[owner_id]
		if owner_id == own:
			continue  # 本舰 owner 已由 _advance_identification 推进
		svc.set_time(now_s() - maxf(0.0, float(sim_dt)))
		svc.step(sim_dt)
		advanced += 1
	for owner_id2 in _identity_owners.keys():
		var svc2 = _identity_owners[owner_id2]
		for target_id in svc2.assessments.keys():
			var tid2 := String(target_id)
			var a: Dictionary = svc2.get_assessment(tid2)
			if a.is_empty():
				continue
			var prev2: Dictionary = authority_intel.identity_operational(
				String(owner_id2), tid2) if authority_intel != null else {}
			var meta2 := {"source": "tick"}
			if not prev2.is_empty():
				meta2["observed_t"] = float(prev2.get("identity_observed_t", now_s()))
				meta2["ttl_s"] = float(prev2.get("identity_ttl_s", 0.0))
			_route_identity_assessment(String(owner_id2), tid2, a, meta2)
	var delivered := _identity_process_query_queue()
	if authority_intel != null:
		authority_intel.identity_advance(now_s())
	return {"enabled": true, "owners": _identity_owners.size(),
		"advanced": advanced, "queries_delivered": delivered}


func identification_enabled() -> bool:
	return identification_service != null


## 某目标的证据列表（按时间升序，只读副本；不写 world）。
func identification_evidence(target_id: String) -> Array:
	if identification_service == null:
		return []
	var raw = identification_service.evidence_by_target.get(target_id, [])
	if not (raw is Array):
		return []
	return (raw as Array).duplicate(true)


func identification_ingest(evidence) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.ingest(evidence)
	if bool(res.get("ok", false)) and not bool(res.get("duplicate", false)):
		_record({"op": "identification_ingest", "evidence": evidence})
		_flush_identification_outputs()
	return res

func identification_step(dt: float) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.step(dt)
	_flush_identification_outputs()
	return res

func identification_assess(target_id: String) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.assess(target_id)
	_flush_identification_outputs()
	return res

func identification_get(target_id: String) -> Dictionary:
	if identification_service == null:
		return {}
	return identification_service.get_assessment(target_id)

func identification_auto_tick(dt: float) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.auto_query_tick(dt)
	var executed: Array = []
	for raw in (res.get("requests", []) as Array):
		if raw is Dictionary:
			var ex: Dictionary = _execute_identification_query(raw as Dictionary)
			if bool(ex.get("ok", false)):
				executed.append(ex)
	_flush_identification_outputs()
	res["executed"] = executed
	return res

func identification_set_auto(enabled: bool, opts := {}) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.set_auto(enabled, opts)
	if bool(res.get("ok", false)):
		_record({"op": "identification_set_auto", "enabled": enabled, "opts": opts})
	_flush_identification_outputs()
	return res

func identification_manual_confirm(target_id: String, identity: String, opts := {}) -> Dictionary:
	# JC-A02：真实旧入口统一走受信 owner 管道（权限+审计+单一写者）
	if _identity_enabled:
		var owner := _identity_own_owner()
		var o: Dictionary = opts if opts is Dictionary else {}
		var res2: Dictionary = identity_manual_confirm(owner, target_id, identity, o)
		if bool(res2.get("ok", false)):
			_record({"op": "identification_manual_confirm", "target_id": target_id,
				"identity": identity, "opts": o, "audit_ids": res2.get("audit_ids", []),
				"outcome": {"owner_id": owner, "ok": true}})
			_flush_identification_outputs()
		return res2
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.manual_confirm(target_id, identity, opts)
	if bool(res.get("ok", false)):
		_record({"op": "identification_manual_confirm", "target_id": target_id,
			"identity": identity, "opts": opts})
	_flush_identification_outputs()
	return res

func identification_authorize_hostile(target_id: String, authority := "command", opts := {}) -> Dictionary:
	# JC-A02：旧"授权敌对"入口同样走受信 owner 人工确认（权限+审计）
	if _identity_enabled:
		var owner := _identity_own_owner()
		var o: Dictionary = opts if opts is Dictionary else {}
		o["authority"] = authority
		var r2: Dictionary = identity_manual_confirm(owner, target_id, "hostile", o)
		if bool(r2.get("ok", false)):
			_record({"op": "identification_authorize_hostile",
				"target_id": target_id, "authority": authority, "opts": o,
				"audit_ids": r2.get("audit_ids", [])})
		return r2
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.authorize_hostile(target_id, authority, opts)
	if bool(res.get("ok", false)):
		_record({"op": "identification_authorize_hostile", "target_id": target_id,
			"authority": authority, "opts": opts})
	_flush_identification_outputs()
	return res

func identification_clear_manual(target_id: String, opts := {}) -> Dictionary:
	# JC-A02：撤销人工确认需要受信 actor/authority，并写审计
	if _identity_enabled:
		var owner := _identity_own_owner()
		var o: Dictionary = opts if opts is Dictionary else {}
		var r2: Dictionary = identity_manual_clear(owner, target_id, o)
		if bool(r2.get("ok", false)):
			_record({"op": "identification_clear_manual",
				"target_id": target_id, "opts": o,
				"audit_ids": r2.get("audit_ids", [])})
		return r2
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	var res: Dictionary = identification_service.clear_manual(target_id)
	if bool(res.get("ok", false)):
		_record({"op": "identification_clear_manual", "target_id": target_id})
	_flush_identification_outputs()
	return res
func identification_set_target_state(target_id: String, state: Dictionary) -> Dictionary:
	if identification_service == null:
		return {"ok": false, "reason": "no_identification_service"}
	return identification_service.set_target_state(target_id, state)

func identification_vm() -> Dictionary:
	if identification_service == null:
		return {}
	return identification_service.vm()

func identification_summary() -> Dictionary:
	if identification_service == null:
		return {}
	return identification_service.summary()

func identification_take_query_requests() -> Array:
	if identification_service == null:
		return []
	return identification_service.take_query_requests()

# ── 法律状态（ID13；可选组件）──────────────────────────────────

func legal_apply_event(trigger: String, payload := {}) -> Dictionary:
	if legal_status_service == null:
		return {"ok": false, "reason": "no_legal_status_service"}
	var p: Dictionary = payload if payload is Dictionary else {}
	var r: Dictionary = legal_status_service.apply_event(trigger, p)
	if bool(r.get("ok", false)) and not bool(r.get("duplicate", false)):
		_record({"op": "legal_apply_event", "trigger": trigger,
			"payload": _json_norm(p)})
	return r

func legal_set_status(new_status: String, reason := "") -> Dictionary:
	if legal_status_service == null:
		return {"ok": false, "reason": "no_legal_status_service"}
	var r: Dictionary = legal_status_service.set_status(new_status, reason)
	if bool(r.get("ok", false)):
		_record({"op": "legal_set_status", "status": new_status, "reason": reason})
	return r

func legal_tick(dt: float) -> Dictionary:
	if legal_status_service == null:
		return {"ok": false, "reason": "no_legal_status_service"}
	var r: Dictionary = legal_status_service.tick(dt)
	if bool(r.get("ok", false)):
		_record({"op": "legal_tick", "dt": float(dt)})
	return r

func legal_vm() -> Dictionary:
	return legal_status_service.vm() if legal_status_service != null else {}

func legal_summary() -> Dictionary:
	return legal_status_service.summary() if legal_status_service != null else {}

func legal_impact() -> Dictionary:
	return legal_status_service.impact() if legal_status_service != null else {}

func legal_status_text() -> String:
	return legal_status_service.status if legal_status_service != null else ""

func legal_port_access() -> Dictionary:
	return legal_status_service.port_access() if legal_status_service != null else {}

func legal_status_vm() -> Dictionary:
	return legal_vm()

func legal_status_summary() -> Dictionary:
	return legal_summary()

func legal_status_impact() -> Dictionary:
	return legal_impact()

func legal_iff_watch_flag() -> bool:
	return legal_status_service.iff_watch_flag() if legal_status_service != null else false

func legal_combat_roe_modifier() -> float:
	return legal_status_service.combat_roe_modifier() if legal_status_service != null else 1.0

func legal_ending_branch_hint() -> String:
	return legal_status_service.ending_branch_hint() if legal_status_service != null else ""

# 兼容别名（脚本/UI 事件驱动）
func apply_legal_event(trigger: String, payload := {}) -> Dictionary:
	return legal_apply_event(trigger, payload)

func legal_status() -> String:
	return legal_status_text()

func legal_status_get_status() -> String:
	return legal_status_text()

# ── 交通管制（OTC/航道/NPC；可选组件）──────────────────────────

func traffic_vm() -> Dictionary:
	return traffic_control.vm() if traffic_control != null else {}

func traffic_summary() -> Dictionary:
	return traffic_control.summary() if traffic_control != null else {}

func traffic_request(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	if traffic_control == null:
		return {"ok": false, "reason": "no_traffic_control"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var r: Dictionary = traffic_control.request_clearance(track_id, lane_id, o)
	if bool(r.get("ok", false)):
		_record({"op": "traffic_request", "track_id": track_id, "lane_id": lane_id,
			"opts": _json_norm(o)})
	return r

func traffic_permit(request_id: String, opts := {}) -> Dictionary:
	if traffic_control == null:
		return {"ok": false, "reason": "no_traffic_control"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var r: Dictionary = traffic_control.permit(request_id, o)
	if bool(r.get("ok", false)):
		_record({"op": "traffic_permit", "request_id": request_id,
			"opts": _json_norm(o)})
	return r

func traffic_occupy(lane_id: String, occupant_id: String, opts := {}) -> Dictionary:
	if traffic_control == null:
		return {"ok": false, "reason": "no_traffic_control"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var r: Dictionary = traffic_control.occupy(lane_id, occupant_id, o)
	if bool(r.get("ok", false)):
		_record({"op": "traffic_occupy", "lane_id": lane_id,
			"occupant_id": occupant_id, "opts": _json_norm(o)})
	return r

func traffic_release(lane_id: String, occupant_id := "") -> Dictionary:
	if traffic_control == null:
		return {"ok": false, "reason": "no_traffic_control"}
	var r: Dictionary = traffic_control.release(lane_id, occupant_id)
	if bool(r.get("ok", false)):
		_record({"op": "traffic_release", "lane_id": lane_id,
			"occupant_id": occupant_id})
	return r

func traffic_disguise(track_id: String, disguise := {}, opts := {}) -> Dictionary:
	if traffic_control == null:
		return {"ok": false, "reason": "no_traffic_control"}
	var d: Dictionary = disguise if disguise is Dictionary else {}
	var o: Dictionary = opts if opts is Dictionary else {}
	var r: Dictionary = traffic_control.record_disguise(track_id, d, o)
	if bool(r.get("ok", false)):
		_record({"op": "traffic_disguise", "track_id": track_id,
			"disguise": _json_norm(d), "opts": _json_norm(o)})
	return r

func traffic_clues(track_id := "") -> Array:
	return traffic_control.clues_for(track_id) if traffic_control != null else []

func traffic_lane(lane_id: String) -> Dictionary:
	return traffic_control.lane(lane_id) if traffic_control != null else {}

func traffic_otc_for(cluster_id: String) -> Array:
	return traffic_control.otc_for(cluster_id) if traffic_control != null else []

# 兼容别名（脚本/UI 事件驱动）
func apply_traffic_request(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	return traffic_request(track_id, lane_id, opts)

func apply_traffic_disguise(track_id: String, disguise := {}, opts := {}) -> Dictionary:
	return traffic_disguise(track_id, disguise, opts)

# ── 战斗弹道（可选组件）────────────────────────────────────────

func combat_ballistics_vm() -> Dictionary:
	return combat_ballistics.vm() if combat_ballistics != null else {}

func combat_ballistics_summary() -> Dictionary:
	return combat_ballistics.summary() if combat_ballistics != null else {}

func combat_ballistics_active() -> Array:
	return combat_ballistics.active_projectiles() if combat_ballistics != null else []

func combat_ballistics_projectiles() -> Array:
	return combat_ballistics.projectiles_all() if combat_ballistics != null else []

func combat_ballistics_intercepts() -> Array:
	return combat_ballistics.intercept_records() if combat_ballistics != null else []

func combat_ballistics_impacts() -> Array:
	return combat_ballistics.impact_records() if combat_ballistics != null else []

func combat_ballistics_pd() -> Dictionary:
	return combat_ballistics.pd_state() if combat_ballistics != null else {}

func combat_ballistics_launch(shooter: String, target: String, weapon: String,
		opts := {}) -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_combat_ballistics"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var states: Dictionary = _ballistics_states()
	var ss: Dictionary = (o.get("shooter_state") as Dictionary) \
		if o.get("shooter_state") is Dictionary else (states.get(shooter, {}) as Dictionary)
	var ts: Dictionary = (o.get("target_state") as Dictionary) \
		if o.get("target_state") is Dictionary else (states.get(target, {}) as Dictionary)
	if ss.is_empty() or ts.is_empty():
		return {"ok": false, "reason": "unknown_entity",
			"shooter": shooter, "target": target}
	var res: Dictionary = combat_ballistics.launch(shooter, target, weapon, ss, ts, o)
	if bool(res.get("ok", false)):
		_record({"op": "combat_ballistics_launch", "shooter": shooter,
			"target": target, "weapon": weapon, "opts": _json_norm(o)})
	return res

func combat_predict(shooter: String, target: String, weapon: String,
		opts := {}) -> Dictionary:
	if combat_ballistics == null:
		return {"ok": false, "reason": "no_combat_ballistics"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var states: Dictionary = _ballistics_states()
	var ss: Dictionary = (o.get("shooter_state") as Dictionary) \
		if o.get("shooter_state") is Dictionary else (states.get(shooter, {}) as Dictionary)
	var ts: Dictionary = (o.get("target_state") as Dictionary) \
		if o.get("target_state") is Dictionary else (states.get(target, {}) as Dictionary)
	if ss.is_empty() or ts.is_empty():
		return {"ok": false, "reason": "unknown_entity",
			"shooter": shooter, "target": target}
	return combat_ballistics.predict(ss, ts, weapon, o)

# 别名（UI/脚本）
func ballistics_launch(shooter: String, target: String, weapon: String, opts := {}) -> Dictionary:
	return combat_ballistics_launch(shooter, target, weapon, opts)

# ── 舰船目录 / 改装 / 毁伤档案（5D）────────────────────

## entity → 舰级：known_ship/entity_binding → 实体 class_id → TBD。
func entity_class_id(entity_id: String) -> String:
	if entity_id == "":
		return "TBD"
	if ship_catalog != null and bool(ship_catalog.ready):
		var bind: Dictionary = ship_catalog.entity_binding(entity_id)
		if bool(bind.get("ok", false)):
			var bcid := str(bind.get("class_id", ""))
			if bcid != "":
				return bcid
		var known: Dictionary = ship_catalog.known_ship(entity_id)
		if not known.is_empty():
			var kcid := str(known.get("class_id", ""))
			if kcid != "":
				return kcid
		for row in (ship_catalog.ships() as Array):
			if row is Dictionary:
				var r: Dictionary = row
				for f in ["entity_id", "ship_id", "hull_code", "hull", "batch"]:
					if str(r.get(f, "")) == entity_id:
						var cid0 := str(r.get("class_id", ""))
						if cid0 != "":
							return cid0
		var cls: Dictionary = ship_catalog.class_of(entity_id)
		if not cls.is_empty():
			var cid1 := str(cls.get("class_id", ""))
			if cid1 != "":
				return cid1
	# 实体自身 class_id（world 优先；world 未携带时回退 seed）
	var candidates: Array = []
	if world != null and world.has_entity(entity_id):
		candidates.append(world.entity(entity_id))
	for raw in (_seed.get("entities", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == entity_id:
			candidates.append(raw)
	for ent in candidates:
		var direct := str((ent as Dictionary).get("class_id", ""))
		if direct != "":
			return direct
		if (ent as Dictionary).get("flags") is Dictionary:
			var fl := str(((ent as Dictionary)["flags"] as Dictionary).get("class_id", ""))
			if fl != "":
				return fl
		if (ent as Dictionary).get("extra") is Dictionary:
			var ex := str(((ent as Dictionary)["extra"] as Dictionary).get("class_id", ""))
			if ex != "":
				return ex
	return "TBD"

func class_vm(entity_id: String) -> Dictionary:
	var cid: String = entity_class_id(entity_id)
	var out: Dictionary = {"ok": cid != "TBD" and cid != "", "entity_id": entity_id,
		"class_id": cid, "known": cid != "TBD" and cid != "", "truth": false,
		"writes": {"world": false, "ui": false, "v15": false}}
	var cls: Dictionary = {}
	if ship_catalog != null and bool(ship_catalog.ready) and cid != "TBD":
		cls = ship_catalog.class_of(cid)
	if cls.is_empty():
		out["tbd"] = true
		out["reason"] = "unknown_class"
		return out
	for k in cls.keys():
		out[k] = cls[k]
	out["ok"] = true
	out["class_id"] = cid
	out["entity_id"] = entity_id
	out["truth"] = false
	out["source"] = "ship_catalog"
	return out

func ship_catalog_vm() -> Dictionary:
	if ship_catalog != null and bool(ship_catalog.ready):
		return ship_catalog.to_dict()
	return {}

func ship_catalog_summary() -> Dictionary:
	if ship_catalog != null and bool(ship_catalog.ready):
		return ship_catalog.summary()
	return {}

## DamageService 建档时把 ships 字符串/对象补 class_id（旧 damage_l1 显式档案仍优先）。
func _damage_ships_with_class(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item in (raw as Array):
		if item is Dictionary:
			var row: Dictionary = (item as Dictionary).duplicate(true)
			var rid := str(row.get("id", row.get("ship_id", "")))
			if rid != "" and str(row.get("class_id", "")) == "":
				var cid := entity_class_id(rid)
				if cid != "TBD":
					row["class_id"] = cid
			out.append(row)
		else:
			var sid := str(item)
			var row2 := {"id": sid}
			var cid2 := entity_class_id(sid)
			if cid2 != "TBD":
				row2["class_id"] = cid2
			out.append(row2)
	return out

func damage_profile_for(entity_or_class: String) -> Dictionary:
	if damage_profile_service == null or not bool(damage_profile_service.ready):
		return {}
	return damage_profile_service.profile_for(entity_or_class)

func damage_class_of(entity_id: String) -> Dictionary:
	var cid := "TBD"
	var ship_id := ""
	if damage_service != null:
		for sid in (damage_service.ship_ids as Array):
			if str(sid) == entity_id:
				ship_id = str(sid)
				break
		if ship_id == "" and (damage_service.ships as Dictionary).has(entity_id):
			ship_id = entity_id
		if ship_id != "":
			var m = (damage_service.ships as Dictionary)[ship_id]
			if m != null:
				cid = str(m.class_id)
				if cid == "" and m._class_profile is Dictionary:
					cid = str((m._class_profile as Dictionary).get("class_id", ""))
				return {"ok": cid != "", "entity_id": entity_id, "ship_id": ship_id,
					"class_id": cid if cid != "" else "TBD",
					"profile_source": str(m.profile_source), "truth": false}
	if ship_catalog != null and bool(ship_catalog.ready) \
			and entity_class_id(entity_id) == "TBD" and ship_catalog.class_of(entity_id).is_empty():
		return {"ok": false, "entity_id": entity_id, "ship_id": "", "class_id": "TBD",
			"reason": "no_damage_profile", "truth": false}
	var prof: Dictionary = damage_profile_for(entity_id)
	if prof.is_empty() and (ship_catalog == null or entity_class_id(entity_id) == "TBD"):
		return {"ok": false, "entity_id": entity_id, "ship_id": "", "class_id": "TBD",
			"reason": "no_damage_profile", "truth": false}
	if not prof.is_empty() and not bool(prof.get("fallback", false)):
		cid = str(prof.get("class_id", ""))
		if cid != "":
			return {"ok": true, "entity_id": entity_id, "ship_id": "",
				"class_id": cid, "profile_source": "profile", "truth": false}
	return {"ok": false, "entity_id": entity_id, "ship_id": "", "class_id": "TBD",
		"reason": "no_damage_profile", "truth": false}

# ── 改装 API（可选 refit）────────────────────────────────────

func _refit_fail(reason_text: String) -> Dictionary:
	return {"ok": false, "reason": reason_text}

func _publish_refit(kind: String, payload := {}) -> Dictionary:
	if bus == null:
		return {"ok": false, "reason": "no_bus"}
	var ev: Dictionary = _mk_event("refit." + kind, "", payload)
	var pub: Dictionary = bus.publish(ev)
	if not bool(pub.get("ok", false)):
		warnings.append("refit 事件发布失败：" + kind)
		return pub
	_tick_events.append(pub.get("event", {}))
	return pub

func refit_vm() -> Dictionary:
	if refit_service == null:
		return {}
	return refit_service.to_dict()

func refit_slots() -> Dictionary:
	if refit_service == null:
		return {}
	return refit_service.slots()

func refit_options(category := "") -> Array:
	if refit_service == null:
		return []
	return refit_service.options(category)

func refit_quote(module: Variant) -> Dictionary:
	if refit_service == null:
		return _refit_fail("no_refit_service")
	return refit_service.quote(module)

func refit_install(module: Variant, opts := {}) -> Dictionary:
	if refit_service == null:
		return _refit_fail("no_refit_service")
	var res: Dictionary = refit_service.install(module, opts)
	if bool(res.get("ok", false)):
		_publish_refit("install", {"module_id": str(res.get("module_id", "")),
			"planned": bool(res.get("planned", false)), "costs": res.get("costs", {})})
	return res

func refit_remove(module: Variant) -> Dictionary:
	if refit_service == null:
		return _refit_fail("no_refit_service")
	var res: Dictionary = refit_service.remove(module)
	if bool(res.get("ok", false)):
		_publish_refit("remove", {"module_id": str(res.get("module_id", "")),
			"where": str(res.get("where", ""))})
	return res

func refit_commit() -> Dictionary:
	if refit_service == null:
		return _refit_fail("no_refit_service")
	var res: Dictionary = refit_service.commit()
	if bool(res.get("ok", false)):
		_publish_refit("commit", {"committed": res.get("committed", []),
			"costs": res.get("costs", {}), "resources": res.get("resources", {})})
	return res

func refit_tick(days: float) -> Dictionary:
	if refit_service == null:
		return _refit_fail("no_refit_service")
	var res: Dictionary = refit_service.tick(days)
	if bool(res.get("ok", false)):
		_publish_refit("tick", {"days": days, "completed": res.get("completed", [])})
	return res

func refit_stats() -> Dictionary:
	if refit_service == null:
		return {}
	return refit_service.stats()

# ── 舰队编制 / 全舰队改装（5G）──────────────────────────────

func _publish_fleet_event(typ: String, payload := {}) -> Dictionary:
	if bus == null:
		return {"ok": false, "reason": "no_bus"}
	var ev: Dictionary = _mk_event(typ, "", payload)
	var pub: Dictionary = bus.publish(ev)
	if not bool(pub.get("ok", false)):
		warnings.append("fleet 事件发布失败：" + typ)
		return pub
	_tick_events.append(pub.get("event", {}))
	return pub

func fleet_vm() -> Dictionary:
	var out: Dictionary = {"schema": "v17.fleet_session.v1",
		"formation": fleet_formation.to_dict() if fleet_formation != null else null,
		"refit": fleet_refit.summary() if fleet_refit != null else null,
		"summary": fleet_summary(), "truth": false,
		"writes": {"world": false, "track_table": false, "ui": false, "v15": false}}
	return out

func fleet_summary() -> Dictionary:
	return {"schema": "v17.fleet_session.v1",
		"formation_ready": fleet_formation != null and bool(fleet_formation.ready),
		"refit_ready": fleet_refit != null and bool(fleet_refit.ready),
		"formation": fleet_formation.summary() if fleet_formation != null else {},
		"refit": fleet_refit.summary() if fleet_refit != null else {},
		"proposal": true, "truth": false,
		"writes": {"world": false, "track_table": false, "ui": false, "v15": false}}

func fleet_roster() -> Array:
	if fleet_formation == null:
		return []
	return fleet_formation.roster_view()

func fleet_slots() -> Dictionary:
	if fleet_formation == null:
		return {}
	return fleet_formation.slots()

func fleet_assign(ship_id: String, slot: String) -> Dictionary:
	if fleet_formation == null:
		return {"ok": false, "reason": "no_fleet_formation"}
	var res: Dictionary = fleet_formation.assign(ship_id, slot)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet.assign", {"ship_id": ship_id, "slot": slot})
	return res

func fleet_unassign(ship_id: String) -> Dictionary:
	if fleet_formation == null:
		return {"ok": false, "reason": "no_fleet_formation"}
	var res: Dictionary = fleet_formation.unassign(ship_id)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet.unassign", {"ship_id": ship_id})
	return res

func fleet_move(ship_id: String, slot: String) -> Dictionary:
	if fleet_formation == null:
		return {"ok": false, "reason": "no_fleet_formation"}
	var res: Dictionary = fleet_formation.move(ship_id, slot)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet.move", {"ship_id": ship_id, "slot": slot})
	return res

func fleet_validate() -> Dictionary:
	if fleet_formation == null:
		return {"ok": false, "reason": "no_fleet_formation"}
	var res: Dictionary = fleet_formation.validate()
	_publish_fleet_event("fleet.validated", {"ok": bool(res.get("ok", false))})
	return res

func fleet_stats() -> Dictionary:
	if fleet_formation == null:
		return {}
	return fleet_formation.stats()

func fleet_refit_vm() -> Dictionary:
	if fleet_refit == null:
		return {}
	return fleet_refit.to_dict()

func fleet_refit_ships() -> Array:
	if fleet_refit == null:
		return []
	return fleet_refit.ships_list()

func fleet_select_ship(ship_id: String) -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	var res: Dictionary = fleet_refit.select_ship(ship_id)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet_refit.select_ship", {"ship_id": ship_id})
	return res

func fleet_options(ship_id := "", category := "") -> Array:
	if fleet_refit == null:
		return []
	return fleet_refit.options(ship_id, category)

func fleet_quote(a: Variant = "", b: Variant = "") -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	return fleet_refit.quote(a, b)

func fleet_install(a: Variant = "", b: Variant = "", opts := {}) -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	var res: Dictionary = fleet_refit.install(a, b, opts)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet_refit.install", {"ship_id": str(fleet_refit.selected()),
			"module_id": str(res.get("module_id", "")), "planned": bool(res.get("planned", false))})
	return res

func fleet_remove(a: Variant = "", b: Variant = "") -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	var res: Dictionary = fleet_refit.remove(a, b)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet_refit.remove", {"ship_id": str(fleet_refit.selected()),
			"module_id": str(res.get("module_id", ""))})
	return res

func fleet_commit(ship_id := "") -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	var res: Dictionary = fleet_refit.commit(ship_id)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet_refit.commit", {"ship_id": str(ship_id),
			"committed": res.get("committed", []), "costs": res.get("costs", {})})
	return res

func fleet_refit_tick(days: float) -> Dictionary:
	if fleet_refit == null:
		return {"ok": false, "reason": "no_fleet_refit"}
	var res: Dictionary = fleet_refit.tick(days)
	if bool(res.get("ok", false)):
		_publish_fleet_event("fleet_refit.tick", {"days": days,
			"completed": res.get("completed", [])})
	return res

func fleet_refit_stats(ship_id := "") -> Dictionary:
	if fleet_refit == null:
		return {}
	return fleet_refit.stats(ship_id)

func fleet_refit_state(ship_id: String) -> Dictionary:
	if fleet_refit == null:
		return {}
	return fleet_refit.refit_state(ship_id)

# 通用别名（与 task API 对齐；tick 与 session 主 tick 冲突，用 fleet_refit_tick）
func select_ship(ship_id: String) -> Dictionary:
	return fleet_select_ship(ship_id)

func options(ship_id := "", category := "") -> Array:
	return fleet_options(ship_id, category)

func quote(a: Variant = "", b: Variant = "") -> Dictionary:
	return fleet_quote(a, b)

func install(a: Variant = "", b: Variant = "", opts := {}) -> Dictionary:
	return fleet_install(a, b, opts)

func remove(a: Variant = "", b: Variant = "") -> Dictionary:
	return fleet_remove(a, b)

func commit(ship_id := "") -> Dictionary:
	return fleet_commit(ship_id)

func stats(ship_id := "") -> Dictionary:
	return fleet_refit_stats(ship_id)

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
		# A0-T1：位置副本必须与 physics 同一时刻（仅同坐标语义时校验；帧转换
		# 会话显式不同步，不在本不变量范围内）。
		if _world_sync_mode == WORLD_SYNC_MODE_TICK and not _world_copy_in_sync():
			v.append("world 位置副本与 physics 不一致")
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
	if identification_service != null:
		if not bool(identification_service.ready):
			v.append("identification_service 未就绪")
		if absf(float(identification_service.t) - now_s()) > 1.0e-6:
			v.append("identification 时间与会话不一致：%s != %s" % [
				str(identification_service.t), str(now_s())])
		if not bool(identification_service.check_contracts().get("ok", false)):
			v.append("identification 不变量失败")
	if legal_status_service != null:
		if not bool(legal_status_service.ready):
			v.append("legal_status_service 未就绪")
		if not bool(legal_status_service.check_contracts().get("ok", false)):
			v.append("legal 不变量失败：" + str(
				legal_status_service.check_contracts().get("violations", [])))
	if traffic_control != null:
		if not bool(traffic_control.ready):
			v.append("traffic_control 未就绪")
		if absf(float(traffic_control.t) - now_s()) > 1.0e-6:
			v.append("traffic 时间与会话不一致：%s != %s" % [
				str(traffic_control.t), str(now_s())])
		var tw = (traffic_control.vm().get("writes", {}) as Dictionary) \
			if traffic_control.vm().get("writes") is Dictionary else {}
		if bool(tw.get("world", false)) or bool(tw.get("track_table", false)) \
				or bool(tw.get("ui", false)) or bool(tw.get("v15", false)):
			v.append("traffic 声明写 world/track_table/ui/v15")
	if combat_ballistics != null:
		if not bool(combat_ballistics.ready):
			v.append("combat_ballistics 未就绪")
		if absf(float(combat_ballistics.t) - now_s()) > 1.0e-6:
			v.append("ballistics 时间与会话不一致：%s != %s" % [
				str(combat_ballistics.t), str(now_s())])
		var bw = (combat_ballistics.vm().get("writes", {}) as Dictionary) \
			if combat_ballistics.vm().get("writes") is Dictionary else {}
		if bool(bw.get("world", false)) or bool(bw.get("track_table", false)) \
				or bool(bw.get("ui", false)) or bool(bw.get("v15", false)):
			v.append("ballistics 声明写 world/track_table/ui/v15")
	if ship_catalog != null:
		if not bool(ship_catalog.ready):
			v.append("ship_catalog 未就绪")
		var cat_contracts: Dictionary = ship_catalog.check_contracts()
		if not bool(cat_contracts.get("ok", false)):
			v.append("ship_catalog 不变量失败：" + str(cat_contracts.get("violations", [])))
	if damage_profile_service != null:
		if not bool(damage_profile_service.ready):
			v.append("damage_profile_service 未就绪")
	if refit_service != null:
		if not bool(refit_service.ready):
			v.append("refit_service 未就绪")
		var rc: Dictionary = refit_service.check_contracts()
		if not bool(rc.get("ok", false)):
			v.append("refit 不变量失败：" + str(rc.get("violations", [])))
	if fleet_refit != null:
		if not bool(fleet_refit.ready):
			v.append("fleet_refit 未就绪")
		var frc: Dictionary = fleet_refit.check_contracts()
		if not bool(frc.get("ok", false)):
			v.append("fleet_refit 不变量失败：" + str(frc.get("violations", [])))
	if fleet_formation != null:
		if not bool(fleet_formation.ready):
			v.append("fleet_formation 未就绪")
		var ffc: Dictionary = fleet_formation.check_contracts()
		if not bool(ffc.get("ok", false)):
			v.append("fleet_formation 不变量失败：" + str(ffc.get("violations", [])))
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
		# A-01：合成视图必须**说明静态字段来源**。world/snapshot 实体只承载运动投影，
		# 静态特征（side/batch/rcs/radius/has_pd）的唯一权威在此块中按稳定 ID 提供。
		"entity_catalog": {
			"schema": "v17.entity_catalog.v1",
			"source": "entity_catalog",
			"authoritative": true,
			"entities": entity_catalog.all_entities() if entity_catalog != null else [],
		},
		"track_table": track_table.snapshot() if track_table != null else null,
		"story": story_state.snapshot() if story_state != null else null,
		"sensor": sensor_service.vm() if sensor_service != null else null,
		"port": port_service.vm() if port_service != null else null,
		"combat": combat_service.vm() if combat_service != null else null,
		"damage": damage_service.vm() if damage_service != null else null,
		"physics": physics_world_service.snapshot() if physics_world_service != null else null,
		"physics_frame": physics_frame_meta(),
		"signal": signal_service.vm() if signal_service != null else null,
		"ew": ew_service.vm() if ew_service != null else null,
		"facilities": facility_registry.summary() if facility_registry != null else null,
		"transponder": transponder_service.vm() if transponder_service != null else null,
		"identification": identification_service.vm() if identification_service != null else null,
		"legal_status": legal_status_service.vm() if legal_status_service != null else null,
		"traffic_control": traffic_control.vm() if traffic_control != null else null,
		"combat_ballistics": combat_ballistics.vm() if combat_ballistics != null else null,
		"ship_catalog": {"schema": "v17.ship_catalog.v1",
			"summary": ship_catalog.summary()} if ship_catalog != null else null,
		"catalog": {"schema": "v17.ship_catalog.v1",
			"summary": ship_catalog.summary()} if ship_catalog != null else null,
		"damage_profile": damage_profile_service.summary() \
			if damage_profile_service != null else null,
		"refit": refit_service.save_state() if refit_service != null else null,
		"fleet_formation": fleet_formation.save_state() if fleet_formation != null else null,
		"fleet_refit": fleet_refit.save_state() if fleet_refit != null else null,
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
		# A-05：传感器运行态（控制值/时钟/通道/分配器/去重/后端子状态）。
		# 静态 mounts/targets 与 provider 对象不入档（读档后从原权威重建/重新注入）。
		"sensor_service": sensor_service.export_state() if sensor_service != null else null,
		"signal_service": signal_service.save_state() if signal_service != null else "",
		# JC-A01/R4：Comms 在途队列/ETA/链路状态（恢复后不得把丢失当送达）
		"comms": comms.export_state() if comms != null else null,
		"ew_service": ew_service.save_state() if ew_service != null else "",
		"facility_registry": facility_registry.to_dict() if facility_registry != null else null,
		"transponder_service": transponder_service.save_state() if transponder_service != null else "",
		"identification_service": identification_service.save_state() if identification_service != null else "",
		# JC-A02：每 owner 计算器状态（不含本舰 owner，其状态在 identification_service 段）+ 待处理查询
		"identity_owners": _identity_owners_export(),
		"identity_pending_queries": JSON.parse_string(JSON.stringify(_identity_pending_queries)),
		"identity_query_queue": JSON.parse_string(JSON.stringify(_identity_query_queue)),
		"identity_seen_events": JSON.parse_string(JSON.stringify(_identity_seen_events)),
		# JC-A03：EW 观测采样/延迟队列/投递审计/候选/质量历史随档
		"ew_observation_samples": JSON.parse_string(JSON.stringify(
			_ew_samples.slice(maxi(0, (_ew_samples as Array).size() - 200),
				(_ew_samples as Array).size()))),
		"ew_observation_queue": JSON.parse_string(JSON.stringify(_ew_obs_queue)),
		"ew_delivered_observations": JSON.parse_string(JSON.stringify(
			_ew_delivered.slice(maxi(0, (_ew_delivered as Array).size() - 200),
				(_ew_delivered as Array).size()))),
		"ew_candidates": JSON.parse_string(JSON.stringify(
			_ew_candidates.slice(maxi(0, (_ew_candidates as Array).size() - 200),
				(_ew_candidates as Array).size()))),
		"ew_observation_seq": _ew_obs_seq,
		"ew_quality_history": JSON.parse_string(JSON.stringify(_ew_quality_history)),
		"ew_combat_quality": JSON.parse_string(JSON.stringify(_ew_combat_quality)),
		"ew_rejected_deliveries": JSON.parse_string(JSON.stringify(
			(_ew_rejected_deliveries as Array).slice(maxi(0,
				(_ew_rejected_deliveries as Array).size() - 100),
				(_ew_rejected_deliveries as Array).size()))),
		"legal_status_service": legal_status_service.save_state() if legal_status_service != null else "",
		"traffic_control": traffic_control.save_state() if traffic_control != null else "",
		"combat_ballistics": combat_ballistics.save_state() if combat_ballistics != null else "",
		"ship_catalog": {"schema": "v17.ship_catalog.v1",
			"summary": ship_catalog.summary()} if ship_catalog != null else null,
		"catalog": {"schema": "v17.ship_catalog.v1",
			"summary": ship_catalog.summary()} if ship_catalog != null else null,
		"damage_profile": damage_profile_service.summary() \
			if damage_profile_service != null else null,
		"refit": refit_service.save_state() if refit_service != null else null,
		"fleet_formation": fleet_formation.save_state() if fleet_formation != null else null,
		"fleet_refit": fleet_refit.save_state() if fleet_refit != null else null,
		"combat_time_cap": {"active": _combat_scale_cap_active,
			"restore_to": _scale_before_combat, "cap": COMBAT_SCALE_CAP},
		# A-03：事件总线恢复使用 EventBus 的版本化导出（含完整去重集合与自动 ID 分配器），
		# 不再只存 seq/events；Session 不直接重建 EventBus 私有字段。
		"bus": bus.export_state() if bus != null else null,
		# JC-A01：授权/分方情报（owner 航迹 + 授权 context + 审计）
		"authority_intel": authority_intel.export_state() \
			if (_authority_enabled and authority_intel != null) else null,
		# JC-A01：在途共享随档保存（恢复后按到达时刻继续）
		"pending_intel_shares": _pending_intel_shares.duplicate(true),
		# R4：在途投递登记也必须随档，否则恢复后到达回调不会触发
		"standalone": JSON.parse_string(JSON.stringify(_standalone)),
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
	# A-04：`log` 是旧档可恢复性的唯一操作证据；缺失或类型错误必须显式拒绝，
	# 不能默认成空日志后「静默开一场新模拟」。
	if not data.has("log"):
		errors.append("load_state: 缺少 log 段（无法重建可恢复历史）")
		return {"ok": false, "reason": "missing_log"}
	var log = data.get("log", [])
	if not (seed is Dictionary) or not (log is Array):
		errors.append("load_state: seed/log 类型无效")
		return {"ok": false, "reason": "invalid_payload"}
	boot(seed)
	if not ready:
		return {"ok": false, "reason": "boot_failed", "errors": errors.duplicate()}
	_replaying = true
	_comms_restore = []
	# JC-A04：重放从头开始确定抽样，seed 取存档 seed（默认 0），保证同档同序同 draw。
	if comms != null and seed is Dictionary:
		comms.reset_ew_rng(int((seed as Dictionary).get("comms_ew_seed", 0)))
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
	# JC-A01/R4：Comms 在途状态必须在 replay 之后按存档权威恢复，
	# 否则「队列项消失」会被 _reconcile_standalone 误判为已送达。
	if comms != null and data.has("comms"):
		var cr: Dictionary = comms.load_state(data.get("comms"))
		if not bool(cr.get("ok", false)):
			replay_errors.append("comms 状态恢复失败：" + str(cr.get("reason", ""))
				+ " " + JSON.stringify(cr.get("errors", [])))
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
	var saved_ew = data.get("ew_service", null)
	if saved_ew != null and String(saved_ew) != "":
		if ew_service == null:
			replay_errors.append("存档含 ew_service 快照但 boot 未启用 ew_service")
		else:
			var ewr: Dictionary = ew_service.load_state(saved_ew)
			if not bool(ewr.get("ok", false)):
				replay_errors.append("ew_service 快照恢复失败：" + str(ewr.get("reason", "")))
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
	var saved_idf = data.get("identification_service", null)
	if saved_idf != null and String(saved_idf) != "":
		if identification_service == null:
			replay_errors.append("存档含 identification_service 快照但 boot 未启用 identification_service")
		else:
			var idr: Dictionary = identification_service.load_state(saved_idf)
			if not bool(idr.get("ok", false)):
				replay_errors.append("identification_service 快照恢复失败：" + str(idr.get("errors", [])))
	# JC-A02：owner 身份管道恢复（旧档只有单实例 → legacy_single_owner 迁移）
	_identity_restore_identity(data)
	# JC-A03：EW 观测采样/延迟队列/投递/候选/质量状态恢复
	var ewr: Dictionary = _ew_restore_state(data)
	if not bool(ewr.get("ok", false)):
		replay_errors.append("EW 状态恢复失败：" + String(ewr.get("reason", ""))
			+ " field=" + String(ewr.get("field", "")))
	var saved_legal = data.get("legal_status_service", null)
	if saved_legal != null and String(saved_legal) != "":
		if legal_status_service == null:
			replay_errors.append("存档含 legal_status_service 快照但 boot 未启用 legal_status")
		else:
			var lr: Dictionary = legal_status_service.load_state(saved_legal)
			if not bool(lr.get("ok", false)):
				replay_errors.append("legal_status_service 快照恢复失败：" + str(lr.get("errors", [])))
	var saved_traffic = data.get("traffic_control", null)
	if saved_traffic != null and String(saved_traffic) != "":
		if traffic_control == null:
			replay_errors.append("存档含 traffic_control 快照但 boot 未启用 traffic_control")
		else:
			var trc: Dictionary = traffic_control.load_state(saved_traffic)
			if not bool(trc.get("ok", false)):
				replay_errors.append("traffic_control 快照恢复失败：" + str(trc.get("reason", trc.get("errors", []))))
	var saved_ball = data.get("combat_ballistics", null)
	if saved_ball != null and String(saved_ball) != "":
		if combat_ballistics == null:
			replay_errors.append("存档含 combat_ballistics 快照但 boot 未启用 combat_ballistics")
		else:
			var br: Dictionary = combat_ballistics.load_state(saved_ball)
			if not bool(br.get("ok", false)):
				replay_errors.append("combat_ballistics 快照恢复失败：" + str(br.get("reason", br.get("errors", []))))
	# 5D：catalog/refit 快照（旧档缺字段兼容）
	var saved_cat = data.get("ship_catalog", null)
	if saved_cat is Dictionary and ship_catalog != null:
		var saved_sum: Dictionary = (saved_cat as Dictionary).get("summary", {}) \
			if (saved_cat as Dictionary).get("summary") is Dictionary else {}
		var now_sum: Dictionary = ship_catalog.summary()
		if saved_sum.has("classes") and int(saved_sum.get("classes", 0)) != int(now_sum.get("classes", 0)):
			warnings.append("存档 catalog 类型数 %s 与当前 %s 不一致" % [
				str(saved_sum.get("classes")), str(now_sum.get("classes"))])
	var saved_refit = data.get("refit", null)
	if saved_refit is Dictionary:
		if refit_service == null:
			replay_errors.append("存档含 refit 快照但 boot 未启用 refit")
		else:
			var rr2: Dictionary = refit_service.load_state(saved_refit)
			if not bool(rr2.get("ok", false)):
				replay_errors.append("refit 快照恢复失败：" + str(rr2.get("reason", rr2.get("errors", []))))
	var saved_ff = data.get("fleet_formation", null)
	if saved_ff is Dictionary:
		if fleet_formation == null:
			replay_errors.append("存档含 fleet_formation 快照但 boot 未启用 fleet_formation")
		else:
			var ffr: Dictionary = fleet_formation.load_state(saved_ff)
			if not bool(ffr.get("ok", false)):
				replay_errors.append("fleet_formation 快照恢复失败：" + str(ffr.get("reason", ffr.get("errors", []))))
	var saved_fr = data.get("fleet_refit", null)
	if saved_fr is Dictionary:
		if fleet_refit == null:
			replay_errors.append("存档含 fleet_refit 快照但 boot 未启用 fleet_refit")
		else:
			var frr: Dictionary = fleet_refit.load_state(saved_fr)
			if not bool(frr.get("ok", false)):
				replay_errors.append("fleet_refit 快照恢复失败：" + str(frr.get("reason", frr.get("errors", []))))
	# 交战时间膨胀状态（旧存档无此字段 → 视为未封顶）
	var saved_cap = data.get("combat_time_cap", null)
	if saved_cap is Dictionary:
		_combat_scale_cap_active = bool((saved_cap as Dictionary).get("active", false))
		_scale_before_combat = float((saved_cap as Dictionary).get("restore_to", 1.0))
	else:
		_combat_scale_cap_active = false
		_scale_before_combat = 1.0
	# A-03 / A-04：恢复事件总线历史 —— 通过 EventBus 的版本化导入接口（导入 ≠ 发布，不派发历史）。
	# 迁移必须采用「重放已用集合 ∪ 可见历史 ID」，**不是**用尾部历史替换集合：
	# 早期显式 ID 可能已被 1000 条环形缓冲裁掉，但仍存在于 seed+log 重放结果中。
	var replay_seen: Array = []
	for k0 in bus._seen_ids.keys():
		replay_seen.append(String(k0))
	var replay_seq := int(bus.seq)
	var replay_id_seq := int(bus._id_seq)
	var saved_bus = data.get("bus", null)
	_legacy_migration = {
		"schema": "v17.legacy_migration.v1",
		"applied": false,
		"shape": "new",
		"save_schema": String(data.get("schema", "")),
		"version_adopted": 0,
		"replay_seen_ids": replay_seen.size(),
		"replay_seq": replay_seq,
		"replay_id_seq": replay_id_seq,
		"recovered": {},
		"partial": [],
		"unrecoverable": [],
	}
	if not (saved_bus is Dictionary):
		# 形态 A：无 bus 段 → 保留重放可恢复的 seq / allocator / 已用 ID，只记录迁移版本。
		_legacy_migration["applied"] = true
		_legacy_migration["shape"] = "no_bus_section"
		_legacy_migration["version_adopted"] = 1
		_legacy_migration["recovered"] = {
			"seq": replay_seq, "id_seq": replay_id_seq,
			"seen_ids": replay_seen.size(), "events": bus.events.size(),
			"source": "seed+log replay",
		}
		_legacy_migration["partial"].append(
			"no bus section: visible history rebuilt from seed+log replay only")
		warnings.append("旧档无 bus 段：按 seed+log 重放恢复（迁移版本 1）")
	else:
		var sb2: Dictionary = saved_bus
		if not sb2.has("schema"):
			# 形态 B：旧 bus（只有 seq/events）→ 合并重放已用集合 ∪ 可见历史 ID，高水位不倒退。
			_legacy_migration["applied"] = true
			_legacy_migration["shape"] = "legacy_bus_seq_events"
			_legacy_migration["version_adopted"] = 2
			# 旧 bus 的 seq/events 也必须过整数契约与类型校验（不能用 int() 静默截断）。
			var legacy_seq_ok := true
			var raw_legacy_seq = sb2.get("seq", 0)
			if not (raw_legacy_seq is int or raw_legacy_seq is float):
				legacy_seq_ok = false
				replay_errors.append("bus legacy: seq 类型无效（%s）" % type_string(
					typeof(raw_legacy_seq)))
			elif is_nan(float(raw_legacy_seq)) or is_inf(float(raw_legacy_seq)):
				legacy_seq_ok = false
				replay_errors.append("bus legacy: seq 非有限")
			elif absf(float(raw_legacy_seq) - roundf(float(raw_legacy_seq))) > 0.0:
				legacy_seq_ok = false
				replay_errors.append("bus legacy: seq 不是整数（%s）" % str(raw_legacy_seq))
			elif float(raw_legacy_seq) < 0.0 or float(raw_legacy_seq) > 9007199254740991.0:
				legacy_seq_ok = false
				replay_errors.append("bus legacy: seq 越界（%s）" % str(raw_legacy_seq))
			var raw_legacy_events = sb2.get("events", null)
			if not (raw_legacy_events is Array):
				legacy_seq_ok = false
				replay_errors.append("bus legacy: events 必须是数组（实际 %s）" % type_string(
					typeof(raw_legacy_events)))
			var legacy_saved_seq := maxi(int(roundf(float(raw_legacy_seq)))
				if legacy_seq_ok else 0, 0)
			var merged_seen: Array = replay_seen.duplicate()
			var visible_ids: Array = []
			if raw_legacy_events is Array:
				for raw_le in (raw_legacy_events as Array):
					if raw_le is Dictionary:
						var lid := String((raw_le as Dictionary).get("id", ""))
						if lid != "" and not (lid in merged_seen):
							merged_seen.append(lid)
						if lid != "":
							visible_ids.append(lid)
			var legacy_state: Dictionary = {
				"seq": maxi(legacy_saved_seq, replay_seq),
				"id_seq": replay_id_seq,
				"events": raw_legacy_events if raw_legacy_events is Array else [],
				"seen_ids": merged_seen,
			}
			var lr_bus: Dictionary = {"ok": false, "errors": []}
			if legacy_seq_ok:
				lr_bus = bus.import_state(legacy_state)
			else:
				lr_bus = {"ok": false,
					"errors": ["legacy bus 段校验失败，未导入（见上方具体原因）"]}
			if not bool(lr_bus.get("ok", false)):
				replay_errors.append("bus legacy 迁移失败：" + str(lr_bus.get("errors", [])))
			else:
				_legacy_migration["recovered"] = {
					"seq": int(bus.seq), "id_seq": int(bus._id_seq),
					"seen_ids": bus._seen_ids.size(),
					"seen_ids_from_replay": replay_seen.size(),
					"seen_ids_from_visible_history": visible_ids.size(),
					"events": bus.events.size(),
					"source": "replay used-ids UNION visible history ids",
				}
				_legacy_migration["partial"].append(
					"legacy bus: allocator restored from replay; none of the ids " +
					"evicted before save can be recovered beyond replay evidence")
				warnings.append("旧档 bus 按「重放已用集合 ∪ 可见历史」迁移（迁移版本 2）")
		else:
			var br: Dictionary = bus.import_state(sb2)
			if not bool(br.get("ok", false)):
				replay_errors.append("bus 状态导入失败：" + str(br.get("errors", [])))
			else:
				_legacy_migration["version_adopted"] = 2
				_legacy_migration["recovered"] = {
					"seq": int(bus.seq), "id_seq": int(bus._id_seq),
					"seen_ids": bus._seen_ids.size(), "events": bus.events.size(),
					"source": "v2 bus state (full dedup set)",
				}
	# 旧档不可恢复的状态：显式声明（A-05 承接 SensorService 运行态）。
	if data.get("sensor_service", null) == null:
		_legacy_migration["unrecoverable"].append(
			"sensor_service runtime state (EMCON/radar/channels): absent from this save; " +
			"restored from seed defaults — DS-A-05 scope, NOT a lossless restore")
	if data.get("entity_catalog", null) == null:
		_legacy_migration["unrecoverable"].append(
			"entity_catalog additions: rebuilt from the old seed by stable id "
			+ "(fields unknown to the seed stay seed-default with source=seed)")
	_replaying = false
	_log = (log as Array).duplicate(true)
	if track_table != null:
		_last_track_t = float(track_table.t)
	if story_state != null:
		_last_story_revision = int(story_state.revision)
	_last_bus_routed_index = bus.events.size()
	_routed_seqs = {}
	_last_time_s = now_s()
	# A0-T1：replay 只重放业务操作（physics 不参与 replay），因此读档后必须用恢复的
	# physics 快照重新对齐 world 位置副本；否则 snapshot 仍是 seed 旧位置。
	_world_sync_mode = _resolve_world_sync_mode()
	var world_sync: Dictionary = world_physics_sync("load")
	# A-05：SensorService 运行态恢复。顺序：world/physics 同步 → 恢复运行态 →
	# 重绑定 physics geometry provider → 之后才允许产生新的传感器输出。
	# 不把已恢复的证据/观测重放进 TrackTable（历史数组不导入）。
	var saved_sensor = data.get("sensor_service", null)
	# R8/G0-2：传感器恢复模式/原因必须透传到公共 load 结果与恢复报告，
	# 让调用者能区分「完整恢复」与「可接受的旧档部分迁移」。
	var sr_mode := "full"
	var sr_partial: Array = []
	if saved_sensor != null and sensor_service != null:
		if not (saved_sensor is Dictionary):
			replay_errors.append("sensor_service 运行态段必须是对象")
		else:
			var sr: Dictionary = sensor_service.import_state(saved_sensor)
			if not bool(sr.get("ok", false)):
				replay_errors.append("sensor_service 运行态恢复失败：" + str(
					sr.get("errors", [])))
			else:
				sr_mode = String(sr.get("restore_mode", "full"))
				sr_partial = (sr.get("partial_reasons", []) as Array).duplicate()
			# 恢复结果只进 _sensor_restore_report（不写 warnings，
			# 否则会改变 snapshot() 的可见状态，破坏 save→load 的规范化等价）。
	# 重绑定几何 provider（provider 对象不入 JSON；按当前 session 重新注入并复核同刻）。
	var rebound: Dictionary = _bind_sensor_geometry(true)
	var geo_st: Dictionary = sensor_service.geometry_status() if sensor_service != null else {}
	var sens_time_ok := true
	if sensor_service != null:
		sens_time_ok = absf(float(geo_st.get("t", -1.0)) - now_s()) <= 1.0e-6
		if not sens_time_ok:
			replay_errors.append("sensor geometry 与 session 不同刻（%.9f vs %.9f）" % [
				float(geo_st.get("t", -1.0)), now_s()])
	# JC-A01：恢复授权/分方情报（owner 航迹 + 授权 context + 审计）。
	# R5：真正旧档（缺段）→ 只迁入本舰 owner；已存在但畸形的新段 → 明确失败。
	var ai_state = data.get("authority_intel", null)
	var ai_res: Dictionary = {"ok": true, "restore_mode": "legacy_own_ship_only"}
	if _authority_enabled and authority_intel != null:
		if data.has("authority_intel") and not (ai_state is Dictionary):
			# R5/C：字段**存在**但为 null/非对象 = 坏新段，必须明确失败；
			# 只有字段完全缺失才是真正旧档（迁移路径）。
			ai_res = {"ok": false, "reason": "invalid_authority_intel_section",
				"detail": "authority_intel 必须是对象（收到 %s）" % (
					"null" if ai_state == null else type_string(typeof(ai_state)))}
			replay_errors.append("authority_intel 段畸形：" + String(
				ai_res.get("detail", "")))
		else:
			ai_res = authority_intel.import_state(ai_state)
			if not bool(ai_res.get("ok", false)):
				replay_errors.append("authority_intel 恢复失败：" + str(
					ai_res.get("reason", "")))
			elif String(ai_res.get("restore_mode", "")) == "legacy_own_ship_only":
				# 真正旧来源：把旧 TrackTable 航迹迁入**本舰 owner**（不复制给盟军）
				var legacy_tracks: Array = []
				if track_table != null and track_table.has_method("all_tracks"):
					legacy_tracks = track_table.all_tracks()
				elif track_table != null and track_table.has_method("snapshot"):
					var snap_l: Dictionary = track_table.snapshot()
					if snap_l.get("tracks") is Array:
						legacy_tracks = snap_l.get("tracks")
				var own_owner_id := String(
					(authority_intel.domains.get("player", {}) as Dictionary)
						.get("intel_owner_id", "player_intel"))
				var mig: Dictionary = authority_intel.migrate_legacy_tracks(
					own_owner_id, legacy_tracks)
				ai_res["legacy_migrated"] = int(mig.get("migrated", 0))
				ai_res["legacy_owner"] = own_owner_id
	_authority_restore_mode = String(ai_res.get("restore_mode", "full"))
	_authority_restore_reasons = []
	if not bool(ai_res.get("ok", true)):
		_authority_restore_mode = "failed"
		_authority_restore_reasons.append(String(ai_res.get("reason", "")))
	elif int(ai_res.get("legacy_migrated", 0)) > 0:
		_authority_restore_reasons.append("legacy_tracks_migrated:%d" % int(
			ai_res.get("legacy_migrated", 0)))
	# 在途共享：恢复后继续按到达时刻融合
	_pending_intel_shares = {}
	var raw_pending = data.get("pending_intel_shares", null)
	if raw_pending is Dictionary:
		for pk in (raw_pending as Dictionary).keys():
			var pv = (raw_pending as Dictionary)[pk]
			if pv is Dictionary:
				_pending_intel_shares[String(pk)] = (pv as Dictionary).duplicate(true)
	# R4：恢复在途投递登记，使到达回调在继续 tick 时正常触发
	_standalone = {}
	var raw_standalone = data.get("standalone", null)
	if raw_standalone is Dictionary:
		for sk in (raw_standalone as Dictionary).keys():
			var sv = (raw_standalone as Dictionary)[sk]
			if sv is Dictionary:
				_standalone[String(sk)] = (sv as Dictionary).duplicate(true)
	_sensor_restore_report = {
		"schema": "v17.sensor_restore.v2",
		"saved": saved_sensor is Dictionary,
		"rebind": rebound,
		"geometry_source": String(geo_st.get("source", "")),
		"geometry_frame": String(geo_st.get("frame", "")),
		"time_ok": sens_time_ok,
		# R8/G0-2：完整恢复 vs 可接受的旧档部分迁移（含不可重建项原因）
		"restore_mode": sr_mode,
		"partial_reasons": sr_partial,
		"is_partial": sr_mode == "partial",
	}
	ready = replay_errors.is_empty() and errors.is_empty()
	return {"ok": ready, "errors": replay_errors, "result_errors": errors.duplicate(),
		"world_sync": world_sync, "sensor_restore": _sensor_restore_report.duplicate(true),
		"sensor_restore_mode": sr_mode, "sensor_partial_reasons": sr_partial,
		# R5：授权/情报恢复模式与原因公开可读
		"authority_restore_mode": _authority_restore_mode,
		"authority_restore_reasons": _authority_restore_reasons.duplicate(),
		"identity_restore_mode": _identity_restore_mode,
		"ew_restore_mode": _ew_restore_mode,
		"ew_restore_missing": _ew_restore_missing.duplicate(),
		"pending_intel_shares": _pending_intel_shares.size()}


## R5：授权/情报恢复报告（公开披露，不污染规范化 snapshot）。
func authority_restore_report() -> Dictionary:
	return {"schema": "v17.authority_restore.v1",
		"restore_mode": _authority_restore_mode,
		"reasons": _authority_restore_reasons.duplicate(),
		"pending_shares": _pending_intel_shares.size()}

# ── A-06：通信重放核对 ─────────────────────────────────────────
## 重放一次 send_comms，并与操作日志里记录的版本化 outcome 逐项核对：
##   * 原始失败（ok=false，如 no_route）→ 重放必须得到**同一失败**，不算恢复错误；
##   * 原始成功但重放失败，或原因/消息 ID/路径/延迟不一致 → 明确 `comms_replay_diverged`；
##   * 旧日志没有 outcome → 按 A-04 版本规则显式标 `legacy_unverified`，不静默忽略。
func _replay_send_comms(op: Dictionary) -> Dictionary:
	var from_id := String(op.get("from_id", ""))
	var to_id := String(op.get("to_id", ""))
	var mode := String(op.get("mode", "LD"))
	var text_key := String(op.get("text_key", "COMMS_SENT"))
	var payload = op.get("payload", {})
	var opts = op.get("opts", {})
	# JC-A04：v1 outcome 是 EW 接线前的原始结果；重放须同样忽略 EW（迁移语义），
	# 否则旧档会被新 EW 误解成 divergence。v2 才按冻结 EW 采样重放比较。
	var early_out = op.get("outcome", null)
	var legacy_v1 := false
	if early_out is Dictionary:
		var eo: Dictionary = early_out
		var ever = eo.get("version", null)
		if String(eo.get("schema", "")) == COMMS_OUTCOME_SCHEMA_V1 \
				and (ever is int or ever is float) \
				and int(roundf(float(ever))) == COMMS_OUTCOME_VERSION_LEGACY:
			legacy_v1 = true
	var replay_opts: Dictionary = (opts as Dictionary).duplicate(true) \
		if opts is Dictionary else {}
	if legacy_v1:
		replay_opts["ignore_ew"] = true
	var res: Dictionary = send_comms(from_id, to_id, mode, text_key,
		payload if payload is Dictionary else {}, replay_opts)
	var row: Dictionary = {
		"from": from_id, "to": to_id, "mode": mode, "text_key": text_key,
		"replay_ok": bool(res.get("ok", false)),
		"replay_reason": String(res.get("reason", "")),
		"replay_delivery_id": String(res.get("delivery_id", "")),
		"replay_latency_s": float(res.get("latency_s", 0.0)),
		"replay_path": (res.get("path", []) as Array).duplicate() \
			if res.get("path") is Array else [],
	}
	var rec_outcome = op.get("outcome", null)
	# R04：**outcome 存在即必须合法**。字段存在但 schema/version/类型错误属于
	# 损坏或不支持，必须明确拒绝；只有「确实没有 outcome 字段」的旧操作才可标
	# legacy_unverified（此前 version=999 会被当成旧档而 load 成功）。
	if op.has("outcome"):
		var oc_problems: Array = []
		if not (rec_outcome is Dictionary):
			oc_problems.append("outcome must be an object")
		else:
			var oc: Dictionary = rec_outcome
			var oc_schema := String(oc.get("schema", ""))
			var oc_ver = oc.get("version", null)
			var oc_ver_int := -1
			if oc_ver is int or oc_ver is float:
				if is_finite(float(oc_ver)) \
						and absf(float(oc_ver) - roundf(float(oc_ver))) <= 0.0:
					oc_ver_int = int(roundf(float(oc_ver)))
			var oc_ok_v2 := oc_schema == COMMS_OUTCOME_SCHEMA \
				and oc_ver_int == COMMS_OUTCOME_VERSION
			var oc_ok_v1 := oc_schema == COMMS_OUTCOME_SCHEMA_V1 \
				and oc_ver_int == COMMS_OUTCOME_VERSION_LEGACY
			if not oc_ok_v2 and not oc_ok_v1:
				oc_problems.append("outcome.schema/version unsupported: "
					+ oc_schema + "@" + str(oc_ver))
			if oc_ok_v2:
				var ewv = oc.get("ew", null)
				if not (ewv is Dictionary):
					oc_problems.append("outcome.ew must be an object for v2")
				else:
					var ewdd: Dictionary = ewv
					for ef in ["jam_severity", "latency_add_s", "failure_chance", "draw"]:
						var evn = ewdd.get(ef, null)
						if not (evn is int or evn is float) or not is_finite(float(evn)):
							oc_problems.append("outcome.ew.%s must be a finite number" % ef)
					if not (ewdd.get("will_fail", null) is bool):
						oc_problems.append("outcome.ew.will_fail must be bool")
				for lf in ["latency_base_s", "latency_ew_add_s"]:
					var lv = oc.get(lf, null)
					if not (lv is int or lv is float) or not is_finite(float(lv)):
						oc_problems.append("outcome.%s must be a finite number" % lf)
				row["legacy_outcome_v1"] = false
			else:
				# v1：EW 接线前的合法旧记录，明确标记迁移（不是 legacy_unverified）
				row["legacy_outcome_v1"] = true
			if not (oc.get("ok", null) is bool):
				oc_problems.append("outcome.ok must be bool")
			for sf in ["reason", "mode", "delivery_id"]:
				if not (oc.get(sf, null) is String):
					oc_problems.append("outcome.%s must be a string" % sf)
			for nf in ["latency_s", "arrive_t", "sent_t"]:
				var nv = oc.get(nf, null)
				if not (nv is int or nv is float) or not is_finite(float(nv)):
					oc_problems.append("outcome.%s must be a finite number" % nf)
			var rc = oc.get("relay_count", null)
			if not (rc is int or rc is float) or not is_finite(float(rc)) \
					or absf(float(rc) - roundf(float(rc))) > 0.0 or float(rc) < 0.0:
				oc_problems.append("outcome.relay_count must be a non-negative integer")
			if not (oc.get("path", null) is Array):
				oc_problems.append("outcome.path must be an array")
		if not oc_problems.is_empty():
			row["invalid_outcome"] = true
			row["recorded"] = rec_outcome.duplicate(true) if rec_outcome is Dictionary else {}
			_comms_restore.append(row)
			return {"ok": false, "reason": "comms_outcome_invalid", "comms": row,
				"errors": ["send_comms outcome 不合法：" + str(oc_problems)]}
	if rec_outcome is Dictionary:
		var ro: Dictionary = rec_outcome
		row["recorded"] = {
			"ok": bool(ro.get("ok", false)), "reason": String(ro.get("reason", "")),
			"delivery_id": String(ro.get("delivery_id", "")),
			"latency_s": float(ro.get("latency_s", 0.0)),
			"path": (ro.get("path", []) as Array).duplicate() \
				if ro.get("path") is Array else [],
			"relay_count": int(ro.get("relay_count", 0)),
		}
		var rec_ok := bool(ro.get("ok", false))
		var diverge: Array = []
		if rec_ok != bool(res.get("ok", false)):
			diverge.append("ok")
		if String(ro.get("reason", "")) != String(res.get("reason", "")):
			diverge.append("reason")
		if String(ro.get("delivery_id", "")) != String(res.get("delivery_id", "")):
			diverge.append("delivery_id")
		if absf(float(ro.get("latency_s", 0.0)) - float(res.get("latency_s", 0.0))) \
				> 1.0e-6:
			diverge.append("latency_s")
		# R04：离散值精确、时间 ≤1e-6 s——核对声明保存的 mode / relay_count / arrive_t。
		if String(ro.get("mode", "")) != String(res.get("mode", "")):
			diverge.append("mode")
		if int(ro.get("relay_count", 0)) != int(res.get("relay_count", 0)):
			diverge.append("relay_count")
		if absf(float(ro.get("arrive_t", -1.0)) - float(res.get("arrive_t", -1.0))) \
				> 1.0e-6:
			diverge.append("arrive_t")
		if JSON.stringify(ro.get("path", [])) != JSON.stringify(row["replay_path"]):
			diverge.append("path")
		# JC-A04：v2 重放必须核对发送时刻冻结的 EW 采样（draw/will_fail/
		# latency add），旧 v1 只核对迁移前的基础字段且显式标记 legacy。
		if legacy_v1:
			row["legacy_outcome_v1"] = true
		else:
			var rec_ew: Dictionary = ro.get("ew", {}) if ro.get("ew") is Dictionary else {}
			var res_ew: Dictionary = res.get("ew", {}) \
				if res.get("ew") is Dictionary else {}
			for ek in ["jam_severity", "latency_add_s", "failure_chance", "draw"]:
				if absf(float(rec_ew.get(ek, -1.0)) - float(res_ew.get(ek, -2.0))) \
						> 1.0e-9:
					diverge.append("ew." + ek)
			if bool(rec_ew.get("will_fail", false)) \
					!= bool(res_ew.get("will_fail", true)):
				diverge.append("ew.will_fail")
			for lk in ["latency_base_s", "latency_ew_add_s"]:
				if absf(float(ro.get(lk, -1.0)) - float(res.get(lk, -2.0))) \
						> 1.0e-6:
					diverge.append(lk)
		row["expected_failure"] = not rec_ok
		row["divergence"] = diverge
		row["matched"] = diverge.is_empty()
		_comms_restore.append(row)
		if not diverge.is_empty():
			return {"ok": false, "reason": "comms_replay_diverged", "comms": row,
				"errors": ["send_comms 重放与原始 outcome 不一致：" + str(diverge)]}
		return {"ok": true, "comms": row}
	# 旧日志：无 outcome 字段 → 可恢复范围按 A-04 规则显式标注
	row["legacy_unverified"] = true
	row["expected_failure"] = false
	row["matched"] = false
	_comms_restore.append(row)
	return {"ok": true, "comms": row}


## A-06：通信恢复报告（只读）：逐项 outcome 对照 + 计数。
func comms_restore_report() -> Dictionary:
	var matched := 0
	var expected_failures := 0
	var legacy := 0
	var legacy_v1 := 0
	var diverged := 0
	for raw in _comms_restore:
		if not (raw is Dictionary):
			continue
		var r: Dictionary = raw
		if bool(r.get("legacy_outcome_v1", false)):
			legacy_v1 += 1
		if bool(r.get("legacy_unverified", false)):
			legacy += 1
			continue
		if not bool(r.get("matched", false)):
			diverged += 1
		elif bool(r.get("expected_failure", false)):
			expected_failures += 1
		else:
			matched += 1
	return {
		"schema": "v17.comms_restore.v1",
		"ops": _comms_restore.duplicate(true),
		"total": _comms_restore.size(),
		"matched_success": matched,
		"matched_expected_failure": expected_failures,
		"legacy_unverified": legacy,
		"legacy_outcome_v1": legacy_v1,
		"diverged": diverged,
		"losless_claim": false,
		"note": "original failures are preserved as failures; only divergences are recovery errors",
	}


func _replay_op(op: Dictionary) -> Dictionary:
	var kind := String(op.get("op", ""))
	match kind:
		"apply_ew":
			if ew_service == null:
				return {"ok": true, "skipped": "no_ew_service"}
			return ew_service.apply(op.get("effect", {}))
		"ew_emcon":
			if ew_service == null:
				return {"ok": true, "skipped": "no_ew_service"}
			return ew_service.set_emcon(bool(op.get("on", false)))
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
			return _replay_send_comms(op)
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
			# R2：重放必须按日志中的**同一份规范化 context**恢复同样语义，
			# 不能只传 salvo 退回无 shooter 的 legacy 路径。
			var rf_opts: Dictionary = {"salvo": int(op.get("salvo", 1))}
			for ck in ["actor_id", "controller_id", "domain_id", "fleet_id",
					"shooter_id", "legacy_context"]:
				if op.has(ck) and String(op.get(ck, "")) != "":
					rf_opts[ck] = String(op.get(ck, ""))
			return request_fire(String(op.get("target_id", "")),
				String(op.get("weapon_id", "")), bool(op.get("confirmed", false)),
				rf_opts)
		"set_weapon_salvo":
			if combat_service == null:
				return {"ok": true, "skipped": "no_combat_service"}
			return set_weapon_salvo(String(op.get("weapon_id", "")), int(op.get("salvo", 1)))
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
		"identification_ingest":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_ingest(op.get("evidence", {}))
		"identification_step":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_step(float(op.get("dt", 0.0)))
		"identification_set_auto":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_set_auto(bool(op.get("enabled", false)), op.get("opts", {}))
		"identification_manual_confirm":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_manual_confirm(str(op.get("target_id", "")),
				str(op.get("identity", "unknown")), op.get("opts", {}))
		"identification_authorize_hostile":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_authorize_hostile(str(op.get("target_id", "")),
				str(op.get("authority", "command")), op.get("opts", {}))
		"identification_clear_manual":
			if identification_service == null:
				return {"ok": true, "skipped": "no_identification_service"}
			return identification_clear_manual(str(op.get("target_id", "")))
		"legal_apply_event":
			if legal_status_service == null:
				return {"ok": true, "skipped": "no_legal_status_service"}
			return legal_apply_event(str(op.get("trigger", "")), op.get("payload", {}))
		"legal_set_status":
			if legal_status_service == null:
				return {"ok": true, "skipped": "no_legal_status_service"}
			return legal_set_status(str(op.get("status", "")), str(op.get("reason", "")))
		"legal_tick":
			if legal_status_service == null:
				return {"ok": true, "skipped": "no_legal_status_service"}
			return legal_tick(float(op.get("dt", 0.0)))
		"traffic_request":
			if traffic_control == null:
				return {"ok": true, "skipped": "no_traffic_control"}
			return traffic_request(str(op.get("track_id", "")),
				str(op.get("lane_id", "")), op.get("opts", {}))
		"traffic_permit":
			if traffic_control == null:
				return {"ok": true, "skipped": "no_traffic_control"}
			return traffic_permit(str(op.get("request_id", "")), op.get("opts", {}))
		"traffic_occupy":
			if traffic_control == null:
				return {"ok": true, "skipped": "no_traffic_control"}
			return traffic_occupy(str(op.get("lane_id", "")),
				str(op.get("occupant_id", "")), op.get("opts", {}))
		"traffic_release":
			if traffic_control == null:
				return {"ok": true, "skipped": "no_traffic_control"}
			return traffic_release(str(op.get("lane_id", "")),
				str(op.get("occupant_id", "")))
		"traffic_disguise":
			if traffic_control == null:
				return {"ok": true, "skipped": "no_traffic_control"}
			return traffic_disguise(str(op.get("track_id", "")),
				op.get("disguise", {}), op.get("opts", {}))
		"combat_ballistics_launch":
			if combat_ballistics == null:
				return {"ok": true, "skipped": "no_combat_ballistics"}
			return combat_ballistics_launch(str(op.get("shooter", "")),
				str(op.get("target", "")), str(op.get("weapon", "")), op.get("opts", {}))
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

# ═══════════════════════════════════════════════════════════════════
# JC-A01（#58）：指挥权限与分方情报 facade
# ═══════════════════════════════════════════════════════════════════

## 授权检查（fire 入口用；不消耗资源）。
## R1b：真实逐舰运行态**按实际运行态注入**，配置 bool 不得自证。
func authorize_fire(opts := {}) -> Dictionary:
	if not _authority_enabled or authority_intel == null:
		return {"ok": false, "reason": "authority_unavailable"}
	var runtime_ids: Array = []
	if combat_service != null and combat_service.get("own_id") != null:
		var own_id := String(combat_service.own_id)
		if own_id != "":
			runtime_ids.append(own_id)
	return authority_intel.authorize_fire(
		opts if opts is Dictionary else {}, runtime_ids)


func _record_fire_audit(target_id: String, weapon_id: String, opts: Dictionary,
		auth: Dictionary, rejected: bool) -> void:
	if not _authority_enabled or authority_intel == null:
		return
	# R2：审计必须带**同一份规范化 context**（actor/controller/fleet/shooter/t/legacy）
	authority_intel.record_audit({
		"t": float(now_s()), "op": "request_fire", "target_id": target_id,
		"weapon_id": weapon_id,
		"requested_shooter": String(opts.get("shooter_id", "")),
		"requested_actor": String(opts.get("actor_id", "")),
		"requested_controller": String(opts.get("controller_id", "")),
		"requested_domain": String(opts.get("domain_id", "")),
		"requested_fleet": String(opts.get("fleet_id", "")),
		"resolved_shooter": String(auth.get("shooter_id", "")),
		"actor_id": String(auth.get("actor_id", "")),
		"controller_id": String(auth.get("controller_id", "")),
		"domain_id": String(auth.get("domain_id", "")),
		"fleet_id": String(auth.get("fleet_id", "")),
		"context_source": String(auth.get("context_source", "")),
		"legacy_context": String(auth.get("legacy_context", "")),
		"own_entity_instance_id": String(auth.get("own_entity_instance_id", "")),
		"ok": not rejected, "reason": String(auth.get("reason", "")),
		"detail": String(auth.get("detail", "")),
	})


func fire_audit() -> Array:
	if not _authority_enabled or authority_intel == null:
		return []
	return authority_intel.fire_audit()


func intel_owner_of(entity_id: String) -> String:
	if not _authority_enabled or authority_intel == null:
		return ""
	return authority_intel.owner_of_entity(entity_id)


## 本舰实体 id（可信锚点；供 HUD/情报 facade 解析默认 owner）。
func own_entity_id() -> String:
	return String(_seed.get("own_entity", ""))


## owner 隔离读入口：只返回该 owner 自己的航迹与观测。
func intel_view(owner_id: String) -> Dictionary:
	if not _authority_enabled or authority_intel == null:
		return {"owner_id": owner_id, "tracks": [], "observations": [],
			"reason": "authority_unavailable"}
	return authority_intel.intel_view(owner_id)


## 玩家/AI 可读的绘图位置：只来自该 owner 航迹（绝不读物理真值）。
func plot_positions(owner_id: String) -> Dictionary:
	if not _authority_enabled or authority_intel == null:
		return {"owner_id": owner_id, "source": "unavailable", "positions": []}
	return authority_intel.plot_positions(owner_id)


func selected_tracks(owner_id: String) -> Array:
	if not _authority_enabled or authority_intel == null:
		return []
	return authority_intel.selected(owner_id)


## 接收共享观测：**必须经真实投递到达**；只有接收 owner 自己的视图可见。
## delivery: delivery_id / received_t / share_authorized_by / path / delay_s
func receive_intel_observation(owner_id: String, row: Dictionary,
		delivery := {}) -> Dictionary:
	if not _authority_enabled or authority_intel == null:
		return {"ok": false, "reason": "authority_unavailable"}
	var d: Dictionary = delivery if delivery is Dictionary else {}
	# 实际到达时刻默认取会话当前时刻（不得由调用方随意填未来时间）
	if not d.has("received_t"):
		d["received_t"] = float(now_s())
	if not d.has("now_t"):
		d["now_t"] = float(now_s())
	return authority_intel.receive_observation(owner_id, row, d)


## 经既有 Comms 链路发起一次情报共享（发出→未到达不可见→到达仅接收方融合）。
func queue_intel_share(from_id: String, to_id: String, owner_id: String,
		row: Dictionary, text_key := "COMMS_SENT") -> Dictionary:
	if comms == null:
		return {"ok": false, "reason": "no_comms"}
	var payload := {"intel_share": {
		"owner_id": owner_id,
		"row": row.duplicate(true),
		"share_authorized_by": String(row.get("observer_id", "")) \
			if false else String(row.get("share_authorized_by", "")),
	}}
	var sr: Dictionary = comms.send(from_id, to_id, "LD", text_key, payload, {})
	if not bool(sr.get("ok", false)):
		return sr
	var did := String(sr.get("delivery_id", ""))
	# 与 send_comms 相同：登记到 _standalone，使到达时由 _reconcile_standalone 投递
	_standalone[did] = {"from": from_id, "to": to_id, "mode": "LD",
		"text_key": text_key, "sent_t": now_s(),
		"latency_s": float(sr.get("latency_s", 0.0))}
	_pending_intel_shares[did] = {
		"owner_id": owner_id, "row": row.duplicate(true),
		"from": from_id, "to": to_id,
		"share_authorized_by": String(row.get("share_authorized_by", "")),
	}
	return {"ok": true, "delivery_id": did, "pending": _pending_intel_shares.size()}


## 处理已到达的共享：只把 delivered 事件转成 receiver 的融合输入。
func _drain_intel_deliveries() -> void:
	if comms == null or not _authority_enabled or authority_intel == null:
		return
	var evs: Array = comms.take_events()
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := String(ev.get("kind", ""))
		var did := String(ev.get("delivery_id", ""))
		if did == "" or not _pending_intel_shares.has(did):
			continue
		if kind != "delivered":
			continue
		var pend: Dictionary = _pending_intel_shares[did]
		_pending_intel_shares.erase(did)
		var row: Dictionary = (pend.get("row", {}) as Dictionary).duplicate(true)
		var delivery := {"delivery_id": did,
			"received_t": float(ev.get("t", now_s())),
			"now_t": float(now_s()),
			"share_authorized_by": String(pend.get("share_authorized_by", "")),
			"path": "%s->%s" % [String(pend.get("from", "")),
				String(pend.get("to", ""))]}
		if row.get("delay_s", null) == null:
			delivery["delay_s"] = float(ev.get("latency_s", 0.0))
		var rr: Dictionary = authority_intel.receive_observation(
			String(pend.get("owner_id", "")), row, delivery)
		if bool(rr.get("ok", false)):
			(ev as Dictionary)["intel_owner_id"] = String(pend.get("owner_id", ""))
			# 到达后立即触发一次 owner 融合读（保证 HUD/列表读到的是融合结果）
			var _v: Dictionary = authority_intel.intel_view(
				String(pend.get("owner_id", "")))
			_v.clear()


## 处理已到达的共享：只把 delivered 的共享转成 receiver 的融合输入。
func _deliver_intel_share(delivery_id: String, info := {}) -> void:
	if not _authority_enabled or authority_intel == null:
		return
	if not _pending_intel_shares.has(delivery_id):
		return
	var pend: Dictionary = _pending_intel_shares[delivery_id]
	var row: Dictionary = (pend.get("row", {}) as Dictionary).duplicate(true)
	var info_d: Dictionary = info if info is Dictionary else {}
	var latency := 0.0
	var lat_raw = info_d.get("latency_s", null)
	if lat_raw is int or lat_raw is float:
		latency = float(lat_raw)
	elif lat_raw is String and String(lat_raw) != "":
		latency = float(String(lat_raw))
	var delivery := {"delivery_id": delivery_id,
		"received_t": float(now_s()),
		"now_t": float(now_s()),
		"share_authorized_by": String(pend.get("share_authorized_by", "")),
		"path": "%s->%s" % [String(pend.get("from", "")),
			String(pend.get("to", ""))]}
	# 延迟必须与实际到达一致（received - observed），不能用链路理论时延冒充
	var obs_t := float(row.get("observed_t", 0.0))
	delivery["delay_s"] = maxf(0.0, float(now_s()) - obs_t)
	delivery["link_latency_s"] = latency
	var rr: Dictionary = authority_intel.receive_observation(
		String(pend.get("owner_id", "")), row, delivery)
	_last_intel_share_result = {"delivery_id": delivery_id,
		"result": rr.duplicate(true), "delivery": delivery.duplicate(true)}
	# JC-A04：真实 delivered 只消费一次；即使 owner 拒绝融合（授权/时间等原因）
	# 也清除待融合，避免同一真实结果被重复消费或 pending 消失被误判为成功。
	_pending_intel_shares.erase(delivery_id)


## R4 诊断：最近一次共享到达的判定结果
func last_intel_share_result() -> Dictionary:
	return _last_intel_share_result.duplicate(true)

## 已到达共享的待融合项（供恢复后继续处理）。
func pending_intel_shares() -> Dictionary:
	return _pending_intel_shares.duplicate(true)


## 测试钩子：直接改世界真值（模拟未观测到的敌方改名/移动），**不**通知任何 owner。
## R6：必须实际改变被测真值表面，并回传前后值供断言。
func _apply_hidden_truth_mutation(entity_id: String, new_id: String,
		new_pos: Array) -> Dictionary:
	var before := {}
	var after := {}
	var moved := 0
	# 0) 物理表面基线（T2：声称 physics 就核对 physics，不能只比 WorldState 副本）
	var phys_before: Array = []
	if physics_world_service != null:
		var st0: Dictionary = physics_state(entity_id)
		if st0.get("r") is Array:
			phys_before = (st0.get("r") as Array).duplicate()
	if not phys_before.is_empty():
		before["physics"] = {"pos_km": phys_before.duplicate()}
	# 1) WorldState 是实体元数据权威：用既有 entity.move 事件真实改坐标
	if world != null and world.has_method("entity") and world.has_method("apply"):
		var e0: Dictionary = world.entity(entity_id)
		if not e0.is_empty():
			before["world"] = {"pos_km": (e0.get("pos_km", []) as Array).duplicate(),
				"name": String(e0.get("name", ""))}
	if world != null and world.has_method("apply"):
		if new_pos is Array and (new_pos as Array).size() >= 3:
			var ev: Dictionary = _mk_event("entity.move", entity_id,
				{"pos_km": (new_pos as Array).duplicate()})
			var w: String = String(world.get("writer"))
			if w == "":
				w = String(_seed.get("writer", "session"))
			var r: Dictionary = world.apply(ev, w)
			if bool(r.get("ok", false)):
				moved += 1
	if world != null and world.has_method("entity"):
		var e1: Dictionary = world.entity(entity_id)
		if not e1.is_empty():
			after["world"] = {"pos_km": (e1.get("pos_km", []) as Array).duplicate(),
				"name": String(e1.get("name", ""))}
	# 2) 物理表面：若提供真实 upsert/重置接口则同步（不同实现命名不同）
	if physics_world_service != null:
		for m in ["upsert_entity", "set_position", "set_entity_state"]:
			if physics_world_service.has_method(m):
				var st: Dictionary = physics_state(entity_id)
				var vel = st.get("v", [0.0, 0.0, 0.0])
				if m == "upsert_entity":
					physics_world_service.call(m, entity_id,
						{"r": (new_pos as Array).duplicate(), "v": vel})
				elif m == "set_position":
					physics_world_service.call(m, entity_id,
						(new_pos as Array).duplicate(), vel)
				else:
					physics_world_service.call(m, entity_id,
						{"r": (new_pos as Array).duplicate(), "v": vel})
				moved += 1
				break
	var before_pos: Array = (before.get("world", {}) as Dictionary).get("pos_km", [])
	var after_pos: Array = (after.get("world", {}) as Dictionary).get("pos_km", [])
	var phys_after: Array = []
	if physics_world_service != null:
		var st1: Dictionary = physics_state(entity_id)
		if st1.get("r") is Array:
			phys_after = (st1.get("r") as Array).duplicate()
	if not phys_after.is_empty():
		after["physics"] = {"pos_km": phys_after.duplicate()}
	var changed := false
	if before_pos.size() >= 3 and after_pos.size() >= 3:
		changed = absf(float(before_pos[0]) - float(after_pos[0])) > 1.0e-9 \
			or absf(float(before_pos[1]) - float(after_pos[1])) > 1.0e-9 \
			or absf(float(before_pos[2]) - float(after_pos[2])) > 1.0e-9
	var physics_changed := false
	if phys_before.size() >= 3 and phys_after.size() >= 3:
		physics_changed = absf(float(phys_before[0]) - float(phys_after[0])) > 1.0e-9 \
			or absf(float(phys_before[1]) - float(phys_after[1])) > 1.0e-9 \
			or absf(float(phys_before[2]) - float(phys_after[2])) > 1.0e-9
	return {"ok": true, "entity_id": entity_id, "new_id": new_id,
		"moved_surfaces": moved, "truth_changed": changed or physics_changed,
		"world_changed": changed, "physics_changed": physics_changed,
		"before": before, "after": after, "intel_notified": false}
# ── JC-A02：owner 身份管道的存档/恢复 ─────────────────────────────

func _identity_owners_export() -> Dictionary:
	var out: Dictionary = {}
	for owner_id in _identity_owners.keys():
		if owner_id == _identity_own_owner():
			continue  # 本舰 owner 状态已写入 identification_service 段
		var svc = _identity_owners[owner_id]
		out[String(owner_id)] = svc.save_state()
	return out


func _identity_restore_identity(data: Dictionary) -> void:
	if not _identity_enabled:
		_identity_restore_mode = "disabled"
		return
	var own := _identity_own_owner()
	if own != "" and identification_service != null:
		_identity_owners[own] = identification_service
	var raw = data.get("identity_owners", null)
	if raw is Dictionary:
		_identity_restore_mode = "full"
		for owner_id in (raw as Dictionary).keys():
			if String(owner_id) == own:
				continue
			if not _identity_owner_ok(String(owner_id)):
				continue
			var svc = _identity_service_for(String(owner_id))
			if svc == null:
				continue
			var state = (raw as Dictionary)[owner_id]
			if state is String and String(state) != "":
				svc.load_state(state)
	else:
		# 旧单实例存档：只迁移到本舰 owner（不复制到盟军/敌方）
		_identity_restore_mode = "legacy_single_owner"
	var raw_q = data.get("identity_pending_queries", null)
	_identity_pending_queries = {}
	if raw_q is Dictionary:
		for owner_id2 in (raw_q as Dictionary).keys():
			var rows = (raw_q as Dictionary)[owner_id2]
			if rows is Array and _identity_owner_ok(String(owner_id2)):
				_identity_pending_queries[String(owner_id2)] = (rows as Array).duplicate(true)
	# 真实延迟 IFF 查询队列与已消费事件（每 owner 一次消费）随档恢复
	_identity_query_queue = []
	var raw_qq = data.get("identity_query_queue", null)
	if raw_qq is Array:
		for raw_q2 in (raw_qq as Array):
			if raw_q2 is Dictionary:
				var qrow: Dictionary = raw_q2
				if _identity_owner_ok(String(qrow.get("owner_id", ""))):
					_identity_query_queue.append(qrow.duplicate(true))
	_identity_seen_events = {}
	var raw_seen2 = data.get("identity_seen_events", null)
	if raw_seen2 is Dictionary:
		_identity_seen_events = (raw_seen2 as Dictionary).duplicate(true)
# ── JC-A02：scenario 应答配置安装（缺失保留明确 unavailable，不静默全友军）──
func _install_scenario_transponders() -> void:
	if transponder_service == null:
		return
	var ents = _seed.get("entities", [])
	if not (ents is Array):
		return
	for raw in (ents as Array):
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var tpl := String(e.get("transponder_profile", ""))
		var eid := String(e.get("id", ""))
		if tpl == "" or eid == "":
			continue
		if _transponder_profile_id_for(eid) != "":
			continue
		# 应答声明单独字段；没有就如实 unknown（不用隐藏 side/identity 解题）
		var claimed := String(e.get("transponder_claimed_identity", "unknown"))
		var ur: Dictionary = transponder_service.upsert_profile({
			"profile_id": tpl + ":" + eid,
			"name": String(e.get("name", eid)),
			"entity_type": String(e.get("kind", "ship")),
			"entity_id": eid, "facility_id": "", "facility_code": "",
			"transponder_code": "TXP-" + eid.to_upper(),
			"registration_code": "REG-" + eid.to_upper(),
			"side": "unknown", "identity": claimed,
			"modes": ["mode_s"], "default_mode": "mode_s",
			"status": "normal", "range_km": 5000.0, "silent": false,
			"broadcast": {"interval_s": 30.0, "modes": ["mode_s"],
				"enabled": false},
			"crypto": {"captured": false, "epoch": 1, "valid": true,
				"key_id": ""},
			"trigger_map": {}, "note": "scenario claimed transponder profile"})
		if not bool(ur.get("ok", false)):
			warnings.append("scenario transponder 安装失败：" + eid + " " + str(
				ur.get("errors", []))) 

