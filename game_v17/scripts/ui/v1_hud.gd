extends Control

# 方案B 自绘 V1 HUD 样张：统一 LayoutTokens/TextMetrics/PanelPainter。
# 独立 v1_hud.tscn；不改旧 HUD/Control 壳；数据无 GameSession 时明确 DEMO。
# 不实现 IME/剧情/物理/存档。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")
const Painter := preload("res://scripts/ui/panel_painter.gd")
const ShellBinder := preload("res://scripts/ui/shell_binder.gd")
const DamageModel := preload("res://framework/core/damage_model.gd")
const CombatService := preload("res://scripts/core/combat_service.gd")

const SCENARIO := "res://framework/content/scenario_transit_l4_l1.json"
const TRANSFER := "res://framework/content/transfer_l4_l1_cached.json"

var tok = null
var _contacts: Array = []
var _selected := 0
var _page := "ship"
var _collapsed := false
var _t := 0.0
var _timers := [
	{"label": "BURN WINDOW", "remain": 30.0, "total": 30.0},
	{"label": "ARRIVAL", "remain": 120.0, "total": 120.0},
	{"label": "LINK", "remain": 15.0, "total": 15.0},
]
var _top_dots: Array = []
var _contact_rects: Array = []
var _tabs: Array = []
var _frames := 0
var _shot_path := ""
var _target_size := Vector2i(1920, 1080)
var _commander := "指挥官 · 沧澜"
var _delta_v := 0.0
var _transfer_ok := false
var binder = null
var _save_msg := ""
var _save_ok := true
var _sensor_msg := ""
var _right_buttons: Array = []
var _damage = null
var _combat = null
var _overlay := ""
var _overlay_close := Rect2()
var _damage_rows: Array = []
var _damage_buttons: Array = []
var _selected_section := ""
var _damage_msg := ""
var _roe_buttons: Array = []
var _roe_msg := ""
var _roe_locked := true
var _command_rows: Array = []
var _command_buttons: Array = []
var _selected_cmd := -1
var _command_msg := ""
var _comms_type := "HOLD"
var _comms_target := ""
var _comms_msg := ""
var _comms_type_buttons: Array = []
var _comms_send_rect := Rect2()
var _comms_cmd_rows: Array = []
var _comms_cmd_buttons: Array = []
var _optical_target := ""
var _optical_track: Dictionary = {}
var _optical_msg := ""
var _optical_buttons: Array = []
var _combat_target := ""
var _combat_weapon := ""
var _combat_msg := ""
var _combat_target_rows: Array = []
var _combat_weapon_rows: Array = []
var _combat_buttons: Array = []
var _combat_roe_buttons: Array = []


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
	tok = Tokens.new()
	_commander = OS.get_environment("DSH_PLAYER_NAME")
	if _commander == "":
		_commander = String(get_tree().root.get_meta("player_name", "沧澜"))
	if _commander == "":
		_commander = "沧澜"
	if _commander.begins_with("指挥官"):
		pass
	else:
		_commander = "指挥官 · " + _commander
	_load_data()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	if _shot_path != "":
		get_window().size = _target_size
		Input.warp_mouse(Vector2(_target_size) * 0.5)
	if OS.get_environment("DSH_FLOW_SMOKE") == "1":
		call_deferred("_flow_smoke_v1")
	if OS.get_environment("DSH_V1_SAVE_TEST") == "1":
		call_deferred("_run_save_test")
	if OS.get_environment("DSH_V1_TEST") == "1":
		call_deferred("_run_interaction_test")


func _load_data() -> void:
	binder = ShellBinder.new()
	var flow: Dictionary = {}
	var root := get_tree().root
	if root.has_meta("flow_state") and root.get_meta("flow_state") is Dictionary:
		flow = (root.get_meta("flow_state") as Dictionary).duplicate(true)
	var pname := String(flow.get("player_name", ""))
	if pname == "":
		pname = OS.get_environment("DSH_PLAYER_NAME")
	if pname == "":
		pname = _commander.trim_prefix("指挥官 · ")
	if pname == "":
		pname = "沧澜"
	binder.commander = "指挥官 · " + pname
	var ok: bool = binder.boot()
	print("[V1 HUD] binder boot=", str(ok), " errors=", str(binder.errors), " contacts=", binder.contacts.size(), " orders=", binder.commands.size())
	_contacts = binder.contacts.duplicate(true) if binder.contacts is Array else []
	if _contacts.is_empty():
		# 无 session 时保留明确 fallback 样张；不让页面空/假实时。
		_contacts = [{"id": "----", "name": "NO SESSION / NO TRACK", "cls": "NOT READY", "type": "unknown",
			"badge": "NOT READY", "threat": "unknown", "demo": true}]
	_normalize_contacts()
	_selected = 0
	for i in range(_contacts.size()):
		if String((_contacts[i] as Dictionary).get("id", "")) == "1000":
			_selected = i
			break
	if _contacts.size() > 0:
		_comms_target = String((_contacts[_selected] as Dictionary).get("entity_id", (_contacts[_selected] as Dictionary).get("id", "")))
	if FileAccess.file_exists(TRANSFER):
		var d = JSON.parse_string(FileAccess.get_file_as_string(TRANSFER))
		if d is Dictionary:
			var budget: Dictionary = d.get("budget", {}) if d.get("budget", {}) is Dictionary else {}
			_delta_v = float(budget.get("total_dv_mps", 0.0))
			_transfer_ok = _delta_v > 0.0
	if not bool(binder.delta_v_ready):
		_delta_v = 0.0
		_transfer_ok = false
	else:
		_delta_v = float(binder.delta_v_mps)
		_transfer_ok = true
	binder.seed_timers()
	_selected_cmd = 0 if binder != null and binder.commands.size() > 0 else -1
	if binder != null and binder.contacts.size() > 0:
		_comms_target = String((_contacts[_selected] as Dictionary).get("entity_id", (_contacts[_selected] as Dictionary).get("id", "")))
	_seed_comms_sample()
	_seed_combat_tracks()
	# CombatService（ROE 四档）与 DamageModel（损管页）为会话外挂的 shadow 组件；
	# GameSession 当前未内置 damage_vm；损管明确标注 MODEL，不伪造。
	_combat = CombatService.new({})
	if _combat != null and bool(_combat.ready) and binder.session != null:
		binder.session.combat_service = _combat
		_combat.t = float(binder.session.now_s())
	_roe_locked = String(binder.story_vm.get("phase", "prelude")) == "prelude"
	if OS.get_environment("DSH_V1_ROE_UNLOCK") == "1":
		_roe_locked = false
	_damage = DamageModel.new()
	var dok: bool = _damage.setup({}, "apsis")
	print("[V1 HUD] damage_model=", str(dok), " sections=", _damage.section_ids().size(), " combat=", str(_combat.ready), " roe=", String(_combat.roe) if _combat != null else "—", " roe_locked=", str(_roe_locked))
	var view := OS.get_environment("DSH_V1_VIEW")
	if view == "combat":
		_overlay = "combat"
		_seed_combat_tracks()
	elif view == "damage":
		_overlay = "damage"
		if _damage != null and _damage.ready:
			var ids: Array = _damage.section_ids()
			if not ids.is_empty():
				_selected_section = String(ids[0])
	elif view == "roe":
		_overlay = "roe"
	elif view == "comms":
		_overlay = "comms"
	elif view == "optical":
		_overlay = "optical"
		# 光学页目标=当前选中实体（默认旗舰1000），不自动跳到哈马丹。
		if _selected >= 0 and _selected < _contacts.size():
			var picked: Dictionary = _contacts[_selected]
			_optical_target = String(picked.get("entity_id", picked.get("id", "")))
			_optical_track = binder.selected_track(picked) if binder != null else {}
		else:
			_optical_target = ""
			_optical_track = {}

func _seed_comms_sample() -> void:
	# 通过真实 session.send_comms 生成消息流；from/to 来自 session 实体，不硬编码舰名。
	if binder == null or binder.session == null or binder.session.comms == null:
		return
	var vm: Dictionary = binder.session.comms.vm()
	if (vm.get("events", []) as Array).size() > 0:
		return
	var ids: Array = []
	for raw in binder.contacts:
		if raw is Dictionary:
			var eid := String((raw as Dictionary).get("entity_id", ""))
			if eid != "" and not (eid in ids):
				ids.append(eid)
	if ids.size() < 2:
		return
	var res1: Dictionary = binder.session.send_comms(String(ids[0]), String(ids[1]), "LD", "COMMS_SENT", {}, {})
	var res2: Dictionary = binder.session.send_comms(String(ids[0]), String(ids[1] if ids.size() > 1 else ids[0]), "LR", "COMMS_SENT", {}, {})
	print("[V1 HUD] COMMS seed LD=", str(bool(res1.get("ok", false))), " LR=", str(bool(res2.get("ok", false))), " events=", (binder.session.comms.vm().get("events", []) as Array).size())


func _normalize_contacts() -> void:
	for i in range(_contacts.size()):
		var c: Dictionary = _contacts[i]
		if String(c.get("entity_id", "")) == "apsis" or String(c.get("id", "")) == "apsis":
			c["id"] = "1000"
			c["badge"] = "FLAG"
			_contacts[i] = c
	# 旗舰 1000 固定第一；其余保持原顺序（友军/中立/未知规则不变）。
	var flag: Dictionary = {}
	var rest: Array = []
	for raw in _contacts:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "1000":
			flag = raw
		else:
			rest.append(raw)
	_contacts = ([flag] + rest) if not flag.is_empty() else rest
	_selected = clampi(_selected, 0, maxi(0, _contacts.size() - 1))
	if _contacts.size() > 0:
		_comms_target = String((_contacts[_selected] as Dictionary).get("entity_id", (_contacts[_selected] as Dictionary).get("id", "")))


func _select_preserving(preferred_id := "") -> void:
	var old_id := preferred_id
	if old_id == "" and _selected >= 0 and _selected < _contacts.size():
		old_id = String((_contacts[_selected] as Dictionary).get("id", ""))
	_normalize_contacts()
	_selected = 0
	if old_id != "":
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("id", "")) == old_id:
				_selected = i
				break
	if String((_contacts[_selected] as Dictionary).get("id", "")) != "":
		_comms_target = String((_contacts[_selected] as Dictionary).get("entity_id", (_contacts[_selected] as Dictionary).get("id", "")))




func _process(delta: float) -> void:
	_t += delta
	if binder != null:
		binder.tick(delta)
		_timers = binder.timers() if binder.timers() is Array else []
		if _frames % 10 == 0:
			var old_sel := ""
			if _selected >= 0 and _selected < _contacts.size():
				old_sel = String((_contacts[_selected] as Dictionary).get("id", ""))
			binder.refresh()
			_contacts = binder.contacts.duplicate(true) if binder.contacts is Array else _contacts
			_select_preserving(old_sel)
	queue_redraw()
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("V1 HUD SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _type_col(t: Dictionary) -> Color:
	match String(t.get("type", "")):
		"friendly":
			return P.PH_DIM
		"station":
			return P.FAINT
		"unknown":
			return P.AMBER
		"neutral":
			return P.BLUE
		_:
			return P.DIM


func _draw() -> void:
	var l: Dictionary = tok.layout(size.x, size.y)
	var top: Rect2 = l.top
	var left: Rect2 = l.left
	var center: Rect2 = l.center
	var right: Rect2 = l.right
	var bottom: Rect2 = l.bottom
	draw_rect(Rect2(Vector2.ZERO, size), P.BG)
	# 顶栏
	Painter.panel(self, top, "", P.PH)
	Painter.label(self, top.position.x + 14, top.position.y + 22, "GHOST TRACK // APSIS", 11, P.PH, true)
	Painter.label(self, top.position.x + 14, top.position.y + 43, _commander, 15, P.PH)
	var live := binder != null and bool(binder.ready)
	var now_s := float(binder.session.now_s()) if binder != null and binder.session != null else _t
	Painter.label(self, top.position.x + 14, top.position.y + 58, "MISSION T+%s · L1 港内 %s · %s" % [_clock(now_s), _clock(6 * 3600 + 42 * 60 + 17), "SESSION LIVE" if live else "FALLBACK DEMO"], 7, P.a(P.DIM, 0.95), true)
	var tx := top.position.x + 300.0
	Painter.label(self, tx, top.position.y + 20, "动态计时 / TIMERS", 7, P.a(P.FAINT, 0.95), false)
	for i in range(_timers.size()):
		var timer: Dictionary = _timers[i]
		var remain := float(timer.get("remain", 0.0))
		var total := maxf(1.0, float(timer.get("total", 1.0)))
		var col := P.AMBER if i == 0 else (P.BLUE if i == 1 else P.PH)
		var y := top.position.y + 36.0 + float(i) * 11.0
		Painter.label(self, tx, y, "%s %s" % [String(timer.get("label", "")), _clock(remain)], 6, col, true)
		draw_rect(Rect2(tx + 160, y - 6, 76, 3), P.a(P.LINE, 0.9))
		draw_rect(Rect2(tx + 160, y - 6, 76.0 * clampf(remain / total, 0.0, 1.0), 3), P.a(col, 0.9))
	# 右侧槽
	var rx := top.end.x - 150.0
	Painter.label(self, rx, top.position.y + 20, "链路 / 时标 / Δv / ROE", 7, P.a(P.PH, 0.75), false)
	Painter.label(self, rx, top.position.y + 35, "LINK OK · 無線電 8s", 6, P.TXT, true)
	Painter.label(self, rx, top.position.y + 48, "×1 · Δv %s" % ("%.1f m/s" % _delta_v if _transfer_ok else "NOT READY"), 6, P.a(P.DIM, 0.95), true)
	Painter.label(self, rx, top.position.y + 60, TM.fit(String(binder.roe_text) if binder != null else "ROE NOT READY", 180, true, 6), 6, P.a(P.DIM, 0.95), true)
	# 三色点
	_top_dots.clear()
	for i in range(3):
		var dp := Vector2(top.end.x - 22.0 - float(i) * 20.0, top.position.y + 15.0)
		var cols := [Color("#6DE6A2"), Color("#E8C24B"), Color("#E2564A")]
		draw_circle(dp, 6.0, P.a(cols[i], 0.2))
		draw_circle(dp, 3.5, P.a(cols[i], 0.95))
		_top_dots.append({"rect": Rect2(dp - Vector2(10, 10), Vector2(20, 20)), "kind": ["save", "menu", "quit"][i]})
	if _save_msg != "":
		Painter.label(self, top.position.x + 300, top.position.y + 66, TM.fit(_save_msg, 520, true, 6), 6, P.PH if _save_ok else P.RED, true)
	# 左接触
	Painter.panel(self, left, "接触 / CONTACTS", P.PH)
	var ly := left.position.y + 34.0
	Painter.label(self, left.position.x + 12, ly, "友军 / FRIENDLY", 7, P.a(P.PH_DIM, 0.95))
	Painter.label(self, left.end.x - 12, ly, ("▸" if _collapsed else "▾") + "  %02d" % _contacts.size(), 7, P.PH, true)
	PersonPainterDivider(left, ly + 5.0)
	_contact_rects.clear()
	if not _collapsed:
		var row_y := ly + 16.0
		for i in range(_contacts.size()):
			var c: Dictionary = _contacts[i]
			var rh := 42.0 if String(c.get("type", "")) == "unknown" else 48.0
			if row_y + rh > left.end.y - 40.0:
				break
			var tr := Rect2(left.position.x + 8, row_y, left.size.x - 16, rh)
			_contact_rects.append({"rect": tr, "index": i})
			Painter.list_row(self, tr, "[%s] %s" % [String(c.get("id", "")), String(c.get("name", ""))], String(c.get("badge", "")), _type_col(c), i == _selected)
			Painter.label(self, tr.position.x + 8, tr.position.y + 31, String(c.get("cls", "")), 6, P.a(P.FAINT, 0.95), true)
			row_y += rh + 4.0
	# 中图
	Painter.panel(self, center, "战术图 / TACTICAL PLOT", P.PH)
	_draw_map(center)
	# 右栏
	Painter.panel(self, right, "", P.PH)
	_draw_right(right)
	# 底部
	Painter.panel(self, bottom, "", P.PH)
	_draw_bottom(bottom)
	if _overlay != "":
		_draw_overlay(l)


func PersonPainterDivider(r: Rect2, y: float) -> void:
	draw_line(Vector2(r.position.x + 10, y), Vector2(r.end.x - 10, y), P.a(P.LINE, 0.8), 1.0)


func _draw_map(r: Rect2) -> void:
	var area := Rect2(r.position.x + 12, r.position.y + 34, r.size.x - 24, r.size.y - 46)
	draw_rect(area, P.a(P.EARTH, 0.55))
	draw_rect(area, P.a(P.LINE, 0.6), false, 1.0)
	for i in range(180):
		var hh := (i * 1103515245 + 12345) & 0x7fffffff
		draw_rect(Rect2(area.position.x + 8 + float(hh % int(maxf(1.0, area.size.x - 16))),
			area.position.y + 8 + float((hh / 97) % int(maxf(1.0, area.size.y - 80))), 1, 1), P.a(P.TXT, 0.08))
	var p0 := Vector2(area.position.x + area.size.x * 0.26, area.position.y + area.size.y * 0.28)
	var p1 := Vector2(area.position.x + area.size.x * 0.72, area.position.y + area.size.y * 0.62)
	draw_arc(p0, 90, 0, TAU, 64, P.a(P.PH_DIM, 0.2), 1.0, true)
	draw_line(p0, p1, P.a(P.AMBER, 0.8), 1.0)
	draw_circle(p0, 3.0, P.AMBER)
	draw_circle(p1, 3.0, P.PH)
	Painter.label(self, p0.x - 20, p0.y - 12, "L4-02 HAMMER", 7, P.AMBER, true)
	Painter.label(self, p1.x + 6, p1.y + 16, "L1 MERIDIAN", 7, P.PH, true)
	for i in range(5):
		var q := p0.lerp(p1, 0.18 + float(i) * 0.04) + Vector2(float(i - 2) * 6.0, float(i - 2) * 4.0)
		draw_circle(q, 2.0, P.PH_DIM)
	var ty := area.end.y - 34.0
	draw_line(Vector2(area.position.x + 12, ty), Vector2(area.end.x - 12, ty), P.a(P.LINE2, 0.7), 1.0)
	draw_line(Vector2(area.position.x + 12 + area.size.x * 0.42, ty - 7), Vector2(area.position.x + 12 + area.size.x * 0.42, ty + 7), P.a(P.AMBER, 0.85), 1.0)
	Painter.label(self, area.position.x + 12, ty - 12, "T+00:00 · TOF 144:00:00 · WINDOW OPEN 18:00 / CLOSE 24:00", 7, P.TXT, true)
	Painter.label(self, area.position.x + 12, area.end.y - 14, ("SESSION LIVE · TRACK/SENSOR/STORY" if binder != null and bool(binder.ready) else "FALLBACK DEMO · TOKEN LAYOUT") + " · V1 PALETTE", 6, P.a(P.FAINT, 0.9), true)


func _draw_right(r: Rect2) -> void:
	var x := r.position.x + 12.0
	var right := r.end.x - 12.0
	var y := r.position.y + 34.0
	var c: Dictionary = _contacts[_selected] if _selected >= 0 and _selected < _contacts.size() else {}
	var fields: Dictionary = binder.ship_fields(c, _page) if binder != null else {"title": "NOT READY", "source": "NO SESSION", "lines": []}
	_tabs = [{"rect": Rect2(x, r.position.y + 4, 70, 18), "page": "ship"}, {"rect": Rect2(x + 76, r.position.y + 4, 76, 18), "page": "target"}]
	for tab in _tabs:
		var active := String(tab.get("page", "")) == _page
		var tr: Rect2 = tab["rect"]
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.10 if active else 0.04))
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.65 if active else 0.25), false, 1.0)
		Painter.label(self, tr.position.x + 6, tr.position.y + 13, "SHIP" if String(tab.get("page", "")) == "ship" else "TARGET", 7, P.PH if active else P.FAINT, true)
	Painter.label(self, right - TM.width(String(fields.get("source", "")), true, 6), r.position.y + 14, String(fields.get("source", "NOT READY")), 6, P.a(P.AMBER, 0.9), true)
	Painter.label(self, x, y + 8, TM.fit(String(fields.get("title", "NOT READY")), r.size.x - 24, false, 12), 12, P.TXT)
	Painter.label(self, x, y + 22, "LIVE DATABASE FIELD · SESSION/TRACK", 7, P.PH_DIM, true)
	y += 38.0
	for raw in (fields.get("lines", []) as Array):
		var line := String(raw)
		var col := P.TXT
		if line.begins_with("DAMAGE") or line.begins_with("SENSOR NOT"):
			col = P.AMBER
		Painter.label(self, x, y, TM.fit(line, r.size.x - 24, true, 7), 7, col, true)
		y += 13.0
	y += 5.0
	Painter.section(self, x, y, right, "SENSOR / 传感器")
	y += 14.0
	var ss: Dictionary = binder.sensor_state() if binder != null else {"ready": false, "text": "SENSOR NOT READY"}
	if bool(ss.get("ready", false)):
		Painter.label(self, x, y, "RADAR %s · EMCON %s · OBS %d" % ["ON" if bool(ss.get("radar", false)) else "OFF", str(bool(ss.get("emcon", false))), int(ss.get("obs", 0))], 7, P.TXT, true)
		y += 12.0
		Painter.label(self, x, y, "IFF EVID %d · OPTICAL %d · CH %d" % [int(ss.get("iff", 0)), int(ss.get("optical", 0)), int(ss.get("channels", 0))], 7, P.a(P.DIM, 0.9), true)
	else:
		Painter.label(self, x, y, "SENSOR NOT READY · 无 sensor_service", 7, P.AMBER, true)
	y += 18.0
	Painter.section(self, x, y, right, "ROE / Δv")
	y += 14.0
	Painter.key_value(self, x, y, right, "ROE", TM.fit(String(binder.roe_text) if binder != null else "ROE NOT READY", 190, true, 7), P.AMBER)
	y += 12.0
	Painter.key_value(self, x, y, right, "Δv", "%.1f m/s" % _delta_v if _transfer_ok else "NOT READY", P.TXT)
	y += 20.0
	Painter.section(self, x, y, right, "SENSOR CONTROLS / 只读最小交互")
	y += 10.0
	_right_buttons.clear()
	var labels := [["DAMAGE", "DAMAGE / 损管"], ["ROE", "ROE / 四档"], ["COMMS", "COMMS / 命令"], ["COMBAT", "COMBAT / 战斗"], ["NAV", "NAV / 导航"], ["OPTICAL", "OPTICAL / 光学"], ["INFO", "INFO / 信息"]]
	for i in range(labels.size()):
		var bw := (r.size.x - 32.0) * 0.5 - 4.0
		var col := i % 2
		var br := Rect2(x + float(col) * (bw + 8.0), y + float(i / 2) * 26.0, bw, 21.0)
		_right_buttons.append({"rect": br, "kind": String(labels[i][0])})
		Painter.button(self, br, String(labels[i][1]), true, P.PH)
	if _sensor_msg != "":
		Painter.label(self, x, y + 83, TM.fit(_sensor_msg, r.size.x - 24, true, 7), 7, P.AMBER, true)
	Painter.label(self, x, r.end.y - 14, "LIVE SESSION · 最小交互 · 自绘 V1", 6, P.a(P.FAINT, 0.9), true)

func _draw_bottom(r: Rect2) -> void:
	var split := r.position.x + floorf(r.size.x * 0.56)
	var y := r.position.y + 40.0
	var live := binder != null and bool(binder.ready)
	Painter.label(self, r.position.x + 12, r.position.y + 20, "命令队列 / COMMAND QUEUE · " + ("GAME SESSION" if live else "FALLBACK DEMO"), 8, P.PH, false)
	Painter.label(self, split + 12, r.position.y + 20, "事件日志 / EVENT LOG · " + ("SESSION BUS" if live else "FALLBACK DEMO"), 8, P.PH, false)
	Painter.divider(self, r.position.x + 10, r.position.y + 26, r.end.x - 10)
	draw_line(Vector2(split, r.position.y + 10), Vector2(split, r.end.y - 10), P.a(P.LINE, 0.8), 1.0)
	var cmds: Array = binder.commands if binder != null else []
	_command_rows.clear()
	_command_buttons.clear()
	if cmds.is_empty():
		Painter.label(self, r.position.x + 12, y, "NO COMMAND DATA · NOT READY", 7, P.FAINT, true)
	else:
		for i in range(mini(3, cmds.size())):
			var c: Dictionary = cmds[i]
			var state := String(c.get("state", "—"))
			var col := P.PH if state in ["EXECUTING", "DONE", "TRANSMITTED"] else (P.AMBER if state in ["QUEUED", "ISSUED"] else P.DIM)
			var rr := Rect2(r.position.x + 8, y + float(i) * 14.0 - 9, split - r.position.x - 16, 13)
			_command_rows.append({"rect": rr, "index": i})
			if i == _selected_cmd:
				draw_rect(rr, P.a(P.PH, 0.10))
			Painter.label(self, r.position.x + 12, y + float(i) * 14.0, "%s %s · %s → %s · %s · %s" % [
				String(c.get("id", "")), state, String(c.get("actor", "")), String(c.get("target", "")),
				String(c.get("action", "")), String(c.get("delay", ""))], 7, col, true)
		if _selected_cmd >= 0 and _selected_cmd < cmds.size():
			var sc: Dictionary = cmds[_selected_cmd]
			Painter.label(self, r.position.x + 12, y + 34.0, "DETAIL %s · %s → %s · %s · mode %s · delay %s · %s" % [
				String(sc.get("id", "")), String(sc.get("actor", "")), String(sc.get("target", "")),
				String(sc.get("action", "")), String(sc.get("mode", "")), String(sc.get("delay", "")), String(sc.get("state", ""))], 6, P.a(P.PH_DIM, 0.95), true)
		var b1 := Rect2(r.position.x + 12, r.end.y - 26, 84, 18)
		var b2 := Rect2(r.position.x + 102, r.end.y - 26, 84, 18)
		_command_buttons.append({"rect": b1, "kind": "ABORT"})
		_command_buttons.append({"rect": b2, "kind": "REVOKE"})
		Painter.button(self, b1, "ABORT", _selected_cmd >= 0, P.AMBER)
		Painter.button(self, b2, "REVOKE", _selected_cmd >= 0, P.RED)
		if _command_msg != "":
			Painter.label(self, r.position.x + 196, r.end.y - 12, TM.fit(_command_msg, split - r.position.x - 210, true, 6), 6, P.AMBER, true)
	var events: Array = binder.events if binder != null else []
	if events.is_empty():
		Painter.label(self, split + 12, y, "NO EVENT DATA · NOT READY", 7, P.FAINT, true)
	else:
		for i in range(mini(4, events.size())):
			var e: Dictionary = events[i]
			var payload: Dictionary = e.get("payload", {}) if e.get("payload", {}) is Dictionary else {}
			var text := String(payload.get("label", ""))
			if text == "":
				text = String(e.get("type", ""))
			Painter.label(self, split + 12, y + float(i) * 14.0, "%5.1fs  %s" % [float(e.get("t", 0.0)), String(e.get("type", "—"))], 7, P.PH_DIM if i == 0 else P.DIM, true)
			Painter.label(self, split + 154, y + float(i) * 14.0, TM.fit(text, r.size.x - (split - r.position.x) - 180, false, 7), 7, P.TXT, false)
	Painter.label(self, r.position.x + 12, r.end.y - 8, ("GAME SESSION · TRACK/SENSOR/STORY · 自绘 V1 HUD" if live else "FALLBACK DEMO · 无 session") + " · 三色点保存", 6, P.a(P.AMBER if not live else P.FAINT, 0.85), true)

func _run_interaction_test() -> void:
	# 仅 headless 验证真实 API；不改变正常手动流程。
	_do_right_action("DAMAGE")
	if _damage != null and _damage.ready:
		var ids: Array = _damage.section_ids()
		if not ids.is_empty():
			_selected_section = String(ids[0])
			_damage_action("FIX")
			_damage_action("PRI")
			_damage_action("CANCEL")
	_do_right_action("ROE")
	_roe_locked = false
	_roe_action("HOLD")
	_selected_cmd = 0
	_command_action("REVOKE")
	_do_right_action("COMMS")
	_comms_send()
	_do_right_action("OPTICAL")
	for i in range(_contacts.size()):
		if String((_contacts[i] as Dictionary).get("track_id", "")) != "":
			_selected = i
			_optical_target = String((_contacts[i] as Dictionary).get("entity_id", (_contacts[i] as Dictionary).get("id", "")))
			_optical_track = binder.selected_track(_contacts[i]) if binder != null else {}
			break
	_optical_action("VIS")
	_optical_action("IR")
	_optical_action("IFF")
	_optical_action("ELINT")
	_optical_action("LIGHT")
	_do_right_action("COMBAT")
	_seed_combat_tracks()
	_combat_action("TRACK")
	_combat_action("SOLUTION")
	_combat_action("AUTHORIZE FIRE")
	_combat_action("FIRE")
	print("[V1 HUD] INTERACTION TEST damage=", _damage_msg, " roe=", _roe_msg, " command=", _command_msg, " comms=", _comms_msg, " optical=", _optical_msg, " combat=", _combat_msg)


func _run_save_test() -> void:
	_do_save("save")
	var meta: Dictionary = binder.save_service.load_metadata("save") if binder != null and binder.save_service != null else {}
	print("[V1 HUD] SAVE TEST metadata=", str(bool(meta.get("ok", false))), " slot=", String((meta.get("meta", {}) as Dictionary).get("slot", "")))


func _flow_smoke_v1() -> void:
	print("[V1 HUD] FLOW SMOKE COMPLETE name=", _commander, " contacts=", _contacts.size(), " commands=", binder.commands.size() if binder != null else 0)
	get_tree().quit()


func _draw_overlay(l: Dictionary) -> void:
	var center: Rect2 = l.center
	var right: Rect2 = l.right
	var r := Rect2(center.position.x, center.position.y, right.end.x - center.position.x, center.size.y)
	if _overlay == "comms":
		r.size.y = minf(r.size.y, 600.0)
		r.position.y = center.position.y + 20.0
	if _overlay == "optical":
		r.size.y = minf(r.size.y, 600.0)
		r.position.y = center.position.y + 12.0
	draw_rect(r, P.a(P.PANEL, 0.985))
	draw_rect(r, P.a(P.PH, 0.7), false, 1.0)
	_overlay_close = Rect2(r.end.x - 96, r.position.y + 8, 84, 20)
	Painter.button(self, _overlay_close, "关闭 / CLOSE", true, P.RED)
	if _overlay == "damage":
		_draw_damage_overlay(r)
	elif _overlay == "roe":
		_draw_roe_overlay(r)
	elif _overlay == "comms":
		_draw_comms_overlay(r)
	elif _overlay == "optical":
		_draw_optical_overlay(r)
	elif _overlay == "combat":
		_draw_combat_overlay(r)


func _draw_comms_overlay(r: Rect2) -> void:
	var gap := 12.0
	var left_w := floorf((r.size.x - 28.0 - gap) * 0.58)
	var right_w := r.size.x - 28.0 - gap - left_w
	var lp := Rect2(r.position.x + 14.0, r.position.y + 14.0, left_w, r.size.y - 28.0)
	var rp := Rect2(lp.end.x + gap, lp.position.y, right_w, lp.size.y)
	# 独立双栏面板边框
	draw_rect(lp, P.a(P.PANEL2, 0.42))
	draw_rect(lp, P.a(P.LINE2, 0.65), false, 1.0)
	draw_rect(rp, P.a(P.PANEL2, 0.42))
	draw_rect(rp, P.a(P.LINE2, 0.65), false, 1.0)
	Painter.label(self, lp.position.x + 10, lp.position.y + 20, "通信 / COMMS · 双栏", 11, P.PH)
	Painter.label(self, rp.position.x + 10, rp.position.y + 20, "命令 / ORDERS · 双栏", 11, P.PH)
	var vm: Dictionary = binder.session.comms.vm() if binder != null and binder.session != null and binder.session.comms != null else {}
	var events: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	var links: Array = vm.get("links", []) if vm.get("links", []) is Array else []
	# 左栏 CHANNELS 表
	var cy := lp.position.y + 38.0
	Painter.section(self, lp.position.x + 10, cy, lp.end.x - 10, "CHANNELS / 频道")
	cy += 15.0
	Painter.label(self, lp.position.x + 10, cy, "MODE     STATUS     LATENCY   EVENTS", 6, P.a(P.FAINT, 0.9), true)
	cy += 12.0
	var modes := ["LD", "LR", "RDO", "IR", "VIS"]
	for i in range(modes.size()):
		var mode := String(modes[i])
		var st := "OPEN"
		var lat := "—"
		for raw in links:
			if raw is Dictionary and String((raw as Dictionary).get("mode", "")) == mode:
				var link: Dictionary = raw
				if bool(link.get("disabled", false)):
					st = "CLOSED"
				elif bool(link.get("occluded", false)):
					st = "OCCLUDED"
				elif float(link.get("jam", 0.0)) >= 0.7:
					st = "JAMMED"
				lat = "%.1fs" % float(link.get("latency_s", link.get("latency", 0.0)))
				break
		var n_ev := 0
		for raw2 in events:
			if raw2 is Dictionary and String((raw2 as Dictionary).get("mode", "")) == mode:
				n_ev += 1
		var y := cy + float(i) * 17.0
		var col := P.PH if st == "OPEN" else (P.AMBER if st in ["OCCLUDED", "JAMMED"] else P.RED)
		draw_rect(Rect2(lp.position.x + 10, y - 9, lp.size.x - 20, 13), P.a(P.PANEL, 0.35) if i % 2 == 0 else P.a(P.PANEL2, 0.2))
		Painter.label(self, lp.position.x + 14, y, mode, 7, P.TXT, true)
		Painter.label(self, lp.position.x + 80, y, st, 7, col, true)
		Painter.label(self, lp.position.x + 156, y, lat, 7, P.DIM, true)
		Painter.label_right(self, lp.end.x - 14, y, str(n_ev), 7, P.TXT, true)
	# 左栏 MESSAGE STREAM
	var my := cy + 5.0 * 17.0 + 14.0
	Painter.section(self, lp.position.x + 10, my, lp.end.x - 10, "MESSAGE STREAM / 消息")
	my += 16.0
	if events.is_empty():
		Painter.label(self, lp.position.x + 12, my, "NO MESSAGES · NOT READY", 7, P.FAINT, true)
	var row_capacity := mini(10, maxi(1, int((lp.end.y - my - 12.0) / 16.0)))
	for i in range(maxi(0, events.size() - row_capacity), events.size()):
		var ev: Dictionary = events[i]
		var from := String(ev.get("from_name", ev.get("from", "—")))
		var to := String(ev.get("to_name", ev.get("to", "—")))
		var mode := String(ev.get("mode", "—"))
		var content := String(ev.get("text", ""))
		if content == "":
			content = String(ev.get("text_key", "TEXT KEY 未提供"))
		if content == "":
			content = "[" + String(ev.get("kind", "comms")) + " · " + String(ev.get("reason", "")) + "]"
		var row := i - maxi(0, events.size() - row_capacity)
		var yy := my + float(row) * 16.0
		if row % 2 == 1:
			draw_rect(Rect2(lp.position.x + 10, yy - 11, lp.size.x - 20, 14), P.a(P.PANEL, 0.30))
		Painter.label(self, lp.position.x + 12, yy, TM.fit("[%s 至 %s]-[%s]-[%s]" % [from, to, mode, content], lp.size.x - 24, true, 7), 7, P.TXT, true)
	# 链路明细，填满左栏下部（真实 comms vm links）
	var link_y := lp.end.y - 174.0
	Painter.section(self, lp.position.x + 10, link_y, lp.end.x - 10, "LINK DETAIL / 链路明细")
	link_y += 15.0
	if links.is_empty():
		Painter.label(self, lp.position.x + 12, link_y, "NO LINKS · NOT READY", 7, P.FAINT, true)
	for i in range(mini(5, links.size())):
		var l: Dictionary = links[i]
		var la := String(l.get("a", l.get("from", "—")))
		var lb := String(l.get("b", l.get("to", "—")))
		var lm := String(l.get("mode", "—"))
		var st := "OPEN"
		if bool(l.get("disabled", false)):
			st = "CLOSED"
		elif bool(l.get("occluded", false)):
			st = "OCCLUDED"
		elif float(l.get("jam", 0.0)) >= 0.7:
			st = "JAMMED"
		Painter.label(self, lp.position.x + 12, link_y + float(i) * 14.0, TM.fit("%s → %s · %s · %s · %s" % [la, lb, lm, st, "%.1fs" % float(l.get("latency_s", l.get("latency", 0.0)))], lp.size.x - 24, true, 7), 7, P.PH_DIM if st == "OPEN" else P.AMBER, true)
	# 右栏命令面板
	var px := rp.position.x + 10.0
	var py := rp.position.y + 38.0
	Painter.section(self, px, py, rp.end.x - 10, "COMMAND PANEL / 命令面板")
	py += 16.0
	_comms_type_buttons.clear()
	var types := ["HOLD", "NAV", "EMCON", "IFF", "ROE"]
	for i in range(types.size()):
		var tr := Rect2(px + float(i % 3) * (right_w - 28.0) / 3.0, py + float(i / 3) * 24.0, (right_w - 40.0) / 3.0, 20.0)
		_comms_type_buttons.append({"rect": tr, "kind": String(types[i])})
		var active := _comms_type == String(types[i])
		Painter.button(self, tr, String(types[i]), true, P.PH if active else P.PH_DIM)
	py += 52.0
	Painter.label(self, px, py, "TARGET " + (_comms_target if _comms_target != "" else "NOT READY"), 7, P.TXT, true)
	py += 13.0
	Painter.label(self, px, py, "ISSUER apsis · MODE " + ("LD" if _comms_type in ["HOLD", "NAV"] else "SENSOR/ROE"), 6, P.DIM, true)
	py += 20.0
	_comms_send_rect = Rect2(px, py, 160, 22)
	Painter.button(self, _comms_send_rect, "SEND / 发送", true, P.PH)
	py += 29.0
	if _comms_msg != "":
		Painter.label(self, px, py, TM.fit(_comms_msg, rp.size.x - 28, true, 7), 7, P.AMBER, true)
	py += 16.0
	var auth_txt := ""
	for lv in ["TRACK", "SOLUTION", "FIRE"]:
		var au: Dictionary = binder.session.combat_authorization(lv, _comms_target, "") if binder != null and binder.session != null else {}
		auth_txt += "%s:%s " % [lv, "OK" if bool(au.get("ok", false)) else "LOCK"]
	Painter.label(self, px, py, "AUTH " + auth_txt, 6, P.a(P.PH_DIM, 0.9), true)
	py += 14.0
	Painter.section(self, px, py, rp.end.x - 10, "COMMAND QUEUE / 命令队列")
	py += 15.0
	_comms_cmd_rows.clear()
	_comms_cmd_buttons.clear()
	var cmds: Array = binder.commands if binder != null else []
	for i in range(mini(3, cmds.size())):
		var c: Dictionary = cmds[i]
		var rr := Rect2(px, py + float(i) * 17.0, rp.size.x - 20, 15)
		_comms_cmd_rows.append({"rect": rr, "index": i})
		if i == _selected_cmd:
			draw_rect(rr, P.a(P.PH, 0.10))
		Painter.label(self, px, rr.position.y + 11, TM.fit("%s %s · %s → %s" % [String(c.get("id", "")), String(c.get("state", "")), String(c.get("actor", "")), String(c.get("target", ""))], rr.size.x, true, 7), 7, P.PH if i == _selected_cmd else P.DIM, true)
	# 选中命令详情 + ROE/授权，填满右栏下部
	var detail_y := rp.end.y - 174.0
	Painter.section(self, px, detail_y, rp.end.x - 10, "SELECTED COMMAND / 命令详情")
	detail_y += 15.0
	if _selected_cmd >= 0 and _selected_cmd < cmds.size():
		var sc: Dictionary = cmds[_selected_cmd]
		Painter.label(self, px, detail_y, "ID " + String(sc.get("id", "—")) + " · " + String(sc.get("state", "—")), 7, P.TXT, true)
		Painter.label(self, px, detail_y + 13, "ACTOR → TARGET  " + String(sc.get("actor", "—")) + " → " + String(sc.get("target", "—")), 7, P.TXT, true)
		Painter.label(self, px, detail_y + 26, "ACTION " + String(sc.get("action", "—")) + " · MODE " + String(sc.get("mode", "—")) + " · DELAY " + String(sc.get("delay", "—")), 7, P.DIM, true)
	else:
		Painter.label(self, px, detail_y, "NO COMMAND SELECTED", 7, P.FAINT, true)
	detail_y += 46.0
	Painter.label(self, px, detail_y, "ROE " + (String(_combat.roe) if _combat != null else "NOT READY") + " · ROE 不授予 FIRE 授权", 7, P.AMBER, true)
	var by := rp.end.y - 34.0
	_comms_cmd_buttons.append({"rect": Rect2(px, by, 84, 18), "kind": "ABORT"})
	_comms_cmd_buttons.append({"rect": Rect2(px + 90, by, 84, 18), "kind": "REVOKE"})
	Painter.button(self, _comms_cmd_buttons[0]["rect"], "ABORT", _selected_cmd >= 0, P.AMBER)
	Painter.button(self, _comms_cmd_buttons[1]["rect"], "REVOKE", _selected_cmd >= 0, P.RED)
	Painter.label(self, px, rp.end.y - 12, "双栏 · COMMS 600H · 默认旗舰 target", 6, P.a(P.FAINT, 0.9), true)


func _comms_action(kind: String) -> void:
	_comms_type = kind
	_comms_msg = "TYPE " + kind + " · target " + _comms_target
	queue_redraw()


func _comms_send() -> void:
	if binder == null or binder.session == null:
		_comms_msg = "NO SESSION · NOT READY"
		return
	var target := _comms_target
	if target == "":
		_comms_msg = "NO TARGET · NOT READY"
		return
	var res: Dictionary = {}
	if _comms_type in ["HOLD", "NAV"]:
		res = binder.session.issue_order(_comms_type, "apsis", [target], {}, {})
	elif _comms_type == "EMCON":
		res = binder.sensor_command("EMCON")
	elif _comms_type == "IFF":
		res = binder.sensor_command("IFF")
	elif _comms_type == "ROE":
		if _roe_locked:
			_comms_msg = "ROE LOCKED · 序章未解锁"
			return
		res = binder.session.set_roe("HOLD")
	_comms_msg = "SEND %s → %s · %s%s" % [_comms_type, target, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] COMMS ", _comms_msg)
	binder.refresh()
	_selected_cmd = clampi(_selected_cmd, 0, maxi(0, binder.commands.size() - 1))
	queue_redraw()


func _draw_optical_overlay(r: Rect2) -> void:
	var x := r.position.x + 16.0
	var y := r.position.y + 34.0
	Painter.label(self, x, y, "光学 / 识别 · OPTICAL / IDENTIFICATION", 12, P.PH)
	Painter.label(self, x, y + 14, "目标=当前选中 track/entity · 数据来自 track_vm / sensor_vm · 不伪造 L3/L4", 7, P.a(P.AMBER, 0.9), true)
	var c: Dictionary = _contacts[_selected] if _selected >= 0 and _selected < _contacts.size() else {}
	var tr: Dictionary = _optical_track
	if tr.is_empty() and binder != null:
		tr = binder.selected_track(c)
	var target_id := String(_optical_target)
	if target_id == "":
		target_id = String(c.get("entity_id", c.get("id", "")))
	Painter.label(self, x, y + 40, "TARGET  " + String(c.get("name", "NOT READY")) + " · " + String(c.get("id", target_id)), 9, P.TXT)
	Painter.label(self, x, y + 56, "ENTITY/TRACK " + target_id + " · " + (String(tr.get("track_id", "TRACK NOT READY")) if not tr.is_empty() else "TRACK NOT READY"), 7, P.PH_DIM, true)
	# 左侧识别链
	var ly := y + 82.0
	Painter.section(self, x, ly, x + 540, "IDENTIFICATION CHAIN / L1–L4")
	ly += 16.0
	var level := int(tr.get("level", 0)) if not tr.is_empty() else 0
	var lv_names := ["NO TRACK", "L1 BEARING", "L2 POSITION", "L3 CLASSIFIED", "L4 IDENTIFIED"]
	var level_name := String(lv_names[clampi(level, 0, 4)])
	var lv_cols := [P.FAINT, P.DIM, P.BLUE, P.AMBER, P.PH]
	for i in range(1, 5):
		var active := level >= i
		var cr := Rect2(x + float(i - 1) * 132.0, ly, 124, 20)
		draw_rect(cr, P.a(lv_cols[i], 0.12 if active else 0.03))
		draw_rect(cr, P.a(lv_cols[i], 0.7 if active else 0.22), false, 1.0)
		Painter.label(self, cr.position.x + 5, cr.position.y + 14, "L%d %s" % [i, String(lv_names[i])], 7, lv_cols[i] if active else P.FAINT, true)
	ly += 30.0
	Painter.key_value(self, x, ly, x + 540, "LEVEL", "L%d · %s" % [level, level_name], P.PH if level >= 3 else P.AMBER)
	ly += 13.0
	Painter.key_value(self, x, ly, x + 540, "IDENTITY", String(tr.get("identity_label", tr.get("identity", "—"))) if not tr.is_empty() else "NOT READY", P.TXT)
	ly += 13.0
	var sources: Array = tr.get("sources", []) if not tr.is_empty() and tr.get("sources", []) is Array else []
	var evidence: Array = tr.get("evidence_ids", []) if not tr.is_empty() and tr.get("evidence_ids", []) is Array else []
	Painter.key_value(self, x, ly, x + 540, "SOURCES", ",".join(sources) if not sources.is_empty() else "NOT READY", P.TXT)
	ly += 13.0
	Painter.key_value(self, x, ly, x + 540, "EVIDENCE", str(evidence.size()) + " ids", P.TXT)
	ly += 13.0
	Painter.key_value(self, x, ly, x + 540, "RANGE / BRG", ("%.1f km / %.0f°" % [float(tr.get("range_km", -1.0)), float(tr.get("bearing_deg", -1.0))]) if not tr.is_empty() else "NOT READY", P.TXT)
	ly += 13.0
	# FOV/SNR 从 sensor vm channels 查
	var fov := "—"
	var snr := "—"
	if binder != null:
		var svm: Dictionary = binder.sensor_vm
		var chans: Array = svm.get("channels", []) if svm.get("channels", []) is Array else []
		for raw in chans:
			if raw is Dictionary and (String((raw as Dictionary).get("target_id", "")) == target_id or String((raw as Dictionary).get("target", "")) == target_id):
				fov = str((raw as Dictionary).get("fov_deg", (raw as Dictionary).get("fov", "—")))
				snr = str((raw as Dictionary).get("snr_db", (raw as Dictionary).get("snr", "—")))
				break
	Painter.key_value(self, x, ly, x + 540, "FOV / SNR", "%s / %s" % [fov, snr], P.TXT)
	# 右光学小窗
	var ow := Rect2(x + 570, y + 80, 330, 250)
	draw_rect(ow, P.a(P.EARTH, 0.7))
	draw_rect(ow, P.a(P.LINE2, 0.6), false, 1.0)
	draw_string(F.mono(), Vector2(ow.position.x + 8, ow.position.y + 16), "V1 OPTICAL / 瞄准框 · FOV " + str(fov), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH, 0.9))
	var cen := ow.position + ow.size * 0.5
	draw_line(Vector2(cen.x - ow.size.x * 0.4, cen.y), Vector2(cen.x - 12, cen.y), P.a(P.PH, 0.65), 1.0)
	draw_line(Vector2(cen.x + 12, cen.y), Vector2(cen.x + ow.size.x * 0.4, cen.y), P.a(P.PH, 0.65), 1.0)
	draw_line(Vector2(cen.x, cen.y - ow.size.y * 0.4), Vector2(cen.x, cen.y - 12), P.a(P.PH, 0.65), 1.0)
	draw_line(Vector2(cen.x, cen.y + 12), Vector2(cen.x, cen.y + ow.size.y * 0.4), P.a(P.PH, 0.65), 1.0)
	draw_rect(Rect2(cen - Vector2(44, 44), Vector2(88, 88)), P.a(P.AMBER, 0.7), false, 1.0)
	draw_circle(cen, 2.0, P.PH)
	draw_string(F.mono(), Vector2(ow.position.x + 8, ow.end.y - 12), "VIS/IR · SNR " + str(snr) + " · TRACK L%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))
	# 按钮
	_optical_buttons.clear()
	var labels := [["VIS", "VIS / 可见光"], ["IR", "IR / 红外"], ["IFF", "IFF QUERY"], ["ELINT", "ELINT"], ["LIGHT", "LIGHT SIGNAL"]]
	var by := r.end.y - 36.0
	for i in range(labels.size()):
		var br := Rect2(x + float(i) * 120.0, by, 112, 22)
		_optical_buttons.append({"rect": br, "kind": String(labels[i][0])})
		Painter.button(self, br, String(labels[i][1]), true, P.PH if i < 3 else P.PH_DIM)
	if _optical_msg != "":
		Painter.label(self, x, by - 12, TM.fit(_optical_msg, r.size.x - 32, true, 7), 7, P.AMBER, true)


func _optical_action(kind: String) -> void:
	if binder == null or binder.session == null or binder.session.sensor_service == null:
		_optical_msg = "SENSOR NOT READY · 无 sensor_service"
		return
	var target := _optical_target
	if target == "":
		_optical_msg = "NO TARGET · NOT READY"
		return
	var s = binder.session.sensor_service
	var res: Dictionary = {}
	match kind:
		"VIS":
			res = s.start_channel("optical", target)
		"IR":
			res = s.start_channel("ir", target)
		"IFF":
			res = s.query_iff(target)
		"LIGHT":
			res = binder.session.send_comms("apsis", target, "VIS", "COMMS_SENT", {}, {})
		"ELINT":
			res = {"ok": false, "reason": "elint_not_wired"}
		_:
			res = {"ok": false, "reason": "unknown"}
	_optical_msg = "%s %s · %s%s" % [kind, target, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] OPTICAL ", _optical_msg)
	binder.refresh()
	_optical_track = binder.selected_track(_contacts[_selected]) if binder != null and _selected >= 0 and _selected < _contacts.size() else {}
	queue_redraw()


func _seed_combat_tracks() -> void:
	if _combat == null or binder == null:
		return
	var tracks: Array = binder.track_vm.get("tracks", []) if binder.track_vm.get("tracks", []) is Array else []
	for raw in tracks:
		if raw is Dictionary:
			var tr: Dictionary = raw
			var tid := String(tr.get("track_id", tr.get("id", "")))
			if tid != "":
				_combat.register_track(tid, tr)
	var vm: Dictionary = _combat.vm()
	var crows: Array = vm.get("tracks", []) if vm.get("tracks", []) is Array else []
	if _combat_target == "" and not crows.is_empty():
		_combat_target = String((crows[0] as Dictionary).get("id", ""))
	var wrows: Array = vm.get("weapons", []) if vm.get("weapons", []) is Array else []
	if _combat_weapon == "":
		for raw2 in wrows:
			if raw2 is Dictionary and String((raw2 as Dictionary).get("kind", "")) in ["kinetic", "guided"]:
				_combat_weapon = String((raw2 as Dictionary).get("id", ""))
				break
	print("[V1 HUD] COMBAT tracks=", crows.size(), " weapons=", wrows.size(), " target=", _combat_target, " weapon=", _combat_weapon)


func _draw_combat_overlay(r: Rect2) -> void:
	var x := r.position.x + 16.0
	var y := r.position.y + 34.0
	Painter.label(self, x, y, "战斗终端 / COMBAT TERMINAL", 12, P.PH)
	Painter.label(self, x, y + 14, "目标/武器/ROE/授权/预测 · CombatService shadow · NO PHYSICS HIT", 7, P.a(P.AMBER, 0.9), true)
	if _combat == null or not bool(_combat.ready):
		Painter.label(self, x, y + 44, "COMBAT NOT READY · no CombatService", 9, P.AMBER)
		return
	var vm: Dictionary = _combat.vm()
	var track_rows: Array = vm.get("tracks", []) if vm.get("tracks", []) is Array else []
	var weapon_rows: Array = vm.get("weapons", []) if vm.get("weapons", []) is Array else []
	# 目标列表
	var tw := 300.0
	Painter.section(self, x, y + 42.0, x + tw, "TARGETS / 目标")
	_combat_target_rows.clear()
	var ty := y + 60.0
	for i in range(mini(5, track_rows.size())):
		var tr: Dictionary = track_rows[i]
		var tid := String(tr.get("id", ""))
		var tr_rect := Rect2(x, ty + float(i) * 28.0, tw - 8, 25.0)
		_combat_target_rows.append({"rect": tr_rect, "id": tid})
		if tid == _combat_target:
			draw_rect(tr_rect, P.a(P.AMBER, 0.12))
		Painter.label(self, x, tr_rect.position.y + 11, "L%d %s · %s" % [int(tr.get("level", 0)), tid, String(tr.get("identity", "unknown"))], 7, P.PH if tid == _combat_target else P.TXT, true)
		var rng := float(tr.get("range_km", -1.0))
		Painter.label(self, x + 8, tr_rect.position.y + 22, "threat %s · %s" % [String(tr.get("threat", "—")), ("%.1f km" % rng) if rng >= 0.0 else "RANGE NOT READY"], 6, P.a(P.DIM, 0.9), true)
	# 武器架
	var wx := x + tw + 16.0
	Painter.section(self, wx, y + 42.0, wx + 360.0, "WEAPON RACK / 武器架")
	_combat_weapon_rows.clear()
	var wy := y + 60.0
	for i in range(mini(6, weapon_rows.size())):
		var w: Dictionary = weapon_rows[i]
		var wid := String(w.get("id", ""))
		var wr := Rect2(wx, wy + float(i) * 28.0, 352, 25.0)
		_combat_weapon_rows.append({"rect": wr, "id": wid})
		if wid == _combat_weapon:
			draw_rect(wr, P.a(P.PH, 0.10))
		Painter.label(self, wx, wr.position.y + 11, "%s · %s" % [wid, String(w.get("kind", ""))], 7, P.PH if wid == _combat_weapon else P.TXT, true)
		Painter.label(self, wx + 190, wr.position.y + 11, "AMMO %s · CD %s · RANGE %s" % [
			str(w.get("ammo", "—")), str(w.get("cooldown_remaining_s", w.get("cooldown_s", "—"))), str(w.get("range_km", "—"))], 6, P.a(P.DIM, 0.9), true)
	# 右: ROE/授权/预测
	var rx := x + tw + 390.0
	var ry := y + 42.0
	Painter.section(self, rx, ry, r.end.x - 14, "ROE / AUTHORIZATION")
	ry += 16.0
	Painter.label(self, rx, ry, "ROE " + String(vm.get("roe", "—")) + " · " + String(vm.get("roe_label", "")), 8, P.PH, true)
	ry += 14.0
	_combat_roe_buttons.clear()
	var roes := ["DEFEND", "HOLD", "TIGHT", "FREE"]
	for i in range(roes.size()):
		var br := Rect2(rx + float(i) * 83.0, ry, 78, 18)
		_combat_roe_buttons.append({"rect": br, "kind": String(roes[i])})
		Painter.button(self, br, String(roes[i]), true, P.PH if String(vm.get("roe", "")) == String(roes[i]) else P.PH_DIM)
	ry += 28.0
	for lvl in ["TRACK", "SOLUTION", "FIRE"]:
		var au: Dictionary = binder.session.combat_authorization(lvl, _combat_target, _combat_weapon) if binder != null and binder.session != null else {}
		Painter.label(self, rx, ry, "%s AUTHORIZATION" % lvl, 7, P.a(P.PH_DIM, 0.9), true)
		Painter.label_right(self, r.end.x - 14, ry, "OK" if bool(au.get("ok", false)) else String(au.get("reason", "LOCKED")), 7, P.PH if bool(au.get("ok", false)) else P.AMBER, true)
		ry += 13.0
	# 预测接口
	ry += 6.0
	Painter.section(self, rx, ry, r.end.x - 14, "PREDICTION / INTERFACE · NO PHYSICS")
	ry += 15.0
	var pred: Dictionary = _combat.predict_shot(_combat_target, _combat_weapon) if _combat_target != "" and _combat_weapon != "" else {}
	if bool(pred.get("ok", false)):
		Painter.label(self, rx, ry, "TOF %.1fs · HIT %d%% · ERR %.2f km" % [float(pred.get("time_of_flight_s", -1.0)), int(float(pred.get("hit_probability", 0.0)) * 100.0), float(pred.get("error_km", 0.0))], 7, P.TXT, true)
		Painter.label(self, rx, ry + 12, "trajectory=" + String(pred.get("trajectory", "interface_only")) + " · no_physics=" + str(bool(pred.get("no_physics", true))), 6, P.a(P.FAINT, 0.9), true)
	else:
		Painter.label(self, rx, ry, "PREDICTION NOT READY · " + String(pred.get("reason", "no target/weapon")), 7, P.AMBER, true)
	ry += 38.0
	# 操作按钮：按可用宽度等分两列，避免固定宽度在不同分辨率下越界/错位
	_combat_buttons.clear()
	var actions := ["TRACK", "SOLUTION", "AUTHORIZE FIRE", "FIRE"]
	var btn_gap := 8.0
	var btn_avail := maxf(120.0, r.end.x - 14.0 - rx)
	var btn_w := floorf((btn_avail - btn_gap) * 0.5)
	for i in range(actions.size()):
		var col := i % 2
		var row := i / 2
		var br := Rect2(rx + float(col) * (btn_w + btn_gap), ry + float(row) * 26.0, btn_w, 21)
		_combat_buttons.append({"rect": br, "kind": String(actions[i])})
		Painter.button(self, br, String(actions[i]), true, P.PH if i < 3 else P.RED)
	ry += 60.0
	# 战斗事件
	Painter.section(self, x, y + 235.0, x + r.size.x - 36, "COMBAT EVENTS / 战斗事件")
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	var ey := y + 252.0
	if evs.is_empty():
		Painter.label(self, x, ey, "NO COMBAT EVENTS · NOT READY", 7, P.FAINT, true)
	for i in range(maxi(0, evs.size() - 5), evs.size()):
		var ev: Dictionary = evs[i]
		Painter.label(self, x, ey + float(i - maxi(0, evs.size() - 5)) * 12.0, "%5.1fs %s · %s" % [float(ev.get("t", 0.0)), String(ev.get("kind", "")), TM.fit(JSON.stringify(ev.get("payload", {})), 520, true, 6)], 6, P.a(P.DIM, 0.9), true)
	if _combat_msg != "":
		Painter.label(self, x, r.end.y - 14, TM.fit(_combat_msg, r.size.x - 32, true, 7), 7, P.AMBER, true)


func _combat_action(kind: String) -> void:
	if _combat == null or not bool(_combat.ready):
		_combat_msg = "COMBAT NOT READY"
		return
	var res: Dictionary = {}
	match kind:
		"TRACK":
			res = _combat.request_track(_combat_target, true)
		"SOLUTION":
			res = _combat.request_solution(_combat_target, _combat_weapon, true)
		"AUTHORIZE FIRE":
			res = binder.session.grant_authorization("FIRE", "target", _combat_target) if binder != null and binder.session != null else {"ok": false, "reason": "no_session"}
		"FIRE":
			res = _combat.request_fire(_combat_target, _combat_weapon, true)
		"DEFEND", "HOLD", "TIGHT", "FREE":
			res = _combat.set_roe(kind)
		_:
			res = {"ok": false, "reason": "unknown_action"}
	_combat_msg = "%s %s/%s · %s%s" % [kind, _combat_target, _combat_weapon, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] COMBAT ", _combat_msg)
	queue_redraw()


func _draw_damage_overlay(r: Rect2) -> void:
	var x := r.position.x + 14.0
	var y := r.position.y + 34.0
	Painter.label(self, x, y, "损管 / DAMAGE · 7 SECTIONS", 12, P.PH)
	Painter.label(self, x, y + 14, "SOURCE · V2DamageModel shadow (session 无 damage_vm) · 只读/最小交互", 7, P.a(P.AMBER, 0.9), true)
	_damage_rows.clear()
	_damage_buttons.clear()
	if _damage == null or not bool(_damage.ready):
		Painter.label(self, x, y + 40, "DAMAGE NOT READY · 无模型/内容", 9, P.AMBER)
		return
	var vm: Dictionary = _damage.vm_damage()
	var secs: Array = vm.get("sections", []) if vm.get("sections", []) is Array else []
	var sy := y + 44.0
	for i in range(secs.size()):
		var sec: Dictionary = secs[i]
		var sr := Rect2(x, sy + float(i) * 36.0, r.size.x * 0.55, 32.0)
		var selected := String(sec.get("id", "")) == _selected_section
		var fire: Dictionary = sec.get("fire", {}) if sec.get("fire", {}) is Dictionary else {}
		var dec: Dictionary = sec.get("decompression", {}) if sec.get("decompression", {}) is Dictionary else {}
		Painter.list_row(self, sr, "%s · %s" % [String(sec.get("id", "")), String(sec.get("label", ""))],
			"%.1f%% %s%s%s" % [float(sec.get("integrity_pct", 0.0)), String(sec.get("state", "")),
			" · FIRE" if bool(fire.get("active", false)) else "", " · DEC" if bool(dec.get("active", false)) else ""],
			P.RED if float(sec.get("integrity", 0.0)) < 0.25 else P.PH_DIM, selected)
		_damage_rows.append({"rect": sr, "id": String(sec.get("id", ""))})
	_damage_buttons.clear()
	var bx := x
	var by := r.end.y - 34.0
	for i in range(3):
		var br := Rect2(bx + float(i) * 128.0, by, 118, 22.0)
		_damage_buttons.append({"rect": br, "kind": ["FIX", "PRI", "CANCEL"][i]})
		Painter.button(self, br, ["FIX / 维修", "PRI / 优先级", "CANCEL / 取消"][i], true, P.PH if i < 2 else P.AMBER)
	Painter.label(self, bx + 400, by + 15, "选择的 section / 点击列表选中", 7, P.a(P.FAINT, 0.9), true)
	# 右侧资源/队列/事件
	var rx := x + r.size.x * 0.57
	var ry := y + 44.0
	Painter.section(self, rx, ry, r.end.x - 14, "RESOURCES / 队伍")
	ry += 15.0
	var res: Dictionary = vm.get("resources", {}) if vm.get("resources", {}) is Dictionary else {}
	Painter.label(self, rx, ry, "TEAMS %s · SPARES %s · PERSONNEL %s" % [str(res.get("teams_available", "")), str(res.get("spares", "")), str(res.get("personnel", ""))], 7, P.TXT, true)
	ry += 18.0
	Painter.section(self, rx, ry, r.end.x - 14, "QUEUE / 队列")
	ry += 15.0
	var jobs: Array = vm.get("queue", []) if vm.get("queue", []) is Array else []
	if jobs.is_empty():
		Painter.label(self, rx, ry, "NO REPAIR JOBS", 7, P.FAINT, true)
	for i in range(mini(3, jobs.size())):
		var job: Dictionary = jobs[i]
		Painter.label(self, rx, ry + float(i) * 12.0, "%s · P%s · %.0f%%" % [String(job.get("section", "")), str(job.get("priority", "")), float(job.get("progress_pct", 0.0))], 7, P.TXT, true)
	ry += 48.0
	Painter.section(self, rx, ry, r.end.x - 14, "EVENTS / 事件")
	ry += 15.0
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	for i in range(mini(3, maxi(0, evs.size() - 3))):
		var ev: Dictionary = evs[evs.size() - 1 - i]
		Painter.label(self, rx, ry + float(i) * 12.0, TM.fit(String(ev.get("text", ev.get("type", ""))), r.size.x * 0.4, false, 7), 7, P.DIM, true)
	if _damage_msg != "":
		Painter.label(self, x, r.end.y - 48, TM.fit(_damage_msg, r.size.x - 28, true, 7), 7, P.AMBER, true)


func _draw_roe_overlay(r: Rect2) -> void:
	var x := r.position.x + 24.0
	var y := r.position.y + 40.0
	Painter.label(self, x, y, "ROE / 交战规则 · 四档", 12, P.PH)
	Painter.label(self, x, y + 16, "session.set_roe(DEFEND/HOLD/TIGHT/FREE) · 当前 " + (String(_combat.roe) if _combat != null else "NOT READY"), 8, P.PH_DIM, true)
	if _roe_locked:
		Painter.label(self, x, y + 40, "LOCKED · 序章未解锁 · 仅显示当前档位", 9, P.AMBER)
	else:
		Painter.label(self, x, y + 40, "UNLOCKED · 点击档位调用真实 session.set_roe", 8, P.TXT, true)
	_roe_buttons.clear()
	var labels := [["DEFEND", "DEFEND / 防御"], ["HOLD", "HOLD / 保持"], ["TIGHT", "TIGHT / 严格"], ["FREE", "FREE / 自由"]]
	for i in range(labels.size()):
		var br := Rect2(x + float(i % 2) * 220.0, y + 60.0 + float(i / 2) * 42.0, 210, 30.0)
		_roe_buttons.append({"rect": br, "kind": String(labels[i][0])})
		var active := _combat != null and String(_combat.roe) == String(labels[i][0])
		Painter.button(self, br, String(labels[i][1]), not _roe_locked, P.PH if active else P.PH_DIM)
		if active:
			Painter.label(self, br.position.x + 4, br.end.y - 3, "CURRENT", 6, P.PH, true)
	Painter.label(self, x, y + 180, "授权提示：ROE 只改交战规则，不授予开火许可；需另行授权。", 8, P.a(P.DIM, 0.95), false)
	if _roe_msg != "":
		Painter.label(self, x, y + 204, TM.fit(_roe_msg, r.size.x - 48, true, 8), 8, P.AMBER, true)


func _do_save(kind: String) -> void:
	var intent := "save"
	if kind == "menu":
		intent = "save_and_menu"
	elif kind == "quit":
		intent = "save_and_quit"
	if binder == null:
		return
	var res: Dictionary = binder.save(intent)
	_save_ok = bool(res.get("ok", false))
	_save_msg = binder.last_save_text
	print("[V1 HUD] SAVE ", intent, " · ", _save_msg)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _overlay != "":
		if _overlay_close.has_point(event.position):
			_overlay = ""
			return
		if _overlay == "damage":
			for row in _damage_rows:
				if (row["rect"] as Rect2).has_point(event.position):
					_selected_section = String(row.get("id", ""))
					return
			for b in _damage_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_damage_action(String(b.get("kind", "")))
					return
		elif _overlay == "roe":
			for b in _roe_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_roe_action(String(b.get("kind", "")))
					return
		elif _overlay == "optical":
			for b in _optical_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_optical_action(String(b.get("kind", "")))
					return
		elif _overlay == "combat":
			for row in _combat_target_rows:
				if (row["rect"] as Rect2).has_point(event.position):
					_combat_target = String(row.get("id", ""))
					return
			for row in _combat_weapon_rows:
				if (row["rect"] as Rect2).has_point(event.position):
					_combat_weapon = String(row.get("id", ""))
					return
			for b in _combat_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_combat_action(String(b.get("kind", "")))
					return
			for b in _combat_roe_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_combat_action(String(b.get("kind", "")))
					return
		elif _overlay == "comms":
			for b in _comms_type_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_comms_action(String(b.get("kind", "")))
					return
			if _comms_send_rect.has_point(event.position):
				_comms_send()
				return
			for row in _comms_cmd_rows:
				if (row["rect"] as Rect2).has_point(event.position):
					_selected_cmd = int(row.get("index", -1))
					return
			for b in _comms_cmd_buttons:
				if (b["rect"] as Rect2).has_point(event.position):
					_command_action(String(b.get("kind", "")))
					return
		return
	for d in _top_dots:
		if (d["rect"] as Rect2).has_point(event.position):
			_do_save(String(d.get("kind", "")))
			return
	for b in _right_buttons:
		if (b["rect"] as Rect2).has_point(event.position):
			_do_right_action(String(b.get("kind", "")))
			return
	for c in _contact_rects:
		if (c["rect"] as Rect2).has_point(event.position):
			_selected = int(c.get("index", 0))
			var picked: Dictionary = _contacts[_selected]
			_comms_target = String(picked.get("entity_id", picked.get("id", "")))
			_page = "target" if String(picked.get("type", "")) in ["unknown", "neutral"] else "ship"
			return
	for tab in _tabs:
		if (tab["rect"] as Rect2).has_point(event.position):
			_page = String(tab.get("page", "ship"))
			return
	for row in _command_rows:
		if (row["rect"] as Rect2).has_point(event.position):
			_selected_cmd = int(row.get("index", -1))
			return
	for b in _command_buttons:
		if (b["rect"] as Rect2).has_point(event.position):
			_command_action(String(b.get("kind", "")))
			return


func _do_right_action(kind: String) -> void:
	if binder == null:
		return
	match kind:
		"DAMAGE":
			_overlay = "damage"
			if _selected_section == "" and _damage != null and _damage.ready:
				var secs: Array = _damage.section_ids()
				if not secs.is_empty():
					_selected_section = String(secs[0])
		"ROE":
			_overlay = "roe"
		"COMMS":
			_overlay = "comms"
		"COMBAT":
			_overlay = "combat"
			_seed_combat_tracks()
		"NAV":
			get_tree().change_scene_to_file("res://nav_page.tscn")
		"OPTICAL":
			_overlay = "optical"
			if _selected >= 0 and _selected < _contacts.size():
				var picked: Dictionary = _contacts[_selected]
				_optical_target = String(picked.get("entity_id", picked.get("id", "")))
				_optical_track = binder.selected_track(picked) if binder != null else {}
		"INFO":
			_sensor_msg = "INFO OPS · 占位信号（未接信息作战）"
		_:
			_sensor_msg = "ACTION " + kind + " · 未接线"
	queue_redraw()


func _damage_action(kind: String) -> void:
	if _damage == null or _selected_section == "":
		_damage_msg = "NO SECTION SELECTED"
		return
	var res: Dictionary = {}
	if kind == "FIX":
		res = _damage.assign_repair(_selected_section, 2)
	elif kind == "PRI":
		res = _damage.set_priority(_selected_section, 1)
	elif kind == "CANCEL":
		res = _damage.cancel_repair(_selected_section)
	_damage_msg = "%s %s · %s%s" % [kind, _selected_section, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] DAMAGE ", _damage_msg)


func _roe_action(level: String) -> void:
	if _roe_locked:
		_roe_msg = "LOCKED · 序章未解锁"
		return
	if binder == null or binder.session == null:
		_roe_msg = "ROE NOT READY · no session"
		return
	var res: Dictionary = binder.session.set_roe(level)
	_roe_msg = "set_roe %s · %s%s" % [level, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] ROE ", _roe_msg)


func _command_action(kind: String) -> void:
	if binder == null or binder.session == null or _selected_cmd < 0 or _selected_cmd >= binder.commands.size():
		_command_msg = "NO COMMAND SELECTED"
		return
	var c: Dictionary = binder.commands[_selected_cmd]
	var oid := String(c.get("id", ""))
	var res: Dictionary = {}
	if kind == "ABORT":
		res = binder.session.abort_order(oid, "ui_abort")
	elif kind == "REVOKE":
		res = binder.session.reject_order(oid, "ui_revoke", "commander")
	_command_msg = "%s %s · %s%s" % [kind, oid, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	print("[V1 HUD] COMMAND ", _command_msg)
	binder.refresh()


func _clock(s: float) -> String:
	var sec := int(maxf(0.0, s))
	return "%02d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
