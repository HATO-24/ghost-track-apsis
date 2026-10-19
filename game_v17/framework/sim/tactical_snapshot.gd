class_name V2TacticalSnapshot
extends RefCounted

## GHOST TRACK / APSIS · V2 战术快照 / 可视化数据（V2-SENSOR-2）
##
## 职责：把 **core 世界状态（只读）** + **sim 传感器模型状态** 归一化成一份纯数据快照，
## 供 UI/plot 直接消费；另提供 step() 产生「观测注入建议」，但**绝不修改 world**——
## 是否 ingest / advance 由调用方（UI 或关卡流程）决定。
##
## 边界（重要）：
##   * build()：只读 world（vm_* / entities / track_for / t / layers），不写任何 core 字段；
##   * step()：只推进 sim_state 里的传感器模型（V2RadarModel/V2TwsModel/V2OpticalModel），
##     返回雷达扫描观测建议 + TWS 通道观测建议 + 通道事件；**不调用 world.advance/ingest/
##     set_track_*/select**，返回 `world_modified=false`；
##   * 本文件不做渲染、不画扇形/球体；屏幕投影只是「建议坐标」（orthographic 建议相机），
##     UI 可以用自己的相机覆盖；
##   * sim→core 单向：本文件可读 core 对象，core 不引用本文件。
##
## 公开 API：
##   var sim = V2TacticalSnapshot.make_sim_state(world, cfg)       # 从本舰能力建雷达/TWS/光学实例
##   var snap = V2TacticalSnapshot.build(world, sim, cfg)         # 纯数据战术快照
##   var out  = V2TacticalSnapshot.step(world, 1.0, {"sim_state": sim, "camera": cam})
##       → {ok, snapshot, observations, radar_observations, tws_observations,
##          channel_updates, events, world_modified:false, suggested_calls, …}
##   V2TacticalSnapshot.start_channel(sim, "optical"|"ir", "2001")
##   V2TacticalSnapshot.project_local(local_km, camera, own_local_km)   # 屏幕投影建议
##   V2TacticalSnapshot.build_world_snapshot(world, sim, cfg)           # 给传感器模型的输入快照
##
## cfg（可选）：
##   "sim_state"       : step 必填；make_sim_state() 的返回值
##   "camera"          : {map_rect:[x,y,w,h] px, yaw_deg, pitch_deg, scale_px_per_km(0=自动),
##                        center_mode:"own"|"datum", fit_margin}
##   "sim_targets"     : 覆盖世界目标行（测试/适配钩子；空数组可用于验证失锁）
##   "sun_illum"/"shadow"/"jamming"/"los"/"maneuver_g"/"rng" : 传感器环境
##   "radar_model"/"optical_model"/"ir_model"/"max_channels"/"radar_enabled" : make_sim_state 用
##   "bearing_line_km": 无实体方位线的显示长度（建议值，默认 450 km）
##
## 数据口径：docs/34 §8; 05 §S-01…S-07; 01 §5; docs/v2_core_interface.md（world 只读 API）。

const Types := preload("res://framework/sim/sensor_types.gd")
const RadarModel := preload("res://framework/sim/radar.gd")
const TwsModel := preload("res://framework/sim/tws.gd")
const OpticalModel := preload("res://framework/sim/optical.gd")
## v15 复用的轨道模型（无 class_name，按路径 preload）：
## local_propagate = L1 局部相对运动二阶梯泰勒；local_propagate_rk4 = ≤5 s 步长 RK4。
const Orbit := preload("res://scripts/orbit_model.gd")

const SCHEMA_BUILD := "tactical_snapshot.v1"
const SCHEMA_STEP := "tactical_step.v1"
const SCHEMA_SIM := "tactical_sim_state.v1"

## 设计基线 MAP 区（ui/layout.gd 的 MAP Rect2；仅作投影建议默认值，不参与 UI 依赖）。
const DEFAULT_MAP_RECT := [436.0, 124.0, 1088.0, 752.0]
const DEFAULT_YAW_DEG := 0.0
const DEFAULT_PITCH_DEG := 60.0           # 俯视战术图建议俯仰
const DEFAULT_FIT_MARGIN := 0.82
const DEFAULT_BEARING_LINE_KM := 450.0    # [本文定值] 仅用于显示 L1 方位线长度
const MIN_SCALE_PX_PER_KM := 1.0e-6
const EDGE_MARGIN_PX := 14.0
const ACTIVE_TWS_STATES := ["ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const OPTICAL_KINDS := ["optical", "ir"]

# ── V2-SENSOR-3：真实轨道（L1 局部相对运动）与可视化元数据 ────────
const ORBIT_SOURCE := "local_propagate"           # 位置/预测来源标注（需求 §3）
const ORBIT_SOURCE_STATIC := "static_r"           # 只有 r、无 v 的站体：不伪造速度轨迹
const ORBIT_SOURCE_FIXED := "static_fixed"        # tags 含 fixed 的固定设施：不推进（站体/储罐）
const ORBIT_SOURCE_NONE := "none"                 # 无 r/v（如纯方位回波）
const PROPAGATOR_RK4 := "rk4"
const PROPAGATOR_TAYLOR := "taylor"
const DEFAULT_PROPAGATOR := PROPAGATOR_RK4
const PREDICTION_HORIZONS_S := [30.0, 60.0, 120.0]   # 预测点列（秒）
const MAX_PREDICTION_HORIZON_S := 600.0

## 实体 kind → 可视化元数据建议（UI 画符号/尺寸用；本层不做渲染）。
## size_km = 符号建议直径（不是真实包围盒；站体/储罐可用 meta.radius_km 覆盖）。
const ICON_CATALOG := {
	"ship": {"shape": "chevron", "glyph": "ship", "label_cn": "舰船", "size_km": 0.6, "has_orbit": true},
	"station": {"shape": "hexagon", "glyph": "station", "label_cn": "站点", "size_km": 0.8, "has_orbit": false},
	"tank": {"shape": "cylinder", "glyph": "tank", "label_cn": "储罐", "size_km": 0.3, "has_orbit": false},
	"wreck": {"shape": "cross", "glyph": "wreck", "label_cn": "残骸", "size_km": 0.5, "has_orbit": false},
	"contact": {"shape": "circle", "glyph": "contact", "label_cn": "接触", "size_km": 0.4, "has_orbit": false},
	"unknown": {"shape": "diamond", "glyph": "unknown", "label_cn": "未知", "size_km": 0.4, "has_orbit": false},
}



# ═══════════════════════════════════════════════════════════════════
# 1. 传感器模型装配（从本舰能力/型号架生成 sim_state）
# ═══════════════════════════════════════════════════════════════════

## 从 world 本舰能力/传感器架创建 sim 模型实例（RefCounted，不触碰 world）。
## 返回 sim_state（build()/step() 的输入）：
##   {schema, observer_id, time, radar, tws, optical, records, enabled, notes}
static func make_sim_state(world, cfg: Dictionary = {}) -> Dictionary:
	var own = _own_entity(world)
	var own_id := ""
	var meta: Dictionary = {}
	var signatures: Dictionary = {}
	if own != null:
		own_id = String(own.id)
		meta = _as_dict(own.meta)
		signatures = _as_dict(own.signatures)
	var rack := _as_array(meta.get("sensors", []))
	var radar_model := String(cfg.get("radar_model", _pick_model(rack, signatures, "radar", "YW-R9")))
	var optical_model := String(cfg.get("optical_model", _pick_model(rack, signatures, "optical", "MS-OT2")))
	var ir_model := String(cfg.get("ir_model", _pick_model(rack, signatures, "ir", "CH-IR2")))
	var has_radar := bool(cfg.get("radar_enabled", true)) and _has_radar_capability(own)
	var radar_rec = Types.record(radar_model)
	var tws = TwsModel.new(radar_rec, {
		"id": radar_model,
		"max_channels": int(cfg.get("max_channels", radar_rec.track_capacity)),
		"enabled": has_radar,
	})
	var opt = OpticalModel.new({
		"optical": Types.record(optical_model),
		"ir": Types.record(ir_model),
	})
	return {
		"schema": SCHEMA_SIM,
		"observer_id": own_id,
		"time": 0.0,
		"radar": tws.radar,          # 与 TWS 共享同一部雷达（扫描节奏一致）
		"tws": tws,
		"optical": opt,
		"records": {
			"radar": radar_rec.to_dict(),
			"optical": Types.record(optical_model).to_dict(),
			"ir": Types.record(ir_model).to_dict(),
		},
		"enabled": {
			"radar": has_radar,
			"tws": has_radar,
			"optical": true,
			"ir": true,
		},
		"notes": [] if has_radar else ["本舰无 sensor.radar.active 能力：雷达/TWS 默认关闭（可 cfg.radar_enabled 覆盖）"],
	}


## 建立光学/IR 凝视通道（调用方在 UI 点“建立通道”时用）。
static func start_channel(sim_state: Dictionary, kind: String, track_id: String) -> Dictionary:
	var opt = sim_state.get("optical", null)
	if opt == null:
		return {"ok": false, "reason": "sim_state 无 optical 模型"}
	return opt.start(kind, track_id)


## 停止光学/IR 通道（target_id 为空 = 停该类型全部）。
static func stop_channel(sim_state: Dictionary, kind: String, track_id: String = "") -> void:
	var opt = sim_state.get("optical", null)
	if opt != null:
		opt.stop(kind, track_id)


## 设置雷达/TWS 开关（EMCON；只改 sim 模型，不改 world）。
static func set_radar_enabled(sim_state: Dictionary, on: bool) -> void:
	var tws = sim_state.get("tws", null)
	if tws != null:
		tws.set_enabled(on)
	var en: Dictionary = _as_dict(sim_state.get("enabled", {}))
	en["radar"] = on
	en["tws"] = on
	sim_state["enabled"] = en


# ═══════════════════════════════════════════════════════════════════
# 1.5 轨道传播（Orbit.local_propagate / RK4）与可视化元数据
# ═══════════════════════════════════════════════════════════════════

## L1 局部相对运动传播（km / km/s）。mode: "rk4"（默认，步长 ≤5 s）| "taylor"（二阶梯）。
## 返回 JSON 友好字典：{r:[x,y,z], v:[x,y,z], source:"local_propagate", propagator, dt_s}。
static func propagate_local(r_km, v_kmps, dt_s: float,
		mode: String = DEFAULT_PROPAGATOR) -> Dictionary:
	var r := Types.to_vec3(r_km)
	var v := Types.to_vec3(v_kmps)
	var dt := clampf(dt_s, -MAX_PREDICTION_HORIZON_S, MAX_PREDICTION_HORIZON_S)
	var out: Dictionary
	if mode == PROPAGATOR_TAYLOR:
		out = Orbit.local_propagate(r, v, dt)
	else:
		out = Orbit.local_propagate_rk4(r, v, dt)
	var rr: Vector3 = out.get("r", r)
	var vv: Vector3 = out.get("v", v)
	return {
		"r": _vec_array(rr),
		"v": _vec_array(vv),
		"source": ORBIT_SOURCE,
		"propagator": PROPAGATOR_TAYLOR if mode == PROPAGATOR_TAYLOR else PROPAGATOR_RK4,
		"dt_s": dt,
	}


## 实体 kind → 符号/尺寸元数据目录（UI 画符号用；本层不渲染）。
static func icon_catalog() -> Dictionary:
	return ICON_CATALOG.duplicate(true)


## kind + meta/tags → 单个实体的可视化元数据：
##   {kind, shape, glyph, label_cn, size_km, has_orbit, fixed, is_station/is_tank/is_wreck}
## meta 可覆盖：icon（形状名）、size_km、radius_km、radius_m。
static func visual_metadata(kind: String, meta: Dictionary = {}, tags: Array = []) -> Dictionary:
	var k := kind if ICON_CATALOG.has(kind) else "unknown"
	var base: Dictionary = (ICON_CATALOG[k] as Dictionary).duplicate(true)
	var size_km := float(base.get("size_km", 0.4))
	if meta.has("size_km"):
		size_km = maxf(0.01, float(meta.get("size_km", size_km)))
	elif meta.has("radius_km"):
		size_km = maxf(0.01, float(meta.get("radius_km", 0.0)) * 2.0)
	elif meta.has("radius_m"):
		size_km = maxf(0.01, float(meta.get("radius_m", 0.0)) * 2.0 / 1000.0)
	var shape := String(base.get("shape", k))
	if meta.has("icon") and String(meta.get("icon", "")) != "":
		shape = String(meta.get("icon", shape))
	var fixed := tags.has("fixed")
	return {
		"kind": k,
		"shape": shape,
		"glyph": String(base.get("glyph", k)),
		"label_cn": String(base.get("label_cn", "")),
		"size_km": size_km,
		"has_orbit": bool(base.get("has_orbit", false)),
		"fixed": fixed,
		"is_station": k == "station",
		"is_tank": k == "tank",
		"is_wreck": k == "wreck",
	}


## V2Entity / 实体字典 → 可视化元数据（probe 与 UI 复用）。
static func entity_visual(entity) -> Dictionary:
	if entity == null:
		return visual_metadata("unknown")
	if entity is Dictionary:
		var d: Dictionary = entity
		return visual_metadata(String(d.get("kind", "unknown")),
			_as_dict(d.get("meta", {})), _as_array(d.get("tags", [])))
	return visual_metadata(String(entity.kind), _as_dict(entity.meta), _as_array(entity.tags))


## 读取实体轨道状态（只读；不伪造：无 r 即无位置，无 v 或 fixed 则不推进）。
static func _entity_orbit_state(entity) -> Dictionary:
	var out: Dictionary = {
		"has_r": false, "r0": Vector3.ZERO, "has_v": false, "v0": Vector3.ZERO,
		"fixed": false, "kind": "unknown", "meta": {}, "tags": [],
	}
	if entity == null:
		return out
	var orbit: Dictionary = {}
	var meta: Dictionary = {}
	var tags: Array = []
	var kind := "unknown"
	if entity is Dictionary:
		var d: Dictionary = entity
		kind = String(d.get("kind", "unknown"))
		meta = _as_dict(d.get("meta", {}))
		tags = _as_array(d.get("tags", []))
		orbit = _as_dict(d.get("orbit", {}))
		if orbit.is_empty() and (d.has("r") or d.has("v")):
			orbit = d
	else:
		kind = String(entity.kind)
		meta = _as_dict(entity.meta)
		tags = _as_array(entity.tags)
		orbit = _as_dict(entity.orbit)
	if orbit.has("r") and orbit.get("r") != null:
		out["has_r"] = true
		out["r0"] = Types.to_vec3(orbit.get("r", []))
	if orbit.has("v") and orbit.get("v") != null:
		out["has_v"] = true
		out["v0"] = Types.to_vec3(orbit.get("v", []))
	out["fixed"] = tags.has("fixed")
	out["kind"] = kind
	out["meta"] = meta
	out["tags"] = tags
	return out


## 实体在 time_s 时刻的 L1 局部状态：
##   {has_position, r, v, source(local_propagate/static_fixed/static_r/none), propagator,
##    fixed, epoch_r, epoch_v}
static func _entity_state(entity, time_s: float, mode: String) -> Dictionary:
	var st := _entity_orbit_state(entity)
	var out: Dictionary = {
		"has_position": false,
		"r": Vector3.ZERO,
		"v": Vector3.ZERO,
		"source": ORBIT_SOURCE_NONE,
		"propagator": mode,
		"fixed": bool(st.get("fixed", false)),
		"epoch_r": null,
		"epoch_v": null,
	}
	if not bool(st.get("has_r", false)):
		return out
	var r0: Vector3 = st.get("r0", Vector3.ZERO)
	out["has_position"] = true
	out["epoch_r"] = _vec_array(r0)
	if bool(st.get("fixed", false)) or not bool(st.get("has_v", false)):
		out["r"] = r0
		out["v"] = Vector3.ZERO
		out["source"] = ORBIT_SOURCE_FIXED if bool(st.get("fixed", false)) else ORBIT_SOURCE_STATIC
		out["propagator"] = "none"
		if bool(st.get("has_v", false)):
			out["epoch_v"] = _vec_array(st.get("v0", Vector3.ZERO))
		return out
	var v0: Vector3 = st.get("v0", Vector3.ZERO)
	out["epoch_v"] = _vec_array(v0)
	var prop := propagate_local(r0, v0, time_s, mode)
	out["r"] = Types.to_vec3(prop.get("r", []))
	out["v"] = Types.to_vec3(prop.get("v", []))
	out["source"] = ORBIT_SOURCE
	out["propagator"] = String(prop.get("propagator", mode))
	return out


## 位置预测：30/60/120 s 点列（L1 局部 km，绝对坐标；view/screen 由投影层补）。
static func _prediction_for(state: Dictionary, time_s: float, mode: String,
		level: int, age: float) -> Dictionary:
	if not bool(state.get("has_position", false)):
		return {}
	var source := String(state.get("source", ORBIT_SOURCE_NONE))
	if source == ORBIT_SOURCE_NONE:
		return {}
	var fixed := bool(state.get("fixed", false))
	var r_now: Vector3 = state.get("r", Vector3.ZERO)
	var v_now: Vector3 = state.get("v", Vector3.ZERO)
	var epoch_r: Vector3 = Types.to_vec3(state.get("epoch_r", []))
	var epoch_v: Vector3 = Types.to_vec3(state.get("epoch_v", []))
	var points: Array = []
	for h_raw in PREDICTION_HORIZONS_S:
		var h := float(h_raw)
		var point: Dictionary = {"dt_s": h, "t_s": time_s + h, "fixed": fixed}
		if fixed or source != ORBIT_SOURCE:
			point["local_r_km"] = _vec_array(r_now)
			point["sigma_km"] = 0.0
		else:
			var prop := propagate_local(epoch_r, epoch_v, time_s + h, mode)
			point["local_r_km"] = prop.get("r", _vec_array(r_now))
			point["sigma_km"] = float(Orbit.sigma_km({"level": level, "age": age}, h))
		points.append(point)
	return {
		"source": source,
		"propagator": String(state.get("propagator", mode)),
		"fixed": fixed,
		"horizons_s": PREDICTION_HORIZONS_S.duplicate(),
		"points": points,
	}


## 快照时间基准：默认 world.t；cfg.time_s 可覆盖（测试/回放/外部时钟适配）。
static func _snapshot_time(world, cfg: Dictionary) -> float:
	if cfg.has("time_s"):
		return float(cfg.get("time_s", 0.0))
	return _world_time(world)


static func _pick_model(rack: Array, signatures: Dictionary, kind: String, fallback: String) -> String:
	for raw in rack:
		var model := String(raw)
		if model.is_empty():
			continue
		var rec = Types.record(model)
		var ok := false
		match kind:
			"radar":
				ok = bool(rec.is_radar()) or String(rec.kind) == "search_radar" or String(rec.kind) == "tws_radar"
			"optical":
				ok = String(rec.kind) == "optical" and String(rec.subtype) != "lidar"
			"ir":
				ok = String(rec.kind) == "ir"
			_:
				ok = String(rec.kind) == kind
		if ok:
			return model
	var sig := String(signatures.get(kind, ""))
	if sig != "":
		return sig
	return fallback


static func _has_radar_capability(own) -> bool:
	if own == null:
		return false
	var caps := _as_array(own.capabilities)
	if caps.has("sensor.radar.active") or caps.has("sensor.radar.tws"):
		return true
	# 有雷达型号签名时也视为可用（迁移场景可能没写 capability）。
	return String(_as_dict(own.signatures).get("radar", "")) != ""


# ═══════════════════════════════════════════════════════════════════
# 2. build(world, sim_state, cfg)：纯数据战术快照
# ═══════════════════════════════════════════════════════════════════

## 构建战术快照（只读 world + 读取 sim_state 当前状态；不推进任何模型）。
## 位置/预测来自 Orbit.local_propagate_rk4（L1 局部相对运动），不再是 r+v·t 线性外推。
static func build(world, sim_state: Dictionary = {}, cfg: Dictionary = {}) -> Dictionary:
	var sim: Dictionary = sim_state if sim_state != null else {}
	var time_s := _snapshot_time(world, cfg)
	var mode := String(cfg.get("propagator", DEFAULT_PROPAGATOR))
	if mode != PROPAGATOR_TAYLOR:
		mode = PROPAGATOR_RK4
	var own = _own_entity(world)
	var own_id := String(own.id) if own != null else String(_world_field(world, "own_id", ""))
	var own_state := _entity_state(own, time_s, mode)
	var own_local := _entity_pos(own)
	if bool(own_state.get("has_position", false)):
		own_local = own_state.get("r", own_local)
	var camera := camera_from(cfg)
	var own_view := _own_view(own_local, camera)
	var contacts := _build_contacts(world, sim, cfg, camera, own_local, time_s, mode)
	_resolve_auto_scale(camera, contacts, own_local)
	_project_contacts(contacts, camera, own_local, own_view)

	var tws_section := _tws_section(sim)
	var optical_section := _optical_section(sim)
	var radar_section := _radar_section(world, sim, cfg, own_local, contacts)
	var layers := _read_layers(world)
	var snap := {
		"schema": SCHEMA_BUILD,
		"version": 3,
		"drawable": false,   # 本文件不做渲染
		"t": _world_time(world),
		"time_s": time_s,
		"datum": _scenario_datum(world),
		"scenario_id": _scenario_field(world, "id", ""),
		"orbit_source": ORBIT_SOURCE,
		"propagator": mode,
		"prediction_horizons_s": PREDICTION_HORIZONS_S.duplicate(),
		"icon_catalog": icon_catalog(),
		"own": _own_section(own, own_id, own_local, own_state, camera, own_view, time_s, mode),
		"contacts": contacts,
		"radar": radar_section,
		"tws": tws_section,
		"optical": optical_section,
		"exposure": radar_section.get("exposure", {}),
		"layers": layers,
		"camera": camera,
		"counts": {
			"contacts": contacts.size(),
			"entities": _count_entities(contacts),
			"no_entity": contacts.size() - _count_entities(contacts),
			"bearing_only": _count_bearing_only(contacts),
			"in_radar_sphere": _count_in_radar_sphere(contacts),
			"stations": _count_kind(contacts, "station"),
			"tanks": _count_kind(contacts, "tank"),
			"predicted": _count_predicted(contacts),
			"tws_channels": tws_section.get("channel_count", 0),
			"tws_active": tws_section.get("active_count", 0),
			"optical_locked": optical_section.get("locked_count", 0),
		},
		"notes": _build_notes(sim),
	}
	return _json_ready(snap)


# ── 2.1 接触行（世界航迹，含无实体回波 9002 与固定站体/储罐）────────

static func _build_contacts(world, sim: Dictionary, cfg: Dictionary, camera: Dictionary,
		own_local: Vector3, time_s: float, mode: String) -> Array:
	var rows: Array = []
	if world != null and world.has_method("vm_contacts"):
		rows = _as_array(world.vm_contacts())
	elif not _entity_list(world).is_empty():
		rows = _rows_from_entities(world)
	var out: Array = []
	var radar_rec = _sim_radar_record(sim)
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var entry := _contact_entry(world, row, sim, cfg, camera, own_local, time_s, mode, radar_rec)
		out.append(entry)
	return out


static func _contact_entry(world, row: Dictionary, sim: Dictionary, cfg: Dictionary,
		camera: Dictionary, own_local: Vector3, time_s: float, mode: String,
		radar_rec) -> Dictionary:
	var track_id := String(row.get("track_id", row.get("id", "")))
	var entity_id := String(row.get("entity_id", ""))
	var has_entity := bool(row.get("has_entity", entity_id != ""))
	var entity = null
	if world != null and entity_id != "" and world.has_method("entity"):
		entity = world.entity(entity_id)
	var tr = null
	if world != null and track_id != "" and world.has_method("track_for"):
		tr = world.track_for(track_id)
	var level := int(row.get("level", _track_field(tr, "level", 0)))
	var identity := String(row.get("identity", _track_field(tr, "identity_kind", "unknown")))
	var threat := String(row.get("threat", _track_field(tr, "threat", "pending")))
	var kind := String(row.get("kind", "contact"))
	if entity != null and not (entity is Dictionary):
		kind = String(entity.kind)
	elif entity != null and entity is Dictionary:
		kind = String((entity as Dictionary).get("kind", kind))
	var visual := entity_visual(entity) if has_entity else visual_metadata("unknown")
	var entity_state := _entity_state(entity, time_s, mode) if has_entity else {}
	var bearing_deg := float(row.get("bearing_deg", _track_field(tr, "bearing_deg", -1.0)))
	var range_km := float(row.get("range_km", _track_field(tr, "range_km", -1.0)))
	if has_entity and entity != null and bool(entity_state.get("has_position", false)):
		var pos: Vector3 = entity_state.get("r", Vector3.ZERO)
		var geom := Types.geometry_km(own_local, pos)
		bearing_deg = float(geom.get("bearing_deg", bearing_deg))
		range_km = float(geom.get("range_km", range_km))
	var bearing_only := bool(row.get("bearing_only", _track_field(tr, "bearing_only", range_km < 0.0)))
	if level <= 1:
		bearing_only = true
	var range_band := String(row.get("range_band", _track_field(tr, "range_band", "")))
	var sigma_b := float(row.get("bearing_sigma_deg", _track_field(tr, "bearing_sigma_deg", 180.0)))
	var display_name := String(row.get("name", ""))
	var entry: Dictionary = {
		"track_id": track_id,
		"entity_id": entity_id,
		"batch": String(row.get("batch", track_id)),
		"name": display_name,
		"name_en": String(row.get("name_en", "")),
		"class": String(row.get("class", "")),
		"role": String(row.get("role", "")),
		"side": String(row.get("side", "unknown")),
		"faction": String(row.get("faction", "")),
		"kind": kind,
		"icon": visual.get("shape", "unknown"),
		"icon_meta": visual,
		"size_km": float(visual.get("size_km", 0.4)),
		"is_station": bool(visual.get("is_station", false)),
		"is_tank": bool(visual.get("is_tank", false)),
		"is_wreck": bool(visual.get("is_wreck", false)),
		"fixed": bool(visual.get("fixed", false)),
		"has_entity": has_entity,
		"is_own": _is_own_row(world, row, entity_id),
		"selected": bool(row.get("selected", false)),
		"level": level,
		"level_name": String(row.get("level_name", _track_field(tr, "level_name", ""))),
		"level_label": String(row.get("level_label", _track_field(tr, "level_label", ""))),
		"identity": identity,
		"identity_label": String(row.get("identity_label", _track_field(tr, "identity_label", ""))),
		"threat": threat,
		"stale": bool(row.get("stale", _track_field(tr, "stale", false))),
		"age_s": float(row.get("age_s", _track_field(tr, "age_s", 0.0))),
		"quality": float(row.get("quality", _track_field(tr, "quality", 0.0))),
		"observation_count": int(row.get("observation_count", _track_field(tr, "observation_count", 0))),
		"sources": _as_array(row.get("sources", _track_field(tr, "sources", []))),
		"bearings": {
			"bearing_deg": bearing_deg,
			"bearing_sigma_deg": sigma_b,
		},
		"range_km": range_km,
		"range_band": range_band,
		"bearing_only": bearing_only,
		"tags": _as_array(row.get("tags", _track_field(tr, "tags", []))),
		"notes": _as_array(row.get("notes", [])),
		"orbit_source": String(entity_state.get("source", ORBIT_SOURCE_NONE)) if has_entity else ORBIT_SOURCE_NONE,
		"propagator": String(entity_state.get("propagator", "none")) if has_entity else "none",
		"epoch_r_km": entity_state.get("epoch_r", null) if has_entity else null,
		"epoch_v_kmps": entity_state.get("epoch_v", null) if has_entity else null,
		"local_v_kmps": _vec_array(entity_state.get("v", Vector3.ZERO)) if has_entity else null,
		"position_source": "none",
		"local_r_km": null,
		"view_r_km": null,
		"screen": {},
		"bearing_line": {},
		"prediction": {},
		"marker": _marker_for(has_entity, bearing_only, visual),
	}
	if bool(entry["is_own"]):
		entry["marker"] = {
			"shape": "own", "bearing_only": false, "emphasis": true,
			"kind": kind, "icon": visual.get("shape", "chevron"),
			"size_km": float(visual.get("size_km", 0.6)), "fixed": bool(visual.get("fixed", false)),
		}
	# 位置显示规则：L1/纯方位接触只给方位线（不泄露实体真位置）；L2+ 才显示位置解。
	var own_row := bool(entry["is_own"])
	var position_known := own_row or (level >= 2 and (has_entity or range_km >= 0.0))
	if position_known and has_entity and entity != null and bool(entity_state.get("has_position", false)):
		var pos: Vector3 = entity_state.get("r", Vector3.ZERO)
		var view := pos - own_local
		entry["position_source"] = "fixed_orbit" if String(entity_state.get("source", "")) == ORBIT_SOURCE_FIXED else "propagated_orbit"
		entry["local_r_km"] = _vec_array(pos)
		entry["view_r_km"] = _vec_array(view)
		entry["range_km"] = float(view.length())
		if radar_rec != null:
			var rcs := _entity_rcs(entity)
			var eff := RadarModel.effective_radius_km(radar_rec, rcs, float(cfg.get("jamming", 0.0)))
			entry["radar_effective_radius_km"] = eff
			entry["in_radar_sphere"] = view.length() <= eff + 1.0e-6
			entry["rcs_m2"] = rcs
		# 轨道预测点列（30/60/120 s）：固定设施不推进（points 为同一点，fixed=true）。
		entry["prediction"] = _prediction_for(entity_state, time_s, mode, level,
			float(entry.get("age_s", 0.0)))
	elif position_known and range_km >= 0.0:
		# L2+ 无实体（交叉定位等）：由航迹方位/距离解重建位置，不读实体真值。
		var br := deg_to_rad(bearing_deg)
		var pos := own_local + Vector3(sin(br), cos(br), 0.0) * range_km
		entry["position_source"] = "track_solution"
		entry["local_r_km"] = _vec_array(pos)
		entry["view_r_km"] = _vec_array(pos - own_local)
		entry["orbit_source"] = "track_solution"
		if radar_rec != null:
			var eff2 := RadarModel.effective_radius_km(radar_rec, 10.0, float(cfg.get("jamming", 0.0)))
			entry["radar_effective_radius_km"] = eff2
			entry["in_radar_sphere"] = range_km <= eff2 + 1.0e-6
	else:
		# L1 纯方位 / 无实体回波（9002）：只给方位线 + 距离档，不给伪造位置。
		entry["position_source"] = "bearing_line"
		entry["orbit_source"] = ORBIT_SOURCE_NONE
		entry["bearing_line"] = _bearing_line(own_local, bearing_deg, sigma_b, cfg)
		if not (entry["bearing_line"] as Dictionary).is_empty():
			var end_local := Types.to_vec3((entry["bearing_line"] as Dictionary).get("endpoint_local_km", []))
			entry["local_r_km"] = _vec_array(end_local)
			entry["view_r_km"] = _vec_array(end_local - own_local)
	if not range_band.is_empty():
		entry["range_band_label"] = _range_band_label(range_band)
	var tws_ch := _tws_channel_for(sim, track_id)
	if not tws_ch.is_empty():
		entry["tws"] = _tws_channel_view(tws_ch)
	var opt_ch := _optical_channel_for(sim, OPTICAL_KINDS, track_id)
	if not opt_ch.is_empty():
		entry["optical_channels"] = opt_ch
	return entry


static func _marker_for(has_entity: bool, bearing_only: bool, visual: Dictionary = {}) -> Dictionary:
	var shape := "contact"
	if not has_entity:
		shape = "phantom"
	elif bearing_only:
		shape = "bearing"
	elif bool(visual.get("is_station", false)):
		shape = "station"
	elif bool(visual.get("is_tank", false)):
		shape = "tank"
	elif bool(visual.get("is_wreck", false)):
		shape = "wreck"
	return {
		"shape": shape,
		"bearing_only": bearing_only,
		"emphasis": has_entity and not bearing_only,
		"kind": String(visual.get("kind", "unknown")),
		"icon": String(visual.get("shape", "unknown")),
		"size_km": float(visual.get("size_km", 0.4)),
		"fixed": bool(visual.get("fixed", false)),
	}



static func _bearing_line(own_local: Vector3, bearing_deg: float, sigma_deg: float,
		cfg: Dictionary) -> Dictionary:
	if bearing_deg < 0.0 and bearing_deg != 0.0:
		return {}
	var length_km := maxf(1.0, float(cfg.get("bearing_line_km", DEFAULT_BEARING_LINE_KM)))
	var br := deg_to_rad(bearing_deg)
	var dir := Vector3(sin(br), cos(br), 0.0)
	var end_local := own_local + dir * length_km
	return {
		"bearing_deg": bearing_deg,
		"bearing_sigma_deg": sigma_deg,
		"length_km": length_km,
		"direction": [dir.x, dir.y, dir.z],
		"endpoint_local_km": _vec_array(end_local),
		"endpoint_view_km": _vec_array(dir * length_km),
	}


static func _range_band_label(band: String) -> String:
	match band:
		"NEAR":
			return "近"
		"MID":
			return "中"
		"FAR":
			return "远"
		_:
			return band


# ── 2.2 屏幕投影建议（orthographic 建议相机；UI 可覆盖）────────────

## 读取/规范化相机建议参数。
static func camera_from(cfg: Dictionary) -> Dictionary:
	var raw := _as_dict(cfg.get("camera", {}))
	var rect := _as_array(raw.get("map_rect", DEFAULT_MAP_RECT))
	var cam := {
		"mode": "orthographic_suggestion",
		"map_rect": _rect4(rect),
		"yaw_deg": float(raw.get("yaw_deg", DEFAULT_YAW_DEG)),
		"pitch_deg": float(raw.get("pitch_deg", DEFAULT_PITCH_DEG)),
		"scale_px_per_km": float(raw.get("scale_px_per_km", 0.0)),
		"auto_scale": float(raw.get("scale_px_per_km", 0.0)) <= 0.0,
		"fit_margin": clampf(float(raw.get("fit_margin", DEFAULT_FIT_MARGIN)), 0.2, 1.0),
		"center_mode": String(raw.get("center_mode", "own")),
		"bearing_line_km": float(raw.get("bearing_line_km", cfg.get("bearing_line_km", DEFAULT_BEARING_LINE_KM))),
	}
	return cam


## 屏幕投影建议：局部 km → 地图像素。orthographic：yaw 绕天顶、pitch 俯视压扁；
## 返回值 {x, y, inside, depth_km, view_km, heading_deg, edge?}。
## 注意：这是**建议坐标**，UI 可以完全不用（自己的相机/投影优先）。
static func project_local(local_r_km, camera: Dictionary, own_local_km: Variant = null) -> Dictionary:
	var cam: Dictionary = camera if camera != null and not camera.is_empty() else camera_from({})
	var rect := _rect4(_as_array(cam.get("map_rect", DEFAULT_MAP_RECT)))
	var center_mode := String(cam.get("center_mode", "own"))
	var view := Types.to_vec3(local_r_km)
	if center_mode == "own" and own_local_km != null:
		view -= Types.to_vec3(own_local_km)
	var yaw := deg_to_rad(float(cam.get("yaw_deg", DEFAULT_YAW_DEG)))
	var pitch := deg_to_rad(float(cam.get("pitch_deg", DEFAULT_PITCH_DEG)))
	var cy := cos(yaw)
	var sy := sin(yaw)
	var x1 := cy * view.x + sy * view.y
	var y1 := -sy * view.x + cy * view.y
	var cp := cos(pitch)
	var sp := sin(pitch)
	var y2 := cp * y1 - sp * view.z
	var depth := sp * y1 + cp * view.z
	var scale := float(cam.get("scale_px_per_km", 0.0))
	var rx: float = float(rect[0])
	var ry: float = float(rect[1])
	var rw: float = float(rect[2])
	var rh: float = float(rect[3])
	var cx: float = rx + rw * 0.5
	var cy_px: float = ry + rh * 0.5
	var sx: float = cx + x1 * scale
	var sy_px: float = cy_px - y2 * scale
	var inside: bool = (sx >= rx and sx <= rx + rw and sy_px >= ry and sy_px <= ry + rh)
	var heading := fposmod(rad_to_deg(atan2(view.x, view.y)), 360.0)
	var out: Dictionary = {
		"x": sx,
		"y": sy_px,
		"inside": inside,
		"depth_km": depth,
		"view_km": _vec_array(view),
		"heading_deg": heading,
	}
	if not inside:
		var ex := clampf(sx, rx + EDGE_MARGIN_PX, rx + rw - EDGE_MARGIN_PX)
		var ey := clampf(sy_px, ry + EDGE_MARGIN_PX, ry + rh - EDGE_MARGIN_PX)
		out["edge"] = {
			"x": ex,
			"y": ey,
			"angle_deg": rad_to_deg(atan2(sx - cx, cy_px - sy_px)),
		}
		out["clamped_x"] = ex
		out["clamped_y"] = ey
	return out


static func _resolve_auto_scale(camera: Dictionary, contacts: Array, own_local: Vector3) -> void:
	if not bool(camera.get("auto_scale", false)):
		camera["scale_px_per_km"] = maxf(MIN_SCALE_PX_PER_KM,
			float(camera.get("scale_px_per_km", 1.0)))
		return
	var rect := _rect4(_as_array(camera.get("map_rect", DEFAULT_MAP_RECT)))
	var margin := float(camera.get("fit_margin", DEFAULT_FIT_MARGIN))
	var half_w: float = float(rect[2]) * 0.5 * margin
	var half_h: float = float(rect[3]) * 0.5 * margin
	var max_x := 1.0
	var max_y := 1.0
	for raw in contacts:
		if not (raw is Dictionary):
			continue
		var view := Types.to_vec3((raw as Dictionary).get("view_r_km", []))
		var yaw := deg_to_rad(float(camera.get("yaw_deg", DEFAULT_YAW_DEG)))
		var pitch := deg_to_rad(float(camera.get("pitch_deg", DEFAULT_PITCH_DEG)))
		var cy := cos(yaw)
		var sy := sin(yaw)
		var x1 := absf(cy * view.x + sy * view.y)
		var y1 := -sy * view.x + cy * view.y
		var y2 := absf(cos(pitch) * y1 - sin(pitch) * view.z)
		max_x = maxf(max_x, x1)
		max_y = maxf(max_y, y2)
	var scale_x := half_w / max_x
	var scale_y := half_h / max_y
	var scale := minf(scale_x, scale_y)
	camera["scale_px_per_km"] = clampf(scale, MIN_SCALE_PX_PER_KM, 12.0)


static func _project_contacts(contacts: Array, camera: Dictionary, own_local: Vector3,
		own_view: Dictionary) -> void:
	for raw in contacts:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var local_arr = c.get("local_r_km", null)
		if local_arr != null:
			c["screen"] = project_local(local_arr, camera, own_local)
		var bl: Dictionary = _as_dict(c.get("bearing_line", {}))
		if not bl.is_empty():
			var end_local = bl.get("endpoint_local_km", null)
			bl["endpoint_screen"] = project_local(end_local, camera, own_local) if end_local != null else {}
			c["bearing_line"] = bl
		# 轨道预测点列（30/60/120 s）：补 view_r_km 与屏幕投影建议。
		var pred: Dictionary = _as_dict(c.get("prediction", {}))
		if not pred.is_empty():
			var points: Array = _as_array(pred.get("points", []))
			for i in range(points.size()):
				var point: Dictionary = points[i]
				var plat = point.get("local_r_km", null)
				if plat == null:
					continue
				var pv: Vector3 = Types.to_vec3(plat) - own_local
				point["view_r_km"] = _vec_array(pv)
				point["screen"] = project_local(plat, camera, own_local)
				points[i] = point
			pred["points"] = points
			c["prediction"] = pred
		c["screen"] = c.get("screen", {})



static func _own_view(own_local: Vector3, camera: Dictionary) -> Dictionary:
	if String(camera.get("center_mode", "own")) == "datum":
		return project_local(Vector3.ZERO, camera, null)
	return project_local(own_local, camera, own_local)


# ── 2.3 雷达球 / TWS / 光学 / 暴露 ────────────────────────────────

static func _radar_section(world, sim: Dictionary, cfg: Dictionary, own_local: Vector3,
		contacts: Array) -> Dictionary:
	var radar = sim.get("radar", null)
	var rec = radar.record if radar != null and radar.record != null else _sim_radar_record(sim)
	if rec == null:
		return {"available": false, "reason": "sim_state 无雷达模型"}
	var enabled := bool(radar.enabled) if radar != null else false
	var seconds_on := float(radar.seconds_on) if radar != null else 0.0
	var ref_rcs := 10.0
	var jam := float(cfg.get("jamming", 0.0))
	var sphere: Dictionary = RadarModel.sphere_for(rec, own_local, ref_rcs, jam)
	sphere["center_local_km"] = _vec_array(own_local)
	sphere["enabled"] = enabled
	sphere["contacts_in_sphere"] = 0
	for raw in contacts:
		if raw is Dictionary and bool((raw as Dictionary).get("in_radar_sphere", false)):
			sphere["contacts_in_sphere"] = int(sphere["contacts_in_sphere"]) + 1
	var exposure: Dictionary = RadarModel.exposure_state(rec, seconds_on, {"on": enabled})
	return {
		"available": true,
		"model": String(rec.model),
		"kind": String(rec.kind),
		"enabled": enabled,
		"seconds_on": seconds_on,
		"scan_index": int(radar.scan_index) if radar != null else 0,
		"scan_period_s": float(radar.scan_period_s) if radar != null else float(rec.refresh_s),
		"scan_progress": float(radar.time_since_scan) / maxf(1.0e-6, float(rec.refresh_s)) if radar != null else 0.0,
		"sphere": sphere,
		"exposure": exposure,
		"tws_capacity": int(rec.track_capacity),
	}


static func _tws_section(sim: Dictionary) -> Dictionary:
	var tws = sim.get("tws", null)
	if tws == null:
		return {"available": false, "channels": [], "by_state": {}, "channel_count": 0,
			"active_count": 0, "reason": "sim_state 无 TWS 模型"}
	var channels_raw: Array = _as_array(tws.channels_export())
	var channels: Array = []
	var by_state: Dictionary = {}
	for raw in channels_raw:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var view := _tws_channel_view(ch)
		channels.append(view)
		var st := String(view.get("state", ""))
		by_state[st] = int(by_state.get(st, 0)) + 1
	var active := 0
	for raw2 in channels:
		if bool((raw2 as Dictionary).get("active", false)):
			active += 1
	return {
		"available": true,
		"enabled": bool(tws.is_enabled()),
		"model": String(tws.record.model) if tws.record != null else "",
		"scan_period_s": float(tws.scan_period_s),
		"max_channels": int(tws.max_channels),
		"stare_required_s": float(tws.stare_required_s),
		"state_machine": TwsModel.STATES.duplicate(),
		"channels": channels,
		"by_state": by_state,
		"channel_count": channels.size(),
		"active_count": active,
	}


static func _tws_channel_view(ch: Dictionary) -> Dictionary:
	var state := String(ch.get("state", ""))
	var active := state in ACTIVE_TWS_STATES
	return {
		"target_track_id": String(ch.get("target_id", "")),
		"state": state,
		"active": active,
		"lost_lock": state == "SEARCH" or state == "DETECT",
		"fire_control_ready": state == "FIRE_CONTROL",
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
		"stare_s": float(ch.get("stare_s", 0.0)),
		"stare_progress": float(ch.get("stare_progress", 0.0)),
		"slot": int(ch.get("slot", -1)),
		"fire_control": _as_dict(ch.get("fire_control", {})),
		"history": _as_array(ch.get("history", [])),
	}


static func _optical_section(sim: Dictionary) -> Dictionary:
	var opt = sim.get("optical", null)
	if opt == null:
		return {"available": false, "channels": [], "optical": [], "ir": [],
			"locked_count": 0, "reason": "sim_state 无光学模型"}
	var data: Dictionary = opt.to_dict()
	var channels: Array = []
	var optical: Array = []
	var ir: Array = []
	for raw in _as_array(data.get("channels", [])):
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var kind := String(ch.get("channel", ""))
		var view := {
			"channel": kind,
			"target_track_id": String(ch.get("target_id", "")),
			"status": String(ch.get("status", "")),
			"locked": bool(ch.get("locked", false)),
			"progress": float(ch.get("progress", 0.0)),
			"stare_s": float(ch.get("stare_s", 0.0)),
			"required_s": float(ch.get("required_s", 0.0)),
			"refresh_s": float(ch.get("refresh_s", 0.0)),
			"samples": int(ch.get("samples", 0)),
			"slant_range_km": float(ch.get("slant_range_km", -1.0)),
			"measured_range_km": float(ch.get("measured_range_km", -1.0)),
			"range_band": String(ch.get("range_band", "")),
			"bearing_deg": float(ch.get("bearing_deg", -1.0)),
			"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 0.0)),
			"illum": float(ch.get("illum", 1.0)),
			"level_support": int(ch.get("level_support", 0)),
			"classification": _as_dict(ch.get("classification", {})),
			"reason": String(ch.get("reason", "")),
		}
		channels.append(view)
		if kind == "optical":
			optical.append(view)
		else:
			ir.append(view)
	var by_status: Dictionary = _as_dict(data.get("by_status", {}))
	return {
		"available": true,
		"enabled": bool(opt.enabled),
		"channels": channels,
		"optical": optical,
		"ir": ir,
		"by_status": by_status,
		"locked_count": int(by_status.get("locked", 0)),
	}


static func _own_section(own, own_id: String, own_local: Vector3, own_state: Dictionary,
		camera: Dictionary, own_view: Dictionary, time_s: float, mode: String) -> Dictionary:
	var visual := entity_visual(own)
	var view := own_local - own_local
	var prediction := _prediction_for(own_state, time_s, mode, 4, 0.0)
	if not prediction.is_empty():
		var points: Array = _as_array(prediction.get("points", []))
		for i in range(points.size()):
			var point: Dictionary = points[i]
			var plat = point.get("local_r_km", null)
			if plat == null:
				continue
			point["view_r_km"] = _vec_array(Types.to_vec3(plat) - own_local)
			point["screen"] = project_local(plat, camera, own_local)
			points[i] = point
		prediction["points"] = points
	if own == null:
		return {"id": own_id, "available": false, "local_r_km": _vec_array(own_local),
			"screen": own_view, "orbit_source": String(own_state.get("source", ORBIT_SOURCE_NONE)),
			"prediction": prediction, "view_r_km": _vec_array(view)}
	return {
		"id": String(own.id),
		"available": true,
		"batch": String(own.batch),
		"name": String(own.name),
		"name_en": String(own.name_en),
		"class": String(own.cls),
		"role": String(own.role),
		"side": String(own.side),
		"kind": String(own.kind),
		"icon": visual.get("shape", "chevron"),
		"icon_meta": visual,
		"size_km": float(visual.get("size_km", 0.6)),
		"tags": _as_array(own.tags),
		"capabilities": _as_array(own.capabilities),
		"orbit_source": String(own_state.get("source", ORBIT_SOURCE_NONE)),
		"propagator": String(own_state.get("propagator", mode)),
		"fixed": bool(own_state.get("fixed", false)),
		"local_r_km": _vec_array(own_local),
		"view_r_km": _vec_array(view),
		"local_v_kmps": _vec_array(own_state.get("v", Vector3.ZERO)),
		"epoch_r_km": own_state.get("epoch_r", null),
		"epoch_v_kmps": own_state.get("epoch_v", null),
		"prediction": prediction,
		"screen": own_view,
	}



# ── 2.4 辅助 ─────────────────────────────────────────────────────

static func _tws_channel_for(sim: Dictionary, track_id: String) -> Dictionary:
	var tws = sim.get("tws", null)
	if tws == null or track_id == "":
		return {}
	var ch: Dictionary = tws.channel(track_id)
	if ch.is_empty():
		return {}
	return _tws_channel_view(ch)


static func _optical_channel_for(sim: Dictionary, kinds: Array, track_id: String) -> Dictionary:
	var opt = sim.get("optical", null)
	if opt == null or track_id == "":
		return {}
	var out: Dictionary = {}
	for kind in kinds:
		var ch: Dictionary = opt.channel(String(kind), track_id)
		if ch.is_empty():
			continue
		out[String(kind)] = {
			"channel": String(kind),
			"status": String(ch.get("status", "")),
			"locked": bool(ch.get("locked", false)),
			"progress": float(ch.get("progress", 0.0)),
			"level_support": int(ch.get("level_support", 0)),
		}
	return out


static func _sim_radar_record(sim: Dictionary) -> Variant:
	var radar = sim.get("radar", null)
	if radar != null and radar.record != null:
		return radar.record
	var records: Dictionary = _as_dict(sim.get("records", {}))
	if records.has("radar"):
		return Types.record_from_dict(_as_dict(records.get("radar", {})))
	return null


static func _build_notes(sim: Dictionary) -> Array:
	var notes: Array = [
		"build() 只读 world；不做渲染；screen 为投影建议（UI 可覆盖）",
		"位置/预测：Orbit.local_propagate_rk4（L1 局部相对运动）；预测点列 30/60/120 s；固定设施不推进",
	]
	notes.append_array(_as_array(sim.get("notes", [])))
	return notes



static func _own_entity(world):
	if world == null:
		return null
	if world.has_method("own"):
		return world.own()
	var oid := String(_world_field(world, "own_id", ""))
	if oid != "" and world.has_method("entity"):
		return world.entity(oid)
	return null


static func _is_own_row(world, row: Dictionary, entity_id: String) -> bool:
	var own_id := String(_world_field(world, "own_id", ""))
	if own_id == "":
		return false
	if entity_id != "" and entity_id == own_id:
		return true
	if String(row.get("id", "")) == own_id:
		return true
	var tags := _as_array(row.get("tags", []))
	return tags.has("own")


static func _entity_pos(entity) -> Vector3:
	if entity == null:
		return Vector3.ZERO
	var orbit := _as_dict(entity.orbit)
	if orbit.has("r"):
		return Types.to_vec3(orbit.get("r", Vector3.ZERO))
	return Types.to_vec3(entity.orbit)


static func _entity_rcs(entity) -> float:
	if entity == null:
		return 10.0
	var meta := _as_dict(entity.meta)
	if meta.has("rcs_m2"):
		return maxf(0.01, float(meta.get("rcs_m2", 10.0)))
	return 10.0


static func _rows_from_entities(world) -> Array:
	var out: Array = []
	if world == null:
		return out
	var own_id := String(_world_field(world, "own_id", ""))
	for e in _entity_list(world):
		if e == null:
			continue
		var eid := String(e.id)
		var row := {
			"track_id": eid,
			"entity_id": eid,
			"batch": String(e.batch),
			"name": String(e.name),
			"name_en": String(e.name_en),
			"class": String(e.cls),
			"role": String(e.role),
			"side": String(e.side),
			"faction": String(e.faction),
			"kind": String(e.kind),
			"has_entity": true,
			"level": int(e.track_level),
			"identity": String(e.identity),
			"threat": String(e.threat),
			"is_own": eid == own_id,
			"tags": _as_array(e.tags),
		}
		out.append(row)
	return out



static func _count_entities(contacts: Array) -> int:
	var n := 0
	for raw in contacts:
		if raw is Dictionary and bool((raw as Dictionary).get("has_entity", false)):
			n += 1
	return n


static func _count_bearing_only(contacts: Array) -> int:
	var n := 0
	for raw in contacts:
		if raw is Dictionary and bool((raw as Dictionary).get("bearing_only", false)):
			n += 1
	return n


static func _count_in_radar_sphere(contacts: Array) -> int:
	var n := 0
	for raw in contacts:
		if raw is Dictionary and bool((raw as Dictionary).get("in_radar_sphere", false)):
			n += 1
	return n


static func _count_kind(contacts: Array, kind: String) -> int:
	var n := 0
	for raw in contacts:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


static func _count_predicted(contacts: Array) -> int:
	var n := 0
	for raw in contacts:
		if raw is Dictionary:
			var pred: Dictionary = _as_dict((raw as Dictionary).get("prediction", {}))
			if not pred.is_empty():
				n += 1
	return n



static func _read_layers(world) -> Dictionary:
	if world != null and world.has_method("vm_layers"):
		return _as_dict(world.vm_layers())
	return _as_dict(_world_field(world, "layers", {}))


static func _entity_list(world) -> Array:
	if world == null:
		return []
	var v: Variant = world.get("entities")
	if v is Array:
		return v
	return []


static func _world_field(world, name: String, default_value: Variant) -> Variant:
	if world == null:
		return default_value
	var v: Variant = world.get(name)
	if v != null:
		return v
	return default_value


static func _world_time(world) -> float:
	return float(_world_field(world, "t", 0.0))


static func _scenario_field(world, name: String, default_value: String) -> String:
	var sc: Variant = _world_field(world, "scenario", null)
	if sc != null:
		var v: Variant = sc.get(name)
		if v != null:
			return String(v)
	return default_value


static func _scenario_datum(world) -> String:
	var datum := _scenario_field(world, "datum", "L1")
	return datum if datum != "" else "L1"


static func _track_field(tr, name: String, default_value: Variant) -> Variant:
	if tr == null:
		return default_value
	var v: Variant = tr.get(name)
	if v != null:
		return v
	return default_value


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}


static func _as_array(v: Variant) -> Array:
	if v is Array:
		return (v as Array).duplicate(true)
	return []


static func _rect4(raw: Array) -> Array:
	if raw.size() < 4:
		return DEFAULT_MAP_RECT.duplicate()
	return [float(raw[0]), float(raw[1]), maxf(1.0, float(raw[2])), maxf(1.0, float(raw[3]))]


static func _vec_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## 保证输出只含 JSON 基本类型（Vector3/Vector2/Color 等转数组/字符串）。
static func _json_ready(value: Variant) -> Variant:
	if value is Vector3:
		return _vec_array(value)
	if value is Vector2:
		return [value.x, value.y]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Dictionary:
		var out: Dictionary = {}
		for raw_key in (value as Dictionary).keys():
			out[String(raw_key)] = _json_ready((value as Dictionary)[raw_key])
		return out
	if value is Array:
		var arr: Array = []
		for item in (value as Array):
			arr.append(_json_ready(item))
		return arr
	return value


# ═══════════════════════════════════════════════════════════════════
# 3. step(world, dt, cfg)：推进 sim 模型，返回观测建议（不改 world）
# ═══════════════════════════════════════════════════════════════════

## 推进 dt：雷达扫描 / TWS 状态机 / 光学凝视；返回可注入 core 的观测建议与通道事件。
## **不修改 world**：不调用 world.advance/ingest/select/set_*；调用方自行决定是否应用。
## cfg 需含 "sim_state"（make_sim_state 的返回值，函数会原地推进其中的模型）。
static func step(world, dt: float, cfg: Dictionary = {}) -> Dictionary:
	# 注意：这里必须保留引用，step 会原地推进 sim_state（time/模型内部状态）。
	var sim_state: Dictionary = cfg.get("sim_state", {})
	if sim_state.is_empty():
		return {"ok": false, "schema": SCHEMA_STEP, "world_modified": false,
			"reason": "cfg.sim_state 为空：先调用 make_sim_state(world, cfg)"}
	var step_dt := maxf(0.0, dt)
	var sim_time := float(sim_state.get("time", 0.0)) + step_dt
	sim_state["time"] = sim_time
	var own_id := String(sim_state.get("observer_id", ""))
	var world_snapshot := build_world_snapshot(world, sim_state, cfg)
	var tws = sim_state.get("tws", null)
	var radar = sim_state.get("radar", null)
	var optical = sim_state.get("optical", null)

	var tws_out: Dictionary = {}
	var radar_out: Dictionary = {}
	var radar_scan_obs: Array = []
	var tws_obs: Array = []
	var channel_updates: Array = []

	if tws != null:
		tws_out = tws.step(step_dt, world_snapshot)
		radar_out = {
			"scanned": bool(tws_out.get("scanned", false)),
			"scan_index": int(tws_out.get("scan_index", 0)),
			"exposure": _as_dict(tws_out.get("exposure", {})),
			"sphere": _as_dict(tws_out.get("sphere", {})),
			"seconds_on": float(tws.radar.seconds_on) if tws.radar != null else 0.0,
		}
		if bool(tws_out.get("scanned", false)) and tws.radar != null:
			var last_scan: Dictionary = _as_dict(tws.radar.last_scan)
			radar_scan_obs = _core_observations_from_scan(
				_as_array(last_scan.get("observations", [])), own_id)
		var tws_sensor := ""
		if tws.record != null:
			tws_sensor = String(tws.record.model)
		tws_obs = _core_observations_from_tws_channels(
			_as_array(tws_out.get("channels", [])), own_id, tws_sensor)
		for raw in _as_array(tws_out.get("events", [])):
			if raw is Dictionary:
				var ev: Dictionary = (raw as Dictionary).duplicate(true)
				ev["source"] = "tws"
				channel_updates.append(ev)
	elif radar != null:
		radar_out = radar.step(step_dt, world_snapshot)
		if bool(radar_out.get("scanned", false)):
			radar_scan_obs = _core_observations_from_scan(
				_as_array(radar_out.get("observations", [])), own_id)
	else:
		return {"ok": false, "schema": SCHEMA_STEP, "world_modified": false,
			"reason": "sim_state 无 radar/tws 模型"}

	var optical_out: Dictionary = {}
	if optical != null:
		optical_out = optical.step(step_dt, world_snapshot)
		for raw2 in _as_array(optical_out.get("events", [])):
			if raw2 is Dictionary:
				var ev2: Dictionary = (raw2 as Dictionary).duplicate(true)
				ev2["source"] = "optical"
				channel_updates.append(ev2)

	var observations: Array = []
	observations.append_array(radar_scan_obs)
	observations.append_array(tws_obs)
	var snapshot := build(world, sim_state, cfg)
	var active_tws := int(_as_dict(snapshot.get("tws", {})).get("active_count", 0))
	return {
		"ok": true,
		"schema": SCHEMA_STEP,
		"t": _world_time(world),
		"sim_time": sim_time,
		"dt": step_dt,
		"world_modified": false,
		"boundary": "本函数只推进 sim_state 模型；不改 world。调用方自定是否 world.advance(dt) / world.ingest(obs)",
		"snapshot": snapshot,
		"observations": observations,
		"radar_observations": radar_scan_obs,
		"tws_observations": tws_obs,
		"channel_updates": channel_updates,
		"events": {
			"scanned": bool(radar_out.get("scanned", false)),
			"scan_index": int(radar_out.get("scan_index", 0)),
			"exposure": _as_dict(radar_out.get("exposure", {})),
			"optical_by_status": _as_dict(optical_out.get("by_status", {})),
		},
		"suggested_calls": _suggested_calls(sim_state, observations.size(), tws_obs.size()),
		"counts": {
			"observations": observations.size(),
			"radar_observations": radar_scan_obs.size(),
			"tws_observations": tws_obs.size(),
			"channel_updates": channel_updates.size(),
			"tws_channels": int(_as_dict(snapshot.get("tws", {})).get("channel_count", 0)),
			"tws_active": active_tws,
			"optical_locked": int(_as_dict(snapshot.get("optical", {})).get("locked_count", 0)),
		},
	}


static func _suggested_calls(sim_state: Dictionary, obs_count: int, tws_count: int) -> Array:
	var calls: Array = []
	if obs_count > 0:
		calls.append("world.advance(dt) 后按需 world.ingest(obs) 或 V2ObservationBridge.ingest_scan(world, scan)")
	if tws_count > 0:
		calls.append("V2ObservationBridge.ingest_tws_channels(world, tws.channels_export(), {source})")
	var opt = sim_state.get("optical", null)
	if opt != null:
		calls.append("光学锁定后按 docs/34 §8.6 用 kind=optical.classification + support=3 注入（可选）")
	return calls


# ═══════════════════════════════════════════════════════════════════
# 4. build_world_snapshot(world, sim_state, cfg)：给传感器模型的只读输入
# ═══════════════════════════════════════════════════════════════════

## 从 world 实体组装 world_snapshot（见 docs/34 §8.2）；目标 id 用航迹 id。
## 位置用 Orbit.local_propagate(_rk4) 传播到快照时间（world.t，可由 cfg.time_s 覆盖）。
## cfg["sim_targets"] 可覆盖目标行（测试/适配钩子，例如传 [] 验证失锁）。
static func build_world_snapshot(world, sim_state: Dictionary = {}, cfg: Dictionary = {}) -> Dictionary:
	var time_s := _snapshot_time(world, cfg)
	var mode := String(cfg.get("propagator", DEFAULT_PROPAGATOR))
	if mode != PROPAGATOR_TAYLOR:
		mode = PROPAGATOR_RK4
	var own = _own_entity(world)
	var own_state := _entity_state(own, time_s, mode)
	var own_local := _entity_pos(own)
	if bool(own_state.get("has_position", false)):
		own_local = own_state.get("r", own_local)
	var observer_id := String(own.id) if own != null else String(sim_state.get("observer_id", ""))
	var aux: Dictionary = _as_dict(sim_state)
	var sim_time := float(aux.get("time", _world_time(world)))
	var snap: Dictionary = {
		"t": time_s,
		"sim_time": sim_time,
		"orbit_source": ORBIT_SOURCE,
		"propagator": mode,
		"observer": {
			"id": observer_id,
			"pos_km": _vec_array(own_local),
			"v_kmps": _vec_array(own_state.get("v", Vector3.ZERO)),
			"orbit_source": String(own_state.get("source", ORBIT_SOURCE_NONE)),
			"maneuver_g": float(cfg.get("maneuver_g", 0.0)),
		},
		"targets": [],
		"sun_illum": float(cfg.get("sun_illum", 1.0)),
		"jamming": float(cfg.get("jamming", 0.0)),
		"shadow": bool(cfg.get("shadow", false)),
		"los": bool(cfg.get("los", true)),
	}
	if cfg.has("sim_targets") and cfg.get("sim_targets") is Array:
		snap["targets"] = (cfg.get("sim_targets") as Array).duplicate(true)
		return snap
	if world == null:
		return snap
	var rows: Array = []
	for e in _entity_list(world):
		if e == null or String(e.id) == observer_id:
			continue
		var tr = null
		if world.has_method("track_for"):
			tr = world.track_for(String(e.id))
		var row: Dictionary = _target_row(e, tr, time_s, mode)
		# sim 目标标识用航迹 id（与 V2ObservationBridge.target_row 字段对齐）；缺航迹时退回实体 id。
		if String(row.get("id", "")) == "":
			row["id"] = String(e.id)
		rows.append(row)
	snap["targets"] = rows
	return snap


# ═══════════════════════════════════════════════════════════════════
# 5. core 观测建议（字段与 docs/v2_core_interface.md §2 对齐）
#    不 import observation_bridge：只读快照层保持低耦合（sim→core 单向）；
#    建议由调用方自行交给 world.ingest / V2ObservationBridge。
# ═══════════════════════════════════════════════════════════════════

## 与 V2ObservationBridge.target_row() 字段对齐的 sim 输入目标行（core 侧为权威定义）。
## 传播态写 `r`/`v`（传感器模型用当前时刻位置），epoch 原值写 `epoch_r`/`epoch_v`。
static func _target_row(entity, track, time_s: float = 0.0,
		mode: String = DEFAULT_PROPAGATOR) -> Dictionary:
	var row: Dictionary = {
		"id": String(track.id) if track != null else (String(entity.batch) if entity != null else ""),
		"track_id": String(track.id) if track != null else "",
		"entity_id": String(entity.id) if entity != null else "",
		"batch": String(entity.batch) if entity != null else "",
		"side": String(entity.side) if entity != null else "unknown",
		"kind": String(entity.kind) if entity != null else "contact",
		"name": String(entity.name) if entity != null else "",
		"class": String(entity.cls) if entity != null else "",
	}
	if entity != null:
		row["classification"] = {
			"ship_class": String(entity.cls),
			"role": String(entity.role),
			"faction": String(entity.faction),
		}
		var meta := _as_dict(entity.meta)
		if meta.has("builder"):
			row["classification"]["builder"] = String(meta.get("builder", ""))
		for extra in ["rcs_m2", "transponder", "iff_code", "temp_k", "area_m2"]:
			if meta.has(extra):
				row[extra] = meta[extra]
		var orbit := _as_dict(entity.orbit)
		if not orbit.is_empty():
			row["orbit"] = orbit
			if orbit.has("r"):
				row["epoch_r"] = _as_array(orbit.get("r", []))
			if orbit.has("v"):
				row["epoch_v"] = _as_array(orbit.get("v", []))
		var state := _entity_state(entity, time_s, mode)
		row["orbit_source"] = String(state.get("source", ORBIT_SOURCE_NONE))
		row["propagator"] = String(state.get("propagator", "none"))
		row["fixed"] = bool(state.get("fixed", false))
		if bool(state.get("has_position", false)):
			row["r"] = _vec_array(state.get("r", Vector3.ZERO))
			row["v"] = _vec_array(state.get("v", Vector3.ZERO))
	if track != null:
		row["range_km"] = float(track.range_km)
		row["bearing_deg"] = float(track.bearing_deg)
	return row



## 雷达扫描观测 → core 观测建议（只保留 detected；target_id → track_id）。
static func _core_observations_from_scan(observations: Array, source: String) -> Array:
	var out: Array = []
	for raw in observations:
		if not (raw is Dictionary):
			continue
		var det: Dictionary = raw
		if not bool(det.get("detected", false)):
			continue
		var obs := _core_observation(det, source)
		if obs.is_empty():
			continue
		out.append(obs)
	return out


## TWS 通道 → core 观测建议（只注入可跟踪通道；失锁/SEARCH/DETECT 过滤）。
## 映射规则与 docs/34 §8.6 / observation_bridge.tws_channel_to_observation 一致。
static func _core_observations_from_tws_channels(channels: Array, source: String,
		sensor: String = "") -> Array:
	var out: Array = []
	for raw in channels:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		var state := String(ch.get("state", ""))
		if not (state in ACTIVE_TWS_STATES):
			continue
		var det: Dictionary = {
			"detected": true,
			"kind": "radar.tws",
			"sensor": sensor,
			"t": float(ch.get("t", -1.0)),
			"quality": float(ch.get("quality", 0.0)),
			"support": 2,
			"bearing_deg": float(ch.get("bearing_deg", -1.0)),
			"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 1.0)),
			"range_km": float(ch.get("range_km", -1.0)),
			"range_sigma_km": float(ch.get("range_sigma_km", -1.0)),
			"target_id": String(ch.get("target_id", "")),
			"notes": ["TWS state=%s age=%.1fs update=%.2fHz stable=%s" % [
				state, float(ch.get("age_s", 0.0)),
				float(ch.get("update_rate_hz", 0.0)),
				str(bool(ch.get("stable_track", false)))]],
			"channel_state": state,
			"fire_control": _as_dict(ch.get("fire_control", {})),
		}
		var obs := _core_observation(det, source)
		if obs.is_empty():
			continue
		out.append(obs)
	return out


## 单条传感器观测 → V2 core 观测 schema（字段见 docs/v2_core_interface.md §2）。
static func _core_observation(det: Dictionary, source: String) -> Dictionary:
	var obs: Dictionary = {
		"detected": bool(det.get("detected", false)),
		"kind": String(det.get("kind", "")),
		"sensor": String(det.get("sensor", det.get("sensor_id", ""))),
		"source": source,
		"t": float(det.get("t", -1.0)),
	}
	if det.has("quality"):
		obs["quality"] = float(det.get("quality", 0.0))
	var support: Variant = det.get("support", det.get("level_support", null))
	if support != null:
		obs["support"] = int(support)
	for key in ["bearing_deg", "bearing_sigma_deg", "range_km", "range_sigma_km",
			"range_band", "radial_vel_kmps"]:
		if det.has(key):
			obs[key] = det[key]
	if det.has("classification") and det.get("classification") is Dictionary:
		obs["classification"] = _as_dict(det.get("classification", {}))
	if det.has("identity") and det.get("identity") is Dictionary:
		obs["identity"] = _as_dict(det.get("identity", {}))
	if det.has("iff_status"):
		obs["iff_status"] = String(det.get("iff_status", ""))
	if det.has("signal") and det.get("signal") is Dictionary:
		obs["signal"] = _as_dict(det.get("signal", {}))
	if det.has("notes") and det.get("notes") is Array:
		obs["notes"] = _as_array(det.get("notes", []))
	if det.has("reason"):
		obs["reason"] = String(det.get("reason", ""))
	if det.has("channel_state"):
		obs["channel_state"] = String(det.get("channel_state", ""))
	if det.has("fire_control") and det.get("fire_control") is Dictionary:
		obs["fire_control"] = _as_dict(det.get("fire_control", {}))
	# 目标标识：entity_id > track_id > target_id（雷达观测的 target_id 即航迹 id）。
	var entity_id := String(det.get("entity_id", ""))
	var track_id := String(det.get("track_id", ""))
	var target_id := String(det.get("target_id", det.get("batch", "")))
	if entity_id != "":
		obs["entity_id"] = entity_id
	elif track_id != "":
		obs["track_id"] = track_id
	elif target_id != "":
		obs["track_id"] = target_id
	else:
		return {}
	return obs

