extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3X 最小 probe：LegalStatusService（ID13 法律状态）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/legal_status_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const LegalStatusService := preload("res://scripts/core/legal_status_service.gd")

const STATES := ["UNLISTED", "WATCHLIST", "RESTRICTED", "DESIGNATED_ILLEGAL",
	"HUNTED", "CLEARED"]
var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3X PROBE · LegalStatusService")
	print("════════════════════════════════════════════════════════════")
	_test_setup_defaults()
	_test_escalation()
	_test_status_impact()
	_test_clear_tick()
	_test_dedupe()
	_test_save_invalid()
	_test_events_aliases()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 LEGAL STATUS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 LEGAL STATUS PROBE FAILED")
		quit(1)
	else:
		print("V17 LEGAL STATUS PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
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
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _fresh(cfg := {}) -> Object:
	var s = LegalStatusService.new(cfg)
	_ok(bool(s.ready), "LegalStatusService ready", str(s.errors))
	return s

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

# ═══════════════════════════════════════════════════════════════════
# 1. setup / defaults
# ═══════════════════════════════════════════════════════════════════

func _test_setup_defaults() -> void:
	_section_begin("1 setup/defaults")
	var s = _fresh()
	_eq(str(s.status), "UNLISTED", "初始 UNLISTED")
	_eq(s.heat, 0.0, "初始 heat 0")
	_eq(s.t, 0.0, "初始 t 0")
	_eq(s.ticks, 0, "初始 ticks 0")
	_ok(bool(s.check_contracts().get("ok", false)), "初始 contracts ok")
	_eq((s.vm().get("states", []) as Array).size(), 6, "6 状态")
	_eq((s.vm().get("thresholds", {}) as Dictionary).size(), 4, "4 阈值")
	_eq(float(s.thresholds.get("WATCHLIST", 0.0)), 2.0, "WATCHLIST=2")
	_eq(float(s.thresholds.get("RESTRICTED", 0.0)), 4.0, "RESTRICTED=4")
	_eq(float(s.thresholds.get("DESIGNATED_ILLEGAL", 0.0)), 7.0,
		"DESIGNATED_ILLEGAL=7")
	_eq(float(s.thresholds.get("HUNTED", 0.0)), 10.0, "HUNTED=10")
	var imp: Dictionary = s.impact()
	_eq(str(imp.get("legal_status", "")), "UNLISTED", "impact 初始状态")
	_eq(str(imp.get("port_access", {}).get("ueg", "")), "NORMAL", "UNLISTED UEG NORMAL")
	_eq(str(imp.get("port_access", {}).get("joint", "")), "NORMAL", "UNLISTED 共管 NORMAL")
	_eq(bool(imp.get("iff_watch_flag", true)), false, "UNLISTED 无 watch")
	_eq(float(imp.get("combat_roe_modifier", 0.0)), 1.0, "UNLISTED roe 1.0")
	_eq(str(imp.get("ending_branch_hint", "")), "standard", "UNLISTED hint")
	_eq(bool((imp.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_eq(bool((imp.get("writes", {}) as Dictionary).get("side", true)), false, "不改 side")
	_eq(bool((imp.get("writes", {}) as Dictionary).get("legal_text", true)), false,
		"不改法律文本")
	_eq(s.port_access().get("ueg"), "NORMAL", "port_access API")
	_eq(s.iff_watch_flag(), false, "iff API")
	_eq(s.combat_roe_modifier(), 1.0, "roe API")
	_eq(s.ending_branch_hint(), "standard", "hint API")
	_eq((s.log as Array).size(), 1, "init 日志")
	_ok(str((s.log[0] as Dictionary).get("reason", "")) != "", "init reason")
	_data_line("defaults", "UNLISTED/heat0 · 阈值2/4/7/10 · impact NORMAL/1.0/standard · 日志")

# ═══════════════════════════════════════════════════════════════════
# 2. 逐级迁移
# ═══════════════════════════════════════════════════════════════════

func _test_escalation() -> void:
	_section_begin("2 逐级迁移")
	var s = _fresh()
	var r1: Dictionary = s.apply_event("strong", {"event_id": "e1"})
	_eq(bool(r1.get("ok", false)), true, "strong ok")
	_eq(float(s.heat), 1.0, "strong heat 1")
	_eq(str(s.status), "UNLISTED", "heat1 UNLISTED")
	_eq(str(r1.get("previous", "")), "UNLISTED", "strong previous")
	_ok(str((r1.get("log_entry", {}) as Dictionary).get("reason", "")) != "",
		"strong reason 记录")
	var r2: Dictionary = s.apply_event("fire_control_illumination", {"event_id": "e2"})
	_eq(float(s.heat), 3.0, "火控 heat 3")
	_eq(str(s.status), "WATCHLIST", "heat3 WATCHLIST")
	_eq(str(r2.get("previous", "")), "UNLISTED", "WATCH previous")
	_eq(str(r2.get("status", "")), "WATCHLIST", "WATCH status")
	var r3: Dictionary = s.apply_event("blackbox_public", {"event_id": "e3"})
	_eq(float(s.heat), 5.0, "黑匣子 heat 5")
	_eq(str(s.status), "RESTRICTED", "heat5 RESTRICTED")
	var r4: Dictionary = s.apply_event("attack_ueg", {"event_id": "e4"})
	_eq(float(s.heat), 9.0, "袭击 UEG heat 9")
	_eq(str(s.status), "DESIGNATED_ILLEGAL", "heat9 DESIGNATED")
	var r5: Dictionary = s.apply_event("report_public", {"event_id": "e5"})
	_eq(float(s.heat), 11.0, "公开报告 heat 11")
	_eq(str(s.status), "HUNTED", "heat11 HUNTED")
	_eq(str(s.ending_branch_hint()), "hunted", "HUNTED hint")
	# 负数事件不越界 heat
	var s2 = _fresh()
	var rn: Dictionary = s2.apply_event("retreat", {"event_id": "n1"})
	_eq(float(s2.heat), 0.0, "退让 heat 不越界")
	_eq(str(s2.status), "UNLISTED", "退让不晋级")
	_ok(str(rn.get("reason", "")) != "", "退让 reason")
	# 每次变化日志 reason/trigger/from/to
	for raw in (s.log as Array):
		var e: Dictionary = raw
		_ok(str(e.get("schema", "")) != "", "log schema")
		_ok(str(e.get("reason", "")) != "", "log reason")
		_ok(e.has("status"), "log status")
	# 迁移顺序/阈值边界
	var b = _fresh()
	for i in range(2):
		b.apply_event("strong", {"event_id": "b1_%d" % i})
	# 重新构造 heat 1.99/2.0 边界
	var b2 = _fresh({"weights": {"strong": 1.99}})
	b2.apply_event("strong", {"event_id": "b2a"})
	_eq(str(b2.status), "UNLISTED", "heat1.99 UNLISTED")
	b2.apply_event("strong", {"event_id": "b2b"})
	_ok(float(b2.heat) >= 2.0, "heat>=2", str(b2.heat))
	_eq(str(b2.status), "WATCHLIST", "heat>=2 WATCHLIST")
	# 自定义阈值
	var c = _fresh({"thresholds": {"WATCHLIST": 1.0, "RESTRICTED": 3.0,
		"DESIGNATED_ILLEGAL": 6.0, "HUNTED": 9.0}})
	c.apply_event("strong", {"event_id": "c1"})
	_eq(str(c.status), "WATCHLIST", "自定义阈值 heat1 WATCH")
	_data_line("escalation", "strong+1/fire+2/黑匣子+2/袭UEG+4/报告+2 · 1→3→5→9→11 迁移 · 阈值可调")

# ═══════════════════════════════════════════════════════════════════
# 3. 各状态影响接口
# ═══════════════════════════════════════════════════════════════════

func _test_status_impact() -> void:
	_section_begin("3 影响接口")
	var expected := {
		"UNLISTED": {"ueg": "NORMAL", "joint": "NORMAL", "watch": false,
			"roe": 1.0, "hint": "standard"},
		"WATCHLIST": {"ueg": "WATCHED", "joint": "NORMAL", "watch": true,
			"roe": 1.05, "hint": "watchlist"},
		"RESTRICTED": {"ueg": "RESTRICTED", "joint": "WATCHED", "watch": true,
			"roe": 1.15, "hint": "restricted"},
		"DESIGNATED_ILLEGAL": {"ueg": "DENIED", "joint": "RESTRICTED", "watch": true,
			"roe": 1.30, "hint": "designated_illegal"},
		"HUNTED": {"ueg": "DENIED", "joint": "DENIED", "watch": true,
			"roe": 1.50, "hint": "hunted"},
		"CLEARED": {"ueg": "CLEARED", "joint": "CLEARED", "watch": false,
			"roe": 1.0, "hint": "cleared"},
	}
	for st in STATES:
		var s = _fresh()
		var sr: Dictionary = s.set_status(str(st), "test")
		_eq(bool(sr.get("ok", false)), true, "set_status " + str(st))
		_eq(str(s.status), str(st), "status " + str(st))
		var imp: Dictionary = s.impact()
		var exp: Dictionary = expected[st]
		_eq(str(imp.get("port_access", {}).get("ueg", "")), exp["ueg"],
			"UEG 港 " + str(st))
		_eq(str(imp.get("port_access", {}).get("joint", "")), exp["joint"],
			"共管港 " + str(st))
		_eq(bool(imp.get("iff_watch_flag", false)), exp["watch"],
			"iff watch " + str(st))
		_eq(float(imp.get("combat_roe_modifier", 0.0)), exp["roe"],
			"roe modifier " + str(st))
		_eq(str(imp.get("ending_branch_hint", "")), exp["hint"],
			"ending hint " + str(st))
		_eq(bool((imp.get("writes", {}) as Dictionary).get("world", true)), false,
			"影响不写 world " + str(st))
		# 影响只读：调用前后 vm 除 status/log 不变
		var before_heat := float(s.heat)
		s.impact()
		s.port_access()
		s.iff_watch_flag()
		s.combat_roe_modifier()
		s.ending_branch_hint()
		_eq(float(s.heat), before_heat, "影响只读 " + str(st))
		_eq(str(s.status), str(st), "影响后状态 " + str(st))
	_data_line("impact", "6 状态 × UEG/共管港/iff/ROE/ending hint · 只输出标志不写 world/side/legal_text")

# ═══════════════════════════════════════════════════════════════════
# 4. CLEARED / tick / decay
# ═══════════════════════════════════════════════════════════════════

func _test_clear_tick() -> void:
	_section_begin("4 CLEARED/tick")
	var s = _fresh()
	s.apply_event("attack_nesoss", {"event_id": "a1"})
	_eq(str(s.status), "RESTRICTED", "袭击 NESOSS +5 → RESTRICTED")
	# 显式 CLEARED
	var cr: Dictionary = s.apply_event("cleared", {"reason": "court"})
	_eq(bool(cr.get("ok", false)), true, "cleared ok")
	_eq(str(s.status), "CLEARED", "CLEARED")
	_ok(str(s.ending_branch_hint()) == "cleared", "CLEARED hint")
	_eq(bool(s.impact().get("iff_watch_flag", true)), false, "CLEARED 去 watch")
	_ok(bool(s.check_contracts().get("ok", false)), "CLEARED contracts")
	# CLEARED 锁定
	_eq(str(s.apply_event("strong").get("reason", "")), "cleared_locked",
		"CLEARED 后事件拒绝")
	_eq(str(s.set_status("HUNTED").get("reason", "")), "cleared_locked",
		"CLEARED 后 set_status 拒绝")
	_eq(str(s.status), "CLEARED", "锁定状态不变")
	# viedicated/exonerated 也 CLEARED
	for trig in ["vindicated", "exonerated"]:
		var s2 = _fresh()
		s2.apply_event("attack_ueg", {"event_id": "x"})
		var rr: Dictionary = s2.apply_event(str(trig))
		_eq(bool(rr.get("ok", false)), true, str(trig) + " ok")
		_eq(str(s2.status), "CLEARED", str(trig) + " CLEARED")
	# tick 无衰减
	var t = _fresh()
	t.apply_event("strong", {"event_id": "t1"})
	var tr: Dictionary = t.tick(10.0)
	_eq(bool(tr.get("ok", false)), true, "tick ok")
	_eq(float(t.t), 10.0, "tick t")
	_eq(t.ticks, 1, "ticks 1")
	_eq(float(t.heat), 1.0, "无衰减 heat 1")
	_eq(str(t.status), "UNLISTED", "无衰减状态")
	_ok(str(tr.get("log_entry", {}).get("reason", "")).contains("tick"), "tick 日志")
	# tick 非法 dt
	_eq(str(t.tick(NAN).get("reason", "")), "invalid_dt", "tick NaN 拒绝")
	_eq(str(t.tick(-1.0).get("reason", "")), "invalid_dt", "tick 负数拒绝")
	# decay + deescalation
	var d = _fresh({"decay_per_day": 1.0, "allow_deescalation": true})
	d.apply_event("strong", {"event_id": "d1"})
	d.apply_event("fire_control_illumination", {"event_id": "d2"})
	_eq(str(d.status), "WATCHLIST", "decay 前 WATCH")
	var dt1: Dictionary = d.tick(86400.0)
	_eq(float(d.heat), 2.0, "decay 1 天 heat2")
	_eq(str(d.status), "WATCHLIST", "heat2 WATCH")
	var dt2: Dictionary = d.tick(86400.0)
	_eq(float(d.heat), 1.0, "decay 2 天 heat1")
	_eq(str(d.status), "UNLISTED", "deescalation UNLISTED")
	_eq(bool(dt2.get("changed", false)), true, "decay changed")
	# 默认不允许降级：热衰减但不降状态
	var nd = _fresh({"decay_per_day": 1.0, "allow_deescalation": false})
	nd.apply_event("strong", {"event_id": "nd1"})
	nd.apply_event("fire_control_illumination", {"event_id": "nd2"})
	nd.tick(86400.0)
	_ok(float(nd.heat) < 3.0, "默认 decay heat 降低", str(nd.heat))
	_eq(str(nd.status), "WATCHLIST", "默认不降状态")
	# tick CLEARED 不改
	var cl = _fresh()
	cl.apply_event("cleared")
	var ct: Dictionary = cl.tick(100.0)
	_eq(bool(ct.get("ok", false)), true, "CLEARED tick ok")
	_eq(str(cl.status), "CLEARED", "CLEARED tick 不变")
	_data_line("clear/tick", "CLEARED 锁定 · tick/decay/deescalation · 默认不降级 · 非法 dt 拒绝")

# ═══════════════════════════════════════════════════════════════════
# 5. 去重
# ═══════════════════════════════════════════════════════════════════

func _test_dedupe() -> void:
	_section_begin("5 去重")
	var s = _fresh()
	var r1: Dictionary = s.apply_event("strong", {"event_id": "dup1"})
	_eq(bool(r1.get("duplicate", true)), false, "首次不重复")
	_eq(float(s.heat), 1.0, "首次 heat1")
	var r2: Dictionary = s.apply_event("strong", {"event_id": "dup1"})
	_eq(bool(r2.get("duplicate", false)), true, "同 event_id 去重")
	_eq(str(r2.get("reason", "")), "duplicate_event", "去重 reason")
	_eq(float(s.heat), 1.0, "去重不改 heat")
	_eq(str(s.status), "UNLISTED", "去重不改状态")
	_eq(s.log.size(), 3, "去重日志 3（init+首次+dedupe）")
	# 无 event_id：相同 trigger+payload 也去重
	var a: Dictionary = s.apply_event("blackbox_public", {"source": "x"})
	_eq(bool(a.get("duplicate", true)), false, "无 id 首次不重复")
	var b: Dictionary = s.apply_event("blackbox_public", {"source": "x"})
	_eq(bool(b.get("duplicate", false)), true, "无 id 同 payload 去重")
	# 不同 payload 不去重
	var c: Dictionary = s.apply_event("blackbox_public", {"source": "y"})
	_eq(bool(c.get("duplicate", true)), false, "不同 payload 不去重")
	# force 可绕过
	var f: Dictionary = s.apply_event("strong", {"event_id": "dup1", "force": true})
	_eq(bool(f.get("duplicate", true)), false, "force 绕过去重")
	# 未知 trigger
	var u: Dictionary = s.apply_event("NOPE")
	_eq(str(u.get("reason", "")), "unknown_trigger", "未知 trigger 拒绝")
	_eq(float(s.heat), 6.0, "未知 trigger 不改 heat")
	# 空 trigger
	_eq(str(s.apply_event("").get("reason", "")), "invalid_trigger", "空 trigger 拒绝")
	_data_line("dedupe", "event_id/trigger+payload 去重 · force 覆盖 · 未知/空 trigger 拒绝")

# ═══════════════════════════════════════════════════════════════════
# 6. save/load / 非法
# ═══════════════════════════════════════════════════════════════════

func _test_save_invalid() -> void:
	_section_begin("6 save/invalid")
	var s = _fresh()
	s.apply_event("strong", {"event_id": "s1"})
	s.apply_event("fire_control_illumination", {"event_id": "s2"})
	s.tick(5.0)
	var save: String = str(s.save_state())
	_ok(str((JSON.parse_string(save) as Dictionary).get("schema", "")) ==
		"v17.legal_status_save.v1", "save schema")
	var s2 = _fresh()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_eq(_norm(s.vm()), _norm(s2.vm()), "load VM 一致")
	_eq(str(s2.status), "WATCHLIST", "load status")
	_eq(float(s2.heat), 3.0, "load heat")
	# load 后继续事件
	_eq(bool(s2.apply_event("blackbox_public", {"event_id": "s3"}).get("ok", false)),
		true, "load 后继续事件")
	# CLEARED 存档
	var c = _fresh()
	c.apply_event("cleared", {"reason": "court"})
	var c2 = _fresh()
	_eq(bool(c2.load_state(str(c.save_state())).get("ok", false)), true, "CLEARED load")
	_eq(str(c2.status), "CLEARED", "CLEARED load status")
	# 非法存档
	var before := _norm(c2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.legal_status_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.legal_status_save.v1", "version": "1.0.0",
			"status": "BAD", "log": [], "dedupe": {}, "thresholds": {}, "weights": {}}),
		JSON.stringify({"schema": "v17.legal_status_save.v1", "version": "1.0.0",
			"status": "UNLISTED", "log": "bad", "dedupe": {}, "thresholds": {},
			"weights": {}}),
		JSON.stringify({"schema": "v17.legal_status_save.v1", "version": "1.0.0",
			"status": "UNLISTED", "log": [], "dedupe": "bad", "thresholds": {},
			"weights": {}}),
		JSON.stringify({"schema": "v17.legal_status_save.v1", "version": "1.0.0",
			"status": "UNLISTED", "log": [], "dedupe": {}, "thresholds": "bad",
			"weights": {}})]
	for bad in bads:
		_eq(bool(c2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 28))
	_eq(_norm(c2.vm()), before, "非法存档不改状态")
	# 非法 config
	var badcfg = LegalStatusService.new({"thresholds": {"WATCHLIST": 0.0}})
	_eq(bool(badcfg.ready), false, "非法阈值 config 拒绝")
	var badcfg2 = LegalStatusService.new({"thresholds": {"WATCHLIST": 5.0,
		"RESTRICTED": 3.0}})
	_eq(bool(badcfg2.ready), false, "非递增阈值拒绝")
	# 确定性
	var a = _fresh()
	var b = _fresh()
	for sv in [a, b]:
		sv.apply_event("strong", {"event_id": "d1"})
		sv.apply_event("blackbox_public", {"event_id": "d2"})
		sv.tick(2.0)
	_eq(_norm(a.vm()), _norm(b.vm()), "同操作 VM 一致")
	_eq(a.save_state(), b.save_state(), "同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts")
	_data_line("save/invalid", "save-load VM 一致 · CLEARED 存档 · 非法存档/阈值原子拒绝 · 确定")

# ═══════════════════════════════════════════════════════════════════
# 7. 触发别名 / 影响因素
# ═══════════════════════════════════════════════════════════════════

func _test_events_aliases() -> void:
	_section_begin("7 触发因素")
	var cases := {
		"strong": 1.0, "strong_negotiator": 1.0, "negotiation_strong": 1.0,
		"roe_tight": 1.0, "fire_control_illumination": 2.0,
		"blackbox": 2.0, "blackbox_public": 2.0, "blackbox_recovered": 1.0,
		"evidence": 1.0, "evidence_public": 2.0, "evidence_presented": 1.0,
		"attack_ueg": 4.0, "attack_nesoss": 5.0, "attack": 3.0,
		"negotiation_standard": 0.5, "standard": 0.5,
		"negotiation_question": 1.0, "question": 1.0,
		"negotiation_retreat": -1.0, "retreat": -1.0,
		"report_public": 2.0, "report": 1.0, "report_suppress": -1.0,
		"deputy_trust_low": 1.0, "deputy_trust_high": -1.0, "deputy_trust": 1.0,
		"political_aeug": 2.0, "political_ueg": 1.0, "aeug_action": 2.0,
	}
	for trig in cases.keys():
		var s = _fresh()
		var r: Dictionary = s.apply_event(str(trig), {"event_id": "x_" + str(trig)})
		_eq(bool(r.get("ok", false)), true, "trigger " + str(trig))
		_eq(float(s.heat), maxf(0.0, float(cases[trig])), "trigger heat " + str(trig))
		_ok(str((r.get("log_entry", {}) as Dictionary).get("reason", "")) != "",
			"trigger reason " + str(trig))
	# 副官信任/政治倾向/AEUG 组合使状态升级
	var combo = _fresh()
	combo.apply_event("deputy_trust_low", {"event_id": "c1"})
	combo.apply_event("political_aeug", {"event_id": "c2"})
	combo.apply_event("aeug_action", {"event_id": "c3"})
	_eq(str(combo.status), "RESTRICTED", "信任/政治/AEUG → RESTRICTED")
	# 报告公开/压制
	var pub = _fresh()
	pub.apply_event("report_public", {"event_id": "p1"})
	pub.apply_event("report_public", {"event_id": "p2"})
	_eq(str(pub.status), "RESTRICTED", "公开报告两次 RESTRICTED")
	var sup = _fresh()
	sup.apply_event("report_public", {"event_id": "q1"})
	sup.apply_event("report_suppress", {"event_id": "q2"})
	_eq(float(sup.heat), 1.0, "压制报告 heat 降低")
	_data_line("events", "29 触发别名 · 副官信任/政治倾向/AEUG · 报告公开/压制 · 每次变化有 reason")

# 局部工具别名（保持 probe 自洽）
func _all_events() -> Array:
	return []
