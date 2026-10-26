extends "res://tests/jc_authority_intel_probe.gd"

const Binder := preload("res://scripts/ui/shell_binder.gd")
var results: Dictionary = {}

func obs(id: String, observer: String, tid: String, observed: float, received: float, delay: float) -> Dictionary:
	return {"observation_id": id, "observer_id": observer, "target_id": tid,
		"sensor": "optical", "source": "optical", "path": "direct",
		"observed_t": observed, "received_t": received, "delay_s": delay,
		"quality": 0.8, "range_km": 900.0, "bearing_deg": 22.0}

func _run() -> void:
	var s = GS.new(_seed())
	results["valid_direct_control"] = s.receive_intel_observation("player_intel", obs("OWN-OK", "own_ship", "local_contact", 0.0, 0.0, 0.0))
	results["unknown_owner_control"] = s.receive_intel_observation("not_an_owner", obs("UNKNOWN-OWNER", "own_ship", "must_not_show", 0.0, 0.0, 0.0))
	var cross = s.receive_intel_observation("player_intel", obs("CROSS", "enemy_ship", "secret_enemy_contact", 0.0, 0.0, 0.0))
	results["cross_owner_direct"] = {"result": cross, "view": s.intel_view("player_intel")}
	var future = s.receive_intel_observation("ally_intel", obs("FUTURE", "ally_ship", "future_contact", 0.0, 30.0, 30.0))
	results["future_receipt"] = {"now_s": s.now_s(), "result": future, "view": s.intel_view("ally_intel")}
	var bad = s.receive_intel_observation("player_intel", obs("BADTIME", "own_ship", "bad_time_contact", 99.0, 1.0, -98.0))
	results["invalid_times"] = {"result": bad, "view": s.intel_view("player_intel")}
	var d = obs("DUP", "ally_ship", "duplicate_contact", 0.0, 0.0, 0.0)
	s.receive_intel_observation("ally_intel", d)
	var c0: int = s.intel_view("ally_intel").observations.size()
	s.receive_intel_observation("ally_intel", d)
	results["duplicate"] = {"before_observations": c0, "after_observations": s.intel_view("ally_intel").observations.size()}
	results["unknown_observer_owner"] = s.intel_owner_of("not_registered")
	# Feed an otherwise legitimate ally sensor output into the existing real routing
	# seam. Do not directly write TrackTable or player facade.
	var r = GS.new(_seed())
	var ev = {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": "ALLY-OBS-REAL-ROUTE", "observer_id": "ally_ship",
		"target_id": "ally_private_contact", "entity_id": "ally_private_contact",
		"batch": "ALLY-PRIVATE", "sensor": "optical", "support": 2,
		"quality": 0.8, "range_km": 456.0, "bearing_deg": 33.0, "t": 0.0}
	r.sensor_service._outbox.append(ev)
	var route = r._advance_sensors(0.0)
	var b = Binder.new()
	b.session = r
	b.refresh()
	var contacts: Array = []
	for row in b.contacts:
		if String(row.get("entity_id", "")) == "ally_private_contact":
			contacts.append(row.duplicate(true))
	results["ally_sensor_route"] = {"route": route,
		"player_owner_view": r.intel_view("player_intel"),
		"ally_owner_view": r.intel_view("ally_intel"),
		"global_tracks": r.track_vm({}), "player_binder_contacts": contacts}
	results["head"] = "1d1e8399da438b77b74acee40d753711c8d2a8f9"
	var f = FileAccess.open(OS.get_environment("A01_INTEL_BOUNDARY_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	print("A01_INTEL_BOUNDARY_RESULT ", JSON.stringify(results))
	_finished = true
	quit(0)
