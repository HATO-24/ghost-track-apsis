class_name V17Bridge
extends RefCounted

# V17 数据桥：V1 HUD/plot 继续做主角，framework/ 的 V2 core/sim 只作为数据后端。
# 不在这里画 UI；V17 HUD/plot 通过 bridge / state.fw_* 读取只读 view-model。
#
# 设计（V17-CORE-1）：
#   - boot()：装载 V2 场景 + world + mission；V15 自己拥有 PRELUDE 覆盖层，默认跳过
#     V2 prelude（避免双门控；DSH_V2_PRELUDE=1 可保留）。
#   - sync(dt)：由 V15 state 时钟驱动 world.advance(dt)（V15 paused/sim_frozen 时 dt=0），
#     随后刷新归一化快照：tutorial / flow / damage / replay / contacts / actions / exec。
#   - 所有 vm_* 数据只读；写操作只走 perform_action / start_repair / open_decision 等封装。
#   - 教学门控：tutorial_allowed() / decision_reason() 供 V15 decision 使用；
#     DSH_SKIP_TUTORIAL=1 时 V2 端门控禁用（world 装载时读取）。
#
# 字段名与 UI/plot 约定见 game_v17/docs/v17_bridge_fields.md。

const ScenarioScript := preload("res://framework/core/scenario.gd")
const WorldScript := preload("res://framework/core/world.gd")
const MissionScript := preload("res://framework/core/mission.gd")
const NavigationScript := preload("res://framework/core/navigation_model.gd")

const DEFAULT_SCENARIO := "res://framework/content/scenario_l1_v2.json"

var scenario: V2Scenario
var world: V2World
var mission: V2Mission
var ready := false
var errors: Array[String] = []

# —— 归一化只读快照（state.fw_* 直接复制这些）——
var tutorial: Dictionary = {}
var flow: Dictionary = {}
var damage: Dictionary = {}
var damage_full: Dictionary = {}
var damage_model_ready := false
var replay: Dictionary = {}
var contacts: Array = []
var actions: Array = []
var actions_target := ""
var tutorial_ready := false
var exec_window_s := 360.0
var exec_left := 360.0
var exec_pct := 0.0
var decision_reason := ""
# —— R4-CORE-2：导航/交通管制/机动规划（V2NavigationModel；只读快照）——
var nav = null                      # V2NavigationModel（未就绪为 null）
var nav_ready := false
var nav_snapshot: Dictionary = {}   # vm_navigation() 只读快照
var nav_summary: Dictionary = {}
var nav_last: Dictionary = {}       # 最近一次导航写操作结果

# —— 运行时元数据 ——
var sync_count := 0
var synced_t := 0.0
var skipped_v2_prelude := false
var last_action: Dictionary = {}
## 回放查看头：seek 后固定在该帧；录制继续追加帧时不移动播放头（-1=不固定）。
var replay_index_pin := -1

func boot(scenario_path := DEFAULT_SCENARIO) -> bool:
	errors.clear()
	scenario = ScenarioScript.load_file(scenario_path)
	if not scenario.errors.is_empty():
		errors.append_array(scenario.errors)
	world = WorldScript.new()
	var ok := world.load_scenario(scenario)
	if not ok:
		errors.append_array(world.errors)
	mission = MissionScript.from_scenario(scenario)
	world.attach_mission(mission)
	# R4-CORE-2：导航/交通管制/机动规划（独立模型；失败不阻塞世界桥）
	nav = NavigationScript.new()
	nav_ready = bool(nav.setup())
	if not nav_ready:
		errors.append("navigation: " + str(nav.errors))
	ready = ok
	# V15 自己有 PRELUDE 覆盖层；默认跳过 V2 prelude，避免“执行前冻结”双门控。
	if ready and OS.get_environment("DSH_V2_PRELUDE") != "1":
		var pre := world.prelude_skip()
		skipped_v2_prelude = bool(pre.get("ok", false))
	refresh()
	return ready

## 由 V15 state 每帧驱动：dt 已按 time_scale 折算（暂停/冻结/截图时传 0）。
func sync(dt: float) -> void:
	if not ready:
		return
	var step := maxf(0.0, dt)
	if step > 0.0:
		world.advance(step)
		if nav_ready and nav != null:
			nav.step(step)
	sync_count += 1
	synced_t = float(world.t)
	refresh()

## 刷新归一化快照（vm_* 只读）。
func refresh() -> void:
	if not ready:
		return
	tutorial = world.vm_tutorial()
	flow = world.vm_flow()
	damage = world.vm_damage()
	damage_full = world.vm_damage_full() if world.has_method("vm_damage_full") else {}
	damage_model_ready = not damage_full.is_empty()
	_refresh_replay()
	contacts = world.vm_contacts()
	_refresh_nav()
	tutorial_ready = bool(tutorial.get("ready", false))
	exec_window_s = float(world.exec_window_s)
	exec_left = world.exec_left()
	exec_pct = world.exec_pct()
	decision_reason = _compute_decision_reason()
	if actions_target != "":
		actions = world.vm_actions(actions_target)

## 只刷新导航只读快照（导航写操作后调用，避免整桥 refresh 的成本）。
func _refresh_nav() -> void:
	if nav_ready and nav != null:
		nav_snapshot = nav.vm_navigation()
		nav_summary = nav.summary()
	else:
		nav_snapshot = {}
		nav_summary = {}

## 当前导航 vm（只读；未就绪返回空字典）。
func navigation_view() -> Dictionary:
	return nav_snapshot

func navigation_summary() -> Dictionary:
	return nav_summary

## 完整损管模型 vm（R2-DAMAGE-2 接入；旧 damage_view() 保留 legacy 字段）。
func damage_full_view() -> Dictionary:
	return damage_full


## 只刷新回放快照并返回（HUD 调试钩子直接操作 world.replay_* 后可调用，避免读到旧帧列表）。
func replay_view_fresh() -> Dictionary:
	if not ready:
		return {}
	_refresh_replay()
	return replay.duplicate(true)

## 回放快照刷新：若查看头被 seek 固定，录制继续追加帧也不移动播放头（每帧重新对齐一次）。
func _refresh_replay() -> void:
	if replay_index_pin >= 0:
		var cur_rep: Dictionary = world.vm_replay()
		var total := int(cur_rep.get("total", 0))
		if total > 0:
			var pin := clampi(replay_index_pin, 0, total - 1)
			if int(cur_rep.get("index", -1)) != pin:
				world.replay_seek_index(pin)
				cur_rep = world.vm_replay()
			replay_index_pin = pin
			cur_rep["pinned"] = true
			var cur_frame: Dictionary = world.replay_frame()
			cur_rep["frame_t"] = float(cur_frame.get("t", 0.0))
			replay = cur_rep
		else:
			replay = cur_rep
	else:
		replay = world.vm_replay()
		replay["pinned"] = false
		var cur_frame2: Dictionary = world.replay_frame()
		replay["frame_t"] = float(cur_frame2.get("t", 0.0))

func _compute_decision_reason() -> String:
	if not bool(tutorial.get("enabled", false)):
		return ""
	if bool(tutorial.get("ready", false)):
		return ""
	var p: Dictionary = (tutorial.get("progress", {}) as Dictionary)
	return "教学门控：识别不足（%d/%d）— %s" % [
		int(p.get("done", 0)), int(p.get("need", 0)), String(tutorial.get("hint", ""))]

## V15 decision 门控：V2 教程未完成时返回 false（不自动完成识别）。
func tutorial_allowed() -> bool:
	if not ready:
		return true
	if not bool(tutorial.get("enabled", false)):
		return true
	return bool(tutorial.get("ready", false))

## 当前门控原因（空字符串 = 未阻塞）。
func decision_gate_reason() -> String:
	return decision_reason

# ── 只读查询 ─────────────────────────────────────────────────────

func summary() -> Dictionary:
	if not ready:
		return {"ready": false, "errors": errors.duplicate()}
	var fc: Dictionary = (flow.get("decision", {}) as Dictionary)
	var choice: Dictionary = (fc.get("decision", {}) as Dictionary)
	return {
		"ready": true,
		"scenario": scenario.id,
		"title": scenario.title,
		"entities": world.entities.size(),
		"contacts": contacts.size(),
		"own": world.own_id,
		"phase": String(mission.phase) if mission != null else "",
		"phase_kind": String(mission.kind) if mission != null else "",
		"t": float(world.t),
		"tutorial_ready": tutorial_ready,
		"tutorial": "%d/%d" % [
			int((tutorial.get("progress", {}) as Dictionary).get("done", 0)),
			int((tutorial.get("progress", {}) as Dictionary).get("need", 0))],
		"decision_open": bool(fc.get("open", false)),
		"decision_made": not choice.is_empty(),
		"exec_window_s": exec_window_s,
		"exec_left": exec_left,
		"skipped_v2_prelude": skipped_v2_prelude,
		"errors": errors.duplicate(),
	}

func contacts_view() -> Array:
	return contacts

func actions_for(track_id: String) -> Array:
	return world.vm_actions(track_id) if ready else []

func set_actions_target(track_id: String) -> void:
	actions_target = track_id
	if ready:
		actions = world.vm_actions(track_id)

func selected() -> Dictionary:
	return world.vm_selected() if ready else {}

func contact(track_id: String) -> Dictionary:
	return world.vm_contact(track_id) if ready else {}

func flow_view() -> Dictionary:
	return flow

func tutorial_view() -> Dictionary:
	return tutorial

func damage_view() -> Dictionary:
	return damage

func replay_view() -> Dictionary:
	return replay

func bridge_state() -> Dictionary:
	return {
		"ready": ready,
		"summary": summary(),
		"tutorial": tutorial.duplicate(true),
		"tutorial_ready": tutorial_ready,
		"decision_reason": decision_reason,
		"flow": flow.duplicate(true),
		"damage": damage.duplicate(true),
		"damage_full": damage_full.duplicate(true),
		"damage_model_ready": damage_model_ready,
		"replay": replay.duplicate(true),
		"contacts": contacts.duplicate(true),
		"actions": actions.duplicate(true),
		"actions_target": actions_target,
		"nav": nav_snapshot.duplicate(true),
		"nav_summary": nav_summary.duplicate(true),
		"nav_ready": nav_ready,
		"exec_window_s": exec_window_s,
		"exec_left": exec_left,
		"exec_pct": exec_pct,
		"sync_count": sync_count,
		"t": synced_t,
	}

# ── 写操作（wrapper；每次都刷新快照）─────────────────────────────

func perform_action(action_id: String, target_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.perform_action(action_id, target_id)
	last_action = r.duplicate(true)
	refresh()
	return r

func start_repair(section_id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.start_repair(section_id)
	refresh()
	return r

func apply_damage(id: String, severity := 0.5, label := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.apply_damage(id, severity, label)
	refresh()
	return r

func open_decision() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.open_decision()
	refresh()
	return r

func choose_ending(kind: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.choose_ending(kind)
	refresh()
	return r

func submit_report(truth := true) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.submit_report(truth)
	refresh()
	return r

func evidence_start(id: String) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.start_evidence(id)
	refresh()
	return r

func advance_mission(steps := 1) -> Array:
	if not ready:
		return []
	var out: Array = world.advance_mission(steps)
	refresh()
	return out

# —— 回放（只读帧；不推进世界；seek 后固定查看头）——
func replay_start() -> Dictionary:
	if not ready:
		return {}
	world.replay_start()
	replay_index_pin = 0
	refresh()
	return replay.duplicate(true)

func replay_pause() -> Dictionary:
	if not ready:
		return {}
	var r: Dictionary = world.replay_pause()
	replay_index_pin = int(r.get("index", 0))
	refresh()
	return replay.duplicate(true)

func replay_stop() -> Dictionary:
	if not ready:
		return {}
	var r: Dictionary = world.replay_stop()
	replay_index_pin = -1
	refresh()
	return replay.duplicate(true)

func replay_seek(t_s: float) -> Dictionary:
	if not ready:
		return {}
	var r: Dictionary = world.replay_seek(t_s)
	replay_index_pin = int(r.get("index", 0))
	refresh()
	return replay.duplicate(true)

func replay_seek_index(index: int) -> Dictionary:
	if not ready:
		return {}
	var r: Dictionary = world.replay_seek_index(index)
	replay_index_pin = int(r.get("index", index))
	refresh()
	return replay.duplicate(true)

func replay_frame() -> Dictionary:
	if not ready:
		return {}
	if replay_index_pin >= 0:
		var total := int(world.vm_replay().get("total", 0))
		if total > 0 and int(world.replay.get("index", -1)) != clampi(replay_index_pin, 0, total - 1):
			world.replay_seek_index(clampi(replay_index_pin, 0, total - 1))
	return world.replay_frame()

func replay_clear() -> void:
	if ready:
		replay_index_pin = -1
		world.replay_clear()
		refresh()

# ── R4-CORE-2：导航/交通管制/机动规划 wrapper（只转发；不自动执行/不自动授权）──

func _nav_call(method: String, args: Array = []) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	if not nav_ready or nav == null:
		return {"ok": false, "reason": "navigation 未就绪"}
	var r = nav.callv(method, args)
	nav_last = (r as Dictionary).duplicate(true) if r is Dictionary else {}
	_refresh_nav()
	return r if r is Dictionary else {}

func nav_plan_routes(from_id: String, to_id: String, constraints := {}) -> Dictionary:
	return _nav_call("plan_routes", [from_id, to_id, constraints])

func nav_select_route(route_arg = null) -> Dictionary:
	return _nav_call("select_route", [route_arg])

func nav_request_clearance(route_arg = null, window = null, priority := 3) -> Dictionary:
	return _nav_call("request_clearance", [route_arg, window, priority])

func nav_grant_clearance(request_id: String) -> Dictionary:
	return _nav_call("grant_clearance", [request_id])

func nav_deny_clearance(request_id: String, reason := "authority_denied") -> Dictionary:
	return _nav_call("deny_clearance", [request_id, reason])

func nav_hold_clearance(request_id: String, until_t := -1.0) -> Dictionary:
	return _nav_call("hold_clearance", [request_id, until_t])

# 任务要求的短别名
func nav_grant(request_id: String) -> Dictionary:
	return nav_grant_clearance(request_id)

func nav_deny(request_id: String, reason := "authority_denied") -> Dictionary:
	return nav_deny_clearance(request_id, reason)

func nav_hold(request_id: String, until_t := -1.0) -> Dictionary:
	return nav_hold_clearance(request_id, until_t)

func nav_plan_maneuver(kind: String, target := "", opts := {}) -> Dictionary:
	return _nav_call("plan_maneuver", [kind, target, opts])

func nav_authorize_maneuver(plan_id: String) -> Dictionary:
	return _nav_call("authorize_maneuver", [plan_id])

func nav_queue_maneuver(plan_id: String, clearance_id := "") -> Dictionary:
	return _nav_call("queue_maneuver", [plan_id, clearance_id])

func nav_execute_maneuver(plan_id: String) -> Dictionary:
	return _nav_call("execute_maneuver", [plan_id])

func nav_abort_maneuver(plan_id: String, reason := "commander_abort") -> Dictionary:
	return _nav_call("abort_maneuver", [plan_id, reason])

# 任务要求的短别名
func nav_authorize(plan_id: String) -> Dictionary:
	return nav_authorize_maneuver(plan_id)

func nav_execute(plan_id: String) -> Dictionary:
	return nav_execute_maneuver(plan_id)

func nav_abort(plan_id: String, reason := "commander_abort") -> Dictionary:
	return nav_abort_maneuver(plan_id, reason)

# ── 完整损管模型写 API（只转发到 world/entity.damage；不自动命中/不生成武器）──

func damage_apply_hit(section: String, energy: float, penetration := 0.5,
		direction := "fore", source := "bridge", entity_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.damage_apply_hit(section, energy, penetration, direction,
		source, entity_id)
	refresh()
	return r

func damage_assign_repair(section: String, priority := 2, entity_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.damage_assign_repair(section, priority, entity_id)
	refresh()
	return r

func damage_cancel_repair(section: String, entity_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.damage_cancel_repair(section, entity_id)
	refresh()
	return r

func damage_set_priority(section: String, priority: int, entity_id := "") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.damage_set_priority(section, priority, entity_id)
	refresh()
	return r

func restart() -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = world.restart()
	skipped_v2_prelude = false
	if OS.get_environment("DSH_V2_PRELUDE") != "1":
		var pre := world.prelude_skip()
		skipped_v2_prelude = bool(pre.get("ok", false))
	if nav_ready and nav != null:
		nav.reset()
	refresh()
	return r

func advance(dt: float) -> void:
	sync(dt)
