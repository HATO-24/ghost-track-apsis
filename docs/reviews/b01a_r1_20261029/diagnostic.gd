extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
const SEL_A := [{"ship_id":"APSIS","slot":"command","instance_id":"apsis"},{"ship_id":"HARMATTAN","slot":"screen","instance_id":"harmattan"}]
func _seed(selection: Array, scenario := "A", extra := {}) -> Dictionary:
	var sd := {
		"own_entity": "apsis",
		"physics_world": {"auto_seed": true},
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"ship_catalog": {},
		"fleet_formation": {}, "fleet_refit": {},
		"entities": [
			{"id": "legacy_ship", "kind": "ship", "name": "legacy",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
		],
		"deployment": {
			"scenario_id": scenario,
			"deployment_seed": 424242,
			"selection": {"ships": selection.duplicate(true)},
		},
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "fleet_id": "own_fleet",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "fleet_id": "ally_fleet",
				"authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "fleet_id": "enemy_fleet",
				"authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "apsis", "domain_id": "player",
				"fleet_id": "own_fleet"}],
		"ew_service": {},
		"identification_service": {"auto": {"enabled": false}},
	}
	for key in extra.keys():
		sd[key] = extra[key]
	return sd


func _ids(s) -> Dictionary:
	var w: Array = s.world.entities.keys()
	var p: Array = s.physics_world_service.entity_ids()
	var c: Array = s.entity_metadata_ids()
	w.sort(); p.sort(); c.sort()
	return {"world":w,"physics":p,"catalog":c}

func _initialize() -> void:
	var out := {"head":"7185b92e83482b731ca7d15da7765ae41eda7c4c","scope":"Original #62 deployment contracts; one bounded reviewer diagnostic, not production/formal edits"}
	var normal = GS.new(_seed(SEL_A,"SAME"))
	out["legal_control"] = {"ready":normal.ready,"ids":_ids(normal),"vm":normal.fleet_deployment_vm(),"apsis_resources":normal.deployment_resources("apsis")}
	var explicit := _seed(SEL_A,"SAME")
	explicit["physics_world"] = {"auto_seed":true,"entities":(explicit["entities"] as Array).duplicate(true)}
	var ep = GS.new(explicit)
	out["explicit_physics_roster"] = {"ready":ep.ready,"ids":_ids(ep),"errors":ep.errors}
	var bad_selection: Array = SEL_A.duplicate(true)
	bad_selection[0]["controller_id"] = "unregistered_controller"
	bad_selection[0]["owner_id"] = "player_intel"
	bad_selection[0]["domain_id"] = "player"
	var bad = GS.new(_seed(bad_selection,"SAME"))
	out["unauthorized_controller"] = {"ready":bad.ready,"errors":bad.errors,"ids":_ids(bad),"resources":bad.deployment_resources("apsis"),"domains":bad.authority_intel.domains}
	var legacy_seed := {"physics_world":{"auto_seed":true},"seed_frame":"bary_rot","entities":[{"id":"old_ship","kind":"ship","name":"old","pos_km":[100.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]}]}
	var legacy = GS.new(legacy_seed)
	var legacy_path := ProjectSettings.globalize_path("res://../.test-results/sol-b01a/legacy-control.json")
	var file := FileAccess.open(legacy_path,FileAccess.WRITE)
	file.store_string(legacy.save_state());file.close()
	var loaded: Dictionary = normal.load_state(FileAccess.get_file_as_string(legacy_path))
	out["legacy_file_over_active_deployment"] = {"load":loaded,"ids":_ids(normal),"vm":normal.fleet_deployment_vm(),"apsis_resources":normal.deployment_resources("apsis"),"saved_deployment":JSON.parse_string(FileAccess.get_file_as_string(legacy_path)).get("deployment")}
	var intact = GS.new(_seed(SEL_A,"SAME"))
	var saved: Dictionary = intact.deployment_service.export_state()
	saved["resources"] = {}
	var restore: Dictionary = intact.deployment_service.load_state(saved)
	out["missing_instance_resources"] = {"restore":restore,"vm":intact.fleet_deployment_vm(),"resources":intact.deployment_resources("apsis")}
	var pos1 := _seed(SEL_A,"SAME")
	var pos2 := _seed(SEL_A,"SAME")
	pos1["deployment"]["positions"] = {"APSIS":{"pos_km":[100.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]}}
	pos2["deployment"]["positions"] = {"APSIS":{"pos_km":[200.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]}}
	var p1 = GS.new(pos1)
	var p2 = GS.new(pos2)
	out["geometry_revision"] = {"first":p1.deployment_service.committed(),"second":p2.deployment_service.committed()}
	var dest := ProjectSettings.globalize_path("res://../.test-results/sol-b01a/diagnostic.json")
	var f := FileAccess.open(dest,FileAccess.WRITE)
	f.store_string(JSON.stringify(out,"  "));f.close()
	print("SOL_B01A_DIAGNOSTIC_COMPLETE ",dest)
	quit(0)
