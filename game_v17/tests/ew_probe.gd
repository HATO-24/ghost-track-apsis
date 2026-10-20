extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# EW PROBE · 完整游戏-阶段3Q
#
# 验证：统一 EW 效果层（干扰/欺骗/假目标/EMCON/通信 spoof/激光/LWR/
# 诱饵）、持续时间/衰减/过期、可观测影响接口、Session 接入、存档、
# JSON、确定性；不写 world/TrackTable/UI。只跑一次。
# ═══════════════════════════════════════════════════════════════════

const EWService := preload("res://scripts/core/ew_service.gd")
const GameSession := preload("res://scripts/core/game_session.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("EW PROBE · 完整游戏-阶段3Q")
	print("════════════════════════════════════════════════════════════════")
	_test_setup_apply()
	_test_all_effect_types()
	_test_duration_decay_expire()
	_test_observation_effects()
	_test_comms_spoof()
	_test_transponder_emcon()
	_test_session_integration()
	_test_save_load_json()
	print("────────────────────────────────────────────────────────────────")
	print("EW PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("EW PROBE FAILED")
		quit(1)
	else:
		print("EW PROBE OK")
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


func _service() -> Object:
	return EWService.new({
		"observer": {"id": "own", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [{"id": "T1", "pos_km": [100.0, 0.0, 0.0]},
			{"id": "T2", "pos_km": [200.0, 0.0, 0.0]}],
	})


func _apply(s, etype: String, target := "T1", severity := 0.7,
		duration := 20.0, extra := {}) -> Dictionary:
	var e := {"effect": etype, "source_id": "jammer-1", "target_id": target,
		"severity": severity, "duration_s": duration}
	for k in extra.keys():
		e[k] = extra[k]
	return s.apply(e)


func _event_count(s, kind: String) -> int:
	var n := 0
	for raw in (s.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


# ── 1. setup / apply ────────────────────────────────────────────

func _test_setup_apply() -> void:
	print("")
	print("── 1. setup / apply ──")
	var s = _service()
	_ok(bool(s.ready), "ready", str(s.errors))
	_ok((s.errors as Array).is_empty(), "setup 无错误")
	_ok(String((s.observer as Dictionary).get("id", "")) == "own", "observer")
	_ok((s.targets as Array).size() == 2, "targets")
	var a: Dictionary = _apply(s, "noise_jam", "T1", 0.8, 20.0,
		{"band": "X", "params": {"bandwidth_mhz": 50.0}})
	_ok(bool(a.get("ok", false)), "apply noise_jam", str(a.get("reason", "")))
	var e: Dictionary = a.get("effect", {}) as Dictionary
	_eq(String(e.get("schema", "")), "ew_effect.v1", "effect schema")
	_eq(String(e.get("effect", "")), "noise_jam", "effect type")
	_eq(String(e.get("category", "")), "radar", "effect category")
	_eq(String(e.get("source_id", "")), "jammer-1", "source")
	_eq(String(e.get("target_id", "")), "T1", "target")
	_eq(String(e.get("band", "")), "X", "band")
	_ok(float(e.get("severity", 0.0)) == 0.8, "severity")
	_ok(float(e.get("duration_s", 0.0)) == 20.0, "duration")
	_ok(float(e.get("t_start", -1.0)) == 0.0, "t_start")
	_ok(float(e.get("t_end", -1.0)) == 20.0, "t_end")
	_eq(String(e.get("id", "")), "EW-00001", "effect id")
	_ok(bool(e.get("active", false)), "active")
	_ok((e.get("target_kinds", []) as Array).has("radar"), "target_kinds")
	_ok(not bool(e.get("writes_v15", true)), "不写 V15")
	_ok((s.active() as Array).size() == 1, "active 1")
	_ok((s.active("T1") as Array).size() == 1, "active target")
	_ok((s.active("T2") as Array).is_empty(), "active 其他 target 空")
	_ok(_event_count(s, "ew_applied") >= 1, "ew_applied event")
	var q: Dictionary = s.query_effect("noise_jam", "T1", "radar")
	_ok(bool(q.get("active", false)), "query active")
	_ok(float(q.get("severity", 0.0)) == 0.8, "query severity")
	_ok((q.get("effects", []) as Array).size() == 1, "query effects")
	_ok(not bool(q.get("reason", "") != ""), "query reason empty")
	_ok((s.query_effect("noise_jam", "T2") as Dictionary).get("active", true) == false,
		"query T2 no effect")
	_ok(not bool(s.query_effect("bad", "T1").get("ok", true)), "query 非法类型 false")
	_ok(_json_ok(s.vm()), "VM JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("ui", true)) == false, "不写 UI")
	# 非法 apply
	_ok(not bool(s.apply({"effect": "bad"}).get("ok", true)), "非法 effect false")
	_ok(not bool(s.apply({"effect": "noise_jam"}).get("ok", true)),
		"缺 source false")
	_ok(not bool(s.apply({"effect": "noise_jam", "source_id": "x", "duration_s": NAN}).get("ok", true)),
		"非有限 duration false")
	_ok(not bool(s.apply({"effect": "noise_jam", "source_id": "x", "duration_s": -2.0}).get("ok", true)),
		"非法 duration false")
	_ok(not bool(s.apply({}).get("ok", true)), "非法 payload false")


# ── 2. 十种效果 ──────────────────────────────────────────────

func _test_all_effect_types() -> void:
	print("")
	print("── 2. 十种效果类型 ──")
	var s = _service()
	for etype in ["noise_jam", "deception", "chaff", "false_target", "comms_jam",
			"comms_spoof", "emcon", "lwr", "laser_dazzle", "decoy"]:
		var r: Dictionary = _apply(s, etype, "T1", 0.7, 30.0)
		_ok(bool(r.get("ok", false)), "apply " + etype, str(r.get("reason", "")))
		_ok(String((r.get("effect", {}) as Dictionary).get("effect", "")) == etype,
			"effect type " + etype)
		_ok((s.active("T1") as Array).size() >= 1, "active " + etype)
		var fx: Dictionary = r.get("effect", {}) as Dictionary
		_ok((fx.get("target_kinds", []) as Array).size() >= 1, "target_kinds " + etype)
		_ok(float(fx.get("t_end", -1.0)) > 0.0, "t_end " + etype)
		_ok(float(fx.get("decay_per_s", -1.0)) >= 0.0, "decay 字段 " + etype)
		_ok(not bool(fx.get("writes_v15", true)), "不写 V15 " + etype)
	_ok((s.active() as Array).size() == 10, "十种 effect 均 active")
	for etype in ["noise_jam", "deception", "chaff", "false_target", "comms_jam",
			"comms_spoof", "emcon", "lwr", "laser_dazzle", "decoy"]:
		_ok((s.query_effect(etype) as Dictionary).get("active", false), "query " + etype)
	_ok(_json_ok(s.vm()), "all effects VM JSON")
	_ok((s.vm().get("counts", {}) as Dictionary).has("by_type"), "counts by_type")
	_eq(int((s.vm().get("counts", {}) as Dictionary).get("active", 0)), 10, "counts active 10")
	_ok(_event_count(s, "ew_applied") >= 10, "10 ew_applied events")


# ── 3. 持续时间 / 衰减 / 过期 ─────────────────────────────────

func _test_duration_decay_expire() -> void:
	print("")
	print("── 3. 持续时间 / 衰减 / 过期 ──")
	var s = _service()
	var r: Dictionary = _apply(s, "noise_jam", "T1", 0.8, 10.0,
		{"decay_per_s": 0.05})
	_ok(bool(r.get("ok", false)), "decay fixture")
	_eq(int(s.active().size()), 1, "初始 active")
	s.step(4.0)
	var e: Dictionary = s.active()[0]
	_ok(absf(float(e.get("remaining_severity", 0.0)) - 0.6) < 1.0e-6, "decay 0.6 @4s",
		str(e.get("remaining_severity", 0)))
	_ok(absf(float(e.get("age_s", 0.0)) - 4.0) < 1.0e-6, "age 4s")
	_ok(bool(s.query_effect("noise_jam", "T1").get("active", false)), "未过期 active")
	s.step(6.0)
	_ok(s.active().is_empty(), "decay 到 0 后移除")
	_ok(_event_count(s, "ew_expired") >= 1, "ew_expired event")
	_ok((s.active() as Array).is_empty(), "active 0")
	# duration 到期
	var s2 = _service()
	_apply(s2, "comms_jam", "T1", 0.5, 5.0)
	s2.step(6.0)
	_ok(s2.active().is_empty(), "duration 到期移除")
	# expire 单个/全部
	var s3 = _service()
	var r3: Dictionary = _apply(s3, "lwr", "T1", 0.8, 60.0)
	var id := String((r3.get("effect", {}) as Dictionary).get("id", ""))
	_ok(bool(s3.expire(id).get("ok", false)), "expire 单个")
	_ok(s3.active().is_empty(), "单个 expire 后空")
	_ok(not bool(s3.expire(id).get("ok", true)), "重复 expire false")
	_apply(s3, "noise_jam", "T1", 0.5, 60.0)
	_apply(s3, "chaff", "T1", 0.5, 60.0)
	var ea: Dictionary = s3.expire("")
	_ok(bool(ea.get("ok", false)), "expire all")
	_ok(int(ea.get("expired", 0)) == 2, "expire all 2")
	_ok(s3.active().is_empty(), "expire all 后空")
	# 即时 duration=0
	var s4 = _service()
	_apply(s4, "laser_dazzle", "T1", 0.8, 0.0)
	s4.step(1.0)
	_ok(s4.active().is_empty(), "duration=0 下一步过期")
	# 持久 emcon
	var s5 = _service()
	s5.set_emcon(true)
	_ok(bool(s5.emcon_active), "emcon active")
	s5.step(100.0)
	_ok(bool(s5.query_effect("emcon").get("active", false)), "emcon 持久")
	_ok(_json_ok(s5.vm()), "duration VM JSON")


# ── 4. 观测/识别影响 ─────────────────────────────────────────

func _test_observation_effects() -> void:
	print("")
	print("── 4. 观测/识别影响 ──")
	var s = _service()
	_apply(s, "noise_jam", "T1", 0.8, 60.0)
	var o: Dictionary = s.observation_effect("T1", "radar")
	_eq(String(o.get("schema", "")), "ew_observation_effect.v1", "obs effect schema")
	_ok(bool(o.get("jammed", false)), "jammed")
	_ok(float(o.get("confidence_mult", 1.0)) < 1.0, "置信度降级")
	_ok(float(o.get("delay_s", 0.0)) > 0.0, "干扰延迟")
	_ok(float(o.get("no_reply_chance", 0.0)) > 0.0, "无应答概率")
	_ok(not bool(o.get("produces_contact", true)), "不产生 contact")
	_ok(not bool(o.get("writes_track_table", true)), "不写 TrackTable")
	_ok((o.get("false_observations", []) as Array).is_empty(), "纯干扰无假观测")
	# deception + false_target + chaff → 假候选
	var s2 = _service()
	_apply(s2, "deception", "T1", 0.8, 60.0)
	_apply(s2, "chaff", "T1", 0.8, 60.0)
	_apply(s2, "false_target", "T1", 0.8, 60.0)
	var o2: Dictionary = s2.observation_effect("T1", "radar")
	_ok(float(o2.get("deception_severity", 0.0)) > 0.0, "deception severity")
	_ok(float(o2.get("chaff_severity", 0.0)) > 0.0, "chaff severity")
	_ok(float(o2.get("false_target_severity", 0.0)) > 0.0, "false_target severity")
	_ok(int(o2.get("false_candidate_count", 0)) > 0, "假观测候选")
	_ok(bool(o2.get("requires_confirmation", false)), "假候选需确认")
	_ok(not bool(o2.get("produces_contact", true)), "假候选不产生 contact")
	var cands: Array = o2.get("false_observations", []) as Array
	_ok(cands.size() == int(o2.get("false_candidate_count", -1)), "候选计数一致")
	var cand: Dictionary = cands[0]
	_ok(bool(cand.get("fake", false)), "candidate fake")
	_ok(String(cand.get("identity", "")) == "unknown", "candidate identity unknown")
	_ok(not bool(cand.get("produces_contact", true)), "candidate 不产生 contact")
	_ok(not bool(cand.get("writes_track_table", true)), "candidate 不写 track")
	_ok(String(cand.get("candidate_id", "")) != "", "candidate_id")
	# chaff 单独
	var s3 = _service()
	_apply(s3, "chaff", "T1", 0.7, 60.0)
	var o3: Dictionary = s3.observation_effect("T1", "radar")
	_ok(float(o3.get("chaff_severity", 0.0)) > 0.0, "chaff obs")
	_ok(int(o3.get("false_candidate_count", 0)) > 0, "chaff 假观测")
	# 激光致盲/ LWR
	var s4 = _service()
	_apply(s4, "laser_dazzle", "T1", 0.8, 60.0)
	_apply(s4, "lwr", "T1", 0.7, 60.0)
	var o4: Dictionary = s4.observation_effect("T1", "optical")
	_ok(bool(o4.get("dazzled", false)), "dazzled")
	_ok(float(o4.get("laser_dazzle_severity", 0.0)) > 0.0, "dazzle severity")
	_ok(bool(o4.get("lwr_alert", false)), "lwr alert")
	_ok(float(o4.get("confidence_mult", 1.0)) < 1.0, "dazzle 置信度降级")
	# EMCON
	var s5 = _service()
	s5.set_emcon(true)
	var o5: Dictionary = s5.observation_effect("T1", "radar")
	_ok(bool(o5.get("emcon", false)), "emcon observation")
	# 诱饵
	var s6 = _service()
	_apply(s6, "decoy", "T1", 0.8, 60.0)
	var o6: Dictionary = s6.observation_effect("T1", "radar")
	_ok(float(o6.get("decoy_severity", 0.0)) > 0.0, "decoy severity")
	_ok(int(o6.get("false_candidate_count", 0)) > 0, "decoy 假候选")
	# target 过滤
	var o7: Dictionary = s.observation_effect("T2", "radar")
	_ok(not bool(o7.get("jammed", true)), "T2 不受 T1 干扰")
	_ok(_json_ok(o), "obs effect JSON")
	_ok(_json_ok(o2), "deception JSON")


# ── 5. 通信 / spoof ──────────────────────────────────────────

func _test_comms_spoof() -> void:
	print("")
	print("── 5. 通信干扰 / spoof ──")
	var s = _service()
	_apply(s, "comms_jam", "T1", 0.8, 60.0)
	var c: Dictionary = s.comms_effect("T1")
	_eq(String(c.get("schema", "")), "ew_comms_effect.v1", "comms schema")
	_ok(bool(c.get("jammed", false)), "comms jammed")
	_ok(float(c.get("latency_add_s", 0.0)) > 0.0, "通信延迟")
	_ok(float(c.get("failure_chance", 0.0)) > 0.0, "通信失败率")
	_ok(not bool(c.get("writes_v15", true)), "通信不写 V15")
	# spoof
	var s2 = _service()
	_apply(s2, "comms_spoof", "T1", 0.8, 60.0,
		{"params": {"text": "FRIENDLY REQUEST DOCK"}})
	var c2: Dictionary = s2.comms_effect("T1")
	_ok(bool(c2.get("spoofed", false)), "spoofed")
	_eq(String(c2.get("spoof_text", "")), "FRIENDLY REQUEST DOCK", "spoof text")
	_ok(bool(c2.get("suspicious", false)), "suspicious")
	_ok(bool(c2.get("requires_confirmation", false)), "spoof 需确认")
	_ok(not bool(c2.get("auto_execute", true)), "不自动执行")
	_ok((c2.get("spoof_events", []) as Array).size() >= 1, "spoof event")
	var se: Dictionary = (c2.get("spoof_events", []) as Array)[0]
	_ok(not bool(se.get("auto_execute", true)), "spoof event 不自动执行")
	_ok(bool(se.get("suspicious", false)), "spoof event suspicious")
	_ok(not bool(c2.get("produces_contact", true)), "spoof 不产生 contact")
	# target 过滤
	var c3: Dictionary = s.comms_effect("T2")
	_ok(not bool(c3.get("jammed", true)), "T2 无 comms jam")
	# 默认 comms_effect 无效果
	var s3 = _service()
	var c4: Dictionary = s3.comms_effect("T1")
	_ok(not bool(c4.get("jammed", true)), "无 jam")
	_ok(not bool(c4.get("spoofed", true)), "无 spoof")
	_ok(_json_ok(c), "comms JSON")
	_ok(_json_ok(c2), "spoof JSON")


# ── 6. 应答机 / EMCON ────────────────────────────────────────

func _test_transponder_emcon() -> void:
	print("")
	print("── 6. 应答机 / EMCON ──")
	var s = _service()
	_apply(s, "comms_spoof", "T1", 0.8, 60.0)
	var t: Dictionary = s.transponder_effect("T1")
	_eq(String(t.get("schema", "")), "ew_transponder_effect.v1", "transponder schema")
	_ok(bool(t.get("reply_forged", false)), "reply forged")
	_ok(float(t.get("confidence_mult", 1.0)) < 1.0, "transponder 置信度降级")
	_ok(bool(t.get("requires_confirmation", false)), "transponder 需确认")
	_ok(not bool(t.get("hostile", true)), "不判 hostile")
	_ok(String(t.get("identity", "")) == "unknown", "identity unknown")
	_ok(not bool(t.get("produces_contact", true)), "不产生 contact")
	_ok(not bool(t.get("writes_v15", true)), "不写 V15")
	# deception / chaff 降低应答置信度
	var s2 = _service()
	_apply(s2, "deception", "T1", 0.8, 60.0)
	_apply(s2, "chaff", "T1", 0.8, 60.0)
	var t2: Dictionary = s2.transponder_effect("T1")
	_ok(float(t2.get("confidence_mult", 1.0)) < 1.0, "deception/chaff 应答置信度")
	# EMCON 开/关
	var s3 = _service()
	var on: Dictionary = s3.set_emcon(true)
	_ok(bool(on.get("ok", false)), "set_emcon(true)")
	_ok(bool(on.get("active", false)), "emcon on")
	_ok(bool(on.get("passive_ok", false)), "emcon passive_ok")
	_ok(bool(s3.emcon_active), "emcon_active")
	_ok((s3.active("", "radar") as Array).size() >= 1, "emcon radar effect")
	var off: Dictionary = s3.set_emcon(false)
	_ok(bool(off.get("ok", false)), "set_emcon(false)")
	_ok(not bool(s3.emcon_active), "emcon_active false")
	_ok((s3.active("", "radar") as Array).is_empty(), "emcon off 移除效果")
	_ok(_json_ok(t), "transponder JSON")
	_ok(_json_ok(on), "emcon JSON")


# ── 7. GameSession 接入 ─────────────────────────────────────

func _test_session_integration() -> void:
	print("")
	print("── 7. GameSession 接入 ──")
	var s = GameSession.new()
	var cfg := {"ew_service": {
		"observer": {"id": "own"}, "targets": [{"id": "T1", "pos_km": [100.0, 0.0, 0.0]}]}}
	var br: Dictionary = s.boot(cfg)
	_ok(bool(br.get("ok", false)), "session boot", str(s.errors))
	_ok(s.ew_service != null and bool(s.ew_service.ready), "session ew_service ready")
	_ok((s.snapshot().get("ew") is Dictionary), "snapshot ew")
	var ap: Dictionary = s.apply_ew({"effect": "noise_jam", "source_id": "jammer",
		"target_id": "T1", "severity": 0.8, "duration_s": 20.0})
	_ok(bool(ap.get("ok", false)), "session apply_ew")
	_ok((s.ew_active("T1") as Array).size() >= 1, "session ew_active")
	_ok(float(s.ew_observation_effect("T1").get("confidence_mult", 1.0)) < 1.0,
		"session observation effect")
	var tk: Dictionary = s.tick(2.0)
	_ok(bool(tk.get("ok", false)), "session tick")
	var ew_step: Dictionary = tk.get("ew_step", {}) if tk.get("ew_step") is Dictionary else {}
	_ok(bool(ew_step.get("enabled", false)), "tick ew enabled")
	_ok(int(ew_step.get("events", 0)) >= 1, "tick ew events")
	_ok(bool(tk.get("components", {}).get("ew", false)), "tick components ew")
	var has_ew_bus := false
	for raw in (s.snapshot().get("events", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("type", "")).begins_with("ew."):
			has_ew_bus = true
	_ok(has_ew_bus, "EW 事件总线")
	# EMCON + comms/spoof effect wrappers
	var em: Dictionary = s.set_ew_emcon(true)
	_ok(bool(em.get("ok", false)), "session set_ew_emcon")
	_ok(bool(s.ew_service.emcon_active), "session emcon active")
	_ok(bool(s.ew_comms_effect("T1").has("ok")), "session comms effect")
	_ok(bool(s.ew_transponder_effect("T1").has("ok")), "session transponder effect")
	# 未启用时退化
	var s0 = GameSession.new()
	s0.boot({})
	_ok(s0.ew_service == null, "无配置退化")
	_ok(not bool(s0.apply_ew({"effect": "noise_jam", "source_id": "x"}).get("ok", true)),
		"无 ew apply false")
	_ok(not bool(s0.set_ew_emcon(true).get("ok", true)), "无 ew emcon false")
	_ok((s0.ew_active() as Array).is_empty(), "无 ew active 空")


# ── 8. save/load / JSON / 确定性 ─────────────────────────────

func _test_save_load_json() -> void:
	print("")
	print("── 8. save/load / JSON / 确定性 ──")
	var s = _service()
	_apply(s, "noise_jam", "T1", 0.8, 60.0)
	_apply(s, "comms_spoof", "T1", 0.7, 60.0, {"params": {"text": "HOLD"}})
	s.set_emcon(true)
	s.step(2.0)
	var text: String = s.save_state()
	var p = JSON.parse_string(text)
	_ok(p is Dictionary, "save JSON")
	_ok(String((p as Dictionary).get("schema", "")) == "v17.ew_service_save.v1", "save schema")
	_ok(String((p as Dictionary).get("version", "")) == "1.0.0", "save version")
	_ok((p as Dictionary).get("effects") is Array, "save effects")
	var r = _service()
	var lr: Dictionary = r.load_state(text)
	_ok(bool(lr.get("ok", false)), "load ok", str(lr.get("reason", "")))
	_ok((r.effects as Array).size() == (s.effects as Array).size(), "load effects count")
	_ok(absf(float(r.t) - float(s.t)) < 1.0e-9, "load t")
	_ok(bool(r.emcon_active), "load emcon")
	_ok((r.active() as Array).size() >= 2, "load active")
	_ok(float(r.observation_effect("T1").get("confidence_mult", 1.0)) < 1.0,
		"load observation effect")
	_ok(_json_ok(r.vm()), "loaded VM JSON")
	_ok(s.save_state() == s.save_state(), "save 确定性")
	# 非法快照
	var bad: Array = [["empty", ""], ["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future", JSON.stringify({"schema": "v17.ew_service_save.v1",
			"version": "9.0.0", "effects": []})],
		["old", JSON.stringify({"schema": "v17.ew_service_save.v1",
			"version": "0.9.0", "effects": []})],
		["no effects", JSON.stringify({"schema": "v17.ew_service_save.v1",
			"version": "1.0.0"})]]
	for raw in bad:
		var c: Array = raw
		_ok(not bool(r.load_state(c[1]).get("ok", true)), "拒绝快照: " + String(c[0]))
	# 双实例确定性
	var a = _service()
	var b = _service()
	for svc in [a, b]:
		svc.apply({"effect": "noise_jam", "source_id": "jammer", "target_id": "T1",
			"severity": 0.8, "duration_s": 20.0})
		svc.apply({"effect": "comms_spoof", "source_id": "spoofer", "target_id": "T1",
			"severity": 0.7, "duration_s": 20.0, "params": {"text": "X"}})
		svc.step(1.0)
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(_json_ok(a.summary()), "summary JSON")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
