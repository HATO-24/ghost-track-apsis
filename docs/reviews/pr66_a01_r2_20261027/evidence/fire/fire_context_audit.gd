extends "res://tests/session_probe.gd"

# Review only. Uses the existing finite-ammo, normal-ROE unified-fire fixture.
var audit_rows: Array = []

func _initialize() -> void:
	for mode in ["control", "unknown_shooter", "ally_shooter", "enemy_shooter", "other_own_unavailable", "hostile_actor", "wrong_controller", "foreign_fleet", "legacy_hostile_actor", "other_own_runtime_flag"]:
		audit_case(mode)
	var out = FileAccess.open(OS.get_environment("A01_FIRE_OUT"), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(audit_rows, "\t"))
	print("A01_FIRE_AUDIT ", JSON.stringify(audit_rows))
	quit(0)

func audit_case(mode: String) -> void:
	var cfg: Dictionary = _unified_cfg()
	cfg["command_domains"] = [
		{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl", "intel_owner_id": "player_intel", "authorized_actors": ["player_ctrl"]},
		{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai", "intel_owner_id": "ally_intel", "authorized_actors": ["ally_ai"]},
		{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai", "intel_owner_id": "opfor_intel", "authorized_actors": ["opfor_ai"]}]
	cfg["fleet_instances"] = [{"entity_instance_id": "session_ship", "domain_id": "player", "fleet_id": "taskforce"},
		{"entity_instance_id": "ally_ship", "domain_id": "ally", "fleet_id": "ally_fleet"},
		{"entity_instance_id": "enemy_ship", "domain_id": "opfor", "fleet_id": "enemy_fleet"}]
	if mode in ["other_own_runtime_flag", "other_own_unavailable"]:
		cfg["entities"].append({"id": "second_own", "kind": "ship", "side": "friend", "pos_km": [10.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]})
		cfg["fleet_instances"].append({"entity_instance_id": "second_own", "domain_id": "player", "fleet_id": "taskforce"})
		cfg["own_fleet"] = [{"entity_instance_id": "second_own", "combat_runtime": mode == "other_own_runtime_flag"}]
	var s = GameSession.new(cfg)
	_unified_prepare(s)
	var opts: Dictionary = {"shooter_id": "session_ship", "actor_id": "player_ctrl", "controller_id": "player_ctrl", "fleet_id": "taskforce"}
	if mode == "unknown_shooter":
		opts["shooter_id"] = "not_registered"
	elif mode == "ally_shooter":
		opts["shooter_id"] = "ally_ship"
	elif mode == "enemy_shooter":
		opts["shooter_id"] = "enemy_ship"
	elif mode == "hostile_actor":
		opts["actor_id"] = "opfor_ai"
	elif mode == "wrong_controller":
		opts["controller_id"] = "opfor_ai"
	elif mode == "foreign_fleet":
		opts["fleet_id"] = "enemy_fleet"
	elif mode == "legacy_hostile_actor":
		opts.erase("shooter_id")
		opts["actor_id"] = "opfor_ai"
	elif mode in ["other_own_runtime_flag", "other_own_unavailable"]:
		opts["shooter_id"] = "second_own"
	var before: Dictionary = audit_res(s)
	var auth: Dictionary = s.authorize_fire(opts)
	var result: Dictionary = s.request_fire("R1", "missile", true, opts)
	s.flush_events()
	var after: Dictionary = audit_res(s)
	var saved: Dictionary = JSON.parse_string(s.save_state())
	var log_fire: Array = []
	for op in saved.get("log", []):
		if String(op.get("op", "")) == "request_fire":
			log_fire.append(op)
	var projectiles: Array = s.combat_ballistics_active()
	audit_rows.append({"mode": mode, "ready": s.ready, "errors": s.errors, "opts": opts, "auth": auth,
		"before": before, "after": after, "result": result, "fire_audit": s.fire_audit(), "saved_fire_ops": log_fire,
		"projectiles": projectiles})

func audit_res(s) -> Dictionary:
	return {"ammo": _missile_ammo(s), "projectiles": s.combat_ballistics_active().size(),
		"success_events": s.bus.filter_events({"type": "combat.weapon_launch"}).size(),
		"combat_own_id": s.combat_service.own_id}
