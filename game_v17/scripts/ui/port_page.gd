extends Control

# 阶段3H 港口/入港页：真实 PortService；Chronos/Greenwich/Sextant 资源与请求。
# 只读 UI + 手动 PortService API；不写剧情/物理/存档。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const PortService := preload("res://scripts/core/port_service.gd")

const SHIP_ID := "apsis"
const PORT_ID := "l1_meridian_05"

var service = null
var _request_id := ""
var _status: Label = null
var _resource_label: Label = null
var _request_label: Label = null
var _ops_status: Label = null
var _log_label: Label = null
var _logs: Array[String] = []
var _name := ""
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	_name = OS.get_environment("DSH_PLAYER_NAME")
	if _name == "":
		_name = String(get_tree().root.get_meta("player_name", "沧澜"))
	if _name == "":
		_name = "沧澜"
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	service = PortService.new(_config())
	service.bind_event_bus(null)
	print("[PORT PAGE] boot=%s ports=%d resources=%s name=%s" % [str(service.ready), service.ports.size(), str(service.resource_summary()), _name])
	_build()
	_refresh()
	set_process(true)
	if OS.get_environment("DSH_PORT_TEST") == "1":
		call_deferred("_run_port_test")
	if _shot_path != "":
		get_window().size = Vector2i(1920, 1080)
		Input.warp_mouse(Vector2(1920, 1080) * 0.5)


func _config() -> Dictionary:
	return {"ports": [
		{"id": "l1_meridian_05", "name": "L1 Meridian", "berths": ["B1", "B2", "B3"],
			"drydock_slots": 2, "tugs": ["TUG1"], "fuel_capacity_t": 2400.0, "fuel_available_t": 1900.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C1", "require_permit": true, "services": ["refuel", "repair", "tow", "shuttle"],
			"hazard": "EXAMPLE · 3 号罐泄漏 / TANK 3 LEAK", "rescue": "EXAMPLE · 救援目标 12 船员 / 12 CREW"},
		{"id": "chronos", "name": "Chronos 站", "berths": ["CH-1"], "drydock_slots": 1,
			"tugs": ["CH-TUG"], "fuel_capacity_t": 600.0, "fuel_available_t": 420.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C2", "require_permit": true, "services": ["refuel", "repair", "tow"]},
		{"id": "greenwich", "name": "Greenwich 船坞", "berths": ["G-1", "G-2"], "drydock_slots": 2,
			"tugs": ["G-TUG"], "fuel_capacity_t": 900.0, "fuel_available_t": 700.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C3", "require_permit": false, "services": ["refuel", "repair"]},
		{"id": "sextant", "name": "Sextant 泊位", "berths": ["S-1"], "drydock_slots": 0,
			"tugs": ["S-TUG"], "fuel_capacity_t": 300.0, "fuel_available_t": 260.0,
			"windows": [{"id": "W1", "open_t": 0.0, "close_t": 1000000.0}],
			"corridor": "C4", "require_permit": true, "services": ["tow", "shuttle"]},
	]}


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = P.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var rootv := VBoxContainer.new()
	rootv.add_theme_constant_override("separation", 8)
	margin.add_child(rootv)
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 74)
	rootv.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	tv.add_child(h)
	h.add_child(UiTheme.make_label("港口 / PORT · L1 MERIDIAN", false, 14, P.PH))
	h.add_child(UiTheme.make_label("指挥官 " + _name, true, 8, P.AMBER))
	_status = UiTheme.make_label("", true, 8, P.PH_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_status)
	tv.add_child(UiTheme.make_label("Chronos / Greenwich / Sextant · 泊位/船坞/拖船/燃料 · 请求/许可/窗口", true, 7, P.a(P.FAINT, 0.9)))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	rootv.add_child(body)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(410, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UiTheme.make_label("港口资源 / PORTS", false, 10, P.PH))
	_resource_label = UiTheme.make_label("", true, 8, P.TXT)
	_resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_resource_label)
	lv.add_child(HSeparator.new())
	lv.add_child(UiTheme.make_label("3 号罐 / 救援示例", false, 9, P.AMBER))
	lv.add_child(UiTheme.make_label("EXAMPLE · 3 号罐泄漏 / TANK 3 LEAK", true, 8, P.RED))
	lv.add_child(UiTheme.make_label("EXAMPLE · 救援目标 12 船员 / 12 CREW", true, 8, P.RED))
	lv.add_child(UiTheme.make_label("示例标签，不是剧情事实；不伪造伤亡/裁决。", true, 7, P.a(P.FAINT, 0.9)))
	lv.add_child(HSeparator.new())
	lv.add_child(UiTheme.make_label("请求 / REQUEST", false, 9, P.PH_DIM))
	_request_label = UiTheme.make_label("", true, 8, P.TXT)
	_request_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_request_label)
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var cv := VBoxContainer.new()
	center.add_child(cv)
	cv.add_child(UiTheme.make_label("入港窗口 / WINDOW & QUEUE", false, 10, P.PH))
	var map := PortMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(map)
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(370, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 7)
	right.add_child(rv)
	rv.add_child(UiTheme.make_label("操作 / OPERATIONS", false, 10, P.PH))
	for item in [["REQUEST DOCK", "_request_dock"], ["APPROACH", "_approach"], ["DOCK", "_dock"], ["REFUEL", "_refuel"], ["REPAIR", "_repair"], ["FINISH SERVICE", "_finish_service"], ["UNDOCK", "_undock"], ["DEPART", "_depart"]]:
		var b := Button.new()
		b.text = String(item[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, String(item[1])))
		rv.add_child(b)
	_ops_status = UiTheme.make_label("READY · 手动操作", true, 8, P.AMBER)
	_ops_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_ops_status)
	rv.add_child(UiTheme.make_label("失败显示 reason；不自动许可/对接/服务；不写剧情/物理/存档。", true, 7, P.a(P.FAINT, 0.9)))
	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 76)
	rootv.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	bv.add_child(UiTheme.make_label("日志 / LOG", false, 8, P.PH_DIM))
	_log_label = UiTheme.make_label("PORT PAGE READY", true, 7, P.a(P.DIM, 0.9))
	bv.add_child(_log_label)


func _result(res: Dictionary, action: String) -> void:
	var ok := bool(res.get("ok", false))
	var text := "%s · %s%s" % [action, "OK" if ok else "FAILED", "" if ok else " · " + String(res.get("reason", ""))]
	_logs.append(text)
	while _logs.size() > 5:
		_logs.pop_front()
	if _ops_status != null:
		_ops_status.text = text
		_ops_status.add_theme_color_override("font_color", P.PH if ok else P.RED)
	if _log_label != null:
		_log_label.text = " · ".join(_logs)
	_refresh()


func _refresh() -> void:
	if service == null:
		return
	_status.text = "t=%.0fs · requests=%d · name=%s" % [service.t_s, service.requests.size(), _name]
	var lines: Array = []
	for pid in ["l1_meridian_05", "chronos", "greenwich", "sextant"]:
		var ps: Dictionary = service.port_summary(pid)
		if ps.is_empty():
			continue
		var rs: Dictionary = ps.get("resources", {}) if ps.get("resources", {}) is Dictionary else {}
		lines.append("%s · berth %d/%d · drydock %d/%d · tug %d/%d · fuel %.0f/%.0ft" % [
			String(ps.get("name", pid)), int(rs.get("berths_free", 0)), int(rs.get("berths_total", 0)),
			int(rs.get("drydock_free", 0)), int(rs.get("drydock_total", 0)),
			int(rs.get("tugs_free", 0)), int(rs.get("tugs_total", 0)),
			float(rs.get("fuel_available_t", 0.0)), float(rs.get("fuel_capacity_t", 0.0))])
	_resource_label.text = "\n".join(lines)
	var rr: Dictionary = service.get_request(_request_id) if _request_id != "" else {}
	var wstat: Dictionary = service.window_status(PORT_ID)
	var window_txt := "WINDOW %s · %s" % ["OPEN" if bool(wstat.get("is_open", false)) else "CLOSED", String((wstat.get("window", {}) as Dictionary).get("id", "—"))]
	if rr.is_empty():
		_request_label.text = "NO REQUEST · 点击 REQUEST DOCK\n" + window_txt
	else:
		_request_label.text = "%s · status=%s · berth=%s · reason=%s\n%s" % [String(rr.get("request_id", "")), String(rr.get("status", "")), String(rr.get("berth_id", "—")), String(rr.get("reason", "")), window_txt]


func _run_port_test() -> void:
	# 仅 DSH_PORT_TEST=1 验证 PortService 真实 API；不自动切场景。
	_request_dock()
	if _request_id != "":
		_approach()
		_dock()
		_refuel()
		_finish_service()
		_repair()
		_finish_service()
		_undock()
	_log("PORT TEST state=" + String(service.get_request(_request_id).get("status", "")))


func _request_dock() -> void:
	var req: Dictionary = service.request("dock", SHIP_ID, PORT_ID, {"priority": 2, "clearance": "L1-CLEARANCE-001"})
	_result(req, "REQUEST DOCK")
	if bool(req.get("ok", false)):
		_request_id = String(req.get("request_id", ""))
		var perm: Dictionary = service.permit(_request_id)
		_result(perm, "PERMIT " + _request_id)
	else:
		_logs.append("REQUEST reason " + String(req.get("reason", "")))


func _approach() -> void:
	if _request_id == "":
		_result({"ok": false, "reason": "no_request"}, "APPROACH")
		return
	_result(service.approach(_request_id), "APPROACH " + _request_id)


func _dock() -> void:
	_result(service.dock(_request_id), "DOCK " + _request_id)


func _refuel() -> void:
	_result(service.refuel(_request_id, 100.0), "REFUEL 100t")


func _repair() -> void:
	_result(service.repair(_request_id), "REPAIR")


func _finish_service() -> void:
	_result(service.finish_service(_request_id), "FINISH SERVICE")


func _undock() -> void:
	_result(service.undock(_request_id), "UNDOCK")


func _depart() -> void:
	var rr: Dictionary = service.get_request(_request_id) if _request_id != "" else {}
	if String(rr.get("status", "")) != "DEPARTED":
		_result({"ok": false, "reason": "not_departed · 先 UNDOCK"}, "DEPART")
		return
	get_tree().root.set_meta("player_name", _name)
	OS.set_environment("DSH_PLAYER_NAME", _name)
	_logs.append("FLOW DEPART → game_shell.tscn · name=" + _name)
	get_tree().change_scene_to_file("res://game_shell.tscn")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 20 == 0:
		_refresh()
	if _shot_path != "" and _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("PORT PAGE SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


class PortMap extends Control:
	const PP := preload("res://scripts/pal.gd")
	const FF := preload("res://scripts/fonts.gd")

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, PP.a(PP.EARTH, 0.6))
		draw_rect(r, PP.a(PP.LINE, 0.6), false, 1.0)
		var mono := FF.mono()
		for i in range(80):
			var hh := (i * 1103515245 + 12345) & 0x7fffffff
			draw_rect(Rect2(12.0 + float(hh % int(maxf(1.0, size.x - 24.0))), 12.0 + float((hh / 97) % int(maxf(1.0, size.y - 120.0))), 1, 1), PP.a(PP.TXT, 0.08))
		var c := Vector2(size.x * 0.5, size.y * 0.42)
		draw_arc(c, 100.0, 0, TAU, 64, PP.a(PP.PH_DIM, 0.35), 1.0, true)
		draw_circle(c, 4.0, PP.PH)
		var labels := [["Chronos", -140.0, -40.0], ["Greenwich", 110.0, 60.0], ["Sextant", 120.0, -70.0], ["Meridian", -80.0, 90.0]]
		for lab in labels:
			var q := c + Vector2(float(lab[1]), float(lab[2]))
			draw_circle(q, 3.0, PP.AMBER)
			draw_line(c, q, PP.a(PP.LINE2, 0.45), 1.0)
			draw_string(mono, q + Vector2(6, 4), String(lab[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, PP.TXT)
		draw_string(mono, Vector2(14, size.y - 18), "L1 MERIDIAN · BERTH/DOCK/TUG/WINDOW · SHADOW PORT SERVICE", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, PP.a(PP.FAINT, 0.9))


func _log(text: String) -> void:
	print("[PORT PAGE] ", text)
