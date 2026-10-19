extends Control

## V2 通用滚动视图（scroll view）+ 滚动条模型。
##
## 干什么：
## - 管理 `content_height`（内容总高）与 `offset`（当前滚动位移）的夹取；
## - 在子节点 `ClipContent` 里绘制内容（内容超出视口时由子节点 `clip_contents` 裁切）；
## - 画右侧滚动条（轨道 + 滑块），支持滚轮、拖动滑块、点击轨道翻页；
## - 子类只需实现三个虚方法：`_draw_frame()`（画自己的框/头/脚）、
##   `_paint_content(ci)`（在内容层画可滚动内容，坐标已含 offset）、
##   `_on_input(event) -> bool`（处理行点击/悬停等，返回 true 表示已消费）。
##
## 虚拟滚动：子类在 `_paint_content` 里按 `offset`/`view_height()` 只画可见行，
## 不创建每行 Node；行数上千也不增加节点数。
##
## 与 core 无关；只依赖 theme tokens。

signal offset_changed(offset: float)

const T := preload("res://ui/theme.gd")


## 内容层：独立子节点，自带 `clip_contents`，内容超出部分被裁掉。
class ClipContent extends Control:
	var host: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if host != null:
			host.call("_paint_content", self)


var content_height := 0.0
var offset := 0.0
var scroll_step := 40.0
var bar_width := 6.0
var bar_gap := 4.0
var bar_margin := 6.0
var min_thumb := 18.0
var accent: Color = Color(0.549, 0.941, 0.753, 1.0)
var track_color: Color = Color(0.113, 0.267, 0.22, 1.0)
var always_show_bar := false

var _content: Control = null
var _drag_active := false
var _drag_grab := 0.0
var _hover_bar := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	accent = T.PH
	track_color = T.a(T.LINE, 0.55)
	_content = ClipContent.new()
	_content.host = self
	add_child(_content)
	_layout_content()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_content()


# ══ 子类接口（虚方法）════════════════════════════════════════════════════

## 视口矩形（不含滚动条）。子类按自己的 header/footer 覆盖。
func body_rect() -> Rect2:
	var pad := 16.0
	var bar_reserve := bar_gap + bar_width + bar_margin
	return Rect2(
		pad, pad,
		maxf(8.0, size.x - pad * 2.0 - bar_reserve),
		maxf(8.0, size.y - pad * 2.0))


func view_height() -> float:
	return body_rect().size.y


## 画框/标题/页脚。子类覆盖；基类默认画空。
func _draw_frame() -> void:
	pass


## 在 ClipContent 里画可滚动内容。子类覆盖；ci 为内容层节点。
func _paint_content(_ci: CanvasItem) -> void:
	pass


## 子类输入钩子（行点击/悬停）。返回 true = 已消费。
func _on_input(_event: InputEvent) -> bool:
	return false


# ══ 滚动模型 ═════════════════════════════════════════════════════════════

func set_content_height(h: float) -> void:
	content_height = maxf(h, 0.0)
	_clamp_offset()
	# 内容/数据变了：即使 offset 没变也要重画 ClipContent（只重画 frame 会留下旧数据）。
	queue_redraw()
	if _content != null:
		_content.queue_redraw()


func max_offset() -> float:
	return maxf(0.0, content_height - view_height())


func is_scrollable() -> bool:
	return max_offset() > 0.5


func scroll_to(y: float) -> void:
	_set_offset(y)


func scroll_by(dy: float) -> bool:
	var before := offset
	_set_offset(offset + dy)
	return not is_equal_approx(before, offset)


func scroll_to_top() -> void:
	scroll_to(0.0)


func scroll_to_bottom() -> void:
	scroll_to(max_offset())


## 滚动进度 0..1（不可滚时 0）。
func scroll_ratio() -> float:
	var mo := max_offset()
	return 0.0 if mo <= 0.5 else offset / mo


func first_visible_index(row_h: float) -> int:
	if row_h <= 0.0:
		return 0
	return int(floor(offset / row_h))


func visible_row_count(row_h: float) -> int:
	if row_h <= 0.0:
		return 0
	return int(ceil(view_height() / row_h)) + 1


func _set_offset(y: float) -> void:
	var clamped := clampf(y, 0.0, max_offset())
	if is_equal_approx(clamped, offset):
		return
	offset = clamped
	offset_changed.emit(offset)
	queue_redraw()
	if _content != null:
		_content.queue_redraw()


func _layout_content() -> void:
	if _content == null:
		return
	var b := body_rect()
	_content.position = b.position
	_content.size = b.size
	_clamp_offset()
	_content.queue_redraw()
	queue_redraw()


func _clamp_offset() -> void:
	var clamped := clampf(offset, 0.0, max_offset())
	if is_equal_approx(clamped, offset):
		return
	offset = clamped
	offset_changed.emit(offset)


func track_rect() -> Rect2:
	var b := body_rect()
	return Rect2(
		size.x - bar_margin - bar_width,
		b.position.y,
		bar_width,
		b.size.y)


func thumb_rect() -> Rect2:
	var tr := track_rect()
	if max_offset() <= 0.5:
		return Rect2(tr.position, Vector2(bar_width, tr.size.y))
	var frac := clampf(view_height() / maxf(content_height, 1.0), 0.0, 1.0)
	var h := clampf(tr.size.y * frac, min_thumb, tr.size.y)
	var travel := tr.size.y - h
	var y := tr.position.y + travel * scroll_ratio()
	return Rect2(tr.position.x, y, bar_width, h)


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	_draw_frame()
	_draw_scrollbar()


func _draw_scrollbar() -> void:
	if not is_scrollable() and not always_show_bar:
		return
	var tr := track_rect()
	var th := thumb_rect()
	draw_rect(tr, T.a(T.LINE, 0.38))
	var col := T.a(accent, 0.9 if _hover_bar else 0.68)
	draw_rect(th, col)
	if is_scrollable():
		# 上下端小刻度，提示还有内容
		var cap := T.a(accent, 0.35)
		draw_rect(Rect2(tr.position.x, tr.position.y - 2.0, bar_width, 1.0), cap)
		draw_rect(Rect2(tr.position.x, tr.end.y + 1.0, bar_width, 1.0), cap)


# ══ 输入（滚轮 / 滚动条拖动 / 轨道翻页）══════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if _on_input(event):
		accept_event()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if scroll_by(-scroll_step * maxf(1.0, mb.factor)):
						accept_event()
					return
				MOUSE_BUTTON_WHEEL_DOWN:
					if scroll_by(scroll_step * maxf(1.0, mb.factor)):
						accept_event()
					return
				MOUSE_BUTTON_LEFT:
					if is_scrollable() and thumb_rect().grow(3.0).has_point(mb.position):
						_drag_active = true
						_drag_grab = mb.position.y - thumb_rect().position.y
						accept_event()
						return
					if is_scrollable() and track_rect().has_point(mb.position):
						var page := view_height() * 0.9
						scroll_by(-page if mb.position.y < thumb_rect().position.y else page)
						accept_event()
						return
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT and _drag_active:
				_drag_active = false
				accept_event()
				return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hit_bar := is_scrollable() and thumb_rect().grow(3.0).has_point(mm.position)
		if hit_bar != _hover_bar:
			_hover_bar = hit_bar
			queue_redraw()
		if _drag_active:
			var tr := track_rect()
			var h := thumb_rect().size.y
			var travel := maxf(1.0, tr.size.y - h)
			var frac := clampf((mm.position.y - tr.position.y - _drag_grab) / travel, 0.0, 1.0)
			scroll_to(frac * max_offset())
			accept_event()
