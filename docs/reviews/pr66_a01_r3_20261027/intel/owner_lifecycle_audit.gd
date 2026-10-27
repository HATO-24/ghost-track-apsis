extends "res://tests/jc_authority_intel_probe.gd"

func owner_row(s, tid: String) -> Dictionary:
	for raw in s.intel_view("player_intel").tracks:
		if String(raw.get("id", "")) == tid:
			return raw.duplicate(true)
	return {}

func global_row(s, eid: String) -> Dictionary:
	for raw in s.track_vm({}).get("tracks", []):
		if String(raw.get("entity_id", "")) == eid:
			return raw.duplicate(true)
	return {}

func _run() -> void:
	var result: Dictionary = {"head": "8b4cf990021bafe0f5b2945039c850b5c985cf5a"}
	# Reuse the old legitimate ally sensor route, without writing player intel.
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
	var foreign_track = b.selected_track({"track_id": "T0001"})
	var foreign_entity = b.selected_entity({"track_id": "T0001", "entity_id": "ally_private_contact"})
	var local = {"observation_id": "LOCAL", "observer_id": "own_ship",
		"target_id": "local_contact", "sensor": "radar", "source": "radar",
		"observed_t": 0.0, "quality": 0.8, "range_km": 111.0, "bearing_deg": 11.0}
	var received = r.receive_intel_observation("player_intel", local)
	b.refresh()
	result["selected"] = {"route": route, "global_foreign_exists": not global_row(r, "ally_private_contact").is_empty(),
		"foreign_track": foreign_track, "foreign_entity": foreign_entity,
		"local_receive": received, "local_track": b.selected_track({"track_id": "local_contact"}),
		"local_entity": b.selected_entity({"track_id": "local_contact"}),
		"closed": foreign_track.is_empty() and foreign_entity.is_empty() \
			and not b.selected_track({"track_id": "local_contact"}).is_empty()}
	# Same one-shot local observation, no further sensor input, compared against
	# the already frozen TrackTable stale/forget policy in the same real Session.
	var cfg = _seed()
	cfg.erase("sensor_service")
	var s = GS.new(cfg)
	var aging = {"observation_id": "AGE-ONE", "observer_id": "own_ship",
		"target_id": "aging_contact", "sensor": "radar", "source": "radar",
		"observed_t": 0.0, "quality": 0.8, "range_km": 500.0, "bearing_deg": 30.0}
	var a1 = s.receive_intel_observation("player_intel", aging)
	var a2 = s.handle_observation({"event_id": "AGE-ONE", "entity_id": "aging_contact",
		"target_id": "aging_contact", "sensor": "radar", "support": 2,
		"quality": 0.8, "range_km": 500.0, "bearing_deg": 30.0, "t": 0.0})
	var timeline: Array = [{"t": s.now_s(), "owner": owner_row(s, "aging_contact"), "global": global_row(s, "aging_contact")}]
	var ticks: Array = []
	for dt in [31.0, 270.0]:
		var tr = s.tick(dt)
		ticks.append({"dt": dt, "ok": tr.get("ok", false), "reason": tr.get("reason", "")})
		timeline.append({"t": s.now_s(), "owner": owner_row(s, "aging_contact"), "global": global_row(s, "aging_contact")})
	result["lifecycle"] = {"ready": s.ready, "owner_input": a1, "global_control_input": a2,
		"stale_after_s": s.track_table.config.stale_after_s,
		"forget_after_s": s.track_table.config.forget_after_s,
		"ticks": ticks, "timeline": timeline,
		"owner_retained_after_forget": not owner_row(s, "aging_contact").is_empty(),
		"global_forgotten": global_row(s, "aging_contact").is_empty()}
	var f = FileAccess.open(OS.get_environment("A01_R3_OWNER_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	print("A01_R3_OWNER_RESULT ", JSON.stringify(result))
	_finished = true
	quit(0 if result.selected.closed else 1)
