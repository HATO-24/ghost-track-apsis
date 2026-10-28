extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const DT := 1.0
const FIRE_T := 24.0

func _initialize() -> void:
	var result := {
		"purpose": "Same-seed/same-time actual GameSession fire comparison; real Sensor EW arm, natural clean Sensor arm, and isolated legacy no-Sensor compatibility arm.",
		"head": "ea29da7138ad353c4198f76547f57c4e0b07142d",
		"fire_t": FIRE_T,
		"target_initial_range_km": 600.0,
		"cases": {
			"clean_sensor": _run_case(false, true),
			"moderate_ew_sensor": _run_case(true, true),
			"legacy_no_sensor": _run_case(false, false)
		}}
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a03-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a03-r2/fire/ballistics_quality_consumer.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write diagnostic result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("A03_R2_BALLISTICS_QUALITY_RESULT: ", JSON.stringify(result))
	quit(0)

func _run_case(jammed: bool, with_sensor: bool) -> Dictionary:
	var s = GS.new(_seed(with_sensor))
	for i in range(2):
		s.tick(DT)
	var track: Dictionary = s.combat_register_track("raider_2", {
		"batch": "raider_2", "entity_id": "raider_2", "track_id": "raider_2",
		"identity": "hostile", "threat": "hostile", "range_km": 600.0,
		"in_arc": true, "destroyed": false})
	var grant: Dictionary = s.grant_authorization("FIRE", "target", "raider_2", 90.0)
	var ew: Dictionary = {}
	if jammed:
		ew = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 60.0, "source_id": "DIAG-R2-FIRE"})
	var pre_solution_measurement: Dictionary = {}
	while s.now_s() < 9.0:
		s.tick(DT)
		pre_solution_measurement = s.owner_measurement_quality("player_intel", "raider_2")
	var solve_req: Dictionary = s.combat_request_solution("raider_2", "missile", true)
	var sol0: Dictionary = solve_req.get("solution", {}) if solve_req.get("solution") is Dictionary else {}
	var sid := String(sol0.get("solution_id", ""))
	while s.now_s() < FIRE_T:
		s.tick(DT)
	var status: Dictionary = s.combat_service.solution_status(sid)
	var owner_at_fire: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var track_at_fire: Dictionary = s.combat_service.track("raider_2")
	var states: Dictionary = s._ballistics_states()
	var shooter_state: Dictionary = states.get("own_ship", {}) if states.get("own_ship") is Dictionary else {}
	var target_state: Dictionary = states.get("raider_2", {}) if states.get("raider_2") is Dictionary else {}
	var physical_prediction: Dictionary = s.combat_ballistics.predict(shooter_state, target_state, "missile")
	var service_prediction: Dictionary = s.combat_service.predict_shot("raider_2", "missile")
	var ammo_before := int((s.combat_service.weapons.get("missile", {}) as Dictionary).get("ammo", -1))
	var shot: Dictionary = s.request_fire("raider_2", "missile", true, _fire_opts())
	var ammo_after := int((s.combat_service.weapons.get("missile", {}) as Dictionary).get("ammo", -1))
	return {
		"jammed": jammed, "sensor_enabled": with_sensor,
		"ew_apply": ew, "registration": track, "grant": grant,
		"t_at_fire": s.now_s(), "pre_solution_owner_measurement": pre_solution_measurement,
		"owner_measurement_at_fire": owner_at_fire, "combat_track_at_fire": track_at_fire,
		"solution_request": solve_req, "solution_at_fire": status,
		"physical_states_at_fire": {"shooter": shooter_state, "target": target_state},
		"combat_service_prediction_before_fire": service_prediction,
		"actual_ballistics_prediction_before_fire": physical_prediction,
		"session_request_fire_result": shot, "ammo_before": ammo_before, "ammo_after": ammo_after,
		"projectiles_after": s.combat_ballistics.projectiles_all()
	}

func _fire_opts() -> Dictionary:
	return {"target_entity": "raider_2", "actor_id": "player_ctrl",
		"controller_id": "player_ctrl", "domain_id": "player",
		"fleet_id": "own_fleet", "shooter_id": "own_ship"}

func _seed(with_sensor: bool) -> Dictionary:
	var data := {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot", "track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet", "role": "flag"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}],
		"ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
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
