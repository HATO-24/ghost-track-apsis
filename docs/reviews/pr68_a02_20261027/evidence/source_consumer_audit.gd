extends SceneTree

# Independent, bounded source/consumer audit for PR68 head 7293058d.
# Reuses only JC-A02 seed fixture; does not invoke the formal probe.
const GS := preload("res://scripts/core/game_session.gd")
const Binder := preload("res://scripts/ui/shell_binder.gd")
const HUD := preload("res://scripts/ui/v1_hud.gd")
var result: Dictionary = {"head": "7293058d1c0d3cdedceff1fae6233523e7f8b313", "cases": {}}

func _initialize() -> void:
	_manual_binder()
	_iff_owner_and_duplicate()
	_real_sensor_and_signal()
	_real_track_consumer()
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a02/evidence/source_consumer_audit.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("SOURCE_CONSUMER_AUDIT_JSON=" + out)
	for k in result.cases.keys():
		print("CASE ", k, " ", JSON.stringify(result.cases[k]))
	quit(0)

func _new(extra := {}):
	var seed := _seed()
	for k in extra.keys():
		seed[k] = extra[k]
	return GS.new(seed)

func _binder(s):
	var b = Binder.new()
	b.session = s
	return b

func _brief(s, target: String) -> Dictionary:
	var b = _binder(s)
	return {"op": s.identity_operational("player_intel", target),
		"hud": b.ident_view({"entity_id": target}, true),
		"combat": s.combat_identity(target), "audit": s.authority_intel.identity_audit.duplicate(true)}

func _manual_binder() -> void:
	var s = _new()
	var b = _binder(s)
	var row := {"entity_id": "raider_2"}
	var guarded: Dictionary = s.identity_manual_confirm("player_intel", "raider_2", "hostile",
		{"authority": "cic_operator", "authorized": true})
	var legacy: Dictionary = b.ident_confirm(row, "hostile")
	var before := _brief(s, "raider_2")
	s.tick(1.0)
	var after := _brief(s, "raider_2")
	var cleared: Dictionary = b.ident_clear(row)
	var clear_before := _brief(s, "raider_2")
	s.tick(1.0)
	result.cases["binder_manual_old_route"] = {"ready": s.ready, "guarded_same_authority": guarded,
		"binder_confirm": legacy, "immediate": before, "after_tick": after,
		"binder_clear": cleared, "clear_immediate": clear_before, "clear_after_tick": _brief(s, "raider_2")}
	var s2 = _new()
	var no_auth: Dictionary = s2.identification_manual_confirm("raider_2", "hostile")
	s2.tick(1.0)
	result.cases["legacy_manual_no_authority"] = {"call": no_auth, "after_tick": _brief(s2, "raider_2")}

func _iff_owner_and_duplicate() -> void:
	var s = _iff_contact_session()
	var before: Dictionary = s.identity_operational("player_intel", "harmattan")
	var q: Dictionary = s.identity_iff_query("ally_intel", "harmattan", {"mode": "mode_s"})
	result.cases["iff_ally_query_own_leak"] = {"player_before": before, "query": q,
		"player_after": s.identity_operational("player_intel", "harmattan"),
		"ally_after": s.identity_operational("ally_intel", "harmattan"),
		"player_raw_evidence": s.identification_evidence("harmattan"),
		"ally_assessment": s.identity_get_for("ally_intel", "harmattan")}
	var s_default = _iff_contact_session()
	var q_default: Dictionary = s_default.identity_iff_query("player_intel", "harmattan")
	var s_explicit = _iff_contact_session()
	var q_explicit: Dictionary = s_explicit.identity_iff_query("player_intel", "harmattan", {"mode": "mode_s"})
	var repeated: Dictionary = s_explicit.identity_iff_query("player_intel", "harmattan", {"mode": "mode_s"})
	var s_binder = _iff_contact_session()
	var b = _binder(s_binder)
	var binder_query: Dictionary = b.ident_interrogate({"entity_id": "harmattan"}, "mode_s")
	result.cases["iff_default_double_route"] = {
		"default_query": q_default, "default_evidence": s_default.identification_evidence("harmattan"),
		"default_op": s_default.identity_operational("player_intel", "harmattan"),
		"explicit_query": q_explicit, "explicit_evidence": s_explicit.identification_evidence("harmattan"),
		"explicit_op": s_explicit.identity_operational("player_intel", "harmattan"),
		"same_tick_explicit_repeat": repeated,
		"binder_legal_query": binder_query, "binder_legal_view": _brief(s_binder, "harmattan")}

func _iff_contact_session():
	var s = _new({"sensor_service": {
		"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
		"targets": [{"id": "harmattan", "pos_km": [321719.0, 900.0, 0.0], "rcs_m2": 100.0}],
		"options": {"radar_enabled": true, "emcon": false}}})
	s.tick(6.0)
	return s

func _real_sensor_and_signal() -> void:
	var target := {"id": "raider_2", "pos_km": [321719.0, 500.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0], "rcs_m2": 100.0, "temp_k": 300.0,
		"area_m2": 1000.0, "size_m": 50.0, "illum": 1.0,
		"transponder": "ok", "iff_code": "VISIBLE-DECLARED", "registered": true,
		"crypto_epoch": "epoch-1", "side": "hostile",
		"classification": {"ship_class": "DDG", "role": "test", "faction": "visible-markings"}}
	var sensor_cfg := {"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
		"targets": [target], "options": {"radar_enabled": true, "emcon": false}}
	var s = _new({"sensor_service": sensor_cfg})
	var b = _binder(s)
	s.tick(6.0) # Legal detected-contact positive; identity-only evidence cannot create a track.
	var iff: Dictionary = b.ident_iff({"entity_id": "raider_2"})
	var before_flush := _brief(s, "raider_2")
	s.tick(1.0)
	var after_flush := _brief(s, "raider_2")
	var optical_start: Dictionary = s.sensor_service.start_channel("optical", "raider_2")
	s.tick(30.0)
	result.cases["real_sensor_iff_optical"] = {"ready": s.ready, "iff": iff,
		"iff_immediate": before_flush, "iff_after_flush": after_flush,
		"optical_start": optical_start, "sensor_evidence": s.sensor_service.evidence.duplicate(true),
		"normalized_evidence": s.identification_evidence("raider_2"), "final": _brief(s, "raider_2")}
	var no_declaration := target.duplicate(true)
	no_declaration["transponder"] = "off"
	no_declaration.erase("registered")
	var variants: Array = []
	for hidden_side in ["friend", "hostile"]:
		var t := no_declaration.duplicate(true)
		t["side"] = hidden_side
		var c := sensor_cfg.duplicate(true)
		c["targets"] = [t]
		var sx = _new({"sensor_service": c})
		var bx = _binder(sx)
		sx.tick(6.0)
		var rx: Dictionary = bx.ident_iff({"entity_id": "raider_2"})
		variants.append({"hidden_side": hidden_side, "reply": rx, "view": _brief(sx, "raider_2")})
	result.cases["sensor_no_reply_hidden_side_control"] = variants
	var emitter := {"type": "radar", "model": "YW-R9", "signature_name": "YW-R9",
		"active": true, "silent": false, "lpi": false, "frequency_mhz": 9500.0,
		"power_dbm": 90.0, "gain_tx_dbi": 30.0, "prf_hz": 1200.0, "scan_period_s": 1.0}
	var signal_cfg := {"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
		"targets": [{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0], "emissions": [emitter]}],
		"elint": {"enabled": true, "range_km": 60000.0, "refresh_s": 1.0}}
	var se = _new({"signal_service": signal_cfg})
	se.tick(1.0)
	result.cases["real_signal_elint"] = {"ready": se.ready,
		"raw_evidence": se.signal_service.evidence.duplicate(true),
		"normalized_evidence": se.identification_evidence("raider_2"), "view": _brief(se, "raider_2")}

func _real_track_consumer() -> void:
	var s = _new()
	s.tick(6.0)
	var b = _binder(s)
	b.refresh()
	var hud = HUD.new()
	hud.binder = b
	hud._combat = s.combat_service
	hud._seed_combat_tracks()
	var tracks: Array = b.track_vm.get("tracks", [])
	var selected := ""
	for raw in tracks:
		if raw is Dictionary and String(raw.get("target_id", raw.get("entity_id", ""))) == "raider_2":
			selected = String(raw.get("track_id", raw.get("id", "")))
	if selected == "" and not tracks.is_empty():
		selected = String(tracks[0].get("track_id", tracks[0].get("id", "")))
	var conf: Dictionary = s.identity_manual_confirm("player_intel", "raider_2", "friend", {"authority": "command"})
	b.refresh()
	var fire: Dictionary = {}
	if selected != "":
		fire = s.request_fire(selected, "missile", true, {"target_entity": "raider_2"})
	s.combat_register_track("raider_2", {"identity": "unknown", "entity_id": "raider_2", "range_km": 600.0})
	var same_id_fire: Dictionary = s.request_fire("raider_2", "missile", true, {"target_entity": "raider_2"})
	result.cases["actual_hud_track_key"] = {"actual_tracks": tracks, "selected": selected,
		"manual_control": conf, "contacts": b.contacts, "fire": fire,
		"entity_op": s.identity_operational("player_intel", "raider_2"),
		"track_combat_identity": s.combat_identity(selected), "combat_track": s.combat_service.track(selected),
		"same_id_control_fire": same_id_fire, "same_id_control_track": s.combat_service.track("raider_2")}
	hud.free()

func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "faction": "ueg", "roe": "DEFENSIVE",
				"fleet_id": "ally_fleet", "authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "faction": "ocu", "roe": "AGGRESSIVE",
				"fleet_id": "enemy_fleet", "authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet", "role": "flag"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet", "role": "picket"},
			{"entity_instance_id": "raider_2", "domain_id": "opfor",
				"fleet_id": "enemy_fleet", "role": "raider"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}],
		"identification_service": {"evidence_ttl_s": 12.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
		"transponder_service": {
			"content_path": "res://framework/content/transponders_prologue.json"},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship",
				"pos_km": [321719.0, 300.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship",
				"pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]},
			{"id": "harmattan", "kind": "ship",
				"pos_km": [321719.0, 900.0, 0.0], "vel_kmps": [0.0, 0.2, 0.0]},
			{"id": "probe_ship", "kind": "ship",
				"pos_km": [321719.0, 1200.0, 0.0], "vel_kmps": [0.0, 0.1, 0.0],
				"transponder_profile": "ueg_military"}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
	}
