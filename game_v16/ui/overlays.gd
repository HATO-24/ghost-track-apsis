extends Control

## V2-3 第一关覆盖层：PRELUDE / DECISION / REPORT / END。
##
## 只负责「画 + 收输入 + 发信号」；文本/选项/可用性来自 `ui/data_source.gd`
## （core V2-CORE-2 的 vm_prelude/vm_decision/vm_report/vm_end + story_l1.json）。
## 不在 UI 写死结局/文本；按钮回调由 game_screen 直接调 core 方法。

signal prelude_choose(kind: String, id: String)   # kind = route | window
signal prelude_execute()
signal decision_chosen(kind: String)
signal report_submitted(mode: String)             # truth | fake
signal end_restart()
signal end_quit()

const T := preload("res://ui/theme.gd")
const L := preload("res://ui/layout.gd")

const MODE_NONE := "none"
const MODE_PRELUDE := "prelude"
const MODE_DECISION := "decision"
const MODE_REPORT := "report"
const MODE_END := "end"

var mode := MODE_NONE
var payload: Dictionary = {}

var _panel := Rect2()
var _buttons: Array = []       # [{rect, action, data, enabled, reason, label}]
var _rows: Array = []          # 展示行 [{kind, id, data, enabled, reason, rect}]
var _fire_confirm := false
var _hover_btn := -1
var _hover_row := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func is_open() -> bool:
	return mode != MODE_NONE


func close() -> void:
	mode = MODE_NONE
	payload = {}
	visible = false
	_buttons.clear()
	_rows.clear()
	queue_redraw()


func update_payload(p: Dictionary) -> void:
	payload = p.duplicate(true)
	_layout()
	queue_redraw()


func open_prelude(p: Dictionary) -> void:
	mode = MODE_PRELUDE
	payload = p.duplicate(true)
	visible = true
	_layout()
	queue_redraw()


func open_decision(p: Dictionary) -> void:
	mode = MODE_DECISION
	payload = p.duplicate(true)
	_fire_confirm = false
	visible = true
	_layout()
	queue_redraw()


func open_report(p: Dictionary) -> void:
	mode = MODE_REPORT
	payload = p.duplicate(true)
	visible = true
	_layout()
	queue_redraw()


func open_end(p: Dictionary) -> void:
	mode = MODE_END
	payload = p.duplicate(true)
	visible = true
	_layout()
	queue_redraw()


# ══ 布局 ═════════════════════════════════════════════════════════════════

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and mode != MODE_NONE:
		_layout()
		queue_redraw()


func _layout() -> void:
	_buttons.clear()
	_rows.clear()
	match mode:
		MODE_PRELUDE:
			_layout_prelude()
		MODE_DECISION:
			_layout_decision()
		MODE_REPORT:
			_layout_report()
		MODE_END:
			_layout_end()
		_:
			pass


func _layout_prelude() -> void:
	_panel = Rect2(360.0, 140.0, 1200.0, 800.0)
	var routes: Array = payload.get("routes", []) if payload.get("routes", []) is Array else []
	var windows: Array = payload.get("windows", []) if payload.get("windows", []) is Array else []
	var sel_route := String(payload.get("route", ""))
	var sel_window := String(payload.get("window", ""))
	var y := _panel.position.y + 176.0
	for i in range(routes.size()):
		var r: Dictionary = routes[i]
		_rows.append({"kind": "route", "id": String(r.get("id", "")), "data": r,
			"enabled": true, "reason": "", "selected": String(r.get("id", "")) == sel_route,
			"rect": Rect2(_panel.position.x + 40.0, y + float(i) * 94.0, 520.0, 84.0)})
	for i in range(windows.size()):
		var w: Dictionary = windows[i]
		_rows.append({"kind": "window", "id": String(w.get("id", "")), "data": w,
			"enabled": true, "reason": "", "selected": String(w.get("id", "")) == sel_window,
			"rect": Rect2(_panel.position.x + 620.0, y + float(i) * 94.0, 520.0, 84.0)})
	var can_exec := bool(payload.get("can_execute", false))
	_buttons.append({
		"rect": Rect2(_panel.end.x - 320.0, _panel.end.y - 84.0, 280.0, 46.0),
		"action": "execute", "data": {}, "enabled": can_exec,
		"reason": "" if can_exec else "先选择目的地与变轨窗口",
		"label": "确认并执行点火 / EXECUTE",
	})


func _layout_decision() -> void:
	_panel = Rect2(330.0, 110.0, 1260.0, 860.0)
	var options: Array = payload.get("options", []) if payload.get("options", []) is Array else []
	var y := _panel.position.y + 310.0
	for i in range(options.size()):
		var o: Dictionary = options[i]
		_rows.append({"kind": "ending", "id": String(o.get("kind", "")), "data": o,
			"enabled": bool(o.get("enabled", true)), "reason": String(o.get("reason", "")),
			"selected": false,
			"rect": Rect2(_panel.position.x + 40.0, y + float(i) * 84.0, _panel.size.x - 80.0, 74.0)})


func _layout_report() -> void:
	_panel = Rect2(400.0, 100.0, 1120.0, 880.0)
	var fake_ok := bool(payload.get("fake_available", false))
	_buttons.append({
		"rect": Rect2(_panel.position.x + 40.0, _panel.end.y - 86.0, 340.0, 46.0),
		"action": "report_truth", "data": {}, "enabled": true, "reason": "",
		"label": "如实提交 / SUBMIT TRUTH",
	})
	_buttons.append({
		"rect": Rect2(_panel.end.x - 380.0, _panel.end.y - 86.0, 340.0, 46.0),
		"action": "report_fake", "data": {}, "enabled": fake_ok,
		"reason": "" if fake_ok else String(payload.get("fake_reason", "内容未提供伪造文本")),
		"label": "伪造记录 / FALSIFY",
	})


func _layout_end() -> void:
	_panel = Rect2(460.0, 160.0, 1000.0, 760.0)
	_buttons.append({
		"rect": Rect2(_panel.position.x + 40.0, _panel.end.y - 86.0, 300.0, 46.0),
		"action": "restart", "data": {}, "enabled": true, "reason": "",
		"label": "重新开始 / RESTART",
	})
	_buttons.append({
		"rect": Rect2(_panel.end.x - 340.0, _panel.end.y - 86.0, 300.0, 46.0),
		"action": "quit", "data": {}, "enabled": true, "reason": "",
		"label": "退出 / QUIT",
	})


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	if mode == MODE_NONE:
		return
	draw_rect(Rect2(Vector2.ZERO, L.DESIGN), Color(0.01, 0.03, 0.024, 0.78))
	draw_rect(_panel, T.a(T.PANEL, 0.985))
	draw_rect(_panel, T.a(_accent(), 0.72), false, 1.0)
	T.corners(self, _panel.grow(-1.0), 16.0, _accent(), 0.85)
	T.text(self, _panel.position.x + 28.0, _panel.position.y + 20.0,
		String(payload.get("kicker", "")), T.F8, T.a(_accent(), 0.85))
	T.text(self, _panel.position.x + 28.0, _panel.position.y + 36.0,
		String(payload.get("title", "")), T.F22, T.a(T.TXT, 0.97))
	if payload.has("phase_title"):
		T.text(self, _panel.position.x + 28.0, _panel.position.y + 66.0,
			String(payload.get("phase_title", "")), T.F9, T.a(T.DIM, 0.95))
	if payload.has("countdown"):
		T.text_r(self, _panel.end.x - 28.0, _panel.position.y + 20.0, "决策倒计时 / COUNTDOWN", T.F7, T.FAINT)
		T.text_r(self, _panel.end.x - 28.0, _panel.position.y + 34.0, String(payload.get("countdown", "—")),
			T.F22, T.a(T.AMBER, 0.95), false)
	if payload.has("hint") and String(payload.get("hint", "")) != "":
		T.text_fit(self, _panel.position.x + 28.0, _panel.position.y + 92.0,
			String(payload.get("hint", "")), T.F8, T.a(T.AMBER, 0.9), _panel.size.x - 56.0)
	T.hline(self, _panel.position.x + 24.0, _panel.position.y + 90.0, _panel.end.x - 24.0, T.a(T.LINE, 0.9))
	match mode:
		MODE_PRELUDE:
			_draw_prelude()
		MODE_DECISION:
			_draw_decision()
		MODE_REPORT:
			_draw_report()
		MODE_END:
			_draw_end()
	_draw_buttons()
	_draw_hint()


func _accent() -> Color:
	match mode:
		MODE_DECISION:
			return T.AMBER
		MODE_END:
			return T.PH_DIM
		MODE_REPORT:
			return T.BLUE
		_:
			return T.PH


func _draw_prelude() -> void:
	_draw_wrapped(String(payload.get("body", "")), _panel.position.x + 40.0, _panel.position.y + 104.0,
		_panel.size.x - 80.0, T.F10, T.a(T.TXT, 0.9), 18.0)
	T.text(self, _panel.position.x + 40.0, _panel.position.y + 152.0, "目的地 / DESTINATION", T.F8, T.a(T.PH, 0.9))
	T.text(self, _panel.position.x + 620.0, _panel.position.y + 152.0, "变轨窗口 / WINDOW", T.F8, T.a(T.PH, 0.9))
	for raw in _rows:
		var row: Dictionary = raw
		var r: Rect2 = row["rect"]
		var data: Dictionary = row["data"]
		var selected := bool(row.get("selected", false))
		var hovered: bool = _hover_row >= 0 and _rows[_hover_row] == row
		draw_rect(r, T.a(T.PANEL2, 0.95 if selected else (0.5 if hovered else 0.3)))
		draw_rect(r, T.a(T.PH if selected else T.LINE, 0.75 if selected else 0.5), false, 1.0)
		var ok := bool(data.get("ok", false))
		var accent: Color = T.PH if ok else T.AMBER
		T.badge(self, Rect2(r.position.x + 12.0, r.position.y + 12.0, 22.0, 14.0),
			"OK" if ok else "NO", accent, T.F7)
		T.text_fit(self, r.position.x + 44.0, r.position.y + 8.0, String(data.get("label", row["id"])),
			T.F11, T.a(accent, 0.97), r.size.x - 140.0)
		T.text_fit(self, r.position.x + 44.0, r.position.y + 30.0, String(data.get("hint", "")),
			T.F8, T.a(T.DIM, 0.95), r.size.x - 140.0)
		T.text_r(self, r.end.x - 12.0, r.position.y + 8.0, "Δv %d m/s" % int(data.get("dv_ms", 0.0)),
			T.F8, T.a(accent, 0.9), false)
		if selected:
			draw_rect(Rect2(r.position.x, r.position.y, 3.0, r.size.y), T.PH)
	var confirm_text := String(payload.get("confirm_text", ""))
	T.text_fit(self, _panel.position.x + 40.0, _panel.end.y - 124.0, confirm_text, T.F9,
		T.a(T.DIM, 0.95), _panel.size.x - 460.0)
	T.text_fit(self, _panel.position.x + 40.0, _panel.end.y - 104.0,
		String(payload.get("execute_text", "")), T.F8, T.a(T.FAINT, 0.9), _panel.size.x - 460.0)
	if not bool(payload.get("can_execute", false)):
		T.text_r(self, _panel.end.x - 40.0, _panel.end.y - 104.0,
			"先选择目的地与变轨窗口", T.F8, T.a(T.AMBER, 0.85))


func _draw_decision() -> void:
	var prompt_text := String(payload.get("prompt_text", ""))
	_draw_wrapped(prompt_text, _panel.position.x + 40.0, _panel.position.y + 104.0,
		_panel.size.x - 80.0, T.F10, T.a(T.TXT, 0.92), 19.0)
	var ev_summary := String(payload.get("evidence_summary", ""))
	if ev_summary != "":
		T.text(self, _panel.position.x + 40.0, _panel.position.y + 206.0, ev_summary, T.F8, T.a(T.PH_DIM, 0.95))
	T.text(self, _panel.position.x + 40.0, _panel.position.y + 230.0,
		"指挥官裁决 / COMMANDER DETERMINATION · 内容来自 story.endings + FIRE 灾难分支", T.F8, T.a(T.AMBER, 0.9))
	for raw in _rows:
		var row: Dictionary = raw
		var r: Rect2 = row["rect"]
		var data: Dictionary = row["data"]
		var kind := String(data.get("kind", ""))
		var enabled := bool(row.get("enabled", true))
		var hovered: bool = _hover_row >= 0 and _rows[_hover_row] == row
		var accent: Color = T.PH
		if kind == "EXPOSE":
			accent = T.BLUE
		elif kind == "EVACUATE":
			accent = T.AMBER
		elif kind == "FIRE":
			accent = T.RED
		draw_rect(r, T.a(T.PANEL2, 0.95 if hovered else 0.45))
		draw_rect(r, T.a(accent if enabled else T.LINE, 0.8 if enabled else 0.4), false, 1.0)
		var col: Color = T.a(accent, 0.97) if enabled else T.a(T.FAINT, 0.85)
		T.text(self, r.position.x + 14.0, r.position.y + 8.0,
			"%s  %s" % [String(data.get("code", "")), String(data.get("label", kind))], T.F12, col)
		T.text_fit(self, r.position.x + 14.0, r.position.y + 32.0,
			String(data.get("hint", "")), T.F8, T.a(T.DIM if enabled else T.FAINT, 0.95), r.size.x - 260.0)
		if not enabled:
			T.text_r(self, r.end.x - 14.0, r.position.y + 10.0,
				"不可用：" + String(row.get("reason", "")), T.F8, T.a(T.AMBER, 0.9))
		if kind == "FIRE":
			T.text_r(self, r.end.x - 14.0, r.position.y + 10.0,
				"再次点击确认 / CONFIRM" if _fire_confirm else "灾难分支 · 需二次确认", T.F8, T.a(T.RED, 0.9))


func _draw_report() -> void:
	var meta_rows: Array = [
		["单位 / UNIT", String(payload.get("unit", ""))],
		["事件 / EVENT", String(payload.get("event", ""))],
		["证据 / EVIDENCE", String(payload.get("evidence", ""))],
		["裁决 / OUTCOME", String(payload.get("ending_label", ""))],
	]
	var y := _panel.position.y + 104.0
	for i in range(meta_rows.size()):
		var row: Array = meta_rows[i]
		var ry := y + float(i) * 24.0
		T.text(self, _panel.position.x + 40.0, ry, String(row[0]), T.F8, T.FAINT)
		T.text_fit(self, _panel.position.x + 210.0, ry - 1.0, String(row[1]), T.F9, T.a(T.TXT, 0.95), 560.0)
	T.hline(self, _panel.position.x + 24.0, y + 106.0, _panel.end.x - 24.0, T.a(T.LINE, 0.8))
	var cy := y + 116.0
	var consequence := String(payload.get("consequence", ""))
	if consequence != "":
		cy = _draw_wrapped("后果 / CONSEQUENCE：" + consequence, _panel.position.x + 40.0, cy,
			_panel.size.x - 80.0, T.F9, T.a(T.AMBER, 0.92), 18.0) + 8.0
	_draw_wrapped(String(payload.get("body", "")), _panel.position.x + 40.0, cy,
		_panel.size.x - 80.0, T.F11, T.a(T.TXT, 0.94), 21.0)
	var recommend := String(payload.get("recommend", ""))
	if recommend != "":
		T.text_fit(self, _panel.position.x + 40.0, _panel.end.y - 146.0,
			"建议 / RECOMMEND：" + recommend, T.F9, T.a(T.PH_DIM, 0.95), _panel.size.x - 80.0)
	T.text_fit(self, _panel.position.x + 40.0, _panel.end.y - 122.0,
		"提交后进入 END；伪造将留下 AUDIT FLAG（core submit_report 写 flow.report.audit_flag）。",
		T.F8, T.a(T.FAINT, 0.9), _panel.size.x - 80.0)


func _draw_end() -> void:
	T.text(self, _panel.position.x + 40.0, _panel.position.y + 120.0,
		String(payload.get("outcome_label", "")), T.F26, T.a(T.PH, 0.95))
	T.text(self, _panel.position.x + 40.0, _panel.position.y + 156.0,
		"归档 / CASE %s · 报告：%s" % [String(payload.get("outcome_kind", "")),
			String(payload.get("report_mode_label", "—"))], T.F9, T.a(T.DIM, 0.95))
	var rows: Array = [
		["阶段 / PHASE", String(payload.get("phase_title", ""))],
		["证据 / EVIDENCE", String(payload.get("evidence", ""))],
		["审计 / AUDIT", String(payload.get("audit_note", "—"))],
		["声望 / REPUTATION", String(payload.get("reputation", "—"))],
		["平民撤离 / EVAC", String(payload.get("civilians", "—"))],
		["武器释放 / FIRE", String(payload.get("fire_release", "—"))],
	]
	var y := _panel.position.y + 196.0
	for i in range(rows.size()):
		var row: Array = rows[i]
		var ry := y + float(i) * 30.0
		T.text(self, _panel.position.x + 40.0, ry, String(row[0]), T.F8, T.FAINT)
		T.text_fit(self, _panel.position.x + 280.0, ry - 1.0, String(row[1]), T.F10, T.a(T.TXT, 0.95), 620.0)
	T.hline(self, _panel.position.x + 24.0, y + 186.0, _panel.end.x - 24.0, T.a(T.LINE, 0.8))
	var summary := String(payload.get("summary", ""))
	if summary != "":
		_draw_wrapped(summary, _panel.position.x + 40.0, y + 200.0, _panel.size.x - 80.0, T.F9,
			T.a(T.PH_DIM, 0.95), 18.0)
	var history := String(payload.get("history", ""))
	if history != "":
		T.text_fit(self, _panel.position.x + 40.0, _panel.end.y - 128.0, history, T.F8,
			T.a(T.FAINT, 0.85), _panel.size.x - 80.0)


func _draw_buttons() -> void:
	for i in range(_buttons.size()):
		var b: Dictionary = _buttons[i]
		var r: Rect2 = b["rect"]
		var action := String(b.get("action", ""))
		var enabled := bool(b.get("enabled", true))
		var hovered := i == _hover_btn
		var col: Color = T.PH
		match action:
			"report_fake":
				col = T.AMBER
			"quit":
				col = T.RED
		draw_rect(r, T.a(col, (0.16 if hovered else 0.07) if enabled else 0.03))
		draw_rect(r, T.a(col, 0.85 if enabled else 0.30), false, 1.0)
		T.text_c(self, r.get_center().x, r.position.y + 13.0, String(b.get("label", "")), T.F10,
			T.a(col, 0.96) if enabled else T.a(T.FAINT, 0.9))


func _draw_hint() -> void:
	var hint := ""
	if _hover_btn >= 0 and not bool((_buttons[_hover_btn] as Dictionary).get("enabled", true)):
		hint = "不可用：" + String((_buttons[_hover_btn] as Dictionary).get("reason", ""))
	elif _hover_row >= 0 and _rows.size() > _hover_row:
		var row: Dictionary = _rows[_hover_row]
		var data: Dictionary = row.get("data", {})
		hint = String(data.get("hint", ""))
		if not bool(row.get("enabled", true)):
			hint = "不可用：" + String(row.get("reason", ""))
	if hint != "":
		T.text_fit(self, _panel.position.x + 28.0, _panel.end.y - 30.0, hint, T.F8,
			T.a(T.AMBER, 0.9), _panel.size.x - 56.0)
	else:
		T.text_r(self, _panel.end.x - 28.0, _panel.end.y - 30.0,
			"1–4 选择 · ENTER 确认 · R 重开 · Q 退出", T.F7, T.a(T.FAINT, 0.8))


# ══ 输入 ═════════════════════════════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if mode == MODE_NONE:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hb := -1
		for i in range(_buttons.size()):
			if (_buttons[i]["rect"] as Rect2).has_point(mm.position):
				hb = i
				break
		var hr := -1
		for i in range(_rows.size()):
			if (_rows[i]["rect"] as Rect2).has_point(mm.position):
				hr = i
				break
		if hb != _hover_btn or hr != _hover_row:
			_hover_btn = hb
			_hover_row = hr
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		for i in range(_buttons.size()):
			var b: Dictionary = _buttons[i]
			if not (b["rect"] as Rect2).has_point(mb.position):
				continue
			if not bool(b.get("enabled", true)):
				queue_redraw()
				return
			_activate(String(b.get("action", "")))
			accept_event()
			return
		for i in range(_rows.size()):
			var row: Dictionary = _rows[i]
			if not (row["rect"] as Rect2).has_point(mb.position):
				continue
			var kind := String(row["kind"])
			if kind == "route" or kind == "window":
				prelude_choose.emit(kind, String(row["id"]))
			elif kind == "ending":
				_choose_row(row)
			accept_event()
			return


func _choose_row(row: Dictionary) -> void:
	if not bool(row.get("enabled", true)):
		return
	var kind := String(row["id"])
	if kind == "FIRE":
		if not _fire_confirm:
			_fire_confirm = true
			queue_redraw()
			return
	decision_chosen.emit(kind)


func handle_key(keycode: int) -> bool:
	if mode == MODE_NONE:
		return false
	match mode:
		MODE_PRELUDE:
			if keycode >= KEY_1 and keycode <= KEY_4:
				var n := keycode - KEY_1
				var kind := "route" if n < 2 else "window"
				var idx := n if n < 2 else n - 2
				var id := ""
				var count := 0
				for raw in _rows:
					var row: Dictionary = raw
					if String(row["kind"]) != kind:
						continue
					if count == idx:
						id = String(row["id"])
						break
					count += 1
				if id != "":
					prelude_choose.emit(kind, id)
				return true
			if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
				for raw2 in _buttons:
					var b: Dictionary = raw2
					if String(b.get("action", "")) == "execute" and bool(b.get("enabled", true)):
						_activate("execute")
						return true
				return true
		MODE_DECISION:
			if keycode >= KEY_1 and keycode <= KEY_4:
				var n2 := keycode - KEY_1
				if n2 < _rows.size():
					_choose_row(_rows[n2])
				return true
		MODE_REPORT:
			if keycode == KEY_T:
				_activate("report_truth")
				return true
			if keycode == KEY_F:
				_activate("report_fake")
				return true
		MODE_END:
			if keycode == KEY_R:
				end_restart.emit()
				return true
			if keycode == KEY_Q or keycode == KEY_ESCAPE:
				end_quit.emit()
				return true
	return false


func _activate(action: String) -> void:
	match action:
		"execute":
			prelude_execute.emit()
		"report_truth":
			report_submitted.emit("truth")
		"report_fake":
			report_submitted.emit("fake")
		"restart":
			end_restart.emit()
		"quit":
			end_quit.emit()


# ══ 文本换行 ═════════════════════════════════════════════════════════════

func _wrap(text: String, max_w: float, sz: int) -> Array:
	var lines: Array = []
	var font := T.font_for(text)
	var cur := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if ch == "\n":
			lines.append(cur)
			cur = ""
			continue
		var test := cur + ch
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w and cur != "":
			lines.append(cur)
			cur = ch
		else:
			cur = test
	if cur != "":
		lines.append(cur)
	return lines


func _draw_wrapped(text: String, x: float, y: float, max_w: float, sz: int, col: Color, line_h := 18.0) -> float:
	var lines: Array = _wrap(text, max_w, sz)
	for i in range(lines.size()):
		T.text(self, x, y + float(i) * line_h, String(lines[i]), sz, col, T.has_cjk(String(lines[i])))
	return y + float(lines.size()) * line_h
