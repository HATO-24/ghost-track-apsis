extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3E 最小 probe：PortService 港口/对接/加注/船坞/拖曳
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/port_service_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接物理/UI。
# ═══════════════════════════════════════════════════════════════════

const PortService := preload("res://scripts/core/port_service.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3E PROBE · PortService")
	print("════════════════════════════════════════════════════════════")
	_test_config()
	_test_request()
	_test_permit_resources()
	_test_dock_lifecycle()
	_test_refuel_repair()
	_test_tow_shuttle()
	_test_queue_expiry()
	_test_save_load()
	_test_events_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PORT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PORT PROBE FAILED")
		quit(1)
	else:
		print("V17 PORT PROBE OK")
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
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _cfg() -> Dictionary:
	return {"ports": [
		{"id": "p1", "name": "L1 Meridian", "berths": ["B1", "B2"],
			"drydock_slots": 1, "tugs": ["TUG1"],
			"fuel_capacity_t": 1000.0, "fuel_available_t": 1000.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000.0}],
			"corridor": "C1", "require_permit": true,
			"services": ["refuel", "repair", "tow", "shuttle"]},
		{"id": "p2", "name": "L4 Hammer", "berths": ["B1"], "drydock_slots": 0,
			"tugs": [], "fuel_capacity_t": 100.0, "fuel_available_t": 100.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000.0}],
			"corridor": "C2", "require_permit": false,
			"services": ["refuel"]},
	]}

func _state_core(s) -> String:
	var vm: Dictionary = s.vm()
	return _norm_json({"t_s": vm.get("t_s", 0.0), "ports": vm.get("ports", []),
		"requests": vm.get("requests", []), "summary": vm.get("summary", {})})

func _new_port(bus = null):
	var s = PortService.new(_cfg())
	if bus != null:
		s.bind_event_bus(bus)
	_ok(bool(s.ready), "PortService ready", str(s.errors))
	return s

func _docked(s, ship := "ship1", port := "p1") -> Dictionary:
	var r: Dictionary = s.request("dock", ship, port, {"clearance": "CLR-1"})
	var rid := String(r.get("request_id", ""))
	var gp: Dictionary = s.permit(rid)
	_eq(String(gp.get("status", "")), "GRANTED", "helper grant " + ship)
	s.approach(rid)
	var dk: Dictionary = s.dock(rid)
	_eq(String(dk.get("status", "")), "DOCKED", "helper dock " + ship)
	return {"request_id": rid, "dock": dk}

# ═══════════════════════════════════════════════════════════════════
# 1. 配置 / 初始
# ═══════════════════════════════════════════════════════════════════

func _test_config() -> void:
	_section_begin("1 配置/初始")
	var s = _new_port()
	_eq(s.ports.size(), 2, "ports 2")
	_eq(String(s.summary().get("schema", "")), "v17.port_service.v1", "summary schema")
	_eq(int(s.summary().get("ports", 0)), 2, "summary ports")
	_eq(int(s.summary().get("requests", 0)), 0, "初始 requests 0")
	var res: Dictionary = s.summary().get("resources", {})
	_eq(int(res.get("berths_total", 0)), 3, "全局泊位 3")
	_eq(int(res.get("berths_free", 0)), 3, "初始泊位全空闲")
	_eq(int(res.get("drydock_total", 0)), 1, "全局船坞 1")
	_eq(int(res.get("tugs_total", 0)), 1, "全局拖船 1")
	_near(float(res.get("fuel_available_t", 0.0)), 1100.0, 1.0e-9, "全局燃料 1100")
	var vm: Dictionary = s.vm()
	_eq(String(vm.get("schema", "")), "v17.port_service.v1", "vm schema")
	_ok(vm.get("ports") is Array and (vm.get("ports") as Array).size() == 2, "vm ports")
	_ok(vm.get("requests") is Array, "vm requests")
	_ok(vm.get("queue") is Array, "vm queue")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("v15", true)), false, "不写 v15")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_ok(bool(s.check_contracts().get("ok", false)), "初始 contracts ok")
	# 每港资源
	var r1: Dictionary = s.port_summary("p1")
	_eq(int((r1.get("resources", {}) as Dictionary).get("berths_total", 0)), 2, "p1 泊位 2")
	_eq(String((r1.get("resources", {}) as Dictionary).get("corridor", "")), "C1", "p1 corridor")
	_ok(bool((r1.get("resources", {}) as Dictionary).get("window", {}).get("is_open", false)),
		"p1 窗口初始开放")
	# 非法配置拒绝
	var bads := [
		{"ports": []},
		{"ports": [{"id": "x", "berths": ["B1"]}, {"id": "x", "berths": ["B2"]}]},
		{"ports": [{"id": "x", "berths": ["B1", "B1"]}]},
		{"ports": [{"id": "x", "berths": ["B1"], "fuel_capacity_t": -1.0}]},
		{"ports": [{"id": "x", "berths": ["B1"],
			"fuel_capacity_t": 10.0, "fuel_available_t": 20.0}]},
		{"ports": [{"id": "x", "berths": ["B1"],
			"windows": [{"open_t": 10.0, "close_t": 5.0}]}]},
		{"ports": [{"id": "x", "berths": ["B1"], "services": ["bogus"]}]},
		{"ports": [{"id": "x", "berths": ["B1"], "tugs": ["T", "T"]}]},
	]
	for b in bads:
		var svc = PortService.new(b)
		_eq(bool(svc.ready), false, "非法配置拒绝")
	_item("config", "ports/berths/drydock/tugs/fuel/window/services 校验")

func _item(label: String, value: String) -> void:
	pass

# ═══════════════════════════════════════════════════════════════════
# 2. request 基础
# ═══════════════════════════════════════════════════════════════════

func _test_request() -> void:
	_section_begin("2 request")
	var s = _new_port()
	var bad_kind: Dictionary = s.request("bogus", "ship1", "p1")
	_eq(String(bad_kind.get("reason", "")), "invalid_kind", "非法 kind 拒绝")
	var bad_ship: Dictionary = s.request("dock", "", "p1")
	_eq(String(bad_ship.get("reason", "")), "invalid_ship", "空 ship 拒绝")
	var bad_port: Dictionary = s.request("dock", "ship1", "no_port")
	_eq(String(bad_port.get("reason", "")), "unknown_port", "未知 port 拒绝")
	var r: Dictionary = s.request("dock", "ship1", "p1", {"priority": 3,
		"clearance": "CLR-1", "window_id": "W1"})
	_eq(bool(r.get("ok", false)), true, "request dock ok")
	var rid := String(r.get("request_id", ""))
	_ok(rid.begins_with("PR-"), "request_id 生成")
	_eq(String(r.get("status", "")), "REQUESTED", "初始 REQUESTED")
	var req: Dictionary = s.get_request(rid)
	_eq(String(req.get("kind", "")), "dock", "kind")
	_eq(String(req.get("ship_id", "")), "ship1", "ship_id")
	_eq(String(req.get("port_id", "")), "p1", "port_id")
	_eq(int(req.get("priority", 0)), 3, "priority")
	_eq(String(req.get("berth_id", "")), "", "未许可无 berth")
	_ok(bool(s.check_contracts().get("ok", false)), "contracts_ok")
	_ok(s.check_contracts().get("ok", false), "request 后 contracts ok")
	# 同一舰只允许一个活动请求
	var busy: Dictionary = s.request("tow", "ship1", "p1")
	_eq(String(busy.get("reason", "")), "ship_busy", "同舰第二请求拒绝")
	# 许可前不自动 grant
	_eq(String(s.get_request(rid).get("status", "")), "REQUESTED", "无自动 grant")
	# 队列
	var q: Array = s.queue()
	_eq(q.size(), 1, "queue 1")
	_eq(String((q[0] as Dictionary).get("request_id", "")), rid, "queue request")
	_data_line("request", "字段/priority/无自动 grant/同舰 busy/queue")

# ═══════════════════════════════════════════════════════════════════
# 3. permit / 拒绝 / HOLD / 窗口
# ═══════════════════════════════════════════════════════════════════

func _test_permit_resources() -> void:
	_section_begin("3 permit/资源")
	# 有/无 clearance
	var s = _new_port()
	var r0: Dictionary = s.request("dock", "ship0", "p1", {})
	var r0id := String(r0.get("request_id", ""))
	var d0: Dictionary = s.permit(r0id)
	_eq(bool(d0.get("ok", true)), false, "无许可拒绝")
	_eq(String(d0.get("reason", "")), "no_permit", "no_permit")
	_eq(String(s.get_request(r0id).get("status", "")), "DENIED", "status DENIED")
	# 资源容量：p2 只有 B1
	var a: Dictionary = s.request("dock", "a", "p2", {"clearance": "C-A"})
	var aid := String(a.get("request_id", ""))
	_eq(String(s.permit(aid).get("status", "")), "GRANTED", "第一个 grant")
	_ok(String(s.get_request(aid).get("berth_id", "")) != "", "grant 分配 berth")
	var b: Dictionary = s.request("dock", "b", "p2", {"clearance": "C-B"})
	var bid := String(b.get("request_id", ""))
	var hb: Dictionary = s.permit(bid)
	_eq(String(hb.get("reason", "")), "no_berth", "无泊位 HOLD")
	_eq(String(s.get_request(bid).get("status", "")), "HOLD", "status HOLD")
	_ok(s.queue("p2").size() == 1, "HOLD 进队列")
	# 队列优先级/创建顺序
	var q = s.queue("p2")
	_eq(String((q[0] as Dictionary).get("request_id", "")), bid, "queue 包含 held")
	# HOLD 后释放资源再 permit（deny 释放已占用泊位）
	s.deny(aid, "release_berth")
	var hp: Dictionary = s.permit(bid)
	_eq(bool(hp.get("ok", false)), true, "资源释放后 HOLD permit ok")
	_eq(String(hp.get("status", "")), "GRANTED", "HOLD→GRANTED")
	# 拒绝
	var c: Dictionary = s.request("dock", "c", "p1", {"clearance": "C-C"})
	var cid := String(c.get("request_id", ""))
	var de: Dictionary = s.deny(cid, "manual_deny")
	_eq(bool(de.get("ok", true)), false, "deny 返回 false")
	_eq(String(s.get_request(cid).get("status", "")), "DENIED", "deny 后 DENIED")
	_eq(String(s.get_request(cid).get("reason", "")), "manual_deny", "deny reason")
	# port not accepting
	var cfg_no := _cfg()
	(cfg_no["ports"][0] as Dictionary)["accepting"] = false
	var s_no = PortService.new(cfg_no)
	var nr: Dictionary = s_no.request("dock", "z", "p1", {"clearance": "C-Z"})
	var nid := String(nr.get("request_id", ""))
	_eq(String(s_no.permit(nid).get("reason", "")), "port_not_accepting", "port 不接受拒绝")
	# 窗口关闭：tick 到闭窗后 permit → HOLD window_not_open
	var s2 = _new_port()
	var wr: Dictionary = s2.request("dock", "w1", "p1", {"clearance": "C-W"})
	var wid := String(wr.get("request_id", ""))
	s2.tick(2000.0)
	_eq(bool(s2.window_status("p1").get("is_open", true)), false, "窗口已关")
	_eq(String(s2.permit(wid).get("reason", "")), "window_not_open", "窗口关 HOLD")
	_eq(String(s2.get_request(wid).get("status", "")), "HOLD", "窗口关 status HOLD")
	# HOLD 后再次 permit 仍关窗
	_eq(String(s2.permit(wid).get("reason", "")), "window_not_open", "再次 permit 仍 HOLD")
	# hold_on_capacity=false → DENIED no_berth
	var cfg_deny := _cfg()
	(cfg_deny["ports"][1] as Dictionary)["hold_on_capacity"] = false
	var s3 = PortService.new(cfg_deny)
	var x1: Dictionary = s3.request("dock", "x1", "p2", {"clearance": "C-X1"})
	s3.permit(String(x1.get("request_id", "")))
	var x2: Dictionary = s3.request("dock", "x2", "p2", {"clearance": "C-X2"})
	var x2res: Dictionary = s3.permit(String(x2.get("request_id", "")))
	_eq(String(x2res.get("reason", "")), "no_berth", "容量满 reason")
	_eq(String(s3.get_request(String(x2.get("request_id", ""))).get("status", "")), "DENIED",
		"hold=false 时 DENIED")
	_data_line("permit", "permit/deny/HOLD 队列/释放后 grant/不接受/窗口/容量满分支")

# ═══════════════════════════════════════════════════════════════════
# 4. 对接全流程
# ═══════════════════════════════════════════════════════════════════

func _test_dock_lifecycle() -> void:
	_section_begin("4 对接全流程")
	var s = _new_port()
	var r: Dictionary = s.request("dock", "ship1", "p1", {"clearance": "CLR-1"})
	var rid := String(r.get("request_id", ""))
	# 未许可不能进近/对接
	_eq(String(s.approach(rid).get("reason", "")), "wrong_state", "REQUESTED approach 拒绝")
	_eq(String(s.dock(rid).get("reason", "")), "wrong_state", "REQUESTED dock 拒绝")
	var gp: Dictionary = s.permit(rid)
	_eq(String(gp.get("status", "")), "GRANTED", "permit GRANTED")
	_eq(String(s.get_request(rid).get("berth_id", "")), "B1", "分配 B1")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("berths_free", -1)), 1,
		"grant 后空闲泊位 1")
	# dock 需要 approach
	var dk_early: Dictionary = s.dock(rid)
	_eq(String(dk_early.get("reason", "")), "wrong_state", "GRANTED dock 拒绝")
	var ap: Dictionary = s.approach(rid)
	_eq(String(ap.get("status", "")), "APPROACH", "approach APPROACH")
	_eq(String(ap.get("corridor", "")), "C1", "corridor C1")
	var dk: Dictionary = s.dock(rid)
	_eq(String(dk.get("status", "")), "DOCKED", "dock DOCKED")
	_eq(String(dk.get("berth_id", "")), "B1", "DOCKED berth")
	var req: Dictionary = s.get_request(rid)
	_near(float(req.get("granted_t", -1.0)), 0.0, 1.0e-9, "granted_t")
	_near(float(req.get("docked_t", -1.0)), 0.0, 1.0e-9, "docked_t")
	# 状态机序列历史
	var hist: Array = req.get("history", [])
	_ok(hist.size() >= 4, "history 状态迁移")
	_eq(String((hist[hist.size() - 1] as Dictionary).get("status", "")), "DOCKED", "history 末 DOCKED")
	# 服务中不能 undock
	s.refuel(rid, 10.0)
	_eq(String(s.undock(rid).get("reason", "")), "wrong_state", "SERVICING undock 拒绝")
	s.finish_service(rid)
	# 服务完成回 DOCKED
	_eq(String(s.get_request(rid).get("status", "")), "DOCKED", "finish 回 DOCKED")
	var ud: Dictionary = s.undock(rid)
	_eq(String(ud.get("status", "")), "DEPARTED", "undock DEPARTED")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("berths_free", 0)), 2,
		"离港释放泊位")
	_eq(String(s.undock(rid).get("reason", "")), "wrong_state", "重复 undock 拒绝")
	_ok(bool(s.check_contracts().get("ok", false)), "全流程 contracts ok")
	_data_line("dock_lifecycle", "REQUESTED→GRANTED→APPROACH→DOCKED→SERVICING→DOCKED→DEPARTED")

# ═══════════════════════════════════════════════════════════════════
# 5. 加注 / 船坞维修
# ═══════════════════════════════════════════════════════════════════

func _test_refuel_repair() -> void:
	_section_begin("5 加注/维修")
	var s = _new_port()
	var d := _docked(s, "ship1", "p1")
	var rid := String(d.get("request_id", ""))
	# services 可用
	var sv: Array = s.services(rid)
	_eq(sv.size(), 4, "services 4")
	var refuel_row := {}
	for raw in sv:
		if String((raw as Dictionary).get("service", "")) == "refuel":
			refuel_row = raw
	_ok(bool(refuel_row.get("available", false)), "refuel available")
	# 非法 amount / 未 docked
	_eq(String(s.refuel(rid, 0.0).get("reason", "")), "invalid_amount", "amount 0 拒绝")
	_eq(String(s.refuel(rid, -1.0).get("reason", "")), "invalid_amount", "amount 负拒绝")
	var fuel_before := float(s.port_summary("p1").get("resources", {}).get("fuel_available_t", 0.0))
	var rf: Dictionary = s.refuel(rid, 100.0)
	_eq(bool(rf.get("ok", false)), true, "refuel ok")
	_eq(String(rf.get("status", "")), "SERVICING", "refuel SERVICING")
	_near(float(rf.get("fuel_available_t", -1.0)), fuel_before - 100.0, 1.0e-9, "燃料扣除")
	# 重复服务拒绝
	_eq(String(s.refuel(rid, 10.0).get("reason", "")), "wrong_state", "SERVICING 再加注拒绝")
	var fin: Dictionary = s.finish_service(rid)
	_eq(String(fin.get("status", "")), "DOCKED", "refuel finish DOCKED")
	_ok(bool(s.get_request(rid).get("service_done", false)), "service_done")
	_near(float(s.port_summary("p1").get("resources", {}).get("fuel_available_t", 0.0)),
		fuel_before - 100.0, 1.0e-9, "燃料保持扣除")
	# 维修：占 drydock
	var rp: Dictionary = s.repair(rid)
	_eq(String(rp.get("status", "")), "SERVICING", "repair SERVICING")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("drydock_used", 0)), 1,
		"船坞占用 1")
	_eq(String(s.repair(rid).get("reason", "")), "wrong_state", "SERVICING 重复维修拒绝")
	_eq(String(s.finish_service(rid).get("status", "")), "DOCKED", "repair finish DOCKED")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("drydock_used", 0)), 0,
		"船坞释放")
	# 燃料不足 / 无船坞
	var p2fuel: Dictionary = s.request("dock", "ship2", "p2", {"clearance": "C2"})
	s.permit(String(p2fuel.get("request_id", "")))
	s.approach(String(p2fuel.get("request_id", "")))
	s.dock(String(p2fuel.get("request_id", "")))
	_eq(String(s.refuel(String(p2fuel.get("request_id", "")), 200.0).get("reason", "")),
		"insufficient_fuel", "燃料不足拒绝")
	_eq(String(s.repair(String(p2fuel.get("request_id", ""))).get("reason", "")),
		"service_unavailable", "p2 不支持 repair")
	var lock_row := {}
	for raw in s.services(String(p2fuel.get("request_id", ""))):
		if String((raw as Dictionary).get("service", "")) == "repair":
			lock_row = raw
	_ok(bool(lock_row.get("locked", false)), "p2 repair locked")
	# 未 docked 的 refuel
	var s2 = _new_port()
	var w: Dictionary = s2.request("dock", "w", "p1", {"clearance": "C-W"})
	s2.permit(String(w.get("request_id", "")))
	_eq(String(s2.refuel(String(w.get("request_id", "")), 1.0).get("reason", "")),
		"wrong_state", "未 docked refuel 拒绝")
	_data_line("services", "refuel 扣油/服务态互斥/维修占船坞/燃料不足/服务不可用")

# ═══════════════════════════════════════════════════════════════════
# 6. 拖曳 / 穿梭机
# ═══════════════════════════════════════════════════════════════════

func _test_tow_shuttle() -> void:
	_section_begin("6 拖曳/穿梭机")
	var s = _new_port()
	# tow: permit 占 tug
	var tw: Dictionary = s.tow("tug_ship", "p1", {"clearance": "C-T", "priority": 2})
	_eq(bool(tw.get("ok", false)), true, "tow request ok")
	var tid := String(tw.get("request_id", ""))
	_eq(String(tw.get("status", "")), "REQUESTED", "tow REQUESTED")
	_eq(String(s.permit(tid).get("status", "")), "GRANTED", "tow permit GRANTED")
	_eq(String(s.get_request(tid).get("tug_id", "")), "TUG1", "tow 分配 drag")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("tugs_free", -1)), 0,
		"tug 占用")
	# 第二拖曳 HOLD no_tug
	var tw2: Dictionary = s.tow("tug_ship2", "p1", {"clearance": "C-T2"})
	var tw2id := String(tw2.get("request_id", ""))
	_eq(String(s.permit(tw2id).get("reason", "")), "no_tug", "无拖船 HOLD")
	_eq(String(s.get_request(tw2id).get("status", "")), "HOLD", "第二拖曳 HOLD")
	# tow 进近→对接（对接时分配 berth）→离港释放
	_eq(String(s.approach(tid).get("status", "")), "APPROACH", "tow approach")
	_eq(String(s.dock(tid).get("status", "")), "DOCKED", "tow dock DOCKED")
	_ok(String(s.get_request(tid).get("berth_id", "")) != "", "tow dock 分配 berth")
	_eq(String(s.undock(tid).get("status", "")), "DEPARTED", "tow departed")
	_eq(int((s.port_summary("p1").get("resources", {}) as Dictionary).get("tugs_free", -1)), 1,
		"tow 离港释放 tug")
	var rp: Dictionary = s.permit(tw2id)
	_eq(String(rp.get("status", "")), "GRANTED", "tug 释放后第二拖曳 grant")
	# shuttle：permit 占泊位
	var sh: Dictionary = s.shuttle("shuttle_ship", "p1", {"clearance": "C-S"})
	var sid := String(sh.get("request_id", ""))
	_eq(String(s.permit(sid).get("status", "")), "GRANTED", "shuttle grant")
	_ok(String(s.get_request(sid).get("berth_id", "")) != "", "shuttle 分配 berth")
	_eq(String(s.approach(sid).get("status", "")), "APPROACH", "shuttle approach")
	_eq(String(s.dock(sid).get("status", "")), "DOCKED", "shuttle docked")
	_eq(String(s.undock(sid).get("status", "")), "DEPARTED", "shuttle departed")
	_ok(bool(s.check_contracts().get("ok", false)), "tow/shuttle contracts ok")
	_data_line("tow_shuttle", "tow 占 tug→dock 分配泊位→释放 · shuttle 占泊位 · 容量 HOLD")

# ═══════════════════════════════════════════════════════════════════
# 7. 队列 / 窗口 / tick / 过期
# ═══════════════════════════════════════════════════════════════════

func _test_queue_expiry() -> void:
	_section_begin("7 队列/窗口/tick")
	var s = _new_port()
	# 优先级排序：低优先级先建，高优先级后建
	var low: Dictionary = s.request("dock", "low", "p1", {"clearance": "C-L", "priority": 1})
	var high: Dictionary = s.request("dock", "high", "p1", {"clearance": "C-H", "priority": 9})
	var mid: Dictionary = s.request("dock", "mid", "p1", {"clearance": "C-M", "priority": 5})
	var q: Array = s.queue()
	_eq(q.size(), 3, "queue 3")
	_eq(String((q[0] as Dictionary).get("request_id", "")), String(high.get("request_id", "")),
		"优先级最高排第一")
	_eq(String((q[1] as Dictionary).get("request_id", "")), String(mid.get("request_id", "")),
		"优先级次高第二")
	_eq(String((q[2] as Dictionary).get("request_id", "")), String(low.get("request_id", "")),
		"低优先级最后")
	# tick 不自动 grant/dock/service
	var tk: Dictionary = s.tick(1.0)
	_eq(bool(tk.get("ok", false)), true, "tick ok")
	_eq(int((tk.get("no_auto", {}) as Dictionary).get("granted", -1)), 0, "tick 不自动 grant")
	_eq(int((tk.get("no_auto", {}) as Dictionary).get("docked", -1)), 0, "tick 不自动 dock")
	_eq(String(s.get_request(String(high.get("request_id", ""))).get("status", "")),
		"REQUESTED", "tick 后仍 REQUESTED")
	_near(s.t_s, 1.0, 1.0e-9, "tick 推进时间")
	_eq(String(s.tick(-1.0).get("reason", "")), "invalid_dt", "负 dt 拒绝")
	_eq(String(s.tick(NAN).get("reason", "")), "invalid_dt", "NaN dt 拒绝")
	# 过期：expire_in
	var s2 = _new_port()
	var er: Dictionary = s2.request("dock", "exp", "p1", {"clearance": "C-E",
		"expire_in": 5.0})
	var eid := String(er.get("request_id", ""))
	s2.tick(2.0)
	_eq(String(s2.get_request(eid).get("status", "")), "REQUESTED", "到期前仍 REQUESTED")
	s2.tick(5.0)
	_eq(String(s2.get_request(eid).get("status", "")), "DENIED", "到期后 DENIED")
	_eq(String(s2.get_request(eid).get("reason", "")), "window_expired", "window_expired")
	# 燃料补充（资源，不是自动服务）
	var cfg := _cfg()
	(cfg["ports"][1] as Dictionary)["fuel_capacity_t"] = 200.0
	(cfg["ports"][1] as Dictionary)["fuel_refill_per_s"] = 10.0
	var s3 = PortService.new(cfg)
	s3.tick(5.0)
	_near(float(s3.port_summary("p2").get("resources", {}).get("fuel_available_t", 0.0)),
		150.0, 1.0e-9, "燃料按 tick 补充")
	# 全局容量摘要
	_ok(s.summary().get("resources", {}).get("berths_total", 0) == 3, "全局容量摘要")
	_data_line("queue", "优先级排序 · tick 不自动 · expire→DENIED · 燃料补充 · 全局容量")

# ═══════════════════════════════════════════════════════════════════
# 8. 存档
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("8 存档")
	var s = _new_port()
	var d := _docked(s, "ship1", "p1")
	var rid := String(d.get("request_id", ""))
	s.refuel(rid, 50.0)   # SERVICING + fuel consumed
	var save := s.save_state()
	var parsed = JSON.parse_string(save)
	_ok(parsed is Dictionary, "save JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.port_service_save.v1",
			"save schema")
		_ok((parsed as Dictionary).get("ports") is Dictionary, "save ports")
		_ok((parsed as Dictionary).get("requests") is Dictionary, "save requests")
		_eq((parsed as Dictionary).get("requests", {}).size(), 1, "save requests 1")
	var s2 = PortService.new(_cfg())
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_ok(_norm_json(s.vm()) == _norm_json(s2.vm()), "load 后 VM 一致")
	_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(s2.save_state())),
		"load 后再次 save 一致")
	_eq(String(s2.get_request(rid).get("status", "")), "SERVICING", "load 保留 SERVICING")
	_near(float(s2.port_summary("p1").get("resources", {}).get("fuel_available_t", 0.0)),
		float(s.port_summary("p1").get("resources", {}).get("fuel_available_t", 0.0)),
		1.0e-9, "load 燃料一致")
	s2.finish_service(rid)
	_eq(String(s2.undock(rid).get("status", "")), "DEPARTED", "load 后继续 finish/undock")
	_ok(bool(s2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# 非法存档拒绝且不改状态
	var before := _state_core(s2)
	for bad in ["", "{bad", JSON.stringify({"schema": "bad"}),
			JSON.stringify({"schema": "v17.port_service_save.v1", "version": "9.9.9"}),
			JSON.stringify({"schema": "v17.port_service_save.v1", "version": "1.0.0",
				"ports": [], "requests": {}}),
			JSON.stringify({"schema": "v17.port_service_save.v1", "version": "1.0.0",
				"ports": {"p1": {"berth_state": {}, "tug_state": {},
					"fuel_available_t": -1.0}}, "requests": {}})]:
		var br: Dictionary = s2.load_state(String(bad))
		_eq(bool(br.get("ok", true)), false, "非法存档拒绝：" + String(bad).substr(0, 36))
	_eq(_state_core(s2), before, "非法存档不改状态")
	_data_line("save_load", "save/load VM 一致 · 继续服务/离港 · 非法存档拒绝")

# ═══════════════════════════════════════════════════════════════════
# 9. 事件 / JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_events_json() -> void:
	_section_begin("9 事件/JSON/确定性")
	var bus = EventBus.new()
	var s = _new_port(bus)
	var d := _docked(s, "ship1", "p1")
	var rid := String(d.get("request_id", ""))
	s.refuel(rid, 10.0)
	s.finish_service(rid)
	s.repair(rid)
	s.finish_service(rid)
	s.undock(rid)
	var kinds: Array = []
	for raw in s.events:
		kinds.append(String((raw as Dictionary).get("kind", "")))
		_ok(String((raw as Dictionary).get("schema", "")) == "port_event.v1", "事件 schema")
		_ok(bool((raw as Dictionary).get("writes_v15", true)) == false, "事件不写 v15")
	for k in ["port.request_created", "port.request_granted", "port.approach",
			"port.docked", "port.service_started", "port.service_finished",
			"port.departed"]:
		_ok(k in kinds, "事件存在：" + k)
	_ok(s.events_since(3).size() < s.events.size(), "events_since 过滤")
	var tk := s.take_events()
	_ok(tk.size() > 0, "take_events")
	_eq(s.events.size(), 0, "take 后 events 空")
	_ok(bus.current_seq() > 0, "EventBus 收到事件")
	# JSON / VM
	var vm: Dictionary = s.vm()
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "vm JSON 可解析")
	_ok(vm.get("summary") is Dictionary, "vm summary")
	_ok(vm.get("queue") is Array, "vm queue")
	# 确定性：两实例同操作
	var a = PortService.new(_cfg())
	var b = PortService.new(_cfg())
	for sv in [a, b]:
		var r: Dictionary = sv.request("dock", "ship1", "p1", {"clearance": "C"})
		var xid := String(r.get("request_id", ""))
		sv.permit(xid)
		sv.approach(xid)
		sv.dock(xid)
		sv.refuel(xid, 20.0)
		sv.finish_service(xid)
		sv.undock(xid)
	_ok(_norm_json(a.vm()) == _norm_json(b.vm()), "同操作 vm 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("events_json", "事件序列·EventBus·vm JSON·同操作确定性")
