extends Control

# 方案B-15 副官通话面板：V1 自绘，文本来自 StoryTextLibrary deputy.*。
# 手动点击下一句；最后按钮进入导航；不自动跳过。

signal finished

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var _lines: Array = []
var _index := 0
var _next_rect := Rect2()
var _panel := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(lines: Array) -> void:
	_lines = lines.duplicate()
	_index = 0
	queue_redraw()


func show_all_for_shot() -> void:
	_index = maxi(0, _lines.size() - 1)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), P.a(P.BG, 0.55))
	_panel = Rect2(size.x * 0.18, size.y * 0.18, size.x * 0.64, size.y * 0.58)
	draw_rect(_panel, P.a(P.PANEL, 0.98))
	draw_rect(_panel, P.a(P.LINE2, 0.65), false, 1.0)
	draw_string(F.cjk(), _panel.position + Vector2(28, 36), "副官通话 / DEPUTY CALL", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.PH)
	draw_string(F.mono(), _panel.position + Vector2(28, 54), "SOURCE StoryTextLibrary deputy.* · 手动下一句 · 不自动跳过", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))
	draw_line(_panel.position + Vector2(24, 66), Vector2(_panel.end.x - 24, _panel.position.y + 66), P.a(P.LINE, 0.8), 1.0)
	var y := _panel.position.y + 98.0
	var shown := mini(_index + 1, _lines.size())
	for i in range(shown):
		var text := String(_lines[i])
		var wrapped := _wrap(text, 82)
		draw_string(F.cjk(), Vector2(_panel.position.x + 28, y), "副官 / DEPUTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.AMBER, 0.9))
		y += 18.0
		for line in wrapped:
			draw_string(F.cjk(), Vector2(_panel.position.x + 28, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TXT)
			y += 16.0
		y += 8.0
	_next_rect = Rect2(_panel.end.x - 220, _panel.end.y - 46, 192, 28)
	var last := _index >= _lines.size() - 1
	draw_rect(_next_rect, P.a(P.PANEL2, 0.9))
	draw_rect(_next_rect, P.a(P.PH if last else P.AMBER, 0.7), false, 1.0)
	draw_string(F.cjk(), _next_rect.position + Vector2(14, 19), "进入导航 / ENTER NAV" if last else "下一句 / NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
	draw_string(F.mono(), Vector2(_panel.position.x + 28, _panel.end.y - 18), "LINE %d/%d · V1 SELF-DRAWN · 文本原样" % [_index + 1, _lines.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _next_rect.has_point(event.position):
		return
	if _index < _lines.size() - 1:
		_index += 1
		queue_redraw()
		accept_event()
	else:
		finished.emit()
		accept_event()


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
