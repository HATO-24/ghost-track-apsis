extends SceneTree
const GS = preload("res://scripts/core/game_session.gd")
const OUT = "C:/Users/ASUS/.codex/worktrees/jc-a01-validation/GHOST TRACK_APSIS/.test-results/sol-a01/save"
func _initialize():
	var cfg = {"own_entity":"own_ship", "track_table":true,
		"command_domains":[
			{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","authorized_actors":["player_ctrl"]},
			{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","authorized_actors":["ally_ai"]},
			{"domain_id":"opfor","kind":"ai_hostile","controller_id":"opfor_ai","intel_owner_id":"opfor_intel","authorized_actors":["opfor_ai"]}],
		"fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player"},{"entity_instance_id":"ally_ship","domain_id":"ally"},{"entity_instance_id":"enemy_ship","domain_id":"opfor"}],
		"entities":[{"id":"own_ship","kind":"ship","pos_km":[321719.0,0.0,0.0]},{"id":"ally_ship","kind":"ship","pos_km":[321719.0,300.0,0.0]},{"id":"enemy_ship","kind":"ship","pos_km":[321719.0,800.0,0.0]}]}
	var s = GS.new(cfg)
	print("READY=", s.ready, " ERR=", s.errors)
	for i in range(6): s.tick(1.0)
	s.receive_intel_observation("player_intel", {"observation_id":"P1","observer_id":"own_ship","target_id":"P-T","observed_t":6.0,"received_t":6.0,"delay_s":0.0,"path":"direct","quality":0.7,"source":"radar","pos_km":[1.0,2.0,3.0]})
	s.receive_intel_observation("ally_intel", {"observation_id":"A1","observer_id":"ally_ship","target_id":"A-T","observed_t":6.0,"received_t":16.0,"delay_s":10.0,"path":"direct","quality":0.5,"source":"optical","pos_km":[4.0,5.0,6.0]})
	s.receive_intel_observation("opfor_intel", {"observation_id":"O1","observer_id":"enemy_ship","target_id":"O-T","observed_t":6.0,"received_t":8.0,"delay_s":2.0,"path":"direct","quality":0.4,"source":"radar","pos_km":[7.0,8.0,9.0]})
	print("LEGACY_TRACK_WRITE=", s.track_table.handle_observation({"track_id":"legacy_enemy","sensor":"radar","t":6.0,"range_km":1.0,"bearing_deg":90.0}, s.track_table.current_writer()))
	var text = s.save_state()
	var path = OUT + "/authority-roundtrip.json"
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text); f.flush(); f.close()
	var disk = FileAccess.get_file_as_string(path)
	print("FILE_BYTES=", disk.to_utf8_buffer().size(), " SAME_TEXT=", text == disk)
	var s2 = GS.new(cfg)
	var lr = s2.load_state(disk)
	print("LOAD=", lr)
	for owner in ["player_intel","ally_intel","opfor_intel"]:
		print("OWNER_PRE_", owner, "=", JSON.stringify(s.intel_view(owner)))
		print("OWNER_POST_", owner, "=", JSON.stringify(s2.intel_view(owner)))
	for i in range(10):
		s.tick(1.0); s2.tick(1.0)
	print("TIME=", s.now_s(), "/", s2.now_s())
	for owner in ["player_intel","ally_intel","opfor_intel"]:
		print("OWNER_10TICK_MATCH_", owner, "=", JSON.stringify(s.intel_view(owner)) == JSON.stringify(s2.intel_view(owner)))
	print("PRE_LEGACY_TRACKS=", JSON.stringify(s.track_table.all_tracks()))
	var data = JSON.parse_string(text)
	data.erase("authority_intel")
	var old_s = GS.new(cfg); var old_res = old_s.load_state(JSON.stringify(data))
	print("LEGACY_MISSING=", old_res, " OLD_TRACKS=", JSON.stringify(old_s.track_table.all_tracks()), " OWNER_PLAYER=", JSON.stringify(old_s.intel_view("player_intel")), " OWNER_ALLY=", JSON.stringify(old_s.intel_view("ally_intel")))
	var bad = JSON.parse_string(text)
	bad["authority_intel"] = "broken"
	var bad_s = GS.new(cfg); print("BAD_NONDICT=", bad_s.load_state(JSON.stringify(bad)))
	var badver = JSON.parse_string(text)
	badver["authority_intel"]["version"] = 999
	var badv_s = GS.new(cfg); print("BAD_VERSION=", badv_s.load_state(JSON.stringify(badver)))
	quit()

