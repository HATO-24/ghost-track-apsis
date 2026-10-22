extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段5F 最小 probe：FleetRefitService + FleetFormationService
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/fleet_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const FleetRefitService := preload("res://scripts/core/fleet_refit_service.gd")
const FleetFormationService := preload("res://scripts/core/fleet_formation.gd")
const ShipCatalog := preload("res://scripts/core/ship_catalog.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

const CLASS_IDS := ["OCUVF-APOGEE", "OCUVF-PALLET-5C", "OCUVF-HEMATITE-6C",
	"OCUVF-GANTRY-3M", "OCUVF-MOONPORT-4", "OCUVF-SAFEHARBOR-1",
	"OCUVF-WINCH-2", "OCUVF-ARIA-1"]
const SLOT_IDS := ["command", "screen", "gun", "missile", "logistics", "relay",
	"tug", "shuttle"]
const EXISTING := ["APSIS", "HARMATTAN", "FERRY", "WATCHTOWER", "DEEPWELL"]

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE5F PROBE · FleetRefit / FleetFormation")
	print("════════════════════════════════════════════════════════════")
	_test_roster()
	_test_refit_base()
	_test_refit_multi()
	_test_formation_base()
	_test_formation_constraints()
	_test_save_errors()
	_test_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 FLEET PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 FLEET PROBE FAILED")
		quit(1)
	else:
		print("V17 FLEET PROBE OK")
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

func _refit(cat) -> Object:
	var f = FleetRefitService.new(cat)
	_ok(bool(f.ready), "FleetRefit ready", str(f.errors))
	return f

func _formation(cat, refit = null) -> Object:
	var f = FleetFormationService.new(cat, null, {"refit": refit} if refit != null else {})
	_ok(bool(f.ready), "FleetFormation ready", str(f.errors))
	return f

func _ship(f, sid: String) -> Dictionary:
	for raw in f.ships:
		if str((raw as Dictionary).get("ship_id", "")) == sid:
			return raw
	return {}

# ═══════════════════════════════════════════════════════════════════
# 1. roster 内容
# ═══════════════════════════════════════════════════════════════════

func _test_roster() -> void:
	_section_begin("1 roster")
	var cat = _catalog()
	var f = _refit(cat)
	var roster: Dictionary = f.roster
	_eq(str(roster.get("schema", "")), "v17.fleet_roster.v1", "roster schema")
	_eq(bool(roster.get("proposal", false)), true, "roster proposal")
	_eq((roster.get("ships", []) as Array).size(), 13, "13 艘（5+8 预备）")
	_eq((roster.get("slots", {}) as Dictionary).size(), 8, "8 编队槽位")
	_eq((roster.get("class_refit_policies", {}) as Dictionary).size(), 8, "8 class 改装 policy")
	var class_counts: Dictionary = {}
	var ids: Dictionary = {}
	for raw in (roster.get("ships", []) as Array):
		var sh: Dictionary = raw
		var sid := str(sh.get("ship_id", ""))
		_ok(sid != "", "ship_id 非空")
		_ok(not ids.has(sid), "ship_id 唯一 " + sid)
		ids[sid] = true
		for fld in ["ship_id", "name", "class_id", "role", "status", "assigned_slot", "refit_state"]:
			_ok(sh.has(fld), sid + " 字段 " + str(fld))
		_ok(str(sh.get("name", "")) != "", sid + " name")
		_ok(str(sh.get("class_id", "")) in CLASS_IDS, sid + " friendly class")
		_ok(sh.get("formation_roles") is Array and not (sh.get("formation_roles") as Array).is_empty(),
			sid + " formation_roles")
		_ok(sh.get("fuel_t") is int or sh.get("fuel_t") is float, sid + " fuel_t")
		_ok(sh.get("repair_slots_required") is int or sh.get("repair_slots_required") is float,
			sid + " repair_slots")
		class_counts[str(sh.get("class_id", ""))] = int(class_counts.get(str(sh.get("class_id", "")), 0)) + 1
	for cid in CLASS_IDS:
		_ok(class_counts.has(cid), "class 覆盖 " + cid)
		_ok(int(class_counts.get(cid, 0)) >= 1, "class 舰只 " + cid)
	for sid2 in EXISTING:
		_ok(ids.has(sid2), "既有船 " + sid2)
	_ok(ids.size() == 13, "13 unique ship ids")
	# 槽位定义
	for sk in SLOT_IDS:
		_ok((roster.get("slots", {}) as Dictionary).has(sk), "slot " + str(sk))
		var sd: Dictionary = (roster.get("slots", {}) as Dictionary).get(sk, {})
		_ok(int(sd.get("cap", 0)) >= 1, "slot cap " + str(sk))
		_ok(sd.get("roles") is Array, "slot roles " + str(sk))
	var cmd: Dictionary = (roster.get("slots", {}) as Dictionary).get("command", {})
	_eq(bool(cmd.get("required", false)), true, "command required")
	_eq(int(cmd.get("cap", 0)), 1, "command cap1")
	# limits
	var lim: Dictionary = roster.get("limits", {}) as Dictionary
	for lk in ["max_ships", "max_mass_t", "min_total_dv_kmps", "max_total_dv_kmps",
			"max_crew", "fuel_capacity_t", "repair_dock_capacity"]:
		_ok(lim.get(lk) is int or lim.get(lk) is float, "limit " + str(lk))
	_eq(int(lim.get("max_ships", 0)), 13, "max_ships 13")
	# policies
	for pcid in CLASS_IDS:
		_ok((roster.get("class_refit_policies", {}) as Dictionary).has(pcid), "policy " + pcid)
		var pol: Dictionary = (roster.get("class_refit_policies", {}) as Dictionary).get(pcid, {})
		_ok(pol.get("allowed_categories") is Array, pcid + " allowed")
		_ok(pol.get("slots") is Dictionary, pcid + " slots")
		for cat2 in ["hull", "sensor", "weapon", "defense", "utility", "dock"]:
			_ok((pol.get("slots", {}) as Dictionary).has(cat2), pcid + " slot " + str(cat2))
	_data_line("roster", "13 艘/8 型覆盖/8 槽/8 policies · 现有5+预备8 · command required cap1")

# ═══════════════════════════════════════════════════════════════════
# 2. FleetRefit 基础
# ═══════════════════════════════════════════════════════════════════

func _test_refit_base() -> void:
	_section_begin("2 FleetRefit 基础")
	var cat = _catalog()
	var f = _refit(cat)
	_eq(f.ships.size(), 13, "13 ships")
	_eq(f.services.size(), 13, "13 services")
	_eq(str(f.selected()), "APSIS", "默认选 APSIS")
	_eq(int(f.resources.get("credits", 0)), 300000, "共享 credits")
	_eq(int(f.resources.get("materials", 0)), 1000, "共享 materials")
	var pols: Dictionary = f.policies
	for sid in EXISTING:
		var st: Dictionary = f.stats(sid)
		_ok(not st.is_empty(), "stats " + sid)
		var cur: Dictionary = st.get("current", {}) as Dictionary
		var cls: Dictionary = cat.class_of(str(_ship(f, sid).get("class_id", "")))
		_near(float(cur.get("mass_t", 0.0)), float(cls.get("displacement_t", 0.0)), 0.001,
			sid + " 基础 mass")
		_near(float(cur.get("dv_kmps", 0.0)), float(cls.get("dv_kmps", 0.0)), 0.001,
			sid + " 基础 dv")
		_eq(int(cur.get("crew", 0)), int(cls.get("crew", 0)), sid + " 基础 crew")
		var pol: Dictionary = pols.get(str(_ship(f, sid).get("class_id", "")), {}) as Dictionary
		var base_slots: Dictionary = (st.get("slots", {}) as Dictionary).get("base", {}) as Dictionary
		for cat2 in ["hull", "sensor", "weapon", "defense", "utility", "dock"]:
			_eq(int(base_slots.get(cat2, -1)), int((pol.get("slots", {}) as Dictionary).get(cat2, -2)),
				sid + " slot " + str(cat2))
		_ok(f.options(sid).size() > 0, sid + " options")
	# 选择切换
	_eq(bool(f.select_ship("HARMATTAN").get("ok", false)), true, "select HARMATTAN")
	_eq(str(f.selected()), "HARMATTAN", "selected HARMATTAN")
	_eq(str(f.select_ship("NOPE").get("reason", "")), "unknown_ship", "未知 select")
	# quote/可用性
	_ok(bool(f.quote("APSIS", "hull_armor_light").get("ok", false)), "APSIS quote armor")
	_ok(bool(f.quote("HARMATTAN", "sensor_radar_mk2").get("ok", false)), "HARMATTAN quote radar")
	_eq(str(f.quote("MISSIVE", "hull_armor_light").get("reason", "")),
		"module_not_available_for_class", "MISSIVE 禁用 hull 模块")
	var mopts: Array = f.options("MISSIVE")
	_eq(mopts.size(), 11, "MISSIVE options 11")
	var aopts: Array = f.options("APSIS")
	_eq(aopts.size(), 24, "APSIS options 24")
	_eq(f.options("NOPE").size(), 0, "未知 ship options 空")
	_data_line("refit-base", "13 独立服务 · 默认 APSIS · 共享 300000cr/1000材 · 按 class 过滤模块/槽位")

# ═══════════════════════════════════════════════════════════════════
# 3. 多舰改装/共享资源
# ═══════════════════════════════════════════════════════════════════

func _test_refit_multi() -> void:
	_section_begin("3 多舰改装")
	var cat = _catalog()
	var f = _refit(cat)
	# planned 不扣共享资源
	_ok(bool(f.install("APSIS", "hull_armor_light").get("ok", false)), "APSIS install")
	_ok(bool(f.install("HARMATTAN", "sensor_radar_mk2").get("ok", false)), "HARMATTAN install")
	_eq(int(f.resources.get("credits", 0)), 300000, "planned 不扣 credits")
	_eq(int((f.stats("APSIS").get("installed", []) as Array).size()), 0, "planned 未安装")
	_eq((f.stats("HARMATTAN").get("planned", []) as Array).size(), 1, "HARMATTAN planned")
	# commit APSIS
	var ca: Dictionary = f.commit("APSIS")
	_eq(bool(ca.get("ok", false)), true, "APSIS commit")
	_eq(int(f.resources.get("credits", 0)), 288000, "APSIS 扣 12000cr")
	_eq(int(f.resources.get("materials", 0)), 960, "APSIS 扣 40材")
	# HARMATTAN 独立
	var cb: Dictionary = f.commit("HARMATTAN")
	_eq(bool(cb.get("ok", false)), true, "HARMATTAN commit")
	_eq(int(f.resources.get("credits", 0)), 272000, "共享再扣 16000cr")
	_eq(int(f.resources.get("materials", 0)), 935, "共享再扣 25材")
	_eq((f.stats("APSIS").get("queue", []) as Array).size(), 1, "APSIS queue")
	_eq((f.stats("HARMATTAN").get("queue", []) as Array).size(), 1, "HARMATTAN queue")
	# tick 全部
	var tk: Dictionary = f.tick(10.0)
	_eq(bool(tk.get("ok", false)), true, "fleet tick")
	_eq((tk.get("completed", []) as Array).size(), 2, "fleet tick completed 2")
	_near(float((f.stats("APSIS").get("current", {}) as Dictionary).get("mass_t", 0.0)),
		9080.0, 0.001, "APSIS 改装 mass 9080")
	_near(float((f.stats("HARMATTAN").get("current", {}) as Dictionary).get("mass_t", 0.0)),
		320.0, 0.001, "HARMATTAN 改装 mass 320")
	_eq((f.stats("APSIS").get("installed", []) as Array).size(), 1, "APSIS installed 1")
	_eq((f.stats("HARMATTAN").get("installed", []) as Array).size(), 1, "HARMATTAN installed 1")
	# 每舰独立 save_state
	_ok(not f.refit_state("APSIS").is_empty(), "APSIS refit state")
	_ok(not f.refit_state("HARMATTAN").is_empty(), "HARMATTAN refit state")
	_eq((f.refit_state("MISSIVE").get("installed", []) as Array).size(), 0, "MISSIVE 独立空")
	# 非法/禁用原子
	var before: String = f.save_json()
	_eq(str(f.install("MISSIVE", "hull_armor_light").get("reason", "")),
		"module_not_available_for_class", "MISSIVE 禁用")
	_eq(str(f.install("NOPE", "sensor_mast").get("reason", "")), "unknown_ship", "未知舰")
	var bad_install: Dictionary = f.install("APSIS", "weapon_spinal")
	_ok(not bool(bad_install.get("ok", true)), "约束失败拒绝", str(bad_install.get("reason", "")))
	_eq(f.save_json(), before, "非法不改状态")
	# commit_all
	var c_all: Dictionary = f.commit_all()
	_eq(bool(c_all.get("ok", false)), true, "commit_all ok")
	# 各舰 stats 不串
	_eq((f.all_stats() as Array).size(), 13, "all_stats 13")
	_data_line("refit-multi", "计划不扣共享 · 逐舰 commit 扣共享 · tick 全部 · 各舰独立 mass/queue")

# ═══════════════════════════════════════════════════════════════════
# 4. Formation 基础
# ═══════════════════════════════════════════════════════════════════

func _test_formation_base() -> void:
	_section_begin("4 Formation 基础")
	var cat = _catalog()
	var ff = _formation(cat)
	_eq(ff.ships.size(), 13, "13 ships")
	_eq(ff.assignments.size(), 5, "初始 5 编组")
	_eq(bool(ff.validate().get("ok", false)), true, "初始 validate ok",
		str(ff.validate().get("errors", [])))
	var sl: Dictionary = ff.slots()
	_eq(int(sl.get("total_cap", 0)), 19, "总槽位 19")
	var sdefs: Dictionary = sl.get("slots", {}) as Dictionary
	_eq(int((sdefs.get("command", {}) as Dictionary).get("used", 0)), 1, "command used1")
	_eq(int((sdefs.get("screen", {}) as Dictionary).get("used", 0)), 1, "screen used1")
	_eq(int((sdefs.get("gun", {}) as Dictionary).get("used", 0)), 1, "gun used1")
	_eq(int((sdefs.get("logistics", {}) as Dictionary).get("used", 0)), 1, "logistics used1")
	_eq(int((sdefs.get("relay", {}) as Dictionary).get("used", 0)), 1, "relay used1")
	var st: Dictionary = ff.stats()
	_eq(int((st.get("totals", {}) as Dictionary).get("ships", 0)), 5, "totals ships5")
	_near(float((st.get("totals", {}) as Dictionary).get("mass_t", 0.0)), 13000.0, 0.001,
		"初始总 mass 13000")
	_near(float((st.get("totals", {}) as Dictionary).get("dv_kmps", 0.0)), 21.44, 0.001,
		"初始总 dv 21.44")
	_eq(int((st.get("totals", {}) as Dictionary).get("crew", 0)), 368, "初始 crew 368")
	_near(float((st.get("totals", {}) as Dictionary).get("fuel_t", 0.0)), 8900.0, 0.001,
		"初始 fuel 8900")
	_eq(int((st.get("totals", {}) as Dictionary).get("repair_slots_required", 0)), 1,
		"初始维修槽 1")
	# 自由 add
	_ok(bool(ff.assign("VESUVIUS", "missile").get("ok", false)), "assign VESUVIUS missile")
	_ok(bool(ff.assign("BOLLARD", "tug").get("ok", false)), "assign BOLLARD tug")
	_ok(bool(ff.assign("MISSIVE", "shuttle").get("ok", false)), "assign MISSIVE shuttle")
	_eq(ff.assignments.size(), 8, "assign 后 8")
	_ok(bool(ff.validate().get("ok", false)), "assign 后 validate")
	# 重复
	_eq(str(ff.assign("VESUVIUS", "missile").get("reason", "")), "already_assigned",
		"重复 assign 拒绝")
	# 角色不兼容
	_eq(str(ff.assign("LEE_SHORE", "gun").get("reason", "")), "role_mismatch",
		"角色不兼容")
	# move
	_ok(bool(ff.move("MISSIVE", "shuttle").get("ok", false)), "move 同槽 no-op")
	_ok(bool(ff.move("HARMATTAN", "relay").get("ok", false)), "move screen→relay")
	_eq(str((ff.assignments.get("HARMATTAN", "") as String)), "relay", "HARMATTAN relay")
	_eq(str(ff.move("MISSIVE", "gun").get("reason", "")), "role_mismatch", "非法 move")
	# unassign
	_ok(bool(ff.unassign("MISSIVE").get("ok", false)), "unassign MISSIVE")
	_eq(str(ff.unassign("MISSIVE").get("reason", "")), "not_assigned", "重复 unassign")
	# 槽位满
	var capff = _formation(cat)
	capff.slot_defs["screen"] = (capff.slot_defs["screen"] as Dictionary).duplicate()
	capff.slot_defs["screen"]["cap"] = 1
	_eq(str(capff.assign("LEE_SHORE", "screen").get("reason", "")), "slot_full",
		"screen 槽满拒绝")
	# command 必需
	var reqff = _formation(cat)
	_ok(bool(reqff.unassign("APSIS").get("ok", false)), "unassign command")
	_eq(bool(reqff.validate().get("ok", true)), false, "无 command validate fail")
	_ok(bool(reqff.assign("PERIGEE", "command").get("ok", false)), "reserve command 接替")
	_eq(bool(reqff.validate().get("ok", false)), true, "command 接替后 valid")
	# 统计更新
	var st2: Dictionary = ff.stats()
	_eq(int(st2.get("assigned", 0)), 7, "assigned 7")
	_ok(int(st2.get("unassigned", 0)) == 6, "unassigned 6")
	_data_line("formation", "13 艘 · 8 槽/总19 · 初始5 · 自由 assign/move/unassign · command 必需/角色/上限")

# ═══════════════════════════════════════════════════════════════════
# 5. Formation 约束
# ═══════════════════════════════════════════════════════════════════

func _test_formation_constraints() -> void:
	_section_begin("5 Formation 约束")
	var cat = _catalog()
	var fr = _refit(cat)
	var base: Dictionary = fr.roster.duplicate(true)
	# mass
	var r_mass: Dictionary = base.duplicate(true)
	(r_mass.get("limits", {}) as Dictionary)["max_mass_t"] = 14000.0
	var ff_mass = FleetFormationService.new(cat, r_mass)
	_ok(bool(ff_mass.ready), "mass 约束 setup", str(ff_mass.errors))
	_eq(str(ff_mass.assign("SPRINGHEAD", "logistics").get("reason", "")), "constraint_failed",
		"总质量超限拒绝")
	# fuel
	var r_fuel: Dictionary = base.duplicate(true)
	(r_fuel.get("limits", {}) as Dictionary)["fuel_capacity_t"] = 9000.0
	var ff_fuel = FleetFormationService.new(cat, r_fuel)
	_eq(str(ff_fuel.assign("BEACON", "relay").get("reason", "")), "constraint_failed",
		"燃料超限拒绝")
	# crew
	var r_crew: Dictionary = base.duplicate(true)
	(r_crew.get("limits", {}) as Dictionary)["max_crew"] = 380
	var ff_crew = FleetFormationService.new(cat, r_crew)
	_eq(str(ff_crew.assign("SPRINGHEAD", "logistics").get("reason", "")), "constraint_failed",
		"编制超限拒绝")
	# dv 下限
	var r_dv: Dictionary = base.duplicate(true)
	(r_dv.get("limits", {}) as Dictionary)["min_total_dv_kmps"] = 100.0
	var ff_dv = FleetFormationService.new(cat, r_dv)
	_eq(str(ff_dv.assign("BOLLARD", "tug").get("reason", "")), "constraint_failed",
		"总 Δv 不足拒绝")
	# repair docks
	var r_rep: Dictionary = base.duplicate(true)
	(r_rep.get("limits", {}) as Dictionary)["repair_dock_capacity"] = 0
	var ff_rep = FleetFormationService.new(cat, r_rep)
	_eq(str(ff_rep.assign("BOLLARD", "tug").get("reason", "")), "constraint_failed",
		"维修坞容量拒绝")
	# 链接 refit：APSIS 改装后 mass 变化
	_ok(bool(fr.install("APSIS", "hull_armor_light").get("ok", false)), "refit APSIS plan")
	fr.commit("APSIS"); fr.tick(10.0)
	var ff_link = _formation(cat, fr)
	_eq(bool(ff_link.stats().get("refit_linked", false)), true, "formation 链接 refit")
	_near(float((ff_link.stats().get("totals", {}) as Dictionary).get("mass_t", 0.0)),
		13080.0, 0.001, "链接后总 mass 13080")
	_ok(bool(ff_link.validate().get("ok", false)), "链接后 valid")
	# 非法 roster / 状态
	var bad = FleetFormationService.new(cat, {"schema": "bad"})
	_ok(not bool(bad.ready), "坏 roster 拒绝")
	# save/load 状态
	var saved: Dictionary = ff_link.save_state()
	var ff2 = _formation(cat)
	var lr: Dictionary = ff2.load_state(saved)
	_eq(bool(lr.get("ok", false)), true, "formation load")
	_eq(ff2.assignments, ff_link.assignments, "formation assignments 一致")
	_eq(ff2.save_state(), saved, "formation save/load 一致")
	# 非法 assignment 存档
	var bad_save: Dictionary = {"schema": "v17.fleet_formation_save.v1",
		"version": "1.0.0", "assignments": {"NOPE": "command"}}
	_eq(str(ff2.load_state(bad_save).get("reason", "")), "unknown_ship",
		"非法 assignment 拒绝")
	# reset
	var rst: Dictionary = ff2.reset()
	_eq(bool(rst.get("ok", false)), true, "formation reset")
	_eq(ff2.assignments.size(), 5, "reset 回初始 5")
	_data_line("constraints", "mass/fuel/crew/dv/repair 拒绝 · refit 链接 stats · 存档/非法/回滚")

# ═══════════════════════════════════════════════════════════════════
# 6. FleetRefit 存档/错误
# ═══════════════════════════════════════════════════════════════════

func _test_save_errors() -> void:
	_section_begin("6 存档/错误")
	var cat = _catalog()
	var f = _refit(cat)
	f.install("APSIS", "hull_armor_light")
	f.install("HARMATTAN", "sensor_radar_mk2")
	f.commit("APSIS"); f.commit("HARMATTAN"); f.tick(10.0)
	f.install("FERRY", "weapon_pd_ciws")
	var saved: Dictionary = f.save_state()
	_eq(str(saved.get("schema", "")), "v17.fleet_refit_save.v1", "fleet save schema")
	var f2 = _refit(cat)
	var lr: Dictionary = f2.load_state(saved)
	_eq(bool(lr.get("ok", false)), true, "fleet load ok")
	_eq(f2.save_json(), f.save_json(), "fleet save/load 一致")
	_eq(f2.resources, f.resources, "fleet 共享资源一致")
	_eq(f2.stats("APSIS").get("current"), f.stats("APSIS").get("current"),
		"fleet APSIS stats 一致")
	_eq((f2.stats("FERRY").get("planned", []) as Array).size(), 1, "fleet planned 恢复")
	# 字符串加载
	var f3 = _refit(cat)
	_eq(bool(f3.load_state(f.save_json()).get("ok", false)), true, "fleet load JSON string")
	# 非法
	var bad: Dictionary = saved.duplicate(true)
	bad["version"] = "9.9.9"
	_eq(str(f3.load_state(bad).get("reason", "")), "unsupported_version", "版本拒绝")
	var bad2: Dictionary = saved.duplicate(true)
	(bad2.get("ship_states", {}) as Dictionary)["NOPE"] = {}
	_eq(str(f3.load_state(bad2).get("reason", "")), "unknown_ship", "未知舰拒绝")
	# 坏 roster/options
	var br = FleetRefitService.new(cat, {"schema": "bad"})
	_ok(not bool(br.ready), "坏 refit roster 拒绝")
	var bo = FleetRefitService.new(cat, null, "/no/options.json")
	_ok(not bool(bo.ready), "坏 refit options 拒绝")
	# reset
	var rst: Dictionary = f2.reset()
	_eq(bool(rst.get("ok", false)), true, "fleet reset")
	_eq(int(f2.resources.get("credits", 0)), 300000, "reset 共享资源")
	_eq((f2.stats("APSIS").get("installed", []) as Array).size(), 0, "reset APSIS 空")
	_data_line("save", "舰级独立状态/共享资源/planned 恢复 · 字符串/非法版本/未知舰/坏 roster/options 拒绝 · reset")

# ═══════════════════════════════════════════════════════════════════
# 7. 确定性/契约
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("7 确定性")
	var cat = _catalog()
	var a = _refit(cat)
	var b = _refit(cat)
	for f in [a, b]:
		f.install("APSIS", "hull_armor_light")
		f.install("HARMATTAN", "sensor_radar_mk2")
		f.commit_all()
		f.tick(10.0)
	_eq(a.save_json(), b.save_json(), "refit 同操作 save 一致")
	_eq(a.summary(), b.summary(), "refit summary 一致")
	_eq(a.all_stats(), b.all_stats(), "refit all_stats 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "refit contracts")
	var fa = _formation(cat)
	var fb = _formation(cat)
	for ff in [fa, fb]:
		ff.assign("VESUVIUS", "missile")
		ff.assign("BOLLARD", "tug")
		ff.assign("MISSIVE", "shuttle")
	_eq(fa.save_json(), fb.save_json(), "formation 同操作 save 一致")
	_eq(fa.stats(), fb.stats(), "formation stats 一致")
	_eq(fa.summary(), fb.summary(), "formation summary 一致")
	_ok(bool(fa.check_contracts().get("ok", false)), "formation contracts")
	_eq(fa.to_dict().get("schema"), "v17.fleet_formation.v1", "formation to_dict")
	_ok(JSON.parse_string(fa.save_json()) is Dictionary, "formation save JSON")
	_data_line("determinism", "refit/formation 同操作 save/stats/summary 一致 · contracts")
