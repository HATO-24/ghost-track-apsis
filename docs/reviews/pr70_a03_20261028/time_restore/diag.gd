extends "res://tests/jc_ew_observation_probe.gd"

const OUT := "C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/time_restore/result.json"
const SAVE := "user://jc_a03_time_restore_diag_20261028.json"
const OLD_SAVE := "user://jc_a03_old_archive_diag_20261028.json"
const EW_KEYS := ["ew_observation_samples", "ew_observation_queue",
	"ew_delivered_observations", "ew_candidates", "ew_observation_seq",
	"ew_quality_history", "ew_combat_quality"]

func _run() -> void:
	var report := {"head": "6bd919aa19898bbf31f5dd7c3287befc47392877", "cases": {}}

	# Natural sensor observations under an active EW effect; save while the real queue is in flight.
	var src = _new()
	var effect: Dictionary = src.apply_ew({"effect": "noise_jam",
		"target_id": "raider_2", "severity": 0.5, "duration_s": 120.0,
		"source_id": "TIME-DIAG-EW", "band": "radar"})
	for i in range(2):
		src.tick(TICK_DT)
	_register_combat_track(src, "raider_2")
	var queue_before: Array = src.ew_delivery_queue()
	var save_text: String = src.save_state()
	var sf := FileAccess.open(SAVE, FileAccess.WRITE)
	if sf == null:
		push_error("Could not open in-flight save file " + SAVE)
		quit(2)
		return
	sf.store_string(save_text)
	sf.close()
	var disk_text := FileAccess.get_file_as_string(SAVE)
	var dst = _new()
	var load_result: Dictionary = dst.load_state(disk_text)
	var queue_loaded: Array = dst.ew_delivery_queue()
	var queue_initial_equal := queue_before == queue_loaded
	var solution_id := ""
	var solution_request_source: Dictionary = {}
	var solution_request_restored: Dictionary = {}
	var src_trace: Array = []
	var dst_trace: Array = []
	var per_tick_equal: Array[bool] = []
	var delivered_time_checks: Array = []
	var solution_requested_at := -1.0
	for n in range(10):
		src.tick(TICK_DT)
		dst.tick(TICK_DT)
		var mq_src: Dictionary = src.owner_measurement_quality("player_intel", "raider_2")
		var mq_dst: Dictionary = dst.owner_measurement_quality("player_intel", "raider_2")
		# Invoke the actual solution API once after an owner measurement has arrived.
		if solution_id == "" and bool(mq_src.get("ok", false)) and bool(mq_dst.get("ok", false)):
			solution_request_source = src.combat_request_solution("raider_2", "missile", true)
			solution_request_restored = dst.combat_request_solution("raider_2", "missile", true)
			var sol: Dictionary = solution_request_source.get("solution", {}) \
				if solution_request_source.get("solution") is Dictionary else {}
			solution_id = String(sol.get("solution_id", ""))
			solution_requested_at = float(src.now_s())
		var snap_src := _snapshot(src, solution_id)
		var snap_dst := _snapshot(dst, solution_id)
		src_trace.append(snap_src)
		dst_trace.append(snap_dst)
		per_tick_equal.append(snap_src == snap_dst)
		for d in (src.ew_delivered_observations() as Array):
			if d is Dictionary and String((d as Dictionary).get("target_id", "")) == "raider_2":
				var row: Dictionary = d
				delivered_time_checks.append({"observation_id": row.get("observation_id", ""),
					"observed_t": row.get("observed_t", -1.0),
					"received_t": row.get("received_t", -1.0), "delay_s": row.get("delay_s", -1.0),
					"received_not_before_observed": float(row.get("received_t", -1.0)) + TIME_TOL >= float(row.get("observed_t", 0.0)),
					"elapsed_matches_delay": absf((float(row.get("received_t", 0.0)) - float(row.get("observed_t", 0.0))) - float(row.get("delay_s", 0.0))) <= TIME_TOL})
	var save_removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK
	var cases := {"effect": effect, "queue_before_save": queue_before,
		"queue_loaded_from_real_file": queue_loaded, "load": load_result,
		"queue_initial_equal": queue_initial_equal, "solution_id": solution_id,
		"solution_requested_at": solution_requested_at,
		"solution_request_source": solution_request_source,
		"solution_request_restored": solution_request_restored,
		"save_file_removed_after_load": save_removed,
		"source_trace": src_trace, "restored_trace": dst_trace,
		"per_tick_equal": per_tick_equal, "all_ticks_equal": _all_true(per_tick_equal),
		"delivered_time_checks": delivered_time_checks,
		"remaining_queue_source": src.ew_delivery_queue(),
		"remaining_queue_restored": dst.ew_delivery_queue()}
	report["cases"]["natural_inflight_file_10tick"] = cases

	# Compatibility fixture: real serialized session with only post-A03 EW sections removed.
	# Existing ew_service state remains; missing appended queue/history fields should default empty.
	var legacy_src = _new()
	legacy_src.tick(TICK_DT)
	var legacy_obj: Variant = JSON.parse_string(legacy_src.save_state())
	var stripped: Dictionary = legacy_obj if legacy_obj is Dictionary else {}
	var removed_keys: Array = []
	for key in EW_KEYS:
		if stripped.has(key):
			stripped.erase(key)
			removed_keys.append(key)
	var old_text := JSON.stringify(stripped)
	var old_file := FileAccess.open(OLD_SAVE, FileAccess.WRITE)
	if old_file == null:
		push_error("Could not open legacy save file " + OLD_SAVE)
		quit(2)
		return
	old_file.store_string(old_text)
	old_file.close()
	var legacy_dst = _new()
	var legacy_load: Dictionary = legacy_dst.load_state(FileAccess.get_file_as_string(OLD_SAVE))
	legacy_dst.tick(TICK_DT)
	var legacy_after := {"queue": legacy_dst.ew_delivery_queue(),
		"samples_count": (legacy_dst.ew_observation_samples() as Array).size(),
		"delivered_count": (legacy_dst.ew_delivered_observations() as Array).size(),
		"candidates_count": (legacy_dst.ew_candidate_evidence("player_intel") as Array).size(),
		"seq": legacy_dst._ew_obs_seq,
		"quality_history": legacy_dst._ew_quality_history,
		"combat_quality": legacy_dst._ew_combat_quality}
	var old_removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_SAVE)) == OK
	report["cases"]["archive_without_a03_sections"] = {"load": legacy_load,
		"removed_ew_sections": removed_keys, "after_one_tick": legacy_after,
		"file_removed_after_load": old_removed}

	var of := FileAccess.open(OUT, FileAccess.WRITE)
	if of == null:
		push_error("Could not open diagnostic report " + OUT)
		quit(2)
		return
	of.store_string(JSON.stringify(report, "\t"))
	of.close()
	print("JC-A03 TIME/RESTORE DIAGNOSTIC report=", OUT)
	print(JSON.stringify({"load_ok": load_result.get("ok", false),
		"queue_equal": queue_initial_equal, "queue_ids": _ids(queue_before),
		"all_ticks_equal": _all_true(per_tick_equal), "tick_equal": per_tick_equal,
		"delivered_time_checks": delivered_time_checks,
		"solution_id": solution_id, "solution_source": solution_request_source,
		"solution_restored": solution_request_restored,
		"legacy_load_ok": legacy_load.get("ok", false),
		"legacy_removed_sections": removed_keys, "legacy_after": legacy_after,
		"report": OUT}))
	quit(0)


func _snapshot(s, solution_id: String) -> Dictionary:
	var samples: Array = []
	for raw in s.ew_observation_samples():
		if raw is Dictionary and String((raw as Dictionary).get("target_id", "")) == "raider_2":
			samples.append((raw as Dictionary).duplicate(true))
	var sensor_observations: Array = []
	if s.sensor_service != null:
		for raw_obs in s.sensor_service.observations:
			if raw_obs is Dictionary and String((raw_obs as Dictionary).get("target_id", "")) == "raider_2":
				sensor_observations.append((raw_obs as Dictionary).duplicate(true))
	var visible := _view_track(s, "player_intel", "raider_2")
	var mq: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var combat_track: Dictionary = s.combat_service.track("raider_2") \
		if s.combat_service != null else {}
	var solution: Dictionary = s.combat_service.solution_status(solution_id) \
		if s.combat_service != null and solution_id != "" else {}
	return {"t": s.now_s(), "queue": s.ew_delivery_queue(),
		"samples": samples, "sensor_capture_geometry": sensor_observations,
		"delivered": s.ew_delivered_observations(), "owner_visible_track": visible,
		"owner_measurement": mq, "combat_track": combat_track,
		"solution": solution,
		"solution_status_rows": s.combat_service.solutions.duplicate(true) \
			if s.combat_service != null else {}}


func _ids(rows: Array) -> Array:
	var ids: Array = []
	for raw in rows:
		if raw is Dictionary:
			ids.append((raw as Dictionary).get("observation_id", ""))
	return ids


func _all_true(rows: Array) -> bool:
	for raw in rows:
		if not bool(raw):
			return false
	return true
