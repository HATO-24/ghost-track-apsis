extends SceneTree
const GS = preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
	var s = GS.new()
	var loaded = s.load_state(FileAccess.get_file_as_string(OS.get_environment("SOL_A01_BASELINE_SAVE")))
	var out = {"candidate":"1d1e8399da438b77b74acee40d753711c8d2a8f9", "load":loaded, "global_tracks":s.track_table.all_tracks(), "player_view":s.intel_view("player_intel"), "ally_view":s.intel_view("ally_intel")}
	print("BASELINE_IMPORT ", JSON.stringify(out))
	var file = FileAccess.open(OS.get_environment("SOL_A01_BASELINE_RESULT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	var lost = s.track_table.all_tracks().size() == 1 and s.intel_view("player_intel").tracks.is_empty()
	quit(1 if lost else 0)
