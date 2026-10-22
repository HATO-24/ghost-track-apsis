extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5E 最小 probe：ShipCatalog 共用舰级/亚种/自动推算/审计
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
const BASE_ORB := [
	"ORBFLT-POLARIS", "ORBFLT-SENTINEL", "ORBFLT-GATEKEEPER",
	"ORBFLT-FORGE", "ORBFLT-TRACTOR", "ORBFLT-BEACON"]

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE5E PROBE · ShipCatalog variants/derive/audit")
	print("════════════════════════════════════════════════════════════")
	_test_load_counts()
	_test_friendly()
	_test_33osid_audit()
	_test_orbflt_variants()
	_test_derivation()
	_test_catalog_api()
	_test_validation_errors()
	_test_determinism()
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

func _base_rows(c) -> Dictionary:
	var out: Dictionary = {}
	for raw in (c.classes() as Array):
		out[str((raw as Dictionary).get("class_id", ""))] = raw
	return out

func _variant(c, vid: String) -> Dictionary:
	var r: Dictionary = c.resolve_variant(vid)
	if bool(r.get("ok", false)):
		return (r.get("variant", {}) as Dictionary)
	return {}

# ═══════════════════════════════════════════════════════════════════
# 1. 加载/数量
# ═══════════════════════════════════════════════════════════════════

func _test_load_counts() -> void:
	_section_begin("1 加载/数量")
	var c = _catalog()
	var sum: Dictionary = c.summary()
	_eq(int(sum.get("classes", 0)), 32, "base classes 32（友8+敌24）")
	_eq(int(sum.get("friendly_classes", 0)), 8, "友军 8")
	_eq(int(sum.get("enemy_classes", 0)), 24, "敌军 24")
	_eq(int(sum.get("variants", 0)), 18, "variant 18")
	_eq(int(sum.get("variant_classes", 0)), 18, "variant_classes 18")
	var fac: Dictionary = sum.get("factions", {}) as Dictionary
	_eq(int(fac.get("ocuvf_id13", 0)), 8, "faction 友军 8")
	_eq(int(fac.get("33osid", 0)), 18, "faction 33OSID 18")
	_eq(int(fac.get("uegaf_orbflt", 0)), 6, "faction ORBFLT 6")
	_eq(int(fac.get("ueof_7th", 0)), 0, "UEOF7 独立 class 0")
	_eq(int(fac.get("ueof_3rd", 0)), 0, "UEOF3 独立 class 0")
	_eq(int(sum.get("orbflt_classes", 0)), 6, "ORBFLT base 6")
	_eq((sum.get("base_orbflt", []) as Array).size(), 6, "base_orbflt 6")
	_eq(int(sum.get("ueof_7th_classes", 0)), 0, "UEOF 7th classes 0")
	_eq(int(sum.get("ueof_3rd_classes", 0)), 0, "UEOF 3rd classes 0")
	_eq(int(sum.get("ueof_7th_variants", 0)), 6, "UEOF7 variants 6")
	_eq(int(sum.get("ueof_3rd_variants", 0)), 6, "UEOF3 variants 6")
	_eq(int(sum.get("fleet_variants", 0)), 6, "fleet variants 6")
	var ops: Dictionary = sum.get("operator_variants", {}) as Dictionary
	_eq(int(ops.get("ueof_7th", 0)), 6, "operator ueof7 6")
	_eq(int(ops.get("ueof_3rd", 0)), 6, "operator ueof3 6")
	_eq(int(ops.get("uegaf_orbflt", 0)), 6, "operator fleet 6")
	_eq(int(sum.get("known_ships", 0)), 7, "known ships 7")
	_eq(int(sum.get("friendly_ships", 0)), 5, "friendly ships 5")
	_eq(int(sum.get("enemy_ships", 0)), 2, "enemy ships 2")
	_eq(bool(sum.get("proposal", false)), true, "summary proposal")
	_eq(bool(sum.get("truth", true)), false, "summary truth false")
	_ok(bool(c.check_contracts().get("ok", false)), "contracts ok",
		str(c.check_contracts().get("violations", [])))
	_ok(bool(c.validate().get("ok", false)), "validate ok", str(c.validate().get("errors", [])))
	_data_line("counts", "base 32（友8+33OSID18+ORBFLT6）· variant 18（UEOF 7/3 各6 + fleet6）")

# ═══════════════════════════════════════════════════════════════════
# 2. 友军（保持 8 型）
# ═══════════════════════════════════════════════════════════════════

func _test_friendly() -> void:
	_section_begin("2 友军 8 型")
	var c = _catalog()
	var by_id: Dictionary = _base_rows(c)
	for i in range(FRIENDLY_IDS.size()):
		var cid := str(FRIENDLY_IDS[i])
		_ok(by_id.has(cid), "友军存在 " + cid)
		var row: Dictionary = by_id.get(cid, {})
		_eq(str(row.get("faction", "")), "ocuvf_id13", cid + " faction")
		_eq(str(row.get("role", "")), str(FRIENDLY_ROLES[i]), cid + " role")
		for f in ["class_id", "name", "role", "hull_code_prefix",
				"displacement_t", "dv_kmps", "accel_g", "crew", "sensors",
				"weapons", "armor", "rcs", "ir", "dimensions_m", "sections",
				"known_ships", "name_pool", "proposal"]:
			_ok(row.has(f), cid + " 字段 " + f)
		_ok(bool(row.get("proposal", false)), cid + " proposal")
		_ok(str(row.get("hull_range", "")) != "", cid + " hull_range")
		_ok(str(row.get("source", "")) != "", cid + " source")
	var apogee: Dictionary = by_id["OCUVF-APOGEE"]
	_near(float(apogee.get("displacement_t", 0.0)), 9000.0, 1.0e-6, "APOGEE 9000t")
	_near(float(apogee.get("dv_kmps", 0.0)), 3.15, 1.0e-6, "APOGEE 3.15")
	_eq(int(apogee.get("crew", 0)), 240, "APOGEE 240")
	_eq(str(c.known_ship("APSIS").get("hull_code", "")), "001", "APSIS 001")
	_eq(str(c.known_ship("HARMATTAN").get("hull_code", "")), "114", "HARMATTAN 114")
	_eq(str(c.entity_binding("apsis").get("ship_id", "")), "APSIS", "apsis binding")
	_data_line("friendly", "8 型保持 · APSIS 001/HARMATTAN 114 · 字段/成本值不变")

# ═══════════════════════════════════════════════════════════════════
# 3. 33OSID / CA-4471 audit
# ═══════════════════════════════════════════════════════════════════

func _test_33osid_audit() -> void:
	_section_begin("3 33OSID 审计")
	var c = _catalog()
	var rows: Array = c.classes("33osid")
	_eq(rows.size(), 18, "33OSID 18")
	var by_id: Dictionary = _base_rows(c)
	var base_codes := {"33OSID-RECEIVERSHIP": "BB", "33OSID-ENFORCEMENT": "CA",
		"33OSID-INTERDICT": "CL", "33OSID-RECOURSE": "DD",
		"33OSID-REQUISITION": "FF", "33OSID-SUMMONS": "AV"}
	for b in BASE_33:
		_ok(by_id.has(b), "base 存在 " + b)
		var row: Dictionary = by_id.get(b, {})
		_eq(str(row.get("hull_code", "")), str(base_codes[b]), b + " type code")
		_eq(str(row.get("variant_of", "")), "", b + " base")
		var n := 0
		for raw2 in rows:
			var r2: Dictionary = raw2
			if str(r2.get("variant_of", "")) == b:
				n += 1
				_eq(str(r2.get("faction", "")), "33osid", str(r2.get("class_id")) + " faction")
				_ok(bool(r2.get("proposal", false)), str(r2.get("class_id")) + " proposal")
		_eq(n, 2, b + " 2 亚种")
	var ca: Dictionary = c.known_ship("CA-4471")
	_eq(str(ca.get("class_id", "")), "33OSID-ENFORCEMENT", "CA class")
	_ok(ca.has("batch"), "CA has batch 字段")
	_eq(ca.get("batch"), null, "CA batch null/unassigned")
	_ok(str(ca.get("batch_source", "")).contains("舷号"), "CA batch_source")
	_eq(c.by_batch("TBD"), {}, "by_batch TBD 不命中 CA")
	var av: Dictionary = c.known_ship("AV-4412")
	_eq(str(av.get("batch", "")), "2001", "AV batch 2001")
	_ok(str(av.get("batch_source", "")) != "", "AV batch_source")
	_eq(str(c.by_batch("2001").get("ship_id", "")), "AV-4412", "by_batch 2001 AV")
	_eq(str(c.by_batch("1000").get("ship_id", "")), "APSIS", "by_batch 1000 友军")
	var e: Dictionary = c.to_dict().get("enemy", {}) as Dictionary
	_ok(e.get("audit") is Dictionary, "enemy audit 对象")
	var audit: Dictionary = e.get("audit", {}) as Dictionary
	_eq(int(audit.get("33osid_checked_classes", 0)), 18, "audit checked 18")
	_eq(int(audit.get("33osid_known_ships", 0)), 2, "audit known 2")
	_ok((audit.get("33osid_findings", []) as Array).size() >= 3, "audit findings")
	var ca_fix := false
	for raw3 in (audit.get("33osid_findings", []) as Array):
		if raw3 is Dictionary and str((raw3 as Dictionary).get("id", "")) == "CA-4471":
			ca_fix = true
	_ok(ca_fix, "audit 含 CA-4471")
	_data_line("33osid", "18（6 base+12 变体）· CA-4471 batch null+batch_source · AV 2001 · audit findings")

# ═══════════════════════════════════════════════════════════════════
# 4. ORBFLT base + 共用变体
# ═══════════════════════════════════════════════════════════════════

func _test_orbflt_variants() -> void:
	_section_begin("4 ORBFLT/共享变体")
	var c = _catalog()
	var bases: Array = c.classes("uegaf_orbflt")
	_eq(bases.size(), 6, "ORBFLT base 6")
	var all_vids: Dictionary = {}
	var total_op := 0
	var total_fleet := 0
	for raw in bases:
		var row: Dictionary = raw
		var bid := str(row.get("class_id", ""))
		_ok(bid in BASE_ORB, "base id " + bid)
		for nf in ["displacement_t", "dv_kmps", "accel_g", "crew"]:
			_ok(row.get(nf) is int or row.get(nf) is float, bid + " 数值 " + str(nf))
			_ok(not (row.get(nf) is String and String(row.get(nf)) == "TBD"),
				bid + " 非 TBD " + str(nf))
		_ok((row.get("sensors", []) as Array).size() >= 2, bid + " sensors")
		_ok((row.get("weapons", []) as Array).size() >= 1, bid + " weapons")
		_eq((row.get("operator_variants", []) as Array).size(), 2, bid + " operator 2")
		_eq((row.get("fleet_variants", []) as Array).size(), 1, bid + " fleet 1")
		var ops: Dictionary = {}
		for ov in (row.get("operator_variants", []) as Array):
			var orow: Dictionary = ov
			total_op += 1
			ops[str(orow.get("operator", ""))] = true
			_ok(str(orow.get("variant_id", "")) != "", bid + " variant_id")
			_ok(str(orow.get("name", "")) != "", bid + " variant name")
			_ok(str(orow.get("role", "")) != "", bid + " variant role")
			_ok(str(orow.get("refit", "")) != "", bid + " variant refit")
			_eq(str(orow.get("derive_from", "")), bid, bid + " derive_from")
			_ok(orow.get("modifiers") is Dictionary, bid + " modifiers")
			_eq(bool(orow.get("proposal", false)), true, bid + " variant proposal")
			all_vids[str(orow.get("variant_id", ""))] = true
		_ok(bool(ops.get("ueof_7th", false)), bid + " 覆盖 7th")
		_ok(bool(ops.get("ueof_3rd", false)), bid + " 覆盖 3rd")
		for fv in (row.get("fleet_variants", []) as Array):
			var frow: Dictionary = fv
			total_fleet += 1
			_eq(str(frow.get("operator", "")), "uegaf_orbflt", bid + " fleet operator")
			_eq(str(frow.get("derive_from", "")), bid, bid + " fleet derive")
			all_vids[str(frow.get("variant_id", ""))] = true
			_ok(str(frow.get("refit", "")) != "", bid + " fleet refit")
	_eq(total_op, 12, "operator variants 12")
	_eq(total_fleet, 6, "fleet variants 6")
	_eq(all_vids.size(), 18, "variant id 唯一 18")
	for b2 in BASE_ORB:
		_eq(c.variants_of(str(b2)).size(), 3, "variants_of base " + str(b2))
	_eq(c.variants_of("ueof_7th").size(), 6, "variants_of ueof7")
	_eq(c.variants_of("ueof_3rd").size(), 6, "variants_of ueof3")
	_eq(c.variants_of("uegaf_orbflt").size(), 6, "variants_of fleet")
	_eq(c.variants_of("").size(), 18, "variants_of all 18")
	_eq(c.variants_of("NOPE").size(), 0, "variants_of 未知空")
	_eq(c.classes("ueof_7th").size(), 0, "UEOF 无独立 class")
	_eq(c.classes("ueof_3rd").size(), 0, "UEOF3 无独立 class")
	for vid in all_vids.keys():
		var v: Dictionary = _variant(c, str(vid))
		_ok(not v.is_empty(), "resolve_variant " + str(vid))
		_ok(str(v.get("variant_of", "")) != "", str(vid) + " variant_of")
		_ok(str(v.get("base_class_id", "")) != "", str(vid) + " base_class_id")
		_ok(str(v.get("name", "")) != "", str(vid) + " name")
		_ok(str(v.get("role", "")) != "", str(vid) + " role")
		_ok(str(v.get("refit", "")) != "", str(vid) + " refit")
		_ok(v.get("modifiers") is Dictionary or v.get("derivation") is Dictionary,
			str(vid) + " modifiers/derivation")
		_eq(bool(v.get("derived", false)), true, str(vid) + " derived")
		_eq(bool(v.get("proposal", false)), true, str(vid) + " proposal")
		_eq(bool(v.get("truth", true)), false, str(vid) + " truth false")
		_ok(str(v.get("class_id", "")) in BASE_ORB, str(vid) + " class_id 指向 base")
		_eq(str(c.class_of(str(vid)).get("class_id", "")), str(v.get("derive_from", "")),
			str(vid) + " class_of 展开到 base")
	_data_line("orbflt/variants", "ORBFLT 6 base · operator 2/base（覆盖7/3）· fleet 1/base · 共18")

# ═══════════════════════════════════════════════════════════════════
# 5. 自动推算
# ═══════════════════════════════════════════════════════════════════

func _test_derivation() -> void:
	_section_begin("5 自动推算")
	var c = _catalog()
	var by_id: Dictionary = _base_rows(c)
	var checked := 0
	for base_id in BASE_ORB:
		var base: Dictionary = by_id.get(base_id, {})
		for raw in c.variants_of(base_id):
			var v: Dictionary = raw
			var mod: Dictionary = v.get("modifiers", {}) if v.get("modifiers") is Dictionary else {}
			var bmass := float(base.get("displacement_t", 0.0))
			var bdv := float(base.get("dv_kmps", 0.0))
			var bacc := float(base.get("accel_g", 0.0))
			var bcrew := int(base.get("crew", 0))
			var mf := float(mod.get("mass_factor", 1.0))
			var df := float(mod.get("dv_factor", 1.0))
			var af := float(mod.get("accel_factor", 1.0))
			var cf := float(mod.get("crew_factor", 1.0))
			_near(float(v.get("displacement_t", 0.0)), bmass * mf, 0.01,
				str(v.get("variant_id")) + " mass 推算")
			_near(float(v.get("dv_kmps", 0.0)), bdv * df, 0.001,
				str(v.get("variant_id")) + " dv 推算")
			_near(float(v.get("accel_g", 0.0)), bacc * af, 0.001,
				str(v.get("variant_id")) + " accel 推算")
			_eq(int(v.get("crew", 0)), int(round(float(bcrew) * cf)),
				str(v.get("variant_id")) + " crew 推算")
			_ok(not (v.get("displacement_t") is String), str(v.get("variant_id")) + " 非 TBD mass")
			_ok(not (v.get("dv_kmps") is String), str(v.get("variant_id")) + " 非 TBD dv")
			_ok(not (v.get("accel_g") is String), str(v.get("variant_id")) + " 非 TBD accel")
			_ok(not (v.get("crew") is String), str(v.get("variant_id")) + " 非 TBD crew")
			var bs: Array = (base.get("sensors", []) as Array).duplicate()
			var adds: Array = mod.get("sensors_add", []) as Array
			for s in adds:
				if not str(s) in bs:
					bs.append(str(s))
			_eq((v.get("sensors", []) as Array).size(), bs.size(),
				str(v.get("variant_id")) + " sensors 合并")
			_ok(v.get("stats_derived") is Dictionary, str(v.get("variant_id")) + " stats_derived")
			var sd: Dictionary = v.get("stats_derived", {}) as Dictionary
			_near(float(sd.get("displacement_t", 0.0)), float(v.get("displacement_t", 0.0)),
				1.0e-6, str(v.get("variant_id")) + " stats mass")
			_eq(int(sd.get("crew", -1)), int(v.get("crew", -2)),
				str(v.get("variant_id")) + " stats crew")
			checked += 1
	_eq(checked, 18, "18 变体推算检查")
	var one: Dictionary = _variant(c, "ORBFLT-SENTINEL-U7")
	var one_base: Dictionary = by_id["ORBFLT-SENTINEL"]
	_near(float(one.get("displacement_t", 0.0)), float(one_base.get("displacement_t", 0.0)) * 1.02,
		0.01, "Sentinel U7 mass")
	_near(float(one.get("dv_kmps", 0.0)), float(one_base.get("dv_kmps", 0.0)) * 1.12,
		0.001, "Sentinel U7 dv")
	_ok("ELINT-7" in (one.get("sensors", []) as Array), "Sentinel U7 sensor add")
	_ok("MISSILE-7" in (one.get("weapons", []) as Array), "Sentinel U7 weapon add")
	_ok(str(one.get("derive_from", "")) == "ORBFLT-SENTINEL", "Sentinel U7 derive_from")
	_ok(str(one.get("operator", "")) == "ueof_7th", "Sentinel U7 operator")
	_data_line("derive", "18 变体 base×倍率推算 mass/dv/accel/crew + sensors/weapons add · 无 TBD")

# ═══════════════════════════════════════════════════════════════════
# 6. Catalog API
# ═══════════════════════════════════════════════════════════════════

func _test_catalog_api() -> void:
	_section_begin("6 API")
	var c = _catalog()
	_eq(str(c.resolve_variant("ORBFLT-SENTINEL-U7").get("kind", "")), "variant",
		"resolve_variant kind")
	_eq(str(c.resolve_variant("ORBFLT-SENTINEL-U7").get("base_class_id", "")),
		"ORBFLT-SENTINEL", "resolve_variant base")
	_eq(str(c.resolve_variant("NOPE").get("reason", "")), "unknown_variant",
		"resolve_variant 未知")
	_eq(str(c.resolve("ORBFLT-SENTINEL-U3").get("kind", "")), "variant",
		"resolve variant kind")
	_eq(str(c.class_of("ORBFLT-SENTINEL-FLT").get("class_id", "")), "ORBFLT-SENTINEL",
		"class_of variant -> base")
	_eq(str(c.class_of("ORBFLT-SENTINEL").get("class_id", "")), "ORBFLT-SENTINEL",
		"class_of base")
	_eq(c.known_ship("NOPE"), {}, "known 未知空")
	_ok(not c.name_pool("ORBFLT-SENTINEL").is_empty(), "name_pool base")
	_eq(c.name_pool("NOPE").size(), 0, "name_pool 未知空")
	_eq(c.variants_of("NOPE").size(), 0, "variants 未知空")
	_eq(c.known_ship("APSIS").get("class_id"), "OCUVF-APOGEE", "APSIS class")
	_eq(c.known_ship("CA-4471").get("class_id"), "33OSID-ENFORCEMENT", "CA class")
	var d: Dictionary = c.to_dict()
	_ok(d.get("enemy") is Dictionary, "to_dict enemy")
	_ok(d.get("friendly") is Dictionary, "to_dict friendly")
	var js: String = c.to_json()
	_ok(js.length() > 1000, "to_json 长")
	_ok(JSON.parse_string(js) is Dictionary, "to_json 可解析")
	_ok(js.contains("\"variant_id\""), "JSON 含 variant_id")
	_ok(js.contains("\"proposal\":true"), "JSON proposal true")
	var sum: Dictionary = c.summary()
	_ok((sum.get("base_orbflt", []) as Array).has("ORBFLT-SENTINEL"), "summary base orbflt")
	_ok(int(sum.get("auto_derived_variants", 0)) == 18, "summary auto 18")
	_data_line("api", "variants_of/resolve_variant/resolve/class_of/name_pool/summary/to_json")

# ═══════════════════════════════════════════════════════════════════
# 7. 校验/失败
# ═══════════════════════════════════════════════════════════════════

func _test_validation_errors() -> void:
	_section_begin("7 校验/失败")
	var c = _catalog()
	var d: Dictionary = c.to_dict()
	var f: Dictionary = (d.get("friendly") as Dictionary).duplicate(true)
	var e: Dictionary = (d.get("enemy") as Dictionary).duplicate(true)
	_ok(bool(c.validate({"friendly": f, "enemy": e}).get("ok", false)),
		"候选合法")
	var e_dup: Dictionary = e.duplicate(true)
	for raw in (e_dup.get("classes", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("class_id", "")) == "ORBFLT-SENTINEL":
			var r: Dictionary = raw
			var fv: Array = r.get("fleet_variants", []) as Array
			var dup: Dictionary = (fv[0] as Dictionary).duplicate(true)
			dup["variant_id"] = "ORBFLT-SENTINEL-U7"
			fv.append(dup)
			r["fleet_variants"] = fv
	_ok(not bool(c.validate({"friendly": f, "enemy": e_dup}).get("ok", true)),
		"variant_id 重复拒绝")
	var e_bad_derive: Dictionary = e.duplicate(true)
	for raw2 in (e_bad_derive.get("classes", []) as Array):
		if raw2 is Dictionary and str((raw2 as Dictionary).get("class_id", "")) == "ORBFLT-SENTINEL":
			((raw2 as Dictionary)["operator_variants"] as Array)[0]["derive_from"] = "NOPE"
	_ok(not bool(c.validate({"friendly": f, "enemy": e_bad_derive}).get("ok", true)),
		"derive_from 错误拒绝")
	var e_noop: Dictionary = e.duplicate(true)
	for raw3 in (e_noop.get("classes", []) as Array):
		if raw3 is Dictionary and str((raw3 as Dictionary).get("class_id", "")) == "ORBFLT-SENTINEL":
			(raw3 as Dictionary)["operator_variants"] = [((raw3 as Dictionary)["operator_variants"] as Array)[0]]
	_ok(not bool(c.validate({"friendly": f, "enemy": e_noop}).get("ok", true)),
		"operator 覆盖不足拒绝")
	var e_tbd: Dictionary = e.duplicate(true)
	for raw4 in (e_tbd.get("classes", []) as Array):
		if raw4 is Dictionary and str((raw4 as Dictionary).get("class_id", "")) == "ORBFLT-SENTINEL":
			(raw4 as Dictionary)["displacement_t"] = "TBD"
	_ok(not bool(c.validate({"friendly": f, "enemy": e_tbd}).get("ok", true)),
		"ORBFLT 数值 TBD 拒绝")
	var e_ca: Dictionary = e.duplicate(true)
	for raw5 in (e_ca.get("classes", []) as Array):
		if raw5 is Dictionary and str((raw5 as Dictionary).get("class_id", "")) == "33OSID-ENFORCEMENT":
			((raw5 as Dictionary)["known_ships"] as Array)[0]["batch"] = "TBD"
	_ok(not bool(c.validate({"friendly": f, "enemy": e_ca}).get("ok", true)),
		"CA batch TBD 拒绝")
	var e_noaudit: Dictionary = e.duplicate(true)
	e_noaudit.erase("audit")
	_ok(not bool(c.validate({"friendly": f, "enemy": e_noaudit}).get("ok", true)),
		"audit 缺失拒绝")
	var e_ueof: Dictionary = e.duplicate(true)
	var urow: Dictionary = (e.get("classes", [])[0] as Dictionary).duplicate(true)
	urow["class_id"] = "UEOF-X-CA"; urow["faction"] = "ueof_7th"; urow["name"] = "X级"
	e_ueof["classes"] = (e_ueof.get("classes", []) as Array) + [urow]
	_ok(not bool(c.validate({"friendly": f, "enemy": e_ueof}).get("ok", true)),
		"UEOF 独立 class 拒绝")
	_eq(str(c.resolve_variant("").get("reason", "")), "unknown_variant", "resolve_variant 空")
	_data_line("validation", "variant_id/derive/operator覆盖/ORBFLT TBD/CA batch/audit/UEOF独立 class 均拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("8 确定性")
	var a = _catalog()
	var b = _catalog()
	_eq(a.to_json(), b.to_json(), "两 catalog JSON 一致")
	_eq(a.summary(), b.summary(), "summary 一致")
	_eq(a.classes(), b.classes(), "classes 一致")
	_eq(a.variants_of(""), b.variants_of(""), "variants 一致")
	_eq(a.to_dict().get("enemy", {}), b.to_dict().get("enemy", {}), "enemy 内容一致")
	var ids: Array = []
	for raw in a.variants_of(""):
		ids.append(str((raw as Dictionary).get("variant_id", "")))
	var sorted_ids: Array = ids.duplicate()
	sorted_ids.sort()
	_eq(ids, sorted_ids, "variant 排序")
	_ok(bool(a.check_contracts().get("ok", false)), "contracts")
	_data_line("determinism", "JSON/summary/classes/variants/enemy 一致 · variant 排序")
