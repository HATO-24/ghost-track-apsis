class_name TacticalPlot
extends Control

# V1.5 战术图：V1 的薄荷绿四区语言 + V2 的轨道相机与自动压平。
#
# 两种模式，用 80px 黑块硬切切换（0.44s）：
#   3D   —— 局部水平板（LVLH）。相机绕本舰 orbit：yaw / pitch / dist。
#           世界单位 = 米；+x 东，+y 北，+z 天顶。所有文字屏幕对齐，不跟 3D 转。
#   压平 —— 正交地月战略图（V2 map3d 的地月图重绘成薄荷绿），中心仍锁本舰。
#           dist > 640,000 进压平；压平里放大到 planar_zoom > 1.30 回 3D
#           （等效 dist = 520,000 < 580,000）。
#
# 基准 datum 决定"下"是谁：
#   EARTH —— 地球基准弧（+ 刻度、大气辉光、SUN 刻度）。
#   MOON  —— 月面基准弧（更小、冰蓝）。
#   L1    —— 站点基准十字 + 地月双体方向标记，不画地球弧。
#
# 基准弧不是实体星球，是仪表：只有 1px 弧、刻度、极薄辉光；转到板下（pitch < 0）
# 时翻面变成虚线。

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

# ── 相机 / 模式 ────────────────────────────────────────
const DIST_DEFAULT := 520000.0
const DIST_MIN := 300000.0
const DIST_MAX := 1400000.0
const PLANAR_IN := 640000.0
const PLANAR_OUT := 580000.0
const PITCH_MIN := -8.0
const PITCH_MAX := 78.0
const FOV_Y := 58.0
const MODE_CUT := 0.44
const TILE := 80.0
# 长焦系数：相机拉远、焦距同步放大 —— 近场尺度不变，透视畸变收敛，
# 让局部板保持"仪表"而不是鱼眼。
const CAM_FACTOR := 4.5

# 战略图常量（km）
const EARTH_R_KM := 6378.0
const MOON_R_KM := 1737.0
const EARTH_MOON_KM := 384400.0
const PLANAR_SPAN_KM := 700000.0

var state
var mono: Font
var cjk: Font

# 3D orbit 相机
var yaw3d := deg_to_rad(-16.0)
var pitch := deg_to_rad(26.0)
var dist := DIST_DEFAULT
# 压平战略图
var ortho := false
var yaw2d := 0.0
var planar_zoom := 1.0
# 自动缓慢自转；用户一动手就停
var auto_rotate := true
# 模式硬切：-1 = 不动画，0..0.44 = 进行中
var mode_fx_t := -1.0

var _t := 0.0
var _stars: Array[Vector3] = []
var _tile_pos: Array[Vector2] = []
var _cut_delay: Array[float] = []
var _mode_cut_delay: Array[float] = []

# 由 _update_camera() 推导
var _cam_pos := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _focal := 700.0
var _planar_scale := 0.0014

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()
	_make_stars()
	_make_tiles()
	auto_rotate = not (state != null and state.capture)

func _process(delta: float) -> void:
	_t += delta
	if state.sensor_fx_t >= 0.0:
		state.sensor_fx_t += delta
		if state.sensor_fx_t > 0.38:
			state.sensor_fx_t = -1.0
	if auto_rotate and not ortho and mode_fx_t < 0.0:
		yaw3d += 0.012 * delta
	if mode_fx_t >= 0.0:
		mode_fx_t += delta
		if mode_fx_t > MODE_CUT:
			mode_fx_t = -1.0
	_update_mode()
	queue_redraw()

func _update_mode() -> void:
	if mode_fx_t >= 0.0:
		return
	if not ortho and dist > PLANAR_IN:
		set_planar(true)
	elif ortho and dist < PLANAR_OUT:
		set_planar(false)

# ── 相机 ────────────────────────────────────────────────

func reset_camera() -> void:
	yaw3d = deg_to_rad(-16.0)
	pitch = deg_to_rad(26.0)
	dist = DIST_DEFAULT
	planar_zoom = 1.0
	ortho = false
	mode_fx_t = -1.0
	yaw2d = yaw3d
	auto_rotate = not (state != null and state.capture)

func force_planar(on: bool) -> void:
	ortho = on
	mode_fx_t = -1.0
	if on:
		yaw2d = yaw3d
		dist = PLANAR_IN
		planar_zoom = 1.0
	else:
		dist = DIST_DEFAULT
		yaw3d = yaw2d

func set_planar(on: bool) -> void:
	if ortho == on:
		return
	ortho = on
	mode_fx_t = 0.0
	if on:
		yaw2d = yaw3d
		planar_zoom = clampf(PLANAR_IN / maxf(dist, 1.0), 0.45, 1.45)
	else:
		yaw3d = yaw2d
		auto_rotate = false

func rotate_map(dx: float, dy: float) -> void:
	auto_rotate = false
	if ortho:
		yaw2d -= dx * 0.006
	else:
		yaw3d -= dx * 0.006
		pitch = clampf(pitch + dy * 0.004, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))

func zoom_map(f: float) -> void:
	if f <= 0.0:
		return
	auto_rotate = false
	if ortho:
		# 压平里滚轮改的是等效 dist：拉远继续压平，放大到 < 580,000 就回 3D
		var nd := dist * f
		if nd < PLANAR_OUT:
			dist = clampf(nd, DIST_MIN, DIST_MAX)
			set_planar(false)
		else:
			dist = clampf(nd, PLANAR_OUT, DIST_MAX)
			planar_zoom = clampf(PLANAR_IN / dist, 0.45, 1.45)
	else:
		dist = clampf(dist * f, DIST_MIN, DIST_MAX)

func flip_map() -> void:
	auto_rotate = false
	if ortho:
		yaw2d += PI
	else:
		yaw3d += PI

func _cam_dist() -> float:
	return dist * CAM_FACTOR

func _update_camera() -> void:
	_planar_scale = (size.x * 0.86) / PLANAR_SPAN_KM * planar_zoom
	var cd := _cam_dist()
	var cp := cos(pitch)
	var sp := sin(pitch)
	_cam_pos = Vector3(cp * sin(yaw3d), -cp * cos(yaw3d), sp) * cd
	var to_target := -_cam_pos
	if to_target.length() < 1.0:
		to_target = Vector3(0.0, -1.0, 0.0)
	_fwd = to_target.normalized()
	var r := _fwd.cross(Vector3.UP)
	if r.length() < 0.001:
		r = Vector3.RIGHT
	_right = r.normalized()
	_up = _right.cross(_fwd).normalized()
	_focal = (size.y * 0.5 / tan(deg_to_rad(FOV_Y * 0.5))) * CAM_FACTOR

func _o() -> Vector2:
	return size * 0.5

func _p3(p: Vector3) -> Vector2:
	var d := p - _cam_pos
	var z := d.dot(_fwd)
	if z < 500.0:
		return Vector2(-1.0e9, -1.0e9)
	return size * 0.5 + Vector2(d.dot(_right), -d.dot(_up)) / z * _focal

func _p2(km: Vector3) -> Vector2:
	var c := cos(yaw2d)
	var s := sin(yaw2d)
	var x := km.x * c + km.y * s
	var y := km.x * s - km.y * c
	return size * 0.5 + Vector2(x, y) * _planar_scale

func _ok(p: Vector2) -> bool:
	return p.x > -1.0e8 and p.x > -260.0 and p.x < size.x + 260.0 and p.y > -260.0 and p.y < size.y + 260.0

func _world(bearing: float, range_km: float, alt_km := 0.0) -> Vector3:
	var b := deg_to_rad(bearing)
	return Vector3(sin(b) * range_km * 1000.0, cos(b) * range_km * 1000.0, alt_km * 1000.0)

func _north_dir() -> Vector2:
	if ortho:
		return Vector2(sin(yaw2d), -cos(yaw2d))
	var pn := _p3(Vector3(0.0, 100000.0, 0.0))
	if not _ok(pn):
		return Vector2(0.0, -1.0)
	var d := pn - _o()
	if d.length() < 0.5:
		return Vector2(0.0, -1.0)
	return d.normalized()

func _heading_dir() -> Vector2:
	if ortho:
		var pd := _p2(Vector3(sin(deg_to_rad(75.0)) * 100.0, cos(deg_to_rad(75.0)) * 100.0, 0.0)) - _o()
		if pd.length() < 0.5:
			return Vector2(0.0, -1.0)
		return pd.normalized()
	var hp := _p3(_world(75.0, 100.0, 0.0))
	if not _ok(hp):
		return Vector2(0.0, -1.0)
	var d := hp - _o()
	if d.length() < 0.5:
		return Vector2(0.0, -1.0)
	return d.normalized()

# ── 画布 ────────────────────────────────────────────────

func _draw() -> void:
	_update_camera()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	_draw_dots()
	if ortho:
		_draw_planar()
	else:
		_draw_3d()
	_draw_sweep()
	_draw_sensor_cut()
	_draw_mode_cut()

func _draw_3d() -> void:
	_draw_stars()
	_draw_datum_backing()
	_draw_grid()
	_draw_orbits()
	_draw_burn_plan()
	_draw_contacts()
	_draw_own()
	_draw_sensor()
	_draw_chrome()

func _draw_planar() -> void:
	_draw_stars()
	_draw_planar_grid()
	_draw_planar_orbits()
	_draw_planar_rings()
	_draw_planar_bodies()
	_draw_planar_contacts()
	_draw_planar_own()
	_draw_planar_sensor()
	_draw_planar_inset()
	_draw_chrome()

# ── 背景 ────────────────────────────────────────────────

func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20871103
	for i in 170:
		_stars.append(Vector3(
			rng.randf_range(0.0, size.x),
			rng.randf_range(0.0, size.y),
			rng.randf_range(0.08, 0.42)
		))

func _draw_stars() -> void:
	for s in _stars:
		var a: float = s.z
		if not state.capture:
			a *= 0.72 + 0.28 * sin(_t * 1.6 + s.x * 0.11)
		if ortho:
			a *= 0.55
		draw_rect(Rect2(s.x, s.y, 1.0, 1.0), Palette.a(Palette.BLUE, a))

func _draw_dots() -> void:
	var step := 24.0
	var a := 0.014 + 0.006 * sin(_t * 0.7)
	var y := 0.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, y, 1, 1), Palette.a(Palette.PH, a))
			x += step
		y += step

# ── 基准（datum）背景 ──────────────────────────────────

func _draw_datum_backing() -> void:
	var dat := String(state.datum)
	if dat == "L1":
		_draw_station_backing()
		return
	var flipped := pitch < 0.0
	var col := Palette.PH_DIM
	var lbl := "EARTH REF · DATUM"
	var sub := "LOCAL HORIZONTAL / +400 km"
	var r_mul := 2.6
	var apex := 0.80
	if dat == "MOON":
		col = Palette.BLUE
		lbl = "MOON REF · DATUM"
		sub = "LUNAR LOCAL / +100 km"
		r_mul = 3.8
		apex = 0.88
	_draw_limb(col, lbl, sub, flipped, r_mul, apex)

# 仪表化的基准弧：不是实体地球/月球，只是一条 1px 地平弧 + 刻度 + 极薄辉光。
# 用圆的一段在屏幕空间画；从板下看（pitch < 0）时翻到上缘并变虚线。
func _draw_limb(col: Color, lbl: String, sub: String, flipped: bool, r_mul: float, apex_frac: float) -> void:
	var o := _o()
	var H := size.y
	var sy := -1.0 if flipped else 1.0
	var R := H * r_mul
	var apex_y := H * apex_frac if not flipped else H * (1.0 - apex_frac)
	var center := Vector2(o.x, apex_y + sy * R)
	var t0 := -0.34
	var t1 := 0.34
	# 4 层极薄大气辉光
	for k in range(4):
		var rr := R + 1.6 * float(k + 1)
		var gp: Array[Vector2] = []
		for i in range(0, 41):
			var t := t0 + (t1 - t0) * float(i) / 40.0
			gp.append(center + Vector2(sin(t) * rr, -cos(t) * rr * sy))
		_polyline(gp, Palette.a(col, 0.062 - float(k) * 0.013), 1.0)
	# 弧内侧填黑：基准面是空的，不画实体星球
	var base: Array[Vector2] = []
	for i in range(0, 41):
		var t := t0 + (t1 - t0) * float(i) / 40.0
		base.append(center + Vector2(sin(t) * R, -cos(t) * R * sy))
	var poly := PackedVector2Array(base)
	var far_y := H + 40.0 if not flipped else -40.0
	for q in base:
		if not flipped:
			far_y = maxf(far_y, q.y + 20.0)
		else:
			far_y = minf(far_y, q.y - 20.0)
	poly.append(Vector2(base[base.size() - 1].x, far_y))
	poly.append(Vector2(base[0].x, far_y))
	draw_colored_polygon(poly, Palette.BG)
	# 主弧
	if flipped:
		_dashed_polyline(base, Palette.a(col, 0.34), 1.0, 6.0)
	else:
		_polyline(base, Palette.a(col, 0.78), 1.0)
	# 刻度
	if not flipped:
		for i in range(0, 41, 2):
			var t := t0 + (t1 - t0) * float(i) / 40.0
			if absf(center.x + sin(t) * R - o.x) > size.x * 0.72:
				continue
			var d := Vector2(sin(t), -cos(t) * sy)
			draw_line(center + d * (R - 8.0), center + d * (R - 1.0), Palette.a(col, 0.55), 1.0)
	# SUN 刻度
	var st := -0.13
	var sd := Vector2(sin(st), -cos(st) * sy)
	var s0 := center + sd * (R - 9.0)
	var s1 := center + sd * (R + 2.0)
	draw_line(s0, s1, Palette.a(Palette.AMBER, 0.6), 1.0)
	_txt(mono, s1.x + 8.0, s1.y - 12.0, "SUN 312°", 7, Palette.a(Palette.AMBER, 0.55))
	# 标签
	_txt_r(mono, size.x - 24.0, size.y - 80.0, "VIEW 3D · DIST %s km" % _fmt_km(dist / 1000.0), 7, Palette.a(Palette.PH_DIM, 0.8))
	_txt_r(mono, size.x - 24.0, size.y - 68.0, sub, 8, Palette.a(Palette.PH_DIM, 0.75))
	_txt_r(mono, size.x - 24.0, size.y - 56.0, lbl, 7, Palette.a(Palette.FAINT, 0.8))
	if flipped:
		_txt(mono, 24.0, 150.0, "DATUM BELOW · 基准翻面 / FLIPPED", 8, Palette.a(Palette.AMBER, 0.65))

func _draw_station_backing() -> void:
	# L1 站点基准：不画地球弧；站点基准十字 + 地月双体方向。
	var o := _o()
	var a_l := _p3(_world(270.0, 430.0, 0.0))
	var a_r := _p3(_world(90.0, 430.0, 0.0))
	if _ok(a_l) and _ok(a_r):
		_dashed_line2(a_l, a_r, Palette.a(Palette.PH_FAINT, 0.22), 1.0, 7.0)
	_dir_marker(270.0, 300.0, "EARTH", "地心 · 326,000 km", Palette.PH_DIM)
	_dir_marker(90.0, 300.0, "MOON", "月心 · 58,400 km", Palette.BLUE)
	_txt(cjk, 24.0, 124.0, "站点基准 / STATION FRAME", 8, Palette.a(Palette.PH, 0.65))
	_txt(mono, 24.0, 136.0, "DATUM L1 · NO EARTH LIMB", 7, Palette.a(Palette.FAINT, 0.9))
	# 站点十字（画在本舰标记下面一层）
	draw_line(o - Vector2(34.0, 0.0), o + Vector2(34.0, 0.0), Palette.a(Palette.PH, 0.30), 1.0)
	draw_line(o - Vector2(0.0, 34.0), o + Vector2(0.0, 34.0), Palette.a(Palette.PH, 0.30), 1.0)
	_txt_r(mono, size.x - 24.0, size.y - 80.0, "VIEW 3D · DIST %s km" % _fmt_km(dist / 1000.0), 7, Palette.a(Palette.PH_DIM, 0.8))
	_txt_r(mono, size.x - 24.0, size.y - 68.0, "STATION FRAME / 环一 · 斛", 8, Palette.a(Palette.PH_DIM, 0.75))
	_txt_r(mono, size.x - 24.0, size.y - 56.0, "L1 REF · DATUM", 7, Palette.a(Palette.FAINT, 0.8))

func _dir_marker(bearing: float, range_km: float, en: String, zh: String, col: Color) -> void:
	var p := _p3(_world(bearing, range_km, 0.0))
	if not _ok(p):
		return
	var o := _o()
	_dashed_line2(o, p, Palette.a(col, 0.20), 1.0, 5.0)
	var dir := (p - o)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	draw_line(p - dir * 16.0, p, Palette.a(col, 0.72), 1.0)
	draw_colored_polygon(PackedVector2Array([
		p, p - dir * 9.0 + perp * 3.5, p - dir * 9.0 - perp * 3.5
	]), Palette.a(col, 0.85))
	draw_arc(p, 11.0, 0, TAU, 24, Palette.a(col, 0.40), 1.0, true)
	_txt(mono, p.x + 12.0, p.y - 16.0, en, 8, Palette.a(col, 0.9))
	_txt(cjk, p.x + 12.0, p.y - 4.0, zh, 7, Palette.a(col, 0.55))

# ── 3D 局部板 ──────────────────────────────────────────

func _draw_grid() -> void:
	var o := _o()
	for r in [50.0, 100.0, 200.0, 400.0]:
		var pts: Array[Vector3] = []
		for i in range(0, 361, 3):
			pts.append(_world(float(i), r, 0.0))
		_poly3(pts, Palette.a(Palette.GRID, 0.80 if r < 400.0 else 0.55), 1.0)
	for b in range(0, 360, 30):
		var p := _p3(_world(float(b), 425.0, 0.0))
		_seg2(o, p, Palette.a(Palette.GRID, 0.34), 1.0)
		if int(b) % 90 == 0 and _ok(p):
			_txt(mono, p.x - 7.0, p.y + 2.0, "%03d" % b, 7, Palette.a(Palette.FAINT, 0.85))
	for r in [100.0, 200.0, 400.0]:
		var lp := _p3(_world(322.0, r, 0.0))
		if _ok(lp):
			_txt_r(mono, lp.x - 3.0, lp.y - 9.0, "%d" % int(r), 7, Palette.a(Palette.DIM, 0.55))
	# 抬高一层：让"高度"可见
	var hi: Array[Vector3] = []
	for i in range(0, 361, 3):
		hi.append(_world(float(i), 200.0, 40.0))
	_poly3(hi, Palette.a(Palette.PH_FAINT, 0.42), 1.0, true)
	for b in [0.0, 90.0, 180.0, 270.0]:
		_seg3(_world(b, 200.0, 0.0), _world(b, 200.0, 40.0), Palette.a(Palette.PH_FAINT, 0.30), 1.0)
	var al := _p3(_world(300.0, 200.0, 40.0))
	if _ok(al):
		_txt(mono, al.x + 3.0, al.y - 10.0, "ALT +40", 7, Palette.a(Palette.PH_FAINT, 0.9))

func _draw_orbits() -> void:
	# 本舰轨道（滑行段）：局部水平面里的一条浅弧
	var pts: Array[Vector3] = []
	for i in range(0, 100):
		var x := -440.0 + 880.0 * float(i) / 99.0
		pts.append(Vector3(x, 0.00025 * x * x, 0.0) * 1000.0)
	_poly3(pts, Palette.a(Palette.PH_DIM, 0.30), 1.2)
	var lp := _p3(Vector3(120.0, 0.00025 * 120.0 * 120.0, 0.0) * 1000.0)
	if _ok(lp):
		_txt(cjk, lp.x, lp.y - 16.0, "轨道 400 km · 顺行", 8, Palette.a(Palette.DIM, 0.75))
	# 敌方轨道：另一个平面，斜穿画面
	var epts: Array[Vector3] = []
	for i in range(0, 90):
		var s := -460.0 + 920.0 * float(i) / 89.0
		epts.append(Vector3(s, 300.0 - 0.36 * s, -0.10 * s + 0.00012 * s * s) * 1000.0)
	_poly3(epts, Palette.a(Palette.RED, 0.20), 1.0, true)
	var ep := _p3(Vector3(360.0, 300.0 - 0.36 * 360.0, -0.10 * 360.0 + 0.00012 * 360.0 * 360.0) * 1000.0)
	if _ok(ep):
		_txt(cjk, ep.x, ep.y - 14.0, "敌方轨道 · i 51.6°", 8, Palette.a(Palette.RED, 0.55))

func _draw_burn_plan() -> void:
	var o := _o()
	var p1 := _p3(_world(340.0, 70.0, 60.0))
	if _ok(p1):
		draw_line(o, p1, Palette.a(Palette.PH, 0.50), 1.3, true)
		var dir := (p1 - o)
		if dir.length() > 0.001:
			dir = dir.normalized()
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([
				p1, p1 - dir * 9.0 + perp * 4.0, p1 - dir * 9.0 - perp * 4.0
			]), Palette.a(Palette.PH, 0.75))
		draw_circle(o, 3.0, Palette.a(Palette.PH, 0.9))
		draw_arc(o, 16.0, 0, TAU, 32, Palette.a(Palette.PH, 0.22), 1.0, true)
		_txt(cjk, p1.x - 128.0, p1.y - 14.0, "点火 T+06.2s", 9, Palette.PH)
		_txt(mono, p1.x - 128.0, p1.y - 1.0, "Δv 84 m/s · BRG 340", 8, Palette.a(Palette.PH_DIM, 1.0))
		_txt(mono, p1.x - 128.0, p1.y + 12.0, "PLANE CHANGE +60 km", 7, Palette.a(Palette.PH_FAINT, 1.0))
	# 目标节点
	var wp := _p3(_world(18.0, 392.0, 34.0))
	if _ok(wp):
		draw_polyline(PackedVector2Array([
			wp + Vector2(0, -6), wp + Vector2(6, 0), wp + Vector2(0, 6),
			wp + Vector2(-6, 0), wp + Vector2(0, -6)
		]), Palette.a(Palette.PH_DIM, 0.7), 1.0)
		_txt(mono, wp.x + 10.0, wp.y - 6.0, "NODE B-2", 7, Palette.a(Palette.PH_DIM, 0.9))

# ── 接触 ────────────────────────────────────────────────

func _contact_pos3(t: Dictionary) -> Vector2:
	return _p3(_world(float(t.bearing), float(t.range), float(t.alt)))

func _draw_contacts() -> void:
	for t in state.tracks:
		if t.get("own", false):
			continue
		if t.get("bearing_only", false):
			_draw_bearing_only(t)
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		var col := _side_color(t)
		var base := _p3(_world(float(t.bearing), float(t.range), 0.0))
		if absf(float(t.alt)) > 3.0 and _ok(base):
			draw_dashed_line(base, p, Palette.a(col, 0.30), 1.0, 2.0)
			draw_circle(base, 1.4, Palette.a(col, 0.35))
		if int(t.level) <= 2:
			_draw_error_ellipse(p, t, col)
		_draw_symbol(p, t, col)
		_draw_track_label(t, p, col)

func _draw_bearing_only(t: Dictionary) -> void:
	var o := _o()
	var b := deg_to_rad(float(t.bearing))
	var half := deg_to_rad(1.7)
	var far := 460.0
	var p1 := _p3(_world(rad_to_deg(b - half), far, 0.0))
	var p2 := _p3(_world(rad_to_deg(b + half), far, 0.0))
	if _ok(p1) and _ok(p2):
		draw_colored_polygon(PackedVector2Array([o, p1, p2]), Palette.a(Palette.AMBER, 0.035))
		draw_dashed_line(o, p1, Palette.a(Palette.AMBER, 0.30), 1.0, 3.0)
		draw_dashed_line(o, p2, Palette.a(Palette.AMBER, 0.30), 1.0, 3.0)
	var arc: Array[Vector3] = []
	for i in range(0, 21):
		var bb := rad_to_deg(b - half) + rad_to_deg(2.0 * half) * float(i) / 20.0
		arc.append(_world(bb, 340.0, 0.0))
	_poly3(arc, Palette.a(Palette.AMBER, 0.38), 1.0, true)
	var mid := _p3(_world(float(t.bearing), 340.0, 0.0))
	if _ok(mid):
		_txt(cjk, mid.x - 112.0, mid.y - 34.0, "方位 %03d°" % int(t.bearing), 9, Palette.AMBER)
		_txt(cjk, mid.x - 112.0, mid.y - 21.0, "距离未知 · 陈旧 %ds" % int(t.age), 8, Palette.a(Palette.AMBER, 0.65))
		_txt(mono, mid.x - 112.0, mid.y - 8.0, "BEARING ONLY / MEMORY", 7, Palette.a(Palette.AMBER, 0.4))

func _draw_error_ellipse(p: Vector2, t: Dictionary, col: Color) -> void:
	var big := int(t.level) <= 1
	var rx := 34.0 if big else 17.0
	var ry := 15.0 if big else 8.0
	var b := deg_to_rad(float(t.bearing))
	var c3 := _world(float(t.bearing), float(t.range), float(t.alt))
	var q := _p3(c3 + Vector3(sin(b), cos(b), 0.0) * 20000.0)
	var dir := q - p
	if dir.length() < 0.001:
		dir = Vector2(0.0, -1.0)
	var rot := dir.normalized().angle()
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
			var d := PackedVector2Array([
				p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7),
				p + Vector2(-7, 0), p + Vector2(0, -7)
			])
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)
			]), Palette.a(col, 0.12))
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
	var off: Vector2 = t.get("off", Vector2(16, 12))
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
	var p := _o()
	var dat := String(state.datum)
	var own_name := String(state.unit.get("name", "哈马丹"))
	draw_circle(p, 2.6, Palette.PH)
	draw_arc(p, 11.0, 0, TAU, 36, Palette.a(Palette.PH, 0.65), 1.0, true)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var b := deg_to_rad(a)
		var d := Vector2(sin(b), -cos(b))
		draw_line(p + d * 7.0, p + d * 13.0, Palette.a(Palette.PH, 0.55), 1.0)
	var hq := _p3(_world(75.0, 40.0, 0.0))
	if _ok(hq):
		var hd := (hq - p)
		if hd.length() > 0.001:
			draw_line(p, p + hd.normalized() * 24.0, Palette.a(Palette.PH, 0.40), 1.0)
	if dat == "L1":
		# 站点基准：双十字 + 方括号
		draw_line(p - Vector2(26.0, 0.0), p + Vector2(26.0, 0.0), Palette.a(Palette.PH, 0.85), 1.0)
		draw_line(p - Vector2(0.0, 26.0), p + Vector2(0.0, 26.0), Palette.a(Palette.PH, 0.85), 1.0)
		draw_arc(p, 16.0, 0, TAU, 32, Palette.a(Palette.PH, 0.35), 1.0, true)
		for q in [Vector2(-22, -22), Vector2(22, -22), Vector2(-22, 22), Vector2(22, 22)]:
			draw_rect(Rect2(p + q - Vector2(3, 3), Vector2(6, 6)), Palette.a(Palette.PH, 0.7), false, 1.0)
	_txt(cjk, p.x + 16.0, p.y + 8.0, own_name, 11, Palette.PH)
	if dat == "L1":
		_txt(mono, p.x + 16.0, p.y + 21.0, "OWN · STATION 斛 / L1", 7, Palette.a(Palette.PH_DIM, 0.9))
	else:
		_txt(mono, p.x + 16.0, p.y + 21.0, "OWN · 400 km", 7, Palette.a(Palette.PH_DIM, 0.9))

# ── 传感器图层（3D） ───────────────────────────────────

func _draw_sensor() -> void:
	var sid := int(state.sensor)
	if sid == 0:
		return
	match sid:
		1:
			_sensor_ir()
		2:
			_sensor_radar()
		3:
			_sensor_optical()
		4:
			_sensor_iff()
		5:
			_sensor_elint()

func _layer_label(txt: String, col: Color, sub := "") -> void:
	_txt(cjk, 24.0, 96.0, txt, 8, col)
	if sub != "":
		_txt(mono, 24.0, 108.0, sub, 7, Palette.a(col, 0.40))

func _sensor_ir() -> void:
	var o := _o()
	for t in state.tracks:
		if t.get("own", false):
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(t.bearing))
		for k in range(2):
			draw_arc(p, 9.0 + float(k) * 7.0 + pulse * 3.0, 0, TAU, 28, Palette.a(Palette.AMBER, 0.18 - float(k) * 0.05), 1.0, true)
		if t.side == "hostile":
			var b := _p3(_world(float(t.bearing), 520.0, 0.0))
			if _ok(b):
				draw_dashed_line(o, b, Palette.a(Palette.AMBER, 0.18), 1.0, 4.0)
	_layer_label("IRST 明视 IR-9 / 被动红外", Palette.a(Palette.AMBER, 0.8), "NO RANGING · BEARING ONLY")

func _sensor_radar() -> void:
	var o := _o()
	var sweep := fmod(_t * 0.9, TAU)
	var r := 420.0
	var poly: Array[Vector2] = [o]
	var fan_ok := true
	for i in range(0, 25):
		var a := sweep - 0.55 + 1.10 * float(i) / 24.0
		var q := _p3(_world(rad_to_deg(a), r, 0.0))
		if not _ok(q):
			fan_ok = false
			break
		poly.append(q)
	if fan_ok and poly.size() > 3:
		draw_colored_polygon(PackedVector2Array(poly), Palette.a(Palette.PH, 0.09))
	var tip := _p3(_world(rad_to_deg(sweep), r, 0.0))
	if _ok(tip):
		draw_line(o, tip, Palette.a(Palette.PH, 0.85), 1.4)
	for rr in [100.0, 200.0, 400.0]:
		var arc: Array[Vector3] = []
		for i in range(0, 25):
			var a := sweep - 0.55 + 1.10 * float(i) / 24.0
			arc.append(_world(rad_to_deg(a), rr, 0.0))
		_poly3(arc, Palette.a(Palette.PH, 0.38), 1.0)
	_layer_label("远望 R-9 SWEEP / 主动雷达", Palette.a(Palette.PH, 0.8), "EMIT · BEARING + RANGE")

func _sensor_optical() -> void:
	# 光学凝视：取当前最值得盯的接触（优先敌对），画屏幕对齐的取景框
	var target: Dictionary = {}
	for t in state.tracks:
		if t.get("own", false):
			continue
		if t.side == "hostile":
			target = t
			break
		if target.is_empty():
			target = t
	if target.is_empty():
		return
	var p := _contact_pos3(target)
	if not _ok(p):
		return
	var r := Rect2(p - Vector2(120.0, 78.0), Vector2(240.0, 156.0))
	draw_rect(r, Palette.a(Palette.BLUE, 0.025))
	draw_rect(r, Palette.a(Palette.BLUE, 0.55), false, 1.0)
	var cp := r.get_center()
	draw_line(cp - Vector2(140, 0), cp + Vector2(140, 0), Palette.a(Palette.BLUE, 0.18), 1.0)
	draw_line(cp - Vector2(0, 100), cp + Vector2(0, 100), Palette.a(Palette.BLUE, 0.18), 1.0)
	# 取景框四角
	for q in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if q.x < cp.x else -1.0
		var sy := 1.0 if q.y < cp.y else -1.0
		draw_line(q, q + Vector2(10.0 * sx, 0), Palette.a(Palette.BLUE, 0.8), 1.0)
		draw_line(q, q + Vector2(0, 10.0 * sy), Palette.a(Palette.BLUE, 0.8), 1.0)
	_txt(mono, r.position.x + 8.0, r.position.y + 5.0, "MS-IR9 / STARE 12.4s", 7, Palette.a(Palette.BLUE, 0.8))
	_txt_r(mono, r.end.x - 8.0, r.position.y + 5.0, "MAG 8×", 7, Palette.a(Palette.BLUE, 0.55))
	_txt(cjk, r.position.x + 8.0, r.end.y - 12.0, "锁定 " + String(target.id), 7, Palette.a(Palette.BLUE, 0.65))
	_layer_label("MS-IR9 光学凝视", Palette.a(Palette.BLUE, 0.8), "STARE 12.4s · 受光照/阴影")

func _sensor_iff() -> void:
	var o := _o()
	for k in range(3):
		var rr := fmod(_t * 70.0 + float(k) * 130.0, 380.0)
		var circle: Array[Vector3] = []
		for i in range(0, 49):
			var a := TAU * float(i) / 48.0
			circle.append(Vector3(cos(a) * rr * 1000.0, sin(a) * rr * 1000.0, 0.0))
		_poly3(circle, Palette.a(Palette.PH, 0.10 * (1.0 - rr / 380.0)), 1.0)
	for t in state.tracks:
		if t.get("own", false):
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		var tag := "F" if t.side == "friend" else ("H" if t.side == "hostile" else "?")
		draw_rect(Rect2(p.x + 7, p.y - 18, 11, 10), Palette.a(Palette.PH, 0.10))
		_txt(mono, p.x + 9, p.y - 17, tag, 7, Palette.a(Palette.PH, 0.85))
	_layer_label("MK-12 IFF / 敌我识别", Palette.a(Palette.PH, 0.75))

func _sensor_elint() -> void:
	var o := _o()
	for t in state.tracks:
		if t.get("own", false):
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		draw_dashed_line(o, p, Palette.a(Palette.AMBER, 0.16), 1.0, 5.0)
		if t.side == "hostile":
			_txt(mono, p.x + 10.0, p.y + 18.0, "EMIT", 7, Palette.a(Palette.AMBER, 0.6))
	_layer_label("ELINT / 通信截听", Palette.a(Palette.AMBER, 0.8), "PASSIVE · SIGNAL FINGERPRINT")

# ── 压平战略图（V2 地月图 · 薄荷绿重绘） ───────────────

func _earth_km() -> Vector2:
	match String(state.datum):
		"L1":
			return Vector2(-326000.0, 0.0)
		_:
			return Vector2(-192000.0, 0.0)

func _moon_km() -> Vector2:
	match String(state.datum):
		"L1":
			return Vector2(58400.0, 0.0)
		_:
			return Vector2(192400.0, 0.0)

func _draw_planar_grid() -> void:
	var lim := 600000.0
	var step := 50000.0
	var x := -lim
	while x <= lim:
		var c := Palette.a(Palette.GRID, 0.30 if absf(x) < 1.0 else 0.14)
		draw_line(_p2(Vector3(x, -lim, 0.0)), _p2(Vector3(x, lim, 0.0)), c, 1.0)
		x += step
	var y := -lim
	while y <= lim:
		var c2 := Palette.a(Palette.GRID, 0.30 if absf(y) < 1.0 else 0.14)
		draw_line(_p2(Vector3(-lim, y, 0.0)), _p2(Vector3(lim, y, 0.0)), c2, 1.0)
		y += step
	var gy := 160.0 if String(state.datum) == "L1" else 124.0
	_txt(mono, 16.0, gy, "ECLIPTIC / 黄道面 · GRID 50,000 km", 7, Palette.a(Palette.FAINT, 0.8))
	_txt(mono, size.x * 0.5 - 52.0, 88.0, "CISLUNAR / 地月系", 8, Palette.a(Palette.PH, 0.42))
	# 太阳方向：只做刻度，不画光照
	var sx := 16.0
	var sy := size.y - 74.0
	draw_circle(Vector2(sx + 5.0, sy + 3.0), 2.2, Palette.a(Palette.AMBER, 0.55))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(sx + 5.0, sy + 3.0) + Vector2(cos(a), sin(a)) * 4.0, Vector2(sx + 5.0, sy + 3.0) + Vector2(cos(a), sin(a)) * 6.5, Palette.a(Palette.AMBER, 0.35), 1.0)
	_txt(mono, sx + 16.0, sy, "SOL 312° · 光照", 7, Palette.a(Palette.AMBER, 0.50))

func _draw_planar_orbits() -> void:
	var earth := _earth_km()
	var moon := _moon_km()
	# 月球轨道
	var pts: Array[Vector3] = []
	for i in range(0, 181):
		var a := TAU * float(i) / 180.0
		pts.append(Vector3(earth.x + cos(a) * EARTH_MOON_KM, earth.y + sin(a) * EARTH_MOON_KM, 0.0))
	_poly2(pts, Palette.a(Palette.DIM, 0.18), 1.0, true)
	# 地月转移弧
	_poly2(_quad_bezier(earth, Vector2(-96000.0, 62000.0), Vector2.ZERO), Palette.a(Palette.PH, 0.34), 1.2)
	_poly2(_quad_bezier(Vector2.ZERO, Vector2(92000.0, -44000.0), moon), Palette.a(Palette.PH, 0.34), 1.2)
	var lp := _p2(Vector3((earth.x + moon.x) * 0.5, 90000.0, 0.0))
	_txt(mono, lp.x + 6.0, lp.y, "TRANSFER ARC", 7, Palette.a(Palette.PH, 0.30))
	# 月球轨道标签：取一个落在画面内、且不压住中心区域的轨道点
	var labelled := false
	var oo := _o()
	for i in range(0, 181, 2):
		var a := TAU * float(i) / 180.0
		var q := _p2(Vector3(earth.x + cos(a) * EARTH_MOON_KM, earth.y + sin(a) * EARTH_MOON_KM, 0.0))
		if not labelled and q.x > 60.0 and q.x < size.x - 380.0 and q.y > 120.0 and q.y < size.y - 130.0 and q.distance_to(oo) > 130.0:
			_txt(mono, q.x + 4.0, q.y - 4.0, "MOON ORBIT · 384,400 km", 7, Palette.a(Palette.DIM, 0.55))
			labelled = true

func _draw_planar_rings() -> void:
	for r in [25000.0, 50000.0, 100000.0, 200000.0]:
		var pts: Array[Vector3] = []
		for i in range(0, 97):
			var a := TAU * float(i) / 96.0
			pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
		_poly2(pts, Palette.a(Palette.PH, 0.16), 1.0)
		var lp := _p2(Vector3(cos(deg_to_rad(45.0)) * r, sin(deg_to_rad(45.0)) * r, 0.0))
		if lp.x < size.x - 40.0 and lp.y > 60.0 and lp.y < size.y - 40.0:
			_txt(mono, lp.x + 3.0, lp.y - 9.0, "%dk" % int(r / 1000.0), 7, Palette.a(Palette.PH, 0.35))

func _draw_planar_bodies() -> void:
	var earth := _earth_km()
	var moon := _moon_km()
	var dat := String(state.datum)
	# 地月双体轴线：L1 基准时把两个方向都画出来（不画地球弧）
	var e2 := _p2(Vector3(earth.x, earth.y, 0.0))
	var m2 := _p2(Vector3(moon.x, moon.y, 0.0))
	_dashed_line2(e2, m2, Palette.a(Palette.PH_FAINT, 0.26), 1.0, 8.0)
	var span := moon.x - earth.x
	if absf(span) > 1.0:
		var f_flag := (0.0 - earth.x) / span
		_axis_tick(e2, m2, "%s km" % _fmt_km(-earth.x), f_flag * 0.5)
		_axis_tick(e2, m2, "%s km" % _fmt_km(moon.x), (f_flag + 1.0) * 0.5)
	_body_planar(earth, EARTH_R_KM, "EARTH / 地球", Palette.PH, dat == "EARTH", "FLAGSHIP · %s km · R 6,378" % _fmt_km(earth.length()))
	_body_planar(moon, MOON_R_KM, "MOON / 月球", Palette.DIM, dat == "MOON", "FLAGSHIP · %s km · R 1,737" % _fmt_km(moon.length()))
	if dat == "L1":
		_txt(mono, 24.0, 124.0, "L1 DATUM · EARTH-MOON TWO-BODY", 8, Palette.a(Palette.PH, 0.65))
		_txt(mono, 24.0, 136.0, "STATION 环一 · 斛 / NO BODY LIMB", 7, Palette.a(Palette.FAINT, 0.9))
		# L1 拉格朗日点标记：在站点上方标一个菱形
		var o := _o()
		var lp := o + Vector2(0.0, -88.0)
		draw_polyline(PackedVector2Array([
			lp + Vector2(0, -5), lp + Vector2(5, 0), lp + Vector2(0, 5),
			lp + Vector2(-5, 0), lp + Vector2(0, -5)
		]), Palette.a(Palette.PH, 0.55), 1.0)
		_txt(mono, lp.x + 10.0, lp.y - 4.0, "L1 · 环一 · 斛", 8, Palette.a(Palette.PH, 0.75))
		_txt(mono, lp.x + 10.0, lp.y + 8.0, "STATION FRAME / 地月双体", 7, Palette.a(Palette.FAINT, 0.8))

func _axis_tick(a: Vector2, b: Vector2, label: String, frac: float) -> void:
	var p := a.lerp(b, frac)
	var dir := (b - a)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	draw_line(p + perp * 4.0, p - perp * 4.0, Palette.a(Palette.PH_FAINT, 0.55), 1.0)
	_txt(mono, p.x + perp.x * 8.0 + 2.0, p.y + perp.y * 8.0 - 4.0, label, 7, Palette.a(Palette.PH_DIM, 0.60))

func _body_planar(pos_km: Vector2, radius_km: float, label: String, col: Color, is_ref: bool, sub: String) -> void:
	var p := _p2(Vector3(pos_km.x, pos_km.y, 0.0))
	var r := maxf(radius_km * _planar_scale, 12.0)
	var near := p.distance_to(_o()) < 170.0
	draw_circle(p, r, Palette.BG)
	if is_ref:
		for k in range(2):
			draw_arc(p, r + 10.0 + float(k) * 6.0, 0, TAU, 64, Palette.a(Palette.PH, 0.22 - float(k) * 0.08), 1.0, true)
	for i in range(4):
		draw_arc(p, r + float(i) * 2.0, 0, TAU, 64, Palette.a(col, 0.10 - float(i) * 0.02), 1.0, true)
	draw_arc(p, r, 0, TAU, 64, Palette.a(col, 0.72), 1.0, true)
	# 球面网格：一条横椭圆 + 两条竖弧
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
	# 标签：靠近旗舰（L1 时的月球）时往外让，避免压住接触集群
	var lx := p.x + r + 8.0
	var lw := mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var ly := p.y - 6.0
	if near:
		lx = p.x + r + 16.0
		ly = p.y - 40.0
		if lx + lw > size.x - 12.0:
			lx = p.x - r - 16.0 - lw
	else:
		if lx + lw > size.x - 12.0:
			lx = p.x - r - 8.0 - lw
	if is_ref:
		_txt(mono, lx, ly - 12.0, "DATUM REF", 7, Palette.a(Palette.PH, 0.75))
	_txt(mono, lx, ly, label, 9, Palette.a(col, 0.90 if is_ref else 0.75))
	_txt(mono, lx, ly + 11.0, sub, 7, Palette.a(col, 0.45))

func _draw_planar_contacts() -> void:
	var o := _o()
	var cluster: Array[Dictionary] = []
	var friends := 0
	var total := 0
	for t in state.tracks:
		if t.get("own", false):
			continue
		total += 1
		var b := deg_to_rad(float(t.bearing))
		var rng_km := float(t.range)
		var pos := _p2(Vector3(sin(b) * rng_km, cos(b) * rng_km, 0.0))
		var col := _side_color(t)
		if t.get("bearing_only", false):
			var half := deg_to_rad(2.2)
			var d1 := Vector2(sin(b - half), -cos(b - half))
			var d2 := Vector2(sin(b + half), -cos(b + half))
			draw_colored_polygon(PackedVector2Array([o, o + d1 * 90.0, o + d2 * 90.0]), Palette.a(Palette.AMBER, 0.05))
			draw_dashed_line(o, o + Vector2(sin(b), -cos(b)) * 90.0, Palette.a(Palette.AMBER, 0.35), 1.0, 3.0)
			cluster.append({"t": t, "col": col})
			continue
		if pos.distance_to(o) < 26.0:
			if t.side == "friend":
				friends += 1
			else:
				cluster.append({"t": t, "col": col})
		else:
			_draw_symbol(pos, t, col)
			_draw_track_label(t, pos, col)
	# 战略尺度上近场接触 < 1px：用编队框 + 引线拉出来
	draw_rect(Rect2(o - Vector2(22, 22), Vector2(44, 44)), Palette.a(Palette.PH, 0.30), false, 1.0)
	_txt(mono, o.x - 150.0, o.y + 58.0, "LOCAL TRACKS ×%d · 编队 ×%d" % [total, friends], 7, Palette.a(Palette.PH, 0.70))
	if cluster.size() > 0:
		var fan := [-158.0, -110.0, 165.0, -134.0, 148.0, -178.0]
		for i in range(cluster.size()):
			var it: Dictionary = cluster[i]
			var tt: Dictionary = it["t"]
			var c: Color = it["col"]
			var ang := deg_to_rad(float(fan[i % fan.size()]))
			var dir := Vector2(cos(ang), sin(ang))
			var q := o + dir * (44.0 + float(i) * 30.0)
			draw_line(o + dir * 30.0, q, Palette.a(c, 0.35), 1.0)
			_draw_symbol(q, tt, c)
			var idf := cjk if Fonts.has_cjk(tt.id) else mono
			if cos(ang) < -0.2:
				_txt_r(idf, q.x - 8.0, q.y + 2.0, tt.id, 8, Palette.a(c, 0.9))
			else:
				_txt(idf, q.x + 8.0, q.y + 2.0, tt.id, 8, Palette.a(c, 0.9))

func _draw_planar_own() -> void:
	var o := _o()
	var dat := String(state.datum)
	var own_name := String(state.unit.get("name", "哈马丹"))
	if dat == "L1":
		draw_line(Vector2(o.x - 46.0, o.y), Vector2(o.x + 46.0, o.y), Palette.a(Palette.PH, 0.55), 1.0)
		draw_line(Vector2(o.x, o.y - 46.0), Vector2(o.x, o.y + 46.0), Palette.a(Palette.PH, 0.55), 1.0)
		draw_arc(o, 20.0, 0, TAU, 40, Palette.a(Palette.PH, 0.35), 1.0, true)
	draw_circle(o, 2.0, Palette.PH)
	draw_arc(o, 12.0, 0, TAU, 40, Palette.a(Palette.PH, 0.6), 1.0, true)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var bb := deg_to_rad(a)
		var d := Vector2(cos(bb), sin(bb))
		draw_line(o + d * 8.0, o + d * 15.0, Palette.a(Palette.PH, 0.55), 1.0)
	_txt(cjk, o.x + 20.0, o.y + 66.0, own_name, 11, Palette.PH)
	_txt(mono, o.x + 20.0, o.y + 79.0, "OWN · FLAGSHIP · CENTER LOCK", 7, Palette.a(Palette.PH, 0.55))

func _draw_planar_sensor() -> void:
	var sid := int(state.sensor)
	if sid == 0:
		return
	var o := _o()
	match sid:
		1:
			for t in state.tracks:
				if t.get("own", false) or t.get("bearing_only", false):
					continue
				var pos := _p2(Vector3(sin(deg_to_rad(float(t.bearing))) * float(t.range), cos(deg_to_rad(float(t.bearing))) * float(t.range), 0.0))
				var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(t.bearing))
				for k in range(2):
					draw_arc(pos, 10.0 + float(k) * 8.0 + pulse * 3.0, 0, TAU, 32, Palette.a(Palette.AMBER, 0.18 - float(k) * 0.05), 1.0, true)
			_layer_label("IRST 明视 IR-9 / 被动红外", Palette.a(Palette.AMBER, 0.8), "NO RANGING · BEARING ONLY")
		2:
			var sweep := fmod(_t * 0.9, TAU)
			var poly: Array[Vector2] = [o]
			for i in range(0, 25):
				var a := sweep - 0.55 + 1.10 * float(i) / 24.0
				poly.append(o + Vector2(sin(a), -cos(a)) * 120.0)
			draw_colored_polygon(PackedVector2Array(poly), Palette.a(Palette.PH, 0.09))
			draw_line(o, o + Vector2(sin(sweep), -cos(sweep)) * 120.0, Palette.a(Palette.PH, 0.85), 1.4)
			for rr in [40.0, 80.0, 120.0]:
				draw_arc(o, rr, 0, TAU, 48, Palette.a(Palette.PH, 0.16), 1.0, true)
			_layer_label("远望 R-9 SWEEP / 主动雷达", Palette.a(Palette.PH, 0.8), "EMIT · STRATEGIC SCOPE")
		3:
			var moon := _moon_km()
			var mp := _p2(Vector3(moon.x, moon.y, 0.0))
			var r := Rect2(mp - Vector2(110, 72), Vector2(220, 144))
			draw_rect(r, Palette.a(Palette.BLUE, 0.025))
			draw_rect(r, Palette.a(Palette.BLUE, 0.55), false, 1.0)
			var cp := r.get_center()
			draw_line(cp - Vector2(140, 0), cp + Vector2(140, 0), Palette.a(Palette.BLUE, 0.18), 1.0)
			draw_line(cp - Vector2(0, 100), cp + Vector2(0, 100), Palette.a(Palette.BLUE, 0.18), 1.0)
			_txt(mono, r.position.x + 8.0, r.position.y + 5.0, "MS-IR9 / STARE 12.4s", 7, Palette.a(Palette.BLUE, 0.8))
			_layer_label("MS-IR9 光学凝视", Palette.a(Palette.BLUE, 0.8), "LONG-RANGE STARE")
		4:
			for k in range(3):
				var rr := fmod(_t * 70.0 + float(k) * 130.0, 390.0)
				draw_arc(o, rr, 0, TAU, 64, Palette.a(Palette.PH, 0.10 * (1.0 - rr / 390.0)), 1.0, true)
			_layer_label("MK-12 IFF / 敌我识别", Palette.a(Palette.PH, 0.75))
		5:
			for t in state.tracks:
				if t.get("own", false):
					continue
				var pos2 := _p2(Vector3(sin(deg_to_rad(float(t.bearing))) * float(t.range), cos(deg_to_rad(float(t.bearing))) * float(t.range), 0.0))
				draw_dashed_line(o, pos2, Palette.a(Palette.AMBER, 0.16), 1.0, 5.0)
			_layer_label("ELINT / 通信截听", Palette.a(Palette.AMBER, 0.8), "PASSIVE · SIGNAL FINGERPRINT")

func _draw_planar_inset() -> void:
	var r := Rect2(size.x - 268.0, 64.0, 252.0, 156.0)
	draw_rect(r, Palette.a(Palette.PANEL, 0.85))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)
	_txt(cjk, r.position.x + 8.0, r.position.y + 5.0, "局部 / LOCAL PATCH", 7, Palette.a(Palette.PH, 0.8))
	_txt_r(mono, r.end.x - 8.0, r.position.y + 5.0, "×0.11 px/km", 7, Palette.a(Palette.FAINT, 0.9))
	var c := r.position + Vector2(86.0, 74.0)
	var sc := 0.105
	for rr in [100.0, 200.0, 400.0]:
		draw_arc(c, rr * sc, 0, TAU, 64, Palette.a(Palette.GRID, 0.9 if rr < 400.0 else 0.6), 1.0, true)
	for bb in range(0, 360, 30):
		var d := Vector2(sin(deg_to_rad(float(bb))), -cos(deg_to_rad(float(bb))))
		draw_line(c + d * 4.0, c + d * 6.0, Palette.a(Palette.GRID, 0.6), 1.0)
	for t in state.tracks:
		if t.get("own", false):
			continue
		var d2 := Vector2(sin(deg_to_rad(float(t.bearing))), -cos(deg_to_rad(float(t.bearing)))) * float(t.range) * sc
		var q := c + d2
		if q.x < r.position.x + 3.0 or q.x > r.end.x - 3.0 or q.y < r.position.y + 14.0 or q.y > r.end.y - 20.0:
			continue
		var col := _side_color(t)
		if t.get("bearing_only", false):
			draw_dashed_line(c, q, Palette.a(Palette.AMBER, 0.5), 1.0, 3.0)
		else:
			_draw_symbol(q, t, col)
	draw_circle(c, 1.6, Palette.PH)
	draw_arc(c, 5.0, 0, TAU, 20, Palette.a(Palette.PH, 0.6), 1.0, true)
	_txt(mono, r.position.x + 8.0, r.end.y - 22.0, "3D BOARD → ORTHO SNAPSHOT", 7, Palette.a(Palette.FAINT, 0.75))
	_txt(mono, r.position.x + 8.0, r.end.y - 10.0, "%s / %s" % [String(state.datum), String(state.unit.get("name", "OWN"))], 7, Palette.a(Palette.PH, 0.55))

# ── 界面装饰 ────────────────────────────────────────────

func _draw_chrome() -> void:
	if ortho:
		_chrome_planar()
	else:
		_chrome_3d()
	_draw_compass()
	if not ortho:
		_draw_optical()

func _chrome_3d() -> void:
	_txt(cjk, 16.0, 10.0, "战术态势", 14, Palette.PH)
	_txt(mono, 16.0, 29.0, "TACTICAL PLOT", 8, Palette.DIM)
	_txt(cjk, 16.0, 41.0, "LVLH · 半径 400 km · 高度 ×1" if String(state.datum) != "L1" else "STATION FRAME · 半径 400 km · 高度 ×1", 8, Palette.FAINT)
	_txt(mono, 16.0, 53.0, "DATUM %s · 3D ORBIT · %.0f km" % [String(state.datum), dist / 1000.0], 8, Palette.a(Palette.PH, 0.75))
	_txt(mono, 16.0, 65.0, "EXEC WINDOW %s · 1× LOCK" % _hms(state.exec_left), 7, Palette.a(Palette.AMBER, 0.70))
	var blink := 0.55 + 0.45 * sin(_t * 3.2)
	draw_circle(Vector2(8.0, 16.0), 2.2, Palette.a(Palette.PH, blink * 0.8))
	_draw_legend()
	_txt(mono, 16.0, size.y - 14.0, "拖动旋转 · 滚轮缩放 · R 翻转 · D 基准", 7, Palette.a(Palette.FAINT, 0.75))

func _chrome_planar() -> void:
	_txt(cjk, 16.0, 10.0, "压平态势", 14, Palette.PH)
	_txt(mono, 16.0, 29.0, "PLANAR CHART / CENTER OWN", 8, Palette.DIM)
	_txt(cjk, 16.0, 41.0, "ORTHOGRAPHIC · GRID 50,000 km", 8, Palette.FAINT)
	_txt(mono, 16.0, 53.0, "DATUM %s · PLANAR ×%.2f" % [String(state.datum), planar_zoom], 8, Palette.a(Palette.PH, 0.75))
	_txt(mono, 16.0, 65.0, "EXEC WINDOW %s · 1× LOCK" % _hms(state.exec_left), 7, Palette.a(Palette.AMBER, 0.70))
	var blink := 0.55 + 0.45 * sin(_t * 3.2)
	draw_circle(Vector2(8.0, 16.0), 2.2, Palette.a(Palette.PH, blink * 0.8))
	_corners(Rect2(6.0, 6.0, size.x - 12.0, size.y - 12.0), 14.0, Palette.a(Palette.PH, 0.40))
	# 图例 + 比例尺（V2 压平式）
	var ly := size.y - 44.0
	_txt(cjk, 16.0, ly, "● 友军    ◆ 敌对    □ 未知    ┄ 只方位", 7, Palette.a(Palette.FAINT, 0.9))
	var sx := 16.0
	var sy := size.y - 18.0
	var px := clampf(100000.0 * _planar_scale, 30.0, 180.0)
	draw_line(Vector2(sx, sy), Vector2(sx + px, sy), Palette.a(Palette.TXT, 0.6), 1.0)
	draw_line(Vector2(sx, sy - 4.0), Vector2(sx, sy + 2.0), Palette.a(Palette.TXT, 0.6), 1.0)
	draw_line(Vector2(sx + px, sy - 4.0), Vector2(sx + px, sy + 2.0), Palette.a(Palette.TXT, 0.6), 1.0)
	_txt(mono, sx, sy - 12.0, "100,000 km", 7, Palette.a(Palette.DIM, 0.8))
	_txt(mono, size.x - 16.0, size.y - 14.0, "拖动旋转 · 滚轮缩放 · R 翻转 · D 基准", 7, Palette.a(Palette.FAINT, 0.75))

func _draw_compass() -> void:
	var c := Vector2(size.x - 48.0, 46.0) if not ortho else Vector2(size.x - 62.0, size.y - 74.0)
	var nd := _north_dir()
	if nd.length() < 0.5:
		nd = Vector2(0.0, -1.0)
	var rot := atan2(nd.x, -nd.y)
	draw_arc(c, 18.0, 0, TAU, 48, Palette.a(Palette.LINE2, 0.8), 1.0, true)
	for i in range(12):
		var ang := rot + deg_to_rad(float(i) * 30.0)
		var d := Vector2(sin(ang), -cos(ang))
		var l := 4.0 if i % 3 == 0 else 2.0
		draw_line(c + d * 18.0, c + d * (18.0 - l), Palette.a(Palette.PH_DIM, 0.55), 1.0)
	var npos := c + Vector2(sin(rot), -cos(rot)) * 33.0
	_txt(mono, npos.x - 2.5, npos.y - 4.0, "N", 7, Palette.PH_DIM)
	# 本舰航向针（bearing 075）
	var hd := _heading_dir()
	if hd.length() < 0.5:
		hd = Vector2(0.0, -1.0)
	var pp := Vector2(-hd.y, hd.x)
	draw_line(c, c + hd * 12.0, Palette.a(Palette.PH, 0.75), 1.0)
	draw_colored_polygon(PackedVector2Array([
		c + hd * 14.0, c + hd * 8.0 + pp * 3.0, c + hd * 8.0 - pp * 3.0
	]), Palette.a(Palette.PH, 0.8))
	if ortho:
		_txt(cjk, c.x - 30.0, c.y + 46.0, "帧 PLANAR", 7, Palette.a(Palette.FAINT, 0.9))
	else:
		_txt(cjk, c.x - 90.0, c.y - 5.0, "帧 LVLH", 7, Palette.a(Palette.FAINT, 0.9))

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
	# 只方位：两道收敛的虚线（无距离）
	draw_dashed_line(Vector2(234, y + 12), Vector2(248, y + 2), Palette.a(Palette.AMBER, 0.8), 1.0, 3.0)
	draw_dashed_line(Vector2(234, y + 12), Vector2(248, y + 8), Palette.a(Palette.AMBER, 0.8), 1.0, 3.0)
	_txt(cjk, 252.0, y, "只方位", 8, Palette.DIM)
	var y2 := 704.0
	draw_line(Vector2(16, y2 + 5), Vector2(34, y2 + 5), Palette.a(Palette.PH, 0.8), 1.0)
	_txt(cjk, 40.0, y2, "现时", 7, Palette.DIM)
	draw_dashed_line(Vector2(82, y2 + 5), Vector2(100, y2 + 5), Palette.a(Palette.PH, 0.7), 1.0, 4.0)
	_txt(cjk, 106.0, y2, "计划", 7, Palette.DIM)
	draw_dashed_line(Vector2(148, y2 + 5), Vector2(166, y2 + 5), Palette.a(Palette.RED, 0.5), 1.0, 2.0)
	_txt(cjk, 172.0, y2, "预测", 7, Palette.DIM)

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
	_txt(mono, r.end.x - 42.0, r.position.y + 5.0, "MS-IR9 8×", 7, Palette.a(Palette.BLUE, 0.55))
	_txt(mono, r.position.x + 6.0, r.end.y - 12.0, "案卷 4471 +2.1", 7, Palette.a(Palette.BLUE, 0.55))

func _draw_sweep() -> void:
	var y := fmod(_t * 27.0, size.y)
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.a(Palette.PH, 0.022), 1.0)

# ── 硬切（80px 黑块） ──────────────────────────────────

func _make_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var cols := int(ceil(size.x / TILE))
	var rows := int(ceil(size.y / TILE))
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
		_tile_pos.append(Vector2(float(idx % cols) * TILE, float(idx / cols) * TILE))
		_cut_delay.append(float(k) / float(order.size()) * 0.30)
		_mode_cut_delay.append(0.02 + float(k) / float(order.size()) * 0.32)

func _draw_sensor_cut() -> void:
	if state.sensor_fx_t < 0.0:
		return
	for i in range(_tile_pos.size()):
		if state.sensor_fx_t < _cut_delay[i]:
			draw_rect(Rect2(_tile_pos[i], Vector2(TILE, TILE)), Palette.BG)

func _draw_mode_cut() -> void:
	if mode_fx_t < 0.0:
		return
	if mode_fx_t < 0.10:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.a(Palette.PH, 0.035 * (1.0 - mode_fx_t / 0.10)))
	for i in range(_tile_pos.size()):
		if mode_fx_t < _mode_cut_delay[i]:
			draw_rect(Rect2(_tile_pos[i], Vector2(TILE, TILE)), Palette.BG)

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

func _poly3(pts: Array[Vector3], color: Color, width := 1.0, dashed := false) -> void:
	var run: Array[Vector2] = []
	for p in pts:
		var q := _p3(p)
		if _ok(q):
			run.append(q)
		else:
			_flush(run, color, width, dashed)
			run.clear()
	_flush(run, color, width, dashed)

func _poly2(pts: Array[Vector3], color: Color, width := 1.0, dashed := false) -> void:
	var run: Array[Vector2] = []
	for p in pts:
		run.append(_p2(p))
	_flush(run, color, width, dashed)

func _flush(run: Array[Vector2], color: Color, width: float, dashed: bool) -> void:
	if run.size() < 2:
		return
	if dashed:
		_dashed_polyline(run, color, width, 5.0)
	else:
		draw_polyline(PackedVector2Array(run), color, width, true)

func _polyline(pts: Array[Vector2], color: Color, width := 1.0) -> void:
	if pts.size() < 2:
		return
	draw_polyline(PackedVector2Array(pts), color, width, true)

func _seg3(a: Vector3, b: Vector3, color: Color, width := 1.0) -> void:
	var pa := _p3(a)
	var pb := _p3(b)
	if _ok(pa) and _ok(pb):
		draw_line(pa, pb, color, width, true)

func _seg2(a: Vector2, b: Vector2, color: Color, width := 1.0) -> void:
	if _ok(a) and _ok(b):
		draw_line(a, b, color, width, true)

func _dashed_line2(a: Vector2, b: Vector2, color: Color, width := 1.0, dash := 4.0) -> void:
	if _ok(a) and _ok(b):
		draw_dashed_line(a, b, color, width, dash)

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

func _quad_bezier(a: Vector2, c: Vector2, b: Vector2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(0, 41):
		var t := float(i) / 40.0
		var u := 1.0 - t
		var p := a * u * u + c * 2.0 * u * t + b * t * t
		out.append(Vector3(p.x, p.y, 0.0))
	return out

func _hms(s: float) -> String:
	var t := int(maxf(s, 0.0))
	return "%02d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, t % 60]

func _fmt_km(v: float) -> String:
	var n := int(round(v))
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func _corners(r: Rect2, l: float, c: Color) -> void:
	draw_line(r.position, r.position + Vector2(l, 0), c, 1.0)
	draw_line(r.position, r.position + Vector2(0, l), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), c, 1.0)
	draw_line(r.end, r.end - Vector2(l, 0), c, 1.0)
	draw_line(r.end, r.end - Vector2(0, l), c, 1.0)

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)
