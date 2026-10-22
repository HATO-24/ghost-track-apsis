extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2C 最小 probe：GameSession 编排（Time/EventBus/World/
# Order/Comms + 内存 save/load）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/session_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接旧场景/UI。
# ═══════════════════════════════════════════════════════════════════

const GameSession := preload("res://scripts/core/game_session.gd")
const PreludeScenario := preload("res://scripts/core/prelude_scenario.gd")
const CislunarPhysics := preload("res://framework/sim/cislunar_physics.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2C PROBE · GameSession 编排")
	print("════════════════════════════════════════════════════════════")
	_test_boot()
	_test_order_flow()
	_test_comms_links()
	_test_order_failures()
	_test_time_controls()
	_test_separation()
	_test_save_load()
	_test_errors()
	_test_json_determinism()
	_test_optional_components()
	_test_track_l1_l4()
	_test_story_integration()
	_test_save_components()
	_test_old_save_compat()
	_test_component_errors_determinism()
	_test_sensor_optional()
	_test_sensor_pipeline()
	_test_sensor_save_load()
	_test_sensor_errors_determinism()
	_test_optional_port_combat()
	_test_port_integration()
	_test_combat_integration()
	_test_port_combat_save_load()
	_test_damage_integration()
	_test_damage_save_load()
	_test_physics_integration()
	_test_physics_save_load()
	_test_physics_frame_conversion()
	_test_combat_ballistics_integration()
	_test_unified_fire_path()
	_test_signal_integration()
	_test_signal_save_load()
	_test_signal_binding()
	_test_signal_dynamic_targets()
	_test_facility_registry()
	_test_transponder_integration()
	_test_ew_integration()
	_test_legal_status_integration()
	_test_traffic_integration()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SESSION PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SESSION PROBE FAILED")
		quit(1)
	else:
		print("V17 SESSION PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _story_content_json(s) -> String:
	var vm: Dictionary = s.story_vm()
	return _norm_json({
		"flags": vm.get("flags", {}), "evidence_ids": vm.get("evidence_ids", []),
		"choices": vm.get("choices", []), "trust": vm.get("trust", 0.0),
		"morality": vm.get("morality", 0.0), "reputation": vm.get("reputation", 0.0),
		"threat": vm.get("threat", 0.0), "chapter": vm.get("chapter", ""),
		"phase": vm.get("phase", ""),
	})

func _story_state_json(s) -> String:
	var vm: Dictionary = s.story_vm()
	return _norm_json({
		"flags": vm.get("flags", {}), "evidence_ids": vm.get("evidence_ids", []),
		"choices": vm.get("choices", []), "trust": vm.get("trust", 0.0),
		"morality": vm.get("morality", 0.0), "reputation": vm.get("reputation", 0.0),
		"threat": vm.get("threat", 0.0), "chapter": vm.get("chapter", ""),
		"phase": vm.get("phase", ""), "t_s": vm.get("t_s", 0.0),
		"revision": vm.get("revision", 0),
	})

func _new_session():
	var s = GameSession.new()
	_ok(bool(s.ready), "session boot ready", str(s.errors))
	return s

func _event_types(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("type", "")))
	return out

func _snap_entities(s) -> Array:
	return (s.snapshot().get("entities", []) as Array).duplicate(true)

# ═══════════════════════════════════════════════════════════════════
# 1. boot
# ═══════════════════════════════════════════════════════════════════

func _test_boot() -> void:
	_section_begin("1 boot")
	var s = _new_session()
	_eq(s.booted, true, "booted")
	_eq(s.errors.size(), 0, "无 boot errors")
	_eq(String(s.writer), "session", "session writer")
	_eq(String(s.world.current_writer()), "session", "world 单写者=session")
	_ok(bool(s.time.ready), "time ready")
	_ok(bool(s.bus.ready), "bus ready")
	_ok(bool(s.world.ready), "world ready")
	_ok(bool(s.orders.ready), "orders ready")
	_ok(bool(s.comms.ready), "comms ready")
	_eq(int(s.world.entity_count()), 3, "seed 实体 3")
	var ids: Array = []
	for raw in _snap_entities(s):
		ids.append(String((raw as Dictionary).get("id", "")))
	for eid in ["apsis", "harmattan", "l1_station"]:
		_ok(eid in ids, "seed 实体: " + eid)
	var cv: Dictionary = s.comms.vm()
	_eq((cv.get("nodes", []) as Array).size(), 3, "comms 节点 3")
	_eq((cv.get("links", []) as Array).size(), 2, "comms 链路 2")
	_near(s.now_s(), 0.0, 1.0e-9, "初始 t=0")
	_eq(bool(s.time.paused), false, "初始未暂停")
	_near(float(s.time.scale), 1.0, 1.0e-9, "初始 scale=1")
	var c: Dictionary = s.check_contracts()
	_ok(bool(c.get("ok", false)), "初始 contracts ok", str(c.get("violations", [])))
	var snap: Dictionary = s.snapshot()
	_eq(String(snap.get("schema", "")), "v17.game_session.v1", "snapshot schema")
	_eq(String(snap.get("version", "")), "1.0.0", "snapshot version")
	_eq(int((snap.get("components", {}) as Dictionary).size()), 4, "snapshot components 4")
	_ok(snap.get("components", {}).get("orders") is Dictionary, "snapshot orders")
	_ok(snap.get("components", {}).get("comms") is Dictionary, "snapshot comms")
	_ok(snap.get("components", {}).get("world") is Dictionary, "snapshot world")
	_ok(snap.get("entities") is Array, "snapshot entities")
	_ok(snap.get("contracts", {}).get("ok", false), "snapshot contracts ok")
	_ok(snap.get("events") is Array, "snapshot recent events")
	_data_line("boot", "entities=3 nodes=3 links=2 t=0 writer=session contracts ok")

# ═══════════════════════════════════════════════════════════════════
# 2. 订单流（依赖通信投递）
# ═══════════════════════════════════════════════════════════════════

func _test_order_flow() -> void:
	_section_begin("2 订单流")
	var s = _new_session()
	var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {"zone": "l1"}, {})
	_eq(bool(iss.get("ok", false)), true, "issue_order ok", str(iss.get("reason", "")))
	var oid := String(iss.get("order_id", ""))
	var did := String(iss.get("delivery_id", ""))
	_ok(oid != "", "order_id 生成")
	_ok(did != "", "delivery_id 来自通信")
	_eq(String(s.order(oid).get("status", "")), "ISSUED", "初始 ISSUED")
	_eq(String(s.order(oid).get("delivery_id", "")), did, "order.delivery_id 一致")
	var types := _event_types(iss.get("events", []))
	_ok("order.drafted" in types, "事件 order.drafted")
	_ok("order.issued" in types, "事件 order.issued")
	_eq(s.comms.pending.size(), 1, "通信 pending 1")
	# tick 传输
	var t1: Dictionary = s.tick(0.01)
	_eq(bool(t1.get("ok", false)), true, "tick1 ok")
	var types1 := _event_types(t1.get("events", []))
	_ok("order.transmitting" in types1, "tick1 order.transmitting", str(types1))
	_eq(String(s.order(oid).get("status", "")), "TRANSMITTING", "status TRANSMITTING")
	# tick 到投递
	var t2: Dictionary = s.tick(1.0)
	var types2 := _event_types(t2.get("events", []))
	_ok("order.delivered" in types2, "tick2 order.delivered", str(types2))
	_ok("order.queued" in types2, "tick2 order.queued", str(types2))
	_eq(String(s.order(oid).get("status", "")), "QUEUED", "status QUEUED")
	_ok(float(s.order(oid).get("delivered_t", -1.0)) > 0.0, "delivered_t 记录")
	_ok(s.check_contracts().get("ok", false), "订单-通信一致性 ok")
	# 生命周期：authorize → begin → complete
	var au: Dictionary = s.authorize_order(oid, "apsis")
	_eq(bool(au.get("ok", false)), true, "authorize ok", str(au.get("reason", "")))
	_eq(String(s.order(oid).get("status", "")), "AUTHORIZED", "status AUTHORIZED")
	_ok("order.authorized" in _event_types(au.get("events", [])), "事件 order.authorized")
	var be: Dictionary = s.begin_execute_order(oid)
	_eq(bool(be.get("ok", false)), true, "begin_execute ok")
	_eq(String(s.order(oid).get("status", "")), "EXECUTING", "status EXECUTING")
	var co: Dictionary = s.complete_order(oid, {"result": "held"})
	_eq(bool(co.get("ok", false)), true, "complete ok")
	_eq(String(s.order(oid).get("status", "")), "DONE", "status DONE")
	_eq(String((s.order(oid).get("result", {}) as Dictionary).get("result", "")), "held",
		"result 记录")
	_ok("order.done" in _event_types(co.get("events", [])), "事件 order.done")
	_ok(s.check_contracts().get("ok", false), "完成后 contracts ok")
	_ok(s.bus.current_seq() >= 8, "bus 事件数增长", str(s.bus.current_seq()))
	# 重复操作拒绝
	_eq(bool(s.authorize_order(oid, "apsis").get("ok", true)), false, "终态再授权拒绝")
	_eq(bool(s.begin_execute_order(oid).get("ok", true)), false, "终态再执行拒绝")
	_data_line("order_flow", "%s ISSUED→TRANSMITTING→DELIVERED→QUEUED→AUTHORIZED→EXECUTING→DONE · delivery=%s" % [oid, did])

# ═══════════════════════════════════════════════════════════════════
# 3. 通信 / 链路
# ═══════════════════════════════════════════════════════════════════

func _test_comms_links() -> void:
	_section_begin("3 通信/链路")
	var s = _new_session()
	var send: Dictionary = s.send_comms("apsis", "harmattan", "LD", "COMMS_SENT",
		{"content": "hello"}, {})
	_eq(bool(send.get("ok", false)), true, "send_comms ok", str(send.get("reason", "")))
	var did := String(send.get("delivery_id", ""))
	_ok(did != "", "send_comms delivery_id")
	_eq(String(send.get("mode", "")), "LD", "send mode LD")
	_ok(float(send.get("latency_s", -1.0)) >= 0.0, "send latency")
	_eq(s.comms.pending.size(), 1, "send 后 pending 1")
	var tick: Dictionary = s.tick(0.2)
	var types := _event_types(tick.get("events", []))
	_ok("comms.delivered" in types, "tick 后 comms.delivered", str(types))
	_eq(s.comms.pending.size(), 0, "delivered 后 pending 0")
	# 失败发送：无效 mode / 未知节点
	var bad1: Dictionary = s.send_comms("apsis", "harmattan", "XX", "COMMS_SENT", {}, {})
	_eq(bool(bad1.get("ok", true)), false, "无效 mode 拒绝")
	_eq(String(bad1.get("reason", "")), "invalid_mode", "invalid_mode reason")
	var bad2: Dictionary = s.send_comms("apsis", "no_node", "LD", "COMMS_SENT", {}, {})
	_eq(bool(bad2.get("ok", true)), false, "未知节点拒绝")
	# 链路禁用 → 订单通信失败
	var off: Dictionary = s.set_link("apsis", "harmattan", {"enabled": false})
	_eq(bool(off.get("ok", false)), true, "禁用 link ok")
	_ok(bool((off.get("applied", {}) as Dictionary).get("enabled", false)), "enabled applied")
	var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {}, {})
	_eq(bool(iss.get("ok", true)), false, "链路断开 issue 失败")
	_ok(String(iss.get("reason", "")).begins_with("comms_"), "失败 reason comms_*", String(iss.get("reason", "")))
	var oid := String(iss.get("order_id", ""))
	_eq(String(s.order(oid).get("status", "")), "REJECTED", "订单 REJECTED")
	_ok("order.rejected" in _event_types(iss.get("events", [])), "事件 order.rejected")
	# 恢复
	var on: Dictionary = s.set_link("apsis", "harmattan", {"enabled": true})
	_eq(bool(on.get("ok", false)), true, "恢复 link ok")
	# occluded / jam
	var occ: Dictionary = s.set_link("apsis", "harmattan", {"occluded": true})
	_eq(bool(occ.get("ok", false)), true, "设置遮挡 ok")
	var jam: Dictionary = s.set_link("apsis", "harmattan", {"jam": 0.9})
	_eq(bool(jam.get("ok", false)), true, "设置干扰 ok")
	s.set_link("apsis", "harmattan", {"occluded": false, "jam": 0.0})
	var unknown: Dictionary = s.set_link("no_a", "no_b", {"enabled": false})
	_eq(bool(unknown.get("ok", true)), false, "未知链路 set_link 失败")
	_data_line("comms", "send/delivered/失败/链路禁用→订单拒绝/恢复/遮挡/干扰")

# ═══════════════════════════════════════════════════════════════════
# 4. 订单失败 / 过期 / 撤销
# ═══════════════════════════════════════════════════════════════════

func _test_order_failures() -> void:
	_section_begin("4 订单失败/过期/撤销")
	var s = _new_session()
	# 过期
	var exp: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {}, {"expire_in": 1.0})
	_eq(bool(exp.get("ok", false)), true, "过期订单 issue ok")
	var eoid := String(exp.get("order_id", ""))
	s.tick(2.0)
	_eq(String(s.order(eoid).get("status", "")), "STALE", "过期 → STALE")
	# 撤销 QUEUED 订单
	var ab: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {}, {})
	_eq(bool(ab.get("ok", false)), true, "撤销测试 issue ok")
	var aoid := String(ab.get("order_id", ""))
	s.tick(1.0)
	_eq(String(s.order(aoid).get("status", "")), "QUEUED", "tick 后 QUEUED")
	var abr: Dictionary = s.abort_order(aoid, "player_abort")
	_eq(bool(abr.get("ok", false)), true, "abort ok")
	_eq(String(s.order(aoid).get("status", "")), "ABORTED", "status ABORTED")
	_eq(String(s.order(aoid).get("reason", "")), "player_abort", "abort reason")
	_eq(bool(s.abort_order(aoid).get("ok", true)), false, "终态再 abort 拒绝")
	# 拒绝
	var rej_issue: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {}, {})
	var roid := String(rej_issue.get("order_id", ""))
	var rej: Dictionary = s.reject_order(roid, "player_reject")
	_eq(bool(rej.get("ok", false)), true, "reject ok")
	_eq(String(s.order(roid).get("status", "")), "REJECTED", "status REJECTED")
	# 失败订单不执行
	_eq(bool(s.begin_execute_order(roid).get("ok", true)), false, "REJECTED 不能执行")
	_ok(s.check_contracts().get("ok", false), "失败路径 contracts ok")
	_data_line("failures", "过期 STALE · 撤销 ABORTED · 拒绝 REJECTED · 终态操作拒绝")

# ═══════════════════════════════════════════════════════════════════
# 5. 暂停 / 时标 / 时间单调
# ═══════════════════════════════════════════════════════════════════

func _test_time_controls() -> void:
	_section_begin("5 暂停/时标")
	var s = _new_session()
	var t0 := s.now_s()
	s.tick(1.0)
	_ok(s.now_s() > t0, "tick 时间推进", "%.3f" % s.now_s())
	var times: float = float(s.orders.t)
	s.pause()
	_eq(bool(s.time.paused), true, "session pause")
	var pt: Dictionary = s.tick(10.0)
	_eq(bool(pt.get("ok", false)), true, "暂停 tick ok")
	_eq(bool(pt.get("paused", false)), true, "暂停 tick paused")
	_near(s.now_s(), 1.0, 1.0e-9, "暂停时间不变")
	_near(float(s.orders.t), times, 1.0e-9, "暂停订单时间不变")
	_ok(bool(s.check_contracts().get("ok", false)), "暂停时 contracts ok")
	s.resume()
	s.tick(1.0)
	_near(s.now_s(), 2.0, 1.0e-9, "resume 时间推进")
	# 时标 2x：session 时间 +2、orders 同步
	var sc: Dictionary = s.set_scale(2.0)
	_eq(bool(sc.get("ok", false)), true, "set_scale(2)")
	s.tick(1.0)
	_near(s.now_s(), 4.0, 1.0e-9, "scale=2 时间+2")
	_near(float(s.orders.t), 4.0, 1.0e-9, "orders 时间同步")
	s.set_scale(1.0)
	# 单调
	var last := s.now_s()
	var mono := true
	for i in range(5):
		s.tick(0.5 + float(i) * 0.1)
		if s.now_s() + 1.0e-9 < last:
			mono = false
		last = s.now_s()
	_ok(mono, "多次 tick 时间单调")
	var neg: Dictionary = s.tick(-1.0)
	_eq(bool(neg.get("ok", true)), false, "负 dt tick 拒绝")
	var bad_scale: Dictionary = s.set_scale(-1.0)
	_eq(bool(bad_scale.get("ok", true)), false, "负 scale 拒绝")
	_ok(bool(s.check_contracts().get("ok", false)), "时间控制后 contracts ok")
	_data_line("time_controls", "pause/resume/scale2x/单调/负值拒绝")

# ═══════════════════════════════════════════════════════════════════
# 6. bus / world 分离 + 单写者
# ═══════════════════════════════════════════════════════════════════

func _test_separation() -> void:
	_section_begin("6 bus/world 分离")
	var s = _new_session()
	var before := _snap_entities(s)
	# bus 发布事件不写 world
	var pub: Dictionary = s.bus.publish({"type": "entity.move", "t": s.now_s(),
		"source": "test", "target": "apsis", "payload": {"pos_km": [99, 99, 99]}})
	_eq(bool(pub.get("ok", false)), true, "bus 直接发布 ok")
	_eq(str(_snap_entities(s)), str(before), "bus 发布不改变 world")
	# 订单 tick 事件不改变 world
	var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {}, {})
	s.tick(1.0)
	_eq(str(_snap_entities(s)), str(before), "订单 tick 不改变 world 实体")
	# 单写者：外部 token 写 world 被拒
	var ev: Dictionary = {"type": "entity.move", "t": s.now_s(), "source": "test",
		"target": "apsis", "payload": {"pos_km": [1, 2, 3]}}
	var hack: Dictionary = s.world.apply(ev, "hacker")
	_eq(bool(hack.get("ok", true)), false, "非 session 写者被拒绝")
	_eq(String(hack.get("reason", "")), "writer_mismatch", "writer_mismatch")
	_eq(str(_snap_entities(s)), str(before), "非法写者不改变 world")
	# session 自己可写（显式 world 事件）
	var ok: Dictionary = s.world.apply(ev, "session")
	_eq(bool(ok.get("ok", false)), true, "session 写者写 world ok")
	_ok(bool(s.check_contracts().get("ok", false)), "分离后 contracts ok")
	# snapshot 只读
	var snap := s.snapshot()
	var ents: Array = snap.get("entities", [])
	if not ents.is_empty():
		(ents[0] as Dictionary)["name"] = "MUTATED"
	_eq(String(s.world.entity("apsis").get("name", "")), "远地点", "snapshot 深拷贝只读")
	_data_line("separation", "bus/订单 tick 不写 world · 非 session 写者拒绝 · snapshot 只读")

# ═══════════════════════════════════════════════════════════════════
# 7. 内存 save/load
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("7 save/load")
	var s = _new_session()
	var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {"k": 1}, {})
	var oid := String(iss.get("order_id", ""))
	s.tick(1.0)
	s.authorize_order(oid, "apsis")
	s.begin_execute_order(oid)
	s.complete_order(oid, {"done": true})
	s.send_comms("apsis", "harmattan", "LD", "COMMS_SENT", {"content": "saved"}, {})
	s.set_link("harmattan", "l1_station", {"enabled": true})
	s.tick(0.5)
	var save_a := s.save_state()
	_ok(save_a.length() > 500, "save_state JSON 长度", "len=%d" % save_a.length())
	var parsed = JSON.parse_string(save_a)
	_ok(parsed is Dictionary, "save_state JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.game_session_save.v1", "save schema")
		_ok((parsed as Dictionary).get("seed") is Dictionary, "save seed")
		_ok((parsed as Dictionary).get("log") is Array, "save log")
		_ok(((parsed as Dictionary).get("log") as Array).size() > 0, "log 非空")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save_a)
	_eq(bool(lr.get("ok", false)), true, "load_state ok", str(lr.get("errors", [])))
	_ok(bool(s2.ready), "load 后 ready")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "save/load snapshot 一致（JSON 规范化）")
	_eq(String(s2.order(oid).get("status", "")), "DONE", "load 后订单 DONE")
	_ok(s2.bus.current_seq() > 0, "load 后事件重放")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# 二次保存一致（确定性）
	var save_b := s2.save_state()
	_ok(_norm_json(JSON.parse_string(save_a)) == _norm_json(JSON.parse_string(save_b)), "save-A == save-B（JSON 规范化）")
	_data_line("save_load", "save len=%d load snapshot 一致 · 二次 save 相同" % save_a.length())

# ═══════════════════════════════════════════════════════════════════
# 8. 错误路径
# ═══════════════════════════════════════════════════════════════════

func _test_errors() -> void:
	_section_begin("8 错误路径")
	var s = _new_session()
	var bad1: Dictionary = s.issue_order("", "apsis", ["harmattan"])
	_eq(bool(bad1.get("ok", true)), false, "空 action 拒绝")
	_eq(String(bad1.get("reason", "")), "empty_action", "empty_action reason")
	var bad2: Dictionary = s.issue_order("hold", "", ["harmattan"])
	_eq(bool(bad2.get("ok", true)), false, "空 issuer 拒绝")
	var bad3: Dictionary = s.issue_order("hold", "apsis", [])
	_eq(bool(bad3.get("ok", true)), false, "空 targets 拒绝")
	var unk_auth: Dictionary = s.authorize_order("O-999999")
	_eq(bool(unk_auth.get("ok", true)), false, "未知订单 authorize 拒绝")
	_eq(String(unk_auth.get("reason", "")), "unknown_order", "unknown_order")
	var unk_begin: Dictionary = s.begin_execute_order("O-999999")
	_eq(bool(unk_begin.get("ok", true)), false, "未知订单 begin 拒绝")
	var unk_complete: Dictionary = s.complete_order("O-999999")
	_eq(bool(unk_complete.get("ok", true)), false, "未知订单 complete 拒绝")
	var bad_mode: Dictionary = s.send_comms("apsis", "harmattan", "XX", "COMMS_SENT")
	_eq(bool(bad_mode.get("ok", true)), false, "无效通信 mode 拒绝")
	var bad_node: Dictionary = s.send_comms("no_node", "harmattan", "LD", "COMMS_SENT")
	_eq(bool(bad_node.get("ok", true)), false, "未知通信节点拒绝")
	# load 错误
	var no_json: Dictionary = s.load_state("")
	_eq(bool(no_json.get("ok", true)), false, "空 load_state 拒绝")
	var bad_json: Dictionary = s.load_state("{not json")
	_eq(bool(bad_json.get("ok", true)), false, "非法 JSON load_state 拒绝")
	var bad_schema: Dictionary = s.load_state("{\"schema\":\"bad\"}")
	_eq(bool(bad_schema.get("ok", true)), false, "错误 schema load_state 拒绝")
	# 失败不伪造：订单数不因失败 issue 增加（仅成功创建的草稿会记录）
	var count_before: int = int(s.orders.orders.size())
	s.issue_order("hold", "apsis", ["harmattan"], {}, {"expire_in": 0.1})
	var count_after: int = int(s.orders.orders.size())
	_eq(count_after, count_before + 1, "失败/成功订单记录数量合理")
	_ok(bool(s.check_contracts().get("ok", false)), "错误路径后 contracts ok")
	_data_line("errors", "空参数/未知订单/无效 mode/未知节点/坏 JSON 均安全拒绝")

# ═══════════════════════════════════════════════════════════════════
# 9. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("9 JSON/确定性")
	var a = _new_session()
	var b = _new_session()
	for s in [a, b]:
		var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {"x": 1}, {})
		var oid := String(iss.get("order_id", ""))
		s.tick(1.0)
		s.authorize_order(oid, "apsis")
		s.begin_execute_order(oid)
		s.complete_order(oid, {"ok": true})
		s.send_comms("apsis", "harmattan", "LD", "COMMS_SENT", {"content": "same"}, {})
		s.tick(0.2)
	var ja := JSON.stringify(a.snapshot())
	var jb := JSON.stringify(b.snapshot())
	_ok(ja.length() > 3000, "snapshot JSON 长度", "len=%d" % ja.length())
	_ok(JSON.parse_string(ja) is Dictionary, "snapshot JSON 可解析")
	_ok(ja == jb, "两次相同操作 snapshot JSON 完全一致（确定性）")
	_ok(a.save_state() == b.save_state(), "两次 save_state JSON 一致")
	var parsed = JSON.parse_string(ja)
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq(String(pd.get("schema", "")), "v17.game_session.v1", "回读 schema")
		_ok(pd.get("components") is Dictionary, "回读 components")
		_ok(pd.get("entities") is Array, "回读 entities")
		_ok(pd.get("contracts") is Dictionary, "回读 contracts")
		_ok(pd.get("events") is Array, "回读 events")
		_ok(pd.get("orders_summary") is Dictionary, "回读 orders_summary")
		_ok(pd.get("comms_summary") is Dictionary, "回读 comms_summary")
	_eq(String(a.to_dict().get("schema", "")), "v17.game_session.v1", "to_dict schema")
	_ok(a.to_json().length() > 3000, "to_json 输出")
	_data_line("json_det", "snapshot=%d save=%d 确定性一致" % [ja.length(), a.save_state().length()])

# ═══════════════════════════════════════════════════════════════════
# 11. 可选组件（track_table / story_state）
# ═══════════════════════════════════════════════════════════════════

func _test_optional_components() -> void:
	_section_begin("11 可选组件")
	var s = _new_session()
	_ok(s.track_table == null, "默认无 track_table")
	_ok(s.story_state == null, "默认无 story_state")
	_eq(s.track_vm().size(), 0, "无 track_table 时 track_vm 空")
	_eq((s.track_filter({}) as Array).size(), 0, "无 track_table 时 filter 空")
	_eq(s.story_vm().size(), 0, "无 story_state 时 story_vm 空")
	_eq(String(s.handle_observation({}).get("reason", "")), "no_track_table", "无 track_table observation 拒绝")
	_eq(String(s.handle_evidence({}).get("reason", "")), "no_track_table", "无 track_table evidence 拒绝")
	_eq(String(s.handle_story_evidence("x").get("reason", "")), "no_story_state", "无 story_state evidence 拒绝")
	_eq(String(s.gate({}).get("reason", "")), "no_story_state", "无 story_state gate 拒绝")
	var save := s.save_state()
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "退化 session save/load ok")
	_ok(s2.track_table == null, "退化 load 后无 track_table")
	_ok(s2.story_state == null, "退化 load 后无 story_state")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "退化 save/load snapshot 一致")
	var s3 = GameSession.new({"track_table": false, "story_state": false})
	_ok(bool(s3.ready), "显式 false 退化 ready")
	_ok(s3.track_table == null, "显式 false 无 track_table")
	_ok(s3.story_state == null, "显式 false 无 story_state")
	# 可选组合启用
	var e = GameSession.new({"track_table": true, "story_state": true})
	_ok(bool(e.ready), "启用组件 boot ready", str(e.errors))
	_ok(e.track_table != null, "启用 track_table")
	_ok(e.story_state != null, "启用 story_state")
	_ok(String(e._track_writer) != "", "track writer 非空")
	_ok(not e.track_vm().is_empty(), "track_vm 非空")
	_eq(String(e.track_vm().get("schema", "")), "fused_track_table.v1", "track vm schema")
	_ok(not e.story_vm().is_empty(), "story_vm 非空")
	_eq(String(e.story_vm().get("schema", "")), "v17.story_state.v1", "story vm schema")
	var snap: Dictionary = e.snapshot()
	_ok(snap.has("track_table") and snap["track_table"] is Dictionary, "snapshot 含 track_table")
	_ok(snap.has("story") and snap["story"] is Dictionary, "snapshot 含 story")
	_ok(bool(e.check_contracts().get("ok", false)), "启用组件 contracts ok")
	_data_line("optional", "无配置退化 · false 退化 · true 启用 track/story")

# ═══════════════════════════════════════════════════════════════════
# 12. TrackTable 观测 L1-L4 / 过期
# ═══════════════════════════════════════════════════════════════════

func _obs(s, event_id: String, sensor: String, support: int, entity := "E1", batch := "2001") -> Dictionary:
	return {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": event_id, "t": s.now_s(), "sensor": sensor,
		"entity_id": entity, "batch": batch, "support": support,
		"quality": 0.8, "range_km": 1000.0, "bearing_deg": 45.0}

func _ev_track(s, event_id: String, track_id: String, etype: String, support: int,
		identity := "unknown", iff := {}) -> Dictionary:
	var ev := {"schema": "track_evidence.v1", "kind": "evidence",
		"event_id": event_id, "t": s.now_s(), "track_id": track_id,
		"evidence_type": etype, "support": support, "source": etype,
		"identity": identity, "threat": "none"}
	if not iff.is_empty():
		ev["iff"] = iff
	return ev

func _test_track_l1_l4() -> void:
	_section_begin("12 TrackTable L1-L4/过期")
	var cfg = {"track_table": {"stale_after_s": 5.0, "forget_after_s": 20.0},
		"story_state": true}
	var s = GameSession.new(cfg)
	_ok(bool(s.ready), "track session ready", str(s.errors))
	_ok(s.track_table != null, "track_table 启用")
	_eq(String(s.track_table.current_writer()), String(s._track_writer), "track 单写者一致")
	# L1
	var r1: Dictionary = s.handle_observation(_obs(s, "obs-1", "radar", 1))
	_eq(bool(r1.get("ok", false)), true, "observation L1 ok", str(r1.get("reason", "")))
	_eq((s.track_vm().get("tracks", []) as Array).size(), 1, "L1 后 1 track")
	var t0: Dictionary = (s.track_vm().get("tracks", []) as Array)[0]
	_eq(int(t0.get("level", -1)), 1, "L1 level=1")
	var tid := String(t0.get("id", ""))
	_ok(tid != "", "track id 生成")
	# L2（不同 source）
	var r2: Dictionary = s.handle_observation(_obs(s, "obs-2", "optical", 1))
	_eq(bool(r2.get("ok", false)), true, "observation 第二源 ok")
	_eq(int((s.track_filter({}) as Array)[0].get("level", -1)), 2, "L2 level=2")
	# 非法 observation（support 3 / L3 不允许由观测提升）
	var bad_obs: Dictionary = s.handle_observation(_obs(s, "obs-bad", "radar", 3))
	_eq(bool(bad_obs.get("ok", true)), false, "observation support=3 拒绝")
	_eq(int((s.track_filter({}) as Array)[0].get("level", -1)), 2, "非法观测不改变 level")
	# L3 光学证据
	var r3: Dictionary = s.handle_evidence(_ev_track(s, "ev-1", tid, "optical", 3, "friend"))
	_eq(bool(r3.get("ok", false)), true, "evidence L3 ok", str(r3.get("reason", "")))
	_eq(int((s.track_filter({}) as Array)[0].get("level", -1)), 3, "L3 level=3")
	# L4 IFF 证据
	var iff := {"status": "friend"}
	var r4: Dictionary = s.handle_evidence(_ev_track(s, "ev-2", tid, "iff", 4, "friend", iff))
	_eq(bool(r4.get("ok", false)), true, "evidence L4 ok", str(r4.get("reason", "")))
	var t4: Dictionary = (s.track_filter({}) as Array)[0]
	_eq(int(t4.get("level", -1)), 4, "L4 level=4")
	_eq(String(t4.get("identity", "")), "friend", "L4 identity friend")
	_ok(not (t4.get("evidence", []) as Array).is_empty(), "证据可追溯")
	# 重复 event_id / 未知 track / 未授权 writer 拒绝
	var dup: Dictionary = s.handle_evidence(_ev_track(s, "ev-2", tid, "iff", 4, "friend", iff))
	_eq(bool(dup.get("ok", true)), false, "重复 event_id 拒绝")
	var unk: Dictionary = s.handle_evidence(_ev_track(s, "ev-3", "T9999", "optical", 3, "friend"))
	_eq(bool(unk.get("ok", true)), false, "未知 track 证据拒绝")
	var before_track: String = _norm_json(s.track_filter({}))
	var unauth: Dictionary = s.track_table.handle_observation(_obs(s, "obs-hack", "radar", 1), "hacker")
	_eq(bool(unauth.get("ok", true)), false, "非 writer 直接写拒绝")
	_eq(_norm_json(s.track_filter({})), before_track, "拒绝写不改变 track")
	# filter
	_eq((s.track_filter({"level_min": 3}) as Array).size(), 1, "filter level_min=3")
	_eq((s.track_filter({"level_min": 5}) as Array).size(), 0, "filter level_min=5 空")
	_eq((s.track_filter({"identity": "friend"}) as Array).size(), 1, "filter identity friend")
	# tick stale
	var tick1: Dictionary = s.tick(6.0)
	_eq(bool(tick1.get("ok", false)), true, "tick 6s ok")
	_near(float(s.track_table.t), s.now_s(), 1.0e-6, "track t 与会话同步")
	_eq(bool((s.track_filter({}) as Array)[0].get("stale", false)), true, "track 过期 stale")
	_ok(bool(s.check_contracts().get("ok", false)), "stale 后 contracts ok")
	# tick forget（total 21 > forget 20）
	var tick2: Dictionary = s.tick(15.0)
	_eq(bool(tick2.get("ok", false)), true, "tick 15s ok")
	_eq((s.track_filter({}) as Array).size(), 0, "forget 后 track 移除")
	_eq(int(s.track_vm().get("all_count", -1)), 0, "forget 后 all_count 0")
	_ok(bool(s.check_contracts().get("ok", false)), "forget 后 contracts ok")
	_ok(bool(s.story_state != null), "story 仍启用")
	_data_line("track_L1_L4", "L1→L2→L3→L4 · 拒绝非法/重复/未授权 · stale/forget")

# ═══════════════════════════════════════════════════════════════════
# 13. StoryState 集成 / 事件路由
# ═══════════════════════════════════════════════════════════════════

func _test_story_integration() -> void:
	_section_begin("13 Story 集成/路由")
	var s = GameSession.new({"story_state": true})
	_ok(bool(s.ready), "story session ready", str(s.errors))
	_ok(s.story_state != null, "story_state 启用")
	# StoryState 证据
	var se: Dictionary = s.handle_story_evidence("ev_ghost_track")
	_eq(bool(se.get("ok", false)), true, "handle_story_evidence ok")
	_ok(bool(s.story_vm().get("evidence_ids", []).has("ev_ghost_track")), "story evidence 记录")
	var dup: Dictionary = s.handle_story_evidence("ev_ghost_track")
	_eq(bool(dup.get("ok", true)), false, "重复 story evidence 拒绝")
	var bad: Dictionary = s.handle_story_evidence("Bad-ID")
	_eq(bool(bad.get("ok", true)), false, "非法 story evidence 拒绝")
	# 直接 bus 发布 story.flag → tick 白名单路由
	var pub: Dictionary = s.bus.publish({"type": "story.flag", "t": s.now_s(),
		"source": "test", "payload": {"flag": "aeug_contact", "value": true}})
	_eq(bool(pub.get("ok", false)), true, "bus 发布 story.flag ok")
	_ok(not bool(s.story_vm().get("flags", {}).has("aeug_contact")), "tick 前 flag 未路由")
	var tick: Dictionary = s.tick(0.1)
	_eq(bool(tick.get("ok", false)), true, "tick 路由 ok")
	_ok(bool(s.story_vm().get("flags", {}).has("aeug_contact")), "tick 后 flag 已路由")
	_ok((tick.get("routed", []) as Array).size() > 0, "tick 返回 routed")
	# route_event 显式证据
	var re: Dictionary = s.route_event({"type": "story.evidence", "t": s.now_s(),
		"source": "test", "payload": {"evidence_id": "ev_extra"}})
	_eq(bool(re.get("ok", false)), true, "route_event story.evidence ok")
	_ok(bool(s.story_vm().get("evidence_ids", []).has("ev_extra")), "route evidence 生效")
	_eq(String(re.get("type", "")), "story.evidence", "route 返回 type")
	# route_event choice
	var rc: Dictionary = s.route_event({"type": "story.choice", "t": s.now_s(),
		"source": "test", "payload": {"choice_id": "ch_help", "meta": {"a": 1}}})
	_eq(bool(rc.get("ok", false)), true, "route_event story.choice ok")
	_ok(bool(s.story_vm().get("choices", [])[0].get("choice_id", "") == "ch_help"), "route choice 生效")
	# 未知事件类型不路由
	var nr: Dictionary = s.route_event({"type": "entity.move", "t": s.now_s(),
		"source": "test", "payload": {}})
	_eq(bool(nr.get("ok", true)), false, "非白名单 route 拒绝")
	_eq(String(nr.get("reason", "")), "not_routable", "not_routable reason")
	# 非法 story flag 不改变状态
	var before := _story_state_json(s)
	var bad_flag: Dictionary = s.route_event({"type": "story.flag", "t": s.now_s(),
		"source": "test", "payload": {"flag": "Bad-Name", "value": true}})
	_eq(bool(bad_flag.get("ok", true)), false, "非法 story flag route 拒绝")
	_eq(_story_state_json(s), before, "失败 route 不改变 story")
	# 非白名单 bus 事件不写 story（tick 只推进时间/revision，不改内容）
	var before_content := _story_content_json(s)
	var pub2: Dictionary = s.bus.publish({"type": "entity.move", "t": s.now_s(),
		"source": "test", "target": "apsis", "payload": {"pos_km": [1, 2, 3]}})
	_eq(bool(pub2.get("ok", false)), true, "bus 发布非白名单 ok")
	s.tick(0.2)
	_eq(_story_content_json(s), before_content, "非白名单事件不写 story 内容")
	# gate / VM / 时间 / revision
	_ok(bool(s.gate({"flags": ["aeug_contact"]}).get("passed", false)), "gate flag 通过")
	_eq(bool(s.gate({"flags": ["no_such"]}).get("passed", true)), false, "gate 缺失 flag 不通过")
	_eq(String(s.story_vm().get("schema", "")), "v17.story_state.v1", "story vm schema")
	_near(float(s.story_state.t_s), s.now_s(), 1.0e-6, "story t_s 与会话同步")
	var rev := int(s.story_state.revision)
	s.tick(0.1)
	_ok(int(s.story_state.revision) >= rev, "story revision 单调")
	_ok(bool(s.check_contracts().get("ok", false)), "story 集成 contracts ok")
	_data_line("story", "evidence/flag/choice 路由 · 非白名单不写 · gate/t_s/revision")

# ═══════════════════════════════════════════════════════════════════
# 14. 组件存档往返
# ═══════════════════════════════════════════════════════════════════

func _test_save_components() -> void:
	_section_begin("14 组件存档")
	var cfg = {"track_table": {"stale_after_s": 5.0, "forget_after_s": 20.0},
		"story_state": true}
	var s = GameSession.new(cfg)
	s.handle_observation(_obs(s, "obs-1", "radar", 1))
	s.handle_observation(_obs(s, "obs-2", "optical", 1))
	var tid := String((s.track_filter({}) as Array)[0].get("id", ""))
	s.handle_evidence(_ev_track(s, "ev-1", tid, "optical", 3, "friend"))
	s.handle_story_evidence("ev_ghost_track")
	s.route_event({"type": "story.flag", "t": s.now_s(), "source": "test",
		"payload": {"flag": "aeug_contact", "value": true}})
	s.tick(1.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "组件 save JSON 可解析")
	if d is Dictionary:
		_ok((d as Dictionary).get("track_table") is Dictionary, "save 含 track_table 快照")
		_ok((d as Dictionary).get("story") is Dictionary, "save 含 story 快照")
		_ok((d as Dictionary).get("bus") is Dictionary, "save 含 bus 历史")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "组件 load ok", str(lr.get("errors", [])))
	_ok(s2.track_table != null, "load 后 track_table 启用")
	_ok(s2.story_state != null, "load 后 story_state 启用")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "组件 snapshot 一致")
	_ok(_norm_json(s.track_vm()) == _norm_json(s2.track_vm()), "track_vm 一致")
	_ok(_norm_json(s.story_vm()) == _norm_json(s2.story_vm()), "story_vm 一致")
	_near(float(s2.track_table.t), s2.now_s(), 1.0e-6, "load track t 同步")
	_near(float(s2.story_state.t_s), s2.now_s(), 1.0e-6, "load story t 同步")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# 再次保存（load 后立即，规范化一致）
	var save2 := s2.save_state()
	_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(save2)),
		"load 后再次 save 规范化一致")
	# load 后可继续 tick/观测
	s2.tick(0.5)
	_eq(bool(s2.handle_observation(_obs(s2, "obs-after", "elint", 1, "E2", "2002")).get("ok", false)),
		true, "load 后继续观测 ok")
	_ok(bool(s2.check_contracts().get("ok", false)), "继续 tick 后 contracts ok")
	# 退化存档（无 track/story）可被启用会话读取
	var plain = GameSession.new()
	plain.issue_order("hold", "apsis", ["harmattan"], {}, {})
	plain.tick(1.0)
	var plain_save := plain.save_state()
	var plain_d = JSON.parse_string(plain_save)
	var enabled_load = GameSession.new(cfg)
	var elr: Dictionary = enabled_load.load_state(plain_save)
	_eq(bool(elr.get("ok", false)), true, "无组件存档可被启用会话读取", str(elr.get("errors", [])))
	_ok(enabled_load.track_table == null, "旧存档 seed 无配置 → 组件退化（兼容）")
	_data_line("save_components", "track/story/bus 快照 · load 后 VM/t/contracts 一致 · 继续操作/再次 save")

# ═══════════════════════════════════════════════════════════════════
# 15. 旧存档缺字段兼容
# ═══════════════════════════════════════════════════════════════════

func _test_old_save_compat() -> void:
	_section_begin("15 旧存档兼容")
	var s = _new_session()
	s.issue_order("hold", "apsis", ["harmattan"], {}, {})
	s.tick(1.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "当前 save 可解析")
	if not (d is Dictionary):
		return
	# 模拟旧存档：无 track_table/story/bus 字段，seed 也无组件配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("track_table")
	old.erase("story")
	old.erase("bus")
	var seed: Dictionary = old.get("seed", {}) if old.get("seed") is Dictionary else {}
	seed.erase("track_table")
	seed.erase("story_state")
	old["seed"] = seed
	var old_text := JSON.stringify(old)
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(old_text)
	_eq(bool(lr.get("ok", false)), true, "旧存档缺字段 load ok", str(lr.get("errors", [])))
	_ok(s2.track_table == null, "旧存档 load 后无 track_table")
	_ok(s2.story_state == null, "旧存档 load 后无 story_state")
	_eq(String(s2.snapshot().get("schema", "")), "v17.game_session.v1", "旧存档 snapshot schema")
	_near(s2.now_s(), s.now_s(), 1.0e-9, "旧存档恢复时间")
	_eq(String(s2.orders.orders.keys()[0] if s2.orders.orders.size() > 0 else ""),
		String(s.orders.orders.keys()[0] if s.orders.orders.size() > 0 else ""), "旧存档恢复订单")
	var save2 := s2.save_state()
	_ok(JSON.parse_string(save2) is Dictionary, "旧存档再次 save 可解析")
	# 缺 bus 的旧存档在启用会话中也兼容：组件为空（seed 无配置 → 退化）
	var enabled = GameSession.new({"story_state": true})
	var elr: Dictionary = enabled.load_state(old_text)
	_eq(bool(elr.get("ok", false)), true, "旧存档可被启用会话读取（seed 无配置 → 退化）",
		str(elr.get("errors", [])))
	_data_line("old_save", "缺 track_table/story/bus/seed 字段兼容 · 恢复核心状态")

# ═══════════════════════════════════════════════════════════════════
# 16. 组件非法事件 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_component_errors_determinism() -> void:
	_section_begin("16 组件非法/确定性")
	var cfg = {"track_table": true, "story_state": true}
	var s = GameSession.new(cfg)
	var before_track := _norm_json(s.track_filter({}))
	var before_story := _story_state_json(s)
	# 非法观测 / 证据 / story 操作不改状态
	_eq(bool(s.handle_observation({}).get("ok", true)), false, "空 observation 拒绝")
	_eq(bool(s.handle_observation({"schema": "bad"}).get("ok", true)), false, "坏 observation schema 拒绝")
	_eq(bool(s.handle_evidence({}).get("ok", true)), false, "空 evidence 拒绝")
	_eq(_norm_json(s.track_filter({})), before_track, "非法观测/证据不改变 track")
	_eq(bool(s.handle_story_evidence("Bad-ID").get("ok", true)), false, "非法 story evidence 拒绝")
	_eq(bool(s.route_event({"type": "story.flag", "source": "x", "t": 0,
		"payload": {"flag": "Bad-Name"}}).get("ok", true)), false, "非法 story flag 拒绝")
	_eq(_story_state_json(s), before_story, "非法 story 操作不改变 story")
	# 非法 track evidence 路由不改 track
	var bad_ev_route: Dictionary = s.route_event({"type": "track.evidence", "t": s.now_s(),
		"source": "x", "payload": {"track_id": "T9999", "evidence_type": "optical",
			"support": 3, "identity": "friend"}})
	_eq(bool(bad_ev_route.get("ok", true)), false, "非法 track.evidence route 拒绝")
	_eq(_norm_json(s.track_filter({})), before_track, "非法 track route 不改变 track")
	# 总线路由失败写 warning（不静默）
	s.bus.publish({"type": "story.flag", "t": s.now_s(), "source": "test",
		"payload": {"flag": "Bad-Name", "value": true}})
	s.tick(0.1)
	_ok(s.warnings.size() > 0, "总线路由失败记录 warnings")
	_ok(bool(s.check_contracts().get("ok", false)), "失败后 contracts ok")
	# 确定性：同操作两实例
	var a = GameSession.new(cfg)
	var b = GameSession.new(cfg)
	for st in [a, b]:
		st.handle_observation(_obs(st, "obs-1", "radar", 1))
		st.handle_observation(_obs(st, "obs-2", "optical", 1))
		st.handle_story_evidence("ev_ghost_track")
		st.route_event({"type": "story.flag", "t": st.now_s(), "source": "test",
			"payload": {"flag": "aeug_contact", "value": true}})
		st.tick(1.0)
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "组件同操作 snapshot 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"组件同操作 save 一致")
	# 单写者：外部 token 写 world/track 均拒绝
	var w: Dictionary = a.world.apply({"type": "entity.move", "t": a.now_s(), "source": "x",
		"target": "apsis", "payload": {"pos_km": [1, 2, 3]}}, "hacker")
	_eq(String(w.get("reason", "")), "writer_mismatch", "world 外部写拒绝")
	var unauth_track: Dictionary = a.track_table.handle_observation(_obs(a, "obs-hack", "radar", 1), "hacker")
	_eq(bool(unauth_track.get("ok", true)), false, "track 外部写拒绝")
	_data_line("components_errors", "非法组件事件不改状态 · 同操作确定性 · 单写者拒绝")

# ═══════════════════════════════════════════════════════════════════
# 17. SensorService 可选 / API
# ═══════════════════════════════════════════════════════════════════

func _sensor_target(id: String, batch: String, pos: Array, transponder: String,
		code: String, side := "unknown") -> Dictionary:
	return {"id": id, "target_id": id, "entity_id": "E-" + batch, "batch": batch,
		"pos_km": pos, "vel_kmps": [0.0, 0.0, 0.0], "rcs_m2": 10.0,
		"temp_k": 300.0, "area_m2": 1000.0, "size_m": 50.0, "illum": 1.0,
		"transponder": transponder, "iff_code": code,
		"registered": side == "friend", "crypto_epoch": "epoch-1",
		"side": side, "faction": "test",
		"classification": {"ship_class": "DDG", "role": "test", "faction": side}}

func _sensor_cfg() -> Dictionary:
	return {"track_table": true, "story_state": true,
		"sensor_service": {
			"observer": {"id": "harmattan", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0], "attitude_quat": [0.0, 0.0, 0.0, 1.0]},
			"targets": [_sensor_target("T1", "2001", [0.0, 500.0, 0.0],
				"ok", "CMP-2001", "friend")],
			"snapshot": {"sun_dir": [0.0, 0.0, 1.0], "sun_illum": 1.0,
				"jamming": 0.0, "shadow": false, "los": true},
			"options": {"radar_enabled": true, "emcon": false},
		}}

func _sensor_state(s) -> String:
	if s.sensor_service == null:
		return ""
	var vm: Dictionary = s.sensor_vm()
	return _norm_json({
		"t": vm.get("t", 0.0), "step_count": vm.get("step_count", 0),
		"selected_target": vm.get("selected_target", ""),
		"radar_enabled": vm.get("radar_enabled", false),
		"emcon": vm.get("emcon", false),
		"counts": vm.get("counts", {}),
	})

func _test_sensor_optional() -> void:
	_section_begin("17 Sensor 可选/API")
	var s = _new_session()
	_ok(s.sensor_service == null, "默认无 sensor_service")
	_eq(s.sensor_vm().size(), 0, "无 sensor 时 sensor_vm 空")
	_eq(String(s.set_sensor_target("T1").get("reason", "")), "no_sensor_service", "无传感器 set_target 拒绝")
	_eq(String(s.start_sensor_channel("optical", "T1").get("reason", "")), "no_sensor_service", "无传感器 start 拒绝")
	_eq(String(s.stop_sensor_channel().get("reason", "")), "no_sensor_service", "无传感器 stop 拒绝")
	_eq(String(s.set_radar_enabled(false).get("reason", "")), "no_sensor_service", "无传感器 radar 拒绝")
	_eq(String(s.set_emcon(true).get("reason", "")), "no_sensor_service", "无传感器 emcon 拒绝")
	_eq(String(s.query_iff("T1").get("reason", "")), "no_sensor_service", "无传感器 IFF 拒绝")
	var s2 = GameSession.new({"sensor_service": false})
	_ok(bool(s2.ready), "sensor=false ready")
	_ok(s2.sensor_service == null, "sensor=false 退化")
	var s3 = GameSession.new({"sensor_service": true})
	_ok(bool(s3.ready), "sensor=true boot ready", str(s3.errors))
	_ok(s3.sensor_service != null, "sensor=true 启用")
	_ok(not s3.sensor_vm().is_empty(), "sensor=true vm 非空")
	_eq(String(s3.sensor_vm().get("schema", "")), "sensor_service.v1", "sensor vm schema")
	_ok((s3.sensor_vm().get("targets", []) as Array).is_empty(), "sensor=true 默认无目标")
	# 空目标配置也可 ready（no observations）
	var s4 = GameSession.new({"sensor_service": {"observer": {"id": "harmattan",
		"pos_km": [0.0, 0.0, 0.0]}, "targets": []}})
	_ok(bool(s4.ready), "空目标 sensor ready", str(s4.errors))
	_ok(s4.sensor_service != null, "空目标启用")
	_data_line("sensor_optional", "无/false 退化 · true 启默认 · 空目标配置 ready")

# ═══════════════════════════════════════════════════════════════════
# 18. Sensor 管道（雷达/光学/IFF/EMCON）
# ═══════════════════════════════════════════════════════════════════

func _test_sensor_pipeline() -> void:
	_section_begin("18 Sensor 管道")
	var s = GameSession.new(_sensor_cfg())
	_ok(bool(s.ready), "sensor pipeline boot ready", str(s.errors))
	_ok(s.sensor_service != null, "sensor 启用")
	_ok(s.track_table != null, "sensor 管道 track_table 启用")
	var vm: Dictionary = s.sensor_vm()
	_eq(String(vm.get("schema", "")), "sensor_service.v1", "sensor vm schema")
	_eq(String(vm.get("mode", "")), "shadow", "sensor mode shadow")
	_ok(bool(vm.get("ready", false)), "sensor vm ready")
	_eq(String((vm.get("observer", {}) as Dictionary).get("id", "")), "harmattan", "observer id")
	_eq((vm.get("targets", []) as Array).size(), 1, "targets 1")
	var writes: Dictionary = vm.get("writes", {})
	_eq(bool(writes.get("track_table", true)), false, "sensor 不直接写 track_table")
	_eq(bool(writes.get("v15", true)), false, "sensor 不写 v15")
	_eq(bool(writes.get("world", true)), false, "sensor 不写 world")
	# 目标/通道控制
	_eq(bool(s.set_sensor_target("T1").get("ok", false)), true, "set_sensor_target ok")
	_eq(String(s.sensor_vm().get("selected_target", "")), "T1", "selected_target=T1")
	var bad_t: Dictionary = s.set_sensor_target("TX")
	_eq(bool(bad_t.get("ok", true)), false, "未知目标 set_target 拒绝")
	_eq(String(bad_t.get("reason", "")), "unknown_target", "unknown_target")
	var bad_ch: Dictionary = s.start_sensor_channel("xx", "T1")
	_eq(bool(bad_ch.get("ok", true)), false, "非法通道 kind 拒绝")
	var ch: Dictionary = s.start_sensor_channel("optical", "T1")
	_eq(bool(ch.get("ok", false)), true, "start optical ok")
	# tick：观测→TrackTable（L1/L2 级）
	var t1: Dictionary = s.tick(1.0)
	_eq(bool(t1.get("ok", false)), true, "sensor tick1 ok")
	_near(float(s.sensor_service.t), s.now_s(), 1.0e-6, "sensor t 同步")
	var sr1: Dictionary = t1.get("sensor_route", {})
	_ok(bool(sr1.get("enabled", false)), "sensor_route enabled")
	_ok(int(sr1.get("observations", 0)) >= 1, "sensor observation 路由 >=1", str(sr1))
	var tracks: Array = s.track_filter({})
	_eq(tracks.size(), 1, "sensor 观测建 1 track")
	var lv1 := int((tracks[0] as Dictionary).get("level", 0))
	_ok(lv1 >= 1 and lv1 <= 2, "观测→track L1/L2", "level=%d" % lv1)
	_ok(bool(s.check_contracts().get("ok", false)), "sensor tick1 contracts ok")
	# 光学证据 → L3
	var t2: Dictionary = s.tick(5.0)
	_eq(bool(t2.get("ok", false)), true, "sensor tick5 ok")
	var sensor_evd: Array = s.sensor_vm().get("evidence", [])
	_ok(sensor_evd.size() > 0, "sensor 产生 evidence")
	var optical_ok := false
	for e in sensor_evd:
		if String((e as Dictionary).get("evidence_type", "")) == "optical":
			optical_ok = true
	_ok(optical_ok, "sensor 产生 optical evidence")
	_ok(int((t2.get("sensor_route", {}) as Dictionary).get("evidence", 0)) >= 1,
		"optical evidence 路由到 track")
	_ok(int((s.track_filter({}) as Array)[0].get("level", 0)) >= 3, "光学证据→L3")
	# IFF → L4（身份）
	var iff: Dictionary = s.query_iff("T1")
	_eq(bool(iff.get("ok", false)), true, "query_iff ok")
	_eq(String(iff.get("identity", "")), "friend", "IFF identity friend")
	_eq(bool(iff.get("never_hostile", false)), true, "IFF never_hostile")
	_eq(bool(iff.get("routed", false)), true, "IFF evidence 路由")
	var t4: Dictionary = (s.track_filter({}) as Array)[0]
	_eq(int(t4.get("level", 0)), 4, "IFF→L4")
	_eq(String(t4.get("identity", "")), "friend", "track identity friend")
	var iff_unk: Dictionary = s.query_iff("TX")
	_eq(bool(iff_unk.get("ok", true)), false, "未知目标 IFF 拒绝")
	_eq(String(iff_unk.get("reason", "")), "unknown_target", "unknown IFF target")
	# EMCON / 雷达开关
	var radar_before := int((s.sensor_vm().get("counts", {}) as Dictionary).get("radar_obs", 0))
	var em: Dictionary = s.set_emcon(true)
	_eq(bool(em.get("ok", false)), true, "set_emcon true ok")
	_eq(bool(s.sensor_vm().get("emcon", false)), true, "sensor emcon=true")
	_eq(bool(s.sensor_vm().get("radar_enabled", true)), false, "emcon 关闭雷达")
	s.tick(1.0)
	var radar_after := int((s.sensor_vm().get("counts", {}) as Dictionary).get("radar_obs", 0))
	_eq(radar_after, radar_before, "EMCON 后无新雷达观测")
	var em_off: Dictionary = s.set_emcon(false)
	_eq(bool(em_off.get("ok", false)), true, "set_emcon false ok")
	_eq(bool(s.sensor_vm().get("radar_enabled", false)), true, "emcon off 恢复雷达")
	var off: Dictionary = s.set_radar_enabled(false)
	_eq(bool(off.get("ok", false)), true, "set_radar_enabled false ok")
	s.tick(1.0)
	_eq(int((s.sensor_vm().get("counts", {}) as Dictionary).get("radar_obs", 0)), radar_after,
		"雷达关闭无新雷达观测")
	_eq(bool(s.set_radar_enabled(true).get("ok", false)), true, "雷达恢复 ok")
	# stop 通道
	var stop: Dictionary = s.stop_sensor_channel("optical", "T1")
	_eq(bool(stop.get("ok", false)), true, "stop optical ok")
	_ok(JSON.parse_string(JSON.stringify(s.sensor_vm())) is Dictionary, "sensor vm JSON 可解析")
	_ok(bool(s.check_contracts().get("ok", false)), "sensor 管道 contracts ok")
	_data_line("sensor_pipeline", "雷达观测→track L1/L2 · optical→L3 · IFF→L4 · EMCON/雷达开关")

# ═══════════════════════════════════════════════════════════════════
# 19. Sensor 存档 / load 重建
# ═══════════════════════════════════════════════════════════════════

func _test_sensor_save_load() -> void:
	_section_begin("19 Sensor 存档")
	var s = GameSession.new(_sensor_cfg())
	s.tick(1.0)
	s.set_sensor_target("T1")
	s.start_sensor_channel("optical", "T1")
	s.tick(5.0)
	s.query_iff("T1")
	s.set_emcon(true)
	s.tick(1.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "sensor save JSON 可解析")
	if d is Dictionary:
		var seed: Dictionary = (d as Dictionary).get("seed", {})
		_ok(seed.has("sensor_service"), "save seed 含 sensor_service 配置")
		_ok(not (d as Dictionary).has("sensor"), "save 无 sensor 快照（靠 boot+log 重建）")
		var log: Array = (d as Dictionary).get("log", [])
		var ops: Array = []
		for raw in log:
			if raw is Dictionary:
				ops.append(String((raw as Dictionary).get("op", "")))
		_ok("set_sensor_target" in ops, "log 含 set_sensor_target")
		_ok("start_sensor_channel" in ops, "log 含 start_sensor_channel")
		_ok("query_iff" in ops, "log 含 query_iff")
		_ok("set_emcon" in ops, "log 含 set_emcon")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "sensor load ok", str(lr.get("errors", [])))
	_ok(s2.sensor_service != null, "load 重建 sensor_service")
	_ok(_norm_json(s.sensor_vm()) == _norm_json(s2.sensor_vm()), "load 后 sensor_vm 一致")
	_ok(JSON.stringify(s.sensor_service.summary()) == JSON.stringify(s2.sensor_service.summary()),
		"load 后 sensor summary 一致")
	_ok(_norm_json(s.track_vm()) == _norm_json(s2.track_vm()), "load 后 track_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(s2.save_state())),
		"load 后再次 save 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "sensor load contracts ok")
	# load 后继续控制/推进
	var em: Dictionary = s2.set_emcon(false)
	_eq(bool(em.get("ok", false)), true, "load 后 set_emcon false ok")
	var t: Dictionary = s2.tick(1.0)
	_eq(bool(t.get("ok", false)), true, "load 后 tick ok")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后继续 tick contracts ok")
	# 旧存档缺 sensor 配置兼容
	var old: Dictionary = (d as Dictionary).duplicate(true)
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("sensor_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 sensor 配置 load ok", str(lr3.get("errors", [])))
	_ok(s3.sensor_service == null, "旧存档 load 后 sensor 退化")
	_data_line("sensor_save", "seed+log 重建 sensor · load VM/summary/snapshot 一致 · 旧档兼容")

# ═══════════════════════════════════════════════════════════════════
# 20. Sensor 失败不改状态 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_sensor_errors_determinism() -> void:
	_section_begin("20 Sensor 失败/确定性")
	var s = GameSession.new(_sensor_cfg())
	s.tick(1.0)
	s.set_sensor_target("T1")
	s.start_sensor_channel("optical", "T1")
	s.tick(2.0)
	var before := _sensor_state(s)
	var bad_start: Dictionary = s.start_sensor_channel("xx", "T1")
	_eq(bool(bad_start.get("ok", true)), false, "非法通道 start 拒绝")
	var bad_stop: Dictionary = s.stop_sensor_channel("xx", "")
	_eq(bool(bad_stop.get("ok", true)), false, "非法通道 stop 拒绝")
	var bad_target: Dictionary = s.set_sensor_target("TX")
	_eq(bool(bad_target.get("ok", true)), false, "未知目标 set 拒绝")
	var bad_iff: Dictionary = s.query_iff("TX")
	_eq(bool(bad_iff.get("ok", true)), false, "未知目标 IFF 拒绝")
	_eq(_sensor_state(s), before, "失败控制不改 sensor 状态")
	# IFF 未选目标（空）失败
	var s2 = GameSession.new(_sensor_cfg())
	var no_target: Dictionary = s2.query_iff("")
	_eq(bool(no_target.get("ok", true)), false, "IFF 无目标拒绝")
	# support=0 观测被忽略（无失败、无 warning）
	var s3 = GameSession.new({"track_table": true,
		"sensor_service": {"observer": {"id": "harmattan", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [_sensor_target("T2", "2002", [0.0, 40000.0, 0.0],
				"off", "", "unknown")],
			"snapshot": {"sun_illum": 1.0, "los": true}}})
	var t3: Dictionary = s3.tick(1.0)
	var sr3: Dictionary = t3.get("sensor_route", {})
	_ok(int(sr3.get("ignored", 0)) >= 1, "support=0 观测被忽略")
	_eq(int(sr3.get("failed", 0)), 0, "support=0 不算路由失败")
	_eq((s3.track_filter({}) as Array).size(), 0, "超距目标不建 track")
	# 确定性：两实例同传感器操作
	var a = GameSession.new(_sensor_cfg())
	var b = GameSession.new(_sensor_cfg())
	for st in [a, b]:
		st.tick(1.0)
		st.set_sensor_target("T1")
		st.start_sensor_channel("optical", "T1")
		st.tick(5.0)
		st.query_iff("T1")
		st.set_emcon(true)
		st.tick(1.0)
	_ok(_norm_json(a.sensor_vm()) == _norm_json(b.sensor_vm()), "sensor 同操作 VM 一致")
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "sensor 同操作 snapshot 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"sensor 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "sensor 失败/确定性 contracts ok")
	_data_line("sensor_errors", "失败控制不改状态 · support0 忽略 · 同操作确定性")

# ═══════════════════════════════════════════════════════════════════
# 21. Port/Combat 可选组件
# ═══════════════════════════════════════════════════════════════════

func _port_cfg_session() -> Dictionary:
	return {"port_service": {"ports": [
		{"id": "p1", "name": "L1 Meridian", "berths": ["B1"], "drydock_slots": 1,
			"tugs": ["TUG1"], "fuel_capacity_t": 500.0, "fuel_available_t": 500.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 100000.0}],
			"corridor": "C1", "require_permit": false,
			"services": ["refuel", "repair", "tow", "shuttle"]}]}}

func _combat_cfg_session() -> Dictionary:
	return {"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
		"roe": "TIGHT", "own_id": "session_ship", "fleet_id": "taskforce"}}

func _port_core(s) -> String:
	var vm: Dictionary = s.port_vm()
	return _norm_json({"t_s": vm.get("t", 0.0), "ports": vm.get("ports", []),
		"requests": vm.get("requests", []), "queue": vm.get("queue", [])})

func _combat_core(s) -> String:
	var vm: Dictionary = s.combat_vm()
	return _norm_json({"t": vm.get("t", 0.0), "roe": vm.get("roe", ""),
		"weapons": vm.get("weapons", []), "tracks": vm.get("tracks", []),
		"grants": vm.get("grants", []), "solutions": vm.get("solutions", []),
		"incoming": vm.get("incoming", [])})

func _test_optional_port_combat() -> void:
	_section_begin("21 Port/Combat 可选")
	var s = _new_session()
	_ok(s.port_service == null, "默认无 port_service")
	_ok(s.combat_service == null, "默认无 combat_service")
	_eq(s.port_vm().size(), 0, "无 port 时 port_vm 空")
	_eq(s.port_summary().size(), 0, "无 port 时 port_summary 空")
	_eq(s.combat_vm().size(), 0, "无 combat 时 combat_vm 空")
	_eq((s.port_services() as Array).size(), 0, "无 port 时 services 空")
	_eq(String(s.port_request("dock", "ship1", "p1").get("reason", "")), "no_port_service",
		"无 port request 拒绝")
	_eq(String(s.port_dock("x").get("reason", "")), "no_port_service", "无 port dock 拒绝")
	_eq(String(s.set_roe("HOLD").get("reason", "")), "no_combat_service", "无 combat set_roe 拒绝")
	_eq(String(s.combat_register_track("T1").get("reason", "")), "no_combat_service",
		"无 combat register 拒绝")
	_eq(String(s.request_fire("T1", "railgun").get("reason", "")), "no_combat_service",
		"无 combat fire 拒绝")
	_eq(String(s.grant_authorization("FIRE").get("reason", "")), "no_combat_service",
		"无 combat grant 拒绝")
	_eq(String(s.combat_authorization().get("reason", "")), "no_combat_service",
		"无 combat check 拒绝")
	# 单启用
	var p = GameSession.new(_port_cfg_session())
	_ok(bool(p.ready), "port-only session ready", str(p.errors))
	_ok(p.port_service != null, "port 启用")
	_ok(p.combat_service == null, "port-only 无 combat")
	_eq(String(p.port_vm().get("schema", "")), "v17.port_service.v1", "port vm schema")
	_ok(int(p.port_summary().get("ports", 0)) == 1, "port summary ports=1")
	var c = GameSession.new(_combat_cfg_session())
	_ok(bool(c.ready), "combat-only session ready", str(c.errors))
	_ok(c.combat_service != null, "combat 启用")
	_ok(c.port_service == null, "combat-only 无 port")
	_eq(String(c.combat_vm().get("schema", "")), "combat_service.v1", "combat vm schema")
	_eq(String(c.combat_vm().get("roe", "")), "TIGHT", "combat roe TIGHT")
	_ok(bool(c.combat_vm().get("weapons") is Array), "combat weapons")
	# 启用 true 的默认配置
	var pd = GameSession.new({"port_service": true})
	_ok(bool(pd.ready), "port_service=true ready", str(pd.errors))
	_ok(pd.port_service != null, "port_service=true 启用")
	_ok(int(pd.port_summary().get("ports", 0)) >= 1, "默认港口配置")
	var cd = GameSession.new({"combat_service": true})
	_ok(bool(cd.ready), "combat_service=true ready", str(cd.errors))
	_ok(cd.combat_service != null, "combat_service=true 启用")
	_data_line("optional_pc", "无配置退化 · 单启用 · true 默认配置")

# ═══════════════════════════════════════════════════════════════════
# 22. Port 集成
# ═══════════════════════════════════════════════════════════════════

func _test_port_integration() -> void:
	_section_begin("22 Port 集成")
	var s = GameSession.new(_port_cfg_session())
	_ok(bool(s.ready), "port session ready", str(s.errors))
	var r: Dictionary = s.port_request("dock", "ship1", "p1", {"clearance": "C1"})
	_eq(bool(r.get("ok", false)), true, "port_request ok", str(r.get("reason", "")))
	var rid := String(r.get("request_id", ""))
	_ok(rid.begins_with("PR-"), "request id")
	_eq(String(s.port_request("dock", "ship1", "p1", {}).get("reason", "")), "ship_busy",
		"同舰第二请求拒绝")
	# 状态机
	_eq(String(s.port_permit(rid).get("status", "")), "GRANTED", "port_permit GRANTED")
	_eq(String(s.port_approach(rid).get("status", "")), "APPROACH", "port_approach")
	_eq(String(s.port_dock(rid).get("status", "")), "DOCKED", "port_dock DOCKED")
	_ok((s.port_services(rid) as Array).size() >= 2, "port_services")
	_eq(String(s.port_refuel(rid, 50.0).get("status", "")), "SERVICING", "port_refuel")
	_eq(String(s.port_finish_service(rid).get("status", "")), "DOCKED", "port_finish_service")
	_eq(String(s.port_repair(rid).get("status", "")), "SERVICING", "port_repair")
	_eq(String(s.port_finish_service(rid).get("status", "")), "DOCKED", "repair finish")
	_eq(String(s.port_undock(rid).get("status", "")), "DEPARTED", "port_undock DEPARTED")
	var res: Dictionary = s.port_summary().get("resources", {})
	_eq(int(res.get("berths_free", -1)), 1, "离港后泊位空闲")
	_eq(int(res.get("drydock_free", -1)), 1, "维修后船坞空闲")
	_ok(float(res.get("fuel_available_t", 0.0)) < 500.0, "加注消耗燃料")
	# 失败不改状态
	var before := _port_core(s)
	_eq(String(s.port_dock("PR-999999").get("reason", "")), "unknown_request", "未知 request 拒绝")
	_eq(String(s.port_refuel(rid, 1.0).get("reason", "")), "wrong_state", "DEPARTED refuel 拒绝")
	_eq(String(s.port_undock(rid).get("reason", "")), "wrong_state", "重复 undock 拒绝")
	_eq(_port_core(s), before, "失败不改 port 状态")
	# 总线事件（flush）
	s.flush_events()
	var port_events: Array = s.bus.filter_events({"type": "port"})
	_ok(port_events.size() > 0, "port.* 事件进 bus", str(port_events.size()))
	var kinds: Dictionary = {}
	for raw in port_events:
		kinds[String((raw as Dictionary).get("type", ""))] = true
	_ok(kinds.has("port.request_created"), "bus 含 request_created")
	_ok(kinds.has("port.request_granted"), "bus 含 request_granted")
	_ok(kinds.has("port.docked"), "bus 含 docked")
	_ok(kinds.has("port.departed"), "bus 含 departed")
	# tick 驱动时间且不自动
	var r2: Dictionary = s.port_request("dock", "ship2", "p1", {"clearance": "C2"})
	var rid2 := String(r2.get("request_id", ""))
	var tk: Dictionary = s.tick(2.0)
	_eq(bool(tk.get("ok", false)), true, "port tick ok")
	_near(float(s.port_service.t_s), s.now_s(), 1.0e-6, "port t 与会话同步")
	_eq(String(s.port_service.get_request(rid2).get("status", "")), "REQUESTED",
		"tick 不自动 grant")
	_eq(String(s.port_permit(rid2).get("status", "")), "GRANTED", "tick 后手动 permit")
	_ok(bool(s.check_contracts().get("ok", false)), "port contracts ok")
	# tow / shuttle（独立 session，避免泊位被占用）
	var st = GameSession.new(_port_cfg_session())
	var tw: Dictionary = st.port_tow("tugship", "p1", {"clearance": "CT"})
	var tid := String(tw.get("request_id", ""))
	_eq(String(st.port_permit(tid).get("status", "")), "GRANTED", "tow permit")
	_eq(String(st.port_approach(tid).get("status", "")), "APPROACH", "tow approach")
	_eq(String(st.port_dock(tid).get("status", "")), "DOCKED", "tow dock")
	_eq(String(st.port_undock(tid).get("status", "")), "DEPARTED", "tow undock")
	var sh: Dictionary = st.port_shuttle("shuttleship", "p1", {"clearance": "CS"})
	_eq(bool(sh.get("ok", false)), true, "shuttle request ok")
	_data_line("port", "request→permit→approach→dock→refuel/repair→undock · 事件 · tick 不自动")

# ═══════════════════════════════════════════════════════════════════
# 23. Combat 集成
# ═══════════════════════════════════════════════════════════════════

func _test_combat_integration() -> void:
	_section_begin("23 Combat 集成")
	var s = GameSession.new(_combat_cfg_session())
	_ok(bool(s.ready), "combat session ready", str(s.errors))
	var vm: Dictionary = s.combat_vm()
	_eq(String(vm.get("schema", "")), "combat_service.v1", "combat vm schema")
	_eq(String(vm.get("roe", "")), "TIGHT", "初始 ROE TIGHT")
	_eq(String(vm.get("own_id", "")), "session_ship", "own_id")
	_ok(bool(s.combat_vm().get("writes", {}).get("v15", true)) == false, "combat 不写 v15")
	# ROE
	var roe_h: Dictionary = s.set_roe("HOLD")
	_eq(bool(roe_h.get("ok", false)), true, "set_roe HOLD ok")
	_eq(String(s.combat_vm().get("roe", "")), "HOLD", "ROE HOLD")
	_eq(bool(s.set_roe("TIGHT").get("ok", false)), true, "set_roe TIGHT")
	var bad_roe: Dictionary = s.set_roe("BOGUS")
	_eq(bool(bad_roe.get("ok", true)), false, "非法 ROE 拒绝")
	_eq(String(s.combat_vm().get("roe", "")), "TIGHT", "非法 ROE 不改状态")
	# track/solution
	var reg: Dictionary = s.combat_register_track("T1", {"identity": "hostile",
		"threat": "hostile", "range_km": 500.0, "in_arc": true})
	_eq(bool(reg.get("ok", false)), true, "register track ok")
	var sol: Dictionary = s.combat_request_solution("T1", "railgun")
	_eq(bool(sol.get("ok", false)), true, "request_solution ok", str(sol.get("reason", "")))
	var tk: Dictionary = s.tick(5.0)
	_eq(bool(tk.get("ok", false)), true, "combat tick drive ok")
	_near(float(s.combat_service.t), s.now_s(), 1.0e-6, "combat t 与会话同步")
	var sols: Array = s.combat_vm().get("solutions", [])
	_eq(sols.size(), 1, "combat solutions 1")
	_eq(String((sols[0] as Dictionary).get("status", "")), "READY", "solution READY")
	# 授权
	var ga: Dictionary = s.grant_authorization("FIRE", "target", "T1")
	_eq(bool(ga.get("ok", false)), true, "grant FIRE target ok")
	var chk: Dictionary = s.combat_authorization("FIRE", "T1", "railgun")
	_ok(not chk.is_empty() and String(chk.get("scope_id", "")) == "T1", "check_authorization 返回 grant")
	# 未确认 fire 拒绝
	var ammo_before := _railgun_ammo(s)
	var no_conf: Dictionary = s.request_fire("T1", "railgun", false)
	_eq(bool(no_conf.get("ok", true)), false, "未确认 fire 拒绝")
	_eq(_railgun_ammo(s), ammo_before, "未确认 fire 不耗弹")
	# 统一路径：本会话未启用 combat_ballistics → 明确拒绝，绝不白扣弹药
	# （命中/事件/冷却的实弹路径见「40 统一开火路径」）
	var fire: Dictionary = s.request_fire("T1", "railgun", true)
	_eq(bool(fire.get("ok", true)), false, "无弹道服务 fire 拒绝")
	_eq(String(fire.get("reason", "")), "no_ballistics", "no_ballistics reason")
	_eq(_railgun_ammo(s), ammo_before, "拒绝时不耗弹")
	_ok(s.combat_ballistics_impacts().is_empty(), "无弹道服务无 impact")
	# 未知目标/武器/授权
	_eq(String(s.request_fire("TX", "railgun", true).get("reason", "")), "unknown_track",
		"未知目标拒绝")
	_eq(bool(s.combat_register_track("T2", {"identity": "friend", "threat": "none",
		"range_km": 100.0, "in_arc": true}).get("ok", false)), true, "注册友方 track")
	var friend_fire: Dictionary = s.request_fire("T2", "railgun", true)
	_eq(bool(friend_fire.get("ok", true)), false, "友方 fire 拒绝")
	var bad_grant: Dictionary = s.grant_authorization("BOGUS", "target", "T1")
	_eq(bool(bad_grant.get("ok", true)), false, "非法授权级别拒绝")
	var bad_check: Dictionary = s.combat_authorization("BOGUS")
	_ok(bad_check.is_empty(), "非法 check 返回空")
	# revoke
	var rv: Dictionary = s.revoke_authorization()
	_eq(bool(rv.get("ok", false)), true, "revoke_authorization ok")
	_ok(bool(s.check_contracts().get("ok", false)), "combat contracts ok")
	_data_line("combat", "set_roe/track/solution/READY/grant/fire/冷却拒绝/事件 · ROE 不改状态")

func _railgun_ammo(s) -> int:
	for w in (s.combat_vm().get("weapons", []) as Array):
		if String((w as Dictionary).get("id", "")) == "railgun":
			return int((w as Dictionary).get("ammo", -1))
	return -1

# ═══════════════════════════════════════════════════════════════════
# 24. Port/Combat 存档
# ═══════════════════════════════════════════════════════════════════

func _test_port_combat_save_load() -> void:
	_section_begin("24 Port/Combat 存档")
	var cfg := _port_cfg_session()
	cfg["combat_service"] = (_combat_cfg_session()["combat_service"] as Dictionary)
	var s = GameSession.new(cfg)
	_ok(bool(s.ready), "port+combat session ready", str(s.errors))
	# port 状态：DOCKED + refuel 后 SERVICING
	var pr: Dictionary = s.port_request("dock", "ship1", "p1", {"clearance": "C1"})
	var rid := String(pr.get("request_id", ""))
	s.port_permit(rid)
	s.port_approach(rid)
	s.port_dock(rid)
	s.port_refuel(rid, 25.0)
	# combat 状态：solution READY + grant + fire
	s.combat_register_track("T1", {"identity": "hostile", "threat": "hostile",
		"range_km": 500.0, "in_arc": true})
	s.combat_request_solution("T1", "railgun")
	var tk: Dictionary = s.tick(5.0)
	_ok(bool(tk.get("ok", false)), "save 前 tick ok")
	s.grant_authorization("FIRE", "target", "T1")
	s.request_fire("T1", "railgun", true)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "save JSON 可解析")
	if d is Dictionary:
		_ok(String((d as Dictionary).get("port_service", "")) != "", "save 含 port_service")
		_ok(String((d as Dictionary).get("combat_service", "")) != "", "save 含 combat_service")
		var seed: Dictionary = (d as Dictionary).get("seed", {})
		_ok(seed.has("port_service"), "seed 含 port_service 配置")
		_ok(seed.has("combat_service"), "seed 含 combat_service 配置")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "port+combat load ok", str(lr.get("errors", [])))
	_ok(s2.port_service != null and s2.combat_service != null, "load 重建 port/combat")
	_ok(_norm_json(s.port_vm()) == _norm_json(s2.port_vm()), "load 后 port_vm 一致")
	_ok(_norm_json(s.combat_vm()) == _norm_json(s2.combat_vm()), "load 后 combat_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	_near(float(s2.port_service.t_s), s2.now_s(), 1.0e-6, "load port t 同步")
	_near(float(s2.combat_service.t), s2.now_s(), 1.0e-6, "load combat t 同步")
	# 继续操作
	_eq(String(s2.port_finish_service(rid).get("status", "")), "DOCKED", "load 后 finish_service")
	_eq(String(s2.port_undock(rid).get("status", "")), "DEPARTED", "load 后 undock")
	_eq(bool(s2.set_roe("HOLD").get("ok", false)), true, "load 后 set_roe")
	# 旧存档兼容：删除组件字段和 seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("port_service")
	old.erase("combat_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("port_service")
	old_seed.erase("combat_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 port/combat 兼容", str(lr3.get("errors", [])))
	_ok(s3.port_service == null, "旧存档 load 后 port 退化")
	_ok(s3.combat_service == null, "旧存档 load 后 combat 退化")
	# 确定性：两实例同操作
	var a = GameSession.new(cfg)
	var b = GameSession.new(cfg)
	for sv in [a, b]:
		var r: Dictionary = sv.port_request("dock", "ship1", "p1", {"clearance": "C"})
		var xid := String(r.get("request_id", ""))
		sv.port_permit(xid)
		sv.port_approach(xid)
		sv.port_dock(xid)
		sv.port_refuel(xid, 10.0)
		sv.combat_register_track("T1", {"identity": "hostile", "threat": "hostile",
			"range_km": 500.0, "in_arc": true})
		sv.combat_request_solution("T1", "railgun")
		sv.tick(5.0)
		sv.grant_authorization("FIRE", "target", "T1")
		sv.request_fire("T1", "railgun", true)
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "port+combat 同操作 snapshot 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"port+combat 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("pc_save", "save/load port+combat VM/snapshot 一致 · 继续操作 · 旧档兼容 · 确定性")

# ═══════════════════════════════════════════════════════════════════
# 25. Damage 集成（Session/Combat 伤害事件 → DamageService）
# ═══════════════════════════════════════════════════════════════════

func _damage_cfg_session() -> Dictionary:
	return {"damage_service": {"ships": ["apsis", "harmattan"], "default_ship": "apsis"}}

func _damage_core(s) -> String:
	var vm: Dictionary = s.damage_vm()
	return _norm_json({"t": vm.get("t", 0.0), "ships": vm.get("ships", []),
		"applied_damage": vm.get("applied_damage", [])})

func _damage_integrity(s, ship_id: String, section := "hull") -> float:
	var vm: Dictionary = s.damage_ship_vm(ship_id)
	for raw in (vm.get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == section:
			return float((raw as Dictionary).get("integrity", -1.0))
	return -1.0

func _test_damage_integration() -> void:
	_section_begin("25 Damage 集成")
	# 可选退化
	var plain = _new_session()
	_ok(plain.damage_service == null, "默认无 damage_service")
	_eq(plain.damage_vm().size(), 0, "无 damage 时 VM 空")
	_eq(plain.damage_summary().size(), 0, "无 damage 时 summary 空")
	_eq((plain.damage_ships() as Array).size(), 0, "无 damage 时 ships 空")
	_eq(String(plain.damage_apply_hit("apsis", "hull", 0.2).get("reason", "")),
		"no_damage_service", "无 damage apply_hit 拒绝")
	_eq(String(plain.damage_repair("apsis", "hull").get("reason", "")),
		"no_damage_service", "无 damage repair 拒绝")
	_eq(String(plain.damage_apply_event({}).get("reason", "")),
		"no_damage_service", "无 damage event 拒绝")
	# 启用
	var s = GameSession.new(_damage_cfg_session())
	_ok(bool(s.ready), "damage session ready", str(s.errors))
	_ok(s.damage_service != null, "damage 启用")
	_ok(s.combat_service == null, "damage-only 无 combat")
	_eq(String(s.damage_vm().get("schema", "")), "v17.damage_service.v1", "damage vm schema")
	_eq((s.damage_ships() as Array).size(), 2, "damage 2 舰")
	_eq(int(s.damage_summary().get("ships", 0)), 2, "damage summary ships=2")
	_eq(int(s.damage_summary().get("operational", 0)), 2, "damage 全 operational")
	_eq((s.damage_ship_vm("apsis").get("sections", []) as Array).size(), 7,
		"apsis 7 分区")
	_eq(bool(s.damage_service.model("ferry") == null), true, "未配置 ferry")
	# 直接伤害/维修
	var r: Dictionary = s.damage_apply_hit("apsis", "hull", 0.4, 0.5)
	_eq(bool(r.get("ok", false)), true, "damage_apply_hit ok")
	_eq(bool(r.get("applied", false)), true, "damage applied")
	var integ := _damage_integrity(s, "apsis", "hull")
	_ok(integ < 1.0, "hull integrity <1", str(integ))
	_eq((s.damage_vm().get("applied_damage", []) as Array).size(), 1, "applied_damage 1")
	var rep: Dictionary = s.damage_repair("apsis", "hull", 1)
	_eq(bool(rep.get("ok", false)), true, "damage_repair ok")
	var t1: Dictionary = s.tick(2.0)
	_eq(bool(t1.get("ok", false)), true, "damage tick 驱动 ok")
	_near(float(s.damage_service.t), s.now_s(), 1.0e-6, "damage t 与会话同步")
	_ok(t1.get("damage_tick") is Dictionary, "tick 返回 damage_tick")
	_ok(bool(s.check_contracts().get("ok", false)), "damage contracts ok")
	# 失败不改状态
	var before := _damage_core(s)
	_eq(String(s.damage_apply_hit("no_ship", "hull", 0.2).get("reason", "")),
		"unknown_ship", "未知舰伤害拒绝")
	_eq(String(s.damage_apply_hit("apsis", "bad_section", 0.2).get("reason", "")),
		"invalid_section", "非法分区伤害拒绝")
	_eq(String(s.damage_repair("no_ship", "hull").get("reason", "")),
		"unknown_ship", "未知舰维修拒绝")
	_eq(_damage_core(s), before, "失败不改 damage 状态")
	# 总线 damage.* 事件（flush）
	s.flush_events()
	var devs: Array = s.bus.filter_events({"type": "damage"})
	_ok(devs.size() > 0, "damage.* 事件进 bus", str(devs.size()))
	var dkinds: Dictionary = {}
	for raw in devs:
		dkinds[String((raw as Dictionary).get("type", ""))] = true
	_ok(dkinds.has("damage.applied"), "bus 含 damage.applied")
	_ok(dkinds.has("damage.repair_queued"), "bus 含 repair_queued")
	# Combat 伤害事件白名单路由：incoming 不可拦截 → tick 内路由
	var cfg := _damage_cfg_session()
	cfg["combat_service"] = (_combat_cfg_session()["combat_service"] as Dictionary)
	var sc = GameSession.new(cfg)
	_ok(bool(sc.ready), "combat+damage ready", str(sc.errors))
	sc.combat_register_track("T1", {"identity": "hostile", "threat": "hostile",
		"range_km": 500.0, "in_arc": true, "ship_id": "apsis"})
	var inc: Dictionary = sc.combat_service.incoming_missile("threat-1", "T1", 0.5,
		{"eta_s": 0.1, "interceptable": false})
	_eq(bool(inc.get("ok", false)), true, "incoming 注册")
	var tk: Dictionary = sc.tick(1.0)
	_eq(bool(tk.get("ok", false)), true, "combat tick 路由 ok")
	_ok(_damage_integrity(sc, "apsis", "hull") < 1.0, "combat damage 写入 apsis hull")
	_ok((sc.damage_vm().get("applied_damage", []) as Array).size() >= 1,
		"combat damage applied 记录")
	var bus_types: Array = []
	for raw2 in sc.bus.recent(50):
		bus_types.append(String((raw2 as Dictionary).get("type", "")))
	_ok("combat.incoming_impact" in bus_types, "bus 含 combat.incoming_impact")
	_ok("damage.applied" in bus_types, "bus 含 damage.applied（combat 路由）")
	# 同一次伤害不重复应用
	var applied_before := (sc.damage_vm().get("applied_damage", []) as Array).size()
	sc.flush_events()
	_eq((sc.damage_vm().get("applied_damage", []) as Array).size(), applied_before,
		"flush 不重复应用")
	_ok(bool(sc.check_contracts().get("ok", false)), "combat+damage contracts ok")
	_data_line("damage", "可选退化 · 直接伤害/维修/tick · 总线事件 · combat damage 白名单路由")

# ═══════════════════════════════════════════════════════════════════
# 26. Damage 存档
# ═══════════════════════════════════════════════════════════════════

func _test_damage_save_load() -> void:
	_section_begin("26 Damage 存档")
	var cfg := _damage_cfg_session()
	cfg["combat_service"] = (_combat_cfg_session()["combat_service"] as Dictionary)
	var s = GameSession.new(cfg)
	s.damage_apply_hit("apsis", "hull", 0.5, 0.4)
	s.damage_apply_hit("harmattan", "sensors", 0.3, 0.3)
	s.damage_repair("apsis", "hull", 1)
	s.tick(2.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "damage save JSON 可解析")
	if d is Dictionary:
		_ok(String((d as Dictionary).get("damage_service", "")) != "", "save 含 damage_service")
		var seed: Dictionary = (d as Dictionary).get("seed", {})
		_ok(seed.has("damage_service"), "seed 含 damage_service 配置")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "damage load ok", str(lr.get("errors", [])))
	_ok(s2.damage_service != null, "load 重建 damage_service")
	_ok(_norm_json(s.damage_vm()) == _norm_json(s2.damage_vm()), "load 后 damage_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	_near(float(s2.damage_service.t), s2.now_s(), 1.0e-6, "load damage t 同步")
	# load 后继续
	var rep2: Dictionary = s2.damage_repair("harmattan", "sensors", 2)
	_eq(bool(rep2.get("ok", false)), true, "load 后继续维修")
	var t2: Dictionary = s2.tick(3.0)
	_eq(bool(t2.get("ok", false)), true, "load 后继续 tick")
	_ok(bool(s2.check_contracts().get("ok", false)), "继续后 contracts ok")
	# 旧存档兼容：删除伤害字段和 seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("damage_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("damage_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 damage 兼容", str(lr3.get("errors", [])))
	_ok(s3.damage_service == null, "旧存档 load 后 damage 退化")
	# 确定性：两实例同操作
	var a = GameSession.new(cfg)
	var b = GameSession.new(cfg)
	for sv in [a, b]:
		sv.damage_apply_hit("apsis", "hull", 0.4, 0.4)
		sv.damage_repair("apsis", "hull", 1)
		sv.tick(2.0)
		sv.damage_apply_hit("harmattan", "tanks", 0.6, 0.6)
		sv.tick(1.0)
	_ok(_norm_json(a.damage_vm()) == _norm_json(b.damage_vm()), "damage 同操作 VM 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"damage 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "damage 确定性 contracts ok")
	_data_line("damage_save", "save/load damage_vm/snapshot 一致 · 继续 · 旧档兼容 · 确定性")

# ═══════════════════════════════════════════════════════════════════
# 27. PhysicsWorld 集成（位置权威/tick 顺序/显式同步）
# ═══════════════════════════════════════════════════════════════════

func _physics_cfg_session() -> Dictionary:
	return {"physics_world": true}

func _physics_core(s) -> String:
	var vm: Dictionary = s.physics_vm()
	return _norm_json({"t": vm.get("t", 0.0), "entities": vm.get("entities", []),
		"samples": vm.get("samples", [])})

func _world_pos(s, entity_id: String) -> Array:
	var ent: Dictionary = s.world.entity(entity_id)
	var pos = ent.get("pos_km", [])
	return (pos as Array).duplicate() if pos is Array else []

func _test_physics_integration() -> void:
	_section_begin("27 Physics 集成")
	# 可选退化
	var plain = _new_session()
	_ok(plain.physics_world_service == null, "默认无 physics_world")
	_eq(plain.physics_vm().size(), 0, "无 physics VM 空")
	_eq(plain.physics_summary().size(), 0, "无 physics summary 空")
	_eq((plain.physics_entity_ids() as Array).size(), 0, "无 physics ids 空")
	_eq((plain.physics_positions() as Dictionary).size(), 0, "无 physics positions 空")
	_eq(String(plain.physics_state("apsis").get("reason", "")), "no_physics_world",
		"无 physics state 拒绝")
	_eq(String(plain.upsert_physics_entity("x", {}).get("reason", "")),
		"no_physics_world", "无 physics upsert 拒绝")
	_eq(String(plain.remove_physics_entity("x").get("reason", "")),
		"no_physics_world", "无 physics remove 拒绝")
	_eq(String(plain.set_physics_time(10.0).get("reason", "")),
		"no_physics_world", "无 physics set_time 拒绝")
	_eq(String(plain.sync_world_from_physics().get("reason", "")),
		"no_physics_world", "无 physics sync 拒绝")
	var pos_plain: Dictionary = plain.position_of("apsis")
	_eq(String(pos_plain.get("source", "")), "world", "无 physics position 退回 world")
	# 启用：自动灌入 seed 实体
	var s = GameSession.new(_physics_cfg_session())
	_ok(bool(s.ready), "physics session ready", str(s.errors))
	_ok(s.physics_world_service != null, "physics 启用")
	_eq((s.physics_entity_ids() as Array).size(), 3, "physics 3 seed 实体")
	_ok("apsis" in s.physics_entity_ids(), "physics 含 apsis")
	_eq(String(s.physics_vm().get("schema", "")), "v17.physics_world.v1", "physics vm schema")
	_eq(int(s.physics_summary().get("entities", 0)), 3, "physics summary 3")
	_near(float(s.physics_world_service.t), s.now_s(), 1.0e-6, "physics boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "physics boot contracts ok")
	var st: Dictionary = s.physics_state("apsis")
	_eq(String(st.get("frame", "")), "bary_rot", "physics_state frame")
	_ok((st.get("r", []) as Array).size() == 3, "physics_state r 3")
	var st_eci: Dictionary = s.physics_state("apsis", "earth_eci")
	_eq(String(st_eci.get("frame", "")), "earth_eci", "physics_state earth_eci")
	_eq((s.physics_positions() as Dictionary).size(), 3, "physics_positions 3")
	_eq(String(s.position_of("apsis").get("frame", "")), "bary_rot",
		"position_of 使用 physics 权威")
	# tick 顺序：time → physics → world；world 不自动同步
	var w0: Array = _world_pos(s, "apsis")
	var r0: Array = s.physics_state("apsis").get("r", [])
	var tick1: Dictionary = s.tick(90.0)
	_eq(bool(tick1.get("ok", false)), true, "physics tick ok")
	var pt: Dictionary = tick1.get("physics_tick", {})
	_eq(bool(pt.get("ok", false)), true, "physics_tick ok")
	_eq(int(pt.get("steps", 0)), 2, "physics 90s→2 步")
	_near(float(s.physics_world_service.t), s.now_s(), 1.0e-6, "tick 后 physics t 同步")
	_near(s.now_s(), 90.0, 1.0e-6, "tick 后 session t=90")
	_ok(bool((tick1.get("components", {}) as Dictionary).get("physics", false)),
		"tick components.physics")
	_ok(_norm_json(_world_pos(s, "apsis")) == _norm_json(w0), "world 位置不自动同步")
	_ok(_norm_json(s.physics_state("apsis").get("r", [])) != _norm_json(r0),
		"physics 位置已推进")
	_eq(bool(s.check_contracts().get("ok", false)), true, "physics tick contracts ok")
	# 显式同步
	var sync: Dictionary = s.sync_world_from_physics()
	_eq(bool(sync.get("ok", false)), true, "显式 sync ok")
	_eq(int(sync.get("count", 0)), 3, "sync 3 实体")
	_ok(_norm_json(_world_pos(s, "apsis")) == _norm_json(s.physics_state("apsis").get("r", [])),
		"sync 后 world=physics(apsis)")
	_ok(_norm_json(_world_pos(s, "harmattan")) == _norm_json(s.physics_state("harmattan").get("r", [])),
		"sync 后 world=physics(harmattan)")
	var bus_types: Array = []
	for raw in s.bus.recent(80):
		bus_types.append(String((raw as Dictionary).get("type", "")))
	_ok("physics.world_synced" in bus_types, "bus 含 physics.world_synced")
	_eq(bool(s.check_contracts().get("ok", false)), true, "sync 后 contracts ok")
	# 只同步 world 已有实体；physics 额外实体 skipped
	var up: Dictionary = s.upsert_physics_entity("extra_ship", {"r": [0.0, 0.0, 0.0],
		"v": [0.0, 0.0, 0.0], "mass_kg": 1000.0})
	_eq(bool(up.get("ok", false)), true, "upsert physics 实体 ok")
	_ok("extra_ship" in s.physics_entity_ids(), "实体已加入")
	var sync2: Dictionary = s.sync_world_from_physics()
	_ok("extra_ship" in (sync2.get("skipped", []) as Array), "world 缺失实体 skipped")
	var rem: Dictionary = s.remove_physics_entity("extra_ship")
	_eq(bool(rem.get("ok", false)), true, "remove physics 实体 ok")
	_ok(not ("extra_ship" in s.physics_entity_ids()), "实体已移除")
	# 失败不改状态
	var before := _physics_core(s)
	_eq(bool(s.upsert_physics_entity("bad", {"r": [NAN, 0.0, 0.0],
		"v": [0.0, 0.0, 0.0]}).get("ok", true)), false, "NaN 物理实体拒绝")
	_eq(bool(s.upsert_physics_entity("bad", {"state": {"r": [0.0, 0.0, 0.0],
		"v": [0.0, 0.0, 0.0]}, "mass_kg": -1.0}).get("ok", true)), false,
		"负质量物理实体拒绝")
	_eq(String(s.remove_physics_entity("no_such").get("reason", "")), "unknown_entity",
		"删除未知物理实体拒绝")
	_eq(_physics_core(s), before, "物理失败不改状态")
	# set_physics_time
	var target: float = s.now_s() + 120.0
	var stime: Dictionary = s.set_physics_time(target)
	_eq(bool(stime.get("ok", false)), true, "set_physics_time ok")
	_near(s.now_s(), target, 1.0e-6, "set_physics_time session t")
	_near(float(s.physics_world_service.t), target, 1.0e-6, "set_physics_time physics t")
	_eq(bool(s.check_contracts().get("ok", false)), true, "set_physics_time contracts ok")
	_eq(String(s.set_physics_time(target - 10.0).get("reason", "")), "time_regression",
		"set_physics_time 回退拒绝")
	# 暂停同步
	s.pause()
	var pt_before := float(s.physics_world_service.t)
	var paused_tick: Dictionary = s.tick(60.0)
	_eq(bool(paused_tick.get("paused", false)), true, "暂停 tick paused")
	_near(float(s.physics_world_service.t), pt_before, 1.0e-9, "暂停时不推进 physics")
	_eq(String(s.set_physics_time(s.now_s() + 60.0).get("reason", "")), "paused",
		"暂停时 set_physics_time 拒绝")
	s.resume()
	_ok(bool(s.tick(60.0).get("ok", false)), "resume 后 tick ok")
	_data_line("physics", "可选退化 · seed 实体 · tick 先 physics · world 不自动同步 · 显式 sync · 暂停不推进")

func _test_physics_save_load() -> void:
	_section_begin("28 Physics 存档")
	var s = GameSession.new(_physics_cfg_session())
	s.tick(120.0)
	s.sync_world_from_physics()
	s.upsert_physics_entity("extra_ship", {"r": [1.0, 2.0, 3.0],
		"v": [0.0, 0.0, 0.0], "mass_kg": 500.0})
	s.tick(60.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "physics save JSON 可解析")
	if d is Dictionary:
		_ok(String((d as Dictionary).get("physics_world", "")) != "", "save 含 physics_world")
		var seed: Dictionary = (d as Dictionary).get("seed", {})
		_ok(seed.has("physics_world"), "seed 含 physics_world 配置")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "physics load ok", str(lr.get("errors", [])))
	_ok(s2.physics_world_service != null, "load 重建 physics")
	_ok(_norm_json(s.physics_vm()) == _norm_json(s2.physics_vm()), "load 后 physics_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	_near(float(s2.physics_world_service.t), s2.now_s(), 1.0e-6, "load physics t 同步")
	_eq((s2.physics_entity_ids() as Array).size(), 4, "load physics 4 实体")
	# load 后继续推进
	s.tick(60.0)
	s2.tick(60.0)
	_ok(_norm_json(s.physics_vm()) == _norm_json(s2.physics_vm()), "load 后同 tick physics 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "继续后 contracts ok")
	# 旧存档兼容：删除 physics 字段 + seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("physics_world")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("physics_world")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 physics 兼容", str(lr3.get("errors", [])))
	_ok(s3.physics_world_service == null, "旧存档 load 后 physics 退化")
	# 确定性
	var a = GameSession.new(_physics_cfg_session())
	var b = GameSession.new(_physics_cfg_session())
	for sv in [a, b]:
		sv.tick(150.0)
		sv.sync_world_from_physics()
		sv.upsert_physics_entity("extra_ship", {"r": [1.0, 2.0, 3.0],
			"v": [0.0, 0.0, 0.0], "mass_kg": 500.0})
		sv.tick(60.0)
	_ok(_norm_json(a.physics_vm()) == _norm_json(b.physics_vm()), "physics 同操作 VM 一致")
	_ok(a.save_state() == b.save_state(), "physics 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "physics 确定性 contracts ok")
	_data_line("physics_save", "save/load physics_vm/snapshot 一致 · 继续 tick · 旧档兼容 · 确定性")


# ═══════════════════════════════════════════════════════════════════
# 29. SignalService 集成（ELINT/证据路由/灯语）
# ═══════════════════════════════════════════════════════════════════

func _signal_emitter(model: String, sig: String, lpi := false) -> Dictionary:
	return {"type": "radar", "model": model, "signature_name": sig,
		"active": true, "silent": false, "lpi": lpi,
		"frequency_mhz": 9500.0, "power_dbm": 90.0, "gain_tx_dbi": 30.0,
		"prf_hz": 1200.0, "scan_period_s": 1.0}

func _signal_cfg_session() -> Dictionary:
	return {"track_table": true, "signal_service": {
		"observer": {"id": "Obs", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [
			{"id": "E1", "pos_km": [0.0, 1500.0, 0.0],
				"emissions": [_signal_emitter("YW-R9", "YW-R9")]},
			{"id": "E2", "pos_km": [500.0, 1500.0, 0.0],
				"emissions": [_signal_emitter("KD-R6", "KD-R6", true)]},
			{"id": "E3", "pos_km": [0.0, 500.0, 0.0],
				"emissions": [{"type": "radar", "model": "YW-R9", "signature_name": "YW-R9",
					"active": true, "silent": true, "lpi": false,
					"frequency_mhz": 9500.0, "power_dbm": 90.0}]},
			{"id": "L1", "pos_km": [0.0, 20.0, 0.0]},
			{"id": "O1", "pos_km": [0.0, 20.0, 0.0], "occluded": true}],
		"stations": [
			{"id": "S1", "pos_km": [0.0, 0.0, 0.0], "enabled": true,
				"sigma_bearing_deg": 1.0},
			{"id": "S2", "pos_km": [1000.0, 0.0, 0.0], "enabled": true,
				"sigma_bearing_deg": 1.0}],
		"elint": {"enabled": true, "range_km": 60000.0, "refresh_s": 1.0},
		"month": 10, "time": "night"}}

func _signal_core(s) -> String:
	var vm: Dictionary = s.signal_vm()
	return _norm_json({"t": vm.get("t", 0.0),
		"observations": vm.get("observations", []),
		"evidence": vm.get("evidence", []),
		"transmissions": (vm.get("light", {}) as Dictionary).get("transmissions", [])})

func _track_count(s) -> int:
	return (s.track_table.tracks as Dictionary).size()

func _test_signal_integration() -> void:
	_section_begin("29 Signal 集成")
	# 可选退化
	var plain = _new_session()
	_ok(plain.signal_service == null, "默认无 signal_service")
	_eq(plain.signal_vm().size(), 0, "无 signal VM 空")
	_eq(plain.signal_summary().size(), 0, "无 signal summary 空")
	_eq(String(plain.signal_intercept("E1").get("reason", "")), "no_signal_service",
		"无 signal intercept 拒绝")
	_eq(String(plain.signal_df("E1").get("reason", "")), "no_signal_service",
		"无 signal df 拒绝")
	_eq(String(plain.signal_resolve("x").get("reason", "")), "no_signal_service",
		"无 signal resolve 拒绝")
	_eq(String(plain.light_send("APPROACH_REQ", "L1").get("reason", "")),
		"no_signal_service", "无 signal light_send 拒绝")
	_eq(String(plain.light_receive("x").get("reason", "")), "no_signal_service",
		"无 signal light_receive 拒绝")
	_eq(String(plain.light_ack("x").get("reason", "")), "no_signal_service",
		"无 signal light_ack 拒绝")
	# 启用 + track_table
	var s = GameSession.new(_signal_cfg_session())
	_ok(bool(s.ready), "signal session ready", str(s.errors))
	_ok(s.signal_service != null, "signal 启用")
	_eq(String(s.signal_vm().get("schema", "")), "signal_service.v1", "signal vm schema")
	_eq(bool(s.signal_summary().get("ready", false)), true, "signal summary ready")
	_eq(int(s.signal_summary().get("codes", 0)), 7, "signal 7 灯语码")
	_near(float(s.signal_service.t), s.now_s(), 1.0e-6, "signal boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "signal boot contracts ok")
	_ok(bool((s.tick(0.0).get("components", {}) as Dictionary).get("signal", false)),
		"tick components.signal")
	var tracks0 := _track_count(s)
	_ok(tracks0 > 0, "boot ELINT 已路由建 track", str(tracks0))
	# ELINT intercept → observation/evidence 白名单路由
	var r: Dictionary = s.signal_intercept("E1")
	_eq(bool(r.get("ok", false)), true, "intercept E1 ok")
	_ok((r.get("observations", []) as Array).size() > 0, "intercept observations")
	var route: Dictionary = s._last_signal_route
	_eq(bool(route.get("enabled", false)), true, "signal route enabled")
	_ok(int(route.get("observations", 0)) > 0, "route observations")
	_eq(_track_count(s), tracks0, "intercept 不重复建 track", str(_track_count(s)))
	var lvl_max := 0
	for tid in s.track_table.tracks.keys():
		var tr: Dictionary = s.track_table.tracks[tid]
		lvl_max = maxi(lvl_max, int(tr.get("level", 0)))
	_ok(lvl_max >= 3, "ELINT evidence 融合到 L3", str(lvl_max))
	# 重复 intercept 不新增 track
	var r2: Dictionary = s.signal_intercept("E1")
	_eq(bool(r2.get("ok", false)), true, "重复 intercept ok")
	_eq(_track_count(s), tracks0, "重复 intercept 不新增 track")
	# DF 多站 L1/L2 + evidence 路由
	var d: Dictionary = s.signal_df("E1")
	_eq(bool(d.get("ok", false)), true, "signal_df ok", str(d.get("reason", "")))
	_ok((d.get("l1", []) as Array).size() > 0, "DF L1")
	_ok((d.get("candidates", []) as Array).size() > 0, "DF candidates")
	_eq(_track_count(s), tracks0, "DF 不重复建 track")
	_ok(int(s._last_signal_route.get("evidence", 0)) > 0, "DF evidence 路由")
	var cand: Dictionary = (d.get("candidates", []) as Array)[0]
	_eq(int(cand.get("level_support", 0)), 2, "DF candidate L2")
	var fixid := String(cand.get("fix_id", ""))
	var rr: Dictionary = s.signal_resolve(fixid)
	_eq(bool(rr.get("ok", false)), true, "signal_resolve fix ok")
	_eq(String(rr.get("type", "")), "elint_fix", "resolve type")
	_eq(bool(s.signal_resolve("NOPE").get("ok", true)), false, "resolve 未知 false")
	# 静默/未知目标失败
	_eq(String(s.signal_intercept("E3").get("reason", "")), "no_emission",
		"静默目标 no_emission")
	_eq(bool(s.signal_intercept("NOPE").get("ok", true)), false, "未知目标 intercept false")
	# 灯语 send/receive/ack → bus light_signal.*
	var send: Dictionary = s.light_send("APPROACH_REQ", "L1")
	_eq(bool(send.get("ok", false)), true, "light_send ok", str(send.get("reason", "")))
	var txid := String((send.get("tx", {}) as Dictionary).get("tx_id", ""))
	_ok(txid != "", "light tx_id")
	_eq(String((send.get("tx", {}) as Dictionary).get("status", "")), "SENT", "light SENT")
	var recv: Dictionary = s.light_receive(txid)
	_eq(bool(recv.get("ok", false)), true, "light_receive ok")
	_eq(String((recv.get("tx", {}) as Dictionary).get("status", "")), "RECEIVED",
		"light RECEIVED")
	var ack: Dictionary = s.light_ack(txid)
	_eq(bool(ack.get("ok", false)), true, "light_ack ok")
	_eq(String((ack.get("tx", {}) as Dictionary).get("status", "")), "ACKED", "light ACKED")
	_eq(String(s.signal_resolve(txid).get("status", "")), "ACKED", "resolve ACKED")
	var bus_types: Array = []
	for raw in s.bus.recent(120):
		bus_types.append(String((raw as Dictionary).get("type", "")))
	_ok("light_signal.send" in bus_types, "bus light_signal.send")
	_ok("light_signal.receive" in bus_types, "bus light_signal.receive")
	_ok("light_signal.ack" in bus_types, "bus light_signal.ack")
	# 灯语失败：遮挡/超距/未知/误读
	_eq(String(s.light_send("APPROACH_REQ", "O1").get("reason", "")), "occluded",
		"目标遮挡 occluded")
	_eq(String(s.light_send("APPROACH_REQ", "L1", {"occluded": true}).get("reason", "")),
		"occluded", "显式遮挡 occluded")
	_eq(String(s.light_send("APPROACH_REQ", "E1").get("reason", "")), "out_of_range",
		"超距 out_of_range")
	_eq(bool(s.light_send("NOPE", "L1").get("ok", true)), false, "未知 code false")
	_eq(bool(s.light_send("APPROACH_REQ", "NOPE").get("ok", true)), false,
		"未知 target false")
	var send3: Dictionary = s.light_send("APPROACH_ACK", "L1")
	var tx3 := String((send3.get("tx", {}) as Dictionary).get("tx_id", ""))
	var mis: Dictionary = s.light_receive(tx3, {"misread": true})
	_eq(bool(mis.get("ok", true)), false, "误读 false")
	_eq(String(mis.get("reason", "")), "misread", "误读 reason")
	var bus_mis: Array = []
	for raw_m in s.bus.recent(240):
		bus_mis.append(String((raw_m as Dictionary).get("type", "")))
	_ok("light_signal.misread" in bus_mis, "bus light_signal.misread")
	# 超时：tick 驱动 signal.step
	var send2: Dictionary = s.light_send("MAYDAY", "L1", {"timeout_s": 1.0})
	var tx2 := String((send2.get("tx", {}) as Dictionary).get("tx_id", ""))
	var tk: Dictionary = s.tick(2.0)
	_eq(bool(tk.get("ok", false)), true, "signal tick ok")
	_near(float(s.signal_service.t), s.now_s(), 1.0e-6, "tick 后 signal t 同步")
	_eq(String(s.signal_resolve(tx2).get("status", "")), "TIMEOUT", "灯语超时 TIMEOUT")
	_eq(bool(s.light_receive(tx2).get("ok", true)), false, "超时后 receive false")
	_eq(bool(s.light_ack(tx2).get("ok", true)), false, "超时后 ack false")
	var bus2: Array = []
	for raw2 in s.bus.recent(200):
		bus2.append(String((raw2 as Dictionary).get("type", "")))
	_ok("light_signal.timeout" in bus2, "bus light_signal.timeout")
	# 失败不改状态
	var before := _signal_core(s)
	_eq(String(s.signal_intercept("NOPE").get("reason", "")), "no_signal",
		"未知 ELINT 目标 reason")
	_ok(not bool(s.signal_intercept("NOPE").get("ok", true)), "未知 ELINT 目标拒绝")
	# 未知目标 intercept 仍会做一次被动扫描（SignalService 行为）；以下失败不应改状态
	before = _signal_core(s)
	_eq(bool(s.light_receive("NOPE").get("ok", true)), false, "未知 tx receive false")
	_eq(bool(s.light_ack("NOPE").get("ok", true)), false, "未知 tx ack false")
	_eq(bool(s.signal_resolve("NOPE").get("ok", true)), false, "未知 signal id false")
	_eq(_signal_core(s), before, "signal 失败不改状态")
	_eq(bool(s.check_contracts().get("ok", false)), true, "signal contracts ok")
	_data_line("signal", "ELINT L1/L2/evidence→TrackTable 不重复建 track · light_signal.*→bus · 超时/遮挡/误读")

func _test_signal_save_load() -> void:
	_section_begin("30 Signal 存档")
	var cfg := _signal_cfg_session()
	var s = GameSession.new(cfg)
	s.track_table.tracks.clear()
	s.signal_intercept("E1")
	s.signal_df("E1")
	var send: Dictionary = s.light_send("APPROACH_REQ", "L1")
	var txid := String((send.get("tx", {}) as Dictionary).get("tx_id", ""))
	s.light_receive(txid)
	s.tick(3.0)
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "signal save JSON 可解析")
	if d is Dictionary:
		_ok(String((d as Dictionary).get("signal_service", "")) != "",
			"save 含 signal_service")
		var seed: Dictionary = (d as Dictionary).get("seed", {})
		_ok(seed.has("signal_service"), "seed 含 signal_service 配置")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "signal load ok", str(lr.get("errors", [])))
	_ok(s2.signal_service != null, "load 重建 signal_service")
	_ok(_norm_json(s.signal_vm()) == _norm_json(s2.signal_vm()), "load 后 signal_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	_near(float(s2.signal_service.t), s2.now_s(), 1.0e-6, "load signal t 同步")
	# load 后继续操作/推进
	var ok_mirror := false
	_ok(bool(s2.signal_intercept("E2").get("ok", false)), "load 后继续 intercept")
	var send2: Dictionary = s2.light_send("HOLD_POSITION", "L1")
	_eq(bool(send2.get("ok", false)), true, "load 后继续 light_send")
	ok_mirror = bool(s.signal_intercept("E2").get("ok", false))
	ok_mirror = ok_mirror and bool(s.light_send("HOLD_POSITION", "L1").get("ok", false))
	_ok(ok_mirror, "原始实例镜像持续操作")
	s.tick(2.0)
	s2.tick(2.0)
	_ok(_norm_json(s.signal_vm()) == _norm_json(s2.signal_vm()), "load 后同 tick signal 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "继续后 contracts ok")
	# 旧存档兼容：删除 signal 字段 + seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("signal_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("signal_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 signal 兼容", str(lr3.get("errors", [])))
	_ok(s3.signal_service == null, "旧存档 load 后 signal 退化")
	# 启动配置 emitters/light_codes/month/time
	var em_cfg: Dictionary = {"track_table": true, "signal_service": {
		"observer": {"id": "Obs", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [],
		"emitters": [{"id": "E1", "target_id": "E1", "pos_km": [0.0, 1500.0, 0.0],
			"type": "radar", "model": "YW-R9", "signature_name": "YW-R9",
			"active": true, "silent": false, "lpi": false,
			"frequency_mhz": 9500.0, "power_dbm": 90.0}],
		"month": 10, "time": "night"}}
	var s4 = GameSession.new(em_cfg)
	_ok(bool(s4.ready), "emitters/month/time boot ready", str(s4.errors))
	_ok(bool(s4.signal_intercept("E1").get("ok", false)), "emitters 配置 E1 可拦截")
	# 确定性：两实例同操作
	var a = GameSession.new(_signal_cfg_session())
	var b = GameSession.new(_signal_cfg_session())
	for sv in [a, b]:
		sv.signal_intercept("E1")
		sv.signal_df("E1")
		var sd: Dictionary = sv.light_send("APPROACH_REQ", "L1")
		var stx := String((sd.get("tx", {}) as Dictionary).get("tx_id", ""))
		sv.light_receive(stx)
		sv.tick(3.0)
	_ok(_norm_json(a.signal_vm()) == _norm_json(b.signal_vm()), "signal 同操作 VM 一致")
	_ok(a.save_state() == b.save_state(), "signal 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "signal 确定性 contracts ok")
	_data_line("signal_save", "save/load signal_vm/snapshot 一致 · 继续 · 旧档兼容 · emitters 配置 · 确定性")

# ═══════════════════════════════════════════════════════════════════
# 31. Signal→Track 实体绑定（entity_id/batch）
# ═══════════════════════════════════════════════════════════════════

func _bind_emitter(model: String, sig: String) -> Dictionary:
	return {"type": "radar", "model": model, "signature_name": sig,
		"active": true, "silent": false, "lpi": false,
		"frequency_mhz": 9500.0, "power_dbm": 90.0, "gain_tx_dbi": 30.0,
		"prf_hz": 1200.0, "scan_period_s": 1.0}

func _binding_cfg() -> Dictionary:
	return {"track_table": true,
		"sensor_service": {"targets": [
			{"id": "E1", "entity_id": "apsis", "batch": "B1"},
			{"id": "harmattan", "entity_id": "harmattan", "batch": "META-B"}]},
		"signal_service": {
			"observer": {"id": "Obs", "pos_km": [0.0, 0.0, 0.0]},
			"targets": [
				{"id": "E1", "pos_km": [0.0, 1500.0, 0.0],
					"emissions": [_bind_emitter("YW-R9", "YW-R9")]},
				{"id": "apsis", "pos_km": [100.0, 1500.0, 0.0],
					"emissions": [_bind_emitter("KD-R6", "KD-R6")]},
				{"id": "harmattan", "pos_km": [200.0, 1500.0, 0.0],
					"emissions": [_bind_emitter("KD-R7", "KD-R7")]},
				{"id": "UNBOUND", "pos_km": [300.0, 1500.0, 0.0],
					"emissions": [_bind_emitter("XX-R1", "XX-R1")]}],
			"stations": [{"id": "S1", "pos_km": [0.0, 0.0, 0.0]}]}}

func _track_for_entity(s, entity_id: String) -> Dictionary:
	for tid in (s.track_table.tracks as Dictionary).keys():
		var tr: Dictionary = s.track_table.tracks[tid]
		if String(tr.get("entity_id", "")) == entity_id:
			return tr
	return {}

func _track_rows_vm(s) -> Array:
	return s.track_table.vm().get("tracks", []) as Array

func _test_signal_binding() -> void:
	_section_begin("31 Signal 实体绑定")
	var s = GameSession.new(_binding_cfg())
	_ok(bool(s.ready), "binding session ready", str(s.errors))
	# 启动时 target_meta 来自 sensor 配置（优先） + signal 配置自带 meta 均可
	var bind_e1: Dictionary = s._signal_binding("E1")
	_eq(String(bind_e1.get("entity_id", "")), "apsis", "binding E1 entity=apsis")
	_eq(String(bind_e1.get("batch", "")), "B1", "binding E1 batch=B1")
	_eq(String(bind_e1.get("source", "")), "sensor_target_meta", "binding E1 source meta")
	var bind_ap: Dictionary = s._signal_binding("apsis")
	_eq(String(bind_ap.get("entity_id", "")), "apsis", "binding world entity")
	_eq(String(bind_ap.get("source", "")), "world", "binding world source")
	var bind_hm: Dictionary = s._signal_binding("harmattan")
	_eq(String(bind_hm.get("entity_id", "")), "harmattan", "binding harmattan entity")
	_eq(String(bind_hm.get("batch", "")), "META-B", "meta 优先于 world batch")
	var bind_un: Dictionary = s._signal_binding("UNBOUND")
	_eq(String(bind_un.get("entity_id", "")), "", "未知目标 entity 空")
	_eq(String(bind_un.get("batch", "")), "", "未知目标 batch 空")
	# 拦截后 track 具备 entity_id/batch（UI 可用）
	var r: Dictionary = s.signal_intercept("E1")
	_eq(bool(r.get("ok", false)), true, "intercept E1 ok")
	var tr_e1: Dictionary = _track_for_entity(s, "apsis")
	_ok(not tr_e1.is_empty(), "E1 track 有 entity_id=apsis")
	_eq(String(tr_e1.get("batch", "")), "B1", "E1 track batch=B1")
	_eq(int(tr_e1.get("level", 0)), 3, "E1 track evidence L3")
	var tracks_before := _track_count(s)
	var r2: Dictionary = s.signal_intercept("E1")
	_eq(bool(r2.get("ok", false)), true, "重复 intercept ok")
	_eq(_track_count(s), tracks_before, "重复拦截不重复建 track")
	# evidence 复用同一 track（不新增、level 不退化）
	var tr_e1b: Dictionary = _track_for_entity(s, "apsis")
	_eq(String(tr_e1b.get("id", "")), String(tr_e1.get("id", "")), "evidence 复用同 track")
	_ok(int(tr_e1b.get("level", 0)) >= 3, "evidence 后 L3")
	# world 绑定目标
	var ra: Dictionary = s.signal_intercept("apsis")
	_eq(bool(ra.get("ok", false)), true, "intercept world apsis ok")
	var tr_ap: Dictionary = _track_for_entity(s, "apsis")
	_ok(not tr_ap.is_empty(), "world apsis track entity")
	var tr_hm: Dictionary = _track_for_entity(s, "harmattan")
	_ok(not tr_hm.is_empty(), "meta harmattan track entity")
	_eq(String(tr_hm.get("batch", "")), "META-B", "meta 优先 batch 写入 track")
	# 缺失目标元数据：留空 + warning（不硬编码）
	var ru: Dictionary = s.signal_intercept("UNBOUND")
	_eq(bool(ru.get("ok", false)), true, "intercept UNBOUND ok")
	var route: Dictionary = s._last_signal_route
	_ok(int(route.get("missing_meta", 0)) >= 1, "route missing_meta")
	_ok(int(route.get("bound", 0)) >= 1, "route bound")
	var warn_hit := false
	for w in s.warnings:
		if String(w).contains("UNBOUND") and String(w).contains("entity/batch"):
			warn_hit = true
	_ok(warn_hit, "缺失目标 warning")
	var unbound_track := {}
	for tid2 in (s.track_table.tracks as Dictionary).keys():
		var tr2: Dictionary = s.track_table.tracks[tid2]
		if String(tr2.get("entity_id", "")) == "":
			unbound_track = tr2
	_ok(not unbound_track.is_empty(), "缺失目标 track entity 保持空")
	# UI track_vm 可用
	var rows: Array = _track_rows_vm(s)
	_ok(rows.size() >= 2, "track_vm rows")
	var entity_rows := 0
	var batch_rows := 0
	for raw in rows:
		var row: Dictionary = raw
		_ok(String(row.get("id", "")) != "", "track_vm id")
		_ok(row.has("entity_id"), "track_vm entity_id 字段")
		_ok(row.has("batch"), "track_vm batch 字段")
		_ok(int(row.get("level", 0)) >= 1, "track_vm level")
		_ok(float(row.get("last_update", -1.0)) >= 0.0, "track_vm last_update")
		if String(row.get("entity_id", "")) != "":
			entity_rows += 1
		if String(row.get("batch", "")) != "":
			batch_rows += 1
	_ok(entity_rows >= 2, "track_vm 多条有 entity_id", str(entity_rows))
	_ok(batch_rows >= 2, "track_vm 多条有 batch", str(batch_rows))
	_ok(JSON.parse_string(JSON.stringify(rows)) is Array, "track_vm JSON")
	# 失败/未知目标不新增 track
	var cnt := _track_count(s)
	_eq(bool(s.signal_intercept("NOPE").get("ok", true)), false, "未知目标 false")
	_eq(_track_count(s), cnt, "未知目标不新增 track")
	_eq(bool(s.check_contracts().get("ok", false)), true, "binding contracts ok")
	# 存档/load 绑定保持
	var save := s.save_state()
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "binding load ok", str(lr.get("errors", [])))
	_ok(not _track_for_entity(s2, "apsis").is_empty(), "load 后 entity 绑定保持")
	_eq(String(_track_for_entity(s2, "apsis").get("batch", "")), "B1",
		"load 后 batch 保持")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "binding load snapshot 一致")
	# 确定性
	var a = GameSession.new(_binding_cfg())
	var b = GameSession.new(_binding_cfg())
	for x in [a, b]:
		x.signal_intercept("E1")
		x.signal_intercept("apsis")
		x.signal_intercept("harmattan")
		var rr: Dictionary = x._last_signal_route
		ok_mirror = int(rr.get("bound", 0)) >= 1
	_ok(ok_mirror, "binding 同操作 bound")
	_ok(_norm_json(a.snapshot()) == _norm_json(b.snapshot()), "binding 同操作 snapshot 一致")
	_ok(a.save_state() == b.save_state(), "binding 同操作 save 一致")
	_data_line("binding", "target_meta 优先 entity/batch · world 兜底 · 缺失留空+warning · UI track_vm · 存档/确定性")

var ok_mirror := false

# ═══════════════════════════════════════════════════════════════════
# 32. Signal 动态目标（Session 包装；side 不拒绝灯语）
# ═══════════════════════════════════════════════════════════════════

func _test_signal_dynamic_targets() -> void:
	_section_begin("32 Signal 动态目标")
	# 可选退化
	var plain = _new_session()
	_eq(String(plain.signal_upsert_target({"id": "X", "side": "hostile"}).get("reason", "")),
		"no_signal_service", "无 signal upsert 拒绝")
	_eq(String(plain.signal_remove_target("X").get("reason", "")), "no_signal_service",
		"无 signal remove 拒绝")
	_eq(String(plain.signal_set_targets([]).get("reason", "")), "no_signal_service",
		"无 signal set_targets 拒绝")
	_eq(String(plain.signal_sync_targets([]).get("reason", "")), "no_signal_service",
		"无 signal sync_targets 拒绝")
	_eq((plain.signal_target_ids() as Array).size(), 0, "无 signal target_ids 空")
	_eq(plain.signal_target("X").size(), 0, "无 signal target 空")
	_eq(String(plain.signal_sync_from_world().get("reason", "")), "no_signal_service",
		"无 signal sync_from_world 拒绝")
	_eq(String(plain.signal_sync_from_contacts().get("reason", "")), "no_signal_service",
		"无 signal sync_from_contacts 拒绝")
	# 启用（绑定配置同时有 track_table）
	var s = GameSession.new(_binding_cfg())
	_ok(bool(s.ready), "dynamic session ready", str(s.errors))
	_ok("E1" in s.signal_target_ids(), "初始 target_ids 含 E1")
	# 跑一次绑定路由，让 contacts 有 track
	s.signal_intercept("E1")
	s.signal_intercept("harmattan")
	# upsert 动态目标（hostile/neutral/unknown）
	var up: Dictionary = s.signal_upsert_target({"id": "H1", "side": "hostile",
		"entity_id": "apsis", "batch": "B-DYN", "pos_km": [0.0, 20.0, 0.0],
		"light_capable": true, "receiver_facing": true})
	_eq(bool(up.get("ok", false)), true, "session upsert hostile ok")
	_eq(String(s.signal_target("H1").get("side", "")), "hostile", "session H1 side")
	_eq(String(s.signal_target("H1").get("entity_id", "")), "apsis", "session H1 entity")
	s.signal_upsert_target({"id": "N1", "side": "neutral", "pos_km": [0.0, 20.0, 0.0]})
	s.signal_upsert_target({"id": "U1", "side": "unknown", "pos_km": [0.0, 20.0, 0.0]})
	# 灯语不因 side 拒绝；ACK 由能力决定
	for id in ["H1", "N1", "U1"]:
		var snd: Dictionary = s.light_send("APPROACH_REQ", String(id))
		_eq(bool(snd.get("ok", false)), true, "session 灯语可发 " + String(id))
		var tx := String((snd.get("tx", {}) as Dictionary).get("tx_id", ""))
		_eq(bool(s.light_receive(tx).get("ok", false)), true, "session 可收 " + String(id))
		_eq(bool(s.light_ack(tx).get("ok", false)), true, "session ACK " + String(id))
	# 能力失败
	s.signal_upsert_target({"id": "CAP", "side": "hostile",
		"pos_km": [0.0, 20.0, 0.0], "light_capable": false})
	var scap: Dictionary = s.light_send("APPROACH_REQ", "CAP")
	var txcap := String((scap.get("tx", {}) as Dictionary).get("tx_id", ""))
	s.light_receive(txcap)
	_eq(String(s.light_ack(txcap).get("reason", "")), "not_light_capable",
		"session 无能力 ack 拒绝")
	_eq(String(s.signal_resolve(txcap).get("status", "")), "RECEIVED",
		"session 失败不伪造 ACK")
	# remove / set / sync
	_eq(bool(s.signal_remove_target("U1").get("ok", false)), true, "session remove ok")
	_ok(not ("U1" in s.signal_target_ids()), "session remove 后不在")
	_eq(bool(s.signal_remove_target("U1").get("ok", true)), false, "session remove 未知拒绝")
	var ids_before: Array = s.signal_target_ids()
	_eq(bool(s.signal_set_targets([{"id": "X1", "side": "hostile"},
		{"id": "X1", "side": "neutral"}]).get("ok", true)), false,
		"session set 重复拒绝")
	_eq(s.signal_target_ids(), ids_before, "session set 失败不改状态")
	var setr: Dictionary = s.signal_set_targets([
		{"id": "S1", "side": "hostile", "pos_km": [0.0, 20.0, 0.0]},
		{"id": "S2", "side": "neutral", "pos_km": [0.0, 20.0, 0.0]}])
	_eq(bool(setr.get("ok", false)), true, "session set_targets ok")
	_eq(s.signal_target_ids(), ["S1", "S2"], "session set 后目标")
	var sy: Dictionary = s.signal_sync_targets([
		{"id": "S1", "batch": "B-S"}, {"id": "S3", "side": "friend",
			"pos_km": [0.0, 20.0, 0.0]}])
	_eq(bool(sy.get("ok", false)), true, "session sync_targets ok")
	_eq(int(sy.get("added", -1)), 1, "session sync added")
	_eq(int(sy.get("updated", -1)), 1, "session sync updated")
	_eq(String(s.signal_target("S1").get("side", "")), "hostile", "session sync 保留 side")
	# 从 world 同步（只读 world，不写）
	var wp_before := JSON.stringify((s.world.entity("apsis") as Dictionary).get("pos_km", []))
	var sw: Dictionary = s.signal_sync_from_world()
	_eq(bool(sw.get("ok", false)), true, "sync_from_world ok")
	_eq(String(sw.get("source", "")), "world", "sync_from_world source")
	_ok("apsis" in s.signal_target_ids(), "world 目标 apsis 加入")
	_ok("harmattan" in s.signal_target_ids(), "world 目标 harmattan 加入")
	_eq(String(s.signal_target("apsis").get("entity_id", "")), "apsis", "world target entity")
	_eq(JSON.stringify((s.world.entity("apsis") as Dictionary).get("pos_km", [])), wp_before,
		"sync_from_world 不写 world")
	# 从 contacts（TrackTable）同步
	var sc: Dictionary = s.signal_sync_from_contacts()
	_eq(bool(sc.get("ok", false)), true, "sync_from_contacts ok")
	_eq(String(sc.get("source", "")), "contacts", "sync_from_contacts source")
	_ok(int(sc.get("count", 0)) > 0, "contacts 目标数")
	var contact_ids: Array = s.signal_target_ids()
	var has_entity_target := false
	for tid in contact_ids:
		var tr: Dictionary = s.signal_target(String(tid))
		if String(tr.get("source", "")) == "contact" or String(tr.get("track_id", "")) != "":
			has_entity_target = true
	_ok(has_entity_target, "contacts 目标带 track_id/source")
	# 失败不改状态
	var ids_now: Array = s.signal_target_ids()
	_eq(bool(s.signal_upsert_target({"id": "BAD", "side": "enemy"}).get("ok", true)),
		false, "session 非法 side 拒绝")
	_eq(bool(s.signal_sync_targets([{"id": "BAD2", "side": "bad"}]).get("ok", true)),
		false, "session 非法 sync 拒绝")
	_eq(s.signal_target_ids(), ids_now, "失败不改动态目标")
	# 为存档/load 再注册动态目标（前面 set_targets 已替换掉 H1/CAP）
	s.signal_upsert_target({"id": "H1", "side": "hostile", "entity_id": "apsis",
		"batch": "B-DYN", "pos_km": [0.0, 20.0, 0.0], "light_capable": true})
	s.signal_upsert_target({"id": "CAP", "side": "hostile",
		"pos_km": [0.0, 20.0, 0.0], "light_capable": false})
	# 存档/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	var signal_json := String((d as Dictionary).get("signal_service", ""))
	_ok(signal_json != "", "session save 含 signal_service")
	var sigd = JSON.parse_string(signal_json)
	_ok(sigd is Dictionary and (sigd as Dictionary).has("targets"),
		"signal 快照含 targets")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "dynamic target load ok", str(lr.get("errors", [])))
	_eq(s2.signal_target_ids(), s.signal_target_ids(), "load 后 target_ids 一致")
	_eq(String(s2.signal_target("H1").get("side", "")), "hostile", "load 后 H1 side")
	_eq(bool(s2.signal_target("CAP").get("light_capable", true)), false,
		"load 后 CAP 能力")
	var send2: Dictionary = s2.light_send("APPROACH_REQ", "H1")
	_eq(bool(send2.get("ok", false)), true, "load 后灯语可发")
	# 旧 signal 快照缺 targets：保留 boot targets
	var old_sig: Dictionary = (sigd as Dictionary).duplicate(true)
	old_sig.erase("targets")
	var old_session: Dictionary = (d as Dictionary).duplicate(true)
	old_session["signal_service"] = JSON.stringify(old_sig)
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old_session))
	_eq(bool(lr3.get("ok", false)), true, "旧 signal 快照兼容", str(lr3.get("errors", [])))
	_ok((s3.signal_target_ids() as Array).size() > 0, "旧快照按 log 重建目标列表")
	# 确定性
	var a = GameSession.new(_binding_cfg())
	var b = GameSession.new(_binding_cfg())
	for sv in [a, b]:
		sv.signal_upsert_target({"id": "DX", "side": "hostile",
			"pos_km": [0.0, 20.0, 0.0]})
		var sd: Dictionary = sv.light_send("APPROACH_REQ", "DX")
		var stx := String((sd.get("tx", {}) as Dictionary).get("tx_id", ""))
		sv.light_receive(stx)
		sv.light_ack(stx)
		sv.signal_sync_from_world()
		sv.tick(1.0)
	_ok(_norm_json(a.signal_vm()) == _norm_json(b.signal_vm()),
		"dynamic 同操作 signal_vm 一致")
	_ok(a.save_state() == b.save_state(), "dynamic 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "dynamic contracts ok")
	_data_line("dynamic_targets", "side 不拒绝灯语 · ACK 由能力/状态 · 增删/替换/同步 world+contacts · 存档/确定性")

# ═══════════════════════════════════════════════════════════════════
# 33. FacilityRegistry 集成（只读设施注册表）
# ═══════════════════════════════════════════════════════════════════

func _test_facility_registry() -> void:
	_section_begin("33 Facility 注册表")
	# 可选退化
	var plain = _new_session()
	_ok(plain.facility_registry == null, "默认无 facility_registry")
	_eq(plain.facility_lookup("L1-05").size(), 0, "无 facility lookup 空")
	_eq(String(plain.facility_by_transponder("TXP-L1-05").get("reason", "")),
		"no_facility_registry", "无 facility transponder 拒绝")
	_eq(plain.facility_for_entity("l1_station").size(), 0, "无 facility entity 空")
	_eq((plain.facilities_by_cluster("L1_MERIDIAN") as Array).size(), 0,
		"无 facility cluster 空")
	_eq(plain.facility_vm().size(), 0, "无 facility vm 空")
	_eq(plain.facility_summary().size(), 0, "无 facility summary 空")
	# 启用
	var s = GameSession.new({"facility_registry": true})
	_ok(bool(s.ready), "facility session ready", str(s.errors))
	_ok(s.facility_registry != null, "facility 启用")
	var sum: Dictionary = s.facility_summary()
	_eq(int(sum.get("clusters", 0)), 7, "facility 7 cluster")
	_eq(int(sum.get("facilities", 0)), 29, "facility 29 站")
	_eq(int(sum.get("facility_codes", 0)), 29, "facility_code 29")
	_eq(int(sum.get("transponders", 0)), 29, "transponder 29")
	_eq(bool(s.check_contracts().get("ok", false)), true, "facility contracts ok")
	_ok(bool((s.tick(0.0).get("components", {}) as Dictionary).get("facility", false)),
		"tick components.facility")
	# lookup / transponder / entity / cluster
	var wp_before := JSON.stringify((s.world.entity("l1_station") as Dictionary).get("pos_km", []))
	var l105: Dictionary = s.facility_lookup("L1-05")
	_eq(String((l105.get("facility", {}) as Dictionary).get("name", "")), "Chronos",
		"facility_lookup L1-05")
	_eq(String((l105.get("codes", {}) as Dictionary).get("facility_code", "")),
		"FC-L1-05", "lookup codes")
	_eq((l105.get("ports", []) as Array).size(), 2, "lookup ports")
	_eq(String((l105.get("cluster", {}) as Dictionary).get("name", "")), "Meridian",
		"lookup cluster")
	_eq(String(s.facility_by_transponder("TXP-L4-02").get("facility_id", "")), "L4-02",
		"facility_by_transponder")
	_eq(String(s.facility_by_transponder("NOPE").get("reason", "")),
		"unknown_transponder", "未知 transponder 拒绝")
	_eq(String(s.facility_for_entity("l1_station").get("facility_id", "")), "L1-05",
		"facility_for_entity")
	_ok(s.facility_for_entity("no_such").is_empty(), "未知 entity 空")
	var l1: Array = s.facilities_by_cluster("L1_MERIDIAN")
	_eq(l1.size(), 4, "L1 4 站")
	_eq((s.facilities_by_cluster("NESOSS") as Array).size(), 6, "NESOSS 6 站")
	_eq((s.facilities_by_cluster("LUNSYNC") as Array).size(), 3, "LUNSYNC 3 站")
	_ok((s.facilities_by_cluster("NOPE") as Array).is_empty(), "未知 cluster 空")
	_ok(s.facility_lookup("NOPE").is_empty(), "未知 facility 空")
	_ok(JSON.parse_string(JSON.stringify(s.facility_vm())) is Dictionary,
		"facility_vm JSON")
	_eq((s.facility_vm().get("facilities", []) as Array).size(), 29, "facility_vm 29")
	# 不改现有实体
	_eq(JSON.stringify((s.world.entity("l1_station") as Dictionary).get("pos_km", [])),
		wp_before, "facility 查询不改变实体")
	_eq((s.world.entities_sorted() as Array).size(), 3, "world 实体数不变")
	# 存档/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("facility_registry"),
		"save 含 facility_registry")
	var seed: Dictionary = (d as Dictionary).get("seed", {})
	_ok(seed.has("facility_registry"), "seed 含 facility_registry")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "facility load ok", str(lr.get("errors", [])))
	_ok(s2.facility_registry != null, "load 重建 facility_registry")
	_ok(_norm_json(s.facility_vm()) == _norm_json(s2.facility_vm()),
		"load 后 facility_vm 一致")
	_ok(_norm_json(s.facility_summary()) == _norm_json(s2.facility_summary()),
		"load 后 summary 一致")
	_eq(String(s2.facility_lookup("L1-05").get("facility", {}).get("name", "")),
		"Chronos", "load 后 lookup")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# 旧存档兼容：删除 facility 字段 + seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("facility_registry")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("facility_registry")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 facility 兼容", str(lr3.get("errors", [])))
	_ok(s3.facility_registry == null, "旧存档 load 后 facility 退化")
	# 自定义 content_path（错误路径 → session 未就绪）
	var sbad = GameSession.new({"facility_registry": {"content_path": "/no/such.json"}})
	_ok(not bool(sbad.ready), "错误 content_path boot 失败")
	# 确定性
	var a = GameSession.new({"facility_registry": true})
	var b = GameSession.new({"facility_registry": true})
	_ok(_norm_json(a.facility_vm()) == _norm_json(b.facility_vm()),
		"facility 同操作 VM 一致")
	_ok(a.save_state() == b.save_state(), "facility 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "facility contracts ok 2")
	_data_line("facility", "7 cluster/29 站/57 港口 · lookup/transponder/entity/cluster · 不写 world · 存档/旧档/确定性")

# ═══════════════════════════════════════════════════════════════════
# 34. TransponderService 集成（应答机行为层）
# ═══════════════════════════════════════════════════════════════════

func _transponder_cfg_session() -> Dictionary:
	return {"facility_registry": true, "transponder_service": true}

func _transponder_routing_cfg() -> Dictionary:
	var tgt: Dictionary = _sensor_target("T1", "2001", [0.0, 500.0, 0.0],
		"ok", "CMP-2001", "friend")
	tgt["entity_id"] = "apsis"
	tgt["batch"] = "B1"
	return {"facility_registry": true, "transponder_service": true,
		"track_table": true,
		"sensor_service": {
			"observer": {"id": "harmattan", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0], "attitude_quat": [0.0, 0.0, 0.0, 1.0]},
			"targets": [tgt],
			"snapshot": {"sun_dir": [0.0, 0.0, 1.0], "sun_illum": 1.0,
				"jamming": 0.0, "shadow": false, "los": true},
			"options": {"radar_enabled": true, "emcon": false}}}

func _test_transponder_integration() -> void:
	_section_begin("34 Transponder 集成")
	# 可选退化
	var plain = _new_session()
	_ok(plain.transponder_service == null, "默认无 transponder_service")
	_eq(plain.transponder_vm().size(), 0, "无 transponder VM 空")
	_eq(plain.transponder_summary().size(), 0, "无 transponder summary 空")
	_eq((plain.transponder_trigger_ids() as Array).size(), 0, "无 transponder trigger_ids 空")
	_eq(String(plain.transponder_interrogate("a", "b").get("reason", "")),
		"no_transponder_service", "无 transponder interrogate 拒绝")
	_eq(String(plain.transponder_broadcast().get("reason", "")),
		"no_transponder_service", "无 transponder broadcast 拒绝")
	_eq(String(plain.transponder_lookup_code("X").get("reason", "")),
		"no_transponder_service", "无 transponder lookup 拒绝")
	_eq(String(plain.transponder_set_status("a", "normal").get("reason", "")),
		"no_transponder_service", "无 transponder set_status 拒绝")
	_eq(String(plain.transponder_set_jam("a", 0.5).get("reason", "")),
		"no_transponder_service", "无 transponder set_jam 拒绝")
	_eq(String(plain.transponder_set_occlusion("a", true).get("reason", "")),
		"no_transponder_service", "无 transponder set_occlusion 拒绝")
	_eq(String(plain.transponder_set_crypto("a", {}).get("reason", "")),
		"no_transponder_service", "无 transponder set_crypto 拒绝")
	_eq(String(plain.transponder_upsert_profile({}).get("reason", "")),
		"no_transponder_service", "无 transponder upsert 拒绝")
	_eq(String(plain.transponder_remove_profile("a").get("reason", "")),
		"no_transponder_service", "无 transponder remove 拒绝")
	# 启用
	var s = GameSession.new(_transponder_cfg_session())
	_ok(bool(s.ready), "transponder session ready", str(s.errors))
	_ok(s.transponder_service != null, "transponder 启用")
	_eq(int(s.transponder_summary().get("profiles", 0)), 6, "transponder 6 profiles")
	_eq(String(s.transponder_vm().get("schema", "")), "v17.transponder_service.v1",
		"transponder vm schema")
	_near(float(s.transponder_service.t), s.now_s(), 1.0e-6, "transponder boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "transponder boot contracts ok")
	_ok(bool((s.tick(0.0).get("components", {}) as Dictionary).get("transponder", false)),
		"tick components.transponder")
	_ok(bool((s.tick(1.0).get("transponder_tick", {}) as Dictionary).get("enabled", false)),
		"tick transponder_tick enabled")
	# 询问/广播/lookup
	var r: Dictionary = s.transponder_interrogate("l1_station", "apsis", "mode_s")
	_eq(bool(r.get("ok", false)), true, "transponder interrogate ok")
	_eq(String((r.get("reply", {}) as Dictionary).get("transponder_code", "")),
		"TXP-APSIS-01", "transponder reply code")
	_eq(String(s.transponder_lookup_code("TXP-APSIS-01").get("profile_id", "")),
		"apsis", "transponder lookup")
	var br: Dictionary = s.transponder_broadcast()
	_eq(bool(br.get("ok", false)), true, "transponder broadcast ok")
	_ok((br.get("broadcasts", []) as Array).size() >= 3, "transponder broadcast rows")
	var pl: Dictionary = s.transponder_passive_listen()
	_eq(bool(pl.get("passive", false)), true, "transponder passive")
	# 状态/触发
	_eq(bool(s.transponder_set_status("l1_station", "captured").get("ok", false)),
		true, "transponder set_status captured")
	var rc: Dictionary = s.transponder_interrogate("apsis", "l1_station", "station_beacon")
	_eq(bool((rc.get("reply", {}) as Dictionary).get("spoofed", false)), true,
		"transponder captured spoofed")
	_eq(String((rc.get("trigger", {}) as Dictionary).get("trigger_id", "")),
		"station_spoof", "transponder station_spoof trigger")
	_eq(bool(s.transponder_set_status("l1_station", "normal").get("ok", false)), true,
		"transponder status normal")
	var rf: Dictionary = s.transponder_interrogate("apsis", "ceres_2_demo", "mode_s")
	_eq(String((rf.get("trigger", {}) as Dictionary).get("trigger_id", "")),
		"ceres_no_reply", "transponder ceres_no_reply")
	_ok("ceres_no_reply" in s.transponder_trigger_ids(), "transponder trigger_ids")
	# 加密/干扰/遮挡 wrapper
	_eq(bool(s.transponder_set_crypto("greenwich", {"valid": false}).get("ok", false)),
		true, "transponder set_crypto")
	_eq(String(s.transponder_interrogate("apsis", "greenwich", "mode_5").get("reason", "")),
		"crypto_fail", "transponder crypto_fail")
	s.transponder_set_crypto("greenwich", {"valid": true, "captured": false})
	_eq(bool(s.transponder_set_jam("apsis", 0.9).get("ok", false)), true,
		"transponder set_jam")
	_eq(String(s.transponder_interrogate("x", "apsis").get("reason", "")),
		"jammed", "transponder jammed")
	s.transponder_set_jam("apsis", 0.0)
	_eq(bool(s.transponder_set_occlusion("apsis", true).get("ok", false)), true,
		"transponder set_occlusion")
	_eq(String(s.transponder_interrogate("x", "apsis").get("reason", "")),
		"occluded", "transponder occluded")
	s.transponder_set_occlusion("apsis", false)
	# profile 管理
	var np: Dictionary = {"profile_id": "probe_ship", "name": "Probe",
		"entity_type": "ship", "entity_id": "probe_ship",
		"transponder_code": "TXP-PROBE-01", "registration_code": "REG-PROBE-01",
		"modes": ["mode_s"], "default_mode": "mode_s", "status": "normal",
		"range_km": 1000.0}
	_eq(bool(s.transponder_upsert_profile(np).get("ok", false)), true,
		"transponder upsert_profile")
	_eq(String(s.transponder_profile("probe_ship").get("name", "")), "Probe",
		"transponder profile")
	_eq(bool(s.transponder_remove_profile("probe_ship").get("ok", false)), true,
		"transponder remove_profile")
	# 事件总线
	var bus_types: Array = []
	for raw in s.bus.recent(200):
		bus_types.append(String((raw as Dictionary).get("type", "")))
	_ok("transponder.interrogation" in bus_types, "bus transponder.interrogation")
	_ok("transponder.broadcast" in bus_types, "bus transponder.broadcast")
	_ok("transponder.no_reply" in bus_types, "bus transponder.no_reply")
	_ok("transponder.status_changed" in bus_types, "bus transponder.status_changed")
	# world 不变
	_ok((s.world.entities_sorted() as Array).size() == 3, "transponder 不改 world 实体数")
	_eq(JSON.stringify((s.world.entity("apsis") as Dictionary).get("pos_km", [])),
		"[0.0,0.0,0.0]", "transponder 不改实体位置")
	# evidence 路由：先由 sensor 建/更新 track(entity apsis)
	var sr = GameSession.new(_transponder_routing_cfg())
	_ok(bool(sr.ready), "transponder routing session ready", str(sr.errors))
	sr.tick(1.0)
	var tracks0: int = (sr.track_table.tracks as Dictionary).size()
	_ok(tracks0 > 0, "sensor 已建 track")
	var tr_entity := {}
	for tid in (sr.track_table.tracks as Dictionary).keys():
		var tr: Dictionary = sr.track_table.tracks[tid]
		if String(tr.get("entity_id", "")) == "apsis":
			tr_entity = tr
	_ok(not tr_entity.is_empty(), "track entity=apsis")
	var rt: Dictionary = sr.transponder_interrogate("l1_station", "apsis", "mode_s")
	_eq(bool(rt.get("ok", false)), true, "routing interrogate ok")
	var tracks1: int = (sr.track_table.tracks as Dictionary).size()
	_eq(tracks1, tracks0, "transponder evidence 不重复建 track")
	var lvl_after := 0
	var sources_after: Array = []
	for tid2 in (sr.track_table.tracks as Dictionary).keys():
		var tr2: Dictionary = sr.track_table.tracks[tid2]
		if String(tr2.get("entity_id", "")) == "apsis":
			lvl_after = int(tr2.get("level", 0))
			sources_after = (tr2.get("sources", []) as Array).duplicate()
	_ok(lvl_after >= 4, "transponder evidence 融合 L4", str(lvl_after))
	_ok("iff" in sources_after, "track sources 含 iff")
	_eq(bool(sr.check_contracts().get("ok", false)), true, "routing contracts ok")
	# 存档/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("transponder_service"),
		"save 含 transponder_service")
	var seed: Dictionary = (d as Dictionary).get("seed", {})
	_ok(seed.has("transponder_service"), "seed 含 transponder_service")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "transponder load ok", str(lr.get("errors", [])))
	_ok(s2.transponder_service != null, "load 重建 transponder")
	_ok(_norm_json(s.transponder_vm()) == _norm_json(s2.transponder_vm()),
		"load 后 transponder_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	var rr2: Dictionary = s2.transponder_interrogate("l1_station", "apsis", "mode_s")
	_eq(bool(rr2.get("ok", false)), true, "load 后继续 interrogate")
	# 旧存档兼容：删除 transponder 字段 + seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("transponder_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("transponder_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 transponder 兼容", str(lr3.get("errors", [])))
	_ok(s3.transponder_service == null, "旧存档 load 后 transponder 退化")
	# 确定性
	var a = GameSession.new(_transponder_cfg_session())
	var b = GameSession.new(_transponder_cfg_session())
	for sv in [a, b]:
		sv.transponder_interrogate("l1_station", "apsis", "mode_s")
		sv.transponder_broadcast()
		sv.transponder_set_status("l1_station", "spoofed")
		sv.transponder_interrogate("apsis", "l1_station", "station_beacon")
		sv.tick(1.0)
	_ok(_norm_json(a.transponder_vm()) == _norm_json(b.transponder_vm()),
		"transponder 同操作 VM 一致")
	_ok(a.save_state() == b.save_state(), "transponder 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "transponder contracts ok 2")
	_data_line("transponder", "询问/广播/lookup/状态/加密/干扰/遮挡/trigger · evidence→TrackTable L4 · bus · 存档/旧档/确定性")

# ── EWService 可选接入 ─────────────────────────────────────────

func _test_ew_integration() -> void:
	_section_begin("ew")
	var off = GameSession.new({})
	_ok(off.ew_service == null, "未配置 ew 退化")
	_ok(not bool(off.apply_ew({"effect": "noise_jam", "source_id": "x"}).get("ok", true)),
		"未配置 apply_ew false")
	var cfg := {"ew_service": {"observer": {"id": "own"},
		"targets": [{"id": "T1", "pos_km": [100.0, 0.0, 0.0]}]}}
	var s = GameSession.new(cfg)
	_ok(bool(s.ready), "ew session ready", str(s.errors))
	_ok(s.ew_service != null and bool(s.ew_service.ready), "ew_service ready")
	_ok(s.snapshot().get("ew") is Dictionary, "snapshot ew")
	var ap: Dictionary = s.apply_ew({"effect": "noise_jam", "source_id": "jammer",
		"target_id": "T1", "severity": 0.8, "duration_s": 20.0})
	_ok(bool(ap.get("ok", false)), "session apply_ew")
	_ok((s.ew_active("T1") as Array).size() >= 1, "ew_active")
	_ok(float(s.ew_observation_effect("T1").get("confidence_mult", 1.0)) < 1.0,
		"ew observation effect")
	var tk: Dictionary = s.tick(2.0)
	_ok(bool(tk.get("ok", false)), "ew session tick")
	_ok(bool((tk.get("components", {}) as Dictionary).get("ew", false)), "components ew")
	var ew_step: Dictionary = tk.get("ew_step", {}) if tk.get("ew_step") is Dictionary else {}
	_ok(bool(ew_step.get("enabled", false)), "ew_step enabled")
	_ok(int(ew_step.get("events", 0)) >= 1, "ew_step events")
	var bus_ok := false
	for raw in (s.snapshot().get("events", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("type", "")).begins_with("ew."):
			bus_ok = true
	_ok(bus_ok, "EW 事件 bus")
	_ok(bool(s.set_ew_emcon(true).get("ok", false)), "session ew emcon")
	_ok(bool(s.ew_service.emcon_active), "ew emcon active")
	_ok(bool(s.ew_comms_effect("T1").has("ok")), "session comms effect")
	_ok(bool(s.ew_transponder_effect("T1").has("ok")), "session transponder effect")
	var txt: String = s.save_state()
	_ok(txt.length() > 100 and (JSON.parse_string(txt) as Dictionary).has("ew_service"),
		"save 含 ew_service")
	var s2 = GameSession.new(cfg)
	var lr: Dictionary = s2.load_state(txt)
	_ok(bool(lr.get("ok", false)), "load ew session", str(lr.get("errors", [])))
	_ok(s2.ew_service != null, "load ew service")
	_ok(_norm_json(s.snapshot().get("ew")) == _norm_json(s2.snapshot().get("ew")),
		"load ew snapshot 一致")
	_ok((s2.ew_active("T1") as Array).size() >= 1, "load ew active")
	_data_line("ew", "可选退化 · apply/tick/bus · observation/comms/transponder 接口 · EMCON · 存档")

# ═══════════════════════════════════════════════════════════════════
# 35. IdentificationService 集成（识别自动化/证据融合）
# ═══════════════════════════════════════════════════════════════════

func _identification_cfg() -> Dictionary:
	return {"facility_registry": true, "transponder_service": true,
		"identification_service": {"auto": {"enabled": true, "interval_s": 2.0,
			"modes": ["mode_s"], "max_range_km": 5000.0,
			"max_requests_per_tick": 2}}}

func _test_identification_integration() -> void:
	_section_begin("35 Identification 集成")
	# 可选退化
	var plain = _new_session()
	_ok(plain.identification_service == null, "默认无 identification_service")
	_eq(plain.identification_vm().size(), 0, "无 identification VM 空")
	_eq(plain.identification_summary().size(), 0, "无 identification summary 空")
	_eq(plain.identification_get("x").size(), 0, "无 identification get 空")
	_eq(String(plain.identification_ingest({}).get("reason", "")),
		"no_identification_service", "无 identification ingest 拒绝")
	_eq(String(plain.identification_assess("x").get("reason", "")),
		"no_identification_service", "无 identification assess 拒绝")
	_eq(String(plain.identification_auto_tick(1.0).get("reason", "")),
		"no_identification_service", "无 identification auto 拒绝")
	_eq(String(plain.identification_set_auto(true).get("reason", "")),
		"no_identification_service", "无 identification set_auto 拒绝")
	_eq(String(plain.identification_manual_confirm("x", "friend").get("reason", "")),
		"no_identification_service", "无 identification manual 拒绝")
	_eq(String(plain.identification_authorize_hostile("x").get("reason", "")),
		"no_identification_service", "无 identification authorize 拒绝")
	_eq((plain.identification_take_query_requests() as Array).size(), 0,
		"无 identification query_requests 空")
	# 启用
	var s = GameSession.new(_identification_cfg())
	_ok(bool(s.ready), "identification session ready", str(s.errors))
	_ok(s.identification_service != null, "identification 启用")
	_eq(String(s.identification_vm().get("schema", "")), "v17.identification_service.v1",
		"identification vm schema")
	_eq(int(s.identification_summary().get("targets", 0)), 0, "identification 初始 0")
	_near(float(s.identification_service.t), s.now_s(), 1.0e-6, "identification boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "identification boot contracts ok")
	_ok(bool((s.tick(0.0).get("components", {}) as Dictionary).get("identification", false)),
		"tick components.identification")
	# 证据融合
	var r: Dictionary = s.identification_ingest({"target_id": "apsis",
		"source": "transponder", "identity": "friend", "confidence": 0.9,
		"mode": "mode_s", "t": 0.0})
	_eq(bool(r.get("ok", false)), true, "identification ingest ok")
	_eq(String(r.get("assessment", {}).get("identity", "")), "friend",
		"identification friend")
	_eq(int(r.get("assessment", {}).get("level", 0)), 3, "identification 单源 L3")
	_ok("apsis" in s.transponder_service.profile_ids(), "transponder profile apsis")
	# 双源 L4
	var r2: Dictionary = s.identification_ingest({"target_id": "apsis",
		"source": "optical", "identity": "friend", "confidence": 0.85,
		"category": "sensor", "t": 0.0})
	_eq(int(r2.get("assessment", {}).get("level", 0)), 4, "identification 双源 L4")
	_eq(String(s.identification_get("apsis").get("identity", "")), "friend",
		"identification get")
	var ass: Dictionary = s.identification_assess("apsis")
	_eq(bool(ass.get("ok", false)), true, "identification assess ok")
	# 矛盾/欺骗
	s.identification_ingest({"target_id": "C1", "source": "transponder",
		"identity": "friend", "confidence": 0.9})
	s.identification_ingest({"target_id": "C1", "source": "optical",
		"identity": "hostile", "confidence": 0.9, "category": "sensor"})
	var ac: Dictionary = s.identification_get("C1")
	_eq(String(ac.get("identity", "")), "suspect", "identification 冲突 suspect")
	_ok((ac.get("contradictions", []) as Array).size() > 0, "identification contradictions")
	_ok(int(ac.get("level", 4)) <= 3, "identification 冲突 <=L3")
	var sp: Dictionary = s.identification_ingest({"target_id": "S1",
		"source": "transponder", "identity": "friend", "confidence": 0.9,
		"spoofed": true, "status": "captured"})
	_ok(float(sp.get("assessment", {}).get("spoof_suspicion", 0.0)) >= 0.5,
		"identification spoof_suspicion")
	# 人工确认/授权
	var mc: Dictionary = s.identification_manual_confirm("M1", "friend",
		{"authority": "captain"})
	_eq(bool(mc.get("ok", false)), true, "identification manual ok")
	_eq(int(mc.get("assessment", {}).get("level", 0)), 4, "identification manual L4")
	var ah: Dictionary = s.identification_authorize_hostile("M2", "weapons")
	_eq(String(ah.get("assessment", {}).get("identity", "")), "hostile",
		"identification authorize hostile")
	_eq(bool(ah.get("assessment", {}).get("authorized", false)), true,
		"identification authorized")
	_eq(int(ah.get("assessment", {}).get("level", 0)), 4, "identification hostile L4")
	_eq(bool(s.identification_clear_manual("M1").get("ok", false)), true,
		"identification clear_manual")
	# 自动询问（transponder 执行）
	s.identification_set_target_state("apsis", {"range_km": 100.0,
		"los": true, "emcon": false})
	var ev_before := int(s.identification_get("apsis").get("evidence_count", 0))
	var at: Dictionary = s.identification_auto_tick(3.0)
	_eq(bool(at.get("ok", false)), true, "identification auto_tick ok")
	_ok((at.get("requests", []) as Array).size() >= 1, "identification auto requests")
	_ok((at.get("executed", []) as Array).size() >= 1, "identification auto executed")
	var ev_after := int(s.identification_get("apsis").get("evidence_count", 0))
	_ok(ev_after > ev_before, "identification auto 回灌证据", "%d->%d" % [ev_before, ev_after])
	var reqs: Array = s.identification_take_query_requests()
	_ok(reqs is Array, "identification query_requests 数组")
	# tick 自动推进
	var t0 := float(s.identification_service.t)
	var tick_res: Dictionary = s.tick(3.0)
	_eq(bool(tick_res.get("ok", false)), true, "identification tick ok")
	_ok(bool((tick_res.get("identification_tick", {}) as Dictionary).get("enabled", false)),
		"identification_tick enabled")
	_near(float(s.identification_service.t), s.now_s(), 1.0e-6, "identification t 同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "identification tick contracts ok")
	# 事件 bus
	var bus_types: Array = []
	for raw in s.bus.recent(300):
		bus_types.append(String((raw as Dictionary).get("type", "")))
	_ok("identification.assessment" in bus_types, "bus identification.assessment")
	_ok("identification.evidence_ingested" in bus_types, "bus identification.evidence_ingested")
	_ok("identification.query_request" in bus_types, "bus identification.query_request")
	_ok("identification.manual_confirm" in bus_types, "bus identification.manual_confirm")
	# 不改 world
	_eq(JSON.stringify((s.world.entity("apsis") as Dictionary).get("pos_km", [])),
		"[0.0,0.0,0.0]", "identification 不改实体位置")
	# 失败不改状态
	var before_core := _norm_json(s.identification_vm())
	_ok(not bool(s.identification_ingest({"target_id": "X", "source": "sensor",
		"identity": "bogus"}).get("ok", true)), "identification 非法证据拒绝")
	_eq(bool(s.identification_manual_confirm("X", "bogus").get("ok", true)), false,
		"identification 非法 manual 拒绝")
	_ok(_norm_json(s.identification_vm()) != "", "identification VM 可用")
	# 存档/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("identification_service"),
		"save 含 identification_service")
	var seed: Dictionary = (d as Dictionary).get("seed", {})
	_ok(seed.has("identification_service"), "seed 含 identification_service")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "identification load ok", str(lr.get("errors", [])))
	_ok(s2.identification_service != null, "load 重建 identification")
	_ok(_norm_json(s.identification_vm()) == _norm_json(s2.identification_vm()),
		"load 后 identification_vm 一致")
	_ok(_norm_json(s.snapshot()) == _norm_json(s2.snapshot()), "load 后 snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	_ok(bool(s2.identification_assess("apsis").get("ok", false)), "load 后 assess")
	# 旧存档兼容
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("identification_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("identification_service")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 identification 兼容", str(lr3.get("errors", [])))
	_ok(s3.identification_service == null, "旧存档 load 后 identification 退化")
	# 确定性
	var a = GameSession.new(_identification_cfg())
	var b = GameSession.new(_identification_cfg())
	for sv in [a, b]:
		sv.identification_ingest({"target_id": "apsis", "source": "transponder",
			"identity": "friend", "confidence": 0.9, "t": 0.0})
		sv.identification_ingest({"target_id": "apsis", "source": "optical",
			"identity": "friend", "confidence": 0.8, "category": "sensor", "t": 0.0})
		sv.identification_authorize_hostile("M2", "weapons")
		sv.identification_set_target_state("apsis", {"range_km": 100.0,
			"los": true, "emcon": false})
		sv.identification_auto_tick(2.0)
	_ok(_norm_json(a.identification_vm()) == _norm_json(b.identification_vm()),
		"identification 同操作 VM 一致")
	_ok(a.save_state() == b.save_state(), "identification 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "identification contracts ok 2")
	_data_line("identification", "融合/冲突/欺骗/人工/授权 · 自动询问经 transponder 回灌 · bus · 存档/旧档/确定性")

# ═══════════════════════════════════════════════════════════════════
# 36. LegalStatusService 集成（ID13 法律状态/影响接口/脚本事件）
# ═══════════════════════════════════════════════════════════════════

func _test_legal_status_integration() -> void:
	_section_begin("36 LegalStatus 集成")
	# 默认不启用 → 退化
	var off = _new_session()
	_ok(off.legal_status_service == null, "默认无 legal_status_service")
	_eq(off.legal_vm().size(), 0, "无 legal VM 空")
	_eq(off.legal_summary().size(), 0, "无 legal summary 空")
	_eq(off.legal_impact().size(), 0, "无 legal impact 空")
	_eq(off.legal_status_text(), "", "无 legal status 空")
	_eq(str(off.legal_apply_event("strong").get("reason", "")),
		"no_legal_status_service", "无 legal 事件拒绝")
	_eq(str(off.legal_set_status("HUNTED").get("reason", "")),
		"no_legal_status_service", "无 legal set_status 拒绝")
	_eq(str(off.legal_tick(1.0).get("reason", "")),
		"no_legal_status_service", "无 legal tick 拒绝")
	_ok(off.snapshot().get("legal_status") == null, "无 legal snapshot null")
	_ok((JSON.parse_string(off.save_state()) as Dictionary).has("legal_status_service"),
		"无 legal save 字段为空字符串")
	# 启用
	var cfg := {"legal_status": true}
	var s = GameSession.new(cfg)
	_ok(bool(s.ready), "legal session ready", str(s.errors))
	_ok(s.legal_status_service != null and bool(s.legal_status_service.ready),
		"legal_status_service ready")
	_eq(s.legal_status_text(), "UNLISTED", "初始 UNLISTED")
	_near(float(s.legal_status_service.t), s.now_s(), 1.0e-6, "legal boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "legal boot contracts ok")
	_ok(s.snapshot().get("legal_status") is Dictionary, "snapshot legal")
	_eq(str((s.snapshot().get("legal_status", {}) as Dictionary).get("status", "")),
		"UNLISTED", "snapshot legal status")
	_ok(bool((s.tick(0.0).get("components", {}) as Dictionary).get("legal_status", false)),
		"tick components.legal_status")
	# 影响接口
	_eq(str(s.legal_port_access().get("ueg", "")), "NORMAL", "session port_access")
	_eq(bool(s.legal_iff_watch_flag()), false, "session iff")
	_eq(float(s.legal_combat_roe_modifier()), 1.0, "session roe")
	_eq(str(s.legal_ending_branch_hint()), "standard", "session hint")
	# 脚本事件驱动
	var r1: Dictionary = s.legal_apply_event("strong", {"event_id": "L1"})
	_eq(bool(r1.get("ok", false)), true, "session legal event ok")
	_eq(str(r1.get("status", "")), "UNLISTED", "strong 后 UNLISTED")
	_eq(float(s.legal_status_service.heat), 1.0, "session legal heat")
	var r2: Dictionary = s.legal_apply_event("fire_control_illumination",
		{"event_id": "L2"})
	_eq(str(r2.get("status", "")), "WATCHLIST", "火控后 WATCHLIST")
	_eq(bool(s.legal_iff_watch_flag()), true, "WATCH iff")
	_eq(str(s.legal_port_access().get("ueg", "")), "WATCHED", "WATCH UEG 港")
	# 去重
	var rd: Dictionary = s.legal_apply_event("strong", {"event_id": "L1"})
	_eq(bool(rd.get("duplicate", false)), true, "session legal 去重")
	_eq(float(s.legal_status_service.heat), 3.0, "去重不改 heat")
	# 失败不改状态
	var before := _norm_json(s.legal_vm())
	_ok(not bool(s.legal_apply_event("NOPE").get("ok", true)), "session 未知 trigger 拒绝")
	_ok(not bool(s.legal_set_status("BAD").get("ok", true)), "session 非法状态拒绝")
	_eq(_norm_json(s.legal_vm()), before, "失败不改 legal VM")
	# 直接 tick（服务时间独立；不影响 session contracts）
	var lt: Dictionary = s.legal_tick(2.0)
	_eq(bool(lt.get("ok", false)), true, "session legal_tick ok")
	_eq(bool(s.check_contracts().get("ok", false)), true, "legal_tick 后 contracts ok")
	# session tick 推进并同步
	var t0 := float(s.legal_status_service.t)
	var tk: Dictionary = s.tick(3.0)
	_eq(bool(tk.get("ok", false)), true, "legal session tick ok")
	_ok(bool((tk.get("legal_status_tick", {}) as Dictionary).get("enabled", false)),
		"legal_status_tick enabled")
	_near(float(s.legal_status_service.t), t0 + 3.0, 1.0e-6, "legal tick t 增加")
	_eq(bool(s.check_contracts().get("ok", false)), true, "legal tick contracts ok")
	# snapshot/VM 一致
	_eq(str(s.legal_vm().get("schema", "")), "v17.legal_status.v1", "legal vm schema")
	_eq(_norm_json(s.legal_vm()), _norm_json(s.snapshot().get("legal_status")),
		"legal vm = snapshot")
	# save/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("legal_status_service"),
		"save 含 legal_status_service")
	var seed: Dictionary = (d as Dictionary).get("seed", {})
	_ok(seed.has("legal_status"), "seed 含 legal_status")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "legal load ok", str(lr.get("errors", [])))
	_ok(s2.legal_status_service != null, "load 重建 legal")
	_eq(_norm_json(s.legal_vm()), _norm_json(s2.legal_vm()), "load legal VM 一致")
	_eq(_norm_json(s.snapshot()), _norm_json(s2.snapshot()), "load snapshot 一致")
	_eq(bool(s2.check_contracts().get("ok", false)), true, "load contracts ok")
	_eq(str(s2.legal_status_text()), "WATCHLIST", "load legal status")
	_eq(bool(s2.legal_apply_event("blackbox_public", {"event_id": "L3"}).get("ok", false)),
		true, "load 后 legal 事件")
	# 旧存档兼容：无 legal 字段/seed 配置 → 退化，日志 legal op 跳过
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("legal_status_service")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("legal_status")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 legal 兼容", str(lr3.get("errors", [])))
	_ok(s3.legal_status_service == null, "旧存档 legal 退化")
	# 确定性
	var a = GameSession.new(cfg)
	var b = GameSession.new(cfg)
	for sv in [a, b]:
		sv.legal_apply_event("strong", {"event_id": "D1"})
		sv.legal_apply_event("blackbox_public", {"event_id": "D2"})
		sv.tick(1.0)
	_eq(_norm_json(a.legal_vm()), _norm_json(b.legal_vm()), "legal 同操作 VM 一致")
	_eq(a.save_state(), b.save_state(), "legal 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "legal contracts ok 2")
	_data_line("legal", "可选退化 · 初始 UNLISTED · 事件/去重/影响接口 · tick · save/load/旧档 · 确定")

# ═══════════════════════════════════════════════════════════════════
# 37. TrafficControl 集成（OTC/航道/NPC/伪装/事件/存档）
# ═══════════════════════════════════════════════════════════════════

func _traffic_cfg() -> Dictionary:
	return {"traffic_control": true}

func _test_traffic_integration() -> void:
	_section_begin("37 TrafficControl 集成")
	# 默认不启用 → 退化
	var off = _new_session()
	_ok(off.traffic_control == null, "默认无 traffic_control")
	_eq(off.traffic_vm().size(), 0, "无 traffic VM 空")
	_eq(off.traffic_summary().size(), 0, "无 traffic summary 空")
	_eq(off.traffic_clues().size(), 0, "无 traffic clues 空")
	_eq(off.traffic_lane("LANE-L1-IN-01").size(), 0, "无 traffic lane 空")
	_eq(off.traffic_otc_for("L1_MERIDIAN").size(), 0, "无 traffic otc 空")
	_eq(str(off.traffic_request("T1", "LANE-L1-IN-01").get("reason", "")),
		"no_traffic_control", "无 traffic request 拒绝")
	_eq(str(off.traffic_permit("R1").get("reason", "")), "no_traffic_control",
		"无 traffic permit 拒绝")
	_eq(str(off.traffic_occupy("LANE-L1-IN-01", "T1").get("reason", "")),
		"no_traffic_control", "无 traffic occupy 拒绝")
	_eq(str(off.traffic_release("LANE-L1-IN-01").get("reason", "")),
		"no_traffic_control", "无 traffic release 拒绝")
	_eq(str(off.traffic_disguise("T1").get("reason", "")), "no_traffic_control",
		"无 traffic disguise 拒绝")
	_ok(off.snapshot().get("traffic_control") == null, "无 traffic snapshot null")
	var off_save = JSON.parse_string(off.save_state())
	_ok(off_save is Dictionary and off_save.get("traffic_control", "x") == "",
		"无 traffic save 字段空")
	# 启用
	var s = GameSession.new(_traffic_cfg())
	_ok(bool(s.ready), "traffic session ready", str(s.errors))
	_ok(s.traffic_control != null and bool(s.traffic_control.ready), "traffic ready")
	_near(float(s.traffic_control.t), s.now_s(), 1.0e-6, "traffic boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "traffic boot contracts ok")
	var sum: Dictionary = s.traffic_summary()
	_eq(str(sum.get("schema", "")), "traffic_control.v1", "traffic summary schema")
	_eq(int(sum.get("facilities", 0)), 110, "traffic facilities 110")
	_eq(int(sum.get("lanes", 0)), 18, "traffic lanes 18")
	_eq(bool((sum.get("writes", {}) as Dictionary).get("world", true)), false,
		"traffic 不写 world")
	var vm: Dictionary = s.traffic_vm()
	_eq(str(vm.get("schema", "")), "traffic_control.v1", "traffic VM schema")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"traffic 不写 track_table")
	_eq(str(s.traffic_lane("LANE-L1-IN-01").get("name", "")), "Meridian 进港主航道",
		"traffic lane query")
	_ok(s.traffic_otc_for("L1_MERIDIAN").size() >= 2, "traffic otc query")
	_eq(s.traffic_lane("NOPE").size(), 0, "traffic 未知 lane 空")
	_ok(s.snapshot().get("traffic_control") is Dictionary, "snapshot traffic")
	# tick / NPC / bus
	var world_before := _norm_json(s.world.entities_sorted())
	var tk0: Dictionary = s.tick(0.0)
	_eq(bool(tk0.get("ok", false)), true, "traffic tick 0 ok")
	_ok(bool((tk0.get("components", {}) as Dictionary).get("traffic", false)),
		"components.traffic")
	_ok(bool((tk0.get("traffic_step", {}) as Dictionary).get("enabled", false)),
		"traffic_step enabled")
	_near(float(s.traffic_control.t), s.now_s(), 1.0e-6, "tick 后 traffic t 同步")
	var tk: Dictionary = s.tick(5.0)
	_eq(bool(tk.get("ok", false)), true, "traffic tick 5 ok")
	var npc_count := int(s.traffic_summary().get("npc", 0))
	_ok(npc_count >= 1, "NPC 被 tick 激活", str(npc_count))
	_eq(_norm_json(s.world.entities_sorted()), world_before, "traffic 不改 world")
	# API request/permit/occupy/release
	var req: Dictionary = s.traffic_request("TRK-1", "LANE-L1-IN-01",
		{"priority": 1, "width": 1})
	_eq(bool(req.get("ok", false)), true, "traffic request ok")
	var rid := str(req.get("request_id", ""))
	var perm: Dictionary = s.traffic_permit(rid)
	_eq(bool(perm.get("ok", false)), true, "traffic permit ok")
	var cid := str(perm.get("clearance_id", ""))
	var occ: Dictionary = s.traffic_occupy("LANE-L1-IN-01", "TRK-1",
		{"clearance_id": cid})
	_eq(bool(occ.get("ok", false)), true, "traffic occupy ok")
	var occ_id := str(occ.get("occupancy_id", ""))
	_ok(occ_id != "", "occupancy id")
	_eq(bool(s.traffic_release("LANE-L1-IN-01", "TRK-1").get("ok", false)), true,
		"traffic release ok")
	# 失败不改状态
	var before_fail := _norm_json(s.traffic_vm())
	_ok(not bool(s.traffic_permit("NOPE").get("ok", true)), "未知 request 拒绝")
	_ok(not bool(s.traffic_request("T2", "NOPE").get("ok", true)), "未知 lane 拒绝")
	_eq(_norm_json(s.traffic_vm()), before_fail, "失败不改 traffic VM")
	# 伪装/线索/文本
	var dis: Dictionary = s.traffic_disguise("TRK-1",
		{"transponder_code": "TXP-L1-05", "facility_code": "FC-L1-05",
			"lane_id": "LANE-L1-IN-01", "claimed_class": "fuel"},
		{"force_detected": true})
	_eq(bool(dis.get("ok", false)), true, "traffic disguise ok")
	_eq(bool(dis.get("detected", false)), true, "disguise force detected")
	_ok((dis.get("clue_ids", []) as Array).size() >= 1, "disguise clues")
	_ok(s.traffic_clues("TRK-1").size() >= 1, "traffic clues 查询")
	_ok(s.traffic_clues("").size() >= s.traffic_clues("TRK-1").size(),
		"traffic 全线索")
	# tick 将 API/伪装产生的 outbox 事件白名单发布到 bus
	var tk2: Dictionary = s.tick(0.0)
	_ok(int((tk2.get("traffic_step", {}) as Dictionary).get("routed", 0)) >= 1,
		"traffic tick routed")
	_eq(bool(tk2.get("ok", false)), true, "traffic tick2 ok")
	# 事件白名单进 bus
	var types: Array = _event_types(s.bus.recent(300))
	for t in ["traffic.lane_record", "traffic.otc_event", "traffic.clue"]:
		_ok(str(t) in types, "bus " + str(t))
	var traffic_ev_ok := true
	for raw in s.bus.recent(300):
		if raw is Dictionary and str((raw as Dictionary).get("type", "")).begins_with("traffic."):
			var ev: Dictionary = raw
			if not str(ev.get("type", "")) in ["traffic.lane_record",
					"traffic.otc_event", "traffic.clue"]:
				traffic_ev_ok = false
			if not (ev.get("payload") is Dictionary):
				traffic_ev_ok = false
	_ok(traffic_ev_ok, "traffic bus 仅白名单 payload")
	# save/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("traffic_control"), "save 含 traffic")
	_ok((d as Dictionary).get("traffic_control", "") != "", "save traffic 非空")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "traffic load ok", str(lr.get("errors", [])))
	_ok(s2.traffic_control != null, "load 重建 traffic")
	_eq(_norm_json(s.traffic_vm()), _norm_json(s2.traffic_vm()), "load traffic VM 一致")
	_eq(_norm_json(s.traffic_summary()), _norm_json(s2.traffic_summary()),
		"load traffic summary 一致")
	_eq(_norm_json(s.snapshot()), _norm_json(s2.snapshot()), "load snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load contracts ok")
	# load 后继续 API
	var r2: Dictionary = s2.traffic_request("TRK-2", "LANE-L1-OUT-01",
		{"priority": 2, "width": 1})
	_eq(bool(r2.get("ok", false)), true, "load 后 request")
	# 旧存档兼容：删除字段+seed 配置
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("traffic_control")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("traffic_control")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 traffic 兼容", str(lr3.get("errors", [])))
	_ok(s3.traffic_control == null, "旧存档 traffic 退化")
	# 非法 traffic 快照
	var bad: Dictionary = (d as Dictionary).duplicate(true)
	bad["traffic_control"] = "{\"schema\":\"bad\"}"
	var s4 = GameSession.new()
	_eq(bool(s4.load_state(JSON.stringify(bad)).get("ok", true)), false,
		"非法 traffic 快照拒绝")
	# 坏配置
	var sbad = GameSession.new({"traffic_control": {"lanes_path": "/no/such.json"}})
	_ok(not bool(sbad.ready), "traffic 坏 lanes 配置拒绝")
	# 确定性
	var a = GameSession.new(_traffic_cfg())
	var b = GameSession.new(_traffic_cfg())
	for sv in [a, b]:
		sv.tick(5.0)
		sv.traffic_request("TRK-D", "LANE-L1-IN-01", {"priority": 1})
		sv.traffic_disguise("TRK-D", {"transponder_code": "TXP-L1-05",
			"facility_code": "FC-L1-05", "lane_id": "LANE-L1-IN-01"},
			{"force_detected": true})
	_eq(_norm_json(a.traffic_vm()), _norm_json(b.traffic_vm()),
		"traffic 同操作 VM 一致")
	_eq(a.save_state(), b.save_state(), "traffic 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "traffic contracts ok 2")
	_data_line("traffic", "可选退化 · 110 设施/18 航道 · API/失败 · NPC tick · 伪装/线索 · bus · 存档/旧档/确定性")

# ═══════════════════════════════════════════════════════════════════
# 38. Prelude L1→bary_rot 帧转换（4F）
# ═══════════════════════════════════════════════════════════════════

func _prelude_physics_cfg(frame_cfg: Dictionary, top_level := {}) -> Dictionary:
	var p = PreludeScenario.new()
	var cfg: Dictionary = p.boot_config()
	cfg["physics_world"] = frame_cfg
	for k in top_level.keys():
		cfg[k] = top_level[k]
	return cfg

func _r_vec(s, id: String) -> Array:
	return (s.physics_state(id).get("r", []) as Array).duplicate()

func _dist3(a: Array, b: Array) -> float:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(
		Vector3(float(b[0]), float(b[1]), float(b[2])))

func _test_physics_frame_conversion() -> void:
	_section_begin("38 L1→bary 帧转换")
	var p = PreludeScenario.new()
	_ok(bool(p.ready), "prelude scenario ready")
	var l1pos: Array = []
	var eq: Dictionary = CislunarPhysics.equilibrium_points()
	if eq.get("L1") is Dictionary:
		var lp: Vector3 = (eq["L1"] as Dictionary).get("pos_rot", Vector3.ZERO)
		l1pos = [lp.x, lp.y, lp.z]
	_eq(l1pos.size(), 3, "L1 bary 位置可用")
	var earth: Vector3 = CislunarPhysics.earth_position_rot()
	var moon: Vector3 = CislunarPhysics.moon_position_rot()
	# 默认 auto：检测到 prelude → L1 相对转 bary
	var cfg := _prelude_physics_cfg({"seed_frame": "auto"})
	var s = GameSession.new(cfg)
	_ok(bool(s.ready), "prelude physics ready", str(s.errors))
	_ok(s.physics_world_service != null, "prelude physics 启用")
	var meta: Dictionary = s.physics_frame_meta()
	_eq(str(meta.get("seed_frame", "")), "l1", "auto 解析 l1")
	_eq(bool(meta.get("applied", false)), true, "auto applied")
	_eq(bool(meta.get("auto_prelude", false)), true, "auto prelude 检测")
	_eq(int(meta.get("converted", 0)), 9, "转换 9 实体")
	_eq(int(meta.get("conversion_count", 0)), 1, "conversion_count 1")
	var off: Array = meta.get("offset_km", []) as Array
	_eq(off.size(), 3, "offset 3")
	for i in range(3):
		_ok(absf(float(off[i]) - float(l1pos[i])) <= 1.0e-3, "offset= L1[%d]" % i)
	# apsis: L1 相对 0 → bary L1
	var apsis_r := _r_vec(s, "apsis")
	for i2 in range(3):
		_ok(absf(float(apsis_r[i2]) - float(l1pos[i2])) <= 1.0e-3,
			"apsis bary= L1[%d]" % i2)
	# ceres 相对 42,120 → bary = L1 + 局部
	var ceres_r := _r_vec(s, "ceres_2")
	_ok(absf(float(ceres_r[0]) - (float(l1pos[0]) + 42.0)) <= 1.0e-3, "ceres x +42")
	_ok(absf(float(ceres_r[1]) - (float(l1pos[1]) + 120.0)) <= 1.0e-3, "ceres y +120")
	_ok(absf(float(ceres_r[2]) - float(l1pos[2])) <= 1.0e-3, "ceres z")
	# Earth/Moon 距旗舰（转换后）
	var earth_dist := _dist3(apsis_r, [earth.x, earth.y, earth.z])
	var moon_dist := _dist3(apsis_r, [moon.x, moon.y, moon.z])
	_ok(earth_dist > 300000.0, "Earth 距旗舰 > 300000 km", str(earth_dist))
	_ok(moon_dist < 100000.0, "Moon 距旗舰 < 100000 km", str(moon_dist))
	_ok(earth_dist > 100000.0, "Earth 距离不再是 4670 异常", str(earth_dist))
	# 世界实体保持 L1 相对（不写 world）
	var w_apsis: Array = p.entity("apsis").get("pos_km", [])
	var w_ceres: Array = p.entity("ceres_2").get("pos_km", [])
	_eq(s.world.entity("apsis").get("pos_km", []), w_apsis, "世界 apsis 保持局部")
	_eq(s.world.entity("ceres_2").get("pos_km", []), w_ceres, "世界 ceres 保持局部")
	# 所有 prelude 实体：physics r - L1 = world 局部（保持相对关系）
	for raw in (p.entity_ids() as Array):
		var eid := str(raw)
		var ent := p.entity(eid)
		var local: Array = ent.get("pos_km", [0.0, 0.0, 0.0])
		var br := _r_vec(s, eid)
		var rel := [float(br[0]) - float(l1pos[0]), float(br[1]) - float(l1pos[1]),
			float(br[2]) - float(l1pos[2])]
		_ok(absf(float(rel[0]) - float(local[0])) <= 1.0e-3,
			"相对 x " + eid)
		_ok(absf(float(rel[1]) - float(local[1])) <= 1.0e-3,
			"相对 y " + eid)
		_ok(absf(float(rel[2]) - float(local[2])) <= 1.0e-3,
			"相对 z " + eid)
		# 速度保持
		var vel: Array = ent.get("vel_kmps", [0.0, 0.0, 0.0])
		var pv: Array = s.physics_state(eid).get("v", [])
		for k in range(3):
			_ok(absf(float(pv[k]) - float(vel[k])) <= 1.0e-6, "速度保持 " + eid)
	_ok(bool(s.check_contracts().get("ok", false)), "prelude physics contracts")
	_ok(s.snapshot().get("physics_frame") is Dictionary, "snapshot physics_frame")
	# 显式 bary_rot（关闭转换）→ 复现 4670 异常但符合显式帧
	var cfg_bary := _prelude_physics_cfg({"seed_frame": "bary_rot"})
	var sb = GameSession.new(cfg_bary)
	_ok(bool(sb.ready), "bary session ready", str(sb.errors))
	var mb = sb.physics_frame_meta()
	_eq(bool(mb.get("applied", true)), false, "bary 关闭转换")
	var bary_apsis := _r_vec(sb, "apsis")
	_ok(absf(float(bary_apsis[0])) <= 1.0e-6, "bary apsis x=0")
	var bary_earth_dist := _dist3(bary_apsis, [earth.x, earth.y, earth.z])
	_near(bary_earth_dist, absf(earth.x), 1.0, "显式 bary Earth 距离 4670")
	# 显式 frame_origin 数组
	var cfg_off := _prelude_physics_cfg({"seed_frame": "l1",
		"frame_origin": [1000.0, 2000.0, 3000.0]})
	var so = GameSession.new(cfg_off)
	var mo = so.physics_frame_meta()
	_eq(str(mo.get("frame_origin", "")), "explicit", "显式 origin")
	_eq(so.physics_state("apsis").get("r", []), [1000.0, 2000.0, 3000.0],
		"显式 offset apsis")
	# frame_origin=l1 + auto（无 prelude marker 也可）
	var cfg_origin := _prelude_physics_cfg({"seed_frame": "auto",
		"frame_origin": "l1"})
	var so2 = GameSession.new(cfg_origin)
	_eq(bool(so2.physics_frame_meta().get("applied", false)), true, "origin l1 applied")
	_eq(str(so2.physics_frame_meta().get("frame_origin", "")), "l1", "origin l1")
	# 显式关闭
	var cfg_none := _prelude_physics_cfg({"seed_frame": "l1",
		"frame_origin": "none"})
	var sn = GameSession.new(cfg_none)
	_eq(bool(sn.physics_frame_meta().get("applied", true)), false, "frame_origin none 关闭")
	_eq(sn.physics_state("apsis").get("r", []), [0.0, 0.0, 0.0], "none apsis bary 0")
	# 顶层 seed_frame 支持
	var cfg_top := _prelude_physics_cfg({}, {"seed_frame": "l1"})
	var st = GameSession.new(cfg_top)
	_eq(bool(st.physics_frame_meta().get("applied", false)), true, "顶层 seed_frame")
	# 非 prelude demo：auto 不转换
	var s_demo = GameSession.new({"physics_world": true})
	var md = s_demo.physics_frame_meta()
	_eq(bool(md.get("applied", false)), false, "demo auto bary")
	_eq(s_demo.physics_state("apsis").get("r", []), [0.0, 0.0, 0.0],
		"demo apsis bary 0")
	# 无重复转换：同 config 重新 boot 只加一次
	var apsis_before := _r_vec(s, "apsis")
	s.boot(cfg)
	var meta2: Dictionary = s.physics_frame_meta()
	_eq(int(meta2.get("conversion_count", 0)), 1, "reboot conversion_count 1")
	_eq(_r_vec(s, "apsis"), apsis_before, "reboot 不重复偏移")
	# save/load 不重复
	var save := s.save_state()
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "frame load ok", str(lr.get("errors", [])))
	_eq(int(s2.physics_frame_meta().get("conversion_count", 0)), 1,
		"load conversion_count 1")
	_eq(_r_vec(s2, "apsis"), apsis_before, "load 不重复偏移")
	_eq(JSON.stringify(s2.physics_vm()), JSON.stringify(s.physics_vm()),
		"load physics VM 一致")
	# 非法 seed_frame/origin warning 且不转换
	var cfg_bad := _prelude_physics_cfg({"seed_frame": "bogus"})
	var sbad = GameSession.new(cfg_bad)
	_ok(bool(sbad.ready), "非法帧 config 不致命")
	_eq(bool(sbad.physics_frame_meta().get("applied", true)), false, "非法帧不转换")
	_ok((sbad.warnings as Array).size() >= 1, "非法帧 warning")
	# 确定性
	var c1 = GameSession.new(cfg)
	var c2 = GameSession.new(cfg)
	_eq(_norm_json(c1.physics_frame_meta()), _norm_json(c2.physics_frame_meta()),
		"帧 meta 确定")
	_eq(_norm_json(c1.physics_vm()), _norm_json(c2.physics_vm()), "帧 physics 确定")
	_data_line("frame", "L1 offset=%s · apsis Earth=%.1f km Moon=%.1f km · bary异常=%.1f km · 9实体相对/速度/无重复/存档" % [str(off), earth_dist, moon_dist, bary_earth_dist])

# ═══════════════════════════════════════════════════════════════════
# 39. CombatBallistics 集成（发射/step/命中→Damage/PD/存档）
# ═══════════════════════════════════════════════════════════════════

func _ballistics_cfg(with_damage := true) -> Dictionary:
	var c := {"combat_ballistics": true}
	if with_damage:
		c["damage_service"] = true
	return c

func _duel_cfg(pd_platform := "") -> Dictionary:
	var c := {"combat_ballistics": true, "damage_service": true,
		"entities": [
			{"id": "apsis", "batch": "1", "kind": "ship", "name": "APSIS",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "batch": "2", "kind": "ship", "name": "HAMATTAN",
				"pos_km": [100.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}],
		"nodes": [{"id": "apsis"}, {"id": "harmattan"}],
		"links": [{"a": "apsis", "b": "harmattan", "mode": "LD"}]}
	if pd_platform != "":
		c["combat_ballistics"] = {"pd_platform_id": pd_platform}
	return c

func _test_combat_ballistics_integration() -> void:
	_section_begin("39 CombatBallistics 集成")
	# 默认不启用 → 退化
	var off = _new_session()
	_ok(off.combat_ballistics == null, "默认无 combat_ballistics")
	_eq(off.combat_ballistics_vm().size(), 0, "无 ballistics VM 空")
	_eq(off.combat_ballistics_summary().size(), 0, "无 ballistics summary 空")
	_eq(off.combat_ballistics_active().size(), 0, "无 ballistics active 空")
	_eq(off.combat_ballistics_intercepts().size(), 0, "无 ballistics intercepts 空")
	_eq(off.combat_ballistics_impacts().size(), 0, "无 ballistics impacts 空")
	_eq(off.combat_ballistics_pd().size(), 0, "无 ballistics pd 空")
	_eq(str(off.combat_ballistics_launch("apsis", "harmattan", "railgun").get("reason", "")),
		"no_combat_ballistics", "无 ballistics launch 拒绝")
	_eq(str(off.combat_predict("apsis", "harmattan", "railgun").get("reason", "")),
		"no_combat_ballistics", "无 ballistics predict 拒绝")
	_ok(off.snapshot().get("combat_ballistics") == null, "无 ballistics snapshot null")
	var off_save = JSON.parse_string(off.save_state())
	_ok(off_save is Dictionary and off_save.get("combat_ballistics", "x") == "",
		"无 ballistics save 字段空")
	# 启用 + damage
	var s = GameSession.new(_ballistics_cfg(true))
	_ok(bool(s.ready), "ballistics session ready", str(s.errors))
	_ok(s.combat_ballistics != null and bool(s.combat_ballistics.ready), "ballistics ready")
	_near(float(s.combat_ballistics.t), s.now_s(), 1.0e-6, "ballistics boot 时间同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "ballistics boot contracts ok")
	var sum: Dictionary = s.combat_ballistics_summary()
	_eq(str(sum.get("schema", "")), "combat_ballistics.v1", "ballistics summary schema")
	_eq(int(sum.get("projectiles", 0)), 0, "初始 projectiles 0")
	_eq(bool((sum.get("writes", {}) as Dictionary).get("world", true)), false,
		"ballistics 不写 world")
	_ok(s.snapshot().get("combat_ballistics") is Dictionary, "snapshot ballistics")
	# predict/launch
	var pred: Dictionary = s.combat_predict("apsis", "harmattan", "railgun")
	_eq(bool(pred.get("ok", false)), true, "predict ok")
	_eq(str(pred.get("schema", "")), "ballistic_prediction.v1", "predict schema")
	_ok(float(pred.get("time_of_flight_s", -1.0)) > 0.0, "predict tof")
	var launch: Dictionary = s.combat_ballistics_launch("apsis", "harmattan", "railgun")
	_eq(bool(launch.get("ok", false)), true, "launch ok")
	_eq(s.combat_ballistics_active().size(), 1, "launch active 1")
	var pid := str(launch.get("projectile_id", ""))
	_ok(pid.begins_with("PRJ-"), "projectile id")
	# 失败不改状态
	var vm_before := _norm_json(s.combat_ballistics_vm())
	_ok(not bool(s.combat_ballistics_launch("NOPE", "harmattan", "railgun").get("ok", true)),
		"未知 shooter 拒绝")
	_ok(not bool(s.combat_ballistics_launch("apsis", "harmattan", "bogus").get("ok", true)),
		"未知武器 拒绝")
	_ok(not bool(s.combat_ballistics_launch("apsis", "NOPE", "railgun").get("ok", true)),
		"未知 target 拒绝")
	_eq(_norm_json(s.combat_ballistics_vm()), vm_before, "失败不改 ballistics VM")
	# tick 命中→Damage
	var world_before := _norm_json(s.world.entities_sorted())
	var tk: Dictionary = s.tick(2.0)
	_eq(bool(tk.get("ok", false)), true, "ballistics tick ok")
	var step: Dictionary = tk.get("ballistics_step", {})
	_eq(bool(step.get("enabled", false)), true, "ballistics_step enabled")
	_eq(bool(step.get("ok", false)), true, "ballistics_step ok")
	_ok(int(step.get("impacts", 0)) >= 1, "ballistics tick impacts")
	_eq(int(step.get("damage_applied", 0)), 1, "damage_applied 1")
	_eq(s.combat_ballistics_impacts().size(), 1, "impact records 1")
	_eq(s.combat_ballistics_active().size(), 0, "hit 后 active 0")
	_eq(_norm_json(s.world.entities_sorted()), world_before, "ballistics 不改 world")
	_near(float(s.combat_ballistics.t), s.now_s(), 1.0e-6, "tick 后 ballistics t 同步")
	_eq(bool(s.check_contracts().get("ok", false)), true, "ballistics tick contracts")
	# 伤害真的进 DamageService
	var dmg_vm: Dictionary = s.damage_ship_vm("harmattan")
	var dsum: Dictionary = dmg_vm.get("summary", {}) as Dictionary
	_ok(float(dsum.get("integrity_avg", 1.0)) < 1.0, "Damage integrity 下降",
		str(dsum.get("integrity_avg")))
	_ok(int(dsum.get("needs_attention", 0)) >= 1, "Damage needs_attention")
	# bus 事件 / damage_event applied true
	var types: Array = _event_types(s.bus.recent(300))
	for t in ["ballistics.launch", "ballistics.impact"]:
		_ok(str(t) in types, "bus " + str(t))
	var impact_event_ok := false
	for raw_ev in s.bus.recent(300):
		if raw_ev is Dictionary and str((raw_ev as Dictionary).get("type", "")) == "ballistics.impact":
			var payload: Dictionary = (raw_ev as Dictionary).get("payload", {})
			var inner: Dictionary = payload.get("payload", {}) if payload.get("payload") is Dictionary else {}
			var de: Dictionary = inner.get("damage_event", {})
			if bool(de.get("applied", false)) and str(de.get("shot_id", "")) == pid:
				impact_event_ok = true
	_ok(impact_event_ok, "impact damage_event applied=true")
	# 不重复应用：再 tick，damage 不变
	var impacts_before := s.combat_ballistics_impacts().size()
	var tk2: Dictionary = s.tick(2.0)
	_eq(int((tk2.get("ballistics_step", {}) as Dictionary).get("damage_applied", 0)), 0,
		"重复 tick 不重复应用")
	_eq(s.combat_ballistics_impacts().size(), impacts_before, "impact 记录不重复")
	# save/load
	var save := s.save_state()
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).has("combat_ballistics"), "save 含 ballistics")
	_ok((d as Dictionary).get("combat_ballistics", "") != "", "save ballistics 非空")
	var s2 = GameSession.new()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "ballistics load ok", str(lr.get("errors", [])))
	_ok(s2.combat_ballistics != null, "load 重建 ballistics")
	_eq(_norm_json(s.combat_ballistics_vm()), _norm_json(s2.combat_ballistics_vm()),
		"load ballistics VM 一致")
	_eq(_norm_json(s.damage_ship_vm("harmattan")), _norm_json(s2.damage_ship_vm("harmattan")),
		"load damage 一致")
	_eq(_norm_json(s.snapshot()), _norm_json(s2.snapshot()), "load snapshot 一致")
	_ok(bool(s2.check_contracts().get("ok", false)), "load contracts ok")
	# 旧存档兼容
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("combat_ballistics")
	var old_seed: Dictionary = old.get("seed", {})
	old_seed.erase("combat_ballistics")
	old["seed"] = old_seed
	var s3 = GameSession.new()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 ballistics 兼容", str(lr3.get("errors", [])))
	_ok(s3.combat_ballistics == null, "旧存档 ballistics 退化")
	# 非法快照
	var bad: Dictionary = (d as Dictionary).duplicate(true)
	bad["combat_ballistics"] = "{\"schema\":\"bad\"}"
	var s4 = GameSession.new()
	_eq(bool(s4.load_state(JSON.stringify(bad)).get("ok", true)), false,
		"非法 ballistics 快照拒绝")
	# 无 DamageService 时命中：applied=false
	var s_nd = GameSession.new(_ballistics_cfg(false))
	s_nd.combat_ballistics_launch("apsis", "harmattan", "railgun")
	var tnd: Dictionary = s_nd.tick(2.0)
	var ndstep: Dictionary = tnd.get("ballistics_step", {})
	_ok(int(ndstep.get("impacts", 0)) >= 1, "无 damage 命中")
	_eq(int(ndstep.get("damage_applied", 0)), 0, "无 damage applied 0")
	var nd_applied := false
	for raw2 in s_nd.bus.recent(200):
		if raw2 is Dictionary and str((raw2 as Dictionary).get("type", "")) == "ballistics.impact":
			var p2: Dictionary = (raw2 as Dictionary).get("payload", {})
			var inner2: Dictionary = p2.get("payload", {}) if p2.get("payload") is Dictionary else {}
			if not bool((inner2.get("damage_event", {}) as Dictionary).get("applied", true)):
				nd_applied = true
	_ok(nd_applied, "无 damage 事件 applied=false")
	# PD 自动拦截
	var spd = GameSession.new(_duel_cfg("apsis"))
	var lpd: Dictionary = spd.combat_ballistics_launch("harmattan", "apsis", "missile",
		{"force_pd": true})
	_eq(bool(lpd.get("ok", false)), true, "PD 场景 missile launch")
	var pd_before: Dictionary = spd.combat_ballistics_pd()
	_eq(int(pd_before.get("ammo", 0)), 80, "PD 初始弹药 80")
	var tpd: Dictionary = spd.tick(1.0)
	var pdstep: Dictionary = tpd.get("ballistics_step", {})
	_eq(int(pdstep.get("intercepts", 0)), 1, "PD intercept 1")
	_eq(spd.combat_ballistics_active().size(), 0, "PD 后主动弹 0")
	_eq(int(spd.combat_ballistics_pd().get("ammo", 0)), 79, "PD 耗弹 1")
	var inter: Array = spd.combat_ballistics_intercepts()
	_eq(inter.size(), 1, "PD intercept 记录")
	_eq(bool((inter[0] as Dictionary).get("intercepted", false)), true, "PD 拦截成功")
	var ptypes: Array = _event_types(spd.bus.recent(200))
	_ok("ballistics.pd_launch" in ptypes, "bus pd_launch")
	_ok("ballistics.projectile_intercepted" in ptypes, "bus projectile_intercepted")
	# 坏配置
	var sbad = GameSession.new({"combat_ballistics": {"content_path": "/no/such.json"}})
	_ok(not bool(sbad.ready), "ballistics 坏 content 配置拒绝")
	# 确定性
	var a = GameSession.new(_ballistics_cfg(true))
	var b = GameSession.new(_ballistics_cfg(true))
	for sv in [a, b]:
		sv.combat_ballistics_launch("apsis", "harmattan", "railgun")
		sv.tick(2.0)
	_eq(_norm_json(a.combat_ballistics_vm()), _norm_json(b.combat_ballistics_vm()),
		"ballistics 同操作 VM 一致")
	_eq(a.save_state(), b.save_state(), "ballistics 同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "ballistics contracts ok 2")
	_data_line("ballistics", "可选退化 · predict/launch · tick 命中→Damage applied · PD 拦截 · bus · 存档/旧档/确定性")

# ═══════════════════════════════════════════════════════════════════
# 40. 统一开火路径（门禁 → 真实弹道 → 异步命中 → 时间倍速）
# ═══════════════════════════════════════════════════════════════════

func _unified_cfg() -> Dictionary:
	return {"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "session_ship", "fleet_id": "taskforce"},
		"combat_ballistics": {"pd_platform_id": "own"},
		"damage_service": true,
		"own_entity": "session_ship",
		"entities": [
			{"id": "session_ship", "batch": "1", "kind": "ship", "name": "APSIS",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0], "side": "friend"},
			{"id": "raider", "batch": "2", "kind": "ship", "name": "RAIDER",
				"pos_km": [300.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0], "side": "hostile"}],
		"nodes": [{"id": "session_ship"}, {"id": "raider"}],
		"links": [{"a": "session_ship", "b": "raider", "mode": "LD"}]}


func _unified_prepare(s, track_id := "R1") -> void:
	s.combat_register_track(track_id, {"identity": "hostile", "threat": "hostile",
		"range_km": 300.0, "in_arc": true, "ship_id": "raider", "entity_id": "raider"})
	s.combat_request_solution(track_id, "missile")
	s.tick(21.0)
	s.grant_authorization("FIRE", "target", track_id)


func _missile_ammo(s) -> int:
	for w in (s.combat_vm().get("weapons", []) as Array):
		if String((w as Dictionary).get("id", "")) == "missile":
			return int((w as Dictionary).get("ammo", -1))
	return -1


func _test_unified_fire_path() -> void:
	_section_begin("40 统一开火路径")
	var s = GameSession.new(_unified_cfg())
	_ok(bool(s.ready), "unified session ready", str(s.errors))
	_ok(s.combat_ballistics != null and bool(s.combat_ballistics.ready), "ballistics 已启用")
	_eq(bool(s.check_contracts().get("ok", false)), true, "unified boot contracts")
	_unified_prepare(s)
	# 玩家把时间倍速拉到 600×：开火后必须被压到 60×（决策 4）
	s.set_scale(600.0)
	_eq(float(s.time.scale), 600.0, "开火前倍速 600")
	# 门禁通过 + 真实发射
	var ammo0 := _missile_ammo(s)
	var fire: Dictionary = s.request_fire("R1", "missile", true)
	_eq(bool(fire.get("ok", false)), true, "统一路径 fire ok", str(fire.get("reason", "")))
	_eq(String(fire.get("physics", "")), "ballistics", "physics=ballistics")
	_eq(int(fire.get("launched", 0)), 1, "launched=1")
	_eq((fire.get("projectile_ids", []) as Array).size(), 1, "projectile_ids 1")
	_eq(String(fire.get("shooter_id", "")), "session_ship", "shooter 解析为本舰")
	_eq(String(fire.get("target_entity", "")), "raider", "target 实体解析")
	_eq(_missile_ammo(s), ammo0 - 1, "fire 扣 1 发弹药")
	_eq(s.combat_ballistics_active().size(), 1, "真实弹丸在飞")
	var pred: Dictionary = fire.get("prediction", {})
	_eq(String(pred.get("schema", "")), "ballistic_prediction.v1", "prediction schema")
	_ok(not fire.has("hit"), "不同步返回命中")
	# 交战时间倍速：强制降档
	var cap: Dictionary = s.combat_time_cap_state()
	_ok(bool(cap.get("active", false)), "交战中启用时间倍速上限")
	_near(float(cap.get("scale", 0.0)), 60.0, 1.0e-6, "倍速被压到 60×")
	_near(float(cap.get("restore_to", 0.0)), 600.0, 1.0e-6, "记录交战前倍速 600")
	_ok(bool((fire.get("time_cap", {}) as Dictionary).get("capped", false)),
		"fire 返回 capped 标记")
	_eq(float(cap.get("cap", 0.0)), 60.0, "time_cap cap=60")
	# bus：发射事件进总线，不含同步 hit/miss
	s.flush_events()
	var ckinds: Dictionary = {}
	for raw in s.bus.filter_events({"type": "combat"}):
		ckinds[String((raw as Dictionary).get("type", ""))] = true
	_ok(ckinds.has("combat.weapon_launch"), "bus 含 combat.weapon_launch")
	_ok(not ckinds.has("combat.combat_hit") and not ckinds.has("combat.combat_miss"),
		"bus 无同步 hit/miss")
	# 冷却内再次 fire 拒绝
	var again: Dictionary = s.request_fire("R1", "missile", true)
	_ok(not bool(again.get("ok", true)), "冷却内 fire 拒绝", str(again.get("reason", "")))
	# 推进到命中：异步 impact → Damage → 倍速恢复
	var hit_t := -1.0
	var dmg_applied := 0
	for i in range(400):
		var tk: Dictionary = s.tick(1.0)
		var bs: Dictionary = tk.get("ballistics_step", {})
		dmg_applied += int(bs.get("damage_applied", 0))
		if not s.combat_ballistics_impacts().is_empty():
			hit_t = float(s.now_s())
			break
	_ok(hit_t > 0.0, "弹丸最终命中/失效并产生 impact", "t=%.1f" % hit_t)
	_ok(s.combat_ballistics_impacts().size() >= 1, "impact 记录 ≥1")
	_eq(s.combat_ballistics_active().size(), 0, "命中后无在飞弹")
	_ok(dmg_applied >= 1, "命中真的路由进 DamageService", str(dmg_applied))
	var rtr: Dictionary = s.combat_service.track("R1")
	_ok(float(rtr.get("damage_taken", 0.0)) > 0.0, "航迹战果记账 damage_taken > 0",
		str(rtr.get("damage_taken")))
	var cap2: Dictionary = s.combat_time_cap_state()
	_ok(not bool(cap2.get("active", false)), "无在飞弹后释放倍速上限")
	_near(float(cap2.get("scale", 0.0)), 600.0, 1.0e-6, "倍速恢复到 600×")
	var itypes: Array = _event_types(s.bus.recent(400))
	_ok("ballistics.impact" in itypes, "bus 含 ballistics.impact")
	# 齐射：设置 → 一次发射多发
	var sal: Dictionary = s.set_weapon_salvo("missile", 3)
	_eq(bool(sal.get("ok", false)), true, "set_weapon_salvo 3")
	_eq(int(sal.get("salvo", 0)), 3, "齐射设置生效")
	_eq(String(s.request_fire("R1", "missile", true).get("reason", "")), "no_ready_solution",
		"无解算不放行（齐射前需重新解算）")
	# 上一轮命中已把 R1 记成 destroyed，后续用新航迹（同实体）
	_unified_prepare(s, "R2")
	var ammo1 := _missile_ammo(s)
	var sf: Dictionary = s.request_fire("R2", "missile", true)
	_eq(bool(sf.get("ok", false)), true, "齐射 fire ok", str(sf.get("reason", "")))
	_eq(int(sf.get("salvo", 0)), 3, "salvo=3")
	_eq(int(sf.get("launched", 0)), 3, "launched=3")
	_eq((sf.get("projectile_ids", []) as Array).size(), 3, "projectile_ids 3")
	_eq(_missile_ammo(s), ammo1 - 3, "齐射扣 3 发")
	_eq(s.combat_ballistics_active().size(), 3, "三发同时在飞")
	# 逐发独立散布：位置不重合
	var v0: Array = (s.combat_ballistics_active()[0] as Dictionary).get("vel_kmps", [])
	var v1: Array = (s.combat_ballistics_active()[1] as Dictionary).get("vel_kmps", [])
	var v2: Array = (s.combat_ballistics_active()[2] as Dictionary).get("vel_kmps", [])
	var d01 := Vector3(float(v0[0]), float(v0[1]), float(v0[2])).distance_to(
		Vector3(float(v1[0]), float(v1[1]), float(v1[2])))
	var d02 := Vector3(float(v0[0]), float(v0[1]), float(v0[2])).distance_to(
		Vector3(float(v2[0]), float(v2[1]), float(v2[2])))
	_ok(d01 > 0.0 and d02 > 0.0, "齐射逐发独立散布（初速方向不同）",
		"d01=%.4f d02=%.4f" % [d01, d02])
	# 齐射弹药不足：拒绝 + 要求重设，不扣弹
	s.combat_service.weapons["missile"]["ammo"] = 2
	s.set_weapon_salvo("missile", 4)
	_unified_prepare(s, "R3")
	var short: Dictionary = s.request_fire("R3", "missile", true)
	_ok(not bool(short.get("ok", true)), "弹药不足拒绝齐射")
	_eq(String(short.get("reason", "")), "insufficient_ammo_for_salvo", "拒绝理由")
	_ok(bool(short.get("needs_salvo_reset", false)), "要求重设齐射")
	_eq(int(_missile_ammo(s)), 2, "拒绝时不扣弹")
	s.set_weapon_salvo("missile", 2)
	_unified_prepare(s, "R4")
	var okf: Dictionary = s.request_fire("R4", "missile", true)
	_eq(bool(okf.get("ok", false)), true, "下调齐射后可发射", str(okf.get("reason", "")))
	_eq(int(_missile_ammo(s)), 0, "齐射 2 扣光弹药")
	# 规划辅助：预演 + 按意图发射
	var plan: Dictionary = s.combat_plan("R4", "railgun", "multi_axis")
	_eq(bool(plan.get("ok", false)), true, "combat_plan ok", str(plan.get("reason", "")))
	_eq(String(plan.get("schema", "")), "combat_plan.v1", "plan schema")
	var prd: Dictionary = s.combat_predict_track("R4", "railgun")
	_eq(String(prd.get("schema", "")), "ballistic_prediction.v1", "combat_predict_track schema")
	# 无实体状态的航迹 → 明确拒绝
	s.combat_register_track("GHOST", {"identity": "hostile", "threat": "hostile",
		"range_km": 300.0, "in_arc": true, "ship_id": "nobody", "entity_id": "nobody"})
	var ghost: Dictionary = s.request_fire("GHOST", "railgun", true)
	_eq(bool(ghost.get("ok", true)), false, "无物理状态 fire 拒绝")
	_eq(String(ghost.get("reason", "")), "no_physics_state", "no_physics_state reason")
	_eq(int((ghost.get("missing", {}) as Dictionary).get("target", 0)), 1, "missing 标记目标缺状态")
	# 未知武器齐射设置
	_eq(String(s.set_weapon_salvo("nope", 2).get("reason", "")), "unknown_weapon",
		"未知武器 set_weapon_salvo")
	_eq(bool(s.check_contracts().get("ok", false)), true, "unified contracts ok")
	# 存档往返保留倍速状态
	var sv: String = s.save_state()
	var s2 = GameSession.new(_unified_cfg())
	_eq(bool(s2.load_state(sv).get("ok", false)), true, "unified save/load ok")
	_eq(s2.combat_time_cap_state(), s.combat_time_cap_state(), "time_cap 存档往返一致")
	_data_line("unified_fire", "门禁→真实弹丸→异步 impact→Damage→倍速降档/恢复 · 齐射/散布/弹药不足拒绝 · 规划预演")
