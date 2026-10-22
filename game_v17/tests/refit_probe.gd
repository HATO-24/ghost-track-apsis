extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5B 最小 probe：RefitService（APSIS 干船坞改装）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/refit_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；只读改装服务，不接 UI/不写 world。
# ═══════════════════════════════════════════════════════════════════

const RefitService := preload("res://scripts/core/refit_service.gd")
const ShipCatalog := preload("res://scripts/core/ship_catalog.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

const CATS := ["hull", "sensor", "weapon", "defense", "utility", "dock"]
const CAT_COUNT := {"hull": 4, "sensor": 5, "weapon": 6, "defense": 4,
	"utility": 7, "dock": 4}

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE5B PROBE · RefitService")
	print("════════════════════════════════════════════════════════════")
	_test_setup()
	_test_modules()
	_test_slots_quote()
	_test_install_commit_tick()
	_test_constraints()
	_test_remove_save_errors()
	_test_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 REFIT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 REFIT PROBE FAILED")
		quit(1)
	else:
		print("V17 REFIT PROBE OK")
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
	var cat = ShipCatalog.new()
	_ok(bool(cat.ready), "ShipCatalog ready", str(cat.errors))
	return cat

func _svc(cat, res := {}) -> Object:
	var s = RefitService.new(cat, null, res)
	_ok(bool(s.ready), "RefitService ready", str(s.errors))
	return s

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 基础 stats / 模块数量
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 setup/基础")
	var cat = _catalog()
	var s = _svc(cat)
	var sum: Dictionary = s.summary()
	_eq(str(sum.get("platform", "")), "APSIS", "platform APSIS")
	_eq(int(sum.get("modules", 0)), 30, "模块 30≥24")
	_eq(str(sum.get("location", "")), "L4_ANVIL", "默认地点 L4_ANVIL")
	_eq(bool(sum.get("proposal", false)), true, "proposal")
	_eq(bool(sum.get("truth", true)), false, "truth false")
	var writes: Dictionary = sum.get("writes", {}) as Dictionary
	for k in ["ui", "world", "combat", "v15"]:
		_eq(bool(writes.get(k, true)), false, "不写 " + str(k))
	# categories
	for cat2 in CATS:
		_eq((s.options(str(cat2)) as Array).size(), int(CAT_COUNT[cat2]),
			"category 数量 " + str(cat2))
	_eq((s.options() as Array).size(), 30, "全部 options 30")
	# 基础槽位
	var slots: Dictionary = s.slots()
	var base: Dictionary = slots.get("base", {}) as Dictionary
	_eq(int(base.get("hull", 0)), 3, "base hull 3")
	_eq(int(base.get("sensor", 0)), 3, "base sensor 3")
	_eq(int(base.get("weapon", 0)), 3, "base weapon 3")
	_eq(int(base.get("defense", 0)), 3, "base defense 3")
	_eq(int(base.get("utility", 0)), 6, "base utility 6")
	_eq(int(base.get("dock", 0)), 2, "base dock 2")
	_eq(int(slots.get("total_base", 0)), 20, "总槽位 20")
	_eq(int(slots.get("total_free", 0)), 20, "空闲 20")
	# APSIS 基础 stats 来自 ShipCatalog
	var st: Dictionary = s.stats()
	var cur: Dictionary = st.get("current", {}) as Dictionary
	_near(float(cur.get("mass_t", 0.0)), 9000.0, 1.0e-6, "基础质量 9000t")
	_near(float(cur.get("dv_kmps", 0.0)), 3.15, 1.0e-6, "基础 Δv 3.15")
	_near(float(cur.get("accel_g", 0.0)), 0.02, 1.0e-6, "基础加速度 0.02g")
	_eq(int(cur.get("crew", 0)), 240, "基础编制 240")
	_near(float(cur.get("power_generation_kw", 0.0)), 400.0, 1.0e-6, "基础功率 400kW")
	_eq(int(st.get("dock_bays", 0)), 2, "2 维修坞")
	var cat2: Dictionary = cat.class_of("APSIS")
	_eq(str(cat2.get("class_id", "")), "OCUVF-APOGEE", "catalog APSIS 远地点级")
	# 默认 resources
	var res: Dictionary = st.get("resources", {}) as Dictionary
	_eq(int(res.get("credits", 0)), 200000, "默认 credits")
	_eq(int(res.get("materials", 0)), 500, "默认 materials")
	_ok(bool(s.check_contracts().get("ok", false)), "初始 contracts")
	_data_line("setup", "APSIS 远地点级 · 30 模块 · 20 槽位 · 2 维修坞 · 9000t/3.15/0.02g/240人/400kW")

# ═══════════════════════════════════════════════════════════════════
# 2. 模块字段/效果/成本
# ═══════════════════════════════════════════════════════════════════

func _test_modules() -> void:
	_section_begin("2 模块字段")
	var cat = _catalog()
	var s = _svc(cat)
	var mods: Array = s.options()
	var ids: Dictionary = {}
	for raw in mods:
		var m: Dictionary = raw
		var mid := str(m.get("module_id", ""))
		_ok(mid != "", "module_id 非空")
		_ok(not ids.has(mid), "module_id 唯一 " + mid)
		ids[mid] = true
		_ok(str(m.get("name", "")) != "", mid + " name")
		_ok(str(m.get("name_en", "")) != "", mid + " name_en")
		_ok(str(m.get("category", "")) in CATS, mid + " category")
		for f in ["slots", "mass_t", "power_kw", "dv_penalty_kmps",
				"accel_penalty_g", "crew", "cost_credits", "cost_materials",
				"cost_days"]:
			_ok(m.get(f) is int or m.get(f) is float, mid + " 数值 " + f)
		_ok(int(m.get("slots", 0)) >= 1, mid + " slots≥1")
		_ok(float(m.get("mass_t", 0.0)) >= 0.0, mid + " mass≥0")
		_ok(int(m.get("cost_credits", 0)) >= 0, mid + " credits≥0")
		_ok(int(m.get("cost_materials", 0)) >= 0, mid + " materials≥0")
		_ok(int(m.get("cost_days", 0)) >= 1, mid + " days≥1")
		_ok(str(m.get("availability", "")) != "", mid + " availability")
		_ok(m.get("location_tags") is Array and not (m.get("location_tags") as Array).is_empty(),
			mid + " location_tags")
		_ok(m.get("effects") is Dictionary, mid + " effects")
		_ok(m.get("conflicts") is Array, mid + " conflicts")
		_ok(m.get("requires") is Array, mid + " requires")
		_ok(bool(m.get("proposal", false)), mid + " proposal")
		_ok(str(m.get("source", "")) != "", mid + " source")
	# 示例模块关键字段
	var light: Dictionary = {}
	for raw2 in mods:
		if str((raw2 as Dictionary).get("module_id", "")) == "hull_armor_light":
			light = raw2
	_eq(int(light.get("slots", 0)), 1, "轻装甲 1 槽")
	_near(float(light.get("mass_t", 0.0)), 80.0, 1.0e-6, "轻装甲 80t")
	_eq(int(light.get("cost_credits", 0)), 12000, "轻装甲 12000cr")
	_eq(int(light.get("cost_materials", 0)), 40, "轻装甲 40 材")
	_eq(int(light.get("cost_days", 0)), 5, "轻装甲 5 天")
	# 类别字段覆盖
	var cat_count: Dictionary = {}
	for raw3 in mods:
		var c := str((raw3 as Dictionary).get("category", ""))
		cat_count[c] = int(cat_count.get(c, 0)) + 1
	for cat3 in CATS:
		_ok(int(cat_count.get(cat3, 0)) >= 2, "类别模块 ≥2 " + str(cat3))
	# 至少 24
	_ok(mods.size() >= 24, "模块总数≥24")
	# quote
	var q: Dictionary = s.quote("hull_armor_light")
	_eq(bool(q.get("ok", false)), true, "quote ok")
	var qc: Dictionary = q.get("costs", {}) as Dictionary
	_eq(int(qc.get("credits", 0)), 12000, "quote credits")
	_eq(int(qc.get("materials", 0)), 40, "quote materials")
	_eq(int(qc.get("days", 0)), 5, "quote days")
	_ok(q.get("stats_after_install") is Dictionary, "quote stats_after")
	_eq(str(s.quote("nope").get("reason", "")), "unknown_module", "quote 未知")
	_data_line("modules", "30 模块 / 6 类 · 字段/成本/效果/地点/冲突/requires 齐全 · quote")

# ═══════════════════════════════════════════════════════════════════
# 3. 槽位/quote/约束
# ═══════════════════════════════════════════════════════════════════

func _test_slots_quote() -> void:
	_section_begin("3 槽位/约束")
	var cat = _catalog()
	var s = _svc(cat)
	var ci: Dictionary = s.can_install("hull_armor_light")
	_eq(bool(ci.get("ok", false)), true, "轻装甲可装")
	_eq(str(ci.get("reason", "")), "", "can reason 空")
	var after: Dictionary = ci.get("stats_after", {}) as Dictionary
	_near(float(after.get("mass_t", 0.0)), 9080.0, 1.0e-6, "装后 9080t")
	_near(float(after.get("dv_kmps", 0.0)), 3.13, 1.0e-6, "装后 Δv 3.13")
	_near(float(after.get("accel_g", 0.0)), 0.019, 1.0e-6, "装后 accel 0.019")
	# 计划后槽位
	var ins: Dictionary = s.install("hull_armor_light")
	_eq(bool(ins.get("ok", false)), true, "install 轻装甲 ok")
	_eq(bool(ins.get("planned", false)), true, "install planned")
	var slots: Dictionary = s.slots()
	_eq(int((slots.get("planned", {}) as Dictionary).get("hull", 0)), 1, "planned hull 1")
	_eq(int((slots.get("free", {}) as Dictionary).get("hull", 0)), 2, "free hull 2")
	# 计划不影响 current stats
	_near(float(s.stats().get("mass_t", 0.0)), 9000.0, 1.0e-6, "计划不改 current")
	_near(float((s.stats().get("projected", {}) as Dictionary).get("mass_t", 0.0)),
		9080.0, 1.0e-6, "projected 9080")
	# 重复拒绝
	var dup: Dictionary = s.install("hull_armor_light")
	_eq(bool(dup.get("ok", true)), false, "重复安装拒绝")
	_eq(str(dup.get("reason", "")), "already_installed_or_planned", "重复 reason")
	# 未知拒绝
	_eq(str(s.can_install("nope").get("reason", "")), "unknown_module", "未知安装拒绝")
	# 成本引用
	var before: String = s.save_json()
	_ok(not bool(s.can_install("nope").get("ok", true)), "未知不改状态")
	_eq(s.save_json(), before, "未知不改状态 save")
	_data_line("slots/quote", "20 槽位/计划占用/quote stats_after · 重复/未知原子拒绝")

# ═══════════════════════════════════════════════════════════════════
# 4. install/commit/tick/stats
# ═══════════════════════════════════════════════════════════════════

func _test_install_commit_tick() -> void:
	_section_begin("4 安装/提交/时间")
	var cat = _catalog()
	var s = _svc(cat)
	var r1: Dictionary = s.install("sensor_radar_mk2")
	_eq(bool(r1.get("ok", false)), true, "install radar")
	var r2: Dictionary = s.install("sensor_optical_ir")
	_eq(bool(r2.get("ok", true)), false, "wrong location optical 拒绝")
	_eq(str(r2.get("reason", "")), "wrong_location", "wrong location reason")
	# 在 L1 可安装
	var s_l1 = _svc(cat, {"location": "L1_MERIDIAN"})
	_eq(bool(s_l1.install("sensor_optical_ir").get("ok", false)), true,
		"L1 可安装光学")
	# 提交
	var res_before: Dictionary = s.resources.duplicate()
	var cm: Dictionary = s.commit()
	_eq(bool(cm.get("ok", false)), true, "commit ok")
	_eq((cm.get("committed", []) as Array).size(), 1, "commit 1")
	_eq(s.planned.size(), 0, "commit 清 planned")
	_eq(s.queue().size(), 1, "queue 1")
	_eq(int(s.resources.get("credits", 0)), int(res_before.get("credits", 0)) - 16000,
		"commit 扣 credits")
	_eq(int(s.resources.get("materials", 0)), int(res_before.get("materials", 0)) - 25,
		"commit 扣 materials")
	var job: Dictionary = (s.queue()[0] as Dictionary)
	_eq(str(job.get("module_id", "")), "sensor_radar_mk2", "queue module")
	_eq(int(job.get("days_remaining", 0)), 6, "queue 6 天")
	# tick 未完成
	var tk1: Dictionary = s.tick(2.0)
	_eq((tk1.get("completed", []) as Array).size(), 0, "tick2 未完成")
	_eq(int((s.queue()[0] as Dictionary).get("days_remaining", 0)), 4, "剩 4 天")
	_near(float(s.stats().get("current", {}).get("mass_t", 0.0)), 9000.0, 1.0e-6,
		"未完成 current 基础")
	# tick 完成
	var tk2: Dictionary = s.tick(4.0)
	_eq((tk2.get("completed", []) as Array).size(), 1, "tick4 完成")
	_eq(s.queue().size(), 0, "queue 清空")
	_eq(s.installed.size(), 1, "installed 1")
	_eq(float(s.stats().get("t_days", -1.0)), 6.0, "t_days 6")
	var cur: Dictionary = s.stats().get("current", {}) as Dictionary
	_near(float(cur.get("mass_t", 0.0)), 9020.0, 1.0e-6, "完成 mass 9020")
	_near(float(cur.get("power_used_kw", 0.0)), 40.0, 1.0e-6, "完成 power used 40")
	_near(float(cur.get("power_headroom_kw", 0.0)), 360.0, 1.0e-6, "headroom 360")
	_ok(float((cur.get("effects", {}) as Dictionary).get("sensor_range", 0.0)) > 0.0,
		"effects sensor_range")
	_ok(bool(s.check_contracts().get("ok", false)), "commit tick contracts")
	# 先计划多个再提交
	var s2 = _svc(cat)
	for mid in ["hull_armor_light", "defense_pd_battery", "utility_radiator"]:
		_ok(bool(s2.install(str(mid)).get("ok", false)), "多计划安装 " + str(mid))
	var cm2: Dictionary = s2.commit()
	_eq(bool(cm2.get("ok", false)), true, "多计划 commit")
	_eq((s2.queue() as Array).size(), 3, "多计划 queue 3")
	var t_all: Dictionary = s2.tick(100.0)
	_eq((t_all.get("completed", []) as Array).size(), 3, "多计划全部完成")
	_eq(s2.installed.size(), 3, "installed 3")
	# immediate 安装：入队但未完成
	var s3 = _svc(cat)
	var imm: Dictionary = s3.install_now("utility_fuel_tank")
	_eq(bool(imm.get("ok", false)), true, "install_now ok")
	_eq(s3.queue().size(), 1, "install_now 入队")
	_eq(s3.installed.size(), 0, "install_now 未完成")
	_data_line("install/commit/tick", "计划→commit 扣资源/queue→tick 完成派生 stats · 多计划 · immediate")

# ═══════════════════════════════════════════════════════════════════
# 5. 约束：槽位/质量/功率/成本/冲突/依赖/地点
# ═══════════════════════════════════════════════════════════════════

func _test_constraints() -> void:
	_section_begin("5 约束")
	var cat = _catalog()
	# 槽位
	var s = _svc(cat)
	_ok(bool(s.install("hull_armor_light").get("ok", false)), "槽位测试 light")
	_ok(bool(s.install("hull_armor_heavy").get("ok", false)), "槽位测试 heavy")
	var no_slot: Dictionary = s.install("hull_ablative")
	_eq(str(no_slot.get("reason", "")), "no_slot", "hull 槽位满")
	var before: String = s.save_json()
	_ok(not bool(no_slot.get("ok", true)), "槽位失败不改")
	_eq(s.save_json(), before, "槽位失败状态不变")
	# 成本
	var poor = _svc(cat, {"credits": 1000, "materials": 10})
	_eq(str(poor.can_install("hull_armor_light").get("reason", "")),
		"insufficient_credits", "credits 不足")
	# 依赖
	var dep = _svc(cat)
	_eq(str(dep.can_install("sensor_fire_control").get("reason", "")),
		"missing_requirement", "缺 radar 依赖")
	_ok(bool(dep.install("sensor_radar_mk2").get("ok", false)), "先装 radar")
	_ok(bool(dep.install("sensor_fire_control").get("ok", false)), "依赖满足可装")
	# 冲突
	var conf = _svc(cat, {"credits": 200000, "materials": 500, "location": "L4_ANVIL"})
	_ok(bool(conf.install("utility_reactor").get("ok", false)), "reactor")
	_ok(bool(conf.install("weapon_missile_bay").get("ok", false)), "missile bay")
	var conflict: Dictionary = conf.can_install("weapon_spinal")
	_eq(str(conflict.get("reason", "")), "conflict", "spine 与 missile 冲突")
	# 地点
	var earth = _svc(cat, {"location": "EARTH"})
	_eq(str(earth.can_install("sensor_optical_ir").get("ok", true)), "true",
		"EARTH 可装 optical")
	_eq(str(earth.can_install("hull_armor_heavy").get("reason", "")),
		"wrong_location", "EARTH 不可装 L4 armor")
	# 地点通配
	_eq(str(_svc(cat, {"location": "L2_KARMAN"}).can_install("utility_fuel_tank").get("ok", true)),
		"true", "通配地点可装")
	# availability
	var opt = _svc(cat)
	var spinal_quote: Dictionary = opt.quote("weapon_spinal")
	_eq(int((spinal_quote.get("costs", {}) as Dictionary).get("credits", 0)),
		85000, "spine cost")
	# 功率上限：把平台基础发电降到 100 kW，railgun(120) 即超功率
	var opts_pw: Dictionary = opt.options_data.duplicate(true)
	var plat_pw: Dictionary = (opts_pw.get("platforms", {}) as Dictionary).get("APSIS", {}) as Dictionary
	var base_pw: Dictionary = plat_pw.get("base", {}) as Dictionary
	base_pw["power_kw"] = 100.0
	plat_pw["base"] = base_pw
	opts_pw["platforms"] = {"APSIS": plat_pw}
	var pw = _svc(cat)
	_ok(bool(pw.setup(cat, opts_pw, {})), "低功率平台 setup")
	var pw_bad: Dictionary = pw.can_install("weapon_railgun_mk2")
	_eq(str(pw_bad.get("reason", "")), "power_limit", "功率不足")
	# 质量上限（用候选 options 降低上限）
	var opts: Dictionary = opt.options_data.duplicate(true)
	var plat: Dictionary = (opts.get("platforms", {}) as Dictionary).get("APSIS", {}) as Dictionary
	var base: Dictionary = plat.get("base", {}) as Dictionary
	base["max_mass_t"] = 9100.0
	plat["base"] = base
	opts["platforms"] = {"APSIS": plat}
	var mass_s = _svc(cat)
	mass_s.ready = false
	_ok(bool(mass_s.setup(cat, opts, {})), "自定义 max_mass setup")
	_ok(bool(mass_s.install("hull_armor_light").get("ok", false)), "9080<9100 可装")
	var mass_bad: Dictionary = mass_s.install("hull_ablative")
	_eq(str(mass_bad.get("reason", "")), "mass_limit", "超质量上限")
	_data_line("constraints", "槽位/成本/依赖/冲突/地点/availability/功率/质量上限 · 失败原子")

# ═══════════════════════════════════════════════════════════════════
# 6. remove / save / load / reset / 错误
# ═══════════════════════════════════════════════════════════════════

func _test_remove_save_errors() -> void:
	_section_begin("6 移除/存档")
	var cat = _catalog()
	var s = _svc(cat)
	# planned remove
	_ok(bool(s.install("hull_armor_light").get("ok", false)), "安装 planned")
	var rem1: Dictionary = s.remove("hull_armor_light")
	_eq(bool(rem1.get("ok", false)), true, "remove planned ok")
	_eq(str(rem1.get("where", "")), "planned", "remove planned where")
	_eq(s.planned.size(), 0, "planned 清空")
	# installed remove
	_ok(bool(s.install_now("utility_fuel_tank").get("ok", false)), "immediate 安装")
	s.tick(10.0)
	_eq(s.installed.size(), 1, "安装完成 1")
	var rem2: Dictionary = s.remove("utility_fuel_tank")
	_eq(bool(rem2.get("ok", false)), true, "remove installed ok")
	_eq(str(rem2.get("where", "")), "installed", "remove installed where")
	_eq(s.installed.size(), 0, "installed 清空")
	_eq(str(s.remove("nope").get("reason", "")), "not_installed", "remove 未知")
	# 依赖移除
	var dep = _svc(cat, {"location": "L1_MERIDIAN"})
	_ok(bool(dep.install("utility_command").get("ok", false)), "依赖 command 安装")
	_ok(bool(dep.install("dock_command_bridge").get("ok", false)), "依赖 bridge 安装")
	dep.commit()
	dep.tick(100.0)
	_eq(dep.installed.size(), 2, "依赖两模块完成")
	var rem3: Dictionary = dep.remove("utility_command")
	_eq(bool(rem3.get("ok", true)), false, "被依赖模块不可移除")
	_eq(str(rem3.get("reason", "")), "required_by_installed", "依赖移除 reason")
	# 存档：planned+queue+resources
	var s2 = _svc(cat)
	s2.install("hull_armor_light")
	s2.commit()
	s2.install("sensor_radar_mk2")
	var saved: Dictionary = s2.save_state()
	_eq(str(saved.get("schema", "")), "v17.refit_save.v1", "save schema")
	var s3 = _svc(cat)
	var lr: Dictionary = s3.load_state(saved)
	_eq(bool(lr.get("ok", false)), true, "load ok")
	_eq(s3.installed.size(), 0, "load installed 0")
	_eq(s3.queue().size(), 1, "load queue 1")
	_eq(s3.planned.size(), 1, "load planned 1")
	_eq(s3.save_state(), saved, "save/load 一致")
	_eq(s3.stats().get("t_days"), s2.stats().get("t_days"), "load t 一致")
	# 字符串存档
	var s4 = _svc(cat)
	_eq(bool(s4.load_state(s2.save_json()).get("ok", false)), true, "load JSON 字符串")
	# 非法存档原子
	var bad: Dictionary = saved.duplicate(true)
	bad["installed"] = ["nope"]
	var s5 = _svc(cat)
	var before: String = s5.save_json()
	_eq(bool(s5.load_state(bad).get("ok", true)), false, "非法存档拒绝")
	_eq(s5.save_json(), before, "非法存档不改状态")
	# version/schema
	var bad2: Dictionary = saved.duplicate(true)
	bad2["version"] = "9.9.9"
	_eq(bool(s5.load_state(bad2).get("ok", true)), false, "版本不支持拒绝")
	# reset
	var reset: Dictionary = s2.reset()
	_eq(bool(reset.get("ok", false)), true, "reset ok")
	_eq(s2.installed.size(), 0, "reset installed")
	_eq(s2.queue().size(), 0, "reset queue")
	_eq(s2.resources, {"credits": 200000, "materials": 500}, "reset resources")
	_eq(float(s2.t_days), 0.0, "reset t")
	# 坏 options
	var badopt = RefitService.new(cat, {"schema": "bad"})
	_ok(not bool(badopt.ready), "坏 options 拒绝")
	var badopt2 = RefitService.new(cat, {"schema": "v17.refit_options.v1",
		"modules": []})
	_ok(not bool(badopt2.ready), "模块不足 24 拒绝")
	_data_line("save/remove", "planned/installed/queue 移除 · 依赖保护 · save/load 字符串/dict · 非法/坏 options 原子")

# ═══════════════════════════════════════════════════════════════════
# 7. 确定性/契约
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("7 确定性")
	var cat = _catalog()
	var a = _svc(cat)
	var b = _svc(cat)
	for s in [a, b]:
		s.install("hull_armor_light")
		s.install("sensor_radar_mk2")
		s.commit()
		s.tick(100.0)
	_eq(a.save_json(), b.save_json(), "同操作 save 一致")
	_eq(a.stats(), b.stats(), "同操作 stats 一致")
	_eq(a.summary(), b.summary(), "同操作 summary 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "契约 ok")
	_eq(a.to_dict().get("schema"), "v17.refit_service.v1", "to_dict schema")
	_ok(JSON.parse_string(a.save_json()) is Dictionary, "save JSON 可解析")
	# 20 模块长流程确定性
	var c = _svc(cat)
	var d = _svc(cat)
	for mid in ["hull_armor_light", "hull_armor_heavy", "sensor_radar_mk2",
			"sensor_optical_ir", "weapon_pd_ciws", "defense_pd_battery",
			"utility_radiator", "utility_command", "utility_stealth"]:
		for sv in [c, d]:
			sv.install(str(mid))
	for sv2 in [c, d]:
		sv2.commit()
		sv2.tick(100.0)
	_eq(c.save_json(), d.save_json(), "长流程 save 一致")
	_ok(c.installed.size() >= 1, "长流程安装数")
	_data_line("determinism", "同操作 save/stats/summary 一致 · contracts · JSON · 长流程")
