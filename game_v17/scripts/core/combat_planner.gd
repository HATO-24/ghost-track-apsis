class_name V2CombatPlanner
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 交战规划辅助（游戏性层，不参与飞行物理）
#
# 职责：把"我想怎么打"翻译成弹道服务能吃的巡航剖面（Δv 时序点）。
#   direct      直射：不设航路点，中段静默滑行，末段开机
#   silent      静默接近：引导头关机到距目标 X km 才开机（降低被发现概率）
#   offset      侧向迂回：起手一次横向 Δv，半程反向消掉，形成"侧向进场"
#   multi_axis  多轴同时到达：齐射每发取不同方位角，压缩对方点防通道
#
# 规划器只做算术与校验，不改弹道状态、不写 world/UI。
# 真实可行性由 CombatBallistics.launch() 的 Δv 预算校验兜底；这里提前给出
# feasible=false 让玩家在发射前就知道"这套走法油不够"。
# ═══════════════════════════════════════════════════════════════════

const INTENTS := ["direct", "silent", "offset", "multi_axis"]
const DEFAULT_OFFSET_KM := 200.0     # 侧向迂回的目标横偏
const DEFAULT_SILENT_KM := 600.0     # 静默段结束距离
const MIN_OFFSET_KM := 20.0
const MAX_OFFSET_FRAC := 0.08        # 横偏不超过射程的 8%

var errors: Array = []
var warnings: Array = []


func _init() -> void:
	errors = []
	warnings = []


# ── 几何 ───────────────────────────────────────────────────

func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Vector3:
		return v
	return Vector3.ZERO


func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _lateral_axis(los: Vector3) -> Vector3:
	## 侧向轴：与视线垂直，优先取黄道法向（cislunar 平面外）→ 退回 Z 叉积。
	var up := Vector3(0.0, 0.0, 1.0)
	var lat := los.normalized().cross(up)
	if lat.length() < 1.0e-6:
		lat = los.normalized().cross(Vector3(1.0, 0.0, 0.0))
	if lat.length() < 1.0e-6:
		return Vector3(0.0, 1.0, 0.0)
	return lat.normalized()


# ── 规划 ───────────────────────────────────────────────────

func plan(ball, shooter_state: Dictionary, target_state: Dictionary, weapon_id: String,
		intent := "direct", opts := {}) -> Dictionary:
	## 单发规划。ball 为 V2CombatBallistics 实例（用于 predict 取射程/TOF/Δv 预算）。
	errors = []
	if ball == null:
		return {"ok": false, "reason": "no_ballistics"}
	var it := String(intent)
	if not (it in INTENTS):
		return {"ok": false, "reason": "unknown_intent", "intent": it}
	var o: Dictionary = opts if opts is Dictionary else {}
	var pred: Dictionary = ball.predict(shooter_state, target_state, weapon_id)
	if not bool(pred.get("ok", false)):
		return {"ok": false, "reason": String(pred.get("reason", "predict_failed"))}
	var sp := _v3(shooter_state.get("pos_km", shooter_state.get("r_km", [])))
	var tp := _v3(target_state.get("pos_km", target_state.get("r_km", [])))
	var los := tp - sp
	var range_km := float(pred.get("range_km", los.length()))
	var tof := float(pred.get("time_of_flight_s", 0.0))
	var dv_budget := float(pred.get("dv_budget_kmps", 0.0))
	var profile := {"waypoints": [], "terminal_acquire_km":
		float(o.get("terminal_acquire_km", 0.0)), "seeker_off_until_km": 0.0}
	var waypoints: Array = []
	var bearing_deg := float(o.get("bearing_deg", 90.0))
	match it:
		"direct":
			pass
		"silent":
			profile["seeker_off_until_km"] = float(o.get("silent_km",
				minf(DEFAULT_SILENT_KM, maxf(MIN_OFFSET_KM, range_km * 0.5))))
		"offset", "multi_axis":
			var off := float(o.get("offset_km", minf(DEFAULT_OFFSET_KM,
				maxf(MIN_OFFSET_KM, range_km * MAX_OFFSET_FRAC))))
			if range_km <= 0.0 or tof <= 0.0:
				return {"ok": false, "reason": "no_geometry"}
			var lat := _lateral_axis(los)
			if it == "multi_axis":
				lat = lat.rotated(los.normalized(), deg_to_rad(bearing_deg))
			var t_half := tof * 0.5
			var dv := off / maxf(1.0, t_half)
			# 起手横移 → 半程抵消：净横偏 ≈ dv * t_half
			waypoints.append({"t_s": 0.0, "dv_kmps": _arr(lat * dv)})
			waypoints.append({"t_s": t_half, "dv_kmps": _arr(-lat * dv)})
	profile["waypoints"] = waypoints
	var dv_planned := estimate_dv(waypoints)
	var feasible := dv_budget <= 0.0 or dv_planned <= dv_budget + 1.0e-9
	if not feasible:
		warnings.append("规划 Δv 超预算：%.2f / %.2f km/s" % [dv_planned, dv_budget])
	return {"ok": true, "reason": "", "schema": "combat_plan.v1",
		"intent": it, "weapon_id": weapon_id,
		"range_km": range_km, "time_of_flight_s": tof,
		"aim_km": pred.get("aim_km", []),
		"profile": profile, "waypoints": waypoints.duplicate(true),
		"dv_planned_kmps": dv_planned, "dv_budget_kmps": dv_budget,
		"feasible": feasible,
		"seeker": pred.get("seeker", {}),
		"notes": _notes(it, waypoints, dv_planned, dv_budget, feasible)}


func plan_salvo(ball, shooter_state: Dictionary, target_state: Dictionary, weapon_id: String,
		n: int, intent := "multi_axis", opts := {}) -> Dictionary:
	## 齐射规划：逐发剖面（multi_axis 时按方位均分，形成多轴同时到达）。
	var count := maxi(1, int(n))
	var plans: Array = []
	var total_dv := 0.0
	var all_ok := true
	for i in range(count):
		var o: Dictionary = (opts as Dictionary).duplicate(true) if opts is Dictionary else {}
		o["bearing_deg"] = 360.0 * float(i) / float(count) + float(o.get("bearing_deg", 0.0))
		var p := plan(ball, shooter_state, target_state, weapon_id, intent, o)
		if not bool(p.get("ok", false)):
			all_ok = false
			plans.append({"ok": false, "reason": String(p.get("reason", ""))})
			continue
		total_dv = maxf(total_dv, float(p.get("dv_planned_kmps", 0.0)))
		plans.append(p)
	return {"ok": all_ok, "reason": "" if all_ok else "partial_plan_failed",
		"schema": "combat_plan_set.v1", "intent": intent, "count": count,
		"plans": plans, "max_dv_planned_kmps": total_dv,
		"feasible": all_ok and _all_feasible(plans)}


func _all_feasible(plans: Array) -> bool:
	for p in plans:
		if p is Dictionary and not bool((p as Dictionary).get("feasible", true)):
			return false
	return true


func _notes(intent: String, waypoints: Array, dv_planned: float, dv_budget: float,
		feasible: bool) -> Array:
	var out: Array = []
	match intent:
		"direct":
			out.append("直射：中段静默滑行，末段开机自导")
		"silent":
			out.append("静默接近：末段才开引导头，降低被 ESM/点防提前发现")
		"offset":
			out.append("侧向迂回：横偏后回正，避开对方点防主轴")
		"multi_axis":
			out.append("多轴同时到达：压缩点防通道，齐射效率最高")
	if dv_budget > 0.0:
		out.append("Δv 预算 %.2f km/s，本方案 %.2f km/s（%.0f%%）"
			% [dv_budget, dv_planned, 100.0 * dv_planned / maxf(1.0e-6, dv_budget)])
	if not feasible:
		out.append("不可行：超出 Δv 预算，需缩短航程或换直射")
	out.append("航路点 %d 个（Δv 时序脉冲）" % waypoints.size())
	return out


func estimate_dv(waypoints: Array) -> float:
	var total := 0.0
	for wp in waypoints:
		if wp is Dictionary:
			total += _v3((wp as Dictionary).get("dv_kmps", [])).length()
	return total


## 把规划结果转成 launch(opts) 可直接使用的覆盖字段。
func to_launch_opts(plan_or_set: Dictionary) -> Dictionary:
	if String(plan_or_set.get("schema", "")) == "combat_plan_set.v1":
		var profiles: Array = []
		for p in (plan_or_set.get("plans", []) as Array):
			if p is Dictionary:
				profiles.append((p as Dictionary).get("profile", {}))
		return {"profiles": profiles, "intent": String(plan_or_set.get("intent", "multi_axis"))}
	return {"profile": plan_or_set.get("profile", {}),
		"intent": String(plan_or_set.get("intent", "direct"))}


func summary() -> Dictionary:
	return {"schema": "combat_planner.v1", "intents": INTENTS,
		"default_offset_km": DEFAULT_OFFSET_KM, "default_silent_km": DEFAULT_SILENT_KM,
		"writes": {"world": false, "track_table": false, "ui": false}}
