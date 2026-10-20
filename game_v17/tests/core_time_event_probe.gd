extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2A 最小 probe：TimeService / EventBus / WorldState
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/core_time_event_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接旧场景/UI。
# ═══════════════════════════════════════════════════════════════════

const TimeService := preload("res://scripts/core/time_service.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")
const WorldState := preload("res://scripts/core/world_state.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2A PROBE · TimeService / EventBus / WorldState")
	print("════════════════════════════════════════════════════════════")
	_test_time_basic()
	_test_time_controls()
	_test_time_window_seek()
	_test_event_publish()
	_test_event_filters_subs()
	_test_world_basic()
	_test_world_writer()
	_test_world_rejections()
	_test_cross()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 CORE TIME EVENT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 CORE TIME EVENT PROBE FAILED")
		quit(1)
	else:
		print("V17 CORE TIME EVENT PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f tol=%.6f" % [actual, expected, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _ev(event_type: String, t: float, source := "test", target := "",
		payload := {}, id := "") -> Dictionary:
	return {"id": id, "type": event_type, "t": t, "source": source,
		"target": target, "payload": payload, "text_key": ""}

# ═══════════════════════════════════════════════════════════════════
# 1. TimeService 基础 / 单调
# ═══════════════════════════════════════════════════════════════════

func _test_time_basic() -> void:
	_section_begin("1 TimeService 基础")
	var ts = TimeService.new()
	_ok(ts.ready, "time ready", str(ts.errors))
	_eq(ts.errors.size(), 0, "time 无 errors")
	_near(ts.now_s(), 0.0, 1.0e-9, "初始 t=0")
	_near(ts.epoch_s, 760.8, 1.0e-9, "默认 epoch=760.8")
	_near(ts.scale, 1.0, 1.0e-9, "默认 scale=1")
	_eq(ts.paused, false, "默认不暂停")
	_eq(ts.mode(), "running", "mode running")
	_ok(ts.check_invariants().get("ok", false), "初始不变量 ok")
	_eq(ts.tick_count, 0, "tick_count=0")
	var r1: Dictionary = ts.tick(1.0)
	_eq(bool(r1.get("ok", false)), true, "tick(1) ok")
	_near(ts.now_s(), 1.0, 1.0e-9, "t=1")
	_near(float(r1.get("dt_scaled_s", -1.0)), 1.0, 1.0e-9, "scaled dt=1")
	var r2: Dictionary = ts.tick(2.5)
	_near(ts.now_s(), 3.5, 1.0e-9, "t=3.5")
	_ok(ts.now_s() >= 1.0, "t 单调")
	_eq(ts.tick_count, 2, "tick_count=2")
	_near(ts.last_dt_s, 2.5, 1.0e-9, "last_dt=2.5")
	_near(ts.epoch_abs_s(), 760.8 + 3.5, 1.0e-9, "epoch_abs=epoch+t")
	_near(ts.now_days(), 3.5 / 86400.0, 1.0e-12, "now_days")
	var before := ts.now_s()
	var bad: Dictionary = ts.tick(-1.0)
	_eq(bool(bad.get("ok", true)), false, "负 dt 拒绝")
	_near(ts.now_s(), before, 1.0e-9, "负 dt 不改变 t")
	_ok(ts.contract_errors.size() > 0, "负 dt 记录 contract error")
	var nan: Dictionary = ts.tick(NAN)
	_eq(bool(nan.get("ok", true)), false, "NaN dt 拒绝")
	var zero: Dictionary = ts.tick(0.0)
	_eq(bool(zero.get("ok", false)), true, "tick(0) ok")
	_near(ts.now_s(), before, 1.0e-9, "tick(0) 不改变 t")
	_ok(ts.check_invariants().get("ok", false), "推进后不变量 ok")
	var et: Dictionary = ts.event_time()
	_eq(String(et.get("schema", "")), "v17.time_service.v1", "event_time schema")
	_near(float(et.get("t_s", -1.0)), ts.now_s(), 1.0e-9, "event_time t_s")
	_ok(et.has("epoch_abs_s"), "event_time epoch_abs")
	_data_line("time_basic", "t=%.3f tick_count=%d 单调/拒绝负/NaN" % [ts.now_s(), ts.tick_count])

func _test_time_controls() -> void:
	_section_begin("2 TimeService 控制")
	var ts = TimeService.new()
	ts.pause()
	_eq(ts.paused, true, "pause")
	_eq(ts.mode(), "paused", "mode paused")
	var before := ts.now_s()
	var r: Dictionary = ts.tick(10.0)
	_eq(bool(r.get("ok", false)), true, "暂停 tick ok")
	_near(ts.now_s(), before, 1.0e-9, "暂停不推进")
	_near(float(r.get("dt_scaled_s", -1.0)), 0.0, 1.0e-9, "暂停 scaled dt=0")
	ts.resume()
	ts.tick(1.0)
	_near(ts.now_s(), 1.0, 1.0e-9, "resume 后推进")
	var s1: Dictionary = ts.set_scale(2.0)
	_eq(bool(s1.get("ok", false)), true, "set_scale(2) ok")
	ts.tick(1.0)
	_near(ts.now_s(), 3.0, 1.0e-9, "scale=2 推进 2s")
	var sbad: Dictionary = ts.set_scale(-1.0)
	_eq(bool(sbad.get("ok", true)), false, "负 scale 拒绝")
	_near(ts.scale, 2.0, 1.0e-9, "负 scale 不生效")
	# max_dt 裁剪
	var ts2 = TimeService.new({"max_dt_s": 5.0})
	ts2.tick(100.0)
	_near(ts2.now_s(), 5.0, 1.0e-9, "max_dt 裁剪到 5s")
	_ok(ts2.warnings.size() > 0, "max_dt 裁剪记录 warning")
	# 港内时间
	var ts3 = TimeService.new()
	ts3.set_docked(true)
	ts3.tick(3.0)
	_near(ts3.docked_s, 3.0, 1.0e-9, "docked 时 docked_s 推进")
	ts3.set_docked(false)
	ts3.tick(2.0)
	_near(ts3.docked_s, 3.0, 1.0e-9, "非 docked 不推进 docked_s")
	_ok(ts3.docked_s <= ts3.now_s(), "docked_s <= t_s")
	# 参数非法
	var bad = TimeService.new({"scale": -1.0})
	_eq(bad.ready, false, "非法 scale setup 失败")
	_ok(bad.errors.size() > 0, "非法 setup 记录 errors")
	_data_line("time_controls", "pause/scale=2/max_dt=5/docked 时间 正常")

func _test_time_window_seek() -> void:
	_section_begin("3 TimeService 窗口/seek")
	var ts = TimeService.new()
	var w: Dictionary = ts.set_window(5.0)
	_eq(bool(w.get("ok", false)), true, "set_window(5)")
	_eq(ts.window_active, true, "window active")
	ts.tick(2.0)
	_near(ts.window_left_s, 3.0, 1.0e-9, "window left=3")
	var snap: Dictionary = ts.snapshot()
	_eq(bool((snap.get("window", {}) as Dictionary).get("active", false)), true, "snapshot window active")
	ts.tick(4.0)
	_eq(ts.window_active, false, "窗口过期后 active=false")
	_eq(ts.window_expired, true, "window expired=true")
	_near(ts.window_left_s, 0.0, 1.0e-9, "window left=0")
	var badw: Dictionary = ts.set_window(-1.0)
	_eq(bool(badw.get("ok", true)), false, "负窗口拒绝")
	ts.clear_window()
	_eq(ts.window_active, false, "clear_window")
	# seek
	var ts2 = TimeService.new()
	var sk: Dictionary = ts2.seek(10.0)
	_eq(bool(sk.get("ok", false)), true, "seek 向前 ok")
	_near(ts2.now_s(), 10.0, 1.0e-9, "seek t=10")
	var back: Dictionary = ts2.seek(5.0)
	_eq(bool(back.get("ok", true)), false, "seek 回退拒绝")
	_near(ts2.now_s(), 10.0, 1.0e-9, "回退不改变 t")
	var neg: Dictionary = ts2.seek(-1.0)
	_eq(bool(neg.get("ok", true)), false, "seek 负值拒绝")
	_ok(ts2.check_invariants().get("ok", false), "seek 后不变量 ok")
	# snapshot JSON
	var js := JSON.stringify(ts2.snapshot())
	_ok(js.length() > 300, "time snapshot JSON", "len=%d" % js.length())
	_ok(JSON.parse_string(js) is Dictionary, "time snapshot 回读")
	ts2.reset()
	_near(ts2.now_s(), 0.0, 1.0e-9, "reset t=0")
	_data_line("time_window_seek", "window countdown/expire · seek 单向 · JSON")

# ═══════════════════════════════════════════════════════════════════
# 4. EventBus 发布
# ═══════════════════════════════════════════════════════════════════

func _test_event_publish() -> void:
	_section_begin("4 EventBus 发布")
	var bus = EventBus.new()
	_ok(bus.ready, "bus ready")
	_eq(bus.current_seq(), 0, "初始 seq=0")
	_eq(bus.count(), 0, "初始 count=0")
	var r1: Dictionary = bus.publish(_ev("entity.spawn", 0.0, "world", "",
		{"entity": {"id": "apsis", "kind": "ship"}}))
	_eq(bool(r1.get("ok", false)), true, "publish 合法 ok", str(r1.get("errors", [])))
	_eq(bus.current_seq(), 1, "seq=1")
	_eq(bus.count(), 1, "count=1")
	var e: Dictionary = r1.get("event", {})
	_eq(String(e.get("schema", "")), "v17.event.v1", "event schema")
	_ok(String(e.get("id", "")) != "", "event id 自动生成")
	_eq(int(e.get("seq", -1)), 1, "event seq=1")
	_eq(String(e.get("type", "")), "entity.spawn", "event type")
	_ok(e.get("payload") is Dictionary, "event payload")
	var r2: Dictionary = bus.publish(_ev("entity.move", 1.5, "world", "apsis",
		{"pos_km": [0, 0, 1]}, "custom-evt-1"))
	_eq(bool(r2.get("ok", false)), true, "显式 id publish ok")
	_eq(String((r2.get("event", {}) as Dictionary).get("id", "")), "custom-evt-1", "显式 id")
	_eq(bus.current_seq(), 2, "seq=2")
	var last: Dictionary = bus.last_event()
	_eq(int(last.get("seq", -1)), 2, "last_event seq=2")
	_ok(bus.event_by_id("custom-evt-1").size() > 0, "event_by_id")
	_ok(bus.event_by_id("no_such").size() == 0, "event_by_id 未知")
	# 非法事件
	var bad1: Dictionary = bus.publish({"type": "", "t": 0.0, "source": "x"})
	_eq(bool(bad1.get("ok", true)), false, "缺 type 拒绝")
	var bad2: Dictionary = bus.publish({"type": "x", "t": 0.0})
	_eq(bool(bad2.get("ok", true)), false, "缺 source 拒绝")
	var bad3: Dictionary = bus.publish({"type": "x", "t": NAN, "source": "x"})
	_eq(bool(bad3.get("ok", true)), false, "NaN t 拒绝")
	var bad4: Dictionary = bus.publish({"type": "x", "t": -1.0, "source": "x"})
	_eq(bool(bad4.get("ok", true)), false, "负 t 拒绝")
	var bad5: Dictionary = bus.publish({"type": "x", "t": 0.0, "source": "x", "payload": []})
	_eq(bool(bad5.get("ok", true)), false, "payload 非对象拒绝")
	var bad6: Dictionary = bus.publish({"type": "x", "t": 0.0, "source": "x", "target": 5})
	_eq(bool(bad6.get("ok", true)), false, "target 非字符串拒绝")
	var dup: Dictionary = bus.publish(_ev("entity.move", 2.0, "world", "apsis", {}, "custom-evt-1"))
	_eq(bool(dup.get("ok", true)), false, "重复 event id 拒绝")
	_eq(bus.count(), 2, "非法发布不增加 count")
	_ok(bus.errors.size() > 0, "非法发布记录 errors")
	_ok(bus.check_invariants().get("ok", false), "bus 不变量 ok")
	_data_line("event_publish", "合法/显式 id/非法/重复 拒绝 · seq 单调")

func _test_event_filters_subs() -> void:
	_section_begin("5 EventBus 过滤/订阅")
	var bus = EventBus.new()
	bus.publish(_ev("entity.spawn", 0.0, "world", "", {"entity": {"id": "a", "kind": "ship"}}))
	bus.publish(_ev("entity.move", 1.0, "world", "a", {"pos_km": [0, 0, 0]}))
	bus.publish(_ev("order.issued", 2.0, "story", "a", {"kind": "move"}))
	bus.publish(_ev("order.done", 3.0, "world", "a"))
	var all_recent: Array = bus.recent(10)
	_eq(all_recent.size(), 4, "recent 4")
	_eq(int((all_recent[0] as Dictionary).get("seq", -1)), 1, "recent 顺序首 seq=1")
	_eq(int((all_recent[3] as Dictionary).get("seq", -1)), 4, "recent 顺序末 seq=4")
	var last2: Array = bus.recent(2)
	_eq(last2.size(), 2, "recent(2) 2 条")
	_eq(int((last2[0] as Dictionary).get("seq", -1)), 3, "recent(2) 首 seq=3")
	var entity_events: Array = bus.filter_events({"type": "entity"})
	_eq(entity_events.size(), 2, "type 前缀 entity 2 条")
	var order_events: Array = bus.filter_events({"type": "order", "source": "story"})
	_eq(order_events.size(), 1, "type+source 过滤")
	var by_target: Array = bus.filter_events({"target": "a"})
	_eq(by_target.size(), 3, "target 过滤 3 条")
	var since: Array = bus.filter_events({"since_t": 2.0})
	_eq(since.size(), 2, "since_t 过滤 2 条")
	var exact: Array = bus.filter_events({"type_exact": "entity.move"})
	_eq(exact.size(), 1, "type_exact 1 条")
	# 订阅
	var received: Array = []
	var received_order: Array = []
	var tok1: Dictionary = bus.subscribe("entity", func(ev): received.append(ev.get("seq", 0)))
	_eq(bool(tok1.get("ok", false)), true, "subscribe entity ok")
	_eq(bus.subscribers_count(), 1, "subscribers=1")
	var tok_all: Dictionary = bus.subscribe("", func(ev): received_order.append(ev.get("seq", 0)))
	_eq(bus.subscribers_count(), 2, "subscribers=2")
	var r: Dictionary = bus.publish(_ev("entity.flag", 4.0, "world", "a", {"key": "x", "value": 1}))
	_eq(int(r.get("dispatched", -1)), 2, "dispatched=2")
	_eq(received.size(), 1, "entity 订阅收到")
	# 注：订阅后仅新事件，故 received_order 应为 1；重新检查
	_eq(received_order.size(), 1, "全订阅仅收到新事件")
	bus.publish(_ev("order.issued", 5.0, "story", "a", {"kind": "x"}))
	_eq(received.size(), 1, "entity 订阅不收 order")
	_eq(received_order.size(), 2, "全订阅收到第二条")
	var un: Dictionary = bus.unsubscribe(int(tok1.get("token", -1)))
	_eq(bool(un.get("ok", false)), true, "unsubscribe ok")
	bus.publish(_ev("entity.move", 6.0, "world", "a", {"pos_km": [0, 0, 1]}))
	_eq(received.size(), 1, "取消后不再收到")
	var unk: Dictionary = bus.unsubscribe(99999)
	_eq(bool(unk.get("ok", true)), false, "未知 token 取消拒绝")
	_ok(bus.check_invariants().get("ok", false), "订阅后不变量 ok")
	_data_line("event_filters", "recent/前缀/target/since/exact · 订阅/取消/顺序")

# ═══════════════════════════════════════════════════════════════════
# 6. WorldState 基础
# ═══════════════════════════════════════════════════════════════════

func _test_world_basic() -> void:
	_section_begin("6 WorldState 基础")
	var ws = WorldState.new({"writer": "world"})
	_ok(ws.ready, "world ready", str(ws.errors))
	_eq(ws.current_writer(), "world", "writer=world")
	_eq(ws.entity_count(), 0, "初始 0 实体")
	var spawn := _ev("entity.spawn", 0.0, "world", "",
		{"entity": {"id": "apsis", "kind": "ship", "name": "远地点",
			"pos_km": [1, 2, 3], "vel_kmps": [0, 0, 0], "flags": {"own": true}}})
	var r1: Dictionary = ws.apply(spawn, "world")
	_eq(bool(r1.get("ok", false)), true, "spawn ok", str(r1.get("errors", [])))
	_eq(ws.entity_count(), 1, "entity_count=1")
	_eq(ws.version, 1, "version=1")
	var e: Dictionary = ws.entity("apsis")
	_eq(String(e.get("kind", "")), "ship", "entity kind")
	_eq(String(e.get("name", "")), "远地点", "entity name")
	_eq(bool((e.get("flags", {}) as Dictionary).get("own", false)), true, "entity flags")
	_eq(int(e.get("version", -1)), 1, "entity version=1")
	_eq(ws.event_refs.size(), 1, "event_ref 1")
	_ok(ws.has_entity("apsis"), "has_entity")
	_ok(not ws.has_entity("no"), "has_entity 未知 false")
	_ok(ws.entity("no").is_empty(), "entity 未知空")
	# move
	var r2: Dictionary = ws.apply(_ev("entity.move", 1.0, "world", "apsis",
		{"pos_km": [10, 20, 30], "vel_kmps": [0.1, 0.2, 0.3]}), "world")
	_eq(bool(r2.get("ok", false)), true, "move ok")
	var e2: Dictionary = ws.entity("apsis")
	_eq((e2.get("pos_km", []) as Array)[0], 10.0, "move pos 更新")
	_eq((e2.get("vel_kmps", []) as Array)[2], 0.3, "move vel 更新")
	_eq(int(e2.get("version", -1)), 2, "entity version=2")
	_eq(ws.version, 2, "world version=2")
	# flag/rename
	_eq(bool(ws.apply(_ev("entity.flag", 2.0, "world", "apsis",
		{"key": "selected", "value": true}), "world").get("ok", false)), true, "flag ok")
	_eq(bool(ws.entity("apsis").get("flags", {}).get("selected", false)), true, "flag 值")
	_eq(bool(ws.apply(_ev("entity.rename", 3.0, "world", "apsis",
		{"name": "旗舰"}), "world").get("ok", false)), true, "rename ok")
	_eq(String(ws.entity("apsis").get("name", "")), "旗舰", "rename 值")
	_eq(bool(ws.apply(_ev("world.note", 4.0, "world", "",
		{"text": "note"}), "world").get("ok", false)), true, "note ok")
	# snapshot 只读
	var snap: Dictionary = ws.snapshot()
	_eq(String(snap.get("schema", "")), "v17.world_state.v1", "snapshot schema")
	_eq(int(snap.get("entity_count", -1)), 1, "snapshot entity_count")
	_eq((snap.get("entities", []) as Array).size(), 1, "snapshot entities 1")
	var ents: Array = snap.get("entities", [])
	var copy: Dictionary = ents[0]
	copy["name"] = "MUTATED"
	_eq(String(ws.entity("apsis").get("name", "")), "旗舰", "snapshot 深拷贝只读")
	_ok(snap.get("invariants", {}).get("ok", false), "snapshot 不变量 ok")
	_ok(snap.get("event_refs") is Array, "snapshot event_refs")
	# despawn
	_eq(bool(ws.apply(_ev("entity.despawn", 5.0, "world", "apsis"), "world").get("ok", false)),
		true, "despawn ok")
	_eq(ws.entity_count(), 0, "despawn 后 0 实体")
	_ok(ws.check_invariants().get("ok", false), "world 不变量 ok")
	_data_line("world_basic", "spawn/move/flag/rename/note/despawn · snapshot 只读")

func _test_world_writer() -> void:
	_section_begin("7 WorldState 单写者")
	var ws = WorldState.new({"writer": "world"})
	var conflict: Dictionary = ws.claim_writer("other")
	_eq(bool(conflict.get("ok", true)), false, "writer 冲突拒绝")
	_eq(String(conflict.get("reason", "")), "writer_conflict", "冲突 reason")
	_eq(bool(ws.claim_writer("world").get("ok", false)), true, "相同 writer 认领 ok")
	var no_writer = WorldState.new({"writer": ""})
	_eq(no_writer.ready, true, "无 writer setup ready")
	var spawn := _ev("entity.spawn", 0.0, "world", "",
		{"entity": {"id": "a", "kind": "ship"}})
	var fail: Dictionary = no_writer.apply(spawn, "")
	_eq(bool(fail.get("ok", true)), false, "未认领 writer 拒绝")
	_eq(String(fail.get("reason", "")), "no_writer", "no_writer reason")
	var claim: Dictionary = no_writer.claim_writer("w1")
	_eq(bool(claim.get("ok", false)), true, "claim w1")
	var claim2: Dictionary = no_writer.claim_writer("w2")
	_eq(bool(claim2.get("ok", true)), false, "第二写者拒绝")
	var wrong: Dictionary = no_writer.apply(spawn, "w2")
	_eq(bool(wrong.get("ok", true)), false, "错误 token 拒绝")
	_eq(String(wrong.get("reason", "")), "writer_mismatch", "writer_mismatch reason")
	var ok: Dictionary = no_writer.apply(spawn, "w1")
	_eq(bool(ok.get("ok", false)), true, "正确 token 写入 ok")
	var rel_bad: Dictionary = no_writer.release_writer("w2")
	_eq(bool(rel_bad.get("ok", true)), false, "错误 token release 拒绝")
	var rel: Dictionary = no_writer.release_writer("w1")
	_eq(bool(rel.get("ok", false)), true, "release w1")
	_eq(bool(no_writer.claim_writer("w2").get("ok", false)), true, "release 后认领 w2")
	_data_line("world_writer", "单写者 claim/冲突/错误 token 拒绝/释放")

func _test_world_rejections() -> void:
	_section_begin("8 WorldState 拒绝")
	var ws = WorldState.new({"writer": "world"})
	ws.apply(_ev("entity.spawn", 0, "world", "", {"entity": {"id": "a", "kind": "ship"}}), "world")
	var v0: int = ws.version
	var c0: int = ws.entity_count()
	var dup: Dictionary = ws.apply(_ev("entity.spawn", 1, "world", "",
		{"entity": {"id": "a", "kind": "ship"}}), "world")
	_eq(bool(dup.get("ok", true)), false, "重复 spawn 拒绝")
	_eq(String(dup.get("reason", "")), "duplicate_entity", "duplicate reason")
	var missing: Dictionary = ws.apply(_ev("entity.move", 1, "world", "no",
		{"pos_km": [0, 0, 0]}), "world")
	_eq(bool(missing.get("ok", true)), false, "move 未知实体拒绝")
	var bad_id: Dictionary = ws.apply(_ev("entity.spawn", 1, "world", "",
		{"entity": {"id": "Bad-ID", "kind": "ship"}}), "world")
	_eq(bool(bad_id.get("ok", true)), false, "非法实体 id 拒绝")
	var bad_pos: Dictionary = ws.apply(_ev("entity.spawn", 1, "world", "",
		{"entity": {"id": "b", "kind": "ship", "pos_km": [NAN, 0, 0]}}), "world")
	_eq(bool(bad_pos.get("ok", true)), false, "NaN 位置拒绝")
	var bad_move: Dictionary = ws.apply(_ev("entity.move", 1, "world", "a",
		{"pos_km": [1, 2]}), "world")
	_eq(bool(bad_move.get("ok", true)), false, "非法 move pos 拒绝")
	var bad_type: Dictionary = ws.apply(_ev("entity.teleport", 1, "world", "a"), "world")
	_eq(bool(bad_type.get("ok", true)), false, "非白名单事件拒绝")
	_eq(String(bad_type.get("reason", "")), "invalid_event", "非法事件 reason")
	var bad_payload: Dictionary = ws.apply(_ev("entity.flag", 1, "world", "a",
		{"key": "", "value": 1}), "world")
	_eq(bool(bad_payload.get("ok", true)), false, "flag 空 key 拒绝")
	var bad_rename: Dictionary = ws.apply(_ev("entity.rename", 1, "world", "a",
		{"name": ""}), "world")
	_eq(bool(bad_rename.get("ok", true)), false, "rename 空名拒绝")
	var bad_src: Dictionary = ws.apply({"type": "entity.flag", "t": 1, "source": "",
		"target": "a", "payload": {"key": "x", "value": 1}}, "world")
	_eq(bool(bad_src.get("ok", true)), false, "缺 source 事件拒绝")
	var bad_t: Dictionary = ws.apply({"type": "entity.flag", "t": NAN, "source": "world",
		"target": "a", "payload": {"key": "x", "value": 1}}, "world")
	_eq(bool(bad_t.get("ok", true)), false, "NaN t 事件拒绝")
	_eq(ws.version, v0, "拒绝事件不增加 version")
	_eq(ws.entity_count(), c0, "拒绝事件不改变实体数")
	_ok(ws.errors.size() > 0, "拒绝记录 errors")
	_ok(ws.contract_errors.size() > 0, "拒绝记录 contract_errors")
	_ok(ws.check_invariants().get("ok", false), "拒绝后不变量 ok")
	_data_line("world_rejections", "重复/未知/非法 id/NaN/非白名单/source/t 拒绝且无副作用")

# ═══════════════════════════════════════════════════════════════════
# 9. 跨模块（时钟引用 / bus→world）
# ═══════════════════════════════════════════════════════════════════

func _test_cross() -> void:
	_section_begin("9 跨模块")
	var time = TimeService.new({"t_s": 0.0})
	time.tick(10.0)
	var ws = WorldState.new({"writer": "world", "time": time})
	_eq(ws.clock_t_s(), 10.0, "world 时钟引用 t=10")
	var bus = EventBus.new()
	var pub: Dictionary = bus.publish(_ev("entity.spawn", 10.0, "world", "",
		{"entity": {"id": "b", "kind": "station", "pos_km": [5, 6, 7]}}))
	_eq(bool(pub.get("ok", false)), true, "bus 发布 spawn ok")
	# bus 不直接写 world
	_eq(ws.entity_count(), 0, "bus 发布不自动写 world")
	var ev: Dictionary = pub.get("event", {})
	var applied: Dictionary = ws.apply(ev, "world")
	_eq(bool(applied.get("ok", false)), true, "bus 事件交 world 应用 ok", str(applied.get("errors", [])))
	_eq(ws.entity_count(), 1, "world 应用后 1 实体")
	_eq(ws.event_refs.size(), 1, "world event_ref 1")
	_eq(String((ws.event_refs[0] as Dictionary).get("type", "")), "entity.spawn", "event_ref type")
	var illegal_pub: Dictionary = bus.publish(_ev("entity.teleport", 11.0, "world", "b"))
	_eq(bool(illegal_pub.get("ok", false)), true, "bus 可发布任意 type")
	var wf: Dictionary = ws.apply(illegal_pub.get("event", {}), "world")
	_eq(bool(wf.get("ok", true)), false, "world 拒绝非白名单 bus 事件")
	_eq(ws.entity_count(), 1, "非法事件不改变 world")
	# 时间在事件时间中保留
	var et: Dictionary = time.event_time()
	_near(float(et.get("t_s", -1.0)), time.now_s(), 1.0e-9, "事件时间=t")
	_data_line("cross", "time 引用/bus 发布不写 world/world 只接受白名单事件")

# ═══════════════════════════════════════════════════════════════════
# 10. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("10 JSON/确定性")
	var tjs := JSON.stringify(TimeService.new().snapshot())
	_ok(tjs.length() > 300, "time snapshot JSON", "len=%d" % tjs.length())
	_ok(JSON.parse_string(tjs) is Dictionary, "time snapshot 回读")
	var bus = EventBus.new()
	bus.publish(_ev("entity.spawn", 0, "world", "", {"entity": {"id": "a", "kind": "ship"}}))
	bus.publish(_ev("entity.move", 1, "world", "a", {"pos_km": [1, 2, 3]}))
	var bjs := JSON.stringify(bus.snapshot())
	_ok(bjs.length() > 400, "bus snapshot JSON", "len=%d" % bjs.length())
	var bp = JSON.parse_string(bjs)
	_ok(bp is Dictionary, "bus snapshot 回读")
	if bp is Dictionary:
		_eq(int((bp as Dictionary).get("count", -1)), 2, "回读 bus count=2")
	var ws = WorldState.new({"writer": "world"})
	ws.apply(_ev("entity.spawn", 0, "world", "", {"entity": {"id": "a", "kind": "ship"}}), "world")
	ws.apply(_ev("entity.move", 1, "world", "a", {"pos_km": [4, 5, 6]}), "world")
	var wjs := JSON.stringify(ws.snapshot())
	_ok(wjs.length() > 400, "world snapshot JSON", "len=%d" % wjs.length())
	_ok(JSON.parse_string(wjs) is Dictionary, "world snapshot 回读")
	# 确定性：两次同操作
	var ws2 = WorldState.new({"writer": "world"})
	ws2.apply(_ev("entity.spawn", 0, "world", "", {"entity": {"id": "a", "kind": "ship"}}), "world")
	ws2.apply(_ev("entity.move", 1, "world", "a", {"pos_km": [4, 5, 6]}), "world")
	_ok(JSON.stringify(ws.snapshot()) == JSON.stringify(ws2.snapshot()),
		"world 同操作 snapshot 一致（确定性）")
	var bus2 = EventBus.new()
	bus2.publish(_ev("entity.spawn", 0, "world", "", {"entity": {"id": "a", "kind": "ship"}}))
	bus2.publish(_ev("entity.move", 1, "world", "a", {"pos_km": [1, 2, 3]}))
	_ok(JSON.stringify(bus.snapshot()) == JSON.stringify(bus2.snapshot()),
		"bus 同事件 snapshot 一致（确定性）")
	var t1 = TimeService.new()
	var t2 = TimeService.new()
	t1.tick(5.0)
	t2.tick(5.0)
	_ok(JSON.stringify(t1.snapshot()) == JSON.stringify(t2.snapshot()),
		"time 同输入 snapshot 一致（确定性）")
	_data_line("json_determinism", "三个内核 snapshot JSON 可回读 · 同输入确定性")
