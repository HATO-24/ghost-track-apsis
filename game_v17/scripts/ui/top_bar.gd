extends Control

# 阶段1A 顶栏：Control 绘制 + Theme 9-slice + token 文本 + 动态计时器 + 三色圆点。
# 只发信号/日志，不实现存档。

signal dot_action(kind: String)

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")

@export var commander_name := "指挥官 · 沧澜"
@export var mission_time_base := 0.0
@export var port_time := "L1 港内 06:42:17"

var _t := 0.0
var _mouse := Vector2(-100, -100)
var _hover_dot := -1
var _dots := [
	{"kind": "save", "col": Color("#6DE6A2"), "tip": "存档 / SAVE · 只发日志"},
	{"kind": "menu", "col": Color("#E8C24B"), "tip": "存档并回主菜单 / SAVE + MENU"},
	{"kind": "quit", "col": Color("#E2564A"), "tip": "存档并退出桌面 / SAVE + QUIT"},
]
var _timers := [
	{"label": "TRANSIT WINDOW", "remain": 25.0, "total": 30.0, "col": P.AMBER},
	{"label": "PORT SLOT", "remain": 71.0, "total": 120.0, "col": P.BLUE},
	{"label": "IFF ACK", "remain": 9.0, "total": 15.0, "col": P.PH},
]
var _tokens := {
	"COMMANDER": "指挥官 / COMMANDER",
	"MISSION": "任务 / MISSION",
	"PORT": "港内时间 / PORT",
	"LINK": "链路 / LINK",
	"SCALE": "时标 / TIMESCALE",
	"DV": "Δv 预算 / BUDGET",
	"ROE": "交战规则 / ROE",
	"SAVE": "存档 / SAVE",
	"MENU": "存档回主菜单 / SAVE + MENU",
	"QUIT": "存档退出桌面 / SAVE + QUIT",
}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 72)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func token(key: String) -> String:
	return String(_tokens.get(key, key))


func _process(delta: float) -> void:
	_t += delta
	for item in _timers:
		var d: Dictionary = item
		d["remain"] = maxf(0.0, float(d.get("remain", 0.0)) - delta)
	queue_redraw()


func _fmt_clock(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%02d:%02d" % [s / 60, s % 60]


func _draw() -> void:
	var th: Theme = theme
	if th != null:
		var sb: StyleBox = th.get_stylebox("panel", "Panel")
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), P.PANEL)
	draw_rect(Rect2(0, size.y - 1, size.x, 1), P.a(P.LINE, 0.85))
	var mono := F.mono()
	var cjk := F.cjk()
	# 左侧：指挥官 / 任务时间
	draw_string(cjk, Vector2(16, 20), token("COMMANDER"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.PH, 0.75))
	draw_string(cjk, Vector2(16, 38), commander_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.PH)
	draw_string(mono, Vector2(16, 55), "MISSION T+%s · %s" % [_fmt_clock(_t + mission_time_base), port_time], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.DIM, 0.95))
	# 中左：动态计时器（3 条，自动过期）
	var tx := 300.0
	draw_string(cjk, Vector2(tx, 20), "动态计时 / COUNTDOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.FAINT, 0.95))
	for i in range(_timers.size()):
		var item: Dictionary = _timers[i]
		var remain := float(item.get("remain", 0.0))
		var total := maxf(1.0, float(item.get("total", 1.0)))
		var col: Color = item.get("col", P.PH) as Color
		var y := 37.0 + float(i) * 12.0
		var expired := remain <= 0.0001
		var label := String(item.get("label", ""))
		draw_string(mono, Vector2(tx, y), "%s %s" % [label, "EXPIRED" if expired else _fmt_clock(remain)], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col if not expired else P.RED)
		draw_rect(Rect2(tx + 184, y - 7, 88, 3), P.a(P.LINE, 0.9))
		draw_rect(Rect2(tx + 184, y - 7, 88.0 * clampf(remain / total, 0.0, 1.0), 3), P.a(col, 0.9))
	# 右侧槽位
	var right := size.x - 150.0
	draw_string(cjk, Vector2(right, 20), token("LINK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.PH, 0.7))
	draw_string(mono, Vector2(right, 35), "無線電 8s · LINK OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
	draw_string(mono, Vector2(right, 49), "×1 · %s" % token("SCALE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))
	draw_string(mono, Vector2(right, 62), "Δv 8,420 m/s · ROE 僅自衛", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))
	# 三色圆点
	for i in range(_dots.size()):
		var d: Dictionary = _dots[i]
		var dp := Vector2(size.x - 20.0 - float(i) * 20.0, 15.0)
		var hot := _hover_dot == i
		var col: Color = d.get("col", P.PH) as Color
		draw_circle(dp, 7.0 if hot else 5.5, P.a(col, 0.22 if hot else 0.12))
		draw_circle(dp, 3.5, P.a(col, 0.95))
		draw_arc(dp, 8.0, 0, TAU, 20, P.a(col, 0.7 if hot else 0.35), 1.0, true)
		if hot:
			var tip := String(d.get("tip", ""))
			var tw := cjk.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 12.0
			var tr := Rect2(Vector2(size.x - tw - 10.0, 26.0), Vector2(tw, 17.0))
			draw_rect(tr, P.a(P.PANEL2, 0.98))
			draw_rect(tr, P.a(col, 0.65), false, 1.0)
			draw_string(cjk, Vector2(tr.position.x + 6.0, tr.position.y + 12.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
	draw_string(mono, Vector2(size.x - 86, 34), "SAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))


func _dot_rect(i: int) -> Rect2:
	return Rect2(Vector2(size.x - 20.0 - float(i) * 20.0 - 10.0, 5.0), Vector2(20, 20))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover_dot = -1
		for i in range(_dots.size()):
			if _dot_rect(i).has_point(_mouse):
				_hover_dot = i
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(_dots.size()):
			if _dot_rect(i).has_point(event.position):
				var kind := String((_dots[i] as Dictionary).get("kind", ""))
				print("[UI PROTO] dot_action=", kind, " (save not implemented; signal only)")
				dot_action.emit(kind)
				_hover_dot = -1
				queue_redraw()
				return
