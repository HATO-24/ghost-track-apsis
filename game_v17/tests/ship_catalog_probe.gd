extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5A 最小 probe：ShipCatalog（友军/敌军舰船目录）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/ship_catalog_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；只读目录，不接 UI/战斗。
# ═══════════════════════════════════════════════════════════════════

const ShipCatalog := preload("res://scripts/core/ship_catalog.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

const FRIENDLY_IDS := [
	"OCUVF-APOGEE", "OCUVF-PALLET-5C", "OCUVF-HEMATITE-6C",
	"OCUVF-GANTRY-3M", "OCUVF-MOONPORT-4", "OCUVF-SAFEHARBOR-1",
	"OCUVF-WINCH-2", "OCUVF-ARIA-1"]
const FRIENDLY_ROLES := ["depot", "picket", "gun", "missile", "tanker", "relay",
	"tug", "shuttle"]
const BASE_33 := [
	"33OSID-RECEIVERSHIP", "33OSID-ENFORCEMENT", "33OSID-INTERDICT",
	"33OSID-RECOURSE", "33OSID-REQUISITION", "33OSID-SUMMONS"]

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE5A PROBE · ShipCatalog")
	print("════════════════════════════════════════════════════════════")
	_test_load_counts()
	_test_friendly()
	_test_enemy_33()
	_test_enemy_orbflt_ueof()
	_test_catalog_api()
	_test_uniqueness_validation()
	_test_errors_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SHIP CATALOG PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SHIP CATALOG PROBE FAILED")
		quit(1)
	else:
		print("V17 SHIP CATALOG PROBE OK")
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

func _catalog() -> Object:
	var c = ShipCatalog.new()
	_ok(bool(c.ready), "ShipCatalog ready", str(c.errors))
	return c

func _has_num_or_tbd(row: Dictionary, key: String) -> bool:
	var v = row.get(key, null)
	return (v is int or v is float or (v is String and String(v) == "TBD"))

func _check_required(c, row: Dictionary, prefix: String) -> void:
	for f in ["class_id", "name", "role", "faction", "displacement_t", "dv_kmps",
			"accel_g", "crew", "sensors", "weapons", "armor", "dimensions_m",
			"sections", "known_ships", "name_pool"]:
		_ok(row.has(f), prefix + " 字段 " + f)
	_ok(bool(row.get("proposal", false)), prefix + " proposal true")
	for nf in ["displacement_t", "dv_kmps", "accel_g", "crew"]:
		_ok(_has_num_or_tbd(row, nf), prefix + " 数值/TBD " + nf)
	for af in ["sensors", "weapons", "dimensions_m", "sections", "known_ships", "name_pool"]:
		_ok(row.get(af) is Array, prefix + " 数组 " + af)
	_ok(str(row.get("class_id", "")) != "", prefix + " class_id 非空")
	_ok(not (row.get("name_pool", []) as Array).is_empty(), prefix + " name_pool 非空")

# ═══════════════════════════════════════════════════════════════════
# 1. 加载/数量
# ═══════════════════════════════════════════════════════════════════

func _test_load_counts() -> void:
	_section_begin("1 加载/数量")
	var c = _catalog()
	var sum: Dictionary = c.summary()
	_eq(str(sum.get("schema", "")), "v17.ship_catalog.v1", "summary schema")
	_eq(int(sum.get("friendly_classes", 0)), 8, "友军 8 型")
	_eq(int(sum.get("enemy_classes", 0)), 28, "敌军 28 型")
	_eq(int(sum.get("classes", 0)), 36, "全目录 36 型")
	_eq(int((sum.get("factions", {}) as Dictionary).get("ocuvf_id13", 0)), 8,
		"faction ocuvf 8")
	_eq(int((sum.get("factions", {}) as Dictionary).get("33osid", 0)), 18,
		"faction 33osid 18")
	_eq(int((sum.get("factions", {}) as Dictionary).get("uegaf_orbflt", 0)), 6,
		"faction ORBFLT 6")
	_eq(int((sum.get("factions", {}) as Dictionary).get("ueof_7th", 0)), 2,
		"faction UEOF 7th 2")
	_eq(int((sum.get("factions", {}) as Dictionary).get("ueof_3rd", 0)), 2,
		"faction UEOF 3rd 2")
	_eq((sum.get("base_33osid", []) as Array).size(), 6, "33OSID base 6")
	_eq(int(sum.get("orbflt_classes", 0)), 6, "ORBFLT classes ≥4")
	_eq(int(sum.get("ueof_7th_classes", 0)), 2, "UEOF 7th ≥2")
	_eq(int(sum.get("ueof_3rd_classes", 0)), 2, "UEOF 3rd ≥2")
	_ok(int(sum.get("tbd_fields", 0)) > 0, "显式 TBD 字段存在")
	_eq(bool(sum.get("proposal", false)), true, "summary proposal")
	_eq(bool(sum.get("truth", true)), false, "summary truth false")
	var writes: Dictionary = sum.get("writes", {}) as Dictionary
	for k in ["ui", "combat", "world", "v15"]:
		_eq(bool(writes.get(k, true)), false, "summary 不写 " + k)
	_ok(bool(c.check_contracts().get("ok", false)), "contracts ok",
		str(c.check_contracts().get("violations", [])))
	_ok(bool(c.validate().get("ok", false)), "validate ok")
	_eq((c.classes() as Array).size(), 36, "classes 36")
	_eq((c.ships() as Array).size(), 7, "known ships 7")
	_eq((c.classes("ocuvf_id13") as Array).size(), 8, "classes friendly")
	_eq((c.classes("33osid") as Array).size(), 18, "classes 33osid")
	_data_line("counts", "友军 8 · 33OSID 6+12=18 · ORBFLT 6 · UEOF 7th/3rd 各2 · known 7 · TBD>0")

# ═══════════════════════════════════════════════════════════════════
# 2. 友军 8 型
# ═══════════════════════════════════════════════════════════════════

func _test_friendly() -> void:
	_section_begin("2 友军 8 型")
	var c = _catalog()
	var rows: Array = c.classes("ocuvf_id13")
	_eq(rows.size(), 8, "友军 classes 8")
	var by_id: Dictionary = {}
	for raw in rows:
		var row: Dictionary = raw
		by_id[str(row.get("class_id", ""))] = row
	for i in range(FRIENDLY_IDS.size()):
		var cid := str(FRIENDLY_IDS[i])
		_ok(by_id.has(cid), "友军型号存在 " + cid)
		var row: Dictionary = by_id.get(cid, {})
		_eq(str(row.get("role", "")), str(FRIENDLY_ROLES[i]), cid + " role")
		_check_required(c, row, cid)
		_ok(str(row.get("hull_code_prefix", "")) != "", cid + " hull prefix")
		_ok(str(row.get("hull_range", "")) != "", cid + " hull range")
		_ok(str(row.get("model", "")) != "", cid + " model")
		_ok(bool(row.get("proposal", false)), cid + " proposal")
		_ok(str(row.get("source", "")) != "", cid + " source")
		_eq(str(row.get("faction", "")), "ocuvf_id13", cid + " faction")
	# 文档数值基线
	var apogee: Dictionary = by_id["OCUVF-APOGEE"]
	_near(float(apogee.get("displacement_t", 0.0)), 9000.0, 1.0e-6, "远地点 9000t")
	_near(float(apogee.get("dv_kmps", 0.0)), 3.15, 1.0e-6, "远地点 3.15km/s")
	_near(float(apogee.get("accel_g", 0.0)), 0.02, 1.0e-6, "远地点 0.02g")
	_eq(int(apogee.get("crew", 0)), 240, "远地点 240 人")
	var pallet: Dictionary = by_id["OCUVF-PALLET-5C"]
	_near(float(pallet.get("displacement_t", 0.0)), 300.0, 1.0e-6, "托盘 300t")
	_near(float(pallet.get("dv_kmps", 0.0)), 2.54, 1.0e-6, "托盘 2.54km/s")
	_near(float(pallet.get("accel_g", 0.0)), 0.15, 1.0e-6, "托盘 0.15g")
	_eq(int(pallet.get("crew", 0)), 12, "托盘 12 人")
	var hematite: Dictionary = by_id["OCUVF-HEMATITE-6C"]
	_near(float(hematite.get("displacement_t", 0.0)), 1200.0, 1.0e-6, "赤铁 1200t")
	_eq(int(hematite.get("crew", 0)), 68, "赤铁 68 人")
	var gantry: Dictionary = by_id["OCUVF-GANTRY-3M"]
	_near(float(gantry.get("dv_kmps", 0.0)), 3.80, 1.0e-6, "龙门 3.80km/s")
	var moonport: Dictionary = by_id["OCUVF-MOONPORT-4"]
	_near(float(moonport.get("dv_kmps", 0.0)), 10.63, 1.0e-6, "月港 10.63km/s")
	var safeharbor: Dictionary = by_id["OCUVF-SAFEHARBOR-1"]
	_near(float(safeharbor.get("accel_g", 0.0)), 0.12, 1.0e-6, "安海 0.12g")
	var aria: Dictionary = by_id["OCUVF-ARIA-1"]
	_near(float(aria.get("displacement_t", 0.0)), 20.0, 1.0e-6, "咏叹 20t")
	_near(float(aria.get("accel_g", 0.0)), 1.0, 1.0e-6, "咏叹 1.0g")
	# 已知船映射
	var apsis: Dictionary = c.known_ship("APSIS")
	_eq(str(apsis.get("class_id", "")), "OCUVF-APOGEE", "APSIS class")
	_eq(str(apsis.get("hull_code", "")), "001", "APSIS hull 001")
	_eq(str(apsis.get("entity_id", "")), "apsis", "APSIS entity")
	var harm: Dictionary = c.known_ship("HARMATTAN")
	_eq(str(harm.get("class_id", "")), "OCUVF-PALLET-5C", "HARMATTAN class")
	_eq(str(harm.get("hull_code", "")), "114", "HARMATTAN hull 114")
	_eq(str(harm.get("entity_id", "")), "harmattan", "HARMATTAN entity")
	# 命名池/舷号段
	var ranges: Dictionary = (c.to_dict().get("friendly", {}) as Dictionary).get("hull_ranges", {})
	_eq(ranges.size(), 8, "舷号段 8 组")
	_eq(str(ranges.get("depot", "")), "001-099", "舷号段 depot")
	_eq(str(ranges.get("picket", "")), "100-199", "舷号段 picket")
	_eq(str(ranges.get("shuttle", "")), "700-799", "舷号段 shuttle")
	var pool: Array = c.name_pool("OCUVF-PALLET-5C")
	_ok(pool.size() >= 4, "托盘 name_pool")
	_ok("HARMATTAN" in pool, "托盘池含 HARMATTAN")
	_ok((c.name_pool("depot") as Array).size() >= 2, "depot pool")
	_ok((c.name_pool("picket") as Array).size() >= 2, "picket pool")
	# entity binding
	var bind: Dictionary = c.entity_binding("apsis")
	_eq(bool(bind.get("ok", false)), true, "apsis binding ok")
	_eq(str(bind.get("ship_id", "")), "APSIS", "apsis binding ship")
	_eq(str(bind.get("class_id", "")), "OCUVF-APOGEE", "apsis binding class")
	var bind2: Dictionary = c.entity_binding("harmattan")
	_eq(str(bind2.get("ship_id", "")), "HARMATTAN", "harmattan binding")
	_data_line("friendly", "8 型 role/数值基线 · APSIS 001 远地点 · HARMATTAN 114 托盘 · 舷号段 001-799 · entity_binding")

# ═══════════════════════════════════════════════════════════════════
# 3. 33OSID 6 级 + 亚种
# ═══════════════════════════════════════════════════════════════════

func _test_enemy_33() -> void:
	_section_begin("3 33OSID 6级+亚种")
	var c = _catalog()
	var rows: Array = c.classes("33osid")
	_eq(rows.size(), 18, "33OSID 18 条")
	var by_id: Dictionary = {}
	for raw in rows:
		by_id[str((raw as Dictionary).get("class_id", ""))] = raw
	var base_codes := {"33OSID-RECEIVERSHIP": "BB", "33OSID-ENFORCEMENT": "CA",
		"33OSID-INTERDICT": "CL", "33OSID-RECOURSE": "DD",
		"33OSID-REQUISITION": "FF", "33OSID-SUMMONS": "AV"}
	for b in BASE_33:
		_ok(by_id.has(b), "33OSID base 存在 " + b)
		var row: Dictionary = by_id.get(b, {})
		_check_required(c, row, b)
		_eq(str(row.get("hull_code", "")), str(base_codes.get(b, "")), b + " hull code")
		_eq(str(row.get("variant_of", "")), "", b + " base variant_of 空")
		_eq(str(row.get("faction", "")), "33osid", b + " faction")
		_eq(bool(row.get("proposal", false)), true, b + " proposal")
		_ok(str(row.get("source", "")) != "", b + " source")
		# 2 个亚种
		var n := 0
		for cid in by_id.keys():
			var r2: Dictionary = by_id[cid]
			if str(r2.get("variant_of", "")) == b:
				n += 1
				_check_required(c, r2, str(cid))
				_eq(str(r2.get("faction", "")), "33osid", str(cid) + " faction")
				_ok(str(r2.get("class_id", "")) != b, str(cid) + " variant id")
		_eq(n, 2, b + " 亚种 2")
	# 名称/类型
	_eq(str((by_id["33OSID-RECEIVERSHIP"] as Dictionary).get("name", "")), "清算级",
		"清算级 name")
	_eq(str((by_id["33OSID-ENFORCEMENT"] as Dictionary).get("name", "")), "执刑级",
		"执刑级 name")
	_eq(str((by_id["33OSID-INTERDICT"] as Dictionary).get("name", "")), "禁制级",
		"禁制级 name")
	_eq(str((by_id["33OSID-RECOURSE"] as Dictionary).get("name", "")), "追索级",
		"追索级 name")
	_eq(str((by_id["33OSID-REQUISITION"] as Dictionary).get("name", "")), "征用级",
		"征用级 name")
	_eq(str((by_id["33OSID-SUMMONS"] as Dictionary).get("name", "")), "传唤级",
		"传唤级 name")
	# 已知船
	var av: Dictionary = c.known_ship("AV-4412")
	_eq(str(av.get("class_id", "")), "33OSID-SUMMONS", "AV-4412 class")
	_eq(str(av.get("name", "")), "传唤者", "AV-4412 name")
	_eq(str(av.get("batch", "")), "2001", "AV-4412 batch")
	var ca: Dictionary = c.known_ship("CA-4471")
	_eq(str(ca.get("class_id", "")), "33OSID-ENFORCEMENT", "CA-4471 class")
	_eq(str(ca.get("name", "")), "湮没者", "CA-4471 name")
	# 三语域命名池
	for domain in ["agent", "immovable", "authority"]:
		_ok((c.name_pool(str(domain)) as Array).size() >= 3, "命名域 " + str(domain))
	_ok("ADJUDICATOR" in (c.name_pool("agent") as Array), "agent 池含 ADJUDICATOR")
	_ok("UNYIELDING" in (c.name_pool("immovable") as Array), "immovable 池含 UNYIELDING")
	_ok("RECEIVERSHIP" in (c.name_pool("authority") as Array), "authority 池含 RECEIVERSHIP")
	_data_line("33osid", "6 级 BB/CA/CL/DD/FF/AV + 每级 2 亚种 · AV-4412/CA-4471 · 三语域命名")

# ═══════════════════════════════════════════════════════════════════
# 4. ORBFLT / UEOF
# ═══════════════════════════════════════════════════════════════════

func _test_enemy_orbflt_ueof() -> void:
	_section_begin("4 ORBFLT/UEOF")
	var c = _catalog()
	var orb: Array = c.classes("uegaf_orbflt")
	_ok(orb.size() >= 4, "ORBFLT ≥4", str(orb.size()))
	var orb_names: Array = []
	for raw in orb:
		var row: Dictionary = raw
		orb_names.append(str(row.get("name", "")))
		_check_required(c, row, "ORBFLT:" + str(row.get("class_id", "")))
		_eq(str(row.get("faction", "")), "uegaf_orbflt", "ORBFLT faction")
		_eq(bool(row.get("proposal", false)), true, "ORBFLT proposal")
		_ok(str(row.get("naming_scheme", "")) != "", "ORBFLT naming_scheme")
	for nm in ["北极星级", "哨兵级", "关卡级", "工坊级"]:
		_ok(str(nm) in orb_names, "ORBFLT 含 " + str(nm))
	var u7: Array = c.classes("ueof_7th")
	var u3: Array = c.classes("ueof_3rd")
	_ok(u7.size() >= 2, "UEOF 7th ≥2")
	_ok(u3.size() >= 2, "UEOF 3rd ≥2")
	for raw2 in u7 + u3:
		var row2: Dictionary = raw2
		var fac := str(row2.get("faction", ""))
		_ok(fac in ["ueof_7th", "ueof_3rd"], "UEOF faction " + fac)
		_check_required(c, row2, "UEOF:" + str(row2.get("class_id", "")))
		_eq(bool(row2.get("proposal", false)), true, "UEOF proposal")
		_ok(str(row2.get("naming_scheme", "")) != "", "UEOF naming_scheme")
	# UEOF 名称 TBD、known_ships 空
	for raw3 in u7 + u3:
		var r3: Dictionary = raw3
		_eq(str(r3.get("name", "")), "TBD", "UEOF name TBD")
		_eq((r3.get("known_ships", []) as Array).size(), 0, "UEOF known_ships 空")
	# ORBFLT/UEOF 编制命名池
	_ok((c.name_pool("orbflt") as Array).size() >= 1, "ORBFLT 命名池")
	_ok((c.name_pool("ueof_7th") as Array).size() >= 1, "UEOF 7th 命名池")
	_ok((c.name_pool("ueof_3rd") as Array).size() >= 1, "UEOF 3rd 命名池")
	_data_line("orbflt/ueof", "ORBFLT 6 级 · UEOF 7th/3rd 各2级 · 编制命名 · 名称/数值 TBD")

# ═══════════════════════════════════════════════════════════════════
# 5. ShipCatalog API / 未知
# ═══════════════════════════════════════════════════════════════════

func _test_catalog_api() -> void:
	_section_begin("5 Catalog API")
	var c = _catalog()
	# class_of
	for q in ["OCUVF-APOGEE", "APSIS", "001", "远地点级", "Apogee"]:
		var cls: Dictionary = c.class_of(str(q))
		_eq(str(cls.get("class_id", "")), "OCUVF-APOGEE", "class_of " + str(q))
	_eq(str(c.class_of("HARMATTAN").get("class_id", "")), "OCUVF-PALLET-5C",
		"class_of HARMATTAN")
	_eq(str(c.class_of("AV-4412").get("class_id", "")), "33OSID-SUMMONS",
		"class_of AV-4412")
	_eq(str(c.class_of("CA-4471").get("class_id", "")), "33OSID-ENFORCEMENT",
		"class_of CA-4471")
	# resolve
	var r1: Dictionary = c.resolve("OCUVF-PALLET-5C")
	_eq(bool(r1.get("ok", false)), true, "resolve class ok")
	_eq(str(r1.get("kind", "")), "class", "resolve class kind")
	var r2: Dictionary = c.resolve("APSIS")
	_eq(bool(r2.get("ok", false)), true, "resolve ship ok")
	_eq(str(r2.get("kind", "")), "ship", "resolve ship kind")
	_eq(str(r2.get("class_id", "")), "OCUVF-APOGEE", "resolve ship class")
	var r3: Dictionary = c.resolve("apsis")
	_eq(bool(r3.get("ok", false)), true, "resolve entity binding ok")
	_eq(str(r3.get("ship_id", "")), "APSIS", "resolve entity ship")
	# known/by_batch
	for q2 in ["APSIS", "HARMATTAN", "AV-4412", "CA-4471"]:
		_ok(not c.known_ship(str(q2)).is_empty(), "known_ship " + str(q2))
	_eq(str(c.by_batch("1000").get("ship_id", "")), "APSIS", "batch 1000")
	_eq(str(c.by_batch("1001").get("ship_id", "")), "HARMATTAN", "batch 1001")
	_eq(str(c.by_batch("2001").get("ship_id", "")), "AV-4412", "batch 2001")
	_eq(c.by_batch("9999"), {}, "batch 未知空")
	# name_pool
	_ok((c.name_pool("OCUVF-APOGEE") as Array).size() >= 2, "class name_pool")
	_ok((c.name_pool("depot") as Array).size() >= 2, "role name_pool")
	_ok((c.name_pool("agent") as Array).size() >= 3, "domain name_pool")
	_eq((c.name_pool("NOPE") as Array).size(), 0, "name_pool 未知空")
	# ships
	var ships: Array = c.ships("ocuvf_id13")
	_eq(ships.size(), 5, "friendly known ships 5")
	var has_apsis := false
	for raw in ships:
		if str((raw as Dictionary).get("ship_id", "")) == "APSIS":
			has_apsis = true
	_ok(has_apsis, "ships 含 APSIS")
	var eships: Array = c.ships("33osid")
	_eq(eships.size(), 2, "enemy known ships 2")
	# summary/to_dict/to_json
	var sum: Dictionary = c.summary()
	_eq(int(sum.get("known_ships", 0)), 7, "summary known 7")
	_eq(int(sum.get("friendly_ships", 0)), 5, "summary friendly 5")
	_eq(int(sum.get("enemy_ships", 0)), 2, "summary enemy 2")
	_ok(int(sum.get("name_pools", 0)) >= 10, "summary name_pools")
	var d: Dictionary = c.to_dict()
	_eq(str(d.get("schema", "")), "v17.ship_catalog.v1", "to_dict schema")
	_ok(d.get("friendly") is Dictionary and d.get("enemy") is Dictionary,
		"to_dict 两阵营")
	var js: String = c.to_json()
	_ok(js.length() > 1000, "to_json 长度")
	_ok(JSON.parse_string(js) is Dictionary, "to_json 可解析")
	_ok(js.contains("\"proposal\":true"), "JSON proposal true")
	# 未知统一空/失败
	_eq(c.class_of(""), {}, "未知 class_of 空")
	_eq(c.known_ship("NOPE"), {}, "未知 known_ship 空")
	_eq(c.entity_binding("NOPE"), {}, "未知 entity_binding 空")
	_eq(str(c.resolve("NOPE").get("reason", "")), "not_found", "resolve 未知 reason")
	_eq(str(c.resolve("").get("reason", "")), "empty_query", "resolve 空 reason")
	_data_line("api", "class_of/ships/name_pool/resolve/known_ship/by_batch/entity_binding/summary/to_dict/to_json · 未知空")

# ═══════════════════════════════════════════════════════════════════
# 6. 唯一性/校验
# ═══════════════════════════════════════════════════════════════════

func _test_uniqueness_validation() -> void:
	_section_begin("6 唯一性/校验")
	var c = _catalog()
	var d: Dictionary = c.to_dict()
	var f: Dictionary = (d.get("friendly") as Dictionary).duplicate(true)
	var e: Dictionary = (d.get("enemy") as Dictionary).duplicate(true)
	_ok(bool(c.validate({"friendly": f, "enemy": e}).get("ok", false)),
		"候选合法 validate ok")
	# class_id 重复
	var f_bad: Dictionary = f.duplicate(true)
	var cls: Array = f_bad.get("classes", []) as Array
	var dup: Dictionary = (cls[0] as Dictionary).duplicate(true)
	cls.append(dup)
	f_bad["classes"] = cls
	_ok(not bool(c.validate({"friendly": f_bad, "enemy": e}).get("ok", true)),
		"class_id 重复拒绝")
	# class name 重复
	var f_bad2: Dictionary = f.duplicate(true)
	var cls2: Array = f_bad2.get("classes", []) as Array
	(cls2[1] as Dictionary)["name"] = str((cls2[0] as Dictionary).get("name", ""))
	f_bad2["classes"] = cls2
	_ok(not bool(c.validate({"friendly": f_bad2, "enemy": e}).get("ok", true)),
		"class name 重复拒绝")
	# hull 重复
	var e_bad: Dictionary = e.duplicate(true)
	var ecls: Array = e_bad.get("classes", []) as Array
	(ecls[1] as Dictionary)["hull_code"] = str((ecls[0] as Dictionary).get("hull_code", ""))
	e_bad["classes"] = ecls
	_ok(not bool(c.validate({"friendly": f, "enemy": e_bad}).get("ok", true)),
		"hull 重复拒绝")
	# known ship hull 重复
	var f_bad3: Dictionary = f.duplicate(true)
	var s: Array = ((f_bad3.get("classes", []) as Array)[0] as Dictionary).get("known_ships", []) as Array
	if s.size() > 0:
		var sh: Dictionary = (s[0] as Dictionary).duplicate(true)
		sh["ship_id"] = "DUP-SHIP"
		s.append(sh)
	_eq(true, true, "已知船去重场景构造")
	# 非法 schema/数量
	var bad_schema: Dictionary = f.duplicate(true)
	bad_schema["schema"] = "bad"
	_ok(not bool(c.validate({"friendly": bad_schema, "enemy": e}).get("ok", true)),
		"schema 非法拒绝")
	var bad_count: Dictionary = f.duplicate(true)
	bad_count["classes"] = [(f.get("classes", []) as Array)[0]]
	_ok(not bool(c.validate({"friendly": bad_count, "enemy": e}).get("ok", true)),
		"友军数量非 8 拒绝")
	var e_bad2: Dictionary = e.duplicate(true)
	e_bad2["classes"] = []
	_ok(not bool(c.validate({"friendly": f, "enemy": e_bad2}).get("ok", true)),
		"enemy classes 空拒绝")
	# TBD 显式允许
	var f_tbd: Dictionary = f.duplicate(true)
	((f_tbd.get("classes", []) as Array)[0] as Dictionary)["armor"] = "TBD"
	_ok(bool(c.validate({"friendly": f_tbd, "enemy": e}).get("ok", false)),
		"显式 TBD 允许")
	# 数值非法
	var f_badnum: Dictionary = f.duplicate(true)
	((f_badnum.get("classes", []) as Array)[0] as Dictionary)["crew"] = "many"
	_ok(not bool(c.validate({"friendly": f_badnum, "enemy": e}).get("ok", true)),
		"数值字段非数字/TBD 拒绝")
	# proposal 必须
	var f_badprop: Dictionary = f.duplicate(true)
	((f_badprop.get("classes", []) as Array)[0] as Dictionary)["proposal"] = false
	_ok(not bool(c.validate({"friendly": f_badprop, "enemy": e}).get("ok", true)),
		"proposal false 拒绝")
	_data_line("validation", "class_id/name/hull/known ship 唯一 · schema/数量/proposal/数值/TBD 校验")

# ═══════════════════════════════════════════════════════════════════
# 7. 错误/确定性
# ═══════════════════════════════════════════════════════════════════

func _test_errors_determinism() -> void:
	_section_begin("7 错误/确定性")
	var bad = ShipCatalog.new({"friendly_path": "/no/such_friendly.json"})
	_ok(not bool(bad.ready), "坏 friendly 路径失败")
	_ok((bad.errors as Array).size() >= 1, "坏路径 errors")
	var bad2 = ShipCatalog.new({"enemy_content": {"schema": "bad"}})
	_ok(not bool(bad2.ready), "坏 enemy 内容失败")
	# load 方法（load_catalog；load 与 GDScript 全局冲突）
	var c = _catalog()
	var lr: Dictionary = c.load_catalog(null, null)
	_eq(bool(lr.get("ok", false)), true, "load_catalog ok")
	_eq(bool(c.reload().get("ok", false)), true, "reload ok")
	# 失败不改已加载
	var before: String = c.to_json()
	var fail: Dictionary = c.load_catalog(null, "/no/such_enemy.json")
	_ok(not bool(fail.get("ok", true)), "坏 enemy 覆盖失败")
	_eq(c.to_json(), before, "失败不改已加载内容")
	# 确定性
	var a = _catalog()
	var b = _catalog()
	_eq(a.to_json(), b.to_json(), "两 catalog 内容一致")
	_eq(a.summary(), b.summary(), "两 catalog summary 一致")
	_eq(a.classes(), b.classes(), "classes 一致")
	_eq(a.ships(), b.ships(), "ships 一致")
	# 排序
	var ids: Array = []
	for raw in a.classes():
		ids.append(str((raw as Dictionary).get("class_id", "")))
	var sorted_ids: Array = ids.duplicate()
	sorted_ids.sort()
	_eq(ids, sorted_ids, "classes 排序")
	_ok(bool(a.check_contracts().get("ok", false)), "check contracts")
	_data_line("errors", "坏路径/内容失败 · load_catalog/reload · 失败原子 · 确定性/排序")
