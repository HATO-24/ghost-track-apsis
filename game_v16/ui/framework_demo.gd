extends Control

## V2 UI 框架演示屏（V2-2）。
##
## 四区沿用 V1.5 的阅读顺序，但全部由数据驱动：
##   左 · 接触列表（ListView，虚拟滚动 / 选中 / 右键 / 空态）
##   中 · 战术区占位（不渲染雷达/TWS/光学；V2-3 的接入点）
##   右 · section 面板（registry 按 kind/capabilities/航迹/证据生成，可滚动）
##   下 · 事件/命令列表 + 动作按钮菜单 + 框架自检
##
## 数据来自 `ui/data_source.gd`（core view-model；core 未就绪时 content / local demo 兜底）。
## 交互：左键选中、右键动作菜单、↑↓ 选择、TAB 推进阶段（UI 演示）、L 事件/命令、P 布局自检。
##
## 截图钩子：`DSH_V2_SHOT`（路径）+ `DSH_V2_VIEW`（default/target/menu/scroll/layout/empty），
## `DSH_V2_DENSITY`（追加 synthetic 接触数）、`DSH_V2_LAYOUT=1`、`DSH_V2_FALLBACK=1`。
## headless：跑 `_check()` 后退出（0=通过）。

const Palette := preload("res://scripts/pal.gd")
const T := preload("res://ui/theme.gd")
const L := preload("res://ui/layout.gd")
const DataSource := preload("res://ui/data_source.gd")
const ListView := preload("res://ui/widgets/list_view.gd")
const SectionPanel := preload("res://ui/widgets/section_panel.gd")
const ActionMenu := preload("res://ui/widgets/action_menu.gd")

const VIEWS := ["default", "target", "menu", "scroll", "layout", "empty", "fallback"]
const BUILD_TAG := "V2 UI FRAMEWORK · V2-2"

var data = null

var _contacts = null
var _sections = null
var _events = null
var _orders = null
var _actions_inline = null
var _menu = null
var _overlay = null

var _tab := "events"
var _ui_events: Array = []
var _ui_event_seq := 0
var _shot_path := ""
var _shot_view := ""
var _density := 0
var _probe_visible := false
var _probe_cache: Array = []
var _self_checks := 0
var _self_fails: Array[String] = []
var _headless := false


# ══ 生命周期 ═════════════════════════════════════════════════════════════

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_shot_path = OS.get_environment("DSH_V2_SHOT")
	_shot_view = OS.get_environment("DSH_V2_VIEW")
	if _shot_view == "":
		_shot_view = "default"
	_density = int(OS.get_environment("DSH_V2_DENSITY"))
	_probe_visible = OS.get_environment("DSH_V2_LAYOUT") == "1" or _shot_view == "layout"
	if not _headless:
		_setup_window()
	data = DataSource.new()
	data.boot(OS.get_environment("DSH_V2_FALLBACK") == "1")
	if _density > 0:
		data.add_synthetic(_density)
	_build_children()
	_select(data.own_id, false)
	_log_event("SYS", "V2 UI 框架启动 · source=%s · contacts=%d" % [
		data.source_label(), data.all_contacts().size()])
	for note in data.notes:
		_log_event("DATA", note)
	_refresh_all()
	if not _headless:
		get_window().size_changed.connect(_on_window_resized)
	print("V2 UI BOOT ", data.status_line())
	_run_check()
	if _headless:
		_finish_headless()
	elif _shot_path != "":
		_capture.call_deferred()


func _finish_headless() -> void:
	var code := 0 if _self_fails.is_empty() else 1
	print("V2 UI SELFTEST checks=%d fail=%d" % [_self_checks, _self_fails.size()])
	for f in _self_fails:
		print("  FAIL ", f)
	print("V2 UI HEADLESS ", "OK" if code == 0 else "FAILED")
	get_tree().quit(code)


func _setup_window() -> void:
	var w := get_window()
	w.title = "GHOST TRACK // APSIS — V2 DYNAMIC UI"
	if _shot_path != "":
		w.borderless = true
		w.size = Vector2i(1920, 1080)
		w.position = Vector2i(0, 0)
		return
	w.size = Vector2i(1600, 900)
	var scr := DisplayServer.screen_get_size()
	if scr.x > 1600 and scr.y > 900:
		w.position = Vector2i((scr.x - 1600) / 2, (scr.y - 900) / 2)


func _on_window_resized() -> void:
	queue_redraw()


func _build_children() -> void:
	# 左栏：接触列表
	_contacts = ListView.new()
	_contacts.name = "ContactsView"
	_contacts.position = L.LEFT.position
	_contacts.size = L.LEFT.size
	_contacts.row_mode = "contact"
	_contacts.row_height = T.ROW_CONTACT
	_contacts.list_title = "接触 / CONTACTS"
	_contacts.list_kicker = "动态列表 · 虚拟滚动 / VIRTUAL LIST"
	_contacts.set_empty("（无接触 / NO CONTACTS）", "world.vm_contacts() 为空")
	_contacts.item_selected.connect(_on_contact_selected)
	_contacts.item_context.connect(_on_contact_context)
	add_child(_contacts)

	# 右栏：section registry
	_sections = SectionPanel.new()
	_sections.name = "SectionPanel"
	_sections.position = L.RIGHT.position
	_sections.size = L.RIGHT.size
	add_child(_sections)

	# 下左：事件 / 命令队列（两个列表共享同一区域，L 切换）
	_events = ListView.new()
	_events.name = "EventsView"
	_events.position = L.LOG.position
	_events.size = L.LOG.size
	_events.row_mode = "log"
	_events.row_height = T.ROW_LOG
	_events.header_h = 44.0
	_events.list_title = "事件 / EVENTS"
	_events.list_kicker = "core 事件流 + UI 事件 · 最新在上 · L 切命令队列"
	_events.set_empty("（暂无事件 / NO EVENTS）", "V2 core 事件流与 UI 交互会写入这里")
	add_child(_events)

	_orders = ListView.new()
	_orders.name = "OrdersView"
	_orders.position = L.LOG.position
	_orders.size = L.LOG.size
	_orders.row_mode = "log"
	_orders.row_height = T.ROW_LOG
	_orders.header_h = 44.0
	_orders.list_title = "命令队列 / ORDERS"
	_orders.list_kicker = "world.vm_orders() · 只读 · L 切回事件"
	_orders.set_empty("（命令队列为空 / EMPTY QUEUE）",
		"V2-1 orders：PRE_ORDER → AUTHORIZED → QUEUED → TRANSMITTED → EXECUTING → DONE")
	_orders.visible = false
	add_child(_orders)

	# 下中：动作按钮菜单（inline 形态）
	_actions_inline = ActionMenu.new()
	_actions_inline.name = "ActionBar"
	_actions_inline.mode = ActionMenu.MODE_INLINE
	_actions_inline.position = L.ACTIONS.position
	_actions_inline.size = L.ACTIONS.size
	_actions_inline.title = "动作 / ACTIONS"
	_actions_inline.action_chosen.connect(_on_action_chosen)
	add_child(_actions_inline)
	_actions_inline.visible = true

	# 顶层：右键动作菜单（popup 形态）
	_menu = ActionMenu.new()
	_menu.name = "ActionMenu"
	_menu.mode = ActionMenu.MODE_POPUP
	_menu.position = Vector2.ZERO
	_menu.size = L.DESIGN
	_menu.action_chosen.connect(_on_action_chosen)
	add_child(_menu)

	# 顶层：布局自检覆盖层（P / DSH_V2_LAYOUT）
	_overlay = Control.new()
	_overlay.name = "LayoutProbeOverlay"
	_overlay.position = Vector2.ZERO
	_overlay.size = L.DESIGN
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_overlay.draw.connect(_draw_layout_probe)
	add_child(_overlay)


# ══ 刷新（view-model → widgets）══════════════════════════════════════════

func _refresh_all() -> void:
	_refresh_contacts()
	_refresh_events()
	_refresh_orders()
	_refresh_sections()
	_refresh_actions()
	queue_redraw()


func _refresh_contacts() -> void:
	var rows: Array = []
	for raw in data.all_contacts():
		var c: Dictionary = raw
		var ev: Dictionary = data.entity(String(c.get("id", "")))
		var caps: Array = ev.get("caps", [])
		var kind := String(c.get("kind", "unknown"))
		var subtitle := "%s · %s" % [T.kind_label(kind), String(c.get("cls", ""))]
		if String(c.get("cls", "")) == "":
			subtitle = T.kind_label(kind)
		if not bool(c.get("has_entity", true)):
			subtitle = "无实体航迹 · 虚警/纯回波"
		if bool(c.get("synthetic", false)):
			subtitle += " · DEMO"
		rows.append({
			"id": String(c.get("id", "")),
			"id_label": String(c.get("batch", c.get("id", ""))),
			"title": String(c.get("name", "")),
			"subtitle": subtitle,
			"badge": T.level_name(int(c.get("level", 0))),
			"badge_color": T.identity_color(String(c.get("identity", "unknown"))),
			"accent": T.accent_for(ev),
			"identity": String(c.get("identity", "unknown")),
			"side": String(c.get("side", "unknown")),
			"caps": caps.size(),
			"synthetic": bool(c.get("synthetic", false)),
		})
	_contacts.set_items(rows)
	_contacts.set_selected(data.selected_id)


func _refresh_events() -> void:
	var rows: Array = []
	for ev in _ui_events:
		var e: Dictionary = ev
		rows.append({
			"id": "ui-%d" % int(e.get("seq", 0)),
			"kind": String(e.get("kind", "UI")),
			"text": String(e.get("text", "")),
			"time": "UI",
			"accent": _kind_color(String(e.get("kind", "UI"))),
			"fresh": rows.is_empty(),
		})
	var core_events: Array = data.recent_events(32)
	for i in range(core_events.size() - 1, -1, -1):
		var raw: Dictionary = core_events[i]
		var k := String(raw.get("kind", "EVENT"))
		rows.append({
			"id": "core-%d" % i,
			"kind": k.to_upper(),
			"text": String(raw.get("text", "")),
			"time": "T+" + T.hms(float(raw.get("t", 0.0))),
			"accent": _kind_color(k),
			"fresh": rows.is_empty(),
		})
	_events.set_items(rows)


func _refresh_orders() -> void:
	var rows: Array = []
	var orders: Array = data.orders()
	for raw in orders:
		var o: Dictionary = raw
		var state := String(o.get("state", ""))
		var action_id := String(o.get("action", o.get("action_id", "")))
		var target := String(o.get("target", o.get("target_id", "")))
		var text := action_id
		if target != "":
			text += " → " + target
		var note := String(o.get("note", o.get("reason", "")))
		if note != "":
			text += "（" + note + "）"
		rows.append({
			"id": String(o.get("id", "")),
			"kind": state,
			"text": text,
			"time": "T+" + T.hms(float(o.get("issued_t", 0.0))),
			"accent": _order_color(state),
		})
	_orders.set_items(rows)


func _refresh_sections() -> void:
	var vm: Dictionary = data.entity(data.selected_id)
	var acts: Array = data.actions_for(data.selected_id)
	var ctx: Dictionary = {
		"own_id": data.own_id,
		"own_entity_id": data.own_entity_id,
		"state": data.state(),
		"evidence": data.evidence(),
	}
	if OS.get_environment("DSH_V2_DEBUG") == "1":
		print("V2 UI SECTIONS sel=", data.selected_id, " vm.id=", vm.get("id"),
			" kind=", vm.get("kind"), " batch=", vm.get("batch"),
			" contact=", str((vm.get("contact", {}) as Dictionary).get("id", "")))
	_sections.set_entity(vm, acts, ctx)
	if OS.get_environment("DSH_V2_DEBUG") == "1":
		var ov: Dictionary = _sections.find_section("overview")
		print("V2 UI SECT-OVERVIEW ", str(ov.get("rows", [])))


func _refresh_actions() -> void:
	var vm: Dictionary = data.entity(data.selected_id)
	var acts: Array = data.actions_for(data.selected_id)
	_actions_inline.set_actions(acts, vm)
	if _menu.is_open():
		_menu.set_actions(acts, vm)


func _refresh_log_tab() -> void:
	_events.visible = _tab == "events"
	_orders.visible = _tab == "orders"


# ══ 选择 / 交互 ══════════════════════════════════════════════════════════

func _select(id: String, log_it := true) -> void:
	if not data.select(id):
		return
	if _menu.is_open():
		_menu.close()
	var c: Dictionary = data.contact(data.selected_id)
	if log_it:
		_log_event("SELECT", "选中 [%s] %s · %s · L%d" % [
			String(c.get("batch", c.get("id", ""))),
			String(c.get("name", "")),
			T.identity_label(String(c.get("identity", "unknown"))),
			int(c.get("level", 0)),
		])
	_refresh_contacts()
	_refresh_sections()
	_refresh_actions()
	queue_redraw()


func _on_contact_selected(id: String) -> void:
	if id == data.selected_id:
		return
	_select(id)


func _on_contact_context(id: String, at: Vector2) -> void:
	if id != data.selected_id:
		_select(id)
	_open_action_menu(at)


func _open_action_menu(at: Vector2) -> void:
	var vm: Dictionary = data.entity(data.selected_id)
	var acts: Array = data.actions_for(data.selected_id)
	_menu.open(acts, vm, at)
	queue_redraw()


func _on_action_chosen(action_id: String, target_id: String) -> void:
	var action: Dictionary = {}
	for raw in data.actions_for(data.selected_id):
		var a: Dictionary = raw
		if String(a.get("id", "")) == action_id:
			action = a
			break
	var label := String(action.get("label", action_id))
	var target_name := String(data.contact(target_id).get("name", target_id))
	_log_event("ACTION", "选择动作「%s」→ %s（UI 演示；V2-1 未提供执行 API，不伪造结果）" % [label, target_name])
	print("V2 UI ACTION ", action_id, " target=", target_id, " available=", action.get("available"))
	queue_redraw()


func _advance_phase() -> void:
	var p: String = data.advance_phase()
	var res: Dictionary = data.last_phase_result()
	if not res.is_empty() and not bool(res.get("ok", false)):
		_log_event("PHASE", "阶段推进被拒绝 → %s（%s）" % [p, String(res.get("reason", ""))])
	else:
		_log_event("PHASE", "任务阶段 → %s · %s" % [p, data.phase_title])
	print("V2 UI PHASE ", p, " title=", data.phase_title, " result=", str(res))
	_refresh_sections()
	queue_redraw()


func _log_event(kind: String, text: String) -> void:
	_ui_events.push_front({"kind": kind, "text": text, "t": data.time, "seq": _ui_event_seq})
	_ui_event_seq += 1
	while _ui_events.size() > 80:
		_ui_events.pop_back()
	_refresh_events()


func _show_tab(tab: String) -> void:
	_tab = tab
	_refresh_log_tab()
	queue_redraw()


# ══ 截图钩子 / 视图 ══════════════════════════════════════════════════════

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_shot_view()
	await get_tree().process_frame
	await get_tree().process_frame
	var w := get_window()
	w.borderless = true
	w.size = Vector2i(1920, 1080)
	w.position = Vector2i(0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("V2 UI SHOT view=%s size=%s err=%s → %s" % [_shot_view, str(img.get_size()), str(err), _shot_path])
	get_tree().quit(0 if err == OK else 1)


func _apply_shot_view() -> void:
	match _shot_view:
		"target":
			_select(_first_target_id(), false)
			_sections.scroll_to(_sections.max_offset() * 0.55)
		"menu":
			_select(_first_target_id(), false)
			var vm: Dictionary = data.entity(data.selected_id)
			var acts: Array = data.actions_for(data.selected_id)
			_menu.open(acts, vm, Vector2(L.MAP.position.x + 560.0, 430.0))
			var disabled: Dictionary = _menu.first_disabled_action()
			if not disabled.is_empty():
				_menu.debug_focus(String(disabled.get("id", "")))
			_log_event("ACTION", "右键目标菜单：%d 项动作，%d 项不可用（灰显 + 原因）" % [
				acts.size(), acts.size() - _count_available(acts)])
		"scroll":
			var need: int = maxi(0, 20 - int(data.synthetic_count()))
			if need > 0:
				data.add_synthetic(need)
				_log_event("DATA", "追加 %d 个 synthetic 演示实体（仅演示/压测，非剧情数据）" % need)
			_select(data.own_id, false)
			_refresh_all()
			_contacts.scroll_to(_contacts.row_height * 6.0)
			_sections.scroll_to(_sections.max_offset() * 0.7)
		"layout":
			_probe_visible = true
			_overlay.visible = true
			_build_layout_probe()
		"empty":
			_show_tab("orders")
		"fallback":
			_select(_first_target_id(), false)
		_:
			pass
	_refresh_log_tab()
	queue_redraw()


func _first_target_id() -> String:
	var fallback := ""
	for raw in data.all_contacts():
		var c: Dictionary = raw
		if bool(c.get("is_own", false)):
			continue
		if String(c.get("entity_id", "")) == "":
			continue
		var side := String(c.get("side", "unknown"))
		if side == "hostile" or side == "unknown" or side == "neutral":
			return String(c.get("id", ""))
		if fallback == "":
			fallback = String(c.get("id", ""))
	if fallback != "":
		return fallback
	return data.selected_id


# ══ 键盘 / 鼠标 ══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			if _menu.is_open():
				_menu.close()
				accept_event()
			elif _probe_visible:
				_probe_visible = false
				_overlay.visible = false
				accept_event()
			else:
				get_tree().quit()
		KEY_Q:
			if not _menu.is_open():
				get_tree().quit()
		KEY_F10:
			if not _headless:
				var w := get_window()
				w.borderless = not w.borderless
				queue_redraw()
		KEY_F11:
			if not _headless:
				var w2 := get_window()
				w2.mode = Window.MODE_WINDOWED if w2.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_EXCLUSIVE_FULLSCREEN
				queue_redraw()
		KEY_TAB:
			_advance_phase()
			accept_event()
		KEY_L:
			if not _menu.is_open():
				_show_tab("orders" if _tab == "events" else "events")
				accept_event()
		KEY_P:
			if not _menu.is_open():
				_probe_visible = not _probe_visible
				_overlay.visible = _probe_visible
				if _probe_visible:
					_build_layout_probe()
				queue_redraw()
				accept_event()
		KEY_UP, KEY_DOWN:
			if not _menu.is_open():
				_step_selection(-1 if key.keycode == KEY_UP else 1)
				accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if not _menu.is_open():
				_open_action_menu(Vector2(L.MAP.position.x + L.MAP.size.x * 0.5, L.MAP.position.y + 320.0))
				accept_event()


func _step_selection(dir: int) -> void:
	var all: Array = data.all_contacts()
	if all.is_empty():
		return
	var ids: Array = []
	for raw in all:
		ids.append(String((raw as Dictionary).get("id", "")))
	var idx := ids.find(data.selected_id)
	if idx < 0:
		idx = 0
	else:
		idx = clampi(idx + dir, 0, ids.size() - 1)
	_select(String(ids[idx]))
	_contacts.scroll_to_item(data.selected_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _menu.is_open():
			_open_action_menu(mb.position)
			accept_event()


# ══ 绘制：机箱 / 顶栏 ════════════════════════════════════════════════════

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, L.DESIGN), T.BG)
	_draw_bezel()
	_draw_top_bar()
	_draw_map_placeholder()
	_draw_probe_panel()
	_draw_footer()


func _draw_bezel() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 40.0), T.BEZEL)
	draw_rect(Rect2(0.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(1880.0, 0.0, 40.0, 1080.0), T.BEZEL)
	draw_rect(Rect2(0.0, 1040.0, 1920.0, 40.0), T.BEZEL)
	draw_line(Vector2(0.0, 1.0), Vector2(1920.0, 1.0), T.a(T.TXT, 0.035), 1.0)
	draw_line(Vector2(1.0, 0.0), Vector2(1.0, 1080.0), T.a(T.TXT, 0.025), 1.0)
	draw_line(Vector2(0.0, 1078.0), Vector2(1920.0, 1078.0), Color(0.0, 0.0, 0.0, 0.55), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for i in range(180):
		var edge := rng.randi_range(0, 3)
		var x := 0.0
		var y := 0.0
		match edge:
			0:
				x = rng.randf_range(0.0, 1920.0)
				y = rng.randf_range(2.0, 38.0)
			1:
				x = rng.randf_range(2.0, 38.0)
				y = rng.randf_range(0.0, 1080.0)
			2:
				x = rng.randf_range(1882.0, 1918.0)
				y = rng.randf_range(0.0, 1080.0)
			_:
				x = rng.randf_range(0.0, 1920.0)
				y = rng.randf_range(1042.0, 1078.0)
		draw_rect(Rect2(x, y, 1.0, 1.0), T.a(T.TXT, rng.randf_range(0.01, 0.03)))
	_screw(Vector2(20.0, 20.0))
	_screw(Vector2(1900.0, 20.0))
	_screw(Vector2(20.0, 1060.0))
	_screw(Vector2(1900.0, 1060.0))
	T.text(self, 56.0, 10.0, "CS-9", T.F9, T.a(T.PH_DIM, 0.85), false)
	T.text(self, 56.0, 22.0, "战术显控台", T.F7, T.a(T.FAINT, 0.9))
	T.text_r(self, 1864.0, 1052.0, "TACTICAL DISPLAY UNIT · V2 UI FRAMEWORK · SER. 0447", T.F7, T.a(T.FAINT, 0.8), false)
	for i in range(3):
		var c := T.PH
		if i == 1:
			c = T.AMBER
		elif i == 2:
			c = T.RED
		var lp := Vector2(1802.0 + float(i) * 16.0, 20.0)
		draw_circle(lp, 2.6, T.a(c, 0.9))
		draw_circle(lp, 6.0, T.a(c, 0.08))


func _screw(p: Vector2) -> void:
	draw_circle(p, 5.5, Color("#050606"))
	draw_arc(p, 5.5, 0.0, TAU, 24, Color("#232A27"), 1.0, true)
	draw_line(p + Vector2(-3.0, -1.0), p + Vector2(3.0, 1.0), Color("#1A201D"), 1.0)


func _draw_top_bar() -> void:
	draw_rect(L.TOP, T.a(T.BG, 0.55))
	draw_line(Vector2(40.0, 112.0), Vector2(1880.0, 112.0), T.a(T.LINE, 0.95), 1.0)
	T.text(self, 60.0, 42.0, "GHOST TRACK // APSIS", T.F26, T.PH)
	T.text(self, 60.0, 74.0, "FRAMEWORK V2 · DYNAMIC DATA UI", T.F8, T.DIM, false)
	T.vline(self, 500.0, 44.0, 104.0, T.a(T.LINE, 0.7))

	var st: Dictionary = data.state()
	T.text(self, 520.0, 46.0, "场景 / SCENARIO", T.F7, T.FAINT)
	var title := String(data.title)
	if title == "":
		title = "（未加载场景 / NO SCENARIO）"
	T.text_fit(self, 520.0, 58.0, title, T.F11, T.TXT, 560.0)
	T.text(self, 520.0, 80.0, "DATUM %s · T+%s · PHASE %s%s · MODE %s" % [
		data.datum, T.hms(float(st.get("t", 0.0))), data.phase,
		(" · " + data.phase_title) if data.phase_title != "" else "", data.mode], T.F8, T.DIM, false)

	# 右侧框架计数 chip
	var xr := 1864.0
	xr = _chip_right(xr, 48.0, "SRC " + data.source_label(),
		T.PH if data.mode == "core" else T.AMBER, data.mode == "core")
	var ent: int = data.all_contacts().size()
	xr = _chip_right(xr, 48.0, "CON %02d" % ent, T.PH_DIM, true)
	xr = _chip_right(xr, 48.0, "SECT %02d" % _sections.section_count(), T.PH_DIM, true)
	var avail := _count_available(data.actions_for(data.selected_id))
	var total: int = data.actions_for(data.selected_id).size()
	xr = _chip_right(xr, 48.0, "ACT %d/%d" % [avail, total], T.PH_DIM, true)
	var metrics: Dictionary = _current_metrics()
	xr = _chip_right(xr, 48.0, "SCALE %.0f%%" % (float(metrics.get("scale", 1.0)) * 100.0), T.PH_DIM, true)
	T.text_r(self, 1864.0, 78.0, "1920×1080 DESIGN · LETTERBOX KEEP · %s" % BUILD_TAG, T.F7,
		T.a(T.FAINT, 0.85), false)
	T.text(self, 520.0, 96.0, "VIEW %s · %s" % [_shot_view.to_upper(), _probe_visible_state()], T.F7,
		T.a(T.FAINT, 0.8), false)


func _probe_visible_state() -> String:
	return "LAYOUT PROBE ON" if _probe_visible else "P 布局自检"


func _chip_right(xr: float, y: float, label: String, col: Color, active: bool) -> float:
	var w := T.text_w(label, T.F7, false) + 14.0
	var x := xr - w
	T.chip(self, Rect2(x, y, w, 18.0), label, col, active, T.F7)
	return x - 6.0


# ══ 绘制：战术区占位 ═════════════════════════════════════════════════════

func _draw_map_placeholder() -> void:
	var r := L.MAP
	T.panel(self, r, 0.84, 0.85)
	var inner := r.grow(-12.0)
	T.corners(self, inner, 20.0, T.PH_DIM, 0.55)
	T.text(self, r.position.x + 24.0, r.position.y + 20.0, "战术区 / TACTICAL FIELD", T.F11, T.TXT)
	T.text(self, r.position.x + 24.0, r.position.y + 38.0,
		"占位 / PLACEHOLDER · V2-3 雷达 / TWS / 光学 图层接入点 · 本屏不渲染战术符号", T.F8, T.FAINT)
	T.text_r(self, r.end.x - 24.0, r.position.y + 20.0, "MAP %d×%d" % [int(r.size.x), int(r.size.y)], T.F7,
		T.a(T.FAINT, 0.85), false)

	# 网格 + 基准线（不是雷达图；仅表达“这里是地图空间”）
	for gx in range(int(inner.position.x) + 64, int(inner.end.x), 64):
		draw_line(Vector2(gx, inner.position.y), Vector2(gx, inner.end.y), T.a(T.GRID, 0.10), 1.0)
	for gy in range(int(inner.position.y) + 64, int(inner.end.y), 64):
		draw_line(Vector2(inner.position.x, gy), Vector2(inner.end.x, gy), T.a(T.GRID, 0.10), 1.0)
	var cx := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.5
	draw_line(Vector2(cx - 14.0, cy), Vector2(cx + 14.0, cy), T.a(T.PH_DIM, 0.5), 1.0)
	draw_line(Vector2(cx, cy - 14.0), Vector2(cx, cy + 14.0), T.a(T.PH_DIM, 0.5), 1.0)
	# 基准线 + 刻度（DATUM 占位，与雷达无关）
	var datum_y := r.position.y + r.size.y - 150.0
	draw_line(Vector2(inner.position.x + 32.0, datum_y), Vector2(inner.end.x - 32.0, datum_y), T.a(T.PH_FAINT, 0.55), 1.0)
	for i in range(11):
		var tx := inner.position.x + 32.0 + float(i) * ((inner.size.x - 64.0) / 10.0)
		var th := 6.0 if i % 5 == 0 else 3.0
		draw_line(Vector2(tx, datum_y), Vector2(tx, datum_y - th), T.a(T.PH_FAINT, 0.5), 1.0)
	T.text(self, inner.position.x + 36.0, datum_y + 6.0, "DATUM / 局部水平面 · 占位", T.F7, T.a(T.FAINT, 0.85))

	# 中央说明
	T.text_c(self, cx, cy - 64.0, "UI 框架演示屏 / FRAMEWORK DEMO", T.F18, T.a(T.PH, 0.9))
	T.text_c(self, cx, cy - 38.0, "list · scroll · section · action menu", T.F10, T.DIM)
	T.text_c(self, cx, cy - 12.0, "左栏接触 / 事件列表由 view-model 动态生成；右栏 section 按 kind/capabilities 生成。", T.F9, T.FAINT)
	T.text_c(self, cx, cy + 8.0, "本区不绘制任何战术符号，避免伪造 V2-3 雷达 / TWS / 光学态势。", T.F9, T.FAINT)

	# 选中实体摘要
	var vm: Dictionary = data.entity(data.selected_id)
	if not vm.is_empty():
		var c: Dictionary = vm.get("contact", {})
		var accent: Color = T.accent_for(vm)
		var box := Rect2(r.position.x + 24.0, r.end.y - 132.0, 560.0, 112.0)
		draw_rect(box, T.a(T.PANEL2, 0.88))
		draw_rect(box, T.a(accent, 0.45), false, 1.0)
		T.text(self, box.position.x + 14.0, box.position.y + 10.0, "选中 / SELECTED", T.F7, T.a(accent, 0.95))
		T.text_fit(self, box.position.x + 14.0, box.position.y + 26.0,
			String(vm.get("name", "")), T.F18, accent, 300.0)
		T.text(self, box.position.x + 14.0, box.position.y + 54.0,
			"[%s] %s · %s · %s" % [
				String(c.get("batch", vm.get("id", ""))),
				String(vm.get("name_en", vm.get("id", ""))),
				T.kind_label(String(vm.get("kind", ""))),
				T.side_label(String(c.get("side", "unknown"))),
			], T.F8, T.DIM, false)
		T.text(self, box.position.x + 14.0, box.position.y + 72.0,
			"L%d · %s · 威胁 %s" % [
				int(vm.get("level", 0)),
				T.identity_label(String(vm.get("identity", "unknown"))),
				_threat_text(String(c.get("threat", ""))),
			], T.F8, T.TXT)
		T.text(self, box.position.x + 14.0, box.position.y + 90.0,
			"r = %s km · v = %s km/s" % [T.vec3(vm.get("orbit", {}).get("r")), T.vec3(vm.get("orbit", {}).get("v"))],
			T.F8, T.a(T.DIM, 0.95), false)
		T.text_r(self, box.end.x - 14.0, box.position.y + 90.0,
			"SECT %d · ACT %d/%d" % [
				_sections.section_count(),
				_count_available(data.actions_for(data.selected_id)),
				data.actions_for(data.selected_id).size(),
			], T.F7, T.a(T.FAINT, 0.9), false)
	# 右键提示
	var hint := Rect2(r.end.x - 320.0, r.end.y - 40.0, 296.0, 22.0)
	draw_line(Vector2(hint.position.x, hint.position.y), Vector2(hint.end.x, hint.position.y), T.a(T.LINE, 0.6), 1.0)
	T.text_r(self, hint.end.x - 4.0, hint.position.y + 6.0,
		"右键目标 → 动作菜单 / CONTEXT MENU", T.F8, T.a(T.PH_DIM, 0.9))


# ══ 绘制：下右框架自检 / 底栏 ════════════════════════════════════════════

func _draw_probe_panel() -> void:
	var r := L.PROBE
	T.panel(self, r, 0.965, 0.85)
	T.text(self, r.position.x + 12.0, r.position.y + 8.0, "框架自检 / FRAMEWORK PROBE", T.F9, T.TXT)
	var ok_col: Color = T.PH if _self_fails.is_empty() else T.RED
	T.chip(self, Rect2(r.end.x - 108.0, r.position.y + 8.0, 96.0, 16.0),
		"HEADLESS OK" if _self_fails.is_empty() else "HEADLESS FAIL", ok_col, true, T.F7)

	var metrics: Dictionary = _current_metrics()
	var st: Dictionary = data.state()
	var rows_left: Array = [
		["SRC", "%s%s" % [data.source_label(), (" +%d DEMO" % data.synthetic_count()) if data.synthetic_count() > 0 else ""]],
		["CONTACTS", "%d · 列表可视 %d" % [data.all_contacts().size(), _contacts.visible_rows()]],
		["LIST", "内容 %dpx / 视口 %dpx · %d%%" % [
			int(_contacts.content_height), int(_contacts.view_height()), int(round(_contacts.scroll_ratio() * 100.0))]],
		["SECTIONS", "%d · 内容 %dpx / 视口 %dpx" % [
			_sections.section_count(), int(_sections.content_height), int(_sections.view_height())]],
		["ACTIONS", "%d/%d 可用 · inline %d 行" % [
			_count_available(data.actions_for(data.selected_id)),
			data.actions_for(data.selected_id).size(), _actions_inline.inline_row_count()]],
	]
	var rows_right: Array = [
		["PHASE", "%s · %s" % [data.phase, data.phase_title if data.phase_title != "" else "—"]],
		["EVENTS", "%d 条（core + UI）" % _events.items.size()],
		["ORDERS", "%d 条" % _orders.items.size()],
		["LAYOUT", "1920×1080 @ %.3f · WIN %s" % [
			float(metrics.get("scale", 1.0)), str(metrics.get("window", Vector2i(1920, 1080)))]],
		["LETTERBOX", "bar L%.0f T%.0f R%.0f B%.0f" % [
			float(metrics.get("bars", {}).get("left", 0.0)),
			float(metrics.get("bars", {}).get("top", 0.0)),
			float(metrics.get("bars", {}).get("right", 0.0)),
			float(metrics.get("bars", {}).get("bottom", 0.0))]],
	]
	var y0 := r.position.y + 34.0
	for i in range(rows_left.size()):
		var row: Array = rows_left[i]
		var y := y0 + float(i) * 19.0
		T.text(self, r.position.x + 12.0, y, String(row[0]), T.F7, T.FAINT, false)
		T.text_fit(self, r.position.x + 84.0, y - 1.0, String(row[1]), T.F8, T.a(T.TXT, 0.95), 176.0, false)
	for i in range(rows_right.size()):
		var row2: Array = rows_right[i]
		var y2 := y0 + float(i) * 19.0
		T.text(self, r.position.x + 276.0, y2, String(row2[0]), T.F7, T.FAINT, false)
		T.text_fit(self, r.position.x + 348.0, y2 - 1.0, String(row2[1]), T.F8, T.a(T.TXT, 0.95), 168.0, false)
	T.text(self, r.position.x + 12.0, r.end.y - 16.0,
		"按 P 打开布局自检 / 输入映射证据", T.F7, T.a(T.FAINT, 0.85))


func _draw_footer() -> void:
	T.text(self, 60.0, 1002.0,
		"↑↓ 选择 · 右键动作菜单 · L 事件/命令 · TAB 任务阶段 · P 布局自检 · F10 边框 · F11 全屏 · Q 退出",
		T.F8, T.FAINT)
	var metrics: Dictionary = _current_metrics()
	T.text_r(self, 1864.0, 1002.0,
		"%s · DESIGN 1920×1080 · SCALE %.3f · %s" % [BUILD_TAG, float(metrics.get("scale", 1.0)), data.source_label()],
		T.F8, T.a(T.FAINT, 0.9), false)


# ══ 布局自检覆盖层 ═══════════════════════════════════════════════════════

func _build_layout_probe() -> void:
	_probe_cache = L.probe_all()


func _draw_layout_probe() -> void:
	if _overlay == null:
		return
	var ci: Control = _overlay
	if _probe_cache.is_empty():
		_build_layout_probe()
	ci.draw_rect(Rect2(Vector2.ZERO, L.DESIGN), Color(0.01, 0.03, 0.024, 0.82))
	var panel := Rect2(200.0, 120.0, 1520.0, 840.0)
	ci.draw_rect(panel, T.a(T.PANEL, 0.985))
	ci.draw_rect(panel, T.a(T.PH, 0.8), false, 1.0)
	T.corners(ci, panel.grow(-1.0), 16.0, T.PH, 0.9)
	T.text(ci, panel.position.x + 24.0, panel.position.y + 20.0, "布局自检 / LAYOUT PROBE", T.F18, T.PH)
	T.text(ci, panel.position.x + 24.0, panel.position.y + 48.0,
		"设计基线 1920×1080；引擎 stretch = canvas_items / keep；下表用同一 letterbox 公式把设计点映射成窗口像素再映射回来。",
		T.F9, T.DIM)
	T.text(ci, panel.position.x + 24.0, panel.position.y + 64.0,
		"鼠标点击在窗口缩放/超宽/竖屏下都按此映射换算到设计坐标（黑边不接收点击）—— 每行 max_err 应 < 0.001px。",
		T.F9, T.FAINT)
	var y := panel.position.y + 92.0
	var cols := [24.0, 176.0, 300.0, 470.0, 640.0, 810.0, 1080.0, 1280.0]
	var heads := ["WINDOW", "SCALE", "LETTERBOX RECT", "PROBE (960,540)", "BACK", "ERR", "BARS", "OK"]
	for i in range(heads.size()):
		T.text(ci, panel.position.x + cols[i], y, String(heads[i]), T.F7, T.FAINT, false)
	ci.draw_line(Vector2(panel.position.x + 24.0, y + 16.0), Vector2(panel.end.x - 24.0, y + 16.0),
		T.a(T.LINE, 0.8), 1.0)
	y += 24.0
	for raw in _probe_cache:
		var pr: Dictionary = raw
		var lb: Rect2 = pr.get("letterbox", Rect2())
		var rows: Array = pr.get("rows", [])
		var mid: Dictionary = {}
		for rrow in rows:
			var rd: Dictionary = rrow
			if (rd.get("design", Vector2.ZERO) as Vector2).distance_to(Vector2(960.0, 540.0)) < 1.0:
				mid = rd
		var win: Vector2i = pr.get("window", L.DESIGN_I)
		var wp: Vector2 = mid.get("window", Vector2.ZERO)
		var bp: Vector2 = mid.get("back", Vector2.ZERO)
		var vals := [
			"%d×%d" % [win.x, win.y],
			"%.4f" % float(pr.get("scale", 1.0)),
			"(%.1f, %.1f, %.1f, %.1f)" % [lb.position.x, lb.position.y, lb.size.x, lb.size.y],
			"(%.2f, %.2f)" % [wp.x, wp.y],
			"(%.2f, %.2f)" % [bp.x, bp.y],
			"%.6f" % float(mid.get("err", 0.0)),
			"L%.0f T%.0f R%.0f B%.0f" % [
				float((pr.get("bars", {}) as Dictionary).get("left", 0.0)),
				float((pr.get("bars", {}) as Dictionary).get("top", 0.0)),
				float((pr.get("bars", {}) as Dictionary).get("right", 0.0)),
				float((pr.get("bars", {}) as Dictionary).get("bottom", 0.0))],
			"OK" if bool(pr.get("ok", false)) else "FAIL",
		]
		var row_ok := bool(pr.get("ok", false))
		var col: Color = T.a(T.TXT, 0.95) if row_ok else T.RED
		for i in range(vals.size()):
			var cc: Color = col
			if i == 7:
				cc = T.PH if row_ok else T.RED
			T.text(ci, panel.position.x + cols[i], y, String(vals[i]), T.F8, cc, i <= 1)
		ci.draw_line(Vector2(panel.position.x + 24.0, y + 16.0), Vector2(panel.end.x - 24.0, y + 16.0),
			T.a(T.LINE, 0.25), 1.0)
		y += 22.0
	# 当前窗口实测
	var metrics: Dictionary = _current_metrics()
	var cur := Rect2(panel.position.x + 24.0, panel.end.y - 120.0, panel.size.x - 48.0, 96.0)
	ci.draw_rect(cur, T.a(T.PANEL2, 0.9))
	ci.draw_rect(cur, T.a(T.LINE, 0.8), false, 1.0)
	var lb2: Rect2 = metrics.get("letterbox", Rect2())
	T.text(ci, cur.position.x + 14.0, cur.position.y + 10.0,
		"当前窗口 / CURRENT · viewport %s · window %s · scale %.4f" % [
			str(metrics.get("viewport")), str(metrics.get("window")), float(metrics.get("scale", 1.0))],
		T.F9, T.TXT)
	T.text(ci, cur.position.x + 14.0, cur.position.y + 32.0,
		"letterbox rect = (%.1f, %.1f, %.1f, %.1f) → 16:9 居中；黑边坐标不会被当作设计坐标。"
		% [lb2.position.x, lb2.position.y, lb2.size.x, lb2.size.y],
		T.F8, T.DIM)
	T.text(ci, cur.position.x + 14.0, cur.position.y + 52.0,
		"复跑：& $godot --headless --path game_v16 --script res://ui/ui_probe.gd   （layout self_check：8 组窗口尺寸，max_err < 0.001）",
		T.F8, T.FAINT, false)
	T.text(ci, cur.position.x + 14.0, cur.position.y + 72.0,
		"截图钩子：DSH_V2_SHOT / DSH_V2_VIEW=layout；关闭：P 或 ESC。",
		T.F8, T.a(T.FAINT, 0.9))
	T.text_r(ci, panel.end.x - 24.0, panel.position.y + 20.0, "ESC / P 关闭", T.F8, T.a(T.FAINT, 0.9))


# ══ 工具 ═════════════════════════════════════════════════════════════════

func _current_metrics() -> Dictionary:
	var vp := Vector2(L.DESIGN)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	var win := Vector2i(1920, 1080)
	if not _headless:
		win = get_window().size
	return L.current_metrics(vp, win)


func _count_available(acts: Array) -> int:
	var n := 0
	for raw in acts:
		if bool((raw as Dictionary).get("available", false)):
			n += 1
	return n


func _kind_color(kind: String) -> Color:
	match kind.to_lower():
		"load", "order", "data":
			return T.BLUE
		"track", "select", "phase":
			return T.AMBER
		"evidence", "action":
			return T.PH
		"error", "warning", "warn":
			return T.RED
		_:
			return T.DIM


func _threat_text(threat: String) -> String:
	match threat:
		"":
			return "—"
		"none":
			return "无威胁"
		"low":
			return "低"
		"med", "medium":
			return "中"
		"high":
			return "高"
		"hostile":
			return "确认敌对"
		_:
			return threat


func _order_color(state: String) -> Color:
	match state:
		"PRE_ORDER", "AUTHORIZED":
			return T.BLUE
		"QUEUED", "TRANSMITTED":
			return T.AMBER
		"EXECUTING":
			return T.PH_DIM
		"REJECTED", "ABORTED":
			return T.RED
		_:
			return T.FAINT


# ══ 自检（headless + GUI 启动都跑）═══════════════════════════════════════

func _run_check() -> void:
	_self_checks = 0
	_self_fails.clear()
	# 1) 布局
	var lc := L.self_check()
	_check(bool(lc["ok"]), "layout letterbox self_check")
	print("V2 UI SELFCHECK layout sizes=%d max_err=%.6f" % [
		(lc["probes"] as Array).size(), float(lc["max_err"])])
	# 2) 数据
	_check(data.all_contacts().size() > 0, "data contacts > 0")
	_check(not data.own().is_empty(), "data own exists")
	_check(not data.selected().is_empty(), "data selected exists")
	_check(data.actions_for(data.selected_id).size() > 0, "actions_for selected non-empty")
	_check(not data.contact(data.selected_id).is_empty(), "selected contact resolvable")
	# 3) 列表选中同步
	_check(_contacts.item_index(data.selected_id) >= 0, "contacts list selected row exists")
	_check(_contacts.items.size() == data.all_contacts().size(), "contacts list row count = data count")
	_check(_contacts.visible_rows() <= _contacts.items.size() + 1, "contacts virtualized row count sane")
	# 4) section registry
	var ids: Array = _sections.section_ids()
	_check(ids.has("overview"), "section registry overview")
	_check(ids.has("contact"), "section registry contact")
	_check(ids.has("phase"), "section registry phase")
	_check(not _sections.find_section("overview").is_empty(), "section content built")
	# 5) action menu 数据
	var acts: Array = data.actions_for(data.selected_id)
	var disabled := 0
	for raw in acts:
		var a: Dictionary = raw
		if not bool(a.get("available", true)):
			disabled += 1
			if String(a.get("reason", "")) == "":
				_check(false, "disabled action %s missing reason" % String(a.get("id", "")))
	_check(disabled >= 0 and acts.size() == _actions_inline.actions.size(), "action bar synced")
	print("V2 UI SELFCHECK sections=%s actions=%d disabled=%d" % [str(ids), acts.size(), disabled])
	# 6) 滚动模型（临时 ListView，200 行）
	var lv = ListView.new()
	lv.position = Vector2(0.0, 0.0)
	lv.size = L.LEFT.size
	lv.row_mode = "contact"
	lv.row_height = T.ROW_CONTACT
	add_child(lv)
	var rows: Array = []
	for i in range(200):
		rows.append({
			"id": "S-%03d" % i, "id_label": "%04d" % i, "title": "scroll test", "subtitle": "test",
			"badge": "L0", "badge_color": T.AMBER, "accent": T.PH, "identity": "unknown",
		})
	lv.set_items(rows)
	_check(lv.max_offset() > 0.0, "temp list 200 rows scrollable")
	_check(lv.visible_rows() < 200, "temp list virtualized")
	lv.scroll_to(1.0e9)
	_check(is_equal_approx(lv.offset, lv.max_offset()), "temp list scroll clamp")
	remove_child(lv)
	lv.queue_free()
	# 7) 菜单几何
	var menu = ActionMenu.new()
	menu.mode = ActionMenu.MODE_POPUP
	menu.size = L.DESIGN
	add_child(menu)
	menu.set_actions(acts, data.selected())
	_check(menu.available_count() == _count_available(acts), "menu available count sync")
	var mid_rect: Rect2 = menu.row_rect_for(String((acts[0] as Dictionary).get("id", "")))
	_check(mid_rect.end.x <= L.DESIGN.x and mid_rect.position.x >= 0.0, "menu geometry inside design")
	remove_child(menu)
	menu.queue_free()
	# 8) 主题令牌
	_check(T.PH != T.RED and T.F7 < T.F26, "theme tokens distinct")
	print("V2 UI SELFCHECK checks=%d fail=%d" % [_self_checks, _self_fails.size()])


func _check(cond: bool, label: String) -> void:
	_self_checks += 1
	if not cond:
		_self_fails.append(label)
		print("V2 UI SELFCHECK FAIL: ", label)
