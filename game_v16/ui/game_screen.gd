extends Control

## V2-3 第一关游戏屏（四区 + core flow director + 覆盖层）。
##
## 数据：`ui/data_source.gd`（core V2-CORE-2 的 vm_* / vm_flow / flow 方法 + story_l1.json）。
## 战术图：`ui/tactical_view.gd` 消费 `sim/tactical_snapshot.gd`（V2-SENSOR-2，纯数据）。
## 动作：菜单 → data.perform_action → core `perform_action`（core 负责观测/状态，UI 不伪造）。
## 流程：PRELUDE → COMMAND（战术）→ DECISION → REPORT → END，全部由 world.vm_flow() 驱动；
##       按钮直接调 core 的 prelude_*/open_decision/choose_ending/submit_report/restart。
##
## 截图：DSH_V2_SHOT + DSH_V2_VIEW=tactical|prelude|decision|report|end；DSH_V2_WARM 预热秒数。
## headless：`godot --headless --path game_v16` 跑自检后退出（0=通过）。

const T := preload("res://ui/theme.gd")
const L := preload("res://ui/layout.gd")
const DataSource := preload("res://ui/data_source.gd")
const ListView := preload("res://ui/widgets/list_view.gd")
const SectionPanel := preload("res://ui/widgets/section_panel.gd")
const ActionMenu := preload("res://ui/widgets/action_menu.gd")
const TacticalView := preload("res://ui/tactical_view.gd")
const Overlays := preload("res://ui/overlays.gd")

const BUILD_TAG := "V2-3 · FIRST LEVEL · TACTICAL UI"

var data = null
var _tactical = null
var _contacts = null
var _sections = null
var _events = null
var _orders = null
var _actions_inline = null
var _menu = null
var _overlays = null

var _headless := false
var _shot_path := ""
var _shot_view := ""
var _warm_s := 0.0
var _time_scale := 1.0
var _tab := "events"
var _ui_events: Array = []
var _ui_event_seq := 0
var _refresh_accum := 0.0
var _flow: Dictionary = {}
var _flow_mode := ""
var _flow_hint := ""
var _tactical_snapshot: Dictionary = {}
var _last_obs := 0
var _last_sensor_log_t := -100.0
var _last_phase := ""

var _mission_buttons: Array = []
var _mission_hover := -1

var _self_checks := 0
var _self_fails: Array[String] = []


# ══ 生命周期 ═════════════════════════════════════════════════════════════

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_shot_path = OS.get_environment("DSH_V2_SHOT")
	_shot_view = OS.get_environment("DSH_V2_VIEW")
	if _shot_view == "":
		_shot_view = "tactical"
	_warm_s = float(OS.get_environment("DSH_V2_WARM")) if OS.get_environment("DSH_V2_WARM") != "" else 0.0
	if OS.get_environment("DSH_V2_TIMESCALE") != "":
		_time_scale = clampf(float(OS.get_environment("DSH_V2_TIMESCALE")), 0.1, 120.0)
	if not _headless:
		_setup_window()
	data = DataSource.new()
	data.boot()
	_build_children()
	data.select(data.own_id)
	_ui_log("SYS", "V2-3 游戏屏启动 · source=%s · 接触 %d" % [
		data.source_label(), data.all_contacts().size()])
	for note in data.notes:
		_ui_log("DATA", note)
	_refresh_all()
	_sync_flow(true)
	_tactical_tick(0.0)
	if OS.get_environment("DSH_SKIP_PRELUDE") == "1" and not _headless:
		_debug_to_command()
		_sync_flow(true)
	if _headless:
		_run_self_check()
		_finish_headless()
	elif _shot_path != "":
		_capture.call_deferred()
	elif OS.get_environment("DSH_V2_AUTOPLAY") == "1":
		_autoplay.call_deferred()
	else:
		set_process(true)

func _autoplay() -> void:
	# 演示视频用自动流程；只调用 core 公开方法，不伪造状态。
	var w := get_window()
	w.borderless = true
	w.size = Vector2i(1920, 1080)
	w.position = Vector2i(0, 0)
	await get_tree().create_timer(1.2).timeout
	data.select("2001")
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(1.8).timeout
	data.prelude_choose_route("meridian")
	data.prelude_choose_window("t1800")
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(1.8).timeout
	data.prelude_execute()
	data.advance_mission(3)
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(2.0).timeout
	data.perform_action("crossfix", "2001")
	_refresh_all()
	await get_tree().create_timer(1.6).timeout
	data.perform_action("radar_illum", "2001")
	_refresh_all()
	await get_tree().create_timer(1.6).timeout
	data.start_evidence("port_telemetry")
	_refresh_all()
	await get_tree().create_timer(1.6).timeout
	data.perform_action("optical_channel", "2001")
	_refresh_all()
	await get_tree().create_timer(4.0).timeout
	data.open_decision()
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(4.6).timeout
	data.choose_ending("HOLD")
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(3.4).timeout
	data.submit_report(true)
	_refresh_all(); _sync_flow(true)
	await get_tree().create_timer(5.0).timeout
	# 保持 END 画面给录屏收尾
	set_process(true)


func _finish_headless() -> void:
	var code := 0 if _self_fails.is_empty() else 1
	print("V2-3 GAME SELFTEST checks=%d fail=%d" % [_self_checks, _self_fails.size()])
	for f in _self_fails:
		print("  FAIL ", f)
	print("V2-3 GAME HEADLESS ", "OK" if code == 0 else "FAILED")
	get_tree().quit(code)


func _setup_window() -> void:
	var w := get_window()
	w.title = "GHOST TRACK // APSIS — V2 FIRST LEVEL"
	if _shot_path != "":
		w.borderless = true
		w.size = Vector2i(1920, 1080)
		w.position = Vector2i(0, 0)
		return
	w.size = Vector2i(1600, 900)
	var scr := DisplayServer.screen_get_size()
	if scr.x > 1600 and scr.y > 900:
		w.position = Vector2i((scr.x - 1600) / 2, (scr.y - 900) / 2)


func _build_children() -> void:
	_tactical = TacticalView.new()
	_tactical.position = L.MAP.position
	_tactical.size = L.MAP.size
	_tactical.contact_selected.connect(_on_contact_selected)
	_tactical.contact_context.connect(_on_contact_context)
	add_child(_tactical)
	_tactical.bind(data)

	_contacts = ListView.new()
	_contacts.position = L.LEFT.position
	_contacts.size = L.LEFT.size
	_contacts.row_mode = "contact"
	_contacts.row_height = T.ROW_CONTACT
	_contacts.list_title = "接触 / CONTACTS"
	_contacts.list_kicker = "航迹排序 · 选中→战术图/右栏 · 右键动作"
	_contacts.set_empty("（无接触 / NO CONTACTS）", "world.vm_contacts() 为空")
	_contacts.item_selected.connect(_on_contact_selected)
	_contacts.item_context.connect(_on_contact_context)
	add_child(_contacts)

	_sections = SectionPanel.new()
	_sections.position = L.RIGHT.position
	_sections.size = L.RIGHT.size
	add_child(_sections)

	_events = ListView.new()
	_events.position = L.LOG.position
	_events.size = L.LOG.size
	_events.row_mode = "log"
	_events.row_height = T.ROW_LOG
	_events.header_h = 44.0
	_events.list_title = "事件 / 通信 / EVENTS"
	_events.list_kicker = "core 事件 + 无线电 · L 切命令队列"
	_events.set_empty("（暂无事件 / NO EVENTS）", "world.recent_events/recent_radio")
	add_child(_events)

	_orders = ListView.new()
	_orders.position = L.LOG.position
	_orders.size = L.LOG.size
	_orders.row_mode = "log"
	_orders.row_height = T.ROW_LOG
	_orders.header_h = 44.0
	_orders.list_title = "命令队列 / ORDERS"
	_orders.list_kicker = "world.vm_orders() · L 切回事件"
	_orders.set_empty("（命令队列为空 / EMPTY QUEUE）", "动作由 core perform_action 直接执行")
	_orders.visible = false
	add_child(_orders)

	_actions_inline = ActionMenu.new()
	_actions_inline.mode = ActionMenu.MODE_INLINE
	_actions_inline.position = L.ACTIONS.position
	_actions_inline.size = L.ACTIONS.size
	_actions_inline.title = "动作 / ACTIONS"
	_actions_inline.action_chosen.connect(_on_action_chosen)
	add_child(_actions_inline)
	_actions_inline.visible = true

	_menu = ActionMenu.new()
	_menu.mode = ActionMenu.MODE_POPUP
	_menu.position = Vector2.ZERO
	_menu.size = L.DESIGN
	_menu.action_chosen.connect(_on_action_chosen)
	add_child(_menu)

	_overlays = Overlays.new()
	_overlays.position = Vector2.ZERO
	_overlays.size = L.DESIGN
	_overlays.prelude_choose.connect(_on_prelude_choose)
	_overlays.prelude_execute.connect(_on_prelude_execute)
	_overlays.decision_chosen.connect(_on_decision_chosen)
	_overlays.report_submitted.connect(_on_report_submitted)
	_overlays.end_restart.connect(_on_end_restart)
	_overlays.end_quit.connect(_on_end_quit)
	add_child(_overlays)


# ══ 仿真 / 流程 director ═════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _headless:
		return
	if _is_paused():
		return
	var dt := delta * _time_scale
	data.advance_world(dt)
	_tactical_tick(dt)
	_refresh_accum += delta
	if _refresh_accum >= 0.20:
		_refresh_accum = 0.0
		_refresh_all()
		_sync_flow()


func _is_paused() -> bool:
	if _overlays == null:
		return false
	if _overlays.is_open():
		return true
	var report: Dictionary = _flow.get("report", {}) if _flow.get("report", {}) is Dictionary else {}
	return bool(report.get("submitted", false))


func _tactical_tick(dt: float) -> void:
	if not data.tactical_available():
		return
	# 前置/决策/报告/结束覆盖层打开时时间冻结：只重建快照，不推进 sim、不注入观测。
	var frozen: bool = bool(_flow.get("time_frozen", false)) or (_overlays != null and _overlays.is_open())
	if frozen or dt <= 0.0:
		_tactical_snapshot = data.tactical_build(_tactical.camera_cfg())
		if not _tactical_snapshot.is_empty():
			_tactical.set_snapshot(_tactical_snapshot)
		return
	var out: Dictionary = data.tactical_step(dt, _tactical.camera_cfg())
	if out.get("snapshot", null) is Dictionary and not (out["snapshot"] as Dictionary).is_empty():
		_tactical_snapshot = out["snapshot"]
		_tactical.set_snapshot(_tactical_snapshot)
		var obs := int(out.get("observations", 0))
		if obs > 0:
			_last_obs = obs
			var now_t: float = data.world_time()
			if obs >= 5 and now_t - _last_sensor_log_t >= 6.0:
				_last_sensor_log_t = now_t
				_ui_log("SENSOR", "传感器观测注入 core：+%d 条（radar.tws/optical/ir）" % obs)


func _warm(seconds: float, chunk := 0.5) -> void:
	_sync_flow(true)
	var remain := maxf(0.0, seconds)
	while remain > 0.0:
		var dt := minf(chunk, remain)
		data.advance_world(dt)
		_tactical_tick(dt)
		remain -= dt
	data.refresh()
	_refresh_all()
	_sync_flow(true)


func _sync_flow(force := false) -> void:
	var flow: Dictionary = data.vm_flow()
	_flow = flow
	var prelude: Dictionary = flow.get("prelude", {}) if flow.get("prelude", {}) is Dictionary else {}
	var decision: Dictionary = flow.get("decision", {}) if flow.get("decision", {}) is Dictionary else {}
	var report: Dictionary = flow.get("report", {}) if flow.get("report", {}) is Dictionary else {}
	var end: Dictionary = flow.get("end", {}) if flow.get("end", {}) is Dictionary else {}
	var mode := "none"
	if bool(prelude.get("open", false)) and not bool(prelude.get("executed", false)):
		mode = "prelude"
	elif bool(decision.get("open", false)):
		mode = "decision"
	elif bool(report.get("available", false)):
		mode = "report"
	elif bool(report.get("submitted", false)) or bool(end.get("ok", false)):
		mode = "end"
	if not force and mode == _flow_mode:
		if mode == "prelude" and _overlays.mode == "prelude":
			_overlays.update_payload(_prelude_payload())
		return
	_flow_mode = mode
	match mode:
		"prelude":
			_overlays.open_prelude(_prelude_payload())
		"decision":
			_overlays.open_decision(_decision_payload())
		"report":
			_overlays.open_report(_report_payload())
		"end":
			_overlays.open_end(_end_payload())
		_:
			_overlays.close()
	_refresh_all()


func _phase_kind() -> String:
	var mission: Dictionary = _flow.get("mission", {}) if _flow.get("mission", {}) is Dictionary else {}
	return String(mission.get("kind", ""))


func _phase_title() -> String:
	var mission: Dictionary = _flow.get("mission", {}) if _flow.get("mission", {}) is Dictionary else {}
	return String(mission.get("title", ""))


# ══ 覆盖层 payload（全部来自 core flow + content story）══════════════════

func _prelude_payload() -> Dictionary:
	var p: Dictionary = data.prelude_state()
	return {
		"kicker": "PRELUDE · L4-02 HAMMER → L1 MERIDIAN",
		"title": "前置航行 / PRELUDE",
		"phase_title": _phase_title(),
		"body": String(p.get("body", "")),
		"hint": _flow_hint,
		"route": String(p.get("route", "")),
		"window": String(p.get("window", "")),
		"routes": p.get("routes", []),
		"windows": p.get("windows", []),
		"confirm_text": String(p.get("confirm_text", "")),
		"execute_text": String(p.get("execute_text", "")),
		"can_execute": bool(p.get("can_execute", false)),
	}


func _decision_payload() -> Dictionary:
	var d: Dictionary = data.vm_decision()
	var prompt := String(d.get("prompt", ""))
	var countdown: float = data.decision_countdown()
	prompt = prompt.replace("{mm:ss}", _fmt_countdown(countdown))
	var opts: Array = d.get("options", []) if d.get("options", []) is Array else []
	var ev_count := int(d.get("evidence_count", 0))
	var tasks: Array = data.evidence_tasks()
	return {
		"kicker": "DECISION · 指挥官裁决 / COMMANDER DETERMINATION",
		"title": "指挥官裁决 / COMMANDER DETERMINATION",
		"phase_title": _phase_title(),
		"prompt_text": prompt,
		"countdown": _fmt_countdown(countdown),
		"options": opts,
		"evidence_summary": "证据 EVIDENCE %d/%d · can_expose=%s · 决策文本来自 story.decision_prompt/endings" % [
			ev_count, tasks.size(), str(bool(d.get("can_expose", false)))],
		"hint": _flow_hint,
	}


func _report_payload() -> Dictionary:
	var rs: Dictionary = data.report_state()
	var kind := String(rs.get("ending_kind", ""))
	var body := String(data.story_get("report_bodies." + kind, ""))
	var consequence := ""
	if kind == "FIRE":
		consequence = String(data.story_get("consequence_fire", ""))
	var endings: Array = data.story_get("endings", []) if data.story_get("endings", []) is Array else []
	var label := kind
	for raw in endings:
		if String((raw as Dictionary).get("kind", "")) == kind:
			label = String((raw as Dictionary).get("label", kind))
	return {
		"kicker": "REPORT · 内部事后报告 / INTERNAL AFTER-ACTION",
		"title": "内部事后报告 / INTERNAL AFTER-ACTION",
		"phase_title": _phase_title(),
		"unit": String(data.story_get("report_unit", "")),
		"event": String(data.story_get("report_event", "")),
		"evidence": String(data.story_get("report_evidence", "")),
		"ending_kind": kind,
		"ending_label": label,
		"body": body,
		"consequence": consequence,
		"recommend": String(rs.get("recommend", "")),
		"fake_available": bool(rs.get("fake_available", false)),
		"fake_reason": "" if bool(rs.get("fake_available", false)) else "content 未提供 %s 的伪造文本（不伪造）" % kind,
		"hint": _flow_hint,
	}


func _end_payload() -> Dictionary:
	var es: Dictionary = data.end_summary()
	var report: Dictionary = es.get("report", {}) if es.get("report", {}) is Dictionary else {}
	var rep: Dictionary = es.get("reputation", {}) if es.get("reputation", {}) is Dictionary else {}
	var rep_parts: Array = []
	for key in rep.keys():
		rep_parts.append("%s %+d" % [String(key), int(rep[key])])
	var tasks: Array = data.evidence_tasks()
	return {
		"kicker": "END · 归档 / AFTER-ACTION CLOSED",
		"title": "归档 / AFTER-ACTION CLOSED",
		"outcome_label": String(es.get("ending_label", "")),
		"outcome_kind": String(es.get("ending_kind", "")),
		"phase_title": _phase_title(),
		"evidence": "%d/%d 已取得" % [int(es.get("evidence_count", 0)), tasks.size()],
		"report_mode_label": "伪造 / FALSIFIED" if String(report.get("mode", "")) == "fake" else
			("如实 / TRUTH" if String(report.get("mode", "")) == "truth" else "—"),
		"audit_note": "AUDIT FLAG（core report.audit_flag）" if bool(es.get("audit_flag", false)) else "无",
		"reputation": ", ".join(PackedStringArray(rep_parts)) if not rep_parts.is_empty() else "content 未结算（core 无声望模型）",
		"civilians": "已撤离" if bool(es.get("civilians_evacuated", false)) else "—",
		"fire_release": "是（灾难分支）" if bool(es.get("fire_release", false)) else "—",
		"summary": String(es.get("recommend", "")),
		"history": "mission %s · flags %s" % [String(es.get("mission_kind", "")),
			str(es.get("flags", {}))],
	}


func _fmt_countdown(seconds: float) -> String:
	var s := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


# ══ 覆盖层回调（直接调 core flow 方法）══════════════════════════════════

func _on_prelude_choose(kind: String, id: String) -> void:
	var r: Dictionary = data.prelude_choose_route(id) if kind == "route" else data.prelude_choose_window(id)
	_flow_hint = "" if bool(r.get("ok", false)) else String(r.get("reason", "不可用"))
	print("V2-3 PRELUDE CHOOSE ", kind, " ", id, " ok=", r.get("ok"), " reason=", r.get("reason"))
	_refresh_all()
	_sync_flow(true)


func _on_prelude_execute() -> void:
	var c: Dictionary = data.prelude_confirm()
	var r: Dictionary = data.prelude_execute()
	if bool(r.get("ok", false)):
		_flow_hint = ""
		data.advance_mission(3)
		_ui_log("PHASE", "前置航行执行：Δv %.0f m/s · 时间开始流动" % float(r.get("dv_spent_ms", 0.0)))
	else:
		_flow_hint = String(r.get("reason", "执行被拒绝"))
		_ui_log("PHASE", "前置航行执行被拒：%s" % _flow_hint)
	print("V2-3 PRELUDE EXECUTE ok=", r.get("ok"), " reason=", r.get("reason"), " confirm=", c.get("ok"))
	_refresh_all()
	_sync_flow(true)


func _on_decision_chosen(kind: String) -> void:
	var r: Dictionary = data.choose_ending(kind)
	_flow_hint = "" if bool(r.get("ok", false)) else String(r.get("reason", "裁决被拒绝"))
	_ui_log("DECISION", "裁决 %s（%s）" % [kind, "ok" if bool(r.get("ok", false)) else _flow_hint])
	print("V2-3 DECISION ", kind, " ok=", r.get("ok"), " reason=", r.get("reason"))
	_refresh_all()
	_sync_flow(true)


func _on_report_submitted(mode: String) -> void:
	var r: Dictionary = data.submit_report(mode == "truth")
	_flow_hint = "" if bool(r.get("ok", false)) else String(r.get("reason", "提交被拒绝"))
	_ui_log("REPORT", "报告提交：%s（audit=%s）" % [mode, str(r.get("audit_flag", false))])
	print("V2-3 REPORT SUBMIT ", mode, " ok=", r.get("ok"), " audit=", r.get("audit_flag"))
	_refresh_all()
	_sync_flow(true)


func _on_end_restart() -> void:
	var r: Dictionary = data.restart_world()
	print("V2-3 END RESTART ok=", r.get("ok"), " reason=", r.get("reason"))
	_ui_log("FLOW", "任务重开（core restart）")
	_flow_hint = ""
	_tactical.reset_view()
	_refresh_all()
	_sync_flow(true)


func _on_end_quit() -> void:
	print("V2-3 END QUIT")
	get_tree().quit()


# ══ 选择 / 动作 ══════════════════════════════════════════════════════════

func _on_contact_selected(id: String) -> void:
	if id == data.selected_id:
		return
	data.select(id)
	var c: Dictionary = data.contact(id)
	_ui_log("SELECT", "选中 [%s] %s" % [String(c.get("batch", id)), String(c.get("name", ""))])
	_refresh_all()
	if _tactical != null:
		_tactical.set_selected(data.selected_id)


func _on_contact_context(id: String, at: Vector2) -> void:
	if id != data.selected_id:
		_on_contact_selected(id)
	_open_action_menu(at)


func _open_action_menu(at: Vector2) -> void:
	_menu.open(data.actions_for(data.selected_id), data.entity(data.selected_id), at)
	queue_redraw()


func _on_action_chosen(action_id: String, target_id: String) -> void:
	var res: Dictionary = data.perform_action(action_id, target_id)
	if not bool(res.get("ok", false)):
		_ui_log("ACTION", "动作 %s 被拒：%s" % [action_id, String(res.get("reason", ""))])
		print("V2-3 ACTION FAIL ", action_id, " reason=", res.get("reason"))
		_refresh_all()
		return
	# 光学/IR 动作：同时建立 sim 光学凝视通道（仅改变 sim_state，供战术图显示通道环）
	var effect: Dictionary = data.action_effect(action_id)
	var ekind := String(effect.get("kind", ""))
	if ekind == "optical" or ekind == "ir":
		var tr_id := String(data.contact(target_id).get("track_id", target_id))
		data.tactical_start_channel(ekind, tr_id)
	_ui_log("ACTION", "动作 %s → %s · 执行平台 %s · 等级 L%d→L%d · %s" % [
		action_id, String(data.contact(target_id).get("batch", target_id)),
		String(res.get("actor_name", "")), int(res.get("level", 0)), int(res.get("level_after", res.get("level", 0))),
		String(res.get("detail", ""))])
	print("V2-3 ACTION OK ", action_id, " target=", target_id, " actor=", res.get("actor_id"),
		" level=", res.get("level"), " detail=", res.get("detail"))
	_refresh_all()
	_tactical_tick(0.0)


func _step_selection(dir: int) -> void:
	var all: Array = data.all_contacts()
	if all.is_empty():
		return
	var ids: Array = []
	for raw in all:
		ids.append(String((raw as Dictionary).get("id", "")))
	var idx := ids.find(data.selected_id)
	if idx < 0:
		idx = 0
	else:
		idx = clampi(idx + dir, 0, ids.size() - 1)
	_on_contact_selected(String(ids[idx]))
	_contacts.scroll_to_item(data.selected_id)


# ══ 刷新 ═════════════════════════════════════════════════════════════════

func _refresh_all() -> void:
	_refresh_contacts()
	_refresh_events()
	_refresh_orders()
	_refresh_sections()
	_refresh_actions()
	_refresh_mission()
	queue_redraw()


func _refresh_contacts() -> void:
	var rows: Array = []
	for raw in data.all_contacts():
		var c: Dictionary = raw
		var ev: Dictionary = data.entity(String(c.get("id", "")))
		var caps: Array = ev.get("caps", [])
		var subtitle := "%s · %s" % [T.kind_label(String(c.get("kind", ""))), String(c.get("cls", ""))]
		if not bool(c.get("has_entity", true)):
			subtitle = "无实体航迹 · 虚警/纯回波"
		rows.append({
			"id": String(c.get("id", "")),
			"id_label": String(c.get("batch", c.get("id", ""))),
			"title": String(c.get("name", "")),
			"subtitle": subtitle,
			"badge": T.level_name(int(c.get("level", 0))),
			"badge_color": T.identity_color(String(c.get("identity", "unknown"))),
			"accent": T.accent_for(ev),
			"identity": String(c.get("identity", "unknown")),
			"side": String(c.get("side", "unknown")),
			"caps": caps.size(),
		})
	_contacts.set_items(rows)
	_contacts.set_selected(data.selected_id)
	if _tactical != null:
		_tactical.set_selected(data.selected_id)


func _refresh_events() -> void:
	var rows: Array = []
	for ev in _ui_events:
		var e: Dictionary = ev
		rows.append({
			"id": "ui-%d" % int(e.get("seq", 0)),
			"kind": String(e.get("kind", "UI")),
			"text": String(e.get("text", "")),
			"time": "UI",
			"accent": _kind_color(String(e.get("kind", "UI"))),
			"fresh": rows.is_empty(),
		})
	var combined: Array = []
	for raw in data.recent_events(24):
		if raw is Dictionary:
			var ev2: Dictionary = raw
			combined.append({"t": float(ev2.get("t", 0.0)), "kind": String(ev2.get("kind", "EVENT")),
				"text": String(ev2.get("text", ""))})
	for raw2 in data.recent_radio(12):
		if raw2 is Dictionary:
			var rd: Dictionary = raw2
			combined.append({"t": float(rd.get("t", 0.0)),
				"kind": String(rd.get("mode", "RDO")),
				"text": "%s→%s %s" % [String(rd.get("from", "")), String(rd.get("to", "")),
					String(rd.get("text", ""))]})
	combined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) > float(b.get("t", 0.0)))
	for raw3 in combined:
		var ev3: Dictionary = raw3
		var k := String(ev3.get("kind", "EVENT"))
		rows.append({
			"id": "core-%d" % rows.size(),
			"kind": k.to_upper(),
			"text": String(ev3.get("text", "")),
			"time": "T+" + T.hms(float(ev3.get("t", 0.0))),
			"accent": _kind_color(k),
		})
	_events.set_items(rows)


func _refresh_orders() -> void:
	var rows: Array = []
	for raw in data.orders():
		var o: Dictionary = raw
		var state := String(o.get("state", ""))
		var text := String(o.get("action", ""))
		var target := String(o.get("target", ""))
		if target != "":
			text += " → " + target
		rows.append({
			"id": String(o.get("id", "")),
			"kind": state,
			"text": text,
			"time": "T+" + T.hms(float(o.get("created_t", 0.0))),
			"accent": _order_color(state),
		})
	_orders.set_items(rows)


func _refresh_sections() -> void:
	var vm: Dictionary = data.entity(data.selected_id)
	var acts: Array = data.actions_for(data.selected_id)
	var st: Dictionary = data.state()
	st["phase_title"] = _phase_title()
	st["phase_context"] = _phase_kind()
	var ctx: Dictionary = {
		"own_id": data.own_id,
		"own_entity_id": data.own_entity_id,
		"state": st,
		"evidence": data.evidence(),
	}
	_sections.set_entity(vm, acts, ctx)


func _refresh_actions() -> void:
	var vm: Dictionary = data.entity(data.selected_id)
	var acts: Array = data.actions_for(data.selected_id)
	_actions_inline.set_actions(acts, vm)
	if _menu.is_open():
		_menu.set_actions(acts, vm)


func _refresh_mission() -> void:
	_mission_buttons.clear()
	var tasks: Array = data.evidence_tasks()
	var panel := L.PROBE
	var y := panel.position.y + 34.0
	for raw in tasks:
		var ev: Dictionary = raw
		var rect := Rect2(panel.position.x + 12.0, y, 110.0, 16.0)
		_mission_buttons.append({"rect": rect, "action": "evidence", "id": String(ev.get("id", "")),
			"enabled": String(ev.get("state", "")) == "unknown" and not _overlays.is_open()})
		y += 20.0
	var drect := Rect2(panel.position.x + 300.0, panel.end.y - 34.0, 216.0, 24.0)
	_mission_buttons.append({"rect": drect, "action": "decision", "id": "",
		"enabled": not _overlays.is_open() and _phase_kind() != "" and _phase_kind() != "END"})
	# 裁决是否已打开/已完成
	if bool((_flow.get("decision", {}) as Dictionary).get("open", false)):
		for b in _mission_buttons:
			if String((b as Dictionary).get("action", "")) == "decision":
				(b as Dictionary)["enabled"] = false


func _ui_log(kind: String, text: String) -> void:
	_ui_events.push_front({"kind": kind, "text": text, "seq": _ui_event_seq})
	_ui_event_seq += 1
	while _ui_events.size() > 60:
		_ui_events.pop_back()
	if _events != null:
		_refresh_events()


func _kind_color(kind: String) -> Color:
	match kind.to_lower():
		"load", "order", "data", "flow":
			return T.BLUE
		"track", "select", "phase", "decision", "prelude", "timeline":
			return T.AMBER
		"evidence", "action", "report":
			return T.PH
		"rdo", "ld", "lr", "vis", "ir":
			return T.BLUE
		"error", "warning", "warn":
			return T.RED
		_:
			return T.DIM


func _order_color(state: String) -> Color:
	match state:
		"PRE_ORDER", "AUTHORIZED":
			return T.BLUE
		"QUEUED", "TRANSMITTED":
			return T.AMBER
		"EXECUTING":
			return T.PH_DIM
		"DONE":
			return T.PH
		"REJECTED", "ABORTED":
			return T.RED
		_:
			return T.FAINT


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, L.DESIGN), T.BG)
	_draw_bezel()
	_draw_top_bar()
	_draw_mission_panel()
	_draw_footer()


func _draw_bezel() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 40.0), T.BEZEL)
	draw_rect(Rect2(0.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(1880.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(0.0, 1040.0, 1920.0, 40.0), T.BEZEL)
	_screw(Vector2(20.0, 20.0))
	_screw(Vector2(1900.0, 20.0))
	_screw(Vector2(20.0, 1060.0))
	_screw(Vector2(1900.0, 1060.0))
	T.text(self, 56.0, 10.0, "CS-9", T.F9, T.a(T.PH_DIM, 0.85), false)
	T.text(self, 56.0, 22.0, "战术显控台", T.F7, T.a(T.FAINT, 0.9))
	T.text_r(self, 1864.0, 1052.0, "TACTICAL DISPLAY UNIT · " + BUILD_TAG + " · SER. 0447",
		T.F7, T.a(T.FAINT, 0.8), false)


func _screw(p: Vector2) -> void:
	draw_circle(p, 5.5, Color("#050606"))
	draw_arc(p, 5.5, 0.0, TAU, 24, Color("#232A27"), 1.0, true)
	draw_line(p + Vector2(-3.0, -1.0), p + Vector2(3.0, 1.0), Color("#1A201D"), 1.0)


func _draw_top_bar() -> void:
	draw_rect(L.TOP, T.a(T.BG, 0.55))
	draw_line(Vector2(40.0, 112.0), Vector2(1880.0, 112.0), T.a(T.LINE, 0.95), 1.0)
	T.text(self, 60.0, 40.0, "GHOST TRACK // APSIS", T.F24, T.PH)
	T.text(self, 60.0, 72.0, "OCUVF-ID13 · 指挥官席 / COMMANDER", T.F8, T.DIM)
	T.vline(self, 480.0, 44.0, 104.0, T.a(T.LINE, 0.7))
	var kind: String = _phase_kind()
	T.text(self, 500.0, 44.0, "场景 / SCENARIO · " + data.scenario_id, T.F7, T.FAINT)
	T.text_fit(self, 500.0, 56.0, data.title, T.F11, T.TXT, 520.0)
	T.text(self, 500.0, 80.0, "PHASE %s · %s" % [kind, _phase_title()], T.F8, T.a(T.AMBER, 0.9))
	var frozen: bool = bool(_flow.get("time_frozen", false))
	T.text(self, 500.0, 96.0, "T+%s · 决策倒计时 %s · TIME ×%d%s" % [
		T.hms(data.world_time()), _fmt_countdown(data.decision_countdown()), int(_time_scale),
		" · 时间冻结" if frozen else ""], T.F8, T.DIM, false)
	var counts: Dictionary = _tactical_snapshot.get("counts", {}) if _tactical_snapshot.get("counts", {}) is Dictionary else {}
	var radar: Dictionary = _tactical_snapshot.get("radar", {}) if _tactical_snapshot.get("radar", {}) is Dictionary else {}
	var xr := 1864.0
	xr = _chip_right(xr, 44.0, "TWS %d" % int(counts.get("tws_channels", 0)),
		T.PH if int(counts.get("tws_active", 0)) > 0 else T.PH_DIM, int(counts.get("tws_active", 0)) > 0)
	xr = _chip_right(xr, 44.0, "OPT %d" % int(counts.get("optical_locked", 0)),
		T.PH if int(counts.get("optical_locked", 0)) > 0 else T.PH_DIM, int(counts.get("optical_locked", 0)) > 0)
	xr = _chip_right(xr, 44.0, "RADAR %s" % ("ON" if bool(radar.get("enabled", false)) else "OFF"),
		T.PH if bool(radar.get("enabled", false)) else T.AMBER, bool(radar.get("enabled", false)))
	xr = _chip_right(xr, 44.0, "ROE 仅自卫", T.AMBER, true)
	xr = _chip_right(xr, 44.0, String(kind), T.PH_DIM, true)
	T.text_r(self, 1864.0, 72.0, "VIEW %s · %s · 证据 %d/%d" % [_shot_view.to_upper(),
		data.source_label(), int(data.state().get("evidence_count", 0)),
		(data.evidence_tasks() as Array).size()], T.F7, T.a(T.FAINT, 0.85), false)


func _chip_right(xr: float, y: float, label: String, col: Color, active: bool) -> float:
	var w := T.text_w(label, T.F7, false) + 14.0
	T.chip(self, Rect2(xr - w, y, w, 18.0), label, col, active, T.F7)
	return xr - w - 6.0


func _draw_mission_panel() -> void:
	var panel := L.PROBE
	T.panel(self, panel, 0.965, 0.85)
	T.text(self, panel.position.x + 12.0, panel.position.y + 8.0, "任务 / MISSION", T.F9, T.TXT)
	var frozen: bool = bool(_flow.get("time_frozen", false))
	T.text_r(self, panel.end.x - 12.0, panel.position.y + 8.0,
		"%s · %s" % [_phase_kind(), "FROZEN" if frozen else ("×%d" % int(_time_scale))],
		T.F8, T.a(T.AMBER, 0.9))
	T.hline(self, panel.position.x + 10.0, panel.position.y + 26.0, panel.end.x - 10.0, T.a(T.LINE, 0.65))
	var tasks: Array = data.evidence_tasks()
	var y := panel.position.y + 34.0
	for raw in tasks:
		var ev: Dictionary = raw
		var state := String(ev.get("state", "unknown"))
		var col: Color = T.FAINT
		if state == "done":
			col = T.PH
		elif state == "in_progress":
			col = T.AMBER
		var rect := Rect2(panel.position.x + 12.0, y, 110.0, 16.0)
		draw_rect(rect, T.a(col, 0.07))
		draw_rect(rect, T.a(col, 0.35), false, 1.0)
		T.text_fit(self, rect.position.x + 4.0, rect.position.y + 3.0, String(ev.get("label", "")),
			T.F7, T.a(col, 0.95), 100.0)
		T.bar(self, Rect2(rect.position.x + 114.0, rect.position.y + 6.0, 84.0, 3.0),
			float(ev.get("progress", 0.0)), col)
		var status := "开始"
		if state == "done":
			status = "已取得"
		elif state == "in_progress":
			status = "%.0fs" % float(ev.get("remain_s", 0.0))
		T.text_r(self, rect.end.x + 214.0, rect.position.y + 2.0, status, T.F7, T.a(col, 0.85))
		y += 20.0
	var drect := Rect2(panel.position.x + 300.0, panel.end.y - 34.0, 216.0, 24.0)
	var can_decide: bool = not _overlays.is_open() and _phase_kind() != "END" and _phase_kind() != ""
	draw_rect(drect, T.a(T.AMBER if can_decide else T.LINE, 0.10 if can_decide else 0.03))
	draw_rect(drect, T.a(T.AMBER if can_decide else T.LINE, 0.7 if can_decide else 0.3), false, 1.0)
	T.text_c(self, drect.get_center().x, drect.position.y + 6.0, "打开裁决 / DECISION", T.F8,
		T.a(T.AMBER, 0.95) if can_decide else T.a(T.FAINT, 0.8))
	T.text(self, panel.position.x + 12.0, panel.end.y - 28.0,
		"证据：点任务行开始 · 时间线 T+75 自动裁决", T.F7, T.a(T.FAINT, 0.8))
	T.text(self, panel.position.x + 12.0, panel.end.y - 14.0,
		"穿梭机任务互斥（core start_evidence 校验）", T.F7, T.a(T.FAINT, 0.8))


func _draw_footer() -> void:
	var hint := "↑↓ 选择 · 右键目标动作 · 1/2/3 时间倍率 · L 事件/命令 · R 战术图复位 · TAB 调试推进 · Q 退出"
	if _overlays != null and _overlays.is_open():
		hint = "覆盖层：1–4 选择 · ENTER 确认 · R 重开 · Q 退出"
	T.text(self, 60.0, 1002.0, hint, T.F8, T.FAINT)
	T.text_r(self, 1864.0, 1002.0, "%s · 1920×1080 · %s · ×%d" % [
		BUILD_TAG, data.source_label(), int(_time_scale)], T.F8, T.a(T.FAINT, 0.9), false)


# ══ 输入 ═════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if _overlays != null and _overlays.is_open():
		if _overlays.handle_key(key.keycode):
			accept_event()
		return
	match key.keycode:
		KEY_ESCAPE, KEY_Q:
			if _menu.is_open():
				_menu.close()
			else:
				get_tree().quit()
		KEY_TAB:
			var r: Array = data.advance_mission(1)
			print("V2-3 DEBUG ADVANCE ", str(r))
			_ui_log("FLOW", "调试推进阶段 %s" % str(r))
			_refresh_all()
			_sync_flow(true)
			accept_event()
		KEY_L:
			_tab = "orders" if _tab == "events" else "events"
			_events.visible = _tab == "events"
			_orders.visible = _tab == "orders"
			accept_event()
		KEY_1:
			_time_scale = 1.0
			queue_redraw()
		KEY_2:
			_time_scale = 10.0
			queue_redraw()
		KEY_3:
			_time_scale = 60.0
			queue_redraw()
		KEY_R:
			_tactical.reset_view()
			accept_event()
		KEY_UP, KEY_DOWN:
			if not _menu.is_open():
				_step_selection(-1 if key.keycode == KEY_UP else 1)
				accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if not _menu.is_open():
				_open_action_menu(_tactical.get_global_rect().position + Vector2(L.MAP.size.x * 0.5, 260.0))
				accept_event()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _menu.is_open() and not _overlays.is_open():
			_open_action_menu(mb.position)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _handle_mission_click(mb.position):
				accept_event()
				return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var idx := _mission_button_at(mm.position)
		if idx != _mission_hover:
			_mission_hover = idx
			queue_redraw()


func _mission_button_at(pos: Vector2) -> int:
	for i in range(_mission_buttons.size()):
		if (_mission_buttons[i]["rect"] as Rect2).has_point(pos):
			return i
	return -1


func _handle_mission_click(pos: Vector2) -> bool:
	var idx := _mission_button_at(pos)
	if idx < 0:
		return false
	var b: Dictionary = _mission_buttons[idx]
	if not bool(b.get("enabled", true)):
		return true
	match String(b.get("action", "")):
		"evidence":
			var r: Dictionary = data.start_evidence(String(b.get("id", "")))
			_ui_log("EVIDENCE", "证据任务开始：%s" % (String(r.get("reason", "")) if not bool(r.get("ok", false)) else String(b.get("id", ""))))
			_refresh_all()
		"decision":
			var r2: Dictionary = data.open_decision()
			_ui_log("DECISION", "打开裁决：%s" % (String(r2.get("reason", "")) if not bool(r2.get("ok", false)) else "ok"))
			_refresh_all()
			_sync_flow(true)
	return true


# ══ 截图钩子 ═════════════════════════════════════════════════════════════

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_shot_view()
	await get_tree().process_frame
	await get_tree().process_frame
	var w := get_window()
	w.borderless = true
	w.size = Vector2i(1920, 1080)
	w.position = Vector2i(0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("V2-3 GAME SHOT view=%s size=%s err=%s → %s" % [
		_shot_view, str(img.get_size()), str(err), _shot_path])
	get_tree().quit(0 if err == OK else 1)


func _apply_shot_view() -> void:
	match _shot_view:
		"prelude":
			_sync_flow(true)
		"tactical":
			_debug_to_command()
			data.tactical_start_channel("optical", "2001")
			_warm(maxf(30.0, _warm_s))
		"decision":
			_debug_to_command()
			_warm(maxf(20.0, _warm_s))
			data.open_decision()
		"report":
			_debug_to_command()
			data.open_decision()
			data.choose_ending("HOLD")
		"end":
			_debug_to_command()
			data.open_decision()
			data.choose_ending("HOLD")
			data.submit_report(true)
		_:
			_debug_to_command()
	_refresh_all()
	_sync_flow(true)
	_tactical_tick(0.0)


func _debug_to_command() -> void:
	if bool(data.prelude_state().get("open", false)):
		var r: Dictionary = data.prelude_skip()
		print("V2-3 DEBUG PRELUDE SKIP ", str(r))
		data.advance_mission(3)
	_refresh_all()


# ══ headless 自检 ════════════════════════════════════════════════════════

func _run_self_check() -> void:
	_self_checks = 0
	_self_fails.clear()
	# 1) 布局 / 数据
	var lc := L.self_check()
	_check(bool(lc["ok"]), "layout letterbox self_check")
	_check(data.all_contacts().size() > 0, "contacts > 0")
	_check(not data.own().is_empty(), "own exists")
	_check(data.story_data().size() > 0, "story_l1 loaded")
	# 2) 战术快照（sim V2-SENSOR-2）
	_check(data.tactical_available(), "tactical snapshot available")
	var snap: Dictionary = data.tactical_build(_tactical.camera_cfg())
	_check(not snap.is_empty(), "tactical build non-empty")
	_check((snap.get("contacts", []) as Array).size() == data.all_contacts().size(), "snapshot contacts count")
	var radar: Dictionary = snap.get("radar", {}) if snap.get("radar", {}) is Dictionary else {}
	_check(bool(radar.get("available", false)), "radar sphere available (data, not sector)")
	_check(String((radar.get("sphere", {}) as Dictionary).get("shape", "")) == "sphere", "radar shape=sphere")
	var own_scr: Dictionary = (snap.get("own", {}) as Dictionary).get("screen", {}) if (snap.get("own", {}) as Dictionary).get("screen", {}) is Dictionary else {}
	_check(not own_scr.is_empty(), "own screen projection")
	var l1_has_line := false
	for raw_c in (snap.get("contacts", []) as Array):
		var c: Dictionary = raw_c
		if int(c.get("level", 0)) <= 1 and not (c.get("bearing_line", {}) as Dictionary).is_empty():
			l1_has_line = true
	_check(l1_has_line, "L1/Bearing-only contacts use bearing_line (no fake position)")
	# 3) PRELUDE → COMMAND（core flow）
	var p: Dictionary = data.prelude_state()
	_check(bool(p.get("open", false)), "prelude open at boot")
	var rr: Dictionary = data.prelude_choose_route("meridian")
	_check(bool(rr.get("ok", false)), "prelude choose route meridian")
	var wr: Dictionary = data.prelude_choose_window("t1800")
	_check(bool(wr.get("ok", false)), "prelude choose window t1800")
	_check(bool(data.prelude_state().get("can_execute", false)), "prelude can_execute")
	var er: Dictionary = data.prelude_execute()
	_check(bool(er.get("ok", false)), "prelude execute")
	data.advance_mission(3)
	_refresh_all()
	_sync_flow(true)
	_check(_phase_kind() == "COMMAND", "phase COMMAND after prelude")
	# 4) 动作 → core perform_action（真执行，不伪造）
	var target := "2001"
	var acts: Array = data.actions_for(target)
	var pick: Dictionary = {}
	for raw_a in acts:
		var a: Dictionary = raw_a
		if bool(a.get("available", false)):
			pick = a
			break
	_check(not pick.is_empty(), "available action for 2001")
	if not pick.is_empty():
		var ar: Dictionary = data.perform_action(String(pick.get("id", "")), target)
		_check(bool(ar.get("ok", false)), "core perform_action ok")
		_check(int(ar.get("level", -1)) >= 1, "perform_action returns evidence level")
	# 5) 传感器 step → 观测注入 core；TWS/光学通道
	_warm(26.0)
	var snap2: Dictionary = data.tactical_build(_tactical.camera_cfg())
	var counts: Dictionary = snap2.get("counts", {}) if snap2.get("counts", {}) is Dictionary else {}
	_check(int(counts.get("tws_channels", 0)) > 0, "TWS channels from sim after warm")
	_check(int(data.entity("2001").get("level", 0)) >= 2, "2001 level raised by ingested observations")
	var obs_ok := false
	for raw_c2 in (snap2.get("contacts", []) as Array):
		var c2: Dictionary = raw_c2
		if not (c2.get("tws", {}) as Dictionary).is_empty():
			obs_ok = true
	_check(obs_ok, "contact carries TWS channel state")
	# 6) 证据任务：开始 + 时间推进自动完成
	var started: Dictionary = data.start_evidence("port_telemetry")
	_check(bool(started.get("ok", false)), "start_evidence port_telemetry")
	_warm(34.0)
	var done := 0
	for raw_e in data.evidence_tasks():
		if String((raw_e as Dictionary).get("state", "")) == "done":
			done += 1
	_check(done >= 1, "evidence auto-completed by world.advance")
	# 7) DECISION：EXPOSE 门槛来自 core vm_decision
	var od: Dictionary = data.open_decision()
	_check(bool(od.get("ok", false)), "open_decision")
	_sync_flow(true)
	var vm_dec: Dictionary = data.vm_decision()
	_check(bool(vm_dec.get("open", false)), "decision open in vm")
	var expose_enabled := true
	var expose_reason := ""
	for raw_o in (vm_dec.get("options", []) as Array):
		var o: Dictionary = raw_o
		if String(o.get("kind", "")) == "EXPOSE":
			expose_enabled = bool(o.get("enabled", true))
			expose_reason = String(o.get("reason", ""))
	_check(not expose_enabled and expose_reason != "", "EXPOSE disabled with reason when evidence < min")
	# 8) 裁决 → REPORT → END（文本来自 content）
	var ch: Dictionary = data.choose_ending("HOLD")
	_check(bool(ch.get("ok", false)), "choose_ending HOLD")
	_sync_flow(true)
	_check(bool(data.report_state().get("available", false)), "report available")
	_check(String(_report_payload().get("body", "")) != "", "report body from story")
	var sub: Dictionary = data.submit_report(true)
	_check(bool(sub.get("ok", false)), "submit_report truth")
	_sync_flow(true)
	var es: Dictionary = data.end_summary()
	_check(bool(es.get("ok", false)), "end summary ok")
	_check(String(es.get("ending_kind", "")) == "HOLD", "end ending_kind HOLD")
	_check(not bool(es.get("audit_flag", false)), "truth report no audit flag")
	# 9) 覆盖层几何
	var has_btn := false
	for raw_b in _overlays._buttons:
		if (raw_b as Dictionary).get("rect", null) is Rect2 and (raw_b["rect"] as Rect2).size.x > 0.0:
			has_btn = true
	_check(has_btn, "overlay buttons geometry")
	# 10) 重开
	var rs: Dictionary = data.restart_world()
	_check(bool(rs.get("ok", false)), "restart world")
	_check(bool(data.prelude_state().get("open", false)), "prelude open after restart")
	print("V2-3 GAME SELFTEST flow: prelude→command→decision→report→end; contacts=%d tws=%d evidence_done=%d" % [
		data.all_contacts().size(), int(counts.get("tws_channels", 0)), done])


func _check(cond: bool, label: String) -> void:
	_self_checks += 1
	if not cond:
		_self_fails.append(label)
		print("V2-3 GAME SELFTEST FAIL: ", label)
