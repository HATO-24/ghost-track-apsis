extends RefCounted

# 方案B-24：V1 线框 3D 战术图。
# 只读：transfer cache timeline/samples + binder contacts/session entities + facility markers；
# 不读旧 plot state；不写 world/物理。鼠标拖拽旋转、滚轮缩放、R 重置。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")

const TRANSFER_PATH := "res://framework/content/transfer_l4_l1_cached.json"
const FLEET_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"

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
	timeline = []
	fleet_samples = []
	contacts = []
	entity_pos = {}
	_load_json_arrays()
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
	var cy := cos(yaw)
	var sy := sin(yaw)
	var x := u.x * cy + u.z * sy
	var z := -u.x * sy + u.z * cy
	var cp := cos(pitch)
	var sp := sin(pitch)
	var yy := u.y * cp - z * sp
	var zz := u.y * sp + z * cp
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
