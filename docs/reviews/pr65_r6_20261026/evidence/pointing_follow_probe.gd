extends SceneTree
const Optical = preload("res://framework/sim/optical_ir_channel.gd")

func snap(degrees: float) -> Dictionary:
	var angle = deg_to_rad(degrees)
	var omega = deg_to_rad(0.003)
	return {"observer": {"id": "observer", "pos_km": [0.0, 0.0, 0.0],
		"vel_kmps": [0.0, 0.0, 0.0]},
		"targets": [{"id": "moving_target", "pos_km": [1000.0 * sin(angle),
			1000.0 * cos(angle), 0.0], "vel_kmps": [1000.0 * cos(angle) * omega,
				-1000.0 * sin(angle) * omega, 0.0],
			"temp_k": 300.0, "area_m2": 1000.0, "size_m": 50.0}], "los": true}

func _initialize() -> void:
	var original = Optical.new()
	original.start_channel("ir", "moving_target")
	for i in range(20):
		original.step(1.0, snap(45.0 - 0.003 * (19 - i)))
	var saved = original.export_state()
	var restored = Optical.new()
	var load = restored.import_state(saved)
	var rows = []
	var before = {"original": original.sensors.ir.duplicate(true),
		"restored": restored.sensors.ir.duplicate(true)}
	var first_divergent_tick = -1
	for i in range(1, 151):
		var input = snap(45.0 + 0.003 * i)
		original.step(1.0, input)
		restored.step(1.0, input)
		var a = original.channels["ir:moving_target"]
		var b = restored.channels["ir:moving_target"]
		if first_divergent_tick < 0 and a.status != b.status:
			first_divergent_tick = i
		if i <= 2 or i >= 120:
			rows.append({"tick": i, "original_status": a.status, "restored_status": b.status,
				"original_reason": a.reason, "restored_reason": b.reason,
				"original_boresight": original.sensors.ir.boresight_deg,
				"restored_boresight": restored.sensors.ir.boresight_deg})
	var result = {"head": "5d7208b82ebae81da874e059c2d88286317c6483",
		"load_ok": load.ok, "before": before, "rows": rows,
		"input_rate_deg_s": 0.003, "continued_ticks": 150,
		"first_divergent_tick": first_divergent_tick,
		"state_equal": original.export_state() == restored.export_state()}
	print("R5_POINTING_RESULT ", JSON.stringify(result))
	var file = FileAccess.open(OS.get_environment("R5_POINTING_OUT"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
	quit(0 if result.state_equal else 1)
