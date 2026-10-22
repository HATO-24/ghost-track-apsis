class_name V2CombatBallistics
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4G · 战斗弹道 / 拦截闭环（R6 物理化）
#
# 本版把"接口层概率"换成可推进的物理闭环：
#   railgun  实弹：CR3BP 旋转系 RK4 积分 + 射击法解算瞄准点（含科氏/引力偏折）
#   missile  导弹：独立飞控（姿态限转向率 + 推力矢量）+ 引导头状态机
#                  （radar_active / ir_passive / arm）+ 比例导引 PN
#   salvo    齐射：一次发射生成 N 个独立弹（散布 / 独立引导头 / 独立对抗）
#   profile  巡航：Δv 时序点（相对发射时刻的脉冲机动）+ 静默接近
#   counter  对抗：干扰按距离方程压低有效作用距离；诱饵作为竞争目标被锁定
#   pd       点防：ETA 排序 + 冷却射速模型（齐射饱和才有意义）
#
# 单位：km / km/s / s。坐标系：bary_rot（与 physics_world 一致）。
# 只输出 projectile/intercept/impact/event/damage_event；
# 不写 world / TrackTable / UI，不应用伤害。
#
# 与 CombatService 分工：CombatService 只管 ROE/授权/解算排队/弹药；
# 本服务只管"弹出去以后怎么飞、怎么锁、怎么被打掉、打在哪"。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONTENT := "res://framework/content/weapons_l1.json"
const SCHEMA_VM := "combat_ballistics.v1"
const SCHEMA_EVENT := "ballistics_event.v1"
const SCHEMA_DAMAGE := "combat_damage_event.v1"
const SCHEMA_PROJECTILE := "ballistic_projectile.v1"
const SCHEMA_INTERCEPT := "ballistic_intercept.v1"
const SCHEMA_IMPACT := "ballistic_impact.v1"
const SAVE_SCHEMA := "v17.combat_ballistics_save.v1"
const SAVE_VERSION := "2.0.0"
const WEAPON_KINDS := ["kinetic", "guided", "point_defense", "ew", "decoy"]
const MAX_EVENTS := 1000

# ── 积分 / 交战分辨率 ──────────────────────────────────────────
const SUBSTEP_MAX_S := 1.0        # 单子步上限；弹道积分与引信判定的时间分辨率
const MAX_SUBSTEPS := 256         # 单次 step 的子步上限（时间倍速下的算力护栏）
const MAX_PD_SHOTS_PER_STEP := 4  # 单步内单平台最多射数（射速模型护栏）
const SOLVE_ITER := 4             # 射击法瞄准点迭代次数
const SOLVE_COARSE_STEPS := 24    # 射击法试射的粗积分步数

# ── 引导头 / 距离方程 ──────────────────────────────────────────
const SEEKER_TYPES := ["radar_active", "ir_passive", "arm"]
const RCS_REF_M2 := 1000.0        # 雷达距离方程参考 RCS（m²）
const IR_REF := 1.0               # 红外距离方程参考辐射强度
const RCS_DEFAULT_M2 := 800.0     # 未标注目标的缺省 RCS（约护卫舰）
const IR_DEFAULT := 1.0
const PN_N := 3.5                 # 比例导引有效导航比

const PHASES := ["BOOST", "MIDCOURSE", "TERMINAL", "TERMINAL_LOST"]
const SEEKER_STATES := ["SEARCH", "ACQUIRE", "TRACK", "LOST"]

const DEFAULTS := {
	"railgun": {"hit_radius_km": 0.08, "lifetime_s": 120.0, "salvo_spread_deg": 0.05,
		"proximity_fuse_km": 0.0, "frag_damage": 1.0},
	"missile": {"hit_radius_km": 0.15, "lifetime_s": 900.0, "fuel_s": 120.0,
		"max_accel_kmps2": 0.30, "turn_rate_dps": 45.0, "max_speed_kmps": 12.0,
		"boost_s": 8.0, "salvo_spread_deg": 0.15,
		"proximity_fuse_km": 0.35, "frag_damage": 0.35,
		"seeker": {"type": "radar_active", "range_km": 400.0, "fov_deg": 60.0,
			"acquire_s": 2.5, "break_s": 1.5, "break_margin": 0.85,
			"home_on_jam": false},
		"profile": {"waypoints": [], "terminal_acquire_km": 800.0,
			"seeker_off_until_km": 0.0}},
	"pd": {"intercept_prob": 0.65, "range_factor_min": 0.35},
	"decoy": {"lifetime_s": 20.0, "seduce_prob": 0.65,
		"rcs_m2": 2000.0, "ir_signature": 0.9},
	"jammer": {"lifetime_s": 30.0, "lock_loss_prob": 0.20,
		"power": 1.0, "range_km": 5000.0},
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
var _t_cur := 0.0          # 子步内当前时刻（事件时间戳用；t 仍是 step 结束时刻）
var _substeps_last := 0


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
	_t_cur = 0.0
	_substeps_last = 0
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
	_push_event("ballistics_ready", {"weapons": weapons.size(),
		"substep_max_s": SUBSTEP_MAX_S, "model": "cr3bp_rk4"})
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
		if int(w.get("salvo", 1)) < 1:
			errs.append("weapon %s salvo 必须 >=1" % id)
		if w.get("seeker") is Dictionary:
			var sk: Dictionary = w.get("seeker")
			var st := String(sk.get("type", "radar_active"))
			if not (st in SEEKER_TYPES):
				errs.append("weapon %s seeker.type 非法: %s" % [id, st])
			if float(sk.get("range_km", 1.0)) <= 0.0:
				errs.append("weapon %s seeker.range_km 必须 >0" % id)
			var fov := float(sk.get("fov_deg", 60.0))
			if fov <= 0.0 or fov > 180.0:
				errs.append("weapon %s seeker.fov_deg 必须在 (0,180]" % id)
		if w.get("profile") is Dictionary:
			var prof: Dictionary = w.get("profile")
			var wps = prof.get("waypoints", [])
			if not (wps is Array):
				errs.append("weapon %s profile.waypoints 必须数组" % id)
			else:
				for wp in (wps as Array):
					if not (wp is Dictionary):
						errs.append("weapon %s waypoint 非对象" % id)
						continue
					if float((wp as Dictionary).get("t_s", -1.0)) < 0.0:
						errs.append("weapon %s waypoint.t_s 必须 >=0" % id)
	return {"ok": errs.is_empty(), "errors": errs}


func _weapon(id: String) -> Dictionary:
	return (weapons.get(id, {}) as Dictionary).duplicate(true) if weapons.get(id) is Dictionary else {}


func _merged(wid: String) -> Dictionary:
	var w := _weapon(wid)
	if w.is_empty():
		return w
	var d: Dictionary = DEFAULTS.get(wid, {}) if DEFAULTS.get(wid) is Dictionary else {}
	for k in d.keys():
		if not w.has(k):
			w[k] = (d[k] as Dictionary).duplicate(true) if d[k] is Dictionary else d[k]
		elif d[k] is Dictionary and w[k] is Dictionary:
			for kk in (d[k] as Dictionary).keys():
				if not (w[k] as Dictionary).has(kk):
					(w[k] as Dictionary)[kk] = (d[k] as Dictionary)[kk]
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
		"side": String(d.get("side", "")),
		"kind": String(d.get("kind", d.get("ship_class", ""))),
		"rcs_m2": float(d.get("rcs_m2", 0.0)),
		"ir_signature": float(d.get("ir_signature", 0.0))}


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


func _steer(cur: Vector3, want: Vector3, max_turn_deg: float) -> Vector3:
	## 姿态/速度方向按转向率限幅朝 want 旋转；不做瞬时对准。
	if want.length() < 1.0e-9:
		return cur
	var w := want.normalized()
	if cur.length() < 1.0e-9:
		return w
	var c := cur.normalized()
	var angle := rad_to_deg(c.angle_to(w))
	if max_turn_deg <= 0.0 or angle <= max_turn_deg:
		return w
	var axis := c.cross(w)
	if axis.length() < 1.0e-9:
		return w
	return c.rotated(axis.normalized(), deg_to_rad(max_turn_deg)).normalized()


func _lead_point(shooter_pos: Vector3, target_pos: Vector3, target_vel: Vector3,
		speed: float) -> Vector3:
	## 线性提前点（不动点迭代）。仅作射击法初值，最终由 solve_aim 修正。
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


func _gauss(seed_text: String) -> float:
	## 确定性正态采样（Box-Muller），用于散布；不用 randf 以保证可复现/可存档。
	var u1 := maxf(1.0e-7, _roll(seed_text + "|a"))
	var u2 := _roll(seed_text + "|b")
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


# ── 弹道积分（CR3BP 旋转系 RK4）─────────────────────────────

func _integrate(r: Vector3, v: Vector3, accel_extra: Vector3, dt: float) -> Array:
	## 单子步积分：复用 V2CislunarPhysics（引力 + 科氏 + 离心），叠加常值推力。
	var st: Dictionary = V2CislunarPhysics.rk4_step_accel({"r": r, "v": v}, dt, accel_extra)
	return [V2CislunarPhysics.to_vec3(st.get("r", r), r),
		V2CislunarPhysics.to_vec3(st.get("v", v), v)]


func _coast_end(pos: Vector3, vel: Vector3, tof: float, steps: int) -> Vector3:
	## 无推力滑行到 tof 的终点位置（射击法试射用；步数固定，粗积分）。
	if tof <= 0.0:
		return pos
	var n := maxi(1, steps)
	var h := tof / float(n)
	var r := pos
	var v := vel
	for i in range(n):
		var out := _integrate(r, v, Vector3.ZERO, h)
		r = out[0]
		v = out[1]
	return r


func solve_aim(shooter_state: Dictionary, target_state: Dictionary, weapon_id: String,
		opts := {}) -> Dictionary:
	## 射击法解算瞄准点：迭代"试射终点 vs 目标预测位置"，把科氏/引力偏折吃掉。
	## 成本：SOLVE_ITER × SOLVE_COARSE_STEPS 次 RK4，只在发射/预测时调用，不进 tick 热路径。
	var w := _merged(weapon_id)
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	var ss := _norm_state(shooter_state)
	var ts := _norm_state(target_state)
	if ss.is_empty() or ts.is_empty():
		return {"ok": false, "reason": "invalid_state"}
	var speed := float(w.get("speed_kmps", 0.0))
	if speed <= 0.0:
		return {"ok": false, "reason": "missing_speed"}
	var sp := _v3(ss.get("pos_km"))
	var tp := _v3(ts.get("pos_km"))
	var tv := _v3(ts.get("vel_kmps"))
	var o: Dictionary = opts if opts is Dictionary else {}
	var max_iter := int(o.get("iter", SOLVE_ITER))
	var coarse := int(o.get("steps", SOLVE_COARSE_STEPS))
	var aim := _lead_point(sp, tp, tv, speed)
	var tof := sp.distance_to(aim) / speed
	var last_err := 0.0
	for i in range(maxi(1, max_iter)):
		tof = sp.distance_to(aim) / speed
		if tof <= 0.0:
			break
		var dir := (aim - sp)
		if dir.length() < 1.0e-9:
			break
		var end := _coast_end(sp, dir.normalized() * speed, tof, coarse)
		# 目标也必须走同一条 CR3BP 积分：地月系梯度下线性外推几十秒就偏几百米
		var tgt := _coast_end(tp, tv, tof, coarse)
		var err := end.distance_to(tgt)
		last_err = err
		if err <= 1.0e-4:   # 0.1 m 收敛
			break
		aim = aim + (tgt - end)
	return {"ok": true, "aim_km": _arr(aim), "time_of_flight_s": tof,
		"residual_km": last_err, "speed_kmps": speed,
		"iterations": maxi(1, max_iter), "coarse_steps": coarse}

# ── 引导头模型 ─────────────────────────────────────────────

func _make_seeker(w: Dictionary) -> Dictionary:
	var raw: Dictionary = (w.get("seeker", {}) as Dictionary).duplicate(true) \
		if w.get("seeker") is Dictionary else {}
	var typ := String(raw.get("type", "radar_active"))
	if not (typ in SEEKER_TYPES):
		typ = "radar_active"
	return {"type": typ, "range_km": float(raw.get("range_km", 400.0)),
		"fov_deg": float(raw.get("fov_deg", 60.0)),
		"acquire_s": float(raw.get("acquire_s", 2.5)),
		"break_s": float(raw.get("break_s", 1.5)),
		"break_margin": clampf(float(raw.get("break_margin", 0.85)), 0.1, 1.0),
		"home_on_jam": bool(raw.get("home_on_jam", false)),
		"state": "SEARCH", "acquire_elapsed_s": 0.0, "lost_elapsed_s": 0.0,
		"lock_id": "", "lock_kind": "", "quality": 0.0, "margin": 0.0,
		"eff_range_km": 0.0, "jam_ratio": 0.0}


func _target_rcs(ts: Dictionary) -> float:
	var rcs := float(ts.get("rcs_m2", 0.0))
	return rcs if rcs > 0.0 else RCS_DEFAULT_M2


func _target_ir(ts: Dictionary) -> float:
	var ir := float(ts.get("ir_signature", 0.0))
	return ir if ir > 0.0 else IR_DEFAULT


func _eff_range_km(sk: Dictionary, rcs_m2: float, ir_sig: float, jam_ratio: float) -> float:
	## 距离方程：雷达 R ∝ RCS^(1/4)，红外 R ∝ I^(1/2)，干扰按 (1+jam) 压。
	var base := float(sk.get("range_km", 400.0))
	var typ := String(sk.get("type", "radar_active"))
	if typ == "ir_passive":
		var ir := maxf(0.02, ir_sig)
		return base * pow(ir / IR_REF, 0.5) / (1.0 + jam_ratio)
	if typ == "arm":
		# 反辐射：跟踪辐射源，本身不被压制；对无辐射目标作用距离打折
		return base
	var rcs := maxf(1.0, rcs_m2)
	return base * pow(rcs / RCS_REF_M2, 0.25) / (1.0 + jam_ratio)


func _jam_ratio(p: Dictionary, _smap: Dictionary) -> float:
	## 只有"目标方"的干扰机才压制来袭弹；按距离线性衰减，超出射程无效。
	var owner := String(p.get("target_id", ""))
	if owner == "":
		return 0.0
	var pos := _v3(p.get("pos_km", []))
	var total := 0.0
	for raw in countermeasures:
		if not (raw is Dictionary):
			continue
		var cm: Dictionary = raw
		if String(cm.get("kind", "")) != "jammer":
			continue
		if String(cm.get("owner_id", "")) != owner:
			continue
		if not bool(cm.get("active", true)):
			continue
		var rng := maxf(1.0, float(cm.get("range_km", 5000.0)))
		var d := pos.distance_to(_v3(cm.get("pos_km", [])))
		if d > rng:
			continue
		total += float(cm.get("power", 1.0)) * (1.0 - d / rng)
	return clampf(total, 0.0, 8.0)


func _seeker_candidates(p: Dictionary, ts: Dictionary) -> Array:
	## 候选目标 = 真目标 + 目标方仍在工作的诱饵（诱饵是独立假目标，不靠掷骰）。
	var out: Array = []
	out.append({"kind": "target", "id": String(p.get("target_id", "")),
		"pos": _v3(ts.get("pos_km", [])), "vel": _v3(ts.get("vel_kmps", [])),
		"rcs": _target_rcs(ts), "ir": _target_ir(ts)})
	var owner := String(p.get("target_id", ""))
	for raw in countermeasures:
		if not (raw is Dictionary):
			continue
		var cm: Dictionary = raw
		if String(cm.get("kind", "")) != "decoy":
			continue
		if String(cm.get("owner_id", "")) != owner:
			continue
		if not bool(cm.get("active", true)):
			continue
		out.append({"kind": "decoy", "id": String(cm.get("countermeasure_id", "")),
			"pos": _v3(cm.get("pos_km", [])), "vel": _v3(cm.get("vel_kmps", [])),
			"rcs": float(cm.get("rcs_m2", 2000.0)),
			"ir": float(cm.get("ir_signature", 0.9))})
	return out


func _pick_track(p: Dictionary, ts: Dictionary, jam: float) -> Dictionary:
	## 选锁定对象：已有锁定且仍可用则保持（滞回），否则按 特征/距离² 打分取最高。
	var sk: Dictionary = p.get("seeker", {})
	var mpos := _v3(p.get("pos_km", []))
	var vel := _v3(p.get("vel_kmps", []))
	var cands := _seeker_candidates(p, ts)
	var locked_id := String(sk.get("lock_id", ""))
	var best: Dictionary = {}
	var best_score := -1.0
	var keep: Dictionary = {}
	for raw in cands:
		var c: Dictionary = raw
		var d := maxf(0.001, mpos.distance_to(_v3(c.get("pos", []))))
		c["dist_km"] = d
		c["eff_range_km"] = _eff_range_km(sk, float(c.get("rcs", 0.0)),
			float(c.get("ir", 0.0)), jam)
		var margin := float(c["eff_range_km"]) / d
		c["margin"] = margin
		var score := (float(c.get("rcs", 1.0)) if String(sk.get("type", "")) != "ir_passive"
			else float(c.get("ir", 1.0))) / (d * d)
		c["score"] = score
		# 视场：弹轴（速度方向）与视线夹角
		var los := _v3(c.get("pos", [])) - mpos
		var in_fov := true
		if vel.length() > 1.0e-9 and los.length() > 1.0e-9:
			in_fov = rad_to_deg(vel.normalized().angle_to(los.normalized())) \
				<= float(sk.get("fov_deg", 60.0)) * 0.5 + 1.0e-9
		c["in_fov"] = in_fov
		if String(c.get("id", "")) == locked_id:
			keep = c
		if not in_fov:
			continue
		if score > best_score:
			best_score = score
			best = c
	if not keep.is_empty() and float(keep.get("margin", 0.0)) >= float(sk.get("break_margin", 0.85)):
		return keep
	if best.is_empty():
		# 没有视场内候选：仍返回几何最近者用于 margin 判定（便于记录丢锁原因）
		var near: Dictionary = {}
		var near_d := INF
		for raw2 in cands:
			var c2: Dictionary = raw2
			if float(c2.get("dist_km", INF)) < near_d:
				near_d = float(c2.get("dist_km", INF))
				near = c2
		return near
	return best


func _seeker_update(p: Dictionary, smap: Dictionary, dt: float) -> Dictionary:
	## 引导头四态推进。返回 {locked, pos, vel, kind, id, quality}。
	var sk: Dictionary = p.get("seeker", {}) if p.get("seeker") is Dictionary else {}
	if sk.is_empty():
		return {"locked": false, "reason": "no_seeker"}
	var tid := String(p.get("target_id", ""))
	var ts: Dictionary = smap.get(tid, {}) if smap.get(tid) is Dictionary else {}
	if ts.is_empty():
		sk["state"] = "LOST"
		sk["lock_id"] = ""
		p["seeker"] = sk
		return {"locked": false, "reason": "no_target"}
	if bool(p.get("seeker_silent", false)):
		sk["state"] = "SEARCH"
		sk["acquire_elapsed_s"] = 0.0
		sk["quality"] = 0.0
		p["seeker"] = sk
		return {"locked": false, "reason": "silent"}
	var jam := _jam_ratio(p, smap)
	sk["jam_ratio"] = jam
	var pick := _pick_track(p, ts, jam)
	if pick.is_empty():
		sk["state"] = "LOST"
		p["seeker"] = sk
		return {"locked": false, "reason": "no_candidate"}
	var margin := float(pick.get("margin", 0.0))
	var in_fov := bool(pick.get("in_fov", true))
	sk["margin"] = margin
	sk["eff_range_km"] = float(pick.get("eff_range_km", 0.0))
	# 强制诱骗（测试/剧本钩子）：直接锁诱饵
	if bool(p.get("opts_force_decoy", false)) and String(pick.get("kind", "")) == "decoy":
		sk["state"] = "TRACK"
		sk["lock_id"] = String(pick.get("id", ""))
		sk["lock_kind"] = "decoy"
		sk["quality"] = 1.0
		p["decoyed"] = true
		p["seeker"] = sk
		return {"locked": true, "pos": _v3(pick.get("pos", [])),
			"vel": _v3(pick.get("vel", [])), "kind": "decoy",
			"id": String(pick.get("id", "")), "quality": 1.0}
	# 强制丢锁（测试/剧本钩子）
	if bool(p.get("opts_force_jam", false)):
		sk["state"] = "LOST"
		sk["lock_id"] = ""
		sk["quality"] = 0.0
		p["guidance_lost"] = true
		p["seeker"] = sk
		return {"locked": false, "reason": "jammed"}
	var st := String(sk.get("state", "SEARCH"))
	var can_see := margin >= 1.0 and in_fov
	var brk := float(sk.get("break_margin", 0.85))
	if st == "SEARCH":
		if can_see:
			sk["state"] = "ACQUIRE"
			sk["acquire_elapsed_s"] = 0.0
	elif st == "ACQUIRE":
		if can_see:
			sk["acquire_elapsed_s"] = float(sk.get("acquire_elapsed_s", 0.0)) + dt
			if float(sk["acquire_elapsed_s"]) >= float(sk.get("acquire_s", 2.5)):
				sk["state"] = "TRACK"
				sk["lock_id"] = String(pick.get("id", ""))
				sk["lock_kind"] = String(pick.get("kind", "target"))
		else:
			sk["state"] = "SEARCH"
			sk["acquire_elapsed_s"] = 0.0
	elif st == "TRACK":
		if margin < brk or not in_fov:
			sk["lost_elapsed_s"] = float(sk.get("lost_elapsed_s", 0.0)) + dt
			if float(sk["lost_elapsed_s"]) >= float(sk.get("break_s", 1.5)):
				sk["state"] = "LOST"
				sk["lock_id"] = ""
				sk["quality"] = 0.0
				p["guidance_lost"] = true
				_push_event("seeker_lost", {"projectile_id": p.get("projectile_id", ""),
					"reason": "snr" if margin < brk else "fov", "margin": margin})
		else:
			sk["lost_elapsed_s"] = 0.0
	elif st == "LOST":
		if can_see:
			sk["state"] = "ACQUIRE"
			sk["acquire_elapsed_s"] = 0.0
	# 记录锁定点（丢锁后惯性外推的基准）
	var locked := String(sk.get("state", "")) == "TRACK"
	if locked:
		sk["quality"] = clampf(margin - 1.0 + 0.5, 0.0, 1.0)
		sk["lock_id"] = String(pick.get("id", ""))
		sk["lock_kind"] = String(pick.get("kind", "target"))
		p["last_lock_pos"] = _arr(_v3(pick.get("pos", [])))
		p["last_lock_vel"] = _arr(_v3(pick.get("vel", [])))
		p["last_lock_t"] = float(p.get("age_s", 0.0))
		if String(sk.get("lock_kind", "")) == "decoy":
			p["decoyed"] = true
		else:
			p["decoyed"] = false
	else:
		sk["quality"] = 0.0
	p["seeker"] = sk
	return {"locked": locked, "pos": _v3(pick.get("pos", [])),
		"vel": _v3(pick.get("vel", [])), "kind": String(pick.get("kind", "")),
		"id": String(pick.get("id", "")), "quality": float(sk.get("quality", 0.0)),
		"margin": margin}


# ── 制导律 ─────────────────────────────────────────────────

func _pn_accel(p: Dictionary, lock: Dictionary, dt: float) -> Vector3:
	## 比例导引指令加速度：a_cmd = N · V_perp / t_go，受最大过载与转向率双重限幅。
	var pos := _v3(p.get("pos_km", []))
	var vel := _v3(p.get("vel_kmps", []))
	var tpos := _v3(lock.get("pos", p.get("target_last_km", [])))
	var tvel := _v3(lock.get("vel", p.get("target_last_vel", [])))
	var rel := tpos - pos
	var d := rel.length()
	if d < 1.0e-6:
		return Vector3.ZERO
	var u := rel / d
	var relv := tvel - vel
	var closing := -relv.dot(u)
	var t_go := d / maxf(0.05, closing)
	var perp := relv - u * relv.dot(u)
	var a_cmd := perp * (PN_N / maxf(0.2, t_go))
	var v := vel.length()
	var a_max := float(p.get("max_accel_kmps2", 0.0))
	var a_turn := deg_to_rad(float(p.get("turn_rate_dps", 0.0))) * maxf(1.0, v)
	if a_turn > 0.0:
		a_max = minf(a_max, a_turn) if a_max > 0.0 else a_turn
	if a_max > 0.0 and a_cmd.length() > a_max:
		a_cmd = a_cmd.normalized() * a_max
	return a_cmd


func _pn_dir(p: Dictionary, lock: Dictionary, dt: float) -> Vector3:
	## 末制导期望弹轴方向（用于姿态，不直接产生过载）。
	var vel := _v3(p.get("vel_kmps", []))
	var a := _pn_accel(p, lock, dt)
	var want := vel + a * maxf(0.05, minf(dt, 1.0))
	if want.length() < 1.0e-9:
		return vel
	return want.normalized()


func _inertial_dir(p: Dictionary) -> Vector3:
	## 丢锁后惯性外推：用最后锁定点 + 相对速度预测，不读目标实时状态。
	var pos := _v3(p.get("pos_km", []))
	var vel := _v3(p.get("vel_kmps", []))
	if not p.has("last_lock_pos"):
		return vel.normalized() if vel.length() > 1.0e-9 else Vector3(1, 0, 0)
	var lp := _v3(p.get("last_lock_pos", []))
	var lv := _v3(p.get("last_lock_vel", []))
	var dt_lock := maxf(0.0, float(p.get("age_s", 0.0)) - float(p.get("last_lock_t", 0.0)))
	var pred := lp + lv * dt_lock
	var want := pred - pos
	if want.length() < 1.0e-9:
		return vel.normalized() if vel.length() > 1.0e-9 else Vector3(1, 0, 0)
	return want.normalized()


# ── 巡航剖面（Δv 时序点）─────────────────────────────────────

func _apply_waypoints(p: Dictionary) -> void:
	var prof: Dictionary = p.get("profile", {}) if p.get("profile") is Dictionary else {}
	var wps: Array = prof.get("waypoints", []) if prof.get("waypoints") is Array else []
	if wps.is_empty():
		return
	var idx := int(p.get("wp_index", 0))
	var vel := _v3(p.get("vel_kmps", []))
	var age := float(p.get("age_s", 0.0))
	while idx < wps.size():
		var wp: Dictionary = wps[idx]
		var at := float(wp.get("t_s", 0.0))
		if age + 1.0e-9 < at:
			break
		var dv := _v3(wp.get("dv_kmps", []))
		if dv.length() > 1.0e-9:
			vel += dv
			p["dv_used_kmps"] = float(p.get("dv_used_kmps", 0.0)) + dv.length()
			_push_event("waypoint_dv", {"projectile_id": p.get("projectile_id", ""),
				"index": idx, "t_s": at, "dv_kmps": _arr(dv),
				"dv_used_kmps": float(p.get("dv_used_kmps", 0.0))})
		idx += 1
	p["wp_index"] = idx
	p["vel_kmps"] = _arr(vel)


func _update_seeker_gate(p: Dictionary, ts: Dictionary) -> void:
	## 静默接近：距目标 > seeker_off_until_km 时引导头关机（降低被 ESM/PD 发现概率）。
	var prof: Dictionary = p.get("profile", {}) if p.get("profile") is Dictionary else {}
	var off_km := float(prof.get("seeker_off_until_km", 0.0))
	if off_km <= 0.0:
		p["seeker_silent"] = false
		return
	if ts.is_empty():
		p["seeker_silent"] = false
		return
	var d := _v3(p.get("pos_km", [])).distance_to(_v3(ts.get("pos_km", [])))
	p["seeker_silent"] = d > off_km


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
	var kind := String(w.get("kind", ""))
	var range_km := sp.distance_to(tp)
	var speed := float(w.get("speed_kmps", 0.0))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range", "range_km": range_km}
	var guided := kind == "guided"
	var aim := tp
	var tof := 0.0
	var residual := 0.0
	if guided:
		# 制导：中段靠预测拦截点，末端引导头自纠；飞行时间按平均速度粗估
		var v0 := speed
		var acc := float(w.get("max_accel_kmps2", 0.0))
		var fuel := float(w.get("fuel_s", 0.0))
		var vmax := float(w.get("max_speed_kmps", v0))
		var avg := v0 + 0.5 * minf(acc * fuel, maxf(0.0, vmax - v0))
		tof = range_km / maxf(0.1, avg)
		aim = _lead_point(sp, tp, _v3(ts.get("vel_kmps")), maxf(0.1, avg))
	else:
		var sol := solve_aim(ss, ts, weapon_id, {"iter": 2, "steps": 16})
		if bool(sol.get("ok", false)):
			aim = _v3(sol.get("aim_km", _arr(tp)))
			tof = float(sol.get("time_of_flight_s", 0.0))
			residual = float(sol.get("residual_km", 0.0))
	var q := clampf(float(w.get("accuracy", 0.5))
		* (1.0 - clampf(range_km / maxf(1.0, float(w.get("range_km", 1.0))), 0.0, 1.0) * 0.25),
		0.0, 1.0)
	var lead_offset := aim - tp
	return {"ok": true, "reason": "", "schema": "ballistic_prediction.v1",
		"no_physics": false, "mode": "guided" if guided else "ballistic",
		"trajectory": "cr3bp_pn" if guided else "cr3bp_shooting",
		"model": "cr3bp_rk4", "substep_max_s": SUBSTEP_MAX_S,
		"target_id": String(ts.get("id", "")), "weapon_id": weapon_id,
		"range_km": range_km, "time_of_flight_s": tof,
		"aim_km": _arr(aim), "lead_point_km": _arr(aim),
		"lead_offset_km": _arr(lead_offset), "residual_km": residual,
		"fuel_s": float(w.get("fuel_s", 0.0)),
		"dv_budget_kmps": float(w.get("max_accel_kmps2", 0.0)) * float(w.get("fuel_s", 0.0)),
		"hit_probability": q, "error_km": maxf(0.0, range_km * (1.0 - q) * 0.01),
		"guidance": String(w.get("guidance", "")),
		"interceptable": bool(w.get("interceptable", false)),
		"seeker": (w.get("seeker", {}) as Dictionary).duplicate(true) if w.get("seeker") is Dictionary else {}}


# ── launch（含齐射）──────────────────────────────────────────

func launch(shooter_id: String, target_id: String, weapon_id: String,
		shooter_state: Dictionary, target_state: Dictionary, opts := {}) -> Dictionary:
	## 单发发射。齐射由调用方循环（或传 opts.salvo>1 由本函数展开）。
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
	var o: Dictionary = opts if opts is Dictionary else {}
	var salvo := maxi(1, int(o.get("salvo", 1)))
	if salvo > 1:
		return _launch_salvo(shooter_id, target_id, weapon_id, ss, ts, o, salvo)
	var kind := String(w.get("kind", ""))
	var range_km := _v3(ss.get("pos_km")).distance_to(_v3(ts.get("pos_km")))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range", "range_km": range_km}
	if kind in ["kinetic", "guided"] and range_km < float(w.get("min_range_km", 0.0)):
		return {"ok": false, "reason": "inside_min_range"}
	if kind == "kinetic" or kind == "guided":
		return _launch_projectile(shooter_id, target_id, weapon_id, ss, ts, o, w, 0, 1)
	if kind == "decoy" or kind == "ew":
		return _deploy_cm(shooter_id, weapon_id, ss, w)
	if kind == "point_defense":
		return {"ok": false, "reason": "pd_is_automatic"}
	return {"ok": false, "reason": "weapon_not_launchable"}


func _launch_salvo(shooter_id: String, target_id: String, weapon_id: String,
		ss: Dictionary, ts: Dictionary, o: Dictionary, salvo: int) -> Dictionary:
	## 齐射：每发独立散布 / 独立引导头 / 独立对抗。任一发失败不影响已发。
	var w := _merged(weapon_id)
	var kind := String(w.get("kind", ""))
	if not (kind in ["kinetic", "guided"]):
		return {"ok": false, "reason": "salvo_requires_offensive_weapon"}
	var ids: Array = []
	var fails: Array = []
	for i in range(salvo):
		var r := _launch_projectile(shooter_id, target_id, weapon_id, ss, ts, o, w, i, salvo)
		if bool(r.get("ok", false)):
			ids.append(String(r.get("projectile_id", "")))
		else:
			fails.append({"index": i, "reason": String(r.get("reason", ""))})
	_push_event("salvo_launch", {"shooter_id": shooter_id, "target_id": target_id,
		"weapon_id": weapon_id, "requested": salvo, "launched": ids.size(),
		"projectile_ids": ids, "failed": fails})
	return {"ok": ids.size() > 0, "reason": "" if ids.size() > 0 else "salvo_all_failed",
		"kind": kind, "salvo_requested": salvo, "salvo_launched": ids.size(),
		"projectile_ids": ids, "failed": fails}


func _launch_projectile(shooter_id: String, target_id: String, weapon_id: String,
		ss: Dictionary, ts: Dictionary, o: Dictionary, w: Dictionary,
		index: int, total: int) -> Dictionary:
	var kind := String(w.get("kind", ""))
	var speed := float(w.get("speed_kmps", 0.0))
	if speed <= 0.0:
		return {"ok": false, "reason": "missing_speed"}
	var sp := _v3(ss.get("pos_km"))
	var tp := _v3(ts.get("pos_km"))
	var tv := _v3(ts.get("vel_kmps"))
	var aim := tp
	var tof := 0.0
	var residual := 0.0
	if kind == "guided":
		# 制导：初瞄预测拦截点（中段靠飞控 + 末段引导头自纠）
		var v0 := speed
		var acc := float(w.get("max_accel_kmps2", 0.0))
		var fuel := float(w.get("fuel_s", 0.0))
		var vmax := float(w.get("max_speed_kmps", v0))
		var avg := v0 + 0.5 * minf(acc * fuel, maxf(0.0, vmax - v0))
		aim = _lead_point(sp, tp, tv, maxf(0.1, avg))
		tof = sp.distance_to(aim) / maxf(0.1, avg)
	else:
		var sol := solve_aim(ss, ts, weapon_id)
		if not bool(sol.get("ok", false)):
			return {"ok": false, "reason": String(sol.get("reason", "solve_failed"))}
		aim = _v3(sol.get("aim_km", _arr(tp)))
		tof = float(sol.get("time_of_flight_s", 0.0))
		residual = float(sol.get("residual_km", 0.0))
	if bool(o.get("aim_error", false)):
		aim += Vector3(0.0, float(o.get("aim_error_km", 50.0)), 0.0)
	var dir := aim - sp
	if dir.length() < 1.0e-9:
		dir = Vector3(1.0, 0.0, 0.0)
	dir = dir.normalized()
	# 齐射散布：绕射击轴随机偏转（确定性高斯，可存档可复现）
	var spread := float(w.get("salvo_spread_deg", 0.0))
	if spread > 0.0 and total > 1:
		var seed_txt := "%s|%s|%s|%d" % [shooter_id, target_id, weapon_id, index]
		var axis_a := dir.cross(Vector3(0.0, 0.0, 1.0))
		if axis_a.length() < 1.0e-6:
			axis_a = dir.cross(Vector3(1.0, 0.0, 0.0))
		axis_a = axis_a.normalized()
		var axis_b := dir.cross(axis_a).normalized()
		var off_a := _gauss(seed_txt + "|a") * spread
		var off_b := _gauss(seed_txt + "|b") * spread
		dir = dir.rotated(axis_b, deg_to_rad(off_a)).rotated(axis_a, deg_to_rad(off_b)).normalized()
	var v0 := dir * speed
	_seq_proj += 1
	var pid := "PRJ-%05d" % _seq_proj
	var fuel_s := float(w.get("fuel_s", 0.0))
	var seeker := _make_seeker(w) if kind == "guided" else {}
	var prof: Dictionary = (w.get("profile", {}) as Dictionary).duplicate(true) \
		if w.get("profile") is Dictionary else {"waypoints": [], "terminal_acquire_km": 0.0,
			"seeker_off_until_km": 0.0}
	# 规划辅助下发的剖面覆盖（单发 profile / 齐射逐发 profiles）
	var override: Dictionary = {}
	if o.get("profiles") is Array and index < (o.get("profiles") as Array).size() \
			and (o.get("profiles") as Array)[index] is Dictionary:
		override = (o.get("profiles") as Array)[index]
	elif o.get("profile") is Dictionary:
		override = o.get("profile")
	for k in override.keys():
		prof[k] = (override[k] as Dictionary).duplicate(true) if override[k] is Dictionary else override[k]
	var wps: Array = prof.get("waypoints", []) if prof.get("waypoints") is Array else []
	var dv_planned := 0.0
	for wp in wps:
		if wp is Dictionary:
			dv_planned += _v3((wp as Dictionary).get("dv_kmps", [])).length()
	var dv_budget := float(w.get("max_accel_kmps2", 0.0)) * fuel_s
	if kind == "guided" and dv_planned > dv_budget + 1.0e-9:
		return {"ok": false, "reason": "insufficient_dv",
			"dv_planned_kmps": dv_planned, "dv_budget_kmps": dv_budget}
	var p := {
		"schema": SCHEMA_PROJECTILE, "projectile_id": pid,
		"shooter_id": shooter_id, "target_id": target_id, "weapon_id": weapon_id,
		"kind": "railgun" if kind == "kinetic" else "missile",
		"pos_km": _arr(sp), "vel_kmps": _arr(v0),
		"prev_pos_km": _arr(sp), "launch_t": t, "age_s": 0.0,
		"lifetime_s": float(w.get("lifetime_s", 120.0)),
		"fuel_s": fuel_s, "fuel_remaining_s": fuel_s,
		"dv_budget_kmps": dv_budget, "dv_remaining_kmps": dv_budget, "dv_used_kmps": 0.0,
		"speed_kmps": speed, "max_accel_kmps2": float(w.get("max_accel_kmps2", 0.0)),
		"turn_rate_dps": float(w.get("turn_rate_dps", 0.0)),
		"max_speed_kmps": maxf(speed, float(w.get("max_speed_kmps", speed))),
		"hit_radius_km": float(w.get("hit_radius_km", 0.1)),
		"proximity_fuse_km": float(w.get("proximity_fuse_km", 0.0)),
		"frag_damage": float(w.get("frag_damage", 1.0)),
		"damage": float(w.get("damage", 0.0)),
		"penetration": float(w.get("penetration", 0.0)),
		"damage_kind": String(w.get("damage_kind", "kinetic")),
		"interceptable": bool(w.get("interceptable", false)),
		"guided": kind == "guided",
		"phase": "BOOST" if kind == "guided" else "MIDCOURSE",
		"boost_s": float(w.get("boost_s", 8.0)),
		"attitude": _arr(dir),
		"thrusting": false,
		"seeker": seeker,
		"seeker_silent": false,
		"profile": prof,
		"waypoints": wps.duplicate(true),
		"wp_index": 0,
		"salvo_index": index, "salvo_total": total,
		"aim_km": _arr(aim), "planned_tof_s": tof, "solve_residual_km": residual,
		"active": true, "status": "FLIGHT", "hit": false,
		"intercepted": false, "guidance_lost": false, "decoyed": false,
		"closest_km": _v3(ss.get("pos_km")).distance_to(tp),
		"target_last_km": _arr(tp), "target_last_vel": _arr(tv),
		"opts_force_decoy": bool(o.get("force_decoy", false)),
		"opts_force_jam": bool(o.get("force_jam", false)),
		"opts_force_pd": bool(o.get("force_pd", false)),
	}
	projectiles.append(p)
	_push_event("launch", {"projectile_id": pid, "shooter_id": shooter_id,
		"target_id": target_id, "weapon_id": weapon_id, "kind": p["kind"],
		"range_km": _v3(ss.get("pos_km")).distance_to(tp), "speed_kmps": speed,
		"time_of_flight_s": tof, "salvo_index": index, "salvo_total": total,
		"solve_residual_km": residual,
		"seeker_type": String(seeker.get("type", "")) if not seeker.is_empty() else ""})
	return {"ok": true, "reason": "", "projectile": p.duplicate(true),
		"projectile_id": pid, "kind": p["kind"]}


func _deploy_cm(shooter_id: String, weapon_id: String, ss: Dictionary, w: Dictionary) -> Dictionary:
	var kind := String(w.get("kind", ""))
	var lifetime := float(w.get("duration_s", DEFAULTS.get("decoy", {}).get("lifetime_s", 20.0)))
	_seq_proj += 1
	var cid := "CM-%05d" % _seq_proj
	var cm := {"countermeasure_id": cid,
		"kind": "decoy" if kind == "decoy" else "jammer",
		"weapon_id": weapon_id, "owner_id": shooter_id,
		"pos_km": _arr(_v3(ss.get("pos_km"))),
		"vel_kmps": _arr(_v3(ss.get("vel_kmps"))),
		"deployed_t": t, "active_until": t + maxf(1.0, lifetime),
		"lifetime_s": lifetime, "active": true,
		"seduce_prob": float(w.get("seduce_prob", DEFAULTS.get("decoy", {}).get("seduce_prob", 0.65))),
		"lock_loss_prob": float(w.get("lock_loss_prob", DEFAULTS.get("jammer", {}).get("lock_loss_prob", 0.2))),
		"power": float(w.get("power", DEFAULTS.get("jammer", {}).get("power", 1.0))),
		"range_km": float(w.get("range_km", DEFAULTS.get("jammer", {}).get("range_km", 5000.0))),
		"rcs_m2": float(w.get("rcs_m2", DEFAULTS.get("decoy", {}).get("rcs_m2", 2000.0))),
		"ir_signature": float(w.get("ir_signature", DEFAULTS.get("decoy", {}).get("ir_signature", 0.9)))}
	countermeasures.append(cm)
	_push_event("countermeasure_deployed", {"countermeasure_id": cid,
		"owner_id": shooter_id, "kind": cm["kind"], "active_until": cm["active_until"]})
	return {"ok": true, "reason": "", "countermeasure": cm.duplicate(true),
		"countermeasure_id": cid, "kind": cm["kind"]}


func deploy_countermeasure(shooter_id: String, kind: String, state: Dictionary,
		opts := {}) -> Dictionary:
	var wid := "decoy" if kind == "decoy" else "jammer"
	return launch(shooter_id, shooter_id, wid, state, state, opts)


# ── step / physics ─────────────────────────────────────────

func step(dt: float, states := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready"}
	var d := maxf(0.0, float(dt))
	var t_start := t
	t += d
	dt_last = d
	step_count += 1
	_t_cur = t
	var smap := _states_map(states)
	var new_events: Array = []
	# 反制器材过期（用步末时刻判定）
	for raw in countermeasures:
		if raw is Dictionary:
			var cm: Dictionary = raw
			if bool(cm.get("active", true)) and t + 1.0e-9 >= float(cm.get("active_until", 0.0)):
				cm["active"] = false
				_push_event("countermeasure_expired", {"countermeasure_id": cm.get("countermeasure_id", "")})
	# 子步：积分/引导/引信/PD 都在子步网格上跑，避免高时间倍速下"一步飞 4 万公里"
	var n := int(ceil(d / SUBSTEP_MAX_S)) if d > 0.0 else 0
	n = clampi(n, 0, MAX_SUBSTEPS)
	_substeps_last = n
	var h := d / float(maxi(1, n)) if n > 0 else 0.0
	for k in range(n):
		_t_cur = t_start + h * float(k + 1)
		_auto_pd(smap, new_events, h)
		for raw2 in projectiles:
			if not (raw2 is Dictionary):
				continue
			var p: Dictionary = raw2
			if not bool(p.get("active", true)):
				continue
			_step_projectile(p, smap, h)
	if n == 0:
		_t_cur = t
	# 清理
	var active: Array = []
	for raw3 in projectiles:
		if raw3 is Dictionary and bool((raw3 as Dictionary).get("active", true)):
			active.append(raw3)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_t_cur = t
	return {"ok": true, "t": t, "dt": dt_last, "substeps": _substeps_last,
		"substep_s": h, "active_projectiles": active.size(),
		"intercepts": intercepts.size(), "impacts": impacts.size(),
		"events": events.duplicate(true), "new_events": new_events}


func _step_projectile(p: Dictionary, smap: Dictionary, h: float) -> void:
	var tid := String(p.get("target_id", ""))
	var ts: Dictionary = smap.get(tid, {}) if smap.get(tid) is Dictionary else {}
	p["prev_pos_km"] = p.get("pos_km", [])
	p["age_s"] = float(p.get("age_s", 0.0)) + h
	if float(p.get("age_s", 0.0)) >= float(p.get("lifetime_s", 120.0)):
		_end_projectile(p, "EXPIRED", "lifetime")
		return
	if bool(p.get("intercepted", false)):
		return
	if not ts.is_empty():
		p["target_last_km"] = _arr(_v3(ts.get("pos_km", [])))
		p["target_last_vel"] = _arr(_v3(ts.get("vel_kmps", [])))
	var guided := bool(p.get("guided", false))
	var lock: Dictionary = {"locked": false}
	if guided:
		_update_seeker_gate(p, ts)
		_apply_waypoints(p)
		lock = _seeker_update(p, smap, h)
		_update_phase(p, ts, lock, h)
	var pos := _v3(p.get("pos_km", []))
	var vel := _v3(p.get("vel_kmps", []))
	var max_speed := float(p.get("max_speed_kmps", 0.0))
	# 期望弹轴方向
	var want := vel.normalized() if vel.length() > 1.0e-9 else _v3(p.get("attitude", []))
	if guided:
		var phase := String(p.get("phase", "MIDCOURSE"))
		if phase == "TERMINAL" and bool(lock.get("locked", false)):
			want = _pn_dir(p, lock, h)
		elif phase == "TERMINAL_LOST":
			want = _inertial_dir(p)
	if want.length() < 1.0e-9:
		want = Vector3(1.0, 0.0, 0.0)
	# 姿态限幅（转向率）：姿态只影响弹轴指向与主发动机方向，不直接产生过载
	var att := _v3(p.get("attitude", []))
	if att.length() < 1.0e-9:
		att = want
	att = _steer(att, want, float(p.get("turn_rate_dps", 0.0)) * h)
	p["attitude"] = _arr(att)
	# 加速度：主发动机沿弹轴（增速）+ 末制导姿控/推力矢量横向过载（改向）
	# 统一按 Δv 预算扣减，避免"加速段烧光燃料、末段无力修正"
	var extra := Vector3.ZERO
	var dv_left := float(p.get("dv_remaining_kmps", 0.0))
	var accel := float(p.get("max_accel_kmps2", 0.0))
	var phase2 := String(p.get("phase", "MIDCOURSE"))
	if guided and dv_left > 1.0e-9 and accel > 0.0:
		if phase2 == "BOOST" or (phase2 == "MIDCOURSE" and vel.length() < max_speed - 1.0e-9):
			extra = att * accel
		elif phase2 == "TERMINAL" and bool(lock.get("locked", false)):
			extra = _pn_accel(p, lock, h)
	var dv_need := extra.length() * h
	if dv_need > dv_left:
		var k := dv_left / maxf(1.0e-12, dv_need)
		extra = extra * k
		dv_need = dv_left
	if dv_need > 1.0e-12:
		p["dv_remaining_kmps"] = maxf(0.0, dv_left - dv_need)
		p["dv_used_kmps"] = float(p.get("dv_used_kmps", 0.0)) + dv_need
		p["thrusting"] = true
	else:
		p["thrusting"] = false
		if guided and dv_left <= 1.0e-9 and phase2 == "BOOST":
			p["phase"] = "MIDCOURSE"
	p["fuel_remaining_s"] = float(p.get("dv_remaining_kmps", 0.0)) / maxf(1.0e-9, accel)
	# 积分（CR3BP 旋转系 RK4）
	var out := _integrate(pos, vel, extra, h)
	var new_pos: Vector3 = out[0]
	var new_vel: Vector3 = out[1]
	p["pos_km"] = _arr(new_pos)
	p["vel_kmps"] = _arr(new_vel)
	p["speed_kmps"] = new_vel.length()
	# 命中判定（线段-球 + 近炸引信）
	var target_pos := _v3(p.get("target_last_km", []))
	var target_radius := float(ts.get("radius_km", 0.0)) if not ts.is_empty() else 0.0
	var body_r := float(p.get("hit_radius_km", 0.1)) + target_radius
	var dist := _segment_distance(pos, new_pos, target_pos)
	if dist <= body_r + 1.0e-9:
		_impact(p, target_pos, dist, false, ts)
		return
	var fuse := float(p.get("proximity_fuse_km", 0.0))
	if fuse > 0.0 and dist <= body_r + fuse + 1.0e-9:
		_impact(p, target_pos, dist, true, ts)
		return
	var closest := new_pos.distance_to(target_pos)
	if closest < float(p.get("closest_km", 999999.0)):
		p["closest_km"] = closest


func _update_phase(p: Dictionary, ts: Dictionary, lock: Dictionary, _h: float) -> void:
	var phase := String(p.get("phase", "MIDCOURSE"))
	var sk: Dictionary = p.get("seeker", {}) if p.get("seeker") is Dictionary else {}
	var st := String(sk.get("state", "SEARCH"))
	if phase == "BOOST" and float(p.get("age_s", 0.0)) >= float(p.get("boost_s", 8.0)):
		phase = "MIDCOURSE"
	# 引导头锁定 → 转末段；丢锁 → 惯性外推段
	if st == "TRACK" and phase in ["BOOST", "MIDCOURSE", "TERMINAL_LOST"]:
		phase = "TERMINAL"
	elif st == "LOST" and phase == "TERMINAL":
		phase = "TERMINAL_LOST"
	elif st == "LOST" and phase in ["BOOST", "MIDCOURSE"]:
		phase = "TERMINAL_LOST"
	p["phase"] = phase
	# 末段强制开机距离（静默接近的最后一段必须开机）
	var prof: Dictionary = p.get("profile", {}) if p.get("profile") is Dictionary else {}
	var acq := float(prof.get("terminal_acquire_km", 0.0))
	if acq > 0.0 and not ts.is_empty():
		var d := _v3(p.get("pos_km", [])).distance_to(_v3(ts.get("pos_km", [])))
		if d <= acq:
			p["seeker_silent"] = false


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


func _impact_direction(p: Dictionary, ts: Dictionary) -> String:
	## 命中方位由相对速度几何推导（无目标姿态时的最佳近似）：用于后效选部位。
	var tv := _v3(ts.get("vel_kmps", []))
	var pv := _v3(p.get("vel_kmps", []))
	if tv.length() < 1.0e-9 or pv.length() < 1.0e-9:
		return String(p.get("direction", "fore"))
	var fwd := tv.normalized()
	var rel := (pv - tv)
	if rel.length() < 1.0e-9:
		return "fore"
	rel = rel.normalized()
	var up := fwd.cross(Vector3(0.0, 0.0, 1.0))
	if up.length() < 1.0e-9:
		up = fwd.cross(Vector3(1.0, 0.0, 0.0))
	up = up.normalized()
	var left := up.cross(fwd).normalized()
	var d_fwd := rel.dot(fwd)
	var d_up := rel.dot(up)
	var d_left := rel.dot(left)
	if absf(d_fwd) >= absf(d_up) and absf(d_fwd) >= absf(d_left):
		# 相对速度与目标前进方向相反 = 迎面击中前部
		return "fore" if d_fwd < 0.0 else "aft"
	if absf(d_up) >= absf(d_left):
		return "dorsal" if d_up > 0.0 else "ventral"
	return "port" if d_left > 0.0 else "starboard"


func _impact(p: Dictionary, hit_pos: Vector3, miss_distance: float,
		frag: bool, ts: Dictionary) -> void:
	p["active"] = false
	p["status"] = "HIT"
	p["hit"] = true
	_seq_impact += 1
	var direction := _impact_direction(p, ts)
	var frag_k := float(p.get("frag_damage", 1.0)) if frag else 1.0
	var energy := float(p.get("damage", 0.0)) * frag_k
	var imp := {"schema": SCHEMA_IMPACT, "impact_id": "IMP-%05d" % _seq_impact,
		"t": _t_cur, "projectile_id": p.get("projectile_id", ""),
		"shooter_id": p.get("shooter_id", ""), "target_id": p.get("target_id", ""),
		"weapon_id": p.get("weapon_id", ""), "kind": p.get("kind", ""),
		"pos_km": _arr(hit_pos), "miss_distance_km": miss_distance,
		"proximity": frag, "direction": direction,
		"shot_id": p.get("projectile_id", "")}
	impacts.append(imp)
	var dmg := {"schema": SCHEMA_DAMAGE, "kind": "damage", "t": _t_cur,
		"shot_id": String(p.get("projectile_id", "")), "target_id": p.get("target_id", ""),
		"source_id": String(p.get("shooter_id", "")), "weapon_id": p.get("weapon_id", ""),
		"damage": energy,
		"penetration": float(p.get("penetration", 0.0)),
		"damage_kind": String(p.get("damage_kind", "kinetic")),
		"direction": direction, "proximity": frag,
		"hit_point_km": _arr(hit_pos), "source": "combat_ballistics",
		"applied": false, "writes_v15": false}
	p["damage_event"] = dmg
	_push_event("impact", {"impact_id": imp["impact_id"], "target_id": p.get("target_id", ""),
		"projectile_id": p.get("projectile_id", ""), "proximity": frag,
		"direction": direction, "damage_event": dmg.duplicate(true)})


func _auto_pd(smap: Dictionary, _new_events: Array, h: float) -> void:
	## 点防御：按 ETA 排序选最紧急目标；冷却决定持续射速（齐射饱和才有意义）。
	var platform: Dictionary = smap.get(_pd_platform_id, {}) if smap.get(_pd_platform_id) is Dictionary else {}
	if platform.is_empty():
		return
	if not bool(platform.get("has_pd", false)):
		return
	var pdw := _merged("pd")
	if pdw.is_empty():
		return
	var range_km := float(pdw.get("range_km", 180.0))
	var cd := maxf(0.05, float(pdw.get("cooldown_s", 2.0)))
	var ppos := _v3(platform.get("pos_km", []))
	var pid := String(platform.get("id", _pd_platform_id))
	var shots := 0
	while _pd_ammo > 0 and shots < MAX_PD_SHOTS_PER_STEP and _t_cur + 1.0e-9 >= _pd_cooldown_until:
		var best: Dictionary = {}
		var best_eta := INF
		for raw in projectiles:
			if not (raw is Dictionary):
				continue
			var p: Dictionary = raw
			if not bool(p.get("active", true)) or bool(p.get("intercepted", false)):
				continue
			if not bool(p.get("interceptable", false)):
				continue
			if String(p.get("target_id", "")) != _pd_platform_id and String(p.get("target_id", "")) != pid:
				continue
			var d := ppos.distance_to(_v3(p.get("pos_km", [])))
			if d > range_km + 1.0e-9:
				continue
			var closing := -( _v3(p.get("vel_kmps", [])) ).dot((ppos - _v3(p.get("pos_km", []))).normalized())
			var eta := d / maxf(1.0e-6, closing)
			if eta < best_eta:
				best_eta = eta
				best = p
		if best.is_empty():
			return
		_pd_ammo -= 1
		_pd_cooldown_until = _t_cur + cd
		_seq_intercept += 1
		var dist := ppos.distance_to(_v3(best.get("pos_km", [])))
		var base := float(pdw.get("intercept_prob", pdw.get("intercept_accuracy", 0.65)))
		var factor := clampf(1.0 - 0.5 * (dist / maxf(1.0, range_km)),
			float(pdw.get("range_factor_min", 0.35)), 1.0)
		var chance := clampf(base * factor, 0.0, 1.0)
		var roll := _roll("PD|" + String(best.get("projectile_id", "")) + "|" + str(_seq_intercept))
		var intercepted := bool(best.get("opts_force_pd", false)) or roll < chance
		var rec := {"schema": SCHEMA_INTERCEPT, "intercept_id": "INT-%05d" % _seq_intercept,
			"t": _t_cur, "projectile_id": best.get("projectile_id", ""),
			"target_id": best.get("target_id", ""), "platform_id": _pd_platform_id,
			"weapon_id": "pd", "distance_km": dist, "eta_s": best_eta,
			"chance": chance, "roll": roll,
			"intercepted": intercepted, "ammo_left": _pd_ammo}
		intercepts.append(rec)
		_push_event("pd_launch", {"intercept_id": rec["intercept_id"],
			"projectile_id": best.get("projectile_id", ""),
			"chance": chance, "roll": roll, "eta_s": best_eta})
		if intercepted:
			_end_projectile(best, "INTERCEPTED", "pd")
		shots += 1
	# 子步分辨率下的额外机会：h 小则射速受限由 cooldown 保证，无需再判


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
		"model": "cr3bp_rk4", "substep_max_s": SUBSTEP_MAX_S,
		"substeps_last": _substeps_last,
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
		"model": "cr3bp_rk4", "substep_max_s": SUBSTEP_MAX_S,
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
	var ev := {"schema": SCHEMA_EVENT, "seq": _seq_event, "t": _t_cur, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	_outbox.append(ev.duplicate(true))


# ── reset / save / load ──────────────────────────────────────

func reset() -> Dictionary:
	t = 0.0
	dt_last = 0.0
	step_count = 0
	_t_cur = 0.0
	_substeps_last = 0
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
	var ver := String(p.get("version", ""))
	if not (ver in [SAVE_VERSION, "1.0.0"]):
		return {"ok": false, "reason": "unsupported_version", "version": ver}
	var legacy := ver == "1.0.0"
	for k in ["projectiles", "countermeasures", "intercepts", "impacts", "events"]:
		if not (p.get(k) is Array):
			return {"ok": false, "reason": "invalid_payload", "field": k}
	t = float(p.get("t", 0.0))
	_t_cur = t
	# 1.0.0 的弹丸没有姿态/引导头/剖面字段，无法安全迁移 → 丢弃在飞弹并告警
	projectiles = [] if legacy else (p.get("projectiles") as Array).duplicate(true)
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
	if legacy:
		warnings.append("存档为 1.0.0（无引导头/姿态字段），在飞弹已丢弃")
	_outbox = []
	return {"ok": true, "reason": "", "t": t, "projectiles": projectiles.size(),
		"legacy": legacy}
