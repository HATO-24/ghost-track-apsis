extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2 flow probe（第一关端到端）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v16" --script res://tests/flow_probe.gd
#
# 覆盖：PRELUDE → COMMAND → 动作（7 支持动作 / 武器 unsupported）→ 证据任务
#       （遥测+黑匣子并行 / 穿梭机互斥 / ELINT / 撤离）→ DECISION（EXPOSE gating /
#       HOLD / FIRE）→ REPORT（truth/fake + AUDIT FLAG）→ END → RESTART；
#       自动时间线（story events/radio）、mission flag 联动、时间冻结。
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const SCENARIO := "res://content/scenario_l1_v2.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("V2-CORE-2 FLOW PROBE · 第一关端到端")
	print("════════════════════════════════════════════════════════════")
	_test_prelude()
	_test_actions()
	_test_evidence()
	_test_decision_report_restart()
	_test_expose_gating()
	_test_fire_branch()
	_test_timeline_and_mission()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V2-CORE-2 FLOW PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("FLOW PROBE FAILED")
		quit(1)
	else:
		print("FLOW PROBE OK")
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

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _new_session() -> Dictionary:
	var s := V2Scenario.load_file(SCENARIO)
	var w := V2World.new()
	var ok := w.load_scenario(s)
	var m := V2Mission.from_scenario(s)
	w.attach_mission(m)
	return {"world": w, "mission": m, "scenario": s, "ok": ok}

## 跳过前置航行（走正式 skip 流程，保持 flag/时间语义）。
func _skip_prelude(w: V2World) -> void:
	w.prelude_skip()

## 推进到 COMMAND（两次 advance：PRELUDE→READ→COMMAND）。
func _to_command(w: V2World) -> void:
	_skip_prelude(w)
	w.advance(0.01)
	w.advance(0.01)

## 推进到 DECISION（COMMAND 阶段打开决策后 advance 一次）。
func _to_decision(w: V2World) -> void:
	_to_command(w)
	w.open_decision()
	w.advance(0.01)

func _timeline_events(w: V2World) -> Array:
	var out: Array = []
	for raw in w.events:
		var d: Dictionary = raw
		if String(d.get("kind", "")).begins_with("timeline:"):
			out.append(d)
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. PRELUDE：路由/窗口/执行/跳过 + 时间冻结
# ═══════════════════════════════════════════════════════════════════

func _test_prelude() -> void:
	_section_begin("1 PRELUDE 前置航行")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_ok(bool(sess["ok"]), "V2 场景装载", str(w.errors))
	_eq(w.t, 0.0, "初始时间 0")
	_eq(bool(w.vm_state().get("prelude_open", false)), true, "前置航行默认打开")
	_eq(bool(w.vm_state().get("time_frozen", false)), true, "前置航行期间时间冻结")
	_eq(m.phase, "prelude", "mission 起始阶段 prelude")

	# 冻结：advance 不推进时间、不触发时间线
	var out := w.advance(100.0)
	_eq(w.t, 0.0, "前置航行期间 advance 不推进时间")
	_eq(bool(out.get("frozen", false)), true, "advance 返回 frozen=true")
	_eq(_timeline_events(w).size(), 0, "冻结时不触发时间线事件")

	# 冻结期间不允许识别动作
	var pre_action := w.perform_action("crossfix", "2001")
	_eq(bool(pre_action.get("ok", true)), false, "前置航行未完成时拒绝 perform_action")
	_ok(String(pre_action.get("reason", "")).contains("前置航行"), "拒绝原因明确", String(pre_action.get("reason", "")))

	# 目的地
	var wrong_route := w.prelude_choose_route("karman")
	_eq(bool(wrong_route.get("ok", true)), false, "错误目的地被拒绝（Karman）")
	_non_empty(String(wrong_route.get("reason", "")), "错误目的地提示来自数据: " + String(wrong_route.get("reason", "")))
	_eq(int(w.prelude_state().get("step", -1)), 0, "错误选择不推进步骤")
	var route := w.prelude_choose_route("meridian")
	_eq(bool(route.get("ok", false)), true, "选择正确目的地 Meridian")
	_eq(int(w.prelude_state().get("step", 0)), 1, "步骤 → 1（变轨窗口）")
	# 窗口
	var wrong_win := w.prelude_choose_window("t0200")
	_eq(bool(wrong_win.get("ok", true)), false, "错误窗口被拒绝（T+02:00）")
	var win := w.prelude_choose_window("t1800")
	_eq(bool(win.get("ok", false)), true, "选择正确窗口 T+18:00")
	_eq(int(w.prelude_state().get("step", 0)), 2, "步骤 → 2（可执行）")
	_eq(bool(w.prelude_confirm().get("ok", false)), true, "确认选择")
	var radio_before := w.radio.size()
	var exec := w.prelude_execute()
	_eq(bool(exec.get("ok", false)), true, "执行点火")
	_eq(float(exec.get("dv_spent_ms", 0.0)), 120.0, "Δv 扣除 = 路由 120 + 窗口 0")
	_eq(bool(w.prelude_state().get("executed", false)), true, "prelude.executed")
	_eq(bool(w.vm_state().get("time_frozen", true)), false, "执行后时间开始流动")
	_eq(bool(w.flow_flags.get("prelude_executed", false)), true, "flag prelude_executed")
	_eq(bool(m.has_flag("prelude_executed")), true, "mission flag 联动：prelude_executed")
	_ok(w.radio.size() > radio_before, "执行后写入离港通信", "%d → %d" % [radio_before, w.radio.size()])

	# 时间流动后自动推进阶段
	w.advance(0.01)
	_eq(m.kind, "READ", "PRELUDE → READ")
	w.advance(0.01)
	_eq(m.kind, "COMMAND", "READ → COMMAND")
	_data_line("prelude", "route=meridian window=t1800 dv=120ms phase=%s" % m.kind)

# ═══════════════════════════════════════════════════════════════════
# 2. perform_action：7 个支持动作 + 武器 unsupported + 不伪造 L4
# ═══════════════════════════════════════════════════════════════════

func _test_actions() -> void:
	_section_begin("2 perform_action（7 动作）")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_command(w)
	_eq(m.kind, "COMMAND", "进入 COMMAND 阶段")
	var tr: V2Track = w.track_for("2001")
	_eq(tr.level, 1, "2001 初始 L1")
	_eq(tr.observation_count, 0, "时间线不自动做识别动作（观测计数 0）")
	var order_before := w.orders.all().size()

	# crossfix → L2
	var a1 := w.perform_action("crossfix", "2001")
	_eq(bool(a1.get("ok", false)), true, "crossfix 执行", String(a1.get("reason", "")))
	_eq(int(a1.get("level", 0)), 2, "crossfix → L2")
	_eq(tr.level, 2, "航迹等级 L2")
	_ok(tr.range_km > 0.0, "L2 有距离解", "range=%.1f km" % tr.range_km)

	# radar_illum（L2 维持，刷新位置）
	var a2 := w.perform_action("radar_illum", "2001")
	_eq(bool(a2.get("ok", false)), true, "radar_illum 执行")
	_eq(int(a2.get("level", 0)), 2, "radar_illum 维持 L2")
	_non_empty(String(a2.get("sensor", "")), "观测带传感器型号: " + String(a2.get("sensor", "")))

	# model_ident → L3 分类
	var a3 := w.perform_action("model_ident", "2001")
	_eq(bool(a3.get("ok", false)), true, "model_ident 执行", String(a3.get("reason", "")))
	_eq(int(a3.get("level", 0)), 3, "model_ident → L3")
	_eq(String(tr.classification.get("ship_class", "")), "传唤级", "L3 分类 = 传唤级")

	# radar_track / optical_channel / ir_channel（保持 L3；IR 不降级）
	var a4 := w.perform_action("radar_track", "2001")
	_eq(bool(a4.get("ok", false)), true, "radar_track 执行（L3 可用）")
	var a5 := w.perform_action("optical_channel", "2001")
	_eq(bool(a5.get("ok", false)), true, "optical_channel 执行")
	var a6 := w.perform_action("ir_channel", "2001")
	_eq(bool(a6.get("ok", false)), true, "ir_channel 执行")
	_eq(tr.level, 3, "IR/雷达通道不改变 L3（不降级）")

	# IFF：2001 不应答 → 不伪造 L4
	var a7 := w.perform_action("iff_query", "2001")
	_eq(bool(a7.get("ok", false)), true, "iff_query 执行", String(a7.get("reason", "")))
	_ok(tr.level <= 3, "2001 IFF 无应答不升 L4（不伪造）", "level=%d" % tr.level)
	_eq(tr.iff_status, "no_reply", "IFF 无应答状态")
	_ok(tr.identity_kind != "friend" and tr.identity_kind != "hostile", "无应答不给友方/敌方身份",
		"identity=" + tr.identity_kind)

	# 友方 IFF → L4 证据
	var friend_iff := w.perform_action("iff_query", "1000")
	_eq(bool(friend_iff.get("ok", false)), true, "友方 IFF 询问", String(friend_iff.get("reason", "")))
	var fr := w.track_for("1000")
	_eq(fr.level, 4, "友方 IFF → L4")
	_eq(fr.identity_kind, "friend", "友方身份")
	_eq(fr.iff_status, "friend", "IFF friend")

	# 民用不明目标 L1：IFF 被等级门控拒绝（不会伪造 L4）
	var ceres_iff := w.perform_action("iff_query", "9001")
	_eq(bool(ceres_iff.get("ok", true)), false, "L1 不明目标 IFF 被等级门控拒绝")
	_eq(String(ceres_iff.get("reason_code", "")), "level", "拒绝原因 reason_code=level")
	var ceres := w.track_for("9001")
	_eq(ceres.level, 1, "不明目标保持 L1（不伪造 L4）")

	# 无实体回波：只刷新方位，不伪造 L2
	var phantom := w.perform_action("crossfix", "9002")
	_eq(bool(phantom.get("ok", false)), true, "无实体回波 crossfix 执行")
	var ph := w.track_for("9002")
	_eq(ph.level, 1, "无实体回波保持 L1（不伪造位置）")
	_ok(String(phantom.get("detail", "")).contains("仅方位"), "detail 说明仅方位")

	# 武器类 → unsupported，不产生状态/命令
	var orders_mid := w.orders.all().size()
	var fire := w.perform_action("fire_control", "2001")
	_eq(bool(fire.get("ok", true)), false, "武器类动作明确 unsupported")
	_eq(String(fire.get("reason_code", "")), "unsupported", "reason_code=unsupported")
	_non_empty(String(fire.get("reason", "")), "unsupported 原因非空")
	_eq(w.orders.all().size(), orders_mid, "武器类动作不产生命令记录")
	_eq(tr.level, 3, "武器类动作不改变等级")

	# 未知动作
	var unknown := w.perform_action("no_such_action", "2001")
	_eq(bool(unknown.get("ok", true)), false, "未知动作被拒绝")

	# 命令审计：每个成功动作一条 DONE 命令
	var all_orders := w.orders.all()
	_ok(all_orders.size() >= 9, "动作生成命令审计记录（DONE）", "orders=%d" % all_orders.size())
	var done_count := 0
	for raw in all_orders:
		var o: V2Orders.Order = raw
		if o.state == "DONE":
			done_count += 1
	_ok(done_count >= 9, "审计命令均为 DONE", "done=%d" % done_count)
	_data_line("actions", "7 支持动作执行，orders=%d（含友方/民用/回波审计），2001 level=%d identity=%s" % [
		all_orders.size(), tr.level, tr.identity_kind])

# ═══════════════════════════════════════════════════════════════════
# 3. 证据任务：并行遥测/ELINT、穿梭机互斥、撤离
# ═══════════════════════════════════════════════════════════════════

func _test_evidence() -> void:
	_section_begin("3 证据任务")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_command(w)
	_eq(w.evidence_count(), 0, "初始证据 0")
	_eq(w.can_expose(), false, "证据不足不可曝光")

	# 远程任务并行 + 穿梭机占用
	_eq(bool(w.start_evidence("port_telemetry").get("ok", false)), true, "开始港务遥测（远程）")
	_eq(bool(w.start_evidence("elint_signature").get("ok", false)), true, "开始 ELINT 特征码（远程并行）")
	_eq(bool(w.start_evidence("inspection_blackbox").get("ok", false)), true, "开始核查组黑匣子（穿梭机）")
	var busy := w.start_evidence("evacuation")
	_eq(bool(busy.get("ok", true)), false, "穿梭机互斥：撤离任务被拒绝")
	_ok(String(busy.get("reason", "")).contains("穿梭机"), "互斥原因写明穿梭机占用", String(busy.get("reason", "")))
	var dup := w.start_evidence("port_telemetry")
	_eq(bool(dup.get("ok", true)), false, "重复开始任务被拒绝")

	# 推进：遥测 30 s 完成；ELINT 45 s
	w.advance(30.5)
	_eq(w.evidence_count(), 1, "遥测完成（30 s）")
	_eq(String((w.evidence["port_telemetry"] as Dictionary).get("state", "")), "done", "遥测状态 done")
	_ok(w.evidence_remaining("elint_signature") > 0.0, "ELINT 仍在进行（剩余 > 0）")
	var vm_ev := w.vm_evidence()
	var progress_ok := false
	for raw in vm_ev:
		var d: Dictionary = raw
		if String(d.get("id", "")) == "elint_signature":
			progress_ok = float(d.get("progress", 0.0)) > 0.0 and float(d.get("progress", 0.0)) < 1.0
	_ok(progress_ok, "vm_evidence 提供 progress")
	w.advance(15.0)
	_eq(w.evidence_count(), 2, "ELINT 完成（45 s）")
	_eq(w.can_expose(), true, "2 件证据 → 可曝光（EXPOSE gating 数据来自 policy）")

	# 黑匣子 75 s 完成后，穿梭机空出 → 撤离 60 s
	w.advance(30.0)
	_eq(w.evidence_count(), 3, "黑匣子完成（75 s）")
	_eq(bool(w.start_evidence("evacuation").get("ok", false)), true, "黑匣子完成后启动撤离（穿梭机空出）")
	w.advance(60.0)
	_eq(w.evidence_count(), 4, "撤离完成（60 s）")
	_eq(w.civilians_evacuated, true, "撤离完成置 civilians_evacuated")
	_eq(bool(w.flow_flags.get("civilians_evacuated", false)), true, "flag civilians_evacuated")
	_eq(bool(m.has_flag("civilians_evacuated")), true, "mission flag 联动 civilians_evacuated")
	_data_line("evidence", "4/4 完成；遥测+ELINT 并行、黑匣子/撤离共用穿梭机（互斥）")

# ═══════════════════════════════════════════════════════════════════
# 4. 决策 / 报告 / END / RESTART（HOLD + 伪造报告）
# ═══════════════════════════════════════════════════════════════════

func _test_decision_report_restart() -> void:
	_section_begin("4 决策/报告/END/RESTART")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_command(w)

	# 决策未打开时拒绝
	_eq(bool(w.choose_ending("HOLD").get("ok", true)), false, "决策未打开时 choose_ending 被拒绝")
	w.open_decision()
	_eq(bool(w.flow.get("decision_open", false)), true, "open_decision 打开决策")
	w.advance(0.01)
	_eq(m.kind, "DECISION", "mission 进入 DECISION")
	var dec := w.vm_decision()
	_non_empty(String(dec.get("prompt", "")), "决策提示来自 story.decision_prompt")
	_eq((dec.get("options", []) as Array).size(), 4, "决策选项 3 结局 + FIRE 灾难分支")
	_eq(bool(m.has_flag("decision_open")), true, "mission flag 联动 decision_open")

	# HOLD（内容结局）
	var hold := w.choose_ending("HOLD")
	_eq(bool(hold.get("ok", false)), true, "选择结局 HOLD", String(hold.get("reason", "")))
	_eq(String(hold.get("kind", "")), "HOLD", "结局 kind")
	_ok(not (hold.get("reply", {}) as Dictionary).is_empty(), "结局回复通信来自 story.decision_replies")
	_eq(bool(hold.get("fire_release", true)), false, "HOLD 不触发武器释放")
	_eq(bool(m.has_flag("decision_made")), true, "mission flag 联动 decision_made")

	# 报告：伪造
	_eq(bool(w.report_state().get("available", false)), true, "报告可提交")
	var fake := w.submit_report(false)
	_eq(bool(fake.get("ok", false)), true, "提交伪造报告", String(fake.get("reason", "")))
	_eq(bool(fake.get("audit_flag", false)), true, "伪造报告置 AUDIT FLAG")
	_eq(int(w.audit_count), 1, "audit_count=1")
	_eq(bool(w.flow_flags.get("audit_flag", false)), true, "flag audit_flag")
	var report: Dictionary = fake.get("report", {})
	_eq(String(report.get("mode", "")), "fake", "报告模式 fake")
	_non_empty(String(report.get("text", "")), "报告正文非空")
	var end := w.end_summary()
	_eq(bool(end.get("ok", false)), true, "end_summary 可用")
	_eq(String(end.get("ending_kind", "")), "HOLD", "end_summary 结局 HOLD")
	_eq(bool(end.get("audit_flag", false)), true, "end_summary 带 audit_flag")
	_ok(String(end.get("mission_kind", "")) == "END", "mission 推进到 END", String(end.get("mission_kind", "")))
	_eq(bool(w.flow.get("ended", false)), true, "flow.ended=true")
	# 结束后时间冻结、动作拒绝
	var t_end: float = w.t
	var frozen := w.advance(10.0)
	_eq(bool(frozen.get("frozen", false)), true, "END 后时间冻结")
	_eq(w.t, t_end, "END 后 advance 不推进时间")
	_eq(bool(w.perform_action("crossfix", "2001").get("ok", true)), false, "END 后拒绝动作")
	_eq(bool(w.submit_report(true).get("ok", true)), false, "报告不可重复提交")

	# 重开
	var before_entities := w.entities.size()
	var r := w.restart()
	_eq(bool(r.get("ok", false)), true, "restart 成功", str(r.get("errors", [])))
	_eq(w.t, 0.0, "重开时间复位 0")
	_eq(bool(w.vm_state().get("ended", false)), false, "重开 ended=false")
	_eq(w.evidence_count(), 0, "重开证据复位 0")
	_eq(w.audit_count, 0, "重开 audit_count=0")
	_eq(w.entities.size(), before_entities, "重开实体数不变")
	_eq(w.tracks.count(), 8, "重开航迹 8")
	_eq(bool(w.prelude_open()), true, "重开前置航行重新打开")
	_eq(m.phase, "prelude", "重开 mission 回到 prelude")
	_eq(m.has_flag("report_submitted"), false, "重开 mission flags 清空")
	_eq(bool(w.flow_flags.is_empty()), true, "重开流程 flags 清空")
	_data_line("report", "HOLD + fake report：audit_flag=true, mission→END, restart 复位")

# ═══════════════════════════════════════════════════════════════════
# 5. EXPOSE gating
# ═══════════════════════════════════════════════════════════════════

func _test_expose_gating() -> void:
	_section_begin("5 EXPOSE gating")
	var sess := _new_session()
	var w: V2World = sess["world"]
	_to_decision(w)
	# 证据不足：EXPOSE 禁用且拒绝
	var dec := w.vm_decision()
	var expose_disabled := false
	var expose_reason := ""
	for raw in (dec.get("options", []) as Array):
		var o: Dictionary = raw
		if String(o.get("kind", "")) == "EXPOSE":
			expose_disabled = not bool(o.get("enabled", true))
			expose_reason = String(o.get("reason", ""))
	_ok(expose_disabled, "证据不足时 EXPOSE 选项禁用")
	_ok(expose_reason.contains("证据不足"), "禁用原因写明证据不足", expose_reason)
	var rej := w.choose_ending("EXPOSE")
	_eq(bool(rej.get("ok", true)), false, "证据不足时 choose_ending(EXPOSE) 被拒绝")
	_ok(String(rej.get("reason", "")).contains("证据不足"), "拒绝原因明确", String(rej.get("reason", "")))
	var decided: Dictionary = w.flow.get("decision", {})
	_ok(decided.is_empty(), "拒绝后未记录决策")

	# 补足证据后 EXPOSE 成功
	w.evidence_complete("port_telemetry")
	w.evidence_complete("inspection_blackbox")
	_eq(w.can_expose(), true, "补足 2 件证据")
	var expose := w.choose_ending("EXPOSE")
	_eq(bool(expose.get("ok", false)), true, "证据足够后 EXPOSE 成功", String(expose.get("reason", "")))
	_eq(String(expose.get("kind", "")), "EXPOSE", "结局 EXPOSE")
	_eq(bool(w.flow.get("fire_release", true)), false, "EXPOSE 不触发武器释放")
	var end := w.end_summary()
	_eq(bool(end.get("can_expose", false)), true, "end_summary can_expose")
	_eq(String(end.get("ending_kind", "")), "EXPOSE", "end_summary EXPOSE")

# ═══════════════════════════════════════════════════════════════════
# 6. FIRE 灾难分支
# ═══════════════════════════════════════════════════════════════════

func _test_fire_branch() -> void:
	_section_begin("6 FIRE 灾难分支")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_decision(w)
	var fire := w.choose_ending("FIRE")
	_eq(bool(fire.get("ok", false)), true, "选择 FIRE（灾难分支）", String(fire.get("reason", "")))
	_eq(bool(fire.get("fire_release", false)), true, "FIRE 置武器释放")
	_non_empty(String(fire.get("consequence", "")), "灾难后果文本来自 story.consequence_fire")
	_eq(bool(m.has_flag("fire_release")), true, "mission flag 联动 fire_release")
	var radio_hit := false
	for raw in w.radio:
		if String((raw as Dictionary).get("text", "")).contains("武器释放"):
			radio_hit = true
	_ok(radio_hit, "开火回复写入通信流（story.decision_replies.FIRE）")
	# mission 进入 CONSEQUENCE
	w.advance_mission(1)
	_eq(m.kind, "CONSEQUENCE", "FIRE 后 mission 进入 CONSEQUENCE")
	_non_empty(m.prompt().get("text", ""), "后果提示来自 story.consequence_fire")
	# 报告：如实
	var truth := w.submit_report(true)
	_eq(bool(truth.get("ok", false)), true, "提交如实报告")
	_eq(bool(truth.get("audit_flag", true)), false, "如实报告无 AUDIT FLAG")
	var report: Dictionary = truth.get("report", {})
	_non_empty(String(report.get("text", "")), "报告正文非空")
	_ok(String(report.get("text", "")).contains("火灾") or String(report.get("text", "")).contains("储罐"),
		"FIRE 报告正文为灾难描述")
	var end := w.end_summary()
	_eq(bool(end.get("fire_release", false)), true, "end_summary fire_release")
	_non_empty(String(end.get("consequence", "")), "end_summary 带灾难后果")
	_eq(String(end.get("ending_kind", "")), "FIRE", "end_summary 结局 FIRE")
	_ok(String(end.get("mission_kind", "")) == "END", "FIRE 流程推进到 END", String(end.get("mission_kind", "")))
	_data_line("fire", "FIRE 灾难分支：consequence + truth report + END")

# ═══════════════════════════════════════════════════════════════════
# 7. 自动时间线 / mission snapshot / mission_auto
# ═══════════════════════════════════════════════════════════════════

func _test_timeline_and_mission() -> void:
	_section_begin("7 时间线 / mission 联动")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_command(w)
	_eq(m.kind, "COMMAND", "进入 COMMAND")
	var tr: V2Track = w.track_for("2001")
	_eq(tr.observation_count, 0, "时间线不自动产生观测")
	# 推进时间到决策事件（story.events t=75,type=decision）
	for i in range(6):
		w.advance(10.0)
	_eq(bool(w.flow.get("decision_open", false)), false, "T+60 前决策未打开")
	var out := w.advance(15.0)
	_eq(bool(w.flow.get("decision_open", false)), true, "T+75 决策事件自动打开决策")
	var ev_out: Array = out.get("events", [])
	_eq(ev_out.size() > 0, true, "advance 返回触发的时间线事件")
	_eq(bool(m.has_flag("decision_open")), true, "mission flag decision_open")
	_eq(m.kind, "DECISION", "mission 自动推进到 DECISION")

	# 时间线事件/通信齐全
	var ev_types: Array = []
	for raw in _timeline_events(w):
		ev_types.append(String((raw as Dictionary).get("kind", "")))
	for t in ["timeline:notice", "timeline:false_alarm", "timeline:radar_on",
			"timeline:optical", "timeline:iff", "timeline:decision"]:
		_ok(t in ev_types, "时间线事件: " + t)
	_ok(w.radio.size() >= 5, "时间线通信写入 radio", "radio=%d" % w.radio.size())
	_eq(tr.observation_count, 0, "全程不自动做识别动作（观测计数仍 0）")
	_eq(tr.level, 1, "2001 等级仍 L1（只能由玩家动作推进）")
	_eq(w.track_for("9001").level, 1, "9001 等级仍 L1")

	# mission snapshot / vm_flow
	var snap := w.mission_snapshot()
	_ok(not snap.is_empty(), "mission_snapshot 可用")
	_eq(String(snap.get("kind", "")), "DECISION", "mission.snapshot kind")
	_ok(not (snap.get("prompt", {}) as Dictionary).is_empty(), "mission.snapshot 带 prompt（UI）")
	var flow := w.vm_flow()
	_ok(flow.has("prelude") and flow.has("decision") and flow.has("report") and flow.has("end"),
		"vm_flow 提供四层覆盖信息")
	_ok(flow.has("mission"), "vm_flow 带 mission snapshot")
	_eq(bool(flow.get("time_frozen", true)), false, "运行中时间不冻结")
	_eq(w.phase_context, "DECISION", "phase_context 跟随 mission kind")

	# mission_auto 可由 UI 关闭
	var sess2 := _new_session()
	var w2: V2World = sess2["world"]
	var m2: V2Mission = sess2["mission"]
	_skip_prelude(w2)
	w2.mission_auto = false
	w2.advance(0.01)
	_eq(m2.phase, "prelude", "mission_auto=false 时不自动推进")
	var res := w2.advance_mission(1)
	_ok((res as Array).size() >= 1, "advance_mission 显式推进")
	_eq(m2.kind, "READ", "显式推进 1 格 → READ")
	w2.advance_mission(1)
	_eq(m2.kind, "COMMAND", "再推进 1 格 → COMMAND")
	_data_line("timeline", "events/radio 自动触发，decision@T+75；不自动识别；mission_auto 可控")
