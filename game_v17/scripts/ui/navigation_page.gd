extends Control

# 阶段3D 导航/离港页：接 PrologueController 真实轨迹/窗口/状态机。
# 只读显示 + 手动按钮；不自动推进、不接物理/剧情分支/存档。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const PrologueController := preload("res://scripts/core/prologue_controller.gd")
const FlightMap := preload("res://scripts/ui/flight_map.gd")
const TEACHING_PATH := "res://framework/content/teaching_l4_l1.json"

var controller = null
var map = null
var _status: Label = null
var _time_label: Label = null
var _state_label: Label = null
var _teach_label: Label = null
var _playing := false
var _speed := 60.0
var _frames := 0
var _shot_path := ""
var _logs: Array[String] = []
var _teach_steps: Dictionary = {}
var _status_text := ""


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_boot_controller()
	_load_teaching()
	_build_shell()
	_refresh()
	set_process(true)
	if OS.get_environment("DSH_NAV_TEST") == "1":
		call_deferred("_run_nav_test")
	if _shot_path != "":
		get_window().size = Vector2i(1920, 1080)
		Input.warp_mouse(Vector2(1920, 1080) * 0.5)


func _boot_controller() -> void:
	controller = PrologueController.new({})
	var pname := OS.get_environment("DSH_PLAYER_NAME")
	if pname == "":
		pname = String(get_tree().root.get_meta("player_name", "沧澜"))
	if pname == "":
		pname = "沧澜"
	var rs: Dictionary = controller.submit_name(pname)
	if not bool(rs.get("ok", false)):
		print("[NAV PAGE] name failed ", str(rs))
	if bool(controller.ready):
		controller.confirm_briefing()
		controller.accept_handover()
	print("[NAV PAGE] boot name=%s state=%s t=%.0f tof=%.0f fleet=%d timeline=%d" % [
		controller.player_name, controller.state, controller.t_s, controller.tof_s,
		controller.fleet().size(), controller.timeline().size()])


func _load_teaching() -> void:
	_teach_steps = {}
	if not FileAccess.file_exists(TEACHING_PATH):
		return
	var f := FileAccess.open(TEACHING_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for raw in (parsed.get("steps", []) if parsed.get("steps", []) is Array else []):
			if raw is Dictionary:
				_teach_steps[String((raw as Dictionary).get("id", ""))] = raw


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
	var rootv := VBoxContainer.new()
	rootv.add_theme_constant_override("separation", 8)
	margin.add_child(rootv)
	# top
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 78)
	rootv.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	tv.add_child(th)
	th.add_child(UiTheme.make_label("导航 / NAVIGATION · 离港", false, 14, P.PH))
	_state_label = UiTheme.make_label("", true, 8, P.PH_DIM)
	th.add_child(_state_label)
	_time_label = UiTheme.make_label("", true, 8, P.TXT)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	th.add_child(_time_label)
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	tv.add_child(cb)
	var play := Button.new()
	play.text = "播放 / PLAY"
	play.pressed.connect(func(): _playing = true; _refresh())
	cb.add_child(play)
	var pause := Button.new()
	pause.text = "暂停 / PAUSE"
	pause.pressed.connect(func(): _playing = false; _refresh())
	cb.add_child(pause)
	for sp in [1.0, 60.0, 3600.0]:
		var b := Button.new()
		b.text = "×%d" % int(sp)
		b.pressed.connect(func(): _speed = sp; _refresh())
		cb.add_child(b)
	cb.add_child(UiTheme.make_label("advance_time 只在 NAVIGATION/DEPARTURE_REQUEST/BURN_WINDOW/CRUISE", true, 7, P.a(P.FAINT, 0.9)))
	# body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	rootv.add_child(body)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UiTheme.make_label("导航教学 / TEACHING", false, 10, P.PH))
	_teach_label = UiTheme.make_label("", false, 8, P.TXT)
	_teach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_teach_label)
	lv.add_child(UiTheme.make_label("步骤只手动完成，不自动推进。", true, 7, P.a(P.FAINT, 0.9)))
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	cv.add_child(UiTheme.make_label("L4-02 → L1 · 真实轨迹 / TIMELINE", false, 10, P.PH))
	map = FlightMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(map)
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(362, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 7)
	right.add_child(rv)
	rv.add_child(UiTheme.make_label("操作 / OPERATIONS", false, 10, P.PH))
	for item in [["SET DEST L1", "_set_dest"], ["REQUEST DEPARTURE", "_request_departure"], ["AUTHORIZE BURN", "_authorize_burn"], ["IGNITE", "_ignite"], ["ARRIVE", "_arrive"], ["COMPLETE", "_complete"]]:
		var b := Button.new()
		b.text = String(item[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, String(item[1])))
		rv.add_child(b)
	var sep := HSeparator.new()
	rv.add_child(sep)
	_status = UiTheme.make_label("READY · 等待手动操作", true, 8, P.AMBER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	rv.add_child(UiTheme.make_label("不自动推进 · 失败显示 reason · 不接物理/剧情/存档", true, 7, P.a(P.FAINT, 0.9)))
	# bottom
	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 84)
	rootv.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	bv.add_child(UiTheme.make_label("日志 / LOG", false, 8, P.PH_DIM))
	_log_label = UiTheme.make_label("NAV PAGE READY", true, 7, P.a(P.DIM, 0.9))
	bv.add_child(_log_label)
	map.set_controller(controller)


var _log_label: Label


func _run_nav_test() -> void:
	# 仅在 DSH_NAV_TEST=1 下验证按钮真实 API；正常页面不自动推进。
	_set_dest()
	_request_departure()
	_authorize_burn()
	_ignite()
	var adv: Dictionary = controller.advance_time(controller.WINDOW_OPEN_S + 1.0 - controller.t_s)
	_log("TEST advance window · " + str(bool(adv.get("ok", false))))
	_ignite()
	controller.advance_time(float(controller.tof_s) + 1.0)
	_arrive()
	_complete()
	_log("NAV TEST COMPLETE state=" + controller.state)


func _set_dest() -> void:
	_result(controller.set_destination(controller.target_id), "SET DEST " + controller.target_id)


func _request_departure() -> void:
	_result(controller.request_departure(), "REQUEST DEPARTURE")


func _authorize_burn() -> void:
	_result(controller.authorize_burn(), "AUTHORIZE BURN")


func _ignite() -> void:
	_result(controller.ignite(), "IGNITE")


func _arrive() -> void:
	_result(controller.arrive(), "ARRIVE")


func _complete() -> void:
	var res: Dictionary = controller.complete()
	_result(res, "COMPLETE")
	if bool(res.get("ok", false)) and controller.state == "COMPLETE":
		var saved_name := String(controller.player_name)
		if saved_name == "":
			saved_name = "沧澜"
		get_tree().root.set_meta("player_name", saved_name)
		OS.set_environment("DSH_PLAYER_NAME", saved_name)
		_log("FLOW COMPLETE → port_page.tscn · name=" + saved_name)
		get_tree().change_scene_to_file("res://port_page.tscn")


func _result(res: Dictionary, action: String) -> void:
	var ok := bool(res.get("ok", false))
	var text := "%s · %s%s" % [action, "OK" if ok else "FAILED", "" if ok else " · " + String(res.get("reason", ""))]
	_log(text)
	_status_text = text
	_status.text = text
	_status.add_theme_color_override("font_color", P.PH if ok else P.RED)
	_refresh()


func _refresh() -> void:
	if controller == null:
		return
	_state_label.text = "STATE %s · NAME %s" % [controller.state, controller.player_name]
	_time_label.text = "T+%s / TOF %s · WINDOW %s–%s · %s" % [
		_clock(controller.t_s), _clock(controller.tof_s), _clock(controller.WINDOW_OPEN_S),
		_clock(controller.WINDOW_CLOSE_S), "PLAYING" if _playing else "PAUSED"]
	_teach_label.text = _teaching_text()
	_status.text = _status_text if _status_text != "" else "state=%s · dest=%s · req=%s · auth=%s" % [controller.state, controller.destination, controller.request_id, str(controller.burn_authorized)]
	map.queue_redraw()


func _teaching_text() -> String:
	var ids := {"NAVIGATION": "T07-G1-S2", "DEPARTURE_REQUEST": "T07-G1-S4", "BURN_WINDOW": "T07-G1-S4", "CRUISE": "T07-G1-S5", "ARRIVAL": "T07-G1-S5", "COMPLETE": "T07-G1-S5"}
	var sid := String(ids.get(controller.state, "T07-G1-S2"))
	var st: Dictionary = _teach_steps.get(sid, {}) if _teach_steps.get(sid, {}) is Dictionary else {}
	if st.is_empty():
		return "%s\n%s" % [sid, "教学文本 NOT READY"]
	return "%s · %s\n%s" % [sid, String(st.get("title", "")), String(st.get("player_action", ""))]


func _process(delta: float) -> void:
	if controller == null:
		return
	var allowed: bool = controller.state in ["NAVIGATION", "DEPARTURE_REQUEST", "BURN_WINDOW", "CRUISE"]
	if _playing and allowed:
		var res: Dictionary = controller.advance_time(delta * _speed)
		if not bool(res.get("ok", false)):
			_playing = false
			_log("ADVANCE FAILED · " + String(res.get("reason", "")))
	if _frames % 10 == 0:
		_refresh()
	_frames += 1
	if _shot_path != "" and _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("NAV PAGE SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _clock(s: float) -> String:
	var sec := int(maxf(0.0, s))
	return "%02d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]


func _log(text: String) -> void:
	print("[NAV PAGE] ", text)
	_logs.append(text)
	while _logs.size() > 5:
		_logs.pop_front()
	if _log_label != null:
		_log_label.text = " · ".join(_logs)
