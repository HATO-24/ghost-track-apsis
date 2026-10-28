extends "res://tests/jc_identity_pipeline_probe.gd"

func _run() -> void:
	var report := {"head": "7293058d1c0d3cdedceff1fae6233523e7f8b313", "cases": {}}
	# TTL: observed_t starts authority TTL; test actual combat consumer after true expiry.
	var s = _new()
	_register_combat_track(s, "ttl_target")
	var t0 := float(s.now_s())
	var ing: Dictionary = s.identity_ingest("player_intel", _ev("ttl_target", "transponder", "friend", 0.9, {"observed_t": t0, "ttl_s": 5.0}))
	var ttl_before: Dictionary = s.identity_operational("player_intel", "ttl_target")
	for i in range(11):
		s.tick(1.0)
	var ttl_after: Dictionary = s.identity_operational("player_intel", "ttl_target")
	var ci: Dictionary = s.combat_identity("ttl_target")
	s._sync_combat_identity("ttl_target")
	var combat_track: Dictionary = s.combat_service.track("ttl_target")
	var ttl_binder = Binder.new()
	ttl_binder.session = s
	var hud_after: Dictionary = ttl_binder.ident_view({"track_id": "ttl_target"})
	# Delayed arrival: received now but observed five seconds ago; TTL must already be stale.
	var delayed = _new()
	for i0 in range(8):
		delayed.tick(1.0)
	var delayed_ingest: Dictionary = delayed.identity_ingest("player_intel", _ev("delayed_target", "transponder", "friend", 0.9, {"observed_t": 0.0, "received_t": float(delayed.now_s()), "ttl_s": 5.0}))
	var delayed_op: Dictionary = delayed.identity_operational("player_intel", "delayed_target")
	report["cases"]["ttl_consumer"] = {"ingest": ing, "t0": t0, "now": s.now_s(), "before": ttl_before, "after": ttl_after, "combat_identity": ci, "combat_track_identity": combat_track.get("identity", ""), "hud_identity": hud_after.get("identity", ""), "hud_known": hud_after.get("known", false), "svc_assessment": s.identity_get_for("player_intel", "ttl_target"), "delayed_arrival": {"now": delayed.now_s(), "ingest": delayed_ingest, "operational": delayed_op}}

	# Late evidence: immediately ignored by op, yet remains in service input and changes next tick.
	var late_session = _new()
	late_session.tick(1.0)
	late_session.tick(1.0)
	var newer: Dictionary = late_session.identity_ingest("player_intel", _ev("late_target", "optical", "friend", 0.9, {"observed_t": 2.0, "received_t": 2.0, "ttl_s": 20.0, "category": "sensor"}))
	var old_late: Dictionary = late_session.identity_ingest("player_intel", _ev("late_target", "transponder", "hostile", 0.9, {"observed_t": 1.0, "received_t": 2.0, "ttl_s": 20.0}))
	var late_immediate: Dictionary = late_session.identity_operational("player_intel", "late_target")
	var assessment_immediate: Dictionary = late_session.identity_get_for("player_intel", "late_target")
	late_session.tick(1.0)
	var late_after_tick: Dictionary = late_session.identity_operational("player_intel", "late_target")
	var assessment_after_tick: Dictionary = late_session.identity_get_for("player_intel", "late_target")
	# Control: same valid evidence ingested old-first then new; no late rejection.
	var control = _new()
	control.tick(1.0)
	control.tick(1.0)
	var old_first: Dictionary = control.identity_ingest("player_intel", _ev("order_target", "transponder", "hostile", 0.9, {"observed_t": 1.0, "received_t": 2.0, "ttl_s": 20.0}))
	var new_second: Dictionary = control.identity_ingest("player_intel", _ev("order_target", "optical", "friend", 0.9, {"observed_t": 2.0, "received_t": 2.0, "ttl_s": 20.0, "category": "sensor"}))
	var control_operational: Dictionary = control.identity_operational("player_intel", "order_target")
	control.tick(1.0)
	var control_after_tick: Dictionary = control.identity_operational("player_intel", "order_target")
	report["cases"]["late_contamination"] = {"newer_ingest": newer, "late_ingest": old_late, "immediate_operational": late_immediate, "immediate_service_assessment": assessment_immediate, "after_one_tick_operational": late_after_tick, "after_one_tick_assessment": assessment_after_tick, "control_old_first": old_first, "control_new_second": new_second, "control_operational": control_operational, "control_after_one_tick": control_after_tick}

	# Actual filesystem roundtrip for a non-own owner and pending query; compare 10 tick outputs incl event IDs.
	var src = _new()
	var rst: Dictionary = src.identity_ingest("ally_intel", _ev("restore_target", "optical", "neutral", 0.7, {"observed_t": float(src.now_s()), "ttl_s": 5.0, "category": "sensor"}))
	# Deliberately hand-inserted only to verify pending-query serialization; this does not test its runtime lifecycle.
	src._identity_pending_queries["ally_intel"] = [{"query_id": "Q-DIAG-1", "target_id": "restore_target", "eta": 3.0}]
	var save_path := "user://jc_a02_diag_ttl_restore_20261027.json"
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(src.save_state())
	f.close()
	var dst = _new()
	var load_result: Dictionary = dst.load_state(FileAccess.get_file_as_string(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var pre_pending = dst._identity_pending_queries.duplicate(true)
	var pre_events = (dst._identity_owners["ally_intel"].events as Array).duplicate(true)
	var src_trace: Array = []
	var dst_trace: Array = []
	for i2 in range(10):
		src.tick(1.0)
		dst.tick(1.0)
		var svc_src = src._identity_owners["ally_intel"]
		var svc_dst = dst._identity_owners["ally_intel"]
		var op_src: Dictionary = src.identity_operational("ally_intel", "restore_target")
		var op_dst: Dictionary = dst.identity_operational("ally_intel", "restore_target")
		var ev_src: Array = svc_src.events
		var ev_dst: Array = svc_dst.events
		src_trace.append({"tick": i2 + 1, "event_id": ev_src[-1].get("event_id", "") if not ev_src.is_empty() else "", "identity": op_src.get("identity", ""), "state": op_src.get("identity_state", ""), "confidence": op_src.get("identity_confidence", -1.0)})
		dst_trace.append({"tick": i2 + 1, "event_id": ev_dst[-1].get("event_id", "") if not ev_dst.is_empty() else "", "identity": op_dst.get("identity", ""), "state": op_dst.get("identity_state", ""), "confidence": op_dst.get("identity_confidence", -1.0)})
	report["cases"]["filesystem_restore_10_ticks"] = {"ingest": rst, "load": load_result, "restore_mode": dst._identity_restore_mode, "pending_restored": pre_pending, "pending_fixture_kind": "manually_inserted_serialization_only", "owner_restored": dst._identity_owners.has("ally_intel"), "event_count_before_ticks": pre_events.size(), "source_trace": src_trace, "restored_trace": dst_trace, "traces_equal": src_trace == dst_trace}
	var out_path := "C:/Users/ASUS/.codex/worktrees/jc-a02-validation/GHOST TRACK_APSIS/.test-results/sol-a02/ttl_restore/result.json"
	var of := FileAccess.open(out_path, FileAccess.WRITE)
	of.store_string(JSON.stringify(report, "\t"))
	of.close()
	print("DIAG TTL/RESTORE report=", out_path)
	print(JSON.stringify({"ttl_state": ttl_after.get("identity_state", ""), "ttl_identity": ttl_after.get("identity", ""), "combat_identity": ci.get("identity", ""), "hud_identity": hud_after.get("identity", ""), "delayed_state": delayed_op.get("identity_state", ""), "delayed_observed_t": delayed_op.get("identity_observed_t", -1.0), "late_immediate": late_immediate.get("identity", ""), "late_after_tick": late_after_tick.get("identity", ""), "late_state_after_tick": late_after_tick.get("identity_state", ""), "restore_equal": src_trace == dst_trace, "restore_mode": dst._identity_restore_mode}))
	_finish()
