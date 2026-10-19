extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# V17-CORE-1 bridge probe（V15 视觉 + framework V2 core 桥接）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_bridge_probe.gd
# 可选环境变量：
#   DSH_SKIP_TUTORIAL=1   教学门控禁用（断言分支）
#
# 覆盖：10 接触 / tutorial 字段与门控 / fw_perform_action / flow / damage /
#       replay / exec 窗口 / 站体储罐 / V15 state.fw_* 归一字段 / 决策挂起与自动打开 /
#       V15→V2 决策/报告镜像。
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const BridgeScript := preload("res://scripts/framework_bridge.gd")
const StateScript := preload("res://scripts/state.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []
var _skip_tutorial := false

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("V17-CORE-1 BRIDGE PROBE · V15 视觉 + framework V2 core")
	print("════════════════════════════════════════════════════════════")
	_skip_tutorial = OS.get_environment("DSH_SKIP_TUTORIAL") == "1"
	_test_boot()
	_test_contacts_and_stations(_bridge)
	_test_tutorial_and_actions()
	_test_flow_and_exec()
	_test_damage()
	_test_replay()
	_test_state_fields(_bridge)
	_test_v15_gate_and_flow()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 BRIDGE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 BRIDGE PROBE FAILED")
		quit(1)
	else:
		print("V17 BRIDGE PROBE OK")
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

func _non_empty(s: String, label: String) -> void:
	_ok(s != "", label, "" if s == "" else "len=%d" % s.length())

func _contains(arr: Array, needle, label: String) -> void:
	_ok(needle in arr, label, "needle=" + str(needle) + " arr=" + str(arr).substr(0, 200))

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

var _bridge = null

func _test_boot() -> void:
	_section_begin("1 boot")
	_bridge = BridgeScript.new()
	var ok: bool = _bridge.boot()
	_eq(ok, true, "bridge.boot 成功", str(_bridge.errors))
	_eq(_bridge.ready, true, "ready=true")
	var sum: Dictionary = _bridge.summary()
	_eq(String(sum.get("scenario", "")), "l1_supervision_v2", "场景 id")
	_eq(int(sum.get("entities", 0)), 9, "实体 9")
	_eq(int(sum.get("contacts", 0)), 10, "接触 10")
	_eq(String(sum.get("own", "")), "harmattan", "own=harmattan")
	_eq(bool(sum.get("skipped_v2_prelude", false)), true, "默认跳过 V2 prelude（V15 自管 PRELUDE）")
	_eq(bool((_bridge.flow.get("prelude", {}) as Dictionary).get("open", true)), false,
		"V2 flow.prelude.open=false")
	_bridge.sync(0.5)
	_bridge.sync(0.5)
	_ok(int(_bridge.sync_count) >= 2, "sync 计数", str(_bridge.sync_count))
	_eq(_bridge.contacts.size(), 10, "sync 后 contacts 10")
	_data_line("boot", "ready=%s entities=9 contacts=10 own=harmattan skipped_v2_prelude=true" % str(ok))

func _test_contacts_and_stations(bridge) -> void:
	_section_begin("2 接触/站体")
	var contacts: Array = bridge.contacts_view()
	_eq(contacts.size(), 10, "contacts 10")
	var by_id: Dictionary = {}
	for raw in contacts:
		var c: Dictionary = raw
		by_id[String(c.get("track_id", ""))] = c
	for tid in ["1001", "2001", "9001", "9002", "0100", "0101"]:
		_ok(by_id.has(tid), "接触存在: " + tid)
	var station: Dictionary = by_id.get("0100", {})
	_eq(String(station.get("kind", "")), "station", "0100 kind=station")
	_eq(String(station.get("icon", "")), "station", "0100 icon")
	_eq(bool(station.get("fixed", false)), true, "0100 fixed")
	_eq(String(station.get("orbit_source", "")), "fixed", "0100 orbit_source=fixed")
	var tank: Dictionary = by_id.get("0101", {})
	_eq(String(tank.get("kind", "")), "tank", "0101 kind=tank")
	_eq(bool(tank.get("fixed", false)), true, "0101 fixed")
	_eq(String((by_id.get("9002", {}) as Dictionary).get("entity_id", "x")), "", "9002 无实体回波")
	_data_line("contacts", "10 条（7 舰 + 无实体 9002 + 站体 0100 + 储罐 0101）")

func _test_tutorial_and_actions() -> void:
	_section_begin("3 教学门控 / 动作")
	var tut: Dictionary = _bridge.tutorial_view()
	_eq(bool(tut.get("enabled", false)), not _skip_tutorial, "tutorial.enabled（env skip 时 false）")
	if not _skip_tutorial:
		_eq(bool(tut.get("ready", true)), false, "初始未 ready")
		_eq((tut.get("required_actions", []) as Array).size(), 4, "required_actions 4")
		_eq(int((tut.get("progress", {}) as Dictionary).get("need", 0)), 2, "need=2")
		_non_empty(String(_bridge.decision_gate_reason()), "decision_gate_reason 非空: " + String(_bridge.decision_gate_reason()))
		_ok(String(_bridge.decision_gate_reason()).contains("教学"), "门控原因写明教学")
		_eq(bool(_bridge.tutorial_allowed()), false, "tutorial_allowed=false")
	else:
		_eq(bool(_bridge.tutorial_allowed()), true, "env skip → tutorial_allowed=true")

	# 动作列表
	var acts: Array = _bridge.actions_for("2001")
	_ok(acts.size() >= 10, "actions_for(2001) 返回动作", str(acts.size()))
	var crossfix: Dictionary = {}
	var iff: Dictionary = {}
	var fire: Dictionary = {}
	for raw in acts:
		var a: Dictionary = raw
		match String(a.get("id", "")):
			"crossfix":
				crossfix = a
			"iff_query":
				iff = a
			"fire_control":
				fire = a
	_eq(bool(crossfix.get("available", false)), true, "L1 crossfix 可用")
	_eq(String(iff.get("reason_code", "")), "level", "iff_query 被等级门控")
	_eq(String(fire.get("reason_code", "")), "unsupported", "武器类 unsupported")

	# 执行动作 → 教学进度
	var a1: Dictionary = _bridge.perform_action("crossfix", "2001")
	_eq(bool(a1.get("ok", false)), true, "fw/bridge perform_action crossfix", String(a1.get("reason", "")))
	_eq(int(a1.get("level", 0)), 2, "crossfix → L2")
	_eq(String(a1.get("actor_id", "")), "harmattan", "actor=harmattan")
	var tut1: Dictionary = _bridge.tutorial_view()
	if not _skip_tutorial:
		_eq(int((tut1.get("progress", {}) as Dictionary).get("done", 0)), 1, "教学完成 1/2")
		_eq(bool(tut1.get("ready", true)), false, "1 项不够")
	var a2: Dictionary = _bridge.perform_action("model_ident", "2001")
	_eq(bool(a2.get("ok", false)), true, "perform_action model_ident")
	_eq(int(a2.get("level", 0)), 3, "model_ident → L3")
	var tut2: Dictionary = _bridge.tutorial_view()
	if not _skip_tutorial:
		_eq(bool(tut2.get("ready", false)), true, "2 项后 tutorial ready")
		_eq(int((tut2.get("progress", {}) as Dictionary).get("done", 0)), 2, "教学完成 2/2")
		_eq(_bridge.decision_gate_reason(), "", "ready 后 decision_reason 清空")
	_eq(String((a2.get("detail", ""))).length() > 0, true, "动作返回 detail")
	_data_line("tutorial/action", "crossfix→L2, model_ident→L3, gate %s" %
		("skipped(env)" if _skip_tutorial else "0→1→2 ready"))

func _test_flow_and_exec() -> void:
	_section_begin("4 flow / 执行窗口")
	var r: Dictionary = _bridge.open_decision()
	_eq(bool(r.get("ok", false)), true, "open_decision（教学已满足）", String(r.get("reason", "")))
	var flow: Dictionary = _bridge.flow_view()
	_eq(bool((flow.get("decision", {}) as Dictionary).get("open", false)), true, "flow.decision.open")
	_eq(float(flow.get("exec_window_s", 0.0)), 360.0, "exec_window_s=360")
	var left := float(flow.get("exec_left", -1.0))
	_ok(left >= 0.0 and left <= 360.0, "exec_left 在 [0,360]", "left=%.1f" % left)
	_ok(flow.has("exec_pct") and flow.has("reputation") and flow.has("reputation_settled"),
		"flow 提供 exec_pct/reputation")
	var rep: Dictionary = flow.get("reputation", {})
	for k in ["ocu", "meridian", "ueg_doves", "outer", "reclaimers"]:
		_ok(rep.has(k), "五方声望 key: " + k)
	for need in ["prelude", "decision", "report", "end", "mission", "tutorial", "damage", "replay"]:
		_ok(flow.has(need), "flow 字段: " + need)
	_eq(_bridge.exec_window_s, 360.0, "bridge.exec_window_s")
	_ok(_bridge.exec_left <= 360.0, "bridge.exec_left", "left=%.1f" % _bridge.exec_left)
	_data_line("flow", "decision.open, exec_window_s=360, exec_left=%.1f" % left)

func _test_damage() -> void:
	_section_begin("5 损管")
	var dmg: Dictionary = _bridge.damage_view()
	_eq(String(dmg.get("entity_id", "")), "harmattan", "损管归属本舰")
	var sections: Array = dmg.get("sections", [])
	_eq(sections.size(), 3, "本舰损管 3 项")
	var ids: Array = []
	for raw in sections:
		ids.append(String((raw as Dictionary).get("id", "")))
	_contains(ids, "sensor_cal", "含 sensor_cal")
	_contains(ids, "ir_false_alarm", "含 ir_false_alarm")
	_contains(ids, "thermal", "含 thermal")
	_ok(int((dmg.get("summary", {}) as Dictionary).get("total", 0)) == 3, "summary.total=3")
	var rep: Dictionary = _bridge.start_repair("sensor_cal")
	_eq(bool(rep.get("ok", false)), true, "start_repair(sensor_cal)", String(rep.get("reason", "")))
	# 推进世界让维修完成（sensor_cal 120s）
	_bridge.sync(125.0)
	var after: Dictionary = _bridge.damage_view()
	var repaired := false
	for raw in (after.get("sections", []) as Array):
		var d: Dictionary = raw
		if String(d.get("id", "")) == "sensor_cal":
			repaired = String(d.get("state", "")) == "repaired"
	_ok(repaired, "sensor_cal 维修完成（advance 自动推进）")
	_eq((after.get("queue", []) as Array).size(), 0, "维修队列清空")
	_data_line("damage", "3 项；sensor_cal repari 120s → repaired")

func _test_replay() -> void:
	_section_begin("6 回放")
	var rp: Dictionary = _bridge.replay_view()
	_ok(bool(rp.get("recording", false)), "recording=true")
	_ok(int(rp.get("total", 0)) >= 1, "replay 帧数", "total=%d" % int(rp.get("total", 0)))
	var before := int(rp.get("total", 0))
	_bridge.sync(2.5)
	rp = _bridge.replay_view()
	_ok(int(rp.get("total", 0)) > before, "sync 后帧数增长", "%d → %d" % [before, int(rp.get("total", 0))])
	var frame: Dictionary = _bridge.replay_frame()
	for key in ["t", "own", "contacts", "flow", "orders", "evidence", "damage", "exec_left"]:
		_ok(frame.has(key), "帧字段: " + key)
	_ok(not frame.has("weapons") and not frame.has("fire_control"), "帧不含武器数据")
	var started: Dictionary = _bridge.replay_start()
	_eq(bool(started.get("playing", false)), true, "replay_start")
	var seeked: Dictionary = _bridge.replay_seek(1.0)
	_ok(int(seeked.get("index", -1)) >= 0, "replay_seek")
	var paused: Dictionary = _bridge.replay_pause()
	_eq(bool(paused.get("paused", false)), true, "replay_pause")
	# seek 后固定查看头：录制继续追加帧也不移动 index
	var pin_idx := int(_bridge.replay_view().get("index", 0))
	var pin_frame: Dictionary = _bridge.replay_frame()
	_ok(bool(_bridge.replay_view().get("pinned", false)), "seek 后 pinned=true")
	_ok(_bridge.replay_view().has("frame_t"), "replay 提供 frame_t（当前帧时间）")
	_bridge.sync(2.0)
	_eq(int(_bridge.replay_view().get("index", -1)), pin_idx, "录制追加帧不移动回放查看头")
	_ok(float(_bridge.replay_frame().get("t", -1.0)) == float(pin_frame.get("t", -2.0)),
		"固定帧内容不变")
	var stopped: Dictionary = _bridge.replay_stop()
	_eq(bool(stopped.get("playing", true)), false, "replay_stop")
	_eq(bool(_bridge.replay_view().get("pinned", true)), false, "replay_stop 解除固定")
	_data_line("replay", "recording/帧增长/seek/pause/stop/seek 固定查看头，只读")

func _test_state_fields(_bridge_unused) -> void:
	_section_begin("7 state.fw_* 归一字段")
	var st = StateScript.new()
	st.framework = _bridge
	st.fw_sync(0.0)
	_eq(st.fw_ready, true, "state.fw_ready")
	_eq(st.fw_contacts.size(), 10, "state.fw_contacts 10")
	_ok(st.fw_tutorial.size() > 0, "state.fw_tutorial 非空")
	_ok(st.fw_flow.size() > 0, "state.fw_flow 非空")
	_ok(st.fw_damage.size() > 0, "state.fw_damage 非空")
	_ok(st.fw_replay.size() > 0, "state.fw_replay 非空")
	var selected_batch: String = st.fw_selected_batch()
	_ok(selected_batch != "", "fw_selected_batch 非空", selected_batch)
	_ok(st.fw_actions_target == selected_batch or st.fw_actions_target == "", "fw_actions_target 跟随选中",
		st.fw_actions_target)
	var acts: Array = st.fw_actions_for("2001")
	_ok(acts.size() >= 10, "state.fw_actions_for(2001)", str(acts.size()))
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["ready", "tutorial", "flow", "damage", "replay", "contacts", "actions",
			"decision_reason", "exec_window_s", "exec_left", "reputation", "last_action"]:
		_ok(bs.has(key), "fw_bridge_state 字段: " + key)
	# 损管 wrapper
	var rep: Dictionary = st.fw_start_repair("ir_false_alarm")
	_eq(bool(rep.get("ok", false)), true, "state.fw_start_repair(ir_false_alarm)")
	# 回放 wrapper
	var rp: Dictionary = st.fw_replay_start()
	_eq(bool(rp.get("playing", false)), true, "state.fw_replay_start")
	var seek_idx: Dictionary = st.fw_replay_seek_index(1)
	_ok(int(seek_idx.get("index", -1)) >= 0, "state.fw_replay_seek_index(1)")
	_eq(int(st.fw_replay.get("index", -1)), int(seek_idx.get("index", -2)), "state.fw_replay 帧号同步")
	st.fw_replay_stop()
	_data_line("state.fw_*", "ready/contacts=10/tutorial/flow/damage/replay/actions"
		+ "/actions_target/decision_reason/bridge_state/replay_seek_index")

func _test_v15_gate_and_flow() -> void:
	_section_begin("8 V15 决策门控 / 流程镜像")
	var st = StateScript.new()
	var br = BridgeScript.new()
	_ok(br.boot(), "新 bridge boot")
	st.framework = br
	# V15 prelude 由 V15 自己处理：直接跳过，聚焦门控
	if st.prelude_open:
		st.prelude_skip()
	st.fw_sync(0.0)
	_eq(st.fw_ready, true, "state 桥接 ready")
	# 把 V15 时钟推到决策窗口
	st.clock = st.clock - st.tau() + st.decision_t + 1.0
	st.refresh(st.clock)
	if _skip_tutorial:
		_eq(bool(st.decision_open), true, "env skip → 决策直接打开")
		_data_line("V15 gate", "DSH_SKIP_TUTORIAL=1 → 决策直开")
		return
	_eq(bool(st.decision_open), false, "教学未完成 → V15 决策被阻塞")
	_eq(bool(st.fw_decision_deferred), true, "fw_decision_deferred=true")
	_non_empty(st.fw_decision_reason, "fw_decision_reason: " + st.fw_decision_reason)
	# V15 原流程未被自动推进：仍需玩家动作
	var act1: Dictionary = st.fw_perform_action("crossfix", "2001")
	_eq(bool(act1.get("ok", false)), true, "fw_perform_action crossfix")
	_eq(bool(st.decision_open), false, "1 项识别仍不打开决策")
	var act2: Dictionary = st.fw_perform_action("model_ident", "2001")
	_eq(bool(act2.get("ok", false)), true, "fw_perform_action model_ident")
	_eq(bool(st.fw_tutorial_ready()), true, "tutorial ready")
	_eq(bool(st.decision_open), true, "教学完成后挂起的 V15 决策自动打开")
	_eq(st.fw_decision_reason, "", "decision_reason 清空")
	# V15 决策 → V2 镜像（choose_ending / submit_report）
	var ch: Dictionary = st.choose_ending("HOLD")
	_eq(String(ch.get("outcome", "")), "HOLD", "V15 choose_ending HOLD")
	_eq(bool(st.report_open), true, "V15 report_open")
	var flow: Dictionary = st.fw_flow
	var dec_view: Dictionary = flow.get("decision", {})
	var chosen: Dictionary = dec_view.get("decision", {})
	_eq(String(chosen.get("kind", "")), "HOLD", "V2 镜像 decision=HOLD")
	var sub: Dictionary = st.submit_report("TRUTH")
	_eq(bool(st.end_open), true, "V15 submit_report → END")
	_eq(bool(st.fw_flow.get("reputation_settled", false)), true, "V2 镜像 reputation_settled")
	var end: Dictionary = st.fw_flow.get("end", {})
	_eq(bool(end.get("ok", false)), true, "V2 end_summary.ok")
	_data_line("V15 gate", "gate 阻塞→跨 2 动作后自动开决策→HOLD/TRUTH 镜像到 V2")
