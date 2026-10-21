class_name V2CombatBallistics
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4G · 战斗弹道 / 拦截闭环
#
# 内容复用 framework/content/weapons_l1.json：
#   railgun（直线弹道/提前量/命中半径/穿透）
#   missile（制导追踪/最大加速度/转向率/燃料/寿命，可被 PD 拦截）
#   pd（自动拦截 incoming：射程/弹药/冷却/概率）
#   decoy/jammer（简化概率诱偏/降锁定，不伪造真实信号）
#
# 只输出 projectile/intercept/impact/event/damage_event；不写 world/TrackTable/UI，
# 位置/速度由调用方每步通过 states 提供；不执行实体损伤应用。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONTENT := "res://framework/content/weapons_l1.json"
const SCHEMA_VM := "combat_ballistics.v1"
const SCHEMA_EVENT := "ballistics_event.v1"
const SCHEMA_DAMAGE := "combat_damage_event.v1"
const SCHEMA_PROJECTILE := "ballistic_projectile.v1"
const SCHEMA_INTERCEPT := "ballistic_intercept.v1"
const SCHEMA_IMPACT := "ballistic_impact.v1"
const SAVE_SCHEMA := "v17.combat_ballistics_save.v1"
const SAVE_VERSION := "1.0.0"
const WEAPON_KINDS := ["kinetic", "guided", "point_defense", "ew", "decoy"]
const MAX_EVENTS := 1000

const DEFAULTS := {
	"railgun": {"hit_radius_km": 0.08, "lifetime_s": 120.0},
	"missile": {"hit_radius_km": 0.15, "lifetime_s": 300.0, "fuel_s": 120.0,
		"max_accel_kmps2": 0.30, "turn_rate_dps": 45.0, "max_speed_kmps": 12.0},
	"pd": {"intercept_prob": 0.65, "range_factor_min": 0.35},
	"decoy": {"lifetime_s": 20.0, "seduce_prob": 0.65},
	"jammer": {"lifetime_s": 30.0, "lock_loss_prob": 0.20},
}

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var weapons: Dictionary = {}
var errors: Array = []
var warnings: Array = []
var config: Dictionary = {}

var projectiles: Array = []
var countermeasures: Array = []
var intercepts: Array = []
var impacts: Array = []
var events: Array = []
var tracks_meta: Dictionary = {}

var _pd_ammo := 0
var _pd_ammo_max := 0
var _pd_cooldown_until := -1.0
var _pd_platform_id := "own"
var _seq_proj := 0
var _seq_event := 0
var _seq_intercept := 0
var _seq_impact := 0
var _outbox: Array = []


func _init(cfg := {}) -> void:
	setup(cfg)


# ── setup / content ─────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	projectiles = []
	countermeasures = []
	intercepts = []
	impacts = []
	events = []
	_outbox = []
	_seq_proj = 0
	_seq_event = 0
	_seq_intercept = 0
	_seq_impact = 0
	weapons = {}
	content = {}
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	content_path = String(config.get("content_path", DEFAULT_CONTENT))
	var data: Variant = null
	if config.get("content") is Dictionary and not (config.get("content") as Dictionary).is_empty():
		data = config.get("content")
	else:
		if not FileAccess.file_exists(content_path):
			errors.append("weapons content 不存在: " + content_path)
			return false
		var f := FileAccess.open(content_path, FileAccess.READ)
		if f == null:
			errors.append("weapons content 不可读: " + content_path)
			return false
		data = JSON.parse_string(f.get_as_text())
		f.close()
	if not (data is Dictionary):
		errors.append("weapons content JSON 无效")
		return false
	content = data
	var v := validate_content(content)
	if not bool(v.get("ok", false)):
		for e in (v.get("errors", []) as Array):
			errors.append("content: " + String(e))
		return false
	for raw in (content.get("weapons", []) as Array):
		if raw is Dictionary:
			var w: Dictionary = raw
			weapons[String(w.get("id", ""))] = w.duplicate(true)
	for wid in ["railgun", "missile", "pd", "decoy", "jammer"]:
		if not weapons.has(wid):
			errors.append("缺武器: " + wid)
	if not errors.is_empty():
		return false
	_pd_platform_id = String(config.get("pd_platform_id", "own"))
	var pd := _weapon("pd")
	_pd_ammo_max = int(pd.get("ammo", 0))
	_pd_ammo = _pd_ammo_max
	_pd_cooldown_until = -1.0
	ready = true
	_push_event("ballistics_ready", {"weapons": weapons.size()})
	return true


func validate_content(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["content 必须对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != "weapons.v1":
		errs.append("schema 必须 weapons.v1")
	var arr = d.get("weapons", null)
	if not (arr is Array) or (arr as Array).is_empty():
		errs.append("weapons 必须非空")
		return {"ok": false, "errors": errs}
	var ids: Dictionary = {}
	for raw in (arr as Array):
		if not (raw is Dictionary):
			errs.append("weapon 非对象")
			continue
		var w: Dictionary = raw
		var id := String(w.get("id", ""))
		if id == "": errs.append("weapon id 空")
		elif ids.has(id): errs.append("weapon 重复: " + id)
		ids[id] = true
		if not (String(w.get("kind", "")) in WEAPON_KINDS):
			errs.append("weapon %s kind 非法" % id)
		for k in ["range_km", "ammo", "cooldown_s", "accuracy", "damage"]:
			if not w.has(k): errs.append("weapon %s 缺 %s" % [id, k])
			elif not is_finite(float(w.get(k, NAN))): errs.append("weapon %s.%s 非有限" % [id, k])
		if bool(w.has("speed_kmps")) and float(w.get("speed_kmps", 0.0)) <= 0.0:
			errs.append("weapon %s speed_kmps 必须 >0" % id)
	return {"ok": errs.is_empty(), "errors": errs}


func _weapon(id: String) -> Dictionary:
	return (weapons.get(id, {}) as Dictionary).duplicate(true) if weapons.get(id) is Dictionary else {}


func _merged(wid: String) -> Dictionary:
	var w := _weapon(wid)
	var kind := String(w.get("kind", ""))
	var d: Dictionary = DEFAULTS.get(wid, {}) if DEFAULTS.get(wid) is Dictionary else {}
	if kind == "point_defense" and not d.has("hit_radius_km"):
		d = DEFAULTS.get("pd", {}).duplicate(true)
	for k in d.keys():
		if not w.has(k):
			w[k] = d[k]
	return w


# ── states / math ───────────────────────────────────────────

func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Vector3:
		return v
	return Vector3.ZERO


func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _norm_state(s: Variant) -> Dictionary:
	if not (s is Dictionary):
		return {}
	var d: Dictionary = s
	var pos = d.get("pos_km", d.get("position_km", d.get("r_km", [])))
	var vel = d.get("vel_kmps", d.get("velocity_kmps", d.get("v_kmps", [])))
	if not (pos is Array) or (pos as Array).size() < 3:
		return {}
	return {"id": String(d.get("id", d.get("shooter_id", ""))),
		"pos_km": _arr(_v3(pos)), "vel_kmps": _arr(_v3(vel)),
		"radius_km": float(d.get("radius_km", 0.0)),
		"has_pd": bool(d.get("has_pd", false)),
		"side": String(d.get("side", ""))}


func _states_map(states: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (states is Dictionary):
		return out
	var d: Dictionary = states
	if d.has("shooters") or d.has("targets"):
		for key in ["shooters", "targets"]:
			var v = d.get(key, null)
			if v is Dictionary:
				for k in (v as Dictionary).keys():
					var ns := _norm_state((v as Dictionary)[k])
					if not ns.is_empty():
						out[String(k)] = ns
			elif v is Array:
				for raw in (v as Array):
					var ns2 := _norm_state(raw)
					if not ns2.is_empty():
						out[String(ns2.get("id", ""))] = ns2
	for k2 in d.keys():
		if k2 in ["shooters", "targets"]:
			continue
		var ns3 := _norm_state(d[k2])
		if not ns3.is_empty():
			out[String(ns3.get("id", k2))] = ns3
	return out


func _lead_point(shooter_pos: Vector3, target_pos: Vector3, target_vel: Vector3,
		speed: float) -> Vector3:
	if speed <= 0.0:
		return target_pos
	var p := target_pos
	for i in range(4):
		var dist := shooter_pos.distance_to(p)
		var tof := dist / speed
		p = target_pos + target_vel * tof
	return p


func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 1.0e-12:
		return a.distance_to(p)
	var u := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * u).distance_to(p)


func _roll(seed_text: String) -> float:
	var h := int(hash(seed_text))
	return float((h & 0x7fffffff) % 1000000) / 1000000.0


# ── predict ─────────────────────────────────────────────────

func predict(shooter_state: Dictionary, target_state: Dictionary, weapon_id: String,
		opts := {}) -> Dictionary:
	var w := _merged(weapon_id)
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	var ss := _norm_state(shooter_state)
	var ts := _norm_state(target_state)
	if ss.is_empty() or ts.is_empty():
		return {"ok": false, "reason": "invalid_state"}
	var sp := _v3(ss.get("pos_km"))
	var tp := _v3(ts.get("pos_km"))
	var tv := _v3(ts.get("vel_kmps"))
	var speed := float(w.get("speed_kmps", 0.0))
	var kind := String(w.get("kind", ""))
	if kind == "kinetic":
		if speed <= 0.0:
			return {"ok": false, "reason": "missing_speed"}
		var lead := _lead_point(sp, tp, tv, speed)
		var tof := sp.distance_to(lead) / speed
		var interceptable := false
		return {"ok": true, "schema": "ballistic_prediction.v1",
			"weapon_id": weapon_id, "mode": "ballistic",
			"time_of_flight_s": tof, "lead_point_km": _arr(lead),
			"lead_offset_km": _arr(lead - tp), "hit_probability":
				float(w.get("accuracy", 0.0)), "interceptable": interceptable,
			"no_physics": false, "trajectory": "straight_lead",
			"range_km": sp.distance_to(tp)}
	if kind == "guided":
		var range_km := sp.distance_to(tp)
		var v0 := maxf(0.1, speed)
		var tof2 := range_km / v0
		var max_speed := maxf(v0, float(w.get("max_speed_kmps", v0)))
		var acc := maxf(0.01, float(w.get("max_accel_kmps2", 0.3)))
		var t_acc := maxf(0.0, (max_speed - v0) / acc)
		tof2 = t_acc + maxf(0.0, range_km - 0.5 * (v0 + max_speed) * t_acc) / max_speed
		var prob := clampf(float(w.get("accuracy", 0.5))
			* (1.0 - 0.35 * clampf(range_km / maxf(1.0, float(w.get("range_km", 1.0))), 0.0, 1.0)), 0.0, 1.0)
		return {"ok": true, "schema": "ballistic_prediction.v1",
			"weapon_id": weapon_id, "mode": "guided",
			"time_of_flight_s": tof2, "lead_point_km": _arr(_lead_point(sp, tp, tv, max_speed)),
			"lead_offset_km": [], "hit_probability": prob,
			"interceptable": bool(w.get("interceptable", false)),
			"fuel_s": float(w.get("fuel_s", 0.0)),
			"no_physics": false, "trajectory": "guided_proportional",
			"range_km": range_km}
	return {"ok": false, "reason": "weapon_not_projectile", "kind": kind}


# ── launch ──────────────────────────────────────────────────

func launch(shooter_id: String, target_id: String, weapon_id: String,
		shooter_state: Dictionary, target_state: Dictionary, opts := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var w := _merged(weapon_id)
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	var ss := _norm_state(shooter_state)
	var ts := _norm_state(target_state)
	if ss.is_empty() or ts.is_empty():
		return {"ok": false, "reason": "invalid_state"}
	if shooter_id == "":
		return {"ok": false, "reason": "empty_shooter"}
	if target_id == "":
		return {"ok": false, "reason": "empty_target"}
	var kind := String(w.get("kind", ""))
	var range_km := _v3(ss.get("pos_km")).distance_to(_v3(ts.get("pos_km")))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range", "range_km": range_km}
	var o: Dictionary = opts if opts is Dictionary else {}
	if kind in ["kinetic", "guided"] and range_km < float(w.get("min_range_km", 0.0)):
		return {"ok": false, "reason": "inside_min_range"}
	if kind == "kinetic" or kind == "guided":
		var speed := float(w.get("speed_kmps", 0.0))
		if speed <= 0.0:
			return {"ok": false, "reason": "missing_speed"}
		var sp := _v3(ss.get("pos_km"))
		var tp := _v3(ts.get("pos_km"))
		var tv := _v3(ts.get("vel_kmps"))
		var aim := _lead_point(sp, tp, tv, speed)
		if kind == "guided":
			aim = tp + tv * 0.5
		if bool(o.get("aim_error", false)):
			aim += Vector3(0.0, float(o.get("aim_error_km", 50.0)), 0.0)
		var dir := (aim - sp)
		if dir.length() < 1.0e-9:
			dir = Vector3(1.0, 0.0, 0.0)
		dir = dir.normalized()
		var v0 := dir * speed
		_seq_proj += 1
		var pid := "PRJ-%05d" % _seq_proj
		var p := {
			"schema": SCHEMA_PROJECTILE, "projectile_id": pid,
			"shooter_id": shooter_id, "target_id": target_id, "weapon_id": weapon_id,
			"kind": "railgun" if kind == "kinetic" else "missile",
			"pos_km": _arr(sp), "vel_kmps": _arr(v0),
			"prev_pos_km": _arr(sp), "launch_t": t, "age_s": 0.0,
			"lifetime_s": float(w.get("lifetime_s", 120.0)),
			"fuel_s": float(w.get("fuel_s", 0.0)),
			"fuel_remaining_s": float(w.get("fuel_s", 0.0)),
			"speed_kmps": speed, "max_accel_kmps2": float(w.get("max_accel_kmps2", 0.0)),
			"turn_rate_dps": float(w.get("turn_rate_dps", 0.0)),
			"max_speed_kmps": maxf(speed, float(w.get("max_speed_kmps", speed))),
			"hit_radius_km": float(w.get("hit_radius_km", 0.1)),
			"damage": float(w.get("damage", 0.0)),
			"penetration": float(w.get("penetration", 0.0)),
			"damage_kind": String(w.get("damage_kind", "kinetic")),
			"interceptable": bool(w.get("interceptable", false)),
			"guided": kind == "guided",
			"active": true, "status": "FLIGHT", "hit": false,
			"intercepted": false, "guidance_lost": false,
			"decoyed": false, "closest_km": range_km,
			"target_last_km": _arr(tp),
			"opts_force_decoy": bool(o.get("force_decoy", false)),
			"opts_force_jam": bool(o.get("force_jam", false)),
			"opts_force_pd": bool(o.get("force_pd", false)),
		}
		projectiles.append(p)
		_push_event("launch", {"projectile_id": pid, "shooter_id": shooter_id,
			"target_id": target_id, "weapon_id": weapon_id, "kind": p["kind"],
			"range_km": range_km, "speed_kmps": speed,
			"time_of_flight_s": range_km / speed})
		return {"ok": true, "reason": "", "projectile": p.duplicate(true),
			"projectile_id": pid, "kind": p["kind"]}
	if kind == "decoy" or kind == "ew":
		var lifetime := float(w.get("duration_s", DEFAULTS.get("decoy", {}).get("lifetime_s", 20.0)))
		_seq_proj += 1
		var cid := "CM-%05d" % _seq_proj
		var cm := {"countermeasure_id": cid, "kind": "decoy" if kind == "decoy" else "jammer",
			"weapon_id": weapon_id, "owner_id": shooter_id,
			"pos_km": _arr(_v3(ss.get("pos_km"))), "deployed_t": t,
			"active_until": t + maxf(1.0, lifetime),
			"lifetime_s": lifetime, "active": true,
			"seduce_prob": float(w.get("seduce_prob", DEFAULTS.get("decoy", {}).get("seduce_prob", 0.65))),
			"lock_loss_prob": float(w.get("lock_loss_prob", DEFAULTS.get("jammer", {}).get("lock_loss_prob", 0.2)))}
		countermeasures.append(cm)
		_push_event("countermeasure_deployed", {"countermeasure_id": cid,
			"owner_id": shooter_id, "kind": cm["kind"], "active_until": cm["active_until"]})
		return {"ok": true, "reason": "", "countermeasure": cm.duplicate(true),
			"countermeasure_id": cid, "kind": cm["kind"]}
	if kind == "point_defense":
		return {"ok": false, "reason": "pd_is_automatic"}
	return {"ok": false, "reason": "weapon_not_launchable"}


func deploy_countermeasure(shooter_id: String, kind: String, state: Dictionary,
		opts := {}) -> Dictionary:
	var wid := "decoy" if kind == "decoy" else "jammer"
	return launch(shooter_id, shooter_id, wid, state, state, opts)


# ── step / physics ─────────────────────────────────────────

func step(dt: float, states := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	var smap := _states_map(states)
	var new_events: Array = []
	# score countermeasures
	for raw in countermeasures:
		if raw is Dictionary:
			var cm: Dictionary = raw
			if bool(cm.get("active", true)) and t + 1.0e-9 >= float(cm.get("active_until", 0.0)):
				cm["active"] = false
				_push_event("countermeasure_expired", {"countermeasure_id": cm.get("countermeasure_id", "")})
	# PD auto intercept
	_auto_pd(smap, new_events)
	# projectiles
	for raw in projectiles:
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		if not bool(p.get("active", true)):
			continue
		p["prev_pos_km"] = p.get("pos_km", [])
		p["age_s"] = t - float(p.get("launch_t", 0.0))
		if float(p.get("age_s", 0.0)) >= float(p.get("lifetime_s", 120.0)):
			_end_projectile(p, "EXPIRED", "lifetime")
			continue
		if p.get("intercepted", false):
			continue
		var target_state: Dictionary = smap.get(String(p.get("target_id", "")), {}) if smap.get(String(p.get("target_id", ""))) is Dictionary else {}
		var target_pos := _v3(p.get("target_last_km", []))
		if not target_state.is_empty():
			target_pos = _v3(target_state.get("pos_km", []))
			p["target_last_km"] = _arr(target_pos)
		var pos := _v3(p.get("pos_km", []))
		var vel := _v3(p.get("vel_kmps", []))
		# PD handled separately; decoy/jammer
		if bool(p.get("guided", false)):
			var jamming := _owner_countermeasure(String(p.get("target_id", "")), "jammer")
			var decoy := _owner_countermeasure(String(p.get("target_id", "")), "decoy")
			if bool(p.get("opts_force_decoy", false)) and not decoy.is_empty():
				p["decoyed"] = true
			elif not decoy.is_empty() and _roll("DECOY|" + String(p.get("projectile_id", ""))) < float(decoy.get("seduce_prob", 0.65)):
				p["decoyed"] = true
			if not jamming.is_empty() and (bool(p.get("opts_force_jam", false))
					or _roll("JAM|" + String(p.get("projectile_id", "")) + "|" + str(step_count)) < float(jamming.get("lock_loss_prob", 0.2))):
				p["guidance_lost"] = true
				p["guidance_quality"] = 0.0
			if bool(p.get("decoyed", false)) and not decoy.is_empty():
				target_pos = _v3(decoy.get("pos_km", []))
			if bool(p.get("guidance_lost", false)):
				vel = vel.normalized() * float(p.get("speed_kmps", 1.0))
			else:
				var aim := target_pos
				var desired := aim - pos
				if desired.length() > 1.0e-9:
					var want_dir := desired.normalized()
					var cur_dir := vel.normalized() if vel.length() > 1.0e-9 else want_dir
					var angle := rad_to_deg(cur_dir.angle_to(want_dir))
					var max_turn := float(p.get("turn_rate_dps", 0.0)) * d
					if max_turn > 0.0 and angle > max_turn:
						var axis := cur_dir.cross(want_dir)
						if axis.length() > 1.0e-9:
							cur_dir = cur_dir.rotated(axis.normalized(), deg_to_rad(max_turn))
						else:
							cur_dir = want_dir
					var speed := float(p.get("speed_kmps", 1.0))
					var fuel := float(p.get("fuel_remaining_s", 0.0))
					if fuel > 0.0:
						var max_speed := float(p.get("max_speed_kmps", speed))
						speed = minf(max_speed, speed + float(p.get("max_accel_kmps2", 0.0)) * d)
						p["fuel_remaining_s"] = maxf(0.0, fuel - d)
					p["speed_kmps"] = speed
					vel = cur_dir * speed
			p["pos_km"] = _arr(pos + vel * d)
		else:
			p["pos_km"] = _arr(pos + vel * d)
		# hit detection
		var new_pos := _v3(p.get("pos_km", []))
		var target_radius := float(target_state.get("radius_km", 0.0)) if not target_state.is_empty() else 0.0
		var dist := _segment_distance(_v3(p.get("prev_pos_km", [])), new_pos, target_pos)
		var closest := new_pos.distance_to(target_pos)
		if dist <= float(p.get("hit_radius_km", 0.1)) + target_radius + 1.0e-9:
			if bool(p.get("decoyed", false)):
				_end_projectile(p, "DECOY_IMPACT", "decoy")
				p["impacts_decoy"] = true
			else:
				_impact(p, target_pos, dist)
			continue
		if closest < float(p.get("closest_km", 999999.0)):
			p["closest_km"] = closest
		if bool(p.get("guided", false)) and float(p.get("fuel_remaining_s", 0.0)) <= 0.0:
			p["guided"] = false
		if float(p.get("age_s", 0.0)) >= float(p.get("lifetime_s", 120.0)):
			_end_projectile(p, "EXPIRED", "lifetime")
	# cleanup active
	var active: Array = []
	for raw in projectiles:
		if raw is Dictionary and bool((raw as Dictionary).get("active", true)):
			active.append(raw)
	# keep inactive in projectiles for records? yes keep but `projectiles()` filters.
	# trim events/impacts
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return {"ok": true, "t": t, "dt": dt_last,
		"active_projectiles": active.size(), "intercepts": intercepts.size(),
		"impacts": impacts.size(), "events": events.duplicate(true),
		"new_events": new_events}


func _end_projectile(p: Dictionary, status: String, reason: String) -> void:
	p["active"] = false
	p["status"] = status
	if status == "EXPIRED":
		_push_event("projectile_expired", {"projectile_id": p.get("projectile_id", ""),
			"reason": reason, "closest_km": p.get("closest_km", -1.0)})
		_push_event("miss", {"projectile_id": p.get("projectile_id", ""),
			"reason": reason, "closest_km": p.get("closest_km", -1.0),
			"target_id": p.get("target_id", "")})
	elif status == "INTERCEPTED":
		p["intercepted"] = true
		_push_event("projectile_intercepted", {"projectile_id": p.get("projectile_id", ""),
			"reason": reason})


func _impact(p: Dictionary, hit_pos: Vector3, miss_distance: float) -> void:
	p["active"] = false
	p["status"] = "HIT"
	p["hit"] = true
	_seq_impact += 1
	var imp := {"schema": SCHEMA_IMPACT, "impact_id": "IMP-%05d" % _seq_impact,
		"t": t, "projectile_id": p.get("projectile_id", ""),
		"shooter_id": p.get("shooter_id", ""), "target_id": p.get("target_id", ""),
		"weapon_id": p.get("weapon_id", ""), "kind": p.get("kind", ""),
		"pos_km": _arr(hit_pos), "miss_distance_km": miss_distance,
		"shot_id": p.get("projectile_id", "")}
	impacts.append(imp)
	var dmg := {"schema": SCHEMA_DAMAGE, "kind": "damage", "t": t,
		"shot_id": String(p.get("projectile_id", "")), "target_id": p.get("target_id", ""),
		"source_id": p.get("shooter_id", ""), "weapon_id": p.get("weapon_id", ""),
		"damage": float(p.get("damage", 0.0)),
		"penetration": float(p.get("penetration", 0.0)),
		"damage_kind": String(p.get("damage_kind", "kinetic")),
		"hit_point_km": _arr(hit_pos), "source": "combat_ballistics",
		"applied": false, "writes_v15": false}
	p["damage_event"] = dmg
	_push_event("impact", {"impact_id": imp["impact_id"], "target_id": p.get("target_id", ""),
		"projectile_id": p.get("projectile_id", ""), "damage_event": dmg.duplicate(true)})


func _auto_pd(smap: Dictionary, _new_events: Array) -> void:
	var platform: Dictionary = smap.get(_pd_platform_id, {}) if smap.get(_pd_platform_id) is Dictionary else {}
	if platform.is_empty():
		return
	if not bool(platform.get("has_pd", false)):
		return
	var pdw := _merged("pd")
	if pdw.is_empty():
		return
	if _pd_ammo <= 0:
		return
	if t + 1.0e-9 < _pd_cooldown_until:
		return
	var range_km := float(pdw.get("range_km", 180.0))
	for raw in projectiles:
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		if not bool(p.get("active", true)) or bool(p.get("intercepted", false)):
			continue
		if not bool(p.get("interceptable", false)):
			continue
		if String(p.get("target_id", "")) != _pd_platform_id and String(p.get("target_id", "")) != String(platform.get("id", "")):
			continue
		var dist := _v3(platform.get("pos_km", [])).distance_to(_v3(p.get("pos_km", [])))
		if dist > range_km + 1.0e-9:
			continue
		_pd_ammo -= 1
		_pd_cooldown_until = t + float(pdw.get("cooldown_s", 2.0))
		_seq_intercept += 1
		var base := float(pdw.get("intercept_prob", pdw.get("intercept_accuracy", 0.65)))
		var factor := clampf(1.0 - 0.5 * (dist / maxf(1.0, range_km)), float(pdw.get("range_factor_min", 0.35)), 1.0)
		var chance := clampf(base * factor, 0.0, 1.0)
		var roll := _roll("PD|" + String(p.get("projectile_id", "")) + "|" + str(_seq_intercept))
		var intercepted := bool(p.get("opts_force_pd", false)) or roll < chance
		var rec := {"schema": SCHEMA_INTERCEPT, "intercept_id": "INT-%05d" % _seq_intercept,
			"t": t, "projectile_id": p.get("projectile_id", ""),
			"target_id": p.get("target_id", ""), "platform_id": _pd_platform_id,
			"weapon_id": "pd", "distance_km": dist, "chance": chance, "roll": roll,
			"intercepted": intercepted, "ammo_left": _pd_ammo}
		intercepts.append(rec)
		_push_event("pd_launch", {"intercept_id": rec["intercept_id"],
			"projectile_id": p.get("projectile_id", ""), "chance": chance, "roll": roll})
		if intercepted:
			_end_projectile(p, "INTERCEPTED", "pd")
		return


func _owner_countermeasure(owner_id: String, kind: String) -> Dictionary:
	for raw in countermeasures:
		if not (raw is Dictionary):
			continue
		var cm: Dictionary = raw
		if String(cm.get("owner_id", "")) != owner_id:
			continue
		if String(cm.get("kind", "")) != kind:
			continue
		if not bool(cm.get("active", true)):
			continue
		return cm
	return {}


# ── query / events ─────────────────────────────────────────

func active_projectiles() -> Array:
	var out: Array = []
	for raw in projectiles:
		if raw is Dictionary and bool((raw as Dictionary).get("active", true)):
			out.append((raw as Dictionary).duplicate(true))
	return out


func projectiles_all() -> Array:
	var out: Array = []
	for raw in projectiles:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


func intercept_records() -> Array:
	return JSON.parse_string(JSON.stringify(intercepts))


func impact_records() -> Array:
	return JSON.parse_string(JSON.stringify(impacts))


func pd_state() -> Dictionary:
	return {"platform_id": _pd_platform_id, "ammo": _pd_ammo,
		"ammo_max": _pd_ammo_max, "cooldown_until": _pd_cooldown_until,
		"cooldown_remaining_s": maxf(0.0, _pd_cooldown_until - t)}


func vm() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t, "dt": dt_last,
		"step_count": step_count, "weapons": weapons.keys(),
		"projectiles": projectiles_all(), "active_projectiles": active_projectiles(),
		"countermeasures": JSON.parse_string(JSON.stringify(countermeasures)),
		"intercepts": intercept_records(), "impacts": impact_records(),
		"pd": pd_state(), "events": events.duplicate(true),
		"counts": {"projectiles": projectiles.size(), "active": active_projectiles().size(),
			"intercepts": intercepts.size(), "impacts": impacts.size(),
			"countermeasures": countermeasures.size(), "events": events.size()},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"world": false, "track_table": false, "v15": false, "ui": false}}


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t,
		"projectiles": projectiles.size(), "active": active_projectiles().size(),
		"intercepts": intercepts.size(), "impacts": impacts.size(),
		"countermeasures": countermeasures.size(), "pd": pd_state(),
		"writes": {"world": false, "track_table": false, "v15": false}}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func _push_event(kind: String, payload := {}) -> void:
	_seq_event += 1
	var ev := {"schema": SCHEMA_EVENT, "seq": _seq_event, "t": t, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	_outbox.append(ev.duplicate(true))


# ── reset / save / load ──────────────────────────────────────

func reset() -> Dictionary:
	t = 0.0
	dt_last = 0.0
	step_count = 0
	projectiles = []
	countermeasures = []
	intercepts = []
	impacts = []
	events = []
	_outbox = []
	_seq_proj = 0
	_seq_event = 0
	_seq_intercept = 0
	_seq_impact = 0
	_pd_ammo = _pd_ammo_max
	_pd_cooldown_until = -1.0
	return {"ok": true, "reset": true, "t": t}


func save_state() -> String:
	var payload := {"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "t": t,
		"projectiles": JSON.parse_string(JSON.stringify(projectiles)),
		"countermeasures": JSON.parse_string(JSON.stringify(countermeasures)),
		"intercepts": JSON.parse_string(JSON.stringify(intercepts)),
		"impacts": JSON.parse_string(JSON.stringify(impacts)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"pd": {"ammo": _pd_ammo, "cooldown_until": _pd_cooldown_until},
		"seq": {"proj": _seq_proj, "event": _seq_event,
			"intercept": _seq_intercept, "impact": _seq_impact},
		"warnings": warnings.duplicate(), "errors": errors.duplicate()}
	return JSON.stringify(payload)


func snapshot() -> Dictionary:
	return JSON.parse_string(save_state())


func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		if String(data).strip_edges() == "":
			return {"ok": false, "reason": "empty_state"}
		parsed = JSON.parse_string(String(data))
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json"}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var p: Dictionary = parsed
	if String(p.get("schema", "")) != SAVE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if String(p.get("version", "")) != SAVE_VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	for k in ["projectiles", "countermeasures", "intercepts", "impacts", "events"]:
		if not (p.get(k) is Array):
			return {"ok": false, "reason": "invalid_payload", "field": k}
	t = float(p.get("t", 0.0))
	projectiles = (p.get("projectiles") as Array).duplicate(true)
	countermeasures = (p.get("countermeasures") as Array).duplicate(true)
	intercepts = (p.get("intercepts") as Array).duplicate(true)
	impacts = (p.get("impacts") as Array).duplicate(true)
	events = (p.get("events") as Array).duplicate(true)
	var pd: Dictionary = p.get("pd", {}) if p.get("pd") is Dictionary else {}
	_pd_ammo = int(pd.get("ammo", _pd_ammo_max))
	_pd_cooldown_until = float(pd.get("cooldown_until", -1.0))
	var seq: Dictionary = p.get("seq", {}) if p.get("seq") is Dictionary else {}
	_seq_proj = int(seq.get("proj", 0))
	_seq_event = int(seq.get("event", 0))
	_seq_intercept = int(seq.get("intercept", 0))
	_seq_impact = int(seq.get("impact", 0))
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	_outbox = []
	return {"ok": true, "reason": "", "t": t, "projectiles": projectiles.size()}
