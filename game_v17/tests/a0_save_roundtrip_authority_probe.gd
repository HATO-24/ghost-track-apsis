extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A-01 / A0-T3 · 存档往返权威探针
#
# 真实产品入口链路：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
# 检查 physics / world / track / sensor / identification 的 save → load 往返：
#
#   1) 数值误差 ≤ 1e-9（physics r/v、world pos/vel、track range 等）
#   2) 整数类型不漂移（事件 seq、计数类字段必须仍是 int，不是 float）
#   3) SensorService 运行态持久化（EMCON / radar / channels）
#   4) save → load → save canonical equality（两次存档 JSON 规范化后一致）
#   5) 1000 tick 存档性能（体积 / 耗时，记录为 INFO 证据）
#
# 预期失败（Phase A 基线，**不得隐藏**）：
#   - 事件 `seq` int → float 漂移（JSON 往返）；
#   - SensorService 运行态未持久化（存档无 sensor_service 运行态；EMCON/radar 读档后丢失）；
#   - 由此导致 save→load→save canonical equality 失败。
#
# Output: `A0-T3 SAVE ROUNDTRIP AUTHORITY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
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

const TICK_DT := 60.0
const SAVE_TICKS := 5
const PERF_TICKS := 1000
const NUM_TOL := 1.0e-9
const TIME_TOL_S := 1.0e-6

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
	print("A0-T3 SAVE ROUNDTRIP AUTHORITY PROBE · real entry main_menu → v1_hud")
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
	print("[A0-T3] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("A0-T3 SAVE ROUNDTRIP AUTHORITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T3] FAILED: ", f)
		print("A0-T3 SAVE ROUNDTRIP AUTHORITY PROBE FAILED")
	else:
		print("A0-T3 SAVE ROUNDTRIP AUTHORITY PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-T3] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-T3] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-T3] STEP ", title)


func _info(text: String) -> void:
	print("[A0-T3] INFO ", text)


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
	if _session.physics_world_service == null or _session.sensor_service == null:
		_finish()
		return

	var sc := _read_json(TARGET_SCENARIO)
	for raw in (sc.get("entities", []) if sc.get("entities") is Array else []):
		if raw is Dictionary:
			_truth[String((raw as Dictionary).get("id", ""))] = (raw as Dictionary).duplicate(true)
	_eq(_truth.size(), 7, "scenario truth table has 7 entities")

	_step("2. drive %d ticks on the live HUD session, then save" % SAVE_TICKS)
	for i in range(SAVE_TICKS):
		var tk: Dictionary = _session.tick(TICK_DT)
		_ok(bool(tk.get("ok", false)), "tick %d ok" % (i + 1),
			"reason=" + String(tk.get("reason", "")))
	var save_text: String = _session.save_state()
	_ok(save_text.length() > 500, "live session save_state non-empty",
		"len=%d" % save_text.length())

	_step("3. physics/world roundtrip: numeric error <= " + str(NUM_TOL))
	# 3a. 真实 HUD session 自身 save→load（暴露真实入口的往返缺陷）
	var s_live = GameSessionScript.new()
	var lr_live: Dictionary = s_live.load_state(save_text)
	var live_errors: Array = lr_live.get("errors", []) if lr_live.get("errors") is Array else []
	_ok(bool(lr_live.get("ok", false)),
		"live HUD session save→load ok (real entry roundtrip)",
		"errors=" + str(live_errors))
	_info("A0-T3 BASELINE: live session load ok=%s errors=%s" % [
		str(lr_live.get("ok", false)), str(live_errors)])
	# 3b. 用同一 scenario seed 的干净 session 完成权威往返检查。
	#     live session 的 comms 种子路由会在 replay 时命中 no_route（独立的 comms replay
	#     缺陷，已在 3a 单独记录），不让它掩盖 physics/world/track 往返结论。
	var sv = GameSessionScript.new(_roundtrip_seed())
	_ok(bool(sv.ready), "roundtrip fixture session ready", str(sv.errors))
	for i in range(SAVE_TICKS):
		sv.tick(TICK_DT)
	# A0-T3 审查修正（P2）：fixture 必须产生**非空** channels，且启动多个通道以覆盖
	# 内容比较。通道启动与随后的 tick 必须在**捕获 pre-state 之前**完成，否则
	# pre_phys/pre_tracks 会相对最后一次 tick 变陈旧（导致假失败）。
	var ch_ready: Dictionary = sv.sensor_service.start_channel("optical", "harmattan")
	_ok(bool(ch_ready.get("ok", false)), "fixture started an optical channel",
		str(ch_ready.get("reason", "")))
	var ch_ready2: Dictionary = sv.sensor_service.start_channel("ir", "harmattan")
	_ok(bool(ch_ready2.get("ok", false)), "fixture started an ir channel",
		str(ch_ready2.get("reason", "")))
	# 再推进一个 tick，让 channels 缓存刷新且包含这些通道。
	sv.tick(TICK_DT)
	# ── 捕获 pre-state（必须在所有 tick 之后）──
	var pre_phys: Dictionary = {}
	for eid in _truth.keys():
		var st: Dictionary = sv.physics_state(eid)
		pre_phys[eid] = {"r": (st.get("r", []) as Array).duplicate(),
			"v": (st.get("v", []) as Array).duplicate()}
	var pre_world: Dictionary = {}
	for eid in _truth.keys():
		var we: Dictionary = sv.world.entity(eid)
		pre_world[eid] = {"pos_km": (we.get("pos_km", []) as Array).duplicate(),
			"vel_kmps": (we.get("vel_kmps", []) as Array).duplicate()}
	var pre_tracks: Array = sv.track_table.vm().get("tracks", []) \
		if sv.track_table.vm().get("tracks") is Array else []
	# A0-T3 审查修正（P1）：显式把 EMCON 切到与初始值**相反**的状态，并确认确实改变；
	# 否则「读档后相等」可能只是默认值碰巧相同，无法证明 save/load 保留了 EMCON。
	# 注意：EMCON 切换不推进 tick，所以上面的 pre-state（物理/航迹）仍然有效。
	var initial_emcon := bool(sv.sensor_service.emcon)
	var initial_radar := bool(sv.sensor_service.radar_enabled)
	_info("A0-T3 SENSOR fixture: initial emcon=%s radar=%s" % [
		str(initial_emcon), str(initial_radar)])
	# set_emcon 会联动 radar_enabled = not emcon；这里显式翻转 EMCON。
	sv.sensor_service.set_emcon(not initial_emcon)
	var mutated_emcon := bool(sv.sensor_service.emcon)
	var mutated_radar := bool(sv.sensor_service.radar_enabled)
	_ok(mutated_emcon != initial_emcon,
		"EMCON actually toggled to the opposite state before save",
		"initial=%s mutated=%s" % [str(initial_emcon), str(mutated_emcon)])
	# 再验证 radar 与 EMCON 的联动关系符合契约（emcon == not radar_enabled）。
	var radar_lnk := (mutated_radar == (not mutated_emcon))
	_ok(radar_lnk, "radar_enabled is the inverse of emcon after explicit toggle",
		"emcon=%s radar=%s" % [str(mutated_emcon), str(mutated_radar)])
	var pre_channels: Array = sv.sensor_service._last_channels.duplicate(true) \
		if sv.sensor_service._last_channels is Array else []
	_ok(pre_channels.size() > 0,
		"fixture produces non-empty sensor channels", "n=" + str(pre_channels.size()))
	# 规范化后的完整 channel 内容（排序 + 去掉时间相关噪声字段），用于往返比较。
	var pre_channel_canon: Array = _canonical_channels(pre_channels)
	_info("A0-T3 SENSOR fixture: mutated emcon=%s radar=%s channels=%d" % [
		str(mutated_emcon), str(mutated_radar), pre_channels.size()])
	var save_text2: String = sv.save_state()
	_ok(save_text2.length() > 500, "fixture save_state non-empty",
		"len=%d" % save_text2.length())
	var save1: Dictionary = JSON.parse_string(save_text2) \
		if JSON.parse_string(save_text2) is Dictionary else {}
	_info("A0-T3 SENSOR fixture: save_has_sensor_service=%s" % str(save1.has("sensor_service")))
	var s2 = GameSessionScript.new()
	var lr: Dictionary = s2.load_state(save_text2)
	_ok(bool(lr.get("ok", false)), "fixture load_state ok",
		"errors=" + str(lr.get("errors", [])))
	if not bool(lr.get("ok", false)):
		_info("A0-T3 BASELINE: fixture load_state failed → roundtrip checks cannot proceed")
		_finish()
		return
	_ok(s2.physics_world_service != null, "loaded session has PhysicsWorld")
	var phys_bad: Array = []
	if s2.physics_world_service != null:
		for eid in _truth.keys():
			var st2: Dictionary = s2.physics_state(eid)
			var pre: Dictionary = pre_phys[eid]
			var r2: Array = st2.get("r", []) if st2.get("r") is Array else []
			var v2: Array = st2.get("v", []) if st2.get("v") is Array else []
			var r0: Array = pre["r"]
			var v0: Array = pre["v"]
			if r0.size() >= 3 and r2.size() >= 3:
				for i in range(3):
					if absf(float(r2[i]) - float(r0[i])) > NUM_TOL:
						phys_bad.append({"entity": eid, "axis": "r%d" % i,
							"actual": float(r2[i]), "expected": float(r0[i])})
			if v0.size() >= 3 and v2.size() >= 3:
				for i in range(3):
					if absf(float(v2[i]) - float(v0[i])) > NUM_TOL:
						phys_bad.append({"entity": eid, "axis": "v%d" % i,
							"actual": float(v2[i]), "expected": float(v0[i])})
	_ok(phys_bad.is_empty(), "physics r/v roundtrip within 1e-9",
		"violations=" + str(phys_bad.slice(0, 8)))
	var world_bad: Array = []
	for eid in _truth.keys():
		var we2: Dictionary = s2.world.entity(eid)
		var pre2: Dictionary = pre_world[eid]
		var p2: Array = we2.get("pos_km", []) if we2.get("pos_km") is Array else []
		var p0: Array = pre2["pos_km"]
		if p0.size() >= 3 and p2.size() >= 3:
			for i in range(3):
				if absf(float(p2[i]) - float(p0[i])) > NUM_TOL:
					world_bad.append({"entity": eid, "axis": "pos%d" % i,
						"actual": float(p2[i]), "expected": float(p0[i])})
	_ok(world_bad.is_empty(), "world pos roundtrip within 1e-9",
		"violations=" + str(world_bad.slice(0, 8)))

	_step("4. track roundtrip")
	var tracks2: Array = s2.track_table.vm().get("tracks", []) \
		if s2.track_table.vm().get("tracks") is Array else []
	_eq(tracks2.size(), pre_tracks.size(), "track count preserved")
	var track_bad: Array = []
	for i in range(mini(pre_tracks.size(), tracks2.size())):
		var a: Dictionary = pre_tracks[i]
		var b: Dictionary = tracks2[i]
		if String(a.get("track_id", "")) != String(b.get("track_id", "")):
			track_bad.append({"index": i, "reason": "track_id mismatch",
				"before": String(a.get("track_id", "")), "after": String(b.get("track_id", ""))})
			continue
		var ra := float(a.get("range_km", -1.0))
		var rb := float(b.get("range_km", -1.0))
		if absf(ra - rb) > NUM_TOL:
			track_bad.append({"track": String(a.get("track_id", "")),
				"field": "range_km", "before": ra, "after": rb})
		_eq(String(a.get("identity", "")), String(b.get("identity", "")),
			"track identity preserved: " + String(a.get("track_id", "")))
	_ok(track_bad.is_empty(), "track numeric roundtrip within 1e-9",
		"violations=" + str(track_bad))

	_step("5. JSON numeric contract + restored runtime types (A-00 协调后口径)")
	# 协调后契约（A-00 断言映射表）：
	#   * **原始 JSON 数字**：不依赖 JSON Variant 类型（JSON 数字解析为 float 属正常），
	#     只校验数值语义 —— 有限、整数值、落在安全整数范围 0..2^53-1、事件 seq ≥1、
	#     且严格递增。负数/分数/越界/重复/逆序都算违例。
	#   * **恢复后的运行时值**：必须是 GDScript int（这才是类型漂移的真实判据）。
	const SAFE_INT_MAX := 9007199254740991.0  # 2^53-1
	var json_num_bad: Array = []
	var json_seq_values: Array = []
	if save1.has("bus") and save1.get("bus") is Dictionary:
		var busd: Dictionary = save1.get("bus")
		var evs: Array = busd.get("events", []) if busd.get("events") is Array else []
		for i in range(evs.size()):
			var ev: Dictionary = evs[i]
			if not ev.has("seq"):
				continue
			var raw_reason := _json_int_violation(ev.get("seq"), 1.0, SAFE_INT_MAX)
			if raw_reason != "":
				json_num_bad.append({"where": "save.bus.events[%d].seq" % i,
					"value": str(ev.get("seq")), "reason": raw_reason})
			else:
				json_seq_values.append(float(ev.get("seq")))
		if busd.has("seq"):
			var br := _json_int_violation(busd.get("seq"), 0.0, SAFE_INT_MAX)
			if br != "":
				json_num_bad.append({"where": "save.bus.seq",
					"value": str(busd.get("seq")), "reason": br})
	# 严格递增（按存档中的事件顺序）
	var order_bad: Array = []
	for i in range(1, json_seq_values.size()):
		if float(json_seq_values[i]) <= float(json_seq_values[i - 1]):
			order_bad.append({"index": i, "prev": json_seq_values[i - 1],
				"current": json_seq_values[i], "reason": "seq not strictly increasing"})
	_ok(json_num_bad.is_empty(),
		"raw JSON bus/event seq are finite integral values within 0..2^53-1 (value semantics, not Variant type)",
		"violations=" + str(json_num_bad.slice(0, 8)))
	_ok(order_bad.is_empty(), "raw JSON event seq strictly increasing",
		"violations=" + str(order_bad.slice(0, 8)))
	# 5b. 读档后 session 内部事件 seq 必须是真正的 GDScript int（类型漂移判据）
	var int_bad: Array = []
	var loaded_events: Array = s2.bus.events if s2.bus != null and s2.bus.events is Array else []
	for i in range(loaded_events.size()):
		var ev2: Dictionary = loaded_events[i]
		if ev2.has("seq"):
			var sv2 = ev2.get("seq")
			if not (sv2 is int):
				int_bad.append({"where": "loaded.bus.events[%d].seq" % i,
					"value": str(sv2), "type": type_string(typeof(sv2))})
	_ok(int_bad.is_empty(), "restored runtime event seq is a real GDScript int (no type drift)",
		"violations=" + str(int_bad.slice(0, 8)))
	# 5c. 负例：非法 seq 形态必须被同一判据拒绝
	var seq_neg: Array = []
	for bad in [{-1.0: "negative"}, {0.0: "zero"}, {1.5: "fractional"},
			{1.0e16: "out-of-range"}]:
		for val in bad.keys():
			var reason := _json_int_violation(val, 1.0, SAFE_INT_MAX)
			if reason == "":
				seq_neg.append({"value": val, "expected_reason": bad[val]})
	# 1.0 合法（≥1）—— 用它证明判据不是「一律拒绝」
	if _json_int_violation(1.0, 1.0, SAFE_INT_MAX) != "":
		seq_neg.append({"value": 1.0, "reason": "legal value wrongly rejected"})
	_ok(seq_neg.is_empty(), "NEGATIVE: illegal seq shapes are rejected by the numeric contract",
		"violations=" + str(seq_neg))
	# 5d. identification 数值字段类型（A0 C4 已定位 max_requests_per_tick 4→4.0）
	var ident_type_bad: Array = []
	if s2.identification_service != null and s2.identification_service.config is Dictionary:
		var icfg: Dictionary = s2.identification_service.config
		var auto: Dictionary = icfg.get("auto", {}) if icfg.get("auto") is Dictionary else {}
		if auto.has("max_requests_per_tick"):
			var mv = auto.get("max_requests_per_tick")
			if not (mv is int):
				ident_type_bad.append({"field": "identification.auto.max_requests_per_tick",
					"value": str(mv), "type": type_string(typeof(mv))})
	_ok(ident_type_bad.is_empty(), "identification integer config stays int",
		"violations=" + str(ident_type_bad))

	_step("6. SensorService runtime state persistence (EMCON / radar / channels)")
	_ok(save1.has("sensor_service"),
		"save payload contains sensor_service runtime snapshot")
	var sensor_bad: Array = []
	if s2.sensor_service == null:
		sensor_bad.append({"reason": "loaded session has no sensor_service"})
	else:
		if bool(s2.sensor_service.radar_enabled) != mutated_radar:
			sensor_bad.append({"field": "radar_enabled",
				"actual": bool(s2.sensor_service.radar_enabled), "expected": mutated_radar})
		if bool(s2.sensor_service.emcon) != mutated_emcon:
			sensor_bad.append({"field": "emcon",
				"actual": bool(s2.sensor_service.emcon), "expected": mutated_emcon})
		var ch2: Array = s2.sensor_service._last_channels.duplicate(true) \
			if s2.sensor_service._last_channels is Array else []
		# A0-T3 审查修正（P2）：比较**规范化后的完整 channel 内容**（不只数量）。
		var post_channel_canon: Array = _canonical_channels(ch2)
		if ch2.size() != pre_channels.size():
			sensor_bad.append({"field": "channels_count",
				"actual": ch2.size(), "expected": pre_channels.size()})
		var ch_diff: Array = _canonical_diff(pre_channel_canon, post_channel_canon,
			"channels")
		if not ch_diff.is_empty():
			sensor_bad.append({"field": "channels_content",
				"diff_count": ch_diff.size(), "sample": ch_diff.slice(0, 6)})
	_ok(sensor_bad.is_empty(), "SensorService runtime state persists across save/load (EMCON + radar + full channel content)",
		"violations=" + str(sensor_bad))
	_info("A0-T3 BASELINE: saved emcon=%s radar=%s; loaded emcon=%s radar=%s; save_has_sensor=%s" % [
		str(mutated_emcon), str(mutated_radar),
		str(s2.sensor_service.emcon if s2.sensor_service != null else "n/a"),
		str(s2.sensor_service.radar_enabled if s2.sensor_service != null else "n/a"),
		str(save1.has("sensor_service"))])

	_step("7. save → load → save canonical equality")
	var save2: String = s2.save_state()
	var canon_bad: Array = _canonical_diff(save1, JSON.parse_string(save2) \
		if JSON.parse_string(save2) is Dictionary else {})
	_ok(canon_bad.is_empty(), "save→load→save canonical equality",
		"diff_count=%d sample=%s" % [canon_bad.size(), str(canon_bad.slice(0, 10))])

	_step("8. 1000-tick save performance (INFO evidence)")
	var perf = GameSessionScript.new()
	_ok(bool(perf.ready), "perf session ready", str(perf.errors))
	var t0 := Time.get_ticks_msec()
	for i in range(PERF_TICKS):
		perf.tick(1.0)
	var tick_ms := Time.get_ticks_msec() - t0
	var ts0 := Time.get_ticks_msec()
	var perf_save: String = perf.save_state()
	var save_ms := Time.get_ticks_msec() - ts0
	var tl0 := Time.get_ticks_msec()
	var perf2 = GameSessionScript.new()
	var perf_lr: Dictionary = perf2.load_state(perf_save)
	var load_ms := Time.get_ticks_msec() - tl0
	_info("A0-T3 PERF: %d ticks=%dms save=%dms (%d bytes) load=%dms ok=%s" % [
		PERF_TICKS, tick_ms, save_ms, perf_save.length(), load_ms,
		str(perf_lr.get("ok", false))])
	_ok(perf_save.length() > 0, "1000-tick save non-empty", "len=%d" % perf_save.length())
	_ok(load_ms >= 0, "1000-tick load completed", "ms=%d" % load_ms)
	_info("A0-T3 PERF NOTE: 存档体积与读档时间随 tick 线性增长（A0 C4 已记录），本探针只记录实测值")

	_step("9. A0-T3 baseline evidence summary (expected Phase A failures)")
	_info("A0-T3 BASELINE: physics_violations=%d world_violations=%d track_violations=%d" % [
		phys_bad.size(), world_bad.size(), track_bad.size()])
	_info("A0-T3 BASELINE: int_drift=%d ident_type_drift=%d sensor_persist_violations=%d canonical_diff=%d" % [
		int_bad.size(), ident_type_bad.size(), sensor_bad.size(), canon_bad.size()])

	_finish()


# ── helpers ─────────────────────────────────────────────────────

## A-00 协调后契约：校验一个「原始 JSON 数字」是否满足整数语义（不依赖 Variant 类型）。
## 返回 "" = 合法；否则返回拒绝原因。规则：有限、整数值、min_v..max_v 范围。
func _json_int_violation(value, min_v: float, max_v: float) -> String:
	if value == null:
		return "missing"
	var f := 0.0
	if value is int:
		f = float(value)
	elif value is float:
		f = float(value)
	elif value is String:
		var s := String(value).strip_edges()
		if not s.is_valid_float():
			return "not a number (%s)" % s
		f = float(s)
	else:
		return "not a number (type %s)" % type_string(typeof(value))
	if is_nan(f) or is_inf(f):
		return "not finite"
	if absf(f - roundf(f)) > 0.0:
		return "not an integer value"
	if f < min_v:
		return "below minimum %s" % str(min_v)
	if f > max_v:
		return "above safe integer maximum %s" % str(max_v)
	return ""


## A0-T3 审查修正（P2）：把 sensor channels 规范化为可比较的稳定结构。
## 保留全部**语义字段**（channel 类型、目标、状态、可见性、分类、几何、设备参数等），
## 只去掉「随时间推进必然变化」的字段（history 时间序列、计数/速率/年龄等），
## 并按 (channel, target_id, mount_id) 排序，使比较与顺序无关。
const CHANNEL_VOLATILE_FIELDS := ["history", "age_s", "state_since_t", "status_since_t",
	"update_rate_hz", "update_count", "hits", "misses", "consecutive_hits",
	"lost_lock_count", "samples", "stare_s", "stare_progress", "progress",
	"predicted_next_t", "lost_at", "locked_t", "quality", "fire_control", "next_t"]

func _canonical_channels(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var norm: Dictionary = {}
		for k in row.keys():
			var key := String(k)
			if key in CHANNEL_VOLATILE_FIELDS:
				continue
			norm[key] = JSON.parse_string(JSON.stringify(row[k])) \
				if (row[k] is Dictionary or row[k] is Array) else row[k]
		norm["_channel_key"] = "%s|%s|%s" % [
			String(row.get("channel", "")), String(row.get("target_id", "")),
			String(row.get("mount_id", ""))]
		out.append(norm)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("_channel_key", "")) < String(b.get("_channel_key", "")))
	return out


## 规范化对比两份存档 JSON（忽略 run 相关噪声字段），返回差异列表。
func _canonical_diff(a, b, path := "") -> Array:
	var out: Array = []
	if a is Dictionary and b is Dictionary:
		var keys_a: Array = (a as Dictionary).keys()
		keys_a.sort()
		var keys_b: Array = (b as Dictionary).keys()
		keys_b.sort()
		for k in keys_a:
			var key := String(k)
			if not (b as Dictionary).has(k):
				out.append({"path": path + "/" + key, "reason": "missing in after"})
				continue
			out.append_array(_canonical_diff((a as Dictionary)[k], (b as Dictionary)[k],
				path + "/" + key))
		for k2 in keys_b:
			if not (a as Dictionary).has(k2):
				out.append({"path": path + "/" + String(k2), "reason": "extra in after"})
		return out
	if a is Array and b is Array:
		var aa: Array = a
		var bb: Array = b
		if aa.size() != bb.size():
			out.append({"path": path, "reason": "array size %d != %d" % [aa.size(), bb.size()]})
		for i in range(mini(aa.size(), bb.size())):
			out.append_array(_canonical_diff(aa[i], bb[i], path + "[%d]" % i))
		return out
	if typeof(a) != typeof(b):
		out.append({"path": path, "reason": "type %s != %s" % [
			type_string(typeof(a)), type_string(typeof(b))],
			"before": str(a), "after": str(b)})
		return out
	if a is float and b is float:
		if absf(float(a) - float(b)) > NUM_TOL:
			out.append({"path": path, "reason": "float diff", "before": float(a),
				"after": float(b)})
		return out
	if str(a) != str(b):
		out.append({"path": path, "reason": "value diff", "before": str(a), "after": str(b)})
	return out


## 往返测试用 fixture：同一 scenario 实体 + 必需服务，但不含 comms 种子路由。
func _roundtrip_seed() -> Dictionary:
	var sc := _read_json(TARGET_SCENARIO)
	return {
		"entities": (sc.get("entities", []) as Array).duplicate(true),
		"own_entity": String(sc.get("own_entity", "apsis")),
		"physics_world": true,
		"seed_frame": String(sc.get("frame", "bary_rot")),
		"frame_origin": "bary_rot",
		"track_table": true,
		"sensor_service": {"observer": {"id": "apsis", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "harmattan", "pos_km": [322139.0, 0.0, 0.0], "rcs_m2": 1100.0}],
			"options": {"radar_enabled": true, "emcon": false}},
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
	print("[A0-T3] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}
