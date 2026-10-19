extends Control

## CISLUNAR EXPLORER · V1 HUD overlay（CISLUNAR-UI-1）
##
## 纯绘制层：只读 `vm`（由 explorer.gd 每帧填充），不持有场景逻辑、不做相机/时间控制。
## 视觉 = V1：薄荷绿线框、1px 边框、7–11pt 等宽/中文字体、四角刻度；不做 V2 大留白。
##
## vm 字段（explorer.gd 填充）：
##   t / speed / paused / source("placeholder"|"model") / model_note
##   objects: [{id,name,name_en,kind,screen:Vector2,on_screen,selected,meta}]
##   selected: {id,name,name_en,kind,radius_km,period_s,dist_earth_km,dist_moon_km,note}
##
## 点击对象列表：explorer.gd 调用 row_at(pos) → {id, rect}。

const Pal := preload("res://scripts/pal.gd")
const UiFonts := preload("res://scripts/fonts.gd")

const LIST_RECT := Rect2(40.0, 40.0, 380.0, 440.0)
const INFO_RECT := Rect2(1480.0, 40.0, 400.0, 334.0)
const MODULE_RECT := Rect2(1480.0, 560.0, 400.0, 290.0)
const CTRL_RECT := Rect2(40.0, 866.0, 620.0, 168.0)
const TIME_RECT := Rect2(1480.0, 866.0, 400.0, 168.0)
const ROW_H := 20.0
const LIST_TOP := 112.0
const FOOT_Y := 1054.0

var vm: Dictionary = {}
var mono: Font
var cjk: Font
var _stars: Array[Vector2] = []
var _star_a: Array[float] = []


func _ready() -> void:
	mono = UiFonts.mono()
	cjk = UiFonts.cjk()
	mouse_filter = Control.MOUSE_FILTER_IGNORE     # 点击由 explorer._unhandled_input 处理
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20871103
	for i in range(140):
		_stars.append(Vector2(rng.randf_range(0.0, 1920.0), rng.randf_range(0.0, 1080.0)))
		_star_a.append(rng.randf_range(0.10, 0.34))


func set_vm(view_model: Dictionary) -> void:
	vm = view_model


# ═══════════════════════════════════════════════════════════════════
# 列表命中（explorer 点击用；与 _draw 同布局）
# ═══════════════════════════════════════════════════════════════════

func _object_rows() -> Array:
	var rows: Array = []
	for raw in (vm.get("objects", []) as Array):
		if raw is Dictionary:
			rows.append(raw)
	return rows


func row_at(p: Vector2) -> String:
	if p.x < LIST_RECT.position.x or p.x > LIST_RECT.end.x:
		return ""
	var objs := _object_rows()
	for i in range(objs.size()):
		var top := LIST_TOP + ROW_H * float(i)
		var r := Rect2(LIST_RECT.position.x + 10.0, top - 14.0, LIST_RECT.size.x - 20.0, ROW_H)
		if r.has_point(p):
			return String((objs[i] as Dictionary).get("id", ""))
	return ""


# ═══════════════════════════════════════════════════════════════════
# 绘制
# ═══════════════════════════════════════════════════════════════════

func _draw() -> void:
	_draw_stars()
	_draw_title()
	_draw_list()
	_draw_info()
	_draw_modules()
	_draw_controls()
	_draw_time()
	_draw_legend()
	_draw_labels()
	_draw_footer()


func _draw_stars() -> void:
	for i in range(_stars.size()):
		var p: Vector2 = _stars[i]
		var a := float(_star_a[i])
		draw_circle(p, 1.0 if i % 7 == 0 else 0.6, Pal.a(Pal.PH_FAINT, a))


func _panel(r: Rect2, title_cn: String, title_en: String) -> void:
	draw_rect(r, Pal.a(Pal.BG, 0.62))
	draw_rect(r, Pal.a(Pal.LINE, 0.9), false, 1.0)
	# V1 四角刻度
	var k := 9.0
	draw_line(r.position, r.position + Vector2(k, 0), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.position, r.position + Vector2(0, k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - k, r.position.y), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + k, r.end.y), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.end, r.end - Vector2(k, 0), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.end, r.end - Vector2(0, k), Pal.a(Pal.PH, 0.55), 1.0)
	_txt(mono, r.position.x + 10.0, r.position.y + 16.0, title_en, 8, Pal.a(Pal.PH, 0.92))
	_txt(cjk, r.position.x + 10.0 + 7.2 * float(title_en.length()), r.position.y + 16.0,
		" / " + title_cn, 8, Pal.a(Pal.DIM, 0.85))
	draw_line(Vector2(r.position.x + 10.0, r.position.y + 22.0),
		Vector2(r.end.x - 10.0, r.position.y + 22.0), Pal.a(Pal.LINE, 0.7), 1.0)


func _draw_title() -> void:
	_txt(mono, 40.0, 26.0, "CISLUNAR EXPLORER", 11, Pal.PH)
	_txt(cjk, 258.0, 26.0, "地月系自由探索 · V1 线框技术演示", 8, Pal.a(Pal.DIM, 0.9))
	_txt(mono, 40.0, 40.0, "EARTH-MOON SYSTEM / FREE EXPLORATION · SER. 058",
		7, Pal.a(Pal.PH_FAINT, 0.95))


func _draw_list() -> void:
	_panel(LIST_RECT, "对象列表", "OBJECTS")
	var objs := _object_rows()
	for i in range(objs.size()):
		var o: Dictionary = objs[i]
		var y := LIST_TOP + ROW_H * float(i)
		var sel := bool(o.get("selected", false))
		var col: Color = o.get("color", Pal.PH)
		if sel:
			draw_rect(Rect2(LIST_RECT.position.x + 6.0, y - 14.0, LIST_RECT.size.x - 12.0, ROW_H - 2.0),
				Pal.a(Pal.PH, 0.07))
			draw_rect(Rect2(LIST_RECT.position.x + 6.0, y - 14.0, 2.0, ROW_H - 2.0), Pal.a(col, 0.9))
			_txt(mono, LIST_RECT.position.x + 12.0, y, ">", 7, Pal.a(col, 1.0))
		else:
			_txt(mono, LIST_RECT.position.x + 12.0, y, "·", 7, Pal.a(col, 0.45))
		var num := "[%03d]" % (i + 1)
		_txt(mono, LIST_RECT.position.x + 24.0, y, num, 7, Pal.a(Pal.PH_FAINT, 0.9))
		var name := String(o.get("name", ""))
		var f: Font = cjk if UiFonts.has_cjk(name) else mono
		_txt(f, LIST_RECT.position.x + 62.0, y, name, 7,
			Pal.a(col, 0.95 if sel else 0.78))
		var kind := String(o.get("kind_label", ""))
		_txt_r(mono, LIST_RECT.end.x - 12.0, y, kind, 7, Pal.a(Pal.FAINT, 0.95))


func _draw_info() -> void:
	_panel(INFO_RECT, "当前选中", "SELECTED OBJECT")
	var s: Dictionary = vm.get("selected", {})
	if s.is_empty():
		_txt(mono, INFO_RECT.position.x + 12.0, INFO_RECT.position.y + 52.0, "NO SELECTION", 8, Pal.a(Pal.FAINT, 0.9))
		return
	var col: Color = s.get("color", Pal.PH)
	_txt(mono, INFO_RECT.position.x + 12.0, INFO_RECT.position.y + 46.0,
		String(s.get("id", "")), 8, Pal.a(Pal.FAINT, 0.9))
	var name := String(s.get("name", ""))
	var f: Font = cjk if UiFonts.has_cjk(name) else mono
	_txt(f, INFO_RECT.position.x + 12.0, INFO_RECT.position.y + 64.0, name, 11, Pal.a(col, 0.98))
	var y := INFO_RECT.position.y + 88.0
	_txt(mono, INFO_RECT.position.x + 12.0, y, "KIND", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, INFO_RECT.position.x + 116.0, y, String(s.get("kind", "—")), 7, Pal.a(Pal.TXT, 0.85))
	y += 16.0
	_txt(mono, INFO_RECT.position.x + 12.0, y, "RADIUS", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, INFO_RECT.position.x + 116.0, y, String(s.get("radius_text", "—")), 7, Pal.a(Pal.TXT, 0.85))
	y += 16.0
	_txt(mono, INFO_RECT.position.x + 12.0, y, "PERIOD", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, INFO_RECT.position.x + 116.0, y, String(s.get("period_text", "—")), 7, Pal.a(Pal.TXT, 0.85))
	y += 16.0
	_txt(mono, INFO_RECT.position.x + 12.0, y, "D.EARTH", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, INFO_RECT.position.x + 116.0, y, String(s.get("dist_earth_text", "—")), 7, Pal.a(Pal.TXT, 0.85))
	y += 16.0
	_txt(mono, INFO_RECT.position.x + 12.0, y, "D.MOON", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, INFO_RECT.position.x + 116.0, y, String(s.get("dist_moon_text", "—")), 7, Pal.a(Pal.TXT, 0.85))
	y += 20.0
	var note := String(s.get("note", ""))
	if note != "":
		var fn: Font = cjk if UiFonts.has_cjk(note) else mono
		_txt(fn, INFO_RECT.position.x + 12.0, y, note, 7, Pal.a(Pal.DIM, 0.85))


func _draw_controls() -> void:
	_panel(CTRL_RECT, "控制", "CONTROLS")
	var lines := [
		"LMB 拖拽 旋转   RMB/MMB 拖拽 平移   滚轮 缩放",
		"1 地球焦点   2 月球焦点   3 L1 焦点   4 选中焦点",
		"TAB 循环选择   R 重置视角/时间   SPACE 暂停",
		"- / =  时间倍率 1× / 10× / 100× / 1000×",
		"5 L1 站聚焦   6 舰船聚焦   7 地球港聚焦",
		"点击对象 / 左侧列表；选中后右侧 MODULES",
	]
	for i in range(lines.size()):
		var ln := String(lines[i])
		var f: Font = cjk if UiFonts.has_cjk(ln) else mono
		_txt(f, CTRL_RECT.position.x + 12.0, CTRL_RECT.position.y + 46.0 + 17.0 * float(i), ln, 7,
			Pal.a(Pal.DIM, 0.9))


func _draw_time() -> void:
	_panel(TIME_RECT, "时间", "TIME / SIM")
	var t := float(vm.get("t", 0.0))
	var spd := float(vm.get("speed", 1.0))
	var paused := bool(vm.get("paused", false))
	_txt(mono, TIME_RECT.position.x + 12.0, TIME_RECT.position.y + 48.0, "T+ " + _fmt_hms(t), 9,
		Pal.a(Pal.PH, 0.95))
	_txt(mono, TIME_RECT.position.x + 12.0, TIME_RECT.position.y + 66.0,
		"RATE ×%s" % _fmt_speed(spd), 7, Pal.a(Pal.BLUE, 0.9))
	_txt(mono, TIME_RECT.position.x + 150.0, TIME_RECT.position.y + 66.0,
		"PAUSED" if paused else "RUNNING", 7,
		Pal.a(Pal.AMBER if paused else Pal.PH, 0.92))
	var src := String(vm.get("source", "placeholder"))
	_txt(mono, TIME_RECT.position.x + 12.0, TIME_RECT.position.y + 90.0,
		"MODEL", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, TIME_RECT.position.x + 116.0, TIME_RECT.position.y + 90.0,
		"sim/cislunar_model" if src == "model" else "placeholder (NOT READY)", 7,
		Pal.a(Pal.PH if src == "model" else Pal.AMBER, 0.9))
	_txt(mono, TIME_RECT.position.x + 12.0, TIME_RECT.position.y + 108.0,
		"fmt: EARTH-MOON CIRCULAR + CR3BP L-points", 7, Pal.a(Pal.FAINT, 0.85))


func _draw_legend() -> void:
	var x := 40.0
	var y := 500.0
	_txt(mono, x, y, "LEGEND", 7, Pal.a(Pal.PH, 0.85))
	var items := [
		["地球/月球 线框", Pal.PH],
		["月球轨道", Pal.PH_DIM],
		["GEO 环 / 月球同步环", Pal.BLUE],
		["L1–L5 站点 / 平动点", Pal.AMBER],
		["港口/站点", Pal.ID_SUSPECT],
		["舰船（技术演示几何）", Pal.BLUE],
	]
	for i in range(items.size()):
		var it: Array = items[i]
		var yy := y + 16.0 + 15.0 * float(i)
		var col: Color = it[1]
		draw_line(Vector2(x, yy - 3.0), Vector2(x + 18.0, yy - 3.0), Pal.a(col, 0.85), 1.0)
		var ln := String(it[0])
		var f: Font = cjk if UiFonts.has_cjk(ln) else mono
		_txt(f, x + 26.0, yy, ln, 7, Pal.a(Pal.DIM, 0.85))


func _draw_modules() -> void:
	_panel(MODULE_RECT, "模块与端口", "MODULES / PORTS")
	var s: Dictionary = vm.get("selected", {})
	if s.is_empty():
		_txt(mono, MODULE_RECT.position.x + 12.0, MODULE_RECT.position.y + 52.0,
			"NO SELECTION", 7, Pal.a(Pal.FAINT, 0.9))
		return
	var modules: Array = s.get("modules", [])
	var y := MODULE_RECT.position.y + 44.0
	if modules.is_empty():
		_txt(mono, MODULE_RECT.position.x + 12.0, y,
			"NO MODULE DATA（天体 / 轨道环 / 平动点）", 7, Pal.a(Pal.FAINT, 0.9))
		y += 16.0
	else:
		var n := mini(10, modules.size())
		var rows := int(ceil(float(n) / 2.0))
		for i in range(n):
			var col := i % 2
			var row := i / 2
			var x := MODULE_RECT.position.x + 12.0 + 196.0 * float(col)
			var yy := y + 16.0 * float(row)
			_txt(mono, x, yy, "· " + _fit(mono, String(modules[i]), 7, 178.0), 7,
				Pal.a(Pal.TXT, 0.86))
		y += 16.0 * float(rows) + 4.0
	var ports: Array = s.get("ports", [])
	if not ports.is_empty():
		var ptext := ""
		for i2 in range(ports.size()):
			if i2 > 0:
				ptext += " · "
			ptext += String(ports[i2])
		_txt(mono, MODULE_RECT.position.x + 12.0, y, "PORTS", 7, Pal.a(Pal.FAINT, 0.9))
		_txt(mono, MODULE_RECT.position.x + 76.0, y, _fit(mono, ptext, 7, 306.0), 7,
			Pal.a(Pal.TXT, 0.82))
		y += 16.0
	var vis := String(s.get("visual_text", ""))
	if vis != "":
		_txt(cjk if UiFonts.has_cjk(vis) else mono, MODULE_RECT.position.x + 12.0, y,
			_fit(cjk if UiFonts.has_cjk(vis) else mono, vis, 7, 372.0), 7, Pal.a(Pal.DIM, 0.85))
		y += 16.0
	var stext := String(s.get("status_text", ""))
	if stext != "":
		_txt(cjk if UiFonts.has_cjk(stext) else mono, MODULE_RECT.position.x + 12.0, y,
			_fit(cjk if UiFonts.has_cjk(stext) else mono, stext, 7, 372.0), 7,
			Pal.a(Pal.PH_DIM, 0.9))


func _draw_labels() -> void:
	var placed: Array[Rect2] = []
	for raw in _object_rows():
		var o: Dictionary = raw
		if not bool(o.get("on_screen", false)):
			continue
		var p: Vector2 = o.get("screen", Vector2(-9999, -9999))
		if p.x < 0.0 or p.y < 0.0 or p.x > 1920.0 or p.y > 1080.0:
			continue
		if LIST_RECT.has_point(p) or INFO_RECT.has_point(p) \
				or CTRL_RECT.has_point(p) or TIME_RECT.has_point(p):
			continue
		var col: Color = o.get("color", Pal.PH)
		var sel := bool(o.get("selected", false))
		var label := String(o.get("label", ""))
		var f: Font = cjk if UiFonts.has_cjk(label) else mono
		var sz := 8 if sel else 7
		var a := 0.98 if sel else 0.80
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
		var cands: Array[Vector2] = []
		for row in range(4):
			cands.append(Vector2(p.x + 16.0, p.y - 2.0 + 13.0 * float(row)))
		for row2 in range(4):
			cands.append(Vector2(p.x - 22.0 - tw, p.y - 2.0 + 13.0 * float(row2)))
		cands.append(Vector2(p.x + 16.0, p.y - 17.0))
		var tx := p.x + 16.0
		var ty := p.y - 2.0
		var placed_ok := false
		for cpos in cands:
			var cp: Vector2 = cpos
			var r := Rect2(cp.x - 2.0, cp.y - float(sz), tw + 4.0, float(sz) + 4.0)
			if cp.x < 8.0 or cp.y < 20.0 or cp.x + tw > 1912.0 or cp.y > 1012.0:
				continue
			var clash := false
			for used in placed:
				if used.intersects(r):
					clash = true
					break
			if not clash:
				tx = cp.x
				ty = cp.y
				placed.append(r)
				placed_ok = true
				break
		# 密集区放弃次要标签（V1 式避让）；选中标签始终显示
		if not placed_ok and not sel:
			continue
		if not placed_ok:
			placed.append(Rect2(tx - 2.0, ty - float(sz), tw + 4.0, float(sz) + 4.0))
		var tick_a := 0.9 if sel else 0.55
		if tx > p.x:
			draw_line(p + Vector2(4.0, 0.0), Vector2(tx - 4.0, ty - 3.0), Pal.a(col, tick_a), 1.0)
		else:
			draw_line(p + Vector2(-4.0, 0.0), Vector2(tx + tw + 4.0, ty - 3.0), Pal.a(col, tick_a), 1.0)
		if sel:
			draw_rect(Rect2(p - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Pal.a(col, 0.85), false, 1.0)
			draw_line(p - Vector2(0.0, 9.0), p + Vector2(0.0, 9.0), Pal.a(col, 0.6), 1.0)
			draw_line(p - Vector2(9.0, 0.0), p + Vector2(9.0, 0.0), Pal.a(col, 0.6), 1.0)
		else:
			draw_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Pal.a(col, 0.80), true)
		_txt(f, tx, ty, label, sz, Pal.a(col, a))


func _draw_footer() -> void:
	draw_line(Vector2(40.0, FOOT_Y - 14.0), Vector2(1880.0, FOOT_Y - 14.0), Pal.a(Pal.LINE, 0.8), 1.0)
	_txt(mono, 40.0, FOOT_Y, "EARTH-MOON CIRCULAR MODEL / CR3BP L-POINTS", 7, Pal.a(Pal.PH, 0.85))
	var src := String(vm.get("source", "placeholder"))
	if src == "model":
		_txt(mono, 560.0, FOOT_Y, "DATA: sim/cislunar_model.sample(t)", 7, Pal.a(Pal.PH, 0.75))
	else:
		_txt(mono, 560.0, FOOT_Y,
			"DATA: PLACEHOLDER CONSTANTS · sim/cislunar_model.gd NOT READY（不伪造实时状态）",
			7, Pal.a(Pal.AMBER, 0.85))
	_txt_r(mono, 1880.0, FOOT_Y, "CISLUNAR TECHNICAL DEMO · V1 WIREFRAME · SER. 058", 7,
		Pal.a(Pal.PH_FAINT, 0.95))
	var note := String(vm.get("model_note", ""))
	if note != "":
		_txt(mono, 40.0, FOOT_Y - 24.0, note, 7, Pal.a(Pal.FAINT, 0.8))


# ═══════════════════════════════════════════════════════════════════
# 文本工具
# ═══════════════════════════════════════════════════════════════════

func _fit(f: Font, s: String, size: int, maxw: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= maxw:
		return s
	var cut := s
	while cut.length() > 1 and f.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > maxw:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "…"


func _fmt_hms(t: float) -> String:
	var sec := int(maxf(0.0, t))
	var d := sec / 86400
	var h := (sec % 86400) / 3600
	var m := (sec % 3600) / 60
	var s := sec % 60
	if d > 0:
		return "%dD %02d:%02d:%02d" % [d, h, m, s]
	return "%02d:%02d:%02d" % [h, m, s]


func _fmt_speed(spd: float) -> String:
	if spd >= 1000.0:
		return "1000"
	if spd >= 100.0:
		return "100"
	if spd >= 10.0:
		return "10"
	return "1"


func _txt(f: Font, x: float, y: float, s: String, size: int, c: Color) -> void:
	draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, c)


func _txt_r(f: Font, xr: float, y: float, s: String, size: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(f, Vector2(xr - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, c)
