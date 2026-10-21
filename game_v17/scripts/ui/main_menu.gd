extends Control

# 方案B-21：V1 自绘主菜单。New/Continue/Load/Settings/Quit。
# 读档仅传 load_slot 给 ShellBinder；不伪造存档；不改剧情/物理。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")
const Painter := preload("res://scripts/ui/panel_painter.gd")
const SaveService := preload("res://scripts/core/save_service.gd")

const VERSION := "V1.7"
const SAVE_ROOT := "user://saves"
const SLOTS := ["save", "menu", "quit", "autosave"]
const PROLOGUE := "res://prologue.tscn"
const V1_HUD := "res://v1_hud.tscn"

var _save = null
var _slots: Array = []
var _latest := {}
var _overlay := ""
var _buttons: Array = []
var _overlay_buttons: Array = []
var _overlay_rows: Array = []
var _target_size := Vector2i(1920, 1080)
var _shot_path := ""
var _frames := 0
var _status := "READY · 选择行动"


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var sz := OS.get_environment("DSH_HUD_SIZE")
	if sz == "":
		sz = "1920x1080"
	var parts := sz.split("x")
	if parts.size() == 2:
		_target_size = Vector2i(int(parts[0]), int(parts[1]))
	var win := get_window()
	if win != null:
		win.size = _target_size
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	theme = null
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_save = SaveService.new(SAVE_ROOT)
	_refresh_slots()
	var view := OS.get_environment("DSH_MAIN_MENU_VIEW")
	if view in ["load", "settings", "quit"]:
		_overlay = view
	set_process(true)
	if _shot_path != "":
		get_window().size = _target_size
		Input.warp_mouse(Vector2(_target_size) * 0.5)


func _refresh_slots() -> void:
	_slots.clear()
	_latest = {}
	if _save == null:
		return
	var rows: Array = _save.list_slots()
	var by_slot: Dictionary = {}
	for raw in rows:
		if raw is Dictionary:
			by_slot[String((raw as Dictionary).get("slot", ""))] = raw
	for slot in SLOTS:
		var row: Dictionary = {"slot": slot, "exists": false, "ok": false}
		if by_slot.has(slot):
			row = (by_slot[slot] as Dictionary).duplicate(true)
		if bool(row.get("exists", false)) and bool(row.get("ok", false)):
			row["metadata"] = _save.load_metadata(slot).get("meta", {})
			var upd := float((row.get("metadata", {}) as Dictionary).get("updated_at", row.get("updated_at", 0.0)))
			if slot in ["save", "menu", "autosave"] and (_latest.is_empty() or upd > float((_latest.get("metadata", {}) as Dictionary).get("updated_at", 0.0))):
				_latest = row.duplicate(true)
		_slots.append(row)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), P.BG)
	draw_grid(w, h)
	# 标题
	var x := w * 0.10
	var y := h * 0.16
	draw_string(F.cjk(), Vector2(x, y), "GHOST TRACK // APSIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.PH)
	draw_string(F.mono(), Vector2(x, y + 26), "完整游戏 · " + VERSION + " · OCUVF-ID13 / L1 MERIDIAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.AMBER)
	draw_line(Vector2(x, y + 38), Vector2(w * 0.58, y + 38), P.a(P.LINE, 0.8), 1.0)
	draw_string(F.cjk(), Vector2(x, y + 64), "战术指挥终端 / V1 SELF-DRAWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TXT)
	draw_string(F.mono(), Vector2(x, y + 82), "MAIN MENU · 1920/1600 ADAPTIVE · NO FAKE SAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.FAINT, 0.9))
	_draw_emblem(Rect2(w * 0.68, y - 46, w * 0.22, w * 0.22))
	# 主按钮
	_buttons.clear()
	var bx := x
	var by := y + 122.0
	var bw := minf(440.0, w * 0.34)
	var bh := 44.0
	var labels := [
		["NEW", "NEW GAME / 新游戏"],
		["CONTINUE", "CONTINUE / 继续"],
		["LOAD", "LOAD / 读档"],
		["SETTINGS", "SETTINGS / 设置"],
		["QUIT", "QUIT / 退出"],
	]
	for i in range(labels.size()):
		var br := Rect2(bx, by + float(i) * (bh + 10.0), bw, bh)
		var k := String(labels[i][0])
		var enabled := true
		var sub := ""
		if k == "CONTINUE":
			enabled = not _latest.is_empty()
			sub = ("latest · " + String(_latest.get("slot", "")) + " · " + _fmt_time(float((_latest.get("metadata", {}) as Dictionary).get("updated_at", 0.0)))) if enabled else "NO SAVE · 无有效存档"
		elif k == "LOAD":
			sub = "SLOTS save/menu/quit/autosave"
		elif k == "SETTINGS":
			sub = "占位 · 未接设置"
		var col := P.PH if enabled else P.FAINT
		draw_rect(br, P.a(P.PANEL2, 0.55 if enabled else 0.20))
		draw_rect(br, P.a(col, 0.70 if enabled else 0.20), false, 1.0)
		Painter.label(self, br.position.x + 14, br.position.y + 26, String(labels[i][1]), 13, P.TXT if enabled else P.FAINT, false)
		if sub != "":
			Painter.label(self, br.position.x + bw - 8 - TM.width(sub, true, 7), br.position.y + 27, TM.fit(sub, bw - 170, true, 7), 7, P.a(P.DIM, 0.9), true)
		_buttons.append({"rect": br, "kind": k})
	# 状态与页脚
	Painter.label(self, x, by + 5.0 * (bh + 10.0) + 22.0, "STATUS  " + _status, 8, P.AMBER, true)
	Painter.label(self, x, h - 24.0, "V1 MENU · NEW→prologue · CONTINUE/LOAD→SaveService → v1_hud · QUIT 需确认", 7, P.a(P.FAINT, 0.9), true)
	Painter.label(self, w - 180.0, h - 24.0, "VERSION " + VERSION + " · " + str(_target_size.x) + "x" + str(_target_size.y), 7, P.a(P.FAINT, 0.9), true)
	if _overlay != "":
		_draw_overlay(w, h)


func draw_grid(w: float, h: float) -> void:
	for i in range(24):
		var gx := w * float(i) / 24.0
		draw_line(Vector2(gx, 0), Vector2(gx, h), P.a(P.LINE, 0.045), 1.0)
	for j in range(14):
		var gy := h * float(j) / 14.0
		draw_line(Vector2(0, gy), Vector2(w, gy), P.a(P.LINE, 0.045), 1.0)


func _draw_emblem(r: Rect2) -> void:
	# assets/emblems 不在当前工程；使用 V1 程序化徽记，不伪造图片。
	var c := r.position + r.size * 0.5
	var rad := minf(r.size.x, r.size.y) * 0.36
	draw_circle(c, rad + 14.0, P.a(P.PH, 0.05))
	draw_arc(c, rad, 0.0, TAU, 72, P.a(P.PH_DIM, 0.55), 1.0, true)
	draw_arc(c, rad * 0.76, 0.0, TAU, 64, P.a(P.AMBER, 0.45), 1.0, true)
	var pts := PackedVector2Array([c + Vector2(0, -rad * 0.55), c + Vector2(rad * 0.42, 0), c + Vector2(0, rad * 0.55), c + Vector2(-rad * 0.42, 0)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), P.a(P.PH, 0.75), 1.0)
	draw_line(c + Vector2(-rad * 0.55, 0), c + Vector2(rad * 0.55, 0), P.a(P.PH_DIM, 0.5), 1.0)
	draw_circle(c, 3.0, P.PH)
	Painter.label(self, r.position.x, r.end.y + 12.0, "OCUVF / ID13", 10, P.PH, false)
	Painter.label(self, r.position.x, r.end.y + 26.0, "PROCEDURAL EMBLEM · 非图片资产", 6, P.a(P.FAINT, 0.9), true)


func _draw_overlay(w: float, h: float) -> void:
	var r := Rect2(w * 0.18, h * 0.20, w * 0.64, h * 0.60)
	draw_rect(r, P.a(P.PANEL, 0.985))
	draw_rect(r, P.a(P.LINE2, 0.65), false, 1.0)
	var x := r.position.x + 22.0
	var y := r.position.y + 30.0
	_overlay_buttons.clear()
	_overlay_rows.clear()
	if _overlay == "load":
		Painter.label(self, x, y, "LOAD / 读档", 15, P.PH)
		Painter.label(self, x, y + 16, "槽位来自 SaveService · 只读校验 · 选择读取到 v1_hud", 8, P.a(P.AMBER, 0.9), true)
		var ry := y + 42.0
		for i in range(_slots.size()):
			var row: Dictionary = _slots[i]
			var rr := Rect2(x, ry + float(i) * 62.0, r.size.x - 44.0, 56.0)
			var ok := bool(row.get("exists", false)) and bool(row.get("ok", false))
			var md: Dictionary = row.get("metadata", {}) if row.get("metadata", {}) is Dictionary else {}
			draw_rect(rr, P.a(P.PANEL2, 0.35))
			Painter.label(self, rr.position.x + 8, rr.position.y + 18, String(row.get("slot", "")).to_upper(), 11, P.PH if ok else P.FAINT, true)
			var state := "EMPTY" if not bool(row.get("exists", false)) else ("CORRUPTED" if not bool(row.get("ok", false)) else "VALID · " + _fmt_time(float(md.get("updated_at", 0.0))))
			Painter.label(self, rr.position.x + 8, rr.position.y + 34, state, 8, P.PH if ok else P.AMBER, true)
			if ok:
				Painter.label(self, rr.position.x + 220, rr.position.y + 18, "CHAPTER " + String(md.get("chapter", "—")) + " · " + String(md.get("location", "—")), 7, P.TXT, true)
				Painter.label(self, rr.position.x + 220, rr.position.y + 34, "SIZE / path " + String(row.get("path", "")), 6, P.a(P.FAINT, 0.9), true)
				var br := Rect2(rr.end.x - 112, rr.position.y + 16, 96, 24)
				_overlay_buttons.append({"rect": br, "kind": "LOAD:" + String(row.get("slot", ""))})
				Painter.button(self, br, "LOAD", true, P.PH)
		var cl := Rect2(r.end.x - 120.0, r.end.y - 40.0, 96, 26)
		_overlay_buttons.append({"rect": cl, "kind": "CLOSE"})
		Painter.button(self, cl, "CLOSE", true, P.PH_DIM)
	elif _overlay == "settings":
		Painter.label(self, x, y, "SETTINGS / 设置", 15, P.PH)
		Painter.label(self, x, y + 40, "占位 · 设置页面未接入（音量/键位/显示等后续任务）", 11, P.TXT, false)
		Painter.label(self, x, y + 60, "当前无设置写入；不伪造选项。", 8, P.PH_DIM, true)
		var cl2 := Rect2(r.end.x - 120.0, r.end.y - 40.0, 96, 26)
		_overlay_buttons.append({"rect": cl2, "kind": "CLOSE"})
		Painter.button(self, cl2, "CLOSE", true, P.PH_DIM)
	elif _overlay == "quit":
		Painter.label(self, x, y, "QUIT / 退出确认", 15, P.AMBER)
		Painter.label(self, x, y + 44, "确认退出游戏？未保存进度会丢失。", 11, P.TXT, false)
		Painter.label(self, x, y + 64, "QUIT 只在确认后调用 get_tree().quit()。", 8, P.PH_DIM, true)
		var yes := Rect2(r.end.x - 230.0, r.end.y - 44.0, 96, 28)
		var no := Rect2(r.end.x - 120.0, r.end.y - 44.0, 96, 28)
		_overlay_buttons.append({"rect": yes, "kind": "QUIT_YES"})
		_overlay_buttons.append({"rect": no, "kind": "CLOSE"})
		Painter.button(self, yes, "确认退出", true, P.AMBER)
		Painter.button(self, no, "取消", true, P.PH_DIM)


func _fmt_time(unix_s: float) -> String:
	if unix_s <= 0.0:
		return "—"
	return Time.get_datetime_string_from_unix_time(int(unix_s))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := (event as InputEventMouseButton).position
	if _overlay != "":
		for b in _overlay_buttons:
			if (b["rect"] as Rect2).has_point(pos):
				_overlay_action(String(b.get("kind", "")))
				accept_event()
				return
		return
	for b in _buttons:
		if (b["rect"] as Rect2).has_point(pos):
			_main_action(String(b.get("kind", "")))
			accept_event()
			return


func _main_action(kind: String) -> void:
	match kind:
		"NEW":
			OS.set_environment("DSH_LOAD_SLOT", "")
			get_tree().root.set_meta("load_slot", "")
			get_tree().root.set_meta("flow_state", {})
			_status = "NEW GAME → prologue"
			get_tree().change_scene_to_file(PROLOGUE)
		"CONTINUE":
			if _latest.is_empty():
				_status = "NO SAVE · 无有效存档"
				return
			_enter_load(String(_latest.get("slot", "")))
		"LOAD":
			_overlay = "load"
			_refresh_slots()
			queue_redraw()
		"SETTINGS":
			_overlay = "settings"
			queue_redraw()
		"QUIT":
			_overlay = "quit"
			queue_redraw()


func _overlay_action(kind: String) -> void:
	if kind.begins_with("LOAD:"):
		_enter_load(kind.substr(5))
	elif kind == "QUIT_YES":
		get_tree().quit()
	elif kind == "CLOSE":
		_overlay = ""
		queue_redraw()


func _enter_load(slot: String) -> void:
	if _save == null or not _save.has_slot(slot):
		_status = "LOAD FAILED · NO SLOT " + slot
		return
	var md: Dictionary = _save.load_metadata(slot)
	if not bool(md.get("ok", false)):
		_status = "LOAD FAILED · " + String(md.get("reason", "corrupted"))
		return
	get_tree().root.set_meta("load_slot", slot)
	OS.set_environment("DSH_LOAD_SLOT", slot)
	_status = "LOAD " + slot + " → v1_hud"
	print("[MAIN MENU] LOAD slot=", slot, " → v1_hud.tscn")
	get_tree().change_scene_to_file(V1_HUD)


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("MAIN MENU SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()
