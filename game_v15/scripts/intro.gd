extends Control

# P5a-INTRO：启动 CG（冷启动自检 → 地月/轨道线框 → GHOST TRACK / APSIS 标题硬切）
# + 主菜单（开始演示 / 设置 / 退出）。延续 game_v15 的薄荷磷光终端风格：
# 1px 线、扫描线、固定 seed 噪点、80px 硬切；不依赖外部贴图。
# 本文件只属于 intro.tscn；不改 main/hud/plot/state/project.godot。

const Palette := preload("res://scripts/pal.gd")
const Fonts := preload("res://scripts/fonts.gd")

const DW := 1920.0
const DH := 1080.0
const CG_TOTAL := 8.8          # 8–10s 目标区间
const CUT_SEED := 4471         # 与 HUD/plot 硬切同 seed，保持可复现
const CUT_DUR := 0.32
const SHOT_FRAMES := 30
const CONFIG_PATH := "user://p5a_intro.cfg"

const CHECK_LINES := [
	["CISLUNAR GRID", "OK"],
	["ORBIT MODEL L1/L4", "OK"],
	["TIDAL TABLE [4471]", "OK"],
	["SENSOR RACK MS-IR9", "OK"],
	["IFF REGISTRY", "OK"],
	["COMMS LD/LR/RDO", "OK"],
	["ORDER BUFFER", "OK"],
	["GHOST TRACK DRIVER", "OK"],
	["APSIS // ONLINE", "READY"],
]
const CHECK_AT := [0.18, 0.42, 0.66, 0.90, 1.14, 1.38, 1.62, 1.86, 2.10]

const MENU_ITEMS := [
	["开始演示 / START DEMO", "ENTER", "res://main.tscn"],
	["设置 / OPTIONS", "←→", ""],
	["退出 / QUIT", "ESC", ""],
]

var mono: Font
var cjk: Font

# ── 状态 / 时间 ───────────────────────────────────────
var _state := "cg"             # "cg" | "menu" | "options"
var _t := 0.0                  # CG 计时（真实时间）
var _menu_t := 0.0             # 菜单自身计时（揭场硬切用）
var _sample_t := -1.0          # 截图冻结时间（DSH_INTRO_T / cg1 / cg2）
var _shot_path := ""
var _shot_frames := 0
var _capture_started := false

# ── 菜单 / 设置 ───────────────────────────────────────
var _menu_sel := 0
var _options_sel := 0
var _mouse := Vector2(-1.0, -1.0)
var _master := 0.8
var _muted := false
var _cfg := ConfigFile.new()
var _demo := false
var _demo_started := false
var _sfx_stage := 0

# ── 确定性视觉素材 ────────────────────────────────────
var _stars: Array = []         # [{p:Vector2, a:float, s:int}]
var _noise: Array = []         # [{p:Vector2, a:float}]
var _cut_cells: Array = []     # 80px 格洗牌顺序（24×14）
var _cut_cols := 24
var _cut_rows := 14
var _blink := 0.0

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_load_settings()
	_build_visuals()
	_parse_env()
	_demo = OS.get_environment("DSH_DEMO") == "1"
	queue_redraw()

func _load_settings() -> void:
	var err := _cfg.load(CONFIG_PATH)
	if err != OK:
		_master = 0.8
		_muted = false
	else:
		_master = clampf(float(_cfg.get_value("audio", "master", 0.8)), 0.0, 1.0)
		_muted = bool(_cfg.get_value("audio", "muted", false))
	_apply_audio()

func _save_settings() -> void:
	if _shot_path != "":
		return  # 截图/自动化不落盘，保证可复现
	_cfg.set_value("audio", "master", _master)
	_cfg.set_value("audio", "muted", _muted)
	_cfg.save(CONFIG_PATH)

func _apply_audio() -> void:
	# Audio 不存在：静默降级，不报错。存在 autoload Audio 时按其 API 调用（见 _audio）。
	if not Engine.has_singleton("AudioServer"):
		return
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, _muted)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, _master)))

# autoload Audio 存在时调用；不存在静默返回，不报错。
func _audio(method: String, arg: Variant = null) -> void:
	var a := get_node_or_null("/root/Audio")
	if a == null or not a.has_method(method):
		return
	if arg == null:
		a.call(method)
	else:
		a.call(method, arg)

func _build_visuals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CUT_SEED
	for i in range(140):
		_stars.append({
			"p": Vector2(rng.randf_range(40.0, DW - 40.0), rng.randf_range(60.0, DH - 60.0)),
			"a": rng.randf_range(0.04, 0.22),
			"s": 1 if rng.randf() > 0.86 else 0,
		})
	for i in range(64):
		_noise.append({
			"p": Vector2(rng.randf_range(0.0, DW), rng.randf_range(0.0, DH)),
			"a": rng.randf_range(0.03, 0.12),
		})
	var arr: Array = []
	for i in range(_cut_cols * _cut_rows):
		arr.append(i)
	var st := CUT_SEED
	for i in range(arr.size() - 1, 0, -1):
		st = (st * 1103515245 + 12345) & 0x7fffffff
		var j := st % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	_cut_cells = arr

func _parse_env() -> void:
	var intro := OS.get_environment("DSH_INTRO")
	var shot := OS.get_environment("DSH_SHOT")
	var skip := OS.get_environment("DSH_SKIP_INTRO")
	# 未显式要求 intro 且已有 DSH_SHOT（或 DSH_SKIP_INTRO=1）→ 直接进 main，保证既有 HUD 截图不变。
	if skip == "1" or (intro == "" and shot != ""):
		set_process(false)
		call_deferred("_forward_to_main")
		return
	_shot_path = shot
	# 截图模式：全屏 1920×1080，避免窗口边框/任务栏把内容裁成 1920×1061。
	if _shot_path != "":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	match intro:
		"menu":
			_state = "menu"
			_menu_t = 1.0
		"cg1":
			_state = "cg"
			_sample_t = 1.70
		"cg2":
			_state = "cg"
			_sample_t = 5.20
		_:
			_state = "cg"
	var te := OS.get_environment("DSH_INTRO_T")
	if te != "":
		_sample_t = maxf(0.0, float(te))
	if _state == "menu":
		_enter_menu_audio_only()
		# 菜单截图冻结到固定时刻，噪点/扫描线/星点闪烁可复现。
		if _shot_path != "" and _sample_t < 0.0:
			_sample_t = 0.60
	elif _state == "cg":
		pass
	# 自动化/回归：直接走“开始演示”，用于验证 intro → main 的场景切换。
	if OS.get_environment("DSH_INTRO_ACTION") == "start":
		_state = "menu"
		call_deferred("_activate_menu", 0)

func _forward_to_main() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _enter_menu_audio_only() -> void:
	_audio("play_bgm", "menu")

func _enter_menu() -> void:
	_state = "menu"
	_menu_t = 0.0
	_menu_sel = 0
	_enter_menu_audio_only()

func _process(delta: float) -> void:
	_t += delta
	_menu_t += delta
	if _state == "cg":
		var ct := _cg_time()
		if ct >= 0.06 and _sfx_stage < 1:
			_sfx_stage = 1
			_audio("sfx", "boot")
		if ct >= 3.16 and _sfx_stage < 2:
			_sfx_stage = 2
			_audio("sfx", "hard_cut")
		if ct >= 6.46 and _sfx_stage < 3:
			_sfx_stage = 3
			_audio("sfx", "hard_cut")
		if ct >= 6.57 and _sfx_stage < 4:
			_sfx_stage = 4
			_audio("sfx", "hard_cut")
		if ct >= CG_TOTAL:
			_enter_menu()
	elif _state == "menu" and _demo and not _demo_started and _menu_t >= 2.8:
		_demo_started = true
		_activate_menu(0)
	if _shot_path != "" and not _capture_started:
		_shot_frames += 1
		if _shot_frames >= SHOT_FRAMES:
			_capture_started = true
			_capture()
	queue_redraw()

# ── 输入 ──────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			_handle_key(ke.keycode)
	elif event is InputEventMouseMotion:
		_mouse = _to_design((event as InputEventMouseMotion).position)
		queue_redraw()
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.pressed and me.button_index == MOUSE_BUTTON_LEFT:
			_mouse = _to_design(me.position)
			_handle_click(_mouse)

func _handle_key(k: int) -> void:
	if _state == "cg":
		_enter_menu()
		return
	if _state == "options":
		if k == KEY_UP or k == KEY_W:
			_options_sel = wrapi(_options_sel - 1, 0, 3)
			_audio("sfx", "ui_confirm")
		elif k == KEY_DOWN or k == KEY_S:
			_options_sel = wrapi(_options_sel + 1, 0, 3)
			_audio("sfx", "ui_confirm")
		elif k == KEY_LEFT or k == KEY_A:
			if _options_sel == 0:
				_master = clampf(_master - 0.1, 0.0, 1.0)
				_apply_audio()
				_save_settings()
		elif k == KEY_RIGHT or k == KEY_D:
			if _options_sel == 0:
				_master = clampf(_master + 0.1, 0.0, 1.0)
				_apply_audio()
				_save_settings()
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			if _options_sel == 1:
				_muted = not _muted
				_apply_audio()
				_save_settings()
				_audio("sfx", "ui_confirm")
			elif _options_sel == 2:
				_audio("sfx", "ui_back")
				_state = "menu"
		elif k == KEY_ESCAPE:
			_audio("sfx", "ui_back")
			_state = "menu"
		queue_redraw()
		return
	# menu
	if k == KEY_UP or k == KEY_W:
		_menu_sel = wrapi(_menu_sel - 1, 0, MENU_ITEMS.size())
		_audio("sfx", "ui_confirm")
	elif k == KEY_DOWN or k == KEY_S:
		_menu_sel = wrapi(_menu_sel + 1, 0, MENU_ITEMS.size())
		_audio("sfx", "ui_confirm")
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		_activate_menu(_menu_sel)
	elif k == KEY_ESCAPE:
		get_tree().quit()
	queue_redraw()

func _handle_click(p: Vector2) -> void:
	if _state == "cg":
		if _skip_rect().has_point(p):
			_enter_menu()
		return
	if _state == "options":
		if _back_rect().has_point(p):
			_audio("sfx", "ui_back")
			_state = "menu"
			return
		for i in range(3):
			if _option_row_rect(i).has_point(p):
				_options_sel = i
				if i == 1:
					_muted = not _muted
					_apply_audio()
					_save_settings()
				elif i == 2:
					_audio("sfx", "ui_back")
					_state = "menu"
				return
		return
	for i in range(MENU_ITEMS.size()):
		if _menu_btn_rect(i).has_point(p):
			_menu_sel = i
			_activate_menu(i)
			return

func _activate_menu(idx: int) -> void:
	if idx < 0 or idx >= MENU_ITEMS.size():
		return
	match idx:
		0:
			_audio("sfx", "ui_confirm")
			get_tree().call_deferred("change_scene_to_file", "res://main.tscn")
		1:
			_audio("sfx", "ui_confirm")
			_state = "options"
			_options_sel = 0
		2:
			_audio("sfx", "ui_back")
			get_tree().quit()

# ── 截图钩子（与 main 的 DSH_SHOT 同速：30 帧后存图退出）──
func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("SHOT (%d,%d) err=%d → %s" % [img.get_width(), img.get_height(), err, _shot_path])
	get_tree().quit()

# ── 坐标 / 排版辅助 ───────────────────────────────────
func _scale_off() -> Array:
	var sc := minf(size.x / DW, size.y / DH)
	if sc <= 0.0:
		sc = 1.0
	var off := (size - Vector2(DW, DH) * sc) * 0.5
	return [sc, off]

func _to_design(p: Vector2) -> Vector2:
	var so := _scale_off()
	var sc: float = so[0]
	var off: Vector2 = so[1]
	return (p - off) / sc

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(xr - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_c(f: Font, cx: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

# 终端式字距（标题用）：逐字符绘制，保持 1px 线条感。
func _txt_spaced(s: String, cx: float, y: float, sz: int, gap: float, c: Color) -> void:
	var total := 0.0
	for i in range(s.length()):
		total += mono.get_string_size(s.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if i < s.length() - 1:
			total += gap
	var x := cx - total * 0.5
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		draw_string(mono, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
		x += mono.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if i < s.length() - 1:
			x += gap

func _cg_time() -> float:
	if _sample_t >= 0.0:
		return _sample_t
	return _t

# ── 顶层绘制 ──────────────────────────────────────────
func _draw() -> void:
	var so := _scale_off()
	var sc: float = so[0]
	var off: Vector2 = so[1]
	draw_set_transform(off, 0.0, Vector2(sc, sc))
	draw_rect(Rect2(Vector2.ZERO, Vector2(DW, DH)), Palette.BG)
	if _state == "cg":
		_draw_cg()
	else:
		_draw_menu()
		if _state == "options":
			_draw_options()
	_draw_scanlines()
	_draw_frame()

func _draw_cg() -> void:
	var t := _cg_time()
	_draw_grid_bg(0.30)
	_draw_noise(t)
	if t < 3.15:
		_draw_selfcheck(t)
	elif t < 6.55:
		_draw_orbit(t)
	else:
		_draw_title(t)
	# 硬切过渡：自检→轨道 / 轨道→黑场→标题 / 标题→菜单
	var cover := 0.0
	if t >= 3.15 and t < 3.50:
		cover = 1.0 - clampf((t - 3.15) / 0.35, 0.0, 1.0)
	elif t >= 6.40 and t < 6.55:
		cover = clampf((t - 6.40) / 0.15, 0.0, 1.0)
	elif t >= 6.55 and t < 6.90:
		cover = 1.0 - clampf((t - 6.55) / 0.35, 0.0, 1.0)
	elif t >= 8.40:
		cover = clampf((t - 8.40) / 0.40, 0.0, 1.0)
	if cover > 0.0:
		_draw_cut(cover)
	_txt(mono, 96.0, DH - 72.0, "SIG 0.98 · L1 MERIDIAN · OCUVF-ID13", 7, Palette.a(Palette.FAINT, 0.8))
	_txt_r(mono, DW - 96.0, DH - 72.0, "T+%04.1f s / %04.1f s" % [t, CG_TOTAL], 7, Palette.a(Palette.FAINT, 0.8))

# ── 通用底纹：网格 / 星点 / 噪点 / 扫描线 / 边框 ───────
func _draw_grid_bg(a: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(DW, DH)), Palette.a(Palette.BG, 1.0))
	for x in range(0, int(DW) + 1, 80):
		draw_line(Vector2(float(x), 0), Vector2(float(x), DH), Palette.a(Palette.GRID, a * 0.35), 1.0)
	for y in range(0, int(DH) + 1, 80):
		draw_line(Vector2(0, float(y)), Vector2(DW, float(y)), Palette.a(Palette.GRID, a * 0.35), 1.0)
	# 中轴 / 四角括弧
	draw_line(Vector2(DW * 0.5, 0), Vector2(DW * 0.5, DH), Palette.a(Palette.PH_FAINT, a * 0.35), 1.0)
	draw_line(Vector2(0, DH * 0.5), Vector2(DW, DH * 0.5), Palette.a(Palette.PH_FAINT, a * 0.20), 1.0)

func _draw_stars(t: float) -> void:
	for st in _stars:
		var d: Dictionary = st
		var tw := 0.75 + 0.25 * sin(t * 1.7 + float(int(d["p"].x)) * 0.011)
		var c: Color = Palette.a(Palette.PH, float(d["a"]) * tw)
		var p: Vector2 = d["p"]
		draw_rect(Rect2(p, Vector2(1.0 + float(d["s"]), 1.0 + float(d["s"]))), c)

func _draw_noise(t: float) -> void:
	var step := int(floor(t * 12.0))
	for i in range(_noise.size()):
		var d: Dictionary = _noise[i]
		# 固定 seed 噪点按帧步进变化，保持可复现
		var h := (i * 1103515245 + step * 12345 + CUT_SEED) & 0x7fffffff
		var p: Vector2 = d["p"]
		var jitter := Vector2(float(h % 7) - 3.0, float((h / 7) % 7) - 3.0)
		var c: Color = Palette.a(Palette.TXT, float(d["a"]) * (0.6 + 0.4 * sin(float(step) + float(i))))
		draw_rect(Rect2(p + jitter, Vector2(1, 1)), c)

func _draw_scanlines() -> void:
	for y in range(0, int(DH), 3):
		draw_line(Vector2(0, float(y)), Vector2(DW, float(y)), Palette.a(Palette.PH, 0.028), 1.0)
	var sy := fmod(_cg_time() * 110.0, DH)
	draw_line(Vector2(0, sy), Vector2(DW, sy), Palette.a(Palette.PH, 0.075), 1.0)
	draw_line(Vector2(0, sy + 3.0), Vector2(DW, sy + 3.0), Palette.a(Palette.PH, 0.03), 1.0)

func _draw_frame() -> void:
	var m := 24.0
	var pts := [
		[Vector2(m, m), Vector2(m + 26, m)], [Vector2(m, m), Vector2(m, m + 26)],
		[Vector2(DW - m, m), Vector2(DW - m - 26, m)], [Vector2(DW - m, m), Vector2(DW - m, m + 26)],
		[Vector2(m, DH - m), Vector2(m + 26, DH - m)], [Vector2(m, DH - m), Vector2(m, DH - m - 26)],
		[Vector2(DW - m, DH - m), Vector2(DW - m - 26, DH - m)], [Vector2(DW - m, DH - m), Vector2(DW - m, DH - m - 26)],
	]
	for seg in pts:
		draw_line(seg[0], seg[1], Palette.a(Palette.PH, 0.45), 1.0)

# 80px 固定 seed 硬切（cover=1 全黑；cover 递减=揭示）
func _draw_cut(cover: float) -> void:
	var c := clampf(cover, 0.0, 1.0)
	if c <= 0.0:
		return
	var n := int(round(float(_cut_cells.size()) * c))
	for i in range(n):
		var idx: int = int(_cut_cells[i])
		var col := idx % _cut_cols
		var row := idx / _cut_cols
		draw_rect(Rect2(float(col) * 80.0, float(row) * 80.0, 80.0, 80.0), Palette.BEZEL)

# ── CG：冷启动自检 ────────────────────────────────────
func _draw_selfcheck(t: float) -> void:
	_draw_stars(t)
	_txt(mono, 96.0, 120.0, "CISLUNAR // COLD START", 15, Palette.a(Palette.PH, 0.95))
	_txt(cjk, 96.0, 144.0, "地月指挥终端 · 冷启动序列", 10, Palette.a(Palette.DIM, 1.0))
	_txt_r(mono, DW - 96.0, 120.0, "ID13 · HARMATTAN · L4-02 HAMMER", 9, Palette.a(Palette.DIM, 0.95))
	_txt_r(mono, DW - 96.0, 144.0, "BOOT SEQ 0x4471 · 1× LOCK", 8, Palette.a(Palette.FAINT, 0.95))
	draw_line(Vector2(96, 160), Vector2(DW - 96, 160), Palette.a(Palette.LINE2, 0.9), 1.0)

	var x := 140.0
	var y := 230.0
	for i in range(CHECK_LINES.size()):
		var th: float = CHECK_AT[i]
		if t < th:
			continue
		var row: Array = CHECK_LINES[i]
		var label := String(row[0])
		var status := String(row[1])
		var typed := int(minf(float(label.length()), (t - th) * 60.0))
		var str_typed := label.substr(0, typed)
		var off := "%04X" % (0x4A00 + i * 0x20)
		_txt(mono, x, y, off, 12, Palette.a(Palette.PH_FAINT, 0.95))
		_txt(mono, x + 78.0, y, str_typed, 13, Palette.a(Palette.PH, 0.95))
		if typed >= label.length():
			draw_line(Vector2(x + 78.0, y + 5), Vector2(x + 470.0, y + 5), Palette.a(Palette.LINE, 0.55), 1.0)
			var tag_col: Color = Palette.PH if status == "OK" else Palette.AMBER
			_txt_r(mono, x + 600.0, y, "[ %s ]" % status, 12, Palette.a(tag_col, 0.9))
		y += 34.0
	# 进度条 + 阶段标记
	var prog := clampf(t / 3.0, 0.0, 1.0)
	draw_rect(Rect2(140, 560, 600, 1), Palette.a(Palette.LINE, 0.95))
	draw_rect(Rect2(140, 560, 600.0 * prog, 1), Palette.a(Palette.PH, 0.9))
	for i in range(6):
		var tx := 140.0 + 600.0 * float(i) / 5.0
		draw_line(Vector2(tx, 556), Vector2(tx, 564), Palette.a(Palette.PH_FAINT, 0.9), 1.0)
	_txt(mono, 140.0, 586.0, "BOOT %02d%% · T+%04.1fs · MEM CHECK 64K" % [int(prog * 100.0), t], 9,
		Palette.a(Palette.DIM, 0.95))
	# 左下：确定性的内存 hex dump
	var hx := 140.0
	var hy := 660.0
	_txt(mono, hx, hy - 18.0, "MEM / 0x4A00", 8, Palette.a(Palette.FAINT, 0.95))
	for r in range(6):
		var line := "%04X  " % (0x4A00 + r * 16)
		for cidx in range(8):
			var v := (r * 37 + cidx * 11 + 4471) % 256
			line += "%02X " % v
		_txt(mono, hx, hy + float(r) * 16.0, line, 9, Palette.a(Palette.PH_DIM, 0.9))
	# 右下：启动日志
	var lx := 900.0
	var ly := 660.0
	_txt(mono, lx, ly - 18.0, "BOOT LOG", 8, Palette.a(Palette.FAINT, 0.95))
	var logs := [
		["T+0.02", "POWER RAIL A/B ........ NOMINAL"],
		["T+0.31", "GYRO CALIBRATION ..... 0.002°"],
		["T+0.74", "TIDAL MODEL [L1] ..... LOADED"],
		["T+1.12", "GHOST TRACK DRIVER ... ARMED"],
		["T+1.55", "OCJC LINK ............ STANDBY"],
	]
	for i in range(logs.size()):
		var row3: Array = logs[i]
		var yy := ly + float(i) * 18.0
		_txt(mono, lx, yy, String(row3[0]), 8, Palette.a(Palette.PH_FAINT, 0.95))
		_txt(mono, lx + 92.0, yy, String(row3[1]), 8, Palette.a(Palette.DIM, 0.9))
	# 右侧遥测
	var rx := DW - 540.0
	var ry := 300.0
	var tel := [
		["DATUM", "L4-02 HAMMER"],
		["EPOCH", "T+00:00:00"],
		["LINK", "LASER DIRECT · 4 s"],
		["RACK", "MS-IR9 / ELINT"],
		["ROE", "WEAPONS HOLD"],
		["ORDERS", "0 QUEUED"],
	]
	_txt(mono, rx, ry - 26.0, "TELEMETRY / 遥测", 9, Palette.a(Palette.FAINT, 0.95))
	for i in range(tel.size()):
		var row2: Array = tel[i]
		var yy := ry + float(i) * 34.0
		_txt(mono, rx, yy, String(row2[0]), 9, Palette.a(Palette.FAINT, 0.95))
		_txt(mono, rx + 140.0, yy, String(row2[1]), 9, Palette.a(Palette.TXT, 0.9))
		draw_line(Vector2(rx, yy + 8.0), Vector2(rx + 340.0, yy + 8.0), Palette.a(Palette.LINE, 0.25), 1.0)
	_txt(mono, rx, 560.0, "SENSOR FEED · 1 Hz · 被动", 8, Palette.a(Palette.PH_FAINT, 0.9))
	for i in range(10):
		var bx := rx + float(i) * 26.0
		var bh := 6.0 + float((i * 13 + int(t * 10.0)) % 18)
		draw_rect(Rect2(bx, 590.0 - bh, 18.0, bh), Palette.a(Palette.PH, 0.30 + 0.04 * float(i % 4)))
	# 大字 / 落款
	_txt(mono, 140.0, 940.0, "GHOST TRACK", 34, Palette.a(Palette.PH, 0.22))
	_txt(cjk, 140.0, 974.0, "冷启动自检 · 不进入通信流 · 固定 seed 4471", 8, Palette.a(Palette.FAINT, 0.85))
	_draw_skip_btn()

# ── CG：地月 / 拉格朗日线框 ───────────────────────────
func _draw_orbit(t: float) -> void:
	_draw_stars(t)
	var earth := Vector2(700.0, 650.0)
	var moon := Vector2(1330.0, 400.0)
	var er := 170.0
	var mr := 54.0
	var dist := earth.distance_to(moon)
	var dir := (moon - earth).normalized()
	# 地球 / 月球（1px 线 + 经纬线框，不依赖贴图）
	draw_arc(earth, er, 0, TAU, 96, Palette.a(Palette.PH, 0.65), 1.0, true)
	draw_arc(earth, er + 9.0, 0, TAU, 96, Palette.a(Palette.PH_FAINT, 0.30), 1.0, true)
	draw_arc(earth, er - 14.0, 0, TAU, 96, Palette.a(Palette.EARTH, 1.0), 1.0, true)
	for k in range(3):
		var lon := Vector2(cos(float(k) * PI / 3.0), sin(float(k) * PI / 3.0))
		var pts := PackedVector2Array()
		for i in range(65):
			var a := float(i) / 64.0 * TAU
			var p := Vector2(cos(a) * er * absf(lon.x), sin(a) * er)
			pts.append(earth + p)
		draw_polyline(pts, Palette.a(Palette.PH_FAINT, 0.22), 1.0)
	for k in range(3):
		var yy := -er + float(k + 1) * er * 0.5
		var hw := er * sqrt(maxf(0.0, 1.0 - (yy / er) * (yy / er)))
		draw_line(earth + Vector2(-hw, yy), earth + Vector2(hw, yy), Palette.a(Palette.PH_FAINT, 0.22), 1.0)
	draw_arc(moon, mr, 0, TAU, 48, Palette.a(Palette.PH, 0.65), 1.0, true)
	draw_arc(moon, mr + 8.0, 0, TAU, 48, Palette.a(Palette.PH_FAINT, 0.30), 1.0, true)
	draw_circle(earth, 2.4, Palette.a(Palette.PH, 1.0))
	draw_circle(moon, 1.8, Palette.a(Palette.PH, 1.0))
	# 地月连线 + 刻度
	draw_dashed_line(earth, moon, Palette.a(Palette.PH_FAINT, 0.4), 1.0, 6.0)
	var steps := 8
	for i in range(steps + 1):
		var p := earth + dir * dist * float(i) / float(steps)
		draw_line(p - Vector2(0, 3), p + Vector2(0, 3), Palette.a(Palette.PH_FAINT, 0.35), 1.0)
	# L1 / L2 / L4 / L5 站点（L4/L5 为相对地月方向的 ±60° 三角点，0.55 距离作图内示意）
	var l1 := earth + dir * (dist - 120.0)
	var l2 := moon + dir * 120.0
	var l4 := earth + dir.rotated(deg_to_rad(60.0)) * (dist * 0.55)
	var l5 := earth + dir.rotated(deg_to_rad(-60.0)) * (dist * 0.55)
	var sites := [[l1, "L1", "MERIDIAN-05"], [l2, "L2", "KARMAN"], [l4, "L4", "HAMMER"], [l5, "L5", "EKO"]]
	for s in sites:
		var p: Vector2 = s[0]
		draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), Palette.a(Palette.PH, 0.9), 1.0)
		draw_line(p + Vector2(0, -8), p + Vector2(0, 8), Palette.a(Palette.PH, 0.9), 1.0)
		draw_rect(Rect2(p + Vector2(-2.5, -2.5), Vector2(5, 5)), Palette.a(Palette.PH, 0.95))
		var lab := "%s // %s" % [String(s[1]), String(s[2])]
		var tw := mono.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_rect(Rect2(p + Vector2(12, -11), Vector2(tw + 10, 16)), Palette.a(Palette.BG, 0.72))
		_txt(mono, p.x + 17.0, p.y + 5.0, lab, 9, Palette.a(Palette.TXT, 0.95))
	# 转动雷达线 + 速度向量
	var ang := fmod(t * 0.55, TAU)
	draw_line(earth, earth + Vector2(cos(ang), sin(ang)) * (er + 380.0), Palette.a(Palette.PH, 0.20), 1.0)
	var vp := earth + Vector2(0, -er - 38.0)
	draw_line(vp, vp + dir * 52.0, Palette.a(Palette.PH, 0.75), 1.0)
	var pp := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		vp + dir * 58.0, vp + dir * 46.0 + pp * 4.0, vp + dir * 46.0 - pp * 4.0
	]), Palette.a(Palette.PH, 0.85))
	_txt(mono, vp.x + 14.0, vp.y - 26.0, "VECTOR 0.98 km/s", 8, Palette.a(Palette.PH_FAINT, 0.9))
	# 标签 / 遥测
	_txt(mono, 84.0, 116.0, "ORBIT FRAME / L1 MERIDIAN", 14, Palette.a(Palette.PH, 0.95))
	_txt(cjk, 84.0, 140.0, "地月双体 · 转移轨道 · 固定 seed 线框", 9, Palette.a(Palette.DIM, 1.0))
	_txt_r(mono, DW - 96.0, 116.0, "FRAME LVLH · ZOOM ×0.10", 8, Palette.a(Palette.FAINT, 0.95))
	_txt(mono, earth.x - er - 12.0, earth.y + er + 34.0, "EARTH", 10, Palette.a(Palette.PH, 0.9))
	_txt(mono, moon.x - mr - 12.0, moon.y + mr + 30.0, "MOON", 10, Palette.a(Palette.PH, 0.9))
	var rx := DW - 540.0
	_txt(mono, rx, 228.0, "TRANSIT / HAMMER → MERIDIAN", 10, Palette.a(Palette.FAINT, 0.95))
	var lines := [
		["Δv BUDGET", "120 m/s"],
		["WINDOW", "T+18:00"],
		["TRANSIT", "6 h 42 m"],
		["STATUS", "CRUISE / 巡航"],
	]
	for i in range(lines.size()):
		var row: Array = lines[i]
		var yy := 272.0 + float(i) * 34.0
		_txt(mono, rx, yy, String(row[0]), 9, Palette.a(Palette.FAINT, 0.95))
		_txt(mono, rx + 160.0, yy, String(row[1]), 9, Palette.a(Palette.TXT, 0.9))
		draw_line(Vector2(rx, yy + 9.0), Vector2(rx + 360.0, yy + 9.0), Palette.a(Palette.LINE, 0.25), 1.0)
	_txt(mono, rx, 470.0, "固定 seed 4471 · 80px 硬切 · 1px 线框", 8, Palette.a(Palette.FAINT, 0.85))
	# 左下角水印
	_txt(mono, 84.0, DH - 120.0, "L1 MERIDIAN-05 // CHRONOS", 22, Palette.a(Palette.PH, 0.10))
	_txt(cjk, 84.0, DH - 96.0, "第七号轨道紧急托管令 · 执行窗口 06:00", 8, Palette.a(Palette.FAINT, 0.75))
	_draw_skip_btn()

func _draw_title(t: float) -> void:
	_draw_stars(t)
	var cx := DW * 0.5
	_txt_spaced("GHOST TRACK", cx, 486.0, 92, 20.0, Palette.a(Palette.PH, 0.96))
	draw_rect(Rect2(cx - 430.0, 512.0, 860.0, 1.0), Palette.a(Palette.PH, 0.55))
	_txt_spaced("APSIS", cx, 566.0, 40, 26.0, Palette.a(Palette.PH, 0.85))
	_txt_c(cjk, cx, 616.0, "地月指挥终端 · CISLUNAR OPERATIONS SIMULATOR", 11, Palette.a(Palette.DIM, 0.95))
	_txt_c_mono("ORDER 7 // CHRONOS // DEMO BUILD v0.5", cx, 660.0, 9, Palette.a(Palette.AMBER, 0.75))
	# 闪烁块光标
	_blink += 0.016
	if fmod(_blink, 1.0) < 0.55:
		draw_rect(Rect2(cx - 6.0, 690.0, 12.0, 18.0), Palette.a(Palette.PH, 0.85))
	# 四角刻度
	draw_line(Vector2(cx - 470.0, 440.0), Vector2(cx - 470.0, 700.0), Palette.a(Palette.PH_FAINT, 0.35), 1.0)
	draw_line(Vector2(cx + 470.0, 440.0), Vector2(cx + 470.0, 700.0), Palette.a(Palette.PH_FAINT, 0.35), 1.0)
	_txt_r(mono, DW - 96.0, DH - 96.0, "SIGNAL ACQUIRED · 0.98", 8, Palette.a(Palette.FAINT, 0.85))
	_txt(mono, 96.0, DH - 96.0, "GHOST TRACK / APSIS", 8, Palette.a(Palette.FAINT, 0.85))
	_draw_skip_btn()

func _txt_c_mono(s: String, cx: float, y: float, sz: int, c: Color) -> void:
	var w := mono.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(mono, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _skip_rect() -> Rect2:
	return Rect2(DW - 372.0, DH - 128.0, 276.0, 40.0)

func _draw_skip_btn() -> void:
	var rc := _skip_rect()
	var hot := rc.has_point(_mouse)
	draw_rect(rc, Palette.a(Palette.PANEL2, 0.95 if hot else 0.55))
	draw_rect(rc, Palette.a(Palette.PH, 0.75 if hot else 0.35), false, 1.0)
	_txt(mono, rc.position.x + 16.0, rc.position.y + 14.0, "跳过 / SKIP ▸", 9, Palette.PH if hot else Palette.a(Palette.DIM, 0.95))
	_txt_r(mono, rc.end.x - 14.0, rc.position.y + 14.0, "ANY KEY", 7, Palette.a(Palette.FAINT, 0.85))

# ── 主菜单 ────────────────────────────────────────────
func _draw_menu() -> void:
	_draw_grid_bg(0.35)
	_draw_stars(_cg_time())
	_draw_noise(_cg_time())
	# 左：标题 / 按钮
	var lx := 196.0
	_txt(mono, lx, 168.0, "CISLUNAR OPERATIONS SIMULATOR", 9, Palette.a(Palette.FAINT, 0.95))
	_txt_spaced("GHOST TRACK", lx + 300.0, 286.0, 62, 12.0, Palette.a(Palette.PH, 0.95))
	_txt_spaced("APSIS", lx + 300.0, 340.0, 30, 20.0, Palette.a(Palette.PH, 0.85))
	draw_line(Vector2(lx, 366.0), Vector2(lx + 600.0, 366.0), Palette.a(Palette.PH, 0.35), 1.0)
	_txt(cjk, lx, 396.0, "地月指挥终端 · 第七号轨道紧急托管令（演示）", 10, Palette.a(Palette.DIM, 0.95))
	_txt(mono, lx, 420.0, "GHOST TRACK / APSIS · DEMO BUILD v0.5", 8, Palette.a(Palette.FAINT, 0.9))
	# 菜单按钮
	for i in range(MENU_ITEMS.size()):
		var rc := _menu_btn_rect(i)
		var sel := i == _menu_sel
		var hot := rc.has_point(_mouse)
		draw_rect(rc, Palette.a(Palette.PANEL2, 0.95 if (sel or hot) else 0.45))
		draw_rect(rc, Palette.a(Palette.PH, 0.80 if (sel or hot) else 0.25), false, 1.0)
		if sel:
			draw_rect(Rect2(rc.position.x, rc.position.y, 2.0, rc.size.y), Palette.PH)
		_txt(mono, rc.position.x + 18.0, rc.position.y + 18.0, "0%d" % (i + 1), 12, Palette.a(Palette.PH, 0.9 if sel else 0.5))
		_txt(cjk, rc.position.x + 58.0, rc.position.y + 18.0, String(MENU_ITEMS[i][0]), 12, Palette.PH if sel else Palette.TXT)
		_txt_r(mono, rc.end.x - 16.0, rc.position.y + 18.0, String(MENU_ITEMS[i][1]), 8, Palette.a(Palette.FAINT, 0.85))
	# 右：轨道线框小图 + 遥测
	_draw_menu_orbit()
	# 底部
	_txt(mono, 96.0, DH - 72.0, "v0.5 DEMO · OCUVF-ID13 · ORDER 7", 8, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, DW - 96.0, DH - 72.0, "↑↓ 选择 · ENTER 确认 · ESC 退出", 8, Palette.a(Palette.FAINT, 0.9))
	# 揭场硬切（菜单前 0.32s）
	_draw_cut(clampf(1.0 - _menu_t / CUT_DUR, 0.0, 1.0))

func _menu_btn_rect(i: int) -> Rect2:
	return Rect2(196.0, 470.0 + float(i) * 52.0, 520.0, 40.0)

func _draw_menu_orbit() -> void:
	var c := Vector2(1460.0, 500.0)
	var r := 170.0
	draw_arc(c, r, 0, TAU, 96, Palette.a(Palette.PH_FAINT, 0.45), 1.0, true)
	draw_arc(c, r * 0.62, 0, TAU, 72, Palette.a(Palette.PH_FAINT, 0.30), 1.0, true)
	draw_arc(c, r * 0.3, 0, TAU, 48, Palette.a(Palette.PH, 0.35), 1.0, true)
	var moon := c + Vector2(r * 0.82, -r * 0.55)
	draw_circle(c, 3.0, Palette.a(Palette.PH, 0.9))
	draw_arc(moon, 3.0, 0, TAU, 24, Palette.a(Palette.PH, 0.9), 1.0, true)
	draw_dashed_line(c, moon, Palette.a(Palette.PH_FAINT, 0.4), 1.0, 5.0)
	var l1 := c + (moon - c) * 0.62
	draw_line(l1 + Vector2(-6, 0), l1 + Vector2(6, 0), Palette.a(Palette.PH, 0.8), 1.0)
	draw_line(l1 + Vector2(0, -6), l1 + Vector2(0, 6), Palette.a(Palette.PH, 0.8), 1.0)
	_txt(mono, l1.x + 10.0, l1.y + 4.0, "L1", 7, Palette.a(Palette.PH, 0.8))
	_txt(mono, c.x - 4.0, c.y + r + 24.0, "EARTH", 7, Palette.a(Palette.FAINT, 0.9))
	_txt(mono, moon.x + 8.0, moon.y - 8.0, "MOON", 7, Palette.a(Palette.FAINT, 0.9))
	var rx := DW - 380.0
	var tel := [
		["ID13", "HARMATTAN · 哨舰"],
		["DATUM", "L1 MERIDIAN-05"],
		["LINK", "LD · 4 s"],
		["ROE", "WEAPONS HOLD"],
	]
	for i in range(tel.size()):
		var row: Array = tel[i]
		var yy := 760.0 + float(i) * 26.0
		_txt(mono, rx, yy, String(row[0]), 8, Palette.a(Palette.FAINT, 0.9))
		_txt(mono, rx + 104.0, yy, String(row[1]), 8, Palette.a(Palette.TXT, 0.85))
	_txt(mono, rx, 900.0, "AUDIO: SILENT FALLBACK", 7, Palette.a(Palette.FAINT, 0.6))

# ── 设置面板 ──────────────────────────────────────────
func _option_row_rect(i: int) -> Rect2:
	return Rect2(560.0, 380.0 + float(i) * 72.0, 800.0, 56.0)

func _back_rect() -> Rect2:
	return _option_row_rect(2)

func _draw_options() -> void:
	# 压暗 + 面板
	draw_rect(Rect2(Vector2.ZERO, Vector2(DW, DH)), Color(0.01, 0.03, 0.02, 0.72))
	var pr := Rect2(496.0, 300.0, 928.0, 440.0)
	draw_rect(pr, Palette.a(Palette.PANEL, 0.98))
	draw_rect(pr, Palette.a(Palette.PH, 0.55), false, 1.0)
	_txt(cjk, pr.position.x + 28.0, pr.position.y + 40.0, "设置 / OPTIONS", 16, Palette.PH)
	_txt_r(mono, pr.end.x - 28.0, pr.position.y + 40.0, "AUDIO · LOCAL CONFIG", 8, Palette.a(Palette.FAINT, 0.9))
	draw_line(Vector2(pr.position.x, pr.position.y + 56.0), Vector2(pr.end.x, pr.position.y + 56.0), Palette.a(Palette.PH, 0.25), 1.0)
	# 行
	for i in range(3):
		var rc := _option_row_rect(i)
		var sel := i == _options_sel
		var hot := rc.has_point(_mouse)
		draw_rect(rc, Palette.a(Palette.PANEL2, 0.95 if (sel or hot) else 0.45))
		draw_rect(rc, Palette.a(Palette.PH, 0.70 if (sel or hot) else 0.22), false, 1.0)
		if sel:
			draw_rect(Rect2(rc.position.x, rc.position.y, 2.0, rc.size.y), Palette.PH)
		if i == 0:
			_txt(cjk, rc.position.x + 20.0, rc.position.y + 30.0, "主音量 / MASTER", 12, Palette.PH if sel else Palette.TXT)
			var bar := Rect2(rc.position.x + 340.0, rc.position.y + 24.0, 300.0, 8.0)
			draw_rect(bar, Palette.a(Palette.LINE, 0.9))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * _master, bar.size.y)), Palette.a(Palette.PH, 0.95))
			var knob_x := bar.position.x + bar.size.x * _master
			draw_rect(Rect2(knob_x - 2.0, bar.position.y - 4.0, 4.0, 16.0), Palette.PH)
			_txt_r(mono, rc.end.x - 20.0, rc.position.y + 30.0, "%d%%" % int(round(_master * 100.0)), 11, Palette.a(Palette.TXT, 0.95))
		elif i == 1:
			_txt(cjk, rc.position.x + 20.0, rc.position.y + 30.0, "静音 / MUTE", 12, Palette.PH if sel else Palette.TXT)
			_txt_r(mono, rc.end.x - 20.0, rc.position.y + 30.0, "ON" if _muted else "OFF", 12, Palette.AMBER if _muted else Palette.a(Palette.DIM, 0.95))
		else:
			_txt(cjk, rc.position.x + 20.0, rc.position.y + 30.0, "返回 / BACK", 12, Palette.PH if sel else Palette.TXT)
			_txt_r(mono, rc.end.x - 20.0, rc.position.y + 30.0, "ESC", 8, Palette.a(Palette.FAINT, 0.9))
	_txt(cjk, pr.position.x + 28.0, pr.end.y - 28.0, "←→ 调节音量 · ↑↓ 选择 · ENTER 确认 / 切换 · ESC 返回", 8, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, pr.end.x - 28.0, pr.end.y - 28.0, "AUDIO ABSENT → SILENT", 7, Palette.a(Palette.FAINT, 0.6))
