extends SceneTree
const Contracts = preload("res://scripts/core/jc_contracts.gd")
const FIXTURE = "res://tests/fixtures/jc_contracts/valid_three_domains.json"
var results: Array = []

func _initialize() -> void:
	var f = FileAccess.open(FIXTURE, FileAccess.READ)
	var valid: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_case("baseline_valid", valid, true)
	var d: Dictionary = valid.duplicate(true)
	d["commands"][0]["domain_id"] = "ally"
	d["commands"][0]["controller_id"] = "ally_ai"
	d["commands"][0]["shooter_id"] = "I-AL1"
	_case("old_player_actor_direct_fires_ally", d, false)
	d = valid.duplicate(true)
	d["instances"][0]["selected"] = false
	_case("old_unselected_instance_still_deployed", d, false)
	d = valid.duplicate(true)
	d["deployments"][0].erase("request_id")
	_case("old_replay_flag_bypasses_request_id", d, false)
	d = valid.duplicate(true)
	d["deployments"][1]["request_id"] = d["deployments"][0]["request_id"]
	_case("old_same_request_different_instance", d, false)
	d = valid.duplicate(true)
	d["observation_shares"][0]["intel_owner_id"] = "NOT-A-DOMAIN-OWNER"
	d["observation_shares"][0]["observer_id"] = "NO-SUCH-OBSERVER"
	d["observation_shares"][0]["delay_s"] = 999.0
	_case("old_unknown_owner_observer_delay", d, false)
	d = valid.duplicate(true)
	d["ledgers"][0]["fuel_kg"] = 3000.5
	_case("old_fractional_kg_fuel", d, true)
	d = valid.duplicate(true)
	d["ledgers"][0]["mass_kg"] = INF
	_case("old_infinite_mass", d, false)
	d = valid.duplicate(true)
	d["objectives"][0]["threshold"] = 9007199254740992
	_case("old_native_int_above_safe_range", d, false)
	d = valid.duplicate(true)
	d["ledgers"][0].erase("fuel_kg")
	_case("old_missing_required_fuel", d, false)
	d = valid.duplicate(true)
	d["fleets"][0]["roster"][0]["entity_instance_id"] = "I-AL1"
	_case("old_player_roster_ally_reference", d, false)

	d = valid.duplicate(true)
	d["deployments"][0]["t"] = -5.0
	_case("residual_deployment_negative_t", d, false)
	d = valid.duplicate(true)
	d["deployments"][0]["from_state"] = "DRAFT"
	d["deployments"][0]["to_state"] = "VALIDATED"
	_case("residual_deployment_transition_disagrees_current_state", d, false)
	d = valid.duplicate(true)
	d["instances"][1]["selected"] = false
	d["instances"][1]["deployment_state"] = "DRAFT"
	d["deployments"].remove_at(1)
	d["commands"][0]["shooter_id"] = "I-A2"
	_case("residual_fire_unselected_undeployed_shooter", d, false)
	d = valid.duplicate(true)
	d["observation_shares"][0]["observer_id"] = "I-OP1"
	_case("residual_enemy_observer_self_authorized_as_player_intel", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["shooter_id"] = "I-A2"
	d["commands"][0]["legacy_context"] = "own_ship"
	d["commands"][0]["own_entity_instance_id"] = "I-A2"
	_case("residual_legacy_self_declares_second_ship_as_own", d, false)
	d = valid.duplicate(true)
	d["commands"][0].erase("command_id")
	_case("residual_missing_command_id", d, false)
	var output_path = OS.get_environment("JC_K0_AUDIT_OUTPUT")
	if output_path != "":
		var out = FileAccess.open(output_path, FileAccess.WRITE)
		out.store_string(JSON.stringify({"head":"5d7208b82ebae81da874e059c2d88286317c6483","cases":results}, "\t"))
		out.close()
	quit(0)

func _case(name: String, doc: Dictionary, expected_ok: bool) -> void:
	var result: Dictionary = Contracts.validate(doc)
	var row = {"case":name,"ok":result.get("ok"),"expected_ok":expected_ok,"errors":result.get("errors")}
	results.append(row)
	print("[R6-K0-AUDIT] ", JSON.stringify(row))

