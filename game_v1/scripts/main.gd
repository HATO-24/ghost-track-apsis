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
var _frames := 0

func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	print("MAIN READY env=", _shot_path)
	get_window().title = "AD-FLEET // 战术显控台 — GUI DEMO 01"
	get_window().size = Vector2i(1600, 900)
	var screen := DisplayServer.screen_get_size()
	get_window().position = Vector2i((screen.x - 1600) / 2, (screen.y - 900) / 2)
	if _shot_path != "":
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

func _process(delta: float) -> void:
	if not state.paused:
		state.clock += delta * state.time_scale
	state.elapsed += delta
	hud.queue_redraw()

	_frames += 1
	if _shot_path != "":
		if _frames == 3:
			print("PROC RUNNING frame=3")
		if _frames >= 45:
			var img := vp.get_texture().get_image()
			print("IMG size=", img.get_size(), " empty=", img.is_empty())
			var err := img.save_png(_shot_path)
			print("SAVE err=", err, " path=", _shot_path)
			get_tree().quit()

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