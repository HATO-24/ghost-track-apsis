extends SceneTree
const GS = preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
	var s = GS.new({"own_entity":"own_ship", "track_table":true, "entities":[{"id":"own_ship", "kind":"ship", "pos_km":[321719.0,0.0,0.0]}]})
	s.tick(1.0)
	s.track_table.handle_observation({"track_id":"legacy_enemy", "sensor":"radar", "t":1.0, "range_km":123.0, "bearing_deg":45.0}, s.track_table.current_writer())
	var text = s.save_state()
	var file = FileAccess.open(OS.get_environment("SOL_A01_BASELINE_SAVE"), FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var check = GS.new()
	var loaded = check.load_state(text)
	var out = {"producer":"9d0f3b4380275b0a30fffb4a29fa5c44ef58165f", "game_subtree_matches_main_3045311":true, "source_ready":s.ready, "source_load":loaded, "source_tracks":check.track_table.all_tracks(), "has_authority_section":JSON.parse_string(text).has("authority_intel")}
	print("BASELINE_EXPORT ", JSON.stringify(out))
	quit(0 if loaded.ok and check.track_table.all_tracks().size() == 1 else 1)
