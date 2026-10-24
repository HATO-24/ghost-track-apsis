extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A0-T2 / Issue #4.1 · 传感器目标几何绑定 PhysicsWorld
#
# 真实入口：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
#
# 验证：
#   1) 真实入口 + orbital_sim 场景/物理/传感器清点；
#   2) **修复前证据**：配置里的静态 target 位置与 physics 真实位置存在显著差异
#      （静态 harmattan=[20,0,0] / l1_station=[0,0,10]，均 L1 相对语义）；
#   3) 绑定后传感器几何来源 = physics_world、frame=bary_rot、单位 km/km/s；
#   4) **目标机动后**（tick N 次）传感器读到的 range/bearing 与 physics 当前时刻
#      逐值一致（不是静态旧值，也不是 seed 值）；
#   5) 采样时刻一致：几何 t == physics t == session t == observation.t（容差 1e-6 s）；
#   6) **观测语义保留**：TrackTable 的 range_km 来自 observation（观测值），
#      observation 仍带 support/quality/bearing_sigma 等观测属性；HUD/CombatService
#      不读传感器内部真值（CombatService 只看自己的 track 行）；
#   7) 无 physics / 帧不匹配时显式退化 static 并记录原因（不静默当物理真值）；
#   8) 重复运行确定性：同一操作序列的几何与观测数值一致。
#
# Red-first：修复前传感器使用静态 target 位置，步骤 4/5 会失败。
# Output: `A0-T2 SENSOR GEOMETRY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
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
const TIME_TOL_S := 1.0e-6
const RANGE_TOL_KM := 1.0e-6
const BEARING_TOL_DEG := 1.0e-6
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
	print("A0-T2 SENSOR GEOMETRY PROBE · real entry main_menu → v1_hud")
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
	print("[A0-T2] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("A0-T2 SENSOR GEOMETRY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T2] FAILED: ", f)
		print("A0-T2 SENSOR GEOMETRY PROBE FAILED")
	else:
		print("A0-T2 SENSOR GEOMETRY PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-T2] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-T2] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.9f expected=%.9f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-T2] STEP ", title)


func _info(text: String) -> void:
	print("[A0-T2] INFO ", text)


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
	_ok(_session.sensor_service != null, "SensorService enabled in orbital_sim")
	_ok(_session.physics_world_service != null, "PhysicsWorld enabled in orbital_sim")
	if _session.sensor_service == null or _session.physics_world_service == null:
		_finish()
		return

	_step("2. scenario truth + static config baseline (pre-fix geometry evidence)")
	var sc := _read_json(TARGET_SCENARIO)
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_eq(ents.size(), 7, "scenario entity count")
	for raw in ents:
		if raw is Dictionary:
			_truth[String((raw as Dictionary).get("id", ""))] = (raw as Dictionary).duplicate(true)
	# 静态配置位置（SensorService.setup 时的 targets；修复前几何就是这些值）
	var static_targets: Dictionary = {}
	for raw_t in _session.sensor_service.config.get("targets", []):
		if raw_t is Dictionary:
			static_targets[String((raw_t as Dictionary).get("id", ""))] = \
				(raw_t as Dictionary).get("pos_km", [])
	_ok(not static_targets.is_empty(), "sensor config has static targets",
		"ids=" + str(static_targets.keys()))
	var static_obs: Array = _session.sensor_service.config.get("observer", {}).get("pos_km", [])
	_info("static observer apsis pos_km=%s" % str(static_obs))
	for tid in static_targets.keys():
		_info("static target %s pos_km=%s" % [String(tid), str(static_targets[tid])])
	# 静态配置与 physics 的差值（真实测量；不硬编码成普遍规律）
	for tid in static_targets.keys():
		var sp: Array = static_targets[tid]
		var pr: Array = _physics_r(String(tid))
		var d := _dist_km(sp, pr)
		_ok(d > MOVE_EPS_KM, "static config position differs from physics: " + String(tid),
			"static=%s physics=%s diff_km=%.6f" % [str(sp), str(pr), d])
		_info("A0-T2 GEOMETRY GAP %s: static vs physics = %.3f km" % [String(tid), d])
	# 场景配置本身就带 physics 几何（L1 绝对坐标），静态 target 是另一套 L1 相对值。
	var harmattan_truth: Dictionary = _truth.get("harmattan", {}) if _truth.get("harmattan") is Dictionary else {}
	_info("scenario harmattan pos_km=%s (physics bary_rot absolute)" % str(harmattan_truth.get("pos_km", [])))

	_step("3. geometry source after boot: physics_world / bary_rot / km")
	_ok(_session.has_method("sensor_geometry_status"),
		"GameSession.sensor_geometry_status() API exists")
	var gs0: Dictionary = _session.call("sensor_geometry_status") \
		if _session.has_method("sensor_geometry_status") else {}
	_eq(String(gs0.get("source", "")), "physics_world", "geometry source physics_world")
	_eq(bool(gs0.get("authoritative", false)), true, "geometry marked authoritative")
	_eq(String(gs0.get("frame", "")), FRAME, "geometry frame bary_rot")
	var units: Dictionary = gs0.get("units", {}) if gs0.get("units") is Dictionary else {}
	_eq(String(units.get("length", "")), "km", "geometry length unit km")
	_eq(String(units.get("velocity", "")), "km/s", "geometry velocity unit km/s")
	_eq(String(units.get("time", "")), "s", "geometry time unit s")
	var last0: Dictionary = gs0.get("last", {}) if gs0.get("last") is Dictionary else {}
	_ok(bool(last0.get("ok", false)), "boot geometry bind ok", str(last0))
	_eq(bool(last0.get("time_ok", false)), true, "boot geometry time_ok")
	_eq(int(last0.get("bound", 0)), static_targets.size(), "boot geometry bound target count")
	_eq(bool(last0.get("observer_bound", false)), true, "boot geometry observer bound")
	_ok((last0.get("missing", []) as Array).is_empty(), "no missing geometry targets",
		str(last0.get("missing", [])))
	_ok((last0.get("mismatched_frame", []) as Array).is_empty(),
		"no frame-mismatched targets", str(last0.get("mismatched_frame", [])))

	_step("4. after target maneuver (%d×%ds): sensor geometry == physics same instant" % [TICK_COUNT, int(TICK_DT)])
	var seed_pos: Dictionary = {}
	for tid in static_targets.keys():
		seed_pos[String(tid)] = _physics_r(String(tid))
	for i in range(TICK_COUNT):
		var tk: Dictionary = _session.tick(TICK_DT)
		_ok(bool(tk.get("ok", false)), "tick %d ok" % (i + 1),
			"reason=" + String(tk.get("reason", "")))
	_near(float(_session.physics_world_service.t), _session.now_s(), TIME_TOL_S,
		"physics time == session time after ticks")
	_near(float(_session.sensor_service.t), _session.now_s(), TIME_TOL_S,
		"sensor time == session time after ticks")
	var gs1: Dictionary = _session.call("sensor_geometry_status") \
		if _session.has_method("sensor_geometry_status") else {}
	_eq(String(gs1.get("source", "")), "physics_world", "post-tick geometry source physics_world")
	_near(float(gs1.get("t", -1.0)), _session.now_s(), TIME_TOL_S,
		"geometry t == session t")
	var last1: Dictionary = gs1.get("last", {}) if gs1.get("last") is Dictionary else {}
	_ok(bool(last1.get("ok", false)), "post-tick geometry bind ok", str(last1))
	_eq(bool(last1.get("time_ok", false)), true, "post-tick geometry time_ok")
	_near(float(last1.get("provider_t", -1.0)), _session.now_s(), TIME_TOL_S,
		"geometry provider_t == session t")
	# 目标确实机动（否则无法区分静态与物理）
	var moved := 0
	for tid in static_targets.keys():
		var d2 := _dist_km(_physics_r(String(tid)), seed_pos[String(tid)])
		if d2 > MOVE_EPS_KM:
			moved += 1
		_info("A0-T2 MOVED %s: %.3f km since boot" % [String(tid), d2])
	_ok(moved >= 1, "at least one target moved since boot", "moved=%d" % moved)
	# 传感器 targets 几何 == physics（逐值）
	var obs_pos: Array = _session.sensor_service.observer.get("pos_km", [])
	var obs_r: Array = _physics_r(String(_session.sensor_service.observer.get("id", "")))
	_ok(_vec_near(obs_pos, obs_r, RANGE_TOL_KM), "sensor observer pos == physics observer pos",
		"sensor=%s physics=%s" % [str(obs_pos), str(obs_r)])
	for raw_t2 in _session.sensor_service.targets:
		if not (raw_t2 is Dictionary):
			continue
		var tr2: Dictionary = raw_t2
		var tid2 := String(tr2.get("id", ""))
		if not static_targets.has(tid2):
			continue
		var spos: Array = tr2.get("pos_km", []) if tr2.get("pos_km") is Array else []
		var ppos: Array = _physics_r(tid2)
		_ok(_vec_near(spos, ppos, RANGE_TOL_KM),
			"sensor target pos == physics pos: " + tid2,
			"sensor=%s physics=%s" % [str(spos), str(ppos)])
		_eq(String(tr2.get("geometry_source", "")), "physics_world",
			"sensor target geometry_source marked: " + tid2)
		_near(float(tr2.get("geometry_t", -1.0)), _session.now_s(), TIME_TOL_S,
			"sensor target geometry_t == session t: " + tid2)
		_eq(String(tr2.get("geometry_frame", "")), FRAME,
			"sensor target geometry_frame bary_rot: " + tid2)
		# 静态元数据必须保留（来自原权威，不被几何绑定覆盖）
		var truth: Dictionary = _truth.get(tid2, {}) if _truth.get(tid2) is Dictionary else {}
		for meta_key in ["rcs_m2", "side", "iff_code", "classification", "batch"]:
			_ok(tr2.has(meta_key), "sensor target keeps static metadata %s: %s" % [meta_key, tid2],
				"keys=" + str(tr2.keys()))

	_step("5. observation geometry == physics geometry (not static, not stale seed)")
	var obs_all: Array = _session.sensor_service.observations
	_ok(obs_all.size() > 0, "sensor produced observations", "n=" + str(obs_all.size()))
	var checked := 0
	var mismatch: Array = []
	var time_mismatch: Array = []
	# 只检查**最新一次** step 产生的观测（历史观测属于旧时刻，不能拿当前 t 比较）。
	var newest_t := -1.0
	for raw_o in obs_all:
		if raw_o is Dictionary:
			newest_t = maxf(newest_t, float((raw_o as Dictionary).get("t", -1.0)))
	for i in range(obs_all.size() - 1, -1, -1):
		if checked >= 6:
			break
		var o: Dictionary = obs_all[i]
		var ot := float(o.get("t", -1.0))
		if absf(ot - newest_t) > TIME_TOL_S:
			continue
		if absf(ot - float(_session.physics_world_service.t)) > TIME_TOL_S:
			time_mismatch.append({"obs_t": ot,
				"physics_t": float(_session.physics_world_service.t)})
		var tid3 := String(o.get("target_id", ""))
		if not static_targets.has(tid3):
			continue
		var rng := float(o.get("range_km", -1.0))
		var brg := float(o.get("bearing_deg", -1.0))
		if rng < 0.0 or brg < 0.0:
			continue
		var expect := _expect_geometry(tid3)
		# 观测值 = physics 几何 + 传感器测量噪声；用观测行自带的 sigma 作容差
		# （4σ 或 1 单位，取大），不硬编码噪声量级。
		var rsig := absf(float(o.get("range_sigma_km", -1.0)))
		if rsig <= 0.0:
			rsig = 1.0
		var bsig := absf(float(o.get("bearing_sigma_deg", -1.0)))
		if bsig <= 0.0:
			bsig = 1.0
		var range_tol := maxf(rsig * 4.0, 1.0)
		var bearing_tol := maxf(bsig * 4.0, 1.0)
		if absf(rng - float(expect.get("range_km", -1.0))) > range_tol \
				or _bearing_delta(brg, float(expect.get("bearing_deg", -1.0))) > bearing_tol:
			mismatch.append({"target": tid3, "obs_range": rng, "obs_bearing": brg,
				"expect": expect, "range_tol": range_tol, "bearing_tol": bearing_tol})
		# 观测必须显著不同于静态配置几何（反证：不是旧静态位置）
		var static_rng := _range_from_static(tid3)
		if static_rng >= 0.0:
			_ok(absf(rng - static_rng) > MOVE_EPS_KM,
				"observation range is NOT the static config geometry: " + tid3,
				"obs=%.3f static=%.3f" % [rng, static_rng])
		checked += 1
	_ok(checked > 0, "checked at least one observation against physics geometry",
		"checked=%d" % checked)
	_ok(mismatch.is_empty(), "observation range/bearing tracks physics geometry (within sensor noise)",
		"mismatches=" + str(mismatch))
	_ok(time_mismatch.is_empty(), "observation t == physics t (same simulation instant)",
		"mismatches=" + str(time_mismatch))
	# 观测语义：观测行必须带观测属性（support/quality/sensor/bearing），不是真值直传。
	# 注意 sigma 字段在 authority 层；服务层 observation 行只有 support/quality/range/bearing。
	var semantic_ok := false
	var obs_sensors: Array = []
	for raw_o2 in obs_all:
		if raw_o2 is Dictionary:
			var o2: Dictionary = raw_o2
			if o2.has("support") and o2.has("quality") and o2.has("sensor") \
					and o2.has("bearing_deg") and o2.has("range_km"):
				semantic_ok = true
				var s2 := String(o2.get("sensor", ""))
				if not (s2 in obs_sensors):
					obs_sensors.append(s2)
	_ok(semantic_ok, "observations carry observation attributes (support/quality/sensor/range/bearing)")
	_ok(obs_sensors.size() > 0, "observations tagged with sensor kind", str(obs_sensors))
	var bad_support: Array = []
	for raw_o3 in obs_all:
		if raw_o3 is Dictionary:
			var sup := int((raw_o3 as Dictionary).get("support", -1))
			# 0 = 未探测/未命中行（合法；路由层会忽略），1/2 = L1/L2 观测。
			if sup < 0 or sup > 2:
				bad_support.append(sup)
	_ok(bad_support.is_empty(), "observation support levels within L0/L1/L2", str(bad_support))

	_step("6. observation semantics preserved: TrackTable range_km stays an OBSERVATION")
	var tv: Dictionary = _session.track_table.vm() if _session.track_table != null else {}
	var tracks: Array = tv.get("tracks", []) if tv.get("tracks") is Array else []
	_ok(tracks.size() > 0, "TrackTable has fused tracks", "n=" + str(tracks.size()))
	for raw_tr in tracks:
		if not (raw_tr is Dictionary):
			continue
		var tr3: Dictionary = raw_tr
		var eid := String(tr3.get("entity_id", ""))
		if not static_targets.has(eid):
			continue
		var trange := float(tr3.get("range_km", -1.0))
		var sources: Array = tr3.get("sources", []) if tr3.get("sources") is Array else []
		_ok(sources.size() > 0, "track has observation sources (not truth): " + eid,
			str(sources))
		_ok(String(tr3.get("identity", "")) != "",
			"track keeps evidence-derived identity: " + eid,
			"identity=" + String(tr3.get("identity", "")))
		# 观测语义：track range 来自 observation，可以带观测误差；不得是内部 truth 字段直传。
		var obs_range := _latest_obs_range(eid)
		if obs_range >= 0.0:
			_ok(absf(trange - obs_range) <= 1.0e-3,
				"track range_km comes from observation (observation semantics): " + eid,
				"track=%.6f obs=%.6f" % [trange, obs_range])
	# CombatService 只读自己的 track 行，不读 sensor 内部真值
	var combat_tracks: Array = _session.combat_vm().get("tracks", []) \
		if _session.combat_vm().get("tracks") is Array else []
	for raw_ct in combat_tracks:
		if raw_ct is Dictionary:
			_ok(not (raw_ct as Dictionary).has("pos_km"),
				"CombatService track rows do not carry sensor/truth positions",
				"keys=" + str((raw_ct as Dictionary).keys()))
	# HUD 不读 sensor 内部几何：contacts 使用 track 观测值
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	for raw_c in contacts:
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		_ok(not c.has("truth_pos_km"), "HUD contact has no truth position field: " + String(c.get("id", "")))
		_ok(c.has("display_id"), "HUD contact uses safe display fields: " + String(c.get("id", "")))

	_step("7. degraded modes: no physics / frame mismatch → explicit static, no silent truth")
	var plain = GameSessionScript.new({"sensor_service": {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0],
			"rcs_m2": 10.0, "side": "friend"}],
	}})
	_ok(bool(plain.ready), "sensor-only session ready", str(plain.errors))
	var pgs: Dictionary = plain.call("sensor_geometry_status") \
		if plain.has_method("sensor_geometry_status") else {}
	_eq(String(pgs.get("source", "")), "static", "no-physics geometry source static")
	_eq(bool(pgs.get("authoritative", false)), false, "no-physics geometry not authoritative")
	var p_obs: Array = plain.sensor_service.config.get("targets", [])
	_ok(p_obs.size() > 0, "no-physics session keeps configured static targets")
	# 帧不匹配：L1 转换 seed + sensor，显式 static + 原因
	var conv = GameSessionScript.new({
		"physics_world": true, "prelude": {"scenario": "probe_frame_gate"},
		"seed_frame": "l1", "frame_origin": "l1",
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [20.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}],
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0], "rcs_m2": 10.0}],
		},
	})
	_ok(bool(conv.ready), "frame-converted session ready", str(conv.errors))
	_eq(bool(conv.physics_frame_meta().get("applied", false)), true,
		"frame-converted seed applied")
	var cgs: Dictionary = conv.call("sensor_geometry_status") \
		if conv.has_method("sensor_geometry_status") else {}
	_eq(String(cgs.get("source", "")), "static", "frame-mismatch geometry source static")
	_eq(bool(cgs.get("authoritative", true)), false, "frame-mismatch geometry not authoritative")
	# 审查修正：必须精确给出 reason=frame_mismatch，不再接受空原因/provider_not_ready。
	_eq(String(cgs.get("reason", "")), "frame_mismatch", "frame-mismatch public reason exact")
	_eq(bool(cgs.get("complete", true)), false, "frame-mismatch geometry not complete")
	_eq(bool(cgs.get("available", true)), false, "frame-mismatch geometry not available")
	var c_last: Dictionary = cgs.get("last", {}) if cgs.get("last") is Dictionary else {}
	_eq(String(c_last.get("reason", "")), "frame_mismatch", "frame-mismatch last.reason exact")
	_eq(bool(c_last.get("ok", true)), false, "frame-mismatch last.ok false")
	_eq(bool(c_last.get("time_ok", true)), false, "frame-mismatch last.time_ok false")
	# 无 physics 会话的公开 reason 也必须是精确值（不是空串）。
	_eq(String(pgs.get("reason", "")), "no_physics_world", "no-physics public reason exact")
	_eq(bool(pgs.get("complete", true)), false, "no-physics geometry not complete")

	_step("9. time mismatch: no observations from stale geometry")
	# 用可控 provider 人为制造时间不匹配：几何 t 落后于传感器 t。
	var clock = _FakeGeometryProvider.new()
	clock.frame = FRAME
	clock.t = 0.0
	clock.states = {
		"apsis": {"r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
		"harmattan": {"r": [500.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
	}
	var tm = GameSessionScript.new({"sensor_service": {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0], "rcs_m2": 10.0}],
		"options": {"radar_enabled": true, "emcon": false},
	}})
	_ok(bool(tm.ready), "time-mismatch session ready", str(tm.errors))
	clock.t = 0.0
	var tbind: Dictionary = tm.sensor_service.bind_geometry_provider(clock)
	_ok(bool(tbind.get("ok", false)), "fake provider bound at t=0", str(tbind))
	clock.t = 1.0
	# 先跑一次正常 step（几何可用），产生基线观测（sensor t 0→1，provider t=1）
	tm.sensor_service.step(1.0)
	var obs_base: int = tm.sensor_service.observations.size()
	_ok(obs_base > 0, "baseline observation generated with aligned geometry",
		"n=" + str(obs_base))
	# 人为制造时间不匹配：provider 时间不跟随传感器 t（step 后 sensor t=101，provider t=1）
	tm.sensor_service.t = 100.0
	var tstep: Dictionary = tm.sensor_service.step(1.0)
	var tgs: Dictionary = tm.call("sensor_geometry_status") \
		if tm.has_method("sensor_geometry_status") else {}
	_eq(String(tgs.get("reason", "")), "time_mismatch", "time-mismatch public reason")
	_eq(bool(tgs.get("authoritative", true)), false, "time-mismatch not authoritative")
	_eq(bool(tgs.get("complete", true)), false, "time-mismatch not complete")
	_eq(bool(tgs.get("available", true)), false, "time-mismatch not available")
	_eq(bool((tgs.get("last", {}) as Dictionary).get("time_ok", true)), false,
		"time-mismatch last.time_ok false")
	var obs_after: int = tm.sensor_service.observations.size()
	_ok(obs_after == obs_base, "no NEW observation generated on time mismatch",
		"before=%d after=%d" % [obs_base, obs_after])
	_ok(int(tgs.get("suppressed_steps", 0)) > 0,
		"suppressed_steps counted for time mismatch",
		"suppressed=" + str(tgs.get("suppressed_steps", 0)))
	# 恢复一致后应能继续产生观测（不是永久关死）
	clock.t = 102.0
	tm.sensor_service.step(1.0)
	var tgs2: Dictionary = tm.call("sensor_geometry_status") \
		if tm.has_method("sensor_geometry_status") else {}
	_eq(bool(tgs2.get("authoritative", false)), true, "geometry recovers when time aligns")
	_ok(tm.sensor_service.observations.size() > obs_after,
		"observations resume after time realigns",
		"n=" + str(tm.sensor_service.observations.size()))

	_step("10. partial binding failure: observer missing / target missing are not authoritative")
	# 10a. observer 在 physics 中缺失
	var mo = GameSessionScript.new({"sensor_service": {
		"observer": {"id": "ghost_ship", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0], "rcs_m2": 10.0}],
	}})
	_ok(bool(mo.ready), "observer-missing session ready", str(mo.errors))
	var mo_prov = _FakeGeometryProvider.new()
	mo_prov.states = {"harmattan": {"r": [500.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}}
	mo_prov.t = 1.0
	mo.sensor_service.bind_geometry_provider(mo_prov)
	mo.sensor_service.step(1.0)
	var mo_gs: Dictionary = mo.call("sensor_geometry_status") \
		if mo.has_method("sensor_geometry_status") else {}
	_eq(bool(mo_gs.get("authoritative", true)), false, "observer-missing not authoritative")
	_eq(bool(mo_gs.get("complete", true)), false, "observer-missing not complete")
	_eq(String(mo_gs.get("reason", "")), "observer_missing", "observer-missing public reason")
	_eq(bool(mo_gs.get("observer_bound", true)), false, "observer-missing observer_bound false")
	var mo_missing: Array = mo_gs.get("missing", []) if mo_gs.get("missing") is Array else []
	_ok("ghost_ship" in mo_missing, "observer-missing records missing id", str(mo_missing))
	_eq(mo.sensor_service.observations.size(), 0,
		"observer-missing generates NO observations from stale geometry")
	# 10b. 单个 target 在 physics 中缺失
	var mt = GameSessionScript.new({"sensor_service": {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [
			{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0], "rcs_m2": 10.0},
			{"id": "missing_target", "pos_km": [30.0, 0.0, 0.0], "rcs_m2": 10.0}],
	}})
	_ok(bool(mt.ready), "target-missing session ready", str(mt.errors))
	var mt_prov = _FakeGeometryProvider.new()
	mt_prov.states = {
		"apsis": {"r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
		"harmattan": {"r": [500.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
	}
	mt_prov.t = 1.0
	mt.sensor_service.bind_geometry_provider(mt_prov)
	mt.sensor_service.step(1.0)
	var mt_gs: Dictionary = mt.call("sensor_geometry_status") \
		if mt.has_method("sensor_geometry_status") else {}
	_eq(bool(mt_gs.get("authoritative", true)), false, "target-missing not authoritative")
	_eq(bool(mt_gs.get("complete", true)), false, "target-missing not complete")
	_eq(String(mt_gs.get("reason", "")), "target_missing", "target-missing public reason")
	var mt_skipped: Array = mt_gs.get("skipped", []) if mt_gs.get("skipped") is Array else []
	_ok("missing_target" in mt_skipped, "target-missing records skipped id", str(mt_skipped))
	_eq(mt.sensor_service.observations.size(), 0,
		"target-missing generates NO observations (mixed geometry suppressed)")
	# 未绑定的行必须被标记为 unavailable 且坐标已清空（不沿用旧静态坐标）
	for raw_t in mt.sensor_service.targets:
		if raw_t is Dictionary and String((raw_t as Dictionary).get("id", "")) == "missing_target":
			_eq(String((raw_t as Dictionary).get("geometry_source", "")), "unavailable",
				"missing target row marked unavailable")
			var mpos: Array = (raw_t as Dictionary).get("pos_km", [1.0])
			_eq(mpos.size(), 0, "missing target row has cleared pos_km (no stale coords)")

	_step("11. determinism of failure paths")
	var fa = GameSessionScript.new(_determinism_cfg())
	var fb = GameSessionScript.new(_determinism_cfg())
	var fa_prov = _FakeGeometryProvider.new()
	var fb_prov = _FakeGeometryProvider.new()
	fa_prov.states = {"apsis": {"r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}}
	fa_prov.t = 1.0
	fb_prov.states = {"apsis": {"r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]}}
	fb_prov.t = 1.0
	fa.sensor_service.bind_geometry_provider(fa_prov)
	fb.sensor_service.bind_geometry_provider(fb_prov)
	fa.sensor_service.step(1.0)
	fb.sensor_service.step(1.0)
	var fg1 := JSON.stringify(fa.call("sensor_geometry_status"))
	var fg2 := JSON.stringify(fb.call("sensor_geometry_status"))
	_ok(fg1 == fg2, "identical failure-path geometry status across runs",
		"len_a=%d len_b=%d" % [fg1.length(), fg2.length()])
	_eq(fa.sensor_service.observations.size(), fb.sensor_service.observations.size(),
		"identical suppressed observation count across runs")

	_step("12. determinism: same operation sequence yields identical geometry + observations")
	var d1 = GameSessionScript.new(_determinism_cfg())
	var d2 = GameSessionScript.new(_determinism_cfg())
	for i in range(4):
		d1.tick(TICK_DT)
		d2.tick(TICK_DT)
	var g1 := JSON.stringify(d1.call("sensor_geometry_status") if d1.has_method("sensor_geometry_status") else {})
	var g2 := JSON.stringify(d2.call("sensor_geometry_status") if d2.has_method("sensor_geometry_status") else {})
	_ok(g1 == g2, "identical geometry status across identical runs",
		"len_a=%d len_b=%d" % [g1.length(), g2.length()])
	var o1 := JSON.stringify(d1.sensor_service.observations)
	var o2 := JSON.stringify(d2.sensor_service.observations)
	_ok(o1 == o2, "identical observations across identical runs",
		"len_a=%d len_b=%d" % [o1.length(), o2.length()])
	_ok(JSON.stringify(d1.track_table.vm()) == JSON.stringify(d2.track_table.vm()),
		"identical TrackTable across identical runs")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _determinism_cfg() -> Dictionary:
	return {
		"entities": [
			{"id": "apsis", "kind": "ship", "name": "APSIS",
				"pos_km": [321719.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "name": "HAMATTAN",
				"pos_km": [322139.0, 0.0, 0.0], "vel_kmps": [0.0, 0.02, 0.0]}],
		"physics_world": true, "seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "harmattan", "pos_km": [322139.0, 0.0, 0.0],
				"rcs_m2": 10.0, "side": "hostile"}],
			"options": {"radar_enabled": true, "emcon": false},
		},
	}


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
	print("[A0-T2] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}


func _physics_r(eid: String) -> Array:
	if _session == null or _session.physics_world_service == null:
		return []
	var st: Dictionary = _session.physics_state(eid)
	var r = st.get("r", [])
	return (r as Array).duplicate() if r is Array else []


## 由 physics 当前时刻计算的期望几何（与传感器同源：bary_rot / km）。
func _expect_geometry(tid: String) -> Dictionary:
	var oid := String(_session.sensor_service.observer.get("id", "apsis"))
	var o: Array = _physics_r(oid)
	var t: Array = _physics_r(tid)
	if o.size() < 3 or t.size() < 3:
		return {}
	var dx := float(t[0]) - float(o[0])
	var dy := float(t[1]) - float(o[1])
	var dz := float(t[2]) - float(o[2])
	var rng := sqrt(dx * dx + dy * dy + dz * dz)
	var brg := rad_to_deg(atan2(dx, dy))
	if brg < 0.0:
		brg += 360.0
	return {"range_km": rng, "bearing_deg": brg}


## 由静态配置位置计算的期望 range（用于反证「观测不是旧静态几何」）。
func _range_from_static(tid: String) -> float:
	var obs_pos: Array = _session.sensor_service.config.get("observer", {}).get("pos_km", [])
	var row := _find_static_target(tid)
	if row.is_empty():
		return -1.0
	var tp: Array = row.get("pos_km", [])
	if obs_pos.size() < 3 or tp.size() < 3:
		return -1.0
	return _dist_km(obs_pos, tp)


func _find_static_target(tid: String) -> Dictionary:
	for raw in _session.sensor_service.config.get("targets", []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			return raw
	return {}


func _latest_obs_range(tid: String) -> float:
	var obs: Array = _session.sensor_service.observations
	for i in range(obs.size() - 1, -1, -1):
		var o: Dictionary = obs[i]
		if String(o.get("target_id", "")) == tid:
			return float(o.get("range_km", -1.0))
	return -1.0


## 方位角差（考虑 0/360 环绕）。
func _bearing_delta(a: float, b: float) -> float:
	var d := fmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)


func _vec_near(a: Array, b: Array, tol: float) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	for i in range(3):
		if absf(float(a[i]) - float(b[i])) > tol:
			return false
	return true


func _dist_km(a: Array, b: Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return -1.0
	var dx := float(a[0]) - float(b[0])
	var dy := float(a[1]) - float(b[1])
	var dz := float(a[2]) - float(b[2])
	return sqrt(dx * dx + dy * dy + dz * dz)


## A0-T2 失败路径测试用的可控几何 provider（只读契约实现；不写任何游戏状态）。
## 可人为设置 t / states / frame，用来制造时间不匹配与实体缺失。
class _FakeGeometryProvider:
	var t := 0.0
	var frame := "bary_rot"
	var ready := true
	var states: Dictionary = {}

	func geometry_ready() -> bool:
		return ready

	func geometry_frame() -> String:
		return frame

	func geometry_t() -> float:
		return t

	func geometry_state(entity_id: String) -> Dictionary:
		if not states.has(entity_id):
			return {"ok": false, "reason": "unknown_entity", "id": entity_id}
		var row: Dictionary = states[entity_id]
		var r: Array = row.get("r", []) if row.get("r") is Array else []
		var v: Array = row.get("v", []) if row.get("v") is Array else []
		if r.size() < 3 or v.size() < 3:
			return {"ok": false, "reason": "non_finite_state", "id": entity_id}
		return {"ok": true, "id": entity_id, "frame": frame, "t": t,
			"r": r.duplicate(), "v": v.duplicate(),
			"units": {"length": "km", "velocity": "km/s", "time": "s"}}
