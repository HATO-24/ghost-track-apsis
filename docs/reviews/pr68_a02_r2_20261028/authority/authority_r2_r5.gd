extends SceneTree

const GS := preload("res://scripts/core/game_session.gd")
const Binder := preload("res://scripts/ui/shell_binder.gd")

func _initialize() -> void:
	var out := {}
	var seed := _seed()

	# Actual Binder legacy confirm/clear wrapper, then same semantics through
	# legacy GameSession methods and current owner-scoped methods.
	var binder_session = GS.new(seed)
	var binder = Binder.new()
	binder.session = binder_session
	var binder_confirm: Dictionary = binder.ident_confirm(
		{"entity_id": "raider_2", "track_id": "raider_2"}, "friend")
	var binder_after_confirm := binder_session.identity_operational(
		"player_intel", "raider_2")
	var binder_audit_after_confirm: Array = binder_session.authority_intel.identity_audit.duplicate(true)
	var binder_clear: Dictionary = binder.ident_clear(
		{"entity_id": "raider_2", "track_id": "raider_2"})
	var binder_after_clear := binder_session.identity_operational(
		"player_intel", "raider_2")
	out["real_binder_old_confirm_clear"] = {
		"confirm": binder_confirm,
		"after_confirm": _summary(binder_after_confirm),
		"audit_after_confirm": binder_audit_after_confirm,
		"clear": binder_clear,
		"after_clear": _summary(binder_after_clear),
		"audit_final": binder_session.authority_intel.identity_audit.duplicate(true)}

	var legacy_session = GS.new(seed)
	var legacy_confirm: Dictionary = legacy_session.identification_manual_confirm(
		"raider_2", "friend", {"authority": "command"})
	var legacy_after_confirm := legacy_session.identity_operational(
		"player_intel", "raider_2")
	var legacy_audit_after_confirm: Array = legacy_session.authority_intel.identity_audit.duplicate(true)
	var legacy_clear: Dictionary = legacy_session.identification_clear_manual(
		"raider_2", {"authority": "command"})
	var legacy_after_clear := legacy_session.identity_operational(
		"player_intel", "raider_2")
	out["legacy_session_confirm_clear"] = {
		"confirm": legacy_confirm,
		"after_confirm": _summary(legacy_after_confirm),
		"audit_after_confirm": legacy_audit_after_confirm,
		"clear": legacy_clear,
		"after_clear": _summary(legacy_after_clear),
		"audit_final": legacy_session.authority_intel.identity_audit.duplicate(true)}

	var current_session = GS.new(seed)
	var current_confirm: Dictionary = current_session.identity_manual_confirm(
		"player_intel", "raider_2", "friend",
		{"authority": "command", "actor_id": "player_ctrl"})
	var current_after_confirm := current_session.identity_operational(
		"player_intel", "raider_2")
	var current_clear: Dictionary = current_session.identity_manual_clear(
		"player_intel", "raider_2",
		{"authority": "command", "actor_id": "player_ctrl"})
	var current_after_clear := current_session.identity_operational(
		"player_intel", "raider_2")
	var unauthorized := current_session.identity_manual_confirm(
		"ally_intel", "harmattan", "friend",
		{"authority": "command", "actor_id": "untrusted-caller"})
	var unauthorized_after := current_session.identity_operational(
		"ally_intel", "harmattan")
	var authorized_ally := current_session.identity_manual_confirm(
		"ally_intel", "harmattan", "friend",
		{"authority": "command", "actor_id": "ally_ai"})
	var authorized_ally_after := current_session.identity_operational(
		"ally_intel", "harmattan")
	out["owner_scoped_authority"] = {
		"confirm": current_confirm,
		"after_confirm": _summary(current_after_confirm),
		"clear": current_clear,
		"after_clear": _summary(current_after_clear),
		"untrusted_cross_owner_confirm": unauthorized,
		"cross_owner_after_rejection": _summary(unauthorized_after),
		"trusted_ally_controller_confirm": authorized_ally,
		"trusted_ally_after_confirm": _summary(authorized_ally_after),
		"audit": current_session.authority_intel.identity_audit.duplicate(true)}

	# R5: evaluator conflict must survive a successful reply; transmission state
	# is separate, and explicit jam request cannot overwrite actual occlusion.
	var conflict_session = GS.new(seed)
	var conflict_ingest: Dictionary = conflict_session.identity_ingest(
		"player_intel", {"target_id": "harmattan", "source": "optical",
		"identity": "hostile", "confidence": 0.95})
	var conflict_before := _summary(conflict_session.identity_operational(
		"player_intel", "harmattan"))
	var conflict_query: Dictionary = conflict_session.identity_iff_query(
		"player_intel", "harmattan", {"mode": "mode_s", "range_km": 10.0})
	var conflict_after := _summary(conflict_session.identity_operational(
		"player_intel", "harmattan"))
	var occluded_session = GS.new(seed)
	var occluded: Dictionary = occluded_session.identity_iff_query(
		"player_intel", "harmattan", {"mode": "mode_s", "range_km": 10.0,
		"occluded": true})
	var occluded_jammed: Dictionary = occluded_session.identity_iff_query(
		"player_intel", "harmattan", {"mode": "mode_s", "range_km": 10.0,
		"occluded": true, "jam": 0.95})
	out["iff_assessment_vs_transport"] = {
		"ingest": conflict_ingest,
		"before": conflict_before,
		"query": conflict_query,
		"after": conflict_after,
		"occluded_only": occluded,
		"occluded_plus_requested_jam": occluded_jammed}

	var path := "C:/Users/ASUS/.codex/worktrees/jc-a02-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a02-r2/authority/results.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("A02_R2_R5_AUTHORITY_RESULT: ", JSON.stringify(out))
	quit(0)

func _summary(d: Dictionary) -> Dictionary:
	var keys := ["owner_id", "target_id", "identity", "identity_state",
		"identity_iff_state", "identity_iff_reason", "identity_iff_reply_status",
		"identity_confidence", "identity_manual", "identity_authorized",
		"identity_audited", "identity_audit_ids", "audit_ids", "identity_sources"]
	var out := {}
	for key in keys:
		if d.has(key):
			out[key] = d[key]
	return out

func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot", "track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "faction": "ueg", "roe": "DEFENSIVE",
				"fleet_id": "ally_fleet", "authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "faction": "ocu", "roe": "AGGRESSIVE",
				"fleet_id": "enemy_fleet", "authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player", "fleet_id": "own_fleet", "role": "flag"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally", "fleet_id": "ally_fleet", "role": "picket"},
			{"entity_instance_id": "raider_2", "domain_id": "opfor", "fleet_id": "enemy_fleet", "role": "raider"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}],
		"identification_service": {"evidence_ttl_s": 12.0, "decay_half_life_s": 60.0,
			"auto": {"enabled": false}},
		"transponder_service": {"content_path": "res://framework/content/transponders_prologue.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [321719.0, 300.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship", "pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [321719.0, 900.0, 0.0], "vel_kmps": [0.0, 0.2, 0.0]}]
	}
