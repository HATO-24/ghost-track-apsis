extends "res://ui/widgets/scroll_view.gd"

## V2 通用动态列表（list view）：接触 / 命令 / 事件共用。
##
## 特性：
## - `items` 是纯 view-model 数组（Dictionary），由 `ui/data_source.gd` 刷新时重填；
## - 虚拟滚动：只绘制可见行（不创建每行 Node），行数 > 面板高度时可滚动、不截断；
## - 行选中（`selected_id`）+ 左键选择信号、右键上下文信号、悬停高亮、空态；
## - 两种行样式：`contact`（接触/命令：id + 标题 + 副标题 + L 徽标 + 身份）与
##   `log`（事件流：kind 标签 + 文本 + 时间）。
##
## 行 Dictionary 字段（contact）：
##   id, title, subtitle, badge, badge_color, accent, identity, side,
##   caps (int), synthetic (bool), enabled (bool, 默认 true)
## 行 Dictionary 字段（log）：
##   kind, text, time, accent

signal item_selected(id: String)
signal item_context(id: String, at: Vector2)
signal item_activated(id: String)

var items: Array = []
var row_mode := "contact"
var row_height := T.ROW_CONTACT
var header_h := 44.0
var list_title := "列表 / LIST"
var list_kicker := ""
var empty_title := "（暂无数据 / NO DATA）"
var empty_hint := ""
var selected_id := ""
var hover_id := ""
var header_right_inset := 0.0
var synthetic_tag := "DEMO"

var _hover_index := -1


func _ready() -> void:
	super._ready()
	scroll_step = row_height * 2.0
	mouse_exited.connect(_on_mouse_exited)


func body_rect() -> Rect2:
	var bar_reserve := bar_gap + bar_width + bar_margin
	return Rect2(
		12.0,
		header_h,
		maxf(8.0, size.x - 12.0 - bar_reserve - 12.0),
		maxf(8.0, size.y - header_h - 12.0))


# ══ 数据 ═════════════════════════════════════════════════════════════════

func set_row_mode(mode: String, h: float = -1.0) -> void:
	row_mode = mode
	if h > 0.0:
		row_height = h
	scroll_step = row_height * 2.0
	set_items(items)


func set_items(list: Array) -> void:
	items = list if list != null else []
	if selected_id != "" and item_index(selected_id) < 0:
		selected_id = ""
	_hover_index = -1
	scroll_step = row_height * 2.0
	set_content_height(float(items.size()) * row_height + 8.0)
	queue_redraw()


func set_selected(id: String) -> void:
	if selected_id == id:
		return
	selected_id = id
	queue_redraw()


func set_header(title: String, kicker: String = "") -> void:
	list_title = title
	list_kicker = kicker
	queue_redraw()


func set_empty(title: String, hint: String = "") -> void:
	empty_title = title
	empty_hint = hint
	queue_redraw()


func item_index(id: String) -> int:
	for i in range(items.size()):
		if String((items[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func item_at(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	return items[index]


func selected_item() -> Dictionary:
	return item_at(item_index(selected_id))


func visible_rows() -> int:
	return mini(items.size(), int(ceil(view_height() / row_height)) + 1)


func first_visible() -> int:
	return clampi(int(floor(offset / row_height)), 0, maxi(0, items.size() - 1))


func scroll_to_item(id: String) -> void:
	var i := item_index(id)
	if i < 0:
		return
	var top := float(i) * row_height
	if top < offset:
		scroll_to(top)
	elif top + row_height > offset + view_height():
		scroll_to(top + row_height - view_height())


## 控件内坐标 → 行号；不在内容区/越界返回 -1。
func row_at(pos: Vector2) -> int:
	var b := body_rect()
	if pos.x < b.position.x or pos.x > b.end.x or pos.y < b.position.y or pos.y > b.end.y:
		return -1
	var y := pos.y - b.position.y + offset
	var i := int(floor(y / row_height))
	if i < 0 or i >= items.size():
		return -1
	return i


## 行号 → 控件内矩形（滚动后的屏幕坐标），用于测试/自检。
func row_rect(index: int) -> Rect2:
	var b := body_rect()
	return Rect2(b.position.x, b.position.y + float(index) * row_height - offset, b.size.x, row_height)


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw_frame() -> void:
	T.panel(self, Rect2(0.0, 0.0, size.x, size.y), 0.965, 0.85)
	T.text(self, 16.0, 12.0, list_title, T.F11, T.TXT)
	if list_kicker != "":
		T.text(self, 16.0, 28.0, list_kicker, T.F7, T.FAINT)

	var count_col: Color = T.PH_DIM if items.size() > 0 else T.FAINT
	T.text_r(self, size.x - 16.0 - header_right_inset, 11.0, "%02d" % items.size(), T.F12, count_col, false)
	if is_scrollable():
		T.text_r(self, size.x - 16.0 - header_right_inset, 28.0,
			"%d%% · 滚轮" % int(round(scroll_ratio() * 100.0)), T.F7, T.FAINT)
	else:
		T.text_r(self, size.x - 16.0 - header_right_inset, 28.0, "FIT", T.F7, T.FAINT)
	T.hline(self, 12.0, header_h, size.x - 12.0, T.a(T.LINE, 0.9))

	if items.is_empty():
		var b := body_rect()
		var cy := b.position.y + b.size.y * 0.40
		T.text_c(self, 12.0 + b.size.x * 0.5, cy, empty_title, T.F10, T.FAINT)
		if empty_hint != "":
			T.text_c(self, 12.0 + b.size.x * 0.5, cy + 18.0, T.ellipsis(empty_hint, T.F8, b.size.x - 8.0), T.F8, T.a(T.FAINT, 0.8))


func _paint_content(ci: CanvasItem) -> void:
	if items.is_empty():
		return
	var first := int(floor(offset / row_height))
	var last := int(ceil((offset + view_height()) / row_height))
	first = clampi(first, 0, items.size() - 1)
	last = clampi(last, 0, items.size())
	for i in range(first, last):
		var y := float(i) * row_height - offset
		if row_mode == "log":
			_paint_log_row(ci, items[i], i, y)
		else:
			_paint_contact_row(ci, items[i], i, y)


func _row_width() -> float:
	return body_rect().size.x


func _paint_contact_row(ci: CanvasItem, it: Dictionary, i: int, y: float) -> void:
	var w := _row_width()
	var h := row_height
	var eid := String(it.get("id", ""))
	var sel := eid != "" and eid == selected_id
	var hovered := i == _hover_index
	var accent: Color = it.get("accent", T.PH)
	var enabled := bool(it.get("enabled", true))
	var dim := 1.0 if enabled else 0.45

	if sel:
		ci.draw_rect(Rect2(0.0, y, w, h), T.a(T.PANEL2, 0.95))
		ci.draw_rect(Rect2(0.0, y, 2.0, h), accent)
		ci.draw_rect(Rect2(0.0, y, w, 1.0), T.a(accent, 0.22))
	elif hovered:
		ci.draw_rect(Rect2(0.0, y, w, h), T.a(T.PANEL2, 0.55))
	ci.draw_line(Vector2(0.0, y + h - 1.0), Vector2(w, y + h - 1.0), T.a(T.LINE, 0.55), 1.0)

	var identity := String(it.get("identity", "unknown"))
	var id_col: Color = T.identity_color(identity)
	var id_label := String(it.get("id_label", eid))
	T.identity_glyph(ci, Vector2(11.0, y + 20.0), 4.5, identity, T.a(id_col, dim))
	T.text(ci, 22.0, y + 6.0, "[%s]" % id_label, T.F7, T.a(T.FAINT, dim), false)
	T.text_fit(ci, 22.0, y + 18.0, String(it.get("title", "")), T.F12, T.a(accent, dim), w - 84.0)

	# 右上：L 徽标；右中：身份；右下：能力数。
	var badge := String(it.get("badge", ""))
	if badge != "":
		var bcol: Color = it.get("badge_color", T.AMBER)
		T.badge(ci, Rect2(w - 30.0, y + 6.0, 22.0, 12.0), badge, bcol, T.F7)
	var identity_text := T.identity_label(identity)
	var idt_col: Color = T.a(id_col, 0.85 * dim)
	T.text_r(ci, w - 8.0, y + 20.0, identity_text, T.F7, idt_col)
	T.text_fit(ci, 22.0, y + 36.0, String(it.get("subtitle", "")), T.F8, T.a(T.DIM, dim), w - 92.0)
	var caps := int(it.get("caps", 0))
	T.text_r(ci, w - 8.0, y + 36.0, "%d CAP" % caps, T.F7, T.a(T.FAINT, 0.9 * dim), false)

	if bool(it.get("synthetic", false)):
		T.text(ci, 22.0, y + 49.0, synthetic_tag, T.F7, T.a(T.AMBER, 0.7), false)
	# 行底装饰条：用 accent 提示强度（不表示真实信号）。
	ci.draw_rect(Rect2(22.0, y + h - 7.0, 120.0, 1.0), T.a(accent, 0.20 * dim))


func _paint_log_row(ci: CanvasItem, it: Dictionary, i: int, y: float) -> void:
	var w := _row_width()
	var h := row_height
	var hovered := i == _hover_index
	if hovered:
		ci.draw_rect(Rect2(0.0, y, w, h), T.a(T.PANEL2, 0.5))
	ci.draw_line(Vector2(0.0, y + h - 1.0), Vector2(w, y + h - 1.0), T.a(T.LINE, 0.35), 1.0)
	var kind := String(it.get("kind", "SYS"))
	var col: Color = it.get("accent", T.PH)
	T.text(ci, 8.0, y + 9.0, kind, T.F7, T.a(col, 0.9), false)
	var text_w := w - 78.0 - 104.0
	T.text_fit(ci, 78.0, y + 8.0, String(it.get("text", "")), T.F9, T.a(T.TXT, 0.94), text_w)
	T.text_r(ci, w - 8.0, y + 9.0, String(it.get("time", "")), T.F7, T.a(T.FAINT, 0.9), false)
	if bool(it.get("fresh", false)):
		ci.draw_rect(Rect2(0.0, y, 2.0, h), T.a(col, 0.9))


# ══ 输入 ═════════════════════════════════════════════════════════════════

func _on_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var ri := row_at(mm.position)
		if ri != _hover_index:
			_hover_index = ri
			hover_id = String((items[ri] as Dictionary).get("id", "")) if ri >= 0 else ""
			queue_redraw()
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var idx := row_at(mb.position)
			if idx < 0:
				return false
			var it: Dictionary = items[idx]
			var eid := String(it.get("id", ""))
			if row_mode == "contact" and eid != "":
				selected_id = eid
				queue_redraw()
				item_selected.emit(eid)
			else:
				item_activated.emit(eid)
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			var ridx := row_at(mb.position)
			if ridx < 0:
				return false
			var rit: Dictionary = items[ridx]
			var reid := String(rit.get("id", ""))
			if row_mode == "contact" and reid != "":
				selected_id = reid
				queue_redraw()
				item_selected.emit(reid)
				item_context.emit(reid, get_global_rect().position + mb.position)
			return true
	return false


func _on_mouse_exited() -> void:
	if _hover_index != -1:
		_hover_index = -1
		hover_id = ""
		queue_redraw()
