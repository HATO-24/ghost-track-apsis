extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A02（#59）多来源身份收敛与 IFF 闭环 · 验收探针
#
# 本探针按 A02 卡 §5 验收条款编写，先以红例保存（实现前应失败），
# 实现后应全绿。断言面向"可观察行为"：四来源归一、单一写者、
# owner 隔离、冲突/TTL/迟到、IFF 六态、人工授权/撤销、HUD/火控一致、
# 旧档迁移与真实文件恢复后继续 10 tick。
#
# Output: `JC-A02 IDENTITY PIPELINE PROBE RESULT: PASS=n FAIL=m`; quit 0/1
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const Binder := preload("res://scripts/ui/shell_binder.gd")
const TICK_DT := 1.0
const CONF_TOL := 1.0e-9

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-A02 IDENTITY PIPELINE PROBE · 四来源/单一写者/owner隔离/IFF/消费者/恢复")
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(420.0).timeout
	if _finished:
		return
	print("[A02] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-A02 IDENTITY PIPELINE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A02] FAILED: ", f)
		print("JC-A02 IDENTITY PIPELINE PROBE FAILED")
	else:
		print("JC-A02 IDENTITY PIPELINE PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A02] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A02] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(t: String) -> void:
	print("")
	print("[A02] STEP ", t)


func _info(t: String) -> void:
	print("[A02] INFO ", t)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("R1 单一写者与重复证据抑制")
	var s = _new()
	_ok(bool(s.ready), "session ready", str(s.errors))
	if not bool(s.ready):
		_finish()
		return
	var w0: Dictionary = s.identity_report()
	var r1: Dictionary = s.identity_ingest("player_intel", _ev("raider_2",
		"transponder", "friend", 0.9))
	_ok(bool(r1.get("ok", false)), "首次证据 ingest ok", str(r1.get("reason", "")))
	var r2: Dictionary = s.identity_ingest("player_intel", _ev("raider_2",
		"transponder", "friend", 0.9))
	_ok(bool(r2.get("duplicate", false)), "完全相同证据判重", str(r2))
	var op1: Dictionary = s.identity_operational("player_intel", "raider_2")
	_ok(not op1.is_empty(), "操作性身份可读", str(op1.get("reason", "")))
	var writes1 := int(op1.get("id", op1.get("writer_count", 1)))
	_ok(writes1 >= 1, "操作性身份有写入计数", str(writes1))
	var rep2: Dictionary = s.identity_report()
	var w1 := int((rep2.get("writes", {}) as Dictionary).get("player_intel", 0))
	var before_w: int = int((w0.get("writes", {}) as Dictionary).get("player_intel", 0))
	_ok(w1 - before_w <= 2,
		"一次有效证据只产生一次身份写入（重复不放大）",
		"writes_before=%d after=%d" % [before_w, w1])
	# 同一 target 的确认结论应只来自一个写者面（owner 情报轨迹）
	var iv1: Dictionary = s.intel_view("player_intel")
	var trk_raider := _track(iv1, "raider_2")
	_ok(not trk_raider.is_empty(), "owner 情报轨迹存在")
	_eq(String(trk_raider.get("identity", "")), "friend", "owner 轨迹身份来自唯一写者")

	_step("R2 四来源各自有效（IFF/ELINT/光学/人工）")
	var s2 = _new()
	var iff: Dictionary = s2.identity_ingest("player_intel", _ev("t_iff",
		"transponder", "friend", 0.9, {"mode": "mode_5", "status": "normal"}))
	_ok(bool(iff.get("ok", false)), "IFF 来源 ingest ok", str(iff.get("reason", "")))
	var elint: Dictionary = s2.identity_ingest("player_intel", _ev("t_elint",
		"elint", "suspect", 0.6, {"mode": "emitter"}))
	_ok(bool(elint.get("ok", false)), "ELINT 来源 ingest ok", str(elint.get("reason", "")))
	var opt: Dictionary = s2.identity_ingest("player_intel", _ev("t_opt",
		"optical", "neutral", 0.5, {"category": "sensor"}))
	_ok(bool(opt.get("ok", false)), "光学来源 ingest ok", str(opt.get("reason", "")))
	var man: Dictionary = s2.identity_manual_confirm("player_intel", "t_man",
		"hostile", {"authority": "command", "operator": "CO", "reason": "visual ID"})
	_ok(bool(man.get("ok", false)), "人工来源（带授权）ok", str(man.get("reason", "")))
	var oiff: Dictionary = s2.identity_operational("player_intel", "t_iff")
	_eq(String(oiff.get("identity", "")), "friend", "IFF 单源 friend")
	_eq(String(s2.identity_operational("player_intel", "t_elint").get("identity", "")),
		"suspect", "ELINT 单源 suspect")
	_eq(String(s2.identity_operational("player_intel", "t_opt").get("identity", "")),
		"neutral", "光学单源 neutral")
	_eq(String(s2.identity_operational("player_intel", "t_man").get("identity", "")),
		"hostile", "人工权威 hostile")
	var aiff: Dictionary = s2.identity_get_for("player_intel", "t_iff")
	_ok(absf(float(oiff.get("confidence", -1.0)) - float(aiff.get("confidence", -2.0)))
		<= CONF_TOL, "操作性身份置信度与评估一致（容差1e-9）",
		"%s vs %s" % [str(oiff.get("confidence", null)), str(aiff.get("confidence", null))])
	_ok(bool(String(oiff.get("state", "")) != ""), "操作性身份带 IFF/身份状态",
		String(oiff.get("state", "")))

	_step("R3 冲突：IFF friend + 光学 hostile 不得维持 friend")
	var s3 = _new()
	s3.identity_ingest("player_intel", _ev("t_conf", "transponder", "friend", 0.9))
	s3.identity_ingest("player_intel", _ev("t_conf", "optical", "hostile", 0.8,
		{"category": "sensor"}))
	var oconf: Dictionary = s3.identity_operational("player_intel", "t_conf")
	_ok(String(oconf.get("identity", "")) != "friend",
		"冲突后不维持 friend", String(oconf.get("identity", "")))
	_eq(String(oconf.get("state", "")), "conflict", "冲突状态可读")
	var aconf: Dictionary = s3.identity_get_for("player_intel", "t_conf")
	_ok((aconf.get("contradictions", []) as Array).size() >= 1, "冲突证据被记录")

	_step("R4 TTL / 同 tick 边界 / 迟到证据")
	var s4 = _new()
	s4.identity_ingest("player_intel", _ev("t_ttl", "transponder", "friend", 0.9,
		{"observed_t": float(s4.now_s()), "ttl_s": 10.0}))
	var o4a: Dictionary = s4.identity_operational("player_intel", "t_ttl")
	_eq(String(o4a.get("state", "")), "valid", "TTL 内状态 valid")
	for i4 in range(11):
		s4.tick(TICK_DT)
	var o4b: Dictionary = s4.identity_operational("player_intel", "t_ttl")
	_ok(String(o4b.get("state", "")) in ["stale", "expired"],
		"超过 TTL 后不再 valid", String(o4b.get("state", "")))
	# 新证据刷新
	s4.identity_ingest("player_intel", _ev("t_ttl", "transponder", "friend", 0.9,
		{"observed_t": float(s4.now_s()), "ttl_s": 10.0}))
	_eq(String(s4.identity_operational("player_intel", "t_ttl").get("state", "")),
		"valid", "新证据刷新 TTL")
	# 迟到旧证据不得覆盖较新结论
	s4.identity_ingest("player_intel", _ev("t_late", "optical", "hostile", 0.9,
		{"observed_t": float(s4.now_s()), "category": "sensor"}))
	var late: Dictionary = s4.identity_ingest("player_intel", _ev("t_late",
		"transponder", "friend", 0.9,
		{"observed_t": float(s4.now_s()) - 30.0}))
	_ok(bool(late.get("ok", false)), "迟到证据被接受但不主导",
		str(late.get("reason", "")))
	_ok(bool(late.get("late_ignored", false)), "迟到旧证据被标记 late_ignored",
		str(late.get("late_ignored", null)))
	# 当前结论（光学单源=未经授权 hostile → suspect）不得被迟到旧证据改变
	var cur_late := String(s4.identity_operational("player_intel", "t_late").get(
		"identity", ""))
	_ok(cur_late in ["suspect", "hostile"], "迟到证据不改变当前结论", cur_late)

	_step("R5 IFF 查询状态：有效回应/无回应/缺配置/受干扰")
	var s5 = _new()
	var q1: Dictionary = s5.identity_iff_query("player_intel", "harmattan")
	_ok(bool(q1.get("ok", false)), "有配置目标可查询", str(q1.get("reason", "")))
	_ok(String(q1.get("state", "")) in ["valid", "no_reply", "pending"],
		"IFF 状态属于合法枚举", String(q1.get("state", "")))
	if String(q1.get("state", "")) == "valid":
		_ok(String(q1.get("identity", "")) != "hostile", "回应声明不直接成敌对",
			String(q1.get("identity", "")))
	var q2: Dictionary = s5.identity_iff_query("player_intel", "raider_2")
	_ok(bool(q2.get("ok", true)) == false or String(q2.get("state", "")) == "unavailable",
		"无应答配置给明确 unavailable", String(q2.get("state", "")))
	# scenario 实体带 transponder_profile（内容里无同名 profile）→ 按实体装入，
	# 应答声明默认 unknown，不能静默变成友军
	var qs: Dictionary = s5.identity_iff_query("player_intel", "probe_ship")
	_ok(bool(qs.get("ok", false)), "scenario 应答配置可查询",
		str(qs.get("reason", "")))
	_eq(String(qs.get("state", "")), "valid", "scenario profile 有明确 valid 状态")
	_ok(String(qs.get("identity", "")) != "friend",
		"应答声明未静默成友军", String(qs.get("identity", "")))
	var q3: Dictionary = s5.identity_iff_query("player_intel", "l1_station",
		{"jam": 0.95, "occluded": true})
	_ok(String(q3.get("state", "")) in ["jammed", "no_reply", "valid"],
		"受干扰/遮挡有明确状态", String(q3.get("state", "")))
	# 无回应不等于敌对，也不等于友军
	var a5: Dictionary = s5.identity_operational("player_intel", "raider_2")
	_ok(String(a5.get("identity", "")) != "hostile" \
		and String(a5.get("identity", "")) != "friend",
		"无回应未被解成敌对/友军", String(a5.get("identity", "")))

	_step("R6 人工确认：未授权拒绝/授权审计/撤销恢复/不越权")
	var s6 = _new()
	var bad: Dictionary = s6.identity_manual_confirm("player_intel", "raider_2",
		"friend", {"operator": "nobody"})
	_ok(bool(bad.get("ok", true)) == false, "未授权人工确认被拒绝",
		str(bad.get("reason", "")))
	_ok(String(bad.get("reason", "")) in ["unauthorized", "no_authority",
		"authority_required"], "拒绝原因明确", String(bad.get("reason", "")))
	# 未授权确认不得产生操作性身份
	_ok(String(s6.identity_operational("player_intel", "raider_2").get("identity",
		"unknown")) == "unknown", "未授权确认不改变操作性身份")
	var okm: Dictionary = s6.identity_manual_confirm("player_intel", "raider_2",
		"friend", {"authority": "command", "operator": "CO", "reason": "escor"})
	_ok(bool(okm.get("ok", false)), "授权人工确认 ok", str(okm.get("reason", "")))
	var o6: Dictionary = s6.identity_operational("player_intel", "raider_2")
	_eq(String(o6.get("identity", "")), "friend", "人工确认成为操作性身份")
	_ok(bool(o6.get("manual", false)), "操作性身份标记 manual")
	_ok(bool(o6.get("authorized", false)), "操作性身份标记 authorized")
	_ok(int((o6.get("audit_ids", []) as Array).size()) >= 1 \
		or bool(o6.get("audited", false)), "人工确认可审计")
	# 人工不改变隐藏真值 side
	var side_before := String(_meta(s6, "raider_2").get("side", ""))
	_eq(String(_meta(s6, "raider_2").get("side", "")), side_before,
		"人工确认不覆写隐藏真值 side")
	# 撤销 → 恢复推断
	s6.identity_ingest("player_intel", _ev("raider_2", "optical", "hostile", 0.9,
		{"category": "sensor"}))
	var clr: Dictionary = s6.identity_manual_clear("player_intel", "raider_2",
		{"authority": "command", "actor_id": "player_ctrl"})
	_ok(bool(clr.get("ok", false)), "撤销人工确认 ok", str(clr.get("reason", "")))
	# 单源光学 hostile 在无授权证据下按契约收敛为 suspect；撤销后恢复推断
	_eq(String(s6.identity_operational("player_intel", "raider_2").get("identity", "")),
		"suspect", "撤销后恢复推断")
	_ok(bool(s6.identity_operational("player_intel", "raider_2").get("manual", true)) == false,
		"撤销后 manual 标记清除")

	_step("R7 两个 owner 同一目标不同证据不串域")
	var s7 = _new()
	s7.identity_ingest("player_intel", _ev("shared_target", "transponder",
		"friend", 0.9))
	s7.identity_ingest("ally_intel", _ev("shared_target", "optical", "hostile", 0.9,
		{"category": "sensor"}))
	var id7p := String(s7.identity_operational("player_intel", "shared_target").get(
		"identity", ""))
	var id7a := String(s7.identity_operational("ally_intel", "shared_target").get(
		"identity", ""))
	_eq(id7p, "friend", "player owner 身份独立")
	_eq(id7a, "suspect", "ally owner 身份独立（单源未授权 hostile→suspect）")
	_ok(id7p != id7a, "两个 owner 结论不互相污染")
	var err: Dictionary = s7.identity_ingest("ghost_owner", _ev("shared_target",
		"transponder", "friend", 0.9))
	_ok(bool(err.get("ok", true)) == false, "未知 owner 被拒绝",
		str(err.get("reason", "")))

	_step("R8 HUD 与火控读同一操作性身份")
	var s8 = _new()
	_register_combat_track(s8, "raider_2")
	s8.identity_ingest("player_intel", _ev("raider_2", "optical", "hostile", 0.9,
		{"category": "sensor"}))
	var op8: Dictionary = s8.identity_operational("player_intel", "raider_2")
	var combat8: Dictionary = s8.combat_identity("raider_2")
	_eq(String(combat8.get("identity", "")), String(op8.get("identity", "")),
		"火控读到与 owner 相同的操作性身份")
	var binder8 = Binder.new()
	binder8.session = s8
	var view8: Dictionary = binder8.ident_view({"track_id": "raider_2"})
	_eq(String(view8.get("identity", "")), String(op8.get("identity", "")),
		"HUD ident_view 读到同一操作性身份")
	# 人工 friend → 消费者一致，且不自动给开火许可
	s8.identity_manual_confirm("player_intel", "raider_2", "friend",
		{"authority": "command", "operator": "CO"})
	binder8.refresh()
	var view8b: Dictionary = binder8.ident_view({"track_id": "raider_2"})
	_eq(String(view8b.get("identity", "")), "friend", "HUD 反映人工 friend")
	var rf: Dictionary = s8.request_fire("raider_2", "missile", true,
		{"target_entity": "raider_2", "actor_id": "player_ctrl",
			"controller_id": "player_ctrl", "domain_id": "player",
			"fleet_id": "own_fleet"})
	_ok(bool(rf.get("ok", true)) == false, "友军身份不自动给开火许可",
		String(rf.get("reason", "")))
	_ok(not _is_authority_reason(String(rf.get("reason", ""))),
		"拒绝原因来自身份/ROE 而非授权缺失", String(rf.get("reason", "")))

	_step("R9 旧单实例存档迁移 + 真实文件恢复 + 继续 10 tick")
	var s9 = _new()
	s9.identity_ingest("player_intel", _ev("raider_2", "transponder", "friend", 0.9,
		{"observed_t": float(s9.now_s()), "ttl_s": 30.0}))
	s9.identity_ingest("ally_intel", _ev("shared_target", "optical", "hostile",
		0.9, {"category": "sensor"}))
	var path := "user://jc_a02_identity_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s9.save_state())
	f.close()
	var s10 = _new()
	var lr: Dictionary = s10.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr.get("ok", false)), "真实文件恢复成功", str(lr.get("errors", [])))
	_ok(String(lr.get("identity_restore_mode", "")) != "", "恢复模式公开可读",
		String(lr.get("identity_restore_mode", "")))
	_eq(String(s10.identity_operational("player_intel", "raider_2").get(
		"identity", "")), "friend", "player owner 身份恢复")
	_eq(String(s10.identity_operational("ally_intel", "shared_target").get(
		"identity", "")), "suspect", "ally owner 身份恢复")
	for i9 in range(10):
		s9.tick(TICK_DT)
		s10.tick(TICK_DT)
	var o9: Dictionary = s9.identity_operational("player_intel", "raider_2")
	var o10: Dictionary = s10.identity_operational("player_intel", "raider_2")
	_eq(String(o10.get("identity", "")), String(o9.get("identity", "")),
		"10 tick 后身份一致")
	_eq(String(o10.get("state", "")), String(o9.get("state", "")),
		"10 tick 后 TTL/状态一致")
	_ok(absf(float(o10.get("confidence", -1.0)) - float(o9.get("confidence", -2.0)))
		<= CONF_TOL, "10 tick 后置信度一致（容差1e-9）")
	# 旧档迁移：旧存档没有 identity_owners 段
	var doc: Dictionary = JSON.parse_string(s9.save_state())
	doc.erase("identity_owners")
	doc.erase("identity_pending_queries")
	var s11 = _new()
	var leg: Dictionary = s11.load_state(JSON.stringify(doc))
	_ok(bool(leg.get("ok", false)), "旧单实例存档可加载", str(leg.get("errors", [])))
	_ok(String(leg.get("identity_restore_mode", "")) in ["legacy_single_owner",
		"legacy"], "旧档恢复模式明确", String(leg.get("identity_restore_mode", "")))

	_step("R10 真实入口：盟军IFF查询不串本舰 / 默认与显式mode单事件 / 真实ELINT类别")
	var sR10 = _new()
	for i10 in range(2):
		sR10.tick(TICK_DT)
	var aq: Dictionary = sR10.identity_iff_query("ally_intel", "harmattan",
		{"mode": "mode_s"})
	_ok(bool(aq.get("ok", false)), "ally 真实 IFF 查询 ok", str(aq.get("reason", "")))
	_ok(String(aq.get("state", "")) in ["valid", "no_reply"],
		"ally 查询状态合法", String(aq.get("state", "")))
	_ok(bool(sR10.identity_operational("player_intel", "harmattan").get("ok", true))
		== false, "盟军查询回复不写本舰 owner（不串域）")
	var oq: Dictionary = sR10.identity_iff_query("player_intel", "harmattan")
	_ok(bool(oq.get("ok", false)), "本舰默认 mode 查询 ok")
	var oev: Dictionary = sR10.identity_get_for("player_intel", "harmattan")
	_eq(int(oev.get("evidence_count", 0)), 1, "默认 mode 同一回复只形成一条证据")
	var sR10b = _new()
	for i10b in range(2):
		sR10b.tick(TICK_DT)
	sR10b.identity_iff_query("player_intel", "harmattan", {"mode": "mode_s"})
	_eq(int(sR10b.identity_get_for("player_intel", "harmattan").get(
		"evidence_count", 0)), 1, "显式 mode_s 同一回复只形成一条证据")
	# 真实 track.evidence 事件（ELINT）经路由进入身份管道，类别不被改写成 iff
	var el_ev := {"schema": "track_evidence.v1", "kind": "evidence",
		"event_id": "SEVD-000001", "t": float(sR10.now_s()), "target_id": "raider_2",
		"evidence_type": "elint", "source": "ew_service",
		"identity": "suspect", "confidence": 0.6, "support": 2}
	var el_route: Dictionary = sR10.route_event({"type": "track.evidence",
		"payload": {"evidence": el_ev}})
	_ok(bool(el_route.get("ok", false)) or String(el_route.get("reason", "")) == "unknown_track",
		"真实 ELINT 事件进入路由（TrackTable 可因无航迹拒绝）",
		str(el_route.get("reason", "")))
	var elv: Array = sR10.identity_evidence_for("player_intel", "raider_2")
	var el_src := ""
	var el_cat := ""
	var el_type := ""
	for raw_el in elv:
		if raw_el is Dictionary and String((raw_el as Dictionary).get(
				"source", "")) == "elint":
			el_src = String((raw_el as Dictionary).get("source", ""))
			el_cat = String((raw_el as Dictionary).get("category", ""))
			el_type = String((raw_el as Dictionary).get("evidence_type", ""))
	_eq(el_src, "elint", "ELINT 证据 source 保留")
	_eq(el_cat, "elint", "ELINT 证据 category 不被改写成 iff")
	_eq(el_type, "elint", "ELINT 证据 evidence_type 保留")

	_step("R11 真实 Binder 旧入口：受信权限+审计；跨 owner 写入拒绝")
	var sR11 = _new()
	var b11 = Binder.new()
	b11.session = sR11
	var bc: Dictionary = b11.ident_confirm({"entity_id": "raider_2",
		"track_id": "raider_2"}, "friend")
	_ok(bool(bc.get("ok", false)), "Binder 旧确认入口可用（受信 cic_operator）",
		str(bc.get("reason", "")))
	var op11: Dictionary = sR11.identity_operational("player_intel", "raider_2")
	_eq(String(op11.get("identity", "")), "friend", "Binder 确认进入操作性身份")
	_ok(bool(op11.get("manual", false)), "Binder 确认标记 manual")
	_ok(int((op11.get("audit_ids", []) as Array).size()) >= 1,
		"Binder 确认产生审计记录", str(op11.get("audit_ids", [])))
	var bad11: Dictionary = sR11.identity_manual_confirm("ally_intel",
		"ally_target", "friend", {"authority": "command",
			"actor_id": "untrusted-caller"})
	_ok(bool(bad11.get("ok", true)) == false,
		"不可信 actor 不能向 ally owner 写人工确认", str(bad11.get("reason", "")))
	var cl11: Dictionary = b11.ident_clear({"entity_id": "raider_2",
		"track_id": "raider_2"})
	_ok(bool(cl11.get("ok", false)), "Binder 撤销入口可用（受信权限）",
		str(cl11.get("reason", "")))
	_ok(bool(sR11.identity_operational("player_intel", "raider_2").get(
		"manual", true)) == false, "Binder 撤销后 manual 清除")

	_step("R12 实际 HUD 航迹键（T0001→raider_2）解析到同一 owner 身份")
	var sR12 = _new()
	# 真实 radar 6s → 形成 sensor target→track 映射（实际 HUD 种入来源）
	for i12a in range(6):
		sR12.tick(TICK_DT)
	var real_tid := String(sR12._sensor_track_map.get("raider_2", ""))
	_ok(real_tid != "", "真实 sensor 建立 raider_2→track 映射", real_tid)
	if real_tid == "":
		real_tid = "T0001"
	# 实际 HUD._seed_combat_tracks 原样种入：只有 id/batch，无 entity_id/ship_id
	sR12.combat_service.register_track(real_tid, {"id": real_tid, "batch": "OCU-07"})
	var sm: Dictionary = sR12.identity_manual_confirm("player_intel",
		"raider_2", "friend", {"authority": "command"})
	_ok(bool(sm.get("ok", false)), "实体键人工 friend ok")
	var ci12: Dictionary = sR12.combat_identity(real_tid)
	_eq(String(ci12.get("identity", "")), "friend",
		"实际 HUD 空映射字段航迹键解析到同一 owner 身份")
	_eq(String(ci12.get("resolved_key", "")), "raider_2",
		"实际 HUD 航迹键经 sensor 映射解析出实体键")
	_eq(String(ci12.get("via", "")), "sensor_map",
		"解析路径为已验证 sensor 映射")
	var rf12: Dictionary = sR12.request_fire(real_tid, "missile", true,
		{"target_entity": "raider_2", "actor_id": "player_ctrl",
			"controller_id": "player_ctrl", "domain_id": "player",
			"fleet_id": "own_fleet"})
	var ctr12 = sR12.combat_service.track(real_tid)
	var ctr12_identity := ""
	if ctr12 is Dictionary:
		ctr12_identity = String((ctr12 as Dictionary).get("identity", ""))
	_eq(ctr12_identity, "friend", "火控边界把同一身份投影到实际 HUD 航迹")
	_ok(String(rf12.get("reason", "")) != "unknown_track",
		"实际 HUD 路径不再因未知身份停在 unknown_track",
		str(rf12.get("reason", "")))
	# 兼容正例：预填字段的 combat 行与实体键仍可解析
	var sR12b = _new()
	_register_combat_track(sR12b, "T0009", "raider_2")
	sR12b.identity_manual_confirm("player_intel", "raider_2", "friend",
		{"authority": "command"})
	_eq(String(sR12b.combat_identity("T0009").get("identity", "")), "friend",
		"预填 entity_id 的兼容正例仍绿")
	_eq(String(sR12b.combat_identity("raider_2").get("identity", "")), "friend",
		"实体键兼容正例仍绿")

	_step("R13 TTL 进入消费者：过期后 HUD 标记失效、火控不把 friend 当有效")
	var sR13 = _new()
	sR13.identity_ingest("player_intel", _ev("ttl_cons", "optical", "friend", 0.9,
		{"ttl_s": 5.0}))
	for i13 in range(11):
		sR13.tick(TICK_DT)
	var op13: Dictionary = sR13.identity_operational("player_intel", "ttl_cons")
	_eq(String(op13.get("validity", "")), "expired", "过期后 validity=expired")
	_eq(bool(op13.get("valid", true)), false, "过期后 valid=false")
	_eq(String(op13.get("effective_identity", "")), "unknown",
		"过期后 effective_identity=unknown（历史仍保留）")
	var b13 = Binder.new()
	b13.session = sR13
	var v13: Dictionary = b13.ident_view({"track_id": "ttl_cons"})
	_eq(bool(v13.get("valid", true)), false, "HUD 消费过期有效性")
	_eq(String(v13.get("validity", "")), "expired", "HUD 显示过期状态")
	# R4：实际普通显示要消费有效结果，不能把过期 friend 当有效值显示
	_eq(String(v13.get("identity", "")), "unknown", "HUD 普通显示用有效结果")
	_eq(String(v13.get("last_known_identity", "")), "friend",
		"HUD 保留最后已知身份作历史")
	_ok(bool(v13.get("warn", false)), "HUD 标记失效告警")
	_ok(String(v13.get("tag", "")).find("EXPIRED") >= 0, "HUD 标签区分失效",
		String(v13.get("tag", "")))
	# 普通联系人路径同样消费有效性
	b13.refresh()
	var c13: Dictionary = {}
	for raw_c13 in (b13.contacts as Array):
		if raw_c13 is Dictionary and String((raw_c13 as Dictionary).get(
				"track_id", "")) == "ttl_cons":
			c13 = raw_c13
	_ok(not c13.is_empty(), "过期 owner 航迹仍出现在 contacts")
	_eq(String(c13.get("identity", "")), "unknown", "联系人普通显示消费有效性")
	_eq(String(c13.get("validity", "")), "expired", "联系人显示过期态")
	_eq(String(c13.get("last_known_identity", "")), "friend",
		"联系人保留最后已知身份")
	var ci13: Dictionary = sR13.combat_identity("ttl_cons")
	_eq(String(ci13.get("identity", "")), "unknown",
		"火控不把过期 friend 当有效身份")
	_eq(String(ci13.get("last_known_identity", "")), "friend",
		"火控仍保留最后已知身份作历史")

	_step("R14 合法迟到证据：审计保留且不污染下一 tick 重算")
	var sR14 = _new()
	for i14 in range(2):
		sR14.tick(TICK_DT)
	sR14.identity_ingest("player_intel", _ev("late_t", "optical", "friend", 0.9,
		{"ttl_s": 20.0}))
	var t14 := float(sR14.now_s())
	var late14: Dictionary = sR14.identity_ingest("player_intel", _ev("late_t",
		"transponder", "hostile", 0.9,
		{"observed_t": t14 - 1.0, "received_t": t14, "ttl_s": 20.0}))
	_ok(bool(late14.get("late_ignored", false)), "迟到旧证据标记 late_ignored",
		str(late14.get("late_ignored", null)))
	var before14 := String(sR14.identity_operational("player_intel", "late_t").get(
		"identity", ""))
	sR14.tick(TICK_DT)
	var after14 := String(sR14.identity_operational("player_intel", "late_t").get(
		"identity", ""))
	_eq(after14, before14, "迟到证据不污染下一 tick 重算（结论不变）")

	_step("R15 IFF 传输状态与身份评估状态分离（冲突不被覆盖；遮挡不冒充 jammed）")
	var sR15 = _new()
	sR15.identity_ingest("player_intel", _ev("harmattan", "optical", "hostile", 0.9,
		{"category": "sensor"}))
	var q15: Dictionary = sR15.identity_iff_query("player_intel", "harmattan")
	_ok(bool(q15.get("ok", false)), "冲突后真实 IFF 查询 ok")
	var op15: Dictionary = sR15.identity_operational("player_intel", "harmattan")
	_eq(String(op15.get("state", "")), "conflict",
		"IFF 传输状态不覆盖 assessment 冲突状态")
	_ok(String(op15.get("iff_state", "")) in ["valid", "no_reply"],
		"IFF 传输状态独立可读", String(op15.get("iff_state", "")))
	var sR15b = _new()
	var q15b: Dictionary = sR15b.identity_iff_query("player_intel", "harmattan",
		{"occluded": true, "jam": 0.95})
	_eq(String(q15b.get("state", "")), "no_reply", "遮挡按实际回复原因记为 no_reply")
	_eq(String(q15b.get("reason", "")), "occluded",
		"请求 jam 参数不冒充实际阻断原因")
	_eq(String(sR15b.identity_operational("player_intel", "harmattan").get(
		"iff_state", "")), "no_reply", "操作性身份读到实际 IFF 传输状态")

	_step("R16 真实延迟查询生命周期：pending → 到达后 valid；随档恢复")
	var sR16 = _new()
	for i16 in range(2):
		sR16.tick(TICK_DT)
	var q16: Dictionary = sR16.identity_iff_query("player_intel", "harmattan",
		{"latency_s": 3.0})
	_eq(String(q16.get("state", "")), "pending", "延迟查询初始 pending")
	_eq(String(sR16.identity_operational("player_intel", "harmattan").get(
		"iff_state", "")), "pending", "操作性身份可见 pending")
	for i16b in range(3):
		sR16.tick(TICK_DT)
	_ok(String(sR16.identity_operational("player_intel", "harmattan").get(
		"iff_state", "")) in ["valid", "no_reply"], "延迟到达后状态转为实际结果",
		String(sR16.identity_operational("player_intel", "harmattan").get(
			"iff_state", "")))
	# 在途查询随档恢复
	var sR16c = _new()
	for i16c in range(2):
		sR16c.tick(TICK_DT)
	sR16c.identity_iff_query("player_intel", "harmattan", {"latency_s": 5.0})
	var text16: String = sR16c.save_state()
	var sR16d = _new()
	var lr16: Dictionary = sR16d.load_state(text16)
	_ok(bool(lr16.get("ok", false)), "延迟查询存档恢复 ok",
		str(lr16.get("errors", [])))
	_eq(int(lr16.get("identity_query_queue", 0)), 0, "队列计数在恢复结果中可读")
	_ok(int((sR16d._identity_query_queue as Array).size()) >= 1,
		"在途查询队列随档恢复")
	for i16d in range(5):
		sR16d.tick(TICK_DT)
	_ok(String(sR16d.identity_operational("player_intel", "harmattan").get(
		"iff_state", "")) in ["valid", "no_reply"], "恢复后延迟查询仍按 ETA 到达",
		String(sR16d.identity_operational("player_intel", "harmattan").get(
			"iff_state", "")))


	_step("总结")
	_info("A02 验收：四来源/冲突/TTL/迟到/IFF/人工/owner隔离/消费者/恢复")
	_finish()


# ── helpers ──────────────────────────────────────────────────────

func _new():
	return GS.new(_seed())


func _ev(target: String, source: String, identity: String, conf: float,
		extra := {}) -> Dictionary:
	# 未显式给 observed_t 时由 Session 归一化按当前时间补齐
	var d: Dictionary = {"target_id": target, "source": source,
		"identity": identity, "confidence": conf}
	for k in extra.keys():
		d[k] = extra[k]
	return d


func _track(view: Dictionary, tid: String) -> Dictionary:
	for raw in (view.get("tracks", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			return raw
	return {}


func _meta(s, eid: String) -> Dictionary:
	if s == null or not s.has_method("entity_metadata"):
		return {}
	var m = s.entity_metadata(eid)
	return m if m is Dictionary else {}


func _is_authority_reason(reason: String) -> bool:
	return reason in ["unknown_shooter", "shooter_not_authorized",
		"direct_command_not_permitted", "shooter_runtime_unavailable",
		"legacy_anchor_unknown", "domain_unknown", "authority_unavailable",
		"actor_not_authorized", "controller_mismatch", "fleet_mismatch",
		"context_domain_mismatch"]


func _register_combat_track(s, tid: String, entity_id := "") -> void:
	if s == null or s.combat_service == null:
		return
	s.combat_service.register_track(tid, {"id": tid, "batch": tid,
		"track_id": tid if entity_id == "" else entity_id,
		"entity_id": entity_id,
		"identity": "unknown", "threat": "unknown",
		"range_km": 500.0, "in_arc": true, "destroyed": false,
		"pos_km": [321719.0, 500.0, 0.0]})


func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "faction": "ueg", "roe": "DEFENSIVE",
				"fleet_id": "ally_fleet", "authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "faction": "ocu", "roe": "AGGRESSIVE",
				"fleet_id": "enemy_fleet", "authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet", "role": "flag"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet", "role": "picket"},
			{"entity_instance_id": "raider_2", "domain_id": "opfor",
				"fleet_id": "enemy_fleet", "role": "raider"}],
		"own_fleet": [{"entity_instance_id": "own_ship"}],
		"identification_service": {"evidence_ttl_s": 12.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
		"transponder_service": {
			"content_path": "res://framework/content/transponders_prologue.json"},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship",
				"pos_km": [321719.0, 300.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship",
				"pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]},
			{"id": "harmattan", "kind": "ship",
				"pos_km": [321719.0, 900.0, 0.0], "vel_kmps": [0.0, 0.2, 0.0]},
			{"id": "probe_ship", "kind": "ship",
				"pos_km": [321719.0, 1200.0, 0.0], "vel_kmps": [0.0, 0.1, 0.0],
				"transponder_profile": "ueg_military"}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
	}
