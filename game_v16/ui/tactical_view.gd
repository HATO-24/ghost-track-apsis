extends Control

## V2-3 战术图：消费 `sim/tactical_snapshot.gd`（V2-SENSOR-2）的纯数据快照。
##
## 数据（经 `ui/data_source.gd` 的 tactical_* 包装）：
##   - contacts[i].screen / marker / level_label / identity_label / threat / bearing_line …
##   - radar.sphere（球形 R_eff / 名义 / TWS 跟踪半径，非扇形）+ radar.exposure
##   - tws.channels（六态/quality/age）+ optical.optical/ir（进度/状态）
##   - own.screen / local_r_km / camera（yaw_deg/pitch_deg/scale_px_per_km）
##
## 本文件只做「画 + 相机输入」，不改 world/sim；相机参数回传给 data_source 重新 build。
## 右击接触 → contact_context(id, at)，由 game_screen 弹 action_menu。

signal contact_selected(id: String)
signal contact_context(id: String, at: Vector2)
signal view_changed(info: Dictionary)

const T := preload("res://ui/theme.gd")
const L := preload("res://ui/layout.gd")

const HEADER_H := 36.0
const FOOTER_H := 28.0

var _data = null
var _snapshot: Dictionary = {}
var _selected_id := ""
var _hover_id := ""
var yaw_deg := 0.0
var pitch_deg := 60.0
var scale_px_per_km := 0.0      # 0 = 自动 fit（来自快照）
var _drag := false
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _drag_yaw := 0.0
var _drag_pitch := 60.0
var _fit_margin := 0.82


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS


# ══ 绑定 / 相机 ══════════════════════════════════════════════════════════

func bind(data_ref) -> void:
	_data = data_ref
	rebuild()


func camera_cfg() -> Dictionary:
	return {
		"map_rect": [L.MAP.position.x, L.MAP.position.y, L.MAP.size.x, L.MAP.size.y],
		"yaw_deg": yaw_deg,
		"pitch_deg": pitch_deg,
		"scale_px_per_km": scale_px_per_km,
		"fit_margin": _fit_margin,
		"center_mode": "own",
	}


func rebuild() -> void:
	if _data == null:
		return
	if not _data.tactical_available():
		_snapshot = {}
		queue_redraw()
		return
	_snapshot = _data.tactical_build(camera_cfg())
	_snapshot_from_camera()
	set_selected(String(_data.selected_id))
	queue_redraw()


func set_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	_snapshot = snap
	_snapshot_from_camera()
	queue_redraw()


func _snapshot_from_camera() -> void:
	if _snapshot.is_empty():
		return
	var cam: Dictionary = _snapshot.get("camera", {}) if _snapshot.get("camera", {}) is Dictionary else {}
	if float(cam.get("scale_px_per_km", 0.0)) > 0.0:
		scale_px_per_km = float(cam.get("scale_px_per_km", 0.0))
	if bool(cam.get("auto_scale", false)):
		scale_px_per_km = 0.0


func set_selected(id: String) -> void:
	_selected_id = id
	queue_redraw()


func selected_id() -> String:
	return _selected_id


func reset_view() -> void:
	yaw_deg = 0.0
	pitch_deg = 60.0
	scale_px_per_km = 0.0
	rebuild()
	view_changed.emit(camera_cfg())


func view_info() -> Dictionary:
	return {"yaw": yaw_deg, "pitch": pitch_deg, "scale": scale_px_per_km,
		"contacts": (_snapshot.get("contacts", []) as Array).size()}


# ══ 坐标 ═════════════════════════════════════════════════════════════════

func _body_rect() -> Rect2:
	return Rect2(10.0, HEADER_H + 2.0, size.x - 20.0, size.y - HEADER_H - FOOTER_H - 4.0)


## snapshot 的屏幕建议坐标是 1920×1080 设计坐标（MAP 区）；换成控件局部坐标。
func _to_local(px: float, py: float) -> Vector2:
	return Vector2(px, py) - position


func _contact_local(c: Dictionary) -> Vector2:
	var scr: Dictionary = c.get("screen", {}) if c.get("screen", {}) is Dictionary else {}
	if scr.is_empty():
		return Vector2(-9999.0, -9999.0)
	return _to_local(float(scr.get("x", 0.0)), float(scr.get("y", 0.0)))


func _camera() -> Dictionary:
	if _snapshot.get("camera", null) is Dictionary:
		return _snapshot.get("camera")
	return _data.camera_cfg() if _data != null else {}


func _map_center() -> Vector2:
	var cam := _camera()
	var rect: Array = cam.get("map_rect", [])
	if rect.size() >= 4:
		return _to_local(float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3]) * 0.5)
	return _body_rect().get_center()


func _plane_to_local(rel: Vector3, scale: float) -> Vector2:
	return _map_center() + _plane_project(rel, scale)


func _plane_project(rel: Vector3, scale: float) -> Vector2:
	var cam := _camera()
	var yaw := deg_to_rad(float(cam.get("yaw_deg", yaw_deg)))
	var pitch := deg_to_rad(float(cam.get("pitch_deg", pitch_deg)))
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var x1 := cy * rel.x + sy * rel.y
	var y1 := -sy * rel.x + cy * rel.y
	var y2 := cp * y1 - sp * rel.z
	return Vector2(x1, -y2) * scale


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	T.panel(self, Rect2(0.0, 0.0, size.x, size.y), 0.90, 0.85)
	T.corners(self, Rect2(0.0, 0.0, size.x, size.y).grow(-1.0), 14.0, T.PH_DIM, 0.55)
	_draw_header()
	if _snapshot.is_empty():
		_draw_no_data()
		_draw_footer()
		return
	var body := _body_rect()
	_draw_grid(body)
	_draw_radar(body)
	_draw_predictions()
	_draw_bearing_lines()
	_draw_contacts(body)
	_draw_own()
	_draw_footer()


func _draw_no_data() -> void:
	var body := _body_rect()
	T.text_c(self, body.get_center().x, body.position.y + 40.0,
		"战术数据未就绪 / TACTICAL SNAPSHOT UNAVAILABLE", T.F13, T.a(T.AMBER, 0.9))
	T.text_c(self, body.get_center().x, body.position.y + 64.0,
		"需要 core V2-CORE-2（vm_flow/world）与 sim/tactical_snapshot.gd（V2-SENSOR-2）", T.F8, T.FAINT)
	T.text_c(self, body.get_center().x, body.position.y + 82.0,
		"本屏不会伪造战术符号；请查 headless 日志的 source/notes", T.F8, T.a(T.FAINT, 0.9))


func _draw_header() -> void:
	T.text(self, 16.0, 8.0, "战术态势 / TACTICAL PLOT", T.F11, T.TXT)
	var radar: Dictionary = _snapshot.get("radar", {}) if _snapshot.get("radar", {}) is Dictionary else {}
	var counts: Dictionary = _snapshot.get("counts", {}) if _snapshot.get("counts", {}) is Dictionary else {}
	var kicker := "2D 投影 · 中心本舰 · 球形雷达（非扇形）· 右击接触动作菜单"
	if not radar.is_empty():
		kicker = "2D 投影 · 球形 %s · 接触 %d · TWS %d · 光学锁定 %d" % [
			String(radar.get("model", "RADAR")),
			int(counts.get("contacts", 0)), int(counts.get("tws_channels", 0)),
			int(counts.get("optical_locked", 0))]
	T.text(self, 16.0, 24.0, kicker, T.F7, T.FAINT)
	var cam := _camera()
	T.text_r(self, size.x - 14.0, 8.0, "YAW %03d° · PITCH %02d° · %.3f px/km" % [
		int(round(fposmod(yaw_deg, 360.0))), int(round(pitch_deg)),
		float(cam.get("scale_px_per_km", scale_px_per_km))], T.F7, T.a(T.PH_DIM, 0.95), false)
	var exp: Dictionary = radar.get("exposure", {}) if radar.get("exposure", {}) is Dictionary else {}
	var emit_txt := "SIM 未就绪"
	var emit_col: Color = T.AMBER
	if bool(radar.get("available", false)):
		emit_txt = "RADAR %s · scan #%d" % ["ON" if bool(radar.get("enabled", false)) else "OFF",
			int(radar.get("scan_index", 0))]
		emit_col = T.PH if bool(radar.get("enabled", false)) else T.FAINT
	T.text_r(self, size.x - 14.0, 24.0, emit_txt, T.F7, T.a(emit_col, 0.9))
	if not exp.is_empty():
		T.text(self, size.x - 420.0, 24.0, "ELINT 截获 %.0f km · 定位 %.0f%%" % [
			float(exp.get("elint_intercept_range_km", 0.0)), float(exp.get("fix_progress", 0.0)) * 100.0],
			T.F7, T.a(T.AMBER, 0.8), false)
	T.hline(self, 12.0, HEADER_H, size.x - 12.0, T.a(T.LINE, 0.85))


func _scale() -> float:
	var cam := _camera()
	var s := float(cam.get("scale_px_per_km", 0.0))
	return maxf(s, 1.0e-6)


func _draw_grid(_body: Rect2) -> void:
	var center := _map_center()
	var scale := _scale()
	var pitch := deg_to_rad(float(_camera().get("pitch_deg", pitch_deg)))
	# 距离环步长：约 200 px 一圈，取 1/2/5×10ⁿ
	var km := 200.0 / scale
	var pow10 := pow(10.0, floor(log(maxf(km, 10.0)) / log(10.0)))
	var step := pow10
	if km / pow10 >= 5.0:
		step = pow10 * 5.0
	elif km / pow10 >= 2.0:
		step = pow10 * 2.0
	var r := step
	while r * scale < size.length() * 1.2:
		var pts := PackedVector2Array()
		for i in range(73):
			var ang := TAU * float(i) / 72.0
			pts.append(_plane_to_local(Vector3(cos(ang) * r, sin(ang) * r, 0.0), scale))
		draw_polyline(pts, T.a(T.GRID, 0.34), 1.0)
		var top := _plane_to_local(Vector3(0.0, r, 0.0), scale)
		if _body_rect().has_point(top):
			T.text(self, top.x + 5.0, top.y - 11.0, "%s km" % T.fmt_int(int(round(r))), T.F7, T.a(T.PH_FAINT, 0.9), false)
		r += step
	# 轴/方位
	var far := 100000.0
	var axes := {"N": Vector3(0, 1, 0), "E": Vector3(1, 0, 0), "S": Vector3(0, -1, 0), "W": Vector3(-1, 0, 0)}
	for key in axes:
		var p := _plane_to_local((axes[key] as Vector3) * far, scale)
		var clipped := _clamp_segment(center, p, _body_rect().grow(-8.0))
		T.text(self, clipped.x + 3.0, clipped.y, String(key), T.F7, T.a(T.PH_FAINT, 0.8), false)
	if pitch > 0.0:
		pass
	draw_line(center - Vector2(9, 0), center + Vector2(9, 0), T.a(T.PH, 0.45), 1.0)
	draw_line(center - Vector2(0, 9), center + Vector2(0, 9), T.a(T.PH, 0.45), 1.0)


func _clamp_segment(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	if rect.has_point(b):
		return b
	var lo := 0.0
	var hi := 1.0
	for i in range(18):
		var mid := (lo + hi) * 0.5
		if rect.has_point(a.lerp(b, mid)):
			lo = mid
		else:
			hi = mid
	return a.lerp(b, lo)


func _draw_radar(body: Rect2) -> void:
	var radar: Dictionary = _snapshot.get("radar", {}) if _snapshot.get("radar", {}) is Dictionary else {}
	if not bool(radar.get("available", false)):
		T.text_c(self, body.get_center().x, body.position.y + 18.0,
			"雷达球形范围不可用（sim_state 无雷达模型）· 不画假扇形", T.F8, T.a(T.AMBER, 0.75))
		return
	var sphere: Dictionary = radar.get("sphere", {}) if radar.get("sphere", {}) is Dictionary else {}
	if sphere.is_empty():
		return
	var eff := float(sphere.get("effective_radius_km", 0.0))
	var nom := float(sphere.get("nominal_radius_km", eff))
	var track_r := float(sphere.get("track_radius_km", eff))
	var center := _map_center()
	var scale := _scale()
	if eff * scale > minf(body.size.x, body.size.y) * 0.75:
		draw_rect(body, T.a(T.PH, 0.028))
		T.chip(self, Rect2(body.position.x + 10.0, body.end.y - 26.0, 250.0, 16.0),
			"视图全部在球形范围内（R %.0f km）" % eff, T.PH_DIM, true, T.F7)
		T.text(self, body.end.x - 240.0, body.end.y - 24.0, "球形 / SPHERE · 无扇形",
			T.F7, T.a(T.PH_FAINT, 0.85))
	else:
		draw_arc(center, nom * scale, 0.0, TAU, 96, T.a(T.PH_FAINT, 0.28), 1.0, true)
		draw_arc(center, eff * scale, 0.0, TAU, 96, T.a(T.PH, 0.55), 1.2, true)
		draw_arc(center, track_r * scale, 0.0, TAU, 96, T.a(T.PH_DIM, 0.35), 1.0, true)
		T.text(self, center.x + eff * scale * 0.72, center.y - 5.0,
			"球形搜索 R %.0f km" % eff, T.F7, T.a(T.PH, 0.85))
	# 扫描进度弧
	var prog := clampf(float(radar.get("scan_progress", 0.0)), 0.0, 1.0)
	if bool(radar.get("enabled", false)):
		draw_arc(center, 24.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, T.a(T.PH, 0.5), 2.0, true)
	T.text(self, body.position.x + 10.0, body.position.y + 8.0,
		"球形 / SPHERE · 非扇形 · 接触在界内 %d" % int(sphere.get("contacts_in_sphere", 0)),
		T.F7, T.a(T.PH_DIM, 0.9))




## 轨道预测（虚线）：core 当前没有轨道传播，快照也没有传播接口；
## 这里用实体 orbit r + v 做 120 s 线性外推（短弧近似），只用于显示，
## 不写回 core、不当作观测。v15 orbit_model 的完整传播留给后续 V2-CORE 扩展。
func _draw_predictions() -> void:
	if _data == null or _snapshot.is_empty():
		return
	var own_g: Dictionary = _data.own_geometry()
	var own_r: Variant = own_g.get("r", Vector3.ZERO)
	if not (own_r is Vector3):
		return
	var scale := _scale()
	var body := _body_rect()
	for raw in (_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw
		if bool(c.get("is_own", false)):
			continue
		var marker: Dictionary = c.get("marker", {}) if c.get("marker", {}) is Dictionary else {}
		if String(marker.get("shape", "")) != "contact":
			continue
		var tid := String(c.get("track_id", ""))
		var g: Dictionary = _data.geometry_of(tid)
		if g.is_empty():
			continue
		var v: Variant = g.get("v", Vector3.ZERO)
		var r: Variant = g.get("r", Vector3.ZERO)
		if not (v is Vector3) or not (r is Vector3):
			continue
		if (v as Vector3).length() < 1.0e-4:
			continue
		var accent: Color = T.side_color(String(c.get("side", "unknown")))
		var prev := _to_local_from_rel((r as Vector3) - (own_r as Vector3), scale)
		var drew := false
		for tf in [30.0, 60.0, 120.0]:
			var p: Vector3 = (r as Vector3) + (v as Vector3) * tf
			var sp := _to_local_from_rel(p - (own_r as Vector3), scale)
			if not body.grow(30.0).has_point(sp) and not drew:
				break
			draw_dashed_line(prev, sp, T.a(accent, 0.26), 1.0, 5.0)
			prev = sp
			drew = true
		if drew:
			T.text(self, prev.x + 4.0, prev.y + 10.0, "+120s（线性外推）", T.F7, T.a(accent, 0.42), false)


func _to_local_from_rel(rel: Vector3, scale: float) -> Vector2:
	return _map_center() + Vector2(_plane_project(rel, scale))

func _draw_bearing_lines() -> void:
	var center := _map_center()
	for raw in (_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw
		var bl: Dictionary = c.get("bearing_line", {}) if c.get("bearing_line", {}) is Dictionary else {}
		if bl.is_empty():
			continue
		var end_scr: Dictionary = bl.get("endpoint_screen", {}) if bl.get("endpoint_screen", {}) is Dictionary else {}
		if end_scr.is_empty():
			continue
		var endp := _to_local(float(end_scr.get("x", 0.0)), float(end_scr.get("y", 0.0)))
		var is_selected := _is_selected(c)
		var col: Color = T.AMBER if not is_selected else T.PH
		draw_dashed_line(center, endp, T.a(col, 0.55 if is_selected else 0.35), 1.0, 6.0)
		var brg := float((c.get("bearings", {}) as Dictionary).get("bearing_deg", 0.0)) if c.get("bearings", {}) is Dictionary else 0.0
		var band := String(c.get("range_band_label", ""))
		var label := "BRG %03d° · %s" % [int(brg), band if band != "" else "L1 方位"]
		var lp := center.lerp(endp, 0.62)
		if _body_rect().has_point(lp):
			T.text(self, lp.x + 4.0, lp.y - 4.0, label, T.F7, T.a(col, 0.9), false)


func _contact_priority(c: Dictionary) -> int:
	if _is_selected(c):
		return 0
	var side := String(c.get("side", "unknown"))
	if side == "hostile":
		return 1
	if side == "unknown" or side == "neutral":
		return 2
	return 3


func _draw_contacts(body: Rect2) -> void:
	var map_round := Rect2(body)
	var placed_labels: Array = [Rect2(_map_center() + Vector2(12.0, 6.0), Vector2(168.0, 18.0))]
	var ordered: Array = (_snapshot.get("contacts", []) as Array).duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _contact_priority(a) < _contact_priority(b))
	for raw in ordered:
		var c: Dictionary = raw
		if bool(c.get("is_own", false)):
			continue
		var marker: Dictionary = c.get("marker", {}) if c.get("marker", {}) is Dictionary else {}
		var shape := String(marker.get("shape", "contact"))
		if shape == "bearing" or shape == "phantom":
			continue
		var scr: Dictionary = c.get("screen", {}) if c.get("screen", {}) is Dictionary else {}
		if scr.is_empty():
			continue
		var sp := _to_local(float(scr.get("x", 0.0)), float(scr.get("y", 0.0)))
		var inside := bool(scr.get("inside", true))
		if not inside:
			_draw_edge_marker(scr, c)
			continue
		if not map_round.grow(20.0).has_point(sp):
			continue
		var side := String(c.get("side", "unknown"))
		var identity := String(c.get("identity", "unknown"))
		var level := int(c.get("level", 0))
		var accent: Color = T.side_color(side)
		var selected := _is_selected(c)
		var hovered := String(c.get("track_id", "")) == _hover_id or String(c.get("entity_id", "")) == _hover_id
		if selected:
			draw_arc(sp, 15.0, 0.0, TAU, 28, T.a(T.PH, 0.9), 1.4, true)
			draw_arc(sp, 19.0, 0.0, TAU, 28, T.a(T.PH, 0.3), 1.0, true)
		elif hovered:
			draw_arc(sp, 12.0, 0.0, TAU, 24, T.a(T.TXT, 0.55), 1.0, true)
		T.identity_glyph(self, sp, 6.5, identity, T.a(T.identity_color(identity), 0.95))
		T.badge(self, Rect2(sp + Vector2(9.0, -18.0), Vector2(20.0, 12.0)),
			T.level_name(level), T.identity_color(identity), T.F7)
		# TWS 通道环（snapshot.contacts[i].tws）
		var tws: Dictionary = c.get("tws", {}) if c.get("tws", {}) is Dictionary else {}
		if not tws.is_empty():
			var st := String(tws.get("state", ""))
			var col: Color = T.AMBER
			if st == "FIRE_CONTROL":
				col = T.RED
			elif st == "TRACK" or st == "STARE":
				col = T.PH
			elif st == "ACQUIRE":
				col = T.BLUE
			draw_arc(sp, 12.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(tws.get("quality", 0.0)), 0.0, 1.0),
				32, T.a(col, 0.85), 2.0, true)
			draw_arc(sp, 12.0, 0.0, TAU, 32, T.a(col, 0.16), 1.0, true)
			if st in ["ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]:
				T.text(self, sp.x - 4.0, sp.y + 22.0, "TWS " + st, T.F7, T.a(col, 0.85), false)
		# 光学/IR 通道环
		var opts: Array = c.get("optical_channels", []) if c.get("optical_channels", []) is Array else []
		var oi := 0
		for raw_opt in opts:
			var och: Dictionary = raw_opt
			var kind := String(och.get("channel", "optical"))
			var status := String(och.get("status", ""))
			var col2: Color = T.PH if status == "locked" else (T.BLUE if kind == "optical" else T.AMBER)
			var rad := 22.0 + float(oi) * 5.0
			draw_arc(sp, rad, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(och.get("progress", 0.0)), 0.0, 1.0),
				36, T.a(col2, 0.9), 1.6, true)
			var tag := ("OPT %s %.0f%%" % [status, float(och.get("progress", 0.0)) * 100.0]) if kind == "optical" else "IR " + status
			T.text(self, sp.x + rad + 3.0, sp.y - 8.0, tag, T.F7, T.a(col2, 0.9), false)
			oi += 1
		# 标签 + 引线（按优先级放置，简单碰撞避免）
		var label_size := Vector2(172.0, 30.0)
		var candidates: Array = [
			sp + Vector2(24.0, -6.0),
			sp + Vector2(-label_size.x - 24.0, -6.0),
			sp + Vector2(14.0, 18.0),
			sp + Vector2(-label_size.x - 14.0, 18.0),
		]
		var label_pos: Vector2 = candidates[0]
		var chosen := false
		for cand in candidates:
			var cand_rect := Rect2(cand, label_size)
			if not body.has_point(cand_rect.position) or cand_rect.end.x > body.end.x or cand_rect.end.y > body.end.y:
				continue
			var clash := false
			for pr in placed_labels:
				if (pr as Rect2).grow(3.0).intersects(cand_rect):
					clash = true
					break
			if not clash:
				label_pos = cand
				chosen = true
				break
		if not chosen:
			if String(c.get("side", "unknown")) == "friend" and not selected:
				# 友方密集编队：只画符号 + 小批号，避免标签互相遮挡
				T.text(self, sp.x + 8.0, sp.y - 10.0, String(c.get("batch", "")), T.F7,
					T.a(accent, 0.8), false)
				continue
			label_pos = sp + Vector2(24.0, -6.0)
			if label_pos.x + label_size.x > body.end.x:
				label_pos.x = sp.x - label_size.x - 24.0
		placed_labels.append(Rect2(label_pos, label_size))
		draw_line(sp, label_pos + Vector2(0.0, 9.0), T.a(accent, 0.45), 1.0)
		draw_rect(Rect2(label_pos, label_size), T.a(T.PANEL, 0.78))
		draw_rect(Rect2(label_pos, label_size), T.a(accent, 0.30), false, 1.0)
		T.text_fit(self, label_pos.x + 4.0, label_pos.y + 2.0,
			"[%s] %s" % [String(c.get("batch", "")), String(c.get("name", ""))], T.F7,
			T.a(accent, 0.95), label_size.x - 8.0)
		var rng_km := float(c.get("range_km", -1.0))
		var info := "L%d %s" % [level, String(c.get("identity_label", ""))]
		if rng_km >= 0.0:
			info += " · %.0f km" % rng_km
		if bool(c.get("stale", false)):
			info += " · 陈旧 %.0fs" % float(c.get("age_s", 0.0))
		T.text_fit(self, label_pos.x + 4.0, label_pos.y + 16.0, info, T.F7, T.a(T.DIM, 0.95),
			label_size.x - 8.0, false)


func _draw_edge_marker(scr: Dictionary, c: Dictionary) -> void:
	var edge: Dictionary = scr.get("edge", {}) if scr.get("edge", {}) is Dictionary else {}
	if edge.is_empty():
		return
	var sp := _to_local(float(edge.get("x", 0.0)), float(edge.get("y", 0.0)))
	var accent: Color = T.side_color(String(c.get("side", "unknown")))
	draw_rect(Rect2(sp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), T.a(accent, 0.8))
	T.text_fit(self, sp.x + 6.0, sp.y - 6.0, "[%s] %s" % [String(c.get("batch", "")),
		String(c.get("name", ""))], T.F7, T.a(accent, 0.85), 120.0)


func _draw_own() -> void:
	var own: Dictionary = _snapshot.get("own", {}) if _snapshot.get("own", {}) is Dictionary else {}
	var scr: Dictionary = own.get("screen", {}) if own.get("screen", {}) is Dictionary else {}
	var sp := _map_center()
	if not scr.is_empty():
		sp = _to_local(float(scr.get("x", 0.0)), float(scr.get("y", 0.0)))
	draw_circle(sp, 3.0, T.PH)
	draw_arc(sp, 8.0, 0.0, TAU, 24, T.a(T.PH, 0.9), 1.2, true)
	draw_arc(sp, 14.0, 0.0, TAU, 28, T.a(T.PH, 0.25), 1.0, true)
	T.text(self, sp.x + 14.0, sp.y + 8.0, "OWN [%s] %s" % [String(own.get("batch", "")),
		String(own.get("name", "本舰"))], T.F8, T.a(T.PH, 0.95))


func _draw_footer() -> void:
	var y := size.y - FOOTER_H + 5.0
	T.hline(self, 12.0, size.y - FOOTER_H, size.x - 12.0, T.a(T.LINE, 0.7))
	var scale := _scale()
	var km_target := 120.0 / scale
	var pow10 := pow(10.0, floor(log(maxf(km_target, 1.0)) / log(10.0)))
	var nice := pow10
	if km_target / pow10 >= 5.0:
		nice = pow10 * 5.0
	elif km_target / pow10 >= 2.0:
		nice = pow10 * 2.0
	var bar_w := nice * scale
	var x0 := 16.0
	draw_line(Vector2(x0, y + 9.0), Vector2(x0 + bar_w, y + 9.0), T.a(T.PH, 0.7), 1.0)
	draw_line(Vector2(x0, y + 5.0), Vector2(x0, y + 13.0), T.a(T.PH, 0.7), 1.0)
	draw_line(Vector2(x0 + bar_w, y + 5.0), Vector2(x0 + bar_w, y + 13.0), T.a(T.PH, 0.7), 1.0)
	T.text(self, x0, y + 14.0, "%s km" % T.fmt_int(int(round(nice))), T.F7, T.a(T.PH_DIM, 0.95), false)
	# TWS / 光学摘要
	var tws: Dictionary = _snapshot.get("tws", {}) if _snapshot.get("tws", {}) is Dictionary else {}
	var opt: Dictionary = _snapshot.get("optical", {}) if _snapshot.get("optical", {}) is Dictionary else {}
	var summ := "TWS %d 通道/%d 活跃 · 光学 VIS %d / IR %d" % [
		int(tws.get("channel_count", 0)), int(tws.get("active_count", 0)),
		(opt.get("optical", []) as Array).size() if opt.get("optical", []) is Array else 0,
		(opt.get("ir", []) as Array).size() if opt.get("ir", []) is Array else 0]
	T.text(self, x0 + 200.0, y + 2.0, summ, T.F7, T.a(T.PH_DIM, 0.9), false)
	T.text_r(self, size.x - 14.0, y + 2.0, "拖拽旋转 · 滚轮缩放 · R 复位 · 右击目标动作",
		T.F7, T.a(T.FAINT, 0.9))


# ══ 输入 ═════════════════════════════════════════════════════════════════

func _is_selected(c: Dictionary) -> bool:
	return String(c.get("track_id", "")) == _selected_id or String(c.get("entity_id", "")) == _selected_id


func contact_at(pos: Vector2) -> String:
	var best := ""
	var best_d := 18.0
	for raw in (_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw
		if bool(c.get("is_own", false)):
			continue
		var marker: Dictionary = c.get("marker", {}) if c.get("marker", {}) is Dictionary else {}
		if String(marker.get("shape", "")) == "bearing" or String(marker.get("shape", "")) == "phantom":
			continue
		var scr: Dictionary = c.get("screen", {}) if c.get("screen", {}) is Dictionary else {}
		if scr.is_empty() or not bool(scr.get("inside", true)):
			continue
		var sp := _to_local(float(scr.get("x", 0.0)), float(scr.get("y", 0.0)))
		var d := sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = String(c.get("track_id", c.get("entity_id", "")))
	return best


func screen_pos_of(id: String) -> Vector2:
	for raw in (_snapshot.get("contacts", []) as Array):
		var c: Dictionary = raw
		if String(c.get("track_id", "")) == id or String(c.get("entity_id", "")) == id:
			var scr: Dictionary = c.get("screen", {}) if c.get("screen", {}) is Dictionary else {}
			if not scr.is_empty():
				return _to_local(float(scr.get("x", 0.0)), float(scr.get("y", 0.0)))
	return _map_center()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.15)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.15)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_start = mb.position
				_drag_moved = false
				_drag_yaw = yaw_deg
				_drag_pitch = pitch_deg
				accept_event()
			else:
				if not _drag_moved:
					var cid := contact_at(mb.position)
					if cid != "":
						_selected_id = cid
						queue_redraw()
						contact_selected.emit(cid)
				_drag = false
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var cid2 := contact_at(mb.position)
			if cid2 != "":
				_selected_id = cid2
				queue_redraw()
				contact_selected.emit(cid2)
				contact_context.emit(cid2, get_global_rect().position + mb.position)
			accept_event()
			return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag:
			var delta := mm.position - _drag_start
			if delta.length() > 3.0:
				_drag_moved = true
			yaw_deg = fposmod(_drag_yaw + delta.x * 0.35, 360.0)
			pitch_deg = clampf(_drag_pitch - delta.y * 0.25, 12.0, 90.0)
			_rebuild_camera()
			view_changed.emit(camera_cfg())
		else:
			var hid := contact_at(mm.position)
			if hid != _hover_id:
				_hover_id = hid
				queue_redraw()


func _zoom_by(factor: float) -> void:
	var cur := scale_px_per_km
	if cur <= 0.0:
		cur = _scale()
	scale_px_per_km = clampf(cur * factor, 1.0e-5, 12.0)
	_rebuild_camera()
	view_changed.emit(camera_cfg())


func _rebuild_camera() -> void:
	if _data == null or not _data.tactical_available():
		return
	_snapshot = _data.tactical_build(camera_cfg())
	queue_redraw()
