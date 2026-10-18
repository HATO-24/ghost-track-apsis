extends Control

const StateScript := preload("res://scripts/state.gd")
const PlotScript := preload("res://scripts/plot.gd")
const HudScript := preload("res://scripts/hud.gd")

const BASE := Vector2i(1920, 1080)

var state = StateScript.new()
var vp: SubViewport
var plot
var hud
var _shot_path := ""
var _scene := ""
var _gif_dir := ""
var _frames := 0

func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	_scene = OS.get_environment("DSH_SCENE")
	_gif_dir = OS.get_environment("DSH_GIF")
	print("MAIN READY shot=", _shot_path, " scene=", _scene, " gif=", _gif_dir)
	get_window().title = "AD-FLEET // 战术显控台 — V1.5"
	get_window().size = Vector2i(1600, 900)
	var screen := DisplayServer.screen_get_size()
	get_window().position = Vector2i((screen.x - 1600) / 2, (screen.y - 900) / 2)
	if _shot_path != "" or _gif_dir != "":
		get_window().borderless = true
		get_window().size = Vector2i(1920, 1080)
		get_window().position = Vector2i(0, 0)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	vp = SubViewport.new()
	vp.size = BASE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.gui_disable_input = true
	svc.add_child(vp)

	var root := Control.new()
	root.size = Vector2(BASE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(root)

	plot = PlotScript.new()
	plot.state = state
	plot.position = Vector2(396, 124)
	plot.size = Vector2(1128, 752)
	plot.clip_contents = true
	plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plot)

	hud = HudScript.new()
	hud.state = state
	hud.position = Vector2.ZERO
	hud.size = Vector2(BASE)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	var crt := ColorRect.new()
	crt.position = Vector2(40, 40)
	crt.size = Vector2(1840, 1000)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crt.gdshader")
	crt.material = mat
	root.add_child(crt)

	if _shot_path != "":
		state.capture = true
		state.paused = true
		state.boot_t = 2.0
		_set_scene(_scene)
	elif _gif_dir != "":
		state.capture = true
		state.paused = true
		_capture_gif(_gif_dir)

func _set_scene(sc: String) -> void:
	state.sensor = 0
	if sc == "ir":
		state.sensor = 1
	elif sc == "radar":
		state.sensor = 2
	elif sc == "optical":
		state.sensor = 3
	if sc == "boot":
		state.boot_t = 1.0
	if hud != null:
		hud.menu_open = (sc == "menu")
		hud.menu_t = 0.5
	state.sensor_fx_t = -1.0

func _process(delta: float) -> void:
	if not state.capture and state.boot_t < 2.0:
		state.boot_t = minf(2.0, state.boot_t + delta)
	if not state.paused:
		state.clock += delta * state.time_scale
	state.elapsed += delta
	hud.queue_redraw()

	_frames += 1
	if _shot_path != "" and _frames >= 45:
		var img := vp.get_texture().get_image()
		var err := img.save_png(_shot_path)
		print("SHOT ", img.get_size(), " err=", err, " → ", _shot_path)
		get_tree().quit()

func _capture_gif(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 120
	var ns := OS.get_environment("DSH_GIF_N")
	if ns != "":
		n = int(ns)
	for i in range(n):
		_apply_demo(float(i) / 12.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.save_png(dir + "/f%03d.png" % i)
	print("GIF FRAMES DONE ", dir)
	get_tree().quit()

func _apply_demo(t: float) -> void:
	state.boot_t = 2.0
	hud.menu_open = false
	var prev := int(state.sensor)
	state.sensor = 0
	if t < 1.6:
		state.boot_t = t
		return
	if t >= 3.6 and t < 4.5:
		hud.menu_open = true
		hud.menu_t = t - 3.6
	if t >= 4.5:
		state.sensor = 1
	if t >= 6.0:
		state.sensor = 2
	if t >= 7.5:
		state.sensor = 3
	if state.sensor != prev:
		state.sensor_fx_t = 0.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if size.x <= 1.0:
			return
		var p: Vector2 = event.position * (Vector2(BASE) / size)
		hud.click(p)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			state.paused = not state.paused
		KEY_1:
			state.time_scale = 1.0
			state.paused = false
		KEY_2:
			state.time_scale = 10.0
			state.paused = false
		KEY_3:
			state.time_scale = 60.0
			state.paused = false
		KEY_4:
			state.time_scale = 300.0
			state.paused = false
		KEY_ESCAPE:
			get_tree().quit()
