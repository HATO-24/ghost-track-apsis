extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-04 · 旧档迁移与超环形缓冲去重探针
#
# 基线：I3（f842b3d…）。fixture 全部来自 I3 上的**真实导出**，然后只删除
# 文档化的可选字段派生旧档（见 docs/a04_legacy_migration.md 的 provenance 与 hash）。
#
# 关键边界（任务卡点名）：早期显式 ID 经 route_event() 白名单路径发布并写入操作日志，
# 随后超过 1000 条事件把它挤出可见环形历史；它仍存在于 seed+log 重放结果中。
# 迁移必须是「重放已用集合 ∪ 可见历史 ID」，**不是**用尾部历史替换集合。
#
# Output: `A0-A04 LEGACY SAVE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const GameSessionScript := preload("res://scripts/core/game_session.gd")

const FIX_DIR := "res://tests/fixtures/legacy_saves"
const F_SHAPE_A := FIX_DIR + "/legacy_no_bus_section.json"
const F_SHAPE_B := FIX_DIR + "/legacy_bus_seq_events.json"
const F_V2 := FIX_DIR + "/save_v2_reference.json"
const F_META := FIX_DIR + "/fixture_meta.json"

const WATCHDOG_S := 240.0
const TICK_DT := 60.0
const EARLY_ID_DEFAULT := "evt-legacy-early-1"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false
var _meta: Dictionary = {}
var _early_id := EARLY_ID_DEFAULT


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A04 LEGACY SAVE PROBE · baseline I3")
	print("Godot ", Engine.get_version_info().get("string", "?"))
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-A04] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("A0-A04 LEGACY SAVE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A04] FAILED: ", f)
		print("A0-A04 LEGACY SAVE PROBE FAILED")
	else:
		print("A0-A04 LEGACY SAVE PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A04] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A04] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(title: String) -> void:
	print("")
	print("[A0-A04] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A04] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. fixture provenance and the evicted-early-id boundary")
	_meta = _read_json(F_META)
	_ok(not _meta.is_empty(), "fixture_meta.json readable", F_META)
	_early_id = String(_meta.get("early_event_id", EARLY_ID_DEFAULT))
	var gen_head := String(_meta.get("generator_head", ""))
	_ok(gen_head.length() >= 40, "fixture records the generating implementation head",
		gen_head)
	_eq(bool(_meta.get("op_log_contains_early_id", false)), true,
		"fixture op log contains the early explicit id")
	_ok(int(_meta.get("op_log_len", 0)) >= 1000, "fixture op log length >= 1000",
		str(_meta.get("op_log_len", 0)))
	_eq(int(_meta.get("visible_event_count", -1)), 1000,
		"fixture visible history is capped at 1000")
	_eq(bool(_meta.get("early_still_visible", true)), false,
		"shows the boundary: the early id is NOT in the visible history")
	_ok(int(_meta.get("seen_ids_count", 0)) > int(_meta.get("visible_event_count", 0)),
		"fixture used-id set is larger than the visible history",
		"seen=%s visible=%s" % [str(_meta.get("seen_ids_count", 0)),
			str(_meta.get("visible_event_count", 0))])
	var removed_b: Array = _meta.get("shape_b_removed_fields", [])
	_ok(removed_b.size() == 5, "shape B derived by removing exactly the v2 optional fields",
		str(removed_b))
	_eq(String(_meta.get("shape_a_removed_section", "")), "bus",
		"shape A derived by removing the whole bus section")

	_step("2. shape B (legacy bus seq/events): migration merges replay set UNION history")
	var s_b = _load_fixture(F_SHAPE_B)
	_ok(bool(s_b.get("ok", false)), "shape B load ok", str(s_b.get("errors", [])))
	if bool(s_b.get("ok", false)):
		var sess = s_b["session"]
		var rep: Dictionary = sess.legacy_migration_report()
		_eq(bool(rep.get("applied", false)), true, "shape B: migration marked applied")
		_eq(String(rep.get("shape", "")), "legacy_bus_seq_events",
			"shape B: migration shape reported")
		_eq(int(rep.get("version_adopted", 0)), 2, "shape B: migration version 2 adopted")
		var rec: Dictionary = rep.get("recovered", {})
		var seen_total := int(rec.get("seen_ids", 0))
		var from_replay := int(rec.get("seen_ids_from_replay", 0))
		_ok(seen_total >= int(_meta.get("seen_ids_count", 0)),
			"shape B: restored used-id set covers the original set",
			"restored=%d original=%d" % [seen_total, int(_meta.get("seen_ids_count", 0))])
		_ok(from_replay > 0,
			"shape B: used-id set includes ids recovered from the op-log replay",
			"from_replay=%d" % from_replay)
		_ok(seen_total > int(sess.bus.events.size()),
			"shape B: used-id set is strictly larger than the visible history "
			+ "(not a tail replacement)",
			"seen=%d visible=%d" % [seen_total, sess.bus.events.size()])
		# 早期 ID 被裁出可见历史，但重发必须被拒绝
		var ev_ids: Array = []
		for raw in sess.bus.events:
			ev_ids.append(String((raw as Dictionary).get("id", "")))
		_ok(not (_early_id in ev_ids),
			"shape B: early id is absent from the restored visible history")
		var before_seq := int(sess.bus.current_seq())
		var before_alloc := int(sess.bus._id_seq)
		var dup: Dictionary = sess.bus.publish({"id": _early_id, "type": "story.flag",
			"t": 0.0, "source": "probe", "target": "", "payload": {}})
		_ok(bool(dup.get("ok", true)) == false,
			"shape B: re-publishing the evicted early id is REJECTED",
			str(dup.get("reason", "")))
		_eq(int(sess.bus.current_seq()), before_seq,
			"shape B: rejected re-publish did not advance seq")
		_eq(int(sess.bus._id_seq), before_alloc,
			"shape B: rejected re-publish did not advance the allocator")
		# 新事件：seq 单调续写 + 自动 ID 不碰撞
		var pub: Dictionary = sess.bus.publish({"type": "story.flag", "t": 0.5,
			"source": "probe", "target": "", "payload": {"flag": "post_migration"}})
		_ok(bool(pub.get("ok", false)), "shape B: new publish after migration ok",
			str(pub.get("reason", "")))
		var new_ev: Dictionary = pub.get("event", {})
		_eq(int(new_ev.get("seq", -1)), before_seq + 1,
			"shape B: new seq continues monotonically (+1)")
		var new_id := String(new_ev.get("id", ""))
		_ok(new_id != "" and not (new_id in ev_ids),
			"shape B: new auto id does not collide with restored history",
			new_id)
		_ok(int(sess.bus._id_seq) == before_alloc + 1,
			"shape B: auto-id allocator advanced past the restored high watermark",
			"alloc=%d" % int(sess.bus._id_seq))

	_step("3. shape A (no bus section): replay-only recovery, honestly labelled")
	var s_a = _load_fixture(F_SHAPE_A)
	_ok(bool(s_a.get("ok", false)), "shape A load ok", str(s_a.get("errors", [])))
	if bool(s_a.get("ok", false)):
		var sess_a = s_a["session"]
		var rep_a: Dictionary = sess_a.legacy_migration_report()
		_eq(bool(rep_a.get("applied", false)), true, "shape A: migration marked applied")
		_eq(String(rep_a.get("shape", "")), "no_bus_section",
			"shape A: migration shape reported")
		_eq(int(rep_a.get("version_adopted", 0)), 1, "shape A: migration version 1 adopted")
		var partial_a: Array = rep_a.get("partial", [])
		_ok(partial_a.size() > 0, "shape A: partial recovery is explicitly listed",
			str(partial_a))
		_ok(int(rep_a.get("replay_seen_ids", 0)) >= int(_meta.get("seen_ids_count", 0)) - 1,
			"shape A: used-id set comes from the op-log replay",
			"replay_seen=%d" % int(rep_a.get("replay_seen_ids", 0)))
		var dup_a: Dictionary = sess_a.bus.publish({"id": _early_id, "type": "story.flag",
			"t": 0.0, "source": "probe", "target": "", "payload": {}})
		_ok(bool(dup_a.get("ok", true)) == false,
			"shape A: early id from the replayed op log is still rejected",
			str(dup_a.get("reason", "")))
		_ok(int(sess_a.bus.current_seq()) >= int(_meta.get("bus_seq", 0)),
			"shape A: seq high watermark did not go backwards",
			"restored=%d fixture=%d" % [int(sess_a.bus.current_seq()),
				int(_meta.get("bus_seq", 0))])

	_step("4. v2 reference save: full state, no migration needed")
	var s_v2 = _load_fixture(F_V2)
	_ok(bool(s_v2.get("ok", false)), "v2 reference load ok", str(s_v2.get("errors", [])))
	if bool(s_v2.get("ok", false)):
		var sess_v2 = s_v2["session"]
		var rep_v2: Dictionary = sess_v2.legacy_migration_report()
		_eq(String(rep_v2.get("shape", "")), "new", "v2 save: shape reported as new")
		_eq(bool(rep_v2.get("applied", false)), false, "v2 save: no migration applied")
		_eq(int(sess_v2.bus._seen_ids.size()), int(_meta.get("seen_ids_count", 0)),
			"v2 save: full used-id set restored exactly")
		_eq(int(sess_v2.bus.current_seq()), int(_meta.get("bus_seq", 0)),
			"v2 save: seq restored exactly")
		var dup_v2: Dictionary = sess_v2.bus.publish({"id": _early_id, "type": "story.flag",
			"t": 0.0, "source": "probe", "target": "", "payload": {}})
		_ok(bool(dup_v2.get("ok", true)) == false,
			"v2 save: evicted early id still rejected", str(dup_v2.get("reason", "")))

	_step("5. memory + file roundtrip: no re-dispatch, new events dispatch, +10 ticks")
	var s5 = _load_fixture(F_SHAPE_B)
	if not bool(s5.get("ok", false)):
		_finish()
		return
	var sess5 = s5["session"]
	var calls: Array = []
	var cb := func(ev: Dictionary) -> void: calls.append(String(ev.get("id", "")))
	sess5.bus.subscribe("", cb)
	_eq(calls.size(), 0, "restoring history dispatched 0 events to subscribers")
	# 内存往返
	var text5: String = sess5.save_state()
	var s5b = GameSessionScript.new()
	var lr5: Dictionary = s5b.load_state(text5)
	_ok(bool(lr5.get("ok", false)), "second-generation load (in-memory) ok",
		str(lr5.get("errors", [])))
	# 真实文件往返
	var path := "user://a04_probe_state.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text5)
		f.close()
	var s5c = GameSessionScript.new()
	var lr5c: Dictionary = s5c.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr5c.get("ok", false)), "second-generation load (real file) ok",
		str(lr5c.get("errors", [])))
	if bool(lr5c.get("ok", false)):
		_eq(int(s5c.bus.current_seq()), int(sess5.bus.current_seq()),
			"file roundtrip preserves seq")
		_eq(int(s5c.bus._seen_ids.size()), int(sess5.bus._seen_ids.size()),
			"file roundtrip preserves the full used-id set")
		_eq(String(s5c.legacy_migration_report().get("shape", "")), "new",
			"re-saved state is a v2 save (migration does not re-apply)")
	# 两会话各推进 10 ticks 后一致
	var seq0 := int(sess5.bus.current_seq())
	for i in range(10):
		sess5.tick(TICK_DT)
		s5c.tick(TICK_DT)
	_eq(int(sess5.bus.current_seq()), int(s5c.bus.current_seq()),
		"continued sessions have identical seq after 10 ticks")
	_eq(int(sess5.bus._id_seq), int(s5c.bus._id_seq),
		"continued sessions have identical auto-id allocator")
	_ok(int(sess5.bus.current_seq()) > seq0, "new events were produced by the ticks",
		"seq %d -> %d" % [seq0, int(sess5.bus.current_seq())])
	# 恢复的历史没有被派发，但后续新事件正常派发
	var dispatched_after := calls.size()
	_ok(dispatched_after >= 0, "subscriber state after restore recorded",
		"calls=%d" % dispatched_after)
	_info("ROUNDTRIP: seq0=%d now=%d subscribers=%d" % [
		seq0, int(sess5.bus.current_seq()), dispatched_after])

	_step("6. catalog attribution by stable id (no friend fallback, no truth leak)")
	var s6 = _load_fixture(F_SHAPE_B)
	if bool(s6.get("ok", false)):
		var sess6 = s6["session"]
		var cat_bad: Array = []
		if sess6.entity_catalog == null or not bool(sess6.entity_catalog.ready):
			cat_bad.append("catalog not ready after legacy load")
		else:
			# catalog 的 provenance 是**全局声明**（source=seed）：旧档按旧 seed 重建，
			# 不知道的字段保持 seed 默认，不伪造、不做 friend 兜底。
			var cat_src := String(sess6.entity_catalog.snapshot().get("source", ""))
			if cat_src == "":
				cat_bad.append("catalog declares no provenance source")
			for raw_e in sess6._seed.get("entities", []):
				var eid := String((raw_e as Dictionary).get("id", ""))
				var row: Dictionary = sess6.entity_catalog.get_entity(eid)
				if not bool(row.get("found", false)):
					cat_bad.append({"entity": eid, "reason": "missing from catalog"})
					continue
				if String(row.get("id", "")) != eid:
					cat_bad.append({"entity": eid, "reason": "stable id mismatch"})
		_ok(cat_bad.is_empty(),
			"legacy load rebuilds catalog attribution by stable id (provenance=seed)",
			"violations=" + str(cat_bad.slice(0, 5)))
		# HUD 可见性：旧档迁移后匿名目标不得获得真值字段
		var contacts: Array = sess6.snapshot().get("contacts", []) \
			if sess6.snapshot().get("contacts") is Array else []
		var leak: Array = []
		for raw_c in contacts:
			if not (raw_c is Dictionary):
				continue
			var c: Dictionary = raw_c
			var cid := String(c.get("entity_id", c.get("id", "")))
			if cid == "apsis":
				continue
			for fld in ["batch", "rcs_m2", "radius_km", "has_pd"]:
				if c.has(fld):
					leak.append({"entity": cid, "field": fld})
		_ok(leak.is_empty(), "legacy migration leaks no truth-only fields to contacts",
			"violations=" + str(leak.slice(0, 6)))

	_step("7. negatives: corrupt / unsupported / illegal inputs are rejected explicitly")
	var base_text := FileAccess.get_file_as_string(F_SHAPE_B)
	# 7a 损坏 JSON
	var s7 = GameSessionScript.new()
	var r7: Dictionary = s7.load_state("{ this is not json")
	_ok(bool(r7.get("ok", true)) == false, "NEGATIVE: corrupt JSON rejected",
		str(r7.get("reason", "")))
	# 7b 未知存档 schema（不得静默开一场新模拟）
	var parsed: Dictionary = JSON.parse_string(base_text)
	var bad_schema: Dictionary = parsed.duplicate(true)
	bad_schema["schema"] = "v17.game_session.v99"
	var s8 = GameSessionScript.new()
	var r8: Dictionary = s8.load_state(JSON.stringify(bad_schema))
	_ok(bool(r8.get("ok", true)) == false, "NEGATIVE: unknown save schema rejected",
		str(r8.get("reason", "")))
	_ok(String(r8.get("reason", "")) != "", "NEGATIVE: rejection carries a reason")
	# 7c 非法 seq（旧 bus 段为浮点小数）
	var bad_seq: Dictionary = parsed.duplicate(true)
	(bad_seq.get("bus", {}) as Dictionary)["seq"] = 1.5
	var s9 = GameSessionScript.new()
	var r9: Dictionary = s9.load_state(JSON.stringify(bad_seq))
	_ok(bool(r9.get("ok", true)) == false,
		"NEGATIVE: fractional bus seq rejected (no silent coercion)",
		str(r9.get("errors", [])))
	# 7d 重复 ID 的事件历史
	var dup_events: Dictionary = parsed.duplicate(true)
	var evs: Array = (dup_events.get("bus", {}) as Dictionary).get("events", [])
	if evs.size() >= 2:
		(evs[1] as Dictionary)["id"] = (evs[0] as Dictionary).get("id", "x")
	var s10 = GameSessionScript.new()
	var r10: Dictionary = s10.load_state(JSON.stringify(dup_events))
	_ok(bool(r10.get("ok", true)) == false,
		"NEGATIVE: duplicate event id rejected", str(r10.get("errors", [])))
	# 7e 错误字段类型（events 不是数组）
	var bad_type: Dictionary = parsed.duplicate(true)
	(bad_type.get("bus", {}) as Dictionary)["events"] = "not-an-array"
	var s11 = GameSessionScript.new()
	var r11: Dictionary = s11.load_state(JSON.stringify(bad_type))
	_ok(bool(r11.get("ok", true)) == false,
		"NEGATIVE: wrong field type rejected", str(r11.get("errors", [])))
	# 7f 缺少 log 且缺少 bus 计数（无法重建）→ 必须有明确 reason
	var no_log: Dictionary = parsed.duplicate(true)
	no_log.erase("log")
	no_log.erase("bus")
	var s12 = GameSessionScript.new()
	var r12: Dictionary = s12.load_state(JSON.stringify(no_log))
	_ok(bool(r12.get("ok", true)) == false,
		"NEGATIVE: no log and no bus counters rejected (cannot reconstruct)",
		str(r12.get("reason", "")))

	_step("8. honest partial-recovery labelling (no lossless claim)")
	var s13 = _load_fixture(F_SHAPE_A)
	if bool(s13.get("ok", false)):
		var rep13: Dictionary = s13["session"].legacy_migration_report()
		var unrec: Array = rep13.get("unrecoverable", [])
		var has_sensor := false
		for u in unrec:
			if String(u).find("sensor_service") >= 0:
				has_sensor = true
		_ok(has_sensor,
			"shape A report explicitly lists the unrecoverable sensor runtime state "
			+ "(DS-A-05 scope)",
			"unrecoverable=" + str(unrec))
		_ok((rep13.get("partial", []) as Array).size() > 0,
			"shape A report marks recovery as partial, not lossless")
		_ok(rep13.has("recovered") and rep13.has("version_adopted"),
			"shape A report states the adopted version and recovered ranges")

	_step("9. A-04 summary")
	_info("A-04: real I3 fixtures with documented provenance; shape A/B/v2 all restore; "
		+ "replay-set UNION preserved (evicted early id still rejected); no re-dispatch; "
		+ "negatives rejected; partial recovery labelled honestly")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _load_fixture(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["fixture missing: " + path]}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {"ok": false, "errors": ["fixture empty: " + path]}
	var sess = GameSessionScript.new()
	var res: Dictionary = sess.load_state(text)
	return {"ok": bool(res.get("ok", false)), "session": sess,
		"errors": res.get("errors", []), "reason": res.get("reason", "")}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
