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
	var row = {"target_head": "2ae7bf7cba8af32ff4456cefe28efa3650b868dd",
		"public_load_result": result, "public_sensor_report": s.sensor_restore_report(),
		"direct_sensor_import": direct}
	print("R7_LEGACY_PARTIAL ", JSON.stringify(row))
	FileAccess.open(OS.get_environment("R7_LEGACY_RESULT"), FileAccess.WRITE).store_string(JSON.stringify(row, "\t"))
	quit(0)
