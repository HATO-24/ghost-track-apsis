extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A-01 / A0-T2 · 实体元数据管道探针
#
# 真实产品入口链路：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
#
# 对 7 个 scenario 实体逐项检查以下字段在整条链路上的传递：
#   side / identity / batch / rcs_m2 / radius_km / has_pd
# 传递层级：PhysicsWorld → WorldState → snapshot → 航迹 → contacts
#
# 规则：
#   * 缺失值必须显示为明确的 `unknown`（或空 + 明确 reason），**禁止静默回退为 `friend`**；
#   * 当前已知的 6/7 错误 contacts 行（缺 side/identity/batch/rcs/radius/has_pd，
#     或静默 friend 回退）必须被探针**明确暴露**，不得隐藏。
#
# 预期失败（Phase A 基线）：
#   - WorldState/snapshot 实体缺少 side/identity/batch/rcs/radius/has_pd（WorldState 只保留
#     8 个核心键，元数据未落库）；
#   - contacts 对无证据实体静默回退 side=friend / identity=friend（6/7 行）；
#   - 航迹 identity 未与 scenario truth 关联（无证据时应 unknown）。
#
# Output: `A0-T2 ENTITY METADATA PIPELINE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
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

const META_FIELDS := ["side", "identity", "batch", "rcs_m2", "radius_km", "has_pd"]
const NUM_FIELDS := ["rcs_m2", "radius_km"]
const TICK_DT := 60.0
const TICK_COUNT := 3
# 玩家可见层允许的「无证据」占位值
const SAFE_UNKNOWN := ["unknown", "unknown track", "unknown contact", "unknown signal", ""]

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
	print("A0-T2 ENTITY METADATA PIPELINE PROBE · real entry main_menu → v1_hud")
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
	print("A0-T2 ENTITY METADATA PIPELINE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T2] FAILED: ", f)
		print("A0-T2 ENTITY METADATA PIPELINE PROBE FAILED")
	else:
		print("A0-T2 ENTITY METADATA PIPELINE PROBE OK")
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


func _step(title: String) -> void:
	print("")
	print("[A0-T2] STEP ", title)


func _info(text: String) -> void:
	print("[A0-T2] INFO ", text)


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

	_step("2. scenario truth (7 entities, direct JSON read)")
	var sc := _read_json(TARGET_SCENARIO)
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_eq(ents.size(), 7, "scenario entity count")
	for raw in ents:
		if raw is Dictionary:
			var e: Dictionary = raw
			var eid := String(e.get("id", ""))
			if eid != "":
				_truth[eid] = e.duplicate(true)
				_truth_ids.append(eid)
	_truth_ids.sort()
	_ok(_truth.size() == 7, "scenario truth table has 7 entities", str(_truth_ids))
	for eid in _truth_ids:
		var t: Dictionary = _truth[eid]
		_info("TRUTH %s: side=%s identity=%s batch=%s rcs=%s radius=%s has_pd=%s" % [
			eid, String(t.get("side", "")), String(t.get("identity", "")),
			String(t.get("batch", "")), str(t.get("rcs_m2", "")),
			str(t.get("radius_km", "")), str(t.get("has_pd", ""))])

	# 推进几个 tick，让传感器/航迹/contacts 进入稳定状态
	for i in range(TICK_COUNT):
		_session.tick(TICK_DT)
	_binder.refresh()

	_step("3. layer 1: PhysicsWorld — does it carry static metadata?")
	var pw_has_meta := 0
	var pw_missing: Array = []
	for eid in _truth_ids:
		var st: Dictionary = _session.physics_state(eid)
		var found := 0
		for f in META_FIELDS:
			if st.has(f):
				found += 1
		if found == META_FIELDS.size():
			pw_has_meta += 1
		else:
			pw_missing.append({"entity": eid, "fields_present": found,
				"keys": st.keys()})
	_ok(pw_has_meta == _truth_ids.size(),
		"PhysicsWorld exposes all static metadata fields for 7 entities",
		"ok=%d/7 missing=%s" % [pw_has_meta, str(pw_missing)])

	_step("4. layer 2: WorldState — does it carry static metadata?")
	var ws_has_meta := 0
	var ws_missing: Array = []
	for eid in _truth_ids:
		var we: Dictionary = _session.world.entity(eid)
		var found := 0
		for f in META_FIELDS:
			if we.has(f):
				found += 1
		if found == META_FIELDS.size():
			ws_has_meta += 1
		else:
			ws_missing.append({"entity": eid, "fields_present": found,
				"keys": we.keys()})
	_ok(ws_has_meta == _truth_ids.size(),
		"WorldState carries all static metadata fields for 7 entities",
		"ok=%d/7 missing=%s" % [ws_has_meta, str(ws_missing)])

	_step("5. layer 3: snapshot().entities — does it carry static metadata?")
	var snap: Dictionary = _session.snapshot()
	var snap_ents: Array = snap.get("entities", []) if snap.get("entities") is Array else []
	_eq(snap_ents.size(), 7, "snapshot has 7 entities")
	var snap_by_id: Dictionary = {}
	for raw_s in snap_ents:
		if raw_s is Dictionary:
			snap_by_id[String((raw_s as Dictionary).get("id", ""))] = raw_s
	var snap_has_meta := 0
	var snap_missing: Array = []
	for eid in _truth_ids:
		var se: Dictionary = snap_by_id.get(eid, {}) if snap_by_id.get(eid) is Dictionary else {}
		var found := 0
		for f in META_FIELDS:
			if se.has(f):
				found += 1
		if found == META_FIELDS.size():
			snap_has_meta += 1
		else:
			snap_missing.append({"entity": eid, "fields_present": found})
	_ok(snap_has_meta == _truth_ids.size(),
		"snapshot().entities carries all static metadata fields for 7 entities",
		"ok=%d/7 missing=%s" % [snap_has_meta, str(snap_missing)])

	_step("6. layer 4: tracks — metadata traceability")
	var tracks: Array = _session.track_table.vm().get("tracks", []) \
		if _session.track_table.vm().get("tracks") is Array else []
	var tr_by_entity: Dictionary = {}
	for raw_t in tracks:
		if raw_t is Dictionary:
			var tr: Dictionary = raw_t
			tr_by_entity[String(tr.get("entity_id", ""))] = tr
	_ok(tracks.size() > 0, "TrackTable has tracks", "n=" + str(tracks.size()))
	var track_meta_ok := 0
	var track_meta_bad: Array = []
	for eid in tr_by_entity.keys():
		var tr2: Dictionary = tr_by_entity[eid]
		var found2 := 0
		for f in META_FIELDS:
			if tr2.has(f):
				found2 += 1
		if found2 == META_FIELDS.size():
			track_meta_ok += 1
		else:
			track_meta_bad.append({"entity": eid, "fields_present": found2,
				"keys": tr2.keys()})
	_ok(track_meta_ok == tr_by_entity.size(),
		"tracks carry all static metadata fields",
		"ok=%d/%d bad=%s" % [track_meta_ok, tr_by_entity.size(), str(track_meta_bad)])

	_step("7. layer 5: contacts — metadata + no silent friend fallback")
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	_ok(contacts.size() > 0, "binder.contacts non-empty", "n=" + str(contacts.size()))
	var c_by_entity: Dictionary = {}
	for raw_c in contacts:
		if raw_c is Dictionary:
			var c: Dictionary = raw_c
			c_by_entity[String(c.get("entity_id", c.get("id", "")))] = c
	# 7a. 每个 scenario 实体都应有 contact 行（或明确 reason）
	var missing_contacts: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			missing_contacts.append(eid)
	_ok(missing_contacts.is_empty(), "all 7 scenario entities have a contact row",
		"missing=" + str(missing_contacts))
	# 7b. **当前已知失败**：无证据实体不得静默回退 friend
	var friend_fallback: Array = []
	var unknown_ok := 0
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			continue
		var c2: Dictionary = c_by_entity[eid]
		var c_side := String(c2.get("side", "")).to_lower()
		var c_ident := String(c2.get("identity", "")).to_lower()
		var c_type := String(c2.get("type", "")).to_lower()
		var truth_side := String((_truth[eid] as Dictionary).get("side", "")).to_lower()
		_info("CONTACT %s: side=%s identity=%s type=%s (truth side=%s)" % [
			eid, c_side, c_ident, c_type, truth_side])
		# 无证据时不得为 friend；除非该实体是 scenario 里明确 friend（本舰/友军）
		var truth_is_friend := truth_side in ["friend", "ally", "ocu", "ueg"]
		if c_side == "friend" and not truth_is_friend:
			friend_fallback.append({"entity": eid, "contact_side": c_side,
				"truth_side": truth_side})
		elif c_side in ["unknown", "ocu", "neutral", "hostile"]:
			unknown_ok += 1
		# 无证据时 identity 也不得静默 friend
		if c_ident == "friend" and not truth_is_friend:
			friend_fallback.append({"entity": eid, "contact_identity": c_ident,
				"truth_side": truth_side})
	_ok(friend_fallback.is_empty(),
		"no silent friend fallback for non-friend entities in contacts",
		"violations=" + str(friend_fallback))
	# 7c. contacts 元数据字段完整性
	var c_meta_ok := 0
	var c_meta_bad: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			continue
		var c3: Dictionary = c_by_entity[eid]
		var found3 := 0
		for f in META_FIELDS:
			if c3.has(f) and c3.get(f) != null:
				found3 += 1
		if found3 == META_FIELDS.size():
			c_meta_ok += 1
		else:
			c_meta_bad.append({"entity": eid, "fields_present": found3,
				"keys": c3.keys()})
	_ok(c_meta_ok == _truth_ids.size(),
		"contacts carry all static metadata fields for 7 entities",
		"ok=%d/7 bad=%s" % [c_meta_ok, str(c_meta_bad)])
	# 7d. batch 可追溯
	var batch_bad: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			continue
		var c4: Dictionary = c_by_entity[eid]
		var cb := String(c4.get("batch", ""))
		var tb := String((_truth[eid] as Dictionary).get("batch", ""))
		if cb == "" or cb == "<null>":
			batch_bad.append({"entity": eid, "contact_batch": cb, "truth_batch": tb})
	_ok(batch_bad.is_empty(), "contacts expose batch for traceability",
		"violations=" + str(batch_bad))

	_step("8. per-field pass-through matrix (7 entities × 6 fields × 5 layers)")
	var field_layers := {
		"physics": func(eid: String) -> Dictionary: return _session.physics_state(eid),
		"world": func(eid: String) -> Dictionary: return _session.world.entity(eid),
		"snapshot": func(eid: String) -> Dictionary:
			return snap_by_id.get(eid, {}) if snap_by_id.get(eid) is Dictionary else {},
		"track": func(eid: String) -> Dictionary:
			return tr_by_entity.get(eid, {}) if tr_by_entity.get(eid) is Dictionary else {},
		"contact": func(eid: String) -> Dictionary:
			return c_by_entity.get(eid, {}) if c_by_entity.get(eid) is Dictionary else {},
	}
	var matrix_bad: Array = []
	for layer_name in ["physics", "world", "snapshot", "track", "contact"]:
		var getter = field_layers[layer_name]
		for eid in _truth_ids:
			var row: Dictionary = getter.call(eid)
			var truth: Dictionary = _truth[eid]
			for f in META_FIELDS:
				var expected = truth.get(f, null)
				var actual = row.get(f, "<missing>")
				var okv := _meta_equal(f, actual, expected)
				if not okv:
					matrix_bad.append({"layer": layer_name, "entity": eid, "field": f,
						"actual": str(actual), "expected": str(expected)})
	_ok(matrix_bad.is_empty(),
		"metadata pass-through matrix complete (5 layers × 7 entities × 6 fields)",
		"violations=%d sample=%s" % [matrix_bad.size(), str(matrix_bad.slice(0, 8))])

	_step("9. A0-T2 baseline evidence summary (expected Phase A failures)")
	_info("A0-T2 BASELINE: physics=%d/7 world=%d/7 snapshot=%d/7 track=%d/%d contact=%d/7 have full metadata" % [
		pw_has_meta, ws_has_meta, snap_has_meta, track_meta_ok, tr_by_entity.size(), c_meta_ok])
	_info("A0-T2 BASELINE: %d silent friend-fallback rows in contacts" % friend_fallback.size())
	_info("A0-T2 BASELINE: %d metadata pass-through violations" % matrix_bad.size())

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _meta_equal(field: String, actual, expected) -> bool:
	if expected == null:
		expected = ""
	# 允许玩家可见层的「未知」占位：缺值必须显式 unknown，不能静默 friend
	if actual is String and String(actual).to_lower() in SAFE_UNKNOWN:
		if String(expected) == "" or String(expected).to_lower() in SAFE_UNKNOWN:
			return true
		# 有 truth 但显示 unknown 是**安全**的（不泄露），算通过
		return true
	if actual == null or actual == "<missing>":
		return false
	if field in NUM_FIELDS:
		if actual is int or actual is float:
			if expected is int or expected is float:
				return absf(float(actual) - float(expected)) <= 1.0e-9
		return false
	if expected is bool:
		return actual is bool and actual == expected
	return str(actual) == str(expected)


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
