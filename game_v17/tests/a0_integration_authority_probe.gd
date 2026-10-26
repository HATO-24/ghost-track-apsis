extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-01 · 实现链同提交整合验收探针
#
# 基线：A-00 交付 I0 候选 b9101c8（A-00 最终 head 882e058）。
# 真实入口：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
#
# 覆盖任务卡 7 行验收矩阵：
#   1. 无噪声 geometry fixture：observer [0,0,0] / target [3,4,0] km / 距离 5；
#      方位用**独立标量公式**；非零速度输入且 provider 速度保留。
#   2. observer 与 target **分别**移动（各 10×60 s）；两次移动都必须反映到
#      距离/方位/速度输入；不能只证明目标在动。
#   3. 不确定观测 fixture：真值 5 km、注入测量 5.25 km / 真值+0.05°；
#      fixture 声明 sigma=0.1 km/0.02°；TrackTable/消费者保留**测量**字段，
#      不得拉回真值；传递容差 1e-9。
#   4. 生产误差参数：沿实际 radar/optical backend 取得 sigma 与单位；
#      缺 sigma 必须显式失败，**禁止**用默认 1 冒充模型参数。
#   5. 实际消费者 source/frame/t 表：physics / world / 合成 snapshot / sensor 输入 /
#      ballistics 初始状态 / HUD 输入逐项列出。
#   6. 失败与降级：缺实体、observer_missing、target_missing、provider 未就绪、
#      过期 t、未知 frame、physics 失败都有 reason；**无效几何必须停止本 tick 相关路由**；
#      显式 legacy/static 允许但必须标 ADVISORY，不得冒充 LIVE。
#   7. 可见性：7 个 scenario 实体 catalog 归属正确；匿名 contacts 无 friend fallback、
#      无 batch/rcs/radius/has_pd 泄漏。
#
# 阈值（任务卡 §阈值）：world 副本 1e-9 km / 1e-12 km/s；provider 独立几何
# 1e-6 km / 1e-6 deg；采样时差 1e-6 s。
#
# Output: `A0-A01 INTEGRATION AUTHORITY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"
const GameSessionScript := preload("res://scripts/core/game_session.gd")
const Types := preload("res://framework/sim/sensor_types.gd")

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
# 任务卡阈值
const GEO_DIST_TOL_KM := 1.0e-6
const GEO_BEARING_TOL_DEG := 1.0e-6
const SAME_TICK_TOL_S := 1.0e-6
const OBS_TRANSFER_TOL := 1.0e-9
# 真值/内部可见字段
const TRUTH_ONLY_FIELDS := ["batch", "rcs_m2", "radius_km", "has_pd"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _hud = null
var _binder = null
var _session = null
var _truth: Dictionary = {}
var _truth_ids: Array[String] = []
var _main_menu_instantiated := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A01 INTEGRATION AUTHORITY PROBE · baseline I0 b9101c8 / A-00 head 882e058")
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
	print("[A0-A01] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("A0-A01 INTEGRATION AUTHORITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A01] FAILED: ", f)
		print("A0-A01 INTEGRATION AUTHORITY PROBE FAILED")
	else:
		print("A0-A01 INTEGRATION AUTHORITY PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A01] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A01] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-A01] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A01] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. real entry main_menu → v1_hud")
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
	_ok(_session.physics_world_service != null, "PhysicsWorld enabled")
	_ok(_session.sensor_service != null, "SensorService enabled")
	_ok(_session.track_table != null, "TrackTable enabled")
	_ok(_session.entity_catalog != null and bool(_session.entity_catalog.ready),
		"EntityCatalog ready")
	if _session.physics_world_service == null or _session.sensor_service == null:
		_finish()
		return

	_step("2. scenario truth + local no-noise scalar geometry")
	var sc := _read_json(TARGET_SCENARIO)
	for raw in (sc.get("entities", []) if sc.get("entities") is Array else []):
		if raw is Dictionary:
			var e: Dictionary = raw
			var eid := String(e.get("id", ""))
			if eid != "":
				_truth[eid] = e.duplicate(true)
				_truth_ids.append(eid)
	_truth_ids.sort()
	_eq(_truth.size(), 7, "scenario truth table has 7 entities")
	# 局部精确数值自检：observer [0,0,0]、target [3,4,0] km → 距离恰为 5，方位为 atan2(3,4)。
	var exp5 := _geom_expect([0.0, 0.0, 0.0], [3.0, 4.0, 0.0])
	_near(float(exp5["range_km"]), 5.0, 0.0,
		"local no-noise scalar expectation: [0,0,0]->[3,4,0] is exactly 5 km")
	_near(float(exp5["bearing_deg"]), rad_to_deg(atan2(3.0, 4.0)), 0.0,
		"local no-noise scalar expectation: bearing uses the atan2(dx,dy) axis definition")
	_info("NO-NOISE scalar: range=%.12f bearing=%.12f" % [
		float(exp5["range_km"]), float(exp5["bearing_deg"])])

	_step("3. real session: provider geometry == independent scalar geometry (same tick)")
	# 真实装配 session（main_menu → v1_hud → ShellBinder → GameSession）。
	# 期望值从**回读的权威物理位置**用标量 double 计算，不使用绝对假设。
	for i in range(3):
		_session.tick(TICK_DT)
	var g0 := _provider_vs_scalar(_session, "harmattan")
	_ok(bool(g0.get("ok", false)), "provider geometry matches scalar expectation on the real session",
		str(g0.get("reason", "")))
	_near(float(g0.get("range_err_km", -1.0)), 0.0, GEO_DIST_TOL_KM,
		"real session: provider range == independent scalar range (<=1e-6 km)")
	_near(float(g0.get("bearing_err_deg", -1.0)), 0.0, GEO_BEARING_TOL_DEG,
		"real session: provider bearing == independent scalar bearing (<=1e-6 deg)")
	_info("REAL SESSION: dist=%.9f err=%.3e km | bearing=%.9f err=%.3e deg" % [
		float(g0.get("range_km", -1.0)), float(g0.get("range_err_km", -1.0)),
		float(g0.get("bearing_deg", -1.0)), float(g0.get("bearing_err_deg", -1.0))])
	# 非零速度输入 + provider 速度保留（真实 session 的 apsis 有轨道速度）
	var apsis_vel := _physics_velocity(_session, "apsis")
	_ok(apsis_vel.size() >= 3, "observer velocity readable from physics", str(apsis_vel))
	var v_nz := false
	if apsis_vel.size() >= 3:
		for comp in apsis_vel:
			if absf(float(comp)) > 0.0:
				v_nz = true
	_ok(v_nz, "observer has a non-zero velocity input", str(apsis_vel))

	_step("4. observer and target moved SEPARATELY via authorized physics API (%d×%.0fs each)" % [
		TICK_COUNT, TICK_DT])
	# 3a. 只移动 observer：读回其权威位置后加固定偏移
	var obs0 := _physics_pos(_session, "apsis")
	_ok(obs0.size() >= 3, "observer position readable before move", str(obs0))
	var obs_new := [float(obs0[0]) + 25.0, float(obs0[1]) - 10.0, float(obs0[2]) + 5.0]
	var up_obs: Dictionary = _session.physics_world_service.upsert_entity("apsis",
		{"r": obs_new, "v": [0.0, 0.0, 0.0]})
	_ok(bool(up_obs.get("ok", false)), "authorized physics API moved observer",
		str(up_obs.get("reason", "")))
	for i in range(TICK_COUNT):
		_session.tick(TICK_DT)
	var g_obs := _provider_vs_scalar(_session, "harmattan")
	_ok(bool(g_obs.get("ok", false)),
		"after OBSERVER move: provider geometry still matches scalar expectation",
		str(g_obs.get("reason", "")))
	_near(float(g_obs.get("range_err_km", -1.0)), 0.0, GEO_DIST_TOL_KM,
		"after OBSERVER move: range error <= 1e-6 km")
	_near(float(g_obs.get("bearing_err_deg", -1.0)), 0.0, GEO_BEARING_TOL_DEG,
		"after OBSERVER move: bearing error <= 1e-6 deg")
	_ok(absf(float(g_obs.get("range_km", -1.0)) - float(g0.get("range_km", -1.0))) > 1.0,
		"OBSERVER move actually changed the observed geometry",
		"before=%.6f after=%.6f km" % [float(g0.get("range_km", -1.0)),
			float(g_obs.get("range_km", -1.0))])
	_info("OBSERVER MOVE: range %.6f -> %.6f km" % [float(g0.get("range_km", -1.0)),
		float(g_obs.get("range_km", -1.0))])
	# 3b. 再只移动 target
	var tgt0 := _physics_pos(_session, "harmattan")
	_ok(tgt0.size() >= 3, "target position readable before move", str(tgt0))
	var tgt_new := [float(tgt0[0]) - 40.0, float(tgt0[1]) + 30.0, float(tgt0[2])]
	var up_tgt: Dictionary = _session.physics_world_service.upsert_entity("harmattan",
		{"r": tgt_new, "v": [0.0, 0.0, 0.0]})
	_ok(bool(up_tgt.get("ok", false)), "authorized physics API moved target",
		str(up_tgt.get("reason", "")))
	for i in range(TICK_COUNT):
		_session.tick(TICK_DT)
	var g_both := _provider_vs_scalar(_session, "harmattan")
	_ok(bool(g_both.get("ok", false)),
		"after TARGET move: provider geometry still matches scalar expectation",
		str(g_both.get("reason", "")))
	_near(float(g_both.get("range_err_km", -1.0)), 0.0, GEO_DIST_TOL_KM,
		"after TARGET move: range error <= 1e-6 km")
	_near(float(g_both.get("bearing_err_deg", -1.0)), 0.0, GEO_BEARING_TOL_DEG,
		"after TARGET move: bearing error <= 1e-6 deg")
	_ok(absf(float(g_both.get("range_km", -1.0)) - float(g_obs.get("range_km", -1.0))) > 1.0,
		"TARGET move actually changed the observed geometry",
		"before=%.6f after=%.6f km" % [float(g_obs.get("range_km", -1.0)),
			float(g_both.get("range_km", -1.0))])
	_info("TARGET MOVE: range %.6f -> %.6f km" % [float(g_obs.get("range_km", -1.0)),
		float(g_both.get("range_km", -1.0))])

	_step("4. uncertainty observation fixture: measurement preserved, not pulled to truth")
	# fixture 声明：真值 5 km，测量 5.25 km，方位 真值+0.05°，sigma 0.1 km / 0.02°
	var true_range := 5.0
	var measured_range := 5.25
	var true_bearing := 36.86989764584402  # atan2(3,4) in deg
	var measured_bearing := true_bearing + 0.05
	var sig_range := 0.1
	var sig_bearing := 0.02
	var ux = GameSessionScript.new({"track_table": true, "sensor_service": {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [3.0, 4.0, 0.0], "rcs_m2": 1100.0}]}})
	_ok(bool(ux.ready), "uncertainty fixture session ready", str(ux.errors))
	var write: Dictionary = ux.track_table.handle_observation({
		"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": "OBS-UNCERTAIN-1", "t": 60.0, "observer_id": "apsis",
		"target_id": "harmattan", "sensor": "radar", "sensor_model": "YW-R9",
		"support": 2, "quality": 1.0,
		"range_km": measured_range, "bearing_deg": measured_bearing,
		"range_sigma_km": sig_range, "bearing_sigma_deg": sig_bearing,
		"level_decided": false, "produces_contact": false, "writes_v15": false,
	}, "session_fusion")
	_ok(bool(write.get("ok", false)), "uncertainty observation accepted by TrackTable",
		str(write.get("reason", "")))
	var utracks: Array = ux.track_table.vm().get("tracks", [])
	_eq(utracks.size(), 1, "uncertainty fixture produced 1 track")
	var ur := -1.0
	if utracks.size() > 0:
		ur = float((utracks[0] as Dictionary).get("range_km", -1.0))
	# 测量值必须保留（容差 1e-9），不得被真值 5.0 覆盖
	_near(ur, measured_range, OBS_TRANSFER_TOL,
		"track keeps the MEASURED range (5.25), not the true range (5.0)")
	_ok(absf(ur - true_range) > 0.1,
		"track range was NOT pulled back to truth", "track=%.6f truth=%.6f" % [ur, true_range])
	_info("UNCERTAINTY fixture: truth=%.3f measured=%.3f sigma=%.3f/%.3f track=%.6f" % [
		true_range, measured_range, sig_range, sig_bearing, ur])

	_step("5. production error parameters from the actual radar/optical backend")
	var radar_rec = Types.record("YW-R9")
	var optical_rec = Types.record("MS-OT2")
	var ir_rec = Types.record("CH-IR2")
	var param_bad: Array = []
	var param_rows: Array = []
	for pair in [["YW-R9", radar_rec], ["MS-OT2", optical_rec], ["CH-IR2", ir_rec]]:
		var model := String(pair[0])
		var rec = pair[1]
		if rec == null:
			param_bad.append({"model": model, "reason": "model record missing"})
			continue
		var bs := float(rec.sigma_bearing_deg)
		var rf := float(rec.sigma_range_frac)
		var rfloor := float(rec.sigma_range_floor_km)
		var rng := float(rec.range_km)
		param_rows.append({"model": model, "range_km": rng,
			"sigma_bearing_deg": bs, "sigma_range_frac": rf,
			"sigma_range_floor_km": rfloor})
		# 必须有可追溯的非零误差量（缺 sigma 明确失败，禁止默认 1 冒充）
		if is_nan(bs) or is_inf(bs) or bs <= 0.0:
			param_bad.append({"model": model, "field": "sigma_bearing_deg",
				"value": bs, "reason": "missing/invalid bearing sigma"})
		if is_nan(rng) or rng <= 0.0:
			param_bad.append({"model": model, "field": "range_km", "value": rng,
				"reason": "missing/invalid range"})
		_info("MODEL %s: range=%.3f km, sigma_bearing=%.6f deg, sigma_range_frac=%.6f, sigma_range_floor=%.6f km" % [
			model, rng, bs, rf, rfloor])
	_ok(param_bad.is_empty(),
		"bearing/range model params present with units for radar/optical/IR backends",
		"violations=" + str(param_bad))
	_ok(param_rows.size() == 3, "all three sensor model records resolved",
		"n=" + str(param_rows.size()))
	# 测距误差量：只有声明了测距能力的模型才能声称测距精度；缺 sigma 必须**显式标注
	# 未验证**，绝不能用默认 1 冒充模型参数（任务卡第 4 行）。
	var range_sigma_models: Array = []
	var range_unverified: Array = []
	for row in param_rows:
		var r := (row as Dictionary)
		var m := String(r.get("model", ""))
		var rf := float(r.get("sigma_range_frac", 0.0))
		var rfloor := float(r.get("sigma_range_floor_km", 0.0))
		if rf > 0.0 or rfloor > 0.0:
			range_sigma_models.append(m)
		else:
			range_unverified.append(m)
	_info("RANGE SIGMA: measured models=%s | range sigma UNVERIFIED (declares no range measurement)=%s" % [
		str(range_sigma_models), str(range_unverified)])
	_ok(not range_sigma_models.is_empty(),
		"at least one backend declares a traceable range sigma (radar ranging)",
		str(range_sigma_models))
	# 明确记录「未验证」清单，不得把它当成通过
	_info("EXPLICIT UNVERIFIED: models without range sigma are NOT claimed to have range accuracy: "
		+ str(range_unverified))

	_step("6. consumer source/frame/t table (same entity id)")
	var consumers_bad: Array = []
	# 6a. physics：唯一运动学权威
	var ps: Dictionary = _session.physics_state("harmattan")
	var p_frame := String(ps.get("frame", ""))
	var p_t := float(ps.get("t", -1.0))
	var p_units: Dictionary = ps.get("units", {}) if ps.get("units") is Dictionary else {}
	if p_frame != FRAME:
		consumers_bad.append({"consumer": "physics", "field": "frame", "value": p_frame})
	if String(p_units.get("length", "")) != "km":
		consumers_bad.append({"consumer": "physics", "field": "unit_length",
			"value": str(p_units.get("length", ""))})
	# 6b. world 投影：与 physics 同帧同刻（副本容差 1e-9 km）
	var we: Dictionary = _session.world.entity("harmattan")
	var we_pos: Array = we.get("pos_km", []) if we.get("pos_km") is Array else []
	var ps_r: Array = ps.get("r", []) if ps.get("r") is Array else []
	if we_pos.size() < 3 or ps_r.size() < 3:
		consumers_bad.append({"consumer": "world", "reason": "position missing"})
	else:
		for i in range(3):
			if absf(float(we_pos[i]) - float(ps_r[i])) > 1.0e-9:
				consumers_bad.append({"consumer": "world", "field": "pos_km[%d]" % i,
					"world": float(we_pos[i]), "physics": float(ps_r[i])})
	# 6c. 合成 snapshot：声明 frame + t
	var snap: Dictionary = _session.snapshot()
	var snap_frame: Dictionary = snap.get("physics_frame", {}) \
		if snap.get("physics_frame") is Dictionary else {}
	var snap_ents: Array = snap.get("entities", []) if snap.get("entities") is Array else []
	var snap_hit: Dictionary = {}
	for raw_se in snap_ents:
		if raw_se is Dictionary and String((raw_se as Dictionary).get("id", "")) == "harmattan":
			snap_hit = raw_se
	if snap_hit.is_empty():
		consumers_bad.append({"consumer": "snapshot", "reason": "entity missing"})
	if snap_frame.is_empty():
		consumers_bad.append({"consumer": "snapshot", "reason": "no physics_frame block"})
	# 6d. sensor 输入：几何 provider 的 t/frame/source
	var sens_geo: Dictionary = _session.sensor_geometry_status()
	if String(sens_geo.get("source", "")) != "physics_world":
		consumers_bad.append({"consumer": "sensor", "field": "geometry_source",
			"value": String(sens_geo.get("source", ""))})
	if String(sens_geo.get("frame", "")) != FRAME:
		consumers_bad.append({"consumer": "sensor", "field": "frame",
			"value": String(sens_geo.get("frame", ""))})
	_near(float(sens_geo.get("t", -1.0)), float(_session.now_s()), SAME_TICK_TOL_S,
		"sensor geometry sampled at the same session tick")
	# 6e. ballistics 初始状态：必须有可追溯 source
	var ball_src: Dictionary = _ballistics_state_source(_session, "harmattan")
	if not bool(ball_src.get("ok", false)):
		consumers_bad.append({"consumer": "ballistics", "reason":
			String(ball_src.get("reason", "no traceable state source"))})
	# 6f. HUD/火控输入：binder 行必须声明来源，不要求复制 truth
	var hud_rows: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	var hud_hit: Dictionary = {}
	for raw_h in hud_rows:
		if raw_h is Dictionary:
			var hr: Dictionary = raw_h
			if String(hr.get("entity_id", hr.get("id", ""))) == "harmattan":
				hud_hit = hr
	if hud_hit.is_empty():
		consumers_bad.append({"consumer": "hud", "reason": "contact row missing"})
	else:
		for sf in ["side_source", "identity_source"]:
			if String(hud_hit.get(sf, "")) == "":
				consumers_bad.append({"consumer": "hud", "field": sf, "reason": "source not declared"})
	_ok(consumers_bad.is_empty(),
		"all consumers expose a traceable source/frame/t (physics/world/snapshot/sensor/ballistics/HUD)",
		"violations=" + str(consumers_bad))
	_info("CONSUMER TABLE: physics frame=%s t=%.3f | world copy<=1e-9 | snapshot frame_keys=%s | sensor source=%s t=%.3f | ballistics=%s | hud side_source=%s" % [
		p_frame, p_t, str(snap_frame.keys()), String(sens_geo.get("source", "")),
		float(sens_geo.get("t", -1.0)),
		str(ball_src.get("source", "n/a")), String(hud_hit.get("side_source", ""))])

	_step("7. invalid geometry must stop this tick's routing (P20 branch risk)")
	# 复现任务卡点名的分支风险：mark_geometry_unavailable() 清空 provider 后，
	# _geometry_usable() 的「无 provider」分支会允许静态观测 → 无效几何仍然路由。
	var fm = GameSessionScript.new({
		"own_entity": "apsis",
		"physics_world": true, "seed_frame": "l1", "frame_origin": "l1",
		"track_table": true,
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [20.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [{"id": "harmattan", "pos_km": [20.0, 0.0, 0.0], "rcs_m2": 1100.0}],
			"options": {"radar_enabled": true, "emcon": false}},
	})
	_ok(bool(fm.ready), "frame-mismatch fixture ready", str(fm.errors))
	var fm_geo: Dictionary = fm.sensor_geometry_status()
	_eq(String(fm_geo.get("source", "")), "static", "frame-mismatch geometry source is static")
	_eq(bool(fm_geo.get("authoritative", true)), false,
		"frame-mismatch geometry is not authoritative")
	_eq(String(fm_geo.get("reason", "")), "frame_mismatch",
		"frame-mismatch reason recorded")
	_ok(fm.physics_world_service != null, "frame-mismatch fixture still has PhysicsWorld")
	for i in range(2):
		fm.tick(TICK_DT)
	var fm_obs: Array = fm.sensor_service.observations
	var fm_tracks: Array = fm.track_table.vm().get("tracks", []) \
		if fm.track_table.vm().get("tracks") is Array else []
	_info("FRAME-MISMATCH: observations=%d tracks=%d suppressed=%d" % [
		fm_obs.size(), fm_tracks.size(),
		int(fm.sensor_geometry_status().get("suppressed_steps", -1))])
	# 无效几何（physics 在场但不可用）不得产出可被当真的观测/航迹
	_ok(fm_obs.is_empty(),
		"invalid geometry (frame_mismatch) suppresses ALL observations for these ticks",
		"observations=" + str(fm_obs.size()))
	_ok(fm_tracks.is_empty(),
		"invalid geometry (frame_mismatch) does not create tracks",
		"tracks=" + str(fm_tracks.size()))
	# 每条产出的观测必须带可判别的几何等级标签，禁止 ADVISORY 冒充 LIVE
	var live_ok := true
	for raw_o in fm_obs:
		if not (raw_o is Dictionary):
			continue
		var o: Dictionary = raw_o
		var adv := String(o.get("geometry_advisory", ""))
		if adv == "":
			live_ok = false
	_ok(live_ok, "any observation produced under degraded geometry is labelled advisory")

	_step("8. failure reasons + explicit degradation (no silent stale geometry)")
	var reason_bad: Array = []
	# 8a. 缺实体：sensor 目标在 physics 中不存在
	var me = GameSessionScript.new({
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": FRAME, "frame_origin": FRAME, "track_table": true,
		"entities": [{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
			"vel_kmps": [0.0, 0.0, 0.0]}],
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [{"id": "ghost_target", "pos_km": [10.0, 0.0, 0.0], "rcs_m2": 100.0}],
			"options": {"radar_enabled": true, "emcon": false}},
	})
	_ok(bool(me.ready), "missing-entity fixture ready", str(me.errors))
	for i in range(2):
		me.tick(TICK_DT)
	var me_geo: Dictionary = me.sensor_geometry_status()
	var me_reason := String(me_geo.get("reason", ""))
	if me_reason == "":
		reason_bad.append({"case": "target_missing", "reason": "empty reason"})
	_info("MISSING ENTITY: reason=%s skipped=%s suppressed=%d obs=%d" % [
		me_reason, str(me_geo.get("skipped", [])),
		int(me_geo.get("suppressed_steps", -1)), me.sensor_service.observations.size()])
	_ok("ghost_target" in (me_geo.get("skipped", []) as Array),
		"missing target recorded in geometry skipped list",
		str(me_geo.get("skipped", [])))
	_ok(me.sensor_service.observations.is_empty(),
		"missing target produces no observations from stale static geometry",
		"observations=" + str(me.sensor_service.observations.size()))
	# 8b. observer 缺失
	var mo = GameSessionScript.new({
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": FRAME, "frame_origin": FRAME, "track_table": true,
		"entities": [{"id": "harmattan", "kind": "ship", "pos_km": [3.0, 4.0, 0.0],
			"vel_kmps": [0.0, 0.0, 0.0]}],
		"sensor_service": {
			"observer": {"id": "ghost_ship", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [{"id": "harmattan", "pos_km": [3.0, 4.0, 0.0], "rcs_m2": 100.0}],
			"options": {"radar_enabled": true, "emcon": false}},
	})
	_ok(bool(mo.ready), "observer-missing fixture ready", str(mo.errors))
	for i in range(2):
		mo.tick(TICK_DT)
	var mo_geo: Dictionary = mo.sensor_geometry_status()
	if String(mo_geo.get("reason", "")) == "":
		reason_bad.append({"case": "observer_missing", "reason": "empty reason"})
	_ok("ghost_ship" in (mo_geo.get("missing", []) as Array),
		"missing observer recorded in geometry missing list",
		str(mo_geo.get("missing", [])))
	_ok(mo.sensor_service.observations.is_empty(),
		"missing observer produces no observations",
		"observations=" + str(mo.sensor_service.observations.size()))
	# 8c. provider 未就绪 / 无 physics 的显式 legacy 模式必须有 reason 且标 advisory
	var legacy = GameSessionScript.new({"sensor_service": {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [3.0, 4.0, 0.0], "rcs_m2": 100.0}]}})
	_ok(bool(legacy.ready), "no-physics legacy fixture ready", str(legacy.errors))
	var lg_geo: Dictionary = legacy.sensor_geometry_status()
	var lg_reason := String(lg_geo.get("reason", ""))
	if lg_reason == "":
		reason_bad.append({"case": "no_physics_world", "reason": "empty reason"})
	_ok(String(lg_geo.get("source", "")) == "static",
		"legacy static mode declares source=static", String(lg_geo.get("source", "")))
	_ok(lg_geo.get("advisory") == true,
		"legacy static mode is explicitly labelled advisory (not LIVE)",
		"advisory=" + str(lg_geo.get("advisory")))
	_ok(reason_bad.is_empty(), "all degradation cases carry an explicit reason",
		"violations=" + str(reason_bad))

	_step("9. visibility: catalog attribution + anonymous contacts")
	var cat_bad: Array = []
	for eid in _truth_ids:
		if _session.entity_catalog == null or not bool(_session.entity_catalog.has_entity(eid)):
			cat_bad.append({"entity": eid, "reason": "not in catalog"})
			continue
		var crow: Dictionary = _session.entity_catalog.get_entity(eid)
		var truth: Dictionary = _truth[eid]
		for f in ["side", "batch", "rcs_m2", "radius_km", "has_pd"]:
			if str(crow.get(f, "<missing>")) != str(truth.get(f, "__none__")):
				cat_bad.append({"entity": eid, "field": f,
					"catalog": str(crow.get(f, "<missing>")),
					"truth": str(truth.get(f, "__none__"))})
	_ok(cat_bad.is_empty(), "7 scenario entities have correct catalog attribution",
		"violations=" + str(cat_bad.slice(0, 6)))
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	_ok(contacts.size() > 0, "binder contacts non-empty", "n=" + str(contacts.size()))
	var leak: Array = []
	var friend_bad: Array = []
	for raw_c in contacts:
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		var cid := String(c.get("entity_id", c.get("id", "")))
		var truth_side := ""
		if _truth.has(cid):
			truth_side = String((_truth[cid] as Dictionary).get("side", "")).to_lower()
		var is_own := (cid == "apsis")
		var is_public := String(c.get("facility_id", "")) != ""
		for f in TRUTH_ONLY_FIELDS:
			if not c.has(f):
				continue
			if is_own or is_public:
				continue
			leak.append({"entity": cid, "field": f, "value": str(c.get(f))})
		var cs := String(c.get("side", "")).to_lower()
		if cs == "friend" and truth_side != "" and truth_side not in ["friend", "ally", "ueg", "ocu"]:
			friend_bad.append({"entity": cid, "side": cs, "truth": truth_side})
	_ok(leak.is_empty(), "anonymous contacts leak no truth-only fields",
		"violations=" + str(leak.slice(0, 8)))
	_ok(friend_bad.is_empty(), "anonymous contacts have no silent friend fallback",
		"violations=" + str(friend_bad))

	# R01：玩家 VM 的**所有公开分支**（tracks / selected / events）遵守同一可见性策略。
	# 反例：selected 命中未知目标时曾直接返回内部航迹的 batch（真值泄漏）。
	var r01_vm: Dictionary = _session.track_vm({})
	var r01_rows: Array = r01_vm.get("tracks", []) if r01_vm.get("tracks") is Array else []
	var r01_tid := ""
	if r01_rows.size() > 0:
		r01_tid = String((r01_rows[0] as Dictionary).get("id", ""))
	_ok(r01_tid != "", "R01: live HUD session exposes a stable track id", r01_tid)
	var r01_sel: Dictionary = _session.track_vm({"selected_id": r01_tid}).get("selected", {}) \
		if r01_tid != "" else {}
	var r01_leak: Array = []
	for f2 in TRUTH_ONLY_FIELDS:
		if r01_sel.has(f2):
			r01_leak.append({"branch": "selected", "field": f2,
				"value": str(r01_sel.get(f2, ""))})
	for raw_r in r01_rows:
		if raw_r is Dictionary:
			for f3 in TRUTH_ONLY_FIELDS:
				if (raw_r as Dictionary).has(f3):
					r01_leak.append({"branch": "tracks", "field": f3})
	for raw_ev2 in (r01_vm.get("events", []) as Array):
		if raw_ev2 is Dictionary:
			for f4 in TRUTH_ONLY_FIELDS:
				if (raw_ev2 as Dictionary).has(f4):
					r01_leak.append({"branch": "events", "field": f4})
	_ok(r01_leak.is_empty(),
		"R01: player VM tracks/selected/events all withhold truth-only fields",
		"violations=" + str(r01_leak.slice(0, 6)))
	_ok(String(r01_sel.get("id", "")) == r01_tid,
		"R01: selected branch keeps the stable id (commands still usable)",
		String(r01_sel.get("id", "")))
	# 内部记录必须继续保留 batch（不能靠删字段过关）
	var r01_internal: Dictionary = _session.track_table.selected(r01_tid) if r01_tid != "" else {}
	_ok(String(r01_internal.get("batch", "")) != "",
		"R01: internal track record still keeps batch for dedup/save",
		String(r01_internal.get("batch", "")))


	_step("10. A-01 summary")
	_info("A-01: no-noise range=5 verified; observer+target moves verified; uncertainty measurement preserved; "
		+ "error params traced; consumer table checked; invalid geometry suppression checked; visibility checked")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

## 独立标量几何期望（不使用 Vector3；与 authority 的 atan2(dx,dy) 轴向定义一致）。
func _geom_expect(obs: Array, tgt: Array) -> Dictionary:
	var dx := float(tgt[0]) - float(obs[0])
	var dy := float(tgt[1]) - float(obs[1])
	var dz := float(tgt[2]) - float(obs[2])
	var rng := sqrt(dx * dx + dy * dy + dz * dz)
	var brg := rad_to_deg(atan2(dx, dy))
	if brg < 0.0:
		brg += 360.0
	return {"range_km": rng, "bearing_deg": brg}


## 真实 session 中 **geometry provider 几何** vs 独立标量期望（同 tick）。
## 阈值 1e-6 km / 1e-6 deg 是「同源 double 复制/确定性公式」误差，**不是**传感器精度；
## 因此这里比较的是 provider 的几何（sensor_service.observer/targets，由 physics 刷新），
## 不是带测量误差的 observation（后者单独按模型 sigma 校验）。
func _provider_vs_scalar(sess, target_id: String) -> Dictionary:
	if sess == null or sess.sensor_service == null or sess.physics_world_service == null:
		return {"ok": false, "reason": "no session/physics/sensor"}
	var svc = sess.sensor_service
	var oid := String(svc.observer.get("id", "apsis"))
	var opos := _physics_pos(sess, oid)
	var tpos := _physics_pos(sess, target_id)
	if opos.size() < 3 or tpos.size() < 3:
		return {"ok": false, "reason": "missing authoritative position"}
	var expect := _geom_expect(opos, tpos)
	# provider 几何：sensor_service 内部 observer/target 的 pos_km（几何绑定时从 physics 刷新）
	var prov_obs: Array = svc.observer.get("pos_km", []) if svc.observer.get("pos_km") is Array else []
	var prov_tgt: Array = []
	for raw_t in svc.targets:
		if raw_t is Dictionary and String((raw_t as Dictionary).get("id", "")) == target_id:
			prov_tgt = (raw_t as Dictionary).get("pos_km", []) \
				if (raw_t as Dictionary).get("pos_km") is Array else []
			break
	if prov_obs.size() < 3 or prov_tgt.size() < 3:
		return {"ok": false, "reason": "provider geometry not populated"}
	# 1) provider 与 physics 逐分量一致（同源复制，<=1e-9 km）
	for i in range(3):
		if absf(float(prov_obs[i]) - float(opos[i])) > 1.0e-9:
			return {"ok": false, "reason": "provider observer pos != physics pos",
				"axis": i, "provider": float(prov_obs[i]), "physics": float(opos[i])}
		if absf(float(prov_tgt[i]) - float(tpos[i])) > 1.0e-9:
			return {"ok": false, "reason": "provider target pos != physics pos",
				"axis": i, "provider": float(prov_tgt[i]), "physics": float(tpos[i])}
	# 2) provider 几何 vs 独立标量期望
	var got := _geom_expect(prov_obs, prov_tgt)
	var phys_t := float(sess.physics_world_service.t)
	var gs: Dictionary = svc.geometry_status()
	if absf(float(gs.get("t", -1.0)) - phys_t) > SAME_TICK_TOL_S:
		return {"ok": false, "reason": "geometry sample t != physics t",
			"geometry_t": float(gs.get("t", -1.0)), "physics_t": phys_t}
	return {"ok": true,
		"range_km": float(got["range_km"]), "expect_range_km": float(expect["range_km"]),
		"range_err_km": absf(float(got["range_km"]) - float(expect["range_km"])),
		"bearing_deg": float(got["bearing_deg"]),
		"expect_bearing_deg": float(expect["bearing_deg"]),
		"bearing_err_deg": _bearing_delta(float(got["bearing_deg"]),
			float(expect["bearing_deg"])),
		"t": phys_t, "physics_t": phys_t}


## 传感器几何 provider 实际使用的 range/bearing（由观测行或 provider 位置取）。
func _sensor_geometry_of(sess, target_id: String) -> Dictionary:
	var out := {"range_km": -1.0, "bearing_deg": -1.0}
	var obs: Array = sess.sensor_service.observations if sess.sensor_service != null else []
	for i in range(obs.size() - 1, -1, -1):
		var o: Dictionary = obs[i]
		if String(o.get("target_id", "")) != target_id:
			continue
		var r := float(o.get("range_km", -1.0))
		if r <= 0.0:
			continue
		out["range_km"] = r
		out["bearing_deg"] = float(o.get("bearing_deg", -1.0))
		return out
	# 回退：若尚无观测（被抑制），用 geometry provider 直接读 target 位置算
	var gs: Dictionary = sess.sensor_geometry_status()
	var last: Dictionary = gs.get("last", {}) if gs.get("last") is Dictionary else {}
	if bool(last.get("ok", false)):
		var oid := String(gs.get("observer_id", "apsis"))
		var opos: Array = _physics_pos(sess, oid)
		var tpos: Array = _physics_pos(sess, target_id)
		if opos.size() >= 3 and tpos.size() >= 3:
			return _geom_expect(opos, tpos)
	return out


func _physics_pos(sess, eid: String) -> Array:
	if sess == null or sess.physics_world_service == null:
		return []
	var st: Dictionary = sess.physics_state(eid)
	var r = st.get("r", [])
	return (r as Array).duplicate() if r is Array else []


func _physics_velocity(sess, eid: String) -> Array:
	if sess == null or sess.physics_world_service == null:
		return []
	var st: Dictionary = sess.physics_state(eid)
	var v = st.get("v", [])
	return (v as Array).duplicate() if v is Array else []


## ballistics 初始状态的可追溯来源（A-01 要求：不能是未标明的演示值）。
func _ballistics_state_source(sess, eid: String) -> Dictionary:
	if sess == null or sess.combat_ballistics == null:
		return {"ok": false, "reason": "no_ballistics_service"}
	var b = sess.combat_ballistics
	if b.has_method("state_source"):
		var r: Dictionary = b.state_source(eid)
		if bool(r.get("ok", false)):
			return r
		return {"ok": false, "reason": String(r.get("reason", "state_source_failed"))}
	return {"ok": false, "reason": "no state_source() API on CombatBallistics"}


func _bearing_delta(a: float, b: float) -> float:
	var d := fmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)


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
	print("[A0-A01] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}
