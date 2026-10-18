class_name TacticalPlot
extends Control

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

# 立体战术图：轴测投影 + 地球遮挡。
# 坐标系：以本舰为原点，方位 000 向上，距离 1 km ≈ 1.25 px，
# y 轴按 0.42 压缩做出俯视倾角。高度单独抬升。
# 不做自由相机——这是仪表，不是观光。

const ORIGIN := Vector2(564.0, 416.0)
const UNIT := 1.25
const SQUASH := 0.42
const LIMB_R := 2600.0
const EARTH_CX := 564.0
const EARTH_CY := 3210.0

var state
var mono: Font
var cjk: Font
var _t := 0.0
var _stars: Array[Vector3] = []

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()
	_make_stars()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20871103
	for i in 150:
		var x := rng.randf_range(0.0, 1128.0)
		var y := rng.randf_range(0.0, 720.0)
		var a := rng.randf_range(0.08, 0.42)
		if y < _limb_y(x) - 6.0:
			_stars.append(Vector3(x, y, a))

func _limb_y(x: float) -> float:
	var dx := x - EARTH_CX
	return EARTH_CY - sqrt(maxf(LIMB_R * LIMB_R - dx * dx, 0.0))

func _visible(p: Vector2) -> bool:
	return p.y < _limb_y(p.x) - 1.5

func _proj(bearing: float, range_km: float, alt_km := 0.0) -> Vector2:
	var b := deg_to_rad(bearing)
	var e := sin(b) * range_km
	var n := cos(b) * range_km
	return Vector2(
		ORIGIN.x + e * UNIT,
		ORIGIN.y - n * UNIT * SQUASH - alt_km * UNIT
	)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	_draw_stars()
	_draw_earth()
	_draw_grid()
	_draw_orbits()
	_draw_burn_plan()
	_draw_contacts()
	_draw_own()
	_draw_chrome()
	_draw_sweep()

# ── 背景 ────────────────────────────────────────────────

func _draw_stars() -> void:
	for s in _stars:
		var a: float = s.z
		if not state.capture:
			a *= 0.72 + 0.28 * sin(_t * 1.6 + s.x * 0.11)
		draw_rect(Rect2(s.x, s.y, 1.0, 1.0), Palette.a(Palette.BLUE, a))

func _draw_earth() -> void:
	var pts := PackedVector2Array()
	var x := -30.0
	while x <= 1160.0:
		pts.append(Vector2(x, _limb_y(x)))
		x += 8.0
	pts.append(Vector2(1160.0, size.y + 24.0))
	pts.append(Vector2(-30.0, size.y + 24.0))
	draw_colored_polygon(pts, Palette.EARTH)

	# 纬度弧
	var a0 := -PI * 0.5 - 0.27
	var a1 := -PI * 0.5 + 0.27
	for i in range(3):
		var rr := LIMB_R - 44.0 * float(i + 1)
		draw_arc(Vector2(EARTH_CX, EARTH_CY), rr, a0, a1, 140, Palette.a(Palette.GRID, 0.44 - i * 0.08), 1.0, true)

	# 经线
	for x0 in [-140.0, 220.0, 560.0, 900.0, 1240.0]:
		var x1: float = 564.0 + (float(x0) - 564.0) * 0.35
		draw_line(Vector2(x0, size.y + 12.0), Vector2(x1, _limb_y(x1) + 8.0), Palette.a(Palette.GRID, 0.30), 1.0, true)

	# 晨昏线：右侧压暗
	for i in range(18):
		var sx := 740.0 + float(i) * 23.0
		draw_rect(
			Rect2(sx, _limb_y(sx), 24.0, size.y - _limb_y(sx) + 24.0),
			Palette.a(Color.BLACK, 0.006 * float(i))
		)

	# 大气辉光
	for i in range(14):
		var r := LIMB_R + float(i) * 1.7
		var a := 0.165 * pow(1.0 - float(i) / 14.0, 2.0)
		draw_arc(Vector2(EARTH_CX, EARTH_CY), r, a0, a1, 160, Palette.a(Palette.BLUE, a), 1.0, true)
	draw_arc(Vector2(EARTH_CX, EARTH_CY), LIMB_R, a0, a1, 160, Palette.a(Palette.BLUE, 0.92), 1.2, true)
	draw_arc(Vector2(EARTH_CX, EARTH_CY), LIMB_R - 0.8, a0, a1, 160, Palette.a(Color("#C9F4FF"), 0.28), 0.7, true)

# ── 网格 ────────────────────────────────────────────────

func _draw_grid() -> void:
	for r in [50.0, 100.0, 200.0, 400.0]:
		var pts: Array[Vector2] = []
		for i in range(0, 361, 3):
			pts.append(_proj(float(i), r))
		_polyline_masked(pts, Palette.a(Palette.GRID, 0.80 if r < 400.0 else 0.55), 1.0)
	for b in range(0, 360, 30):
		var p := _proj(float(b), 425.0)
		_line_masked(ORIGIN, p, Palette.a(Palette.GRID, 0.34), 1.0)
		if int(b) % 90 == 0 and _visible(p):
			_txt(mono, p.x - 7.0, p.y + 2.0, "%03d" % b, 7, Palette.a(Palette.FAINT, 0.85))
	for r in [100.0, 200.0, 400.0]:
		var lp := _proj(322.0, r)
		if _visible(lp):
			_txt_r(mono, lp.x - 3.0, lp.y - 9.0, "%d" % int(r), 7, Palette.a(Palette.DIM, 0.55))

	# 抬高一层：让"高度"可见
	var hi: Array[Vector2] = []
	for i in range(0, 361, 3):
		hi.append(_proj(float(i), 200.0, 40.0))
	_polyline_masked(hi, Palette.a(Palette.PH_FAINT, 0.42), 1.0, true)
	for b in [0.0, 90.0, 180.0, 270.0]:
		var p0 := _proj(b, 200.0, 0.0)
		var p1 := _proj(b, 200.0, 40.0)
		if _visible(p0) and _visible(p1):
			draw_line(p0, p1, Palette.a(Palette.PH_FAINT, 0.30), 1.0, true)
	var al := _proj(300.0, 200.0, 40.0)
	if _visible(al):
		_txt(mono, al.x + 3.0, al.y - 10.0, "ALT +40", 7, Palette.a(Palette.PH_FAINT, 0.9))

# ── 轨道 ────────────────────────────────────────────────

func _draw_orbits() -> void:
	# 本舰轨道（滑行段）
	var pts: Array[Vector2] = []
	for i in range(0, 100):
		var x := -20.0 + 1180.0 * float(i) / 99.0
		var dx := x - ORIGIN.x
		var y := ORIGIN.y + 0.00016 * dx * dx - 0.05 * dx
		pts.append(Vector2(x, y))
	_polyline_masked(pts, Palette.a(Palette.PH_DIM, 0.30), 1.2)
	var ly := ORIGIN.y + 0.00016 * pow(120.0 - ORIGIN.x, 2) - 0.05 * (120.0 - ORIGIN.x)
	_txt(cjk, 120.0, ly - 15.0, "轨道 400 km · 顺行", 8, Palette.a(Palette.DIM, 0.75))

	# 敌方轨道：另一个平面，斜穿画面
	var epts: Array[Vector2] = []
	for i in range(0, 90):
		var x2 := -20.0 + 1180.0 * float(i) / 89.0
		var y2 := 600.0 - 0.36 * x2 + 0.00008 * x2 * x2
		epts.append(Vector2(x2, y2))
	_polyline_masked(epts, Palette.a(Palette.RED, 0.20), 1.0, true)
	_txt(cjk, 900.0, 318.0, "敌方轨道 · i 51.6°", 8, Palette.a(Palette.RED, 0.55))

# ── 命令 ────────────────────────────────────────────────

func _draw_burn_plan() -> void:
	# 待生效的变轨矢量（含离面分量），不是"未来位置"
	var p1 := _proj(340.0, 70.0, 60.0)
	draw_line(ORIGIN, p1, Palette.a(Palette.PH, 0.50), 1.3, true)
	var dir := (p1 - ORIGIN).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var tip := p1
	draw_colored_polygon(
		PackedVector2Array([tip, tip - dir * 9.0 + perp * 4.0, tip - dir * 9.0 - perp * 4.0]),
		Palette.a(Palette.PH, 0.75)
	)
	draw_circle(ORIGIN, 3.0, Palette.a(Palette.PH, 0.9))
	draw_arc(ORIGIN, 16.0, 0, TAU, 32, Palette.a(Palette.PH, 0.22), 1.0, true)

	_txt(cjk, p1.x - 128.0, p1.y - 14.0, "点火 T+06.2s", 9, Palette.PH)
	_txt(mono, p1.x - 128.0, p1.y - 1.0, "Δv 84 m/s · BRG 340", 8, Palette.a(Palette.PH_DIM, 1.0))
	_txt(mono, p1.x - 128.0, p1.y + 12.0, "PLANE CHANGE +60 km", 7, Palette.a(Palette.PH_FAINT, 1.0))

	# 目标节点
	var wp := _proj(18.0, 392.0, 34.0)
	if _visible(wp):
		draw_polyline(PackedVector2Array([wp + Vector2(0, -6), wp + Vector2(6, 0), wp + Vector2(0, 6), wp + Vector2(-6, 0), wp + Vector2(0, -6)]), Palette.a(Palette.PH_DIM, 0.7), 1.0)
		_txt(mono, wp.x + 10.0, wp.y - 6.0, "NODE B-2", 7, Palette.a(Palette.PH_DIM, 0.9))

# ── 接触 ────────────────────────────────────────────────

func _draw_contacts() -> void:
	for t in state.tracks:
		if t.get("own", false):
			continue
		if t.get("bearing_only", false):
			_draw_bearing_only(t)
			continue
		var p := _proj(t.bearing, t.range, t.alt)
		if not _visible(p):
			continue
		var col := _side_color(t)
		var base := _proj(t.bearing, t.range, 0.0)
		if absf(t.alt) > 3.0 and _visible(base):
			draw_dashed_line(base, p, Palette.a(col, 0.30), 1.0, 2.0)
			draw_circle(base, 1.4, Palette.a(col, 0.35))
		if int(t.level) <= 2:
			_draw_error_ellipse(p, t, col)
		_draw_symbol(p, t, col)
		_draw_track_label(t, p, col)

func _draw_bearing_only(t: Dictionary) -> void:
	var b := deg_to_rad(float(t.bearing))
	var half := deg_to_rad(1.7)
	var far := 460.0
	var p1 := _proj(rad_to_deg(b - half), far)
	var p2 := _proj(rad_to_deg(b + half), far)
	draw_colored_polygon(PackedVector2Array([ORIGIN, p1, p2]), Palette.a(Palette.AMBER, 0.035))
	draw_dashed_line(ORIGIN, p1, Palette.a(Palette.AMBER, 0.30), 1.0, 3.0)
	draw_dashed_line(ORIGIN, p2, Palette.a(Palette.AMBER, 0.30), 1.0, 3.0)
	var arc: Array[Vector2] = []
	for i in range(0, 21):
		var bb := rad_to_deg(b - half) + rad_to_deg(2.0 * half) * float(i) / 20.0
		arc.append(_proj(bb, 340.0))
	_dashed_polyline(arc, Palette.a(Palette.AMBER, 0.38), 1.0, 5.0)
	var mid := _proj(float(t.bearing), 340.0)
	_txt(cjk, mid.x - 112.0, mid.y - 34.0, "方位 302°", 9, Palette.AMBER)
	_txt(cjk, mid.x - 112.0, mid.y - 21.0, "距离未知 · 陈旧 41s", 8, Palette.a(Palette.AMBER, 0.65))
	_txt(mono, mid.x - 112.0, mid.y - 8.0, "BEARING ONLY / MEMORY", 7, Palette.a(Palette.AMBER, 0.4))

func _draw_error_ellipse(p: Vector2, t: Dictionary, col: Color) -> void:
	var big := int(t.level) <= 1
	var rx := 34.0 if big else 17.0
	var ry := 15.0 if big else 8.0
	var rot := deg_to_rad(float(t.bearing))
	var pts: Array[Vector2] = []
	for i in range(0, 361, 10):
		var a := deg_to_rad(float(i))
		pts.append(p + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	_dashed_polyline(pts, Palette.a(col, 0.38), 1.0, 3.0)

func _draw_symbol(p: Vector2, t: Dictionary, col: Color) -> void:
	if t.get("ghost", false):
		var g: Array[Vector2] = [
			p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6),
			p + Vector2(-6, 0), p + Vector2(0, -6)
		]
		_dashed_polyline(g, Palette.a(col, 0.55), 1.0, 2.0)
		draw_polyline(PackedVector2Array([p + Vector2(-9, 0), p + Vector2(9, 0)]), Palette.a(col, 0.22), 1.0)
		return
	match t.side:
		"friend":
			draw_circle(p, 3.2, col)
			draw_arc(p, 8.0, 0, TAU, 28, Palette.a(col, 0.55), 1.0, true)
			draw_line(p + Vector2(8, 0), p + Vector2(13, 0), Palette.a(col, 0.6), 1.0)
		"hostile":
			var d := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0), p + Vector2(0, -7)])
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), Palette.a(col, 0.12))
			draw_polyline(d, col, 1.3, true)
			if int(t.level) >= 3:
				for q in [Vector2(-12, -12), Vector2(12, -12), Vector2(-12, 12), Vector2(12, 12)]:
					draw_line(p + q, p + q * 0.72, Palette.a(col, 0.55), 1.0)
		"unknown":
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Palette.a(col, 0.10))
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Palette.a(col, 0.8), false, 1.0)
			draw_circle(p, 1.0, col)
		_:
			draw_circle(p, 2.5, col)

func _draw_track_label(t: Dictionary, p: Vector2, col: Color) -> void:
	var off: Vector2 = t.off
	var lx := p.x + off.x
	var ly := p.y + off.y
	var idf := cjk if Fonts.has_cjk(t.id) else mono
	var dim := 0.5 if t.get("stale", false) else 1.0
	if t.side == "friend":
		_txt(idf, lx, ly, t.id + " · " + t.cls, 11, Palette.a(col, dim))
	else:
		_txt(idf, lx, ly, t.id, 11, Palette.a(col, dim))
	var sub := "%03d° · %d km" % [int(t.bearing), int(t.range)]
	if t.get("ghost", false):
		sub = "未归档 · 方位 %03d°" % int(t.bearing)
	_txt(mono, lx, ly + 12.0, sub, 8, Palette.a(col, 0.60 * dim))
	if int(t.level) > 0:
		var lv := "L%d" % int(t.level)
		draw_rect(Rect2(p.x + 10.0, p.y - 22.0, 17.0, 11.0), Palette.a(col, 0.10))
		draw_rect(Rect2(p.x + 10.0, p.y - 22.0, 17.0, 11.0), Palette.a(col, 0.45), false, 1.0)
		_txt(mono, p.x + 13.0, p.y - 21.0, lv, 7, Palette.a(col, 0.9))

func _draw_own() -> void:
	var p := ORIGIN
	draw_circle(p, 2.6, Palette.PH)
	draw_arc(p, 11.0, 0, TAU, 36, Palette.a(Palette.PH, 0.65), 1.0, true)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var b := deg_to_rad(a)
		var d := Vector2(sin(b), -cos(b))
		draw_line(p + d * 7.0, p + d * 13.0, Palette.a(Palette.PH, 0.55), 1.0)
	var hd := Vector2(sin(deg_to_rad(75.0)), -cos(deg_to_rad(75.0)) * SQUASH).normalized()
	draw_line(p, p + hd * 24.0, Palette.a(Palette.PH, 0.40), 1.0)
	_txt(cjk, p.x + 16.0, p.y + 8.0, "哈马丹", 11, Palette.PH)
	_txt(mono, p.x + 16.0, p.y + 21.0, "OWN · 400 km", 7, Palette.a(Palette.PH_DIM, 0.9))

# ── 界面装饰 ────────────────────────────────────────────

func _draw_chrome() -> void:
	_txt(cjk, 16.0, 10.0, "战术态势", 14, Palette.PH)
	_txt(mono, 16.0, 29.0, "TACTICAL PLOT", 8, Palette.DIM)
	_txt(cjk, 16.0, 41.0, "LVLH · 半径 400 km · 高度 ×1", 8, Palette.FAINT)
	var blink := 0.55 + 0.45 * sin(_t * 3.2)
	draw_circle(Vector2(8.0, 16.0), 2.2, Palette.a(Palette.PH, blink * 0.8))

	_draw_compass()
	_draw_optical()
	_draw_legend()

func _draw_compass() -> void:
	var c := Vector2(size.x - 48.0, 46.0)
	draw_arc(c, 18.0, 0, TAU, 48, Palette.a(Palette.LINE2, 0.8), 1.0, true)
	for i in range(12):
		var ang := deg_to_rad(float(i) * 30.0)
		var d := Vector2(sin(ang), -cos(ang))
		var l := 4.0 if i % 3 == 0 else 2.0
		draw_line(c + d * 18.0, c + d * (18.0 - l), Palette.a(Palette.PH_DIM, 0.55), 1.0)
	_txt(mono, c.x - 2.5, c.y - 33.0, "N", 7, Palette.PH_DIM)
	var nd := Vector2(sin(deg_to_rad(75.0)), -cos(deg_to_rad(75.0)))
	var pp := Vector2(-nd.y, nd.x)
	draw_line(c, c + nd * 12.0, Palette.a(Palette.PH, 0.75), 1.0)
	draw_colored_polygon(PackedVector2Array([c + nd * 14.0, c + nd * 8.0 + pp * 3.0, c + nd * 8.0 - pp * 3.0]), Palette.a(Palette.PH, 0.8))
	_txt(cjk, c.x - 90.0, c.y - 5.0, "帧 LVLH", 7, Palette.a(Palette.FAINT, 0.9))

func _draw_optical() -> void:
	var r := Rect2(size.x - 252.0, 76.0, 236.0, 132.0)
	draw_rect(r, Color("#020504"))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 90:
		var x := rng.randf_range(r.position.x + 2.0, r.end.x - 2.0)
		var y := rng.randf_range(r.position.y + 2.0, r.end.y - 2.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), Palette.a(Palette.TXT, rng.randf_range(0.02, 0.10)))
	var tp := r.position + Vector2(r.size.x * 0.63, r.size.y * 0.46)
	for i in range(6):
		draw_circle(tp, 2.0 + float(i) * 2.4, Palette.a(Palette.BLUE, maxf(0.012, 0.05 - float(i) * 0.007)))
	draw_circle(tp, 1.5, Color("#DDF6FF"))
	draw_line(tp - Vector2(9, 0), tp + Vector2(9, 0), Palette.a(Palette.BLUE, 0.45), 0.8)
	draw_line(tp - Vector2(0, 9), tp + Vector2(0, 9), Palette.a(Palette.BLUE, 0.45), 0.8)
	var cp := r.get_center()
	draw_line(cp - Vector2(30, 0), cp + Vector2(30, 0), Palette.a(Palette.LINE2, 0.35), 0.8)
	draw_line(cp - Vector2(0, 24), cp + Vector2(0, 24), Palette.a(Palette.LINE2, 0.35), 0.8)
	_txt(cjk, r.position.x + 6.0, r.position.y + 5.0, "光学通道 / OPTICAL", 7, Palette.a(Palette.BLUE, 0.75))
	_txt(mono, r.end.x - 42.0, r.position.y + 5.0, "CH-2 8×", 7, Palette.a(Palette.BLUE, 0.55))
	_txt(mono, r.position.x + 6.0, r.end.y - 12.0, "4471-K  +2.1", 7, Palette.a(Palette.BLUE, 0.55))

func _draw_legend() -> void:
	_txt(cjk, 16.0, 664.0, "图例 / LEGEND", 7, Palette.a(Palette.FAINT, 0.9))
	var y := 682.0
	draw_circle(Vector2(22.0, y + 5.0), 3.0, Palette.PH)
	_txt(cjk, 32.0, y, "友军", 8, Palette.DIM)
	draw_rect(Rect2(84.0, y + 1.0, 8.0, 8.0), Palette.a(Palette.AMBER, 0.8), false, 1.0)
	_txt(cjk, 96.0, y, "未知", 8, Palette.DIM)
	var d := PackedVector2Array([Vector2(158, y + 5), Vector2(163, y + 0), Vector2(168, y + 5), Vector2(163, y + 10), Vector2(158, y + 5)])
	draw_polyline(d, Palette.RED, 1.0)
	_txt(cjk, 174.0, y, "敌对", 8, Palette.DIM)
	var g: Array[Vector2] = [
		Vector2(236, y + 5), Vector2(241, y + 0), Vector2(246, y + 5),
		Vector2(241, y + 10), Vector2(236, y + 5)
	]
	_dashed_polyline(g, Palette.PH_FAINT, 1.0, 2.0)
	_txt(cjk, 252.0, y, "幽影", 8, Palette.DIM)

	var y2 := 704.0
	draw_line(Vector2(16, y2 + 5), Vector2(34, y2 + 5), Palette.a(Palette.PH, 0.8), 1.0)
	_txt(cjk, 40.0, y2, "现时", 7, Palette.DIM)
	draw_dashed_line(Vector2(82, y2 + 5), Vector2(100, y2 + 5), Palette.a(Palette.PH, 0.7), 1.0, 4.0)
	_txt(cjk, 106.0, y2, "计划", 7, Palette.DIM)
	draw_dashed_line(Vector2(148, y2 + 5), Vector2(166, y2 + 5), Palette.a(Palette.RED, 0.5), 1.0, 2.0)
	_txt(cjk, 172.0, y2, "预测", 7, Palette.DIM)

func _draw_sweep() -> void:
	var y := fmod(_t * 27.0, size.y)
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.a(Palette.PH, 0.022), 1.0)

# ── 工具 ────────────────────────────────────────────────

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

func _polyline_masked(pts: Array[Vector2], color: Color, width := 1.0, dashed := false) -> void:
	var run: Array[Vector2] = []
	for p in pts:
		if _visible(p):
			run.append(p)
		else:
			_flush_run(run, color, width, dashed)
			run.clear()
	_flush_run(run, color, width, dashed)

func _flush_run(run: Array[Vector2], color: Color, width: float, dashed: bool) -> void:
	if run.size() < 2:
		return
	if dashed:
		_dashed_polyline(run, color, width, 5.0)
	else:
		draw_polyline(PackedVector2Array(run), color, width, true)

func _dashed_polyline(pts: Array[Vector2], color: Color, width := 1.0, dash := 4.0) -> void:
	var on := true
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		if on:
			draw_line(a, b, color, width, true)
		acc += a.distance_to(b)
		if acc >= dash:
			acc = 0.0
			on = not on

func _line_masked(a: Vector2, b: Vector2, color: Color, width := 1.0) -> void:
	var n := maxi(2, int(a.distance_to(b) / 6.0))
	var prev := a
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / float(n))
		if _visible(prev) and _visible(p):
			draw_line(prev, p, color, width, true)
		prev = p

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)

