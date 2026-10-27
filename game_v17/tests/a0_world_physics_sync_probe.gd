extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A0-T1 (Issue #2.2) · WorldState 位置副本 vs PhysicsWorld 权威
#
# 真实入口：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
# 验证「PhysicsWorld 是运行时位置/速度唯一写入者；tick 边界把只读副本同步给
# WorldState；对外 snapshot 与 physics 来自同一仿真时刻」。
#
# 断言组：
#   1) 真实入口 + physics/world 实体清点（scenario 7 实体）；
#   2) boot 时 world 副本 == physics（同一 seed）；
#   3) 多次 tick 后 snapshot().entities 位置/速度 == physics 同一时刻（容差 1e-9 km）；
#      世界副本不再是 seed 旧值（反证 C3）；
#   4) 坐标系/单位/容差：bary_rot、km、km/s、量级 sanity；
#   5) 消费者：plot_positions() 走 physics；存档 save→load 后 snapshot 与 physics 一致；
#   6) 单向性：手写 world 位置不反向覆盖 physics，下一次 tick 副本自愈；
#   7) 确定性：无 tick 的重复 snapshot 完全一致（同步不重复推进/不抖动）。
#
# Red-first：修复前 WorldState 位置副本在 tick 中永不更新，本探针 FAIL。
# Output: `A0-T1 WORLD PHYSICS SYNC PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"
const GameSessionScript := preload("res://scripts/core/game_session.gd")

const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
const MAX_BINDER_FRAMES := 120
const WATCHDOG_S := 180.0

const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

const FRAME := "bary_rot"
const TICK_DT := 60.0
const TICK_COUNT := 10
# 位置/速度副本必须逐位一致（同一 double 复制），容差仅吸收 JSON/序列化路径噪声。
const POS_TOL_KM := 1.0e-9
const VEL_TOL_KMPS := 1.0e-12
const TIME_TOL_S := 1.0e-6
const MOVE_EPS_KM := 1.0

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _hud = null
var _binder = null
var _session = null
var _truth: Dictionary = {}
var _main_menu_instantiated := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-T1 WORLD PHYSICS SYNC PROBE · real entry main_menu → v1_hud")
	print("Godot ", Engine.get_version_info().get("string", "?"), " · profile=", TARGET_PROFILE)
	print("════════════════════════════════════════════════════════════════")
	_setup_env()
	node_added.connect(_on_node_added)
	_watchdog()
	_run()


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	var scr = node.get_script()
	if scr != null and String(scr.resource_path) == "res://scripts/ui/main_menu.gd":
		_main_menu_instantiated = true


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-T1] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _setup_env() -> void:
	for k in ENV_KEYS:
		_env_backup[k] = OS.get_environment(k)
	OS.set_environment("DSH_BUILD", TARGET_PROFILE)
	for k in ["DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE", "DSH_V1_TEST",
			"DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
			"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]:
		OS.set_environment(k, "")


func _restore_env() -> void:
	for k in ENV_KEYS:
		var v := String(_env_backup.get(k, ""))
		if v == "":
			OS.unset_environment(k)
		else:
			OS.set_environment(k, v)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("A0-T1 WORLD PHYSICS SYNC PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T1] FAILED: ", f)
		print("A0-T1 WORLD PHYSICS SYNC PROBE FAILED")
	else:
		print("A0-T1 WORLD PHYSICS SYNC PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-T1] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-T1] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-T1] STEP ", title)


func _info(text: String) -> void:
	print("[A0-T1] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. real entry main_menu → v1_hud (change_scene_to_file)")
	var err := change_scene_to_file(MAIN_MENU)
	_ok(err == OK, "change_scene_to_file(main_menu) == OK", "err=%d" % err)
	if err != OK:
		_finish()
		return
	var boot := await _await_v1_hud()
	if boot["hud"] == null:
		_finish()
		return
	_hud = boot["hud"]
	_ok(bool(boot["saw_main_menu"]), "real entry passed main_menu",
		"saw=%s frames=%d" % [str(boot["saw_main_menu"]), int(boot["frames"])])
	_ok(bool(boot["scene_script_ok"]), "current_scene is V1HUD with v1_hud.gd",
		String(_hud.scene_file_path))
	_binder = _hud.get("binder")
	_session = _binder.get("session") if _binder != null else null
	_ok(_binder != null and bool(_binder.get("ready")), "ShellBinder ready")
	_ok(_session != null, "GameSession available")
	if _session == null:
		_finish()
		return
	_ok(_session.physics_world_service != null, "PhysicsWorld enabled in orbital_sim")
	if _session.physics_world_service == null:
		_finish()
		return

	_step("2. scenario entities are present in PhysicsWorld and WorldState")
	var sc := _read_json(TARGET_SCENARIO)
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_eq(ents.size(), 7, "scenario entity count")
	for raw in ents:
		if raw is Dictionary:
			_truth[String((raw as Dictionary).get("id", ""))] = (raw as Dictionary).duplicate(true)
	var phys_ids: Array = _session.physics_entity_ids()
	var world_ids: Array = _world_ids()
	_ok(phys_ids.size() >= 7, "PhysicsWorld entity count >= 7", "n=" + str(phys_ids.size()))
	for eid in _truth.keys():
		_ok(eid in phys_ids, "physics has scenario entity: " + eid)
		_ok(eid in world_ids, "world has scenario entity: " + eid)

	_step("3. boot: world position copy == physics (same seed, same frame)")
	var mismatch_boot: Array = _compare_all()
	_ok(mismatch_boot.is_empty(), "boot world copy matches physics",
		"mismatches=" + str(mismatch_boot))
	var st0: Dictionary = _session.physics_state("apsis")
	_eq(String(st0.get("frame", "")), FRAME, "physics_state frame is bary_rot")
	var units: Dictionary = _session.physics_world_service.units()
	_eq(String(units.get("length", "")), "km", "physics length unit km")
	_eq(String(units.get("time", "")), "s", "physics time unit s")
	_eq(String(units.get("velocity", "")), "km/s", "physics velocity unit km/s")

	_step("4. after %d ticks: snapshot positions/velocities == physics same instant" % TICK_COUNT)
	var seed_pos: Dictionary = {}
	for eid in _truth.keys():
		seed_pos[eid] = _physics_r(eid)
	var t_before: float = _session.now_s()
	var world_version_before: int = _world_version()
	var first_sync: Dictionary = {}
	for i in range(TICK_COUNT):
		var tk: Dictionary = _session.tick(TICK_DT)
		_ok(bool(tk.get("ok", false)), "tick %d ok" % (i + 1),
			"reason=" + String(tk.get("reason", "")))
		if i == 0:
			first_sync = tk.get("world_sync", {}) if tk.get("world_sync") is Dictionary else {}
	_near(_session.now_s(), t_before + TICK_DT * float(TICK_COUNT), TIME_TOL_S,
		"session time advanced by ticks")
	_near(float(_session.physics_world_service.t), _session.now_s(), TIME_TOL_S,
		"physics time == session time")

	_step("4a. a tick that really syncs: updated entities vs post-sync mismatch are distinct")
	# 审查修正：成功写回的实体进 updated，mismatched 只表示同步后仍未对齐的对象。
	_ok(not first_sync.is_empty(), "first tick returns world_sync段",
		"keys=" + str(first_sync.keys()))
	_eq(String(first_sync.get("reason", "")), "tick", "world_sync reason=tick")
	_eq(bool(first_sync.get("enabled", false)), true, "world_sync enabled")
	var upd: Array = first_sync.get("updated", []) if first_sync.get("updated") is Array else []
	_ok(upd.size() > 0, "tick actually synced entities (updated non-empty)",
		"updated=" + str(upd))
	_eq(int(first_sync.get("synced", -1)), upd.size(),
		"synced count == updated count")
	_ok(_truth.size() >= upd.size(), "updated entities are a subset of world entities",
		"updated=%d world=%d" % [upd.size(), _truth.size()])
	for eid in upd:
		_ok(_truth.has(String(eid)), "updated entity is a known scenario entity: " + String(eid))
	var post_mismatch: Array = first_sync.get("mismatched", []) \
		if first_sync.get("mismatched") is Array else []
	_ok(post_mismatch.is_empty(),
		"mismatched is EMPTY after a successful sync (post-sync semantics)",
		"mismatched=" + str(post_mismatch))
	_eq(bool(first_sync.get("in_sync", false)), true, "first tick in_sync=true")
	_eq(int(first_sync.get("compared", 0)), _truth.size(),
		"first tick compared all scenario entities")
	# 反例保护：updated 与 mismatched 不得含同一实体（旧实现把已修复实体塞进 mismatched）。
	var overlap: Array = []
	for eid in upd:
		if String(eid) in post_mismatch:
			overlap.append(String(eid))
	_ok(overlap.is_empty(), "updated and mismatched are disjoint", str(overlap))
	# 后续 tick（已对齐）应报告 0 更新且仍 in_sync —— 语义稳定。
	var idle_tick: Dictionary = _session.tick(0.0)
	var idle_sync: Dictionary = idle_tick.get("world_sync", {}) \
		if idle_tick.get("world_sync") is Dictionary else {}
	var idle_upd: Array = idle_sync.get("updated", []) if idle_sync.get("updated") is Array else []
	_ok(idle_upd.is_empty(), "no-op tick reports no updated entities", str(idle_upd))
	_ok(bool(idle_sync.get("in_sync", false)), "no-op tick stays in_sync")

	# 同步状态（A0-T1 新 API；修复前不存在 → has_method=false 会走 FAIL 分支）
	_ok(_session.has_method("world_physics_sync_status"),
		"GameSession.world_physics_sync_status() API exists")
	var status: Dictionary = _session.call("world_physics_sync_status") \
		if _session.has_method("world_physics_sync_status") else {}
	_ok(bool(status.get("enabled", false)), "world/physics sync enabled", str(status))
	_ok(bool(status.get("in_sync", false)), "world copy in sync with physics",
		"mismatched=" + str(status.get("mismatched", [])))
	_eq(int(status.get("compared", 0)), _truth.size(), "sync compares all scenario entities")
	_eq(String(status.get("frame", "")), FRAME, "sync frame bary_rot")
	# 核心断言：对外 snapshot 与 physics 同一时刻、同一数值。
	var mismatch_tick: Array = _compare_all()
	_ok(mismatch_tick.is_empty(), "snapshot().entities == physics after ticks",
		"mismatches=" + str(mismatch_tick))
	# 反证 C3：harmattan 在 600 s 内应移动约 12 km，旧实现副本仍是 seed 值。
	var moved := _dist_km(_physics_r("harmattan"), seed_pos["harmattan"])
	_ok(moved > MOVE_EPS_KM, "physics entity actually moved", "harmattan moved_km=%.6f" % moved)
	var snap_row: Dictionary = _snapshot_entity("harmattan")
	_ok(not snap_row.is_empty(), "snapshot row exists: harmattan")
	if not snap_row.is_empty():
		var snap_pos: Array = snap_row.get("pos_km", []) if snap_row.get("pos_km") is Array else []
		_ok(_dist_km(snap_pos, seed_pos["harmattan"]) > MOVE_EPS_KM,
			"snapshot position is current, not stale seed copy",
			"snap=%s seed=%s" % [str(snap_pos), str(seed_pos["harmattan"])])
	# 副本确实被写入：world version 单调增长（tick 边界同步事件）
	_ok(_world_version() > world_version_before, "world version advanced by tick sync",
		"before=%d after=%d" % [world_version_before, _world_version()])
	# 来源标记：world event_refs 由 physics_world 写入
	var last_sources: Array = []
	var refs: Array = _world_event_refs()
	for i in range(maxi(0, refs.size() - 3), refs.size()):
		if refs[i] is Dictionary:
			last_sources.append(String((refs[i] as Dictionary).get("source", "")))
	_ok("physics_world" in last_sources, "world copy written by physics_world source",
		"sources=" + str(last_sources))
	# 坐标系/量级 sanity：同一 bary_rot、km 量级、速度合理。
	for eid in ["apsis", "harmattan"]:
		var r: Array = _physics_r(eid)
		var v: Array = _physics_v(eid)
		_ok(_norm_km(r) > 1.0e4 and _norm_km(r) < 1.0e6,
			"position magnitude is cislunar km: " + eid, "|r|=%.1f km" % _norm_km(r))
		_ok(_norm_km(v) < 100.0, "velocity magnitude is km/s scale: " + eid,
			"|v|=%.6f km/s" % _norm_km(v))

	_step("5. internal authority: PhysicsWorld→WorldState 同刻；玩家 plot 另按 owner 情报验边界")
	# 内部权威强度不变：完整 7 实体、同刻位置/速度保持在步骤 3/4 已断言；
	# 这里补「内部消费者」与「玩家可见」分离的等强度断言。
	var internal_pos: Dictionary = _session.physics_positions("bary_rot") \
		if _session != null and _session.has_method("physics_positions") else {}
	_ok(internal_pos.size() >= _truth.size(),
		"internal physics_positions covers all scenario entities",
		"n=" + str(internal_pos.size()))
	if _binder != null and _binder.has_method("plot_positions"):
		var pp: Dictionary = _binder.call("plot_positions")
		# 旧契约要求玩家 plot 直读 physics；新合同下玩家 plot 只来自本舰 owner 情报。
		_eq(String(pp.get("source", "")), "intel", "player plot source=intel")
		var rows: Array = pp.get("positions", []) if pp.get("positions") is Array else []
		# 无观测时允许为空；有行时每行必须能追溯到该 owner 的合法观测航迹。
		var owner_id := ""
		if _binder.has_method("_intel_owner"):
			owner_id = String(_binder.call("_intel_owner"))
		var owner_view: Dictionary = _session.intel_view(owner_id) \
			if _session != null and _session.has_method("intel_view") else {}
		var owned: Dictionary = {}
		for raw_tr in (owner_view.get("tracks", []) as Array):
			if raw_tr is Dictionary:
				owned[String((raw_tr as Dictionary).get("id", ""))] = raw_tr
		var unmapped: Array = []
		for raw_p in rows:
			if not (raw_p is Dictionary):
				continue
			var pr: Dictionary = raw_p
			var tid := String(pr.get("id", ""))
			var tr: Dictionary = owned.get(tid, {}) if owned.get(tid) is Dictionary else {}
			if tr.is_empty():
				unmapped.append(tid)
				continue
			var p1: Array = pr.get("pos_km", []) if pr.get("pos_km") is Array else []
			var p2: Array = tr.get("pos_km", []) if tr.get("pos_km") is Array else []
			if p1.size() >= 3 and p2.size() >= 3 \
					and not _vec_near(p1, p2, POS_TOL_KM):
				unmapped.append(tid + ":pos")
			if absf(float(pr.get("observed_t", -1.0))
					- float(tr.get("last_observed_t", -2.0))) > 1.0e-6:
				unmapped.append(tid + ":t")
		_ok(unmapped.is_empty(),
			"every player plot point maps to its owner's approved observation",
			str(unmapped))
		# T2：选真实存在且该 owner 已获合法观测的**同一目标**（harmattan）做隐藏移动对照
		var p0: Array = _physics_r("harmattan")
		var obs: Dictionary = _session.receive_intel_observation(owner_id, {
			"observation_id": "OBS-WS-1", "observer_id": String(
				_session.own_entity_id()) if _session.has_method("own_entity_id") else "apsis",
			"target_id": "harmattan", "sensor": "radar", "source": "radar",
			"observed_t": float(_session.now_s()), "quality": 0.9,
			"range_km": 500.0, "bearing_deg": 90.0, "pos_km": p0})
		_ok(bool(obs.get("ok", false)), "legit owner observation accepted",
			str(obs.get("reason", "")))
		var pp2: Dictionary = _binder.call("plot_positions")
		var got: Dictionary = {}
		for raw_p2 in (pp2.get("positions", []) as Array):
			if raw_p2 is Dictionary:
				got[String((raw_p2 as Dictionary).get("id", ""))] = raw_p2
		var wrow: Dictionary = got.get("harmattan", {}) if got.get("harmattan") is Dictionary else {}
		var wpos: Array = wrow.get("pos_km", []) if wrow.get("pos_km") is Array else []
		var obs_t0 := float(wrow.get("observed_t", -1.0))
		_ok(_vec_near(wpos, p0, POS_TOL_KM),
			"player plot reflects the newly observed position", str(wpos))
		# 实际变更**同一目标**隐藏真值；先证明 truth/physics 都真的变了
		var p1: Array = [999.0, 1234.0, 77.0]
		var mut: Dictionary = {}
		if _session != null and _session.has_method("_apply_hidden_truth_mutation"):
			mut = _session.call("_apply_hidden_truth_mutation", "harmattan",
				"hidden_ws", p1)
		_ok(bool(mut.get("truth_changed", false)),
			"hidden mutation actually changed the compared target",
			JSON.stringify(mut.get("before", {})).substr(0, 120))
		_ok(bool(mut.get("physics_changed", false)),
			"hidden mutation changed PhysicsWorld (not just a world copy)")
		var ph1: Array = _physics_r("harmattan")
		_ok(_vec_near(ph1, p1, POS_TOL_KM),
			"physics now holds the mutated coordinate", str(ph1))
		var pp3: Dictionary = _binder.call("plot_positions")
		var now_pos: Dictionary = {}
		for raw_p3 in (pp3.get("positions", []) as Array):
			if raw_p3 is Dictionary:
				now_pos[String((raw_p3 as Dictionary).get("id", ""))] = raw_p3
		var wrow3: Dictionary = now_pos.get("harmattan", {}) if now_pos.get("harmattan") is Dictionary else {}
		var wpos3: Array = wrow3.get("pos_km", []) if wrow3.get("pos_km") is Array else []
		_ok(_vec_near(wpos3, p0, POS_TOL_KM),
			"player plot does not follow hidden physics motion without new observation",
			str(wpos3))
		_ok(absf(float(wrow3.get("observed_t", -2.0)) - obs_t0) <= 1.0e-9,
			"player plot keeps the old sampling time until a new observation")
		# 合法新观测到达 → 同一目标位置/时间确实更新（防止永远冻结）
		_session.tick(TICK_DT)
		var obs2: Dictionary = _session.receive_intel_observation(owner_id, {
			"observation_id": "OBS-WS-2", "observer_id": String(
				_session.own_entity_id()) if _session.has_method("own_entity_id") else "apsis",
			"target_id": "harmattan", "sensor": "radar", "source": "radar",
			"observed_t": float(_session.now_s()), "quality": 0.9,
			"range_km": 3.0, "bearing_deg": 0.0, "pos_km": p1})
		_ok(bool(obs2.get("ok", false)), "second legit observation accepted",
			str(obs2.get("reason", "")))
		var pp4: Dictionary = _binder.call("plot_positions")
		var got4: Dictionary = {}
		for raw_p4 in (pp4.get("positions", []) as Array):
			if raw_p4 is Dictionary:
				got4[String((raw_p4 as Dictionary).get("id", ""))] = raw_p4
		var wrow4: Dictionary = got4.get("harmattan", {}) if got4.get("harmattan") is Dictionary else {}
		var wpos4: Array = wrow4.get("pos_km", []) if wrow4.get("pos_km") is Array else []
		_ok(_vec_near(wpos4, p1, POS_TOL_KM),
			"player plot updates for the same target after a legit new observation",
			str(wpos4))
		_ok(float(wrow4.get("observed_t", -1.0)) > obs_t0,
			"player plot sampling time advanced after the new observation",
			str(wrow4.get("observed_t", null)))
	else:
		_ok(false, "ShellBinder.plot_positions() exists")

	_step("6. consumer: save → load restores world copy at the same physics instant")
	# 用同一 scenario seed 起一个独立 session 做存档往返：HUD 实例上带 comms 种子
	# 路由，重放 send_comms 会命中与本任务无关的既有 replay 限制（记录为 NOT RUN 项），
	# 这里只验证「存档里的 world 副本 == 恢复后的 physics == 保存前 physics」。
	var sv = GameSessionScript.new({
		"entities": sc.get("entities", []),
		"physics_world": true, "seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"own_entity": String(sc.get("own_entity", "apsis")),
	})
	_ok(bool(sv.ready), "save/load fixture session ready", str(sv.errors))
	for i in range(3):
		sv.tick(TICK_DT)
	var pre_save: Dictionary = {}
	for eid in _truth.keys():
		pre_save[eid] = _physics_r_in(sv, String(eid))
	var save_text: String = sv.save_state()
	_ok(save_text.length() > 500, "save_state non-empty", "len=%d" % save_text.length())
	var pre_save_after: Dictionary = {}
	for eid in _truth.keys():
		pre_save_after[eid] = _physics_r_in(sv, String(eid))
	var s2 = GameSessionScript.new()
	var lr: Dictionary = s2.load_state(save_text)
	_ok(bool(lr.get("ok", false)), "load_state ok", "reason=" + String(lr.get("reason", "")))
	_ok(s2.physics_world_service != null, "loaded session has PhysicsWorld")
	if s2.physics_world_service != null:
		_near(float(s2.physics_world_service.t), s2.now_s(), TIME_TOL_S,
			"loaded physics time == loaded session time")
		var mism: Array = []
		for eid in _truth.keys():
			var sr: Dictionary = _snapshot_entity_in(s2, String(eid))
			var pr: Array = _physics_r_in(s2, String(eid))
			var spos: Array = sr.get("pos_km", []) if sr.get("pos_km") is Array else []
			if not _vec_near(spos, pr, POS_TOL_KM):
				mism.append({"id": eid, "snap": spos, "physics": pr})
			if not _vec_near(spos, pre_save_after[eid], POS_TOL_KM):
				mism.append({"id": eid, "snap": spos, "pre_save": pre_save_after[eid]})
		_ok(mism.is_empty(), "loaded snapshot positions == restored physics == pre-save",
			"mismatches=" + str(mism))
		var st_sync: Dictionary = s2.call("world_physics_sync_status") \
			if s2.has_method("world_physics_sync_status") else {}
		_ok(bool(st_sync.get("in_sync", false)), "loaded session world copy in sync",
			str(st_sync.get("mismatched", [])))
	# 保存前后 physics 未被存档流程推进（save_state 只读序列化，不 step）
	var drift: Array = []
	for eid in _truth.keys():
		if not _vec_near(pre_save_after[eid], pre_save[eid], POS_TOL_KM):
			drift.append(eid)
	_ok(drift.is_empty(), "save does not advance physics time/state", str(drift))

	_step("7. one-way authority: world write never overrides physics; next tick heals copy")
	var phys_before: Array = _physics_r("harmattan")
	var manual: Dictionary = _session.world.apply({"type": "entity.move",
		"t": _session.now_s(), "source": "probe_manual",
		"target": "harmattan", "payload": {"pos_km": [0.0, 0.0, 0.0]}},
		String(_session.writer))
	_ok(bool(manual.get("ok", false)), "manual world move accepted (single writer)",
		"reason=" + String(manual.get("reason", "")))
	_ok(_vec_near(_physics_r("harmattan"), phys_before, POS_TOL_KM),
		"manual world write does NOT change physics (no reverse overwrite)",
		"physics=%s before=%s" % [str(_physics_r("harmattan")), str(phys_before)])
	var st_div: Dictionary = _session.call("world_physics_sync_status") \
		if _session.has_method("world_physics_sync_status") else {}
	_ok(not bool(st_div.get("in_sync", true)), "sync status detects divergence",
		str(st_div.get("mismatched", [])))
	_session.tick(0.0)
	var healed_snap: Array = _snapshot_entity("harmattan").get("pos_km", []) \
		if _snapshot_entity("harmattan").get("pos_km", []) is Array else []
	_ok(_vec_near(_physics_r("harmattan"), phys_before, POS_TOL_KM),
		"zero tick keeps physics authoritative",
		"physics=%s before=%s" % [str(_physics_r("harmattan")), str(phys_before)])
	_ok(_vec_near(healed_snap, _physics_r("harmattan"), POS_TOL_KM),
		"tick boundary heals world copy from physics",
		"snap=%s physics=%s" % [str(healed_snap), str(_physics_r("harmattan"))])

	_step("8. frame gate: converted-frame session (L1 seed) is NOT auto-synced")
	# 序章/prelude seed 会把 L1 局部坐标 + offset 转成 bary_rot（A0 C8）；世界副本
	# 仍是 L1 局部语义，两者不是同一坐标空间 → 本任务必须显式不同步并记录原因。
	var prelude_like = GameSessionScript.new({
		"physics_world": true,
		"prelude": {"scenario": "probe_frame_gate"},
		"seed_frame": "l1", "frame_origin": "l1",
		"entities": [
			{"id": "apsis", "kind": "ship", "name": "APSIS",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "name": "HAMATTAN",
				"pos_km": [20.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}],
	})
	_ok(bool(prelude_like.ready), "converted-frame session ready",
		str(prelude_like.errors))
	_eq(bool(prelude_like.physics_frame_meta().get("applied", false)), true,
		"converted-frame seed applied L1 offset")
	var gate: Dictionary = prelude_like.call("world_physics_sync_status") \
		if prelude_like.has_method("world_physics_sync_status") else {}
	_eq(bool(gate.get("enabled", true)), false, "converted-frame sync disabled")
	_eq(String(gate.get("reason", "")), "frame_mismatch", "converted-frame sync reason")
	var pre_world_pos: Array = prelude_like.world.entity("apsis").get("pos_km", [])
	prelude_like.tick(120.0)
	var post_world_pos: Array = prelude_like.world.entity("apsis").get("pos_km", [])
	_ok(_vec_near(post_world_pos, pre_world_pos, POS_TOL_KM),
		"converted-frame world copy untouched (no cross-frame corruption)",
		"before=%s after=%s" % [str(pre_world_pos), str(post_world_pos)])
	var pre_phys: Array = prelude_like.physics_state("apsis").get("r", [])
	_ok(_norm_km(pre_phys) > 1.0e5, "converted-frame physics is bary_rot scale",
		"|r|=%.1f km" % _norm_km(pre_phys))
	_ok(not _vec_near(pre_phys, post_world_pos, 1.0),
		"converted-frame physics and world copy are different spaces (documented gap)")

	_step("9. determinism: repeated snapshot without tick is identical")
	var snap_a := JSON.stringify(_session.snapshot())
	var snap_b := JSON.stringify(_session.snapshot())
	_ok(snap_a == snap_b, "repeated snapshot identical (sync does not drift)",
		"len_a=%d len_b=%d" % [snap_a.length(), snap_b.length()])

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _await_v1_hud() -> Dictionary:
	var frames := 0
	var saw_main_menu := false
	var scene_script_ok := false
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
			continue
		var hud = cs
		var f2 := 0
		while f2 < MAX_BINDER_FRAMES:
			var b = hud.get("binder")
			if b != null and bool(b.get("ready")):
				break
			await process_frame
			f2 += 1
		var scr = hud.get_script()
		var script_path := ""
		if scr != null:
			script_path = String(scr.resource_path)
		scene_script_ok = script_path == HUD_SCRIPT and String(hud.name) == HUD_NODE
		return {"hud": hud, "frames": frames,
			"saw_main_menu": saw_main_menu or _main_menu_instantiated,
			"scene_script_ok": scene_script_ok,
			"elapsed_ms": Time.get_ticks_msec() - t0}
	print("[A0-T1] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}


func _snapshot_entity(eid: String) -> Dictionary:
	return _snapshot_entity_in(_session, eid)


func _snapshot_entity_in(sess, eid: String) -> Dictionary:
	var snap: Dictionary = sess.snapshot() if sess != null else {}
	for raw in (snap.get("entities", []) if snap.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == eid:
			return raw
	return {}


func _world_ids() -> Array:
	var out: Array = []
	for raw in (_session.world.entities_sorted() if _session != null and _session.world != null else []):
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("id", "")))
	return out


func _world_version() -> int:
	return int(_session.world.version) if _session != null and _session.world != null else 0


func _world_event_refs() -> Array:
	return _session.world.event_refs if _session != null and _session.world != null else []


func _physics_state(eid: String) -> Dictionary:
	return _session.physics_state(eid) if _session != null else {}


func _physics_r(eid: String) -> Array:
	return _physics_r_in(_session, eid)


func _physics_r_in(sess, eid: String) -> Array:
	if sess == null:
		return []
	var st: Dictionary = sess.physics_state(eid)
	var r = st.get("r", [])
	return (r as Array).duplicate() if r is Array else []


func _physics_v(eid: String) -> Array:
	if _session == null:
		return []
	var st: Dictionary = _session.physics_state(eid)
	var v = st.get("v", [])
	return (v as Array).duplicate() if v is Array else []


func _compare_all() -> Array:
	var out: Array = []
	for eid in _truth.keys():
		var snap: Dictionary = _snapshot_entity(String(eid))
		var spos: Array = snap.get("pos_km", []) if snap.get("pos_km") is Array else []
		var svel: Array = snap.get("vel_kmps", []) if snap.get("vel_kmps") is Array else []
		var pr: Array = _physics_r(String(eid))
		var pv: Array = _physics_v(String(eid))
		if not _vec_near(spos, pr, POS_TOL_KM):
			out.append({"id": eid, "field": "pos_km", "snap": spos, "physics": pr})
		if not _vec_near(svel, pv, VEL_TOL_KMPS):
			out.append({"id": eid, "field": "vel_kmps", "snap": svel, "physics": pv})
	return out


func _vec_near(a: Array, b: Array, tol: float) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	for i in range(3):
		if absf(float(a[i]) - float(b[i])) > tol:
			return false
	return true


func _sub3(a: Array, b: Array) -> Array:
	if a.size() < 3 or b.size() < 3:
		return []
	return [float(a[0]) - float(b[0]), float(a[1]) - float(b[1]), float(a[2]) - float(b[2])]


func _dist_km(a: Array, b: Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return -1.0
	var dx := float(a[0]) - float(b[0])
	var dy := float(a[1]) - float(b[1])
	var dz := float(a[2]) - float(b[2])
	return sqrt(dx * dx + dy * dy + dz * dz)


func _norm_km(v: Array) -> float:
	if v.size() < 3:
		return -1.0
	return sqrt(float(v[0]) * float(v[0]) + float(v[1]) * float(v[1])
		+ float(v[2]) * float(v[2]))
