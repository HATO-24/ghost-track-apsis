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
const Orbit := preload("res://scripts/orbit_model.gd")
const CommandModel := preload("res://scripts/command_model.gd")

# P1a：历史 / 预测窗口（秒）与采样
const PRED_HORIZON := 300.0
const PRED_STEPS := 60
const HIST_HORIZON := 60.0
const HIST_STEPS := 24
const PRED_TICKS := [60.0, 120.0, 300.0]

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
var roll3d := 0.0
var roll_unlocked := false
# 压平战略图
var ortho := false
var yaw2d := 0.0
var planar_zoom := 1.0
# 自动缓慢自转；用户一动手就停
var auto_rotate := true
# 模式硬切：-1 = 不动画，0..0.44 = 进行中
var _label_rects: Array[Rect2] = []
var _pending_contact_labels: Array = []
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
	roll3d = 0.0
	roll_unlocked = false
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
		pitch = clampf(pitch, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
		auto_rotate = false

func rotate_map(dx: float, dy: float) -> void:
	auto_rotate = false
	if ortho:
		# 压平：横拖只 yaw；竖拖不改变指向（保持平面图固定）
		yaw2d = fposmod(yaw2d - dx * 0.006, TAU)
		yaw3d = yaw2d
	else:
		# 3D：横拖只改 yaw，竖拖只改 pitch；上拖=向前压（pitch 降低），下拖=抬高。
		# pitch 限幅在 [-8°, 78°]，不再 fposmod 翻面，避免横拖混入俯仰/指向跳变。
		yaw3d = fposmod(yaw3d - dx * 0.006, TAU)
		pitch = clampf(pitch + dy * 0.0035, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
		yaw2d = yaw3d

func toggle_roll_unlock() -> bool:
	roll_unlocked = not roll_unlocked
	auto_rotate = false
	return roll_unlocked

func rotate_roll(d: float) -> void:
	if not roll_unlocked:
		return
	roll3d = fposmod(roll3d + d, TAU)
	auto_rotate = false

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
	if absf(roll3d) > 0.00001:
		var cr := cos(roll3d)
		var sr := sin(roll3d)
		var rr := _right * cr + _up * sr
		var uu := _up * cr - _right * sr
		_right = rr
		_up = uu
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
	var px := Vector2(x, y) * _planar_scale
	if absf(roll3d) > 0.00001:
		var cr := cos(roll3d)
		var sr := sin(roll3d)
		px = Vector2(px.x * cr - px.y * sr, px.x * sr + px.y * cr)
	return size * 0.5 + px

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
	_label_rects.clear()
	_pending_contact_labels.clear()
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
	if _layer_on("stations"):
		_draw_datum_backing()
	if _layer_on("grid"):
		_draw_grid()
	if _layer_on("predictions"):
		_draw_own_plan()
	# P4d：先把本舰中心与点火/站位注记区当作保留区，接触标签绕开。
	var oo := _o()
	_label_rects.append(Rect2(oo - Vector2(150, 90), Vector2(300, 180)).grow(4.0))
	_label_rects.append(Rect2(oo + Vector2(0, 22), Vector2(300, 86)).grow(4.0))
	for raw in state.pending_commands():
		var c2: Dictionary = raw
		var tgt := String(c2.get("target", ""))
		if tgt != "":
			var tt: Dictionary = state.track_by_id(tgt)
			if not tt.is_empty() and _lvl(tt) >= 2:
				var cp := _contact_pos3(tt)
				if _ok(cp):
					_label_rects.append(Rect2(cp + Vector2(10, -38), Vector2(250, 56)).grow(4.0))
	if _layer_on("contacts"):
		_draw_contacts()
	_draw_own()
	_draw_interaction_overlays()
	for it in _pending_contact_labels:
		_draw_track_label(it["t"], it["p"], it["col"])
	if _layer_on("radar"):
		_draw_sensor()
	_draw_tasks()
	_draw_chrome()
	_draw_target_menu()
	_draw_command_queue()

func _draw_planar() -> void:
	_draw_stars()
	if _layer_on("grid"):
		_draw_planar_grid()
	if _layer_on("predictions"):
		_draw_planar_orbits()
	if _layer_on("stations"):
		_draw_planar_rings()
		_draw_planar_bodies()
	if _layer_on("contacts"):
		_draw_planar_contacts()
	_draw_planar_own()
	_draw_interaction_overlays()
	if _layer_on("radar"):
		_draw_planar_sensor()
	_draw_tasks()
	if _layer_on("predictions"):
		_draw_planar_inset()
	_draw_chrome()
	_draw_target_menu()

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

func _layer_on(name: String) -> bool:
	if state != null and state.has_method("is_layer_visible"):
		return bool(state.call("is_layer_visible", name))
	return true

func _track_screen(t: Dictionary) -> Vector2:
	if ortho:
		if _lvl(t) <= 1:
			var b1 := deg_to_rad(float(t.get("obs_bearing_deg", t.get("bearing", 0.0))))
			return _p2(Vector3(sin(b1), cos(b1), 0.0) * 300.0)
		return _p2(_track_km(t, _tau_now()))
	if _lvl(t) <= 1:
		var b2 := deg_to_rad(float(t.get("obs_bearing_deg", t.get("bearing", 0.0))))
		return _p3(_world(rad_to_deg(b2), 300.0, 0.0))
	return _contact_pos3(t)

# 右键命中：返回 track id（屏幕坐标，14px 半径；L1 方位线取 300km 处中点）
func pick_track(p: Vector2) -> String:
	if state == null:
		return ""
	var best := ""
	var best_d := 18.0
	for t in state.tracks:
		if t.get("own", false) or bool(t.get("occluded", false)) or bool(t.get("phantom", false)):
			continue
		var q := _track_screen(t)
		if not _ok(q):
			continue
		var d := p.distance_to(q)
		if d < best_d:
			best_d = d
			best = String(t.get("id", t.get("batch", "")))
	return best

# 目标选中括号 / 通道进度 / 对接状态（地图交互层）
func _draw_interaction_overlays() -> void:
	if state == null:
		return
	if bool(state.get("target_menu_open")) and String(state.get("target_menu_track")) != "":
		var tid := String(state.target_menu_track)
		var tr: Dictionary = state.track_by_id(tid)
		if not tr.is_empty():
			var q := _track_screen(tr)
			if _ok(q):
				draw_rect(Rect2(q - Vector2(14, 14), Vector2(28, 28)), Palette.a(Palette.AMBER, 0.85), false, 1.0)
				for a in [Vector2(-14, -14), Vector2(14, -14), Vector2(-14, 14), Vector2(14, 14)]:
					draw_line(q + a, q + a * 0.7, Palette.a(Palette.AMBER, 0.9), 1.0)
	# 光学 / 红外通道：目标环 + 进度
	var chs: Dictionary = state.get("track_channels") if state.get("track_channels") is Dictionary else {}
	for raw_id in chs.keys():
		var tid2 := String(raw_id)
		var tr2: Dictionary = state.track_by_id(tid2)
		if tr2.is_empty():
			continue
		var q2 := _track_screen(tr2)
		if not _ok(q2):
			continue
		var cd: Dictionary = chs[tid2]
		var yy := -24.0
		for kind in cd.keys():
			var e: Dictionary = cd[kind]
			var st := String(e.get("status", ""))
			if st == "stopped":
				continue
			var prog := clampf(float(e.get("progress", 0.0)), 0.0, 1.0)
			var col := Palette.BLUE if String(kind) == "optical" else Palette.AMBER
			draw_arc(q2, 20.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 if st == "locked" else prog), 40, Palette.a(col, 0.8), 1.2, true)
			_txt(mono, q2.x + 24.0, q2.y + yy, "%s %s %d%%" % ["OPT" if String(kind) == "optical" else "IR", "锁定" if st == "locked" else "跟踪", int(round(prog * 100.0))], 7, Palette.a(col, 0.85))
			yy += 12.0

# 目标菜单 fallback（HUD 未接管时由 plot 绘制；HUD 接管后不画）
func _draw_target_menu() -> void:
	if state == null or not bool(state.get("target_menu_open")) or bool(state.get("target_menu_hud_handled")):
		return
	var acts: Array = state.get("target_menu_actions") if state.get("target_menu_actions") is Array else []
	if acts.is_empty():
		return
	var tid := String(state.get("target_menu_track"))
	var tr: Dictionary = state.track_by_id(tid)
	var sx := size.x - 252.0
	var sy := 454.0
	var h := 34.0 + float(acts.size()) * 13.0
	draw_rect(Rect2(sx - 6.0, sy - 14.0, 244.0, h), Palette.a(Palette.PANEL, 0.9))
	draw_rect(Rect2(sx - 6.0, sy - 14.0, 244.0, h), Palette.a(Palette.AMBER, 0.35), false, 1.0)
	_txt(cjk, sx, sy, "目标动作 / [%s] %s" % [String(tr.get("batch", tid)), String(tr.get("name", ""))], 8, Palette.AMBER)
	var yy := sy + 15.0
	for raw in acts:
		var a: Dictionary = raw
		var avail := bool(a.get("available", false))
		var unsup := bool(a.get("unsupported", false))
		var col := Palette.PH if avail else (Palette.FAINT if not unsup else Palette.DIM)
		var tail := "" if avail else ("未实现" if unsup else "需 L%d" % int(a.get("min_level", 1)))
		_txt(mono, sx, yy, "%s  %s" % [String(a.get("label", a.get("id", ""))), tail], 7, Palette.a(col, 0.85))
		yy += 13.0

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
	# 站点十字（画在本舰标记下面一层）
	draw_line(o - Vector2(34.0, 0.0), o + Vector2(34.0, 0.0), Palette.a(Palette.PH, 0.30), 1.0)
	draw_line(o - Vector2(0.0, 34.0), o + Vector2(0.0, 34.0), Palette.a(Palette.PH, 0.30), 1.0)
	_txt_r(mono, size.x - 24.0, size.y - 80.0, "VIEW 3D · DIST %s km" % _fmt_km(dist / 1000.0), 7, Palette.a(Palette.PH_DIM, 0.8))
	_txt_r(mono, size.x - 24.0, size.y - 68.0, "STATION FRAME / L1 Meridian-05 Chronos", 8, Palette.a(Palette.PH_DIM, 0.75))
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

# ── 本舰：历史 / 点火计划 / 命令幽灵（P1d）─────────────

func _own_now() -> Dictionary:
	return state.own_at(_tau_now())

func _own_history_pts() -> Array[Vector3]:
	var tau := _tau_now()
	var cur: Vector3 = (_own_now()["r"] as Vector3)
	var pts: Array[Vector3] = []
	for i in range(HIST_STEPS + 1):
		var tt := -HIST_HORIZON + HIST_HORIZON * float(i) / float(HIST_STEPS)
		var st: Dictionary = state.own_at(tau + tt)
		pts.append((st["r"] as Vector3) - cur)
	return pts

# 本舰计划：从当前实际状态出发，应用所有 PENDING BURN（命令模型 plan）
func _own_plan_data() -> Dictionary:
	var tau := _tau_now()
	var st := _own_now()
	var burns: Array = []
	for raw in state.pending_commands():
		var c: Dictionary = raw
		if String(c.get("action", "")) != "BURN":
			continue
		if float(c.get("exec_t", tau)) < tau:
			continue
		var pl: Dictionary = c.get("plan", {})
		burns.append({"t": float(c.get("exec_t", tau)), "dv": pl.get("dv", Vector3.ZERO), "cmd": c})
	return CommandModel.plan_own(st, tau, burns, PRED_HORIZON, PRED_STEPS)

func _burn_screen_dir(km: Vector3, dv: Vector3) -> Vector2:
	var a := _p3(km * 1000.0)
	var b := _p3((km + dv * 90.0) * 1000.0)
	if not _ok(a) or not _ok(b):
		return Vector2(0.0, -1.0)
	var d := b - a
	if d.length() < 0.01:
		return Vector2(0.0, -1.0)
	return d.normalized()

# 点火节点：Δv 箭头 + 节点 + T+/Δv/状态标签；pending = 命令幽灵（虚线菱形）
func _draw_burn_node(km: Vector3, cmd: Dictionary, pending: bool, remain: float, draft := false) -> void:
	var p := _p3(km * 1000.0)
	if not _ok(p):
		return
	var pl: Dictionary = cmd.get("plan", {})
	var dv: Vector3 = pl.get("dv", Vector3.ZERO)
	var dir := _burn_screen_dir(km, dv)
	var perp := Vector2(-dir.y, dir.x)
	var exec_t := float(cmd.get("exec_t", 0.0))
	var col := Palette.BLUE if draft else (Palette.PH if not pending else Palette.AMBER)
	var alpha := 0.9 if not pending else (0.55 + 0.35 * sin(_t * 4.0))
	var d := 6.0
	var diamond_list: Array[Vector2] = [
		p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d),
		p + Vector2(-d, 0), p + Vector2(0, -d)
	]
	var diamond := PackedVector2Array(diamond_list)
	if pending:
		_dashed_polyline(diamond_list, Palette.a(col, alpha), 1.0, 3.0)
		_txt(mono, p.x + 10.0, p.y - 20.0, "命令幽灵", 7, Palette.a(col, alpha))
	else:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)
		]), Palette.a(col, 0.45))
		draw_polyline(diamond, Palette.a(col, 0.9), 1.0)
	draw_arc(p, 15.0, 0, TAU, 32, Palette.a(col, 0.18), 1.0, true)
	# Δv 箭头
	draw_line(p - dir * 6.0, p + dir * 30.0, Palette.a(Palette.PH if not pending else Palette.PH_DIM, 0.85), 1.2)
	draw_colored_polygon(PackedVector2Array([
		p + dir * 36.0, p + dir * 26.0 + perp * 4.0, p + dir * 26.0 - perp * 4.0
	]), Palette.a(Palette.PH if not pending else Palette.PH_DIM, 0.85))
	# 标签
	var bms := float(pl.get("dv_ms", 0.0))
	var bbrg := float(pl.get("brg", 0.0))
	var belev := float(pl.get("elev", 0.0))
	var lx := p.x + 16.0
	var ly := p.y + 38.0
	if pending:
		_txt(cjk, lx, ly, "点火 T+%04.1fs · %s" % [exec_t, ("轨道预览 / 未点火" if draft else "待生效")], 9, Palette.a(Palette.BLUE if draft else Palette.AMBER, 0.95))
		_txt(mono, lx, ly + 13.0, "Δv %.0f m/s · BRG %03d° · ELEV %+02d°" % [bms, int(bbrg), int(belev)], 8, Palette.a(Palette.PH_DIM, 1.0))
		_txt(mono, lx, ly + 26.0, "%s / %s" % [state.cmd_model.phase_text(cmd, _tau_now()), "未点火" if draft else "命令幽灵"], 7, Palette.a(Palette.BLUE if draft else Palette.AMBER, 0.85))
	else:
		_txt(cjk, lx, ly, "点火 T+%04.1fs · 已执行" % exec_t, 9, Palette.a(Palette.PH, 0.95))
		_txt(mono, lx, ly + 13.0, "Δv %.0f m/s · 已扣 · 已执行" % bms, 8, Palette.a(Palette.PH_DIM, 0.95))

func _target_marker_pos(t: Dictionary) -> Vector2:
	if _lvl(t) >= 2:
		return _contact_pos3(t)
	var b := float(t.get("obs_bearing_deg", t.get("bearing", 0.0)))
	if b < 0.0:
		b = float(t.get("bearing", 0.0))
	return _p3(_world(b, 330.0, 0.0))

func _draw_ghost_bracket(p: Vector2, col: Color) -> void:
	var br := 18.0
	var rect: Array[Vector2] = [
		p + Vector2(-br, -br), p + Vector2(br, -br),
		p + Vector2(br, br), p + Vector2(-br, br), p + Vector2(-br, -br)
	]
	_dashed_polyline(rect, col, 1.0, 4.0)
	_txt(mono, p.x - br, p.y - br - 10.0, "GHOST", 7, col)

func _draw_shadow_commands(tau: float) -> void:
	# 待生效：目标处的命令幽灵
	for raw in state.pending_commands():
		var c: Dictionary = raw
		if String(c.get("action", "")) != "SHADOW":
			continue
		var tid := String(c.get("target", ""))
		var t: Dictionary = state.track_by_id(tid)
		if t.is_empty():
			continue
		var p := _target_marker_pos(t)
		if not _ok(p):
			continue
		_draw_ghost_bracket(p, Palette.a(Palette.AMBER, 0.55))
		var remain := float(c.get("exec_t", tau)) - tau
		_txt(cjk, p.x + 22.0, p.y - 32.0, "跟踪（SHADOW）%s · 待生效" % tid, 9, Palette.a(Palette.AMBER, 0.9))
		_txt(mono, p.x + 22.0, p.y - 20.0, "望楼中继 +8 s · %s" % state.cmd_model.phase_text(c, tau), 7, Palette.a(Palette.AMBER, 0.6))
	# 已生效：跟踪括号 + 连线
	var active: Dictionary = state.cmd_model.active_shadow()
	if active.is_empty():
		return
	var tid2 := String(active.get("target", ""))
	var t2: Dictionary = state.track_by_id(tid2)
	if t2.is_empty():
		return
	var p2 := _target_marker_pos(t2)
	if not _ok(p2):
		return
	draw_dashed_line(_o(), p2, Palette.a(Palette.PH, 0.16), 1.0, 6.0)
	var br := 14.0
	for corner in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
		var q := p2 + Vector2(float(corner[0]) * br, float(corner[1]) * br)
		draw_line(q, q - Vector2(float(corner[0]) * 7.0, 0.0), Palette.a(Palette.PH, 0.8), 1.0)
		draw_line(q, q - Vector2(0.0, float(corner[1]) * 7.0), Palette.a(Palette.PH, 0.8), 1.0)
	_txt(cjk, p2.x + 20.0, p2.y + 2.0, "跟踪（SHADOW）· %s" % tid2, 8, Palette.a(Palette.PH, 0.85))
	_txt(mono, p2.x + 20.0, p2.y + 14.0, "跟踪生效 / 望楼号中继", 7, Palette.a(Palette.PH_DIM, 0.8))

func _draw_station_commands(tau: float) -> void:
	for raw in state.pending_commands():
		var c: Dictionary = raw
		if String(c.get("action", "")) != "STATION":
			continue
		var p := _o()
		var remain := float(c.get("exec_t", tau)) - tau
		_draw_ghost_bracket(p - Vector2(46.0, 0.0), Palette.a(Palette.AMBER, 0.5))
		_txt(cjk, p.x - 90.0, p.y - 34.0, "保持站位（STATION）· 待生效 %.1fs" % maxf(0.0, remain), 8, Palette.a(Palette.AMBER, 0.8))
	if state.station_hold:
		_txt(mono, _o().x + 16.0, _o().y + 34.0, "保持站位（STATION）", 7, Palette.a(Palette.PH_DIM, 0.9))

func _draw_own_plan() -> void:
	var tau := _tau_now()
	var cur_r: Vector3 = _own_now()["r"]
	# 历史（-60..0 s）：实线暗
	_poly_km(_own_history_pts(), Palette.a(Palette.PH_DIM, 0.32), 1.2, false)
	# 已执行点火：节点（实心）
	for raw in state.own_events:
		var ev: Dictionary = raw
		var et := float(ev.get("t", 0.0))
		if et > tau:
			continue
		var ev_st: Dictionary = state.own_at(et)
		var ev_km := (ev_st["r"] as Vector3) - cur_r
		var dv: Vector3 = ev.get("dv", Vector3.ZERO)
		var brg := rad_to_deg(atan2(dv.x, dv.y))
		var elev := rad_to_deg(asin(clampf(dv.z / maxf(dv.length(), 1.0e-9), -1.0, 1.0)))
		var fake := {
			"exec_t": et,
			"plan": {"dv_ms": dv.length() * 1000.0, "dv": dv, "brg": brg, "elev": elev},
		}
		_draw_burn_node(ev_km, fake, false, 0.0)
	# 计划（0..+300 s）：虚线 + 待生效点火节点（命令幽灵）
	var plan := _own_plan_data()
	_poly_km(plan["pts"], Palette.a(Palette.PH, 0.60), 1.3, true)
	for raw in plan["events"]:
		var ev: Dictionary = raw
		var cmd: Dictionary = ev.get("cmd", {})
		_draw_burn_node(ev["km"] as Vector3, cmd, true, float(cmd.get("exec_t", 0.0)) - tau)
	var pts: Array = plan["pts"]
	# 计划终点
	if pts.size() > 0:
		var ep := _p3((pts[pts.size() - 1] as Vector3) * 1000.0)
		if _ok(ep):
			_txt(mono, ep.x + 6.0, ep.y + 10.0, "计划 +300 s", 7, Palette.a(Palette.PH_FAINT, 0.8))
	# 计划节点 B-2（点火后 +120 s 的计划位置）
	var node_rel := 120.0
	var node_idx := int(round(node_rel / PRED_HORIZON * float(PRED_STEPS)))
	if node_idx >= 0 and node_idx < pts.size():
		var np3: Vector3 = pts[node_idx]
		var np := _p3(np3 * 1000.0)
		if _ok(np):
			draw_polyline(PackedVector2Array([
				np + Vector2(0, -6), np + Vector2(6, 0), np + Vector2(0, 6),
				np + Vector2(-6, 0), np + Vector2(0, -6)
			]), Palette.a(Palette.PH_DIM, 0.85), 1.0)
			_txt_r(mono, np.x - 10.0, np.y - 4.0, "NODE B-2 · T+%ds" % int(node_rel), 7, Palette.a(Palette.PH_DIM, 0.9))
			_txt_r(mono, np.x - 10.0, np.y + 8.0, "%.1f km" % np3.length(), 7, Palette.a(Palette.PH_FAINT, 0.9))
	# P1e：预览命令（preview_command）→ draft 节点 / 预览线
	var pv: Dictionary = state.cmd_model.preview_cmd
	if not pv.is_empty():
		var pa := String(pv.get("action", ""))
		if pa == "BURN":
			var pl: Dictionary = pv.get("plan", {})
			var pburn: Array = [{"t": float(pv.get("exec_t", tau)), "dv": pl.get("dv", Vector3.ZERO), "cmd": pv}]
			var pplan := CommandModel.plan_own(_own_now(), tau, pburn, PRED_HORIZON, PRED_STEPS)
			_poly_km(pplan["pts"], Palette.a(Palette.BLUE, 0.55), 1.1, true)
			var evs: Array = pplan["events"]
			if evs.size() > 0:
				var pe: Dictionary = evs[0]
				_draw_burn_node(pe["km"] as Vector3, pv, true, 0.0, true)
			else:
				var endpoints: Array = pplan["pts"]
				if endpoints.size() > 0:
					var pend := _p3((endpoints[endpoints.size() - 1] as Vector3) * 1000.0)
					if _ok(pend):
						_txt(cjk, pend.x + 6.0, pend.y - 8.0, "DRAFT 预览（点火在 +300s 视野外）", 8, Palette.a(Palette.BLUE, 0.8))
		elif pa == "SHADOW":
			var ptid := String(pv.get("target", ""))
			var pt: Dictionary = state.track_by_id(ptid)
			if not pt.is_empty():
				var pp := _target_marker_pos(pt)
				if _ok(pp):
					_draw_ghost_bracket(pp, Palette.a(Palette.BLUE, 0.6))
					_txt(cjk, pp.x + 22.0, pp.y - 32.0, "SHADOW %s · DRAFT 预览" % ptid, 9, Palette.a(Palette.BLUE, 0.85))
	# 命令幽灵 / 生效标记
	_draw_shadow_commands(tau)
	_draw_station_commands(tau)

# 命令队列面板（右上，光学小窗下方；不占 HUD）
func _draw_command_queue() -> void:
	var cmds: Array = state.commands()
	if cmds.is_empty():
		return
	var shown: Array = []
	var start := maxi(0, cmds.size() - 5)
	for i in range(start, cmds.size()):
		shown.append(cmds[i])
	var has_draft: bool = not state.cmd_model.preview_cmd.is_empty()
	var rows := shown.size() + (1 if has_draft else 0)
	var r := Rect2(size.x - 252.0, 216.0, 236.0, 26.0 + float(rows) * 25.0)
	draw_rect(r, Palette.a(Palette.PANEL, 0.88))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)
	_txt(cjk, r.position.x + 8.0, r.position.y + 5.0, "命令队列 / COMMAND QUEUE", 7, Palette.a(Palette.PH, 0.85))
	_txt_r(mono, r.end.x - 8.0, r.position.y + 5.0, "%02d" % cmds.size(), 7, Palette.a(Palette.FAINT, 0.9))
	var tau := _tau_now()
	var y := r.position.y + 15.0
	for raw in shown:
		var c: Dictionary = raw
		var act := String(c.get("action", ""))
		var st := String(c.get("status", ""))
		var col := Palette.PH
		var tail := ""
		match st:
			"QUEUED":
				col = Palette.AMBER
				tail = "传达 %.1fs" % maxf(0.0, float(c.get("tx_t", tau)) - tau)
			"TRANSMITTED":
				col = Palette.AMBER
				tail = "生效 %.1fs" % maxf(0.0, float(c.get("exec_t", tau)) - tau)
			"EXEC":
				col = Palette.PH_DIM
				tail = "确认 %.1fs" % maxf(0.0, float(c.get("done_t", tau)) - tau)
			"DONE":
				col = Palette.PH_FAINT
				tail = "已完成"
			"ABORTED":
				col = Palette.FAINT
				tail = "已撤销"
			_:
				col = Palette.RED
				tail = "已拒绝"
		var name := act
		if act == "SHADOW":
			name = "跟踪（SHADOW）" + String(c.get("target", ""))
		elif act == "BURN":
			name = "点火（BURN）T+%04.1f Δv%.0f" % [float(c.get("exec_t", 0.0)), float((c.get("plan", {}) as Dictionary).get("dv_ms", 0.0))]
		elif act == "STATION":
			name = "保持站位（STATION）"
		_txt(mono, r.position.x + 8.0, y, String(c.get("id", "")), 7, Palette.a(Palette.FAINT, 0.9))
		_txt(cjk, r.position.x + 60.0, y, name, 7, Palette.a(col, 0.92))
		_txt_r(mono, r.end.x - 8.0, y, tail, 7, Palette.a(col, 0.85))
		if String(c.get("id", "")) == String(state.cmd_model.selected_id):
			draw_line(Vector2(r.position.x + 4.0, y + 9.0), Vector2(r.end.x - 4.0, y + 9.0), Palette.a(Palette.PH, 0.25), 1.0)
		y += 25.0
	if has_draft:
		var pv: Dictionary = state.cmd_model.preview_cmd
		var pact := String(pv.get("action", ""))
		var pname := pact
		if pact == "BURN":
			pname = "点火（BURN）T+%04.1f Δv%.0f" % [float(pv.get("exec_t", 0.0)), float((pv.get("plan", {}) as Dictionary).get("dv_ms", 0.0))]
		elif pact == "SHADOW":
			pname = "跟踪（SHADOW）" + String(pv.get("target", ""))
		_txt(mono, r.position.x + 8.0, y, "草案", 7, Palette.a(Palette.BLUE, 0.9))
		_txt(cjk, r.position.x + 60.0, y, pname, 7, Palette.a(Palette.BLUE, 0.9))
		_txt_r(mono, r.end.x - 8.0, y, "预览", 7, Palette.a(Palette.BLUE, 0.9))

# ── 接触状态向量 / 预测轨道 ────────────────────────────

var _pred_cache: Dictionary = {}

func _tau_now() -> float:
	return state.tau()

func _track_km(t: Dictionary, tau: float) -> Vector3:
	return state.board_pos(t, tau)

func _track_vel(t: Dictionary, tau: float) -> Vector3:
	return state.board_vel(t, tau)

func _track_pos(t: Dictionary) -> Vector2:
	return _p3(_track_km(t, _tau_now()) * 1000.0)

# 历史（-60 s）+ 预测（+300 s）折线；按 id 缓存 0.25 s
# 注意：本舰点火会改变局部板原点，所以这里用 state.board_pos（含已生效点火）
func _pred_data(t: Dictionary) -> Dictionary:
	var tau := _tau_now()
	var key := String(t.get("id", "?"))
	var cached: Dictionary = _pred_cache.get(key, {})
	if not cached.is_empty() and absf(float(cached.get("tau", -1.0e9)) - tau) < 0.25:
		return cached
	var hist_pts: Array[Vector3] = []
	for i in range(HIST_STEPS + 1):
		var tt := -HIST_HORIZON + HIST_HORIZON * float(i) / float(HIST_STEPS)
		hist_pts.append(state.board_pos(t, tau + tt))
	var pred_pts: Array[Vector3] = []
	for i in range(PRED_STEPS + 1):
		var tt2 := PRED_HORIZON * float(i) / float(PRED_STEPS)
		pred_pts.append(state.board_pos(t, tau + tt2))
	var out := {"tau": tau, "hist": {"pts": hist_pts}, "pred": {"pts": pred_pts}}
	_pred_cache[key] = out
	return out

# 局部板 km 折线 → 屏幕（自动裁掉相机后面的点）
func _poly_km(pts: Array, color: Color, width := 1.0, dashed := false) -> void:
	var run: Array[Vector2] = []
	for p in pts:
		var v: Vector3 = p
		var q := _p3(v * 1000.0)
		if _ok(q):
			run.append(q)
		else:
			_flush(run, color, width, dashed)
			run.clear()
	_flush(run, color, width, dashed)

func _px_per_km(km: Vector3) -> float:
	var a := _p3(km * 1000.0)
	var dir := km
	if dir.length() < 1.0:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	var b := _p3((km + dir * 10.0) * 1000.0)
	if not _ok(a) or not _ok(b):
		return 0.0
	return a.distance_to(b) / 10.0

func _screen_dir(km: Vector3, vel: Vector3) -> Vector2:
	if vel.length() < 1.0e-6:
		return Vector2(0.0, -1.0)
	var a := _p3(km * 1000.0)
	var b := _p3((km + vel.normalized() * 10.0) * 1000.0)
	if not _ok(a) or not _ok(b):
		return Vector2(0.0, -1.0)
	var d := b - a
	if d.length() < 0.001:
		return Vector2(0.0, -1.0)
	return d.normalized()

# 位置协方差（各向异性：沿航迹大、横向小）画成虚线椭圆；随时间单调变大
func _cov_ellipse(p: Vector2, sigma: float, pxk: float, dir: Vector2, col: Color, alpha := 0.28) -> void:
	if sigma < 0.05 or pxk < 1.0e-4:
		return
	var rx := minf(sigma * 1.4 * pxk, 44.0)
	var ry := minf(sigma * 0.55 * pxk, 18.0)
	if rx < 1.6:
		return
	var rot := dir.angle() if dir.length() > 0.001 else 0.0
	var e: Array[Vector2] = []
	for i in range(0, 361, 12):
		var a := deg_to_rad(float(i))
		e.append(p + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	_dashed_polyline(e, Palette.a(col, alpha), 1.0, 3.0)

# 历史（实线暗）/ 预测（虚线）/ +60 +120 +300 刻度 / 随时间变大的误差椭圆
func _draw_track_motion(t: Dictionary, p: Vector2, col: Color) -> void:
	var data := _pred_data(t)
	_poly_km(data["hist"]["pts"], Palette.a(col, 0.24), 1.0, false)
	_poly_km(data["pred"]["pts"], Palette.a(col, 0.60), 1.0, true)
	var tau := _tau_now()
	var km0 := _track_km(t, tau)
	var vel0 := _track_vel(t, tau)
	var pxk := _px_per_km(km0)
	var sdir := _screen_dir(km0, vel0)
	# 当前误差椭圆
	_cov_ellipse(p, Orbit.sigma_km(t, 0.0), pxk, sdir, col, 0.22)
	var labels := String(t.get("side", "")) != "friend"
	for tick in PRED_TICKS:
		var km := _track_km(t, tau + float(tick))
		var q := _p3(km * 1000.0)
		if not _ok(q):
			continue
		var ahead := _track_km(t, tau + float(tick) + 8.0)
		var qa := _p3(ahead * 1000.0)
		var dir := (qa - q)
		if dir.length() < 0.001:
			dir = sdir
		else:
			dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		var sigma := Orbit.sigma_km(t, float(tick))
		var half := minf(maxf(sigma * 1.2 * pxk, 3.0), 44.0)
		# 刻度：垂直航迹的误差条（随预测时间变长）
		draw_line(q - perp * half, q + perp * half, Palette.a(col, 0.45), 1.0)
		draw_line(q - dir * 3.0, q + dir * 3.0, Palette.a(col, 0.75), 1.0)
		if labels:
			_txt(mono, q.x + 7.0, q.y - 3.0, "+%ds" % int(tick), 7, Palette.a(col, 0.60))
	# +300 s 处画一个完整的误差椭圆（生长终点）
	var km300 := _track_km(t, tau + PRED_HORIZON)
	var q300 := _p3(km300 * 1000.0)
	if _ok(q300):
		_cov_ellipse(q300, Orbit.sigma_km(t, PRED_HORIZON), pxk, sdir, col, 0.26)


# ── 接触（P1c：按传感器等级画）──────────────────────────

func _contact_pos3(t: Dictionary) -> Vector2:
	return _track_pos(t)

func _lvl(t: Dictionary) -> int:
	return clampi(int(t.get("level", 1)), 0, 4)

# 敌我识别（IFF）应答状态 → 中文（IFF 不判敌意；不明 ≠ 敌意）
func _iff_text(iff: String) -> String:
	match iff:
		"friend":
			return "友军"
		"faulty_transponder":
			return "应答机故障"
		"wrong_code":
			return "应答码错误"
		"no_reply":
			return "无应答"
		"":
			return "未询问"
		_:
			return iff

func _draw_contacts() -> void:
	for t in state.tracks:
		if t.get("own", false):
			continue
		if bool(t.get("occluded", false)):
			continue   # 遮蔽不画（05 §S-02/S-03 对抗）
		if bool(t.get("phantom", false)):
			_draw_phantom(t)
			continue
		var col := _side_color(t)
		if _lvl(t) <= 1:
			_draw_bearing_contact(t, col)
			continue
		var km := _track_km(t, _tau_now())
		var p := _p3(km * 1000.0)
		if not _ok(p):
			continue
		# 存储/预测轨道只有 L2+（有距离解）才画
		_draw_track_motion(t, p, col)
		var base := _p3(Vector3(km.x, km.y, 0.0) * 1000.0)
		if absf(km.z) > 3.0 and _ok(base):
			draw_dashed_line(base, p, Palette.a(col, 0.30), 1.0, 2.0)
			draw_circle(base, 1.4, Palette.a(col, 0.35))
		_draw_covariance(p, t, col)
		_draw_symbol(p, t, col)
		_pending_contact_labels.append({"t": t, "p": p, "col": col})

# L1：只有方位线（无点、无距离、无预测）
func _draw_bearing_contact(t: Dictionary, col: Color) -> void:
	var o := _o()
	var b := float(t.get("obs_bearing_deg", t.get("bearing", 0.0)))
	if b < 0.0:
		b = float(t.get("bearing", 0.0))
	var half := 1.2
	var far := 470.0
	var p1 := _p3(_world(b - half, far, 0.0))
	var p2 := _p3(_world(b + half, far, 0.0))
	if _ok(p1) and _ok(p2):
		draw_colored_polygon(PackedVector2Array([o, p1, p2]), Palette.a(col, 0.030))
		draw_dashed_line(o, p1, Palette.a(col, 0.26), 1.0, 4.0)
		draw_dashed_line(o, p2, Palette.a(col, 0.26), 1.0, 4.0)
	var mid := _p3(_world(b, 300.0, 0.0))
	if _ok(mid):
		var off: Vector2 = t.get("off", Vector2(16, 12))
		var lx := mid.x + off.x * 0.35
		var ly := mid.y + off.y * 0.35
		var bname := String(t.get("name", t.get("id", "")))
		var bbatch := String(t.get("batch", t.get("id", "")))
		var idf := cjk if Fonts.has_cjk(bname) else mono
		_txt(idf, lx, ly - 16.0, "[%s] %s" % [bbatch, bname], 10, Palette.a(col, 0.85))
		var band := String(t.get("range_band", ""))
		if band == "":
			band = "距离不明"
		_txt(mono, lx, ly - 4.0, "%s · L1 · 仅方位 · %s" % [_identity_label(_ident(t)), band], 7, Palette.a(col, 0.62))
		_txt(mono, lx, ly + 8.0, "仅方位 · 未定位 / BEARING ONLY", 7, Palette.a(col, 0.36))
		draw_line(mid + Vector2(-3, 0), mid + Vector2(3, 0), Palette.a(col, 0.7), 1.0)
		draw_line(mid + Vector2(0, -3), mid + Vector2(0, 3), Palette.a(col, 0.7), 1.0)

# CH-IR2 回波：没有实体，只有一条方位线；交叉确认后标「无威胁目标」
func _draw_phantom(t: Dictionary) -> void:
	var o := _o()
	var resolved := bool(t.get("false_alarm", false))
	var col := Palette.FAINT if resolved else Palette.AMBER
	var b := float(state.phantom_bearing)
	var pm := _p3(_world(b, 470.0, 0.0))
	if not _ok(pm):
		return
	draw_dashed_line(o, pm, Palette.a(col, 0.16 if resolved else 0.28), 1.0, 6.0)
	var mid := _p3(_world(b, 315.0, 0.0))
	if not _ok(mid):
		return
	if resolved:
		# 无威胁目标：灰阶方框 + 斜杠（无实体，已交叉确认）
		draw_rect(Rect2(mid - Vector2(5, 5), Vector2(10, 10)), Palette.a(Palette.FAINT, 0.10))
		draw_rect(Rect2(mid - Vector2(5, 5), Vector2(10, 10)), Palette.a(Palette.FAINT, 0.85), false, 1.0)
		draw_line(mid + Vector2(-6, -6), mid + Vector2(6, 6), Palette.a(Palette.FAINT, 0.55), 1.0)
		_txt(mono, mid.x + 10.0, mid.y - 20.0, "[9002] 无威胁目标", 8, Palette.a(Palette.FAINT, 0.9))
		_txt(cjk, mid.x + 10.0, mid.y - 8.0, "已交叉确认 · 无威胁", 9, Palette.a(Palette.DIM, 0.95))
		_txt(mono, mid.x + 10.0, mid.y + 5.0, "残骸/反射 · 无威胁", 7, Palette.a(Palette.FAINT, 0.9))
	else:
		var d := 5.0
		draw_polyline(PackedVector2Array([
			mid + Vector2(0, -d), mid + Vector2(d, 0), mid + Vector2(0, d),
			mid + Vector2(-d, 0), mid + Vector2(0, -d)
		]), Palette.a(col, 0.8), 1.0)
		_txt(mono, mid.x + 10.0, mid.y - 20.0, "[9002] 不明接触", 8, Palette.a(col, 0.8))
		_txt(mono, mid.x + 10.0, mid.y - 8.0, "CH-IR2 回波候选 · L1", 8, Palette.a(col, 0.62))
		_txt(mono, mid.x + 10.0, mid.y + 5.0, "待交叉确认", 7, Palette.a(col, 0.4))

# 协方差椭圆（来自 SensorModel.covariance：径向 / 横向 σ，单位 km）
func _draw_covariance(p: Vector2, t: Dictionary, col: Color) -> void:
	var cov: Dictionary = t.get("covariance", {})
	if cov.is_empty():
		return
	var cross := float(cov.get("cross_sigma_km", 0.0))
	var radial := float(cov.get("radial_sigma_km", 0.0))
	if cross <= 0.01 and radial <= 0.01:
		return
	var km := _track_km(t, _tau_now())
	var pxk := _px_per_km(km)
	if pxk <= 1.0e-6:
		return
	var dir3 := km
	if dir3.length() < 1.0:
		dir3 = Vector3(0.0, 1.0, 0.0)
	dir3 = dir3.normalized()
	var q := _p3((km + dir3 * 10.0) * 1000.0)
	var rdir := q - p
	if rdir.length() < 0.001:
		rdir = Vector2(0.0, -1.0)
	else:
		rdir = rdir.normalized()
	var cdir := Vector2(-rdir.y, rdir.x)
	var rx := clampf(radial * pxk, 4.0, 120.0)
	var ry := clampf(cross * pxk, 2.5, 120.0)
	if rx < 1.4 and ry < 1.4:
		return
	var e: Array[Vector2] = []
	for i in range(0, 361, 10):
		var a := deg_to_rad(float(i))
		e.append(p + rdir * (sin(a) * rx) + cdir * (cos(a) * ry))
	_dashed_polyline(e, Palette.a(col, 0.38), 1.0, 3.0)

func _draw_level_badge(p: Vector2, t: Dictionary, col: Color) -> void:
	var lv := _lvl(t)
	if lv <= 0:
		return
	var txt := "L%d" % lv
	draw_rect(Rect2(p.x + 10.0, p.y - 22.0, 17.0, 11.0), Palette.a(col, 0.10))
	draw_rect(Rect2(p.x + 10.0, p.y - 22.0, 17.0, 11.0), Palette.a(col, 0.45), false, 1.0)
	_txt(mono, p.x + 13.0, p.y - 21.0, txt, 7, Palette.a(col, 0.9))

# ── P1j：身份（19 §2.5）——形状 + 颜色双编码 ───────────────
func _ident(t: Dictionary) -> String:
	var v := String(t.get("identity", ""))
	if v != "":
		return v
	var side := String(t.get("side", ""))
	if side == "friend":
		return "friend"
	if side == "hostile":
		return "hostile"
	return "pending"

func _identity_color(kind: String) -> Color:
	match kind:
		"pending":
			return Palette.FAINT
		"unknown":
			return Palette.AMBER
		"assumed_friend":
			return Palette.BLUE
		"friend":
			return Palette.PH
		"neutral":
			return Palette.DIM
		"suspect":
			return Palette.AMBER
		"hostile":
			return Palette.RED
		_:
			return Palette.TXT

func _identity_label(kind: String) -> String:
	if state != null and state.has_method("identity_label"):
		return String(state.call("identity_label", kind))
	return kind

# 身份符号：不只靠颜色（待定虚线框 / 未知菱形 / 假定友好虚线圆 / 友方实心圆 /
# 中立方形 / 可疑三角 / 敌方实心菱形）
func _symbol_at(p: Vector2, kind: String, col: Color, level := 1) -> void:
	match kind:
		"pending":
			var sq: Array[Vector2] = [
				p + Vector2(-5, -5), p + Vector2(5, -5), p + Vector2(5, 5),
				p + Vector2(-5, 5), p + Vector2(-5, -5)
			]
			_dashed_polyline(sq, Palette.a(col, 0.85), 1.0, 3.0)
			_txt(mono, p.x - 2.0, p.y + 3.0, "?", 7, Palette.a(col, 0.9))
		"unknown":
			var dm := PackedVector2Array([
				p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7),
				p + Vector2(-7, 0), p + Vector2(0, -7)
			])
			draw_polyline(dm, Palette.a(col, 0.85), 1.2)
			draw_circle(p, 1.0, Palette.a(col, 0.7))
		"assumed_friend":
			var c: Array[Vector2] = []
			for i in range(0, 25):
				var a := TAU * float(i) / 24.0
				c.append(p + Vector2(cos(a), sin(a)) * 7.0)
			_dashed_polyline(c, Palette.a(col, 0.85), 1.0, 3.0)
			draw_circle(p, 1.2, Palette.a(col, 0.8))
		"friend":
			draw_circle(p, 3.2, col)
			draw_arc(p, 8.0, 0, TAU, 28, Palette.a(col, 0.55), 1.0, true)
			draw_line(p + Vector2(8, 0), p + Vector2(13, 0), Palette.a(col, 0.6), 1.0)
		"neutral":
			draw_rect(Rect2(p - Vector2(5.5, 5.5), Vector2(11, 11)), Palette.a(col, 0.12))
			draw_rect(Rect2(p - Vector2(5.5, 5.5), Vector2(11, 11)), Palette.a(col, 0.85), false, 1.1)
		"suspect":
			var tri := PackedVector2Array([
				p + Vector2(0, -8), p + Vector2(7.5, 5.5), p + Vector2(-7.5, 5.5), p + Vector2(0, -8)
			])
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -8), p + Vector2(7.5, 5.5), p + Vector2(-7.5, 5.5)
			]), Palette.a(col, 0.12))
			draw_polyline(tri, Palette.a(col, 0.9), 1.2)
			draw_circle(p + Vector2(0, 0.5), 1.2, Palette.a(col, 0.85))
		"hostile":
			var d := PackedVector2Array([
				p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7),
				p + Vector2(-7, 0), p + Vector2(0, -7)
			])
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)
			]), Palette.a(col, 0.16))
			draw_polyline(d, col, 1.3, true)
			if level >= 3:
				for q in [Vector2(-12, -12), Vector2(12, -12), Vector2(-12, 12), Vector2(12, 12)]:
					draw_line(p + q, p + q * 0.72, Palette.a(col, 0.55), 1.0)
		_:
			draw_circle(p, 2.5, col)

func _draw_symbol(p: Vector2, t: Dictionary, col: Color) -> void:
	if t.get("ghost", false):
		var g: Array[Vector2] = [
			p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6),
			p + Vector2(-6, 0), p + Vector2(0, -6)
		]
		_dashed_polyline(g, Palette.a(col, 0.55), 1.0, 2.0)
		draw_polyline(PackedVector2Array([p + Vector2(-9, 0), p + Vector2(9, 0)]), Palette.a(col, 0.22), 1.0)
		return
	_symbol_at(p, _ident(t), Palette.a(col, 0.95), int(t.get("level", 1)))

func _is_selected_track(t: Dictionary) -> bool:
	if state == null or state.tracks.is_empty():
		return false
	var idx := clampi(int(state.selected), 0, state.tracks.size() - 1)
	return state.tracks[idx] == t

func _label_free(r: Rect2) -> bool:
	for u in _label_rects:
		if u.intersects(r):
			return false
	return true

func _draw_track_label(t: Dictionary, p: Vector2, col: Color) -> void:
	if not _layer_on("labels"):
		return
	var lv := _lvl(t)
	# P4d：标签碰撞规避。未选中接触只显示一行，选中项展开多行。
	var compact := not _is_selected_track(t)
	var label_w := 190.0 if compact else 250.0
	var label_h := 20.0 if compact else 46.0
	var base_off: Vector2 = t.get("off", Vector2(16, 12))
	var candidates: Array[Vector2] = [
		base_off,
		Vector2(16, 12),
		Vector2(16, -label_h - 8.0),
		Vector2(-label_w - 8.0, 12),
		Vector2(-label_w - 8.0, -label_h - 8.0),
		Vector2(16, label_h + 12.0),
		Vector2(16, -label_h * 2.0 - 4.0),
		Vector2(-label_w - 8.0, label_h + 12.0),
		Vector2(label_w + 24.0, 12),
		Vector2(label_w + 24.0, -label_h - 8.0),
	]
	var chosen := base_off
	var found := false
	for c in candidates:
		var r := Rect2(p + c, Vector2(label_w, label_h)).grow(2.0)
		if r.position.x < 6.0 or r.position.y < 6.0:
			continue
		if r.end.x > size.x - 6.0 or r.end.y > size.y - 6.0:
			continue
		if _label_free(r):
			chosen = c
			found = true
			break
	if not found:
		# 兜底：在点周围搜索 40px 网格，找第一个空白区；最后才退回基准偏移。
		for dy in range(-360, 361, 40):
			for dx in [-300, -220, -140, -60, 60, 140, 220, 300]:
				var c2 := Vector2(float(dx), float(dy))
				var r2 := Rect2(p + c2, Vector2(label_w, label_h)).grow(2.0)
				if r2.position.x < 6.0 or r2.position.y < 6.0 or r2.end.x > size.x - 6.0 or r2.end.y > size.y - 6.0:
					continue
				if _label_free(r2):
					chosen = c2
					found = true
					break
			if found:
				break
		if not found:
			chosen = base_off
	var lr := Rect2(p + chosen, Vector2(label_w, label_h))
	_label_rects.append(lr.grow(2.0))
	var lx := p.x + chosen.x
	var ly := p.y + chosen.y
	if chosen.length() > 40.0:
		draw_line(p, lr.position + Vector2(0, 8), Palette.a(col, 0.22), 1.0, 3.0)
	var dim := 0.55 if t.get("stale", false) else 1.0
	var batch := String(t.get("batch", t.get("id", "")))
	var nm := String(t.get("name", t.get("id", "")))
	var dock_lbl := String(t.get("dock_state", ""))
	if dock_lbl != "":
		nm += (" · 已对接Chronos" if dock_lbl == "docked" else " · 对接Chronos")
	var ident := _identity_label(_ident(t))
	var threat := String(t.get("threat", ""))
	var th_tag := ""
	if threat == "high" or threat == "hostile":
		th_tag = " · 威胁 %s" % String(t.get("threat_label", threat))
	var idf := cjk if Fonts.has_cjk(nm) else mono
	var stale_tag := " · 过期" if t.get("stale", false) else ""
	var rng_label := _fmt_km(float(t.get("obs_range_km", -1.0)) if float(t.get("obs_range_km", -1.0)) >= 0.0 else float(t.get("range", 0.0)))
	var sig := float((t.get("covariance", {}) as Dictionary).get("pos_sigma_km", 0.0))
	match lv:
		2:
			_txt(idf, lx, ly, "[%s] %s" % [batch, nm], 11, Palette.a(col, dim))
			if compact:
				return
			_txt(mono, lx, ly + 12.0, "%s%s · L2 · 方位%03d° 俯仰%+02d° · %s km · σ%.1f%s" % [ident, th_tag, int(t.get("az_deg", t.get("bearing", 0))), int(round(float(t.get("el_deg", 0.0)))), rng_label, sig, stale_tag], 8, Palette.a(col, 0.62 * dim))
		3:
			var cls: Dictionary = t.get("classification", {})
			_txt(idf, lx, ly, "[%s] %s" % [batch, nm], 11, Palette.a(col, dim))
			if compact:
				return
			_txt(cjk, lx, ly + 12.0, "%s%s · L3 · %s · %s · %s" % [ident, th_tag, String(cls.get("ship_class", "—")), String(cls.get("builder", "—")), String(cls.get("faction", "—"))], 8, Palette.a(col, 0.66 * dim))
			_txt(mono, lx, ly + 24.0, "L3 已分类 · %s km%s" % [rng_label, stale_tag], 7, Palette.a(col, 0.45 * dim))
		4:
			var info: Dictionary = t.get("id_info", {})
			var nm4 := String(info.get("name", nm))
			var hull := String(info.get("hull", ""))
			var title := "[%s] %s" % [batch, nm4]
			if hull != "":
				title += " · %s" % hull
			_txt(idf, lx, ly, title, 11, Palette.a(col, dim))
			if compact:
				return
			var iff := String(t.get("iff_status", ""))
			_txt(mono, lx, ly + 12.0, "%s%s · L4 · %s · 敌我识别 %s%s" % [ident, th_tag, String(info.get("faction", "—")), _iff_text(iff), stale_tag], 8, Palette.a(col, 0.66 * dim))
			if iff == "friend" or String(info.get("via", "")) == "datalink":
				draw_line(Vector2(lx, ly + 24.0), Vector2(lx + 4.0, ly + 28.0), Palette.a(Palette.PH, 0.8), 1.0)
				draw_line(Vector2(lx + 4.0, ly + 28.0), Vector2(lx + 11.0, ly + 19.0), Palette.a(Palette.PH, 0.8), 1.0)
				_txt(mono, lx + 14.0, ly + 26.0, "已确认", 7, Palette.a(Palette.PH, 0.5))
			elif iff == "faulty_transponder":
				_txt(cjk, lx, ly + 26.0, "敌我识别：应答机故障", 7, Palette.a(Palette.AMBER, 0.85))
			elif iff != "":
				_txt(cjk, lx, ly + 26.0, "敌我识别：无应答", 7, Palette.a(Palette.AMBER, 0.7))
	_draw_level_badge(p, t, col)

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
	if state.has_method("is_mast_deployed") and not bool(state.call("is_mast_deployed", String(state.rack_ship))):
		_txt(mono, p.x + 16.0, p.y + 34.0, "MAST DOWN · 传感器架不可用", 7, Palette.a(Palette.AMBER, 0.9))
	_txt(cjk, p.x + 16.0, p.y + 8.0, own_name, 11, Palette.PH)
	if dat == "L1":
		_txt(mono, p.x + 16.0, p.y + 21.0, "本舰 · 站位 Meridian-05 / L1", 7, Palette.a(Palette.PH_DIM, 0.9))
	else:
		_txt(mono, p.x + 16.0, p.y + 21.0, "本舰 · 400 km", 7, Palette.a(Palette.PH_DIM, 0.9))

# ── 传感器规则图层（P1c）───────────────────────────────

func _fleet_on(ship: String, model: String) -> bool:
	var m: Dictionary = state.sensor_on.get(ship, {})
	return bool(m.get(model, false))

func _draw_sensor() -> void:
	var o := _o()
	var s: Dictionary = state.active_sensor()
	var typ := String(s.get("type", ""))
	# 1) 被动红外常开：L1 目标已有方位线，这里补脉动端点（仅方位、无距离）
	if _fleet_on("harmattan", "CH-IR2") or _fleet_on("apsis", "MS-IR9"):
		for t in state.tracks:
			if t.get("own", false) or t.get("phantom", false):
				continue
			if _lvl(t) > 1:
				continue
			var b := float(t.get("obs_bearing_deg", t.get("bearing", 0.0)))
			var q := _p3(_world(b, 430.0, 0.0))
			if _ok(q):
				var pulse := 0.5 + 0.5 * sin(_t * 1.6 + b)
				draw_circle(q, 1.6 + pulse * 1.6, Palette.a(Palette.AMBER, 0.45))
	# 2) 主动雷达：开机 → EMIT 暴露状态（视觉效果未建模；不画扇形/示意圆）
	if _fleet_on("harmattan", "YW-R9"):
		_draw_emit_status(o)
	# 3) 光学凝视：进度环（遮蔽/阴影不画）
	for t in state.tracks:
		if t.get("own", false) or t.get("phantom", false):
			continue
		if String(t.get("side", "")) == "friend":
			continue
		if bool(t.get("occluded", false)):
			continue
		var st: Dictionary = t.get("stare", {})
		if st.is_empty():
			continue
		var prog := clampf(float(st.get("progress", 0.0)), 0.0, 1.0)
		if prog <= 0.01:
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		draw_arc(p, 17.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 40, Palette.a(Palette.BLUE, 0.75), 1.5, true)
		draw_arc(p, 17.0, -PI * 0.5, -PI * 0.5 + TAU, 40, Palette.a(Palette.BLUE, 0.14), 1.0, true)
		_txt(mono, p.x + 21.0, p.y - 6.0, "凝视 %.0f/%.0f 秒" % [float(st.get("stare_s", 0.0)), float(st.get("required_s", 0.0))], 7, Palette.a(Palette.BLUE, 0.7))
	# 4) IFF 询问标签（L3+）
	for t in state.tracks:
		if t.get("own", false) or t.get("phantom", false) or _lvl(t) < 3:
			continue
		var p2 := _contact_pos3(t)
		if not _ok(p2):
			continue
		var iff := String(t.get("iff_status", ""))
		var tag := "F" if iff == "friend" else "?"
		var icol := Palette.PH if tag == "F" else Palette.AMBER
		draw_rect(Rect2(p2.x + 9.0, p2.y - 35.0, 12.0, 11.0), Palette.a(icol, 0.10))
		draw_rect(Rect2(p2.x + 9.0, p2.y - 35.0, 12.0, 11.0), Palette.a(icol, 0.5), false, 1.0)
		_txt(mono, p2.x + 11.0, p2.y - 34.0, tag, 7, Palette.a(icol, 0.9))
	# 5) ELINT 点名（对方截获我方发射）
	if bool(state.elint_named):
		_draw_elint_named(o)
	# 6) 选中的通信模块：链路
	if typ == "radio" or typ == "lasercom":
		_draw_comm_links(o)
	_draw_sensor_label(s, typ)

func _layer_label(txt: String, col: Color, sub := "") -> void:
	# P4e：从左上状态块移出，放到光学窗下方，避免与标题/任务块重叠。
	_txt(cjk, size.x - 252.0, 216.0, txt, 8, col)
	if sub != "":
		_txt(mono, size.x - 252.0, 228.0, sub, 7, Palette.a(col, 0.40))

# EMIT 暴露状态：只标真实含义（主动传感器开机 → 可能被对方 ELINT 截获）；
# 截获半径/扫描范围未建模，不画示意圆或扇形。
func _draw_emit_status(o: Vector2) -> void:
	var ems: Array = state.emission.get("emitters", [])
	var s := "EMIT 暴露 · 主动传感器开机"
	if bool(state.elint_named):
		s = "EMIT 暴露 · 已被 ELINT 截获"
	if not ems.is_empty():
		var best: Dictionary = ems[0]
		for raw in ems:
			var e: Dictionary = raw
			if float(e.get("weight", 0.0)) > float(best.get("weight", 0.0)):
				best = e
		s += " · %s（%s）" % [String(best.get("model", "")), String(best.get("owner", "")).to_upper()]
	_txt(mono, o.x - 150.0, o.y - 22.0, s, 7, Palette.a(Palette.AMBER, 0.85))
	_txt(mono, o.x - 150.0, o.y - 10.0, "截获半径/扫描范围未建模（第二批 TWS）", 7, Palette.a(Palette.FAINT, 0.75))

# 敌方 ELINT 点名：从传唤级指向本舰的虚线 + 截获环
func _draw_elint_named(o: Vector2) -> void:
	var hostile: Dictionary = state.track_by_id("2001")
	var from := o
	if not hostile.is_empty() and _lvl(hostile) >= 2:
		from = _contact_pos3(hostile)
	else:
		var b := float(hostile.get("bearing", 41.0)) if not hostile.is_empty() else 41.0
		from = _p3(_world(b, 430.0, 0.0))
	if not _ok(from):
		return
	draw_dashed_line(from, o, Palette.a(Palette.RED, 0.30), 1.0, 6.0)
	_txt(mono, o.x + 14.0, o.y + 34.0, "ELINT 截获我方发射（示意连线，范围未建模）", 7, Palette.a(Palette.RED, 0.75))

func _draw_comm_links(o: Vector2) -> void:
	for t in state.tracks:
		if t.get("own", false) or String(t.get("side", "")) != "friend":
			continue
		var p := _contact_pos3(t)
		if not _ok(p):
			continue
		draw_dashed_line(o, p, Palette.a(Palette.PH_DIM, 0.30), 1.0, 5.0)
	# 链路文字在左上图层说明里（Y 轴命令/点火标签密集，避免压字）

func _draw_sensor_label(s: Dictionary, typ: String) -> void:
	var model := String(s.get("model", "—"))
	var mast_ok := true
	if state.has_method("is_mast_deployed"):
		mast_ok = bool(state.call("is_mast_deployed", String(state.rack_ship)))
	var mode := String(s.get("mode", typ))
	var src := String(s.get("source", "—"))
	var col := Palette.PH
	var sub := ""
	match typ:
		"ir":
			col = Palette.AMBER
			sub = "红外 · 被动 · L1 方位线 · 无距离"
		"radar":
			sub = "主动 · L2 距离+方位 · 开机暴露风险"
		"optical":
			col = Palette.BLUE
			sub = "可见光 · 凝视 → L3 分类 · 阴影环境无效"
		"iff":
			sub = "敌我识别（IFF）→ L4 · 身份判断"
		"elint":
			col = Palette.AMBER
			sub = "被动"
		"radio", "lasercom":
			col = Palette.DIM
			sub = "链路 · 激光直连 > 激光中继 > 红外 > 无线电（鲁棒/全向）> 可见光"
	if not mast_ok:
		sub = "桅杆收起 · 传感器架不可用（先伸出桅杆）"
	_layer_label("%s / %s · %s" % [model, mode, src], col, sub)

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
	_txt(mono, size.x * 0.5 - 52.0, 88.0, "地月空间 / CISLUNAR", 8, Palette.a(Palette.PH, 0.42))
	# 太阳方向：只做刻度，不画光照
	var sx := 16.0
	var sy := size.y - 74.0
	draw_circle(Vector2(sx + 5.0, sy + 3.0), 2.2, Palette.a(Palette.AMBER, 0.55))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(sx + 5.0, sy + 3.0) + Vector2(cos(a), sin(a)) * 4.0, Vector2(sx + 5.0, sy + 3.0) + Vector2(cos(a), sin(a)) * 6.5, Palette.a(Palette.AMBER, 0.35), 1.0)
	_txt(mono, sx + 16.0, sy, "太阳 SUN 312° · 光照", 7, Palette.a(Palette.AMBER, 0.50))

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
	_txt(mono, lp.x + 6.0, lp.y, "转移轨道 / TRANSFER ORBIT", 7, Palette.a(Palette.PH, 0.30))
	# 月球轨道标签：取一个落在画面内、且不压住中心区域的轨道点
	var labelled := false
	var oo := _o()
	for i in range(0, 181, 2):
		var a := TAU * float(i) / 180.0
		var q := _p2(Vector3(earth.x + cos(a) * EARTH_MOON_KM, earth.y + sin(a) * EARTH_MOON_KM, 0.0))
		if not labelled and q.x > 60.0 and q.x < size.x - 380.0 and q.y > 120.0 and q.y < size.y - 130.0 and q.distance_to(oo) > 130.0:
			_txt(mono, q.x + 4.0, q.y - 4.0, "月球轨道 · 384,400 km", 7, Palette.a(Palette.DIM, 0.55))
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
		_txt(mono, 24.0, 124.0, "L1 基准 · 地月双体", 8, Palette.a(Palette.PH, 0.65))
		_txt(mono, 24.0, 136.0, "站点 Meridian-05 Chronos / 无天体弧", 7, Palette.a(Palette.FAINT, 0.9))
		# L1 拉格朗日点标记：在站点上方标一个菱形
		var o := _o()
		var lp := o + Vector2(0.0, -88.0)
		draw_polyline(PackedVector2Array([
			lp + Vector2(0, -5), lp + Vector2(5, 0), lp + Vector2(0, 5),
			lp + Vector2(-5, 0), lp + Vector2(0, -5)
		]), Palette.a(Palette.PH, 0.55), 1.0)
		_txt(mono, lp.x + 10.0, lp.y - 4.0, "L1 · Meridian-05 · Chronos", 8, Palette.a(Palette.PH, 0.75))
		_txt(mono, lp.x + 10.0, lp.y + 8.0, "站点基准 / STATION FRAME · 地月双体", 7, Palette.a(Palette.FAINT, 0.8))

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

func _draw_planar_contact_title(t: Dictionary) -> String:
	var lv := _lvl(t)
	var batch := String(t.get("batch", t.get("id", "")))
	var nm := String(t.get("name", t.get("id", "")))
	var dock_lbl := String(t.get("dock_state", ""))
	if dock_lbl != "":
		nm += (" · 已对接Chronos" if dock_lbl == "docked" else " · 对接Chronos")
	var ident := _identity_label(_ident(t))
	if lv <= 1:
		return "[%s] %s · %s · L1 仅方位" % [batch, nm, ident]
	if lv == 2:
		return "[%s] %s · %s · L2" % [batch, nm, ident]
	if lv == 3:
		var cls: Dictionary = t.get("classification", {})
		return "[%s] %s · %s · L3" % [batch, nm, String(cls.get("ship_class", ident))]
	var info: Dictionary = t.get("id_info", {})
	return "[%s] %s · %s · L4" % [batch, String(info.get("name", nm)), ident]

func _draw_planar_contacts() -> void:
	var o := _o()
	var cluster: Array[Dictionary] = []
	var friends := 0
	var total := 0
	var lv_counts := [0, 0, 0, 0, 0]
	for t in state.tracks:
		if t.get("own", false):
			continue
		total += 1
		if bool(t.get("occluded", false)):
			continue
		if bool(t.get("phantom", false)):
			lv_counts[1] += 1
			_draw_planar_phantom(o, t)
			continue
		var lvl := _lvl(t)
		lv_counts[lvl] += 1
		var km := _track_km(t, _tau_now())
		var pos := _p2(km)
		var col := _side_color(t)
		if lvl <= 1:
			# L1 仅方位：方位线端点用 _p2 地图坐标（随 yaw/zoom 旋转缩放）
			var b := deg_to_rad(float(t.get("obs_bearing_deg", t.get("bearing", 0.0))))
			var far_km := Vector3(sin(b), cos(b), 0.0) * 450.0
			var p_end := _p2(far_km)
			var p_a := _p2(Vector3(sin(b - deg_to_rad(1.2)), cos(b - deg_to_rad(1.2)), 0.0) * 450.0)
			var p_b := _p2(Vector3(sin(b + deg_to_rad(1.2)), cos(b + deg_to_rad(1.2)), 0.0) * 450.0)
			if _ok(p_end) and _ok(p_a) and _ok(p_b):
				draw_colored_polygon(PackedVector2Array([o, p_a, p_b]), Palette.a(col, 0.025))
				draw_dashed_line(o, p_a, Palette.a(col, 0.26), 1.0, 4.0)
				draw_dashed_line(o, p_b, Palette.a(col, 0.26), 1.0, 4.0)
				_draw_symbol(p_end, t, col)
			cluster.append({"t": t, "col": col, "lvl": lvl, "pos": p_end})
			continue
		if pos.distance_to(o) < 26.0:
			if t.side == "friend":
				friends += 1
			else:
				cluster.append({"t": t, "col": col, "lvl": lvl, "pos": pos})
		else:
			_draw_symbol(pos, t, col)
			_draw_planar_contact_label(t, pos, col)
	# 战略尺度上近场接触：编队框按接触的 _p2 地图坐标外接，随 yaw/zoom 移动
	var frame := Rect2()
	if cluster.size() > 0:
		var minp := Vector2(1.0e9, 1.0e9)
		var maxp := Vector2(-1.0e9, -1.0e9)
		for it in cluster:
			var pp: Vector2 = it.get("pos", o)
			minp = Vector2(minf(minp.x, pp.x), minf(minp.y, pp.y))
			maxp = Vector2(maxf(maxp.x, pp.x), maxf(maxp.y, pp.y))
		frame = Rect2(minp - Vector2(14, 14), (maxp - minp) + Vector2(28, 28))
		if frame.size.x < 44.0:
			frame = Rect2(frame.get_center() - Vector2(22, frame.size.y * 0.5), Vector2(44.0, frame.size.y))
		if frame.size.y < 44.0:
			frame = Rect2(frame.get_center() - Vector2(frame.size.x * 0.5, 22), Vector2(frame.size.x, 44.0))
		draw_rect(frame, Palette.a(Palette.PH, 0.30), false, 1.0)
	else:
		draw_rect(Rect2(o - Vector2(22, 22), Vector2(44, 44)), Palette.a(Palette.PH, 0.30), false, 1.0)
	_txt(mono, o.x - 150.0, o.y + 58.0, "LOCAL ×%d · L4 %d/L3 %d/L2 %d/L1 %d" % [
		total, lv_counts[4], lv_counts[3], lv_counts[2], lv_counts[1]], 7, Palette.a(Palette.PH, 0.70))
	if cluster.size() > 0:
		var fan := [-158.0, -110.0, 165.0, -134.0, 148.0, -178.0]
		for i in range(cluster.size()):
			var it: Dictionary = cluster[i]
			var tt: Dictionary = it["t"]
			var c: Color = it["col"]
			var pos_m: Vector2 = it.get("pos", o)
			_draw_symbol(pos_m, tt, c)
			var ang := deg_to_rad(float(fan[i % fan.size()]))
			var dir := Vector2(cos(ang), sin(ang))
			var q := frame.get_center() + dir * (maxf(frame.size.x, frame.size.y) * 0.5 + 34.0 + float(i) * 22.0)
			draw_line(pos_m, q, Palette.a(c, 0.35), 1.0)
			var title := _draw_planar_contact_title(tt)
			var idf := cjk if Fonts.has_cjk(title) else mono
			if cos(ang) < -0.2:
				_txt_r(idf, q.x - 8.0, q.y + 2.0, title, 8, Palette.a(c, 0.9))
			else:
				_txt(idf, q.x + 8.0, q.y + 2.0, title, 8, Palette.a(c, 0.9))

func _draw_planar_contact_label(t: Dictionary, pos: Vector2, col: Color) -> void:
	var title := _draw_planar_contact_title(t)
	var dock_state := String(t.get("dock_state", ""))
	if dock_state != "":
		title += " · 对接Chronos"
		if dock_state == "docked":
			title += "（已对接）"
	var idf := cjk if Fonts.has_cjk(title) else mono
	_txt(idf, pos.x + 7.0, pos.y + 2.0, title, 8, Palette.a(col, 0.9))
	var lv := _lvl(t)
	if lv == 4:
		var ident: Dictionary = t.get("identity", {})
		var hull := String(ident.get("hull", ""))
		if hull != "":
			_txt(mono, pos.x + 7.0, pos.y + 13.0, "#" + hull, 7, Palette.a(col, 0.55))

func _draw_planar_phantom(o: Vector2, t: Dictionary) -> void:
	var resolved := bool(t.get("false_alarm", false))
	var col := Palette.FAINT if resolved else Palette.AMBER
	var b := deg_to_rad(float(state.phantom_bearing))
	var end := _p2(Vector3(sin(b), cos(b), 0.0) * 315.0)
	draw_dashed_line(o, end, Palette.a(col, 0.35), 1.0, 5.0)
	draw_rect(Rect2(end - Vector2(4, 4), Vector2(8, 8)), Palette.a(col, 0.8), false, 1.0)
	_txt_r(mono, end.x - 5.0, end.y - 3.0, "[9002] 不明接触", 7, Palette.a(col, 0.85))
	if resolved:
		_txt_r(cjk, end.x - 5.0, end.y + 10.0, "无威胁目标 · 已交叉确认", 8, Palette.a(Palette.FAINT, 0.85))

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
	_txt(mono, o.x + 20.0, o.y + 79.0, "本舰 · 旗舰 · 中心锁定", 7, Palette.a(Palette.PH, 0.55))

func _draw_planar_sensor() -> void:
	var o := _o()
	# EMIT：真实比例暴露环（ELINT 截获距离 × 平面比例尺）
	if bool(state.emission.get("exposed", false)):
		var ems: Array = state.emission.get("emitters", [])
		if not ems.is_empty():
			var best: Dictionary = ems[0]
			for raw in ems:
				var e: Dictionary = raw
				if float(e.get("weight", 0.0)) > float(best.get("weight", 0.0)):
					best = e
			var rr := float(best.get("elint_range_km", 0.0)) * _planar_scale
			if rr > 6.0 and rr < size.x:
				draw_arc(o, rr, 0, TAU, 96, Palette.a(Palette.AMBER, 0.22), 1.0, true)
				_txt(mono, o.x + rr * 0.72, o.y - rr * 0.72, "EMIT 暴露 · 对方 ELINT 截获半径 %s km（按比例）" % _fmt_km(float(best.get("elint_range_km", 0.0))), 7, Palette.a(Palette.AMBER, 0.7))
	# ELINT 点名：从传唤级指向本舰
	if bool(state.elint_named):
		var hostile: Dictionary = state.track_by_id("2001")
		var from := o
		if not hostile.is_empty():
			var km := _track_km(hostile, _tau_now())
			from = _p2(km)
			if from.distance_to(o) < 6.0:
				var b := deg_to_rad(float(hostile.get("bearing", 41.0)))
				from = o + Vector2(sin(b), -cos(b)) * 34.0
		draw_dashed_line(from, o, Palette.a(Palette.RED, 0.35), 1.0, 6.0)
		# 不再写“通信截听点名”文字：只保留连线，减少信息量。
	# 当前选中模块的标签（架来自选中舰，显示在左上）
	var s: Dictionary = state.active_sensor()
	if not s.is_empty():
		_layer_label("%s / %s · %s" % [String(s.get("model", "—")), String(s.get("mode", "")), String(s.get("source", ""))], Palette.PH, "舰队融合 · 1 Hz · L1 方位线在局部图外圈")

func _inset_pts(pts: Array, c: Vector2, sc: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in pts:
		var v: Vector3 = p
		out.append(c + Vector2(v.x, -v.y) * sc)
	return out

func _draw_planar_inset() -> void:
	var r := Rect2(size.x - 316.0, 60.0, 300.0, 214.0)
	draw_rect(r, Palette.a(Palette.PANEL, 0.85))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)
	_txt(cjk, r.position.x + 8.0, r.position.y + 5.0, "局部 / LOCAL PATCH", 7, Palette.a(Palette.PH, 0.8))
	_txt_r(mono, r.end.x - 8.0, r.position.y + 5.0, "预测 +300 s · ×0.10 px/km", 7, Palette.a(Palette.PH, 0.55))
	var c := r.position + Vector2(150.0, 104.0)
	var sc := 0.100
	# 局部小图：100/200/400 km 参考环（真实距离标尺，不是雷达范围）
	for rr in [100.0, 200.0, 400.0]:
		draw_arc(c, rr * sc, 0, TAU, 64, Palette.a(Palette.GRID, 0.9 if rr < 400.0 else 0.6), 1.0, true)
	_txt(mono, r.position.x + 8.0, r.position.y + 197.0, "参考环 100/200/400 km", 7, Palette.a(Palette.FAINT, 0.75))
	for bb in range(0, 360, 30):
		var d := Vector2(sin(deg_to_rad(float(bb))), -cos(deg_to_rad(float(bb))))
		draw_line(c + d * 4.0, c + d * 6.0, Palette.a(Palette.GRID, 0.6), 1.0)
	var tau := _tau_now()
	# 历史 / 预测（战略图上看不见的 300 s 位移，在局部小图里可见；仅 L2+ 有位置才画）
	for t in state.tracks:
		if t.get("own", false) or bool(t.get("occluded", false)):
			continue
		if bool(t.get("phantom", false)):
			var b := deg_to_rad(float(state.phantom_bearing))
			draw_dashed_line(c, c + Vector2(sin(b), -cos(b)) * 62.0, Palette.a(Palette.FAINT, 0.30), 1.0, 4.0)
			_txt(mono, c.x + sin(b) * 62.0 + 3.0, c.y - cos(b) * 62.0, "不明接触", 7, Palette.a(Palette.FAINT, 0.8))
			continue
		if _lvl(t) < 2:
			continue
		var data := _pred_data(t)
		var col := _side_color(t)
		_dashed_polyline(_inset_pts(data["hist"]["pts"], c, sc), Palette.a(col, 0.16), 1.0, 2.0)
		_dashed_polyline(_inset_pts(data["pred"]["pts"], c, sc), Palette.a(col, 0.45), 1.0, 3.0)
		var km := _track_km(t, tau)
		var q := c + Vector2(km.x, -km.y) * sc
		_draw_symbol(q, t, col)
	# 预测刻度：+60/+120/+300 的采样点
	for tick in PRED_TICKS:
		for t in state.tracks:
			if t.get("own", false) or bool(t.get("phantom", false)) or bool(t.get("occluded", false)):
				continue
			if _lvl(t) < 2:
				continue
			var km2 := _track_km(t, tau + float(tick))
			var q2 := c + Vector2(km2.x, -km2.y) * sc
			if not r.grow(-4.0).has_point(q2):
				continue
			draw_circle(q2, 1.2, Palette.a(_side_color(t), 0.65))
	# 本舰点火计划（P1d：命令模型 plan，含 PENDING BURN）
	var plan := _own_plan_data()
	_dashed_polyline(_inset_pts(plan["pts"], c, sc), Palette.a(Palette.PH, 0.65), 1.0, 3.0)
	for raw in plan["events"]:
		var ev: Dictionary = raw
		var ekm: Vector3 = ev.get("km", Vector3.ZERO)
		var eq := c + Vector2(ekm.x, -ekm.y) * sc
		if r.grow(-4.0).has_point(eq):
			draw_circle(eq, 2.0, Palette.a(Palette.AMBER, 0.8))
	for raw in state.own_events:
		var ev2: Dictionary = raw
		var et := float(ev2.get("t", 0.0))
		if et > tau:
			continue
		var st: Dictionary = state.own_at(et)
		var cur: Dictionary = state.own_at(tau)
		var ekm2 := (st["r"] as Vector3) - (cur["r"] as Vector3)
		var eq2 := c + Vector2(ekm2.x, -ekm2.y) * sc
		if r.grow(-4.0).has_point(eq2):
			draw_circle(eq2, 1.8, Palette.a(Palette.PH, 0.9))
	# 旧节点 B-2 标记
	var node_idx := int(round(120.0 / PRED_HORIZON * float(PRED_STEPS)))
	var ppt: Array = plan["pts"]
	if node_idx >= 0 and node_idx < ppt.size():
		var np3: Vector3 = ppt[node_idx]
		var nq := c + Vector2(np3.x, -np3.y) * sc
		draw_polyline(PackedVector2Array([
			nq + Vector2(0, -3), nq + Vector2(3, 0), nq + Vector2(0, 3), nq + Vector2(-3, 0), nq + Vector2(0, -3)
		]), Palette.a(Palette.PH, 0.85), 1.0)
	draw_circle(c, 1.6, Palette.PH)
	draw_arc(c, 5.0, 0, TAU, 20, Palette.a(Palette.PH, 0.6), 1.0, true)
	_txt(mono, r.position.x + 8.0, r.end.y - 22.0, "历史 -60 s · 预测 +300 s", 7, Palette.a(Palette.FAINT, 0.8))
	_txt(mono, r.position.x + 8.0, r.end.y - 10.0, "%s / Chronos · 3D→ORTHO" % String(state.datum), 7, Palette.a(Palette.PH, 0.55))

# ── 界面装饰 ────────────────────────────────────────────

func _draw_chrome() -> void:
	if ortho:
		_chrome_planar()
	else:
		_chrome_3d()
	_draw_compass()
	if not ortho:
		_draw_optical()

# ── P2b：取证/撤人任务进度 + Chronos 任务标记 ───────────
func _draw_tasks() -> void:
	var raw_tasks = state.get("evidence_tasks")
	var tasks: Array = raw_tasks if raw_tasks is Array else []
	var raw_ev = state.get("evidence")
	var ev: Dictionary = raw_ev if raw_ev is Dictionary else {}
	var cnt := 0
	for k in ev.keys():
		if bool(ev[k]):
			cnt += 1
	var expose_ok := false
	if state != null and state.has_method("can_expose"):
		expose_ok = bool(state.call("can_expose"))
	var head_col := Palette.PH_DIM if expose_ok else Palette.AMBER
	_txt(cjk, 16.0, 150.0, "任务 / TASK · EXPOSE 收集证据 %d/3" % cnt, 7, Palette.a(head_col, 0.95))
	_txt(mono, 16.0, 162.0, "EXPOSE 需 ≥2 项 · 穿梭机同时只可执行一项", 7, Palette.a(Palette.FAINT, 0.9))
	var y := 176.0
	for raw in tasks:
		var tk: Dictionary = raw
		var st := String(tk.get("status", ""))
		var prog := clampf(float(tk.get("progress", 0.0)), 0.0, 1.0)
		var col := Palette.PH_DIM if st == "DONE" else Palette.AMBER
		_txt(mono, 16.0, y, "%s · %s · %d%%" % [String(tk.get("label", "")), "完成" if st == "DONE" else "进行中", int(round(prog * 100.0))], 7, Palette.a(col, 0.92))
		draw_rect(Rect2(16.0, y + 3.0, 128.0, 2.0), Palette.a(col, 0.22))
		draw_rect(Rect2(16.0, y + 3.0, 128.0 * prog, 2.0), Palette.a(col, 0.85))
		y += 16.0
	# Chronos 任务标记（固定方位，仅作现场参照）
	var cp := _p3(_world(250.0, 240.0, 0.0))
	if _ok(cp):
		draw_polyline(PackedVector2Array([
			cp + Vector2(0, -5), cp + Vector2(5, 0), cp + Vector2(0, 5),
			cp + Vector2(-5, 0), cp + Vector2(0, -5)
		]), Palette.a(Palette.AMBER, 0.55), 1.0)
		_txt(cjk, cp.x + 8.0, cp.y + 15.0, "Chronos · L1-05", 7, Palette.a(Palette.AMBER, 0.75))
	# 运行中的穿梭机 / 哈马丹取证标记
	for raw2 in tasks:
		var tk2: Dictionary = raw2
		if String(tk2.get("status", "")) != "RUNNING":
			continue
		var shuttle := bool(tk2.get("shuttle", false))
		var prog2 := clampf(float(tk2.get("progress", 0.0)), 0.0, 1.0)
		var dist := 60.0 + 80.0 * (1.0 - absf(prog2 * 2.0 - 1.0))
		var p := _p3(_world(250.0, dist, 8.0))
		if not _ok(p):
			continue
		var c := Palette.BLUE if shuttle else Palette.AMBER
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -5), p + Vector2(5, 4), p + Vector2(-5, 4)
		]), Palette.a(c, 0.85))
		_txt(mono, p.x + 8.0, p.y + 2.0, ("穿梭机 · " if shuttle else "哈马丹 · ") + String(tk2.get("label", "")), 7, Palette.a(c, 0.8))

func _chrome_3d() -> void:
	# P6b：回到终端行排版；层级靠字号/颜色/标签/分隔线，不靠表格式状态块。
	var x0 := 16.0
	_txt(cjk, x0, 20.0, "战术态势", 14, Palette.PH)
	_txt(mono, x0, 38.0, "TACTICAL PLOT · L1 MERIDIAN-05", 8, Palette.DIM)
	draw_line(Vector2(x0, 50.0), Vector2(x0 + 340.0, 50.0), Palette.a(Palette.LINE, 0.55), 1.0)
	var vx := x0 + 58.0
	# FRAME：基准/视图/距离，静态结构 + 动态距离。
	_txt(mono, x0, 58.0, "FRAME", 7, Palette.FAINT)
	_txt(mono, vx, 58.0, "%s · 3D LVLH · ±400 km · DIST %s km" % [String(state.datum), _fmt_km(dist / 1000.0)], 7, Palette.a(Palette.PH, 0.80))
	# CLOCK：T+ / 窗口 / 锁定 / LIVE；数值用琥珀色。
	_txt(mono, x0, 74.0, "CLOCK", 7, Palette.FAINT)
	_txt(mono, vx, 74.0, "T+%s · WINDOW %s · 1×" % [_hms(_tau_now()), _hms(state.exec_left)], 7, Palette.a(Palette.AMBER, 0.86))
	var live_col: Color = Palette.a(Palette.PH, 0.95) if not state.paused else Palette.a(Palette.AMBER, 0.95)
	var blink := 0.45 + 0.55 * absf(sin(_t * 3.2))
	draw_circle(Vector2(x0 + 342.0, 77.0), 2.0, Palette.a(live_col, blink))
	_txt(mono, x0 + 350.0, 74.0, "LIVE" if not state.paused else "PAUSED", 7, live_col)
	# SENSOR：当前传感器架/模式；随选中模块变化。
	_txt(mono, x0, 90.0, "SENSOR", 7, Palette.FAINT)
	_txt(mono, vx, 90.0, String(state.sensor_note).substr(0, 38), 7, Palette.a(Palette.PH, 0.72))
	# TASK：EXPOSE 进度 / 当前穿梭机任务；琥珀色为动作态。
	var tasks: Array = state.evidence_tasks if state.evidence_tasks is Array else []
	var task_s := "穿梭机待命"
	for raw in tasks:
		var tk: Dictionary = raw
		if String(tk.get("status", "")) == "RUNNING":
			task_s = "%s %d%%" % [String(tk.get("label", "任务")), int(round(float(tk.get("progress", 0.0)) * 100.0))]
			break
	var ev_n := int(state.evidence_count()) if state.has_method("evidence_count") else 0
	var task_col: Color = Palette.a(Palette.AMBER, 0.88) if task_s != "穿梭机待命" else Palette.a(Palette.PH_DIM, 0.85)
	_txt(mono, x0, 106.0, "TASK", 7, Palette.FAINT)
	_txt(cjk, vx, 106.0, "EXPOSE %d/3 · %s" % [ev_n, task_s], 7, task_col)
	# 取证明细：一行，作为状态补充；不重复任务块。
	var ev: Dictionary = state.evidence if state.evidence is Dictionary else {}
	var bits: Array[String] = []
	if bool(ev.get("port_telemetry", false)): bits.append("TEL")
	if bool(ev.get("inspection_blackbox", false)): bits.append("REC")
	if bool(ev.get("elint_signature", false)): bits.append("ELINT")
	if bits.size() > 0:
		_txt(mono, x0, 122.0, "EVIDENCE  " + " / ".join(bits), 7, Palette.a(Palette.PH, 0.55))
	# P9a：选中舰三维方位 + 相对轨道读数；基准锁本舰（选中舰只读）
	# 放右侧（光学窗/命令队列下方），避开左侧 HUD 覆盖层与任务面板
	var si: Dictionary = state.selected_info() if state.has_method("selected_info") else {}
	if not si.is_empty():
		var sx := size.x - 252.0
		var sy := 384.0
		draw_rect(Rect2(sx - 6.0, sy - 14.0, 244.0, 62.0), Palette.a(Palette.PANEL, 0.62))
		_txt(cjk, sx, sy, "[%s] %s · %s · 威胁 %s" % [String(si.get("batch", "")), String(si.get("name", "")), String(si.get("identity", "")), String(si.get("threat", ""))], 8, Palette.a(Palette.PH, 0.92))
		_txt(mono, sx, sy + 13.0, "AZ %03d°  EL %+02d°  RNG %s km" % [int(round(float(si.get("az_deg", 0.0)))), int(round(float(si.get("el_deg", 0.0)))), _fmt_km(float(si.get("range_km", 0.0)))], 7, Palette.a(Palette.PH, 0.72))
		_txt(mono, sx, sy + 26.0, "Vc %+.0f m/s · 视向速度" % float(si.get("closing_mps", 0.0)), 7, Palette.a(Palette.PH_DIM, 0.8))
		var oi: Dictionary = si.get("orbit", {})
		if bool(oi.get("available", false)):
			_txt(mono, sx, sy + 39.0, "相对轨道 a≈%s km · T≈%s · i≈%.1f°" % [_fmt_km(float(oi.get("semi_major_km", 0.0))), _hms(float(oi.get("period_s", 0.0))), float(oi.get("inc_deg", 0.0))], 7, Palette.a(Palette.PH, 0.60))
		else:
			_txt(mono, sx, sy + 39.0, String(oi.get("note", "无轨道解")), 7, Palette.a(Palette.FAINT, 0.8))
		_txt(mono, size.x - 24.0, sy + 56.0, String(state.datum_note()) if state.has_method("datum_note") else String(state.datum), 7, Palette.a(Palette.PH_DIM, 0.75))
	_draw_legend()
	_txt_r(mono, size.x - 24.0, size.y - 116.0, String(state.cmd_note), 7, Palette.a(Palette.AMBER, 0.85))
	_txt_r(mono, size.x - 24.0, size.y - 104.0, "1 保持站位 STATION · 2 跟踪 SHADOW · 3 点火 BURN · 4 撤销", 7, Palette.a(Palette.PH, 0.65))
	_txt_r(mono, size.x - 24.0, size.y - 92.0, "历元 T0+%06.1fs · 预测 %d 点" % [_tau_now(), PRED_STEPS + 1], 7, Palette.a(Palette.PH_FAINT, 0.9))
	_txt_r(mono, size.x - 16.0, size.y - 14.0, "拖动：横=Yaw / 竖=Pitch · 滚轮缩放 · R 翻转 · D 基准 · Q/E 横滚 · F10 无边框 · F11 独占全屏", 7, Palette.a(Palette.FAINT, 0.75))

func _chrome_planar() -> void:
	_txt(cjk, 16.0, 10.0, "压平态势", 14, Palette.PH)
	_txt(mono, 16.0, 29.0, "PLANAR CHART / CENTER OWN", 8, Palette.DIM)
	_txt(cjk, 16.0, 41.0, "ORTHOGRAPHIC · GRID 50,000 km", 8, Palette.FAINT)
	_txt(mono, 16.0, 53.0, "DATUM %s · PLANAR ×%.2f" % [String(state.datum), planar_zoom], 8, Palette.a(Palette.PH, 0.75))
	_txt(mono, 16.0, 65.0, "执行窗口 %s · 1× 锁" % _hms(state.exec_left), 7, Palette.a(Palette.AMBER, 0.70))
	_txt(mono, 16.0, 77.0, String(state.sensor_note), 7, Palette.a(Palette.PH, 0.80))
	_txt(mono, 16.0, 89.0, "传感器架 %s · 融合 1 Hz · 等级由证据时间戳决定" % String(state.rack_ship).to_upper(), 7, Palette.a(Palette.PH_FAINT, 0.95))
	if state.has_method("selected_info"):
		var si2: Dictionary = state.selected_info()
		if not si2.is_empty():
			var px2 := size.x - 316.0
			var py2 := 288.0
			draw_rect(Rect2(px2 - 6.0, py2 - 14.0, 300.0, 56.0), Palette.a(Palette.PANEL, 0.62))
			_txt(mono, px2, py2, "选中 [%s] %s" % [String(si2.get("batch", "")), String(si2.get("name", ""))], 8, Palette.a(Palette.PH, 0.9))
			_txt(mono, px2, py2 + 13.0, "AZ %03d°  EL %+02d°  RNG %s km" % [int(round(float(si2.get("az_deg", 0.0)))), int(round(float(si2.get("el_deg", 0.0)))), _fmt_km(float(si2.get("range_km", 0.0)))], 7, Palette.a(Palette.PH, 0.7))
			if state.has_method("datum_note"):
				_txt(mono, px2, py2 + 26.0, String(state.datum_note()), 7, Palette.a(Palette.PH_DIM, 0.78))
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
	_txt_r(mono, size.x - 16.0, size.y - 104.0, String(state.cmd_note), 7, Palette.a(Palette.AMBER, 0.85))
	_txt(mono, size.x - 16.0, size.y - 14.0, "拖动旋转 · 滚轮缩放 · R 翻转 · D 基准 · Z 横滚锁 · Q/E 横滚", 7, Palette.a(Palette.FAINT, 0.75))

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
	_txt(cjk, 16.0, 648.0, "图例 / LEGEND · 身份 / IDENTITY", 7, Palette.a(Palette.FAINT, 0.9))
	_txt(mono, 424.0, 648.0, "威胁：待判定 · 无威胁 · 低 · 中 · 高 · 敌对", 7, Palette.a(Palette.PH_DIM, 0.9))
	var row1 := [["pending", "待定"], ["unknown", "未知"], ["assumed_friend", "假定友好"], ["friend", "友方"]]
	var row2 := [["neutral", "中立"], ["suspect", "可疑"], ["hostile", "敌方"]]
	var x := 22.0
	for it in row1:
		_symbol_at(Vector2(x, 666.0), String(it[0]), _identity_color(String(it[0])), 1)
		_txt(cjk, x + 13.0, 669.0, String(it[1]), 7, Palette.DIM)
		x += 108.0
	x = 22.0
	for it in row2:
		_symbol_at(Vector2(x, 684.0), String(it[0]), _identity_color(String(it[0])), 1)
		_txt(cjk, x + 13.0, 687.0, String(it[1]), 7, Palette.DIM)
		x += 108.0
	draw_rect(Rect2(Vector2(x - 2.0, 679.0), Vector2(8, 8)), Palette.a(Palette.FAINT, 0.85), false, 1.0)
	draw_line(Vector2(x - 3.0, 678.0), Vector2(x + 7.0, 690.0), Palette.a(Palette.FAINT, 0.65), 1.0)
	_txt(cjk, x + 13.0, 687.0, "无威胁", 7, Palette.DIM)
	var y2 := 704.0
	draw_line(Vector2(16, y2 + 5), Vector2(34, y2 + 5), Palette.a(Palette.PH_DIM, 0.55), 1.0)
	_txt(cjk, 40.0, y2, "历史", 7, Palette.DIM)
	draw_dashed_line(Vector2(82, y2 + 5), Vector2(100, y2 + 5), Palette.a(Palette.PH, 0.8), 1.0, 4.0)
	_txt(cjk, 106.0, y2, "预测", 7, Palette.DIM)
	draw_dashed_line(Vector2(148, y2 + 5), Vector2(166, y2 + 5), Palette.a(Palette.PH, 0.35), 1.0, 2.0)
	_txt(cjk, 172.0, y2, "1σ 误差", 7, Palette.DIM)
	_txt(mono, 16.0, 720.0, "航迹：批号 · L1 方位线 · L2 定位+协方差 · L3 分类 · L4 舰名/敌我识别", 7, Palette.a(Palette.PH, 0.65))
	_txt(mono, 16.0, 734.0, "T+60/120/300 = 预测刻度 · 辐射 = 主动传感器开机即暴露（截获半径未建模） · LINK DEGRADED", 7, Palette.a(Palette.PH_FAINT, 0.95))
	_txt(mono, 16.0, 748.0, "标记三层：身份（符号）· L级（L1–L4 识别等级）· 威胁（处置优先级，非身份）", 7, Palette.a(Palette.AMBER, 0.8))

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
	_txt(cjk, r.position.x + 6.0, r.position.y + 5.0, "可见光通道 / OPTICAL", 7, Palette.a(Palette.BLUE, 0.75))
	_txt(mono, r.end.x - 42.0, r.position.y + 5.0, "MS-OT2 8×", 7, Palette.a(Palette.BLUE, 0.55))
	_txt(mono, r.position.x + 6.0, r.end.y - 12.0, "[9001] 谷神-2 +2.1", 7, Palette.a(Palette.BLUE, 0.55))

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
	if t.get("ghost", false):
		return Palette.PH_FAINT
	return _identity_color(_ident(t))

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

