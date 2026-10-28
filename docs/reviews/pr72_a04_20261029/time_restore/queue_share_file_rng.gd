extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")

func _initialize() -> void:
    var continuous = GS.new(_seed())
    continuous.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"A04-QUEUE-SHARE"})
    var share_row := {"observer_id":"own_ship", "target_id":"enemy_ship", "sensor":"radar", "observed_t":0.0, "received_t":0.0, "quality":1.0, "range_km":400.0, "bearing_deg":0.0, "share_authorized_by":"player_ctrl"}
    var share: Dictionary = continuous.queue_intel_share("own_ship", "ally_ship", "ally_intel", share_row)
    var before_save: Dictionary = continuous.comms_ew_state()
    var save_text: String = continuous.save_state()
    var save_doc: Dictionary = JSON.parse_string(save_text)
    var log_send_count := 0
    for raw in save_doc.get("log", []):
        if raw is Dictionary and String((raw as Dictionary).get("op", "")) == "send_comms":
            log_send_count += 1
    var path := "user://a04_queue_share_rng.json"
    var wf := FileAccess.open(path, FileAccess.WRITE)
    wf.store_string(save_text)
    wf.close()
    var rf := FileAccess.open(path, FileAccess.READ)
    var disk_text: String = rf.get_as_text()
    rf.close()

    var restored = GS.new(_seed())
    var lr: Dictionary = restored.load_state(disk_text)
    var restored_before_next: Dictionary = restored.comms_ew_state()
    var next_cont: Dictionary = continuous.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    var next_restored: Dictionary = restored.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
    var draw_cont := float(_ew(next_cont).get("draw", -1.0))
    var draw_restored := float(_ew(next_restored).get("draw", -2.0))
    var out := {
        "head":"1de99a85c4f69dca706509648450487197523ab5",
        "share_ok":share.get("ok", false), "share_delivery_id":share.get("delivery_id", ""),
        "save_file_bytes":disk_text.length(), "send_comms_log_count":log_send_count,
        "continuous_before_save":before_save, "load_ok":lr.get("ok", false), "load_errors":lr.get("errors", []),
        "restored_before_next":restored_before_next,
        "next_continuous_draw":draw_cont, "next_restored_draw":draw_restored,
        "next_draw_matches":absf(draw_cont-draw_restored) <= 1.0e-6,
        "continuous_after_next":continuous.comms_ew_state(), "restored_after_next":restored.comms_ew_state()
    }
    print("A04_QUEUE_SHARE_FILE_RNG=" + JSON.stringify(out))
    quit(0)

func _ew(res: Dictionary) -> Dictionary:
    return (res.get("ew", {}) as Dictionary) if res.get("ew") is Dictionary else {}

func _seed() -> Dictionary:
    return {
        "own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true,
        "command_domains":[{"domain_id":"player","kind":"player","controller_id":"player_ctrl","intel_owner_id":"player_intel","fleet_id":"own_fleet","authorized_actors":["player_ctrl"]},{"domain_id":"ally","kind":"ai_ally","controller_id":"ally_ai","intel_owner_id":"ally_intel","fleet_id":"ally_fleet","authorized_actors":["ally_ai"]},{"domain_id":"opfor","kind":"ai_hostile","controller_id":"opfor_ai","intel_owner_id":"opfor_intel","fleet_id":"enemy_fleet","authorized_actors":["opfor_ai"]}],
        "fleet_instances":[{"entity_instance_id":"own_ship","domain_id":"player","fleet_id":"own_fleet"},{"entity_instance_id":"ally_ship","domain_id":"ally","fleet_id":"ally_fleet"},{"entity_instance_id":"enemy_ship","domain_id":"opfor","fleet_id":"enemy_fleet"}],
        "entities":[{"id":"own_ship","kind":"ship","pos_km":[0.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"ally_ship","kind":"ship","pos_km":[100.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]},{"id":"enemy_ship","kind":"ship","pos_km":[400.0,0.0,0.0],"vel_kmps":[0.0,0.0,0.0]}],
        "nodes":[{"id":"own_ship","name":"OWN"},{"id":"ally_ship","name":"ALLY"},{"id":"enemy_ship","name":"OPFOR"}],
        "links":[{"a":"own_ship","b":"ally_ship","mode":"LD","latency_s":2.0},{"a":"own_ship","b":"enemy_ship","mode":"LD","latency_s":2.0}],
        "identification_service":{"auto":{"enabled":false}}, "ew_service":{}
    }

