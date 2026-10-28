extends "res://tests/jc_ew_observation_probe.gd"

const OUT := "C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/time_restore/expiry.json"

func _run() -> void:
	var report := {"head": "6bd919aa19898bbf31f5dd7c3287befc47392877", "cases": {}}
	var s = _new()
	var applied: Dictionary = s.apply_ew({"effect": "noise_jam",
		"target_id": "raider_2", "severity": 0.5, "duration_s": 1.0,
		"source_id": "EXPIRY-BOUNDARY", "band": "radar"})
	var effect_initial: Array = (s.ew_service.effects as Array).duplicate(true)
	var timeline: Array = []
	for i in range(2):
		var pre := {"session_now": s.now_s(), "ew_t": s.ew_service.t,
			"ew_step_count": s.ew_service.step_count,
			"active_effects": s.ew_service.active("raider_2", "radar"),
			"ew_effect_rows": (s.ew_service.effects as Array).duplicate(true),
			"sample_count": (s.ew_observation_samples() as Array).size()}
		var before_n := int(pre.sample_count)
		s.tick(TICK_DT)
		var all_samples: Array = s.ew_observation_samples()
		var tick_samples: Array = []
		for raw in all_samples.slice(before_n, all_samples.size()):
			if raw is Dictionary and String((raw as Dictionary).get("target_id", "")) == "raider_2":
				tick_samples.append((raw as Dictionary).duplicate(true))
		var row := {"pre": pre, "post": {"session_now": s.now_s(),
			"ew_t": s.ew_service.t, "ew_step_count": s.ew_service.step_count,
			"active_effects": s.ew_service.active("raider_2", "radar"),
			"ew_effect_rows": (s.ew_service.effects as Array).duplicate(true),

			"owner_measurement": s.owner_measurement_quality("player_intel", "raider_2")},
			"new_target_samples": tick_samples}
		timeline.append(row)
	report["cases"]["noise_half_duration_1s"] = {"apply": applied,
		"effect_initial": effect_initial, "ticks": timeline,
		"sample_vs_end": _summarize_samples(timeline),
		"sample_semantics": "observational only; sample is before EW step within each GameSession tick"}

	var clean = _new()
	var clean_pre := {"session_now": clean.now_s(), "ew_t": clean.ew_service.t,
		"ew_step_count": clean.ew_service.step_count,
		"active_effects": clean.ew_service.active("raider_2", "radar")}
	clean.tick(TICK_DT)
	var clean_samples: Array = []
	for raw2 in clean.ew_observation_samples():
		if raw2 is Dictionary and String((raw2 as Dictionary).get("target_id", "")) == "raider_2":
			clean_samples.append((raw2 as Dictionary).duplicate(true))
	report["cases"]["ew_zero_first_tick"] = {"pre": clean_pre,
		"post": {"session_now": clean.now_s(), "ew_t": clean.ew_service.t,
			"ew_step_count": clean.ew_service.step_count,
			"active_effects": clean.ew_service.active("raider_2", "radar"),
			"queue": clean.ew_delivery_queue(),
			"delivered": clean.ew_delivered_observations()},
		"target_samples": clean_samples}

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("Could not open expiry report " + OUT)
		quit(2)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("JC-A03 EFFECT EXPIRY DIAGNOSTIC report=", OUT)
	print(JSON.stringify({"apply_effect": applied.get("effect", {}),
		"jam_tick1": timeline[0], "after_expiry_tick2": timeline[1],
		"ew_zero_tick1": report["cases"]["ew_zero_first_tick"], "report": OUT}))
	quit(0)


func _summarize_samples(ticks: Array) -> Array:
	var out: Array = []
	for trow in ticks:
		for raw in trow.new_target_samples:
			out.append({"session_t": trow.post.session_now,
				"ew_t_before_sample": trow.pre.ew_t,
				"sampled_t": raw.get("sampled_t", -1.0),
				"observed_t": raw.get("observed_t", -1.0),
				"confidence_mult": raw.get("confidence_mult", -1.0),
				"delay_s": raw.get("delay_s", -1.0),
				"quality_before": raw.get("quality_before", -1.0),
				"quality_after": raw.get("quality_after", -1.0),
				"jammed": raw.get("jammed", false)})
	return out


