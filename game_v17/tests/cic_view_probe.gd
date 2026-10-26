extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4I 最小 probe：CICView（可观测信息层）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/cic_view_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不读 PhysicsWorld truth/不写。
# ═══════════════════════════════════════════════════════════════════

const CICView := preload("res://scripts/core/cic_view.gd")
const TrackTable := preload("res://scripts/core/track_table.gd")
const FacilityRegistry := preload("res://scripts/core/facility_registry.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE4I PROBE · CICView")
	print("════════════════════════════════════════════════════════════")
	_test_setup()
	_test_l1()
	_test_l2_l4()
	_test_metadata_facilities()
	_test_no_truth_readonly()
	_test_track_table_integration()
	_test_determinism_errors()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 CIC VIEW PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 CIC VIEW PROBE FAILED")
		quit(1)
	else:
		print("V17 CIC VIEW PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
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
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _track(id: String, level: int, bearing = 45.0, range = 100.0,
		quality := 0.8, age := 0.0, extra := {}) -> Dictionary:
	var t := {"id": id, "batch": "B-" + id, "level": level,
		"bearing_deg": bearing, "range_km": range, "quality": quality,
		"last_update": 100.0 - float(age), "sources": ["radar", "ir"],
		"identity": "unknown", "threat": "none"}
	for k in (extra as Dictionary).keys():
		t[str(k)] = (extra as Dictionary)[k]
	return t

func _cfg(tracks: Array, extra := {}) -> Dictionary:
	var vm := {"schema": "fused_track_table.v1", "t": 100.0, "tracks": tracks}
	var c := {"track_table_vm": vm,
		"ownship": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0], "heading_deg": 0.0}}
	for k in extra.keys():
		c[k] = extra[k]
	return c

func _svc(cfg: Dictionary) -> Object:
	var c = CICView.new(cfg)
	_ok(bool(c.ready), "CICView ready", str(c.errors))
	return c

func _view(cfg: Dictionary) -> Dictionary:
	var c = _svc(cfg)
	var v: Dictionary = c.build()
	_eq(bool(v.get("ok", true)), true, "build ok", str(v.get("reason", "")))
	return v

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 错误
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 setup/错误")
	var bad1 = CICView.new({})
	_ok(not bool(bad1.ready), "缺 TrackTable 失败")
	var bad2 = CICView.new({"track_table_vm": {"t": 0.0}})
	_ok(not bool(bad2.ready), "缺 tracks 失败")
	var bad3 = CICView.new({"track_table_vm": {"t": 0.0, "tracks": []}})
	_ok(not bool(bad3.ready), "缺 ownship 失败")
	var bad4 = CICView.new({"track_table_vm": {"t": 0.0, "tracks": []},
		"ownship": {"id": "x", "pos_km": [0.0, 0.0]}})
	_ok(not bool(bad4.ready), "ownship 非三维失败")
	var bad5 = CICView.new({"track_table_vm": {"t": 0.0, "tracks": []},
		"ownship": {"id": "x", "pos_km": [0.0, NAN, 0.0]}})
	_ok(not bool(bad5.ready), "ownship 非有限失败")
	var bad6 = CICView.new({"track_table_vm": {"t": 0.0, "tracks": []},
		"ownship": {"id": "x", "pos_km": [0.0, 0.0, 0.0], "heading_deg": "x"}})
	_ok(not bool(bad6.ready), "ownship heading 非法失败")
	# 合法
	var c = _svc(_cfg([]))
	_eq(bool(c.ready), true, "合法 setup")
	var v: Dictionary = c.build()
	_eq(str(v.get("schema", "")), "v17.cic_view.v1", "view schema")
	_eq(bool(v.get("truth", true)), false, "view truth false")
	_eq(bool((v.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"不写 TrackTable")
	_eq(bool((v.get("writes", {}) as Dictionary).get("world", true)), false,
		"不写 world")
	_eq(bool((v.get("writes", {}) as Dictionary).get("ui", true)), false,
		"不写 UI")
	_eq(bool((v.get("writes", {}) as Dictionary).get("physics", true)), false,
		"不读/写 physics")
	var own: Dictionary = v.get("ownship", {})
	_eq(str(own.get("id", "")), "apsis", "ownship id")
	_eq(bool(own.get("known", false)), true, "ownship known")
	_eq(bool(own.get("truth", true)), false, "ownship truth false")
	_eq((own.get("pos_km", []) as Array), [0.0, 0.0, 0.0], "ownship pos")
	_eq((v.get("tracks", []) as Array).size(), 0, "空 tracks")
	_eq((v.get("facilities", []) as Array).size(), 0, "空 facilities")
	_ok(bool(c.check().get("ok", false)), "空 view check ok")
	_data_line("setup", "缺 VM/tracks/ownship/heading 失败 · 合法 view truth=false/writes=false/ownship known")

# ═══════════════════════════════════════════════════════════════════
# 2. L1：无位置，仅 bearing ray/cone
# ═══════════════════════════════════════════════════════════════════

func _test_l1() -> void:
	_section_begin("2 L1 方位线")
	var c = _svc(_cfg([_track("T1", 1, 45.0, 100.0, 0.9, 0.0)]))
	var v: Dictionary = c.build()
	var tr: Dictionary = (v.get("tracks", []) as Array)[0]
	_eq(int(tr.get("level", 0)), 1, "L1 level")
	_eq(str(tr.get("level_name", "")), "L1_BEARING", "L1 name")
	_eq(bool(tr.get("truth", true)), false, "L1 track truth false")
	_ok(not tr.has("estimate_km"), "L1 无 estimate_km")
	_ok(not tr.has("position_km"), "L1 无 position_km")
	_ok(not tr.has("position_source"), "L1 无 position_source")
	_ok(not tr.has("uncertainty_km"), "L1 无 uncertainty_km")
	_eq(tr.get("range_km", 0.0), null, "L1 range 不暴露")
	var ray: Dictionary = tr.get("bearing_ray", {})
	_ok(not ray.is_empty(), "L1 bearing_ray")
	_eq((ray.get("origin_km", []) as Array), [0.0, 0.0, 0.0], "ray origin ownship")
	_near(float(ray.get("bearing_deg", -1.0)), 45.0, 1.0e-6, "ray bearing")
	_ok(float(ray.get("cone_deg", 0.0)) > 0.0, "ray cone")
	_eq(ray.get("truth"), false, "ray truth false")
	_ok(float(tr.get("uncertainty_deg", 0.0)) > 0.0, "L1 uncertainty_deg")
	# 缺 bearing → 无 ray/无位置
	var c2 = _svc(_cfg([_track("T2", 1, -1.0, 100.0)]))
	var tr2: Dictionary = (c2.build().get("tracks", []) as Array)[0]
	_eq(tr2.get("bearing_ray", {}), null, "缺 bearing ray null")
	_eq(tr2.get("reason", ""), "missing_bearing", "缺 bearing reason")
	_ok(not tr2.has("estimate_km"), "缺 bearing 无位置")
	# bearing 归一化
	var c3 = _svc(_cfg([_track("T3", 1, 370.0, 50.0)]))
	var tr3: Dictionary = (c3.build().get("tracks", []) as Array)[0]
	_near(float((tr3.get("bearing_ray", {}) as Dictionary).get("bearing_deg", -1.0)),
		10.0, 1.0e-6, "bearing 370→10")
	# 质量/年龄影响 cone
	var hi = _svc(_cfg([_track("TH", 1, 90.0, 100.0, 1.0, 0.0)]))
	var lo = _svc(_cfg([_track("TL", 1, 90.0, 100.0, 0.1, 40.0)]))
	var ch := float((hi.build().get("tracks", [])[0] as Dictionary).get("uncertainty_deg", 0.0))
	var cl := float((lo.build().get("tracks", [])[0] as Dictionary).get("uncertainty_deg", 0.0))
	_ok(cl > ch, "低质量/老数据 cone 更大", "%f > %f" % [cl, ch])
	_ok(bool(c.check().get("ok", false)), "L1 check ok")
	_data_line("l1", "只有 bearing_ray/cone · range=null · 无 estimate/position · 缺 bearing 不伪造 · cone 随质量/年龄")

# ═══════════════════════════════════════════════════════════════════
# 3. L2/L3/L4 估计位置/身份/证据
# ═══════════════════════════════════════════════════════════════════

func _test_l2_l4() -> void:
	_section_begin("3 L2/L3/L4")
	var tracks := [
		_track("T2", 2, 0.0, 100.0, 0.9, 0.0),
		_track("T2B", 2, 90.0, 50.0, 0.6, 40.0),
		_track("T3", 3, 180.0, 50.0, 0.8, 5.0, {"identity": "neutral",
			"threat": "suspect", "evidence": [{"type": "optical", "evidence_id": "E1"}]}),
		_track("T4", 4, 270.0, 200.0, 0.95, 0.0, {"identity": "hostile",
			"threat": "hostile", "evidence": [{"type": "iff", "evidence_id": "E2"}]}),
		_track("T2MISS", 2, 45.0, null, 0.7, 0.0),
		_track("T2NOB", 2, -1.0, 100.0, 0.7, 0.0)]
	var c = _svc(_cfg(tracks))
	var v: Dictionary = c.build()
	var by_id: Dictionary = {}
	for raw in (v.get("tracks", []) as Array):
		by_id[str((raw as Dictionary).get("id", ""))] = raw
	for lv in [2, 3, 4]:
		for raw2 in (v.get("tracks", []) as Array):
			var tr: Dictionary = raw2
			if str(tr.get("id", "")) in ["T2MISS", "T2NOB"]:
				continue
			if int(tr.get("level", 0)) == lv:
				_ok(tr.get("estimate_km", null) != null, "L%d 有估计 " % lv + str(tr.get("id")))
				_ok(tr.get("position_km", null) != null, "L%d 有 position " % lv + str(tr.get("id")))
				_ok(float(tr.get("uncertainty_km", -1.0)) >= 0.0, "L%d uncertainty " % lv)
				_eq(bool(tr.get("position_truth", true)), false, "L%d position truth false " % lv)
	# 估计几何：T2 bearing0 range100 → own+(0,100)
	var t2: Dictionary = by_id["T2"]
	var t2est: Array = t2.get("estimate_km", []) as Array
	_near(float(t2est[0]), 0.0, 1.0e-6, "T2 x")
	_near(float(t2est[1]), 100.0, 1.0e-6, "T2 y")
	_near(float((t2.get("range_km", 0.0))), 100.0, 1.0e-9, "T2 range")
	# 90° → +X
	var t2b: Dictionary = by_id["T2B"]
	var t2best: Array = t2b.get("estimate_km", []) as Array
	_near(float(t2best[0]), 50.0, 1.0e-6, "T2B x")
	_near(float(t2best[1]), 0.0, 1.0e-6, "T2B y")
	# T3/T4 身份/威胁/证据保留
	_eq(str((by_id["T3"] as Dictionary).get("identity", "")), "neutral", "T3 identity")
	_eq(str((by_id["T3"] as Dictionary).get("threat", "")), "suspect", "T3 threat")
	_eq(((by_id["T3"] as Dictionary).get("evidence", []) as Array).size(), 1, "T3 evidence")
	_eq(str((by_id["T4"] as Dictionary).get("identity", "")), "hostile", "T4 identity")
	_eq(str((by_id["T4"] as Dictionary).get("threat", "")), "hostile", "T4 threat")
	_eq(((by_id["T4"] as Dictionary).get("evidence", []) as Array).size(), 1, "T4 evidence")
	_ok(float((by_id["T4"] as Dictionary).get("quality", 0.0)) >= 0.9, "T4 quality")
	# 缺 range → 无位置；缺 bearing → 无位置
	for badid in ["T2MISS", "T2NOB"]:
		var b: Dictionary = by_id[str(badid)]
		_eq(b.get("estimate_km", "x"), null, str(badid) + " estimate null")
		_eq(b.get("position_km", "x"), null, str(badid) + " position null")
		_ok(str(b.get("reason", "")) in ["missing_range", "missing_bearing"],
			str(badid) + " reason")
	# 质量/年龄影响 uncertainty
	var uT2 := float((by_id["T2"] as Dictionary).get("uncertainty_km", 0.0))
	var uT2B := float((by_id["T2B"] as Dictionary).get("uncertainty_km", 0.0))
	_ok(uT2B > uT2, "低质量/老数据 uncertainty 更大",
		"%f > %f" % [uT2B, uT2])
	# stale（age 40 > 30）
	_ok(bool((by_id["T2B"] as Dictionary).get("stale", false)), "age>30 stale")
	_ok(not bool((by_id["T2"] as Dictionary).get("stale", true)), "age0 非 stale")
	_ok(bool(c.check().get("ok", false)), "L2-L4 check ok")
	_data_line("l2-l4", "L2 估计=own+bearing/range · uncertainty/age/quality · L3/L4 identity/threat/evidence · 缺 range/bearing 不伪造")

# ═══════════════════════════════════════════════════════════════════
# 4. metadata / facilities / ownship
# ═══════════════════════════════════════════════════════════════════

func _test_metadata_facilities() -> void:
	_section_begin("4 metadata/设施/ownship")
	var facilities := [
		{"facility_id": "L1-05", "facility_code": "FC-L1-05", "name": "Chronos",
			"parent_cluster": "L1_MERIDIAN",
			"physical": {"orbit": {"position_km": [10.0, 20.0, 30.0]}}},
		{"facility_id": "L1-01", "facility_code": "FC-L1-01", "name": "Greenwich",
			"parent_cluster": "L1_MERIDIAN", "pos_km": [1.0, 2.0, 3.0]}]
	var metadata := {"T1": {"known": true, "entity_id": "ceres_2",
		"facility_id": "L1-05"}, "T2": {"known": false}}
	var c = _svc(_cfg([_track("T1", 1), _track("T2", 2),
		_track("T3", 3), _track("T4", 4)], {"facilities": facilities,
			"metadata": metadata, "ownship": {"id": "apsis",
				"pos_km": [100.0, 200.0, 300.0]}}))
	var v: Dictionary = c.build()
	var by_id: Dictionary = {}
	for raw in (v.get("tracks", []) as Array):
		by_id[str((raw as Dictionary).get("id", ""))] = raw
	_eq(bool((by_id["T1"] as Dictionary).get("known", false)), true, "T1 known")
	_eq(str((by_id["T1"] as Dictionary).get("entity_id", "")), "ceres_2", "T1 entity")
	_eq(str((by_id["T1"] as Dictionary).get("facility_id", "")), "L1-05", "T1 facility")
	_eq(bool((by_id["T2"] as Dictionary).get("known", true)), false, "T2 unknown")
	_eq(bool((by_id["T3"] as Dictionary).get("known", true)), false, "T3 unknown")
	_eq(str((by_id["T3"] as Dictionary).get("entity_id", "")), "", "T3 无 entity")
	# 设施
	var facs: Array = v.get("facilities", []) as Array
	_eq(facs.size(), 2, "设施 2")
	var fac_by: Dictionary = {}
	for raw2 in facs:
		fac_by[str((raw2 as Dictionary).get("facility_id", ""))] = raw2
	_eq((fac_by["L1-05"].get("pos_km", []) as Array), [10.0, 20.0, 30.0],
		"设施 orbit position")
	_eq(bool((fac_by["L1-05"] as Dictionary).get("known", false)), true, "设施 known")
	_eq(bool((fac_by["L1-05"] as Dictionary).get("truth", true)), false, "设施 truth false")
	_eq((fac_by["L1-01"].get("pos_km", []) as Array), [1.0, 2.0, 3.0], "设施 pos_km")
	_eq(str((fac_by["L1-05"] as Dictionary).get("facility_code", "")), "FC-L1-05",
		"设施 code")
	# ownship override
	_eq((v.get("ownship", {}).get("pos_km", []) as Array), [100.0, 200.0, 300.0],
		"ownship pos")
	# L2 估计平移随 ownship
	var t2: Dictionary = by_id["T2"]
	var t2est2: Array = t2.get("estimate_km", []) as Array
	_near(float(t2est2[0]), 100.0 + 70.71067811865476, 1.0e-4, "ownship 平移 x")
	var sum: Dictionary = c.summary()
	_eq(int(sum.get("known", 0)), 1, "summary known 1")
	_eq(int(sum.get("facilities", 0)), 2, "summary facilities 2")
	_ok(bool(c.check().get("ok", false)), "metadata/设施 check")
	# FacilityRegistry 实际对象
	var reg = FacilityRegistry.new()
	_ok(bool(reg.ready), "registry ready")
	var cr = _svc(_cfg([_track("T1", 1)], {"facility_registry": reg}))
	var vr: Dictionary = cr.build()
	_ok((vr.get("facilities", []) as Array).size() >= 20, "registry 设施载入")
	for rawf in (vr.get("facilities", []) as Array):
		var frow: Dictionary = rawf
		_ok(str(frow.get("facility_id", "")) != "", "registry 设施 id")
		_ok(str(frow.get("facility_code", "")) != "", "registry 设施 code")
		_ok(str(frow.get("cluster_id", "")) != "", "registry 设施 cluster")
		_ok(str(frow.get("name", "")) != "", "registry 设施 name")
		_eq(bool(frow.get("known", false)), true, "registry 设施 known")
		_eq(bool(frow.get("truth", true)), false, "registry 设施 truth false")
		_ok(frow.get("pos_km") is Array and (frow.get("pos_km") as Array).size() == 3,
			"registry 设施 pos 3")
	_data_line("metadata/facilities", "known/entity/facility 映射 · 设施 registry/array · ownship 平移 · summary")

# ═══════════════════════════════════════════════════════════════════
# 5. 不含 truth / 只读
# ═══════════════════════════════════════════════════════════════════

func _test_no_truth_readonly() -> void:
	_section_begin("5 无 truth/只读")
	var truth_tracks := [{
		"id": "TX", "batch": "BX", "level": 2, "bearing_deg": 45.0,
		"range_km": 100.0, "quality": 0.8, "last_update": 100.0,
		"truth": true, "position_km": [1.0, 2.0, 3.0],
		"true_identity": "hostile", "entity_id": "hidden_entity"}]
	var vm_in := {"t": 100.0, "tracks": truth_tracks}
	var cfg := {"track_table_vm": vm_in,
		"ownship": {"id": "own", "pos_km": [0.0, 0.0, 0.0]},
		"metadata": {"TX": {"known": true, "entity_id": "known_entity"}}}
	var before := JSON.stringify(cfg)
	var c = _svc(cfg)
	var v: Dictionary = c.build()
	_eq(JSON.stringify(cfg), before, "输入未被修改")
	_eq(bool(v.get("truth", true)), false, "view 无 truth")
	var raw_json: String = JSON.stringify(v)
	_ok(not raw_json.contains("\"truth\":true"), "JSON 不含 truth:true")
	_ok(not raw_json.contains("\"true_identity\""), "不含 true_identity")
	var tr: Dictionary = (v.get("tracks", []) as Array)[0]
	_eq(bool(tr.get("truth", true)), false, "track truth false")
	_ok(not tr.has("true_identity"), "track 无 true_identity")
	# 输入 track 的 position_km 为 truth，不应被 CIC 直接透传；L2 用 own+bearing/range
	_ok(not tr.get("position_km", []).is_empty(), "L2 position 由估计生成")
	_ok(str(tr.get("entity_id", "")) == "known_entity", "仅 metadata 已知 entity")
	_ok(not raw_json.contains("hidden_entity"), "不暴露 truth entity")
	var w: Dictionary = v.get("writes", {}) as Dictionary
	for k in ["track_table", "world", "ui", "physics", "v15"]:
		_eq(bool(w.get(k, true)), false, "writes.%s false" % k)
	_ok(bool(c.check().get("ok", false)), "check ok")
	_eq((c.tracks() as Array).size(), 1, "tracks API")
	_eq((c.facilities() as Array).size(), 0, "facilities API")
	# 返回副本不可反向改内部
	var copy: Dictionary = c.to_dict()
	(copy["tracks"] as Array)[0]["id"] = "MUT"
	_eq(str((c.to_dict().get("tracks", [])[0] as Dictionary).get("id", "")), "TX",
		"to_dict 副本")
	_data_line("no-truth", "truth:false/writes 全 false · 忽略 truth position/true_identity/hidden entity · 输入只读")

# ═══════════════════════════════════════════════════════════════════
# 6. 实际 TrackTable 集成
# ═══════════════════════════════════════════════════════════════════

func _test_track_table_integration() -> void:
	_section_begin("6 TrackTable 集成")
	var tt = TrackTable.new()
	var writer := str(tt.current_writer())
	var obs1 := {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": "o1", "t": 1.0, "sensor": "radar", "entity_id": "E1",
		"batch": "2001", "support": 1, "quality": 0.8,
		"range_km": 1000.0, "bearing_deg": 45.0}
	var obs2 := {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": "o2", "t": 2.0, "sensor": "ir", "entity_id": "E1",
		"batch": "2001", "support": 2, "quality": 0.7,
		"range_km": 900.0, "bearing_deg": 50.0}
	_eq(bool(tt.handle_observation(obs1, writer).get("ok", false)), true, "TT obs1")
	_eq(bool(tt.handle_observation(obs2, writer).get("ok", false)), true, "TT obs2")
	var vm: Dictionary = tt.vm()
	_eq((vm.get("tracks", []) as Array).size(), 1, "TT 1 track")
	var c = CICView.new({"track_table": tt,
		"ownship": {"id": "own", "pos_km": [0.0, 0.0, 0.0]}})
	_ok(bool(c.ready), "TT CIC ready")
	var v: Dictionary = c.build()
	_eq((v.get("tracks", []) as Array).size(), 1, "CIC TT tracks 1")
	var tr: Dictionary = (v.get("tracks", []) as Array)[0]
	_eq(int(tr.get("level", 0)), 2, "TT 融合 L2")
	# A-01 契约协调：CICView 是玩家视图，真值 batch 不得以玩家字段名暴露；仅保留内部名。
	_ok(not tr.has("batch"), "TT 不得暴露玩家字段 batch")
	_ok(not tr.has("batch_internal"), "TT 不得暴露真值 batch（含内部别名）")
	_ok(tr.get("estimate_km", null) != null, "TT L2 estimate")
	_near(float(tr.get("range_km", 0.0)), 900.0, 1.0e-6, "TT range")
	var est: Array = tr.get("estimate_km", []) as Array
	var dist := sqrt(float(est[0]) * float(est[0]) + float(est[1]) * float(est[1]))
	_near(dist, 900.0, 1.0e-6, "TT estimate range")
	_ok(float(tr.get("uncertainty_km", -1.0)) > 0.0, "TT uncertainty")
	_ok(bool(c.check().get("ok", false)), "TT check")
	# metadata 后处理已知
	var meta := {str(tr.get("id", "")): {"known": true, "entity_id": "ceres_2"}}
	var c2 = CICView.new({"track_table": tt,
		"ownship": {"id": "own", "pos_km": [0.0, 0.0, 0.0]},
		"metadata": meta})
	var tr2: Dictionary = (c2.build().get("tracks", []) as Array)[0]
	_eq(bool(tr2.get("known", false)), true, "TT known metadata")
	_eq(str(tr2.get("entity_id", "")), "ceres_2", "TT entity metadata")
	_data_line("track-table", "实际 TrackTable 两观测 L2 · bearing/range→estimate · metadata known · check")

# ═══════════════════════════════════════════════════════════════════
# 7. 确定性/JSON/连续 build
# ═══════════════════════════════════════════════════════════════════

func _test_determinism_errors() -> void:
	_section_begin("7 确定/JSON")
	var tracks := []
	for i in range(6):
		tracks.append(_track("T%d" % i, (i % 4) + 1, float(i * 30),
			100.0 + i * 10.0, 0.9 - i * 0.1, i * 2.0))
	var cfg := _cfg(tracks, {"facilities": [
		{"facility_id": "F2", "facility_code": "FC-F2", "name": "F2"},
		{"facility_id": "F1", "facility_code": "FC-F1", "name": "F1"}]})
	var a = _svc(cfg)
	var b = _svc(cfg)
	var va: Dictionary = a.build()
	var vb: Dictionary = b.build()
	_eq(JSON.stringify(va), JSON.stringify(vb), "两次 build 一致")
	_eq(a.to_json(), b.to_json(), "to_json 一致")
	_eq(a.build(), va, "重复 build 一致")
	_ok(JSON.parse_string(a.to_json()) is Dictionary, "JSON 可解析")
	_eq((va.get("tracks", []) as Array).size(), 6, "6 tracks")
	_eq((va.get("tracks", [])[0] as Dictionary).get("id", ""), "T0", "track 排序")
	_eq((va.get("facilities", [])[0] as Dictionary).get("facility_id", ""), "F1",
		"设施排序")
	_eq(a.summary(), va.get("summary", {}), "summary 一致")
	_ok(bool(a.check().get("ok", false)), "check ok")
	# build 失败 reason
	var bad = CICView.new({"track_table_vm": {"t": 0.0, "tracks": []},
		"ownship": {"id": "x", "pos_km": [0.0, 0.0, 0.0]}})
	_ok(bool(bad.ready), "空 tracks ready")
	_eq((bad.build().get("tracks", []) as Array).size(), 0, "空 tracks build")
	var bad2 = CICView.new({})
	_eq(str(bad2.build().get("reason", "")), "not_ready", "未 ready build reason")
	# 非法 metadata 不崩溃
	var c3 = CICView.new({"track_table_vm": {"t": 0.0,
		"tracks": [_track("X", 1)]}, "ownship": {"id": "o", "pos_km": [0,0,0]},
		"metadata": {"X": "bad"}})
	_ok(bool(c3.ready), "metadata 非对象 setup 不崩溃")
	_data_line("determinism", "两次 build/to_json 一致 · 排序/重复 build · 空 tracks · not_ready reason")
