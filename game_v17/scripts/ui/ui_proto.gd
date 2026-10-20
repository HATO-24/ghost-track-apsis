extends Control

# 完整游戏阶段1A：新 Control+Theme+9-Slice UI 壳原型。
# 独立场景 ui_proto.tscn；不改旧场景/project；只做壳与视觉。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const TopBar := preload("res://scripts/ui/top_bar.gd")
const ContactList := preload("res://scripts/ui/contact_list.gd")
const CustomCursor := preload("res://scripts/ui/custom_cursor.gd")
const TimeService := preload("res://scripts/core/time_service.gd")
const EventBus := preload("res://scripts/core/event_bus.gd")
const GameSession := preload("res://scripts/core/game_session.gd")
const SaveService := preload("res://scripts/core/save_service.gd")
const RightPanel := preload("res://scripts/ui/right_panel.gd")
const CommandLog := preload("res://scripts/ui/command_log.gd")
const CONTACT_SOURCE := "res://framework/content/scenario_transit_l4_l1.json"
const TRACK_SCHEMA := "res://config/schema/track.json"
const SAVE_ROOT := "user://saves"

var _top
var _contacts
var _cursor
var _log_label: Label
var _frames := 0
var _shot_path := ""
var _target_size := Vector2i(1920, 1080)

var _log_lines: Array[String] = []
var _session = null
var _save = null
var _bus = null
var _right_panel = null
var _command_log = null
var _selected_contact: Dictionary = {}


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var sz := OS.get_environment("DSH_PROTO_SIZE")
	if sz == "":
		sz = "1920x1080"
	var parts := sz.split("x")
	if parts.size() == 2:
		_target_size = Vector2i(int(parts[0]), int(parts[1]))
	var win := get_window()
	if win != null:
		win.size = _target_size
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_session = GameSession.new()
	var boot_res: Dictionary = _session.boot({"orders": [
		{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
	]})
	_save = SaveService.new(SAVE_ROOT)
	_save.setup(SAVE_ROOT)
	_bus = _session.bus
	_build_shell()
	_top.bind_services(_session, _bus)
	_load_contacts()
	_seed_events()
	_refresh_command_log()
	set_process(true)
	if OS.get_environment("DSH_UI_SAVE_TEST") == "1":
		call_deferred("_run_save_test")
	if _shot_path != "":
		get_window().size = _target_size
		Input.warp_mouse(Vector2(_target_size) * 0.5)


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = P.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	margin.add_child(root_v)
	# Top bar
	_top = TopBar.new()
	_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.dot_action.connect(_on_dot_action)
	root_v.add_child(_top)
	# Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_v.add_child(body)
	_contacts = ContactList.new()
	_contacts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_contacts.contact_selected.connect(_on_contact)
	_contacts.log_line.connect(_on_log)
	body.add_child(_contacts)
	# Center map shell
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	center.add_child(cv)
	cv.add_child(UiTheme.make_label("战术态势 / TACTICAL PLOT", false, 11, P.PH))
	cv.add_child(UiTheme.make_label("NAV FRAME · L1 · 9-SLICE SHELL", true, 7, P.a(P.FAINT, 0.9)))
	var map := MapShell.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(map)
	# Right panel（舰船/目标页 + 按钮槽位）
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(344, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_right_panel = RightPanel.new()
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.page_action.connect(func(kind): _on_log("ACTION " + kind + " · READ-ONLY / NOT WIRED"))
	right.add_child(_right_panel)
	# Bottom command queue + event log
	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 132)
	root_v.add_child(bottom)
	_command_log = CommandLog.new()
	_command_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_command_log)
	# custom cursor last
	_cursor = CustomCursor.new()
	_cursor.custom_minimum_size = Vector2.ZERO
	_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cursor.z_index = 100
	add_child(_cursor)


func _load_contacts() -> void:
	var rows: Array = []
	var snap: Dictionary = _session.snapshot() if _session != null else {}
	var ents: Array = snap.get("entities", []) if snap.get("entities", []) is Array else []
	var by_id: Dictionary = {}
	for raw in ents:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var eid := String(e.get("id", ""))
		by_id[eid] = e
		var kind := String(e.get("kind", "ship"))
		var fl: Dictionary = e.get("flags", {}) if e.get("flags", {}) is Dictionary else {}
		var badge := "PORT" if kind == "station" else ("FLAGSHIP" if bool(fl.get("flagship", false)) else "FRIENDLY")
		rows.append({"id": String(e.get("batch", eid)), "entity_id": eid, "name": String(e.get("name", "")),
			"cls": kind.to_upper(), "type": "station" if kind == "station" else "friendly", "side": "friend",
			"threat": "none", "badge": badge, "session": true})
	# track schema 示例：明确 DEMO，不混入 session entities
	if FileAccess.file_exists(TRACK_SCHEMA):
		var f := FileAccess.open(TRACK_SCHEMA, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.get("example") is Dictionary:
				var ex: Dictionary = parsed.get("example")
				rows.append({"id": "TRACK-EX", "entity_id": "TRACK-EX", "name": "TRACK EXAMPLE / DEMO",
					"cls": "track schema · level %d" % int(ex.get("level", 0)), "type": "unknown",
					"side": "unknown", "threat": "pending", "badge": "DEMO TRACK", "session": false,
					"track": ex.duplicate(true)})
	if rows.is_empty():
		rows = [{"id": "----", "name": "NO CONTACT DATA", "cls": "session 未就绪", "type": "unknown", "side": "unknown", "threat": "pending", "badge": "NOT READY"}]
	_contacts.set_contacts(rows)
	if _right_panel != null:
		_right_panel.set_snapshot(snap)
		if not rows.is_empty():
			_right_panel.set_selected(rows[0])
	_on_log("SESSION contacts=%d + track DEMO · orders=%d" % [ents.size(), int((snap.get("orders_summary", {}) as Dictionary).get("orders", 0))])


func _seed_events() -> void:
	# UI 只发布示例 tactical.timer；Session.bus 真实事件由 topbar 订阅。
	for item in [["变轨窗口 / BURN WINDOW", 30.0, "burn"], ["入轨 / ARRIVAL", 120.0, "arrival"], ["链路 / LINK", 15.0, "link"]]:
		_bus.publish({"type": "tactical.timer", "t": _session.now_s(), "source": "ui_proto",
			"target": "top_bar", "payload": {"label": String(item[0]), "duration_s": float(item[1]), "kind": String(item[2])}})
	_on_log("SESSION EVENTBUS seeded 3 tactical.timer · t=%.1fs" % _session.now_s())


func _refresh_command_log() -> void:
	if _command_log == null or _session == null:
		return
	var snap: Dictionary = _session.snapshot()
	var comps: Dictionary = snap.get("components", {}) if snap.get("components", {}) is Dictionary else {}
	var om: Dictionary = comps.get("orders", {}) if comps.get("orders", {}) is Dictionary else {}
	var raw_orders: Array = om.get("orders", []) if om.get("orders", []) is Array else []
	var cmds: Array = []
	for raw in raw_orders:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = raw
		cmds.append({
			"id": String(o.get("order_id", "—")), "state": String(o.get("status", "—")),
			"actor": String(o.get("issuer_id", "—")), "target": ",".join(o.get("target_ids", [])) if o.get("target_ids") is Array else "—",
			"action": String(o.get("action", "—")), "mode": String(o.get("mode", "—")),
			"delay": "%.1fs" % float(o.get("delivery_delay_s", 0.0)),
		})
	var events: Array = _session.bus.recent(8) if _session.bus != null else []
	_command_log.set_data(cmds, events, "GAME SESSION · ORDERS", "SESSION BUS")


func _process(delta: float) -> void:
	if _session != null:
		_session.tick(delta)
	if _frames % 10 == 0:
		_refresh_command_log()
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 36:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("UI PROTO SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _session == null:
		return
	match event.keycode:
		KEY_SPACE:
			if bool(_session.time.paused):
				_session.resume()
			else:
				_session.pause()
			_on_log("SESSION TIME %s · scale ×%.0f" % ["PAUSED" if bool(_session.time.paused) else "RUNNING", float(_session.time.scale)])
		KEY_1:
			_session.set_scale(1.0); _on_log("SESSION TIMESCALE ×1")
		KEY_2:
			_session.set_scale(10.0); _on_log("SESSION TIMESCALE ×10")
		KEY_3:
			_session.set_scale(60.0); _on_log("SESSION TIMESCALE ×60")
		KEY_4:
			_session.set_scale(300.0); _on_log("SESSION TIMESCALE ×300")


func _on_dot_action(kind: String) -> void:
	var intent := "save"
	if kind == "menu":
		intent = "save_and_menu"
	elif kind == "quit":
		intent = "save_and_quit"
	var res: Dictionary = {}
	if _save != null and _session != null:
		res = _save.save_with_intent(_session, intent, {"chapter": "stage1e", "location": "ui_proto"})
	var ok := bool(res.get("ok", false))
	var status := ""
	if ok:
		status = "SAVED slot=%s · %sB · %s" % [String(res.get("slot", "")), str(int(res.get("bytes", 0))), String(res.get("checksum", "")).substr(0, 8)]
		if intent == "save_and_menu":
			status += " · should_show_menu=" + str(bool(res.get("should_show_menu", false)))
		elif intent == "save_and_quit":
			status += " · should_exit=" + str(bool(res.get("should_exit", false)))
	else:
		status = "SAVE FAILED · " + String(res.get("reason", "not_ready"))
	if _top != null:
		_top.set_save_result(status, ok)
	_on_log("SAVE intent=%s · %s · path=%s" % [intent, "OK" if ok else "FAILED", String(res.get("path", ""))])
	if _session != null and _session.bus != null:
		_session.bus.publish({"type": "save.request", "t": _session.now_s(), "source": "ui_proto.top_bar",
			"target": kind, "payload": {"intent": intent, "ok": ok, "path": String(res.get("path", "")), "save_implemented": true}})
	if _cursor != null:
		_cursor.set_state("point")


func _run_save_test() -> void:
	# 仅 DSH_UI_SAVE_TEST=1 执行：boot 后真实 save + load metadata + UI refresh；默认不写。
	var res: Dictionary = _save.save_with_intent(_session, "save", {"chapter": "stage1e", "location": "ui_proto.test"})
	var ok := bool(res.get("ok", false))
	_on_log("SAVE TEST save=%s slot=%s path=%s" % ["OK" if ok else "FAIL", String(res.get("slot", "")), String(res.get("path", ""))])
	var meta: Dictionary = _save.load_metadata("save")
	_on_log("SAVE TEST metadata=%s slot=%s updated=%s" % [str(bool(meta.get("ok", false))), String((meta.get("meta", {}) as Dictionary).get("slot", "")), str(float((meta.get("meta", {}) as Dictionary).get("updated_at", 0.0)))])
	_top.set_save_result("SAVED save · %sB · metadata %s" % [str(int(res.get("bytes", 0))), "OK" if bool(meta.get("ok", false)) else "FAIL"], ok and bool(meta.get("ok", false)))
	_refresh_command_log()


func _on_contact(index: int, data: Dictionary) -> void:
	_selected_contact = data.duplicate(true)
	if _right_panel != null:
		_right_panel.set_snapshot(_session.snapshot() if _session != null else {})
		_right_panel.set_selected(_selected_contact)
	_on_log("CONTACT.SELECT [%s] %s" % [String(data.get("id", "")), String(data.get("name", ""))])
	if _bus != null:
		_bus.publish({"type": "contact.select", "t": _session.now_s() if _session != null else 0.0, "source": "ui_proto.contact_list",
			"target": String(data.get("id", "")), "payload": {"index": index, "contact": data.duplicate(true)}})


func _on_log(text: String) -> void:
	print("[UI PROTO] ", text)
	_log_lines.append(text)
	while _log_lines.size() > 4:
		_log_lines.pop_front()
	if _command_log != null:
		_refresh_command_log()





func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()


class MapShell extends Control:
	const P2 := preload("res://scripts/pal.gd")

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), P2.a(P.EARTH, 0.65))
		draw_rect(Rect2(Vector2.ZERO, size), P2.a(P.LINE, 0.5), false, 1.0)
		var step := 48.0
		var gx := 0.0
		while gx < size.x:
			draw_line(Vector2(gx, 0), Vector2(gx, size.y), P2.a(P.PH_FAINT, 0.18), 1.0)
			gx += step
		var gy := 0.0
		while gy < size.y:
			draw_line(Vector2(0, gy), Vector2(size.x, gy), P2.a(P.PH_FAINT, 0.18), 1.0)
			gy += step
		var c := size * 0.5
		draw_circle(c, 2.5, P2.PH)
		draw_arc(c, 28.0, 0, TAU, 48, P2.a(P.PH, 0.35), 1.0, true)
		draw_arc(c, 78.0, 0, TAU, 64, P2.a(P.PH_DIM, 0.25), 1.0, true)
		draw_arc(c, 140.0, 0, TAU, 80, P2.a(P.PH_DIM, 0.18), 1.0, true)
		draw_line(Vector2(c.x - 30, c.y), Vector2(c.x + 30, c.y), P2.a(P.PH, 0.7), 1.0)
		draw_line(Vector2(c.x, c.y - 30), Vector2(c.x, c.y + 30), P2.a(P.PH, 0.7), 1.0)
		draw_polyline(PackedVector2Array([c + Vector2(-60, 40), c + Vector2(-20, 21), c + Vector2(12, -8), c + Vector2(52, -24)]), P2.a(P.AMBER, 0.7), 1.0)
		draw_circle(c + Vector2(52, -24), 3.0, P2.AMBER)
		draw_string(preload("res://scripts/fonts.gd").mono(), Vector2(8, size.y - 12), "GRID 48 px · LAYOUT CONTROL / NOT PIXEL-HUD", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P2.a(P.FAINT, 0.9))
