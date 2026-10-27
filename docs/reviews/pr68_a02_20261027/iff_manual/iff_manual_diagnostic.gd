extends SceneTree
const GS = preload("res://scripts/core/game_session.gd")

func _initialize() -> void:
	var out := {}
	var seed := _seed()
	var s = GS.new(seed)
	out["init"] = {"identity_enabled": s.identity_enabled(), "owners": s.authority_intel.owner_ids() if s.authority_intel.has_method("owner_ids") else []}
	# Minimal identity evidence creates an existing assessment before the IFF query.
	var e := s.identity_ingest("player_intel", {"target_id":"harmattan", "source":"optical", "identity":"hostile", "confidence":0.95})
	var before := s.identity_operational("player_intel", "harmattan")
	var q := s.identity_iff_query("player_intel", "harmattan", {"mode":"mode_s", "range_km":10.0})
	var after := s.identity_operational("player_intel", "harmattan")
	out["iff_conflict_overwrite"] = {"ingest":e, "before":{"identity":before.get("identity"), "state":before.get("state"), "sources":before.get("sources")}, "query":q, "after":{"identity":after.get("identity"), "state":after.get("state"), "iff_state":after.get("identity_iff_state"), "sources":after.get("sources")}}
	# Supplied authority/operator strings must be treated as untrusted; revoke also needs actor checks.
	var s2 = GS.new(seed)
	s2.identity_ingest("player_intel", {"target_id":"harmattan", "source":"optical", "identity":"neutral", "confidence":0.6})
	var forged := s2.identity_manual_confirm("ally_intel", "harmattan", "friend", {"authority":"command", "operator":"untrusted-caller"})
	var revoke := s2.identity_manual_clear("ally_intel", "harmattan")
	out["manual_self_auth_and_cross_owner"] = {"confirm":forged, "clear_without_actor":revoke, "audit":s2.authority_intel.identity_audit, "player":s2.identity_operational("player_intel","harmattan"), "ally":s2.identity_operational("ally_intel","harmattan")}
	# Compare actually occluded vs jam + occlusion; the transponder reports its first rejection reason.
	var s3 = GS.new(seed)
	var occluded := s3.identity_iff_query("player_intel", "harmattan", {"mode":"mode_s", "range_km":10.0, "occluded":true})
	var jam_and_occluded := s3.identity_iff_query("player_intel", "harmattan", {"mode":"mode_s", "range_km":10.0, "occluded":true, "jam":0.95})
	out["iff_jam_attribution"] = {"occluded_only":occluded, "jam_and_occluded":jam_and_occluded}
	var path := "res://.test-results/sol-a02/iff_manual/results.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("IFF_MANUAL_DIAGNOSTIC: ", JSON.stringify(out))
	quit(0)

func _seed() -> Dictionary:
	return {
		"own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true,
		"command_domains":[
			{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","faction":"ueg","roe":"TIGHT","fleet_id":"own_fleet","authorized_actors":["player_ctrl"]},
			{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","faction":"ueg","roe":"DEFENSIVE","fleet_id":"ally_fleet","authorized_actors":["ally_ai"]},
			{"domain_id":"opfor","kind":"ai_hostile","controller_id":"opfor_ai","intel_owner_id":"opfor_intel","faction":"ocu","roe":"AGGRESSIVE","fleet_id":"enemy_fleet","authorized_actors":["opfor_ai"]}],
		"fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player","fleet_id":"own_fleet","role":"flag"},{"entity_instance_id":"ally_ship","domain_id":"ally","fleet_id":"ally_fleet","role":"picket"},{"entity_instance_id":"raider_2","domain_id":"opfor","fleet_id":"enemy_fleet","role":"raider"}],
		"own_fleet":[{"entity_instance_id":"own_ship"}],
		"identification_service":{"evidence_ttl_s":12.0,"decay_half_life_s":60.0,"auto":{"enabled":false}},
		"transponder_service":{"content_path":"res://framework/content/transponders_prologue.json"},
		"entities":[{"id":"own_ship","kind":"ship","pos_km":[321719.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"ally_ship","kind":"ship","pos_km":[321719.0,300.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"raider_2","kind":"ship","pos_km":[321719.0,600.0,0.0],"vel_kmps":[0.0,0.4,0.0]},{"id":"harmattan","kind":"ship","pos_km":[321719.0,900.0,0.0],"vel_kmps":[0.0,0.2,0.0]}]
	}

