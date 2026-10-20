extends Control

# 阶段1B：玩家名输入组合示例（玩家名输入 + 自绘候选窗）。
# 独立 scene；不接剧情/存档。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const ImeInput := preload("res://scripts/ui/ime_input.gd")
const ImeCandidate := preload("res://scripts/ui/ime_candidate.gd")

signal name_submitted(name: String)
signal name_cancelled

var input
var candidate
var status_label
var confirm_btn
var _shot_path := ""
var _frames := 0
var _demo := false


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	_demo = OS.get_environment("DSH_UI_IME_DEMO") == "1"
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
			win.size = Vector2i(1920, 1080)
	_build()
	if _demo:
		call_deferred("_apply_demo")
	set_process(true)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = P.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 430)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UiTheme.make_label("玩家名 / PLAYER NAME", false, 16, P.PH))
	v.add_child(UiTheme.make_label("中日英输入 · 自绘候选窗 · 不接剧情/存档", true, 8, P.a(P.DIM, 0.95)))
	v.add_child(HSeparator.new())
	input = ImeInput.new()
	input.custom_minimum_size = Vector2(0, 46)
	input.placeholder = "输入玩家名（中文/日本語/English）"
	input.max_length = 24
	input.duplicate_names = ["Apsis", "哈马丹", "Hammer"]
	input.text_changed.connect(func(t): _on_input(t, "TEXT"))
	input.composition_changed.connect(func(c): _on_input(c, "COMPOSE"))
	input.submitted.connect(_on_submitted)
	input.cancelled.connect(_on_cancelled)
	v.add_child(input)
	var hint := UiTheme.make_label("↑↓ 选择候选 · ENTER 确认 · ESC 取消 · PgUp/PgDn 翻页 · 长度上限 24", true, 7, P.a(P.FAINT, 0.95))
	v.add_child(hint)
	status_label = UiTheme.make_label("", true, 8, P.AMBER)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var demo_btn := Button.new()
	demo_btn.text = "载入候选示例 / DEMO IME"
	demo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo_btn.pressed.connect(_apply_demo)
	confirm_btn = Button.new()
	confirm_btn.text = "确认玩家名 / CONFIRM"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(func(): input.commit_name())
	var cancel_btn := Button.new()
	cancel_btn.text = "取消 / CANCEL"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): input.cancel(); name_cancelled.emit())
	row.add_child(demo_btn)
	row.add_child(confirm_btn)
	row.add_child(cancel_btn)
	v.add_child(row)
	v.add_child(UiTheme.make_label("GODOT IME 边界：系统组合事件平台相关；候选窗自绘，候选由外部注入。", true, 7, P.a(P.FAINT, 0.9)))
	# candidate overlay on root (positioned after layout)
	candidate = ImeCandidate.new()
	candidate.z_index = 50
	add_child(candidate)
	input.candidate_window = candidate


func _apply_demo() -> void:
	if input == null:
		return
	input.set_composition("沧", ["沧澜", "沧海", "沧溟", "苍岚", "苍梧"])
	input.focus_input()
	status_label.text = "DEMO：组合串「沧」· 候选 5 · ↑↓ / ENTER 选择（注入模拟，非系统 IME）"
	_update_candidate_placement()


func _update_candidate_placement() -> void:
	if input == null or candidate == null:
		return
	var gr: Rect2 = input.get_global_rect()
	input.input_rect = gr
	candidate.place(gr)


func _on_input(t: String, typ: String) -> void:
	if status_label != null:
		var v: Dictionary = input.validate_name(input.text)
		status_label.text = "%s · text=%s · comp=%s · valid=%s/%s" % [typ, input.text, input.composition, str(bool(v.get("ok", false))), String(v.get("reason", ""))]
	_update_candidate_placement()


func _on_submitted(res: Dictionary) -> void:
	var ok := bool(res.get("ok", false))
	status_label.text = "SUBMIT %s · name=%s · reason=%s" % ["OK" if ok else "REJECT", String(res.get("value", "")), String(res.get("reason", ""))]
	if ok:
		name_submitted.emit(String(res.get("value", "")))
	else:
		status_label.add_theme_color_override("font_color", P.RED)


func _on_cancelled() -> void:
	if status_label != null:
		status_label.text = "CANCELLED · 组合/输入取消"
	name_cancelled.emit()


func _process(_delta: float) -> void:
	if input != null and candidate != null:
		_update_candidate_placement()
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("IME SHOT size=%s err=%d → %s" % [str(img.get_size()), err, _shot_path])
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if candidate != null and candidate.visible and candidate.get_global_rect().has_point(event.position):
			return
		if input != null and input.get_global_rect().has_point(event.position):
			return
		if input != null:
			input.release_focus()
