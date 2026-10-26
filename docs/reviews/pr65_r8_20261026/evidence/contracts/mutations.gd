extends SceneTree
const C = preload("res://scripts/core/jc_contracts.gd")
const FIX = "res://tests/fixtures/jc_contracts/valid_three_domains.json"
var rows: Array = []
func _initialize() -> void:
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	_case("baseline_valid", valid, true)
	var d: Dictionary = valid.duplicate(true)
	d["instances"][1]["selected"] = false
	d["instances"][1]["deployment_state"] = "DRAFT"
	d["deployments"].remove_at(1)
	d["commands"][0]["shooter_id"] = "I-A2"
	_case("r6_unselected_undeployed_shooter", d, false)
	d = valid.duplicate(true)
	d["observation_shares"][0]["observer_id"] = "I-OP1"
	_case("r6_enemy_observer_player_selfauth", d, false)
	d = valid.duplicate(true)
	d["deployments"][0]["t"] = -5.0
	_case("r6_deployment_negative_t", d, false)
	d = valid.duplicate(true)
	d["deployments"][0]["from_state"] = "DRAFT"
	d["deployments"][0]["to_state"] = "VALIDATED"
	_case("r6_deployment_final_state_mismatch", d, false)
	d = valid.duplicate(true)
	d["commands"][0].erase("command_id")
	_case("r6_missing_command_id", d, false)
	d = valid.duplicate(true)
	d["commands"][0].erase("seq")
	_case("missing_seq", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["lifecycle"]["lifecycle_version"] = "UNSUPPORTED-999"
	_case("unknown_lifecycle_version", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["lifecycle"]["request"]["t"] = 1000.0
	d["commands"][0]["lifecycle"]["receipt"]["t"] = 2.0
	d["commands"][0]["lifecycle"]["execution"]["t"] = 1.0
	_case("reverse_lifecycle_time", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["lifecycle"]["receipt"]["state"] = "rejected"
	d["commands"][0]["lifecycle"]["execution"]["state"] = "completed"
	_case("rejected_then_completed", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["lifecycle"]["execution"]["request_id"] = "OTHER-REQ"
	_case("wrong_request_correlation", d, false)
	d = valid.duplicate(true)
	var second: Dictionary = d["commands"][0].duplicate(true)
	second["command_id"] = "CMD-2"
	d["commands"].append(second)
	_case("duplicate_event_id_seq_request_across_commands", d, false)
	d = valid.duplicate(true)
	d["commands"][0]["shooter_id"] = "I-A2"
	d["commands"][0]["legacy_context"] = "own_ship"
	d["commands"][0]["own_entity_instance_id"] = "I-A2"
	_case("legacy_self_declared_other_own", d, true)
	d = valid.duplicate(true)
	d["observation_shares"][2].erase("received_by_intel_owner_id")
	_case("cross_owner_missing_explicit_receiver", d, false)
	var out := FileAccess.open(OS.get_environment("JC_K0_AUDIT_OUTPUT"), FileAccess.WRITE)
	out.store_string(JSON.stringify({"head":"9d0f3b4380275b0a30fffb4a29fa5c44ef58165f","cases":rows}, "\t"))
	out.close()
	quit(0)
func _case(label: String, d: Dictionary, expected_ok: bool) -> void:
	var r: Dictionary = C.validate(d)
	var gating := not (label in ["reverse_lifecycle_time", "rejected_then_completed", "duplicate_event_id_seq_request_across_commands", "legacy_self_declared_other_own"])
	var row := {"case":label,"gating":gating,"ok":r["ok"],"expected_ok":expected_ok,"matches":r["ok"] == expected_ok,"errors":r["errors"]}
	rows.append(row)
	print("[R8-K0-AUDIT] ", JSON.stringify(row))


