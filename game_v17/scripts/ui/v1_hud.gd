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
const Plot3D := preload("res://scripts/ui/plot3d.gd")

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
var _plot3d = null
var _plot_surface: Control = null
var _plot3d_rect := Rect2()
# 方案B-32：overlay 独立层（位于 plot 之上 + 裁剪）；_cv 是当前 overlay 绘制画布。
var _overlay_layer: Control = null
var _overlay_local := Rect2()
var _overlay_offset := Vector2.ZERO
var _cv: CanvasItem = null
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
var _signal_code := ""
var _signal_tx_id := ""
var _signal_msg := ""
var _signal_code_index := 0
var _txp_reply: Dictionary = {}
var _txp_msg := ""
var _trigger_banner := ""
var _ceres_msg := ""
var _chronos_msg := ""
var _chronos_buttons: Array = []
var _av4412_msg := ""
var _av4412_buttons: Array = []
var _report_msg := ""
var _report_buttons: Array = []
var _traffic_msg := ""
var _traffic_buttons: Array = []
var _traffic_otc_rows: Array = []
var _traffic_lane_rows: Array = []
var _traffic_otc := ""
var _traffic_lane := ""
var _traffic_request_id := ""
var _traffic_clearance_id := ""
var _traffic_last: Dictionary = {}
var _save_slots: Array = []
var _save_load_buttons: Array = []
var _save_overlay_msg := ""
var _exit_intent := false


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
	if binder != null and String(binder.load_slot_requested) != "" and not bool(binder.load_ok):
		_save_ok = false
		_save_msg = "LOAD FAILED · " + String(binder.load_error) + " · 返回主菜单"
		call_deferred("_return_to_main_menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	# 独立裁剪层：战术图不得溢出中间区域
	_plot_surface = Control.new()
	_plot_surface.name = "TacticalPlotSurface"
	_plot_surface.clip_contents = true
	_plot_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plot_surface.set_script(load("res://scripts/ui/plot_surface.gd"))
	_plot_surface.set("host", self)
	add_child(_plot_surface)
	# 方案B-32：overlay 层必须在 plot_surface 之后加入，保证弹层盖住战术图且被裁剪。
	_overlay_layer = Control.new()
	_overlay_layer.name = "OverlayLayer"
	_overlay_layer.clip_contents = true
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.set_script(load("res://scripts/ui/overlay_layer.gd"))
	_overlay_layer.set("host", self)
	_overlay_layer.visible = false
	add_child(_overlay_layer)
	_cv = self
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
	if OS.get_environment("DSH_V1_SELECT_TRACK") == "1":
		for i2 in range(_contacts.size()):
			if String((_contacts[i2] as Dictionary).get("track_id", "")) != "":
				_selected = i2
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
	# CombatService（ROE 四档）与 DamageModel（损管页）为会话外挂的 shadow 组件；
	# GameSession 当前未内置 damage_vm；损管明确标注 MODEL，不伪造。
	_combat = CombatService.new({})
	if _combat != null and bool(_combat.ready) and binder.session != null:
		binder.session.combat_service = _combat
		_combat.t = float(binder.session.now_s())
	_seed_combat_tracks()
	_roe_locked = String(binder.story_vm.get("phase", "prelude")) == "prelude"
	if OS.get_environment("DSH_V1_ROE_UNLOCK") == "1":
		_roe_locked = false
	_damage = DamageModel.new()
	var dok: bool = _damage.setup({}, "apsis")
	print("[V1 HUD] damage_model=", str(dok), " sections=", _damage.section_ids().size(), " combat=", str(_combat.ready), " roe=", String(_combat.roe) if _combat != null else "—", " roe_locked=", str(_roe_locked))
	var view := OS.get_environment("DSH_V1_VIEW")
	if view == "traffic":
		_overlay = "traffic"
		call_deferred("_traffic_demo")
	elif view == "report" or view == "prologue_complete":
		_overlay = "report"
		call_deferred("_report_demo", view == "prologue_complete")
		return
	if view == "av4412":
		_overlay = "av4412"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("entity_id", "")) == "av_4412":
				_selected = i
				break
		call_deferred("_av4412_demo")
	elif view == "chronos":
		_overlay = "chronos"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("entity_id", "")) == "chronos":
				_selected = i
				break
		call_deferred("_chronos_demo")
	elif view == "ceres_chain":
		_overlay = "optical"
		_page = "target"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("entity_id", "")) == "ceres_2":
				_selected = i
				_optical_target = "ceres_2"
				_optical_track = _track_for_contact(_contacts[i])
				break
		call_deferred("_ceres_chain_demo")
	elif view == "ceres":
		_overlay = "optical"
		_page = "target"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("entity_id", "")) == "ceres_2":
				_selected = i
				_optical_target = "ceres_2"
				_optical_track = _track_for_contact(_contacts[i])
				break
		call_deferred("_ceres_demo")
	elif view == "transponder":
		_overlay = "optical"
		_page = "facility"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("facility_id", "")) != "":
				_selected = i
				_optical_target = String((_contacts[i] as Dictionary).get("entity_id", (_contacts[i] as Dictionary).get("id", "")))
				_optical_track = _track_for_contact(_contacts[i])
				break
		call_deferred("_transponder_demo")
	elif view == "facility":
		_page = "facility"
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("facility_id", "")) != "":
				_selected = i
				break
	elif view == "combat":
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
	elif view == "save":
		_overlay = "save"
		_rebuild_save_slots()
	elif view == "optical" or view == "signal":
		_overlay = "optical"
		# 光学/信号样张选中第一个有 track 的接触；正常 UI 由用户点击接触决定 target。
		if _selected >= 0 and _selected < _contacts.size():
			var picked: Dictionary = _contacts[_selected]
			_optical_target = String(picked.get("entity_id", picked.get("id", "")))
			_optical_track = _track_for_contact(picked)
		if view == "signal":
			for i in range(_contacts.size()):
				if String((_contacts[i] as Dictionary).get("track_id", "")) != "":
					_selected = i
					_optical_target = String((_contacts[i] as Dictionary).get("entity_id", (_contacts[i] as Dictionary).get("id", "")))
					_optical_track = _track_for_contact(_contacts[i])
					break
			call_deferred("_signal_demo")

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




func _update_trigger_banner() -> void:
	if _trigger_banner != "" or binder == null:
		return
	for raw in binder.events:
		if raw is Dictionary:
			var e: Dictionary = raw
			var ty := String(e.get("type", ""))
			var pl: Dictionary = e.get("payload", {}) if e.get("payload", {}) is Dictionary else {}
			var tid := String(pl.get("trigger_id", ""))
			if tid in ["ceres_no_reply", "av4412_arrival", "chronos_unrest"] or ty.find("ceres_no_reply") >= 0 or ty.find("av4412_arrival") >= 0 or ty.find("chronos_unrest") >= 0:
				_trigger_banner = tid if tid != "" else ty
				break


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
	if _trigger_banner != "":
		Painter.label(self, top.position.x + 840, top.position.y + 66, TM.fit("TRIGGER " + _trigger_banner, 480, true, 6), 6, P.AMBER, true)
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
			Painter.label(self, tr.position.x + 8, tr.position.y + 31, TM.fit(String(c.get("cls", "")), tr.size.x - 16, true, 6), 6, P.a(P.FAINT, 0.95), true)
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
	_plot3d_rect = area
	if _plot3d == null:
		_plot3d = Plot3D.new()
		_plot3d.setup(binder)
	# 绘制区只到时间轴上方；底部时间/状态仍由父 HUD 画
	var plot_area := Rect2(area.position, Vector2(area.size.x, maxf(40.0, area.size.y - 32.0)))
	if _plot_surface != null:
		_plot_surface.position = plot_area.position
		_plot_surface.size = plot_area.size
		_plot_surface.visible = true
		_plot_surface.queue_redraw()
	var ty := area.end.y - 28.0
	draw_line(Vector2(area.position.x + 12, ty), Vector2(area.end.x - 12, ty), P.a(P.LINE2, 0.7), 1.0)
	Painter.label(self, area.position.x + 12, ty + 8, "T+00:00 · TOF 144:00:00 · WINDOW OPEN 18:00 / CLOSE 24:00", 7, P.TXT, true)
	Painter.label(self, area.position.x + 12, area.end.y - 10, "SESSION LIVE · CIC VIEW · V1 WIREFRAME · 不写 WORLD", 6, P.a(P.FAINT, 0.9), true)


func _draw_plot_surface(canvas: CanvasItem) -> void:
	if _plot3d == null or _plot_surface == null:
		return
	var local := Rect2(Vector2.ZERO, _plot_surface.size)
	var selected_id := ""
	if _selected >= 0 and _selected < _contacts.size():
		var c: Dictionary = _contacts[_selected]
		selected_id = String(c.get("track_id", ""))
	if not bool(_plot3d.draw_plot(canvas, local, binder, selected_id)):
		canvas.draw_rect(local, P.a(P.EARTH, 0.55))
		canvas.draw_rect(local, P.a(P.LINE, 0.6), false, 1.0)


func _draw_map_legacy(r: Rect2) -> void:
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
	_tabs = [{"rect": Rect2(x, r.position.y + 4, 70, 18), "page": "ship"},
		{"rect": Rect2(x + 76, r.position.y + 4, 76, 18), "page": "target"},
		{"rect": Rect2(x + 158, r.position.y + 4, 84, 18), "page": "facility"}]
	for tab in _tabs:
		var active := String(tab.get("page", "")) == _page
		var tr: Rect2 = tab["rect"]
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.10 if active else 0.04))
		draw_rect(tr, P.a(P.PH if active else P.LINE, 0.65 if active else 0.25), false, 1.0)
		var plabel := "SHIP" if String(tab.get("page", "")) == "ship" else ("TARGET" if String(tab.get("page", "")) == "target" else "FACILITY")
		Painter.label(self, tr.position.x + 6, tr.position.y + 13, plabel, 7, P.PH if active else P.FAINT, true)
	if _page == "facility":
		_draw_facility_page(r, x, right, y, c)
		return
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
	var labels := [["DAMAGE", "DAMAGE / 损管"], ["ROE", "ROE / 四档"], ["COMMS", "COMMS / 命令"], ["COMBAT", "COMBAT / 战斗"], ["NAV", "NAV / 导航"], ["OPTICAL", "OPTICAL / 光学"], ["CHRONOS", "CHRONOS / 行动"], ["AV4412", "AV-4412 / 对峙"], ["TRAFFIC", "TRAFFIC / OTC"]]
	for i in range(labels.size()):
		var bw := (r.size.x - 32.0) * 0.5 - 4.0
		var col := i % 2
		var br := Rect2(x + float(col) * (bw + 8.0), y + float(i / 2) * 26.0, bw, 21.0)
		_right_buttons.append({"rect": br, "kind": String(labels[i][0])})
		Painter.button(self, br, String(labels[i][1]), true, P.PH)
	if _sensor_msg != "":
		Painter.label(self, x, y + 83, TM.fit(_sensor_msg, r.size.x - 24, true, 7), 7, P.AMBER, true)
	Painter.label(self, x, r.end.y - 14, "LIVE SESSION · 最小交互 · 自绘 V1", 6, P.a(P.FAINT, 0.9), true)

func _draw_facility_page(r: Rect2, x: float, right: float, y: float, c: Dictionary) -> void:
	Painter.label(self, right - TM.width("FACILITY REGISTRY", true, 6), r.position.y + 14, "FACILITY REGISTRY", 6, P.a(P.AMBER, 0.9), true)
	var fid := String(c.get("facility_id", ""))
	if fid == "":
		Painter.label(self, x, y + 8, "NO FACILITY DATA · NOT READY", 10, P.AMBER)
		Painter.label(self, x, y + 26, "当前接触无注册表映射（facility_for_entity 空）", 7, P.DIM, true)
		return
	Painter.label(self, x, y + 8, TM.fit(String(c.get("facility_name", c.get("name", fid))), r.size.x - 24, false, 12), 12, P.TXT)
	Painter.label(self, x, y + 22, "设施 / FACILITY · " + String(c.get("facility_class", "")), 7, P.PH_DIM, true)
	var cy := y + 42.0
	var port_ids: Array = []
	for p in (c.get("ports", []) if c.get("ports", []) is Array else []):
		if p is Dictionary:
			port_ids.append(String((p as Dictionary).get("port_id", "")))
		else:
			port_ids.append(str(p))
	var rows := [
		["ID / CODE", fid + " · " + String(c.get("facility_code", "—"))],
		["TRANSPONDER", String(c.get("transponder_code", "—")) + " · " + String(c.get("transponder_type", "—"))],
		["IFF RECENT", _transponder_recent_text(fid, c)],
		["CLUSTER", String(c.get("cluster_id", "—")) + " · " + String(c.get("cluster_name", "—"))],
		["OWNER / SIDE", String(c.get("owner", "—")) + " · " + String(c.get("side", "—"))],
		["SERVICES", ",".join(c.get("services", []) if c.get("services", []) is Array else [])],
		["PORTS", ",".join(port_ids)],
	]
	var phys: Dictionary = c.get("physical", {}) if c.get("physical", {}) is Dictionary else {}
	var orbit: Dictionary = phys.get("orbit", {}) if phys.get("orbit", {}) is Dictionary else {}
	var sk: Dictionary = phys.get("station_keeping", {}) if phys.get("station_keeping", {}) is Dictionary else {}
	rows.append(["ORBIT", "%s · %s · pos %s" % [String(orbit.get("frame", "—")), String(orbit.get("type", "—")), str(orbit.get("position_km", []))]])
	rows.append(["MASS / RADIUS", "%.2e kg · %.2f km" % [float(phys.get("mass_kg", 0.0)), float(phys.get("radius_km", 0.0))]])
	rows.append(["STATION-KEEPING", "%s · %.1f m/s/yr" % [String(sk.get("mode", "—")), float(sk.get("dv_m_s_year", 0.0))]])
	for pair in rows:
		Painter.key_value(self, x, cy, right, String(pair[0]), TM.fit(String(pair[1]), r.size.x - 150, true, 7), P.TXT)
		cy += 15.0
	cy += 8.0
	Painter.section(self, x, cy, right, "FACILITY SOURCE")
	cy += 14.0
	Painter.label(self, x, cy, "来自 GameSession.facility_for_entity → FacilityRegistry.facility_card", 6, P.a(P.FAINT, 0.9), true)
	cy += 14.0
	Painter.label(self, x, cy, "不写 world/UI/物理；未知设施显示 NOT READY。", 6, P.a(P.FAINT, 0.9), true)
	Painter.label(self, x, r.end.y - 14, "FACILITY · " + fid + " · 只读注册表", 6, P.a(P.FAINT, 0.9), true)


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
	_load_slot("save")
	print("[V1 HUD] SAVE TEST load·", _save_overlay_msg)


func _flow_smoke_v1() -> void:
	print("[V1 HUD] FLOW SMOKE COMPLETE name=", _commander, " contacts=", _contacts.size(), " commands=", binder.commands.size() if binder != null else 0)
	get_tree().quit()


func _overlay_rect(l: Dictionary) -> Rect2:
	# 方案B-32：所有子界面共用同一弹层几何（中间区 + 右栏），四周留 6px 边距。
	var center: Rect2 = l.center
	var right: Rect2 = l.right
	var m := 6.0
	return Rect2(center.position.x + m, center.position.y + m, right.end.x - center.position.x - m * 2.0, center.size.y - m * 2.0)


const OV_PAD := 16.0
const OV_HEADER_H := 52.0
const OV_BTN_H := 24.0
const OV_BTN_GAP := 6.0


# 方案B-32：统一模态帧。页头（标题 12pt / 副标题 7pt / 右对齐状态 chip）+ 分隔线 +
# 内容区 + 页脚按钮区。返回 body/footer/header 三个 rect，子界面只往这三块里排内容。
func _overlay_frame(r: Rect2, title: String, subtitle: String, accent: Color = P.PH, chips := "", footer_rows := 1) -> Dictionary:
	var cv := _cv
	var x := r.position.x + OV_PAD
	var top := r.position.y
	Painter.label(cv, x, top + 28.0, TM.fit(title, r.size.x - 280.0, false, 12), 12, accent)
	Painter.label(cv, x, top + 43.0, TM.fit(subtitle, r.size.x - 280.0, true, 7), 7, P.a(P.AMBER, 0.85), true)
	if chips != "":
		Painter.label_right(cv, r.end.x - 112.0, top + 20.0, TM.fit(chips, 320.0, true, 7), 7, P.PH_DIM, true)
	cv.draw_line(Vector2(x - 4, top + OV_HEADER_H), Vector2(r.end.x - OV_PAD + 4, top + OV_HEADER_H), P.a(P.LINE, 0.85), 1.0)
	var rows := maxi(0, footer_rows)
	var footer_h := float(rows) * OV_BTN_H + float(maxi(0, rows - 1)) * OV_BTN_GAP
	var footer := Rect2(x, r.end.y - OV_PAD - footer_h, r.size.x - OV_PAD * 2.0, footer_h)
	var body_bottom := (footer.position.y - 14.0) if rows > 0 else (r.end.y - OV_PAD)
	var body := Rect2(x, top + OV_HEADER_H + 10.0, r.size.x - OV_PAD * 2.0, body_bottom - (top + OV_HEADER_H + 10.0))
	if rows > 0:
		cv.draw_line(Vector2(x - 4, footer.position.y - 8.0), Vector2(r.end.x - OV_PAD + 4, footer.position.y - 8.0), P.a(P.LINE, 0.7), 1.0)
	return {"body": body, "footer": footer, "header": Rect2(x, top, r.size.x - OV_PAD * 2.0, OV_HEADER_H)}


# 方案B-32：统一页脚按钮条。items = [[kind, label] 或 [kind, label, color]]；
# 宽度按可用区域等分，cols>0 时按列数换行，单行过宽时收窄居中。返回命中区（弹层局部坐标）。
func _button_bar(rect: Rect2, items: Array, cols := 0) -> Array:
	var out: Array = []
	if items.is_empty():
		return out
	var n := items.size()
	var per_row := cols if cols > 0 else n
	per_row = maxi(1, mini(per_row, n))
	var rows := int(ceil(float(n) / float(per_row)))
	var bh := minf(OV_BTN_H, (rect.size.y - OV_BTN_GAP * float(rows - 1)) / float(rows))
	var bw := floorf((rect.size.x - OV_BTN_GAP * float(per_row - 1)) / float(per_row))
	var row_w := float(per_row) * bw + OV_BTN_GAP * float(per_row - 1)
	if per_row >= n and bw > 220.0:
		bw = 220.0
		row_w = float(per_row) * bw + OV_BTN_GAP * float(per_row - 1)
	var x0 := rect.position.x + maxf(0.0, (rect.size.x - row_w) * 0.5)
	for i in range(n):
		var item: Array = items[i]
		var br := Rect2(x0 + float(i % per_row) * (bw + OV_BTN_GAP), rect.position.y + float(i / per_row) * (bh + OV_BTN_GAP), bw, bh)
		var col: Color = P.PH
		if item.size() > 2:
			col = item[2]
		Painter.button(_cv, br, String(item[1]), true, col)
		out.append({"rect": br, "kind": String(item[0])})
	return out


func _draw_overlay(l: Dictionary) -> void:
	# 方案B-32：父画布只负责定位 overlay 层，实际绘制交给 OverlayLayer（盖住 plot、可裁剪）。
	if _overlay_layer == null:
		return
	if _overlay == "":
		_overlay_layer.visible = false
		return
	var r := _overlay_rect(l)
	_overlay_local = Rect2(Vector2.ZERO, r.size)
	_overlay_offset = r.position
	_overlay_layer.position = r.position
	_overlay_layer.size = r.size
	_overlay_layer.visible = true
	_overlay_layer.queue_redraw()


func _draw_overlay_layer(cv: CanvasItem) -> void:
	_cv = cv
	var r := _overlay_local
	cv.draw_rect(r, P.a(P.PANEL, 0.985))
	cv.draw_rect(r, P.a(P.PH, 0.7), false, 1.0)
	_overlay_close = Rect2(r.end.x - 96, r.position.y + 8, 84, 20)
	Painter.button(cv, _overlay_close, "关闭 / CLOSE", true, P.RED)
	if _overlay == "damage":
		_draw_damage_overlay(r)
	elif _overlay == "roe":
		_draw_roe_overlay(r)
	elif _overlay == "comms":
		_draw_comms_overlay(r)
	elif _overlay == "optical":
		_draw_optical_overlay(r)
	elif _overlay == "chronos":
		_draw_chronos_overlay(r)
	elif _overlay == "av4412":
		_draw_av4412_overlay(r)
	elif _overlay == "traffic":
		_draw_traffic_overlay(r)
	elif _overlay == "report":
		_draw_report_overlay(r)
	elif _overlay == "complete":
		_draw_complete_overlay(r)
	elif _overlay == "combat":
		_draw_combat_overlay(r)
	elif _overlay == "save":
		_draw_save_overlay(r)
	_cv = self


func _draw_comms_overlay(r: Rect2) -> void:
	var vm: Dictionary = binder.session.comms.vm() if binder != null and binder.session != null and binder.session.comms != null else {}
	var events: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	var links: Array = vm.get("links", []) if vm.get("links", []) is Array else []
	var fr := _overlay_frame(r, "通信 / COMMS · 命令 / ORDERS", "双栏 · 消息流 / 链路明细 / 命令面板 · 不写 world", P.PH, "TARGET " + (_comms_target if _comms_target != "" else "—"))
	var body: Rect2 = fr.body
	var gap := 12.0
	var left_w := floorf((body.size.x - gap) * 0.56)
	var right_w := body.size.x - left_w - gap
	var lp := Rect2(body.position.x, body.position.y, left_w, body.size.y)
	var rp := Rect2(lp.end.x + gap, body.position.y, right_w, body.size.y)
	_cv.draw_rect(lp, P.a(P.PANEL2, 0.42))
	_cv.draw_rect(lp, P.a(P.LINE2, 0.65), false, 1.0)
	_cv.draw_rect(rp, P.a(P.PANEL2, 0.42))
	_cv.draw_rect(rp, P.a(P.LINE2, 0.65), false, 1.0)
	Painter.label(_cv, lp.position.x + 10, lp.position.y + 18, "通信 / COMMS", 11, P.PH)
	Painter.label(_cv, rp.position.x + 10, rp.position.y + 18, "命令 / ORDERS", 11, P.PH)
	var cy := lp.position.y + 36.0
	Painter.section(_cv, lp.position.x + 10, cy, lp.end.x - 10, "CHANNELS / 频道")
	cy += 15.0
	Painter.label(_cv, lp.position.x + 10, cy, "MODE     STATUS     LATENCY   EVENTS", 6, P.a(P.FAINT, 0.9), true)
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
		_cv.draw_rect(Rect2(lp.position.x + 10, y - 9, lp.size.x - 20, 13), P.a(P.PANEL, 0.35) if i % 2 == 0 else P.a(P.PANEL2, 0.2))
		Painter.label(_cv, lp.position.x + 14, y, mode, 7, P.TXT, true)
		Painter.label(_cv, lp.position.x + 80, y, st, 7, col, true)
		Painter.label(_cv, lp.position.x + 156, y, lat, 7, P.DIM, true)
		Painter.label_right(_cv, lp.end.x - 14, y, str(n_ev), 7, P.TXT, true)
	var my := cy + 5.0 * 17.0 + 14.0
	Painter.section(_cv, lp.position.x + 10, my, lp.end.x - 10, "MESSAGE STREAM / 消息")
	my += 16.0
	if events.is_empty():
		Painter.label(_cv, lp.position.x + 12, my, "NO MESSAGES · NOT READY", 7, P.FAINT, true)
	var row_capacity := mini(10, maxi(1, int((lp.end.y - my - 140.0) / 16.0)))
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
			_cv.draw_rect(Rect2(lp.position.x + 10, yy - 11, lp.size.x - 20, 14), P.a(P.PANEL, 0.30))
		Painter.label(_cv, lp.position.x + 12, yy, TM.fit("[%s 至 %s]-[%s]-[%s]" % [from, to, mode, content], lp.size.x - 24, true, 7), 7, P.TXT, true)
	# 各链真实通信文本：统一从消息流下方依次排，不再写死 y 偏移
	var chain_y := my + float(mini(row_capacity, maxi(events.size(), 0))) * 16.0 + 4.0
	var chains := [["CHRONOS CHAIN COMMS", binder.chronos_comms_lines if binder != null else []],
		["AV-4412 COMMS", binder.av4412_comms_lines if binder != null else []],
		["REPORT EVENTS", binder.report_comms_lines if binder != null else []],
		["TRAFFIC EVENTS", binder.traffic_comms_lines if binder != null else []]]
	for ch in chains:
		var lines: Array = ch[1]
		if lines.is_empty() or chain_y > lp.end.y - 190.0:
			continue
		Painter.label(_cv, lp.position.x + 12, chain_y, String(ch[0]), 6, P.AMBER, true)
		chain_y += 11.0
		for i in range(mini(2, lines.size())):
			Painter.label(_cv, lp.position.x + 12, chain_y, TM.fit(String(lines[i]), lp.size.x - 24, true, 7), 7, P.PH_DIM, true)
			chain_y += 14.0
	var link_y := lp.end.y - 132.0
	Painter.section(_cv, lp.position.x + 10, link_y, lp.end.x - 10, "LINK DETAIL / 链路明细")
	link_y += 15.0
	if links.is_empty():
		Painter.label(_cv, lp.position.x + 12, link_y, "NO LINKS · NOT READY", 7, P.FAINT, true)
	for i in range(mini(5, links.size())):
		var l: Dictionary = links[i]
		var la := String(l.get("a", l.get("from", "—")))
		var lb := String(l.get("b", l.get("to", "—")))
		var lm := String(l.get("mode", "—"))
		var st2 := "OPEN"
		if bool(l.get("disabled", false)):
			st2 = "CLOSED"
		elif bool(l.get("occluded", false)):
			st2 = "OCCLUDED"
		elif float(l.get("jam", 0.0)) >= 0.7:
			st2 = "JAMMED"
		Painter.label(_cv, lp.position.x + 12, link_y + float(i) * 14.0, TM.fit("%s → %s · %s · %s · %s" % [la, lb, lm, st2, "%.1fs" % float(l.get("latency_s", l.get("latency", 0.0)))], lp.size.x - 24, true, 7), 7, P.PH_DIM if st2 == "OPEN" else P.AMBER, true)
	# 右栏命令面板
	var px := rp.position.x + 10.0
	var py := rp.position.y + 36.0
	Painter.section(_cv, px, py, rp.end.x - 10, "COMMAND PANEL / 命令面板")
	py += 16.0
	_comms_type_buttons.clear()
	var types := ["HOLD", "NAV", "EMCON", "IFF", "ROE"]
	var tw2 := floorf((right_w - 26.0 - 4.0 * 6.0) / 5.0)
	for i in range(types.size()):
		var tr := Rect2(px + float(i) * (tw2 + 6.0), py, tw2, 20.0)
		_comms_type_buttons.append({"rect": tr, "kind": String(types[i])})
		var active := _comms_type == String(types[i])
		Painter.button(_cv, tr, String(types[i]), true, P.PH if active else P.PH_DIM)
	py += 28.0
	Painter.label(_cv, px, py, TM.fit("TARGET " + (_comms_target if _comms_target != "" else "NOT READY"), right_w - 20.0, true, 7), 7, P.TXT, true)
	py += 13.0
	Painter.label(_cv, px, py, "ISSUER apsis · MODE " + ("LD" if _comms_type in ["HOLD", "NAV"] else "SENSOR/ROE"), 6, P.DIM, true)
	py += 16.0
	var auth_txt := ""
	for lv in ["TRACK", "SOLUTION", "FIRE"]:
		var au: Dictionary = binder.session.combat_authorization(lv, _comms_target, "") if binder != null and binder.session != null else {}
		auth_txt += "%s:%s " % [lv, "OK" if bool(au.get("ok", false)) else "LOCK"]
	Painter.label(_cv, px, py, TM.fit("AUTH " + auth_txt, right_w - 20.0, true, 6), 6, P.a(P.PH_DIM, 0.9), true)
	py += 14.0
	Painter.section(_cv, px, py, rp.end.x - 10, "COMMAND QUEUE / 命令队列")
	py += 15.0
	_comms_cmd_rows.clear()
	_comms_cmd_buttons.clear()
	var cmds: Array = binder.commands if binder != null else []
	for i in range(mini(3, cmds.size())):
		var c: Dictionary = cmds[i]
		var rr := Rect2(px, py + float(i) * 17.0, right_w - 20.0, 15)
		_comms_cmd_rows.append({"rect": rr, "index": i})
		if i == _selected_cmd:
			_cv.draw_rect(rr, P.a(P.PH, 0.10))
		Painter.label(_cv, px, rr.position.y + 11, TM.fit("%s %s · %s → %s" % [String(c.get("id", "")), String(c.get("state", "")), String(c.get("actor", "")), String(c.get("target", ""))], rr.size.x, true, 7), 7, P.PH if i == _selected_cmd else P.DIM, true)
	var detail_y := rp.end.y - 140.0
	Painter.section(_cv, px, detail_y, rp.end.x - 10, "SELECTED COMMAND / 命令详情")
	detail_y += 15.0
	if _selected_cmd >= 0 and _selected_cmd < cmds.size():
		var sc: Dictionary = cmds[_selected_cmd]
		Painter.label(_cv, px, detail_y, TM.fit("ID " + String(sc.get("id", "—")) + " · " + String(sc.get("state", "—")), right_w - 20.0, true, 7), 7, P.TXT, true)
		Painter.label(_cv, px, detail_y + 13, TM.fit("ACTOR → TARGET  " + String(sc.get("actor", "—")) + " → " + String(sc.get("target", "—")), right_w - 20.0, true, 7), 7, P.TXT, true)
		Painter.label(_cv, px, detail_y + 26, TM.fit("ACTION " + String(sc.get("action", "—")) + " · MODE " + String(sc.get("mode", "—")) + " · DELAY " + String(sc.get("delay", "—")), right_w - 20.0, true, 7), 7, P.DIM, true)
	else:
		Painter.label(_cv, px, detail_y, "NO COMMAND SELECTED", 7, P.FAINT, true)
	detail_y += 46.0
	Painter.label(_cv, px, detail_y, TM.fit("ROE " + (String(_combat.roe) if _combat != null else "NOT READY") + " · ROE 不授予 FIRE 授权", right_w - 20.0, true, 7), 7, P.AMBER, true)
	# 动作按钮：统一页脚条（SEND / ABORT / REVOKE）
	_comms_send_rect = Rect2()
	var bar: Array = _button_bar(fr.footer, [["SEND", "SEND / 发送", P.PH], ["ABORT", "ABORT", P.AMBER], ["REVOKE", "REVOKE", P.RED]])
	for b in bar:
		_comms_cmd_buttons.append(b)
		if String(b.get("kind", "")) == "SEND":
			_comms_send_rect = b.get("rect", Rect2())
	if _comms_msg != "":
		Painter.label(_cv, body.position.x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_comms_msg, body.size.x, true, 7), 7, P.AMBER, true)


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


func _track_for_contact(c: Dictionary) -> Dictionary:
	if binder == null or binder.track_vm.is_empty():
		return {}
	var tr: Dictionary = binder.selected_track(c)
	if not tr.is_empty():
		return tr
	var eid := String(c.get("entity_id", ""))
	var cid := String(c.get("id", ""))
	for raw in (binder.track_vm.get("tracks", []) if binder.track_vm.get("tracks", []) is Array else []):
		if raw is Dictionary:
			var rt: Dictionary = raw
			if (eid != "" and String(rt.get("entity_id", "")) == eid) or (cid != "" and String(rt.get("batch", "")) == cid):
				return rt
	return {}


func _transponder_recent_text(fid: String, c: Dictionary) -> String:
	if _txp_reply.is_empty():
		return "NOT QUERIED"
	var target := String(_txp_reply.get("target_id", ""))
	if target != fid and target != String(c.get("entity_id", "")) and target != String(c.get("id", "")):
		return "NOT QUERIED"
	return "%s · %s · %s · crypto %s" % [String(_txp_reply.get("registration_code", "—")), String(_txp_reply.get("facility_code", "—")), String(_txp_reply.get("status", "—")), ("OK" if bool((_txp_reply.get("crypto", {}) as Dictionary).get("valid", false)) else "FAIL")]


func _ceres_demo() -> void:
	# 仅 DSH_V1_VIEW=ceres 截图样张：真实 Ceres-2 IFF + 灯语；不伪造。
	_optical_action("IFF")
	var codes: Array = []
	if binder != null and binder.session != null and binder.session.signal_service != null:
		codes = binder.session.signal_service.code_ids
	for i in range(codes.size()):
		if String(codes[i]) == "GUSHEN2_REQ":
			_signal_code_index = i
			_signal_code = "GUSHEN2_REQ"
			break
	_optical_action("LIGHT")
	_optical_action("RECV")
	_optical_action("ACK")
	print("[V1 HUD] CERES DEMO ", _optical_msg, " | trigger=", _trigger_banner)


func _transponder_demo() -> void:
	# 仅 DSH_V1_VIEW=transponder 截图样张：真实 transponder_service 询问，不伪造。
	_optical_action("IFF")
	print("[V1 HUD] TRANSPONDER DEMO ", _txp_msg)


func _ceres_action(kind: String) -> String:
	var res: Dictionary = {}
	match kind:
		"DATA_LINK":
			var sensors := 2
			if binder != null and binder.session != null and binder.session.sensor_service != null:
				var svm: Dictionary = binder.session.sensor_vm
				var ec: Dictionary = svm.get("elint", {}) if svm.get("elint", {}) is Dictionary else {}
				sensors = maxi(2, int((ec.get("counts", {}) as Dictionary).get("observations", 2)) if ec.get("counts", {}) is Dictionary else 2)
			var has_dl := binder.session.comms != null if binder != null and binder.session != null else false
			binder.ceres_ingest({"kind": "sensor", "sensors": sensors, "source": "data_link", "data_link": has_dl})
			res = binder.ceres_advance("data_link_l2", {"data_link": has_dl, "sensor_sources": sensors})
		"VIS", "ELINT", "IFF":
			res = binder.ceres_advance("identify_l3", {"kind": "identification", "source": String(kind).to_lower(), "level": "L3", "identity": "unknown"})
		"READ_LIGHT":
			res = binder.ceres_advance("read_light", {"light_code": binder.ceres_emergency_code()})
		"TYPE_L4":
			res = binder.ceres_advance("classify_l4", {})
		"RESCUE_PROMPT":
			res = binder.ceres_advance("rescue_prompt", {})
		"RESCUE":
			res = binder.ceres_rescue("rescue")
		"IGNORE":
			res = binder.ceres_rescue("ignore")
		_:
			res = {"ok": false, "reason": "unknown_action"}
	var ok := bool(res.get("ok", false))
	var trig := String(res.get("trigger_id", ""))
	_ceres_msg = "%s · %s%s" % [kind, "OK" if ok else "FAILED", "" if ok else " · " + String(res.get("reason", ""))]
	if trig != "":
		_trigger_banner = trig + " · ceres_2 · " + String(res.get("state", binder.ceres_state()))
	_ceres_msg += " · stage=" + binder.ceres_state()
	if res.has("reputation"):
		_ceres_msg += " · rep=" + JSON.stringify(res.get("reputation", {}))
	binder.refresh()
	return _ceres_msg


func _ceres_chain_demo() -> void:
	# 截图/调试：按真实 CeresChain API 顺序推进到 RESCUE_PROMPT；不自动选择救援。
	binder.ceres_advance("data_link_l2", {"data_link": true, "sensor_sources": 2})
	binder.ceres_advance("identify_l3", {"kind": "identification", "source": "vis", "level": "L3"})
	binder.ceres_advance("read_light", {"light_code": binder.ceres_emergency_code()})
	binder.ceres_advance("classify_l4", {})
	binder.ceres_advance("rescue_prompt", {})
	_ceres_msg = "CERES DEMO · stage=" + binder.ceres_state() + " · " + String(binder.last_ceres_result.get("trigger_id", ""))
	_trigger_banner = "ceres_rescue_prompt · ceres_2 · RESCUE_PROMPT"
	print("[V1 HUD] CERES CHAIN DEMO ", _ceres_msg)
	queue_redraw()


func _signal_demo() -> void:
	# 仅 DSH_V1_VIEW=signal 截图样张：走真实 ELINT/灯语 API，不伪造。
	# 样张优先选任意非友方 SIGNAL 动态 target，展示 all-sides；发送/ACK 仍由真实 target 能力决定。
	if binder != null and binder.session != null and binder.session.signal_service != null:
		# 优先真正的动态 SIGNAL target（L1/O1 等），展示任意 side；不选 harmattan 发射器。
		for i in range(_contacts.size()):
			var sc: Dictionary = _contacts[i]
			if bool(sc.get("signal_target", false)):
				_selected = i
				var seid := String(sc.get("entity_id", ""))
				if seid == "":
					seid = String(sc.get("id", ""))
				_optical_target = seid
				_optical_track = _track_for_contact(sc)
				break
		if _optical_target == "":
			for raw_t in (binder.session.signal_service.targets if binder.session.signal_service.targets is Array else []):
				if raw_t is Dictionary and String((raw_t as Dictionary).get("side", "unknown")) != "friend":
					_optical_target = String((raw_t as Dictionary).get("id", ""))
					break
		if _optical_target == "":
			var svm2: Dictionary = binder.session.signal_service.vm()
			var stargets: Array = svm2.get("targets", []) if svm2.get("targets", []) is Array else []
			for raw_t in stargets:
				if raw_t is Dictionary and not (raw_t.get("emissions", []) as Array).is_empty() and not bool((raw_t as Dictionary).get("occluded", false)):
					var tid := String((raw_t as Dictionary).get("id", ""))
					if tid != "":
						_optical_target = tid
						break
			if _optical_target != "":
				for i in range(_contacts.size()):
					if String((_contacts[i] as Dictionary).get("entity_id", (_contacts[i] as Dictionary).get("id", ""))) == _optical_target:
						_selected = i
						_optical_track = _track_for_contact(_contacts[i])
						break
	print("[V1 HUD] SIGNAL DEMO start target=", _optical_target, " contacts=", _contacts.size(), " sensor=", str(binder != null and binder.session != null and binder.session.sensor_service != null), " signal=", str(binder != null and binder.session != null and binder.session.signal_service != null))
	_optical_action("ELINT")
	_optical_action("LIGHT")
	_optical_action("RECV")
	_optical_action("ACK")
	print("[V1 HUD] SIGNAL DEMO ", _signal_msg)


func _draw_ceres_panel(sr: Rect2) -> void:
	_cv.draw_rect(sr, P.a(P.PANEL, 0.98))
	_cv.draw_rect(sr, P.a(P.AMBER, 0.65), false, 1.0)
	var vm: Dictionary = binder.ceres_vm() if binder != null else {}
	var stage := String(vm.get("state", "NOT READY"))
	Painter.label(_cv, sr.position.x + 10, sr.position.y + 18, "CERES / 谷神-2 识别链 · STAGE " + stage, 9, P.AMBER)
	var chain := ["L1", "L2", "L3", "LIGHT_READ", "L4_TYPE", "RESCUE_PROMPT"]
	var found := false
	for i in range(chain.size()):
		var st := String(chain[i])
		var cx := sr.position.x + 10.0 + float(i) * (sr.size.x - 20.0) / 6.0
		var active := stage == st or (stage in ["RESCUED", "IGNORED", "COMPLETE"] and st == "RESCUE_PROMPT")
		if active and not found:
			found = true
		_cv.draw_rect(Rect2(cx, sr.position.y + 28, (sr.size.x - 20.0) / 6.0 - 3, 16), P.a(P.AMBER if active else P.LINE, 0.20 if active else 0.06))
		_cv.draw_rect(Rect2(cx, sr.position.y + 28, (sr.size.x - 20.0) / 6.0 - 3, 16), P.a(P.AMBER if active else P.LINE, 0.75 if active else 0.25), false, 1.0)
		Painter.label(_cv, cx + 4, sr.position.y + 40, st, 6, P.PH if active else P.FAINT, true)
	var key := "ceres.fault"
	match stage:
		"L2":
			key = "ceres.l2"
		"L3":
			key = "ceres.identify_prompt"
		"LIGHT_READ":
			key = "ceres.vis_read"
		"L4_TYPE":
			key = "ceres.l3_l4"
		"RESCUE_PROMPT":
			key = "ceres.rescue_prompt"
		"RESCUED":
			key = "ceres.rescue_yes"
		"IGNORED":
			key = "ceres.rescue_no"
	var txt: String = binder.ceres_text(key) if binder != null else ""
	var lines := _wrap_text_cjk(txt, sr.size.x - 20.0, 7, true)
	var ty := sr.position.y + 58.0
	for i in range(mini(lines.size(), 4)):
		Painter.label(_cv, sr.position.x + 10, ty, lines[i], 7, P.TXT, true)
		ty += 13.0
	Painter.label(_cv, sr.position.x + 10, sr.end.y - 42, "EMERGENCY CODE " + (binder.ceres_emergency_code() if binder != null else "—") + " · EVIDENCE %d · TRIGGERS %s" % [int((vm.get("evidence", []) as Array).size()), ",".join(vm.get("trigger_ids", []) if vm.get("trigger_ids", []) is Array else [])], 6, P.PH_DIM, true)
	var rep: Dictionary = vm.get("reputation", {}) if vm.get("reputation", {}) is Dictionary else {}
	Painter.label(_cv, sr.position.x + 10, sr.end.y - 30, "REPUTATION " + JSON.stringify(rep) + " · 不自动完成", 6, P.a(P.FAINT, 0.9), true)
	if _ceres_msg != "":
		Painter.label(_cv, sr.position.x + 10, sr.end.y - 16, TM.fit(_ceres_msg, sr.size.x - 20, true, 6), 6, P.AMBER, true)


func _wrap_text_cjk(text: String, max_px: float, size := 7, mono := true) -> Array:
	# 方案B-32：按真实像素宽度折行。CJK 可任意字间断行，优先在标点/空格后断，
	# 避免旧实现「未遇到标点就不断行」导致长段文字溢出面板。
	var out: Array = []
	if text == "":
		return out
	var breaks := ["，", "。", "；", "、", "：", "）", "】", " ", ",", ".", ";", "/", "·", "-"]
	var cur := ""
	var last_break := -1
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		cur += ch
		if ch in breaks:
			last_break = cur.length()
		if TM.width(cur, mono, size) > max_px and cur.length() > 1:
			if last_break > 0 and last_break < cur.length():
				out.append(cur.substr(0, last_break))
				cur = cur.substr(last_break)
			else:
				out.append(cur.substr(0, cur.length() - 1))
				cur = ch
			last_break = -1
	if cur != "":
		out.append(cur)
	return out


func _av4412_track() -> Dictionary:
	if binder == null or binder.session == null:
		return {}
	var e: Dictionary = {}
	for raw in (binder.snapshot.get("entities", []) if binder.snapshot.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "av_4412":
			e = raw
			break
	var pos: Array = e.get("pos_km", [0.0, 0.0, 0.0]) if e.get("pos_km", []) is Array else [0.0, 0.0, 0.0]
	var vel: Array = e.get("vel_kmps", [0.0, 0.0, 0.0]) if e.get("vel_kmps", []) is Array else [0.0, 0.0, 0.0]
	var radar := false
	var ss: Dictionary = binder.sensor_state() if binder != null else {}
	radar = bool(ss.get("radar", false))
	return {"t": float(binder.session.now_s()) if binder != null and binder.session != null else 0.0,
		"pos": pos, "vel": vel, "window_open": true, "radar_active": radar}


func _traffic_action(kind: String) -> void:
	if binder == null or not binder.traffic_ready:
		_traffic_msg = "TRAFFIC NOT READY"
		return
	var track := "apsis"
	if _selected >= 0 and _selected < _contacts.size():
		var c: Dictionary = _contacts[_selected]
		if String(c.get("track_id", "")) != "":
			track = String(c.get("track_id"))
		elif String(c.get("entity_id", "")) != "":
			track = String(c.get("entity_id"))
		elif String(c.get("id", "")) != "":
			track = String(c.get("id"))
	var lane := _traffic_lane
	if lane == "":
		var lr: Array = binder.traffic_lane_rows()
		lane = String((lr[0] as Dictionary).get("lane_id", "")) if not lr.is_empty() else ""
	var otc := _traffic_otc
	var row_otc: Dictionary = {}
	for raw in binder.traffic_otc_rows():
		if raw is Dictionary and String((raw as Dictionary).get("facility_id", "")) == otc:
			row_otc = raw
			break
	var res: Dictionary = {}
	match kind:
		"REQUEST":
			var opts := {"direction": String(binder.traffic_lane(lane).get("direction", "bidirectional"))}
			if not row_otc.is_empty():
				opts["facility_code"] = String(row_otc.get("facility_code", ""))
				opts["transponder_code"] = String(row_otc.get("transponder_code", ""))
			res = binder.traffic_request(track, lane, opts)
			if bool(res.get("ok", false)):
				_traffic_request_id = String(res.get("request_id", ""))
		"PERMIT":
			res = binder.traffic_permit(_traffic_request_id, {})
			if bool(res.get("ok", false)):
				_traffic_clearance_id = String(res.get("clearance_id", ""))
		"OCCUPY":
			res = binder.traffic_occupy(lane, track, {"clearance_id": _traffic_clearance_id, "width": 1})
		"RELEASE":
			res = binder.traffic_release(lane, track)
		"DISGUISE":
			var d := {"lane_id": lane, "claimed_class": "freighter"}
			if not row_otc.is_empty():
				d["transponder_code"] = String(row_otc.get("transponder_code", ""))
				d["facility_code"] = String(row_otc.get("facility_code", ""))
				d["claimed_class"] = String(row_otc.get("facility_class", "freighter"))
			res = binder.traffic_disguise(track, d, {})
		_:
			res = {"ok": false, "reason": "unknown_action"}
	_traffic_last = res.duplicate(true)
	_traffic_msg = kind + " " + lane + " · " + ("OK" if bool(res.get("ok", false)) else "FAILED · " + String(res.get("reason", "")))
	if kind == "DISGUISE" and bool(res.get("ok", false)):
		_traffic_msg += " · detected=" + str(bool(res.get("detected", false))) + " p=" + ("%.2f" % float(res.get("probability", 0.0))) + " anomalies=" + str((res.get("anomalies", []) as Array).size())
	print("[V1 HUD] TRAFFIC ", _traffic_msg)
	queue_redraw()


func _traffic_demo() -> void:
	# 仅截图/调试：真实 TrafficControlService fallback，不伪造 OTC/航道。
	if binder == null or not binder.traffic_ready:
		return
	var lanes: Array = binder.traffic_lane_rows()
	var otcs: Array = binder.traffic_otc_rows()
	_traffic_otc = String((otcs[0] as Dictionary).get("facility_id", "")) if not otcs.is_empty() else ""
	_traffic_lane = String((lanes[0] as Dictionary).get("lane_id", "")) if not lanes.is_empty() else ""
	_traffic_action("REQUEST")
	if bool(_traffic_last.get("ok", false)):
		_traffic_action("PERMIT")
		_traffic_action("OCCUPY")
	_traffic_action("DISGUISE")
	_traffic_msg = "TRACE · lane=" + _traffic_lane + " · req=" + _traffic_request_id + " · clr=" + _traffic_clearance_id + " · " + _traffic_msg
	print("[V1 HUD] TRAFFIC DEMO ", _traffic_msg, " source=", binder.traffic_source)
	queue_redraw()


func _draw_traffic_overlay(r: Rect2) -> void:
	var vm0: Dictionary = binder.traffic_vm() if binder != null and binder.traffic_ready else {}
	var chips := ""
	if binder != null and binder.traffic_ready:
		chips = "SOURCE " + String(binder.traffic_source).to_upper() + " · t=" + ("%.0f" % float(vm0.get("t", 0.0)))
	var fr := _overlay_frame(r, "TRAFFIC / OTC · 交通管制", "OTC 19 · lanes 18 · NPC/queue · REQUEST/PERMIT/OCCUPY/RELEASE · DISGUISE anomalies", P.PH, chips)
	var body: Rect2 = fr.body
	var x := body.position.x
	if binder == null or not binder.traffic_ready:
		Painter.label(_cv, x, body.position.y + 20, "TRAFFIC NOT READY · no TrafficControlService", 11, P.AMBER)
		return
	var vm: Dictionary = vm0
	var gap := 12.0
	var col_w := floorf((body.size.x - gap * 2.0) / 3.0)
	var lx := x
	var mx := x + col_w + gap
	var rx := x + col_w * 2.0 + gap * 2.0
	var top := body.position.y
	var bottom := body.end.y
	Painter.section(_cv, lx, top, lx + col_w, "OTC / 19 · CLUSTER")
	_traffic_otc_rows.clear()
	var grouped: Dictionary = {}
	for raw in binder.traffic_otc_rows():
		if raw is Dictionary:
			var cid := String((raw as Dictionary).get("parent_cluster", "—"))
			if not grouped.has(cid):
				grouped[cid] = []
			(grouped[cid] as Array).append(raw)
	var oy := top + 15.0
	for cid in grouped.keys():
		if oy > bottom - 16.0:
			break
		Painter.label(_cv, lx, oy, String(cid), 7, P.PH_DIM, true)
		oy += 11.0
		for raw2 in (grouped[cid] as Array):
			if oy > bottom - 6.0:
				break
			var o: Dictionary = raw2
			var rr := Rect2(lx, oy - 9.0, col_w - 4.0, 20.0)
			_traffic_otc_rows.append({"rect": rr, "id": String(o.get("facility_id", ""))})
			if String(o.get("facility_id", "")) == _traffic_otc:
				_cv.draw_rect(rr, P.a(P.PH, 0.10))
			Painter.label(_cv, lx + 4, oy, TM.fit(String(o.get("facility_id", "")) + " · " + String(o.get("facility_code", "")), col_w - 10, true, 7), 7, P.PH if String(o.get("facility_id", "")) == _traffic_otc else P.TXT, true)
			var phys_o: Dictionary = o.get("physical", {}) if o.get("physical", {}) is Dictionary else {}
			var orb_o: Dictionary = phys_o.get("orbit", {}) if phys_o.get("orbit", {}) is Dictionary else {}
			var orb_txt := String(orb_o.get("type", "")) + " · " + str(orb_o.get("position_km", []))
			Painter.label(_cv, lx + 8, oy + 10, TM.fit(String(o.get("transponder_code", "")) + " · " + orb_txt, col_w - 14, true, 6), 6, P.a(P.FAINT, 0.9), true)
			oy += 20.0
	Painter.section(_cv, mx, top, mx + col_w, "LANES / 18")
	_traffic_lane_rows.clear()
	var ly := top + 15.0
	for raw3 in binder.traffic_lane_rows():
		if ly > bottom - 6.0:
			break
		var lane3: Dictionary = raw3
		var lid := String(lane3.get("lane_id", ""))
		var occ: Dictionary = binder.traffic_service.lane_occupancy(lid) if binder.traffic_service != null else {}
		var rr2 := Rect2(mx, ly - 9.0, col_w - 4.0, 20.0)
		_traffic_lane_rows.append({"rect": rr2, "id": lid})
		if lid == _traffic_lane:
			_cv.draw_rect(rr2, P.a(P.AMBER, 0.10))
		Painter.label(_cv, mx + 4, ly, TM.fit(lid + " · " + String(lane3.get("name", "")), col_w - 10, true, 7), 7, P.AMBER if lid == _traffic_lane else P.TXT, true)
		var freetxt := "free %d/%d · queue %d" % [int(occ.get("free", occ.get("free_capacity", 0))), int(lane3.get("capacity", 0)), int((occ.get("queue", []) as Array).size()) if occ.get("queue", []) is Array else int(occ.get("queue_count", 0))]
		var from_e: Dictionary = lane3.get("from", {}) if lane3.get("from", {}) is Dictionary else {}
		var to_e: Dictionary = lane3.get("to", {}) if lane3.get("to", {}) is Dictionary else {}
		var wins: Array = lane3.get("windows", []) if lane3.get("windows", []) is Array else []
		var win_txt := "—"
		if not wins.is_empty() and wins[0] is Dictionary:
			win_txt = "%.0f–%.0f" % [float((wins[0] as Dictionary).get("open_t", 0.0)), float((wins[0] as Dictionary).get("close_t", 0.0))]
		Painter.label(_cv, mx + 8, ly + 9, TM.fit(String(from_e.get("id", "")) + "→" + String(to_e.get("id", "")) + " · cap " + str(lane3.get("capacity", "")) + " · win " + win_txt + " · pri " + str(lane3.get("priority", "")) + " · " + freetxt, col_w - 14, true, 6), 6, P.a(P.FAINT, 0.9), true)
		ly += 20.0
	var ry := top
	Painter.section(_cv, rx, ry, rx + col_w, "NPC / QUEUE / OCCUPANCY")
	ry += 15.0
	var nrow := 0
	for raw4 in binder.traffic_npc_rows():
		if nrow >= 4:
			break
		var n: Dictionary = raw4
		Painter.label(_cv, rx, ry, TM.fit(String(n.get("npc_id", "")) + " · " + String(n.get("callsign", "")) + " · " + String(n.get("ship_class", "")), col_w - 4.0, true, 7), 7, P.TXT, true)
		ry += 12.0
		nrow += 1
	var occrows: Array = vm.get("occupancies", []) if vm.get("occupancies", []) is Array else []
	for i in range(mini(3, occrows.size())):
		var o2: Dictionary = occrows[i]
		Painter.label(_cv, rx, ry, TM.fit("OCC " + String(o2.get("lane_id", "")) + " · " + String(o2.get("occupant_id", o2.get("track_id", ""))), col_w - 4.0, true, 6), 6, P.PH_DIM, true)
		ry += 11.0
	Painter.label(_cv, rx, ry, TM.fit("SEL OTC " + (_traffic_otc if _traffic_otc != "" else "—") + " · LANE " + (_traffic_lane if _traffic_lane != "" else "—"), col_w - 4.0, true, 7), 7, P.PH, true)
	ry += 18.0
	Painter.section(_cv, rx, ry, rx + col_w, "DISGUISE / ANOMALY")
	ry += 14.0
	if _traffic_last.is_empty():
		Painter.label(_cv, rx, ry, "NO DISGUISE RECORD · anomalies —", 7, P.FAINT, true)
	else:
		Painter.label(_cv, rx, ry, TM.fit("p=" + ("%.2f" % float(_traffic_last.get("probability", 0.0))) + " · detected=" + str(bool(_traffic_last.get("detected", false))) + " · anomalies=" + ",".join(_traffic_last.get("anomalies", []) if _traffic_last.get("anomalies", []) is Array else []), col_w - 4.0, true, 7), 7, P.TXT, true)
		ry += 12.0
		Painter.label(_cv, rx, ry, TM.fit("clues=" + str((_traffic_last.get("clue_ids", []) as Array).size()) + " · clue ids " + ",".join(_traffic_last.get("clue_ids", []) if _traffic_last.get("clue_ids", []) is Array else []), col_w - 4.0, true, 6), 6, P.PH_DIM, true)
	ry += 16.0
	Painter.label(_cv, rx, ry, "EVENTS", 7, P.PH_DIM, true)
	ry += 11.0
	var evs2: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	for i in range(maxi(0, evs2.size() - 3), evs2.size()):
		if ry > bottom - 4.0:
			break
		Painter.label(_cv, rx, ry, TM.fit(JSON.stringify((evs2[i] as Dictionary).get("payload", {})), col_w - 4.0, true, 6), 6, P.a(P.FAINT, 0.9), true)
		ry += 10.0
	_traffic_buttons.clear()
	var b_labels := [["REQUEST", "REQUEST"], ["PERMIT", "PERMIT"], ["OCCUPY", "OCCUPY"], ["RELEASE", "RELEASE"], ["DISGUISE", "DISGUISE"]]
	var items: Array = []
	for i in range(b_labels.size()):
		items.append([String(b_labels[i][0]), String(b_labels[i][1]), P.PH if i < 4 else P.AMBER])
	_traffic_buttons = _button_bar(fr.footer, items)
	if _traffic_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_traffic_msg, body.size.x, true, 7), 7, P.AMBER, true)


func _report_action(kind: String) -> void:
	if binder == null or not binder.report_ready:
		_report_msg = "REPORT NOT READY"
		return
	match kind:
		"COMPOSE":
			var res: Dictionary = binder.report_compose()
			_report_msg = "COMPOSE · " + ("OK · branch=" + String(res.get("branch_hint", "")) if bool(res.get("ok", false)) else "FAILED · " + String(res.get("reason", "")))
		"SUBMIT", "WITHHOLD":
			var c := "submit_evidence" if kind == "SUBMIT" else "withhold_evidence"
			var res2: Dictionary = binder.report_choose(c)
			_report_msg = kind + " · " + ("OK · " + c if bool(res2.get("ok", false)) else "FAILED · " + String(res2.get("reason", "")))
		"COMPLETE":
			var vm2: Dictionary = binder.report_vm()
			if bool(vm2.get("prologue_complete", false)):
				_overlay = "complete"
				_report_msg = "PROLOGUE COMPLETE · demo only · 不切主菜单/不真结局"
				binder.report_comms_lines.append("[ID13 至 OCJC]-[RDO]-[PROLOGUE COMPLETE · demo only]")
			else:
				_report_msg = "COMPLETE BLOCKED · COMPOSE REQUIRED"
		"CLOSE":
			_overlay = ""
		_:
			_report_msg = "UNKNOWN"
	queue_redraw()


func _report_demo(show_complete: bool) -> void:
	# 截图/调试：用真实 chain 状态汇总给 AfterActionReport；不伪造结局。
	if binder == null:
		return
	# Ceres: 推进到 RESCUED
	for a in ["data_link_l2", "identify_l3", "read_light", "classify_l4", "rescue_prompt", "rescue"]:
		var pl := {}
		if a == "data_link_l2":
			pl = {"data_link": true, "sensor_sources": 2}
		elif a == "identify_l3":
			pl = {"kind": "identification", "source": "vis", "level": "L3"}
		elif a == "read_light":
			pl = {"light_code": binder.ceres_emergency_code()}
		binder.ceres_advance(a, pl)
	# Chronos: 推进到 ACTIONS 并完成 evac/blackbox/telemetry
	for a2 in ["port_comm", "action_evac", "private_comm", "choose_accept", "open_actions", "evac", "blackbox", "telemetry"]:
		binder.chronos_advance(a2, {})
	# AV: 真实轨道/窗口/接触/谈判/QUESTION
	binder.av4412_update_orbit(_av4412_track())
	binder.av4412_advance("window_open", {})
	var radar_now := bool(binder.av4412_chain.radar_active) if binder.av4412_chain != null else false
	binder.av4412_advance("early_radar" if radar_now else "passive_contact", {})
	binder.av4412_advance("comms", {})
	binder.av4412_advance("negotiation", {})
	binder.av4412_advance("question", {})
	# 真实 ELINT/通信证据（若 core signal_service 可用），不伪造。
	if binder.session != null and binder.session.signal_service != null:
		binder.session.signal_intercept("harmattan")
		binder.session.signal_df("harmattan")
		if binder.session.track_table != null:
			binder.session.tick(0.1)
	binder.report_sync()
	binder.report_choose("withhold_evidence")
	var comp: Dictionary = binder.report_compose()
	_overlay = "complete" if show_complete else "report"
	_report_msg = "REPORT DEMO · branch=" + binder.report_branch_hint() + " · compose=" + str(bool(comp.get("ok", false)))
	_trigger_banner = "report_composed · " + binder.report_branch_hint()
	print("[V1 HUD] REPORT DEMO ", _report_msg, " missing=", str(binder.report_missing()))
	queue_redraw()


func _draw_report_overlay(r: Rect2) -> void:
	var fr := _overlay_frame(r, "AFTER ACTION REPORT / 行动报告", "chain 汇总 → report/上报选择/branch hint · 原文本自 story_report · 不伪造结局", P.PH)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	if binder == null or not binder.report_ready:
		Painter.label(_cv, x, y + 20, "REPORT NOT READY · no AfterActionReport", 11, P.AMBER)
		return
	var vm: Dictionary = binder.report_vm()
	var inputs: Dictionary = vm.get("inputs", {}) if vm.get("inputs", {}) is Dictionary else {}
	var gap := 16.0
	var left_w := floorf((body.size.x - gap) * 0.46)
	var right_x := x + left_w + gap
	var right_w := body.size.x - left_w - gap
	var ly := y
	Painter.section(_cv, x, ly, x + left_w, "RECORD / 行动清单")
	ly += 17.0
	var ceres := String(inputs.get("ceres", ""))
	var ch: Dictionary = inputs.get("chronos", {}) if inputs.get("chronos", {}) is Dictionary else {}
	var ev: Array = inputs.get("evidence", []) if inputs.get("evidence", []) is Array else []
	var lines := [
		"CERES-2 救援： " + (ceres.to_upper() if ceres != "" else "—"),
		"CHRONOS 撤离： " + ("YES" if bool(ch.get("evac", false)) else "NO"),
		"CHRONOS 黑匣子： " + ("YES" if bool(ch.get("blackbox", false)) else "NO"),
		"CHRONOS 遥测： " + ("YES" if bool(ch.get("telemetry", false)) else "NO"),
		"AV-4412 选项： " + (String(inputs.get("av4412", "")).to_upper() if String(inputs.get("av4412", "")) != "" else "—"),
		"证据： " + (",".join(ev) if not ev.is_empty() else "—"),
		"ID13 状态： " + String(inputs.get("legal_status", "UNLISTED")),
	]
	for line in lines:
		Painter.label(_cv, x, ly, TM.fit(line, left_w - 8.0, true, 10), 10, P.TXT, true)
		ly += 16.0
	ly += 6.0
	Painter.section(_cv, x, ly, x + left_w, "MISSING ITEMS")
	ly += 16.0
	var miss: Array = vm.get("missing_items", []) if vm.get("missing_items", []) is Array else binder.report_missing()
	if miss.is_empty():
		Painter.label(_cv, x, ly, "MISSING · NONE", 10, P.PH, true)
	else:
		for m in miss:
			if ly > body.end.y - 12.0:
				break
			Painter.label(_cv, x, ly, "· " + String(m), 9, P.AMBER, true)
			ly += 13.0
	var ry := y
	Painter.section(_cv, right_x, ry, right_x + right_w, "REPORT BODY / 原文")
	ry += 16.0
	var rtxt: String = binder.report_text()
	if rtxt == "":
		rtxt = "NO REPORT YET · COMPOSE REPORT"
	var rtb := bool((vm.get("report", {}) as Dictionary).get("tbd", false)) if vm.get("report", {}) is Dictionary else false
	if rtb or rtxt == "TBD":
		rtxt = "TBD · report.standard_missing_tbd · 不伪造报告正文"
	var rlines := _wrap_text_cjk(rtxt, right_w, 9, true)
	for line2 in rlines:
		if ry > body.end.y - 96.0:
			break
		Painter.label(_cv, right_x, ry, line2, 9, P.TXT, true)
		ry += 14.0
	ry += 6.0
	var bh: String = binder.report_branch_hint()
	Painter.label(_cv, right_x, ry, TM.fit("BRANCH HINT " + (bh if bh != "" else "—"), right_w, true, 10), 10, P.AMBER, true)
	ry += 15.0
	var binfo: Dictionary = binder.report_branch_info(bh)
	Painter.label(_cv, right_x, ry, TM.fit("BRANCH " + String(binfo.get("label", "—")), right_w, true, 8), 8, P.PH_DIM, true)
	ry += 14.0
	var btext: String = binder.report_branch_text(bh)
	if btext != "":
		var blines := _wrap_text_cjk(btext, right_w, 8, true)
		for j in range(mini(3, blines.size())):
			Painter.label(_cv, right_x, ry, TM.fit(blines[j], right_w, true, 8), 8, P.DIM, true)
			ry += 12.0
	_report_buttons.clear()
	var labels := [["COMPOSE", "COMPOSE REPORT"], ["SUBMIT", "SUBMIT EVIDENCE"], ["WITHHOLD", "WITHHOLD EVIDENCE"], ["COMPLETE", "COMPLETE PROLOGUE"]]
	var items: Array = []
	for i in range(labels.size()):
		items.append([String(labels[i][0]), String(labels[i][1]), P.PH])
	_report_buttons = _button_bar(fr.footer, items)
	if _report_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_report_msg, body.size.x, true, 8), 8, P.AMBER, true)


func _draw_complete_overlay(r: Rect2) -> void:
	var fr := _overlay_frame(r, "序章完成 / PROLOGUE COMPLETE", "DEMO · 仅显示完成画面/分支提示 · 不切主菜单/不执行真结局", P.PH)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	if binder == null or not binder.report_ready:
		Painter.label(_cv, x, y + 20, "REPORT NOT READY", 11, P.AMBER)
		return
	var vm: Dictionary = binder.report_vm()
	var report: Dictionary = vm.get("report", {}) if vm.get("report", {}) is Dictionary else {}
	var rh: String = binder.report_branch_hint()
	Painter.section(_cv, x, y, body.end.x, "PROLOGUE RESULT")
	var ty := y + 18.0
	Painter.label(_cv, x, ty, TM.fit("BRANCH HINT " + (rh if rh != "" else "—"), body.size.x, true, 11), 11, P.AMBER, true)
	ty += 18.0
	Painter.label(_cv, x, ty, "ENDING EXECUTED false · PROLOGUE COMPLETE true", 8, P.DIM, true)
	ty += 22.0
	var body_txt := String(report.get("zh", ""))
	if body_txt == "" or bool(report.get("tbd", false)):
		body_txt = "TBD · 报告正文未提供，不伪造"
	var lines := _wrap_text_cjk(body_txt, body.size.x, 9, true)
	for line in lines:
		if ty > body.end.y - 48.0:
			break
		Painter.label(_cv, x, ty, line, 10, P.TXT, true)
		ty += 15.0
	ty += 10.0
	Painter.section(_cv, x, ty, body.end.x, "ACTION SUMMARY")
	ty += 16.0
	var inputs: Dictionary = vm.get("inputs", {}) if vm.get("inputs", {}) is Dictionary else {}
	Painter.label(_cv, x, ty, TM.fit("CERES " + String(inputs.get("ceres", "—")) + " · AV " + String(inputs.get("av4412", "—")) + " · EVIDENCE " + ",".join(inputs.get("evidence", []) if inputs.get("evidence", []) is Array else []), body.size.x, true, 8), 8, P.PH_DIM, true)
	ty += 14.0
	Painter.label(_cv, x, ty, TM.fit("ID13 STATUS " + String(inputs.get("legal_status", "UNLISTED")) + " · 不写 world/不执行结局", body.size.x, true, 8), 8, P.a(P.FAINT, 0.9), true)
	_report_buttons.clear()
	_report_buttons = _button_bar(fr.footer, [["CLOSE", "返回 HUD / CLOSE"]])
	if _report_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_report_msg, body.size.x, true, 8), 8, P.AMBER, true)


func _draw_av4412_overlay(r: Rect2) -> void:
	var fr := _overlay_frame(r, "AV-4412 / 对峙 · 谈判", "四选项大字可读 · 原文/后续 10pt · TBD 明示 · 不自动开火/推进", P.PH)
	var body: Rect2 = fr.body
	var x := body.position.x
	if binder == null or not binder.av4412_ready:
		Painter.label(_cv, x, body.position.y + 20, "AV4412 NOT READY · no AV4412Chain", 11, P.AMBER)
		return
	var vm: Dictionary = binder.av4412_vm()
	var state := String(vm.get("state", "NOT READY"))
	var states := ["ORBIT_DEPARTURE", "WINDOW_OPEN", "CONTACT", "COMMS", "NEGOTIATION", "OPTION", "RESOLUTION"]
	var active_i := 0
	match state:
		"ORBIT_DEPARTURE": active_i = 0
		"WINDOW_OPEN": active_i = 1
		"EARLY_RADAR", "PASSIVE_CONTACT": active_i = 2
		"COMMS": active_i = 3
		"NEGOTIATION": active_i = 4
		"STRONG", "STANDARD", "QUESTION", "RETREAT": active_i = 5
		"RESOLUTION", "REPORT_HANDOFF": active_i = 6
	var sy := body.position.y
	var scw := floorf((body.size.x - 6.0 * float(states.size() - 1)) / float(states.size()))
	for i in range(states.size()):
		var cr := Rect2(x + float(i) * (scw + 6.0), sy, scw, 19)
		_cv.draw_rect(cr, P.a(P.AMBER if i <= active_i else P.LINE, 0.16 if i <= active_i else 0.05))
		_cv.draw_rect(cr, P.a(P.AMBER if i == active_i else P.LINE, 0.75 if i == active_i else 0.25), false, 1.0)
		Painter.label(_cv, cr.position.x + 4, cr.position.y + 14, TM.fit(String(states[i]), scw - 8.0, true, 7), 7, P.PH if i == active_i else P.FAINT, true)
	var gap := 16.0
	var left_w := floorf(body.size.x * 0.58)
	var right_x := x + left_w + gap
	var right_w := body.size.x - left_w - gap
	var body_y := sy + 30.0
	Painter.section(_cv, x, body_y, x + left_w, "当前原文 / CURRENT TEXT")
	var ty := body_y + 17.0
	var keys: Array = []
	match state:
		"ORBIT_DEPARTURE", "WINDOW_OPEN": keys = ["av4412.contact_rules"]
		"EARLY_RADAR", "PASSIVE_CONTACT", "COMMS": keys = ["av4412.opening"]
		"NEGOTIATION": keys = ["av4412.negotiation_rules"]
		"STRONG": keys = ["av4412.strong", "av4412.strong_aftermath"]
		"STANDARD": keys = ["av4412.standard", "av4412.standard_aftermath"]
		"QUESTION": keys = ["av4412.question", "av4412.question_aftermath"]
		"RETREAT": keys = ["av4412.retreat_rules"]
	var opt_h := maxf(4.0 * 44.0, body.size.y * 0.42)
	var options_y := body.end.y - opt_h
	for k in keys:
		var txt: String = binder.av4412_text(String(k))
		if txt == "" or txt == "TBD":
			txt = "TBD · " + String(k) + " · 未提供原文（不伪造）"
		var lines := _wrap_text_cjk(txt, left_w, 10, true)
		for line in lines:
			if ty > options_y - 16.0:
				break
			Painter.label(_cv, x, ty, line, 10, P.TXT, true)
			ty += 15.0
		ty += 4.0
	Painter.section(_cv, x, options_y - 2.0, x + left_w, "OPTIONS / 四选项 · 点击选择")
	var card_y := options_y + 15.0
	var card_h := maxf(34.0, (body.end.y - card_y - 3.0 * 3.0) / 4.0)
	_av4412_buttons.clear()
	for i in range(4):
		var opt: String = String(["strong", "standard", "question", "retreat"][i])
		var card := Rect2(x, card_y + float(i) * (card_h + 3.0), left_w, card_h)
		_av4412_buttons.append({"rect": card, "kind": String(opt).to_upper()})
		var selected: bool = String(vm.get("option", "")) == opt
		_cv.draw_rect(card, P.a(P.PANEL2, 0.75 if selected else 0.5))
		_cv.draw_rect(card, P.a(P.AMBER if selected else P.LINE2, 0.9 if selected else 0.55), false, 1.0)
		Painter.label(_cv, card.position.x + 8, card.position.y + 15, ("▶ " if selected else "") + String(opt).to_upper(), 11, P.PH if selected else P.TXT, true)
		var ot: String = binder.av4412_text("av4412." + opt)
		if ot == "" or ot == "TBD":
			ot = "TBD · 未提供原文（不伪造）"
		var ol := _wrap_text_cjk(ot, card.size.x - 16.0, 10, true)
		for j in range(mini(2, ol.size())):
			Painter.label(_cv, card.position.x + 8, card.position.y + 30 + float(j) * 13.0, TM.fit(ol[j], card.size.x - 16.0, true, 10), 10, P.DIM, true)
	var ry := body_y
	Painter.section(_cv, right_x, ry, right_x + right_w, "THREAT / TRUST / ROE")
	ry += 15.0
	Painter.label(_cv, right_x, ry, TM.fit("THREAT %d · TRUST %d · CHOICE %s" % [int(vm.get("threat", 0)), int(vm.get("trust", 0)), String(vm.get("option", "—"))], right_w, true, 8), 8, P.PH, true)
	ry += 14.0
	var flags: Dictionary = vm.get("flags", {}) if vm.get("flags", {}) is Dictionary else {}
	var roe_txt := "ROE TIGHT · fire_control_illumination · auto_fire=false" if bool(flags.get("roe_tight", false)) else "ROE " + String(binder.roe_text)
	Painter.label(_cv, right_x, ry, TM.fit(roe_txt, right_w, true, 8), 8, P.AMBER if bool(flags.get("roe_tight", false)) else P.TXT, true)
	ry += 14.0
	Painter.label(_cv, right_x, ry, TM.fit("REPUTATION " + JSON.stringify(vm.get("reputation", {})), right_w, true, 7), 7, P.a(P.DIM, 0.9), true)
	ry += 13.0
	Painter.label(_cv, right_x, ry, TM.fit("FLAGS " + JSON.stringify(flags), right_w, true, 7), 7, P.a(P.DIM, 0.9), true)
	ry += 13.0
	Painter.label(_cv, right_x, ry, TM.fit("TRIGGERS " + ",".join(vm.get("trigger_ids", []) if vm.get("trigger_ids", []) is Array else []), right_w, true, 7), 7, P.AMBER, true)
	ry += 20.0
	var orb: Dictionary = vm.get("orbit", {}) if vm.get("orbit", {}) is Dictionary else {}
	Painter.section(_cv, right_x, ry, right_x + right_w, "TRACK / WINDOW")
	ry += 15.0
	if orb.is_empty():
		Painter.label(_cv, right_x, ry, "TRACK NOT READY · 需要真实 av4412 轨道", 8, P.AMBER, true)
	else:
		Painter.label(_cv, right_x, ry, TM.fit("t=%.1fs · pos=%s" % [float(orb.get("t", 0.0)), str(orb.get("pos", []))], right_w, true, 7), 7, P.TXT, true)
		ry += 13.0
		Painter.label(_cv, right_x, ry, TM.fit("WINDOW %s · RADAR %s · DETECTED %s" % ["OPEN" if bool(binder.av4412_chain.window_open) else "CLOSED", str(bool(binder.av4412_chain.radar_active)), str(bool((vm.get("detection", {}) as Dictionary).get("detected", false)) if vm.get("detection", {}) is Dictionary else false)], right_w, true, 7), 7, P.TXT, true)
	ry += 20.0
	Painter.section(_cv, right_x, ry, right_x + right_w, "TBD / EVENTS / COMMS")
	ry += 14.0
	var tbd_keys: Array = []
	for k2 in (vm.get("text_keys", []) if vm.get("text_keys", []) is Array else []):
		if bool((binder.av4412_chain.text(String(k2)) as Dictionary).get("tbd", false)):
			tbd_keys.append(String(k2))
	if not tbd_keys.is_empty():
		Painter.label(_cv, right_x, ry, TM.fit("TBD KEYS " + ",".join(tbd_keys) + " · 不伪造", right_w, true, 7), 7, P.AMBER, true)
		ry += 13.0
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	for i in range(maxi(0, evs.size() - 3), evs.size()):
		Painter.label(_cv, right_x, ry, TM.fit(String((evs[i] as Dictionary).get("action", "")) + " · " + String((evs[i] as Dictionary).get("trigger_id", "")), right_w, true, 7), 7, P.PH_DIM, true)
		ry += 12.0
	for line in (binder.av4412_comms_lines if binder != null else []):
		if ry > body.end.y - 14.0:
			break
		Painter.label(_cv, right_x, ry, TM.fit(String(line), right_w, true, 7), 7, P.DIM, true)
		ry += 12.0
	var bar: Array = _button_bar(fr.footer, [["TRACK", "TRACK"], ["WINDOW", "WINDOW"], ["ADVANCE", "ADVANCE"]])
	for b in bar:
		_av4412_buttons.append(b)
	if _av4412_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_av4412_msg, body.size.x, true, 8), 8, P.AMBER, true)


func _av4412_action(kind: String) -> void:
	if binder == null or not binder.av4412_ready:
		_av4412_msg = "AV4412 NOT READY"
		return
	var res: Dictionary = {}
	match kind:
		"TRACK":
			res = binder.av4412_update_orbit(_av4412_track())
		"WINDOW":
			res = binder.av4412_advance("window_open", {})
		"ADVANCE":
			var st: String = binder.av4412_state()
			var nxt := ""
			if st == "WINDOW_OPEN":
				var radar_now := bool(binder.av4412_chain.radar_active) if binder.av4412_chain != null else false
				nxt = "early_radar" if radar_now else "passive_contact"
			elif st in ["EARLY_RADAR", "PASSIVE_CONTACT"]:
				nxt = "comms"
			elif st == "COMMS":
				nxt = "negotiation"
			elif st in ["STRONG", "STANDARD", "QUESTION", "RETREAT"]:
				nxt = "resolve"
			elif st == "RESOLUTION":
				nxt = "report_handoff"
			else:
				var acts: Array = binder.av4412_actions()
				nxt = String(acts[0]) if not acts.is_empty() else ""
			res = binder.av4412_advance(nxt, {}) if nxt != "" else {"ok": false, "reason": "no_available_action"}
		"STRONG", "STANDARD", "QUESTION", "RETREAT":
			res = binder.av4412_advance(String(kind).to_lower(), {})
		_:
			res = {"ok": false, "reason": "unknown_action"}
	_av4412_msg = "%s · %s%s · state=%s · threat=%d trust=%d" % [kind, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", "")), binder.av4412_state(), int(binder.av4412_vm().get("threat", 0)), int(binder.av4412_vm().get("trust", 0))]
	var trig := String(res.get("trigger_id", ""))
	if trig != "":
		_trigger_banner = trig + " · av_4412 · " + binder.av4412_state()
	queue_redraw()


func _av4412_demo() -> void:
	# 截图/调试：真实 AV4412Chain 轨道输入 + 窗口 + 接触 + 通信 + 谈判 + STRONG；不自动开火。
	binder.av4412_update_orbit(_av4412_track())
	binder.av4412_advance("window_open", {})
	var radar_now := bool(binder.av4412_chain.radar_active) if binder.av4412_chain != null else false
	binder.av4412_advance("early_radar" if radar_now else "passive_contact", {})
	binder.av4412_advance("comms", {})
	binder.av4412_advance("negotiation", {})
	binder.av4412_advance("strong", {})
	_av4412_msg = "DEMO state=" + binder.av4412_state() + " · ROE TIGHT · fire_control_illumination · auto_fire=false · 未 resolve/handoff"
	_trigger_banner = "av4412_strong · ROE TIGHT · fire_control_illumination"
	print("[V1 HUD] AV4412 DEMO ", _av4412_msg)
	queue_redraw()


func _draw_chronos_overlay(r: Rect2) -> void:
	var fr := _overlay_frame(r, "CHRONOS / 港务 · 私人通信 · 行动", "Ceres 后链 · 文本来自 story_chronos · 接受/拒绝互斥 · 不自动完成/不自动开 4412", P.PH)
	var body: Rect2 = fr.body
	var x := body.position.x
	if binder == null or not binder.chronos_ready:
		Painter.label(_cv, x, body.position.y + 20, "CHRONOS NOT READY · no ChronosChain", 9, P.AMBER)
		return
	var vm: Dictionary = binder.chronos_vm()
	var stage := String(vm.get("state", "NOT READY"))
	var states := ["WAIT_DOCK", "PORT_COMM", "ACTION_EVAC", "PRIVATE_COMM", "CHOICE", "ACTIONS", "WINDOW_END"]
	var active_i := 0
	for i in range(states.size()):
		if String(states[i]) == stage:
			active_i = i
	var sy := body.position.y
	var scw := floorf((body.size.x - 6.0 * float(states.size() - 1)) / float(states.size()))
	for i in range(states.size()):
		var cr := Rect2(x + float(i) * (scw + 6.0), sy, scw, 18)
		_cv.draw_rect(cr, P.a(P.AMBER if i <= active_i else P.LINE, 0.16 if i <= active_i else 0.05))
		_cv.draw_rect(cr, P.a(P.AMBER if i == active_i else P.LINE, 0.75 if i == active_i else 0.25), false, 1.0)
		Painter.label(_cv, cr.position.x + 4, cr.position.y + 13, TM.fit(String(states[i]), scw - 8.0, true, 6), 6, P.PH if i == active_i else P.FAINT, true)
	var gap := 16.0
	var left_w := floorf(body.size.x * 0.58)
	var right_x := x + left_w + gap
	var right_w := body.size.x - left_w - gap
	var ty := sy + 30.0
	var keys: Array = []
	match stage:
		"WAIT_DOCK":
			keys = ["chronos.port_header"]
		"PORT_COMM":
			keys = ["chronos.port_rdo"]
		"ACTION_EVAC":
			keys = ["chronos.evac_option"]
		"PRIVATE_COMM":
			keys = ["chronos.private_comm"]
		"CHOICE":
			keys = ["chronos.accept", "chronos.reject", "chronos.trust_note"]
		"ACTIONS":
			keys = ["chronos.accept" if String(vm.get("choice", "")) == "accept" else "chronos.reject", "chronos.actions_menu"]
		"WINDOW_END":
			keys = ["chronos.window_teaching"]
		_:
			keys = []
	for k in keys:
		var txt: String = binder.chronos_text(String(k))
		var lines := _wrap_text_cjk(txt, left_w, 9, true)
		for line in lines:
			if ty > body.end.y - 70.0:
				break
			Painter.label(_cv, x, ty, line, 9, P.TXT, true)
			ty += 14.0
		ty += 4.0
	ty += 4.0
	Painter.label(_cv, x, ty, "COMMS LOG", 8, P.PH_DIM)
	ty += 14.0
	var log_lines: Array = binder.chronos_comms_lines
	if log_lines.is_empty():
		Painter.label(_cv, x, ty, "NO CHRONOS COMMS · 尚未触发", 7, P.FAINT, true)
	else:
		for i in range(maxi(0, log_lines.size() - 3), log_lines.size()):
			Painter.label(_cv, x, ty, TM.fit(String(log_lines[i]), left_w, true, 6), 6, P.PH_DIM, true)
			ty += 12.0
	var ry := sy + 30.0
	Painter.section(_cv, right_x, ry, right_x + right_w, "TRUST / STATE")
	ry += 15.0
	Painter.label(_cv, right_x, ry, TM.fit("TRUST %d · %s · CHOICE %s" % [int(vm.get("trust", 0)), String(vm.get("trust_state", "")), String(vm.get("choice", "—"))], right_w, true, 8), 8, P.PH, true)
	ry += 14.0
	Painter.label(_cv, right_x, ry, TM.fit("ACTIONS " + ",".join(vm.get("actions", []) if vm.get("actions", []) is Array else []), right_w, true, 7), 7, P.TXT, true)
	ry += 14.0
	Painter.label(_cv, right_x, ry, TM.fit("FLAGS " + JSON.stringify(vm.get("flags", {})), right_w, true, 6), 6, P.a(P.DIM, 0.9), true)
	ry += 14.0
	Painter.label(_cv, right_x, ry, TM.fit("REPUTATION " + JSON.stringify(vm.get("reputation", {})), right_w, true, 6), 6, P.a(P.DIM, 0.9), true)
	ry += 14.0
	Painter.label(_cv, right_x, ry, TM.fit("TRIGGERS " + ",".join(vm.get("trigger_ids", []) if vm.get("trigger_ids", []) is Array else []), right_w, true, 6), 6, P.AMBER, true)
	ry += 20.0
	Painter.section(_cv, right_x, ry, right_x + right_w, "WINDOW / 494")
	ry += 15.0
	var flags: Dictionary = vm.get("flags", {}) if vm.get("flags", {}) is Dictionary else {}
	Painter.label(_cv, right_x, ry, TM.fit("WINDOW " + ("ENDED" if bool(flags.get("window_ended", false)) else ("OPEN" if bool(flags.get("window_open", false)) else "NOT OPEN")) + " · 不自动开 4412", right_w, true, 7), 7, P.AMBER, true)
	var labels := [["PORT", "PORT COMM"], ["EVAC", "EVAC"], ["PRIVATE", "PRIVATE"], ["ACCEPT", "ACCEPT"], ["REJECT", "REJECT"], ["OPEN", "OPEN ACTIONS"], ["BLACKBOX", "BLACKBOX"], ["TELEMETRY", "TELEMETRY"], ["WINDOW", "WINDOW END"]]
	var items: Array = []
	for i in range(labels.size()):
		items.append([String(labels[i][0]), String(labels[i][1]), P.PH if i in [5, 6, 7, 8] else P.PH_DIM])
	_chronos_buttons = _button_bar(fr.footer, items)
	if _chronos_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_chronos_msg, body.size.x, true, 7), 7, P.AMBER, true)


func _chronos_action(kind: String) -> void:
	if binder == null or not binder.chronos_ready:
		_chronos_msg = "CHRONOS NOT READY"
		return
	var action := ""
	match kind:
		"PORT":
			action = "port_comm"
		"EVAC":
			action = "action_evac" if binder.chronos_state() == "PORT_COMM" else "evac"
		"PRIVATE":
			action = "private_comm"
		"ACCEPT":
			action = "choose_accept"
		"REJECT":
			action = "choose_reject"
		"OPEN":
			action = "open_actions"
		"BLACKBOX":
			action = "blackbox"
		"TELEMETRY":
			action = "telemetry"
		"WINDOW":
			action = "window_end"
		_:
			action = "unknown"
	var res: Dictionary = binder.chronos_advance(action, {})
	_chronos_msg = "%s · %s%s · state=%s · trust=%d" % [action, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", "")), binder.chronos_state(), binder.chronos_trust()]
	var trig := String(res.get("trigger_id", ""))
	if trig != "":
		_trigger_banner = trig + " · chronos · " + binder.chronos_state()
	queue_redraw()


func _chronos_demo() -> void:
	# 截图/调试：真实 ChronosChain API，推进到 ACTIONS 后停手；不选 WINDOW END/不自动开 4412。
	for a in ["port_comm", "action_evac", "private_comm", "choose_accept", "open_actions", "blackbox", "telemetry"]:
		binder.chronos_advance(a, {})
	_chronos_msg = "DEMO state=" + binder.chronos_state() + " · trust=" + str(binder.chronos_trust()) + " · 未执行 WINDOW END/4412"
	_trigger_banner = "chronos_telemetry · chronos · ACTIONS"
	print("[V1 HUD] CHRONOS DEMO ", _chronos_msg)
	queue_redraw()


func _draw_optical_overlay(r: Rect2) -> void:
	var c: Dictionary = _contacts[_selected] if _selected >= 0 and _selected < _contacts.size() else {}
	var tr: Dictionary = _optical_track
	if tr.is_empty() and binder != null:
		tr = _track_for_contact(c)
	var target_id := String(_optical_target)
	if target_id == "":
		target_id = String(c.get("entity_id", c.get("id", "")))
	var level := int(tr.get("level", 0)) if not tr.is_empty() else 0
	var is_ceres := target_id == "ceres_2" and binder != null and bool(binder.ceres_ready)
	var labels := [["VIS", "VIS / 可见光"], ["IR", "IR / 红外"], ["IFF", "IFF QUERY"], ["ELINT", "ELINT"], ["LIGHT", "LIGHT TX"], ["RECV", "LIGHT RECV"], ["ACK", "LIGHT ACK"], ["CODE_PREV", "CODE ◀"], ["CODE_NEXT", "CODE ▶"]]
	if is_ceres:
		labels = [["DATA_LINK", "DATA LINK"], ["VIS", "VIS"], ["ELINT", "ELINT"], ["IFF", "IFF QUERY"], ["READ_LIGHT", "READ LIGHT"], ["TYPE_L4", "TYPE L4"], ["RESCUE_PROMPT", "RESCUE PROMPT"], ["RESCUE", "RESCUE"], ["IGNORE", "IGNORE"]]
	var fr := _overlay_frame(r, "光学 / 识别 · OPTICAL / IDENTIFICATION", "目标=当前选中 track/entity · 数据来自 track_vm / sensor_vm · 不伪造 L3/L4", P.PH, "TRACK L%d · %s" % [level, String(c.get("id", target_id))])
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	var gap := 16.0
	var left_w := floorf(body.size.x * 0.5 - gap * 0.5)
	var right_x := x + left_w + gap
	var right_w := body.size.x - left_w - gap
	Painter.label(_cv, x, y + 10, TM.fit("TARGET  " + String(c.get("name", "NOT READY")) + " · " + String(c.get("id", target_id)), left_w, false, 9), 9, P.TXT)
	Painter.label(_cv, x, y + 24, TM.fit("ENTITY/TRACK " + target_id + " · " + (String(tr.get("track_id", "TRACK NOT READY")) if not tr.is_empty() else "TRACK NOT READY"), left_w, true, 7), 7, P.PH_DIM, true)
	var ly := y + 48.0
	Painter.section(_cv, x, ly, x + left_w, "IDENTIFICATION CHAIN / L1–L4")
	ly += 16.0
	var lv_names := ["NO TRACK", "L1 BEARING", "L2 POSITION", "L3 CLASSIFIED", "L4 IDENTIFIED"]
	var level_name := String(lv_names[clampi(level, 0, 4)])
	var lv_cols := [P.FAINT, P.DIM, P.BLUE, P.AMBER, P.PH]
	var cw := floorf((left_w - 3.0 * 6.0) / 4.0)
	for i in range(1, 5):
		var active := level >= i
		var cr := Rect2(x + float(i - 1) * (cw + 6.0), ly, cw, 20)
		_cv.draw_rect(cr, P.a(lv_cols[i], 0.12 if active else 0.03))
		_cv.draw_rect(cr, P.a(lv_cols[i], 0.7 if active else 0.22), false, 1.0)
		Painter.label(_cv, cr.position.x + 5, cr.position.y + 14, TM.fit("L%d %s" % [i, String(lv_names[i])], cw - 10.0, true, 7), 7, lv_cols[i] if active else P.FAINT, true)
	ly += 30.0
	var kv_right := minf(x + left_w, x + 460.0)
	Painter.key_value(_cv, x, ly, kv_right, "LEVEL", "L%d · %s" % [level, level_name], P.PH if level >= 3 else P.AMBER)
	ly += 15.0
	Painter.key_value(_cv, x, ly, kv_right, "IDENTITY", String(tr.get("identity_label", tr.get("identity", "—"))) if not tr.is_empty() else "NOT READY", P.TXT)
	ly += 15.0
	var sources: Array = tr.get("sources", []) if not tr.is_empty() and tr.get("sources", []) is Array else []
	var evidence: Array = tr.get("evidence_ids", []) if not tr.is_empty() and tr.get("evidence_ids", []) is Array else []
	Painter.key_value(_cv, x, ly, kv_right, "SOURCES", ",".join(sources) if not sources.is_empty() else "NOT READY", P.TXT)
	ly += 15.0
	Painter.key_value(_cv, x, ly, kv_right, "EVIDENCE", str(evidence.size()) + " ids", P.TXT)
	ly += 15.0
	Painter.key_value(_cv, x, ly, kv_right, "RANGE / BRG", ("%.1f km / %.0f°" % [float(tr.get("range_km", -1.0)), float(tr.get("bearing_deg", -1.0))]) if not tr.is_empty() else "NOT READY", P.TXT)
	ly += 15.0
	var fov := "—"
	var snr := "—"
	if binder != null:
		var svm0: Dictionary = binder.sensor_vm
		var chans: Array = svm0.get("channels", []) if svm0.get("channels", []) is Array else []
		for raw in chans:
			if raw is Dictionary and (String((raw as Dictionary).get("target_id", "")) == target_id or String((raw as Dictionary).get("target", "")) == target_id):
				fov = str((raw as Dictionary).get("fov_deg", (raw as Dictionary).get("fov", "—")))
				snr = str((raw as Dictionary).get("snr_db", (raw as Dictionary).get("snr", "—")))
				break
	Painter.key_value(_cv, x, ly, kv_right, "FOV / SNR", "%s / %s" % [fov, snr], P.TXT)
	var ow_h := minf(right_w * 0.75, body.size.y * 0.42)
	var ow := Rect2(right_x, y, right_w, ow_h)
	_cv.draw_rect(ow, P.a(P.EARTH, 0.7))
	_cv.draw_rect(ow, P.a(P.LINE2, 0.6), false, 1.0)
	_cv.draw_string(F.mono(), Vector2(ow.position.x + 8, ow.position.y + 16), "V1 OPTICAL / 瞄准框 · FOV " + str(fov), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, P.a(P.PH, 0.9))
	var cen := ow.position + ow.size * 0.5
	_cv.draw_line(Vector2(cen.x - ow.size.x * 0.4, cen.y), Vector2(cen.x - 12, cen.y), P.a(P.PH, 0.65), 1.0)
	_cv.draw_line(Vector2(cen.x + 12, cen.y), Vector2(cen.x + ow.size.x * 0.4, cen.y), P.a(P.PH, 0.65), 1.0)
	_cv.draw_line(Vector2(cen.x, cen.y - ow.size.y * 0.4), Vector2(cen.x, cen.y - 12), P.a(P.PH, 0.65), 1.0)
	_cv.draw_line(Vector2(cen.x, cen.y + 12), Vector2(cen.x, cen.y + ow.size.y * 0.4), P.a(P.PH, 0.65), 1.0)
	_cv.draw_rect(Rect2(cen - Vector2(44, 44), Vector2(88, 88)), P.a(P.AMBER, 0.7), false, 1.0)
	_cv.draw_circle(cen, 2.0, P.PH)
	_cv.draw_string(F.mono(), Vector2(ow.position.x + 8, ow.end.y - 12), "VIS/IR · SNR " + str(snr) + " · TRACK L%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, P.a(P.FAINT, 0.9))
	_optical_buttons.clear()
	var items: Array = []
	for i in range(labels.size()):
		items.append([String(labels[i][0]), String(labels[i][1]), P.PH if i < 3 else P.PH_DIM])
	_optical_buttons = _button_bar(fr.footer, items)
	var sr := Rect2(right_x, ow.end.y + 10.0, right_w, maxf(120.0, body.end.y - ow.end.y - 10.0))
	_cv.draw_rect(sr, P.a(P.PANEL2, 0.35))
	_cv.draw_rect(sr, P.a(P.LINE, 0.6), false, 1.0)
	Painter.label(_cv, sr.position.x + 10, sr.position.y + 18, "SIGNAL / ELINT · LIGHT", 9, P.PH)
	var svm: Dictionary = {}
	if binder != null and binder.session != null and binder.session.signal_service != null:
		svm = binder.session.signal_service.vm()
	if svm.is_empty():
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 40, "NO SIGNAL · signal_service NOT READY", 8, P.AMBER)
	else:
		var ec: Dictionary = svm.get("elint", {}) if svm.get("elint", {}) is Dictionary else {}
		var lc: Dictionary = ec.get("counts", {}) if ec.get("counts", {}) is Dictionary else {}
		var light: Dictionary = svm.get("light", {}) if svm.get("light", {}) is Dictionary else {}
		var lcounts: Dictionary = light.get("counts", {}) if light.get("counts", {}) is Dictionary else {}
		var codes: Array = light.get("codes", []) if light.get("codes", []) is Array else []
		if _signal_code == "" and not codes.is_empty():
			_signal_code = String(codes[0])
		var side := String(c.get("side", c.get("type", "unknown")))
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 40, TM.fit("TARGET side=%s identity=%s · ELINT signals %d · fixes/candidates %d · obs %d · evidence %d" % [side, String(tr.get("identity", side)) if not tr.is_empty() else side, int(lc.get("signals", 0)), int(lc.get("candidates", 0)), int(lc.get("observations", 0)), int(lc.get("evidence", 0))], sr.size.x - 20.0, true, 7), 7, P.TXT, true)
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 54, TM.fit("CODES %d · selected %s · TX sent %d recv %d ack %d timeout %d occluded %d misread %d" % [codes.size(), _signal_code, int(lcounts.get("sent", 0)), int(lcounts.get("received", 0)), int(lcounts.get("acked", 0)), int(lcounts.get("timeout", 0)), int(lcounts.get("occluded", 0)), int(lcounts.get("misread", 0))], sr.size.x - 20.0, true, 6), 6, P.DIM, true)
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 68, TM.fit("TX " + (_signal_tx_id if _signal_tx_id != "" else "NONE") + " · FIXES/指纹/置信度来自 signal vm", sr.size.x - 20.0, true, 7), 7, P.PH_DIM, true)
		var txs: Array = light.get("transmissions", []) if light.get("transmissions", []) is Array else []
		if not txs.is_empty():
			var tx: Dictionary = txs[txs.size() - 1]
			Painter.label(_cv, sr.position.x + 10, sr.position.y + 84, TM.fit("LAST TX %s · code %s · %s · reason %s" % [String(tx.get("tx_id", "")), String(tx.get("code_id", "")), String(tx.get("status", "")), String(tx.get("reason", ""))], sr.size.x - 20.0, true, 6), 6, P.TXT, true)
	if not _txp_reply.is_empty():
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 100, TM.fit("IFF " + String(_txp_reply.get("entity_type", "")) + " · status " + String(_txp_reply.get("status", "")) + " · identity " + String(_txp_reply.get("identity", "")) + " · code " + String(_txp_reply.get("transponder_code", "—")) + " · reg " + String(_txp_reply.get("registration_code", "—")), sr.size.x - 20.0, true, 7), 7, P.TXT, true)
		Painter.label(_cv, sr.position.x + 10, sr.position.y + 113, TM.fit("facility " + String(_txp_reply.get("facility_code", "—")) + " · crypto " + ("OK" if bool((_txp_reply.get("crypto", {}) as Dictionary).get("valid", false)) else "FAIL") + " · conf " + ("%.2f" % float(_txp_reply.get("confidence", 0.0))) + " · reason " + String(_txp_reply.get("reason", "")) + " · trigger " + String((_txp_reply.get("trigger", {}) as Dictionary).get("trigger_id", "")) if _txp_reply.get("trigger", {}) is Dictionary else "", sr.size.x - 20.0, true, 6), 6, P.PH_DIM, true)
	if _signal_msg != "":
		Painter.label(_cv, sr.position.x + 10, sr.end.y - 12, TM.fit(_signal_msg, sr.size.x - 20, true, 7), 7, P.AMBER, true)
	if is_ceres:
		_draw_ceres_panel(sr)
	if _optical_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_optical_msg, body.size.x, true, 7), 7, P.AMBER, true)


func _optical_action(kind: String) -> void:
	if binder == null or binder.session == null:
		_optical_msg = "NOT READY · no session"
		return
	var signal_kind := kind in ["ELINT", "LIGHT", "RECV", "ACK", "CODE_PREV", "CODE_NEXT"]
	if signal_kind:
		if binder.session.signal_service == null:
			_optical_msg = "SIGNAL NOT READY · no signal_service"
			_signal_msg = _optical_msg
			return
	else:
		if binder.session.sensor_service == null:
			_optical_msg = "SENSOR NOT READY · 无 sensor_service"
			return
	var target := _optical_target
	if target == "":
		_optical_msg = "NO TARGET · NOT READY"
		return
	var s = binder.session.sensor_service
	var res: Dictionary = {}
	if _optical_target == "ceres_2" and binder.ceres_ready and kind in ["DATA_LINK", "VIS", "ELINT", "IFF", "READ_LIGHT", "TYPE_L4", "RESCUE_PROMPT", "RESCUE", "IGNORE"]:
		_ceres_msg = _ceres_action(kind)
		_optical_msg = _ceres_msg
		_signal_msg = _ceres_msg
		return
	match kind:
		"VIS":
			res = s.start_channel("optical", target)
		"IR":
			res = s.start_channel("ir", target)
		"IFF":
			var qmode := "mode_5" if target == "av_4412" else "mode_s"
			res = binder.transponder_query(target, qmode)
			var reply: Dictionary = res.get("reply", {}) if res.get("reply", {}) is Dictionary else {}
			_txp_reply = reply
			_txp_msg = "IFF " + target + " · " + ("REPLY " + String(reply.get("status", "")) if bool(reply.get("ok", false)) else "NO REPLY · " + String(res.get("reason", reply.get("reason", ""))))
			if bool(reply.get("ok", false)):
				_txp_msg += " · %s/%s · code %s · reg %s · fac %s · crypto %s · conf %.2f · trigger %s" % [
					String(reply.get("entity_type", "")), String(reply.get("identity", "")),
					String(reply.get("transponder_code", "")), String(reply.get("registration_code", "")),
					String(reply.get("facility_code", "")), ("OK" if bool((reply.get("crypto", {}) as Dictionary).get("valid", false)) else "FAIL"),
					float(reply.get("confidence", 0.0)), String((reply.get("trigger", {}) as Dictionary).get("trigger_id", "")) if reply.get("trigger", {}) is Dictionary else ""]
				var tid := String((reply.get("trigger", {}) as Dictionary).get("trigger_id", "")) if reply.get("trigger", {}) is Dictionary else ""
				if tid != "":
					_trigger_banner = tid + " · " + target + " · " + String(reply.get("status", "")) + " · " + String(reply.get("reason", ""))
			elif String((res.get("trigger", {}) as Dictionary).get("trigger_id", "")) if res.get("trigger", {}) is Dictionary else "" != "":
				_trigger_banner = String((res.get("trigger", {}) as Dictionary).get("trigger_id", "")) + " · " + target + " · " + String(res.get("reason", ""))
			binder.refresh()
		"LIGHT":
			var codes: Array = []
			if binder.session.signal_service != null:
				codes = binder.session.signal_service.code_ids
			if codes.is_empty():
				res = {"ok": false, "reason": "no_light_codes"}
			else:
				_signal_code = String(codes[0]) if _signal_code == "" else _signal_code
				res = binder.session.light_send(_signal_code, target)
				if bool(res.get("ok", false)):
					_signal_tx_id = String(res.get("tx_id", res.get("id", "")))
		"RECV":
			if _signal_tx_id == "":
				res = {"ok": false, "reason": "no_tx"}
			else:
				res = binder.session.light_receive(_signal_tx_id)
		"ACK":
			if _signal_tx_id == "":
				res = {"ok": false, "reason": "no_tx"}
			else:
				res = binder.session.light_ack(_signal_tx_id)
		"CODE_PREV", "CODE_NEXT":
			var code_ids: Array = binder.session.signal_service.code_ids if binder.session.signal_service != null else []
			if code_ids.is_empty():
				res = {"ok": false, "reason": "no_light_codes"}
			else:
				_signal_code_index = int(_signal_code_index) + (-1 if kind == "CODE_PREV" else 1)
				_signal_code_index = posmod(_signal_code_index, code_ids.size())
				_signal_code = String(code_ids[_signal_code_index])
				res = {"ok": true, "code_id": _signal_code}
		"ELINT":
			res = binder.session.signal_intercept(target)
			var df: Dictionary = binder.session.signal_df(target)
			if bool(res.get("ok", false)):
				res["df"] = df
			binder.session.tick(0.1)
			_signal_msg = "ELINT %s · %s%s" % [target, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
			_signal_msg += " · df=" + ("OK" if bool(df.get("ok", false)) else String(df.get("reason", "FAILED")))
		_:
			res = {"ok": false, "reason": "unknown"}
	_optical_msg = "%s %s · %s%s" % [kind, target, "OK" if bool(res.get("ok", false)) else "FAILED", "" if bool(res.get("ok", false)) else " · " + String(res.get("reason", ""))]
	if kind in ["ELINT", "LIGHT", "RECV", "ACK"]:
		_signal_msg = _optical_msg
	print("[V1 HUD] OPTICAL ", _optical_msg)
	binder.refresh()
	_optical_track = _track_for_contact(_contacts[_selected]) if _selected >= 0 and _selected < _contacts.size() else {}
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
	var vm0: Dictionary = _combat.vm() if _combat != null and bool(_combat.ready) else {}
	var chips := ""
	if not vm0.is_empty():
		chips = "ROE " + String(vm0.get("roe", "—")) + " · TGT " + (_combat_target if _combat_target != "" else "—")
	var fr := _overlay_frame(r, "战斗终端 / COMBAT TERMINAL", "目标/武器/ROE/授权/预测 · CombatService shadow · NO PHYSICS HIT", P.PH, chips)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	if _combat == null or not bool(_combat.ready):
		Painter.label(_cv, x, y + 20, "COMBAT NOT READY · no CombatService", 9, P.AMBER)
		return
	var vm: Dictionary = vm0
	var track_rows: Array = vm.get("tracks", []) if vm.get("tracks", []) is Array else []
	var weapon_rows: Array = vm.get("weapons", []) if vm.get("weapons", []) is Array else []
	var gap := 16.0
	var tw := floorf(body.size.x * 0.24)
	var wx := x + tw + gap
	var ww := floorf(body.size.x * 0.30)
	var rx := wx + ww + gap
	var rw := body.size.x - tw - ww - gap * 2.0
	var ev_h := minf(120.0, body.size.y * 0.22)
	var ev_top := body.end.y - ev_h
	Painter.section(_cv, x, y, x + tw, "TARGETS / 目标")
	_combat_target_rows.clear()
	var ty := y + 18.0
	for i in range(mini(5, track_rows.size())):
		var tr: Dictionary = track_rows[i]
		var tid := String(tr.get("id", ""))
		var tr_rect := Rect2(x, ty + float(i) * 28.0, tw, 25.0)
		_combat_target_rows.append({"rect": tr_rect, "id": tid})
		if tid == _combat_target:
			_cv.draw_rect(tr_rect, P.a(P.AMBER, 0.12))
		Painter.label(_cv, x, tr_rect.position.y + 11, TM.fit("L%d %s · %s" % [int(tr.get("level", 0)), tid, String(tr.get("identity", "unknown"))], tw - 4.0, true, 7), 7, P.PH if tid == _combat_target else P.TXT, true)
		var rng := float(tr.get("range_km", -1.0))
		Painter.label(_cv, x + 8, tr_rect.position.y + 22, TM.fit("threat %s · %s" % [String(tr.get("threat", "—")), ("%.1f km" % rng) if rng >= 0.0 else "RANGE NOT READY"], tw - 12.0, true, 6), 6, P.a(P.DIM, 0.9), true)
	Painter.section(_cv, wx, y, wx + ww, "WEAPON RACK / 武器架")
	_combat_weapon_rows.clear()
	var wy := y + 18.0
	for i in range(mini(6, weapon_rows.size())):
		var w: Dictionary = weapon_rows[i]
		var wid := String(w.get("id", ""))
		var wr := Rect2(wx, wy + float(i) * 28.0, ww, 25.0)
		_combat_weapon_rows.append({"rect": wr, "id": wid})
		if wid == _combat_weapon:
			_cv.draw_rect(wr, P.a(P.PH, 0.10))
		Painter.label(_cv, wx, wr.position.y + 11, TM.fit("%s · %s" % [wid, String(w.get("kind", ""))], ww, true, 7), 7, P.PH if wid == _combat_weapon else P.TXT, true)
		Painter.label(_cv, wx + 8, wr.position.y + 22, TM.fit("AMMO %s · CD %s · RANGE %s" % [
			str(w.get("ammo", "—")), str(w.get("cooldown_remaining_s", w.get("cooldown_s", "—"))), str(w.get("range_km", "—"))], ww - 12.0, true, 6), 6, P.a(P.DIM, 0.9), true)
	var ry := y
	Painter.section(_cv, rx, ry, rx + rw, "ROE / AUTHORIZATION")
	ry += 16.0
	Painter.label(_cv, rx, ry, TM.fit("ROE " + String(vm.get("roe", "—")) + " · " + String(vm.get("roe_label", "")), rw, true, 8), 8, P.PH, true)
	ry += 14.0
	_combat_roe_buttons.clear()
	var roes := ["DEFEND", "HOLD", "TIGHT", "FREE"]
	var rbtn_w := floorf((rw - 3.0 * 6.0) / 4.0)
	for i in range(roes.size()):
		var br := Rect2(rx + float(i) * (rbtn_w + 6.0), ry, rbtn_w, 18)
		_combat_roe_buttons.append({"rect": br, "kind": String(roes[i])})
		Painter.button(_cv, br, String(roes[i]), true, P.PH if String(vm.get("roe", "")) == String(roes[i]) else P.PH_DIM)
	ry += 28.0
	for lvl in ["TRACK", "SOLUTION", "FIRE"]:
		var au: Dictionary = binder.session.combat_authorization(lvl, _combat_target, _combat_weapon) if binder != null and binder.session != null else {}
		Painter.label(_cv, rx, ry, "%s AUTHORIZATION" % lvl, 7, P.a(P.PH_DIM, 0.9), true)
		Painter.label_right(_cv, rx + rw, ry, TM.fit("OK" if bool(au.get("ok", false)) else String(au.get("reason", "LOCKED")), rw * 0.5, true, 7), 7, P.PH if bool(au.get("ok", false)) else P.AMBER, true)
		ry += 13.0
	ry += 6.0
	Painter.section(_cv, rx, ry, rx + rw, "PREDICTION / INTERFACE · NO PHYSICS")
	ry += 15.0
	var pred: Dictionary = _combat.predict_shot(_combat_target, _combat_weapon) if _combat_target != "" and _combat_weapon != "" else {}
	if bool(pred.get("ok", false)):
		Painter.label(_cv, rx, ry, TM.fit("TOF %.1fs · HIT %d%% · ERR %.2f km" % [float(pred.get("time_of_flight_s", -1.0)), int(float(pred.get("hit_probability", 0.0)) * 100.0), float(pred.get("error_km", 0.0))], rw, true, 7), 7, P.TXT, true)
		Painter.label(_cv, rx, ry + 12, TM.fit("trajectory=" + String(pred.get("trajectory", "interface_only")) + " · no_physics=" + str(bool(pred.get("no_physics", true))), rw, true, 6), 6, P.a(P.FAINT, 0.9), true)
	else:
		Painter.label(_cv, rx, ry, TM.fit("PREDICTION NOT READY · " + String(pred.get("reason", "no target/weapon")), rw, true, 7), 7, P.AMBER, true)
	Painter.section(_cv, x, ev_top, body.end.x, "COMBAT EVENTS / 战斗事件")
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	var ey := ev_top + 17.0
	if evs.is_empty():
		Painter.label(_cv, x, ey, "NO COMBAT EVENTS · NOT READY", 7, P.FAINT, true)
	for i in range(maxi(0, evs.size() - 5), evs.size()):
		var ev: Dictionary = evs[i]
		Painter.label(_cv, x, ey + float(i - maxi(0, evs.size() - 5)) * 12.0, TM.fit("%5.1fs %s · %s" % [float(ev.get("t", 0.0)), String(ev.get("kind", "")), JSON.stringify(ev.get("payload", {}))], body.size.x, true, 6), 6, P.a(P.DIM, 0.9), true)
	_combat_buttons.clear()
	var actions := ["TRACK", "SOLUTION", "AUTHORIZE FIRE", "FIRE"]
	var items: Array = []
	for i in range(actions.size()):
		items.append([String(actions[i]), String(actions[i]), P.PH if i < 3 else P.RED])
	_combat_buttons = _button_bar(fr.footer, items)
	if _combat_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_combat_msg, body.size.x, true, 7), 7, P.AMBER, true)


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
	var fr := _overlay_frame(r, "损管 / DAMAGE · 7 SECTIONS", "SOURCE · V2DamageModel shadow (session 无 damage_vm) · 只读/最小交互", P.PH)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	_damage_rows.clear()
	_damage_buttons.clear()
	if _damage == null or not bool(_damage.ready):
		Painter.label(_cv, x, y + 20, "DAMAGE NOT READY · 无模型/内容", 9, P.AMBER)
		return
	var vm: Dictionary = _damage.vm_damage()
	var secs: Array = vm.get("sections", []) if vm.get("sections", []) is Array else []
	var gap := 16.0
	var left_w := floorf(body.size.x * 0.55)
	var rx := x + left_w + gap
	var rw := body.size.x - left_w - gap
	var sy := y
	for i in range(secs.size()):
		var sec: Dictionary = secs[i]
		var sr := Rect2(x, sy + float(i) * 36.0, left_w, 32.0)
		var selected := String(sec.get("id", "")) == _selected_section
		var fire: Dictionary = sec.get("fire", {}) if sec.get("fire", {}) is Dictionary else {}
		var dec: Dictionary = sec.get("decompression", {}) if sec.get("decompression", {}) is Dictionary else {}
		Painter.list_row(_cv, sr, "%s · %s" % [String(sec.get("id", "")), String(sec.get("label", ""))],
			"%.1f%% %s%s%s" % [float(sec.get("integrity_pct", 0.0)), String(sec.get("state", "")),
			" · FIRE" if bool(fire.get("active", false)) else "", " · DEC" if bool(dec.get("active", false)) else ""],
			P.RED if float(sec.get("integrity", 0.0)) < 0.25 else P.PH_DIM, selected)
		_damage_rows.append({"rect": sr, "id": String(sec.get("id", ""))})
	var ry := y
	Painter.section(_cv, rx, ry, rx + rw, "RESOURCES / 队伍")
	ry += 15.0
	var res: Dictionary = vm.get("resources", {}) if vm.get("resources", {}) is Dictionary else {}
	Painter.label(_cv, rx, ry, TM.fit("TEAMS %s · SPARES %s · PERSONNEL %s" % [str(res.get("teams_available", "")), str(res.get("spares", "")), str(res.get("personnel", ""))], rw, true, 7), 7, P.TXT, true)
	ry += 18.0
	Painter.section(_cv, rx, ry, rx + rw, "QUEUE / 队列")
	ry += 15.0
	var jobs: Array = vm.get("queue", []) if vm.get("queue", []) is Array else []
	if jobs.is_empty():
		Painter.label(_cv, rx, ry, "NO REPAIR JOBS", 7, P.FAINT, true)
	for i in range(mini(3, jobs.size())):
		var job: Dictionary = jobs[i]
		Painter.label(_cv, rx, ry + float(i) * 12.0, TM.fit("%s · P%s · %.0f%%" % [String(job.get("section", "")), str(job.get("priority", "")), float(job.get("progress_pct", 0.0))], rw, true, 7), 7, P.TXT, true)
	ry += 48.0
	Painter.section(_cv, rx, ry, rx + rw, "EVENTS / 事件")
	ry += 15.0
	var evs: Array = vm.get("events", []) if vm.get("events", []) is Array else []
	for i in range(mini(3, maxi(0, evs.size() - 3))):
		var ev: Dictionary = evs[evs.size() - 1 - i]
		Painter.label(_cv, rx, ry + float(i) * 12.0, TM.fit(String(ev.get("text", ev.get("type", ""))), rw, true, 7), 7, P.DIM, true)
	var items: Array = [["FIX", "FIX / 维修", P.PH], ["PRI", "PRI / 优先级", P.PH], ["CANCEL", "CANCEL / 取消", P.AMBER]]
	_damage_buttons = _button_bar(fr.footer, items)
	if _damage_msg != "":
		Painter.label(_cv, x, (fr.footer as Rect2).position.y - 12.0, TM.fit(_damage_msg, body.size.x, true, 7), 7, P.AMBER, true)


func _draw_roe_overlay(r: Rect2) -> void:
	var cur := String(_combat.roe) if _combat != null else "NOT READY"
	var fr := _overlay_frame(r, "ROE / 交战规则 · 四档", "session.set_roe(DEFEND/HOLD/TIGHT/FREE) · 当前 " + cur, P.PH, "LOCKED" if _roe_locked else "UNLOCKED", 0)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	if _roe_locked:
		Painter.label(_cv, x, y + 6, "LOCKED · 序章未解锁 · 仅显示当前档位", 9, P.AMBER)
	else:
		Painter.label(_cv, x, y + 6, "UNLOCKED · 点击档位调用真实 session.set_roe", 8, P.TXT, true)
	_roe_buttons.clear()
	var labels := [["DEFEND", "DEFEND / 防御", "只在对自身被攻击时还击"], ["HOLD", "HOLD / 保持", "需三级手动授权，默认不交战"], ["TIGHT", "TIGHT / 严格", "TRACK 自动，SOLUTION/FIRE 一次确认"], ["FREE", "FREE / 自由", "敌对目标自动 TRACK/SOLUTION，FIRE 手动"]]
	var gap := 12.0
	var cw := floorf((body.size.x - gap) * 0.5)
	var ch := minf(96.0, (body.size.y - 40.0 - gap) * 0.5)
	var grid_h := 2.0 * ch + gap
	var gy := y + 24.0 + maxf(0.0, (body.size.y - 40.0 - grid_h) * 0.5)
	for i in range(labels.size()):
		var br := Rect2(x + float(i % 2) * (cw + gap), gy + float(i / 2) * (ch + gap), cw, ch)
		_roe_buttons.append({"rect": br, "kind": String(labels[i][0])})
		var active := _combat != null and String(_combat.roe) == String(labels[i][0])
		_cv.draw_rect(br, P.a(P.PANEL2, 0.45))
		_cv.draw_rect(br, P.a(P.PH if active else P.LINE, 0.85 if active else 0.35), false, 1.0)
		Painter.label(_cv, br.position.x + 12, br.position.y + 24, TM.fit(String(labels[i][1]), cw - 24.0, false, 14), 14, P.PH if active else P.TXT)
		Painter.label(_cv, br.position.x + 12, br.position.y + 44, TM.fit(String(labels[i][2]), cw - 24.0, false, 9), 9, P.DIM)
		if active:
			Painter.label(_cv, br.end.x - 60, br.position.y + 20, "CURRENT", 8, P.PH, true)
		elif _roe_locked:
			Painter.label(_cv, br.end.x - 60, br.position.y + 20, "LOCKED", 8, P.FAINT, true)
	Painter.label(_cv, x, body.end.y - 16, "授权提示：ROE 只改交战规则，不授予开火许可；需另行授权。", 9, P.a(P.DIM, 0.95))
	if _roe_msg != "":
		Painter.label(_cv, x, body.end.y - 2, TM.fit(_roe_msg, body.size.x, true, 8), 8, P.AMBER, true)


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
	var slot := String(res.get("slot", "save"))
	var path := String(res.get("path", ""))
	var meta: Dictionary = binder.save_service.load_metadata(slot) if binder.save_service != null and _save_ok else {}
	var m: Dictionary = meta.get("meta", {}) if meta.get("meta", {}) is Dictionary else {}
	var ts := float(m.get("updated_at", 0.0))
	_save_msg = ("SAVED slot=%s · %sB · %s" % [slot, str(int(res.get("bytes", 0))), _fmt_time(ts)]) if _save_ok else ("FAILED · " + String(res.get("reason", "")))
	_save_msg += " · " + path
	print("[V1 HUD] SAVE ", intent, " · ", _save_msg)
	if kind == "menu":
		_overlay = "save"
		_exit_intent = false
		_save_overlay_msg = "SAVE/MENU · 意图：存档并打开菜单（不切场景）"
		_rebuild_save_slots()
	elif kind == "quit":
		_overlay = "save"
		_exit_intent = true
		_save_overlay_msg = "EXIT INTENT ONLY · 不真正退出"
		_rebuild_save_slots()
	queue_redraw()


func _fmt_time(unix_s: float) -> String:
	if unix_s <= 0.0:
		return "—"
	return Time.get_datetime_string_from_unix_time(int(unix_s))


func _rebuild_save_slots() -> void:
	_save_slots.clear()
	if binder == null or binder.save_service == null:
		return
	for slot in ["save", "menu", "quit", "autosave"]:
		var path := String(binder.save_service.slot_path(slot))
		var exists := FileAccess.file_exists(path)
		var meta: Dictionary = {}
		var corrupt := false
		var reason := ""
		if exists:
			meta = binder.save_service.load_metadata(slot)
			if not bool(meta.get("ok", false)):
				corrupt = true
				reason = String(meta.get("reason", "corrupted"))
		var m: Dictionary = meta.get("meta", {}) if meta.get("meta", {}) is Dictionary else {}
		var size := 0
		if exists:
			var bytes := FileAccess.get_file_as_bytes(path)
			size = bytes.size()
		_save_slots.append({"slot": slot, "path": path, "exists": exists, "corrupt": corrupt,
			"reason": reason, "meta": m, "size": size})


func _draw_save_overlay(r: Rect2) -> void:
	var fr := _overlay_frame(r, "存档 / SAVE · LOAD", "三色点：绿=save · 黄=menu+打开 · 红=quit+退出确认（不退出） · SaveService user://saves", P.PH, "", 0)
	var body: Rect2 = fr.body
	var x := body.position.x
	var y := body.position.y
	_rebuild_save_slots()
	_save_load_buttons.clear()
	Painter.section(_cv, x, y, body.end.x, "SLOTS / 槽位")
	var gap := 12.0
	var note_h := 64.0
	var card_w := floorf((body.size.x - gap) * 0.5)
	var card_h := minf(132.0, floorf((body.end.y - note_h - (y + 18.0) - gap) * 0.5))
	for i in range(_save_slots.size()):
		var row: Dictionary = _save_slots[i]
		var rr := Rect2(x + float(i % 2) * (card_w + gap), y + 18.0 + float(i / 2) * (card_h + gap), card_w, card_h)
		_cv.draw_rect(rr, P.a(P.PANEL2, 0.35))
		var corrupted := bool(row.get("corrupt", false))
		var exists := bool(row.get("exists", false))
		var col := P.RED if corrupted else (P.PH if exists else P.FAINT)
		_cv.draw_rect(rr, P.a(col, 0.5), false, 1.0)
		Painter.label(_cv, rr.position.x + 10, rr.position.y + 20, String(row.get("slot", "")).to_upper(), 12, col, true)
		var state := "CORRUPTED · " + String(row.get("reason", "")) if corrupted else ("EXISTS" if exists else "EMPTY · NO SAVE")
		Painter.label(_cv, rr.position.x + 10, rr.position.y + 36, TM.fit("STATE " + state, card_w - 130.0, true, 7), 7, col, true)
		var m: Dictionary = row.get("meta", {}) if row.get("meta", {}) is Dictionary else {}
		if exists and not corrupted:
			Painter.label(_cv, rr.position.x + 10, rr.position.y + 54, TM.fit("UPDATED " + _fmt_time(float(m.get("updated_at", 0.0))), card_w - 20.0, true, 7), 7, P.TXT, true)
			Painter.label(_cv, rr.position.x + 10, rr.position.y + 68, TM.fit("CHAPTER %s · LOCATION %s" % [String(m.get("chapter", "—")), String(m.get("location", "—"))], card_w - 20.0, true, 7), 7, P.DIM, true)
			Painter.label(_cv, rr.position.x + 10, rr.position.y + 82, TM.fit("SIZE %dB · t=%.1fs" % [int(row.get("size", 0)), float(m.get("t_s", 0.0))], card_w - 20.0, true, 7), 7, P.DIM, true)
			Painter.label(_cv, rr.position.x + 10, rr.position.y + 96, TM.fit("PATH " + String(row.get("path", "")), card_w - 130.0, true, 6), 6, P.a(P.FAINT, 0.9), true)
		else:
			Painter.label(_cv, rr.position.x + 10, rr.position.y + 54, TM.fit("PATH " + String(row.get("path", "")), card_w - 20.0, true, 6), 6, P.a(P.FAINT, 0.9), true)
		var br := Rect2(rr.end.x - 108, rr.position.y + 24, 96, 22)
		if exists and not corrupted:
			_save_load_buttons.append({"rect": br, "slot": String(row.get("slot", ""))})
			Painter.button(_cv, br, "LOAD / 读档", true, P.PH)
		else:
			Painter.button(_cv, br, "LOAD · N/A", false, P.FAINT)
	var py := body.end.y - note_h + 10.0
	Painter.section(_cv, x, py, body.end.x, "ACTIONS / 说明")
	Painter.label(_cv, x, py + 18, TM.fit("NEW GAME / 新建：占位（未接剧情流程） · CONTINUE / 继续：由 LOAD 读档恢复", body.size.x, true, 7), 7, P.DIM)
	Painter.label(_cv, x, py + 32, TM.fit("不覆盖主菜单/退出；黄色只显示 SAVE+MENU 意图，红色只显示 QUIT 意图。", body.size.x, true, 6), 6, P.a(P.FAINT, 0.9), true)
	if _exit_intent:
		Painter.label(_cv, x, py + 48, "EXIT CONFIRMATION · 已写入 quit 槽，但未退出游戏（intent only）", 8, P.RED)
	if _save_overlay_msg != "":
		Painter.label(_cv, x, py + 48, TM.fit(_save_overlay_msg, body.size.x, true, 7), 7, P.AMBER, true)


func _load_slot(slot: String) -> void:
	if binder == null or binder.save_service == null:
		_save_overlay_msg = "LOAD FAILED · no SaveService"
		return
	# 优先使用 SaveService 的原始 payload：当前 session 已 boot track/story/sensor/combat，
	# 原地 load_state 能恢复这些可选组件；load_session 新建 session 无这些组件会失败。
	var loaded := false
	var load_fail := ""
	var raw: Dictionary = binder.save_service.call("_read_slot_raw", slot)
	if bool(raw.get("ok", false)):
		var payload: Dictionary = raw.get("payload", {}) if raw.get("payload", {}) is Dictionary else {}
		var save_text := String(payload.get("session_save", ""))
		if save_text != "" and binder.session != null:
			# 当前 shell 的 CombatService 是 UI 外挂注入，boot seed 未含 combat_service；
			# load_state 会用 seed 重新 boot，先把可选 combat_service 加回 seed 供快照恢复。
			var parsed = JSON.parse_string(save_text)
			if parsed is Dictionary:
				var seed: Dictionary = parsed.get("seed", {}) if parsed.get("seed", {}) is Dictionary else {}
				if not seed.has("combat_service"):
					seed["combat_service"] = {}
					parsed["seed"] = seed
					save_text = JSON.stringify(parsed)
			var lr: Dictionary = binder.session.load_state(save_text)
			loaded = bool(lr.get("ok", false))
			if not loaded:
				load_fail = String(lr.get("reason", "session_load_failed"))
	else:
		load_fail = String(raw.get("reason", "read_failed"))
	if not loaded:
		# fallback: 标准 load_session（无可选组件时会返回明确失败 reason）
		var res2: Dictionary = binder.save_service.load_session(slot)
		if bool(res2.get("ok", false)) and res2.get("session") != null:
			binder.session = res2.get("session")
			loaded = true
		else:
			_save_overlay_msg = "LOAD FAILED · " + String(res2.get("reason", load_fail))
			return
	if binder.session != null:
		if binder.session.combat_service != null:
			_combat = binder.session.combat_service
			_combat.t = float(binder.session.now_s())
		elif _combat != null:
			binder.session.combat_service = _combat
			_combat.t = float(binder.session.now_s())
		binder.refresh()
		_contacts = binder.contacts.duplicate(true) if binder.contacts is Array else []
		_normalize_contacts()
		_selected = 0
		for i in range(_contacts.size()):
			if String((_contacts[i] as Dictionary).get("id", "")) == "1000":
				_selected = i
				break
		_selected_cmd = 0 if binder.commands.size() > 0 else -1
		_comms_target = String((_contacts[_selected] as Dictionary).get("entity_id", (_contacts[_selected] as Dictionary).get("id", ""))) if _contacts.size() > 0 else ""
		_save_msg = "LOADED slot=" + slot
		_save_overlay_msg = "LOADED " + slot + " · name=" + String(binder.session.writer) + " · t=" + str(int(float(binder.session.now_s()))) + "s"
		print("[V1 HUD] LOAD ", _save_overlay_msg)
		_rebuild_save_slots()




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
		"CHRONOS":
			_overlay = "chronos"
		"AV4412":
			_overlay = "av4412"
		"TRAFFIC":
			_overlay = "traffic"
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


func _gui_input(event: InputEvent) -> void:
	if _plot3d != null and _plot3d_rect.size.x > 0.0 and bool(_plot3d.handle_input(event, _plot3d_rect)):
		var picked := String(_plot3d.consume_pick()) if _plot3d.has_method("consume_pick") else ""
		if picked != "":
			_select_track_contact(picked)
		accept_event()
		queue_redraw()
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := (event as InputEventMouseButton).position
	if _overlay != "":
		# 方案B-32：overlay 按钮 rect 存在弹层局部坐标，命中判定需先换算。
		var lpos := pos - _overlay_offset
		if _overlay_close.has_point(lpos):
			_overlay = ""
			accept_event()
			return
		if _overlay_hit(lpos):
			accept_event()
		return
	for d in _top_dots:
		if (d["rect"] as Rect2).has_point(pos):
			_do_save(String(d.get("kind", "")))
			accept_event()
			return
	for t in _tabs:
		if (t["rect"] as Rect2).has_point(pos):
			_page = String(t.get("page", "ship"))
			queue_redraw()
			accept_event()
			return
	for c in _contact_rects:
		if (c["rect"] as Rect2).has_point(pos):
			_selected = int(c.get("index", 0))
			var picked: Dictionary = _contacts[_selected]
			_optical_target = String(picked.get("entity_id", picked.get("id", "")))
			_page = "facility" if String(picked.get("facility_id", "")) != "" else ("target" if String(picked.get("type", "")) in ["unknown", "neutral"] else "ship")
			queue_redraw()
			accept_event()
			return
	for b in _right_buttons:
		if (b["rect"] as Rect2).has_point(pos):
			_do_right_action(String(b.get("kind", "")))
			accept_event()
			return


func _overlay_hit(lp: Vector2) -> bool:
	# 方案B-32：统一子界面命中分发（全部使用弹层局部坐标）。返回 true 表示已消费点击。
	match _overlay:
		"traffic":
			for row in _traffic_otc_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_traffic_otc = String(row.get("id", ""))
					queue_redraw()
					return true
			for row in _traffic_lane_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_traffic_lane = String(row.get("id", ""))
					queue_redraw()
					return true
			for b in _traffic_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_traffic_action(String(b.get("kind", "")))
					return true
		"report", "complete":
			for b in _report_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_report_action(String(b.get("kind", "")))
					return true
		"chronos":
			for b in _chronos_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_chronos_action(String(b.get("kind", "")))
					return true
		"av4412":
			for b in _av4412_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_av4412_action(String(b.get("kind", "")))
					return true
		"optical":
			for b in _optical_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_optical_action(String(b.get("kind", "")))
					return true
		"comms":
			for b in _comms_type_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_comms_action(String(b.get("kind", "")))
					return true
			for row in _comms_cmd_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_selected_cmd = int(row.get("index", 0))
					queue_redraw()
					return true
			for b in _comms_cmd_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					var k := String(b.get("kind", ""))
					if k == "SEND":
						_comms_send()
					else:
						_command_action(k)
					return true
		"combat":
			for row in _combat_target_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_combat_target = String(row.get("id", ""))
					queue_redraw()
					return true
			for row in _combat_weapon_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_combat_weapon = String(row.get("id", ""))
					queue_redraw()
					return true
			for b in _combat_roe_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_combat_action(String(b.get("kind", "")))
					return true
			for b in _combat_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_combat_action(String(b.get("kind", "")))
					return true
		"damage":
			for row in _damage_rows:
				if (row["rect"] as Rect2).has_point(lp):
					_selected_section = String(row.get("id", ""))
					queue_redraw()
					return true
			for b in _damage_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_damage_action(String(b.get("kind", "")))
					return true
		"roe":
			for b in _roe_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_roe_action(String(b.get("kind", "")))
					return true
		"save":
			for b in _save_load_buttons:
				if (b["rect"] as Rect2).has_point(lp):
					_load_slot(String(b.get("slot", "")))
					return true
	return false


func _return_to_main_menu() -> void:
	print("[V1 HUD] LOAD FAILED → main_menu.tscn · ", binder.load_error if binder != null else "")
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _select_track_contact(track_id: String) -> void:
	for i in range(_contacts.size()):
		var c: Dictionary = _contacts[i]
		if String(c.get("track_id", "")) == track_id:
			_selected = i
			_comms_target = String(c.get("entity_id", c.get("id", "")))
			_optical_track = _track_for_contact(c)
			_optical_target = _comms_target
			return


func _unhandled_input(event: InputEvent) -> void:
	if _plot3d != null and _plot3d_rect.size.x > 0.0 and bool(_plot3d.handle_input(event, _plot3d_rect)):
		accept_event()
		queue_redraw()
		return
