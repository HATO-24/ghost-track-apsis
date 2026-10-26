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
	var valid = Tws.new()
	var positive: Dictionary = valid.import_state(good)
	var positive_step: Dictionary = valid.step(1.0, {"t": 1.0, "targets": []})
	var all_ok: bool = bool(positive.get("ok", false)) \
		and int(positive_step.get("channel_count", 0)) == 1
	print("R8_NULL_CONTROL ", JSON.stringify({"import": positive, "continued": positive_step.get("channel_count", 0)}))
	for field in ["history", "stare_s", "stare_required_s", "quality", "state_since_t"]:
		var tw = Tws.new()
		var before := JSON.stringify(tw.export_state())
		var state: Dictionary = good.duplicate(true)
		state.channels.broken[field] = null
		var validation = tw.validate_state(state)
		var imported = tw.import_state(state)
		var unchanged := before == JSON.stringify(tw.export_state())
		all_ok = all_ok and not bool(validation.get("ok", true)) \
			and not bool(imported.get("ok", true)) and unchanged
		rows.append({"field": field, "validation": validation, "import": imported,
			"unchanged": unchanged})
		print("R8_NULL_PRESTEP ", JSON.stringify(rows[-1]))
		if field == "history" and bool(imported.get("ok", false)):
			var result = tw.step(1.0, {"t": 1.0, "targets": []})
			print("R8_NULL_POSTSTEP ", JSON.stringify(result))
	var result := {"head": "9d0f3b4380275b0a30fffb4a29fa5c44ef58165f",
		"positive_import": positive, "positive_continued_channel_count": positive_step.get("channel_count", 0),
		"cases": rows, "all_ok": all_ok}
	FileAccess.open(OS.get_environment("R8_NULL_OUT"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	quit(0 if all_ok else 1)
