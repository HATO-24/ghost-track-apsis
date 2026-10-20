extends Control

# 阶段1A 自定义指针：V1 准心；default/point/disabled/drag 四态。
# 只做视觉；不改变系统输入语义。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var state := "default"
var _pos := Vector2(960, 540)
var _visible := true
var _disabled := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_process(true)
	_pos = get_viewport_rect().get_center() if get_viewport_rect().size.x > 0.0 else Vector2(960, 540)


func set_state(s: String) -> void:
	state = s
	queue_redraw()


func _process(_delta: float) -> void:
	var vp := get_viewport_rect()
	if vp.size.x > 0.0:
		_pos = get_global_mouse_position()
	if _disabled:
		state = "disabled"
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		state = "drag"
	elif get_viewport().gui_get_hovered_control() != null:
		state = "point"
	else:
		state = "default"
	queue_redraw()


func set_disabled(on: bool) -> void:
	_disabled = on
	state = "disabled" if on else "default"


func _draw() -> void:
	if not _visible:
		return
	var p := _pos
	var col := P.PH
	match state:
		"point":
			col = P.BLUE
		"disabled":
			col = P.FAINT
		"drag":
			col = P.AMBER
		_:
			col = P.PH
	var seg := 7.0
	if state == "drag":
		seg = 9.0
	draw_line(p - Vector2(18, 0), p - Vector2(seg, 0), P.a(col, 0.9), 1.0)
	draw_line(p + Vector2(seg, 0), p + Vector2(18, 0), P.a(col, 0.9), 1.0)
	draw_line(p - Vector2(0, 18), p - Vector2(0, seg), P.a(col, 0.9), 1.0)
	draw_line(p + Vector2(0, seg), p + Vector2(0, 18), P.a(col, 0.9), 1.0)
	draw_arc(p, 4.0, 0, TAU, 16, P.a(col, 0.85), 1.0, true)
	draw_circle(p, 1.4, col)
	if state == "disabled":
		draw_line(p - Vector2(7, 7), p + Vector2(7, 7), P.a(P.RED, 0.9), 1.0)
	elif state == "point":
		draw_arc(p, 11.0, -PI * 0.5, PI * 0.5, 16, P.a(col, 0.7), 1.0, true)
	elif state == "drag":
		draw_rect(Rect2(p + Vector2(10, 10), Vector2(8, 8)), P.a(col, 0.6), false, 1.0)
