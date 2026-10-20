extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3R 最小 probe：IdentificationService（识别自动化/证据融合）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/identification_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/TrackTable/UI。
# ═══════════════════════════════════════════════════════════════════

const IdentificationService := preload("res://scripts/core/identification_service.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3R PROBE · IdentificationService")
	print("════════════════════════════════════════════════════════════")
	_test_setup_fusion()
	_test_contradiction_spoof()
	_test_levels_manual()
	_test_decay_duplicate()
	_test_auto_query()
	_test_matrix()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 IDENTIFICATION PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 IDENTIFICATION PROBE FAILED")
		quit(1)
	else:
		print("V17 IDENTIFICATION PROBE OK")
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

func _new_service(cfg := {}) -> Object:
	var s = IdentificationService.new(cfg)
	_ok(bool(s.ready), "IdentificationService ready", str(s.errors))
	return s

func _ev(target: String, source: String, identity: String, confidence: float,
		extra := {}) -> Dictionary:
	var d: Dictionary = {"target_id": target, "source": source,
		"identity": identity, "confidence": confidence, "mode": "mode_s"}
	for k in (extra as Dictionary).keys():
		d[String(k)] = (extra as Dictionary)[k]
	return d

func _a(s, target: String) -> Dictionary:
	return s.get_assessment(target)

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

# ═══════════════════════════════════════════════════════════════════
# 1. setup + 基础融合
# ═══════════════════════════════════════════════════════════════════

func _test_setup_fusion() -> void:
	_section_begin("1 setup/融合")
	var s = _new_service()
	_eq(str(s.vm().get("schema", "")), "v17.identification_service.v1", "VM schema")
	_eq(int(s.summary().get("targets", -1)), 0, "初始 targets=0")
	_ok(bool((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false,
		"不写 world")
	_ok(bool((s.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false,
		"不写 TrackTable")
	_ok(bool((s.vm().get("writes", {}) as Dictionary).get("weapon", true)) == false,
		"不自动武器")
	_ok(bool(s.check_contracts().get("ok", false)), "初始 contracts ok")
	# 单源 friend
	var r1: Dictionary = s.ingest(_ev("T1", "transponder", "friend", 0.9))
	_eq(bool(r1.get("ok", false)), true, "ingest1 ok")
	var a1: Dictionary = r1.get("assessment", {})
	_eq(str(a1.get("identity", "")), "friend", "单源 friend")
	_ok(float(a1.get("confidence", 0.0)) > 0.0 and float(a1.get("confidence", 0.0)) < 1.0,
		"单源 confidence 中间值")
	_eq(int(a1.get("level", 0)), 3, "单源 L3")
	_eq(str(a1.get("level_name", "")), "L3_CLASSIFIED", "单源 level_name")
	_ok((a1.get("sources", []) as Array).has("transponder"), "sources 含 transponder")
	_ok((a1.get("categories", []) as Array).has("iff"), "categories iff")
	_eq(int(a1.get("evidence_count", 0)), 1, "evidence_count 1")
	# 第二类独立证据 → L4 friend
	var r2: Dictionary = s.ingest(_ev("T1", "optical", "friend", 0.85,
		{"category": "sensor"}))
	var a2: Dictionary = r2.get("assessment", {})
	_eq(str(a2.get("identity", "")), "friend", "双源 friend")
	_eq(int(a2.get("level", 0)), 4, "双源 L4")
	_eq(str(a2.get("level_name", "")), "L4_IDENTIFIED", "双源 L4 name")
	_ok(float(a2.get("confidence", 0.0)) >= 0.75, "双源 confidence>=0.75")
	_eq((a2.get("sources", []) as Array).size(), 2, "sources 2")
	_eq((a2.get("categories", []) as Array).size(), 2, "categories 2")
	# neutral / station / unknown
	var n: Dictionary = s.ingest(_ev("T2", "sensor", "neutral", 0.8))
	_eq(str(n.get("assessment", {}).get("identity", "")), "neutral", "neutral 融合")
	var st: Dictionary = s.ingest(_ev("T3", "transponder", "station", 0.9,
		{"status": "normal"}))
	_eq(str(st.get("assessment", {}).get("identity", "")), "station", "station 融合")
	var un: Dictionary = s.ingest(_ev("T4", "track", "unknown", 0.5))
	_eq(str(un.get("assessment", {}).get("identity", "")), "unknown", "unknown 融合")
	_eq(int(un.get("assessment", {}).get("level", 0)), 2, "unknown 只有证据 → L2")
	# 未知目标 assess/get
	_eq(bool(s.assess("NOPE").get("ok", true)), false, "unknown assess 拒绝")
	_eq(str(s.assess("NOPE").get("reason", "")), "unknown_target", "unknown_target reason")
	_ok(s.get_assessment("NOPE").is_empty(), "unknown get 空")
	# ingest 校验
	var before := _norm(s.vm())
	var bads: Array = [
		{},
		{"target_id": "X", "source": "", "identity": "friend"},
		{"target_id": "", "source": "sensor", "identity": "friend"},
		{"target_id": "X", "source": "sensor", "identity": "bogus"},
		{"target_id": "X", "source": "sensor", "identity": "friend", "confidence": NAN},
		{"target_id": "X", "source": "sensor", "identity": "friend", "t": NAN},
	]
	for bad in bads:
		_eq(bool(s.ingest(bad).get("ok", true)), false, "非法证据拒绝")
	_eq(_norm(s.vm()), before, "非法证据不改状态")
	# events
	_ok(s.events.size() > 0, "产生事件")
	var last: Dictionary = s.events[s.events.size() - 1]
	_eq(str(last.get("schema", "")), "identification_event.v1", "事件 schema")
	_data_line("setup/fusion", "单源 L3/双源独立 L4 · friend/neutral/station/unknown · 非法证据原子拒绝")

# ═══════════════════════════════════════════════════════════════════
# 2. IFF hostiles / 矛盾 / 欺骗
# ═══════════════════════════════════════════════════════════════════

func _test_contradiction_spoof() -> void:
	_section_begin("2 hostile/矛盾/欺骗")
	var s = _new_service()
	# IFF/应答单独 hostile → suspect（不能自动 hostile）
	var h: Dictionary = s.ingest(_ev("H1", "iff", "hostile", 0.95, {"mode": "mode_5"}))
	var ah: Dictionary = h.get("assessment", {})
	_eq(str(ah.get("identity", "")), "suspect", "IFF 单独 hostile → suspect")
	_eq(bool(ah.get("authorized", true)), false, "未授权")
	_ok(int(ah.get("level", 0)) <= 3, "IFF 单独最高 L3")
	_ok((ah.get("notes", []) as Array).has("iff_alone_downgraded"), "iff_alone note")
	_ok(float(ah.get("spoof_suspicion", 0.0)) > 0.0, "IFF hostile spoof 加权")
	# 第二类证据仍不能自动 hostile
	var h2: Dictionary = s.ingest(_ev("H1", "optical", "hostile", 0.9,
		{"category": "sensor"}))
	var ah2: Dictionary = h2.get("assessment", {})
	_eq(str(ah2.get("identity", "")), "suspect", "双源 hostile 仍 suspect")
	_eq(bool(ah2.get("authorized", true)), false, "双源未授权")
	_ok(int(ah2.get("level", 4)) <= 3, "双源 hostile 自动 <=L3")
	# 矛盾：friend vs hostile
	var c: Dictionary = s.ingest(_ev("C1", "transponder", "friend", 0.9))
	s.ingest(_ev("C1", "optical", "hostile", 0.8, {"category": "sensor"}))
	var ac: Dictionary = s.get_assessment("C1")
	_eq(str(ac.get("identity", "")), "suspect", "friend/hostile 冲突 → suspect")
	_ok((ac.get("contradictions", []) as Array).size() > 0, "contradictions")
	_ok(float(ac.get("spoof_suspicion", 0.0)) > 0.0, "冲突 spoof_suspicion")
	_ok(int(ac.get("level", 4)) <= 3, "冲突 <=L3")
	_ok(float(ac.get("confidence", 1.0)) <= 0.7, "冲突 confidence<=0.7")
	# spoofed 标记
	var sp: Dictionary = s.ingest(_ev("S1", "transponder", "friend", 0.9,
		{"spoofed": true, "status": "captured"}))
	var asp: Dictionary = sp.get("assessment", {})
	_ok(float(asp.get("spoof_suspicion", 0.0)) >= 0.5, "spoofed/captured suspicion>=0.5")
	_eq(str(asp.get("trigger_hint", "")), "spoof_suspicion", "spoof trigger_hint")
	_ok(float(asp.get("confidence", 1.0)) <= 0.6, "spoof confidence<=0.6")
	# 矛盾+欺骗 降级
	var multi: Dictionary = s.ingest(_ev("M1", "transponder", "friend", 0.9,
		{"spoofed": true, "status": "captured"}))
	s.ingest(_ev("M1", "optical", "hostile", 0.9, {"category": "sensor"}))
	var am: Dictionary = s.get_assessment("M1")
	_eq(str(am.get("identity", "")), "suspect", "冲突+欺骗 suspect")
	_ok(int(am.get("level", 4)) <= 3, "冲突+欺骗 <=L3")
	_ok((am.get("contradictions", []) as Array).size() > 0, "M1 contradictions")
	_data_line("contradiction", "IFF 单独/双源 hostile 仍 suspect · 冲突→suspect · spoofed/captured 降级")

# ═══════════════════════════════════════════════════════════════════
# 3. L3-L4 / 人工确认 / 授权
# ═══════════════════════════════════════════════════════════════════

func _test_levels_manual() -> void:
	_section_begin("3 L3/L4/manual")
	var s = _new_service()
	# 单类证据不 L4
	s.ingest(_ev("L1", "transponder", "friend", 0.95))
	_ok(int(s.get_assessment("L1").get("level", 0)) <= 3, "单类证据不 L4")
	# 两类但低置信也不 L4（用低置信）
	s.ingest(_ev("L2", "transponder", "friend", 0.2))
	s.ingest(_ev("L2", "optical", "friend", 0.2, {"category": "sensor"}))
	_ok(int(s.get_assessment("L2").get("level", 4)) <= 3, "低置信不 L4")
	# 两类高置信 L4
	s.ingest(_ev("L3", "transponder", "friend", 0.95))
	s.ingest(_ev("L3", "optical", "friend", 0.95, {"category": "sensor"}))
	_eq(int(s.get_assessment("L3").get("level", 0)), 4, "两类高置信 L4")
	# 人工确认 friend（无证据也可）
	var mc: Dictionary = s.manual_confirm("M1", "friend", {"authority": "captain"})
	_eq(bool(mc.get("ok", false)), true, "manual_confirm friend ok")
	var am1: Dictionary = mc.get("assessment", {})
	_eq(str(am1.get("identity", "")), "friend", "manual identity")
	_eq(int(am1.get("level", 0)), 4, "manual L4")
	_eq(bool(am1.get("manual", false)), true, "manual flag")
	_eq(bool(am1.get("auto", true)), false, "manual auto=false")
	_eq(str(am1.get("manual_authority", "")), "captain", "manual authority")
	# 人工确认 hostile → L4 authorized
	var mh: Dictionary = s.manual_confirm("M2", "hostile", {"authority": "weapons"})
	var amh: Dictionary = mh.get("assessment", {})
	_eq(str(amh.get("identity", "")), "hostile", "manual hostile")
	_eq(int(amh.get("level", 0)), 4, "manual hostile L4")
	_eq(bool(amh.get("authorized", false)), true, "manual hostile authorized")
	_ok(bool(s.check_contracts().get("ok", false)), "manual hostile contracts ok")
	# authorize_hostile
	var au: Dictionary = s.authorize_hostile("M3", "command", {})
	_eq(str(au.get("assessment", {}).get("identity", "")), "hostile",
		"authorize hostile identity")
	_eq(int(au.get("assessment", {}).get("level", 0)), 4, "authorize hostile L4")
	_eq(bool(au.get("assessment", {}).get("authorized", false)), true,
		"authorize authorized true")
	# 无授权 hostile 不允许（模拟评估内部）——非法 manual identity
	_eq(bool(s.manual_confirm("M4", "bogus").get("ok", true)), false,
		"manual 非法 identity 拒绝")
	_eq(bool(s.manual_confirm("", "friend").get("ok", true)), false, "空 target 拒绝")
	# clear manual → 回到自动（无证据 unknown）
	var cm: Dictionary = s.clear_manual("M1")
	_eq(bool(cm.get("ok", false)), true, "clear_manual ok")
	var am1c: Dictionary = cm.get("assessment", {})
	_eq(bool(am1c.get("manual", true)), false, "clear manual=false")
	_eq(str(am1c.get("identity", "")), "unknown", "clear 后 unknown（无证据）")
	_ok(int(am1c.get("level", 0)) <= 3, "clear 后 <=L3")
	_eq(bool(s.clear_manual("NOPE").get("ok", true)), false, "clear 未知拒绝")
	# target state
	var ts: Dictionary = s.set_target_state("L3", {"range_km": 100.0, "los": true,
		"emcon": false})
	_eq(bool(ts.get("ok", false)), true, "set_target_state ok")
	_eq(float((ts.get("state", {}) as Dictionary).get("range_km", 0.0)), 100.0,
		"target state range")
	# 事件
	var manual_evs := 0
	for e in s.events:
		if str((e as Dictionary).get("kind", "")) in ["manual_confirm", "manual_clear"]:
			manual_evs += 1
	_ok(manual_evs >= 2, "manual 事件")
	_data_line("levels", "自动最高 L3 · 双类高置信 L4 · manual/authorize hostile L4 · clear/state")

# ═══════════════════════════════════════════════════════════════════
# 4. 衰减 / 重复抑制
# ═══════════════════════════════════════════════════════════════════

func _test_decay_duplicate() -> void:
	_section_begin("4 衰减/重复")
	var s = _new_service({"evidence_ttl_s": 20.0, "decay_half_life_s": 10.0})
	var r1: Dictionary = s.ingest(_ev("D1", "transponder", "friend", 0.9))
	_eq(bool(r1.get("ok", false)), true, "decay ingest1")
	var c0 := float(s.get_assessment("D1").get("confidence", 0.0))
	var r2: Dictionary = s.ingest(_ev("D1", "transponder", "friend", 0.9))
	_eq(bool(r2.get("duplicate", false)), true, "重复证据抑制")
	_eq(int(s.get_assessment("D1").get("evidence_count", 0)), 1, "重复不增加证据")
	_eq(float(s.get_assessment("D1").get("confidence", 0.0)), c0,
		"重复不改 confidence")
	s.step(5.0)
	var c1 := float(s.get_assessment("D1").get("confidence", 0.0))
	_ok(c1 < c0 + 1.0e-9, "step 后 confidence 不增")
	_near(float(s.get_assessment("D1").get("age", -1.0)), 5.0, 1.0e-9, "age=5")
	s.step(10.0)
	var c2 := float(s.get_assessment("D1").get("confidence", 0.0))
	_ok(c2 < c1 + 1.0e-9, "更长 age confidence 衰减")
	# 超过 ttl：证据清除 → unknown/L1/L2
	s.step(20.0)
	var ad: Dictionary = s.get_assessment("D1")
	_eq(int(ad.get("evidence_count", -1)), 0, "超 ttl evidence_count=0")
	_eq(str(ad.get("identity", "")), "unknown", "超 ttl identity unknown")
	_eq(int(ad.get("level", 0)), 1, "超 ttl L1")
	_eq(float(ad.get("confidence", -1.0)), 0.0, "超 ttl confidence 0")
	# 时间衰减后的评估事件
	_ok(s.events.size() > 0, "decay 事件")
	# 时间非法
	var before := _norm(s.vm())
	_eq(bool(s.step(-1.0).get("ok", true)), false, "负 dt 拒绝")
	_eq(bool(s.step(NAN).get("ok", true)), false, "NaN dt 拒绝")
	_eq(_norm(s.vm()), before, "非法 step 不改状态")
	_data_line("decay", "重复抑制 · step 衰减/age · ttl 过期清证据 → unknown/L1 · 非法 dt")

# ═══════════════════════════════════════════════════════════════════
# 5. 自动/半自动询问
# ═══════════════════════════════════════════════════════════════════

func _test_auto_query() -> void:
	_section_begin("5 自动询问")
	var s = _new_service({"auto": {"enabled": false, "interval_s": 2.0,
		"modes": ["mode_s", "mode_5"], "max_range_km": 500.0}})
	s.ingest(_ev("A1", "transponder", "unknown", 0.3, {"range_km": 100.0,
		"los": true, "emcon": false}))
	var off: Dictionary = s.auto_query_tick(1.0)
	_eq(bool(off.get("enabled", true)), false, "auto disabled")
	_eq((off.get("requests", []) as Array).size(), 0, "disabled 无请求")
	# 开启
	_eq(bool(s.set_auto(true, {"interval_s": 2.0, "modes": ["mode_s"],
		"max_range_km": 500.0, "min_confidence": 0.8}).get("ok", false)), true,
		"set_auto true")
	var q1: Dictionary = s.auto_query_tick(2.0)
	_ok((q1.get("requests", []) as Array).size() >= 1, "auto 产生请求")
	var req: Dictionary = (q1.get("requests", []) as Array)[0]
	_eq(str(req.get("schema", "")), "identification_query_request.v1", "request schema")
	_eq(str(req.get("target_id", "")), "A1", "request target")
	_eq(str(req.get("mode", "")), "mode_s", "request mode")
	_ok(str(req.get("request_id", "")) != "", "request id")
	_eq(bool(req.get("weapon", true)), false, "request 不发射武器")
	_eq(bool(req.get("auto", false)), true, "request auto")
	_ok(float(req.get("priority", 0.0)) > 0.0, "request priority")
	# take 清空
	_eq((s.take_query_requests() as Array).size() >= 1, true, "take_query_requests")
	_eq((s.take_query_requests() as Array).size(), 0, "take 后空")
	# interval 未到不产生
	_eq((s.auto_query_tick(0.5).get("requests", []) as Array).size(), 0,
		"interval 未到无请求")
	# 目标状态限制：超 range
	s.set_target_state("A1", {"range_km": 9999.0, "los": true, "emcon": false})
	s.set_auto(true, {"interval_s": 1.0})
	s.step(3.0)
	_eq((s.auto_query_tick(1.0).get("requests", []) as Array).size(), 0,
		"超 range 不自动询问")
	# LOS false
	s.set_target_state("A1", {"range_km": 100.0, "los": false, "emcon": false})
	s.step(3.0)
	_eq((s.auto_query_tick(1.0).get("requests", []) as Array).size(), 0,
		"无 LOS 不自动询问")
	# EMCON
	s.set_target_state("A1", {"range_km": 100.0, "los": true, "emcon": true})
	s.step(3.0)
	_eq((s.auto_query_tick(1.0).get("requests", []) as Array).size(), 0,
		"EMCON 不自动询问")
	# 恢复 → 产生
	s.set_target_state("A1", {"range_km": 100.0, "los": true, "emcon": false})
	s.step(3.0)
	_ok((s.auto_query_tick(1.0).get("requests", []) as Array).size() >= 1,
		"恢复条件后可询问")
	# manual 锁定目标不询问
	s.manual_confirm("A1", "friend", {})
	s.step(3.0)
	_eq((s.auto_query_tick(1.0).get("requests", []) as Array).size(), 0,
		"manual 目标不自动询问")
	# 事件 query_request
	_ok(s.events.size() > 0, "auto events")
	var has_q := false
	for e in s.events:
		if str((e as Dictionary).get("kind", "")) == "query_request":
			has_q = true
	_ok(has_q, "query_request 事件")
	_data_line("auto", "interval/priority/mode · range/LOS/EMCON 允许 · manual 跳过 · 无武器")

# ═══════════════════════════════════════════════════════════════════
# 6. 存档 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_save_determinism() -> void:
	_section_begin("6 save/确定性")
	var s = _new_service({"auto": {"enabled": true, "interval_s": 2.0,
		"modes": ["mode_s"]}})
	s.ingest(_ev("S1", "transponder", "friend", 0.9))
	s.ingest(_ev("S1", "optical", "friend", 0.8, {"category": "sensor"}))
	s.ingest(_ev("S2", "iff", "hostile", 0.9, {"mode": "mode_5"}))
	s.set_target_state("S2", {"range_km": 100.0, "los": true, "emcon": false})
	s.auto_query_tick(3.0)
	s.manual_confirm("S3", "neutral", {"authority": "captain"})
	var save := str(s.save_state())
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "save JSON")
	if d is Dictionary:
		_eq(str((d as Dictionary).get("schema", "")),
			"v17.identification_service_save.v1", "save schema")
		_ok((d as Dictionary).get("evidence") is Dictionary, "save evidence")
		_ok((d as Dictionary).get("assessments") is Dictionary, "save assessments")
	var s2 = _new_service()
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "save/load ok", str(lr.get("errors", [])))
	_ok(_norm(s.vm()) == _norm(s2.vm()), "load VM 一致")
	_eq(str(s2.get_assessment("S2").get("identity", "")), "suspect", "load S2 suspect")
	_eq(int(s2.get_assessment("S3").get("level", 0)), 4, "load manual L4")
	_eq(bool(s2.get_assessment("S1").get("manual", true)), false, "load S1 auto")
	# load 后可继续
	var q: Dictionary = s2.auto_query_tick(2.0)
	_ok(q.get("requests") is Array, "load 后 auto tick")
	# 非法存档原子拒绝
	var before := _norm(s2.vm())
	var bads: Array = ["", "{bad",
		JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.identification_service_save.v1",
			"version": "9.9.9"}),
		JSON.stringify({"schema": "v17.identification_service_save.v1",
			"version": "1.0.0", "evidence": [], "assessments": {}}),
		JSON.stringify({"schema": "v17.identification_service_save.v1",
			"version": "1.0.0", "evidence": {"X": "bad"}, "assessments": {}})]
	for bad in bads:
		_eq(bool(s2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 32))
	_eq(_norm(s2.vm()), before, "非法存档不改状态")
	# 确定性
	var a = _new_service()
	var b = _new_service()
	for x in [a, b]:
		x.ingest(_ev("D1", "transponder", "friend", 0.9))
		x.ingest(_ev("D1", "optical", "friend", 0.8, {"category": "sensor"}))
		x.ingest(_ev("D2", "iff", "hostile", 0.9))
		x.manual_confirm("D3", "hostile", {"authority": "weapons"})
		x.set_auto(true, {"interval_s": 1.0})
		x.auto_query_tick(2.0)
	_eq(_norm(a.vm()), _norm(b.vm()), "同操作 VM 一致")
	_eq(_norm(JSON.parse_string(a.save_state())),
		_norm(JSON.parse_string(b.save_state())), "同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("save", "save/load VM/evidence/assessments/manual 一致 · 非法存档原子拒绝 · 同操作确定")

# ═══════════════════════════════════════════════════════════════════
# 7. 批量矩阵（身份×来源 / 类别 / 冲突对 / 自动询问）
# ═══════════════════════════════════════════════════════════════════

func _test_matrix() -> void:
	_section_begin("7 批量矩阵")
	# 每个身份 × 单来源
	var ids: Array = ["friend", "neutral", "suspect", "unknown", "station"]
	var sources: Array = ["transponder", "optical", "elint", "track"]
	for ident in ids:
		for src in sources:
			var s = _new_service()
			var tid := "M-%s-%s" % [str(ident), str(src)]
			var r: Dictionary = s.ingest(_ev(tid, str(src), str(ident), 0.9))
			_eq(bool(r.get("ok", false)), true, "matrix ingest %s/%s" % [ident, src])
			var a: Dictionary = r.get("assessment", {})
			_eq(str(a.get("identity", "")), str(ident), "matrix identity %s/%s" % [ident, src])
			_ok(int(a.get("level", 0)) in [2, 3, 4], "matrix level %s/%s" % [ident, src])
			_ok((a.get("sources", []) as Array).has(str(src)), "matrix source %s/%s" % [ident, src])
			_ok(float(a.get("confidence", -1.0)) >= 0.0 and float(a.get("confidence", 2.0)) <= 1.0,
				"matrix confidence %s/%s" % [ident, src])
	# source→category 映射
	var expected := {"transponder": "iff", "iff": "iff", "elint": "elint",
		"signal": "elint", "radar": "sensor", "sensor": "sensor",
		"optical": "sensor", "ir": "sensor", "track": "track",
		"track_table": "track", "manual": "manual", "authorization": "manual",
		"database": "database"}
	for src2 in expected.keys():
		var s2 = _new_service()
		var r2: Dictionary = s2.ingest(_ev("CAT-" + str(src2), str(src2), "friend", 0.8))
		var cats: Array = r2.get("assessment", {}).get("categories", [])
		_ok(cats.has(str(expected[src2])), "category %s→%s" % [src2, expected[src2]],
			str(cats))
	# 身份冲突对
	var conflict_pairs: Array = [["friend", "hostile"], ["friend", "suspect"],
		["neutral", "hostile"], ["station", "friend"], ["suspect", "hostile"]]
	for pair in conflict_pairs:
		var s3 = _new_service()
		s3.ingest(_ev("CF", "transponder", str(pair[0]), 0.9))
		s3.ingest(_ev("CF", "optical", str(pair[1]), 0.9, {"category": "sensor"}))
		var a3: Dictionary = s3.get_assessment("CF")
		_ok(str(a3.get("identity", "")) in ["suspect", "unknown"],
			"冲突对 %s/%s → suspect/unknown" % [str(pair[0]), str(pair[1])],
			str(a3.get("identity")))
		_ok((a3.get("contradictions", []) as Array).size() > 0,
			"冲突对 contradictions " + str(pair))
		_ok(float(a3.get("spoof_suspicion", 0.0)) > 0.0, "冲突对 spoof " + str(pair))
		_ok(int(a3.get("level", 4)) <= 3, "冲突对 <=L3 " + str(pair))
	# 双源高/低置信 L4 边界
	var pairs: Array = [["transponder", "optical", 0.95, true], ["transponder", "elint", 0.95, true],
		["transponder", "optical", 0.2, false], ["transponder", "optical", 0.7, false]]
	for row in pairs:
		var s4 = _new_service()
		s4.ingest(_ev("LV", str(row[0]), "friend", float(row[2])))
		s4.ingest(_ev("LV", str(row[1]), "friend", float(row[2]),
			{"category": str(row[0]) if false else "sensor"} if str(row[1]) == "optical" \
			else {"category": "elint"}))
		var a4: Dictionary = s4.get_assessment("LV")
		if bool(row[3]):
			_eq(int(a4.get("level", 0)), 4, "双源高置信 L4 " + str(row))
		else:
			_ok(int(a4.get("level", 4)) <= 3, "双源低/中置信 <=L3 " + str(row))
	# 自动询问矩阵：多目标状态
	var s5 = _new_service({"auto": {"enabled": true, "interval_s": 1.0,
		"modes": ["mode_s"], "max_range_km": 500.0, "max_requests_per_tick": 3}})
	for i in range(5):
		s5.ingest(_ev("A" + str(i), "transponder", "unknown", 0.2,
			{"range_km": 100.0, "los": true, "emcon": false}))
	s5.set_target_state("A2", {"range_km": 9999.0, "los": true, "emcon": false})
	s5.set_target_state("A3", {"range_km": 100.0, "los": false, "emcon": false})
	s5.set_target_state("A4", {"range_km": 100.0, "los": true, "emcon": true})
	var aq: Dictionary = s5.auto_query_tick(1.0)
	var reqs: Array = aq.get("requests", [])
	_ok(reqs.size() <= 3, "auto max_requests_per_tick<=3", str(reqs.size()))
	var got_ids: Array = []
	for raw in reqs:
		got_ids.append(str((raw as Dictionary).get("target_id", "")))
		_ok(bool((raw as Dictionary).get("weapon", true)) == false, "auto request 无武器")
	_ok(("A0" in got_ids) or ("A1" in got_ids), "auto 选可询问目标")
	_ok(not ("A2" in got_ids), "auto 跳过超 range")
	_ok(not ("A3" in got_ids), "auto 跳过无 LOS")
	_ok(not ("A4" in got_ids), "auto 跳过 EMCON")
	_ok(s5.take_query_requests().size() == reqs.size(), "auto take 数量")
	_data_line("matrix", "5 身份×4 来源 · source→category · 冲突对 · L4 置信边界 · auto 多目标过滤")
