class_name Hud
extends Control

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

const TOP := Rect2(40, 40, 1840, 72)
const TRACKS := Rect2(60, 120, 320, 752)
const UNIT := Rect2(1540, 120, 320, 752)
const LOG := Rect2(60, 880, 1120, 156)
const TIME := Rect2(1200, 880, 660, 156)

var state
var map
var mono: Font
var cjk: Font
var row_rects: Array[Rect2] = []
var time_rects: Array[Rect2] = []
var menu_rects: Array[Rect2] = []
var menu_open := false
var menu_t := 0.0

const SENSOR_RECT := Rect2(720, 128, 424, 28)
const MENU_RECT := Rect2(720, 160, 424, 320)
const AUTO_RECT := Rect2(1380, 128, 144, 28)

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()

func _process(delta: float) -> void:
	menu_t += delta

func _draw() -> void:
	if state.boot_t < 1.7:
		_draw_boot()
		return
	_draw_bezel()
	_draw_top()
	_draw_tracks()
	_draw_unit()
	_draw_log()
	_draw_time()
	_draw_map_ui()
	if menu_open:
		_draw_sensor_menu()
	_draw_screen_edge()

func click(p: Vector2) -> void:
	if SENSOR_RECT.has_point(p):
		menu_open = not menu_open
		menu_t = 0.0
		return
	if menu_open:
		for i in range(menu_rects.size()):
			if menu_rects[i].has_point(p):
				state.sensor = i
				menu_open = false
				return
		if not MENU_RECT.has_point(p):
			menu_open = false
			return
	for i in range(row_rects.size()):
		if row_rects[i].has_point(p):
			state.selected = i
			queue_redraw()
			return
	for i in range(time_rects.size()):
		if time_rects[i].has_point(p):
			state.time_scale = [1.0, 10.0, 60.0, 300.0][i]
			state.paused = false
			queue_redraw()
			return

func consumes(p: Vector2) -> bool:
	if SENSOR_RECT.has_point(p):
		return true
	if menu_open and MENU_RECT.has_point(p):
		return true
	for r in row_rects:
		if r.has_point(p):
			return true
	for r in time_rects:
		if r.has_point(p):
			return true
	return false

# ── 外壳 ────────────────────────────────────────────────

func _draw_bezel() -> void:
	draw_rect(Rect2(0, 0, 1920, 40), Palette.BEZEL)
	draw_rect(Rect2(0, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(1880, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(0, 1040, 1920, 40), Palette.BEZEL)
	draw_line(Vector2(0, 1), Vector2(1920, 1), Palette.a(Palette.TXT, 0.04), 1.0)
	draw_line(Vector2(0, 1078), Vector2(1920, 1078), Color(0, 0, 0, 0.6), 1.0)
	_txt(mono, 56, 10, "DATUM // CISLUNAR COMMAND", 8, Palette.a(Palette.PH, 0.8))
	_txt(cjk, 56, 22, "监督官显控台 · CS-9", 7, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, 1864, 1053, "FUI-7 / SER. 0447 / 地月管区", 7, Palette.a(Palette.FAINT, 0.8))
	for i in range(3):
		var c := Palette.PH if i == 0 else (Palette.AMBER if i == 1 else Palette.RED)
		draw_circle(Vector2(1802.0 + float(i) * 16.0, 20.0), 2.4, Palette.a(c, 0.9))
	for i in range(30):
		var bx := 60.0 + float(i) * 3.0
		var bh := 6.0 + float((i * 5) % 7)
		draw_rect(Rect2(bx, 1064.0 - bh, 1.0, bh), Palette.a(Palette.FAINT, 0.3))

# ── 顶栏 ────────────────────────────────────────────────

func _draw_top() -> void:
	draw_rect(TOP, Palette.a(Palette.BG, 0.6))
	draw_line(Vector2(40, 112), Vector2(1880, 112), Palette.a(Palette.LINE, 1.0), 1.0)
	_txt(mono, 60, 46, "SUPERVISOR / 监督官", 8, Palette.a(Palette.DIM, 0.9))
	var total := int(state.clock)
	var hh := int(total / 3600.0)
	var mm := int(total / 60.0) % 60
	var ss := total % 60
	var clock_s := "T+%02d:%02d:%02d" % [hh, mm, ss]
	_bl(mono, 60, 84, clock_s, 26, Palette.TXT)
	var cw := mono.get_string_size(clock_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_bl(mono, 60.0 + cw + 3.0, 84, ".%d" % int(fmod(state.clock, 1.0) * 10.0), 12, Palette.a(Palette.DIM, 0.8))
	_txt(mono, 60, 92, "CISLUNAR TRANSIT / 地月转移", 7, Palette.a(Palette.FAINT, 0.9))

	draw_line(Vector2(520, 50), Vector2(520, 102), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(mono, 548, 47, "NOTICE 4471 / RECEIVERSHIP", 8, Palette.a(Palette.AMBER, 0.8))
	_txt(cjk, 548, 66, "宽限期剩余", 9, Palette.DIM)
	_bl(mono, 626, 84, _hms(float(state.grace_left)), 22, Palette.AMBER)
	draw_rect(Rect2(548, 96, 420, 1), Palette.a(Palette.AMBER, 0.18))
	draw_rect(Rect2(548, 96, 14, 1), Palette.AMBER)
	_txt_r(mono, 968, 88, "216 h", 7, Palette.a(Palette.AMBER, 0.45))

	draw_line(Vector2(1288, 50), Vector2(1288, 102), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(mono, 1300, 47, "LINK / 链路", 7, Palette.FAINT)
	_bl(mono, 1304, 84, "0.4s", 13, Palette.TXT)
	_txt(mono, 1300, 92, "LASER · LOCKED", 7, Palette.a(Palette.PH, 0.55))
	_txt(mono, 1440, 47, "SCALE / 时标", 7, Palette.FAINT)
	_bl(mono, 1436, 84, "×%d" % int(state.time_scale), 16, Palette.TXT)
	_txt(mono, 1440, 92, "AUTO-SLOW ON", 7, Palette.AMBER)
	_txt(mono, 1580, 47, "FLEET Δv", 7, Palette.FAINT)
	_bl(mono, 1568, 84, "1,420", 16, Palette.TXT)
	_bl(mono, 1636, 84, "m/s", 8, Palette.DIM)
	_txt(mono, 1580, 92, "45% REMAIN", 7, Palette.FAINT)
	_txt(mono, 1730, 47, "ROE / 交战规则", 7, Palette.FAINT)
	_bl(mono, 1700, 84, "HOLD", 12, Palette.RED)
	_txt(cjk, 1730, 92, "不得先开火", 7, Palette.DIM)

# ── 接触列表 ────────────────────────────────────────────

func _draw_tracks() -> void:
	_panel(TRACKS, "TRACKS / 接触", "%02d" % state.tracks.size())
	row_rects.clear()
	for i in range(state.tracks.size()):
		var y := 168.0 + float(i) * 80.0
		row_rects.append(Rect2(60, y, 320, 80))
		_draw_row(state.tracks[i], i, y)
	draw_line(Vector2(60, 808), Vector2(380, 808), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(mono, 76, 816, "PASSIVE / 被动扫描", 7, Palette.a(Palette.PH, 0.55))
	_txt_r(mono, 364, 816, "ELINT 监听", 7, Palette.a(Palette.DIM, 0.7))
	_chip(Rect2(76, 832, 88, 17), "IR 被动", Palette.PH, true)
	_chip(Rect2(170, 832, 88, 17), "光学 8×", Palette.PH, true)
	_chip(Rect2(264, 832, 88, 17), "雷达 关", Palette.FAINT, false)

func _draw_row(t: Dictionary, i: int, y: float) -> void:
	var col := _side_color(t)
	var sel: bool = i == int(state.selected)
	var fg := Palette.BG if sel else Palette.TXT
	var dimv := 0.45 if t.get("stale", false) else 1.0
	if sel:
		draw_rect(Rect2(60, y, 320, 80), Palette.PH)
	else:
		draw_line(Vector2(76, y + 79), Vector2(364, y + 79), Palette.a(Palette.LINE, 0.5), 1.0)

	var idf := cjk if Fonts.has_cjk(t.id) else mono
	_txt(idf, 76, y + 12, t.id, 13, fg if sel else Palette.a(col, dimv))
	_txt(cjk, 170, y + 16, t.cls, 8, Palette.a(Palette.BG, 0.65) if sel else Palette.a(Palette.DIM, dimv))
	_level(346.0, y + 10.0, t, sel)

	var line2 := ""
	if t.get("own", false):
		line2 = "CENTER / 基准"
	elif t.get("bearing_only", false):
		line2 = "BRG 302° · RANGE ?"
	else:
		line2 = "BRG %03d° · %s" % [int(t.bearing), _range(t.range)]
	_txt(mono, 76, y + 36, line2, 8, Palette.a(Palette.BG, 0.75) if sel else Palette.a(Palette.DIM, dimv))
	var cl := "编队"
	if t.side == "hostile":
		cl = "%+.1f km/s" % float(t.closing)
	elif t.get("own", false):
		cl = "—"
	_txt_r(mono, 364, y + 36, cl, 8, Palette.BG if sel else Palette.a(col, 0.85))

	var age_s := "实时"
	if t.get("stale", false):
		age_s = "陈旧 %ds" % int(t.age)
	elif not t.get("own", false):
		age_s = "更新 %02ds" % int(t.age)
	_txt(cjk, 76, y + 53, age_s, 7, Palette.a(Palette.BG, 0.6) if sel else Palette.a(Palette.FAINT, dimv))

	var frac := 1.0
	if not t.get("own", false):
		frac = clampf(1.0 - float(t.age) / 45.0 * 0.75, 0.12, 1.0)
	draw_rect(Rect2(76, y + 66, 288, 2), Palette.a(Palette.BG, 0.25) if sel else Palette.a(Palette.LINE, 0.8))
	draw_rect(Rect2(76, y + 66, 288.0 * frac, 2), Palette.BG if sel else Palette.a(col, 0.55 * dimv))

func _level(x: float, y: float, t: Dictionary, sel: bool) -> void:
	var lv := "L%d" % int(t.level)
	var c := Palette.BG if sel else _side_color(t)
	draw_rect(Rect2(x, y, 18, 12), Palette.a(c, 0.10))
	draw_rect(Rect2(x, y, 18, 12), Palette.a(c, 0.5), false, 1.0)
	_txt(mono, x + 3, y + 1, lv, 7, Palette.a(c, 0.9))

# ── 旗舰面板 ────────────────────────────────────────────

func _draw_unit() -> void:
	_panel(UNIT, "FLAGSHIP / 旗舰", "L4")
	var u: Dictionary = state.unit
	_txt(cjk, 1556, 168, u.name, 24, Palette.TXT)
	_txt(mono, 1556, 198, u.en, 8, Palette.DIM)
	_txt(cjk, 1556, 212, u.cls + " · " + u.role, 10, Palette.PH)
	_txt(cjk, 1556, 228, u.faction, 8, Palette.DIM)
	draw_line(Vector2(1540, 240), Vector2(1860, 240), Palette.a(Palette.LINE, 0.9), 1.0)

	var stats := [
		["MASS / 干重", u.mass], ["CREW / 编制", u.crew],
		["ACCEL / 加速", u.accel], ["ORBIT / 轨道", u.orbit],
		["INC / 倾角", u.inc], ["PERIOD / 周期", u.period]
	]
	for i in range(6):
		var cx := 1556.0 + float(i % 2) * 150.0
		var cy := 252.0 + float(i / 2) * 28.0
		_txt(mono, cx, cy, stats[i][0], 7, Palette.FAINT)
		_txt(mono, cx, cy + 12.0, stats[i][1], 9, Palette.TXT)

	_txt(mono, 1556, 336, "SYSTEMS / 系统", 7, Palette.FAINT)
	for i in range(5):
		var cy := 354.0 + float(i) * 24.0
		var sname: String = u.systems[i][0]
		var sv: float = u.systems[i][1]
		_txt(cjk, 1556, cy, sname, 9, Palette.DIM)
		_bar(Rect2(1636, cy + 4, 130, 4), sv, _sys_color(sv))
		_txt_r(mono, 1860, cy, "%d%%" % int(sv * 100.0), 8, Palette.TXT)

	_txt(mono, 1556, 484, "Δv BUDGET / 预算", 7, Palette.FAINT)
	_txt(mono, 1556, 496, u.dv, 30, Palette.PH)
	var dw := mono.get_string_size(u.dv, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_txt(mono, 1556.0 + dw + 6.0, 524, "m/s", 9, Palette.DIM)
	_txt(mono, 1556, 552, "/ %s MAX" % u.dv_max, 8, Palette.DIM)
	_bar(Rect2(1556, 566, 288, 5), 0.45, Palette.PH)
	_txt(mono, 1556, 576, "45% REMAIN · 已耗 1,730", 7, Palette.FAINT)

	_txt(mono, 1556, 596, "WEAPONS / 武器", 7, Palette.FAINT)
	for i in range(3):
		var cy := 614.0 + float(i) * 20.0
		_txt(cjk, 1556, cy, u.weapons[i][0], 9, Palette.DIM)
		_txt_r(mono, 1860, cy, u.weapons[i][1], 8, Palette.TXT)

	draw_rect(Rect2(1556, 684, 288, 34), Palette.a(Palette.AMBER, 0.05))
	draw_rect(Rect2(1556, 684, 2, 34), Palette.a(Palette.AMBER, 0.8))
	_txt(mono, 1566, 689, "DAMAGE / 损管", 7, Palette.AMBER)
	_txt(cjk, 1566, 701, u.damage + " · " + u.damage2, 8, Palette.TXT)

	_txt(mono, 1556, 744, "SENSOR ARRAY / 传感器", 7, Palette.FAINT)
	_txt(cjk, 1556, 760, "6 MODULES · 2 ONLINE", 8, Palette.DIM)
	_txt(mono, 1556, 776, "CCS-7 · R-9 · 听-3 · M-2", 7, Palette.a(Palette.PH, 0.5))
	draw_line(Vector2(1540, 820), Vector2(1860, 820), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(mono, 1556, 828, "DOCK 2/2", 8, Palette.PH)
	_txt_r(mono, 1860, 828, "HULL 100%", 8, Palette.DIM)

# ── 命令日志 ────────────────────────────────────────────

func _draw_log() -> void:
	_panel(LOG, "EVENT LOG / 命令日志", "12")
	var cmd_left := maxf(0.0, 6.2 - float(state.elapsed))
	var pending := cmd_left > 0.0
	for i in range(state.log_lines.size()):
		var l: Dictionary = state.log_lines[i]
		var y := 918.0 + float(i) * 24.0
		_txt(mono, 76, y, "T+" + l.t, 9, Palette.a(Palette.FAINT, 0.95))
		_txt(cjk, 150, y - 1, l.text, 10, Palette.a(Palette.TXT, 0.92))
		var tw := cjk.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if l.arg != "":
			_txt(mono, 150.0 + tw + 10.0, y, l.arg, 8, Palette.a(Palette.AMBER, 0.7))
		if i == 0 and pending:
			draw_rect(Rect2(150, y + 16, 930, 1), Palette.a(Palette.AMBER, 0.10))
			draw_rect(Rect2(150, y + 16, 930.0 * (1.0 - cmd_left / 6.2), 1), Palette.a(Palette.AMBER, 0.55))
		_log_status(l, i, y, cmd_left, pending)

func _log_status(l: Dictionary, i: int, y: float, cmd_left: float, pending: bool) -> void:
	var txt := ""
	var col := Palette.DIM
	match l.status:
		"PENDING":
			txt = "待生效 %.1fs" % cmd_left
			col = Palette.AMBER
		"EXEC":
			txt = "已执行"
			col = Palette.PH_DIM
		"HOLD":
			txt = "暂缓"
			col = Palette.AMBER
		"RX":
			txt = "已接收"
			col = Palette.BLUE
	var r := Rect2(1080, y - 1, 84, 15)
	draw_rect(r, Palette.a(col, 0.06))
	draw_rect(r, Palette.a(col, 0.40), false, 1.0)
	_txt(cjk, r.position.x + 7, r.position.y + 3, txt, 7, col)

# ── 时间轴 ──────────────────────────────────────────────

func _draw_time() -> void:
	_panel(TIME, "REPLAY / 态势回放", "60s")
	time_rects.clear()
	var scales := [1.0, 10.0, 60.0, 300.0]
	var names := ["1×", "10×", "60×", "300×"]
	for i in range(4):
		var r := Rect2(1216.0 + float(i) * 46.0, 912, 40, 20)
		time_rects.append(r)
		var active := absf(float(state.time_scale) - scales[i]) < 0.1
		if active:
			draw_rect(r, Palette.PH)
			_txt(mono, r.position.x + 8, r.position.y + 4, names[i], 9, Palette.BG)
		else:
			draw_rect(r, Palette.a(Palette.LINE, 0.5), false, 1.0)
			_txt(mono, r.position.x + 8, r.position.y + 4, names[i], 9, Palette.a(Palette.DIM, 0.75))
	_txt(mono, 1404, 917, "SPACE PAUSE / 1-4 SCALE", 7, Palette.FAINT)

	var x0 := 1216.0
	var x1 := 1844.0
	var w := x1 - x0
	var y := 966.0
	draw_line(Vector2(x0, y), Vector2(x1, y), Palette.a(Palette.LINE2, 0.9), 1.0)
	for i in range(13):
		var x := x0 + w * float(i) / 12.0
		var h := 9.0 if i % 3 == 0 else 4.0
		draw_line(Vector2(x, y - h), Vector2(x, y), Palette.a(Palette.PH_DIM, 0.6), 1.0)
	var events := [0.18, 0.42, 0.66, 0.86]
	var ecols := [Palette.AMBER, Palette.PH, Palette.AMBER, Palette.BLUE]
	for i in range(events.size()):
		var ex := x0 + w * float(events[i])
		draw_line(Vector2(ex, y - 10), Vector2(ex, y + 3), Palette.a(ecols[i], 0.28), 1.0)
		draw_circle(Vector2(ex, y), 2.6, Palette.a(ecols[i], 0.9))
	draw_line(Vector2(x1, 950), Vector2(x1, 974), Palette.PH, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x1, 944), Vector2(x1 + 6, 950), Vector2(x1 - 6, 950)]), Palette.PH)
	_txt(mono, x0, 980, "T-60", 7, Palette.FAINT)
	_txt(mono, x0 + w * 0.5 - 12.0, 980, "T-30", 7, Palette.FAINT)
	_txt_r(mono, x1, 980, "NOW", 7, Palette.PH)
	draw_line(Vector2(1200, 996), Vector2(1860, 996), Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(mono, 1216, 1004, "MEMORY DECAY 60s / 记忆衰减", 7, Palette.FAINT)
	_txt_r(mono, 1844, 1004, "CURSOR T+62:13.8", 7, Palette.a(Palette.AMBER, 0.55))

# ── 地图上的传感器条 / 菜单 / 模式 ─────────────────────

func _draw_map_ui() -> void:
	# 传感器条
	draw_rect(SENSOR_RECT, Palette.a(Palette.PANEL, 0.95))
	draw_rect(SENSOR_RECT, Palette.a(Palette.LINE, 1.0), false, 1.0)
	var s: Dictionary = state.sensors[int(state.sensor)]
	var sc := Color(s.color)
	_txt(mono, SENSOR_RECT.position.x + 10, SENSOR_RECT.position.y + 6, "SENSOR", 7, Palette.a(Palette.PH, 0.8))
	_glyph(SENSOR_RECT.position.x + 64, SENSOR_RECT.position.y + 6, 16.0, s.glyph, sc)
	_txt(cjk, SENSOR_RECT.position.x + 90, SENSOR_RECT.position.y + 8, s.mfr + " · " + s.model, 9, Palette.TXT)
	_txt(cjk, SENSOR_RECT.position.x + 214, SENSOR_RECT.position.y + 9, s.mode, 7, Palette.DIM)
	_txt(mono, SENSOR_RECT.end.x - 14, SENSOR_RECT.position.y + 8, "▾", 10, Palette.PH)
	_txt_r(mono, SENSOR_RECT.end.x - 30, SENSOR_RECT.position.y + 14, s.sig, 7, Palette.a(Palette.FAINT, 0.9))

	# AUTO 模式指示
	draw_rect(AUTO_RECT, Palette.a(Palette.PANEL, 0.9))
	draw_rect(AUTO_RECT, Palette.a(Palette.LINE, 0.9), false, 1.0)
	draw_circle(AUTO_RECT.position + Vector2(10, 14), 2.0, Palette.PH)
	var auto_txt := "AUTO / PLANAR" if (map != null and bool(map.ortho)) else "AUTO / 3D"
	_txt(mono, AUTO_RECT.position.x + 18, AUTO_RECT.position.y + 8, auto_txt, 8, Palette.PH)

func _draw_sensor_menu() -> void:
	menu_rects.clear()
	var r := MENU_RECT
	draw_rect(r, Palette.a(Palette.PANEL2, 0.98))
	draw_rect(r, Palette.a(Palette.LINE2, 1.0), false, 1.0)
	_txt(mono, r.position.x + 10, r.position.y + 7, "SENSOR ARRAY / 传感器阵列", 8, Palette.PH)
	_txt_r(mono, r.end.x - 10, r.position.y + 7, "06 MODULES", 7, Palette.FAINT)
	draw_line(Vector2(r.position.x, r.position.y + 28), Vector2(r.end.x, r.position.y + 28), Palette.a(Palette.LINE, 1.0), 1.0)

	for i in range(state.sensors.size()):
		var s: Dictionary = state.sensors[i]
		var row := Rect2(r.position.x, r.position.y + 32.0 + float(i) * 48.0, r.size.x, 48.0)
		menu_rects.append(row)
		var sel := i == int(state.sensor)
		var sc := Color(s.color)
		if sel:
			draw_rect(row, Palette.PH)
		_glyph(row.position.x + 12, row.position.y + 12, 24.0, s.glyph, Palette.BG if sel else sc)
		_txt(cjk, row.position.x + 48, row.position.y + 8, s.mfr, 7, Palette.a(Palette.BG, 0.65) if sel else Palette.DIM)
		_txt(mono, row.position.x + 48, row.position.y + 20, s.model, 10, Palette.BG if sel else Palette.TXT)
		_txt(cjk, row.position.x + 130, row.position.y + 20, s.mode, 8, Palette.a(Palette.BG, 0.75) if sel else Palette.a(Palette.TXT, 0.8))
		_txt_r(mono, row.end.x - 10, row.position.y + 8, s.sig, 7, Palette.a(Palette.BG, 0.65) if sel else Palette.FAINT)
		if not sel:
			draw_line(Vector2(row.position.x + 8, row.end.y), Vector2(row.end.x - 8, row.end.y), Palette.a(Palette.LINE, 0.55), 1.0)

	# 开场：准星闪 → 绿框 → 1-2-4-3 象限硬切
	var order := [0, 1, 3, 2]
	for k in range(4):
		var delay := 0.08 + float(k) * 0.06
		if menu_t < delay:
			var qx := 0.0 if order[k] % 2 == 0 else r.size.x * 0.5
			var qy := 0.0 if order[k] < 2 else r.size.y * 0.5
			draw_rect(Rect2(r.position + Vector2(qx, qy), r.size * 0.5), Palette.BG)
	var frame_a := clampf(menu_t / 0.12, 0.0, 1.0)
	draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Palette.a(Palette.PH, 0.8 * frame_a), false, 2.0)
	if menu_t < 0.14:
		var c := r.get_center()
		draw_circle(c, 2.0, Palette.PH)
		draw_line(c - Vector2(18, 0), c + Vector2(18, 0), Palette.a(Palette.PH, 0.8), 1.0)
		draw_line(c - Vector2(0, 18), c + Vector2(0, 18), Palette.a(Palette.PH, 0.8), 1.0)

func _glyph(x: float, y: float, s: float, kind: String, c: Color) -> void:
	var cx := x + s * 0.5
	var cy := y + s * 0.5
	var r := s * 0.38
	match kind:
		"ring":
			draw_arc(Vector2(cx, cy), r, 0, TAU, 24, c, 1.2, true)
			draw_circle(Vector2(cx, cy), 1.5, c)
		"hex":
			var p: Array[Vector2] = []
			for i in range(7):
				var a := TAU * float(i) / 6.0 - PI * 0.5
				p.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(PackedVector2Array(p), c, 1.2, true)
		"web":
			for i in range(3):
				draw_arc(Vector2(cx, cy), r * (0.35 + float(i) * 0.3), 0, TAU, 24, c, 1.0, true)
			for i in range(4):
				var a := TAU * float(i) / 4.0
				draw_line(Vector2(cx, cy), Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r, c, 1.0)
		"frame":
			draw_rect(Rect2(cx - r, cy - r * 0.7, r * 2.0, r * 1.4), c, false, 1.0)
			draw_line(Vector2(cx - r - 2, cy), Vector2(cx + r + 2, cy), c, 1.0)
			draw_line(Vector2(cx, cy - r - 2), Vector2(cx, cy + r + 2), c, 1.0)
		"gate":
			draw_line(Vector2(cx - r, cy - r), Vector2(cx - r, cy + r), c, 1.2)
			draw_line(Vector2(cx + r, cy - r), Vector2(cx + r, cy + r), c, 1.2)
			draw_line(Vector2(cx - r, cy), Vector2(cx + r, cy), c, 1.0)
		"jag":
			var p2 := PackedVector2Array([Vector2(cx - r, cy + r * 0.6), Vector2(cx - r * 0.4, cy - r * 0.5), Vector2(cx + r * 0.1, cy + r * 0.2), Vector2(cx + r, cy - r * 0.7)])
			draw_polyline(p2, c, 1.2, true)
		_:
			draw_circle(Vector2(cx, cy), r, c)

# ── 启动动画 ────────────────────────────────────────────

func _draw_boot() -> void:
	var t: float = state.boot_t
	var w := 1920.0
	var h := 1080.0
	draw_rect(Rect2(0, 0, w, h), Palette.BG)
	var scan_y := h * clampf(t / 1.5, 0.0, 1.0)
	draw_rect(Rect2(0, scan_y, w, 1), Palette.a(Palette.PH, 0.8))
	draw_rect(Rect2(0, scan_y - 60.0, w, 1), Palette.a(Palette.PH, 0.10))
	_corners(Rect2(30, 30, w - 60, h - 60), 26.0, Palette.a(Palette.PH, 0.5))
	var jitter := 2.0 if fmod(t * 14.0, 1.0) < 0.18 else 0.0
	_txt(mono, 120.0 + jitter, 150.0, "CISLUNAR", 64, Palette.PH)
	_txt(mono, 122.0, 224.0, "COMMAND / 地月指挥", 13, Palette.a(Palette.PH, 0.55))
	_txt(mono, 122.0, 246.0, "COLD START · SUPERVISOR AUTHORITY", 8, Palette.a(Palette.DIM, 0.8))
	var lines := [
		"DATUM CCS / COLD START",
		"MOUNT CISLUNAR GRID ........ OK",
		"LINK APSIS ................. 0.4s",
		"SENSOR ARRAY ............... 06",
		"RECEIVERSHIP NOTICE 4471 ... RX",
		"SUPERVISOR AUTHORITY ....... GRANTED"
	]
	for i in range(lines.size()):
		if t * 8.0 > float(i):
			_txt(mono, 120, 300 + i * 30, lines[i], 11, Palette.a(Palette.PH, 0.85))
	var p := clampf((t - 0.15) / 1.25, 0.0, 1.0)
	draw_rect(Rect2(120, 620, 420, 2), Palette.a(Palette.PH, 0.15))
	draw_rect(Rect2(120, 620, 420 * p, 2), Palette.PH)
	_txt(mono, 120, 634, "INITIALIZING %03d%%" % int(p * 100.0), 8, Palette.a(Palette.PH, 0.6))
	for i in range(72):
		var bx := 120.0 + float(i % 24) * 34.0
		var by := 700.0 + float(i / 24) * 34.0
		var on := fmod(absf(sin(float(i) * 12.9898) * 43758.5453), 1.0) < clampf(t * 0.9, 0.0, 1.0)
		if on:
			draw_rect(Rect2(bx, by, 30, 30), Palette.a(Palette.PH, 0.10))
			draw_rect(Rect2(bx, by, 30, 30), Palette.a(Palette.PH, 0.35), false, 1.0)
	var st := ["LINK 0.4s", "ARRAY 06", "NOTICE 4471", "APSIS 192,000 km", "ROE HOLD"]
	for i in range(st.size()):
		if t * 6.0 > float(i):
			_txt_r(mono, 1800, 300 + i * 24, st[i], 9, Palette.a(Palette.DIM, 0.8))
# ── 工具 ────────────────────────────────────────────────

func _panel(r: Rect2, title: String, meta: String) -> void:
	draw_rect(r, Palette.a(Palette.PANEL, 0.92))
	draw_rect(r, Palette.a(Palette.LINE, 1.0), false, 1.0)
	_corners(r, 10.0, Palette.a(Palette.PH, 0.35))
	_txt(mono, r.position.x + 16, r.position.y + 12, title, 8, Palette.a(Palette.PH, 0.8))
	_txt_r(mono, r.end.x - 16, r.position.y + 12, meta, 8, Palette.a(Palette.FAINT, 0.8))
	draw_line(Vector2(r.position.x, r.position.y + 28), Vector2(r.end.x, r.position.y + 28), Palette.a(Palette.LINE, 1.0), 1.0)

func _chip(r: Rect2, label: String, col: Color, active: bool) -> void:
	draw_rect(r, Palette.a(col, 0.07 if active else 0.02))
	draw_rect(r, Palette.a(col, 0.45 if active else 0.20), false, 1.0)
	_txt(cjk, r.position.x + 6, r.position.y + 4, label, 7, Palette.a(col, 0.9 if active else 0.45))

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

func _corners(r: Rect2, l: float, c: Color) -> void:
	draw_line(r.position, r.position + Vector2(l, 0), c, 1.0)
	draw_line(r.position, r.position + Vector2(0, l), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), c, 1.0)
	draw_line(r.end, r.end - Vector2(l, 0), c, 1.0)
	draw_line(r.end, r.end - Vector2(0, l), c, 1.0)

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

func _range(v: float) -> String:
	if v < 10000.0:
		return "%d km" % int(v)
	return "%.1f Mm" % (v / 1000.0)

func _hms(s: float) -> String:
	var t := int(s)
	return "%02d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, t % 60]

func _bl(f: Font, x: float, baseline: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _bl_r(f: Font, xr: float, baseline: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_bl(f, xr - w, baseline, s, sz, c)

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)

func _draw_screen_edge() -> void:
	draw_rect(Rect2(40, 40, 1840, 1000), Color(0, 0, 0, 1), false, 1.0)
	draw_rect(Rect2(41, 41, 1838, 998), Palette.a(Palette.TXT, 0.02), false, 1.0)