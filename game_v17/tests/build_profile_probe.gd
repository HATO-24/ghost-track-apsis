extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# BUILD PROFILE PROBE · 版本划分
#
# 验证：两个交付版本（full 剧情本体 / combat_sim 作战模拟器）的剖面加载、
# 功能开关、选择优先级、坏配置回退、sandbox 场景几何、JSON 安全、不写外部。
# 版本划分只决定「开机时装什么」，不改变任何服务接口/存档 schema。
# ═══════════════════════════════════════════════════════════════════

const BuildProfile := preload("res://scripts/core/build_profile.gd")
const CONTENT := "res://framework/content/build_profiles.json"
const SANDBOX := "res://framework/content/scenario_combat_sandbox.json"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("BUILD PROFILE PROBE · 版本划分")
	print("════════════════════════════════════════════════════════════════")
	_test_content()
	_test_default()
	_test_combat_sim()
	_test_sandbox_opts_guard()
	_test_selection()
	_test_fallback()
	_test_sandbox_scenario()
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


func _dist(a: Array, b: Array) -> float:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(
		Vector3(float(b[0]), float(b[1]), float(b[2])))


# ── 1. 内容 ─────────────────────────────────────────────────

func _test_content() -> void:
	print("")
	print("── 1. 配置文件 ──")
	var d := _read_json(CONTENT)
	_ok(not d.is_empty(), "build_profiles.json 可读")
	_eq(String(d.get("schema", "")), "build_profiles.v1", "schema")
	_ok(String(d.get("version", "")) != "", "version")
	_eq(String(d.get("default", "")), "full", "默认剖面 full")
	var ps: Dictionary = d.get("profiles", {})
	_eq(ps.size(), 2, "两个剖面")
	_ok(ps.has("full"), "有 full")
	_ok(ps.has("combat_sim"), "有 combat_sim")
	for pid in ["full", "combat_sim"]:
		var p: Dictionary = ps[pid]
		_ok(String(p.get("label", "")) != "", pid + " label")
		_ok(String(p.get("entry_scene", "")).begins_with("res://"), pid + " entry_scene")
		_ok(String(p.get("save_root", "")) != "", pid + " save_root")
		_ok(p.get("features") is Dictionary, pid + " features")
		var f: Dictionary = p.get("features", {})
		for k in BuildProfile.FEATURES:
			_ok(f.has(k), pid + " 开关 " + k)
	# 两版本存档根必须分开，否则互相覆盖
	_ok(String((ps["full"] as Dictionary).get("save_root", "")) \
		!= String((ps["combat_sim"] as Dictionary).get("save_root", "")), "两版本存档根不同")


# ── 2. 默认剖面 ─────────────────────────────────────────────

func _test_default() -> void:
	print("")
	print("── 2. 默认（full 剧情本体）──")
	var bp = BuildProfile.new()
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_eq(String(bp.id), "full", "默认选 full")
	_eq(String(bp.boot_mode), "prelude", "full boot_mode=prelude")
	_ok(not bool(bp.is_sandbox()), "full 不是 sandbox")
	_ok(not bool(bp.is_combat_sim()), "full 不是模拟器")
	for k in ["story", "prelude", "triggers", "identification", "traffic", "port",
			"signal", "combat", "ballistics", "damage", "physics_world"]:
		_ok(bool(bp.enabled(k)), "full 开启 " + k)
	_ok(not bool(bp.enabled("sandbox")), "full 不开 sandbox")
	_eq(String(bp.entry_scene), "res://main_menu.tscn", "full 入口主菜单")
	_eq(String(bp.save_root), "user://saves", "full 存档根")
	_eq(bp.profile_ids().size(), 2, "可选剖面 2 个")


# ── 3. 模拟器剖面 ───────────────────────────────────────────

func _test_combat_sim() -> void:
	print("")
	print("── 3. combat_sim（作战模拟器）──")
	var bp = BuildProfile.new({"id": "combat_sim"})
	_ok(bool(bp.ready), "ready", str(bp.errors))
	_eq(String(bp.id), "combat_sim", "选中模拟器")
	_eq(String(bp.boot_mode), "sandbox", "boot_mode=sandbox")
	_ok(bool(bp.is_sandbox()), "is_sandbox")
	_ok(bool(bp.is_combat_sim()), "is_combat_sim")
	# 剧情三件套必须关掉
	for k in ["story", "prelude", "triggers"]:
		_ok(not bool(bp.enabled(k)), "模拟器关闭 " + k)
	# 打仗必需的开着
	for k in ["combat", "ballistics", "damage", "physics_world"]:
		_ok(bool(bp.enabled(k)), "模拟器开启 " + k)
	_ok(bool(bp.enabled("sandbox")), "sandbox 开关")
	# 非战斗系统按需关掉
	_ok(not bool(bp.enabled("traffic")), "模拟器关闭 traffic")
	_ok(not bool(bp.enabled("port")), "模拟器关闭 port")
	_eq(String(bp.entry_scene), "res://v1_hud.tscn", "模拟器直接进战术台")
	_eq(String(bp.save_root), "user://saves_sim", "模拟器独立存档根")
	_eq(String(bp.scenario), SANDBOX, "sandbox 场景路径")
	_ok((bp.notes as Array).size() >= 1, "有说明文字")
	# 沙盒便利项：模拟器三个全开
	for k in ["unlimited_ammo", "auto_authorize", "quick_restart"]:
		_ok(bool(bp.sandbox_opt(k, false)), "模拟器便利项开启 " + k)
	_eq((bp.sandbox_opts as Dictionary).size(), 3, "sandbox_opts 三项")
	_eq(bool(bp.vm().get("sandbox_opts", {}).get("unlimited_ammo", false)), true,
		"vm 暴露 sandbox_opts")


# ── 3b. 便利项不对本体开口子 ────────────────────────────────

func _test_sandbox_opts_guard() -> void:
	print("")
	print("── 3b. sandbox_opts 只在 sandbox 生效 ──")
	var bf = BuildProfile.new({"id": "full"})
	_ok(bool(bf.ready), "full ready", str(bf.errors))
	for k in ["unlimited_ammo", "auto_authorize", "quick_restart"]:
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
	for k in ["unlimited_ammo", "auto_authorize", "quick_restart"]:
		_ok(not bool(bfb.sandbox_opt(k, false)), "回退剖面便利项恒关 " + k)


# ── 4. 选择优先级 ───────────────────────────────────────────

func _test_selection() -> void:
	print("")
	print("── 4. 选择优先级 / 切换 ──")
	# 显式 id 优先于环境变量
	OS.set_environment(BuildProfile.ENV_KEY, "combat_sim")
	var a = BuildProfile.new({"id": "full"})
	_eq(String(a.id), "full", "显式 id 压过环境变量")
	var b = BuildProfile.new()
	_eq(String(b.id), "combat_sim", "环境变量生效")
	OS.set_environment(BuildProfile.ENV_KEY, "")
	var c = BuildProfile.new()
	_eq(String(c.id), "full", "无环境变量回落 default")
	# 运行时切换
	var d = BuildProfile.new()
	_ok(bool(d.select("combat_sim")), "select combat_sim")
	_eq(String(d.boot_mode), "sandbox", "切换后 boot_mode 变化")
	_ok(bool(d.select("full")), "select 回 full")
	_eq(String(d.boot_mode), "prelude", "切回 prelude")
	_ok(not bool(d.select("nope")), "select 未知剖面拒绝")
	_ok(not (d.warnings as Array).is_empty(), "select 失败留告警")


# ── 5. 坏配置回退 ───────────────────────────────────────────

func _test_fallback() -> void:
	print("")
	print("── 5. 坏配置回退（绝不把游戏打死）──")
	var bad = BuildProfile.new({"content_path": "/no/such/file.json"})
	_ok(bool(bad.ready), "缺失配置仍 ready")
	_eq(String(bad.id), "full", "回退 full")
	_ok(not (bad.warnings as Array).is_empty(), "留回退告警")
	for k in ["story", "prelude", "combat", "ballistics"]:
		_ok(bool(bad.enabled(k)), "回退后开启 " + k)
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


# ── 6. sandbox 场景几何 ─────────────────────────────────────

func _test_sandbox_scenario() -> void:
	print("")
	print("── 6. sandbox 场景（真实地月系几何）──")
	var sc := _read_json(SANDBOX)
	_ok(not sc.is_empty(), "场景可读")
	_eq(String(sc.get("schema", "")), "scenario_combat_sandbox.v1", "场景 schema")
	_eq(String(sc.get("frame", "")), "bary_rot", "坐标系 bary_rot")
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
	# 交战尺度：实弹档 / 导弹档 / 点防档都覆盖到
	var own_pos: Array = (by_id[own] as Dictionary).get("pos_km", [0.0, 0.0, 0.0])
	var d_ham := _dist(own_pos, (by_id["harmattan"] as Dictionary).get("pos_km", []))
	var d_rai := _dist(own_pos, (by_id["raider_2"] as Dictionary).get("pos_km", []))
	var d_skf := _dist(own_pos, (by_id["skiff"] as Dictionary).get("pos_km", []))
	_ok(d_ham > 100.0 and d_ham < 1200.0, "harmattan 落在实弹射程内", "%.0f km" % d_ham)
	_ok(d_rai > 1200.0 and d_rai < 6000.0, "raider_2 只在导弹射程内", "%.0f km" % d_rai)
	_ok(d_skf < 180.0, "skiff 落在点防射程内", "%.0f km" % d_skf)
	# 通讯图与交战配置
	_ok((sc.get("nodes", []) as Array).size() >= ents.size(), "nodes 覆盖实体")
	_ok((sc.get("links", []) as Array).size() >= 1, "links 非空")
	var cb: Dictionary = sc.get("combat", {})
	_eq(String(cb.get("own_id", "")), own, "combat.own_id = own_entity")
	_ok(String(cb.get("pd_platform_id", "")) != "", "combat.pd_platform_id 指定")
	_ok((sc.get("engage_hint", []) as Array).size() >= 1, "有交战提示")


# ── 7. JSON / 边界 ─────────────────────────────────────────

func _test_json_boundary() -> void:
	print("")
	print("── 7. JSON / 边界 ──")
	var bp = BuildProfile.new({"id": "combat_sim"})
	var vm: Dictionary = bp.vm()
	_eq(String(vm.get("schema", "")), "build_profile.v1", "vm schema")
	_ok(_json_ok(vm), "vm JSON 安全")
	var w: Dictionary = vm.get("writes", {})
	_ok(not bool(w.get("world", true)), "不写 world")
	_ok(not bool(w.get("track_table", true)), "不写 track_table")
	_ok(not bool(w.get("ui", true)), "不写 ui")
	var sm: Dictionary = bp.summary()
	_eq(String(sm.get("schema", "")), "build_profile.v1", "summary schema")
	_ok(_json_ok(sm), "summary JSON 安全")
	_eq(String(sm.get("id", "")), "combat_sim", "summary id")
	# 两次加载一致（确定性）
	var a = BuildProfile.new({"id": "combat_sim"})
	var b = BuildProfile.new({"id": "combat_sim"})
	_eq(JSON.stringify(a.vm()), JSON.stringify(b.vm()), "同配置 VM 逐字节一致")
	# 版本划分不改变服务接口：两剖面都能给出 entry/save_root/boot_mode
	for pid in ["full", "combat_sim"]:
		var p = BuildProfile.new({"id": pid})
		_ok(String(p.entry_scene) != "", pid + " entry_scene 非空")
		_ok(String(p.save_root) != "", pid + " save_root 非空")
		_ok(String(p.boot_mode) in ["prelude", "sandbox"], pid + " boot_mode 合法")
