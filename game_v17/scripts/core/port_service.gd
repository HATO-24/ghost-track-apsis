extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3E：PortService（港口/对接/加注/船坞/拖曳服务；新文件）
#
# 状态机（每个 request 手动推进，不自动执行）：
#   REQUESTED → GRANTED / DENIED / HOLD
#   GRANTED → APPROACH → DOCKED → SERVICING → (finish) DOCKED → DEPARTED
#   HOLD → permit 重评估 → GRANTED / DENIED
#
# 资源：泊位 / 船坞槽 / 拖船 / 燃料（每港 + 全局容量）；排队按优先级；
# 预约窗/许可/进近走廊；失败 reason；不写物理/UI/world/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.port_service.v1"
const SAVE_SCHEMA := "v17.port_service_save.v1"
const VERSION := "1.0.0"
const KINDS := ["dock", "tow", "shuttle"]
const SERVICES := ["refuel", "repair", "tow", "shuttle"]
const STATES := ["REQUESTED", "GRANTED", "DENIED", "HOLD", "APPROACH",
	"DOCKED", "SERVICING", "DEPARTED"]
const TERMINAL := ["DENIED", "DEPARTED"]
const ACTIVE := ["REQUESTED", "GRANTED", "HOLD", "APPROACH", "DOCKED", "SERVICING"]
const MAX_EVENTS := 400

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var config: Dictionary = {}
var ports: Dictionary = {}        # port_id -> {config..., berths_state}
var requests: Dictionary = {}     # request_id -> request dict
var t_s := 0.0
var _request_seq := 0
var _event_seq := 0
var events: Array = []
var event_bus = null

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	ports = {}
	requests = {}
	t_s = 0.0
	_request_seq = 0
	_event_seq = 0
	events = []
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	if config.is_empty():
		config = _demo_config()
	var v: Dictionary = validate_config(config)
	if not bool(v.get("ok", false)):
		errors.append_array(v.get("errors", []))
		return false
	for raw_p in (config.get("ports", []) as Array):
		var p: Dictionary = (raw_p as Dictionary).duplicate(true)
		var pid := String(p.get("id", ""))
		var berth_state: Dictionary = {}
		var idx := 0
		for bid in (p.get("berths", []) as Array):
			berth_state[String(bid)] = {"occupied_by": "", "index": idx}
			idx += 1
		var tug_state: Dictionary = {}
		for tid in (p.get("tugs", []) as Array):
			tug_state[String(tid)] = {"occupied_by": ""}
		ports[pid] = {
			"id": pid, "name": String(p.get("name", pid)),
			"berths": (p.get("berths", []) as Array).duplicate(),
			"drydock_slots": int(p.get("drydock_slots", 0)),
			"drydock_used": 0,
			"tugs": (p.get("tugs", []) as Array).duplicate(),
			"fuel_capacity_t": float(p.get("fuel_capacity_t", 0.0)),
			"fuel_available_t": float(p.get("fuel_available_t", p.get("fuel_capacity_t", 0.0))),
			"windows": (p.get("windows", []) as Array).duplicate(true),
			"corridor": String(p.get("corridor", "")),
			"require_permit": bool(p.get("require_permit", true)),
			"services": (p.get("services", []) as Array).duplicate(),
			"accepting": bool(p.get("accepting", true)),
			"hold_on_capacity": bool(p.get("hold_on_capacity", true)),
			"fuel_refill_per_s": float(p.get("fuel_refill_per_s", 0.0)),
			"berth_state": berth_state,
			"tug_state": tug_state,
		}
	ready = true
	return true

func _demo_config() -> Dictionary:
	return {"ports": [
		{"id": "l1_meridian_05", "name": "L1 Meridian", "berths": ["B1", "B2"],
			"drydock_slots": 1, "tugs": ["TUG1"], "fuel_capacity_t": 1000.0,
			"fuel_available_t": 1000.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C1", "require_permit": true,
			"services": ["refuel", "repair", "tow", "shuttle"]},
		{"id": "l4_02_hammer", "name": "L4-02 Hammer", "berths": ["B1"],
			"drydock_slots": 0, "tugs": [], "fuel_capacity_t": 400.0,
			"fuel_available_t": 400.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C2", "require_permit": false,
			"services": ["refuel", "tow"]},
	]}

# ── 配置校验 ────────────────────────────────────────────────────

func validate_config(cfg: Dictionary) -> Dictionary:
	var errs: Array[String] = []
	var warns: Array[String] = []
	if not (cfg.get("ports") is Array) or (cfg.get("ports") as Array).is_empty():
		errs.append("ports 必须是非空数组")
		return {"ok": false, "errors": errs, "warnings": warns}
	var ids := {}
	for raw_p in (cfg.get("ports") as Array):
		if not (raw_p is Dictionary):
			errs.append("port 非对象")
			continue
		var p: Dictionary = raw_p
		var pid := String(p.get("id", ""))
		if pid == "" or ids.has(pid):
			errs.append("port id 空/重复")
			continue
		ids[pid] = true
		if not (p.get("berths") is Array):
			errs.append("port %s berths 必须是数组" % pid)
		else:
			var bset := {}
			for bid in (p.get("berths") as Array):
				var b := String(bid)
				if b == "" or bset.has(b):
					errs.append("port %s berth id 空/重复" % pid)
				bset[b] = true
		if int(p.get("drydock_slots", 0)) < 0:
			errs.append("port %s drydock_slots 不能为负" % pid)
		if p.get("tugs") is Array:
			var tset := {}
			for tid in (p.get("tugs") as Array):
				var tg := String(tid)
				if tg == "" or tset.has(tg):
					errs.append("port %s tug id 空/重复" % pid)
				tset[tg] = true
		var cap := float(p.get("fuel_capacity_t", 0.0))
		var avail := float(p.get("fuel_available_t", cap))
		if not is_finite(cap) or cap < 0.0:
			errs.append("port %s fuel_capacity_t 非法" % pid)
		if not is_finite(avail) or avail < 0.0 or avail > cap + 1.0e-9:
			errs.append("port %s fuel_available_t 非法" % pid)
		if p.get("windows") is Array:
			for raw_w in (p.get("windows") as Array):
				if not (raw_w is Dictionary):
					errs.append("port %s window 非对象" % pid)
					continue
				var op := float((raw_w as Dictionary).get("open_t", 0.0))
				var cl := float((raw_w as Dictionary).get("close_t", 0.0))
				if not is_finite(op) or not is_finite(cl) or op < 0.0 or cl <= op:
					errs.append("port %s window 时间非法" % pid)
		if p.get("services") is Array:
			for sv in (p.get("services") as Array):
				if not (String(sv) in SERVICES):
					errs.append("port %s service 非法：%s" % [pid, String(sv)])
	if errs.is_empty() and ids.is_empty():
		errs.append("没有合法 port")
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns}

# ── 窗口 / 许可 / 容量 ──────────────────────────────────────────

func window_status(port_id: String) -> Dictionary:
	var p = ports.get(port_id, null)
	if not (p is Dictionary):
		return {"ok": false, "reason": "unknown_port"}
	var wins: Array = (p.get("windows", []) as Array)
	var open_win := {}
	for raw in wins:
		if raw is Dictionary:
			var op := float((raw as Dictionary).get("open_t", 0.0))
			var cl := float((raw as Dictionary).get("close_t", 0.0))
			if t_s >= op and t_s <= cl:
				open_win = (raw as Dictionary).duplicate(true)
				break
	return {"ok": true, "is_open": not open_win.is_empty(), "window": open_win,
		"t_s": t_s}

func resource_summary(port_id := "") -> Dictionary:
	if port_id != "":
		var p = ports.get(port_id, null)
		if not (p is Dictionary):
			return {}
		return _port_resource(p)
	var berths_total := 0
	var berths_free := 0
	var drydock_total := 0
	var drydock_free := 0
	var tugs_total := 0
	var tugs_free := 0
	var fuel := 0.0
	var fuel_cap := 0.0
	for pid in ports.keys():
		var p: Dictionary = ports[pid]
		var rs := _port_resource(p)
		berths_total += int(rs.get("berths_total", 0))
		berths_free += int(rs.get("berths_free", 0))
		drydock_total += int(rs.get("drydock_total", 0))
		drydock_free += int(rs.get("drydock_free", 0))
		tugs_total += int(rs.get("tugs_total", 0))
		tugs_free += int(rs.get("tugs_free", 0))
		fuel += float(rs.get("fuel_available_t", 0.0))
		fuel_cap += float(rs.get("fuel_capacity_t", 0.0))
	return {"schema": SCHEMA, "ports": ports.size(), "berths_total": berths_total,
		"berths_free": berths_free, "drydock_total": drydock_total,
		"drydock_free": drydock_free, "tugs_total": tugs_total,
		"tugs_free": tugs_free, "fuel_available_t": fuel,
		"fuel_capacity_t": fuel_cap}

func _port_resource(p: Dictionary) -> Dictionary:
	var berths_total := (p.get("berths", []) as Array).size()
	var berths_free := 0
	var occupied: Array = []
	for bid in (p.get("berths", []) as Array):
		var st: Dictionary = (p.get("berth_state", {}) as Dictionary).get(String(bid), {})
		if String(st.get("occupied_by", "")) == "":
			berths_free += 1
		else:
			occupied.append(String(bid))
	var tugs_total := (p.get("tugs", []) as Array).size()
	var tugs_free := 0
	for tid in (p.get("tugs", []) as Array):
		var st2: Dictionary = (p.get("tug_state", {}) as Dictionary).get(String(tid), {})
		if String(st2.get("occupied_by", "")) == "":
			tugs_free += 1
	return {
		"port_id": String(p.get("id", "")),
		"berths_total": berths_total, "berths_free": berths_free,
		"berths_occupied": occupied,
		"drydock_total": int(p.get("drydock_slots", 0)),
		"drydock_used": int(p.get("drydock_used", 0)),
		"drydock_free": int(p.get("drydock_slots", 0)) - int(p.get("drydock_used", 0)),
		"tugs_total": tugs_total, "tugs_free": tugs_free,
		"fuel_available_t": float(p.get("fuel_available_t", 0.0)),
		"fuel_capacity_t": float(p.get("fuel_capacity_t", 0.0)),
		"window": window_status(String(p.get("id", ""))),
		"corridor": String(p.get("corridor", "")),
		"services": (p.get("services", []) as Array).duplicate(),
	}

func _free_berth(p: Dictionary) -> String:
	for bid in (p.get("berths", []) as Array):
		var st: Dictionary = (p.get("berth_state", {}) as Dictionary).get(String(bid), {})
		if String(st.get("occupied_by", "")) == "":
			return String(bid)
	return ""

func _free_tug(p: Dictionary) -> String:
	for tid in (p.get("tugs", []) as Array):
		var st: Dictionary = (p.get("tug_state", {}) as Dictionary).get(String(tid), {})
		if String(st.get("occupied_by", "")) == "":
			return String(tid)
	return ""

func _active_request_for_ship(ship_id: String, exclude := "") -> String:
	for rid in requests.keys():
		if String(rid) == exclude:
			continue
		var r: Dictionary = requests[rid]
		if String(r.get("ship_id", "")) == ship_id and String(r.get("status", "")) in ACTIVE:
			return String(rid)
	return ""

# ── 请求 / 许可 ─────────────────────────────────────────────────

## 创建请求（不自动许可/对接/服务）。
func request(kind: String, ship_id: String, port_id: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	if not (kind in KINDS):
		return _fail("invalid_kind", "precondition: kind 非法：" + kind)
	if ship_id == "":
		return _fail("invalid_ship", "precondition: ship_id 不能为空")
	if not ports.has(port_id):
		return _fail("unknown_port", "precondition: 未知港口：" + port_id)
	var busy := _active_request_for_ship(ship_id)
	if busy != "":
		return _fail("ship_busy", "precondition: 舰已有活动请求：" + busy)
	var o: Dictionary = opts if opts is Dictionary else {}
	_request_seq += 1
	var rid := "PR-%06d" % _request_seq
	var p: Dictionary = ports[port_id]
	var req := {
		"schema": "port_request.v1", "request_id": rid, "kind": kind,
		"ship_id": ship_id, "port_id": port_id,
		"status": "REQUESTED", "reason": "",
		"priority": int(o.get("priority", 1)),
		"clearance": String(o.get("clearance", "")),
		"window_id": String(o.get("window_id", "")),
		"berth_id": "", "drydock": false, "tug_id": "",
		"service_kind": "", "service_amount_t": 0.0, "service_done": false,
		"created_t": t_s, "granted_t": -1.0, "approach_t": -1.0,
		"docked_t": -1.0, "service_started_t": -1.0, "service_finished_t": -1.0,
		"departed_t": -1.0, "history": [],
		"expire": bool(float(o.get("expire_in", 0.0)) > 0.0 or o.has("expire_t")),
		"expire_t": (t_s + float(o.get("expire_in", 0.0))) if float(o.get("expire_in", 0.0)) > 0.0 else float(o.get("expire_t", -1.0)),
	}
	requests[rid] = req
	_log_status(req, "REQUESTED", "created")
	_emit("port.request_created", {"request_id": rid, "kind": kind,
		"ship_id": ship_id, "port_id": port_id, "priority": int(req["priority"])})
	return {"ok": true, "request_id": rid, "status": "REQUESTED",
		"request": req.duplicate(true)}

## 许可/重评估：REQUESTED/HOLD → GRANTED/DENIED/HOLD。
func permit(request_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "REQUESTED" and String(r.get("status", "")) != "HOLD":
		return _fail("wrong_state", "precondition: 状态 %s 不能许可" % String(r.get("status", "")))
	var pid := String(r.get("port_id", ""))
	var p: Dictionary = ports[pid]
	if not bool(p.get("accepting", true)):
		return _deny(r, "port_not_accepting")
	# 窗口
	var ws := window_status(pid)
	if not bool(ws.get("is_open", false)) and (p.get("windows", []) as Array).size() > 0:
		return _hold(r, "window_not_open")
	# 许可
	if bool(p.get("require_permit", true)) and String(r.get("clearance", "")) == "":
		return _deny(r, "no_permit")
	# 资源
	var kind := String(r.get("kind", ""))
	if kind in ["dock", "shuttle"]:
		var bid := _free_berth(p)
		if bid == "":
			if bool(p.get("hold_on_capacity", true)):
				return _hold(r, "no_berth")
			return _deny(r, "no_berth")
		r["berth_id"] = bid
		(p["berth_state"] as Dictionary)[bid]["occupied_by"] = String(r.get("request_id", ""))
	elif kind == "tow":
		var tid := _free_tug(p)
		if tid == "":
			if bool(p.get("hold_on_capacity", true)):
				return _hold(r, "no_tug")
			return _deny(r, "no_tug")
		r["tug_id"] = tid
		(p["tug_state"] as Dictionary)[tid]["occupied_by"] = String(r.get("request_id", ""))
	r["status"] = "GRANTED"
	r["granted_t"] = t_s
	r["reason"] = ""
	_log_status(r, "GRANTED", "permit")
	_emit("port.request_granted", {"request_id": request_id, "kind": kind,
		"ship_id": String(r.get("ship_id", "")), "port_id": pid,
		"berth_id": String(r.get("berth_id", "")),
		"tug_id": String(r.get("tug_id", ""))})
	return {"ok": true, "request_id": request_id, "status": "GRANTED",
		"request": r.duplicate(true)}

## 显式拒绝（港方）。
func deny(request_id: String, reason_text := "denied") -> Dictionary:
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var rr: Dictionary = req
	if String(rr.get("status", "")) in TERMINAL:
		return _fail("wrong_state", "precondition: 请求已结束")
	_release_resources(rr)
	return _deny(rr, String(reason_text))

func _deny(r: Dictionary, reason_text: String) -> Dictionary:
	r["status"] = "DENIED"
	r["reason"] = String(reason_text)
	_log_status(r, "DENIED", reason_text)
	_emit("port.request_denied", {"request_id": String(r.get("request_id", "")),
		"reason": String(reason_text)})
	return {"ok": false, "request_id": String(r.get("request_id", "")),
		"status": "DENIED", "reason": String(reason_text), "denied": true}

func _hold(r: Dictionary, reason_text: String) -> Dictionary:
	r["status"] = "HOLD"
	r["reason"] = String(reason_text)
	_log_status(r, "HOLD", reason_text)
	_emit("port.request_held", {"request_id": String(r.get("request_id", "")),
		"reason": String(reason_text), "priority": int(r.get("priority", 0))})
	return {"ok": false, "request_id": String(r.get("request_id", "")),
		"status": "HOLD", "reason": String(reason_text), "held": true}

## 排队（HOLD/REQUESTED，按优先级降序 + 创建时间）。
func queue(port_id := "") -> Array:
	var rows: Array = []
	for rid in requests.keys():
		var r: Dictionary = requests[rid]
		if not (String(r.get("status", "")) in ["REQUESTED", "HOLD"]):
			continue
		if port_id != "" and String(r.get("port_id", "")) != port_id:
			continue
		rows.append(r.duplicate(true))
	rows.sort_custom(func(a, b):
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		return float(a.get("created_t", 0.0)) < float(b.get("created_t", 0.0)))
	return rows

func approach(request_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "GRANTED":
		return _fail("wrong_state", "precondition: 状态 %s 不能进近" % String(r.get("status", "")))
	var pid := String(r.get("port_id", ""))
	var ws := window_status(pid)
	if not bool(ws.get("is_open", false)):
		return _fail("window_closed", "precondition: 预约窗未开/已关")
	r["status"] = "APPROACH"
	r["approach_t"] = t_s
	r["reason"] = ""
	_log_status(r, "APPROACH", "corridor:" + String((ports[pid] as Dictionary).get("corridor", "")))
	_emit("port.approach", {"request_id": request_id, "port_id": pid,
		"corridor": String((ports[pid] as Dictionary).get("corridor", ""))})
	return {"ok": true, "request_id": request_id, "status": "APPROACH",
		"corridor": String((ports[pid] as Dictionary).get("corridor", ""))}

func dock(request_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "APPROACH":
		return _fail("wrong_state", "precondition: 状态 %s 不能对接" % String(r.get("status", "")))
	var pid := String(r.get("port_id", ""))
	var p: Dictionary = ports[pid]
	if String(r.get("kind", "")) == "tow" and String(r.get("berth_id", "")) == "":
		var bid := _free_berth(p)
		if bid == "":
			return _fail("no_berth", "precondition: 没有空闲泊位")
		r["berth_id"] = bid
		(p["berth_state"] as Dictionary)[bid]["occupied_by"] = String(r.get("request_id", ""))
	if String(r.get("berth_id", "")) == "":
		return _fail("no_berth", "precondition: 未分配泊位")
	r["status"] = "DOCKED"
	r["docked_t"] = t_s
	r["reason"] = ""
	_log_status(r, "DOCKED", String(r.get("berth_id", "")))
	_emit("port.docked", {"request_id": request_id, "berth_id": String(r.get("berth_id", "")),
		"ship_id": String(r.get("ship_id", ""))})
	return {"ok": true, "request_id": request_id, "status": "DOCKED",
		"berth_id": String(r.get("berth_id", ""))}

## 可用服务列表（对 DOCKED 请求；含锁定原因）。
func services(request_id := "", port_id := "") -> Array:
	var pid := port_id
	var req := {}
	if request_id != "":
		var rawr = requests.get(request_id, null)
		if rawr is Dictionary:
			req = rawr
			pid = String(req.get("port_id", ""))
	if pid == "" or not ports.has(pid):
		return []
	var p: Dictionary = ports[pid]
	var out: Array = []
	var status := String(req.get("status", "")) if not req.is_empty() else ""
	for sv in ["refuel", "repair"]:
		var available: bool = (sv in (p.get("services", []) as Array))
		var why: String = "" if available else "not_supported"
		if status != "DOCKED":
			available = false
			why = "not_docked"
		elif sv == "repair" and int(p.get("drydock_slots", 0)) - int(p.get("drydock_used", 0)) <= 0:
			available = false
			why = "no_drydock"
		out.append({"service": sv, "port_id": pid, "available": available,
			"locked": not available, "reason": why,
			"label_key": "PORT_" + sv.to_upper()})
	for sv in ["tow", "shuttle"]:
		out.append({"service": sv, "port_id": pid,
			"available": sv in (p.get("services", []) as Array),
			"locked": not (sv in (p.get("services", []) as Array)),
			"reason": "" if sv in (p.get("services", []) as Array) else "not_supported",
			"label_key": "PORT_" + sv.to_upper()})
	return out

## 加注（DOCKED → SERVICING，消耗燃料；finish_service 后回 DOCKED）。
func refuel(request_id: String, amount_t: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "DOCKED":
		return _fail("wrong_state", "precondition: 状态 %s 不能加注" % String(r.get("status", "")))
	if not is_finite(amount_t) or amount_t <= 0.0:
		return _fail("invalid_amount", "precondition: amount_t 必须 >0")
	var p: Dictionary = ports[String(r.get("port_id", ""))]
	if not ("refuel" in (p.get("services", []) as Array)):
		return _fail("service_unavailable", "precondition: 该港不支持 refuel")
	if float(p.get("fuel_available_t", 0.0)) < amount_t:
		return _fail("insufficient_fuel", "precondition: 港口燃料不足")
	var before := float(p.get("fuel_available_t", 0.0))
	p["fuel_available_t"] = before - amount_t
	r["status"] = "SERVICING"
	r["service_kind"] = "refuel"
	r["service_amount_t"] = amount_t
	r["service_started_t"] = t_s
	r["service_done"] = false
	_log_status(r, "SERVICING", "refuel %.1ft" % amount_t)
	_emit("port.service_started", {"request_id": request_id, "service": "refuel",
		"amount_t": amount_t, "fuel_before_t": before,
		"fuel_after_t": float(p.get("fuel_available_t", 0.0))})
	return {"ok": true, "request_id": request_id, "status": "SERVICING",
		"service": "refuel", "amount_t": amount_t,
		"fuel_available_t": float(p.get("fuel_available_t", 0.0))}

## 船坞维修（DOCKED → SERVICING，占用 drydock 槽；finish_service 释放）。
func repair(request_id: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "DOCKED":
		return _fail("wrong_state", "precondition: 状态 %s 不能维修" % String(r.get("status", "")))
	var p: Dictionary = ports[String(r.get("port_id", ""))]
	if not ("repair" in (p.get("services", []) as Array)):
		return _fail("service_unavailable", "precondition: 该港不支持 repair")
	if int(p.get("drydock_slots", 0)) - int(p.get("drydock_used", 0)) <= 0:
		return _fail("no_drydock", "precondition: 船坞槽已满")
	var o: Dictionary = opts if opts is Dictionary else {}
	p["drydock_used"] = int(p.get("drydock_used", 0)) + 1
	r["status"] = "SERVICING"
	r["service_kind"] = "repair"
	r["drydock"] = true
	r["service_started_t"] = t_s
	r["service_done"] = false
	r["reason"] = String(o.get("reason", ""))
	_log_status(r, "SERVICING", "repair drydock")
	_emit("port.service_started", {"request_id": request_id, "service": "repair",
		"drydock_used": int(p.get("drydock_used", 0))})
	return {"ok": true, "request_id": request_id, "status": "SERVICING",
		"service": "repair", "drydock_used": int(p.get("drydock_used", 0))}

## 显式完成服务（不自动）：SERVICING → DOCKED；释放船坞槽。
func finish_service(request_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "SERVICING":
		return _fail("wrong_state", "precondition: 状态 %s 不在服务中" % String(r.get("status", "")))
	var p: Dictionary = ports[String(r.get("port_id", ""))]
	if bool(r.get("drydock", false)):
		p["drydock_used"] = maxi(0, int(p.get("drydock_used", 0)) - 1)
		r["drydock"] = false
	r["status"] = "DOCKED"
	r["service_done"] = true
	r["service_finished_t"] = t_s
	r["reason"] = ""
	_log_status(r, "DOCKED", "service_finished")
	_emit("port.service_finished", {"request_id": request_id,
		"service": String(r.get("service_kind", "")),
		"amount_t": float(r.get("service_amount_t", 0.0))})
	return {"ok": true, "request_id": request_id, "status": "DOCKED",
		"service": String(r.get("service_kind", ""))}

## 拖曳任务：创建 kind=tow 请求（tug 在 permit 时占用）。
func tow(ship_id: String, port_id: String, opts := {}) -> Dictionary:
	return request("tow", ship_id, port_id, opts)

## 穿梭机任务：创建 kind=shuttle 请求（berth 在 permit 时占用）。
func shuttle(ship_id: String, port_id: String, opts := {}) -> Dictionary:
	return request("shuttle", ship_id, port_id, opts)

## 离港：DOCKED → DEPARTED；释放泊位/拖船/船坞。
func undock(request_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	var req = requests.get(request_id, null)
	if not (req is Dictionary):
		return _fail("unknown_request", "precondition: 未知请求：" + request_id)
	var r: Dictionary = req
	if String(r.get("status", "")) != "DOCKED":
		return _fail("wrong_state", "precondition: 状态 %s 不能离港" % String(r.get("status", "")))
	_release_resources(r)
	r["status"] = "DEPARTED"
	r["departed_t"] = t_s
	r["reason"] = ""
	_log_status(r, "DEPARTED", "undock")
	_emit("port.departed", {"request_id": request_id,
		"ship_id": String(r.get("ship_id", "")),
		"port_id": String(r.get("port_id", ""))})
	return {"ok": true, "request_id": request_id, "status": "DEPARTED"}

func _release_resources(r: Dictionary) -> void:
	var pid := String(r.get("port_id", ""))
	if not ports.has(pid):
		return
	var p: Dictionary = ports[pid]
	var bid := String(r.get("berth_id", ""))
	if bid != "" and (p.get("berth_state", {}) as Dictionary).has(bid):
		(p["berth_state"] as Dictionary)[bid]["occupied_by"] = ""
		r["berth_id"] = ""
	var tid := String(r.get("tug_id", ""))
	if tid != "" and (p.get("tug_state", {}) as Dictionary).has(tid):
		(p["tug_state"] as Dictionary)[tid]["occupied_by"] = ""
		r["tug_id"] = ""
	if bool(r.get("drydock", false)):
		p["drydock_used"] = maxi(0, int(p.get("drydock_used", 0)) - 1)
		r["drydock"] = false

## 手动推进时间（不自动许可/对接/服务）；可过期窗口请求（→DENIED window_expired）。
func tick(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: PortService 未 ready")
	if not is_finite(dt) or dt < 0.0:
		return _fail("invalid_dt", "precondition: dt 必须有限且 >=0")
	t_s += dt
	# 燃料自然补充（资源，不是服务执行）
	for pid in ports.keys():
		var p: Dictionary = ports[pid]
		var rate := float(p.get("fuel_refill_per_s", 0.0))
		if rate > 0.0:
			p["fuel_available_t"] = minf(float(p.get("fuel_capacity_t", 0.0)),
				float(p.get("fuel_available_t", 0.0)) + rate * dt)
	var expired: Array = []
	for rid in requests.keys():
		var r: Dictionary = requests[rid]
		if not (String(r.get("status", "")) in ["REQUESTED", "HOLD", "GRANTED"]):
			continue
		if bool(r.get("expire", false)) and t_s >= float(r.get("expire_t", 0.0)):
			_release_resources(r)
			r["status"] = "DENIED"
			r["reason"] = "window_expired"
			_log_status(r, "DENIED", "window_expired")
			_emit("port.request_expired", {"request_id": rid})
			expired.append(rid)
	return {"ok": true, "t_s": t_s, "expired": expired,
		"resources": resource_summary(),
		"no_auto": {"granted": 0, "docked": 0, "serviced": 0}}

func _log_status(r: Dictionary, status: String, reason: String) -> void:
	(r.get("history", []) as Array).append({"t": t_s, "status": status,
		"reason": reason})

# ── 事件 ────────────────────────────────────────────────────────

func _emit(kind: String, detail: Dictionary) -> void:
	_event_seq += 1
	var ev := {"schema": "port_event.v1", "seq": _event_seq, "t": t_s,
		"kind": kind, "detail": detail.duplicate(true), "writes_v15": false}
	events.append(ev)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	if event_bus != null and event_bus.has_method("publish"):
		event_bus.publish({"type": kind, "t": t_s, "source": "port_service",
			"target": String(detail.get("port_id", "")),
			"payload": detail.duplicate(true), "text_key": ""})

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out := events.duplicate(true)
	events = []
	return out

func bind_event_bus(bus) -> Dictionary:
	if bus == null or not bus.has_method("publish"):
		return {"ok": false, "reason": "invalid_event_bus"}
	event_bus = bus
	return {"ok": true}

# ── 查询 / VM ───────────────────────────────────────────────────

func get_request(request_id: String) -> Dictionary:
	return (requests.get(request_id, {}) as Dictionary).duplicate(true)

func port_summary(port_id: String) -> Dictionary:
	var p = ports.get(port_id, null)
	if not (p is Dictionary):
		return {}
	return {"id": String(p.get("id", "")), "name": String(p.get("name", "")),
		"resources": _port_resource(p)}

func summary() -> Dictionary:
	var counts := {}
	for st in STATES:
		counts[st] = 0
	for rid in requests.keys():
		var st := String((requests[rid] as Dictionary).get("status", ""))
		counts[st] = int(counts.get(st, 0)) + 1
	return {"schema": SCHEMA, "ready": ready, "t": t_s,
		"ports": ports.size(), "requests": requests.size(), "counts": counts,
		"resources": resource_summary(), "writes_v15": false}

func vm() -> Dictionary:
	var port_rows: Array = []
	for pid in ports.keys():
		var p: Dictionary = ports[pid]
		port_rows.append({"id": pid, "name": String(p.get("name", "")),
			"resources": _port_resource(p),
			"accepting": bool(p.get("accepting", true)),
			"require_permit": bool(p.get("require_permit", true)),
			"windows": (p.get("windows", []) as Array).duplicate(true)})
	port_rows.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	var req_rows: Array = []
	for rid in requests.keys():
		req_rows.append((requests[rid] as Dictionary).duplicate(true))
	req_rows.sort_custom(func(a, b): return String(a.get("request_id", "")) < String(b.get("request_id", "")))
	return {"schema": SCHEMA, "mode": "shadow", "ready": ready, "t": t_s,
		"ports": port_rows, "requests": req_rows,
		"queue": queue(), "events": events.duplicate(true),
		"summary": summary(),
		"writes": {"world": false, "v15": false, "physics": false},
		"warnings": warnings.duplicate(), "errors": errors.duplicate()}

# ── save/load（内存 JSON） ─────────────────────────────────────

func save_state() -> String:
	if not ready:
		return ""
	return JSON.stringify({
		"schema": SAVE_SCHEMA, "version": VERSION, "t_s": t_s,
		"request_seq": _request_seq, "event_seq": _event_seq,
		"ports": JSON.parse_string(JSON.stringify(ports)),
		"requests": JSON.parse_string(JSON.stringify(requests)),
		"events": JSON.parse_string(JSON.stringify(events)),
	})

func save() -> String:
	return save_state()

func load_state(json_text: String) -> Dictionary:
	var p = _load_state_impl(json_text)
	return p

func load(json_text: String) -> Dictionary:
	return _load_state_impl(json_text)

func _load_state_impl(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		return _fail("empty_state", "load: 空 JSON")
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return _fail("invalid_json", "load: JSON 无效")
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if String(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	# 先校验 ports/requests，再应用（失败不改状态）
	var new_ports = d.get("ports", null)
	var new_requests = d.get("requests", null)
	if not (new_ports is Dictionary) or not (new_requests is Dictionary):
		return _fail("invalid_payload", "load: ports/requests 类型无效")
	for pid in (new_ports as Dictionary).keys():
		var np: Dictionary = (new_ports as Dictionary)[pid]
		if not (np.get("berth_state") is Dictionary) or not (np.get("tug_state") is Dictionary):
			return _fail("invalid_resources", "load: 泊位/拖船状态无效")
		if float(np.get("fuel_available_t", -1.0)) < 0.0:
			return _fail("invalid_resources", "load: 燃料为负")
		if int(np.get("drydock_used", 0)) < 0 or int(np.get("drydock_used", 0)) > int(np.get("drydock_slots", 0)):
			return _fail("invalid_resources", "load: 船坞占用非法")
	for rid in (new_requests as Dictionary).keys():
		var nr: Dictionary = (new_requests as Dictionary)[rid]
		if not (String(nr.get("status", "")) in STATES):
			return _fail("invalid_request", "load: request 状态非法")
	ports = (new_ports as Dictionary).duplicate(true)
	requests = (new_requests as Dictionary).duplicate(true)
	t_s = float(d.get("t_s", 0.0))
	_request_seq = int(d.get("request_seq", 0))
	_event_seq = int(d.get("event_seq", 0))
	if d.get("events") is Array:
		events = (d.get("events") as Array).duplicate(true)
	_check_contracts()
	return {"ok": true, "t_s": t_s, "ports": ports.size(),
		"requests": requests.size(), "errors": []}

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	for pid in ports.keys():
		var p: Dictionary = ports[pid]
		var used := 0
		for bid in (p.get("berths", []) as Array):
			var st: Dictionary = (p.get("berth_state", {}) as Dictionary).get(String(bid), {})
			if String(st.get("occupied_by", "")) != "":
				used += 1
				if not requests.has(String(st.get("occupied_by", ""))):
					v.append("泊位占用引用未知 request：" + pid)
		if used > (p.get("berths", []) as Array).size():
			v.append("泊位超容量：" + pid)
		if int(p.get("drydock_used", 0)) < 0 or int(p.get("drydock_used", 0)) > int(p.get("drydock_slots", 0)):
			v.append("船坞占用越界：" + pid)
		var fuel := float(p.get("fuel_available_t", 0.0))
		if not is_finite(fuel) or fuel < 0.0 or fuel > float(p.get("fuel_capacity_t", 0.0)) + 1.0e-9:
			v.append("燃料越界：" + pid)
		for tid in (p.get("tugs", []) as Array):
			var st2: Dictionary = (p.get("tug_state", {}) as Dictionary).get(String(tid), {})
			if String(st2.get("occupied_by", "")) != "" and not requests.has(String(st2.get("occupied_by", ""))):
				v.append("拖船占用引用未知 request：" + pid)
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _check_contracts() -> void:
	var v: Array = check_contracts().get("violations", [])
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("PortService 不变量失败：" + str(v))

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": String(reason_text), "errors": [msg]}
