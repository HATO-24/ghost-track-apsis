class_name V2World
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 世界状态容器（纯数据；UI 只能通过只读 view-model 或明确命令方法修改）
#
#   容器：实体 / 航迹 / 选中 / 时间 / 图层 / 命令 / 证据 / 事件流
#   只读查询：vm_* 系列返回普通 Dictionary，UI 不需要碰内部对象。
#   数据来源：V2Scenario（V2 schema 或 v15 迁移），规则来自 content/*.json。
#   本类不做传感器数学、不做渲染、不模拟武器。
#
#   V2-CORE-2（V2-3 第一关端到端）追加：
#     perform_action（7 个支持动作 → 观测/状态）、prelude_*、start_evidence/任务推进、
#     open_decision/choose_ending/submit_report/end_summary/restart、mission flag 联动。
#     TEXT-ENGINE-1：story 文本由玩家动作触发（mission.story_triggers），不再按 t 自动播报。
#     时间在前置航行完成/任务结束时会冻结（不自动做玩家识别动作）。
# ═══════════════════════════════════════════════════════════════════

signal state_changed(reason: String)
signal log_event(kind: String, text: String)
signal track_changed(track_id: String, reason: String)
signal order_changed(order_data: Dictionary)
signal evidence_changed(id: String, state: String)
signal flow_changed(reason: String)

const TRACK_RULES_PATH := "res://framework/content/track_rules.json"
const MAX_EVENT_LOG := 256

var scenario: V2Scenario = null
var entities: Array[V2Entity] = []
var by_id: Dictionary = {}
var own_id := ""
var selected_id := ""
var t := 0.0
var layers := {
	"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true,
}

var tracks: V2TrackTable = null
var orders: V2Orders = null
var evidence: Dictionary = {}
var evidence_policy: Dictionary = {}
var phase_context := ""          # mission 可写入当前阶段 kind，供动作/UI 过滤
var errors: Array[String] = []
var warnings: Array[String] = []
var events: Array = []
var radio: Array = []

# —— V2-CORE-2 流程状态 ——
var mission = null               # V2Mission（不写类型标注：避免与 mission.gd 的循环依赖）
var mission_auto := true         # advance() 时自动推进一格任务阶段（false 时由 UI 调 advance_mission）
var prelude: Dictionary = {}     # 前置航行状态（route/window/execute/skip）
var flow: Dictionary = {}        # decision / report / end / consequence
var flow_flags: Dictionary = {}  # 流程 flag（自动同步给 mission）
var civilians_evacuated := false
var audit_count := 0
var story_events_data: Array = []   # 时间线事件（story.events）
var story_radio_data: Array = []    # 时间线通信（story.radio_lines）
var _fired_events: Dictionary = {}
var _fired_radio: Dictionary = {}

# —— V2-CORE-3 系统 ——
var tutorial: Dictionary = {}        # 教学门控（story.tutorial）
var exec_window_s := 360.0           # 执行窗口（秒）
var exec_frozen_left := -1.0         # 决策后冻结的剩余时间
var reputation: Dictionary = {}      # 运行时声望（story.reputation 基线 + 结局差量）
var damage: Array = []               # 引用 own.damage_sections（本舰损管项）
var damage_repair_rate_s := 120.0
var replay: Dictionary = {}          # 回放入口（只读帧，不推进世界）
var _last_replay_t := -1.0

# —— R2-DAMAGE-2：完整损管模型接入（entity.damage = V2DamageModel）——
const DamageModelScript := preload("res://framework/core/damage_model.gd")
const MAX_DAMAGE_EVENTS := 128
var damage_content: Dictionary = {}      # damage_l1.json（本舰/敌舰档案；只读参数来自内容）
var damage_events_log: Array = []        # 统一损管事件（只读；含 entity_id）
var _damage_last_seq: Dictionary = {}    # entity_id -> 已记录事件 seq（去重）

# ── 场景装载 ─────────────────────────────────────────────────────

func load_scenario(s: V2Scenario) -> bool:
	errors.clear()
	warnings.clear()
	events.clear()
	radio.clear()
	t = 0.0
	scenario = s
	if s == null:
		errors.append("load_scenario: scenario 为空")
		return false
	for e in s.errors:
		errors.append(String(e))
	for w in s.warnings:
		warnings.append(String(w))
	_load_entities(s)
	_load_tracks(s)
	_load_orders(s)
	_load_evidence(s)
	_init_flow(s)
	_init_damage_models(s)
	# 自动化钩子（headless 探针/截图）：DSH_SKIP_PRELUDE=1 时跳过前置航行，时间立即可流动。
	if OS.get_environment("DSH_SKIP_PRELUDE") == "1" and prelude_open():
		prelude_skip()
	sync_entities()
	selected_id = own_id
	if selected_id != "":
		state_changed.emit("select")
	state_changed.emit("load")
	push_log(("load"), "场景装载：%s · entities=%d tracks=%d phases=%d migrated=%s" % [
		s.id, entities.size(), tracks.count() if tracks != null else 0,
		s.phases.size(), str(s.migrated)])
	if mission != null:
		mission.attach_scenario(s)
	return errors.is_empty()

func _load_entities(s: V2Scenario) -> void:
	entities.clear()
	by_id.clear()
	own_id = ""
	for e in s.entities:
		entities.append(e)
		by_id[e.id] = e
	if by_id.has(s.own_entity_id):
		own_id = s.own_entity_id
	if own_id == "":
		for e in entities:
			if "own" in e.tags or "own_fleet" in e.tags:
				own_id = e.id
				break
	if own_id == "":
		for e in entities:
			if e.side == "friend":
				own_id = e.id
				break
	if own_id == "" and entities.size() > 0:
		own_id = entities[0].id
		warnings.append("世界装载：无己方实体，默认选中第一实体 " + own_id)

func _load_tracks(s: V2Scenario) -> void:
	var rule_errors: Array = []
	var rules := V2TrackTable.load_rules(TRACK_RULES_PATH, rule_errors)
	for e in rule_errors:
		errors.append(String(e))
	tracks = V2TrackTable.new(rules)
	for raw_seed in s.initial_tracks:
		if raw_seed is Dictionary:
			tracks.seed(raw_seed, t)
	for e in tracks.errors:
		errors.append("track: " + String(e))

func _load_orders(s: V2Scenario) -> void:
	orders = V2Orders.new(s.orders_config)
	if not orders.order_changed.is_connected(_on_order_changed):
		orders.order_changed.connect(_on_order_changed)

func _load_evidence(s: V2Scenario) -> void:
	evidence.clear()
	evidence_policy = s.evidence_policy.duplicate(true)
	for raw_id in s.evidence_defs.keys():
		var id := String(raw_id)
		var def: Dictionary = (s.evidence_defs[id] as Dictionary).duplicate(true)
		evidence[id] = {
			"id": id,
			"label": String(def.get("label", id)),
			"duration_s": float(def.get("duration_s", 0.0)),
			"shuttle": bool(def.get("shuttle", false)),
			"flags_on_done": (def.get("flags_on_done", []) as Array).duplicate(),
			"risk": String(def.get("risk", "")),
			"start_text": String(def.get("start_text", "")),
			"done_text": String(def.get("done_text", "")),
			"state": "unknown",
			"started_t": -1.0,
			"done_t": -1.0,
			"def": def,
		}

## 初始化流程状态（前置航行 / 决策 / 报告 / 时间线 / flag），全部来自场景数据。
func _init_flow(s: V2Scenario) -> void:
	flow = {
		"decision_open": false, "decision": {}, "decision_t": -1.0,
		"report": {}, "report_open": false, "report_available": false,
		"ended": false, "fire_release": false, "consequence": "", "ending": {},
		"reputation": s.reputation_base(),
	}
	flow_flags.clear()
	civilians_evacuated = false
	audit_count = 0
	_fired_events.clear()
	_fired_radio.clear()
	story_events_data = s.story_events()
	story_radio_data = s.story_radio()
	var pd := s.prelude_data()
	var enabled := s.prelude_enabled() and not pd.is_empty()
	prelude = {
		"open": enabled,
		"executed": false,
		"step": 0,
		"route": "",
		"window": "",
		"confirmed": false,
		"dv_spent_ms": 0.0,
		"data": pd,
		"title": String(pd.get("title", "前置航行 / PRELUDE")),
		"body": String(pd.get("body", "")),
		"routes": (pd.get("routes", []) as Array).duplicate(true),
		"windows": (pd.get("windows", []) as Array).duplicate(true),
	}
	if mission != null:
		phase_context = String(mission.kind)
	_init_systems(s)

## V2-CORE-3：教学门控 / 损坏 / 执行窗口 / 声望 / 回放（全部来自场景与 story 数据）。
func _init_systems(s: V2Scenario) -> void:
	# 教学门控
	tutorial = {"enabled": false, "title": "", "hint": "", "required_actions": [],
		"min_required": 0, "labels": {}, "done_text": "", "completed": {}}
	var tut = s.story.get("tutorial", null)
	if tut is Dictionary and bool((tut as Dictionary).get("enabled", false)):
		var td: Dictionary = tut
		tutorial["enabled"] = true
		tutorial["title"] = String(td.get("title", "教学 / TUTORIAL"))
		tutorial["hint"] = String(td.get("hint", ""))
		tutorial["required_actions"] = (td.get("required_actions", []) as Array).duplicate()
		tutorial["min_required"] = int(td.get("min_required", 0))
		tutorial["labels"] = (td.get("step_labels", {}) as Dictionary).duplicate(true)
		tutorial["done_text"] = String(td.get("done_text", ""))
	if OS.get_environment("DSH_SKIP_TUTORIAL") == "1":
		tutorial["enabled"] = false
	# 执行窗口
	exec_window_s = float(s.exec_window_config.get("duration_s", 360.0))
	if exec_window_s <= 0.0:
		exec_window_s = 360.0
	exec_frozen_left = -1.0
	# 声望基线（五方）
	reputation = s.reputation_base()
	for k in ["ocu", "meridian", "ueg_doves", "outer", "reclaimers"]:
		if not reputation.has(k):
			reputation[k] = 0
	flow["reputation"] = reputation.duplicate(true)
	flow["reputation_settled"] = false
	flow["decision_pending"] = false
	# 损管：初始化本舰 damage_sections / damage_queue（数据来自 content damage.initial）
	damage = []
	var own_e := own()
	if own_e != null:
		own_e.damage_sections.clear()
		own_e.damage_queue.clear()
		damage = own_e.damage_sections
	damage_repair_rate_s = float(s.damage_config.get("repair_rate_s", 120.0))
	for raw in (s.damage_config.get("initial", []) as Array):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		var sev := clampf(float(d.get("severity", 0.0)), 0.0, 1.0)
		var state := String(d.get("state", "degraded"))
		if not (state in ["ok", "degraded", "damaged", "repairing", "repaired"]):
			state = "degraded"
		damage.append({
			"id": String(d.get("id", "")),
			"label": String(d.get("label", d.get("id", ""))),
			"state": state, "severity": sev,
			"repair_eta_s": float(d.get("repair_eta_s", maxf(15.0, sev * damage_repair_rate_s))),
			"repair_progress_s": 0.0, "started_t": -1.0, "entity_id": own_id,
		})
	# 回放
	replay = {"recording": true, "playing": false, "paused": false, "index": 0,
		"interval_s": 1.0, "buffer": []}
	_last_replay_t = -1.0
	_replay_capture(true)

func _on_order_changed(order_data: Dictionary) -> void:
	order_changed.emit(order_data)
	state_changed.emit("order")
	var oid := String(order_data.get("id", ""))
	var st := String(order_data.get("state", ""))
	push_log("order", "命令 %s · %s → %s%s" % [oid, String(order_data.get("action", "")), st,
		("（%s）" % String(order_data.get("reason", ""))) if String(order_data.get("reason", "")) != "" else ""])

# ── 旧 V2-0 兼容查询 ─────────────────────────────────────────────

func selected() -> V2Entity:
	return by_id.get(selected_id)

func own() -> V2Entity:
	return by_id.get(own_id)

func entity(eid: String) -> V2Entity:
	return by_id.get(eid)

func visible_entities() -> Array[V2Entity]:
	var out: Array[V2Entity] = []
	for e in entities:
		if e.side == "unknown" and not bool(layers.get("contacts", true)):
			continue
		out.append(e)
	return out

# ── 选择 ─────────────────────────────────────────────────────────

## 接受实体 id 或航迹 id（虚警/纯回波没有实体，只能按航迹选中）。
func select(id: String) -> bool:
	var known := by_id.has(id) or (tracks != null and tracks.find(id) != null)
	if not known:
		return false
	selected_id = id
	state_changed.emit("select")
	_note_story_event("select", "select", id)
	return true

func select_batch(batch: String) -> bool:
	for e in entities:
		if e.id == batch or e.batch == batch:
			return select(e.id)
	return false

func selected_entity() -> V2Entity:
	var e: V2Entity = by_id.get(selected_id)
	if e != null:
		return e
	if tracks != null:
		var tr := tracks.find(selected_id)
		if tr != null and tr.entity_id != "":
			return by_id.get(tr.entity_id)
	return null

func selected_track() -> V2Track:
	if tracks == null:
		return null
	var tr := tracks.find(selected_id)
	if tr != null:
		return tr
	var e: V2Entity = by_id.get(selected_id)
	if e != null:
		return tracks.find_by_entity(e.id)
	return null

func track_for(id: String) -> V2Track:
	if tracks == null:
		return null
	var tr := tracks.find(id)
	if tr != null:
		return tr
	return tracks.find_by_entity(id)

# ── 时间推进 / 图层 / 日志 ───────────────────────────────────────

## 推进世界时间：自动时间线 + 证据任务 + 损管 + 命令队列 + 航迹衰减 + 任务阶段 + 执行窗口。
## 前置航行未完成 / 任务已结束时冻结时间（dt 被忽略，返回 frozen=true）。
func advance(dt: float) -> Dictionary:
	var out := {"orders": [], "tracks": [], "events": [], "radio": [], "tasks": [],
		"damage": [], "phase": {}, "frozen": false}
	if dt <= 0.0:
		return out
	var frozen := _time_frozen()
	if frozen:
		out["frozen"] = true
		return out
	t += dt
	# TEXT-ENGINE-1：story.events/radio_lines 不再按时间自动播报；
	# 只有 story.triggers 的 environment 类（如需保留的纯倒计时）在 advance 内触发。
	# 玩家动作触发的文本由各命令方法同步 push（_note_story_event）。
	out["events"] = _tick_story_environment()
	out["radio"] = []
	out["tasks"] = _tick_evidence_tasks()
	out["damage"] = advance_damage(dt)
	out["damage_events"] = _advance_damage_models(dt)
	if orders != null:
		out["orders"] = orders.tick(t)
	if tracks != null:
		out["tracks"] = tracks.expire(t)
	sync_entities()
	for raw in (out["tracks"] as Array):
		var tr: Dictionary = raw
		track_changed.emit(String(tr.get("track_id", "")), "decay")
		push_log("track", "航迹 %s 等级衰减 L%d → L%d" % [
			String(tr.get("track_id", "")), int(tr.get("from", 0)), int(tr.get("to", 0))])
	# 执行窗口结束仍无决策 → 打开决策（教学门控未满足时挂起 pending）
	_tick_exec_window()
	# 教学门控 pending：玩家补完识别后自动打开决策
	_try_open_pending_decision()
	if mission_auto:
		out["phase"] = _advance_mission_once()
	_replay_capture()
	state_changed.emit("tick")
	return out

# —— V2-CORE-3：执行窗口 ——

func exec_left() -> float:
	if not (flow.get("decision", {}) as Dictionary).is_empty() and exec_frozen_left >= 0.0:
		return exec_frozen_left
	if bool(prelude.get("executed", false)):
		return maxf(0.0, exec_window_s - t)
	return exec_window_s

func exec_pct() -> float:
	if exec_window_s <= 0.0:
		return 0.0
	return clampf(1.0 - exec_left() / exec_window_s, 0.0, 1.0)

func _tick_exec_window() -> void:
	if not bool(prelude.get("executed", false)):
		return
	if bool(flow.get("ended", false)):
		return
	if not (flow.get("decision", {}) as Dictionary).is_empty():
		return
	if bool(flow.get("decision_open", false)) or bool(flow.get("decision_pending", false)):
		return
	if t >= exec_window_s:
		push_log("decision", "执行窗口结束（%s s）" % str(exec_window_s))
		open_decision()

## 任务/前置航行是否冻结世界时间。
func _time_frozen() -> bool:
	if bool(prelude.get("open", false)) and not bool(prelude.get("executed", false)):
		return true
	if bool(flow.get("ended", false)):
		return true
	return false

## 证据任务推进入口（任务随 world.advance 自动推进；此方法为流程/测试的明确入口，等价 advance）。
func advance_tasks(dt: float) -> Dictionary:
	return advance(dt)

func set_layer(name: String, on: bool) -> void:
	if layers.has(name):
		layers[name] = on
		state_changed.emit("layer")

func push_log(kind: String, text: String) -> void:
	events.append({"kind": kind, "text": text, "t": t})
	while events.size() > MAX_EVENT_LOG:
		events.pop_front()
	log_event.emit(kind, text)

func push_radio(line: Dictionary) -> void:
	var d: Dictionary = line.duplicate(true)
	if not d.has("t"):
		d["t"] = t
	radio.append(d)
	while radio.size() > MAX_EVENT_LOG:
		radio.pop_front()
	state_changed.emit("radio")

func recent_events(n := 8) -> Array:
	var out: Array = []
	var start := maxi(0, events.size() - n)
	for i in range(start, events.size()):
		out.append((events[i] as Dictionary).duplicate(true))
	return out

func recent_radio(n := 8) -> Array:
	var out: Array = []
	var start := maxi(0, radio.size() - n)
	for i in range(start, radio.size()):
		out.append((radio[i] as Dictionary).duplicate(true))
	return out

# ── 航迹/观测 ────────────────────────────────────────────────────

## 融合一条观测（sim 层产出，core 只消费）。返回 V2Track。
func ingest(obs: Dictionary) -> V2Track:
	if tracks == null:
		errors.append("ingest: 世界未装载航迹表")
		return null
	var tr := tracks.ingest(obs, t)
	if tr != null:
		sync_entities()
		track_changed.emit(tr.id, "observation")
		state_changed.emit("observation")
	return tr

func observe_entity(entity_id: String, obs: Dictionary) -> V2Track:
	var o: Dictionary = obs.duplicate(true)
	o["entity_id"] = entity_id
	return ingest(o)

func observe_track(track_id: String, obs: Dictionary) -> V2Track:
	var o: Dictionary = obs.duplicate(true)
	o["track_id"] = track_id
	return ingest(o)

## 脚本/剧情设定身份（例如光学分类后判可疑）；与等级分开。
func set_track_identity(id: String, kind: String, details: Dictionary = {}) -> bool:
	var tr := track_for(id)
	if tr == null:
		return false
	tr.set_identity(kind, details, t)
	sync_entities()
	track_changed.emit(tr.id, "identity")
	state_changed.emit("identity")
	return true

func set_track_level(id: String, level: int, note := "") -> bool:
	if tracks == null:
		return false
	var tr := track_for(id)
	if tr == null:
		return false
	tracks.set_level(tr.id, level, t, note)
	sync_entities()
	track_changed.emit(tr.id, "level")
	state_changed.emit("level")
	return true

## 把航迹等级/身份/威胁同步到实体快照（V2-0 UI 兼容层，逻辑仍以航迹为准）。
func sync_entities() -> void:
	if tracks == null:
		return
	for e in entities:
		var tr := tracks.find_by_entity(e.id)
		if tr == null and e.batch != "":
			tr = tracks.find(e.batch)
		if tr == null:
			tr = tracks.find(e.id)
		if tr == null:
			continue
		e.track_level = tr.level
		e.identity = tr.identity_kind
		e.threat = tr.threat

# ── 命令 ─────────────────────────────────────────────────────────

## 发预命令：校验动作可用性后创建 PRE_ORDER（不推进时间、不入队）。
func issue_order(action_id: String, target_id := "", params: Dictionary = {}) -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var actor := own()
	if actor == null:
		return {"ok": false, "reason": "无己方实体（actor 为空）"}
	var target: V2Entity = by_id.get(target_id)
	var tr := track_for(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	if target == null and tr == null:
		return {"ok": false, "reason": "目标不存在: " + target_id}
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var eval := V2Actions.available_one(action_id, actor, target, tr, ctx)
	if eval.is_empty():
		return {"ok": false, "reason": "未知动作: " + action_id}
	if not bool(eval.get("available", false)):
		# 本舰能力不足时，命令可由舰队内可执行该动作的平台承接（如 IFF 由远地点执行）。
		var alt := _find_fleet_actor(action_id, target, tr, ctx)
		if not alt.is_empty():
			actor = alt.get("actor", actor)
			eval = alt.get("eval", eval)
	if not bool(eval.get("available", false)):
		return {"ok": false, "reason": String(eval.get("reason", "不可用")),
			"reason_code": String(eval.get("reason_code", "")), "action": eval}
	var p: Dictionary = params.duplicate(true)
	if not p.has("duration_s"):
		p["duration_s"] = float(eval.get("duration_s", 0.0))
	var o := orders.issue(action_id, target_id, p, actor.id, tr.id if tr != null else "", t)
	push_log("order", "预命令 %s · %s → %s（%s，不推进仿真）" % [o.id, action_id, target_id, actor.display_name()])
	state_changed.emit("order")
	_note_story_event("order", action_id, target_id, {"state": "PRE_ORDER"})
	return {"ok": true, "reason": "", "order": o, "action": eval, "actor_id": actor.id}

func authorize_order(order_id: String) -> Dictionary:
	return _order_action("authorize", order_id)

func enqueue_order(order_id: String) -> Dictionary:
	return _order_action("enqueue", order_id)

func transmit_order(order_id: String) -> Dictionary:
	return _order_action("transmit", order_id)

func begin_order(order_id: String) -> Dictionary:
	return _order_action("begin_exec", order_id)

func complete_order(order_id: String) -> Dictionary:
	return _order_action("complete", order_id)

func abort_order(order_id: String, reason := "指挥官撤销") -> Dictionary:
	return _order_action("abort", order_id, reason)

func reject_order(order_id: String, reason := "授权驳回") -> Dictionary:
	return _order_action("reject", order_id, reason)

func abort_latest_order(reason := "指挥官撤销") -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var r := orders.abort_latest(t, reason)
	if bool(r.get("ok", false)):
		state_changed.emit("order")
	return r

func _order_action(method: String, order_id: String, reason := "") -> Dictionary:
	if orders == null:
		return {"ok": false, "reason": "世界未装载命令队列"}
	var r: Dictionary
	match method:
		"authorize":
			r = orders.authorize(order_id, t)
		"enqueue":
			r = orders.enqueue(order_id, t)
		"transmit":
			r = orders.transmit(order_id, t)
		"begin_exec":
			r = orders.begin_exec(order_id, t)
		"complete":
			r = orders.complete(order_id, t, reason)
		"abort":
			r = orders.abort(order_id, t, reason)
		"reject":
			r = orders.reject(order_id, t, reason)
		_:
			r = {"ok": false, "reason": "未知命令操作: " + method}
	state_changed.emit("order")
	if bool(r.get("ok", false)):
		var oo: V2Orders.Order = orders.find(order_id)
		var st := String(oo.state) if oo != null else ""
		var act := String(oo.action) if oo != null else ""
		var tgt := String(oo.target) if oo != null else ""
		_note_story_event("order", act, tgt, {"state": st, "order_id": order_id, "method": method})
	return r

func order_of(order_id: String) -> V2Orders.Order:
	return orders.find(order_id) if orders != null else null

# ── 证据 / 取证任务 ──────────────────────────────────────────────

## 开始取证任务。穿梭机任务互斥（遥测/ELINT 等远程任务可并行）。
## 返回 {ok, reason, task}。
func start_evidence(id: String) -> Dictionary:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return {"ok": false, "reason": "未知证据任务: " + id, "task": null}
	var d: Dictionary = ev
	var state := String(d.get("state", ""))
	if state == "done":
		return {"ok": false, "reason": "任务已完成: " + String(d.get("label", id)), "task": d.duplicate(true)}
	if state == "in_progress":
		return {"ok": false, "reason": "任务已在进行: " + String(d.get("label", id)), "task": d.duplicate(true)}
	if bool(d.get("shuttle", false)):
		var busy := _shuttle_task()
		if busy != "":
			return {"ok": false, "reason": "穿梭机占用中（%s），需等待其完成" % String((evidence[busy] as Dictionary).get("label", busy)),
				"task": d.duplicate(true), "busy_with": busy}
	d["state"] = "in_progress"
	d["started_t"] = t
	evidence_change_emit(id, "in_progress")
	push_log("evidence", "开始取证：%s%s" % [String(d.get("label", id)),
		"（穿梭机）" if bool(d.get("shuttle", false)) else ""])
	flow_changed.emit("evidence_start")
	_note_story_event("evidence", "start", id)
	return {"ok": true, "reason": "", "task": d.duplicate(true)}

func evidence_start(id: String) -> bool:
	return bool(start_evidence(id).get("ok", false))

func evidence_complete(id: String) -> bool:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return false
	var d: Dictionary = ev
	if String(d.get("state", "")) == "done":
		return false
	d["state"] = "done"
	d["done_t"] = t
	for raw_flag in (d.get("flags_on_done", []) as Array):
		_set_flag(String(raw_flag), true)
	evidence_change_emit(id, "done")
	push_log("evidence", "证据取得：%s" % String(d.get("label", id)))
	_replay_capture(true)
	flow_changed.emit("evidence_done")
	_note_story_event("evidence", "complete", id)
	return true

## 当前占用的穿梭机任务 id（"" 表示空闲）。
func _shuttle_task() -> String:
	for k in evidence.keys():
		var d: Dictionary = evidence[k]
		if bool(d.get("shuttle", false)) and String(d.get("state", "")) == "in_progress":
			return String(k)
	return ""

## 任务推进：到期的进行中任务自动完成（在 advance 内调用，需 prior t 已推进）。
func _tick_evidence_tasks() -> Array:
	var done: Array = []
	for k in evidence.keys():
		var d: Dictionary = evidence[k]
		if String(d.get("state", "")) != "in_progress":
			continue
		var dur := float(d.get("duration_s", 0.0))
		if dur <= 0.0:
			continue
		var started := float(d.get("started_t", t))
		if t - started >= dur - 1.0e-6:
			if evidence_complete(String(k)):
				done.append({"id": String(k), "label": String(d.get("label", k)),
					"flags": (d.get("flags_on_done", []) as Array).duplicate()})
	return done

func evidence_remaining(id: String) -> float:
	var ev = evidence.get(id)
	if not (ev is Dictionary):
		return -1.0
	var d: Dictionary = ev
	if String(d.get("state", "")) != "in_progress":
		return 0.0
	return maxf(0.0, float(d.get("duration_s", 0.0)) - (t - float(d.get("started_t", t))))

func evidence_add(id: String) -> bool:
	return evidence_complete(id)

func evidence_change_emit(id: String, new_state: String) -> void:
	state_changed.emit("evidence")
	evidence_changed.emit(id, new_state)

func evidence_count() -> int:
	var n := 0
	for k in evidence.keys():
		if String((evidence[k] as Dictionary).get("state", "")) == "done":
			n += 1
	return n

func can_expose() -> bool:
	var need := int(evidence_policy.get("min_for_expose", 2))
	return evidence_count() >= need

func evidence_ids() -> Array:
	var out: Array = []
	for k in evidence.keys():
		out.append(String(k))
	return out

# ── 只读 view-model（UI 消费）────────────────────────────────────

func vm_state() -> Dictionary:
	var phase := String(mission.phase) if mission != null else ""
	var phase_kind := String(mission.kind) if mission != null else ""
	return {
		"t": t, "scenario_id": scenario.id if scenario != null else "",
		"title": scenario.title if scenario != null else "",
		"own_id": own_id, "selected_id": selected_id, "phase_context": phase_context,
		"phase": phase, "phase_kind": phase_kind,
		"prelude_open": bool(prelude.get("open", false)),
		"prelude_executed": bool(prelude.get("executed", false)),
		"decision_open": bool(flow.get("decision_open", false)),
		"decision_made": not (flow.get("decision", {}) as Dictionary).is_empty(),
		"report_submitted": not (flow.get("report", {}) as Dictionary).is_empty(),
		"ended": bool(flow.get("ended", false)),
		"fire_release": bool(flow.get("fire_release", false)),
		"civilians_evacuated": civilians_evacuated,
		"time_frozen": _time_frozen(),
		"audit_flag": bool(flow.get("report", {}).get("audit_flag", false)),
		"entity_count": entities.size(),
		"track_count": tracks.count() if tracks != null else 0,
		"order_count": orders.orders.size() if orders != null else 0,
		"evidence_count": evidence_count(),
		"evidence_total": evidence.size(),
		"can_expose": can_expose(),
		"layers": layers.duplicate(true),
		"migrated": scenario.migrated if scenario != null else false,
		"flags": flow_flags.duplicate(true),
		# V2-CORE-3
		"tutorial_ready": tutorial_ready(),
		"tutorial_pending_decision": bool(flow.get("decision_pending", false)),
		"exec_window_s": exec_window_s,
		"exec_left": exec_left(),
		"exec_pct": exec_pct(),
		"replay_recording": bool(replay.get("recording", false)),
		"damage_damaged": int((vm_damage_summary()).get("damaged", 0)),
		"damage_repairing": int((vm_damage_summary()).get("repairing", 0)),
		"errors": errors.duplicate(), "warnings": warnings.duplicate(),
	}

## 接触列表行（航迹 + 实体资料合并；UI 不写死批号）。
func vm_contacts() -> Array:
	var out: Array = []
	if tracks == null:
		return out
	for raw in tracks.tracks:
		var tr: V2Track = raw
		var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
		out.append(_contact_row(tr, e))
	return out

func vm_contact(id: String) -> Dictionary:
	var tr := track_for(id)
	if tr == null:
		return {}
	var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
	return _contact_row(tr, e)

func _contact_row(tr: V2Track, e: V2Entity) -> Dictionary:
	var row := {
		"track_id": tr.id, "entity_id": tr.entity_id,
		"batch": (e.batch if e != null and e.batch != "" else tr.id),
		"level": tr.level, "level_name": tr.level_name(), "level_label": tr.level_label(),
		"identity": tr.identity_kind, "identity_label": tr.identity_label(),
		"threat": tr.threat, "stale": tr.stale, "age_s": tr.age_s,
		"bearing_deg": tr.bearing_deg, "range_km": tr.range_km,
		"bearing_only": tr.is_bearing_only(), "sources": tr.sources.duplicate(),
		"quality": tr.quality, "observation_count": tr.observation_count,
		"selected": tr.id == selected_id or (e != null and e.id == selected_id),
		"tags": tr.tags.duplicate(), "notes": tr.notes.duplicate(),
	}
	if e != null:
		row["name"] = e.name
		row["name_en"] = e.name_en
		row["class"] = e.cls
		row["role"] = e.role
		row["side"] = e.side
		row["faction"] = e.faction
		row["kind"] = e.kind
		row["has_entity"] = true
		# 站体/储罐/固定设施（V2-CORE-3；UI 画标记用，不做渲染）
		row["fixed"] = e.is_fixed()
		row["icon"] = e.icon()
		row["size_km"] = e.size_km()
		row["display_kind"] = e.display_kind()
		row["entity_tags"] = e.tags.duplicate()
		if bool(e.is_fixed()):
			row["orbit_source"] = "fixed"
	else:
		row["name"] = "无实体接触"
		row["name_en"] = ""
		row["class"] = ""
		row["role"] = ""
		row["side"] = "unknown"
		row["faction"] = ""
		row["kind"] = "contact"
		row["has_entity"] = false
		row["fixed"] = false
		row["icon"] = "contact"
		row["size_km"] = 0.0
		row["display_kind"] = "接触"
		row["entity_tags"] = []
	return row

func vm_selected() -> Dictionary:
	if selected_id == "":
		return {}
	var tr := selected_track()
	if tr != null:
		var e: V2Entity = by_id.get(tr.entity_id) if tr.entity_id != "" else null
		return _contact_row(tr, e)
	var e2: V2Entity = selected_entity()
	if e2 != null:
		return {"track_id": "", "entity_id": e2.id, "batch": e2.display_batch(),
			"name": e2.name, "class": e2.cls, "side": e2.side, "level": e2.track_level,
			"identity": e2.identity, "threat": e2.threat, "has_entity": true,
			"selected": true, "capabilities": e2.capabilities.duplicate()}
	return {}

func vm_entity(id: String) -> Dictionary:
	var e: V2Entity = by_id.get(id)
	if e == null:
		return {}
	var d: Dictionary = e.to_dict()
	var tr: V2Track = tracks.find_by_entity(e.id) if tracks != null else null
	d["track"] = tr.to_dict() if tr != null else {}
	return d

## 目标可用动作（右栏/右键菜单直接用）。舰队内其它平台能执行的动作也会标为可用，
## 并给出 actor_id/actor_name（UI 可显示“由远地点号执行”）。
func vm_actions(target_id: String) -> Array:
	var actor := own()
	var target: V2Entity = by_id.get(target_id)
	var tr := track_for(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var out := V2Actions.available(actor, target, tr, ctx)
	if actor == null:
		return out
	for i in range(out.size()):
		var a: Dictionary = out[i]
		if bool(a.get("available", false)):
			a["actor_id"] = actor.id
			a["actor_name"] = actor.display_name()
			continue
		if not bool(a.get("supported", true)):
			continue
		var alt := _find_fleet_actor(String(a.get("id", "")), target, tr, ctx)
		if alt.is_empty():
			continue
		var ev: Dictionary = (alt.get("eval", {}) as Dictionary).duplicate(true)
		var alt_actor: V2Entity = alt.get("actor", null)
		ev["actor_id"] = alt_actor.id if alt_actor != null else ""
		ev["actor_name"] = alt_actor.display_name() if alt_actor != null else ""
		ev["by_fleet"] = true
		out[i] = ev
	return out

func vm_orders() -> Array:
	return orders.snapshot() if orders != null else []

func vm_orders_summary() -> Dictionary:
	return orders.summary() if orders != null else {}

func vm_evidence() -> Array:
	var out: Array = []
	for k in evidence.keys():
		var d: Dictionary = (evidence[k] as Dictionary).duplicate(true)
		d.erase("def")
		var state := String(d.get("state", ""))
		d["remaining_s"] = evidence_remaining(String(k))
		var dur := float(d.get("duration_s", 0.0))
		if state == "in_progress" and dur > 0.0:
			d["progress"] = clampf(1.0 - evidence_remaining(String(k)) / dur, 0.0, 1.0)
		elif state == "done":
			d["progress"] = 1.0
		else:
			d["progress"] = 0.0
		d["color"] = "amber" if state == "in_progress" else ("ph" if state == "done" else "dim")
		out.append(d)
	return out

func vm_layers() -> Dictionary:
	return layers.duplicate(true)

func vm_tracks() -> Array:
	return tracks.summary() if tracks != null else []

## 完整只读快照（调试/存档/探针）。
func vm_snapshot() -> Dictionary:
	return {
		"state": vm_state(),
		"contacts": vm_contacts(),
		"orders": vm_orders(),
		"evidence": vm_evidence(),
		"tracks": vm_tracks(),
		"flow": vm_flow(),
		"recent_events": recent_events(16),
		"recent_radio": recent_radio(8),
	}

# ═══════════════════════════════════════════════════════════════════
# TEXT-ENGINE-1：行动触发文本
#   story.events / story.radio_lines 只作为文本池（按索引引用），不再按 t 自动播报。
#   mission.story_triggers 决定“哪个玩家动作 → 哪条文本”；世界只负责把命中条目
#   写入 events/radio，并把顺序保留在 mission.trigger_log。
#   仅 on=="environment" 的触发器可随 advance(t) 触发（不占用玩家动作顺序）。
# ═══════════════════════════════════════════════════════════════════

func _tick_story_environment() -> Array:
	if mission == null or not mission.has_method("tick_environment"):
		return []
	return _push_story_items(mission.tick_environment(t))

## 玩家动作成功后的统一通知入口（失败动作不要调用）。
func _note_story_event(kind: String, action: String, target := "", extra: Dictionary = {}) -> Array:
	if mission == null or not mission.has_method("note_player_event"):
		return []
	var fired: Array = mission.note_player_event(kind, action, target, extra)
	return _push_story_items(fired)

func _push_story_items(items: Array) -> Array:
	var out: Array = []
	for raw in items:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		var channel := String(item.get("channel", "event"))
		if channel == "radio":
			var line: Dictionary = (item.get("radio", {}) as Dictionary).duplicate(true)
			if not line.has("t"):
				line["t"] = t
			push_radio(line)
		else:
			var ev: Dictionary = (item.get("event", {}) as Dictionary).duplicate(true)
			var typ := String(ev.get("type", "event"))
			push_log("story:" + typ, String(ev.get("text", "")))
		out.append(item.duplicate(true))
	if not out.is_empty():
		state_changed.emit("story_trigger")
	return out

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：V2Mission 联动
#   - attach_mission：绑定后阶段条件可读 world；flow flag 自动同步给 mission。
#   - advance 内自动推进一格（mission_auto，可由 UI 关闭）；advance_mission 供显式推进。
# ═══════════════════════════════════════════════════════════════════

func attach_mission(m) -> void:
	mission = m
	if mission == null:
		return
	mission.attach_world(self)
	if scenario != null:
		mission.attach_scenario(scenario)
	_sync_mission_flags()
	phase_context = String(mission.kind)
	state_changed.emit("mission")
	flow_changed.emit("mission_attach")

func _set_flag(name: String, value := true) -> void:
	flow_flags[name] = value
	if name == "civilians_evacuated":
		civilians_evacuated = bool(value)
	if mission != null:
		mission.set_flag(name, value)

func _sync_mission_flags() -> void:
	if mission == null:
		return
	for k in flow_flags.keys():
		mission.set_flag(String(k), bool(flow_flags[k]))

func _advance_mission_once() -> Dictionary:
	if mission == null:
		return {"ok": false, "reason": "未绑定 mission"}
	var r = mission.advance(t)
	if not (r is Dictionary):
		return {"ok": false, "reason": "任务推进返回异常"}
	var rd: Dictionary = r
	if bool(rd.get("ok", false)):
		phase_context = String(mission.kind)
		state_changed.emit("phase")
		flow_changed.emit("phase")
		push_log("phase", "任务阶段 → %s（%s）" % [String(mission.phase), String(mission.kind)])
	return rd

## 连续推进最多 steps 格（遇到条件不满足即停止）。返回每步结果。
func advance_mission(steps := 1) -> Array:
	var out: Array = []
	for i in range(maxi(1, int(steps))):
		var r := _advance_mission_once()
		out.append(r)
		if not bool(r.get("ok", false)):
			break
	return out

func mission_snapshot() -> Dictionary:
	if mission == null:
		return {}
	return mission.snapshot(t)

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：前置航行（PRELUDE）
#   数据来自 story.prelude（routes/windows/confirm/execute/done_comm）；
#   执行前世界时间冻结；执行/跳过后置 prelude_executed，时间开始流动。
# ═══════════════════════════════════════════════════════════════════

func prelude_open() -> bool:
	return bool(prelude.get("open", false)) and not bool(prelude.get("executed", false))

func prelude_state() -> Dictionary:
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	var route := String(prelude.get("route", ""))
	var window := String(prelude.get("window", ""))
	return {
		"open": bool(prelude.get("open", false)), "executed": bool(prelude.get("executed", false)),
		"step": int(prelude.get("step", 0)), "route": route, "window": window,
		"confirmed": bool(prelude.get("confirmed", false)),
		"dv_spent_ms": float(prelude.get("dv_spent_ms", 0.0)),
		"title": String(prelude.get("title", "")), "body": String(prelude.get("body", "")),
		"routes": (prelude.get("routes", []) as Array).duplicate(true),
		"windows": (prelude.get("windows", []) as Array).duplicate(true),
		"route_def": _find_def(prelude.get("routes", []), route),
		"window_def": _find_def(prelude.get("windows", []), window),
		"confirm_text": String(data.get("confirm_text", "")),
		"execute_text": String(data.get("execute_text", "")),
		"can_execute": int(prelude.get("step", 0)) >= 2,
		"time_frozen": _time_frozen(),
	}

func prelude_choose_route(id: String) -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	var def := _find_def(prelude.get("routes", []), id)
	if def.is_empty():
		return {"ok": false, "reason": "未知目的地: " + id}
	if not bool(def.get("ok", false)):
		return {"ok": false, "reason": String(def.get("hint", "该目的地不适用")), "route_def": def}
	prelude["route"] = id
	prelude["window"] = ""
	prelude["confirmed"] = false
	prelude["step"] = 1
	push_log("prelude", "前置航行：目的地 %s（Δv %.0f m/s）" % [String(def.get("label", id)), float(def.get("dv_ms", 0.0))])
	flow_changed.emit("prelude_route")
	_note_story_event("prelude", "route", id)
	return {"ok": true, "step": 1, "route_def": def}

func prelude_choose_window(id: String) -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if String(prelude.get("route", "")) == "":
		return {"ok": false, "reason": "先选择目的地"}
	var def := _find_def(prelude.get("windows", []), id)
	if def.is_empty():
		return {"ok": false, "reason": "未知变轨窗口: " + id}
	if not bool(def.get("ok", false)):
		return {"ok": false, "reason": String(def.get("hint", "该窗口不适用")), "window_def": def}
	prelude["window"] = id
	prelude["confirmed"] = false
	prelude["step"] = 2
	push_log("prelude", "前置航行：变轨窗口 %s（Δv %.0f m/s）" % [String(def.get("label", id)), float(def.get("dv_ms", 0.0))])
	flow_changed.emit("prelude_window")
	_note_story_event("prelude", "window", id)
	return {"ok": true, "step": 2, "window_def": def}

func prelude_confirm() -> Dictionary:
	if int(prelude.get("step", 0)) < 2:
		return {"ok": false, "reason": "先选择目的地与变轨窗口"}
	prelude["confirmed"] = true
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	flow_changed.emit("prelude_confirm")
	_note_story_event("prelude", "confirm")
	return {"ok": true, "confirmed": true, "confirm_text": String(data.get("confirm_text", ""))}

func prelude_execute() -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	if String(prelude.get("route", "")) == "" or String(prelude.get("window", "")) == "":
		return {"ok": false, "reason": "未选择目的地与变轨窗口"}
	var route_def := _find_def(prelude.get("routes", []), String(prelude.get("route", "")))
	var window_def := _find_def(prelude.get("windows", []), String(prelude.get("window", "")))
	var dv := float(route_def.get("dv_ms", 0.0)) + float(window_def.get("dv_ms", 0.0))
	prelude["executed"] = true
	prelude["open"] = false
	prelude["step"] = 3
	prelude["confirmed"] = true
	prelude["dv_spent_ms"] = dv
	_set_flag("prelude_executed")
	var data: Dictionary = (prelude.get("data", {}) as Dictionary)
	for raw in (data.get("done_comm", []) as Array):
		if raw is Dictionary:
			var line: Dictionary = (raw as Dictionary).duplicate(true)
			line["t"] = t
			push_radio(line)
	push_log("prelude", "前置航行执行：点火完成，Δv %.0f m/s（时间开始流动）" % dv)
	flow_changed.emit("prelude_executed")
	state_changed.emit("prelude")
	_note_story_event("prelude", "execute", String(prelude.get("route", "")))
	return {"ok": true, "dv_spent_ms": dv, "execute_text": String(data.get("execute_text", "")),
		"radio_count": (data.get("done_comm", []) as Array).size(), "flags": flow_flags.duplicate(true)}

## 跳过前置航行（默认取第一个可用目的地/窗口，等价于执行）。
func prelude_skip() -> Dictionary:
	if bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行已执行"}
	if not bool(prelude.get("open", false)):
		return {"ok": false, "reason": "无前置航行阶段"}
	var route_def := _first_ok(prelude.get("routes", []))
	var window_def := _first_ok(prelude.get("windows", []))
	if route_def.is_empty() or window_def.is_empty():
		return {"ok": false, "reason": "场景未提供可用的目的地/窗口"}
	prelude["route"] = String(route_def.get("id", ""))
	prelude["window"] = String(window_def.get("id", ""))
	var r := prelude_execute()
	r["skipped"] = true
	return r

func _find_def(list_raw, id: String) -> Dictionary:
	for raw in (list_raw as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
			return (raw as Dictionary).duplicate(true)
	return {}

func _first_ok(list_raw) -> Dictionary:
	for raw in (list_raw as Array):
		if raw is Dictionary and bool((raw as Dictionary).get("ok", false)):
			return (raw as Dictionary).duplicate(true)
	return {}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：决策 / 报告 / 结束 / 重开
#   结局与文本全部来自 story（endings/decision_replies/report_*/consequence_fire）。
# ═══════════════════════════════════════════════════════════════════

func open_decision() -> Dictionary:
	if bool(flow.get("decision_open", false)):
		return {"ok": false, "reason": "决策已打开"}
	if not (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "已作出决策"}
	if bool(prelude.get("open", false)) and not bool(prelude.get("executed", false)):
		return {"ok": false, "reason": "前置航行未完成"}
	# 教学门控（V2-CORE-3）：识别不足时拒绝打开；挂起 pending，完成关键识别后自动打开。
	if not tutorial_ready():
		flow["decision_pending"] = true
		var tut := vm_tutorial()
		var reason := "教学门控：识别不足（%d/%d）— %s" % [
			int((tut.get("progress", {}) as Dictionary).get("done", 0)),
			int((tut.get("progress", {}) as Dictionary).get("need", 0)),
			String(tut.get("hint", ""))]
		push_log("tutorial", reason)
		flow_changed.emit("tutorial_gate")
		return {"ok": false, "reason": reason, "gated": true, "tutorial": tut,
			"evidence_count": evidence_count(), "can_expose": can_expose()}
	flow["decision_open"] = true
	flow["decision_pending"] = false
	flow["decision_t"] = t
	_set_flag("decision_open")
	push_log("decision", "决策打开：执行窗口剩余 %.0f s，证据 %d/%d" % [
		exec_left(), evidence_count(), evidence.size()])
	flow_changed.emit("decision_open")
	state_changed.emit("decision")
	_note_story_event("decision", "open")
	return {"ok": true, "prompt": scenario.decision_prompt() if scenario != null else "",
		"evidence_count": evidence_count(), "can_expose": can_expose(),
		"exec_window_s": exec_window_s, "exec_left": exec_left(),
		"time_frozen": _time_frozen()}

## 教学门控满足后，若决策曾被挂起则自动打开。
func _try_open_pending_decision() -> void:
	if not bool(flow.get("decision_pending", false)):
		return
	if bool(flow.get("decision_open", false)) or not (flow.get("decision", {}) as Dictionary).is_empty():
		return
	if not tutorial_ready():
		return
	flow["decision_pending"] = false
	open_decision()

## 决策选项（UI 覆盖层用）：来自 story.endings + story.fire_option/FIRE 灾难分支。
func vm_decision() -> Dictionary:
	var options: Array = []
	if scenario != null:
		for raw in scenario.endings:
			if not (raw is Dictionary):
				continue
			var e: Dictionary = (raw as Dictionary).duplicate(true)
			var enabled := true
			var reason := ""
			if String(e.get("kind", "")) == "EXPOSE" and not can_expose():
				enabled = false
				reason = "证据不足（%d/%d 件）" % [evidence_count(), int(evidence_policy.get("min_for_expose", 2))]
			e["enabled"] = enabled
			e["reason"] = reason
			options.append(e)
		var fire_raw = scenario.story.get("fire_option", null)
		var fire: Dictionary = {}
		if fire_raw is Dictionary:
			fire = (fire_raw as Dictionary).duplicate(true)
		else:
			fire = {"kind": "FIRE", "label": "武器释放 / FIRE",
				"hint": "授权武器释放：灾难分支，将造成储罐区二次火灾与平民伤亡。"}
		fire["enabled"] = true
		fire["reason"] = ""
		options.append(fire)
	return {
		"open": bool(flow.get("decision_open", false)),
		"prompt": scenario.decision_prompt() if scenario != null else "",
		"options": options,
		"evidence_count": evidence_count(),
		"can_expose": can_expose(),
		"decision": (flow.get("decision", {}) as Dictionary).duplicate(true),
		"reply": (((flow.get("decision", {}) as Dictionary).get("reply", {}) as Dictionary)).duplicate(true),
		"consequence": String(flow.get("consequence", "")),
		"fire_release": bool(flow.get("fire_release", false)),
	}

func choose_ending(kind: String) -> Dictionary:
	var k := kind.strip_edges().to_upper()
	if not bool(flow.get("decision_open", false)):
		return {"ok": false, "reason": "决策未打开（先 open_decision）", "kind": k}
	if not (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "已作出决策", "kind": k}
	var ending: Dictionary = {}
	if k == "FIRE":
		ending = {"kind": "FIRE", "code": "F", "label": "武器释放 / FIRE"}
		if scenario != null:
			var fire_raw = scenario.story.get("fire_option", null)
			if fire_raw is Dictionary:
				var fr: Dictionary = fire_raw
				ending["label"] = String(fr.get("label", ending["label"]))
				ending["hint"] = String(fr.get("hint", ""))
				if fr.get("reputation") is Dictionary:
					ending["reputation"] = (fr.get("reputation") as Dictionary).duplicate(true)
	else:
		if scenario == null:
			return {"ok": false, "reason": "无场景数据", "kind": k}
		ending = scenario.ending_by_kind(k)
		if ending.is_empty():
			return {"ok": false, "reason": "未知结局: " + k, "kind": k}
	if k == "EXPOSE" and not can_expose():
		return {"ok": false, "reason": "证据不足（%d/%d 件），无法曝光" % [
			evidence_count(), int(evidence_policy.get("min_for_expose", 2))],
			"kind": k, "evidence_count": evidence_count()}
	var reply: Dictionary = {}
	if scenario != null:
		reply = (scenario.decision_replies().get(k, {}) as Dictionary).duplicate(true)
	# 声望（V2-CORE-3）：结局差量来自 story；缺数据时保持基线并标 settled=false。
	var rep_delta = ending.get("reputation", null)
	var rep_settled := rep_delta is Dictionary
	if rep_delta is Dictionary:
		_apply_reputation(rep_delta)
	exec_frozen_left = exec_left()
	flow["decision"] = {
		"kind": k, "code": String(ending.get("code", "")), "label": String(ending.get("label", k)),
		"hint": String(ending.get("hint", "")), "chosen_t": t, "ending": ending.duplicate(true),
		"reply": reply.duplicate(true), "reputation": reputation.duplicate(true),
		"reputation_settled": rep_settled, "exec_left": exec_frozen_left,
	}
	flow["ending"] = ending.duplicate(true)
	flow["decision_open"] = false
	flow["reputation_settled"] = rep_settled
	flow["reputation"] = reputation.duplicate(true)
	_set_flag("decision_made")
	if k == "FIRE":
		flow["fire_release"] = true
		flow["consequence"] = scenario.consequence_text() if scenario != null else ""
		_set_flag("fire_release")
	if not reply.is_empty():
		var line: Dictionary = reply.duplicate(true)
		line["t"] = t
		push_radio(line)
	push_log("decision", "指挥官决策：%s%s · 执行窗口冻结 %.0f s" % [
		k, "（武器释放/灾难分支）" if k == "FIRE" else "", exec_frozen_left])
	_replay_capture(true)
	flow_changed.emit("decision")
	state_changed.emit("decision")
	_note_story_event("decision", "choose", k)
	return {"ok": true, "kind": k, "ending": ending, "reply": reply,
		"fire_release": bool(flow.get("fire_release", false)), "consequence": String(flow.get("consequence", "")),
		"reputation": reputation.duplicate(true), "reputation_settled": rep_settled,
		"exec_left": exec_frozen_left}

## 应用结局声望差量（-100..100）。
func _apply_reputation(delta: Dictionary) -> void:
	for k in delta.keys():
		var key := String(k)
		var cur := int(reputation.get(key, 0))
		reputation[key] = clampi(cur + int(delta[k]), -100, 100)

func report_state() -> Dictionary:
	var dec: Dictionary = (flow.get("decision", {}) as Dictionary)
	var kind := String(dec.get("kind", ""))
	var report: Dictionary = (flow.get("report", {}) as Dictionary)
	var fakes: Dictionary = scenario.report_fake() if scenario != null else {}
	return {
		"available": (not kind.is_empty()) and report.is_empty(),
		"submitted": not report.is_empty(),
		"ending_kind": kind,
		"prompt": String(scenario.story.get("report_event", "")) if scenario != null else "",
		"options": [
			{"mode": "truth", "label": "如实提交 / TRUTH", "hint": "按实际决策与证据提交内部事后报告。"},
			{"mode": "fake", "label": "伪造记录 / FALSIFY", "hint": "修改报告正文；被发现将留下 AUDIT FLAG。"},
		],
		"audit_flag": bool(report.get("audit_flag", false)),
		"report": report.duplicate(true),
		"fake_available": fakes.has(kind),
		"recommend": String((scenario.report_recommend() as Dictionary).get(kind, "")) if scenario != null else "",
	}

## 提交内部事后报告。truth=false 时置 audit flag（伪造记录）。
func submit_report(truth := true) -> Dictionary:
	if (flow.get("decision", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "尚未作出决策"}
	if not (flow.get("report", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "报告已提交"}
	var kind := String((flow.get("decision", {}) as Dictionary).get("kind", ""))
	var bodies: Dictionary = scenario.report_bodies() if scenario != null else {}
	var fakes: Dictionary = scenario.report_fake() if scenario != null else {}
	var recs: Dictionary = scenario.report_recommend() if scenario != null else {}
	var body := String(bodies.get(kind, ""))
	var fake_text := String(fakes.get(kind, ""))
	var text := body if truth else (fake_text if fake_text != "" else body)
	var audit := not truth
	var report := {
		"mode": "truth" if truth else "fake", "truth": truth,
		"submitted_t": t, "text": text, "body": body, "fake_text": fake_text,
		"unit": String(scenario.story.get("report_unit", "")) if scenario != null else "",
		"event": String(scenario.story.get("report_event", "")) if scenario != null else "",
		"evidence": String(scenario.story.get("report_evidence", "")) if scenario != null else "",
		"recommend": String(recs.get(kind, "")),
		"audit_flag": audit, "ending_kind": kind,
	}
	flow["report"] = report
	flow["report_open"] = true
	flow["report_available"] = false
	flow["ended"] = true
	if audit:
		audit_count += 1
		_set_flag("audit_flag")
	_set_flag("report_submitted")
	advance_mission(3)
	push_log("report", "内部事后报告提交（%s）%s" % [
		"如实" if truth else "伪造", " · AUDIT FLAG" if audit else ""])
	_replay_capture(true)
	flow_changed.emit("report")
	state_changed.emit("report")
	_note_story_event("report", "submit", kind)
	return {"ok": true, "report": report.duplicate(true), "audit_flag": audit,
		"mission_phase": String(mission.phase) if mission != null else "", "ended": true}

func end_summary() -> Dictionary:
	var dec: Dictionary = (flow.get("decision", {}) as Dictionary)
	var kind := String(dec.get("kind", ""))
	var report: Dictionary = (flow.get("report", {}) as Dictionary).duplicate(true)
	var rep_settled := bool(flow.get("reputation_settled", false))
	var rep: Dictionary = (flow.get("reputation", {}) as Dictionary).duplicate(true)
	if rep.is_empty():
		rep = reputation.duplicate(true)
	var data := {
		"ok": not report.is_empty(),
		"t": t,
		"ending_kind": kind,
		"ending_code": String(dec.get("code", "")),
		"ending_label": String(dec.get("label", "")),
		"decision": dec.duplicate(true),
		"report": report,
		"audit_flag": bool(report.get("audit_flag", false)),
		"audit_count": audit_count,
		"evidence_count": evidence_count(),
		"evidence_total": evidence.size(),
		"can_expose": can_expose(),
		"civilians_evacuated": civilians_evacuated,
		"fire_release": bool(flow.get("fire_release", false)),
		"consequence": String(flow.get("consequence", "")),
		"reputation": rep,
		"reputation_settled": rep_settled,
		"reputation_base": scenario.reputation_base() if scenario != null else {},
		"exec_window_s": exec_window_s,
		"exec_left": exec_frozen_left if exec_frozen_left >= 0.0 else exec_left(),
		"recommend": String(report.get("recommend", "")),
		"flags": flow_flags.duplicate(true),
		"mission_phase": String(mission.phase) if mission != null else "",
		"mission_kind": String(mission.kind) if mission != null else "",
		"damage": vm_damage(),
		"tutorial": vm_tutorial(),
	}
	if civilians_evacuated and scenario != null:
		var dock = scenario.story.get("av4412_dock", null)
		if dock is Dictionary:
			data["dock_line"] = String((dock as Dictionary).get("report_line", ""))
	if scenario != null:
		data["report_fake_available"] = (scenario.report_fake() as Dictionary).has(kind)
	return data

## 重开：从场景原始数据重新装载（含实体/航迹/证据/时间/流程/mission flags）。
func restart() -> Dictionary:
	if scenario == null:
		return {"ok": false, "reason": "无场景"}
	var m = mission
	var s2 := scenario.clone()
	if s2 == null or not s2.errors.is_empty():
		return {"ok": false, "reason": "场景重载失败", "errors": s2.errors}
	var ok := load_scenario(s2)
	if m != null:
		attach_mission(m)
		m.reset()
		if m.has_method("reset_story_triggers"):
			m.reset_story_triggers()
		_sync_mission_flags()
		phase_context = String(m.kind)
	push_log("flow", "任务重开：时间/航迹/证据/流程已复位")
	state_changed.emit("restart")
	flow_changed.emit("restart")
	return {"ok": ok, "errors": errors.duplicate(), "warnings": warnings.duplicate(),
		"phase": String(m.phase) if m != null else "", "prelude_open": bool(prelude.get("open", false)),
		"t": t, "evidence_count": evidence_count()}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：perform_action —— 7 个支持动作 → 观测/状态（不伪造 L4）
#   动作可用性仍由 content/actions.json + V2Actions 决定；本方法只在可用时执行，
#   用动作 effect 的支撑级 + 目标真实轨道几何 + 平台传感器参数生成观测。
#   武器类（supported=false）一律返回 unsupported，不产生任何状态。
# ═══════════════════════════════════════════════════════════════════

func perform_action(action_id: String, target_id: String, params: Dictionary = {}) -> Dictionary:
	var tr := track_for(target_id)
	var target: V2Entity = by_id.get(target_id)
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	var level_before := int(tr.level) if tr != null else (int(target.track_level) if target != null else 0)
	if bool(flow.get("ended", false)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "任务已结束"}
	if prelude_open():
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "前置航行未完成（时间冻结）"}
	var actor := own()
	if actor == null:
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "无己方实体（actor 为空）"}
	if tr == null and target == null:
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "目标不存在: " + target_id}
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	var eval := V2Actions.available_one(action_id, actor, target, tr, ctx)
	if eval.is_empty():
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": "未知动作: " + action_id}
	if not bool(eval.get("supported", true)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": String(eval.get("reason", "未实现")), "reason_code": "unsupported", "supported": false}
	if not bool(eval.get("available", false)):
		# 本舰能力不足时，按舰队传感器能力找能执行该动作的友军平台（如 IFF 由远地点执行）。
		var alt := _find_fleet_actor(action_id, target, tr, ctx)
		if not alt.is_empty():
			actor = alt.get("actor", actor)
			eval = alt.get("eval", eval)
	if not bool(eval.get("available", false)):
		return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
			"reason": String(eval.get("reason", "不可用")),
			"reason_code": String(eval.get("reason_code", "")), "action_def": eval}
	var result: Dictionary = {}
	match action_id:
		"crossfix":
			result = _act_crossfix(actor, target, tr)
		"radar_illum":
			result = _act_radar(actor, target, tr)
		"radar_track":
			result = _act_radar(actor, target, tr)
		"model_ident":
			result = _act_optical(actor, target, tr)
		"optical_channel":
			result = _act_optical(actor, target, tr)
		"iff_query":
			result = _act_iff(actor, target, tr)
		"ir_channel":
			result = _act_ir(actor, target, tr)
		_:
			return {"ok": false, "action": action_id, "target_id": target_id, "level": level_before,
				"reason": "动作未实现: " + action_id, "reason_code": "unsupported"}
	if not bool(result.get("ok", false)):
		return {"ok": false, "action": action_id, "target_id": target_id,
			"level": int(tr.level) if tr != null else level_before,
			"reason": String(result.get("reason", "不可用")),
			"reason_code": String(result.get("reason_code", "")), "detail": String(result.get("detail", ""))}
	var obs: Dictionary = (result.get("observation", {}) as Dictionary)
	var tr2: V2Track = null
	if not obs.is_empty():
		tr2 = ingest(obs)
	var tr3: V2Track = tr2 if tr2 != null else tr
	var level_after := int(tr3.level) if tr3 != null else level_before
	var order := _record_action_done(action_id, target_id, tr3, actor)
	# 教学门控记录（成功的识别动作才计入；不自动完成任何识别）
	_record_tutorial_action(action_id)
	push_log("action", "动作：%s → %s · L%d %s · %s（执行：%s）" % [
		String(eval.get("label", action_id)), target_id, level_after,
		tr3.level_name() if tr3 != null else "", String(result.get("detail", "")),
		actor.display_name()])
	_replay_capture(true)
	flow_changed.emit("action")
	state_changed.emit("action")
	_note_story_event("action", action_id, target_id)
	return {
		"ok": true, "action": action_id, "action_label": String(eval.get("label", action_id)),
		"target_id": target_id, "level": level_after,
		"actor_id": actor.id, "actor_name": actor.display_name(),
		"tutorial": vm_tutorial(),
		"level_name": tr3.level_name() if tr3 != null else "",
		"identity": tr3.identity_kind if tr3 != null else "",
		"identity_label": tr3.identity_label() if tr3 != null else "",
		"reason": "", "detail": String(result.get("detail", "")),
		"order_id": order.id if order != null else "",
		"observation_count": tr3.observation_count if tr3 != null else 0,
		"sensor": String(obs.get("sensor", "")),
		"support": int(obs.get("support", 0)),
	}

## 立即动作的命令审计记录（DONE）：让命令队列/日志能追溯玩家做过的识别动作。
func _record_action_done(action_id: String, target_id: String, tr: V2Track,
		actor: V2Entity = null) -> V2Orders.Order:
	if orders == null:
		return null
	var actor_id := own_id
	if actor != null:
		actor_id = actor.id
	var o := orders.issue(action_id, target_id,
		{"immediate": true, "duration_s": 0.0, "tx_delay_s": 0.0, "exec_delay_s": 0.0},
		actor_id, tr.id if tr != null else "", t)
	orders.authorize(o.id, t)
	orders.enqueue(o.id, t)
	orders.transmit(o.id, t)
	orders.begin_exec(o.id, t)
	orders.complete(o.id, t, "即时动作完成")
	return o

# —— 动作实现（观测生成）────────────────────────────────────────

func _act_crossfix(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["ir", "optical", "elint"])
	var rb := _range_bearing(actor, tr, target)
	var obs := _obs_base(actor, tr, target, "crossfix", sensor)
	var notes: Array = ["交叉定位：双平台方位线"]
	if rb.has("range_km") and rb.has("bearing_deg"):
		obs["support"] = 2
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
		obs["bearing_sigma_deg"] = maxf(0.05, float(sensor.get("sigma_bearing_deg", 0.5)))
		obs["range_km"] = float(rb.get("range_km", 0.0))
		obs["range_sigma_km"] = maxf(0.5, float(rb.get("range_km", 0.0)) * 0.03)
		obs["quality"] = 0.75
		notes.append("方位交叉 → L2 定位（σr≈3% R）")
		obs["notes"] = notes
		return {"ok": true, "observation": obs, "detail": "交叉定位 → L2"}
	obs["support"] = 1
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["quality"] = 0.5
	notes.append("无第二方位线：仅刷新方位（不伪造 L2）")
	obs["notes"] = notes
	return {"ok": true, "observation": obs, "detail": "仅方位（无实体/无第二线）"}

func _act_radar(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["radar"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少雷达传感器", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无目标距离/几何数据，雷达无法解算", "reason_code": "no_range"}
	var eff := float(sensor.get("range_km", 30000.0))
	var pd := SensorModel.detection_pd(range_km, eff, 4.0)
	if pd < 0.5:
		return {"ok": false, "reason": "超出雷达探测距离（%.0f km > 有效 %.0f km，Pd=%.2f）" % [range_km, eff, pd],
			"reason_code": "range"}
	var stable := range_km <= float(sensor.get("track_range_km", eff * 0.5))
	var obs := _obs_base(actor, tr, target, "radar", sensor)
	obs["support"] = 2
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	elif tr != null and tr.bearing_deg >= 0.0:
		obs["bearing_deg"] = tr.bearing_deg
	obs["bearing_sigma_deg"] = maxf(0.01, float(sensor.get("sigma_bearing_deg", 0.15)))
	var sigr := maxf(float(sensor.get("sigma_range_floor_km", 0.5)),
		range_km * float(sensor.get("sigma_range_frac", 0.0025)))
	if not stable:
		sigr *= 3.0
	obs["range_km"] = range_km
	obs["range_sigma_km"] = sigr
	obs["quality"] = clampf(pd * (1.0 if stable else 0.4), 0.0, 1.0)
	obs["notes"] = ["雷达照射：" + ("稳定跟踪" if stable else "探测（超出稳定跟踪距离）"),
		"开机即暴露（ELINT 可截获）"]
	return {"ok": true, "observation": obs,
		"detail": "雷达 %s → L2（%.0f km，σr=%.1f km）" % [
			"稳定跟踪" if stable else "探测", range_km, sigr]}

func _act_optical(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_optical(actor)
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少光学传感器（非激光测距）", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无距离数据（需先 L2 定位）", "reason_code": "no_range"}
	var max_km := float(sensor.get("range_km", 15000.0))
	if range_km > max_km:
		return {"ok": false, "reason": "超出光学作用距离（%.0f km > %.0f km）" % [range_km, max_km],
			"reason_code": "range"}
	var obs := _obs_base(actor, tr, target, "optical", sensor)
	obs["support"] = 3
	var cls := {"ship_class": target.cls, "role": target.role, "faction": target.faction,
		"confidence": 0.85}
	if target.meta.has("builder"):
		cls["builder"] = String(target.meta.get("builder", ""))
	obs["classification"] = cls
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["quality"] = 0.8
	obs["notes"] = ["光学凝视 + 数据库比对 → L3 分类", "不给距离解（光学仅方位/分类）"]
	return {"ok": true, "observation": obs,
		"detail": "光学分类 → L3（%s）" % String(cls.get("ship_class", ""))}

func _act_iff(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["iff"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少 IFF 询问机能力", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	if range_km < 0.0:
		return {"ok": false, "reason": "无距离数据（需先 L2 定位）", "reason_code": "no_range"}
	var max_km := float(sensor.get("range_km", 2000.0))
	if range_km > max_km:
		return {"ok": false, "reason": "超出 IFF 询问距离（%.0f km > %.0f km）" % [range_km, max_km],
			"reason_code": "range"}
	var obs := _obs_base(actor, tr, target, "iff", sensor)
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	var friendly := target != null and (target.side == "friend" or "own_fleet" in target.tags or "own" in target.tags)
	if friendly:
		obs["support"] = 4
		obs["identity"] = {"kind": "friend", "name": target.name, "hull": target.hull,
			"faction": target.faction, "via": "iff", "confidence": 0.9}
		obs["iff_status"] = "friend"
		obs["quality"] = 0.95
		obs["notes"] = ["IFF 应答正确 → 友军（L4 证据）"]
		return {"ok": true, "observation": obs, "detail": "IFF 应答：友军 → L4 证据"}
	var tp := String(target.meta.get("transponder", "")) if target != null else ""
	var status := "faulty_transponder" if tp == "faulty" else "no_reply"
	obs["support"] = 1
	obs["iff_status"] = status
	obs["quality"] = 0.5
	obs["notes"] = ["IFF 无应答 / 应答机故障 → 身份未知（不明≠敌意，不判敌、不升 L4）"]
	return {"ok": true, "observation": obs, "detail": "IFF 无应答：身份未知（不伪造 L4）"}

func _act_ir(actor: V2Entity, target: V2Entity, tr: V2Track) -> Dictionary:
	var sensor := _actor_sensor(actor, ["ir"])
	if sensor.is_empty():
		return {"ok": false, "reason": "缺少红外传感器", "reason_code": "capability"}
	var rb := _range_bearing(actor, tr, target)
	var obs := _obs_base(actor, tr, target, "ir", sensor)
	obs["support"] = 1
	if rb.has("bearing_deg"):
		obs["bearing_deg"] = float(rb.get("bearing_deg", 0.0))
	obs["bearing_sigma_deg"] = maxf(0.05, float(sensor.get("sigma_bearing_deg", 1.2)))
	var range_km := float(rb.get("range_km", -1.0))
	if range_km < 0.0 and tr != null:
		range_km = float(tr.range_km)
	var band := "UNKNOWN"
	if range_km >= 0.0:
		band = SensorModel.ir_range_band(range_km, float(sensor.get("range_km", 60000.0)),
			sensor.get("band_edges", [0.333, 0.667]))
		obs["range_band"] = band
	obs["quality"] = 0.6
	obs["notes"] = ["被动红外：方位线 + 距离档（%s），无距离解 → L1" % band, "不暴露"]
	return {"ok": true, "observation": obs, "detail": "红外通道（方位/档位 %s）" % band}

# —— 动作辅助 ——

func _obs_base(actor: V2Entity, tr: V2Track, target: V2Entity, kind: String, sensor: Dictionary) -> Dictionary:
	var obs := {
		"detected": true, "kind": kind,
		"sensor": String(sensor.get("model", "")),
		"source": (actor.id if actor != null else own_id), "t": t, "quality": 0.5,
	}
	if tr != null:
		obs["track_id"] = tr.id
		if tr.entity_id != "":
			obs["entity_id"] = tr.entity_id
	if target != null and not obs.has("entity_id"):
		obs["entity_id"] = target.id
	return obs

func _range_bearing(actor: V2Entity, tr: V2Track, target: V2Entity) -> Dictionary:
	var geom := _geometry_between(actor, target)
	if not geom.is_empty():
		return geom
	var out := {}
	if tr != null:
		if tr.range_km >= 0.0:
			out["range_km"] = tr.range_km
		if tr.bearing_deg >= 0.0:
			out["bearing_deg"] = tr.bearing_deg
		if out.has("range_km") and tr.range_sigma_km > 0.0:
			out["range_sigma_km"] = tr.range_sigma_km
	return out

## 目标相对执行平台的真实几何（L1 站心 km；来自场景轨道状态，只做换算，不伪造）。
func _geometry_between(actor: V2Entity, target: V2Entity) -> Dictionary:
	if actor == null or target == null:
		return {}
	var rs: Array = (actor.orbit.get("r", []) as Array)
	var rt: Array = (target.orbit.get("r", []) as Array)
	if rs.size() < 3 or rt.size() < 3:
		return {}
	var rel := Vector3(float(rt[0]) - float(rs[0]), float(rt[1]) - float(rs[1]), float(rt[2]) - float(rs[2]))
	var rng := rel.length()
	if rng <= 0.001:
		return {}
	var horiz := sqrt(rel.x * rel.x + rel.y * rel.y)
	return {
		"range_km": rng,
		"bearing_deg": fposmod(rad_to_deg(atan2(rel.x, rel.y)), 360.0),
		"elevation_deg": rad_to_deg(atan2(rel.z, maxf(0.001, horiz))),
		"range_sigma_km": maxf(0.5, rng * 0.01),
	}

## 按能力类型找平台传感器（型号参数来自保留的 SensorModel 型号库；缺数据时给保守回退）。
func _actor_sensor(actor: V2Entity, types: Array) -> Dictionary:
	if actor == null:
		return {}
	var ship_key := String(actor.meta.get("ship_key", actor.id))
	for raw in (actor.meta.get("sensors", []) as Array):
		var model := String(raw)
		if model == "":
			continue
		var s: Dictionary = SensorModel.rack_sensor(ship_key, model)
		if s.is_empty():
			continue
		var stype := String(s.get("type", ""))
		if stype in types:
			return s
	return {}

func _actor_optical(actor: V2Entity) -> Dictionary:
	if actor == null:
		return {}
	var ship_key := String(actor.meta.get("ship_key", actor.id))
	for raw in (actor.meta.get("sensors", []) as Array):
		var model := String(raw)
		if model == "":
			continue
		var s: Dictionary = SensorModel.rack_sensor(ship_key, model)
		if s.is_empty():
			continue
		if String(s.get("type", "")) == "optical" and String(s.get("subtype", "")) != "lidar":
			return s
	if actor.has("sensor.optical"):
		return {"model": "", "type": "optical", "range_km": 15000.0, "refresh_s": 8.0,
			"sigma_bearing_deg": 0.05}
	return {}

## 舰队内找能执行该动作的友军平台（本舰能力不足时使用，如 IFF 由远地点执行）。
## 返回 {actor, eval}；没有可用平台返回 {}。
func _find_fleet_actor(action_id: String, target: V2Entity, tr: V2Track,
		ctx: Dictionary) -> Dictionary:
	for e in entities:
		if e == null or e.id == own_id:
			continue
		if e.side != "friend":
			continue
		var ev := V2Actions.available_one(action_id, e, target, tr, ctx)
		if bool(ev.get("available", false)):
			return {"actor": e, "eval": ev}
	return {}

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-2：流程 view-model（UI 覆盖层）
# ═══════════════════════════════════════════════════════════════════

func vm_prelude() -> Dictionary:
	return prelude_state()

func vm_report() -> Dictionary:
	return report_state()

func vm_end() -> Dictionary:
	return end_summary()

## 流程总览：UI 根据 prelude.open/decision.open/report.submitted/ended 决定显示哪层。
## V2-CORE-3 追加：tutorial / exec 窗口 / reputation / damage / replay 摘要。
func vm_flow() -> Dictionary:
	return {
		"t": t,
		"time_frozen": _time_frozen(),
		"prelude": prelude_state(),
		"decision": vm_decision(),
		"report": report_state(),
		"end": end_summary(),
		"mission": mission_snapshot(),
		"flags": flow_flags.duplicate(true),
		"civilians_evacuated": civilians_evacuated,
		"audit_count": audit_count,
		"tutorial": vm_tutorial(),
		"tutorial_ready": tutorial_ready(),
		"exec_window_s": exec_window_s,
		"exec_left": exec_left(),
		"exec_pct": exec_pct(),
		"reputation": reputation.duplicate(true),
		"reputation_settled": bool(flow.get("reputation_settled", false)),
		"damage": vm_damage(),
		"replay": {"recording": bool(replay.get("recording", false)),
			"playing": bool(replay.get("playing", false)),
			"paused": bool(replay.get("paused", false)),
			"total": (replay.get("buffer", []) as Array).size()},
	}
# ═══════════════════════════════════════════════════════════════════
# V2-CORE-3：教学门控（story.tutorial 数据驱动）
#   DECISION 前必须完成 required_actions 中至少 min_required 项关键识别；
#   未满足时 open_decision 返回 reason 并挂起 pending，玩家补完后自动打开。
#   不自动完成任何识别动作。
# ═══════════════════════════════════════════════════════════════════

func tutorial_ready() -> bool:
	if not bool(tutorial.get("enabled", false)):
		return true
	var req: Array = tutorial.get("required_actions", [])
	var completed: Dictionary = tutorial.get("completed", {})
	var done := 0
	for raw in req:
		if completed.has(String(raw)):
			done += 1
	return done >= _tutorial_need()

func _tutorial_need() -> int:
	if not bool(tutorial.get("enabled", false)):
		return 0
	var req: Array = tutorial.get("required_actions", [])
	var min_req := int(tutorial.get("min_required", 0))
	if min_req <= 0:
		return req.size()
	return mini(min_req, req.size())

func _tutorial_label(action_id: String) -> String:
	var labels: Dictionary = tutorial.get("labels", {})
	return String(labels.get(action_id, action_id))

func _tutorial_done_count() -> int:
	var req: Array = tutorial.get("required_actions", [])
	var completed: Dictionary = tutorial.get("completed", {})
	var done := 0
	for raw in req:
		if completed.has(String(raw)):
			done += 1
	return done

func _record_tutorial_action(action_id: String) -> void:
	if not bool(tutorial.get("enabled", false)):
		return
	if not (action_id in (tutorial.get("required_actions", []) as Array)):
		return
	var completed: Dictionary = tutorial.get("completed", {})
	if completed.has(action_id):
		return
	completed[action_id] = t
	tutorial["completed"] = completed
	push_log("tutorial", "教学：完成 %s（%d/%d）" % [
		_tutorial_label(action_id), _tutorial_done_count(), _tutorial_need()])
	if tutorial_ready():
		_set_flag("tutorial_ready", true)
		push_log("tutorial", String(tutorial.get("done_text", "识别链完成，决策权限已解锁。")))
	flow_changed.emit("tutorial")
	_try_open_pending_decision()

func vm_tutorial() -> Dictionary:
	var req: Array = tutorial.get("required_actions", [])
	var completed: Dictionary = tutorial.get("completed", {})
	var done_rows: Array = []
	var missing: Array = []
	var done := 0
	for raw in req:
		var aid := String(raw)
		if completed.has(aid):
			done += 1
			done_rows.append({"id": aid, "label": _tutorial_label(aid), "at": float(completed[aid])})
		else:
			missing.append({"id": aid, "label": _tutorial_label(aid)})
	return {
		"enabled": bool(tutorial.get("enabled", false)),
		"ready": tutorial_ready(),
		"title": String(tutorial.get("title", "")),
		"hint": String(tutorial.get("hint", "")),
		"done_text": String(tutorial.get("done_text", "")),
		"required_actions": req.duplicate(),
		"min_required": int(tutorial.get("min_required", 0)),
		"completed": done_rows,
		"missing": missing,
		"progress": {"done": done, "need": _tutorial_need()},
		"decision_pending": bool(flow.get("decision_pending", false)),
		"actions": _tutorial_actions_view(),
	}

## 教学步骤清单（含动作是否可用/原因），UI 可直接渲染。
func _tutorial_actions_view() -> Array:
	var out: Array = []
	var actor := own()
	var target: V2Entity = by_id.get("2001")
	var tr := track_for("2001")
	if target == null and tr != null and tr.entity_id != "":
		target = by_id.get(tr.entity_id)
	var ctx := {"phase": phase_context, "flags": flow_flags.duplicate()}
	for raw in (tutorial.get("required_actions", []) as Array):
		var aid := String(raw)
		var row := {"id": aid, "label": _tutorial_label(aid),
			"done": (tutorial.get("completed", {}) as Dictionary).has(aid),
			"at": float((tutorial.get("completed", {}) as Dictionary).get(aid, -1.0)),
			"available": false, "reason": ""}
		if actor != null and (target != null or tr != null):
			var ev := V2Actions.available_one(aid, actor, target, tr, ctx)
			row["available"] = bool(ev.get("available", false))
			row["reason"] = String(ev.get("reason", ""))
		out.append(row)
	return out

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-3：损管模型
#   damage_sections / damage_queue 挂在实体上（本舰默认 3 项，来自 content damage.initial）；
#   state: degraded / damaged / repairing / repaired；只做状态与进度，不伪造战斗结果。
# ═══════════════════════════════════════════════════════════════════

func _damage_entity() -> V2Entity:
	if own_id != "" and by_id.has(own_id):
		return by_id.get(own_id)
	return null

func _damage_sections() -> Array:
	var e := _damage_entity()
	if e != null:
		return e.damage_sections
	return damage

func _damage_item(id: String) -> Dictionary:
	for raw in _damage_sections():
		if String((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}

## 施加/加重损伤（剧情/调试用）。severity 0–1；已有项取较大值。
func apply_damage(id: String, severity := 0.5, label := "", entity_id := "") -> Dictionary:
	var e := _damage_entity()
	if entity_id != "" and by_id.has(entity_id):
		e = by_id.get(entity_id)
	if e == null:
		return {"ok": false, "reason": "无实体可施加损管"}
	if e.id != own_id:
		# 非本舰实体也维护自己的 damage_sections（不进入 vm_damage）
		pass
	var d := _damage_item_on(e, id)
	if d.is_empty():
		d = {"id": id, "label": (label if label != "" else id), "state": "degraded",
			"severity": 0.0, "repair_eta_s": 0.0, "repair_progress_s": 0.0,
			"started_t": -1.0, "entity_id": e.id}
		e.damage_sections.append(d)
	var sev := clampf(float(severity), 0.0, 1.0)
	d["severity"] = maxf(float(d.get("severity", 0.0)), sev)
	d["state"] = "damaged" if float(d["severity"]) >= 0.5 else "degraded"
	if label != "":
		d["label"] = label
	d["repair_progress_s"] = 0.0
	d["repair_eta_s"] = float(d.get("repair_eta_s", 0.0))
	if float(d["repair_eta_s"]) <= 0.0:
		d["repair_eta_s"] = maxf(15.0, float(d["severity"]) * damage_repair_rate_s)
	e.damage_queue.erase(id)
	if e.id == own_id:
		damage = e.damage_sections
	push_log("damage", "损管：%s 受损（严重度 %.0f%%）" % [
		String(d.get("label", id)), float(d["severity"]) * 100.0])
	_replay_capture(true)
	state_changed.emit("damage")
	flow_changed.emit("damage")
	return {"ok": true, "section": d.duplicate(true)}

func _damage_item_on(e: V2Entity, id: String) -> Dictionary:
	for raw in e.damage_sections:
		if String((raw as Dictionary).get("id", "")) == id:
			return raw
	return {}

## 开始维修（一次一项；进度随 advance_damage 推进）。
func start_repair(id: String) -> Dictionary:
	var d := _damage_item(id)
	if d.is_empty():
		return {"ok": false, "reason": "未知损管项: " + id}
	var state := String(d.get("state", ""))
	if state == "repaired":
		return {"ok": false, "reason": "已修复: " + String(d.get("label", id))}
	if state == "repairing":
		return {"ok": false, "reason": "正在维修: " + String(d.get("label", id))}
	d["state"] = "repairing"
	d["repair_progress_s"] = 0.0
	d["started_t"] = t
	var e := _damage_entity()
	if e != null and not (id in e.damage_queue):
		e.damage_queue.append(id)
	push_log("damage", "损管：开始维修 %s（预计 %.0f s）" % [
		String(d.get("label", id)), float(d.get("repair_eta_s", 0.0))])
	_replay_capture(true)
	state_changed.emit("damage")
	return {"ok": true, "section": d.duplicate(true)}

## 推进维修进度；到点置 repaired。返回本次完成列表。
func advance_damage(dt: float) -> Array:
	var done: Array = []
	if dt <= 0.0:
		return done
	var e := _damage_entity()
	var sections: Array = e.damage_sections if e != null else damage
	for raw in sections:
		var d: Dictionary = raw
		if String(d.get("state", "")) != "repairing":
			continue
		d["repair_progress_s"] = float(d.get("repair_progress_s", 0.0)) + dt
		if float(d["repair_progress_s"]) >= float(d.get("repair_eta_s", 0.0)):
			d["state"] = "repaired"
			d["severity"] = 0.0
			if e != null:
				e.damage_queue.erase(String(d.get("id", "")))
			done.append({"id": String(d.get("id", "")), "label": String(d.get("label", "")),
				"t": t})
			push_log("damage", "损管：完成维修 %s" % String(d.get("label", "")))
	if not done.is_empty():
		state_changed.emit("damage")
		flow_changed.emit("damage")
	return done

func vm_damage_summary() -> Dictionary:
	var damaged := 0
	var degraded := 0
	var repairing := 0
	var repaired := 0
	for raw in _damage_sections():
		var st := String((raw as Dictionary).get("state", ""))
		match st:
			"damaged":
				damaged += 1
			"degraded":
				degraded += 1
			"repairing":
				repairing += 1
			"repaired":
				repaired += 1
	return {"total": _damage_sections().size(), "damaged": damaged, "degraded": degraded,
		"repairing": repairing, "repaired": repaired,
		"needs_attention": damaged + degraded + repairing > 0}

## 损管面板 view-model（旧字段保持兼容；完整损管模型见 model/events/resources/effects）。
func vm_damage() -> Dictionary:
	var e := _damage_entity()
	var rows: Array = []
	for raw in _damage_sections():
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		var eta := float(d.get("repair_eta_s", 0.0))
		var prog := float(d.get("repair_progress_s", 0.0))
		var st := String(d.get("state", ""))
		d["repair_remaining_s"] = maxf(0.0, eta - prog) if st == "repairing" else (0.0 if st == "repaired" else eta)
		d["progress"] = clampf(prog / maxf(0.001, eta), 0.0, 1.0)
		d["severity_pct"] = float(d.get("severity", 0.0)) * 100.0
		d["can_repair"] = st in ["degraded", "damaged"]
		rows.append(d)
	var full := vm_damage_full()
	var vm := {
		"entity_id": e.id if e != null else "",
		"entity_name": e.display_name() if e != null else "",
		"sections": rows,
		"queue": (e.damage_queue.duplicate() if e != null else []),
		"repair_rate_s": damage_repair_rate_s,
		"summary": vm_damage_summary(),
		# —— 兼容旧字段别名（V17 HUD / state.fw_damage 现有调用）——
		"damage_sections": rows.duplicate(true),
		"damage_queue": (e.damage_queue.duplicate() if e != null else []),
		# —— R2-DAMAGE-2：完整损管模型只读 vm（权威数据）——
		"has_full_model": not full.is_empty(),
		"model": full,
		"events": (full.get("events", []) as Array).duplicate(true),
		"resources": (full.get("resources", {}) as Dictionary).duplicate(true),
		"effects": (full.get("effects", {}) as Dictionary).duplicate(true),
		"summary_full": (full.get("summary", {}) as Dictionary).duplicate(true),
		"units": (full.get("units", {}) as Dictionary).duplicate(true),
		"note": "legacy 字段（sections/queue/summary）保持兼容；完整损管模型见 model/events/resources/effects/summary_full（只读，无武器）。",
	}
	return vm

# ═══════════════════════════════════════════════════════════════════
# R2-DAMAGE-2：完整损管模型接入
#   - entity.damage（V2DamageModel）由 damage_l1.json 档案初始化（harmattan/summons）；
#   - world.advance 推进 step(dt)，事件写入 events/damage_events_log（只读）；
#   - vm_damage() 同时返回 legacy 兼容字段 + 完整 model vm；
#   - damage_apply_hit/assign_repair/cancel_repair 只转发，不自动命中/不生成武器。
# ═══════════════════════════════════════════════════════════════════

func _init_damage_models(_s: V2Scenario) -> void:
	damage_content = DamageModelScript.load_content()
	damage_events_log.clear()
	_damage_last_seq.clear()
	if damage_content.is_empty():
		warnings.append("损管模型内容未就绪：framework/content/damage_l1.json（保留 legacy 损管）")
		return
	var ships: Dictionary = damage_content.get("ships", {}) if damage_content.get("ships") is Dictionary else {}
	var initialized := 0
	for raw in entities:
		var e: V2Entity = raw
		if not ships.has(e.id):
			continue
		if e.init_damage(damage_content, e.id):
			initialized += 1
			_damage_last_seq[e.id] = e.damage.events.size()
		else:
			warnings.append("损管模型初始化失败：" + e.id)
	if initialized > 0:
		push_log("damage", "完整损管模型已接入：%d 艘实体（内容 %s）" % [
			initialized, String(damage_content.get("id", ""))])

func _damage_entity_by_id(entity_id := "") -> V2Entity:
	var eid := String(entity_id) if String(entity_id) != "" else own_id
	if eid == "":
		return null
	return by_id.get(eid)

## 完整损管模型实例（懒加载：仅内容有该实体档案时返回，否则 null）。
func damage_model_for(entity_id := ""):
	var e := _damage_entity_by_id(entity_id)
	if e == null:
		return null
	if e.damage == null:
		e.ensure_damage(damage_content, e.id)
	return e.damage

## 完整损管只读 vm（直接取模型权威 view-model；无模型返回空字典）。
func vm_damage_full(entity_id := "") -> Dictionary:
	var m = damage_model_for(entity_id)
	if m == null:
		return {}
	return m.vm_damage()

## 统一损管事件（只读；最近 limit 条，含 entity_id）。
func damage_events(limit := 64) -> Array:
	var n := maxi(0, mini(int(limit), damage_events_log.size()))
	var start := damage_events_log.size() - n
	return damage_events_log.slice(start, damage_events_log.size()).duplicate(true)

func _record_damage_event(entity_id: String, ev: Dictionary) -> Dictionary:
	var rec: Dictionary = ev.duplicate(true)
	rec["entity_id"] = entity_id
	var seq := int(rec.get("seq", 0))
	if seq <= int(_damage_last_seq.get(entity_id, 0)):
		return {}
	_damage_last_seq[entity_id] = seq
	damage_events_log.append(rec)
	while damage_events_log.size() > MAX_DAMAGE_EVENTS:
		damage_events_log.pop_front()
	push_log("damage", "损管事件：%s · %s" % [entity_id, String(rec.get("text", ""))])
	return rec

## 推进所有已初始化的完整损管模型（火灾/失压/断电/维修队列）。返回新事件。
func _advance_damage_models(dt: float) -> Array:
	var out: Array = []
	if dt <= 0.0:
		return out
	for raw in entities:
		var e: V2Entity = raw
		if e.damage == null:
			continue
		e.damage.step(dt)
		for ev in e.damage.events:
			var seq := int((ev as Dictionary).get("seq", 0))
			if seq > int(_damage_last_seq.get(e.id, 0)):
				var rec := _record_damage_event(e.id, ev as Dictionary)
				if not rec.is_empty():
					out.append(rec)
	return out

## 伤害输入转发（剧情/调试/未来武器系统调用；本世界不自动生成命中）。
func damage_apply_hit(section: String, energy: float, penetration := 0.5,
		direction := "fore", source := "script", entity_id := "") -> Dictionary:
	var e := _damage_entity_by_id(entity_id)
	if e == null:
		return {"ok": false, "reason": "无实体可施加伤害"}
	if e.damage == null:
		return {"ok": false, "reason": "实体无完整损管模型（content 无档案）：" + e.id}
	var r: Dictionary = e.damage.apply_hit(section, energy, penetration, direction, source)
	for raw in (r.get("events", []) as Array):
		_record_damage_event(e.id, raw as Dictionary)
	if bool(r.get("ok", false)):
		push_log("damage", "损管命中：%s · %s · energy=%.2f pen=%.2f" % [
			e.id, section, energy, penetration])
		_replay_capture(true)
		state_changed.emit("damage")
		flow_changed.emit("damage")
	return r

## 维修指派转发（priority 1 最高）。
func damage_assign_repair(section: String, priority := 2, entity_id := "") -> Dictionary:
	var e := _damage_entity_by_id(entity_id)
	if e == null or e.damage == null:
		return {"ok": false, "reason": "实体无完整损管模型"}
	var r: Dictionary = e.damage.assign_repair(section, priority)
	if bool(r.get("ok", false)):
		push_log("damage", "损管指派：%s · %s（优先级 %d）" % [e.id, section, int(priority)])
		_replay_capture(true)
		state_changed.emit("damage")
		flow_changed.emit("damage")
	return r

func damage_cancel_repair(section: String, entity_id := "") -> Dictionary:
	var e := _damage_entity_by_id(entity_id)
	if e == null or e.damage == null:
		return {"ok": false, "reason": "实体无完整损管模型"}
	var r: Dictionary = e.damage.cancel_repair(section)
	if bool(r.get("ok", false)):
		push_log("damage", "损管取消：%s · %s" % [e.id, section])
		state_changed.emit("damage")
	return r

func damage_set_priority(section: String, priority: int, entity_id := "") -> Dictionary:
	var e := _damage_entity_by_id(entity_id)
	if e == null or e.damage == null:
		return {"ok": false, "reason": "实体无完整损管模型"}
	return e.damage.set_priority(section, priority)

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-3：回放（只读帧；不推进世界、不伪造）
#   每 interval_s（默认 1s）或关键事件写一帧；帧含 t/own/contacts/events/orders/
#   evidence/flow/damage/exec 摘要。回放期间 UI 不应调用 advance。
# ═══════════════════════════════════════════════════════════════════

func _replay_capture(force := false) -> void:
	if not bool(replay.get("recording", false)):
		return
	var interval := float(replay.get("interval_s", 1.0))
	if not force and _last_replay_t >= 0.0 and t - _last_replay_t < interval - 1.0e-9:
		return
	var buffer: Array = replay.get("buffer", [])
	var frame := _replay_make_frame()
	buffer.append(frame)
	while buffer.size() > 900:
		buffer.pop_front()
	replay["buffer"] = buffer
	replay["index"] = buffer.size() - 1
	_last_replay_t = t

func _replay_make_frame() -> Dictionary:
	var contacts: Array = []
	if tracks != null:
		for raw in tracks.tracks:
			var tr: V2Track = raw
			contacts.append({"track_id": tr.id, "entity_id": tr.entity_id,
				"level": tr.level, "identity": tr.identity_kind,
				"range_km": tr.range_km, "bearing_deg": tr.bearing_deg,
				"stale": tr.stale})
			if contacts.size() >= 16:
				break
	var ord_sum := orders.summary() if orders != null else {}
	var own_e := own()
	return {
		"t": t,
		"own_id": own_id,
		"own": {"id": own_id, "name": own_e.display_name() if own_e != null else "",
			"damage": vm_damage_summary()},
		"contacts": contacts,
		"events_count": events.size(),
		"last_event": (events[events.size() - 1] as Dictionary).duplicate(true) if events.size() > 0 else {},
		"orders": {"total": int(ord_sum.get("total", 0)),
			"counts": (ord_sum.get("counts", {}) as Dictionary).duplicate(true)},
		"evidence": {"done": evidence_count(), "total": evidence.size()},
		"flow": {"phase": String(mission.phase) if mission != null else "",
			"phase_kind": String(mission.kind) if mission != null else "",
			"prelude_executed": bool(prelude.get("executed", false)),
			"decision_open": bool(flow.get("decision_open", false)),
			"decision_made": not (flow.get("decision", {}) as Dictionary).is_empty(),
			"report_submitted": not (flow.get("report", {}) as Dictionary).is_empty(),
			"ended": bool(flow.get("ended", false))},
		"exec_left": exec_left(),
		"damage": vm_damage_summary(),
	}

func replay_start() -> Dictionary:
	replay["recording"] = bool(replay.get("recording", true))
	replay["playing"] = true
	replay["paused"] = false
	replay["index"] = 0
	state_changed.emit("replay")
	return vm_replay()

func replay_pause() -> Dictionary:
	replay["playing"] = false
	replay["paused"] = true
	state_changed.emit("replay")
	return vm_replay()

func replay_stop() -> Dictionary:
	replay["playing"] = false
	replay["paused"] = false
	var buffer: Array = replay.get("buffer", [])
	replay["index"] = maxi(0, buffer.size() - 1)
	state_changed.emit("replay")
	return vm_replay()

## 按时间（秒）定位最近一帧。
func replay_seek(t_s: float) -> Dictionary:
	var buffer: Array = replay.get("buffer", [])
	var best := 0
	for i in range(buffer.size()):
		if float((buffer[i] as Dictionary).get("t", 0.0)) <= t_s + 1.0e-9:
			best = i
		else:
			break
	replay["index"] = clampi(best, 0, maxi(0, buffer.size() - 1))
	replay["playing"] = false
	replay["paused"] = true
	state_changed.emit("replay")
	return vm_replay()

## 按帧下标定位。
func replay_seek_index(index: int) -> Dictionary:
	var buffer: Array = replay.get("buffer", [])
	replay["index"] = clampi(index, 0, maxi(0, buffer.size() - 1))
	replay["playing"] = false
	replay["paused"] = true
	state_changed.emit("replay")
	return vm_replay()

func replay_frame() -> Dictionary:
	var buffer: Array = replay.get("buffer", [])
	if buffer.is_empty():
		return {}
	var idx := clampi(int(replay.get("index", 0)), 0, buffer.size() - 1)
	return (buffer[idx] as Dictionary).duplicate(true)

func replay_clear() -> void:
	replay["buffer"] = []
	replay["index"] = 0
	replay["playing"] = false
	replay["paused"] = false
	_last_replay_t = -1.0
	state_changed.emit("replay")

func vm_replay() -> Dictionary:
	var buffer: Array = replay.get("buffer", [])
	var frames: Array = []
	var start := maxi(0, buffer.size() - 600)
	for i in range(start, buffer.size()):
		var f: Dictionary = buffer[i]
		var fl: Dictionary = (f.get("flow", {}) as Dictionary)
		frames.append({"index": i, "t": float(f.get("t", 0.0)),
			"phase": String(fl.get("phase", "")), "kind": String(fl.get("phase_kind", "")),
			"decision_made": bool(fl.get("decision_made", false)),
			"ended": bool(fl.get("ended", false))})
	return {
		"recording": bool(replay.get("recording", false)),
		"playing": bool(replay.get("playing", false)),
		"paused": bool(replay.get("paused", false)),
		"index": clampi(int(replay.get("index", 0)), 0, maxi(0, buffer.size() - 1)),
		"total": buffer.size(),
		"interval_s": float(replay.get("interval_s", 1.0)),
		"t": t,
		"current": replay_frame(),
		"frames": frames,
	}



func _with(d: Dictionary, key: String, value) -> Dictionary:
	var o: Dictionary = d
	o[key] = value
	return o
