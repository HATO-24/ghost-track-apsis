extends Control

# 阶段1H 序章简报面板：V1 行动简报格式。
# 文本来自 content JSON（prelude/notice 等 key），不在脚本内硬编码剧情。
# 不实现导航/物理/存档；只显示并发出 continue/skip。

signal continue_requested
signal skip_requested

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var data: Dictionary = {}
var _continue_rect := Rect2(1030, 884, 300, 30)
var _skip_rect := Rect2(1350, 884, 300, 30)


func _ready() -> void:
	custom_minimum_size = Vector2(1600, 960)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_data(d: Dictionary) -> void:
	data = d.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(160, 90), Vector2(1600, 880))
	draw_rect(Rect2(Vector2.ZERO, size), P.a(P.BG, 0.0))
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), r)
	else:
		draw_rect(r, P.PANEL)
	draw_rect(r, P.a(P.LINE2, 0.55), false, 1.0)
	var cjk := F.cjk()
	var mono := F.mono()
	draw_string(cjk, Vector2(r.position.x + 24, r.position.y + 30), "行动简报 / MISSION BRIEFING", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.PH)
	draw_string(mono, Vector2(r.position.x + 24, r.position.y + 50), "DRAFT · 剧本简报 / STORY BRIEFING · 2193-11-07", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.AMBER)
	draw_line(Vector2(r.position.x + 24, r.position.y + 60), Vector2(r.end.x - 24, r.position.y + 60), P.a(P.LINE, 0.8), 1.0)
	# FROM / TO
	draw_string(mono, Vector2(r.position.x + 24, r.position.y + 86), "FROM  " + String(data.get("from", "NOT READY")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TXT)
	draw_string(mono, Vector2(r.position.x + 24, r.position.y + 104), "TO    " + String(data.get("to", "NOT READY")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TXT)
	draw_string(mono, Vector2(r.position.x + 24, r.position.y + 122), "DATE  2193-11-07 · CLASS  DRAFT / INTERNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.FAINT, 0.95))
	# 任务摘要
	draw_string(cjk, Vector2(r.position.x + 24, r.position.y + 158), "任务摘要 / SUMMARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.PH_DIM)
	var body := String(data.get("body", "NOT READY"))
	var lines := _wrap(body, 82)
	var y := r.position.y + 178.0
	for i in range(mini(lines.size(), 11)):
		draw_string(cjk, Vector2(r.position.x + 24, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
		y += 14.0
	# 目标 / ROE
	y += 8.0
	draw_string(cjk, Vector2(r.position.x + 24, y), "目标 / OBJECTIVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.PH_DIM)
	y += 17.0
	for obj in (data.get("objectives", []) as Array):
		draw_string(cjk, Vector2(r.position.x + 32, y), "· " + String(obj), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
		y += 15.0
	y += 8.0
	draw_string(cjk, Vector2(r.position.x + 24, y), "ROE / 交战规则", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.PH_DIM)
	y += 17.0
	for roe_line in (data.get("roe", []) as Array):
		draw_string(cjk, Vector2(r.position.x + 32, y), "· " + String(roe_line), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.AMBER)
		y += 15.0
	# 左侧舰队编制
	var fy := r.position.y + 500.0
	draw_string(cjk, Vector2(r.position.x + 24, fy), "舰队编制 / FLEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.PH_DIM)
	fy += 18.0
	for raw in (data.get("fleet", []) as Array):
		var f: Dictionary = raw
		draw_string(mono, Vector2(r.position.x + 24, fy), "[%s] %s" % [String(f.get("batch", "—")), String(f.get("name", "—"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
		draw_string(mono, Vector2(r.position.x + 330, fy), String(f.get("role", "—")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))
		fy += 15.0
	# 星图示意（非真实导航）
	var map := Rect2(r.position.x + 900, r.position.y + 160, 650, 390)
	draw_rect(map, P.a(P.EARTH, 0.55))
	draw_rect(map, P.a(P.LINE, 0.7), false, 1.0)
	draw_string(cjk, Vector2(map.position.x + 12, map.position.y + 20), "星图示意 / SCHEMATIC · NOT FOR NAVIGATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))
	var c := map.position + map.size * 0.5
	draw_circle(c, 3.0, P.PH)
	draw_arc(c, 70.0, 0, TAU, 64, P.a(P.PH_DIM, 0.4), 1.0, true)
	draw_arc(c, 140.0, 0, TAU, 80, P.a(P.PH_DIM, 0.25), 1.0, true)
	var p0 := c + Vector2(-170, 50)
	var p1 := c + Vector2(130, -70)
	draw_line(p0, p1, P.a(P.AMBER, 0.8), 1.0)
	draw_circle(p0, 4.0, P.AMBER)
	draw_circle(p1, 4.0, P.PH)
	draw_string(mono, p0 + Vector2(-60, 18), "L4-02 HAMMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.AMBER)
	draw_string(mono, p1 + Vector2(-40, 20), "L1 MERIDIAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.PH)
	draw_line(Vector2(map.position.x + 12, map.end.y - 20), Vector2(map.position.x + 112, map.end.y - 20), P.a(P.PH, 0.5), 1.0)
	draw_string(mono, Vector2(map.position.x + 120, map.end.y - 17), "SCHEMATIC ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))
	# 按钮
	_continue_rect = Rect2(r.position.x + 870, r.position.y + 790, 300, 30)
	_skip_rect = Rect2(r.position.x + 1190, r.position.y + 790, 300, 30)
	_btn(_continue_rect, "继续 / DEPUTY CALL", true, P.PH)
	_btn(_skip_rect, "跳过简报 / SKIP", true, P.PH_DIM)
	draw_string(mono, Vector2(r.position.x + 24, r.end.y - 16), "TEXT SOURCE · StoryTextLibrary briefing.body · 原样引用，不润色 · 手动进入副官通话", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _wrap(text: String, width: int) -> Array:
	var out: Array = []
	var cur := ""
	for i in text.length():
		cur += text.substr(i, 1)
		if cur.length() >= width and text.substr(i, 1) in ["，", "。", "；", " ", "、"]:
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


func _btn(rect: Rect2, label: String, active: bool, col: Color) -> void:
	draw_rect(rect, P.a(P.PANEL2, 0.85))
	draw_rect(rect, P.a(col, 0.7 if active else 0.3), false, 1.0)
	draw_string(F.cjk(), Vector2(rect.position.x + 12, rect.position.y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TXT)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _continue_rect.has_point(event.position):
		continue_requested.emit()
		accept_event()
	elif _skip_rect.has_point(event.position):
		skip_requested.emit()
		accept_event()
