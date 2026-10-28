extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")

func _initialize() -> void:
    var seed := GS.new()
    var base_text: String = seed.save_state()
    var p := "user://a03_r2_time_restore_base.json"
    var wf := FileAccess.open(p, FileAccess.WRITE)
    wf.store_string(base_text)
    wf.close()
    var rf := FileAccess.open(p, FileAccess.READ)
    var file_text: String = rf.get_as_text()
    rf.close()
    var full_doc: Dictionary = JSON.parse_string(file_text)
    var out: Dictionary = {"base_readback_bytes": file_text.length(), "cases": []}
    _case(out, "full_file", file_text)
    var legacy_doc: Dictionary = full_doc.duplicate(true)
    for k in ["ew_observation_samples", "ew_observation_queue", "ew_delivered_observations", "ew_candidates", "ew_observation_seq", "ew_quality_history", "ew_combat_quality", "ew_rejected_deliveries"]:
        legacy_doc.erase(k)
    _case(out, "legacy_all_ew_absent", JSON.stringify(legacy_doc))
    var null_doc: Dictionary = full_doc.duplicate(true)
    null_doc["ew_observation_queue"] = null
    _case(out, "present_queue_null", JSON.stringify(null_doc))
    var partial_doc: Dictionary = full_doc.duplicate(true)
    partial_doc.erase("ew_combat_quality")
    _case(out, "partial_missing_combat_quality", JSON.stringify(partial_doc))
    print("A03_R2_TIME_RESTORE_DIAG=" + JSON.stringify(out))
    quit(0)

func _case(out: Dictionary, label: String, text: String) -> void:
    var s := GS.new()
    var r: Dictionary = s.load_state(text)
    var row := {"case": label, "ok": r.get("ok", null), "mode": r.get("ew_restore_mode", ""), "errors": r.get("errors", []), "queue_size": (s.ew_delivery_queue() as Array).size()}
    (out["cases"] as Array).append(row)
