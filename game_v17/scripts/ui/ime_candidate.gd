extends Control

# 阶段1B 自绘 IME 候选窗：V1 风格；分页/滚动；位置避让输入框与屏幕边界。
# 仅视觉/交互；候选由 ImeInput 外部注入（不调用系统 IME 候选）。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")

const WIDTH := 300.0
const ROW_H := 22.0
const HEAD_H := 58.0
const FOOT_H := 26.0
const PAGE_SIZE := 5

var composition := ""
var candidates: Array = []
var selected := 0
var page := 0
var last_placement := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func set_data(comp: String, cands: Array, sel: int, pg: int) -> void:
	composition = comp
	candidates = cands.duplicate()
	selected = clampi(sel, 0, maxi(0, candidates.size() - 1))
	page = maxi(0, pg)
	visible = composition != "" and not candidates.is_empty()
	if visible:
		size = Vector2(WIDTH, HEAD_H + ROW_H * float(mini(PAGE_SIZE, candidates.size())) + FOOT_H)
	queue_redraw()


func page_count() -> int:
	return maxi(1, int(ceil(float(candidates.size()) / float(PAGE_SIZE))))


func current_page_rows() -> Array:
	var out: Array = []
	var start := page * PAGE_SIZE
	for i in range(start, mini(start + PAGE_SIZE, candidates.size())):
		out.append({"index": i, "text": String(candidates[i])})
	return out


## 避让输入框：优先下方，越界则上方；贴边时夹紧屏幕内。
func place(input_rect: Rect2) -> void:
	if not visible:
		return
	var vp := Vector2(1920, 1080) if not is_inside_tree() else get_viewport_rect().size
	if vp.x <= 1.0:
		vp = Vector2(1920, 1080)
	# 优先输入框右侧；空间不足再下方/上方，避免覆盖输入框。
	var p := Vector2(input_rect.end.x + 6.0, input_rect.position.y)
	if p.x + size.x > vp.x - 8.0:
		p = Vector2(input_rect.position.x, input_rect.end.y + 4.0)
	if p.y + size.y > vp.y - 8.0:
		p.y = input_rect.position.y - size.y - 4.0
	p.x = clampf(p.x, 8.0, maxf(8.0, vp.x - size.x - 8.0))
	p.y = clampf(p.y, 8.0, maxf(8.0, vp.y - size.y - 8.0))
	position = p
	last_placement = p
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), P.PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), P.a(P.AMBER, 0.65), false, 1.0)
	var mono := F.mono()
	var cjk := F.cjk()
	draw_string(cjk, Vector2(10, 18), "候选 / CANDIDATES", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.AMBER)
	draw_string(mono, Vector2(size.x - 82, 18), "%d/%d" % [page + 1, page_count()], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))
	draw_string(mono, Vector2(10, 34), "组合: " + composition, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	draw_line(Vector2(8, 40), Vector2(size.x - 8, 40), P.a(P.LINE, 0.8), 1.0)
	var rows := current_page_rows()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var idx := int(row.get("index", 0))
		var y := HEAD_H + float(i) * ROW_H
		var sel := idx == selected
		if sel:
			draw_rect(Rect2(6, y - 16, size.x - 12, ROW_H - 2), P.a(P.AMBER, 0.10))
			draw_rect(Rect2(6, y - 16, 2, ROW_H - 2), P.a(P.AMBER, 0.85))
		draw_string(mono, Vector2(12, y), "%02d" % (idx + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.AMBER if sel else P.FAINT, 0.95))
		draw_string(cjk, Vector2(40, y), String(row.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TXT if sel else P.DIM)
	draw_line(Vector2(8, size.y - FOOT_H), Vector2(size.x - 8, size.y - FOOT_H), P.a(P.LINE, 0.65), 1.0)
	draw_string(cjk, Vector2(10, size.y - 9), "↑↓ 选择 · ENTER 确认 · ESC 取消 · PgUp/PgDn 翻页", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.95))
	var sel_text := ""
	if selected >= 0 and selected < candidates.size():
		sel_text = String(candidates[selected])
	draw_string(mono, Vector2(10, size.y - 22), "SELECTED: " + sel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH_DIM, 0.95))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in range(current_page_rows().size()):
		var row: Dictionary = current_page_rows()[i]
		var r := Rect2(6, HEAD_H + float(i) * ROW_H - 16, size.x - 12, ROW_H - 2)
		if r.has_point(event.position):
			selected = int(row.get("index", 0))
			queue_redraw()
			accept_event()
			return
