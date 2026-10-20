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
