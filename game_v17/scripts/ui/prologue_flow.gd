extends Control

# 阶段1H 序章入口：玩家名 → 行动简报 → game_shell。
# 文本从 content JSON 按常量 key 读取（DRAFT）；不硬编码剧情；
# 不实现导航/物理/存档；不自动跳过简报。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const ImeInput := preload("res://scripts/ui/ime_input.gd")
const ImeCandidate := preload("res://scripts/ui/ime_candidate.gd")
const BriefingPanel := preload("res://scripts/ui/briefing_panel.gd")
const PrologueController := preload("res://scripts/core/prologue_controller.gd")

const STORY_PATH := "res://framework/content/story_l1.json"
const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"
const NAV_SCENE := "res://nav_page.tscn"
const BRIEFING_DATE := "2193-11-07"

# 文本 key（内容层）：不在脚本硬编码简报正文。
const TEXT_KEYS := {
	"title": "prelude.title",
	"body": "prelude.body",
	"confirm": "prelude.confirm_text",
	"execute": "prelude.execute_text",
	"fire_hint": "fire_option.hint",
	"notice_body": "notice.body",
	"notice_from": "notice.from",
	"notice_to": "notice.to",
}

var phase := "name"
var _input = null
var _candidate = null
var _briefing = null
var _status: Label = null
var _name_page: Control = null
var _frames := 0
var _shot_path := ""
var _name := ""
var controller = null


func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
		if _shot_path != "":
			win.borderless = true
			win.position = Vector2i(0, 0)
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	controller = PrologueController.new({})
	var phase_env := OS.get_environment("DSH_PROLOGUE_PHASE")
	var start_briefing := phase_env == "briefing"
	if start_briefing:
		var pname := OS.get_environment("DSH_PLAYER_NAME")
		if pname == "":
			pname = "沧澜"
		controller.submit_name(pname)
		_name = pname
		_flow_write("briefing")
	_show_phase("briefing" if start_briefing else "name")
	set_process(true)
	if OS.get_environment("DSH_FLOW_SMOKE") == "1":
		call_deferred("_flow_smoke_start")
	if _shot_path != "":
		get_window().size = Vector2i(1920, 1080)
		Input.warp_mouse(Vector2(1920, 1080) * 0.5)


func _show_phase(p: String) -> void:
	phase = p
	for c in get_children():
		if c is ColorRect:
			continue
		c.queue_free()
	if _bg_missing():
		var bg := ColorRect.new()
		bg.color = P.BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg, 0)
	if p == "briefing":
		_show_briefing()
	else:
		_show_name()


func _bg_missing() -> bool:
	for c in get_children():
		if c is ColorRect:
			return false
	return true


func _show_name() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 430)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UiTheme.make_label("序章 / PROLOGUE · 玩家名", false, 16, P.PH))
	v.add_child(UiTheme.make_label("DRAFT · 输入后进入行动简报 · 不接剧情/存档", true, 8, P.a(P.DIM, 0.9)))
	v.add_child(HSeparator.new())
	_input = ImeInput.new()
	_input.custom_minimum_size = Vector2(0, 46)
	_input.max_length = 24
	_input.placeholder = "输入玩家名（中文/日本語/English）"
	_input.text_changed.connect(func(t): _on_name_text(t, "TEXT"))
	_input.composition_changed.connect(func(c): _on_name_text(c, "COMPOSE"))
	_input.submitted.connect(_on_name_submitted)
	_input.cancelled.connect(func(): _status.text = "CANCELLED · 输入未提交")
	v.add_child(_input)
	_candidate = ImeCandidate.new()
	_candidate.z_index = 50
	add_child(_candidate)
	_input.candidate_window = _candidate
	_status = UiTheme.make_label("ENTER 确认 / ESC 取消 · 名字长度 2–24", true, 8, P.a(P.FAINT, 0.95))
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var confirm := Button.new()
	confirm.text = "确认 / CONFIRM"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func(): _input.commit_name())
	var client := Button.new()
	client.text = "输入示例 / DEMO IME"
	client.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	client.pressed.connect(_apply_name_demo)
	row.add_child(confirm)
	row.add_child(client)
	v.add_child(row)
	v.add_child(UiTheme.make_label("IME 组合/候选由 ImeInput 自绘；真实系统 IME 需平台桥接。", true, 7, P.a(P.FAINT, 0.9)))
	if OS.get_environment("DSH_PROLOGUE_DEMO") == "1":
		call_deferred("_apply_name_demo")
	else:
		_input.focus_input()


func _apply_name_demo() -> void:
	if _input == null:
		return
	_input.set_composition("沧", ["沧澜", "沧海", "沧溟", "苍岚", "苍梧"])
	_input.focus_input()
	if _status != null:
		_status.text = "DEMO：组合串「沧」· ↑↓ 选择 · ENTER 确认"


func _on_name_text(t: String, typ: String) -> void:
	if _status == null or _input == null:
		return
	var vr: Dictionary = _input.validate_name(_input.text)
	_status.text = "%s · name=%s · comp=%s · valid=%s/%s" % [typ, _input.text, _input.composition, str(bool(vr.get("ok", false))), String(vr.get("reason", ""))]
	if _candidate != null and _input != null:
		var gr: Rect2 = _input.get_global_rect()
		_input.input_rect = gr
		_candidate.place(gr)


func _flow_smoke_start() -> void:
	_name = "沧澜"
	if controller == null:
		controller = PrologueController.new({})
	controller.submit_name(_name)
	_flow_write("briefing")
	_enter_nav()


func _on_name_submitted(res: Dictionary) -> void:
	if not bool(res.get("ok", false)):
		_status.text = "REJECT · " + String(res.get("reason", "invalid_name"))
		_status.add_theme_color_override("font_color", P.RED)
		return
	_name = String(res.get("value", ""))
	if controller == null:
		controller = PrologueController.new({})
	var cr: Dictionary = controller.submit_name(_name)
	if not bool(cr.get("ok", false)):
		_status.text = "FLOW REJECT · " + String(cr.get("reason", ""))
		_status.add_theme_color_override("font_color", P.RED)
		return
	_flow_write("briefing")
	_show_phase("briefing")


func _flow_write(phase: String) -> void:
	var saved := ""
	if controller != null:
		saved = controller.save_state()
	var flow := {"player_name": _name, "controller_save": saved, "phase": phase,
		"updated_utc": Time.get_datetime_string_from_system(true)}
	get_tree().root.set_meta("flow_state", flow)
	if _name != "":
		get_tree().root.set_meta("player_name", _name)
		OS.set_environment("DSH_PLAYER_NAME", _name)
	print("[PROLOGUE] FLOW write phase=", phase, " saved_bytes=", saved.length())


func _load_story() -> Dictionary:
	if not FileAccess.file_exists(STORY_PATH):
		return {}
	var f := FileAccess.open(STORY_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed.get("story", {}) if parsed is Dictionary and parsed.get("story") is Dictionary else {}


func _resolve_key(root: Dictionary, path: String) -> String:
	var cur: Variant = root
	for part in path.split("."):
		if not (cur is Dictionary):
			return ""
		cur = (cur as Dictionary).get(part, "")
	return String(cur)


func _load_briefing_data() -> Dictionary:
	var story := _load_story()
	var scenario: Dictionary = {}
	if FileAccess.file_exists(SCENARIO_PATH):
		var f := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				scenario = parsed
	var fleet: Array = []
	for raw in (scenario.get("entities", []) if scenario.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == "ship":
			var e: Dictionary = raw
			fleet.append({"batch": String(e.get("batch", "")), "name": String(e.get("name", "")), "role": String(e.get("role", e.get("class", "")))})
	var from_name := "L4-02 Hammer"
	var to_name := "L1 Meridian"
	if scenario.get("source") is Dictionary:
		from_name = String((scenario.get("source") as Dictionary).get("name", from_name))
	if scenario.get("target") is Dictionary:
		to_name = String((scenario.get("target") as Dictionary).get("name", to_name))
	var objectives: Array = []
	for k in ["confirm", "execute"]:
		var t := _resolve_key(story, String(TEXT_KEYS[k]))
		if t != "":
			objectives.append(t)
	var roe: Array = ["WEAPONS HOLD / 仅自衛 · 武器释放需授权"]
	var fh := _resolve_key(story, String(TEXT_KEYS["fire_hint"]))
	if fh != "":
		roe.append(fh)
	return {
		"date": BRIEFING_DATE,
		"title": _resolve_key(story, String(TEXT_KEYS["title"])),
		"body": _resolve_key(story, String(TEXT_KEYS["body"])),
		"from": from_name + " · ID13 APSIS",
		"to": to_name,
		"objectives": objectives,
		"roe": roe,
		"fleet": fleet,
		"draft": true,
	}


func _show_briefing() -> void:
	_briefing = BriefingPanel.new()
	_briefing.set_anchors_preset(Control.PRESET_FULL_RECT)
	_briefing.set_data(_load_briefing_data())
	_briefing.continue_requested.connect(_enter_nav)
	_briefing.skip_requested.connect(_enter_nav)
	add_child(_briefing)


func _enter_nav() -> void:
	# 手动 CONTINUE/SKIP：写 controller save + 名字 + 阶段，再切 nav；不自动跳过简报。
	if _name != "":
		get_tree().root.set_meta("player_name", _name)
		OS.set_environment("DSH_PLAYER_NAME", _name)
	if controller == null:
		controller = PrologueController.new({})
	if String(controller.player_name) == "":
		controller.submit_name(_name if _name != "" else "沧澜")
	if String(controller.state) == "BRIEFING":
		if not bool(controller.confirm_briefing().get("ok", false)):
			print("[PROLOGUE] FLOW CONTINUE FAILED")
			return
	if String(controller.state) == "HANDOVER":
		if not bool(controller.accept_handover().get("ok", false)):
			print("[PROLOGUE] FLOW HANDOVER FAILED")
			return
	if String(controller.state) != "NAVIGATION":
		print("[PROLOGUE] FLOW STATE INVALID ", controller.state)
		return
	_flow_write("navigation")
	get_tree().change_scene_to_file(NAV_SCENE)


func _process(_delta: float) -> void:
	if _input != null and _candidate != null:
		var gr: Rect2 = _input.get_global_rect()
		_input.input_rect = gr
		_candidate.place(gr)
	if _shot_path == "":
		return
	_frames += 1
	if _frames >= 40:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var err := img.save_png(_shot_path)
			print("PROLOGUE SHOT phase=%s size=%s err=%d → %s" % [phase, str(img.get_size()), err, _shot_path])
		get_tree().quit()
