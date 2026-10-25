extends SceneTree

# DS-A-04 fixture generator (temporary; NOT registered in the probe matrix).
# Produces REAL saves on the I3 implementation, then derives the two legacy shapes by
# deleting only the documented optional fields. Never fabricates content.

const GameSessionScript := preload("res://scripts/core/game_session.gd")
const OUT_DIR := "user://legacy_fixtures"

const EARLY_ID := "evt-legacy-early-1"
const EARLY_TYPE := "story.flag"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var s = GameSessionScript.new(_seed())
	print("READY=", s.ready, " errors=", s.errors)
	# 1) 早期显式 ID 走 route_event() 白名单路径（会写入操作日志）
	var early: Dictionary = s.route_event({"id": EARLY_ID, "type": EARLY_TYPE,
		"t": 0.125, "source": "legacy_fixture", "target": "",
		"payload": {"flag": "legacy_early", "ratio": 1.25, "fine": 0.001}})
	print("EARLY ok=", early.get("ok", false), " reason=", early.get("reason", ""),
		" seq=", early.get("seq", -1))
	var log_has_id := false
	for raw in s._log:
		if raw is Dictionary and String((raw as Dictionary).get("op", "")) == "route_event":
			var ev: Dictionary = (raw as Dictionary).get("event", {})
			if String(ev.get("id", "")) == EARLY_ID:
				log_has_id = true
	print("LOG_HAS_EARLY_ID=", log_has_id, " log_len=", s._log.size())
	# 2) 产生 > MAX_EVENTS 条事件，把早期 ID 挤出可见历史
	# 只靠事件条数把早期 ID 挤出可见历史（不推进物理，避免无谓成本）
	for i in range(1005):
		s.route_event({"type": "story.flag", "t": float(i) + 1.0,
			"source": "legacy_fixture", "target": "",
			"payload": {"flag": "bulk_%d" % i, "i": i, "ratio": 1.5}})
	var still_visible := false
	for raw_ev in s.bus.events:
		if raw_ev is Dictionary and String((raw_ev as Dictionary).get("id", "")) == EARLY_ID:
			still_visible = true
	print("VISIBLE_EVENTS=", s.bus.count(), " EARLY_STILL_VISIBLE=", still_visible,
		" SEEN_IDS=", s.bus._seen_ids.size(), " SEQ=", s.bus.seq,
		" ID_SEQ=", s.bus._id_seq)
	# 3) 真实导出（I3 新档），保留作为对照
	var full_text: String = s.save_state()
	_write(OUT_DIR + "/save_v2_reference.json", full_text)
	# 4) 形态 B：删除 v2 新增字段（schema/version/id_seq/seen_ids/max_events）
	var parsed: Dictionary = JSON.parse_string(full_text)
	var legacy_b: Dictionary = parsed.duplicate(true)
	var lbus: Dictionary = legacy_b.get("bus", {})
	var removed_b: Array = []
	for f in ["schema", "version", "id_seq", "seen_ids", "max_events"]:
		if lbus.has(f):
			lbus.erase(f)
			removed_b.append(f)
	legacy_b["bus"] = lbus
	_write(OUT_DIR + "/legacy_bus_seq_events.json", JSON.stringify(legacy_b))
	print("SHAPE_B_REMOVED=", removed_b)
	# 5) 形态 A：整段删除 bus
	var legacy_a: Dictionary = parsed.duplicate(true)
	legacy_a.erase("bus")
	_write(OUT_DIR + "/legacy_no_bus_section.json", JSON.stringify(legacy_a))
	print("SHAPE_A_REMOVED_BUS=true")
	# 6) 探针期望元数据
	var meta := {
		"generator_head": OS.get_environment("DSH_FIXTURE_HEAD"),
		"early_event_id": EARLY_ID,
		"early_event_seq": int(early.get("seq", -1)),
		"early_event_type": EARLY_TYPE,
		"early_time_s": 0.125,
		"early_payload": {"flag": "legacy_early", "ratio": 1.25, "fine": 0.001},
		"op_log_contains_early_id": log_has_id,
		"op_log_len": s._log.size(),
		"visible_event_count": s.bus.count(),
		"early_still_visible": still_visible,
		"seen_ids_count": s.bus._seen_ids.size(),
		"bus_seq": int(s.bus.seq),
		"bus_id_seq": int(s.bus._id_seq),
		"shape_b_removed_fields": removed_b,
		"shape_a_removed_section": "bus",
	}
	_write(OUT_DIR + "/fixture_meta.json", JSON.stringify(meta, "  "))
	print("META=", JSON.stringify(meta))
	quit(0)


func _seed() -> Dictionary:
	return {
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"epoch": "2193-04-11T08:00:00Z",
		"track_table": true,
		"story_state": {"flags": {}, "evidence": {}, "choices": {}},
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [322139.0, 0.0, 0.0],
				"vel_kmps": [0.0, 1.02, 0.0]}],
	}


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("WRITE_FAIL ", path)
		return
	f.store_string(text)
	f.close()
	print("WROTE ", path, " len=", text.length())
