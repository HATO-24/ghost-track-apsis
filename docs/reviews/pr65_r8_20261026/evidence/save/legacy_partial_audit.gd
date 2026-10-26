extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
	var text = FileAccess.get_file_as_string(OS.get_environment("R6_LEGACY_OUT"))
	var s = Session.new()
	var result = s.load_state(text)
	var obj: Dictionary = JSON.parse_string(text)
	var t = Session.new()
	t.load_state(text)
	var direct: Dictionary = t.sensor_service.import_state(obj.sensor_service)
	var full_session = Session.new()
	var full: Dictionary = full_session.load_state(s.save_state())
	var report: Dictionary = s.sensor_restore_report()
	var partial_ok: bool = String(result.get("sensor_restore_mode", "")) == "partial" \
		and String(report.get("restore_mode", "")) == "partial" \
		and bool(report.get("is_partial", false)) \
		and result.get("sensor_partial_reasons", []).size() > 0 \
		and JSON.stringify(result.get("sensor_partial_reasons", [])) \
			== JSON.stringify(direct.get("partial_reasons", []))
	var full_ok: bool = bool(full.get("ok", false)) \
		and String(full.get("sensor_restore_mode", "")) == "full" \
		and full.get("sensor_partial_reasons", []).is_empty() \
		and not bool(full.get("sensor_restore", {}).get("is_partial", true))
	var row = {"target_head": "9d0f3b4380275b0a30fffb4a29fa5c44ef58165f",
		"public_load_result": result, "public_sensor_report": s.sensor_restore_report(),
		"direct_sensor_import": direct, "full_resave_load": full,
		"partial_disclosed": partial_ok, "full_control": full_ok}
	print("R8_LEGACY_PARTIAL ", JSON.stringify(row))
	FileAccess.open(OS.get_environment("R8_LEGACY_RESULT"), FileAccess.WRITE).store_string(JSON.stringify(row, "\t"))
	quit(0 if partial_ok and full_ok else 1)
