extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A1.1 · Entity static metadata authority — cross-system regression probe
#
# Verifies (real orbital_sim entry path: main_menu → v1_hud → ShellBinder → GameSession):
#   1) scenario metadata is retrievable by entity id from the runtime authority:
#      side / identity / batch / ship_class / rcs_m2 / ir_signature / radius_km /
#      has_pd / facility_id / transponder_profile;
#   2) ballistics/PD state reads those values from the authority (no silent defaults);
#   3) contacts display never defaults missing info to "friend" — unknown stays unknown;
#   4) world-internal truth is NOT auto-copied into player tracks/display:
#      catalog truth side/identity must not appear in track/contact rows without evidence.
#
# Red-first evidence: on the pre-A1.1 implementation `session.entity_metadata()` does
# not exist and this probe prints the actual fallback/wrong values via `[A1] FAIL`.
#
# Output: `A1 ENTITY METADATA AUTHORITY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# No rendering, no writes outside res:// reads + process env restoration.
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

const META_FIELDS := ["side", "identity", "batch", "ship_class", "rcs_m2",
	"ir_signature", "radius_km", "has_pd", "facility_id", "transponder_profile"]
const NUM_FIELDS := ["rcs_m2", "ir_signature", "radius_km"]

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
	print("A1 ENTITY METADATA AUTHORITY PROBE · real entry main_menu → v1_hud → ShellBinder")
	print("Godot ", Engine.get_version_info().get("string", "?"), " · profile=", TARGET_PROFILE)
	print("════════════════════════════════════════════════════════════════")
	_setup_env()
	node_added.connect(_on_node_added)
	_watchdog()
	_run()


## Real-entry proof: the menu node is instantiated before auto-skip replaces it on the
## same frame, so record it via SceneTree.node_added instead of polling current_scene.
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
	print("[A1] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("A1 ENTITY METADATA AUTHORITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A1] FAILED: ", f)
		print("A1 ENTITY METADATA AUTHORITY PROBE FAILED")
	else:
		print("A1 ENTITY METADATA AUTHORITY PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A1] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A1] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(title: String) -> void:
	print("")
	print("[A1] STEP ", title)


func _info(text: String) -> void:
	print("[A1] INFO ", text)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# ── boot ─────────────────────────────────────────────────────────

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
	_ok(_binder != null and bool(_binder.get("ready")), "ShellBinder ready",
		"errors=" + str(_binder.get("errors")) if _binder != null else "binder=null")
	_ok(_session != null, "GameSession available")
	if _session == null:
		_finish()
		return

	_step("2. scenario truth table (read directly from scenario JSON)")
	var sc := _read_json(TARGET_SCENARIO)
	_ok(not sc.is_empty(), "scenario JSON readable", TARGET_SCENARIO)
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

	_step("3. entity metadata authority (catalog) by entity id")
	_ok(_session.has_method("entity_metadata"), "GameSession.entity_metadata(id) API exists")
	for eid in _truth_ids:
		var truth: Dictionary = _truth[eid]
		var meta: Dictionary = _get_metadata(eid)
		_ok(bool(meta.get("found", false)), "metadata found: " + eid,
			"meta_keys=" + str(meta.keys()))
		for field in META_FIELDS:
			_check_meta_field(eid, meta, field, truth.get(field))
	# unknown id must not invent metadata
	if _session.has_method("entity_metadata"):
		var unknown: Dictionary = _session.entity_metadata("__no_such_entity__")
		_ok(not bool(unknown.get("found", true)), "unknown id -> found=false",
			"meta=" + str(unknown))

	_step("4. ballistics / PD state reads authority (no silent defaults)")
	var states: Dictionary = {}
	if _session.has_method("_ballistics_states"):
		states = _session._ballistics_states()
	_ok(not states.is_empty(), "session._ballistics_states() non-empty", "n=" + str(states.size()))
	for eid in _truth_ids:
		var truth: Dictionary = _truth[eid]
		var st: Dictionary = states.get(eid, {}) if states.get(eid) is Dictionary else {}
		_ok(not st.is_empty(), "ballistics state exists: " + eid)
		if st.is_empty():
			continue
		_check_state_field(eid, st, "side", truth.get("side"))
		_check_state_field(eid, st, "has_pd", truth.get("has_pd"))
		_check_state_field(eid, st, "rcs_m2", truth.get("rcs_m2"), true)
		_check_state_field(eid, st, "ir_signature", truth.get("ir_signature"), true)
		_check_state_field(eid, st, "radius_km", truth.get("radius_km"), true)
		_ok(bool(st.get("metadata_found", false)),
			"ballistics state metadata_found=true: " + eid,
			"metadata_found=" + str(st.get("metadata_found", "missing")))
		_eq(String(st.get("radius_source", "missing")), "catalog",
			"ballistics radius from catalog (not silent default): " + eid)

	_step("5. contacts: missing info stays UNKNOWN; no truth auto-copy; no friend default")
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	var by_eid: Dictionary = {}
	for raw_c in contacts:
		if raw_c is Dictionary:
			var c: Dictionary = raw_c
			var ceid := String(c.get("entity_id", ""))
			if ceid != "":
				by_eid[ceid] = c
	_ok(contacts.size() > 0, "binder.contacts non-empty", "n=" + str(contacts.size()))
	for eid in _truth_ids:
		var truth: Dictionary = _truth[eid]
		var truth_side := String(truth.get("side", "")).to_lower()
		var truth_identity := String(truth.get("identity", "")).to_lower()
		var row: Dictionary = by_eid.get(eid, {}) if by_eid.get(eid) is Dictionary else {}
		if row.is_empty():
			# own ship / entity not exposed as contact is allowed; log for review
			_info("contact absent for " + eid + " (allowed only if not a player contact)")
			continue
		var badge := String(row.get("badge", ""))
		var cside := String(row.get("side", "missing")).to_lower()
		var cident := String(row.get("identity", "missing")).to_lower()
		var ctype := String(row.get("type", "missing"))
		var ssrc := String(row.get("side_source", "missing"))
		var isrc := String(row.get("identity_source", "missing"))
		_ok(ssrc != "missing", "contact has explicit side_source: " + eid,
			"badge=%s side=%s" % [badge, cside])
		_ok(isrc != "missing", "contact has explicit identity_source: " + eid,
			"badge=%s identity=%s" % [badge, cident])
		if ssrc == "facility_registry":
			# facility ownership is content/database data, not world truth; identity must stay player-derived
			_ok(cident == "unknown", "facility contact identity stays unknown: " + eid,
				"identity=%s identity_source=%s" % [cident, isrc])
			continue
		# Default at boot: no player evidence → unknown, never "friend", never truth side/identity.
		_ok(cside == "unknown", "contact side unknown (no evidence): " + eid,
			"side=%s side_source=%s badge=%s" % [cside, ssrc, badge])
		if isrc == "track":
			_ok(cident == "unknown", "track identity unknown at boot: " + eid,
				"identity=%s" % cident)
		else:
			_eq(cident, "unknown", "contact identity unknown (no evidence): " + eid)
		_ok(cside != "friend", "contact does not default to friend: " + eid, "side=" + cside)
		if truth_side != "":
			_ok(cside != truth_side,
				"contact side not auto-copied from world truth: " + eid,
				"contact=%s truth=%s" % [cside, truth_side])
		if isrc == "track":
			_ok(cident != truth_identity,
				"track identity not auto-copied from world truth: " + eid,
				"contact=%s truth=%s" % [cident, truth_identity])
		if badge == "ENTITY":
			_ok(ctype != "friendly", "entity contact not defaulted to friendly type: " + eid,
				"type=" + ctype)
	# global guards
	var friend_contacts: Array = []
	var truth_leaks: Array = []
	for eid2 in by_eid.keys():
		var c2: Dictionary = by_eid[eid2]
		if String(c2.get("side_source", "")) == "facility_registry":
			continue
		var sid := String(c2.get("side", "")).to_lower()
		if sid == "friend":
			friend_contacts.append(String(eid2))
		var t2: Dictionary = _truth.get(String(eid2), {})
		if not t2.is_empty() and sid != "" and sid == String(t2.get("side", "")).to_lower():
			truth_leaks.append("%s(%s)" % [String(eid2), sid])
	_ok(friend_contacts.is_empty(), "no silent friend default in contacts",
		"friend_contacts=" + str(friend_contacts))
	_ok(truth_leaks.is_empty(), "no truth side leaked into contacts",
		"leaks=" + str(truth_leaks))

	_step("6. truth vs player view separation (explicit evidence)")
	# The simulation authority knows harmattan is hostile; the player-facing track/contact does not.
	var hmeta := _get_metadata("harmattan")
	var hrow: Dictionary = by_eid.get("harmattan", {})
	_eq(String(hmeta.get("side", "")), "hostile", "catalog truth harmattan side")
	if not hrow.is_empty():
		_ok(String(hrow.get("side", "")).to_lower() != String(hmeta.get("side", "")).to_lower(),
			"player contact does not reveal catalog truth side",
			"contact=%s truth=%s" % [String(hrow.get("side", "")), String(hmeta.get("side", ""))])
		_ok(String(hrow.get("identity", "")).to_lower() != String(hmeta.get("identity", "")).to_lower(),
			"player track identity is evidence-derived, not catalog truth",
			"contact=%s truth=%s" % [String(hrow.get("identity", "")), String(hmeta.get("identity", ""))])
	_finish()


func _get_metadata(eid: String) -> Dictionary:
	if _session != null and _session.has_method("entity_metadata"):
		var m = _session.entity_metadata(eid)
		if m is Dictionary:
			return m
	# pre-A1.1 fallback: only world/snapshot fields exist (missing static metadata)
	var out := {"found": false, "legacy_fallback": true, "id": eid}
	var snap: Dictionary = _session.snapshot() if _session != null else {}
	for raw in (snap.get("entities", []) if snap.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == eid:
			out = (raw as Dictionary).duplicate(true)
			out["found"] = true
			out["legacy_fallback"] = true
			break
	return out


func _check_meta_field(eid: String, meta: Dictionary, field: String, expected) -> void:
	# scenario JSON omits absent strings (null); canonical catalog records them as "".
	if expected == null:
		expected = ""
	var actual = meta.get(field, "<missing>")
	if field in NUM_FIELDS:
		var ok_num := false
		if actual is int or actual is float:
			ok_num = absf(float(actual) - float(expected)) <= 1.0e-9
		_ok(ok_num, "metadata %s.%s preserved" % [eid, field],
			"actual=%s expected=%s legacy=%s" % [str(actual), str(expected), str(meta.get("legacy_fallback", false))])
	else:
		_ok(actual == expected, "metadata %s.%s preserved" % [eid, field],
			"actual=%s expected=%s legacy=%s" % [str(actual), str(expected), str(meta.get("legacy_fallback", false))])


func _check_state_field(eid: String, st: Dictionary, field: String, expected, is_num := false) -> void:
	var actual = st.get(field, "<missing>")
	if is_num:
		var ok_num := false
		if actual is int or actual is float:
			ok_num = absf(float(actual) - float(expected)) <= 1.0e-9
		_ok(ok_num, "ballistics %s.%s from authority" % [eid, field],
			"actual=%s expected=%s" % [str(actual), str(expected)])
	else:
		_ok(actual == expected, "ballistics %s.%s from authority" % [eid, field],
			"actual=%s expected=%s" % [str(actual), str(expected)])


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
	print("[A1] FAIL entry timeout waiting for v1_hud (%d frames / %d ms)" % [MAX_BOOT_FRAMES, MAX_BOOT_MS])
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}
