extends Control

# 地月立体态势图。
# 中心永远锁在旗舰 APSIS 上；相机围绕它转，不自由平移。
# 3D 透视 / 压平正交两套投影；切换用 80px 黑块硬切（Marathon 式马赛克）。

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

const EARTH_R := 6378.0
const MOON_R := 1737.0
var MOON_POS := Vector3(384400, 0, 0)
var APSIS := Vector3(192000, 0, 12000)

var state
var mono: Font
var cjk: Font

var yaw3d := deg_to_rad(-80.0)
var pitch := deg_to_rad(24.0)
var dist := 520000.0
var ortho := false
var yaw2d := 0.0
var planar_zoom := 1.0
var transition := -1.0
var transition_to := false
var auto_rotate := true

var _t := 0.0
var _stars: Array[Vector2] = []
var _star_a: Array[float] = []
var _tile_pos: Array[Vector2] = []
var _tile_delay: Array[float] = []
var _cam_pos := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _focal := 800.0
var _planar_scale := 0.0014

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()
	_make_stars()
	_make_mosaic()

func _process(delta: float) -> void:
	_t += delta
	if auto_rotate and not ortho:
		yaw3d += 0.012 * delta
	if transition >= 0.0:
		transition += delta
		if transition > 0.5:
			transition = -1.0
	if not ortho and dist > 640000.0:
		set_planar(true)
	elif ortho and dist < 580000.0 and transition < 0.0:
		set_planar(false)
	queue_redraw()

func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20871103
	for i in range(170):
		_stars.append(Vector2(rng.randf(), rng.randf()))
		_star_a.append(rng.randf_range(0.12, 0.55))

func _make_mosaic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var cols := int(ceil(size.x / 80.0))
	var rows := int(ceil(size.y / 80.0))
	var order: Array[int] = []
	for i in range(cols * rows):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in range(order.size()):
		var idx := order[k]
		_tile_pos.append(Vector2(float(idx % cols) * 80.0, float(idx / cols) * 80.0))
		_tile_delay.append(float(k) / float(order.size()) * 0.34)

# ── 相机 ────────────────────────────────────────────────

func _update_camera() -> void:
	if ortho:
		_right = Vector3(cos(yaw2d), sin(yaw2d), 0.0)
		_up = Vector3(-sin(yaw2d), cos(yaw2d), 0.0)
		_fwd = Vector3(0, 0, -1)
		_cam_pos = APSIS + Vector3(0, 0, dist)
		_planar_scale = (size.x * 0.86) / 700000.0 * planar_zoom
	else:
		var cp := cos(pitch)
		var sp := sin(pitch)
		_cam_pos = APSIS + Vector3(cp * cos(yaw3d), cp * sin(yaw3d), sp) * dist
		_fwd = (APSIS - _cam_pos).normalized()
		_right = _fwd.cross(Vector3(0, 0, 1)).normalized()
		_up = _right.cross(_fwd).normalized()
		_focal = (size.y * 0.5) / tan(deg_to_rad(23.0))

func _project(p: Vector3) -> Vector2:
	var d := p - _cam_pos
	if ortho:
		return size * 0.5 + Vector2(d.dot(_right), -d.dot(_up)) * _planar_scale
	var z := d.dot(_fwd)
	if z < 1200.0:
		return Vector2(-1.0e9, -1.0e9)
	return size * 0.5 + Vector2(d.dot(_right) / z * _focal, -d.dot(_up) / z * _focal)

func _ok(p: Vector2) -> bool:
	return p.x > -1.0e8 and p.x > -200.0 and p.x < size.x + 200.0 and p.y > -200.0 and p.y < size.y + 200.0

# ── 绘制 ────────────────────────────────────────────────

func _draw() -> void:
	_update_camera()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	_draw_dots()
	_draw_stars()
	_draw_grid()
	_draw_orbits()
	_draw_rings()
	_draw_bodies()
	_draw_contacts()
	_draw_sensor()
	_draw_center()
	if ortho:
		_draw_planar_compass()
	_draw_chrome()
	_draw_transition()

func _draw_dots() -> void:
	var step := 32.0
	var a := 0.022 + 0.010 * sin(_t * 0.7)
	var y := 0.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, y, 1, 1), Palette.a(Palette.PH, a))
			x += step
		y += step

func _draw_stars() -> void:
	var ox := fposmod(yaw3d * 40.0, size.x)
	for i in range(_stars.size()):
		var s := _stars[i]
		var x := fposmod(s.x * size.x + ox, size.x)
		var y := s.y * size.y
		draw_rect(Rect2(x, y, 1, 1), Palette.a(Palette.TXT, _star_a[i]))

func _draw_grid() -> void:
	var step := 100000.0
	if ortho:
		step = 50000.0
	var lim := 600000.0
	var x := -lim
	while x <= lim:
		var c := Palette.a(Palette.GRID, 0.24 if absf(x) < 1.0 else 0.15)
		_line3(Vector3(x, -lim, 0), Vector3(x, lim, 0), c, 1.0)
		x += step
	var y := -lim
	while y <= lim:
		var c2 := Palette.a(Palette.GRID, 0.24 if absf(y) < 1.0 else 0.15)
		_line3(Vector3(-lim, y, 0), Vector3(lim, y, 0), c2, 1.0)
		y += step
	var p := _project(Vector3(-340000, -230000, 0))
	if _ok(p):
		_txt(mono, p.x, p.y, "ECLIPTIC / 黄道面", 7, Palette.a(Palette.FAINT, 0.8))

func _draw_orbits() -> void:
	# 月球轨道
	var moon: Array[Vector3] = []
	for i in range(0, 181):
		var a := TAU * float(i) / 180.0
		moon.append(Vector3(cos(a) * 384400.0, sin(a) * 384400.0, 0))
	_poly3(moon, Palette.a(Palette.DIM, 0.18), 1.0, false)

	# 地月转移弧：地球 → APSIS → 月球
	var arc: Array[Vector3] = []
	var e := Vector3(0, 0, 0)
	var c := Vector3(192000, 0, 24000)
	var m := MOON_POS
	for i in range(0, 101):
		var t := float(i) / 100.0
		var u := 1.0 - t
		arc.append(e * u * u + c * 2.0 * u * t + m * t * t)
	_poly3(arc, Palette.a(Palette.PH, 0.38), 1.2, false)

	# 舰队轨道
	if ortho or dist < 420000.0:
		var fo: Array[Vector3] = []
		for i in range(0, 65):
			var a := TAU * float(i) / 64.0
			fo.append(APSIS + Vector3(cos(a) * 6000.0, sin(a) * 6000.0, 0))
		_poly3(fo, Palette.a(Palette.PH, 0.30), 1.0, true)

func _draw_rings() -> void:
	for r in [25000.0, 50000.0, 100000.0, 200000.0]:
		var pts: Array[Vector3] = []
		for i in range(0, 97):
			var a := TAU * float(i) / 96.0
			pts.append(APSIS + Vector3(cos(a) * r, sin(a) * r, 0))
		_poly3(pts, Palette.a(Palette.PH, 0.16), 1.0, false)
		var lp := _project(APSIS + Vector3(cos(deg_to_rad(45.0)) * r, sin(deg_to_rad(45.0)) * r, 0))
		if _ok(lp):
			_txt(mono, lp.x + 3, lp.y - 9, "%d" % int(r / 1000.0) + "k", 7, Palette.a(Palette.PH, 0.35))

func _draw_bodies() -> void:
	_body(Vector3.ZERO, EARTH_R, "EARTH / 地球", Palette.PH, 24.0)
	_body(MOON_POS, MOON_R, "MOON / 月球", Palette.DIM, 14.0)

func _body(pos: Vector3, radius: float, label: String, col: Color, min_r: float) -> void:
	var p := _project(pos)
	if not _ok(p):
		return
	var r := min_r
	if ortho:
		r = maxf(radius * _planar_scale, min_r)
	else:
		var d := pos.distance_to(_cam_pos)
		r = maxf(radius / maxf(d, 1.0) * _focal, min_r)
	draw_circle(p, r, Palette.BG)
	for i in range(4):
		draw_arc(p, r + float(i) * 2.0, 0, TAU, 64, Palette.a(col, 0.10 - float(i) * 0.02), 1.0, true)
	draw_arc(p, r, 0, TAU, 64, Palette.a(col, 0.72), 1.0, true)
	# 球面网格：横椭圆 + 两条竖弧
	var ell: Array[Vector2] = []
	for i in range(0, 49):
		var a := TAU * float(i) / 48.0
		ell.append(p + Vector2(cos(a) * r, sin(a) * r * 0.32))
	draw_polyline(PackedVector2Array(ell), Palette.a(col, 0.16), 1.0, true)
	var ell2: Array[Vector2] = []
	for i in range(0, 49):
		var a := TAU * float(i) / 48.0
		ell2.append(p + Vector2(cos(a) * r * 0.42, sin(a) * r))
	draw_polyline(PackedVector2Array(ell2), Palette.a(col, 0.10), 1.0, true)
	var lx := p.x + r + 8.0
	var ly := p.y - 6.0
	if label.begins_with("MOON"):
		ly = p.y + r + 6.0
	if lx > size.x - 150.0:
		lx = p.x - r - 120.0
	_txt(mono, lx, ly, label, 9, Palette.a(col, 0.85))
	if label.begins_with("EARTH"):
		_txt(mono, lx, ly + 11.0, "0 km · R 6,378", 7, Palette.a(col, 0.42))
	else:
		_txt(mono, lx, ly + 11.0, "384,400 km · R 1,737", 7, Palette.a(col, 0.42))

func _draw_contacts() -> void:
	var fan := [22.0, -42.0, 68.0, -118.0]
	var fi := 0
	var cluster := ortho or dist > 180000.0
	for t in state.tracks:
		if t.get("own", false):
			continue
		var pos: Vector3 = t.pos
		var near: bool = pos.distance_to(APSIS) < 12000.0 and t.side == "friend"
		if near and cluster:
			continue
		var p := _project(pos)
		if not _ok(p):
			continue
		if near and not cluster:
			var ang := deg_to_rad(float(fan[fi % fan.size()]))
			fi += 1
			var q := p + Vector2(cos(ang), sin(ang)) * 34.0
			draw_line(p, q, Palette.a(Palette.PH, 0.35), 1.0)
			p = q
		var col := _side_color(t)
		if not ortho and absf(t.alt) > 200.0:
			var base := _project(Vector3(pos.x, pos.y, 0))
			if _ok(base):
				draw_dashed_line(base, p, Palette.a(col, 0.25), 1.0, 2.0)
				draw_circle(base, 1.2, Palette.a(col, 0.3))
		_draw_symbol(p, t, col)
		var off: Vector2 = t.off
		var lx := p.x + off.x
		var ly := p.y + off.y
		var idf := cjk if Fonts.has_cjk(t.id) else mono
		_txt(idf, lx, ly, t.id, 10, Palette.a(col, 0.95))
		_txt(mono, lx, ly + 11.0, _dist_label(t), 7, Palette.a(col, 0.55))
	if cluster:
		var cp := size * 0.5
		draw_rect(Rect2(cp - Vector2(22, 22), Vector2(44, 44)), Palette.a(Palette.PH, 0.30), false, 1.0)
		_txt(mono, cp.x + 30.0, cp.y + 38.0, "ESCORT ×4 / 编队", 7, Palette.a(Palette.PH, 0.70))

func _dist_label(t: Dictionary) -> String:
	var r := float(t.range)
	if r < 10000.0:
		return "%d km" % int(r)
	return "%.1f Mm" % (r / 1000.0)

func _draw_symbol(p: Vector2, t: Dictionary, col: Color) -> void:
	if t.get("ghost", false):
		var g: Array[Vector2] = [p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0), p + Vector2(0, -6)]
		_dashed(g, Palette.a(col, 0.55), 1.0, 2.0)
		return
	match t.side:
		"friend":
			draw_circle(p, 3.0, col)
			draw_arc(p, 7.0, 0, TAU, 24, Palette.a(col, 0.55), 1.0, true)
		"hostile":
			var d := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0), p + Vector2(0, -7)])
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), Palette.a(col, 0.12))
			draw_polyline(d, col, 1.2, true)
		"unknown":
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Palette.a(col, 0.8), false, 1.0)
		_:
			draw_circle(p, 2.5, col)

func _draw_sensor() -> void:
	var sid := int(state.sensor)
	if sid == 0:
		return
	match sid:
		1:
			_radar()
		2:
			_ir()
		3:
			_optical()
		4:
			_iff()
		5:
			_ew()

func _radar() -> void:
	var sweep := fmod(_t * 1.1, TAU)
	var r := 280000.0
	var pts: Array[Vector2] = [_project(APSIS)]
	for i in range(0, 25):
		var a := sweep - 0.55 + 1.10 * float(i) / 24.0
		pts.append(_project(APSIS + Vector3(cos(a) * r, sin(a) * r, 0)))
	var poly := PackedVector2Array()
	for q in pts:
		if _ok(q):
			poly.append(q)
	if poly.size() > 3:
		draw_colored_polygon(poly, Palette.a(Palette.PH, 0.045))
	for i in range(25):
		var a := sweep - 0.55 + 1.10 * float(i) / 24.0
		var q := _project(APSIS + Vector3(cos(a) * r, sin(a) * r, 0))
		if _ok(q):
			draw_line(_project(APSIS), q, Palette.a(Palette.PH, 0.05), 1.0)
	var tip := _project(APSIS + Vector3(cos(sweep) * r, sin(sweep) * r, 0))
	if _ok(tip):
		draw_line(_project(APSIS), tip, Palette.a(Palette.PH, 0.55), 1.4)
	for rr in [100000.0, 200000.0, 280000.0]:
		var arc: Array[Vector2] = []
		for i in range(0, 33):
			var a := sweep - 0.55 + 1.10 * float(i) / 32.0
			arc.append(_project(APSIS + Vector3(cos(a) * rr, sin(a) * rr, 0)))
		var ap := PackedVector2Array()
		for q in arc:
			if _ok(q):
				ap.append(q)
		if ap.size() > 2:
			draw_polyline(ap, Palette.a(Palette.PH, 0.20), 1.0, true)
	_txt(mono, 14.0, size.y - 54.0, "R-9 ACTIVE SWEEP / 主动雷达", 8, Palette.a(Palette.PH, 0.75))
	_txt(mono, 14.0, size.y - 42.0, "BEARING-ONLY UNTIL PAINT", 7, Palette.a(Palette.PH, 0.35))

func _ir() -> void:
	for t in state.tracks:
		if t.get("own", false):
			continue
		var p := _project(t.pos)
		if not _ok(p):
			continue
		var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(t.bearing))
		for k in range(2):
			draw_arc(p, 10.0 + float(k) * 8.0 + pulse * 3.0, 0, TAU, 32, Palette.a(Palette.AMBER, 0.18 - float(k) * 0.05), 1.0, true)
		if t.side == "hostile":
			var b := _project(APSIS + Vector3(cos(deg_to_rad(float(t.bearing))) * 300000.0, sin(deg_to_rad(float(t.bearing))) * 300000.0, 0))
			if _ok(b):
				draw_dashed_line(_project(APSIS), b, Palette.a(Palette.AMBER, 0.18), 1.0, 4.0)
	_txt(mono, 14.0, size.y - 54.0, "IRST 听-3 / 被动红外", 8, Palette.a(Palette.AMBER, 0.8))
	_txt(mono, 14.0, size.y - 42.0, "NO RANGING · BEARING ONLY", 7, Palette.a(Palette.AMBER, 0.38))

func _optical() -> void:
	var mp := _project(MOON_POS)
	if not _ok(mp):
		return
	var r := Rect2(mp - Vector2(110, 72), Vector2(220, 144))
	draw_rect(r, Palette.a(Palette.BLUE, 0.025))
	draw_rect(r, Palette.a(Palette.BLUE, 0.55), false, 1.0)
	var cp := r.get_center()
	draw_line(cp - Vector2(140, 0), cp + Vector2(140, 0), Palette.a(Palette.BLUE, 0.18), 1.0)
	draw_line(cp - Vector2(0, 100), cp + Vector2(0, 100), Palette.a(Palette.BLUE, 0.18), 1.0)
	for i in range(4):
		var sx := r.position.x + 10.0 + float(i) * 52.0
		draw_circle(Vector2(sx, r.position.y + 24.0), 1.0, Palette.a(Palette.TXT, 0.35))
	_txt(mono, r.position.x + 8.0, r.position.y + 5.0, "M-2 OPTICAL / STARE 12.4s", 7, Palette.a(Palette.BLUE, 0.8))
	_txt(mono, r.end.x - 58.0, r.position.y + 5.0, "MAG 8×", 7, Palette.a(Palette.BLUE, 0.55))
	_txt(mono, 14.0, size.y - 54.0, "OPTICAL / 光学凝视", 8, Palette.a(Palette.BLUE, 0.8))
	_txt(mono, 14.0, size.y - 42.0, "STARE 12.4s · 4471-K", 7, Palette.a(Palette.BLUE, 0.4))

func _iff() -> void:
	for k in range(3):
		var rr := fmod(_t * 70.0 + float(k) * 130.0, 390.0)
		var p := _project(APSIS)
		if _ok(p):
			draw_arc(p, rr, 0, TAU, 64, Palette.a(Palette.PH, 0.10 * (1.0 - rr / 390.0)), 1.0, true)
	for t in state.tracks:
		if t.get("own", false):
			continue
		var p := _project(t.pos)
		if not _ok(p):
			continue
		var tag := "F" if t.side == "friend" else ("H" if t.side == "hostile" else "?")
		draw_rect(Rect2(p.x + 7, p.y - 18, 11, 10), Palette.a(Palette.PH, 0.10))
		_txt(mono, p.x + 9, p.y - 17, tag, 7, Palette.a(Palette.PH, 0.85))
	_txt(mono, 14.0, size.y - 54.0, "MK-12 IFF / 敌我识别", 8, Palette.a(Palette.PH, 0.75))

func _ew() -> void:
	for i in range(42):
		var x := fposmod(sin(float(i) * 12.9898 + _t * 2.0) * 43758.5453, 1.0) * size.x
		var y := fposmod(sin(float(i) * 78.233 + _t * 3.1) * 12345.6789, 1.0) * size.y
		draw_rect(Rect2(x, y, 2, 1), Palette.a(Palette.RED, 0.18))
	for i in range(2):
		var p := Vector2(size.x * 0.62 + float(i) * 46.0, size.y * 0.36 + float(i) * 18.0)
		draw_polyline(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0), p + Vector2(0, -6)]), Palette.a(Palette.RED, 0.5), 1.0)
		_txt(mono, p.x + 9, p.y - 6, "FALSE", 7, Palette.a(Palette.RED, 0.5))
	_txt(mono, 14.0, size.y - 54.0, "N-4 EW / 电子战", 8, Palette.a(Palette.RED, 0.8))
	_txt(mono, 14.0, size.y - 42.0, "NOISE FLOOR +18 dB", 7, Palette.a(Palette.RED, 0.4))
	draw_rect(Rect2(size.x * 0.5 - 80, 64, 160, 18), Palette.a(Palette.RED, 0.08))
	draw_rect(Rect2(size.x * 0.5 - 80, 64, 160, 18), Palette.a(Palette.RED, 0.45), false, 1.0)
	_txt(mono, size.x * 0.5 - 70, 68, "JAMMING / 干扰中", 8, Palette.RED)

func _draw_center() -> void:
	var p := size * 0.5
	draw_circle(p, 2.0, Palette.PH)
	draw_arc(p, 12.0, 0, TAU, 40, Palette.a(Palette.PH, 0.6), 1.0, true)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var b := deg_to_rad(a)
		var d := Vector2(cos(b), sin(b))
		draw_line(p + d * 8.0, p + d * 15.0, Palette.a(Palette.PH, 0.55), 1.0)
	_txt(cjk, p.x + 28.0, p.y - 30.0, "远地点", 11, Palette.PH)
	_txt(mono, p.x + 28.0, p.y - 17.0, "APSIS · FLAGSHIP", 7, Palette.a(Palette.PH, 0.55))

func _draw_chrome() -> void:
	_corners(Rect2(6, 6, size.x - 12, size.y - 12), 14.0, Palette.a(Palette.PH, 0.45))
	_txt(cjk, 24.0, 12.0, "压平态势" if ortho else "立体态势", 12, Palette.TXT)
	_txt(mono, 24.0, 30.0, "PLANAR CHART / CENTER APSIS" if ortho else "TACTICAL MAP / CENTER APSIS", 7, Palette.a(Palette.DIM, 0.8))

	
	_txt_r(mono, size.x - 14.0, size.y - 45.0, "GRID 50,000 km", 7, Palette.a(Palette.FAINT, 0.7))
	_txt_r(mono, size.x - 14.0, size.y - 31.0, "CENTER X+192,000 Y+0 Z+12,000", 7, Palette.a(Palette.FAINT, 0.65))

	# 比例尺
	var km := 100000.0
	var px := 0.0
	if ortho:
		px = km * _planar_scale
	else:
		px = km / dist * _focal
	px = clampf(px, 30.0, 180.0)
	var sy := size.y - 18.0
	draw_line(Vector2(14, sy), Vector2(14 + px, sy), Palette.a(Palette.TXT, 0.6), 1.0)
	draw_line(Vector2(14, sy - 4), Vector2(14, sy + 2), Palette.a(Palette.TXT, 0.6), 1.0)
	draw_line(Vector2(14 + px, sy - 4), Vector2(14 + px, sy + 2), Palette.a(Palette.TXT, 0.6), 1.0)
	_txt(mono, 14.0, sy - 13.0, "100,000 km", 7, Palette.a(Palette.DIM, 0.8))

	# 图例
	_txt(mono, 14.0, size.y - 38.0, "● FRIEND   ◆ HOSTILE   □ UNKNOWN   ◇ GHOST", 7, Palette.a(Palette.FAINT, 0.85))

func _draw_transition() -> void:
	if transition < 0.0:
		return
	if transition < 0.10:
		draw_rect(Rect2(0, 0, size.x, size.y), Palette.a(Palette.PH, 0.03 * (1.0 - transition / 0.10)))
	for i in range(_tile_pos.size()):
		if transition < _tile_delay[i]:
			draw_rect(Rect2(_tile_pos[i], Vector2(80, 80)), Palette.BG)

func _draw_planar_compass() -> void:
	var c := size - Vector2(92, 92)
	draw_arc(c, 26.0, 0, TAU, 40, Palette.a(Palette.PH, 0.30), 1.0, true)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * 26.0, c + d * 31.0, Palette.a(Palette.PH, 0.40), 1.0)
	_txt(mono, c.x - 3.0, c.y - 44.0, "N", 8, Palette.a(Palette.PH, 0.7))
	_txt(mono, c.x + 34.0, c.y - 5.0, "E", 8, Palette.a(Palette.PH, 0.7))
	_txt(mono, c.x - 41.0, c.y - 5.0, "W", 8, Palette.a(Palette.PH, 0.7))
	_txt(mono, c.x - 3.0, c.y + 36.0, "S", 8, Palette.a(Palette.PH, 0.7))
	_txt(mono, c.x - 30.0, c.y + 52.0, "PLANAR / 压平", 7, Palette.a(Palette.PH, 0.5))
# ── 工具 ────────────────────────────────────────────────

func _line3(a: Vector3, b: Vector3, c: Color, w := 1.0) -> void:
	var pa := _project(a)
	var pb := _project(b)
	if _ok(pa) and _ok(pb):
		draw_line(pa, pb, c, w, true)

func _poly3(pts: Array[Vector3], c: Color, w := 1.0, dashed := false) -> void:
	var run: Array[Vector2] = []
	for p in pts:
		var q := _project(p)
		if _ok(q):
			run.append(q)
		else:
			_flush(run, c, w, dashed)
			run.clear()
	_flush(run, c, w, dashed)

func _flush(run: Array[Vector2], c: Color, w: float, dashed: bool) -> void:
	if run.size() < 2:
		return
	if dashed:
		_dashed(run, c, w, 6.0)
	else:
		draw_polyline(PackedVector2Array(run), c, w, true)

func _dashed(pts: Array[Vector2], c: Color, w := 1.0, dash := 4.0) -> void:
	var on := true
	var acc := 0.0
	for i in range(1, pts.size()):
		if on:
			draw_line(pts[i - 1], pts[i], c, w, true)
		acc += pts[i - 1].distance_to(pts[i])
		if acc >= dash:
			acc = 0.0
			on = not on

func _corners(r: Rect2, l: float, c: Color) -> void:
	draw_line(r.position, r.position + Vector2(l, 0), c, 1.0)
	draw_line(r.position, r.position + Vector2(0, l), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), c, 1.0)
	draw_line(r.end, r.end - Vector2(l, 0), c, 1.0)
	draw_line(r.end, r.end - Vector2(0, l), c, 1.0)

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

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)

# ── 交互 ────────────────────────────────────────────────

func set_planar(on: bool) -> void:
	if ortho == on:
		return
	ortho = on
	transition = 0.0
	if on:
		yaw2d = 0.0
		planar_zoom = 1.0
	else:
		yaw3d = deg_to_rad(-80.0)
		pitch = deg_to_rad(24.0)

func rotate_map(dx: float, dy: float) -> void:
	auto_rotate = false
	if ortho:
		yaw2d -= dx * 0.006
	else:
		yaw3d -= dx * 0.006
		pitch = clampf(pitch + dy * 0.004, deg_to_rad(-8.0), deg_to_rad(78.0))

func zoom_map(f: float) -> void:
	if ortho:
		planar_zoom = clampf(planar_zoom / f, 0.70, 1.45)
		if planar_zoom > 1.30:
			dist = 520000.0
			set_planar(false)
	else:
		dist = clampf(dist * f, 35000.0, 1400000.0)

func flip_map() -> void:
	if ortho:
		yaw2d += PI
	else:
		yaw3d += PI
