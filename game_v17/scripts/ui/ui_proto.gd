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
const RightPanel := preload("res://scripts/ui/right_panel.gd")
const CommandLog := preload("res://scripts/ui/command_log.gd")
const CONTACT_SOURCE := "res://framework/content/scenario_transit_l4_l1.json"

var _top
var _contacts
var _cursor
var _log_label: Label
var _frames := 0
var _shot_path := ""
var _target_size := Vector2i(1920, 1080)

var _log_lines: Array[String] = []
var _time = null
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
	_time = TimeService.new({})
	_time.setup({"epoch_s": 760.8, "scale": 1.0})
	_bus = EventBus.new({})
	_bus.setup({})
	_build_shell()
	_top.bind_services(_time, _bus)
	_load_contacts()
	_seed_events()
	_refresh_command_log()
	set_process(true)
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
	if FileAccess.file_exists(CONTACT_SOURCE):
		var f := FileAccess.open(CONTACT_SOURCE, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				var ents: Array = parsed.get("entities", []) if parsed.get("entities", []) is Array else []
				for raw in ents:
					if not (raw is Dictionary):
						continue
					var e: Dictionary = raw
					var kind := String(e.get("kind", "ship"))
					var side := String(e.get("side", "friend"))
					var ttype := "station" if kind == "station" else ("friendly" if side == "friend" else ("unknown" if side == "unknown" else "neutral"))
					var threat := "none" if side == "friend" else ("med" if side == "unknown" else "low")
					var badge := "PORT" if kind == "station" else ("FLAGSHIP" if side == "friend" and String(e.get("id", "")) == "apsis" else ("UNKNOWN" if side == "unknown" else "FRIENDLY"))
					rows.append({"id": String(e.get("batch", e.get("id", ""))), "name": String(e.get("name", "")),
						"cls": String(e.get("class", e.get("role", ""))), "type": ttype, "side": side,
						"threat": threat, "badge": badge})
	if rows.is_empty():
		rows = [{"id": "----", "name": "NO CONTACT DATA", "cls": "content 未加载", "type": "unknown", "side": "unknown", "threat": "pending", "badge": "NOT READY"}]
	_contacts.set_contacts(rows)
	if not rows.is_empty() and _right_panel != null:
		_right_panel.set_selected(rows[0])
	_on_log("CONTACTS loaded from scenario_transit_l4_l1.json · %d" % rows.size())


func _seed_events() -> void:
	# UI 只发布示例 tactical.timer 事件；顶栏从 EventBus 订阅，过期由 TimeService 判定。
	for item in [["变轨窗口 / BURN WINDOW", 30.0, "burn"], ["入轨 / ARRIVAL", 120.0, "arrival"], ["链路 / LINK", 15.0, "link"]]:
		_bus.publish({"type": "tactical.timer", "t": _time.now_s(), "source": "ui_proto",
			"target": "top_bar", "payload": {"label": String(item[0]), "duration_s": float(item[1]), "kind": String(item[2])}})
	_on_log("EVENTBUS seeded 3 tactical.timer · time_service t=%.1fs" % _time.now_s())


func _refresh_command_log() -> void:
	if _command_log == null or _bus == null:
		return
	var events: Array = _bus.recent(8)
	var demo_commands: Array = [
		{"id": "ORD-0007", "state": "QUEUED", "actor": "指挥官", "target": "哈马丹 1001", "action": "SHADOW", "mode": "LD", "delay": "8.0s"},
		{"id": "ORD-0008", "state": "TRANSMITTED", "actor": "哈马丹 1001", "target": "L1 港", "action": "SCAN", "mode": "LR", "delay": "1.0s"},
		{"id": "ORD-0009", "state": "EXECUTING", "actor": "指挥官", "target": "远地点 1000", "action": "HOLD", "mode": "LD", "delay": "—"},
	]
	_command_log.set_data(demo_commands, events, "DEMO · NO GAMESESSION", "EVENTBUS · REAL")


func _process(delta: float) -> void:
	if _time != null:
		_time.tick(delta)
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
	if _time == null:
		return
	match event.keycode:
		KEY_SPACE:
			if _time.paused:
				_time.resume()
			else:
				_time.pause()
			_on_log("TIME %s · scale ×%.0f" % ["PAUSED" if _time.paused else "RUNNING", _time.scale])
		KEY_1:
			_time.set_scale(1.0); _on_log("TIMESCALE ×1")
		KEY_2:
			_time.set_scale(10.0); _on_log("TIMESCALE ×10")
		KEY_3:
			_time.set_scale(60.0); _on_log("TIMESCALE ×60")
		KEY_4:
			_time.set_scale(300.0); _on_log("TIMESCALE ×300")


func _on_dot_action(kind: String) -> void:
	_on_log("DOT " + kind + " · signal only · save not implemented")
	if _cursor != null:
		_cursor.set_state("point")


func _on_contact(index: int, data: Dictionary) -> void:
	_selected_contact = data.duplicate(true)
	if _right_panel != null:
		_right_panel.set_selected(_selected_contact)
	_on_log("CONTACT.SELECT [%s] %s" % [String(data.get("id", "")), String(data.get("name", ""))])
	if _bus != null:
		_bus.publish({"type": "contact.select", "t": _time.now_s(), "source": "ui_proto.contact_list",
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
