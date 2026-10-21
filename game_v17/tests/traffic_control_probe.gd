extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# TRAFFIC CONTROL PROBE · 完整游戏-阶段3Z
#
# 验证：设施扩展（OTC/储罐/加注，保留旧 29/57）、航道数据/容量/窗口/
# 方向/优先级/OTC 监视、申请/许可/排队/占用/释放、NPC 占用、伪装/
# 识破/线索、存档/JSON/确定性；不写 world/TrackTable/UI。只跑一次。
# ═══════════════════════════════════════════════════════════════════

const Traffic := preload("res://scripts/core/traffic_control_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("TRAFFIC CONTROL PROBE · 完整游戏-阶段3Z")
	print("════════════════════════════════════════════════════════════════")
	_test_data()
	_test_lanes()
	_test_clearance_flow()
	_test_windows_capacity_npc()
	_test_disguise_clues()
	_test_save_load_json()
	print("────────────────────────────────────────────────────────────────")
	print("TRAFFIC CONTROL PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("TRAFFIC CONTROL PROBE FAILED")
		quit(1)
	else:
		print("TRAFFIC CONTROL PROBE OK")
		quit(0)


# ── helpers ──────────────────────────────────────────────────

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[FAIL] ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _json_ok(v: Variant) -> bool:
	var s := JSON.stringify(v)
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref") \
		and not s.contains("Vector3")


func _service() -> Object:
	return Traffic.new()


func _events(s, kind: String) -> int:
	var n := 0
	for raw in (s.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _lane_endpoint_ok(s, lane: Dictionary, key: String) -> bool:
	var e: Dictionary = lane.get(key, {}) if lane.get(key) is Dictionary else {}
	var eid := String(e.get("id", ""))
	return eid != "" and (bool(s.facilities.has(eid)) or bool(s.clusters.has(eid)) or bool(s.orbital_nodes.has(eid)))


# ── 1. 数据量 / 设施扩展 ─────────────────────────────────────

func _test_data() -> void:
	print("")
	print("── 1. 设施扩展数据 / OTC / 储罐 / 加注 ──")
	var s = _service()
	_ok(bool(s.ready), "service ready", str(s.errors))
	_ok((s.errors as Array).is_empty(), "setup 无错误")
	_eq(int((s.facilities as Dictionary).size()), 110, "合并设施 110")
	_eq(int((s.otc_satellites as Array).size()), 19, "OTC 19")
	_eq(int((s.fuel_facilities as Array).size()), 62, "TNK+FUL 62")
	_eq(int((s.clusters as Dictionary).size()), 7, "旧 clusters 7")
	_eq(int((s.orbital_nodes as Dictionary).size()), 2, "orbital nodes 2")
	var old_count := 0
	var old_ports := 0
	for raw in s.facilities_list:
		var f: Dictionary = s.facility(String(raw))
		if String(f.get("_source", "")) == "facilities":
			old_count += 1
			old_ports += (f.get("ports", []) as Array).size()
	_eq(old_count, 29, "旧 facilities 29 保留")
	_eq(old_ports, 57, "旧 ports 57 保留")
	for fid in ["L1-01", "L1-05", "NESOSS-01", "LUNSYNC-03"]:
		_ok(not s.facility(fid).is_empty(), "旧设施 " + fid)
	var exp_otc := {"L1_MERIDIAN": 2, "L2_KARMAN": 2, "L3_ALBORADA": 1,
		"L4_ANVIL": 2, "L5_NEW_LAGOS": 2, "NESOSS": 3, "LEO": 3, "FAR": 2,
		"LUNSYNC": 2}
	for cid in exp_otc.keys():
		var otc: Array = s.otc_for(String(cid))
		_eq(otc.size(), int(exp_otc[cid]), "OTC 数量 " + String(cid))
		_ok(otc.size() > 0, "OTC 存在 " + String(cid))
		var tank := 0
		var fuel := 0
		for fid2 in s.facilities.keys():
			var f2: Dictionary = s.facilities[fid2]
			if String(f2.get("parent_cluster", "")) == String(cid):
				if String(f2.get("facility_class", "")) == "tank":
					tank += 1
				elif String(f2.get("facility_class", "")) == "fuel":
					fuel += 1
		_ok(tank >= 1, "TNK " + String(cid), str(tank))
		_ok(fuel >= 1, "FUL " + String(cid), str(fuel))
	# OTC 字段/物理
	var o: Dictionary = s.otc_for("L1_MERIDIAN")[0]
	_eq(String(o.get("facility_class", "")), "otc", "OTC class")
	_eq(String(o.get("transponder_type", "")), "otc", "OTC transponder type")
	_ok((o.get("services", []) as Array).has("traffic_control"), "OTC services")
	_ok((o.get("ports", []) as Array).size() > 0, "OTC port")
	_ok((o.get("physical", {}) as Dictionary).has("orbit"), "OTC orbit")
	_ok(float((o.get("physical", {}) as Dictionary).get("period_s", 0.0)) > 0.0, "OTC period")
	_ok(float((o.get("physical", {}) as Dictionary).get("mass_kg", 0.0)) > 0.0, "OTC mass")
	_ok((o.get("physical", {}) as Dictionary).get("station_keeping", {}).has("mode"), "OTC station_keeping")
	# 燃料设施
	var tank_sample: Dictionary = {}
	var fuel_sample: Dictionary = {}
	for raw in s.fuel_facilities:
		if raw is Dictionary:
			if String((raw as Dictionary).get("facility_class", "")) == "tank" and tank_sample.is_empty():
				tank_sample = raw
			if String((raw as Dictionary).get("facility_class", "")) == "fuel" and fuel_sample.is_empty():
				fuel_sample = raw
	_ok(not tank_sample.is_empty(), "TNK sample")
	_ok(not fuel_sample.is_empty(), "FUL sample")
	_ok((tank_sample.get("services", []) as Array).has("storage"), "TNK services")
	_ok((fuel_sample.get("services", []) as Array).has("refuel"), "FUL services")
	_ok((fuel_sample.get("services", []) as Array).has("tankfarm"), "FUL tankfarm")
	_ok((tank_sample.get("ports", []) as Array).size() > 0, "TNK port")
	_ok((fuel_sample.get("ports", []) as Array).size() > 0, "FUL port")
	_ok((tank_sample.get("physical", {}) as Dictionary).has("period_s"), "TNK physical")
	# LEO/FAR nodes
	for nid in ["LEO", "FAR"]:
		var n: Dictionary = s.cluster(nid)
		_ok(not n.is_empty(), "orbital node " + nid)
		_ok(not s.otc_for(nid).is_empty(), "node OTC " + nid)
	# 唯一性
	var ids: Dictionary = {}
	var codes: Dictionary = {}
	var txps: Dictionary = {}
	var ports: Dictionary = {}
	var bad := 0
	for fid3 in s.facilities.keys():
		var f3: Dictionary = s.facilities[fid3]
		var id := String(f3.get("facility_id", ""))
		if ids.has(id): bad += 1
		ids[id] = true
		var code := String(f3.get("facility_code", ""))
		if codes.has(code): bad += 1
		codes[code] = true
		var txp := String(f3.get("transponder_code", ""))
		if txps.has(txp): bad += 1
		txps[txp] = true
		for raw_p in (f3.get("ports", []) as Array):
			if raw_p is Dictionary:
				var pid := String((raw_p as Dictionary).get("port_id", ""))
				if ports.has(pid): bad += 1
				ports[pid] = true
	_eq(bad, 0, "ID/code/transponder/port 唯一")
	_ok(ids.size() == 110, "设施 id 计数")
	_ok(codes.size() == 110, "设施 code 计数")
	_ok(txps.size() == 110, "应答机计数")
	_ok(ports.size() > 57, "端口总数扩展")
	_ok(_json_ok(s.summary()), "summary JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")


# ── 2. 航道 schema / 查询 ───────────────────────────────────

func _test_lanes() -> void:
	print("")
	print("── 2. 航道 / 容量 / 窗口 / 方向 / OTC 监视 ──")
	var s = _service()
	_eq(int((s.lanes as Dictionary).size()), 18, "18 航道")
	_eq(int((s.npc_ships as Dictionary).size()), 6, "6 NPC")
	_eq(int((s.npc_schedule as Array).size()), 6, "6 NPC 占用示例")
	for lid in s.lanes_list:
		var lane: Dictionary = s.lane(String(lid))
		_ok(not lane.is_empty(), "lane 存在 " + String(lid))
		_ok(int(lane.get("capacity", 0)) > 0, "capacity " + String(lid))
		_ok(String(lane.get("direction", "")) in ["inbound", "outbound", "bidirectional"],
			"direction " + String(lid))
		var pr := int(lane.get("priority", 0))
		_ok(pr >= 1 and pr <= 5, "priority " + String(lid), str(pr))
		_ok((lane.get("windows", []) as Array).size() > 0, "windows " + String(lid))
		_ok((lane.get("monitor_otc", []) as Array).size() > 0, "monitor_otc " + String(lid))
		_ok(_lane_endpoint_ok(s, lane, "from"), "from 端点 " + String(lid))
		_ok(_lane_endpoint_ok(s, lane, "to"), "to 端点 " + String(lid))
		var mon_ok := true
		for oid in (lane.get("monitor_otc", []) as Array):
			if not s.facilities.has(String(oid)):
				mon_ok = false
		_ok(mon_ok, "monitor OTC 存在 " + String(lid))
		var occ: Dictionary = s.lane_occupancy(String(lid))
		_eq(int(occ.get("capacity", 0)), int(lane.get("capacity", 0)), "occupancy capacity " + String(lid))
		_eq(int(occ.get("free", -1)), int(lane.get("capacity", 0)), "初始 free " + String(lid))
	for cid in ["L1_MERIDIAN", "L2_KARMAN", "L3_ALBORADA", "L4_ANVIL",
			"L5_NEW_LAGOS", "NESOSS", "LEO", "FAR", "LUNSYNC"]:
		_ok((s.lanes_for(String(cid)) as Array).size() >= 1, "cluster lanes " + String(cid))
		_ok((s.otc_for(String(cid)) as Array).size() >= 1, "cluster OTC " + String(cid))
	_ok(_json_ok(s.vm()), "lanes VM JSON")
	_ok(String((s.vm().get("schema", ""))) == "traffic_control.v1", "VM schema")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")


# ── 3. 申请/许可/占用/释放 ─────────────────────────────────

func _test_clearance_flow() -> void:
	print("")
	print("── 3. 申请 / 许可 / 占用 / 释放 ──")
	var s = _service()
	var req: Dictionary = s.request_clearance("TRK-1", "LANE-L1-IN-01", {"priority": 1})
	_ok(bool(req.get("ok", false)), "request ok", str(req.get("reason", "")))
	var rid := String(req.get("request_id", ""))
	_eq(String((req.get("request", {}) as Dictionary).get("status", "")), "PENDING", "request PENDING")
	_ok(rid != "", "request_id")
	_ok(_events(s, "otc_event") >= 1, "otc_event request")
	var perm: Dictionary = s.permit(rid)
	_ok(bool(perm.get("ok", false)), "permit ok", str(perm.get("reason", "")))
	var cid := String(perm.get("clearance_id", ""))
	_ok(cid != "", "clearance_id")
	_eq(String((perm.get("clearance", {}) as Dictionary).get("status", "")), "CLEARED", "CLEARED")
	_ok(_events(s, "otc_event") >= 2, "otc_event permit")
	var occ: Dictionary = s.occupy("LANE-L1-IN-01", "TRK-1", {"clearance_id": cid})
	_ok(bool(occ.get("ok", false)), "occupy ok", str(occ.get("reason", "")))
	var oid := String(occ.get("occupancy_id", ""))
	_ok(oid != "", "occupancy_id")
	var lo: Dictionary = s.lane_occupancy("LANE-L1-IN-01")
	_eq(int(lo.get("used", 0)), 1, "占用 used=1")
	_eq(int(lo.get("free", 0)), 1, "占用 free=1")
	_ok(_events(s, "lane_record") >= 1, "lane_record event")
	var rel: Dictionary = s.release("LANE-L1-IN-01", "TRK-1")
	_ok(bool(rel.get("ok", false)), "release ok")
	_eq(int(s.lane_occupancy("LANE-L1-IN-01").get("free", 0)), 2, "释放 free=2")
	_ok(not bool(s.release("LANE-L1-IN-01", "TRK-1").get("ok", true)), "重复 release false")
	# 非法
	_ok(not bool(s.request_clearance("", "LANE-L1-IN-01").get("ok", true)), "空 track false")
	_ok(not bool(s.request_clearance("T", "NOPE").get("ok", true)), "未知 lane false")
	_ok(not bool(s.request_clearance("T", "LANE-L1-IN-01", {"direction": "outbound"}).get("ok", true)),
		"方向不匹配 false")
	_ok(not bool(s.request_clearance("T", "LANE-L1-IN-01", {"facility_code": "FC-NOPE"}).get("ok", true)),
		"未知 facility false")
	_ok(not bool(s.request_clearance("T", "LANE-L1-IN-01", {"transponder_code": "TXP-NOPE"}).get("ok", true)),
		"未知 transponder false")
	_ok(not bool(s.permit("REQ-NOPE").get("ok", true)), "未知 permit false")
	_ok(not bool(s.occupy("LANE-L1-IN-01", "NO-CLEAR").get("ok", true)), "无 clearance occupy false")
	_ok(not bool(s.reject("REQ-NOPE").get("ok", true)), "未知 reject false")
	# reject
	var r2: Dictionary = s.request_clearance("TRK-R", "LANE-L1-IN-01")
	_ok(bool(s.reject(String(r2.get("request_id", "")), "denied").get("ok", false)), "reject ok")
	# direction/route
	var r3: Dictionary = s.request_clearance("TRK-3", "LANE-L1-IN-01",
		{"direction": "inbound", "facility_code": "FC-L1-01", "transponder_code": "TXP-L1-01"})
	_ok(bool(r3.get("ok", false)), "合法 facility/transponder 请求", str(r3.get("reason", "")))
	_ok(_json_ok(s.vm()), "flow VM JSON")


# ── 4. 窗口 / 容量排队 / NPC ───────────────────────────────

func _test_windows_capacity_npc() -> void:
	print("")
	print("── 4. 窗口 / 容量排队 / NPC 占用 ──")
	# 窗口关闭/重开
	var s = _service()
	_ok(bool(s.request_clearance("T0", "LANE-L1-MAINT-01").get("ok", false)), "窗口内请求")
	s.step(1000.0)
	var wc: Dictionary = s.request_clearance("T1", "LANE-L1-MAINT-01")
	_ok(not bool(wc.get("ok", true)), "窗口关闭 false")
	_eq(String(wc.get("reason", "")), "window_closed", "window_closed reason")
	_ok(float(wc.get("next_window_s", -1.0)) >= 3600.0, "next_window")
	s.step(2600.0)
	_ok(bool(s.request_clearance("T1", "LANE-L1-MAINT-01").get("ok", false)), "窗口重开请求")
	# 容量排队
	var s2 = _service()
	var q1: Dictionary = s2.request_clearance("A", "LANE-L1-TNK-01")
	var p1: Dictionary = s2.permit(String(q1.get("request_id", "")))
	_ok(bool(p1.get("ok", false)), "容量测试 permit 1")
	var o1: Dictionary = s2.occupy("LANE-L1-TNK-01", "A", {"clearance_id": String(p1.get("clearance_id", ""))})
	_ok(bool(o1.get("ok", false)), "容量测试 occupy 1")
	var q2: Dictionary = s2.request_clearance("B", "LANE-L1-TNK-01")
	var p2: Dictionary = s2.permit(String(q2.get("request_id", "")))
	_ok(not bool(p2.get("ok", true)), "容量满 permit false")
	_eq(String(p2.get("reason", "")), "capacity_full", "capacity_full reason")
	_eq(int(p2.get("queue_pos", 0)), 1, "queue_pos")
	_ok(bool(s2.release("LANE-L1-TNK-01", "A").get("ok", false)), "释放容量")
	var p3: Dictionary = s2.permit(String(q2.get("request_id", "")))
	_ok(bool(p3.get("ok", false)), "释放后 permit 成功", str(p3.get("reason", "")))
	# NPC 定时
	var s3 = _service()
	s3.step(0.0)
	_ok(int((s3.active_npc as Dictionary).size()) >= 1, "NPC 定时激活")
	var npc_occ := false
	for oid in s3.active_npc.keys():
		if String((s3.active_npc[oid] as Dictionary).get("lane_id", "")) == "LANE-L1-IN-01":
			npc_occ = true
	_ok(npc_occ, "LANE-L1 NPC 占用")
	_ok((s3.lane_occupancy("LANE-L1-IN-01").get("occupancies", []) as Array).size() >= 1,
		"lane occupancy 含 NPC")
	# 手动 NPC
	var s4 = _service()
	var n1: Dictionary = s4.npc_occupy("LANE-L1-TNK-01", "NPC-TANKER-01", {"duration_s": 100.0})
	_ok(bool(n1.get("ok", false)), "npc_occupy ok")
	_ok(not bool(s4.npc_occupy("LANE-L1-TNK-01", "NPC-NOPE").get("ok", true)), "未知 NPC false")
	_ok(not bool(s4.npc_occupy("LANE-L1-TNK-01", "NPC-TANKER-01").get("ok", true)), "NPC 容量/重复 false")
	_ok(bool(s4.npc_release("LANE-L1-TNK-01", "NPC-TANKER-01").get("ok", false)), "npc_release ok")
	_ok(not bool(s4.npc_release("LANE-L1-TNK-01", "NPC-TANKER-01").get("ok", true)), "重复 npc_release false")
	# 过期 clearance
	var s5 = _service()
	var rq: Dictionary = s5.request_clearance("EXP", "LANE-L1-IN-01")
	var pp: Dictionary = s5.permit(String(rq.get("request_id", "")))
	s5.step(400.0)
	var oc: Dictionary = s5.occupy("LANE-L1-IN-01", "EXP", {"clearance_id": String(pp.get("clearance_id", ""))})
	_ok(not bool(oc.get("ok", true)), "过期 clearance occupy false")
	_ok(_json_ok(s3.vm()), "NPC VM JSON")


# ── 5. 伪装 / 识破 / 线索 ──────────────────────────────────

func _test_disguise_clues() -> void:
	print("")
	print("── 5. 伪装 / 识破 / 线索 ──")
	var s = _service()
	var good: Dictionary = s.record_disguise("TRK-D1", {
		"transponder_code": "TXP-L1-01", "facility_code": "FC-L1-01",
		"claimed_class": "traffic_control", "lane_id": "LANE-L1-IN-01"})
	_ok(bool(good.get("ok", false)), "合法伪装可记录")
	_ok(String(good.get("disguise_id", "")) != "", "disguise_id")
	_ok(float(good.get("probability", -1.0)) >= 0.0, "probability")
	_ok(float(good.get("roll", -1.0)) >= 0.0, "roll")
	_ok((good.get("anomalies", []) as Array).is_empty(), "合法无异常", str(good.get("anomalies", [])))
	# 未知 transponder
	var bad1: Dictionary = s.record_disguise("TRK-BAD1", {
		"transponder_code": "TXP-NOPE", "facility_code": "FC-L1-01",
		"lane_id": "LANE-L1-IN-01"})
	_ok(bool(bad1.get("ok", false)), "未知 transponder 记录")
	_ok((bad1.get("anomalies", []) as Array).has("transponder_anomaly"), "transponder_anomaly")
	# 未知 facility
	var bad2: Dictionary = s.record_disguise("TRK-BAD2", {
		"transponder_code": "TXP-L1-01", "facility_code": "FC-NOPE",
		"lane_id": "LANE-L1-IN-01"})
	_ok((bad2.get("anomalies", []) as Array).has("facility_mismatch"), "facility_mismatch")
	# route 不匹配
	var bad3: Dictionary = s.record_disguise("TRK-BAD3", {
		"transponder_code": "TXP-L1-01", "facility_code": "FC-L1-01",
		"lane_id": "NOPE"})
	_ok((bad3.get("anomalies", []) as Array).has("track_route_mismatch"), "route mismatch")
	# 强制识破
	var det: Dictionary = s.record_disguise("TRK-GHOST", {
		"transponder_code": "TXP-L2-02", "facility_code": "FC-L2-02",
		"claimed_class": "traffic_control", "lane_id": "LANE-L2-01"},
		{"force_detected": true})
	_ok(bool(det.get("detected", false)), "force detected")
	_eq(String((det.get("disguise", {}) as Dictionary).get("status", "")), "DETECTED", "DETECTED 状态")
	_ok((det.get("clue_ids", []) as Array).size() >= 1, "识破线索")
	var ghost := false
	for c in s.clues:
		if c is Dictionary and String((c as Dictionary).get("type", "")) == "ghost_track":
			ghost = true
	_ok(ghost, "ghost_track clue")
	var gclue: Dictionary = {}
	for c2 in s.clues:
		if c2 is Dictionary and String((c2 as Dictionary).get("type", "")) == "ghost_track":
			gclue = c2
			break
	_ok(bool(gclue.get("requires_investigation", false)), "clue 需调查")
	_ok(not bool(gclue.get("produces_contact", true)), "clue 不产生 contact")
	_ok(not bool(gclue.get("writes_v15", true)), "clue 不写 V15")
	_ok(String(gclue.get("clue_id", "")) != "", "clue_id")
	_ok((s.clues_for("TRK-GHOST") as Array).size() >= 1, "clues_for track")
	_ok(not (s.clue(String(gclue.get("clue_id", ""))) as Dictionary).is_empty(), "clue by id")
	# 历史不一致
	var h1: Dictionary = s.record_disguise("TRK-HIST", {"transponder_code": "TXP-L1-01",
		"facility_code": "FC-L1-01", "lane_id": "LANE-L1-IN-01"}, {"force_detected": false})
	_ok(bool(h1.get("ok", false)), "history 1")
	var h2: Dictionary = s.record_disguise("TRK-HIST", {"transponder_code": "TXP-L2-02",
		"facility_code": "FC-L2-02", "lane_id": "LANE-L2-01"}, {"force_detected": false})
	_ok((h2.get("anomalies", []) as Array).has("track_history_mismatch"), "历史不一致异常")
	# 记录/事件
	_ok((s.records_for("TRK-GHOST") as Array).size() >= 1, "records_for track")
	_ok(_events(s, "lane_record") >= 1, "disguise lane_record")
	_ok(_json_ok(s.vm()), "disguise VM JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")


# ── 6. 存档 / JSON / 确定性 ────────────────────────────────

func _test_save_load_json() -> void:
	print("")
	print("── 6. save/load / JSON / 确定性 ──")
	var s = _service()
	var rq: Dictionary = s.request_clearance("TRK-S", "LANE-L1-IN-01")
	var pp: Dictionary = s.permit(String(rq.get("request_id", "")))
	s.occupy("LANE-L1-IN-01", "TRK-S", {"clearance_id": String(pp.get("clearance_id", ""))})
	s.record_disguise("TRK-S", {"transponder_code": "TXP-L1-01", "facility_code": "FC-L1-01",
		"lane_id": "LANE-L1-IN-01"}, {"force_detected": true})
	s.step(10.0)
	var text: String = s.save_state()
	var p = JSON.parse_string(text)
	_ok(p is Dictionary, "save JSON")
	_ok(String((p as Dictionary).get("schema", "")) == "v17.traffic_control_save.v1", "save schema")
	_ok(String((p as Dictionary).get("version", "")) == "1.0.0", "save version")
	_ok((p as Dictionary).get("requests") is Array, "save requests")
	_ok((p as Dictionary).get("clues") is Array, "save clues")
	var r = _service()
	var lr: Dictionary = r.load_state(text)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("reason", "")))
	_ok((r.requests as Dictionary).size() == (s.requests as Dictionary).size(), "load requests")
	_ok((r.occupancies as Dictionary).size() == (s.occupancies as Dictionary).size(), "load occupancies")
	_ok((r.clues as Array).size() == (s.clues as Array).size(), "load clues")
	_ok((r.records as Array).size() == (s.records as Array).size(), "load records")
	_ok(absf(float(r.t) - float(s.t)) < 1.0e-9, "load t")
	_ok(_json_ok(r.vm()), "loaded VM JSON")
	_ok(s.save_state() == s.save_state(), "save 确定性")
	var bad: Array = [["empty", ""], ["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future", JSON.stringify({"schema": "v17.traffic_control_save.v1",
			"version": "9.0.0", "requests": [], "clearances": [], "occupancies": [],
			"active_npc": [], "disguises": [], "clues": [], "records": [], "events": []})],
		["missing", JSON.stringify({"schema": "v17.traffic_control_save.v1", "version": "1.0.0"})]]
	for raw in bad:
		var c: Array = raw
		_ok(not bool(r.load_state(c[1]).get("ok", true)), "拒绝快照: " + String(c[0]))
	# 双实例确定性
	var a = _service()
	var b = _service()
	for svc in [a, b]:
		var q: Dictionary = svc.request_clearance("T", "LANE-L1-IN-01")
		svc.permit(String(q.get("request_id", "")))
		svc.record_disguise("T", {"transponder_code": "TXP-L1-01",
			"facility_code": "FC-L1-01", "lane_id": "LANE-L1-IN-01"}, {"force_detected": true})
		svc.step(1.0)
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(_json_ok(a.summary()), "summary JSON")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "最终不写 world")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "最终不写 TrackTable")
