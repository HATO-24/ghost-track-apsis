extends SceneTree
const Session = preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
	var text = FileAccess.get_file_as_string(OS.get_environment("R6_LEGACY_OUT"))
	var s = Session.new()
	var result = s.load_state(text)
	print("R6_LEGACY_IMPORT ", JSON.stringify({"target_head": "5d7208b82ebae81da874e059c2d88286317c6483",
		"ok": result.get("ok", false), "errors": result.get("errors", []),
		"sensor_restore": result.get("sensor_restore", {}),
		"migration": s._migration_report if s.get("_migration_report") != null else {}}))
	quit(0 if bool(result.get("ok", false)) else 1)
