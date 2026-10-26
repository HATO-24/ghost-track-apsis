extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A-01 / A0-T1 · 航迹 vs 物理真值权威探针
#
# 真实产品入口链路：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
# 不使用手工拼装的服务替代。
#
# 检查项：
#   1) 真实入口 + physics/track/sensor 组件就绪；
#   2) **同一 tick**：航迹距离 vs PhysicsWorld 真值距离，误差 ≤ 0.5 km；
#   3) 时间戳误差 ≤ 1e-6 s（track_table.t == physics.t == session t，观测 t 同刻）；
#   4) 身份/威胁 vs scenario truth（**当前已知失败**：观测/证据未建立 truth identity）；
#   5) 来源/batch 可追溯性（track.sources 非空、batch/entity_id 可回溯）；
#   6) TrackTable 单写者（current_writer 唯一且与 session 记录一致）；
#   7) 帧与单位信息（bary_rot / km / km/s）来自 physics 权威。
#
# 预期失败（Phase A 基线，**不得隐藏**）：
#   - 航迹距离来自静态传感器配置几何（20 km / 10 km），与物理真值（420.2 / 90.0 km）不符；
#   - track identity/threat 未与 scenario truth 对齐；
#   - contacts/snapshot 缺少 side/identity/batch/rcs/radius/has_pd 传递。
#
# Output: `A0-T1 TRACK TRUTH AUTHORITY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"

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
const RANGE_TOL_KM := 0.5
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
	print("A0-T1 TRACK TRUTH AUTHORITY PROBE · real entry main_menu → v1_hud")
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
	print("A0-T1 TRACK TRUTH AUTHORITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T1] FAILED: ", f)
		print("A0-T1 TRACK TRUTH AUTHORITY PROBE FAILED")
	else:
		print("A0-T1 TRACK TRUTH AUTHORITY PROBE OK")
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
		"actual=%.9f expected=%.9f tol=" % [actual, expected] + str(tol))


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
	_ok(_session.physics_world_service != null, "PhysicsWorld enabled")
	_ok(_session.track_table != null, "TrackTable enabled")
	_ok(_session.sensor_service != null, "SensorService enabled")
	if _session.physics_world_service == null or _session.track_table == null \
			or _session.sensor_service == null:
		_finish()
		return

	_step("2. scenario truth table (read directly from scenario JSON)")
	var sc := _read_json(TARGET_SCENARIO)
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_eq(ents.size(), 7, "scenario entity count")
	for raw in ents:
		if raw is Dictionary:
			_truth[String((raw as Dictionary).get("id", ""))] = (raw as Dictionary).duplicate(true)
	_ok(_truth.size() == 7, "scenario truth table has 7 entities", str(_truth.keys()))

	_step("3. same tick: track range vs PhysicsWorld truth range (tol ≤ %.1f km)" % RANGE_TOL_KM)
	# 推进到稳定状态（多次 tick，确保观测/航迹已生成）
	for i in range(TICK_COUNT):
		var tk: Dictionary = _session.tick(TICK_DT)
		_ok(bool(tk.get("ok", false)), "tick %d ok" % (i + 1),
			"reason=" + String(tk.get("reason", "")))
	# 同一 tick 的物理时间与航迹时间
	var now := float(_session.now_s())
	var phys_t := float(_session.physics_world_service.t)
	var track_t := float(_session.track_table.t)
	_near(track_t, now, TIME_TOL_S, "track_table.t == session now_s (same tick)")
	_near(phys_t, now, TIME_TOL_S, "physics.t == session now_s (same tick)")
	_near(track_t, phys_t, TIME_TOL_S, "track_table.t == physics.t (same tick)")
	# 观测时间同刻：只校验**最新一次 tick** 产生的观测（历史观测属于早期时刻，正常）
	var obs_rows: Array = _session.sensor_service.observations
	_ok(obs_rows.size() > 0, "sensor produced observations", "n=" + str(obs_rows.size()))
	var newest_obs_t := -1.0
	for raw_o in obs_rows:
		if raw_o is Dictionary:
			newest_obs_t = maxf(newest_obs_t, float((raw_o as Dictionary).get("t", -1.0)))
	var obs_time_bad: Array = []
	var newest_checked := 0
	for raw_o2 in obs_rows:
		if not (raw_o2 is Dictionary):
			continue
		var ot := float((raw_o2 as Dictionary).get("t", -1.0))
		if absf(ot - newest_obs_t) > TIME_TOL_S:
			continue
		newest_checked += 1
		# 最新批次观测 t 必须等于当前 tick 的 physics t（同刻）
		if absf(ot - phys_t) > TIME_TOL_S:
			obs_time_bad.append({"obs_t": ot, "physics_t": phys_t})
	_ok(newest_checked > 0, "latest observation batch present", "n=%d" % newest_checked)
	_ok(obs_time_bad.is_empty(),
		"latest observation batch t == physics t (same tick, tol 1e-6 s)",
		"violations=" + str(obs_time_bad))
	# 航迹距离 vs 物理真值距离
	var tracks: Array = _session.track_table.vm().get("tracks", []) \
		if _session.track_table.vm().get("tracks") is Array else []
	_ok(tracks.size() > 0, "TrackTable has fused tracks", "n=" + str(tracks.size()))
	var compared := 0
	var range_bad: Array = []
	var range_rows: Array = []
	for raw_tr in tracks:
		if not (raw_tr is Dictionary):
			continue
		var tr: Dictionary = raw_tr
		var eid := String(tr.get("entity_id", ""))
		if eid == "" or not _truth.has(eid):
			continue
		var tr_range := float(tr.get("range_km", -1.0))
		var truth_range := _physics_range(eid)
		if truth_range < 0.0:
			continue
		compared += 1
		var delta := absf(tr_range - truth_range)
		range_rows.append({"entity": eid, "track_range_km": tr_range,
			"physics_range_km": truth_range, "abs_error_km": delta})
		if delta > RANGE_TOL_KM:
			range_bad.append(range_rows[range_rows.size() - 1])
		_info("RANGE %s: track=%.6f physics=%.6f err=%.6f km" % [
			eid, tr_range, truth_range, delta])
	_ok(compared > 0, "at least one track compared against physics truth",
		"compared=%d" % compared)
	_ok(range_bad.is_empty(), "track range matches physics truth within %.1f km" % RANGE_TOL_KM,
		"violations=" + str(range_bad))

	_step("4. identity/threat/side vs evidence & scenario semantics")
	# A0-T1 审查修正（P2）：原实现只检查 identity，且仅在 sources 为空时校验 unknown；
	# 这里补齐 threat/side 的一致性检查：
	#   4a. identity 必须由证据派生（无身份证据时必须 unknown，不得凭空等于 truth）；
	#   4b. threat 必须与证据/身份一致（无授权证据时不得为 hostile，且不得脱离身份乱报）；
	#   4c. side（投影到 contacts 时）不得与 scenario side 语义矛盾；
	#   4d. scenario 语义一致性：truth=hostile 的实体不得在无授权证据下被标成 friend/neutral。
	const IDENTITY_SOURCES := ["iff", "transponder", "optical", "vis", "identification"]
	const VALID_THREATS := ["none", "unknown", "suspect", "hostile"]
	var ident_bad: Array = []
	var threat_bad: Array = []
	var side_bad: Array = []
	var checked_identity := 0
	var checked_threat := 0
	var checked_side := 0
	# contacts 投影层（用于 side 语义检查）
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	var contact_by_entity: Dictionary = {}
	for raw_c in contacts:
		if raw_c is Dictionary:
			var c: Dictionary = raw_c
			contact_by_entity[String(c.get("entity_id", c.get("id", "")))] = c
	for raw_tr2 in tracks:
		if not (raw_tr2 is Dictionary):
			continue
		var tr2: Dictionary = raw_tr2
		var eid2 := String(tr2.get("entity_id", ""))
		if eid2 == "" or not _truth.has(eid2):
			continue
		var truth2: Dictionary = _truth[eid2]
		var truth_identity := String(truth2.get("identity", "")).to_lower()
		var truth_side := String(truth2.get("side", "")).to_lower()
		var track_identity := String(tr2.get("identity", "")).to_lower()
		var track_threat := String(tr2.get("threat", "")).to_lower()
		var sources: Array = tr2.get("sources", []) if tr2.get("sources") is Array else []
		var has_identity_evidence := false
		for s in sources:
			var sl := String(s).to_lower()
			for known in IDENTITY_SOURCES:
				if sl == known or sl.begins_with(known + "."):
					has_identity_evidence = true
					break
		_info("IDENTITY %s: track=%s truth=%s sources=%s threat=%s" % [
			eid2, track_identity, truth_identity, str(sources), track_threat])
		# 4a. identity 证据派生
		checked_identity += 1
		if not has_identity_evidence and track_identity not in ["unknown", ""]:
			ident_bad.append({"entity": eid2, "track_identity": track_identity,
				"sources": sources, "reason": "identity not unknown without identity evidence"})
		if has_identity_evidence and track_identity == truth_identity and sources.is_empty():
			ident_bad.append({"entity": eid2, "reason": "identity equals truth with no evidence"})
		# 4b. threat 与证据/身份一致
		checked_threat += 1
		if not (track_threat in VALID_THREATS):
			threat_bad.append({"entity": eid2, "threat": track_threat,
				"reason": "threat not in " + str(VALID_THREATS)})
		elif track_threat == "hostile":
			# hostile 必须有显式授权证据（track_table 的 hostile_requires_authority 契约）。
			var authorized := false
			for s in sources:
				if String(s).to_lower() in ["manual", "player", "authority", "command"]:
					authorized = true
					break
			if not authorized:
				threat_bad.append({"entity": eid2, "threat": track_threat,
					"sources": sources,
					"reason": "threat=hostile without explicit authority evidence"})
		if track_identity == "unknown" and track_threat in ["suspect", "hostile"]:
			threat_bad.append({"entity": eid2, "track_identity": track_identity,
				"threat": track_threat,
				"reason": "threat escalates above identity evidence"})
		# 4c/4d. side 语义（contacts 投影层）与 scenario 一致性
		if contact_by_entity.has(eid2):
			var c2: Dictionary = contact_by_entity[eid2]
			var c_side := String(c2.get("side", "")).to_lower()
			var c_ident := String(c2.get("identity", "")).to_lower()
			checked_side += 1
			# truth 非 friend/ally 时，不得静默标成 friend（沿用 A0-T2 的静默兜底缺陷口径）
			var truth_is_friend := truth_side in ["friend", "ally", "ueg", "ocu"]
			if c_side == "friend" and not truth_is_friend:
				side_bad.append({"entity": eid2, "contact_side": c_side,
					"truth_side": truth_side, "reason": "silent friend fallback"})
			if c_ident == "friend" and not truth_is_friend:
				side_bad.append({"entity": eid2, "contact_identity": c_ident,
					"truth_side": truth_side, "reason": "silent friend identity fallback"})
			_info("SIDE %s: contact side=%s identity=%s (truth side=%s)" % [
				eid2, c_side, c_ident, truth_side])
	_ok(checked_identity > 0, "identity checks applied to >=1 track",
		"checked=%d" % checked_identity)
	_ok(ident_bad.is_empty(),
		"track identity is evidence-derived and not auto-copied from truth",
		"violations=" + str(ident_bad))
	_ok(checked_threat > 0, "threat checks applied to >=1 track",
		"checked=%d" % checked_threat)
	_ok(threat_bad.is_empty(),
		"track threat is consistent with evidence and identity (no unauthorized hostile)",
		"violations=" + str(threat_bad))
	_ok(checked_side > 0, "side checks applied to >=1 contact", "checked=%d" % checked_side)
	_ok(side_bad.is_empty(),
		"contact side/identity do not contradict scenario side semantics",
		"violations=" + str(side_bad))

	_step("5. provenance: track sources / batch / entity_id traceable")
	var prov_bad: Array = []
	for raw_tr3 in tracks:
		if not (raw_tr3 is Dictionary):
			continue
		var tr3: Dictionary = raw_tr3
		var eid3 := String(tr3.get("entity_id", ""))
		var sources3: Array = tr3.get("sources", []) if tr3.get("sources") is Array else []
		var batch3 := String(tr3.get("batch", ""))
		var tid3 := String(tr3.get("track_id", ""))
		if tid3 == "":
			prov_bad.append({"entity": eid3, "reason": "missing track_id"})
			continue
		if sources3.is_empty():
			prov_bad.append({"entity": eid3, "track": tid3, "reason": "missing sources"})
		if eid3 == "":
			prov_bad.append({"track": tid3, "reason": "missing entity_id"})
		_info("PROVENANCE track=%s entity=%s batch=%s sources=%s" % [
			tid3, eid3, batch3, str(sources3)])
	_ok(prov_bad.is_empty(), "all tracks have traceable provenance (sources/entity_id)",
		"violations=" + str(prov_bad))

	_step("6. TrackTable single writer")
	var tt_writer := String(_session.track_table.current_writer())
	_ok(tt_writer != "", "TrackTable has a claimed writer", "writer=" + tt_writer)
	# 第二次 claim 用不同 id 必须失败（单写者约束）
	var claim_other: Dictionary = _session.track_table.claim_writer("__a0_probe_other__")
	_eq(bool(claim_other.get("ok", true)), false,
		"TrackTable rejects a second writer claim")
	_eq(String(claim_other.get("reason", "")), "writer_conflict",
		"TrackTable writer conflict reason")
	_eq(String(_session.track_table.current_writer()), tt_writer,
		"TrackTable writer unchanged after rejected claim")

	_step("7. frame and units from physics authority")
	var frame := String(_session.physics_world_service.frame())
	_eq(frame, FRAME, "physics frame is bary_rot")
	var units: Dictionary = _session.physics_world_service.units()
	_eq(String(units.get("length", "")), "km", "physics length unit km")
	_eq(String(units.get("velocity", "")), "km/s", "physics velocity unit km/s")
	_eq(String(units.get("time", "")), "s", "physics time unit s")
	# 航迹 range 单位：km（与 physics 同量级，不是 m 或 AU）
	var sample_range := 0.0
	for raw_tr4 in tracks:
		if raw_tr4 is Dictionary and float((raw_tr4 as Dictionary).get("range_km", -1.0)) > 0.0:
			sample_range = float((raw_tr4 as Dictionary).get("range_km", -1.0))
			break
	_ok(sample_range > 0.0, "track range is positive km value",
		"sample=%.3f" % sample_range)

	_step("8. A0 baseline evidence summary (expected Phase A failures, not hidden)")
	# 汇总当前已知的权威链缺口，作为 Phase A 修复前基线证据（INFO，不影响 PASS/FAIL 计数）
	var static_gap := 0
	for raw_tr5 in tracks:
		if not (raw_tr5 is Dictionary):
			continue
		var eid5 := String((raw_tr5 as Dictionary).get("entity_id", ""))
		if eid5 == "" or not _truth.has(eid5):
			continue
		var trr := float((raw_tr5 as Dictionary).get("range_km", -1.0))
		var prr := _physics_range(eid5)
		if prr > 0.0 and absf(trr - prr) > RANGE_TOL_KM:
			static_gap += 1
	_info("A0-T1 BASELINE: %d/%d tracks have range != physics truth (>%.1f km)" % [
		static_gap, tracks.size(), RANGE_TOL_KM])
	_info("A0-T1 BASELINE: %d identity violations, %d provenance violations" % [
		ident_bad.size(), prov_bad.size()])

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


## 物理真值距离：observer（本舰）→ entity，bary_rot / km。
func _physics_range(eid: String) -> float:
	if _session == null or _session.physics_world_service == null:
		return -1.0
	var own := String(_session.combat_service.own_id) if _session.combat_service != null else ""
	if own == "":
		own = "apsis"
	var o: Dictionary = _session.physics_state(own)
	var t: Dictionary = _session.physics_state(eid)
	var orr: Array = o.get("r", []) if o.get("r") is Array else []
	var trr: Array = t.get("r", []) if t.get("r") is Array else []
	if orr.size() < 3 or trr.size() < 3:
		return -1.0
	var dx := float(trr[0]) - float(orr[0])
	var dy := float(trr[1]) - float(orr[1])
	var dz := float(trr[2]) - float(orr[2])
	return sqrt(dx * dx + dy * dy + dz * dz)
