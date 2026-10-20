extends Control

# 阶段2-SCENE-1：L4-02 Hammer → L1 Meridian 真实转场场景。
# 数据：framework/content/scenario_transit_l4_l1.json + transfer_planner.plan()（缓存一次）。
# 视觉：V1 HUD（1920×1080 / Palette / 1px / 7–14pt）；不接旧 Chronos 关卡。
# 不改旧 HUD/plot/state/bridge/framework；不写 world；只推进本地转场时间。

const TransferPlanner := preload("res://framework/sim/transfer_planner.gd")
const TransitHUD := preload("res://scripts/transit_hud.gd")
const Palette := preload("res://scripts/pal.gd")
const Fonts := preload("res://scripts/fonts.gd")

const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"
const BASE := Vector2i(1920, 1080)

var scenario: Dictionary = {}
var plan: Dictionary = {}
var t: float = 0.0
var tof_s: float = 0.0
var playing := false
var speed := 100.0
var phase := "departure"
var hud
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
	# 真实 transfer_planner 计算一次并缓存；失败不伪造轨迹。
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
