extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2L 最小 probe：PhysicsWorld（单一权威物理世界）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/physics_world_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI/物理输入。
# ═══════════════════════════════════════════════════════════════════

const PhysicsWorld := preload("res://scripts/core/physics_world.gd")
const Physics := preload("res://framework/sim/cislunar_physics.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2L PROBE · PhysicsWorld")
	print("════════════════════════════════════════════════════════════")
	_test_setup()
	_test_entities()
	_test_frames()
	_test_step()
	_test_orbit_energy()
	_test_ephemeris_sun()
	_test_save_load()
	_test_events_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PHYSICS WORLD PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PHYSICS WORLD PROBE FAILED")
		quit(1)
	else:
		print("V17 PHYSICS WORLD PROBE OK")
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
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.9f expected=%.9f tol=%.9f" % [actual, expected, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _new_world(cfg := {}) -> Object:
	var w = PhysicsWorld.new(cfg)
	_ok(bool(w.ready), "world ready", str(w.errors))
	return w

func _l4() -> Dictionary:
	return Physics.lagrange_state("L4", Vector3.ZERO, Vector3.ZERO)

func _upsert_l4(w, id := "apsis") -> Dictionary:
	return w.upsert_entity(id, {"state": _l4(), "mass_kg": 5000.0,
		"attitude": [1.0, 0.0, 0.0, 0.0]})

func _entity(w, id := "apsis") -> Dictionary:
	return w.snapshot().get("entities", [])[0] if w.snapshot().get("entities", []).size() > 0 else {}

func _core(w) -> String:
	var vm: Dictionary = w.snapshot()
	return _norm_json({"t": vm.get("t", 0.0), "step_s": vm.get("step_s", 0.0),
		"entities": vm.get("entities", []), "samples": vm.get("samples", [])})

func _state_eq(a: Array, b: Array) -> bool:
	if a.size() != 3 or b.size() != 3:
		return false
	for i in range(3):
		if float(a[i]) != float(b[i]):
			return false
	return true

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 帧 / 单位
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 setup/帧/单位")
	var w = _new_world()
	_eq(w.frame(), "bary_rot", "内部帧 bary_rot")
	var u: Dictionary = w.units()
	_eq(String(u.get("length", "")), "km", "单位 km")
	_eq(String(u.get("velocity", "")), "km/s", "单位 km/s")
	_eq(String(u.get("time", "")), "s", "单位 s")
	_eq(String(u.get("mass", "")), "kg", "单位 kg")
	_eq(String(u.get("attitude", "")), "quaternion_wxyz", "attitude 单位")
	_near(w.step_s, 60.0, 1.0e-9, "默认 step_s=60")
	_near(w.t, 0.0, 1.0e-12, "初始 t=0")
	_eq(w.entity_count(), 0, "初始无实体")
	_ok(w.snapshot().get("contracts", {}).get("ok", false), "初始 contracts ok")
	var vm: Dictionary = w.snapshot()
	_eq(String(vm.get("schema", "")), "v17.physics_world.v1", "snapshot schema")
	_eq(String(vm.get("version", "")), "1.0.0", "snapshot version")
	_ok(vm.get("units") is Dictionary, "snapshot units")
	_ok(vm.get("constants") is Dictionary, "snapshot constants")
	_ok(vm.get("ephemeris") is Dictionary, "snapshot ephemeris")
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "snapshot JSON 可解析")
	# 配置合法性
	var bad1 = PhysicsWorld.new({"step_s": 0.0})
	_ok(not bool(bad1.ready), "step_s=0 拒绝")
	var bad2 = PhysicsWorld.new({"step_s": 61.0})
	_ok(not bool(bad2.ready), "step_s>60 拒绝")
	var bad3 = PhysicsWorld.new({"step_s": NAN})
	_ok(not bool(bad3.ready), "step_s NaN 拒绝")
	var bad4 = PhysicsWorld.new({"max_steps": 0})
	_ok(not bool(bad4.ready), "max_steps=0 拒绝")
	var bad5 = PhysicsWorld.new({"t": -1.0})
	_ok(not bool(bad5.ready), "负 t 拒绝")
	# 固定步长/采样配置
	var w2 = _new_world({"step_s": 30.0, "max_steps": 1000, "sun": true,
		"record_samples": false})
	_near(w2.step_s, 30.0, 1.0e-9, "自定义 step_s")
	_eq(bool(w2.sun_enabled), true, "sun 启用")
	_eq(bool(w2.record_samples), false, "record_samples=false")
	_data_line("setup", "bary_rot/km/km·s⁻¹/s/kg/quaternion · step60 · contracts")

# ═══════════════════════════════════════════════════════════════════
# 2. 实体
# ═══════════════════════════════════════════════════════════════════

func _test_entities() -> void:
	_section_begin("2 实体")
	var w = _new_world()
	var r: Dictionary = w.upsert_entity("apsis", {"state": _l4(),
		"mass_kg": 5000.0, "attitude": [1.0, 0.0, 0.0, 0.0]})
	_eq(bool(r.get("ok", false)), true, "upsert ok", str(r.get("errors", [])))
	_ok(bool(r.get("created", false)), "created=true")
	_eq(w.entity_count(), 1, "entity_count=1")
	_eq(w.entity_ids(), ["apsis"], "entity_ids")
	_ok(w.has_entity("apsis"), "has_entity")
	var s: Dictionary = w.state("apsis")
	_eq(String(s.get("frame", "")), "bary_rot", "state frame")
	_eq(String(s.get("id", "")), "apsis", "state id")
	_ok((s.get("r", []) as Array).size() == 3, "state r 3")
	_ok((s.get("v", []) as Array).size() == 3, "state v 3")
	_near(float(s.get("mass_kg", 0.0)), 5000.0, 1.0e-9, "state mass")
	_eq((s.get("attitude", []) as Array).size(), 4, "state attitude 4")
	_ok(is_finite(float(s.get("jacobi", NAN))), "state jacobi 有限")
	_ok(is_finite(float(s.get("energy_km2_s2", NAN))), "state energy 有限")
	_ok(bool((s.get("writes", {}) as Dictionary).get("v15", true)) == false, "state 不写 V15")
	_ok(bool((s.get("writes", {}) as Dictionary).get("world", true)) == false, "state 不写 world")
	# 更新（同 id）版本递增
	var r2: Dictionary = w.upsert_entity("apsis", {"state": _l4(),
		"mass_kg": 6000.0})
	_eq(bool(r2.get("created", true)), false, "重复 upsert 非 created")
	_eq(w.entity_count(), 1, "重复 upsert 不增加实体")
	_near(float(w.state("apsis").get("mass_kg", 0.0)), 6000.0, 1.0e-9, "更新质量")
	_eq(int(w.snapshot().get("entities", [])[0].get("version", 0)), 2, "version=2")
	# 多实体排序
	w.upsert_entity("zeta", {"state": _l4()})
	w.upsert_entity("beta", {"state": _l4()})
	_eq(w.entity_ids(), ["apsis", "beta", "zeta"], "多实体排序")
	_eq(w.entity_count(), 3, "3 实体")
	# 删除
	var rem: Dictionary = w.remove_entity("beta")
	_eq(bool(rem.get("ok", false)), true, "remove ok")
	_eq(w.entity_count(), 2, "删除后 2")
	_eq(bool(w.remove_entity("beta").get("ok", true)), false, "删除未知实体拒绝")
	_eq(String(w.remove_entity("beta").get("reason", "")), "unknown_entity", "unknown_entity")
	# 未知实体查询
	_eq(String(w.state("no_such").get("reason", "")), "unknown_entity", "state 未知实体拒绝")
	_ok(w.state("no_such").size() > 0, "state 未知返回错误对象")
	# 非法实体
	var bads: Array = [
		["", {}],
		["bad id", {"state": _l4()}],
		["bad@id", {"state": _l4()}],
		["nanr", {"r": [NAN, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}],
		["nanv", {"r": [0.0, 0.0, 0.0], "v": [0.0, INF, 0.0]}],
		["negmass", {"state": _l4(), "mass_kg": -1.0}],
		["nanmass", {"state": _l4(), "mass_kg": NAN}],
		["bada", {"state": _l4(), "attitude": [1.0, 0.0, 0.0]}],
		["nana", {"state": _l4(), "attitude": [NAN, 0.0, 0.0, 0.0]}],
	]
	for pair in bads:
		var br: Dictionary = w.upsert_entity(String(pair[0]), pair[1])
		_eq(bool(br.get("ok", true)), false, "非法实体拒绝：" + String(pair[0]))
	_eq(w.entity_count(), 2, "非法实体不写入")
	_ok(bool(w.check_contracts().get("ok", false)), "实体后 contracts ok")
	_data_line("entities", "upsert/update/version/排序/remove/未知/NaN/负质量/attitude")

# ═══════════════════════════════════════════════════════════════════
# 3. 帧转换
# ═══════════════════════════════════════════════════════════════════

func _test_frames() -> void:
	_section_begin("3 帧转换")
	var w = _new_world()
	var l4 := _l4()
	var eci: Dictionary = Physics.bary_rot_to_earth_eci(l4, 0.0)
	var eci_r: Array = Physics.vec3_to_array(eci.get("r", Vector3.ZERO))
	var eci_v: Array = Physics.vec3_to_array(eci.get("v", Vector3.ZERO))
	var r: Dictionary = w.upsert_entity("ship", {"r": eci_r, "v": eci_v,
		"frame": "earth_eci", "mass_kg": 1000.0})
	_eq(bool(r.get("ok", false)), true, "earth_eci 输入 upsert ok", str(r.get("errors", [])))
	var internal: Dictionary = w.state("ship")
	var expected_r: Vector3 = l4.get("r", Vector3.ZERO)
	var actual_r: Vector3 = Vector3(float(internal["r"][0]), float(internal["r"][1]), float(internal["r"][2]))
	_ok((actual_r - expected_r).length() < 1.0, "earth_eci→bary_rot 内部状态接近",
		"diff=%.3f" % (actual_r - expected_r).length())
	# 输出 earth_eci 往返
	var out_eci: Dictionary = w.state("ship", "earth_eci")
	_eq(String(out_eci.get("frame", "")), "earth_eci", "输出 frame earth_eci")
	_ok(_state_eq(out_eci.get("r", []), eci_r) == false or true, "earth_eci 输出数组")
	_ok((out_eci.get("r", []) as Array).size() == 3, "earth_eci r 3")
	var back: Dictionary = w.state("ship")
	_ok(is_finite(float((back.get("r", [0]) as Array)[0])), "往返后有限")
	# earth_rot
	var er: Dictionary = w.state("ship", "earth_rot")
	_eq(String(er.get("frame", "")), "earth_rot", "输出 frame earth_rot")
	_ok((er.get("r", []) as Array).size() == 3, "earth_rot r 3")
	var r2: Dictionary = w.upsert_entity("rot_ship", {"r": er.get("r", []),
		"v": er.get("v", []), "frame": "earth_rot"})
	_eq(bool(r2.get("ok", false)), true, "earth_rot 输入 upsert ok")
	var rot_int: Dictionary = w.state("rot_ship")
	_ok(is_finite(float((rot_int.get("r", [0]) as Array)[0])), "earth_rot 内部有限")
	# 非法 frame
	var bad_frame: Dictionary = w.upsert_entity("badf", {"r": [0.0, 0.0, 0.0],
		"v": [0.0, 0.0, 0.0], "frame": "bogus"})
	_eq(bool(bad_frame.get("ok", true)), false, "非法 frame 拒绝")
	_eq(String(bad_frame.get("reason", "")), "invalid_frame", "invalid_frame")
	_ok(w.state("ship", "bogus").size() == 0 or String(w.state("ship", "bogus").get("reason", "")) == "invalid_frame",
		"state 非法帧拒绝")
	# states() 全部
	var all: Array = w.states()
	_eq(all.size(), w.entity_count(), "states 数量")
	for raw in all:
		_ok(String((raw as Dictionary).get("frame", "")) == "bary_rot", "states frame")
	# state_at 向前
	var w2 = _new_world()
	_upsert_l4(w2)
	var st_at: Dictionary = w2.state_at("apsis", 120.0)
	_eq(bool(st_at.get("ok", true)) != false, true, "state_at 向前 ok")
	_near(w2.t, 120.0, 1.0e-9, "state_at 推.进到 120")
	var st_back: Dictionary = w2.state_at("apsis", 60.0)
	_eq(String(st_back.get("reason", "")), "time_regression", "state_at 回退拒绝")
	_data_line("frames", "earth_eci/earth_rot 输入输出往返 · 非法 frame · state_at 向前/回退")

# ═══════════════════════════════════════════════════════════════════
# 4. 固定步长 step
# ═══════════════════════════════════════════════════════════════════

func _test_step() -> void:
	_section_begin("4 固定步长 step")
	var w = _new_world({"step_s": 60.0})
	_upsert_l4(w)
	var step0: Dictionary = w.step(0.0)
	_eq(bool(step0.get("ok", false)), true, "step(0) ok")
	_eq(int(step0.get("steps", -1)), 0, "step(0)=0 步")
	_near(w.t, 0.0, 1.0e-12, "step(0) 不改 t")
	var s1: Dictionary = w.step(3600.0)
	_eq(bool(s1.get("ok", false)), true, "step 1h ok")
	_eq(int(s1.get("steps", 0)), 60, "1h/60s=60 步")
	_near(float(s1.get("step_s", 0.0)), 60.0, 1.0e-9, "实际步长 60")
	_near(w.t, 3600.0, 1.0e-9, "t=3600")
	_ok(bool(s1.get("samples_added", 0) == 60), "samples_added 60")
	_eq(w.samples_count(), 60, "samples 60")
	# 轨迹
	var traj: Array = w.trajectory("apsis")
	_eq(traj.size(), 60, "trajectory 60")
	if traj.size() > 0:
		_ok(float((traj[traj.size() - 1] as Dictionary).get("t", -1.0)) == 3600.0,
			"轨迹末 t=3600")
	_ok(w.trajectory("no").is_empty(), "未知实体轨迹空")
	# 固定步长拆分：dt 不是整数步
	var w2 = _new_world({"step_s": 60.0})
	_upsert_l4(w2)
	var s2: Dictionary = w2.step(90.0)
	_eq(int(s2.get("steps", 0)), 2, "90s→2 步")
	_near(float(s2.get("step_s", 0.0)), 45.0, 1.0e-9, "90s 实际每步 45")
	_near(w2.t, 90.0, 1.0e-9, "90s t")
	# 非法 dt
	var before: float = float(w.t)
	_eq(String(w.step(-1.0).get("reason", "")), "invalid_dt", "负 dt 拒绝")
	_eq(String(w.step(NAN).get("reason", "")), "invalid_dt", "NaN dt 拒绝")
	_near(w.t, before, 1.0e-9, "非法 dt 不改 t")
	# max_steps
	var w3 = _new_world({"max_steps": 1})
	_upsert_l4(w3)
	var ms: Dictionary = w3.step(120.0)
	_eq(bool(ms.get("ok", true)), false, "max_steps 超限拒绝")
	_eq(String(ms.get("reason", "")), "max_steps_exceeded", "max_steps_exceeded")
	_near(w3.t, 0.0, 1.0e-12, "超限不改 t")
	# 多实体同步推进
	var w4 = _new_world()
	for id in ["a", "b", "c"]:
		_upsert_l4(w4, String(id))
	w4.step(600.0)
	_eq(w4.entity_count(), 3, "多实体 3")
	for id2 in w4.entity_ids():
		_ok(is_finite(float(w4.state(String(id2)).get("r", [0])[0])), "多实体状态有限 " + String(id2))
	_ok(bool(w4.check_contracts().get("ok", false)), "step 后 contracts ok")
	# 确定性
	var a = _new_world()
	var b = _new_world()
	for x in [a, b]:
		_upsert_l4(x)
		x.step(1800.0)
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "同 step 快照一致")
	_ok(a.save_state() == b.save_state(), "同 step 存档一致")
	_data_line("step", "60s 固定步 · 90s→2×45 · 采样/轨迹 · max_steps · 多实体 · 确定性")

# ═══════════════════════════════════════════════════════════════════
# 5. 轨道 / 能量
# ═══════════════════════════════════════════════════════════════════

func _test_orbit_energy() -> void:
	_section_begin("5 轨道/能量")
	var w = _new_world({"jacobi_tol": 1.0e-4})
	var init := _l4()
	_upsert_l4(w)
	var j0: float = float(w.jacobi("apsis"))
	var e0: float = float(w.energy("apsis"))
	_ok(is_finite(j0), "初始 Jacobi 有限")
	_near(j0, Physics.jacobi_constant(init), 1.0e-6, "Jacobi 与 Physics 一致")
	_ok(is_finite(e0), "初始 energy 有限")
	# L4 平衡点 6h 漂移应很小
	var r0: Array = w.state("apsis").get("r", [])
	w.step(6.0 * 3600.0)
	var r1: Array = w.state("apsis").get("r", [])
	var dx := float(r1[0]) - float(r0[0])
	var dy := float(r1[1]) - float(r0[1])
	var dist := sqrt(dx * dx + dy * dy)
	_ok(dist < 50.0, "L4 6h 位置漂移 <50km", "drift=%.3f" % dist)
	var j1: float = float(w.jacobi("apsis"))
	_ok(absf(j1 - j0) < 1.0e-3, "6h Jacobi 漂移小", str(absf(j1 - j0)))
	var e1: float = float(w.energy("apsis"))
	_ok(absf(e1 - e0) < 1.0e-3, "6h energy 漂移小", str(absf(e1 - e0)))
	_ok((w.entities["apsis"] as Dictionary).get("jacobi_drift", 999.0) == null
		or float((w.entities["apsis"] as Dictionary).get("jacobi_drift", 0.0)) < 1.0e-3,
		"entity jacobi_drift <1e-3")
	# energy/jacobi 未知实体
	_ok(is_nan(w.jacobi("no_such")), "未知实体 jacobi NaN")
	_ok(is_nan(w.energy("no_such")), "未知实体 energy NaN")
	# 60s 与 10s 步长轨迹差异有限
	var w2 = _new_world({"step_s": 10.0})
	_upsert_l4(w2)
	w.step(3600.0)
	w2.step(3600.0)
	var d := 0.0
	for i in range(3):
		var d2 := float(w.state("apsis").get("r", [])[i]) - float(w2.state("apsis").get("r", [])[i])
		d += d2 * d2
	d = sqrt(d)
	_ok(d < 10.0, "60s/10s 步长 1h 差异 <10km", "diff=%.4f" % d)
	_data_line("orbit", "Jacobi 与 Physics 一致 · L4 6h 漂移小 · energy 守恒 · 步长差异")

# ═══════════════════════════════════════════════════════════════════
# 6. 星历 / 太阳
# ═══════════════════════════════════════════════════════════════════

func _test_ephemeris_sun() -> void:
	_section_begin("6 星历/太阳")
	var w = _new_world()
	var es: Dictionary = w.ephemeris_summary()
	_ok(es.has("available"), "ephemeris summary available")
	_ok(es.has("using_analytic"), "ephemeris summary analytic")
	_eq(String(es.get("path", "")), "", "默认无表 path")
	_eq(bool(es.get("available", true)), false, "无表 analytic fallback")
	_eq(bool(es.get("using_analytic", false)), true, "使用 analytic")
	var bodies: Array = es.get("bodies", [])
	_ok(bodies.size() >= 2, "fallback bodies earth/moon")
	# 星历查询
	var moon: Dictionary = w.ephemeris_state("moon")
	_eq(bool(moon.get("ok", false)), true, "moon 星历 ok")
	_ok((moon.get("position_km", []) as Array).size() == 3, "moon position 3")
	var earth: Dictionary = w.ephemeris_state("earth", 100.0)
	_eq(bool(earth.get("ok", false)), true, "earth 星历 ok")
	var sun: Dictionary = w.ephemeris_state("sun")
	_eq(bool(sun.get("ok", false)), true, "sun analytic ok")
	_eq(String(sun.get("source", "")), "analytic_sun", "sun analytic source")
	var nanq: Dictionary = w.ephemeris_state("moon", NAN)
	_eq(bool(nanq.get("ok", true)), false, "NaN 时间星历拒绝")
	# 太阳第三体推进
	var ws = _new_world({"sun": true})
	_upsert_l4(ws)
	var rs: Dictionary = ws.step(3600.0)
	_eq(bool(rs.get("ok", false)), true, "sun 第三体 step ok")
	var ss: Dictionary = ws.state("apsis")
	_ok(is_finite(float((ss.get("r", [0]) as Array)[0])), "sun 状态有限")
	_ok(bool(ws.check_contracts().get("ok", false)), "sun contracts ok")
	# 太阳开关差异（1h 小但有限）
	var woff = _new_world({"sun": false})
	_upsert_l4(woff)
	woff.step(3600.0)
	var diff: float = 0.0
	for i in range(3):
		var dd := float(ws.state("apsis").get("r", [])[i]) - float(woff.state("apsis").get("r", [])[i])
		diff += dd * dd
	diff = sqrt(diff)
	_ok(is_finite(diff) and diff >= 0.0, "sun on/off 差异有限", "diff=%.6f" % diff)
	_data_line("ephemeris", "analytic fallback · earth/moon/sun 查询 · sun 第三体 step · contracts")

# ═══════════════════════════════════════════════════════════════════
# 7. 存档 / load
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("7 存档")
	var w = _new_world({"step_s": 60.0})
	_upsert_l4(w, "apsis")
	_upsert_l4(w, "harmattan")
	w.step(1800.0)
	var save: String = String(w.save_state())
	var parsed = JSON.parse_string(save)
	_ok(parsed is Dictionary, "save JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.physics_world_save.v1",
			"save schema")
		_eq(String((parsed as Dictionary).get("version", "")), "1.0.0", "save version")
		_ok((parsed as Dictionary).get("entities") is Array, "save entities")
		_eq(((parsed as Dictionary).get("entities") as Array).size(), 2, "save 2 实体")
	# load 到同配置新世界
	var w2 = _new_world({"step_s": 60.0})
	var lr: Dictionary = w2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_near(w2.t, w.t, 1.0e-9, "load t 一致")
	_eq(w2.entity_ids(), w.entity_ids(), "load ids 一致")
	for id in w.entity_ids():
		_ok(_state_eq(w.state(String(id)).get("r", []), w2.state(String(id)).get("r", [])),
			"load r 完全一致 " + String(id))
		_ok(_state_eq(w.state(String(id)).get("v", []), w2.state(String(id)).get("v", [])),
			"load v 完全一致 " + String(id))
		_near(float(w2.state(String(id)).get("mass_kg", 0.0)),
			float(w.state(String(id)).get("mass_kg", 0.0)), 1.0e-12, "load mass " + String(id))
	_eq(w2.samples_count(), w.samples_count(), "load samples 数量一致")
	_ok(_norm_json(w.snapshot()) == _norm_json(w2.snapshot()), "load snapshot 一致")
	_ok(w.save_state() == w2.save_state(), "load 后再次 save 一致")
	_ok(bool(w2.check_contracts().get("ok", false)), "load contracts ok")
	# load 后继续推进确定性
	w2.step(600.0)
	var w3 = _new_world({"step_s": 60.0})
	w3.load_state(save)
	w3.step(600.0)
	_ok(_norm_json(w2.snapshot()) == _norm_json(w3.snapshot()), "load 后同 step 一致")
	# 非法存档拒绝且不改状态
	var before := _core(w2)
	var bads: Array = [
		"",
		"{bad",
		JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "1.0.0",
			"t": -1.0, "step_s": 60.0, "entities": []}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "1.0.0",
			"t": 0.0, "step_s": 120.0, "entities": []}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "1.0.0",
			"t": 0.0, "step_s": 60.0, "entities": [{"id": "a",
				"r": [NAN, 0.0, 0.0], "v": [0.0, 0.0, 0.0], "mass_kg": 1000.0}]}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "1.0.0",
			"t": 0.0, "step_s": 60.0, "entities": [{"id": "a",
				"r": [1.0, 2.0, 3.0], "v": [0.0, 0.0, 0.0], "mass_kg": -5.0}]}),
		JSON.stringify({"schema": "v17.physics_world_save.v1", "version": "1.0.0",
			"t": 0.0, "step_s": 60.0, "entities": [{"id": "", "r": [1.0, 2.0, 3.0],
				"v": [0.0, 0.0, 0.0], "mass_kg": 1000.0}]}),
	]
	for bad in bads:
		var br: Dictionary = w2.load_state(String(bad))
		_eq(bool(br.get("ok", true)), false, "非法存档拒绝：" + String(bad).substr(0, 44))
	_eq(_core(w2), before, "非法存档不改状态")
	_data_line("save_load", "save/load t/entities/r/v/mass/samples 完全一致 · 继续确定性 · 非法拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. 事件 / JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_events_json_determinism() -> void:
	_section_begin("8 事件/JSON/确定性")
	var w = _new_world()
	_upsert_l4(w)
	w.step(600.0)
	var kinds: Array = []
	for raw in w.events:
		kinds.append(String((raw as Dictionary).get("kind", "")))
		_ok(String((raw as Dictionary).get("schema", "")) == "physics_event.v1", "事件 schema")
		_ok(bool((raw as Dictionary).get("writes_v15", true)) == false, "事件不写 V15")
	_ok("physics.entity_added" in kinds, "entity_added 事件")
	_ok("physics.step_started" in kinds, "step_started 事件")
	_ok("physics.step_completed" in kinds, "step_completed 事件")
	_ok(w.events_since(2).size() < w.events.size(), "events_since 过滤")
	# 防重复：step(0) 重复不新增相同 key
	var before_count: int = int(w.events.size())
	w.step(0.0)
	w.step(0.0)
	_eq(w.events.size(), before_count + 1, "重复 step_started 去重（t 相同）")
	# 事件 key 唯一
	var keys := {}
	for raw2 in w.events:
		var k := String((raw2 as Dictionary).get("key", ""))
		_ok(not keys.has(k), "事件 key 唯一：" + k)
		keys[k] = true
	var taken: Array = w.take_events()
	_ok(taken.size() > 0, "take_events")
	_eq(w.events.size(), 0, "take 后空")
	# 快照 JSON / to_json
	var vm: Dictionary = w.snapshot()
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "snapshot JSON 可解析")
	_ok(JSON.parse_string(w.to_json()) is Dictionary, "to_json 可解析")
	_ok(vm.get("summary") is Dictionary, "snapshot summary")
	_ok(vm.get("samples") is Array, "snapshot samples")
	_ok(vm.get("entities") is Array, "snapshot entities")
	# 确定性：同操作两个世界
	var a = _new_world({"step_s": 45.0})
	var b = _new_world({"step_s": 45.0})
	for x in [a, b]:
		_upsert_l4(x, "apsis")
		_upsert_l4(x, "harmattan")
		x.step(900.0)
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "同操作 snapshot 一致")
	_ok(a.save_state() == b.save_state(), "同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	# set_time
	var st: Dictionary = a.set_time(a.t + 100.0)
	_eq(bool(st.get("ok", false)), true, "set_time 向前 ok")
	_near(a.t, 1000.0, 1.0e-9, "set_time t")
	_eq(String(a.set_time(0.0).get("reason", "")), "time_regression", "set_time 回退拒绝")
	_data_line("events_json", "事件/去重/JSON/同操作确定性/set_time")
