extends Control

# 阶段3D 导航图：真实 L4-02→L1 timeline + 5 舰 fleet cache sample + 窗口/时间轴。
# 只读；不绘制假地图，不自动推进。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var controller = null
var _pr := {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_controller(c) -> void:
	controller = c
	queue_redraw()


func _point(pos: Array, pr: Dictionary) -> Vector2:
	if pos.size() < 3 or pr.is_empty():
		return Vector2.ZERO
	var x := float(pr.x0) + (float(pos[0]) - float(pr.minx)) / maxf(1.0, float(pr.spanx)) * float(pr.w)
	var y := float(pr.y0) + (float(pr.maxy) - float(pos[1])) / maxf(1.0, float(pr.spany)) * float(pr.h)
	return Vector2(x, y)


func _fleet_at(t_s: float) -> Array:
	if controller == null:
		return []
	var samples: Array = controller.fleet_cache.get("samples", []) if controller.fleet_cache.get("samples", []) is Array else []
	if samples.is_empty():
		return []
	var a: Dictionary = samples[0]
	var b: Dictionary = samples[samples.size() - 1]
	for i in range(samples.size() - 1):
		var s0: Dictionary = samples[i]
		var s1: Dictionary = samples[i + 1]
		if float(s0.get("t_s", 0.0)) <= t_s and float(s1.get("t_s", 0.0)) >= t_s:
			a = s0
			b = s1
			break
	var t0 := float(a.get("t_s", 0.0))
	var t1 := float(b.get("t_s", 1.0))
	var u := 0.0 if t1 <= t0 else clampf((t_s - t0) / (t1 - t0), 0.0, 1.0)
	var out: Array = []
	var sa: Array = a.get("ships", []) if a.get("ships") is Array else []
	var sb: Array = b.get("ships", []) if b.get("ships") is Array else []
	for i in range(mini(sa.size(), sb.size())):
		var ship: Dictionary = sa[i]
		var other: Dictionary = sb[i]
		var pa: Array = ship.get("pos_rot_km", []) if ship.get("pos_rot_km") is Array else []
		var pb: Array = other.get("pos_rot_km", []) if other.get("pos_rot_km") is Array else []
		if pa.size() >= 3 and pb.size() >= 3:
			out.append({"ship_id": String(ship.get("ship_id", "")), "batch": String(ship.get("batch", "")),
				"pos_km": [lerpf(float(pa[0]), float(pb[0]), u), lerpf(float(pa[1]), float(pb[1]), u), lerpf(float(pa[2]), float(pb[2]), u)]})
	return out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, P.a(P.EARTH, 0.7))
	draw_rect(r, P.a(P.LINE, 0.6), false, 1.0)
	var cjk := F.cjk()
	var mono := F.mono()
	if controller == null:
		draw_string(cjk, Vector2(24, 32), "NAVIGATION NOT READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.AMBER)
		return
	var tl: Array = controller.timeline()
	var pts: Array = []
	for raw in tl:
		if raw is Dictionary and (raw as Dictionary).get("flagship_pos_km", []) is Array and ((raw as Dictionary).get("flagship_pos_km", []) as Array).size() >= 3:
			pts.append((raw as Dictionary).get("flagship_pos_km"))
	if pts.is_empty():
		draw_string(cjk, Vector2(24, 32), "TRANSFER TIMELINE NOT READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.AMBER)
		return
	var minx := 1.0e30
	var maxx := -1.0e30
	var miny := 1.0e30
	var maxy := -1.0e30
	for raw in pts:
		var p: Array = raw
		minx = minf(minx, float(p[0])); maxx = maxf(maxx, float(p[0]))
		miny = minf(miny, float(p[1])); maxy = maxf(maxy, float(p[1]))
	var pad := 80.0
	_pr = {"x0": pad, "y0": 110.0, "w": maxf(1.0, size.x - pad * 2.0), "h": maxf(1.0, size.y - 250.0),
		"minx": minx, "maxy": maxy, "spanx": maxf(1.0, maxx - minx), "spany": maxf(1.0, maxy - miny)}
	# 固定星点
	for i in range(160):
		var hh := (i * 1103515245 + 12345) & 0x7fffffff
		var sx := 12.0 + float(hh % int(maxf(1.0, size.x - 24.0)))
		var sy := 12.0 + float((hh / 97) % int(maxf(1.0, size.y - 160.0)))
		draw_rect(Rect2(sx, sy, 1, 1), P.a(P.TXT, 0.07 + 0.05 * float(i % 3)))
	# 轨迹
	var prev := Vector2.ZERO
	for i in range(pts.size()):
		var q := _point(pts[i], _pr)
		if i > 0:
			draw_line(prev, q, P.a(P.AMBER, 0.8), 1.0)
		draw_circle(q, 2.0, P.a(P.AMBER, 0.85))
		prev = q
	draw_string(mono, _point(pts[0], _pr) + Vector2(8, -8), "L4-02 HAMMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.AMBER)
	draw_string(mono, _point(pts[pts.size() - 1], _pr) + Vector2(8, 18), "L1 MERIDIAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.PH)
	# 5 舰当前真实 sample
	var ships := _fleet_at(float(controller.t_s))
	for i in range(ships.size()):
		var ship: Dictionary = ships[i]
		var q := _point(ship.get("pos_km", []), _pr)
		var c: Color = P.PH if String(ship.get("ship_id", "")) == "apsis" else P.PH_DIM
		draw_circle(q, 3.0, c)
		var lp := q + Vector2(10.0, -12.0 + float(i) * 9.0)
		draw_line(q, Vector2(lp.x - 3.0, lp.y), P.a(c, 0.35), 1.0)
		draw_string(mono, lp, "%s %s" % [String(ship.get("batch", "")), String(ship.get("ship_id", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(c, 0.9))
	# 时间轴/窗口
	var ty := size.y - 126.0
	draw_line(Vector2(24, ty), Vector2(size.x - 24, ty), P.a(P.LINE2, 0.8), 1.0)
	var tof := maxf(1.0, float(controller.tof_s))
	var wx0 := 24.0 + (float(controller.WINDOW_OPEN_S) / tof) * (size.x - 48.0)
	var wx1 := 24.0 + (float(controller.WINDOW_CLOSE_S) / tof) * (size.x - 48.0)
	draw_rect(Rect2(wx0, ty - 5, maxf(1.0, wx1 - wx0), 10), P.a(P.AMBER, 0.10))
	draw_line(Vector2(wx0, ty - 8), Vector2(wx0, ty + 8), P.a(P.AMBER, 0.85), 1.0)
	draw_line(Vector2(wx1, ty - 8), Vector2(wx1, ty + 8), P.a(P.AMBER, 0.85), 1.0)
	var nx := 24.0 + clampf(float(controller.t_s) / tof, 0.0, 1.0) * (size.x - 48.0)
	draw_line(Vector2(nx, ty - 12), Vector2(nx, ty + 12), P.a(P.PH, 0.9), 1.0)
	draw_string(mono, Vector2(24, ty - 16), "T+%s / TOF %s" % [_clock(float(controller.t_s)), _clock(tof)], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	draw_string(mono, Vector2(wx0 - 20, ty + 25), "WINDOW OPEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.AMBER, 0.9))
	draw_string(mono, Vector2(wx1 - 20, ty + 35), "CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.AMBER, 0.9))
	draw_string(mono, Vector2(24, size.y - 20), "REAL FLEET CACHE SAMPLE · TIMELINE %d 点 · SCHEMATIC FRAME" % tl.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _clock(s: float) -> String:
	var sec := int(maxf(0.0, s))
	return "%02d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
