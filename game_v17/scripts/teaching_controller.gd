extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 阶段2-TEACHING-1：07 教学目标手动控制器（新文件；不接 HUD/state/bridge）
#
# - 读取 framework/content/teaching_l4_l1.json（4 goals / 20 steps）；
# - 手动教学状态机：note(action, target, extra) 按 player_action/trigger_condition 匹配；
#   仅玩家动作触发；同一动作 once；失败动作不触发；允许乱序补触发；
# - manual_only=true / auto_complete=false：tick(t) 只记时间，不自动推进任何步骤；
# - vm()/to_json() 只读：goals/steps/progress/current/hints/last_event/completed/skipped/JSON；
# - 分支裁决（G4 S2–S5）为互斥选择：选择一个后其余未选分支标记 skipped（exclusive_decision）；
# - 不实现 UI/文本渲染；不写 V15/bridge。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_PATH := "res://framework/content/teaching_l4_l1.json"
const SCHEMA := "v17_teaching_controller.v1"
const STATUS_PENDING := "pending"
const STATUS_COMPLETED := "completed"
const STATUS_SKIPPED := "skipped"

var source_path := DEFAULT_PATH
var source_data: Dictionary = {}
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []

var scenario_id := ""
var story_file := ""
var manual_only := true
var auto_complete := false
var status_vocabulary: Dictionary = {}
var goals: Array = []
var steps: Array = []
var step_by_id: Dictionary = {}
var step_status: Dictionary = {}
var step_event_log: Dictionary = {}
var goal_status: Dictionary = {}
var t_s := 0.0
var events: Array = []
var last_event: Dictionary = {}
var _seen_actions: Dictionary = {}
var _event_seq := 0

func _init(path := DEFAULT_PATH) -> void:
	load_file(path)

# ── 加载 / 校验 ─────────────────────────────────────────────────

func load_file(path := DEFAULT_PATH) -> bool:
	source_path = path
	source_data = {}
	errors.clear()
	warnings.clear()
	goals = []
	steps = []
	step_by_id = {}
	step_status = {}
	step_event_log = {}
	goal_status = {}
	events = []
	last_event = {}
	_seen_actions = {}
	_event_seq = 0
	t_s = 0.0
	ready = false
	if not FileAccess.file_exists(path):
		errors.append("missing teaching file: " + path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		errors.append("teaching JSON 不是对象: " + path)
		return false
	source_data = (parsed as Dictionary).duplicate(true)
	scenario_id = str(source_data.get("scenario_id", ""))
	story_file = str(source_data.get("story_file", ""))
	manual_only = bool(source_data.get("manual_only", true))
	auto_complete = bool(source_data.get("auto_complete", false))
	status_vocabulary = (source_data.get("status_vocabulary", {}) as Dictionary).duplicate(true)
	var raw_goals: Array = source_data.get("goals", []) if source_data.get("goals") is Array else []
	var raw_steps: Array = source_data.get("steps", []) if source_data.get("steps") is Array else []
	for raw_g in raw_goals:
		if not (raw_g is Dictionary):
			errors.append("goal 非对象")
			continue
		var g: Dictionary = (raw_g as Dictionary).duplicate(true)
		var gid := str(g.get("id", ""))
		if gid == "":
			errors.append("goal id 为空")
			continue
		var step_ids: Array = g.get("step_ids", []) if g.get("step_ids") is Array else []
		goals.append({
			"id": gid,
			"title": str(g.get("title", "")),
			"objective": str(g.get("objective", "")),
			"source": str(g.get("source", "")),
			"step_ids": step_ids.duplicate(),
			"manual_only": bool(g.get("manual_only", true)),
			"auto_complete": bool(g.get("auto_complete", false)),
		})
	for raw_s in raw_steps:
		if not (raw_s is Dictionary):
			errors.append("step 非对象")
			continue
		var s: Dictionary = (raw_s as Dictionary).duplicate(true)
		var sid := str(s.get("id", ""))
		if sid == "":
			errors.append("step id 为空")
			continue
		if step_by_id.has(sid):
			errors.append("step id 重复: " + sid)
			continue
		step_by_id[sid] = s
		steps.append(s)
		step_status[sid] = STATUS_PENDING
		step_event_log[sid] = []
	if steps.size() != 20:
		warnings.append("steps 数量 %d（期望 20）" % steps.size())
	if goals.size() != 4:
		warnings.append("goals 数量 %d（期望 4）" % goals.size())
	var orders: Dictionary = {}
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		var sid := str(s.get("id", ""))
		var order := int(s.get("order", i + 1))
		if orders.has(order):
			warnings.append("order 重复: %d" % order)
		orders[order] = true
		var gid := str(s.get("goal_id", ""))
		if not goal_status.has(gid):
			goal_status[gid] = STATUS_PENDING
		var step_manual := bool(s.get("manual_only", true))
		if not step_manual:
			warnings.append("step %s manual_only=false（控制器仍要求手动）" % sid)
		if bool(s.get("auto_complete", false)):
			warnings.append("step %s auto_complete=true（控制器不自动完成）" % sid)
	for g in goals:
		var gid2 := str((g as Dictionary).get("id", ""))
		var ids: Array = (g as Dictionary).get("step_ids", [])
		for sid2 in ids:
			if not step_by_id.has(str(sid2)):
				warnings.append("goal %s 引用不存在步骤 %s" % [gid2, str(sid2)])
		_update_goal_status(gid2)
	ready = errors.is_empty()
	_refresh_goal_statuses()
	if ready and auto_complete:
		warnings.append("auto_complete=true（控制器不自动完成；manual_only=%s）" % str(manual_only))
	return ready

# ── 动作映射（键为业务动作；也支持直接传 trigger kind）────────────

func _descriptor(action: String, target: String, extra: Dictionary) -> Dictionary:
	var phase := str(extra.get("phase", "prelude"))
	var success := bool(extra.get("success", true))
	match action:
		# —— 业务动作（转场场景）——
		"open_prelude", "prelude_opened":
			return {"kind": "ui_event", "event": "prelude.opened", "phase": phase}
		"set_destination", "select_destination", "select_route":
			return {"kind": "selection", "ui": "prelude.routes",
				"value": target if target != "" else str(extra.get("value", "meridian"))}
		"select_window", "select_burn_window":
			return {"kind": "selection", "ui": "prelude.windows",
				"value": target if target != "" else str(extra.get("value", "t1800"))}
		"confirm_burn", "ignite", "execute_burn", "burn":
			return {"kind": "player_action", "action": "prelude.confirm_burn"}
		"arrive_l1", "transit_done", "arrive":
			return {"kind": "state", "path": "prelude.transit_done", "equals": true}
		"execution_window":
			return {"kind": "state", "path": "execution_window.visible", "equals": true}
		"open_contact_list", "contact_list_opened":
			return {"kind": "ui_event", "event": "contact_list.opened",
				"selection": target if target != "" else str(extra.get("selection", ""))}
		"crossfix", "radar_illum":
			return {"kind": "action_result", "action": action,
				"track_level": int(extra.get("track_level", 2)),
				"track": str(extra.get("track", target))}
		"model_ident", "optical_channel":
			return {"kind": "action_result", "action": action,
				"track_level": int(extra.get("track_level", 3)),
				"track": str(extra.get("track", target))}
		"iff_query":
			return {"kind": "action_result", "action": "iff_query",
				"track_level": int(extra.get("track_level", 0)),
				"track": str(extra.get("track", target))}
		"select_ship", "unit_select":
			return {"kind": "selection", "ui": "unit_panel.ship",
				"value": target if target != "" else str(extra.get("value", "harmattan"))}
		"sensor_toggle", "toggle_sensor":
			var ship := str(extra.get("ship", ""))
			var model := str(extra.get("model", ""))
			if target.contains("/"):
				var parts := target.split("/")
				ship = str(parts[0])
				model = str(parts[1])
			elif model == "":
				model = target
			return {"kind": "sensor_toggle", "ship": ship, "model": model,
				"value": str(extra.get("value", "on"))}
		"command_event":
			var seq: Array = extra.get("sequence", [target] if target != "" else [])
			return {"kind": "command_event", "sequence": seq.duplicate(),
				"link": str(extra.get("link", ""))}
		"command_queued":
			return {"kind": "command_event", "sequence": [target, "command.queued"],
				"link": str(extra.get("link", "LR"))}
		"command_aborted":
			return {"kind": "command_event", "sequence": [target, "command.aborted"],
				"link": str(extra.get("link", "LR"))}
		"decision", "decide", "choose_decision":
			return {"kind": "decision_choice", "choice": target,
				"evidence_count": int(extra.get("evidence_count", 0)),
				"weapons_release_confirmed": bool(extra.get("weapons_release_confirmed", false))}
		"report_submit", "submit_report":
			return {"kind": "report_submit",
				"report": target if target != "" else str(extra.get("report", "INTERNAL_AFTER_ACTION"))}
		"ack_identity", "open_identity_legend", "identity_legend":
			return {"kind": "manual_ack", "ui": "identity_legend"}
		"open_roe_card", "roe_card_opened":
			return {"kind": "ui_event", "event": "roe_card.opened"}
		# —— 直接 trigger kind（便于上层通用转发）——
		"ui_event":
			return {"kind": "ui_event", "event": target,
				"selection": str(extra.get("selection", "")), "phase": str(extra.get("phase", ""))}
		"selection":
			return {"kind": "selection", "ui": target,
				"value": str(extra.get("value", ""))}
		"player_action":
			return {"kind": "player_action", "action": target}
		"state":
			return {"kind": "state", "path": target,
				"equals": extra.get("equals", true)}
		"action_result":
			return {"kind": "action_result", "action": target,
				"track_level": int(extra.get("track_level", 0)),
				"track": str(extra.get("track", ""))}
		"decision_choice":
			return {"kind": "decision_choice", "choice": target,
				"evidence_count": int(extra.get("evidence_count", 0)),
				"weapons_release_confirmed": bool(extra.get("weapons_release_confirmed", false))}
		"manual_ack":
			return {"kind": "manual_ack", "ui": target}
		"report_submit_raw":
			return {"kind": "report_submit", "report": target}
		_:
			return {}

# ── 匹配 ─────────────────────────────────────────────────────────

func _in_alternatives(value: String, alternatives: String) -> bool:
	if alternatives == "":
		return true
	for alt in alternatives.split("|"):
		if str(alt) == value:
			return true
	return false

func _requirements_ok(trigger: Dictionary, d: Dictionary) -> Dictionary:
	var reqs: Array = trigger.get("requires", []) if trigger.get("requires") is Array else []
	for raw in reqs:
		var req := str(raw)
		if req.contains(">="):
			var parts := req.split(">=")
			var key := str(parts[0]).strip_edges()
			var need := float(parts[1])
			if float(d.get(key, 0.0)) < need:
				return {"ok": false, "reason": "requirements_not_met", "requirement": req}
		elif req.contains("="):
			var kv := req.split("=")
			var k := str(kv[0]).strip_edges()
			var v := str(kv[1]).strip_edges()
			if d.has(k) and str(d.get(k, "")) != v:
				return {"ok": false, "reason": "requirements_not_met", "requirement": req}
		elif req == "weapons_release.confirmed":
			if not bool(d.get("weapons_release_confirmed", false)):
				return {"ok": false, "reason": "requirements_not_met", "requirement": req}
		# 未识别的 requirement 不阻塞（内容/上层可扩展）
	return {"ok": true, "reason": ""}

func _trigger_matches(trigger: Dictionary, d: Dictionary) -> Dictionary:
	var kind := str(trigger.get("kind", ""))
	if kind != str(d.get("kind", "")):
		return {"match": false, "reason": "kind_mismatch"}
	match kind:
		"ui_event":
			if str(trigger.get("event", "")) != str(d.get("event", "")):
				return {"match": false, "reason": "event_mismatch"}
			if trigger.has("selection"):
				if not _in_alternatives(str(d.get("selection", "")),
						str(trigger.get("selection", ""))):
					return {"match": false, "reason": "selection_mismatch"}
			return _requirements_ok(trigger, d)
		"selection":
			if str(trigger.get("ui", "")) != str(d.get("ui", "")):
				return {"match": false, "reason": "ui_mismatch"}
			if str(trigger.get("value", "")) != str(d.get("value", "")):
				return {"match": false, "reason": "value_mismatch"}
			return {"ok": true, "reason": ""}
		"player_action":
			if str(trigger.get("action", "")) != str(d.get("action", "")):
				return {"match": false, "reason": "action_mismatch"}
			return {"ok": true, "reason": ""}
		"state":
			var path := str(trigger.get("path", ""))
			var fallback_ui := str(trigger.get("fallback_ui", ""))
			var d_path := str(d.get("path", ""))
			if d_path != path and (fallback_ui == "" or d_path != fallback_ui):
				return {"match": false, "reason": "path_mismatch"}
			if bool(trigger.get("equals", true)) != bool(d.get("equals", true)):
				return {"match": false, "reason": "equals_mismatch"}
			return {"ok": true, "reason": ""}
		"action_result":
			var actions := str(trigger.get("action", "")).split("|")
			if not (str(d.get("action", "")) in actions):
				return {"match": false, "reason": "action_mismatch"}
			if trigger.has("track_level_min"):
				if int(d.get("track_level", 0)) < int(trigger.get("track_level_min", 0)):
					return {"match": false, "reason": "track_level_too_low"}
			if trigger.has("track"):
				if not _in_alternatives(str(d.get("track", "")),
						str(trigger.get("track", ""))):
					return {"match": false, "reason": "track_mismatch"}
			return {"ok": true, "reason": ""}
		"sensor_toggle":
			if str(trigger.get("ship", "")) != str(d.get("ship", "")):
				return {"match": false, "reason": "ship_mismatch"}
			if str(trigger.get("model", "")) != str(d.get("model", "")):
				return {"match": false, "reason": "model_mismatch"}
			if str(trigger.get("value", "on")) != str(d.get("value", "on")):
				return {"match": false, "reason": "value_mismatch"}
			return {"ok": true, "reason": ""}
		"command_event":
			var need_seq: Array = trigger.get("sequence", []) if trigger.get("sequence") is Array else []
			var have_seq: Array = d.get("sequence", []) if d.get("sequence") is Array else []
			for raw_need in need_seq:
				if not (str(raw_need) in have_seq):
					return {"match": false, "reason": "sequence_missing"}
			var link := str(trigger.get("link", ""))
			if link != "" and str(d.get("link", "")) != link:
				return {"match": false, "reason": "link_mismatch"}
			return {"ok": true, "reason": ""}
		"decision_choice":
			if str(trigger.get("choice", "")) != str(d.get("choice", "")):
				return {"match": false, "reason": "choice_mismatch"}
			return _requirements_ok(trigger, d)
		"manual_ack":
			if str(trigger.get("ui", "")) != str(d.get("ui", "")):
				return {"match": false, "reason": "ui_mismatch"}
			return {"ok": true, "reason": ""}
		"report_submit":
			if str(trigger.get("report", "")) != str(d.get("report", "")):
				return {"match": false, "reason": "report_mismatch"}
			return {"ok": true, "reason": ""}
	return {"match": false, "reason": "unsupported_kind"}

# ── 玩家动作入口 ─────────────────────────────────────────────────

## 玩家动作（唯一推进入口）。
## action: 业务动作（open_prelude/set_destination/confirm_burn/arrive_l1/open_contact_list/
##         crossfix/radar_illum/model_ident/optical_channel/iff_query/select_ship/
##         sensor_toggle/command_event/decision/report_submit/ack_identity/open_roe_card …）
##         或直接 trigger kind（ui_event/selection/player_action/state/action_result/
##         sensor_toggle/command_event/decision_choice/manual_ack/report_submit）。
## target: 目标/取值（如 meridian/t1800/harmattan/YW-R9/9001/HOLD/INTERNAL_AFTER_ACTION）。
## extra: 附加字段（track_level/track/sequence/link/evidence_count/weapons_release_confirmed/
##        success=false 表示失败动作…）。
## 返回 {ok, reason, matched_step_id, goal, progress, duplicate, requirements}。
func note(action: String, target := "", extra := {}) -> Dictionary:
	var x: Dictionary = extra if extra is Dictionary else {}
	if not ready:
		last_event = {"t": t_s, "action": action, "target": target,
			"ok": false, "reason": "not_ready", "matched_step_id": ""}
		return {"ok": false, "reason": "not_ready"}
	if bool(x.get("success", true)) == false or action.begins_with("fail"):
		_event(action, target, "action_failed", "", false, "action_failed")
		return {"ok": false, "reason": "action_failed", "failed": true, "matched_step_id": ""}
	var d := _descriptor(action, target, x)
	if d.is_empty():
		_event(action, target, "unknown_action", "", false, "unknown_action")
		return {"ok": false, "reason": "unknown_action", "matched_step_id": ""}
	var dup_key := JSON.stringify({"action": action, "target": target,
		"extra": x}) if not x.has("success") else JSON.stringify({"action": action,
		"target": target, "extra": x})
	if _seen_actions.has(dup_key):
		_event(action, target, "duplicate_action", "", false, "duplicate_action")
		return {"ok": false, "reason": "duplicate_action", "duplicate": true,
			"matched_step_id": ""}
	var first_blocked := ""
	for raw_s in steps:
		var s: Dictionary = raw_s
		var sid := str(s.get("id", ""))
		if str(step_status.get(sid, STATUS_PENDING)) != STATUS_PENDING:
			continue
		var trigger: Dictionary = s.get("trigger_condition", {}) if s.get("trigger_condition") is Dictionary else {}
		var m := _trigger_matches(trigger, d)
		if not bool(m.get("match", m.get("ok", false))):
			if str(m.get("reason", "")) == "requirements_not_met" and first_blocked == "":
				first_blocked = sid
			continue
		# 命中：完成该步骤（乱序补触发允许命中任意 pending step）
		_seen_actions[dup_key] = true
		step_status[sid] = STATUS_COMPLETED
		(step_event_log[sid] as Array).append({"t": t_s, "action": action,
			"target": target, "kind": str(d.get("kind", ""))})
		var gid := str(s.get("goal_id", ""))
		_update_goal_status(gid)
		# G4 分支互斥：选择后其余未选 decision_choice 步骤标记 skipped
		var skipped_branch: Array = []
		if str(d.get("kind", "")) == "decision_choice":
			for raw_o in steps:
				var so: Dictionary = raw_o
				var sid_o := str(so.get("id", ""))
				if sid_o == sid:
					continue
				if str(so.get("goal_id", "")) != gid:
					continue
				if str(step_status.get(sid_o, STATUS_PENDING)) != STATUS_PENDING:
					continue
				var trig_o: Dictionary = so.get("trigger_condition", {}) if so.get("trigger_condition") is Dictionary else {}
				if str(trig_o.get("kind", "")) == "decision_choice":
					step_status[sid_o] = STATUS_SKIPPED
					skipped_branch.append(sid_o)
					(step_event_log[sid_o] as Array).append({"t": t_s,
						"action": action, "reason": "exclusive_decision"})
		_refresh_goal_statuses()
		var progress := _progress()
		var ev := _event(action, target, "step_completed", sid, true, "")
		ev["goal_id"] = gid
		ev["skipped_branch"] = skipped_branch
		last_event = ev
		return {"ok": true, "reason": "", "matched_step_id": sid, "goal_id": gid,
			"skipped_branch": skipped_branch, "progress": progress,
			"completed": str(step_status.get(sid, "")) == STATUS_COMPLETED}
	if first_blocked != "":
		_event(action, target, "requirements_not_met", first_blocked, false,
			"requirements_not_met")
		return {"ok": false, "reason": "requirements_not_met",
			"matched_step_id": "", "blocked_step_id": first_blocked}
	_event(action, target, "no_match", "", false, "no_match")
	return {"ok": false, "reason": "no_match", "matched_step_id": ""}

## 显式跳过（例如无该分支/内容缺失）；不算完成。
func skip_step(step_id: String, reason := "manual_skip") -> Dictionary:
	if not step_by_id.has(step_id):
		return {"ok": false, "reason": "unknown_step"}
	if str(step_status.get(step_id, "")) == STATUS_COMPLETED:
		return {"ok": false, "reason": "already_completed"}
	if str(step_status.get(step_id, "")) == STATUS_SKIPPED:
		return {"ok": false, "reason": "already_skipped"}
	step_status[step_id] = STATUS_SKIPPED
	(step_event_log[step_id] as Array).append({"t": t_s, "action": "skip",
		"reason": reason})
	var s: Dictionary = step_by_id[step_id]
	_update_goal_status(str(s.get("goal_id", "")))
	_refresh_goal_statuses()
	_event("skip_step", step_id, "step_skipped", step_id, true, reason)
	return {"ok": true, "reason": reason, "step_id": step_id, "progress": _progress()}

## 只记时间；manual_only 下不自动完成任何步骤。
func tick(t: float) -> Dictionary:
	t_s = maxf(0.0, t)
	return vm()

func reset() -> void:
	step_status = {}
	step_event_log = {}
	goal_status = {}
	_seen_actions = {}
	events = []
	last_event = {}
	_event_seq = 0
	t_s = 0.0
	for raw_s in steps:
		var sid := str((raw_s as Dictionary).get("id", ""))
		step_status[sid] = STATUS_PENDING
		step_event_log[sid] = []
	for raw_g in goals:
		goal_status[str((raw_g as Dictionary).get("id", ""))] = STATUS_PENDING
	_refresh_goal_statuses()

# ── 内部状态 / 视图 ──────────────────────────────────────────────

func _event(action: String, target: String, kind: String, step_id: String,
		ok: bool, reason: String) -> Dictionary:
	_event_seq += 1
	var ev := {"seq": _event_seq, "t": t_s, "action": action, "target": target,
		"kind": kind, "step_id": step_id, "ok": ok, "reason": reason}
	events.append(ev)
	while events.size() > 200:
		events.pop_front()
	last_event = ev
	return ev

func _update_goal_status(goal_id: String) -> void:
	var completed := 0
	var skipped := 0
	var pending := 0
	for raw_g in goals:
		var g: Dictionary = raw_g
		if str(g.get("id", "")) != goal_id:
			continue
		var ids: Array = g.get("step_ids", [])
		for sid in ids:
			match str(step_status.get(str(sid), STATUS_PENDING)):
				STATUS_COMPLETED:
					completed += 1
				STATUS_SKIPPED:
					skipped += 1
				_:
					pending += 1
		var status := STATUS_PENDING
		if pending == 0 and ids.size() > 0 and completed > 0:
			status = STATUS_COMPLETED
		elif completed > 0 or skipped > 0:
			status = "in_progress"
		goal_status[goal_id] = status
		g["completed_steps"] = completed
		g["skipped_steps"] = skipped
		g["pending_steps"] = pending
		g["status"] = status
		return

func _refresh_goal_statuses() -> void:
	for raw_g in goals:
		_update_goal_status(str((raw_g as Dictionary).get("id", "")))

func _progress() -> Dictionary:
	var completed := 0
	var skipped := 0
	var resolved := 0
	for raw_s in steps:
		var sid := str((raw_s as Dictionary).get("id", ""))
		var st := str(step_status.get(sid, STATUS_PENDING))
		if st == STATUS_COMPLETED:
			completed += 1
			resolved += 1
		elif st == STATUS_SKIPPED:
			skipped += 1
			resolved += 1
	var total := steps.size()
	var goals_done := 0
	for raw_g in goals:
		if str((raw_g as Dictionary).get("status", "")) == STATUS_COMPLETED:
			goals_done += 1
	return {
		"completed": completed, "skipped": skipped, "resolved": resolved,
		"total": total, "pending": total - resolved,
		"pct": (float(completed) / float(total) * 100.0) if total > 0 else 0.0,
		"resolved_pct": (float(resolved) / float(total) * 100.0) if total > 0 else 0.0,
		"goals_completed": goals_done, "goals_total": goals.size(),
	}

func _step_vm(s: Dictionary) -> Dictionary:
	var sid := str(s.get("id", ""))
	return {
		"id": sid,
		"goal_id": str(s.get("goal_id", "")),
		"order": int(s.get("order", 0)),
		"title": str(s.get("title", "")),
		"objective": str(s.get("objective", "")),
		"player_action": str(s.get("player_action", "")),
		"status": str(step_status.get(sid, STATUS_PENDING)),
		"manual_only": bool(s.get("manual_only", true)),
		"auto_complete": bool(s.get("auto_complete", false)),
		"text_keys": (s.get("expected_text_source", []) as Array).duplicate(),
		"gap_id": str(s.get("gap_id", "")),
	}

func _goal_vm(g: Dictionary) -> Dictionary:
	var ids: Array = g.get("step_ids", [])
	var step_rows: Array = []
	for sid in ids:
		if step_by_id.has(str(sid)):
			step_rows.append(_step_vm(step_by_id[str(sid)]))
	return {
		"id": str(g.get("id", "")),
		"title": str(g.get("title", "")),
		"objective": str(g.get("objective", "")),
		"source": str(g.get("source", "")),
		"status": str(g.get("status", STATUS_PENDING)),
		"completed_steps": int(g.get("completed_steps", 0)),
		"skipped_steps": int(g.get("skipped_steps", 0)),
		"pending_steps": int(g.get("pending_steps", ids.size())),
		"step_count": ids.size(),
		"steps": step_rows,
	}

func _current_step() -> Dictionary:
	for raw_s in steps:
		var s: Dictionary = raw_s
		if str(step_status.get(str(s.get("id", "")), STATUS_PENDING)) == STATUS_PENDING:
			var gid := str(s.get("goal_id", ""))
			return {
				"step_id": str(s.get("id", "")),
				"goal_id": gid,
				"title": str(s.get("title", "")),
				"objective": str(s.get("objective", "")),
				"player_action": str(s.get("player_action", "")),
				"hint": str(s.get("player_action", "")),
				"text_keys": (s.get("expected_text_source", []) as Array).duplicate(),
			}
	return {}

func _hints() -> Array:
	var out: Array = []
	for raw_g in goals:
		var g: Dictionary = raw_g
		if str(g.get("status", "")) == STATUS_COMPLETED:
			continue
		var ids: Array = g.get("step_ids", [])
		var found := false
		for sid in ids:
			if str(step_status.get(str(sid), STATUS_PENDING)) == STATUS_PENDING:
				var s: Dictionary = step_by_id[str(sid)]
				out.append({
					"goal_id": str(g.get("id", "")),
					"step_id": str(sid),
					"title": str(s.get("title", "")),
					"hint": str(s.get("player_action", "")),
					"text_keys": (s.get("expected_text_source", []) as Array).duplicate(),
				})
				found = true
				break
		if not found:
			continue
	return out

func _completed_ids() -> Array:
	var out: Array = []
	for raw_s in steps:
		var sid := str((raw_s as Dictionary).get("id", ""))
		if str(step_status.get(sid, "")) == STATUS_COMPLETED:
			out.append(sid)
	return out

func _skipped_ids() -> Array:
	var out: Array = []
	for raw_s in steps:
		var sid := str((raw_s as Dictionary).get("id", ""))
		if str(step_status.get(sid, "")) == STATUS_SKIPPED:
			out.append(sid)
	return out

## 只读 VM（JSON 安全；不渲染 UI/文本）。
func vm() -> Dictionary:
	var goal_rows: Array = []
	for raw_g in goals:
		goal_rows.append(_goal_vm(raw_g))
	var step_rows: Array = []
	for raw_s in steps:
		step_rows.append(_step_vm(raw_s))
	return {
		"schema": SCHEMA,
		"source": source_path,
		"scenario_id": scenario_id,
		"story_file": story_file,
		"ready": ready,
		"manual_only": manual_only,
		"auto_complete": auto_complete,
		"t_s": t_s,
		"goals": goal_rows,
		"steps": step_rows,
		"progress": _progress(),
		"current": _current_step(),
		"hints": _hints(),
		"last_event": last_event.duplicate(true),
		"completed": _completed_ids(),
		"skipped": _skipped_ids(),
		"events": events.duplicate(true),
		"status_vocabulary": status_vocabulary.duplicate(true),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"note": "手动教学控制器：只读 VM；不实现 UI/文本；不写 V15/bridge；manual_only=true/auto_complete=false。",
	}

func to_json() -> String:
	return JSON.stringify(vm())

## 便捷查询。
func step_state(step_id: String) -> Dictionary:
	if not step_by_id.has(step_id):
		return {}
	return {"step_id": step_id, "status": str(step_status.get(step_id, "")),
		"vm": _step_vm(step_by_id[step_id])}

func goal_state(goal_id: String) -> Dictionary:
	for raw_g in goals:
		if str((raw_g as Dictionary).get("id", "")) == goal_id:
			return _goal_vm(raw_g)
	return {}

func is_goal_completed(goal_id: String) -> bool:
	return str(goal_status.get(goal_id, "")) == STATUS_COMPLETED

func is_complete() -> bool:
	return int(_progress().get("pending", 1)) == 0
