extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-03 · EventBus 事件历史恢复与继续发布探针
#
# 基线：I1（服务开发）/ I2（Session 集成）。本探针直接验证 EventBus 的版本化
# state 契约，并用真实 GameSession 做存读档续写集成证据。
#
# 契约（任务卡）：
#   * EventBus 唯一分配 seq / 自动 ID，并持有去重集合。
#   * Session 通过明确导出/恢复 API 编排，不直接重建 EventBus 私有字段。
#   * 恢复历史 = **导入**，不 publish、不派发历史；订阅 Callable 不序列化。
#   * t 为模拟秒保留浮点；payload 合法浮点保真；实体 ID 保持字符串。
#   * 数值 JSON 兼容范围 0..2^53-1；bus seq/allocator 允许 0，事件 seq 必须 >=1；
#     原始值可为 int/float 但必须有限、无小数、在范围内；**恢复后必须是 GDScript int**。
#   * 达到上限时明确拒绝继续分配（不溢出/不四舍五入）。
#   * 失败导入不得半写 bus（状态完全不变）。
#
# Output: `A0-A03 EVENT CONTINUITY PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const EventBusScript := preload("res://scripts/core/event_bus.gd")
const GameSessionScript := preload("res://scripts/core/game_session.gd")

const WATCHDOG_S := 180.0
const FLOAT_TOL := 1.0e-9
const SAFE_INT_MAX := 9007199254740991.0
const TICK_DT := 60.0

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A03 EVENT CONTINUITY PROBE · baseline I2")
	print("Godot ", Engine.get_version_info().get("string", "?"))
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-A03] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("A0-A03 EVENT CONTINUITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A03] FAILED: ", f)
		print("A0-A03 EVENT CONTINUITY PROBE FAILED")
	else:
		print("A0-A03 EVENT CONTINUITY PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A03] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A03] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-A03] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A03] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. baseline reproduction: mixed IDs + non-integer time/payload roundtrip")
	var bus = EventBusScript.new()
	_ok(bool(bus.ready), "EventBus ready")
	# 混合自动/显式 ID、非整数时间 0.125、payload 浮点 1.25 / 0.001
	var p1: Dictionary = bus.publish({"type": "test.auto", "t": 0.125,
		"source": "unit", "target": "T1", "payload": {"a": 1.25, "b": 0.001,
			"flag": true, "name": "alpha"}})
	_ok(bool(p1.get("ok", false)), "publish auto-id event", str(p1.get("reason", "")))
	var p2: Dictionary = bus.publish({"id": "evt-explicit-1", "type": "test.explicit",
		"t": 0.25, "source": "unit", "target": "T2", "payload": {"r": 3.5}})
	_ok(bool(p2.get("ok", false)), "publish explicit-id event", str(p2.get("reason", "")))
	_ok(bus.count() == 2, "two events recorded", "n=" + str(bus.count()))
	_ok(int(bus.current_seq()) == 2, "bus seq advanced to 2", str(bus.current_seq()))

	_step("2. export → JSON → import: content, int types and float fidelity")
	var exported: Dictionary = bus.export_state()
	_ok(String(exported.get("schema", "")) == "v17.event_bus.state.v2",
		"export carries versioned schema", String(exported.get("schema", "")))
	_eq(int(exported.get("seq", -1)), 2, "exported seq is 2")
	_eq(int(exported.get("id_seq", -1)), 1, "exported auto-id allocator is 1")
	var seen_arr: Array = exported.get("seen_ids", []) if exported.get("seen_ids") is Array else []
	_ok(seen_arr.size() >= 2, "export carries the full used-id set", "n=" + str(seen_arr.size()))
	# 走真实 JSON 往返（模拟存档载体）
	var json_round: Dictionary = JSON.parse_string(JSON.stringify(exported))
	var bus2 = EventBusScript.new()
	var imp: Dictionary = bus2.import_state(json_round)
	_ok(bool(imp.get("ok", false)), "import after JSON roundtrip ok", str(imp.get("errors", [])))
	_eq(int(bus2.current_seq()), 2, "restored bus seq is 2")
	# 恢复后必须是 GDScript int（类型漂移判据）
	_ok(bus2.seq is int, "restored bus seq is a real GDScript int",
		"type=" + type_string(typeof(bus2.seq)))
	_ok(bus2._id_seq is int, "restored allocator is a real GDScript int",
		"type=" + type_string(typeof(bus2._id_seq)))
	var type_bad: Array = []
	for raw in bus2.events:
		var ev: Dictionary = raw
		if not (ev.get("seq", 0) is int):
			type_bad.append({"id": String(ev.get("id", "")),
				"type": type_string(typeof(ev.get("seq")))})
	_ok(type_bad.is_empty(), "every restored event seq is a real GDScript int",
		"violations=" + str(type_bad))
	# 浮点保真（1e-9），布尔/字符串/ID/顺序精确
	var fidelity_bad: Array = []
	if bus2.events.size() == 2:
		var e0: Dictionary = bus2.events[0]
		var e1: Dictionary = bus2.events[1]
		_near(float(e0.get("t", -1.0)), 0.125, FLOAT_TOL, "event t=0.125 preserved (1e-9)")
		var pl0: Dictionary = e0.get("payload", {})
		_near(float(pl0.get("a", -1.0)), 1.25, FLOAT_TOL, "payload 1.25 preserved (1e-9)")
		_near(float(pl0.get("b", -1.0)), 0.001, FLOAT_TOL, "payload 0.001 preserved (1e-9)")
		_eq(bool(pl0.get("flag", false)), true, "payload bool preserved exactly")
		_eq(String(pl0.get("name", "")), "alpha", "payload string preserved exactly")
		_eq(String(e1.get("id", "")), "evt-explicit-1", "explicit id preserved exactly")
		_eq(String(e1.get("target", "")), "T2", "target id stays a string")
		if String(e0.get("id", "")) != "evt-000001":
			fidelity_bad.append({"auto_id": String(e0.get("id", ""))})
	_ok(fidelity_bad.is_empty(), "auto-generated id preserved exactly",
		"violations=" + str(fidelity_bad))
	# save→load→save 规范化内容一致
	var exported2: Dictionary = bus2.export_state()
	_eq(JSON.stringify(exported.get("events", [])),
		JSON.stringify(exported2.get("events", [])),
		"export→import→export normalized events identical")

	_step("3. import must NOT publish or dispatch history (0 subscriber calls)")
	var bus3 = EventBusScript.new()
	var calls: Array = []
	var cb := func(ev: Dictionary) -> void: calls.append(String(ev.get("id", "")))
	bus3.subscribe("", cb)
	var imp3: Dictionary = bus3.import_state(JSON.parse_string(JSON.stringify(exported)))
	_ok(bool(imp3.get("ok", false)), "import into subscribed bus ok", str(imp3.get("errors", [])))
	_eq(calls.size(), 0, "restoring history called subscribers 0 times")
	# 新事件恰好派发一次
	var p3: Dictionary = bus3.publish({"type": "test.after", "t": 1.0,
		"source": "unit", "target": "T3", "payload": {}})
	_ok(bool(p3.get("ok", false)), "publish after restore ok")
	_eq(calls.size(), 1, "new publish dispatched exactly once")
	_ok(int(bus3.current_seq()) == 3, "first new seq is saved seq + 1",
		str(bus3.current_seq()))

	_step("4. old explicit id re-publish rejected without advancing seq/allocator")
	var seq_before := int(bus3.current_seq())
	var alloc_before := int(bus3._id_seq)
	var dup: Dictionary = bus3.publish({"id": "evt-explicit-1", "type": "test.dup",
		"t": 2.0, "source": "unit", "target": "T4", "payload": {}})
	_ok(bool(dup.get("ok", false)) == false, "re-publishing an old explicit id is rejected",
		str(dup.get("reason", "")))
	_eq(int(bus3.current_seq()), seq_before, "rejected publish did not advance seq")
	_eq(int(bus3._id_seq), alloc_before, "rejected publish did not advance allocator")

	_step("5. >MAX_EVENTS: evicted ids stay used; allocator keeps increasing")
	var big = EventBusScript.new()
	for i in range(1005):
		big.publish({"type": "bulk", "t": float(i), "source": "unit",
			"target": "T%d" % i, "payload": {"i": i}})
	_ok(int(big.count()) == 1000, "visible ring buffer capped at MAX_EVENTS=1000",
		str(big.count()))
	var big_state: Dictionary = big.export_state()
	var seen_big: Array = big_state.get("seen_ids", [])
	_ok(seen_big.size() == 1005, "full used-id set keeps all 1005 ids (not shrunk to 1000)",
		"n=" + str(seen_big.size()))
	var big2 = EventBusScript.new()
	var imp_big: Dictionary = big2.import_state(JSON.parse_string(JSON.stringify(big_state)))
	_ok(bool(imp_big.get("ok", false)), "import oversized-history state ok",
		str(imp_big.get("errors", [])))
	_eq(big2._seen_ids.size(), 1005, "restored used-id set is still 1005 (no shrink)")
	# 已被裁出可见缓冲的早期 ID 仍必须拒绝重发
	var early_dup: Dictionary = big2.publish({"id": "evt-000001", "type": "bulk",
		"t": 0.0, "source": "unit", "target": "X", "payload": {}})
	_ok(bool(early_dup.get("ok", true)) == false,
		"id evicted from the visible ring is still rejected", str(early_dup.get("reason", "")))
	_eq(int(big2.current_seq()), 1005, "rejected evicted-id publish did not advance seq")

	_step("6. negative: invalid seq / version / ordering are explicitly rejected")
	var base_state: Dictionary = bus.export_state()
	var neg_cases := {
		"negative seq": {"seq": -1.0},
		"fractional seq": {"seq": 1.5},
		"string seq": {"seq": "2"},
		"out-of-range seq": {"seq": SAFE_INT_MAX + 10.0},
		"version mismatch": {"version": 99},
	}
	for label in neg_cases.keys():
		var broken: Dictionary = JSON.parse_string(JSON.stringify(base_state))
		var patch: Dictionary = neg_cases[label]
		for k in patch.keys():
			broken[k] = patch[k]
		var probe_bus = EventBusScript.new()
		var r: Dictionary = probe_bus.import_state(broken)
		_ok(bool(r.get("ok", true)) == false, "NEGATIVE: %s is rejected" % label,
			str(r.get("errors", [])))
		_eq(int(probe_bus.current_seq()), 0, "NEGATIVE: %s leaves bus untouched" % label)
		_eq(probe_bus.count(), 0, "NEGATIVE: %s wrote no events" % label)
	# 事件 seq 重复 / 倒序
	var dup_state: Dictionary = JSON.parse_string(JSON.stringify(base_state))
	var evs: Array = dup_state.get("events", [])
	if evs.size() >= 2:
		(evs[1] as Dictionary)["seq"] = (evs[0] as Dictionary).get("seq", 1)
		var probe_bus2 = EventBusScript.new()
		var r2: Dictionary = probe_bus2.import_state(dup_state)
		_ok(bool(r2.get("ok", true)) == false,
			"NEGATIVE: duplicate/descending event seq rejected", str(r2.get("errors", [])))
	# counter 比尾部小
	var tail_state: Dictionary = JSON.parse_string(JSON.stringify(base_state))
	tail_state["seq"] = 0
	var probe_bus3 = EventBusScript.new()
	var r3: Dictionary = probe_bus3.import_state(tail_state)
	_ok(bool(r3.get("ok", true)) == false,
		"NEGATIVE: seq smaller than history tail rejected", str(r3.get("errors", [])))
	# 缺必需字段
	var probe_bus4 = EventBusScript.new()
	var r4: Dictionary = probe_bus4.import_state({"schema": "v17.event_bus.state.v2",
		"version": 2})
	_ok(bool(r4.get("ok", true)) == false,
		"NEGATIVE: missing required fields rejected", str(r4.get("errors", [])))
	# 非法 schema（损坏新档不得伪装成旧档）
	var probe_bus5 = EventBusScript.new()
	var r5: Dictionary = probe_bus5.import_state({"schema": "v17.event_bus.state.v99"})
	_ok(bool(r5.get("ok", true)) == false,
		"NEGATIVE: unknown state schema rejected (not treated as legacy)",
		str(r5.get("errors", [])))
	# 失败导入前后 bus 状态一致
	var before_json := JSON.stringify(bus3.export_state())
	bus3.import_state({"schema": "v17.event_bus.state.v99"})
	_eq(JSON.stringify(bus3.export_state()), before_json,
		"failed import leaves the bus state byte-identical")

	_step("7. auto-id vs explicit evt-* collision is detected")
	var coll = EventBusScript.new()
	coll.publish({"type": "a", "t": 0.0, "source": "u", "target": "T", "payload": {}})
	var coll_state: Dictionary = coll.export_state()
	# 把分配器调低到已用号以下 → 下一次分配会重发已存在 ID
	coll_state["id_seq"] = 0
	var coll_probe = EventBusScript.new()
	var cr: Dictionary = coll_probe.import_state(coll_state)
	_ok(bool(cr.get("ok", true)) == false,
		"NEGATIVE: allocator below max used evt-* id is rejected", str(cr.get("errors", [])))

	_step("8. integration: real GameSession save→load→continue (same event stream)")
	var s1 = GameSessionScript.new(_session_seed())
	_ok(bool(s1.ready), "source session ready", str(s1.errors))
	for i in range(4):
		s1.tick(TICK_DT)
	var seq_at_save := int(s1.bus.current_seq())
	var ids_at_save: Array = []
	for raw_ev in s1.bus.events:
		ids_at_save.append(String((raw_ev as Dictionary).get("id", "")))
	var text1: String = s1.save_state()
	_ok(text1.length() > 500, "save_state non-empty", "len=%d" % text1.length())
	# 真实文件往返
	var path := "user://" + "a03_probe_state.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	_ok(f != null, "probe can write a real save file")
	if f != null:
		f.store_string(text1)
		f.close()
	var s2 = GameSessionScript.new()
	var lr: Dictionary = s2.load_state(FileAccess.get_file_as_string(path))
	_ok(bool(lr.get("ok", false)), "load_state from a real file ok", str(lr.get("errors", [])))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not bool(lr.get("ok", false)):
		_finish()
		return
	_eq(int(s2.bus.current_seq()), seq_at_save, "restored bus seq matches the saved seq")
	var rtype_bad: Array = []
	for raw_ev2 in s2.bus.events:
		if not ((raw_ev2 as Dictionary).get("seq", 0) is int):
			rtype_bad.append(String((raw_ev2 as Dictionary).get("id", "")))
	_ok(rtype_bad.is_empty(), "restored session event seq are real GDScript ints",
		"violations=" + str(rtype_bad))
	# 订阅者：恢复历史 0 次
	var post_calls: Array = []
	var cb2 := func(ev2: Dictionary) -> void: post_calls.append(String(ev2.get("id", "")))
	s2.bus.subscribe("", cb2)
	_ok(post_calls.is_empty(), "no subscriber calls immediately after load")
	# 两个会话继续相同命令序列（10 ticks）
	var new_ids_a: Array = []
	var new_ids_b: Array = []
	for i in range(10):
		s1.tick(TICK_DT)
		s2.tick(TICK_DT)
	_ok(int(s2.bus.current_seq()) == int(s1.bus.current_seq()),
		"continued sessions have identical seq after 10 ticks",
		"orig=%d restored=%d" % [int(s1.bus.current_seq()), int(s2.bus.current_seq())])
	_ok(int(s2.bus._id_seq) == int(s1.bus._id_seq),
		"continued sessions have identical auto-id allocator",
		"orig=%d restored=%d" % [int(s1.bus._id_seq), int(s2.bus._id_seq)])
	_ok(post_calls.size() > 0, "new events after restore dispatched to subscribers",
		"n=" + str(post_calls.size()))
	# 首个新 seq == 保存值 + 1
	_ok(int(s2.bus.current_seq()) > seq_at_save,
		"new seq continues past the saved value", "saved=%d now=%d" % [
			seq_at_save, int(s2.bus.current_seq())])
	# 新事件 ID 唯一
	var seen_dup: Array = []
	var seen_local: Dictionary = {}
	for raw_ev3 in s2.bus.events:
		var eid := String((raw_ev3 as Dictionary).get("id", ""))
		if seen_local.has(eid):
			seen_dup.append(eid)
		seen_local[eid] = true
	_ok(seen_dup.is_empty(), "no duplicate event ids after continuation", str(seen_dup))
	_info("INTEGRATION: seq saved=%d continued orig=%d restored=%d subscribers=%d" % [
		seq_at_save, int(s1.bus.current_seq()), int(s2.bus.current_seq()),
		post_calls.size()])

	_step("9. integration: save→load→save normalized equality")
	var save_a: String = s2.save_state()
	var s3 = GameSessionScript.new()
	var lr3: Dictionary = s3.load_state(save_a)
	_ok(bool(lr3.get("ok", false)), "second-generation load ok", str(lr3.get("errors", [])))
	if bool(lr3.get("ok", false)):
		var save_b: String = s3.save_state()
		_eq(JSON.stringify(JSON.parse_string(save_a)["bus"]),
			JSON.stringify(JSON.parse_string(save_b)["bus"]),
			"save→load→save bus state normalized identical")

	_step("10. A-03 summary")
	_info("A-03: versioned state, no-publish import, int contract, allocator/high-water dedup, "
		+ "oversized ring preservation, negative matrix, real-file continuation")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _session_seed() -> Dictionary:
	return {
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"epoch": "2193-04-11T08:00:00Z",
		"track_table": true,
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [322139.0, 0.0, 0.0],
				"vel_kmps": [0.0, 1.02, 0.0]}],
	}
