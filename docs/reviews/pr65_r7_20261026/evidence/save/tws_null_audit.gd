extends SceneTree

const Tws = preload("res://framework/sim/tws.gd")

func _initialize() -> void:
	var rows: Array = []
	var source = Tws.new()
	source.ingest([{"target_id": "broken", "detected": true, "quality": 1.0,
		"stable_track": true, "range_km": 10.0}], 0.0)
	var good: Dictionary = source.export_state()
	good.channels.broken.state = "STARE"
	good.channels.broken.quality = 1.0
	good.channels.broken.stare_s = 7.5
	good.channels.broken.stare_required_s = 8.0
	for field in ["history", "stare_s", "stare_required_s", "quality", "state_since_t"]:
		var tw = Tws.new()
		var state: Dictionary = good.duplicate(true)
		state.channels.broken[field] = null
		var validation = tw.validate_state(state)
		var imported = tw.import_state(state)
		rows.append({"field": field, "validation": validation, "import": imported})
		print("R7_NULL_PRESTEP ", JSON.stringify(rows[-1]))
		if field == "history" and bool(imported.get("ok", false)):
			var result = tw.step(1.0, {"t": 1.0, "targets": []})
			print("R7_NULL_POSTSTEP ", JSON.stringify(result))
	FileAccess.open(OS.get_environment("R7_NULL_OUT"), FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	quit(1 if bool(rows[0].validation.ok) else 0)
