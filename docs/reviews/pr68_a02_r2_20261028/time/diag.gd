extends "res://tests/jc_identity_pipeline_probe.gd"

const OUT := "C:/Users/ASUS/.codex/worktrees/jc-a02-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a02-r2/time/result.json"
const SAVE := "user://jc_a02_r5_natural_pending_20261028.json"

func _run() -> void:
	var report := {"head": "4a658699868b8d046ec5472f9c4b9ea204af6be9", "cases": {}}

	# R4: TTL validity reaches actual identity consumers and aliases agree.
	var s = _new()
	_register_combat_track(s, "ttl_target")
	var t0 := float(s.now_s())
	var ing: Dictionary = s.identity_ingest("player_intel", _ev("ttl_target", "transponder", "friend", 0.9, {"observed_t": t0, "ttl_s": 5.0}))
	var before: Dictionary = s.identity_operational("player_intel", "ttl_target")
	for i in range(11):
		s.tick(1.0)
	var after: Dictionary = s.identity_operational("player_intel", "ttl_target")
	var combat: Dictionary = s.combat_identity("ttl_target")
	s._sync_combat_identity("ttl_target")
	var track: Dictionary = s.combat_service.track("ttl_target")
	var binder = Binder.new()
	binder.session = s
	var hud: Dictionary = binder.ident_view({"track_id": "ttl_target"})
	var delayed = _new()
	for j in range(8):
		delayed.tick(1.0)
	var delayed_ingest: Dictionary = delayed.identity_ingest("player_intel", _ev("delayed_target", "transponder", "friend", 0.9, {"observed_t": 0.0, "received_t": float(delayed.now_s()), "ttl_s": 5.0}))
	var delayed_op: Dictionary = delayed.identity_operational("player_intel", "delayed_target")
	report["cases"]["R4_ttl_consumers_alias"] = {"ingest": ing, "t0": t0, "before": before, "now": s.now_s(), "after": after, "alias_equal": String(after.get("state", "")) == String(after.get("identity_state", "")), "combat_identity": combat.get("identity", ""), "combat_state": combat.get("identity_state", combat.get("state", "")), "combat_track_identity": track.get("identity", ""), "hud_identity": hud.get("identity", ""), "hud_valid": hud.get("valid", false), "hud_validity": hud.get("validity", ""), "hud_effective_identity": hud.get("effective_identity", ""), "hud_state": hud.get("identity_state", hud.get("state", "")), "delayed": {"ingest": delayed_ingest, "operational": delayed_op}}

	# R4: legal non-negative timestamps, same TTL, late event must not leak into next-tick operational state.
	var late = _new()
	late.tick(1.0)
	late.tick(1.0)
	var new_ingest: Dictionary = late.identity_ingest("player_intel", _ev("late_target", "optical", "friend", 0.9, {"observed_t": 2.0, "received_t": 2.0, "ttl_s": 20.0, "category": "sensor"}))
	var late_ingest: Dictionary = late.identity_ingest("player_intel", _ev("late_target", "transponder", "hostile", 0.9, {"observed_t": 1.0, "received_t": 2.0, "ttl_s": 20.0}))
	var late_now: Dictionary = late.identity_operational("player_intel", "late_target")
	var late_a_now: Dictionary = late.identity_get_for("player_intel", "late_target")
	late.tick(1.0)
	var late_next: Dictionary = late.identity_operational("player_intel", "late_target")
	var late_a_next: Dictionary = late.identity_get_for("player_intel", "late_target")
	var control = _new()
	control.tick(1.0)
	control.tick(1.0)
	var old_first: Dictionary = control.identity_ingest("player_intel", _ev("control_target", "transponder", "hostile", 0.9, {"observed_t": 1.0, "received_t": 2.0, "ttl_s": 20.0}))
	var new_second: Dictionary = control.identity_ingest("player_intel", _ev("control_target", "optical", "friend", 0.9, {"observed_t": 2.0, "received_t": 2.0, "ttl_s": 20.0, "category": "sensor"}))
	var control_now: Dictionary = control.identity_operational("player_intel", "control_target")
	control.tick(1.0)
	var control_next: Dictionary = control.identity_operational("player_intel", "control_target")
	report["cases"]["R4_late_continuity"] = {"newer_ingest": new_ingest, "late_ingest": late_ingest, "immediate_operational": late_now, "immediate_assessment": late_a_now, "next_tick_operational": late_next, "next_tick_assessment": late_a_next, "control_old_first": old_first, "control_new_second": new_second, "control_immediate": control_now, "control_next_tick": control_next}

	# Original owner continuity + R5: real owner evidence and a naturally created pending IFF query.
	# Save immediately after API-created pending query, then load those bytes into a fresh session.
	var src = _new()
	var owner_ingest: Dictionary = src.identity_ingest("ally_intel", _ev("restore_target", "optical", "neutral", 0.7, {"observed_t": float(src.now_s()), "ttl_s": 5.0, "category": "sensor"}))
	for k in range(2):
		src.tick(1.0)
	var query: Dictionary = src.identity_iff_query("player_intel", "probe_ship", {"latency_s": 3.0})
	var queue_at_save: Array = (src._identity_query_queue as Array).duplicate(true)
	var state_text: String = src.save_state()
	var sf := FileAccess.open(SAVE, FileAccess.WRITE)
	if sf == null:
		push_error("Could not open real save file: " + SAVE)
		quit(2)
		return
	sf.store_string(state_text)
	sf.close()
	var loaded_text := FileAccess.get_file_as_string(SAVE)
	var dst = _new()
	var load_result: Dictionary = dst.load_state(loaded_text)
	var queue_after_load: Array = (dst._identity_query_queue as Array).duplicate(true)
	var pending_fixture_kind := "natural_identity_iff_query_api"
	var pre_ally_events: Array = (src._identity_owners["ally_intel"].events as Array).duplicate(true)
	var src_trace: Array = []
	var dst_trace: Array = []
	var per_tick_equal: Array[bool] = []
	for n in range(10):
		src.tick(1.0)
		dst.tick(1.0)
		var rows_s := _snapshot(src)
		var rows_d := _snapshot(dst)
		src_trace.append(rows_s)
		dst_trace.append(rows_d)
		per_tick_equal.append(rows_s == rows_d)
	var save_removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK
	var pending_result: Dictionary = src.identity_operational("player_intel", "probe_ship")
	report["cases"]["R5_natural_pending_file_10ticks"] = {"owner_ingest": owner_ingest, "query": query, "query_state_at_creation": query.get("state", ""), "pending_fixture_kind": pending_fixture_kind, "queue_at_save": queue_at_save, "load": load_result, "restore_mode": dst._identity_restore_mode, "queue_after_load": queue_after_load, "owner_restored": dst._identity_owners.has("ally_intel"), "ally_event_count_before_ticks": pre_ally_events.size(), "save_file_removed_after_load": save_removed, "source_trace": src_trace, "restored_trace": dst_trace, "per_tick_equal": per_tick_equal, "traces_equal": src_trace == dst_trace, "pending_operational_final": pending_result, "remaining_queue_source": src._identity_query_queue, "remaining_queue_restored": dst._identity_query_queue}

	var of := FileAccess.open(OUT, FileAccess.WRITE)
	if of == null:
		push_error("Could not open report file: " + OUT)
		quit(2)
		return
	of.store_string(JSON.stringify(report, "\t"))
	of.close()
	print("JC-A02 R4/R5 TIME DIAGNOSTIC report=", OUT)
	print(JSON.stringify({"ttl_alias_equal": report["cases"]["R4_ttl_consumers_alias"]["alias_equal"], "hud_ttl": {"identity": hud.get("identity", ""), "valid": hud.get("valid", false), "validity": hud.get("validity", ""), "effective_identity": hud.get("effective_identity", "")}, "late_next": late_next, "late_control_next": control_next, "natural_pending": query, "pending_queue_at_save": queue_at_save, "load_ok": load_result.get("ok", false), "trace_equal": src_trace == dst_trace, "pending_final": pending_result, "report": OUT}))
	quit(0)


func _snapshot(s) -> Dictionary:
	var owners := {}
	for owner in ["player_intel", "ally_intel", "opfor_intel"]:
		var restore: Dictionary = s.identity_operational(owner, "restore_target")
		var queried: Dictionary = s.identity_operational(owner, "probe_ship")
		var svc = s._identity_owners.get(owner, null)
		var event_ids: Array = []
		if svc != null:
			for ev in svc.events:
				if ev is Dictionary:
					event_ids.append(String((ev as Dictionary).get("event_id", "")))
		owners[owner] = {"restore_identity": restore.get("identity", ""), "restore_state": restore.get("identity_state", restore.get("state", "")), "restore_confidence": restore.get("identity_confidence", -1.0), "query_identity": queried.get("identity", ""), "query_state": queried.get("identity_state", queried.get("state", "")), "query_confidence": queried.get("identity_confidence", -1.0), "query_iff_state": queried.get("iff_state", ""), "event_ids": event_ids}
	var queue: Array = (s._identity_query_queue as Array).duplicate(true)
	var pending: Dictionary = s.identity_operational("player_intel", "probe_ship")
	return {"t": s.now_s(), "owners": owners, "pending_query_queue": queue, "query_result": {"identity": pending.get("identity", ""), "state": pending.get("identity_state", pending.get("state", "")), "iff_state": pending.get("iff_state", ""), "confidence": pending.get("identity_confidence", -1.0)}}
