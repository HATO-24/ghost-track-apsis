extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# E2E ORBITAL SIM PROBE · Issue #5 验收：真实入口端到端集成
#
# 入口链：main_menu.tscn（真实主场景）→（BuildProfile 自动跳过主菜单）
#         → v1_hud.tscn → V1HUD._ready() → ShellBinder.boot() → GameSession.boot()
#
# 断言（只用真实对象/返回值，不读日志、不伪造）：
#   1) 真实入口：SceneTree.change_scene_to_file 加载主场景；主菜单按 profile 自动入 HUD；
#      有界帧/秒超时，超时明确 FAIL。
#   2) 剖面：id / boot_mode / entry_scene / 功能开关 / 场景文件 / sandbox 便利项关闭。
#   3) binder：ShellBinder ready、errors 空；session 已 boot。
#   4) 系统装配：物理/传感器/航迹/战斗/弹道/损管/EW/识别/交通/港口/舰船目录/改装
#      都是真实服务对象且 ready（不是日志、不是 JSON 标记）。
#   5) 拟真：无 story_state / story_vm；unlimited_ammo=false、auto_authorize=false、
#      quick_restart 被拒；弹药真实扣减。
#   6) 战斗闭环：从 binder 航迹选真实敌对目标 → 未授权 FIRE 被拒且不耗弹 →
#      TRACK → SOLUTION → tick 到 READY → 授权 → FIRE → tick 到弹道落地 →
#      真实 impact/miss/intercept 记录 + 事件/弹药计数一致。
#   7) 交通/港口：真实服务查询非空（lane/vm/resource/window），不是空桩。
#
# 输出：`[E2E] STEP ...` / `[E2E] PASS ...` / `[E2E] FAIL ...` / 系统就绪表 /
#       最终 `E2E ORBITAL SIM PROBE RESULT: PASS=n FAIL=m`，全过 quit(0)，否则 quit(1)。
#
# 无渲染依赖、无写盘（只读 user:// 之外内容；不写 user://），有界 await。
# ═══════════════════════════════════════════════════════════════════

# 验收目标 profile：正式拟真模拟器（T1 契约，Issue #1）。探针强制该剖面启动，
# 不读取外部 DSH_BUILD，避免 CI/本地环境污染。
const TARGET_PROFILE := "orbital_sim"

const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"

# 有界等待：600 帧 / 60 秒，先到为准（headless 下帧很快，秒数用于慢机兜底）。
const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
# HUD 出现后等待 binder.boot() 完成的上限（boot 在 _ready 内同步，通常 1 帧内就绪）。
const MAX_BINDER_FRAMES := 120
const MAX_TRACK_TICKS := 120
const MAX_SOLUTION_TICKS := 120
const MAX_BALLISTICS_TICKS := 600
const BALLISTICS_TICK_DT := 2.0
# 兜底看门狗：即使探针协程因意外运行时错误中断，也在有界时间内 quit(1) 而不是挂死。
const WATCHDOG_S := 240.0

const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

# session 服务名 → GameSession 属性名（真实对象，不看日志/配置标记）。
const SESSION_SYSTEMS := [
	["physics_world", "physics_world_service", "physics"],
	["sensor_service", "sensor_service", "sensors"],
	["track_table", "track_table", "track_table"],
	["combat_service", "combat_service", "combat"],
	["combat_ballistics", "combat_ballistics", "ballistics"],
	["damage_service", "damage_service", "damage"],
	["ew_service", "ew_service", "ew"],
	["identification_service", "identification_service", "identification"],
	["traffic_control", "traffic_control", "traffic"],
	["port_service", "port_service", "port"],
	["ship_catalog", "ship_catalog", "ship_catalog"],
	["refit_service", "refit_service", "refit"],
]

# T3 验收目标剖面固定为 orbital_sim（正式拟真模拟器）。断言按该剖面的运行时
# 契约写死，不提供"换成旧 sandbox 剖面也照样 PASS"的宽松分支。
const EXPECT := {
	"orbital_sim": {
		"boot_mode": "simulator",
		"scenario_file": "scenario_orbital_sim.json",
		"features": {
			"story": false, "prelude": false, "triggers": false,
			"identification": true, "traffic": true, "port": true, "signal": true,
			"combat": true, "ballistics": true, "damage": true, "physics_world": true,
			"sandbox": false, "ship_catalog": true, "refit": true,
		},
		"require_systems": ["physics_world", "sensor_service", "track_table",
			"combat_service", "combat_ballistics", "damage_service", "ew_service",
			"identification_service", "traffic_control", "port_service",
			"ship_catalog", "refit_service"],
		"require_limitations": 6,
	},
}

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _main_menu_instantiated := false
var _exp: Dictionary = {}
var _hud = null
var _binder = null
var _session = null
var _profile = null
var _scenario_by_id: Dictionary = {}


# ── 生命周期 ─────────────────────────────────────────────────────

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("E2E ORBITAL SIM PROBE · 真实入口 main_menu → v1_hud → ShellBinder → GameSession")
	print("Godot ", Engine.get_version_info().get("string", "?"),
		" · target profile=", TARGET_PROFILE)
	print("════════════════════════════════════════════════════════════════")
	_exp = EXPECT.get(TARGET_PROFILE, {})
	if _exp.is_empty():
		print("[E2E] FAIL 未知 TARGET_PROFILE=", TARGET_PROFILE)
		quit(1)
		return
	_setup_env()
	node_added.connect(_on_node_added)
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[E2E] FAIL 看门狗超时 %.0fs：探针未正常结束（疑似异常中断/挂起）" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


## 真实入口证明：主菜单在自动跳过前确实被实例化进场景树（同帧内可能立即被替换，
## 因此用 SceneTree.node_added 记录，而不是轮询 current_scene）。
func _on_node_added(node: Node) -> void:
	if node == null:
		return
	var scr = node.get_script()
	if scr == null:
		return
	if String(scr.resource_path) == "res://scripts/ui/main_menu.gd":
		_main_menu_instantiated = true


func _setup_env() -> void:
	for k in ENV_KEYS:
		_env_backup[k] = OS.get_environment(k)
	# 强制目标剖面；清掉会劫持主菜单/场景/自测的环境变量。
	OS.set_environment("DSH_BUILD", TARGET_PROFILE)
	for k in ["DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE", "DSH_V1_TEST",
			"DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_MAIN_MENU_VIEW",
			"DSH_SETTINGS_TEST"]:
		_unset_env(k)
	print("[E2E] STEP 0 · 环境: DSH_BUILD=", OS.get_environment("DSH_BUILD"),
		" DSH_SHOT='' DSH_FLOW_SMOKE='' DSH_NO_AUTOSKIP='' DSH_V1_TEST=''")


func _restore_env() -> void:
	for k in _env_backup.keys():
		var v := String(_env_backup[k])
		if v == "":
			_unset_env(k)
		else:
			OS.set_environment(k, v)


func _unset_env(key: String) -> void:
	if OS.has_method("unset_environment"):
		OS.unset_environment(key)
	else:
		OS.set_environment(key, "")


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("E2E ORBITAL SIM PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[E2E] FAILED: ", f)
		print("E2E ORBITAL SIM PROBE FAILED · target=", TARGET_PROFILE)
	else:
		print("E2E ORBITAL SIM PROBE OK · target=", TARGET_PROFILE)
	_restore_env()
	quit(0 if _fail == 0 else 1)


# ── 断言 / 打印 ──────────────────────────────────────────────────

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[E2E] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[E2E] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(title: String) -> void:
	print("")
	print("[E2E] STEP ", title)


func _info(text: String) -> void:
	print("[E2E] INFO ", text)


func _sys_line(name: String, obj, required: bool) -> void:
	var present := obj != null
	var ready := present and bool(obj.get("ready"))
	var state := "NOT ASSEMBLED"
	if present:
		state = "READY" if ready else "NOT READY"
	var req := "required" if required else "optional"
	print("[E2E] SYSTEM %-22s %-14s %s" % [name, state, req])
	if required:
		_ok(present and ready, "系统就绪: " + name,
			"present=%s ready=%s" % [str(present), str(ready)])


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


# ── 1. 真实入口 ─────────────────────────────────────────────────

func _run() -> void:
	_step("1. 真实入口 main_menu → v1_hud（SceneTree.change_scene_to_file）")
	var err := change_scene_to_file(MAIN_MENU)
	_ok(err == OK, "change_scene_to_file(main_menu) 返回 OK", "err=%d" % err)
	if err != OK:
		_finish()
		return
	var boot := await _await_v1_hud()
	if boot["hud"] == null:
		_finish()
		return
	_hud = boot["hud"]
	_ok(bool(boot["saw_main_menu"]), "真实入口经过 main_menu（主菜单自动跳过已触发）",
		"saw_main_menu=%s frames=%d" % [str(boot["saw_main_menu"]), int(boot["frames"])])
	_ok(bool(boot["scene_script_ok"]), "current_scene 为 V1HUD 且脚本为 v1_hud.gd",
		"path=" + String(_hud.scene_file_path))
	_ok(int(boot["frames"]) <= MAX_BOOT_FRAMES, "入口在帧上限内完成", "frames=%d" % int(boot["frames"]))
	_info("首帧到 HUD 用时 %d 帧 / %d ms" % [int(boot["frames"]), int(boot["elapsed_ms"])])

	_step("2. BuildProfile / ShellBinder")
	_profile = _hud.get("binder").get("build_profile") if _hud.get("binder") != null else null
	_binder = _hud.get("binder")
	_check_binder_profile()

	_step("3. GameSession 启动")
	if _binder != null:
		_session = _binder.get("session")
	_check_session()
	if _session == null:
		_info("session 不可用，后续系统/战斗断言无法执行")
		_finish()
		return

	_step("4. 真实系统装配（以真实服务对象 ready 为准）")
	_check_systems()

	_step("5. 场景实体 / own_entity / 无剧情状态")
	_check_scenario_and_story()

	_step("6. 拟真默认（无便利项）")
	_check_realism()

	_step("7. 交通 / 港口实时查询")
	_check_traffic_port()

	_step("8. 战斗闭环（未授权拒绝 → TRACK → SOLUTION → 授权 → FIRE → 弹道结果）")
	_check_combat()

	_finish()


func _await_v1_hud() -> Dictionary:
	var frames := 0
	var saw_main_menu := false
	var scene_script_ok := false
	var unexpected := ""
	var t0 := Time.get_ticks_msec()
	while frames < MAX_BOOT_FRAMES and (Time.get_ticks_msec() - t0) < MAX_BOOT_MS:
		await process_frame
		frames += 1
		var cs = current_scene
		if cs == null:
			continue
		var path := String(cs.scene_file_path)
		if path == MAIN_MENU:
			saw_main_menu = true
			continue
		if path != V1_HUD:
			unexpected = path
			continue
		# HUD 已出现：等待 binder.boot() 完成（同步 boot，通常当帧就绪）。
		var hud = cs
		var f2 := 0
		while f2 < MAX_BINDER_FRAMES:
			var b = hud.get("binder")
			if b != null and bool(b.get("ready")):
				break
			await process_frame
			f2 += 1
		var script_path := ""
		var scr = hud.get_script()
		if scr != null:
			script_path = String(scr.resource_path)
		scene_script_ok = script_path == HUD_SCRIPT and String(hud.name) == HUD_NODE
		return {"hud": hud, "frames": frames,
			"saw_main_menu": saw_main_menu or _main_menu_instantiated,
			"scene_script_ok": scene_script_ok,
			"elapsed_ms": Time.get_ticks_msec() - t0}
	var cs2 = current_scene
	var cur := "" if cs2 == null else String(cs2.scene_file_path)
	print("[E2E] FAIL 入口超时：等待 v1_hud（%d 帧 / %d ms）未达成" % [MAX_BOOT_FRAMES, MAX_BOOT_MS])
	print("[E2E] INFO timeout_state: current_scene='", cur, "' saw_main_menu=",
		str(saw_main_menu or _main_menu_instantiated), " unexpected_scene='", unexpected, "'")
	_fail += 1
	_failures.append("入口超时：未从 main_menu 到达 v1_hud（current_scene='%s'）" % cur)
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}


# ── 2. binder / profile ─────────────────────────────────────────

func _check_binder_profile() -> void:
	if _binder == null:
		_ok(false, "V1HUD.binder 存在")
		return
	_ok(true, "V1HUD.binder 已创建")
	_ok(_binder.get("session") != null, "binder.session 存在")
	_ok(bool(_binder.get("ready")), "ShellBinder.ready == true",
		"errors=" + str(_binder.get("errors")))
	_ok((_binder.get("errors") as Array).is_empty(), "ShellBinder boot 无错误",
		str(_binder.get("errors")))
	if _profile == null:
		_ok(false, "binder.build_profile 存在")
		return
	_ok(true, "binder.build_profile 存在")
	_ok(bool(_profile.get("ready")), "BuildProfile.ready == true",
		"errors=" + str(_profile.get("errors")))
	_ok((_profile.get("errors") as Array).is_empty(), "BuildProfile 加载无错误",
		str(_profile.get("errors")))
	_eq(String(_profile.get("id")), TARGET_PROFILE, "profile id")
	_eq(String(_profile.get("boot_mode")), String(_exp.get("boot_mode")), "profile boot_mode")
	_eq(String(_profile.get("entry_scene")), V1_HUD, "profile entry_scene")
	var scenario_path := String(_profile.get("scenario"))
	_eq(scenario_path, "res://framework/content/" + String(_exp.get("scenario_file", "")),
		"profile scenario 精确指向验收场景文件")
	# 功能开关：逐项按验收目标断言（orbital_sim: 核心全开、剧情/便利全关）。
	var feats: Dictionary = _exp.get("features", {})
	for k in feats.keys():
		_eq(bool(_profile.enabled(String(k))), bool(feats[k]), "profile feature " + String(k))
	# is_simulator()/is_sandbox()/is_simulation() 运行期契约。
	var has_sim: bool = _profile.has_method("is_simulator")
	_ok(has_sim, "BuildProfile 提供 is_simulator()")
	if has_sim:
		_ok(bool(_profile.call("is_simulator")), "is_simulator() == true")
	var has_sb: bool = _profile.has_method("is_sandbox")
	_ok(has_sb, "BuildProfile 提供 is_sandbox()")
	if has_sb:
		_ok(not bool(_profile.call("is_sandbox")), "is_sandbox() == false（拟真剖面不是 sandbox）")
	var has_simu: bool = _profile.has_method("is_simulation")
	_ok(has_simu, "BuildProfile 提供 is_simulation()")
	if has_simu:
		_ok(bool(_profile.call("is_simulation")), "is_simulation() == true（模拟器跳过剧情）")
	# limitations（T1 契约：正式模拟器逐条声明未实现能力）。
	var lim = _profile.get("limitations")
	var lim_n := 0
	if lim is Array:
		lim_n = (lim as Array).size()
	elif lim is Dictionary:
		lim_n = (lim as Dictionary).size()
	var need_lim := int(_exp.get("require_limitations", 0))
	_ok(lim_n >= need_lim, "profile.limitations 数量 >= " + str(need_lim), "n=" + str(lim_n))
	var empty_lim := 0
	if lim is Array:
		for raw_lim in (lim as Array):
			if String(raw_lim).strip_edges() == "":
				empty_lim += 1
			else:
				_info("LIMITATION " + String(raw_lim))
	_eq(empty_lim, 0, "profile.limitations 条目均非空")


# ── 3. session ──────────────────────────────────────────────────

func _check_session() -> void:
	if _session == null:
		_ok(false, "GameSession 实例存在")
		return
	_ok(true, "GameSession 实例存在")
	_ok(bool(_session.get("ready")), "GameSession.ready == true",
		"errors=" + str(_session.get("errors")))
	_ok(bool(_session.get("booted")), "GameSession.booted == true")
	_ok((_session.get("errors") as Array).is_empty(), "GameSession.boot 无错误",
		str(_session.get("errors")))
	_ok(float(_session.now_s()) >= 0.0, "session 时间基准可读", "t=%.3f" % float(_session.now_s()))


# ── 4. 系统装配 ─────────────────────────────────────────────────

func _check_systems() -> void:
	var required: Array = _exp.get("require_systems", [])
	for pair in SESSION_SYSTEMS:
		var name := String(pair[0])
		var prop := String(pair[1])
		var obj = _session.get(prop)
		_sys_line(name, obj, name in required)
	# 与启动日志同源的 systems_vm：真实服务对象 ready 才 true（不是 JSON 标记）。
	var svm: Dictionary = _binder.systems_vm()
	_ok(not svm.is_empty(), "binder.systems_vm() 非空（与启动日志同源）")
	_eq(String(svm.get("profile", "")), TARGET_PROFILE, "systems_vm.profile")
	_eq(String(svm.get("mode", "")), String(_exp.get("boot_mode")), "systems_vm.mode")
	_eq(String(svm.get("scenario", "")), String(_profile.get("scenario")), "systems_vm.scenario")
	for pair2 in SESSION_SYSTEMS:
		var nm := String(pair2[0])
		var vm_key := String(pair2[2])
		if not (nm in required):
			continue
		_eq(bool(svm.get(vm_key, false)), true, "systems_vm." + vm_key + " == true")
	_eq(String(svm.get("story", "")), "disabled", "systems_vm.story == disabled（无剧情状态）")
	# 物理世界另有一条 binder 侧真实查询。
	var pw = _session.get("physics_world_service")
	if pw != null:
		var ids: Array = _session.physics_entity_ids()
		_ok(ids.size() > 0, "PhysicsWorld 有真实实体", "entities=" + str(ids.size()))
		_ok(bool(_binder.physics_world_ready()), "binder.physics_world_ready() == true")


# ── 5. 场景 / own / story ────────────────────────────────────────

func _check_scenario_and_story() -> void:
	var scenario_path := String(_profile.get("scenario"))
	var sc := _read_json(scenario_path)
	_ok(not sc.is_empty(), "场景 JSON 可读", scenario_path)
	var sc_ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_ok(sc_ents.size() > 0, "场景实体表非空", "n=" + str(sc_ents.size()))
	var snap: Dictionary = _session.snapshot()
	var world_ents: Array = snap.get("entities", []) if snap.get("entities") is Array else []
	_eq(world_ents.size(), sc_ents.size(), "GameSession 世界实体数 == 场景实体数")
	var world_ids: Dictionary = {}
	for raw in world_ents:
		if raw is Dictionary:
			world_ids[String((raw as Dictionary).get("id", ""))] = true
	var missing: Array = []
	for raw2 in sc_ents:
		if not (raw2 is Dictionary):
			continue
		var eid := String((raw2 as Dictionary).get("id", ""))
		if eid == "" or not world_ids.has(eid):
			missing.append(eid)
		else:
			_scenario_by_id[eid] = (raw2 as Dictionary).duplicate(true)
	_ok(missing.is_empty(), "场景每个实体都在真实 world 中", "missing=" + str(missing))
	# 接触表元数据一致性观察（不阻塞：#5 验收不要求接触层身份完整，但如实上报）。
	var contact_mismatch: Array = []
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	for raw_c in contacts:
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		var ceid := String(c.get("entity_id", ""))
		var truth2: Dictionary = _scenario_by_id.get(ceid, {})
		if truth2.is_empty():
			continue
		var tside := String(truth2.get("side", "")).to_lower()
		var cside := String(c.get("side", "")).to_lower()
		if tside in ["hostile", "neutral"] and cside != tside:
			contact_mismatch.append("%s(truth=%s,contact=%s,badge=%s)" % [
				ceid, tside, cside, String(c.get("badge", ""))])
	if contact_mismatch.is_empty():
		_info("接触表 side 与场景 truth 一致")
	else:
		_info("CONTACT SIDE MISMATCH n=%d: %s" % [contact_mismatch.size(), str(contact_mismatch)])
	var own := String(sc.get("own_entity", ""))
	_ok(own != "", "场景声明 own_entity", own)
	_eq(String(_session._seed.get("own_entity", "")), own, "session._seed.own_entity")
	_ok(world_ids.has(own), "own_entity 存在且是真实实体", own)
	# 模拟器不得有剧情状态/剧情 VM。
	_ok(_session.get("story_state") == null, "session.story_state == null（无剧情状态机）")
	_ok((_session.story_vm() as Dictionary).is_empty(), "session.story_vm() 为空（无伪造剧情 VM）")
	_ok((_binder.get("story_vm") as Dictionary).is_empty(), "binder.story_vm 为空")
	_ok(not bool(_binder.get("used_prelude")), "binder.used_prelude == false（未走序章路径）")
	var pv = _session.get("prelude")
	_info("session.prelude=" + (str(pv) if pv == null else "present"))
	# 物理世界与场景实体一一对应（位置权威层也是真实装配）。
	var phys_ids: Array = _session.physics_entity_ids()
	_eq(phys_ids.size(), sc_ents.size(), "PhysicsWorld 实体数 == 场景实体数")
	var phys_set: Dictionary = {}
	for pid0 in phys_ids:
		phys_set[String(pid0)] = true
	var phys_missing: Array = []
	for eid0 in world_ids.keys():
		if not phys_set.has(String(eid0)):
			phys_missing.append(String(eid0))
	_ok(phys_missing.is_empty(), "场景每个实体都进入 PhysicsWorld", "missing=" + str(phys_missing))


# ── 6. 拟真默认 ─────────────────────────────────────────────────

func _check_realism() -> void:
	var cs = _session.get("combat_service")
	_ok(cs != null, "combat_service 存在")
	if cs == null:
		return
	_eq(bool(cs.get("unlimited_ammo")), false, "combat_service.unlimited_ammo == false")
	_eq(bool(cs.get("auto_authorize")), false, "combat_service.auto_authorize == false")
	var vm: Dictionary = _session.combat_vm()
	var sandbox: Dictionary = vm.get("sandbox", {}) if vm.get("sandbox") is Dictionary else {}
	_eq(bool(sandbox.get("unlimited_ammo", true)), false,
		"combat_vm.sandbox.unlimited_ammo == false")
	_eq(bool(sandbox.get("auto_authorize", true)), false,
		"combat_vm.sandbox.auto_authorize == false")
	# profile 便利项：正式模拟器必须一项都不生效。
	var opts: Dictionary = _profile.get("sandbox_opts") if _profile.get("sandbox_opts") is Dictionary else {}
	_eq(opts.size(), 3, "profile.sandbox_opts 键数")
	for k in ["unlimited_ammo", "auto_authorize", "quick_restart"]:
		_eq(bool(opts.get(k, false)), false, "profile.sandbox_opts." + String(k) + " == false")
		_eq(bool(_profile.sandbox_opt(String(k), false)), false,
			"profile.sandbox_opt(" + String(k) + ") == false")
	var qr: Dictionary = _binder.quick_restart()
	_ok(not bool(qr.get("ok", true)), "binder.quick_restart() 被拒（拟真剖面无快速重开）",
		str(qr))
	_ok(String(qr.get("reason", "")) != "", "quick_restart 拒绝原因明确",
		String(qr.get("reason", "")))


# ── 7. 交通 / 港口 ──────────────────────────────────────────────

func _check_traffic_port() -> void:
	# 交通：真实 session 装配（不是 direct-fallback 空桩），真实车道/设施/OTC 数据。
	_ok(_binder.get("traffic_service") != null, "binder.traffic_service 存在")
	_ok(bool(_binder.get("traffic_ready")), "binder.traffic_ready == true",
		str(_binder.get("warnings")))
	_eq(String(_binder.get("traffic_source")), "session",
		"traffic 来源为 session（真实装配，不是 direct-fallback 桩）")
	_ok(_binder.get("traffic_service") == _session.get("traffic_control"),
		"binder.traffic_service 就是 session.traffic_control（同一真实对象）")
	var tvm: Dictionary = _binder.traffic_vm()
	_ok(not tvm.is_empty(), "binder.traffic_vm() 非空")
	var counts: Dictionary = tvm.get("counts", {}) if tvm.get("counts") is Dictionary else {}
	_ok(int(counts.get("lanes", 0)) > 0, "traffic 真实车道数据", "lanes=" + str(counts.get("lanes", 0)))
	_ok(int(counts.get("facilities", 0)) > 0, "traffic 真实设施数据",
		"facilities=" + str(counts.get("facilities", 0)))
	_ok(int(counts.get("otc", 0)) > 0, "traffic 真实 OTC 数据", "otc=" + str(counts.get("otc", 0)))
	var lane_rows: Array = _binder.traffic_lane_rows()
	_ok(lane_rows.size() > 0, "binder.traffic_lane_rows() 非空", "n=" + str(lane_rows.size()))
	_ok(_binder.traffic_otc_rows().size() > 0, "binder.traffic_otc_rows() 非空")
	if lane_rows.size() > 0:
		var lane_id := String((lane_rows[0] as Dictionary).get("lane_id",
			(lane_rows[0] as Dictionary).get("id", "")))
		var lane: Dictionary = _binder.traffic_lane(lane_id)
		_ok(not lane.is_empty(), "binder.traffic_lane('" + lane_id + "') 可查询", str(lane.keys()))
		_ok(String(lane.get("lane_id", "")) == lane_id, "traffic_lane 返回真实车道对象",
			"lane_id=" + lane_id)
		_info("traffic lane sample: lane_id=" + lane_id + " cluster=" +
			String(lane.get("cluster_id", "?")))

	# 港口：真实 session.port_service 查询（status/window/resource，非空桩）。
	var port = _session.get("port_service")
	_ok(port != null, "session.port_service 存在")
	if port == null:
		return
	_ok(bool(port.get("ready")), "session.port_service.ready == true")
	var pvm: Dictionary = port.vm()
	var ports_arr: Array = pvm.get("ports", []) if pvm.get("ports") is Array else []
	_ok(ports_arr.size() > 0, "port_service.vm().ports 非空", "n=" + str(ports_arr.size()))
	var rs: Dictionary = port.resource_summary("")
	_ok(int(rs.get("ports", 0)) > 0, "port 资源汇总有真实港口", "ports=" + str(rs.get("ports", 0)))
	_ok(int(rs.get("berths_total", 0)) > 0, "port 泊位资源非零",
		"berths_total=" + str(rs.get("berths_total", 0)))
	if ports_arr.size() > 0:
		var pid := String((ports_arr[0] as Dictionary).get("id", ""))
		var ps: Dictionary = port.port_summary(pid)
		_ok(not ps.is_empty(), "port_summary('" + pid + "') 可查询")
		var ws: Dictionary = port.window_status(pid)
		_ok(bool(ws.get("ok", false)), "window_status('" + pid + "') 可查询", str(ws))
		_info("port sample: id=" + pid + " name=" + String(ps.get("name", "?")) +
			" berths=" + str(int(rs.get("berths_total", 0))))


# ── 8. 战斗闭环 ─────────────────────────────────────────────────

func _ammo_of(weapon_id: String) -> int:
	var rows: Array = _session.combat_vm().get("weapons", []) if _session.combat_vm().get("weapons") is Array else []
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == weapon_id:
			return int((raw as Dictionary).get("ammo", -1))
	return -1


func _weapon_range(weapon_id: String) -> float:
	var rows: Array = _session.combat_service.weapons_status()
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == weapon_id:
			return float((raw as Dictionary).get("range_km", -1.0))
	return -1.0


func _solution_ready(track_id: String, weapon_id: String) -> bool:
	var rows: Array = _session.combat_vm().get("solutions", []) if _session.combat_vm().get("solutions") is Array else []
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		if String(s.get("target_id", "")) == track_id and String(s.get("weapon_id", "")) == weapon_id \
				and String(s.get("status", "")) == "READY":
			return true
	return false


func _check_combat() -> void:
	# 8.0 等待真实航迹产生（传感器 → TrackTable），有界 tick。
	var tracks: Array = _binder.get("track_vm").get("tracks", []) \
		if _binder.get("track_vm") is Dictionary else []
	var track_ticks := 0
	while tracks.is_empty() and track_ticks < MAX_TRACK_TICKS:
		_session.tick(2.0)
		_binder.refresh()
		tracks = _binder.get("track_vm").get("tracks", []) \
			if _binder.get("track_vm") is Dictionary else []
		track_ticks += 1
	_ok(not tracks.is_empty(), "传感器→航迹产生真实 track", "track_ticks=" + str(track_ticks))
	if tracks.is_empty():
		return
	# 把真实航迹注册进战斗服务（与 HUD _seed_combat_tracks 同一真实路径）。
	for raw in tracks:
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var tid := String(tr.get("track_id", tr.get("id", "")))
		if tid != "":
			_session.combat_register_track(tid, tr)
	# 从战斗服务的真实航迹里挑一个可打实体：有物理状态 + 射程内 + 真实敌对。
	# 注意：L2 融合航迹的 identity/threat 允许为 unknown/none（识别尚未完成），
	# 但目标本身必须是场景里的真实敌对实体（scenario truth side=hostile），
	# 不能拿友方/中立目标演"击毁成功"。
	var target_id := ""
	var target_entity := ""
	var weapon := ""
	var target_range := -1.0
	var target_truth: Dictionary = {}
	var diag: Array = []
	for raw2 in _session.combat_service.track_rows():
		if not (raw2 is Dictionary):
			continue
		var row: Dictionary = raw2
		var tid2 := String(row.get("id", ""))
		var threat := String(row.get("threat", ""))
		var identity := String(row.get("identity", ""))
		var eid := String(row.get("entity_id", row.get("ship_id", "")))
		var truth: Dictionary = _scenario_by_id.get(eid, {})
		var truth_side := String(truth.get("side", "")).to_lower()
		var truth_identity := String(truth.get("identity", "")).to_lower()
		var engageable := threat in ["hostile", "suspect"] or identity in ["hostile", "suspect"] \
			or truth_side in ["hostile", "suspect"] or truth_identity in ["hostile", "suspect"]
		if not engageable:
			diag.append("%s(eid=%s identity=%s threat=%s truth_side=%s)" % [tid2, eid, identity, threat, truth_side])
			continue
		var rng := float(row.get("range_km", -1.0))
		var wid := ""
		if rng >= 0.0 and rng <= _weapon_range("railgun"):
			wid = "railgun"
		elif rng >= 50.0 and rng <= _weapon_range("missile"):
			wid = "missile"
		if wid == "":
			diag.append("%s(%s out_of_range range=%.1f)" % [tid2, eid, rng])
			continue
		var pred: Dictionary = _session.combat_predict_track(tid2, wid)
		if not bool(pred.get("ok", false)):
			diag.append("%s(%s no_physics:%s)" % [tid2, wid, str(pred.get("reason", ""))])
			continue
		target_id = tid2
		target_entity = eid
		weapon = wid
		target_range = rng
		target_truth = truth
		break
	_ok(target_id != "", "从真实航迹选中可交战目标（真实敌对实体）",
		"target=%s entity=%s weapon=%s track_range=%.1fkm diag=%s" % [
			target_id, target_entity, weapon, target_range, str(diag)])
	if target_id == "":
		_info("tracks=" + str(tracks))
		return
	var chosen_side := String(target_truth.get("side", "")).to_lower()
	_ok(chosen_side in ["hostile", "suspect"], "目标实体在场景 truth 中为敌对/可疑",
		"side=" + chosen_side + " identity=" + String(target_truth.get("identity", "")))
	var chosen_track: Dictionary = _session.combat_service.track(target_id)
	_info("选定目标: track=%s fusion_identity=%s fusion_threat=%s · entity=%s truth_side=%s" % [
		target_id, String(chosen_track.get("identity", "")),
		String(chosen_track.get("threat", "")), target_entity, chosen_side])
	# 物理真相距离（开火/弹道以 PhysicsWorld 为准；航迹 range 是融合层估计）。
	var own_id := String(_session._seed.get("own_entity", ""))
	var st_own: Dictionary = _session.physics_state(own_id)
	var st_tgt: Dictionary = _session.physics_state(target_entity)
	if st_own.get("r") is Array and st_tgt.get("r") is Array:
		var r_own: Array = st_own.get("r", [])
		var r_tgt: Array = st_tgt.get("r", [])
		if r_own.size() >= 3 and r_tgt.size() >= 3:
			var truth_km := Vector3(float(r_own[0]), float(r_own[1]), float(r_own[2])).distance_to(
				Vector3(float(r_tgt[0]), float(r_tgt[1]), float(r_tgt[2])))
			_info("physics truth range %s→%s = %.1f km（航迹融合值 %.1f km）" % [
				own_id, target_entity, truth_km, target_range])
	# 目标来自 binder contacts（真实接触表）。
	var contact_ok := false
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	for rawc in contacts:
		if rawc is Dictionary and (String((rawc as Dictionary).get("entity_id", "")) == target_entity \
				or String((rawc as Dictionary).get("track_id", "")) == target_id):
			contact_ok = true
			break
	_ok(contact_ok, "目标出现在 binder.contacts 真实接触表")

	# 8.1 齐射数固定为 1，便于弹药/事件对账。
	var sal: Dictionary = _session.set_weapon_salvo(weapon, 1)
	_ok(bool(sal.get("ok", false)), "set_weapon_salvo(" + weapon + ", 1)", str(sal))
	var ammo_before := _ammo_of(weapon)
	_ok(ammo_before > 0, "开火前弹药 > 0", "ammo=" + str(ammo_before))

	# 8.2 未授权 FIRE：必须被拒 + 不耗弹（拟真关键点）。
	var unauthorized: Dictionary = _session.request_fire(target_id, weapon, true)
	_ok(not bool(unauthorized.get("ok", true)), "未授权 FIRE 被拒", str(unauthorized))
	_ok(String(unauthorized.get("reason", "")) != "", "拒绝原因非空",
		String(unauthorized.get("reason", "")))
	_eq(String(unauthorized.get("reason", "")), "needs_authorization",
		"未授权拒绝原因 == needs_authorization（ROE 授权门禁生效）")
	_eq(_ammo_of(weapon), ammo_before, "未授权拒绝不消耗弹药")

	# 8.3 TRACK → SOLUTION → tick 到 READY。
	var trk: Dictionary = _session.combat_service.request_track(target_id, true)
	_ok(bool(trk.get("ok", false)), "TRACK 真实火控请求", str(trk))
	var sol: Dictionary = _session.combat_request_solution(target_id, weapon, true)
	_ok(bool(sol.get("ok", false)), "SOLUTION 真实解算请求", str(sol))
	var sol_ticks := 0
	while sol_ticks < MAX_SOLUTION_TICKS and not _solution_ready(target_id, weapon):
		_session.tick(1.0)
		sol_ticks += 1
	_ok(_solution_ready(target_id, weapon), "解算 READY（真实 tick 推进）",
		"ticks=" + str(sol_ticks))

	# 8.4 FIRE 授权 + 真实发射。
	var grant: Dictionary = _session.grant_authorization("FIRE", "target", target_id)
	_ok(bool(grant.get("ok", false)), "grant_authorization(FIRE, target)", str(grant))
	_ok(not (_session.combat_authorization("FIRE", target_id, weapon) as Dictionary).is_empty(),
		"combat_authorization 读到真实授权")
	var fire: Dictionary = _session.request_fire(target_id, weapon, true, {"intent": "direct"})
	_ok(bool(fire.get("ok", false)), "FIRE 真实发射", str(fire.get("reason", "")))
	if not bool(fire.get("ok", false)):
		return
	_eq(String(fire.get("physics", "")), "ballistics", "开火走真实弹道（physics=ballistics）")
	_ok(not fire.has("hit") and not fire.has("miss"),
		"FIRE 返回不伪造同步命中（命中异步等 impact）", str(fire.keys()))
	var launched := int(fire.get("launched", 0))
	_ok(launched >= 1, "launched >= 1", "launched=" + str(launched))
	var pids: Array = fire.get("projectile_ids", []) if fire.get("projectile_ids") is Array else []
	_eq(pids.size(), launched, "projectile_ids 数与 launched 一致")
	_eq(String(fire.get("shooter_id", "")), String(_session._seed.get("own_entity", "")),
		"shooter 解析为 own_entity")
	_eq(String(fire.get("target_entity", "")), target_entity, "target 实体解析正确")
	var ammo_after := _ammo_of(weapon)
	_eq(ammo_after, ammo_before - launched, "弹药真实扣减（before-launched）")
	_eq(int(fire.get("ammo_left", -1)), ammo_after, "fire.ammo_left == 实时弹药余量")
	_ok(_session.combat_ballistics_active().size() >= launched, "有真实弹丸在飞",
		"active=" + str(_session.combat_ballistics_active().size()))

	# 8.5 tick 到弹道闭环（impact / miss / intercept），有界。
	var ticks := 0
	while ticks < MAX_BALLISTICS_TICKS and not _session.combat_ballistics_active().is_empty():
		_session.tick(BALLISTICS_TICK_DT)
		ticks += 1
	_ok(_session.combat_ballistics_active().is_empty(), "弹道闭环：无在飞弹",
		"ticks=%d dt=%.0f" % [ticks, BALLISTICS_TICK_DT])
	var bvm: Dictionary = _session.combat_ballistics_vm()
	var impacts: Array = _session.combat_ballistics_impacts()
	var intercepts: Array = _session.combat_ballistics_intercepts()
	var events: Array = bvm.get("events", []) if bvm.get("events") is Array else []
	var miss_events := 0
	for rawe in events:
		if rawe is Dictionary and String((rawe as Dictionary).get("kind", "")) in ["miss", "projectile_expired"]:
			miss_events += 1
	_ok(not impacts.is_empty() or not intercepts.is_empty() or miss_events > 0,
		"真实弹道结果记录存在（impact/intercept/miss，不是伪造成功）",
		"impacts=%d intercepts=%d miss=%d" % [impacts.size(), intercepts.size(), miss_events])
	var hit := false
	var damage_target := ""
	if not impacts.is_empty():
		var imp: Dictionary = impacts[0]
		hit = true
		damage_target = String(imp.get("target_id", ""))
		_ok(String(imp.get("impact_id", "")) != "", "impact 记录有 id", str(imp.get("impact_id", "")))
		_eq(String(imp.get("target_id", "")), target_entity, "impact target 与真实目标实体一致")
		_ok(float(imp.get("t", -1.0)) >= 0.0, "impact 有真实时间戳", "t=" + str(imp.get("t", -1.0)))
		_info("impact: id=%s weapon=%s miss_dist=%.4fkm proximity=%s" % [
			String(imp.get("impact_id", "")), String(imp.get("weapon_id", "")),
			float(imp.get("miss_distance_km", -1.0)), str(imp.get("proximity", false))])
	# 命中时：弹道伤害应真实路由进 DamageService（若有该舰损管模型）。
	if hit and damage_target != "":
		var dvm: Dictionary = _session.damage_ship_vm(damage_target)
		if dvm.is_empty():
			_info("DamageService 无 " + damage_target + " 模型档，跳过损管数值断言（impact 已证明真实）")
		else:
			var dsum: Dictionary = dvm.get("summary", {}) if dvm.get("summary") is Dictionary else {}
			if dsum.has("integrity_avg"):
				_ok(float(dsum.get("integrity_avg", 1.0)) < 1.0,
					"命中伤害真实进入 DamageService（integrity 下降）",
					"integrity_avg=%.4f" % float(dsum.get("integrity_avg", 1.0)))

	# 8.6 事件/弹药计数一致。
	var launch_events := 0
	for rawe2 in (_session.combat_service.events as Array):
		if rawe2 is Dictionary and String((rawe2 as Dictionary).get("kind", "")) == "weapon_launch":
			launch_events += 1
	_ok(launch_events >= 1, "combat_service 有 weapon_launch 真实事件", "n=" + str(launch_events))
	_eq(launch_events, launched, "weapon_launch 事件数 == launched")
	_ok(int((bvm.get("counts", {}) as Dictionary).get("projectiles", 0)) >= launched,
		"弹道服务 projectile 计数 >= launched",
		"projectiles=" + str(int((bvm.get("counts", {}) as Dictionary).get("projectiles", 0))))
	var live_track: Dictionary = _session.combat_service.track(target_id)
	_info("战后航迹: damaged=" + str(float(live_track.get("damage_taken", 0.0))) + " destroyed=" +
		str(bool(live_track.get("destroyed", false))))
