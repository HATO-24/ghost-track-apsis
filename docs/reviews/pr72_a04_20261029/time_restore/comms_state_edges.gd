extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")

func _initialize() -> void:
    var out := {"head":"1de99a85c4f69dca706509648450487197523ab5", "cases":[]}

    var src = GS.new(_seed(123))
    src.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"A04-DIAG"})
    src.comms_debug_force_draw(0.1)
    var first: Dictionary = src.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    var frozen: Dictionary = (src.comms.pending[0] as Dictionary).get("ew", {}).duplicate(true)
    var missing_state: Dictionary = src.comms.export_state()
    var missing_pending: Array = missing_state.get("pending", []).duplicate(true)
    (missing_pending[0] as Dictionary).erase("ew")
    missing_state["pending"] = missing_pending
    var restore_missing = GS.new(_seed(123))
    restore_missing.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"A04-DIAG"})
    var missing_lr: Dictionary = restore_missing.comms.load_state(missing_state)
    var after_due: Array = restore_missing.comms.tick(22.0)
    var due_kinds := _event_kinds(after_due)
    out["cases"].append({"case":"v2_pending_missing_ew", "original_frozen_ew":frozen, "load_ok":missing_lr.get("ok", false), "restore_mode":missing_lr.get("restore_mode", ""), "at_due_event_kinds":due_kinds, "converted_failure_to_delivery":due_kinds.has("DELIVERED") and not due_kinds.has("FAILED")})

    var frac_state: Dictionary = src.comms.export_state()
    frac_state["version"] = 2.5
    var frac_target = GS.new(_seed(123))
    var frac_lr: Dictionary = frac_target.comms.load_state(frac_state)
    out["cases"].append({"case":"fractional_state_version_2_5", "load_ok":frac_lr.get("ok", false), "reason":frac_lr.get("reason", ""), "parsed_version":int(frac_state.get("version", -1))})

    var rng_target = GS.new(_seed(456))
    var rng_state: Dictionary = src.comms.export_state()
    var rng_lr: Dictionary = rng_target.comms.load_state(rng_state)
    var saved_rng: Dictionary = rng_state.get("ew_rng", {})
    var restored_rng: Dictionary = rng_target.comms.ew_rng_state()
    var next_src: Dictionary = src.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    var next_target: Dictionary = rng_target.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    out["cases"].append({"case":"state_v2_rng_restoration", "load_ok":rng_lr.get("ok", false), "saved_rng":saved_rng, "reported_after_load":restored_rng, "next_source_draw":_ew(next_src).get("draw", null), "next_restored_draw":_ew(next_target).get("draw", null), "next_draw_matches":absf(float(_ew(next_src).get("draw", -1.0))-float(_ew(next_target).get("draw", -2.0))) < 1.0e-6})

    var atomic = GS.new(_seed(789))
    atomic.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"A04-DIAG"})
    atomic.comms_debug_force_draw(0.1)
    atomic.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    var before: Dictionary = atomic.comms.export_state()
    var bad_present: Dictionary = before.duplicate(true)
    (((bad_present.get("pending", []) as Array)[0] as Dictionary))["ew"] = null
    var bad_present_lr: Dictionary = atomic.comms.load_state(bad_present)
    var after_bad_present: Dictionary = atomic.comms.export_state()
    var bad_version: Dictionary = before.duplicate(true)
    bad_version["version"] = 99
    var bad_version_lr: Dictionary = atomic.comms.load_state(bad_version)
    var after_bad_version: Dictionary = atomic.comms.export_state()
    out["cases"].append({"case":"present_invalid_ew_atomic", "load_ok":bad_present_lr.get("ok", false), "reason":bad_present_lr.get("reason", ""), "errors":bad_present_lr.get("errors", []), "state_unchanged":JSON.stringify(before)==JSON.stringify(after_bad_present)})
    out["cases"].append({"case":"unknown_state_version_atomic", "load_ok":bad_version_lr.get("ok", false), "reason":bad_version_lr.get("reason", ""), "state_unchanged":JSON.stringify(before)==JSON.stringify(after_bad_version)})
    print("A04_TIME_RESTORE_DIAG=" + JSON.stringify(out))
    quit(0)

func _event_kinds(events: Array) -> Array:
    var out: Array = []
    for raw in events:
        if raw is Dictionary:
            out.append(String((raw as Dictionary).get("kind", "")))
    return out

func _ew(res: Dictionary) -> Dictionary:
    return (res.get("ew", {}) as Dictionary) if res.get("ew") is Dictionary else {}

func _seed(rng_seed: int) -> Dictionary:
    return {
        "own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true,
        "comms_ew_seed":rng_seed,
        "command_domains":[{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","fleet_id":"own_fleet","authorized_actors":["player_ctrl"]},{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","fleet_id":"ally_fleet","authorized_actors":["ally_ai"]},{"domain_id":"opfor","kind":"ai_hostile","controller_id":"opfor_ai","intel_owner_id":"opfor_intel","fleet_id":"enemy_fleet","authorized_actors":["opfor_ai"]}],
        "fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player","fleet_id":"own_fleet"},{"entity_instance_id":"ally_ship","domain_id":"ally","fleet_id":"ally_fleet"},{"entity_instance_id":"enemy_ship","domain_id":"opfor","fleet_id":"enemy_fleet"}],
        "entities":[{"id":"own_ship","kind":"ship","pos_km":[0.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"ally_ship","kind":"ship","pos_km":[100.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"enemy_ship","kind":"ship","pos_km":[400.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]}],
        "nodes":[{"id":"own_ship","name":"OWN"},{"id":"ally_ship","name":"ALLY"},{"id":"enemy_ship","name":"OPFOR"}],
        "links":[{"a":"own_ship","b":"ally_ship","mode":"LD","latency_s":2.0},{"a":"own_ship","b":"enemy_ship","mode":"LD","latency_s":2.0}],
        "identification_service":{"auto":{"enabled":false}}, "ew_service":{}
    }
