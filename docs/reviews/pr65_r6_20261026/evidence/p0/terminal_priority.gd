extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-B03P R6 返修探针：内容与真实 catalog 一致、终态规则自洽、权威/玩家视图分离。
#
# 新增拒绝面（审查方要求）：
#   * ship_class_id 必须真实存在于 canonical catalog（不接受 APSIS/HARMATTAN 自证）
#   * 编制不得超过 command_capacity，点数不得超过预算
#   * 零完成 + 时限必须判 defeat（不是 stalemate/victory）
#   * 目标必须给出可实现失能机制 + 依赖 + 替代口径
#   * 每条轨迹必须区分 authority 结果与玩家报告视图
#
# Output: `JC-B03P SCENARIO SPEC PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const SPEC := "C:/Users/ASUS/.codex/worktrees/jc-r6-validation/GHOST TRACK_APSIS/.test-results/r6-p0-audit/terminal_priority.json"
const FRIENDLY := "res://framework/content/ships_friendly.json"
const ENEMY := "res://framework/content/ships_enemy.json"

const MILITARY_ATTRS := ["organic_fire_control", "command_node"]
const TERMINALS := ["victory", "defeat", "withdrawal", "stalemate", "pending_report"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-B03P R6 SPEC PROBE · catalog-bound, rule-consistent, dual-view")
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(120.0).timeout
	if _finished:
		return
	print("[B03P] FAIL watchdog timeout")
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
			print("[B03P] FAILED: ", f)
		print("JC-B03P SCENARIO SPEC PROBE FAILED")
	else:
		print("JC-B03P SCENARIO SPEC PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[B03P] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[B03P] FAIL ", line)


func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		("actual=%s expected=%s" % [str(actual), str(expected)])
		+ (("  " + detail) if detail != "" else ""))


func _step(t: String) -> void:
	print("")
	print("[B03P] STEP ", t)


func _info(t: String) -> void:
	print("[B03P] INFO ", t)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. 提案本体与 catalog 绑定")
	var doc: Dictionary = _read_json(SPEC)
	_ok(not doc.is_empty(), "提案 fixture 可读", SPEC)
	if doc.is_empty():
		_finish()
		return
	_eq(String(doc.get("schema", "")), "v17.jc.scenario_spec.v2", "schema v2")
	_eq(int(doc.get("version", 0)), 2, "version = 2")
	var status := String(doc.get("status", ""))
	_ok(status.find("proposal") >= 0 and status.find("pending") >= 0,
		"状态是「提案待用户核对」", status)
	var cat: Dictionary = doc.get("catalog_binding", {}) if doc.get("catalog_binding") is Dictionary else {}
	_eq(String(cat.get("friendly_catalog", "")), FRIENDLY, "友军 catalog 路径")
	_eq(String(cat.get("enemy_catalog", "")), ENEMY, "敌方 catalog 路径")
	var friendly_ids: Dictionary = _class_ids(FRIENDLY)
	var enemy_ids: Dictionary = _class_ids(ENEMY)
	_ok(friendly_ids.size() >= 8, "友军 catalog 可读", str(friendly_ids.size()))
	_ok(enemy_ids.size() >= 5, "敌方 catalog 可读", str(enemy_ids.size()))
	var bind: Dictionary = cat.get("entity_bindings", {}) if cat.get("entity_bindings") is Dictionary else {}
	for named in bind.keys():
		_ok(friendly_ids.has(String(bind[named])),
			"命名舰 %s 绑定真实友军舰级" % String(named), String(bind[named]))

	_step("2. 舰池/编制：真实舰级 + 容量与预算实际生效")
	var pool: Dictionary = doc.get("fleet_pool", {}) if doc.get("fleet_pool") is Dictionary else {}
	var budget := int(pool.get("points_budget", 0))
	var cap := int(pool.get("command_capacity", 0))
	_ok(budget > 0, "点数预算为正", str(budget))
	_ok(cap >= 2, "指挥容量 >= 2", str(cap))
	var disp_of: Dictionary = {}
	for raw in (pool.get("ships", []) as Array):
		var sh: Dictionary = raw
		var cid := String(sh.get("ship_class_id", ""))
		_ok(friendly_ids.has(cid), "舰池舰级存在: " + cid)
		var disp := float(sh.get("displacement_t", 0.0))
		_ok(disp > 0.0, "舰池给出真实排水量: " + cid, str(disp))
		disp_of[cid] = disp
	var forms: Array = doc.get("formations", []) if doc.get("formations") is Array else []
	_eq(forms.size(), 2, "恰好两套编制")
	var roles: Dictionary = {}
	var over_budget: Array = []
	var over_cap: Array = []
	for raw_f in forms:
		var f: Dictionary = raw_f
		roles[String(f.get("role", ""))] = true
		var comp: Array = f.get("ships", []) if f.get("ships") is Array else []
		if comp.size() > cap:
			over_cap.append({"formation": String(f.get("formation_id", "")),
				"ships": comp.size(), "cap": cap})
		var sum := 0
		for sid in comp:
			if not disp_of.has(String(sid)):
				over_budget.append({"formation": String(f.get("formation_id", "")),
					"reason": "ship not in pool", "ship": String(sid)})
				continue
			sum += int(roundf(float(disp_of[String(sid)]) / 60.0))
		if sum > budget:
			over_budget.append({"formation": String(f.get("formation_id", "")),
				"points": sum, "budget": budget})
		_ok(comp.size() >= 2, "编制 %s 至少 2 舰" % String(f.get("formation_id", "")),
			str(comp.size()))
	_ok(over_cap.is_empty(), "编制不超指挥容量（容量实际生效）", str(over_cap))
	_ok(over_budget.is_empty(), "编制不超点数预算（预算实际生效）", str(over_budget.slice(0, 4)))
	_eq(roles.size(), 2, "两套编制战术角色不同", JSON.stringify(roles.keys()))

	_step("3. 友军/敌方：真实敌方舰级与军事属性")
	var ally: Dictionary = doc.get("ally_force", {})
	_eq(String(ally.get("domain_id", "")), "ally", "友军独立指挥域")
	for sid2 in (ally.get("ships", []) as Array):
		_ok(friendly_ids.has(String(sid2)), "友军舰级存在: " + String(sid2))
	var opfor: Dictionary = doc.get("opfor", {})
	var units: Array = opfor.get("units", []) if opfor.get("units") is Array else []
	_ok(units.size() >= 3, "敌方至少 3 个可引用单位", str(units.size()))
	var unit_ids: Dictionary = {}
	for raw_u in units:
		var u: Dictionary = raw_u
		var uid := String(u.get("entity_instance_id", ""))
		_ok(uid != "" and not unit_ids.has(uid), "敌方实例 ID 唯一: " + uid)
		unit_ids[uid] = true
		_ok(enemy_ids.has(String(u.get("ship_class_id", ""))),
			"敌方舰级存在: " + uid, String(u.get("ship_class_id", "")))
		_ok(String(u.get("military_attribute", "")) in MILITARY_ATTRS,
			"敌方单位是军事属性: " + uid)
		_eq(bool(u.get("protected", true)), false, "敌方目标非受保护民用: " + uid)

	_step("4. 目标：字段完整 + 可实现失能机制 + 依赖/替代")
	var objs: Array = doc.get("objectives", []) if doc.get("objectives") is Array else []
	_ok(objs.size() >= 3, "至少 3 个可审目标", str(objs.size()))
	var obj_ids: Dictionary = {}
	for raw_o in objs:
		var o: Dictionary = raw_o
		var oid := String(o.get("objective_id", ""))
		obj_ids[oid] = true
		for req in ["target_entity_instance_id", "target_military_attribute",
				"complete_condition", "fail_condition", "evidence_source",
				"player_visible_feedback", "terminal_state", "priority"]:
			_ok(o.has(req), "目标 %s 字段 %s" % [oid, req])
		_ok(unit_ids.has(String(o.get("target_entity_instance_id", ""))),
			"目标 %s 指向已声明敌方单位" % oid)
		_eq(bool(o.get("recoverable_in_mission", true)), false,
			"目标 %s 失能不可本场恢复" % oid)
		_ok(String(o.get("disable_mechanism", "")) != "",
			"目标 %s 给出可实现失能机制" % oid, String(o.get("disable_mechanism", "")))
		_ok(String(o.get("mechanism_dependency", "")) != "",
			"目标 %s 标注依赖" % oid, String(o.get("mechanism_dependency", "")))
		_ok(String(o.get("mechanism_alternative", "")) != "",
			"目标 %s 给出替代口径" % oid, String(o.get("mechanism_alternative", "")))

	_step("5. 保护目标：绑定实体 + 损失后果")
	var prot: Array = doc.get("protection_objectives", []) if doc.get("protection_objectives") is Array else []
	_ok(prot.size() >= 2, "保护目标 >= 2", str(prot.size()))
	var civ_ok := false
	for raw_p in prot:
		var p: Dictionary = raw_p
		_ok(String(p.get("bound_entity_instance_id", "")) != "",
			"保护目标 %s 绑定实体" % String(p.get("objective_id", "")))
		_ok(String(p.get("loss_consequence", "")) != "",
			"保护目标 %s 定义损失后果" % String(p.get("objective_id", "")))
		if String(p.get("kind", "")) == "protect_civilian_infrastructure":
			civ_ok = bool(p.get("player_must_not_attack", false)) == true
	_ok(civ_ok, "民用设施必须不可攻击（不得作为胜利条件）")

	_step("6. 终态规则：零完成→defeat、时限不产生胜利、同 tick 优先级")
	var tr: Dictionary = doc.get("terminal_rules", {}) if doc.get("terminal_rules") is Dictionary else {}
	_eq(String(tr.get("zero_completed_at_timeout_is", "")), "defeat",
		"零完成 + 时限 = defeat（不是 stalemate）")
	_eq(bool(tr.get("timeout_never_yields_victory", false)), true,
		"时限永不产生胜利")
	var prio: Array = tr.get("same_tick_priority", [])
	_ok(prio.size() >= 4, "声明同 tick 终态优先级", str(prio.size()))
	_eq(String(prio[0]) if prio.size() > 0 else "", "defeat", "优先级最高为 defeat")
	var vic: Dictionary = tr.get("victory", {}) if tr.get("victory") is Dictionary else {}
	var req: Array = vic.get("required_objectives", [])
	_eq(int(vic.get("min_completed", 0)), req.size(), "胜利需要全部必需目标完成")
	for rid in req:
		_ok(obj_ids.has(String(rid)), "胜利条件引用已定义目标: " + String(rid))
	var def: Dictionary = tr.get("defeat", {}) if tr.get("defeat") is Dictionary else {}
	_ok((def.get("any", []) as Array).size() >= 2, "失败条件有多条路径")
	_ok((def.get("any", []) as Array).has("zero_required_objectives_completed_at_timeout"),
		"失败条件包含零完成")

	_step("7. 贡献语义：玩家 vs 友军，AI 不得包办首胜")
	var contrib: Dictionary = doc.get("contribution_rules", {}) if doc.get("contribution_rules") is Dictionary else {}
	_ok(String(contrib.get("objective_credit", "")).find("玩家") >= 0,
		"目标记功区分玩家直控/授权")
	_ok(String(contrib.get("ai_cannot_win_alone", "")) != "",
		"声明 AI 不能单独取胜")
	_ok(String(contrib.get("player_no_action", "")).find("timeout") >= 0,
		"玩家无操作按 timeout 口径")

	_step("8. 轨迹：规则自洽 + authority/玩家视图分离")
	var traces: Array = doc.get("event_traces", []) if doc.get("event_traces") is Array else []
	_ok(traces.size() >= 10, "轨迹覆盖主要分支", str(traces.size()))
	var trace_ids: Dictionary = {}
	for raw_t in traces:
		var t2: Dictionary = raw_t
		var tid := String(t2.get("trace_id", ""))
		_ok(tid != "" and not trace_ids.has(tid), "轨迹 ID 唯一: " + tid)
		trace_ids[tid] = true
		var term := String(t2.get("expected_terminal", ""))
		_ok(term in TERMINALS, "轨迹 %s 终态合法" % tid, term)
		_ok(String(t2.get("expected_authority", "")) != "",
			"轨迹 %s 有权威结果" % tid, String(t2.get("expected_authority", "")))
		_ok(String(t2.get("expected_player_report", "")) != "",
			"轨迹 %s 有玩家报告视图" % tid, String(t2.get("expected_player_report", "")))
		_ok(String(t2.get("decision_id", "")) != "",
			"轨迹 %s 有裁决 ID" % tid, String(t2.get("decision_id", "")))
		var events: Array = t2.get("events", []) if t2.get("events") is Array else []
		var completed: Dictionary = {}
		var adjudications := 0
		var kinds: Array = []
		for raw_e in events:
			var e: Dictionary = raw_e
			var k := String(e.get("kind", ""))
			kinds.append(k)
			if k == "objective_disable":
				completed[String(e.get("objective_id", ""))] = true
			elif k == "target_still_engaging":
				completed.erase(String(e.get("objective_id", "")))
			elif k == "adjudicate":
				adjudications += 1
		var expected_by_rule := "pending_report"
		if adjudications > 0 and int(t2.get("terminal_events", 0)) > 0:
			if completed.size() >= req.size():
				expected_by_rule = "victory"
			elif completed.size() == 0:
				expected_by_rule = "defeat"
			else:
				expected_by_rule = "stalemate"
		if kinds.has("own_flag_disabled") or kinds.has("protected_target_destroyed"):
			expected_by_rule = "defeat"
		if kinds.has("withdraw_complete"):
			expected_by_rule = "withdrawal"
		if term == "pending_report":
			expected_by_rule = "pending_report"
		_eq(term, expected_by_rule, "轨迹 %s 与终态规则自洽" % tid)
		_ok(adjudications <= 2, "轨迹 %s 裁决事件不超过 2（幂等守卫）" % tid,
			str(adjudications))
	var pend := _find(traces, "TR-DISABLED-NOT-REPORTED")
	_eq(String(pend.get("expected_terminal", "")), "pending_report",
		"「已失能未报告」不算完成")
	_eq(String(pend.get("expected_player_report", "")), "unknown",
		"玩家报告视图仍是 unknown")
	_eq(String(pend.get("expected_authority", "")), "in_progress",
		"权威侧仍在进行")
	var zero := _find(traces, "TR-ZERO-COMPLETE-TIMEOUT")
	_eq(String(zero.get("expected_terminal", "")), "defeat", "零完成轨迹 = defeat")
	var civ := _find(traces, "TR-CIVILIAN-LOSS")
	_eq(String(civ.get("expected_terminal", "")), "defeat", "民用损失轨迹 = defeat")

	_step("10. 负例变体：未知舰级 / 超容量 / 胜利轨迹缺失能事件 必须被拒绝")
	var good_ids: Dictionary = friendly_ids
	# 变体 1：未知舰级（APSIS/HARMATTAN 不能自证合法）
	var v1: Dictionary = doc.duplicate(true)
	((v1.get("formations", []) as Array)[0] as Dictionary)["ships"] = ["APSIS", "HARMATTAN"]
	_ok(_variant_errors(v1, good_ids, enemy_ids, cap).size() > 0,
		"变体1 未知舰级被拒绝", str(_variant_errors(v1, good_ids, enemy_ids, cap).slice(0, 2)))
	# 变体 2：编制超指挥容量
	var v2: Dictionary = doc.duplicate(true)
	((v2.get("formations", []) as Array)[0] as Dictionary)["ships"] = \
		["OCUVF-PALLET-5C", "OCUVF-PALLET-5C", "OCUVF-PALLET-5C", "OCUVF-PALLET-5C"]
	_ok(_variant_errors(v2, good_ids, enemy_ids, 2).size() > 0,
		"变体2 超指挥容量被拒绝", str(_variant_errors(v2, good_ids, enemy_ids, 2).slice(0, 2)))
	# 变体 3：胜利轨迹删除全部失能事件（只剩 adjudicate）
	var v3: Dictionary = doc.duplicate(true)
	for raw_t3 in (v3.get("event_traces", []) as Array):
		if String((raw_t3 as Dictionary).get("trace_id", "")) == "TR-FULL-VICTORY":
			var kept: Array = []
			for raw_e3 in ((raw_t3 as Dictionary).get("events", []) as Array):
				if String((raw_e3 as Dictionary).get("kind", "")) != "objective_disable":
					kept.append(raw_e3)
			(raw_t3 as Dictionary)["events"] = kept
	_ok(_variant_errors(v3, good_ids, enemy_ids, cap).size() > 0,
		"变体3 胜利轨迹缺失能事件被拒绝",
		str(_variant_errors(v3, good_ids, enemy_ids, cap).slice(0, 2)))
	_step("11. 待用户决定项与依赖")
	var pend2: Array = doc.get("user_decisions_pending", [])
	_ok(pend2.size() >= 5, "列出待用户核对项", str(pend2.size()))
	_ok((doc.get("b3_dependencies", []) as Array).size() >= 2, "列出 B3 依赖")
	_ok((doc.get("not_implemented", []) as Array).size() >= 1, "明确未实现范围")
	_info("PENDING USER DECISIONS: " + JSON.stringify(pend2).substr(0, 300))
	_info("本探针只验证内容与 catalog/规则一致性；真实 AI/战斗/裁决/试玩 NOT RUN")
	_finish()


func _find(traces: Array, tid: String) -> Dictionary:
	for raw in traces:
		if raw is Dictionary and String((raw as Dictionary).get("trace_id", "")) == tid:
			return raw
	return {}


func _class_ids(path: String) -> Dictionary:
	var out: Dictionary = {}
	var doc: Dictionary = _read_json(path)
	for raw in (doc.get("classes", []) as Array):
		if raw is Dictionary:
			out[String((raw as Dictionary).get("class_id", ""))] = true
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
## 内容变体校验（供负例断言）：未知舰级 / 超容量 / 轨迹与规则不一致 → 返回错误列表。
func _variant_errors(doc: Dictionary, friendly_ids: Dictionary,
		enemy_ids: Dictionary, cap: int) -> Array:
	var errs: Array = []
	var pool: Dictionary = doc.get("fleet_pool", {}) if doc.get("fleet_pool") is Dictionary else {}
	var pool_ids: Dictionary = {}
	for raw in (pool.get("ships", []) as Array):
		pool_ids[String((raw as Dictionary).get("ship_class_id", ""))] = true
	for raw_f in (doc.get("formations", []) as Array):
		var comp: Array = (raw_f as Dictionary).get("ships", []) as Array
		if comp.size() > cap:
			errs.append("formation over capacity: %d > %d" % [comp.size(), cap])
		for sid in comp:
			if not friendly_ids.has(String(sid)) or not pool_ids.has(String(sid)):
				errs.append("unknown ship class: " + String(sid))
	var rul: Dictionary = doc.get("terminal_rules", {}) if doc.get("terminal_rules") is Dictionary else {}
	var req: Array = (rul.get("victory", {}) as Dictionary).get("required_objectives", []) \
		if rul.get("victory") is Dictionary else []
	for raw_t in (doc.get("event_traces", []) as Array):
		var t: Dictionary = raw_t
		var completed: Dictionary = {}
		var adjudicated := false
		for raw_e in (t.get("events", []) as Array):
			var e: Dictionary = raw_e
			var k := String(e.get("kind", ""))
			if k == "objective_disable":
				completed[String(e.get("objective_id", ""))] = true
			elif k == "target_still_engaging":
				completed.erase(String(e.get("objective_id", "")))
			elif k == "adjudicate":
				adjudicated = true
		if String(t.get("expected_terminal", "")) == "victory" and adjudicated \
				and completed.size() < req.size():
			errs.append("trace %s claims victory with %d/%d objectives" % [
				String(t.get("trace_id", "")), completed.size(), req.size()])
	return errs
