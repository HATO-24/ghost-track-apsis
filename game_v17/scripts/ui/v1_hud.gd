extends Control

# 方案B 自绘 V1 HUD 样张：统一 LayoutTokens/TextMetrics/PanelPainter。
# 独立 v1_hud.tscn；不改旧 HUD/Control 壳；数据无 GameSession 时明确 DEMO。
# 不实现 IME/剧情/物理/存档。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")
const Painter := preload("res://scripts/ui/panel_painter.gd")

const SCENARIO := "res://framework/content/scenario_transit_l4_l1.json"
const TRANSFER := "res://framework/content/transfer_l4_l1_cached.json"

var tok = null
var _contacts: Array = []
var _selected := 0
var _page := "ship"
var _collapsed := false
var _t := 0.0
var _timers := [
	{"label": "BURN WINDOW", "remain": 30.0, "total": 30.0},
	{"label": "ARRIVAL", "remain": 120.0, "total": 120.0},
	{"label": "LINK", "remain": 15.0, "total": 15.0},
]
var _top_dots: Array = []
var _contact_rects: Array = []
var _tabs: Array = []
var _frames := 0
var _shot_path := ""
var _target_size := Vector2i(1920, 1080)
var _commander := "指挥官 · 沧澜"
var _delta_v := 0.0
var _transfer_ok := false


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var sz := OS.get_environment("DSH_HUD_SIZE")
	if sz == "":
		sz = "1920x1080"
	var parts := sz.split("x")
	if parts.size() == 2:
		_target_size = Vector2i(int(parts[0]), int(parts[1]))
	var win := get_window()
	if win != null:
		win.size = _target_size
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	tok = Tokens.new()
	_commander = OS.get_environment("DSH_PLAYER_NAME")
	if _commander == "":
		_commander = String(get_tree().root.get_meta("player_name", "沧澜"))
	if _commander == "":
		_commander = "沧澜"
	if _commander.begins_with("指挥官"):
		pass
	else:
		_commander = "指挥官 · " + _commander
	_load_data()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	if _shot_path != "":
		get_window().size = _target_size
		Input.warp_mouse(Vector2(_target_size) * 0.5)


func _load_data() -> void:
	_contacts = []
	var parsed = null
	if FileAccess.file_exists(SCENARIO):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	if parsed is Dictionary:
		for raw in (parsed.get("entities", []) if parsed.get("entities", []) is Array else []):
			if not (raw is Dictionary):
				continue
			var e: Dictionary = raw
			var kind := String(e.get("kind", "ship"))
			_contacts.append({"id": String(e.get("batch", e.get("id", ""))), "name": String(e.get("name", "")),
				"cls": kind.to_upper(), "type": "station" if kind == "station" else "friendly",
				"badge": "PORT" if kind == "station" else ("FLAG" if String(e.get("id", "")) == "apsis" else "FRIEND"),
				"threat": "none", "demo": false})
	# 明确一个 DEMO 接触，避免把示例当真实目标。
	_contacts.append({"id": "DEMO-2001", "name": "AV-4412 传唤者", "cls": "DEMO TARGET", "type": "unknown",
		"badge": "DEMO", "threat": "unknown", "demo": true})
	while _contacts.size() < 8:
		var i := _contacts.size()
		_contacts.append({"id": "DEMO-%03d" % i, "name": "接触样张 DEMO %d" % i, "cls": "DEMO", "type": "neutral",
			"badge": "DEMO", "threat": "none", "demo": true})
	_selected = 0
	if FileAccess.file_exists(TRANSFER):
		var d = JSON.parse_string(FileAccess.get_file_as_string(TRANSFER))
		if d is Dictionary:
			var budget: Dictionary = d.get("budget", {}) if d.get("budget", {}) is Dictionary else {}
			_delta_v = float(budget.get("total_dv_mps", 0.0))
			_transfer_ok = _delta_v > 0.0


func _process(delta: float) -> void:
	_t += delta
	for item in _timers:
		var d: Dictionary = item
		d["remain"] = maxf(0.0, float(d.get("remain", 0.0)) - delta)
	queue_redraw()
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("V1 HUD SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _type_col(t: Dictionary) -> Color:
	match String(t.get("type", "")):
		"friendly":
			return P.PH_DIM
		"station":
			return P.FAINT
		"unknown":
			return P.AMBER
		"neutral":
			return P.BLUE
		_:
			return P.DIM


func _draw() -> void:
	var l: Dictionary = tok.layout(size.x, size.y)
	var top: Rect2 = l.top
	var left: Rect2 = l.left
	var center: Rect2 = l.center
	var right: Rect2 = l.right
	var bottom: Rect2 = l.bottom
	draw_rect(Rect2(Vector2.ZERO, size), P.BG)
	# 顶栏
	Painter.panel(self, top, "", P.PH)
	Painter.label(self, top.position.x + 14, top.position.y + 22, "GHOST TRACK // APSIS", 11, P.PH, true)
	Painter.label(self, top.position.x + 14, top.position.y + 43, _commander, 15, P.PH)
	Painter.label(self, top.position.x + 14, top.position.y + 58, "MISSION T+%s · L1 港内 %s · DEMO SAMPLE" % [_clock(12 * 60 + 8 + _t), _clock(6 * 3600 + 42 * 60 + 17)], 7, P.a(P.DIM, 0.95), true)
	var tx := top.position.x + 300.0
	Painter.label(self, tx, top.position.y + 20, "动态计时 / TIMERS", 7, P.a(P.FAINT, 0.95), false)
	for i in range(_timers.size()):
		var timer: Dictionary = _timers[i]
		var remain := float(timer.get("remain", 0.0))
		var total := maxf(1.0, float(timer.get("total", 1.0)))
		var col := P.AMBER if i == 0 else (P.BLUE if i == 1 else P.PH)
		var y := top.position.y + 36.0 + float(i) * 11.0
		Painter.label(self, tx, y, "%s %s" % [String(timer.get("label", "")), _clock(remain)], 6, col, true)
		draw_rect(Rect2(tx + 160, y - 6, 76, 3), P.a(P.LINE, 0.9))
		draw_rect(Rect2(tx + 160, y - 6, 76.0 * clampf(remain / total, 0.0, 1.0), 3), P.a(col, 0.9))
	# 右侧槽
	var rx := top.end.x - 150.0
	Painter.label(self, rx, top.position.y + 20, "链路 / 时标 / Δv / ROE", 7, P.a(P.PH, 0.75), false)
	Painter.label(self, rx, top.position.y + 35, "LINK OK · 無線電 8s", 6, P.TXT, true)
	Painter.label(self, rx, top.position.y + 48, "×1 · Δv %s" % ("%.1f m/s" % _delta_v if _transfer_ok else "NOT READY"), 6, P.a(P.DIM, 0.95), true)
	Painter.label(self, rx, top.position.y + 60, "ROE WEAPONS HOLD / 仅自衛", 6, P.a(P.DIM, 0.95), true)
	# 三色点
	_top_dots.clear()
	for i in range(3):
		var dp := Vector2(top.end.x - 22.0 - float(i) * 20.0, top.position.y + 15.0)
		var cols := [Color("#6DE6A2"), Color("#E8C24B"), Color("#E2564A")]
		draw_circle(dp, 6.0, P.a(cols[i], 0.2))
		draw_circle(dp, 3.5, P.a(cols[i], 0.95))
		_top_dots.append({"rect": Rect2(dp - Vector2(10, 10), Vector2(20, 20)), "kind": ["save", "menu", "quit"][i]})
	# 左接触
	Painter.panel(self, left, "接触 / CONTACTS", P.PH)
	var ly := left.position.y + 34.0
	Painter.label(self, left.position.x + 12, ly, "友军 / FRIENDLY", 7, P.a(P.PH_DIM, 0.95))
	Painter.label(self, left.end.x - 12, ly, ("▸" if _collapsed else "▾") + "  %02d" % _contacts.size(), 7, P.PH, true)
	PersonPainterDivider(left, ly + 5.0)
	_contact_rects.clear()
	if not _collapsed:
		var row_y := ly + 16.0
		for i in range(_contacts.size()):
			var c: Dictionary = _contacts[i]
			var rh := 42.0 if String(c.get("type", "")) == "unknown" else 48.0
			if row_y + rh > left.end.y - 40.0:
				break
			var tr := Rect2(left.position.x + 8, row_y, left.size.x - 16, rh)
			_contact_rects.append({"rect": tr, "index": i})
			Painter.list_row(self, tr, "[%s] %s" % [String(c.get("id", "")), String(c.get("name", ""))], String(c.get("badge", "")), _type_col(c), i == _selected)
			Painter.label(self, tr.position.x + 8, tr.position.y + 31, String(c.get("cls", "")), 6, P.a(P.FAINT, 0.95), true)
			row_y += rh + 4.0
	# 中图
	Painter.panel(self, center, "战术图 / TACTICAL PLOT", P.PH)
	_draw_map(center)
	# 右栏
	Painter.panel(self, right, "", P.PH)
	_draw_right(right)
	# 底部
	Painter.panel(self, bottom, "", P.PH)
	_draw_bottom(bottom)


func PersonPainterDivider(r: Rect2, y: float) -> void:
	draw_line(Vector2(r.position.x + 10, y), Vector2(r.end.x - 10, y), P.a(P.LINE, 0.8), 1.0)


func _draw_map(r: Rect2) -> void:
	var area := Rect2(r.position.x + 12, r.position.y + 34, r.size.x - 24, r.size.y - 46)
	draw_rect(area, P.a(P.EARTH, 0.55))
	draw_rect(area, P.a(P.LINE, 0.6), false, 1.0)
	for i in range(180):
		var hh := (i * 1103515245 + 12345) & 0x7fffffff
		draw_rect(Rect2(area.position.x + 8 + float(hh % int(maxf(1.0, area.size.x - 16))),
			area.position.y + 8 + float((hh / 97) % int(maxf(1.0, area.size.y - 80))), 1, 1), P.a(P.TXT, 0.08))
	var p0 := Vector2(area.position.x + area.size.x * 0.26, area.position.y + area.size.y * 0.28)
	var p1 := Vector2(area.position.x + area.size.x * 0.72, area.position.y + area.size.y * 0.62)
	draw_arc(p0, 90, 0, TAU, 64, P.a(P.PH_DIM, 0.2), 1.0, true)
	draw_line(p0, p1, P.a(P.AMBER, 0.8), 1.0)
	draw_circle(p0, 3.0, P.AMBER)
	draw_circle(p1, 3.0, P.PH)
	Painter.label(self, p0.x - 20, p0.y - 12, "L4-02 HAMMER", 7, P.AMBER, true)
	Painter.label(self, p1.x + 6, p1.y + 16, "L1 MERIDIAN", 7, P.PH, true)
	for i in range(5):
		var q := p0.lerp(p1, 0.18 + float(i) * 0.04) + Vector2(float(i - 2) * 6.0, float(i - 2) * 4.0)
		draw_circle(q, 2.0, P.PH_DIM)
	var ty := area.end.y - 34.0
	draw_line(Vector2(area.position.x + 12, ty), Vector2(area.end.x - 12, ty), P.a(P.LINE2, 0.7), 1.0)
	draw_line(Vector2(area.position.x + 12 + area.size.x * 0.42, ty - 7), Vector2(area.position.x + 12 + area.size.x * 0.42, ty + 7), P.a(P.AMBER, 0.85), 1.0)
	Painter.label(self, area.position.x + 12, ty - 12, "T+00:00 · TOF 144:00:00 · WINDOW OPEN 18:00 / CLOSE 24:00", 7, P.TXT, true)
	Painter.label(self, area.position.x + 12, area.end.y - 14, "DEMO SAMPLE · TOKEN LAYOUT · V1 PALETTE", 6, P.a(P.FAINT, 0.9), true)


func _draw_right(r: Rect2) -> void:
	var x := r.position.x + 12.0
	var right := r.end.x - 12.0
	var y := r.position.y + 34.0
	_tabs = [{"rect": Rect2(x, r.position.y + 4, 70, 18), "page": "ship"}, {"rect": Rect2(x + 76, r.position.y + 4, 76, 18), "page": "target"}]
	for tab in _tabs:
		var active := String(tab.get("page", "")) == _page
		var tr: Rect2 = tab["rect"]
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.10 if active else 0.04))
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.65 if active else 0.25), false, 1.0)
		Painter.label(self, tr.position.x + 6, tr.position.y + 13, "SHIP" if String(tab.get("page", "")) == "ship" else "TARGET", 7, P.PH if active else P.FAINT, true)
	var c: Dictionary = _contacts[_selected] if _selected >= 0 and _selected < _contacts.size() else {}
	Painter.label(self, x, y + 8, String(c.get("name", "NOT READY")), 12, P.TXT)
	Painter.label(self, x, y + 22, "BATCH %s · %s · %s" % [String(c.get("id", "—")), String(c.get("type", "unknown")).to_upper(), String(c.get("badge", "—"))], 7, P.PH_DIM, true)
	y += 40.0
	Painter.section(self, x, y, right, "SENSOR / 传感器")
	y += 14.0
	Painter.label(self, x, y, "SENSOR DEMO · RADAR ON · OPTICAL OFF", 7, P.TXT, true)
	y += 13.0
	Painter.label(self, x, y, "OBS 0 · IFF 0 · CH 0 · TRACK L2", 7, P.a(P.DIM, 0.9), true)
	y += 18.0
	Painter.section(self, x, y, right, "DAMAGE / 损管")
	y += 14.0
	Painter.label(self, x, y, "INTEGRITY 100% · FIRE 0 · NOMINAL", 7, P.TXT, true)
	y += 18.0
	Painter.section(self, x, y, right, "ROE / Δv")
	y += 14.0
	Painter.key_value(self, x, y, right, "ROE", "WEAPONS HOLD", P.AMBER)
	y += 12.0
	Painter.key_value(self, x, y, right, "Δv", "%.1f m/s" % _delta_v if _transfer_ok else "NOT READY", P.TXT)
	y += 22.0
	Painter.section(self, x, y, right, "ACTIONS")
	y += 10.0
	var labels := ["NAV / 导航", "DAMAGE / 损管", "OPTICAL / 光学", "INFO / 信息"]
	for i in range(labels.size()):
		var bw := (r.size.x - 32.0) * 0.5 - 4.0
		var br := Rect2(x + float(i % 2) * (bw + 8.0), y + float(i / 2) * 28.0, bw, 22.0)
		Painter.button(self, br, labels[i], true, P.PH)
	Painter.label(self, x, r.end.y - 14, "READ-ONLY SAMPLE · 不实现玩法", 6, P.a(P.FAINT, 0.9), true)


func _draw_bottom(r: Rect2) -> void:
	var split := r.position.x + floorf(r.size.x * 0.56)
	var y := r.position.y + 40.0
	Painter.label(self, r.position.x + 12, r.position.y + 20, "命令队列 / COMMAND QUEUE · DEMO", 8, P.PH, false)
	Painter.label(self, split + 12, r.position.y + 20, "事件日志 / EVENT LOG · DEMO", 8, P.PH, false)
	Painter.divider(self, r.position.x + 10, r.position.y + 26, r.end.x - 10)
	draw_line(Vector2(split, r.position.y + 10), Vector2(split, r.end.y - 10), P.a(P.LINE, 0.8), 1.0)
	var cmds := [
		["CMD-01", "QUEUED", "指挥官", "哈马丹", "LD", "8.0s"],
		["CMD-02", "TRANSMITTED", "哈马丹", "L1 港", "LR", "1.0s"],
		["CMD-03", "EXECUTING", "指挥官", "远地点", "LD", "—"],
	]
	for i in range(cmds.size()):
		var c: Array = cmds[i]
		var col := P.PH if c[1] == "EXECUTING" else (P.AMBER if c[1] == "QUEUED" else P.DIM)
		Painter.label(self, r.position.x + 12, y + float(i) * 14.0, "%s %s · %s → %s · %s · %s" % [String(c[0]), String(c[1]), String(c[2]), String(c[3]), String(c[4]), String(c[5])], 7, col, true)
	var evs := [
		["0.0s", "tactical.timer", "BURN WINDOW"],
		["0.1s", "order.issued", "COMMAND ISSUED"],
		["0.1s", "sensor.radar", "RADAR OBS"],
		["0.2s", "teaching.note", "STEP T07-G1-S2"],
	]
	for i in range(evs.size()):
		var e: Array = evs[i]
		Painter.label(self, split + 12, y + float(i) * 14.0, "%s  %s" % [String(e[0]), String(e[1])], 7, P.PH_DIM if i == 0 else P.DIM, true)
		Painter.label(self, split + 154, y + float(i) * 14.0, String(e[2]), 7, P.TXT, false)
	Painter.label(self, r.position.x + 12, r.end.y - 8, "DEMO DATA · NO GAMESESSION · 自绘 V1 HUD SAMPLE", 6, P.a(P.AMBER, 0.85), true)


func _clock(s: float) -> String:
	var sec := int(maxf(0.0, s))
	return "%02d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for d in _top_dots:
		if (d["rect"] as Rect2).has_point(event.position):
			print("[V1 HUD] dot ", String(d.get("kind", "")), " · sample only / no save")
			return
	for c in _contact_rects:
		if (c["rect"] as Rect2).has_point(event.position):
			_selected = int(c.get("index", 0))
			_page = "target" if String((_contacts[_selected] as Dictionary).get("type", "")) in ["unknown", "neutral"] else "ship"
			return
	for tab in _tabs:
		if (tab["rect"] as Rect2).has_point(event.position):
			_page = String(tab.get("page", "ship"))
			return
