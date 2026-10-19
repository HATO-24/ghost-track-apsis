class_name V2Orders
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 命令/预命令状态机 + 队列（纯数据，不引用 UI）
#
#   PRE_ORDER → AUTHORIZED → QUEUED → TRANSMITTED → EXECUTING → DONE
#        ↘ ABORTED（PRE_ORDER/AUTHORIZED/QUEUED/TRANSMITTED 可撤）
#        ↘ REJECTED（授权/校验失败）
#
#   规则：
#   - 发预命令（issue）只创建 PRE_ORDER 记录，不推进世界时间、不进队列；
#   - 授权（authorize）→ 入队（enqueue）→ 传输（transmit）→ 执行（begin_exec）；
#     tick(now) 按传输延迟/执行延迟自动推进，时间只来自外部 now，本类从不改 t；
#   - 撤销（abort）只在执行前可用；进入 EXECUTING 后只能 DONE（或由上层裁决）。
#   - 延迟、id 前缀等来自配置（scenario.orders / 默认值），不写死第一关。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONFIG := {
	"tx_delay_s": 8.0,       # 队列 → 传输 的链路延迟（docs/14 中继 8 s；可由场景覆盖）
	"exec_delay_s": 0.0,     # 传输 → 执行 的指令延迟
	"id_prefix": "ORD",
	"id_pad": 4,
}

signal order_changed(order: Dictionary)

class Order extends RefCounted:
	const STATES := ["PRE_ORDER", "AUTHORIZED", "QUEUED", "TRANSMITTED",
		"EXECUTING", "DONE", "ABORTED", "REJECTED"]
	const TERMINAL := ["DONE", "ABORTED", "REJECTED"]
	const ABORTABLE := ["PRE_ORDER", "AUTHORIZED", "QUEUED", "TRANSMITTED"]
	const TRANSITIONS := {
		"PRE_ORDER": ["AUTHORIZED", "ABORTED", "REJECTED"],
		"AUTHORIZED": ["QUEUED", "ABORTED", "REJECTED"],
		"QUEUED": ["TRANSMITTED", "ABORTED"],
		"TRANSMITTED": ["EXECUTING", "ABORTED"],
		"EXECUTING": ["DONE"],
		"DONE": [],
		"ABORTED": [],
		"REJECTED": [],
	}

	var id := ""
	var action := ""
	var target := ""
	var target_track := ""
	var actor := ""
	var params: Dictionary = {}
	var state := "PRE_ORDER"
	var note := ""
	var reason := ""

	var created_t := -1.0
	var authorized_t := -1.0
	var queued_t := -1.0
	var tx_t := -1.0
	var exec_t := -1.0
	var done_t := -1.0
	var closed_t := -1.0

	var tx_delay_s := 8.0
	var exec_delay_s := 0.0
	var duration_s := 0.0
	var history: Array = []

	func can(next: String) -> bool:
		return (TRANSITIONS.get(state, []) as Array).has(next)

	func is_terminal() -> bool:
		return state in TERMINAL

	func is_active() -> bool:
		return not is_terminal()

	func go(next: String, now: float, why := "") -> bool:
		if not can(next):
			return false
		var old := state
		state = next
		match next:
			"AUTHORIZED":
				authorized_t = now
			"QUEUED":
				queued_t = now
			"TRANSMITTED":
				tx_t = now
			"EXECUTING":
				exec_t = now
			"DONE":
				done_t = now
				closed_t = now
			"ABORTED", "REJECTED":
				closed_t = now
				if why != "":
					reason = why
		if why != "" and note == "":
			note = why
		history.append({"from": old, "to": next, "t": now, "note": why})
		return true

	## 计划执行时刻：参数里给了绝对 exec_t 就按它，否则 tx 时刻 + exec 延迟。
	func planned_exec_t() -> float:
		if params.has("exec_t"):
			return float(params.get("exec_t", 0.0))
		if tx_t >= 0.0:
			return tx_t + exec_delay_s
		return -1.0

	func to_dict() -> Dictionary:
		return {
			"id": id, "action": action, "target": target, "target_track": target_track,
			"actor": actor, "params": params.duplicate(true), "state": state,
			"note": note, "reason": reason,
			"created_t": created_t, "authorized_t": authorized_t, "queued_t": queued_t,
			"tx_t": tx_t, "exec_t": exec_t, "done_t": done_t, "closed_t": closed_t,
			"tx_delay_s": tx_delay_s, "exec_delay_s": exec_delay_s, "duration_s": duration_s,
			"history": history.duplicate(true),
			"terminal": is_terminal(), "active": is_active(),
		}

# ── 队列/管理器 ─────────────────────────────────────────────────────

var config: Dictionary = {}
var orders: Array = []
var by_id: Dictionary = {}
var errors: Array[String] = []
var next_seq := 1

func _init(p_config: Dictionary = {}) -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	for k in p_config.keys():
		config[k] = p_config[k]

func _new_id() -> String:
	var prefix := String(config.get("id_prefix", "ORD"))
	var pad := int(config.get("id_pad", 4))
	return "%s%0*d" % [prefix, pad, next_seq]

## 发预命令：只记录，不推进时间、不入队。返回 Order。
func issue(action: String, target := "", params: Dictionary = {}, actor := "",
		target_track := "", now := -1.0) -> Order:
	var o := Order.new()
	o.id = _new_id()
	next_seq += 1
	o.action = action
	o.target = target
	o.target_track = target_track
	o.actor = actor
	o.params = params.duplicate(true)
	o.created_t = now
	o.tx_delay_s = float(params.get("tx_delay_s", config.get("tx_delay_s", 8.0)))
	o.exec_delay_s = float(params.get("exec_delay_s", config.get("exec_delay_s", 0.0)))
	o.duration_s = float(params.get("duration_s", 0.0))
	orders.append(o)
	by_id[o.id] = o
	_emit(o)
	return o

func find(order_id: String) -> Order:
	return by_id.get(order_id)

func latest() -> Order:
	return orders[orders.size() - 1] if orders.size() > 0 else null

func all() -> Array:
	return orders.duplicate()

## 尚未授权的预命令。
func pending() -> Array:
	return _filter(["PRE_ORDER", "AUTHORIZED"])

## 等待传输/执行的队列项。
func queued() -> Array:
	return _filter(["QUEUED"])

func transmitting() -> Array:
	return _filter(["TRANSMITTED"])

func executing() -> Array:
	return _filter(["EXECUTING"])

func active() -> Array:
	var out: Array = []
	for raw in orders:
		var o: Order = raw
		if o.is_active():
			out.append(o)
	return out

func _filter(states: Array) -> Array:
	var out: Array = []
	for raw in orders:
		var o: Order = raw
		if o.state in states:
			out.append(o)
	return out

# —— 状态迁移（都返回 {ok, reason, order}）——

func authorize(order_id: String, now: float) -> Dictionary:
	return _go(order_id, "AUTHORIZED", now, "")

func enqueue(order_id: String, now: float) -> Dictionary:
	return _go(order_id, "QUEUED", now, "")

func transmit(order_id: String, now: float) -> Dictionary:
	return _go(order_id, "TRANSMITTED", now, "")

func begin_exec(order_id: String, now: float) -> Dictionary:
	return _go(order_id, "EXECUTING", now, "")

func complete(order_id: String, now: float, why := "") -> Dictionary:
	return _go(order_id, "DONE", now, why)

func abort(order_id: String, now: float, why := "用户撤销") -> Dictionary:
	var o := find(order_id)
	if o == null:
		return {"ok": false, "reason": "命令不存在: " + order_id, "order": null}
	if not (o.state in Order.ABORTABLE):
		o.note = "撤销失败：%s 不可撤销" % o.state
		return {"ok": false, "reason": "当前状态不可撤销（%s）" % o.state, "order": o}
	return _go(order_id, "ABORTED", now, why)

func reject(order_id: String, now: float, why := "校验失败") -> Dictionary:
	var o := find(order_id)
	if o == null:
		return {"ok": false, "reason": "命令不存在: " + order_id, "order": null}
	if not (o.state in ["PRE_ORDER", "AUTHORIZED", "QUEUED", "TRANSMITTED"]):
		return {"ok": false, "reason": "当前状态不可驳回（%s）" % o.state, "order": o}
	return _go(order_id, "REJECTED", now, why)

## 撤销最近一条可撤销命令。
func abort_latest(now: float, why := "用户撤销") -> Dictionary:
	for i in range(orders.size() - 1, -1, -1):
		var o: Order = orders[i]
		if o.state in Order.ABORTABLE:
			return abort(o.id, now, why)
	return {"ok": false, "reason": "没有可撤销的命令", "order": null}

func _go(order_id: String, next: String, now: float, why: String) -> Dictionary:
	var o := find(order_id)
	if o == null:
		return {"ok": false, "reason": "命令不存在: " + order_id, "order": null}
	if not o.go(next, now, why):
		return {"ok": false, "reason": "非法状态迁移 %s → %s" % [o.state, next], "order": o}
	_emit(o)
	return {"ok": true, "reason": "", "order": o}

## 按仿真时间推进队列：QUEUED→TRANSMITTED→EXECUTING→DONE。
## 返回本次发生的迁移列表（供 world 写日志/UI 刷新）。
func tick(now: float) -> Array:
	var transitions: Array = []
	for raw in orders:
		var o: Order = raw
		if o.state == "QUEUED":
			var due := (o.queued_t if o.queued_t >= 0.0 else o.created_t) + o.tx_delay_s
			if now >= due:
				o.go("TRANSMITTED", now, "链路延迟 %.1fs 到期" % o.tx_delay_s)
				transitions.append(_transition_dict(o, "QUEUED"))
				_emit(o)
		if o.state == "TRANSMITTED":
			var planned := o.planned_exec_t()
			if planned >= 0.0 and now >= planned:
				o.go("EXECUTING", now, "")
				transitions.append(_transition_dict(o, "TRANSMITTED"))
				_emit(o)
		if o.state == "EXECUTING":
			if o.duration_s > 0.0 and now >= o.exec_t + o.duration_s:
				o.go("DONE", now, "执行完成（%.1fs）" % o.duration_s)
				transitions.append(_transition_dict(o, "EXECUTING"))
				_emit(o)
	return transitions

func _transition_dict(o: Order, from_state: String) -> Dictionary:
	return {"order_id": o.id, "action": o.action, "from": from_state,
		"to": o.state, "t": o.closed_t if o.is_terminal() else o.exec_t,
		"target": o.target}

# ── 视图 / 报告 ────────────────────────────────────────────────────

func snapshot() -> Array:
	var out: Array = []
	for raw in orders:
		var o: Order = raw
		out.append(o.to_dict())
	return out

func summary() -> Dictionary:
	var counts: Dictionary = {}
	for s in Order.STATES:
		counts[s] = 0
	for raw in orders:
		var o: Order = raw
		counts[o.state] = int(counts.get(o.state, 0)) + 1
	return {
		"total": orders.size(),
		"counts": counts,
		"pending": pending().size(),
		"queued": queued().size(),
		"executing": executing().size(),
		"config": config.duplicate(true),
	}

func _emit(o: Order) -> void:
	order_changed.emit(o.to_dict())
