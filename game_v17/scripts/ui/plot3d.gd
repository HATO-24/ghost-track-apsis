extends RefCounted

# 方案B-24：V1 线框 3D 战术图。
# 只读：transfer cache timeline/samples + binder contacts/session entities + facility markers；
# 不读旧 plot state；不写 world/物理。鼠标拖拽旋转、滚轮缩放、R 重置。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")

const TRANSFER_PATH := "res://framework/content/transfer_l4_l1_cached.json"
const FLEET_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"

var source := "cache"
var physics_rows: Array = []
var facility_rows: Array = []
var bodies: Dictionary = {}
var cic: Dictionary = {}
var own_cic: Array = []
var cic_tracks: Array = []
var cic_facilities: Array = []
var cic_source := "CIC VIEW"
var facility_visual: Array = []
var focus := Vector3.ZERO
var _focus_target := Vector3.ZERO
var label_conflicts := 0
var labels_hidden := 0
var labels_total := 0
var _label_queue: Array = []
var _label_boxes: Array = []
var _plot_safe := Rect2()
var _label_anchor_map: Dictionary = {}
var _stats_logged := false
var timeline: Array = []
var fleet_samples: Array = []
var contacts: Array = []
var entity_pos: Dictionary = {}
var center := Vector3.ZERO
var span := 1.0
var yaw := -0.65
var pitch := 0.32
var dist := 4.0
var dragging := false
var _drag_last := Vector2.ZERO
var _label_pts: Array = []
var _frames := 0


func setup(binder) -> void:
	source = "cache"
	physics_rows = []
	facility_rows = []
	timeline = []
	fleet_samples = []
	contacts = []
	entity_pos = {}
	if binder != null and binder.has_method("plot_cic"):
		var cv: Dictionary = binder.plot_cic()
		if bool(cv.get("ready", false)) and (cv.get("tracks", []) as Array).size() + (cv.get("facilities", []) as Array).size() > 0:
			source = "cic"
			cic = cv.duplicate(true)
			cic_tracks = (cv.get("tracks", []) as Array).duplicate(true)
			own_cic = (cv.get("ownship", {}) as Dictionary).get("pos_km", [0.0, 0.0, 0.0]) if cv.get("ownship", {}) is Dictionary else [0.0, 0.0, 0.0]
			var raw_f: Array = (cv.get("facilities", []) as Array)
			for rawf in raw_f:
				if rawf is Dictionary and String((rawf as Dictionary).get("cluster_id", "")) == "L1_MERIDIAN":
					cic_facilities.append(rawf)
					if cic_facilities.size() >= 12:
						break
			if binder.has_method("plot_bodies"):
				bodies = binder.plot_bodies().duplicate(true)
			if binder.has_method("plot_facilities"):
				facility_visual = (binder.plot_facilities().get("facilities", []) as Array).duplicate(true)
			_load_json_arrays()
			contacts = binder.contacts.duplicate(true) if binder.contacts is Array else []
			_bounds_cic()
			return
	if binder != null and binder.has_method("plot_positions"):
		var pp: Dictionary = binder.plot_positions()
		if String(pp.get("source", "")) == "physics" and not (pp.get("positions", []) as Array).is_empty():
			source = "physics"
			physics_rows = (pp.get("positions", []) as Array).duplicate(true)
			var pf: Dictionary = binder.plot_facilities()
			facility_rows = (pf.get("facilities", []) as Array).duplicate(true)
			if binder.has_method("plot_bodies"):
				bodies = binder.plot_bodies().duplicate(true)
			contacts = binder.contacts.duplicate(true) if binder.contacts is Array else []
			_bounds_physics()
			return
	if binder != null:
		contacts = binder.contacts.duplicate(true) if binder.contacts is Array else []
		var snap: Dictionary = binder.snapshot if binder.snapshot is Dictionary else {}
		for raw in (snap.get("entities", []) if snap.get("entities", []) is Array else []):
			if raw is Dictionary:
				var e: Dictionary = raw
				var pos: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else []
				if pos.size() >= 3:
					entity_pos[String(e.get("id", ""))] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_bounds()


func _bounds_cic() -> void:
	var pts: Array = []
	pts.append(own_cic)
	for raw in cic_tracks:
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var est: Array = tr.get("estimate_km", []) if tr.get("estimate_km", []) is Array else []
		if est.size() >= 3:
			pts.append(est)
		else:
			var b = tr.get("bearing_deg", null)
			if b is int or b is float:
				var cone := float(tr.get("uncertainty_deg", 2.0))
				var ray_len := 6000.0
				pts.append([float(own_cic[0]) + cos(deg_to_rad(float(b))) * ray_len, float(own_cic[1]) + sin(deg_to_rad(float(b))) * ray_len, float(own_cic[2])])
	for raw2 in cic_facilities:
		if raw2 is Dictionary and (raw2 as Dictionary).get("pos_km", []) is Array and ((raw2 as Dictionary).get("pos_km", []) as Array).size() >= 3:
			pts.append((raw2 as Dictionary).get("pos_km"))
	for bk in ["earth", "moon"]:
		if bodies.get(bk) is Dictionary:
			var bp: Array = (bodies[bk] as Dictionary).get("pos_km", [])
			if bp.size() >= 3:
				pts.append(bp)
	if pts.is_empty():
		center = Vector3.ZERO
		span = 1.0
		return
	var mn := Vector3(1.0e30, 1.0e30, 1.0e30)
	var mx := Vector3(-1.0e30, -1.0e30, -1.0e30)
	for raw3 in pts:
		var p3: Array = raw3
		var v := Vector3(float(p3[0]), float(p3[1]), float(p3[2]))
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
		mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
	center = (mn + mx) * 0.5
	span = maxf(1.0, maxf(mx.x - mn.x, maxf(mx.y - mn.y, mx.z - mn.z)))


func _rel_own(raw: Array) -> Array:
	if raw.size() < 3:
		return raw
	return [float(raw[0]) - float(own_cic[0]), float(raw[1]) - float(own_cic[1]), float(raw[2]) - float(own_cic[2])]


func _bounds_physics() -> void:
	var pts: Array = []
	for row in physics_rows:
		if row is Dictionary:
			var p: Array = (row as Dictionary).get("pos_km", [])
			if p.size() >= 3:
				pts.append(p)
	for row in facility_rows:
		if row is Dictionary:
			var p2: Array = (row as Dictionary).get("pos_km", [])
			if p2.size() >= 3:
				pts.append(p2)
	for bk in ["earth", "moon"]:
		if bodies.get(bk) is Dictionary:
			var bp: Array = (bodies[bk] as Dictionary).get("pos_km", [])
			if bp.size() >= 3:
				pts.append(bp)
	if pts.is_empty():
		center = Vector3.ZERO
		span = 1.0
		return
	var mn := Vector3(1.0e30, 1.0e30, 1.0e30)
	var mx := Vector3(-1.0e30, -1.0e30, -1.0e30)
	for raw in pts:
		var p3: Array = raw
		var v := Vector3(float(p3[0]), float(p3[1]), float(p3[2]))
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
		mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
	center = (mn + mx) * 0.5
	span = maxf(1.0, maxf(mx.x - mn.x, maxf(mx.y - mn.y, mx.z - mn.z)))


func _load_json_arrays() -> void:
	if FileAccess.file_exists(TRANSFER_PATH):
		var f := FileAccess.open(TRANSFER_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				timeline = (parsed.get("timeline", []) as Array).duplicate(true) if parsed.get("timeline", []) is Array else []
	if FileAccess.file_exists(FLEET_PATH):
		var f2 := FileAccess.open(FLEET_PATH, FileAccess.READ)
		if f2 != null:
			var parsed2 = JSON.parse_string(f2.get_as_text())
			f2.close()
			if parsed2 is Dictionary:
				fleet_samples = (parsed2.get("samples", []) as Array).duplicate(true) if parsed2.get("samples", []) is Array else []


func _raw_points() -> Array:
	var pts: Array = []
	for raw in timeline:
		if raw is Dictionary and (raw as Dictionary).get("pos_rot_km", []) is Array and ((raw as Dictionary).get("pos_rot_km", []) as Array).size() >= 3:
			pts.append((raw as Dictionary).get("pos_rot_km"))
	pts.append([0.0, 0.0, 0.0]) # Earth limb
	pts.append([384400.0, 0.0, 0.0]) # Moon limb
	return pts


func _bounds() -> void:
	var pts := _raw_points()
	if pts.is_empty():
		center = Vector3.ZERO
		span = 1.0
		return
	var mn := Vector3(1.0e30, 1.0e30, 1.0e30)
	var mx := Vector3(-1.0e30, -1.0e30, -1.0e30)
	for raw in pts:
		var p: Array = raw
		var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
		mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
	center = (mn + mx) * 0.5
	span = maxf(1.0, maxf(mx.x - mn.x, maxf(mx.y - mn.y, mx.z - mn.z)))


func _unit(raw: Array) -> Vector3:
	if raw.size() < 3:
		return Vector3.ZERO
	return (Vector3(float(raw[0]), float(raw[1]), float(raw[2])) - center) / span * 2.0


func _project(u: Vector3, rect: Rect2) -> Vector2:
	var uu := u - focus
	var cy := cos(yaw)
	var sy := sin(yaw)
	var x := uu.x * cy + uu.z * sy
	var z := -uu.x * sy + uu.z * cy
	var cp := cos(pitch)
	var sp := sin(pitch)
	var yy := uu.y * cp - z * sp
	var zz := uu.y * sp + z * cp
	var denom := dist + zz
	if denom <= 0.15:
		return Vector2(-9999, -9999)
	var f := minf(rect.size.x, rect.size.y) * 1.8
	return rect.position + rect.size * 0.5 + Vector2(x, -yy) * f / denom


func rotate_input(delta: Vector2) -> void:
	yaw += delta.x * 0.006
	pitch = clampf(pitch - delta.y * 0.006, -1.35, 1.35)


func zoom_input(delta: float) -> void:
	dist = clampf(dist * pow(1.12, -delta), 1.4, 8.0)


func reset() -> void:
	yaw = -0.65
	pitch = 0.32
	dist = 4.0
	focus = Vector3.ZERO
	_focus_target = Vector3.ZERO


func handle_input(event: InputEvent, rect: Rect2) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if rect.has_point(mb.position):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom_input(1.0)
				return true
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom_input(-1.0)
				return true
			if mb.button_index == MOUSE_BUTTON_LEFT:
				dragging = mb.pressed
				_drag_last = mb.position
				return true
	if event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		rotate_input(mm.position - _drag_last)
		_drag_last = mm.position
		return true
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and (ke.keycode == KEY_R):
			reset()
			return true
	return false


func _queue_label(anchor_pos: Vector2, text: String, col: Color, size: int, prio: int, kind: String) -> void:
	_label_queue.append({"anchor": anchor_pos, "text": text, "col": col, "size": size, "prio": prio, "kind": kind})


func _flush_labels(canvas: CanvasItem) -> void:
	label_conflicts = 0
	labels_hidden = 0
	labels_total = _label_queue.size()
	_label_queue.sort_custom(func(a, b): return int(a.get("prio", 0)) > int(b.get("prio", 0)))
	for raw in _label_queue:
		var e: Dictionary = raw
		var text := String(e.get("text", ""))
		var size := int(e.get("size", 6))
		var w: float = TM.width(text, true, size)
		var h := float(size + 4)
		var offsets := [Vector2(0, 0), Vector2(0, -11), Vector2(0, 11), Vector2(0, -21), Vector2(0, 21)]
		var placed := false
		for off in offsets:
			var p: Vector2 = (e.get("anchor", Vector2.ZERO) as Vector2) + (off as Vector2)
			var rr := Rect2(p.x, p.y - float(size), w + 2.0, h)
			if not _plot_safe.encloses(rr):
				continue
			var hit := false
			for bx in _label_boxes:
				if (bx as Rect2).intersects(rr):
					hit = true
					break
			if hit:
				continue
			if off != Vector2.ZERO:
				label_conflicts += 1
				canvas.draw_line(e.get("anchor", Vector2.ZERO), p + Vector2(0, -2), P.a(P.a(e.get("col", P.TXT), 0.45), 0.6), 1.0)
			canvas.draw_string(F.cjk(), p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, e.get("col", P.TXT))
			_label_boxes.append(rr)
			placed = true
			break
		if not placed:
			if String(e.get("kind", "")) == "facility":
				labels_hidden += 1
			else:
				label_conflicts += 1
				canvas.draw_string(F.cjk(), e.get("anchor", Vector2.ZERO), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, e.get("col", P.TXT))
	if not _stats_logged:
		_stats_logged = true
		print("[V1 PLOT3D] labels=", labels_total, " conflicts=", label_conflicts, " hidden_facility=", labels_hidden, " bodies=", bodies.get("source", "—"))


func label_stats() -> Dictionary:
	return {"labels": labels_total, "conflicts": label_conflicts, "hidden": labels_hidden, "bodies_source": String(bodies.get("source", ""))}


func _label(canvas: CanvasItem, pos: Vector2, text: String, col: Color, size := 7, align_right := false) -> void:
	var p := pos
	for q in _label_pts:
		if absf(p.x - (q as Vector2).x) < 40.0 and absf(p.y - (q as Vector2).y) < 8.0:
			p.y += 10.0
	_label_pts.append(p)
	var w: float = TM.width(text, true, size)
	var x: float = p.x - w if align_right else p.x
	canvas.draw_string(F.cjk(), Vector2(x, p.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func draw_plot(canvas: CanvasItem, rect: Rect2, binder, selected_id := "") -> bool:
	if source == "cic":
		_draw_cic(canvas, rect, binder, selected_id)
		return true
	if source == "physics" and not physics_rows.is_empty():
		_draw_physics(canvas, rect, binder, selected_id)
		return true
	if timeline.is_empty():
		return false
	_label_pts.clear()
	_frames += 1
	canvas.draw_rect(rect, P.a(P.EARTH, 0.38))
	canvas.draw_rect(rect, P.a(P.LINE, 0.65), false, 1.0)
	# grid / stars
	for i in range(20):
		var gx := rect.position.x + rect.size.x * float(i) / 20.0
		canvas.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), P.a(P.LINE, 0.06), 1.0)
	for j in range(12):
		var gy := rect.position.y + rect.size.y * float(j) / 12.0
		canvas.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), P.a(P.LINE, 0.06), 1.0)
	for i in range(56):
		var hh := (i * 1103515245 + 12345) & 0x7fffffff
		var sx := rect.position.x + 8.0 + float(hh % int(maxf(1.0, rect.size.x - 16.0)))
		var sy := rect.position.y + 8.0 + float((hh / 97) % int(maxf(1.0, rect.size.y - 16.0)))
		canvas.draw_rect(Rect2(sx, sy, 1, 1), P.a(P.TXT, 0.16))
	# Earth / Moon limbs (approximate V1 wireframe)
	var earth_u := _unit([0.0, 0.0, 0.0])
	var moon_u := _unit([384400.0, 0.0, 0.0])
	_draw_limb(canvas, rect, earth_u, 6371.0 / span * 2.0, P.PH, "EARTH")
	_draw_limb(canvas, rect, moon_u, 1737.0 / span * 2.0, P.PH_DIM, "MOON")
	# trajectory
	var prev := Vector2(-9999, -9999)
	for raw in timeline:
		if raw is Dictionary:
			var p3: Array = (raw as Dictionary).get("pos_rot_km", [])
			var q := _project(_unit(p3), rect)
			if prev.x > -9000:
				canvas.draw_line(prev, q, P.a(P.AMBER, 0.9), 1.0)
			prev = q
	var first_u: Array = (timeline[0] as Dictionary).get("pos_rot_km", []) if timeline[0] is Dictionary else []
	var last_u: Array = (timeline[timeline.size() - 1] as Dictionary).get("pos_rot_km", []) if timeline[timeline.size() - 1] is Dictionary else []
	var l4 := _project(_unit(first_u), rect)
	var l1 := _project(_unit(last_u), rect)
	canvas.draw_circle(l4, 4.0, P.AMBER)
	canvas.draw_circle(l1, 4.0, P.PH)
	_label(canvas, l4 + Vector2(8, -8), "L4-02 HAMMER", P.AMBER, 7)
	_label(canvas, l1 + Vector2(8, -8), "L1 MERIDIAN", P.PH, 7)
	# fleet positions + velocity vectors
	var sample: Dictionary = {}
	if not fleet_samples.is_empty():
		sample = fleet_samples[0] if fleet_samples[0] is Dictionary else {}
	var ships: Array = sample.get("ships", []) if sample.get("ships", []) is Array else []
	for i in range(mini(7, ships.size())):
		var ship: Dictionary = ships[i]
		var pos3: Array = ship.get("pos_rot_km", [])
		var vel3: Array = ship.get("vel_rot_kmps", [])
		var pu := _unit(pos3)
		var sp := _project(pu, rect)
		var sid := String(ship.get("ship_id", ""))
		var sel := sid == String(selected_id) or String(ship.get("batch", "")) == String(selected_id)
		canvas.draw_circle(sp, 3.0 if not sel else 5.0, P.PH if not sel else P.AMBER)
		canvas.draw_arc(sp, 8.0 if sel else 6.0, 0, TAU, 20, P.a(P.PH, 0.45), 1.0, true)
		if vel3.size() >= 3:
			var v := _unit([float(vel3[0]) * 60.0, float(vel3[1]) * 60.0, float(vel3[2]) * 60.0]) - _unit([0, 0, 0])
			var q2 := _project(pu + v * 0.18, rect)
			canvas.draw_line(sp, q2, P.a(P.PH_DIM, 0.8), 1.0)
		_label(canvas, sp + Vector2(7, -6), sid if sid != "" else String(ship.get("batch", "")), P.PH if not sel else P.AMBER, 6)
	# station/contact markers from binder session entities
	var drawn := 0
	for raw in contacts:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var eid := String(c.get("entity_id", ""))
		if not entity_pos.has(eid):
			continue
		var p3c: Vector3 = entity_pos[eid]
		var spc := _project(p3c / span * 2.0, rect)
		if spc.x < rect.position.x or spc.x > rect.end.x or spc.y < rect.position.y or spc.y > rect.end.y:
			continue
		canvas.draw_rect(Rect2(spc - Vector2(3, 3), Vector2(6, 6)), P.a(P.AMBER, 0.8), false, 1.0)
		_label(canvas, spc + Vector2(7, -5), String(c.get("id", eid)), P.AMBER if String(c.get("id", "")) == String(selected_id) else P.PH_DIM, 6)
		drawn += 1
		if drawn >= 6:
			break
	# radar ring around fleet centroid
	var centroid := Vector3.ZERO
	var n := 0
	for raw in timeline:
		if raw is Dictionary:
			var p3r: Array = (raw as Dictionary).get("pos_rot_km", [])
			centroid += _unit(p3r)
			n += 1
	centroid /= maxf(1.0, float(n))
	var rc := _project(centroid, rect)
	canvas.draw_arc(rc, 54.0, 0, TAU, 64, P.a(P.AMBER, 0.28), 1.0, true)
	canvas.draw_arc(rc, 24.0, 0, TAU, 48, P.a(P.PH, 0.20), 1.0, true)
	_label(canvas, rc + Vector2(-10, -60), "RADAR RING · 360°", P.a(P.AMBER, 0.8), 6)
	# camera / legend
	canvas.draw_string(F.mono(), rect.position + Vector2(10, 16), "V1 PLOT3D · WIREFRAME · DATA TRANSFER CACHE / BINDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH, 0.9))
	canvas.draw_string(F.mono(), Vector2(rect.end.x - 220, rect.position.y + 16), "YAW %.2f · PITCH %.2f · DIST %.2f" % [yaw, pitch, dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.AMBER, 0.9))
	canvas.draw_string(F.mono(), Vector2(rect.position.x + 10, rect.end.y - 10), "DRAG ROTATE · WHEEL ZOOM · R RESET · CAMERA LOCAL ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))
	return true


func _draw_cic(canvas: CanvasItem, rect: Rect2, binder, selected_id: String) -> void:
	_label_pts.clear()
	_label_queue.clear()
	_label_boxes.clear()
	_label_boxes.clear()
	_plot_safe = Rect2(rect.position + Vector2(8, 26), rect.size - Vector2(16, 58))
	canvas.draw_rect(rect, P.a(P.EARTH, 0.38))
	canvas.draw_rect(rect, P.a(P.LINE, 0.65), false, 1.0)
	_draw_stars(canvas, rect)
	_draw_orbit_grid(canvas, rect)
	# 选中目标：相机 focus 平滑趋近（L2+ 用 estimate；L1 仅 ownship 方位，不读位置）
	_focus_target = Vector3.ZERO
	for raw_focus in cic_tracks:
		if raw_focus is Dictionary and String((raw_focus as Dictionary).get("id", "")) == selected_id:
			var est_focus: Array = (raw_focus as Dictionary).get("estimate_km", []) if (raw_focus as Dictionary).get("estimate_km", []) is Array else []
			if est_focus.size() >= 3:
				_focus_target = _unit(_rel_own(est_focus))
			break
	focus = focus.lerp(_focus_target, 0.16)
	canvas.draw_string(F.mono(), rect.position + Vector2(10, 16), "V1 PLOT3D · SOURCE CIC VIEW · truth=false · L1 bearing / L2 estimate", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH, 0.9))
	canvas.draw_string(F.mono(), Vector2(rect.end.x - 260, rect.position.y + 16), "YAW %.2f · PITCH %.2f · DIST %.2f" % [yaw, pitch, dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.AMBER, 0.9))
	# ownship known
	var own_screen := _project(_unit(own_cic), rect)
	canvas.draw_circle(own_screen, 5.0, P.PH)
	canvas.draw_arc(own_screen, 10.0, 0, TAU, 24, P.a(P.PH, 0.6), 1.0, true)
	_queue_label(own_screen + Vector2(9, -7), "OWNSHIP apsis · KNOWN", P.PH, 7, 3, "own")
	# Earth/Moon limbs
	for bk in ["earth", "moon"]:
		var b: Dictionary = bodies.get(bk, {}) if bodies.get(bk, {}) is Dictionary else {}
		var bp: Array = b.get("pos_km", []) if b.get("pos_km", []) is Array else []
		if bp.size() < 3:
			continue
		var sc := _project(_unit(_rel_own(bp)), rect)
		var rad_px := minf(rect.size.x, rect.size.y) * (0.052 if bk == "earth" else 0.027) * (2.8 / maxf(0.8, dist))
		_draw_body(canvas, sc, rad_px, P.PH if bk == "earth" else P.PH_DIM)
		_queue_label(sc + Vector2(rad_px + 8, -rad_px), String(b.get("label", bk.to_upper())) + " · " + String(b.get("source", "")), P.PH if bk == "earth" else P.PH_DIM, 6, 2, "body")
	# transfer/physics trajectory：分段投影，仅视觉参考，不参与 CIC 接触判断
	if not timeline.is_empty():
		var prev_t := Vector2(-9999, -9999)
		for raw_t in timeline:
			if raw_t is Dictionary:
				var tp: Array = (raw_t as Dictionary).get("pos_rot_km", [])
				var tq := _project(_unit(tp), rect)
				if prev_t.x > -9000:
					canvas.draw_line(prev_t, tq, P.a(P.AMBER, 0.22), 1.0)
					canvas.draw_circle(tq, 1.0, P.a(P.AMBER, 0.38))
				prev_t = tq
	# known L1 facilities from CIC
	for i in range(cic_facilities.size()):
		var f: Dictionary = cic_facilities[i]
		var fp: Array = f.get("pos_km", []) if f.get("pos_km", []) is Array else []
		if fp.size() < 3:
			continue
		var sp := _project(_unit(_rel_own(fp)), rect)
		if not rect.has_point(sp):
			continue
		var fv: Dictionary = {}
		for raw_v in facility_visual:
			if raw_v is Dictionary and String((raw_v as Dictionary).get("facility_id", "")) == String(f.get("facility_id", "")):
				fv = raw_v
				break
		var cls_f := String(fv.get("facility_class", "station"))
		_draw_station(canvas, sp, cls_f, 4.0, P.PH_DIM)
		_queue_label(sp + Vector2(7, -7), String(f.get("name", f.get("facility_id", ""))) + " · " + String(f.get("facility_code", "")), P.PH_DIM, 6, 1, "facility")
	# tracks from CIC only：L1 bearing，L2+ estimate+uncertainty；绝不读 session truth
	for raw in cic_tracks:
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		var level := int(tr.get("level", 1))
		var sel := tid == selected_id
		var bdeg = tr.get("bearing_deg", null)
		if level == 1:
			if bdeg == null:
				continue
			var b = float(bdeg)
			var cone := float(tr.get("uncertainty_deg", 2.0))
			var ray_len := span * 0.75
			var dir := Vector3(cos(deg_to_rad(b)) * ray_len, sin(deg_to_rad(b)) * ray_len, 0.0)
			var p1 := _project(_unit(own_cic) + dir / span * 2.0, rect)
			canvas.draw_line(own_screen, p1, P.a(P.PH if not sel else P.AMBER, 0.7), 1.0)
			var p2 := _project(_unit(own_cic) + Vector3(cos(deg_to_rad(b + cone)) * ray_len, sin(deg_to_rad(b + cone)) * ray_len, 0.0) / span * 2.0, rect)
			var p3 := _project(_unit(own_cic) + Vector3(cos(deg_to_rad(b - cone)) * ray_len, sin(deg_to_rad(b - cone)) * ray_len, 0.0) / span * 2.0, rect)
			canvas.draw_line(own_screen, p2, P.a(P.PH_DIM, 0.35), 1.0)
			canvas.draw_line(own_screen, p3, P.a(P.PH_DIM, 0.35), 1.0)
			_queue_label(p1 + Vector2(6, -8), "L1 " + tid + " · BEARING " + ("%.0f°" % b), P.PH if not sel else P.AMBER, 7, 2, "l1")
			continue
		var est: Array = tr.get("estimate_km", []) if tr.get("estimate_km", []) is Array else []
		if est.size() < 3:
			continue
		var sp2 := _project(_unit(_rel_own(est)), rect)
		if not rect.has_point(sp2):
			continue
		var unc := float(tr.get("uncertainty_km", 1.0)) if tr.get("uncertainty_km", null) != null else 1.0
		var rad2 := clampf(unc / maxf(1.0, span) * minf(rect.size.x, rect.size.y) * 1.8, 8.0, 90.0)
		canvas.draw_circle(sp2, 5.0 if sel else 3.0, P.AMBER if sel else P.PH)
		canvas.draw_arc(sp2, rad2, 0, TAU, 48, P.a(P.AMBER if sel else P.PH, 0.42), 1.0, true)
		canvas.draw_arc(sp2, rad2 * 0.55, 0, TAU, 32, P.a(P.PH, 0.22), 1.0, true)
		_queue_label(sp2 + Vector2(rad2 + 7, -7), "L%d %s · ±%.0fkm · %s/%s" % [level, tid, unc, String(tr.get("identity", "unknown")), String(tr.get("threat", "unknown"))], P.AMBER if sel else P.PH, 7, 3 if sel else 2, "l2")
	# summary footer
	var summary: Dictionary = cic.get("summary", {}) if cic.get("summary", {}) is Dictionary else {}
	_flush_labels(canvas)
	canvas.draw_string(F.mono(), Vector2(rect.position.x + 10, rect.end.y - 10), "CIC tracks %d · levels %s · truth=false · L1 bearing-only / L2+ estimate" % [cic_tracks.size(), str(summary.get("levels", {}))], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))
	canvas.draw_string(F.mono(), Vector2(rect.position.x + 10, rect.end.y - 22), "VISUAL · STARFIELD / ORBITAL GRID / LIMB LAT-LONG / LOW-POLY FACILITIES / FOCUS SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.PH_DIM, 0.75))


func _draw_stars(canvas: CanvasItem, rect: Rect2) -> void:
	for i in range(72):
		var hh := (i * 1103515245 + 12345) & 0x7fffffff
		var sx := rect.position.x + 8.0 + float(hh % int(maxf(1.0, rect.size.x - 16.0)))
		var sy := rect.position.y + 8.0 + float((hh / 97) % int(maxf(1.0, rect.size.y - 16.0)))
		var a := 0.08 + 0.10 * float(i % 4)
		canvas.draw_rect(Rect2(sx, sy, 1, 1), P.a(P.TXT, a))


func _draw_orbit_grid(canvas: CanvasItem, rect: Rect2) -> void:
	# L1 参考环 / 基准十字，透视椭圆
	var own_screen := _project(_unit(own_cic), rect)
	for rr in [42.0, 84.0]:
		_draw_ellipse(canvas, own_screen, rr, rr * 0.30, P.a(P.AMBER, 0.20))
		_draw_ellipse(canvas, own_screen, rr * 0.30, rr, P.a(P.PH, 0.12))
	canvas.draw_line(own_screen + Vector2(-26, 0), own_screen + Vector2(26, 0), P.a(P.AMBER, 0.35), 1.0)
	canvas.draw_line(own_screen + Vector2(0, -26), own_screen + Vector2(0, 26), P.a(P.AMBER, 0.35), 1.0)
	# Earth 参考轨道环
	for bk in ["earth", "moon"]:
		var b: Dictionary = bodies.get(bk, {}) if bodies.get(bk, {}) is Dictionary else {}
		var bp: Array = b.get("pos_km", []) if b.get("pos_km", []) is Array else []
		if bp.size() < 3:
			continue
		var bc := _project(_unit(_rel_own(bp)), rect)
		_draw_ellipse(canvas, bc, 28.0, 8.0, P.a(P.PH if bk == "earth" else P.PH_DIM, 0.18))
		_draw_ellipse(canvas, bc, 8.0, 28.0, P.a(P.PH_DIM, 0.12))


func _draw_station(canvas: CanvasItem, c: Vector2, cls: String, scale: float, col: Color) -> void:
	var r := clampf(scale, 3.0, 8.0)
	match cls:
		"otc", "relay":
			var pts := PackedVector2Array()
			for i in range(7):
				var a := TAU * float(i) / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 1.4)
			canvas.draw_polyline(pts, P.a(col, 0.75), 1.0)
			canvas.draw_line(c + Vector2(-r * 2.0, 0), c + Vector2(r * 2.0, 0), P.a(col, 0.55), 1.0)
			canvas.draw_line(c + Vector2(-r * 2.0, -r * 0.25), c + Vector2(-r * 2.0, r * 0.25), P.a(col, 0.55), 1.0)
			canvas.draw_line(c + Vector2(r * 2.0, -r * 0.25), c + Vector2(r * 2.0, r * 0.25), P.a(col, 0.55), 1.0)
		"tank", "fuel", "depot":
			var top := c + Vector2(0, -r)
			var bot := c + Vector2(0, r * 1.3)
			canvas.draw_arc(top, r * 0.8, 0, TAU, 24, P.a(col, 0.7), 1.0, true)
			canvas.draw_line(top + Vector2(-r * 0.8, 0), bot + Vector2(-r * 0.8, 0), P.a(col, 0.6), 1.0)
			canvas.draw_line(top + Vector2(r * 0.8, 0), bot + Vector2(r * 0.8, 0), P.a(col, 0.6), 1.0)
			_draw_ellipse(canvas, bot, r * 0.8, r * 0.25, P.a(col, 0.6))
		"station", "commercial", "port", "logistics":
			canvas.draw_rect(Rect2(c - Vector2(r * 1.2, r * 0.7), Vector2(r * 2.4, r * 1.4)), P.a(col, 0.65), false, 1.0)
			_draw_ellipse(canvas, c + Vector2(0, -r * 0.7), r * 1.2, r * 0.30, P.a(col, 0.55))
			_draw_ellipse(canvas, c + Vector2(0, r * 0.7), r * 1.2, r * 0.30, P.a(col, 0.55))
			for sx in [-r * 1.7, r * 1.7]:
				canvas.draw_line(c + Vector2(sx, 0), c + Vector2(sx * 0.7, 0), P.a(col, 0.5), 1.0)
		_:
			canvas.draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), P.a(col, 0.6), false, 1.0)


func _draw_physics(canvas: CanvasItem, rect: Rect2, binder, selected_id: String) -> void:
	_label_pts.clear()
	_label_queue.clear()
	_label_boxes.clear()
	_plot_safe = Rect2(rect.position + Vector2(8, 26), rect.size - Vector2(16, 58))
	canvas.draw_rect(rect, P.a(P.EARTH, 0.38))
	canvas.draw_rect(rect, P.a(P.LINE, 0.65), false, 1.0)
	for i in range(20):
		var gx := rect.position.x + rect.size.x * float(i) / 20.0
		canvas.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), P.a(P.LINE, 0.06), 1.0)
	for j in range(12):
		var gy := rect.position.y + rect.size.y * float(j) / 12.0
		canvas.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), P.a(P.LINE, 0.06), 1.0)
	canvas.draw_string(F.mono(), rect.position + Vector2(10, 16), "V1 PLOT3D · SOURCE SESSION PHYSICS / " + String(bodies.get("source", "—")) + " · POSITIONS RELATIVE FLAGSHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH, 0.9))
	canvas.draw_string(F.mono(), Vector2(rect.end.x - 260, rect.position.y + 16), "YAW %.2f · PITCH %.2f · DIST %.2f" % [yaw, pitch, dist], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.AMBER, 0.9))
	# Earth / Moon limbs from plot_bodies (physics bary, relative flagship)
	for bk in ["earth", "moon"]:
		var b: Dictionary = bodies.get(bk, {}) if bodies.get(bk, {}) is Dictionary else {}
		var bp: Array = b.get("pos_km", []) if b.get("pos_km", []) is Array else []
		if bp.size() < 3:
			continue
		var sc := _project(_unit(bp), rect)
		var rad_px := minf(rect.size.x, rect.size.y) * (0.055 if bk == "earth" else 0.028) * (2.8 / maxf(0.8, dist))
		_draw_body(canvas, sc, rad_px, P.PH if bk == "earth" else P.PH_DIM)
		_queue_label(sc + Vector2(rad_px + 8, -rad_px), str(b.get("label", bk.to_upper())) + " · r=" + str(b.get("radius_km", "")) + "km", P.PH if bk == "earth" else P.PH_DIM, 7, 2, "body")
	# facility symbols
	var fac_cols := {"station": P.PH, "depot": P.AMBER, "port": P.BLUE, "otc": P.PH_DIM, "tank": P.AMBER, "fuel": P.AMBER, "commercial": P.PH}
	for i in range(facility_rows.size()):
		var f: Dictionary = facility_rows[i]
		var p: Array = f.get("pos_km", [])
		if p.size() < 3:
			continue
		var sp := _project(_unit(p), rect)
		if sp.x < rect.position.x or sp.x > rect.end.x or sp.y < rect.position.y or sp.y > rect.end.y:
			continue
		var cls := String(f.get("facility_class", "station"))
		var col: Color = fac_cols.get(cls, P.PH_DIM)
		canvas.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), P.a(col, 0.7), false, 1.0)
		canvas.draw_line(sp + Vector2(-7, 0), sp + Vector2(7, 0), P.a(col, 0.5), 1.0)
		canvas.draw_line(sp + Vector2(0, -7), sp + Vector2(0, 7), P.a(col, 0.5), 1.0)
		_queue_label(sp + Vector2(7, -7), String(f.get("name", f.get("facility_id", ""))) + " · " + String(f.get("facility_code", "")), col, 6, 1, "facility")
	# fleet / physics entities
	for i in range(physics_rows.size()):
		var row: Dictionary = physics_rows[i]
		var p2: Array = row.get("pos_km", [])
		if p2.size() < 3:
			continue
		var sp2 := _project(_unit(p2), rect)
		var sid := String(row.get("id", ""))
		var sel := sid == selected_id
		if sp2.x < rect.position.x or sp2.x > rect.end.x or sp2.y < rect.position.y or sp2.y > rect.end.y:
			continue
		canvas.draw_circle(sp2, 5.0 if sel else 3.0, P.AMBER if sel else P.PH)
		canvas.draw_arc(sp2, 9.0 if sel else 6.0, 0, TAU, 24, P.a(P.PH, 0.5), 1.0, true)
		var vel: Array = row.get("vel_kmps", []) if row.get("vel_kmps", []) is Array else []
		if vel.size() >= 3:
			var vv := Vector3(float(vel[0]), float(vel[1]), float(vel[2])) * 900.0
			var q := _project(_unit(p2) + vv / span * 2.0, rect)
			canvas.draw_line(sp2, q, P.a(P.PH_DIM, 0.8), 1.0)
		_queue_label(sp2 + Vector2(7, -7), sid + " · " + ("%.0f km" % Vector3(float(p2[0]), float(p2[1]), float(p2[2])).length()), P.AMBER if sel else P.PH, 6, 3 if sel else 2, "ship")
	# radar ring around flagship / origin
	var origin := _project(Vector3.ZERO, rect)
	canvas.draw_arc(origin, 30.0, 0, TAU, 48, P.a(P.AMBER, 0.30), 1.0, true)
	canvas.draw_arc(origin, 56.0, 0, TAU, 64, P.a(P.PH, 0.16), 1.0, true)
	_queue_label(origin + Vector2(-8, -34), "FLAGSHIP / RADAR RING", P.a(P.AMBER, 0.8), 6, 2, "radar")
	_flush_labels(canvas)
	canvas.draw_string(F.mono(), Vector2(rect.position.x + 10, rect.end.y - 10), "DRAG ROTATE · WHEEL ZOOM · R RESET · LABELS selected>ships>facilities", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _draw_body(canvas: CanvasItem, c: Vector2, rad: float, col: Color) -> void:
	# limb + day/night terminator + lat/long grid + tick marks（纯线框，无贴图）
	canvas.draw_arc(c, rad, 0, TAU, 96, P.a(col, 0.78), 1.0, true)
	canvas.draw_arc(c, rad * 0.62, 0, TAU, 64, P.a(col, 0.22), 1.0, true)
	canvas.draw_line(c + Vector2(-rad, 0), c + Vector2(rad, 0), P.a(col, 0.38), 1.0)
	canvas.draw_line(c + Vector2(0, -rad), c + Vector2(0, rad), P.a(col, 0.38), 1.0)
	for k in [-0.65, -0.3, 0.3, 0.65]:
		_draw_ellipse(canvas, c + Vector2(0, rad * float(k)), rad * sqrt(maxf(0.05, 1.0 - float(k) * float(k))), rad * 0.12, P.a(col, 0.20))
	for k2 in [-0.65, -0.25, 0.25, 0.65]:
		_draw_ellipse(canvas, c, rad * 0.14, rad * sqrt(maxf(0.05, 1.0 - float(k2) * float(k2))), P.a(col, 0.16))
	# terminator：夜侧弧
	canvas.draw_arc(c, rad, PI * 0.5, PI * 1.5, 32, P.a(col, 0.36), 1.0, true)
	# 刻度
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p0 := c + Vector2(cos(a), sin(a)) * (rad - 3.0)
		var p1 := c + Vector2(cos(a), sin(a)) * (rad + 3.0)
		canvas.draw_line(p0, p1, P.a(col, 0.35), 1.0)
		if i % 3 == 0:
			canvas.draw_string(F.mono(), p1 + Vector2(3, 4), "%d°" % (i * 30), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, P.a(col, 0.55))


func _draw_ellipse(canvas: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(33):
		var a := TAU * float(i) / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	canvas.draw_polyline(pts, col, 1.0)


func _draw_limb(canvas: CanvasItem, rect: Rect2, u: Vector3, rad_u: float, col: Color, label: String) -> void:
	var c := _project(u, rect)
	if c.x < -1000:
		return
	var r := maxf(12.0, (minf(rect.size.x, rect.size.y) * 0.06 if rad_u > 0.02 else minf(rect.size.x, rect.size.y) * 0.03) * (2.8 / maxf(0.8, dist)))
	canvas.draw_arc(c, r, 0, TAU, 64, P.a(col, 0.55), 1.0, true)
	canvas.draw_arc(c, r * 0.62, 0, TAU, 48, P.a(col, 0.25), 1.0, true)
	canvas.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), P.a(col, 0.22), 1.0)
	canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, r), P.a(col, 0.22), 1.0)
	_label(canvas, c + Vector2(r + 6, -r), label, col, 6)
