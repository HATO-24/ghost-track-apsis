extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R6-SHADOW-1 headless probe：CR3BP/RK4 物理 shadow 接入 V17 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_physics_shadow_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const BridgeScript := preload("res://scripts/framework_bridge.gd")
const StateScript := preload("res://scripts/state.gd")
const NAV_CONTENT_PATH := "res://framework/content/navigation_l1.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	OS.set_environment("V17_PHYSICS", "shadow")
	print("════════════════════════════════════════════════════════════")
	print("R6-SHADOW-1 PROBE · CR3BP/RK4 物理 shadow 接入")
	print("════════════════════════════════════════════════════════════")
	_test_boot_and_entities()
	_test_reference()
	_test_step_and_jacobi()
	_test_v15_unchanged()
	_test_nav_position_provider()
	_test_state_fields()
	_test_json()
	_test_no_auto_execute()
	_test_off_mode()
	_test_restart()
	_test_long_run()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PHYSICS SHADOW PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PHYSICS SHADOW PROBE FAILED")
		quit(1)
	else:
		print("V17 PHYSICS SHADOW PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%.5f expected=%.5f diff=%.5f tol=%.5f" % [
		actual, expected, diff, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _make_bridge():
	var br = BridgeScript.new()
	var ok: bool = br.boot()
	_ok(ok, "bridge.boot", str(br.errors))
	_ok(br.physics_ready, "bridge.physics_ready", str(br.errors))
	return br

func _make_state(br, skip_prelude := true):
	var st = StateScript.new()
	if skip_prelude and st.prelude_open:
		st.prelude_skip()
	st.framework = br
	st.fw_sync(0.0)
	return st

func _entity_row(view: Dictionary, eid: String) -> Dictionary:
	for raw in (view.get("entities", []) as Array):
		if String((raw as Dictionary).get("id", "")) == eid:
			return raw
	return {}

func _ref_lagrange(view: Dictionary, lid: String) -> Dictionary:
	var ref: Dictionary = view.get("reference", {})
	var lag: Dictionary = ref.get("lagrange", {}) if ref.get("lagrange") is Dictionary else {}
	return lag.get(lid, {}) if lag.get(lid) is Dictionary else {}

func _vec(d: Dictionary, key: String) -> Array:
	return (d.get(key, []) as Array)

func _vec_len(arr: Array) -> float:
	if arr.size() < 3:
		return -1.0
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2])).length()

func _vec_dist(a: Array, b: Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return -1.0
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(
		Vector3(float(b[0]), float(b[1]), float(b[2])))

func _earth_rot_pos(row: Dictionary) -> Array:
	var st: Dictionary = (row.get("state_earth_rot", {}) as Dictionary) if row.get("state_earth_rot") is Dictionary else {}
	return _vec(st, "r")

func _track_snapshot(st) -> Dictionary:
	var tr: Dictionary = st.tracks[st.selected] if not st.tracks.is_empty() else {}
	return {
		"id": String(tr.get("id", "")),
		"r": str(tr.get("r", Vector3.ZERO)),
		"v": str(tr.get("v", Vector3.ZERO)),
		"level": int(tr.get("level", 0)),
		"identity": String(tr.get("identity", "")),
		"sensor": int(st.sensor),
		"clock": float(st.clock),
		"decision": bool(st.decision_open),
		"count": st.tracks.size(),
	}

# ═══════════════════════════════════════════════════════════════════
# 1. boot / 实体装载
# ═══════════════════════════════════════════════════════════════════

func _test_boot_and_entities() -> void:
	_section_begin("1 boot / 实体")
	var br = _make_bridge()
	_eq(br.physics_mode, "shadow", "physics_mode=shadow（默认）")
	_ok(br.physics != null, "physics 实例存在")
	var view: Dictionary = br.physics_view()
	for key in ["schema", "model", "authoritative", "mode", "ready", "t", "step_s",
			"config", "entities", "reference", "warnings", "v15_orbit_source", "note"]:
		_ok(view.has(key), "physics_view 含字段: " + key)
	_eq(String(view.get("schema", "")), "cislunar_physics.v1", "schema")
	_eq(bool(view.get("authoritative", true)), false, "authoritative=false（shadow）")
	_eq(String(view.get("mode", "")), "shadow", "mode=shadow")
	_ok(float(view.get("step_s", 999.0)) <= 60.0, "固定步长 ≤60s", str(view.get("step_s")))
	var entities: Array = view.get("entities", [])
	_ok(entities.size() >= 9, "实体数 ≥9", str(entities.size()))
	var ids: Array = []
	for raw in entities:
		var row: Dictionary = raw
		var eid := String(row.get("id", ""))
		ids.append(eid)
		for key in ["id", "source", "state_rot", "state_earth_eci", "state_earth_rot",
				"jacobi", "jacobi0", "jacobi_drift", "finite", "earth_distance_km", "moon_distance_km"]:
			_ok(row.has(key), "%s 含 %s" % [eid, key])
		_eq(bool(row.get("finite", false)), true, "%s finite" % eid)
		_ok(_vec_len(_earth_rot_pos(row)) > 0.0, "%s state_earth_rot.r 有效" % eid)
		_ok(_vec_len(_vec((row.get("state_earth_eci", {}) as Dictionary), "r")) > 0.0,
			"%s state_earth_eci.r 有效" % eid)
		var src := String(row.get("source", ""))
		_ok(src != "", "%s source 非空" % eid)
		_ok(src.contains("非星历") or src.contains("占位") or src.contains("默认"),
			"%s source 明确标注近似/默认" % eid, src)
	for need in ["harmattan", "apsis", "summons_4471", "chronos_station", "tank_farm"]:
		_ok(need in ids, "实体存在: " + need)
	_data_line("boot", "mode=shadow entities=%d step≤60s authoritative=false" % entities.size())

# ═══════════════════════════════════════════════════════════════════
# 2. L1–L5 / GEO / LLO / 月球参考
# ═══════════════════════════════════════════════════════════════════

func _test_reference() -> void:
	_section_begin("2 L1–L5 / GEO / LLO")
	var br = _make_bridge()
	var ref: Dictionary = br.physics_view().get("reference", {})
	var lag: Dictionary = ref.get("lagrange", {})
	_eq(lag.size(), 5, "lagrange 5 点")
	var l1: Dictionary = _ref_lagrange(br.physics_view(), "L1")
	var l2: Dictionary = _ref_lagrange(br.physics_view(), "L2")
	var l3: Dictionary = _ref_lagrange(br.physics_view(), "L3")
	var l4: Dictionary = _ref_lagrange(br.physics_view(), "L4")
	var l5: Dictionary = _ref_lagrange(br.physics_view(), "L5")
	_near(float(l1.get("distance_earth_km", 0.0)), 326381.0, 5.0, "L1 到地 ≈326,381 km")
	_near(float(l2.get("distance_earth_km", 0.0)), 448915.0, 10.0, "L2 到地 ≈448,915 km")
	_near(float(l3.get("distance_earth_km", 0.0)), 381675.0, 5.0, "L3 到地 ≈381,675 km")
	var l3r: Array = _vec(l3, "position_earth_rot_km")
	_ok(float(l3r[0]) < 0.0, "L3 在反月侧（earth_rot x<0）")
	_near(float(l4.get("distance_earth_km", 0.0)), 384400.0, 5.0, "L4 到地=384,400")
	_near(float(l4.get("distance_moon_km", 0.0)), 384400.0, 5.0, "L4 到月=384,400")
	_near(float(l5.get("distance_earth_km", 0.0)), 384400.0, 5.0, "L5 到地=384,400")
	var geo: Dictionary = ref.get("geo", {})
	_near(float(geo.get("radius_km", 0.0)), 42164.0, 1.0e-6, "GEO 半径=42,164")
	_ok(absf(float(geo.get("period_s", 0.0)) - 86164.0) < 20.0, "GEO 周期≈86164 s",
		str(geo.get("period_s")))
	_near(_vec_len(_vec(geo, "position_earth_rot_km")), 42164.0, 2.0, "GEO 位置半径 42,164")
	var llo: Dictionary = ref.get("lunar_leo", {})
	_near(float(llo.get("radius_km", 0.0)), 1837.4, 1.0e-6, "LLO 半径=R_moon+100")
	_near(float(llo.get("distance_moon_km", 0.0)), 1837.4, 5.0, "LLO 到月≈1,837.4")
	var moon: Dictionary = ref.get("moon", {})
	_near(float(moon.get("distance_km", 0.0)), 384400.0, 1.0e-6, "月球距离=384,400")
	_data_line("reference", "L1=%.0f L2=%.0f L3=%.0f L4=%.0f GEO=%.0f LLO=%.1f" % [
		float(l1.get("distance_earth_km", 0.0)), float(l2.get("distance_earth_km", 0.0)),
		float(l3.get("distance_earth_km", 0.0)), float(l4.get("distance_earth_km", 0.0)),
		float(geo.get("radius_km", 0.0)), float(llo.get("radius_km", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 3. step / Jacobi / warnings
# ═══════════════════════════════════════════════════════════════════

func _test_step_and_jacobi() -> void:
	_section_begin("3 step / Jacobi")
	var br = _make_bridge()
	var view0: Dictionary = br.physics_view()
	var pos0 := _earth_rot_pos(_entity_row(view0, "harmattan"))
	_near(float(view0.get("t", -1.0)), 0.0, 1.0e-9, "初始 t=0")
	br.sync(300.0)
	var view1: Dictionary = br.physics_view()
	_near(float(view1.get("t", 0.0)), 300.0, 1.0e-9, "sync(300) 后 shadow t=300")
	var pos1 := _earth_rot_pos(_entity_row(view1, "harmattan"))
	_ok(_vec_dist(pos0, pos1) > 0.0, "实体位置随时间变化",
		"Δ=%.3f km" % _vec_dist(pos0, pos1))
	var summary: Dictionary = br.physics_summary()
	_near(float(summary.get("t", 0.0)), 300.0, 1.0e-9, "physics_summary.t=300")
	_ok(int(summary.get("entities", 0)) >= 9, "summary.entities≥9")
	_ok(bool(summary.get("nav_position_provider", false)), "summary.nav_position_provider=true")
	_ok(float(summary.get("max_jacobi_drift", 1.0)) < 1.0e-4, "Jacobi 漂移 <1e-4",
		"%.8f" % float(summary.get("max_jacobi_drift", 0.0)))
	var warns: Array = view1.get("warnings", [])
	var fatal := false
	for raw in warns:
		var w := String(raw)
		if w.contains("发散") or w.contains("失败"):
			fatal = true
	_ok(not fatal, "无发散/失败 warnings", str(warns))
	_data_line("step", "t=0→300s；位置变化；max_jacobi_drift=%.8f；warnings=%d" % [
		float(summary.get("max_jacobi_drift", 0.0)), warns.size()])

# ═══════════════════════════════════════════════════════════════════
# 4. V15 轨道/HUD 数据不被修改
# ═══════════════════════════════════════════════════════════════════

func _test_v15_unchanged() -> void:
	_section_begin("4 V15 数据不变")
	var br = _make_bridge()
	var st = _make_state(br)
	var snap0 := _track_snapshot(st)
	var world_orbit0 := JSON.stringify((br.world.by_id.get("harmattan") as V2Entity).orbit)
	br.sync(120.0)
	st.fw_sync(0.0)
	var snap1 := _track_snapshot(st)
	_eq(snap1.get("id"), snap0.get("id"), "V15 选中航迹 id 不变")
	_eq(snap1.get("r"), snap0.get("r"), "V15 轨道位置 r 不变")
	_eq(snap1.get("v"), snap0.get("v"), "V15 速度 v 不变")
	_eq(snap1.get("level"), snap0.get("level"), "V15 接触等级不变")
	_eq(snap1.get("identity"), snap0.get("identity"), "V15 身份不变")
	_eq(snap1.get("sensor"), snap0.get("sensor"), "V15 传感器选择不变")
	_eq(snap1.get("clock"), snap0.get("clock"), "V15 clock 不变")
	_eq(snap1.get("decision"), snap0.get("decision"), "V15 决策状态不变")
	_eq(snap1.get("count"), snap0.get("count"), "V15 航迹数量不变")
	var world_orbit1 := JSON.stringify((br.world.by_id.get("harmattan") as V2Entity).orbit)
	_eq(world_orbit1, world_orbit0, "V2 world 实体 orbit 未被 physics 修改")
	_eq(String(br.physics_view().get("v15_orbit_source", "")).contains("unchanged"), true,
		"physics 声明 V15 位置源 unchanged")
	_data_line("v15", "选中轨迹/等级/身份/传感器/clock/决策/实体 orbit 全部不变；physics authoritative=false")

# ═══════════════════════════════════════════════════════════════════
# 5. navigation 位置 provider 绑定
# ═══════════════════════════════════════════════════════════════════

func _test_nav_position_provider() -> void:
	_section_begin("5 navigation 位置 provider")
	var br = _make_bridge()
	var ref: Dictionary = br.physics_view().get("reference", {})
	var nav_pos: Dictionary = br.nav.resolve_positions()
	var l1_nav: Array = nav_pos.get("l1", [])
	var l1_phys: Array = _vec(_ref_lagrange(br.physics_view(), "L1"), "position_earth_rot_km")
	_near(_vec_len(l1_nav), 326381.0, 5.0, "nav l1 位置≈physics L1 326,381 km")
	_ok(_vec_dist(l1_nav, l1_phys) < 1.0, "nav l1 与 physics L1 一致（<1 km）",
		"Δ=%.4f" % _vec_dist(l1_nav, l1_phys))
	# 与内容 abstract 坐标不同（证明 provider 已替换）
	var nav_content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NAV_CONTENT_PATH))
	var abstract_l1 := 326283.0
	_ok(absf(_vec_len(l1_nav) - abstract_l1) > 50.0, "nav l1 已替换 abstract 坐标",
		"phys=%.1f abstract=%.1f" % [_vec_len(l1_nav), abstract_l1])
	var geo_nav: Array = nav_pos.get("geo", [])
	_near(_vec_len(geo_nav), 42164.0, 2.0, "nav geo 半径 42,164（physics）")
	var l4_nav: Array = nav_pos.get("l4", [])
	_near(_vec_len(l4_nav), 384400.0, 5.0, "nav l4 到地 384,400")
	var l2_nav: Array = nav_pos.get("l2", [])
	_near(_vec_len(l2_nav), 448915.0, 10.0, "nav l2 到地 448,915")
	var moon_phys: Array = _vec((ref.get("moon", {}) as Dictionary), "position_earth_rot_km")
	var moon_port_nav: Array = nav_pos.get("moon_port", [])
	_near(_vec_dist(moon_port_nav, moon_phys), 1737.4, 5.0, "nav moon_port 到月≈1,737.4")
	var llo_nav: Array = nav_pos.get("lunar_leo", [])
	_near(_vec_dist(llo_nav, moon_phys), float((ref.get("lunar_leo", {}) as Dictionary).get("distance_moon_km", 0.0)),
		5.0, "nav lunar_leo 到月≈LLO 半径")
	# provider 不影响路线规划/不自动执行
	var routes: Dictionary = br.nav_plan_routes("l1", "geo")
	_eq(bool(routes.get("ok", false)), true, "provider 绑定后路线规划正常")
	_eq((br.navigation_view().get("planned_maneuvers", []) as Array).size(), 0,
		"位置 provider 不自动创建机动")
	_data_line("nav-provider", "l1=%.0f l2=%.0f l4=%.0f geo=%.0f moon_port→月=%.0f km" % [
		_vec_len(l1_nav), _vec_len(l2_nav), _vec_len(l4_nav), _vec_len(geo_nav),
		_vec_dist(moon_port_nav, moon_phys)])

# ═══════════════════════════════════════════════════════════════════
# 6. state 字段
# ═══════════════════════════════════════════════════════════════════

func _test_state_fields() -> void:
	_section_begin("6 state 字段")
	var br = _make_bridge()
	var st = _make_state(br)
	_eq(st.fw_physics_ready, true, "state.fw_physics_ready")
	_eq(st.fw_physics_mode, "shadow", "state.fw_physics_mode=shadow")
	_ok(st.fw_physics.size() > 0, "state.fw_physics 非空")
	_ok((st.fw_physics.get("entities", []) as Array).size() >= 9, "fw_physics.entities≥9")
	_eq(bool(st.fw_physics.get("authoritative", true)), false, "fw_physics.authoritative=false")
	_eq(bool(st.fw_physics_summary.get("authoritative", true)), false,
		"fw_physics_summary.authoritative=false")
	_ok(st.fw_physics_summary.has("t"), "fw_physics_summary 有 t")
	# 旧字段不受影响
	_eq(st.fw_nav_ready, true, "旧 fw_nav_ready 仍 true")
	_eq(st.fw_damage_model, true, "旧 fw_damage_model 仍 true")
	_ok((st.fw_damage.get("sections", []) as Array).size() == 3, "旧 fw_damage 仍 3 项")
	_ok(st.fw_flow.size() > 0, "旧 fw_flow 非空")
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["physics", "physics_summary", "physics_ready", "physics_mode"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	st.fw_sync(0.0)
	_ok(st.fw_physics.size() > 0, "fw_sync 刷新后 fw_physics 仍非空")
	_data_line("state", "fw_physics/fw_physics_ready/fw_physics_summary/fw_physics_mode；旧字段不变")

# ═══════════════════════════════════════════════════════════════════
# 7. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("7 JSON")
	var br = _make_bridge()
	var st = _make_state(br)
	br.sync(60.0)
	st.fw_sync(0.0)
	var js := JSON.stringify(st.fw_physics)
	_ok(js.length() > 4000, "fw_physics JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "JSON 回读 Dictionary")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("entities") is Array, "回读 entities")
		_ok(pd.get("reference") is Dictionary, "回读 reference")
		_ok(((pd.get("reference", {}) as Dictionary).get("lagrange", {}) as Dictionary).size() == 5,
			"回读 reference.lagrange=5")
		_ok(pd.get("warnings") is Array, "回读 warnings")
	var bs_js := JSON.stringify(st.fw_bridge_state())
	_ok(bs_js.length() > 6000, "fw_bridge_state JSON 输出", "len=%d" % bs_js.length())
	var bp = JSON.parse_string(bs_js)
	_ok(bp is Dictionary, "fw_bridge_state 回读 Dictionary")
	if bp is Dictionary:
		_ok((bp.get("physics", {}) as Dictionary).get("entities") is Array,
			"fw_bridge_state 回读 physics.entities")
	_data_line("json", "fw_physics/fw_bridge_state JSON 可序列化/回读")

# ═══════════════════════════════════════════════════════════════════
# 8. 不自动执行导航机动
# ═══════════════════════════════════════════════════════════════════

func _test_no_auto_execute() -> void:
	_section_begin("8 不自动执行")
	var br = _make_bridge()
	var p: Dictionary = br.nav_plan_maneuver("hold")
	var pid := String(p.get("plan_id", ""))
	_ok(br.nav_authorize(pid).get("ok", false), "授权 hold")
	br.sync(200.0)
	_eq(String(_nav_state(br, pid)), "AUTHORIZED", "physics 步进不会自动执行导航机动")
	_ok(float(br.physics_view().get("t", 0.0)) > 0.0, "physics 确实在推进")
	_data_line("no-auto", "physics sync 200s：nav 计划仍 AUTHORIZED（不自动执行）")

func _nav_state(br, plan_id: String) -> String:
	for raw in (br.navigation_view().get("planned_maneuvers", []) as Array):
		if String((raw as Dictionary).get("id", "")) == plan_id:
			return String((raw as Dictionary).get("state", ""))
	return ""

# ═══════════════════════════════════════════════════════════════════
# 9. V17_PHYSICS=off
# ═══════════════════════════════════════════════════════════════════

func _test_off_mode() -> void:
	_section_begin("9 V17_PHYSICS=off")
	OS.set_environment("V17_PHYSICS", "off")
	var br = BridgeScript.new()
	var ok: bool = br.boot()
	OS.set_environment("V17_PHYSICS", "off")
	_eq(ok, true, "off 模式 bridge.boot 仍成功")
	_eq(br.physics_mode, "off", "physics_mode=off")
	_eq(br.physics_ready, false, "physics_ready=false")
	_eq(br.physics_view().size(), 0, "physics_view 空")
	_ok(br.nav_ready, "off 模式导航仍 ready")
	# provider 未绑定 → 回退 abstract 坐标
	var l1_nav: Array = br.nav.resolve_positions().get("l1", [])
	_near(_vec_len(l1_nav), 326283.0, 2.0, "off 模式 nav l1 回退 abstract 326,283")
	var st = _make_state(br)
	_eq(st.fw_physics_ready, false, "state.fw_physics_ready=false")
	_eq(st.fw_physics_mode, "off", "state.fw_physics_mode=off")
	_data_line("off", "V17_PHYSICS=off：bridge 正常、physics 空、nav 回退 abstract")

# ═══════════════════════════════════════════════════════════════════
# 10. restart 复位
# ═══════════════════════════════════════════════════════════════════

func _test_restart() -> void:
	OS.set_environment("V17_PHYSICS", "shadow")
	_section_begin("10 restart 复位")
	var br = _make_bridge()
	var st = _make_state(br)
	br.sync(120.0)
	st.fw_sync(0.0)
	_ok(float(st.fw_physics.get("t", 0.0)) > 0.0, "restart 前 physics t>0")
	st.fw_restart()
	_eq(st.fw_physics_ready, true, "restart 后 physics 仍 ready")
	_near(float(st.fw_physics.get("t", -1.0)), 0.0, 1.0e-9, "restart 后 physics t=0")
	_ok((st.fw_physics.get("entities", []) as Array).size() >= 9, "restart 后实体重载")
	# provider 重启后仍绑定
	var l1_nav: Array = br.nav.resolve_positions().get("l1", [])
	_near(_vec_len(l1_nav), 326381.0, 5.0, "restart 后 nav provider 仍为 physics 位置")
	_data_line("restart", "physics t=0、实体重载、nav provider 重新绑定")

# ═══════════════════════════════════════════════════════════════════
# 11. 长程稳定性
# ═══════════════════════════════════════════════════════════════════

func _test_long_run() -> void:
	_section_begin("11 长程")
	var br = _make_bridge()
	br.sync(3600.0)
	var view: Dictionary = br.physics_view()
	_near(float(view.get("t", 0.0)), 3600.0, 1.0e-9, "sync(3600) 后 t=3600")
	var finite := true
	for raw in (view.get("entities", []) as Array):
		if not bool((raw as Dictionary).get("finite", false)):
			finite = false
	_ok(finite, "长程后所有实体 finite")
	var summary: Dictionary = br.physics_summary()
	_ok(float(summary.get("max_jacobi_drift", 1.0)) < 1.0e-3, "长程 Jacobi 漂移 <1e-3",
		"%.8f" % float(summary.get("max_jacobi_drift", 0.0)))
	var fatal := false
	for raw in (view.get("warnings", []) as Array):
		var w := String(raw)
		if w.contains("发散") or w.contains("失败"):
			fatal = true
	_ok(not fatal, "长程无发散/失败 warning")
	_data_line("long-run", "3600s 后 finite、max_jacobi_drift=%.8f" % [
		float(summary.get("max_jacobi_drift", 0.0))])
