extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")

func _initialize() -> void:
	var result := {
		"purpose": "Bounded actual Session callback diagnostic: failed order exact due/execution rejection and fresh authorized share exact due/single fusion.",
		"head": "1de99a85c4f69dca706509648450487197523ab5",
		"failed_order": _failed_order_case(),
		"successful_share": _successful_share_case()
	}
	var path := "C:/Users/ASUS/.codex/worktrees/jc-a04-validation/GHOST TRACK_APSIS/.test-results/sol-a04/delivery/callback_diagnostic.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write diagnostic result: " + path)
		quit(2)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("A04_DELIVERY_CALLBACK_RESULT: ", JSON.stringify(result))
	quit(0)

func _failed_order_case() -> Dictionary:
	var s = GS.new(_seed())
	var jam: Dictionary = s.apply_ew({"effect": "comms_jam", "target_id": "ally_ship",
		"severity": 0.5, "duration_s": 120.0, "source_id": "DIAG-A04-ORDER"})
	s.comms_debug_force_draw(0.1)
	var issue: Dictionary = s.issue_order("hold", "own_ship", ["ally_ship"], {}, {"mode": "LD"})
	var order_id := String(issue.get("order_id", ""))
	var initial: Dictionary = s.order(order_id)
	var did := String(initial.get("delivery_id", ""))
	var pending0: Array = s.comms_pending()
	for i in range(21):
		s.tick(1.0)
	var at21: Dictionary = s.order(order_id)
	var exec_before: Dictionary = s.begin_execute_order(order_id)
	s.tick(1.0)
	var at22: Dictionary = s.order(order_id)
	var exec_after: Dictionary = s.begin_execute_order(order_id)
	var complete_after: Dictionary = s.complete_order(order_id, {"diagnostic": true})
	var due_events: Array = s.orders.events_since(0)
	var has_done := false
	for raw in due_events:
		if raw is Dictionary and String((raw as Dictionary).get("order_id", "")) == order_id 				and String((raw as Dictionary).get("event", "")) == "DONE":
			has_done = true
	for i2 in range(3):
		s.tick(1.0)
	var final_order: Dictionary = s.order(order_id)
	return {"jam": jam, "issue": issue, "order_id": order_id, "delivery_id": did,
		"ew_sample": (pending0[0] as Dictionary).get("ew", {}) if not pending0.is_empty() else {},
		"order_at_send": initial, "order_at_t21": at21,
		"execute_attempt_t21": exec_before, "order_at_t22": at22,
		"execute_attempt_after_failure": exec_after, "complete_attempt_after_failure": complete_after,
		"done_event_observed": has_done, "order_after_three_more_ticks": final_order,
		"comms_pending_after": s.comms_pending().size()}

func _successful_share_case() -> Dictionary:
	var s = GS.new(_seed())
	var jam: Dictionary = s.apply_ew({"effect": "comms_jam", "target_id": "ally_ship",
		"severity": 0.5, "duration_s": 120.0, "source_id": "DIAG-A04-SHARE"})
	s.comms_debug_force_draw(0.9)
	var row := {"observer_id": "own_ship", "target_id": "enemy_ship",
		"sensor": "radar", "source": "DIAG-A04", "observed_t": 0.0,
		"received_t": 0.0, "quality": 0.8, "range_km": 400.0,
		"bearing_deg": 15.0, "share_authorized_by": "player_intel"}
	var before := (s.authority_intel.intel_view("ally_intel").get("observations", []) as Array).size()
	var send: Dictionary = s.queue_intel_share("own_ship", "ally_ship", "ally_intel", row)
	var pending_at_send: Array = s.comms_pending()
	var due_ids: Array = []
	var share_events: Array = []
	for i in range(21):
		var r21: Dictionary = s.tick(1.0)
		for raw in r21.get("events", []):
			if raw is Dictionary and String((raw as Dictionary).get("type", "")) == "comms.delivered":
				share_events.append(raw)
	var before_due_obs := (s.authority_intel.intel_view("ally_intel").get("observations", []) as Array).size()
	var before_due_pending := s.pending_intel_shares().size()
	var r22: Dictionary = s.tick(1.0)
	for raw2 in r22.get("events", []):
		if raw2 is Dictionary and String((raw2 as Dictionary).get("type", "")) == "comms.delivered":
			share_events.append(raw2)
	var after_due_rows: Array = s.authority_intel.intel_view("ally_intel").get("observations", [])
	var after_due := after_due_rows.size()
	var last_result: Dictionary = s.last_intel_share_result()
	for i2 in range(3):
		var rmore: Dictionary = s.tick(1.0)
		for raw3 in rmore.get("events", []):
			if raw3 is Dictionary and String((raw3 as Dictionary).get("type", "")) == "comms.delivered":
				share_events.append(raw3)
	var after_repeat := (s.authority_intel.intel_view("ally_intel").get("observations", []) as Array).size()
	return {"jam": jam, "send": send,
		"ew_sample": (pending_at_send[0] as Dictionary).get("ew", {}) if not pending_at_send.is_empty() else {},
		"arrive_t": pending_at_send[0].get("arrive_t", null) if not pending_at_send.is_empty() else null,
		"obs_before": before, "obs_before_due": before_due_obs,
		"pending_before_due": before_due_pending, "t_at_due": s.now_s() - 3.0,
		"obs_after_due": after_due, "owner_rows_after_due": after_due_rows,
		"last_share_result": last_result,
		"delivered_event_count_through_due_and_repeat_ticks": share_events.size(),
		"obs_after_three_repeat_ticks": after_repeat,
		"pending_after_repeat_ticks": s.pending_intel_shares().size(),
		"comms_pending_after_repeat_ticks": s.comms_pending().size()}

func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot", "track_table": true,
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
			{"entity_instance_id": "own_ship", "domain_id": "player", "fleet_id": "own_fleet"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally", "fleet_id": "ally_fleet"},
			{"entity_instance_id": "enemy_ship", "domain_id": "opfor", "fleet_id": "enemy_fleet"}],
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [100.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "enemy_ship", "kind": "ship", "pos_km": [400.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}],
		"nodes": [{"id": "own_ship", "name": "OWN"}, {"id": "ally_ship", "name": "ALLY"},
			{"id": "enemy_ship", "name": "OPFOR"}],
		"links": [
			{"a": "own_ship", "b": "ally_ship", "mode": "LD", "latency_s": 2.0},
			{"a": "own_ship", "b": "enemy_ship", "mode": "LD", "latency_s": 2.0}],
		"identification_service": {"auto": {"enabled": false}},
		"ew_service": {}
	}
