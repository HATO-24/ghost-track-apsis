extends Control

## V2 通用动作菜单（action menu）。
##
## 两种形态共用同一套数据/几何：
## - `popup`：右键弹出的浮层（全屏遮罩 + 菜单面板，点外部/右键/ESC 关闭）；
## - `inline`：底部固定面板里的按钮式菜单（2 列 × 5 行）。
##
## 数据来自 `V2Actions.actions_for(actor, target)`（经 `ui/data_source.gd` 归一化）：
## 每项 {id, label, available, reason, levels:[...], requires:[...], unsupported}。
## 不可用项灰显并显示原因；可用项点击发 `action_chosen`（V2-1 尚未提供执行 API 前，
## app 只记录事件，不伪造仿真结果）。
##
## 分组：按动作最低识别等级 `levels[0]` 分组（L1 观测 / L2 位置 / L3 分类 / L4 识别·武器）。

signal action_chosen(action_id: String, target_id: String)
signal closed

const L := preload("res://ui/layout.gd")
const T := preload("res://ui/theme.gd")

const MODE_POPUP := "popup"
const MODE_INLINE := "inline"

var mode := MODE_POPUP
var actions: Array = []
var target: Dictionary = {}
var title := "目标动作 / TARGET ACTIONS"
var hint := ""
var accent := T.PH

var _rows: Array = []          # 几何行：{type:"group"/"action", label, action, rect}
var _panel := Rect2()
var _body := Rect2()
var _content_h := 0.0
var _max_offset := 0.0
var _offset := 0.0
var _anchor := Vector2(960.0, 540.0)
var _hover_row := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	accent = T.PH


# ══ 数据/几何 ════════════════════════════════════════════════════════════

func set_actions(acts: Array, tgt: Dictionary = {}) -> void:
	actions = acts if acts != null else []
	target = tgt if tgt != null else {}
	accent = T.accent_for(target)
	hint = ""
	_hover_row = -1
	_rebuild()
	queue_redraw()


func open(acts: Array, tgt: Dictionary, at: Vector2) -> void:
	mode = MODE_POPUP
	_anchor = at
	set_actions(acts, tgt)
	visible = true
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_hover_row = -1
	hint = ""
	closed.emit()


func is_open() -> bool:
	return visible and mode == MODE_POPUP


func target_id() -> String:
	return String(target.get("id", ""))


func group_label(tier: int) -> String:
	match tier:
		1:
			return "L1 · 观测 / OBSERVE"
		2:
			return "L2 · 位置 / POSITION"
		3:
			return "L3 · 分类 / CLASSIFY"
		_:
			return "L4 · 识别·武器 / IDENT"


func inline_row_count() -> int:
	var n := 0
	for raw in _rows:
		if String((raw as Dictionary).get("type", "")) == "action":
			n += 1
	return n


func first_disabled_action() -> Dictionary:
	for raw in actions:
		var a: Dictionary = raw
		if not bool(a.get("available", false)):
			return a
	return {}


func row_rect_for(action_id: String) -> Rect2:
	for raw in _rows:
		var row: Dictionary = raw
		if String(row.get("type", "")) != "action":
			continue
		if String((row.get("action", {}) as Dictionary).get("id", "")) == action_id:
			return row["rect"]
	return Rect2()


func available_count() -> int:
	var n := 0
	for raw in actions:
		if bool((raw as Dictionary).get("available", false)):
			n += 1
	return n


## 截图/测试用：把某行设为 hover 态，让 footer 显示原因。
func debug_focus(action_id: String) -> void:
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		if String(row.get("type", "")) != "action":
			continue
		var a: Dictionary = row.get("action", {})
		if String(a.get("id", "")) == action_id:
			_hover_row = i
			hint = _reason_of(a) if not bool(a.get("available", false)) else ""
			queue_redraw()
			return


## 测试用：等价于点击某项。
func debug_click(action_id: String) -> bool:
	for raw in _rows:
		var row: Dictionary = raw
		if String(row.get("type", "")) != "action":
			continue
		var a: Dictionary = row.get("action", {})
		if String(a.get("id", "")) == action_id:
			_activate(row)
			return true
	return false


func _reason_of(a: Dictionary) -> String:
	var reason := String(a.get("reason", ""))
	if reason == "":
		reason = "不可用（未给出原因）"
	return reason


func _rebuild() -> void:
	_rows.clear()
	if mode == MODE_INLINE:
		_rebuild_inline()
	elif mode == MODE_POPUP:
		_rebuild_popup()
	else:
		_rebuild_popup()


func _rebuild_popup() -> void:
	# 1) 按 levels[0] 分组，组内保持 actions_for 顺序。
	var groups: Dictionary = {}
	var order: Array = []
	for raw in actions:
		var a: Dictionary = raw
		var tier := int(a.get("tier", 1))
		if not groups.has(tier):
			groups[tier] = []
			order.append(tier)
		(groups[tier] as Array).append(a)
	order.sort()
	# 2) 内容总高：header + 各组 + footer。
	var content_h := T.MENU_HEADER_H
	for tier in order:
		content_h += T.MENU_GROUP_H + float((groups[tier] as Array).size()) * T.ROW_MENU
	var full_h := content_h + T.MENU_FOOTER_H
	var max_h := L.DESIGN.y - 48.0
	var panel_h := minf(full_h, max_h)
	var w := T.MENU_W
	var x := _anchor.x + 16.0
	if x + w > L.DESIGN.x - 24.0:
		x = _anchor.x - w - 16.0
	x = clampf(x, 24.0, L.DESIGN.x - w - 24.0)
	var y := _anchor.y - 32.0
	if y + panel_h > L.DESIGN.y - 24.0:
		y = _anchor.y - panel_h - 24.0
	y = clampf(y, 24.0, L.DESIGN.y - panel_h - 24.0)
	_panel = Rect2(x, y, w, panel_h)
	_body = Rect2(x + 2.0, y + T.MENU_HEADER_H, w - 4.0, panel_h - T.MENU_HEADER_H - T.MENU_FOOTER_H)
	_content_h = content_h
	_max_offset = maxf(0.0, content_h - _body.size.y)
	_offset = clampf(_offset, 0.0, _max_offset)
	var ry := T.MENU_HEADER_H - _offset
	for tier in order:
		_rows.append({
			"type": "group",
			"label": group_label(int(tier)),
			"rect": Rect2(x + 8.0, y + ry, w - 16.0, T.MENU_GROUP_H),
		})
		ry += T.MENU_GROUP_H
		for raw2 in groups[tier]:
			_rows.append({
				"type": "action",
				"action": raw2,
				"rect": Rect2(x + 8.0, y + ry, w - 16.0, T.ROW_MENU),
			})
			ry += T.ROW_MENU


func _rebuild_inline() -> void:
	_panel = Rect2(0.0, 0.0, size.x, size.y)
	_body = _panel
	_content_h = 0.0
	_max_offset = 0.0
	_offset = 0.0
	var pad := 8.0
	var header := 22.0
	var footer := 16.0
	var gap := 2.0
	var cols := 2
	var rows_n := int(ceil(float(actions.size()) / float(cols)))
	var col_w := (size.x - pad * 2.0 - 8.0) / float(cols)
	var row_h := 20.0
	var max_rows := int(floor((size.y - header - footer - pad) / (row_h + gap)))
	rows_n = mini(rows_n, max_rows)
	for i in range(mini(actions.size(), rows_n * cols)):
		var col := i % cols
		var rowi := int(floor(float(i) / float(cols)))
		_rows.append({
			"type": "action",
			"action": actions[i],
			"rect": Rect2(pad + float(col) * (col_w + 8.0), header + pad + float(rowi) * (row_h + gap), col_w, row_h),
		})


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	if mode == MODE_INLINE:
		_draw_inline()
	else:
		_draw_popup()


func _draw_popup() -> void:
	draw_rect(Rect2(Vector2.ZERO, L.DESIGN), Color(0.01, 0.03, 0.024, 0.55))
	draw_rect(Rect2(_panel.position + Vector2(4.0, 4.0), _panel.size), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(_panel, T.a(T.PANEL, 0.985))
	draw_rect(_panel, T.a(accent, 0.8), false, 1.0)
	T.corners(self, _panel.grow(-1.0), 12.0, accent, 0.9)

	# header
	T.text(self, _panel.position.x + 14.0, _panel.position.y + 12.0,
		"[%s] %s" % [_target_batch(), String(target.get("name", "—"))], T.F11, T.a(accent, 0.96))
	var identity := String(target.get("identity", "unknown"))
	T.text(self, _panel.position.x + 14.0, _panel.position.y + 32.0,
		"L%d · %s · %s · %s" % [
			int(target.get("level", 0)), T.identity_label(identity),
			T.kind_label(String(target.get("kind", "ship"))),
			T.side_label(String(target.get("side", "unknown"))),
		], T.F8, T.DIM)
	T.text_r(self, _panel.end.x - 14.0, _panel.position.y + 12.0, title, T.F8, T.a(accent, 0.75))
	T.text_r(self, _panel.end.x - 14.0, _panel.position.y + 32.0,
		"可用 %d/%d" % [available_count(), actions.size()], T.F7, T.a(T.FAINT, 0.9), false)
	T.hline(self, _panel.position.x, _panel.position.y + T.MENU_HEADER_H,
		_panel.end.x, T.a(T.LINE, 0.85))

	# body（超出部分裁掉，只画完整落在 body 内的行）
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var r: Rect2 = row["rect"]
		if r.end.y > _body.end.y + 0.5 or r.position.y < _body.position.y - 0.5:
			continue
		if String(row.get("type", "")) == "group":
			var gx := _panel.position.x + 8.0
			var gy: float = r.position.y
			T.text(self, gx + 4.0, gy + 4.0, String(row.get("label", "")), T.F7, T.a(T.AMBER, 0.72), false)
			draw_line(Vector2(gx + 4.0, gy + T.MENU_GROUP_H - 3.0),
				Vector2(_panel.end.x - 8.0, gy + T.MENU_GROUP_H - 3.0), T.a(T.LINE, 0.35), 1.0)
			continue
		var action: Dictionary = row.get("action", {})
		var ok := bool(action.get("available", false))
		var hot := i == _hover_row and ok
		if hot:
			draw_rect(Rect2(r.position.x + 2.0, r.position.y, r.size.x - 4.0, r.size.y), T.a(T.PH, 0.08))
		var col := T.a(T.TXT, 0.95) if ok else T.a(T.FAINT, 0.85)
		T.text(self, r.position.x + 6.0, r.position.y + 4.0, "▸" if ok else "·", T.F8, T.a(col, 0.85), false)
		T.text(self, r.position.x + 22.0, r.position.y + 4.0, String(action.get("label", "")), T.F9, col)
		if ok:
			T.text_r(self, r.end.x - 6.0, r.position.y + 4.0, "可用", T.F7, T.a(T.PH, 0.75))
		else:
			T.text_fit_r(self, r.end.x - 6.0, r.position.y + 4.0, _reason_of(action), T.F7,
				T.a(T.AMBER, 0.68), r.size.x - 160.0)
		if i == _hover_row and not ok:
			hint = _reason_of(action)

	# footer
	var fy := _panel.end.y - T.MENU_FOOTER_H
	T.hline(self, _panel.position.x, fy, _panel.end.x, T.a(T.LINE, 0.7))
	var foot := hint if hint != "" else "点击可用动作 · 灰显为不可用（右侧为原因） · ESC/右键关闭"
	T.text_fit(self, _panel.position.x + 12.0, fy + 8.0, foot, T.F7,
		T.a(T.AMBER, 0.9) if hint != "" else T.a(T.FAINT, 0.9), _panel.size.x - 24.0)
	if _max_offset > 0.0:
		T.text_r(self, _panel.end.x - 12.0, fy + 8.0, "滚轮", T.F7, T.a(T.FAINT, 0.8))


func _draw_inline() -> void:
	draw_rect(Rect2(0.0, 0.0, size.x, size.y), T.a(T.PANEL, 0.965))
	draw_rect(Rect2(0.0, 0.0, size.x, size.y), T.a(T.LINE, 0.85), false, 1.0)
	T.text(self, 12.0, 5.0, title, T.F9, T.a(T.TXT, 0.92))
	T.text_r(self, size.x - 12.0, 5.0,
		"[%s] %s" % [_target_batch(), _ellipsis_name()], T.F8, T.a(accent, 0.85), true)
	T.text_r(self, size.x - 12.0, 19.0, "可用 %d/%d · 右键出完整菜单 + 原因" % [available_count(), actions.size()],
		T.F7, T.a(T.FAINT, 0.9))
	T.hline(self, 8.0, 24.0, size.x - 8.0, T.a(T.LINE, 0.7))
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var r: Rect2 = row["rect"]
		var action: Dictionary = row.get("action", {})
		var ok := bool(action.get("available", false))
		var hot := i == _hover_row and ok
		draw_rect(r, T.a(T.PANEL2, 0.95 if hot else 0.45))
		draw_rect(r, T.a(T.PH if ok else T.LINE, 0.75 if ok else 0.5), false, 1.0)
		var col := T.a(T.PH, 0.95) if ok else T.a(T.FAINT, 0.9)
		T.badge(self, Rect2(r.position.x + 4.0, r.position.y + 3.0, 15.0, 14.0),
			"L%d" % int(action.get("tier", 1)), T.PH if ok else T.FAINT, T.F7)
		T.text_fit(self, r.position.x + 23.0, r.position.y + 1.0, String(action.get("label", "")),
			T.F8, col, r.size.x - 72.0)
		if ok:
			T.text_r(self, r.end.x - 5.0, r.position.y + 2.0, "可用", T.F7, T.a(T.PH, 0.8))
		else:
			T.text_r(self, r.end.x - 5.0, r.position.y + 2.0, _short_reason(action), T.F7,
				T.a(T.AMBER, 0.75))
	if _rows.is_empty():
		T.text(self, 12.0, 34.0, "（无目标动作 / NO ACTIONS）", T.F9, T.FAINT)
	var foot := hint if hint != "" else "点击执行（V2-1 core 执行 API 未接入，仅记为 UI 事件）"
	T.text_fit(self, 12.0, size.y - 16.0, foot, T.F7,
		T.a(T.AMBER, 0.9) if hint != "" else T.a(T.FAINT, 0.85), size.x - 24.0)


func _ellipsis_name() -> String:
	var name := String(target.get("name", ""))
	return T.ellipsis(name, T.F8, 120.0)


func _target_batch() -> String:
	var c: Variant = target.get("contact", {})
	if c is Dictionary:
		var batch := String((c as Dictionary).get("batch", ""))
		if batch != "":
			return batch
	return target_id()


## inline 按钮太窄：把不可用原因压缩成 2–3 字状态码（完整原因在 popup / section 里）。
func _short_reason(a: Dictionary) -> String:
	match String(a.get("reason_code", "")):
		"level":
			return "等级"
		"capability":
			return "能力"
		"unsupported":
			return "未实现"
		"no_track":
			return "无航迹"
		"no_range":
			return "无距离"
		"range":
			return "超距"
		"phase":
			return "阶段"
		"flag":
			return "条件"
		_:
			var reason := String(a.get("reason", ""))
			return "不可用" if reason == "" else T.ellipsis(reason, T.F7, 54.0, true)




# ══ 输入 ═════════════════════════════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var idx := _row_at(mm.position)
		if idx != _hover_row:
			_hover_row = idx
			var h := ""
			if idx >= 0:
				var row: Dictionary = _rows[idx]
				var a: Dictionary = row.get("action", {})
				if not bool(a.get("available", false)):
					h = _reason_of(a)
			hint = h
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mode == MODE_POPUP:
				close()
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mode == MODE_POPUP and _scroll_by(-T.ROW_MENU):
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == MODE_POPUP and _scroll_by(T.ROW_MENU):
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mode == MODE_POPUP and not _panel.has_point(mb.position):
				close()
				accept_event()
				return
			var idx2 := _row_at(mb.position)
			if idx2 >= 0:
				_activate(_rows[idx2])
				accept_event()


func _row_at(pos: Vector2) -> int:
	if mode == MODE_POPUP and not _body.has_point(pos):
		return -1
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		if String(row.get("type", "")) != "action":
			continue
		if (row["rect"] as Rect2).has_point(pos):
			return i
	return -1


func _scroll_by(dy: float) -> bool:
	if _max_offset <= 0.5:
		return false
	var before := _offset
	_offset = clampf(_offset + dy, 0.0, _max_offset)
	if is_equal_approx(before, _offset):
		return false
	_rebuild()
	queue_redraw()
	return true


func _activate(row: Dictionary) -> void:
	if String(row.get("type", "")) != "action":
		return
	var a: Dictionary = row.get("action", {})
	var aid := String(a.get("id", ""))
	if not bool(a.get("available", false)):
		hint = "不可用：" + _reason_of(a)
		queue_redraw()
		return
	hint = "已选择：%s" % String(a.get("label", aid))
	action_chosen.emit(aid, target_id())
	if mode == MODE_POPUP:
		close()
