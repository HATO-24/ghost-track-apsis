extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
const TICK := 1.0

func _initialize() -> void:
    var out := {"head":"5d372ea2df7c49badeea3846c16b839b1f6faef1", "cases":[]}
    var active = GS.new(_seed())
    active.apply_ew({"effect":"noise_jam", "target_id":"raider_2", "severity":0.5, "duration_s":120.0, "source_id":"R3-R4-CONT"})
    for i in range(6): active.tick(TICK)
    var before: Dictionary = _sig(active)

    var legacy_source = GS.new(_seed())
    legacy_source.tick(TICK)
    var legacy_doc: Dictionary = JSON.parse_string(legacy_source.save_state())
    for k in ["ew_observation_samples", "ew_observation_queue", "ew_delivered_observations", "ew_candidates", "ew_observation_seq", "ew_quality_history", "ew_combat_quality", "ew_rejected_deliveries"]:
        legacy_doc.erase(k)
    var path := "user://a03_r4_legacy_no_ew.json"
    var wf := FileAccess.open(path, FileAccess.WRITE)
    wf.store_string(JSON.stringify(legacy_doc))
    wf.close()
    var rf := FileAccess.open(path, FileAccess.READ)
    var legacy_text: String = rf.get_as_text()
    rf.close()

    var active_lr: Dictionary = active.load_state(legacy_text)
    var after_active: Dictionary = _sig(active)
    var fresh = GS.new(_seed())
    var fresh_lr: Dictionary = fresh.load_state(legacy_text)
    var after_fresh: Dictionary = _sig(fresh)
    var legacy_same := JSON.stringify(after_active) == JSON.stringify(after_fresh)
    out["legacy_active_load"] = {"ok":active_lr.get("ok", false), "mode":active_lr.get("ew_restore_mode", ""), "before":before, "after":after_active}
    out["legacy_fresh_load"] = {"ok":fresh_lr.get("ok", false), "mode":fresh_lr.get("ew_restore_mode", ""), "after":after_fresh}
    out["cases"].append({"case":"legacy_active_equals_fresh", "same":legacy_same})

    var full_source = GS.new(_seed())
    full_source.apply_ew({"effect":"noise_jam", "target_id":"raider_2", "severity":0.5, "duration_s":120.0, "source_id":"R3-R4-FULL"})
    for i in range(2): full_source.tick(TICK)
    var full_text: String = full_source.save_state()
    var full_load = GS.new(_seed())
    var full_lr: Dictionary = full_load.load_state(full_text)
    out["cases"].append({"case":"full_inflight", "ok":full_lr.get("ok", false), "mode":full_lr.get("ew_restore_mode", ""), "state":_sig(full_load)})
    var partial_doc: Dictionary = JSON.parse_string(full_text)
    partial_doc.erase("ew_combat_quality")
    var partial_load = GS.new(_seed())
    var partial_lr: Dictionary = partial_load.load_state(JSON.stringify(partial_doc))
    out["cases"].append({"case":"partial_missing_ew_combat_quality", "ok":partial_lr.get("ok", false), "mode":partial_lr.get("ew_restore_mode", ""), "missing":partial_lr.get("ew_restore_missing", []), "queue":partial_load.ew_delivery_queue().size()})
    var null_doc: Dictionary = JSON.parse_string(full_text)
    null_doc["ew_observation_queue"] = null
    var null_load = GS.new(_seed())
    var null_lr: Dictionary = null_load.load_state(JSON.stringify(null_doc))
    out["cases"].append({"case":"present_queue_null", "ok":null_lr.get("ok", false), "mode":null_lr.get("ew_restore_mode", ""), "errors":null_lr.get("errors", [])})
    print("A03_R4_TIME_RESTORE=" + JSON.stringify(out))
    quit(0)

func _sig(s) -> Dictionary:
    return {"samples":s.ew_observation_samples().size(), "queue":s.ew_delivery_queue().size(), "delivered":s.ew_delivered_observations().size(), "rejected":s.ew_rejected_deliveries().size(), "seq":s._ew_obs_seq, "quality_history":s._ew_quality_history.duplicate(true), "combat_quality":s._ew_combat_quality.duplicate(true), "candidates":s._ew_candidates.duplicate(true)}

func _seed() -> Dictionary:
    return {
        "own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true,
        "command_domains":[{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","fleet_id":"own_fleet","authorized_actors":["player_ctrl"]},{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","fleet_id":"ally_fleet","authorized_actors":["ally_ai"]}],
        "fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player","fleet_id":"own_fleet"},{"entity_instance_id":"ally_ship","domain_id":"ally","fleet_id":"ally_fleet"}],
        "ew_service":{}, "identification_service":{"evidence_ttl_s":30.0,"decay_half_life_s":60.0,"auto":{"enabled":false}},
        "entities":[{"id":"own_ship","kind":"ship","pos_km":[321719.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"raider_2","kind":"ship","pos_km":[321719.0,600.0,0.0],"vel_kmps":[0.0,0.4,0.0]}],
        "sensor_service":{"observer":{"id":"own_ship","pos_km":[321719.0,0.0,0.0]},"targets":[{"id":"raider_2","pos_km":[321719.0,600.0,0.0],"rcs_m2":100.0,"side":"hostile","batch":"OCU-07"}],"options":{"radar_enabled":true,"emcon":false}}
    }
