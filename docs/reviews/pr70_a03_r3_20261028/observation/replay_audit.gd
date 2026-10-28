extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
var result := {"head": "022a7e0e6b0ab2ce65f228f98b4a1146d18792f8", "cases": {}}

func _initialize() -> void:
	var captured := _original_replay()
	_candidate_replay()
	_normal_ally()
	_owner_rejection_boundary(captured)
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a03-r3/observation/replay_audit.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("R3_REPLAY_AUDIT_JSON=" + out)
	for k in result.cases.keys():
		print("CASE ", k, " ", JSON.stringify(result.cases[k]))
	quit(0 if not captured.is_empty() else 2)

func _register_combat(s) -> void:
	s.combat_service.register_track("raider_2", {"id": "raider_2", "entity_id": "raider_2",
		"identity": "unknown", "range_km": 600.0, "in_arc": true})

func _capture(s, ticks_max := 8) -> Dictionary:
	for i in range(ticks_max):
		s.tick(1.0)
		for raw in s.ew_delivery_queue():
			if raw is Dictionary and String(raw.get("target_id", "")) == "raider_2":
				return raw.duplicate(true)
	return {}

func _original_replay() -> Dictionary:
	var s = _new()
	_register_combat(s)
	_ticks(s, 2)
	s.apply_ew(_effect())
	var captured := _capture(s)
	_ticks(s, 9)
	var natural := _brief(s)
	s.ew_service.expire()
	_ticks(s, 5)
	var recovered := _brief(s)
	if not captured.is_empty():
		s._deliver_ew_observation(captured)
	var after := _brief(s)
	result.cases["original_exact_replay"] = {"captured_real_entry": captured,
		"natural_before_expire": natural, "recovered_before_repeat": recovered,
		"after_exact_repeat": after,
		"repeat_method": "_deliver_ew_observation(captured_real_entry) once"}
	return captured

func _candidate_replay() -> void:
	var s = _new()
	_register_combat(s)
	s.apply_ew(_effect({"effect": "deception", "severity": 0.6}))
	var captured := _capture(s)
	_ticks(s, 3)
	var before := _brief(s)
	if not captured.is_empty():
		s._deliver_ew_observation(captured)
	result.cases["candidate_exact_replay"] = {"captured_real_entry": captured,
		"before": before, "after": _brief(s)}

func _normal_ally() -> void:
	var s = _new("ally_ship")
	s.apply_ew(_effect())
	_ticks(s, 6)
	var before := _brief(s)
	_ticks(s, 5)
	result.cases["normal_ally_new_observations"] = {"before": before, "after": _brief(s)}

func _owner_rejection_boundary(captured: Dictionary) -> void:
	var s = _new()
	s.sensor_service.set_radar_enabled(false)
	_ticks(s, 7)
	var before := _brief(s)
	var misaddressed := captured.duplicate(true)
	misaddressed["owner_id"] = "ally_intel"
	if not captured.is_empty():
		s._deliver_ew_observation(misaddressed)
	result.cases["owner_rejected_track_side_effect"] = {"before": before,
		"input": misaddressed, "after": _brief(s),
		"control_method": "Only delivery owner changed to ally; actual source observer remains own_ship, no share authorization"}

func _brief(s) -> Dictionary:
	var pv: Dictionary = s.intel_view("player_intel")
	var av: Dictionary = s.intel_view("ally_intel")
	return {"ready": s.ready, "now": s.now_s(),
		"queue": s.ew_delivery_queue(), "delivered": s.ew_delivered_observations(),
		"rejected": s.ew_rejected_deliveries(),
		"player_measurement": s.owner_measurement_quality("player_intel", "raider_2"),
		"ally_measurement": s.owner_measurement_quality("ally_intel", "raider_2"),
		"player_observations": pv.get("observations", []),
		"ally_observations": av.get("observations", []),
		"candidates": s.ew_candidate_evidence("player_intel"),
		"identity_evidence": s.identity_evidence_for("player_intel", "raider_2"),
		"combat_track": s.combat_service.track("raider_2").duplicate(true),
		"combat_quality_cache": s._ew_combat_quality.duplicate(true),
		"sensor_track_map": s._sensor_track_map.duplicate(true),
		"global_track_vm": s.track_table.vm()}

func _new(observer_id := "own_ship"):
	var cfg := _seed()
	cfg["sensor_service"]["observer"]["id"] = observer_id
	if observer_id != "own_ship":
		cfg["entities"].append({"id": observer_id, "kind": "ship",
			"pos_km": [321719.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]})
	return GS.new(cfg)

func _ticks(s, n: int) -> void:
	for i in range(n):
		s.tick(1.0)

func _effect(extra := {}) -> Dictionary:
	var e := {"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 60.0, "source_id": "audit-ew"}
	for k in extra.keys():
		e[k] = extra[k]
	return e


func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "fleet_id": "own_fleet",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "fleet_id": "ally_fleet",
				"authorized_actors": ["ally_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet"}],
		"ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship",
				"pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
	}




