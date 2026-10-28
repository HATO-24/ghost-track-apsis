extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
var result := {"head": "6bd919aa19898bbf31f5dd7c3287befc47392877", "cases": {}}
func _initialize() -> void:
	var s = _new()
	_ticks(s, 2)
	s.apply_ew(_effect())
	var captured: Dictionary = {}
	for i in range(8):
		s.tick(1.0)
		for raw in s.ew_delivery_queue():
			if raw is Dictionary and String(raw.get("target_id", "")) == "raider_2":
				captured = raw.duplicate(true)
				break
		if not captured.is_empty():
			break
	_ticks(s, 9)
	var natural := _brief(s)
	s.ew_service.expire()
	_ticks(s, 5)
	var recovered := _brief(s)
	if not captured.is_empty():
		s._deliver_ew_observation(captured)
	var after := _brief(s)
	var track_last: Array = s.track_table.events.slice(maxi(0, s.track_table.events.size() - 2))
	result.cases["exact_real_entry_replay"] = {"captured_real_entry": captured,
		"natural_before_expire": natural, "recovered_before_repeat": recovered,
		"after_exact_repeat": after, "last_track_events": track_last,
		"repeat_method": "_deliver_ew_observation(captured_real_entry) once after normal delivery/recovery"}
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a03/observation/replay_audit.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("REPLAY_AUDIT_JSON=" + out)
	print("CAPTURED_ID=", captured.get("observation_id", ""))
	print("BEFORE_MEASUREMENT=", JSON.stringify(recovered.player_measurement))
	print("AFTER_MEASUREMENT=", JSON.stringify(after.player_measurement))
	print("OWNER_OBSERVATIONS=", recovered.player_observations.size(), "->", after.player_observations.size())
	print("DELIVERY_AUDIT=", recovered.delivered.size(), "->", after.delivered.size())
	print("TRACK_EVENTS=", JSON.stringify(track_last))
	quit(0 if not captured.is_empty() else 2)

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

func _brief(s) -> Dictionary:
	var pv: Dictionary = s.intel_view("player_intel")
	var av: Dictionary = s.intel_view("ally_intel")
	return {"ready": s.ready, "now": s.now_s(),
		"sensor_observer": s.sensor_service.observer.duplicate(true),
		"samples": s.ew_observation_samples(), "queue": s.ew_delivery_queue(),
		"delivered": s.ew_delivered_observations(),
		"player_measurement": s.owner_measurement_quality("player_intel", "raider_2"),
		"ally_measurement": s.owner_measurement_quality("ally_intel", "raider_2"),
		"player_observations": pv.get("observations", []),
		"ally_observations": av.get("observations", []),
		"global_track_vm": s.track_table.vm()}


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


