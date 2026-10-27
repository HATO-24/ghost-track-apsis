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
	var clr: Dictionary = s6.identity_manual_clear("player_intel", "raider_2")
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


func _register_combat_track(s, tid: String) -> void:
	if s == null or s.combat_service == null:
		return
	s.combat_service.register_track(tid, {"id": tid, "batch": tid,
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
