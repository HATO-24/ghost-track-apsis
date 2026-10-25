extends SceneTree
const Contracts = preload("res://scripts/core/jc_contracts.gd")
const FIXTURE = "res://tests/fixtures/jc_contracts/valid_three_domains.json"
var results: Array = []

func _initialize() -> void:
	var f = FileAccess.open(FIXTURE, FileAccess.READ)
	var valid: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_case("baseline_valid", valid)
	var d: Dictionary = valid.duplicate(true)
	d["commands"][0]["domain_id"] = "ally"
	d["commands"][0]["controller_id"] = "ally_ai"
	d["commands"][0]["shooter_id"] = "I-AL1"
	_case("player_actor_direct_fires_ally", d)
	d["commands"][0]["legacy_context"] = "own_ship"
	_case("legacy_own_ship_label_with_ally_shooter", d)
	d = valid.duplicate(true)
	d["observation_shares"][0]["intel_owner_id"] = "NOT-A-DOMAIN-OWNER"
	d["observation_shares"][0]["observer_id"] = "NO-SUCH-OBSERVER"
	d["observation_shares"][0]["delay_s"] = 999.0
	_case("unknown_intel_owner_observer_and_delay_conflict", d)
	d = valid.duplicate(true)
	d["command_domains"][1]["intel_owner_id"] = d["command_domains"][0]["intel_owner_id"]
	_case("player_and_ally_share_intel_owner_without_share_grant", d)
	d = valid.duplicate(true)
	for domain in d["command_domains"]:
		domain["kind"] = "player"
	_case("all_three_domains_are_player", d)
	d = valid.duplicate(true)
	d["instances"][0]["selected"] = false
	_case("unselected_instance_still_deployed", d)
	d = valid.duplicate(true)
	d["deployments"][1]["request_id"] = d["deployments"][0]["request_id"]
	_case("same_deploy_request_id_different_instances", d)
	d = valid.duplicate(true)
	d["deployments"][0].erase("request_id")
	_case("idempotent_replay_flag_bypasses_missing_request_id", d)
	d = valid.duplicate(true)
	d["deployments"][0]["t"] = -5.0
	d["deployments"][0]["from_state"] = "DRAFT"
	d["deployments"][0]["to_state"] = "VALIDATED"
	_case("deployment_negative_time_and_transition_disagrees_current_state", d)
	d = valid.duplicate(true)
	d["fleets"][0]["roster"][0]["entity_instance_id"] = "I-AL1"
	_case("player_roster_references_ally_instance", d)
	d = valid.duplicate(true)
	d["commands"].append(d["commands"][0].duplicate(true))
	_case("duplicate_command_id", d)
	d = valid.duplicate(true)
	d["commands"][0].erase("command_id")
	_case("missing_command_id", d)
	d = valid.duplicate(true)
	d["objectives"][0]["threshold"] = 9007199254740992
	_case("native_int_exceeds_safe_integer", d)
	d = valid.duplicate(true)
	d["ledgers"][0]["mass_kg"] = INF
	_case("infinite_mass", d)
	d = valid.duplicate(true)
	d["ledgers"][0].erase("ammo")
	d["ledgers"][0].erase("fuel_kg")
	d["ledgers"][0].erase("cooldown_s_count")
	_case("ledger_without_ammo_fuel_cooldown", d)
	d = valid.duplicate(true)
	d["ledgers"][0]["fuel_kg"] = 3000.5
	_case("fractional_kg_fuel_rejected", d)
	var output_path = OS.get_environment("JC_K0_AUDIT_OUTPUT")
	if output_path != "":
		var out = FileAccess.open(output_path, FileAccess.WRITE)
		out.store_string(JSON.stringify({"head":"dc3821eda91d25f14e44dd9f57e6f5a985e04a9c","cases":results}, "\t"))
		out.close()
	quit(0)

func _case(name: String, doc: Dictionary) -> void:
	var result: Dictionary = Contracts.validate(doc)
	var row = {"case":name,"ok":result.get("ok"),"errors":result.get("errors")}
	results.append(row)
	print("[K0-AUDIT] ", JSON.stringify(row))

