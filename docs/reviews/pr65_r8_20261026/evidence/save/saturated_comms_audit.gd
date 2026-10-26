extends "res://tests/a0_save_cost_probe.gd"

func make_case():
	var sess = GameSessionScript.new(_seed)
	sess.time.scale = 1.0
	sess.time.paused = false
	for i in range(50):
		sess.tick(1.0)
	_control_op(sess, 0)
	return sess

func saturate(sess) -> void:
	while sess.comms.events.size() < sess.comms.MAX_EVENTS:
		var ev: Dictionary = sess.comms.events[-1].duplicate(true)
		ev.seq = sess.comms.events.size() + 1
		sess.comms.events.append(ev)
	sess.comms._event_seq = sess.comms.MAX_EVENTS

func _run() -> void:
	var err = change_scene_to_file(MAIN_MENU)
	if err != OK:
		quit(2)
		return
	var boot = await _await_v1_hud()
	if boot.hud == null:
		quit(2)
		return
	_seed = boot.hud.get("binder").get("session")._seed.duplicate(true)
	var original = make_case()
	var restored = GameSessionScript.new()
	var lr = restored.load_state(original.save_state())
	saturate(original)
	saturate(restored)
	var before_counts = {"original": original.comms.events.size(),
		"restored": restored.comms.events.size()}
	var baseline: Array = _behavior_violations(original, restored, 1)
	var send_o = original.send_comms("apsis", "harmattan", "LD")
	var send_r = restored.send_comms("apsis", "harmattan", "LD")
	var pending_count = restored.comms.pending.size()
	if pending_count > 0:
		restored.comms.pending[0].text = "TAMPERED_DELIVERY_CONTENT"
	var immediate: Array = _full_state_violations(original, restored)
	var behavior: Array = _behavior_violations(original, restored, 1)
	var matched := false
	for v in behavior:
		if String(v.get("area", "")) == "comms.events.new":
			matched = true
	var result = {"head": OS.get_environment("A07_HEAD"), "load_ok": lr.ok,
		"history_cap": original.comms.MAX_EVENTS, "counts_before": before_counts,
		"counts_after": {"original": original.comms.events.size(),
			"restored": restored.comms.events.size()},
		"baseline": baseline, "send_original": send_o.ok, "send_restored": send_r.ok,
		"pending_count": pending_count, "immediate": immediate,
		"behavior": behavior, "output_detected": matched,
		"delivered_original": original.comms.events[-1],
		"delivered_restored": restored.comms.events[-1]}
	print("R8_SATURATED ", JSON.stringify(result))
	FileAccess.open(OS.get_environment("R8_SATURATED_OUT"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	_finished = true
	_restore_env()
	quit(0 if baseline.is_empty() and matched and bool(lr.ok) else 1)
