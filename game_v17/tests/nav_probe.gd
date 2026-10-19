extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R4-NAV-CORE-1 headless probe：导航 / 交通管制 / 机动规划模型
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/nav_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
#
# 覆盖：内容 schema/校验、节点/位置 provider、路线候选（快速/经济/隐蔽 + 约束）、
#       交通许可 grant/deny/hold/expire + 优先级队列、机动状态机、Δv 预算、
#       只读 vm/JSON、无自动执行、确定性、内容驱动。
# ═══════════════════════════════════════════════════════════════════

const Nav := preload("res://framework/core/navigation_model.gd")
const CONTENT_PATH := "res://framework/content/navigation_l1.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []
var _provider_calls := 0


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R4-NAV-CORE-1 PROBE · 导航 / 交通管制 / 机动规划（规划模型，无物理）")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_setup_and_nodes()
	_test_position_provider()
	_test_route_candidates()
	_test_route_constraints()
	_test_route_no_execution()
	_test_traffic_basic()
	_test_traffic_queue_priority()
	_test_traffic_denials()
	_test_traffic_manual_actions()
	_test_traffic_expiry()
	_test_traffic_queue_full()
	_test_maneuver_planning()
	_test_maneuver_state_machine()
	_test_maneuver_abort()
	_test_maneuver_clearance()
	_test_maneuver_budget()
	_test_vm_and_json()
	_test_readonly_and_no_physics()
	_test_determinism()
	_test_content_driven()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("NAV PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("NAV PROBE FAILED")
		quit(1)
	else:
		print("NAV PROBE OK")
		quit(0)


# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
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
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%.5f expected=%.5f diff=%.5f tol=%.5f" % [actual, expected, diff, tol])


func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)


func _new_nav(override := {}):
	var m = Nav.new()
	var ok: bool = m.setup(override)
	return m


func _fresh():
	var m = _new_nav()
	return m


func _base_content() -> Dictionary:
	return Nav.load_content().duplicate(true)


func _edges_list(m) -> Array:
	return m.edges


func _edge_by_id(m, eid: String) -> Dictionary:
	return m.edges_by_id.get(eid, {})


func _candidate_path_valid(m, cand: Dictionary) -> bool:
	var path: Array = cand.get("path", [])
	var eids: Array = cand.get("edges", [])
	if path.size() != eids.size() + 1:
		return false
	for i in range(eids.size()):
		var e: Dictionary = _edge_by_id(m, String(eids[i]))
		if e.is_empty():
			return false
		var from_id := String(path[i])
		var to_id := String(path[i + 1])
		var ef := String(e.get("from", ""))
		var et := String(e.get("to", ""))
		var bidir := bool(e.get("bidirectional", false))
		if not ((ef == from_id and et == to_id) or (bidir and et == from_id and ef == to_id)):
			return false
	return true


func _min_by(cands: Array, field: String) -> float:
	var best := INF
	for raw in cands:
		best = minf(best, float((raw as Dictionary).get(field, INF)))
	return best


func _has_string(arr: Array, needle: String) -> bool:
	for raw in arr:
		if String(raw) == needle:
			return true
	return false


func _any_event(m, kind: String) -> bool:
	for raw in m.events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			return true
	return false


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	if txt.length() <= 2:
		return false
	var back = JSON.parse_string(txt)
	return back is Dictionary or back is Array


func _provider(source: String, node_id: String) -> Vector3:
	_provider_calls += 1
	return Vector3(111.0, 222.0, 333.0)


# ═══════════════════════════════════════════════════════════════════
# 1. 内容文件 / schema / 校验
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容文件 / schema / 校验")
	_ok(FileAccess.file_exists(CONTENT_PATH), "内容文件存在: " + CONTENT_PATH)
	var c := Nav.load_content()
	_ok(not c.is_empty(), "JSON 可解析且为 Dictionary")
	_eq(String(c.get("schema", "")), "navigation.v1", "schema=navigation.v1")
	_eq(String(c.get("id", "")), "navigation_l1", "id=navigation_l1")
	_ok(String(c.get("title", "")) != "", "title 非空")
	var nodes: Dictionary = c.get("nodes", {})
	_eq(nodes.size(), 8, "节点数 8")
	for nid in ["earth_port", "geo", "l1", "l2", "l4", "l5", "moon_port", "lunar_leo"]:
		_ok(nodes.has(nid), "含节点 " + nid)
	var n0: Dictionary = nodes.get("earth_port", {})
	_ok(String(n0.get("name", "")) != "", "Earth Port name 非空")
	_ok(String(n0.get("position_source", "")).begins_with("cislunar:"),
		"position_source 引用 cislunar", String(n0.get("position_source", "")))
	_ok(n0.get("abstract_pos_km") is Array and (n0.get("abstract_pos_km") as Array).size() == 3,
		"abstract_pos_km 为 3D 抽象坐标")
	var edges: Array = c.get("edges", [])
	_eq(edges.size(), 15, "边数 15")
	var e0: Dictionary = edges[0]
	for key in ["id", "from", "to", "transfer_type", "dv_ms", "duration_s", "exposure", "risk", "traffic_required"]:
		_ok(e0.has(key), "边字段 " + key)
	var rl: Dictionary = c.get("route_limits", {})
	_eq((rl.get("profiles", []) as Array).size(), 3, "route_limits 3 类 profile")
	_ok(rl.get("profile_weights") is Dictionary, "profile_weights 存在")
	var tr: Dictionary = c.get("traffic", {})
	_ok(int(tr.get("max_queue", 0)) >= 1, "traffic.max_queue ≥1")
	_ok((tr.get("priority_range", []) as Array).size() == 2, "traffic.priority_range 两点")
	_ok(not bool(tr.get("auto_grant", true)), "traffic.auto_grant=false")
	_ok(not bool(tr.get("auto_execute", true)), "traffic.auto_execute=false")
	var man: Dictionary = c.get("maneuvers", {})
	var kinds: Dictionary = man.get("kinds", {})
	_eq(kinds.size(), 6, "机动 kind 6 种")
	for kind in ["hold", "approach", "retreat", "evade", "point", "burn"]:
		_ok(kinds.has(kind), "含机动 kind " + kind)
	var order: Array = man.get("state_order", [])
	for st in ["PRE_ORDER", "AUTHORIZED", "QUEUED", "EXECUTING", "DONE", "ABORTED"]:
		_ok(order.has(st), "state_order 含 " + st)
	var budget: Dictionary = c.get("budget", {})
	_ok(float(budget.get("dv_total_ms", 0.0)) > 0.0, "budget.dv_total_ms > 0")
	_ok(float(budget.get("dv_reserve_ms", 0.0)) < float(budget.get("dv_total_ms", 0.0)),
		"budget.dv_reserve_ms < total")
	_eq(Nav.validate_content(c).size(), 0, "默认内容自检通过")
	_data_line("content", "nodes=%d edges=%d kinds=%d profiles=%s" % [
		nodes.size(), edges.size(), kinds.size(), str(rl.get("profiles", []))])

	# 篡改副本 → 校验必须报错
	var bad := _base_content()
	bad["schema"] = "wrong"
	_ok(Nav.validate_content(bad).size() > 0, "校验拒绝错误 schema")
	var bad2 := _base_content()
	bad2["nodes"] = {}
	_ok(Nav.validate_content(bad2).size() > 0, "校验拒绝空 nodes")
	var bad3 := _base_content()
	(bad3["edges"] as Array).append({"id": "e_bad_node", "from": "no_such", "to": "moon_port",
		"transfer_type": "high_thrust", "dv_ms": 1.0, "duration_s": 1.0,
		"exposure": 0.0, "risk": 0.0, "traffic_required": false})
	_ok(Nav.validate_content(bad3).size() > 0, "校验拒绝边引用未知节点")
	var bad4 := _base_content()
	(bad4["edges"] as Array).append((bad4["edges"] as Array)[0].duplicate(true))
	_ok(Nav.validate_content(bad4).size() > 0, "校验拒绝重复边 id")
	var bad5 := _base_content()
	(bad5["edges"] as Array)[0]["duration_s"] = 0.0
	_ok(Nav.validate_content(bad5).size() > 0, "校验拒绝 duration_s=0")
	var bad6 := _base_content()
	(bad6["edges"] as Array)[0]["exposure"] = 1.5
	_ok(Nav.validate_content(bad6).size() > 0, "校验拒绝 exposure>1")
	var bad7 := _base_content()
	(bad7["traffic"] as Dictionary)["priority_range"] = [5, 1]
	_ok(Nav.validate_content(bad7).size() > 0, "校验拒绝 priority_range 反序")
	var bad8 := _base_content()
	((bad8["maneuvers"] as Dictionary)["kinds"] as Dictionary).erase("burn")
	_ok(Nav.validate_content(bad8).size() > 0, "校验拒绝缺 maneuver kind")
	var bad9 := _base_content()
	(bad9["budget"] as Dictionary)["dv_total_ms"] = 0.0
	_ok(Nav.validate_content(bad9).size() > 0, "校验拒绝 budget=0")
	var bad10 := _base_content()
	((bad10["route_limits"] as Dictionary)["profiles"] as Array).erase("covert")
	_ok(Nav.validate_content(bad10).size() > 0, "校验拒绝缺 profile")
	var bad11 := _base_content()
	((bad11["nodes"] as Dictionary)["l1"] as Dictionary)["abstract_pos_km"] = [1.0, 2.0]
	_ok(Nav.validate_content(bad11).size() > 0, "校验拒绝非 3D 抽象坐标")
	var bad12 := _base_content()
	((bad12["maneuvers"] as Dictionary)["state_order"] as Array).erase("EXECUTING")
	_ok(Nav.validate_content(bad12).size() > 0, "校验拒绝缺 state")


# ═══════════════════════════════════════════════════════════════════
# 2. 初始化 / 节点
# ═══════════════════════════════════════════════════════════════════

func _test_setup_and_nodes() -> void:
	_section_begin("2 初始化 / 节点")
	var m = _fresh()
	_ok(bool(m.ready), "setup 成功 ready=true", str(m.errors))
	_eq(m.errors.size(), 0, "setup 无错误")
	_eq(m.nodes.size(), 8, "模型 nodes=8")
	_eq(m.edges.size(), 15, "模型 edges=15")
	_eq(m.content.get("id", ""), "navigation_l1", "content id")
	_ok(m.summary() is Dictionary, "summary 返回 Dictionary")
	_eq(int(m.summary().get("nodes", 0)), 8, "summary.nodes=8")
	_eq(int(m.summary().get("edges", 0)), 15, "summary.edges=15")
	_ok(m.node_position_km("l1").size() == 3, "L1 节点有 3D 抽象位置")
	var l1pos: Array = m.node_position_km("l1")
	_near(float(l1pos[0]), 326283.0, 1.0, "L1 抽象 x=326,283 km")
	_ok(m.node_position_km("unknown").is_empty(), "未知节点位置为空")
	_eq(Nav.node_ids(m.content).size(), 8, "静态 node_ids=8")
	_eq(Nav.list_nodes(m.content).size(), 8, "静态 list_nodes=8")
	# 未初始化模型的行为
	var empty = Nav.new()
	_ok(not bool(empty.ready), "未 setup 时 ready=false")
	_ok(not bool(empty.plan_routes("earth_port", "moon_port").get("ok", true)),
		"未初始化 plan_routes 返回失败")
	# 非法内容 setup 失败
	var bad := _base_content()
	(bad["budget"] as Dictionary)["dv_total_ms"] = 0.0
	var mbad = _new_nav(bad)
	_ok(not bool(mbad.ready), "非法内容 setup 失败")
	_ok(mbad.errors.size() > 0, "非法内容 errors 非空")


# ═══════════════════════════════════════════════════════════════════
# 3. 位置 provider（cislunar 接入点，只读）
# ═══════════════════════════════════════════════════════════════════

func _test_position_provider() -> void:
	_section_begin("3 位置 provider")
	var m = _fresh()
	var base: Array = m.node_position_km("l1")
	_provider_calls = 0
	m.bind_position_provider(Callable(self, "_provider"))
	var got: Array = m.node_position_km("l1")
	_eq(got.size(), 3, "provider 返回 3D")
	_near(float(got[0]), 111.0, 1.0e-6, "provider 覆盖 x")
	_near(float(got[2]), 333.0, 1.0e-6, "provider 覆盖 z")
	_eq(_provider_calls, 1, "provider 被调用 1 次")
	var positions: Dictionary = m.resolve_positions()
	_ok(positions.has("l1") and (positions["l1"] as Array).size() == 3, "resolve_positions 含 l1")
	m.clear_position_provider()
	var back: Array = m.node_position_km("l1")
	_near(float(back[0]), 326283.0, 1.0, "clear 后回退抽象坐标")
	_near(float(base[0]), 326283.0, 1.0, "原始抽象坐标一致")
	_data_line("provider", "位置 provider 可绑定/清除；只影响 node_position_km，不改内容")


# ═══════════════════════════════════════════════════════════════════
# 4. 路线候选（快速/经济/隐蔽）
# ═══════════════════════════════════════════════════════════════════

func _test_route_candidates() -> void:
	_section_begin("4 路线候选")
	var m = _fresh()
	var r: Dictionary = m.plan_routes("earth_port", "moon_port")
	_ok(bool(r.get("ok")), "plan_routes earth_port→moon_port 成功", str(r.get("reason", "")))
	var cands: Array = r.get("candidates", [])
	_eq(cands.size(), 3, "返回 3 类候选")
	_eq(_has_string(r.get("profiles", []), "fast"), true, "profiles 含 fast")
	if cands.size() == 3:
		var fast: Dictionary = cands[0]
		var econ: Dictionary = cands[1]
		var covert: Dictionary = cands[2]
		_eq(String(fast.get("profile", "")), "fast", "候选[0] profile=fast")
		_eq(String(econ.get("profile", "")), "economy", "候选[1] profile=economy")
		_eq(String(covert.get("profile", "")), "covert", "候选[2] profile=covert")
		_eq(int(fast.get("rank", 0)), 1, "fast rank=1")
		_eq(int(econ.get("rank", 0)), 2, "economy rank=2")
		_eq(int(covert.get("rank", 0)), 3, "covert rank=3")
		for raw in cands:
			var c: Dictionary = raw
			for key in ["candidate_id", "profile", "profile_label", "from", "to", "path", "edges",
					"transfer_types", "dv_ms", "duration_s", "exposure", "risk",
					"traffic_required", "feasible", "violations", "score"]:
				_ok(c.has(key), "%s 字段 %s" % [String(c.get("candidate_id", "")), key])
			_ok((c.get("path", []) as Array).size() >= 2, "候选路径至少 2 节点")
			_ok((c.get("edges", []) as Array).size() >= 1, "候选至少 1 条边")
			_ok(float(c.get("dv_ms", -1.0)) > 0.0, "候选 dv_ms > 0")
			_ok(float(c.get("duration_s", -1.0)) > 0.0, "候选 duration_s > 0")
			_ok(float(c.get("exposure", -1.0)) >= 0.0 and float(c.get("exposure", 2.0)) <= 1.0,
				"候选 exposure 0..1")
			_ok(float(c.get("risk", -1.0)) >= 0.0 and float(c.get("risk", 2.0)) <= 1.0,
				"候选 risk 0..1")
			_ok(_candidate_path_valid(m, c), "候选路径与边连通一致")
		# 快速 = 最短时间；经济 = 最小 Δv；隐蔽 = 最低暴露
		var fast_dur := float(fast.get("duration_s", INF))
		var econ_dur := float(econ.get("duration_s", INF))
		var covert_dur := float(covert.get("duration_s", INF))
		_ok(fast_dur <= econ_dur + 1.0e-6 and fast_dur <= covert_dur + 1.0e-6,
			"fast 候选时间最短", "fast=%.0f econ=%.0f covert=%.0f" % [fast_dur, econ_dur, covert_dur])
		var fast_dv := float(fast.get("dv_ms", INF))
		var econ_dv := float(econ.get("dv_ms", INF))
		var covert_dv := float(covert.get("dv_ms", INF))
		_ok(econ_dv <= fast_dv + 1.0e-6 and econ_dv <= covert_dv + 1.0e-6,
			"economy 候选 Δv 最小", "fast=%.0f econ=%.0f covert=%.0f" % [fast_dv, econ_dv, covert_dv])
		var fast_e := float(fast.get("exposure", 2.0))
		var econ_e := float(econ.get("exposure", 2.0))
		var covert_e := float(covert.get("exposure", 2.0))
		_ok(covert_e <= fast_e + 1.0e-6 and covert_e <= econ_e + 1.0e-6,
			"covert 候选暴露最低", "fast=%.3f econ=%.3f covert=%.3f" % [fast_e, econ_e, covert_e])
		_ok(_min_by(cands, "duration_s") == fast_dur, "候选集合最小时间=fast")
		_ok(_min_by(cands, "dv_ms") == econ_dv, "候选集合最小 Δv=economy")
		_ok(_min_by(cands, "exposure") == covert_e, "候选集合最小暴露=covert")
		_ok(String(r.get("recommended", "")) != "", "recommended 非空")
		_ok(m.last_routes.size() == 3, "last_routes 缓存 3 条")
		_data_line("routes", "fast=%.0f m/s/%.0f s · economy=%.0f m/s/%.0f s · covert=%.0f m/s/%.0f s" % [
			fast_dv, fast_dur, econ_dv, econ_dur, covert_dv, covert_dur])
	# 未知节点 / 同节点
	_ok(not bool(m.plan_routes("nope", "moon_port").get("ok", true)), "未知起点失败")
	_ok(not bool(m.plan_routes("earth_port", "nope").get("ok", true)), "未知终点失败")
	_ok(not bool(m.plan_routes("l1", "l1").get("ok", true)), "同节点失败")
	_data_line("routes.from_to", "earth_port→moon_port 3 类候选，路径可由边连通验证")


# ═══════════════════════════════════════════════════════════════════
# 5. 路线约束
# ═══════════════════════════════════════════════════════════════════

func _test_route_constraints() -> void:
	_section_begin("5 路线约束")
	var m = _fresh()
	var r_dv: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_dv_ms": 4000.0})
	var c_dv: Array = r_dv.get("candidates", [])
	var feas_dv := 0
	for raw in c_dv:
		if bool((raw as Dictionary).get("feasible", false)):
			feas_dv += 1
	_ok(feas_dv >= 1, "max_dv_ms=4000 至少 1 可行")
	var feas_dv_ok := true
	for raw2 in c_dv:
		var c2: Dictionary = raw2
		if bool(c2.get("feasible", false)) and float(c2.get("dv_ms", 0.0)) > 4000.0 + 1.0e-6:
			feas_dv_ok = false
	_ok(feas_dv_ok, "max_dv 4000 可行候选均不超限")
	var r_imp: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_dv_ms": 1.0})
	var viol_all := true
	for raw3 in (r_imp.get("candidates", []) as Array):
		var c3: Dictionary = raw3
		if bool(c3.get("feasible", true)) or not _has_string(c3.get("violations", []), "max_dv_ms"):
			viol_all = false
	_ok(viol_all, "max_dv=1 全部候选标记 max_dv_ms 违背")
	var r_time: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_duration_s": 60000.0})
	var fast_time_feas := false
	for raw4 in (r_time.get("candidates", []) as Array):
		var c4: Dictionary = raw4
		if String(c4.get("profile", "")) == "fast" and bool(c4.get("feasible", false)):
			fast_time_feas = true
	_ok(fast_time_feas, "max_duration 60,000 s 下 fast 可行")
	var r_expo: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_exposure": 0.30})
	var expo_ok := true
	for raw5 in (r_expo.get("candidates", []) as Array):
		var c5: Dictionary = raw5
		if bool(c5.get("feasible", false)) and float(c5.get("exposure", 2.0)) > 0.30 + 1.0e-6:
			expo_ok = false
	_ok(expo_ok, "max_exposure=0.30 可行候选均不超限")
	var r_traffic: Dictionary = m.plan_routes("earth_port", "moon_port", {"avoid_traffic": true})
	var traffic_ok := true
	for raw6 in (r_traffic.get("candidates", []) as Array):
		var c6: Dictionary = raw6
		if bool(c6.get("feasible", false)) and bool(c6.get("traffic_required", true)):
			traffic_ok = false
	_ok(traffic_ok, "avoid_traffic 可行候选均不需交通许可")
	var r_excl: Dictionary = m.plan_routes("earth_port", "moon_port",
		{"exclude_transfer_types": ["low_energy"]})
	var excl_ok := true
	for raw7 in (r_excl.get("candidates", []) as Array):
		var c7: Dictionary = raw7
		if bool(c7.get("feasible", false)) and _has_string(c7.get("transfer_types", []), "low_energy"):
			excl_ok = false
	_ok(excl_ok, "exclude low_energy 可行候选均不使用该类型")
	var r_hops: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_hops": 1})
	var hops_c: Array = r_hops.get("candidates", [])
	_ok(hops_c.size() <= 3 and hops_c.size() >= 1, "max_hops=1 返回 ≤3 条候选")
	var hops_ok := true
	for raw8 in hops_c:
		if int((raw8 as Dictionary).get("hops", 99)) > 1:
			hops_ok = false
	_ok(hops_ok, "max_hops=1 候选跳数 ≤1")
	_ok(add_constraint_present(r_dv), "约束回显 constraints 字段")
	_data_line("constraints", "max_dv/max_duration/max_exposure/avoid_traffic/exclude_type/max_hops 均生效")


func add_constraint_present(r: Dictionary) -> bool:
	return r.get("constraints") is Dictionary and not (r.get("constraints") as Dictionary).is_empty()


# ═══════════════════════════════════════════════════════════════════
# 6. 路线规划无副作用（无自动执行）
# ═══════════════════════════════════════════════════════════════════

func _test_route_no_execution() -> void:
	_section_begin("6 规划无自动执行")
	var m = _fresh()
	var sig0: String = m.state_signature()
	var budget0: Dictionary = m.budget_vm()
	var t0 = m.t
	var cands_before = m.planned_maneuvers.size()
	m.plan_routes("earth_port", "moon_port")
	_eq(m.t, t0, "plan_routes 不改时间")
	_near(float(m.budget_vm().get("dv_used_ms", -1.0)), float(budget0.get("dv_used_ms", 0.0)),
		1.0e-6, "plan_routes 不改已用 Δv")
	_eq(m.planned_maneuvers.size(), cands_before, "plan_routes 不创建机动")
	_eq(m.state_signature(), sig0, "plan_routes 不改执行状态签名")
	var r: Dictionary = m.plan_routes("earth_port", "moon_port")
	var fast: Dictionary = (r.get("candidates", []) as Array)[0]
	m.select_route(fast.get("candidate_id", ""))
	_eq(m.t, t0, "select_route 不改时间")
	_eq(m.planned_maneuvers.size(), cands_before, "select_route 不创建机动")
	_eq(String(m.selected_route.get("candidate_id", "")), String(fast.get("candidate_id", "")),
		"selected_route 更新")
	_ok(m.plan_routes("earth_port", "moon_port").get("candidates", []) is Array,
		"重复规划仍返回候选")
	_data_line("no-exec", "规划/选择路线不产生机动、不耗预算、不改时间")

# ═══════════════════════════════════════════════════════════════════
# 7. 交通许可基础
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_basic() -> void:
	_section_begin("7 交通许可基础")
	var m = _fresh()
	var r: Dictionary = m.plan_routes("earth_port", "moon_port")
	var cands: Array = r.get("candidates", [])
	var fast: Dictionary = cands[0]
	var econ: Dictionary = cands[1]
	var covert: Dictionary = cands[2]
	var req_fast: Dictionary = m.request_clearance(fast, {}, 3)
	_eq(String(req_fast.get("status", "")), "hold", "高暴露 fast → hold")
	_ok(bool(req_fast.get("ok", false)), "hold 请求返回 ok=true")
	_eq(int(req_fast.get("position", 0)), 1, "hold 队列位置 1")
	_eq(m.queue.size(), 1, "队列长度 1")
	var rec_fast: Dictionary = m.clearance_status(String(req_fast.get("request_id", "")))
	_eq(String(rec_fast.get("status", "")), "hold", "请求记录 status=hold")
	_ok(String(rec_fast.get("reason", "")) == "exposure_review", "hold 原因 exposure_review")
	_ok((rec_fast.get("window", {}) as Dictionary).has("open_t"), "许可带时间窗")
	var req_econ: Dictionary = m.request_clearance(econ, {}, 3)
	_eq(String(req_econ.get("status", "")), "granted", "低暴露 economy → granted")
	_ok(float(req_econ.get("expires_t", -1.0)) > m.t, "granted 有有效期")
	_eq(m.active_clearances().size(), 1, "1 个活动许可")
	_eq(String(m.active_clearance().get("id", "")), String(req_econ.get("request_id", "")),
		"active_clearance 返回最近批准")
	var req_covert: Dictionary = m.request_clearance(covert, {}, 3)
	_eq(String(req_covert.get("status", "")), "granted", "covert（无需交通）→ granted")
	_eq(String(req_covert.get("reason", "")), "traffic_not_required", "无需许可路由 reason=traffic_not_required")
	_ok(m.requests.size() == 3, "requests 记录 3 条")
	_ok(_any_event(m, "clearance_granted"), "事件含 clearance_granted")
	_ok(_any_event(m, "clearance_hold"), "事件含 clearance_hold")
	_ok(JSON.stringify(m.vm_navigation().get("clearance", {})).length() > 10, "vm.clearance 可序列化")
	_data_line("traffic", "fast=hold · economy=granted · covert=granted（traffic_not_required）")


# ═══════════════════════════════════════════════════════════════════
# 8. 优先级队列
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_queue_priority() -> void:
	_section_begin("8 优先级队列")
	var m = _fresh()
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	var fast: Dictionary = cands[0]
	var a: Dictionary = m.request_clearance(fast, {}, 3)
	var b: Dictionary = m.request_clearance(fast, {}, 1)
	var c: Dictionary = m.request_clearance(fast, {}, 4)
	_eq(m.queue.size(), 3, "队列 3 条")
	_eq(String(m.queue[0]), String(b.get("request_id", "")), "队列首 = 优先级 1")
	_eq(String(m.queue[1]), String(a.get("request_id", "")), "队列次 = 优先级 3")
	_eq(String(m.queue[2]), String(c.get("request_id", "")), "队列尾 = 优先级 4")
	var vmq: Array = m.vm_navigation().get("queue", [])
	_eq(vmq.size(), 3, "vm.queue 3 条")
	_eq(int((vmq[0] as Dictionary).get("position", 0)), 1, "vm.queue[0].position=1")
	_eq(String((vmq[0] as Dictionary).get("priority_label", "")), "EMERGENCY", "priority 1 标签 EMERGENCY")
	_ok(int((vmq[2] as Dictionary).get("priority", 0)) == 4, "队列末优先级 4")
	var rec_b: Dictionary = m.clearance_status(String(b.get("request_id", "")))
	_eq(int(rec_b.get("queue_position", 0)), 1, "record.queue_position=1")
	_data_line("queue", "priority 1 → 3 → 4（先进先出 + 优先级）")


# ═══════════════════════════════════════════════════════════════════
# 9. 拒绝原因
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_denials() -> void:
	_section_begin("9 拒绝原因")
	var m = _fresh()
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	var fast: Dictionary = cands[0]
	var econ: Dictionary = cands[1]
	# 优先级越界
	var p0: Dictionary = m.request_clearance(econ, {}, 0)
	_eq(String(p0.get("status", "")), "denied", "priority 0 → denied")
	_eq(String(p0.get("reason", "")), "priority_range", "priority 0 原因 priority_range")
	var p6: Dictionary = m.request_clearance(econ, {}, 6)
	_eq(String(p6.get("reason", "")), "priority_range", "priority 6 原因 priority_range")
	# 时间窗
	var w1: Dictionary = m.request_clearance(econ, {"open_t": m.t - 5.0, "close_t": m.t + 100.0}, 3)
	_eq(String(w1.get("reason", "")), "window_in_past", "过去窗口 → window_in_past")
	var w2: Dictionary = m.request_clearance(econ, {"open_t": m.t + 10.0, "close_t": m.t + 20.0}, 3)
	_eq(String(w2.get("reason", "")), "window_closed", "过近窗口 → window_closed")
	# 未知路线 / 未选择
	var unk: Dictionary = m.request_clearance("RTE-9999")
	_eq(String(unk.get("reason", "")), "unknown_route", "未知路线 → unknown_route")
	# 不可行路线
	var r_bad: Dictionary = m.plan_routes("earth_port", "moon_port", {"max_dv_ms": 1.0})
	var bad_cand: Dictionary = {}
	for raw in (r_bad.get("candidates", []) as Array):
		if not bool((raw as Dictionary).get("feasible", true)):
			bad_cand = raw
			break
	_ok(not bad_cand.is_empty(), "取到不可行候选（max_dv=1）")
	if not bad_cand.is_empty():
		_ok(not bool(bad_cand.get("feasible", true)), "候选 feasible=false")
		var inf: Dictionary = m.request_clearance(bad_cand, {}, 2)
		_eq(String(inf.get("reason", "")), "route_infeasible", "不可行路线 → route_infeasible")
	_ok(_any_event(m, "clearance_denied"), "事件含 clearance_denied")
	_data_line("denials", "priority_range / window_in_past / window_closed / unknown_route / route_infeasible")


# ═══════════════════════════════════════════════════════════════════
# 10. 管制员手动动作
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_manual_actions() -> void:
	_section_begin("10 管制员手动动作")
	# grant
	var m1 = _fresh()
	var c1: Array = m1.plan_routes("earth_port", "moon_port").get("candidates", [])
	var fast1: Dictionary = c1[0]
	var hold1: Dictionary = m1.request_clearance(fast1, {}, 2)
	_eq(m1.queue.size(), 1, "手动 grant 前队列 1")
	var g: Dictionary = m1.grant_clearance(String(hold1.get("request_id", "")))
	_eq(String(g.get("status", "")), "granted", "grant_clearance → granted")
	_eq(m1.queue.size(), 0, "批准后队列清空")
	_eq(m1.active_clearances().size(), 1, "批准后 1 个活动许可")
	var g2: Dictionary = m1.grant_clearance(String(hold1.get("request_id", "")))
	_ok(not bool(g2.get("ok", true)), "重复批准失败")
	# deny
	var m2 = _fresh()
	var c2: Array = m2.plan_routes("earth_port", "moon_port").get("candidates", [])
	var hold2: Dictionary = m2.request_clearance(c2[0], {}, 3)
	var d: Dictionary = m2.deny_clearance(String(hold2.get("request_id", "")), "authority_denied")
	_eq(String(d.get("status", "")), "denied", "deny_clearance → denied")
	_eq(String(d.get("reason", "")), "authority_denied", "拒绝原因 authority_denied")
	_eq(m2.queue.size(), 0, "拒绝后队列清空")
	var d2: Dictionary = m2.deny_clearance(String(hold2.get("request_id", "")))
	_ok(not bool(d2.get("ok", true)), "重复拒绝失败")
	# hold（对 hold 状态再延长）
	var m3 = _fresh()
	var c3: Array = m3.plan_routes("earth_port", "moon_port").get("candidates", [])
	var hold3: Dictionary = m3.request_clearance(c3[0], {}, 3)
	var h: Dictionary = m3.hold_clearance(String(hold3.get("request_id", "")), m3.t + 900.0)
	_eq(String(h.get("status", "")), "hold", "hold_clearance → hold")
	_near(float(h.get("hold_until_t", 0.0)), 900.0, 1.0e-6, "hold_until_t=900")
	var rec3: Dictionary = m3.clearance_status(String(hold3.get("request_id", "")))
	_near(float(rec3.get("hold_until_t", 0.0)), 900.0, 1.0e-6, "记录 hold_until_t=900")
	var unk: Dictionary = m3.grant_clearance("CLR-9999")
	_ok(not bool(unk.get("ok", true)), "grant 未知请求失败")
	_data_line("manual", "grant/deny/hold 均不自动执行机动")


# ═══════════════════════════════════════════════════════════════════
# 11. 许可过期
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_expiry() -> void:
	_section_begin("11 许可过期")
	# hold 过期
	var m1 = _fresh()
	var c1: Array = m1.plan_routes("earth_port", "moon_port").get("candidates", [])
	var hold1: Dictionary = m1.request_clearance(c1[0], {}, 3)
	_eq(m1.queue.size(), 1, "hold 入队")
	var step1: Dictionary = m1.step(601.0)
	_eq(String(m1.clearance_status(String(hold1.get("request_id", ""))).get("status", "")), "expired",
		"hold 超时 → expired")
	_eq(m1.queue.size(), 0, "hold 过期后队列清空")
	_ok(_any_event(m1, "clearance_expired"), "事件含 clearance_expired")
	_ok(step1.get("t", 0.0) != null, "step 返回 t")
	# granted 过期
	var m2 = _fresh()
	var c2: Array = m2.plan_routes("earth_port", "moon_port").get("candidates", [])
	var granted: Dictionary = m2.request_clearance(c2[1], {}, 3)
	_eq(String(granted.get("status", "")), "granted", "economy 批准")
	_eq(m2.active_clearances().size(), 1, "过期前活动许可 1")
	m2.step(1801.0)
	_eq(m2.active_clearances().size(), 0, "granted 超时 → 无活动许可")
	_eq(String(m2.clearance_status(String(granted.get("request_id", ""))).get("status", "")), "expired",
		"granted 记录 expired")
	_eq(m2.expire_clearances().size(), 0, "重复过期无新增")
	_data_line("expiry", "hold_until/validity 到期 → expired，队列移除")


# ═══════════════════════════════════════════════════════════════════
# 12. 队列容量
# ═══════════════════════════════════════════════════════════════════

func _test_traffic_queue_full() -> void:
	_section_begin("12 队列容量")
	var content := _base_content()
	(content["traffic"] as Dictionary)["max_queue"] = 1
	var m = _new_nav(content)
	_ok(bool(m.ready), "max_queue=1 内容 setup 成功", str(m.errors))
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	var fast: Dictionary = cands[0]
	var first: Dictionary = m.request_clearance(fast, {}, 3)
	_eq(String(first.get("status", "")), "hold", "第一条 hold 入队")
	var second: Dictionary = m.request_clearance(fast, {}, 2)
	_eq(String(second.get("reason", "")), "queue_full", "队列满 → queue_full")
	_eq(m.queue.size(), 1, "队列仍为 1")
	_data_line("queue_full", "max_queue=1：第二条请求被拒绝且不占队列")


# ═══════════════════════════════════════════════════════════════════
# 13. 机动计划
# ═══════════════════════════════════════════════════════════════════

func _test_maneuver_planning() -> void:
	_section_begin("13 机动计划")
	var m = _fresh()
	var hold: Dictionary = m.plan_maneuver("hold")
	_ok(bool(hold.get("ok", false)), "plan hold 成功")
	var hid := String(hold.get("plan_id", ""))
	_ok(hid.begins_with("MNV-"), "plan_id 形如 MNV-xxxx")
	var approach: Dictionary = m.plan_maneuver("approach", "moon_port")
	_ok(bool(approach.get("ok", false)), "plan approach(target) 成功")
	var approach_bad: Dictionary = m.plan_maneuver("approach")
	_eq(String(approach_bad.get("reason", "")), "target_required", "approach 缺 target → target_required")
	var point_bad: Dictionary = m.plan_maneuver("point")
	_eq(String(point_bad.get("reason", "")), "target_required", "point 缺 target → target_required")
	var retreat: Dictionary = m.plan_maneuver("retreat")
	_ok(bool(retreat.get("ok", false)), "plan retreat 成功")
	var evade: Dictionary = m.plan_maneuver("evade")
	_ok(bool(evade.get("ok", false)), "plan evade 成功")
	var burn: Dictionary = m.plan_maneuver("burn", "", {"dv_ms": 120.0})
	_ok(bool(burn.get("ok", false)), "plan burn(dv=120) 成功")
	var burn_plan: Dictionary = burn.get("plan", {})
	_near(float(burn_plan.get("dv_ms", 0.0)), 120.0, 1.0e-6, "burn opts.dv_ms 覆盖为 120")
	var hold_plan: Dictionary = hold.get("plan", {})
	_near(float(hold_plan.get("dv_ms", 0.0)), 40.0, 1.0e-6, "hold 默认 Δv=40")
	_eq(String(hold_plan.get("state", "")), "PRE_ORDER", "新计划 state=PRE_ORDER")
	_eq(m.planned_maneuvers.size(), 5, "已计划 5 个机动（失败计划不入列）")
	var unk: Dictionary = m.plan_maneuver("teleport")
	_eq(String(unk.get("reason", "")), "unknown_kind", "未知 kind → unknown_kind")
	_data_line("maneuvers.plan", "hold/approach/retreat/evade/point/burn；缺 target/未知 kind 拒绝")


# ═══════════════════════════════════════════════════════════════════
# 14. 机动状态机
# ═══════════════════════════════════════════════════════════════════

func _test_maneuver_state_machine() -> void:
	_section_begin("14 机动状态机")
	var m = _fresh()
	var p: Dictionary = m.plan_maneuver("hold")
	var pid := String(p.get("plan_id", ""))
	var auth: Dictionary = m.authorize_maneuver(pid)
	_eq(String(auth.get("state", "")), "AUTHORIZED", "authorize → AUTHORIZED")
	_near(float(auth.get("reserved_ms", 0.0)), 40.0, 1.0e-6, "authorize 预留 40 m/s")
	_near(float(m.dv_committed_ms), 40.0, 1.0e-6, "committed=40")
	var q: Dictionary = m.queue_maneuver(pid)
	_eq(String(q.get("state", "")), "QUEUED", "queue → QUEUED")
	var e: Dictionary = m.execute_maneuver(pid)
	_eq(String(e.get("state", "")), "EXECUTING", "execute → EXECUTING")
	var st1: Dictionary = m.step(60.0)
	_eq(int((st1.get("done", []) as Array).size()), 0, "60 s 未完成")
	var plan_now: Dictionary = m._plan_by_id(pid)
	_near(float(plan_now.get("progress", 0.0)), 0.5, 1.0e-6, "progress=0.5")
	var st2: Dictionary = m.step(60.1)
	_eq(int((st2.get("done", []) as Array).size()), 1, "120 s 完成 1 个")
	var done_plan: Dictionary = m._plan_by_id(pid)
	_eq(String(done_plan.get("state", "")), "DONE", "终态 DONE")
	_near(float(done_plan.get("consumed_ms", 0.0)), 40.0, 1.0e-6, "消耗 40 m/s")
	_near(m.dv_used_ms, 40.0, 1.0e-6, "used=40")
	_near(m.dv_committed_ms, 0.0, 1.0e-6, "committed 归零")
	_near(m.available_dv_ms(), 1460.0, 1.0e-6, "available=1460")
	# 非法迁移
	var p2: Dictionary = m.plan_maneuver("hold")
	var p2id := String(p2.get("plan_id", ""))
	var q_before_auth: Dictionary = m.queue_maneuver(p2id)
	_eq(String(q_before_auth.get("reason", "")), "wrong_state", "未授权 queue → wrong_state")
	var e_before_queue: Dictionary = m.execute_maneuver(p2id)
	_eq(String(e_before_queue.get("reason", "")), "wrong_state", "未排队 execute → wrong_state")
	m.authorize_maneuver(p2id)
	var auth2: Dictionary = m.authorize_maneuver(p2id)
	_eq(String(auth2.get("reason", "")), "wrong_state", "重复授权 → wrong_state")
	var done_plan2: Dictionary = m._plan_by_id(pid)
	_ok(not bool(done_plan2.is_empty()), "已有机动计划可查询")
	var abort_done: Dictionary = m.abort_maneuver(pid)
	_eq(String(abort_done.get("reason", "")), "wrong_state", "DONE 后 abort → wrong_state")
	_ok(_any_event(m, "maneuver_done"), "事件含 maneuver_done")
	_data_line("maneuver.fsm", "PRE_ORDER→AUTHORIZED→QUEUED→EXECUTING→DONE，非法迁移拒绝")


# ═══════════════════════════════════════════════════════════════════
# 15. 机动中断
# ═══════════════════════════════════════════════════════════════════

func _test_maneuver_abort() -> void:
	_section_begin("15 机动中断")
	# 排队中中断：无消耗
	var m = _fresh()
	var p: Dictionary = m.plan_maneuver("hold")
	var pid := String(p.get("plan_id", ""))
	m.authorize_maneuver(pid)
	m.queue_maneuver(pid)
	var ab: Dictionary = m.abort_maneuver(pid, "commander_abort")
	_eq(String(ab.get("state", "")), "ABORTED", "排队中 abort → ABORTED")
	_near(float(ab.get("consumed_ms", -1.0)), 0.0, 1.0e-6, "排队中中断无消耗")
	_near(m.dv_used_ms, 0.0, 1.0e-6, "used 仍 0")
	_near(m.dv_committed_ms, 0.0, 1.0e-6, "committed 释放")
	# 执行中中断：按进度部分消耗
	var m2 = _fresh()
	var p2: Dictionary = m2.plan_maneuver("hold")
	var pid2 := String(p2.get("plan_id", ""))
	m2.authorize_maneuver(pid2)
	m2.queue_maneuver(pid2)
	m2.execute_maneuver(pid2)
	m2.step(60.0)   # 120 s 的一半
	var ab2: Dictionary = m2.abort_maneuver(pid2, "tactical_abort")
	_eq(String(ab2.get("state", "")), "ABORTED", "执行中 abort → ABORTED")
	_near(float(ab2.get("consumed_ms", 0.0)), 20.0, 1.0e-6, "执行 50% → 消耗 20 m/s")
	_near(m2.dv_used_ms, 20.0, 1.0e-6, "used=20")
	_near(m2.dv_committed_ms, 0.0, 1.0e-6, "committed 释放")
	_ok(_any_event(m2, "maneuver_aborted"), "事件含 maneuver_aborted")
	var plan_ab: Dictionary = m2._plan_by_id(pid2)
	_eq(String(plan_ab.get("abort_reason", "")), "tactical_abort", "abort_reason 记录")
	_data_line("maneuver.abort", "排队中断 0 消耗；执行中断按 progress 部分消耗")


# ═══════════════════════════════════════════════════════════════════
# 16. 机动需要交通许可
# ═══════════════════════════════════════════════════════════════════

func _test_maneuver_clearance() -> void:
	_section_begin("16 机动 × 交通许可")
	var m = _fresh()
	var burn: Dictionary = m.plan_maneuver("burn", "", {"dv_ms": 84.0})
	var bid := String(burn.get("plan_id", ""))
	m.authorize_maneuver(bid)
	var q_no: Dictionary = m.queue_maneuver(bid)
	_eq(String(q_no.get("reason", "")), "clearance_required", "无许可 queue burn → clearance_required")
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	var clr: Dictionary = m.request_clearance(cands[1], {}, 3)
	_eq(String(clr.get("status", "")), "granted", "economy 许可 granted")
	var q_ok: Dictionary = m.queue_maneuver(bid, String(clr.get("request_id", "")))
	_eq(String(q_ok.get("state", "")), "QUEUED", "带许可 queue 成功")
	m.execute_maneuver(bid)
	var st: Dictionary = m.step(90.1)
	_eq(int((st.get("done", []) as Array).size()), 1, "burn 完成")
	_near(m.dv_used_ms, 84.0, 1.0e-6, "burn 消耗 84 m/s")
	var rec: Dictionary = m.clearance_status(String(clr.get("request_id", "")))
	_ok(not rec.is_empty(), "许可记录可查")
	# 许可过期后 queue 失败
	var m2 = _fresh()
	var burn2: Dictionary = m2.plan_maneuver("evade")
	var eid := String(burn2.get("plan_id", ""))
	m2.authorize_maneuver(eid)
	var cands2: Array = m2.plan_routes("earth_port", "moon_port").get("candidates", [])
	var clr2: Dictionary = m2.request_clearance(cands2[1], {}, 3)
	m2.step(1801.0)
	var q_stale: Dictionary = m2.queue_maneuver(eid, String(clr2.get("request_id", "")))
	_eq(String(q_stale.get("reason", "")), "clearance_required", "许可过期后 queue → clearance_required")
	_data_line("maneuver.clearance", "burn/evade 必须持有效 granted 许可；过期许可失效")


# ═══════════════════════════════════════════════════════════════════
# 17. Δv 预算
# ═══════════════════════════════════════════════════════════════════

func _test_maneuver_budget() -> void:
	_section_begin("17 Δv 预算")
	var m = _fresh()
	_near(m.budget_total_ms(), 1600.0, 1.0e-6, "total=1600")
	_near(m.budget_reserve_ms(), 100.0, 1.0e-6, "reserve=100")
	_near(m.available_dv_ms(), 1500.0, 1.0e-6, "available=1500")
	var p1: Dictionary = m.plan_maneuver("hold")
	m.authorize_maneuver(String(p1.get("plan_id", "")))
	_near(m.available_dv_ms(), 1460.0, 1.0e-6, "授权 40 → available 1460")
	var p2: Dictionary = m.plan_maneuver("hold")
	m.authorize_maneuver(String(p2.get("plan_id", "")))
	_near(m.available_dv_ms(), 1420.0, 1.0e-6, "再授权 40 → available 1420")
	var budget: Dictionary = m.budget_vm()
	_ok(float(budget.get("dv_committed_ms", 0.0)) >= 80.0, "budget.committed 累计")
	_ok(not bool(budget.get("warning", true)), "80/1500 未到 warn 阈值")
	# 小预算内容：授权到不足
	var content := _base_content()
	(content["budget"] as Dictionary)["dv_total_ms"] = 100.0
	(content["budget"] as Dictionary)["dv_reserve_ms"] = 0.0
	var small = _new_nav(content)
	_ok(bool(small.ready), "小预算内容 setup 成功")
	var a1: Dictionary = small.plan_maneuver("hold")
	_ok(bool(small.authorize_maneuver(String(a1.get("plan_id", ""))).get("ok", false)),
		"小预算第 1 次授权成功")
	var a2: Dictionary = small.plan_maneuver("hold")
	_ok(bool(small.authorize_maneuver(String(a2.get("plan_id", ""))).get("ok", false)),
		"小预算第 2 次授权成功")
	var a3: Dictionary = small.plan_maneuver("hold")
	var a3r: Dictionary = small.authorize_maneuver(String(a3.get("plan_id", "")))
	_eq(String(a3r.get("reason", "")), "dv_budget", "第 3 次授权 → dv_budget")
	_near(small.available_dv_ms(), 20.0, 1.0e-6, "小预算 available=20")
	# burn 大 Δv 覆盖并超过预算
	var m2 = _fresh()
	var big: Dictionary = m2.plan_maneuver("burn", "", {"dv_ms": 5000.0})
	var big_plan: Dictionary = big.get("plan", {})
	_near(float(big_plan.get("dv_ms", 0.0)), 1600.0, 1.0e-6, "burn Δv clamp 到 total=1600")
	var big_auth: Dictionary = m2.authorize_maneuver(String(big.get("plan_id", "")))
	_eq(String(big_auth.get("reason", "")), "dv_budget", "超预算 burn 授权失败")
	_data_line("budget", "total=1600 reserve=100；授权预留、执行消耗；不足拒绝")


# ═══════════════════════════════════════════════════════════════════
# 18. vm_navigation / JSON
# ═══════════════════════════════════════════════════════════════════

func _test_vm_and_json() -> void:
	_section_begin("18 vm_navigation / JSON")
	var m = _fresh()
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	m.select_route(cands[1].get("candidate_id", ""))
	var fast: Dictionary = cands[0]
	var econ: Dictionary = cands[1]
	m.request_clearance(fast, {}, 3)     # hold → queue
	m.request_clearance(econ, {}, 3)     # granted
	var hold: Dictionary = m.plan_maneuver("hold")
	m.authorize_maneuver(String(hold.get("plan_id", "")))
	var vm: Dictionary = m.vm_navigation()
	for key in ["schema", "id", "ready", "t", "nodes", "routes", "selected", "clearance",
			"clearances", "queue", "planned_maneuvers", "budget", "limits", "events", "summary"]:
		_ok(vm.has(key), "vm 字段 " + key)
	_eq((vm.get("nodes", []) as Array).size(), 8, "vm.nodes=8")
	_eq((vm.get("routes", []) as Array).size(), 3, "vm.routes=3")
	_eq(String((vm.get("selected", {}) as Dictionary).get("candidate_id", "")),
		String(cands[1].get("candidate_id", "")), "vm.selected 为选中候选")
	_ok((vm.get("clearance", {}) as Dictionary).has("id"), "vm.clearance 有活动许可")
	_eq((vm.get("queue", []) as Array).size(), 1, "vm.queue=1（hold）")
	_eq((vm.get("planned_maneuvers", []) as Array).size(), 1, "vm.planned_maneuvers=1")
	var bvm: Dictionary = vm.get("budget", {})
	for bkey in ["dv_total_ms", "dv_reserve_ms", "dv_used_ms", "dv_committed_ms", "dv_available_ms"]:
		_ok(bvm.has(bkey), "vm.budget." + bkey)
	var lim: Dictionary = vm.get("limits", {})
	for lkey in ["max_hops", "max_queue", "priority_range", "profiles", "maneuver_states"]:
		_ok(lim.has(lkey), "vm.limits." + lkey)
	_ok((vm.get("events", []) as Array).size() > 0, "vm.events 非空")
	_ok((vm.get("summary", {}) as Dictionary).has("nodes"), "vm.summary 有 nodes")
	_ok(_json_ok(vm), "vm JSON 可序列化/回读")
	var txt := JSON.stringify(vm)
	_ok(txt.find("RTE-") >= 0, "JSON 含 candidate id")
	_ok(txt.find("\"schema\":\"navigation.v1\"") >= 0 or txt.find("navigation.v1") >= 0,
		"JSON 含 schema")
	var man_rows: Array = vm.get("planned_maneuvers", [])
	_eq(String((man_rows[0] as Dictionary).get("state", "")), "AUTHORIZED", "vm 机动状态 AUTHORIZED")
	_data_line("vm", "nodes=8 routes=3 queue=1 maneuvers=1 budget/limits/events 完整 JSON")


# ═══════════════════════════════════════════════════════════════════
# 19. 只读 / 无物理副作用
# ═══════════════════════════════════════════════════════════════════

func _test_readonly_and_no_physics() -> void:
	_section_begin("19 只读 / 无物理副作用")
	var m = _fresh()
	var pos_before: Dictionary = m.resolve_positions()
	var sig0: String = m.state_signature()
	var vm1: Dictionary = m.vm_navigation()
	(vm1["budget"] as Dictionary)["dv_total_ms"] = 9999.0
	(vm1["routes"] as Array).clear()
	var vm2: Dictionary = m.vm_navigation()
	_near(float((vm2.get("budget", {}) as Dictionary).get("dv_total_ms", 0.0)), 1600.0, 1.0e-6,
		"修改 vm 不影响模型 budget")
	_eq((vm2.get("routes", []) as Array).size(), 0, "vm 返回新副本（routes 原为空）")
	_eq(m.state_signature(), sig0, "vm 调用不改状态签名")
	# 规划/许可/机动不改节点位置
	m.plan_routes("earth_port", "moon_port")
	var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
	m.select_route(cands[0].get("candidate_id", ""))
	m.request_clearance(cands[0], {}, 2)
	var hold: Dictionary = m.plan_maneuver("hold")
	m.authorize_maneuver(String(hold.get("plan_id", "")))
	var pos_after: Dictionary = m.resolve_positions()
	_eq(str(pos_before), str(pos_after), "规划/许可/授权不改变节点位置（无物理）")
	_ok(m.position_provider.is_valid() == false, "默认无 position provider")
	# provider 不被规划流程调用（只有 node_position_km/vm 会调）
	var m2 = _fresh()
	_provider_calls = 0
	m2.bind_position_provider(Callable(self, "_provider"))
	m2.plan_routes("earth_port", "moon_port")
	m2.plan_maneuver("hold")
	_eq(_provider_calls, 0, "规划流程不调用 position provider（不改几何）")
	_data_line("readonly", "vm 返回副本；规划/许可/授权不改位置/预算/时间")


# ═══════════════════════════════════════════════════════════════════
# 20. 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("20 确定性")
	var a = _fresh()
	var b = _fresh()
	for m in [a, b]:
		var cands: Array = m.plan_routes("earth_port", "moon_port").get("candidates", [])
		m.select_route(cands[1].get("candidate_id", ""))
		m.request_clearance(cands[1], {}, 3)
		var hold: Dictionary = m.plan_maneuver("hold")
		m.authorize_maneuver(String(hold.get("plan_id", "")))
		m.queue_maneuver(String(hold.get("plan_id", "")))
		m.execute_maneuver(String(hold.get("plan_id", "")))
		m.step(121.0)
	var ja := JSON.stringify(a.vm_navigation())
	var jb := JSON.stringify(b.vm_navigation())
	_ok(ja == jb, "相同序列 → 相同 vm JSON（确定性）")
	_eq(a.state_signature(), b.state_signature(), "相同状态签名")
	_eq(a.requests.size(), b.requests.size(), "相同请求数")
	_data_line("determinism", "两次独立运行路线/许可/机动/预算完全一致")


# ═══════════════════════════════════════════════════════════════════
# 21. 内容驱动
# ═══════════════════════════════════════════════════════════════════

func _test_content_driven() -> void:
	_section_begin("21 内容驱动")
	var content := _base_content()
	(content["nodes"] as Dictionary)["l1"]["name"] = "自定义 L1 名称"
	(content["nodes"] as Dictionary)["l1"]["abstract_pos_km"] = [1.0, 2.0, 3.0]
	(content["edges"] as Array)[0]["dv_ms"] = 123.0
	(content["budget"] as Dictionary)["dv_total_ms"] = 500.0
	(content["budget"] as Dictionary)["dv_reserve_ms"] = 20.0
	((content["maneuvers"] as Dictionary)["kinds"] as Dictionary)["hold"]["dv_ms"] = 7.0
	(content["traffic"] as Dictionary)["max_queue"] = 2
	var m = _new_nav(content)
	_ok(bool(m.ready), "内容驱动 setup 成功", str(m.errors))
	_eq(String((m.nodes["l1"] as Dictionary).get("name", "")), "自定义 L1 名称", "节点名称来自内容")
	_near(float((m.nodes["l1"] as Dictionary).get("abstract_pos_km", Vector3.ZERO).x), 1.0,
		1.0e-6, "节点抽象坐标来自内容")
	_near(float(_edge_by_id(m, String((content["edges"] as Array)[0]["id"])).get("dv_ms", 0.0)),
		123.0, 1.0e-6, "边 Δv 来自内容")
	_near(m.budget_total_ms(), 500.0, 1.0e-6, "预算 total 来自内容")
	var hold: Dictionary = m.plan_maneuver("hold")
	_near(float((hold.get("plan", {}) as Dictionary).get("dv_ms", 0.0)), 7.0, 1.0e-6,
		"hold 成本来自内容")
	_eq(int(m.vm_navigation().get("limits", {}).get("max_queue", 0)), 2, "vm.limits.max_queue 来自内容")
	_ok(m.plan_routes("earth_port", "moon_port").get("ok", false), "自定义内容仍可规划路线")
	_data_line("content-driven", "节点/边/预算/机动成本/交通规则均可由 JSON 覆盖")
