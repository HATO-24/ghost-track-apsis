extends "res://tests/a0_save_cost_probe.gd"

# Review-only diagnostic. No production file is modified.
const OpticalIR := preload("res://framework/sim/optical_ir_channel.gd")
var review_hits = 0

func record65(name: String, data: Dictionary, defect := false) -> void:
	print("SOL65_", name, " ", JSON.stringify(data))
	if defect:
		review_hits += 1

func make65(n: int):
	var s = GameSessionScript.new(_seed)
	s.time.scale = 1.0
	s.time.paused = false
	var op_i = 0
	for i in range(n):
		s.tick(1.0)
		if (i + 1) % 50 == 0:
			_control_op(s, op_i)
			op_i += 1
	return s

func pointing65(sensors: Dictionary) -> Dictionary:
	var out = {}
	for k in sensors.keys():
		var row = {}
		for f in ["desired_target_id", "pointing_mode", "boresight_deg", "boresight_el_deg"]:
			row[f] = sensors[k].get(f)
		out[k] = row
	return out

func capture65(s) -> Dictionary:
	var a = s.sensor_service._authority
	var radar = a._tws.radar
	return {"session_t": s.now_s(), "authority_t": a.t,
		"optical_t": a._optical_ir.t,
		"pointing": pointing65(a._optical_ir.sensors),
		"channels": a._optical_ir.export_state().channels,
		"tws_t": a._tws.now_t, "radar": {"elapsed_s": radar.elapsed_s,
			"seconds_on": radar.seconds_on, "time_since_scan": radar.time_since_scan,
			"scan_index": radar.scan_index, "last_scan_t": radar.last_scan_t},
		"obs_seq": s.sensor_service._obs_seq}

func atomic65() -> void:
	for mode in ["invalid_authority_clock", "invalid_child_clock", "invalid_counters"]:
		var s = make65(5)
		s.sensor_service.start_channel("optical", "harmattan")
		var svc = s.sensor_service
		var state = svc.export_state()
		var before = svc._authority.export_backend_state()
		var input = state.duplicate(true)
		if mode == "invalid_authority_clock":
			input.backend.authority_t = -1.0
			input.backend.t = 77.0
			input.backend.channels[0].status = "lost"
		elif mode == "invalid_child_clock":
			input.backend.t = -1.0
			input.backend.authority_t = 99.0
		else:
			input.backend.authority_step_count = -3.5
			input.backend.authority_dt_last = -2.0
		var result = svc.import_state(input)
		var after = svc._authority.export_backend_state()
		var changed = JSON.stringify(before) != JSON.stringify(after)
		record65("ATOMIC", {"case": mode, "import_ok": result.get("ok"),
			"reason": result.get("reason", ""), "changed": changed,
			"before_child_t": before.t, "after_child_t": after.t,
			"before_authority_t": before.authority_t, "after_authority_t": after.authority_t,
			"after_step_count": after.authority_step_count,
			"after_dt_last": after.authority_dt_last},
			(bool(result.get("ok", false)) if mode == "invalid_counters" else changed))

func blind65() -> void:
	var o = make65(50)
	var r = GameSessionScript.new()
	var lr = r.load_state(o.save_state())
	var baseline = _full_state_violations(o, r)
	record65("COMPARATOR_CONTROL", {"load_ok": lr.ok, "violations": baseline})
	if not baseline.is_empty():
		return
	var old_id_seq = r.bus._id_seq
	r.bus._id_seq += 100
	var missed = _full_state_violations(o, r)
	record65("BLIND_ID_ALLOCATOR", {"original": o.bus._id_seq,
		"restored": r.bus._id_seq, "violations": missed}, missed.is_empty())
	r.bus._id_seq = old_id_seq
	var ev = r.bus.events[0].duplicate(true)
	r.bus.events[0].payload = {"review_marker": "changed payload with the same ID"}
	missed = _full_state_violations(o, r)
	record65("BLIND_EVENT_PAYLOAD", {"violations": missed}, missed.is_empty())
	r.bus.events[0] = ev
	if not r.sensor_service.observations.is_empty():
		var ob = r.sensor_service.observations[0].duplicate(true)
		r.sensor_service.observations[0].quality = 0.0 if float(ob.quality) > 0.0 else 1.0
		missed = _full_state_violations(o, r)
		record65("BLIND_OBSERVATION_PAYLOAD", {"original_quality": ob.quality,
			"restored_quality": r.sensor_service.observations[0].quality,
			"violations": missed}, missed.is_empty())
		r.sensor_service.observations[0] = ob
	if not r.comms.pending.is_empty():
		r.comms.pending[0].text = "TAMPERED_DELIVERY_CONTENT"
		missed = _full_state_violations(o, r)
		var behavior = _behavior_violations(o, r, 10)
		var after = _full_state_violations(o, r)
		record65("BLIND_COMMS_CONTENT", {"state_violations": missed,
			"behavior_violations": behavior, "after_violations": after,
			"has_last_event_method": r.comms.has_method("last_event"),
			"restored_last_event": r.comms.events[-1] if not r.comms.events.is_empty() else {}},
			missed.is_empty() and behavior.is_empty() and after.is_empty())

func continuation65(n: int) -> void:
	record65("PROGRESS", {"stage": "construct", "ticks": n})
	var o = make65(n)
	record65("PROGRESS", {"stage": "save_load", "ticks": n})
	var r = GameSessionScript.new()
	var load = r.load_state(o.save_state())
	record65("PROGRESS", {"stage": "capture", "ticks": n})
	var pre_o = capture65(o)
	var pre_r = capture65(r)
	var base_bad = _full_state_violations(o, r)
	# Isolate optical pointing runtime from channel history using identical snapshots.
	var model_plain = OpticalIR.new({"sensors": r.sensor_service._authority._optical_ir.sensors})
	var model_pointing = OpticalIR.new({"sensors": r.sensor_service._authority._optical_ir.sensors})
	var saved_model = o.sensor_service._authority._optical_ir.export_state()
	model_plain.import_state(saved_model)
	model_pointing.import_state(saved_model)
	for k in model_pointing.sensors.keys():
		for f in ["desired_target_id", "pointing_mode", "boresight_deg", "boresight_el_deg"]:
			model_pointing.sensors[k][f] = o.sensor_service._authority._optical_ir.sensors[k][f]
	var timeline = []
	for i in range(10):
		o.tick(1.0)
		r.tick(1.0)
		var snap_o = o.sensor_service._build_snapshot()
		var snap_r = r.sensor_service._build_snapshot()
		model_plain.step(1.0, snap_o)
		model_pointing.step(1.0, snap_o)
		timeline.append({"tick": i + 1, "snapshot_equal": snap_o == snap_r,
			"original_obs_seq": o.sensor_service._obs_seq, "restored_obs_seq": r.sensor_service._obs_seq,
			"original_scan_phase": o.sensor_service._authority._tws.radar.time_since_scan,
			"restored_scan_phase": r.sensor_service._authority._tws.radar.time_since_scan})
	var after = _full_state_violations(o, r)
	record65("CONTINUATION", {"ticks": n, "load_ok": load.ok,
		"initial_violations": base_bad, "original_before": pre_o, "restored_before": pre_r,
		"timeline": timeline, "original_after": capture65(o), "restored_after": capture65(r),
		"violations": after}, not after.is_empty())
	record65("POINTING_ISOLATION", {"ticks": n,
		"plain_channels": model_plain.export_state().channels,
		"pointing_only_restored_channels": model_pointing.export_state().channels,
		"reference_channels": o.sensor_service._authority._optical_ir.export_state().channels})

func _run() -> void:
	var err = change_scene_to_file(MAIN_MENU)
	if err != OK:
		quit(2)
		return
	var boot = await _await_v1_hud()
	if boot.hud == null:
		quit(2)
		return
	_seed = boot.hud.get("binder").get("session")._seed.duplicate(true)
	record65("PROVENANCE", {"head": OS.get_environment("A07_HEAD"),
		"scenario_sha256": FileAccess.get_file_as_string(TARGET_SCENARIO).sha256_text(),
		"seed_sha256": JSON.stringify(_seed).sha256_text()})
	var mode = OS.get_environment("SOL65_MODE")
	if mode.is_valid_int() and int(mode) > 0:
		continuation65(int(mode))
	else:
		atomic65()
		blind65()
	_finished = true
	_restore_env()
	print("SOL65_RESULT review_defects=", review_hits)
	quit(1 if review_hits > 0 else 0)
