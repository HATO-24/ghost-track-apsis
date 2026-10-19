extends Control

# V2 框架启动页：只验证数据层 + 动态列表 + 右栏 section + 动作可用性。
# 正式战术界面会在后续 V2-1/V2-2 替换此页。

const Palette := preload("res://scripts/pal.gd")
const Fonts := preload("res://scripts/fonts.gd")
const ScenarioScript := preload("res://core/scenario.gd")
const WorldScript := preload("res://core/world.gd")
const ActionsScript := preload("res://core/actions.gd")
const MissionScript := preload("res://core/mission.gd")

var scenario: V2Scenario
var world: V2World
var mission: V2Mission
var _t := 0.0
var _scroll := 0.0
var _row_rects: Array = []
var _entity_scroll := 0.0
var _selected_row := -1
var _shot_path := OS.get_environment("DSH_V2_SHOT")

func _ready() -> void:
	get_window().title = "GHOST TRACK // APSIS — V2 FRAMEWORK"
	get_window().size = Vector2i(1600, 900)
	var scr := DisplayServer.screen_get_size()
	get_window().position = Vector2i((scr.x - 1600) / 2, (scr.y - 900) / 2)
	scenario = ScenarioScript.load_file("res://content/scenario_l1.json")
	world = WorldScript.new()
	mission = MissionScript.new()
	var ok := world.load_scenario(scenario)
	print("V2 BOOT ok=", ok, " entities=", world.entities.size(), " own=", world.own_id,
		" errors=", scenario.errors)
	world.state_changed.connect(func(reason: String):
		print("V2 STATE ", reason, " selected=", world.selected_id)
		queue_redraw()
	)
	if world.own_id != "":
		world.select(world.own_id)
	set_process(true)
	if _shot_path != "":
		_capture.call_deferred()

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_window().borderless = true
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("V2 SHOT ", img.get_size(), " err=", err, " → ", _shot_path)
	get_tree().quit()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				var w := get_window()
				w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_EXCLUSIVE_FULLSCREEN
			KEY_F10:
				get_window().borderless = not get_window().borderless
			KEY_ESCAPE, KEY_Q:
				get_tree().quit()
			KEY_TAB:
				mission.advance(world.t)
				print("V2 PHASE ", mission.phase)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_entity_scroll = maxf(0.0, _entity_scroll - 40.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_entity_scroll += 40.0
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for i in range(_row_rects.size()):
				if (_row_rects[i] as Rect2).has_point(mb.position):
					_selected_row = i
					var es: Array = world.visible_entities()
					if i < es.size():
						world.select(es[i].id)
					accept_event()
					return
	elif event is InputEventMouseMotion:
		pass

func _font(cjk: bool, size: int) -> Font:
	return Fonts.cjk() if cjk else Fonts.mono()

func _txt(s: String, pos: Vector2, size: int, col: Color, cjk := true) -> void:
	var f := _font(cjk, size)
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _txt_r(s: String, pos: Vector2, size: int, col: Color, cjk := true) -> void:
	var f := _font(cjk, size)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, pos - Vector2(w, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _line(a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	draw_line(a, b, col, w)

func _panel(r: Rect2, col: Color, line: Color) -> void:
	draw_rect(r, col)
	draw_rect(r, line, false, 1.0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Palette.BG)
	# 标题
	_txt("GHOST TRACK // APSIS", Vector2(56, 58), 26, Palette.PH)
	_txt("FRAMEWORK V2 · DATA LAYER", Vector2(56, 78), 9, Palette.DIM, false)
	_txt_r("V2-0  BOOT PROBE", Vector2(1864, 58), 9, Palette.AMBER, false)
	_line(Vector2(56, 96), Vector2(1864, 96), Palette.LINE)
	# 左：动态接触列表
	var left := Rect2(56, 124, 620, 820)
	_panel(left, Palette.a(Palette.PANEL, 0.96), Palette.a(Palette.LINE, 0.8))
	_txt("接触 / CONTACTS", Vector2(left.position.x + 16, left.position.y + 22), 12, Palette.PH)
	var es: Array = world.visible_entities()
	_txt_r("%02d" % es.size(), Vector2(left.end.x - 16, left.position.y + 22), 12, Palette.PH_DIM, false)
	_line(Vector2(left.position.x + 16, left.position.y + 36), Vector2(left.end.x - 16, left.position.y + 36), Palette.a(Palette.LINE, 0.7))
	var clip := Rect2(left.position.x + 12, 176, left.size.x - 24, 748)
	draw_set_transform(clip.position)
	draw_rect(Rect2(0, 0, clip.size.x, clip.size.y), Palette.a(Palette.BG, 0.0))
	_row_rects.clear()
	var y := -_entity_scroll
	for i in range(es.size()):
		var e: V2Entity = es[i]
		var row := Rect2(0, y, 584, 58)
		if row.intersects(Rect2(0, 0, clip.size.x, clip.size.y)):
			var sel := e.id == world.selected_id
			draw_rect(row, Palette.a(Palette.PANEL2, 0.95 if sel else 0.55))
			draw_rect(row, Palette.a(Palette.PH, 0.65 if sel else 0.18), false, 1.0)
			_txt("[%s]" % e.id, Vector2(12, y + 20), 10, Palette.PH if sel else Palette.DIM, false)
			_txt(e.display_name(), Vector2(76, y + 20), 12, Palette.PH if sel else Palette.TXT)
			var side := "友方" if e.side == "friend" else ("敌方" if e.side == "hostile" else "未知")
			_txt("%s · %s" % [e.cls, side], Vector2(76, y + 38), 9, Palette.DIM)
			_txt_r("L%d" % e.track_level, Vector2(568, y + 20), 10, Palette.AMBER, false)
			_txt_r(e.identity, Vector2(568, y + 38), 8, Palette.DIM, false)
			_row_rects.append(row)
		y += 62
	draw_set_transform(Vector2.ZERO)
	# 右：动态 section
	var right := Rect2(704, 124, 1160, 820)
	_panel(right, Palette.a(Palette.PANEL, 0.96), Palette.a(Palette.LINE, 0.8))
	var sel_e := world.selected()
	if sel_e == null:
		_txt("NO SELECTION", Vector2(right.position.x + 24, right.position.y + 36), 14, Palette.FAINT, false)
		return
	var accent: Color = Palette.PH if sel_e.side == "friend" else (Palette.RED if sel_e.side == "hostile" else Palette.AMBER)
	_txt("选中对象 / SELECTED", Vector2(right.position.x + 24, right.position.y + 28), 9, accent)
	_txt(sel_e.display_name(), Vector2(right.position.x + 24, right.position.y + 58), 26, accent)
	_txt("[%s]  %s · %s · %s" % [sel_e.id, sel_e.name_en, sel_e.cls, sel_e.role],
		Vector2(right.position.x + 24, right.position.y + 82), 9, Palette.DIM)
	_line(Vector2(right.position.x + 24, right.position.y + 98), Vector2(right.end.x - 24, right.position.y + 98), Palette.a(Palette.LINE, 0.8))
	# 生成 sections：由 kind / capabilities 决定，不按批号写死。
	var sections := _sections_for(sel_e)
	var sy := right.position.y + 120
	for sec in sections:
		var sr := Rect2(right.position.x + 24, sy, right.size.x - 48, 1)
		_txt(String(sec["title"]), Vector2(sr.position.x, sy + 14), 9, Palette.FAINT)
		_line(Vector2(sr.position.x, sy + 22), Vector2(sr.end.x, sy + 22), Palette.a(Palette.LINE, 0.55))
		var lines: Array = sec["lines"]
		for i in range(lines.size()):
			var l: Array = lines[i]
			_txt(String(l[0]), Vector2(sr.position.x, sy + 42 + float(i) * 16.0), 9, Palette.DIM)
			_txt(String(l[1]), Vector2(sr.position.x + 190, sy + 42 + float(i) * 16.0), 9, Palette.TXT)
		sy += 26.0 + float(lines.size()) * 16.0
	# 动作 section
	var acts := ActionsScript.actions_for(world.own(), sel_e)
	_txt("动作 / TARGET ACTIONS", Vector2(right.position.x + 24, sy + 14), 9, Palette.FAINT)
	_line(Vector2(right.position.x + 24, sy + 22), Vector2(right.end.x - 24, sy + 22), Palette.a(Palette.LINE, 0.55))
	var ay := sy + 40.0
	for i in range(mini(acts.size(), 6)):
		var a: Dictionary = acts[i]
		var avail := bool(a.get("available", false))
		_txt("%02d  %s" % [i + 1, String(a.get("label", ""))], Vector2(right.position.x + 36, ay), 9,
			Palette.PH if avail else Palette.FAINT)
		if not avail:
			_txt_r(String(a.get("reason", "")), Vector2(right.end.x - 36, ay), 8, Palette.AMBER)
		ay += 18.0
	# 底部
	_txt("TAB 推进任务阶段 · F10 无边框 · F11 独占全屏 · ESC/Q 退出",
		Vector2(56, 1002), 8, Palette.FAINT)
	_txt_r("phase %s · entities %d · own %s" % [mission.phase, world.entities.size(), world.own_id],
		Vector2(1864, 1002), 8, Palette.PH_DIM, false)

func _sections_for(e: V2Entity) -> Array:
	var out: Array = []
	out.append({"title": "概览 / OVERVIEW", "lines": [
		["阵营", e.faction], ["身份", e.identity], ["威胁", e.threat], ["级别", "L%d" % e.track_level],
	]})
	var caps: Array = []
	for c in e.capabilities:
		caps.append([c, "具备"])
	out.append({"title": "能力 / CAPABILITIES", "lines": caps})
	if e.side != "friend":
		out.append({"title": "目标数据 / TARGET", "lines": [
			["批号", e.id], ["舰级", e.cls], ["角色", e.role],
		]})
	return out
