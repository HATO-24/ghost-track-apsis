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
var time_service = null
var event_bus = null
var _time_token := -1
var _timer_event_token := -1
var _dots := [
	{"kind": "save", "col": Color("#6DE6A2"), "tip": "存档 / SAVE · 只发日志"},
	{"kind": "menu", "col": Color("#E8C24B"), "tip": "存档并回主菜单 / SAVE + MENU"},
	{"kind": "quit", "col": Color("#E2564A"), "tip": "存档并退出桌面 / SAVE + QUIT"},
]
var _timers: Array = []  # 由 EventBus tactical.timer 生成：{label, deadline_s, duration_s, col, kind}
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
	var now := _now_s()
	var kept: Array = []
	for raw in _timers:
		var item: Dictionary = raw
		if float(item.get("deadline_s", 0.0)) > now + 1.0e-9:
			kept.append(item)
	# 过期自动移除：不靠 UI 本地倒计时；时间来自 TimeService
	_timers = kept
	queue_redraw()


func bind_services(ts, bus) -> void:
	time_service = ts
	event_bus = bus
	if event_bus != null and event_bus.has_method("subscribe"):
		var sub: Dictionary = event_bus.call("subscribe", "tactical", Callable(self, "_on_bus_event"))
		_timer_event_token = int(sub.get("token", -1))
	queue_redraw()


func _now_s() -> float:
	if time_service != null and time_service.has_method("now_s"):
		return float(time_service.call("now_s"))
	return _t


func _on_bus_event(event: Dictionary) -> void:
	var et := String(event.get("type", ""))
	if et == "tactical.timer":
		var payload: Dictionary = event.get("payload", {}) if event.get("payload", {}) is Dictionary else {}
		var duration := maxf(0.1, float(payload.get("duration_s", 10.0)))
		var now := _now_s()
		_timers.append({
			"label": String(payload.get("label", "TIMER")),
			"deadline_s": now + duration,
			"duration_s": duration,
			"kind": String(payload.get("kind", "timer")),
			"col": P.AMBER if String(payload.get("kind", "")) == "burn" else (P.BLUE if String(payload.get("kind", "")) == "link" else P.PH),
		})
		while _timers.size() > 4:
			_timers.pop_front()
		queue_redraw()


func _fmt_clock(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%02d:%02d" % [s / 60, s % 60]


func _port_clock() -> String:
	if time_service != null and time_service.has_method("epoch_abs_s"):
		var abs_s := float(time_service.call("epoch_abs_s"))
		var h := int(abs_s / 3600.0) % 24
		var m := int(abs_s / 60.0) % 60
		var sec := int(abs_s) % 60
		return "%02d:%02d:%02d" % [h, m, sec]
	var parts := port_time.split(" ")
	return String(parts[parts.size() - 1]) if parts.size() > 0 else port_time


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
	var now_s := _now_s()
	var scale_txt := "×%.0f" % float(time_service.scale) if time_service != null else "×1"
	var paused_txt := "PAUSED" if time_service != null and bool(time_service.paused) else "RUNNING"
	draw_string(mono, Vector2(16, 55), "MISSION T+%s · L1 港内 %s · %s %s" % [_fmt_clock(now_s + mission_time_base), _port_clock(), scale_txt, paused_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.95))
	# 中左：动态计时器（3 条，自动过期）
	var tx := 300.0
	draw_string(cjk, Vector2(tx, 20), "动态计时 / EVENTBUS TIMERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.FAINT, 0.95))
	var now := _now_s()
	for i in range(_timers.size()):
		var item: Dictionary = _timers[i]
		var remain := maxf(0.0, float(item.get("deadline_s", 0.0)) - now)
		var total := maxf(1.0, float(item.get("duration_s", 1.0)))
		var col: Color = item.get("col", P.PH) as Color
		var y := 37.0 + float(i) * 12.0
		var label := String(item.get("label", ""))
		draw_string(mono, Vector2(tx, y), "%s %s" % [label, _fmt_clock(remain)], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
		draw_rect(Rect2(tx + 184, y - 7, 88, 3), P.a(P.LINE, 0.9))
		draw_rect(Rect2(tx + 184, y - 7, 88.0 * clampf(remain / total, 0.0, 1.0), 3), P.a(col, 0.9))
	# 右侧槽位
	var right := size.x - 150.0
	draw_string(cjk, Vector2(right, 20), token("LINK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.a(P.PH, 0.7))
	draw_string(mono, Vector2(right, 35), "無線電 8s · LINK OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT)
	draw_string(mono, Vector2(right, 49), "%s · %s" % [scale_txt, token("SCALE")], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))
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
				if event_bus != null and event_bus.has_method("publish"):
					event_bus.call("publish", {
						"type": "save.request", "t": _now_s(), "source": "ui_proto.top_bar",
						"target": kind, "payload": {"kind": kind, "save_implemented": false},
					})
				print("[UI PROTO] save.request kind=", kind, " (not implemented; event only)")
				dot_action.emit(kind)
				_hover_dot = -1
				queue_redraw()
				return
