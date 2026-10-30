extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DAMAGE PROFILE PROBE · 完整游戏-阶段5C
#
# 验证：36 型 class damage profile（section/装甲/材质/质量分数/差异）、
# DamageProfileService（查询/实体映射/未知回退/effects）、DamageModel 接入
# （旧 damage_l1 覆盖优先、命中/火灾/失压）、DamageService 接入（class 舰、
# 自动建档、存档/确定性）；不写 world/UI。只跑一次。
# ═══════════════════════════════════════════════════════════════════

const ProfileService := preload("res://scripts/core/damage_profile_service.gd")
const DamageModel := preload("res://framework/core/damage_model.gd")
const DamageService := preload("res://scripts/core/damage_service.gd")
const ShipCatalog := preload("res://scripts/core/ship_catalog.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("DAMAGE PROFILE PROBE · 完整游戏-阶段5C")
	print("════════════════════════════════════════════════════════════════")
	_test_profiles_data()
	_test_profile_service()
	_test_model_integration()
	_test_service_integration()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────────")
	print("DAMAGE PROFILE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("DAMAGE PROFILE PROBE FAILED")
		quit(1)
	else:
		print("DAMAGE PROFILE PROBE OK")
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


func _p() -> Object:
	return ProfileService.new()


func _mass_sum(prof: Dictionary) -> float:
	var n := 0.0
	for raw in (prof.get("sections", []) as Array):
		if raw is Dictionary:
			n += float((raw as Dictionary).get("mass_fraction", 0.0))
	return n


func _section_ids(prof: Dictionary) -> Array:
	var out: Array = []
	for raw in (prof.get("sections", []) as Array):
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("id", "")))
	return out


# ── 1. 36 型数据 ────────────────────────────────────────────

func _test_profiles_data() -> void:
	print("")
	print("── 1. 36 型 class damage profile ──")
	var p = _p()
	_ok(bool(p.ready), "profile service ready", str(p.errors))
	_ok((p.errors as Array).is_empty(), "profile service 无错误")
	_eq(int((p.classes as Dictionary).size()), 36, "36 型档案")
	_eq(int((p.class_ids as Array).size()), 36, "36 class ids")
	_eq(String((p.content as Dictionary).get("schema", "")), "damage_profiles.v1", "schema")
	_eq(String((p.content as Dictionary).get("version", "")), "1.0.0", "version")
	_eq(int((p.materials as Dictionary).size()), 4, "4 材质")
	var cat = ShipCatalog.new()
	_ok(bool(cat.ready), "ShipCatalog ready")
	var cat_ids: Array = []
	for raw in (cat.classes() as Array):
		if raw is Dictionary:
			cat_ids.append(String((raw as Dictionary).get("class_id", "")))
	# 5E 后 32 基础舰级 + 4 UEOF 变体 archetype（U7/U3 变体引用）共同构成 36 档案。
	for rawv in (cat.variants_of("") as Array):
		if rawv is Dictionary:
			var dpc := String((rawv as Dictionary).get("damage_profile_class_id", ""))
			if dpc != "" and not (dpc in cat_ids):
				cat_ids.append(dpc)
	cat_ids.sort()
	var p_ids: Array = (p.class_ids as Array).duplicate()
	p_ids.sort()
	_eq(p_ids.size(), cat_ids.size(), "档案数=ShipCatalog 36（32 基础+4 UEOF 变体原型）")
	_ok(p_ids == cat_ids, "class_id 与 ShipCatalog/变体 archetype 一致",
		"catalog+variant=%s profile=%s" % [str(cat_ids.size()), str(p_ids.size())])
	for cid in p.class_ids:
		var prof: Dictionary = p.profile_for(String(cid))
		_ok(not bool(prof.get("fallback", true)), "档案存在 " + String(cid))
		_eq(String(prof.get("class_id", "")), String(cid), "class_id " + String(cid))
		_ok(String(prof.get("name", "")) != "", "name " + String(cid))
		_ok(String(prof.get("hull_class", "")) in ["BB", "CA", "CL", "DD", "FF", "AUX", "STATION", "AV"],
			"hull_class " + String(cid), String(prof.get("hull_class", "")))
		_ok((prof.get("sections", []) as Array).size() >= 6, "sections " + String(cid))
		_ok(absf(_mass_sum(prof) - 1.0) <= 0.05, "mass sum " + String(cid))
		_ok((prof.get("effects", {}) as Dictionary).has("armor"), "armor effects " + String(cid))
		_ok((prof.get("effects", {}) as Dictionary).has("penetration"), "penetration effects " + String(cid))
		var secs: Array = prof.get("sections", []) as Array
		var sec_ok := true
		var mat_ok := true
		var mass_ok := true
		for raw2 in secs:
			if not (raw2 is Dictionary):
				sec_ok = false
				continue
			var s: Dictionary = raw2
			if String(s.get("id", "")) == "" or String(s.get("label", "")) == "":
				sec_ok = false
			if String(s.get("material", "")) in ["steel", "composite", "ceramic", "whipple"]:
				pass
			else:
				mat_ok = false
			if not (s.get("critical_systems") is Array) or (s.get("critical_systems") as Array).is_empty():
				sec_ok = false
			if float(s.get("armor_kinetic", -1.0)) < 0.0 or float(s.get("armor_energy", -1.0)) < 0.0:
				sec_ok = false
			if not (s.get("adjacent") is Array):
				sec_ok = false
			if not s.has("mass_fraction") or float(s.get("mass_fraction", -1.0)) <= 0.0:
				mass_ok = false
		_ok(sec_ok, "section fields " + String(cid))
		_ok(mat_ok, "section material " + String(cid))
		_ok(mass_ok, "section mass " + String(cid))
		_ok((p.sections(String(cid)) as Array).size() == secs.size(), "sections API " + String(cid))
	# 舰级差异
	var s_ids := _section_ids(p.profile_for("33OSID-RECEIVERSHIP"))
	_ok(s_ids.size() == 7, "BB 7 分区")
	_ok(_section_ids(p.profile_for("ORBFLT-BEACON")).size() == 6, "站体无 propulsion")
	_ok(not (_section_ids(p.profile_for("ORBFLT-BEACON")) as Array).has("propulsion"), "站体无动力分区")
	var bb_armor: Dictionary = p.armor("33OSID-RECEIVERSHIP")
	var ca_armor: Dictionary = p.armor("33OSID-ENFORCEMENT")
	var cl_armor: Dictionary = p.armor("33OSID-INTERDICT")
	var dd_armor: Dictionary = p.armor("33OSID-RECOURSE")
	var ff_armor: Dictionary = p.armor("33OSID-REQUISITION")
	_ok(float(bb_armor.get("kinetic_resist", 0.0)) > float(ca_armor.get("kinetic_resist", 1.0)),
		"BB > CA 装甲")
	_ok(float(ca_armor.get("kinetic_resist", 0.0)) > float(cl_armor.get("kinetic_resist", 1.0)),
		"CA > CL 装甲")
	_ok(float(cl_armor.get("kinetic_resist", 0.0)) > float(dd_armor.get("kinetic_resist", 1.0)),
		"CL > DD 装甲")
	_ok(float(dd_armor.get("kinetic_resist", 0.0)) > float(ff_armor.get("kinetic_resist", 1.0)),
		"DD > FF 装甲")
	var tanker: Dictionary = p.profile_for("OCUVF-MOONPORT-4")
	var tank_sec: Dictionary = p.section("OCUVF-MOONPORT-4", "tanks")
	_ok(float(tank_sec.get("mass_fraction", 0.0)) >= 0.25, "油船储罐质量占比")
	_ok(float(tank_sec.get("fire_risk", 0.0)) >= 0.5, "油船储罐火灾风险")
	_ok(float(tank_sec.get("vacuum_risk", 0.0)) >= 0.3, "油船储罐失压风险")
	var mat: String = p.material("33OSID-RECEIVERSHIP", "hull")
	_ok(mat in ["steel", "composite", "ceramic", "whipple"], "hull material")
	_ok(_json_ok(p.to_dict()), "profiles to_dict JSON")


# ── 2. service 查询/回退 ───────────────────────────────────

func _test_profile_service() -> void:
	print("")
	print("── 2. DamageProfileService 查询 / 实体 / 回退 ──")
	var p = _p()
	var prof: Dictionary = p.profile_for("33OSID-RECEIVERSHIP")
	_ok(String(prof.get("class_id", "")) == "33OSID-RECEIVERSHIP", "class 查询")
	_ok(not bool(prof.get("fallback", true)), "class 非回退")
	_ok(bool(p.profile_for("NOPE").get("fallback", false)), "未知 class 回退")
	_eq(String(p.profile_for("NOPE").get("class_id", "")), p.default_class_id, "未知回退 default")
	var ent: Dictionary = p.profile_for("harmattan")
	_eq(String(ent.get("class_id", "")), "OCUVF-PALLET-5C", "entity harmattan→class")
	_ok(not bool(ent.get("fallback", true)), "entity 非回退")
	_eq(String(p.profile_for("HARMATTAN").get("class_id", "")), "OCUVF-PALLET-5C", "entity 大写")
	_eq(String(p.profile_for("CA-4471").get("class_id", "")), "33OSID-ENFORCEMENT", "hull→class")
	_ok(bool(p.profile_for_entity("apsis").get("class_id", "") == "OCUVF-APOGEE"),
		"entity apsis→class")
	_ok((p.profile_for("").get("fallback", false)), "空 query 回退")
	# H01：真实未注册 fixture（不在 catalog/damage_l1/damage_profiles）→ 只读 fallback，不伪造档案。
	var uf := FileAccess.open("res://tests/fixtures/damage_profile/unregistered_entity.json", FileAccess.READ)
	if uf != null:
		var up = JSON.parse_string(uf.get_as_text())
		uf.close()
		var uspec: Dictionary = (up as Dictionary).get("entity", {}) if up is Dictionary else {}
		var uid := String(uspec.get("id", ""))
		var uclass := String(uspec.get("class", ""))
		_ok(uid != "" and uclass != "", "未注册 fixture 字段")
		_ok(bool(p.profile_for(uid).get("fallback", false)), "未注册实体回退")
		_ok(bool(p.profile_for(uclass).get("fallback", false)), "未注册 class 回退")
		_eq(String(p.profile_for(uid).get("class_id", "")), p.default_class_id,
			"未注册实体回退 default")
	else:
		_ok(false, "未注册 fixture 可读")
	_ok((p.sections("33OSID-RECEIVERSHIP") as Array).size() == 7, "sections API")
	_ok((p.section("33OSID-RECEIVERSHIP", "tanks") as Dictionary).get("id", "") == "tanks",
		"section API")
	_ok((p.section("33OSID-RECEIVERSHIP", "NOPE") as Dictionary).is_empty(), "未知 section 空")
	var arm: Dictionary = p.armor("33OSID-RECEIVERSHIP")
	_ok(float(arm.get("kinetic_resist", -1.0)) >= 0.0, "armor kinetic")
	_ok(float(arm.get("energy_resist", -1.0)) >= 0.0, "armor energy")
	var fx: Dictionary = p.effects("33OSID-RECEIVERSHIP")
	_ok(fx.has("armor") and fx.has("penetration"), "effects armor/penetration")
	_eq(p.hull_class("33OSID-RECEIVERSHIP"), "BB", "hull_class BB")
	_eq(p.hull_class("ORBFLT-BEACON"), "STATION", "hull_class STATION")
	var summ: Dictionary = p.summary()
	_eq(int(summ.get("classes", 0)), 36, "summary classes 36")
	_ok((summ.get("by_hull", {}) as Dictionary).has("BB"), "summary by_hull")
	_ok((summ.get("by_material", {}) as Dictionary).has("steel"), "summary by_material")
	_ok(_json_ok(summ), "summary JSON")
	_ok(_json_ok(p.to_json()), "to_json")
	# 无效内容
	var bad: Dictionary = (p.content as Dictionary).duplicate(true)
	bad.erase("classes")
	var pbad = ProfileService.new({"content": bad})
	_ok(not bool(pbad.ready), "缺 classes 不 ready")
	_ok((pbad.errors as Array).size() > 0, "缺 classes errors")
	var bad2: Dictionary = (p.content as Dictionary).duplicate(true)
	(bad2.get("classes", {}) as Dictionary).erase("33OSID-RECEIVERSHIP")
	var pbad2 = ProfileService.new({"content": bad2})
	_ok(not bool(pbad2.ready), "缺 class 不 ready")
	_ok(_json_ok(p.to_dict()), "final profile JSON")


# ── 3. DamageModel 接入 ────────────────────────────────────

func _test_model_integration() -> void:
	print("")
	print("── 3. DamageModel 按 class 接入 / 旧覆盖优先 ──")
	var p = _p()
	var prof_bb: Dictionary = p.profile_for("33OSID-RECEIVERSHIP")
	var prof_ff: Dictionary = p.profile_for("33OSID-REQUISITION")
	var bb = DamageModel.new()
	_ok(bool(bb.setup({}, "bb", prof_bb)), "model BB setup", str(bb.errors))
	_eq(String(bb.class_id), "33OSID-RECEIVERSHIP", "model class_id")
	_eq(String(bb.profile_source), "class_profile", "model source class_profile")
	_eq(String(bb.ship_class), "33OSID-RECEIVERSHIP / class_profile", "model ship_class")
	_ok((bb.sections as Array).size() == 7, "model BB sections")
	_ok((bb.section("hull") as Dictionary).has("armor_kinetic"), "model hull armor field")
	_ok(float((bb.section("hull") as Dictionary).get("armor_kinetic", -1.0)) > 0.0, "hull armor value")
	_ok((bb.section("tanks") as Dictionary).has("material"), "tanks material")
	_ok((bb.section("tanks") as Dictionary).has("mass_fraction"), "tanks mass_fraction")
	_ok((bb.section("tanks") as Dictionary).has("critical_systems"), "tanks critical_systems")
	_ok(bb.vm_damage().has("class_id"), "vm class_id")
	_eq(String(bb.vm_damage().get("class_id", "")), "33OSID-RECEIVERSHIP", "vm class_id value")
	_eq(String(bb.vm_damage().get("profile_source", "")), "class_profile", "vm profile_source")
	var vm_sec: Dictionary = (bb.vm_damage().get("sections", []) as Array)[0]
	_ok(vm_sec.has("armor_kinetic"), "vm section armor")
	_ok(vm_sec.has("material"), "vm section material")
	# 装甲差异：BB 受同能量伤害更小
	var hb: Dictionary = bb.apply_hit("hull", 0.5, 0.5, "fore", "probe")
	var ff = DamageModel.new()
	_ok(bool(ff.setup({}, "ff", prof_ff)), "model FF setup")
	var hf: Dictionary = ff.apply_hit("hull", 0.5, 0.5, "fore", "probe")
	var db := float((hb.get("hit", {}) as Dictionary).get("damage", 0.0))
	var df := float((hf.get("hit", {}) as Dictionary).get("damage", 0.0))
	_ok(db < df, "BB 伤害 < FF 伤害", "bb=%.4f ff=%.4f" % [db, df])
	# 火灾/失压（tanker 高 fire/vacuum）
	var tanker = DamageModel.new()
	_ok(bool(tanker.setup({}, "tanker", p.profile_for("OCUVF-MOONPORT-4"))), "tanker model setup")
	var ht: Dictionary = tanker.apply_hit("tanks", 0.9, 0.8, "fore", "probe")
	_ok(bool(ht.get("ok", false)), "tanks 命中")
	_ok(bool((tanker.section("tanks").get("fire", {}) as Dictionary).get("active", false)),
		"tanks 火灾触发")
	_ok(bool((tanker.section("tanks").get("decompression", {}) as Dictionary).get("active", false)),
		"tanks 失压触发")
	var summary_before: Dictionary = tanker.summary()
	tanker.step(1.0)
	_ok(float(tanker.section("tanks").get("integrity", 1.0)) < 1.0, "tick 火灾/失压损伤")
	_ok(_json_ok(tanker.vm_damage()), "tanker vm JSON")
	# 站体无 propulsion
	var st = DamageModel.new()
	_ok(bool(st.setup({}, "station", p.profile_for("ORBFLT-BEACON"))), "station model setup")
	_ok((st.section("propulsion") as Dictionary).is_empty(), "station 无 propulsion 分区")
	_ok((st.sections as Array).size() == 6, "station sections 6")
	# 旧 damage_l1 显式档案优先
	var oldm = DamageModel.new()
	_ok(bool(oldm.setup({}, "summons_4471", prof_bb)), "old override setup")
	_eq(String(oldm.profile_source), "damage_l1", "old override source")
	_ok(String(oldm.class_id) == "", "old override class_id 空")
	_ok((oldm.sections as Array).size() == 7, "old override sections")
	_ok(float((oldm.section("hull") as Dictionary).get("armor_kinetic", -1.0)) < 0.0,
		"old override 无 class armor 字段")
	# reset 保留 class profile
	bb.reset()
	_eq(String(bb.class_id), "33OSID-RECEIVERSHIP", "reset 保留 class")
	_eq(float(bb.t), 0.0, "reset t")
	_ok(_json_ok(bb.vm_damage()), "model vm JSON")


# ── 4. DamageService 接入 ──────────────────────────────────

func _test_service_integration() -> void:
	print("")
	print("── 4. DamageService 按 class / 自动建档 / 旧行为 ──")
	var s = DamageService.new({"ships": [
		{"id": "bb1", "class_id": "33OSID-RECEIVERSHIP"},
		{"id": "ff1", "class_id": "33OSID-REQUISITION"}]})
	_ok(bool(s.ready), "service class ships ready", str(s.errors))
	_ok(bool(s.profiles_enabled), "profiles enabled")
	_eq(int((s.ship_ids as Array).size()), 2, "class ships 2")
	_eq(String(s.ship_class_id("bb1")), "33OSID-RECEIVERSHIP", "service ship class")
	var pvm: Dictionary = s.vm()
	_ok((pvm.get("profiles", {}) as Dictionary).get("enabled", false), "vm profiles enabled")
	_eq(int((pvm.get("profiles", {}) as Dictionary).get("classes", 0)), 36, "vm profile classes")
	_eq(int((s.summary() as Dictionary).get("profile_classes", 0)), 36, "summary profile classes")
	# 自动建档
	var ar: Dictionary = s.add_ship("ca1", "33OSID-ENFORCEMENT")
	_ok(bool(ar.get("ok", false)), "add_ship class", str(ar.get("errors", [])))
	_eq(String(ar.get("class_id", "")), "33OSID-ENFORCEMENT", "add class id")
	_eq(String(s.ship_class_id("ca1")), "33OSID-ENFORCEMENT", "ca1 class")
	_ok(s.ships.has("ca1"), "ca1 in ships")
	# 未知无 class
	_ok(not bool(s.add_ship("xx", "NOPE").get("ok", true)), "未知 class add false")
	# 直接伤害 class 舰
	var dmg: Dictionary = s.apply_combat_damage({"schema": "combat_damage_event.v1",
		"kind": "damage", "target_ship": "bb1", "damage": 0.4,
		"penetration": 0.7, "section": "tanks", "direction": "fore"})
	_ok(bool(dmg.get("ok", false)), "class ship damage", str(dmg.get("errors", [])))
	_ok(bool(dmg.get("applied", false)), "class ship applied")
	_ok(float((s.ship_vm("bb1").get("sections", []) as Array).size()) >= 1, "bb1 vm sections")
	# 未知舰 + class_id 自动建档
	var auto: Dictionary = s.apply_combat_damage({"schema": "combat_damage_event.v1",
		"kind": "damage", "target_ship": "auto_dd", "class_id": "33OSID-RECOURSE",
		"damage": 0.3, "penetration": 0.5, "section": "hull"})
	_ok(bool(auto.get("ok", false)), "未知舰 class_id 自动建档", str(auto.get("errors", [])))
	_ok(s.ships.has("auto_dd"), "auto_dd in ships")
	# 旧 damage_l1 显式覆盖优先
	var old = DamageService.new({"ships": [
		{"id": "harmattan", "class_id": "33OSID-RECEIVERSHIP"},
		{"id": "summons_4471"}]})
	_ok(bool(old.ready), "old override service ready")
	_eq(String(old.ship_class_id("harmattan")), "", "旧显式档案 class_id 空")
	_ok(String(old.ship_vm("harmattan").get("profile_source", "")) == "damage_l1",
		"旧显式档案 source")
	# 旧 service（默认全旧）
	var legacy = DamageService.new()
	_ok(bool(legacy.ready), "legacy service ready")
	_eq((legacy.ship_ids as Array).size(), 6, "legacy ships 6")
	_eq(String(legacy.ship_class_id("harmattan")), "", "legacy harmattan class_id 空")
	_ok(legacy.profile_service != null, "legacy profile service loaded")
	# 存档/恢复 class 舰
	var txt: String = s.save_state()
	_ok((JSON.parse_string(txt) as Dictionary).has("ship_classes"), "save ship_classes")
	var s2 = DamageService.new({"ships": [
		{"id": "bb1", "class_id": "33OSID-RECEIVERSHIP"},
		{"id": "ff1", "class_id": "33OSID-REQUISITION"}]})
	var lr: Dictionary = s2.load_state(txt)
	_ok(bool(lr.get("ok", false)), "class service load ok", str(lr.get("errors", [])))
	_ok(s2.ships.has("ca1"), "load class-added ca1")
	_ok(s2.ships.has("auto_dd"), "load auto_dd")
	_eq(String(s2.ship_class_id("bb1")), "33OSID-RECEIVERSHIP", "load bb1 class")
	_ok(_json_ok(s2.vm()), "class service vm JSON")
	# 非法 profiles 不破坏旧服务
	var pc = ProfileService.new()
	var bad_content := (pc.content as Dictionary).duplicate(true)
	bad_content["schema"] = "x"
	var sbad = DamageService.new({"ships": [{"id": "bb1", "class_id": "33OSID-RECEIVERSHIP"}],
		"profile_content": bad_content})
	_ok(not bool(sbad.ready), "非法 profile 配置不 ready")
	_ok((sbad.errors as Array).size() > 0, "非法 profile errors")


# ── 5. JSON / 确定性 ───────────────────────────────────────

func _test_json_determinism() -> void:
	print("")
	print("── 5. JSON / 确定性 ──")
	var p = _p()
	_ok(_json_ok(p.summary()), "profile summary JSON")
	_ok(_json_ok(p.to_json()), "profile to_json")
	var m = DamageModel.new()
	_ok(bool(m.setup({}, "x", p.profile_for("UEOF-7TH-CA"))), "model setup determinism")
	var a: Dictionary = m.apply_hit("hull", 0.4, 0.6, "fore", "probe")
	_ok(_json_ok(a), "hit JSON")
	_ok(_json_ok(m.vm_damage()), "model vm JSON")
	var m2 = DamageModel.new()
	m2.setup({}, "x", p.profile_for("UEOF-7TH-CA"))
	var b: Dictionary = m2.apply_hit("hull", 0.4, 0.6, "fore", "probe")
	_ok(JSON.stringify(a.get("hit", {})) == JSON.stringify(b.get("hit", {})), "model 确定性 hit")
	_ok(JSON.stringify(m.summary()) == JSON.stringify(m2.summary()), "model 确定性 summary")
	var svc_a = DamageService.new({"ships": [{"id": "c1", "class_id": "ORBFLT-SENTINEL"}]})
	var svc_b = DamageService.new({"ships": [{"id": "c1", "class_id": "ORBFLT-SENTINEL"}]})
	for sv in [svc_a, svc_b]:
		sv.apply_hit("c1", "hull", 0.3, 0.5, "fore", "probe")
		sv.tick(1.0)
	_ok(JSON.stringify(svc_a.vm()) == JSON.stringify(svc_b.vm()), "service 确定性 VM")
	_ok(_json_ok(svc_a.summary()), "service summary JSON")
	_ok(((svc_a.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((svc_a.vm().get("writes", {}) as Dictionary).get("ui", true)) == false, "不写 UI")
