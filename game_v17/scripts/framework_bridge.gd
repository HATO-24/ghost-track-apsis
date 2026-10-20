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
const PhysicsScript := preload("res://framework/sim/cislunar_physics.gd")
const SensorAuthorityScript := preload("res://framework/sim/sensor_authority.gd")
const InformationWarfareScript := preload("res://framework/sim/information_warfare.gd")
const OpticalIRScript := preload("res://framework/sim/optical_ir_channel.gd")
const DockingScript := preload("res://framework/sim/docking_controller.gd")

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
# —— R6-SHADOW-1 / R6-AUTH-1：CR3BP/RK4 物理（shadow / authoritative 适配层）——
var physics = null
var physics_requested_mode := "shadow"  # V17_PHYSICS 请求：shadow/authoritative/off
var physics_mode := "off"               # 有效模式（authoritative 失败时回落 shadow）
var physics_ready := false
var physics_fallback_reason := ""
var physics_authoritative_view_data: Dictionary = {}
var physics_adapter_last: Dictionary = {}
var physics_view_data: Dictionary = {}
var physics_summary_data: Dictionary = {}
var physics_entity_sources: Dictionary = {}
var physics_jacobi0: Dictionary = {}
var physics_warnings: Array = []
const PHYSICS_STEP_S := 60.0
const MAX_PHYSICS_WARNINGS := 32
const COMPARE_THRESHOLDS := {"range_km": 5.0, "bearing_deg": 5.0, "position_km": 50.0}
# —— R5-SENSOR-BRIDGE-1：传感器 shadow（V2SensorAuthority；只读 advisory）——
var sensor_shadow = null
var sensor_authority_requested_mode := "shadow"  # V17_SENSOR_AUTHORITY 请求
var sensor_authority_mode := "off"               # shadow / authoritative(显示层) / off
var sensor_shadow_mode := "off"                  # 模型有效模式：shadow / off（authoritative 仅显示层）
var sensor_shadow_ready := false
var sensor_shadow_view_data: Dictionary = {}
var sensor_shadow_summary_data: Dictionary = {}
var sensor_shadow_warnings: Array = []
var sensor_shadow_fallback_reason := ""
var sensor_compare_last: Dictionary = {}
const MAX_SENSOR_WARNINGS := 32
# —— R5-INFO-BRIDGE-1：信息作战 shadow（V2InformationWarfare；IFF/ELINT/COMINT/EW advisory）——
var info_warfare = null
var info_warfare_requested_mode := "shadow"
var info_warfare_mode := "off"          # shadow / off（authoritative 不实现）
var info_warfare_ready := false
var info_warfare_view_data: Dictionary = {}
var info_warfare_summary_data: Dictionary = {}
var info_warfare_warnings: Array = []
var info_warfare_fallback_reason := ""
var info_warfare_recent_events: Array = []
var info_warfare_recent_alerts: Array = []
const MAX_INFO_WARNINGS := 32
# —— R5-OPT-DOCK-BRIDGE-1：光学/IR 通道 + 对接控制器（只读 VM / 显式 API）——
var optical_ir = null
var optical_ir_enabled := true
var optical_ir_ready := false
var optical_ir_view_data: Dictionary = {}
var optical_ir_summary_data: Dictionary = {}
var optical_ir_warnings: Array = []
var docking = null
var docking_enabled := true
var docking_ready := false
var docking_view_data: Dictionary = {}
var docking_update_last: Dictionary = {}
var optical_docking_warnings: Array = []
const MAX_OPT_WARNINGS := 32
const INFO_RECENT_MAX := 8
# —— R5-AUTO-SENSOR-1：bridge 自动光学/对接数据（默认 auto；on=手动；off=关闭）——
var optical_ir_auto_enabled := true
var docking_auto_enabled := true
var optical_ir_auto_suppressed := false
var docking_auto_suppressed := false
var optical_ir_auto_target := ""
var docking_auto_target := "chronos-dock-a"
var optical_ir_auto_step_count := 0
var docking_auto_step_count := 0

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
	# R6-SHADOW-1：CR3BP/RK4 物理 shadow（只读；V17_PHYSICS=off 关闭）
	_init_physics_shadow()
	_bind_nav_position_provider()
	# R5-SENSOR-BRIDGE-1：传感器 shadow（只读 advisory；V17_SENSOR_AUTHORITY=off 关闭）
	_init_sensor_shadow()
	# R5-INFO-BRIDGE-1：信息作战 shadow（IFF/ELINT/COMINT/EW advisory；V17_INFO_WARFARE=off 关闭）
	_init_info_warfare()
	# R5-OPT-DOCK-BRIDGE-1：光学/IR + 对接（只读 VM；V17_OPTICAL_IR/V17_DOCKING=off 关闭）
	_init_optical_docking()
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
		_step_physics_shadow(step)
		_step_sensor_shadow(step)
		_step_info_warfare(step)
		_auto_optical_ir(step)
		_auto_docking(step)
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
	_refresh_physics()
	_refresh_sensor_shadow()
	_refresh_info_warfare()
	_refresh_optical_docking()
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

## R6-SHADOW-1：CR3BP/RK4 物理 shadow 只读 vm / summary（authoritative=false）。
func physics_view() -> Dictionary:
	return physics_view_data

func physics_summary() -> Dictionary:
	return physics_summary_data


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
		"physics": physics_view_data.duplicate(true),
		"physics_summary": physics_summary_data.duplicate(true),
		"physics_ready": physics_ready,
		"physics_mode": physics_mode,
		"physics_requested_mode": physics_requested_mode,
		"physics_fallback_reason": physics_fallback_reason,
		"physics_authoritative": physics_authoritative_view_data.duplicate(true),
		"physics_adapter": physics_adapter_last.duplicate(true),
		"sensor_shadow": sensor_shadow_view_data.duplicate(true),
		"sensor_shadow_summary": sensor_shadow_summary_data.duplicate(true),
		"sensor_shadow_ready": sensor_shadow_ready,
		"sensor_shadow_mode": sensor_shadow_mode,
		"sensor_authority_requested_mode": sensor_authority_requested_mode,
		"sensor_authority_mode": sensor_authority_mode,
		"sensor_authority_display": sensor_authority_display(),
		"sensor_shadow_fallback_reason": sensor_shadow_fallback_reason,
		"sensor_compare": sensor_compare_last.duplicate(true),
		"info_warfare": info_warfare_view_data.duplicate(true),
		"info_warfare_summary": info_warfare_summary_data.duplicate(true),
		"info_warfare_ready": info_warfare_ready,
		"info_warfare_mode": info_warfare_mode,
		"info_warfare_requested_mode": info_warfare_requested_mode,
		"info_warfare_fallback_reason": info_warfare_fallback_reason,
		"info_warfare_recent_events": info_warfare_recent_events.duplicate(true),
		"info_warfare_recent_alerts": info_warfare_recent_alerts.duplicate(true),
		"optical_ir": optical_ir_view_data.duplicate(true),
		"optical_ir_summary": optical_ir_summary_data.duplicate(true),
		"optical_ir_ready": optical_ir_ready,
		"optical_ir_enabled": optical_ir_enabled,
		"optical_ir_auto": optical_ir_auto_enabled,
		"optical_ir_auto_suppressed": optical_ir_auto_suppressed,
		"optical_ir_auto_target": optical_ir_auto_target,
		"optical_ir_auto_step_count": optical_ir_auto_step_count,
		"docking": docking_view_data.duplicate(true),
		"docking_ready": docking_ready,
		"docking_enabled": docking_enabled,
		"docking_auto": docking_auto_enabled,
		"docking_auto_suppressed": docking_auto_suppressed,
		"docking_auto_step_count": docking_auto_step_count,
		"docking_update_last": docking_update_last.duplicate(true),
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
	_init_physics_shadow()
	_bind_nav_position_provider()
	_init_sensor_shadow()
	_init_info_warfare()
	_init_optical_docking()
	refresh()
	return r

func advance(dt: float) -> void:
	sync(dt)

# ═══════════════════════════════════════════════════════════════════
# R6-SHADOW-1：CR3BP/RK4 物理 shadow（只读；authoritative=false）
#   - 从 V2 world 实体初始状态装载（L1 局部近似/固定占位；缺失状态明确标注默认）；
#   - 每帧固定步长（≤60s）RK4 推进；不写 V15 轨道/plot/HUD，不自动执行导航机动；
#   - navigation 节点位置 provider 绑定到 shadow/地月模型位置（地心旋转系 km）；
#   - V17_PHYSICS=off 可关闭；R6 后续才替换 V15 位置源。
# ═══════════════════════════════════════════════════════════════════

func _init_physics_shadow() -> void:
	physics = null
	physics_ready = false
	physics_fallback_reason = ""
	physics_view_data = {}
	physics_summary_data = {}
	physics_authoritative_view_data = {}
	physics_adapter_last = {}
	physics_entity_sources.clear()
	physics_jacobi0.clear()
	physics_warnings.clear()
	var env_mode := OS.get_environment("V17_PHYSICS").to_lower()
	if env_mode == "off":
		physics_requested_mode = "off"
	elif env_mode == "shadow":
		physics_requested_mode = "shadow"
	else:
		# 默认进入 authoritative；初始化失败会显式回落 shadow。
		physics_requested_mode = "authoritative"
	physics_mode = physics_requested_mode
	if physics_mode == "off":
		_refresh_authoritative_view()
		return
	# 调试钩子：模拟 authoritative 初始化失败以验证回落（probe 用；不影响正常流程）
	if OS.get_environment("V17_PHYSICS_FORCE_FAIL") == "1":
		physics = null
		physics_ready = false
		if physics_requested_mode == "authoritative":
			physics_mode = "shadow"
			physics_fallback_reason = "authoritative 初始化失败（V17_PHYSICS_FORCE_FAIL=1 调试）→ 回落 shadow"
			_note_physics_warning(physics_fallback_reason)
		_refresh_authoritative_view()
		return
	physics = PhysicsScript.new({"step_s": PHYSICS_STEP_S})
	var l1_state: Dictionary = PhysicsScript.lagrange_state("L1")
	if l1_state.is_empty():
		errors.append("physics: L1 初始化失败")
		physics = null
		if physics_requested_mode == "authoritative":
			physics_mode = "shadow"
			physics_fallback_reason = "authoritative 初始化失败（L1 不可用）→ 回落 shadow"
			_note_physics_warning(physics_fallback_reason)
		_refresh_authoritative_view()
		return
	for raw in world.entities:
		var e: V2Entity = raw
		var built := _physics_state_for_entity(e, l1_state)
		var state: Dictionary = built.get("state", {})
		var add_res: Dictionary = physics.add_entity(e.id, state)
		if bool(add_res.get("ok", false)):
			physics_entity_sources[e.id] = String(built.get("source", ""))
			physics_jacobi0[e.id] = PhysicsScript.jacobi_constant(state)
		else:
			_note_physics_warning("实体 %s 物理初始化失败：%s" % [e.id, str(add_res.get("errors", []))])
	physics_ready = not physics.entity_ids().is_empty() and physics.errors.is_empty()
	if physics_ready:
		_note_physics_warning("物理：实体初始状态来自 V2 场景 L1 局部近似/固定占位（非 JPL 星历）")
	if physics_requested_mode == "authoritative" and not physics_ready:
		physics_mode = "shadow"
		physics_fallback_reason = "authoritative 初始化失败（实体为空/含错误）→ 回落 shadow"
		_note_physics_warning(physics_fallback_reason)
	elif physics_mode == "authoritative" and physics_ready:
		_note_physics_warning("authoritative 适配层就绪：显示层尚未切换（不写 V15 tracks/HUD）；准备切换。")
	_refresh_authoritative_view()

## 从 V2 实体 orbit 构造 barycenter rotating 初始状态；缺失/未知状态使用明确默认并标注。
func _physics_state_for_entity(e: V2Entity, l1_state: Dictionary) -> Dictionary:
	var orbit: Dictionary = e.orbit if e.orbit is Dictionary else {}
	var frame := String(orbit.get("frame", ""))
	var r_arr: Array = orbit.get("r", []) if orbit.get("r") is Array else []
	var v_arr: Array = orbit.get("v", []) if orbit.get("v") is Array else []
	var l1_r: Vector3 = PhysicsScript.to_vec3(l1_state.get("r", Vector3.ZERO), Vector3.ZERO)
	if frame == "L1" and r_arr.size() >= 3:
		var off := Vector3(float(r_arr[0]), float(r_arr[1]), float(r_arr[2]))
		var vel := Vector3.ZERO
		if v_arr.size() >= 3:
			vel = Vector3(float(v_arr[0]), float(v_arr[1]), float(v_arr[2]))
		var note := ""
		if e.is_fixed():
			vel = Vector3.ZERO
			note = "V2 L1 固定/站保持占位（非星历）"
		else:
			note = "V2 L1 局部近似 + 场景演示速度（非星历）"
		return {"state": PhysicsScript.make_state(l1_r + off, vel), "source": note}
	return {"state": PhysicsScript.make_state(l1_r, Vector3.ZERO),
		"source": "缺失/未知轨道状态 → L1 静止默认（明确标注，不伪造星历）"}

## 固定步长 shadow 推进；收集 warnings（去重/限长）。
func _step_physics_shadow(dt: float) -> void:
	if not (physics_mode in ["shadow", "authoritative"]) or not physics_ready or physics == null:
		return
	var res: Dictionary = physics.propagate(dt)
	if not bool(res.get("ok", true)):
		_note_physics_warning("物理 shadow 推进失败：" + String(res.get("reason", "")))
		return
	for raw in (res.get("warnings", []) as Array):
		_note_physics_warning(String(raw))

func _note_physics_warning(text: String) -> void:
	if text == "" or physics_warnings.has(text):
		return
	physics_warnings.append(text)
	while physics_warnings.size() > MAX_PHYSICS_WARNINGS:
		physics_warnings.pop_front()

func _refresh_physics() -> void:
	if not (physics_mode in ["shadow", "authoritative"]) or physics == null:
		physics_view_data = {}
		physics_summary_data = {"ready": false, "mode": physics_mode,
			"requested_mode": physics_requested_mode, "authoritative": false,
			"fallback_reason": physics_fallback_reason, "display_switched": false,
			"t": 0.0, "entities": 0, "warnings": physics_warnings.size()}
		_refresh_authoritative_view()
		return
	var t_now := float(physics.t)
	var entities: Array = []
	var max_drift := 0.0
	for raw in physics.sample_all():
		var s: Dictionary = (raw as Dictionary).duplicate(true)
		var eid := String(s.get("id", ""))
		var jac := float(s.get("jacobi", 0.0))
		var jac0 := float(physics_jacobi0.get(eid, jac))
		s["jacobi0"] = jac0
		s["jacobi_drift"] = absf(jac - jac0)
		max_drift = maxf(max_drift, float(s["jacobi_drift"]))
		s["source"] = String(physics_entity_sources.get(eid, "V2 场景实体（非星历）"))
		entities.append(s)
	var refs := _physics_reference(t_now)
	var is_auth := physics_mode == "authoritative"
	physics_view_data = {
		"schema": "cislunar_physics.v1",
		"model": "cr3bp_rk4_circular",
		"authoritative": is_auth,
		"mode": physics_mode,
		"requested_mode": physics_requested_mode,
		"fallback_reason": physics_fallback_reason,
		"display_switched": false,
		"ready": physics_ready,
		"v15_orbit_source": "unchanged（V15 轨道/sensor_model/plot 仍是权威；物理适配层不写 V15）",
		"t": t_now,
		"step_s": float(physics.config.get("step_s", PHYSICS_STEP_S)),
		"config": physics.config.duplicate(true),
		"entities": entities,
		"reference": refs,
		"warnings": physics_warnings.duplicate(),
		"note": "CR3BP/RK4 物理：shadow/authoritative 适配层；显示层尚未切换；实体初始状态为 V2 场景 L1 局部近似/固定占位（非 JPL 星历）。",
	}
	physics_summary_data = {
		"ready": physics_ready,
		"mode": physics_mode,
		"requested_mode": physics_requested_mode,
		"authoritative": is_auth,
		"fallback_reason": physics_fallback_reason,
		"display_switched": false,
		"t": t_now,
		"entities": entities.size(),
		"frames": ["bary_rot", "earth_rot", "earth_eci"],
		"warnings": physics_warnings.size(),
		"max_jacobi_drift": max_drift,
		"nav_position_provider": bool(nav_ready and physics_ready
			and (physics_mode in ["shadow", "authoritative"])),
		"v15_orbit_source": "unchanged",
		"compare_thresholds": COMPARE_THRESHOLDS.duplicate(true),
		"reference": {
			"lagrange": (refs.get("lagrange", {}) as Dictionary).size(),
			"geo": (refs.get("geo", {}) as Dictionary).size(),
			"lunar_leo": (refs.get("lunar_leo", {}) as Dictionary).size(),
			"moon": (refs.get("moon", {}) as Dictionary).size(),
		},
	}
	_refresh_authoritative_view()

## L1–L5 / GEO / LLO / 月球 静态参考采样（读时按 shadow t 生成；不改任何状态）。
func _physics_reference(t_now: float) -> Dictionary:
	var refs := {"lagrange": {}, "geo": {}, "lunar_leo": {}, "moon": {}}
	var lps: Dictionary = PhysicsScript.equilibrium_points()
	for lid in ["L1", "L2", "L3", "L4", "L5"]:
		if not lps.has(lid):
			continue
		var lp: Dictionary = lps[lid]
		var st: Dictionary = PhysicsScript.lagrange_state(lid)
		if st.is_empty():
			continue
		var eci: Dictionary = PhysicsScript.bary_rot_to_earth_eci(st, t_now)
		var erot: Dictionary = PhysicsScript.bary_rot_to_earth_rot(st)
		(refs["lagrange"] as Dictionary)[lid] = {
			"id": lid,
			"kind": String(lp.get("kind", "")),
			"position_earth_rot_km": _vec_arr(PhysicsScript.to_vec3(erot.get("r", Vector3.ZERO), Vector3.ZERO)),
			"state_earth_eci": PhysicsScript.state_to_array_dict(eci),
			"state_earth_rot": PhysicsScript.state_to_array_dict(erot),
			"distance_earth_km": float(lp.get("earth_distance_km", 0.0)),
			"distance_moon_km": float(lp.get("moon_distance_km", 0.0)),
			"jacobi": float(lp.get("jacobi", 0.0)),
		}
	var geo: Dictionary = PhysicsScript.geo_state(t_now)
	var geo_eci: Dictionary = PhysicsScript.as_state(geo)
	var geo_rot := _physics_eci_to_earth_rot(geo_eci, t_now)
	refs["geo"] = {
		"radius_km": float(geo.get("radius_km", PhysicsScript.GEO_RADIUS_KM)),
		"period_s": float(geo.get("period_s", 0.0)),
		"phase_rad": float(geo.get("phase_rad", 0.0)),
		"position_earth_rot_km": _vec_arr(PhysicsScript.to_vec3(geo_rot.get("r", Vector3.ZERO), Vector3.ZERO)),
		"state_earth_eci": PhysicsScript.state_to_array_dict(geo_eci),
		"speed_kmps": float(geo.get("speed_kmps", 0.0)),
	}
	var llo: Dictionary = PhysicsScript.llo_state(t_now)
	var llo_eci: Dictionary = PhysicsScript.as_state(llo)
	var llo_rot := _physics_eci_to_earth_rot(llo_eci, t_now)
	var moon_rot_pos := _moon_earth_rot_pos(t_now)
	refs["lunar_leo"] = {
		"radius_km": float(llo.get("radius_km", PhysicsScript.llo_radius_km())),
		"period_s": float(llo.get("period_s", 0.0)),
		"inclination_deg": float(llo.get("inclination_deg", 0.0)),
		"position_earth_rot_km": _vec_arr(PhysicsScript.to_vec3(llo_rot.get("r", Vector3.ZERO), Vector3.ZERO)),
		"state_earth_eci": PhysicsScript.state_to_array_dict(llo_eci),
		"distance_moon_km": PhysicsScript.to_vec3(llo_rot.get("r", Vector3.ZERO), Vector3.ZERO).distance_to(moon_rot_pos),
	}
	var moon: Dictionary = PhysicsScript.moon_state_eci(t_now)
	refs["moon"] = {
		"distance_km": float(moon.get("distance_km", PhysicsScript.D_KM)),
		"period_s": float(moon.get("period_s", PhysicsScript.T_MOON_S)),
		"phase_rad": float(moon.get("phase_rad", 0.0)),
		"position_earth_rot_km": _vec_arr(moon_rot_pos),
		"state_earth_eci": PhysicsScript.state_to_array_dict(PhysicsScript.as_state(moon)),
	}
	return refs

func _physics_eci_to_earth_rot(eci_state: Dictionary, t_now: float) -> Dictionary:
	var bary: Dictionary = PhysicsScript.earth_eci_to_bary_rot(eci_state, t_now)
	return PhysicsScript.bary_rot_to_earth_rot(bary)

func _moon_earth_rot_pos(_t_now: float) -> Vector3:
	var erot: Dictionary = PhysicsScript.bary_rot_to_earth_rot(PhysicsScript.moon_state_rot())
	return PhysicsScript.to_vec3(erot.get("r", Vector3.ZERO), Vector3.ZERO)

func _vec_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

# ── navigation 位置 provider（绑定到 shadow 物理/地月模型；Earth-centered rotating km）──

func _bind_nav_position_provider() -> void:
	if nav_ready and nav != null:
		if (physics_mode in ["shadow", "authoritative"]) and physics_ready:
			nav.bind_position_provider(Callable(self, "_nav_shadow_position"))
		else:
			nav.clear_position_provider()

## provider 签名：func(position_source:String, node_id:String) -> Array|Vector3|Dictionary。
## 返回地心旋转系 km（与 navigation 内容 abstract_pos_km 同系）；未知/off 返回 [] 让 nav 回退抽象坐标。
func _nav_shadow_position(position_source: String, node_id: String) -> Array:
	if not (physics_mode in ["shadow", "authoritative"]) or not physics_ready:
		return []
	var t_now := float(physics.t) if physics != null else 0.0
	var src := position_source
	if src == "":
		match node_id:
			"earth_port":
				src = "cislunar:earth_port"
			"geo":
				src = "cislunar:geo_ring"
			"l1":
				src = "cislunar:l1_station"
			"l2":
				src = "cislunar:l2_station"
			"l4":
				src = "cislunar:l4_station"
			"l5":
				src = "cislunar:l5_station"
			"moon_port":
				src = "cislunar:lunar_port"
			"lunar_leo":
				src = "cislunar:lunar_leo"
			_:
				src = ""
	match src:
		"cislunar:earth_port":
			return _vec_arr(Vector3(PhysicsScript.R_EARTH_KM, 0.0, 0.0))
		"cislunar:geo_ring":
			return _nav_eci_pos(PhysicsScript.geo_state(t_now), t_now)
		"cislunar:l1_station":
			return _nav_lagrange_pos("L1")
		"cislunar:l2_station":
			return _nav_lagrange_pos("L2")
		"cislunar:l4_station":
			return _nav_lagrange_pos("L4")
		"cislunar:l5_station":
			return _nav_lagrange_pos("L5")
		"cislunar:lunar_port":
			var moon_pos := _moon_earth_rot_pos(t_now)
			return _vec_arr(moon_pos - Vector3(PhysicsScript.R_MOON_KM, 0.0, 0.0))
		"cislunar:lunar_leo":
			return _nav_eci_pos(PhysicsScript.llo_state(t_now), t_now)
		_:
			return []

func _nav_lagrange_pos(lid: String) -> Array:
	var st: Dictionary = PhysicsScript.lagrange_state(lid)
	if st.is_empty():
		return []
	var erot: Dictionary = PhysicsScript.bary_rot_to_earth_rot(st)
	return _vec_arr(PhysicsScript.to_vec3(erot.get("r", Vector3.ZERO), Vector3.ZERO))

func _nav_eci_pos(eci_state: Dictionary, t_now: float) -> Array:
	var erot := _physics_eci_to_earth_rot(PhysicsScript.as_state(eci_state), t_now)
	return _vec_arr(PhysicsScript.to_vec3(erot.get("r", Vector3.ZERO), Vector3.ZERO))

# ═══════════════════════════════════════════════════════════════════
# R6-AUTH-1：authoritative 物理适配层（只读；显示层尚未切换）
#   - V17_PHYSICS=shadow|authoritative|off；authoritative 时 bridge 仍不写 V15 tracks；
#   - physics_authoritative_view()：own/flagship/targets 的 ECI + 相对 board_r/board_v、
#     range/bearing/elevation、age、warnings（地心旋转系 → 局部板）；
#   - physics_adapter_compare(v15_own, v15_tracks)：物理相对状态 vs V15 board 差异（只读）；
#   - authoritative 初始化失败回落 shadow，不崩溃；display_switched 恒 false。
# ═══════════════════════════════════════════════════════════════════

func physics_authoritative_view() -> Dictionary:
	return physics_authoritative_view_data

## 物理相对状态 vs V15 board 差异（只读；用于切换阈值评估；不写 V15 tracks/HUD）。
## v15_own：state.own_at() 返回 {r,v}；v15_tracks：[{track_id/entity_id, board_r, board_v}]
func physics_adapter_compare(v15_own, v15_tracks: Array) -> Dictionary:
	var view := physics_authoritative_view()
	var out := {
		"ok": false,
		"schema": "v17_physics_adapter_compare.v1",
		"mode": physics_mode,
		"requested_mode": physics_requested_mode,
		"authoritative_ready": bool(view.get("ready", false)),
		"display_switched": false,
		"source": "adapter_compare（只读；不写 V15 tracks/HUD）",
		"frame_mismatch_note": "V15 board=L1 局部差；physics board=地心旋转系差（未切换）；range 直接可比，bearing/位置误差含坐标系旋转差异，仅作阈值参考。",
		"thresholds": COMPARE_THRESHOLDS.duplicate(true),
		"own": {},
		"tracks": [],
		"summary": {},
		"warnings": [],
	}
	if not bool(view.get("ready", false)):
		out["reason"] = String(view.get("error", "authoritative 未就绪"))
		physics_adapter_last = out.duplicate(true)
		return out
	var own_row: Dictionary = view.get("own", {})
	var v15_own_r := Vector3.ZERO
	if v15_own is Dictionary:
		v15_own_r = _variant_vec3((v15_own as Dictionary).get("r", null), Vector3.ZERO)
	out["own"] = {
		"physics_earth_rot_r": ((own_row.get("state_earth_rot", {}) as Dictionary).get("r", []) as Array).duplicate(),
		"v15_r": _vec_arr(v15_own_r),
		"note": "own 参考点：V15 own_at() vs physics earth_rot（坐标系未切换）",
	}
	var target_map := {}
	for raw in (view.get("targets", []) as Array):
		target_map[String((raw as Dictionary).get("entity_id", ""))] = raw
	var rows: Array = []
	var max_range_err := 0.0
	var max_bearing_err := 0.0
	var max_pos_err := 0.0
	var compared := 0
	for raw in v15_tracks:
		if not (raw is Dictionary):
			continue
		var t15: Dictionary = raw
		var eid := _v15_track_entity_id(t15)
		if eid == "" or not target_map.has(eid):
			continue
		var prow: Dictionary = target_map.get(eid, {})
		var v15_board := _variant_vec3(t15.get("board_r", t15.get("r", null)), Vector3.ZERO)
		var v15_board_v := _variant_vec3(t15.get("board_v", t15.get("v", null)), Vector3.ZERO)
		var v15_rng := v15_board.length()
		var v15_bearing := fposmod(rad_to_deg(atan2(v15_board.x, v15_board.y)), 360.0)
		var v15_horiz := sqrt(v15_board.x * v15_board.x + v15_board.y * v15_board.y)
		var v15_el := rad_to_deg(atan2(v15_board.z, maxf(v15_horiz, 1.0e-6)))
		var phys_board := _variant_vec3(prow.get("board_r", null), Vector3.ZERO)
		var phys_rng := float(prow.get("range_km", 0.0))
		var phys_bearing := float(prow.get("bearing_deg", 0.0))
		var range_err := absf(phys_rng - v15_rng)
		var bearing_err := absf(fposmod(phys_bearing - v15_bearing + 180.0, 360.0) - 180.0)
		var pos_err := (phys_board - v15_board).length()
		max_range_err = maxf(max_range_err, range_err)
		max_bearing_err = maxf(max_bearing_err, bearing_err)
		max_pos_err = maxf(max_pos_err, pos_err)
		compared += 1
		rows.append({
			"track_id": String(t15.get("id", t15.get("track_id", ""))),
			"entity_id": eid,
			"role": String(prow.get("role", "target")),
			"physics": {
				"range_km": phys_rng,
				"bearing_deg": phys_bearing,
				"elevation_deg": float(prow.get("elevation_deg", 0.0)),
				"board_r": _vec_arr(phys_board),
			},
			"v15": {
				"range_km": v15_rng,
				"bearing_deg": v15_bearing,
				"elevation_deg": v15_el,
				"board_r": _vec_arr(v15_board),
				"board_v": _vec_arr(v15_board_v),
			},
			"errors": {"range_km": range_err, "bearing_deg": bearing_err,
				"position_km": pos_err},
		})
	var th: Dictionary = COMPARE_THRESHOLDS
	out["tracks"] = rows
	out["summary"] = {
		"tracks_input": v15_tracks.size(),
		"compared": compared,
		"skipped": maxi(0, v15_tracks.size() - compared),
		"max_range_err_km": max_range_err,
		"max_bearing_err_deg": max_bearing_err,
		"max_position_err_km": max_pos_err,
		"within_threshold": bool(compared > 0
			and max_range_err <= float(th.get("range_km", 5.0))
			and max_bearing_err <= float(th.get("bearing_deg", 5.0))
			and max_pos_err <= float(th.get("position_km", 50.0))),
	}
	out["ok"] = compared > 0
	physics_adapter_last = out.duplicate(true)
	return out

func _refresh_authoritative_view() -> void:
	physics_authoritative_view_data = _build_authoritative_view()

func _build_authoritative_view() -> Dictionary:
	var out := {
		"schema": "v17_physics_authoritative.v1",
		"requested_mode": physics_requested_mode,
		"mode": physics_mode,
		"authoritative": physics_mode == "authoritative",
		"ready": bool(physics_mode == "authoritative" and physics_ready and physics != null),
		"display_switched": false,
		"display_note": "显示层尚未切换：V15 tracks/HUD/plot 仍用 V15 数据；本视图只读。",
		"fallback_reason": physics_fallback_reason,
		"source": "cr3bp_rk4_circular · 实体初始 V2 L1 局部近似/固定占位（非 JPL 星历）",
		"frame": {
			"inertial": "earth_eci",
			"rotating": "earth_rot",
			"board": "earth_rot 相对本舰（+x/+y 面内、+z 法向；bearing=atan2(x,y)、elevation=atan2(z,horiz)，与 V15 _derive 同式）",
		},
		"t": 0.0,
		"own": {},
		"flagship": {},
		"targets": [],
		"fixed": [],
		"stations": [],
		"flags": {},
		"warnings": physics_warnings.duplicate(),
		"error": "",
	}
	if physics == null or not physics_ready:
		out["error"] = "physics 未就绪（mode=%s requested=%s）" % [physics_mode, physics_requested_mode]
		out["flags"] = {"authoritative_ready": false, "display_switched": false,
			"fixed_ids": [], "fallback_reason": physics_fallback_reason}
		return out
	if physics_mode != "authoritative":
		out["error"] = "authoritative 未启用（mode=%s；shadow 只读）" % physics_mode
		out["flags"] = {"authoritative_ready": false, "display_switched": false,
			"fixed_ids": [], "fallback_reason": physics_fallback_reason}
		return out
	var rows := {}
	for raw in (physics_view_data.get("entities", []) as Array):
		var row: Dictionary = raw
		rows[String(row.get("id", ""))] = row
	var own_id := String(world.own_id)
	if not rows.has(own_id):
		out["error"] = "own 实体物理状态缺失：" + own_id
		return out
	var own_row: Dictionary = rows[own_id]
	out["t"] = float(physics.t)
	out["own"] = _auth_relative_row(own_row, own_row, own_id, "own")
	var flagship_id := _pick_flagship_id(own_id)
	if flagship_id != "" and rows.has(flagship_id):
		out["flagship"] = _auth_relative_row(rows[flagship_id], own_row, flagship_id, "flagship")
	var targets: Array = []
	var target_ids: Array = []
	for raw in world.entities:
		var e: V2Entity = raw
		if e.id == own_id or e.id == flagship_id:
			continue
		if e.kind != "ship":
			continue
		if not rows.has(e.id):
			continue
		var trow := _auth_relative_row(rows[e.id], own_row, e.id, "target")
		trow["side"] = String(e.side)
		trow["name"] = e.display_name()
		targets.append(trow)
		target_ids.append(e.id)
	out["targets"] = targets
	# R6-FIXED-CORE-1：固定站体（chronos_station / tank_farm 等）的物理相对状态
	var fixed_rows: Array = []
	var fixed_ids: Array = []
	for raw in world.entities:
		var fe: V2Entity = raw
		if fe.id == own_id or fe.id == flagship_id:
			continue
		if not fe.is_fixed():
			continue
		if not rows.has(fe.id):
			continue
		var frow := _auth_relative_row(rows[fe.id], own_row, fe.id, "fixed")
		frow["side"] = String(fe.side)
		frow["name"] = fe.display_name()
		frow["entity_kind"] = String(fe.kind)
		frow["fixed"] = true
		fixed_rows.append(frow)
		fixed_ids.append(fe.id)
	out["fixed"] = fixed_rows
	out["stations"] = fixed_rows.duplicate(true)   # 兼容别名（当前 fixed 均为站体/储罐）
	out["flags"] = {
		"authoritative_ready": true,
		"display_switched": false,
		"own_id": own_id,
		"flagship_id": flagship_id,
		"target_ids": target_ids,
		"fixed_ids": fixed_ids,
		"fallback_reason": physics_fallback_reason,
	}
	return out

func _auth_relative_row(row: Dictionary, own_row: Dictionary, entity_id: String, role: String) -> Dictionary:
	var erot: Dictionary = row.get("state_earth_rot", {}) if row.get("state_earth_rot") is Dictionary else {}
	var eci: Dictionary = row.get("state_earth_eci", {}) if row.get("state_earth_eci") is Dictionary else {}
	var orot: Dictionary = own_row.get("state_earth_rot", {}) if own_row.get("state_earth_rot") is Dictionary else {}
	var tr := _variant_vec3(erot.get("r", null), Vector3.ZERO)
	var tv := _variant_vec3(erot.get("v", null), Vector3.ZERO)
	var orr := _variant_vec3(orot.get("r", null), Vector3.ZERO)
	var ov := _variant_vec3(orot.get("v", null), Vector3.ZERO)
	var metrics := _board_metrics(tr - orr, tv - ov)
	var out := {
		"entity_id": entity_id,
		"role": role,
		"source": String(physics_entity_sources.get(entity_id, "V2 场景实体（非星历）")),
		"age_s": 0.0,
		"age_note": "physics 当前步（shadow/authoritative 同步时间）",
		"state_earth_eci": eci.duplicate(true),
		"state_earth_rot": erot.duplicate(true),
		"finite": bool(row.get("finite", false)),
		"earth_distance_km": float(row.get("earth_distance_km", 0.0)),
		"moon_distance_km": float(row.get("moon_distance_km", 0.0)),
		"jacobi_drift": float(row.get("jacobi_drift", 0.0)),
	}
	for k in metrics.keys():
		out[k] = metrics[k]
	return out

func _board_metrics(dr: Vector3, dv: Vector3) -> Dictionary:
	var rng := dr.length()
	var range_rate := 0.0
	if rng > 1.0e-9:
		range_rate = dr.dot(dv) / rng
	var horiz := sqrt(dr.x * dr.x + dr.y * dr.y)
	return {
		"board_r": _vec_arr(dr),
		"board_v": _vec_arr(dv),
		"range_km": rng,
		"range_rate_kmps": range_rate,
		"closing_kmps": -range_rate,
		"bearing_deg": fposmod(rad_to_deg(atan2(dr.x, dr.y)), 360.0),
		"elevation_deg": rad_to_deg(atan2(dr.z, maxf(horiz, 1.0e-6))),
	}

func _pick_flagship_id(own_id: String) -> String:
	if own_id != "apsis" and world != null and world.by_id.has("apsis"):
		return "apsis"
	for raw in world.entities:
		var e: V2Entity = raw
		if e.id != own_id and e.kind == "ship" and e.side == "friend":
			return e.id
	return ""

func _v15_track_entity_id(track: Dictionary) -> String:
	var direct := String(track.get("entity_id", ""))
	if direct != "":
		return direct
	var batch := String(track.get("batch", ""))
	var tid := String(track.get("id", track.get("track_id", "")))
	if batch != "" or tid != "":
		for raw in contacts:
			var c: Dictionary = raw
			if (batch != "" and String(c.get("batch", "")) == batch) \
					or (tid != "" and String(c.get("track_id", "")) == tid):
				return String(c.get("entity_id", ""))
	if batch != "" and world != null:
		for raw in world.entities:
			var e: V2Entity = raw
			if String(e.batch) == batch:
				return e.id
	return ""

func _variant_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if value is Dictionary:
		var d: Dictionary = value
		for k in ["r", "pos", "position", "board_r"]:
			if d.has(k):
				return _variant_vec3(d.get(k), fallback)
	return fallback

# ═══════════════════════════════════════════════════════════════════
# R5-SENSOR-BRIDGE-1：传感器 shadow 接入（只读 advisory；不写 TrackTable/V15）
#   - V2SensorAuthority 从 world/entity snapshot 喂 step；V17_SENSOR_AUTHORITY=shadow|off；
#     authoritative 不实现（传入也只 shadow 并记录 reason，不伪称）；
#   - sensor_shadow_view()/sensor_shadow_summary()/sensor_compare(legacy_tracks)；
#   - dt=0（暂停）不推进；初始化失败不阻塞 bridge；不接 HUD/plot。
# ═══════════════════════════════════════════════════════════════════

func _init_sensor_shadow() -> void:
	sensor_shadow = null
	sensor_shadow_ready = false
	sensor_shadow_view_data = {}
	sensor_shadow_summary_data = {}
	sensor_shadow_warnings.clear()
	sensor_compare_last = {}
	sensor_shadow_fallback_reason = ""
	var env := OS.get_environment("V17_SENSOR_AUTHORITY").to_lower().strip_edges()
	if env == "off":
		sensor_authority_requested_mode = "off"
		sensor_authority_mode = "off"
		sensor_shadow_mode = "off"
		return
	if env == "authoritative" or env == "auth" or env == "v2":
		sensor_authority_requested_mode = "authoritative"
		sensor_authority_mode = "authoritative"
		sensor_shadow_mode = "shadow"
		sensor_shadow_fallback_reason = ""
		_note_sensor_warning("authoritative 显示层：state 只映射显示字段（level/identity/sources）；bridge 不写 TrackTable/V15")
	else:
		sensor_authority_requested_mode = "shadow"
		sensor_authority_mode = "shadow"
		sensor_shadow_mode = "shadow"
	sensor_shadow = SensorAuthorityScript.new()
	var cfg := _sensor_shadow_config()
	var ok: bool = sensor_shadow.setup(cfg)
	if not ok:
		sensor_shadow_ready = false
		_note_sensor_warning("sensor shadow 初始化失败：" + str(sensor_shadow.errors))
		sensor_shadow = null
		return
	sensor_shadow_ready = bool(sensor_shadow.ready)
	# 首帧 priming：dt=0 初始化一次扫描/观测（不推进时间；之后运行时 dt=0 仍不推进）
	if sensor_shadow_ready:
		sensor_shadow.step(0.0, _build_sensor_snapshot())
	_refresh_sensor_shadow()

## world/entity snapshot（V2 sensor world_snapshot 契约；只读；帧 = V15/V2 L1 局部板）。
func _build_sensor_snapshot() -> Dictionary:
	var own_id := String(world.own_id)
	var observer := SensorAuthorityScript.default_observer(own_id)
	observer["pos_km"] = [0.0, 0.0, 0.0]
	observer["vel_kmps"] = [0.0, 0.0, 0.0]
	observer["mast_deployed"] = true
	observer["emcon"] = false
	if world.has_method("vm_damage_full"):
		var full: Dictionary = world.vm_damage_full()
		var eff: Dictionary = (full.get("effects", {}) as Dictionary) if full.get("effects") is Dictionary else {}
		var sens: Dictionary = (eff.get("sensors", {}) as Dictionary) if eff.get("sensors") is Dictionary else {}
		observer["damage"] = {"sensors": float(sens.get("mult", 1.0)), "comms": 1.0, "propulsion": 1.0}
	var targets: Array = []
	for raw in world.vm_contacts():
		var c: Dictionary = raw
		if bool(c.get("bearing_only", false)):
			continue
		if String(c.get("entity_id", "")) == "" or String(c.get("entity_id", "")) == own_id:
			continue
		var rng := float(c.get("range_km", 0.0))
		if rng <= 0.0:
			continue
		targets.append(SensorAuthorityScript.make_target(String(c.get("track_id", c.get("batch", ""))),
			rng, float(c.get("bearing_deg", 0.0)), {
				"entity_id": String(c.get("entity_id", "")),
				"batch": String(c.get("batch", "")),
				"name": String(c.get("name", "")),
				"faction": String(c.get("faction", "unknown")),
				"transponder": "off",
			}))
	return SensorAuthorityScript.make_snapshot(float(world.t), observer, targets,
		{"sun_illum": 1.0, "jamming": 0.0, "shadow": false, "los": true})

func _sensor_shadow_config() -> Dictionary:
	var own_id := String(world.own_id)
	return {
		"observer_id": own_id,
		"mounts": SensorAuthorityScript.default_mounts(own_id),
		"snapshot": _build_sensor_snapshot(),
		"level_tolerance": 0,
		"range_tolerance_km": 5.0,
	}

func _refresh_sensor_shadow() -> void:
	if sensor_shadow_mode != "shadow" or not sensor_shadow_ready or sensor_shadow == null:
		sensor_shadow_view_data = {}
		sensor_shadow_summary_data = {}
		return
	sensor_shadow_view_data = sensor_shadow.vm_sensor()
	sensor_shadow_summary_data = sensor_shadow.summary()
	for raw in sensor_shadow.warnings:
		_note_sensor_warning(String(raw))

func _step_sensor_shadow(dt: float) -> void:
	if sensor_shadow_mode != "shadow" or not sensor_shadow_ready or sensor_shadow == null:
		return
	if dt <= 0.0:
		return
	sensor_shadow.step(dt, _build_sensor_snapshot())
	_refresh_sensor_shadow()

func _note_sensor_warning(text: String) -> void:
	if text == "" or sensor_shadow_warnings.has(text):
		return
	sensor_shadow_warnings.append(text)
	while sensor_shadow_warnings.size() > MAX_SENSOR_WARNINGS:
		sensor_shadow_warnings.pop_front()

## 传感器 shadow 只读 vm（advisory contacts/channels/radar sphere/optical/warnings）。
func sensor_shadow_view() -> Dictionary:
	return sensor_shadow_view_data

func sensor_shadow_summary() -> Dictionary:
	return sensor_shadow_summary_data

## 只读 compare：advisory shadow vs legacy/state tracks（模型 compare；不写任何轨道）。
func sensor_compare(legacy_tracks) -> Dictionary:
	if sensor_shadow_mode != "shadow" or not sensor_shadow_ready or sensor_shadow == null:
		var fail := {"ok": false, "reason": "sensor shadow 未就绪",
			"mode": sensor_shadow_mode, "requested_mode": sensor_authority_requested_mode,
			"authoritative": false, "read_only": true,
			"fallback_reason": sensor_shadow_fallback_reason}
		sensor_compare_last = fail.duplicate(true)
		return fail
	var r = sensor_shadow.compare(legacy_tracks)
	sensor_compare_last = (r as Dictionary).duplicate(true) if r is Dictionary else {}
	return r if r is Dictionary else {}

## R5-AUTHORITY-DISPLAY-1：authoritative_display 只读摘要（显示层权威；bridge 不写 TrackTable）。
func sensor_authority_display() -> Dictionary:
	var active := sensor_authority_mode == "authoritative" and sensor_shadow_ready
	var advisories: Array = sensor_shadow_view_data.get("advisory_contacts", []) if not sensor_shadow_view_data.is_empty() else []
	return {
		"schema": "v17_sensor_authority_display.v1",
		"mode": sensor_authority_mode,
		"requested_mode": sensor_authority_requested_mode,
		"ready": bool(sensor_shadow_ready),
		"active": active,
		"display_only": true,
		"authoritative_display_only": true,
		"writes_track_table": false,
		"writes_v15_physics": false,
		"writes_v15_display_fields": active,
		"display_fields": ["level", "identity", "sources", "sensor"],
		"untouched_fields": ["r", "v", "own", "off", "task", "damage", "threat", "side", "role", "action"],
		"advisory_count": advisories.size(),
		"note": "显示层权威：state 只映射 V15 显示字段（level/identity/sources）；不改 r/v/任务/损管/威胁；bridge 不写 TrackTable；默认 shadow，需 V17_SENSOR_AUTHORITY=authoritative 显式启用。",
	}

# ═══════════════════════════════════════════════════════════════════
# R5-INFO-BRIDGE-1：信息作战 shadow 接入（IFF/ELINT/COMINT/EW；只读 advisory）
#   - V2InformationWarfare 从 world/entity 输入（observer/mounts/emitters/contacts）喂 step；
#     V17_INFO_WARFARE=shadow|off；authoritative 不实现（只记录 reason，不伪称）；
#   - 暴露计数/最近事件/告警；不写 TrackTable/V15；不接 HUD/plot。
# ═══════════════════════════════════════════════════════════════════

func _init_info_warfare() -> void:
	info_warfare = null
	info_warfare_ready = false
	info_warfare_view_data = {}
	info_warfare_summary_data = {}
	info_warfare_warnings.clear()
	info_warfare_fallback_reason = ""
	info_warfare_recent_events = []
	info_warfare_recent_alerts = []
	var env := OS.get_environment("V17_INFO_WARFARE").to_lower().strip_edges()
	if env == "off":
		info_warfare_requested_mode = "off"
		info_warfare_mode = "off"
		return
	if env == "authoritative" or env == "auth" or env == "v2":
		info_warfare_requested_mode = "authoritative"
		info_warfare_fallback_reason = "authoritative 未实现：保持 shadow advisory（不伪称 authoritative）"
	else:
		info_warfare_requested_mode = "shadow"
	info_warfare_mode = "shadow"
	if info_warfare_fallback_reason != "":
		_note_info_warning(info_warfare_fallback_reason)
	info_warfare = InformationWarfareScript.new()
	var ok: bool = info_warfare.setup(_info_warfare_config())
	if not ok:
		info_warfare_ready = false
		_note_info_warning("info warfare shadow 初始化失败：" + str(info_warfare.errors))
		info_warfare = null
		_refresh_info_warfare()
		return
	info_warfare_ready = bool(info_warfare.ready)
	_refresh_info_warfare()

## 从 V2 world/entity 构造 IW 输入（observer/targets emitters/contacts/advisory）。
func _info_warfare_config() -> Dictionary:
	var own_id := String(world.own_id)
	var observer := InformationWarfareScript.default_observer(own_id)
	observer["pos_km"] = [0.0, 0.0, 0.0]
	observer["vel_kmps"] = [0.0, 0.0, 0.0]
	observer["emcon"] = false
	if world.has_method("vm_damage_full"):
		var full: Dictionary = world.vm_damage_full()
		var eff: Dictionary = (full.get("effects", {}) as Dictionary) if full.get("effects") is Dictionary else {}
		var sens: Dictionary = (eff.get("sensors", {}) as Dictionary) if eff.get("sensors") is Dictionary else {}
		var comms: Dictionary = (eff.get("comms", {}) as Dictionary) if eff.get("comms") is Dictionary else {}
		observer["damage"] = {"sensors": float(sens.get("mult", 1.0)),
			"comms": float(comms.get("mult", 1.0)), "propulsion": 1.0}
	var codes := {"1": "M1", "2": "M2", "3/A": "CMP1234", "C": "25000", "S": "A1B2C3", "5": "FRIEND5"}
	var targets: Array = []
	for raw in world.vm_contacts():
		var c: Dictionary = raw
		if bool(c.get("bearing_only", false)):
			continue
		var eid := String(c.get("entity_id", ""))
		if eid == "" or eid == own_id:
			continue
		var rng := float(c.get("range_km", 0.0))
		if rng <= 0.0:
			continue
		var friendly := String(c.get("side", "")) == "friend"
		var emissions := [{
			"model": "YW-R9", "type": "radar", "active": true, "silent": false,
			"lpi": false, "spoof": false, "frequency_mhz": 9500.0, "power_dbm": 90.0,
			"gain_tx_dbi": 30.0, "prf_hz": 1200.0, "pulse_width_us": 1.2, "scan_period_s": 6.0,
		}]
		var comms := [{"from": eid, "to": own_id, "mode": "radio", "text": "shadow-link",
			"encrypted": false, "frequency_mhz": 300.0}]
		targets.append(InformationWarfareScript.make_target(
			String(c.get("track_id", c.get("batch", ""))), rng,
			float(c.get("bearing_deg", 0.0)), {
				"entity_id": eid,
				"batch": String(c.get("batch", "")),
				"name": String(c.get("name", "")),
				"transponder": "ok" if friendly else "off",
				"registered": friendly,
				"registry_match": friendly,
				"iff_codes": codes if friendly else {},
				"emissions": emissions,
				"comms": comms,
			}))
	var advisory: Array = []
	if sensor_shadow_ready and not sensor_shadow_view_data.is_empty():
		advisory = (sensor_shadow_view_data.get("advisory_contacts", []) as Array).duplicate(true)
	return {
		"observer_id": own_id,
		"observer": observer,
		"targets": targets,
		"stations": [
			{"id": "%s-ELINT-A" % own_id, "model": "ELINT", "pos_km": [0.0, 0.0, 0.0],
				"enabled": true, "sigma_bearing_deg": 1.0},
			{"id": "%s-ELINT-B" % own_id, "model": "ELINT", "pos_km": [5000.0, 0.0, 0.0],
				"enabled": true, "sigma_bearing_deg": 1.0},
		],
		"advisory_contacts": advisory,
	}

func _step_info_warfare(dt: float) -> void:
	if info_warfare_mode != "shadow" or not info_warfare_ready or info_warfare == null:
		return
	if dt <= 0.0:
		return
	info_warfare.step(dt)
	_refresh_info_warfare()

func _refresh_info_warfare() -> void:
	if info_warfare_mode != "shadow" or not info_warfare_ready or info_warfare == null:
		info_warfare_view_data = {}
		info_warfare_summary_data = {}
		info_warfare_recent_events = []
		info_warfare_recent_alerts = []
		return
	info_warfare_view_data = info_warfare.vm_information_warfare()
	info_warfare_summary_data = info_warfare.summary()
	info_warfare_recent_events = _tail(info_warfare_view_data.get("events", []), INFO_RECENT_MAX)
	info_warfare_recent_alerts = _tail(info_warfare_view_data.get("alerts", []), INFO_RECENT_MAX)
	for raw in info_warfare_view_data.get("warnings", []):
		_note_info_warning(String(raw))

func _tail(src: Variant, n: int) -> Array:
	var out: Array = []
	if not (src is Array):
		return out
	var arr: Array = src
	var start := maxi(0, arr.size() - n)
	for i in range(start, arr.size()):
		out.append(arr[i])
	return out

func _note_info_warning(text: String) -> void:
	if text == "" or info_warfare_warnings.has(text):
		return
	info_warfare_warnings.append(text)
	while info_warfare_warnings.size() > MAX_INFO_WARNINGS:
		info_warfare_warnings.pop_front()

## 信息作战 shadow 只读 vm（IFF/ELINT/COMINT/EW/effects/events/alerts/advisory）。
func info_warfare_view() -> Dictionary:
	return info_warfare_view_data

func info_warfare_summary() -> Dictionary:
	return info_warfare_summary_data

## 最近事件/告警（只读；最多 8 条；完整列表见 view.events/alerts）。
func info_warfare_events() -> Array:
	return info_warfare_recent_events

func info_warfare_alerts() -> Array:
	return info_warfare_recent_alerts

# ═══════════════════════════════════════════════════════════════════
# R5-OPT-DOCK-BRIDGE-1：光学/IR 通道 + 对接控制器（只读 VM / 显式 API）
#   - V2OpticalIRChannel（VIS/IR）与 V2DockingController（默认端口样例）；
#     V17_OPTICAL_IR=on|off、V17_DOCKING=on|off（默认 on；off 时 view 为空）；
#   - 不自动写 world/TrackTable/V15；光学/对接均需显式 API（point/start/step、update/…）；
#   - 失败不阻塞 bridge；不接 HUD/plot。
# ═══════════════════════════════════════════════════════════════════

func _init_optical_docking() -> void:
	optical_ir = null
	optical_ir_ready = false
	optical_ir_view_data = {}
	optical_ir_summary_data = {}
	optical_ir_warnings.clear()
	docking = null
	docking_ready = false
	docking_view_data = {}
	docking_update_last = {}
	optical_docking_warnings.clear()
	optical_ir_auto_suppressed = false
	docking_auto_suppressed = false
	optical_ir_auto_step_count = 0
	docking_auto_step_count = 0
	var oenv := OS.get_environment("V17_OPTICAL_IR").to_lower().strip_edges()
	optical_ir_enabled = not (oenv == "off" or oenv == "0")
	optical_ir_auto_enabled = optical_ir_enabled and (oenv == "" or oenv == "auto" or oenv == "1")
	if optical_ir_enabled:
		optical_ir = OpticalIRScript.new()
		var ok: bool = optical_ir.setup({})
		optical_ir_ready = bool(ok and optical_ir.enabled)
		if not optical_ir_ready:
			_note_opt_warning("optical_ir 初始化失败：" + str(optical_ir.errors))
			optical_ir = null
	var denv := OS.get_environment("V17_DOCKING").to_lower().strip_edges()
	docking_enabled = not (denv == "off" or denv == "0")
	docking_auto_enabled = docking_enabled and (denv == "" or denv == "auto" or denv == "1")
	if docking_enabled:
		docking = DockingScript.new()
		var dok: bool = docking.setup(DockingScript.default_ports(), {})
		docking_ready = bool(dok and docking.errors.is_empty())
		if not docking_ready:
			_note_opt_warning("docking 初始化失败：" + str(docking.errors))
			docking = null
	_refresh_optical_docking()

func _refresh_optical_docking() -> void:
	if optical_ir_enabled and optical_ir_ready and optical_ir != null:
		optical_ir_view_data = optical_ir.vm_optical_ir()
		optical_ir_summary_data = optical_ir.summary()
		for raw in optical_ir.warnings:
			_note_opt_warning(String(raw))
	else:
		optical_ir_view_data = {}
		optical_ir_summary_data = {}
	if docking_enabled and docking_ready and docking != null:
		docking_view_data = docking.vm()
	else:
		docking_view_data = {}

func _note_opt_warning(text: String) -> void:
	if text == "" or optical_docking_warnings.has(text):
		return
	optical_docking_warnings.append(text)
	while optical_docking_warnings.size() > MAX_OPT_WARNINGS:
		optical_docking_warnings.pop_front()

## 光学/IR 只读 VM（sensors/channels/by_status/events/warnings/summary/writes=false）。
func optical_ir_view() -> Dictionary:
	return optical_ir_view_data

func optical_ir_summary() -> Dictionary:
	return optical_ir_summary_data

## 光学 snapshot：observer=本舰 L1 板原点；targets 由 V2 contacts 的 range/bearing/alt 构造。
func optical_ir_snapshot() -> Dictionary:
	var own_id := String(world.own_id)
	var observer := OpticalIRScript.default_observer(own_id)
	observer["pos_km"] = [0.0, 0.0, 0.0]
	observer["vel_kmps"] = [0.0, 0.0, 0.0]
	var targets: Array = []
	for raw in world.vm_contacts():
		var c: Dictionary = raw
		if bool(c.get("bearing_only", false)):
			continue
		var eid := String(c.get("entity_id", ""))
		if eid == "" or eid == own_id:
			continue
		var rng := float(c.get("range_km", 0.0))
		if rng <= 0.0:
			continue
		var br := deg_to_rad(float(c.get("bearing_deg", 0.0)))
		var pos := [sin(br) * rng, cos(br) * rng, float(c.get("alt", 0.0))]
		targets.append(OpticalIRScript.make_target(
			String(c.get("track_id", c.get("batch", ""))), pos, {
				"entity_id": eid,
				"batch": String(c.get("batch", "")),
				"name": String(c.get("name", "")),
				"size_m": maxf(1.0, float(c.get("size_km", 0.05)) * 1000.0),
				"temp_k": 300.0, "area_m2": 1000.0, "illum": 1.0,
			}))
	return OpticalIRScript.make_snapshot(float(world.t), observer, targets,
		{"sun_illum": 1.0, "shadow": false, "los": true})

## 显式：两通道对准目标（aim_at；不 step/不写 V15）。
func optical_ir_point(target_id: String) -> Dictionary:
	if not optical_ir_ready or optical_ir == null:
		return {"ok": false, "reason": "optical_ir_not_ready", "target_id": target_id}
	var out := {"ok": true, "target_id": target_id, "sensors": {}}
	for kind in OpticalIRScript.KINDS:
		if optical_ir.has_sensor(kind):
			(out["sensors"] as Dictionary)[kind] = optical_ir.aim_at(kind, target_id)
	_refresh_optical_docking()
	return out

## 显式：启动 VIS/IR 通道（kind=optical|ir）。
func optical_ir_start(kind: String, target_id: String, opts := {}) -> Dictionary:
	if not optical_ir_ready or optical_ir == null:
		return {"ok": false, "reason": "optical_ir_not_ready"}
	optical_ir_auto_suppressed = false
	optical_ir_auto_target = target_id
	var res: Dictionary = optical_ir.start_channel(kind, target_id, opts)
	_refresh_optical_docking()
	return res

## 显式：推进光学通道（用 bridge 构造的 snapshot；不写 V15）。
func optical_ir_step(dt: float) -> Dictionary:
	if not optical_ir_ready or optical_ir == null:
		return {"ok": false, "reason": "optical_ir_not_ready"}
	var out: Dictionary = optical_ir.step(maxf(0.0, dt), optical_ir_snapshot())
	_refresh_optical_docking()
	return out

func optical_ir_stop(kind: String, target_id := "") -> void:
	if not optical_ir_ready or optical_ir == null:
		return
	optical_ir.stop_channel(kind, target_id)
	optical_ir_auto_suppressed = true
	_refresh_optical_docking()

## 对接只读 VM（ports/target/last/events/config/writes=false）。
func docking_view() -> Dictionary:
	return docking_view_data

## 显式：选择目标端口（默认端口样例；不落实体）。
func docking_select_port(port_id: String) -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	docking_auto_suppressed = false
	docking_auto_target = port_id
	var res: Dictionary = docking.select_target_port(port_id)
	_refresh_optical_docking()
	return res

## 显式：相对状态/姿态驱动对接（rel={dr,dv} 或 [x,y,z,vx,vy,vz]；attitude={chaser_port_axis}）。
func docking_update(rel, attitude := {}, dt := 0.0) -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	docking_auto_suppressed = true
	var res: Dictionary = docking.update(rel, attitude, maxf(0.0, float(dt)))
	docking_update_last = res.duplicate(true)
	_refresh_optical_docking()
	return res

func docking_hold(reason := "commander_hold") -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	docking_auto_suppressed = true
	var res: Dictionary = docking.hold(reason)
	_refresh_optical_docking()
	return res

func docking_resume() -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	var res: Dictionary = docking.resume()
	_refresh_optical_docking()
	return res

func docking_abort(reason := "commander_abort") -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	docking_auto_suppressed = true
	var res: Dictionary = docking.abort(reason)
	_refresh_optical_docking()
	return res

func docking_reset() -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	docking.reset()
	docking_auto_suppressed = false
	_refresh_optical_docking()
	return {"ok": true, "state": String(docking.state)}

## R5-AUTHORITY-DISPLAY-1：UNDOCK 包装（调用模型 undock；刷新 view；无实例 ok=false）。
func docking_undock(reason := "commander_undock") -> Dictionary:
	if not docking_ready or docking == null:
		return {"ok": false, "reason": "docking_not_ready"}
	var res: Dictionary = docking.undock(reason)
	docking_auto_suppressed = true
	docking_update_last = res.duplicate(true) if res is Dictionary else {}
	_refresh_optical_docking()
	return res

# ═══════════════════════════════════════════════════════════════════
# R5-AUTO-SENSOR-1：自动光学/对接数据（HUD 打开即有真实 VM）
#   - 默认 auto（V17_OPTICAL_IR/V17_DOCKING 未设或 =auto）；=on 显式手动；=off 关闭；
#   - 光学：sync 自动选目标（bridge actions_target/首个接触）→ start VIS/IR + aim + step；
#     手动 start/stop 可覆盖（stop 抑制 auto，start/resume 恢复）；
#   - 对接：sync 从 V2 world 实体的 L1 相对状态生成 rel + chaser 端口轴 → update(dt)；
#     不落实体/不执行推力/不写 V15；手动 update/hold/abort 可抑制 auto。
# ═══════════════════════════════════════════════════════════════════

func _auto_optical_ir(dt: float) -> void:
	if not optical_ir_enabled or not optical_ir_auto_enabled:
		return
	if not optical_ir_ready or optical_ir == null:
		return
	if optical_ir_auto_suppressed:
		return
	var target := _auto_optical_target()
	if target == "":
		return
	optical_ir_auto_target = target
	if optical_ir.channels.is_empty():
		for kind in OpticalIRScript.KINDS:
			if optical_ir.has_sensor(kind):
				optical_ir.start_channel(kind, target)
	for kind in OpticalIRScript.KINDS:
		if optical_ir.has_sensor(kind):
			optical_ir.aim_at(kind, target)
	optical_ir.step(maxf(0.0, dt), optical_ir_snapshot())
	optical_ir_auto_step_count += 1
	for raw in optical_ir.warnings:
		_note_opt_warning(String(raw))
	_refresh_optical_docking()

func _auto_optical_target() -> String:
	if actions_target != "":
		for raw in contacts:
			var c: Dictionary = raw
			if String(c.get("track_id", "")) == actions_target \
					or String(c.get("batch", "")) == actions_target:
				return String(c.get("track_id", c.get("batch", actions_target)))
		return actions_target
	var own_id := String(world.own_id)
	for raw in contacts:
		var c2: Dictionary = raw
		if bool(c2.get("bearing_only", false)):
			continue
		if String(c2.get("entity_id", "")) == "" or String(c2.get("entity_id", "")) == own_id:
			continue
		if float(c2.get("range_km", 0.0)) <= 0.0:
			continue
		if int(c2.get("level", 0)) < 1:
			continue
		return String(c2.get("track_id", c2.get("batch", "")))
	return ""

func _auto_docking(dt: float) -> void:
	if not docking_enabled or not docking_auto_enabled:
		return
	if not docking_ready or docking == null:
		return
	if docking_auto_suppressed:
		return
	if docking.target_port_id == "" and docking_auto_target != "":
		docking.select_target_port(docking_auto_target)
	if docking.target_port().is_empty():
		return
	var rel := _auto_docking_rel()
	if rel.is_empty():
		return
	var res: Dictionary = docking.update(rel.get("rel", {}), rel.get("attitude", {}),
		maxf(0.0, dt))
	docking_update_last = res.duplicate(true)
	docking_auto_step_count += 1
	for w in res.get("warnings", []):
		_note_opt_warning(String(w))
	_refresh_optical_docking()

## 从 V2 world 实体 L1 相对状态生成对接 rel + chaser 端口轴（不落实体/不执行推力）。
func _auto_docking_rel() -> Dictionary:
	if docking == null:
		return {}
	var port: Dictionary = docking.target_port()
	var owner_id := String(port.get("owner_id", ""))
	var own_id := String(world.own_id)
	if owner_id == "" or own_id == "":
		return {}
	var own_ent = world.by_id.get(own_id, null) if world != null else null
	var tgt_ent = world.by_id.get(owner_id, null) if world != null else null
	if own_ent == null or tgt_ent == null:
		return {}
	var own_rv := _entity_l1_rv(own_ent)
	var tgt_rv := _entity_l1_rv(tgt_ent)
	if own_rv.is_empty() or tgt_rv.is_empty():
		return {}
	var dr: Vector3 = tgt_rv["r"] - own_rv["r"]
	var dv: Vector3 = tgt_rv["v"] - own_rv["v"]
	var attitude := {}
	if dr.length() > 1.0e-9:
		var axis := -dr.normalized()
		attitude = {"chaser_port_axis": [axis.x, axis.y, axis.z]}
	return {
		"rel": {"dr": [dr.x, dr.y, dr.z], "dv": [dv.x, dv.y, dv.z]},
		"attitude": attitude,
	}

func _entity_l1_rv(e) -> Dictionary:
	if e == null:
		return {}
	var orbit: Dictionary = e.orbit if e.orbit is Dictionary else {}
	var r_raw = orbit.get("r", null)
	var v_raw = orbit.get("v", null)
	var r := _variant_vec3(r_raw, Vector3.ZERO) if r_raw != null else Vector3.ZERO
	var v := _variant_vec3(v_raw, Vector3.ZERO) if v_raw != null else Vector3.ZERO
	return {"r": r, "v": v}

## 自动开关（运行时覆盖；off/on 由 _init 环境决定，auto 默认）。
func set_optical_ir_auto(on: bool) -> void:
	optical_ir_auto_enabled = on
	if on:
		optical_ir_auto_suppressed = false

func set_docking_auto(on: bool) -> void:
	docking_auto_enabled = on
	if on:
		docking_auto_suppressed = false
