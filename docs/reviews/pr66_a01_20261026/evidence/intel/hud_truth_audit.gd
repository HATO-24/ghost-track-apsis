extends "res://tests/a0_save_cost_probe.gd"

var result: Dictionary = {}

func _row(plot: Dictionary, eid: String) -> Dictionary:
	for raw in plot.get("positions", []):
		if String(raw.get("id", "")) == eid:
			return raw.duplicate(true)
	return {}

func _run() -> void:
	var err = change_scene_to_file(MAIN_MENU)
	if err != OK:
		quit(2)
		return
	var boot = await _await_v1_hud()
	if boot.hud == null:
		quit(2)
		return
	var binder = boot.hud.get("binder")
	var s = binder.get("session")
	var owner = s.authority_intel.own_owner
	var view0: Dictionary = s.intel_view(owner)
	var facade0: Dictionary = s.plot_positions(owner)
	var hud0: Dictionary = binder.plot_positions()
	var target := "raider_2"
	if not s.physics_positions("bary_rot").has(target):
		target = "harmattan"
	var st: Dictionary = s.physics_state(target, "bary_rot")
	var moved: Dictionary = st.duplicate(true)
	moved["r"] = [float(st.r[0]) + 1234.0, float(st.r[1]) + 77.0, float(st.r[2]) + 9.0]
	moved["frame"] = "bary_rot"
	var move: Dictionary = s.physics_world_service.upsert_entity(target, moved)
	var view1: Dictionary = s.intel_view(owner)
	var facade1: Dictionary = s.plot_positions(owner)
	var hud1: Dictionary = binder.plot_positions()
	result = {
		"head": "1d1e8399da438b77b74acee40d753711c8d2a8f9",
		"real_entry": {"saw_main_menu": boot.saw_main_menu, "scene": current_scene.scene_file_path, "binder_ready": binder.ready},
		"owner": owner, "owner_tracks": view0.tracks.size(),
		"owner_positions": facade0.positions.size(), "hud_positions": hud0.positions.size(),
		"hud_source": hud0.source, "target": target,
		"target_in_owner_view": str(view0).contains(target),
		"truth_move_ok": move.get("ok", false),
		"owner_view_unchanged": JSON.stringify(view0) == JSON.stringify(view1),
		"facade_unchanged": JSON.stringify(facade0) == JSON.stringify(facade1),
		"hud_changed": JSON.stringify(hud0) != JSON.stringify(hud1),
		"hud_target_before": _row(hud0, target), "hud_target_after": _row(hud1, target),
	}
	var f = FileAccess.open(OS.get_environment("A01_INTEL_HUD_OUT"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	print("A01_INTEL_HUD_RESULT ", JSON.stringify(result))
	_finished = true
	_restore_env()
	quit(0 if result.hud_changed and result.owner_view_unchanged else 1)
