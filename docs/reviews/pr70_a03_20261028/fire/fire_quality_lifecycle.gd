extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const DT := 1.0

func _initialize() -> void:
	var out := {
		"purpose": "Real Session/CombatService quality lifecycle diagnostic; no formal probe or production edits.",
		"head": "6bd919aa19898bbf31f5dd7c3287befc47392877",
		"weapon": "missile",
		"cases": []}
	(out["cases"] as Array).append(_quality_drop_case("T0001"))
	(out["cases"] as Array).append(_quality_drop_case("raider_2"))
	(out["cases"] as Array).append(_quality_drop_case("T0001", 2))
	(out["cases"] as Array).append(_quality_recovery_case("raider_2"))
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/fire/results.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write diagnostic result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("A03_FIRE_QUALITY_RESULT: ", JSON.stringify(out))
	quit(0)

func _quality_drop_case(target_key: String, pre_solution_ticks := 0) -> Dictionary:
	var s = GS.new(_seed())
	for i in range(2):
		s.tick(DT)
	var initial_mq: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var reg := _register_track(s, target_key)
	var grant: Dictionary = s.grant_authorization("FIRE", "target", target_key, 90.0)
	var effect: Dictionary = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 1.0, "duration_s": 60.0, "source_id": "DIAG-FIRE-DROP"})
	for i0 in range(pre_solution_ticks):
		s.tick(DT)
	var initial_request: Dictionary = s.combat_request_solution(target_key, "missile", true)
	var initial_solution: Dictionary = initial_request.get("solution", {}) if initial_request.get("solution") is Dictionary else {}
	var sid := String(initial_solution.get("solution_id", ""))
	var timeline: Array = []
	var low_mq: Dictionary = {}
	var ticks_to_low := 0
	for i2 in range(16):
		s.tick(DT)
		ticks_to_low += 1
		var q: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
		var row := {"t": s.now_s(), "owner_quality": q.get("measurement_quality", null),
			"observed_t": q.get("measurement_t", null),
			"combat_quality_alias": _combat_quality(s, target_key),
			"solution_status": String(s.combat_service.solution_status(sid).get("status", ""))}
		timeline.append(row)
		if bool(q.get("ok", false)) and float(q.get("measurement_quality", 1.0)) < 0.5:
			low_mq = q
			break
	var computing_before: Dictionary = s.combat_service.solution_status(sid)
	var retry_while_low: Dictionary = s.combat_request_solution(target_key, "missile", true)
	var after_retry_status: Dictionary = s.combat_service.solution_status(sid)
	var ready_ticks := 0
	while String(s.combat_service.solution_status(sid).get("status", "")) == "COMPUTING" and ready_ticks < 20:
		s.tick(DT)
		ready_ticks += 1
	var ready: Dictionary = s.combat_service.solution_status(sid)
	var ammo_before := _ammo(s)
	var projectiles_before := _projectiles(s)
	var fire := s.request_fire(target_key, "missile", true, _fire_opts())
	var ammo_after := _ammo(s)
	var projectiles_after := _projectiles(s)
	return {"case": "quality_drops_below_floor_during_solution",
		"target_key": target_key, "hud_alias_shape": target_key == "T0001",
		"pre_solution_ticks_after_jam": pre_solution_ticks,
		"sensor_track_map": s._sensor_track_map.duplicate(true),
		"owner_track_ids": _owner_track_ids(s),
		"combat_track_before": reg.get("track", {}),
		"initial_measurement": initial_mq,
		"fire_grant": grant, "initial_solution_request": initial_request,
		"initial_solution": initial_solution, "jam_apply": effect,
		"ticks_until_low": ticks_to_low, "low_measurement": low_mq,
		"timeline": timeline, "computing_solution_after_low": computing_before,
		"request_solution_again_while_low": retry_while_low,
		"original_solution_after_retry": after_retry_status,
		"ticks_until_ready": ready_ticks, "ready_solution": ready,
		"fire_context": _fire_opts(), "request_fire": fire,
		"ammo_before": ammo_before, "ammo_after": ammo_after,
		"projectiles_before": projectiles_before,
		"projectiles_after": projectiles_after,
		"combat_track_after_fire": s.combat_service.track(target_key),
		"fire_audit_tail": (s.fire_audit() as Array).slice(maxi(0, s.fire_audit().size() - 2), s.fire_audit().size())}

func _quality_recovery_case(target_key: String) -> Dictionary:
	var s = GS.new(_seed())
	for i in range(2):
		s.tick(DT)
	var initial := s.owner_measurement_quality("player_intel", "raider_2")
	var reg := _register_track(s, target_key)
	var grant: Dictionary = s.grant_authorization("FIRE", "target", target_key, 90.0)
	var jam: Dictionary = s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.2, "duration_s": 10.0, "source_id": "DIAG-FIRE-RECOVER"})
	var timeline: Array = []
	var low: Dictionary = {}
	for i2 in range(12):
		s.tick(DT)
		var q: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
		timeline.append({"t": s.now_s(), "quality": q.get("measurement_quality", null),
			"measurement_t": q.get("measurement_t", null),
			"queue": (s.ew_delivery_queue() as Array).size()})
		if bool(q.get("ok", false)) and float(q.get("measurement_quality", 1.0)) < 0.9:
			low = q
			break
	var request: Dictionary = s.combat_request_solution(target_key, "missile", true)
	var solution: Dictionary = request.get("solution", {}) if request.get("solution") is Dictionary else {}
	var sid := String(solution.get("solution_id", ""))
	var recovery_ticks := 0
	var recovered: Dictionary = {}
	while recovery_ticks < 30:
		s.tick(DT)
		recovery_ticks += 1
		var q2: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
		var st := String(s.combat_service.solution_status(sid).get("status", ""))
		timeline.append({"t": s.now_s(), "quality": q2.get("measurement_quality", null),
			"measurement_t": q2.get("measurement_t", null),
			"solution_status": st})
		if bool(q2.get("ok", false)) and float(q2.get("measurement_quality", 0.0)) >= 0.9:
			recovered = q2
		if st == "READY" and not recovered.is_empty():
			break
	var ready: Dictionary = s.combat_service.solution_status(sid)
	var ammo_before := _ammo(s)
	var projectiles_before := _projectiles(s)
	var fire := s.request_fire(target_key, "missile", true, _fire_opts())
	return {"case": "solution_started_at_moderate_quality_then_measurement_recovers",
		"target_key": target_key, "initial_measurement": initial,
		"combat_track_before": reg.get("track", {}),
		"fire_grant": grant, "jam_apply": jam,
		"first_degraded_measurement": low, "solution_request": request,
		"solution_at_creation": solution, "timeline": timeline,
		"ticks_until_recovery_and_ready": recovery_ticks,
		"recovered_measurement": recovered, "ready_solution": ready,
		"current_combat_track_before_fire": s.combat_service.track(target_key),
		"request_fire": fire, "ammo_before": ammo_before,
		"ammo_after": _ammo(s), "projectiles_before": projectiles_before,
		"projectiles_after": _projectiles(s)}

func _register_track(s, key: String) -> Dictionary:
	var data := {"batch": key, "identity": "hostile", "threat": "hostile",
		"range_km": 500.0, "in_arc": true, "destroyed": false}
	if key != "T0001":
		data["entity_id"] = "raider_2"
		data["track_id"] = "raider_2"
	return s.combat_register_track(key, data)

func _fire_opts() -> Dictionary:
	return {"target_entity": "raider_2", "actor_id": "player_ctrl",
		"controller_id": "player_ctrl", "domain_id": "player",
		"fleet_id": "own_fleet", "shooter_id": "own_ship"}

func _combat_quality(s, key: String) -> Variant:
	var tr: Dictionary = s.combat_service.track(key)
	return tr.get("measurement_quality", null)

func _owner_track_ids(s) -> Array:
	var ids: Array = []
	for raw in (s.intel_view("player_intel").get("tracks", []) as Array):
		if raw is Dictionary:
			ids.append(String((raw as Dictionary).get("id", "")))
	return ids

func _ammo(s) -> int:
	var w: Dictionary = s.combat_service.weapons.get("missile", {})
	return int(w.get("ammo", -1))

func _projectiles(s) -> Array:
	return s.combat_ballistics.projectiles_all()

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
				"fleet_id": "ally_fleet", "authorized_actors": ["ally_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player", "fleet_id": "own_fleet", "role": "flag"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally", "fleet_id": "ally_fleet", "role": "picket"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}],
		"ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
		"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [321719.0, 300.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship", "pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]}],
		"sensor_service": {"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
				"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}}}
