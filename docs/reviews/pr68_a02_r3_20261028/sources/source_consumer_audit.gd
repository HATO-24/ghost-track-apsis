extends SceneTree

# PR68 R3: actual HUD empty-mapping consumer; original R1/R2/R5 are not executed.
const GS := preload("res://scripts/core/game_session.gd")
const Binder := preload("res://scripts/ui/shell_binder.gd")
const HUD := preload("res://scripts/ui/v1_hud.gd")
var result: Dictionary = {"head": "755ab5ed629165656a566427523b01045775fc0f", "cases": {}}

func _initialize() -> void:
	_real_track_consumer()
	_prefilled_control()
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a02-r3/sources/source_consumer_audit.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("SOURCE_CONSUMER_AUDIT_JSON=" + out)
	for k in result.cases.keys():
		print("CASE ", k, " ", JSON.stringify(result.cases[k]))
	quit(0)

func _new():
	return GS.new(_seed())

func _binder(s):
	var b = Binder.new()
	b.session = s
	return b

func _real_track_consumer() -> void:
	var s = _new()
	s.tick(6.0)
	var b = _binder(s)
	b.refresh()
	var hud = HUD.new()
	hud.binder = b
	hud._combat = s.combat_service
	hud._seed_combat_tracks()
	var tracks: Array = b.track_vm.get("tracks", []).duplicate(true)
	var selected := ""
	for raw in tracks:
		if raw is Dictionary and String(raw.get("target_id", raw.get("entity_id", ""))) == "raider_2":
			selected = String(raw.get("track_id", raw.get("id", "")))
	if selected == "" and not tracks.is_empty():
		selected = String(tracks[0].get("track_id", tracks[0].get("id", "")))
	var pre_manual_combat: Dictionary = s.combat_service.track(selected).duplicate(true)
	var conf: Dictionary = s.identity_manual_confirm("player_intel", "raider_2", "friend", {"authority": "command"})
	b.refresh()
	var pre_fire_identity: Dictionary = s.combat_identity(selected)
	var fire: Dictionary = {}
	if selected != "":
		fire = s.request_fire(selected, "missile", true, {"target_entity": "raider_2"})
	var combat_after_fire: Dictionary = s.combat_service.track(selected).duplicate(true)
	s.combat_register_track("raider_2", {"identity": "unknown", "entity_id": "raider_2", "range_km": 600.0})
	var same_id_fire: Dictionary = s.request_fire("raider_2", "missile", true, {"target_entity": "raider_2"})
	result.cases["actual_hud_track_key"] = {"ready": s.ready,
		"radar_tick_s": 6.0, "actual_hud_seed_called": true,
		"sensor_track_map": s._sensor_track_map.duplicate(true),
		"actual_tracks": tracks, "selected": selected,
		"pre_manual_combat_track": pre_manual_combat,
		"manual_control": conf, "contacts": b.contacts,
		"pre_fire_combat_identity_no_hint": pre_fire_identity,
		"fire": fire, "entity_op": s.identity_operational("player_intel", "raider_2"),
		"track_combat_identity": s.combat_identity(selected),
		"combat_track": combat_after_fire,
		"same_id_control_fire": same_id_fire,
		"same_id_control_identity": s.combat_identity("raider_2"),
		"same_id_control_track": s.combat_service.track("raider_2")}
	hud.free()

func _prefilled_control() -> void:
	var s = _new()
	s.combat_service.register_track("T0009", {"id": "T0009", "batch": "T0009",
		"track_id": "raider_2", "entity_id": "raider_2", "identity": "unknown",
		"range_km": 600.0, "in_arc": true})
	var conf: Dictionary = s.identity_manual_confirm("player_intel", "raider_2", "friend", {"authority": "command"})
	var pre_fire: Dictionary = s.combat_identity("T0009")
	var fire: Dictionary = s.request_fire("T0009", "missile", true, {"target_entity": "raider_2"})
	result.cases["prefilled_compatibility"] = {"manual_control": conf,
		"identity": pre_fire, "fire": fire,
		"combat_track": s.combat_service.track("T0009"),
		"entity_identity": s.combat_identity("raider_2")}

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


