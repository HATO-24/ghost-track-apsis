extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# BUILD PROFILE PROBE · 版本划分
#
# 验证四个交付剖面：
#   full        正式本体（剧情/序章/触发器，默认）
#   orbital_sim 正式拟真模拟器（无剧情、无作弊项、全核心系统）
#   sandbox     开发测试（核心系统 + 便利项全开）
#   combat_sim  旧作战模拟器 DEMO（deprecated，行为向后兼容）
#
# 覆盖：剖面加载、功能开关矩阵、校验负例、sandbox_opts 边界、
# 选择优先级、坏配置回退、场景几何（旧 sandbox 场景 + 新 orbital_sim 场景）、
# feature_status/limitations/deprecated VM、JSON 安全、不写外部。
# 版本划分只决定「开机时装什么」，不改变任何服务接口/存档 schema。
# ═══════════════════════════════════════════════════════════════════

const BuildProfile := preload("res://scripts/core/build_profile.gd")
const CONTENT := "res://framework/content/build_profiles.json"
const SANDBOX := "res://framework/content/scenario_combat_sandbox.json"
const ORBITAL := "res://framework/content/scenario_orbital_sim.json"
const PROFILES := ["full", "orbital_sim", "sandbox", "combat_sim"]
const SAVE_ROOTS := {
	"full": "user://saves",
	"orbital_sim": "user://saves_sim",
	"sandbox": "user://saves_sandbox",
	"combat_sim": "user://saves_sim",
}

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("BUILD PROFILE PROBE · 版本划分")
	print("════════════════════════════════════════════════════════════════")
	_test_content()
	_test_default()
	_test_orbital_sim()
	_test_sandbox_profile()
	_test_combat_sim()
	_test_simulator_validation()
	_test_sandbox_opts_guard()
	_test_selection()
	_test_fallback()
	_test_scenarios()
	_test_json_boundary()
	print("────────────────────────────────────────────────────────────────")
	print("BUILD PROFILE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("BUILD PROFILE PROBE FAILED")
		quit(1)
	else:
		print("BUILD PROFILE PROBE OK")
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


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _dist(a: Array, b: Array) -> float:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(
		Vector3(float(b[0]), float(b[1]), float(b[2])))


## 注入式配置：读真实配置后按场景改一处，用于校验负例（不写盘）。
func _inline(mutator: String) -> Dictionary:
	var raw := _read_json(CONTENT)
	var profs: Dictionary = raw.get("profiles", {}) if raw.get("profiles") is Dictionary else {}
	var p: Dictionary = (profs.get("orbital_sim", {}) as Dictionary).duplicate(true) \
		if profs.get("orbital_sim") is Dictionary else {}
	var feats: Dictionary = p.get("features", {}) if p.get("features") is Dictionary else {}
	if mutator == "traffic_off":
		feats["traffic"] = false
	elif mutator == "port_off":
		feats["port"] = false
	elif mutator == "story_on":
		feats["story"] = true
	elif mutator == "sandbox_opts_on":
		p["sandbox_opts"] = {"unlimited_ammo": true, "auto_authorize": true, "quick_restart": true}
	elif mutator == "scenario_empty":
		p["scenario"] = ""
	p["features"] = feats
	profs["orbital_sim"] = p
	raw["profiles"] = profs
	return raw


# ── 1. 配置文件 ─────────────────────────────────────────────

func _test_content() -> void:
	print("")
	print("── 1. 配置文件（四剖面）──")
	var d := _read_json(CONTENT)
	_ok(not d.is_empty(), "build_profiles.json 可读")
	_eq(String(d.get("schema", "")), "build_profiles.v1", "schema")
	_ok(String(d.get("version", "")) != "", "version")
	_eq(String(d.get("default", "")), "full", "默认剖面 full（不静默改默认）")
	var ps: Dictionary = d.get("profiles", {})
	_eq(ps.size(), 4, "四个剖面")
	for pid in PROFILES:
		_ok(ps.has(pid), "有 " + pid)
	# 每个剖面必备字段（combat_sim 的 features 保持旧矩阵，不含新增两键）
	for pid in ["full", "orbital_sim", "sandbox"]:
		var p: Dictionary = ps[pid]
		_ok(String(p.get("label", "")) != "", pid + " label")
		_ok(String(p.get("subtitle", "")) != "", pid + " subtitle")
		_ok(String(p.get("entry_scene", "")).begins_with("res://"), pid + " entry_scene")
		_ok(String(p.get("save_root", "")) != "", pid + " save_root")
		_ok(p.get("features") is Dictionary, pid + " features")
		var f: Dictionary = p.get("features", {})
		for k in BuildProfile.FEATURES:
			_ok(f.has(k), pid + " 开关 " + k)
	# 旧 combat_sim 条目行为保持：旧 12 键仍在，不新增 ship_catalog/refit
	var cp: Dictionary = ps["combat_sim"]
	var cf: Dictionary = cp.get("features", {})
	for k in ["story", "prelude", "triggers", "identification", "traffic", "port",
			"signal", "combat", "ballistics", "damage", "physics_world", "sandbox"]:
		_ok(cf.has(k), "combat_sim 保留旧开关 " + k)
	_ok(not cf.has("ship_catalog"), "combat_sim 未新增 ship_catalog（旧矩阵不变）")
	_ok(not cf.has("refit"), "combat_sim 未新增 refit（旧矩阵不变）")
	# 存档根：分隔正式/测试；combat_sim 保持旧根不变
	for pid2 in PROFILES:
		_eq(String((ps[pid2] as Dictionary).get("save_root", "")), SAVE_ROOTS[pid2],
			pid2 + " 存档根")
	_ok(SAVE_ROOTS["full"] != SAVE_ROOTS["orbital_sim"], "full / orbital_sim 存档根不同")
	_ok(SAVE_ROOTS["orbital_sim"] != SAVE_ROOTS["sandbox"],
		"orbital_sim / sandbox 存档根不同")
	# orbital_sim 静态矩阵
	var op: Dictionary = ps["orbital_sim"]
	_eq(String(op.get("boot_mode", "")), "simulator", "orbital_sim boot_mode=simulator")
	_eq(String(op.get("scenario", "")), ORBITAL, "orbital_sim 场景路径")
	_eq(String(op.get("entry_scene", "")), "res://v1_hud.tscn", "orbital_sim 直接进战术台")
	var of: Dictionary = op.get("features", {})
	for k2 in ["story", "prelude", "triggers", "sandbox"]:
		_eq(bool(of.get(k2, false)), false, "orbital_sim 关闭 " + k2)
	for k3 in ["identification", "traffic", "port", "signal", "combat", "ballistics",
			"damage", "physics_world", "ship_catalog", "refit"]:
		_eq(bool(of.get(k3, false)), true, "orbital_sim 开启 " + k3)
	# 拟真剖面不写 sandbox_opts（或全 false）
	var oso = op.get("sandbox_opts", null)
	var oso_all_false := true
	if oso is Dictionary:
		for k4 in BuildProfile.SANDBOX_OPTS:
			if bool((oso as Dictionary).get(k4, false)):
				oso_all_false = false
	_ok(oso_all_false, "orbital_sim 无作弊项（sandbox_opts 缺失/全 false）", str(oso))
	# 能力边界：≥6 条且均为非空字符串
	var lim: Array = op.get("limitations", []) if op.get("limitations") is Array else []
	_ok(lim.size() >= 6, "orbital_sim limitations ≥6", str(lim.size()))
	var lim_ok := true
	for item in lim:
		if not (item is String) or String(item).strip_edges() == "":
			lim_ok = false
	_ok(lim_ok, "limitations 全为非空字符串")
	_ok(not bool(op.get("deprecated", false)), "orbital_sim 不是 deprecated")
	# sandbox 静态矩阵
	var sp: Dictionary = ps["sandbox"]
	_eq(String(sp.get("boot_mode", "")), "sandbox", "sandbox boot_mode=sandbox")
	_eq(String(sp.get("scenario", "")), ORBITAL, "sandbox 使用同一 orbital_sim 场景")
	var so: Dictionary = sp.get("sandbox_opts", {})
	for k5 in BuildProfile.SANDBOX_OPTS:
		_eq(bool(so.get(k5, false)), true, "sandbox 开启便利项 " + k5)
	var sf: Dictionary = sp.get("features", {})
	for k6 in ["story", "prelude", "triggers"]:
		_eq(bool(sf.get(k6, true)), false, "sandbox 关闭 " + k6)
	for k7 in ["identification", "traffic", "port", "signal", "combat", "ballistics",
			"damage", "physics_world", "sandbox", "ship_catalog", "refit"]:
		_eq(bool(sf.get(k7, false)), true, "sandbox 开启 " + k7)
	var slab := (String(sp.get("label", "")) + " " + String(sp.get("subtitle", ""))).to_lower()
	_ok(slab.contains("dev") or slab.contains("test") or slab.contains("sandbox")
		or slab.contains("测试"), "sandbox label/subtitle 明确标注开发测试")
	# combat_sim 弃用标记
	var cdep := bool(cp.get("deprecated", false))
	var creason := String(cp.get("deprecated_reason", ""))
	_ok(cdep, "combat_sim deprecated=true")
	_ok(creason.contains("orbital_sim") and creason.contains("sandbox"),
		"combat_sim deprecated_reason 指向新剖面", creason)
	var cnotes: Array = cp.get("notes", [])
	var note_hit := false
	for n in cnotes:
		if String(n).contains("orbital_sim"):
			note_hit = true
	_ok(note_hit, "combat_sim notes 含迁移提示")
	# 全部剖面经加载器解析后开关集合完整（含旧条目缺省 false）
	for pid3 in PROFILES:
		var b = BuildProfile.new({"content": d, "id": pid3})
		_ok(bool(b.ready), pid3 + " 加载器 ready", str(b.errors))
		_eq((b.features as Dictionary).size(), BuildProfile.FEATURES.size(),
			pid3 + " features 全集")


# ── 2. 默认剖面 ─────────────────────────────────────────────

func _test_default() -> void:
	print("")
	print("── 2. 默认（full 剧情本体）──")
	var bp = BuildProfile.new()
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_eq(String(bp.id), "full", "默认选 full")
	_eq(String(bp.boot_mode), "prelude", "full boot_mode=prelude")
	_ok(not bool(bp.is_sandbox()), "full 不是 sandbox")
	_ok(not bool(bp.is_simulator()), "full 不是 simulator")
	_ok(not bool(bp.is_simulation()), "full 不是 simulation")
	_ok(not bool(bp.is_combat_sim()), "full 不是模拟器")
	for k in ["story", "prelude", "triggers", "identification", "traffic", "port",
			"signal", "combat", "ballistics", "damage", "physics_world",
			"ship_catalog", "refit"]:
		_ok(bool(bp.enabled(k)), "full 开启 " + k)
	_ok(not bool(bp.enabled("sandbox")), "full 不开 sandbox")
	_eq(String(bp.entry_scene), "res://main_menu.tscn", "full 入口主菜单")
	_eq(String(bp.save_root), "user://saves", "full 存档根")
	_eq(bp.profile_ids().size(), 4, "可选剖面 4 个")
	_eq((bp.limitations as Array).size(), 0, "full 无 limitations")
	_ok(not bool(bp.deprecated), "full 不是 deprecated")
	for k2 in BuildProfile.SANDBOX_OPTS:
		_ok(not bool(bp.sandbox_opt(k2, false)), "full 便利项恒关 " + k2)


# ── 3. orbital_sim（正式拟真模拟器）──────────────────────────

func _test_orbital_sim() -> void:
	print("")
	print("── 3. orbital_sim（正式拟真剖面）──")
	var bp = BuildProfile.new({"id": "orbital_sim"})
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_ok((bp.errors as Array).is_empty(), "无校验 error", str(bp.errors))
	_eq(String(bp.id), "orbital_sim", "选中 orbital_sim")
	_eq(String(bp.boot_mode), "simulator", "boot_mode=simulator")
	_ok(bool(bp.is_simulator()), "is_simulator")
	_ok(bool(bp.is_simulation()), "is_simulation")
	_ok(not bool(bp.is_sandbox()), "不是 sandbox 剖面")
	_ok(not bool(bp.is_combat_sim()), "不是 combat_sim")
	# 剧情三件套必须关掉
	for k in ["story", "prelude", "triggers"]:
		_ok(not bool(bp.enabled(k)), "模拟器关闭 " + k)
	# 打仗/拟真必需的开着
	for k2 in ["combat", "ballistics", "damage", "physics_world", "traffic", "port",
			"identification", "signal", "ship_catalog", "refit"]:
		_ok(bool(bp.enabled(k2)), "模拟器开启 " + k2)
	_ok(not bool(bp.enabled("sandbox")), "模拟器不开 sandbox")
	_eq(String(bp.entry_scene), "res://v1_hud.tscn", "模拟器直接进战术台")
	_eq(String(bp.save_root), "user://saves_sim", "模拟器存档根")
	_eq(String(bp.scenario), ORBITAL, "orbital_sim 场景路径")
	_ok((bp.limitations as Array).size() >= 6, "limitations ≥6",
		str((bp.limitations as Array).size()))
	_ok((bp.notes as Array).size() >= 1, "有说明文字")
	_ok(not bool(bp.deprecated), "orbital_sim 不是 deprecated")
	_eq(String(bp.deprecated_reason), "", "deprecated_reason 为空")
	# 拟真剖面零作弊项（三个便利项全 false）
	for k3 in BuildProfile.SANDBOX_OPTS:
		_ok(not bool(bp.sandbox_opt(k3, false)), "拟真剖面便利项恒关 " + k3)
	_eq((bp.sandbox_opts as Dictionary).size(), 3, "sandbox_opts 三键存在但全 false")
	var so_all_false := true
	for k4 in BuildProfile.SANDBOX_OPTS:
		if bool((bp.sandbox_opts as Dictionary).get(k4, true)):
			so_all_false = false
	_ok(so_all_false, "sandbox_opts 全 false")
	# 逐功能状态 VM：story/prelude/triggers 有剧情暂停原因
	var fsv: Dictionary = bp.feature_status_vm()
	_eq(fsv.size(), BuildProfile.FEATURES.size(), "feature_status_vm 覆盖全集")
	for k5 in BuildProfile.FEATURES:
		var row: Dictionary = fsv.get(k5, {})
		_ok(row.has("enabled") and row.has("reason"), "feature_status 含 enabled/reason " + k5)
		if bool(bp.enabled(k5)):
			_eq(String(row.get("reason", "x")), "", "开启项无 OFF 原因 " + k5)
		else:
			_ok(String(row.get("reason", "")) != "", "关闭项有 OFF 原因 " + k5)
	for k6 in ["story", "prelude", "triggers"]:
		var r6: Dictionary = fsv.get(k6, {})
		_ok(String(r6.get("reason", "")).contains("剧情"), "关闭原因含「剧情」 " + k6,
			String(r6.get("reason", "")))
	_ok(String((fsv.get("sandbox", {}) as Dictionary).get("reason", "")) != "",
		"sandbox 关闭原因非空")
	# vm / summary 暴露 limitations/deprecated/feature_status
	var vm: Dictionary = bp.vm()
	_eq((vm.get("limitations", []) as Array).size(), (bp.limitations as Array).size(),
		"vm 暴露 limitations")
	_eq(bool(vm.get("deprecated", true)), false, "vm 暴露 deprecated")
	_ok(vm.get("feature_status") is Dictionary, "vm 暴露 feature_status")
	_ok(bool(vm.get("is_simulation", false)), "vm 暴露 is_simulation")
	_ok(_json_ok(vm), "orbital_sim vm JSON 安全")
	var sm: Dictionary = bp.summary()
	_eq((sm.get("limitations", []) as Array).size(), (bp.limitations as Array).size(),
		"summary 暴露 limitations")
	_eq(bool(sm.get("deprecated", true)), false, "summary 暴露 deprecated")
	_ok(_json_ok(sm), "orbital_sim summary JSON 安全")


# ── 4. sandbox（开发测试剖面）───────────────────────────────

func _test_sandbox_profile() -> void:
	print("")
	print("── 4. sandbox（开发测试剖面）──")
	var bp = BuildProfile.new({"id": "sandbox"})
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_eq(String(bp.boot_mode), "sandbox", "boot_mode=sandbox")
	_ok(bool(bp.is_sandbox()), "is_sandbox")
	_ok(bool(bp.is_simulation()), "is_simulation")
	_ok(not bool(bp.is_simulator()), "不是 simulator")
	_eq(String(bp.entry_scene), "res://v1_hud.tscn", "直接进战术台")
	_eq(String(bp.save_root), "user://saves_sandbox", "测试独立存档根")
	_eq(String(bp.scenario), ORBITAL, "使用 orbital_sim 场景")
	for k in ["identification", "traffic", "port", "signal", "combat", "ballistics",
			"damage", "physics_world", "ship_catalog", "refit"]:
		_ok(bool(bp.enabled(k)), "sandbox 开启 " + k)
	_ok(bool(bp.enabled("sandbox")), "sandbox 开关")
	for k2 in ["story", "prelude", "triggers"]:
		_ok(not bool(bp.enabled(k2)), "sandbox 关闭 " + k2)
	for k3 in BuildProfile.SANDBOX_OPTS:
		_ok(bool(bp.sandbox_opt(k3, false)), "sandbox 便利项开启 " + k3)
	_eq((bp.sandbox_opts as Dictionary).size(), 3, "sandbox_opts 三项")
	_eq(bool(bp.vm().get("sandbox_opts", {}).get("unlimited_ammo", false)), true,
		"vm 暴露 sandbox_opts")
	_ok(not bool(bp.deprecated), "sandbox 不是 deprecated")


# ── 5. combat_sim（旧演示剖面，deprecated）──────────────────

func _test_combat_sim() -> void:
	print("")
	print("── 5. combat_sim（旧作战模拟器·向后兼容）──")
	var bp = BuildProfile.new({"id": "combat_sim"})
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_eq(String(bp.id), "combat_sim", "选中模拟器")
	_eq(String(bp.boot_mode), "sandbox", "boot_mode=sandbox")
	_ok(bool(bp.is_sandbox()), "is_sandbox")
	_ok(bool(bp.is_combat_sim()), "is_combat_sim")
	# 旧断言：剧情三件套关闭
	for k in ["story", "prelude", "triggers"]:
		_ok(not bool(bp.enabled(k)), "旧模拟器关闭 " + k)
	# 旧断言：打仗必需的开着
	for k2 in ["combat", "ballistics", "damage", "physics_world"]:
		_ok(bool(bp.enabled(k2)), "旧模拟器开启 " + k2)
	_ok(bool(bp.enabled("sandbox")), "sandbox 开关")
	# 旧断言：非战斗系统按需关掉
	_ok(not bool(bp.enabled("traffic")), "旧模拟器关闭 traffic")
	_ok(not bool(bp.enabled("port")), "旧模拟器关闭 port")
	_ok(bool(bp.enabled("identification")), "旧模拟器 identification 开")
	_ok(bool(bp.enabled("signal")), "旧模拟器 signal 开")
	_ok(not bool(bp.enabled("ship_catalog")), "旧模拟器 ship_catalog 缺省 false")
	_ok(not bool(bp.enabled("refit")), "旧模拟器 refit 缺省 false")
	# 旧断言：入口/存档/场景/文案
	_eq(String(bp.entry_scene), "res://v1_hud.tscn", "旧模拟器直接进战术台")
	_eq(String(bp.save_root), "user://saves_sim", "旧模拟器独立存档根（未改）")
	_eq(String(bp.scenario), SANDBOX, "旧 sandbox 场景路径（未改）")
	_ok((bp.notes as Array).size() >= 1, "有说明文字")
	# 旧断言：便利项三个全开
	for k3 in BuildProfile.SANDBOX_OPTS:
		_ok(bool(bp.sandbox_opt(k3, false)), "旧模拟器便利项开启 " + k3)
	_eq((bp.sandbox_opts as Dictionary).size(), 3, "sandbox_opts 三项")
	_eq(bool(bp.vm().get("sandbox_opts", {}).get("unlimited_ammo", false)), true,
		"vm 暴露 sandbox_opts")
	# 新增：deprecated 标记 + 选择告警
	_ok(bool(bp.deprecated), "combat_sim deprecated=true")
	_ok(String(bp.deprecated_reason) != "", "deprecated_reason 非空")
	var dep_warn := false
	for w in (bp.warnings as Array):
		if String(w).contains("弃用"):
			dep_warn = true
	_ok(dep_warn, "选中 deprecated 剖面留告警", str(bp.warnings))
	# 旧矩阵逐项核对（行为向后兼容）
	var expect := {
		"story": false, "prelude": false, "triggers": false,
		"identification": true, "traffic": false, "port": false, "signal": true,
		"combat": true, "ballistics": true, "damage": true, "physics_world": true,
		"sandbox": true, "ship_catalog": false, "refit": false,
	}
	for k4 in expect.keys():
		_eq(bool(bp.enabled(k4)), bool(expect[k4]), "combat_sim 开关保持 " + k4)


# ── 6. 拟真剖面校验负例 ─────────────────────────────────────

func _test_simulator_validation() -> void:
	print("")
	print("── 6. simulator 剖面校验（负例不崩溃）──")
	# 关闭核心系统 → error（不自动开启）
	var b1 = BuildProfile.new({"content": _inline("traffic_off"), "id": "orbital_sim"})
	_ok(not bool(b1.ready), "traffic=false 时 ready=false")
	var msgs1 := str(b1.errors)
	_ok(msgs1.contains("traffic") and msgs1.contains("核心系统"),
		"缺核心系统报错并点明核心系统", msgs1)
	_ok(not bool(b1.enabled("traffic")), "不自动开启被关掉的核心系统")
	var b2 = BuildProfile.new({"content": _inline("port_off"), "id": "orbital_sim"})
	_ok(not bool(b2.ready), "port=false 时 ready=false")
	_ok(str(b2.errors).contains("port"), "错误信息含 port")
	# 配置写沙盒便利项 → 强制 false + 告警（拟真剖面不许作弊）
	var b3 = BuildProfile.new({"content": _inline("sandbox_opts_on"), "id": "orbital_sim"})
	_ok(bool(b3.ready), "注入 sandbox_opts 仍 ready（只告警）", str(b3.errors))
	for k in BuildProfile.SANDBOX_OPTS:
		_ok(not bool(b3.sandbox_opt(k, false)), "simulator 强制关闭便利项 " + k)
	var so_warn := false
	for w in (b3.warnings as Array):
		if String(w).contains("便利项") or String(w).contains("sandbox_opts"):
			so_warn = true
	_ok(so_warn, "注入 sandbox_opts 留告警", str(b3.warnings))
	var vm3: Dictionary = b3.vm()
	var so3: Dictionary = vm3.get("sandbox_opts", {})
	var all_false3 := true
	for k2 in BuildProfile.SANDBOX_OPTS:
		if bool(so3.get(k2, true)):
			all_false3 = false
	_ok(all_false3, "vm.sandbox_opts 全 false")
	# 配置开 story → 强制关闭 + 告警（模拟器不跑剧情）
	var b4 = BuildProfile.new({"content": _inline("story_on"), "id": "orbital_sim"})
	_ok(not bool(b4.enabled("story")), "simulator 强制关闭 story")
	var story_warn := false
	for w2 in (b4.warnings as Array):
		if String(w2).contains("剧情"):
			story_warn = true
	_ok(story_warn, "强制关闭剧情留告警", str(b4.warnings))
	# 缺 scenario → error
	var b5 = BuildProfile.new({"content": _inline("scenario_empty"), "id": "orbital_sim"})
	_ok(not bool(b5.ready), "simulator 缺 scenario 时 ready=false")
	_ok(str(b5.errors).contains("scenario"), "错误信息含 scenario")
	# 未知 boot_mode → 回退 prelude（老行为），留 error
	var bogus := {"schema": "build_profiles.v1", "default": "full", "profiles": {
		"full": {"label": "F", "features": {"story": true}},
		"weird": {"label": "W", "boot_mode": "warp", "entry_scene": "res://x.tscn",
			"scenario": "res://x.json", "features": {}}}}
	var b6 = BuildProfile.new({"content": bogus, "id": "weird"})
	_eq(String(b6.boot_mode), "prelude", "未知 boot_mode 回退 prelude")
	_ok(not (b6.errors as Array).is_empty(), "未知 boot_mode 留 error")
	_ok(not bool(b6.ready), "未知 boot_mode 不 ready")


# ── 7. sandbox_opts 边界 ────────────────────────────────────

func _test_sandbox_opts_guard() -> void:
	print("")
	print("── 7. sandbox_opts 只在 sandbox 生效 ──")
	var bf = BuildProfile.new({"id": "full"})
	_ok(bool(bf.ready), "full ready", str(bf.errors))
	for k in BuildProfile.SANDBOX_OPTS:
		_ok(not bool(bf.sandbox_opt(k, false)), "本体便利项恒关 " + k)
	_eq(bool(bf.vm().get("sandbox_opts", {}).get("unlimited_ammo", true)), false,
		"本体 vm.sandbox_opts.unlimited_ammo=false")
	# 就算配置里给 full 写了 true，也不能生效（防手滑）
	var raw := _read_json(BuildProfile.DEFAULT_PATH)
	var cfg: Dictionary = raw.duplicate(true)
	var profs: Dictionary = cfg.get("profiles", {})
	var fp: Dictionary = profs.get("full", {})
	fp["sandbox_opts"] = {"unlimited_ammo": true, "auto_authorize": true, "quick_restart": true}
	profs["full"] = fp
	cfg["profiles"] = profs
	var bf2 = BuildProfile.new({"content": cfg, "id": "full"})
	_ok(bool(bf2.ready), "注入配置 ready", str(bf2.errors))
	_eq(String(bf2.boot_mode), "prelude", "仍是 prelude")
	_ok(not bool(bf2.sandbox_opt("unlimited_ammo", false)),
		"prelude 剖面忽略 sandbox_opts.unlimited_ammo")
	# 回退剖面也不开便利项
	var bfb = BuildProfile.new({"content_path": "res://nope.json"})
	_ok(bool(bfb.ready), "回退 ready")
	for k2 in BuildProfile.SANDBOX_OPTS:
		_ok(not bool(bfb.sandbox_opt(k2, false)), "回退剖面便利项恒关 " + k2)


# ── 8. 选择优先级 ───────────────────────────────────────────

func _test_selection() -> void:
	print("")
	print("── 8. 选择优先级 / 切换 ──")
	# 显式 id 优先于环境变量
	OS.set_environment(BuildProfile.ENV_KEY, "orbital_sim")
	var a = BuildProfile.new({"id": "full"})
	_eq(String(a.id), "full", "显式 id 压过环境变量")
	var b = BuildProfile.new()
	_eq(String(b.id), "orbital_sim", "环境变量生效")
	_eq(String(b.boot_mode), "simulator", "环境变量→simulator 剖面")
	OS.set_environment(BuildProfile.ENV_KEY, "combat_sim")
	var b2 = BuildProfile.new()
	_eq(String(b2.boot_mode), "sandbox", "环境变量→sandbox 剖面")
	OS.set_environment(BuildProfile.ENV_KEY, "")
	var c = BuildProfile.new()
	_eq(String(c.id), "full", "无环境变量回落 default")
	# 运行时切换
	var d = BuildProfile.new()
	_ok(bool(d.select("orbital_sim")), "select orbital_sim")
	_eq(String(d.boot_mode), "simulator", "切换后 boot_mode=simulator")
	_ok(bool(d.select("sandbox")), "select sandbox")
	_eq(String(d.boot_mode), "sandbox", "switch 后 boot_mode=sandbox")
	_ok(bool(d.select("combat_sim")), "select combat_sim")
	_eq(String(d.boot_mode), "sandbox", "旧剖面仍是 sandbox")
	var dep_warn := false
	for w in (d.warnings as Array):
		if String(w).contains("弃用"):
			dep_warn = true
	_ok(dep_warn, "select deprecated 剖面留告警")
	_ok(bool(d.select("full")), "select 回 full")
	_eq(String(d.boot_mode), "prelude", "切回 prelude")
	_ok(not bool(d.select("nope")), "select 未知剖面拒绝")
	_ok(not (d.warnings as Array).is_empty(), "select 失败留告警")


# ── 9. 坏配置回退 ───────────────────────────────────────────

func _test_fallback() -> void:
	print("")
	print("── 9. 坏配置回退（绝不把游戏打死）──")
	var bad = BuildProfile.new({"content_path": "/no/such/file.json"})
	_ok(bool(bad.ready), "缺失配置仍 ready")
	_eq(String(bad.id), "full", "回退 full")
	_ok(not (bad.warnings as Array).is_empty(), "留回退告警")
	for k in ["story", "prelude", "combat", "ballistics", "ship_catalog", "refit"]:
		_ok(bool(bad.enabled(k)), "回退后开启 " + k)
	_ok(not bool(bad.is_simulation()), "回退不是模拟器剖面")
	_eq((bad.limitations as Array).size(), 0, "回退无 limitations")
	_ok(not bool(bad.deprecated), "回退不是 deprecated")
	var bad_schema = BuildProfile.new({"content": {"schema": "bogus", "profiles": {}}})
	_ok(bool(bad_schema.ready), "schema 不符仍 ready")
	_eq(String(bad_schema.id), "full", "schema 不符回退 full")
	var no_profiles = BuildProfile.new({"content": {"schema": "build_profiles.v1", "profiles": {}}})
	_ok(bool(no_profiles.ready), "无 profiles 仍 ready")
	_eq(String(no_profiles.id), "full", "无 profiles 回退 full")
	# default 指向不存在
	var bad_default = BuildProfile.new({"content": {
		"schema": "build_profiles.v1", "default": "ghost",
		"profiles": {"full": {"label": "F", "features": {"story": true}}}}})
	_ok(bool(bad_default.ready), "坏 default 仍 ready")
	_eq(String(bad_default.id), "full", "坏 default 回落 full")
	_ok(not (bad_default.warnings as Array).is_empty(), "坏 default 留告警")
	# 环境变量指向不存在
	OS.set_environment(BuildProfile.ENV_KEY, "no_such_profile")
	var bad_env = BuildProfile.new()
	_eq(String(bad_env.id), "full", "坏环境变量回落 default")
	OS.set_environment(BuildProfile.ENV_KEY, "")


# ── 10. 场景几何（sandbox 旧场景 / orbital_sim 正式场景）───

func _test_scenarios() -> void:
	print("")
	print("── 10a. 旧 sandbox 场景（真实地月系几何，向后兼容）──")
	_test_scenario_geometry(SANDBOX, "scenario_combat_sandbox.v1", "combat_sandbox_eml1")
	print("")
	print("── 10b. orbital_sim 正式场景 ──")
	_test_scenario_geometry(ORBITAL, "scenario_orbital_sim.v1", "")
	var osc := _read_json(ORBITAL)
	_ok(not osc.is_empty(), "orbital_sim 场景可读")
	_ok(String(osc.get("title", "")) != "", "orbital_sim 场景 title")
	_ok(String(osc.get("subtitle", "")) != "", "orbital_sim 场景 subtitle")
	_ok(String(osc.get("description", "")) != "", "orbital_sim 场景 description")
	_ok(String(osc.get("own_entity", "")) == "apsis", "orbital_sim own_entity=apsis")
	var cb: Dictionary = osc.get("combat", {})
	_eq(String(cb.get("roe", "")), "TIGHT", "orbital_sim ROE TIGHT（真实授权流程）")
	_eq(String(cb.get("own_id", "")), "apsis", "orbital_sim combat.own_id")
	_ok(String(cb.get("pd_platform_id", "")) != "", "orbital_sim pd_platform_id")
	_eq((osc.get("entities", []) as Array).size(), 7, "orbital_sim 实体=7（与 smoke 一致）")
	# 产品场景不携带任何测试便利项/标记
	_ok(not osc.has("sandbox_opts"), "orbital_sim 场景无 sandbox_opts")
	var txt := _read_text(ORBITAL)
	_ok(not txt.contains("unlimited_ammo"), "场景文本无 unlimited_ammo")
	_ok(not txt.contains("auto_authorize"), "场景文本无 auto_authorize")
	_ok(not txt.contains("quick_restart"), "场景文本无 quick_restart")
	# 与旧场景同族几何（交战可打）
	var so := _read_json(SANDBOX)
	var oe: Array = osc.get("entities", [])
	var se: Array = so.get("entities", [])
	var oid := ""
	for raw in oe:
		if String((raw as Dictionary).get("id", "")) == "apsis":
			oid = "apsis"
	var o_by: Dictionary = _entity_map(oe)
	var s_by: Dictionary = _entity_map(se)
	_ok(oid != "" and o_by.has("harmattan") and o_by.has("skiff") and o_by.has("raider_2"),
		"orbital_sim 与旧场景同实体族")
	var opos: Array = (o_by["apsis"] as Dictionary).get("pos_km", [0.0, 0.0, 0.0])
	_ok(_dist(opos, (o_by["harmattan"] as Dictionary).get("pos_km", [])) > 100.0,
		"orbital_sim 实弹档目标在射程内")
	_ok(_dist(opos, (o_by["raider_2"] as Dictionary).get("pos_km", [])) > 1200.0,
		"orbital_sim 导弹档目标在远距")
	# 旧场景断言（历史兼容）
	for sid in ["harmattan", "skiff", "raider_2", "l1_station", "ferry", "watchtower"]:
		_ok(s_by.has(sid), "旧 sandbox 场景仍有 " + sid)


func _entity_map(ents: Array) -> Dictionary:
	var by: Dictionary = {}
	for raw in ents:
		if raw is Dictionary:
			by[String((raw as Dictionary).get("id", ""))] = raw
	return by


func _test_scenario_geometry(path: String, schema: String, id_expect: String) -> void:
	var sc := _read_json(path)
	_ok(not sc.is_empty(), "场景可读：" + path)
	if sc.is_empty():
		return
	_eq(String(sc.get("schema", "")), schema, "场景 schema")
	_eq(String(sc.get("frame", "")), "bary_rot", "坐标系 bary_rot")
	if id_expect != "":
		_eq(String(sc.get("id", "")), id_expect, "场景 id")
	var ents: Array = sc.get("entities", [])
	_ok(ents.size() >= 5, "实体数 ≥5", str(ents.size()))
	var own := String(sc.get("own_entity", ""))
	_ok(own != "", "own_entity 非空")
	var by_id: Dictionary = {}
	for raw in ents:
		var e: Dictionary = raw
		var eid := String(e.get("id", ""))
		by_id[eid] = e
		_ok(eid != "", "实体 id 非空")
		_ok((e.get("pos_km", []) as Array).size() == 3, eid + " pos_km 三元")
		_ok((e.get("vel_kmps", []) as Array).size() == 3, eid + " vel_kmps 三元")
		_ok(float(e.get("radius_km", 0.0)) > 0.0, eid + " radius_km")
		_ok(String(e.get("side", "")) != "", eid + " side")
	_ok(by_id.has(own), "own_entity 在实体表里")
	# 地月系几何：所有实体都在 EML1 附近（x≈321719 km），不是原点附近的假坐标
	for raw2 in ents:
		var e2: Dictionary = raw2
		var pos: Array = e2.get("pos_km", [0.0, 0.0, 0.0])
		var x := float(pos[0])
		_ok(x > 300000.0 and x < 350000.0, String(e2.get("id", "")) + " 位于 EML1 附近",
			"x=%.0f" % x)
	# 通讯图与交战配置
	_ok((sc.get("nodes", []) as Array).size() >= ents.size(), "nodes 覆盖实体")
	_ok((sc.get("links", []) as Array).size() >= 1, "links 非空")
	var cb: Dictionary = sc.get("combat", {})
	_eq(String(cb.get("own_id", "")), own, "combat.own_id = own_entity")
	_ok(String(cb.get("pd_platform_id", "")) != "", "combat.pd_platform_id 指定")
	_ok((sc.get("engage_hint", []) as Array).size() >= 1, "有交战提示")


# ── 11. JSON / 边界 ────────────────────────────────────────

func _test_json_boundary() -> void:
	print("")
	print("── 11. JSON / 边界 ──")
	# 四个剖面的 vm/summary 全部 JSON 安全、不写外部
	for pid in PROFILES:
		var bp = BuildProfile.new({"id": pid})
		var vm: Dictionary = bp.vm()
		_eq(String(vm.get("schema", "")), "build_profile.v1", pid + " vm schema")
		_ok(_json_ok(vm), pid + " vm JSON 安全")
		_ok(_json_ok(bp.summary()), pid + " summary JSON 安全")
		var w: Dictionary = vm.get("writes", {})
		_ok(not bool(w.get("world", true)), pid + " 不写 world")
		_ok(not bool(w.get("track_table", true)), pid + " 不写 track_table")
		_ok(not bool(w.get("ui", true)), pid + " 不写 ui")
		_ok(String(bp.entry_scene) != "", pid + " entry_scene 非空")
		_ok(String(bp.save_root) != "", pid + " save_root 非空")
		_ok(String(bp.boot_mode) in ["prelude", "sandbox", "simulator"],
			pid + " boot_mode 合法", String(bp.boot_mode))
		_ok(vm.has("limitations") and vm.has("deprecated"), pid + " vm 含 limitations/deprecated")
	# 两次加载一致（确定性；不打印整份 VM，避免日志淹没）
	for pid2 in ["orbital_sim", "sandbox", "combat_sim"]:
		var a = BuildProfile.new({"id": pid2})
		var b = BuildProfile.new({"id": pid2})
		_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), pid2 + " 同配置 VM 逐字节一致")
