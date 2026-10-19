extends RefCounted

## V2 布局基线（layout）。
##
## 设计基线固定 **1920×1080（16:9）**。渲染缩放交给引擎：
## `project.godot` 已配 `window/stretch/mode="canvas_items"` + `aspect="keep"`，
## 因此所有 Control 的坐标、鼠标 `_gui_input` 坐标都直接是 1920×1080 设计坐标，
## 窗口放大/缩小/超宽/竖屏时由引擎做等比 letterbox，点击不会错位。
##
## 本文件仍提供一套独立的窗口像素 ↔ 设计坐标映射（与引擎 keep 公式一致），用于：
## 1. 纯窗口级事件（`DisplayServer` / 外部工具拿到物理像素时）；
## 2. 自检：把设计点映射到窗口再映射回来，验证任意窗口尺寸下误差 < 0.001px；
## 3. 屏幕上「布局自检」面板与 headless probe 输出的证据。
##
## 依赖方向：ui/widgets → ui/layout → 无（不依赖 core）。

const DESIGN := Vector2(1920.0, 1080.0)
const DESIGN_I := Vector2i(1920, 1080)
const ASPECT := 16.0 / 9.0
const BEZEL := 40.0
const BG_MARGIN := 20.0
const GUTTER := 16.0

# ── 四区（V2 框架演示屏；4/8px 网格）──────────────────────────────────────
# 左读 / 中看 / 右算 / 下事件与动作。
const SAFE := Rect2(40.0, 40.0, 1840.0, 1000.0)          # 机箱安全区
const TOP := Rect2(40.0, 40.0, 1840.0, 72.0)             # 顶栏 40..112
const CONTENT_Y := 124.0                                  # 内容区上沿
const CONTENT_BOTTOM := 876.0                             # 内容区下沿
const LEFT := Rect2(60.0, 124.0, 360.0, 752.0)           # 左栏：动态接触列表
const MAP := Rect2(436.0, 124.0, 1088.0, 752.0)          # 中区：战术占位
const RIGHT := Rect2(1540.0, 124.0, 320.0, 752.0)        # 右栏：section
const BOTTOM_Y := 884.0
const LOG := Rect2(60.0, 884.0, 700.0, 156.0)            # 下左：事件/命令列表
const ACTIONS := Rect2(776.0, 884.0, 540.0, 156.0)       # 下中：动作按钮菜单
const PROBE := Rect2(1332.0, 884.0, 528.0, 156.0)        # 下右：框架自检/视图状态

# 布局自检用的采样窗口尺寸（16:9 / 超宽 / 方屏 / 竖屏 / 4K）
const PROBE_SIZES := [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
	Vector2i(3440, 1440),
	Vector2i(1200, 800),
	Vector2i(1024, 1200),
]

const EPS := 0.001


# ══ 窗口像素 ↔ 设计坐标（与引擎 stretch keep 同公式）══════════════════════

## 窗口内实际绘制设计基线的矩形（letterbox：黑边在上下或左右）。
static func letterbox(window_size: Vector2i) -> Rect2:
	var w := Vector2(window_size)
	if w.x < 2.0 or w.y < 2.0:
		w = DESIGN
	var sc := minf(w.x / DESIGN.x, w.y / DESIGN.y)
	var s := DESIGN * sc
	return Rect2((w - s) * 0.5, s)


## 缩放系数：设计 1px → 窗口多少物理像素。
static func fit_scale(window_size: Vector2i) -> float:
	return letterbox(window_size).size.x / DESIGN.x


static func window_to_design(p_window: Vector2, window_size: Vector2i) -> Vector2:
	var r := letterbox(window_size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return p_window
	return (p_window - r.position) * (DESIGN / r.size)


static func design_to_window(p_design: Vector2, window_size: Vector2i) -> Vector2:
	var r := letterbox(window_size)
	return r.position + p_design * (r.size / DESIGN)


static func design_rect_to_window(r_design: Rect2, window_size: Vector2i) -> Rect2:
	var lb := letterbox(window_size)
	var sc := lb.size / DESIGN
	return Rect2(lb.position + r_design.position * sc, r_design.size * sc)


## 该窗口像素点是否落在 16:9 有效画面内（letterbox 黑边不接收点击）。
static func in_letterbox(p_window: Vector2, window_size: Vector2i) -> bool:
	var r := letterbox(window_size)
	return r.has_point(p_window)


## 物理窗口点 → 设计点，并判定是否在 letterbox 黑边内。
static func hit_window(p_window: Vector2, window_size: Vector2i) -> Dictionary:
	var r := letterbox(window_size)
	return {
		"inside": r.has_point(p_window),
		"design": window_to_design(p_window, window_size),
		"scale": r.size.x / DESIGN.x,
	}


# ══ 设计坐标内的区域命中（右键/调试用）══════════════════════════════════

static func hit_zone(p: Vector2) -> String:
	if TOP.has_point(p):
		return "top"
	if LEFT.has_point(p):
		return "left"
	if MAP.has_point(p):
		return "map"
	if RIGHT.has_point(p):
		return "right"
	if LOG.has_point(p):
		return "log"
	if ACTIONS.has_point(p):
		return "actions"
	if PROBE.has_point(p):
		return "probe"
	return "footer" if p.y > CONTENT_BOTTOM else "none"


static func zones() -> Array:
	return [
		{"id": "top", "rect": TOP},
		{"id": "left", "rect": LEFT},
		{"id": "map", "rect": MAP},
		{"id": "right", "rect": RIGHT},
		{"id": "log", "rect": LOG},
		{"id": "actions", "rect": ACTIONS},
		{"id": "probe", "rect": PROBE},
	]


# ══ 自检 ═════════════════════════════════════════════════════════════════

## 对一个窗口尺寸做映射往返自检，返回可打印/可绘制的证据字典。
static func probe(window_size: Vector2i) -> Dictionary:
	var lb := letterbox(window_size)
	var sc := lb.size.x / DESIGN.x
	var rows: Array = []
	var max_err := 0.0
	var samples := [
		Vector2(0.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(DESIGN.x * 0.5, DESIGN.y * 0.5),
		Vector2(DESIGN.x - 1.0, DESIGN.y - 1.0),
		Vector2(DESIGN.x, DESIGN.y),
	]
	for raw_p in samples:
		var p: Vector2 = raw_p
		var pw := design_to_window(p, window_size)
		var back := window_to_design(pw, window_size)
		var err := p.distance_to(back)
		max_err = maxf(max_err, err)
		rows.append({
			"design": p,
			"window": pw,
			"back": back,
			"err": err,
			"inside": in_letterbox(pw, window_size),
		})
	var bars := {
		"left": lb.position.x,
		"top": lb.position.y,
		"right": Vector2(window_size).x - lb.end.x,
		"bottom": Vector2(window_size).y - lb.end.y,
	}
	var has_bars := maxf(maxf(bars.left, bars.top), maxf(bars.right, bars.bottom)) > 0.5
	var corner_ok := (
		design_to_window(Vector2.ZERO, window_size).distance_to(lb.position) < EPS
		and design_to_window(DESIGN, window_size).distance_to(lb.end) < EPS
	)
	var center_ok := in_letterbox(design_to_window(Vector2(DESIGN.x * 0.5, DESIGN.y * 0.5), window_size), window_size)
	var bars_ok := true
	if has_bars:
		bars_ok = not in_letterbox(Vector2(0.5, 0.5), window_size)
	return {
		"window": window_size,
		"letterbox": lb,
		"scale": sc,
		"rows": rows,
		"max_err": max_err,
		"bars": bars,
		"has_bars": has_bars,
		"ok": max_err < EPS and corner_ok and center_ok and bars_ok,
	}


static func probe_all(sizes: Array = PROBE_SIZES) -> Array:
	var out: Array = []
	for ws in sizes:
		out.append(probe(ws as Vector2i))
	return out


## 全量自检：任意窗口尺寸下，设计坐标 ↔ 窗口像素往返误差接近 0，
## 且 letterbox 黑边（若存在）不被判定为有效画面。
static func self_check() -> Dictionary:
	var fails: Array[String] = []
	var probes := probe_all()
	var max_err := 0.0
	for raw in probes:
		var pr: Dictionary = raw
		max_err = maxf(max_err, float(pr.get("max_err", 0.0)))
		if not bool(pr.get("ok", false)):
			fails.append("letterbox probe failed for window %s" % str(pr.get("window")))
	# 设计点必须映射到窗口有效画面内。
	for p in [Vector2(0, 0), Vector2(960, 540), Vector2(1919, 1079)]:
		for raw2 in probes:
			var ws: Vector2i = (raw2 as Dictionary).get("window", DESIGN_I)
			var pw := design_to_window(p, ws)
			if not in_letterbox(pw, ws):
				fails.append("design point %s outside letterbox for %s" % [str(p), str(ws)])
	# 面板必须落在安全区内且横向留 16px gutter。
	var rects := {
		"top": TOP, "left": LEFT, "map": MAP, "right": RIGHT,
		"log": LOG, "actions": ACTIONS, "probe": PROBE,
	}
	for rid in rects:
		var r: Rect2 = rects[rid]
		if not SAFE.encloses(r):
			fails.append("panel %s outside safe area" % rid)
	if absf(LEFT.end.x + GUTTER - MAP.position.x) > 0.5:
		fails.append("left/map gutter != 16")
	if absf(MAP.end.x + GUTTER - RIGHT.position.x) > 0.5:
		fails.append("map/right gutter != 16")
	if absf(LOG.end.x + GUTTER - ACTIONS.position.x) > 0.5:
		fails.append("log/actions gutter != 16")
	if absf(ACTIONS.end.x + GUTTER - PROBE.position.x) > 0.5:
		fails.append("actions/probe gutter != 16")
	return {
		"ok": fails.is_empty(),
		"fails": fails,
		"probes": probes,
		"max_err": max_err,
		"panels": rects,
	}


## 当前运行窗口的实测指标（给屏幕上的自检面板用）。
static func current_metrics(viewport_size: Vector2, window_size: Vector2i) -> Dictionary:
	var ws := window_size
	if ws.x < 2 or ws.y < 2:
		ws = Vector2i(int(viewport_size.x), int(viewport_size.y))
	var lb := letterbox(ws)
	return {
		"viewport": viewport_size,
		"window": ws,
		"scale": lb.size.x / DESIGN.x,
		"letterbox": lb,
		"bars": {
			"left": lb.position.x,
			"top": lb.position.y,
			"right": Vector2(ws).x - lb.end.x,
			"bottom": Vector2(ws).y - lb.end.y,
		},
	}
