extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
 var out := {"ordinary": {}, "v1": {}}
 var bypass: Variant = _new()
 bypass.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"diag"})
 var bad: Dictionary = bypass.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {"actor_id":"player_ctrl", "controller_id":"player_ctrl", "domain_id":"player", "fleet_id":"own_fleet", "owner_id":"player_intel", "intel_owner_id":"player_intel", "ignore_ew":true})
 out.ordinary = {"ok":bad.get("ok", false), "reason":bad.get("reason", ""), "pending":bypass.comms.pending.size()}
 var s: Variant = _new()
 var jam: Dictionary = s.apply_ew({"effect":"comms_jam", "target_id":"ally_ship", "severity":0.5, "duration_s":120.0, "source_id":"diag-v1"})
 var live: Dictionary = s.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {"actor_id":"player_ctrl", "controller_id":"player_ctrl", "domain_id":"player", "fleet_id":"own_fleet", "owner_id":"player_intel", "intel_owner_id":"player_intel"})
 var doc: Dictionary = JSON.parse_string(s.save_state())
 for raw in doc.get("log", []):
  if raw is Dictionary and raw.get("op", "") == "send_comms":
   (raw as Dictionary)["outcome"] = {"schema":"v17.comms_outcome.v1", "version":1, "ok":true, "reason":"", "mode":"LD", "delivery_id":"C-000001", "path":["own_ship","ally_ship"], "latency_s":2.0, "relay_count":0, "arrive_t":2.0, "sent_t":0.0}
 if doc.get("comms") is Dictionary:
  (doc["comms"] as Dictionary)["version"] = 1
  (doc["comms"] as Dictionary).erase("ew_rng")
 var restored: Variant = _new()
 var load: Dictionary = restored.load_state(JSON.stringify(doc))
 var report: Dictionary = restored.comms_restore_report()
 var ops: Array = report.get("ops", [])
 var row: Dictionary = ops[ops.size()-1] if not ops.is_empty() else {}
 out.v1 = {"jam_ok":jam.get("ok", false), "live_send_ok":live.get("ok", false), "live_latency":live.get("latency_s", -1.0), "live_ew":live.get("ew", {}), "load_ok":load.get("ok", false), "load_errors":load.get("errors", []), "report_legacy_v1":report.get("legacy_outcome_v1", 0), "row_legacy":row.get("legacy_outcome_v1", false), "row_matched":row.get("matched", false), "row_divergence":row.get("divergence", []), "replay_ok":row.get("replay_ok", false), "replay_latency":row.get("replay_latency_s", -1.0), "replay_delivery_id":row.get("replay_delivery_id", ""), "restored_ew_state":restored.comms_ew_state()}
 print("A04_R3_LEGACY_BOUNDARY_JSON=" + JSON.stringify(out))
 if bad.get("reason", "") != "ew_bypass_forbidden" or bypass.comms.pending.size() != 0 or not load.get("ok", false) or not row.get("legacy_outcome_v1", false) or not row.get("matched", false) or not row.get("replay_ok", false) or absf(float(row.get("replay_latency_s", -1.0))-2.0)>0.000001:
  quit(1)
 else:
  quit(0)
func _new() -> Variant:
 var sd := {"own_entity":"own_ship", "physics_world":true, "seed_frame":"bary_rot", "frame_origin":"bary_rot", "track_table":true, "command_domains":[{"domain_id":"player", "kind":"player", "controller_id":"player_ctrl", "intel_owner_id":"player_intel", "fleet_id":"own_fleet", "authorized_actors":["player_ctrl"]}, {"domain_id":"ally", "kind":"ai_ally", "controller_id":"ally_ai", "intel_owner_id":"ally_intel", "fleet_id":"ally_fleet", "authorized_actors":["ally_ai"]}], "fleet_instances":[{"entity_instance_id":"own_ship", "domain_id":"player", "fleet_id":"own_fleet"}, {"entity_instance_id":"ally_ship", "domain_id":"ally", "fleet_id":"ally_fleet"}], "entities":[{"id":"own_ship", "kind":"ship", "pos_km":[0,0,0], "vel_kmps":[0,0,0]}, {"id":"ally_ship", "kind":"ship", "pos_km":[100,0,0], "vel_kmps":[0,0,0]}], "nodes":[{"id":"own_ship", "name":"OWN"}, {"id":"ally_ship", "name":"ALLY"}], "links":[{"a":"own_ship", "b":"ally_ship", "mode":"LD", "latency_s":2.0}], "identification_service":{"auto":{"enabled":false}}, "ew_service":{}}
 return GS.new(sd)

