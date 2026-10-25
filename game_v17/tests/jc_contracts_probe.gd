extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-B00：联合战役多舰队/指挥/情报契约探针（K0）
#
# 只校验**结构与语义**（引用完整性、权限分离、单位、时序、序号范围）与
# 可逆序列化；不引入假 AI、不生成“已完成”战役快照、不声明真实舰队已运行。
#
# Output: `JC-B00 CONTRACTS PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const Contracts := preload("res://scripts/core/jc_contracts.gd")
const FIX := "res://tests/fixtures/jc_contracts"
const VALID := FIX + "/valid_three_domains.json"

# 负例 → 期望命中的错误关键字
const NEG_CASES := {
	"invalid_duplicate_instance.json": "重复 entity_instance_id",
	"invalid_cross_domain.json": "跨域指挥",
	"invalid_shooter.json": "shooter_id",
	"invalid_resource_owner.json": "资源引用别舰",
	"invalid_units.json": "单位",
	"invalid_version.json": "version",
	"invalid_time_order.json": "observed_t",
	"invalid_counter.json": "threshold",
	"invalid_not_deployed.json": "部署清单",
	# R6：冻结 actor→controller→shooter 授权
	"invalid_actor_controller.json": "授权名单",
	# R6：情报共享授权者必须是情报拥有者
	"invalid_obs_authorization.json": "未由情报拥有者授权",
	# R6：delay 必须与 received-observed 一致
	"invalid_delay.json": "延迟不一致",
	# R6：幂等键冲突载荷拒绝
	"invalid_idempotency.json": "幂等键冲突",
	# R6：整数计数不接受浮点
	"invalid_ledger_types.json": "非负安全整数",
	# R6：AI 不得直读真值
	"invalid_ai_truth.json": "reads_ground_truth",
	# R6：roster 引用必须已登记
	"invalid_roster_ref.json": "roster 引用未登记实例",
	# R6：选择→部署逐一对应
	"invalid_selection_mapping.json": "未出现在部署清单",
}

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-B00 CONTRACTS PROBE · schema=", Contracts.SCHEMA,
		" version=", Contracts.VERSION)
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(120.0).timeout
	if _finished:
		return
	print("[JC-B00] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-B00 CONTRACTS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[JC-B00] FAILED: ", f)
		print("JC-B00 CONTRACTS PROBE FAILED")
	else:
		print("JC-B00 CONTRACTS PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[JC-B00] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[JC-B00] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(title: String) -> void:
	print("")
	print("[JC-B00] STEP ", title)


func _info(text: String) -> void:
	print("[JC-B00] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. 合法契约：三分域 + 两套自有编制 + 单舰账本")
	var doc: Dictionary = _read_json(VALID)
	_ok(not doc.is_empty(), "valid fixture 可读", VALID)
	if doc.is_empty():
		_finish()
		return
	var res: Dictionary = Contracts.validate(doc)
	_ok(bool(res.get("ok", false)), "valid fixture 通过语义校验",
		"errors=" + str(res.get("errors", [])))
	_ok((res.get("errors", []) as Array).is_empty(), "valid fixture 无错误")
	_eq((doc.get("command_domains", []) as Array).size(), 3,
		"恰好 3 个指挥域（player/ai_ally/ai_hostile）")
	var player_fleets := 0
	for raw in (doc.get("fleets", []) as Array):
		if String((raw as Dictionary).get("domain_id", "")) == "player":
			player_fleets += 1
	_eq(player_fleets, 2, "玩家有 2 套自有编制")
	# 阵营/直控/情报/ROE 四者分离
	var dom0: Dictionary = (doc.get("command_domains", []) as Array)[0]
	_ok(String(dom0.get("faction", "")) != String(dom0.get("controller_id", "")),
		"阵营与直控是两个字段（friend≠直控）")
	_ok(String(dom0.get("intel_owner_id", "")) != "",
		"情报拥有者独立建模", String(dom0.get("intel_owner_id", "")))
	_ok(String(dom0.get("roe", "")) != "", "ROE 授权独立建模",
		String(dom0.get("roe", "")))
	# 选择→实例关系：roster 成员必须是本 fleet 实例
	var roster_ok := true
	var inst_of: Dictionary = {}
	for raw_i in (doc.get("instances", []) as Array):
		inst_of[String((raw_i as Dictionary).get("entity_instance_id", ""))] = \
			String((raw_i as Dictionary).get("fleet_id", ""))
	for raw_f in (doc.get("fleets", []) as Array):
		var f: Dictionary = raw_f
		for raw_r in (f.get("roster", []) as Array):
			var rid := String((raw_r as Dictionary).get("entity_instance_id", ""))
			if not inst_of.has(rid) or String(inst_of[rid]) != String(f.get("fleet_id", "")):
				roster_ok = false
	_ok(roster_ok, "roster 成员都是本舰队的实例（选择→实例关系明确）")
	# 未选择舰不在部署清单
	var deployed_ids: Dictionary = {}
	for raw_d in (doc.get("deployments", []) as Array):
		deployed_ids[String((raw_d as Dictionary).get("entity_instance_id", ""))] = true
	var list_only_deployed := true
	for eid in deployed_ids.keys():
		if not inst_of.has(eid):
			list_only_deployed = false
	_ok(list_only_deployed, "部署清单只包含已登记实例")

	_step("2. 可逆序列化（JSON 往返后语义不变）")
	var rt: Dictionary = Contracts.roundtrip(doc)
	_ok(bool(rt.get("ok", false)), "JSON 往返后仍通过校验",
		"errors=" + str(rt.get("errors", [])))
	var back: Dictionary = rt.get("doc", {}) if rt.get("doc") is Dictionary else {}
	_eq((back.get("command_domains", []) as Array).size(),
		(doc.get("command_domains", []) as Array).size(),
		"往返后指挥域数量一致")
	var back_ver = back.get("version", null)
	_ok(back_ver is int or (back_ver is float and absf(float(back_ver) - roundf(float(back_ver))) < 1.0e-9),
		"往返后 version 仍是整数值", str(back_ver))

	_step("3. 单位契约：t→kg 只换算一次")
	_eq(Contracts.tons_to_kg(12.0), 12000.0, "12 t → 12000 kg")
	_eq(Contracts.tons_to_kg(1.0), 1000.0, "1 t → 1000 kg")
	var twice: float = Contracts.tons_to_kg(Contracts.tons_to_kg(1.0))
	_ok(absf(twice - 1000000.0) < 1.0e-6,
		"重复换算会得到不同量级（证明只允许一次）", str(twice))

	_step("4. 负例矩阵：逐项明确拒绝")
	for fname in NEG_CASES.keys():
		var fdoc: Dictionary = _read_json(FIX + "/" + String(fname))
		if fdoc.is_empty():
			_ok(false, "负例 fixture 可读: " + String(fname))
			continue
		var r: Dictionary = Contracts.validate(fdoc)
		var errs: Array = r.get("errors", [])
		var joined := JSON.stringify(errs)
		var expect := String(NEG_CASES[fname])
		var hit := joined.find(expect) >= 0
		_ok(bool(r.get("ok", true)) == false, "NEGATIVE 被拒绝: " + String(fname),
			"reason=" + str(errs.slice(0, 2)))
		_ok(hit, "NEGATIVE 命中期望原因: " + String(fname), "expect~" + expect)

	_step("5. 权限分离与旧调用语义")
	# 跨域指挥必须拒绝（已由 invalid_cross_domain 覆盖），再断言典型正例的 controller 一致
	var ok_cmd: Dictionary = (doc.get("commands", []) as Array)[0]
	_eq(String(ok_cmd.get("controller_id", "")),
		String(dom0.get("controller_id", "")), "合法命令的 controller 与域直控一致")
	# 旧调用只能映射 own_ship
	var legacy_doc: Dictionary = doc.duplicate(true)
	(legacy_doc.get("commands", []) as Array)[0]["legacy_context"] = "own_ship"
	(legacy_doc.get("commands", []) as Array)[0]["own_entity_instance_id"] = "I-A1"
	var lr: Dictionary = Contracts.validate(legacy_doc)
	_ok(bool(lr.get("ok", false)), "legacy_context=own_ship 被接受",
		"errors=" + str(lr.get("errors", [])))
	var bad_legacy: Dictionary = doc.duplicate(true)
	(bad_legacy.get("commands", []) as Array)[0]["legacy_context"] = "all_allies"
	var blr: Dictionary = Contracts.validate(bad_legacy)
	_ok(bool(blr.get("ok", true)) == false,
		"NEGATIVE: 旧调用不能扩成所有友舰",
		"reason=" + str(blr.get("errors", []).slice(0, 2)))
	# 目标：权威裁决与玩家获知分开
	var obj: Dictionary = (doc.get("objectives", []) as Array)[0]
	_ok(obj.has("authority_state") and obj.has("player_known_state"),
		"目标同时有 authority_state 与 player_known_state")
	_ok(bool(obj.get("story_independent", false)),
		"目标 story_independent=true（story=false 仍裁决）")

	_step("6. R6 冻结项：情报分区 / AI 只读视图 / 生命周期 / legacy scope")
	_eq(String(doc.get("intel_partitioning", "")), "per_owner_track_table",
		"冻结分方情报方案 = per_owner_track_table")
	var view2: Dictionary = doc.get("ai_read_view", {}) if doc.get("ai_read_view") is Dictionary else {}
	_eq(bool(view2.get("reads_ground_truth", true)), false,
		"AI 只读视图不得直读真值")
	var byd: Dictionary = view2.get("by_domain", {}) if view2.get("by_domain") is Dictionary else {}
	_ok(byd.size() >= 3, "AI 只读视图按域授权", str(byd.size()))
	var lc: Array = doc.get("event_lifecycle", []) if doc.get("event_lifecycle") is Array else []
	_eq(lc.size(), 6, "事件/通信生命周期冻结为 6 阶段")
	_eq(String(lc[0]) if lc.size() > 0 else "", "created", "生命周期首阶段 created")
	_eq(String(lc[lc.size() - 1]) if lc.size() > 0 else "", "closed", "生命周期末阶段 closed")
	var ls: Dictionary = doc.get("legacy_scope", {}) if doc.get("legacy_scope") is Dictionary else {}
	_eq(bool(ls.get("own_ship_only", false)), true, "legacy scope 只映射本舰")
	# 授权绑定：合法命令的 actor 必须在该域授权名单内
	var doms: Array = doc.get("command_domains", [])
	var doms_by_id: Dictionary = {}
	for raw_d in doms:
		doms_by_id[String((raw_d as Dictionary).get("domain_id", ""))] = raw_d
	var cmd0: Dictionary = (doc.get("commands", []) as Array)[0]
	var cmd_dom: Dictionary = doms_by_id.get(String(cmd0.get("domain_id", "")), {})
	var auth_actors: Array = cmd_dom.get("authorized_actors", [])
	_ok(String(cmd0.get("actor_id", "")) in auth_actors,
		"合法命令 actor 在域授权名单内", String(cmd0.get("actor_id", "")))
	_ok(not auth_actors.is_empty(), "域授权名单非空（冻结 actor→controller）")
	_step("7. 明确未实现边界（不伪造运行态）")
	_info("本探针只证明数据契约与拒绝语义；不声称真实舰队已部署/AI 已行动/战役可玩")
	_info("K0 字段表与权威划分见 game_v17/docs/contracts/joint_campaign_r2.md")
	_finish()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
