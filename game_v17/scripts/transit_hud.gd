extends Control

# 阶段2-SCENE-1：转场 V1 HUD（只读 planner 数据 + 本地时间控制）。
# 1920×1080；不接旧 Chronos HUD；传感器桥未接时固定显示 SENSOR BRIDGE NOT WIRED。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const C := preload("res://framework/sim/cislunar_physics.gd")

const HEADER := Rect2(40, 40, 1840, 72)
const FLEET := Rect2(60, 124, 320, 752)
const MAP := Rect2(396, 124, 1128, 752)
const SIDE := Rect2(1540, 124, 320, 752)
const BOTTOM := Rect2(60, 884, 1120, 156)
const CTRL := Rect2(1200, 884, 660, 156)
const BTN_PAUSE := Rect2(1216, 920, 110, 22)
const BTN_1X := Rect2(1336, 920, 54, 22)
const BTN_100X := Rect2(1396, 920, 58, 22)
const BTN_1000X := Rect2(1460, 920, 66, 22)
const BTN_10000X := Rect2(1532, 920, 72, 22)
const BTN_IGN := Rect2(1216, 952, 120, 22)
const BTN_ARR := Rect2(1344, 952, 120, 22)
const BTN_REPLAY := Rect2(1472, 952, 120, 22)

var sim
var mono: Font
var cjk: Font


func _ready() -> void:
	mono = F.mono()
	cjk = F.cjk()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _panel(r: Rect2) -> void:
	draw_rect(r, P.a(P.BG, 0.94))
	draw_rect(r, P.a(P.LINE, 0.72), false, 1.0)


func _txt(f: Font, x: float, y: float, s: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_r(f: Font, x: float, y: float, s: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_RIGHT, -1, size, col)


func _ellipsis(f: Font, s: String, size: int, maxw: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= maxw:
		return s
	var out := s
	while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw:
		out = out.substr(0, out.length() - 1)
	return out + "…"


func _btn(r: Rect2, label: String, active: bool, col: Color) -> void:
	draw_rect(r, P.a(col, 0.10 if active else 0.035))
	draw_rect(r, P.a(col, 0.65 if active else 0.25), false, 1.0)
	_txt(cjk, r.position.x + 6.0, r.position.y + 5.0, label, 7, P.a(col, 0.95 if active else 0.55))


func _v3(raw: Variant) -> Vector3:
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return Vector3.ZERO


func _tl() -> Array:
	if sim == null:
		return []
	var plan: Dictionary = sim.plan if sim.plan is Dictionary else {}
	return plan.get("timeline", []) if plan.get("timeline", []) is Array else []


func _frac() -> float:
	if sim == null or float(sim.tof_s) <= 0.0:
		return 0.0
	return clampf(float(sim.t) / float(sim.tof_s), 0.0, 1.0)


func _interp_pos(frac: float) -> Vector3:
	var tl := _tl()
	if tl.is_empty():
		return Vector3.ZERO
	var f := clampf(frac, 0.0, 1.0)
	var n := tl.size()
	if n == 1:
		return _v3((tl[0] as Dictionary).get("pos_rot_km", []))
	var x := f * float(n - 1)
	var i := mini(int(floor(x)), n - 2)
	var a: Vector3 = _v3((tl[i] as Dictionary).get("pos_rot_km", []))
	var b: Vector3 = _v3((tl[i + 1] as Dictionary).get("pos_rot_km", []))
	return a.lerp(b, clampf(x - float(i), 0.0, 1.0))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), P.BG)
	var plan: Dictionary = sim.plan if sim != null and sim.plan is Dictionary else {}
	var ok := bool(plan.get("ok", false))
	var tl := _tl()
	var tr: Dictionary = plan.get("transfer", {}) if plan.get("transfer", {}) is Dictionary else {}
	var budget: Dictionary = plan.get("budget", {}) if plan.get("budget", {}) is Dictionary else {}
	var arrival: Dictionary = plan.get("arrival", {}) if plan.get("arrival", {}) is Dictionary else {}
	var title := String((sim.scenario as Dictionary).get("title", "阶段2 · L4-02 Hammer → L1 Meridian")) if sim != null else "阶段2 · 转场"
	# Header
	_panel(HEADER)
	_txt(cjk, 60, 56, "阶段2 · 转场 / TRANSIT", 12, P.PH)
	_txt(cjk, 60, 74, "L4-02 HAMMER → L1 MERIDIAN · 真实 CR3BP/Lambert 转移 · V1", 7, P.a(P.DIM, 0.95))
	_txt_r(mono, 1848, 56, "T+%.0f s / %.2f d · %s" % [float(sim.t) if sim != null else 0.0,
		float(sim.t) / 86400.0 if sim != null else 0.0, String(sim.phase) if sim != null else "not_ready"], 8,
		P.PH if ok else P.AMBER)
	_txt_r(cjk, 1848, 74, "PLANNER %s · NOT WIRED TO SENSORS" % ("OK" if ok else "NOT READY"), 7, P.PH if ok else P.AMBER)
	# Left fleet
	_panel(FLEET)
	_txt(cjk, FLEET.position.x + 12, FLEET.position.y + 18, "舰队 / FLEET · 5 舰", 9, P.PH)
	_txt_r(mono, FLEET.end.x - 12, FLEET.position.y + 18, "共享转移 + 小偏移", 7, P.a(P.FAINT, 0.9))
	draw_line(Vector2(FLEET.position.x + 12, FLEET.position.y + 26), Vector2(FLEET.end.x - 12, FLEET.position.y + 26), P.a(P.LINE, 0.7), 1.0)
	var fleet: Array = plan.get("fleet", []) if plan.get("fleet", []) is Array else []
	var fleet_dv := float((plan.get("budget", {}) as Dictionary).get("total_dv_mps", 0.0)) if plan.get("budget", {}) is Dictionary else 0.0
	var names := {"apsis": "远地点 / APSIS", "harmattan": "哈马丹 / HARMATTAN", "ferry": "渡口 / FERRY",
		"watchtower": "望楼 / WATCHTOWER", "deepwell": "深井 / DEEPWELL"}
	var roles := {"flagship": "旗舰", "command": "哨舰", "escort": "炮舰", "relay": "中继", "tanker": "油船"}
	var y := FLEET.position.y + 42.0
	for raw in fleet:
		var ship: Dictionary = raw
		var sid := String(ship.get("id", ""))
		var role := String(ship.get("role", ""))
		var col := P.PH if sid == "apsis" else P.PH_DIM
		_txt(mono, FLEET.position.x + 12, y, "[%s]" % String(ship.get("batch", "")), 8, P.a(col, 0.9))
		_txt(cjk, FLEET.position.x + 52, y, _ellipsis(cjk, String(names.get(sid, sid)), 9, 210.0), 9, P.TXT)
		y += 14.0
		_txt(cjk, FLEET.position.x + 52, y, "%s · 偏移 %.0f km · Δv %.0f m/s · %s" % [String(roles.get(role, role)),
			_v3(ship.get("offset_km", [])).length(), fleet_dv, _phase_label()], 7, P.a(P.DIM, 0.95))
		y += 12.0
		var eta := maxf(0.0, float(sim.tof_s) - float(sim.t)) if sim != null else 0.0
		_txt(mono, FLEET.position.x + 52, y, "ETA %s · gate_err %.1f km" % [_hms(eta), float(ship.get("arrival_error_km", -1.0))], 7, P.a(P.FAINT, 0.9))
		y += 24.0
	_txt(cjk, FLEET.position.x + 12, FLEET.end.y - 50, "教学：阶段2转场 / 手动目标", 7, P.a(P.PH_DIM, 0.9))
	_txt(cjk, FLEET.position.x + 12, FLEET.end.y - 34, "按 SPACE 暂停 · 数字键 1–4 时标 · R 重播", 7, P.FAINT)
	var sensor_ok := false
	_txt(cjk, FLEET.position.x + 12, FLEET.end.y - 18,
		"SENSOR BRIDGE NOT WIRED" if not sensor_ok else "SENSOR BRIDGE · READY", 7, P.AMBER)
	# Map
	_panel(MAP)
	_draw_map(plan, ok, tl)
	# Right mission
	_panel(SIDE)
	_txt(cjk, SIDE.position.x + 12, SIDE.position.y + 18, "任务 / TRANSFER", 9, P.PH)
	_txt_r(mono, SIDE.end.x - 12, SIDE.position.y + 18, "REAL", 7, P.a(P.FAINT, 0.9))
	draw_line(Vector2(SIDE.position.x + 12, SIDE.position.y + 26), Vector2(SIDE.end.x - 12, SIDE.position.y + 26), P.a(P.LINE, 0.7), 1.0)
	var sy := SIDE.position.y + 44.0
	var from_s := String((plan.get("source", {}) as Dictionary).get("name", "L4-02 Hammer")) if plan.get("source", {}) is Dictionary else "L4-02 Hammer"
	var to_s := String((plan.get("target", {}) as Dictionary).get("name", "L1-Meridian-05")) if plan.get("target", {}) is Dictionary else "L1-Meridian-05"
	_txt(cjk, SIDE.position.x + 12, sy, "FROM  " + from_s, 8, P.AMBER)
	sy += 16.0
	_txt(cjk, SIDE.position.x + 12, sy, "TO    " + to_s, 8, P.PH)
	sy += 22.0
	_txt(mono, SIDE.position.x + 12, sy, "TOF %s · %.1f d" % [_hms(float(tr.get("tof_s", 0.0))), float(tr.get("tof_days", 0.0))], 8, P.TXT)
	sy += 16.0
	_txt(mono, SIDE.position.x + 12, sy, "Δv TOTAL %.1f m/s" % float(budget.get("total_dv_mps", 0.0)), 8, P.AMBER)
	sy += 14.0
	_txt(mono, SIDE.position.x + 12, sy, "  DEPART %.1f · ARRIVE %.1f · MCC %.1f" % [
		float(budget.get("depart_dv_mps", 0.0)), float(budget.get("arrival_dv_mps", 0.0)),
		float(budget.get("mcc_dv_mps", 0.0))], 7, P.DIM)
	sy += 18.0
	_txt(mono, SIDE.position.x + 12, sy, "ARRIVAL ERR %.1f km · %.2f km/s" % [
		float(arrival.get("radius_km", 0.0)), float(arrival.get("relative_speed_kmps", 0.0))], 7,
		P.PH if bool(arrival.get("ok", false)) else P.AMBER)
	sy += 14.0
	_txt(mono, SIDE.position.x + 12, sy, "GATE %.0f km / %.1f km/s · %s" % [
		float(arrival.get("gate_radius_km", 3000.0)), float(arrival.get("gate_speed_kmps", 3.0)),
		"PASS" if bool(arrival.get("ok", false)) else "FAIL"], 7, P.PH if bool(arrival.get("ok", false)) else P.AMBER)
	sy += 22.0
	draw_line(Vector2(SIDE.position.x + 12, sy), Vector2(SIDE.end.x - 12, sy), P.a(P.LINE, 0.6), 1.0)
	sy += 14.0
	_txt(cjk, SIDE.position.x + 12, sy, "阶段 / PHASE", 7, P.FAINT)
	sy += 16.0
	for pair in [["departure", "出发 / DEPARTURE", 0.0], ["cruise", "巡航 / CRUISE", 0.02], ["arrival", "到达 / ARRIVAL", 0.98]]:
		var pcol: Color = P.PH if String(sim.phase) == String(pair[0]) else P.FAINT
		_txt(cjk, SIDE.position.x + 12, sy, _phase_glyph(String(pair[0])) + " " + String(pair[1]), 8, pcol)
		sy += 14.0
	sy += 8.0
	var warn: Array = plan.get("warnings", []) if plan.get("warnings", []) is Array else []
	if not warn.is_empty():
		_txt(cjk, SIDE.position.x + 12, sy, _ellipsis(cjk, "WARN " + String(warn[0]), 7, 290.0), 7, P.AMBER)
		sy += 14.0
	# V15 传感器/光学小窗占位（明确未接，不伪造）
	var sr := Rect2(SIDE.position.x + 12, SIDE.end.y - 162, SIDE.size.x - 24, 88)
	_panel(sr)
	_txt(cjk, sr.position.x + 8, sr.position.y + 14, "传感器 / 光学小窗", 8, P.PH_DIM)
	_txt(mono, sr.position.x + 8, sr.position.y + 30, "SENSOR BRIDGE NOT WIRED", 8, P.AMBER)
	_txt(cjk, sr.position.x + 8, sr.position.y + 46, "占位：未接 fw_optical_ir / sensor bridge", 7, P.FAINT)
	_txt(cjk, sr.position.x + 8, sr.position.y + 60, "不伪造 FOV/SNR/锁定/遮挡；下一步接入", 7, P.a(P.AMBER, 0.8))
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 64, "PLANNER", 7, P.FAINT)
	_txt(mono, SIDE.position.x + 12, SIDE.end.y - 50, "transfer_planner.plan()", 7, P.TXT)
	_txt(mono, SIDE.position.x + 12, SIDE.end.y - 36, "frame: bary_rot / earth_eci", 7, P.a(P.FAINT, 0.9))
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 18, "传感器桥未接：SENSOR BRIDGE NOT WIRED", 7, P.AMBER)
	# Bottom timeline
	_panel(BOTTOM)
	_txt(cjk, BOTTOM.position.x + 12, BOTTOM.position.y + 16, "时间轴 / TIMELINE", 8, P.PH)
	_txt_r(mono, BOTTOM.end.x - 12, BOTTOM.position.y + 16, "departure → cruise → arrival", 7, P.a(P.FAINT, 0.9))
	var x0 := BOTTOM.position.x + 16.0
	var x1 := BOTTOM.end.x - 16.0
	var ty := BOTTOM.position.y + 66.0
	draw_line(Vector2(x0, ty), Vector2(x1, ty), P.a(P.LINE, 0.9), 1.0)
	for i in range(9):
		var xx := x0 + (x1 - x0) * float(i) / 8.0
		draw_line(Vector2(xx, ty - 5.0), Vector2(xx, ty), P.a(P.PH_DIM, 0.7), 1.0)
		_txt(mono, xx - 12.0, ty + 12.0, _hms(float(sim.tof_s) * float(i) / 8.0) if sim != null else "—", 7, P.FAINT)
	var nowx := x0 + (x1 - x0) * _frac()
	draw_line(Vector2(nowx, ty - 12.0), Vector2(nowx, ty + 4.0), P.PH, 2.0)
	_txt(mono, nowx + 4.0, ty + 24.0, "NOW T+%s" % _hms(float(sim.t) if sim != null else 0.0), 7, P.PH)
	_txt(cjk, x0, ty + 36.0, "出发 0 · 巡航 %.0f%% · 到达 T+%s" % [_frac() * 100.0, _hms(float(sim.tof_s) if sim != null else 0.0)], 7, P.DIM)
	# Controls
	_panel(CTRL)
	var paused := not bool(sim.playing) if sim != null else true
	_txt(cjk, CTRL.position.x + 16, CTRL.position.y + 16, "控制 / CONTROL", 8, P.PH)
	_btn(BTN_PAUSE, "SPACE " + ("暂停" if paused else "播放"), true, P.AMBER)
	_btn(BTN_1X, "1×", _speed_is(1.0), P.PH)
	_btn(BTN_100X, "100×", _speed_is(100.0), P.PH)
	_btn(BTN_1000X, "1000×", _speed_is(1000.0), P.PH)
	_btn(BTN_10000X, "10000×", _speed_is(10000.0), P.PH)
	_btn(BTN_IGN, "点火 / IGNITE", true, P.AMBER)
	_btn(BTN_ARR, "抵达 / ARRIVE", true, P.PH)
	_btn(BTN_REPLAY, "重播 / REPLAY", true, P.PH_DIM)
	_txt(cjk, CTRL.position.x + 16, CTRL.end.y - 28, "本地时间推进 · 真实 planner timeline · 不写 world/V15", 7, P.FAINT)
	_txt(mono, CTRL.position.x + 16, CTRL.end.y - 12, "SPEED %.0f× · %s" % [float(sim.speed) if sim != null else 1.0, String(sim.phase) if sim != null else "not_ready"], 7, P.a(P.PH_DIM, 0.9))


func _phase_label() -> String:
	if sim == null:
		return "not_ready"
	match String(sim.phase):
		"departure":
			return "DEPART"
		"cruise":
			return "CRUISE"
		"arrival":
			return "ARRIVAL"
		_:
			return "NOT READY"


func _phase_glyph(p: String) -> String:
	match p:
		"departure":
			return "●"
		"cruise":
			return "○"
		_:
			return "◉"


func _hms(sec: float) -> String:
	var s := maxf(0.0, sec)
	var d := int(s / 86400.0)
	var h := int(fmod(s, 86400.0) / 3600.0)
	var m := int(fmod(s, 3600.0) / 60.0)
	if d > 0:
		return "%dd %02dh" % [d, h]
	return "%02d:%02d" % [h, m]


func _speed_is(v: float) -> bool:
	return sim != null and absf(float(sim.speed) - v) < 0.1


func _draw_map(plan: Dictionary, ok: bool, tl: Array) -> void:
	var eq := C.equilibrium_points()
	if eq.is_empty():
		_txt(cjk, MAP.position.x + 24, MAP.position.y + 56, "TRANSFER NOT READY · cislunar geometry unavailable", 8, P.AMBER)
		return
	var l1: Vector3 = (eq["L1"] as Dictionary).get("pos_rot", Vector3.ZERO)
	var earth := C.earth_position_rot() - l1
	var moon := C.moon_position_rot() - l1
	var l4: Vector3 = (eq["L4"] as Dictionary).get("pos_rot", Vector3.ZERO) - l1
	var pts: Array[Vector3] = [earth, moon, l4, Vector3.ZERO]
	for raw in tl:
		if raw is Dictionary:
			pts.append(_v3((raw as Dictionary).get("pos_rot_km", [])) - l1)
	var minx := 1.0e30
	var maxx := -1.0e30
	var miny := 1.0e30
	var maxy := -1.0e30
	for q in pts:
		minx = minf(minx, q.x); maxx = maxf(maxx, q.x); miny = minf(miny, q.y); maxy = maxf(maxy, q.y)
	var pad := 80.0
	var spanx := maxf(1.0, maxx - minx); var spany := maxf(1.0, maxy - miny)
	var sc := minf((MAP.size.x - pad * 2.0) / spanx, (MAP.size.y - pad * 2.0) / spany)
	var cx := MAP.position.x + MAP.size.x * 0.5
	var cy := MAP.position.y + MAP.size.y * 0.52
	var pr := {"cx": cx, "cy": cy, "minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy, "sc": sc}
	var pe := _p_real(earth, pr)
	var pm := _p_real(moon, pr)
	var pl4 := _p_real(l4, pr)
	var p1 := _p_real(Vector3.ZERO, pr)
	var re := maxf(7.0, C.R_EARTH_KM * sc)
	var rm := maxf(4.0, C.R_MOON_KM * sc)
	draw_circle(pe, re, P.a(P.BLUE, 0.10))
	draw_arc(pe, re, 0, TAU, 48, P.a(P.BLUE, 0.65), 1.0, true)
	_txt(cjk, pe.x + re + 6, pe.y + 3, "EARTH / 地球", 8, P.a(P.BLUE, 0.9))
	draw_circle(pm, rm, P.a(P.DIM, 0.35))
	draw_arc(pm, rm, 0, TAU, 32, P.a(P.DIM, 0.8), 1.0, true)
	_txt(cjk, pm.x + rm + 6, pm.y + 3, "MOON / 月球", 8, P.a(P.TXT, 0.85))
	# L4/L1 ports
	var l4pts := PackedVector2Array([pl4 + Vector2(0, -7), pl4 + Vector2(7, 0), pl4 + Vector2(0, 7), pl4 + Vector2(-7, 0), pl4 + Vector2(0, -7)])
	draw_polyline(l4pts, P.a(P.AMBER, 0.9), 1.0)
	_txt(cjk, pl4.x + 10, pl4.y + 3, "L4-02 HAMMER 母港", 8, P.AMBER)
	draw_arc(p1, 10.0, 0, TAU, 40, P.a(P.PH, 0.9), 1.0, true)
	draw_line(p1 - Vector2(15, 0), p1 + Vector2(15, 0), P.a(P.PH, 0.7), 1.0)
	draw_line(p1 - Vector2(0, 15), p1 + Vector2(0, 15), P.a(P.PH, 0.7), 1.0)
	_txt(cjk, p1.x + 14, p1.y + 4, "L1 MERIDIAN 港群", 8, P.PH)
	# route
	if tl.size() >= 2:
		var prev := Vector2(-1, -1)
		for raw in tl:
			var row: Dictionary = raw
			var q := _p_real(_v3(row.get("pos_rot_km", [])) - l1, pr)
			if prev.x > -1.0:
				draw_line(prev, q, P.a(P.AMBER, 0.75), 1.0)
			prev = q
		var pc := _p_real(_interp_pos(_frac()) - l1, pr)
		draw_circle(pc, 3.0, P.PH)
		_txt(cjk, pc.x + 8, pc.y - 8, "TRANSIT %s" % (_phase_label()), 7, P.PH)
		# 5 ships at current point (offsets)
		var fleet: Array = plan.get("fleet", []) if plan.get("fleet", []) is Array else []
		for raw2 in fleet:
			var ship: Dictionary = raw2
			var off := _v3(ship.get("offset_km", []))
			var sp := _p_real(_interp_pos(_frac()) - l1 + off, pr)
			var c: Color = P.PH if String(ship.get("id", "")) == "apsis" else P.PH_DIM
			draw_circle(sp, 2.5, c)
			_txt(mono, sp.x + 5, sp.y - 5, String(ship.get("batch", "")), 6, P.a(c, 0.9))
		_txt(cjk, MAP.position.x + 24, MAP.position.y + 42,
			"真实 CR3BP/Lambert 轨迹 · 5 舰沿 timeline · scale %.0f km/px" % (1.0 / maxf(sc, 1.0e-9)), 7, P.a(P.PH_DIM, 0.9))
		_txt(cjk, MAP.position.x + 24, MAP.end.y - 26,
			"L4-02 → L1 · timeline %d 段 · 折线为真实 pos_rot_km（减 L1）" % tl.size(), 7, P.a(P.FAINT, 0.9))
	else:
		_txt(cjk, MAP.position.x + 24, MAP.position.y + 48, "TRANSFER NOT READY · planner timeline 为空", 10, P.AMBER)
		_txt(cjk, MAP.position.x + 24, MAP.position.y + 64, "不画伪造轨迹；仅显示真实地月/L4/L1 几何。", 7, P.FAINT)



func _p_real(p: Vector3, pr: Dictionary) -> Vector2:
	var cx := float(pr.get("cx", 0.0)); var cy := float(pr.get("cy", 0.0))
	var minx := float(pr.get("minx", 0.0)); var maxx := float(pr.get("maxx", 1.0))
	var miny := float(pr.get("miny", 0.0)); var maxy := float(pr.get("maxy", 1.0))
	var sc := float(pr.get("sc", 1.0))
	return Vector2(cx + (p.x - (minx + maxx) * 0.5) * sc, cy - (p.y - (miny + maxy) * 0.5) * sc)


func handle_click(p: Vector2) -> bool:
	if sim == null:
		return false
	if BTN_PAUSE.has_point(p):
		sim.playing = not bool(sim.playing)
		return true
	if BTN_1X.has_point(p):
		sim.speed = 1.0; sim.playing = true; return true
	if BTN_100X.has_point(p):
		sim.speed = 100.0; sim.playing = true; return true
	if BTN_1000X.has_point(p):
		sim.speed = 1000.0; sim.playing = true; return true
	if BTN_10000X.has_point(p):
		sim.speed = 10000.0; sim.playing = true; return true
	if BTN_IGN.has_point(p):
		sim.t = 0.0; sim.playing = false; return true
	if BTN_ARR.has_point(p):
		sim.t = float(sim.tof_s); sim.playing = false; return true
	if BTN_REPLAY.has_point(p):
		sim.t = 0.0; sim.playing = true; return true
	return false
