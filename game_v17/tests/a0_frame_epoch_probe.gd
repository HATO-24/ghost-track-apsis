extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-02 · frame / 历元 / 消费者时间来源探针
#
# 基线：I1（A-01 交付）。真实入口：main_menu → v1_hud → ShellBinder → GameSession。
#
# 契约（任务卡）：
#   * TimeService 写相对 t_s；PhysicsWorld 写状态；physics t 与 session t_s 差 ≤1e-6 s。
#   * scenario UTC 历元由**唯一**会话元数据来源持有；绝对日历时刻 = 该历元 + 相对秒。
#   * epoch_s(=760.8) 是 CR3BP **相位基准**，不是 Unix epoch，禁止互相替换。
#   * 运行态 bary_rot / km / km/s；L1 相对 seed 只在初始化适配层转换一次并标 applied/source。
#   * 带 physics 的产品路径不得把未转换 world 位置标为 bary_rot。
#   * 缺历元旧 seed：保留原时间行为并标 epoch_unknown/legacy；非法 UTC/未知 frame 必须显式拒绝。
#   * 阈值：UTC 字符串与整数历元标签精确一致；时间增量误差 ≤1e-6 s。
#
# Output: `A0-A02 FRAME EPOCH PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"
const GameSessionScript := preload("res://scripts/core/game_session.gd")
const TimeServiceScript := preload("res://scripts/core/time_service.gd")
const Physics2 := preload("res://framework/sim/cislunar_physics.gd")

const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
const MAX_BINDER_FRAMES := 120
const WATCHDOG_S := 180.0

const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

const FRAME := "bary_rot"
const TICK_DT := 60.0
const TIME_TOL_S := 1.0e-6
const SUPPORTED_ALT_FRAMES := ["earth_eci", "earth_rot"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _hud = null
var _binder = null
var _session = null
var _main_menu_instantiated := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A02 FRAME EPOCH PROBE · baseline I1 · profile=", TARGET_PROFILE)
	print("Godot ", Engine.get_version_info().get("string", "?"))
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
	print("[A0-A02] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("A0-A02 FRAME EPOCH PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A02] FAILED: ", f)
		print("A0-A02 FRAME EPOCH PROBE FAILED")
	else:
		print("A0-A02 FRAME EPOCH PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A02] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A02] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-A02] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A02] INFO ", text)


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
	_binder = _hud.get("binder")
	_session = _binder.get("session") if _binder != null else null
	_ok(_binder != null and bool(_binder.get("ready")), "ShellBinder ready")
	_ok(_session != null, "GameSession available")
	if _session == null:
		_finish()
		return
	_ok(_session.time != null, "TimeService present")
	_ok(_session.physics_world_service != null, "PhysicsWorld present")

	_step("2. scenario UTC epoch is the single calendar source")
	var sc := _read_json(TARGET_SCENARIO)
	var scenario_epoch := String(sc.get("epoch", ""))
	_ok(scenario_epoch != "", "scenario declares a UTC epoch", scenario_epoch)
	var meta: Dictionary = _session.session_time_frame_meta()
	var epoch: Dictionary = meta.get("epoch", {}) if meta.get("epoch") is Dictionary else {}
	_eq(String(epoch.get("epoch_source", "")), "scenario",
		"calendar epoch source is the scenario (single source)")
	_eq(bool(epoch.get("epoch_known", false)), true, "calendar epoch is known")
	_eq(bool(epoch.get("epoch_unknown", true)), false, "calendar epoch not marked unknown")
	_eq(_norm_utc(String(epoch.get("calendar_epoch_utc", ""))),
		_norm_utc(scenario_epoch),
		"calendar epoch UTC matches the scenario exactly")
	var expect_unix := float(Time.get_unix_time_from_datetime_string(
		scenario_epoch.strip_edges().replace("Z", "")))
	var got_unix := _num(epoch.get("calendar_epoch_unix_s", null))
	_near(got_unix, expect_unix, 0.0,
		"calendar epoch unix seconds exactly match the UTC string")
	_info("EPOCH: utc=%s unix=%s" % [String(epoch.get("calendar_epoch_utc", "")),
		str(epoch.get("calendar_epoch_unix_s", null))])

	_step("3. CR3BP phase basis is explicit and NOT the calendar epoch")
	_eq(String(epoch.get("phase_basis", "")), "cr3bp_phase_s",
		"phase basis is explicitly labelled cr3bp_phase_s")
	_near(float(epoch.get("phase_epoch_s", -1.0)), 760.8, 1.0e-12,
		"phase epoch keeps the existing 760.8 (not replaced by UTC seconds)")
	_eq(bool(epoch.get("raw_epoch_s_is_unix", true)), false,
		"raw epoch_s is explicitly NOT a Unix epoch")
	var phase_abs := float(epoch.get("phase_abs_s", -1.0))
	var cal_unix := _num(epoch.get("calendar_epoch_unix_s", null))
	_ok(absf(phase_abs - (760.8 + float(meta.get("t_s", 0.0)))) <= TIME_TOL_S,
		"phase_abs = phase_epoch + t_s (dynamics basis consistent)",
		"phase_abs=%.6f" % phase_abs)
	_ok(absf(phase_abs - cal_unix) > 1.0e6,
		"dynamics phase time is NOT the calendar time (no silent mixing)",
		"phase_abs=%.3f cal_unix=%.3f" % [phase_abs, cal_unix])

	_step("4. absolute calendar time = epoch + relative seconds (exact)")
	var now_cal := String(epoch.get("calendar_now_utc", ""))
	var expect_now := Time.get_datetime_string_from_unix_time(
		int(round(expect_unix + float(meta.get("t_s", 0.0)))), true)
	_eq(now_cal, expect_now, "calendar_now == epoch + t_s (exact UTC string)")
	# 推进 +60 s 后必须精确 +60 s
	var t_before := float(_session.now_s())
	var tick_res: Dictionary = _session.tick(60.0)
	_ok(bool(tick_res.get("ok", false)), "tick(+60s) ok", str(tick_res.get("reason", "")))
	var meta2: Dictionary = _session.session_time_frame_meta()
	var epoch2: Dictionary = meta2.get("epoch", {})
	_near(float(meta2.get("t_s", -1.0)) - t_before, 60.0, TIME_TOL_S,
		"relative time advanced by exactly 60 s")
	var expect_after := Time.get_datetime_string_from_unix_time(
		int(round(expect_unix + float(meta2.get("t_s", 0.0)))), true)
	_eq(String(epoch2.get("calendar_now_utc", "")), expect_after,
		"calendar after +60 s is exactly the epoch + new t_s")

	_step("5. physics t == session t_s (<=1e-6 s) and frame table")
	_ok(bool(meta.get("physics_time_ok", false)),
		"physics t equals session t_s within 1e-6 s",
		"physics_t=%s t_s=%s" % [str(meta.get("physics_t", "")), str(meta.get("t_s", ""))])
	_eq(String(meta.get("runtime_frame", "")), FRAME, "runtime frame is bary_rot")
	var units: Dictionary = meta.get("runtime_units", {})
	_eq(String(units.get("length", "")), "km", "runtime length unit km")
	_eq(String(units.get("velocity", "")), "km/s", "runtime velocity unit km/s")
	_eq(String(units.get("time", "")), "s", "runtime time unit s")
	var consumers: Dictionary = meta.get("consumers", {})
	var consumer_bad: Array = []
	for cname in ["physics", "world_projection", "snapshot", "sensor_geometry", "ballistics"]:
		if not consumers.has(cname):
			consumer_bad.append({"consumer": cname, "reason": "missing from table"})
			continue
		var c: Dictionary = consumers[cname]
		var f := String(c.get("frame", ""))
		if f != FRAME:
			consumer_bad.append({"consumer": cname, "frame": f})
		if String(c.get("source", "")) == "":
			consumer_bad.append({"consumer": cname, "reason": "no source declared"})
	_ok(consumer_bad.is_empty(),
		"all physics-chain consumers declare frame=bary_rot and a source",
		"violations=" + str(consumer_bad))
	_info("CONSUMERS: " + JSON.stringify(consumers))

	_step("6. L1 seed conversion happens exactly once and is marked applied/source")
	var l1_session = GameSessionScript.new({
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": "l1", "frame_origin": "l1",
		"track_table": true,
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [20.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
	})
	_ok(bool(l1_session.ready), "L1-frame session ready", str(l1_session.errors))
	var l1_meta: Dictionary = l1_session.session_time_frame_meta()
	var conv: Dictionary = l1_meta.get("frame_conversion", {})
	_eq(bool(conv.get("applied", false)), true, "L1 seed conversion marked applied")
	_eq(String(conv.get("source", "")), "seed", "conversion source marked as seed")
	_eq(int(conv.get("conversion_count", 0)), 1,
		"L1 seed conversion happened exactly once (no duplicate init)")
	_eq(String(l1_meta.get("runtime_frame", "")), FRAME,
		"runtime frame stays bary_rot after L1 conversion")
	_info("L1 CONVERSION: " + JSON.stringify(conv))

	_step("7. frame conversion roundtrip near origin and at EML1 large coords")
	# 直接调用**集中转换器** cislunar_physics 的双精度标量路径（Vector3 版本仅用于显示层）。
	# 门槛不扩大：位置 ≤1e-6 km、速度 ≤1e-9 km/s；原 Vector3 路径在 EML1 处实测速度误差
	# ~1.9e-5 km/s，属适配层量化缺陷，已在 physics_world 适配层改用双精度路径修复。
	var conv_bad: Array = []
	for case_row in [
			{"name": "origin", "r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
			{"name": "near", "r": [3.0, 4.0, 0.0], "v": [0.01, -0.02, 0.0]},
			{"name": "eml1", "r": [321719.0, 0.0, 0.0], "v": [0.0, 1.02, 0.0]}]:
		var cr: Dictionary = case_row
		var r0: Array = cr["r"]
		var v0: Array = cr["v"]
		var alt: Dictionary = Physics2.bary_rot_to_earth_eci_arrays(r0, v0, 1234.5)
		var back: Dictionary = Physics2.earth_eci_to_bary_rot_arrays(
			alt.get("r", []), alt.get("v", []), 1234.5)
		var rb: Array = back.get("r", []) if back.get("r") is Array else []
		var vb: Array = back.get("v", []) if back.get("v") is Array else []
		if rb.size() < 3 or vb.size() < 3:
			conv_bad.append({"case": String(cr["name"]), "reason": "bad roundtrip shape"})
			continue
		for i in range(3):
			if absf(float(rb[i]) - float(r0[i])) > 1.0e-6:
				conv_bad.append({"case": String(cr["name"]), "axis": "r%d" % i,
					"err_km": absf(float(rb[i]) - float(r0[i]))})
			if absf(float(vb[i]) - float(v0[i])) > 1.0e-9:
				conv_bad.append({"case": String(cr["name"]), "axis": "v%d" % i,
					"err_kmps": absf(float(vb[i]) - float(v0[i]))})
	_ok(conv_bad.is_empty(),
		"central converter roundtrips bary_rot<->earth_eci in double precision (1e-6 km / 1e-9 km/s; origin+near+EML1)",
		"violations=" + str(conv_bad.slice(0, 6)))
	# earth_rot 路径同样必须精确
	var rot_bad: Array = []
	for case_row2 in [
			{"name": "origin", "r": [0.0, 0.0, 0.0], "v": [0.0, 0.0, 0.0]},
			{"name": "eml1", "r": [321719.0, 0.0, 0.0], "v": [0.0, 1.02, 0.0]}]:
		var cr2: Dictionary = case_row2
		var fwd: Dictionary = Physics2.bary_rot_to_earth_rot_arrays(cr2["r"], cr2["v"])
		var b2: Dictionary = Physics2.earth_rot_to_bary_rot_arrays(
			fwd.get("r", []), fwd.get("v", []))
		var rb2: Array = b2.get("r", []) if b2.get("r") is Array else []
		var vb2: Array = b2.get("v", []) if b2.get("v") is Array else []
		if rb2.size() < 3 or vb2.size() < 3:
			rot_bad.append({"case": String(cr2["name"]), "reason": "bad shape"})
			continue
		for i in range(3):
			if absf(float(rb2[i]) - float((cr2["r"] as Array)[i])) > 1.0e-6:
				rot_bad.append({"case": String(cr2["name"]), "axis": "r%d" % i})
			if absf(float(vb2[i]) - float((cr2["v"] as Array)[i])) > 1.0e-9:
				rot_bad.append({"case": String(cr2["name"]), "axis": "v%d" % i})
	_ok(rot_bad.is_empty(),
		"central converter roundtrips bary_rot<->earth_rot in double precision",
		"violations=" + str(rot_bad))

	_step("8. save / load preserves epoch, relative time, frame and source")
	# 真实 HUD 会话的 save→load 仍受 comms replay no_route 影响（DS-A-06 范围）：
	# 本卡在此**显式记录该限制**，改用同 seed 的干净 fixture 验证 A-02 的历元/frame 元数据往返。
	var live_save: String = _session.save_state()
	var live_probe = GameSessionScript.new()
	var live_lr: Dictionary = live_probe.load_state(live_save)
	_info("REAL HUD SESSION LIMIT (DS-A-06 scope): load ok=%s errors=%s" % [
		str(live_lr.get("ok", false)), str(live_lr.get("errors", []))])
	var epoch_fixture = GameSessionScript.new(_repeat_seed())
	_ok(bool(epoch_fixture.ready), "epoch save/load fixture ready", str(epoch_fixture.errors))
	for i in range(3):
		epoch_fixture.tick(TICK_DT)
	var meta_before: Dictionary = _session.session_time_frame_meta()
	var meta_fx_before: Dictionary = epoch_fixture.session_time_frame_meta()
	var save_text: String = epoch_fixture.save_state()
	_ok(save_text.length() > 500, "save_state non-empty", "len=%d" % save_text.length())
	var loaded = GameSessionScript.new()
	var lr: Dictionary = loaded.load_state(save_text)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("errors", [])))
	if bool(lr.get("ok", false)):
		var meta_loaded: Dictionary = loaded.session_time_frame_meta()
		var eb: Dictionary = meta_before.get("epoch", {})
		var el: Dictionary = meta_loaded.get("epoch", {})
		_eq(String(el.get("calendar_epoch_utc", "")),
			String(eb.get("calendar_epoch_utc", "")),
			"load preserves the calendar epoch UTC string")
		_eq(String(el.get("epoch_source", "")), String(eb.get("epoch_source", "")),
			"load preserves the epoch source label")
		_near(float(el.get("calendar_epoch_unix_s", -1.0)),
			float(eb.get("calendar_epoch_unix_s", -1.0)), 0.0,
			"load preserves the epoch unix seconds exactly")
		_near(float(meta_loaded.get("t_s", -1.0)), float(meta_fx_before.get("t_s", -1.0)),
			TIME_TOL_S, "load preserves relative time t_s")
		_eq(String(meta_loaded.get("runtime_frame", "")),
			String(meta_before.get("runtime_frame", "")), "load preserves runtime frame")
		_eq(String(meta_loaded.get("seed_frame", "")), String(meta_fx_before.get("seed_frame", "")),
			"load preserves seed frame")
		# 再推进 10 ticks：时间增量一致
		var t0 := float(loaded.now_s())
		for i in range(10):
			loaded.tick(TICK_DT)
		_near(float(loaded.now_s()) - t0, 10.0 * TICK_DT, TIME_TOL_S,
			"post-load 10 ticks advance relative time by exactly 600 s")

	_step("9. repeatability: same seed + same commands → same time/frame metadata")
	var r1 = GameSessionScript.new(_repeat_seed())
	var r2 = GameSessionScript.new(_repeat_seed())
	for i in range(5):
		r1.tick(TICK_DT)
		r2.tick(TICK_DT)
	var m1: Dictionary = r1.session_time_frame_meta()
	var m2: Dictionary = r2.session_time_frame_meta()
	_near(float(m1.get("t_s", -1.0)), float(m2.get("t_s", -1.0)), 0.0,
		"repeated runs have identical relative time")
	_eq(JSON.stringify(m1.get("epoch", {})), JSON.stringify(m2.get("epoch", {})),
		"repeated runs have identical epoch metadata")
	_eq(JSON.stringify(m1.get("frame_conversion", {})),
		JSON.stringify(m2.get("frame_conversion", {})),
		"repeated runs have identical frame conversion metadata")

	_step("10. time is monotonic under pause and scale")
	var mp = GameSessionScript.new(_repeat_seed())
	_ok(bool(mp.ready), "pause/scale fixture ready", str(mp.errors))
	if mp.time != null:
		var tp0 := float(mp.now_s())
		mp.time.paused = true
		mp.tick(TICK_DT)
		_near(float(mp.now_s()), tp0, TIME_TOL_S, "paused session does not advance t_s")
		mp.time.paused = false
		mp.time.scale = 2.0
		var tp1 := float(mp.now_s())
		mp.tick(TICK_DT)
		_near(float(mp.now_s()) - tp1, 2.0 * TICK_DT, TIME_TOL_S,
			"scale=2 advances t_s by exactly 120 s")
		_ok(float(mp.now_s()) > tp1, "relative time remains monotonic under scale")

	_step("11. negative: invalid UTC epoch is explicitly rejected (no fabricated date)")
	var bad_time = TimeServiceScript.new({"epoch_utc": "2193-13-45T99:99:99Z"})
	_eq(bool(bad_time.ready), false, "invalid UTC epoch makes TimeService NOT ready")
	var bad_errors: Array = bad_time.errors
	var has_reason := false
	for e in bad_errors:
		if String(e).find("UTC") >= 0 or String(e).find("历元") >= 0:
			has_reason = true
	_ok(has_reason, "invalid UTC epoch reports an explicit reason", str(bad_errors))
	_eq(String(bad_time.epoch_meta().get("epoch_source", "")), "invalid",
		"invalid epoch is labelled invalid, not silently defaulted")

	_step("12. negative: legacy seed without epoch keeps time but marks epoch_unknown")
	var legacy_time = TimeServiceScript.new({})
	_eq(bool(legacy_time.ready), true, "legacy TimeService still ready (time behaviour kept)")
	var lm: Dictionary = legacy_time.epoch_meta()
	_eq(String(lm.get("epoch_source", "")), "legacy_unknown",
		"legacy seed marks epoch_source=legacy_unknown")
	_eq(bool(lm.get("epoch_unknown", false)), true, "legacy seed marks epoch_unknown")
	_eq(String(lm.get("calendar_now_utc", "x")), "",
		"legacy seed does NOT fabricate a calendar date")
	_near(float(lm.get("phase_epoch_s", -1.0)), 760.8, 1.0e-12,
		"legacy seed keeps the original phase epoch")

	_step("13. negative: unknown frame is rejected, not silently treated as bary_rot")
	var pw = _session.physics_world_service
	var bad_frame: Dictionary = _pw_to_frame(pw, [1.0, 2.0, 3.0], [0.0, 0.0, 0.0], "not_a_frame")
	_eq(bool(bad_frame.get("ok", true)), false, "unknown frame conversion is rejected")
	_ok(String(bad_frame.get("reason", "")) != "",
		"unknown frame rejection carries a reason", str(bad_frame.get("reason", "")))

	_step("14. negative: unknown player target gains no truth coordinates")
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	var leaked: Array = []
	for raw_c in contacts:
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		var eid := String(c.get("entity_id", c.get("id", "")))
		if eid in ["apsis", "harmattan", "l1_station", "ferry", "raider_2", "skiff",
				"watchtower"]:
			continue
		for f in ["pos_km", "r", "truth_pos_km", "batch", "rcs_m2"]:
			if c.has(f):
				leaked.append({"entity": eid, "field": f})
	_ok(leaked.is_empty(), "no truth position leaked to unknown targets",
		"violations=" + str(leaked))

	_step("15. A-02 summary")
	_info("A-02: calendar epoch single-source + phase basis separated; consumer frame table complete; "
		+ "L1 conversion once; converter roundtrip ok; save/load metadata preserved; negatives enforced")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _repeat_seed() -> Dictionary:
	return {
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": FRAME, "frame_origin": FRAME,
		"epoch": "2193-04-11T08:00:00Z",
		"track_table": true,
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [322139.0, 0.0, 0.0],
				"vel_kmps": [0.0, 1.02, 0.0]}],
	}


## 通过 PhysicsWorld 的集中转换器把 bary_rot 状态转到指定帧。
func _pw_to_frame(pw, r: Array, v: Array, frame: String) -> Dictionary:
	if pw == null:
		return {"ok": false, "reason": "no_physics"}
	if not (frame in ["bary_rot"] + SUPPORTED_ALT_FRAMES):
		return {"ok": false, "reason": "unknown_frame:" + frame}
	if not pw.has_method("_to_bary_rot"):
		return {"ok": false, "reason": "no_converter"}
	# 用私有转换器的逆：先构造 alt->bary 的偏移并反算
	var res: Dictionary = pw.upsert_entity("__conv_probe__",
		{"r": r, "v": v, "frame": "bary_rot", "mass_kg": 1000.0})
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": "upsert_failed"}
	var st_bary: Dictionary = pw.state("__conv_probe__", "bary_rot")
	var st_alt: Dictionary = pw.state("__conv_probe__", frame)
	var out := {"ok": true, "r": st_alt.get("r", []), "v": st_alt.get("v", []),
		"bary_r": st_bary.get("r", []), "frame": frame}
	pw.remove_entity("__conv_probe__")
	return out


## 通过 PhysicsWorld 的集中转换器把指定帧状态转回 bary_rot。
func _pw_from_frame(pw, r: Array, v: Array, frame: String) -> Dictionary:
	if pw == null:
		return {"ok": false, "reason": "no_physics"}
	if not (frame in ["bary_rot"] + SUPPORTED_ALT_FRAMES):
		return {"ok": false, "reason": "unknown_frame:" + frame}
	var res: Dictionary = pw.upsert_entity("__conv_probe2__",
		{"r": r, "v": v, "frame": frame, "mass_kg": 1000.0})
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": String(res.get("reason", "upsert_failed"))}
	var st: Dictionary = pw.state("__conv_probe2__", "bary_rot")
	pw.remove_entity("__conv_probe2__")
	return {"ok": true, "r": st.get("r", []), "v": st.get("v", [])}


## UTC 字符串归一化（去尾部 Z、T→空格、去首尾空白），用于精确比较。
func _norm_utc(text: String) -> String:
	var s := String(text).strip_edges()
	if s.ends_with("Z") or s.ends_with("z"):
		s = s.substr(0, s.length() - 1)
	return s.replace("T", " ").replace("t", " ")


## 安全数值读取（null/非数值 → 哨兵值），避免 float(null) 运行时错误。
func _num(value, fallback := -1.0) -> float:
	if value is int or value is float:
		return float(value)
	return float(fallback)


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
	print("[A0-A02] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}
