extends "res://tests/jc_authority_intel_probe.gd"

const SaveServiceAudit := preload("res://scripts/core/save_service.gd")

func _snap(s) -> Dictionary:
	return {"t": s.now_s(), "view": s.intel_view("player_intel"),
		"pending": s.pending_intel_shares(), "comms_pending": s.comms.pending.duplicate(true),
		"third_owner": s.intel_view("opfor_intel")}

func _duplicate_audit(s, row: Dictionary, delivery_id: String) -> Dictionary:
	var before: Dictionary = s.intel_view("player_intel")
	var dup: Dictionary = s.receive_intel_observation("player_intel", row,
		{"delivery_id": delivery_id, "received_t": s.now_s(),
			"now_t": s.now_s(), "share_authorized_by": "ally_intel"})
	var after: Dictionary = s.intel_view("player_intel")
	var n0: int = before.observations.size()
	var n1: int = after.observations.size()
	return {"result": dup, "before": n0, "after": n1,
		"closed": n0 == 1 and n1 == 1 and bool(dup.get("duplicated", false)) \
			and JSON.stringify(_sorted_sig(before)) == JSON.stringify(_sorted_sig(after))}

func _mode_audit(mode: String) -> Dictionary:
	# Identical R3 seed and legal fixture: t=2 send, three-second link, ETA=5.
	var s = GS.new(_seed())
	var fixture_ticks: Array = []
	for i in range(2):
		fixture_ticks.append(s.tick(1.0))
	var row = {"observation_id": "PENDING-ONE", "observer_id": "ally_ship",
		"target_id": "pending_contact", "sensor": "optical", "source": "optical",
		"observed_t": 2.0, "quality": 0.6, "range_km": 800.0,
		"bearing_deg": 45.0, "share_authorized_by": "ally_intel"}
	var q: Dictionary = s.queue_intel_share("ally_ship", "own_ship", "player_intel", row)
	var before := _snap(s)
	var save_result: Dictionary = {}
	var load_result: Dictionary = {}
	var restored
	if mode == "memory":
		var save: String = s.save_state()
		save_result = {"ok": save != "", "bytes": save.length(), "entry": "GameSession.save_state"}
		restored = GS.new()
		load_result = restored.load_state(save)
	else:
		# Use the shipped public file API; preserve its actual file as evidence.
		var svc = SaveServiceAudit.new(OS.get_environment("A01_R4_SHARE_SAVE_ROOT"))
		save_result = svc.save_session(s, "save", {"chapter": "A01_R4", "location": "inflight_eta5"})
		var lr: Dictionary = svc.load_session("save")
		load_result = lr.duplicate()
		load_result.erase("session")
		load_result.erase("payload")
		restored = lr.get("session")
	if restored == null:
		return {"mode": mode, "queued": q, "before": before,
			"save": save_result, "load": load_result, "closed": false, "fixture_failed": true}
	var restored_before := _snap(restored)
	var timeline: Array = []
	var same_timeline := true
	var ticks_ok := true
	var eta_visibility := true
	var third_owner_empty := true
	var first_original_visible := -1.0
	var first_restored_visible := -1.0
	for i in range(10):
		var a: Dictionary = s.tick(1.0)
		var b: Dictionary = restored.tick(1.0)
		var av: Dictionary = s.intel_view("player_intel")
		var bv: Dictionary = restored.intel_view("player_intel")
		var aid: Array = _ids(av)
		var bid: Array = _ids(bv)
		var equal_sig := JSON.stringify(_sorted_sig(av)) == JSON.stringify(_sorted_sig(bv))
		var expected_visible: bool = s.now_s() >= 5.0
		if "pending_contact" in aid and first_original_visible < 0.0:
			first_original_visible = s.now_s()
		if "pending_contact" in bid and first_restored_visible < 0.0:
			first_restored_visible = restored.now_s()
		ticks_ok = ticks_ok and bool(a.get("ok", false)) and bool(b.get("ok", false))
		eta_visibility = eta_visibility and (("pending_contact" in aid) == expected_visible) \
			and (("pending_contact" in bid) == expected_visible)
		third_owner_empty = third_owner_empty \
			and (s.intel_view("opfor_intel").tracks as Array).is_empty() \
			and (restored.intel_view("opfor_intel").tracks as Array).is_empty()
		var ap: int = s.pending_intel_shares().size()
		var bp: int = restored.pending_intel_shares().size()
		var ac: int = s.comms.pending.size()
		var bc: int = restored.comms.pending.size()
		same_timeline = same_timeline and equal_sig and ap == bp and ac == bc \
			and s.now_s() == restored.now_s()
		timeline.append({"t": s.now_s(), "restored_t": restored.now_s(),
			"original_tick_ok": a.get("ok", false), "restored_tick_ok": b.get("ok", false),
			"original_ids": aid, "restored_ids": bid,
			"original_view": av, "restored_view": bv, "view_signature_equal": equal_sig,
			"original_pending": ap, "restored_pending": bp,
			"original_comms_pending": ac, "restored_comms_pending": bc})
	var original_view: Dictionary = s.intel_view("player_intel")
	var restored_view: Dictionary = restored.intel_view("player_intel")
	var original_track: Dictionary = _track(original_view, "pending_contact")
	var restored_track: Dictionary = _track(restored_view, "pending_contact")
	var direct_closed := first_original_visible == 5.0 and first_restored_visible == 5.0 \
		and eta_visibility and third_owner_empty \
		and float(original_track.get("last_observed_t", -1.0)) == 2.0 \
		and float(restored_track.get("last_observed_t", -1.0)) == 2.0 \
		and float(original_track.get("last_received_t", -1.0)) == 5.0 \
		and float(restored_track.get("last_received_t", -1.0)) == 5.0
	var original_duplicate := _duplicate_audit(s, row, String(q.get("delivery_id", "")))
	var restored_duplicate := _duplicate_audit(restored, row, String(q.get("delivery_id", "")))
	var duplicate_closed := bool(original_duplicate.closed) and bool(restored_duplicate.closed)
	var before_pending: Array = before.comms_pending
	var restored_pending: Array = restored_before.comms_pending
	var pending_restored := before_pending.size() == 1 and restored_pending.size() == 1 \
		and float(before_pending[0].get("arrive_t", -1.0)) == 5.0 \
		and float(restored_pending[0].get("arrive_t", -1.0)) == 5.0 \
		and (before.view.tracks as Array).is_empty() and (restored_before.view.tracks as Array).is_empty()
	var continuation_closed := pending_restored and same_timeline and ticks_ok \
		and JSON.stringify(_sorted_sig(original_view)) == JSON.stringify(_sorted_sig(restored_view))
	return {"mode": mode, "queued": q, "fixture_ticks": fixture_ticks,
		"before": before, "save": save_result, "load": load_result,
		"restored_before": restored_before, "timeline": timeline,
		"original_view": original_view, "restored_view": restored_view,
		"original_last_delivery": s.last_intel_share_result(), "restored_last_delivery": restored.last_intel_share_result(),
		"third_owner_original": s.intel_view("opfor_intel"), "third_owner_restored": restored.intel_view("opfor_intel"),
		"first_original_visible_t": first_original_visible, "first_restored_visible_t": first_restored_visible,
		"original_duplicate": original_duplicate, "restored_duplicate": restored_duplicate,
		"normal_arrival_closed": direct_closed, "duplicate_closed": duplicate_closed,
		"pending_eta_restored": pending_restored, "continuation_equal": continuation_closed,
		"closed": bool(q.get("ok", false)) and bool(save_result.get("ok", false)) \
			and bool(load_result.get("ok", false)) and direct_closed and duplicate_closed and continuation_closed}

func _run() -> void:
	var memory: Dictionary = _mode_audit("memory")
	var file: Dictionary = _mode_audit("file")
	var result := {"head": "eb4b98530b589dd5c452a78d46549660985557d3",
		"code_head": "c704f85952eb33ec44c1ac21dfef95d2f8b6a032",
		"memory": memory, "file": file, "closed": bool(memory.closed) and bool(file.closed)}
	var f = FileAccess.open(OS.get_environment("A01_R4_SHARE_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	print("A01_R4_SHARE_RESULT ", JSON.stringify(result))
	_finished = true
	quit(0 if result.closed else 1)
