extends Control

# 阶段2-SCENE-1：L4-02 Hammer → L1 Meridian 真实转场场景。
# 数据：framework/content/scenario_transit_l4_l1.json + transfer_planner.plan()（缓存一次）。
# 视觉：V1 HUD（1920×1080 / Palette / 1px / 7–14pt）；不接旧 Chronos 关卡。
# 不改旧 HUD/plot/state/bridge/framework；不写 world；只推进本地转场时间。

const TransferPlanner := preload("res://framework/sim/transfer_planner.gd")
const TransitHUD := preload("res://scripts/transit_hud.gd")
const TransitSensors := preload("res://scripts/transit_sensors.gd")
const TeachingController := preload("res://scripts/teaching_controller.gd")
const TransitDamage := preload("res://scripts/transit_damage.gd")
const Palette := preload("res://scripts/pal.gd")
const Fonts := preload("res://scripts/fonts.gd")

const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"
const PLAN_CACHE_PATH := "res://framework/content/transfer_l4_l1_cached.json"
const BASE := Vector2i(1920, 1080)

var scenario: Dictionary = {}
var plan: Dictionary = {}
var t: float = 0.0
var tof_s: float = 0.0
var playing := false
var speed := 100.0
var phase := "departure"
var hud
var sensors
var teach
var damage
var destination := "L1 Meridian"
var damage_open := false
var modal_page := ""
var ui_mode := "ship"
var optical_open := false
var tutorial_open := false
var last_note := ""
var _frames := 0
var _shot_path := ""
var _shot_mode := ""
var _ready_t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var win := get_window()
	if win != null:
		win.title = "GHOST TRACK // APSIS — 阶段2 转场"
		win.size = Vector2i(1920, 1080)
		win.position = Vector2i(0, 0)
	_shot_path = OS.get_environment("DSH_SHOT")
	_shot_mode = OS.get_environment("DSH_TRANSIT_ARRIVAL")
	_load_scenario()
	_plan_transfer()
	sensors = TransitSensors.new({})
	teach = TeachingController.new("res://framework/content/teaching_l4_l1.json")
	damage = TransitDamage.new({})
	destination = "L1 Meridian"
	ui_mode = "ship"
	var view := OS.get_environment("DSH_TRANSIT_VIEW")
	if view == "target":
		ui_mode = "target"
	elif view == "tutorial":
		tutorial_open = true
	elif view == "damage":
		ui_mode = "ship"
		damage_open = true
	elif view == "iff":
		ui_mode = "target"
	elif view == "radar":
		ui_mode = "ship"
	hud = TransitHUD.new()
	hud.sim = self
	hud.position = Vector2.ZERO
	hud.size = Vector2(1920, 1080)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	# 截图默认 pre-cruise；arrival 模式到 TOF 终点
	if tof_s > 0.0:
		var frac := float(OS.get_environment("DSH_TRANSIT_T")) if OS.get_environment("DSH_TRANSIT_T") != "" else 0.35
		if _shot_mode == "1":
			frac = 1.0
		t = clampf(frac, 0.0, 1.0) * tof_s
		if sensors != null:
			sensors.seek(t)
			if view == "target":
				sensors.set_target("l1_meridian_05")
			elif view == "damage":
				sensors.select_ship("harmattan")
			elif view == "iff":
				sensors.select_ship("harmattan")
				sensors.set_target("l1_meridian_05")
				sensors.iff_query("l1_meridian_05")
			elif view == "radar":
				sensors.select_ship("harmattan")
				sensors.set_radar_enabled(true)
			elif view == "sensor":
				sensors.select_ship("harmattan")
				sensors.set_target("l1_meridian_05")
				sensors.start_optical("optical", "l1_meridian_05")
				sensors.start_optical("ir", "l1_meridian_05")
				sensors.seek(t)
				optical_open = true
		_update_phase()
	print("TRANSIT READY plan_ok=%s tof_s=%.1f timeline=%d fleet=%d scenario=%s" % [
		str(bool(plan.get("ok", false))), tof_s, (plan.get("timeline", []) as Array).size() if plan.get("timeline", []) is Array else 0,
		(plan.get("fleet", []) as Array).size() if plan.get("fleet", []) is Array else 0,
		String(scenario.get("title", ""))])
	if _shot_path != "":
		get_window().borderless = true
		get_window().size = BASE
		get_window().position = Vector2i(0, 0)
	queue_redraw()


func _load_scenario() -> void:
	scenario = {}
	if not FileAccess.file_exists(SCENARIO_PATH):
		return
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		scenario = parsed


func _plan_transfer() -> void:
	# 优先加载预计算缓存，避免启动时 19s 规划卡顿；缓存在写入时已验证 ok=true。
	plan = {}
	if FileAccess.file_exists(PLAN_CACHE_PATH):
		var cf := FileAccess.open(PLAN_CACHE_PATH, FileAccess.READ)
		if cf != null:
			var ctxt := cf.get_as_text()
			cf.close()
			var cparsed = JSON.parse_string(ctxt)
			if cparsed is Dictionary and bool((cparsed as Dictionary).get("ok", false)):
				plan = cparsed
	if plan.is_empty():
		# 缓存缺失/损坏才重算；失败不伪造轨迹。
		plan = TransferPlanner.plan({})
	var tr: Dictionary = plan.get("transfer", {}) if plan.get("transfer", {}) is Dictionary else {}
	tof_s = float(tr.get("tof_s", 0.0))
	playing = false


func _process(delta: float) -> void:
	_ready_t += delta
	if tof_s <= 0.0 and _ready_t > 1.0:
		playing = false
	elif playing:
		t += delta * speed
	if sensors != null:
		if playing:
			var vm_s: Dictionary = sensors.step(delta * speed)
			t = clampf(float(sensors.t), 0.0, tof_s) if tof_s > 0.0 else t
		else:
			if absf(float(sensors.t) - t) > 1.0e-6:
				sensors.seek(t)
		if teach != null:
			teach.tick(t)
		if damage != null:
			damage.step(delta)
	if tof_s > 0.0:
		t = clampf(t, 0.0, tof_s)
		_update_phase()
	if _shot_path != "":
		_frames += 1
		if _frames >= 40:
			_save_shot()
	if hud != null:
		hud.queue_redraw()


func _update_phase() -> void:
	if tof_s <= 0.0:
		phase = "not_ready"
	elif t <= 1.0:
		phase = "departure"
	elif t >= tof_s - 1.0:
		phase = "arrival"
	else:
		phase = "cruise"


func _frac() -> float:
	return clampf(t / maxf(1.0, tof_s), 0.0, 1.0)


func seek_to(new_t: float) -> void:
	t = clampf(new_t, 0.0, tof_s)
	if sensors != null:
		sensors.seek(t)
	if teach != null:
		teach.tick(t)
	_update_phase()


func ui_select_ship(ship_id: String) -> void:
	if sensors == null:
		return
	var r: Dictionary = sensors.select_ship(ship_id)
	ui_mode = "ship"
	last_note = "SELECT SHIP " + ship_id + ("" if bool(r.get("ok", false)) else " · " + String(r.get("reason", "")))
	if teach != null and bool(r.get("ok", false)):
		var tr: Dictionary = teach.note("select_ship", ship_id)
		last_note += " · teach=" + String(tr.get("reason", "")) if not bool(tr.get("ok", false)) else " · teach✓"
	queue_redraw()


func ui_select_target(target_id: String) -> void:
	if sensors == null:
		return
	var r: Dictionary = sensors.set_target(target_id)
	ui_mode = "target"
	last_note = "TARGET " + target_id + ("" if bool(r.get("ok", false)) else " · " + String(r.get("reason", "")))
	if teach != null and bool(r.get("ok", false)):
		var tr2: Dictionary = teach.note("open_contact_list", target_id)
		last_note += " · teach=" + String(tr2.get("reason", "")) if not bool(tr2.get("ok", false)) else " · teach✓"
	queue_redraw()


func ui_optical_start(kind: String) -> void:
	if sensors == null:
		return
	var tgt := String(sensors.selected_target)
	var r: Dictionary = sensors.start_optical(kind, tgt)
	optical_open = true
	last_note = "OPTICAL %s %s" % [kind, "START" if bool(r.get("ok", false)) else String(r.get("reason", "fail"))]
	if teach != null and bool(r.get("ok", false)):
		var tr3: Dictionary = teach.note("optical_channel", tgt, {"track_level": 3})
		last_note += " · teach=" + String(tr3.get("reason", "")) if not bool(tr3.get("ok", false)) else " · teach✓"
	queue_redraw()


func ui_optical_stop() -> void:
	if sensors != null:
		var r: Dictionary = sensors.stop_optical()
		last_note = "OPTICAL STOP" if bool(r.get("ok", false)) else "OPTICAL STOP · " + String(r.get("reason", "fail"))
	optical_open = false
	queue_redraw()


func ui_ignite() -> void:
	seek_to(0.0)
	if teach != null:
		var tr: Dictionary = teach.note("confirm_burn")
		last_note = "IGNITE · teach=" + String(tr.get("reason", "")) if not bool(tr.get("ok", false)) else "IGNITE · teach✓"
	playing = false
	queue_redraw()


func ui_arrive() -> void:
	seek_to(tof_s)
	if teach != null:
		var tr: Dictionary = teach.note("arrive_l1")
		last_note = "ARRIVE · teach=" + String(tr.get("reason", "")) if not bool(tr.get("ok", false)) else "ARRIVE · teach✓"
	playing = false
	queue_redraw()


func teach_note(action: String, target := "", extra := {}) -> void:
	if teach == null:
		return
	var r: Dictionary = teach.note(action, target, extra)
	last_note = "TEACH %s · %s" % [action, "ok " + String(r.get("matched_step_id", "")) if bool(r.get("ok", false)) else String(r.get("reason", ""))]
	queue_redraw()


func ui_toggle_damage() -> void:
	damage_open = not damage_open
	modal_page = ""
	queue_redraw()


func ui_damage_fix(section_id: String) -> void:
	if damage == null:
		return
	var r: Dictionary = damage.assign_repair(String(sensors.selected_ship), section_id, 2)
	last_note = "DAMAGE FIX %s · %s" % [section_id, "ok" if bool(r.get("ok", false)) else String(r.get("reason", "fail"))]
	queue_redraw()


func ui_damage_priority(section_id: String, priority: int) -> void:
	if damage == null:
		return
	var r: Dictionary = damage.set_priority(String(sensors.selected_ship), section_id, priority)
	last_note = "DAMAGE PRI %s → %d · %s" % [section_id, priority, "ok" if bool(r.get("ok", false)) else String(r.get("reason", "fail"))]
	queue_redraw()


func ui_damage_cancel(section_id: String) -> void:
	if damage == null:
		return
	var r: Dictionary = damage.cancel_repair(String(sensors.selected_ship), section_id)
	last_note = "DAMAGE CANCEL %s · %s" % [section_id, "ok" if bool(r.get("ok", false)) else String(r.get("reason", "fail"))]
	queue_redraw()


func ui_set_radar(on: bool) -> void:
	if sensors == null:
		return
	var r: Dictionary = sensors.set_radar_enabled(on)
	last_note = "RADAR %s · EMCON=%s" % ["ON" if bool(r.get("radar_enabled", false)) else "OFF", str(bool(r.get("emcon", false)))]
	if bool(r.get("ok", false)) and teach != null:
		var tr: Dictionary = teach.note("sensor_toggle", "harmattan/YW-R9", {"value": "on" if on else "off"})
		last_note += " · teach=" + String(tr.get("reason", "")) if not bool(tr.get("ok", false)) else " · teach✓"
	queue_redraw()


func ui_set_emcon(on: bool) -> void:
	if sensors == null:
		return
	var r: Dictionary = sensors.set_emcon(on)
	last_note = "EMCON %s" % ("ON" if bool(r.get("emcon", false)) else "OFF")
	queue_redraw()


func ui_iff() -> void:
	if sensors == null:
		return
	var tgt := String(sensors.selected_target)
	var r: Dictionary = sensors.iff_query(tgt)
	ui_mode = "target"
	last_note = "IFF %s · %s · hostile=%s" % [tgt, String(r.get("status", "fail")), str(bool(r.get("hostile", false)))]
	if bool(r.get("ok", false)) and teach != null:
		var tr: Dictionary = teach.note("iff_query", tgt, {"track": tgt})
		last_note += " · teach=" + String(tr.get("reason", "")) if not bool(tr.get("ok", false)) else " · teach✓"
	queue_redraw()


func ui_set_destination() -> void:
	destination = "L1 Meridian"
	last_note = "DESTINATION → L1 Meridian"
	if teach != null:
		var tr: Dictionary = teach.note("set_destination", "meridian")
		last_note += " · teach✓" if bool(tr.get("ok", false)) else " · teach=" + String(tr.get("reason", ""))
	queue_redraw()


func ui_open_modal(page: String) -> void:
	modal_page = page
	last_note = "MODAL " + page
	if teach != null:
		match page:
			"roe":
				teach.note("open_roe_card")
			"hold":
				teach.note("decision", "HOLD")
			"report":
				teach.note("report_submit", "INTERNAL_AFTER_ACTION")
	queue_redraw()


func _save_shot() -> void:
	if _shot_path == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var err := img.save_png(_shot_path)
		print("TRANSIT SHOT (1920,1080) err=%d → %s" % [err, _shot_path])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			playing = not playing
		KEY_1:
			speed = 1.0
			playing = true
		KEY_2:
			speed = 100.0
			playing = true
		KEY_3:
			speed = 1000.0
			playing = true
		KEY_4:
			speed = 10000.0
			playing = true
		KEY_HOME:
			t = 0.0
			playing = false
		KEY_END:
			t = tof_s
			playing = false
		KEY_R:
			t = 0.0
			playing = true
		KEY_ESCAPE:
			get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud != null and hud.has_method("handle_click"):
			if bool(hud.call("handle_click", event.position)):
				accept_event()
