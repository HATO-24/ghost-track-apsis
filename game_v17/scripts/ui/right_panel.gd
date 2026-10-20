extends Control

# 阶段1D 右栏：选中舰船/目标页（V1 密度）。
# 数据来源：selected contact（scenario content）+ GameSession snapshot（若接入）；
# 当前 ui_proto 无 GameSession → 明确 DEMO / NOT READY，不伪造实时传感器。

signal page_action(kind: String)

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var selected: Dictionary = {}
var snapshot: Dictionary = {}
var session_entities: Array = []
var page := "ship"
var data_source := "DEMO"
var _action_rects: Array = []
var _tabs: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(344, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_selected(contact: Dictionary) -> void:
	selected = contact.duplicate(true)
	queue_redraw()


func set_snapshot(snap: Dictionary) -> void:
	snapshot = snap if snap is Dictionary else {}
	session_entities = snapshot.get("entities", []) if snapshot.get("entities", []) is Array else []
	queue_redraw()


func _session_entity() -> Dictionary:
	if selected.is_empty():
		return {}
	var sid := String(selected.get("entity_id", selected.get("id", "")))
	var batch := String(selected.get("id", ""))
	for raw in session_entities:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if String(e.get("id", "")) == sid or String(e.get("batch", "")) == batch:
			return e
	return {}


func set_page(p: String) -> void:
	page = "target" if p == "target" else "ship"
	queue_redraw()


func _fields() -> Dictionary:
	var f := {
		"name": "NOT READY", "batch": "—", "identity": "—", "range": "—",
		"sensor": "SENSOR NOT READY", "damage": "DAMAGE NOT READY",
		"roe": "ROE —", "dv": "Δv —", "source": "DEMO",
	}
	if page == "target":
		f["name"] = "AV-4412 传唤者"
		f["batch"] = "2001"
		f["identity"] = "UNKNOWN · IFF SHADOW"
		f["range"] = "— km · contact L0"
		f["sensor"] = "RADAR — · OPTICAL — · IR —"
		f["damage"] = "N/A · 非己方"
		f["roe"] = "WEAPONS HOLD / 需授权"
		f["dv"] = "N/A"
		f["source"] = "DEMO TARGET · NO SESSION"
		return f
	if selected.is_empty():
		return f
	if String(selected.get("badge", "")) == "DEMO TRACK":
		f["name"] = "TRACK EXAMPLE / DEMO"
		f["batch"] = "TRACK-EX"
		f["identity"] = "DEMO TRACK · identity unknown"
		f["range"] = "— km · track schema example"
		f["sensor"] = "SENSOR NOT READY · track demo 无传感器"
		f["damage"] = "DAMAGE NOT READY · track demo"
		f["roe"] = "ROE NOT READY"
		f["dv"] = "Δv NOT READY"
		f["source"] = "DEMO TRACK"
		return f
	var e := _session_entity()
	if not e.is_empty():
		var eid := String(e.get("id", ""))
		f["name"] = String(e.get("name", eid))
		f["batch"] = String(e.get("batch", eid))
		var flags: Dictionary = e.get("flags", {}) if e.get("flags", {}) is Dictionary else {}
		f["identity"] = "FRIEND · " + ("FLAGSHIP" if bool(flags.get("flagship", false)) else String(e.get("kind", "ship")).to_upper())
		var pos: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else []
		var range_km := 0.0
		var flag_pos: Array = []
		for raw in session_entities:
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "apsis":
				flag_pos = (raw as Dictionary).get("pos_km", []) if (raw as Dictionary).get("pos_km", []) is Array else []
				break
		if pos.size() >= 3 and flag_pos.size() >= 3:
			var dx := float(pos[0]) - float(flag_pos[0])
			var dy := float(pos[1]) - float(flag_pos[1])
			var dz := float(pos[2]) - float(flag_pos[2])
			range_km = sqrt(dx * dx + dy * dy + dz * dz)
		f["range"] = "%.1f km · %s" % [range_km, String(e.get("kind", "ship")).to_upper()]
		f["source"] = "GAME SESSION"
		f["sensor"] = "SENSOR NOT IN SESSION · NOT READY"
		f["damage"] = "DAMAGE NOT IN SESSION · NOT READY"
		f["roe"] = "ROE NOT IN SESSION · NOT READY"
		f["dv"] = "Δv NOT IN SESSION · NOT READY"
		return f
	f["name"] = String(selected.get("name", "NOT READY"))
	f["batch"] = String(selected.get("id", "—"))
	f["identity"] = String(selected.get("side", "unknown")).to_upper() + " · " + String(selected.get("badge", "—"))
	f["range"] = "— km · " + String(selected.get("cls", "CLASS —"))
	f["source"] = "DEMO · NO SESSION"
	f["sensor"] = "SENSOR NOT READY"
	f["damage"] = "DAMAGE NOT READY"
	f["roe"] = "ROE NOT READY"
	f["dv"] = "Δv NOT READY"
	return f


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), r)
	else:
		draw_rect(r, P.PANEL)
	var f := _fields()
	var cjk := F.cjk()
	var mono := F.mono()
	var y := 18.0
	_tabs.clear()
	_tabs.append({"rect": Rect2(12, 4, 76, 18), "page": "ship"})
	_tabs.append({"rect": Rect2(94, 4, 84, 18), "page": "target"})
	for tab in _tabs:
		var t: Dictionary = tab
		var active := String(t.get("page", "")) == page
		var tr: Rect2 = t["rect"]
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.10 if active else 0.05))
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.65 if active else 0.30), false, 1.0)
		draw_string(mono, Vector2(tr.position.x + 6, tr.position.y + 13), "SHIP" if String(t.get("page", "")) == "ship" else "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH if active else P.FAINT)
	draw_string(mono, Vector2(size.x - 116, 13), f["source"], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.AMBER, 0.9))
	y = 36.0
	draw_string(cjk, Vector2(12, y), f["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TXT)
	y += 18.0
	draw_string(mono, Vector2(12, y), "BATCH " + String(f["batch"]) + " · " + String(f["identity"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH_DIM)
	y += 14.0
	draw_string(cjk, Vector2(12, y), "距离 / RANGE  " + String(f["range"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
	y += 18.0
	draw_line(Vector2(10, y), Vector2(size.x - 10, y), P.a(P.LINE, 0.8), 1.0)
	y += 14.0
	# 传感器摘要
	draw_string(cjk, Vector2(12, y), "传感器 / SENSOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	y += 13.0
	draw_string(mono, Vector2(12, y), String(f["sensor"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	y += 15.0
	# 损管
	draw_string(cjk, Vector2(12, y), "损管 / DAMAGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	y += 13.0
	draw_string(mono, Vector2(12, y), String(f["damage"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	y += 15.0
	# ROE / Δv
	draw_string(cjk, Vector2(12, y), "ROE / 交战规则", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	y += 13.0
	draw_string(mono, Vector2(12, y), String(f["roe"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	y += 15.0
	draw_string(cjk, Vector2(12, y), "Δv 分配", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	y += 13.0
	draw_string(mono, Vector2(12, y), String(f["dv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	y += 18.0
	draw_line(Vector2(10, y), Vector2(size.x - 10, y), P.a(P.LINE, 0.75), 1.0)
	y += 14.0
	draw_string(cjk, Vector2(12, y), "按钮槽位 / ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.FAINT)
	y += 8.0
	_action_rects.clear()
	var labels := [["NAV", "导航 / NAV"], ["DMG", "损管 / DAMAGE"], ["OPT", "光学 / OPTICAL"], ["INFO", "信息 / INFO OPS"]]
	var start_y := size.y - 92.0
	for i in range(labels.size()):
		var bw := (size.x - 30.0) * 0.5 - 4.0
		var bx := 12.0 + float(i % 2) * (bw + 8.0)
		var by := start_y + float(i / 2) * 26.0
		var br := Rect2(bx, by, bw, 22.0)
		_action_rects.append({"rect": br, "kind": String(labels[i][0])})
		draw_rect(br, P.a(P.PANEL2, 0.8))
		draw_rect(br, P.a(P.LINE2, 0.65), false, 1.0)
		draw_string(cjk, Vector2(br.position.x + 6, br.position.y + 15), String(labels[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	draw_string(mono, Vector2(12, size.y - 12), "READ-ONLY · 不实现剧情/物理/存档", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for tab in _tabs:
		if (tab["rect"] as Rect2).has_point(event.position):
			set_page(String(tab.get("page", "ship")))
			accept_event()
			return
	for raw in _action_rects:
		var a: Dictionary = raw
		if (a["rect"] as Rect2).has_point(event.position):
			page_action.emit(String(a.get("kind", "")))
			accept_event()
			return
