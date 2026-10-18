extends RefCounted

# 命令模型（P1d，第一关子集）：STATION / SHADOW / BURN
#
# 设计口径（docs/13）：
#   - 玩家下的是意图；系统给出计划（exec_t / Δv / 预测），命令有延迟；
#   - 生效前可撤销；点火后不可撤销（BURN 只能接受新轨道）；
#   - Δv 是预算：BURN 扣 unit.dv，油船可补给（本版无补给）。
#
# 状态机（第一版）：
#   QUEUED ──tick(exec_t)──▶ EXEC          （已生效，写入 state.own_events / shadow）
#   QUEUED ──abort()───────▶ ABORTED       （生效前免费撤销；链路收不回，这里直接标记中止）
#   *      ──issue()───────▶ REJECTED      （动作未知 / Δv 不足：计划直接标红，不进队列）
#
# 延迟（docs/13 §6；07 §3）：SHADOW 经望楼号中继，链路 8 s；STATION 同链路 8 s。
# BURN 是本舰计划点火：issue 时给计划的绝对执行时刻 exec_t（tau 秒，T0 起算），
# 不额外加链路延迟（本舰本地），执行前可撤销。

const Orbit := preload("res://scripts/orbit_model.gd")

const RELAY_VIA := "望楼号"
const RELAY_DELAY_S := 8.0

const ACT_STATION := "STATION"
const ACT_SHADOW := "SHADOW"
const ACT_BURN := "BURN"

const ST_QUEUED := "QUEUED"
const ST_EXEC := "EXEC"
const ST_ABORTED := "ABORTED"
const ST_REJECTED := "REJECTED"

const MAX_COMMANDS := 10

var commands: Array = []
var selected_id := ""
var _next_id := 1

# ── 工具 ────────────────────────────────────────────────

static func dv_vector(bearing_deg: float, elev_deg: float, dv_mps: float) -> Vector3:
	var b := deg_to_rad(bearing_deg)
	var e := deg_to_rad(elev_deg)
	return Vector3(sin(b) * cos(e), cos(b) * cos(e), sin(e)) * (dv_mps / 1000.0)

static func action_label(action: String) -> String:
	match action:
		ACT_STATION:
			return "保持站位"
		ACT_SHADOW:
			return "跟踪伴飞"
		ACT_BURN:
			return "脉冲点火"
		_:
			return action

static func status_label(status: String) -> String:
	match status:
		ST_QUEUED:
			return "待生效"
		ST_EXEC:
			return "已执行"
		ST_ABORTED:
			return "已撤销"
		ST_REJECTED:
			return "已拒绝"
		_:
			return status

func _make_id() -> String:
	var s := "CMD-%02d" % _next_id
	_next_id += 1
	return s

func _trim() -> void:
	# 队列上限：先丢最旧的已结束命令，再丢最旧的
	var keep: Array = []
	var dropped := false
	for raw in commands:
		var c: Dictionary = raw
		if not dropped and String(c.get("status", "")) != ST_QUEUED:
			dropped = true
			continue
		keep.append(c)
	commands = keep
	if commands.size() > MAX_COMMANDS:
		commands.pop_front()

# ── issue / abort / tick ────────────────────────────────

func issue(unit: String, action: String, target: String, params: Dictionary, now_t: float) -> Dictionary:
	var act := String(action).to_upper()
	if commands.size() >= MAX_COMMANDS:
		_trim()
	var cmd := {
		"id": _make_id(),
		"unit": unit,
		"action": act,
		"target": target,
		"params": params.duplicate(true),
		"issue_t": now_t,
		"delay_s": 0.0,
		"exec_t": now_t,
		"status": ST_QUEUED,
		"via": "local",
		"plan": {},
		"applied_t": -1.0,
		"abort_t": -1.0,
		"authorization": "supervisor",
	}
	match act:
		ACT_SHADOW, ACT_STATION:
			cmd["delay_s"] = RELAY_DELAY_S
			cmd["via"] = RELAY_VIA
			cmd["exec_t"] = now_t + RELAY_DELAY_S
			cmd["plan"] = {
				"target": target,
				"exec_t": cmd["exec_t"],
				"note": "%s 中继 %.0f s" % [RELAY_VIA, RELAY_DELAY_S],
			}
		ACT_BURN:
			# 本舰计划点火：exec_t 是绝对 tau（默认 now + 6.2 s）
			var t_exec := float(params.get("exec_t", now_t + 6.2))
			var dv_ms := float(params.get("dv_ms", 84.0))
			var raw_dv = params.get("dv", null)
			var dv: Vector3
			if raw_dv == null:
				dv = dv_vector(float(params.get("brg", 340.0)), float(params.get("elev", 20.0)), dv_ms)
			else:
				dv = raw_dv
			var budget_ms := float(params.get("budget_ms", 1.0e9))
			cmd["exec_t"] = t_exec
			cmd["plan"] = {
				"dv_ms": dv_ms,
				"dv": dv,
				"brg": float(params.get("brg", 340.0)),
				"elev": float(params.get("elev", 20.0)),
				"lead_s": t_exec - now_t,
				"fuel_after_ms": budget_ms - dv_ms,
			}
			if dv_ms > budget_ms + 1.0e-6:
				cmd["status"] = ST_REJECTED
				cmd["plan"]["reason"] = "dv_insufficient"
		_:
			cmd["status"] = ST_REJECTED
			cmd["plan"] = {"reason": "unknown_action"}
	commands.append(cmd)
	return cmd

func abort(id: String, now_t: float) -> Dictionary:
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("id", "")) != id:
			continue
		if String(c.get("status", "")) == ST_QUEUED:
			c["status"] = ST_ABORTED
			c["abort_t"] = now_t
		return c
	return {}

# 撤销最新一条待生效命令（main 的 4 键预设）
func abort_latest(now_t: float) -> Dictionary:
	var target: Dictionary = {}
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) == ST_QUEUED:
			target = c
	if target.is_empty():
		return {}
	return abort(String(target.get("id", "")), now_t)

func tick(now_t: float) -> Array:
	var out: Array = []
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) != ST_QUEUED:
			continue
		if float(c.get("exec_t", 1.0e9)) <= now_t + 1.0e-6:
			c["status"] = ST_EXEC
			c["applied_t"] = now_t
			out.append(c)
	return out

# ── 查询 ────────────────────────────────────────────────

func by_id(id: String) -> Dictionary:
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("id", "")) == id:
			return c
	return {}

func pending() -> Array:
	var out: Array = []
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) == ST_QUEUED:
			out.append(c)
	return out

func pending_burns(now_t: float) -> Array:
	var out: Array = []
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) != ST_QUEUED:
			continue
		if String(c.get("action", "")) != ACT_BURN:
			continue
		if float(c.get("exec_t", 1.0e9)) < now_t:
			continue
		out.append(c)
	return out

func active_shadow() -> Dictionary:
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("action", "")) == ACT_SHADOW and String(c.get("status", "")) == ST_EXEC:
			return c
	return {}

func counted() -> Dictionary:
	var n := {ST_QUEUED: 0, ST_EXEC: 0, ST_ABORTED: 0, ST_REJECTED: 0}
	for raw in commands:
		var c: Dictionary = raw
		var st := String(c.get("status", ""))
		n[st] = int(n.get(st, 0)) + 1
	return n

# ── 本舰计划轨迹（给 plot 画预测虚线 / 点火节点 / 命令幽灵）──────
# start：当前实际状态 {r, v}（tau 坐标系）；burns：[{t: 绝对 tau, dv: Vector3, cmd: Dictionary}]
# 返回 {pts: Array[Vector3]（相对 start.r 的局部板 km）, rel: Array[float], events: [...]}
static func plan_own(start: Dictionary, start_tau: float, burns: Array, horizon: float, steps: int) -> Dictionary:
	var r0: Vector3 = start["r"]
	var v0: Vector3 = start["v"]
	var r := r0
	var v := v0
	var cur := start_tau
	var bs: Array = burns.duplicate()
	bs.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var bi := 0
	var n := maxi(2, steps)
	var pts: Array[Vector3] = []
	var rels: Array[float] = []
	var events: Array = []
	for i in range(n + 1):
		var t := horizon * float(i) / float(n)
		var abs_t := start_tau + t
		while bi < bs.size() and float((bs[bi] as Dictionary).get("t", 0.0)) <= abs_t + 1.0e-9:
			var ev: Dictionary = bs[bi]
			var ev_t := float(ev.get("t", 0.0))
			var st := Orbit.local_propagate(r, v, ev_t - cur)
			r = st["r"]
			v = st["v"] + (ev.get("dv", Vector3.ZERO) as Vector3)
			events.append({
				"rel": ev_t - start_tau,
				"km": r - r0,
				"dv": ev.get("dv", Vector3.ZERO),
				"cmd": ev.get("cmd", {}),
			})
			cur = ev_t
			bi += 1
		var st2 := Orbit.local_propagate(r, v, abs_t - cur)
		var pos: Vector3 = st2["r"]
		pts.append(pos - r0)
		rels.append(t)
	return {"pts": pts, "rel": rels, "events": events}
