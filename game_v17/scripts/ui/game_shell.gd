extends Control

# 阶段1F 正式 UI Shell：基于 ui_proto 的 Control/Theme/9-Slice 布局，
# boot GameSession（track_table/story_state 可选）+ SaveService。
# 只新增本文件/场景；不改旧场景/project；不实现剧情/物理。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const ContactList := preload("res://scripts/ui/contact_list.gd")
const CommandLog := preload("res://scripts/ui/command_log.gd")
const CustomCursor := preload("res://scripts/ui/custom_cursor.gd")
const ShellBinder := preload("res://scripts/ui/shell_binder.gd")

var binder = null
var _top = null
var _contacts = null
var _right = null
var _command_log = null
var _cursor = null
var _selected: Dictionary = {}
var _page := "ship"
var _frames := 0
var _shot_path := ""
var _target_size := Vector2i(1920, 1080)
var _log_lines: Array[String] = []


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var sz := OS.get_environment("DSH_SHELL_SIZE")
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
	binder = ShellBinder.new()
	var ok: bool = binder.boot()
	binder.seed_timers()
	print("[GAME SHELL] boot=", str(ok), " errors=", str(binder.errors), " contacts=", binder.contacts.size(), " orders=", binder.commands.size())
	_build_shell()
	_contacts.set_contacts(binder.contacts)
	if not binder.contacts.is_empty():
		_selected = binder.contacts[0]
		_right.set_selected(_selected)
	_refresh_ui()
	set_process(true)
	if OS.get_environment("DSH_SHELL_SAVE_TEST") == "1":
		call_deferred("_run_save_test")
	if OS.get_environment("DSH_SHELL_SENSOR_TEST") == "1":
		call_deferred("_run_sensor_test")
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
	_top = ProdTop.new()
	_top.binder = binder
	_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.dot_action.connect(_on_dot)
	root_v.add_child(_top)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_v.add_child(body)
	_contacts = ContactList.new()
	_contacts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_contacts.show_no_threat = true  # 正式壳先显示全部 session 接触；威胁隐藏可由后续过滤开关启用
	_contacts.contact_selected.connect(_on_contact)
	_contacts.log_line.connect(_log)
	body.add_child(_contacts)
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	cv.add_child(UiTheme.make_label("战术态势 / TACTICAL PLOT", false, 11, P.PH))
	cv.add_child(UiTheme.make_label("GAME SHELL · SESSION TRACK / STORY READY", true, 7, P.a(P.FAINT, 0.9)))
	var map := MapShell.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(map)
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(344, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_panel)
	_right = ProdRight.new()
	_right.binder = binder
	_right.page_action.connect(_on_right_action)
	right_panel.add_child(_right)
	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 132)
	root_v.add_child(bottom)
	_command_log = CommandLog.new()
	_command_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_command_log)
	_cursor = CustomCursor.new()
	_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cursor.z_index = 100
	add_child(_cursor)


func _refresh_ui() -> void:
	if binder == null:
		return
	binder.refresh()
	if _contacts != null:
		_contacts.set_contacts(binder.contacts)
	if _right != null:
		_right.set_selected(_selected)
		_right.set_page(_page)
	if _command_log != null:
		_command_log.set_data(binder.commands, binder.events, "GAME SESSION · ORDERS", "SESSION BUS")
	if _top != null:
		_top.queue_redraw()


func _on_right_action(kind: String) -> void:
	if kind in ["RADAR", "EMCON", "IFF", "VIS", "IR"]:
		var res: Dictionary = binder.sensor_command(kind)
		_log("SENSOR %s · %s · %s" % [kind, "OK" if bool(res.get("ok", false)) else "FAILED", String(res.get("reason", ""))])
		if _right != null:
			_right.set_sensor_result(binder.sensor_result)
		_refresh_ui()
	else:
		_log("ACTION " + kind + " · signal only / no gameplay")


func _on_contact(index: int, data: Dictionary) -> void:
	_selected = data.duplicate(true)
	_page = "target" if String(data.get("type", "")) in ["unknown", "neutral"] else "ship"
	if _right != null:
		_right.set_selected(_selected)
		_right.set_page(_page)
	_log("SELECT [%s] %s · track=%s" % [String(data.get("id", "")), String(data.get("name", "")), String(data.get("track_id", "—"))])
	binder.signal_event("contact.select", String(data.get("id", "")), {"contact": data.duplicate(true), "index": index})


func _run_sensor_test() -> void:
	# 真实 SensorService API 一次：RADAR/EMCON/IFF/VIS/IR；结果写日志/右栏，不实现玩法。
	for kind in ["RADAR", "EMCON", "IFF", "VIS", "IR"]:
		_on_right_action(kind)
	if _right != null:
		_right.set_sensor_result("SENSOR TEST " + binder.sensor_result)


func _run_save_test() -> void:
	_on_dot("save")
	var meta: Dictionary = binder.save_service.load_metadata("save") if binder != null and binder.save_service != null else {}
	_log("SAVE TEST metadata=%s slot=%s" % [str(bool(meta.get("ok", false))), String((meta.get("meta", {}) as Dictionary).get("slot", ""))])
	if _top != null and binder != null:
		_top.set_save_result(binder.last_save_text + " · metadata " + ("OK" if bool(meta.get("ok", false)) else "FAIL"), binder.last_save_ok and bool(meta.get("ok", false)))


func _on_dot(kind: String) -> void:
	var intent := "save"
	if kind == "menu":
		intent = "save_and_menu"
	elif kind == "quit":
		intent = "save_and_quit"
	var res: Dictionary = binder.save(intent)
	if _top != null:
		_top.set_save_result(binder.last_save_text, binder.last_save_ok)
	_log("SAVE " + intent + " · " + binder.last_save_text)
	binder.signal_event("save.request", kind, {"intent": intent, "ok": binder.last_save_ok, "path": String(res.get("path", ""))})
	if _cursor != null:
		_cursor.set_state("point")


func _log(text: String) -> void:
	print("[GAME SHELL] ", text)
	_log_lines.append(text)
	while _log_lines.size() > 4:
		_log_lines.pop_front()


func _process(delta: float) -> void:
	if binder != null:
		binder.tick(delta)
	if _frames % 10 == 0:
		_refresh_ui()
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 36:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("GAME SHELL SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if binder == null or binder.session == null:
		return
	match event.keycode:
		KEY_SPACE:
			if bool(binder.session.time.paused):
				binder.session.resume()
			else:
				binder.session.pause()
			_log("TIME " + ("PAUSED" if bool(binder.session.time.paused) else "RUNNING"))
		KEY_1:
			binder.session.set_scale(1.0)
		KEY_H:
			if _contacts != null:
				_contacts.show_no_threat = not _contacts.show_no_threat
				_contacts.queue_redraw()
				_log("CONTACT no-threat display=" + str(_contacts.show_no_threat))
		KEY_2:
			binder.session.set_scale(10.0)
		KEY_3:
			binder.session.set_scale(60.0)
		KEY_4:
			binder.session.set_scale(300.0)


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
		draw_string(preload("res://scripts/fonts.gd").mono(), Vector2(8, size.y - 12), "GRID 48 px · SESSION TRACK PLOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P2.a(P.FAINT, 0.9))


class ProdTop extends Control:
	const PP := preload("res://scripts/pal.gd")
	const FF := preload("res://scripts/fonts.gd")
	const T := preload("res://scripts/ui/ui_theme.gd")
	signal dot_action(kind: String)
	var binder = null
	var _hover := -1
	var _save_text := ""
	var _save_ok := true
	var _dots := [["save", Color("#6DE6A2"), "存档 / SAVE"], ["menu", Color("#E8C24B"), "存档回主菜单 / SAVE+MENU"], ["quit", Color("#E2564A"), "存档退出桌面 / SAVE+QUIT"]]

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 72)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_save_result(text: String, ok: bool) -> void:
		_save_text = text
		_save_ok = ok
		queue_redraw()

	func _dot_rect(i: int) -> Rect2:
		return Rect2(Vector2(size.x - 20.0 - float(i) * 20.0 - 10.0, 5.0), Vector2(20, 20))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_hover = -1
			for i in range(3):
				if _dot_rect(i).has_point(event.position):
					_hover = i
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in range(3):
				if _dot_rect(i).has_point(event.position):
					dot_action.emit(String(_dots[i][0]))
					return

	func _port_clock() -> String:
		if binder == null or binder.session == null:
			return "—"
		var abs_s := float(binder.session.time.epoch_abs_s()) if binder.session.time != null else 0.0
		return "%02d:%02d:%02d" % [int(abs_s / 3600.0) % 24, int(abs_s / 60.0) % 60, int(abs_s) % 60]

	func _draw() -> void:
		var th: Theme = theme
		if th != null:
			draw_style_box(th.get_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(0, size.y - 1, size.x, 1), PP.a(PP.LINE, 0.85))
		var cjk := FF.cjk()
		var mono := FF.mono()
		var t_s := float(binder.session.now_s()) if binder != null and binder.session != null else 0.0
		var scale := float(binder.session.time.scale) if binder != null and binder.session != null else 1.0
		var paused := bool(binder.session.time.paused) if binder != null and binder.session != null else false
		draw_string(cjk, Vector2(16, 20), "指挥官 / COMMANDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.a(PP.PH, 0.75))
		draw_string(cjk, Vector2(16, 38), "指挥官 · 沧澜", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PP.PH)
		draw_string(mono, Vector2(16, 55), "MISSION T+%02d:%02d · L1 港内 %s · ×%.0f %s" % [int(t_s) / 60, int(t_s) % 60, _port_clock(), scale, "PAUSED" if paused else "RUNNING"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.a(PP.DIM, 0.95))
		draw_string(cjk, Vector2(360, 20), "动态计时 / EVENTBUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.a(PP.FAINT, 0.95))
		var timers: Array = binder.timers() if binder != null else []
		for i in range(timers.size()):
			var tm: Dictionary = timers[i]
			var remain := float(tm.get("remain", 0.0))
			var total := maxf(1.0, float(tm.get("total", 1.0)))
			var col: Color = PP.AMBER if String(tm.get("kind", "")) == "burn" else (PP.BLUE if String(tm.get("kind", "")) == "link" else PP.PH)
			var y := 37.0 + float(i) * 12.0
			draw_string(mono, Vector2(360, y), "%s %02d:%02d" % [String(tm.get("label", "")), int(remain) / 60, int(remain) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
			draw_rect(Rect2(544, y - 7, 88, 3), PP.a(PP.LINE, 0.9))
			draw_rect(Rect2(544, y - 7, 88.0 * clampf(remain / total, 0.0, 1.0), 3), PP.a(col, 0.9))
		var right := size.x - 150.0
		draw_string(cjk, Vector2(right, 20), "LINK / Δv / ROE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.a(PP.PH, 0.7))
		draw_string(mono, Vector2(right, 35), "LINK OK · 無線電 8s", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.TXT)
		draw_string(mono, Vector2(right, 49), "Δv %s · %s" % ["%.1f m/s" % binder.delta_v_mps if binder != null and binder.delta_v_ready else "NOT READY", "ROE HOLD" if binder != null and binder.roe_text.begins_with("WEAPONS") else "ROE NOT READY"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.a(PP.DIM, 0.9))
		draw_string(mono, Vector2(right, 62), "STORY " + ("READY" if binder != null and binder.story_vm.get("ready", false) else "NOT READY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.a(PP.FAINT, 0.9))
		for i in range(3):
			var dp := Vector2(size.x - 20.0 - float(i) * 20.0, 15.0)
			var col2: Color = _dots[i][1] as Color
			var hot := _hover == i
			draw_circle(dp, 7.0 if hot else 5.5, PP.a(col2, 0.22 if hot else 0.12))
			draw_circle(dp, 3.5, PP.a(col2, 0.95))
			draw_arc(dp, 8.0, 0, TAU, 20, PP.a(col2, 0.7 if hot else 0.35), 1.0, true)
			if hot:
				var tip := String(_dots[i][2])
				var tw := cjk.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 12.0
				var tr := Rect2(Vector2(size.x - tw - 10.0, 26.0), Vector2(tw, 17.0))
				draw_rect(tr, PP.a(PP.PANEL2, 0.98))
				draw_rect(tr, PP.a(col2, 0.65), false, 1.0)
				draw_string(cjk, Vector2(tr.position.x + 6, tr.position.y + 12), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.TXT)
		draw_string(mono, Vector2(size.x - 86, 34), "SAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.a(PP.FAINT, 0.9))
		if _save_text != "":
			draw_string(mono, Vector2(700, 66), _fit(_save_text, 96), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.PH if _save_ok else PP.RED)

	func _fit(s: String, n: int) -> String:
		return s if s.length() <= n else s.substr(0, n - 1) + "…"


class ProdRight extends Control:
	const PP := preload("res://scripts/pal.gd")
	const FF := preload("res://scripts/fonts.gd")
	signal page_action(kind: String)
	var binder = null
	var selected: Dictionary = {}
	var page := "ship"
	var _tabs: Array = []
	var _actions: Array = []
	var _sensor_actions: Array = []
	var _sensor_result := ""

	func _ready() -> void:
		custom_minimum_size = Vector2(344, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_selected(row: Dictionary) -> void:
		selected = row.duplicate(true)
		queue_redraw()

	func set_page(p: String) -> void:
		page = "target" if p == "target" else "ship"
		queue_redraw()

	func set_sensor_result(text: String) -> void:
		_sensor_result = text
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		for tab in _tabs:
			if (tab["rect"] as Rect2).has_point(event.position):
				set_page(String(tab["page"]))
				return
		for a in _actions:
			if (a["rect"] as Rect2).has_point(event.position):
				page_action.emit(String(a["kind"]))
				return
		for a in _sensor_actions:
			if (a["rect"] as Rect2).has_point(event.position):
				page_action.emit(String(a["kind"]))
				return

	func _draw() -> void:
		var th: Theme = theme
		if th != null:
			draw_style_box(th.get_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
		var cjk := FF.cjk()
		var mono := FF.mono()
		var f: Dictionary = binder.ship_fields(selected, page) if binder != null else {"title": "NOT READY", "source": "NO SESSION", "lines": ["session not booted"]}
		_tabs = [{"rect": Rect2(12, 4, 76, 18), "page": "ship"}, {"rect": Rect2(94, 4, 84, 18), "page": "target"}]
		for tab in _tabs:
			var active := String(tab["page"]) == page
			var tr: Rect2 = tab["rect"]
			draw_rect(tr, PP.a(PP.PH if active else PP.LINE, 0.10 if active else 0.05))
			draw_rect(tr, PP.a(PP.PH if active else PP.LINE, 0.65 if active else 0.3), false, 1.0)
			draw_string(mono, Vector2(tr.position.x + 6, tr.position.y + 13), "SHIP" if String(tab["page"]) == "ship" else "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.PH if active else PP.FAINT)
		draw_string(mono, Vector2(size.x - 126, 13), String(f.get("source", "NOT READY")), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, PP.a(PP.AMBER, 0.9))
		draw_string(cjk, Vector2(12, 40), String(f.get("title", "NOT READY")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PP.TXT)
		var y := 60.0
		for line in (f.get("lines", []) as Array):
			draw_string(mono, Vector2(12, y), _fit(String(line), 60), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.TXT if line != "DAMAGE NOT READY · 无 damage 组件" else PP.AMBER)
			y += 15.0
		y += 6.0
		draw_line(Vector2(10, y), Vector2(size.x - 10, y), PP.a(PP.LINE, 0.75), 1.0)
		y += 12.0
		# 真实 sensor 控制按钮（session.sensor_service）
		_sensor_actions.clear()
		draw_string(cjk, Vector2(12, y), "传感器 / SENSOR CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.PH_DIM)
		y += 6.0
		var sl := [["RADAR", "RADAR ON/OFF"], ["EMCON", "EMCON"], ["IFF", "IFF QUERY"], ["VIS", "VIS"], ["IR", "IR"]]
		for si in range(sl.size()):
			var sw := (size.x - 30.0) / 3.0 - 4.0
			var srect := Rect2(12.0 + float(si % 3) * (sw + 6.0), y + float(si / 3) * 24.0, sw, 19.0)
			_sensor_actions.append({"rect": srect, "kind": String(sl[si][0])})
			draw_rect(srect, PP.a(PP.PANEL2, 0.75))
			draw_rect(srect, PP.a(PP.LINE2, 0.6), false, 1.0)
			draw_string(mono, Vector2(srect.position.x + 5, srect.position.y + 13), String(sl[si][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, PP.TXT)
		y += 50.0
		if _sensor_result != "":
			draw_string(mono, Vector2(12, y), _fit(_sensor_result, 48), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, PP.AMBER)
		y += 12.0
		draw_string(cjk, Vector2(12, y), "按钮槽位 / ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.FAINT)
		_actions.clear()
		var labels := [["NAV", "导航 / NAV"], ["DMG", "损管 / DAMAGE"], ["OPT", "光学 / OPTICAL"], ["INFO", "信息 / INFO OPS"]]
		var start_y := size.y - 92.0
		for i in range(4):
			var bw := (size.x - 30.0) * 0.5 - 4.0
			var br := Rect2(12.0 + float(i % 2) * (bw + 8.0), start_y + float(i / 2) * 26.0, bw, 22.0)
			_actions.append({"rect": br, "kind": String(labels[i][0])})
			draw_rect(br, PP.a(PP.PANEL2, 0.8))
			draw_rect(br, PP.a(PP.LINE2, 0.65), false, 1.0)
			draw_string(cjk, Vector2(br.position.x + 6, br.position.y + 15), String(labels[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.TXT)
		draw_string(mono, Vector2(12, size.y - 12), "READ-ONLY · SESSION DATA · NO GAMEPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, PP.a(PP.FAINT, 0.9))

	func _fit(s: String, n: int) -> String:
		return s if s.length() <= n else s.substr(0, n - 1) + "…"
