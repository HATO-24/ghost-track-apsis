extends Control

## V2-4 启动页：冷启动 CG（8 s，可跳过）→ 主菜单（开始/设置/退出）→ 游戏屏。
##
## 视觉沿用 V1.5/V2 终端语言（pal/fonts/1px 线/扫描线/固定种子噪点/硬切），不依赖贴图。
## 环境变量：
##   DSH_INTRO=1        显示 CG（可配 DSH_INTRO_T 冻结秒数）
##   DSH_INTRO=menu     直接主菜单
##   DSH_SKIP_INTRO=1   直接进入游戏屏
##   DSH_V2_VIEW=intro|menu / DSH_V2_SHOT  截图（intro=CG、menu=主菜单）
## project.godot 由 Lead 切 main_scene；本文件不修改工程配置。

const T := preload("res://ui/theme.gd")

const CG_TOTAL := 8.0
const CONFIG_PATH := "user://v2_intro.cfg"

const CHECK_LINES := [
	"CISLUNAR OPERATIONS TERMINAL",
	"OCUVF-ID13 // COMMANDER CONSOLE",
	"BOOT 0x4471 ... OK",
	"GRAVITY DATUM L1 ... LINKED",
	"SENSOR RACK ... STANDBY",
	"TACTICAL PLOT ... CALIBRATED",
	"OCJC LINK ... ENCRYPTED",
	"MISSION FILE // CHRONOS ... SEALED",
	"AWAITING COMMANDER",
]
const CHECK_AT := [0.20, 0.55, 0.90, 1.30, 1.70, 2.10, 2.55, 3.00, 3.60]

const MENU_ITEMS := ["开始演示 / START DEMO", "设置 / OPTIONS", "退出 / QUIT"]
const WINDOW_MODES := ["窗口 / WINDOW", "F10 无边框 / BORDERLESS", "F11 独占全屏 / EXCLUSIVE"]

var _state := "cg"            # cg | menu | options
var _t := 0.0
var _sample_t := -1.0
var _shot_path := ""
var _shot_view := ""
var _capture_done := false
var _menu_sel := 0
var _options_sel := 0
var _vol_bgm := 0.72
var _vol_sfx := 0.72
var _muted := false
var _win_mode := 0
var _test_mode := ""
var _test_timer := 0.0
var _test_phase := 0
var _test_done := false
var _cfg := ConfigFile.new()
var _mouse := Vector2(-1.0, -1.0)
var _noise: Array = []
var _stars: Array = []
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cfg.load(CONFIG_PATH)
	_vol_bgm = float(_cfg.get_value("audio", "bgm", 0.72))
	_vol_sfx = float(_cfg.get_value("audio", "sfx", 0.72))
	_muted = bool(_cfg.get_value("audio", "muted", false))
	_win_mode = int(_cfg.get_value("video", "window_mode", 0))
	_build_noise()
	_parse_env()


func _parse_env() -> void:
	_shot_path = OS.get_environment("DSH_V2_SHOT")
	_shot_view = OS.get_environment("DSH_V2_VIEW")
	var force := OS.get_environment("DSH_INTRO")
	var skip := OS.get_environment("DSH_SKIP_INTRO")
	var test := OS.get_environment("DSH_INTRO_TEST")
	var view := _shot_view
	var is_intro_shot := _shot_path != "" and (view == "intro" or view == "menu" or view == "settings")
	# 自动化实测：DSH_INTRO_TEST=click_start|enter_start|esc_skip|settings_cycle（headless 也可跑）
	if test != "":
		_test_mode = test
		match test:
			"esc_skip":
				_state = "cg"
			"settings_cycle":
				_state = "options"
				_options_sel = 3
			_:
				_state = "menu"
		_menu_sel = 0
		if _test_mode == "click_start" or _test_mode == "enter_start":
			_setup_capture_window()
		set_process(true)
		queue_redraw()
		return
	if _headless:
		_goto_game()
		return
	if is_intro_shot:
		match view:
			"menu":
				_state = "menu"
			"settings":
				_state = "options"
				_options_sel = 3
			_:
				_state = "cg"
				_sample_t = float(OS.get_environment("DSH_INTRO_T")) if OS.get_environment("DSH_INTRO_T") != "" else 5.0
		_setup_capture_window()
		_capture.call_deferred()
		return
	if skip == "1" or (_shot_path != "" and not is_intro_shot):
		_goto_game()
		return
	if force == "menu":
		_enter_menu()
	elif force == "1":
		_state = "cg"
		if OS.get_environment("DSH_INTRO_T") != "":
			_sample_t = float(OS.get_environment("DSH_INTRO_T"))
	else:
		_state = "cg"
	_apply_window_mode()
	_apply_audio()
	if _state == "menu":
		_play_bgm("menu_music")


func _build_noise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for i in range(140):
		_stars.append({"p": Vector2(rng.randf_range(0.0, 1920.0), rng.randf_range(0.0, 1080.0)),
			"a": rng.randf_range(0.06, 0.30), "s": rng.randi_range(1, 2)})
	for i in range(220):
		_noise.append({"p": Vector2(rng.randf_range(0.0, 1920.0), rng.randf_range(0.0, 1080.0)),
			"a": rng.randf_range(0.008, 0.035)})


# ══ 音频 / 配置 ═══════════════════════════════════════════════════════════

func _audio() -> Node:
	return get_node_or_null("/root/Audio")


func _play_bgm(name: String) -> void:
	var a := _audio()
	if a != null:
		a.call("play_bgm", name)


func _sfx(name: String) -> void:
	var a := _audio()
	if a != null:
		a.call("sfx", name)


func _apply_audio() -> void:
	var a := _audio()
	if a != null:
		a.call("set_bgm_volume", linear_to_db(maxf(0.001, _vol_bgm)))
		a.call("set_sfx_volume", linear_to_db(maxf(0.001, _vol_sfx)))
		if _muted and a.has_method("toggle_mute") and not bool(a.call("is_muted")):
			a.call("toggle_mute")


func _save_settings() -> void:
	_cfg.set_value("audio", "bgm", _vol_bgm)
	_cfg.set_value("audio", "sfx", _vol_sfx)
	_cfg.set_value("audio", "muted", _muted)
	_cfg.set_value("video", "window_mode", _win_mode)
	_cfg.save(CONFIG_PATH)


# ══ 状态机 ═══════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _capture_done:
		return
	if _test_mode != "":
		_test_timer += delta
		_test_tick()
		queue_redraw()
		return
	if _sample_t >= 0.0:
		_t = _sample_t
		queue_redraw()
		return
	if _state == "cg":
		_t += delta
		if _t >= CG_TOTAL:
			_enter_menu()
		queue_redraw()


func _enter_menu() -> void:
	_state = "menu"
	_menu_sel = 0
	_t = CG_TOTAL
	_play_bgm("menu_music")
	queue_redraw()


func _goto_game() -> void:
	# _ready 期间不能同步换场景；延迟到本帧之后。
	get_tree().call_deferred("change_scene_to_file", "res://ui/app.tscn")


func _skip_cg() -> void:
	if _state == "cg" and _sample_t < 0.0:
		_sfx("ui_confirm")
		_enter_menu()


func _input(event: InputEvent) -> void:
	if _capture_done:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_F10:
			_set_window_mode(1)
			return
		if key.keycode == KEY_F11:
			_set_window_mode(2)
			return
		if _state == "cg":
			_skip_cg()
			return
		if _state == "menu":
			match key.keycode:
				KEY_UP:
					_menu_sel = (_menu_sel + MENU_ITEMS.size() - 1) % MENU_ITEMS.size()
					_sfx("ui_hover")
					queue_redraw()
				KEY_DOWN:
					_menu_sel = (_menu_sel + 1) % MENU_ITEMS.size()
					_sfx("ui_hover")
					queue_redraw()
				KEY_ENTER, KEY_KP_ENTER:
					_activate_menu(_menu_sel)
				KEY_ESCAPE, KEY_Q:
					get_tree().quit()
		elif _state == "options":
			match key.keycode:
				KEY_UP:
					_options_sel = (_options_sel + 3) % 4
					queue_redraw()
				KEY_DOWN:
					_options_sel = (_options_sel + 1) % 4
					queue_redraw()
				KEY_LEFT:
					_adjust_option(_options_sel, -0.1)
				KEY_RIGHT:
					_adjust_option(_options_sel, 0.1)
				KEY_ESCAPE:
					_state = "menu"
					_save_settings()
					queue_redraw()
				KEY_ENTER, KEY_KP_ENTER:
					if _options_sel == 2:
						_adjust_option(2, 0.0)
	elif event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		if _state == "cg":
			_skip_cg()
			return
		if _state == "menu":
			for i in range(MENU_ITEMS.size()):
				if _menu_btn_rect(i).has_point(mb.position):
					_activate_menu(i)
					return
		elif _state == "options":
			for i in range(4):
				if _options_row_rect(i).has_point(mb.position):
					_options_sel = i
					_adjust_option(i, 0.0)
					queue_redraw()
					return
			if _back_rect().has_point(mb.position):
				_state = "menu"
				_save_settings()
				queue_redraw()


func _activate_menu(idx: int) -> void:
	_sfx("ui_confirm")
	match idx:
		0:
			_goto_game()
		1:
			_state = "options"
			_options_sel = 0
			queue_redraw()
		2:
			get_tree().quit()


func _adjust_option(idx: int, dv: float) -> void:
	if idx == 0:
		_vol_bgm = clampf(_vol_bgm + dv, 0.0, 1.0)
	elif idx == 1:
		_vol_sfx = clampf(_vol_sfx + dv, 0.0, 1.0)
	elif idx == 2:
		_muted = not _muted
		var a := _audio()
		if a != null and a.has_method("toggle_mute"):
			a.call("toggle_mute")
	elif idx == 3:
		var dir := 1 if dv > 0.0 else (-1 if dv < 0.0 else 1)
		_set_window_mode((_win_mode + dir + WINDOW_MODES.size()) % WINDOW_MODES.size())
		return
	_apply_audio()
	_save_settings()
	queue_redraw()


func _set_window_mode(mode: int) -> void:
	_win_mode = clampi(mode, 0, WINDOW_MODES.size() - 1)
	_apply_window_mode()
	_save_settings()
	queue_redraw()


func _apply_window_mode() -> void:
	if _headless:
		return
	var w := get_window()
	match _win_mode:
		0:
			w.mode = Window.MODE_WINDOWED
			w.borderless = false
			w.size = Vector2i(1600, 900)
			var scr := DisplayServer.screen_get_size()
			if scr.x > 1600 and scr.y > 900:
				w.position = Vector2i((scr.x - 1600) / 2, (scr.y - 900) / 2)
		1:
			w.mode = Window.MODE_WINDOWED
			w.borderless = true
		2:
			w.borderless = false
			w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), T.BG)
	_draw_grid_bg()
	_draw_stars()
	if _state == "cg":
		_draw_cg()
	else:
		_draw_menu()
	_draw_scanlines()
	_draw_noise()
	_draw_frame()


func _draw_grid_bg() -> void:
	for x in range(0, 1921, 64):
		draw_line(Vector2(x, 0), Vector2(x, 1080), T.a(T.GRID, 0.10), 1.0)
	for y in range(0, 1081, 64):
		draw_line(Vector2(0, y), Vector2(1920, y), T.a(T.GRID, 0.10), 1.0)
	draw_line(Vector2(960.0, 0.0), Vector2(960.0, 1080.0), T.a(T.LINE, 0.20), 1.0)
	draw_line(Vector2(0.0, 540.0), Vector2(1920.0, 540.0), T.a(T.LINE, 0.20), 1.0)


func _draw_stars() -> void:
	var t := _t
	for raw in _stars:
		var s: Dictionary = raw
		var p: Vector2 = s["p"]
		var a := float(s["a"]) * (0.7 + 0.3 * sin(t * 0.8 + p.x * 0.01))
		draw_rect(Rect2(p, Vector2(float(s["s"]), float(s["s"]))), T.a(T.PH, a * 0.5))


func _draw_cg() -> void:
	var t := _t
	# 自检行（逐行出现）
	for i in range(CHECK_LINES.size()):
		if t < float(CHECK_AT[i]):
			continue
		var col := T.PH_DIM if i < CHECK_LINES.size() - 1 else T.PH
		T.text(self, 120.0, 170.0 + float(i) * 26.0, String(CHECK_LINES[i]), T.F10, T.a(col, 0.9), false)
		if t < float(CHECK_AT[i]) + 0.12:
			draw_rect(Rect2(120.0, 168.0 + float(i) * 26.0, 560.0, 16.0), T.a(T.PH, 0.08))
	# 轨道/基准线框（程序化）
	var cx := 1400.0
	var cy := 470.0
	for r in [80.0, 150.0, 230.0]:
		draw_arc(Vector2(cx, cy), r, 0.0, TAU, 64, T.a(T.PH_DIM, 0.18 + 0.1 * sin(t + r)), 1.0, true)
	draw_line(Vector2(cx - 300.0, cy), Vector2(cx + 300.0, cy), T.a(T.PH_FAINT, 0.4), 1.0)
	draw_line(Vector2(cx, cy - 260.0), Vector2(cx, cy + 260.0), T.a(T.PH_FAINT, 0.4), 1.0)
	draw_circle(Vector2(cx + 150.0 * cos(t * 0.7), cy + 150.0 * sin(t * 0.7)), 3.0, T.PH)
	draw_circle(Vector2(cx - 230.0 * cos(t * 0.4 + 1.0), cy - 230.0 * sin(t * 0.4 + 1.0)), 2.0, T.AMBER)
	# 标题
	if t > 3.6:
		var a := clampf((t - 3.6) / 0.6, 0.0, 1.0)
		T.text(self, 120.0, 700.0, "GHOST TRACK", T.F26 + 10, T.a(T.PH, a))
		T.text(self, 120.0, 760.0, "// APSIS", T.F26, T.a(T.PH_DIM, a))
		T.text(self, 124.0, 810.0, "CISLUNAR OPERATIONS · FIRST LEVEL", T.F9, T.a(T.DIM, a))
	# 进度条 + 跳过
	var prog := clampf(t / CG_TOTAL, 0.0, 1.0)
	draw_rect(Rect2(120.0, 980.0, 680.0, 2.0), T.a(T.LINE, 0.7))
	draw_rect(Rect2(120.0, 980.0, 680.0 * prog, 2.0), T.PH)
	T.text(self, 120.0, 994.0, "BOOT %02d%%" % int(prog * 100.0), T.F8, T.FAINT, false)
	T.text_r(self, 1800.0, 60.0, "ESC / CLICK 跳过 / SKIP", T.F8, T.a(T.FAINT, 0.9))
	# 右下版本
	T.text_r(self, 1800.0, 1020.0, "GHOST TRACK // APSIS · V2-4 · DEMO", T.F7, T.a(T.FAINT, 0.8), false)


# ══ 启动/点击流程实测（DSH_INTRO_TEST；headless 可跑）════════════════════

func _test_tick() -> void:
	if _test_done:
		return
	match _test_mode:
		"click_start":
			if _test_phase == 0 and _test_timer >= 0.5:
				_test_phase = 1
				print("INTRO TEST click_start: click START at ", str(_menu_btn_rect(0).get_center()))
				_inject_click(_menu_btn_rect(0).get_center())
			elif _test_phase == 1 and _test_timer >= 2.0:
				print("INTRO TEST FAIL click_start: scene didn't change")
				_test_done = true
				get_tree().quit(1)
		"enter_start":
			if _test_phase == 0 and _test_timer >= 0.5:
				_test_phase = 1
				print("INTRO TEST enter_start: ENTER on menu")
				_inject_key(KEY_ENTER)
			elif _test_phase == 1 and _test_timer >= 2.0:
				print("INTRO TEST FAIL enter_start: scene didn't change")
				_test_done = true
				get_tree().quit(1)
		"esc_skip":
			if _test_phase == 0 and _test_timer >= 0.5:
				_test_phase = 1
				print("INTRO TEST esc_skip: ESC during CG")
				_inject_key(KEY_ESCAPE)
			elif _test_phase == 1 and _state == "menu":
				print("INTRO TEST OK esc_skip: CG → MENU state=", _state)
				_test_done = true
				get_tree().quit(0)
		"settings_cycle":
			if _test_phase == 0 and _test_timer >= 0.3:
				_test_phase = 1
				_win_mode = 0   # 测试从窗口模式开始，避免受 user 配置影响（确定性）
				print("INTRO TEST settings: initial mode=", WINDOW_MODES[_win_mode])
				_adjust_option(3, 1.0)
				print("INTRO TEST settings: after → ", WINDOW_MODES[_win_mode])
				_adjust_option(3, 1.0)
				print("INTRO TEST settings: after → ", WINDOW_MODES[_win_mode])
				_adjust_option(3, -1.0)
				print("INTRO TEST settings: back → ", WINDOW_MODES[_win_mode])
				print("INTRO TEST OK settings_cycle volume=%d/%d muted=%s" % [
					int(_vol_bgm * 100.0), int(_vol_sfx * 100.0), str(_muted)])
				_test_done = true
				get_tree().quit(0)


func _inject_click(design_pos: Vector2) -> void:
	var wsize := get_window().size
	var scale := Vector2(1.0, 1.0)
	if wsize.x > 0 and wsize.y > 0:
		scale = Vector2(float(wsize.x) / 1920.0, float(wsize.y) / 1080.0)
	var pos := design_pos * scale
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
	print("INTRO TEST injected click ", str(pos), " (design ", str(design_pos), ")")


func _inject_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
	print("INTRO TEST injected key ", keycode)


func _draw_menu() -> void:
	T.text(self, 120.0, 120.0, "GHOST TRACK", T.F26 + 18, T.PH)
	T.text(self, 124.0, 176.0, "// APSIS", T.F26, T.PH_DIM)
	T.text(self, 124.0, 214.0, "CISLUNAR OPERATIONS · FIRST LEVEL · OCUVF-ID13", T.F9, T.a(T.DIM, 0.95))
	T.text_r(self, 1800.0, 120.0, "V2-4 · TERMINAL UI", T.F8, T.a(T.FAINT, 0.8), false)
	T.vline(self, 820.0, 260.0, 840.0, T.a(T.LINE, 0.6))
	# 左侧菜单
	for i in range(MENU_ITEMS.size()):
		var r := _menu_btn_rect(i)
		var hot := i == _menu_sel or r.has_point(_mouse)
		draw_rect(r, T.a(T.PANEL2, 0.95 if i == _menu_sel else (0.45 if hot else 0.18)))
		draw_rect(r, T.a(T.PH, 0.8 if i == _menu_sel else 0.35), false, 1.0)
		if i == _menu_sel:
			draw_rect(Rect2(r.position.x, r.position.y, 3.0, r.size.y), T.PH)
		T.text(self, r.position.x + 24.0, r.position.y + 24.0, String(MENU_ITEMS[i]), T.F16,
			T.a(T.PH if i == _menu_sel else T.TXT, 0.95))
		T.text_r(self, r.end.x - 20.0, r.position.y + 24.0, ["ENTER", "", "ESC"][i], T.F7,
			T.a(T.FAINT, 0.85), false)
	# 右侧状态栏
	var px := 1240.0
	T.text(self, px, 280.0, "SYSTEM / 系统", T.F9, T.a(T.PH_DIM, 0.9))
	var rows := [
		["TERMINAL", "CS-9 / SER.0447"],
		["DATUM", "L1 MERIDIAN-05"],
		["LINK", "OCJC · ENCRYPTED"],
		["ROE", "WEAPONS HOLD"],
		["AUDIO", "%d%% / %d%%%s" % [int(_vol_bgm * 100.0), int(_vol_sfx * 100.0), " · MUTE" if _muted else ""]],
		["WINDOW", String(WINDOW_MODES[_win_mode])],
	]
	for i in range(rows.size()):
		var row: Array = rows[i]
		T.text(self, px, 308.0 + float(i) * 24.0, String(row[0]), T.F8, T.FAINT, false)
		T.text(self, px + 120.0, 308.0 + float(i) * 24.0, String(row[1]), T.F8, T.a(T.TXT, 0.9), false)
	T.text_r(self, 1800.0, 1020.0, "↑↓ 选择 · ENTER 确认 · ESC/Q 退出", T.F8, T.a(T.FAINT, 0.85))
	T.text(self, 120.0, 1020.0, "GHOST TRACK // APSIS · V2-4 · DEMO BUILD", T.F7, T.a(T.FAINT, 0.75), false)
	if _state == "options":
		_draw_options()


func _draw_options() -> void:
	# 设置页为模态：压暗背景菜单，避免按钮/状态文字透出
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color(0.0, 0.0, 0.0, 0.58))
	var panel := Rect2(560.0, 260.0, 800.0, 540.0)
	draw_rect(panel, T.a(T.PANEL, 0.985))
	draw_rect(panel, T.a(T.PH, 0.7), false, 1.0)
	T.corners(self, panel.grow(-1.0), 14.0, T.PH, 0.85)
	T.text(self, panel.position.x + 28.0, panel.position.y + 24.0, "设置 / OPTIONS", T.F18, T.PH)
	T.text(self, panel.position.x + 28.0, panel.position.y + 50.0,
		"音量调整写入 user://v2_intro.cfg；Audio autoload 存在时立即生效。", T.F8, T.FAINT)
	var labels := ["BGM 音量 / BGM", "SFX 音量 / SFX", "静音 / MUTE", "窗口模式 / WINDOW"]
	for i in range(4):
		var r := _options_row_rect(i)
		var sel := i == _options_sel
		draw_rect(r, T.a(T.PANEL2, 0.9 if sel else 0.35))
		draw_rect(r, T.a(T.PH, 0.6 if sel else 0.25), false, 1.0)
		T.text(self, r.position.x + 12.0, r.position.y + 8.0, String(labels[i]), T.F10,
			T.a(T.PH if sel else T.TXT, 0.95))
		if i < 2:
			var v := _vol_bgm if i == 0 else _vol_sfx
			var bar := Rect2(r.position.x + 260.0, r.position.y + 14.0, 420.0, 10.0)
			draw_rect(bar, T.a(T.LINE, 0.5))
			var segs := 24
			var seg_w := (bar.size.x - float(segs - 1)) / float(segs)
			var filled := int(round(v * float(segs)))
			for s in range(segs):
				draw_rect(Rect2(bar.position.x + float(s) * (seg_w + 1.0), bar.position.y, seg_w, bar.size.y),
					T.PH if s < filled else T.a(T.LINE, 0.6))
			T.text_r(self, r.end.x - 12.0, r.position.y + 8.0, "%d%%" % int(v * 100.0), T.F9, T.a(T.PH, 0.95), false)
		elif i == 2:
			T.text_r(self, r.end.x - 12.0, r.position.y + 8.0, "MUTED" if _muted else "ON", T.F9,
				T.a(T.RED if _muted else T.PH, 0.95), false)
		else:
			T.text_r(self, r.end.x - 12.0, r.position.y + 8.0, String(WINDOW_MODES[_win_mode]), T.F9,
				T.a(T.PH, 0.95), false)
	var back := _back_rect()
	draw_rect(back, T.a(T.PANEL2, 0.6))
	draw_rect(back, T.a(T.LINE, 0.6), false, 1.0)
	T.text_c(self, back.get_center().x, back.position.y + 10.0, "返回 / BACK (ESC)", T.F10, T.a(T.TXT, 0.95))
	T.text(self, panel.position.x + 28.0, panel.end.y - 30.0,
		"←→ 调整 · ↑↓ 选择 · ESC 返回 · F10 无边框 / F11 独占全屏（即时生效）", T.F8, T.a(T.FAINT, 0.9))


func _menu_btn_rect(i: int) -> Rect2:
	return Rect2(120.0, 360.0 + float(i) * 96.0, 560.0, 72.0)


func _options_row_rect(i: int) -> Rect2:
	return Rect2(600.0, 360.0 + float(i) * 68.0, 720.0, 44.0)


func _back_rect() -> Rect2:
	return Rect2(880.0, 700.0, 200.0, 40.0)


func _draw_scanlines() -> void:
	for y in range(0, 1080, 3):
		draw_rect(Rect2(0.0, float(y), 1920.0, 1.0), Color(0.0, 0.0, 0.0, 0.10))


func _draw_noise() -> void:
	for raw in _noise:
		var n: Dictionary = raw
		draw_rect(Rect2(n["p"], Vector2(1.0, 1.0)), T.a(T.PH, float(n["a"])))


func _draw_frame() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 40.0), T.BEZEL)
	draw_rect(Rect2(0.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(1880.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(0.0, 1040.0, 1920.0, 40.0), T.BEZEL)
	draw_rect(Rect2(40.0, 40.0, 1840.0, 1000.0), T.a(T.LINE, 0.35), false, 1.0)
	draw_rect(Rect2(41.0, 41.0, 1838.0, 998.0), T.a(T.TXT, 0.02), false, 1.0)


# ══ 截图 ═════════════════════════════════════════════════════════════════

func _setup_capture_window() -> void:
	var w := get_window()
	w.borderless = true
	w.size = Vector2i(1920, 1080)
	w.position = Vector2i(0, 0)


func _capture() -> void:
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
	print("V2-4 INTRO SHOT view=%s state=%s size=%s err=%s → %s" % [
		_shot_view, _state, str(img.get_size()), str(err), _shot_path])
	_capture_done = true
	get_tree().quit(0 if err == OK else 1)
