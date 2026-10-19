extends RefCounted

# 命令模型（第一关子集）：STATION / SHADOW / BURN
#
# 设计口径（docs/13）：
#   - 玩家下的是意图；系统给出计划（exec_t / Δv / 预测），命令有延迟；
#   - 生效前可撤销；点火后不可撤销（BURN 只能接受新轨道）；
#   - Δv 是预算：BURN 扣 unit.dv，油船可补给（本版无补给）。
#
# 状态机（P1e 补齐）：
#   QUEUED ──tx_t 到达──▶ TRANSMITTED ──exec_t 到达──▶ EXEC ──done_t 到达──▶ DONE
#   QUEUED / TRANSMITTED ──abort()──▶ ABORTED      （生效前可撤销；点火后不可）
#   * ──issue() 校验失败──▶ REJECTED
#
# 时间字段：issue_t → tx_t（命令离舰/离中继）→ exec_t（点火/动作生效）→ done_t（回执）
# 延迟（docs/13 §6；07 §3）：
#   SHADOW / STATION：望楼号中继；tx_t = issue + LINK_TX_S(1s)，exec_t = issue + 8s
#   BURN：本舰本地计划点火；tx_t = issue（即时传达），exec_t 由计划给定（脚本 T+6.2s）
# DONE_ACK_S：动作回执时间（BURN 1s / SHADOW 3s / STATION 2s）
#
# 预览：preview() 生成同结构命令（status=DRAFT）但不入队、不扣 Δv，供 UI/plot 画 draft 节点。

const Orbit := preload("res://scripts/orbit_model.gd")

const RELAY_VIA := "望楼号"
const RELAY_DELAY_S := 8.0
const LINK_TX_S := 1.0

const ACT_STATION := "STATION"
const ACT_SHADOW := "SHADOW"
const ACT_BURN := "BURN"

const ST_QUEUED := "QUEUED"
const ST_TRANSMITTED := "TRANSMITTED"
const ST_EXEC := "EXEC"
const ST_DONE := "DONE"
const ST_ABORTED := "ABORTED"
const ST_REJECTED := "REJECTED"
const ST_DRAFT := "DRAFT"

const DONE_ACK_S := {"BURN": 1.0, "SHADOW": 3.0, "STATION": 2.0}
const MAX_COMMANDS := 10

var commands: Array = []
var selected_id := ""
var preview_cmd: Dictionary = {}
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
			return "排队"
		ST_TRANSMITTED:
			return "传达中"
		ST_EXEC:
			return "已执行"
		ST_DONE:
			return "已完成"
		ST_ABORTED:
			return "已撤销"
		ST_REJECTED:
			return "已拒绝"
		ST_DRAFT:
			return "预览"
		_:
			return status

func _make_id() -> String:
	var s := "CMD-%02d" % _next_id
	_next_id += 1
	return s

func _trim() -> void:
	var keep: Array = []
	var dropped := false
	for raw in commands:
		var c: Dictionary = raw
		var st := String(c.get("status", ""))
		if not dropped and st != ST_QUEUED and st != ST_TRANSMITTED:
			dropped = true
			continue
		keep.append(c)
	commands = keep
	if commands.size() > MAX_COMMANDS:
		commands.pop_front()

# ── 命令对象构造 ────────────────────────────────────────

func _build(unit: String, action: String, target: String, params: Dictionary, now_t: float, id: String) -> Dictionary:
	var act := String(action).to_upper()
	var cmd := {
		"id": id,
		"unit": unit,
		"action": act,
		"target": target,
		"params": params.duplicate(true),
		"issue_t": now_t,
		"delay_s": 0.0,
		"tx_t": now_t,
		"exec_t": now_t,
		"done_t": -1.0,
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
			cmd["tx_t"] = now_t + LINK_TX_S
			cmd["exec_t"] = now_t + RELAY_DELAY_S
			cmd["plan"] = {
				"target": target,
				"tx_t": cmd["tx_t"],
				"exec_t": cmd["exec_t"],
				"note": "%s 中继 %.0f s（先传达 %.0f s，再执行准备）" % [RELAY_VIA, RELAY_DELAY_S, LINK_TX_S],
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
			cmd["tx_t"] = now_t          # 本舰点火指令即时传达
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
	cmd["done_t"] = float(cmd["exec_t"]) + float(DONE_ACK_S.get(act, 2.0))
	return cmd

func issue(unit: String, action: String, target: String, params: Dictionary, now_t: float) -> Dictionary:
	if commands.size() >= MAX_COMMANDS:
		_trim()
	var cmd := _build(unit, action, target, params, now_t, _make_id())
	commands.append(cmd)
	return cmd

# 预览：同结构命令，不入队、不扣 Δv；供 plot 画 draft 节点 / UI 预览面板
func preview(unit: String, action: String, target: String, params: Dictionary, now_t: float) -> Dictionary:
	var cmd := _build(unit, action, target, params, now_t, "DRAFT")
	cmd["status"] = ST_DRAFT
	var plan: Dictionary = cmd.get("plan", {})
	plan["preview"] = true
	preview_cmd = cmd
	return cmd

func clear_preview() -> void:
	preview_cmd = {}

# ── 状态推进 ────────────────────────────────────────────

func abort(id: String, now_t: float) -> Dictionary:
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("id", "")) != id:
			continue
		var st := String(c.get("status", ""))
		if st == ST_QUEUED or st == ST_TRANSMITTED:
			c["status"] = ST_ABORTED
			c["abort_t"] = now_t
		return c
	return {}

func abort_latest(now_t: float) -> Dictionary:
	var target: Dictionary = {}
	for raw in commands:
		var c: Dictionary = raw
		var st := String(c.get("status", ""))
		if st == ST_QUEUED or st == ST_TRANSMITTED:
			target = c
	if target.is_empty():
		return {}
	return abort(String(target.get("id", "")), now_t)

# 每次仿真 tick 调用。返回本 tick 发生的状态迁移：
#   {"transmitted": [...], "exec": [...], "done": [...]}
func tick(now_t: float) -> Dictionary:
	var tx: Array = []
	var ex: Array = []
	var dn: Array = []
	# 1) QUEUED → TRANSMITTED
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) != ST_QUEUED:
			continue
		if float(c.get("tx_t", 1.0e9)) <= now_t + 1.0e-6:
			c["status"] = ST_TRANSMITTED
			c["tx_actual_t"] = now_t
			tx.append(c)
	# 2) TRANSMITTED → EXEC
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) != ST_TRANSMITTED:
			continue
		if float(c.get("exec_t", 1.0e9)) <= now_t + 1.0e-6:
			c["status"] = ST_EXEC
			c["applied_t"] = now_t
			ex.append(c)
	# 3) EXEC → DONE（回执）
	for raw in commands:
		var c: Dictionary = raw
		if String(c.get("status", "")) != ST_EXEC:
			continue
		if float(c.get("done_t", 1.0e9)) <= now_t + 1.0e-6:
			c["status"] = ST_DONE
			c["done_actual_t"] = now_t
			dn.append(c)
	return {"transmitted": tx, "exec": ex, "done": dn}

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
		var st := String(c.get("status", ""))
		if st == ST_QUEUED or st == ST_TRANSMITTED:
			out.append(c)
	return out

func pending_burns(now_t: float) -> Array:
	var out: Array = []
	for raw in commands:
		var c: Dictionary = raw
		var st := String(c.get("status", ""))
		if st != ST_QUEUED and st != ST_TRANSMITTED:
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
	var n := {}
	for raw in commands:
		var c: Dictionary = raw
		var st := String(c.get("status", ""))
		n[st] = int(n.get(st, 0)) + 1
	return n

# 状态机文字（给 plot/UI）：下一里程碑与倒计时
func phase_text(cmd: Dictionary, now_t: float) -> String:
	var st := String(cmd.get("status", ""))
	match st:
		ST_QUEUED:
			return "等待传达 %.1fs" % maxf(0.0, float(cmd.get("tx_t", now_t)) - now_t)
		ST_TRANSMITTED:
			return "传达中 · 生效 %.1fs" % maxf(0.0, float(cmd.get("exec_t", now_t)) - now_t)
		ST_EXEC:
			return "执行中 · 回执 %.1fs" % maxf(0.0, float(cmd.get("done_t", now_t)) - now_t)
		ST_DONE:
			return "已完成"
		ST_ABORTED:
			return "已撤销"
		ST_REJECTED:
			return "已拒绝"
		ST_DRAFT:
			return "预览（未下注）"
		_:
			return st

# ── 本舰计划轨迹（给 plot 画预测虚线 / 点火节点 / 命令幽灵）──────
# start：当前实际状态 {r, v}（tau 坐标系）；burns：[{t: 绝对 tau, dv: Vector3, cmd}]
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
