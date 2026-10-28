extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const DT := 1.0

func _initialize() -> void:
	var result := {
		"purpose": "Minimal actual Session prefire prediction route and Ballistics normalized quality compatibility check.",
		"head": "5d372ea2df7c49badeea3846c16b839b1f6faef1",
		"cases": {
			"clean_sensor": _run_sensor_case(false),
			"moderate_sensor": _run_sensor_case(true),
			"legacy_no_sensor": _run_legacy_case()
		}}
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a03-r4-validation/GHOST TRACK_APSIS/.test-results/sol-a03-r4/fire/prediction_quality_contract.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("A03_R4_PREDICTION_RESULT: ", JSON.stringify(result))
	quit(0)

func _run_sensor_case(jammed: bool) -> Dictionary:
	var s = GS.new(_seed(true))
	for i in range(2):
		s.tick(DT)
	var entity_track: Dictionary = s.combat_register_track("raider_2", _track("raider_2"))
	var hud_track: Dictionary = s.combat_register_track("T0001", _track("T0001"))
	var jam: Dictionary = {}
	if jammed:
		jam = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 60.0, "source_id": "DIAG-R4-PRED"})
	while s.now_s() < 9.0:
		s.tick(DT)
	var solve: Dictionary = s.combat_request_solution("T0001", "missile", true)
	while s.now_s() < 24.0:
		s.tick(DT)
	var entity_owner: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var hud_owner: Dictionary = s.owner_measurement_quality("player_intel", "T0001")
	var entity_prediction: Dictionary = s.combat_predict_track("raider_2", "missile")
	var hud_prediction: Dictionary = s.combat_predict_track("T0001", "missile")
	var service_norm: Dictionary = s.combat_service.predict_shot("raider_2", "missile")
	var states: Dictionary = s._ballistics_states()
	var ss: Dictionary = states.get("own_ship", {}) if states.get("own_ship") is Dictionary else {}
	var ts: Dictionary = states.get("raider_2", {}) if states.get("raider_2") is Dictionary else {}
	var weapon: Dictionary = s.combat_service.weapon_def("missile")
	var mq_only: Dictionary = s.combat_ballistics.predict(ss, ts, "missile", {
		"measurement_quality": float(entity_owner.get("measurement_quality", 1.0))})
	var explicit_prediction: Dictionary = s.combat_ballistics.predict(ss, ts, "missile", {
		"measurement_quality": float(service_norm.get("measurement_quality", 1.0)),
		"quality": float(service_norm.get("hit_probability", -1.0)),
		"quality_accuracy_mult": float(service_norm.get("quality_accuracy_mult", 1.0)),
		"error_km": float(service_norm.get("error_km", -1.0))})
	return {
		"jammed": jammed, "jam_apply": jam,
		"track_map": s._sensor_track_map.duplicate(true),
		"entity_track": entity_track, "hud_track": hud_track,
		"owner_entity": entity_owner, "owner_hud": hud_owner,
		"combat_quality_entity": s.combat_service.track("raider_2"),
		"combat_quality_hud": s.combat_service.track("T0001"),
		"solve_request": solve, "service_normalized_prediction": service_norm,
		"session_prefire_entity": entity_prediction,
		"session_prefire_hud": hud_prediction,
		"direct_ballistics_mq_only": mq_only,
		"direct_ballistics_explicit_normalized": explicit_prediction,
		"weapon_definition": weapon,
		"physical_states": {"shooter": ss, "target": ts}
	}

func _run_legacy_case() -> Dictionary:
	var s = GS.new(_seed(false))
	for i in range(2):
		s.tick(DT)
	var reg: Dictionary = s.combat_register_track("raider_2", _track("raider_2"))
	while s.now_s() < 9.0:
		s.tick(DT)
	var solve: Dictionary = s.combat_request_solution("raider_2", "missile", true)
	while s.now_s() < 24.0:
		s.tick(DT)
	var owner: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var tr: Dictionary = s.combat_service.track("raider_2")
	var prediction: Dictionary = s.combat_predict_track("raider_2", "missile")
	var states: Dictionary = s._ballistics_states()
	var ss: Dictionary = states.get("own_ship", {}) if states.get("own_ship") is Dictionary else {}
	var ts: Dictionary = states.get("raider_2", {}) if states.get("raider_2") is Dictionary else {}
	var direct: Dictionary = s.combat_ballistics.predict(ss, ts, "missile")
	return {"registration": reg, "owner_measurement": owner,
		"combat_track": tr, "solve": solve, "session_prefire": prediction,
		"direct_ballistics_default": direct}

func _track(key: String) -> Dictionary:
	var d := {"batch": key, "identity": "hostile", "threat": "hostile",
		"range_km": 600.0, "in_arc": true, "destroyed": false}
	if key == "raider_2":
		d["entity_id"] = "raider_2"
		d["track_id"] = "raider_2"
	return d

func _seed(with_sensor: bool) -> Dictionary:
	var data := {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot", "track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]}],
		"fleet_instances": [{"entity_instance_id": "own_ship", "domain_id": "player",
			"fleet_id": "own_fleet", "role": "flag"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}], "ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0, "decay_half_life_s": 60.0,
			"auto": {"enabled": false}},
		"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship", "pos_km": [321719.0, 600.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}]}
	if with_sensor:
		data["sensor_service"] = {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
				"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}}
	return data
