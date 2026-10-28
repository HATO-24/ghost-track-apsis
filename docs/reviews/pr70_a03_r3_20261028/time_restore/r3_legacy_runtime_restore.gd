extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
const TICK := 1.0

func _initialize() -> void:
    var out := {"cases": []}
    var active = GS.new(_seed())
    active.apply_ew({"effect":"noise_jam", "target_id":"raider_2", "severity":0.5, "duration_s":120.0, "source_id":"R3-CONT"})
    for i in range(2):
        active.tick(TICK)
    var before_queue: Array = active.ew_delivery_queue()
    var before_samples: Array = active.ew_observation_samples()
    var active_before := {"queue": before_queue.size(), "samples": before_samples.size(), "now": active.now_s()}

    var legacy_source = GS.new(_seed())
    var legacy_doc: Dictionary = JSON.parse_string(legacy_source.save_state())
    for k in ["ew_observation_samples", "ew_observation_queue", "ew_delivered_observations", "ew_candidates", "ew_observation_seq", "ew_quality_history", "ew_combat_quality", "ew_rejected_deliveries"]:
        legacy_doc.erase(k)
    var path := "user://a03_r3_legacy_no_ew.json"
    var wf := FileAccess.open(path, FileAccess.WRITE)
    wf.store_string(JSON.stringify(legacy_doc))
    wf.close()
    var rf := FileAccess.open(path, FileAccess.READ)
    var legacy_text: String = rf.get_as_text()
    rf.close()

    var current_lr: Dictionary = active.load_state(legacy_text)
    var after_current := {"queue": active.ew_delivery_queue().size(), "samples": active.ew_observation_samples().size(), "now": active.now_s(), "mode": current_lr.get("ew_restore_mode", ""), "ok": current_lr.get("ok", false)}
    var fresh = GS.new(_seed())
    var fresh_lr: Dictionary = fresh.load_state(legacy_text)
    var after_fresh := {"queue": fresh.ew_delivery_queue().size(), "samples": fresh.ew_observation_samples().size(), "now": fresh.now_s(), "mode": fresh_lr.get("ew_restore_mode", ""), "ok": fresh_lr.get("ok", false)}
    out["legacy_same_session"] = {"before":active_before, "after":after_current}
    out["legacy_fresh_session"] = after_fresh
    out["cases"].append({"case":"legacy_load_clears_prior_runtime", "same_session_equals_fresh": JSON.stringify({"queue":after_current.queue,"samples":after_current.samples}) == JSON.stringify({"queue":after_fresh.queue,"samples":after_fresh.samples})})

    var full_seed = GS.new(_seed())
    full_seed.apply_ew({"effect":"noise_jam", "target_id":"raider_2", "severity":0.5, "duration_s":120.0, "source_id":"R3-PARTIAL"})
    for i in range(2): full_seed.tick(TICK)
    var full_text: String = full_seed.save_state()
    var full_load = GS.new(_seed())
    var full_lr: Dictionary = full_load.load_state(full_text)
    out["cases"].append({"case":"full", "ok":full_lr.get("ok", false), "mode":full_lr.get("ew_restore_mode", ""), "queue":full_load.ew_delivery_queue().size()})
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
    print("A03_R3_TIME_RESTORE=" + JSON.stringify(out))
    quit(0)

func _seed() -> Dictionary:
    return {
        "own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true,
        "command_domains":[{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","fleet_id":"own_fleet","authorized_actors":["player_ctrl"]},{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","fleet_id":"ally_fleet","authorized_actors":["ally_ai"]}],
        "fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player","fleet_id":"own_fleet"},{"entity_instance_id":"ally_ship","domain_id":"ally","fleet_id":"ally_fleet"}],
        "ew_service":{}, "identification_service":{"evidence_ttl_s":30.0,"decay_half_life_s":60.0,"auto":{"enabled":false}},
        "entities":[{"id":"own_ship","kind":"ship","pos_km":[321719.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"raider_2","kind":"ship","pos_km":[321719.0,600.0,0.0],"vel_kmps":[0.0,0.4,0.0]}],
        "sensor_service":{"observer":{"id":"own_ship","pos_km":[321719.0,0.0,0.0]},"targets":[{"id":"raider_2","pos_km":[321719.0,600.0,0.0],"rcs_m2":100.0,"side":"hostile","batch":"OCU-07"}],"options":{"radar_enabled":true,"emcon":false}}
    }
