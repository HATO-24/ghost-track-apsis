class_name Hud
extends Control

const Fonts := preload("res://scripts/fonts.gd")
const Palette := preload("res://scripts/pal.gd")

# ── 栅格与四区 ──────────────────────────────────────────
# 4px 基础格：所有矩形的位置 / 尺寸必须落在 4 的倍数上。
# 8px 节奏格：间距、行高、控件高度优先取 8 的倍数。
# 既有锚点例外（只落在 4 格，不改）：124 / 876 / 884 —— V1 版式与 main.gd 的 plot 已定。
const U := 4.0
const G := 8.0
const TOP := Rect2(40, 40, 1840, 72)
const TRACKS := Rect2(60, 124, 320, 752)
const UNIT := Rect2(1540, 124, 320, 752)
# P1e：底部「令」区拆成 日志 + 命令面板 两块（仍在同一横带内，4/8 网格不变）。
const LOG := Rect2(60, 884, 560, 156)
const CMD := Rect2(636, 884, 544, 156)
const TIME := Rect2(1200, 884, 660, 156)

# ── P1e：命令面板 / 点火规划（HUD 只读 state；授权才写命令）──
const CMD_ACTIONS := ["STATION", "SHADOW", "BURN"]
const CMD_LABELS := ["STATION 保持站位", "SHADOW 跟踪", "BURN 点火"]
const PLAN_WINDOW_S := 30.0                 # 点火时间轴窗口：T+0 … T+30 s
const CMD_INSET_X := 652.0
const CMD_INNER_R := 1164.0
const ACT_Y := 902.0                        # 动作按钮行 y
const ACT_H := 20.0
# 参数行（T+ / Δv / 方向），高 18
const T_MINUS := Rect2(676, 926, 20, 18)
const T_PLUS := Rect2(756, 926, 20, 18)
const DV_MINUS := Rect2(824, 926, 20, 18)
const DV_PLUS := Rect2(926, 926, 20, 18)
const DIR_CYCLE := Rect2(1104, 926, 60, 18)
# P1f：命令面板把「链路」与「机动」拆两行（y 946 / 954），时间轴下移收紧。
const TIMELINE := Rect2(652, 962, 512, 16)
# 授权 / 撤销 / 武器释放
const AUTH_BTN := Rect2(652, 980, 176, 20)
const ABORT_BTN := Rect2(836, 980, 176, 20)
const FIRE_BTN := Rect2(1020, 980, 144, 20)
const QUEUE_Y := 1012.0
const QUEUE_ROW_H := 12.0
const QUEUE_ABORT_X := 1120.0

# ── P1f：裁决 / 后果 / 报告覆盖层（居中面板，V1.5 仪表风）──
const DECISION_RECT := Rect2(480, 250, 960, 560)
const CONSEQ_RECT := Rect2(560, 300, 800, 440)
const REPORT_RECT := Rect2(440, 210, 1040, 660)
const FILED_RECT := Rect2(700, 468, 520, 120)
const DECISION_KINDS := ["certify", "article9", "stall"]
const DECISION_NAMES := ["认证交接 / CERTIFY", "援引第九条 / ARTICLE 9", "拖程序 / STALL"]
const DECISION_CONSEQ := [
	"按程序签字，储罐交给清算署 · 公约 +1 / 天市 −1 / 清算署 +1（第二幕港务冷淡）",
	"以「迫切且不可逆之损害」阻止交接 · 公约 −1 / 天市 +2 / 清算署 −2 / 永昼 +1（第二幕开场即审裁）",
	"要求文书复核，拖过执行窗口 · 天市 +1 短 / −1 长 · 清算署 −1（储罐可能断供）",
]
const DECISION_RUBRIC := ["回执 · 合法", "回执 · 越权", "回执 · 拖延"]
# 报告覆盖层按钮
const REPORT_TRUTH := Rect2(1056, 300, 396, 110)
const REPORT_FAKE := Rect2(1056, 424, 396, 110)
const CONSEQ_SUBMIT := Rect2(800, 660, 320, 40)

# 传感器条 / 下拉阵列（V2 结构，V1 薄荷语言）。
# 位置规则：水平锁在地图中轴（396 + 1128 / 2 = 960），垂直贴地图上沿 +12。
# 旧值 720 的中心是 900，既不在中轴也不在任何边缘上 —— 这就是"没对准"。
const MAP_CX := 960.0
const BAR_W := 360.0
const BAR_H := 28.0
const BAR_X := MAP_CX - BAR_W * 0.5
const SENSOR_RECT := Rect2(BAR_X, 136, BAR_W, BAR_H)
const MENU_HEAD := 28.0
# P1d：下拉不再是固定 6 项全局传感器，而是「选中舰的按舰架」——
# 行高 52（两行：型号 / 来源·厂商·类型·距离·刷新），高度随架子模块数变化。
const MENU_ROW := 52.0
const MENU_FOOT := 58.0
const MENU_FLASH := 0.14
const MENU_FRAME := 0.12
const MENU_QUAD_ORDER := [0, 1, 3, 2]
const MENU_QUAD_STEP := 0.06

# P1d：下拉的最终矩形 = header + N 行 + 暴露/等级 footer。
func _menu_rect() -> Rect2:
	var n := clampi(_rack_rows().size(), 1, 6)
	return Rect2(BAR_X, 168, BAR_W, MENU_HEAD + float(n) * MENU_ROW + MENU_FOOT)

# ── 显示名层（LORE-01 P0 审计）──────────────────────────
# 数据层（state.gd / 未来 scenario.json）还带旧名；UI 先做显示替换，
# **只改显示，不改 state**。数据层改名后删掉本表即可。
# 依据：docs/10_术语表.md §12（A-01/02/06/10/11/12/13/14/15/16/19/20/24/26）。
const DISPLAY_FIX := {
	"听-3": "明视 IR-9",
	"沙克尔顿租界": "永昼租界",
	"天平动": "天市",
	"长夜": "望楼",
	"塔级": "安海-1",
	"砧级": "托盘-5 改",
	"听级": "托盘-5 改",
	"代偿级": "传唤级",
	"传票级": "传唤级",
	"火力舰": "送达",
	"送达舰": "送达",
	"监督官分遣队": "AD 特遣群",
	"HAMADAN": "HARMATTAN",
	"LEEWARD": "LEE SHORE",
	"LONGNIGHT": "WATCHTOWER",
	"4471-K": "案卷 4471",
	"4503-R": "案卷 4503",
	"接管通知 4471 号": "接管通知 · 案卷 4471",
	# 12 军语 P0（显示层）：未识别是状态词，不能当实体名；火控/weapons free 的正式说法。
	"未识别": "不明接触",
	"火控请求": "火力请求",
	"weapons free": "武器释放授权",
	"WEAPONS FREE": "武器释放授权",
}

# ── P1d：按舰传感器架（只读 state.racks / sensor_on / fleet_emissions）──
# UI 只读，不写 state：ON/OFF 是占位显示（当前融合计划），开关由命令层决定。
func _rack_ship() -> String:
	var v = state.get("rack_ship")
	return String(v) if v != null else "harmattan"

func _rack_ship_name() -> String:
	var tr := _rack_track()
	if tr.is_empty():
		return "—"
	return _dn(String(tr.get("id", "—")))

func _rack_track() -> Dictionary:
	var idx := clampi(int(state.selected), 0, maxi(0, state.tracks.size() - 1))
	if idx >= 0 and idx < state.tracks.size():
		return state.tracks[idx]
	return {}

# 选中舰的完整传感器架：优先读 state.racks（含 maker / type / range_km / refresh_s / expose），
# 退化时读 state.sensors（HUD 视图，字段不全）。
func _rack_rows() -> Array:
	var racks = state.get("racks")
	if racks is Dictionary:
		var ship := _rack_ship()
		if (racks as Dictionary).has(ship):
			var rows: Array = []
			for raw in (racks as Dictionary)[ship]:
				rows.append((raw as Dictionary).duplicate())
			return rows
	var out: Array = []
	for s in state.sensors:
		out.append({
			"model": String(s.get("model", "—")), "source": String(s.get("mfr", "—")),
			"maker": "—", "type": "", "mode": String(s.get("mode", "")),
			"range_km": 0.0, "refresh_s": 0.0,
			"expose": bool(s.get("expose", false)), "on": bool(s.get("on", true)),
		})
	return out

# 当前融合计划里的开 / 关（只读；没有计划时退回架子默认值）
func _rack_on(ship: String, model: String, fallback: bool) -> bool:
	var so = state.get("sensor_on")
	if so is Dictionary and (so as Dictionary).has(ship):
		var m = (so as Dictionary)[ship]
		if m is Dictionary and (m as Dictionary).has(model):
			return bool((m as Dictionary)[model])
	return fallback

# 选中舰的暴露态：优先 state.fleet_emissions；不在融合编成里的船按架子自算。
func _rack_emission() -> Dictionary:
	var ship := _rack_ship()
	var fe = state.get("fleet_emissions")
	if fe is Array:
		for raw in (fe as Array):
			if raw is Dictionary and String((raw as Dictionary).get("ship_id", "")) == ship:
				return raw
	var ems: Array = []
	var exposed := false
	for s in _rack_rows():
		var model := String(s.get("model", ""))
		if not bool(s.get("expose", false)) or not _rack_on(ship, model, bool(s.get("on", true))):
			continue
		# 无线电 / 激光通信只在「正在发射」时计入暴露；融合层没有发射记录时不冒充暴露。
		var typ := String(s.get("type", ""))
		if typ == "radio" or typ == "lasercom":
			continue
		exposed = true
		ems.append({"model": model, "elint_range_km": float(s.get("range_km", 0.0))})
	return {"ship_id": ship, "emitters": ems, "exposed": exposed, "emcon": not exposed,
		"emission_level": 0.0, "warnings": []}

func _rack_glyph(t: String) -> String:
	match t:
		"ir":
			return "web"
		"radar":
			return "hex"
		"optical":
			return "frame"
		"iff":
			return "gate"
		"elint":
			return "jag"
		_:
			return "ring"

func _rack_color(t: String) -> Color:
	match t:
		"ir":
			return Palette.AMBER
		"radar", "iff":
			return Palette.PH
		"optical":
			return Palette.BLUE
		"elint":
			return Palette.RED
		_:
			return Palette.PH_DIM

func _rack_type_cn(s: Dictionary) -> String:
	var mode := String(s.get("mode", ""))
	if mode != "":
		return mode
	match String(s.get("type", "")):
		"ir":
			return "被动红外"
		"radar":
			return "主动雷达"
		"optical":
			return "光学"
		"iff":
			return "敌我识别"
		"elint":
			return "通信截听"
		"radio":
			return "无线电"
		"lasercom":
			return "激光通信"
		_:
			return "—"

func _level_desc(lv: int) -> String:
	match lv:
		0:
			return "无接触"
		1:
			return "仅方位"
		2:
			return "定位 / 无舰种"
		3:
			return "舰级分类"
		4:
			return "具体识别"
		_:
			return "—"

func _ellipsis(f: Font, s: String, sz: int, max_w: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= max_w:
		return s
	var out := s
	while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w:
		out = out.substr(0, out.length() - 1)
	return out + "…"

func _dn(s: String) -> String:
	var out := s
	for k in DISPLAY_FIX:
		out = out.replace(k, DISPLAY_FIX[k])
	return out

var state
var mono: Font
var cjk: Font
var row_rects: Array[Rect2] = []
var time_rects: Array[Rect2] = []
var menu_rects: Array[Rect2] = []
var menu_open := false
var menu_t := 0.0
var _t := 0.0

# P1e 命令面板（本地 draft；授权前不写 state）
var cmd_action := "BURN"
var draft_t := 6.2
var draft_dv := 84.0
var draft_dir := 0
const DIR_PRESETS := [
	{"label": "BRG 340 · ELEV +20", "brg": 340.0, "elev": 20.0},
	{"label": "顺行 000 · ELEV 0", "brg": 0.0, "elev": 0.0},
	{"label": "逆行 180 · ELEV 0", "brg": 180.0, "elev": 0.0},
	{"label": "法向 000 · ELEV +90", "brg": 0.0, "elev": 90.0},
]
var _burn_drag := false
var _preview_dirty := false
var _queue_abort: Array = []          # [{rect: Rect2, id: String}]（每帧重建）

# P1f：覆盖层 / 武器释放（优先读 state 字段；缺失时用 DSH_UI 的本地演示态）
var _demo_decision := false
var _demo_consequence := false
var _demo_report := false
var _decision_done := false
var _fire_confirm_t := 0.0
var _filed_text := ""
var _filed_col := Color(1, 1, 1, 1)
var _filed_t := 0.0
var _key_prev: Dictionary = {}
const FILED_MOCK := ""

func _ready() -> void:
	mono = Fonts.mono()
	cjk = Fonts.cjk()
	# 截图/调试用：DSH_SELECT=n 选中第 n 条接触（只动 HUD 的选中索引，不改 sim 状态）。
	var ds := OS.get_environment("DSH_SELECT")
	if ds != "" and state != null and state.tracks.size() > 0:
		state.selected = clampi(int(ds), 0, state.tracks.size() - 1)
	# P1e：默认 draft（BURN T+6.2 / Δv 84 / BRG340）镜像给 sim 的 preview，供 plot 画 DRAFT 节点。
	_push_preview()
	# P1f 截图/调试钩子：DSH_UI=decision|consequence|report 打开对应覆盖层。
	# state 侧字段（decision_open / …）一旦存在，以 state 为准；这里只是 HUD 本地演示。
	match OS.get_environment("DSH_UI"):
		"decision":
			_demo_decision = true
		"consequence":
			_demo_consequence = true
		"report":
			_demo_report = true

func _process(delta: float) -> void:
	_t += delta
	if menu_open:
		menu_t += delta
	if _fire_confirm_t > 0.0:
		_fire_confirm_t = maxf(0.0, _fire_confirm_t - delta)
	if _filed_t > 0.0:
		_filed_t = maxf(0.0, _filed_t - delta)
	# P1f：覆盖层键盘交给 main.gd（P1f-SIM 已在 _unhandled_input 里处理 1/2/3/F/E），
	# HUD 只负责画与鼠标点击，避免一次按键触发两次命令。
	# P1e：点火节点拖动（只改本地 draft，不写 state）。
	# main.gd 只把鼠标按下转发给 hud.click()，所以这里轮询鼠标位置 / 松开。
	if _burn_drag:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_burn_drag = false
		else:
			var win := get_window()
			if win != null and win.size.x > 1:
				var mp := win.get_mouse_position()
				var p: Vector2 = mp * (Vector2(1920.0, 1080.0) / Vector2(win.size))
				_set_burn_from_x(p.x)
				_push_preview()

func _draw() -> void:
	if state.boot_t < 1.7:
		_draw_boot()
		return
	_draw_bezel()
	_draw_top()
	_draw_tracks()
	_draw_unit()
	_draw_log()
	_draw_command_panel()
	_draw_time()
	_draw_sensor_bar()
	if menu_open:
		_draw_sensor_menu()
	_draw_screen_edge()
	# P1f：覆盖层画在最上层（含 dim），裁决/后果/报告 + 归档结果条。
	if _ov_report():
		_draw_report_overlay()
	elif _ov_consequence():
		_draw_consequence_overlay()
	elif _ov_decision():
		_draw_decision_overlay()
	if _filed_t > 0.0:
		_draw_filed_banner()

func click(p: Vector2) -> void:
	if state.boot_t < 1.7:
		return
	# P1f：覆盖层吃掉一切点击。
	if _any_overlay():
		_handle_overlay_click(p)
		queue_redraw()
		return
	# P1e：命令面板优先（面板内的点击不再落到接触列表/时标/地图）。
	if CMD.has_point(p):
		_handle_command_click(p)
		if _preview_dirty:
			_push_preview()
			_preview_dirty = false
		queue_redraw()
		return
	if SENSOR_RECT.has_point(p):
		menu_open = not menu_open
		menu_t = 0.0
		queue_redraw()
		return
	if menu_open:
		for i in range(menu_rects.size()):
			if menu_rects[i].has_point(p):
				state.sensor = i
				state.sensor_fx_t = 0.0
				menu_open = false
				queue_redraw()
				return
		if not _menu_rect().has_point(p):
			menu_open = false
			queue_redraw()
			return
	for i in row_rects.size():
		if row_rects[i].has_point(p):
			state.selected = i
			queue_redraw()
			return
	for i in time_rects.size():
		if time_rects[i].has_point(p):
			state.time_scale = [1.0, 10.0, 60.0, 300.0][i]
			state.paused = false
			queue_redraw()
			return

func consumes(p: Vector2) -> bool:
	# P1f：覆盖层打开时吞掉所有指针输入（防止点穿到地图/面板）。
	if _any_overlay():
		return true
	if CMD.has_point(p):
		return true
	if SENSOR_RECT.has_point(p):
		return true
	if menu_open:
		if _menu_rect().has_point(p):
			return true
		for r in menu_rects:
			if r.has_point(p):
				return true
	for r in row_rects:
		if r.has_point(p):
			return true
	for r in time_rects:
		if r.has_point(p):
			return true
	return false

func _draw_bezel() -> void:
	draw_rect(Rect2(0, 0, 1920, 40), Palette.BEZEL)
	draw_rect(Rect2(0, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(1880, 0, 40, 1080), Palette.BEZEL)
	draw_rect(Rect2(0, 1040, 1920, 40), Palette.BEZEL)
	draw_line(Vector2(0, 1), Vector2(1920, 1), Palette.a(Palette.TXT, 0.035), 1.0)
	draw_line(Vector2(1, 0), Vector2(1, 1080), Palette.a(Palette.TXT, 0.025), 1.0)
	draw_line(Vector2(0, 1078), Vector2(1920, 1078), Color(0, 0, 0, 0.55), 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for i in 240:
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
		draw_rect(Rect2(x, y, 1, 1), Palette.a(Palette.TXT, rng.randf_range(0.010, 0.030)))

	_screw(Vector2(20, 20))
	_screw(Vector2(1900, 20))
	_screw(Vector2(20, 1060))
	_screw(Vector2(1900, 1060))

	_txt(mono, 56, 11, "CS-9", 9, Palette.a(Palette.PH_DIM, 0.85))
	_txt(cjk, 56, 23, "战术显控台", 7, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, 1864, 1053, "TACTICAL DISPLAY UNIT · SER. 0447", 7, Palette.a(Palette.FAINT, 0.8))

	for i in range(3):
		var c := Palette.PH
		if i == 1:
			c = Palette.AMBER
		elif i == 2:
			c = Palette.RED
		var lp := Vector2(1802.0 + float(i) * 16.0, 20.0)
		draw_circle(lp, 2.6, Palette.a(c, 0.9))
		draw_circle(lp, 6.0, Palette.a(c, 0.08))

	for i in range(36):
		var bx := 60.0 + float(i) * 3.0
		var bh := 7.0 + float((i * 7) % 7)
		draw_rect(Rect2(bx, 1064.0 - bh, 1.0, bh), Palette.a(Palette.FAINT, 0.32))

func _screw(p: Vector2) -> void:
	draw_circle(p, 5.5, Color("#050606"))
	draw_arc(p, 5.5, 0, TAU, 24, Color("#232A27"), 1.0, true)
	draw_line(p + Vector2(-3, -1), p + Vector2(3, 1), Color("#1A201D"), 1.0)

func _draw_top() -> void:
	draw_rect(TOP, Palette.a(Palette.BG, 0.55))
	draw_line(Vector2(40, 112), Vector2(1880, 112), Palette.a(Palette.LINE, 0.95), 1.0)

	_txt(cjk, 60, 47, "监督官席 / SUPERVISOR", 7, Palette.FAINT)
	var total := int(state.clock)
	var hh := int(total / 3600.0)
	var mm := int(total / 60.0) % 60
	var ss := total % 60
	var clock_s := "T+%02d:%02d:%02d" % [hh, mm, ss]
	_txt(mono, 60, 57, clock_s, 26, Palette.PH)
	var cw := mono.get_string_size(clock_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var tenth := int(fmod(float(state.clock), 1.0) * 10.0)
	_txt(mono, 60.0 + cw + 2.0, 70, ".%d" % tenth, 13, Palette.a(Palette.PH, 0.55))
	_txt(cjk, 60, 92, "任务时间 / MISSION ELAPSED", 7, Palette.FAINT)

	draw_line(Vector2(520, 50), Vector2(520, 102), Palette.a(Palette.LINE, 0.7), 1.0)

	# 07 §4：第一关顶栏是「接管通知 · 案卷 4471」，主计时是 6 分钟执行窗口；
	# 主裁定的 216 h 宽限期另算，不压在这一关上。窗口剩余由 state.exec_left 提供。
	var exec_left := 360.0
	var exec_v = state.get("exec_left")
	if exec_v != null:
		exec_left = clampf(float(exec_v), 0.0, 360.0)
	_txt(cjk, 548, 47, "接管通知 · 案卷 4471 / RECEIVERSHIP NOTICE", 7, Palette.a(Palette.AMBER, 0.72))
	_txt(cjk, 548, 66, "执行窗口", 9, Palette.DIM)
	_txt(mono, 626, 56, _hms(exec_left), 24, Palette.AMBER)
	draw_rect(Rect2(548, 96, 420, 1), Palette.a(Palette.AMBER, 0.16))
	draw_rect(Rect2(548, 96, 420.0 * exec_left / 360.0, 1), Palette.AMBER)
	_txt_r(cjk, 968, 87, "EXECUTION WINDOW · 216 h 宽限期另算", 7, Palette.a(Palette.AMBER, 0.45))

	draw_line(Vector2(1288, 50), Vector2(1288, 102), Palette.a(Palette.LINE, 0.7), 1.0)

	_txt(cjk, 1300, 47, "链路 / LINK", 7, Palette.FAINT)
	_txt(mono, 1300, 58, "LASER 0.4s", 11, Palette.PH)
	for i in range(4):
		draw_rect(Rect2(1300.0 + float(i) * 10.0, 92, 7, 3), Palette.a(Palette.PH, 0.70 if i < 3 else 0.14))

	_txt(cjk, 1440, 47, "时标 / TIMESCALE", 7, Palette.FAINT)
	_txt(mono, 1440, 58, "×%d" % int(state.time_scale), 18, Palette.PH)
	_txt(cjk, 1440, 92, "AUTO-SLOW 开", 7, Palette.AMBER)

	_txt(cjk, 1580, 47, "编队 Δv", 7, Palette.FAINT)
	_txt(mono, 1580, 58, _fmt_int(int(state.fleet_dv)), 18, Palette.PH)
	_txt(mono, 1652, 64, "m/s", 8, Palette.DIM)
	_txt(cjk, 1580, 92, "剩余 72%", 7, Palette.FAINT)

	# 12 军语 P0-4/P0-5：同一行 ROE 不再用一个 HOLD 混三种含义；
	# 顶栏 = 仅自卫（不得首先开火），日志的暂缓另用「暂缓执行」。
	_txt(cjk, 1720, 47, "交战规则 / ROE", 7, Palette.FAINT)
	_txt(cjk, 1720, 57, "仅自卫", 12, Palette.AMBER)
	_txt(cjk, 1720, 80, "WEAPONS HOLD", 7, Palette.a(Palette.AMBER, 0.75))
	_txt(cjk, 1720, 92, "不得首先开火", 7, Palette.DIM)

func _draw_tracks() -> void:
	_panel(TRACKS)
	# 12 军语 P0-2：TRACKS = 航迹；本面板是接触列表，所以中文取「接触」、英文取 CONTACTS。
	_txt(cjk, 76, 134, "接触 / CONTACTS", 11, Palette.TXT)
	_txt_r(mono, 364, 134, "%02d" % state.tracks.size(), 12, Palette.PH_DIM)
	_txt(cjk, 76, 153, "威胁排序 / THREAT ↓", 7, Palette.FAINT)
	draw_line(Vector2(60, 168), Vector2(380, 168), Palette.a(Palette.LINE, 0.9), 1.0)

	row_rects.clear()
	for i in range(state.tracks.size()):
		var y := 176.0 + float(i) * 80.0
		row_rects.append(Rect2(60, y, 320, 80))
		_draw_track_row(state.tracks[i], i, y)

	draw_line(Vector2(60, 824), Vector2(380, 824), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(cjk, 76, 832, "传感器 / SENSOR", 7, Palette.FAINT)
	_chip(Rect2(76, 848, 72, 16), "IR 被动", Palette.PH, true)
	_chip(Rect2(156, 848, 72, 16), "光学 8×", Palette.PH, true)
	_chip(Rect2(236, 848, 72, 16), "雷达 关", Palette.FAINT, false)

func _draw_track_row(t: Dictionary, i: int, y: float) -> void:
	var col := _side_color(t)
	var sel: bool = i == int(state.selected)
	if sel:
		draw_rect(Rect2(60, y, 320, 80), Palette.a(Palette.PANEL2, 0.95))
		draw_rect(Rect2(60, y, 2, 80), col)
		draw_rect(Rect2(60, y, 320, 1), Palette.a(col, 0.22))
	draw_line(Vector2(76, y + 79), Vector2(364, y + 79), Palette.a(Palette.LINE, 0.55), 1.0)

	var dim := 0.45 if t.get("stale", false) else 1.0
	var disp_id := _dn(t.id)
	var idf := cjk if Fonts.has_cjk(disp_id) else mono
	_txt(idf, 76, y + 12, disp_id, 13, Palette.a(col, dim))
	_txt(cjk, 160, y + 14, _dn(t.cls), 9, Palette.a(Palette.DIM, dim))
	_draw_level(344.0, y + 12.0, t, col)

	var line2 := ""
	if t.get("own", false):
		line2 = "基准 / REFERENCE"
	elif t.get("bearing_only", false):
		line2 = "方位 302° · 距离未知"
	else:
		line2 = "方位 %03d° · %d km" % [int(t.bearing), int(t.range)]
	_txt(mono, 76, y + 35, line2, 8, Palette.a(Palette.DIM, dim))

	var cl := "编队内"
	if t.side == "hostile":
		# 12 军语 P0-11：光一个 km/s 不知道是接近率还是速度。
		cl = "接近率 %+.1f km/s" % float(t.closing)
	elif t.get("own", false):
		cl = "—"
	_txt_r(mono, 364, y + 35, cl, 8, Palette.a(col, 0.8 * dim))

	var age_s := "实时"
	if t.get("stale", false):
		age_s = "陈旧 %ds" % int(t.age)
	elif not t.get("own", false):
		age_s = "更新 %02ds" % int(t.age)
	_txt(cjk, 76, y + 53, age_s, 8, Palette.a(Palette.AMBER if t.get("stale", false) else Palette.FAINT, dim))

	var frac := 1.0
	if not t.get("own", false):
		frac = clampf(1.0 - float(t.age) / 45.0 * 0.75, 0.12, 1.0)
	draw_rect(Rect2(76, y + 64, 288, 2), Palette.a(Palette.LINE, 0.8))
	draw_rect(Rect2(76, y + 64, 288.0 * frac, 2), Palette.a(col, 0.50 * dim))

func _draw_level(x: float, y: float, t: Dictionary, col: Color) -> void:
	var lv := "L%d" % int(t.level)
	draw_rect(Rect2(x, y, 18, 12), Palette.a(col, 0.08))
	draw_rect(Rect2(x, y, 18, 12), Palette.a(col, 0.42), false, 1.0)
	_txt(mono, x + 3, y + 1, lv, 7, Palette.a(col, 0.9))

func _draw_unit() -> void:
	_panel(UNIT)
	# _draw_ship_watermark()

	var u: Dictionary = state.unit
	# LORE-01 兜底（A-26/A-27）：数据层若还留着旧数据（砧级炮舰 1,200 t / 68 人），
	# 显示层补成“哈马丹号 = 托盘-5 改哨舰（300 t / 12 人）”。数据层修好后自动失效。
	if String(u.get("name", "")) == "哈马丹":
		u = u.duplicate()
		if String(u.get("en", "")) == "HAMADAN":
			u["en"] = "HARMATTAN"
		if String(u.get("cls", "")).contains("砧") or String(u.get("role", "")) == "炮舰":
			u["cls"] = "托盘-5 改"
			u["role"] = "哨舰"
		if String(u.get("mass", "")).contains("1,200"):
			u["mass"] = "300 t"
		if String(u.get("crew", "")) == "68":
			u["crew"] = "12"
	_txt(cjk, 1556, 138, "选中单位 / UNIT", 7, Palette.FAINT)
	_txt(cjk, 1556, 150, _dn(u.name), 24, Palette.TXT)
	_txt(mono, 1556, 181, _dn(u.en), 8, Palette.DIM)
	_txt(cjk, 1556, 195, _dn(u.cls + " · " + u.role), 10, Palette.PH)
	_txt(cjk, 1556, 211, _dn(u.faction), 8, Palette.DIM)
	draw_line(Vector2(1540, 224), Vector2(1860, 224), Palette.a(Palette.LINE, 0.9), 1.0)

	var stats := [
		["干重 MASS", u.mass], ["编制 CREW", u.crew],
		["加速度 ACCEL", u.accel], ["轨道 ORBIT", u.orbit],
		["倾角 INC", u.inc], ["周期 PERIOD", u.period]
	]
	for i in range(6):
		var cx := 1556.0 + float(i % 2) * 150.0
		var cy := 236.0 + float(i / 2) * 24.0
		_txt(cjk, cx, cy, stats[i][0], 8, Palette.DIM)
		_txt(mono, cx, cy + 10.0, stats[i][1], 10, Palette.TXT)

	var sys_avg := 0.0
	for i in range(u.systems.size()):
		sys_avg += float(u.systems[i][1])
	if u.systems.size() > 0:
		sys_avg /= float(u.systems.size())
	_txt(cjk, 1556, 316, "系统 / SYSTEMS", 7, Palette.FAINT)
	_txt_r(mono, 1860, 316, "AVG %d%%" % int(round(sys_avg * 100.0)), 8, Palette.DIM)
	for i in range(mini(5, u.systems.size())):
		var cy := 336.0 + float(i) * 24.0
		var sname: String = u.systems[i][0]
		var sv: float = u.systems[i][1]
		_txt(cjk, 1556, cy, sname, 9, Palette.DIM)
		_bar(Rect2(1636, cy + 4, 128, 4), sv, _sys_color(sv))
		_txt_r(mono, 1860, cy, "%d%%" % int(sv * 100.0), 8, Palette.TXT)

	_txt(cjk, 1556, 470, "Δv 预算 / BUDGET", 7, Palette.FAINT)
	_txt(mono, 1556, 482, u.dv, 30, Palette.PH)
	var dw := mono.get_string_size(u.dv, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_txt(mono, 1556.0 + dw + 5.0, 502, "m/s", 9, Palette.DIM)
	_txt(mono, 1556, 536, "/ %s 满" % u.dv_max, 8, Palette.DIM)
	var dv_now := _to_int(String(u.dv))
	var dv_full := _to_int(String(u.dv_max))
	var dv_frac := 1.0
	if dv_full > 0:
		dv_frac = clampf(float(dv_now) / float(dv_full), 0.0, 1.0)
	_bar(Rect2(1556, 548, 288, 4), dv_frac, Palette.PH)
	_txt(cjk, 1556, 560, "剩余 %d%% · 已耗 %s m/s" % [int(round(dv_frac * 100.0)), _fmt_int(maxi(dv_full - dv_now, 0))], 7, Palette.FAINT)

	# P1d：右区传感器块 = 选中舰的按舰架摘要（只读；完整字段见顶部「架」下拉）。
	# ON/OFF 只显示当前融合计划，不可点 —— 开关属于命令层。
	var rack := _rack_rows()
	var rack_ship := _rack_ship()
	var em := _rack_emission()
	var tr := _rack_track()
	var lv := clampi(int(tr.get("level", 0)), 0, 4)
	_txt(cjk, 1556, 580, "传感器架 / SENSOR RACK", 7, Palette.FAINT)
	_txt_r(cjk, 1844, 580, "%s · %02d 模块" % [_rack_ship_name(), rack.size()], 7, Palette.DIM)
	for i in range(mini(2, rack.size())):
		var s2: Dictionary = rack[i]
		var cy := 596.0 + float(i) * 18.0
		var model := String(s2.get("model", "—"))
		var on := _rack_on(rack_ship, model, bool(s2.get("on", true)))
		_txt(mono, 1556, cy, model, 9, Palette.TXT)
		var mw := mono.get_string_size(model, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_txt(cjk, 1556.0 + mw + 8.0, cy + 1.0,
			"%s · %s" % [String(s2.get("maker", "—")), _rack_type_cn(s2)], 7, Palette.DIM)
		if bool(s2.get("expose", false)):
			_txt_r(cjk, 1808, cy + 1.0, "会暴露", 7, Palette.AMBER)
		else:
			_txt_r(cjk, 1808, cy + 1.0, "被动", 7, Palette.FAINT)
		_txt_r(mono, 1844, cy + 1.0, "开" if on else "关", 7,
			Palette.PH if on else Palette.FAINT)
	if rack.size() > 2:
		_txt_r(mono, 1844, 632.0, "+%d" % (rack.size() - 2), 7, Palette.FAINT)
	var exp_short := "EMIT 暴露" if bool(em.get("exposed", false)) else "EMCON 静默"
	var exp_hint := "ELINT 已点名" if bool(state.get("elint_named")) else "开机即暴露"
	var exp_col: Color = Palette.RED if bool(state.get("elint_named")) else (Palette.AMBER if bool(em.get("exposed", false)) else Palette.FAINT)
	_txt(cjk, 1556, 636, "%s · 等级 L%d · %s" % [exp_short, lv, exp_hint], 7, exp_col)

	draw_rect(Rect2(1556, 660, 288, 32), Palette.a(Palette.AMBER, 0.05))
	draw_rect(Rect2(1556, 660, 2, 32), Palette.a(Palette.AMBER, 0.8))
	# 12 军语 P0-3：damage 是战损/损坏，不是损管；损管英文是 DAMAGE CONTROL。
	_txt(cjk, 1566, 665, "损管 / DAMAGE CONTROL", 7, Palette.AMBER)
	_txt(cjk, 1566, 677, u.damage + " · " + u.damage2, 8, Palette.TXT)

	_txt(cjk, 1556, 706, "姿态 / ATTITUDE", 7, Palette.FAINT)
	draw_rect(Rect2(1556, 720, 64, 56), Palette.a(Palette.LINE, 0.8), false, 1.0)
	var c := Vector2(1588, 748)
	var hd := Vector2(cos(deg_to_rad(12.4)), sin(deg_to_rad(12.4))) * 24.0
	draw_line(c - hd, c + hd, Palette.a(Palette.PH, 0.55), 1.0)
	for k in [-2, -1, 1, 2]:
		var o := Vector2(0, float(k) * 7.0)
		draw_line(c + o + Vector2(-6, 0), c + o + Vector2(6, 0), Palette.a(Palette.PH_FAINT, 0.45), 1.0)
	draw_line(Vector2(1588, 720), Vector2(1588, 726), Palette.a(Palette.PH, 0.5), 1.0)
	draw_circle(c, 1.4, Palette.PH)
	_txt(mono, 1628, 720, "P +12.4°", 8, Palette.TXT)
	_txt(mono, 1628, 732, "Y  -3.1°", 8, Palette.TXT)
	_txt(mono, 1628, 744, "R  +0.8°", 8, Palette.TXT)
	_txt(mono, 1628, 756, "ω  0.02°/s", 7, Palette.DIM)
	_txt(cjk, 1628, 768, "RCS 就绪", 7, Palette.PH_DIM)

	draw_line(Vector2(1540, 820), Vector2(1860, 820), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(cjk, 1556, 828, "损管队列 2 项", 8, Palette.AMBER)
	_txt_r(mono, 1860, 828, "HULL 100%", 8, Palette.DIM)

func _draw_ship_watermark() -> void:
	var col := Palette.a(Palette.PH, 0.10)
	var col2 := Palette.a(Palette.PH, 0.18)
	var cx := 1814.0
	draw_line(Vector2(cx, 150), Vector2(cx, 318), col2, 1.0)
	draw_line(Vector2(cx, 150), Vector2(cx, 166), col, 1.0)
	draw_line(Vector2(cx - 9, 156), Vector2(cx + 9, 156), col, 1.0)
	draw_arc(Vector2(cx, 166), 8.0, 0, PI, 16, col, 1.0, true)
	draw_rect(Rect2(cx - 14, 170, 28, 18), col, false, 1.0)
	draw_rect(Rect2(cx - 18, 188, 36, 24), col, false, 1.0)
	draw_rect(Rect2(cx - 22, 212, 44, 22), col2, false, 1.0)
	draw_rect(Rect2(cx - 20, 214, 40, 18), col, false, 1.0)
	draw_rect(Rect2(cx - 18, 234, 36, 52), col, false, 1.0)
	for k in range(4):
		draw_line(Vector2(cx - 18, 244.0 + float(k) * 10.0), Vector2(cx + 18, 244.0 + float(k) * 10.0), col, 1.0)
	draw_rect(Rect2(cx - 14, 286, 28, 14), col, false, 1.0)
	draw_polyline(PackedVector2Array([
		Vector2(cx - 12, 300), Vector2(cx + 12, 300),
		Vector2(cx + 16, 320), Vector2(cx - 16, 320), Vector2(cx - 12, 300)
	]), col2, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx - 18, 240), Vector2(cx - 44, 224), Vector2(cx - 44, 236), Vector2(cx - 18, 250)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx + 18, 238), Vector2(cx + 44, 220), Vector2(cx + 44, 232), Vector2(cx + 18, 248)]), col, 1.0)
	draw_polyline(PackedVector2Array([Vector2(cx + 18, 254), Vector2(cx + 42, 266), Vector2(cx + 42, 278), Vector2(cx + 18, 268)]), col, 1.0)
	for k in range(7):
		var yy := 214.0 + float(k) * 12.0
		draw_line(Vector2(cx - 22, yy), Vector2(cx - 17, yy), col, 1.0)
		draw_line(Vector2(cx + 17, yy), Vector2(cx + 22, yy), col, 1.0)

func _draw_log() -> void:
	_panel(LOG)
	_txt(cjk, 76, 893, "命令日志 / COMMAND LOG", 8, Palette.TXT)
	_txt_r(mono, 604, 893, "12 ENTRIES · NEWEST FIRST", 7, Palette.FAINT)
	draw_line(Vector2(60, 908), Vector2(620, 908), Palette.a(Palette.LINE, 0.9), 1.0)

	var cmd_left := maxf(0.0, 6.2 - float(state.elapsed))
	var pending := cmd_left > 0.0
	for i in range(state.log_lines.size()):
		var l: Dictionary = state.log_lines[i]
		var y := 918.0 + float(i) * 24.0
		_txt(mono, 76, y, "T+" + l.t, 10, Palette.a(Palette.FAINT, 0.95))
		var disp_text := _ellipsis(cjk, _dn(l.text), 11, 330.0)
		_txt(cjk, 150, y - 1, disp_text, 11, Palette.a(Palette.TXT, 0.92))
		var tw := cjk.get_string_size(disp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if l.arg != "":
			_txt(mono, 150.0 + tw + 10.0, y, _dn(l.arg), 8, Palette.a(Palette.AMBER, 0.7))
		if i == 0 and pending:
			draw_rect(Rect2(150, y + 16, 350, 1), Palette.a(Palette.AMBER, 0.10))
			draw_rect(Rect2(150, y + 16, 350.0 * (1.0 - cmd_left / 6.2), 1), Palette.a(Palette.AMBER, 0.55))
		_log_status(l, i, y, cmd_left, pending)

	var blink := 0.5 + 0.5 * sin(_t * 4.0)
	draw_rect(Rect2(76, 1024, 5, 1), Palette.a(Palette.PH, 0.6 * blink))

func _log_status(l: Dictionary, i: int, y: float, cmd_left: float, pending: bool) -> void:
	var txt := ""
	var col := Palette.DIM
	match l.status:
		"PENDING":
			if pending and i == 0:
				txt = "待生效 %.1fs" % cmd_left
				col = Palette.AMBER
			else:
				txt = "已执行"
				col = Palette.PH_DIM
		"EXEC":
			txt = "已执行"
			col = Palette.PH_DIM
		"HOLD":
			# 12 军语 P0-4：日志里的 HOLD 是「命令暂缓」，不是 ROE。
			txt = "暂缓执行"
			col = Palette.AMBER
		"RX":
			txt = "已接收"
			col = Palette.BLUE
	var r := Rect2(520, y - 1, 84, 15)
	draw_rect(r, Palette.a(col, 0.06))
	draw_rect(r, Palette.a(col, 0.40), false, 1.0)
	_txt(cjk, r.position.x + 7, r.position.y + 2, txt, 8, col)

# ── P1e：命令面板 / 点火节点 ────────────────────────────

func _cmd_btn(r: Rect2, label: String, active: bool, col: Color) -> void:
	draw_rect(r, Palette.a(col, 0.10 if active else 0.03))
	draw_rect(r, Palette.a(col, 0.65 if active else 0.25), false, 1.0)
	if active:
		draw_rect(Rect2(r.position.x, r.position.y, 2.0, r.size.y), col)
	_txt(cjk, r.position.x + 8.0, r.position.y + 4.0, label, 8, Palette.a(col, 0.95 if active else 0.55))

func _mini_btn(r: Rect2, label: String) -> void:
	draw_rect(r, Palette.a(Palette.PH, 0.05))
	draw_rect(r, Palette.a(Palette.PH_DIM, 0.35), false, 1.0)
	var w := cjk.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_txt(cjk, r.position.x + (r.size.x - w) * 0.5, r.position.y + 2.0, label, 9, Palette.TXT)

func _cmd_status_cn(st: String) -> String:
	match st:
		"QUEUED":
			return "排队"
		"TRANSMITTED":
			return "传达中"
		"EXEC":
			return "执行中"
		"DONE":
			return "已完成"
		"ABORTED":
			return "已撤销"
		"REJECTED":
			return "已拒绝"
		"DRAFT":
			return "预览"
		_:
			return st

# 命令状态机文字（等待传达 / 传达中·生效倒计时 / 执行中·回执倒计时）。
# 优先用 CommandModel.phase_text（sim 侧唯一口径）；拿不到时退回状态名。
func _cmd_phase(c: Dictionary) -> String:
	if state.get("cmd_model") != null:
		return String(state.cmd_model.phase_text(c, float(state.tau())))
	return _cmd_status_cn(String(c.get("status", "")))

# 当前 draft 的 BURN 参数（授权和预览共用）
func _draft_params() -> Dictionary:
	var preset: Dictionary = DIR_PRESETS[draft_dir]
	return {
		"exec_t": float(state.tau()) + draft_t,
		"dv_ms": draft_dv,
		"brg": float(preset["brg"]),
		"elev": float(preset["elev"]),
	}

# 把本地 draft 镜像给 sim 的 preview（不入队、不扣 Δv，只给 plot 画 DRAFT 节点）。
func _push_preview() -> void:
	if state == null or state.get("cmd_model") == null:
		return
	match cmd_action:
		"STATION":
			state.preview_command("STATION", {})
		"SHADOW":
			state.preview_command("SHADOW", {"hold_km": 60.0}, "谷神-2")
		"BURN":
			state.preview_command("BURN", _draft_params())

func _set_burn_from_x(x: float) -> void:
	var frac := clampf((x - TIMELINE.position.x) / TIMELINE.size.x, 0.0, 1.0)
	draft_t = clampf(snappedf(frac * PLAN_WINDOW_S, 0.1), 0.5, PLAN_WINDOW_S)

# 授权：把本地 draft 变成真命令（唯一写 state 的地方）
func _authorize() -> void:
	state.clear_preview()
	match cmd_action:
		"STATION":
			state.issue_command("STATION", {})
		"SHADOW":
			state.issue_command("SHADOW", {"hold_km": 60.0}, "谷神-2")
		"BURN":
			state.issue_command("BURN", _draft_params())
	queue_redraw()

func _handle_command_click(p: Vector2) -> void:
	for i in range(3):
		if Rect2(CMD_INSET_X + float(i) * 176.0, ACT_Y, 160, ACT_H).has_point(p):
			cmd_action = CMD_ACTIONS[i]
			_preview_dirty = true
			return
	if T_MINUS.has_point(p):
		draft_t = maxf(0.5, draft_t - 1.0)
		_preview_dirty = true
		return
	if T_PLUS.has_point(p):
		draft_t = minf(PLAN_WINDOW_S, draft_t + 1.0)
		_preview_dirty = true
		return
	if DV_MINUS.has_point(p):
		draft_dv = maxf(8.0, draft_dv - 8.0)
		_preview_dirty = true
		return
	if DV_PLUS.has_point(p):
		draft_dv = minf(240.0, draft_dv + 8.0)
		_preview_dirty = true
		return
	if DIR_CYCLE.has_point(p):
		draft_dir = (draft_dir + 1) % DIR_PRESETS.size()
		_preview_dirty = true
		return
	if TIMELINE.has_point(p):
		# 拖动只改本地 draft：按下即开始，松开在 _process 里轮询结束。
		_set_burn_from_x(p.x)
		_burn_drag = true
		_preview_dirty = true
		return
	if AUTH_BTN.has_point(p):
		_authorize()
		_preview_dirty = false
		return
	if ABORT_BTN.has_point(p):
		state.abort_latest_command()
		return
	if FIRE_BTN.has_point(p):
		_handle_fire_click()
		return
	for row in _queue_abort:
		var rr: Rect2 = row["rect"]
		if rr.has_point(p):
			state.abort_command(String(row["id"]))
			return

func _draw_command_panel() -> void:
	_panel(CMD)
	_queue_abort.clear()
	var dv_left := 0
	var dv_v = state.get("unit_dv_ms")
	if dv_v != null:
		dv_left = int(round(float(dv_v)))
	var camds: Array = state.commands()
	var queued := 0
	var active := 0
	var done := 0
	for raw in camds:
		var st := String((raw as Dictionary).get("status", ""))
		if st == "QUEUED" or st == "TRANSMITTED":
			queued += 1
		elif st == "EXEC":
			active += 1
		elif st == "DONE":
			done += 1

	# header
	_txt(cjk, CMD_INSET_X, 893, "命令 / ORDERS", 8, Palette.TXT)
	_txt_r(cjk, CMD_INNER_R, 893, "%s · 剩余 Δv %s m/s" % [_rack_ship_name(), _fmt_int(dv_left)], 7, Palette.DIM)

	# 动作选择：STATION / SHADOW 谷神-2 / BURN
	for i in range(3):
		var act: String = CMD_ACTIONS[i]
		var col: Color = Palette.PH
		if act == "SHADOW":
			col = Palette.BLUE
		elif act == "BURN":
			col = Palette.AMBER
		_cmd_btn(Rect2(CMD_INSET_X + float(i) * 176.0, ACT_Y, 160, ACT_H), CMD_LABELS[i], cmd_action == act, col)

	# 参数：T+ / Δv / 方向预设（全部只改本地 draft）
	var preset: Dictionary = DIR_PRESETS[draft_dir]
	_txt(cjk, CMD_INSET_X, 928, "T+", 7, Palette.DIM)
	_mini_btn(T_MINUS, "-")
	_txt(mono, 700, 930, "%04.1f s" % draft_t, 10, Palette.TXT)
	_mini_btn(T_PLUS, "+")
	_txt(cjk, 796, 928, "Δv", 7, Palette.DIM)
	_mini_btn(DV_MINUS, "-")
	_txt(mono, 848, 930, "%03.0f m/s" % draft_dv, 10, Palette.TXT)
	_mini_btn(DV_PLUS, "+")
	_txt(cjk, 984, 928, "方向", 7, Palette.DIM)
	_txt(cjk, 1016, 929, _ellipsis(cjk, String(preset["label"]), 7, 82.0), 7, Palette.TXT)
	_cmd_btn(DIR_CYCLE, "换向 ▸", false, Palette.PH)

	# P1f：把「链路」与「机动」拆两行 —— 望楼中继只花时间与暴露，不烧 Δv。
	_txt(cjk, CMD_INSET_X, 946, "链路：望楼中继 +8 s（传达 / 回执，不消耗 Δv）", 7, Palette.a(Palette.BLUE, 0.85))
	_txt(cjk, CMD_INSET_X, 954, "机动：Δv %.0f m/s · 剩余 %s m/s" % [draft_dv, _fmt_int(dv_left)], 7, Palette.a(Palette.AMBER, 0.85))
	if _burn_drag:
		_txt_r(cjk, CMD_INNER_R, 954, "拖动中 · 未授权（松开只记 draft）", 7, Palette.a(Palette.AMBER, 0.9))
	else:
		_txt_r(cjk, CMD_INNER_R, 954, "DRAFT BURN T+%.1f" % draft_t, 7, Palette.a(Palette.BLUE, 0.8))

	# 时间轴：T+0 … T+30，节点 = draft（拖动不授权）
	var tx := TIMELINE.position.x
	var tw := TIMELINE.size.x
	var axis_y := TIMELINE.position.y + 12.0
	draw_line(Vector2(tx, axis_y), Vector2(tx + tw, axis_y), Palette.a(Palette.LINE2, 0.9), 1.0)
	for i in range(7):
		var sec := float(i) * 5.0
		var x := tx + tw * sec / PLAN_WINDOW_S
		var h := 5.0 if i % 2 == 0 else 3.0
		draw_line(Vector2(x, axis_y - h), Vector2(x, axis_y), Palette.a(Palette.PH_DIM, 0.7), 1.0)
	_txt(mono, tx + 3.0, TIMELINE.position.y + 1.0, "T+0", 7, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, CMD_INNER_R - 3.0, TIMELINE.position.y + 1.0, "T+30", 7, Palette.a(Palette.FAINT, 0.9))
	# 起点：NOW
	draw_line(Vector2(tx, axis_y - 8.0), Vector2(tx, axis_y + 2.0), Palette.PH, 2.0)
	# 点火节点（draft）
	var nx := tx + tw * clampf(draft_t / PLAN_WINDOW_S, 0.0, 1.0)
	draw_line(Vector2(nx, axis_y - 8.0), Vector2(nx, axis_y + 2.0), Palette.AMBER, 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(nx, axis_y - 10.0), Vector2(nx + 5.0, axis_y - 6.0),
		Vector2(nx, axis_y - 2.0), Vector2(nx - 5.0, axis_y - 6.0)
	]), Palette.AMBER)

	# 授权 / 撤销 / 武器释放
	_cmd_btn(AUTH_BTN, "授权 / AUTHORIZE", false, Palette.PH)
	_cmd_btn(ABORT_BTN, "撤销待生效 / ABORT", false, Palette.RED)
	# P1f：武器释放（二次确认；仅裁决前可用）
	var fire_col := Palette.RED
	var fire_label := "武器释放 / RELEASE"
	var fire_ready := _fire_available()
	if _flag("fire_branch"):
		fire_label = "已授权 / RELEASED"
		fire_col = Palette.FAINT
	elif _fire_confirm_t > 0.0:
		fire_label = "确认释放？%.0fs" % ceil(_fire_confirm_t)
	elif not fire_ready:
		fire_label = "武器释放（不可用）"
		fire_col = Palette.FAINT
	_cmd_btn(FIRE_BTN, fire_label, _fire_confirm_t > 0.0, fire_col)

	# 队列（读 state.commands；只显示最后 2 条；QUEUED / TRANSMITTED 可 ABORT）
	_txt(cjk, CMD_INSET_X, 1002, "队列 / QUEUE · %d 待生效 · %d 执行 · %d 完成" % [queued, active, done], 7, Palette.FAINT)
	_txt_r(mono, CMD_INNER_R, 1002, "QUEUE %d/%d" % [queued, camds.size()], 7, Palette.FAINT)
	var shown := 0
	for idx in range(camds.size() - 1, -1, -1):
		if shown >= 2:
			break
		var c: Dictionary = camds[idx]
		var y := QUEUE_Y + float(shown) * QUEUE_ROW_H
		shown += 1
		var act := String(c.get("action", ""))
		var st := String(c.get("status", ""))
		var sc: Color = Palette.PH_DIM
		match st:
			"QUEUED":
				sc = Palette.AMBER
			"TRANSMITTED":
				sc = Palette.BLUE
			"EXEC":
				sc = Palette.PH_DIM
			"ABORTED":
				sc = Palette.FAINT
			"REJECTED":
				sc = Palette.RED
			_:
				sc = Palette.PH_DIM
		var target := String(c.get("target", ""))
		var detail := ""
		if act == "SHADOW" and target != "":
			detail = " → " + _dn(target)
		elif act == "BURN":
			detail = " Δv %.0f" % float((c.get("plan", {}) as Dictionary).get("dv_ms", 0.0))
		var line := "%s %s%s · %s" % [String(c.get("id", "")), act, detail, _cmd_phase(c)]
		_txt(mono, CMD_INSET_X, y, _ellipsis(mono, line, 7, 440.0), 7, sc)
		if st == "QUEUED" or st == "TRANSMITTED":
			var rr := Rect2(QUEUE_ABORT_X, y - 1.0, 44, 12)
			draw_rect(rr, Palette.a(Palette.RED, 0.06))
			draw_rect(rr, Palette.a(Palette.RED, 0.35), false, 1.0)
			_txt(cjk, rr.position.x + 8.0, rr.position.y + 2.0, "撤销", 7, Palette.RED)
			_queue_abort.append({"rect": rr, "id": String(c.get("id", ""))})

# ══ P1f：裁决 / 后果 / 报告覆盖层 ══════════════════════
# 原则：读 state 字段（decision_open / report_open / consequence_open / fire_branch /
# audit_flag / report_text / …）与调 state 方法（choose_ending / authorize_fire /
# submit_report）；字段/方法不存在时退回 HUD 本地演示态（DSH_UI 截图钩子用）。

const MOCK_REPORT := "第一关 · 环一 · 斛 — 监督官报告（草案）\n\nT+00:12:40 执行窗口开始。传唤级 · 案卷 4471 送达接管通知；本舰未首先开火。\n\n哈马丹 CH-IR2 报出两条回波：一条为案卷 4471（主动机动），一条为残骸反射。经远地点号 MS-IR9 交叉确认，302° 回波为 CH-IR2 虚警；谷神-2（民用工作船，应答机故障）位于方位 118°、距离 260 km。\n\nSHADOW 命令经望楼号中继，8 s 后生效；BURN 计划 T+6.2 s、Δv 84 m/s、BRG 340 / ELEV +20。\n\n结论：未发生未经授权开火。建议处置：认证交接（CERTIFY）。"

func _flag(name: String) -> bool:
	if state == null:
		return false
	var v = state.get(name)
	return v != null and bool(v)

func _ov_decision() -> bool:
	return _demo_decision or _flag("decision_open")

func _ov_consequence() -> bool:
	return _demo_consequence or _flag("consequence_open")

func _ov_report() -> bool:
	return _demo_report or _flag("report_open")

func _any_overlay() -> bool:
	return _ov_report() or _ov_consequence() or _ov_decision()

func _report_text() -> String:
	if state != null:
		var v = state.get("report_text")
		if v != null and String(v) != "":
			return String(v)
		# 还没有提交过报告：用 scenario 的 report_truth 模板做“草案”预览（不写 state）。
		var story = state.get("story")
		if story is Dictionary and (story as Dictionary).has("report_truth"):
			var rt: Dictionary = (story as Dictionary)["report_truth"]
			var outcome := String(state.get("outcome"))
			if outcome == "":
				outcome = "CERTIFY"
			if rt.has(outcome):
				var tmpl := String(rt[outcome])
				var decision := "认证交接"
				if state.has_method("ending_label"):
					decision = String(state.call("ending_label", outcome))
				tmpl = tmpl.replace("{decision}", decision).replace("{reputation}", "—").replace("{casualties}", "无")
				return "（报告草案 / DRAFT · 未提交）\n" + tmpl
	return MOCK_REPORT

# 武器释放：仅裁决前可用；二次确认。
func _fire_available() -> bool:
	if _any_overlay():
		return false
	if _flag("fire_branch") or _decision_done:
		return false
	return true

func _handle_fire_click() -> void:
	if not _fire_available():
		return
	if _fire_confirm_t <= 0.0:
		_fire_confirm_t = 3.0
		return
	_do_authorize_fire()

func _do_authorize_fire() -> void:
	_fire_confirm_t = 0.0
	if state != null and state.has_method("authorize_fire"):
		state.call("authorize_fire")
		return
	# HUD 本地演示：直接进入后果分支。
	_demo_consequence = true

func _choose_ending(kind: String) -> void:
	_decision_done = true
	if state != null and state.has_method("choose_ending"):
		state.call("choose_ending", kind)
		return
	_demo_decision = false
	_demo_report = true

func _open_report() -> void:
	if state != null and state.has_method("open_report"):
		state.call("open_report")
	elif state != null and state.get("report_open") != null:
		state.set("consequence_open", false)
		state.set("report_open", true)
	else:
		_demo_consequence = false
		_demo_report = true

func _submit_report(kind: String) -> void:
	_demo_report = false
	if state != null and state.has_method("submit_report"):
		state.call("submit_report", kind)
	if kind == "fake":
		_filed_text = "REPORT FILED — AUDIT FLAG 01"
		_filed_col = Palette.RED
	else:
		_filed_text = "REPORT FILED — CASE 4471"
		_filed_col = Palette.PH
	_filed_t = 6.0

func _poll_overlay_keys() -> void:
	for k in [KEY_1, KEY_2, KEY_3, KEY_ENTER, KEY_SPACE]:
		var down := Input.is_key_pressed(k)
		var was := bool(_key_prev.get(k, false))
		_key_prev[k] = down
		if down and not was:
			_on_overlay_key(k)

func _on_overlay_key(k: int) -> void:
	if _ov_report():
		if k == KEY_1:
			_submit_report("truth")
		elif k == KEY_2:
			_submit_report("fake")
	elif _ov_consequence():
		if k == KEY_1 or k == KEY_ENTER or k == KEY_SPACE:
			_open_report()
	elif _ov_decision():
		if k == KEY_1:
			_choose_ending("certify")
		elif k == KEY_2:
			_choose_ending("article9")
		elif k == KEY_3:
			_choose_ending("stall")

func _handle_overlay_click(p: Vector2) -> void:
	if _ov_report():
		if REPORT_TRUTH.has_point(p):
			_submit_report("truth")
		elif REPORT_FAKE.has_point(p):
			_submit_report("fake")
		return
	if _ov_consequence():
		if CONSEQ_SUBMIT.has_point(p):
			_open_report()
		return
	if _ov_decision():
		for i in range(3):
			if _decision_row_rect(i).has_point(p):
				_choose_ending(DECISION_KINDS[i])
				return

func _mouse_base() -> Vector2:
	var win := get_window()
	if win == null or win.size.x <= 1:
		return Vector2(-1.0, -1.0)
	return win.get_mouse_position() * (Vector2(1920.0, 1080.0) / Vector2(win.size))

func _wrap_text(f: Font, text: String, sz: int, max_w: float) -> Array:
	var out: Array = []
	for para in text.split("\n"):
		if String(para) == "":
			out.append("")
			continue
		var cur := ""
		for i in String(para).length():
			var ch := String(para).substr(i, 1)
			if cur != "" and f.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w:
				out.append(cur)
				cur = ch
			else:
				cur += ch
		out.append(cur)
	return out

func _decision_row_rect(i: int) -> Rect2:
	var r := DECISION_RECT
	return Rect2(r.position.x + 28.0, r.position.y + 112.0 + float(i) * 124.0, r.size.x - 56.0, 112.0)

func _overlay_dim() -> void:
	# 全屏压暗：V1.5 的「一次性」覆盖层，不做动画。
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.008, 0.030, 0.024, 0.84))
	for i in range(0, 1080, 4):
		draw_rect(Rect2(0.0, float(i), 1920.0, 1.0), Color(0, 0, 0, 0.045))

func _overlay_frame(r: Rect2, title: String, kicker: String) -> void:
	draw_rect(r, Palette.a(Palette.PANEL, 0.985))
	draw_rect(r, Palette.a(Palette.PH, 0.85), false, 1.0)
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), Palette.a(Palette.LINE, 0.85), false, 1.0)
	_corners(Rect2(r.position - Vector2(10, 10), r.size + Vector2(20, 20)), 26.0, Palette.a(Palette.PH, 0.5))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 44.0)), Palette.a(Palette.PANEL2, 1.0))
	draw_line(Vector2(r.position.x, r.position.y + 44.0), Vector2(r.end.x, r.position.y + 44.0), Palette.a(Palette.PH, 0.5), 1.0)
	_txt(cjk, r.position.x + 20.0, r.position.y + 12.0, title, 13, Palette.PH)
	_txt_r(mono, r.end.x - 20.0, r.position.y + 16.0, kicker, 7, Palette.a(Palette.FAINT, 0.95))

func _draw_decision_overlay() -> void:
	_overlay_dim()
	var r := DECISION_RECT
	_overlay_frame(r, "监督官裁决 / SUPERVISOR DETERMINATION", "DECISION · CASE 4471 · 第一关")
	var prompt := "执行窗口只剩最后一拍。谷神-2 的应答机是坏的，传唤级要你监督交接；选一个："
	var endings: Array = []
	if state != null:
		var pv = state.get("decision_prompt")
		if pv != null and String(pv) != "":
			prompt = String(pv)
		var ev = state.get("endings")
		if ev is Array:
			endings = ev
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, "第一关 · 环一 · 斛 — 监督交接 · 执行窗口 00:06:00", 8, Palette.DIM)
	_txt_r(cjk, r.end.x - 20.0, r.position.y + 56.0, "记录进案卷 · 不可撤回", 7, Palette.a(Palette.AMBER, 0.7))
	_txt(cjk, r.position.x + 20.0, r.position.y + 76.0, _ellipsis(cjk, prompt, 8, r.size.x - 40.0), 8, Palette.a(Palette.TXT, 0.86))
	var mp := _mouse_base()
	for i in range(3):
		var row := _decision_row_rect(i)
		var hot := row.has_point(mp)
		draw_rect(row, Palette.a(Palette.PANEL2, 0.95) if hot else Palette.a(Palette.PANEL, 0.55))
		draw_rect(row, Palette.a(Palette.PH, 0.8 if hot else 0.30), false, 1.0)
		if hot:
			draw_rect(Rect2(row.position.x, row.position.y, 2.0, row.size.y), Palette.PH)
		var label: String = String(DECISION_NAMES[i])
		var hint: String = String(DECISION_CONSEQ[i])
		var tag: String = String(DECISION_RUBRIC[i])
		if i < endings.size():
			var e: Dictionary = endings[i]
			label = "%s / %s" % [String(e.get("label", label)), String(e.get("code", ""))]
			hint = String(e.get("hint", hint))
			tag = String(e.get("code", tag))
		_txt(mono, row.position.x + 18.0, row.position.y + 14.0, "0%d" % (i + 1), 22, Palette.a(Palette.PH, 0.9))
		_txt(cjk, row.position.x + 74.0, row.position.y + 16.0, label, 13, Palette.PH if hot else Palette.TXT)
		_txt(cjk, row.position.x + 74.0, row.position.y + 48.0, _ellipsis(cjk, hint, 8, row.size.x - 300.0), 8, Palette.DIM)
		_txt_r(cjk, row.end.x - 18.0, row.position.y + 16.0, tag, 7, Palette.a(Palette.AMBER, 0.65))
		_txt_r(mono, row.end.x - 18.0, row.position.y + 50.0, "[%d]" % (i + 1), 8, Palette.a(Palette.FAINT, 0.9))
	var fy := r.end.y - 36.0
	draw_line(Vector2(r.position.x + 20.0, fy - 6.0), Vector2(r.end.x - 20.0, fy - 6.0), Palette.a(Palette.LINE, 0.8), 1.0)
	_txt(cjk, r.position.x + 20.0, fy + 2.0, "1 / 2 / 3 或点击行 · 裁决前仍可武器释放（需二次确认）", 7, Palette.FAINT)
	_txt_r(cjk, r.end.x - 20.0, fy + 2.0, "ROE：仅自卫 · 不得首先开火", 7, Palette.a(Palette.AMBER, 0.7))

func _draw_consequence_overlay() -> void:
	_overlay_dim()
	var r := CONSEQ_RECT
	_overlay_frame(r, "后果 / CONSEQUENCE", "FIRE BRANCH · CASE 4471 · SIM FROZEN")
	var ctext := "火控解锁。谷神-2 是民用船——12 人无人生还。ROE 违规写进黑匣子。"
	if state != null:
		var cv = state.get("consequence_text")
		if cv != null and String(cv) != "":
			ctext = String(cv)
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, "开火之后不是战斗，是报告（08 §4）。仿真时间已冻结。", 8, Palette.DIM)
	var lines := _wrap_text(cjk, ctext, 9, r.size.x - 48.0)
	for i in range(mini(lines.size(), 4)):
		_txt(cjk, r.position.x + 24.0, r.position.y + 80.0 + float(i) * 18.0, String(lines[i]), 9, Palette.a(Palette.TXT, 0.92))
	var rows := [
		["民用伤亡 / CIVILIAN CASUALTY", "谷神-2 全损 · 民用 12 人 · 遥测仅剩应急信标"],
		["ROE 违规 / ROE VIOLATION", "未经授权的武器释放 · 违反「仅自卫 / WEAPONS HOLD」"],
		["时间 / SIMULATION", "FROZEN · 命令队列冻结，仅剩报告流程"],
		["案卷 / CASE FILE", "新增条目：武器释放（WEAPONS RELEASE）· 审裁证据封存"],
	]
	for i in range(rows.size()):
		var y := r.position.y + 176.0 + float(i) * 42.0
		_txt(cjk, r.position.x + 24.0, y, rows[i][0], 7, Palette.FAINT)
		_txt(cjk, r.position.x + 250.0, y - 3.0, rows[i][1], 9, Palette.TXT)
		draw_line(Vector2(r.position.x + 24.0, y + 19.0), Vector2(r.end.x - 24.0, y + 19.0), Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(cjk, r.position.x + 24.0, r.position.y + 352.0, "回执 / 上级将收到案卷与传感器日志（08 §3.2）", 7, Palette.a(Palette.AMBER, 0.6))
	_cmd_btn(CONSEQ_SUBMIT, "提交报告 / SUBMIT REPORT", false, Palette.PH)
	_txt_r(cjk, r.end.x - 20.0, r.end.y - 22.0, "E / Enter 或点击按钮", 7, Palette.FAINT)

func _draw_report_overlay() -> void:
	_overlay_dim()
	var r := REPORT_RECT
	_overlay_frame(r, "报告 / REPORT", "CASE 4471 · FILED BY SUPERVISOR")
	var header := "第一关 · 监督交接 — 监督官报告（草案）"
	if state != null:
		var oc := String(state.get("outcome"))
		if oc != "" and state.has_method("ending_label"):
			header = "裁决：%s · 报告（草案）" % String(state.call("ending_label", oc))
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, header, 8, Palette.DIM)
	# 左：报告正文
	var lx := r.position.x + 28.0
	var ly := r.position.y + 76.0
	_txt(cjk, lx, ly, "报告正文 / REPORT TEXT", 7, Palette.FAINT)
	var lines := _wrap_text(cjk, _report_text(), 9, 560.0)
	for i in range(mini(lines.size(), 22)):
		_txt(cjk, lx, ly + 20.0 + float(i) * 16.0, lines[i], 9, Palette.a(Palette.TXT, 0.92))
	# 左下：证据链（08 §3.2）
	var ey := r.position.y + 460.0
	draw_line(Vector2(lx, ey - 12.0), Vector2(lx + 560.0, ey - 12.0), Palette.a(Palette.LINE, 0.8), 1.0)
	_txt(cjk, lx, ey, "证据 / EVIDENCE", 7, Palette.FAINT)
	var evidence := [
		"· 传感器日志：MS-IR9 / CH-IR2 / ELINT 记录（谁在何时开机、看到什么）",
		"· 命令队列：SHADOW / BURN / 撤销记录（谁下令、几秒生效）",
		"· 应答机 / 通信：谷神-2 故障、传唤级接管通告、回执",
		"· 船员证词：后续系统（第一关不做）",
	]
	for i in range(evidence.size()):
		_txt(cjk, lx, ey + 22.0 + float(i) * 18.0, evidence[i], 8, Palette.DIM)
	# 右：处置（如实 / 伪造）；选项文字优先用 state.report_options
	var truth_label := "如实 / TRUTH"
	var truth_hint := "无伪证 · 记录进案卷"
	var fake_label := "伪造 / FALSIFY"
	var fake_hint := "perjury_count +1 · 第三次触发最坏结局"
	var fake_avail := true
	if state != null:
		var ro = state.get("report_options")
		if ro is Array and (ro as Array).size() > 0:
			var o0: Dictionary = (ro as Array)[0]
			truth_label = String(o0.get("label", truth_label))
			truth_hint = String(o0.get("hint", truth_hint))
			if (ro as Array).size() > 1:
				var o1: Dictionary = (ro as Array)[1]
				fake_label = String(o1.get("label", fake_label))
				fake_hint = String(o1.get("hint", fake_hint))
			else:
				fake_avail = false
	var rx := r.position.x + 616.0
	_txt(cjk, rx, ly, "处置 / FILING", 7, Palette.FAINT)
	_report_option_card(REPORT_TRUTH, 0, truth_label, "REPORT FILED — CASE 4471", truth_hint, Palette.PH)
	if fake_avail:
		_report_option_card(REPORT_FAKE, 1, fake_label, "AUDIT FLAG 01", fake_hint, Palette.RED)
	else:
		draw_rect(REPORT_FAKE, Palette.a(Palette.FAINT, 0.03))
		draw_rect(REPORT_FAKE, Palette.a(Palette.FAINT, 0.25), false, 1.0)
		_txt(cjk, REPORT_FAKE.position.x + 16.0, REPORT_FAKE.position.y + 12.0, "%s（本轮不可用）" % fake_label, 11, Palette.FAINT)
		_txt(cjk, REPORT_FAKE.position.x + 16.0, REPORT_FAKE.position.y + 40.0, "只有出现不良后果，才有淡化 / 伪造选项（08 §3.1）。", 8, Palette.DIM)
	_section_note(rx, REPORT_FAKE.end.y + 16.0)
	var pj := 0
	var pjv = state.get("perjury_count") if state != null else null
	if pjv != null:
		pj = int(pjv)
	_txt(mono, rx, REPORT_FAKE.end.y + 78.0, "perjury_count = %d" % pj, 8, Palette.DIM)
	if state != null and bool(state.get("audit_flag")):
		_txt(mono, rx, REPORT_FAKE.end.y + 94.0, "AUDIT FLAG 01 已置位", 8, Palette.RED)
	_txt_r(cjk, r.end.x - 20.0, r.end.y - 40.0, "1 如实 · 2 伪造 · 点击卡片提交（提交后不可更改）", 7, Palette.FAINT)

func _section_note(x: float, y: float) -> void:
	_txt(cjk, x, y, "只有出现不良后果，才有淡化 / 伪造选项（08 §3.1）。", 7, Palette.a(Palette.AMBER, 0.7))
	_txt(cjk, x, y + 14.0, "造假会累积；制度最擅长等。", 7, Palette.a(Palette.FAINT, 0.9))

func _report_option_card(rc: Rect2, idx: int, title: String, big: String, sub: String, col: Color) -> void:
	var hot := rc.has_point(_mouse_base())
	draw_rect(rc, Palette.a(col, 0.10 if hot else 0.04))
	draw_rect(rc, Palette.a(col, 0.75 if hot else 0.35), false, 1.0)
	if hot:
		draw_rect(Rect2(rc.position.x, rc.position.y, 2.0, rc.size.y), col)
	_txt(cjk, rc.position.x + 16.0, rc.position.y + 12.0, title, 11, col)
	_txt(mono, rc.position.x + 16.0, rc.position.y + 40.0, big, 9, Palette.TXT)
	_txt(cjk, rc.position.x + 16.0, rc.position.y + 62.0, sub, 7, Palette.DIM)
	_txt_r(mono, rc.end.x - 16.0, rc.position.y + 12.0, "[%d]" % (idx + 1), 8, Palette.a(Palette.FAINT, 0.9))

func _draw_filed_banner() -> void:
	var a := clampf(_filed_t / 1.2, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.008, 0.030, 0.024, 0.5 * a))
	var r := FILED_RECT
	draw_rect(r, Palette.a(Palette.PANEL, 1.0))
	draw_rect(r, Palette.a(_filed_col, 0.85), false, 1.0)
	_txt(mono, r.position.x + 24.0, r.position.y + 22.0, _filed_text, 15, _filed_col)
	_txt(cjk, r.position.x + 24.0, r.position.y + 54.0, "报告已归档 · 记录进案卷（demo 结束）", 8, Palette.DIM)
	_txt_r(mono, r.end.x - 24.0, r.position.y + 54.0, "FILED", 8, Palette.a(_filed_col, 0.7))

func _draw_time() -> void:
	_panel(TIME)
	_txt(cjk, 1216, 893, "态势回放 / REPLAY", 8, Palette.TXT)
	_txt_r(mono, 1844, 893, "60s BUFFER", 7, Palette.FAINT)

	time_rects.clear()
	var scales := [1.0, 10.0, 60.0, 300.0]
	var names := ["1×", "10×", "60×", "300×"]
	for i in range(4):
		var r := Rect2(1216.0 + float(i) * 48.0, 912, 40, 24)
		time_rects.append(r)
		var active: bool = absf(float(state.time_scale) - float(scales[i])) < 0.1
		if active:
			draw_rect(r, Palette.a(Palette.PH, 0.10))
			draw_rect(r, Palette.a(Palette.PH, 0.65), false, 1.0)
			_txt(mono, r.position.x + 8, r.position.y + 6, names[i], 9, Palette.PH)
		else:
			draw_rect(r, Palette.a(Palette.LINE, 0.5), false, 1.0)
			_txt(mono, r.position.x + 8, r.position.y + 6, names[i], 9, Palette.a(Palette.DIM, 0.75))
	_txt(cjk, 1416, 916, "SPACE 暂停 / 1-4 时标", 7, Palette.FAINT)

	var x0 := 1216.0
	var x1 := 1844.0
	var w := x1 - x0
	var y := 964.0
	draw_rect(Rect2(x0, 952, w * 0.20, 24), Palette.a(Palette.PH, 0.025))
	draw_line(Vector2(x0, y), Vector2(x1, y), Palette.a(Palette.LINE2, 0.9), 1.0)
	for i in range(13):
		var x := x0 + w * float(i) / 12.0
		var h := 9.0 if i % 3 == 0 else 4.0
		draw_line(Vector2(x, y - h), Vector2(x, y), Palette.a(Palette.PH_DIM, 0.70), 1.0)
	var events := [0.18, 0.42, 0.66, 0.86]
	var ecols := [Palette.AMBER, Palette.PH, Palette.AMBER, Palette.BLUE]
	for i in range(events.size()):
		var ex := x0 + w * float(events[i])
		draw_line(Vector2(ex, y - 10), Vector2(ex, y + 3), Palette.a(ecols[i], 0.28), 1.0)
		draw_circle(Vector2(ex, y), 3.0, Palette.a(ecols[i], 0.85))
	draw_line(Vector2(x1, 952), Vector2(x1, 976), Palette.PH, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x1, 944), Vector2(x1 + 6, 952), Vector2(x1 - 6, 952)
	]), Palette.PH)
	_txt(mono, x0, 980, "T-60", 8, Palette.FAINT)
	_txt(mono, x0 + w * 0.5 - 12.0, 980, "T-30", 8, Palette.FAINT)
	_txt_r(mono, x1, 980, "NOW", 8, Palette.PH)

	draw_line(Vector2(1200, 996), Vector2(1860, 996), Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(cjk, 1216, 1004, "记忆衰减 60s · 事件已标记", 7, Palette.FAINT)
	_txt_r(mono, 1844, 1004, "CURSOR T+12:31.4", 7, Palette.a(Palette.AMBER, 0.55))

# ── 传感器条 / 阵列下拉 ────────────────────────────────

func _draw_sensor_bar() -> void:
	# P1d：条显示「选中舰 · 当前模块」，而不是全局来源；右边带只读暴露标记。
	var em_bar := _rack_emission()
	var exposed := bool(em_bar.get("exposed", false))
	var border: Color = Palette.a(Palette.PH, 0.55) if menu_open else (
		Palette.a(Palette.AMBER, 0.55) if exposed else Palette.a(Palette.LINE, 0.95))
	draw_rect(SENSOR_RECT, Palette.a(Palette.PANEL, 1.0))
	draw_rect(SENSOR_RECT, border, false, 1.0)
	var x0 := SENSOR_RECT.position.x
	var y0 := SENSOR_RECT.position.y
	_txt(mono, x0 + 12.0, y0 + 8.0, "SENSOR", 7, Palette.a(Palette.PH, 0.8))
	draw_line(Vector2(x0 + 64.0, y0 + 4.0), Vector2(x0 + 64.0, y0 + 24.0), Palette.a(Palette.LINE, 0.85), 1.0)
	var s: Dictionary = state.sensors[clampi(int(state.sensor), 0, state.sensors.size() - 1)]
	_glyph(x0 + 72.0, y0 + 6.0, 16.0, String(s.get("glyph", "ring")), Color(s.get("color", "#8CF0C0")))
	var model := _dn(String(s.get("model", "—")))
	_txt(cjk, x0 + 96.0, y0 + 8.0, "%s · %s" % [_rack_ship_name(), model], 9, Palette.TXT)
	var tag := "会暴露" if bool(s.get("expose", false)) else "被动"
	var tag_col: Color = Palette.AMBER if bool(s.get("expose", false)) else Palette.FAINT
	_txt_r(cjk, SENSOR_RECT.end.x - 32.0, y0 + 9.0, "%s · %s" % [_dn(String(s.get("mode", ""))), tag], 7, tag_col)
	var chev := "▴" if menu_open else "▾"
	_txt(mono, SENSOR_RECT.end.x - 16.0, y0 + 8.0, chev, 10, Palette.a(Palette.PH, 0.9 if menu_open else 0.7))

func _draw_sensor_menu() -> void:
	# P1d：展开态 = 选中舰的按舰传感器架（只读）。
	# 行：model / source·maker·type·range·refresh / 暴露 + 只读 ON/OFF；
	# footer：暴露（EMCON / EMIT）、接触等级证据、开机即暴露提示。
	menu_rects.clear()
	var r := _menu_rect()
	var x0 := r.position.x
	var y0 := r.position.y
	var rack := _rack_rows()
	var em := _rack_emission()
	var tr := _rack_track()
	var lv := clampi(int(tr.get("level", 0)), 0, 4)
	var ship := _rack_ship()

	# 面板本体（开场时压在 BG 贴片下面）
	draw_rect(r, Palette.a(Palette.PANEL, 1.0))
	draw_rect(r, Palette.a(Palette.LINE, 0.95), false, 1.0)
	var head := "传感器架 / SENSOR RACK"
	_txt(cjk, x0 + 12.0, y0 + 8.0, head, 9, Palette.TXT)
	var hw := cjk.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_txt(cjk, x0 + 12.0 + hw + 8.0, y0 + 9.0, "ON/OFF 只读", 7, Palette.a(Palette.FAINT, 0.95))
	_txt_r(cjk, r.end.x - 12.0, y0 + 8.0, "%s · %02d 模块" % [_rack_ship_name(), rack.size()], 7, Palette.a(Palette.FAINT, 0.95))
	draw_line(Vector2(x0, y0 + MENU_HEAD), Vector2(r.end.x, y0 + MENU_HEAD), Palette.a(Palette.LINE, 0.9), 1.0)

	var foot_y := y0 + MENU_HEAD + float(rack.size()) * MENU_ROW
	for i in range(rack.size()):
		var s: Dictionary = rack[i]
		var row := Rect2(x0, y0 + MENU_HEAD + float(i) * MENU_ROW, r.size.x, MENU_ROW)
		menu_rects.append(row)
		var sel := i == clampi(int(state.sensor), 0, rack.size() - 1)
		if sel:
			draw_rect(row, Palette.a(Palette.PANEL2, 0.95))
			draw_rect(Rect2(row.position.x, row.position.y, 2.0, row.size.y), Palette.PH)
		var typ := String(s.get("type", ""))
		var col := _rack_color(typ)
		_glyph(row.position.x + 12.0, row.position.y + 14.0, 22.0, _rack_glyph(typ), col)
		var model := String(s.get("model", "—"))
		var mf := cjk if Fonts.has_cjk(model) else mono
		_txt(mf, row.position.x + 46.0, row.position.y + 8.0, model, 10, Palette.TXT)
		# 暴露：能力标记（只读）——「会暴露」是能力，不等于此刻正在发射。
		var expose := bool(s.get("expose", false))
		_txt_r(cjk, row.end.x - 52.0, row.position.y + 9.0, "会暴露" if expose else "被动", 7,
			Palette.AMBER if expose else Palette.FAINT)
		# ON/OFF：只读占位（显示当前融合计划，不可点）
		var on := _rack_on(ship, model, bool(s.get("on", true)))
		var chip_col: Color = Palette.PH if on else Palette.FAINT
		var chip := Rect2(row.end.x - 44.0, row.position.y + 6.0, 32, 16)
		draw_rect(chip, Palette.a(chip_col, 0.05))
		draw_rect(chip, Palette.a(chip_col, 0.30), false, 1.0)
		var on_s := "开" if on else "关"
		var on_w := cjk.get_string_size(on_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		_txt(cjk, chip.position.x + (chip.size.x - on_w) * 0.5, chip.position.y + 3.0, on_s, 7, chip_col)
		# 第二行：source · maker · type · range · refresh
		var line2 := "%s · %s · %s · %s · 刷新 %.0fs" % [
			_dn(String(s.get("source", "—"))), String(s.get("maker", "—")),
			_rack_type_cn(s), _km(float(s.get("range_km", 0.0))),
			float(s.get("refresh_s", 0.0))]
		_txt(cjk, row.position.x + 46.0, row.position.y + 30.0,
			_ellipsis(cjk, line2, 7, row.size.x - 66.0), 7, Palette.DIM)
		if not sel:
			draw_line(Vector2(row.position.x + 12.0, row.end.y - 1.0),
				Vector2(row.end.x - 12.0, row.end.y - 1.0), Palette.a(Palette.LINE, 0.55), 1.0)

	# footer：暴露 / 等级 / 警告（全部只读）
	draw_line(Vector2(x0, foot_y), Vector2(r.end.x, foot_y), Palette.a(Palette.LINE, 0.9), 1.0)
	var emitters: Array = em.get("emitters", [])
	var exposed := bool(em.get("exposed", false))
	var named := bool(state.get("elint_named"))
	var line1 := ("%d 个发射器 · 已暴露" % emitters.size()) if exposed else "无主动发射 · 电磁静默"
	var line1_col: Color = Palette.RED if named else (Palette.AMBER if exposed else Palette.PH_DIM)
	_txt(cjk, x0 + 12.0, foot_y + 8.0, "暴露 / EXPOSURE", 7, Palette.FAINT)
	_txt(cjk, x0 + 116.0, foot_y + 8.0, line1, 8, line1_col)
	_txt(cjk, x0 + 12.0, foot_y + 26.0, "等级 / LEVEL", 7, Palette.FAINT)
	_txt(cjk, x0 + 116.0, foot_y + 26.0, "L%d · %s" % [lv, _level_desc(lv)], 8, Palette.a(Palette.PH, 0.85))
	_txt_r(cjk, r.end.x - 12.0, foot_y + 9.0, "ELINT 已点名" if named else "开机即暴露", 7,
		Palette.RED if named else Palette.a(Palette.AMBER, 0.65))
	var warn := ""
	var warns: Array = em.get("warnings", [])
	if not warns.is_empty():
		warn = String(warns[0]).replace("（05 §S-02）", "").replace("（05 §S-04）", "")
	elif exposed:
		warn = "主动模块开机即暴露：ELINT 可截获（05 §S-02）"
	else:
		warn = "被动模块 24 h 开机不付代价（05 §S-01）"
	_txt(cjk, x0 + 12.0, foot_y + 44.0, _ellipsis(cjk, warn, 7, r.size.x - 24.0), 7,
		Palette.a(Palette.AMBER, 0.55))

	# 开场与 V2 同拍：准星闪 <0.14s → 1px PH 细框 0.12s 淡入 → 1-2-4-3 象限硬切
	for k in range(4):
		var delay := 0.08 + float(k) * MENU_QUAD_STEP
		if menu_t < delay:
			var idx: int = int(MENU_QUAD_ORDER[k])
			var qx := 0.0 if idx % 2 == 0 else r.size.x * 0.5
			var qy := 0.0 if idx < 2 else r.size.y * 0.5
			draw_rect(Rect2(r.position + Vector2(qx, qy), r.size * 0.5), Palette.BG)
	var frame_a := clampf(menu_t / MENU_FRAME, 0.0, 1.0)
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Palette.a(Palette.PH, 0.8 * frame_a), false, 1.0)
	if menu_t < MENU_FLASH:
		var c := r.get_center()
		draw_circle(c, 2.0, Palette.PH)
		draw_line(c - Vector2(18.0, 0.0), c + Vector2(18.0, 0.0), Palette.a(Palette.PH, 0.8), 1.0)
		draw_line(c - Vector2(0.0, 18.0), c + Vector2(0.0, 18.0), Palette.a(Palette.PH, 0.8), 1.0)

# ── 冷启动 ──────────────────────────────────────────────

func _draw_boot() -> void:
	var t: float = clampf(float(state.boot_t), 0.0, 1.7)
	draw_rect(Rect2(0, 0, 1920, 1080), Palette.BG)

	# 上升的 1px 扫描线 + 残影
	var sweep := clampf(t / 1.55, 0.0, 1.0)
	var scan_y := 1080.0 * (1.0 - sweep)
	draw_rect(Rect2(0, scan_y, 1920, 1), Palette.a(Palette.PH, 0.8))
	draw_rect(Rect2(0, scan_y + 54.0, 1920, 1), Palette.a(Palette.PH, 0.10))

	# 四角括号
	_corners(Rect2(30, 30, 1860, 1020), 26.0, Palette.a(Palette.PH, 0.5))

	# 标题 / 副题
	var jitter := 2.0 if fmod(t * 14.0, 1.0) < 0.18 else 0.0
	_txt(mono, 120.0 + jitter, 148.0, "CISLUNAR", 64, Palette.PH)
	_txt(mono, 122.0, 222.0, "APSIS // CISLUNAR COMMAND", 13, Palette.a(Palette.PH, 0.55))
	_txt(cjk, 122.0, 246.0, "地月指挥终端 · 冷启动序列 / COLD START", 9, Palette.a(Palette.DIM, 0.85))

	# 六行自检（逐行出现）
	var lines := [
		"DATUM CCS / COLD START",
		"MOUNT CISLUNAR GRID ........ OK",
		"LINK APSIS ................. 0.4s",
		"SENSOR ARRAY ............... 06",
		"RECEIVERSHIP NOTICE 4471 ... RX",
		"SUPERVISOR AUTHORITY ....... GRANTED"
	]
	for i in range(lines.size()):
		if t * 8.0 > float(i):
			_txt(mono, 120.0, 300.0 + float(i) * 30.0, lines[i], 11, Palette.a(Palette.PH, 0.85))

	# 右侧总线读数
	var st := ["LINK 0.4s", "ARRAY 06", "NOTICE 4471", "APSIS 192,000 km", "ROE 仅自卫"]
	for i in range(st.size()):
		if t * 6.0 > float(i):
			_txt_r(mono, 1800.0, 300.0 + float(i) * 24.0, st[i], 9, Palette.a(Palette.DIM, 0.8))

	# 进度条
	var p := clampf((t - 0.15) / 1.25, 0.0, 1.0)
	draw_rect(Rect2(120, 620, 420, 2), Palette.a(Palette.PH, 0.15))
	draw_rect(Rect2(120, 620, 420.0 * p, 2), Palette.PH)
	var ps := "INITIALIZING %03d%%" % int(p * 100.0)
	if p >= 1.0:
		ps = "SYSTEM ONLINE"
	_txt(mono, 120.0, 634.0, ps, 8, Palette.a(Palette.PH, 0.65))
	if p >= 1.0:
		var pw := mono.get_string_size(ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_txt(cjk, 120.0 + pw + 12.0, 633.0, "系统就绪 / READY", 8, Palette.PH)

	# 24px 像素块自检场（24 列 × 3 行）
	for i in range(72):
		var bx := 120.0 + float(i % 24) * 28.0
		var by := 700.0 + floorf(float(i) / 24.0) * 28.0
		var h := fmod(absf(sin(float(i) * 12.9898) * 43758.5453), 1.0)
		if h < clampf(t * 0.9, 0.0, 1.0):
			draw_rect(Rect2(bx, by, 24, 24), Palette.a(Palette.PH, 0.10))
			draw_rect(Rect2(bx, by, 24, 24), Palette.a(Palette.PH, 0.35), false, 1.0)

	# 底缘铭牌
	_txt(mono, 120.0, 1000.0, "CS-9 · TACTICAL DISPLAY UNIT · COLD BOOT", 7, Palette.a(Palette.FAINT, 0.85))
	_txt_r(mono, 1800.0, 1000.0, "SER. 0447 / APSIS", 7, Palette.a(Palette.FAINT, 0.85))

func _draw_screen_edge() -> void:
	draw_rect(Rect2(40, 40, 1840, 1000), Color(0, 0, 0, 1), false, 1.0)
	draw_rect(Rect2(41, 41, 1838, 998), Palette.a(Palette.TXT, 0.022), false, 1.0)

func _panel(r: Rect2) -> void:
	draw_rect(r, Palette.a(Palette.PANEL, 1.0))
	draw_rect(r, Palette.a(Palette.LINE, 0.9), false, 1.0)

func _chip(r: Rect2, label: String, col: Color, active: bool) -> void:
	draw_rect(r, Palette.a(col, 0.07 if active else 0.02))
	draw_rect(r, Palette.a(col, 0.40 if active else 0.20), false, 1.0)
	_txt(cjk, r.position.x + 6, r.position.y + 3, label, 7, Palette.a(col, 0.9 if active else 0.45))

func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Palette.a(Palette.LINE, 0.45))
	var n := 10
	var gap := 1.0
	var w := (r.size.x - gap * float(n - 1)) / float(n)
	var filled := int(round(clampf(frac, 0.0, 1.0) * float(n)))
	for i in range(n):
		var x := r.position.x + float(i) * (w + gap)
		var c := col if i < filled else Palette.a(Palette.LINE, 0.9)
		draw_rect(Rect2(x, r.position.y, w, r.size.y), c)

func _sys_color(v: float) -> Color:
	if v >= 0.85:
		return Palette.PH
	if v >= 0.60:
		return Palette.AMBER
	return Palette.RED

func _side_color(t: Dictionary) -> Color:
	match t.side:
		"friend":
			return Palette.PH
		"hostile":
			return Palette.RED
		"unknown":
			return Palette.AMBER
		"ghost":
			return Palette.PH_FAINT
		_:
			return Palette.TXT

func _glyph(x: float, y: float, s: float, kind: String, c: Color) -> void:
	var cx := x + s * 0.5
	var cy := y + s * 0.5
	var r := s * 0.38
	match kind:
		"ring":
			draw_arc(Vector2(cx, cy), r, 0, TAU, 24, c, 1.2, true)
			draw_circle(Vector2(cx, cy), 1.5, c)
		"hex":
			var p: Array[Vector2] = []
			for i in range(7):
				var a := TAU * float(i) / 6.0 - PI * 0.5
				p.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(PackedVector2Array(p), c, 1.2, true)
		"web":
			for i in range(3):
				draw_arc(Vector2(cx, cy), r * (0.35 + float(i) * 0.3), 0, TAU, 24, c, 1.0, true)
			for i in range(4):
				var a := TAU * float(i) / 4.0
				draw_line(Vector2(cx, cy), Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r, c, 1.0)
		"frame":
			draw_rect(Rect2(cx - r, cy - r * 0.7, r * 2.0, r * 1.4), c, false, 1.0)
			draw_line(Vector2(cx - r - 2, cy), Vector2(cx + r + 2, cy), c, 1.0)
			draw_line(Vector2(cx, cy - r - 2), Vector2(cx, cy + r + 2), c, 1.0)
		"gate":
			draw_line(Vector2(cx - r, cy - r), Vector2(cx - r, cy + r), c, 1.2)
			draw_line(Vector2(cx + r, cy - r), Vector2(cx + r, cy + r), c, 1.2)
			draw_line(Vector2(cx - r, cy), Vector2(cx + r, cy), c, 1.0)
		"jag":
			var p2 := PackedVector2Array([
				Vector2(cx - r, cy + r * 0.6), Vector2(cx - r * 0.4, cy - r * 0.5),
				Vector2(cx + r * 0.1, cy + r * 0.2), Vector2(cx + r, cy - r * 0.7)
			])
			draw_polyline(p2, c, 1.2, true)
		_:
			draw_circle(Vector2(cx, cy), r, c)

func _corners(r: Rect2, l: float, c: Color) -> void:
	draw_line(r.position, r.position + Vector2(l, 0), c, 1.0)
	draw_line(r.position, r.position + Vector2(0, l), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), c, 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), c, 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), c, 1.0)
	draw_line(r.end, r.end - Vector2(l, 0), c, 1.0)
	draw_line(r.end, r.end - Vector2(0, l), c, 1.0)

func _hms(s: float) -> String:
	var t := int(s)
	return "%02d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, t % 60]

# "1,120" / "300 t" → 1120 / 300。只用于显示数值的读取。
func _to_int(s: String) -> int:
	var digits := ""
	for i in s.length():
		var ch := s.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
	return int(digits) if digits != "" else 0

func _fmt_int(n: int) -> String:
	var raw := str(absi(n))
	var out := ""
	for i in raw.length():
		if i > 0 and (raw.length() - i) % 3 == 0:
			out += ","
		out += raw[i]
	return ("-" if n < 0 else "") + out

# 传感器距离显示：60,000 km / 2,000 km
func _km(v: float) -> String:
	if v >= 1000.0:
		return _fmt_int(int(round(v))) + " km"
	return "%d km" % int(round(v))

func _txt(f: Font, x: float, y: float, s: String, sz: int, c: Color) -> void:
	draw_string(f, Vector2(x, y + f.get_ascent(sz)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _txt_r(f: Font, xr: float, y: float, s: String, sz: int, c: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_txt(f, xr - w, y, s, sz, c)
