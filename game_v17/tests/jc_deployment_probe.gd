extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-B01A DEPLOYMENT PROBE · #62
# 选择→校验→冻结部署→真实生成：两套编制在 catalog/world/physics/资源
# 层恰好等于选择；未选舰零残留；实例资源独立；质量 t→kg 一次；幂等/
# 原子拒绝/部署锁/存档恢复/旧单舰 seed 兼容；最小部署入口合同。
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const TICK_DT := 1.0
const TOL := 1.0e-9

var _pass := 0
var _fail := 0
var _failures: Array = []

const SEL_A := [
	{"ship_id": "APSIS", "slot": "command", "instance_id": "apsis"},
	{"ship_id": "HARMATTAN", "slot": "screen", "instance_id": "harmattan"},
]
const SEL_B := [
	{"ship_id": "PERIGEE", "slot": "command", "instance_id": "perigee"},
	{"ship_id": "FERRY", "slot": "gun", "instance_id": "ferry"},
	{"ship_id": "WATCHTOWER", "slot": "relay", "instance_id": "watchtower"},
]
const EXPECTED_A := ["apsis", "harmattan"]
const EXPECTED_B := ["ferry", "perigee", "watchtower"]

func _initialize() -> void:
	print("[B01A] START")
	_run()
	_finish()

func _finish() -> void:
	print("────────────────────────────────────────────────────────────────")
	print("JC-B01A DEPLOYMENT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	for f in _failures:
		print("[B01A] FAILED: ", f)
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[B01A] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[B01A] FAIL ", line)

func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		"%s actual=%s expected=%s" % [detail, str(actual), str(expected)])

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=%s" % [actual, expected, str(tol)])

func _step(title: String) -> void:
	print("")
	print("[B01A] STEP ", title)

func _info(text: String) -> void:
	print("[B01A] INFO ", text)

# ── fixture ───────────────────────────────────────────────────────

func _seed(selection: Array, scenario := "A", extra := {}) -> Dictionary:
	var sd := {
		"own_entity": "apsis",
		"physics_world": {"auto_seed": true},
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"ship_catalog": {},
		"fleet_formation": {}, "fleet_refit": {},
		"entities": [
			{"id": "legacy_ship", "kind": "ship", "name": "legacy",
				"pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
		],
		"deployment": {
			"scenario_id": scenario,
			"deployment_seed": 424242,
			"selection": {"ships": selection.duplicate(true)},
		},
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "fleet_id": "own_fleet",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "fleet_id": "ally_fleet",
				"authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "fleet_id": "enemy_fleet",
				"authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "apsis", "domain_id": "player",
				"fleet_id": "own_fleet"}],
		"ew_service": {},
		"identification_service": {"auto": {"enabled": false}},
	}
	for key in extra.keys():
		sd[key] = extra[key]
	return sd

func _new(selection: Array, scenario := "A", extra := {}) -> Variant:
	return GS.new(_seed(selection, scenario, extra))

func _ids_of(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get("id", "")))
	for i in range(out.size()):
		if String(out[i]) == "":
			out[i] = "?"
	out.sort()
	return out

func _meta_ids(s) -> Array:
	if s == null or not s.has_method("entity_metadata_ids"):
		return []
	var ids: Array = s.entity_metadata_ids()
	ids.sort()
	return ids

func _physics_ids(s) -> Array:
	if s == null or s.physics_world_service == null:
		return []
	var ids: Array = s.physics_world_service.entity_ids()
	ids.sort()
	return ids

func _world_ids(s) -> Array:
	if s == null or s.world == null:
		return []
	var ids: Array = []
	for raw in s.world.entities.keys():
		ids.append(String(raw))
	ids.sort()
	return ids

func _has_api(s, m: String) -> bool:
	return s != null and s.has_method(m)

func _plan(s, selection: Array) -> Dictionary:
	if not _has_api(s, "fleet_deployment_plan"):
		return {"ok": false, "reason": "missing_api"}
	return s.fleet_deployment_plan({"ships": selection})

func _deploy(s, selection: Array, opts := {"confirm": true}) -> Dictionary:
	if not _has_api(s, "fleet_deploy"):
		return {"ok": false, "reason": "missing_api"}
	return s.fleet_deploy({"ships": selection}, opts)

func _vm(s) -> Dictionary:
	if not _has_api(s, "fleet_deployment_vm"):
		return {}
	return s.fleet_deployment_vm()

func _resources(s, iid: String) -> Dictionary:
	if not _has_api(s, "deployment_resources"):
		return {}
	return s.deployment_resources(iid)

func _patch(s, iid: String, patch: Dictionary) -> Dictionary:
	if not _has_api(s, "deployment_test_patch"):
		return {"ok": false, "reason": "missing_api"}
	return s.deployment_test_patch(iid, patch)

func _ev_ids(vm: Dictionary) -> Array:
	var out: Array = []
	for raw in (vm.get("instance_ids", []) as Array):
		out.append(String(raw))
	out.sort()
	return out

func _fleet_instance_map(s) -> Dictionary:
	if s == null or s.authority_intel == null:
		return {}
	return s.authority_intel.instances.duplicate(true)

func _own_domain(s) -> String:
	if s == null or s.authority_intel == null:
		return ""
	var own := String(s._seed.get("own_entity", ""))
	var insts: Dictionary = s.authority_intel.instances if \
		s.authority_intel.instances is Dictionary else {}
	if insts.has(own):
		var oi: Dictionary = insts[own] if insts[own] is Dictionary else {}
		return String(oi.get("domain_id", ""))
	return ""

# ── run ───────────────────────────────────────────────────────────

func _run() -> void:
	_step("J0 合法 A/B 编制 boot 与冻结结果")
	var a = _new(SEL_A, "A")
	var b = _new(SEL_B, "B")
	_ok(a != null and bool(a.ready), "A 编制 boot ready", str(a.errors))
	_ok(b != null and bool(b.ready), "B 编制 boot ready", str(b.errors))
	if a == null or b == null:
		return
	var va: Dictionary = _vm(a)
	var vb: Dictionary = _vm(b)
	_ok(not va.is_empty(), "A deployment vm 可读", str(va.get("reason", "")))
	_ok(not vb.is_empty(), "B deployment vm 可读", str(vb.get("reason", "")))
	_eq(_ev_ids(va), EXPECTED_A, "A 实例 id 集合 = 选择")
	_eq(_ev_ids(vb), EXPECTED_B, "B 实例 id 集合 = 选择")
	_ok(String(va.get("revision", "")) != "",
		"A 冻结 revision 非空", str(va.get("revision", "")))
	_ok(String(va.get("revision", ""))
		!= String(vb.get("revision", "")),
		"A/B 不同编制 revision 不同")
	_eq(int(va.get("deployment_seed", -1)), 424242,
		"部署 seed 与 seed 配置同源")

	_step("J1 未选舰零残留：catalog / physics / world 恰好等于选择")
	_eq(_meta_ids(a), EXPECTED_A, "A catalog 实体 = 选择")
	_eq(_physics_ids(a), EXPECTED_A, "A physics 实体 = 选择")
	_eq(_world_ids(a), EXPECTED_A, "A world 实体 = 选择")
	_eq(_meta_ids(b), EXPECTED_B, "B catalog 实体 = 选择")
	_eq(_physics_ids(b), EXPECTED_B, "B physics 实体 = 选择")
	_eq(_world_ids(b), EXPECTED_B, "B world 实体 = 选择")
	var all_ids: Array = []
	all_ids.append_array(_meta_ids(a))
	all_ids.append_array(_physics_ids(a))
	all_ids.append_array(_world_ids(a))
	_ok(not ("legacy_ship" in all_ids), "A 旧实体不残留")
	_ok(not ("ferry" in all_ids) and not ("watchtower" in all_ids),
		"A 未选 B 舰不残留")
	_ok(not (String(va.get("scenario_id", "")) == ""), "A scenario 记录")
	_info("A meta/physics/world=%s/%s/%s B=%s/%s/%s" % [
		str(_meta_ids(a)), str(_physics_ids(a)), str(_world_ids(a)),
		str(_meta_ids(b)), str(_physics_ids(b)), str(_world_ids(b))])

	_step("J2 实例独立资源与质量/燃料单位转换")
	var ra: Dictionary = _resources(a, "apsis")
	var rb: Dictionary = _resources(a, "harmattan")
	_ok(not ra.is_empty() and not rb.is_empty(),
		"A 两实例资源账本可读", str(ra.get("reason", "")))
	if not ra.is_empty() and not rb.is_empty():
		_ok(ra.get("resources") is Dictionary and rb.get("resources") is Dictionary,
			"资源容器是独立 Dictionary")
		var fuel_a0 := float((ra.get("resources", {}) as Dictionary).get(
			"fuel_kg", -1.0))
		var fuel_b0 := float((rb.get("resources", {}) as Dictionary).get(
			"fuel_kg", -1.0))
		var pa: Dictionary = _patch(a, "apsis", {"resources": {
			"fuel_kg": fuel_a0 + 1000.0, "damage_taken": 0.25}})
		_ok(bool(pa.get("ok", false)), "修改 A 实例燃料/损伤成功",
			str(pa.get("reason", "")))
		var ra2: Dictionary = _resources(a, "apsis")
		var rb2: Dictionary = _resources(a, "harmattan")
		_near(float((ra2.get("resources", {}) as Dictionary).get(
			"fuel_kg", -1.0)), fuel_a0 + 1000.0, TOL, "A 修改只影响 A 燃料")
		_near(float((rb2.get("resources", {}) as Dictionary).get(
			"fuel_kg", -1.0)), fuel_b0, TOL, "B 实例燃料不变")
		_ok(absf(float((rb2.get("resources", {}) as Dictionary).get(
			"damage_taken", 0.0))) < TOL, "B 实例损伤不变")
		var mass_kg := float(ra.get("mass_kg", -1.0))
		var mass_t := float(ra.get("mass_t", -2.0))
		_near(mass_kg, mass_t * 1000.0, 1.0e-6,
			"质量 t→kg 只转换一次（apsis）")
		var mass_b := float(rb.get("mass_kg", -1.0))
		var mass_bt := float(rb.get("mass_t", -2.0))
		_near(mass_b, mass_bt * 1000.0, 1.0e-6,
			"质量 t→kg 只转换一次（harmattan）")

	_step("J3 负例：原子拒绝且原因明确")
	var bad_cases: Array = [
		{"label": "未知舰 id", "sel": [
			{"ship_id": "NO_SUCH_SHIP", "slot": "command", "instance_id": "x"}]},
		{"label": "重复 instance id", "sel": [
			{"ship_id": "APSIS", "slot": "command", "instance_id": "dup"},
			{"ship_id": "HARMATTAN", "slot": "screen", "instance_id": "dup"}]},
		{"label": "槽位超限", "sel": [
			{"ship_id": "APSIS", "slot": "command", "instance_id": "a1"},
			{"ship_id": "PERIGEE", "slot": "command", "instance_id": "a2"}]},
		{"label": "空选择", "sel": []},
	]
	for case in bad_cases:
		var s = _new(case["sel"] as Array, "NEG")
		var ok := s != null and bool(s.ready)
		var reason := ""
		var verr: Array = []
		if s != null:
			verr = s.errors.duplicate()
			reason = ",".join(verr)
		_ok(not ok or reason.contains("deployment"), String(case["label"]) + " 拒绝",
			"ready=%s errors=%s" % [str(ok), str(verr)])
	var a3 = _new(SEL_A, "NEG2")
	var bad_deploy: Dictionary = _deploy(a3, [
		{"ship_id": "NO_SUCH", "slot": "command", "instance_id": "z"}])
	_ok(bool(bad_deploy.get("ok", true)) == false, "部署时未知舰拒绝")
	_ok(String(bad_deploy.get("reason", "")) != "", "unknown class/ship 原因明确",
		str(bad_deploy.get("reason", "")))
	_eq((_meta_ids(a3) as Array).size(), EXPECTED_A.size(),
		"失败部署不半生成（catalog 仍为原部署）")
	var no_confirm: Dictionary = _deploy(a3, SEL_A, {})
	_ok(bool(no_confirm.get("ok", true)) == false, "缺少 confirm 的部署拒绝")
	_ok(String(no_confirm.get("reason", "")) != "", "confirm 缺失原因明确",
		str(no_confirm.get("reason", "")))

	_step("J4 幂等 / 部署锁")
	var a4 = _new(SEL_A, "IDEM")
	var d1: Dictionary = _deploy(a4, SEL_A)
	_ok(bool(d1.get("ok", false)), "首次 confirm 部署成功",
		str(d1.get("reason", "")))
	var d2: Dictionary = _deploy(a4, SEL_A)
	_ok(bool(d2.get("ok", false)), "同选择重复部署幂等成功",
		str(d2.get("reason", "")))
	_eq(_ev_ids(_vm(a4)), EXPECTED_A, "重复部署实例集合不变")
	_advance(a4, 2.0)
	var d3: Dictionary = _deploy(a4, SEL_B)
	_ok(bool(d3.get("ok", true)) == false, "已部署后换编制拒绝")
	_eq(String(d3.get("reason", "")), "deployment_locked",
		"换编制原因 deployment_locked")

	_step("J5 存档/恢复：部署前后、同 t 映射、10 tick 一致、无重复实体")
	var a5 = _new(SEL_A, "SAVE")
	var path := "user://jc_b01a_deploy.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(a5.save_state())
	f.close()
	var b5 = _new(SEL_A, "SAVE")
	var lr: Dictionary = b5.load_state(FileAccess.get_file_as_string(path))
	_ok(bool(lr.get("ok", false)), "部署前真实文件恢复成功", str(lr.get("errors", [])))
	_eq(_ev_ids(_vm(b5)), EXPECTED_A, "部署前恢复实例映射一致")
	_eq(_meta_ids(b5), EXPECTED_A, "部署前恢复 catalog 一致")
	var a6 = _new(SEL_A, "SAVE")
	_advance(a6, 1.0)
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(a6.save_state())
	f2.close()
	var b6 = _new(SEL_A, "SAVE")
	var lr2: Dictionary = b6.load_state(FileAccess.get_file_as_string(path))
	_ok(bool(lr2.get("ok", false)), "部署后真实文件恢复成功",
		str(lr2.get("errors", [])))
	_eq(_ev_ids(_vm(b6)), EXPECTED_A, "部署后恢复实例映射一致")
	_eq(_meta_ids(b6), EXPECTED_A, "部署后 catalog 无重复实体")
	_eq(_physics_ids(b6), EXPECTED_A, "部署后 physics 无重复实体")
	var pa0: Array = _positions(a6)
	var pb0: Array = _positions(b6)
	for i in range(10):
		a6.tick(TICK_DT)
		b6.tick(TICK_DT)
	var pa1: Array = _positions(a6)
	var pb1: Array = _positions(b6)
	_eq(JSON.stringify(pa1), JSON.stringify(pb1),
		"恢复后继续 10 tick 运动一致", "cont=%s restored=%s" % [
			str(pa1), str(pb1)])
	_ok(pa0.size() == pb0.size(), "部署实例位置集合可读")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 预部署阶段（auto=false）：pending 不生成实体；恢复后确认→真实生成；资源持久化
	var pre_extra := {"deployment": {"scenario_id": "PRE",
		"deployment_seed": 424242,
		"selection": {"ships": SEL_A}, "auto": false}}
	var a7 = _new(SEL_A, "PRE", pre_extra)
	_ok(a7 != null and bool(a7.ready), "预部署 auto=false boot ready",
		str(a7.errors if a7 != null else []))
	_eq(_ev_ids(_vm(a7)), [], "预部署阶段尚无冻结实例")
	_eq(_meta_ids(a7), ["legacy_ship"], "预部署阶段不生成参战实体")
	var pre_path := "user://jc_b01a_predeploy.json"
	var fp := FileAccess.open(pre_path, FileAccess.WRITE)
	fp.store_string(a7.save_state())
	fp.close()
	var a7b = _new(SEL_A, "PRE", pre_extra)
	var lrp: Dictionary = a7b.load_state(FileAccess.get_file_as_string(pre_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pre_path))
	_ok(bool(lrp.get("ok", false)), "预部署阶段真实文件恢复成功",
		str(lrp.get("errors", [])))
	_eq(_ev_ids(_vm(a7b)), [], "预部署恢复不提前生成实例")
	var dep_pre: Dictionary = _deploy(a7b, SEL_A)
	_ok(bool(dep_pre.get("ok", false)), "预部署恢复后 confirm 部署成功",
		str(dep_pre.get("reason", "")))
	_eq(_ev_ids(_vm(a7b)), EXPECTED_A, "部署后实例集合 = 选择")
	_eq(_meta_ids(a7b), EXPECTED_A, "部署后 catalog = 选择")
	_advance(a7b, 1.0)
	var dep_lock: Dictionary = _deploy(a7b, SEL_B)
	_eq(String(dep_lock.get("reason", "")), "deployment_locked",
		"运行开始后换编制 deployment_locked")
	# 资源随真实文件恢复
	var a8 = _new(SEL_A, "RES")
	var r8: Dictionary = _resources(a8, "apsis")
	var fuel8 := float(((r8.get("resources", {}) as Dictionary)).get(
		"fuel_kg", 0.0))
	_patch(a8, "apsis", {"resources": {"fuel_kg": fuel8 + 4321.0,
		"damage_taken": 0.4}})
	var res_path := "user://jc_b01a_res.json"
	var fr := FileAccess.open(res_path, FileAccess.WRITE)
	fr.store_string(a8.save_state())
	fr.close()
	var a8b = _new(SEL_A, "RES")
	var lrr: Dictionary = a8b.load_state(FileAccess.get_file_as_string(res_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(res_path))
	_ok(bool(lrr.get("ok", false)), "部署资源真实文件恢复成功",
		str(lrr.get("errors", [])))
	var r8b: Dictionary = _resources(a8b, "apsis")
	_near(float(((r8b.get("resources", {}) as Dictionary)).get(
		"fuel_kg", -1.0)), fuel8 + 4321.0, TOL, "恢复后实例燃料保持")
	_near(float(((r8b.get("resources", {}) as Dictionary)).get(
		"damage_taken", -1.0)), 0.4, TOL, "恢复后实例损伤保持")
	_eq(_meta_ids(a8b), EXPECTED_A, "资源恢复不生成重复实体")
	# 部署实例同步 own/fleet_instances/owner
	var fim: Dictionary = _fleet_instance_map(a)
	_ok(fim.has("apsis") and fim.has("harmattan"),
		"部署实例进入 fleet_instances", str(fim.keys()))
	_ok(String(a._seed.get("own_entity", "")) in EXPECTED_A,
		"own_entity 指向已部署旗舰", str(a._seed.get("own_entity", "")))
	_ok(_own_domain(a) == "player", "部署旗舰 owner 域为 player",
		_own_domain(a))


	_step("J6 旧单舰 seed 兼容与部署入口/UI 合同")
	var legacy = GS.new({
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"entities": [{"id": "own_ship", "kind": "ship",
			"pos_km": [1.0, 2.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}]})
	_ok(legacy != null and bool(legacy.ready), "旧单舰 seed 仍可 boot",
		str(legacy.errors if legacy != null else []))
	_eq(_meta_ids(legacy), ["own_ship"], "旧 seed catalog 保持原实体")
	_ok(not _has_api(legacy, "fleet_deployment_vm")
		or _vm(legacy).get("enabled", true) == false,
		"无 deployment 配置时部署入口未启用/明确不可用")
	_ok(_has_api(a, "fleet_deploy"), "Session 暴露 fleet_deploy 入口")
	_ok(_has_api(a, "fleet_deployment_plan"), "Session 暴露只读 plan 入口")
	_ok(_has_api(a, "fleet_deployment_vm"), "Session 暴露 deployment vm")
	_ok(_has_api(a, "deployment_resources"), "Session 暴露实例资源入口")

func _advance(s, seconds: float) -> void:
	var n := int(round(seconds / TICK_DT))
	for i in range(n):
		s.tick(TICK_DT)

func _positions(s) -> Array:
	if s == null or s.physics_world_service == null:
		return []
	var out: Array = []
	var ids: Array = s.physics_world_service.entity_ids()
	ids.sort()
	for iid in ids:
		var ents: Dictionary = s.physics_world_service.entities \
			if s.physics_world_service.entities is Dictionary else {}
		var st: Dictionary = ents.get(String(iid), {}) \
			if ents.get(String(iid)) is Dictionary else {}
		out.append({"id": String(iid),
			"r": (st.get("r", st.get("pos_km", [])) as Array).duplicate() \
				if st.get("r", st.get("pos_km")) is Array else [],
			"v": (st.get("v", st.get("vel_kmps", [])) as Array).duplicate() \
				if st.get("v", st.get("vel_kmps")) is Array else []})
	return out
