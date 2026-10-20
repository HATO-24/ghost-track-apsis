extends Control

# 阶段1D 底部命令队列 + 事件日志（V1 密度）。
# commands：demo（无 GameSession 时明确 DEMO）；events：EventBus 真实事件（可空）。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")

var commands: Array = []
var events: Array = []
var command_source := "DEMO"
var event_source := "EVENTBUS"


func _ready() -> void:
	custom_minimum_size = Vector2(0, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_commands: Array, p_events: Array, p_cmd_source := "DEMO", p_ev_source := "EVENTBUS") -> void:
	commands = p_commands.duplicate(true)
	events = p_events.duplicate(true)
	command_source = p_cmd_source
	event_source = p_ev_source
	queue_redraw()


func set_events(p_events: Array) -> void:
	events = p_events.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), r)
	else:
		draw_rect(r, P.PANEL)
	var cjk := F.cjk()
	var mono := F.mono()
	var split := floorf(size.x * 0.56)
	draw_line(Vector2(split, 10), Vector2(split, size.y - 10), P.a(P.LINE, 0.75), 1.0)
	draw_string(cjk, Vector2(12, 17), "命令队列 / COMMAND QUEUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	draw_string(mono, Vector2(12, 29), command_source + " · STATUS/SENDER/RECEIVER/MODE/DELAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.AMBER, 0.85))
	var y := 42.0
	if commands.is_empty():
		draw_string(cjk, Vector2(12, y), "NO COMMAND DATA · NOT READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.FAINT)
	else:
		for i in range(mini(3, commands.size())):
			var c: Dictionary = commands[i]
			var col := P.PH if String(c.get("state", "")) == "EXECUTING" else (P.AMBER if String(c.get("state", "")) in ["QUEUED", "TRANSMITTED"] else P.DIM)
			draw_string(mono, Vector2(12, y), "%s %-10s" % [String(c.get("id", "—")), String(c.get("state", "—"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
			draw_string(cjk, Vector2(150, y), "%s → %s" % [String(c.get("actor", "—")), String(c.get("target", "—"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
			draw_string(mono, Vector2(split - 180, y), "%s · %s · %s" % [String(c.get("action", "—")), String(c.get("mode", "—")), String(c.get("delay", "—"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.DIM, 0.9))
			y += 16.0
	# 右侧事件日志
	var ex := split + 12.0
	draw_string(cjk, Vector2(ex, 17), "事件日志 / EVENT LOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.PH)
	draw_string(mono, Vector2(ex, 29), event_source + " · " + str(events.size()) + " events", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.AMBER, 0.85))
	var ey := 42.0
	if events.is_empty():
		draw_string(cjk, Vector2(ex, ey), "NO EVENT DATA · NOT READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.FAINT)
	else:
		for i in range(mini(4, events.size())):
			var e: Dictionary = events[i]
			var et := String(e.get("type", "—"))
			var t := float(e.get("t", -1.0))
			var ts := "%6.1fs" % t if t >= 0.0 else "  —  "
			var payload: Dictionary = e.get("payload", {}) if e.get("payload", {}) is Dictionary else {}
			var txt := String(payload.get("label", ""))
			if txt == "":
				txt = String(e.get("text_key", ""))
			if txt == "":
				txt = String(e.get("target", ""))
			draw_string(mono, Vector2(ex, ey), ts + " " + et, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.PH_DIM if i == 0 else P.DIM)
			draw_string(cjk, Vector2(ex + 168, ey), _fit(txt, 28), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.TXT)
			ey += 15.0
	draw_string(mono, Vector2(12, size.y - 10), "READ-ONLY UI · 三色点 save.request 仅事件 · 无存档", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))


func _fit(s: String, n: int) -> String:
	return s if s.length() <= n else s.substr(0, n - 1) + "…"
