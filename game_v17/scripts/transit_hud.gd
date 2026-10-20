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
const TUT_BTN := Rect2(1640, 56, 160, 20)
const TUT_CLOSE := Rect2(1396, 820, 126, 24)
const OPT_RECT := Rect2(1180, 360, 320, 220)
const OPT_START_VIS := Rect2(1192, 536, 70, 20)
const OPT_START_IR := Rect2(1268, 536, 58, 20)
const OPT_STOP := Rect2(1332, 536, 56, 20)
const OPT_CLOSE := Rect2(1394, 536, 94, 20)
const OPT_OPEN := Rect2(1704, 636, 140, 20)
const SHIP_DAMAGE_BTN := Rect2(1556, 684, 136, 20)
const SHIP_RADAR_BTN := Rect2(1704, 684, 140, 20)
const SHIP_EMCON_BTN := Rect2(1556, 708, 136, 20)
const SHIP_IFF_BTN := Rect2(1704, 708, 140, 20)
const SHIP_DEST_BTN := Rect2(1556, 732, 288, 20)
const DMG_CLOSE := Rect2(1432, 864, 100, 22)
const DMG_FIX := Rect2(1252, 864, 120, 22)
const DMG_PRI := Rect2(1380, 864, 48, 22)
const DMG_CANCEL := Rect2(1304, 864, 72, 22)
const DMG_PANEL := Rect2(300, 140, 1320, 752)

var sim
var mono: Font
var cjk: Font
var _fleet_rects: Array = []
var _target_rects: Array = []
var _dmg_sel_section := ""


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
	# Left fleet / contacts / TWS / teaching
	_draw_fleet_panel(plan)
	# Map
	_panel(MAP)
	_draw_map(plan, ok, tl)
	# Right selected-object page
	_draw_side_page(plan, budget, arrival, tr)
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
	# Overlays: optical small + teaching popup
	_draw_optical_small()
	_draw_tutorial_popup()
	_draw_damage_page()
	_draw_modal_page()


func _sensors_vm() -> Dictionary:
	if sim == null or sim.sensors == null:
		return {}
	return sim.sensors.vm()


func _draw_fleet_panel(plan: Dictionary) -> void:
	_panel(FLEET)
	var vm := _sensors_vm()
	var ships: Array = vm.get("ships", []) if vm.get("ships", []) is Array else []
	var targets: Array = vm.get("targets", []) if vm.get("targets", []) is Array else []
	var obs := String(vm.get("observer_ship", "")) if not vm.is_empty() else ""
	_txt(cjk, FLEET.position.x + 12, FLEET.position.y + 18, "舰队 / FLEET · 5 舰", 9, P.PH)
	_txt_r(mono, FLEET.end.x - 12, FLEET.position.y + 18, "点击切 observer", 6, P.a(P.FAINT, 0.9))
	draw_line(Vector2(FLEET.position.x + 12, FLEET.position.y + 26), Vector2(FLEET.end.x - 12, FLEET.position.y + 26), P.a(P.LINE, 0.7), 1.0)
	_fleet_rects.clear()
	var y := FLEET.position.y + 38.0
	var names := {"apsis": "远地点 / APSIS", "harmattan": "哈马丹 / HARMATTAN", "ferry": "渡口 / FERRY",
		"watchtower": "望楼 / WATCHTOWER", "deepwell": "深井 / DEEPWELL"}
	var roles := {"flagship": "旗舰", "command": "哨舰", "escort": "炮舰", "relay": "中继", "tanker": "油船"}
	for raw in ships:
		var sh: Dictionary = raw
		var sid := String(sh.get("id", ""))
		var rr := Rect2(FLEET.position.x + 8, y - 10, FLEET.size.x - 16, 44)
		_fleet_rects.append({"rect": rr, "id": sid})
		var sel := sid == obs
		if sel:
			draw_rect(rr, P.a(P.PH, 0.08))
			draw_rect(Rect2(rr.position.x, rr.position.y, 2, rr.size.y), P.PH)
		_txt(mono, rr.position.x + 6, y, "[%s] %s" % [String(sh.get("batch", "")), String(names.get(sid, sid))], 8, P.PH if sel else P.TXT)
		_txt_r(cjk, rr.end.x - 6, y, "OBSERVER" if sel else String(roles.get(String(sh.get("role", "")), "")), 6, P.PH if sel else P.FAINT)
		y += 13.0
		_txt(cjk, rr.position.x + 6, y, "range %.0f km · loadout %d · %s" % [float(sh.get("range_km", 0.0)),
			(sh.get("loadout_fallbacks", []) as Array).size(), String(sim.phase) if sim != null else ""], 6, P.a(P.DIM, 0.95))
		y += 11.0
		var chs: Array = vm.get("channels", []) if vm.get("channels", []) is Array else []
		var n_ch := 0
		for rawc in chs:
			if rawc is Dictionary and String((rawc as Dictionary).get("target_id", "")) == String(vm.get("selected_target", "")):
				n_ch += 1
		_txt(mono, rr.position.x + 6, y, "Δv %.0f m/s · ch %d · ETA %s" % [
			float((plan.get("budget", {}) as Dictionary).get("total_dv_mps", 0.0)) if plan.get("budget", {}) is Dictionary else 0.0,
			n_ch, _hms(maxf(0.0, float(sim.tof_s) - float(sim.t)) if sim != null else 0.0)], 6, P.a(P.FAINT, 0.9))
		y += 18.0
	# Contacts / levels / TWS
	_txt(cjk, FLEET.position.x + 12, y, "接触 / 目标 · TWS", 8, P.PH)
	_txt_r(mono, FLEET.end.x - 12, y, "levels %s · TWS %d" % [_levels_text(vm), _tws_count(vm)], 6, P.a(P.FAINT, 0.9))
	y += 12.0
	_target_rects.clear()
	var shown := 0
	for raw in targets:
		if shown >= 6:
			break
		var t: Dictionary = raw
		var rr2 := Rect2(FLEET.position.x + 8, y - 8, FLEET.size.x - 16, 22)
		_target_rects.append({"rect": rr2, "id": String(t.get("id", ""))})
		var sel_t := String(t.get("id", "")) == String(vm.get("selected_target", "")) and String(sim.ui_mode) == "target"
		if sel_t:
			draw_rect(rr2, P.a(P.AMBER, 0.10))
		_txt(mono, rr2.position.x + 4, y, "%s L%d · %.0fkm" % [String(t.get("name", t.get("id", ""))), int(t.get("level", 0)), float(t.get("range_km", 0.0))], 6, P.PH if sel_t else P.TXT)
		_txt_r(mono, rr2.end.x - 4, y, "%s/%s" % [String(t.get("vis_status", "off")), String(t.get("ir_status", "off"))], 6, P.a(P.DIM, 0.9))
		y += 22.0
		shown += 1
	_txt(cjk, FLEET.position.x + 12, FLEET.end.y - 36, "教学：阶段2转场 / 手动目标", 7, P.a(P.PH_DIM, 0.9))
	_btn(TUT_BTN if false else Rect2(FLEET.position.x + 8, FLEET.end.y - 28, 150, 20), "教学 / TUTORIAL", sim != null and bool(sim.tutorial_open), P.AMBER)
	_txt(cjk, FLEET.position.x + 172, FLEET.end.y - 16, String(sim.last_note) if sim != null else "", 6, P.a(P.AMBER, 0.8))


func _levels_text(vm: Dictionary) -> String:
	var lv: Dictionary = vm.get("levels", {}) if vm.get("levels", {}) is Dictionary else {}
	var c: Dictionary = lv.get("counts", {}) if lv.get("counts", {}) is Dictionary else {}
	return "L0 %d/L1 %d/L2 %d/L3+ %d" % [int(c.get("0", 0)), int(c.get("1", 0)), int(c.get("2", 0)),
		int(c.get("3", 0)) + int(c.get("4", 0))]


func _tws_count(vm: Dictionary) -> int:
	var c: Dictionary = vm.get("counts", {}) if vm.get("counts", {}) is Dictionary else {}
	return int(c.get("channels", 0))


func _draw_side_page(plan: Dictionary, budget: Dictionary, arrival: Dictionary, tr: Dictionary) -> void:
	_panel(SIDE)
	var vm := _sensors_vm()
	var target_mode := sim != null and String(sim.ui_mode) == "target"
	_txt(cjk, SIDE.position.x + 12, SIDE.position.y + 18, "选中对象 / SELECTION", 9, P.PH)
	_txt_r(mono, SIDE.end.x - 12, SIDE.position.y + 18, "TARGET" if target_mode else "SHIP", 7, P.AMBER if target_mode else P.PH_DIM)
	draw_line(Vector2(SIDE.position.x + 12, SIDE.position.y + 26), Vector2(SIDE.end.x - 12, SIDE.position.y + 26), P.a(P.LINE, 0.7), 1.0)
	var sy := SIDE.position.y + 42.0
	# 任务摘要（始终保持）
	var from_s := String((plan.get("source", {}) as Dictionary).get("name", "L4-02 Hammer")) if plan.get("source", {}) is Dictionary else "L4-02 Hammer"
	var to_s := String((plan.get("target", {}) as Dictionary).get("name", "L1-Meridian-05")) if plan.get("target", {}) is Dictionary else "L1-Meridian-05"
	_txt(cjk, SIDE.position.x + 12, sy, "MISSION  %s → %s" % [from_s, to_s], 7, P.a(P.DIM, 0.95))
	sy += 14.0
	_txt(mono, SIDE.position.x + 12, sy, "TOF %.1f d · Δv %.1f m/s · ARR %.1f km" % [
		float(tr.get("tof_days", 0.0)), float(budget.get("total_dv_mps", 0.0)), float(arrival.get("radius_km", 0.0))], 7, P.TXT)
	sy += 14.0
	draw_line(Vector2(SIDE.position.x + 12, sy), Vector2(SIDE.end.x - 12, sy), P.a(P.LINE, 0.6), 1.0)
	sy += 14.0
	if target_mode:
		var tid := String(vm.get("selected_target", "")) if not vm.is_empty() else ""
		var trow: Dictionary = {}
		var targets: Array = vm.get("targets", []) if vm.get("targets", []) is Array else []
		for raw in targets:
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
				trow = raw
				break
		_txt(cjk, SIDE.position.x + 12, sy, "目标数据 / TARGET DATA", 8, P.AMBER)
		sy += 16.0
		if trow.is_empty():
			_txt(cjk, SIDE.position.x + 12, sy, "TARGET NOT READY", 8, P.AMBER)
			sy += 14.0
		else:
			_txt(cjk, SIDE.position.x + 12, sy, "名称 %s / %s" % [String(trow.get("name", "")), String(trow.get("id", ""))], 8, P.TXT)
			sy += 14.0
			_txt(mono, SIDE.position.x + 12, sy, "BATCH %s · KIND %s · SIDE %s" % [
				String(trow.get("batch", "")), String(trow.get("kind", "")), String(trow.get("side", ""))], 7, P.DIM)
			sy += 12.0
			_txt(mono, SIDE.position.x + 12, sy, "RANGE %.1f km · LEVEL L%d" % [float(trow.get("range_km", 0.0)), int(trow.get("level", 0))], 7, P.TXT)
			sy += 12.0
			_txt(mono, SIDE.position.x + 12, sy, "contact L%d · optical L%d · VIS %s · IR %s" % [
				int(trow.get("contact_level", 0)), int(trow.get("optical_level", 0)),
				String(trow.get("vis_status", "off")), String(trow.get("ir_status", "off"))], 7, P.TXT)
			sy += 12.0
			_txt(cjk, SIDE.position.x + 12, sy, "reason %s" % String(trow.get("reason", "—")), 7, P.a(P.AMBER, 0.9))
			sy += 16.0
			var iff := _iff_for(String(trow.get("id", "")))
			if iff.is_empty():
				_txt(mono, SIDE.position.x + 12, sy, "IFF — · never hostile · 不判敌", 7, P.FAINT)
			else:
				_txt(mono, SIDE.position.x + 12, sy, "IFF %s · identity %s · hostile %s" % [
					String(iff.get("status", "—")), String(iff.get("identity", "unknown")), str(bool(iff.get("hostile", false)))], 7,
					P.AMBER if String(iff.get("status", "")) != "friend" else P.PH)
			sy += 12.0
			var exp := _exposure()
			_txt(mono, SIDE.position.x + 12, sy, "RADAR %s · exposed %s · EMCON %s" % [
				"ON" if _radar_on() else "OFF", str(bool(exp.get("exposed", false))), str(_emcon_on())], 7, P.DIM)
			sy += 12.0
			_txt(cjk, SIDE.position.x + 12, sy, "光学证据 VIS %s · IR %s" % [String(trow.get("vis_status", "off")), String(trow.get("ir_status", "off"))], 7, P.TXT)
			sy += 16.0
			_txt(cjk, SIDE.position.x + 12, sy, "非己方目标：只读识别/接触/光学证据；", 7, P.FAINT)
			_txt(cjk, SIDE.position.x + 12, sy + 12, "无指挥/损管操作。", 7, P.FAINT)
	else:
		var ship: Dictionary = {}
		var ships: Array = vm.get("ships", []) if vm.get("ships", []) is Array else []
		var obs := String(vm.get("observer_ship", "")) if not vm.is_empty() else ""
		for raw in ships:
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) == obs:
				ship = raw
				break
		_txt(cjk, SIDE.position.x + 12, sy, "友军可指挥舰 / SHIP", 8, P.PH)
		sy += 16.0
		if ship.is_empty():
			_txt(cjk, SIDE.position.x + 12, sy, "SHIP NOT READY", 8, P.AMBER)
			sy += 14.0
		else:
			_txt(cjk, SIDE.position.x + 12, sy, "%s [%s]" % [String(ship.get("name", "")), String(ship.get("batch", ""))], 9, P.TXT)
			sy += 15.0
			_txt(cjk, SIDE.position.x + 12, sy, "%s · %s" % [String(ship.get("class", "")), String(ship.get("role", ""))], 7, P.DIM)
			sy += 13.0
			_txt(mono, SIDE.position.x + 12, sy, "RANGE %.1f km · RCS %.0f m²" % [float(ship.get("range_km", 0.0)), _ship_rcs(String(ship.get("id", "")))], 7, P.TXT)
			sy += 12.0
			var fallbacks: Array = ship.get("loadout_fallbacks", [])
			_txt(mono, SIDE.position.x + 12, sy, "SENSORS %s · fallback %d" % ["AUTHORITY", fallbacks.size()], 7, P.DIM if fallbacks.is_empty() else P.AMBER)
			sy += 12.0
			var opt: Dictionary = vm.get("optical", {}) if vm.get("optical", {}) is Dictionary else {}
			var vis: Dictionary = opt.get("vis", {}) if opt.get("vis", {}) is Dictionary else {}
			var ir: Dictionary = opt.get("ir", {}) if opt.get("ir", {}) is Dictionary else {}
			_txt(mono, SIDE.position.x + 12, sy, "OPT VIS %s · IR %s" % [
				String(vis.get("status", "off")), String(ir.get("status", "off"))], 7, P.PH if not vis.is_empty() or not ir.is_empty() else P.FAINT)
			sy += 12.0
			var exp0 := _exposure()
			var counts0: Dictionary = vm.get("counts", {}) if vm.get("counts", {}) is Dictionary else {}
			_txt(mono, SIDE.position.x + 12, sy, "RADAR %s · EXPOSED %s · contacts %d" % [
				"ON" if _radar_on() else "OFF", str(bool(exp0.get("exposed", false))), int(counts0.get("contacts", 0))], 7, P.DIM)
			sy += 14.0
			var dsum := _damage_summary_for(String(ship.get("id", "")))
			if dsum.is_empty():
				_txt(cjk, SIDE.position.x + 12, sy, "DAMAGE: NO DAMAGE DATA", 7, P.AMBER)
			else:
				_txt(mono, SIDE.position.x + 12, sy, "DAMAGE %.1f%% · fire %d · decomp %d · unpowered %d" % [
					float(dsum.get("integrity_avg", 0.0)) * 100.0, int(dsum.get("on_fire", 0)),
					int(dsum.get("decompressed", 0)), int(dsum.get("unpowered", 0))], 7, P.AMBER if int(dsum.get("needs_attention", 0)) > 0 else P.PH_DIM)
				sy += 12.0
				_txt(mono, SIDE.position.x + 12, sy, "repair %d · queued %d · sections %d" % [
					int(dsum.get("repairing", 0)), int(dsum.get("queued", 0)), int(dsum.get("total", 0))], 7, P.DIM)
			sy += 14.0
			_btn(SHIP_DAMAGE_BTN, "损管页 / DAMAGE", sim != null and bool(sim.damage_open), P.AMBER)
			_btn(SHIP_RADAR_BTN, "RADAR ON/OFF", _radar_on(), P.PH)
			_btn(SHIP_EMCON_BTN, "EMCON ON/OFF", _emcon_on(), P.AMBER)
			_btn(SHIP_IFF_BTN, "IFF 询问", true, P.PH_DIM)
			_btn(SHIP_DEST_BTN, "SET DEST → L1 MERIDIAN", true, P.PH)
			_btn(OPT_OPEN, "打开光学小窗 / OPTICAL", sim != null and bool(sim.optical_open), P.PH)
			_btn(Rect2(SIDE.position.x + 12, SIDE.end.y - 196, 140, 20), "教学 / TUTORIAL", sim != null and bool(sim.tutorial_open), P.AMBER)
	# 教学摘要
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 84, "教学 / TUTORIAL", 7, P.FAINT)
	_txt(mono, SIDE.position.x + 12, SIDE.end.y - 70, _teach_progress_text() if sim != null else "NOT READY", 7, P.PH_DIM)
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 54, _teach_current_text() if sim != null else "NOT READY", 7, P.a(P.DIM, 0.95))
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 30, "sensor bridge: V2TransitSensors shadow", 6, P.FAINT)
	_txt(cjk, SIDE.position.x + 12, SIDE.end.y - 16, "writes v15=false · 不伪造", 6, P.FAINT)


func _ship_rcs(id: String) -> float:
	match id:
		"apsis":
			return 2200.0
		"harmattan":
			return 900.0
		"ferry":
			return 500.0
		"watchtower":
			return 380.0
		"deepwell":
			return 1400.0
		_:
			return 0.0


func _teach_vm() -> Dictionary:
	if sim == null or sim.teach == null:
		return {}
	return sim.teach.vm()


func _teach_progress_text() -> String:
	var vm := _teach_vm()
	if vm.is_empty():
		return "TEACHING NOT READY"
	var p: Dictionary = vm.get("progress", {}) if vm.get("progress", {}) is Dictionary else {}
	return "G %d/%d · STEP %d/%d · %.0f%%" % [int(p.get("goals_completed", 0)), int(p.get("goals_total", 0)),
		int(p.get("completed", 0)), int(p.get("total", 0)), float(p.get("pct", 0.0))]


func _teach_current_text() -> String:
	var vm := _teach_vm()
	var cur: Dictionary = vm.get("current", {}) if vm.get("current", {}) is Dictionary else {}
	if cur.is_empty():
		return "教学完成 / 无待完成步骤"
	return "当前：%s · %s" % [String(cur.get("step_id", "")), String(cur.get("title", ""))]


func _draw_optical_small() -> void:
	if sim == null or not bool(sim.optical_open):
		return
	var r := OPT_RECT
	draw_rect(r, P.a(P.BG, 0.985))
	draw_rect(r, P.a(P.PH, 0.65), false, 1.0)
	_txt(cjk, r.position.x + 8, r.position.y + 12, "光学 / IR 小窗", 8, P.PH)
	_txt_r(mono, r.end.x - 8, r.position.y + 12, "V15 · 320×220", 6, P.a(P.FAINT, 0.9))
	var vm := _sensors_vm()
	var opt: Dictionary = vm.get("optical", {}) if vm.get("optical", {}) is Dictionary else {}
	var tg := String(vm.get("selected_target", "")) if not vm.is_empty() else ""
	_txt(mono, r.position.x + 8, r.position.y + 24, "TGT %s · SHADOW" % tg, 6, P.a(P.DIM, 0.95))
	_opt_line(Rect2(r.position.x + 8, r.position.y + 30, r.size.x - 16, 62), "VIS / 可见光", "optical", opt.get("vis", {}) if opt.get("vis", {}) is Dictionary else {})
	_opt_line(Rect2(r.position.x + 8, r.position.y + 96, r.size.x - 16, 62), "IR / 红外", "ir", opt.get("ir", {}) if opt.get("ir", {}) is Dictionary else {})
	_btn(OPT_START_VIS, "START VIS", true, P.PH)
	_btn(OPT_START_IR, "START IR", true, P.AMBER)
	_btn(OPT_STOP, "STOP", true, P.AMBER)
	_btn(OPT_CLOSE, "CLOSE", true, P.RED)
	_txt(cjk, r.position.x + 8, r.end.y - 10, "真实 V2TransitSensors · 不写 V15 · 失败显示 reason", 6, P.a(P.FAINT, 0.9))


func _opt_line(r: Rect2, label: String, kind: String, ch: Dictionary) -> void:
	var st := String(ch.get("status", "off")) if not ch.is_empty() else "off"
	var col := P.PH if st == "locked" else (P.AMBER if st in ["staring", "acquiring"] else (P.RED if st == "lost" else P.DIM))
	draw_rect(r, P.a(P.PANEL2, 0.45))
	draw_rect(r, P.a(col, 0.35), false, 1.0)
	_txt(mono, r.position.x + 6, r.position.y + 10, "%s · %s" % [label, st.to_upper()], 7, col)
	if ch.is_empty():
		_txt(mono, r.position.x + 6, r.position.y + 24, "NO CHANNEL · reason not_ready", 6, P.FAINT)
		return
	var reason := String(ch.get("reason", ""))
	var fails: Array = ch.get("failures", []) if ch.get("failures", []) is Array else []
	var occ := reason == "occluded" or fails.has("occluded")
	_txt(mono, r.position.x + 6, r.position.y + 22, "TGT %s · FOV %.3f° · SNR %.1f" % [String(ch.get("target_id", "")),
		float(ch.get("fov_deg", 0.0)), float(ch.get("snr_db", -999.0))], 6, P.TXT)
	_txt(mono, r.position.x + 6, r.position.y + 32, "OFF %.2f° · N_PX %.1f · L%d" % [float(ch.get("off_axis_deg", -1.0)),
		float(ch.get("n_px", 0.0)), int(ch.get("level_support", 0))], 6, P.TXT)
	_txt(mono, r.position.x + 6, r.position.y + 42, "OCC %s · LOCK %s · %s" % ["YES" if occ else "no",
		"YES" if bool(ch.get("locked", false)) else "no", reason if reason != "" else "ok"], 6, P.AMBER if occ else P.DIM)


func _draw_tutorial_popup() -> void:
	if sim == null or not bool(sim.tutorial_open):
		return
	var r := Rect2(360, 180, 1200, 660)
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.01, 0.02, 0.016, 0.72))
	draw_rect(r, P.a(P.PANEL, 0.995))
	draw_rect(r, P.a(P.AMBER, 0.7), false, 1.0)
	var vm := _teach_vm()
	var prog: Dictionary = vm.get("progress", {}) if vm.get("progress", {}) is Dictionary else {}
	_txt(cjk, r.position.x + 20, r.position.y + 24, "07 教学 / TUTORIAL · 阶段2转场", 12, P.AMBER)
	_txt(mono, r.end.x - 20, r.position.y + 24, "GOALS %d/%d · STEP %d/%d" % [int(prog.get("goals_completed", 0)),
		int(prog.get("goals_total", 0)), int(prog.get("completed", 0)), int(prog.get("total", 0))], 8, P.PH)
	draw_line(Vector2(r.position.x + 20, r.position.y + 36), Vector2(r.end.x - 20, r.position.y + 36), P.a(P.AMBER, 0.35), 1.0)
	var goals: Array = vm.get("goals", []) if vm.get("goals", []) is Array else []
	var gy := r.position.y + 54.0
	for raw in goals:
		var g: Dictionary = raw
		var gst := String(g.get("status", ""))
		var gc := P.PH if gst == "completed" else P.AMBER
		_txt(cjk, r.position.x + 20, gy, "%s · %s" % [String(g.get("id", "")), String(g.get("title", ""))], 8, gc)
		_txt_r(mono, r.end.x - 20, gy, "%d/%d" % [int(g.get("completed_steps", 0)), int(g.get("step_count", 0))], 7, gc)
		gy += 14.0
		_txt(cjk, r.position.x + 36, gy, _ellipsis(cjk, String(g.get("objective", "")), 7, 1050.0), 7, P.a(P.DIM, 0.9))
		gy += 20.0
	var cur: Dictionary = vm.get("current", {}) if vm.get("current", {}) is Dictionary else {}
	gy += 6.0
	_txt(cjk, r.position.x + 20, gy, "当前步骤 / CURRENT", 8, P.PH)
	gy += 16.0
	if cur.is_empty():
		_txt(cjk, r.position.x + 20, gy, "全部步骤已完成 / SKIPPED", 8, P.PH)
	else:
		_txt(mono, r.position.x + 20, gy, "%s · %s" % [String(cur.get("step_id", "")), String(cur.get("title", ""))], 8, P.AMBER)
		gy += 14.0
		_txt(cjk, r.position.x + 20, gy, "目标：%s" % _ellipsis(cjk, String(cur.get("objective", "")), 7, 1100.0), 7, P.TXT)
		gy += 12.0
		_txt(cjk, r.position.x + 20, gy, "玩家动作：%s" % _ellipsis(cjk, String(cur.get("player_action", "")), 7, 1100.0), 7, P.TXT)
		gy += 12.0
		_txt(cjk, r.position.x + 20, gy, "提示：%s" % _ellipsis(cjk, String(cur.get("hint", "")), 7, 1100.0), 7, P.a(P.PH_DIM, 0.9))
	# 手动触发（仅教学手动记录；真实场景动作仍由点击/控制执行）
	var hints: Array = vm.get("hints", []) if vm.get("hints", []) is Array else []
	var hy := r.position.y + 430.0
	_txt(cjk, r.position.x + 20, hy, "提示 / HINTS", 7, P.FAINT)
	hy += 14.0
	for i in range(mini(3, hints.size())):
		var h: Dictionary = hints[i]
		_txt(cjk, r.position.x + 20, hy, "%s · %s" % [String(h.get("step_id", "")), _ellipsis(cjk, String(h.get("hint", "")), 7, 1100.0)], 7, P.a(P.DIM, 0.9))
		hy += 12.0
	_txt(cjk, r.position.x + 20, r.end.y - 76, "手动触发（教学记录）", 7, P.AMBER)
	var actions := [["SET DEST", "set_destination", "meridian"], ["RADAR ON", "sensor_toggle", "harmattan/YW-R9"],
		["IFF", "iff_query", "2001"], ["ROE", "open_roe_card", ""], ["HOLD", "decision", "HOLD"],
		["REPORT", "report_submit", "INTERNAL_AFTER_ACTION"]]
	for i in range(actions.size()):
		var ar: Array = actions[i]
		var br := Rect2(r.position.x + 20 + float(i) * 158.0, r.end.y - 64, 148, 20)
		_btn(br, "+ " + String(ar[0]), true, P.PH)
	_btn(TUT_CLOSE, "关闭 / CLOSE", true, P.RED)
	_txt(cjk, r.position.x + 20, r.end.y - 20, "manual_only=true · auto_complete=false · 文本来自 teaching_l4_l1.json · 未自动完成", 6, P.a(P.FAINT, 0.9))


func _damage_summary_for(ship_id: String) -> Dictionary:
	if sim == null or sim.damage == null:
		return {}
	var sm: Dictionary = sim.damage.summary()
	var rows: Array = sm.get("ships", []) if sm.get("ships", []) is Array else []
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get("ship_id", "")) == ship_id:
			return (raw as Dictionary).get("summary", {}) if (raw as Dictionary).get("summary", {}) is Dictionary else {}
	return {}


func _radar_on() -> bool:
	var vm := _sensors_vm()
	return bool(vm.get("radar_enabled", false)) if not vm.is_empty() else false


func _emcon_on() -> bool:
	var vm := _sensors_vm()
	return bool(vm.get("emcon", false)) if not vm.is_empty() else false


func _exposure() -> Dictionary:
	var vm := _sensors_vm()
	return vm.get("exposure", {}) if vm.get("exposure", {}) is Dictionary else {}


func _iff_for(id: String) -> Dictionary:
	var vm := _sensors_vm()
	var iff: Dictionary = vm.get("iff", {}) if vm.get("iff", {}) is Dictionary else {}
	var by: Dictionary = iff.get("by_target", {}) if iff.get("by_target", {}) is Dictionary else {}
	var row = by.get(id)
	return row if row is Dictionary else {}


func _draw_damage_page() -> void:
	if sim == null or not bool(sim.damage_open):
		return
	var r := DMG_PANEL
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.01, 0.02, 0.016, 0.72))
	draw_rect(r, P.a(P.PANEL, 0.995))
	draw_rect(r, P.a(P.AMBER, 0.7), false, 1.0)
	var sid := String(sim.sensors.selected_ship) if sim.sensors != null else "harmattan"
	var vm: Dictionary = sim.damage.vm(sid) if sim.damage != null else {}
	_txt(cjk, r.position.x + 20, r.position.y + 24, "损管 / DAMAGE CONTROL · %s" % String(vm.get("name", sid)), 12, P.AMBER)
	_txt(mono, r.end.x - 20, r.position.y + 24, "V2DamageModel · 7 sections · no weapon source", 7, P.a(P.FAINT, 0.9))
	draw_line(Vector2(r.position.x + 20, r.position.y + 36), Vector2(r.end.x - 20, r.position.y + 36), P.a(P.AMBER, 0.35), 1.0)
	var sm: Dictionary = vm.get("summary", {}) if vm.get("summary", {}) is Dictionary else {}
	_txt(mono, r.position.x + 20, r.position.y + 54, "INTEGRITY %.1f%% · NOMINAL %d · DAMAGED %d · FIRE %d · DECOMP %d · REPAIR %d" % [
		float(sm.get("integrity_avg", 0.0)) * 100.0, int(sm.get("nominal", 0)), int(sm.get("damaged", 0)),
		int(sm.get("on_fire", 0)), int(sm.get("decompressed", 0)), int(sm.get("repairing", 0))], 7, P.TXT)
	var sections: Array = vm.get("sections", []) if vm.get("sections", []) is Array else []
	if _dmg_sel_section == "" and not sections.is_empty():
		_dmg_sel_section = String((sections[0] as Dictionary).get("id", ""))
	var sy := r.position.y + 72.0
	_txt(cjk, r.position.x + 20, sy, "分区 / SECTIONS（点击选择）", 8, P.PH)
	sy += 12.0
	for i in range(mini(7, sections.size())):
		var sec: Dictionary = sections[i]
		var sec_id := String(sec.get("id", ""))
		var rr := Rect2(r.position.x + 20, sy - 8, r.size.x - 40, 25)
		var sel := sec_id == _dmg_sel_section
		if sel:
			draw_rect(rr, P.a(P.AMBER, 0.10))
		var st := String(sec.get("state", ""))
		var col := P.PH if st == "nominal" else (P.AMBER if st in ["degraded", "damaged"] else P.RED)
		var fire: Dictionary = sec.get("fire", {}) if sec.get("fire", {}) is Dictionary else {}
		var dec: Dictionary = sec.get("decompression", {}) if sec.get("decompression", {}) is Dictionary else {}
		_txt(mono, rr.position.x + 6, sy, "%s %-10s" % [sec_id, String(sec.get("label", ""))], 7, P.TXT)
		_txt(mono, rr.position.x + 250, sy, "INT %.1f%% · %s" % [float(sec.get("integrity_pct", 0.0)), st.to_upper()], 7, col)
		_txt(mono, rr.position.x + 500, sy, "fire %s · decomp %s · power %s" % [
			"Y" if bool(fire.get("active", false)) else "n", "Y" if bool(dec.get("active", false)) else "n",
			"Y" if bool(sec.get("powered", true)) else "N"], 7, P.AMBER if bool(fire.get("active", false)) or bool(dec.get("active", false)) else P.DIM)
		var rep: Dictionary = sec.get("repair", {}) if sec.get("repair", {}) is Dictionary else {}
		_txt(mono, rr.position.x + 820, sy, "repair %s" % String(rep.get("status", "—")), 7, P.FAINT)
		sy += 25.0
	# actions selected
	var sel_sec: Dictionary = {}
	for raw in sections:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == _dmg_sel_section:
			sel_sec = raw
	if not _dmg_sel_section.is_empty():
		_txt(mono, DMG_FIX.position.x - 250, DMG_FIX.position.y + 6, "SELECTED %s" % _dmg_sel_section, 7, P.PH)
	_btn(DMG_FIX, "FIX / 维修", not sel_sec.is_empty(), P.PH)
	_btn(DMG_PRI, "PRI 1", not sel_sec.is_empty(), P.AMBER)
	_btn(DMG_CANCEL, "CANCEL", not sel_sec.is_empty(), P.RED)
	_btn(DMG_CLOSE, "关闭 / CLOSE", true, P.RED)
	# queue/resources/events
	var qy := r.position.y + 338.0
	_txt(cjk, r.position.x + 20, qy, "维修队列 / QUEUE", 8, P.PH)
	qy += 14.0
	var queue: Array = vm.get("queue", []) if vm.get("queue", []) is Array else []
	if queue.is_empty():
		_txt(cjk, r.position.x + 20, qy, "— 无维修队列", 7, P.FAINT)
	else:
		for raw in queue:
			var job: Dictionary = raw
			_txt(mono, r.position.x + 20, qy, "%s · PRI %d · %s · %.0f%% · remaining %.0fs" % [String(job.get("section", "")), int(job.get("priority", 0)), String(job.get("status", "")), float(job.get("progress_pct", 0.0)), float(job.get("remaining_s", 0.0))], 7, P.TXT)
			qy += 12.0
	var res: Dictionary = vm.get("resources", {}) if vm.get("resources", {}) is Dictionary else {}
	var qy2 := r.position.y + 500.0
	_txt(cjk, r.position.x + 20, qy2, "资源 / RESOURCES", 8, P.PH)
	qy2 += 14.0
	for k in ["repair_teams", "spare_parts", "power_kw", "crew"]:
		if res.has(k):
			_txt(mono, r.position.x + 20, qy2, "%s: %s" % [k, str(res.get(k))], 7, P.TXT)
			qy2 += 12.0
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	var ey := r.position.y + 500.0
	_txt(cjk, r.position.x + 620, ey, "事件 / EVENTS", 8, P.PH)
	ey += 14.0
	for i in range(mini(8, evs.size())):
		var ev: Dictionary = evs[i]
		_txt(mono, r.position.x + 620, ey, "%s · %s" % [String(ev.get("kind", "")), _ellipsis(mono, String(ev.get("text", "")), 6, 650.0)], 6, P.a(P.DIM, 0.9))
		ey += 11.0
	_txt(cjk, r.position.x + 20, r.end.y - 20, "真实 V2DamageModel（TransitDamage）· apply_hit 仅诊断；不写 world/V15 · FIX/PRI/CANCEL 走真实 API", 6, P.a(P.FAINT, 0.9))


func _draw_modal_page() -> void:
	if sim == null or String(sim.modal_page) == "":
		return
	var page := String(sim.modal_page)
	var r := Rect2(520, 260, 880, 520)
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.01, 0.02, 0.016, 0.72))
	draw_rect(r, P.a(P.PANEL, 0.995))
	draw_rect(r, P.a(P.AMBER, 0.7), false, 1.0)
	var title: String = String({"roe": "ROE / 交战规则", "hold": "DECISION / HOLD", "report": "REPORT / 内部报告"}.get(page, page.to_upper()))
	_txt(cjk, r.position.x + 20, r.position.y + 24, String(title), 12, P.AMBER)
	var vm := _teach_vm()
	var cur: Dictionary = vm.get("current", {}) if vm.get("current", {}) is Dictionary else {}
	_txt(cjk, r.position.x + 20, r.position.y + 52, "教学步骤：%s · %s" % [String(cur.get("step_id", "—")), String(cur.get("title", "—"))], 8, P.TXT)
	_txt(cjk, r.position.x + 20, r.position.y + 72, "目标：%s" % _ellipsis(cjk, String(cur.get("objective", "")), 8, 820.0), 7, P.DIM)
	_txt(cjk, r.position.x + 20, r.position.y + 92, "操作：%s" % _ellipsis(cjk, String(cur.get("player_action", "")), 8, 820.0), 7, P.TXT)
	_txt(cjk, r.position.x + 20, r.position.y + 128, "此页为教学模态；关闭后不自动完成步骤。真实动作请按页面/游戏入口执行。", 7, P.FAINT)
	_btn(Rect2(r.end.x - 140, r.end.y - 40, 120, 24), "关闭 / CLOSE", true, P.RED)
	_txt(cjk, r.position.x + 20, r.end.y - 20, "07 教学目标 · teaching_l4_l1.json · manual_only=true · auto_complete=false", 6, P.a(P.FAINT, 0.9))


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
	# damage page
	if bool(sim.damage_open):
		if DMG_CLOSE.has_point(p):
			sim.damage_open = false; return true
		if DMG_FIX.has_point(p) and _dmg_sel_section != "":
			sim.ui_damage_fix(_dmg_sel_section); return true
		if DMG_PRI.has_point(p) and _dmg_sel_section != "":
			sim.ui_damage_priority(_dmg_sel_section, 1); return true
		if DMG_CANCEL.has_point(p) and _dmg_sel_section != "":
			sim.ui_damage_cancel(_dmg_sel_section); return true
		var vm_d: Dictionary = sim.damage.vm(String(sim.sensors.selected_ship)) if sim.damage != null else {}
		var secs: Array = vm_d.get("sections", []) if vm_d.get("sections", []) is Array else []
		for i in range(mini(7, secs.size())):
			var rr := Rect2(DMG_PANEL.position.x + 20, DMG_PANEL.position.y + 76 + float(i) * 25 - 8, DMG_PANEL.size.x - 40, 25)
			if rr.has_point(p):
				_dmg_sel_section = String((secs[i] as Dictionary).get("id", ""))
				return true
		return true
	if String(sim.modal_page) != "":
		if Rect2(1260, 740, 120, 24).has_point(p) or not Rect2(520, 260, 880, 520).has_point(p):
			sim.modal_page = ""
		return true
	# teaching popup
	if bool(sim.tutorial_open):
		if TUT_CLOSE.has_point(p):
			sim.tutorial_open = false
			return true
		var vmt := _teach_vm()
		for i in range(6):
			var br := Rect2(360 + 20 + float(i) * 158.0, 180 + 660 - 64, 148, 20)
			if br.has_point(p):
				match i:
					0: sim.ui_set_destination()
					1: sim.ui_set_radar(not _radar_on())
					2: sim.ui_iff()
					3: sim.ui_open_modal("roe")
					4: sim.ui_open_modal("hold")
					5: sim.ui_open_modal("report")
				return true
		return true
	# teaching button / optical
	if Rect2(FLEET.position.x + 8, FLEET.end.y - 28, 150, 20).has_point(p):
		sim.tutorial_open = true
		return true
	if OPT_OPEN.has_point(p):
		sim.optical_open = not bool(sim.optical_open)
		return true
	if sim.optical_open:
		if OPT_START_VIS.has_point(p):
			sim.ui_optical_start("optical"); return true
		if OPT_START_IR.has_point(p):
			sim.ui_optical_start("ir"); return true
		if OPT_STOP.has_point(p):
			sim.ui_optical_stop(); return true
		if OPT_CLOSE.has_point(p):
			sim.optical_open = false; return true
	# fleet / targets
	for raw in _fleet_rects:
		var fr: Rect2 = (raw as Dictionary)["rect"]
		if fr.has_point(p):
			sim.ui_select_ship(String((raw as Dictionary)["id"]))
			return true
	for raw2 in _target_rects:
		var tr: Rect2 = (raw2 as Dictionary)["rect"]
		if tr.has_point(p):
			sim.ui_select_target(String((raw2 as Dictionary)["id"]))
			return true
	if SHIP_DAMAGE_BTN.has_point(p):
		sim.ui_toggle_damage(); _dmg_sel_section = ""; return true
	if SHIP_RADAR_BTN.has_point(p):
		sim.ui_set_radar(not _radar_on()); return true
	if SHIP_EMCON_BTN.has_point(p):
		sim.ui_set_emcon(not _emcon_on()); return true
	if SHIP_IFF_BTN.has_point(p):
		sim.ui_iff(); return true
	if SHIP_DEST_BTN.has_point(p):
		sim.ui_set_destination(); return true
	if BTN_IGN.has_point(p):
		sim.ui_ignite(); return true
	if BTN_ARR.has_point(p):
		sim.ui_arrive(); return true
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
	if BTN_REPLAY.has_point(p):
		sim.t = 0.0; sim.playing = true; return true
	return false
