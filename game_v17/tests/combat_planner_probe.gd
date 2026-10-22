extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# COMBAT PLANNER PROBE · 完整游戏-阶段4H
#
# 验证规划辅助（游戏性层）：
#   direct / silent / offset / multi_axis 四种意图 → 巡航剖面；
#   Δv 预算校验与可行性；齐射逐发剖面（按方位均分）；
#   to_launch_opts 与弹道服务 launch() 的 profile/profiles 覆盖打通；
#   确定性 / JSON 安全 / 不写 world。
# 规划器只做算术，不做飞行物理；真实可行性仍由弹道服务兜底。
# ═══════════════════════════════════════════════════════════════════

const Ballistics := preload("res://scripts/core/combat_ballistics.gd")
const Planner := preload("res://scripts/core/combat_planner.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("COMBAT PLANNER PROBE · 完整游戏-阶段4H")
	print("════════════════════════════════════════════════════════════════")
	_test_setup()
	_test_direct()
	_test_silent()
	_test_offset_multi_axis()
	_test_infeasible()
	_test_salvo_plan()
	_test_launch_integration()
	_test_determinism_json()
	print("────────────────────────────────────────────────────────────────")
	print("COMBAT PLANNER PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("COMBAT PLANNER PROBE FAILED")
		quit(1)
	else:
		print("COMBAT PLANNER PROBE OK")
		quit(0)


# ── helpers ──────────────────────────────────────────────────

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[FAIL] ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _json_ok(v: Variant) -> bool:
	var s := JSON.stringify(v)
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref") \
		and not s.contains("Vector3")


func _ball() -> Object:
	return Ballistics.new({})


func _own() -> Dictionary:
	return {"id": "own", "pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
		"radius_km": 0.1, "has_pd": true}


func _target(range_km := 400.0) -> Dictionary:
	return {"id": "T1", "pos_km": [range_km, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
		"radius_km": 0.1}


func _mag(v: Variant) -> float:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2])).length()
	return 0.0


# ── 1. setup ────────────────────────────────────────────────

func _test_setup() -> void:
	print("")
	print("── 1. setup / 意图集合 ──")
	var p = Planner.new()
	var sm: Dictionary = p.summary()
	_eq(String(sm.get("schema", "")), "combat_planner.v1", "summary schema")
	_eq((sm.get("intents", []) as Array).size(), 4, "四种意图")
	for it in ["direct", "silent", "offset", "multi_axis"]:
		_ok((sm.get("intents", []) as Array).has(it), "意图 " + it)
	var w: Dictionary = sm.get("writes", {})
	_ok(not bool(w.get("world", true)), "不写 world")
	_ok(not bool(w.get("track_table", true)), "不写 track_table")
	_ok(not bool(w.get("ui", true)), "不写 ui")
	_ok(_json_ok(sm), "summary JSON 安全")
	# 未知意图明确拒绝
	var bad: Dictionary = p.plan(_ball(), _own(), _target(), "missile", "nope")
	_ok(not bool(bad.get("ok", true)), "未知意图拒绝")
	_eq(String(bad.get("reason", "")), "unknown_intent", "未知意图 reason")
	# 无弹道服务
	var nob: Dictionary = p.plan(null, _own(), _target(), "missile", "direct")
	_ok(not bool(nob.get("ok", true)), "无弹道服务拒绝")
	_eq(String(nob.get("reason", "")), "no_ballistics", "no_ballistics reason")


# ── 2. direct ───────────────────────────────────────────────

func _test_direct() -> void:
	print("")
	print("── 2. direct 直射 ──")
	var p = Planner.new()
	var b = _ball()
	var r: Dictionary = p.plan(b, _own(), _target(), "missile", "direct")
	_ok(bool(r.get("ok", false)), "direct ok", str(r.get("reason", "")))
	_eq(String(r.get("schema", "")), "combat_plan.v1", "plan schema")
	_eq(String(r.get("intent", "")), "direct", "intent 回填")
	_eq(String(r.get("weapon_id", "")), "missile", "weapon 回填")
	_eq((r.get("waypoints", []) as Array).size(), 0, "direct 无航路点")
	_eq(float(r.get("dv_planned_kmps", -1.0)), 0.0, "direct 零 Δv")
	_ok(bool(r.get("feasible", false)), "direct 可行")
	_ok(float(r.get("range_km", 0.0)) > 0.0, "射程回填")
	_ok(float(r.get("time_of_flight_s", 0.0)) > 0.0, "TOF 回填")
	var prof: Dictionary = r.get("profile", {})
	_ok((prof.get("waypoints", []) as Array).is_empty(), "profile 无航路点")
	_eq(float(prof.get("seeker_off_until_km", -1.0)), 0.0, "direct 不关引导头")
	_ok((r.get("notes", []) as Array).size() >= 2, "notes 有内容")
	_ok(_json_ok(r), "direct JSON 安全")
	# 实弹（kinetic）也能规划
	var rk: Dictionary = p.plan(b, _own(), _target(120.0), "railgun", "direct")
	_ok(bool(rk.get("ok", false)), "railgun direct ok", str(rk.get("reason", "")))


# ── 3. silent ───────────────────────────────────────────────

func _test_silent() -> void:
	print("")
	print("── 3. silent 静默接近 ──")
	var p = Planner.new()
	var b = _ball()
	var r: Dictionary = p.plan(b, _own(), _target(), "missile", "silent")
	_ok(bool(r.get("ok", false)), "silent ok", str(r.get("reason", "")))
	var prof: Dictionary = r.get("profile", {})
	var off := float(prof.get("seeker_off_until_km", 0.0))
	_ok(off > 0.0, "静默段距离 > 0", "%.1f km" % off)
	_ok(off < float(r.get("range_km", 0.0)), "静默段小于射程", "%.1f < %.1f" % [off, float(r.get("range_km", 0.0))])
	_eq((r.get("waypoints", []) as Array).size(), 0, "silent 不加航路点")
	_eq(float(r.get("dv_planned_kmps", -1.0)), 0.0, "silent 零 Δv")
	_ok(bool(r.get("feasible", false)), "silent 可行")
	# 显式覆盖
	var r2: Dictionary = p.plan(b, _own(), _target(), "missile", "silent", {"silent_km": 123.0})
	_eq(float((r2.get("profile", {}) as Dictionary).get("seeker_off_until_km", 0.0)), 123.0,
		"silent_km 覆盖生效")
	_ok(_json_ok(r), "silent JSON 安全")


# ── 4. offset / multi_axis ──────────────────────────────────

func _test_offset_multi_axis() -> void:
	print("")
	print("── 4. offset 侧向迂回 / multi_axis 多轴 ──")
	var p = Planner.new()
	var b = _ball()
	var ro: Dictionary = p.plan(b, _own(), _target(), "missile", "offset")
	_ok(bool(ro.get("ok", false)), "offset ok", str(ro.get("reason", "")))
	var wpo: Array = ro.get("waypoints", [])
	_eq(wpo.size(), 2, "offset 两个 Δv 脉冲")
	var w0: Dictionary = wpo[0]
	var w1: Dictionary = wpo[1]
	_eq(float(w0.get("t_s", -1.0)), 0.0, "首脉冲 t=0")
	_ok(float(w1.get("t_s", 0.0)) > 0.0, "次脉冲 t>0")
	# 半程反向抵消：dv 向量相反
	var a: Array = w0.get("dv_kmps", [])
	var c: Array = w1.get("dv_kmps", [])
	_ok(_mag(a) > 0.0, "首脉冲 Δv > 0", "%.4f km/s" % _mag(a))
	_ok(absf(float(a[0]) + float(c[0])) < 1.0e-6
		and absf(float(a[1]) + float(c[1])) < 1.0e-6
		and absf(float(a[2]) + float(c[2])) < 1.0e-6, "次脉冲与首脉冲等值反向")
	var dv_o := float(ro.get("dv_planned_kmps", 0.0))
	_ok(dv_o > 0.0, "offset Δv 记账 > 0", "%.4f" % dv_o)
	_ok(absf(dv_o - _mag(a) * 2.0) < 1.0e-6, "Δv = 两脉冲之和")
	_ok(float(ro.get("dv_budget_kmps", 0.0)) > 0.0, "Δv 预算来自弹道服务")
	_ok(bool(ro.get("feasible", false)), "小横偏默认可行")

	var rm: Dictionary = p.plan(b, _own(), _target(), "missile", "multi_axis", {"bearing_deg": 0.0})
	_ok(bool(rm.get("ok", false)), "multi_axis ok", str(rm.get("reason", "")))
	_eq((rm.get("waypoints", []) as Array).size(), 2, "multi_axis 两个脉冲")
	# bearing 0 时与 offset 同向；bearing 90 时应转向（横偏轴旋转 90°）
	var rm90: Dictionary = p.plan(b, _own(), _target(), "missile", "multi_axis", {"bearing_deg": 90.0})
	var a90: Array = ((rm90.get("waypoints", []) as Array)[0] as Dictionary).get("dv_kmps", [])
	var d := Vector3(float(a[0]), float(a[1]), float(a[2])) - Vector3(float(a90[0]), float(a90[1]), float(a90[2]))
	_ok(d.length() > 1.0e-6, "bearing 改变横偏方向", "diff=%.5f" % d.length())
	# 大横偏 → Δv 明显更大
	var rbig: Dictionary = p.plan(b, _own(), _target(), "missile", "offset", {"offset_km": 2000.0})
	_ok(float(rbig.get("dv_planned_kmps", 0.0)) > dv_o, "横偏越大 Δv 越大")
	_ok(_json_ok(ro) and _json_ok(rm), "offset/multi_axis JSON 安全")


# ── 5. infeasible ───────────────────────────────────────────

func _test_infeasible() -> void:
	print("")
	print("── 5. Δv 预算不可行 ──")
	var p = Planner.new()
	var b = _ball()
	var r: Dictionary = p.plan(b, _own(), _target(400.0), "missile", "offset", {"offset_km": 1.0e6})
	_ok(bool(r.get("ok", false)), "超大横偏仍产出方案")
	_ok(not bool(r.get("feasible", true)), "标记不可行")
	_ok(float(r.get("dv_planned_kmps", 0.0)) > float(r.get("dv_budget_kmps", 0.0)),
		"Δv 超预算", "%.1f > %.1f" % [float(r.get("dv_planned_kmps", 0.0)), float(r.get("dv_budget_kmps", 0.0))])
	var notes: Array = r.get("notes", [])
	var has_warn := false
	for n in notes:
		if String(n).contains("不可行"):
			has_warn = true
	_ok(has_warn, "notes 明确提示不可行")
	_ok(_json_ok(r), "不可行方案 JSON 安全")


# ── 6. plan_salvo ───────────────────────────────────────────

func _test_salvo_plan() -> void:
	print("")
	print("── 6. plan_salvo 齐射逐发剖面 ──")
	var p = Planner.new()
	var b = _ball()
	var s: Dictionary = p.plan_salvo(b, _own(), _target(), "missile", 4, "multi_axis")
	_ok(bool(s.get("ok", false)), "plan_salvo ok", str(s.get("reason", "")))
	_eq(String(s.get("schema", "")), "combat_plan_set.v1", "plan_set schema")
	_eq(int(s.get("count", 0)), 4, "count=4")
	var plans: Array = s.get("plans", [])
	_eq(plans.size(), 4, "四发方案")
	var dirs: Array = []
	for raw in plans:
		var pl: Dictionary = raw
		_ok(bool(pl.get("ok", false)), "单发方案 ok")
		var wp: Array = pl.get("waypoints", [])
		_eq(wp.size(), 2, "每发两个脉冲")
		dirs.append(((wp[0] as Dictionary).get("dv_kmps", []) as Array).duplicate())
	# 方位均分 → 至少存在两种不同方向
	var uniq := 0
	for i in range(dirs.size()):
		var same := false
		for j in range(i):
			var dv := _mag(dirs[i]) > 0.0 and _mag(dirs[j]) > 0.0
			if dv:
				var vi := Vector3(float(dirs[i][0]), float(dirs[i][1]), float(dirs[i][2]))
				var vj := Vector3(float(dirs[j][0]), float(dirs[j][1]), float(dirs[j][2]))
				if vi.distance_to(vj) < 1.0e-9:
					same = true
		if not same:
			uniq += 1
	_ok(uniq >= 2, "逐发方位不同", "unique=%d" % uniq)
	_ok(float(s.get("max_dv_planned_kmps", 0.0)) > 0.0, "max_dv 记账")
	_ok(bool(s.get("feasible", false)), "齐射方案可行")
	_ok(_json_ok(s), "plan_set JSON 安全")
	# n=1 也合法
	var s1: Dictionary = p.plan_salvo(b, _own(), _target(), "missile", 1, "multi_axis")
	_eq((s1.get("plans", []) as Array).size(), 1, "n=1 单发方案")
	# 非 multi_axis 的齐射：各发剖面一致
	var sd: Dictionary = p.plan_salvo(b, _own(), _target(), "missile", 3, "direct")
	_ok(bool(sd.get("ok", false)), "direct 齐射 ok")
	for raw2 in (sd.get("plans", []) as Array):
		_eq(((raw2 as Dictionary).get("waypoints", []) as Array).size(), 0, "direct 齐射无航路点")


# ── 7. launch 集成 ──────────────────────────────────────────

func _test_launch_integration() -> void:
	print("")
	print("── 7. to_launch_opts → launch() 剖面覆盖 ──")
	var p = Planner.new()
	var b = _ball()
	var own := _own()
	var tgt := _target()
	var r: Dictionary = p.plan(b, own, tgt, "missile", "silent")
	var lo: Dictionary = p.to_launch_opts(r)
	_ok(lo.get("profile") is Dictionary, "单发 → profile")
	_eq(String(lo.get("intent", "")), "silent", "intent 透传")
	var lr: Dictionary = b.launch("own", "T1", "missile", own, tgt, lo)
	_ok(bool(lr.get("ok", false)), "按规划发射 ok", str(lr.get("reason", "")))
	var pj: Dictionary = (b.projectiles_all() as Array)[0]
	var pp: Dictionary = pj.get("profile", {})
	_ok(float(pp.get("seeker_off_until_km", 0.0)) > 0.0, "剖面写入弹丸（静默段）",
		"%.1f" % float(pp.get("seeker_off_until_km", 0.0)))

	# 齐射：4 发，逐发剖面
	var b2 = _ball()
	var s: Dictionary = p.plan_salvo(b2, own, tgt, "missile", 4, "multi_axis")
	var lo2: Dictionary = p.to_launch_opts(s)
	_ok(lo2.get("profiles") is Array, "齐射 → profiles")
	_eq((lo2.get("profiles", []) as Array).size(), 4, "profiles 四份")
	lo2["salvo"] = 4
	var lr2: Dictionary = b2.launch("own", "T1", "missile", own, tgt, lo2)
	_ok(bool(lr2.get("ok", false)), "齐射发射 ok", str(lr2.get("reason", "")))
	_eq(int(lr2.get("salvo_launched", 0)), 4, "齐射四发全部出管")
	var act: Array = b2.active_projectiles()
	_eq(act.size(), 4, "在飞四发")
	var wp_counts: Dictionary = {}
	for raw in act:
		var prof: Dictionary = (raw as Dictionary).get("profile", {})
		var n := (prof.get("waypoints", []) as Array).size()
		wp_counts[n] = int(wp_counts.get(n, 0)) + 1
	_ok(int(wp_counts.get(2, 0)) == 4, "四发都带两段航路点", str(wp_counts))
	# 逐发航路点方向不同（多轴）
	var first_dirs: Array = []
	for raw2 in act:
		var wps: Array = ((raw2 as Dictionary).get("profile", {}) as Dictionary).get("waypoints", [])
		if not wps.is_empty():
			first_dirs.append((((wps[0] as Dictionary).get("dv_kmps", [])) as Array).duplicate())
	var distinct := 0
	for i in range(first_dirs.size()):
		var seen := false
		for j in range(i):
			var vi := Vector3(float(first_dirs[i][0]), float(first_dirs[i][1]), float(first_dirs[i][2]))
			var vj := Vector3(float(first_dirs[j][0]), float(first_dirs[j][1]), float(first_dirs[j][2]))
			if vi.distance_to(vj) < 1.0e-9:
				seen = true
		if not seen:
			distinct += 1
	_ok(distinct >= 2, "齐射逐发横偏方向不同", "unique=%d" % distinct)


# ── 8. 确定性 / JSON ───────────────────────────────────────

func _test_determinism_json() -> void:
	print("")
	print("── 8. 确定性 / JSON ──")
	var p = Planner.new()
	var b = _ball()
	var r1: Dictionary = p.plan(b, _own(), _target(), "missile", "offset")
	var r2: Dictionary = p.plan(b, _own(), _target(), "missile", "offset")
	_eq(JSON.stringify(r1.get("waypoints", [])), JSON.stringify(r2.get("waypoints", [])),
		"同输入同剖面（确定性）")
	_eq(float(r1.get("dv_planned_kmps", -1.0)), float(r2.get("dv_planned_kmps", -2.0)),
		"同输入同 Δv")
	var s1: Dictionary = p.plan_salvo(b, _own(), _target(), "missile", 3, "multi_axis")
	var s2: Dictionary = p.plan_salvo(b, _own(), _target(), "missile", 3, "multi_axis")
	_eq(JSON.stringify(s1.get("plans", [])), JSON.stringify(s2.get("plans", [])),
		"齐射方案确定性")
	_ok(_json_ok(r1) and _json_ok(s1), "全字段 JSON 安全（无 Vector3/Object）")
	# estimate_dv 与手工求和一致
	var wps: Array = r1.get("waypoints", [])
	var manual := 0.0
	for raw in wps:
		manual += _mag((raw as Dictionary).get("dv_kmps", []))
	_ok(absf(p.estimate_dv(wps) - manual) < 1.0e-9, "estimate_dv 与手工求和一致")
	_ok(absf(p.estimate_dv([]) - 0.0) < 1.0e-12, "空航路点 Δv=0")
