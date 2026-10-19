extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R4-CORE-2 headless probe：导航/交通管制/机动 + 完整损管 接入 V17 bridge/state
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/v17_nav_integration_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const BridgeScript := preload("res://scripts/framework_bridge.gd")
const StateScript := preload("res://scripts/state.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R4-CORE-2 PROBE · 导航/交通管制/机动 + 完整损管 接入")
	print("════════════════════════════════════════════════════════════")
	_test_bridge_boot()
	_test_nav_vm()
	_test_routes_and_selection()
	_test_clearance()
	_test_maneuvers()
	_test_no_auto_execute()
	_test_damage_full_bridge()
	_test_state_fields()
	_test_state_nav_api()
	_test_state_damage_api()
	_test_restart_reset()
	_test_json_and_legacy()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 NAV INTEGRATION PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 NAV INTEGRATION PROBE FAILED")
		quit(1)
	else:
		print("V17 NAV INTEGRATION PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.5f expected=%.5f diff=%.5f" % [actual, expected, diff])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _make_bridge():
	var br = BridgeScript.new()
	var ok: bool = br.boot()
	_ok(ok, "bridge.boot", str(br.errors))
	_ok(br.nav_ready, "bridge.nav_ready", str(br.errors))
	return br

func _make_state(br):
	var st = StateScript.new()
	if st.prelude_open:
		st.prelude_skip()
	st.framework = br
	st.fw_sync(0.0)
	return st

func _future_window(br, lead := 60.0) -> Dictionary:
	var now_t := float(br.navigation_view().get("t", 0.0))
	return {"open_t": now_t + lead, "close_t": now_t + lead + 7200.0}

func _nav_maneuver(br, plan_id: String) -> Dictionary:
	for raw in (br.navigation_view().get("planned_maneuvers", []) as Array):
		if String((raw as Dictionary).get("id", "")) == plan_id:
			return raw
	return {}

func _nav_state(br, plan_id: String) -> String:
	return String(_nav_maneuver(br, plan_id).get("state", ""))

func _clearance_of(br, request_id: String) -> Dictionary:
	for raw in (br.navigation_view().get("clearances", []) as Array):
		if String((raw as Dictionary).get("id", "")) == request_id:
			return raw
	return {}

# ═══════════════════════════════════════════════════════════════════
# 1. bridge 启动：nav 创建/内容加载
# ═══════════════════════════════════════════════════════════════════

func _test_bridge_boot() -> void:
	_section_begin("1 bridge 启动")
	var br = _make_bridge()
	_ok(br.ready, "bridge.ready")
	_ok(br.nav != null, "bridge.nav 实例存在")
	_ok(br.nav_ready, "bridge.nav_ready=true")
	_ok(br.errors.is_empty(), "bridge.errors 为空", str(br.errors))
	_eq(String(br.navigation_view().get("schema", "")), "navigation.v1", "nav schema=navigation.v1")
	_eq(bool(br.navigation_view().get("ready", false)), true, "nav vm ready=true")
	_eq(bool(br.navigation_view().get("authoritative", true)), false, "nav authoritative=false（规划抽象）")
	_data_line("boot", "bridge/nav ready · schema=navigation.v1 · authoritative=false")

# ═══════════════════════════════════════════════════════════════════
# 2. vm_navigation 只读字段
# ═══════════════════════════════════════════════════════════════════

func _test_nav_vm() -> void:
	_section_begin("2 导航 vm")
	var br = _make_bridge()
	var vm: Dictionary = br.navigation_view()
	for key in ["schema", "id", "title", "ready", "t", "nodes", "routes", "selected",
			"clearance", "clearances", "queue", "planned_maneuvers", "budget", "limits",
			"events", "summary"]:
		_ok(vm.has(key), "vm_navigation 含字段: " + key)
	_eq((vm.get("nodes", []) as Array).size(), 8, "nodes=8")
	var budget: Dictionary = vm.get("budget", {})
	for key in ["dv_total_ms", "dv_reserve_ms", "dv_used_ms", "dv_committed_ms", "dv_available_ms"]:
		_ok(budget.has(key), "budget 含 " + key)
	_near(float(budget.get("dv_total_ms", 0.0)), 1600.0, 1.0e-9, "budget total=1600")
	_near(float(budget.get("dv_available_ms", 0.0)), 1500.0, 1.0e-9, "初始 available=1500")
	var sum: Dictionary = vm.get("summary", {})
	_eq(int(sum.get("nodes", 0)), 8, "summary.nodes=8")
	_eq(int(sum.get("edges", 0)), 15, "summary.edges=15")
	var limits: Dictionary = vm.get("limits", {})
	_ok(limits.has("max_hops") and limits.has("priority_range"), "limits 字段")
	_ok(vm.get("events", []) is Array, "events 为 Array")
	_ok(br.navigation_summary().has("maneuvers"), "bridge.navigation_summary()")
	_data_line("nav-vm", "nodes=8 edges=15 budget=1600/1500 · sizes/limits/events/summary 齐全")

# ═══════════════════════════════════════════════════════════════════
# 3. 路线规划 / 选择
# ═══════════════════════════════════════════════════════════════════

func _test_routes_and_selection() -> void:
	_section_begin("3 路线规划/选择")
	var br = _make_bridge()
	var avail_before := float(br.navigation_view().get("budget", {}).get("dv_available_ms", 0.0))
	var r: Dictionary = br.nav_plan_routes("l1", "geo")
	_eq(bool(r.get("ok", false)), true, "nav_plan_routes(l1→geo)")
	var candidates: Array = r.get("candidates", [])
	_ok(candidates.size() >= 3, "3 类候选", str(candidates.size()))
	var profiles: Array = []
	for raw in candidates:
		var c: Dictionary = raw
		profiles.append(String(c.get("profile", "")))
		_ok(String(c.get("candidate_id", "")) != "", "候选有 candidate_id")
		_ok(c.has("dv_ms") and c.has("duration_s") and c.has("exposure") and c.has("feasible"),
			"候选字段 dv/duration/exposure/feasible")
	_ok("fast" in profiles, "候选含 fast")
	_ok("economy" in profiles, "候选含 economy")
	_ok("covert" in profiles, "候选含 covert")
	_eq(String(r.get("recommended", "")) != "", true, "有推荐候选", String(r.get("recommended", "")))
	var first_id := String((candidates[0] as Dictionary).get("candidate_id", ""))
	var sel: Dictionary = br.nav_select_route(first_id)
	_eq(bool(sel.get("ok", false)), true, "nav_select_route(candidate_id)")
	_eq(String(br.navigation_view().get("selected", {}).get("candidate_id", "")), first_id,
		"vm.selected 更新")
	# 规划/选择不消耗 Δv、不产生机动
	_near(float(br.navigation_view().get("budget", {}).get("dv_available_ms", 0.0)), avail_before,
		1.0e-9, "规划不消耗 Δv")
	_eq((br.navigation_view().get("planned_maneuvers", []) as Array).size(), 0,
		"规划不自动创建机动")
	var bad: Dictionary = br.nav_plan_routes("l1", "nonexistent")
	_eq(bool(bad.get("ok", true)), false, "未知节点规划被拒绝")
	_data_line("routes", "l1→geo 候选=%d profiles=%s recommended=%s" % [
		candidates.size(), str(profiles), String(r.get("recommended", ""))])

# ═══════════════════════════════════════════════════════════════════
# 4. 交通许可
# ═══════════════════════════════════════════════════════════════════

func _test_clearance() -> void:
	_section_begin("4 交通许可")
	var br = _make_bridge()
	var routes: Dictionary = br.nav_plan_routes("l1", "geo")
	var candidates: Array = routes.get("candidates", [])
	var fast_id := ""
	var econ_id := ""
	for raw in candidates:
		var c: Dictionary = raw
		if String(c.get("profile", "")) == "fast":
			fast_id = String(c.get("candidate_id", ""))
		elif String(c.get("profile", "")) == "economy":
			econ_id = String(c.get("candidate_id", ""))
	var window := {"open_t": 60.0, "close_t": 3600.0}
	# 高暴露快速路线 → hold（不自动放行）
	br.nav_select_route(fast_id)
	var hold_req: Dictionary = br.nav_request_clearance(fast_id, window, 2)
	_eq(bool(hold_req.get("ok", false)), true, "请求许可（fast 路线）ok")
	_eq(String(hold_req.get("status", "")), "hold", "高暴露路线进入 hold（复核）")
	var hold_id := String(hold_req.get("request_id", ""))
	_eq(String(_clearance_of(br, hold_id).get("status", "")), "hold", "clearances 记录 hold")
	_eq((br.navigation_view().get("queue", []) as Array).size(), 1, "hold 进入 queue")
	# 管制员批准 hold
	var grant: Dictionary = br.nav_grant(hold_id)
	_eq(bool(grant.get("ok", false)), true, "nav_grant(hold)")
	_eq(String(grant.get("status", "")), "granted", "grant 后 granted")
	# 低暴露经济路线 → 自动批准（无需交通许可）
	var econ_req: Dictionary = br.nav_request_clearance(econ_id, window, 3)
	_eq(bool(econ_req.get("ok", false)), true, "请求许可（economy）ok")
	_eq(String(econ_req.get("status", "")), "granted", "低暴露/无需许可 → granted")
	# 拒绝
	var deny_req: Dictionary = br.nav_request_clearance(fast_id, window, 3)
	var deny_id := String(deny_req.get("request_id", ""))
	var deny: Dictionary = br.nav_deny(deny_id, "authority_denied")
	_eq(bool(deny.get("ok", false)), true, "nav_deny")
	_eq(String(deny.get("status", "")), "denied", "deny 后 denied")
	# 保持
	var h2: Dictionary = br.nav_request_clearance(fast_id, window, 3)
	var h2id := String(h2.get("request_id", ""))
	var hold2: Dictionary = br.nav_hold(h2id, 900.0)
	_eq(bool(hold2.get("ok", false)), true, "nav_hold")
	_eq(String(hold2.get("status", "")), "hold", "hold 后 hold")
	# 优先级越界 → denied
	var bad_prio: Dictionary = br.nav_request_clearance(econ_id, window, 9)
	_eq(String(bad_prio.get("status", "")), "denied", "优先级越界被拒绝")
	_eq(String(bad_prio.get("reason", "")), "priority_range", "拒绝原因 priority_range")
	# 时间窗过期 → denied
	var bad_win: Dictionary = br.nav_request_clearance(econ_id, {"open_t": -100.0, "close_t": 100.0}, 3)
	_eq(String(bad_win.get("reason", "")), "window_in_past", "时间窗过期原因 window_in_past")
	# 许可不自动执行机动
	_eq((br.navigation_view().get("planned_maneuvers", []) as Array).size(), 0,
		"许可不自动创建/执行机动")
	_data_line("clearance", "hold→grant · economy→granted · deny/hold/priority/window 拒绝原因 · 无自动执行")

# ═══════════════════════════════════════════════════════════════════
# 5. 机动状态机
# ═══════════════════════════════════════════════════════════════════

func _test_maneuvers() -> void:
	_section_begin("5 机动")
	var br = _make_bridge()
	var budget0: Dictionary = br.navigation_view().get("budget", {})
	var avail0 := float(budget0.get("dv_available_ms", 0.0))
	# hold：无许可 → 授权 → 排队 → 执行 → 自动推进完成
	var p: Dictionary = br.nav_plan_maneuver("hold")
	_eq(bool(p.get("ok", false)), true, "plan_maneuver(hold)")
	var plan_id := String(p.get("plan_id", ""))
	_eq(_nav_state(br, plan_id), "PRE_ORDER", "计划初始 PRE_ORDER")
	_eq(float(br.navigation_view().get("budget", {}).get("dv_available_ms", 0.0)), avail0,
		"规划不消耗/预留 Δv")
	var auth: Dictionary = br.nav_authorize(plan_id)
	_eq(bool(auth.get("ok", false)), true, "nav_authorize")
	_eq(_nav_state(br, plan_id), "AUTHORIZED", "授权后 AUTHORIZED")
	_ok(float(br.navigation_view().get("budget", {}).get("dv_committed_ms", 0.0)) > 0.0,
		"授权预留 Δv（committed）")
	var q: Dictionary = br.nav_execute(plan_id)  # 未排队直接执行应失败
	_eq(bool(q.get("ok", true)), false, "未排队直接 execute 被拒绝")
	var q2: Dictionary = br.nav_queue_maneuver(plan_id)
	_eq(bool(q2.get("ok", false)), true, "nav_queue_maneuver")
	_eq(_nav_state(br, plan_id), "QUEUED", "排队后 QUEUED")
	var ex: Dictionary = br.nav_execute(plan_id)
	_eq(bool(ex.get("ok", false)), true, "nav_execute")
	_eq(_nav_state(br, plan_id), "EXECUTING", "执行后 EXECUTING")
	br.sync(130.0)
	_eq(_nav_state(br, plan_id), "DONE", "步进 130s 后 DONE（hold duration 120）")
	_ok(float(br.navigation_view().get("budget", {}).get("dv_used_ms", 0.0)) >= 40.0,
		"完成后消耗 Δv≥40")
	# 需要许可的 approach：无许可 queue 失败；有许可成功
	var pa: Dictionary = br.nav_plan_maneuver("approach", "geo")
	var aid := String(pa.get("plan_id", ""))
	_eq(bool(pa.get("ok", false)), true, "plan_maneuver(approach, geo)")
	br.nav_authorize(aid)
	var q_no: Dictionary = br.nav_queue_maneuver(aid)
	_eq(bool(q_no.get("ok", true)), false, "approach 无许可排队被拒绝")
	_eq(String(q_no.get("reason", "")), "clearance_required", "原因 clearance_required")
	var routes: Dictionary = br.nav_plan_routes("l1", "geo")
	var clr_route := String((routes.get("candidates", []) as Array)[0].get("candidate_id", ""))
	br.nav_select_route(clr_route)
	var clr: Dictionary = br.nav_request_clearance(clr_route, _future_window(br), 2)
	br.nav_grant(String(clr.get("request_id", "")))
	var q_ok: Dictionary = br.nav_queue_maneuver(aid, String(clr.get("request_id", "")))
	_eq(bool(q_ok.get("ok", false)), true, "approach 持许可排队成功")
	# burn：执行中 abort（部分 Δv）
	var pb: Dictionary = br.nav_plan_maneuver("burn", "", {"dv_ms": 60.0})
	var bid := String(pb.get("plan_id", ""))
	br.nav_authorize(bid)
	var routes2: Dictionary = br.nav_plan_routes("l1", "geo")
	var clr2_route := String((routes2.get("candidates", []) as Array)[0].get("candidate_id", ""))
	br.nav_select_route(clr2_route)
	var clr2: Dictionary = br.nav_request_clearance(clr2_route, _future_window(br), 2)
	br.nav_grant(String(clr2.get("request_id", "")))
	br.nav_queue_maneuver(bid, String(clr2.get("request_id", "")))
	br.nav_execute(bid)
	br.sync(30.0)
	var ab: Dictionary = br.nav_abort(bid)
	_eq(bool(ab.get("ok", false)), true, "nav_abort(EXECUTING)")
	_eq(_nav_state(br, bid), "ABORTED", "abort 后 ABORTED")
	_ok(float(ab.get("consumed_ms", 0.0)) > 0.0, "执行中 abort 有部分 Δv 消耗")
	_data_line("maneuver", "hold 完成 · approach 无许可拒绝/持许可排队 · burn 执行中 abort 部分消耗")

# ═══════════════════════════════════════════════════════════════════
# 6. 不自动执行
# ═══════════════════════════════════════════════════════════════════

func _test_no_auto_execute() -> void:
	_section_begin("6 不自动执行")
	var br = _make_bridge()
	var p: Dictionary = br.nav_plan_maneuver("hold")
	var pid := String(p.get("plan_id", ""))
	_ok(br.nav_authorize(pid).get("ok", false), "授权 hold")
	br.sync(100.0)
	_eq(_nav_state(br, pid), "AUTHORIZED", "授权后步进不自动执行（仍 AUTHORIZED）")
	_ok(float(br.navigation_view().get("budget", {}).get("dv_available_ms", 0.0)) > 0.0,
		"未执行不消耗 Δv（available>0）")
	# 规划路线/请求许可后同样不产生执行
	br.nav_plan_routes("l1", "geo")
	_eq((br.navigation_view().get("planned_maneuvers", []) as Array).size(), 1,
		"规划/许可不自动新增机动")
	_data_line("no-auto", "授权后 sync 100s 仍 AUTHORIZED；规划/许可不自动执行")

# ═══════════════════════════════════════════════════════════════════
# 7. bridge 完整损管 full
# ═══════════════════════════════════════════════════════════════════

func _test_damage_full_bridge() -> void:
	_section_begin("7 完整损管 bridge")
	var br = _make_bridge()
	_eq(bool(br.damage_model_ready), true, "bridge.damage_model_ready=true")
	var full: Dictionary = br.damage_full_view()
	_eq((full.get("sections", []) as Array).size(), 7, "damage_full sections=7")
	_eq(String(full.get("entity_id", "")), "harmattan", "damage_full entity_id")
	for key in ["events", "queue", "resources", "summary", "effects"]:
		_ok(full.has(key), "damage_full 含 " + key)
	# 旧 damage 兼容
	_eq((br.damage_view().get("sections", []) as Array).size(), 3, "旧 damage_view sections=3")
	var r: Dictionary = br.damage_apply_hit("sensors", 0.4, 0.5, "fore", "probe")
	_eq(bool(r.get("ok", false)), true, "bridge.damage_apply_hit")
	var sec_integrity := 1.0
	for raw in (br.damage_full_view().get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "sensors":
			sec_integrity = float((raw as Dictionary).get("integrity", 1.0))
	_ok(sec_integrity < 1.0, "damage_full.sensors 受损", "integrity=%.3f" % sec_integrity)
	_eq((br.damage_view().get("sections", []) as Array).size(), 3, "命中后旧 damage 仍 3 项")
	# 维修转发
	var a: Dictionary = br.damage_assign_repair("sensors", 1)
	_eq(bool(a.get("ok", false)), true, "bridge.damage_assign_repair")
	_ok((br.damage_full_view().get("queue", []) as Array).size() > 0, "damage_full.queue 有任务")
	var c: Dictionary = br.damage_cancel_repair("sensors")
	_eq(bool(c.get("ok", false)), true, "bridge.damage_cancel_repair")
	# 无档案实体
	var bad: Dictionary = br.damage_apply_hit("hull", 0.5, 0.5, "fore", "probe", "ferry")
	_eq(bool(bad.get("ok", true)), false, "无档案实体命中被拒绝")
	_data_line("damage-full", "bridge damage_full sections=7 + 旧 sections=3 兼容 · 写 API 转发")

# ═══════════════════════════════════════════════════════════════════
# 8. state 只读字段
# ═══════════════════════════════════════════════════════════════════

func _test_state_fields() -> void:
	_section_begin("8 state 字段")
	var br = _make_bridge()
	var st = _make_state(br)
	_eq(st.fw_ready, true, "state.fw_ready")
	_eq(st.fw_nav_ready, true, "state.fw_nav_ready")
	_ok(st.fw_nav.size() > 0, "state.fw_nav 非空")
	_eq((st.fw_nav.get("nodes", []) as Array).size(), 8, "fw_nav.nodes=8")
	_eq(int(st.fw_nav_summary.get("edges", 0)), 15, "fw_nav_summary.edges=15")
	_eq(st.fw_damage_model, true, "state.fw_damage_model=true")
	_eq((st.fw_damage_full.get("sections", []) as Array).size(), 7, "state.fw_damage_full sections=7")
	_eq((st.fw_damage.get("sections", []) as Array).size(), 3, "旧 state.fw_damage 仍 3 项（兼容）")
	var bs: Dictionary = st.fw_bridge_state()
	for key in ["nav", "nav_ready", "nav_summary", "damage_full", "damage_model"]:
		_ok(bs.has(key), "fw_bridge_state 含 " + key)
	_data_line("state-fields", "fw_nav/fw_nav_ready/fw_nav_summary/fw_damage_model/fw_damage_full + 旧 fw_damage")

# ═══════════════════════════════════════════════════════════════════
# 9. state 导航 API 包装
# ═══════════════════════════════════════════════════════════════════

func _test_state_nav_api() -> void:
	_section_begin("9 state 导航 API")
	var br = _make_bridge()
	var st = _make_state(br)
	var r: Dictionary = st.fw_nav_plan_routes("l1", "geo")
	_eq(bool(r.get("ok", false)), true, "state.fw_nav_plan_routes")
	var cand := String((r.get("candidates", []) as Array)[0].get("candidate_id", ""))
	var sel: Dictionary = st.fw_nav_select_route(cand)
	_eq(bool(sel.get("ok", false)), true, "state.fw_nav_select_route")
	var clr: Dictionary = st.fw_nav_request_clearance(cand, {"open_t": 60.0, "close_t": 3600.0}, 2)
	_ok(String(clr.get("status", "")) in ["granted", "hold"], "state.fw_nav_request_clearance",
		String(clr.get("status", "")))
	if String(clr.get("status", "")) == "hold":
		_eq(bool(st.fw_nav_grant(String(clr.get("request_id", ""))).get("ok", false)), true,
			"state.fw_nav_grant")
	var p: Dictionary = st.fw_nav_plan_maneuver("hold")
	_eq(bool(p.get("ok", false)), true, "state.fw_nav_plan_maneuver")
	var pid := String(p.get("plan_id", ""))
	_eq(bool(st.fw_nav_authorize(pid).get("ok", false)), true, "state.fw_nav_authorize")
	_eq(bool(st.fw_nav_queue_maneuver(pid).get("ok", false)), true, "state.fw_nav_queue_maneuver")
	_eq(bool(st.fw_nav_execute(pid).get("ok", false)), true, "state.fw_nav_execute")
	br.sync(130.0)
	st.fw_sync(0.0)
	var state_done := false
	for raw in (st.fw_nav.get("planned_maneuvers", []) as Array):
		var m: Dictionary = raw
		if String(m.get("id", "")) == pid and String(m.get("state", "")) == "DONE":
			state_done = true
	_ok(state_done, "fw_nav 反映机动 DONE（bridge.sync 后）")
	# abort 包装（新计划）
	var p2: Dictionary = st.fw_nav_plan_maneuver("retreat")
	var pid2 := String(p2.get("plan_id", ""))
	st.fw_nav_authorize(pid2)
	st.fw_nav_queue_maneuver(pid2)
	st.fw_nav_execute(pid2)
	var ab: Dictionary = st.fw_nav_abort(pid2)
	_eq(bool(ab.get("ok", false)), true, "state.fw_nav_abort")
	_ok(not st.fw_nav.is_empty(), "fw_nav 非空")
	_data_line("state-nav", "plan/select/request/grant/plan_maneuver/authorize/queue/execute/abort 全链路")

# ═══════════════════════════════════════════════════════════════════
# 10. state 完整损管 API
# ═══════════════════════════════════════════════════════════════════

func _test_state_damage_api() -> void:
	_section_begin("10 state 损管 API")
	var br = _make_bridge()
	var st = _make_state(br)
	var r: Dictionary = st.fw_damage_apply_hit("sensors", 0.4, 0.5, "fore", "probe")
	_eq(bool(r.get("ok", false)), true, "state.fw_damage_apply_hit")
	var integrity := 1.0
	for raw in (st.fw_damage_full.get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == "sensors":
			integrity = float((raw as Dictionary).get("integrity", 1.0))
	_ok(integrity < 1.0, "fw_damage_full.sensors 受损")
	_eq((st.fw_damage.get("sections", []) as Array).size(), 3, "旧 fw_damage 仍 3 项")
	var a: Dictionary = st.fw_damage_assign_repair("sensors", 1)
	_eq(bool(a.get("ok", false)), true, "state.fw_damage_assign_repair")
	var pr: Dictionary = st.fw_damage_set_priority("sensors", 2)
	_eq(bool(pr.get("ok", false)), true, "state.fw_damage_set_priority")
	var c: Dictionary = st.fw_damage_cancel_repair("sensors")
	_eq(bool(c.get("ok", false)), true, "state.fw_damage_cancel_repair")
	_data_line("state-damage", "fw_damage_apply_hit/assign/set_priority/cancel 转发；旧 fw_damage 兼容")

# ═══════════════════════════════════════════════════════════════════
# 11. restart 复位
# ═══════════════════════════════════════════════════════════════════

func _test_restart_reset() -> void:
	_section_begin("11 restart 复位")
	var br = _make_bridge()
	var st = _make_state(br)
	st.fw_nav_plan_routes("l1", "geo")
	st.fw_nav_plan_maneuver("hold")
	st.fw_damage_apply_hit("sensors", 0.4, 0.5, "fore", "probe")
	_ok((st.fw_nav.get("planned_maneuvers", []) as Array).size() > 0, "restart 前有导航状态")
	st.fw_restart()
	_eq(st.fw_nav_ready, true, "restart 后 nav 仍 ready")
	_eq((st.fw_nav.get("planned_maneuvers", []) as Array).size(), 0, "restart 后机动清空")
	_eq((st.fw_nav.get("routes", []) as Array).size(), 0, "restart 后候选清空")
	_eq(float(st.fw_nav.get("budget", {}).get("dv_used_ms", -1.0)), 0.0, "restart 后 Δv 复位")
	_eq(st.fw_damage_model, true, "restart 后 damage_model 仍 ready")
	_eq((st.fw_damage_full.get("sections", []) as Array).size(), 7, "restart 后 damage_full 7 分区")
	_near(float(st.fw_damage_full.get("t", -1.0)), 0.0, 1.0e-9, "restart 后 damage_full t=0")
	_data_line("restart", "nav 机动/候选/预算复位；damage_full 重置；旧字段保持")

# ═══════════════════════════════════════════════════════════════════
# 12. JSON / 旧字段回归
# ═══════════════════════════════════════════════════════════════════

func _test_json_and_legacy() -> void:
	_section_begin("12 JSON/旧字段")
	var br = _make_bridge()
	var st = _make_state(br)
	st.fw_nav_plan_routes("l1", "geo")
	st.fw_nav_plan_maneuver("hold")
	st.fw_damage_apply_hit("sensors", 0.4, 0.5, "fore", "probe")
	var bs: Dictionary = st.fw_bridge_state()
	var js := JSON.stringify(bs)
	_ok(js.length() > 4000, "fw_bridge_state JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "JSON 回读 Dictionary")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("nav") is Dictionary, "回读 nav")
		_ok((((pd.get("nav", {}) as Dictionary).get("nodes", []) as Array)).size() == 8,
			"回读 nav.nodes=8")
		_ok(pd.get("damage_full") is Dictionary, "回读 damage_full")
		_eq((((pd.get("damage_full", {}) as Dictionary).get("sections", []) as Array)).size(), 7,
			"回读 damage_full.sections=7")
		_eq((((pd.get("damage", {}) as Dictionary).get("sections", []) as Array)).size(), 3,
			"回读旧 damage.sections=3")
		_ok(pd.get("nav_summary") is Dictionary, "回读 nav_summary")
	# 旧 bridge 契约
	_eq((br.damage_view().get("sections", []) as Array).size(), 3, "bridge 旧 damage sections=3")
	_eq(String(br.damage_view().get("entity_id", "")), "harmattan", "bridge 旧 damage entity_id")
	_ok(br.summary().has("contacts"), "bridge.summary 旧字段")
	_data_line("json/legacy", "fw_bridge_state JSON 可回读；旧 damage sections=3 契约保持")
