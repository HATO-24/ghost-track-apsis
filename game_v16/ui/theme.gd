extends RefCounted

## V2 UI 主题令牌（theme tokens）。
##
## 只放“视觉常量 + 文本/图形原语”，不放布局矩形（布局在 `ui/layout.gd`），
## 不放业务数据（数据在 `ui/data_source.gd`）。
##
## 色板复用 `scripts/pal.gd`（V1.5 薄荷绿），字体复用 `scripts/fonts.gd`；
## 这里的 `F*`/`S*`/`ROW_*` 是 V2 框架统一令牌，widget 不允许再写裸字号/裸间距。
## 绘制原语统一接收 `ci: CanvasItem`，调用者必须在 ci 自己的 `_draw()` 调用栈内调用
## （Godot 只允许在节点自己的 _draw / draw 信号里绘制）。

const Palette := preload("res://scripts/pal.gd")
const Fonts := preload("res://scripts/fonts.gd")

# ── 颜色令牌（复用 pal.gd）────────────────────────────────────────────────
static var BG := Palette.BG
static var EARTH := Palette.EARTH
static var BEZEL := Palette.BEZEL
static var PANEL := Palette.PANEL
static var PANEL2 := Palette.PANEL2
static var LINE := Palette.LINE
static var LINE2 := Palette.LINE2
static var PH := Palette.PH
static var PH_DIM := Palette.PH_DIM
static var PH_FAINT := Palette.PH_FAINT
static var AMBER := Palette.AMBER
static var RED := Palette.RED
static var BLUE := Palette.BLUE
static var TXT := Palette.TXT
static var DIM := Palette.DIM
static var FAINT := Palette.FAINT
static var GRID := Palette.GRID

# 身份分类色（19 §2.5；颜色之外还有形状，色盲友好）
static var ID_PENDING := Palette.ID_PENDING
static var ID_UNKNOWN := Palette.ID_UNKNOWN
static var ID_ASSUMED := Palette.ID_ASSUMED
static var ID_FRIEND := Palette.ID_FRIEND
static var ID_NEUTRAL := Palette.ID_NEUTRAL
static var ID_SUSPECT := Palette.ID_SUSPECT
static var ID_HOSTILE := Palette.ID_HOSTILE

# 威胁色
static var THR_NONE := Palette.THR_NONE
static var THR_LOW := Palette.THR_LOW
static var THR_MED := Palette.THR_MED
static var THR_HIGH := Palette.THR_HIGH
static var THR_HOSTILE := Palette.THR_HOSTILE
static var THR_PENDING := Palette.THR_PENDING

# ── 字号令牌（V1.5 连续档，不改断行习惯）─────────────────────────────────
const F7 := 7
const F8 := 8
const F9 := 9
const F10 := 10
const F11 := 11
const F12 := 12
const F13 := 13
const F16 := 16
const F18 := 18
const F20 := 20
const F22 := 22
const F24 := 24
const F26 := 26

# ── 间距令牌（4px 基础格 / 8px 节奏格）────────────────────────────────────
const S2 := 2
const S4 := 4
const S8 := 8
const S12 := 12
const S16 := 16
const S24 := 24
const S32 := 32
const S40 := 40

# ── 行高 / 控件高度令牌 ──────────────────────────────────────────────────
const ROW_CONTACT := 62.0
const ROW_LOG := 34.0
const ROW_SECTION := 18.0
const ROW_MENU := 24.0
const HEADER_H := 44.0
const SECTION_HEADER_H := 22.0
const MENU_GROUP_H := 18.0
const MENU_HEADER_H := 58.0
const MENU_FOOTER_H := 26.0
const MENU_W := 420.0
const SCROLLBAR_W := 6.0

# ── 透明度令牌 ───────────────────────────────────────────────────────────
const A_PANEL := 0.96
const A_PANEL2 := 0.92
const A_LINE := 0.85
const A_DIM := 0.72
const A_FAINT := 0.55

# ══ 颜色语义 ═════════════════════════════════════════════════════════════

static func a(c: Color, alpha: float) -> Color:
	return Palette.a(c, alpha)


## 阵营 accent：己方薄荷绿 / 敌方朱红 / 中立冰蓝 / 未知琥珀。
static func side_color(side: String) -> Color:
	match side:
		"friend":
			return PH
		"hostile":
			return RED
		"neutral":
			return BLUE
		_:
			return AMBER


## 选中实体 accent：己方基准舰单独走薄荷绿，其余按阵营。
static func accent_for(vm: Dictionary) -> Color:
	if vm.is_empty():
		return PH
	if bool(vm.get("is_own", false)) or ("own" in (vm.get("tags", []) as Array)):
		return PH
	return side_color(String(vm.get("side", "unknown")))


static func identity_color(identity: String) -> Color:
	match identity:
		"pending":
			return ID_PENDING
		"unknown":
			return ID_UNKNOWN
		"assumed_friend":
			return ID_ASSUMED
		"friend":
			return ID_FRIEND
		"neutral":
			return ID_NEUTRAL
		"suspect":
			return ID_SUSPECT
		"hostile":
			return ID_HOSTILE
		_:
			return ID_PENDING


static func threat_color(threat: String) -> Color:
	match threat:
		"none":
			return THR_NONE
		"low":
			return THR_LOW
		"med", "medium":
			return THR_MED
		"high":
			return THR_HIGH
		"hostile":
			return THR_HOSTILE
		_:
			return THR_PENDING


static func kind_color(kind: String) -> Color:
	match kind:
		"ship":
			return PH
		"station":
			return BLUE
		"tank":
			return AMBER
		"wreck":
			return FAINT
		_:
			return FAINT


# ══ 中文/英文标签 ════════════════════════════════════════════════════════

static func identity_label(identity: String) -> String:
	match identity:
		"pending":
			return "待定"
		"unknown":
			return "未知"
		"assumed_friend":
			return "假定友好"
		"friend":
			return "友方"
		"neutral":
			return "中立"
		"suspect":
			return "可疑"
		"hostile":
			return "敌方"
		_:
			return "待定"


static func identity_short(identity: String) -> String:
	match identity:
		"pending":
			return "PEND"
		"unknown":
			return "UNKN"
		"assumed_friend":
			return "ASSUM"
		"friend":
			return "FRIEND"
		"neutral":
			return "NEUT"
		"suspect":
			return "SUSP"
		"hostile":
			return "HOST"
		_:
			return "PEND"


static func side_label(side: String) -> String:
	match side:
		"friend":
			return "友方"
		"hostile":
			return "敌方"
		"neutral":
			return "中立"
		_:
			return "未知"


static func kind_label(kind: String) -> String:
	match kind:
		"ship":
			return "舰船"
		"station":
			return "站点"
		"tank":
			return "储罐"
		"wreck":
			return "残骸"
		"unknown":
			return "未分类"
		_:
			return String(kind)


static func level_name(level: int) -> String:
	return ["L0", "L1", "L2", "L3", "L4"][clampi(level, 0, 4)]


static func level_desc(level: int) -> String:
	match clampi(level, 0, 4):
		0:
			return "未成航迹"
		1:
			return "方位 / BEARING"
		2:
			return "位置 / POSITION"
		3:
			return "分类 / CLASSIFIED"
		_:
			return "识别 / IDENTIFIED"


# ══ 字体 / 文本 ══════════════════════════════════════════════════════════

static func font_cjk() -> Font:
	return Fonts.cjk()


static func font_mono() -> Font:
	return Fonts.mono()


static func has_cjk(s: String) -> bool:
	return Fonts.has_cjk(s)


static func font_for(s: String) -> Font:
	return Fonts.cjk() if Fonts.has_cjk(s) else Fonts.mono()


static func text_w(s: String, sz: int, cjk := true) -> float:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


static func ellipsis(s: String, sz: int, max_w: float, cjk := true) -> String:
	if max_w <= 0.0 or s == "":
		return ""
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= max_w:
		return s
	var dots := "…"
	var dw := f.get_string_size(dots, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var out := ""
	var acc := 0.0
	for i in s.length():
		var ch := s.substr(i, 1)
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if acc + w + dw > max_w:
			break
		out += ch
		acc += w
	return out + dots


## y 为文本顶边（不是基线），与 v15 hud `_txt` 语义一致。
static func text(ci: CanvasItem, x: float, y: float, s: String, sz: int, col: Color, cjk := true) -> void:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	ci.draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


static func text_r(ci: CanvasItem, xr: float, y: float, s: String, sz: int, col: Color, cjk := true) -> void:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	ci.draw_string(f, Vector2(xr - w, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


static func text_c(ci: CanvasItem, cx: float, y: float, s: String, sz: int, col: Color, cjk := true) -> void:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	ci.draw_string(f, Vector2(cx - w * 0.5, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## y 为基线（baseline），用于同一行不同字号对齐。
static func text_baseline(ci: CanvasItem, x: float, baseline_y: float, s: String, sz: int, col: Color, cjk := true) -> void:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	ci.draw_string(f, Vector2(x, baseline_y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


static func text_baseline_r(ci: CanvasItem, xr: float, baseline_y: float, s: String, sz: int, col: Color, cjk := true) -> void:
	var f: Font = Fonts.cjk() if cjk else Fonts.mono()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	ci.draw_string(f, Vector2(xr - w, baseline_y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## 左对齐 + 右侧裁掉（用省略号），返回实际绘制的字符串。
static func text_fit(ci: CanvasItem, x: float, y: float, s: String, sz: int, col: Color, max_w: float, cjk := true) -> String:
	var out := ellipsis(s, sz, max_w, cjk)
	text(ci, x, y, out, sz, col, cjk)
	return out


## 右对齐 + 左侧裁掉（用省略号）。
static func text_fit_r(ci: CanvasItem, xr: float, y: float, s: String, sz: int, col: Color, max_w: float, cjk := true) -> String:
	var out := ellipsis(s, sz, max_w, cjk)
	text_r(ci, xr, y, out, sz, col, cjk)
	return out


# ══ 图形原语 ═════════════════════════════════════════════════════════════

static func panel(ci: CanvasItem, r: Rect2, fill_a := A_PANEL, border_a := A_LINE) -> void:
	ci.draw_rect(r, a(PANEL, fill_a))
	ci.draw_rect(r, a(LINE, border_a), false, 1.0)


static func panel2(ci: CanvasItem, r: Rect2, fill_a := A_PANEL2, border_a := A_LINE) -> void:
	ci.draw_rect(r, a(PANEL2, fill_a))
	ci.draw_rect(r, a(LINE, border_a), false, 1.0)


static func frame(ci: CanvasItem, r: Rect2, col: Color, alpha := 0.8, width := 1.0) -> void:
	ci.draw_rect(r, a(col, alpha), false, width)


static func corners(ci: CanvasItem, r: Rect2, l: float, col: Color, alpha := 0.75) -> void:
	var c := a(col, alpha)
	ci.draw_line(r.position, r.position + Vector2(l, 0), c, 1.0)
	ci.draw_line(r.position, r.position + Vector2(0, l), c, 1.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), c, 1.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), c, 1.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), c, 1.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), c, 1.0)
	ci.draw_line(r.end, r.end - Vector2(l, 0), c, 1.0)
	ci.draw_line(r.end, r.end - Vector2(0, l), c, 1.0)


static func hline(ci: CanvasItem, x1: float, y: float, x2: float, col: Color) -> void:
	ci.draw_line(Vector2(x1, y), Vector2(x2, y), col, 1.0)


static func vline(ci: CanvasItem, x: float, y1: float, y2: float, col: Color) -> void:
	ci.draw_line(Vector2(x, y1), Vector2(x, y2), col, 1.0)


static func chip(ci: CanvasItem, r: Rect2, label: String, col: Color, active := true, sz := F7) -> void:
	ci.draw_rect(r, a(col, 0.08 if active else 0.02))
	ci.draw_rect(r, a(col, 0.42 if active else 0.18), false, 1.0)
	text(ci, r.position.x + 5.0, r.position.y + (r.size.y - float(sz) - 2.0) * 0.5,
		label, sz, a(col, 0.94 if active else 0.42), has_cjk(label))


static func badge(ci: CanvasItem, r: Rect2, label: String, col: Color, sz := F7) -> void:
	ci.draw_rect(r, a(col, 0.09))
	ci.draw_rect(r, a(col, 0.48), false, 1.0)
	var f: Font = Fonts.mono()
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var baseline := r.position.y + (r.size.y + f.get_ascent(sz) - f.get_descent(sz)) * 0.5
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - w) * 0.5, baseline),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, a(col, 0.92))


static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	ci.draw_rect(r, a(LINE, 0.45))
	var n := 10
	var gap := 1.0
	var w := (r.size.x - gap * float(n - 1)) / float(n)
	var filled := int(round(clampf(frac, 0.0, 1.0) * float(n)))
	for i in range(n):
		var x := r.position.x + float(i) * (w + gap)
		ci.draw_rect(Rect2(x, r.position.y, w, r.size.y), col if i < filled else a(LINE, 0.9))


## 身份符号：颜色 + 形状双编码（19 §2.5）。
static func identity_glyph(ci: CanvasItem, c: Vector2, radius: float, identity: String, col: Color) -> void:
	match identity:
		"friend":
			ci.draw_arc(c, radius, 0.0, TAU, 20, col, 1.4, true)
		"hostile":
			var p := PackedVector2Array([
				c + Vector2(0, -radius), c + Vector2(radius, radius),
				c + Vector2(-radius, radius), c + Vector2(0, -radius),
			])
			ci.draw_polyline(p, col, 1.4, true)
		"neutral":
			ci.draw_rect(Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2.0), col, false, 1.3)
		"unknown":
			var q := PackedVector2Array([
				c + Vector2(0, -radius), c + Vector2(radius, 0),
				c + Vector2(0, radius), c + Vector2(-radius, 0), c + Vector2(0, -radius),
			])
			ci.draw_polyline(q, col, 1.3, true)
		"assumed_friend":
			var p2 := PackedVector2Array()
			for i in range(6):
				var ang := TAU * float(i) / 6.0 - PI * 0.5
				p2.append(c + Vector2(cos(ang), sin(ang)) * radius)
			p2.append(p2[0])
			ci.draw_polyline(p2, col, 1.3, true)
		"suspect":
			var p3 := PackedVector2Array([
				c + Vector2(-radius, radius), c + Vector2(0, -radius),
				c + Vector2(radius, radius), c + Vector2(-radius, radius),
			])
			ci.draw_polyline(p3, col, 1.3, true)
		_:
			ci.draw_arc(c, radius * 0.9, 0.0, TAU, 16, col, 1.2, true)
			ci.draw_line(c + Vector2(-radius, 0), c + Vector2(radius, 0), col, 1.0)


# ══ 数值格式 ═════════════════════════════════════════════════════════════

static func hms(seconds: float) -> String:
	var t := int(seconds)
	return "%02d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, t % 60]


static func mmss(seconds: float) -> String:
	var t := int(seconds)
	return "%02d:%02d" % [int(t / 60.0) % 60, t % 60]


static func fmt_int(n: int) -> String:
	var raw := str(absi(n))
	var out := ""
	for i in range(raw.length()):
		if i > 0 and (raw.length() - i) % 3 == 0:
			out += ","
		out += raw.substr(i, 1)
	return ("-" if n < 0 else "") + out


static func num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		return float(String(v).replace(",", ""))
	return 0.0


## 3 维向量 → "x, y, z"（1 位小数；缺失显示 —）
static func vec3(v: Variant) -> String:
	if v is Array:
		var arr: Array = v
		if arr.size() >= 3:
			return "%.1f, %.1f, %.1f" % [num(arr[0]), num(arr[1]), num(arr[2])]
		if arr.size() == 2:
			return "%.1f, %.1f" % [num(arr[0]), num(arr[1])]
	if v is Vector3:
		var v3: Vector3 = v
		return "%.1f, %.1f, %.1f" % [v3.x, v3.y, v3.z]
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("r"):
			return vec3(d.get("r"))
	return "—"


static func clamp_rect_inside(r: Rect2, bounds: Rect2) -> Rect2:
	var out := r
	if out.size.x > bounds.size.x:
		out.size.x = bounds.size.x
	if out.size.y > bounds.size.y:
		out.size.y = bounds.size.y
	out.position.x = clampf(out.position.x, bounds.position.x, bounds.position.x + bounds.size.x - out.size.x)
	out.position.y = clampf(out.position.y, bounds.position.y, bounds.position.y + bounds.size.y - out.size.y)
	return out
