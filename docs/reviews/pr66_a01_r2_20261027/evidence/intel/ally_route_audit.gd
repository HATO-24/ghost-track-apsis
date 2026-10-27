extends "res://tests/jc_authority_intel_probe.gd"

func _run() -> void:
	var s = GS.new(_seed())
	# The same legitimate ally sensor output used in the first review.
	var ev = {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": "ALLY-OBS-REAL-ROUTE", "observer_id": "ally_ship",
		"target_id": "ally_private_contact", "entity_id": "ally_private_contact",
		"batch": "ALLY-PRIVATE", "sensor": "optical", "support": 2,
		"quality": 0.8, "range_km": 456.0, "bearing_deg": 33.0, "t": 0.0}
	s.sensor_service._outbox.append(ev)
	var route = s._advance_sensors(0.0)
	var b = Binder.new()
	b.session = s
	b.refresh()
	var pv = s.intel_view("player_intel")
	var av = s.intel_view("ally_intel")
	var gv = s.track_vm({})
	var selected_leak: Dictionary = b.selected_track({"track_id": "T0001"})
	var results = {
		"head": "61f27fc8e841666705b5fd2e843824a03bf6c0b8",
		"route": route, "player_owner_view": pv, "ally_owner_view": av,
		"player_binder_contacts": b.contacts.duplicate(true),
		"contacts_closed": b.contacts.is_empty() and pv.tracks.is_empty(),
		"global_tracks": gv, "selected_track_for_global_only_id": selected_leak,
		"selected_still_global": not selected_leak.is_empty(),
		"exit_means": "diagnostic completed; contacts_closed proves narrow fix; global/selected remain unfinished",
	}
	var f = FileAccess.open(OS.get_environment("A01_R2_ALLY_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	print("A01_R2_ALLY_ROUTE_RESULT ", JSON.stringify(results))
	_finished = true
	quit(0 if results.contacts_closed else 1)
