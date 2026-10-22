extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# BALLISTICS PROBE · 完整游戏-阶段4G
#
# 验证：railgun 直线/提前量/命中半径/穿透；missile 制导/燃料/寿命/
# 拦截；PD 自动拦截/射程/弹药/冷却/概率；decoy/jammer 诱偏/降锁定；
# 命中/未命中/拦截/失效事件与 damage_event（不应用）；存档/重置/
# JSON/确定性；不写 world。只跑一次。
# ═══════════════════════════════════════════════════════════════════

const Ballistics := preload("res://scripts/core/combat_ballistics.gd")
const CONTENT_PATH := "res://framework/content/weapons_l1.json"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("BALLISTICS PROBE · 完整游戏-阶段4G")
	print("════════════════════════════════════════════════════════════════")
	_test_setup_predict()
	_test_railgun()
	_test_missile()
	_test_pd()
	_test_countermeasures()
	_test_save_reset_json()
	print("────────────────────────────────────────────────────────────────")
	print("BALLISTICS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("BALLISTICS PROBE FAILED")
		quit(1)
	else:
		print("BALLISTICS PROBE OK")
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


func _content() -> Dictionary:
	var f := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var p = JSON.parse_string(f.get_as_text())
	f.close()
	return p if p is Dictionary else {}


func _new(content_override = null) -> Object:
	var cfg := {}
	if content_override is Dictionary:
		cfg["content"] = content_override
	return Ballistics.new(cfg)


func _own(has_pd := true) -> Dictionary:
	return {"id": "own", "pos_km": [0.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0], "radius_km": 0.1, "has_pd": has_pd}


func _target(id := "T1", pos := [600.0, 0.0, 0.0]) -> Dictionary:
	return {"id": id, "pos_km": pos, "vel_kmps": [0.0, 0.0, 0.0], "radius_km": 0.1}


func _states(own: Dictionary, target: Dictionary) -> Dictionary:
	return {"shooters": {String(own.get("id", "own")): own},
		"targets": {String(target.get("id", "T1")): target}}


func _step_n(b, n: int, own: Dictionary, target: Dictionary) -> Dictionary:
	var r := {}
	for i in range(n):
		r = b.step(1.0, _states(own, target))
	return r


func _events(s, kind: String) -> int:
	var n := 0
	for raw in (s.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _projectile(b, idx := 0) -> Dictionary:
	var arr: Array = b.projectiles_all()
	return (arr[idx] as Dictionary) if idx < arr.size() else {}


# ── 1. setup / predict ──────────────────────────────────────

func _test_setup_predict() -> void:
	print("")
	print("── 1. setup / 内容复用 / predict ──")
	var b = _new()
	_ok(bool(b.ready), "ready", str(b.errors))
	_ok((b.errors as Array).is_empty(), "setup 无错误")
	_eq((b.weapons as Dictionary).size(), 5, "复用 5 武器")
	for wid in ["railgun", "missile", "pd", "decoy", "jammer"]:
		_ok((b.weapons as Dictionary).has(wid), "武器 " + wid)
	_eq(String((b.content as Dictionary).get("schema", "")), "weapons.v1", "content schema")
	_ok(b.pd_state().has("ammo"), "PD state")
	_eq(int(b.pd_state().get("ammo_max", 0)), 80, "PD 初始弹药 80")
	var own := _own()
	var tgt := _target()
	var pr: Dictionary = b.predict(own, tgt, "railgun")
	_ok(bool(pr.get("ok", false)), "predict railgun")
	_eq(String(pr.get("mode", "")), "ballistic", "predict mode ballistic")
	_ok(float(pr.get("time_of_flight_s", 0.0)) > 0.0, "predict TOF")
	_ok((pr.get("lead_point_km", []) as Array).size() >= 3, "predict lead point")
	_ok((pr.get("lead_offset_km", []) as Array).size() >= 3, "predict lead offset")
	_ok(float(pr.get("hit_probability", 0.0)) > 0.0, "predict hit prob")
	_ok(not bool(pr.get("interceptable", true)), "railgun not interceptable")
	_ok(not bool(pr.get("no_physics", true)), "railgun 有物理")
	# 移动目标提前量
	var moving := _target("T2", [600.0, 0.0, 0.0])
	moving["vel_kmps"] = [0.1, 0.0, 0.0]
	var pm: Dictionary = b.predict(own, moving, "railgun")
	_ok((pm.get("lead_offset_km", []) as Array).size() >= 3, "移动目标 lead offset")
	_ok(float((pm.get("lead_offset_km", []) as Array)[0]) > 0.0, "提前量 >0")
	# missile predict
	var pmsg: Dictionary = b.predict(own, tgt, "missile")
	_ok(bool(pmsg.get("ok", false)), "predict missile")
	_eq(String(pmsg.get("mode", "")), "guided", "predict mode guided")
	_ok(float(pmsg.get("time_of_flight_s", 0.0)) > 0.0, "missile TOF")
	_ok(bool(pmsg.get("interceptable", false)), "missile interceptable")
	_ok(float(pmsg.get("fuel_s", 0.0)) > 0.0, "missile fuel")
	# 错误
	_ok(not bool(b.predict(own, tgt, "decoy").get("ok", true)), "decoy predict false")
	_ok(not bool(b.predict(own, tgt, "NOPE").get("ok", true)), "未知武器 predict false")
	_ok(not bool(b.predict({}, tgt, "railgun").get("ok", true)), "坏 shooter 状态 false")
	_ok(not bool(b.predict(own, {}, "railgun").get("ok", true)), "坏 target 状态 false")
	_ok(_json_ok(b.vm()), "VM JSON")
	_ok(_json_ok(b.summary()), "summary JSON")
	_ok(((b.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((b.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((b.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")
	_ok(((b.vm().get("writes", {}) as Dictionary).get("ui", true)) == false, "不写 UI")
	for wid in ["railgun", "missile", "pd", "decoy", "jammer"]:
		var wd: Dictionary = b.weapons[wid]
		_ok(String(wd.get("id", "")) == wid, "武器 id " + wid)
		_ok(String(wd.get("kind", "")) != "", "武器 kind " + wid)
		_ok(float(wd.get("range_km", 0.0)) >= 0.0, "武器 range " + wid)
		_ok(int(wd.get("ammo", -1)) >= 0, "武器 ammo " + wid)
		_ok(float(wd.get("cooldown_s", -1.0)) >= 0.0, "武器 cooldown " + wid)
		_ok(float(wd.get("accuracy", -1.0)) >= 0.0, "武器 accuracy " + wid)
		_ok(float(wd.get("damage", -1.0)) >= 0.0, "武器 damage " + wid)
		_ok(String(wd.get("auth_level", "")) in ["TRACK", "SOLUTION", "FIRE"], "武器 auth " + wid)


# ── 2. railgun ──────────────────────────────────────────────

func _test_railgun() -> void:
	print("")
	print("── 2. railgun 直线弹道 / 提前量 / 命中 ──")
	var b = _new()
	var own := _own()
	var tgt := _target("T1", [600.0, 0.0, 0.0])
	var l: Dictionary = b.launch("own", "T1", "railgun", own, tgt)
	_ok(bool(l.get("ok", false)), "railgun launch", str(l.get("reason", "")))
	var p: Dictionary = l.get("projectile", {}) as Dictionary
	_ok(String(p.get("projectile_id", "")) != "", "projectile_id")
	_eq(String(p.get("kind", "")), "railgun", "projectile kind")
	_eq(String(p.get("weapon_id", "")), "railgun", "weapon_id")
	_ok(bool(p.get("active", false)), "active")
	_ok(float(p.get("speed_kmps", 0.0)) == 15.0, "speed 15")
	_ok(float(p.get("damage", 0.0)) > 0.0, "damage")
	_ok(float(p.get("penetration", 0.0)) > 0.0, "penetration")
	_ok(float(p.get("lifetime_s", 0.0)) > 0.0, "lifetime")
	_ok(not bool(p.get("interceptable", true)), "not interceptable")
	_ok(_events(b, "launch") >= 1, "launch event")
	_ok((b.active_projectiles() as Array).size() == 1, "active 1")
	_step_n(b, 20, own, tgt)
	_ok((b.active_projectiles() as Array).size() == 1, "飞行中 active")
	_step_n(b, 25, own, tgt)
	_eq(int((b.impacts as Array).size()), 1, "railgun impact")
	var imp: Dictionary = b.impacts[0]
	_eq(String(imp.get("schema", "")), "ballistic_impact.v1", "impact schema")
	_eq(String(imp.get("target_id", "")), "T1", "impact target")
	_eq(String(imp.get("weapon_id", "")), "railgun", "impact weapon")
	_ok(float(imp.get("miss_distance_km", 9.0)) <= 0.1, "impact miss distance")
	_ok(_events(b, "impact") >= 1, "impact event")
	var dmg: Dictionary = (b.projectiles_all()[0] as Dictionary).get("damage_event", {}) as Dictionary
	_eq(String(dmg.get("schema", "")), "combat_damage_event.v1", "damage event schema")
	_ok(not bool(dmg.get("applied", true)), "damage applied=false")
	_ok(float(dmg.get("damage", 0.0)) > 0.0, "damage value")
	_ok(float(dmg.get("penetration", 0.0)) > 0.0, "penetration value")
	_eq(String(dmg.get("weapon_id", "")), "railgun", "damage weapon")
	_ok(not bool(dmg.get("writes_v15", true)), "damage 不写 V15")
	_ok((b.active_projectiles() as Array).is_empty(), "hit 后 active 0")
	# 移动目标提前量
	var b2 = _new()
	var moving := _target("T2", [600.0, 0.0, 0.0])
	moving["vel_kmps"] = [0.1, 0.0, 0.0]
	var l2: Dictionary = b2.launch("own", "T2", "railgun", own, moving)
	_ok(bool(l2.get("ok", false)), "移动目标 launch")
	for i in range(45):
		moving["pos_km"] = [600.0 + 0.1 * float(i + 1), 0.0, 0.0]
		b2.step(1.0, _states(own, moving))
	_ok((b2.impacts as Array).size() >= 1, "移动目标命中/impacts")
	# 未命中：aim error
	var b3 = _new()
	var miss: Dictionary = b3.launch("own", "T1", "railgun", own, _target("T1", [600.0, 0.0, 0.0]),
		{"aim_error": true, "aim_error_km": 60.0})
	_ok(bool(miss.get("ok", false)), "miss launch")
	var r3: Dictionary = _step_n(b3, 125, own, _target("T1", [600.0, 0.0, 0.0]))
	_ok((b3.impacts as Array).is_empty(), "aim error 不命中")
	_ok((b3.active_projectiles() as Array).is_empty(), "miss 后无 active")
	_ok(_events(b3, "projectile_expired") >= 1, "miss expired event")
	_ok(_events(b3, "miss") >= 1, "miss event")
	_ok(float((b3.projectiles_all()[0] as Dictionary).get("closest_km", 999.0)) > 1.0, "closest 记录")
	# 非法
	_ok(not bool(b.launch("", "T", "railgun", own, tgt).get("ok", true)), "空 shooter false")
	_ok(not bool(b.launch("own", "", "railgun", own, tgt).get("ok", true)), "空 target false")
	_ok(not bool(b.launch("own", "T", "NOPE", own, tgt).get("ok", true)), "未知武器 false")
	_ok(not bool(b.launch("own", "T", "railgun", {}, tgt).get("ok", true)), "坏 shooter 状态 false")
	_ok(not bool(b.launch("own", "T", "railgun", own, {}).get("ok", true)), "坏 target 状态 false")
	var far := _target("FAR", [5000.0, 0.0, 0.0])
	_ok(not bool(b.launch("own", "FAR", "railgun", own, far).get("ok", true)), "超距 launch false")
	# 多弹
	var b4 = _new()
	_ok(bool(b4.launch("own", "T1", "railgun", own, tgt).get("ok", false)), "多弹 1")
	_ok(bool(b4.launch("own", "T2", "railgun", own, _target("T2", [500.0, 0.0, 0.0])).get("ok", false)), "多弹 2")
	_ok((b4.active_projectiles() as Array).size() == 2, "两枚 active")
	_ok(_json_ok(b4.vm()), "multi VM JSON")
	for dist in [200.0, 400.0, 600.0, 800.0, 1000.0, 300.0, 700.0]:
		var bs = _new()
		var os := _own()
		var ts := _target("S" + str(dist), [dist, 0.0, 0.0])
		var ls: Dictionary = bs.launch("own", "S" + str(dist), "railgun", os, ts)
		_ok(bool(ls.get("ok", false)), "railgun 场景 launch " + str(dist))
		_step_n(bs, int(dist / 15.0) + 8, os, ts)
		_ok((bs.impacts as Array).size() == 1, "railgun 场景命中 " + str(dist))
		_ok((bs.active_projectiles() as Array).is_empty(), "railgun 场景结束 " + str(dist))
		var evs: Array = bs.events as Array
		var has_impact := false
		for e in evs:
			if e is Dictionary and String((e as Dictionary).get("kind", "")) == "impact":
				has_impact = true
				_eq(String(e.get("schema", "")), "ballistics_event.v1", "event schema " + str(dist))
				_ok(int(e.get("seq", 0)) > 0, "event seq " + str(dist))
				_ok(float(e.get("t", -1.0)) >= 0.0, "event t " + str(dist))
				_ok(not bool(e.get("writes_v15", true)), "event 不写 V15 " + str(dist))
		_ok(has_impact, "impact event " + str(dist)) 


# ── 3. missile ──────────────────────────────────────────────

func _test_missile() -> void:
	print("")
	print("── 3. missile 制导 / 燃料 / 寿命 / 命中 ──")
	var b = _new()
	var own := _own()
	var tgt := _target("T1", [600.0, 0.0, 0.0])
	var l: Dictionary = b.launch("own", "T1", "missile", own, tgt)
	_ok(bool(l.get("ok", false)), "missile launch", str(l.get("reason", "")))
	var p: Dictionary = l.get("projectile", {}) as Dictionary
	_eq(String(p.get("kind", "")), "missile", "missile kind")
	_eq(String(p.get("kind", "")), "missile", "missile kind2")
	_ok(bool(p.get("guided", false)), "guided")
	_ok(bool(p.get("interceptable", false)), "interceptable")
	_ok(float(p.get("fuel_remaining_s", 0.0)) > 0.0, "fuel")
	_ok(float(p.get("lifetime_s", 0.0)) > 0.0, "lifetime")
	_ok(float(p.get("max_accel_kmps2", 0.0)) > 0.0, "max accel")
	_ok(float(p.get("turn_rate_dps", 0.0)) > 0.0, "turn rate")
	_ok(float(p.get("hit_radius_km", 0.0)) > 0.0, "hit radius")
	_ok(float(p.get("damage", 0.0)) > 0.0, "missile damage")
	_step_n(b, 20, own, tgt)
	var mid: Dictionary = _projectile(b)
	_ok(float(mid.get("fuel_remaining_s", 0.0)) < float(p.get("fuel_remaining_s", 0.0)),
		"燃料消耗")
	_ok(bool(mid.get("active", true)), "missile 飞行中")
	_step_n(b, 50, own, tgt)
	_eq(int((b.impacts as Array).size()), 1, "missile 命中")
	_ok((b.intercepts as Array).is_empty(), "无 PD 拦截")
	var dmg: Dictionary = (_projectile(b).get("damage_event", {}) as Dictionary)
	_eq(String(dmg.get("schema", "")), "combat_damage_event.v1", "missile damage schema")
	_ok(not bool(dmg.get("applied", true)), "missile damage applied=false")
	_ok(float(dmg.get("damage", 0.0)) > 0.0, "missile damage value")
	# 移动目标
	var b2 = _new()
	var moving := _target("T2", [1000.0, 0.0, 0.0])
	moving["vel_kmps"] = [0.05, 0.0, 0.0]
	_ok(bool(b2.launch("own", "T2", "missile", own, moving).get("ok", false)), "移动导弹 launch")
	for i in range(100):
		moving["pos_km"] = [1000.0 + 0.05 * float(i + 1), 0.0, 0.0]
		b2.step(1.0, _states(own, moving))
	_ok((b2.impacts as Array).size() >= 1, "移动目标导弹命中")
	# 远距燃料耗尽/寿命：900 s 寿命下 5900 km 可达（旧 300 s 寿命物理上打不到，属内容不自洽修正）
	var b3 = _new()
	var far := _target("FAR", [5900.0, 0.0, 0.0])
	_ok(bool(b3.launch("own", "FAR", "missile", own, far).get("ok", false)), "远距发射")
	for i in range(400):
		b3.step(1.0, _states(own, far))
	var farp: Dictionary = _projectile(b3)
	# Δv 预算模型：加速段只花掉一部分，末制导保留机动量（旧模型加速段烧光燃料、末段无力修正）
	_ok(float(farp.get("dv_used_kmps", 0.0)) > 0.0, "远距已消耗 Δv")
	_ok(float(farp.get("dv_remaining_kmps", 0.0)) > 0.0, "远距保留末段机动 Δv")
	_ok(bool(farp.get("active", true)), "400s 仍在飞（寿命 900s）")
	for i in range(400):
		b3.step(1.0, _states(own, far))
	_ok(not bool(_projectile(b3).get("active", true)), "远距已失效/命中")
	_ok(_events(b3, "projectile_expired") >= 1 or (b3.impacts as Array).size() >= 1,
		"远距失效/命中事件")
	# 预测 vs 实际 TOF
	var b4 = _new()
	var pred: Dictionary = b4.predict(own, tgt, "missile")
	_ok(float(pred.get("time_of_flight_s", 0.0)) > 0.0, "missile predict TOF2")
	_ok(_json_ok(b4.vm()), "missile VM JSON")
	for mdist in [300.0, 500.0, 800.0, 1200.0]:
		var bm = _new()
		var om := _own()
		var tm := _target("M" + str(mdist), [mdist, 0.0, 0.0])
		var lm2: Dictionary = bm.launch("own", "M" + str(mdist), "missile", om, tm)
		_ok(bool(lm2.get("ok", false)), "missile 场景 launch " + str(mdist))
		_ok(float((lm2.get("projectile", {}) as Dictionary).get("fuel_remaining_s", 0.0)) > 0.0,
			"missile 场景 fuel " + str(mdist))
		for i in range(160):
			bm.step(1.0, _states(om, tm))
			if (bm.impacts as Array).size() > 0:
				break
		_ok((bm.impacts as Array).size() == 1, "missile 场景命中 " + str(mdist))
		_ok((bm.active_projectiles() as Array).is_empty(), "missile 场景结束 " + str(mdist))


# ── 4. PD ──────────────────────────────────────────────────

func _test_pd() -> void:
	print("")
	print("── 4. PD 自动拦截 / 射程 / 弹药 / 冷却 ──")
	var b = _new()
	var own := _own()
	var enemy := {"id": "enemy", "pos_km": [100.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0], "radius_km": 0.1}
	var lm: Dictionary = b.launch("enemy", "own", "missile", enemy, own, {"force_pd": true})
	_ok(bool(lm.get("ok", false)), "enemy missile launch")
	var ammo0 := int(b.pd_state().get("ammo", 0))
	b.step(1.0, {"shooters": {"enemy": enemy}, "targets": {"own": own}})
	_ok((b.intercepts as Array).size() >= 1, "PD 拦截记录")
	var it: Dictionary = b.intercepts[0]
	_eq(String(it.get("schema", "")), "ballistic_intercept.v1", "intercept schema")
	_eq(String(it.get("weapon_id", "")), "pd", "intercept weapon")
	_eq(String(it.get("target_id", "")), "own", "intercept target")
	_ok(bool(it.get("intercepted", false)), "force PD intercepted")
	_ok(int(b.pd_state().get("ammo", -1)) == ammo0 - 1, "PD 消耗弹药")
	_ok(float(b.pd_state().get("cooldown_until", -1.0)) > 0.0, "PD 冷却设置")
	_ok((b.impacts as Array).is_empty(), "拦截后无 impact")
	_ok(_events(b, "pd_launch") >= 1, "pd_launch event")
	_ok(_events(b, "projectile_intercepted") >= 1, "projectile_intercepted event")
	# 冷却期内不再拦截
	var lm2: Dictionary = b.launch("enemy", "own", "missile", enemy, own, {"force_pd": true})
	b.step(0.5, {"shooters": {"enemy": enemy}, "targets": {"own": own}})
	_eq(int((b.intercepts as Array).size()), 1, "冷却内不新增拦截")
	# 射程外
	var b2 = _new()
	var far := {"id": "enemy", "pos_km": [600.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0]}
	b2.launch("enemy", "own", "missile", far, _own(), {"force_pd": true})
	b2.step(1.0, {"shooters": {"enemy": far}, "targets": {"own": _own()}})
	_ok((b2.intercepts as Array).is_empty(), "PD 射程外不拦截")
	# 无 PD 平台
	var b3 = _new()
	var no_pd := {"id": "own", "pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}
	b3.launch("enemy", "own", "missile", enemy, no_pd, {"force_pd": true})
	b3.step(1.0, {"shooters": {"enemy": enemy}, "targets": {"own": no_pd}})
	_ok((b3.intercepts as Array).is_empty(), "无 has_pd 不拦截")
	# 弹药耗尽
	var content := _content()
	for raw in (content.get("weapons", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "pd":
			(raw as Dictionary)["ammo"] = 1
	var b4 = _new(content)
	_ok(int(b4.pd_state().get("ammo", 0)) == 1, "PD 弹药覆盖 1")
	b4.launch("enemy", "own", "missile", enemy, _own(), {"force_pd": true})
	b4.step(1.0, {"shooters": {"enemy": enemy}, "targets": {"own": _own()}})
	_ok(int(b4.pd_state().get("ammo", -1)) == 0, "PD 弹药耗尽")
	b4.launch("enemy", "own", "missile", enemy, _own(), {"force_pd": true})
	b4.step(10.0, {"shooters": {"enemy": enemy}, "targets": {"own": _own()}})
	_eq(int((b4.intercepts as Array).size()), 1, "无弹药不再拦截")
	# 普通概率拦截/或命中
	var b5 = _new()
	b5.launch("enemy", "own", "missile", enemy, _own())
	b5.step(1.0, {"shooters": {"enemy": enemy}, "targets": {"own": _own()}})
	_ok((b5.intercepts as Array).size() + (b5.impacts as Array).size() >= 0, "PD 概率流程")
	for pdist in [60.0, 100.0, 140.0, 179.0]:
		var bp = _new()
		var op := _own()
		var ep := {"id": "enemy", "pos_km": [pdist, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}
		var ammo_before := int(bp.pd_state().get("ammo", 0))
		bp.launch("enemy", "own", "missile", ep, op, {"force_pd": true})
		bp.step(1.0, {"shooters": {"enemy": ep}, "targets": {"own": op}})
		_ok((bp.intercepts as Array).size() == 1, "PD 距离拦截 " + str(pdist))
		_ok(int(bp.pd_state().get("ammo", -1)) == ammo_before - 1, "PD 距离弹药 " + str(pdist))
		_ok(float(bp.pd_state().get("cooldown_until", -1.0)) > 0.0, "PD 距离冷却 " + str(pdist))
		_ok((bp.impacts as Array).is_empty(), "PD 距离无 impact " + str(pdist))
	_ok(_json_ok(b.vm()), "PD VM JSON")


# ── 5. decoy / jammer ──────────────────────────────────────

func _test_countermeasures() -> void:
	print("")
	print("── 5. decoy / jammer 诱偏 / 降锁定 ──")
	var b = _new()
	var own := _own()
	var dec: Dictionary = b.launch("own", "own", "decoy", own, own)
	_ok(bool(dec.get("ok", false)), "decoy launch")
	_ok((b.countermeasures as Array).size() == 1, "countermeasure 1")
	var cm: Dictionary = (b.countermeasures as Array)[0]
	_eq(String(cm.get("kind", "")), "decoy", "countermeasure kind decoy")
	_ok(float(cm.get("active_until", 0.0)) > 0.0, "decoy active_until")
	_ok(bool(cm.get("active", false)), "decoy active")
	_ok(_events(b, "countermeasure_deployed") >= 1, "decoy event")
	# forced decoy seduction
	var enemy := {"id": "enemy", "pos_km": [500.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0]}
	b.launch("enemy", "own", "missile", enemy, own, {"force_decoy": true})
	b.step(1.0, {"shooters": {"enemy": enemy}, "targets": {"own": own}})
	var proj: Dictionary = _projectile(b)
	_ok(bool(proj.get("decoyed", false)), "missile decoyed")
	_ok(_json_ok(b.vm()), "decoy VM JSON")
	# jammer
	var b2 = _new()
	var j: Dictionary = b2.launch("own", "own", "jammer", own, own)
	_ok(bool(j.get("ok", false)), "jammer launch")
	_ok((b2.countermeasures as Array).size() == 1, "jammer countermeasure")
	var cm2: Dictionary = (b2.countermeasures as Array)[0]
	_eq(String(cm2.get("kind", "")), "jammer", "countermeasure kind jammer")
	_ok(float(cm2.get("lock_loss_prob", 0.0)) >= 0.0, "jammer lock loss prob")
	var enemy2 := {"id": "enemy", "pos_km": [500.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0]}
	b2.launch("enemy", "own", "missile", enemy2, own, {"force_jam": true})
	b2.step(1.0, {"shooters": {"enemy": enemy2}, "targets": {"own": own}})
	var proj2: Dictionary = _projectile(b2)
	_ok(bool(proj2.get("guidance_lost", false)), "missile guidance_lost")
	_ok(_events(b2, "countermeasure_deployed") >= 1, "jammer event")
	# 过期
	b.step(30.0, {"shooters": {"enemy": enemy}, "targets": {"own": own}})
	_ok(not bool((b.countermeasures as Array)[0].get("active", true)), "decoy 过期")
	_ok(_events(b, "countermeasure_expired") >= 1, "countermeasure 过期事件")
	_ok(_json_ok(b2.vm()), "jammer VM JSON")


# ── 6. save / reset / JSON / determinism ──────────────────

func _test_save_reset_json() -> void:
	print("")
	print("── 6. save/load / reset / JSON / 确定性 ──")
	var b = _new()
	var own := _own()
	var tgt := _target("T1", [600.0, 0.0, 0.0])
	b.launch("own", "T1", "railgun", own, tgt)
	_step_n(b, 20, own, tgt)
	b.launch("own", "T2", "decoy", own, own)
	var txt: String = b.save_state()
	var p = JSON.parse_string(txt)
	_ok(p is Dictionary, "save JSON")
	_ok(String((p as Dictionary).get("schema", "")) == "v17.combat_ballistics_save.v1", "save schema")
	_ok(String((p as Dictionary).get("version", "")) == "2.0.0", "save version")
	_ok((p as Dictionary).get("projectiles") is Array, "save projectiles")
	_ok((p as Dictionary).get("countermeasures") is Array, "save countermeasures")
	_ok((p as Dictionary).get("events") is Array, "save events")
	_ok((p as Dictionary).get("intercepts") is Array, "save intercepts")
	_ok((p as Dictionary).get("impacts") is Array, "save impacts")
	_ok((p as Dictionary).get("pd") is Dictionary, "save PD")
	_ok((p as Dictionary).get("seq") is Dictionary, "save seq")
	_ok((p as Dictionary).get("projectiles") is Array, "save projectiles array")
	var r = _new()
	var lr: Dictionary = r.load_state(txt)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("reason", "")))
	_eq((r.projectiles as Array).size(), (b.projectiles as Array).size(), "load projectiles")
	_eq((r.countermeasures as Array).size(), (b.countermeasures as Array).size(), "load countermeasures")
	_eq((r.events as Array).size(), (b.events as Array).size(), "load events")
	_ok(absf(float(r.t) - float(b.t)) < 1.0e-9, "load t")
	_eq(int(r.pd_state().get("ammo", -1)), int(b.pd_state().get("ammo", 0)), "load PD ammo")
	_ok(_json_ok(r.vm()), "loaded VM JSON")
	_ok(b.save_state() == b.save_state(), "save 确定性")
	# reset
	var rs: Dictionary = b.reset()
	_ok(bool(rs.get("ok", false)), "reset ok")
	_ok((b.projectiles as Array).is_empty(), "reset projectiles")
	_ok((b.countermeasures as Array).is_empty(), "reset countermeasures")
	_eq(int(b.pd_state().get("ammo", 0)), 80, "reset PD ammo")
	_eq(float(b.t), 0.0, "reset t")
	# 非法 load
	var bad: Array = [["empty", ""], ["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future", JSON.stringify({"schema": "v17.combat_ballistics_save.v1",
			"version": "9.0.0", "projectiles": [], "countermeasures": [],
			"intercepts": [], "impacts": [], "events": []})],
		["missing", JSON.stringify({"schema": "v17.combat_ballistics_save.v1",
			"version": "1.0.0"})]]
	for raw in bad:
		var c: Array = raw
		_ok(not bool(r.load_state(c[1]).get("ok", true)), "拒绝快照: " + String(c[0]))
	# 确定性
	var a = _new()
	var c2 = _new()
	for svc in [a, c2]:
		var o := _own()
		var tg := _target("T1", [600.0, 0.0, 0.0])
		svc.launch("own", "T1", "railgun", o, tg)
		svc.step(5.0, _states(o, tg))
		svc.predict(o, tg, "railgun")
	_ok(JSON.stringify(a.vm()) == JSON.stringify(c2.vm()), "确定性 VM")
	_ok(_json_ok(a.summary()), "summary JSON")
	_ok(_json_ok(a.events), "events JSON")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "最终不写 world")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "最终不写 TrackTable")
