class_name Hud
extends Control

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

const TOP := Rect2(40, 40, 1840, 72)
const TRACKS := Rect2(60, 124, 320, 752)
const UNIT := Rect2(1540, 124, 320, 752)
const LOG := Rect2(60, 884, 1120, 156)
const TIME := Rect2(1200, 884, 660, 156)

var state
var mono: Font
var cjk: Font
var row_rects: Array[Rect2] = []
var time_rects: Array[Rect2] = []
var _t := 0.0

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()

func _process(delta: float) -> void:
	_t += delta

func _draw() -> void:
	_draw_bezel()
	_draw_top()
	_draw_tracks()
	_draw_unit()
	_draw_log()
	_draw_time()
	_draw_screen_edge()

func click(p: Vector2) -> void:
	for i in row_rects.size():
		if row_rects[i].has_point(p):
			state.selected = i
			queue_redraw()
			return
	for i in time_rects.size():
		if time_rects[i].has_point(p):
			state.time_scale = [1.0, 10.0, 60.0, 300.0][i]
			state.paused = false
			queue_redraw()
			return

func _draw_bezel() -> void:
	draw_rect(Rect2(0, 0, 1920, 40), Palette.BEZEL)
	draw_rect(Rect2(0, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(1880, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(0, 1040, 1920, 40), Palette.BEZEL)
	draw_line(Vector2(0, 1), Vector2(1920, 1), Palette.a(Palette.TXT, 0.035), 1.0)
	draw_line(Vector2(1, 0), Vector2(1, 1080), Palette.a(Palette.TXT, 0.025), 1.0)
	draw_line(Vector2(0, 1078), Vector2(1920, 1078), Color(0, 0, 0, 0.55), 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for i in 240:
		var edge := rng.randi_range(0, 3)
		var x := 0.0
		var y := 0.0
		match edge:
			0:
				x = rng.randf_range(0.0, 1920.0)
				y = rng.randf_range(2.0, 38.0)
			1:
				x = rng.randf_range(2.0, 38.0)
				y = rng.randf_range(0.0, 1080.0)
			2:
				x = rng.randf_range(1882.0, 1918.0)
				y = rng.randf_range(0.0, 1080.0)
			_:
				x = rng.randf_range(0.0, 1920.0)
				y = rng.randf_range(1042.0, 1078.0)
		draw_rect(Rect2(x, y, 1, 1), Palette.a(Palette.TXT, rng.randf_range(0.010, 0.030)))

	_screw(Vector2(20, 20))
	_screw(Vector2(1900, 20))
	_screw(Vector2(20, 1060))
	_screw(Vector2(1900, 1060))

	_txt(mono, 56, 11, "CS-9", 9, Palette.a(Palette.PH_DIM, 0.85))
	_txt(cjk, 56, 23, "战术显控台", 7, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, 1864, 1053, "TACTICAL DISPLAY UNIT · SER. 0447", 7, Palette.a(Palette.FAINT, 0.8))

	for i in range(3):
		var c := Palette.PH
		if i == 1:
			c = Palette.AMBER
		elif i == 2:
			c = Palette.RED
		var lp := Vector2(1802.0 + float(i) * 16.0, 20.0)
		draw_circle(lp, 2.6, Palette.a(c, 0.9))
		draw_circle(lp, 6.0, Palette.a(c, 0.08))

	for i in range(36):
		var bx := 60.0 + float(i) * 3.0
		var bh := 7.0 + float((i * 7) % 7)
		draw_rect(Rect2(bx, 1064.0 - bh, 1.0, bh), Palette.a(Palette.FAINT, 0.32))

func _screw(p: Vector2) -> void:
	draw_circle(p, 5.5, Color("#050606"))
	draw_arc(p, 5.5, 0, TAU, 24, Color("#232A27"), 1.0, true)
	draw_line(p + Vector2(-3, -1), p + Vector2(3, 1), Color("#1A201D"), 1.0)

func _draw_top() -> void:
	draw_rect(TOP, Palette.a(Palette.BG, 0.55))
	draw_line(Vector2(40, 112), Vector2(1880, 112), Palette.a(Palette.LINE, 0.95), 1.0)

	_txt(cjk, 60, 47, "监督官席 / SUPERVISOR", 7, Palette.FAINT)
	var total := int(state.clock)
	var hh := int(total / 3600.0)
	var mm := int(total / 60.0) % 60
	var ss := total % 60
	var clock_s := "T+%02d:%02d:%02d" % [hh, mm, ss]
	_txt(mono, 60, 57, clock_s, 26, Palette.PH)
	var cw := mono.get_string_size(clock_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var tenth := int(fmod(float(state.clock), 1.0) * 10.0)
	_txt(mono, 60.0 + cw + 2.0, 70, ".%d" % tenth, 13, Palette.a(Palette.PH, 0.55))
	_txt(cjk, 60, 92, "任务时间 / MISSION ELAPSED", 7, Palette.FAINT)

	draw_line(Vector2(520, 50), Vector2(520, 102), Palette.a(Palette.LINE, 0.7), 1.0)

	_txt(cjk, 548, 47, "接管通知 4471 号 / RECEIVERSHIP NOTICE", 7, Palette.a(Palette.AMBER, 0.72))
	_txt(cjk, 548, 66, "宽限期剩余", 9, Palette.DIM)
	_txt(mono, 626, 56, _hms(float(state.grace_left)), 24, Palette.AMBER)
	draw_rect(Rect2(548, 96, 420, 1), Palette.a(Palette.AMBER, 0.16))
	draw_rect(Rect2(548, 96, 14, 1), Palette.AMBER)
	_txt_r(mono, 968, 87, "216 h", 7, Palette.a(Palette.AMBER, 0.45))

	draw_line(Vector2(1288, 50), Vector2(1288, 102), Palette.a(Palette.LINE, 0.7), 1.0)

	_txt(cjk, 1300, 47, "链路 / LINK", 7, Palette.FAINT)
	_txt(mono, 1300, 58, "LASER 0.4s", 11, Palette.PH)
	for i in range(4):
		draw_rect(Rect2(1300.0 + float(i) * 10.0, 92, 7, 3), Palette.a(Palette.PH, 0.70 if i < 3 else 0.14))

	_txt(cjk, 1440, 47, "时标 / TIMESCALE", 7, Palette.FAINT)
	_txt(mono, 1440, 58, "×%d" % int(state.time_scale), 18, Palette.PH)
	_txt(cjk, 1440, 92, "AUTO-SLOW 开", 7, Palette.AMBER)

	_txt(cjk, 1580, 47, "编队 Δv", 7, Palette.FAINT)
	_txt(mono, 1580, 58, "8,420", 18, Palette.PH)
	_txt(mono, 1652, 64, "m/s", 8, Palette.DIM)
	_txt(cjk, 1580, 92, "剩余 72%", 7, Palette.FAINT)

	_txt(cjk, 1730, 47, "交战规则 / ROE", 7, Palette.FAINT)
	_txt(mono, 1730, 58, "HOLD", 12, Palette.AMBER)
	_txt(cjk, 1730, 92, "不得先开火", 7, Palette.DIM)

func _draw_tracks() -> void:
	_panel(TRACKS)
	_txt(cjk, 76, 134, "接触 / TRACKS", 11, Palette.TXT)
	_txt_r(mono, 364, 134, "%02d" % state.tracks.size(), 12, Palette.PH_DIM)
	_txt(cjk, 76, 153, "威胁排序 / THREAT ↓", 7, Palette.FAINT)
	draw_line(Vector2(60, 170), Vector2(380, 170), Palette.a(Palette.LINE, 0.9), 1.0)

	row_rects.clear()
	for i in range(state.tracks.size()):
		var y := 176.0 + float(i) * 82.0
		row_rects.append(Rect2(60, y, 320, 82))
		_draw_track_row(state.tracks[i], i, y)

	draw_line(Vector2(60, 836), Vector2(380, 836), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(cjk, 76, 843, "传感器 / SENSOR", 7, Palette.FAINT)
	_chip(Rect2(76, 854, 72, 16), "IR 被动", Palette.PH, true)
	_chip(Rect2(154, 854, 64, 16), "光学 8×", Palette.PH, true)
	_chip(Rect2(224, 854, 62, 16), "雷达 关", Palette.FAINT, false)

func _draw_track_row(t: Dictionary, i: int, y: float) -> void:
	var col := _side_color(t)
	var sel: bool = i == int(state.selected)
	if sel:
		draw_rect(Rect2(60, y, 320, 82), Palette.a(Palette.PANEL2, 0.95))
		draw_rect(Rect2(60, y, 2, 82), col)
		draw_rect(Rect2(60, y, 320, 1), Palette.a(col, 0.22))
	draw_line(Vector2(76, y + 81), Vector2(364, y + 81), Palette.a(Palette.LINE, 0.55), 1.0)

	var dim := 0.45 if t.get("stale", false) else 1.0
	var idf := cjk if Fonts.has_cjk(t.id) else mono
	_txt(idf, 76, y + 12, t.id, 13, Palette.a(col, dim))
	_txt(cjk, 160, y + 14, t.cls, 9, Palette.a(Palette.DIM, dim))
	_draw_level(346.0, y + 12.0, t, col)

	var line2 := ""
	if t.get("own", false):
		line2 = "基准 / REFERENCE"
	elif t.get("bearing_only", false):
		line2 = "方位 302° · 距离未知"
	else:
		line2 = "方位 %03d° · %d km" % [int(t.bearing), int(t.range)]
	_txt(mono, 76, y + 35, line2, 8, Palette.a(Palette.DIM, dim))

	var cl := "编队"
	if t.side == "hostile":
		cl = "%+.1f km/s" % float(t.closing)
	elif t.get("own", false):
		cl = "—"
	_txt_r(mono, 364, y + 35, cl, 8, Palette.a(col, 0.8 * dim))

	var age_s := "实时"
	if t.get("stale", false):
		age_s = "陈旧 %ds" % int(t.age)
	elif not t.get("own", false):
		age_s = "更新 %02ds" % int(t.age)
	_txt(cjk, 76, y + 53, age_s, 8, Palette.a(Palette.AMBER if t.get("stale", false) else Palette.FAINT, dim))

	var frac := 1.0
	if not t.get("own", false):
		frac = clampf(1.0 - float(t.age) / 45.0 * 0.75, 0.12, 1.0)
	draw_rect(Rect2(76, y + 66, 288, 2), Palette.a(Palette.LINE, 0.8))
	draw_rect(Rect2(76, y + 66, 288.0 * frac, 2), Palette.a(col, 0.50 * dim))

func _draw_level(x: float, y: float, t: Dictionary, col: Color) -> void:
	var lv := "L%d" % int(t.level)
	draw_rect(Rect2(x, y, 18, 12), Palette.a(col, 0.08))
	draw_rect(Rect2(x, y, 18, 12), Palette.a(col, 0.42), false, 1.0)
	_txt(mono, x + 3, y + 1, lv, 7, Palette.a(col, 0.9))

func _draw_unit() -> void:
	_panel(UNIT)
	# _draw_ship_watermark()

	var u: Dictionary = state.unit
	_txt(cjk, 1556, 138, "选中单位 / UNIT", 7, Palette.FAINT)
	_txt(cjk, 1556, 150, u.name, 24, Palette.TXT)
	_txt(mono, 1556, 181, u.en, 8, Palette.DIM)
	_txt(cjk, 1556, 195, u.cls + " · " + u.role, 10, Palette.PH)
	_txt(cjk, 1556, 211, u.faction, 8, Palette.DIM)
	draw_line(Vector2(1540, 226), Vector2(1860, 226), Palette.a(Palette.LINE, 0.9), 1.0)

	var stats := [
		["干重 MASS", u.mass], ["编制 CREW", u.crew],
		["加速度 ACCEL", u.accel], ["轨道 ORBIT", u.orbit],
		["倾角 INC", u.inc], ["周期 PERIOD", u.period]
	]
	for i in range(6):
		var cx := 1556.0 + float(i % 2) * 150.0
		var cy := 236.0 + float(i / 2) * 26.0
		_txt(cjk, cx, cy, stats[i][0], 8, Palette.DIM)
		_txt(mono, cx, cy + 10.0, stats[i][1], 10, Palette.TXT)

	_txt(cjk, 1556, 316, "系统 / SYSTEMS", 7, Palette.FAINT)
	_txt_r(mono, 1860, 316, "AVG 83%", 8, Palette.DIM)
	for i in range(5):
		var cy := 334.0 + float(i) * 26.0
		var sname: String = u.systems[i][0]
		var sv: float = u.systems[i][1]
		_txt(cjk, 1556, cy, sname, 9, Palette.DIM)
		_bar(Rect2(1636, cy + 4, 130, 4), sv, _sys_color(sv))
		_txt_r(mono, 1860, cy, "%d%%" % int(sv * 100.0), 8, Palette.TXT)

	_txt(cjk, 1556, 470, "Δv 预算 / BUDGET", 7, Palette.FAINT)
	_txt(mono, 1556, 482, u.dv, 30, Palette.PH)
	var dw := mono.get_string_size(u.dv, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_txt(mono, 1556.0 + dw + 5.0, 502, "m/s", 9, Palette.DIM)
	_txt(mono, 1556, 536, "/ %s 满" % u.dv_max, 8, Palette.DIM)
	_bar(Rect2(1556, 550, 288, 5), 0.90, Palette.PH)
	_txt(cjk, 1556, 560, "剩余 90% · 已耗 310 m/s", 7, Palette.FAINT)

	_txt(cjk, 1556, 580, "武器 / WEAPONS", 7, Palette.FAINT)
	for i in range(3):
		var cy := 596.0 + float(i) * 20.0
		_txt(cjk, 1556, cy, u.weapons[i][0], 9, Palette.DIM)
		_txt_r(mono, 1860, cy, u.weapons[i][1], 8, Palette.TXT)

	draw_rect(Rect2(1556, 660, 288, 34), Palette.a(Palette.AMBER, 0.05))
	draw_rect(Rect2(1556, 660, 2, 34), Palette.a(Palette.AMBER, 0.8))
	_txt(cjk, 1566, 665, "损管 / DAMAGE", 7, Palette.AMBER)
	_txt(cjk, 1566, 677, u.damage + " · " + u.damage2, 8, Palette.TXT)

	_txt(cjk, 1556, 706, "姿态 / ATTITUDE", 7, Palette.FAINT)
	draw_rect(Rect2(1556, 718, 62, 58), Palette.a(Palette.LINE, 0.8), false, 1.0)
	var c := Vector2(1587, 747)
	var hd := Vector2(cos(deg_to_rad(12.4)), sin(deg_to_rad(12.4))) * 24.0
	draw_line(c - hd, c + hd, Palette.a(Palette.PH, 0.55), 1.0)
	for k in [-2, -1, 1, 2]:
		var o := Vector2(0, float(k) * 7.0)
		draw_line(c + o + Vector2(-6, 0), c + o + Vector2(6, 0), Palette.a(Palette.PH_FAINT, 0.45), 1.0)
	draw_line(Vector2(1587, 718), Vector2(1587, 724), Palette.a(Palette.PH, 0.5), 1.0)
	draw_circle(c, 1.4, Palette.PH)
	_txt(mono, 1628, 720, "P +12.4°", 8, Palette.TXT)
	_txt(mono, 1628, 732, "Y  -3.1°", 8, Palette.TXT)
	_txt(mono, 1628, 744, "R  +0.8°", 8, Palette.TXT)
	_txt(mono, 1628, 756, "ω  0.02°/s", 7, Palette.DIM)
	_txt(cjk, 1628, 768, "RCS 就绪", 7, Palette.PH_DIM)

	draw_line(Vector2(1540, 820), Vector2(1860, 820), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(cjk, 1556, 828, "损管队列 2 项", 8, Palette.AMBER)
	_txt_r(mono, 1860, 828, "HULL 100%", 8, Palette.DIM)

func _draw_ship_watermark() -> void:
	var col := Palette.a(Palette.PH, 0.10)
	var col2 := Palette.a(Palette.PH, 0.18)
	var cx := 1814.0
	draw_line(Vector2(cx, 150), Vector2(cx, 318), col2, 1.0)
	draw_line(Vector2(cx, 150), Vector2(cx, 166), col, 1.0)
	draw_line(Vector2(cx - 9, 156), Vector2(cx + 9, 156), col, 1.0)
	draw_arc(Vector2(cx, 166), 8.0, 0, PI, 16, col, 1.0, true)
	draw_rect(Rect2(cx - 14, 170, 28, 18), col, false, 1.0)
	draw_rect(Rect2(cx - 18, 188, 36, 24), col, false, 1.0)
	draw_rect(Rect2(cx - 22, 212, 44, 22), col2, false, 1.0)
	draw_rect(Rect2(cx - 20, 214, 40, 18), col, false, 1.0)
	draw_rect(Rect2(cx - 18, 234, 36, 52), col, false, 1.0)
	for k in range(4):
		draw_line(Vector2(cx - 18, 244.0 + float(k) * 10.0), Vector2(cx + 18, 244.0 + float(k) * 10.0), col, 1.0)
	draw_rect(Rect2(cx - 14, 286, 28, 14), col, false, 1.0)
	draw_polyline(PackedVector2Array([
		Vector2(cx - 12, 300), Vector2(cx + 12, 300),
		Vector2(cx + 16, 320), Vector2(cx - 16, 320), Vector2(cx - 12, 300)
	]), col2, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx - 18, 240), Vector2(cx - 44, 224), Vector2(cx - 44, 236), Vector2(cx - 18, 250)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx + 18, 238), Vector2(cx + 44, 220), Vector2(cx + 44, 232), Vector2(cx + 18, 248)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx + 18, 254), Vector2(cx + 42, 266), Vector2(cx + 42, 278), Vector2(cx + 18, 268)]), col, 1.0)
	for k in range(7):
		var yy := 214.0 + float(k) * 12.0
		draw_line(Vector2(cx - 22, yy), Vector2(cx - 17, yy), col, 1.0)
		draw_line(Vector2(cx + 17, yy), Vector2(cx + 22, yy), col, 1.0)

func _draw_log() -> void:
	_panel(LOG)
	_txt(cjk, 76, 893, "命令日志 / COMMAND LOG", 8, Palette.TXT)
	_txt_r(mono, 1164, 893, "12 ENTRIES · NEWEST FIRST", 7, Palette.FAINT)
	draw_line(Vector2(60, 908), Vector2(1180, 908), Palette.a(Palette.LINE, 0.9), 1.0)

	var cmd_left := maxf(0.0, 6.2 - float(state.elapsed))
	var pending := cmd_left > 0.0
	for i in range(state.log_lines.size()):
		var l: Dictionary = state.log_lines[i]
		var y := 918.0 + float(i) * 24.0
		_txt(mono, 76, y, "T+" + l.t, 10, Palette.a(Palette.FAINT, 0.95))
		_txt(cjk, 150, y - 1, l.text, 11, Palette.a(Palette.TXT, 0.92))
		var tw := cjk.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if l.arg != "":
			_txt(mono, 150.0 + tw + 10.0, y, l.arg, 8, Palette.a(Palette.AMBER, 0.7))
		if i == 0 and pending:
			draw_rect(Rect2(150, y + 16, 930, 1), Palette.a(Palette.AMBER, 0.10))
			draw_rect(Rect2(150, y + 16, 930.0 * (1.0 - cmd_left / 6.2), 1), Palette.a(Palette.AMBER, 0.55))
		_log_status(l, i, y, cmd_left, pending)

	var blink := 0.5 + 0.5 * sin(_t * 4.0)
	draw_rect(Rect2(76, 1024, 5, 1), Palette.a(Palette.PH, 0.6 * blink))

func _log_status(l: Dictionary, i: int, y: float, cmd_left: float, pending: bool) -> void:
	var txt := ""
	var col := Palette.DIM
	match l.status:
		"PENDING":
			if pending and i == 0:
				txt = "待生效 %.1fs" % cmd_left
				col = Palette.AMBER
			else:
				txt = "已执行"
				col = Palette.PH_DIM
		"EXEC":
			txt = "已执行"
			col = Palette.PH_DIM
		"HOLD":
			txt = "暂缓 · ROE"
			col = Palette.AMBER
		"RX":
			txt = "已接收"
			col = Palette.BLUE
	var r := Rect2(1080, y - 1, 84, 15)
	draw_rect(r, Palette.a(col, 0.06))
	draw_rect(r, Palette.a(col, 0.40), false, 1.0)
	_txt(cjk, r.position.x + 7, r.position.y + 2, txt, 8, col)

func _draw_time() -> void:
	_panel(TIME)
	_txt(cjk, 1216, 893, "态势回放 / REPLAY", 8, Palette.TXT)
	_txt_r(mono, 1844, 893, "60s BUFFER", 7, Palette.FAINT)

	time_rects.clear()
	var scales := [1.0, 10.0, 60.0, 300.0]
	var names := ["1×", "10×", "60×", "300×"]
	for i in range(4):
		var r := Rect2(1216.0 + float(i) * 46.0, 912, 40, 20)
		time_rects.append(r)
		var active: bool = absf(float(state.time_scale) - float(scales[i])) < 0.1
		if active:
			draw_rect(r, Palette.a(Palette.PH, 0.10))
			draw_rect(r, Palette.a(Palette.PH, 0.65), false, 1.0)
			_txt(mono, r.position.x + 8, r.position.y + 4, names[i], 9, Palette.PH)
		else:
			draw_rect(r, Palette.a(Palette.LINE, 0.5), false, 1.0)
			_txt(mono, r.position.x + 8, r.position.y + 4, names[i], 9, Palette.a(Palette.DIM, 0.75))
	_txt(cjk, 1404, 917, "SPACE 暂停 / 1-4 时标", 7, Palette.FAINT)

	var x0 := 1216.0
	var x1 := 1844.0
	var w := x1 - x0
	var y := 966.0
	draw_rect(Rect2(x0, 952, w * 0.20, 20), Palette.a(Palette.PH, 0.025))
	draw_line(Vector2(x0, y), Vector2(x1, y), Palette.a(Palette.LINE2, 0.9), 1.0)
	for i in range(13):
		var x := x0 + w * float(i) / 12.0
		var h := 9.0 if i % 3 == 0 else 4.0
		draw_line(Vector2(x, y - h), Vector2(x, y), Palette.a(Palette.PH_DIM, 0.70), 1.0)
	var events := [0.18, 0.42, 0.66, 0.86]
	var ecols := [Palette.AMBER, Palette.PH, Palette.AMBER, Palette.BLUE]
	for i in range(events.size()):
		var ex := x0 + w * float(events[i])
		draw_line(Vector2(ex, y - 10), Vector2(ex, y + 3), Palette.a(ecols[i], 0.28), 1.0)
		draw_circle(Vector2(ex, y), 3.0, Palette.a(ecols[i], 0.85))
	draw_line(Vector2(x1, 950), Vector2(x1, 974), Palette.PH, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x1, 944), Vector2(x1 + 6, 950), Vector2(x1 - 6, 950)
	]), Palette.PH)
	_txt(mono, x0, 980, "T-60", 8, Palette.FAINT)
	_txt(mono, x0 + w * 0.5 - 12.0, 980, "T-30", 8, Palette.FAINT)
	_txt_r(mono, x1, 980, "NOW", 8, Palette.PH)

	draw_line(Vector2(1200, 996), Vector2(1860, 996), Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(cjk, 1216, 1004, "记忆衰减 60s · 事件已标记", 7, Palette.FAINT)
	_txt_r(mono, 1844, 1004, "CURSOR T+12:31.4", 7, Palette.a(Palette.AMBER, 0.55))

func _draw_screen_edge() -> void:
	draw_rect(Rect2(40, 40, 1840, 1000), Color(0, 0, 0, 1), false, 1.0)
	draw_rect(Rect2(41, 41, 1838, 998), Palette.a(Palette.TXT, 0.022), false, 1.0)

func _panel(r: Rect2) -> void:
	draw_rect(r, Palette.a(Palette.PANEL, 1.0))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)

func _chip(r: Rect2, label: String, col: Color, active: bool) -> void:
	draw_rect(r, Palette.a(col, 0.07 if active else 0.02))
	draw_rect(r, Palette.a(col, 0.40 if active else 0.20), false, 1.0)
	_txt(cjk, r.position.x + 6, r.position.y + 3, label, 7, Palette.a(col, 0.9 if active else 0.45))

func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Palette.a(Palette.LINE, 0.45))
	var n := 10
	var gap := 1.0
	var w := (r.size.x - gap * float(n - 1)) / float(n)
	var filled := int(round(clampf(frac, 0.0, 1.0) * float(n)))
	for i in range(n):
		var x := r.position.x + float(i) * (w + gap)
		var c := col if i < filled else Palette.a(Palette.LINE, 0.9)
		draw_rect(Rect2(x, r.position.y, w, r.size.y), c)

func _sys_color(v: float) -> Color:
	if v >= 0.85:
		return Palette.PH
	if v >= 0.60:
		return Palette.AMBER
	return Palette.RED

func _side_color(t: Dictionary) -> Color:
	match t.side:
		"friend":
			return Palette.PH
		"hostile":
			return Palette.RED
		"unknown":
			return Palette.AMBER
		"ghost":
			return Palette.PH_FAINT
		_:
			return Palette.TXT

func _hms(s: float) -> String:
	var t := int(s)
	return "%02d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, t % 60]

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)
