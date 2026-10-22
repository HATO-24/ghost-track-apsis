extends Control

# 方案B-21：V1 自绘主菜单。New/Continue/Load/Settings/Quit。
# 读档仅传 load_slot 给 ShellBinder；不伪造存档；不改剧情/物理。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")
const Painter := preload("res://scripts/ui/panel_painter.gd")
const SaveService := preload("res://scripts/core/save_service.gd")
const SettingsService := preload("res://scripts/core/settings_service.gd")
const BuildProfile := preload("res://scripts/core/build_profile.gd")

const VERSION := "V1.7"
const SAVE_ROOT := "user://saves"
const SLOTS := ["save", "menu", "quit", "autosave"]
const PROLOGUE := "res://prologue.tscn"
const V1_HUD := "res://v1_hud.tscn"

var _save = null
var _profile = null
var _save_root := "user://saves"
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
var _settings: Dictionary = {}
var _settings_rows: Array = []
var _settings_msg := ""
var _settings_source := "NOT READY"
var _emblem_tex: Texture2D = null
var _emblem_path := ""
var _settings_svc = null

const SETTINGS_PATH := "user://settings_v1.json"
const SETTINGS_DEFAULTS := {
	"language": "zh", "master": 0.8, "music": 0.6, "sfx": 0.7,
	"subtitles": true, "text_speed": 1.0, "timescale": 1.0,
	"display_mode": "WINDOWED", "ui_scale": 1.0,
}


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	# 版本剖面：作战模拟器版本跳过主菜单，直接进战术台（截图/显式禁用时除外）
	_profile = BuildProfile.new()
	_profile.setup({})
	_save_root = String(_profile.save_root)
	if _profile.is_sandbox() and _shot_path == "" \
			and OS.get_environment("DSH_NO_AUTOSKIP") != "1":
		var target := String(_profile.entry_scene)
		if target != "" and target != "res://main_menu.tscn":
			print("[MAIN MENU] BUILD=", String(_profile.id), " → skip to ", target)
			get_tree().change_scene_to_file(target)
			return
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
	_save = SaveService.new(_save_root)
	_refresh_slots()
	_load_settings()
	_load_emblem()
	var view := OS.get_environment("DSH_MAIN_MENU_VIEW")
	if view in ["load", "settings", "quit"]:
		_overlay = view
	if OS.get_environment("DSH_SETTINGS_TEST") == "1":
		call_deferred("_settings_test")
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


func _settings_test() -> void:
	if _settings_svc == null or not bool(_settings_svc.ready):
		print("[MAIN MENU] SETTINGS TEST NOT READY ", _settings_source)
		return
	_settings["master"] = 0.55
	_push_settings_to_service()
	var sr: Dictionary = _settings_svc.save()
	var ar: Dictionary = _settings_svc.apply_audio()
	print("[MAIN MENU] SETTINGS TEST ready=", _settings_svc.ready, " save=", str(sr.get("ok", false)), " path=", String(_settings_svc.path), " apply_audio=", str(ar.get("ok", false)), " master=", _settings_svc.get_setting("master_volume", null))
	_settings_msg = "TEST · SettingsService save=" + str(bool(sr.get("ok", false))) + " · " + String(_settings_svc.path)
	queue_redraw()


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
			sub = "语言 / 音量 / 字幕 / 显示"
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


func _load_settings() -> void:
	_settings = SETTINGS_DEFAULTS.duplicate(true)
	_settings_source = "SETTINGS SERVICE NOT READY"
	_settings_svc = SettingsService.new({"path": "user://settings.json"})
	if _settings_svc != null and bool(_settings_svc.ready):
		var raw: Dictionary = _settings_svc.settings
		_settings["language"] = str(raw.get("language", "zh"))
		_settings["master"] = float(raw.get("master_volume", 0.8))
		_settings["music"] = float(raw.get("music_volume", 0.7))
		_settings["sfx"] = float(raw.get("sfx_volume", 0.8))
		_settings["subtitles"] = bool(raw.get("subtitles", true))
		_settings["text_speed"] = float(raw.get("text_speed", 1.0))
		_settings["timescale"] = float(raw.get("default_time_scale", 1.0))
		_settings["display_mode"] = str(raw.get("display_mode", "windowed")).to_upper()
		_settings["ui_scale"] = float(raw.get("ui_scale", 1.0))
		_settings_source = "SettingsService READY · user://settings.json"
	else:
		_settings_source = "SETTINGS SERVICE NOT READY · " + (str(_settings_svc.last_error()) if _settings_svc != null else "missing")
		_settings_msg = _settings_source


func _push_settings_to_service() -> void:
	if _settings_svc == null or not bool(_settings_svc.ready):
		return
	_settings_svc.set_setting("language", str(_settings.get("language", "zh")))
	_settings_svc.set_setting("master_volume", clampf(float(_settings.get("master", 0.8)), 0.0, 1.0))
	_settings_svc.set_setting("music_volume", clampf(float(_settings.get("music", 0.6)), 0.0, 1.0))
	_settings_svc.set_setting("sfx_volume", clampf(float(_settings.get("sfx", 0.7)), 0.0, 1.0))
	_settings_svc.set_setting("subtitles", bool(_settings.get("subtitles", true)))
	_settings_svc.set_setting("text_speed", clampf(float(_settings.get("text_speed", 1.0)), 0.5, 2.0))
	var ts := int(_settings.get("timescale", 1.0))
	if not (ts in [1, 10, 60, 300]):
		ts = 1
	_settings_svc.set_setting("default_time_scale", ts)
	_settings_svc.set_setting("display_mode", String(_settings.get("display_mode", "WINDOWED")).to_lower())
	_settings_svc.set_setting("ui_scale", clampf(float(_settings.get("ui_scale", 1.0)), 0.8, 1.5))


func _save_settings() -> void:
	if _settings_svc == null or not bool(_settings_svc.ready):
		_settings_msg = "SAVE FAILED · SETTINGS SERVICE NOT READY"
		return
	_push_settings_to_service()
	var res: Dictionary = _settings_svc.save()
	_settings_msg = "SAVED · " + String(res.get("reason", _settings_svc.last_error())) if not bool(res.get("ok", false)) else "SAVED user://settings.json · SettingsService"
	if not bool(res.get("ok", false)):
		_settings_msg = "SAVE FAILED · " + String(res.get("reason", _settings_svc.last_error()))


func _settings_action(kind: String) -> void:
	if kind == "SAVE":
		_save_settings()
	elif kind == "APPLY":
		_push_settings_to_service()
		if _settings_svc != null and bool(_settings_svc.ready):
			_settings_svc.apply_audio()
			_settings_svc.apply_display()
		Engine.time_scale = clampf(float(_settings.get("timescale", 1.0)), 0.25, 300.0)
		_settings_msg = "APPLIED · SettingsService time_scale=" + str(Engine.time_scale)
	elif kind == "RESET":
		if _settings_svc != null and bool(_settings_svc.ready):
			_settings_svc.reset()
			_load_settings()
		else:
			_settings = SETTINGS_DEFAULTS.duplicate(true)
		_settings_msg = "RESET · defaults"
	elif kind == "CLOSE":
		_overlay = ""
		_settings_msg = ""
	queue_redraw()


func _settings_row_action(index: int, pos: Vector2) -> void:
	if index < 0 or index >= _settings_rows.size():
		return
	var row: Dictionary = _settings_rows[index]
	var kind := String(row.get("kind", ""))
	if kind in ["master", "music", "sfx"]:
		var tr: Rect2 = row.get("track", Rect2())
		var v := clampf((pos.x - tr.position.x) / maxf(1.0, tr.size.x), 0.0, 1.0)
		_settings[kind] = v
		_settings_msg = kind.to_upper() + " = " + ("%.0f%%" % (v * 100.0))
	elif kind == "language":
		var langs := ["zh", "ja", "en"]
		var cur := String(_settings.get("language", "zh"))
		_settings["language"] = langs[(langs.find(cur) + 1) % langs.size()]
		_settings_msg = "LANGUAGE → " + String(_settings["language"])
	elif kind == "subtitles":
		_settings["subtitles"] = not bool(_settings.get("subtitles", true))
		_settings_msg = "SUBTITLES → " + str(bool(_settings["subtitles"]))
	elif kind == "text_speed":
		var speeds := [0.75, 1.0, 1.25, 1.5]
		var cur2 := float(_settings.get("text_speed", 1.0))
		_settings["text_speed"] = speeds[(speeds.find(cur2) + 1) % speeds.size()]
		_settings_msg = "TEXT SPEED → " + str(_settings["text_speed"])
	elif kind == "timescale":
		var scales := [1.0, 10.0, 60.0, 300.0]
		var cur3 := float(_settings.get("timescale", 1.0))
		_settings["timescale"] = scales[(scales.find(cur3) + 1) % scales.size()]
		_settings_msg = "DEFAULT TIMESCALE → " + str(_settings["timescale"])
	elif kind == "display_mode":
		var modes := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
		var cur4 := String(_settings.get("display_mode", "WINDOWED"))
		_settings["display_mode"] = modes[(modes.find(cur4) + 1) % modes.size()]
		_settings_msg = "DISPLAY → " + String(_settings["display_mode"])
	elif kind == "ui_scale":
		var uis := [0.8, 1.0, 1.2, 1.5]
		var cur5 := float(_settings.get("ui_scale", 1.0))
		_settings["ui_scale"] = uis[(uis.find(cur5) + 1) % uis.size()]
		_settings_msg = "UI SCALE → " + str(_settings["ui_scale"])
	_push_settings_to_service()
	queue_redraw()


func _load_emblem() -> void:
	_emblem_tex = null
	_emblem_path = ""
	for path in ["res://assets/emblems/id13.png", "res://assets/emblems/ghost_track.png"]:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				_emblem_tex = res
				_emblem_path = path
				return


func _draw_emblem(r: Rect2) -> void:
	var c := r.position + r.size * 0.5
	var rad := minf(r.size.x, r.size.y) * 0.36
	if _emblem_tex != null:
		var side := minf(r.size.x, r.size.y)
		var ir := Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
		draw_texture_rect(_emblem_tex, ir, false)
		Painter.label(self, r.position.x, r.end.y + 12.0, "OCUVF / ID13", 10, P.PH, false)
		Painter.label(self, r.position.x, r.end.y + 26.0, "ASSET " + _emblem_path, 6, P.a(P.FAINT, 0.9), true)
		return
	# 无 assets/emblems 图片时程序化，不谎称图片资产。
	draw_circle(c, rad + 14.0, P.a(P.PH, 0.05))
	draw_arc(c, rad, 0.0, TAU, 72, P.a(P.PH_DIM, 0.55), 1.0, true)
	draw_arc(c, rad * 0.76, 0.0, TAU, 64, P.a(P.AMBER, 0.45), 1.0, true)
	var pts := PackedVector2Array([c + Vector2(0, -rad * 0.55), c + Vector2(rad * 0.42, 0), c + Vector2(0, rad * 0.55), c + Vector2(-rad * 0.42, 0)])
	draw_polyline(pts + PackedVector2Array([pts[0]]), P.a(P.PH, 0.75), 1.0)
	draw_line(c + Vector2(-rad * 0.55, 0), c + Vector2(rad * 0.55, 0), P.a(P.PH_DIM, 0.5), 1.0)
	draw_circle(c, 3.0, P.PH)
	Painter.label(self, r.position.x, r.end.y + 12.0, "OCUVF / ID13", 10, P.PH, false)
	Painter.label(self, r.position.x, r.end.y + 26.0, "NO PNG ASSET · PROCEDURAL FALLBACK", 6, P.a(P.FAINT, 0.9), true)


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
		Painter.label(self, x, y + 16, _settings_source, 7, P.a(P.AMBER, 0.9), true)
		_settings_rows.clear()
		var col_w2 := (r.size.x - 44.0 - 20.0) * 0.5
		var sx := x
		var sy := y + 42.0
		var row_h := 31.0
		var rows_def := [
			["language", "LANGUAGE", "语言"], ["master", "MASTER", "主音量"],
			["music", "MUSIC", "音乐"], ["sfx", "SFX", "音效"],
			["subtitles", "SUBTITLES", "字幕"],
			["text_speed", "TEXT SPEED", "文本速度"], ["timescale", "DEFAULT TIMESCALE", "默认时标"],
			["display_mode", "DISPLAY MODE", "显示模式"], ["ui_scale", "UI SCALE", "界面缩放"],
		]
		for i in range(rows_def.size()):
			var col := 0 if i < 5 else 1
			var ri := i if i < 5 else i - 5
			var row: Array = rows_def[i]
			var kind := str(row[0])
			var rx2 := sx + float(col) * (col_w2 + 20.0)
			var ry2 := sy + float(ri) * row_h
			var rr := Rect2(rx2, ry2, col_w2, row_h - 4.0)
			var track := Rect2(rx2 + 160.0, ry2 + 11.0, col_w2 - 180.0, 8.0)
			_settings_rows.append({"rect": rr, "kind": kind, "track": track})
			draw_rect(rr, P.a(P.PANEL2, 0.25))
			Painter.label(self, rr.position.x + 6, rr.position.y + 17, str(row[1]) + " / " + str(row[2]), 9, P.TXT, false)
			var v: Variant = _settings.get(kind)
			if kind in ["master", "music", "sfx"]:
				draw_rect(track, P.a(P.LINE, 0.9))
				draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(float(v), 0.0, 1.0), track.size.y)), P.a(P.PH, 0.85))
				Painter.label(self, track.end.x + 8, rr.position.y + 17, "%.0f%%" % (float(v) * 100.0), 8, P.PH_DIM, true)
			else:
				var val := ""
				if kind == "language":
					val = {"zh": "中文", "ja": "日本語", "en": "English"}.get(str(v), str(v))
				elif kind == "subtitles":
					val = "ON" if bool(v) else "OFF"
				else:
					val = str(v)
				Painter.label(self, rr.end.x - 8 - TM.width(val, true, 9), rr.position.y + 17, val, 9, P.PH if kind != "display_mode" else P.AMBER, true)
		var by2 := r.end.y - 38.0
		var labels2 := [["SAVE", "SAVE"], ["APPLY", "APPLY"], ["RESET", "RESET"], ["CLOSE", "CLOSE"]]
		for i in range(labels2.size()):
			var bw2 := (r.size.x - 44.0 - 8.0 * 3.0) / 4.0
			var br2 := Rect2(x + float(i) * (bw2 + 8.0), by2, bw2, 26)
			_overlay_buttons.append({"rect": br2, "kind": String(labels2[i][0])})
			Painter.button(self, br2, String(labels2[i][1]), true, P.PH)
		if _settings_msg != "":
			Painter.label(self, x, by2 - 14.0, TM.fit(_settings_msg, r.size.x - 44.0, true, 8), 8, P.AMBER, true)
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
		if _overlay == "settings":
			for i in range(_settings_rows.size()):
				var row: Dictionary = _settings_rows[i]
				if (row["rect"] as Rect2).has_point(pos):
					_settings_row_action(i, pos)
					accept_event()
					return
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
	elif kind in ["SAVE", "APPLY", "RESET"]:
		_settings_action(kind)
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
