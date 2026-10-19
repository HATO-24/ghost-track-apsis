extends SceneTree

## V2 UI 框架 headless 自检（独立于主场景）。
##
## 运行：
##   & $godot --headless --path game_v16 --script res://ui/ui_probe.gd
##
## 覆盖：布局 letterbox 往返映射、data_source 三级兜底、ListView 虚拟滚动/选中/空态、
## SectionPanel registry（按 kind/capabilities/航迹/证据动态生成、超长可滚动）、
## ActionMenu 分组/灰显原因/信号。退出码：0 = 全过；1 = 有失败。可接 CI。

const L := preload("res://ui/layout.gd")
const T := preload("res://ui/theme.gd")
const DataSource := preload("res://ui/data_source.gd")
const ListView := preload("res://ui/widgets/list_view.gd")
const SectionPanel := preload("res://ui/widgets/section_panel.gd")
const ActionMenu := preload("res://ui/widgets/action_menu.gd")

var _checks := 0
var _fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(label)
		print("  FAIL ", label)


func _run() -> void:
	var win: Window = root
	var ui := Control.new()
	ui.size = L.DESIGN
	win.add_child(ui)
	await process_frame

	# ── 1. 布局 letterbox ────────────────────────────────────────────────
	var lc := L.self_check()
	_check(bool(lc["ok"]), "layout self_check ok")
	print("UI PROBE layout sizes=%d max_err=%.6f fails=%d" % [
		(lc["probes"] as Array).size(), float(lc["max_err"]), (lc["fails"] as Array).size()])

	# ── 2. 数据源（core → content → local demo 三级兜底）───────────────
	var ds = DataSource.new()
	var booted: bool = ds.boot()
	_check(booted, "data_source boot")
	_check(ds.all_contacts().size() > 0, "data_source contacts > 0")
	_check(not ds.own().is_empty(), "data_source own exists")
	_check(not ds.selected().is_empty(), "data_source selected exists")
	print("UI PROBE data ", ds.status_line())
	for note in ds.notes:
		print("  note: ", note)

	var acts: Array = ds.actions_for(ds.selected_id)
	_check(acts.size() > 0, "actions_for returns actions")
	var norm_ok := true
	for raw in acts:
		var a: Dictionary = raw
		norm_ok = norm_ok and String(a.get("id", "")) != "" and String(a.get("label", "")) != ""
		norm_ok = norm_ok and a.get("available") is bool
		if not bool(a.get("available", true)):
			norm_ok = norm_ok and String(a.get("reason", "")) != ""
	_check(norm_ok, "actions normalized with reason")
	print("UI PROBE actions total=%d available=%d" % [acts.size(), _count_available(acts)])
	_check(ds.orders() is Array, "orders() returns array")
	_check(ds.phase_title != "", "mission phase title from core")
	var prompt: Dictionary = ds.mission_prompt()
	_check(not prompt.is_empty() and String(prompt.get("title", "")) != "", "mission.prompt() read-only view")
	print("UI PROBE mission phase=%s title=%s prompt=%s" % [
		ds.phase, ds.phase_title, T.ellipsis(String(prompt.get("title", "")), T.F9, 60.0)])
	_check(ds.recent_events(8) is Array, "recent_events() returns array")

	var ctx: Dictionary = {
		"own_id": ds.own_id,
		"state": ds.state(),
		"evidence": ds.evidence(),
	}

	# ── 3. ListView：虚拟滚动 / 选中 / 右键 / 空态 ─────────────────────
	var lv = ListView.new()
	lv.position = L.LEFT.position
	lv.size = L.LEFT.size
	lv.row_mode = "contact"
	lv.row_height = T.ROW_CONTACT
	ui.add_child(lv)
	await process_frame

	var rows: Array = []
	for i in range(200):
		rows.append({
			"id": "T-%03d" % i,
			"id_label": "%04d" % (3000 + i),
			"title": "测试接触 / TEST CONTACT %03d" % i,
			"subtitle": "ship · 测试",
			"badge": "L%d" % (i % 5),
			"badge_color": T.AMBER,
			"accent": T.PH,
			"identity": "unknown",
			"side": "unknown",
			"caps": i % 4,
		})
	lv.set_items(rows)
	await process_frame
	_check(lv.max_offset() > 0.0, "list 200 rows scrollable")
	_check(lv.visible_rows() < 200, "list virtualized (visible < total)")
	lv.scroll_to(1.0e9)
	_check(is_equal_approx(lv.offset, lv.max_offset()), "list scroll clamped to bottom")
	_check(lv.scroll_ratio() > 0.99, "list scroll ratio bottom")
	lv.scroll_to(0.0)
	var first_row_pos := Vector2(lv.body_rect().position.x + 20.0, lv.body_rect().position.y + 10.0)
	_check(lv.row_at(first_row_pos) == 0, "list row_at top = 0")
	_check(lv.row_at(Vector2(2.0, 2.0)) == -1, "list row_at outside = -1")
	lv.set_selected("T-042")
	_check(lv.item_index("T-042") == 42, "list item_index")
	_check(String(lv.selected_item().get("id", "")) == "T-042", "list selected_item")
	var got_ctx: Array = []
	lv.item_context.connect(func(eid: String, _at: Vector2): got_ctx.append(eid))
	var mm := InputEventMouseButton.new()
	mm.button_index = MOUSE_BUTTON_RIGHT
	mm.pressed = true
	mm.position = Vector2(lv.body_rect().position.x + 10.0, lv.body_rect().position.y + lv.row_height * 5.0 + 8.0)
	lv.call("_on_input", mm)
	_check(got_ctx.size() == 1 and String(got_ctx[0]) == "T-005", "list right-click emits item_context")
	lv.set_items([])
	await process_frame
	_check(lv.max_offset() < 0.5, "empty list not scrollable")
	lv.set_empty("（无数据 / EMPTY）", "空态提示")
	print("UI PROBE list content=%dpx view=%dpx visible=%d" % [
		int(lv.content_height), int(lv.view_height()), lv.visible_rows()])

	# ── 4. 真实接触列表（core view-model）可滚动 ───────────────────────
	var real_rows: Array = []
	for raw_c in ds.all_contacts():
		var c: Dictionary = raw_c
		var ev: Dictionary = ds.entity(String(c.get("id", "")))
		real_rows.append({
			"id": String(c.get("id", "")),
			"id_label": String(c.get("batch", c.get("id", ""))),
			"title": String(c.get("name", "")),
			"subtitle": "%s · %s" % [T.kind_label(String(c.get("kind", ""))), String(c.get("cls", ""))],
			"badge": T.level_name(int(c.get("level", 0))),
			"badge_color": T.identity_color(String(c.get("identity", "unknown"))),
			"accent": T.side_color(String(c.get("side", "unknown"))),
			"identity": String(c.get("identity", "unknown")),
			"side": String(c.get("side", "unknown")),
			"caps": (ev.get("caps", []) as Array).size(),
		})
	lv.set_items(real_rows)
	lv.set_selected(ds.selected_id)
	_check(lv.item_index(ds.selected_id) >= 0, "real contacts selected row exists")
	print("UI PROBE contacts=%d rows=%d" % [real_rows.size(), lv.items.size()])

	# ── 5. SectionPanel：registry / 可滚动 / 己方与对方 accent ─────────
	var sp = SectionPanel.new()
	sp.position = L.RIGHT.position
	sp.size = L.RIGHT.size
	ui.add_child(sp)
	await process_frame

	var own_vm: Dictionary = ds.own()
	var own_acts: Array = ds.actions_for(String(own_vm.get("contact", {}).get("id", ds.selected_id)))
	sp.set_entity(own_vm, own_acts, ctx)
	await process_frame
	_check(sp.section_count() > 0, "sections built for own")
	_check(sp.section_ids().has("overview"), "section registry: overview")
	_check(sp.section_ids().has("contact"), "section registry: contact")
	_check(sp.section_ids().has("capabilities") == not (own_vm.get("caps", []) as Array).is_empty(),
		"section registry: capabilities follows caps")
	_check(sp.section_ids().has("orbit"), "section registry: orbit")
	_check(sp.accent == T.PH, "own accent = PH")
	print("UI PROBE sections own=%s content=%dpx view=%dpx" % [
		str(sp.section_ids()), int(sp.content_height), int(sp.view_height())])

	# 目标：优先选一个有实体资料的敌方/未知接触
	var target_c: Dictionary = {}
	for raw_t in ds.all_contacts():
		var c2: Dictionary = raw_t
		if bool(c2.get("is_own", false)):
			continue
		if String(c2.get("entity_id", "")) == "":
			continue
		target_c = c2
		break
	_check(not target_c.is_empty(), "found non-own target contact")
	var target_vm: Dictionary = ds.entity(String(target_c.get("id", "")))
	var tgt_acts: Array = ds.actions_for(String(target_c.get("id", "")))
	sp.set_entity(target_vm, tgt_acts, ctx)
	await process_frame
	_check(sp.section_ids().has("actions"), "section registry: actions for target")
	_check(sp.accent == T.accent_for(target_vm), "target accent follows side")
	_check(sp.content_height > sp.view_height(), "target sections overflow -> scrollable")
	sp.scroll_to_bottom()
	_check(is_equal_approx(sp.offset, sp.max_offset()), "sections scroll clamp bottom")
	print("UI PROBE sections target=%s content=%dpx offset=%d/%d" % [
		str(sp.section_ids()), int(sp.content_height), int(sp.offset), int(sp.max_offset())])

	# 无实体航迹（虚警）：section 仍能生成（contact/kind，无 capabilities）
	var phantom: Dictionary = {}
	for raw_p in ds.all_contacts():
		var cp: Dictionary = raw_p
		if String(cp.get("entity_id", "")) == "":
			phantom = cp
			break
	if not phantom.is_empty():
		var ph_vm: Dictionary = ds.entity(String(phantom.get("id", "")))
		sp.set_entity(ph_vm, ds.actions_for(String(phantom.get("id", ""))), ctx)
		await process_frame
		_check(sp.section_ids().has("contact"), "phantom contact section exists")
		_check(not sp.section_ids().has("capabilities"), "phantom contact has no capabilities section")
		print("UI PROBE phantom=%s sections=%s" % [String(phantom.get("id", "")), str(sp.section_ids())])

	# registry 可按 kind 生成不同 section（用 synthetic station 验证）
	ds.add_synthetic(8)
	var station: Dictionary = {}
	for raw2 in ds.all_contacts():
		var vm2: Dictionary = raw2
		if String(vm2.get("kind", "")) == "station":
			station = vm2
			break
	_check(not station.is_empty(), "synthetic station exists for kind registry test")
	if not station.is_empty():
		sp.set_entity(ds.entity(String(station.get("id", ""))), ds.actions_for(String(station.get("id", ""))), ctx)
		await process_frame
		_check(sp.section_ids().has("kind"), "section registry: kind section")
		_check(String((sp.find_section("kind") as Dictionary).get("title", "")).contains("站点"),
			"kind section title = station")

	# ── 6. ActionMenu：分组 / 灰显原因 / 点击信号 / 面板在屏内 ─────────
	var menu = ActionMenu.new()
	menu.mode = ActionMenu.MODE_POPUP
	menu.size = L.DESIGN
	ui.add_child(menu)
	await process_frame

	menu.set_actions(tgt_acts, target_vm)
	await process_frame
	_check(menu.available_count() > 0, "menu has available actions")
	_check(menu.available_count() <= tgt_acts.size(), "menu available count sane")
	_check(menu.row_rect_for("crossfix").size.x > 0.0, "menu row geometry")
	var disabled: Dictionary = menu.first_disabled_action()
	_check(not disabled.is_empty(), "menu has disabled action")
	menu.debug_focus(String(disabled.get("id", "")))
	_check(menu.hint != "", "menu disabled hint = reason")
	var emitted: Array = []
	menu.action_chosen.connect(func(aid: String, tid: String): emitted.append([aid, tid]))
	var avail: Dictionary = {}
	for raw3 in tgt_acts:
		if bool((raw3 as Dictionary).get("available", false)):
			avail = raw3
			break
	_check(not avail.is_empty(), "menu has first available action")
	menu.open(tgt_acts, target_vm, Vector2(L.MAP.position.x + 420.0, 420.0))
	_check(menu.is_open(), "menu popup opens")
	_check(menu.debug_click(String(avail.get("id", ""))), "menu debug_click works")
	_check(emitted.size() == 1, "menu action_chosen emitted")
	_check(not menu.is_open(), "menu closes after choose")
	menu.open(tgt_acts, target_vm, Vector2(1900.0, 100.0))
	var panel_edge_ok := true
	for raw4 in tgt_acts:
		var rr: Rect2 = menu.row_rect_for(String((raw4 as Dictionary).get("id", "")))
		if rr.size.x > 0.0:
			panel_edge_ok = panel_edge_ok and rr.position.x >= 0.0 and rr.end.x <= L.DESIGN.x
	_check(panel_edge_ok, "menu panel clamped inside design")
	menu.close()
	menu.mode = ActionMenu.MODE_INLINE
	menu.size = L.ACTIONS.size
	menu.set_actions(tgt_acts, target_vm)
	_check(menu.inline_row_count() > 0, "inline menu rows > 0")
	print("UI PROBE menu actions=%d available=%d inline_rows=%d" % [
		tgt_acts.size(), _count_available(tgt_acts), menu.inline_row_count()])

	# ── 7. 汇总 ─────────────────────────────────────────────────────────
	ui.remove_child(lv)
	ui.remove_child(sp)
	ui.remove_child(menu)
	lv.queue_free()
	sp.queue_free()
	menu.queue_free()
	ui.queue_free()
	await process_frame

	print("UI PROBE done checks=%d fail=%d" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("UI PROBE OK")
		quit(0)
	else:
		print("UI PROBE FAILED")
		for f in _fails:
			print("  - ", f)
		quit(1)


func _count_available(acts: Array) -> int:
	var n := 0
	for raw in acts:
		if bool((raw as Dictionary).get("available", false)):
			n += 1
	return n
