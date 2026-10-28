extends SceneTree
const GS := preload("res://scripts/core/game_session.gd")
var result := {"head": "563e97a61bc00d31104ad6db969edfe87f2fc25f", "cases": {}}

func _initialize() -> void:
	_registered_sender_context()
	_modern_no_context()
	_legacy_seed_control()
	var out := ProjectSettings.globalize_path("res://../.test-results/sol-a04-r3/authority/authority_audit.json")
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

func _modern_no_context() -> void:
	var s = _new()
	var sends: Array = []
	var own_default: Dictionary = s.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {"content": "modern own sender default opts"})
	sends.append({"label": "modern_own_sender_default_opts", "from": "own_ship",
		"to": "ally_ship", "opts_omitted": true, "result": own_default})
	var ally_empty: Dictionary = s.send_comms("ally_ship", "own_ship", "LD",
		"COMMS_SENT", {"content": "modern registered ally explicit empty opts"}, {})
	sends.append({"label": "modern_ally_sender_explicit_empty_opts", "from": "ally_ship",
		"to": "own_ship", "opts": {}, "result": ally_empty})
	var enemy_default: Dictionary = s.send_comms("enemy_ship", "own_ship", "LD",
		"COMMS_SENT", {"content": "modern registered enemy default opts"})
	sends.append({"label": "modern_enemy_sender_default_opts", "from": "enemy_ship",
		"to": "own_ship", "opts_omitted": true, "result": enemy_default})
	var events: Array = _advance(s, 2)
	result.cases["modern_registered_sender_no_context"] = {"ready": s.ready,
		"seed_has_explicit_command_domains": _seed().has("command_domains"),
		"seed_has_explicit_fleet_instances": _seed().has("fleet_instances"),
		"actual_authority_domains": s.authority_intel.domains.duplicate(true),
		"actual_authority_instances": s.authority_intel.instances.duplicate(true),
		"sends": sends, "events_to_2": events,
		"raw_comms_events": s.comms.events.duplicate(true), "now": s.now_s(),
		"note": "Fresh public sends in an explicitly modern authority seed; no load/replay/internal migration was used."}

func _legacy_seed_control() -> void:
	var sd := _seed(false)
	sd.erase("command_domains")
	sd.erase("fleet_instances")
	var s = GS.new(sd)
	var sent: Dictionary = s.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {"content": "legacy seed own sender default opts"})
	var events: Array = _advance(s, 2)
	result.cases["legacy_seed_own_default_context"] = {"ready": s.ready,
		"seed_has_explicit_command_domains": sd.has("command_domains"),
		"seed_has_explicit_fleet_instances": sd.has("fleet_instances"),
		"from": "own_ship", "to": "ally_ship", "opts_omitted": true,
		"result": sent, "events_to_2": events,
		"raw_comms_events": s.comms.events.duplicate(true), "now": s.now_s(),
		"note": "Genuine legacy-style seed omits command_domains/fleet_instances; preserves normal own sender compatibility. No old-log replay was tested."}
