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
	# Right info
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(344, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	right.add_child(rv)
	rv.add_child(UiTheme.make_label("任务 / MISSION", false, 11, P.PH))
	rv.add_child(UiTheme.make_label("L4-02 Hammer → L1 Meridian", false, 9, P.TXT))
	rv.add_child(UiTheme.make_label("TOF 6 d 00 h · Δv 1822.6 m/s", true, 8, P.AMBER))
	rv.add_child(UiTheme.make_label("ARRIVAL 188.8 km / 0.97 km/s · GATE PASS", true, 8, P.PH_DIM))
	rv.add_child(UiTheme.make_label("ROE · WEAPONS HOLD / 仅自衛", false, 8, P.TXT))
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	rv.add_child(sep)
	rv.add_child(UiTheme.make_label("舰队 / FLEET", false, 9, P.PH_DIM))
	for row in [["[1000] APSIS", "FLAG · 0.8 km"], ["[1001] HARMATTAN", "CMD · 244.3 km"], ["[1002] FERRY", "ESC · 316.1 km"], ["[1003] WATCHTOWER", "RLY · 609.3 km"], ["[1004] DEEPWELL", "TNK · 744.0 km"]]:
		var h := HBoxContainer.new()
		var l := UiTheme.make_label(String(row[0]), true, 8, P.TXT)
		var r := UiTheme.make_label(String(row[1]), true, 8, P.a(P.DIM, 0.9))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(r)
		rv.add_child(h)
	rv.add_child(UiTheme.make_label("系统 / SYSTEMS", false, 9, P.PH_DIM))
	for sys in [["SENSOR", "READY"], ["LINK", "OK"], ["DAMAGE", "NOMINAL"], ["IFF", "SHADOW"], ["TEACHING", "0/20"]]:
		var h2 := HBoxContainer.new()
		h2.add_child(UiTheme.make_label(String(sys[0]), true, 7, P.a(P.FAINT, 0.9)))
		var r2 := UiTheme.make_label(String(sys[1]), true, 7, P.TXT)
		r2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(r2)
		rv.add_child(h2)
	var b := Button.new()
	b.text = "打开任务日志 / LOG"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _on_log("MISSION LOG OPEN (壳原型)"))
	rv.add_child(b)
	# Bottom log
	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 96)
	root_v.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	bv.add_child(UiTheme.make_label("指挥日志 / COMMAND LOG", false, 8, P.PH_DIM))
	_log_label = UiTheme.make_label("UI PROTO READY · Control + Theme + 9-Slice shell", true, 8, P.a(P.DIM, 0.95))
	bv.add_child(_log_label)
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
	_on_log("CONTACTS loaded from scenario_transit_l4_l1.json · %d" % rows.size())


func _seed_events() -> void:
	# UI 只发布示例 tactical.timer 事件；顶栏从 EventBus 订阅，过期由 TimeService 判定。
	for item in [["变轨窗口 / BURN WINDOW", 30.0, "burn"], ["入轨 / ARRIVAL", 120.0, "arrival"], ["链路 / LINK", 15.0, "link"]]:
		_bus.publish({"type": "tactical.timer", "t": _time.now_s(), "source": "ui_proto",
			"target": "top_bar", "payload": {"label": String(item[0]), "duration_s": float(item[1]), "kind": String(item[2])}})
	_on_log("EVENTBUS seeded 3 tactical.timer · time_service t=%.1fs" % _time.now_s())


func _process(delta: float) -> void:
	if _time != null:
		_time.tick(delta)
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
	_on_log("CONTACT.SELECT [%s] %s" % [String(data.get("id", "")), String(data.get("name", ""))])
	if _bus != null:
		_bus.publish({"type": "contact.select", "t": _time.now_s(), "source": "ui_proto.contact_list",
			"target": String(data.get("id", "")), "payload": {"index": index, "contact": data.duplicate(true)}})


func _on_log(text: String) -> void:
	print("[UI PROTO] ", text)
	_log_lines.append(text)
	while _log_lines.size() > 4:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = " · ".join(_log_lines)





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
