extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
var result := {"head": "1de99a85c4f69dca706509648450487197523ab5", "cases": {}}

func _initialize() -> void:
	_ignore_ew_control()
	_registered_sender_context()
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a04/transport/transport_audit.json")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("TRANSPORT_AUDIT_JSON=" + out)
	for k in result.cases.keys():
		print("CASE ", k, " ", JSON.stringify(result.cases[k]))
	quit(0)

func _new():
	return GS.new(_seed())

func _advance(s, count: int) -> Array:
	var out: Array = []
	for i in range(count):
		var t: Dictionary = s.tick(1.0)
		out.append_array(t.get("events", []))
	return out

func _context(domain: String) -> Dictionary:
	if domain == "player":
		return {"actor_id": "player_ctrl", "controller_id": "player_ctrl",
			"domain_id": "player", "fleet_id": "own_fleet",
			"owner_id": "player_intel", "intel_owner_id": "player_intel"}
	if domain == "ally":
		return {"actor_id": "ally_ai", "controller_id": "ally_ai",
			"domain_id": "ally", "fleet_id": "ally_fleet",
			"owner_id": "ally_intel", "intel_owner_id": "ally_intel"}
	return {"actor_id": "opfor_ai", "controller_id": "opfor_ai",
		"domain_id": "opfor", "fleet_id": "enemy_fleet",
		"owner_id": "opfor_intel", "intel_owner_id": "opfor_intel"}

func _ignore_ew_control() -> void:
	var s = _new()
	var jam: Dictionary = s.apply_ew({"effect": "comms_jam", "target_id": "ally_ship",
		"source_id": "AUDIT-EW", "severity": 0.5, "duration_s": 120.0})
	s.comms_debug_force_draw(0.1)
	var normal: Dictionary = s.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {"content": "normal"}, _context("player"))
	var bypass_opts := _context("player")
	bypass_opts["ignore_ew"] = true
	s.comms_debug_force_draw(0.1)
	var bypass: Dictionary = s.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {"content": "ordinary opts ignore_ew"}, bypass_opts)
	var pending_at_send: Array = s.comms_pending()
	var at_2: Array = _advance(s, 2)
	var after_2_pending: Array = s.comms_pending()
	# Legitimately remove effect only after both sends; first message must retain frozen failure.
	var expired: Dictionary = s.ew_service.expire()
	var at_22: Array = _advance(s, 20)
	result.cases["ordinary_ignore_ew_option"] = {"ready": s.ready,
		"applied": jam, "normal": normal, "ordinary_bypass_opts": bypass_opts,
		"bypass": bypass, "pending_at_send": pending_at_send,
		"events_to_2": at_2, "pending_at_2": after_2_pending,
		"expire_after_send": expired, "events_2_to_22": at_22,
		"raw_comms_events": s.comms.events.duplicate(true),
		"rng": s.comms_ew_state(), "now": s.now_s()}

func _registered_sender_context() -> void:
	var s = _new()
	var sends: Array = []
	for spec in [
		{"label": "own_sender_player_context", "from": "own_ship", "to": "ally_ship", "ctx": "player"},
		{"label": "ally_sender_ally_context", "from": "ally_ship", "to": "own_ship", "ctx": "ally"},
		{"label": "ally_sender_player_context", "from": "ally_ship", "to": "own_ship", "ctx": "player"},
		{"label": "enemy_sender_player_context", "from": "enemy_ship", "to": "own_ship", "ctx": "player"},
		{"label": "own_sender_opfor_context", "from": "own_ship", "to": "ally_ship", "ctx": "opfor"},
		{"label": "unknown_sender_player_context", "from": "ghost_issuer", "to": "own_ship", "ctx": "player"}
	]:
		var context := _context(String(spec.ctx))
		var sent: Dictionary = s.send_comms(String(spec["from"]), String(spec.to),
			"LD", "COMMS_SENT", {"content": String(spec.label)}, context)
		sends.append({"input": spec, "caller_context": context, "result": sent})
	var order_opts := _context("player")
	order_opts["mode"] = "LD"
	var issued: Dictionary = s.issue_order("hold", "enemy_ship", ["own_ship"], {}, order_opts)
	var events: Array = _advance(s, 2)
	var oid := String(issued.get("order_id", ""))
	result.cases["registered_sender_and_caller_context"] = {"ready": s.ready,
		"sends": sends, "order_input": {"issuer": "enemy_ship", "target": "own_ship", "opts": order_opts},
		"issued": issued, "order_after_due": s.order(oid), "events_to_2": events,
		"raw_comms_events": s.comms.events.duplicate(true),
		"note": "No authorize/begin/complete call was made; successful send/QUEUED is not automatic execution."}

func _seed(with_ew := true) -> Dictionary:
	var sd := {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
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
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet"},
			{"entity_instance_id": "enemy_ship", "domain_id": "opfor",
				"fleet_id": "enemy_fleet"}],
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [100.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "enemy_ship", "kind": "ship", "pos_km": [400.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
		"nodes": [{"id": "own_ship", "name": "OWN"},
			{"id": "ally_ship", "name": "ALLY"},
			{"id": "enemy_ship", "name": "OPFOR"}],
		"links": [
			{"a": "own_ship", "b": "ally_ship", "mode": "LD", "latency_s": 2.0},
			{"a": "own_ship", "b": "enemy_ship", "mode": "LD", "latency_s": 2.0}],
		"identification_service": {"auto": {"enabled": false}},
	}
	if with_ew:
		sd["ew_service"] = {}
	return sd


