extends Control

# 阶段1B 中日英输入组件（Control 自绘；不依赖系统候选窗）。
# - 文本/组合串/候选/已选/焦点；控制字符与特殊符号过滤；长度限制；空名/重复名校验接口。
# - 真实 IME 组合事件在 Godot 侧仍需发行版/平台 IME 支持；本组件处理
#   InputEventIMEComposition，并允许外部注入候选（probe/演示）。
# - 不接剧情/存档。

signal text_changed(text: String)
signal composition_changed(composition: String)
signal candidate_changed(index: int, candidate: String)
signal submitted(result: Dictionary)
signal cancelled
signal focus_changed(focused: bool)

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")

const MAX_NAME_LEN := 24
const PAGE_SIZE := 5

var text := ""
var composition := ""
var candidates: Array = []
var selected := 0
var page := 0
var max_length := MAX_NAME_LEN
var enabled := true
var duplicate_names: Array = []
var duplicate_check: Callable = Callable()
var placeholder := "输入玩家名 / PLAYER NAME"
var input_rect := Rect2()
var _focused := false
var _caret_t := 0.0
var candidate_window = null


func _ready() -> void:
	custom_minimum_size = Vector2(460, 42)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_input(true)


static func sanitize(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code < 0x20 or code == 0x7f:
			continue
		if code >= 0x7f and code <= 0x9f:
			continue
		# 中文/日文/韩文、拉丁字母、数字、空格、常用名连接符
		if code >= 0x4e00 and code <= 0x9fff:
			out += String.chr(code)
		elif code >= 0x3040 and code <= 0x30ff:
			out += String.chr(code)
		elif code >= 0xac00 and code <= 0xd7af:
			out += String.chr(code)
		elif (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5a) or (code >= 0x61 and code <= 0x7a):
			out += String.chr(code)
		elif code in [0x20, 0x2d, 0x5f, 0xb7]:  # space - _ ·
			out += String.chr(code)
		# 其他符号/emoji/控制字符过滤
	return _normalize_spaces(out)


static func _normalize_spaces(s: String) -> String:
	var out := ""
	var prev_space := false
	for i in s.length():
		var ch := s.substr(i, 1)
		if ch == " ":
			if not prev_space:
				out += ch
			prev_space = true
		else:
			out += ch
			prev_space = false
	return out.strip_edges()


static func truncate(s: String, limit: int) -> String:
	if limit <= 0:
		return ""
	if s.length() <= limit:
		return s
	return s.substr(0, limit)


func reset() -> void:
	text = ""
	composition = ""
	candidates = []
	selected = 0
	page = 0
	queue_redraw()


func set_text(s: String) -> void:
	text = truncate(sanitize(s), max_length)
	composition = ""
	candidates = []
	selected = 0
	page = 0
	text_changed.emit(text)
	queue_redraw()


func set_composition(comp: String, cands: Array = []) -> void:
	composition = truncate(sanitize(comp), max_length)
	candidates = []
	for raw in cands:
		var c := sanitize(String(raw))
		if c != "" and c.length() <= max_length:
			candidates.append(c)
	selected = 0
	page = 0
	if composition == "" and candidates.size() > 0:
		composition = String(candidates[0])
	composition_changed.emit(composition)
	_sync_candidate_window()
	queue_redraw()


func set_candidates(cands: Array) -> void:
	set_composition(composition, cands)


## 外部 IME 桥/平台事件可注入组合串与候选（不依赖系统候选窗）。
func apply_ime_composition(comp: String, cands: Array = []) -> void:
	set_composition(comp, cands)


func candidate_count() -> int:
	return candidates.size()


func page_count() -> int:
	return maxi(1, int(ceil(float(candidates.size()) / float(PAGE_SIZE))))


func current_candidate() -> String:
	if candidates.is_empty():
		return ""
	return String(candidates[clampi(selected, 0, candidates.size() - 1)])


func select_next() -> String:
	if candidates.is_empty():
		return ""
	selected = (selected + 1) % candidates.size()
	page = selected / PAGE_SIZE
	candidate_changed.emit(selected, current_candidate())
	_sync_candidate_window()
	queue_redraw()
	return current_candidate()


func select_prev() -> String:
	if candidates.is_empty():
		return ""
	selected = (selected - 1 + candidates.size()) % candidates.size()
	page = selected / PAGE_SIZE
	candidate_changed.emit(selected, current_candidate())
	_sync_candidate_window()
	queue_redraw()
	return current_candidate()


func next_page() -> void:
	if candidates.is_empty():
		return
	page = mini(page_count() - 1, page + 1)
	selected = mini(page * PAGE_SIZE, candidates.size() - 1)
	_sync_candidate_window()
	queue_redraw()


func prev_page() -> void:
	if candidates.is_empty():
		return
	page = maxi(0, page - 1)
	selected = mini(page * PAGE_SIZE, candidates.size() - 1)
	_sync_candidate_window()
	queue_redraw()


func confirm_candidate() -> String:
	var c := current_candidate()
	if c != "":
		text = truncate(sanitize(text + c), max_length)
		text_changed.emit(text)
	composition = ""
	candidates = []
	selected = 0
	page = 0
	_sync_candidate_window()
	queue_redraw()
	return c


func cancel_composition() -> void:
	composition = ""
	candidates = []
	selected = 0
	page = 0
	_sync_candidate_window()
	queue_redraw()


func commit_name() -> Dictionary:
	var n := sanitize(text)
	var res := validate_name(n)
	if bool(res.get("ok", false)):
		text = String(res.get("value", n))
		submitted.emit(res)
	else:
		submitted.emit(res)
	queue_redraw()
	return res


func validate_name(n: String) -> Dictionary:
	var v := truncate(sanitize(n), max_length)
	if v == "":
		return {"ok": false, "reason": "empty_name", "value": v, "max_length": max_length}
	if v.length() < 2:
		return {"ok": false, "reason": "name_too_short", "value": v, "max_length": max_length}
	if duplicate_check.is_valid():
		var dup := bool(duplicate_check.call(v))
		if dup:
			return {"ok": false, "reason": "duplicate_name", "value": v, "max_length": max_length}
	elif duplicate_names.has(v):
		return {"ok": false, "reason": "duplicate_name", "value": v, "max_length": max_length}
	return {"ok": true, "reason": "", "value": v, "max_length": max_length}


func cancel() -> void:
	cancel_composition()
	cancelled.emit()
	queue_redraw()


func _process(delta: float) -> void:
	_caret_t += delta
	if _focused:
		queue_redraw()


func _sync_candidate_window() -> void:
	if candidate_window == null:
		return
	candidate_window.set_data(composition, candidates, selected, page)
	if input_rect.size.x > 0.0:
		candidate_window.place(input_rect)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var th: Theme = theme
	if th != null:
		draw_style_box(th.get_stylebox("panel", "Panel"), r)
	else:
		draw_rect(r, P.PANEL)
	draw_rect(r, P.a(P.PH if _focused else P.LINE, 0.75 if _focused else 0.45), false, 1.0)
	var mono := F.mono()
	var cjk := F.cjk()
	var x := 12.0
	var base := size.y * 0.5 - 6.0
	draw_string(mono, Vector2(x, base), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.PH if _focused else P.FAINT)
	var shown := text
	if composition != "":
		shown = text + composition
	if shown == "":
		draw_string(cjk, Vector2(x + 20, base), placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.a(P.FAINT, 0.85))
	else:
		draw_string(cjk, Vector2(x + 20, base), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TXT)
		if composition != "":
			var tw := cjk.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var cw := cjk.get_string_size(composition, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_line(Vector2(x + 20 + tw, base + 3), Vector2(x + 20 + tw + cw, base + 3), P.a(P.AMBER, 0.85), 1.0)
	if _focused and composition == "" and fmod(_caret_t, 1.0) < 0.55:
		var ct := cjk.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_line(Vector2(x + 20 + ct, base - 9), Vector2(x + 20 + ct, base + 3), P.PH, 1.0)
	draw_string(mono, Vector2(size.x - 84, 12), "IME NAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))
	draw_string(mono, Vector2(size.x - 84, 24), "%d/%d" % [text.length(), max_length], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.DIM, 0.9))


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		accept_event()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_UP:
		select_prev(); accept_event(); return
	if k.keycode == KEY_DOWN:
		select_next(); accept_event(); return
	if k.keycode == KEY_PAGEUP:
		prev_page(); accept_event(); return
	if k.keycode == KEY_PAGEDOWN:
		next_page(); accept_event(); return
	if k.keycode == KEY_ESCAPE:
		if composition != "":
			cancel_composition()
		else:
			cancel()
		accept_event(); return
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		if composition != "" and not candidates.is_empty():
			confirm_candidate()
		else:
			commit_name()
		accept_event(); return
	if k.keycode == KEY_BACKSPACE:
		if composition != "":
			composition = composition.substr(0, composition.length() - 1)
			_sync_candidate_window()
		elif text != "":
			text = text.substr(0, text.length() - 1)
			text_changed.emit(text)
		accept_event(); queue_redraw(); return
	if k.unicode > 0:
		var ch := sanitize(String.chr(k.unicode))
		if ch == "":
			accept_event(); return
		if composition != "":
			composition = truncate(composition + ch, max_length)
			composition_changed.emit(composition)
			_sync_candidate_window()
		else:
			var nv := truncate(text + ch, max_length)
			if nv != text:
				text = nv
				text_changed.emit(text)
		accept_event(); queue_redraw()


func focus_input() -> void:
	grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER:
		_focused = true
		focus_changed.emit(true)
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_EXIT:
		_focused = false
		focus_changed.emit(false)
		queue_redraw()


func to_dict() -> Dictionary:
	return {
		"text": text, "composition": composition, "candidates": candidates.duplicate(),
		"selected": selected, "page": page, "max_length": max_length,
		"valid": validate_name(text), "focused": _focused,
	}


func to_json() -> String:
	return JSON.stringify(to_dict())
