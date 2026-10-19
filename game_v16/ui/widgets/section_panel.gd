extends "res://ui/widgets/scroll_view.gd"

## V2 右栏 section 面板（section registry）。
##
## 输入是 `ui/data_source.gd` 给的**只读实体 view-model**（Dictionary）与
## `V2Actions.actions_for()` 生成的动作数组。section 不是写死的四块：
## 用一张 registry 表按 `kind` / `capabilities` / `orbit` / `signatures` / 是否己方
## 动态生成；内容超过面板高度时可滚动，不截断。
##
## accent：己方薄荷绿（PH）/ 敌方朱红（RED）/ 中立冰蓝（BLUE）/ 未知琥珀（AMBER）。
##
## 子类可调用 `register_section()` 插入自定义 section（V2-3 业务屏扩展点）。

var vm: Dictionary = {}
var actions: Array = []
var own_id := ""
var context: Dictionary = {}
var sections: Array = []
var header_h := 136.0
var footer_h := 18.0

var _registry: Array = []
var _layout: Array = []
var _content_pad := 4.0


func _ready() -> void:
	super._ready()
	scroll_step = 40.0
	_build_registry()


func body_rect() -> Rect2:
	var bar_reserve := bar_gap + bar_width + bar_margin
	return Rect2(
		14.0,
		header_h,
		maxf(8.0, size.x - 14.0 - bar_reserve - 14.0),
		maxf(8.0, size.y - header_h - footer_h))


# ══ registry ═════════════════════════════════════════════════════════════

func _build_registry() -> void:
	_registry = [
		{"id": "overview", "when": Callable(self, "_when_overview"), "build": Callable(self, "_sec_overview")},
		{"id": "capabilities", "when": Callable(self, "_when_capabilities"), "build": Callable(self, "_sec_capabilities")},
		{"id": "contact", "when": Callable(self, "_when_contact"), "build": Callable(self, "_sec_contact")},
		{"id": "orbit", "when": Callable(self, "_when_orbit"), "build": Callable(self, "_sec_orbit")},
		{"id": "signatures", "when": Callable(self, "_when_signatures"), "build": Callable(self, "_sec_signatures")},
		{"id": "kind", "when": Callable(self, "_when_kind"), "build": Callable(self, "_sec_kind")},
		{"id": "phase", "when": Callable(self, "_when_phase"), "build": Callable(self, "_sec_phase")},
		{"id": "evidence", "when": Callable(self, "_when_evidence"), "build": Callable(self, "_sec_evidence")},
		{"id": "tags", "when": Callable(self, "_when_tags"), "build": Callable(self, "_sec_tags")},
		{"id": "actions", "when": Callable(self, "_when_actions"), "build": Callable(self, "_sec_actions")},
	]


## 业务屏扩展：追加一个 section builder；front=true 插到最前（教学/损管等优先显示）。
func register_section(entry: Dictionary, front := false) -> void:
	if not (entry.has("id") and entry.has("when") and entry.has("build")):
		return
	if front:
		_registry.push_front(entry)
	else:
		_registry.append(entry)


func set_entity(vm_in: Variant, actions_in: Array = [], context_in: Dictionary = {}) -> void:
	vm = vm_in if vm_in is Dictionary else {}
	actions = actions_in if actions_in is Array else []
	context = context_in if context_in is Dictionary else {}
	if context.has("own_id"):
		own_id = String(context.get("own_id", own_id))
	accent = T.accent_for(vm)
	sections = []
	for raw in _registry:
		var entry: Dictionary = raw
		var when: Callable = entry["when"]
		if not bool(when.call(vm)):
			continue
		var build: Callable = entry["build"]
		var sec: Variant = build.call(vm)
		if sec is Dictionary and not (sec as Dictionary).is_empty():
			sections.append(sec)
	_relayout()
	queue_redraw()


func section_ids() -> Array:
	var out: Array = []
	for raw in sections:
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func section_count() -> int:
	return sections.size()


func find_section(id: String) -> Dictionary:
	for raw in sections:
		var sec: Dictionary = raw
		if String(sec.get("id", "")) == id:
			return sec
	return {}


func scroll_to_section(id: String) -> void:
	for raw in _layout:
		var lay: Dictionary = raw
		if String((lay["sec"] as Dictionary).get("id", "")) == id:
			scroll_to(float(lay["y"]))
			return


func set_own_id(id: String) -> void:
	own_id = id
	_relayout()


# ── when 谓词 ────────────────────────────────────────────────────────────

func _when_overview(_vm: Dictionary) -> bool:
	return not vm.is_empty()


func _when_capabilities(_vm: Dictionary) -> bool:
	return not (vm.get("caps", []) as Array).is_empty()


func _when_contact(_vm: Dictionary) -> bool:
	var c: Variant = vm.get("contact", {})
	return c is Dictionary and not (c as Dictionary).is_empty()


func _when_phase(_vm: Dictionary) -> bool:
	var st: Variant = context.get("state", {})
	return st is Dictionary and not (st as Dictionary).is_empty()


func _when_evidence(_vm: Dictionary) -> bool:
	return not (context.get("evidence", []) as Array).is_empty()


func _when_orbit(_vm: Dictionary) -> bool:
	return vm.get("orbit", {}) is Dictionary and not (vm.get("orbit", {}) as Dictionary).is_empty()


func _when_signatures(_vm: Dictionary) -> bool:
	return vm.get("signatures", {}) is Dictionary and not (vm.get("signatures", {}) as Dictionary).is_empty()


func _when_kind(_vm: Dictionary) -> bool:
	return not vm.is_empty()


func _when_tags(_vm: Dictionary) -> bool:
	return not (vm.get("tags", []) as Array).is_empty()


func _when_actions(_vm: Dictionary) -> bool:
	if actions.is_empty():
		return false
	var cid := ""
	var c: Variant = vm.get("contact", {})
	if c is Dictionary:
		cid = String((c as Dictionary).get("id", ""))
	var eid := String(vm.get("id", ""))
	return cid != own_id and eid != own_id


# ── section builders ─────────────────────────────────────────────────────

func _sec_overview(_vm: Dictionary) -> Dictionary:
	var identity := String(vm.get("identity", "unknown"))
	var threat := String(vm.get("threat", ""))
	var level := int(vm.get("level", 0))
	var rows: Array = []
	if bool(vm.get("is_own", false)):
		rows.append({"label": "基准 / DATUM", "value": "是 / OWN", "color": T.PH})
	rows.append({
		"label": "身份 / IDENTITY",
		"value": T.identity_label(identity),
		"color": T.identity_color(identity),
	})
	rows.append({
		"label": "威胁 / THREAT",
		"value": _threat_label(threat) if threat != "" else "—",
		"color": T.threat_color(threat) if threat != "" else T.FAINT,
	})
	rows.append({"label": "类别 / KIND", "value": T.kind_label(String(vm.get("kind", "unknown")))})
	rows.append({"label": "批号 / BATCH", "value": String(vm.get("batch", vm.get("id", "—"))), "mono": true})
	rows.append({"label": "舰级 / CLASS", "value": _or_dash(String(vm.get("cls", "")))})
	rows.append({"label": "角色 / ROLE", "value": _or_dash(String(vm.get("role", "")))})
	rows.append({
		"label": "识别 / TRACK",
		"value": "L%d · %s" % [level, T.level_desc(level)],
	})
	return {"id": "overview", "title": "概览 / OVERVIEW", "count": "", "rows": rows}


func _sec_capabilities(_vm: Dictionary) -> Dictionary:
	var caps: Array = vm.get("caps", [])
	var groups: Dictionary = {}
	var order: Array = []
	for raw in caps:
		var cap := String(raw)
		var domain := cap.split(".")[0] if cap.contains(".") else "other"
		if not groups.has(domain):
			groups[domain] = []
			order.append(domain)
		(groups[domain] as Array).append(cap)
	var rows: Array = []
	rows.append({"label": "能力总数 / TOTAL", "value": "%d 项" % caps.size(), "mono": true})
	for domain in order:
		var items: Array = groups[domain]
		var shorts: Array = []
		for raw2 in items:
			var parts := String(raw2).split(".")
			shorts.append(parts[parts.size() - 1] if parts.size() > 1 else String(raw2))
		var domain_col: Color = T.RED if String(domain) == "weapon" else T.TXT
		rows.append({
			"label": "%s.*" % String(domain),
			"value": "%d · %s" % [items.size(), " · ".join(PackedStringArray(shorts))],
			"mono": true,
			"color": domain_col,
		})
	return {
		"id": "capabilities",
		"title": "能力 / CAPABILITIES",
		"count": "%d" % caps.size(),
		"rows": rows,
	}


func _sec_contact(_vm: Dictionary) -> Dictionary:
	var c: Dictionary = vm.get("contact", {})
	var rows: Array = []
	rows.append({"label": "航迹 / TRACK", "value": String(c.get("track_id", "—")), "mono": true})
	rows.append({"label": "批号 / BATCH", "value": String(c.get("batch", "—")), "mono": true})
	rows.append({
		"label": "识别 / LEVEL",
		"value": "%s · %s" % [T.level_name(int(c.get("level", 0))), T.level_desc(int(c.get("level", 0)))],
	})
	var range_km := float(c.get("range_km", -1.0))
	var bearing := float(c.get("bearing_deg", 0.0))
	rows.append({"label": "方位 / BEARING", "value": "%03d°" % int(bearing), "mono": true})
	rows.append({
		"label": "距离 / RANGE",
		"value": ("%s km" % T.fmt_int(int(range_km))) if range_km >= 0.0 else "未知（L1）",
		"mono": true,
	})
	rows.append({
		"label": "数据龄 / AGE",
		"value": "陈旧 %ds" % int(c.get("age_s", 0.0)) if bool(c.get("stale", false)) else "更新 %ds" % int(c.get("age_s", 0.0)),
		"color": T.AMBER if bool(c.get("stale", false)) else T.TXT,
	})
	rows.append({"label": "质量 / QUALITY", "value": "%.2f" % float(c.get("quality", 1.0)), "mono": true})
	var sources: Array = c.get("sources", [])
	if not sources.is_empty():
		rows.append({"label": "来源 / SOURCES", "value": ", ".join(PackedStringArray(sources)), "mono": true})
	var notes: Array = c.get("notes", [])
	if not notes.is_empty():
		rows.append({"label": "注记 / NOTE", "value": String(notes[0])})
	return {"id": "contact", "title": "航迹 / CONTACT", "count": String(c.get("track_id", "")), "rows": rows}


func _sec_phase(_vm: Dictionary) -> Dictionary:
	var st: Dictionary = context.get("state", {})
	var rows: Array = []
	var pc := String(st.get("phase_context", ""))
	if pc == "":
		pc = String(st.get("phase_local", ""))
	if pc != "":
		rows.append({"label": "阶段 / PHASE", "value": pc})
	var pt := String(st.get("phase_title", ""))
	if pt != "":
		rows.append({"label": "阶段名 / TITLE", "value": T.ellipsis(pt, T.F8, 140.0)})
	if st.has("t"):
		rows.append({"label": "世界时 / T+", "value": T.hms(float(st.get("t", 0.0))), "mono": true})
	if st.has("title"):
		rows.append({"label": "场景 / SCENARIO", "value": T.ellipsis(String(st.get("title", "")), T.F8, 150.0)})
	if st.has("track_count"):
		rows.append({"label": "航迹 / TRACKS", "value": str(int(st.get("track_count", 0))), "mono": true})
	if st.has("order_count"):
		rows.append({"label": "命令 / ORDERS", "value": str(int(st.get("order_count", 0))), "mono": true})
	if st.has("entity_count"):
		rows.append({"label": "实体 / ENTITIES", "value": str(int(st.get("entity_count", 0))), "mono": true})
	return {"id": "phase", "title": "阶段 / MISSION", "count": pc, "rows": rows}


func _sec_evidence(_vm: Dictionary) -> Dictionary:
	var evs: Array = context.get("evidence", [])
	var rows: Array = []
	var got := 0
	for raw in evs:
		var ev: Dictionary = raw
		var st := String(ev.get("state", "unknown"))
		var label := String(ev.get("label", ev.get("id", "")))
		var txt := "未取得"
		var col: Color = T.FAINT
		if st == "done":
			txt = "已取得"
			col = T.PH
			got += 1
		elif st == "in_progress":
			txt = "进行中"
			col = T.AMBER
		rows.append({"label": label, "value": "%s · %ds" % [txt, int(ev.get("duration_s", 0.0))], "color": col})
	return {
		"id": "evidence",
		"title": "证据 / EVIDENCE",
		"count": "%d/%d" % [got, evs.size()],
		"rows": rows,
	}


func _sec_orbit(_vm: Dictionary) -> Dictionary:
	var orbit: Dictionary = vm.get("orbit", {})
	var rows: Array = []
	if orbit.has("frame"):
		rows.append({"label": "基准 / FRAME", "value": String(orbit.get("frame")), "mono": true})
	if orbit.has("r"):
		rows.append({"label": "位置 r (km)", "value": T.vec3(orbit.get("r")), "mono": true})
	if orbit.has("v"):
		rows.append({"label": "速度 v (km/s)", "value": T.vec3(orbit.get("v")), "mono": true})
	if orbit.has("epoch"):
		rows.append({"label": "历元 / EPOCH", "value": "%.1f" % T.num(orbit.get("epoch")), "mono": true})
	for key in orbit.keys():
		var k := String(key)
		if k in ["frame", "r", "v", "epoch"]:
			continue
		rows.append({"label": k, "value": str(orbit[key]), "mono": true})
	return {"id": "orbit", "title": "轨道 / ORBIT", "count": "", "rows": rows}


func _sec_signatures(_vm: Dictionary) -> Dictionary:
	var sigs: Dictionary = vm.get("signatures", {})
	var keys: Array = sigs.keys()
	keys.sort()
	var rows: Array = []
	for key in keys:
		rows.append({"label": String(key).to_upper(), "value": str(sigs[key]), "mono": true})
	return {
		"id": "signatures",
		"title": "信号特征 / SIGNATURES",
		"count": "%d" % rows.size(),
		"rows": rows,
	}


func _sec_kind(_vm: Dictionary) -> Dictionary:
	var kind := String(vm.get("kind", "ship"))
	var meta_raw = vm.get("meta", {})
	var meta: Dictionary = meta_raw if meta_raw is Dictionary else {}
	var rows: Array = []
	match kind:
		"contact":
			rows.append({"label": "说明 / NOTE", "value": "该航迹无实体资料（虚警/纯回波）"})
			var srcs: Array = _vm.get("contact", {}).get("sources", []) if _vm.get("contact", {}) is Dictionary else []
			if not srcs.is_empty():
				rows.append({"label": "来源 / SOURCES", "value": ", ".join(PackedStringArray(srcs)), "mono": true})
			var ts: Array = _vm.get("contact", {}).get("tags", []) if _vm.get("contact", {}) is Dictionary else []
			if not ts.is_empty():
				rows.append({"label": "标记 / TAGS", "value": ", ".join(PackedStringArray(ts)), "mono": true})
		"station":
			rows.append({"label": "半径 / RADIUS", "value": _or_dash(String(meta.get("radius", ""))), "mono": true})
			rows.append({"label": "状态 / STATUS", "value": _or_dash(String(meta.get("status", "")))})
		"tank":
			rows.append({"label": "容量 / CAPACITY", "value": _or_dash(String(meta.get("capacity", ""))), "mono": true})
			rows.append({"label": "状态 / STATUS", "value": _or_dash(String(meta.get("status", "")))})
		"wreck":
			rows.append({"label": "威胁 / THREAT", "value": "无威胁", "color": T.THR_NONE})
			rows.append({"label": "来源 / SOURCE", "value": _or_dash(String(meta.get("source", "")))})
		"unknown":
			rows.append({"label": "说明 / NOTE", "value": "实体未给出 kind，右栏仅显示基础字段。"})
		_:
			rows.append({"label": "舰体 / HULL", "value": _or_dash(String(vm.get("hull", ""))), "mono": true})
			rows.append({"label": "阵营 / FACTION", "value": _or_dash(String(vm.get("faction", "")))})
	if not meta.is_empty():
		var keys: Array = meta.keys()
		keys.sort()
		for key in keys:
			rows.append({"label": String(key), "value": _fmt_value(meta[key]), "mono": true})
	var titles := {
		"contact": "接触 / CONTACT",
		"station": "站点 / STATION",
		"tank": "储罐 / TANK",
		"wreck": "残骸 / WRECK",
		"unknown": "未分类 / UNKNOWN",
	}
	var title: String = titles.get(kind, "舰体 / HULL")
	return {"id": "kind", "title": title, "count": kind, "rows": rows}


func _sec_tags(_vm: Dictionary) -> Dictionary:
	var tags: Array = vm.get("tags", [])
	return {
		"id": "tags",
		"title": "标记 / TAGS",
		"count": "%d" % tags.size(),
		"rows": [{"label": "tags", "value": ", ".join(PackedStringArray(tags)), "mono": true}],
	}


func _sec_actions(_vm: Dictionary) -> Dictionary:
	var rows: Array = []
	var avail := 0
	for raw in actions:
		var act: Dictionary = raw
		var ok := bool(act.get("available", false))
		if ok:
			avail += 1
		var value := "可用" if ok else String(act.get("reason", "不可用"))
		rows.append({
			"label": String(act.get("label", act.get("id", ""))),
			"value": value,
			"color": T.PH if ok else T.a(T.AMBER, 0.72),
			"mono": false,
		})
	return {
		"id": "actions",
		"title": "目标动作 / ACTIONS",
		"count": "%d/%d" % [avail, actions.size()],
		"rows": rows,
	}


# ── 布局 / 绘制 ──────────────────────────────────────────────────────────

func _relayout() -> void:
	_layout.clear()
	var y := _content_pad
	for raw in sections:
		var sec: Dictionary = raw
		var rows: Array = sec.get("rows", [])
		var h := T.SECTION_HEADER_H + float(rows.size()) * T.ROW_SECTION + 10.0
		_layout.append({"sec": sec, "y": y, "h": h})
		y += h
	set_content_height(y + _content_pad)


func _row_width() -> float:
	return body_rect().size.x


func _draw_frame() -> void:
	T.panel(self, Rect2(0.0, 0.0, size.x, size.y), 0.965, 0.85)
	if vm.is_empty():
		T.text(self, 16.0, 18.0, "未选择 / NO SELECTION", T.F10, T.FAINT)
		T.text(self, 16.0, 38.0, "左侧列表选择实体 → 按 kind / capabilities 生成 section", T.F8, T.a(T.FAINT, 0.8))
		return

	var identity := String(vm.get("identity", "unknown"))
	var disp_name := String(vm.get("name", ""))
	if disp_name == "":
		disp_name = "[%s]" % String(vm.get("id", ""))
	T.text(self, 16.0, 12.0, "选中对象 / SELECTED", T.F8, T.a(accent, 0.95))
	T.text_fit(self, 16.0, 28.0, disp_name, T.F18, accent, size.x - 32.0)
	T.text_fit(self, 16.0, 52.0, "[%s] %s" % [String(vm.get("batch", vm.get("id", "—"))), String(vm.get("name_en", ""))],
		T.F8, T.DIM, size.x - 32.0, false)
	T.text_fit(self, 16.0, 68.0, "%s · %s" % [_or_dash(String(vm.get("cls", ""))), _or_dash(String(vm.get("role", "")))],
		T.F9, T.a(T.TXT, 0.9), size.x - 32.0)
	T.text_fit(self, 16.0, 84.0, _or_dash(String(vm.get("faction", ""))), T.F7, T.a(T.DIM, 0.9), size.x - 32.0)

	# 身份 / L 级 / kind / OWN·TARGET 四枚 chip
	var cx := 16.0
	var chip_y := 100.0
	cx = _chip_at(cx, chip_y, T.identity_label(identity), T.identity_color(identity))
	cx = _chip_at(cx, chip_y, "L%d" % int(vm.get("level", 0)), T.identity_color(identity))
	cx = _chip_at(cx, chip_y, T.kind_label(String(vm.get("kind", "ship"))), T.kind_color(String(vm.get("kind", "ship"))))
	_chip_at(cx, chip_y, "OWN" if bool(vm.get("is_own", false)) else "TARGET",
		T.PH if bool(vm.get("is_own", false)) else T.AMBER)

	T.hline(self, 12.0, header_h - 6.0, size.x - 12.0, T.a(T.LINE, 0.9))
	T.hline(self, 12.0, size.y - footer_h, size.x - 12.0, T.a(T.LINE, 0.6))
	var hint := "滚轮滚动 · %d section · 内容 %dpx" % [sections.size(), int(content_height)]
	T.text_fit(self, 14.0, size.y - footer_h + 4.0, hint, T.F7, T.a(T.FAINT, 0.9), size.x - 28.0)


func _chip_at(x: float, y: float, label: String, col: Color) -> float:
	var w := T.text_w(label, T.F7, T.has_cjk(label)) + 10.0
	T.chip(self, Rect2(x, y, w, 16.0), label, col, true, T.F7)
	return x + w + 4.0


func _paint_content(ci: CanvasItem) -> void:
	if vm.is_empty():
		return
	var w := _row_width()
	for raw in _layout:
		var lay: Dictionary = raw
		var y := float(lay["y"]) - offset
		var h := float(lay["h"])
		if y + h < 0.0 or y > view_height():
			continue
		var sec: Dictionary = lay["sec"]
		# section 头（同一基线）
		ci.draw_rect(Rect2(0.0, y + 3.0, 2.0, 12.0), T.a(accent, 0.7))
		T.text_baseline(ci, 8.0, y + 14.0, T.ellipsis(String(sec.get("title", "")), T.F8, w - 84.0, true),
			T.F8, T.a(T.TXT, 0.92))
		var count := String(sec.get("count", ""))
		if count != "":
			T.text_baseline_r(ci, w - 2.0, y + 14.0, count, T.F7, T.a(accent, 0.75), false)
		ci.draw_line(Vector2(8.0, y + T.SECTION_HEADER_H - 2.0), Vector2(w - 2.0, y + T.SECTION_HEADER_H - 2.0),
			T.a(T.LINE, 0.45), 1.0)
		# 行
		var rows: Array = sec.get("rows", [])
		var ry := y + T.SECTION_HEADER_H
		for raw_row in rows:
			var row: Dictionary = raw_row
			var label := String(row.get("label", ""))
			var value := String(row.get("value", ""))
			var col: Color = row.get("color", T.TXT)
			var mono := bool(row.get("mono", false))
			var cjk := T.has_cjk(value) or not mono
			var baseline := ry + 13.0
			T.text_baseline(ci, 8.0, baseline, T.ellipsis(label, T.F7, w * 0.42), T.F7, T.a(T.DIM, 0.95))
			T.text_baseline_r(ci, w - 2.0, baseline, T.ellipsis(value, T.F9, w * 0.58 - 10.0, cjk),
				T.F9, col, cjk)
			ry += T.ROW_SECTION
		ry += 10.0


# ══ helpers ══════════════════════════════════════════════════════════════

func _fmt_value(v: Variant) -> String:
	if v is Array:
		var parts: Array = []
		for item in (v as Array):
			parts.append(String(item))
		return ", ".join(PackedStringArray(parts))
	if v is Dictionary:
		return str(v)
	return str(v)


func _or_dash(s: String) -> String:
	return s if s != "" else "—"


func _threat_label(threat: String) -> String:
	match threat:
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
