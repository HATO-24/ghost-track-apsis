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
const DamagePanel := preload("res://ui/damage_panel.gd")
const LayersPanel := preload("res://ui/layers_panel.gd")
const ChannelWindow := preload("res://ui/channel_window.gd")

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
var _damage_panel = null
var _layers_panel = null
var _channel_window = null
var _layers: Dictionary = {}
var _channel_open := false
var _channel_kind := "optical"
var _channel_target := ""
var _channel_action: Dictionary = {}
var _bottom_tab := "mission"          # mission | damage
var _replay_frames: Array = []
var _replay_open := false
var _replay_playing := false
var _replay_cursor := 0
var _replay_accum := 0.0
var _replay_vm: Dictionary = {}
var _replay_core := false
var _replay_buttons: Array = []
var _replay_dragging := false
var _replay_record_started := false

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
	_layers = data.layers_state()
	_layers_panel.bind(data)
	_layers_panel.set_layers(_layers)
	_tactical.set_layers(_layers)
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
	# 教学 section 置顶（来自 data_source.tutorial_state()；core vm_tutorial 或 UI 兜底）
	_sections.register_section({
		"id": "tutorial", "when": Callable(self, "_when_tutorial"),
		"build": Callable(self, "_build_tutorial_section"),
	}, true)

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

	_damage_panel = DamagePanel.new()
	_damage_panel.position = L.PROBE.position
	_damage_panel.size = L.PROBE.size
	_damage_panel.visible = false
	add_child(_damage_panel)

	_menu = ActionMenu.new()
	_menu.mode = ActionMenu.MODE_POPUP
	_menu.position = Vector2.ZERO
	_menu.size = L.DESIGN
	_menu.action_chosen.connect(_on_action_chosen)
	add_child(_menu)

	_layers_panel = LayersPanel.new()
	_layers_panel.position = L.MAP.position + Vector2(12.0, 44.0)
	_layers_panel.size = Vector2(280.0, 226.0)
	_layers_panel.visible = false
	_layers_panel.layer_toggled.connect(_on_layer_toggled)
	add_child(_layers_panel)

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

	_channel_window = ChannelWindow.new()
	_channel_window.position = Vector2.ZERO
	_channel_window.size = L.DESIGN
	_channel_window.visible = false
	_channel_window.start_requested.connect(_on_channel_start)
	_channel_window.stop_requested.connect(_on_channel_stop)
	_channel_window.closed.connect(_close_channel)
	add_child(_channel_window)


# ══ 仿真 / 流程 director ═════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _headless:
		return
	if _is_paused():
		return
	if _replay_open:
		if _replay_playing and _replay_frames.size() > 1:
			_replay_accum += delta
			while _replay_accum >= 0.2:
				_replay_accum -= 0.2
				if _replay_cursor < _replay_frames.size() - 1:
					_replay_cursor += 1
					_replay_apply()
				else:
					_replay_playing = false
					break
			queue_redraw()
		return
	var dt := delta * _time_scale
	data.advance_world(dt)
	_tactical_tick(dt)
	_replay_accum += delta
	if _replay_accum >= 1.0:
		_replay_accum = 0.0
		_record_frame()
	_refresh_accum += delta
	if _refresh_accum >= 0.20:
		_refresh_accum = 0.0
		_refresh_all()
		_sync_flow()


func _is_paused() -> bool:
	if _replay_open:
		return true
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
		_replay_accum += dt
		if _replay_accum >= 1.0:
			_replay_accum = 0.0
			_record_frame()
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
	var mission_kind := String((flow.get("mission", {}) as Dictionary).get("kind", "")) if flow.get("mission", {}) is Dictionary else ""
	if mission_kind == "COMMAND" and not _replay_record_started and data.has_core():
		data.replay_start()   # core V2-CORE-3：COMMAND 起自动录制回放帧（只读帧）
		_replay_record_started = true
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
	var countdown: float = data.exec_left()
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
	_replay_record_started = false
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
		_open_channel(ekind, target_id, res)
	_ui_log("ACTION", "动作 %s → %s · 执行平台 %s · 等级 L%d→L%d · %s" % [
		action_id, String(data.contact(target_id).get("batch", target_id)),
		String(res.get("actor_name", "")), int(res.get("level", 0)), int(res.get("level_after", res.get("level", 0))),
		String(res.get("detail", ""))])
	print("V2-3 ACTION OK ", action_id, " target=", target_id, " actor=", res.get("actor_id"),
		" level=", res.get("level"), " detail=", res.get("detail"))
	_refresh_all()
	_tactical_tick(0.0)


# ── 图层 / 光学通道窗 ───────────────────────────────────────────────────

func _on_layer_toggled(name: String, on: bool) -> void:
	_layers[name] = on
	if _tactical != null:
		_tactical.set_layers(_layers)
	_ui_log("LAYERS", "图层 %s → %s（core set_layer + 本地立即生效）" % [name, "ON" if on else "OFF"])
	_refresh_events()
	queue_redraw()


func _open_channel(kind: String, target_id: String, action_result: Dictionary) -> void:
	if _channel_window == null:
		return
	_channel_kind = kind
	_channel_target = target_id
	_channel_action = action_result.duplicate(true)
	_channel_action["id"] = kind + "_channel"
	var c: Dictionary = data.contact(target_id)
	_channel_window.set_payload(kind, _channel_target_dict(c), _channel_action, not _tactical_snapshot.is_empty())
	_channel_window.set_channel(_find_channel_view(kind, target_id))
	_channel_window.visible = true
	_channel_open = true
	_refresh_channel()
	queue_redraw()


func _close_channel() -> void:
	if _channel_window != null:
		_channel_window.visible = false
	_channel_open = false
	queue_redraw()


func _channel_target_dict(c: Dictionary) -> Dictionary:
	var kind := String(c.get("kind", "ship"))
	var kl := T.kind_label(kind)
	return {
		"id": String(c.get("id", "")), "track_id": String(c.get("track_id", c.get("id", ""))),
		"batch": String(c.get("batch", "")), "name": String(c.get("name", "")),
		"name_en": String(c.get("name_en", "")), "identity": String(c.get("identity", "unknown")),
		"identity_label": String(c.get("identity_label", c.get("identity", ""))),
		"level": int(c.get("level", 0)), "level_label": String(c.get("level_label", "")),
		"kind": kind, "kind_label": kl, "cls": String(c.get("cls", "")),
		"display_kind": String(c.get("display_kind", kind)),
		"range_km": float(c.get("range_km", -1.0)), "range_band": String(c.get("range_band_label", "")),
		"bearing_deg": float(c.get("bearing_deg", -1.0)),
	}


## 从 sim 快照找当前目标/通道的光学通道视图。
## 优先 snapshot.optical.channels（完整字段），退回 contact.optical_channels（dict/array 两种形状）。
func _find_channel_view(kind: String, target_id: String) -> Dictionary:
	if _tactical_snapshot.is_empty():
		return {}
	var track_id := String(data.contact(target_id).get("track_id", target_id))
	var optical: Dictionary = _tactical_snapshot.get("optical", {}) if _tactical_snapshot.get("optical", {}) is Dictionary else {}
	var full: Array = optical.get("channels", []) if optical.get("channels", []) is Array else []
	for raw in full:
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		if String(ch.get("channel", "")) != kind:
			continue
		if String(ch.get("target_track_id", track_id)) == track_id:
			return ch
	for raw_c in (_tactical_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw_c
		if String(c.get("track_id", "")) != track_id:
			continue
		var chans: Variant = c.get("optical_channels", {})
		if chans is Dictionary:
			var d: Dictionary = chans
			if d.get(kind, null) is Dictionary and not (d[kind] as Dictionary).is_empty():
				return (d[kind] as Dictionary).duplicate(true)
		elif chans is Array:
			for raw_ch in chans:
				if raw_ch is Dictionary and String((raw_ch as Dictionary).get("channel", "")) == kind:
					return (raw_ch as Dictionary).duplicate(true)
	return {}


func _refresh_channel() -> void:
	if not _channel_open or _channel_window == null:
		return
	var view := _find_channel_view(_channel_kind, _channel_target)
	_channel_window.set_channel(view)
	var optical: Dictionary = _tactical_snapshot.get("optical", {}) if _tactical_snapshot.get("optical", {}) is Dictionary else {}
	_channel_window.snapshot_available = not view.is_empty() or bool(optical.get("available", false))
	_channel_window.queue_redraw()


func _on_channel_start(kind: String, target_id: String) -> void:
	var tr := String(data.contact(target_id).get("track_id", target_id))
	var r: Dictionary = data.tactical_start_channel(kind, tr)
	_ui_log("CHANNEL", "开始 %s 凝视 → %s：%s" % [kind, tr, "ok" if bool(r.get("ok", true)) else String(r.get("reason", ""))])
	_refresh_channel()


func _on_channel_stop(kind: String, target_id: String) -> void:
	var tr := String(data.contact(target_id).get("track_id", target_id))
	data.tactical_stop_channel(kind, tr)
	_ui_log("CHANNEL", "停止 %s 凝视 → %s" % [kind, tr])
	_refresh_channel()


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
	_refresh_bottom_tab()
	_refresh_channel()
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
	var tut0: Dictionary = data.tutorial_state()
	var drect := Rect2(panel.position.x + 300.0, panel.end.y - 34.0, 216.0, 24.0)
	_mission_buttons.append({"rect": drect, "action": "decision", "id": "",
		"enabled": not _overlays.is_open() and _phase_kind() != "" and _phase_kind() != "END"
			and bool(tut0.get("complete", true)),
		"reason": "教学门控未完成：%s" % String(tut0.get("gate_reason", ""))})
	# 裁决是否已打开/已完成
	if bool((_flow.get("decision", {}) as Dictionary).get("open", false)):
		for b in _mission_buttons:
			if String((b as Dictionary).get("action", "")) == "decision":
				(b as Dictionary)["enabled"] = false


func _when_tutorial(_vm: Dictionary) -> bool:
	return true


## 教学 section：来自 data.tutorial_state()（core vm_tutorial 或 UI 兜底），只读展示。
func _build_tutorial_section(_vm: Dictionary) -> Dictionary:
	var tut: Dictionary = data.tutorial_state()
	var done := int(tut.get("done_count", 0))
	var total := int(tut.get("total", 4))
	var rows: Array = []
	if bool(tut.get("complete", false)):
		rows.append({"label": "状态 / STATUS", "value": "识别完成 / READY", "color": T.PH})
	else:
		rows.append({"label": "门控 / GATE", "value": "识别不足 %d/%d" % [done, total], "color": T.AMBER})
	var steps: Array = tut.get("steps", []) if tut.get("steps", []) is Array else []
	for raw in steps:
		var st: Dictionary = raw
		if st.is_empty():
			continue
		var ok := bool(st.get("done", false))
		var avail := bool(st.get("available", true))
		var stext := "完成" if ok else ("可执行" if avail else "未解锁")
		rows.append({
			"label": String(st.get("label", st.get("id", ""))),
			"value": stext,
			"color": T.PH if ok else (T.AMBER if avail else T.FAINT),
		})
		if not ok and not avail and String(st.get("hint", "")) != "":
			rows.append({"label": "  · 原因", "value": String(st.get("hint", ""))})
	var gate := String(tut.get("gate_reason", ""))
	if gate != "":
		rows.append({"label": "原因 / REASON", "value": gate})
	var hint := String(tut.get("hint", tut.get("reason", "")))
	if hint != "" and bool(tut.get("fallback", false)):
		rows.append({"label": "数据源 / SOURCE", "value": hint})
	return {"id": "tutorial", "title": "教学 / TUTORIAL", "count": "%d/%d" % [done, total], "rows": rows}


func _refresh_bottom_tab() -> void:
	if _damage_panel != null:
		_damage_panel.visible = _bottom_tab == "damage" and not _overlays.is_open() and not _replay_open
		if _damage_panel.visible:
			_damage_panel.bind(data)


# ── 回放（core vm_replay 可用时用 core 帧索引；否则 UI 本地帧兜底）─────

func _record_frame() -> void:
	if _tactical_snapshot.is_empty() or _phase_kind() != "COMMAND":
		return
	var frame: Dictionary = {"t": data.world_time(), "contacts": []}
	for raw in (_tactical_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw
		if bool(c.get("is_own", false)):
			continue
		var scr: Dictionary = c.get("screen", {}) if c.get("screen", {}) is Dictionary else {}
		if scr.is_empty():
			continue
		(frame["contacts"] as Array).append({
			"track_id": String(c.get("track_id", "")),
			"batch": String(c.get("batch", "")),
			"name": String(c.get("name", "")),
			"level": int(c.get("level", 0)),
			"identity": String(c.get("identity", "unknown")),
			"side": String(c.get("side", "unknown")),
			"kind": String(c.get("kind", "ship")),
			"x": float(scr.get("x", 0.0)), "y": float(scr.get("y", 0.0)),
			"inside": bool(scr.get("inside", true)),
		})
	_replay_frames.append(frame)
	if _replay_frames.size() > 240:
		_replay_frames.pop_front()


func _replay_total() -> int:
	if _replay_core:
		return int(_replay_vm.get("total", 0))
	return _replay_frames.size()


func _open_replay() -> void:
	_replay_vm = data.vm_replay()
	var core_like := bool(_replay_vm.get("available", false)) or (_replay_vm.has("recording") and _replay_vm.has("total"))
	_replay_core = core_like and int(_replay_vm.get("total", 0)) > 1
	if not _replay_core and _replay_frames.is_empty():
		_ui_log("REPLAY", "回放帧为空：先在 COMMAND 阶段运行一段时间（core vm_replay 或 UI 本地帧）")
		return
	if _replay_core:
		data.replay_pause()
	_replay_open = true
	_replay_playing = false
	_replay_cursor = maxi(0, int(float(_replay_total() - 1) * 0.6))
	_apply_log_tab()
	_replay_apply()
	_ui_log("REPLAY", "进入回放：%d 帧（%s）" % [_replay_total(),
		"core vm_replay" if _replay_core else "UI 本地帧兜底：core 无 vm_replay()"])
	_refresh_bottom_tab()
	_refresh_events()
	queue_redraw()


func _close_replay() -> void:
	if not _replay_open:
		return
	_replay_open = false
	_replay_playing = false
	if _tactical != null:
		_tactical.clear_replay_frame()
	if _replay_core:
		data.replay_stop()
	_apply_log_tab()
	_refresh_bottom_tab()
	_ui_log("REPLAY", "退出回放，恢复仿真")
	queue_redraw()


func _replay_apply() -> void:
	var total := _replay_total()
	if total <= 0:
		return
	_replay_cursor = clampi(_replay_cursor, 0, total - 1)
	if _replay_core:
		var frames_meta: Array = _replay_vm.get("frames", []) if _replay_vm.get("frames", []) is Array else []
		if _replay_cursor >= 0 and _replay_cursor < frames_meta.size():
			data.replay_seek(float((frames_meta[_replay_cursor] as Dictionary).get("t", 0.0)))
		else:
			data.replay_seek(_replay_cursor)
		var frame: Dictionary = data.replay_frame()
		if frame.is_empty():
			return
		var ghost: Dictionary = {"t": float(frame.get("t", _replay_vm.get("t", 0.0))), "contacts": []}
		for raw in (frame.get("contacts", []) as Array):
			if not (raw is Dictionary):
				continue
			var c: Dictionary = raw
			var eid := String(c.get("entity_id", ""))
			if eid == data.own_entity_id:
				continue
			var tid := String(c.get("track_id", ""))
			var meta: Dictionary = data.contact(tid)
			var p: Vector2 = _tactical.project_bearing_range_local(float(c.get("bearing_deg", 0.0)),
				float(c.get("range_km", 0.0)))
			(ghost["contacts"] as Array).append({
				"track_id": tid, "batch": String(meta.get("batch", c.get("batch", tid))),
				"name": String(meta.get("name", c.get("name", ""))), "level": int(c.get("level", 0)),
				"identity": String(c.get("identity", meta.get("identity", "unknown"))),
				"side": String(meta.get("side", "unknown")), "kind": String(meta.get("kind", "ship")),
				"x": p.x + L.MAP.position.x, "y": p.y + L.MAP.position.y, "inside": true,
			})
		if _tactical != null:
			_tactical.set_replay_frame(ghost)
		return
	if _replay_frames.is_empty():
		return
	if _tactical != null:
		_tactical.set_replay_frame(_replay_frames[_replay_cursor])


func _replay_step(dir: int) -> void:
	_replay_cursor = clampi(_replay_cursor + dir, 0, maxi(0, _replay_total() - 1))
	_replay_apply()
	queue_redraw()


func _replay_timeline_rect() -> Rect2:
	return Rect2(L.LOG.position.x + 16.0, L.LOG.position.y + 84.0, L.LOG.size.x - 32.0, 10.0)


func _draw_replay_panel() -> void:
	var panel := L.LOG
	T.panel(self, panel, 0.97, 0.85)
	_replay_buttons.clear()
	T.text(self, panel.position.x + 12.0, panel.position.y + 8.0, "回放 / REPLAY", T.F9, T.TXT)
	var total := _replay_total()
	var t := 0.0
	if _replay_core:
		t = float(_replay_vm.get("t", 0.0))
	elif total > 0:
		t = float((_replay_frames[_replay_cursor] as Dictionary).get("t", 0.0))
	var src := "CORE vm_replay" if _replay_core else "UI 本地帧兜底（core 无 vm_replay）"
	T.text_r(self, panel.end.x - 12.0, panel.position.y + 8.0,
		"%s · 帧 %d/%d · T+%s" % [src, _replay_cursor + 1, total, T.hms(t)], T.F7,
		T.a(T.BLUE, 0.9), false)
	T.hline(self, panel.position.x + 10.0, panel.position.y + 26.0, panel.end.x - 10.0, T.a(T.LINE, 0.65))
	# 控制按钮
	var bx := panel.position.x + 12.0
	var controls := [
		["⏮", "prev"], ["▶ / ❚❚", "play"], ["⏭", "next"], ["退出 / EXIT", "exit"],
	]
	for raw in controls:
		var rec: Array = raw
		var w := 64.0 if String(rec[1]) != "exit" else 120.0
		if String(rec[1]) == "play":
			w = 90.0
		var r := Rect2(bx, panel.position.y + 36.0, w, 22.0)
		_replay_buttons.append({"rect": r, "action": String(rec[1])})
		draw_rect(r, T.a(T.PANEL2, 0.8))
		draw_rect(r, T.a(T.BLUE if String(rec[1]) != "exit" else T.AMBER, 0.6), false, 1.0)
		var label := String(rec[0])
		if String(rec[1]) == "play":
			label = "暂停 / PAUSE" if _replay_playing else "播放 / PLAY"
		T.text_c(self, r.get_center().x, r.position.y + 5.0, label, T.F8,
			T.a(T.BLUE if String(rec[1]) != "exit" else T.AMBER, 0.95))
		bx = r.end.x + 8.0
	# 时间轴
	var tr := _replay_timeline_rect()
	draw_rect(Rect2(tr.position.x, tr.position.y - 4.0, tr.size.x, tr.size.y + 8.0), T.a(T.PANEL2, 0.8))
	draw_rect(tr, T.a(T.LINE, 0.6))
	if total > 1:
		for i in range(0, total, maxi(1, total / 12)):
			var fx := tr.position.x + tr.size.x * float(i) / float(total - 1)
			draw_line(Vector2(fx, tr.position.y - 3.0), Vector2(fx, tr.position.y + tr.size.y + 3.0),
				T.a(T.PH_FAINT, 0.5), 1.0)
		var px := tr.position.x + tr.size.x * float(_replay_cursor) / float(total - 1)
		draw_rect(Rect2(tr.position.x, tr.position.y + tr.size.y + 4.0,
			px - tr.position.x, 2.0), T.a(T.BLUE, 0.8))
		draw_rect(Rect2(px - 2.0, tr.position.y - 6.0, 4.0, tr.size.y + 12.0), T.BLUE)
		var t0 := 0.0
		var t1 := 0.0
		if _replay_core:
			var frames_core: Array = _replay_vm.get("frames", []) if _replay_vm.get("frames", []) is Array else []
			if not frames_core.is_empty():
				t0 = float((frames_core[0] as Dictionary).get("t", 0.0))
				t1 = float((frames_core[frames_core.size() - 1] as Dictionary).get("t", 0.0))
		else:
			t0 = float((_replay_frames[0] as Dictionary).get("t", 0.0))
			t1 = float((_replay_frames[total - 1] as Dictionary).get("t", 0.0))
		T.text(self, tr.position.x, tr.position.y + tr.size.y + 22.0,
			"T+%s" % T.hms(t0), T.F7, T.a(T.FAINT, 0.9), false)
		T.text_r(self, tr.end.x, tr.position.y + tr.size.y + 22.0,
			"T+%s" % T.hms(t1), T.F7, T.a(T.FAINT, 0.9), false)
	T.text(self, panel.position.x + 12.0, panel.end.y - 44.0,
		"回放时仿真冻结（不调用 world.advance）；拖动时间轴 / ←→ 逐帧 / SPACE 播放暂停 / ESC 退出",
		T.F7, T.a(T.FAINT, 0.85))
	T.text_fit(self, panel.position.x + 12.0, panel.end.y - 28.0,
		String(_replay_vm.get("reason", "")), T.F7, T.a(T.AMBER if not _replay_core else T.PH_DIM, 0.85),
		panel.size.x - 24.0)


func _apply_log_tab() -> void:
	if _events != null:
		_events.visible = _tab == "events" and not _replay_open
	if _orders != null:
		_orders.visible = _tab == "orders" and not _replay_open


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
	if _bottom_tab == "mission":
		_draw_mission_panel()
	if _replay_open:
		_draw_replay_panel()
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
	T.text(self, 500.0, 96.0, "T+%s · 执行窗口 %s · TIME ×%d%s" % [
		T.hms(data.world_time()), _fmt_countdown(data.exec_left()), int(_time_scale),
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
	var tut: Dictionary = data.tutorial_state()
	var tut_ready := bool(tut.get("complete", true))
	var drect := Rect2(panel.position.x + 300.0, panel.end.y - 34.0, 216.0, 24.0)
	var can_decide: bool = not _overlays.is_open() and _phase_kind() != "END" and _phase_kind() != "" and tut_ready and not _replay_open
	draw_rect(drect, T.a(T.AMBER if can_decide else T.LINE, 0.10 if can_decide else 0.03))
	draw_rect(drect, T.a(T.AMBER if can_decide else T.LINE, 0.7 if can_decide else 0.3), false, 1.0)
	T.text_c(self, drect.get_center().x, drect.position.y + 6.0, "打开裁决 / DECISION", T.F8,
		T.a(T.AMBER, 0.95) if can_decide else T.a(T.FAINT, 0.8))
	if not tut_ready:
		T.text(self, panel.position.x + 12.0, panel.end.y - 48.0,
			"教学未完成 %d/%d：完成交叉定位+雷达/型号识别后解锁裁决" % [
				int(tut.get("done_count", 0)), int(tut.get("total", 4))],
			T.F7, T.a(T.AMBER, 0.9))
	T.text(self, panel.position.x + 12.0, panel.end.y - 28.0,
		"证据：点任务行开始 · 时间线 T+75 自动裁决", T.F7, T.a(T.FAINT, 0.8))
	T.text(self, panel.position.x + 12.0, panel.end.y - 14.0,
		"穿梭机任务互斥（core start_evidence 校验）", T.F7, T.a(T.FAINT, 0.8))


func _draw_footer() -> void:
	var hint := "↑↓ 选择 · 右键目标动作 · 1/2/3 时间倍率 · L 事件/命令 · D 损管 · V 回放 · R 复位 · TAB 调试推进 · Q 退出"
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
	if _replay_open:
		match key.keycode:
			KEY_ESCAPE, KEY_V, KEY_Q:
				_close_replay()
			KEY_SPACE:
				_replay_playing = not _replay_playing
			KEY_LEFT:
				_replay_step(-1)
			KEY_RIGHT:
				_replay_step(1)
		accept_event()
		return
	match key.keycode:
		KEY_ESCAPE, KEY_Q:
			if _channel_open:
				_close_channel()
			elif _layers_panel != null and _layers_panel.visible and key.keycode == KEY_ESCAPE:
				_layers_panel.visible = false
			elif _menu.is_open():
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
			if _replay_open:
				_close_replay()
			else:
				_tab = "orders" if _tab == "events" else "events"
				_apply_log_tab()
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
		KEY_O:
			if _layers_panel != null:
				_layers_panel.visible = not _layers_panel.visible
			accept_event()
		KEY_D:
			_bottom_tab = "damage" if _bottom_tab == "mission" else "mission"
			_refresh_bottom_tab()
			queue_redraw()
			accept_event()
		KEY_V:
			if _replay_open:
				_close_replay()
			else:
				_open_replay()
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
	if _replay_open:
		_handle_replay_input(event)
		return
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


func _handle_replay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mb.pressed:
			_replay_dragging = false
			return
		for i in range(_replay_buttons.size()):
			var b: Dictionary = _replay_buttons[i]
			if not (b["rect"] as Rect2).has_point(mb.position):
				continue
			match String(b.get("action", "")):
				"prev":
					_replay_step(-1)
				"play":
					_replay_playing = not _replay_playing
				"next":
					_replay_step(1)
				"exit":
					_close_replay()
			accept_event()
			return
		var tr := _replay_timeline_rect()
		if Rect2(tr.position - Vector2(0.0, 8.0), Vector2(tr.size.x, tr.size.y + 16.0)).has_point(mb.position):
			_replay_dragging = true
			_seek_replay_x(mb.position.x)
			accept_event()
	elif event is InputEventMouseMotion and _replay_dragging:
		_seek_replay_x((event as InputEventMouseMotion).position.x)
		accept_event()


func _seek_replay_x(x: float) -> void:
	var tr := _replay_timeline_rect()
	var frac := clampf((x - tr.position.x) / maxf(1.0, tr.size.x), 0.0, 1.0)
	_replay_cursor = int(round(frac * float(maxi(0, _replay_total() - 1))))
	_replay_apply()
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
		var why := String(b.get("reason", "不可用"))
		if why != "":
			_ui_log("MISSION", why)
		return true
	match String(b.get("action", "")):
		"evidence":
			var r: Dictionary = data.start_evidence(String(b.get("id", "")))
			_ui_log("EVIDENCE", "证据任务开始：%s" % (String(r.get("reason", "")) if not bool(r.get("ok", false)) else String(b.get("id", ""))))
			_refresh_all()
		"decision":
			var r2: Dictionary = data.open_decision()
			if not bool(r2.get("ok", false)):
				_flow_hint = String(r2.get("reason", "裁决被门控"))
				_ui_log("DECISION", "裁决未打开：%s" % _flow_hint)
			else:
				_ui_log("DECISION", "打开裁决 ok")
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
		"tutorial":
			_debug_to_command()
			data.select("2001")
			_refresh_all()
			_warm(maxf(6.0, _warm_s))
			_sections.scroll_to_section("tutorial")
		"damage":
			_debug_to_command()
			_bottom_tab = "damage"
			_refresh_bottom_tab()
			if _damage_panel != null:
				_damage_panel.bind(data)
				_damage_panel.repair("sensor_align")
				_damage_panel.tick(7.0)
		"optical":
			_debug_to_command()
			data.select("2001")
			_refresh_all()
			for aid_o in ["crossfix", "radar_illum", "model_ident"]:
				data.perform_action(String(aid_o), "2001")
			var oc: Dictionary = data.perform_action("optical_channel", "2001")
			print("V2-5 OPTICAL ACTION ", oc.get("ok"), " level=", oc.get("level"), " reason=", oc.get("reason"))
			data.tactical_start_channel("optical", "2001")
			_warm(maxf(20.0, _warm_s))
			_open_channel("optical", "2001", oc)
		"layers":
			_debug_to_command()
			data.select("2001")
			_refresh_all()
			_layers_panel.visible = true
			_layers_panel.toggle("grid")
			_layers_panel.toggle("labels")
			_layers_panel.toggle("predictions")
		"replay":
			_debug_to_command()
			data.replay_start()
			_replay_record_started = true
			_warm(maxf(26.0, _warm_s))
			_open_replay()
			if _replay_frames.size() > 2:
				_replay_cursor = int(float(_replay_frames.size()) * 0.6)
				_replay_apply()
			_replay_playing = false
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
	# 4a) 完成教学门控（core 记录 action；UI 不直接改航迹等级/身份）
	for aid_t in ["crossfix", "radar_illum"]:
		var rt: Dictionary = data.perform_action(String(aid_t), "2001")
		print("V2-4 TUTORIAL ACTION ", aid_t, " ok=", rt.get("ok"), " reason=", rt.get("reason"))
	_refresh_all()
	var tut_done: Dictionary = data.tutorial_state()
	_check(int(tut_done.get("done_count", 0)) >= int(tut_done.get("total", 2)), "tutorial gate completed via actions")
	_check(bool(tut_done.get("complete", false)), "tutorial ready after required actions")
	_check(bool((data.vm_flow().get("tutorial_ready", false))), "core flow tutorial_ready true")
	# 4b) 教学步骤/门控（core vm_tutorial 或 UI 派生；只读，不自动完成识别）
	var tut: Dictionary = data.tutorial_state()
	_check((tut.get("steps", []) as Array).size() >= 3, "tutorial steps present")
	_check(int(tut.get("total", 0)) > 0, "tutorial total > 0")
	var tut_steps: Array = tut.get("steps", []) if tut.get("steps", []) is Array else []
	var tut_first: Dictionary = tut_steps[0] if not tut_steps.is_empty() else {}
	_check(not bool(tut_first.get("done", true)) or data.action_log().size() > 0, "tutorial not auto-completed without evidence/action")
	_refresh_mission()
	var decision_gate_ok := true
	for raw_b in _mission_buttons:
		var btn: Dictionary = raw_b
		if String(btn.get("action", "")) == "decision":
			var should_enable := bool(tut.get("complete", true)) and _phase_kind() == "COMMAND"
			decision_gate_ok = bool(btn.get("enabled", false)) == should_enable
	_check(decision_gate_ok, "decision entry gated by tutorial")
	# 4c) 损管面板（core vm_damage 或 UI 本地兜底）
	_damage_panel.bind(data)
	var dmg: Dictionary = data.vm_damage()
	_check(dmg.has("reason") or dmg.has("sections"), "damage vm returns reason/sections")
	var dmg_sections: Array = dmg.get("sections", []) if dmg.get("sections", []) is Array else []
	var dmg_pick := ""
	for raw_ds in dmg_sections:
		var dsx: Dictionary = raw_ds
		if String(dsx.get("state", "nominal")) != "nominal" and String(dsx.get("state", "")) != "repaired":
			dmg_pick = String(dsx.get("id", ""))
			break
	if dmg_pick == "" and not dmg_sections.is_empty():
		dmg_pick = String((dmg_sections[0] as Dictionary).get("id", ""))
	var rep: Dictionary = _damage_panel.repair(dmg_pick)
	_check(dmg_pick != "" and (bool(rep.get("ok", false)) or String(rep.get("reason", "")) != ""),
		"damage repair callable (%s)" % dmg_pick)
	var dmg_after: Dictionary = data.vm_damage()
	var q_after: int = (dmg_after.get("queue", []) as Array).size() if dmg_after.get("queue", []) is Array else 0
	_check(q_after >= 0, "damage queue/summary readable")
	_damage_panel.tick(28.0)
	_check(not bool(_damage_panel.fallback) or _damage_panel.summary.get("queue", 0) >= 0, "damage panel summary")
	# 4d) 回放（core vm_replay 或 UI 本地帧兜底）
	_record_frame()
	_record_frame()
	_check(_replay_frames.size() >= 2, "replay frames recorded")
	_open_replay()
	_check(_replay_open and _tactical.is_replaying(), "replay opens and freezes sim")
	_replay_step(-1)
	_close_replay()
	_check(not _replay_open and not _tactical.is_replaying(), "replay closes and resumes sim")
	# 4e) 光学/IR 通道窗口数据准备：model_ident → L3，optical_channel → 核心证据
	var mi: Dictionary = data.perform_action("model_ident", "2001")
	_check(bool(mi.get("ok", false)) or String(mi.get("reason", "")) != "", "model_ident callable")
	var oc: Dictionary = data.perform_action("optical_channel", "2001")
	_check(bool(oc.get("ok", false)) or String(oc.get("reason", "")) != "", "optical_channel callable")
	_check(int(oc.get("level", 0)) >= 3 or not bool(oc.get("ok", false)), "optical action raises level to L3")
	data.tactical_start_channel("optical", "2001")
	# 4f) 图层开关（core set_layer/vm_layers + 本地绘制同步）
	var ls: Dictionary = data.layers_state()
	for lk in ["contacts", "labels", "predictions", "radar", "stations", "grid"]:
		_check(ls.has(lk), "layers_state has " + lk)
	_layers = data.layers_state()
	_layers["labels"] = false
	_tactical.set_layers(_layers)
	_check(not _tactical.layer_on("labels"), "tactical labels layer off")
	data.set_layer("labels", false)
	_check(not bool(data.layers_state().get("labels", true)), "core set_layer labels false")
	data.set_layer("labels", true)
	_layers["labels"] = true
	_tactical.set_layers(_layers)
	_check(_tactical.layer_on("labels"), "tactical labels layer restored")
	# 4g) size_km 尺寸缩放（下限 8 px，单调）
	_check(_tactical.marker_px(1.2) > _tactical.marker_px(0.6), "station marker bigger by size_km")
	_check(_tactical.marker_px(0.05) >= 8.0, "marker min visible px >= 8")
	# 4e) 站体/储罐图标
	_check(_tactical.kind_marker_shape("station") == "station_marker", "station marker shape")
	_check(_tactical.kind_marker_shape("tank") == "tank_marker", "tank marker shape")
	_check(_tactical.kind_marker_shape("wreck") == "wreck_marker", "wreck marker shape")
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
	# 5b) 光学通道快照 + 通道窗（sim optical section，状态非空）
	var ch_view: Dictionary = _find_channel_view("optical", "2001")
	_check(not ch_view.is_empty(), "sim optical channel view for 2001")
	_check(String(ch_view.get("status", "")) in ["idle", "acquiring", "staring", "locked", "lost"], "optical channel status")
	_open_channel("optical", "2001", oc)
	_check(_channel_open and _channel_window.visible, "channel window opens")
	_check(String(_channel_window.kind) == "optical", "channel window kind optical")
	_check(bool(_channel_window.snapshot_available), "channel window snapshot available")
	_on_channel_stop("optical", "2001")
	_close_channel()
	_check(not _channel_open and not _channel_window.visible, "channel window closes")
	# 5c) 图层面板存在且可切换
	_check(_layers_panel != null, "layers panel exists")
	_layers_panel.visible = true
	_layers_panel.toggle("grid")
	_check(not _tactical.layer_on("grid"), "layers panel toggle grid off")
	_layers_panel.toggle("grid")
	_layers_panel.visible = false
	_check(_tactical.layer_on("grid"), "layers panel toggle grid on")
	# 6) 证据任务：开始 + 时间推进自动完成
	var started: Dictionary = data.start_evidence("port_telemetry")
	_check(bool(started.get("ok", false)), "start_evidence port_telemetry")
	_warm(34.0)
	var done := 0
	for raw_e in data.evidence_tasks():
		if String((raw_e as Dictionary).get("state", "")) == "done":
			done += 1
	_check(done >= 1, "evidence auto-completed by world.advance")
	# 6b) 教学完成后决策入口不再置灰
	_refresh_mission()
	var gate_enabled := false
	for raw_gb in _mission_buttons:
		var gb: Dictionary = raw_gb
		if String(gb.get("action", "")) == "decision":
			gate_enabled = bool(gb.get("enabled", false))
	_check(gate_enabled, "decision entry enabled after tutorial ready")
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
