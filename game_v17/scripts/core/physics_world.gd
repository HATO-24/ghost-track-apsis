extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2L：PhysicsWorld（单一权威物理世界；新文件）
#
# - 单一权威：实体轨道状态（r/v/mass/attitude）+ 固定步长 tick + 时间；
# - CR3BP 地月（barycenter rotating）+ 可选太阳第三体（V2CompactEphemeris，
#   无表时 analytic fallback / 内置太阳近似）；
# - 内部用 float（GDScript double）数组做 RK4，不经过 Vector3 精度损失；
# - API：setup/upsert_entity/remove_entity/step/set_time/state/state_at/
#   snapshot/save_state/load_state；拒绝 NaN/负质量/未知实体；
# - 轨迹采样/事件（防重复）；不写 UI/TrackTable/命令/world/V15。
# ═══════════════════════════════════════════════════════════════════

const Physics := preload("res://framework/sim/cislunar_physics.gd")
const EphemerisScript := preload("res://framework/sim/ephemeris_compact.gd")

const SCHEMA := "v17.physics_world.v1"
const SAVE_SCHEMA := "v17.physics_world_save.v1"
const VERSION := "1.0.0"
const FRAME := "bary_rot"
const ALT_FRAMES := ["earth_eci", "earth_rot"]
const STEP_DEFAULT := 60.0
const STEP_MAX := 60.0
const MAX_STEPS_DEFAULT := 100000
const MAX_ENTITIES := 256
const MAX_EVENTS := 500
const MAX_SAMPLES := 512
const MU_SUN := 1.32712440018e11
const AU_KM := 149597870.7
const SUN_YEAR_S := 365.256363004 * 86400.0
const ENTITY_ID_PATTERN := "^[A-Za-z0-9_.-]+$"
const JACOBI_TOL := 1.0e-6

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var step_s := STEP_DEFAULT
var max_steps := MAX_STEPS_DEFAULT
var t := 0.0
var entities: Dictionary = {}        # id -> entity dict（r/v 为 double 数组）
var samples: Array = []
var events: Array = []
var _event_seq := 0
var _event_keys: Dictionary = {}

var ephemeris = null
var ephemeris_path := ""
var sun_enabled := false
var sun_mode := "ephemeris_or_analytic"
var record_samples := true
var max_samples := MAX_SAMPLES
var jacobi_tol := JACOBI_TOL

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	step_s = float(c.get("step_s", STEP_DEFAULT))
	max_steps = int(c.get("max_steps", MAX_STEPS_DEFAULT))
	t = float(c.get("t", 0.0))
	entities = {}
	samples = []
	events = []
	_event_seq = 0
	_event_keys = {}
	sun_enabled = bool(c.get("sun", c.get("third_body", false)))
	record_samples = bool(c.get("record_samples", true))
	max_samples = maxi(16, int(c.get("max_samples", MAX_SAMPLES)))
	jacobi_tol = float(c.get("jacobi_tol", JACOBI_TOL))
	ephemeris_path = String(c.get("ephemeris_path", ""))
	if c.get("ephemeris", null) != null:
		ephemeris = c.get("ephemeris")
	else:
		ephemeris = EphemerisScript.new(ephemeris_path)
	if not is_finite(step_s) or step_s <= 0.0 or step_s > STEP_MAX:
		errors.append("step_s 必须在 (0, %.0f] 秒内" % STEP_MAX)
	if max_steps <= 0:
		errors.append("max_steps 必须 >0")
	if not is_finite(t) or t < 0.0:
		errors.append("t 必须有限且 >=0")
	if not errors.is_empty():
		return false
	ready = true
	_emit_once("physics.world_ready", "ready", {"step_s": step_s,
		"frame": FRAME, "sun": sun_enabled})
	return true

# ── 帧 / 单位 / 常数 ───────────────────────────────────────────

func frame() -> String:
	return FRAME

func units() -> Dictionary:
	return {"length": "km", "time": "s", "velocity": "km/s",
		"mass": "kg", "angle": "deg", "attitude": "quaternion_wxyz"}

func constants() -> Dictionary:
	return {"mu_earth_km3_s2": Physics.MU_EARTH_KM3_S2,
		"mu_moon_km3_s2": Physics.MU_MOON_KM3_S2,
		"d_km": Physics.D_KM, "mu_ratio": Physics.mu_moon_ratio(),
		"omega_rad_s": Physics.moon_mean_motion(),
		"mu_sun_km3_s2": MU_SUN, "au_km": AU_KM}

func _mu() -> float:
	return Physics.mu_moon_ratio()

func _omega() -> float:
	return Physics.moon_mean_motion()

func _earth_pos() -> Array:
	return [-_mu() * Physics.D_KM, 0.0, 0.0]

func _moon_pos() -> Array:
	return [(1.0 - _mu()) * Physics.D_KM, 0.0, 0.0]

# ── 实体 ────────────────────────────────────────────────────────

## 新增/更新实体：data = {r,v,mass_kg,attitude,frame}（也接受 position_km/velocity_kmps）。
func upsert_entity(entity_id: String, data: Dictionary) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PhysicsWorld 未 ready")
	if not _id_ok(entity_id):
		return _fail("invalid_entity_id", "precondition: 实体 id 非法：" + entity_id)
	if not (data is Dictionary):
		return _fail("invalid_data", "precondition: entity data 必须是对象")
	var d: Dictionary = data
	var st = _extract_state(d)
	if not (st is Dictionary):
		return _fail("invalid_state", "precondition: 缺少合法 r/v")
	var frame_in := String(d.get("frame", FRAME))
	if not (frame_in == FRAME or frame_in in ALT_FRAMES):
		return _fail("invalid_frame", "precondition: 非法帧：" + frame_in)
	var r: Array = (st as Dictionary).get("r", [])
	var v: Array = (st as Dictionary).get("v", [])
	if not _finite_vec3(r):
		return _fail("invalid_state", "precondition: r 必须为有限三维数组")
	if not _finite_vec3(v):
		return _fail("invalid_state", "precondition: v 必须为有限三维数组")
	var conv: Dictionary = _to_bary_rot(r, v, frame_in)
	if not bool(conv.get("ok", false)):
		return _fail("frame_conversion_failed", String(conv.get("reason", "帧转换失败")))
	r = conv.get("r", [])
	v = conv.get("v", [])
	var mass := float(d.get("mass_kg", d.get("mass", 1000.0)))
	if not is_finite(mass) or mass <= 0.0:
		return _fail("invalid_mass", "precondition: 质量必须有限且 >0")
	var attitude = d.get("attitude", [1.0, 0.0, 0.0, 0.0])
	if not (attitude is Array) or (attitude as Array).size() != 4:
		return _fail("invalid_attitude", "precondition: attitude 必须是四元数数组")
	for comp in (attitude as Array):
		if not is_finite(float(comp)):
			return _fail("invalid_attitude", "precondition: attitude 含 NaN/Inf")
	var is_new := not entities.has(entity_id)
	var created_t := t
	if not is_new:
		created_t = float((entities[entity_id] as Dictionary).get("created_t", t))
	var ent := {
		"id": entity_id,
		"r": [float(r[0]), float(r[1]), float(r[2])],
		"v": [float(v[0]), float(v[1]), float(v[2])],
		"mass_kg": mass,
		"attitude": [(attitude as Array)[0], (attitude as Array)[1],
			(attitude as Array)[2], (attitude as Array)[3]],
		"frame": FRAME, "input_frame": frame_in,
		"created_t": created_t, "updated_t": t,
		"jacobi0": _jacobi_arrays(r, v),
		"version": (int((entities[entity_id] as Dictionary).get("version", 0)) + 1) if not is_new else 1,
	}
	entities[entity_id] = ent
	if is_new:
		_emit_once("physics.entity_added", "entity:" + entity_id,
			{"id": entity_id})
	else:
		_emit_once("physics.entity_updated", "entity_update:%s:%s" % [entity_id, str(t)],
			{"id": entity_id})
	_check_contracts()
	return {"ok": true, "id": entity_id, "created": is_new,
		"entity": _entity_copy(ent), "state": state(entity_id, FRAME)}

func remove_entity(entity_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PhysicsWorld 未 ready")
	if not entities.has(entity_id):
		return _fail("unknown_entity", "precondition: 未知实体：" + entity_id)
	entities.erase(entity_id)
	_emit_once("physics.entity_removed", "entity_removed:" + entity_id,
		{"id": entity_id})
	return {"ok": true, "id": entity_id, "removed": true}

func entity_ids() -> Array:
	var out: Array = entities.keys()
	out.sort()
	return out

func entity_count() -> int:
	return entities.size()

func entities_text() -> Array:
	var out: Array = []
	for id in entity_ids():
		out.append(_entity_copy(entities[id]))
	return out

func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)

# ── 时间 / 步进 ────────────────────────────────────────────────

## 固定步长推进：dt 秒拆成 n=ceil(dt/step_s) 步（每步 <=step_s）。
func step(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PhysicsWorld 未 ready")
	if not is_finite(dt) or dt < 0.0:
		return _fail("invalid_dt", "precondition: dt 必须有限且 >=0")
	_emit_once("physics.step_started", "step_start:%s" % str(t),
		{"t": t, "dt": dt, "entities": entities.size()})
	if dt == 0.0:
		return {"ok": true, "t": t, "steps": 0, "step_s": step_s,
			"entities": states(), "warnings": [], "samples_added": 0}
	var h := step_s
	var n := int(ceil(dt / h))
	if n > max_steps:
		return _fail("max_steps_exceeded", "precondition: 需要 %d 步 > max_steps %d" % [n, max_steps])
	h = dt / float(n)
	var warn: Array = []
	var samples_added := 0
	for i in range(n):
		var step_t := t + h * float(i + 1)
		for id in entities.keys():
			var ent: Dictionary = entities[id]
			var nxt: Dictionary = _rk4(ent["r"], ent["v"], h)
			if not _finite_vec3(nxt.get("r", [])) or not _finite_vec3(nxt.get("v", [])):
				warn.append("entity %s RK4 发散" % String(id))
				_emit_once("physics.diverged", "diverged:%s:%s" % [String(id), str(step_t)],
					{"id": String(id), "t": step_t})
				continue
			ent["r"] = nxt["r"]
			ent["v"] = nxt["v"]
			ent["updated_t"] = step_t
		if record_samples:
			_write_sample(step_t)
			samples_added += 1
	t += dt
	# Jacobi 漂移 / 能量诊断（双精度）
	for id2 in entity_ids():
		var ent2: Dictionary = entities[id2]
		var jac := _jacobi_arrays(ent2["r"], ent2["v"])
		ent2["jacobi"] = jac
		var drift := absf(jac - float(ent2.get("jacobi0", jac)))
		ent2["jacobi_drift"] = drift
		if is_finite(jac) and not is_finite(float(ent2.get("jacobi0", jac))):
			continue
		if is_finite(drift) and drift > jacobi_tol:
			warn.append("entity %s Jacobi 漂移 %s" % [String(id2), str(drift)])
			_emit_once("physics.jacobi_drift", "drift:%s:%s" % [String(id2), str(t)],
				{"id": String(id2), "drift": drift})
	_emit_once("physics.step_completed", "step:%s" % str(t),
		{"t": t, "dt": dt, "steps": n, "step_s": h})
	_check_contracts()
	return {"ok": true, "t": t, "steps": n, "step_s": h,
		"entities": states(), "warnings": warn, "samples_added": samples_added}

func set_time(new_t: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PhysicsWorld 未 ready")
	if not is_finite(new_t) or new_t < 0.0:
		return _fail("invalid_time", "precondition: t 必须有限且 >=0")
	if new_t + 1.0e-9 < t:
		return _fail("time_regression", "precondition: 不允许时间回退")
	t = new_t
	samples = []
	_emit_once("physics.time_set", "time:%s" % str(t), {"t": t})
	_check_contracts()
	return {"ok": true, "t": t}

# ── 状态 / 采样 ────────────────────────────────────────────────

## 实体状态（默认旋转系；支持 earth_eci/earth_rot 输出）。
func state(entity_id: String, out_frame := FRAME) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	if not entities.has(entity_id):
		return {"ok": false, "reason": "unknown_entity", "id": entity_id}
	if not (out_frame == FRAME or out_frame in ALT_FRAMES):
		return {"ok": false, "reason": "invalid_frame"}
	var ent: Dictionary = entities[entity_id]
	var r: Array = (ent["r"] as Array).duplicate()
	var v: Array = (ent["v"] as Array).duplicate()
	if out_frame != FRAME:
		var conv: Dictionary = _from_bary_rot(r, v, out_frame)
		if not bool(conv.get("ok", false)):
			return {"ok": false, "reason": String(conv.get("reason", ""))}
		r = conv.get("r", [])
		v = conv.get("v", [])
	var speed := sqrt(float(r[0]) * 0 + float(v[0]) * float(v[0])
		+ float(v[1]) * float(v[1]) + float(v[2]) * float(v[2]))
	return {
		"schema": "physics_entity_state.v1", "id": entity_id,
		"t": t, "frame": out_frame, "units": units(),
		"r": r, "v": v, "speed_kmps": speed,
		"mass_kg": float(ent.get("mass_kg", 0.0)),
		"attitude": (ent.get("attitude", []) as Array).duplicate(),
		"jacobi": _jacobi_arrays(ent["r"], ent["v"]),
		"energy_km2_s2": _energy_arrays(ent["r"], ent["v"]),
		"writes": {"world": false, "v15": false, "track_table": false, "ui": false},
	}

## 所有实体状态（按 id 排序；只读副本）。
func states(out_frame := FRAME) -> Array:
	var out: Array = []
	for id in entity_ids():
		out.append(state(String(id), out_frame))
	return out

## 绝对时间状态：向前推进到 target_t（不允许回退）；会推进世界时间。
func state_at(entity_id: String, target_t: float, out_frame := FRAME) -> Dictionary:
	if not ready:
		return {}
	if not is_finite(target_t) or target_t < 0.0:
		return {"ok": false, "reason": "invalid_time"}
	if target_t + 1.0e-9 < t:
		return {"ok": false, "reason": "time_regression", "t": t}
	if target_t > t:
		var res: Dictionary = step(target_t - t)
		if not bool(res.get("ok", false)):
			return res
	if not entities.has(entity_id):
		return {"ok": false, "reason": "unknown_entity"}
	return state(entity_id, out_frame)

func trajectory(entity_id: String, out_frame := FRAME) -> Array:
	if not entities.has(entity_id):
		return []
	var out: Array = []
	for raw in samples:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var st: Dictionary = (row.get("states", {}) as Dictionary).get(entity_id, {})
		if st.is_empty():
			continue
		var r: Array = (st.get("r", []) as Array).duplicate()
		var v: Array = (st.get("v", []) as Array).duplicate()
		if out_frame != FRAME:
			var conv: Dictionary = _from_bary_rot(r, v, out_frame)
			if bool(conv.get("ok", false)):
				r = conv.get("r", [])
				v = conv.get("v", [])
		out.append({"t": float(row.get("t", 0.0)), "r": r, "v": v,
			"frame": out_frame})
	return out

func samples_count() -> int:
	return samples.size()

func energy(entity_id: String) -> float:
	if not entities.has(entity_id):
		return NAN
	var ent: Dictionary = entities[entity_id]
	return _energy_arrays(ent["r"], ent["v"])

func jacobi(entity_id: String) -> float:
	if not entities.has(entity_id):
		return NAN
	var ent: Dictionary = entities[entity_id]
	return _jacobi_arrays(ent["r"], ent["v"])

func _write_sample(step_t: float) -> void:
	var states_map: Dictionary = {}
	for id in entities.keys():
		var ent: Dictionary = entities[id]
		states_map[String(id)] = {"r": (ent["r"] as Array).duplicate(),
			"v": (ent["v"] as Array).duplicate()}
	samples.append({"t": step_t, "states": states_map})
	while samples.size() > max_samples:
		samples.pop_front()

# ── 公历/星历接口（可选太阳第三体）────────────────────────────

func ephemeris_summary() -> Dictionary:
	if ephemeris == null:
		return {"available": false, "fallback": true, "bodies": []}
	var bodies: Array = []
	if ephemeris.has_method("bodies"):
		bodies = ephemeris.bodies()
	var win: Dictionary = {}
	if ephemeris.get("time_window") is Dictionary:
		win = (ephemeris.get("time_window") as Dictionary).duplicate(true)
	return {"available": bool(ephemeris.available()) if ephemeris.has_method("available") else false,
		"using_analytic": bool(ephemeris.using_analytic_fallback())
			if ephemeris.has_method("using_analytic_fallback") else true,
		"frame": String(ephemeris.get("frame")) if ephemeris.get("frame") != null else "",
		"time_window": win, "bodies": bodies.duplicate(true),
		"path": ephemeris_path}

## 星历查询（earth/moon；太阳无表时 analytic 近似）；返回 earth_eci 位置/速度。
func ephemeris_state(body_id: String, at_t: float = -1.0) -> Dictionary:
	var qt := t if at_t < 0.0 else at_t
	if not is_finite(qt) or qt < 0.0:
		return {"ok": false, "reason": "invalid_time"}
	if ephemeris != null and ephemeris.has_method("body_state"):
		var st: Dictionary = ephemeris.body_state(body_id, qt)
		if bool(st.get("ok", false)):
			return st
	if String(body_id).to_lower() in ["sun", "sol"]:
		return _sun_state_analytic(qt)
	return {"ok": false, "reason": "unknown_body", "body": body_id}

## 太阳位置（地球惯性系；analytic 圆轨道 1 AU）。
func _sun_state_analytic(at_t: float) -> Dictionary:
	var n := TAU / SUN_YEAR_S
	var ang := n * at_t
	var pos := [AU_KM * cos(ang), AU_KM * sin(ang), 0.0]
	var vel := [-AU_KM * n * sin(ang), AU_KM * n * cos(ang), 0.0]
	return {"ok": true, "body": "sun", "t": at_t, "frame": "earth_eci",
		"position_km": pos, "velocity_kmps": vel, "speed_kmps": sqrt(
			vel[0] * vel[0] + vel[1] * vel[1]),
		"source": "analytic_sun", "analytic_fallback": true, "available": false}

## 太阳在旋转系位置（可选第三体扰动用）。
func _sun_pos_bary_rot(at_t: float) -> Array:
	if ephemeris != null and ephemeris.has_method("body_state"):
		var st: Dictionary = ephemeris.body_state("sun", at_t)
		if bool(st.get("ok", false)):
			var pos = st.get("position_km", [])
			if pos is Array and (pos as Array).size() >= 3:
				var frame_s := String(st.get("frame", "earth_eci"))
				var arr := [float(pos[0]), float(pos[1]), float(pos[2])]
				if frame_s == "earth_eci":
					var conv: Dictionary = _to_bary_rot(arr, [0.0, 0.0, 0.0], "earth_eci")
					if bool(conv.get("ok", false)):
						return conv.get("r", [])
				elif frame_s == "earth_rot":
					var conv2: Dictionary = _to_bary_rot(arr, [0.0, 0.0, 0.0], "earth_rot")
					if bool(conv2.get("ok", false)):
						return conv2.get("r", [])
				else:
					return arr
	var ana: Dictionary = _sun_state_analytic(at_t)
	var conv3: Dictionary = _to_bary_rot(ana["position_km"], [0.0, 0.0, 0.0], "earth_eci")
	return conv3.get("r", [AU_KM, 0.0, 0.0])

# ── 双精度 RK4 / 加速度 ───────────────────────────────────────

func _accel(r: Array, v: Array, at_t: float) -> Array:
	var x := float(r[0]); var y := float(r[1]); var z := float(r[2])
	var vx := float(v[0]); var vy := float(v[1]); var vz := float(v[2])
	var mu := _mu()
	var d := Physics.D_KM
	var ex := -mu * d
	var mx := (1.0 - mu) * d
	var rxe := x - ex; var rye := y; var rze := z
	var rxm := x - mx; var rym := y; var rzm := z
	var d1 := maxf(1.0, sqrt(rxe * rxe + rye * rye + rze * rze))
	var d2 := maxf(1.0, sqrt(rxm * rxm + rym * rym + rzm * rzm))
	var inv1 := 1.0 / (d1 * d1 * d1)
	var inv2 := 1.0 / (d2 * d2 * d2)
	var n := _omega()
	var ax := -Physics.MU_EARTH_KM3_S2 * rxe * inv1 - Physics.MU_MOON_KM3_S2 * rxm * inv2
	var ay := -Physics.MU_EARTH_KM3_S2 * rye * inv1 - Physics.MU_MOON_KM3_S2 * rym * inv2
	var az := -Physics.MU_EARTH_KM3_S2 * rze * inv1 - Physics.MU_MOON_KM3_S2 * rzm * inv2
	ax += n * n * x + 2.0 * n * vy
	ay += n * n * y - 2.0 * n * vx
	if sun_enabled:
		var sun := _sun_pos_bary_rot(at_t)
		var sx := x - float(sun[0]); var sy := y - float(sun[1]); var sz := z - float(sun[2])
		var rs := maxf(1.0, sqrt(sx * sx + sy * sy + sz * sz))
		var r0 := maxf(1.0, sqrt(float(sun[0]) * float(sun[0])
			+ float(sun[1]) * float(sun[1]) + float(sun[2]) * float(sun[2])))
		var invs := 1.0 / (rs * rs * rs)
		var inv0 := 1.0 / (r0 * r0 * r0)
		# 第三体微分加速度：μsun*((sun-r)/|sun-r|³ - sun/|sun|³)
		ax += MU_SUN * (sx * invs - float(sun[0]) * inv0)
		ay += MU_SUN * (sy * invs - float(sun[1]) * inv0)
		az += MU_SUN * (sz * invs - float(sun[2]) * inv0)
	return [ax, ay, az]

func _deriv(r: Array, v: Array, at_t: float) -> Dictionary:
	return {"dr": v.duplicate(), "dv": _accel(r, v, at_t)}

func _rk4(r: Array, v: Array, dt: float) -> Dictionary:
	var k1 := _deriv(r, v, t)
	var r2: Array = [float(r[0]) + 0.5 * dt * float((k1["dr"] as Array)[0]),
		float(r[1]) + 0.5 * dt * float((k1["dr"] as Array)[1]),
		float(r[2]) + 0.5 * dt * float((k1["dr"] as Array)[2])]
	var v2: Array = [float(v[0]) + 0.5 * dt * float((k1["dv"] as Array)[0]),
		float(v[1]) + 0.5 * dt * float((k1["dv"] as Array)[1]),
		float(v[2]) + 0.5 * dt * float((k1["dv"] as Array)[2])]
	var k2 := _deriv(r2, v2, t + 0.5 * dt)
	var r3: Array = [float(r[0]) + 0.5 * dt * float((k2["dr"] as Array)[0]),
		float(r[1]) + 0.5 * dt * float((k2["dr"] as Array)[1]),
		float(r[2]) + 0.5 * dt * float((k2["dr"] as Array)[2])]
	var v3: Array = [float(v[0]) + 0.5 * dt * float((k2["dv"] as Array)[0]),
		float(v[1]) + 0.5 * dt * float((k2["dv"] as Array)[1]),
		float(v[2]) + 0.5 * dt * float((k2["dv"] as Array)[2])]
	var k3 := _deriv(r3, v3, t + 0.5 * dt)
	var r4: Array = [float(r[0]) + dt * float((k3["dr"] as Array)[0]),
		float(r[1]) + dt * float((k3["dr"] as Array)[1]),
		float(r[2]) + dt * float((k3["dr"] as Array)[2])]
	var v4: Array = [float(v[0]) + dt * float((k3["dv"] as Array)[0]),
		float(v[1]) + dt * float((k3["dv"] as Array)[1]),
		float(v[2]) + dt * float((k3["dv"] as Array)[2])]
	var k4 := _deriv(r4, v4, t + dt)
	var nr: Array = []
	var nv: Array = []
	for i in range(3):
		nr.append(float(r[i]) + dt / 6.0 * (float((k1["dr"] as Array)[i])
			+ 2.0 * float((k2["dr"] as Array)[i])
			+ 2.0 * float((k3["dr"] as Array)[i])
			+ float((k4["dr"] as Array)[i])))
		nv.append(float(v[i]) + dt / 6.0 * (float((k1["dv"] as Array)[i])
			+ 2.0 * float((k2["dv"] as Array)[i])
			+ 2.0 * float((k3["dv"] as Array)[i])
			+ float((k4["dv"] as Array)[i])))
	return {"r": nr, "v": nv}

func _effective_potential_arrays(r: Array, v: Array) -> float:
	var x := float(r[0]); var y := float(r[1]); var z := float(r[2])
	var ex := _earth_pos(); var mx := _moon_pos()
	var d1 := maxf(1.0, sqrt(pow(x - float(ex[0]), 2.0) + pow(y - float(ex[1]), 2.0)
		+ pow(z - float(ex[2]), 2.0)))
	var d2 := maxf(1.0, sqrt(pow(x - float(mx[0]), 2.0) + pow(y - float(mx[1]), 2.0)
		+ pow(z - float(mx[2]), 2.0)))
	var n := _omega()
	return 0.5 * n * n * (x * x + y * y) + Physics.MU_EARTH_KM3_S2 / d1 \
		+ Physics.MU_MOON_KM3_S2 / d2

func _energy_arrays(r: Array, v: Array) -> float:
	var speed2 := float(v[0]) * float(v[0]) + float(v[1]) * float(v[1]) \
		+ float(v[2]) * float(v[2])
	return 0.5 * speed2 - _effective_potential_arrays(r, v)

func _jacobi_arrays(r: Array, v: Array) -> float:
	var n := _omega()
	var scale := n * n * Physics.D_KM * Physics.D_KM
	if scale <= 0.0:
		return NAN
	var speed2 := float(v[0]) * float(v[0]) + float(v[1]) * float(v[1]) \
		+ float(v[2]) * float(v[2])
	return 2.0 * _effective_potential_arrays(r, v) / scale - speed2 / scale

# ── 帧转换（经既有 Physics 接口；仅入口/出口）──────────────────

func _extract_state(data: Dictionary):
	var raw = data.get("state", null)
	if raw is Dictionary:
		var st: Dictionary = raw
		if st.get("r", null) != null and st.get("v", null) != null:
			return {"r": _to_arr(st.get("r")), "v": _to_arr(st.get("v"))}
	if data.get("r", null) != null and data.get("v", null) != null:
		return {"r": _to_arr(data.get("r")), "v": _to_arr(data.get("v"))}
	if data.get("position_km", null) != null and data.get("velocity_kmps", null) != null:
		return {"r": _to_arr(data.get("position_km")), "v": _to_arr(data.get("velocity_kmps"))}
	return null

func _to_arr(value) -> Array:
	if value is Vector3:
		return [float(value.x), float(value.y), float(value.z)]
	if value is Array:
		var out: Array = []
		for x in (value as Array):
			if x is int or x is float:
				out.append(float(x))
			else:
				out.append(NAN)
		return out
	return []

func _to_bary_rot(r: Array, v: Array, frame_in: String) -> Dictionary:
	if frame_in == FRAME:
		return {"ok": true, "r": r.duplicate(), "v": v.duplicate()}
	var s := Physics.make_state(Vector3(float(r[0]), float(r[1]), float(r[2])),
		Vector3(float(v[0]), float(v[1]), float(v[2])))
	if frame_in == "earth_eci":
		var d := Physics.earth_eci_to_bary_rot(s, t)
		return {"ok": true, "r": _vec_arr(d.get("r")), "v": _vec_arr(d.get("v"))}
	if frame_in == "earth_rot":
		var d2 := Physics.earth_rot_to_bary_rot(s)
		return {"ok": true, "r": _vec_arr(d2.get("r")), "v": _vec_arr(d2.get("v"))}
	return {"ok": false, "reason": "invalid_frame"}

func _from_bary_rot(r: Array, v: Array, out_frame: String) -> Dictionary:
	var s := Physics.make_state(Vector3(float(r[0]), float(r[1]), float(r[2])),
		Vector3(float(v[0]), float(v[1]), float(v[2])))
	if out_frame == "earth_eci":
		var d := Physics.bary_rot_to_earth_eci(s, t)
		return {"ok": true, "r": _vec_arr(d.get("r")), "v": _vec_arr(d.get("v"))}
	if out_frame == "earth_rot":
		var d2 := Physics.bary_rot_to_earth_rot(s)
		return {"ok": true, "r": _vec_arr(d2.get("r")), "v": _vec_arr(d2.get("v"))}
	return {"ok": false, "reason": "invalid_frame"}

func _vec_arr(v) -> Array:
	if v is Vector3:
		return [float(v.x), float(v.y), float(v.z)]
	return []

# ── 事件（防重复）──────────────────────────────────────────────

func _emit_once(kind: String, key: String, detail: Dictionary) -> void:
	if _event_keys.has(key):
		return
	_event_keys[key] = true
	_event_seq += 1
	events.append({"schema": "physics_event.v1", "seq": _event_seq,
		"t": t, "kind": kind, "key": key, "detail": detail.duplicate(true),
		"writes_v15": false})
	while events.size() > MAX_EVENTS:
		events.pop_front()

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out := events.duplicate(true)
	events = []
	_event_keys = {}
	return out

# ── 快照 / 存档 ────────────────────────────────────────────────

func summary() -> Dictionary:
	return {"schema": SCHEMA, "ready": ready, "t": t, "step_s": step_s,
		"frame": FRAME, "units": units(), "entities": entities.size(),
		"entity_ids": entity_ids(), "sun": sun_enabled,
		"ephemeris": ephemeris_summary(), "samples": samples.size(),
		"events": events.size(), "writes_v15": false}

func snapshot() -> Dictionary:
	var rows: Array = []
	for id in entity_ids():
		rows.append(_state_save(entities[id]))
	var sample_rows: Array = []
	var start := maxi(0, samples.size() - 64)
	for i in range(start, samples.size()):
		sample_rows.append((samples[i] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "version": VERSION, "ready": ready,
		"t": t, "step_s": step_s, "frame": FRAME, "units": units(),
		"constants": constants(), "entities": rows,
		"entity_count": rows.size(), "samples": sample_rows,
		"samples_count": samples.size(), "sun_enabled": sun_enabled,
		"ephemeris": ephemeris_summary(), "events": events.duplicate(true),
		"summary": summary(), "contracts": check_contracts(),
		"errors": errors.duplicate(), "warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate()}

func to_json() -> String:
	return JSON.stringify(snapshot())

func _vec_b64(v: Array) -> String:
	var pf := PackedFloat64Array([float(v[0]), float(v[1]), float(v[2])])
	return Marshalls.raw_to_base64(var_to_bytes(pf))

func _vec_from_b64(s: String) -> Array:
	if s == "":
		return []
	var raw := Marshalls.base64_to_raw(s)
	if raw.is_empty():
		return []
	var v = bytes_to_var(raw)
	if v is PackedFloat64Array and (v as PackedFloat64Array).size() == 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return []

func _num_b64(value: float) -> String:
	var pf := PackedFloat64Array([value])
	return Marshalls.raw_to_base64(var_to_bytes(pf))

func _num_from_b64(s: String) -> float:
	if s == "":
		return NAN
	var raw := Marshalls.base64_to_raw(s)
	if raw.is_empty():
		return NAN
	var v = bytes_to_var(raw)
	if v is PackedFloat64Array and (v as PackedFloat64Array).size() == 1:
		return float((v as PackedFloat64Array)[0])
	return NAN

func _state_save(ent: Dictionary) -> Dictionary:
	var row := _entity_copy(ent)
	row["r_b64"] = _vec_b64(ent["r"])
	row["v_b64"] = _vec_b64(ent["v"])
	row["jacobi0_b64"] = _num_b64(float(ent.get("jacobi0", NAN)))
	return row

func save_state() -> String:
	var rows: Array = []
	for id in entity_ids():
		rows.append(_state_save(entities[id]))
	var saved_samples: Array = []
	for raw_s in samples:
		if not (raw_s is Dictionary):
			continue
		var srow: Dictionary = raw_s
		var states_enc: Dictionary = {}
		for sid in (srow.get("states", {}) as Dictionary).keys():
			var st: Dictionary = (srow.get("states", {}) as Dictionary)[sid]
			states_enc[String(sid)] = {
				"r_b64": _vec_b64(st.get("r", [])),
				"v_b64": _vec_b64(st.get("v", [])),
			}
		saved_samples.append({"t": float(srow.get("t", 0.0)),
			"states_enc": states_enc})
	return JSON.stringify({"schema": SAVE_SCHEMA, "version": VERSION,
		"t": t, "step_s": step_s, "max_steps": max_steps,
		"sun_enabled": sun_enabled, "ephemeris_path": ephemeris_path,
		"entities": rows, "event_seq": _event_seq,
		"samples": saved_samples,
		"events": JSON.parse_string(JSON.stringify(events))}, "", true, true)

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		return _fail("empty_state", "load: 空 JSON")
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return _fail("invalid_json", "load: JSON 无效")
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if String(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	var saved_t := _num(d.get("t", -1.0), -1.0)
	if not is_finite(saved_t) or saved_t < 0.0:
		return _fail("invalid_time", "load: t 非法")
	var saved_step := _num(d.get("step_s", step_s), 0.0)
	if not is_finite(saved_step) or saved_step <= 0.0 or saved_step > STEP_MAX:
		return _fail("invalid_step", "load: step_s 非法")
	if not (d.get("entities") is Array):
		return _fail("invalid_payload", "load: entities 类型无效")
	# 全量校验，成功后再写入
	var new_entities: Dictionary = {}
	for raw in (d.get("entities") as Array):
		if not (raw is Dictionary):
			return _fail("invalid_payload", "load: entity 非对象")
		var ent: Dictionary = raw
		var id := String(ent.get("id", ""))
		if not _id_ok(id) or new_entities.has(id):
			return _fail("invalid_entity", "load: entity id 非法/重复")
		var r := _vec_from_b64(String(ent.get("r_b64", "")))
		var v := _vec_from_b64(String(ent.get("v_b64", "")))
		if r.is_empty():
			r = _to_arr(ent.get("r", []))
		if v.is_empty():
			v = _to_arr(ent.get("v", []))
		if not _finite_vec3(r) or not _finite_vec3(v):
			return _fail("invalid_entity", "load: entity r/v 非法：" + id)
		var mass := _num(ent.get("mass_kg", 0.0), 0.0)
		if not is_finite(mass) or mass <= 0.0:
			return _fail("invalid_mass", "load: entity 质量非法：" + id)
		var att = ent.get("attitude", [])
		if not (att is Array) or (att as Array).size() != 4:
			return _fail("invalid_attitude", "load: entity attitude 非法：" + id)
		for comp in (att as Array):
			if not is_finite(_num(comp, NAN)):
				return _fail("invalid_attitude", "load: entity attitude 非有限：" + id)
		var jac0 := _num_from_b64(String(ent.get("jacobi0_b64", "")))
		if not is_finite(jac0):
			jac0 = _num(ent.get("jacobi0"), _jacobi_arrays(r, v))
		if not is_finite(jac0):
			jac0 = _jacobi_arrays(r, v)
		if not is_finite(jac0):
			return _fail("invalid_entity", "load: jacobi0 非法：" + id)
		new_entities[id] = {"id": id, "r": r, "v": v,
			"mass_kg": mass, "attitude": (att as Array).duplicate(),
			"frame": FRAME, "input_frame": String(ent.get("input_frame", FRAME)),
			"created_t": _num(ent.get("created_t", saved_t), saved_t),
			"updated_t": _num(ent.get("updated_t", saved_t), saved_t),
			"jacobi0": jac0, "version": int(_num(ent.get("version", 1), 1.0))}
	# 应用
	entities = new_entities
	t = saved_t
	step_s = saved_step
	max_steps = maxi(1, int(_num(d.get("max_steps", max_steps), max_steps)))
	sun_enabled = bool(d.get("sun_enabled", sun_enabled))
	_event_seq = int(_num(d.get("event_seq", 0), 0.0))
	events = (d.get("events", []) as Array).duplicate(true) if d.get("events") is Array else []
	_event_keys = {}
	for raw_ev in events:
		if raw_ev is Dictionary:
			_event_keys[String((raw_ev as Dictionary).get("key", ""))] = true
	var new_samples: Array = []
	if d.get("samples") is Array:
		for raw_s in (d.get("samples") as Array):
			if not (raw_s is Dictionary):
				return _fail("invalid_payload", "load: sample 非对象")
			var srow: Dictionary = raw_s
			var st_map: Dictionary = {}
			if srow.get("states_enc") is Dictionary:
				for sid in (srow.get("states_enc") as Dictionary).keys():
					var enc: Dictionary = (srow.get("states_enc") as Dictionary)[sid]
					var sr := _vec_from_b64(String(enc.get("r_b64", "")))
					var sv := _vec_from_b64(String(enc.get("v_b64", "")))
					if not _finite_vec3(sr) or not _finite_vec3(sv):
						return _fail("invalid_payload", "load: sample 状态非法")
					st_map[String(sid)] = {"r": sr, "v": sv}
			elif srow.get("states") is Dictionary:
				for sid2 in (srow.get("states") as Dictionary).keys():
					var st: Dictionary = (srow.get("states") as Dictionary)[sid2]
					var sr2 := _to_arr(st.get("r", []))
					var sv2 := _to_arr(st.get("v", []))
					if not _finite_vec3(sr2) or not _finite_vec3(sv2):
						return _fail("invalid_payload", "load: sample 状态非法")
					st_map[String(sid2)] = {"r": sr2, "v": sv2}
			var st_t := _num(srow.get("t", 0.0), NAN)
			if not is_finite(st_t):
				return _fail("invalid_payload", "load: sample t 非法")
			new_samples.append({"t": st_t, "states": st_map})
	samples = new_samples
	while samples.size() > max_samples:
		samples.pop_front()
	_check_contracts()
	return {"ok": true, "t": t, "entities": entities.size(),
		"samples": samples.size(), "errors": []}

func reset() -> void:
	setup({"step_s": step_s, "max_steps": max_steps, "sun": sun_enabled,
		"record_samples": record_samples, "max_samples": max_samples,
		"ephemeris_path": ephemeris_path, "jacobi_tol": jacobi_tol})

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not is_finite(t) or t < 0.0:
		v.append("t 非法")
	if not is_finite(step_s) or step_s <= 0.0 or step_s > STEP_MAX:
		v.append("step_s 非法")
	var seen := {}
	for id in entities.keys():
		var ent: Dictionary = entities[id]
		if seen.has(String(id)):
			v.append("实体重复：%s" % String(id))
		seen[String(id)] = true
		if not _finite_vec3(ent.get("r", [])):
			v.append("实体 r 非有限：" + String(id))
		if not _finite_vec3(ent.get("v", [])):
			v.append("实体 v 非有限：" + String(id))
		if float(ent.get("mass_kg", 0.0)) <= 0.0:
			v.append("实体质量非法：" + String(id))
		if not is_finite(_jacobi_arrays(ent.get("r", []), ent.get("v", []))):
			v.append("实体 Jacobi 非有限：" + String(id))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("PhysicsWorld 不变量失败：" + str(v))

# ── 工具 ────────────────────────────────────────────────────────

func _entity_copy(ent: Dictionary) -> Dictionary:
	return {"id": String(ent.get("id", "")),
		"r": (ent.get("r", []) as Array).duplicate(),
		"v": (ent.get("v", []) as Array).duplicate(),
		"mass_kg": float(ent.get("mass_kg", 0.0)),
		"attitude": (ent.get("attitude", []) as Array).duplicate(),
		"frame": FRAME, "input_frame": String(ent.get("input_frame", FRAME)),
		"created_t": float(ent.get("created_t", 0.0)),
		"updated_t": float(ent.get("updated_t", 0.0)),
		"jacobi0": float(ent.get("jacobi0", NAN)),
		"version": int(ent.get("version", 1))}

func _num(value, fallback := NAN) -> float:
	if value is int or value is float:
		return float(value)
	return fallback

func _finite_vec3(value) -> bool:
	var a := _to_arr(value)
	if a.size() != 3:
		return false
	for x in a:
		if not is_finite(float(x)):
			return false
	return true

func _id_ok(id: String) -> bool:
	if id == "" or id.strip_edges() != id:
		return false
	var re := RegEx.new()
	re.compile(ENTITY_ID_PATTERN)
	return re.search(id) != null

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": String(reason_text), "errors": [msg]}
