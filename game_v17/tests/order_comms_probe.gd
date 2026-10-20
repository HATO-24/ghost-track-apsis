extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# ORDER / COMMS PROBE · 完整游戏-阶段2B
#
# 验证：OrderService 全状态/延迟/撤销/过期/失败/不自动执行；CommsService
# 节点/链路/延迟/丢包/遮挡/中继/干扰/发送失败；独立文本库动态 from/to/mode；
# JSON、确定性、不写。只跑一次；不接 UI/物理。
#
# 运行：
#   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
#       --path .\game_v17 --script res://tests/order_comms_probe.gd
# 期望末行 ORDER COMMS PROBE OK，退出码 0。
# ═══════════════════════════════════════════════════════════════════

const CommsService := preload("res://scripts/core/comms_service.gd")
const OrderService := preload("res://scripts/core/order_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("ORDER COMMS PROBE · 完整游戏-阶段2B")
	print("════════════════════════════════════════════════════════════════")
	_test_text_library()
	_test_comms_routing()
	_test_comms_failures()
	_test_order_full_state()
	_test_order_auth_abort_expire()
	_test_order_comms_integration()
	_test_json_determinism()
	print("────────────────────────────────────────────────────────────────")
	print("ORDER COMMS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("ORDER COMMS PROBE FAILED")
		quit(1)
	else:
		print("ORDER COMMS PROBE OK")
		quit(0)


# ── 工具 ─────────────────────────────────────────────────────────

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[FAIL] ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _json_ok(v: Variant) -> bool:
	var s := JSON.stringify(v)
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref") \
		and not s.contains("Vector3")


func _has_event(events: Array, kind: String) -> bool:
	for raw in events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			return true
	return false


func _events_of(events: Array, kind: String) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append((raw as Dictionary).duplicate(true))
	return out


func _order_events(service, event_name: String) -> Array:
	var out: Array = []
	for raw in (service.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("event", "")) == event_name:
			out.append((raw as Dictionary).duplicate(true))
	return out


func _comms_basic() -> Object:
	var c = CommsService.new({
		"nodes": [
			{"id": "A", "name": "ALPHA", "role": "command", "type": "ship"},
			{"id": "B", "name": "BETA", "role": "escort", "type": "ship"},
			{"id": "R", "name": "RELAY", "role": "relay", "type": "ship"},
		],
		"links": [
			{"id": "L1", "a": "A", "b": "B", "mode": "LD", "latency_s": 0.1,
				"range_km": 300000.0},
			{"id": "L2", "a": "A", "b": "B", "mode": "RDO", "latency_s": 2.0,
				"range_km": 300000.0},
			{"id": "L3", "a": "A", "b": "R", "mode": "LD", "latency_s": 0.2,
				"range_km": 300000.0},
			{"id": "L4", "a": "R", "b": "B", "mode": "LD", "latency_s": 0.2,
				"range_km": 300000.0},
		],
	})
	return c


# ── 1. 独立文本库 ───────────────────────────────────────────────

func _test_text_library() -> void:
	print("")
	print("── 1. 独立文本库 / 动态 from-to-mode ──")
	var lib = CommsService.TextLibrary.new()
	lib.add_entries([
		{"text_key": "TEST_DYNAMIC",
			"template": "[{from} 至 {to}]-[{mode}]-[{content}]",
			"channel": "comms", "priority": 0},
		{"text_key": "TEST_ROLE",
			"template": "[{from} 至 {to}]-[{mode}]-[通用 {content}]",
			"template_by_role": {"command": "[{from} 至 {to}]-[{mode}]-[指挥 {content}]"},
			"channel": "comms", "priority": 0},
		{"text_key": "TEST_VARIANTS",
			"variants": ["第一次 {content}", "第二次 {content}"], "channel": "comms"},
		{"text_key": "TEST_DELAY",
			"template": "延迟 {delay}s，原因 {reason_text}", "channel": "comms"},
	])
	var r: Dictionary = lib.select("TEST_DYNAMIC", {
		"from": "ALPHA", "to": "BETA", "mode": "LD", "content": "ping",
		"channel": "comms"})
	_ok(bool(r.get("ok", false)), "动态模板 select ok")
	_eq(String(r.get("text", "")), "[ALPHA 至 BETA]-[LD]-[ping]", "from/to/mode/content 替换")
	_eq(String(r.get("from", "")), "ALPHA", "text from 字段")
	_eq(String(r.get("to", "")), "BETA", "text to 字段")
	_eq(String(r.get("mode", "")), "LD", "text mode 字段")
	var r2: Dictionary = lib.select("TEST_DYNAMIC", {
		"from": "BETA", "to": "ALPHA", "mode": "IR", "content": "pong",
		"channel": "comms"})
	_ok(String(r2.get("text", "")).contains("BETA 至 ALPHA"), "动态 from/to 不硬编码")
	_ok(String(r2.get("text", "")).contains("[IR]"), "动态 mode")
	_ok(not bool(lib.select("NO_SUCH_KEY", {}).get("ok", true)), "未知 text_key false")
	var miss: Dictionary = lib.render_template("[{from} {missing}]", {"from": "A"})
	_ok(not bool(miss.get("ok", true)) and String(miss.get("reason", "")).contains("missing_var"),
		"缺变量 false")
	var rr: Dictionary = lib.select("TEST_ROLE", {
		"from": "A", "to": "B", "mode": "RDO", "content": "go",
		"from_role": "command", "channel": "comms"})
	_ok(String(rr.get("text", "")).contains("指挥 go"), "角色模板命中")
	var rv1: Dictionary = lib.select("TEST_VARIANTS", {
		"from": "A", "to": "B", "mode": "LD", "content": "x", "channel": "comms"})
	var rv2: Dictionary = lib.select("TEST_VARIANTS", {
		"from": "A", "to": "B", "mode": "LD", "content": "x", "channel": "comms"})
	_ok(String(rv1.get("text", "")) != String(rv2.get("text", "")), "variants 轮换")
	_ok(_json_ok(lib.to_dict()), "text library JSON")
	_ok(_json_ok(r), "text result JSON")


# ── 2. 通信路由 / 投递 ─────────────────────────────────────────

func _test_comms_routing() -> void:
	print("")
	print("── 2. 通信节点/链路/延迟/中继 ──")
	var c = _comms_basic()
	_ok(bool(c.ready), "comms ready", str(c.errors))
	_eq((c.nodes as Dictionary).size(), 3, "3 节点")
	_eq((c.links as Array).size(), 4, "4 链路")
	var direct: Dictionary = c.send("A", "B", "LD", "COMMS_SENT", {"content": "hello"})
	_ok(bool(direct.get("ok", false)), "直连发送 ok")
	_eq(String(direct.get("path", [])[0]) if (direct.get("path", []) as Array).size() > 0 else "", "A",
		"直连 route 起点 A")
	_ok(float(direct.get("latency_s", 0.0)) > 0.0, "直连 latency>0", str(direct.get("latency_s")))
	_ok(String(direct.get("text", "")).contains("ALPHA") and String(direct.get("text", "")).contains("BETA"),
		"发送文本动态 from/to")
	_ok(String(direct.get("text", "")).contains("[LD]"), "发送文本 mode LD")
	var sent_events: Array = c.take_events()
	_ok(_has_event(sent_events, "SENT"), "SENT 事件")
	var ev0: Dictionary = _events_of(sent_events, "SENT")[0]
	_eq(String(ev0.get("schema", "")), "comms_event.v1", "event schema")
	_ok(String(ev0.get("text", "")).length() > 0, "event 带动态文本")
	_ok(int(ev0.get("writes_v15", 1)) == 0, "event 不写 V15")
	# 延迟前未投递
	var ev_before: Array = c.tick(0.05)
	_ok(not _has_event(ev_before, "DELIVERED"), "延迟前未投递")
	_ok(c.pending_count() == 1, "pending=1")
	var ev_after: Array = c.tick(0.1)
	_ok(_has_event(ev_after, "DELIVERED"), "延迟后 DELIVERED")
	_ok(c.pending_count() == 0, "投递后 pending=0")
	# 中继路由：遮挡直连 LD，但 A-R-B 存在
	_ok(c.set_link_occluded("A", "B", true, "LD"), "设置直连遮挡")
	var relay: Dictionary = c.send("A", "B", "LD", "COMMS_SENT", {"content": "relay"})
	_ok(bool(relay.get("ok", false)), "遮挡时经中继发送 ok")
	_eq(int(relay.get("relay_count", 0)), 1, "中继 relay_count=1")
	_ok(float(relay.get("latency_s", 0.0)) > float(direct.get("latency_s", 0.0)), "中继延迟更大")
	_ok(_json_ok(c.vm()), "comms VM JSON")
	_ok(_json_ok(c.summary()), "comms summary JSON")
	# 五种模式：LD/LR/RDO/IR/VIS
	var cm = CommsService.new({
		"nodes": [{"id": "A", "name": "A"}, {"id": "B", "name": "B"}],
		"links": [
			{"a": "A", "b": "B", "mode": "LD", "latency_s": 0.1},
			{"a": "A", "b": "B", "mode": "LR", "latency_s": 0.35},
			{"a": "A", "b": "B", "mode": "RDO", "latency_s": 2.0},
			{"a": "A", "b": "B", "mode": "IR", "latency_s": 0.2},
			{"a": "A", "b": "B", "mode": "VIS", "latency_s": 0.05},
		],
	})
	for m in ["LD", "LR", "RDO", "IR", "VIS"]:
		var rm: Dictionary = cm.send("A", "B", m, "COMMS_SENT", {"content": "m"},
			{"distance_km": 500.0})
		_ok(bool(rm.get("ok", false)), "mode %s 发送 ok" % m)
		_ok(String(rm.get("text", "")).contains("[%s]" % m), "mode %s 动态文本" % m)
	var vis_far: Dictionary = cm.send("A", "B", "VIS", "COMMS_SENT", {"content": "m"},
		{"distance_km": 99999.0})
	_ok(not bool(vis_far.get("ok", true)), "VIS 超距失败")
	_eq(String(vis_far.get("reason", "")), "out_of_range", "VIS 超距 reason")
	# LR 中继（无双端直连）
	var clr = CommsService.new({
		"nodes": [{"id": "A", "name": "A"}, {"id": "R", "name": "R"}, {"id": "B", "name": "B"}],
		"links": [
			{"a": "A", "b": "R", "mode": "LR", "latency_s": 0.2},
			{"a": "R", "b": "B", "mode": "LR", "latency_s": 0.2},
		],
	})
	var lr: Dictionary = clr.send("A", "B", "LR", "COMMS_SENT", {"content": "lr"})
	_ok(bool(lr.get("ok", false)), "LR 中继发送 ok")
	_eq(int(lr.get("relay_count", 0)), 1, "LR relay_count=1")
	_ok(((c.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "comms 不写 V15")
	_ok(c.take_events() is Array, "take_events 数组")


# ── 3. 通信失败：无路由/超距/遮挡/干扰/丢包/节点 ─────────────

func _test_comms_failures() -> void:
	print("")
	print("── 3. 通信失败原因 / 丢包 / 干扰 ──")
	var c = _comms_basic()
	var no_route: Dictionary = c.send("A", "B", "VIS", "COMMS_SENT", {"content": "x"})
	_ok(not bool(no_route.get("ok", true)), "无链路 VIS 发送失败")
	_eq(String(no_route.get("reason", "")), "no_route", "无路由 reason")
	var bad_key: Dictionary = c.send("A", "B", "LD", "NO_SUCH_KEY", {})
	_ok(not bool(bad_key.get("ok", true)), "未知 text_key 失败")
	_eq(String(bad_key.get("reason", "")), "unknown_text_key", "未知 text_key reason")
	var bad_mode: Dictionary = c.send("A", "B", "XX", "COMMS_SENT", {})
	_ok(not bool(bad_mode.get("ok", true)), "非法 mode 失败")
	_eq(String(bad_mode.get("reason", "")), "invalid_mode", "非法 mode reason")
	var far: Dictionary = c.send("A", "B", "LD", "COMMS_SENT", {"content": "x"},
		{"distance_km": 999999.0})
	_ok(not bool(far.get("ok", true)), "超距发送失败")
	_eq(String(far.get("reason", "")), "out_of_range", "超距 reason")
	# 遮挡且无中继
	var c2 = CommsService.new({
		"nodes": [{"id": "A", "name": "A"}, {"id": "B", "name": "B"}],
		"links": [{"a": "A", "b": "B", "mode": "LD", "occluded": true}],
	})
	var occ: Dictionary = c2.send("A", "B", "LD", "COMMS_SENT", {"content": "x"})
	_ok(not bool(occ.get("ok", true)), "遮挡无中继失败")
	_eq(String(occ.get("reason", "")), "occluded", "遮挡 reason")
	# 干扰（两节点直连，无可绕行中继）
	var c3 = CommsService.new({
		"nodes": [{"id": "A", "name": "A"}, {"id": "B", "name": "B"}],
		"links": [{"a": "A", "b": "B", "mode": "LD", "latency_s": 0.1}],
	})
	_ok(c3.set_link_jam("A", "B", 0.9, "LD"), "设置干扰")
	var jam: Dictionary = c3.send("A", "B", "LD", "COMMS_SENT", {"content": "x"})
	_ok(not bool(jam.get("ok", true)), "高干扰发送失败")
	_eq(String(jam.get("reason", "")), "jammed", "干扰 reason")
	# 节点损坏
	var c4 = _comms_basic()
	_ok(c4.set_node_status("B", "destroyed"), "设置节点损坏")
	var dead: Dictionary = c4.send("A", "B", "LD", "COMMS_SENT", {"content": "x"})
	_ok(not bool(dead.get("ok", true)), "节点损坏失败")
	_eq(String(dead.get("reason", "")), "node_unavailable", "节点损坏 reason")
	# 丢包：在到达时失败（发送本身 ok）
	var c5 = CommsService.new({
		"nodes": [{"id": "A", "name": "A"}, {"id": "B", "name": "B"}],
		"links": [{"a": "A", "b": "B", "mode": "LD", "latency_s": 0.1, "packet_loss": 1.0}],
	})
	var loss_send: Dictionary = c5.send("A", "B", "LD", "COMMS_SENT", {"content": "x"})
	_ok(bool(loss_send.get("ok", false)), "丢包链路发送接受")
	c5.tick(0.2)
	var fail_events: Array = c5.events as Array
	_ok(_has_event(fail_events, "FAILED"), "丢包到达失败事件")
	var fe: Array = _events_of(fail_events, "FAILED")
	_ok(not fe.is_empty() and String((fe[0] as Dictionary).get("reason", "")) == "packet_lost",
		"丢包 reason=packet_lost")
	_ok(_json_ok(c5.vm()), "失败 comms VM JSON")
	_ok(_json_ok(c.vm()), "失败场景 VM JSON")


# ── 4. 命令全状态（本地延迟，不自动执行）───────────────────────

func _order_cfg(extra := {}) -> Dictionary:
	var cfg := {
		"entities": {
			"a": {"name": "ALPHA", "role": "command"},
			"b": {"name": "BETA", "role": "escort"},
		},
		"delivery_delay_s": 2.0,
	}
	for k in extra.keys():
		cfg[k] = extra[k]
	return cfg


func _test_order_full_state() -> void:
	print("")
	print("── 4. OrderService 全状态 / 延迟 / 不自动执行 ──")
	var s = OrderService.new(_order_cfg())
	_ok(bool(s.ready), "order service ready")
	var cr: Dictionary = s.create_draft("set_destination", "a", ["b"],
		{"route": "L1"}, {"mode": "RDO", "delivery_delay": 2.0, "exec_delay": 3.0})
	_ok(bool(cr.get("ok", false)), "create_draft ok")
	var oid := String((cr.get("order", {}) as Dictionary).get("order_id", ""))
	_ok(oid != "", "order_id 存在")
	var draft: Dictionary = s.order(oid)
	_eq(String(draft.get("status", "")), "DRAFT", "DRAFT")
	_eq((_order_events(s, "DRAFTED") as Array).size(), 1, "DRAFTED event")
	var draft_text := String(((_order_events(s, "DRAFTED") as Array)[0] as Dictionary).get("text", ""))
	_ok(draft_text.contains("ALPHA") and draft_text.contains("BETA") and draft_text.contains("RDO"),
		"DRAFTED 动态 from/to/mode", draft_text)
	var iss: Dictionary = s.issue(oid)
	_ok(bool(iss.get("ok", false)), "issue ok")
	_eq(String(s.order(oid).get("status", "")), "ISSUED", "ISSUED")
	_ok((_order_events(s, "ISSUED") as Array).size() == 1, "ISSUED event")
	_ok((_order_events(s, "DELAYED") as Array).size() == 1, "DELAYED event")
	var iss_text := String(((_order_events(s, "ISSUED") as Array)[0] as Dictionary).get("text", ""))
	_ok(iss_text.contains("ALPHA") and iss_text.contains("BETA"), "ISSUED 动态文本")
	var t0: Dictionary = s.tick(0.0)
	_eq(String(s.order(oid).get("status", "")), "TRANSMITTING", "tick(0) → TRANSMITTING")
	_ok((t0.get("events", []) as Array).size() > 0, "tick 返回新事件")
	s.tick(1.0)
	_eq(String(s.order(oid).get("status", "")), "TRANSMITTING", "延迟中仍 TRANSMITTING")
	s.tick(1.1)
	_eq(String(s.order(oid).get("status", "")), "PENDING_EFFECT", "送达后 exec_delay → PENDING_EFFECT")
	_ok((_order_events(s, "DELIVERED") as Array).size() == 1, "DELIVERED event")
	s.tick(3.1)
	_eq(String(s.order(oid).get("status", "")), "QUEUED", "exec_t 后 QUEUED（不自动执行）")
	# 长时间 tick 仍不自动授权/执行
	s.tick(100.0)
	_eq(String(s.order(oid).get("status", "")), "QUEUED", "100s 后不自动授权/执行")
	var auth: Dictionary = s.authorize(oid, "a")
	_ok(bool(auth.get("ok", false)), "authorize ok")
	_eq(String(s.order(oid).get("status", "")), "AUTHORIZED", "AUTHORIZED")
	var begin: Dictionary = s.begin_execute(oid)
	_ok(bool(begin.get("ok", false)), "begin_execute ok")
	_eq(String(s.order(oid).get("status", "")), "EXECUTING", "EXECUTING")
	s.tick(5.0)
	_eq(String(s.order(oid).get("status", "")), "EXECUTING", "EXECUTING 不自动 DONE")
	var done: Dictionary = s.complete(oid, {"ok": true})
	_ok(bool(done.get("ok", false)), "complete ok")
	_eq(String(s.order(oid).get("status", "")), "DONE", "DONE")
	var hist: Array = s.order(oid).get("history", []) as Array
	var seq_states: Array = []
	for raw in hist:
		seq_states.append(String((raw as Dictionary).get("to", "")))
	_ok(seq_states.has("ISSUED") and seq_states.has("TRANSMITTING")
		and seq_states.has("DELIVERED") and seq_states.has("PENDING_EFFECT")
		and seq_states.has("QUEUED") and seq_states.has("AUTHORIZED")
		and seq_states.has("EXECUTING") and seq_states.has("DONE"),
		"全状态序列", str(seq_states))
	_ok((_order_events(s, "DONE") as Array).size() == 1, "DONE event")
	var issued_ev: Array = _order_events(s, "ISSUED")
	_ok(not issued_ev.is_empty() and String((issued_ev[0] as Dictionary).get("from_state", "")) == "DRAFT",
		"ISSUED 事件 from_state=DRAFT")
	_ok(_json_ok(s.vm()), "order VM JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "order 不写 V15")
	# 非法转移
	_ok(not bool(s.issue(oid).get("ok", true)), "已 DONE 不可再 issue")
	_ok(not bool(s.authorize(oid).get("ok", true)), "DONE 不可授权")


func _test_order_auth_abort_expire() -> void:
	print("")
	print("── 5. 命令拒绝 / 撤销 / 过期 / 失败 ──")
	# 过期：delivery 2s，expire 1s → STALE
	var se = OrderService.new(_order_cfg())
	var cr: Dictionary = se.create_draft("hold", "a", ["b"], {},
		{"delivery_delay": 2.0, "expire_in": 1.0})
	var oid := String((cr.get("order", {}) as Dictionary).get("order_id", ""))
	se.issue(oid)
	se.tick(1.1)
	_eq(String(se.order(oid).get("status", "")), "STALE", "过期 → STALE")
	_ok((_order_events(se, "STALE") as Array).size() == 1, "STALE event")
	se.tick(10.0)
	_eq(String(se.order(oid).get("status", "")), "STALE", "STALE 不执行")
	# 撤销：送达前撤销
	var sa = OrderService.new(_order_cfg())
	var cr2: Dictionary = sa.create_draft("hold", "a", ["b"], {}, {"delivery_delay": 5.0})
	var oid2 := String((cr2.get("order", {}) as Dictionary).get("order_id", ""))
	sa.issue(oid2)
	sa.tick(0.0)
	var ab: Dictionary = sa.abort(oid2, "commander_revoke")
	_ok(bool(ab.get("ok", false)), "abort ok")
	_eq(String(sa.order(oid2).get("status", "")), "ABORTED", "ABORTED")
	_ok((_order_events(sa, "ABORTED") as Array).size() == 1, "ABORTED event")
	sa.tick(100.0)
	_eq(String(sa.order(oid2).get("status", "")), "ABORTED", "ABORTED 保持")
	# authority hook 拒绝 → REJECTED
	var sr = OrderService.new(_order_cfg())
	var cr3: Dictionary = sr.create_draft("fire", "a", ["b"], {}, {"delivery_delay": 0.1})
	var oid3 := String((cr3.get("order", {}) as Dictionary).get("order_id", ""))
	var hook = func(order, by):
		return {"allowed": false, "reason": "roe_hold"}
	sr.set_auth_hook(hook)
	sr.issue(oid3)
	sr.tick(0.2)
	var auth_res: Dictionary = sr.authorize(oid3, "a")
	_ok(not bool(auth_res.get("ok", true)), "auth hook 拒绝 false")
	_eq(String(sr.order(oid3).get("status", "")), "REJECTED", "authority 拒绝 → REJECTED")
	_eq(String(sr.order(oid3).get("reason", "")), "roe_hold", "拒绝 reason=roe_hold")
	_ok((_order_events(sr, "REJECTED") as Array).size() == 1, "REJECTED event")
	# 需要授权人但空 → 拒绝
	var sq = OrderService.new(_order_cfg({"require_authorizer": true}))
	var cr4: Dictionary = sq.create_draft("hold", "a", ["b"], {}, {"delivery_delay": 0.1})
	var oid4 := String((cr4.get("order", {}) as Dictionary).get("order_id", ""))
	sq.issue(oid4)
	sq.tick(0.2)
	var qa: Dictionary = sq.authorize(oid4, "")
	_ok(not bool(qa.get("ok", true)), "require_authorizer 空授权人 false")
	_eq(String(sq.order(oid4).get("status", "")), "REJECTED", "缺授权人 → REJECTED")
	# 未授权不能执行
	var sn = OrderService.new(_order_cfg())
	var cr5: Dictionary = sn.create_draft("hold", "a", ["b"], {}, {"delivery_delay": 0.1})
	var oid5 := String((cr5.get("order", {}) as Dictionary).get("order_id", ""))
	sn.issue(oid5)
	sn.tick(0.2)
	_ok(not bool(sn.begin_execute(oid5).get("ok", true)), "QUEUED 未授权不可执行")
	_ok(_json_ok(sn.vm()), "拒绝/撤销 VM JSON")


# ── 6. Order + Comms 集成 ─────────────────────────────────────

func _test_order_comms_integration() -> void:
	print("")
	print("── 6. OrderService ↔ CommsService 投递 ──")
	var c = CommsService.new({
		"nodes": [{"id": "a", "name": "ALPHA", "role": "command"},
			{"id": "b", "name": "BETA", "role": "escort"}],
		"links": [{"a": "a", "b": "b", "mode": "LD", "latency_s": 0.2}],
	})
	var s = OrderService.new(_order_cfg({"comms": c, "delivery_delay_s": 9.0}))
	var cr: Dictionary = s.create_draft("crossfix", "a", ["b"], {}, {"mode": "LD"})
	var oid := String((cr.get("order", {}) as Dictionary).get("order_id", ""))
	var iss: Dictionary = s.issue(oid)
	_ok(bool(iss.get("ok", false)), "带 comms issue ok")
	_eq(String(s.order(oid).get("status", "")), "ISSUED", "comms issue → ISSUED")
	_ok(String(s.order(oid).get("delivery_id", "")) != "", "delivery_id 存在")
	s.tick(0.0)
	_eq(String(s.order(oid).get("status", "")), "TRANSMITTING", "comms tick → TRANSMITTING")
	s.tick(0.3)
	_ok(String(s.order(oid).get("status", "")) in ["QUEUED", "PENDING_EFFECT"],
		"comms 送达 → QUEUED/PENDING", String(s.order(oid).get("status", "")))
	_ok((_order_events(s, "DELIVERED") as Array).size() == 1, "order DELIVERED event")
	_ok(_json_ok(s.vm()), "整合 VM JSON")
	# comms 失败 → order REJECTED
	var cbad = CommsService.new({
		"nodes": [{"id": "a", "name": "ALPHA"}, {"id": "b", "name": "BETA"}],
		"links": [{"a": "a", "b": "b", "mode": "LD", "occluded": true}],
	})
	var sbad = OrderService.new(_order_cfg({"comms": cbad}))
	var cr2: Dictionary = sbad.create_draft("crossfix", "a", ["b"], {}, {"mode": "LD"})
	var oid2 := String((cr2.get("order", {}) as Dictionary).get("order_id", ""))
	var bad_issue: Dictionary = sbad.issue(oid2)
	_ok(not bool(bad_issue.get("ok", true)), "comms 失败 issue false")
	_eq(String(sbad.order(oid2).get("status", "")), "REJECTED", "comms 失败 → REJECTED")
	_ok(String(sbad.order(oid2).get("reason", "")).begins_with("comms_"), "失败 reason comms_*")
	_ok(_json_ok(sbad.vm()), "失败整合 VM JSON")


# ── 7. JSON / 确定性 / 不写 ────────────────────────────────────

func _test_json_determinism() -> void:
	print("")
	print("── 7. JSON / 确定性 / 不写 ──")
	var a = _comms_basic()
	var b = _comms_basic()
	for c in [a, b]:
		c.send("A", "B", "LD", "COMMS_SENT", {"content": "x"})
		c.tick(0.1)
		c.send("A", "B", "LD", "COMMS_SENT", {"content": "y"})
		c.tick(0.2)
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "comms 确定性")
	_ok(_json_ok(a.vm()), "comms VM JSON 2")
	_ok(_json_ok(a.events), "comms events JSON")
	var oa = OrderService.new(_order_cfg())
	var ob = OrderService.new(_order_cfg())
	for o in [oa, ob]:
		var cr: Dictionary = o.create_draft("hold", "a", ["b"], {}, {"delivery_delay": 0.1})
		var oid := String((cr.get("order", {}) as Dictionary).get("order_id", ""))
		o.issue(oid)
		o.tick(0.1)
		o.authorize(oid, "a")
		o.begin_execute(oid)
		o.complete(oid)
	_ok(JSON.stringify(oa.vm()) == JSON.stringify(ob.vm()), "order 确定性")
	_ok(_json_ok(oa.vm()), "order VM JSON 2")
	_ok(bool(oa.ready) and bool(a.ready), "两个服务 ready")
	_ok(((oa.vm().get("text_library", {}) as Dictionary).get("schema", "")) == "comms_text_library.v1",
		"text library schema 公共接口")
