extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# STORY TRIGGER PROBE · 阶段2 TEXT-ENGINE-1
#
# 验证：story.triggers 行动驱动（非时间轴）、顺序、once 抑制、失败不触发、
# 乱序/补触发、世界事件/无线电接线、JSON、重开复位。
#
# 运行：
#   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
#       --path .\game_v17 --script res://tests/story_trigger_probe.gd
# 期望末行 STORY TRIGGER PROBE OK，退出码 0。
# ═══════════════════════════════════════════════════════════════════

const ScenarioScript := preload("res://framework/core/scenario.gd")
const WorldScript := preload("res://framework/core/world.gd")
const MissionScript := preload("res://framework/core/mission.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("STORY TRIGGER PROBE · 阶段2 TEXT-ENGINE-1")
	print("════════════════════════════════════════════════════════════════")
	_test_content()
	_test_no_time_auto()
	_test_world_action_order()
	_test_direct_out_of_order()
	_test_json_and_reset()
	print("────────────────────────────────────────────────────────────────")
	print("STORY TRIGGER PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("STORY TRIGGER PROBE FAILED")
		quit(1)
	else:
		print("STORY TRIGGER PROBE OK")
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
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref")


func _make(attach := true) -> Dictionary:
	var sc = ScenarioScript.load_file("res://framework/content/scenario_l1_v2.json")
	var w = WorldScript.new()
	var ok: bool = w.load_scenario(sc)
	var m = MissionScript.from_scenario(sc)
	if attach and m != null:
		w.attach_mission(m)
	return {"sc": sc, "w": w, "m": m, "ok": ok}


func _ids(m, from_index := 0) -> Array:
	var out: Array = []
	for i in range(from_index, m.trigger_log.size()):
		out.append(String((m.trigger_log[i] as Dictionary).get("trigger_id", "")))
	return out


func _event_texts(w) -> Array:
	var out: Array = []
	for raw in w.events:
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("text", "")))
	return out


func _radio_texts(w) -> Array:
	var out: Array = []
	for raw in w.radio:
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("text", "")))
	return out


# ── 1. 内容 / schema ─────────────────────────────────────────────

func _test_content() -> void:
	print("")
	print("── 1. story.triggers schema / 文本引用 ──")
	var d := _make()
	var sc = d["sc"]
	var m = d["m"]
	var w = d["w"]
	_ok(bool(d["ok"]), "场景/世界装载")
	_ok(sc.errors.is_empty(), "场景解析无错误", str(sc.errors))
	_eq(m.story_triggers.size(), 18, "触发器 18 条（6 events + 12 radio）")
	_ok(m.errors.is_empty(), "mission 触发器解析无错误", str(m.errors))
	var snap: Dictionary = m.trigger_snapshot()
	_ok(String(snap.get("schema", "")) == "v2_story_trigger.v1", "snapshot schema")
	_ok(_json_ok(snap), "snapshot JSON 可序列化")
	var ids: Dictionary = {}
	var keys: Dictionary = {}
	var channels: Dictionary = {"event": 0, "radio": 0}
	var events: Array = (sc.story.get("events", []) as Array)
	var radio: Array = (sc.story.get("radio_lines", []) as Array)
	var key_ok := true
	var idx_ok := true
	for raw in m.story_triggers:
		var t: Dictionary = raw
		var tid := String(t.get("id", ""))
		if ids.has(tid):
			ids[tid] = int(ids[tid]) + 1
		else:
			ids[tid] = 1
		var key := String(t.get("text_key", ""))
		if key == "":
			key_ok = false
		elif keys.has(key):
			key_ok = false
		else:
			keys[key] = true
		var ch := String(t.get("channel", ""))
		var idx := int(t.get("index", -1))
		var entries: Array = events if ch == "event" else radio
		if idx < 0 or idx >= entries.size():
			idx_ok = false
		channels[ch] = int(channels.get(ch, 0)) + 1
		if key == "":
			key_ok = false
	_ok(key_ok, "text_key 全部非空且无重复", "keys=%d" % keys.size())
	_ok(idx_ok, "event_index/radio_index 全部有效")
	_eq(int(channels.get("event", 0)), 6, "event 触发器 6")
	_eq(int(channels.get("radio", 0)), 12, "radio 触发器 12")
	var dup := false
	for k in ids.keys():
		if int(ids[k]) != 1:
			dup = true
	_ok(not dup, "触发器 id 唯一")
	_ok(m.trigger_log.is_empty(), "初始无已触发文本（无自动播报）")


# ── 2. 纯时间推进不播报 ──────────────────────────────────────────

func _test_no_time_auto() -> void:
	print("")
	print("── 2. 时间推进不自动播报（前置未完成 → 冻结）──")
	var d := _make()
	var w = d["w"]
	var m = d["m"]
	var before_events := _event_texts(w).size()
	var before_radio := _radio_texts(w).size()
	var r: Dictionary = w.advance(120.0)
	_ok(bool(r.get("frozen", false)), "前置未完成 → advance frozen")
	_eq(_event_texts(w).size(), before_events, "时间推进后 events 不增加")
	_eq(_radio_texts(w).size(), before_radio, "时间推进后 radio 不增加")
	_eq(m.trigger_log.size(), 0, "时间推进不触发任何 story trigger")

	# 跳过前置（玩家动作）后才允许时间流动；再纯推进 60 s 不应自动播报其余事件。
	var d2 := _make()
	var w2 = d2["w"]
	var m2 = d2["m"]
	w2.prelude_skip()
	var after_arrival: int = m2.trigger_log.size()

	var r2: Dictionary = w2.advance(60.0)
	_ok(not bool(r2.get("frozen", false)), "前置后时间流动")
	_eq(m2.trigger_log.size(), after_arrival, "纯时间推进不新增动作触发器")
	var story_radio_n := 0
	for raw_t in m2.trigger_log:
		if String((raw_t as Dictionary).get("channel", "")) == "radio":
			story_radio_n += 1
	_eq(story_radio_n, 4, "纯时间推进后 story radio 仍为抵达 4 条")


# ── 3. 世界动作驱动顺序 / 重复 / 失败 ────────────────────────────

func _test_world_action_order() -> void:
	print("")
	print("── 3. 世界动作驱动、顺序、once、失败不触发 ──")
	var d := _make()
	var w = d["w"]
	var m = d["m"]
	# 前置点火（玩家动作）→ 抵达文本
	var skip: Dictionary = w.prelude_skip()
	_ok(bool(skip.get("ok", false)), "prelude_skip 成功")
	var arrival := _ids(m)
	_eq(arrival.size(), 5, "抵达触发 5 条（1 event + 4 radio）")
	_ok(arrival.has("TR-ARRIVE-NOTICE"), "抵达触发器 id 正确", str(arrival))
	_ok(arrival.has("TR-ARRIVE-RADIO-4412"), "抵达 radio 触发器存在")
	var arrival_radio_n := 0
	for raw_a in m.trigger_log:
		if String((raw_a as Dictionary).get("channel", "")) == "radio":
			arrival_radio_n += 1
	_eq(arrival_radio_n, 4, "抵达 story radio 4 条（world.radio 另含 prelude done_comm）")
	var ev_arrival := _event_texts(w)
	var has_notice := false
	for s in ev_arrival:
		if String(s).contains("第七号令接管声明送达"):
			has_notice = true
	_ok(has_notice, "抵达 event 文本来自 story events[0]")

	# 选择 9001 → 1 条 radio
	_ok(w.select("ceres_2"), "select ceres_2 成功")
	_ok(_ids(m).has("TR-SELECT-CERES"), "选择目标触发 TR-SELECT-CERES")
	_eq(m.trigger_log.size(), 6, "select 后累计 6 条")

	# 命令生效/传输：世界 order 钩子 → r5/r6（同一命令不同状态各一次）
	var io: Dictionary = w.issue_order("radar_illum", "2001")
	_ok(bool(io.get("ok", false)), "issue_order radar_illum 成功", String(io.get("reason", "")))
	if bool(io.get("ok", false)):
		var oo = io.get("order", null)
		var oid := String(oo.id) if oo != null else ""
		var auth: Dictionary = w.authorize_order(oid)
		_ok(bool(auth.get("ok", false)), "authorize_order 成功", String(auth.get("reason", "")))
		_ok(_ids(m).has("TR-ORDER-RADAR-AUTH"), "命令授权触发 TR-ORDER-RADAR-AUTH")
		var enq: Dictionary = w.enqueue_order(oid)
		_ok(bool(enq.get("ok", false)), "enqueue_order 成功", String(enq.get("reason", "")))
		var tx: Dictionary = w.transmit_order(oid)
		_ok(bool(tx.get("ok", false)), "transmit_order 成功", String(tx.get("reason", "")))
		_ok(_ids(m).has("TR-ORDER-RADAR-TX"), "命令传输触发 TR-ORDER-RADAR-TX")
		var pre_abort: int = m.trigger_log.size()
		var ab: Dictionary = w.abort_order(oid)
		_ok(bool(ab.get("ok", false)), "abort_order 成功", String(ab.get("reason", "")))
		_eq(m.trigger_log.size(), pre_abort, "撤销命令不新增/不伪造文本")
	var before_opt: int = m.trigger_log.size()
	# crossfix 2001 先到 L2，才能 model_ident（真实动作成功才触发）
	var cf: Dictionary = w.perform_action("crossfix", "2001")
	_ok(bool(cf.get("ok", false)), "crossfix 2001 成功", String(cf.get("reason", "")))
	# model_ident 2001 → event + radio
	var act: Dictionary = w.perform_action("model_ident", "2001")
	_ok(bool(act.get("ok", false)), "model_ident 2001 成功", String(act.get("reason", "")))
	var after_opt: int = m.trigger_log.size()
	_ok(_ids(m).has("TR-OPTICAL-CLASS") and _ids(m).has("TR-OPTICAL-RADIO"),
		"光学动作触发 event+radio")
	_eq(after_opt, before_opt + 2, "光学动作新增 2 条")

	# 同一动作重复 → 不再触发（重复 select 同一目标）
	_ok(w.select("ceres_2"), "重复 select 本身可执行")
	_eq(m.trigger_log.size(), after_opt, "重复动作不重复触发文本")

	# 失败动作 → 不触发
	var bad: Dictionary = w.perform_action("fire_weapon", "2001")
	_ok(not bool(bad.get("ok", false)), "非法动作失败")
	_eq(m.trigger_log.size(), after_opt, "失败动作不触发文本")
	var bad2: Dictionary = w.perform_action("iff_query", "does_not_exist")
	_ok(not bool(bad2.get("ok", false)), "不存在目标动作失败")
	_eq(m.trigger_log.size(), after_opt, "目标不存在不触发文本")

	# 事件/文本顺序与世界触发顺序一致
	var seqs: Array = []
	var monotonic := true
	for raw in m.trigger_log:
		var s := int((raw as Dictionary).get("seq", 0))
		seqs.append(s)
		if seqs.size() > 1 and s <= int(seqs[seqs.size() - 2]):
			monotonic = false
	_ok(monotonic, "trigger seq 单调递增", str(seqs))
	var last := String((m.trigger_log[m.trigger_log.size() - 1] as Dictionary).get("trigger_id", ""))
	_ok(last == "TR-OPTICAL-RADIO", "最新触发为光学 radio", last)


# ── 4. 乱序 / 补触发（直接 mission 事件）────────────────────────

func _test_direct_out_of_order() -> void:
	print("")
	print("── 4. 乱序 / 补触发 / 失败入口 ──")
	var d := _make()
	var m = d["m"]
	# 先做较晚动作 model_ident，再做较早选择 select，最后补 crossfix
	var a1: Array = m.note_player_event("action", "model_ident", "2001")
	var a2: Array = m.note_player_event("select", "select", "ceres_2")
	var a3: Array = m.note_player_event("action", "crossfix", "9002")
	_eq(a1.size(), 2, "乱序第1动作触发 2 条")
	_eq(a2.size(), 1, "乱序第2动作触发 1 条")
	_eq(a3.size(), 1, "乱序第3动作补触发 1 条")
	var order := _ids(m)
	_eq(order.size(), 4, "乱序累计 4 条")
	_ok(order[0] == "TR-OPTICAL-CLASS" and order[1] == "TR-OPTICAL-RADIO",
		"乱序后文本顺序跟随动作顺序", str(order))
	_ok(order[2] == "TR-SELECT-CERES", "select 文本在光学之后", str(order))
	_ok(order[3] == "TR-CROSSFIX-FALSE-ALARM", "补触发 crossfix 文本在最后")

	# 重复/失败入口
	var before: int = m.trigger_log.size()
	_eq(m.note_player_event("action", "model_ident", "2001").size(), 0, "重复动作入口 0 条")
	_eq(m.note_player_event("action", "model_ident", "2001", {"ok": false}).size(), 0,
		"ok=false 入口 0 条")
	_eq(m.trigger_log.size(), before, "重复/失败入口总数不变")
	# 失败目标/未知动作天然无匹配
	_eq(m.note_player_event("action", "fire_weapon", "2001").size(), 0, "无匹配动作 0 条")

	# 触发器定义顺序：prelude execute 的多条文本按定义顺序
	var d2 := _make()
	var m2 = d2["m"]
	var pre: Array = m2.note_player_event("prelude", "execute", "")
	_eq(pre.size(), 5, "prelude execute 触发 5 条")
	_eq(String(pre[0].get("trigger_id", "")), "TR-ARRIVE-NOTICE", "prelude 首条 event 在前")
	_eq(String(pre[1].get("trigger_id", "")), "TR-ARRIVE-RADIO-GREENWICH", "prelude radio 按定义顺序")
	_eq(String(pre[4].get("trigger_id", "")), "TR-ARRIVE-RADIO-4412", "prelude 末条 radio")
	_ok(_json_ok(pre), "触发条目 JSON 可序列化")
	# 其他动作类型：decision / evidence / order 状态
	var d4 := _make()
	var m4 = d4["m"]
	_eq(m4.note_player_event("decision", "open").size(), 3, "decision open 触发 3 条")
	_eq(m4.note_player_event("evidence", "start", "port_telemetry").size(), 1,
		"evidence start 触发 1 条")
	_eq(m4.note_player_event("order", "radar_illum", "2001", {"state": "AUTHORIZED"}).size(), 1,
		"order AUTHORIZED 触发 1 条")
	_eq(m4.note_player_event("order", "radar_illum", "2001", {"state": "ABORTED"}).size(), 0,
		"order ABORTED 无文本（不发明撤销文本）")
	_eq(m4.note_player_event("order", "radar_illum", "2001", {"state": "TRANSMITTED"}).size(), 1,
		"order TRANSMITTED 触发 1 条")
	_ok(_json_ok(m4.trigger_snapshot()), "多类型触发 snapshot JSON")


# ── 5. 世界事件/无线电 / 重开复位 / snapshot ────────────────────

func _test_json_and_reset() -> void:
	print("")
	print("── 5. 世界接线 / 重开复位 / snapshot ──")
	var d := _make()
	var w = d["w"]
	var m = d["m"]
	w.prelude_skip()
	w.select("ceres_2")
	var ev := _event_texts(w)
	var rad := _radio_texts(w)
	var all_text: Array = []
	all_text.append_array(ev)
	all_text.append_array(rad)
	var no_empty := true
	for s in all_text:
		if String(s).strip_edges() == "":
			no_empty = false
	_ok(no_empty, "世界 events/radio 文本非空（无占位）")
	_eq(m.trigger_log.size(), 6, "世界接线触发 6 条（4 radio + 1 event + select radio）")
	var joined := "|".join(all_text)
	_ok(joined.contains("第七号令接管声明送达"), "world events 含 story events[0]")
	_ok(joined.contains("第七号轨道紧急托管令现予公告"), "world radio 含 story radio[0]")
	_ok(joined.contains("敌我识别未应答"), "world radio 含 select 触发 radio[4]")
	var snap: Dictionary = m.trigger_snapshot()
	_ok(_json_ok(snap), "trigger_snapshot JSON")
	_eq(int(snap.get("fired_count", 0)), 6, "snapshot fired_count=6")
	_eq(int(snap.get("trigger_count", 0)), 18, "snapshot trigger_count=18")
	# 重开：恢复初始，触发器清空
	var rr: Dictionary = w.restart()
	_ok(bool(rr.get("ok", false)), "world.restart 成功", str(rr.get("errors", [])))
	_eq(m.trigger_log.size(), 0, "restart 后 trigger_log 清空")
	_eq(m.fired_triggers.size(), 0, "restart 后 fired_triggers 清空")
	_ok(_radio_texts(w).is_empty(), "restart 后无 story radio")
	_ok(_json_ok(m.trigger_snapshot()), "restart snapshot JSON")
