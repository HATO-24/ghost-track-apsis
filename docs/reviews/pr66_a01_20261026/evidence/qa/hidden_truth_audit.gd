extends "res://tests/jc_authority_intel_probe.gd"

func _run() -> void:
	var s = GS.new(_seed())
	var phys_before = s.physics_state("enemy_ship").duplicate(true)
	var world_before = s.world.entity("enemy_ship").duplicate(true)
	var result = s._apply_hidden_truth_mutation("enemy_ship", "RENAMED_HIDDEN", [999.0, 0.0, 0.0])
	var phys_after = s.physics_state("enemy_ship").duplicate(true)
	var world_after = s.world.entity("enemy_ship").duplicate(true)
	var unchanged = JSON.stringify(phys_before) == JSON.stringify(phys_after) and JSON.stringify(world_before) == JSON.stringify(world_after)
	var out = {"candidate": "1d1e8399da438b77b74acee40d753711c8d2a8f9", "session_ready": s.ready, "hook": result, "physics_has_set_position": s.physics_world_service.has_method("set_position"), "physics_before": phys_before, "physics_after": phys_after, "world_before": world_before, "world_after": world_after, "actual_truth_unchanged": unchanged}
	print("HIDDEN_TRUTH_AUDIT ", JSON.stringify(out))
	var file = FileAccess.open(OS.get_environment("SOL_A01_QA_OUT"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out, "\t"))
		file.close()
	_finished = true
	quit(1 if unchanged else 0)
