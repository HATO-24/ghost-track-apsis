extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# V17-CORE-3 probe：清算者无线电教学 + 传感器权威边界
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_core3_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const StateScript := preload("res://scripts/state.gd")
const BridgeScript := preload("res://scripts/framework_bridge.gd")
const RADIO_PATH := "res://framework/content/reclaimer_radio_l1.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("V17-CORE-3 PROBE · 清算者无线电 / 传感器权威边界")
	print("════════════════════════════════════════════════════════════")
	_test_content_file()
	_test_phase_gating_and_no_auto()
	_test_initiate_and_format()
	_test_reply_and_no_side_effects()
	_test_transcript_state()
	_test_sensor_authority()
	_test_restart_reset()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 CORE3 PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 CORE3 PROBE FAILED")
		quit(1)
	else:
		print("V17 CORE3 PROBE OK")
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

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _snapshot(st) -> Dictionary:
	return {
		"flags": JSON.stringify(st.flags),
		"evidence": JSON.stringify(st.evidence),
		"reputation": JSON.stringify(st.reputation),
		"decision_open": st.decision_open,
		"consequence_open": st.consequence_open,
		"report_open": st.report_open,
		"end_open": st.end_open,
		"civilians": st.civilians_evacuated,
		"radio": st.radio_feed.size(),
		"clock": st.clock,
	}

func _assert_same_state(before: Dictionary, st, label: String) -> void:
	_eq(JSON.stringify(st.flags), String(before.get("flags", "")), label + " · flags 不变")
	_eq(JSON.stringify(st.evidence), String(before.get("evidence", "")), label + " · evidence 不变")
	_eq(JSON.stringify(st.reputation), String(before.get("reputation", "")), label + " · reputation 不变")
	_eq(bool(st.decision_open), bool(before.get("decision_open", false)), label + " · decision 不变")
	_eq(bool(st.consequence_open), bool(before.get("consequence_open", false)), label + " · consequence 不变")
	_eq(bool(st.report_open), bool(before.get("report_open", false)), label + " · report 不变")
	_eq(bool(st.end_open), bool(before.get("end_open", false)), label + " · end 不变")
	_eq(bool(st.civilians_evacuated), bool(before.get("civilians", false)), label + " · 撤离状态不变")
	_eq(st.clock, float(before.get("clock", 0.0)), label + " · 时钟不变")

## 教学流程专属文本集合（区分 scenario 时间线自带的 T1-07 等清算者广播）。
func _flow_texts(st) -> Dictionary:
	var texts := {}
	var c: Dictionary = st.reclaimer_radio_content
	for raw in (c.get("exchange", []) as Array):
		texts[String((raw as Dictionary).get("text", ""))] = true
	for raw in (c.get("options", []) as Array):
		var o: Dictionary = raw
		for key in ["reply", "ack"]:
			var ln: Dictionary = (o.get(key, {}) as Dictionary) if o.get(key) is Dictionary else {}
			if not ln.is_empty():
				texts[String(ln.get("text", ""))] = true
	return texts

func _feed_flow_count(st) -> int:
	var texts := _flow_texts(st)
	var n := 0
	for raw in st.radio_feed:
		if texts.has(String((raw as Dictionary).get("text", ""))):
			n += 1
	return n

func _mode_ok(mode: String) -> bool:
	return mode == "LD" or mode == "LR" or mode == "RDO"

func _make_state():
	var st = StateScript.new()
	if st.prelude_open:
		st.prelude_skip()
	return st

func _goto_command(st) -> void:
	st.clock = st.T0 + 25.0
	st.refresh(st.clock)

# ═══════════════════════════════════════════════════════════════════
# 1. 内容文件 / schema
# ═══════════════════════════════════════════════════════════════════

func _test_content_file() -> void:
	_section_begin("1 内容文件")
	_ok(FileAccess.file_exists(RADIO_PATH), "内容文件存在: " + RADIO_PATH)
	var st = _make_state()
	var c: Dictionary = st.reclaimer_radio_content
	_ok(not c.is_empty(), "state 已装载清算者无线电内容")
	_eq(String(c.get("schema", "")), "reclaimer_radio.v1", "schema")
	_eq(String(c.get("id", "")), "l1_reclaimer_radio_v1", "内容 id（正式文件，非兜底）")
	_eq(String(c.get("trigger_phase", "")), "COMMAND", "trigger_phase=COMMAND")
	_ok(String(c.get("title", "")) != "", "标题非空")
	var exchange: Array = c.get("exchange", [])
	_ok(exchange.size() >= 3, "exchange 至少 3 条", "size=%d" % exchange.size())
	for raw in exchange:
		var line: Dictionary = raw
		_ok(String(line.get("from", "")) != "", "exchange from 非空")
		_ok(String(line.get("to", "")) != "", "exchange to 非空")
		_ok(_mode_ok(String(line.get("mode", ""))), "exchange mode 合法（LD/LR/RDO）",
			String(line.get("mode", "")))
		_ok(String(line.get("text", "")).strip_edges() != "", "exchange text 非空")
	var opts: Array = c.get("options", [])
	_eq(opts.size(), 3, "3 个回复选项")
	var codes: Array = []
	for raw in opts:
		var o: Dictionary = raw
		codes.append(String(o.get("code", "")))
		_ok(String(o.get("id", "")) != "", "选项 id 非空")
		_ok(String(o.get("label", "")) != "", "选项 label 非空")
		_ok(o.get("reply") is Dictionary, "选项含 reply 行", String(o.get("id", "")))
		var reply: Dictionary = o.get("reply", {})
		_eq(String(reply.get("from", "")), "远地点号", "玩家回复 from=远地点号")
		_ok(_mode_ok(String(reply.get("mode", ""))), "玩家回复 mode 合法")
	_ok("A" in codes and "B" in codes and "C" in codes, "选项编号 A/B/C")
	var guard: Dictionary = c.get("guardrails", {})
	_eq(bool(guard.get("manual_only", false)), true, "guardrails.manual_only=true")
	_eq(bool(guard.get("auto_complete", false)), false, "guardrails.auto_complete=false")
	_eq(bool(guard.get("changes_decision", true)), false, "guardrails.changes_decision=false")
	_data_line("content", "%s · exchange=%d · options=%d" % [String(c.get("id", "")),
		exchange.size(), opts.size()])

# ═══════════════════════════════════════════════════════════════════
# 2. 阶段门控 / 无自动完成
# ═══════════════════════════════════════════════════════════════════

func _test_phase_gating_and_no_auto() -> void:
	_section_begin("2 阶段门控 / 无自动完成")
	var st = _make_state()
	# READ 阶段不可用
	st.clock = st.T0 + 5.0
	st.refresh(st.clock)
	_eq(st.tut_phase, st.PHASE_READ, "t=5 处于 READ 阶段")
	_eq(st.reclaimer_radio_available(), false, "READ 阶段不可发起")
	var r0: Dictionary = st.reclaimer_radio_initiate()
	_eq(bool(r0.get("ok", true)), false, "READ 阶段 initiate 被拒绝")
	_ok(String(r0.get("reason", "")).contains("COMMAND"), "拒绝原因写明 COMMAND 阶段",
		String(r0.get("reason", "")))
	# COMMAND 阶段：可用，且不会自动触发
	st.clock = st.T0 + 25.0
	st.refresh(st.clock)
	_eq(st.tut_phase, st.PHASE_COMMAND, "t=25 处于 COMMAND 阶段")
	_eq(st.reclaimer_radio_available(), true, "COMMAND 阶段可发起")
	_eq(_feed_flow_count(st), 0, "未手动发起前 radio_feed 无教学流程通话（无自动完成）")
	# 时间推进/刷新多次也不应自动触发
	for tt in [40.0, 80.0, 120.0]:
		st.clock = st.T0 + float(tt)
		st.refresh(st.clock)
	_eq(_feed_flow_count(st), 0, "刷新/推进 3 次仍无教学流程通话（不自动完成）")
	_eq(st.reclaimer_radio_stage, "idle", "流程仍为 idle（需手动 initiate）")
	_eq(st.reclaimer_radio_available(), true, "仍未发起，仍可手动发起")
	var stt: Dictionary = st.reclaimer_radio_state()
	_eq(bool(stt.get("available", false)), true, "state.available=true")
	_eq(String(stt.get("phase", "")), "COMMAND", "state.phase=COMMAND")
	_eq(bool(stt.get("open", true)), false, "state.open=false")
	var opts: Array = stt.get("options", [])
	_eq(opts.size(), 3, "state.options=3")
	for raw in opts:
		_eq(bool((raw as Dictionary).get("enabled", true)), false, "未开启时选项 disabled")
		_ok(String((raw as Dictionary).get("reason", "")) != "", "未开启时选项给 reason")
	_data_line("gating", "READ 拒绝 · COMMAND 可发起 · 0 次自动触发（3 次刷新验证）")

# ═══════════════════════════════════════════════════════════════════
# 3. initiate / 标准格式 / radio_feed / 日志
# ═══════════════════════════════════════════════════════════════════

func _test_initiate_and_format() -> void:
	_section_begin("3 initiate / 通信格式 / radio_feed")
	var st = _make_state()
	_goto_command(st)
	# 格式 helper 与 docs/19 示例一致
	var sample := st.format_radio_line("哈马丹号", "远地点号", "LD",
		"[9001] 敌我识别未应答，须进一步确认。完毕。")
	_eq(sample, "[哈马丹号至远地点号]-[LD]-[[9001] 敌我识别未应答，须进一步确认。完毕。]",
		"标准格式 [from至to]-[mode]-[text]（docs/19 §1 示例）")
	var before: Dictionary = _snapshot(st)
	var feed_before: int = st.radio_feed.size()
	var log_newest_before := String((st.log_lines[0] as Dictionary).get("text", "")) if not st.log_lines.is_empty() else ""
	_ok(st.log_lines.size() <= 6, "日志窗口上限 6 条（既有行为）", "size=%d" % st.log_lines.size())
	var r: Dictionary = st.reclaimer_radio_initiate()
	_eq(bool(r.get("ok", false)), true, "COMMAND 阶段 initiate 成功")
	_eq(String(r.get("stage", "")), "open", "initiate 后 stage=open")
	var lines: Array = r.get("lines", [])
	var exchange: Array = st.reclaimer_radio_content.get("exchange", [])
	_eq(lines.size(), exchange.size(), "写入条目数=内容 exchange 数")
	_eq(st.radio_feed.size(), feed_before + exchange.size(), "radio_feed 增加对应条目")
	_ok(not st.log_lines.is_empty(), "日志非空")
	var log_newest_after := String((st.log_lines[0] as Dictionary).get("text", ""))
	_ok(log_newest_after != log_newest_before, "日志更新", log_newest_after)
	_ok(log_newest_after.contains("无线电教学"), "最新日志为教学流程", log_newest_after)
	_assert_same_state(before, st, "initiate")
	# 逐条：from/to/mode/text/format 与内容一致
	var offset: int = st.radio_feed.size() - exchange.size()
	for i in range(exchange.size()):
		var expect: Dictionary = exchange[i]
		var got: Dictionary = st.radio_feed[offset + i]
		_eq(String(got.get("from", "")), String(expect.get("from", "")), "feed[%d].from" % i)
		_eq(String(got.get("to", "")), String(expect.get("to", "")), "feed[%d].to" % i)
		_eq(String(got.get("mode", "")), String(expect.get("mode", "")), "feed[%d].mode" % i)
		_eq(String(got.get("text", "")), String(expect.get("text", "")), "feed[%d].text" % i)
		_ok(_mode_ok(String(got.get("mode", ""))), "feed[%d] mode ∈ LD/LR/RDO" % i)
		var formatted := st.format_radio_line(String(got.get("from", "")), String(got.get("to", "")),
			String(got.get("mode", "")), String(got.get("text", "")))
		_ok(formatted.begins_with("[" + String(got.get("from", "")) + "至"), "feed[%d] 格式前缀" % i)
		_ok(formatted.contains("]-[" + String(got.get("mode", "")) + "]-["), "feed[%d] 格式链路段" % i)
	# 日志里能看到标准格式字符串
	var found_log := false
	for raw in st.log_lines:
		var ln: Dictionary = raw
		if String(ln.get("text", "")).contains("至") and String(ln.get("text", "")).contains("]-["):
			found_log = true
			break
	_ok(found_log, "日志含标准格式通信行")
	# 不可重复发起
	_eq(st.reclaimer_radio_available(), false, "发起后 available=false")
	var r2: Dictionary = st.reclaimer_radio_initiate()
	_eq(bool(r2.get("ok", true)), false, "重复 initiate 被拒绝")
	var stt: Dictionary = st.reclaimer_radio_state()
	_eq(bool(stt.get("open", false)), true, "state.open=true")
	_eq(stt.get("options", []).size(), 3, "state.options 仍 3 项")
	for raw in (stt.get("options", []) as Array):
		_eq(bool((raw as Dictionary).get("enabled", false)), true, "开启时选项 enabled")
	_data_line("initiate", "feed +%d · 日志窗口更新 · %d 条均符合格式" % [exchange.size(), exchange.size()])

# ═══════════════════════════════════════════════════════════════════
# 4. reply / 无副作用
# ═══════════════════════════════════════════════════════════════════

func _test_reply_and_no_side_effects() -> void:
	_section_begin("4 reply / 无副作用")
	var st = _make_state()
	_goto_command(st)
	var r: Dictionary = st.reclaimer_radio_initiate()
	_eq(bool(r.get("ok", false)), true, "initiate 成功")
	var before: Dictionary = _snapshot(st)
	var feed_before: int = st.radio_feed.size()
	var invalid: Dictionary = st.reclaimer_radio_reply("Z")
	_eq(bool(invalid.get("ok", true)), false, "未知选项被拒绝")
	_eq(String(invalid.get("reason", "")).contains("未知"), true, "拒绝原因含未知选项",
		String(invalid.get("reason", "")))
	_eq(st.reclaimer_radio_stage, "open", "无效回复后 stage 仍 open")
	var rep: Dictionary = st.reclaimer_radio_reply("A")
	_eq(bool(rep.get("ok", false)), true, "有效回复 rep.ok")
	_eq(String(rep.get("choice", "")), "ack", "选择 id=ack")
	_eq(String(rep.get("stage", "")), "done", "回复后 stage=done")
	var lines: Array = rep.get("lines", [])
	_ok(lines.size() >= 2, "回复写入 reply+ack 行", "lines=%d" % lines.size())
	_eq(st.radio_feed.size(), feed_before + lines.size(), "radio_feed 增加回复条目")
	_assert_same_state(before, st, "reply")
	# 首条为本舰发出（dir=tx）
	var first: Dictionary = lines[0]
	_eq(String(first.get("dir", "")), "tx", "首条 dir=tx（本舰发出）")
	_eq(String(first.get("from", "")), "远地点号", "回复 from=远地点号")
	_ok(_mode_ok(String(first.get("mode", ""))), "回复 mode 合法")
	# 末条为清算者 ack（rx）
	var last: Dictionary = lines[lines.size() - 1]
	_eq(String(last.get("dir", "")), "rx", "末条 dir=rx（清算者回应）")
	_eq(st.reclaimer_radio_available(), false, "done 后 available=false")
	var r3: Dictionary = st.reclaimer_radio_reply("B")
	_eq(bool(r3.get("ok", true)), false, "通话结束后 reply 被拒绝")
	var init2: Dictionary = st.reclaimer_radio_initiate()
	_eq(bool(init2.get("ok", true)), false, "通话结束后不可再次 initiate（一次流程）")
	# 进入 DECIDE 后不可用
	st.clock = st.T0 + st.decision_t + 1.0
	st.refresh(st.clock)
	_eq(bool(st.decision_open), true, "推进到裁决窗口（framework 未接时直接打开）")
	_eq(st.reclaimer_radio_available(), false, "DECIDE 阶段不可发起")
	_data_line("reply", "未知选项拒绝 · A 回复写 %d 条 · 无 flags/证据/声望/时钟副作用" % lines.size())

# ═══════════════════════════════════════════════════════════════════
# 5. transcript / state 只读字段
# ═══════════════════════════════════════════════════════════════════

func _test_transcript_state() -> void:
	_section_begin("5 transcript / state")
	var st = _make_state()
	_goto_command(st)
	st.reclaimer_radio_initiate()
	st.reclaimer_radio_reply("B")
	var stt: Dictionary = st.reclaimer_radio_state()
	_eq(String(stt.get("stage", "")), "done", "state.stage=done")
	_eq(String(stt.get("choice", "")), "query", "state.choice=query")
	_eq(bool(stt.get("open", true)), false, "state.open=false")
	_eq(bool(stt.get("content_loaded", false)), true, "state.content_loaded")
	_ok(String(stt.get("content_id", "")) != "", "state.content_id 非空")
	_ok(String(stt.get("title", "")) != "", "state.title 非空")
	_ok((stt.get("transcript", []) as Array).size() >= 5, "transcript ≥5 条",
		"size=%d" % (stt.get("transcript", []) as Array).size())
	var formatted: Array = stt.get("formatted_transcript", [])
	_eq(formatted.size(), (stt.get("transcript", []) as Array).size(), "formatted_transcript 等长")
	for s in formatted:
		_ok(String(s).begins_with("[") and String(s).contains("]-["), "transcript 条目为标准格式",
			String(s).substr(0, 40))
	var lines: Array = st.reclaimer_radio_transcript_lines()
	_eq(lines.size(), (stt.get("transcript", []) as Array).size(), "transcript_lines 等长")
	var dirs: Array = []
	for raw in lines:
		dirs.append(String((raw as Dictionary).get("dir", "")))
	_ok("tx" in dirs and "rx" in dirs, "transcript 含 tx/rx 方向")
	_data_line("transcript", "%d 条（initiate 3 + reply/ack 2），含 tx/rx" % lines.size())

# ═══════════════════════════════════════════════════════════════════
# 6. 传感器权威边界
# ═══════════════════════════════════════════════════════════════════

func _test_sensor_authority() -> void:
	_section_begin("6 传感器权威边界")
	var st = _make_state()
	_goto_command(st)
	_eq(st.sensor_authority, "legacy_v15", "state.sensor_authority=legacy_v15")
	var note := st.sensor_authority_note()
	_ok(note.contains("sensor_model"), "authority note 指明 V15 sensor_model", note)
	var sel_before := int((st.tracks[st.selected] as Dictionary).get("level", 0))
	var adv: Dictionary = st.v2_sensor_advisory()
	_eq(String(adv.get("authority", "")), "legacy_v15", "advisory.authority=legacy_v15")
	_eq(String(adv.get("role", "")), "advisory_data_demo", "advisory.role=advisory_data_demo")
	_eq(bool(adv.get("switching", true)), false, "advisory.switching=false（不切换）")
	_eq(bool(adv.get("v2_ready", true)), false, "无 bridge 时 v2_ready=false")
	_eq((adv.get("v2_sources", []) as Array).size(), 3, "v2_sources=radar/tws/optical")
	var v15: Dictionary = adv.get("v15", {})
	_eq(int(v15.get("selected_level", 0)), sel_before, "advisory 引用 V15 接触等级")
	_eq(int((st.tracks[st.selected] as Dictionary).get("level", 0)), sel_before,
		"调用 advisory 不改变 V15 等级")
	_eq(st.sensor, int(v15.get("sensor", -1)), "advisory 不改变 V15 传感器选择")
	# 接 bridge 后：升为数据摘要，但权威仍是 legacy_v15
	var br = BridgeScript.new()
	_ok(br.boot(), "bridge boot")
	st.framework = br
	st.fw_sync(0.0)
	var adv2: Dictionary = st.v2_sensor_advisory()
	_eq(bool(adv2.get("v2_ready", false)), true, "接 bridge 时 v2_ready=true")
	_eq(String(adv2.get("authority", "")), "legacy_v15", "接 bridge 后 authority 仍 legacy_v15")
	_eq(int(adv2.get("v2_contact_count", -1)), 10, "advisory 提供 V2 接触数（10）")
	_eq(bool(adv2.get("switching", true)), false, "接 bridge 后仍不切换")
	_eq(int((st.tracks[st.selected] as Dictionary).get("level", 0)), sel_before,
		"接 bridge 后 V15 等级不变")
	st.framework = null
	_data_line("authority", "legacy_v15 · role=advisory_data_demo · switching=false · bridge 时 v2_contacts=10")

# ═══════════════════════════════════════════════════════════════════
# 7. restart 复位
# ═══════════════════════════════════════════════════════════════════

func _test_restart_reset() -> void:
	_section_begin("7 restart 复位")
	var st = _make_state()
	_goto_command(st)
	st.reclaimer_radio_initiate()
	st.reclaimer_radio_reply("C")
	_eq(st.reclaimer_radio_stage, "done", "先完成一次通话")
	st.restart_demo()
	_eq(st.reclaimer_radio_stage, "idle", "restart 后 stage=idle")
	_eq(st.reclaimer_radio_transcript.size(), 0, "restart 后 transcript 清空")
	_eq(bool(st.reclaimer_radio_open), false, "restart 后 open=false")
	_ok(not st.reclaimer_radio_content.is_empty(), "restart 后内容重新装载")
	_ok(String(st.reclaimer_radio_content.get("id", "")) != "", "restart 后内容 id 非空")
	if st.prelude_open:
		st.prelude_skip()
	st.clock = st.T0 + 25.0
	st.refresh(st.clock)
	_eq(st.reclaimer_radio_available(), true, "restart 后可再次发起（演示重开）")
	_data_line("restart", "stage/transcript/open 复位，内容重载，可再次发起")
