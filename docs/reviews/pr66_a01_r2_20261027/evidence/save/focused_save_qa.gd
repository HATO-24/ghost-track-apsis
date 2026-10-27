extends SceneTree
const GS = preload("res://scripts/core/game_session.gd")
const LEGACY_PATH = "C:/Users/ASUS/.codex/worktrees/jc-a01-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a01-r2/save/baseline_pre_a01.json"
const OUT = "C:/Users/ASUS/.codex/worktrees/jc-a01-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a01-r2/save"
func _initialize():
	var legacy_text = FileAccess.get_file_as_string(LEGACY_PATH)
	var legacy_doc = JSON.parse_string(legacy_text)
	print("LEGACY_FILE_BYTES=", legacy_text.to_utf8_buffer().size(), " SCHEMA=", legacy_doc.get("schema", ""), " HAS_AUTHORITY=", legacy_doc.has("authority_intel"))
	var legacy_session = GS.new({})
	var legacy_result: Dictionary = legacy_session.load_state(legacy_text)
	print("LEGACY_LOAD=", JSON.stringify(legacy_result))
	print("LEGACY_REPORT=", JSON.stringify(legacy_session.authority_restore_report()))
	print("LEGACY_TRACK_COUNT=", legacy_session.track_table.all_tracks().size() if legacy_session.track_table != null else -1)
	print("LEGACY_PLAYER_COUNT=", legacy_session.intel_view("player_intel").get("tracks", []).size())
	print("LEGACY_ALLY_COUNT=", legacy_session.intel_view("ally_intel").get("tracks", []).size())
	print("LEGACY_OWNER_IDS=", JSON.stringify(legacy_session.intel_view("player_intel").get("tracks", []).map(func(x): return x.get("id", ""))))
	var seed = legacy_doc.get("seed", {})
	var fresh = GS.new(seed)
	print("FRESH_READY=", fresh.ready, " ERR=", JSON.stringify(fresh.errors))
	var fresh_text = fresh.save_state()
	print("FRESH_SAVE_BYTES=", fresh_text.to_utf8_buffer().size())
	var broken_doc = JSON.parse_string(fresh_text)
	broken_doc["authority_intel"] = "broken"
	var broken_session = GS.new(seed)
	var broken_result: Dictionary = broken_session.load_state(JSON.stringify(broken_doc))
	print("BROKEN_RESULT=", JSON.stringify(broken_result))
	print("BROKEN_REPORT=", JSON.stringify(broken_session.authority_restore_report()))
	var null_doc = JSON.parse_string(fresh_text)
	null_doc["authority_intel"] = null
	var null_session = GS.new(seed)
	var null_result: Dictionary = null_session.load_state(JSON.stringify(null_doc))
	print("NULL_PRESENT_RESULT=", JSON.stringify(null_result))
	print("NULL_PRESENT_REPORT=", JSON.stringify(null_session.authority_restore_report()))
	var version_doc = JSON.parse_string(fresh_text)
	version_doc["authority_intel"]["version"] = 999
	var version_session = GS.new(seed)
	print("BAD_VERSION_RESULT=", JSON.stringify(version_session.load_state(JSON.stringify(version_doc))))
	quit()
