extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const DT := 1.0
const FIRE_T := 24.0
const AFTER_TICKS := 3

func _initialize() -> void:
	var result := {
		"purpose": "Real clean/moderate Sensor same-seed same-geometry fire comparison; HUD T0001 fire route, entity/HUD prefire prediction, 3 postlaunch ticks.",
		"head": "022a7e0e6b0ab2ce65f228f98b4a1146d18792f8",
		"fire_t": FIRE_T, "after_ticks": AFTER_TICKS,
		"cases": {
			"clean": _run_case(false),
			"moderate": _run_case(true)
		}}
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a03-r3-validation/GHOST TRACK_APSIS/.test-results/sol-a03-r3/fire/quality_motion_comparison.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("A03_R3_QUALITY_MOTION_RESULT: ", JSON.stringify(result))
	quit(0)

func _run_case(jammed: bool) -> Dictionary:
	var s = GS.new(_seed())
	for i in range(2):
		s.tick(DT)
	var tr_entity: Dictionary = s.combat_register_track("raider_2", _track_data("raider_2"))
	var tr_hud: Dictionary = s.combat_register_track("T0001", _track_data("T0001"))
	var grant: Dictionary = s.grant_authorization("FIRE", "target", "T0001", 90.0)
	var jam: Dictionary = {}
	if jammed:
		jam = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 60.0, "source_id": "DIAG-R3-QUALITY"})
	var quality_before_solution: Dictionary = {}
	while s.now_s() < 9.0:
		s.tick(DT)
		quality_before_solution = s.owner_measurement_quality("player_intel", "raider_2")
	var solution_request: Dictionary = s.combat_request_solution("T0001", "missile", true)
	var sol0: Dictionary = solution_request.get("solution", {}) if solution_request.get("solution") is Dictionary else {}
	var sid := String(sol0.get("solution_id", ""))
	while s.now_s() < FIRE_T:
		s.tick(DT)
	var solution_ready: Dictionary = s.combat_service.solution_status(sid)
	var owner_entity_q: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var owner_hud_q: Dictionary = s.owner_measurement_quality("player_intel", "T0001")
	var map_snapshot: Dictionary = s._sensor_track_map.duplicate(true)
	var pre_entity_prediction: Dictionary = s.combat_predict_track("raider_2", "missile")
	var pre_hud_prediction: Dictionary = s.combat_predict_track("T0001", "missile")
	var combat_entity_prediction: Dictionary = s.combat_service.predict_shot("raider_2", "missile")
	var combat_hud_prediction: Dictionary = s.combat_service.predict_shot("T0001", "missile")
	var states: Dictionary = s._ballistics_states()
	var ss: Dictionary = states.get("own_ship", {}) if states.get("own_ship") is Dictionary else {}
	var ts: Dictionary = states.get("raider_2", {}) if states.get("raider_2") is Dictionary else {}
	var physical_states := {"shooter": ss, "target": ts}
	var fire := s.request_fire("T0001", "missile", true, _fire_opts())
	var shot_at_launch := _projectile_snapshot(s)
	var post: Array = []
	for i2 in range(AFTER_TICKS):
		s.tick(DT)
		var snap := _projectile_snapshot(s)
		snap["session_t"] = s.now_s()
		post.append(snap)
	return {
		"jammed": jammed, "noise_jam": jam, "target_vel_seed_kmps": [0.0, 0.0, 0.0],
		"registered_entity": tr_entity, "registered_hud": tr_hud, "grant": grant,
		"quality_at_solution_creation": quality_before_solution,
		"owner_entity_quality_at_fire": owner_entity_q, "owner_hud_quality_at_fire": owner_hud_q,
		"sensor_track_map_at_fire": map_snapshot,
		"combat_entity_track_at_fire": s.combat_service.track("raider_2"),
		"combat_hud_track_at_fire": s.combat_service.track("T0001"),
		"solution_request": solution_request, "solution_ready_before_fire": solution_ready,
		"pre_fire_prediction_entity_route": pre_entity_prediction,
		"pre_fire_prediction_hud_route": pre_hud_prediction,
		"combat_service_prediction_entity": combat_entity_prediction,
		"combat_service_prediction_hud": combat_hud_prediction,
		"physical_states_at_fire": physical_states,
		"fire_result": fire, "projectile_at_launch": shot_at_launch,
		"projectiles_after_ticks": post,
		"ammo_after_ticks": (s.combat_service.weapons.get("missile", {}) as Dictionary).get("ammo", -1)
	}

func _track_data(key: String) -> Dictionary:
	var d := {"batch": key, "identity": "hostile", "threat": "hostile",
		"range_km": 600.0, "in_arc": true, "destroyed": false}
	if key == "raider_2":
		d["entity_id"] = "raider_2"
		d["track_id"] = "raider_2"
	return d

func _fire_opts() -> Dictionary:
	return {"target_entity": "raider_2", "actor_id": "player_ctrl",
		"controller_id": "player_ctrl", "domain_id": "player",
		"fleet_id": "own_fleet", "shooter_id": "own_ship"}

func _projectile_snapshot(s) -> Dictionary:
	var all: Array = s.combat_ballistics.projectiles_all()
	if all.is_empty() or not (all[0] is Dictionary):
		return {"exists": false, "count": all.size()}
	var p: Dictionary = all[0]
	return {"exists": true, "count": all.size(),
		"projectile_id": p.get("projectile_id", ""),
		"status": p.get("status", ""), "hit": p.get("hit", false),
		"pos_km": p.get("pos_km", []), "vel_kmps": p.get("vel_kmps", []),
		"closest_km": p.get("closest_km", null), "aim_km": p.get("aim_km", []),
		"applied_error_km": p.get("applied_error_km", null),
		"measurement_quality": p.get("measurement_quality", null),
		"quality_accuracy_mult": p.get("quality_accuracy_mult", null),
		"target_last_km": p.get("target_last_km", []),
		"launch_t": p.get("launch_t", null), "age_s": p.get("age_s", null)}

func _seed() -> Dictionary:
	return {
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
				"vel_kmps": [0.0, 0.0, 0.0]}],
		"sensor_service": {"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
				"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}}
	}
