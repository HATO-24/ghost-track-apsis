extends Control

## V2-4 损管面板（右/下区独立面板）。
##
## core V2-CORE-3 提供 `vm_damage()` / `start_repair(id)` 时直接消费；
## 未就绪时使用 **UI 本地损管兜底**（明确标注 fallback；不改 core/sim/content）。
## 显示：sections 状态/严重度/完整度条 → 点击启动维修 → 队列/剩余时间；警告层级
## DAMAGED(红) > DEGRADED(琥珀) > REPAIRING(蓝) > NOMINAL(绿)。

signal repair_requested(section_id: String)

const T := preload("res://ui/theme.gd")

var data = null
var fallback := true
var note := ""
var sections: Array = []
var queue: Array = []
var summary: Dictionary = {}
var _buttons: Array = []
var _hover := -1
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_fallback()


func _init_fallback() -> void:
	fallback = true
	note = "UI 兜底：core 无 vm_damage()/start_repair()（契约见 docs/09 §32）；本地维修队列不写 core"
	sections = [
		{"id": "sensor_align", "label": "传感器校准 / SENSOR ALIGN", "state": "damaged",
			"severity": 0.55, "repair_eta_s": 24.0, "progress": 0.0, "integrity": 0.45},
		{"id": "ir_false_alarm", "label": "红外虚警 / IR FALSE ALARM", "state": "degraded",
			"severity": 0.35, "repair_eta_s": 18.0, "progress": 0.0, "integrity": 0.65},
		{"id": "thermal", "label": "热控 / THERMAL", "state": "damaged",
			"severity": 0.50, "repair_eta_s": 30.0, "progress": 0.0, "integrity": 0.50},
	]
	queue = []
	_summary()


func bind(data_ref) -> void:
	data = data_ref
	_sync()
	queue_redraw()


func _sync() -> void:
	if data == null:
		return
	var vm: Dictionary = data.vm_damage()
	if bool(vm.get("available", false)):
		fallback = false
		note = "core vm_damage() · repair_slot=%s" % str(vm.get("repair_slot", "—"))
		sections = vm.get("sections", []) if vm.get("sections", []) is Array else []
		queue = vm.get("queue", []) if vm.get("queue", []) is Array else []
		summary = vm.get("summary", {}) if vm.get("summary", {}) is Dictionary else {}
	else:
		note = String(vm.get("reason", "core 损管未就绪；UI 本地兜底"))
		if sections.is_empty():
			_init_fallback()
		_summary()


func _summary() -> void:
	var damaged := 0
	var repairing := 0
	var nominal := 0
	for raw in sections:
		var s: Dictionary = raw
		var st := String(s.get("state", "nominal"))
		if st == "damaged" or st == "degraded":
			damaged += 1
		elif st == "repairing":
			repairing += 1
		else:
			nominal += 1
	summary = {"damaged": damaged, "repairing": repairing, "nominal": nominal,
		"total": sections.size(), "queue": queue.size()}


## 本地兜底推进（core 模式下由 world.advance 推进，panel 只刷新）。
func tick(dt: float) -> void:
	_t += dt
	if not fallback:
		return
	var still: Array = []
	for raw in queue:
		var q: Dictionary = raw
		var dur := maxf(0.1, float(q.get("duration_s", 20.0)))
		q["elapsed_s"] = float(q.get("elapsed_s", 0.0)) + dt
		q["progress"] = clampf(float(q["elapsed_s"]) / dur, 0.0, 1.0)
		if float(q["progress"]) >= 1.0:
			for raw_s in sections:
				var s: Dictionary = raw_s
				if String(s.get("id", "")) == String(q.get("section_id", "")):
					s["state"] = "nominal"
					s["progress"] = 1.0
					s["integrity"] = 1.0
			still.append({"done": true, "section_id": String(q.get("section_id", ""))})
		else:
			still.append(q)
	queue = []
	for raw2 in still:
		var row: Dictionary = raw2
		if bool(row.get("done", false)):
			continue
		queue.append(row)
	for raw3 in sections:
		var sec: Dictionary = raw3
		if String(sec.get("state", "")) == "repairing":
			var has := false
			for raw4 in queue:
				if String((raw4 as Dictionary).get("section_id", "")) == String(sec.get("id", "")):
					has = true
			if not has:
				sec["state"] = "degraded" if float(sec.get("integrity", 0.0)) < 0.8 else "nominal"
	_summary()
	queue_redraw()


## 启动维修：core 可用时调 start_repair；否则进入 UI 本地维修队列。
func repair(section_id: String) -> Dictionary:
	if data != null and not fallback:
		var r: Dictionary = data.start_repair(section_id)
		if not bool(r.get("ok", false)):
			return {"ok": false, "reason": String(r.get("reason", "core start_repair 拒绝"))}
		_sync()
		return {"ok": true, "fallback": false}
	for raw in queue:
		if String((raw as Dictionary).get("section_id", "")) == section_id:
			return {"ok": false, "reason": "该 section 已在维修队列"}
	for raw2 in sections:
		var sec: Dictionary = raw2
		if String(sec.get("id", "")) != section_id:
			continue
		if String(sec.get("state", "")) == "nominal":
			return {"ok": false, "reason": "该 section 状态正常"}
		var dur := float(sec.get("repair_eta_s", 24.0))
		queue.append({"section_id": section_id, "label": String(sec.get("label", section_id)),
			"duration_s": dur, "elapsed_s": 0.0, "progress": 0.0})
		sec["state"] = "repairing"
		_summary()
		queue_redraw()
		return {"ok": true, "fallback": true}
	return {"ok": false, "reason": "未知 section"}


func is_repairing(section_id: String) -> bool:
	for raw in queue:
		if String((raw as Dictionary).get("section_id", "")) == section_id:
			return true
	return false


func state_color(state: String) -> Color:
	match state:
		"damaged":
			return T.RED
		"degraded":
			return T.AMBER
		"repairing":
			return T.BLUE
		_:
			return T.PH


func _state_label(state: String) -> String:
	match state:
		"damaged":
			return "受损 / DAMAGED"
		"degraded":
			return "降级 / DEGRADED"
		"repairing":
			return "维修中 / REPAIRING"
		_:
			return "正常 / NOMINAL"


# ══ 绘制 ═════════════════════════════════════════════════════════════════

func _draw() -> void:
	T.panel(self, Rect2(0.0, 0.0, size.x, size.y), 0.965, 0.85)
	T.text(self, 12.0, 8.0, "损管 / DAMAGE CONTROL", T.F9, T.TXT)
	var warn := 0
	for raw in sections:
		var st := String((raw as Dictionary).get("state", "nominal"))
		if st == "damaged":
			warn += 2
		elif st == "degraded":
			warn += 1
	var tier := "NOMINAL"
	var tier_col: Color = T.PH
	if warn >= 4:
		tier = "CRITICAL"
		tier_col = T.RED
	elif warn >= 1:
		tier = "CAUTION"
		tier_col = T.AMBER
	T.text_r(self, size.x - 12.0, 8.0, tier, T.F9, T.a(tier_col, 0.95), false)
	T.hline(self, 10.0, 26.0, size.x - 10.0, T.a(T.LINE, 0.65))
	_buttons.clear()
	var y := 32.0
	for raw2 in sections:
		var sec: Dictionary = raw2
		var st := String(sec.get("state", "nominal"))
		var col := state_color(st)
		var label := String(sec.get("label", sec.get("id", "")))
		T.text_fit(self, 12.0, y, label, T.F7, T.a(T.TXT, 0.95), 210.0)
		T.text_r(self, size.x - 12.0, y, _state_label(st), T.F7, T.a(col, 0.95))
		var bar := Rect2(12.0, y + 11.0, 250.0, 3.0)
		var integrity := float(sec.get("integrity", 1.0 - float(sec.get("severity", 0.0))))
		T.bar(self, bar, integrity, col)
		var btn := Rect2(size.x - 92.0, y - 2.0, 80.0, 16.0)
		var repairing := st == "repairing" or is_repairing(String(sec.get("id", "")))
		if st != "nominal" and not repairing:
			_buttons.append({"rect": btn, "id": String(sec.get("id", "")), "label": "维修 / REPAIR",
				"enabled": true})
		elif repairing:
			T.text_r(self, size.x - 92.0, y, "进行中", T.F7, T.a(T.BLUE, 0.9))
		y += 22.0
	# 队列
	T.text(self, 12.0, y + 2.0, "维修队列 / REPAIR QUEUE", T.F7, T.FAINT)
	y += 16.0
	if queue.is_empty():
		T.text(self, 12.0, y, "（队列为空）", T.F7, T.a(T.FAINT, 0.9))
	else:
		for raw3 in queue:
			var q: Dictionary = raw3
			var dur := 1.0
			var prog := float(q.get("progress", 0.0))
			if not fallback and not q.has("progress"):
				var eta := float(q.get("repair_eta_s", 1.0))
				var remain := float(q.get("repair_remaining_s", 0.0))
				dur = maxf(0.1, eta)
				prog = clampf(1.0 - remain / dur, 0.0, 1.0)
			else:
				dur = maxf(0.1, float(q.get("duration_s", 1.0)))
			T.text_fit(self, 12.0, y, String(q.get("label", q.get("section_id", ""))), T.F7, T.a(T.TXT, 0.9), 250.0)
			T.bar(self, Rect2(270.0, y + 2.0, 140.0, 3.0), prog, T.BLUE)
			T.text_r(self, size.x - 12.0, y, "%.0f%%" % (prog * 100.0), T.F7, T.a(T.BLUE, 0.9), false)
			y += 16.0
	if not fallback:
		T.text_fit(self, 12.0, size.y - 26.0, note, T.F7, T.a(T.PH_DIM, 0.9), size.x - 24.0)
	else:
		T.text_fit(self, 12.0, size.y - 26.0, note, T.F7, T.a(T.AMBER, 0.9), size.x - 24.0)
	T.text(self, 12.0, size.y - 14.0, "点击 REPAIR 启动；警告层级 DAMAGED > DEGRADED > REPAIRING > NOMINAL",
		T.F7, T.a(T.FAINT, 0.85))
	for i in range(_buttons.size()):
		var b: Dictionary = _buttons[i]
		var r: Rect2 = b["rect"]
		var hot := i == _hover
		draw_rect(r, T.a(T.PH, 0.16 if hot else 0.06))
		draw_rect(r, T.a(T.PH, 0.8 if hot else 0.45), false, 1.0)
		T.text_c(self, r.get_center().x, r.position.y + 2.0, String(b.get("label", "")), T.F7, T.a(T.PH, 0.95))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var h := -1
		for i in range(_buttons.size()):
			if (_buttons[i]["rect"] as Rect2).has_point(mm.position):
				h = i
				break
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		for i in range(_buttons.size()):
			var b: Dictionary = _buttons[i]
			if not (b["rect"] as Rect2).has_point(mb.position):
				continue
			var r: Dictionary = repair(String(b.get("id", "")))
			print("V2-4 DAMAGE REPAIR ", b.get("id"), " ok=", r.get("ok"), " reason=", r.get("reason"))
			repair_requested.emit(String(b.get("id", "")))
			accept_event()
			return
