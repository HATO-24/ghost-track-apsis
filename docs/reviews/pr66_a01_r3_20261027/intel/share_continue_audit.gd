extends "res://tests/jc_authority_intel_probe.gd"

func _run() -> void:
	var s = GS.new(_seed())
	for i in range(2):
		s.tick(1.0)
	var row = {"observation_id": "PENDING-ONE", "observer_id": "ally_ship",
		"target_id": "pending_contact", "sensor": "optical", "source": "optical",
		"observed_t": 2.0, "quality": 0.6, "range_km": 800.0,
		"bearing_deg": 45.0, "share_authorized_by": "ally_intel"}
	var q = s.queue_intel_share("ally_ship", "own_ship", "player_intel", row)
	var before = {"view": s.intel_view("player_intel"), "pending": s.pending_intel_shares(), "comms_pending": s.comms.pending.duplicate(true)}
	var save = s.save_state()
	var restored = GS.new()
	var load = restored.load_state(save)
	var restored_before = {"view": restored.intel_view("player_intel"), "pending": restored.pending_intel_shares(), "comms_pending": restored.comms.pending.duplicate(true)}
	var timeline: Array = []
	for i in range(8):
		var a = s.tick(1.0)
		var b = restored.tick(1.0)
		timeline.append({"t": s.now_s(), "original_tick_ok": a.get("ok", false), "restored_tick_ok": b.get("ok", false),
			"original_ids": _ids(s.intel_view("player_intel")), "restored_ids": _ids(restored.intel_view("player_intel")),
			"original_pending": s.pending_intel_shares().size(), "restored_pending": restored.pending_intel_shares().size()})
	var n0: int = restored.intel_view("player_intel").observations.size()
	var dup = restored.receive_intel_observation("player_intel", row,
		{"delivery_id": String(q.get("delivery_id", "")), "received_t": restored.now_s(),
			"now_t": restored.now_s(), "share_authorized_by": "ally_intel"})
	var n1: int = restored.intel_view("player_intel").observations.size()
	var same_timeline := true
	for item in timeline:
		if JSON.stringify(item.original_ids) != JSON.stringify(item.restored_ids) \
				or item.original_pending != item.restored_pending:
			same_timeline = false
	var direct_closed := ("pending_contact" in _ids(s.intel_view("player_intel"))) \
		and (s.intel_view("opfor_intel").tracks as Array).is_empty() \
		and float(s.intel_view("player_intel").tracks[0].last_received_t) == 5.0
	var duplicate_closed := n0 == n1 and bool(dup.get("duplicated", false))
	var continuation_closed := same_timeline \
		and JSON.stringify(_sorted_sig(s.intel_view("player_intel"))) \
			== JSON.stringify(_sorted_sig(restored.intel_view("player_intel")))
	var result = {"head": "8b4cf990021bafe0f5b2945039c850b5c985cf5a", "queued": q, "before": before,
		"load": load, "restored_before": restored_before, "timeline": timeline,
		"original_view": s.intel_view("player_intel"), "restored_view": restored.intel_view("player_intel"),
		"original_last_delivery": s.last_intel_share_result(), "restored_last_delivery": restored.last_intel_share_result(),
		"third_owner_original": s.intel_view("opfor_intel"), "third_owner_restored": restored.intel_view("opfor_intel"),
		"duplicate": {"result": dup, "before": n0, "after": n1},
		"normal_arrival_closed": direct_closed, "duplicate_closed": duplicate_closed,
		"continuation_equal": continuation_closed,
		"closed": bool(load.get("ok", false)) and direct_closed and duplicate_closed and continuation_closed}
	var f = FileAccess.open(OS.get_environment("A01_R3_SHARE_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	print("A01_R3_SHARE_RESULT ", JSON.stringify(result))
	_finished = true
	quit(0 if result.closed else 1)
