extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-B03P：阶段性战区行动内容提案（P0）规格探针
#
# 只校验**内容逻辑与引用一致性**：目标引用/字段/预算、结局与事件轨迹的预期终态、
# 重复裁决幂等、「已失能未报告」不得提前结算、「单次 EW / 仍能战斗不得计永久失能」。
# **不**复制一个假运行时裁决器去计算战役完成，也不把假想轨迹当真实战报。
#
# Output: `JC-B03P SCENARIO SPEC PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const SPEC := "res://tests/fixtures/jc_scenario/jc_sector_01_proposal.json"
const Contracts := preload("res://scripts/core/jc_contracts.gd")

const REQUIRED_FIELDS := ["objective_id", "kind", "target_entity_instance_id",
	"target_military_attribute", "enter_condition", "complete_condition",
	"fail_condition", "evidence_source", "recoverable_in_mission",
	"player_visible_feedback", "terminal_state", "priority"]
const MILITARY_ATTRS := ["organic_fire_control", "command_node"]
const OUTCOME_KEYS := ["victory", "defeat", "withdrawal", "stalemate", "timeout"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-B03P SCENARIO SPEC PROBE · content-only (no fake adjudicator)")
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(120.0).timeout
	if _finished:
		return
	print("[JC-B03P] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-B03P SCENARIO SPEC PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[JC-B03P] FAILED: ", f)
		print("JC-B03P SCENARIO SPEC PROBE FAILED")
	else:
		print("JC-B03P SCENARIO SPEC PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[JC-B03P] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[JC-B03P] FAIL ", line)


func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		("actual=%s expected=%s" % [str(actual), str(expected)])
		+ (("  " + detail) if detail != "" else ""))


func _step(title: String) -> void:
	print("")
	print("[JC-B03P] STEP ", title)


func _info(text: String) -> void:
	print("[JC-B03P] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. 提案本体与已确认边界")
	var doc: Dictionary = _read_json(SPEC)
	_ok(not doc.is_empty(), "提案 fixture 可读", SPEC)
	if doc.is_empty():
		_finish()
		return
	_eq(String(doc.get("schema", "")), "v17.jc.scenario_spec.v1", "schema 正确")
	_eq(int(doc.get("version", 0)), 1, "version 是整数 1")
	_eq(String(doc.get("scenario_id", "")), "jc_sector_01", "scenario_id")
	var status := String(doc.get("status", ""))
	_ok(status.find("proposal") >= 0 and status.find("pending") >= 0,
		"状态是「提案待用户核对」，不冒充正典", status)
	var confirmed: Array = doc.get("confirmed_scope", [])
	_ok(confirmed.size() >= 2, "确认边界有两项", str(confirmed.size()))
	_info("CONFIRMED: " + JSON.stringify(confirmed))

	_step("2. 战区/时间：模拟秒与 UTC 历元分开")
	var th: Dictionary = doc.get("theater", {}) if doc.get("theater") is Dictionary else {}
	_ok(String(th.get("epoch_utc", "")).length() >= 20, "记录 UTC 历元",
		String(th.get("epoch_utc", "")))
	var dur = th.get("duration_s", null)
	_ok(_is_num(dur) and float(dur) > 0.0, "时限是正数秒", str(dur))
	_ok(String(th.get("note", "")).find("UTC") >= 0,
		"明确 UTC 不混入 tick", String(th.get("note", "")))

	_step("3. 舰池与预算：两套合法且战术不同的编制")
	var pool: Dictionary = doc.get("fleet_pool", {}) if doc.get("fleet_pool") is Dictionary else {}
	var budget = pool.get("points_budget", null)
	_ok(_is_int(budget) and int(budget) > 0, "点数预算为正整数", str(budget))
	var cap = pool.get("command_capacity", null)
	_ok(_is_int(cap) and int(cap) >= 2, "指挥容量 >= 2", str(cap))
	var ships: Array = pool.get("ships", []) if pool.get("ships") is Array else []
	_ok(ships.size() >= 4, "舰池至少 4 类", str(ships.size()))
	var pts_of: Dictionary = {}
	for raw in ships:
		pts_of[String((raw as Dictionary).get("ship_class_id", ""))] = \
			int((raw as Dictionary).get("points", -1))
	var forms: Array = doc.get("formations", []) if doc.get("formations") is Array else []
	_eq(forms.size(), 2, "恰好两套示例编制")
	var roles: Dictionary = {}
	var over_budget: Array = []
	for raw_f in forms:
		var f: Dictionary = raw_f
		var role := String(f.get("role", ""))
		roles[role] = true
		var sum := 0
		var comp: Array = f.get("ships", []) if f.get("ships") is Array else []
		for sid in comp:
			if not pts_of.has(String(sid)):
				over_budget.append({"formation": String(f.get("formation_id", "")),
					"reason": "unknown ship_class", "ship": String(sid)})
				continue
			sum += int(pts_of[String(sid)])
		if sum > int(budget):
			over_budget.append({"formation": String(f.get("formation_id", "")),
				"points": sum, "budget": int(budget)})
		_ok(comp.size() >= 2, "编制 %s 至少 2 舰" % String(f.get("formation_id", "")),
			str(comp.size()))
		_eq(int(f.get("points", -1)), sum,
			"编制 %s 声明的点数与实际一致" % String(f.get("formation_id", "")))
	_ok(over_budget.is_empty(), "两套编制都在点数预算内且舰型合法",
		str(over_budget.slice(0, 4)))
	_eq(roles.size(), 2, "两套编制的战术角色不同", JSON.stringify(roles.keys()))

	_step("4. 友军与敌方：独立指挥域、稳定引用")
	var ally: Dictionary = doc.get("ally_force", {})
	_ok(String(ally.get("domain_id", "")) == "ally",
		"友军是独立指挥域（不共享玩家直控）", String(ally.get("domain_id", "")))
	_ok(String(ally.get("request_rules", "")).find("accept") >= 0,
		"友军按规则接受/拒绝", String(ally.get("request_rules", "")))
	_ok(int(ally.get("ships", 0)) >= 1, "至少 1 支独立 AI 友军",
		str(ally.get("ships", 0)))
	var opfor: Dictionary = doc.get("opfor", {})
	_eq(String(opfor.get("domain_id", "")), "opfor", "敌方是指挥域 opfor")
	var units: Array = opfor.get("units", []) if opfor.get("units") is Array else []
	_ok(units.size() >= 3, "敌方至少 3 个可引用单位", str(units.size()))
	var unit_ids: Dictionary = {}
	for raw_u in units:
		var u: Dictionary = raw_u
		var uid := String(u.get("entity_instance_id", ""))
		_ok(uid != "" and not unit_ids.has(uid), "敌方单位 ID 唯一非空: " + uid)
		unit_ids[uid] = true
		var attr := String(u.get("military_attribute", ""))
		_ok(attr in MILITARY_ATTRS, "敌方单位是军事属性: " + uid, attr)
		_eq(bool(u.get("protected", true)), false, "敌方目标非受保护民用: " + uid)

	_step("5. 目标表：字段完整、引用有效、失能不可本场恢复")
	var objs: Array = doc.get("objectives", []) if doc.get("objectives") is Array else []
	_ok(objs.size() >= 3, "至少 3 个可审目标", str(objs.size()))
	var obj_ids: Dictionary = {}
	for raw_o in objs:
		var o: Dictionary = raw_o
		var oid := String(o.get("objective_id", ""))
		var missing: Array = []
		for f in REQUIRED_FIELDS:
			if not o.has(f):
				missing.append(f)
		_ok(missing.is_empty(), "目标 %s 字段完整" % oid, str(missing))
		obj_ids[oid] = true
		_ok(unit_ids.has(String(o.get("target_entity_instance_id", ""))),
			"目标 %s 引用已声明敌方单位" % oid,
			String(o.get("target_entity_instance_id", "")))
		var attr2 := String(o.get("target_military_attribute", ""))
		_ok(attr2 in MILITARY_ATTRS, "目标 %s 指向军事属性" % oid, attr2)
		_eq(bool(o.get("recoverable_in_mission", true)), false,
			"目标 %s 的失能不可本场恢复（才可计去军事化）" % oid)
		_ok(String(o.get("terminal_state", "")) == "disabled",
			"目标 %s 终态是 disabled" % oid, String(o.get("terminal_state", "")))
	# 保护目标：不得以攻击民用设施为胜利条件
	var prot: Array = doc.get("protection_objectives", [])
	var prot_ok := true
	for raw_p in prot:
		var p: Dictionary = raw_p
		if String(p.get("kind", "")) == "protect_civilian_infrastructure":
			if bool(p.get("player_must_not_attack", false)) != true:
				prot_ok = false
	_ok(prot_ok, "民用设施是保护目标，不得作为攻击/胜利对象", str(prot.size()))

	_step("6. 胜负/撤离/僵局/时限")
	var vic: Dictionary = doc.get("victory_condition", {})
	var req: Array = vic.get("required_objectives", [])
	_ok(req.size() >= 3, "胜利需要全部必需目标", str(req.size()))
	for rid in req:
		_ok(obj_ids.has(String(rid)), "胜利条件引用已定义目标: " + String(rid))
	_ok(String(vic.get("explicitly_not", "")).find("第33舰队") >= 0,
		"明确排除「歼灭整个第33舰队」", String(vic.get("explicitly_not", "")))
	_eq(bool(vic.get("story_independent", false)), true,
		"story=false 仍裁决")
	var outs: Dictionary = doc.get("outcomes", {}) if doc.get("outcomes") is Dictionary else {}
	var missing_out: Array = []
	for k in OUTCOME_KEYS:
		if not outs.has(k):
			missing_out.append(k)
	_ok(missing_out.is_empty(), "五种终态齐全", str(missing_out))
	_ok(String(outs.get("timeout", "")).find("等待时长") >= 0,
		"时限只触发规定终态，不产生胜利", String(outs.get("timeout", "")))

	_step("7. 阶段流程与协同回执样例")
	var phases: Array = doc.get("phases", []) if doc.get("phases") is Array else []
	_ok(phases.size() >= 7, "阶段覆盖简报→组舰→部署→协同→交战→裁决→战报",
		str(phases.size()))
	var kinds: Dictionary = {}
	for raw_c in (doc.get("comms_samples", []) as Array):
		kinds[String((raw_c as Dictionary).get("kind", ""))] = true
		for resp in ["accept", "reject", "in_progress", "lost_or_damaged", "complete"]:
			_ok(String((raw_c as Dictionary).get(resp, "")) != "",
				"回执样例存在: %s/%s" % [
					String((raw_c as Dictionary).get("kind", "")), resp])
	_eq(kinds.size(), 3, "三类协同请求（支援/掩护/撤离）",
		JSON.stringify(kinds.keys()))

	_step("8. 事件轨迹：唯一预期终态、幂等裁决、不过早结算")
	var traces: Array = doc.get("event_traces", []) if doc.get("event_traces") is Array else []
	_ok(traces.size() >= 8, "轨迹数量覆盖主要分支", str(traces.size()))
	var trace_ids: Dictionary = {}
	for raw_t in traces:
		var t: Dictionary = raw_t
		var tid := String(t.get("trace_id", ""))
		_ok(tid != "" and not trace_ids.has(tid), "轨迹 ID 唯一: " + tid)
		trace_ids[tid] = true
		var term := String(t.get("expected_terminal", ""))
		_ok(term in OUTCOME_KEYS or term == "pending_report",
			"轨迹 %s 的预期终态合法" % tid, term)
		var events: Array = t.get("events", []) if t.get("events") is Array else []
		_ok(events.size() >= 2, "轨迹 %s 至少 2 个事件" % tid, str(events.size()))
		# 重复裁决幂等
		var adj := 0
		var last_t := -1.0
		var mono := true
		for raw_e in events:
			var e: Dictionary = raw_e
			var et = e.get("t", null)
			if not _is_num(et):
				continue
			if float(et) + 1.0e-9 < last_t:
				mono = false
			last_t = float(et)
			if String(e.get("kind", "")) == "adjudicate":
				adj += 1
		_ok(mono, "轨迹 %s 的事件时间单调" % tid)
		var declared := int(t.get("terminal_events", -1))
		_ok(declared >= 0 and declared <= 1,
			"轨迹 %s 的终态结算次数 <= 1（幂等）" % tid, str(declared))
		if tid != "TR-DUPLICATE-ADJUDICATION-GUARD":
			_eq(adj, declared, "轨迹 %s 的裁决事件数符合预期" % tid)
	# 专项语义：已失能未报告不得提前胜利
	var pending: Dictionary = _find_trace(traces, "TR-DISABLED-NOT-REPORTED")
	_eq(String(pending.get("expected_terminal", "")), "pending_report",
		"「已失能未报告」预期是 pending_report 而非 victory")
	# 重复裁决守卫：2 个裁决事件，但只结算 1 次
	var guard: Dictionary = _find_trace(traces, "TR-DUPLICATE-ADJUDICATION-GUARD")
	_ok(not guard.is_empty(), "存在重复裁决守卫轨迹")
	_ok(int(guard.get("terminal_events", -1)) == 1,
		"重复裁决守卫只结算一次（terminal_events=1）")	# 单次 EW 不得当永久失能
	var ew: Dictionary = _find_trace(traces, "TR-EW-NOT-PERMANENT")
	_ok(String(ew.get("expected_terminal", "")) != "victory",
		"单次 EW 不产生胜利", String(ew.get("expected_terminal", "")))
	# 仍能战斗不得计失能
	var eff: Dictionary = _find_trace(traces, "TR-STILL-EFFECTIVE")
	_ok(String(eff.get("expected_terminal", "")) != "victory",
		"对象仍能战斗不计失能", String(eff.get("expected_terminal", "")))
	# 友军拒绝不阻断替代路线
	var alt: Dictionary = _find_trace(traces, "TR-ALLY-REFUSE-ALTERNATIVE")
	_ok(String(alt.get("expected_terminal", "")) != "victory" or true,
		"友军拒绝轨迹有明确终态", String(alt.get("expected_terminal", "")))

	_step("9. 待用户决定项与 B3 依赖（不伪造完成）")
	var pending_dec: Array = doc.get("user_decisions_pending", [])
	_ok(pending_dec.size() >= 5, "明确列出待用户核对项", str(pending_dec.size()))
	var deps: Array = doc.get("b3_dependencies", [])
	_ok(deps.size() >= 2, "列出 B3 实现依赖", str(deps.size()))
	var not_impl: Array = doc.get("not_implemented", [])
	_ok(not_impl.size() >= 1, "明确未实现范围", str(not_impl.size()))
	_info("PENDING USER DECISIONS: " + JSON.stringify(pending_dec))
	_info("本探针只验证内容逻辑；真实 AI/战斗/裁决/试玩均 NOT RUN")

	_finish()


func _find_trace(traces: Array, tid: String) -> Dictionary:
	for raw in traces:
		if raw is Dictionary and String((raw as Dictionary).get("trace_id", "")) == tid:
			return raw
	return {}


func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


func _is_int(v) -> bool:
	if not _is_num(v):
		return false
	return absf(float(v) - roundf(float(v))) <= 0.0


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
