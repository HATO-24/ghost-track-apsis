class_name V2TrafficControlService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3Z · OTC 交通管制 / 航道 / 伪装线索服务
#
# 数据：
#   facilities_system.json（现有 29 设施/57 端口 + otc_satellites/
#   fuel_facilities/orbital_nodes 扩展；不破坏 FacilityRegistry 旧契约）
#   lanes_system.json（lane_id/端点/容量/窗口/方向/优先级/NPC/OTC 监视）
#
# 职责：设施/OTC/航道校验 → 申请/许可/排队/占用/释放 → NPC 占用航道
#       → record_disguise（伪造 transponder/facility/track/route）→
#       lane_record/otc_event/clue；不写 world/TrackTable/UI。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_FACILITIES := "res://framework/content/facilities_system.json"
const DEFAULT_LANES := "res://framework/content/lanes_system.json"
const SCHEMA_FAC := "v17.facilities_system.v1"
const SCHEMA_LANES := "v17.lanes_system.v1"
const SCHEMA_VM := "traffic_control.v1"
const SCHEMA_LANE_RECORD := "lane_record.v1"
const SCHEMA_EVENT := "traffic_event.v1"
const SCHEMA_CLUE := "traffic_clue.v1"
const SAVE_SCHEMA := "v17.traffic_control_save.v1"
const SAVE_VERSION := "1.0.0"
const DIRECTIONS := ["inbound", "outbound", "bidirectional"]
const CLUE_TYPES := ["lane_conflict", "npc_conflict", "window_closed",
	"capacity_exceeded", "transponder_anomaly", "facility_mismatch",
	"track_route_mismatch", "ghost_track", "otc_gap", "direction_mismatch"]
const MAX_EVENTS := 600
const MAX_CLUES := 200
const MAX_RECORDS := 500

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var errors: Array = []
var warnings: Array = []
var config: Dictionary = {}

var facilities: Dictionary = {}
var facilities_list: Array = []
var clusters: Dictionary = {}
var orbital_nodes: Dictionary = {}
var otc_satellites: Array = []
var fuel_facilities: Array = []
var lanes: Dictionary = {}
var lanes_list: Array = []
var npc_ships: Dictionary = {}
var npc_schedule: Array = []

var requests: Dictionary = {}
var clearances: Dictionary = {}
var occupancies: Dictionary = {}
var active_npc: Dictionary = {}
var disguises: Dictionary = {}
var clues: Array = []
var records: Array = []
var events: Array = []

var _seq_req := 0
var _seq_clear := 0
var _seq_occ := 0
var _seq_disg := 0
var _seq_clue := 0
var _seq_event := 0
var _outbox: Array = []


func _init(cfg := {}) -> void:
	setup(cfg)


# ── setup / load ─────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	facilities = {}
	facilities_list = []
	clusters = {}
	orbital_nodes = {}
	otc_satellites = []
	fuel_facilities = []
	lanes = {}
	lanes_list = []
	npc_ships = {}
	npc_schedule = []
	requests = {}
	clearances = {}
	occupancies = {}
	active_npc = {}
	disguises = {}
	clues = []
	records = []
	events = []
	_outbox = []
	_seq_req = 0
	_seq_clear = 0
	_seq_occ = 0
	_seq_disg = 0
	_seq_clue = 0
	_seq_event = 0
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	var fac_data: Variant = null
	if config.get("facilities_content") is Dictionary:
		fac_data = config.get("facilities_content")
	else:
		var fpath := String(config.get("facilities_path", DEFAULT_FACILITIES))
		fac_data = _read_json(fpath)
		if fac_data == null:
			errors.append("facilities content 不可读/JSON 无效: " + fpath)
	var lanes_data: Variant = null
	if config.get("lanes_content") is Dictionary:
		lanes_data = config.get("lanes_content")
	else:
		var lpath := String(config.get("lanes_path", DEFAULT_LANES))
		lanes_data = _read_json(lpath)
		if lanes_data == null:
			errors.append("lanes content 不可读/JSON 无效: " + lpath)
	if not errors.is_empty():
		return false
	var fv := _validate_facilities(fac_data)
	if not bool(fv.get("ok", false)):
		for e in (fv.get("errors", []) as Array):
			errors.append("facilities: " + String(e))
		return false
	var lv := _validate_lanes(lanes_data)
	if not bool(lv.get("ok", false)):
		for e in (lv.get("errors", []) as Array):
			errors.append("lanes: " + String(e))
		return false
	_apply_facilities(fac_data as Dictionary)
	_apply_lanes(lanes_data as Dictionary)
	var cross := _validate_cross()
	if not cross.is_empty():
		for e in cross:
			errors.append("cross: " + String(e))
		return false
	ready = true
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else null


# ── facilities validate/apply ────────────────────────────────

func _validate_facilities(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["必须为对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != SCHEMA_FAC:
		errs.append("schema 必须 " + SCHEMA_FAC)
	var cluster_ids: Dictionary = {}
	var cl_arr = d.get("clusters", null)
	if not (cl_arr is Array):
		errs.append("clusters 必须数组")
	else:
		for raw in (cl_arr as Array):
			if not (raw is Dictionary):
				errs.append("cluster 非对象")
				continue
			var cid := String((raw as Dictionary).get("cluster_id", ""))
			if cid == "":
				errs.append("cluster_id 为空")
			elif cluster_ids.has(cid):
				errs.append("cluster_id 重复: " + cid)
			cluster_ids[cid] = true
	var node_ids: Dictionary = {}
	var nodes = d.get("orbital_nodes", [])
	if nodes is Array:
		for raw in (nodes as Array):
			if raw is Dictionary and String((raw as Dictionary).get("cluster_id", "")) != "":
				node_ids[String((raw as Dictionary).get("cluster_id", ""))] = true
	var rows: Array = []
	for key in ["facilities", "otc_satellites", "fuel_facilities"]:
		var arr = d.get(key, [])
		if not (arr is Array):
			errs.append(key + " 必须数组")
			continue
		for raw in (arr as Array):
			if raw is Dictionary:
				rows.append(raw)
	var ids: Dictionary = {}
	var codes: Dictionary = {}
	var txps: Dictionary = {}
	var ports: Dictionary = {}
	var otc_by_cluster: Dictionary = {}
	var tank_by_cluster: Dictionary = {}
	var fuel_by_cluster: Dictionary = {}
	for raw in rows:
		var f: Dictionary = raw
		var fid := String(f.get("facility_id", ""))
		if fid == "": errs.append("facility_id 为空")
		elif ids.has(fid): errs.append("facility_id 重复: " + fid)
		ids[fid] = true
		var code := String(f.get("facility_code", ""))
		if code == "": errs.append("facility_code 为空: " + fid)
		elif codes.has(code): errs.append("facility_code 重复: " + code)
		codes[code] = true
		var txp := String(f.get("transponder_code", ""))
		if txp == "": errs.append("transponder_code 为空: " + fid)
		elif txps.has(txp): errs.append("transponder_code 重复: " + txp)
		txps[txp] = true
		var cls := String(f.get("facility_class", ""))
		var cid := String(f.get("parent_cluster", ""))
		if not (cid in cluster_ids or node_ids.has(cid)):
			errs.append("facility %s parent_cluster 不存在/非扩展节点: %s" % [fid, cid])
		if cls == "otc": otc_by_cluster[cid] = int(otc_by_cluster.get(cid, 0)) + 1
		elif cls == "tank": tank_by_cluster[cid] = int(tank_by_cluster.get(cid, 0)) + 1
		elif cls == "fuel": fuel_by_cluster[cid] = int(fuel_by_cluster.get(cid, 0)) + 1
		var ports_arr = f.get("ports", [])
		if not (ports_arr is Array) or (ports_arr as Array).is_empty():
			errs.append("facility %s ports 必须非空" % fid)
		else:
			for raw_p in (ports_arr as Array):
				if not (raw_p is Dictionary):
					errs.append("facility %s port 非对象" % fid)
					continue
				var pid := String((raw_p as Dictionary).get("port_id", ""))
				if pid == "": errs.append("facility %s port_id 空" % fid)
				elif ports.has(pid): errs.append("port_id 重复: " + pid)
				ports[pid] = true
		var ph = f.get("physical", null)
		if not (ph is Dictionary) or not ((ph as Dictionary).get("orbit") is Dictionary):
			errs.append("facility %s physical/orbit 缺失" % fid)
		else:
			for k in ["mass_kg", "radius_km", "cross_section_m2", "period_s"]:
				if not (ph as Dictionary).has(k) or float((ph as Dictionary).get(k, 0.0)) <= 0.0:
					errs.append("facility %s physical.%s 非法" % [fid, k])
	# OTC 数量（docs/20 §7.1）
	var otc_expected := {"L1_MERIDIAN": 2, "L2_KARMAN": 2, "L3_ALBORADA": 1,
		"L4_ANVIL": 2, "L5_NEW_LAGOS": 2, "NESOSS": 3, "LEO": 3, "FAR": 2,
		"LUNSYNC": 2}
	for cid in otc_expected.keys():
		if int(otc_by_cluster.get(cid, 0)) != int(otc_expected[cid]):
			errs.append("OTC 数量不符 %s: %d/%d" % [cid, int(otc_by_cluster.get(cid, 0)),
				int(otc_expected[cid])])
	for cid in cluster_ids.keys():
		if int(tank_by_cluster.get(cid, 0)) < 1:
			errs.append("cluster %s 缺 TNK" % cid)
		if int(fuel_by_cluster.get(cid, 0)) < 1:
			errs.append("cluster %s 缺 FUL" % cid)
	for cid in node_ids.keys():
		if int(tank_by_cluster.get(cid, 0)) < 1:
			errs.append("orbital node %s 缺 TNK" % cid)
		if int(fuel_by_cluster.get(cid, 0)) < 1:
			errs.append("orbital node %s 缺 FUL" % cid)
	return {"ok": errs.is_empty(), "errors": errs}


func _apply_facilities(d: Dictionary) -> void:
	clusters = {}
	for raw in (d.get("clusters", []) as Array):
		if raw is Dictionary:
			clusters[String((raw as Dictionary).get("cluster_id", ""))] = (raw as Dictionary).duplicate(true)
	orbital_nodes = {}
	for raw in (d.get("orbital_nodes", []) as Array) if d.get("orbital_nodes") is Array else []:
		if raw is Dictionary:
			orbital_nodes[String((raw as Dictionary).get("cluster_id", ""))] = (raw as Dictionary).duplicate(true)
	otc_satellites = []
	fuel_facilities = []
	facilities = {}
	facilities_list = []
	for key in ["facilities", "otc_satellites", "fuel_facilities"]:
		var arr = d.get(key, []) if d.get(key) is Array else []
		for raw in arr:
			if not (raw is Dictionary):
				continue
			var f: Dictionary = (raw as Dictionary).duplicate(true)
			f["_source"] = key
			var fid := String(f.get("facility_id", ""))
			facilities[fid] = f
			facilities_list.append(fid)
			if String(f.get("facility_class", "")) == "otc":
				otc_satellites.append(f.duplicate(true))
			elif String(f.get("facility_class", "")) in ["tank", "fuel"]:
				fuel_facilities.append(f.duplicate(true))


# ── lanes validate/apply ─────────────────────────────────────

func _validate_cross() -> Array:
	var errs: Array = []
	for lid in lanes_list:
		var lane: Dictionary = lanes[lid]
		var cid := String(lane.get("cluster_id", ""))
		if not (clusters.has(cid) or orbital_nodes.has(cid)):
			errs.append("lane %s cluster 不存在: %s" % [lid, cid])
		for ep in ["from", "to"]:
			var e: Dictionary = lane.get(ep, {}) if lane.get(ep) is Dictionary else {}
			var eid := String(e.get("id", ""))
			if eid == "":
				continue
			if not (facilities.has(eid) or clusters.has(eid) or orbital_nodes.has(eid)):
				errs.append("lane %s %s 端点不存在: %s" % [lid, ep, eid])
		for oid in (lane.get("monitor_otc", []) as Array):
			if not facilities.has(String(oid)):
				errs.append("lane %s monitor_otc 不存在: %s" % [lid, String(oid)])
			elif String((facilities[String(oid)] as Dictionary).get("facility_class", "")) != "otc":
				errs.append("lane %s monitor_otc 非 OTC: %s" % [lid, String(oid)])
	for raw in npc_schedule:
		if raw is Dictionary:
			var s: Dictionary = raw
			if not lanes.has(String(s.get("lane_id", ""))):
				errs.append("npc occupancy lane 不存在: " + String(s.get("lane_id", "")))
			var nid := String(s.get("npc_id", ""))
			if nid != "" and not npc_ships.has(nid):
				errs.append("npc occupancy npc 不存在: " + nid)
	return errs
func _validate_lanes(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["必须为对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != SCHEMA_LANES:
		errs.append("schema 必须 " + SCHEMA_LANES)
	var arr = d.get("lanes", null)
	if not (arr is Array) or (arr as Array).is_empty():
		errs.append("lanes 必须非空数组")
		return {"ok": false, "errors": errs}
	var ids: Dictionary = {}
	for raw in (arr as Array):
		if not (raw is Dictionary):
			errs.append("lane 非对象")
			continue
		var lane: Dictionary = raw
		var lid := String(lane.get("lane_id", ""))
		if lid == "": errs.append("lane_id 为空")
		elif ids.has(lid): errs.append("lane_id 重复: " + lid)
		ids[lid] = true
		for ep in ["from", "to"]:
			var e = lane.get(ep, null)
			if not (e is Dictionary):
				errs.append("lane %s %s 端点缺失" % [lid, ep])
			else:
				var eid := String((e as Dictionary).get("id", ""))
				if eid == "": errs.append("lane %s 端点为���" % lid)
		if int(lane.get("capacity", 0)) <= 0:
			errs.append("lane %s capacity 必须 >0" % lid)
		if not (String(lane.get("direction", "")) in DIRECTIONS):
			errs.append("lane %s direction 非法" % lid)
		if int(lane.get("priority", 0)) < 1 or int(lane.get("priority", 0)) > 5:
			errs.append("lane %s priority 非法" % lid)
		var wins = lane.get("windows", null)
		if not (wins is Array) or (wins as Array).is_empty():
			errs.append("lane %s windows 必须非空" % lid)
		else:
			for raw_w in (wins as Array):
				if not (raw_w is Dictionary) or float((raw_w as Dictionary).get("close_t", 0.0)) <= float((raw_w as Dictionary).get("open_t", 0.0)):
					errs.append("lane %s window 非法" % lid)
		var mon = lane.get("monitor_otc", null)
		if not (mon is Array) or (mon as Array).is_empty():
			errs.append("lane %s monitor_otc 必须非空" % lid)
	var npc = d.get("npc_occupancy", [])
	if npc is Array:
		for raw in (npc as Array):
			if not (raw is Dictionary):
				continue
			var lid2 := String((raw as Dictionary).get("lane_id", ""))
			if not ids.has(lid2):
				errs.append("npc occupancy lane 不存在: " + lid2)
			if float((raw as Dictionary).get("t_end", 0.0)) <= float((raw as Dictionary).get("t_start", 0.0)):
				errs.append("npc occupancy 时间非法")
	return {"ok": errs.is_empty(), "errors": errs}


func _apply_lanes(d: Dictionary) -> void:
	lanes = {}
	lanes_list = []
	for raw in (d.get("lanes", []) as Array):
		if not (raw is Dictionary):
			continue
		var lane: Dictionary = (raw as Dictionary).duplicate(true)
		lanes[String(lane.get("lane_id", ""))] = lane
		lanes_list.append(String(lane.get("lane_id", "")))
	npc_ships = {}
	for raw in (d.get("npc_ships", []) as Array) if d.get("npc_ships") is Array else []:
		if raw is Dictionary:
			npc_ships[String((raw as Dictionary).get("npc_id", ""))] = (raw as Dictionary).duplicate(true)
	npc_schedule = []
	for raw in (d.get("npc_occupancy", []) as Array) if d.get("npc_occupancy") is Array else []:
		if raw is Dictionary:
			npc_schedule.append((raw as Dictionary).duplicate(true))


# ── 查询 ────────────────────────────────────────────────────

func facility(id: String) -> Dictionary:
	return (facilities.get(id, {}) as Dictionary).duplicate(true) if facilities.get(id) is Dictionary else {}


func lane(id: String) -> Dictionary:
	return (lanes.get(id, {}) as Dictionary).duplicate(true) if lanes.get(id) is Dictionary else {}


func cluster(id: String) -> Dictionary:
	if clusters.has(id):
		return (clusters[id] as Dictionary).duplicate(true)
	if orbital_nodes.has(id):
		return (orbital_nodes[id] as Dictionary).duplicate(true)
	return {}


func otc_for(cluster_id: String) -> Array:
	var out: Array = []
	for raw in otc_satellites:
		if raw is Dictionary and String((raw as Dictionary).get("parent_cluster", "")) == cluster_id:
			out.append((raw as Dictionary).duplicate(true))
	return out


func lanes_for(cluster_id: String) -> Array:
	var out: Array = []
	for lid in lanes_list:
		var lane: Dictionary = lanes[lid]
		if String(lane.get("cluster_id", "")) == cluster_id:
			out.append(lane.duplicate(true))
	return out


func lane_occupancy(lane_id: String) -> Dictionary:
	var occ: Array = []
	var used := 0
	for oid in occupancies.keys():
		var o: Dictionary = occupancies[oid]
		if String(o.get("lane_id", "")) != lane_id or not bool(o.get("active", true)):
			continue
		occ.append(o.duplicate(true))
		used += int(o.get("width", 1))
	for oid2 in active_npc.keys():
		var n: Dictionary = active_npc[oid2]
		if String(n.get("lane_id", "")) != lane_id:
			continue
		occ.append(n.duplicate(true))
		used += int(n.get("width", 1))
	var lane := lane(lane_id)
	return {"lane_id": lane_id, "capacity": int(lane.get("capacity", 0)),
		"used": used, "free": maxi(0, int(lane.get("capacity", 0)) - used),
		"occupancies": occ}


func queue_for(lane_id: String) -> Array:
	var out: Array = []
	for rid in requests.keys():
		var r: Dictionary = requests[rid]
		if String(r.get("lane_id", "")) == lane_id and String(r.get("status", "")) in ["PENDING", "QUEUED", "CLEARED"]:
			out.append(r.duplicate(true))
	out.sort_custom(func(a, b):
		var pa := int(a.get("priority", 3))
		var pb := int(b.get("priority", 3))
		if pa != pb:
			return pa < pb
		return float(a.get("requested_t", 0.0)) < float(b.get("requested_t", 0.0)))
	return out


func window_open(lane_row: Dictionary, at_t := -1.0) -> bool:
	var check_t := at_t if at_t >= 0.0 else t
	var wins: Array = lane_row.get("windows", []) if lane_row.get("windows") is Array else []
	for raw in wins:
		if raw is Dictionary:
			var w: Dictionary = raw
			if check_t + 1.0e-9 >= float(w.get("open_t", 0.0)) and check_t <= float(w.get("close_t", 0.0)) + 1.0e-9:
				return true
	return false


func next_window_open(lane_row: Dictionary) -> float:
	var best := -1.0
	var wins: Array = lane_row.get("windows", []) if lane_row.get("windows") is Array else []
	for raw in wins:
		if raw is Dictionary:
			var open_t := float((raw as Dictionary).get("open_t", 0.0))
			if open_t >= t and (best < 0.0 or open_t < best):
				best = open_t
	return best


# ── 申请 / 许可 / 排队 / 占用 ────────────────────────────────

func request_clearance(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	var lane_row := lane(lane_id)
	if lane_row.is_empty():
		return {"ok": false, "reason": "unknown_lane", "lane_id": lane_id}
	if track_id == "":
		return {"ok": false, "reason": "empty_track"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var dir := String(o.get("direction", lane_row.get("direction", "bidirectional")))
	if String(lane_row.get("direction", "")) != "bidirectional" and dir != String(lane_row.get("direction", "")):
		_add_clue("direction_mismatch", track_id, lane_id, "direction=" + dir)
		return {"ok": false, "reason": "direction_mismatch", "lane_id": lane_id}
	var status := String(lane_row.get("status", "open"))
	if status != "open":
		return {"ok": false, "reason": "lane_closed", "lane_id": lane_id}
	if not window_open(lane_row):
		var nw := next_window_open(lane_row)
		return {"ok": false, "reason": "window_closed", "lane_id": lane_id,
			"next_window_s": nw}
	# 设施/OTC 校验（若提供 facility/transponder）
	var fac_code := String(o.get("facility_code", ""))
	var txp := String(o.get("transponder_code", ""))
	if fac_code != "" and not _facility_by_code(fac_code):
		_add_clue("facility_mismatch", track_id, lane_id, "unknown facility_code=" + fac_code)
		return {"ok": false, "reason": "facility_mismatch", "lane_id": lane_id}
	if txp != "" and not _facility_by_txp(txp):
		_add_clue("transponder_anomaly", track_id, lane_id, "unknown transponder=" + txp)
		return {"ok": false, "reason": "transponder_anomaly", "lane_id": lane_id}
	_seq_req += 1
	var rid := "REQ-%05d" % _seq_req
	var req := {"request_id": rid, "track_id": track_id, "lane_id": lane_id,
		"direction": dir, "priority": int(o.get("priority", lane_row.get("priority", 3))),
		"width": maxi(1, int(o.get("width", 1))),
		"transponder_code": txp, "facility_code": fac_code,
		"route": o.get("route", []), "npc_id": String(o.get("npc_id", "")),
		"requested_t": t, "status": "PENDING", "reason": "",
		"clearance_id": "", "queue_pos": 0, "expires_t": -1.0,
		"record_id": "LR-%05d" % _seq_req}
	requests[rid] = req
	_req_record(req, "request")
	_push_event("otc_event", {"action": "request", "request_id": rid,
		"track_id": track_id, "lane_id": lane_id})
	return {"ok": true, "reason": "", "request_id": rid, "status": "PENDING",
		"request": req.duplicate(true), "lane": lane_row}


func request_lane(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	return request_clearance(track_id, lane_id, opts)


func lane_request(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	return request_clearance(track_id, lane_id, opts)


func permit(request_id: String, opts := {}) -> Dictionary:
	var req: Dictionary = requests.get(request_id, {}) if requests.get(request_id) is Dictionary else {}
	if req.is_empty():
		return {"ok": false, "reason": "unknown_request"}
	if String(req.get("status", "")) == "CLEARED":
		return {"ok": false, "reason": "already_cleared", "request_id": request_id}
	if String(req.get("status", "")) in ["OCCUPIED", "RELEASED", "REJECTED", "EXPIRED"]:
		return {"ok": false, "reason": "request_inactive", "status": String(req.get("status", ""))}
	var lane_row := lane(String(req.get("lane_id", "")))
	if lane_row.is_empty():
		return {"ok": false, "reason": "unknown_lane"}
	if not window_open(lane_row):
		req["status"] = "QUEUED"
		req["reason"] = "window_closed"
		return {"ok": false, "reason": "window_closed", "request_id": request_id,
			"status": "QUEUED", "next_window_s": next_window_open(lane_row)}
	var free := _free_capacity(lane_row)
	if free < int(req.get("width", 1)):
		req["status"] = "QUEUED"
		req["queue_pos"] = _queue_position(req)
		req["reason"] = "capacity_full"
		_add_clue("lane_conflict", String(req.get("track_id", "")),
			String(req.get("lane_id", "")), "capacity_full")
		return {"ok": false, "reason": "capacity_full", "request_id": request_id,
			"status": "QUEUED", "queue_pos": int(req["queue_pos"])}
	_seq_clear += 1
	var cid := "CLR-%05d" % _seq_clear
	var ttl := float((opts as Dictionary).get("ttl_s", float(lane_row.get("clearance_ttl_s", 300.0)))) if opts is Dictionary else 300.0
	var clr := {"clearance_id": cid, "request_id": request_id,
		"track_id": String(req.get("track_id", "")), "lane_id": String(req.get("lane_id", "")),
		"width": int(req.get("width", 1)), "granted_t": t,
		"expires_t": t + maxf(10.0, ttl), "status": "CLEARED",
		"transponder_code": String(req.get("transponder_code", "")),
		"facility_code": String(req.get("facility_code", ""))}
	clearances[cid] = clr
	req["status"] = "CLEARED"
	req["clearance_id"] = cid
	req["expires_t"] = clr["expires_t"]
	req["reason"] = ""
	_req_record(req, "cleared")
	_push_event("otc_event", {"action": "permit", "request_id": request_id,
		"clearance_id": cid, "lane_id": clr["lane_id"]})
	return {"ok": true, "reason": "", "clearance_id": cid, "clearance": clr.duplicate(true),
		"request": req.duplicate(true)}


func approve(request_id: String, opts := {}) -> Dictionary:
	return permit(request_id, opts)


func approve_request(request_id: String, opts := {}) -> Dictionary:
	return permit(request_id, opts)


func reject(request_id: String, reason := "rejected") -> Dictionary:
	var req: Dictionary = requests.get(request_id, {}) if requests.get(request_id) is Dictionary else {}
	if req.is_empty():
		return {"ok": false, "reason": "unknown_request"}
	if String(req.get("status", "")) in ["OCCUPIED", "RELEASED", "REJECTED"]:
		return {"ok": false, "reason": "request_inactive"}
	req["status"] = "REJECTED"
	req["reason"] = reason
	_req_record(req, "rejected")
	return {"ok": true, "request_id": request_id, "status": "REJECTED", "reason": reason}


func occupy(lane_id: String, occupant_id: String, opts := {}) -> Dictionary:
	var lane_row := lane(lane_id)
	if lane_row.is_empty():
		return {"ok": false, "reason": "unknown_lane"}
	if not window_open(lane_row):
		return {"ok": false, "reason": "window_closed"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var cid := String(o.get("clearance_id", ""))
	var clr: Dictionary = {}
	if cid != "":
		clr = clearances.get(cid, {}) if clearances.get(cid) is Dictionary else {}
		if clr.is_empty():
			return {"ok": false, "reason": "unknown_clearance"}
		if String(clr.get("status", "")) != "CLEARED":
			return {"ok": false, "reason": "clearance_inactive"}
		if t + 1.0e-9 >= float(clr.get("expires_t", 0.0)):
			clr["status"] = "EXPIRED"
			return {"ok": false, "reason": "clearance_expired"}
		lane_id = String(clr.get("lane_id", lane_id))
		occupant_id = String(clr.get("track_id", occupant_id))
	else:
		for ck in clearances.keys():
			var c: Dictionary = clearances[ck]
			if String(c.get("lane_id", "")) == lane_id and String(c.get("track_id", "")) == occupant_id \
					and String(c.get("status", "")) == "CLEARED":
				clr = c
				cid = String(c.get("clearance_id", ""))
				break
		if clr.is_empty():
			return {"ok": false, "reason": "no_clearance"}
	var width := int(o.get("width", clr.get("width", 1)))
	var free := _free_capacity(lane_row)
	# 本 clearance 已预留一个名额；占用时先释放该预留再校验
	if cid != "" and clearances.has(cid) and String((clearances[cid] as Dictionary).get("status", "")) == "CLEARED":
		free += int((clearances[cid] as Dictionary).get("width", 1))
	if free < width:
		_add_clue("lane_conflict", occupant_id, lane_id, "capacity_full")
		return {"ok": false, "reason": "capacity_full", "free": free, "width": width}
	_seq_occ += 1
	var oid := "OCC-%05d" % _seq_occ
	var occ := {"occupancy_id": oid, "lane_id": lane_id, "occupant_id": occupant_id,
		"track_id": occupant_id, "clearance_id": cid, "width": width,
		"occupy_t": t, "release_t": -1.0, "active": true, "npc": false,
		"direction": String(o.get("direction", lane_row.get("direction", "bidirectional")))}
	occupancies[oid] = occ
	clr["status"] = "OCCUPIED"
	clr["occupancy_id"] = oid
	if requests.has(String(clr.get("request_id", ""))):
		requests[String(clr.get("request_id", ""))]["status"] = "OCCUPIED"
	_req_record({"record_id": "LR-%05d" % _seq_occ, "track_id": occupant_id,
		"lane_id": lane_id, "request_id": clr.get("request_id", "")}, "occupy")
	_push_event("lane_record", {"action": "occupy", "occupancy_id": oid,
		"lane_id": lane_id, "occupant_id": occupant_id})
	return {"ok": true, "reason": "", "occupancy_id": oid, "occupancy": occ.duplicate(true)}


func release(lane_id: String, occupant_id := "") -> Dictionary:
	var released: Array = []
	for oid in occupancies.keys():
		var occ: Dictionary = occupancies[oid]
		if not bool(occ.get("active", true)):
			continue
		if String(occ.get("lane_id", "")) != lane_id:
			continue
		if occupant_id != "" and String(occ.get("occupant_id", occ.get("track_id", ""))) != occupant_id:
			continue
		occ["active"] = false
		occ["release_t"] = t
		released.append(oid)
		var cid := String(occ.get("clearance_id", ""))
		if cid != "" and clearances.has(cid):
			(clearances[cid] as Dictionary)["status"] = "RELEASED"
		if requests.has(String((occ as Dictionary).get("request_id", ""))):
			requests[String((occ as Dictionary).get("request_id", ""))]["status"] = "RELEASED"
	if released.is_empty():
		return {"ok": false, "reason": "no_occupancy", "lane_id": lane_id}
	_push_event("lane_record", {"action": "release", "lane_id": lane_id,
		"released": released.duplicate()})
	return {"ok": true, "reason": "", "released": released, "lane_id": lane_id}


# ── NPC ────────────────────────────────────────────────────

func npc_occupy(lane_id: String, npc_id: String, opts := {}) -> Dictionary:
	var lane_row := lane(lane_id)
	if lane_row.is_empty():
		return {"ok": false, "reason": "unknown_lane"}
	if npc_id == "" or (not npc_ships.has(npc_id) and not bool((opts as Dictionary).get("allow_unknown_npc", false))):
		return {"ok": false, "reason": "unknown_npc"}
	var o: Dictionary = opts if opts is Dictionary else {}
	var dur := maxf(1.0, float(o.get("duration_s", lane_row.get("transit_s", 600.0))))
	var width := maxi(1, int(o.get("width", 1)))
	var free := _free_capacity(lane_row)
	if free < width:
		_add_clue("npc_conflict", npc_id, lane_id, "capacity_full")
		return {"ok": false, "reason": "capacity_full", "free": free, "width": width}
	_seq_occ += 1
	var oid := "NPCOCC-%05d" % _seq_occ
	var occ := {"occupancy_id": oid, "lane_id": lane_id, "npc_id": npc_id,
		"occupant_id": npc_id, "width": width, "start_t": t, "end_t": t + dur,
		"active": true, "npc": true, "contract": String(o.get("contract", ""))}
	occupancies[oid] = occ
	_push_event("lane_record", {"action": "npc_occupy", "occupancy_id": oid,
		"lane_id": lane_id, "npc_id": npc_id})
	return {"ok": true, "reason": "", "occupancy_id": oid, "occupancy": occ.duplicate(true)}


func npc_release(lane_id: String, npc_id := "") -> Dictionary:
	var released: Array = []
	for oid in occupancies.keys():
		var occ: Dictionary = occupancies[oid]
		if not bool(occ.get("npc", false)) or not bool(occ.get("active", true)):
			continue
		if String(occ.get("lane_id", "")) != lane_id:
			continue
		if npc_id != "" and String(occ.get("npc_id", "")) != npc_id:
			continue
		occ["active"] = false
		occ["release_t"] = t
		released.append(oid)
	if released.is_empty():
		return {"ok": false, "reason": "no_npc_occupancy"}
	return {"ok": true, "released": released, "lane_id": lane_id}


# ── NPC 定时推进 / step ─────────────────────────────────────

func step(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	# 定时 NPC
	for raw in npc_schedule:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		var oid := String(s.get("occupancy_id", ""))
		if active_npc.has(oid):
			var cur: Dictionary = active_npc[oid]
			if t + 1.0e-9 >= float(cur.get("end_t", 0.0)):
				cur["active"] = false
				active_npc.erase(oid)
			continue
		if t + 1.0e-9 >= float(s.get("t_start", 0.0)) and t <= float(s.get("t_end", 0.0)) + 1.0e-9:
			var lane_row := lane(String(s.get("lane_id", "")))
			if lane_row.is_empty():
				continue
			var rec := s.duplicate(true)
			rec["active"] = true
			rec["start_t"] = float(s.get("t_start", 0.0))
			rec["end_t"] = float(s.get("t_end", 0.0))
			rec["npc"] = true
			active_npc[oid] = rec
			if _free_capacity(lane_row) < int(rec.get("width", 1)):
				_add_clue("npc_conflict", String(rec.get("npc_id", "")),
					String(rec.get("lane_id", "")), "scheduled_npc_capacity")
			_push_event("otc_event", {"action": "npc_window", "occupancy_id": oid,
				"lane_id": rec.get("lane_id", ""), "npc_id": rec.get("npc_id", "")})
	# 清除过期 clearance
	for cid in clearances.keys().duplicate():
		var c: Dictionary = clearances[cid]
		if String(c.get("status", "")) == "CLEARED" and t + 1.0e-9 >= float(c.get("expires_t", 0.0)):
			c["status"] = "EXPIRED"
			if requests.has(String(c.get("request_id", ""))):
				var r: Dictionary = requests[String(c.get("request_id", ""))]
				if String(r.get("status", "")) == "CLEARED":
					r["status"] = "EXPIRED"
			_push_event("otc_event", {"action": "clearance_expired", "clearance_id": cid})
	# 请求队列过期
	for rid in requests.keys().duplicate():
		var r2: Dictionary = requests[rid]
		if String(r2.get("status", "")) in ["QUEUED"]:
			r2["queue_pos"] = _queue_position(r2)
	return {"ok": true, "t": t, "dt": dt_last, "counts": _counts(),
		"events": events.duplicate(true)}


# ── record_disguise / clues ─────────────────────────────────

## disguise:
## {transponder_code, facility_code, track_id, route/lane_id, claimed_type, side}
func record_disguise(track_id: String, disguise := {}, opts := {}) -> Dictionary:
	if track_id == "":
		return {"ok": false, "reason": "empty_track"}
	var d: Dictionary = disguise if disguise is Dictionary else {}
	var lane_id := String(d.get("lane_id", ""))
	var lane_row := lane(lane_id) if lane_id != "" else {}
	var anomalies: Array = []
	var txp := String(d.get("transponder_code", ""))
	var fac_code := String(d.get("facility_code", ""))
	var fac_by_txp := _facility_by_txp(txp) if txp != "" else {}
	var fac_by_code := _facility_by_code(fac_code) if fac_code != "" else {}
	if txp != "" and fac_by_txp.is_empty():
		anomalies.append("transponder_anomaly")
	if fac_code != "" and fac_by_code.is_empty():
		anomalies.append("facility_mismatch")
	if not fac_by_txp.is_empty() and not fac_by_code.is_empty():
		var expected_type := String(fac_by_txp.get("transponder_type", ""))
		var claimed_class := String(d.get("claimed_class", fac_by_code.get("facility_class", "")))
		if expected_type != "" and expected_type != claimed_class:
			anomalies.append("transponder_type_mismatch")
	if lane_row.is_empty() and lane_id != "":
		anomalies.append("track_route_mismatch")
	if not lane_row.is_empty() and not fac_by_code.is_empty():
		var from_id := String((lane_row.get("from", {}) as Dictionary).get("id", ""))
		var to_id := String((lane_row.get("to", {}) as Dictionary).get("id", ""))
		var fac_id := String(fac_by_code.get("facility_id", ""))
		if fac_id != from_id and fac_id != to_id:
			anomalies.append("track_route_mismatch")
	# OTC 监视缺口
	if not lane_row.is_empty():
		var mon: Array = lane_row.get("monitor_otc", []) if lane_row.get("monitor_otc") is Array else []
		var has_otc := false
		for oid in mon:
			if facilities.has(String(oid)):
				has_otc = true
				break
		if not has_otc:
			anomalies.append("otc_gap")
	# 历史伪装不一致
	for did in disguises.keys():
		var prev: Dictionary = disguises[did]
		if String(prev.get("track_id", "")) == track_id and String(prev.get("facility_code", "")) != fac_code:
			anomalies.append("track_history_mismatch")
			break
	var base_prob := 0.15
	var prob := clampf(base_prob + 0.2 * anomalies.size(), 0.0, 1.0)
	if lane_row.is_empty() == false:
		prob = clampf(prob + 0.05 * (6 - int(lane_row.get("priority", 3))), 0.0, 1.0)
	var force := bool((opts as Dictionary).get("force_detected", false)) if opts is Dictionary else false
	var roll := _roll("DISG|" + track_id + "|" + lane_id + "|" + str(_seq_disg))
	var detected := force or roll < prob
	_seq_disg += 1
	var dis_id := "DISG-%05d" % _seq_disg
	var rec := {"disguise_id": dis_id, "track_id": track_id, "lane_id": lane_id,
		"transponder_code": txp, "facility_code": fac_code,
		"claimed_class": String(d.get("claimed_class", "")), "route": d.get("route", []),
		"anomalies": anomalies.duplicate(), "probability": prob, "roll": roll,
		"detected": detected, "status": "DETECTED" if detected else "ACTIVE",
		"t": t, "clue_id": ""}
	disguises[dis_id] = rec
	var clue_ids: Array = []
	for a in anomalies:
		var clue := _add_clue(String(a), track_id, lane_id, "disguise " + dis_id)
		if not clue.is_empty():
			clue_ids.append(String(clue.get("clue_id", "")))
	if detected:
		var gclue := _add_clue("ghost_track", track_id, lane_id, "disguise_detected: " + dis_id)
		if not gclue.is_empty():
			clue_ids.append(String(gclue.get("clue_id", "")))
	rec["clue_ids"] = clue_ids
	_req_record({"record_id": "LR-%05d" % _seq_disg, "track_id": track_id,
		"lane_id": lane_id, "transponder_code": txp, "facility_code": fac_code,
		"disguise": dis_id, "detected": detected}, "disguise")
	_push_event("lane_record", {"action": "disguise", "disguise_id": dis_id,
		"track_id": track_id, "lane_id": lane_id, "detected": detected})
	return {"ok": true, "reason": "", "disguise_id": dis_id, "detected": detected,
		"probability": prob, "roll": roll, "anomalies": anomalies.duplicate(),
		"clue_ids": clue_ids, "disguise": rec.duplicate(true)}


func clues_for(track_id := "") -> Array:
	var out: Array = []
	for raw in clues:
		if raw is Dictionary and (track_id == "" or String((raw as Dictionary).get("track_id", "")) == track_id):
			out.append((raw as Dictionary).duplicate(true))
	return out


func clue(clue_id: String) -> Dictionary:
	for raw in clues:
		if raw is Dictionary and String((raw as Dictionary).get("clue_id", "")) == clue_id:
			return (raw as Dictionary).duplicate(true)
	return {}


func _add_clue(kind: String, track_id: String, lane_id: String, detail: String) -> Dictionary:
	if not (kind in CLUE_TYPES) and kind != "track_history_mismatch":
		kind = "ghost_track"
	_seq_clue += 1
	var c := {"schema": SCHEMA_CLUE, "clue_id": "CLUE-%05d" % _seq_clue,
		"type": kind, "t": t, "track_id": track_id, "lane_id": lane_id,
		"severity": "critical" if kind in ["ghost_track", "transponder_anomaly"] else "warn",
		"evidence": detail, "ghost_track": kind == "ghost_track",
		"requires_investigation": true, "produces_contact": false,
		"writes_v15": false}
	clues.append(c)
	while clues.size() > MAX_CLUES:
		clues.pop_front()
	_push_event("clue", c.duplicate(true))
	return c


func records_for(track_id := "") -> Array:
	var out: Array = []
	for raw in records:
		if raw is Dictionary and (track_id == "" or String((raw as Dictionary).get("track_id", "")) == track_id):
			out.append((raw as Dictionary).duplicate(true))
	return out


func _req_record(req: Dictionary, action: String) -> void:
	var rec := {"schema": SCHEMA_LANE_RECORD, "record_id": String(req.get("record_id", "LR-%05d" % _seq_event)),
		"action": action, "t": t, "request_id": String(req.get("request_id", "")),
		"track_id": String(req.get("track_id", "")), "lane_id": String(req.get("lane_id", "")),
		"transponder_code": String(req.get("transponder_code", "")),
		"facility_code": String(req.get("facility_code", "")),
		"edit": false, "delete": false, "reason": String(req.get("reason", ""))}
	records.append(rec)
	while records.size() > MAX_RECORDS:
		records.pop_front()


# ── 辅助 ────────────────────────────────────────────────────

func _facility_by_code(code: String) -> Dictionary:
	for fid in facilities.keys():
		var f: Dictionary = facilities[fid]
		if String(f.get("facility_code", "")) == code:
			return f
	return {}


func _facility_by_txp(txp: String) -> Dictionary:
	for fid in facilities.keys():
		var f: Dictionary = facilities[fid]
		if String(f.get("transponder_code", "")) == txp:
			return f
	return {}


func _free_capacity(lane_row: Dictionary) -> int:
	var lid := String(lane_row.get("lane_id", ""))
	var used := 0
	for oid in occupancies.keys():
		var o: Dictionary = occupancies[oid]
		if String(o.get("lane_id", "")) == lid and bool(o.get("active", true)):
			used += int(o.get("width", 1))
	for oid2 in active_npc.keys():
		var n: Dictionary = active_npc[oid2]
		if String(n.get("lane_id", "")) == lid:
			used += int(n.get("width", 1))
	for cid in clearances.keys():
		var c: Dictionary = clearances[cid]
		if String(c.get("lane_id", "")) == lid and String(c.get("status", "")) == "CLEARED":
			used += int(c.get("width", 1))
	return maxi(0, int(lane_row.get("capacity", 0)) - used)


func _queue_position(req: Dictionary) -> int:
	var q := queue_for(String(req.get("lane_id", "")))
	for i in range(q.size()):
		if String((q[i] as Dictionary).get("request_id", "")) == String(req.get("request_id", "")):
			return i + 1
	return q.size()


func _counts() -> Dictionary:
	var active_occ := 0
	for oid in occupancies.keys():
		if bool((occupancies[oid] as Dictionary).get("active", true)):
			active_occ += 1
	return {"facilities": facilities.size(), "lanes": lanes.size(),
		"requests": requests.size(), "clearances": clearances.size(),
		"occupancies": occupancies.size(), "active_occupancies": active_occ,
		"active_npc": active_npc.size(), "disguises": disguises.size(),
		"clues": clues.size(), "records": records.size(), "events": events.size(),
		"otc": otc_satellites.size(), "fuel": fuel_facilities.size()}


func vm() -> Dictionary:
	return {
		"schema": SCHEMA_VM, "mode": "shadow", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"facilities": facilities.size(), "lanes": lanes_list.duplicate(),
		"clusters": clusters.keys(), "orbital_nodes": orbital_nodes.keys(),
		"otc_satellites": otc_satellites.duplicate(true),
		"fuel_facilities": fuel_facilities.duplicate(true),
		"requests": _dict_rows(requests), "clearances": _dict_rows(clearances),
		"occupancies": _dict_rows(occupancies), "active_npc": _dict_rows(active_npc),
		"disguises": _dict_rows(disguises), "clues": clues.duplicate(true),
		"records": records.duplicate(true), "events": events.duplicate(true),
		"counts": _counts(), "warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"world": false, "track_table": false, "v15": false, "ui": false},
	}


func _dict_rows(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		if d[k] is Dictionary:
			out.append((d[k] as Dictionary).duplicate(true))
	return out


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t,
		"facilities": facilities.size(), "lanes": lanes.size(),
		"requests": requests.size(), "clearances": clearances.size(),
		"occupancies": occupancies.size(), "npc": active_npc.size(),
		"disguises": disguises.size(), "clues": clues.size(), "records": records.size(),
		"writes": {"world": false, "track_table": false, "v15": false}}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func _push_event(kind: String, payload := {}) -> void:
	_seq_event += 1
	var ev := {"schema": SCHEMA_EVENT, "seq": _seq_event, "t": t, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))


func _roll(seed_text: String) -> float:
	var h := int(hash(seed_text))
	return float((h & 0x7fffffff) % 1000000) / 1000000.0


# ── save / load ──────────────────────────────────────────────

func save_state() -> String:
	var payload := {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "t": t,
		"requests": JSON.parse_string(JSON.stringify(_dict_rows(requests))),
		"clearances": JSON.parse_string(JSON.stringify(_dict_rows(clearances))),
		"occupancies": JSON.parse_string(JSON.stringify(_dict_rows(occupancies))),
		"active_npc": JSON.parse_string(JSON.stringify(_dict_rows(active_npc))),
		"disguises": JSON.parse_string(JSON.stringify(_dict_rows(disguises))),
		"clues": JSON.parse_string(JSON.stringify(clues)),
		"records": JSON.parse_string(JSON.stringify(records)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"seq": {"req": _seq_req, "clear": _seq_clear, "occ": _seq_occ,
			"disg": _seq_disg, "clue": _seq_clue, "event": _seq_event},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
	}
	return JSON.stringify(payload)


func snapshot() -> Dictionary:
	return JSON.parse_string(save_state())


func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		if String(data).strip_edges() == "":
			return {"ok": false, "reason": "empty_state"}
		parsed = JSON.parse_string(String(data))
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json"}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var p: Dictionary = parsed
	if String(p.get("schema", "")) != SAVE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if String(p.get("version", "")) != SAVE_VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	for k in ["requests", "clearances", "occupancies", "active_npc", "disguises", "clues", "records", "events"]:
		if not (p.get(k) is Array):
			return {"ok": false, "reason": "invalid_payload", "field": k}
	t = float(p.get("t", 0.0))
	requests = _rows_map(p.get("requests"))
	clearances = _rows_map(p.get("clearances"))
	occupancies = _rows_map(p.get("occupancies"))
	active_npc = _rows_map(p.get("active_npc"))
	disguises = _rows_map(p.get("disguises"))
	clues = (p.get("clues") as Array).duplicate(true)
	records = (p.get("records") as Array).duplicate(true)
	events = (p.get("events") as Array).duplicate(true)
	var seq: Dictionary = p.get("seq", {}) if p.get("seq") is Dictionary else {}
	_seq_req = int(seq.get("req", 0))
	_seq_clear = int(seq.get("clear", 0))
	_seq_occ = int(seq.get("occ", 0))
	_seq_disg = int(seq.get("disg", 0))
	_seq_clue = int(seq.get("clue", 0))
	_seq_event = int(seq.get("event", 0))
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	_outbox = []
	return {"ok": true, "reason": "", "t": t, "requests": requests.size()}


func _rows_map(rows: Variant) -> Dictionary:
	var out: Dictionary = {}
	if rows is Array:
		for raw in (rows as Array):
			if not (raw is Dictionary):
				continue
			var d: Dictionary = raw
			var key := ""
			for k in ["request_id", "clearance_id", "occupancy_id", "disguise_id", "npc_id"]:
				if String(d.get(k, "")) != "":
					key = String(d.get(k, ""))
					break
			if key != "":
				out[key] = d.duplicate(true)
	return out
