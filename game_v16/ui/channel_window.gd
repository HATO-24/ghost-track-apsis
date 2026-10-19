extends Control

## V2-5 光学 / 红外 完整通道窗（独立窗口，而不是战术图上的一个环）。
##
## 数据：
## - core `perform_action("optical_channel"/"ir_channel")` 的动作结果（证据/actor/detail）；
## - sim `V2TacticalSnapshot` 的光学快照 `optical.channels[]`（status/idle|acquiring|staring|locked|lost、
##   stare_s/required_s/progress/samples/refresh_s/slant_range/classification/reason…）；
## - `data_source.tactical_start_channel/stop_channel` 控制 sim 凝视通道（只影响显示/观测建模）。
## 窗口自身不写 core，不伪造 locked。

signal start_requested(kind: String, target_id: String)
signal stop_requested(kind: String, target_id: String)
signal closed

const T := preload("res://ui/theme.gd")

const PANEL := Rect2(560.0, 170.0, 800.0, 620.0)

var kind := "optical"
var target: Dictionary = {}
var action_detail: Dictionary = {}
var channel: Dictionary = {}
var snapshot_available := false
var _buttons: Array = []
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func set_payload(kind_ref: String, target_ref: Dictionary, action_ref: Dictionary, snapshot_ok: bool) -> void:
	kind = kind_ref
	target = target_ref.duplicate(true)
	action_detail = action_ref.duplicate(true)
	snapshot_available = snapshot_ok
	queue_redraw()


func set_channel(view: Dictionary) -> void:
	channel = view.duplicate(true)
	queue_redraw()


func _channel_name() -> String:
	return "可见光 / VIS" if kind == "optical" else "红外 / IR"


func _status_color(st: String) -> Color:
	match st:
		"locked":
			return T.PH
		"staring":
			return T.AMBER
		"acquiring":
			return T.BLUE
		"lost":
			return T.RED
		"idle":
			return T.FAINT
		_:
			return T.DIM


func _status_label(st: String) -> String:
	match st:
		"locked":
			return "锁定 / LOCKED"
		"staring":
			return "凝视中 / STARING"
		"acquiring":
			return "截获中 / ACQUIRING"
		"lost":
			return "失锁 / LOST"
		"idle":
			return "待机 / IDLE"
		_:
			return st.to_upper()


func _progress() -> float:
	if not snapshot_available:
		return 0.0
	var req := float(channel.get("required_s", 0.0))
	var stare := float(channel.get("stare_s", 0.0))
	if req > 0.0:
		return clampf(stare / req, 0.0, 1.0)
	return clampf(float(channel.get("progress", 0.0)), 0.0, 1.0)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color(0.0, 0.0, 0.0, 0.52))
	var p := PANEL
	T.panel(self, p, 0.985, 0.9)
	T.corners(self, p.grow(-1.0), 14.0, T.PH, 0.8)
	var head := "光学凝视通道 / OPTICAL STARE" if kind == "optical" else "红外凝视通道 / IR STARE"
	T.text(self, p.position.x + 24.0, p.position.y + 16.0, head, T.F18, T.TXT)
	T.text(self, p.position.x + 24.0, p.position.y + 42.0,
		"%s · %s · sim 通道数据 + core 动作证据" % [_channel_name(),
			"MS-OT2 / EO" if kind == "optical" else "CH-IR2 / IR"], T.F8, T.a(T.DIM, 0.9))
	# 关闭按钮
	var close_r := Rect2(p.end.x - 86.0, p.position.y + 14.0, 66.0, 24.0)
	_buttons = [{"rect": close_r, "action": "close"}]
	draw_rect(close_r, T.a(T.PANEL2, 0.8))
	draw_rect(close_r, T.a(T.AMBER, 0.6), false, 1.0)
	T.text_c(self, close_r.get_center().x, close_r.position.y + 5.0, "关闭 ESC", T.F8, T.a(T.AMBER, 0.95))
	T.hline(self, p.position.x + 16.0, p.position.y + 60.0, p.end.x - 16.0, T.a(T.LINE, 0.65))
	# 目标信息
	var y := p.position.y + 74.0
	T.text(self, p.position.x + 24.0, y, "目标 / TARGET", T.F9, T.a(T.PH_DIM, 0.95))
	y += 24.0
	var rows := [
		["批号 / BATCH", String(target.get("batch", "—"))],
		["名称 / NAME", "%s / %s" % [String(target.get("name", "—")), String(target.get("name_en", ""))]],
		["身份 / IDENTITY", String(target.get("identity_label", target.get("identity", "—")))],
		["等级 / LEVEL", "L%d · %s" % [int(target.get("level", 0)), String(target.get("level_label", ""))]],
		["类型 / KIND", "%s · %s" % [String(target.get("kind_label", target.get("display_kind", target.get("kind", "")))),
			String(target.get("cls", ""))]],
		["距离 / RANGE", "%.0f km · %s" % [float(channel.get("slant_range_km", target.get("range_km", -1.0))),
			String(channel.get("range_band", ""))]],
		["方位 / BEARING", "%.1f°" % float(target.get("bearing_deg", -1.0))],
	]
	for raw in rows:
		var rec: Array = raw
		T.text(self, p.position.x + 24.0, y, String(rec[0]), T.F8, T.FAINT, false)
		T.text_fit(self, p.position.x + 180.0, y, String(rec[1]), T.F8, T.a(T.TXT, 0.95), 560.0)
		y += 20.0
	# 通道状态
	y += 8.0
	T.hline(self, p.position.x + 16.0, y - 12.0, p.end.x - 16.0, T.a(T.LINE, 0.45))
	T.text(self, p.position.x + 24.0, y, "通道 / CHANNEL", T.F9, T.a(T.PH_DIM, 0.95))
	y += 24.0
	var st := String(channel.get("status", "idle")) if snapshot_available else "unavailable"
	var col := _status_color(st)
	T.text(self, p.position.x + 24.0, y, "状态 / STATUS", T.F8, T.FAINT, false)
	T.text(self, p.position.x + 180.0, y, _status_label(st) if snapshot_available else "SIM 未就绪 / UNAVAILABLE",
		T.F10, T.a(col, 0.95))
	y += 24.0
	var prog := _progress()
	T.text(self, p.position.x + 24.0, y, "STARE 进度", T.F8, T.FAINT, false)
	T.bar(self, Rect2(p.position.x + 180.0, y + 2.0, 380.0, 6.0), prog, col)
	T.text(self, p.position.x + 572.0, y, "%.0f%%  %.1f / %.1f s" % [prog * 100.0,
		float(channel.get("stare_s", 0.0)), float(channel.get("required_s", 0.0))], T.F8,
		T.a(col, 0.95), false)
	y += 24.0
	var info := [
		["刷新 / REFRESH", "%.1f s" % float(channel.get("refresh_s", 0.0))],
		["采样 / SAMPLES", str(int(channel.get("samples", 0)))],
		["级支持 / SUPPORT", "+%d（光学分类证据需 support=3）" % int(channel.get("level_support", 0))],
	]
	if bool(channel.get("locked", false)):
		info.append(["锁定时刻 / LOCKED AT", "T+%s" % T.hms(float(channel.get("locked_t", 0.0)))])
	if String(channel.get("reason", "")) != "":
		info.append(["原因 / REASON", String(channel.get("reason", ""))])
	for raw2 in info:
		var rec2: Array = raw2
		T.text(self, p.position.x + 24.0, y, String(rec2[0]), T.F8, T.FAINT, false)
		T.text_fit(self, p.position.x + 180.0, y, String(rec2[1]), T.F8, T.a(T.TXT, 0.9), 560.0)
		y += 20.0
	# 分类结果（sim 光学 dict 可能携带 classification）
	var cls: Dictionary = channel.get("classification", {}) if channel.get("classification", {}) is Dictionary else {}
	if not cls.is_empty():
		T.text(self, p.position.x + 24.0, y, "分类 / CLASS", T.F8, T.FAINT, false)
		T.text_fit(self, p.position.x + 180.0, y, JSON.stringify(cls), T.F8, T.a(T.PH, 0.9), 560.0)
		y += 20.0
	# core 动作证据
	y = maxi(y + 6, p.position.y + 470)
	T.hline(self, p.position.x + 16.0, y - 14.0, p.end.x - 16.0, T.a(T.LINE, 0.45))
	T.text(self, p.position.x + 24.0, y, "CORE 动作 / ACTION RESULT", T.F9, T.a(T.PH_DIM, 0.95))
	y += 24.0
	var detail := [
		["动作 / ACTION", String(action_detail.get("id", kind + "_channel"))],
		["结果 / RESULT", "ok · 执行平台 %s · L%d" % [String(action_detail.get("actor_name", "—")),
			int(action_detail.get("level", target.get("level", 0)))]],
		["说明 / DETAIL", String(action_detail.get("detail", ""))],
		["证据 / EVIDENCE", "core perform_action 生成观测；窗口的 STARE/锁定来自 sim 光学通道"],
	]
	for raw3 in detail:
		var rec3: Array = raw3
		T.text(self, p.position.x + 24.0, y, String(rec3[0]), T.F8, T.FAINT, false)
		T.text_fit(self, p.position.x + 180.0, y, String(rec3[1]), T.F8, T.a(T.TXT, 0.9), 560.0)
		y += 20.0
	# 按钮
	var by := p.end.y - 62.0
	var bx := p.position.x + 24.0
	_buttons.append({"rect": Rect2(bx, by, 190.0, 32.0), "action": "start",
		"enabled": snapshot_available and st != "locked" and st != "staring"})
	_buttons.append({"rect": Rect2(bx + 206.0, by, 190.0, 32.0), "action": "stop",
		"enabled": snapshot_available and st != "idle" and st != "unavailable"})
	_buttons.append({"rect": Rect2(bx + 412.0, by, 150.0, 32.0), "action": "close", "enabled": true})
	for i in range(_buttons.size()):
		var b: Dictionary = _buttons[i]
		if String(b.get("action", "")) == "close" and not (b["rect"] as Rect2).has_point(get_local_mouse_position()):
			# close 按钮已在右上绘制；这里再画底部同一 close
			pass
		var enabled := bool(b.get("enabled", true))
		var r: Rect2 = b["rect"]
		var hot := i == _hover
		var base := T.PH if String(b.get("action", "")) == "start" else (T.AMBER if String(b.get("action", "")) == "stop" else T.DIM)
		draw_rect(r, T.a(base, 0.14 if enabled and hot else (0.06 if enabled else 0.02)))
		draw_rect(r, T.a(base, 0.85 if enabled and hot else (0.45 if enabled else 0.20)), false, 1.0)
		var label: String = str({"start": "开始 STARE / START", "stop": "停止 / STOP", "close": "关闭 / CLOSE"}.get(
			String(b.get("action", "")), ""))
		T.text_c(self, r.get_center().x, r.position.y + 8.0, String(label), T.F8,
			T.a(base, 0.95 if enabled else 0.4))
	if not snapshot_available:
		T.text_fit(self, p.position.x + 24.0, p.end.y - 24.0,
			"sim 光学快照未就绪：状态/进度不可用，窗口只显示 core 动作与接触信息（不伪造锁定）。",
			T.F7, T.a(T.AMBER, 0.9), p.size.x - 48.0)


func _button_at(pos: Vector2) -> int:
	for i in range(_buttons.size()):
		if (_buttons[i]["rect"] as Rect2).has_point(pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var idx := _button_at((event as InputEventMouseMotion).position)
		if idx != _hover:
			_hover = idx
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		var idx := _button_at(mb.position)
		if idx < 0:
			return
		var b: Dictionary = _buttons[idx]
		if not bool(b.get("enabled", true)):
			accept_event()
			return
		match String(b.get("action", "")):
			"start":
				start_requested.emit(kind, String(target.get("id", "")))
			"stop":
				stop_requested.emit(kind, String(target.get("id", "")))
			"close":
				closed.emit()
		accept_event()
