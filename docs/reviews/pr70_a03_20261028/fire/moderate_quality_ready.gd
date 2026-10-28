extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const DT := 1.0

func _initialize() -> void:
	var result := {
		"purpose": "One bounded actual-Session comparison: sustained moderate EW quality at solver READY vs clean same-range control; no fire.",
		"head": "6bd919aa19898bbf31f5dd7c3287befc47392877",
		"range_km": 500.0,
		"clean": _run_case(false),
		"moderate_sustained": _run_case(true)}
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/fire/moderate_quality_ready.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write diagnostic result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("A03_MODERATE_READY_RESULT: ", JSON.stringify(result))
	quit(0)

func _run_case(jammed: bool) -> Dictionary:
	var s = GS.new(_seed())
	for i in range(2):
		s.tick(DT)
	var registration: Dictionary = s.combat_register_track("raider_2", {
		"batch": "raider_2", "entity_id": "raider_2", "track_id": "raider_2",
		"identity": "hostile", "threat": "hostile", "range_km": 500.0,
		"in_arc": true, "destroyed": false})
	var jam: Dictionary = {}
	if jammed:
		jam = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 60.0, "source_id": "DIAG-MODERATE-READY"})
	var quality_timeline: Array = []
	var accepted_q: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var ticks_before_solution := 0
	while jammed and ticks_before_solution < 20:
		s.tick(DT)
		ticks_before_solution += 1
		accepted_q = s.owner_measurement_quality("player_intel", "raider_2")
		quality_timeline.append({"t": s.now_s(), "quality": accepted_q.get("measurement_quality", null),
			"measurement_t": accepted_q.get("measurement_t", null)})
		var q := float(accepted_q.get("measurement_quality", 1.0))
		if bool(accepted_q.get("ok", false)) and q >= 0.5 and q < 0.9:
			break
	var request: Dictionary = s.combat_request_solution("raider_2", "missile", true)
	var solution0: Dictionary = request.get("solution", {}) if request.get("solution") is Dictionary else {}
	var sid := String(solution0.get("solution_id", ""))
	var solution_timeline: Array = []
	var ticks_to_ready := 0
	while ticks_to_ready < 25:
		var qnow: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
		var status: Dictionary = s.combat_service.solution_status(sid)
		solution_timeline.append({"t": s.now_s(), "owner_quality": qnow.get("measurement_quality", null),
			"owner_observed_t": qnow.get("measurement_t", null),
			"combat_track": s.combat_service.track("raider_2"), "status": status})
		if String(status.get("status", "")) == "READY":
			break
		s.tick(DT)
		ticks_to_ready += 1
	var final_q: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	return {"jammed": jammed, "jam_apply": jam, "registration": registration,
		"ticks_before_solution": ticks_before_solution, "current_measurement_at_creation": accepted_q,
		"quality_timeline": quality_timeline, "solution_request": request,
		"solution_at_creation": solution0, "ticks_to_ready": ticks_to_ready,
		"solution_at_ready": s.combat_service.solution_status(sid),
		"owner_measurement_at_ready": final_q,
		"combat_track_at_ready": s.combat_service.track("raider_2"),
		"solution_timeline": solution_timeline}

func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot", "track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]}],
		"fleet_instances": [{"entity_instance_id": "own_ship", "domain_id": "player", "fleet_id": "own_fleet", "role": "flag"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}], "ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0, "decay_half_life_s": 60.0,
			"auto": {"enabled": false}},
		"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship", "pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]}],
		"sensor_service": {"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
				"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}}}
