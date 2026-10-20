extends Control

# 阶段1A 左侧接触列表：Control 绘制；友军可折叠、无威胁隐藏、目标牌缩小、
# 类型底色、选中高亮；示例数据。

signal contact_selected(index: int, data: Dictionary)
signal log_line(text: String)

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var collapsed := false
var show_no_threat := false
var selected := 0
var _rects: Array = []
var _samples: Array = []  # 由 UI 层从 content/schema 加载；不再硬编码



func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_contacts(rows: Array) -> void:
	_samples = []
	for raw in rows:
		if raw is Dictionary:
			_samples.append((raw as Dictionary).duplicate(true))
	selected = clampi(selected, 0, maxi(0, _samples.size() - 1))
	queue_redraw()


func _type_col(t: Dictionary) -> Color:
	if bool(t.get("selected", false)):
		return P.PH
	match String(t.get("type", "")):
		"friendly":
			return P.PH_DIM
		"unknown":
			return P.AMBER
		"neutral":
			return P.BLUE
		"station":
			return P.FAINT
		_:
			return P.DIM


func _visible_rows() -> Array:
	var out: Array = []
	for i in range(_samples.size()):
		var t: Dictionary = _samples[i]
		if not show_no_threat and String(t.get("threat", "")) == "none" and String(t.get("type", "")) != "friendly":
			continue
		out.append({"index": i, "data": t})
	return out


func _draw() -> void:
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), P.PANEL)
	_rects.clear()
	var cjk := F.cjk()
	var mono := F.mono()
	draw_string(cjk, Vector2(12, 18), "接触 / CONTACTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TXT)
	draw_string(mono, Vector2(size.x - 54, 18), "%02d" % _samples.size(), HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, P.FAINT)
	draw_string(cjk, Vector2(12, 34), "友军 / FRIENDLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.PH_DIM, 0.9))
	var fold := "▾" if not collapsed else "▸"
	draw_string(mono, Vector2(size.x - 28, 34), fold, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, P.PH)
	draw_rect(Rect2(8, 40, size.x - 16, 1), P.a(P.LINE, 0.8))
	_rects.append({"rect": Rect2(size.x - 40, 22, 32, 18), "kind": "header"})
	if collapsed:
		draw_string(cjk, Vector2(12, 60), "（已折叠 · 点击顶部展开）", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.FAINT)
		return
	var y := 50.0
	if _samples.is_empty():
		draw_string(cjk, Vector2(12, 64), "NO CONTACT DATA · 未加载内容文件", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.AMBER)
		return
	var rows := _visible_rows()
	for i in range(rows.size()):
		var entry: Dictionary = rows[i]
		var t: Dictionary = entry.get("data", {})
		var idx := int(entry.get("index", 0))
		t["selected"] = idx == selected
		var ttype := String(t.get("type", ""))
		var h := 44.0 if ttype == "unknown" or ttype == "station" else 50.0
		var r := Rect2(8, y, size.x - 16, h)
		var col := _type_col(t)
		draw_rect(r, P.a(col, 0.10 if idx == selected else 0.035))
		draw_rect(Rect2(r.position, Vector2(2, h)), P.a(col, 0.85 if idx == selected else 0.35))
		draw_rect(r, P.a(col, 0.40 if idx == selected else 0.16), false, 1.0)
		draw_string(mono, Vector2(r.position.x + 8, y + 13), "[%s]" % String(t.get("id", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(col, 0.9))
		draw_string(cjk, Vector2(r.position.x + 54, y + 13), String(t.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.TXT if idx == selected else P.DIM)
		draw_string(mono, Vector2(r.position.x + 8, y + 28), String(t.get("cls", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.95))
		draw_string(mono, Vector2(r.end.x - 64, y + 12), String(t.get("badge", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(col, 0.75))
		# threat / type bar
		var thc := P.THR_MED if String(t.get("threat", "")) == "med" else (P.THR_LOW if String(t.get("threat", "")) == "low" else P.THR_NONE)
		draw_rect(Rect2(r.position.x + 8, y + h - 6, 64, 2), P.a(thc, 0.65))
		_rects.append({"rect": r, "kind": "row", "index": idx})
		y += h + 4.0
		if y > size.y - 40:
			break
	draw_string(mono, Vector2(10, size.y - 10), "NO-THREAT HIDDEN · 无威胁已隐藏", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for raw in _rects:
			var r: Dictionary = raw
			if (r["rect"] as Rect2).has_point(event.position):
				if String(r.get("kind", "")) == "header":
					collapsed = not collapsed
					log_line.emit("CONTACT FOLD " + str(collapsed))
				elif String(r.get("kind", "")) == "row":
					selected = int(r.get("index", 0))
					contact_selected.emit(selected, _samples[selected])
					log_line.emit("SELECT CONTACT " + String((_samples[selected] as Dictionary).get("id", "")))
				queue_redraw()
				return
