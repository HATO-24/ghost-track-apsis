extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-B03P R11 规格迁移探针（P0-r11-1 / v17.jc.scenario_spec.v4）
#
# 只验证内容契约/引用/规则自洽：11 独立舰=8 支援 + 3 作战、APSIS 计入 8、
# 四种 HEMATITE:GANTRY 组合、owned/deployed/task_groups 分离、APSIS 后方保护、
# M0/M1 时限、R9 的真实弹道/双攻击链/truth-report/唯一评价、旧 v3 拒绝。
# 不实现运行态裁决器，不把纸面轨迹当真实战报。
#
# Output: `JC-B03P SCENARIO SPEC PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const SPEC := "res://tests/fixtures/jc_scenario/jc_sector_01_proposal.json"
const FRIENDLY := "res://framework/content/ships_friendly.json"
const ENEMY := "res://framework/content/ships_enemy.json"
const SCHEMA := "v17.jc.scenario_spec.v4"
const SUPPORT_COUNT := 8
const COMBAT_COUNT := 3
const TOTAL_INDEPENDENT := 11
const TERMINALS := ["victory", "defeat", "withdrawal", "stalemate", "pending_report", "ongoing"]
const EVAL_ORDER := ["主导", "有效协同", "有限参与", "未参与"]
const PRIORITY := ["defeat", "victory", "withdrawal", "stalemate"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-B03P R11 SPEC PROBE · v4 11-ship/free-composition migration")
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
	_step("1. v4 fixture 本体 / catalog / 实例声明")
	var doc: Dictionary = _read_json(SPEC)
	_ok(not doc.is_empty(), "v4 fixture 可读", SPEC)
	if doc.is_empty():
		_finish()
		return
	_eq(String(doc.get("schema", "")), SCHEMA, "schema v4")
	_eq(int(doc.get("version", 0)), 4, "version = 4")
	var status := String(doc.get("status", ""))
	_ok(status.find("proposal") >= 0 and status.find("pending") >= 0,
		"状态是提案待用户核对", status)
	var fid: Dictionary = _class_ids(FRIENDLY)
	var eid: Dictionary = _class_ids(ENEMY)
	_ok(fid.size() == 8, "友军基础舰级 8", str(fid.size()))
	_ok(eid.size() == 24, "敌方基础舰级 24", str(eid.size()))
	var cat: Dictionary = doc.get("catalog_binding", {}) if doc.get("catalog_binding") is Dictionary else {}
	_eq(String(cat.get("friendly_catalog", "")), FRIENDLY, "catalog 路径 friendly")
	_eq(String(cat.get("enemy_catalog", "")), ENEMY, "catalog 路径 enemy")
	_ok((cat.get("entity_bindings", {}) as Dictionary).is_empty(),
		"不覆盖既有命名实体映射")
	var ib: Array = cat.get("instance_bindings", []) if cat.get("instance_bindings") is Array else []
	_ok(ib.size() >= TOTAL_INDEPENDENT, "instance_bindings 覆盖 11 独立舰", str(ib.size()))
	var seen_ib: Dictionary = {}
	for raw_ib in ib:
		var row_ib: Dictionary = raw_ib
		var iid := String(row_ib.get("entity_instance_id", ""))
		_ok(iid != "" and not seen_ib.has(iid), "instance ID 唯一: " + iid)
		seen_ib[iid] = true
		_ok(fid.has(String(row_ib.get("ship_class_id", ""))),
			"实例 %s 绑定真实友军 class" % iid, String(row_ib.get("ship_class_id", "")))

	_step("2. 11 独立舰 = 8 支援 + 3 作战，APSIS 不占作战位")
	var fo: Dictionary = doc.get("fleet_ownership", {}) if doc.get("fleet_ownership") is Dictionary else {}
	_eq(int(fo.get("independent_ship_count", 0)), TOTAL_INDEPENDENT, "独立舰=11")
	_eq(int(fo.get("support_ship_count", 0)), SUPPORT_COUNT, "支援舰=8")
	_eq(int(fo.get("combat_ship_count", 0)), COMBAT_COUNT, "作战舰=3")
	_eq(String(fo.get("apsis_instance_id", "")), "apsis", "APSIS 实例")
	_eq(bool(fo.get("apsis_counted_in_support", false)), true, "APSIS 计入支援")
	_eq(bool(fo.get("apsis_counted_in_combat", false)), false, "APSIS 不占作战位")
	_eq(bool(fo.get("shuttles_are_independent", true)), false, "穿梭机不算独立舰")
	var support_rows: Array = fo.get("support_roster", []) if fo.get("support_roster") is Array else []
	_eq(support_rows.size(), SUPPORT_COUNT, "support_roster 8")
	var class_counts: Dictionary = {}
	var support_ids: Dictionary = {}
	for raw_s in support_rows:
		var s: Dictionary = raw_s
		var sid := String(s.get("instance_id", ""))
		_ok(sid != "" and not support_ids.has(sid), "支援实例唯一: " + sid)
		support_ids[sid] = true
		_ok(fid.has(String(s.get("ship_class_id", ""))), "支援 class 存在: " + sid,
			String(s.get("ship_class_id", "")))
		var cid_s := String(s.get("ship_class_id", ""))
		class_counts[cid_s] = int(class_counts.get(cid_s, 0)) + 1
		_ok(String(s.get("role_group", "")) == "support", "支援角色组: " + sid)
	_eq(int(class_counts.get("OCUVF-APOGEE", 0)), 1, "APSIS/APOGEE ×1")
	_eq(int(class_counts.get("OCUVF-PALLET-5C", 0)), 2, "PALLET ×2")
	_eq(int(class_counts.get("OCUVF-SAFEHARBOR-1", 0)), 2, "SAFEHARBOR ×2")
	_eq(int(class_counts.get("OCUVF-MOONPORT-4", 0)), 2, "MOONPORT ×2")
	_eq(int(class_counts.get("OCUVF-WINCH-2", 0)), 1, "WINCH ×1")
	var owned_ids: Array = fo.get("owned_instance_ids", []) if fo.get("owned_instance_ids") is Array else []
	_eq(owned_ids.size(), TOTAL_INDEPENDENT, "owned 实例=11")
	var seen_owned: Dictionary = {}
	for oid in owned_ids:
		_ok(not seen_owned.has(String(oid)), "owned 实例唯一: " + String(oid))
		seen_owned[String(oid)] = true
	var attached: Array = fo.get("attached_shuttles", []) if fo.get("attached_shuttles") is Array else []
	for raw_a in attached:
		var a: Dictionary = raw_a
		_eq(String(a.get("ship_class_id", "")), "OCUVF-ARIA-1", "穿梭机 class ARIA-1")
		_eq(bool(a.get("independent", true)), false, "穿梭机独立=false")
		_eq(String(a.get("carried_by", "")), "apsis", "穿梭机随 APSIS")

	_step("3. 四种 HEMATITE:GANTRY 合法组合；当前只拥有 3 作战舰")
	var cs: Dictionary = doc.get("combat_selection", {}) if doc.get("combat_selection") is Dictionary else {}
	_eq(int(cs.get("slot_count", 0)), COMBAT_COUNT, "作战 slot=3")
	var allowed: Array = cs.get("allowed_classes", []) if cs.get("allowed_classes") is Array else []
	_ok("OCUVF-HEMATITE-6C" in allowed and "OCUVF-GANTRY-3M" in allowed,
		"作战 class 只允许 HEMATITE/GANTRY")
	var comps: Array = cs.get("four_legal_compositions", []) if cs.get("four_legal_compositions") is Array else []
	_eq(comps.size(), 4, "四种作战组合")
	var comp_ids: Dictionary = {}
	var ratios: Dictionary = {}
	for raw_c in comps:
		var comp: Dictionary = raw_c
		var cid_c := String(comp.get("composition_id", ""))
		_ok(cid_c != "" and not comp_ids.has(cid_c), "组合 ID 唯一: " + cid_c)
		comp_ids[cid_c] = true
		var ships: Array = comp.get("ships", []) if comp.get("ships") is Array else []
		_eq(ships.size(), COMBAT_COUNT, "组合 %s 3 舰" % cid_c)
		var h := 0; var g := 0
		var row_ids: Dictionary = {}
		var res_refs: Dictionary = {}
		for raw_cs in ships:
			var row_cs: Dictionary = raw_cs
			var iid_c := String(row_cs.get("instance_id", ""))
			_ok(iid_c != "" and not row_ids.has(iid_c), "组合实例唯一 %s/%s" % [cid_c, iid_c])
			row_ids[iid_c] = true
			var rref := String(row_cs.get("resource_ref", ""))
			_ok(rref != "" and not res_refs.has(rref), "独立资源引用 %s/%s" % [cid_c, iid_c])
			res_refs[rref] = true
			var cls := String(row_cs.get("ship_class_id", ""))
			_ok(cls in allowed, "组合 class 合法: " + cls)
			if cls == "OCUVF-HEMATITE-6C": h += 1
			elif cls == "OCUVF-GANTRY-3M": g += 1
		var ratio: Dictionary = comp.get("ratio", {}) if comp.get("ratio") is Dictionary else {}
		_eq(int(ratio.get("HEMATITE", -1)), h, "组合 %s 炮数" % cid_c)
		_eq(int(ratio.get("GANTRY", -1)), g, "组合 %s 导數" % cid_c)
		ratios["%d:%d" % [h, g]] = true
	for r in ["3:0", "2:1", "1:2", "0:3"]:
		_ok(ratios.has(r), "存在比例 " + r)
	var selected_cid := String(cs.get("selected_composition_id", ""))
	_ok(comp_ids.has(selected_cid), "选中组合存在: " + selected_cid)
	# 当前 owned 的 3 艘作战舰必须恰为选中组合，不应包含其它候选
	var selected_ships: Array = []
	for raw_c2 in comps:
		if String((raw_c2 as Dictionary).get("composition_id", "")) == selected_cid:
			selected_ships = (raw_c2 as Dictionary).get("ships", []) as Array
	var owned_combat: Array = owned_ids.slice(SUPPORT_COUNT, owned_ids.size())
	var selected_ids: Array = []
	for raw_s2 in selected_ships:
		selected_ids.append(String((raw_s2 as Dictionary).get("instance_id", "")))
	_eq(owned_combat, selected_ids, "owned 只含选中组合的 3 作战实例")
	_ok(String(cs.get("not_owned_note", "")).find("未选") >= 0,
		"声明未选组合不计 owned")

	_step("4. owned/deployed/reserve/task_groups 分离")
	var dep: Dictionary = doc.get("deployment", {}) if doc.get("deployment") is Dictionary else {}
	_eq(String(dep.get("selected_composition_id", "")), selected_cid, "deployment 选中组合一致")
	var deployed: Array = dep.get("deployed_instance_ids", []) if dep.get("deployed_instance_ids") is Array else []
	var reserve: Array = dep.get("reserve_instance_ids", []) if dep.get("reserve_instance_ids") is Array else []
	var seen_dep: Dictionary = {}
	for did in deployed:
		_ok(seen_owned.has(String(did)), "deployed 属于 owned: " + String(did))
		_ok(not seen_dep.has(String(did)), "deployed 唯一: " + String(did))
		seen_dep[String(did)] = true
	for rid in reserve:
		_ok(seen_owned.has(String(rid)), "reserve 属于 owned: " + String(rid))
		_ok(not seen_dep.has(String(rid)), "reserve 不重复部署: " + String(rid))
	_eq(deployed.size() + reserve.size(), TOTAL_INDEPENDENT, "deployed+reserve=11")
	var tg: Array = dep.get("task_groups", []) if dep.get("task_groups") is Array else []
	_ok(tg.size() >= 2, "任务组 >=2", str(tg.size()))
	var group_ids: Dictionary = {}
	var assigned: Dictionary = {}
	for raw_g in tg:
		var g2: Dictionary = raw_g
		var gid := String(g2.get("group_id", ""))
		_ok(gid != "" and not group_ids.has(gid), "任务组 ID 唯一: " + gid)
		group_ids[gid] = true
		for mid in (g2.get("instance_ids", []) as Array):
			_ok(seen_dep.has(String(mid)), "任务组成员属于 deployed: " + String(mid))
			_ok(not assigned.has(String(mid)), "任务组成员不重复: " + String(mid))
			assigned[String(mid)] = true
	_eq(assigned.size(), deployed.size(), "每个 deployed 恰属一个任务组")
	_ok("apsis" in (tg[0] as Dictionary).get("instance_ids", []) or
		"apsis" in (tg[tg.size() - 1] as Dictionary).get("instance_ids", []),
		"APSIS 在任务组内")

	_step("5. APSIS 后方保护 / 不占作战位")
	var flag: Dictionary = doc.get("own_flag", {}) if doc.get("own_flag") is Dictionary else {}
	_eq(String(flag.get("entity_instance_id", "")), "apsis", "旗舰实例=apsis")
	_eq(String(flag.get("ship_class_id", "")), "OCUVF-APOGEE", "旗舰 class APOGEE")
	_eq(String(flag.get("deployment_rule", "")), "in_theater_rear_support", "APSIS 战区后方")
	_eq(bool(flag.get("in_combat_slot", true)), false, "APSIS 不占作战 slot")
	_eq(String(flag.get("is_protected_objective", "")), "PROT-2", "APSIS 绑定 PROT-2")
	_eq(String(flag.get("loss_consequence", "")), "defeat", "APSIS 损失→defeat")
	var prot: Array = doc.get("protection_objectives", []) if doc.get("protection_objectives") is Array else []
	var prot_ids: Dictionary = {}
	for raw_p in prot:
		var p: Dictionary = raw_p
		var pid := String(p.get("objective_id", ""))
		prot_ids[pid] = true
		_ok(String(p.get("bound_entity_instance_id", "")) != "", "保护目标绑定实体: " + pid)
		_ok(String(p.get("loss_consequence", "")) != "", "保护目标损失后果: " + pid)
		if pid == "PROT-2":
			_eq(String(p.get("bound_entity_instance_id", "")), "apsis", "PROT-2 绑定 APSIS")
	_eq(int(prot_ids.size()), 2, "两个保护目标")
	_ok(str(prot_ids.get("PROT-1", false)) != "", "PROT-1 存在")
	_ok(prot_ids.has("PROT-1"), "民用保护存在")

	_step("6. 敌方 / 目标：OBJ-B 双攻击链、永久失能、C 无身份免疫")
	var opfor: Dictionary = doc.get("opfor", {}) if doc.get("opfor") is Dictionary else {}
	var units: Array = opfor.get("units", []) if opfor.get("units") is Array else []
	_eq(units.size(), 3, "敌方 3 单位")
	var unit_ids: Dictionary = {}
	for raw_u in units:
		var u: Dictionary = raw_u
		var uid := String(u.get("entity_instance_id", ""))
		_ok(uid != "" and not unit_ids.has(uid), "敌方实例唯一: " + uid)
		unit_ids[uid] = true
		_ok(eid.has(String(u.get("ship_class_id", ""))), "敌方 class 存在: " + uid)
		_eq(bool(u.get("protected", true)), false, "敌方非受保护民用: " + uid)
	var objs: Array = doc.get("objectives", []) if doc.get("objectives") is Array else []
	_eq(objs.size(), 3, "三个必需目标")
	var obj_ids: Dictionary = {}
	var obj_by_id: Dictionary = {}
	for raw_o in objs:
		var o: Dictionary = raw_o
		var oid := String(o.get("objective_id", ""))
		obj_ids[oid] = true
		obj_by_id[oid] = o
		_ok(unit_ids.has(String(o.get("target_entity_instance_id", ""))),
			"目标 %s 指向已声明敌方" % oid)
		_eq(bool(o.get("recoverable_in_mission", true)), false,
			"目标 %s 不可恢复" % oid)
		_ok(String(o.get("complete_condition", "")) != "", "目标 %s 完成条件" % oid)
		_ok(String(o.get("disable_mechanism", "")) != "", "目标 %s 机制" % oid)
		_ok(String(o.get("mechanism_dependency", "")) != "", "目标 %s 依赖" % oid)
		_ok(String(o.get("mechanism_alternative", "")) != "", "目标 %s 替代" % oid)
		_ok((o.get("required_attack_chains", []) as Array).size() >= 1,
			"目标 %s 攻击链" % oid)
	_ok(obj_ids.has("OBJ-A") and obj_ids.has("OBJ-B") and obj_ids.has("OBJ-C"),
		"OBJ-A/B/C 齐全")
	var objb: Dictionary = obj_by_id.get("OBJ-B", {}) as Dictionary
	var chains: Array = objb.get("required_attack_chains", []) if objb.get("required_attack_chains") is Array else []
	_ok("missile_vls_fire_control" in chains and "railgun_fire_control" in chains,
		"OBJ-B 同时要求导弹 VLS + railgun 火控链")
	_eq(String(objb.get("complete_condition", "")), "all_required_attack_chains_permanently_disabled",
		"OBJ-B 两条链都永久失能才完成")
	_eq(bool((obj_by_id.get("OBJ-C", {}) as Dictionary).get("no_identity_immunity", false)),
		true, "OBJ-C 无身份免疫")

	_step("7. 终态/时间：M0 无自动结算、truth/report 分离、同 tick/幂等")
	var tr: Dictionary = doc.get("terminal_rules", {}) if doc.get("terminal_rules") is Dictionary else {}
	_eq(bool(tr.get("truth_report_split", false)), true, "truth/report 分离")
	_eq(bool(tr.get("terminal_idempotent", false)), true, "终态幂等")
	_eq(bool(tr.get("no_contribution_exception", false)), true, "无贡献例外")
	var vic: Dictionary = tr.get("victory", {}) if tr.get("victory") is Dictionary else {}
	_eq((vic.get("required_objectives", []) as Array).size(), 3, "胜利需三目标")
	_eq(bool(vic.get("required_all", false)), true, "胜利需全部目标")
	_eq(bool(vic.get("permanent_only", false)), true, "胜利只认永久失能")
	_eq(bool(vic.get("contribution_does_not_change_result", false)), true,
		"贡献不改变真实结果")
	var prio: Array = tr.get("same_tick_priority", []) if tr.get("same_tick_priority") is Array else []
	_eq(prio, PRIORITY, "同 tick 优先级")
	var modes: Dictionary = tr.get("time_limit_modes", {}) if tr.get("time_limit_modes") is Dictionary else {}
	_ok(modes.get("M0") is Dictionary and modes.get("M1") is Dictionary,
		"M0/M1 时限模式声明")
	_eq(bool((modes.get("M0", {}) as Dictionary).get("auto_terminal", true)), false,
		"M0 窗口不自动结算")
	_eq(int((modes.get("M0", {}) as Dictionary).get("window_s", 0)), 3600,
		"M0 观测窗口 3600")
	_eq(bool((modes.get("M1", {}) as Dictionary).get("explicit_enable_required", false)),
		true, "M1 仅显式启用")
	_eq(bool((modes.get("M2", {}) as Dictionary).get("adopted", true)), false,
		"未定义软限不采用")
	var theater: Dictionary = doc.get("theater", {}) if doc.get("theater") is Dictionary else {}
	var tl: Dictionary = theater.get("time_limit", {}) if theater.get("time_limit") is Dictionary else {}
	_eq(String(tl.get("mode", "")), "M0", "theater 默认 M0")
	_eq(bool(tl.get("window_is_auto_terminal", true)), false, "t3600 非自动终态")
	_eq(bool(tl.get("hard_limit_enabled", true)), false, "默认无硬限")

	_step("8. 贡献评价：有序、唯一、友军自主不改真实结果")
	var cr: Dictionary = doc.get("contribution_rules", {}) if doc.get("contribution_rules") is Dictionary else {}
	_eq(cr.get("command_evaluation_order", []), EVAL_ORDER, "评价顺序")
	_eq(bool(cr.get("command_evaluation_unique", false)), true, "评价唯一")
	_ok(String(cr.get("ally_autonomous", "")).find("victory") >= 0 and
		String(cr.get("ally_autonomous", "")).find("未参与") >= 0,
		"友军自主：真实胜利+评价未参与")
	_ok(String(cr.get("player_no_action", "")).find("M0") >= 0,
		"无操作在 M0 不自动结算")
	_eq(bool(cr.get("no_identity_immunity", false)), true, "无身份免疫")
	_ok(String(cr.get("objective_credit", "")).find("authorized") >= 0 or
		String(cr.get("objective_credit", "")).find("授权") >= 0,
		"玩家/授权贡献分开")

	_step("9. 友军有限武装 + 真实弹道 + 回执语义")
	var ally: Dictionary = doc.get("ally_force", {}) if doc.get("ally_force") is Dictionary else {}
	_eq(String(ally.get("domain_id", "")), "ally", "友军独立域")
	_eq(String(ally.get("capability", "")), "limited_armed_independent_escort",
		"友军有限武装独立任务")
	for raw_as in (ally.get("ships", []) as Array):
		var ac := String(raw_as)
		_ok(fid.has(ac), "友军 class 存在: " + ac)
		var wl: Array = _weapons_of(FRIENDLY, ac)
		if ac == "OCUVF-HEMATITE-6C":
			_ok(wl.size() > 0, "友军 HEMATITE 有真实武器")
		else:
			_ok(wl.is_empty(), "友军 %s 目录无武器" % ac)
	var sup: Dictionary = ally.get("suppress", {}) if ally.get("suppress") is Dictionary else {}
	_eq(String(sup.get("weapon", "")), "railgun", "SUPPRESS 使用 railgun")
	_eq(bool(sup.get("real_ballistics", false)), true, "SUPPRESS 真实弹道")
	_eq(int(sup.get("fixed_debuff_s", -1)), 0, "无固定 120s 减益")
	_eq(bool(sup.get("identity_immunity", true)), false, "无射手身份免杀")
	_eq(bool(sup.get("permanent_disable_not_guaranteed", false)), true,
		"不保证永久失能")
	var comms: Array = doc.get("comms_samples", []) if doc.get("comms_samples") is Array else []
	_ok(comms.size() >= 2, "回执样例 >=2", str(comms.size()))
	for raw_c in comms:
		var c: Dictionary = raw_c
		_ok(c.has("status") and c.has("delivery") and c.has("target_completion"),
			"回执区分投递/执行/目标完成")
		_ok(bool(c.get("no_truth_leak", true)), "回执不泄露未知真值")

	_step("10. 事件轨迹：真值/报告分离、M0/M1 条件、幂等、反泄漏")
	var traces: Array = doc.get("event_traces", []) if doc.get("event_traces") is Array else []
	_ok(traces.size() >= 12, "轨迹覆盖主要分支", str(traces.size()))
	var trace_ids: Dictionary = {}
	for raw_t in traces:
		var t: Dictionary = raw_t
		var tid := String(t.get("trace_id", ""))
		_ok(tid != "" and not trace_ids.has(tid), "轨迹 ID 唯一: " + tid)
		trace_ids[tid] = true
		var errs: Array = _trace_errors(doc, t)
		_ok(errs.is_empty(), "轨迹 %s 自洽" % tid, str(errs.slice(0, 3)))
		_ok(String(t.get("decision_id", "")) != "", "轨迹 %s 有裁决 ID" % tid)
		var term := String(t.get("expected_terminal", ""))
		_ok(term in TERMINALS, "轨迹 %s 终态合法" % tid, term)
		_ok(String(t.get("expected_authority", "")) != "", "轨迹 %s 有权威结果" % tid)
		_ok(String(t.get("expected_player_report", "")) != "", "轨迹 %s 有玩家报告" % tid)
		_ok(String(t.get("player_contribution", "")) != "", "轨迹 %s 有玩家贡献" % tid)
		_ok(String(t.get("command_evaluation", "")) in EVAL_ORDER,
			"轨迹 %s 评价合法" % tid, String(t.get("command_evaluation", "")))
		_ok(int(t.get("terminal_events", -1)) >= 0 and int(t.get("terminal_events", -1)) <= 1,
			"轨迹 %s 终态事件<=1" % tid, str(t.get("terminal_events", -1)))
		if bool(t.get("no_truth_leak", false)):
			_ok(String(t.get("expected_player_report", "")).to_lower() == "unknown" or
				String(t.get("expected_terminal", "")) == "pending_report",
				"轨迹 %s 报告未回不泄露真值" % tid)
		if String(t.get("time_mode", "")) == "M0":
			_eq(bool(t.get("hard_limit_enabled", false)), false,
				"轨迹 %s M0 不启用硬限" % tid)
		if String(t.get("time_mode", "")) == "M1":
			_eq(bool(t.get("hard_limit_enabled", false)), true,
				"轨迹 %s M1 显式硬限" % tid)
	var required := ["TR-FULL-VICTORY", "TR-ALL-DISABLED-NO-REPORT",
		"TR-DEFEAT", "TR-WITHDRAW", "TR-M1-STALEMATE", "TR-M1-ZERO-TIMEOUT",
		"TR-M0-WINDOW-ONGOING", "TR-EW-NOT-PERMANENT", "TR-OBJ-B-ONE-CHAIN",
		"TR-ALLY-AUTONOMOUS-WIN", "TR-REPORT-LEAK-GUARD",
		"TR-DUPLICATE-ADJUDICATION-GUARD", "TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW"]
	for need in required:
		_ok(trace_ids.has(need), "必需轨迹存在: " + need)
	var auto := _find(traces, "TR-ALLY-AUTONOMOUS-WIN")
	_eq(String(auto.get("expected_terminal", "")), "victory", "友军自主真实结果 victory")
	_eq(String(auto.get("command_evaluation", "")), "未参与", "友军自主评价未参与")
	var m0 := _find(traces, "TR-M0-WINDOW-ONGOING")
	_eq(String(m0.get("expected_terminal", "")), "ongoing", "M0 t3600 ongoing")
	var one := _find(traces, "TR-OBJ-B-ONE-CHAIN")
	_ok(String(one.get("expected_terminal", "")) != "victory",
		"OBJ-B 单链失能不得 victory")
	var leak := _find(traces, "TR-REPORT-LEAK-GUARD")
	_eq(String(leak.get("expected_player_report", "")), "unknown",
		"报告未回玩家视图 unknown")

	_step("11. 旧 v3 拒绝 / v4 当前策略")
	var osp: Dictionary = doc.get("old_schema_policy", {}) if doc.get("old_schema_policy") is Dictionary else {}
	_eq(String(osp.get("v17.jc.scenario_spec.v4", "")), "current", "v4 当前")
	_ok(String(osp.get("v17.jc.scenario_spec.v3", "")).find("rejected") >= 0,
		"v3 明确拒绝/需迁移")
	var legacy: Dictionary = doc.duplicate(true)
	legacy["schema"] = "v17.jc.scenario_spec.v3"
	legacy["version"] = 3
	_ok(_full_errors(legacy, fid, eid).size() > 0, "旧 v3 schema 被拒绝",
		str(_full_errors(legacy, fid, eid).slice(0, 2)))

	_step("12. 负例变体：数量/绑定/时间/OBJ-B/真值泄漏/幂等")
	var good_ids: Dictionary = fid
	# 4 艘作战舰
	var v4c: Dictionary = doc.duplicate(true)
	var fo4: Dictionary = v4c.get("fleet_ownership", {})
	fo4["combat_ship_count"] = 4
	fo4["owned_instance_ids"] = (fo4.get("owned_instance_ids", []) as Array) + ["C21-EXTRA"]
	_ok(_full_errors(v4c, good_ids, eid).size() > 0, "变体 4 艘作战被拒绝",
		str(_full_errors(v4c, good_ids, eid).slice(0, 2)))
	# 多于 11 / 缺必需位
	var v12: Dictionary = doc.duplicate(true)
	var fo12: Dictionary = v12.get("fleet_ownership", {})
	fo12["owned_instance_ids"] = (fo12.get("owned_instance_ids", []) as Array) + ["extra-support"]
	_ok(_full_errors(v12, good_ids, eid).size() > 0, "变体 12 艘被拒绝",
		str(_full_errors(v12, good_ids, eid).slice(0, 2)))
	var vmiss: Dictionary = doc.duplicate(true)
	var fom: Dictionary = vmiss.get("fleet_ownership", {})
	fom["owned_instance_ids"] = (fom.get("owned_instance_ids", []) as Array).slice(0, 10)
	_ok(_full_errors(vmiss, good_ids, eid).size() > 0, "变体缺必需位被拒绝",
		str(_full_errors(vmiss, good_ids, eid).slice(0, 2)))
	# 错误舰级
	var vclass: Dictionary = doc.duplicate(true)
	((vclass.get("combat_selection", {}) as Dictionary).get("four_legal_compositions", [])[0] as Dictionary)["ships"][0]["ship_class_id"] = "OCUVF-PALLET-5C"
	_ok(_full_errors(vclass, good_ids, eid).size() > 0, "变体错误作战舰级被拒绝",
		str(_full_errors(vclass, good_ids, eid).slice(0, 2)))
	# 重复实例
	var vdup: Dictionary = doc.duplicate(true)
	((vdup.get("fleet_ownership", {}) as Dictionary).get("owned_instance_ids", []) as Array)[1] = "apsis"
	_ok(_full_errors(vdup, good_ids, eid).size() > 0, "变体重复实例被拒绝",
		str(_full_errors(vdup, good_ids, eid).slice(0, 2)))
	# APSIS 算进 3 作战
	var vapsis: Dictionary = doc.duplicate(true)
	var vapsis_owned: Array = (vapsis.get("fleet_ownership", {}) as Dictionary).get(
		"owned_instance_ids", []) as Array
	vapsis_owned[8] = "apsis"
	_ok(_full_errors(vapsis, good_ids, eid).size() > 0, "变体 APSIS 占作战位被拒绝",
		str(_full_errors(vapsis, good_ids, eid).slice(0, 2)))
	# 错误保护绑定（PROT-2 绑到哨舰）
	var vbind: Dictionary = doc.duplicate(true)
	for raw_p2 in (vbind.get("protection_objectives", []) as Array):
		if String((raw_p2 as Dictionary).get("objective_id", "")) == "PROT-2":
			(raw_p2 as Dictionary)["bound_entity_instance_id"] = "picket-1"
	_ok(_full_errors(vbind, good_ids, eid).size() > 0, "变体 PROT-2 错绑实例被拒绝",
		str(_full_errors(vbind, good_ids, eid).slice(0, 2)))
	# M0 自动终态
	var vm0: Dictionary = doc.duplicate(true)
	((vm0.get("terminal_rules", {}) as Dictionary).get("time_limit_modes", {})["M0"] as Dictionary)["auto_terminal"] = true
	_ok(_full_errors(vm0, good_ids, eid).size() > 0, "变体 M0 自动结算被拒绝",
		str(_full_errors(vm0, good_ids, eid).slice(0, 2)))
	# OBJ-B 单链完成
	var vobjb: Dictionary = doc.duplicate(true)
	((vobjb.get("objectives", []) as Array)[1] as Dictionary)["required_attack_chains"] = ["railgun_fire_control"]
	_ok(_full_errors(vobjb, good_ids, eid).size() > 0, "变体 OBJ-B 单链完成被拒绝",
		str(_full_errors(vobjb, good_ids, eid).slice(0, 2)))
	# OBJ-B 轨迹只有一链却 victory
	var vtr: Dictionary = doc.duplicate(true)
	for raw_t2 in (vtr.get("event_traces", []) as Array):
		if String((raw_t2 as Dictionary).get("trace_id", "")) == "TR-OBJ-B-ONE-CHAIN":
			(raw_t2 as Dictionary)["expected_terminal"] = "victory"
	_ok(_full_errors(vtr, good_ids, eid).size() > 0, "变体单链却 victory 被拒绝",
		str(_full_errors(vtr, good_ids, eid).slice(0, 2)))
	# 无真实失能却 victory
	var vnovic: Dictionary = doc.duplicate(true)
	for raw_t3 in (vnovic.get("event_traces", []) as Array):
		if String((raw_t3 as Dictionary).get("trace_id", "")) == "TR-FULL-VICTORY":
			var kept: Array = []
			for raw_e in ((raw_t3 as Dictionary).get("events", []) as Array):
				if String((raw_e as Dictionary).get("kind", "")) != "objective_disable":
					kept.append(raw_e)
			(raw_t3 as Dictionary)["events"] = kept
	_ok(_full_errors(vnovic, good_ids, eid).size() > 0, "变体无真实失能却 victory 被拒绝",
		str(_full_errors(vnovic, good_ids, eid).slice(0, 2)))
	# 报告未回却泄漏真值
	var vleak: Dictionary = doc.duplicate(true)
	for raw_t4 in (vleak.get("event_traces", []) as Array):
		if String((raw_t4 as Dictionary).get("trace_id", "")) == "TR-REPORT-LEAK-GUARD":
			(raw_t4 as Dictionary)["expected_player_report"] = "victory"
			(raw_t4 as Dictionary)["no_truth_leak"] = false
	_ok(_full_errors(vleak, good_ids, eid).size() > 0, "变体报告未回泄漏真值被拒绝",
		str(_full_errors(vleak, good_ids, eid).slice(0, 2)))
	# 同 tick 优先级冲突
	var vsame: Dictionary = doc.duplicate(true)
	for raw_t5 in (vsame.get("event_traces", []) as Array):
		if String((raw_t5 as Dictionary).get("trace_id", "")) == "TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW":
			(raw_t5 as Dictionary)["expected_terminal"] = "withdrawal"
	_ok(_full_errors(vsame, good_ids, eid).size() > 0, "变体同 tick 优先级冲突被拒绝",
		str(_full_errors(vsame, good_ids, eid).slice(0, 2)))
	# 旧幂等：重复裁决只能一次
	var vdupadj: Dictionary = doc.duplicate(true)
	for raw_t6 in (vdupadj.get("event_traces", []) as Array):
		if String((raw_t6 as Dictionary).get("trace_id", "")) == "TR-FULL-VICTORY":
			(raw_t6 as Dictionary)["terminal_events"] = 2
	_ok(_full_errors(vdupadj, good_ids, eid).size() > 0, "变体重复裁决被拒绝",
		str(_full_errors(vdupadj, good_ids, eid).slice(0, 2)))
	# 全部四种作战组合作为正例
	for raw_c3 in (doc.get("combat_selection", {}).get("four_legal_compositions", []) as Array):
		var cid3 := String((raw_c3 as Dictionary).get("composition_id", ""))
		var vcomp: Dictionary = _with_composition(doc, cid3)
		_ok(_full_errors(vcomp, good_ids, eid).is_empty(),
			"四组合作战规格正例: " + cid3,
			str(_full_errors(vcomp, good_ids, eid).slice(0, 2)))

	_step("13. 待核对项与未实现边界")
	var pend: Array = doc.get("user_decisions_pending", []) if doc.get("user_decisions_pending") is Array else []
	_ok(pend.size() >= 3, "列出待核对项", str(pend.size()))
	_ok((doc.get("b3_dependencies", []) as Array).size() >= 2, "列出 B3 依赖")
	_ok((doc.get("not_implemented", []) as Array).size() >= 2, "明确未实现范围")
	_info("本探针只验证内容与 catalog/规则一致性；真实 B1b/B2/B3、战斗、AI、试玩 NOT RUN")
	_finish()


# ── full validator ──────────────────────────────────────────────

func _full_errors(doc: Dictionary, fid: Dictionary, eid: Dictionary) -> Array:
	var errs: Array = []
	if String(doc.get("schema", "")) != SCHEMA: errs.append("schema_v3_or_unknown")
	if int(doc.get("version", 0)) != 4: errs.append("version_not_4")
	var fo: Dictionary = doc.get("fleet_ownership", {}) if doc.get("fleet_ownership") is Dictionary else {}
	if int(fo.get("independent_ship_count", 0)) != TOTAL_INDEPENDENT:
		errs.append("independent_count")
	if int(fo.get("support_ship_count", 0)) != SUPPORT_COUNT: errs.append("support_count")
	if int(fo.get("combat_ship_count", 0)) != COMBAT_COUNT: errs.append("combat_count")
	if String(fo.get("apsis_instance_id", "")) != "apsis": errs.append("apsis_id")
	if bool(fo.get("apsis_counted_in_support", false)) != true: errs.append("apsis_support")
	if bool(fo.get("apsis_counted_in_combat", true)) != false: errs.append("apsis_combat")
	if bool(fo.get("shuttles_are_independent", true)) != false: errs.append("shuttle_independent")
	var support_rows: Array = fo.get("support_roster", []) if fo.get("support_roster") is Array else []
	var counts: Dictionary = {}
	var support_ids: Dictionary = {}
	for raw_s in support_rows:
		var s: Dictionary = raw_s
		var sid := String(s.get("instance_id", ""))
		if sid == "" or support_ids.has(sid): errs.append("support_dup")
		support_ids[sid] = true
		var cid_s := String(s.get("ship_class_id", ""))
		if not fid.has(cid_s): errs.append("support_class_unknown:" + cid_s)
		counts[cid_s] = int(counts.get(cid_s, 0)) + 1
	if int(counts.get("OCUVF-APOGEE", 0)) != 1: errs.append("apogee_count")
	if int(counts.get("OCUVF-PALLET-5C", 0)) != 2: errs.append("pallet_count")
	if int(counts.get("OCUVF-SAFEHARBOR-1", 0)) != 2: errs.append("relay_count")
	if int(counts.get("OCUVF-MOONPORT-4", 0)) != 2: errs.append("tanker_count")
	if int(counts.get("OCUVF-WINCH-2", 0)) != 1: errs.append("winch_count")
	var owned: Array = fo.get("owned_instance_ids", []) if fo.get("owned_instance_ids") is Array else []
	if owned.size() != TOTAL_INDEPENDENT: errs.append("owned_count")
	var owned_seen: Dictionary = {}
	for oid in owned:
		if owned_seen.has(String(oid)): errs.append("owned_dup:" + String(oid))
		owned_seen[String(oid)] = true
	# compositions
	var cs: Dictionary = doc.get("combat_selection", {}) if doc.get("combat_selection") is Dictionary else {}
	var comps: Array = cs.get("four_legal_compositions", []) if cs.get("four_legal_compositions") is Array else []
	if comps.size() != 4: errs.append("composition_count")
	var comp_ids: Dictionary = {}
	var selected_cid := String(cs.get("selected_composition_id", ""))
	var selected_rows: Array = []
	var ratios: Dictionary = {}
	for raw_c in comps:
		var comp: Dictionary = raw_c
		var cid := String(comp.get("composition_id", ""))
		if cid == "" or comp_ids.has(cid): errs.append("composition_id")
		comp_ids[cid] = true
		var ships: Array = comp.get("ships", []) if comp.get("ships") is Array else []
		if ships.size() != COMBAT_COUNT: errs.append("composition_size:" + cid)
		var h := 0; var g := 0
		var seen_i: Dictionary = {}
		var seen_r: Dictionary = {}
		for raw_s2 in ships:
			var r2: Dictionary = raw_s2
			var iid2 := String(r2.get("instance_id", ""))
			if iid2 == "" or seen_i.has(iid2): errs.append("combat_dup:" + iid2)
			seen_i[iid2] = true
			if owned_seen.has(iid2) and cid != selected_cid: errs.append("unselected_combat_owned:" + iid2)
			var rref := String(r2.get("resource_ref", ""))
			if rref == "" or seen_r.has(rref): errs.append("resource_dup:" + rref)
			seen_r[rref] = true
			var cls := String(r2.get("ship_class_id", ""))
			if cls == "OCUVF-HEMATITE-6C": h += 1
			elif cls == "OCUVF-GANTRY-3M": g += 1
			else: errs.append("combat_class:" + cls)
		var ratio: Dictionary = comp.get("ratio", {}) if comp.get("ratio") is Dictionary else {}
		if int(ratio.get("HEMATITE", -1)) != h or int(ratio.get("GANTRY", -1)) != g:
			errs.append("ratio:" + cid)
		ratios["%d:%d" % [h, g]] = true
	for need_r in ["3:0", "2:1", "1:2", "0:3"]:
		if not ratios.has(need_r): errs.append("ratio_missing:" + need_r)
	if selected_cid == "" or not comp_ids.has(selected_cid): errs.append("selected_missing")
	else:
		for raw_c2 in comps:
			if String((raw_c2 as Dictionary).get("composition_id", "")) == selected_cid:
				selected_rows = (raw_c2 as Dictionary).get("ships", []) as Array
	var selected_ids: Array = []
	for raw_s3 in selected_rows:
		selected_ids.append(String((raw_s3 as Dictionary).get("instance_id", "")))
	var owned_combat: Array = owned.slice(SUPPORT_COUNT, owned.size())
	if owned_combat != selected_ids: errs.append("owned_combat_not_selected")
	# APSIS not in combat
	for x in owned_combat:
		if String(x) == "apsis": errs.append("apsis_in_combat")
	# deployment
	var dep: Dictionary = doc.get("deployment", {}) if doc.get("deployment") is Dictionary else {}
	if String(dep.get("selected_composition_id", "")) != selected_cid: errs.append("deployment_composition")
	var deployed: Array = dep.get("deployed_instance_ids", []) if dep.get("deployed_instance_ids") is Array else []
	var reserve: Array = dep.get("reserve_instance_ids", []) if dep.get("reserve_instance_ids") is Array else []
	var dep_seen: Dictionary = {}
	for did in deployed:
		if not owned_seen.has(String(did)): errs.append("deployed_unknown:" + String(did))
		if dep_seen.has(String(did)): errs.append("deployed_dup:" + String(did))
		dep_seen[String(did)] = true
	for rid in reserve:
		if not owned_seen.has(String(rid)): errs.append("reserve_unknown:" + String(rid))
		if dep_seen.has(String(rid)): errs.append("deploy_reserve_overlap:" + String(rid))
	if deployed.size() + reserve.size() != TOTAL_INDEPENDENT: errs.append("deploy_cover")
	var tg: Array = dep.get("task_groups", []) if dep.get("task_groups") is Array else []
	if tg.size() < 2: errs.append("task_group_count")
	var gids: Dictionary = {}
	var assigned: Dictionary = {}
	for raw_g in tg:
		var g2: Dictionary = raw_g
		var gid := String(g2.get("group_id", ""))
		if gid == "" or gids.has(gid): errs.append("group_id:" + gid)
		gids[gid] = true
		for mid in (g2.get("instance_ids", []) as Array):
			if not dep_seen.has(String(mid)): errs.append("group_unknown:" + String(mid))
			if assigned.has(String(mid)): errs.append("group_dup:" + String(mid))
			assigned[String(mid)] = true
	if assigned.size() != deployed.size(): errs.append("group_partition")
	# flag/protection
	var flag: Dictionary = doc.get("own_flag", {}) if doc.get("own_flag") is Dictionary else {}
	if String(flag.get("entity_instance_id", "")) != "apsis": errs.append("flag_id")
	if String(flag.get("ship_class_id", "")) != "OCUVF-APOGEE": errs.append("flag_class")
	if String(flag.get("deployment_rule", "")) != "in_theater_rear_support": errs.append("flag_rear")
	if bool(flag.get("in_combat_slot", true)): errs.append("flag_combat")
	if String(flag.get("is_protected_objective", "")) != "PROT-2": errs.append("flag_protect")
	if String(flag.get("loss_consequence", "")) != "defeat": errs.append("flag_loss")
	var prot: Array = doc.get("protection_objectives", []) if doc.get("protection_objectives") is Array else []
	var prot_ids: Dictionary = {}
	for raw_p in prot:
		var p: Dictionary = raw_p
		var pid := String(p.get("objective_id", ""))
		if pid == "" or prot_ids.has(pid): errs.append("prot_id")
		prot_ids[pid] = true
		if pid == "PROT-2" and String(p.get("bound_entity_instance_id", "")) != "apsis":
			errs.append("prot2_binding")
	if not prot_ids.has("PROT-1") or not prot_ids.has("PROT-2"): errs.append("prot_missing")
	# enemies/objectives
	var opfor: Dictionary = doc.get("opfor", {}) if doc.get("opfor") is Dictionary else {}
	var units: Array = opfor.get("units", []) if opfor.get("units") is Array else []
	var uids: Dictionary = {}
	for raw_u in units:
		var u: Dictionary = raw_u
		var uid := String(u.get("entity_instance_id", ""))
		if uid == "" or uids.has(uid): errs.append("enemy_id")
		uids[uid] = true
		if not eid.has(String(u.get("ship_class_id", ""))): errs.append("enemy_class")
		if bool(u.get("protected", true)): errs.append("enemy_protected")
	var objs: Array = doc.get("objectives", []) if doc.get("objectives") is Array else []
	if objs.size() != 3: errs.append("objective_count")
	var obj_ids: Dictionary = {}
	var obj_by: Dictionary = {}
	for raw_o in objs:
		var o: Dictionary = raw_o
		var oid := String(o.get("objective_id", ""))
		if oid == "" or obj_ids.has(oid): errs.append("objective_id")
		obj_ids[oid] = true
		obj_by[oid] = o
		if not uids.has(String(o.get("target_entity_instance_id", ""))): errs.append("objective_target:" + oid)
		if bool(o.get("recoverable_in_mission", true)): errs.append("objective_recoverable:" + oid)
		for field in ["complete_condition", "disable_mechanism", "mechanism_dependency",
				"mechanism_alternative"]:
			if String(o.get(field, "")) == "": errs.append("objective_field:%s:%s" % [oid, field])
	if not (obj_ids.has("OBJ-A") and obj_ids.has("OBJ-B") and obj_ids.has("OBJ-C")):
		errs.append("objective_missing")
	var objb: Dictionary = obj_by.get("OBJ-B", {}) as Dictionary
	var chains: Array = objb.get("required_attack_chains", []) if objb.get("required_attack_chains") is Array else []
	if not ("missile_vls_fire_control" in chains) or not ("railgun_fire_control" in chains):
		errs.append("objb_chains")
	if String(objb.get("complete_condition", "")) != "all_required_attack_chains_permanently_disabled":
		errs.append("objb_condition")
	if bool((obj_by.get("OBJ-C", {}) as Dictionary).get("no_identity_immunity", false)) != true:
		errs.append("objc_immunity")
	# terminal/time/contribution
	var tr: Dictionary = doc.get("terminal_rules", {}) if doc.get("terminal_rules") is Dictionary else {}
	if bool(tr.get("truth_report_split", false)) != true: errs.append("truth_split")
	if bool(tr.get("terminal_idempotent", false)) != true: errs.append("idempotent")
	if bool(tr.get("no_contribution_exception", false)) != true: errs.append("contribution_exception")
	var vic: Dictionary = tr.get("victory", {}) if tr.get("victory") is Dictionary else {}
	if (vic.get("required_objectives", []) as Array).size() != 3: errs.append("victory_targets")
	if bool(vic.get("required_all", false)) != true: errs.append("victory_all")
	if bool(vic.get("permanent_only", false)) != true: errs.append("victory_permanent")
	if bool(vic.get("contribution_does_not_change_result", false)) != true:
		errs.append("victory_contribution")
	if tr.get("same_tick_priority", []) != PRIORITY: errs.append("priority")
	var modes: Dictionary = tr.get("time_limit_modes", {}) if tr.get("time_limit_modes") is Dictionary else {}
	if bool((modes.get("M0", {}) as Dictionary).get("auto_terminal", true)) != false:
		errs.append("m0_auto")
	if int((modes.get("M0", {}) as Dictionary).get("window_s", 0)) != 3600:
		errs.append("m0_window")
	if bool((modes.get("M1", {}) as Dictionary).get("explicit_enable_required", false)) != true:
		errs.append("m1_explicit")
	if bool((modes.get("M2", {}) as Dictionary).get("adopted", true)) != false:
		errs.append("m2_adopted")
	var theater: Dictionary = doc.get("theater", {}) if doc.get("theater") is Dictionary else {}
	var tl: Dictionary = theater.get("time_limit", {}) if theater.get("time_limit") is Dictionary else {}
	if String(tl.get("mode", "")) != "M0": errs.append("theater_m0")
	if bool(tl.get("window_is_auto_terminal", true)) != false: errs.append("window_terminal")
	if bool(tl.get("hard_limit_enabled", true)) != false: errs.append("default_hard_limit")
	var cr: Dictionary = doc.get("contribution_rules", {}) if doc.get("contribution_rules") is Dictionary else {}
	if cr.get("command_evaluation_order", []) != EVAL_ORDER: errs.append("eval_order")
	if bool(cr.get("command_evaluation_unique", false)) != true: errs.append("eval_unique")
	if String(cr.get("ally_autonomous", "")).find("victory") < 0 \
			or String(cr.get("ally_autonomous", "")).find("未参与") < 0:
		errs.append("ally_autonomous")
	if bool(cr.get("no_identity_immunity", false)) != true: errs.append("identity_immunity")
	# ally
	var ally: Dictionary = doc.get("ally_force", {}) if doc.get("ally_force") is Dictionary else {}
	if String(ally.get("capability", "")) != "limited_armed_independent_escort":
		errs.append("ally_capability")
	var sup: Dictionary = ally.get("suppress", {}) if ally.get("suppress") is Dictionary else {}
	if bool(sup.get("real_ballistics", false)) != true: errs.append("suppress_ballistic")
	if int(sup.get("fixed_debuff_s", -1)) != 0: errs.append("suppress_debuff")
	if bool(sup.get("identity_immunity", true)) != false: errs.append("suppress_immunity")
	# traces
	var traces: Array = doc.get("event_traces", []) if doc.get("event_traces") is Array else []
	var tids: Dictionary = {}
	for raw_t in traces:
		var t: Dictionary = raw_t
		var tid := String(t.get("trace_id", ""))
		if tid == "" or tids.has(tid): errs.append("trace_id")
		tids[tid] = true
		errs.append_array(_trace_errors(doc, t))
	for need_t in ["TR-FULL-VICTORY", "TR-ALL-DISABLED-NO-REPORT",
			"TR-DEFEAT", "TR-WITHDRAW", "TR-M1-STALEMATE", "TR-M1-ZERO-TIMEOUT",
			"TR-M0-WINDOW-ONGOING", "TR-EW-NOT-PERMANENT", "TR-OBJ-B-ONE-CHAIN",
			"TR-ALLY-AUTONOMOUS-WIN", "TR-REPORT-LEAK-GUARD",
			"TR-DUPLICATE-ADJUDICATION-GUARD", "TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW"]:
		if not tids.has(need_t): errs.append("trace_missing:" + need_t)
	for need_o in ["TR-FULL-VICTORY", "TR-OBJ-B-ONE-CHAIN"]:
		if tids.has(need_o):
			pass
	if tids.has("TR-ALLY-AUTONOMOUS-WIN"):
		var at: Dictionary = _find(traces, "TR-ALLY-AUTONOMOUS-WIN")
		if String(at.get("expected_terminal", "")) != "victory": errs.append("ally_win_terminal")
		if String(at.get("command_evaluation", "")) != "未参与": errs.append("ally_win_eval")
	if tids.has("TR-M0-WINDOW-ONGOING"):
		if String(_find(traces, "TR-M0-WINDOW-ONGOING").get("expected_terminal", "")) != "ongoing":
			errs.append("m0_terminal")
	if tids.has("TR-OBJ-B-ONE-CHAIN"):
		if String(_find(traces, "TR-OBJ-B-ONE-CHAIN").get("expected_terminal", "")) == "victory":
			errs.append("objb_one_chain_victory")
	if tids.has("TR-REPORT-LEAK-GUARD"):
		var lt: Dictionary = _find(traces, "TR-REPORT-LEAK-GUARD")
		if String(lt.get("expected_player_report", "")).to_lower() != "unknown":
			errs.append("truth_leak")
	if tids.has("TR-DUPLICATE-ADJUDICATION-GUARD"):
		if int(_find(traces, "TR-DUPLICATE-ADJUDICATION-GUARD").get("terminal_events", 0)) != 1:
			errs.append("dup_adjudication")
	if tids.has("TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW"):
		if String(_find(traces, "TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW").get("expected_terminal", "")) != "defeat":
			errs.append("same_tick_priority")
	# old schema policy
	var osp: Dictionary = doc.get("old_schema_policy", {}) if doc.get("old_schema_policy") is Dictionary else {}
	if String(osp.get("v17.jc.scenario_spec.v4", "")) != "current": errs.append("v4_policy")
	if String(osp.get("v17.jc.scenario_spec.v3", "")).find("rejected") < 0: errs.append("v3_policy")
	return errs


func _trace_errors(doc: Dictionary, t: Dictionary) -> Array:
	var errs: Array = []
	var term := String(t.get("expected_terminal", ""))
	if not (term in TERMINALS): errs.append("terminal_enum:" + term)
	var authority := String(t.get("expected_authority", ""))
	if authority == "": errs.append("authority_empty")
	var report := String(t.get("expected_player_report", ""))
	if report == "": errs.append("report_empty")
	var evs: Array = t.get("events", []) if t.get("events") is Array else []
	var last := -1.0
	var adjudications := 0
	var kills: Dictionary = {}
	var chains: Dictionary = {}
	var hard := false
	var window := false
	var apsis := false
	var civ := false
	var withdraw := false
	var still := false
	for raw_e in evs:
		var e: Dictionary = raw_e
		var et := float(e.get("t", -1.0))
		if not is_finite(et) or et < 0.0 or et < last:
			errs.append("event_time_order")
		last = et
		var k := String(e.get("kind", ""))
		if k == "adjudicate":
			adjudications += 1
		elif k == "objective_disable":
			var oid := String(e.get("objective_id", ""))
			if bool(e.get("permanent", false)) != true: errs.append("disable_not_permanent")
			var chain := String(e.get("chain", ""))
			if chain == "": errs.append("disable_no_chain")
			if not chains.has(oid): chains[oid] = {}
			(chains[oid] as Dictionary)[chain] = true
			kills[oid] = true
		elif k == "target_still_effective" or k == "target_still_engaging":
			kills.erase(String(e.get("objective_id", "")))
			still = true
		elif k == "temporary_ew" or k == "temporary_link_loss":
			if bool(e.get("permanent", false)): errs.append("temp_ew_permanent")
		elif k == "time_limit_reached":
			if String(t.get("time_mode", "")) != "M1" or bool(t.get("hard_limit_enabled", false)) != true:
				errs.append("hard_limit_without_m1")
			hard = true
		elif k == "time_window_reached":
			if String(t.get("time_mode", "")) != "M0": errs.append("window_without_m0")
			window = true
		elif k == "apsis_disabled":
			apsis = true
		elif k == "protected_target_destroyed":
			civ = true
		elif k == "withdraw_complete":
			withdraw = true
		elif k == "ally_request_rejected" or k == "ally_autonomous":
			pass
	# required chains per objective
	var objs: Array = doc.get("objectives", []) if doc.get("objectives") is Array else []
	var req_chains: Dictionary = {}
	for raw_o in objs:
		var o: Dictionary = raw_o
		req_chains[String(o.get("objective_id", ""))] = o.get("required_attack_chains", [])
	var completed: Dictionary = {}
	for oid2 in kills.keys():
		var need: Array = req_chains.get(String(oid2), [])
		var have: Dictionary = chains.get(String(oid2), {})
		var all := true
		for nc in need:
			if not have.has(String(nc)): all = false
		if all: completed[String(oid2)] = true
	var req: Array = (doc.get("terminal_rules", {}).get("victory", {}) as Dictionary).get(
		"required_objectives", []) if doc.get("terminal_rules") is Dictionary else []
	var completed_n := 0
	for rid in req:
		if completed.has(String(rid)): completed_n += 1
	var cands: Array = []
	if completed_n >= req.size() and req.size() > 0: cands.append("victory")
	if apsis or civ: cands.append("defeat")
	if withdraw: cands.append("withdrawal")
	if hard and completed_n == 0: cands.append("defeat")
	if hard and completed_n > 0 and completed_n < req.size(): cands.append("stalemate")
	var derived := ""
	if String(t.get("time_mode", "")) == "M0" and window and adjudications == 0:
		derived = "ongoing"
	elif String(t.get("time_mode", "")) == "M1" and hard:
		for p in PRIORITY:
			if String(p) in cands:
				derived = String(p)
				break
		if derived == "": derived = "ongoing"
	else:
		for p2 in PRIORITY:
			if String(p2) in cands:
				derived = String(p2)
				break
		if derived == "":
			derived = "ongoing"
	# pending_report / report-late semantics
	if report.to_lower() == "unknown":
		if authority == "all_required_disabled" and term != "pending_report":
			errs.append("pending_report_terminal")
		elif authority != "all_required_disabled" and term != "pending_report" and term != "ongoing":
			errs.append("unknown_report_terminal")
	elif term != derived:
		errs.append("terminal_rule:%s!=%s" % [term, derived])
	if adjudications > 2: errs.append("adjudication_count")
	if int(t.get("terminal_events", -1)) < 0 or int(t.get("terminal_events", -1)) > 1:
		errs.append("terminal_events")
	if int(t.get("terminal_events", -1)) == 1 and adjudications == 0:
		errs.append("terminal_without_adjudicate")
	if int(t.get("terminal_events", -1)) == 0 and adjudications > 0:
		errs.append("adjudicate_without_terminal")
	if bool(t.get("no_truth_leak", false)):
		if report.to_lower() != "unknown" and term != "pending_report":
			errs.append("truth_leak")
	if term == "ongoing":
		if adjudications > 0: errs.append("ongoing_with_adjudicate")
		for k in ["apsis_disabled", "protected_target_destroyed", "withdraw_complete"]:
			for raw_e2 in evs:
				if String((raw_e2 as Dictionary).get("kind", "")) == k:
					errs.append("ongoing_but_defeat_condition")
	if String(t.get("time_mode", "")) == "M1" and not hard:
		errs.append("m1_without_hard_limit")
	if String(t.get("time_mode", "")) == "M0" and hard:
		errs.append("m0_with_hard_limit")
	return errs


# ── helpers ─────────────────────────────────────────────────────

func _with_composition(doc: Dictionary, cid: String) -> Dictionary:
	var out: Dictionary = doc.duplicate(true)
	var comps: Array = ((out.get("combat_selection", {}) as Dictionary).get(
		"four_legal_compositions", []) as Array)
	var chosen: Array = []
	for raw_c in comps:
		if String((raw_c as Dictionary).get("composition_id", "")) == cid:
			chosen = (raw_c as Dictionary).get("ships", []) as Array
	var ids: Array = []
	for raw_s in chosen:
		ids.append(String((raw_s as Dictionary).get("instance_id", "")))
	var fo: Dictionary = out.get("fleet_ownership", {})
	var old_owned: Array = fo.get("owned_instance_ids", [])
	var support_ids: Array = old_owned.slice(0, SUPPORT_COUNT)
	fo["owned_instance_ids"] = support_ids + ids
	var dep: Dictionary = out.get("deployment", {})
	dep["deployed_instance_ids"] = support_ids + ids
	dep["selected_composition_id"] = cid
	((out.get("combat_selection", {}) as Dictionary))["selected_composition_id"] = cid
	for raw_g in (dep.get("task_groups", []) as Array):
		if String((raw_g as Dictionary).get("group_id", "")) == "TG-STRIKE":
			(raw_g as Dictionary)["instance_ids"] = ids
	return out


func _find(traces: Array, tid: String) -> Dictionary:
	for raw in traces:
		if raw is Dictionary and String((raw as Dictionary).get("trace_id", "")) == tid:
			return raw
	return {}


func _weapons_of(path: String, class_id: String) -> Array:
	var doc: Dictionary = _read_json(path)
	for raw in (doc.get("classes", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("class_id", "")) == class_id:
			var w = (raw as Dictionary).get("weapons", [])
			return w if w is Array else []
	return []


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
