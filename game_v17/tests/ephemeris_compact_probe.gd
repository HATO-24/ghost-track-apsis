extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# COMPACT EPHEMERIS PROBE · 完整游戏-阶段2D
#
# 验证：无表 analytic fallback、非法表拒绝、合法 Chebyshev/Kepler 插值、
# 时间窗、单位/frame、JSON、确定性；不伪造 JPL 数据（夹具 source=TEST_FIXTURE）。
# 只跑一次；只读；不接 UI/物理。
#
# 运行：
#   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
#       --path .\game_v17 --script res://tests/ephemeris_compact_probe.gd
# 期望末行 EPHEMERIS COMPACT PROBE OK，退出码 0。
# ═══════════════════════════════════════════════════════════════════

const Ephemeris := preload("res://framework/sim/ephemeris_compact.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("EPHEMERIS COMPACT PROBE · 完整游戏-阶段2D")
	print("════════════════════════════════════════════════════════════════")
	_test_no_table()
	_test_invalid_tables()
	_test_chebyshev_table()
	_test_kepler_and_window()
	_test_file_load_json_determinism()
	print("────────────────────────────────────────────────────────────────")
	print("EPHEMERIS COMPACT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("EPHEMERIS COMPACT PROBE FAILED")
		quit(1)
	else:
		print("EPHEMERIS COMPACT PROBE OK")
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


func _near(a: float, b: float, tol := 1.0e-6) -> bool:
	return absf(a - b) <= tol


func _arr_near(a: Variant, b: Array, tol := 1.0e-6) -> bool:
	if not (a is Array) or (a as Array).size() < 3:
		return false
	var aa: Array = a
	for i in range(3):
		if not _near(float(aa[i]), float(b[i]), tol):
			return false
	return true


func _table() -> Dictionary:
	# 测试夹具：线性位置 (10+0.2t, 20+0.3t, 30-0.1t)，Chebyshev degree 1。
	# 这不是 JPL 数据；source.provider=TEST_FIXTURE。
	return {
		"schema": "v17_compact_ephemeris.v1",
		"source": {
			"provider": "TEST_FIXTURE", "derived_from": "probe linear synthetic",
			"license": "test-only", "generated_at": "probe",
		},
		"version": "test-1",
		"frame": "earth_eci",
		"units": {"length": "km", "time": "s", "velocity": "km/s", "angle": "rad"},
		"time_scale": "TDB",
		"time_window": {"start_s": 0.0, "end_s": 100.0},
		"bodies": {
			"moon": {
				"body_id": "301", "center": "earth",
				"interpolation": "chebyshev", "max_error_km": 0.0,
				"segments": [{
					"t0": 0.0, "t1": 100.0, "order": 2,
					"coeffs": {"x": [20.0, 10.0], "y": [35.0, 15.0], "z": [25.0, -5.0]},
				}],
			},
		},
	}


func _kepler_table() -> Dictionary:
	var t := _table()
	var bodies := (t["bodies"] as Dictionary).duplicate(true)
	bodies["test_kepler"] = {
		"body_id": "999", "center": "earth", "interpolation": "kepler",
		"max_error_km": 1.0,
		"kepler": {"a": 7000.0, "e": 0.01, "i": 0.5, "raan": 0.3, "argp": 0.2,
			"M0": 0.0, "n": 0.001, "epoch_s": 0.0,
			"mu_km3_s2": 398600.4418},
	}
	t["bodies"] = bodies
	return t


# ── 1. 无表 analytic fallback ───────────────────────────────────

func _test_no_table() -> void:
	print("")
	print("── 1. 无表 → available=false / analytic earth-moon ──")
	var e = Ephemeris.new()
	_ok(bool(e.ready), "初始化 ready")
	_ok(not bool(e.available_flag), "available=false")
	_ok(bool(e.using_analytic), "using_analytic=true")
	_ok((e.errors as Array).is_empty(), "无表不是错误（errors 空）")
	_ok((e.warnings as Array).size() > 0, "无表 warning")
	_ok(e.bodies().size() == 2, "bodies=earth/moon")
	var ids: Array = []
	for raw in e.bodies():
		ids.append(String((raw as Dictionary).get("id", "")))
	_ok(ids.has("earth") and ids.has("moon"), "earth/moon fallback")
	var es: Dictionary = e.body_state("earth", 0.0)
	_ok(bool(es.get("ok", false)), "earth fallback ok")
	_ok(_arr_near(es.get("position_km", []), [0.0, 0.0, 0.0]), "earth 位置原点")
	_ok(_arr_near(es.get("velocity_kmps", []), [0.0, 0.0, 0.0]), "earth 速度 0")
	_ok(bool(es.get("analytic_fallback", false)), "earth analytic_fallback 标记")
	_ok(not bool(es.get("available", true)), "earth available=false")
	_eq(String(es.get("frame", "")), "earth_eci", "earth frame")
	var ms: Dictionary = e.body_state("moon", 0.0)
	_ok(bool(ms.get("ok", false)), "moon fallback ok")
	_ok(float(ms.get("speed_kmps", 0.0)) > 0.5, "moon 有速度", str(ms.get("speed_kmps")))
	_ok(bool(ms.get("analytic_fallback", false)), "moon analytic_fallback 标记")
	var ms2: Dictionary = e.body_state("301", 1000.0)
	_ok(bool(ms2.get("ok", false)), "moon 别名 301")
	_eq(String(ms2.get("body", "")), "moon", "别名归一 moon")
	var bad: Dictionary = e.body_state("jupiter", 0.0)
	_ok(not bool(bad.get("ok", true)), "未知 body false")
	_eq(String(bad.get("reason", "")), "unknown_body", "未知 body reason")
	var bad_t: Dictionary = e.body_state("moon", NAN)
	_ok(not bool(bad_t.get("ok", true)), "非有限 t false")
	_ok(_json_ok(e.to_dict()), "fallback to_dict JSON")
	_ok(_json_ok(e.summary()), "fallback summary JSON")
	_ok(((e.to_dict().get("writes", {}) as Dictionary).get("v15", true)) == false,
		"fallback 不写 V15")
	# 不存在的路径
	var e2 = Ephemeris.new()
	_ok(not bool(e2.load("res://no/such/ephemeris")), "不存在路径 load false")
	_ok(bool(e2.using_analytic), "不存在路径 analytic fallback")
	_ok((e2.warnings as Array).size() > 0, "不存在路径 warning")


# ── 2. 非法表拒绝 ───────────────────────────────────────────────

func _test_invalid_tables() -> void:
	print("")
	print("── 2. 非法表拒绝（schema/source/frame/units/window/bodies/interp）──")
	var cases := {
		"坏 schema": func(t): t["schema"] = "bad.schema",
		"缺 source": func(t): t["source"] = {},
		"缺 version": func(t): t["version"] = "",
		"坏 frame": func(t): t["frame"] = "mars_fixed",
		"坏 units": func(t): t["units"] = {"length": "m", "time": "s", "velocity": "km/s"},
		"坏 time_window": func(t): t["time_window"] = {"start_s": 10.0, "end_s": 5.0},
		"空 bodies": func(t): t["bodies"] = {},
		"坏 interpolation": func(t): (t["bodies"]["moon"] as Dictionary)["interpolation"] = "spice",
		"cheb 缺 coeffs": func(t): (t["bodies"]["moon"] as Dictionary)["segments"][0].erase("coeffs"),
		"cheb coeffs 过短": func(t): (t["bodies"]["moon"] as Dictionary)["segments"][0]["coeffs"]["x"] = [1.0],
		"kepler 坏 e": func(t): (t["bodies"]["moon"] as Dictionary)["interpolation"] = "kepler",
	}
	for label in cases.keys():
		var tbl := _table()
		(cases[label] as Callable).call(tbl)
		var e = Ephemeris.new()
		_ok(not bool(e.load_data(tbl, "bad-" + String(label))), "拒绝表: " + String(label))
		_ok((e.errors as Array).size() > 0, "错误记录: " + String(label))
		_ok(not bool(e.available_flag), "available=false: " + String(label))
		_ok(bool(e.using_analytic), "回退 analytic: " + String(label))
		_ok(bool(e.body_state("moon", 0.0).get("ok", false)), "回退仍可查询: " + String(label))
	# validate_table 直接返回
	var vr: Dictionary = Ephemeris.new().validate_table({"schema": "x"})
	_ok(not bool(vr.get("ok", true)), "validate_table 非法 false")
	_ok((vr.get("errors", []) as Array).size() > 0, "validate_table 错误列表")
	var vgood: Dictionary = Ephemeris.new().validate_table(_table())
	_ok(bool(vgood.get("ok", false)), "validate_table 合法 true", str(vgood.get("errors", [])))
	# 不允许把测试夹具冒充 JPL：source 必填，表内 provider 原样记录
	var fake_jpl := _table()
	(fake_jpl["source"] as Dictionary)["provider"] = "JPL"
	(fake_jpl["source"] as Dictionary).erase("derived_from")
	var e2 = Ephemeris.new()
	_ok(not bool(e2.load_data(fake_jpl, "fake-jpl-missing-derived")), "缺 derived_from 的 JPL 表拒绝")


# ── 3. 合法 Chebyshev 表 ───────────────────────────────────────

func _test_chebyshev_table() -> void:
	print("")
	print("── 3. 合法 Chebyshev 表 / 插值 / 时间窗 ──")
	var e = Ephemeris.new()
	_ok(bool(e.load_data(_table(), "test-fixture")), "load_data 合法 true", str(e.errors))
	_ok(bool(e.available_flag), "available=true")
	_ok(not bool(e.using_analytic), "using_analytic=false")
	_eq(String(e.version), "test-1", "version")
	_eq(String(e.frame), "earth_eci", "frame")
	_ok(String((e.source as Dictionary).get("provider", "")) == "TEST_FIXTURE", "source 记录 TEST_FIXTURE")
	_ok((e.bodies() as Array).size() == 1, "1 body")
	_ok(bool(e.body_state("moon", 50.0).get("ok", false)), "body_state moon 50")
	var s: Dictionary = e.body_state("moon", 50.0)
	_ok(_arr_near(s.get("position_km", []), [20.0, 35.0, 25.0]), "Chebyshev t=50 位置")
	_ok(_arr_near(s.get("velocity_kmps", []), [0.2, 0.3, -0.1]), "Chebyshev t=50 速度(导数)")
	_ok(_near(float(s.get("speed_kmps", 0.0)), sqrt(0.14), 1.0e-6), "speed")
	_ok(not bool(s.get("analytic_fallback", true)), "table 非 analytic")
	_ok(bool(s.get("available", false)), "table available")
	var s0: Dictionary = e.body_state("moon", 0.0)
	_ok(_arr_near(s0.get("position_km", []), [10.0, 20.0, 30.0]), "Chebyshev t=0 位置")
	var s100: Dictionary = e.body_state("301", 100.0)
	_ok(_arr_near(s100.get("position_km", []), [30.0, 50.0, 20.0]), "Chebyshev t=100 位置（别名）")
	var oor: Dictionary = e.body_state("moon", 101.0)
	_ok(not bool(oor.get("ok", true)), "时间窗上界外 false")
	_eq(String(oor.get("reason", "")), "out_of_time_window", "时间窗外 reason")
	var oor2: Dictionary = e.body_state("moon", -1.0)
	_ok(not bool(oor2.get("ok", true)), "时间窗下界外 false")
	var ub: Dictionary = e.body_state("earth", 50.0)
	_ok(not bool(ub.get("ok", true)), "表中无 earth → unknown_body")
	_eq(String(ub.get("reason", "")), "unknown_body", "unknown body reason")
	_ok(_json_ok(s), "body_state JSON")
	_ok(_json_ok(e.to_dict()), "table to_dict JSON")
	_ok(((e.to_dict().get("writes", {}) as Dictionary).get("v15", true)) == false, "table 不写 V15")
	# 两次加载/查询确定性
	var e2 = Ephemeris.new()
	e2.load_data(_table(), "test-fixture")
	_ok(JSON.stringify(e.body_state("moon", 37.5)) == JSON.stringify(e2.body_state("moon", 37.5)),
		"Chebyshev 确定性")


# ── 4. Kepler / 单位 / frame ───────────────────────────────────

func _test_kepler_and_window() -> void:
	print("")
	print("── 4. Kepler 采样 / units / frame / 时间窗 ──")
	var e = Ephemeris.new()
	_ok(bool(e.load_data(_kepler_table(), "test-kepler")), "Kepler 表合法", str(e.errors))
	_ok((e.bodies() as Array).size() == 2, "2 bodies")
	var k: Dictionary = e.body_state("test_kepler", 100.0)
	_ok(bool(k.get("ok", false)), "Kepler body_state ok")
	var p: Array = k.get("position_km", []) as Array
	var rad := sqrt(float(p[0]) * float(p[0]) + float(p[1]) * float(p[1]) + float(p[2]) * float(p[2]))
	_ok(rad >= 7000.0 * (1.0 - 0.01) - 1.0 and rad <= 7000.0 * (1.0 + 0.01) + 1.0,
		"Kepler 半径在 a(1±e) 内", str(rad))
	_ok(float(k.get("speed_kmps", 0.0)) > 0.0, "Kepler 速度 >0")
	_eq(String(k.get("interpolation", "")), "kepler", "interpolation=kepler")
	_ok(_json_ok(k), "Kepler state JSON")
	var e2 = Ephemeris.new()
	e2.load_data(_kepler_table(), "test-kepler")
	_ok(JSON.stringify(e.body_state("test_kepler", 250.0)) == JSON.stringify(e2.body_state("test_kepler", 250.0)),
		"Kepler 确定性")
	# 单位/frame 校验
	var bad_u := _table()
	bad_u["units"] = {"length": "km", "time": "ms", "velocity": "km/s"}
	_ok(not bool(Ephemeris.new().load_data(bad_u)), "坏 units.time 拒绝")
	var bad_f := _table()
	bad_f["frame"] = "l1_rotating"
	_ok(not bool(Ephemeris.new().load_data(bad_f)), "坏 frame 拒绝")
	var bad_w := _table()
	bad_w["time_window"] = {"start_s": 100.0, "end_s": 100.0}
	_ok(not bool(Ephemeris.new().load_data(bad_w)), "零宽 time_window 拒绝")


# ── 5. 文件加载 / JSON / 确定性 ───────────────────────────────

func _test_file_load_json_determinism() -> void:
	print("")
	print("── 5. 文件加载 / JSON / 确定性 ──")
	var path := "user://ephemeris_probe_fixture.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	_ok(f != null, "写临时测试表")
	if f != null:
		f.store_string(JSON.stringify(_table(), "  "))
		f.close()
	var e = Ephemeris.new()
	_ok(bool(e.load(path)), "load(file) 合法 true", str(e.errors))
	_ok(bool(e.available_flag), "file available=true")
	_ok(bool(e.body_state("moon", 12.5).get("ok", false)), "file body_state ok")
	_ok(_json_ok(e.to_dict()), "file to_dict JSON")
	# 非法 JSON 文件拒绝
	var badp := "user://ephemeris_probe_bad.json"
	var bf := FileAccess.open(badp, FileAccess.WRITE)
	if bf != null:
		bf.store_string("{not json")
		bf.close()
	var eb = Ephemeris.new()
	_ok(not bool(eb.load(badp)), "非法 JSON 文件拒绝")
	_ok((eb.errors as Array).size() > 0, "非法 JSON errors")
	_ok(bool(eb.using_analytic), "非法文件回退 analytic")
	# 无表默认目录（仓库不含 JPL 表）
	var en = Ephemeris.new()
	_ok(not bool(en.available_flag), "仓库默认无表 available=false")
	_ok(bool(en.using_analytic), "仓库默认 analytic")
	_ok((en.to_dict().get("warnings", []) as Array).size() > 0, "默认 warning")
	_ok(String((en.to_dict().get("source", {}) as Dictionary).get("provider", "")) == "analytic",
		"默认 source=analytic，不冒充 JPL")
	# 确定性：同表同查询 JSON 一致
	var a = Ephemeris.new()
	var b = Ephemeris.new()
	a.load_data(_table())
	b.load_data(_table())
	for tt in [0.0, 25.0, 50.0, 100.0]:
		_ok(JSON.stringify(a.body_state("moon", tt)) == JSON.stringify(b.body_state("moon", tt)),
			"确定性 t=%s" % str(tt))
	_ok(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "to_dict 确定性")
	# 清理临时文件
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(badp):
		DirAccess.remove_absolute(badp)
