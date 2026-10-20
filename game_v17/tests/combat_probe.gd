extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# COMBAT PROBE · 完整游戏-阶段3G
#
# 验证：内容驱动武器、ROE 四档、TRACK/SOLUTION/FIRE 三级授权、范围/时限、
# 火控解算、发射/弹药/冷却、点防御/诱饵/干扰、命中/损伤事件、自动降级、
# 存档/恢复、JSON、确定性；只跑一次；不执行物理、不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const Combat := preload("res://scripts/core/combat_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("COMBAT PROBE · 完整游戏-阶段3G")
	print("════════════════════════════════════════════════════════════════")
	_test_content_setup()
	_test_roe_matrix()
	_test_authorization()
	_test_fire_control()
	_test_pd_decoy_jammer()
	_test_auto_downgrade()
	_test_save_load_json()
	print("────────────────────────────────────────────────────────────────")
	print("COMBAT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("COMBAT PROBE FAILED")
		quit(1)
	else:
		print("COMBAT PROBE OK")
		quit(0)


# ── 工具 ─────────────────────────────────────────────────────────

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


func _new(roe := "TIGHT") -> Object:
	return Combat.new({"roe": roe})


func _add(s, id: String, identity: String, range_km := 1000.0, in_arc := true) -> void:
	var threat := "unknown"
	if identity == "hostile":
		threat = "hostile"
	elif identity == "suspect":
		threat = "suspect"
	elif identity in ["friend", "assumed_friend", "neutral"]:
		threat = "none"
	s.register_track(id, {"identity": identity, "threat": threat,
		"range_km": range_km, "in_arc": in_arc, "ship_id": "target-" + id})


func _events_kind(s, kind: String) -> int:
	var n := 0
	for raw in (s.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _weapon(s, id: String) -> Dictionary:
	for raw in (s.vm().get("weapons", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}


# ── 1. 内容 / setup ─────────────────────────────────────────────

func _test_content_setup() -> void:
	print("")
	print("── 1. 内容驱动武器 / setup ──")
	var s = _new()
	_ok(bool(s.ready), "ready", str(s.errors))
	_ok((s.errors as Array).is_empty(), "content 无错误")
	_eq(String((s.content as Dictionary).get("schema", "")), "weapons.v1", "content schema")
	_eq((s.weapons as Dictionary).size(), 5, "5 武器")
	for wid in ["railgun", "missile", "pd", "jammer", "decoy"]:
		_ok((s.weapons as Dictionary).has(wid), "武器存在 " + wid)
	_ok(String((s.weapon_def("railgun") as Dictionary).get("kind", "")) == "kinetic", "railgun kinetic")
	_ok(String((s.weapon_def("missile") as Dictionary).get("kind", "")) == "guided", "missile guided")
	_ok(String((s.weapon_def("pd") as Dictionary).get("kind", "")) == "point_defense", "pd kind")
	_ok(String((s.weapon_def("jammer") as Dictionary).get("kind", "")) == "ew", "jammer kind")
	_ok(String((s.weapon_def("decoy") as Dictionary).get("kind", "")) == "decoy", "decoy kind")
	_ok(float((s.weapon_def("railgun") as Dictionary).get("range_km", 0.0)) > 0.0, "railgun range")
	_ok(float((s.weapon_def("missile") as Dictionary).get("range_km", 0.0)) > 0.0, "missile range")
	_ok(int((s.weapon_def("missile") as Dictionary).get("ammo", 0)) > 0, "missile ammo")
	_ok(float((s.weapon_def("missile") as Dictionary).get("solution_s", 0.0)) > 0.0, "solution_s")
	_ok((s.roe_defs as Dictionary).size() == 4, "ROE 四档")
	for lv in ["DEFEND", "HOLD", "TIGHT", "FREE"]:
		_ok((s.roe_defs as Dictionary).has(lv), "ROE " + lv)
	_eq(s.roe, "TIGHT", "默认 ROE TIGHT")
	_ok(String(s.roe_label()) != "", "ROE label")
	_ok(String(s.roe_label_en()) != "", "ROE label_en")
	_ok(String(s.vm().get("roe_label_en", "")) != "", "VM roe_label_en")
	_ok((s.vm() as Dictionary).has("weapons"), "VM weapons")
	_ok((s.vm() as Dictionary).has("tracks"), "VM tracks")
	_ok(_json_ok(s.vm()), "VM JSON")
	_ok(_json_ok(s.summary()), "summary JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("ui", true)) == false, "不写 UI")
	_ok(_json_ok(s.content), "content JSON")
	_ok((s.content.get("units") is Dictionary), "content units")
	_ok(((s.content.get("roe") as Dictionary).get("authorization_levels") as Array).size() == 3,
		"content 三级授权")
	_ok(((s.content.get("roe") as Dictionary).get("scopes") as Array).size() == 4,
		"content 四种 scope")
	for wid in ["railgun", "missile", "pd", "jammer", "decoy"]:
		_ok(String(s.weapon_def(wid).get("auth_level", "")) in ["TRACK", "SOLUTION", "FIRE"],
			"武器授权级别 " + wid)
	_ok(bool(s.weapon_def("missile").get("interceptable", false)), "missile 可拦截标记")
	_ok(float(s.weapon_def("decoy").get("duration_s", 0.0)) > 0.0, "decoy duration")
	_ok((s.grant_rows() as Array).is_empty(), "初始无授权")


# ── 2. ROE 四档矩阵 ────────────────────────────────────────────

func _test_roe_matrix() -> void:
	print("")
	print("── 2. ROE 四档 / TRACK-SOLUTION 自动/确认 ──")
	for lv in ["DEFEND", "HOLD", "TIGHT", "FREE"]:
		var s = _new(lv)
		for ident in ["hostile", "suspect", "unknown", "neutral"]:
			_add(s, "T-" + ident, ident, 1000.0 if ident != "suspect" else 1500.0, true)
		for ident in ["hostile", "suspect", "unknown", "neutral"]:
			var tr: Dictionary = s.request_track("T-" + ident)
			var expected_auto := false
			if lv in ["DEFEND", "HOLD"]:
				expected_auto = true
			elif lv == "TIGHT":
				expected_auto = ident in ["hostile", "suspect"]
			elif lv == "FREE":
				expected_auto = ident == "hostile"
			if expected_auto:
				_ok(bool(tr.get("ok", false)) and bool(tr.get("auto", false)),
					"%s TRACK %s auto" % [lv, ident], str(tr))
			else:
				_ok(not bool(tr.get("ok", true)) and String(tr.get("reason", "")) in
					["needs_confirmation", "needs_authorization"],
					"%s TRACK %s 需确认/授权" % [lv, ident], str(tr.get("reason", "")))
			var so: Dictionary = s.request_solution("T-" + ident, "missile", false)
			var auto_sol := false
			if lv == "DEFEND":
				auto_sol = ident == "hostile"
			elif lv in ["TIGHT", "FREE"]:
				auto_sol = ident == "hostile"
			if auto_sol:
				_ok(bool(so.get("ok", false)), "%s SOLUTION %s auto/允许" % [lv, ident],
					str(so.get("reason", "")))
			else:
				_ok(not bool(so.get("ok", true)), "%s SOLUTION %s 需确认" % [lv, ident],
					str(so.get("reason", "")))
		_eq(s.roe, lv, "ROE 设置为 " + lv)
		_ok(s.set_roe("FREE").get("ok", false), "切 FREE")
		_ok(s.set_roe("DEFEND").get("ok", false), "切 DEFEND")
		_ok(not bool(s.set_roe("NOPE").get("ok", true)), "非法 ROE false")
	_ok(_json_ok(_new().vm()), "ROE VM JSON")


# ── 3. 三级授权 / scope / 时限 ────────────────────────────────

func _test_authorization() -> void:
	print("")
	print("── 3. TRACK/SOLUTION/FIRE 授权 / scope / 时限 ──")
	var s = _new("TIGHT")
	_add(s, "T", "hostile", 3000.0, true)
	_add(s, "OTHER", "hostile", 3000.0, true)
	var g1: Dictionary = s.grant_authorization("FIRE", "target", "T")
	_ok(bool(g1.get("ok", false)), "target FIRE grant")
	_ok(not (s.check_authorization("FIRE", "T", "missile") as Dictionary).is_empty(),
		"target grant 匹配")
	_ok((s.check_authorization("FIRE", "OTHER", "missile") as Dictionary).is_empty(),
		"target grant 不匹配其他 target")
	_ok((s.check_authorization("SOLUTION", "T") as Dictionary).is_empty(),
		"level 隔离")
	_ok(bool(s.grant_authorization("FIRE", "weapon_group", "missile").get("ok", false)),
		"weapon_group grant")
	_ok(not (s.check_authorization("FIRE", "T", "missile") as Dictionary).is_empty(),
		"weapon_group 匹配")
	_ok((s.check_authorization("FIRE", "OTHER", "railgun") as Dictionary).is_empty(),
		"weapon_group 不匹配 railgun")
	_ok(bool(s.grant_authorization("FIRE", "ship", s.own_id).get("ok", false)), "ship grant")
	_ok(bool(s.grant_authorization("FIRE", "fleet", s.fleet_id).get("ok", false)), "fleet grant")
	_ok(not (s.check_authorization("FIRE", "T", "missile") as Dictionary).is_empty(),
		"fleet grant 匹配")
	_ok(not bool(s.grant_authorization("FIRE", "bad_scope", "x").get("ok", true)), "非法 scope false")
	_ok(not bool(s.grant_authorization("BAD", "target", "T").get("ok", true)), "非法 level false")
	_ok(not bool(s.grant_authorization("FIRE", "target", "").get("ok", true)), "空 scope_id false")
	# duration 到期
	var s2 = _new("TIGHT")
	_add(s2, "T", "hostile", 3000.0, true)
	var gd: Dictionary = s2.grant_authorization("FIRE", "target", "T", 2.0)
	_ok(bool(gd.get("ok", false)), "duration grant")
	_ok(not (s2.check_authorization("FIRE", "T") as Dictionary).is_empty(), "duration 未到期匹配")
	s2.tick(3.0)
	_ok((s2.check_authorization("FIRE", "T") as Dictionary).is_empty(), "duration 到期不匹配")
	_ok(_events_kind(s2, "authorization_expired") >= 1, "到期事件")
	# until destroyed
	var s3 = _new("TIGHT")
	_add(s3, "T", "hostile", 3000.0, true)
	_ok(bool(s3.grant_authorization("FIRE", "target", "T", 0.0, true).get("ok", false)),
		"until_destroyed grant")
	s3.update_track("T", {"destroyed": true})
	_ok((s3.check_authorization("FIRE", "T") as Dictionary).is_empty(), "摧毁后 until_destroyed 失效")
	# revoke
	var s4 = _new("TIGHT")
	_add(s4, "T", "hostile", 3000.0, true)
	var rg: Dictionary = s4.grant_authorization("FIRE", "target", "T")
	_ok(bool(rg.get("ok", false)), "revoke fixture grant")
	_ok(bool(s4.revoke_authorization(String((rg.get("grant", {}) as Dictionary).get("grant_id", ""))).get("ok", false)),
		"revoke grant")
	_ok((s4.check_authorization("FIRE", "T") as Dictionary).is_empty(), "revoke 后不匹配")
	_ok(bool(s4.grant_authorization("FIRE", "target", "T").get("ok", false)), "再次 grant")
	_ok(bool(s4.revoke_authorization("").get("ok", false)), "revoke all")
	_ok((s4.check_authorization("FIRE", "T") as Dictionary).is_empty(), "revoke all 后不匹配")
	# TRACK/SOLUTION grant 允许非自动动作
	var s5 = _new("DEFEND")
	_add(s5, "T", "suspect", 3000.0, false)
	_ok(not bool(s5.request_solution("T", "missile", false).get("ok", true)), "DEFEND suspect solution 需确认")
	_ok(bool(s5.grant_authorization("SOLUTION", "target", "T").get("ok", false)), "SOLUTION grant")
	_ok(bool(s5.request_solution("T", "missile", false).get("ok", false)), "SOLUTION grant 允许")
	_ok(_json_ok(s5.vm()), "auth VM JSON")


# ── 4. 火控 / 发射 / 弹药 / 冷却 / 命中 ───────────────────────

func _test_fire_control() -> void:
	print("")
	print("── 4. 火控解算 / 授权 / 发射 / 命中损伤 ──")
	var s = _new("TIGHT")
	_add(s, "T", "hostile", 3000.0, true)
	_ok(bool(s.request_track("T").get("ok", false)), "TIGHT TRACK auto")
	var so: Dictionary = s.request_solution("T", "missile", false)
	_ok(bool(so.get("ok", false)), "TIGHT SOLUTION auto")
	var sid := String((so.get("solution", {}) as Dictionary).get("solution_id", ""))
	var before: Dictionary = s.solution_status(sid)
	_eq(String(before.get("status", "")), "COMPUTING", "solution COMPUTING")
	_ok(float(before.get("ready_t", 0.0)) > float(before.get("start_t", 0.0)), "solution ready_t")
	_ok(not bool(s.request_fire("T", "missile", false).get("ok", true)), "fire 未确认 false")
	_ok(not bool(s.request_fire("T", "missile", true).get("ok", true)), "fire 未授权 false")
	_ok(_events_kind(s, "solution_started") >= 1, "solution_started event")
	s.tick(1.0)
	_eq(String(s.solution_status(sid).get("status", "")), "COMPUTING", "解算未完")
	s.tick(10.0)
	var ready: Dictionary = s.solution_status(sid)
	_eq(String(ready.get("status", "")), "READY", "solution READY")
	_ok(float(ready.get("quality", 0.0)) > 0.0, "solution quality")
	_ok(float(ready.get("error_km", -1.0)) >= 0.0, "solution error_km")
	_ok(_events_kind(s, "solution_ready") >= 1, "solution_ready event")
	var gr: Dictionary = s.grant_authorization("FIRE", "target", "T")
	_ok(bool(gr.get("ok", false)), "FIRE grant")
	var pred: Dictionary = s.predict_shot("T", "missile")
	_ok(bool(pred.get("ok", false)), "predict_shot ok")
	_ok(bool(pred.get("no_physics", false)), "predict 不执行物理")
	_ok(String(pred.get("trajectory", "")) == "interface_only", "trajectory 接口标记")
	_ok(float(pred.get("time_of_flight_s", -1.0)) > 0.0, "预测飞行时间")
	_ok(float(pred.get("hit_probability", -1.0)) > 0.0, "预测命中概率")
	var ammo_before := int(_weapon(s, "missile").get("ammo", 0))
	var fire: Dictionary = s.request_fire("T", "missile", true)
	_ok(bool(fire.get("ok", false)), "fire 成功", str(fire.get("reason", "")))
	var ammo_after := int(_weapon(s, "missile").get("ammo", 0))
	_eq(ammo_after, ammo_before - 1, "发射消耗弹药")
	_ok(bool(fire.get("hit", false)) or String(fire.get("reason", "")) == "miss", "命中/miss 二选一")
	_ok(_events_kind(s, "weapon_launch") >= 1, "weapon_launch event")
	if bool(fire.get("hit", false)):
		_ok((fire.get("damage_event", {}) as Dictionary).get("schema", "") == "combat_damage_event.v1",
			"damage_event schema")
		_ok(not bool((fire.get("damage_event", {}) as Dictionary).get("applied", true)),
			"damage 不直接 applied")
		_ok(_events_kind(s, "combat_hit") >= 1, "combat_hit event")
	else:
		_ok(_events_kind(s, "combat_miss") >= 1, "combat_miss event")
	var cooldown: Dictionary = s.request_fire("T", "missile", true)
	_ok(not bool(cooldown.get("ok", true)) and
		String(cooldown.get("reason", "")) in ["cooldown", "no_ready_solution"], "冷却/无解阻止发射",
		String(cooldown.get("reason", "")))
	# 新解算后冷却结束可再发射
	var so2: Dictionary = s.request_solution("T", "missile", false)
	if bool(so2.get("ok", false)):
		s.tick(21.0)
		var fire2: Dictionary = s.request_fire("T", "missile", true)
		_ok(bool(fire2.get("ok", false)) or String(fire2.get("reason", "")) == "cooldown",
			"冷却后/仍冷却状态合法", String(fire2.get("reason", "")))
	else:
		_ok(false, "第二次解算失败", str(so2.get("reason", "")))
	# 非进攻武器/未知目标/未知武器/超距
	var ok_bad := 0
	for case in [["NOPE", "missile"], ["T", "NOPE"], ["T", "pd"], ["T", "jammer"]]:
		var c: Array = case
		var r: Dictionary = s.request_solution(String(c[0]), String(c[1]), false)
		if not bool(r.get("ok", true)):
			ok_bad += 1
	_eq(ok_bad, 4, "未知/非进攻目标武器解算拒绝")
	_add(s, "FAR", "hostile", 99999.0, true)
	_ok(not bool(s.request_solution("FAR", "missile", false).get("ok", true)), "超距解算拒绝")
	_ok(_json_ok(s.vm()), "fire control VM JSON")
	# 命中造成的 damage_taken（若命中）
	if bool(fire.get("hit", false)):
		_ok(float(s.track("T").get("damage_taken", 0.0)) > 0.0, "tracks damage_taken 更新（接口内）")
	# FIRE 范围（weapon_group）
	var sw = _new("TIGHT")
	_add(sw, "T", "hostile", 3000.0, true)
	sw.request_solution("T", "missile", true)
	sw.tick(11.0)
	_ok(bool(sw.grant_authorization("FIRE", "weapon_group", "missile").get("ok", false)),
		"weapon_group FIRE grant")
	var fwg: Dictionary = sw.request_fire("T", "missile", true)
	_ok(bool(fwg.get("ok", false)), "weapon_group 允许发射", str(fwg.get("reason", "")))


# ── 5. 点防御 / 诱饵 / 干扰 / incoming ───────────────────────

func _test_pd_decoy_jammer() -> void:
	print("")
	print("── 5. 点防御 / 诱饵 / 干扰 / incoming ──")
	var s = _new("TIGHT")
	_add(s, "T", "hostile", 500.0, true)
	var pd_before := int(_weapon(s, "pd").get("ammo", 0))
	var inc: Dictionary = s.incoming_missile("threat", "T", 0.5)
	_ok(bool(inc.get("ok", false)), "incoming_missile 注册")
	_ok(_events_kind(s, "incoming_detected") >= 1, "incoming_detected event")
	s.tick(2.0)
	_ok(_events_kind(s, "point_defense") >= 1, "点防御事件")
	_ok(int(_weapon(s, "pd").get("ammo", 0)) == pd_before - 1, "点防御消耗弹药")
	_ok(_events_kind(s, "combat_intercept") + _events_kind(s, "incoming_impact") >= 1,
		"拦截或命中事件")
	# 诱饵
	var s2 = _new("TIGHT")
	_add(s2, "T", "hostile", 500.0, true)
	var dec_before := int(_weapon(s2, "decoy").get("ammo", 0))
	var dec: Dictionary = s2.launch_decoy()
	_ok(bool(dec.get("ok", false)), "launch_decoy")
	_eq(int(_weapon(s2, "decoy").get("ammo", 0)), dec_before - 1, "诱饵消耗")
	_ok(float(dec.get("active_until", -1.0)) > float(s2.t), "诱饵激活窗口")
	_ok(not bool(s2.launch_decoy().get("ok", true)), "诱饵冷却阻止连发")
	_ok(_events_kind(s2, "decoy_launched") >= 1, "decoy event")
	# 干扰
	var s3 = _new("TIGHT")
	var jam_before := int(_weapon(s3, "jammer").get("ammo", 0))
	var jam: Dictionary = s3.activate_jammer("T")
	_ok(bool(jam.get("ok", false)), "activate_jammer")
	_eq(int(_weapon(s3, "jammer").get("ammo", 0)), jam_before - 1, "干扰消耗")
	_ok(float(jam.get("active_until", -1.0)) > float(s3.t), "干扰窗口")
	_ok(not bool(s3.activate_jammer("T").get("ok", true)), "干扰冷却阻止")
	_ok(_events_kind(s3, "jammer_active") >= 1, "jammer event")
	_ok(_json_ok(s.vm()) and _json_ok(s2.vm()) and _json_ok(s3.vm()), "PD/decoy/jammer JSON")
	# 不可拦截 incoming
	var s4 = _new("TIGHT")
	_add(s4, "T", "hostile", 500.0, true)
	s4.incoming_missile("threat", "T", 0.5, {"interceptable": false})
	s4.tick(2.0)
	_ok(_events_kind(s4, "incoming_impact") >= 1, "不可拦截 incoming 命中")
	_ok(((s4.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "incoming 不写 world")


# ── 6. 自动降级 ───────────────────────────────────────────────

func _test_auto_downgrade() -> void:
	print("")
	print("── 6. 自动降级 ──")
	var s = _new("FREE")
	_ok(bool(s.set_roe("FREE").get("ok", false)), "set FREE")
	var r: Dictionary = s.set_sensor_damage(0.7)
	_ok(String(s.roe) == "HOLD", "传感器损坏 → HOLD", str(s.roe))
	_ok(_events_kind(s, "roe_downgrade") >= 1, "降级事件")
	_ok(String(r.get("roe", "")) == "HOLD", "set_sensor_damage 返回 roe")
	var s2 = _new("FREE")
	_ok(bool(s2.set_link_lost(true).get("ok", false)), "link lost")
	_eq(String(s2.roe), "HOLD", "链路丢失 → HOLD")
	var s3 = _new("FREE")
	_add(s3, "T", "friend", 1000.0, true)
	var u: Dictionary = s3.update_track("T", {"identity": "neutral", "in_arc": true})
	_ok(bool(u.get("ok", false)), "update neutral in arc")
	_eq(String(s3.roe), "HOLD", "中立进入射界 → HOLD")
	var s4 = _new("FREE")
	_add(s4, "T", "hostile", 3000.0, true)
	s4.weapons["missile"]["ammo"] = 0
	s4.weapons["railgun"]["ammo"] = 0
	s4.tick(0.1)
	_eq(String(s4.roe), "HOLD", "弹药耗尽 → HOLD")
	var s5 = _new("HOLD")
	s5.set_sensor_damage(0.8)
	_eq(String(s5.roe), "HOLD", "已 HOLD 不再降级")
	var s6 = _new("TIGHT")
	s6.set_sensor_damage(0.9)
	_eq(String(s6.roe), "HOLD", "TIGHT 损坏 → HOLD")
	_ok(_json_ok(s.vm()), "downgrade VM JSON")


# ── 7. save/load / JSON / 确定性 ─────────────────────────────

func _test_save_load_json() -> void:
	print("")
	print("── 7. save/load / JSON / 确定性 ──")
	var s = _new("TIGHT")
	_add(s, "T", "hostile", 3000.0, true)
	s.request_track("T")
	s.request_solution("T", "missile", true)
	s.tick(11.0)
	s.grant_authorization("FIRE", "target", "T", 60.0)
	_ok(bool(s.launch_decoy().get("ok", false)), "存档前 decoy")
	var text: String = s.save_state()
	var p = JSON.parse_string(text)
	_ok(p is Dictionary, "save_state JSON")
	_ok(String((p as Dictionary).get("schema", "")) == "v17.combat_service_save.v1", "save schema")
	_ok(String((p as Dictionary).get("version", "")) == "1.0.0", "save version")
	_ok((p as Dictionary).get("weapons") is Dictionary, "save weapons")
	var r = _new()
	var lr: Dictionary = r.load_state(text)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("reason", "")))
	_eq(String(r.roe), "TIGHT", "load roe")
	_eq(int(_weapon(r, "missile").get("ammo", 0)), int(_weapon(s, "missile").get("ammo", 0)),
		"load ammo")
	_ok(bool(r.track("T").size() > 0), "load track")
	_ok((r.grants as Dictionary).size() >= 1, "load grant")
	_ok(absf(float(r.t) - float(s.t)) < 1.0e-9, "load t")
	_ok(float(r.decoy_until) >= float(r.t), "load decoy")
	_ok(_events_kind(r, "solution_ready") >= 1, "load events")
	_ok(_json_ok(r.vm()), "loaded VM JSON")
	_ok(s.save_state() == s.save_state(), "save 确定性")
	# 非法快照拒绝
	var bad: Array = [
		["empty", ""],
		["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future", JSON.stringify({"schema": "v17.combat_service_save.v1",
			"version": "9.0.0", "weapons": {}, "tracks": [], "solutions": [],
			"grants": []})],
		["old", JSON.stringify({"schema": "v17.combat_service_save.v1",
			"version": "0.9.0", "weapons": {}, "tracks": [], "solutions": [],
			"grants": []})],
	]
	for raw in bad:
		var c: Array = raw
		_ok(not bool(r.load_state(c[1]).get("ok", true)), "拒绝存档: " + String(c[0]))
	# 确定性双实例
	var a = _new("TIGHT")
	var b = _new("TIGHT")
	for svc in [a, b]:
		_add(svc, "T", "hostile", 3000.0, true)
		svc.request_track("T")
		svc.request_solution("T", "missile", true)
		svc.tick(11.0)
		svc.grant_authorization("FIRE", "target", "T")
		svc.request_fire("T", "missile", true)
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(_json_ok(a.summary()), "summary JSON")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "最终不写 world")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "最终不写 V15")
