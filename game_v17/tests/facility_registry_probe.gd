extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3O 最小 probe：FacilityRegistry（全设施注册表）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/facility_registry_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const FacilityRegistry := preload("res://scripts/core/facility_registry.gd")

const CONTENT := "res://framework/content/facilities_system.json"
const CLUSTERS := ["L1_MERIDIAN", "L2_KARMAN", "L3_ALBORADA", "L4_ANVIL",
	"L5_NEW_LAGOS", "NESOSS", "LUNSYNC"]
const L1_NAMES := {"L1-01": "Greenwich", "L1-03": "Sextant", "L1-05": "Chronos",
	"L1-08": "Astrolabe"}
const L2_NAMES := {"L2-02": "Janus", "L2-04": "Argus", "L2-07": "Horizon",
	"L2-09": "Silent"}
const L3_NAMES := {"L3-01": "Aurora", "L3-04": "Ceres", "L3-06": "Dew",
	"L3-10": "Demeter"}
const L4_NAMES := {"L4-02": "Hammer", "L4-05": "Vulcan", "L4-08": "Crucible",
	"L4-12": "Ingot"}
const L5_NAMES := {"L5-01": "Eko", "L5-03": "Zuma", "L5-07": "Savannah",
	"L5-11": "Victoria"}
const NE_NAMES := {"NESOSS-01": "Polaris", "NESOSS-02": "Arclight",
	"NESOSS-03": "Hyperion", "NESOSS-04": "Vega Prime",
	"NESOSS-05": "Saturnus", "NESOSS-06": "Noah"}

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3O PROBE · FacilityRegistry")
	print("════════════════════════════════════════════════════════════")
	_test_coverage()
	_test_extension()
	_test_schema_unique()
	_test_queries()
	_test_invalid_atomic()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 FACILITY REGISTRY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 FACILITY REGISTRY PROBE FAILED")
		quit(1)
	else:
		print("V17 FACILITY REGISTRY PROBE OK")
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
		"actual=%.9f expected=%.9f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _new_registry() -> Object:
	var r = FacilityRegistry.new()
	_ok(bool(r.ready), "registry ready", str(r.errors))
	return r

func _fac(r, id: String) -> Dictionary:
	return r.facility(id)

func _card(r, id: String) -> Dictionary:
	return r.facility_card(id)

func _bad_from(r) -> Dictionary:
	return (r.to_dict() as Dictionary).duplicate(true)

# ═══════════════════════════════════════════════════════════════════
# 1. 覆盖：cluster / 站数 / 名称
# ═══════════════════════════════════════════════════════════════════

func _test_coverage() -> void:
	_section_begin("1 覆盖/名称")
	var r = _new_registry()
	var expected_clusters: Array = (CLUSTERS + ["LEO", "FAR"])
	expected_clusters.sort()
	_eq(r.cluster_ids(), expected_clusters, "cluster 9 个（7 base+LEO/FAR）")
	_eq(r.count(), 110, "facility total 110")
	_eq((r.facility_ids() as Array).size(), 110, "facility_ids 110")
	_eq(r.base_count(), 29, "base facility 29")
	_eq(r.extension_count(), 81, "extension facility 81")
	var s: Dictionary = r.summary()
	# 旧字段保持 base 语义
	_eq(int(s.get("clusters", 0)), 7, "summary clusters base 7")
	_eq(int(s.get("facilities", 0)), 29, "summary facilities base 29")
	_eq(int(s.get("facility_codes", 0)), 29, "summary facility_codes base 29")
	_eq(int(s.get("transponders", 0)), 29, "summary transponders base 29")
	_eq(int(s.get("ports", 0)), 57, "summary ports base 57")
	# 4B 总计/扩展
	_eq(int(s.get("total_clusters", 0)), 9, "summary total_clusters 9")
	_eq(int(s.get("total_facilities", 0)), 110, "summary total_facilities 110")
	_eq(int(s.get("total_facility_codes", 0)), 110, "summary total_codes 110")
	_eq(int(s.get("total_transponders", 0)), 110, "summary total_txp 110")
	_eq(int(s.get("total_ports", 0)), 138, "summary total_ports 138")
	_eq(int(s.get("extension_facilities", 0)), 81, "summary extension 81")
	_eq(int(s.get("otc_satellites", 0)), 19, "summary OTC 19")
	_eq(int(s.get("fuel_facilities", 0)), 62, "summary fuel 62")
	_eq(int(s.get("orbital_nodes", 0)), 2, "summary orbital nodes 2")
	var per: Dictionary = s.get("per_cluster", {})
	_eq(int(per.get("L1_MERIDIAN", 0)), 4, "L1 4 站")
	_eq(int(per.get("L2_KARMAN", 0)), 4, "L2 4 站")
	_eq(int(per.get("L3_ALBORADA", 0)), 4, "L3 4 站")
	_eq(int(per.get("L4_ANVIL", 0)), 4, "L4 4 站")
	_eq(int(per.get("L5_NEW_LAGOS", 0)), 4, "L5 4 站")
	_eq(int(per.get("NESOSS", 0)), 6, "NESOSS 6 站")
	_eq(int(per.get("LUNSYNC", 0)), 3, "LUNSYNC 3 站")
	# 20 个已知站名
	var maps: Array = [L1_NAMES, L2_NAMES, L3_NAMES, L4_NAMES, L5_NAMES]
	for m in maps:
		for fid in (m as Dictionary).keys():
			var f := _fac(r, str(fid))
			_ok(not f.is_empty(), "facility 存在 " + str(fid))
			_eq(str(f.get("name", "")), str((m as Dictionary)[fid]),
				"站名 " + str(fid))
			_ok(str(f.get("name_en", "")) != "", "name_en " + str(fid))
			_ok(str(f.get("name_zh", "")) != "", "name_zh " + str(fid))
	# NESOSS 6
	for fid2 in NE_NAMES.keys():
		var nf := _fac(r, str(fid2))
		_eq(str(nf.get("name", "")), str(NE_NAMES[fid2]), "NESSOSS 名称 " + str(fid2))
		_eq(str(nf.get("parent_cluster", "")), "NESOSS", "NESSOSS parent " + str(fid2))
	_eq((r.facilities_by_cluster("NESOSS") as Array).size(), 6, "NESSOSS base 6")
	_eq((r.facilities_by_cluster("LUNSYNC") as Array).size(), 3, "LUNSYNC base 3")
	_eq((r.all_facilities_by_cluster("NESOSS") as Array).size(), 21, "NESSOSS all 21")
	_eq((r.all_facilities_by_cluster("LUNSYNC") as Array).size(), 11, "LUNSYNC all 11")
	# LUNSYNC TBD 提案
	for fid3 in ["LUNSYNC-01", "LUNSYNC-02", "LUNSYNC-03"]:
		var lf := _fac(r, str(fid3))
		_ok(not lf.is_empty(), "LUNSYNC 站存在 " + str(fid3))
		_ok(str(lf.get("name", "")).to_upper() == "TBD", "LUNSYNC name TBD " + str(fid3))
		_ok(str(lf.get("name_zh", "")).contains("TBD"), "LUNSYNC 提案标注 TBD " + str(fid3))
		_eq(str(lf.get("side", "")), "unknown", "LUNSYNC side unknown " + str(fid3))
	# 扩展 cluster 元数据
	for cid0 in ["LEO", "FAR"]:
		var node: Dictionary = r.cluster(str(cid0))
		_ok(not node.is_empty(), "orbital cluster 存在 " + str(cid0))
		_ok(str(node.get("name", "")) != "", "orbital cluster name " + str(cid0))
		_ok(str(node.get("kind", "")) != "", "orbital cluster kind " + str(cid0))
		_eq(str(node.get("registry_group", "")), "orbital_node", "orbital group " + str(cid0))
	# cluster 元数据
	for cid in CLUSTERS:
		var c: Dictionary = r.cluster(str(cid))
		_ok(not c.is_empty(), "cluster 存在 " + str(cid))
		_ok(str(c.get("name", "")) != "", "cluster name " + str(cid))
		_ok(str(c.get("name_en", "")) != "", "cluster name_en " + str(cid))
	_ok(str(r.cluster("L1_MERIDIAN").get("name", "")) == "Meridian", "L1=Meridian")
	_ok(str(r.cluster("L2_KARMAN").get("name", "")) == "Karman", "L2=Karman")
	_ok(str(r.cluster("L3_ALBORADA").get("name", "")) == "Alborada", "L3=Alborada")
	_ok(str(r.cluster("L4_ANVIL").get("name", "")) == "Anvil", "L4=Anvil")
	_ok(str(r.cluster("L5_NEW_LAGOS").get("name", "")) == "New Lagos", "L5=New Lagos")
	_data_line("coverage", "base 7 cluster/29 facility/57 ports · total 9/110/138 · OTC19+fuel62+orbital2")

# ═══════════════════════════════════════════════════════════════════
# 1b. 4B 扩展：OTC 19 / TNK+FUL 62 / LEO/FAR 节点
# ═══════════════════════════════════════════════════════════════════

func _test_extension() -> void:
	_section_begin("1b 扩展/OTC/燃料/节点")
	var r = _new_registry()
	_eq(r.otc_count(), 19, "OTC 19")
	_eq(r.fuel_count(), 62, "fuel 62")
	_eq(r.orbital_node_count(), 2, "orbital nodes 2")
	_eq(r.extension_count(), 81, "extension 81")
	# OTC 查询
	var otc_ids: Array = r.otc_satellite_ids()
	_eq(otc_ids.size(), 19, "OTC ids 19")
	var otc_parents: Dictionary = {}
	for oid in otc_ids:
		var sid := str(oid)
		_ok(sid.begins_with("OTC-"), "OTC id 前缀 " + sid)
		var f: Dictionary = _fac(r, sid)
		_ok(not f.is_empty(), "OTC facility " + sid)
		_eq(str(f.get("facility_class", "")), "otc", "OTC class " + sid)
		_eq(str(f.get("registry_group", "")), "otc_satellite", "OTC group " + sid)
		_ok(str(f.get("facility_code", "")).begins_with("FC-OTC-"), "OTC code " + sid)
		_ok(str(f.get("transponder_code", "")).begins_with("TXP-OTC-"), "OTC txp " + sid)
		_ok(f.get("physical") is Dictionary, "OTC physical " + sid)
		_ok((f.get("ports", []) as Array).size() >= 1, "OTC ports " + sid)
		otc_parents[str(f.get("parent_cluster", ""))] = true
		# by code / txp / card
		_eq(str(r.by_code(str(f.get("facility_code", ""))).get("facility_id", "")), sid,
			"OTC by_code " + sid)
		_eq(str(r.by_transponder_code(str(f.get("transponder_code", ""))).get("facility_id", "")),
			sid, "OTC by_txp " + sid)
		var card: Dictionary = _card(r, sid)
		_eq(str(card.get("registry_group", "")), "otc_satellite", "OTC card group " + sid)
	_eq(otc_parents.size(), 9, "OTC parent clusters 9")
	# fuel 查询：TNK/FUL 各 31
	var fuel_ids: Array = r.fuel_facility_ids()
	_eq(fuel_ids.size(), 62, "fuel ids 62")
	var tnk := 0
	var ful := 0
	for fid in fuel_ids:
		var sid2 := str(fid)
		var f2: Dictionary = _fac(r, sid2)
		_ok(not f2.is_empty(), "fuel facility " + sid2)
		var cls := str(f2.get("facility_class", ""))
		if cls == "tank":
			tnk += 1
		elif cls == "fuel":
			ful += 1
		_ok(cls in ["tank", "fuel"], "fuel class " + sid2)
		_eq(str(f2.get("registry_group", "")), "fuel_facility", "fuel group " + sid2)
		_ok(str(f2.get("facility_id", "")).begins_with("TNK-")
			or str(f2.get("facility_id", "")).begins_with("FUL-"), "fuel id 前缀 " + sid2)
		_ok(f2.get("physical") is Dictionary, "fuel physical " + sid2)
		_ok((f2.get("ports", []) as Array).size() >= 1, "fuel ports " + sid2)
		_eq(str(r.by_code(str(f2.get("facility_code", ""))).get("facility_id", "")), sid2,
			"fuel by_code " + sid2)
	_eq(tnk, 31, "TNK 31")
	_eq(ful, 31, "FUL 31")
	# 轨道节点 LEO/FAR
	for cid in ["LEO", "FAR"]:
		var node: Dictionary = r.orbital_node(str(cid))
		_ok(not node.is_empty(), "orbital_node " + str(cid))
		_eq(str(node.get("cluster_id", "")), str(cid), "orbital id " + str(cid))
		_eq(str(r.cluster(str(cid)).get("registry_group", "")), "orbital_node",
			"cluster group " + str(cid))
		_ok((r.facilities_by_cluster(str(cid)) as Array).size() >= 1,
			"cluster " + str(cid) + " 可查")
	_eq((r.facilities_by_cluster("LEO") as Array).size(), 5, "LEO 5 设施")
	_eq((r.facilities_by_cluster("FAR") as Array).size(), 4, "FAR 4 设施")
	_eq((r.extension_facilities_for_cluster("LEO") as Array).size(), 5,
		"LEO extension 5")
	# 旧 29 回归
	_eq(r.base_facility_ids().size(), 29, "base ids 29")
	for old in ["L1-01", "L1-05", "L2-02", "L3-04", "L4-02", "L5-01",
			"NESOSS-01", "LUNSYNC-01"]:
		_ok(not _fac(r, str(old)).is_empty(), "旧设施回归 " + str(old))
	_eq(str(_fac(r, "L1-05").get("name", "")), "Chronos", "旧设施 L1-05 Chronos")
	_eq((r.ports_for("L1-05") as Array).size(), 2, "旧设施端口 2")
	# entity_ids 扩展支持
	var content: Dictionary = r.to_dict()
	var otc0: Dictionary = (content["otc_satellites"] as Array)[0]
	otc0["entity_ids"] = ["otc_entity_probe"]
	var r2 = FacilityRegistry.new()
	_ok(bool(r2.load_data(content)), "扩展 entity_ids 加载")
	_eq(str(r2.facility_for_entity("otc_entity_probe").get("facility_id", "")),
		str(otc0.get("facility_id", "")), "扩展 entity 绑定")
	var ext_card: Dictionary = r2.facility_card(str(otc0.get("facility_id", "")))
	_eq(str(ext_card.get("registry_group", "")), "otc_satellite", "扩展 entity card")
	# merged 视图
	var md: Dictionary = r.to_merged_dict()
	_eq((md.get("clusters", []) as Array).size(), 9, "merged clusters 9")
	_eq((md.get("facilities", []) as Array).size(), 110, "merged facilities 110")
	_eq(int((md.get("summary", {}) as Dictionary).get("total_facilities", 0)), 110,
		"merged summary 110")
	_data_line("extension", "OTC 19 · TNK31+FUL31=62 · LEO/FAR 节点 · 旧29/57回归 · 扩展 entity_ids · merged")

# ═══════════════════════════════════════════════════════════════════
# 2. schema / 唯一性 / 物理 / 港口
# ═══════════════════════════════════════════════════════════════════

func _test_schema_unique() -> void:
	_section_begin("2 schema/唯一/物理/港口")
	var r = _new_registry()
	var codes: Dictionary = {}
	var txps: Dictionary = {}
	var port_ids: Dictionary = {}
	var parents: Dictionary = {}
	var fids: Array = r.facility_ids()
	for fid in fids:
		var f := _fac(r, str(fid))
		var sid := str(fid)
		_ok(not f.is_empty(), "facility " + sid)
		for k in ["facility_id", "name", "name_en", "facility_code",
				"transponder_code", "transponder_type", "parent_cluster",
				"facility_class", "owner", "side"]:
			_ok(str(f.get(k, "")) != "", "%s.%s 非空" % [sid, k])
		_eq(str(f.get("facility_id", "")), sid, "facility_id " + sid)
		_ok(str(f.get("facility_code", "")).begins_with("FC-"), "facility_code 前缀 " + sid)
		_ok(str(f.get("transponder_code", "")).begins_with("TXP-"),
			"transponder_code 前缀 " + sid)
		codes[str(f.get("facility_code", ""))] = true
		txps[str(f.get("transponder_code", ""))] = true
		parents[str(f.get("parent_cluster", ""))] = true
		_ok(f.get("services") is Array and (f.get("services") as Array).size() > 0,
			"services 非空 " + sid)
		# physical
		var ph: Dictionary = f.get("physical", {})
		_ok(ph.get("orbit") is Dictionary, "physical.orbit " + sid)
		for k2 in ["mass_kg", "radius_km", "cross_section_m2", "period_s"]:
			var x := float(ph.get(k2, 0.0))
			_ok(is_finite(x) and x > 0.0, "physical.%s>0 %s" % [k2, sid])
		_ok(ph.get("station_keeping") is Dictionary, "station_keeping " + sid)
		_ok(str((ph.get("station_keeping", {}) as Dictionary).get("mode", "")) != "",
			"station_keeping.mode " + sid)
		_ok(is_finite(float((ph.get("station_keeping", {}) as Dictionary).get(
			"dv_m_s_year", NAN))), "station_keeping.dv " + sid)
		# ports
		var ports: Array = f.get("ports", [])
		_ok(ports.size() > 0, "ports 非空 " + sid)
		for raw_p in ports:
			_ok(raw_p is Dictionary, "port 对象 " + sid)
			var p: Dictionary = raw_p
			var pid := str(p.get("port_id", ""))
			_ok(pid != "", "port_id 非空 " + sid)
			_ok(not port_ids.has(pid), "port_id 唯一 " + pid)
			port_ids[pid] = true
			_ok(str(p.get("kind", "")) != "", "port kind " + pid)
			_ok(int(p.get("berths", 0)) > 0, "port berths>0 " + pid)
			_ok(float(p.get("max_length_m", 0.0)) > 0.0, "port max_length>0 " + pid)
		if f.has("entity_ids"):
			_ok(f.get("entity_ids") is Array, "entity_ids 数组 " + sid)
	_eq(codes.size(), 110, "facility_code total 110 唯一")
	_eq(txps.size(), 110, "transponder total 110 唯一")
	_eq(port_ids.size(), 138, "port_id total 138 唯一")
	_ok(parents.has("NESOSS") and parents.has("LUNSYNC"), "parent 含 NESOSS/LUNSYNC")
	_ok(parents.has("LEO") and parents.has("FAR"), "parent 含 LEO/FAR")
	# entity 绑定
	var f105 := _fac(r, "L1-05")
	_ok((f105.get("entity_ids", []) as Array).has("l1_station"),
		"L1-05 绑定 l1_station")
	_eq(str(r.facility_for_entity("l1_station").get("facility_id", "")), "L1-05",
		"facility_for_entity l1_station")
	_ok(r.facility_for_entity("no_such").is_empty(), "未知 entity 空")
	# 港口绑定
	_eq((r.ports_for("L1-05") as Array).size(), 2, "L1-05 2 个港口")
	_ok((r.port_ids_for("L1-05") as Array).has("PORT-L1-05-1"), "port_ids_for")
	_ok((r.ports_for("no_such") as Array).is_empty(), "未知 facility ports 空")
	_ok(bool(r.check_contracts().get("ok", false)), "contracts ok")
	_data_line("schema", "required 全过 · code/transponder 110 唯一 · port 138 唯一 · 物理字段 · entity/port 绑定")

# ═══════════════════════════════════════════════════════════════════
# 3. 查询 / transponder / card
# ═══════════════════════════════════════════════════════════════════

func _test_queries() -> void:
	_section_begin("3 查询/transponder/card")
	var r = _new_registry()
	for fid in r.facility_ids():
		var sid := str(fid)
		var by_id: Dictionary = r.facility(sid)
		_eq(str(by_id.get("facility_id", "")), sid, "by id " + sid)
		var code := str(by_id.get("facility_code", ""))
		var by_code: Dictionary = r.by_code(code)
		_eq(str(by_code.get("facility_id", "")), sid, "by code " + sid)
		var txp := str(by_id.get("transponder_code", ""))
		var by_txp: Dictionary = r.by_transponder_code(txp)
		_eq(str(by_txp.get("facility_id", "")), sid, "by transponder " + sid)
		# classify（大小写不敏感）
		var cl: Dictionary = r.classify_transponder(txp.to_lower())
		_eq(bool(cl.get("ok", false)), true, "classify ok " + sid)
		_eq(str(cl.get("facility_id", "")), sid, "classify facility " + sid)
		_ok(str(cl.get("transponder_type", "")) != "", "classify type " + sid)
		# card
		var card: Dictionary = r.facility_card(sid)
		_ok(not card.is_empty(), "card " + sid)
		_eq(str(card.get("schema", "")), "facility_card.v1", "card schema " + sid)
		_ok(card.get("facility") is Dictionary, "card facility " + sid)
		_ok(card.get("cluster") is Dictionary, "card cluster " + sid)
		_ok(card.get("ports") is Array, "card ports " + sid)
		_ok(card.get("physical") is Dictionary, "card physical " + sid)
		_ok((card.get("codes", {}) as Dictionary).has("facility_code"),
			"card codes " + sid)
		_ok((card.get("writes", {}) as Dictionary).get("world", true) == false,
			"card 不写 world " + sid)
	# 未知查询
	_ok(r.facility("NOPE").is_empty(), "未知 facility 空")
	_ok(r.by_code("NOPE").is_empty(), "未知 facility_code 空")
	_ok(r.by_transponder_code("NOPE").is_empty(), "未知 transponder 空")
	_ok(r.facility_card("NOPE").is_empty(), "未知 card 空")
	var c0: Dictionary = r.classify_transponder("")
	_eq(bool(c0.get("ok", true)), false, "空 transponder 拒绝")
	_eq(str(c0.get("reason", "")), "empty_transponder", "empty_transponder reason")
	var c1: Dictionary = r.classify_transponder("NOPE")
	_eq(bool(c1.get("ok", true)), false, "未知 transponder 拒绝")
	_eq(str(c1.get("reason", "")), "unknown_transponder", "unknown_transponder reason")
	_eq(bool(c1.get("matched", true)), false, "unknown matched false")
	# cluster 查询
	var l1: Array = r.facilities_by_cluster("L1_MERIDIAN")
	_eq(l1.size(), 4, "L1 查询 4")
	_eq(str((l1[0] as Dictionary).get("facility_id", "")), "L1-01", "L1 排序")
	var sorted_ids: Array = []
	for raw in l1:
		sorted_ids.append(str((raw as Dictionary).get("facility_id", "")))
	var expected_l1: Array = sorted_ids.duplicate()
	expected_l1.sort()
	_eq(sorted_ids, expected_l1, "cluster 内排序")
	_ok((r.facilities_by_cluster("NOPE") as Array).is_empty(), "未知 cluster 空")
	_eq((r.facilities_by_parent("NESOSS") as Array).size(), 6, "by_parent NESOSS base 6")
	_eq((r.all_facilities_by_cluster("L1_MERIDIAN") as Array).size(), 14,
		"all L1 14")
	_eq((r.all_facilities_by_cluster("NESOSS") as Array).size(), 21,
		"all NESOSS 21")
	_eq((r.facilities_by_cluster("LEO") as Array).size(), 5, "LEO 5")
	_eq((r.facilities_by_cluster("FAR") as Array).size(), 4, "FAR 4")
	_ok(JSON.parse_string(JSON.stringify(r.facility_card("L1-05"))) is Dictionary,
		"card JSON")
	_ok(JSON.parse_string(JSON.stringify(r.facility_card("OTC-L1_MERIDIAN-01"))) is Dictionary,
		"OTC card JSON")
	_data_line("queries", "id/code/transponder(大小写)/card/classify/cluster 排序/base+extension 查询/未知拒绝")

# ═══════════════════════════════════════════════════════════════════
# 4. 非法内容（原子拒绝）
# ═══════════════════════════════════════════════════════════════════

func _test_invalid_atomic() -> void:
	_section_begin("4 非法内容/原子")
	var r = _new_registry()
	var before := JSON.stringify(r.to_dict())
	var ids_before: Array = r.facility_ids()
	# 各类坏数据：都通过 load_data 验证，失败不改旧状态
	var bads: Array = []
	var d1 := _bad_from(r)
	d1["schema"] = "bad"
	bads.append(d1)
	var d2 := _bad_from(r)
	d2["version"] = "9.9.9"
	bads.append(d2)
	var d3 := _bad_from(r)
	d3["facilities"] = []
	bads.append(d3)
	var d4 := _bad_from(r)
	(d4["facilities"] as Array)[0]["facility_id"] = (d4["facilities"] as Array)[1]["facility_id"]
	bads.append(d4)
	var d5 := _bad_from(r)
	(d5["facilities"] as Array)[0]["facility_code"] = (d5["facilities"] as Array)[1]["facility_code"]
	bads.append(d5)
	var d6 := _bad_from(r)
	(d6["facilities"] as Array)[0]["transponder_code"] = (d6["facilities"] as Array)[1]["transponder_code"]
	bads.append(d6)
	var d7 := _bad_from(r)
	(d7["facilities"] as Array)[0]["parent_cluster"] = "NOPE"
	bads.append(d7)
	var d8 := _bad_from(r)
	(d8["facilities"] as Array)[0]["physical"]["mass_kg"] = -1.0
	bads.append(d8)
	var d9 := _bad_from(r)
	(d9["facilities"] as Array)[0]["physical"]["radius_km"] = NAN
	bads.append(d9)
	var d10 := _bad_from(r)
	(d10["facilities"] as Array)[0]["physical"].erase("orbit")
	bads.append(d10)
	var d11 := _bad_from(r)
	(d11["facilities"] as Array)[0]["ports"] = []
	bads.append(d11)
	var d12 := _bad_from(r)
	(d12["facilities"] as Array)[0]["services"] = []
	bads.append(d12)
	var d13 := _bad_from(r)
	(d13["facilities"] as Array)[0]["ports"][0]["berths"] = 0
	bads.append(d13)
	var d14 := _bad_from(r)
	var dup_ports: Array = (d14["facilities"] as Array)[0]["ports"].duplicate(true)
	dup_ports.append(((d14["facilities"] as Array)[1]["ports"] as Array)[0])
	(d14["facilities"] as Array)[0]["ports"] = dup_ports
	bads.append(d14)
	var d15 := _bad_from(r)
	(d15["facilities"] as Array)[0].erase("name")
	bads.append(d15)
	var d16 := _bad_from(r)
	d16["clusters"] = []
	bads.append(d16)
	var d17 := _bad_from(r)
	(d17["otc_satellites"] as Array)[0]["facility_id"] = (d17["facilities"] as Array)[0]["facility_id"]
	bads.append(d17)
	var d18 := _bad_from(r)
	(d18["fuel_facilities"] as Array)[0]["transponder_code"] = "TXP-L1-05"
	bads.append(d18)
	var d19 := _bad_from(r)
	(d19["otc_satellites"] as Array)[0]["ports"][0]["port_id"] = "PORT-L1-05-1"
	bads.append(d19)
	var d20 := _bad_from(r)
	(d20["orbital_nodes"] as Array)[0]["cluster_id"] = "L1_MERIDIAN"
	bads.append(d20)
	var d21 := _bad_from(r)
	d21["otc_satellites"] = "bad"
	bads.append(d21)
	for i in range(bads.size()):
		var brok: bool = r.load_data(bads[i])
		_ok(not brok, "非法内容拒绝 #" + str(i))
	_eq(JSON.stringify(r.to_dict()), before, "非法内容不改注册表")
	_eq(r.facility_ids(), ids_before, "非法内容不改 ids")
	_eq(bool(r.ready), true, "非法内容后仍 ready")
	# 非对象/空
	_ok(not bool(r.load_data("x")), "字符串内容拒绝")
	_ok(not bool(r.load_data([])), "数组内容拒绝")
	_ok(not bool(r.load_data({})), "空对象拒绝")
	# 不存在文件
	var r2 = FacilityRegistry.new({"content_path": "/no/such.json"})
	_ok(not bool(r2.ready), "不存在内容拒绝")
	_eq(bool(r2.check_contracts().get("ok", true)), false, "未 ready contracts false")
	_data_line("invalid", "21 类坏数据（含扩展重复/非法）原子拒绝 · 非对象/不存在文件拒绝 · 旧状态不变")

# ═══════════════════════════════════════════════════════════════════
# 5. JSON / 确定性 / contracts
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("5 JSON/确定性")
	var r = _new_registry()
	var j: String = str(r.to_json())
	_ok(JSON.parse_string(j) is Dictionary, "to_json 可解析")
	var d: Dictionary = r.to_dict()
	_eq(str(d.get("schema", "")), "v17.facilities_system.v1", "to_dict schema")
	_eq(str(d.get("version", "")), "1.0.0", "to_dict version")
	_eq((d.get("clusters", []) as Array).size(), 7, "to_dict base clusters 7")
	_eq((d.get("facilities", []) as Array).size(), 29, "to_dict base facilities 29")
	_eq((d.get("otc_satellites", []) as Array).size(), 19, "to_dict OTC 19")
	_eq((d.get("fuel_facilities", []) as Array).size(), 62, "to_dict fuel 62")
	_eq((d.get("orbital_nodes", []) as Array).size(), 2, "to_dict orbital 2")
	_ok(str(d.get("source", "")) != "", "to_dict source")
	# 往返
	var r2 = _new_registry()
	_ok(bool(r2.load_data(d)), "load_data(to_dict) ok")
	_eq(JSON.stringify(r2.to_dict()), JSON.stringify(d), "to_dict load 往返一致")
	_eq(r2.facility_ids(), r.facility_ids(), "往返 ids 110")
	_eq(r2.count(), 110, "往返 count 110")
	_eq(JSON.stringify(r2.summary()), JSON.stringify(r.summary()), "往返 summary 一致")
	_eq(str(r2.facility("OTC-L1_MERIDIAN-01").get("facility_code", "")),
		"FC-OTC-L1_MERIDIAN-01", "往返 OTC 查询")
	_eq(str(r2.facility("FUL-L1-05").get("facility_code", "")), "FC-FUL-L1-05",
		"往返 FUL 查询")
	_eq(JSON.stringify(r2.facility_card("L1-05")), JSON.stringify(r.facility_card("L1-05")),
		"往返 card")
	# 确定性
	var a = _new_registry()
	var b = _new_registry()
	_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "两次加载一致")
	_eq(a.to_json(), b.to_json(), "to_json 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "contracts ok")
	# 卡片集合确定
	var ca: Array = []
	for fid in a.facility_ids():
		ca.append(JSON.stringify(a.facility_card(str(fid))))
	var cb: Array = []
	for fid2 in b.facility_ids():
		cb.append(JSON.stringify(b.facility_card(str(fid2))))
	_eq(ca, cb, "全部 card 确定")
	# 不写 world/UI 声明
	var s: Dictionary = a.summary()
	_eq(bool((s.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_eq(bool((s.get("writes", {}) as Dictionary).get("ui", true)), false, "不写 UI")
	_data_line("json", "to_dict 基础+扩展 · 往返 ids110/summary/OTC/FUL · 两次加载/card 确定 · contracts")
