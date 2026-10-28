extends "res://tests/jc_ew_observation_probe.gd"

func _run() -> void:
	var source = _new()
	source.apply_ew({"effect":"noise_jam", "target_id":"raider_2", "severity":0.5, "duration_s":120.0, "source_id":"EW-SAVE-CONTROL"})
	for i in range(2):
		source.tick(1.0)
	var text := String(source.save_state())
	var saved: Dictionary = JSON.parse_string(text)
	var valid = _new()
	var good: Dictionary = valid.load_state(text)
	var bad_save: Dictionary = saved.duplicate(true)
	bad_save["ew_observation_queue"] = null
	var file_path := "user://sol_a03_present_null_queue.json"
	var disk = FileAccess.open(file_path, FileAccess.WRITE)
	disk.store_string(JSON.stringify(bad_save))
	disk.close()
	var broken = _new()
	var bad_result: Dictionary = broken.load_state(FileAccess.get_file_as_string(file_path))
	var legacy_save: Dictionary = saved.duplicate(true)
	for key in ["ew_observation_queue", "ew_observation_samples", "ew_delivered_observations", "ew_candidates", "ew_observation_seq", "ew_quality_history", "ew_combat_quality"]:
		legacy_save.erase(key)
	var legacy = _new()
	var old_result: Dictionary = legacy.load_state(JSON.stringify(legacy_save))
	var report := {"head":"6bd919aa19898bbf31f5dd7c3287befc47392877", "source_now":source.now_s(), "source_queue_count":source.ew_delivery_queue().size(), "valid_restore":good, "valid_queue_count":valid.ew_delivery_queue().size(), "present_null_restore":bad_result, "present_null_queue_count":broken.ew_delivery_queue().size(), "absent_legacy_restore":old_result, "absent_legacy_queue_count":legacy.ew_delivery_queue().size()}
	var out = FileAccess.open("C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/save_contract/result.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t"))
	out.close()
	print("SOL A03 SAVE CONTRACT DIAGNOSTIC COMPLETE")
	quit(0)
