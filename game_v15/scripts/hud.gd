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
const CMD_LABELS := ["STATION 保持站位", "SHADOW 跟踪伴飞", "BURN 脉冲点火"]
const PLAN_WINDOW_S := 30.0                 # 点火时间轴窗口：T+0 … T+30 s
const CMD_INSET_X := 652.0
const CMD_INNER_R := 1164.0
const ACT_Y := 910.0                        # 动作按钮行 y（与标题拉开 18px）
const ACT_H := 20.0
# 参数行（T+ / Δv / 方向），高 16
const T_MINUS := Rect2(676, 930, 20, 16)
const T_PLUS := Rect2(756, 930, 20, 16)
const DV_MINUS := Rect2(824, 930, 20, 16)
const DV_PLUS := Rect2(926, 930, 20, 16)
const DIR_CYCLE := Rect2(1104, 930, 60, 16)
# P1f：链路 / 机动两行；时间轴收紧（14px），队列详情移到左下标签页。
const TIMELINE := Rect2(652, 976, 512, 14)
# 授权 / 撤销 / 武器释放
const AUTH_BTN := Rect2(652, 994, 176, 20)
const ABORT_BTN := Rect2(836, 994, 176, 20)
const FIRE_BTN := Rect2(1020, 994, 144, 20)
const QUEUE_Y := 1020.0
const QUEUE_ROW_H := 12.0
const QUEUE_ABORT_X := 1120.0

# ── P1f/P2a：指挥官决策 / 后果 / 内部事后报告覆盖层（居中面板，V1.5 仪表风）──
const DECISION_RECT := Rect2(480, 250, 960, 560)
const CONSEQ_RECT := Rect2(560, 300, 800, 440)
const REPORT_RECT := Rect2(440, 210, 1040, 660)
const FILED_RECT := Rect2(700, 468, 520, 120)
# P2a（D2 · 07/15）：三项默认结局 HOLD / EVACUATE / EXPOSE；FIRE 单独灾难入口。
const DECISION_KINDS := ["hold", "evacuate", "expose"]
const DECISION_NAMES := ["HOLD / 坚守", "EVACUATE / 撤人", "EXPOSE / 曝光"]
const DECISION_CONSEQ := [
	"保持卡位，拒绝让出储罐区与航道，将接管程序拖入 UEG 复核。不首先开火。",
	"撤出 Chronos 人员与可移动储罐，保留记录，允许接管空间站。",
	"向 OCJC 监察与 UEG 轨道事务委员会提交可疑证据，请求联合调查。",
]
const DECISION_RUBRIC := [
	"OCU +2 · Meridian +1 · 清算者 −2",
	"OCU +1 · Meridian +2 · 清算者 −1",
	"OCJC +1 · UEG 鸽派 +2 · 清算者 −3",
]
const DECISION_FIRE := Rect2(508, 728, 904, 34)
# 08 §2：五个声望对象（显示名 + 旧键别名；state 换键后自动生效）
const REP_CANON := ["OCU", "Meridian", "UEG 鸽派", "外环", "清算者"]
const REP_ALIAS := {
	"OCU / OCJC": "OCU", "ocu": "OCU", "ocjc": "OCU", "ocu_ocjc": "OCU",
	"Meridian": "Meridian", "meridian": "Meridian", "斛港务": "Meridian",
	"UEG 鸽派": "UEG 鸽派", "ueg_dove": "UEG 鸽派", "ueg_doves": "UEG 鸽派", "UEG": "UEG 鸽派",
	"外环": "外环", "outer_ring": "外环", "outer": "外环", "远环合作社": "外环",
	"清算者": "清算者", "reclaimers": "清算者", "清算署": "清算者",
}
# 报告覆盖层按钮
const REPORT_TRUTH := Rect2(1056, 300, 396, 110)
const REPORT_FAKE := Rect2(1056, 424, 396, 110)
const CONSEQ_SUBMIT := Rect2(800, 660, 320, 40)

# ── P9a：右区选中舰 / 完整传感器架 / 损管卡 / 日志标签 / 航行准备长按 ──
const UNIT_X := 1556.0
const RACK_HEADER_Y := 512.0
const RACK_ROW_Y := 528.0
const RACK_ROW_PITCH := 16.0
const RACK_ROWS_MAX := 5
const MAST_BTN := Rect2(1556, 480, 120, 14)
const RACK_PAGE_BTN := Rect2(1796, 514, 48, 16)
const DAMAGE_CARD := Rect2(1556, 614, 288, 74)
const DAMAGE_BTN := Rect2(1556, 668, 120, 16)
const DAMAGE_POPUP := Rect2(1556, 470, 288, 190)
const LOG_TAB_COMMS := Rect2(64, 888, 168, 18)
const LOG_TAB_QUEUE := Rect2(240, 888, 168, 18)
const PRELUDE_HOLD_S := 3.0
const PRELUDE_CONFIRM_PROGRESS := Rect2(468, 592, 480, 30)

# ── P10a：右键目标菜单 / 光学通道 / 图层开关 / 队列完整文本 ─────────
const CTX_W := 360.0
const CTX_HEAD_H := 64.0
const CTX_ROW_H := 22.0
const CTX_GROUP_H := 19.0
const CTX_FOOT_H := 26.0
# tier = 需要的识别等级 L 级；opt/ir 为通道动作；locked 由目标当前 level 决定。
const TGT_TIERS := [
	[1, "L1 · 方位 / 交叉定位"],
	[2, "L2 · 距离 / 型号识别"],
	[3, "L3 · IFF / 成像通道"],
	[4, "L4 · 火控 / 武器解算"],
]
const TGT_ACTIONS := [
	[1, "cross_fix", "交叉定位 / CROSS-FIX"],
	[1, "radar_paint", "雷达照射识别 / RADAR ID"],
	[2, "classify", "型号识别 / CLASSIFY"],
	[2, "fire_solution", "火控解算 / FIRE SOLUTION"],
	[3, "iff_challenge", "IFF 问答 / CHALLENGE"],
	[3, "radar_track", "雷达跟踪 / TRACK"],
	[3, "optical", "建立光学通道 / OPTICAL"],
	[3, "ir", "建立红外通道 / IR"],
	[4, "missile_path", "导弹路径解算 / MISSILE"],
	[4, "weapons_standby", "武装待命 / WEAPONS STANDBY"],
]
const OPTICAL_RECT := Rect2(560, 220, 800, 600)
const OPT_TAB_VIS := Rect2(588, 276, 160, 24)
const OPT_TAB_IR := Rect2(752, 276, 160, 24)
const OPT_STARE_BTN := Rect2(588, 712, 200, 32)
const OPT_STOP_BTN := Rect2(800, 712, 200, 32)
const OPT_CLOSE_BTN := Rect2(1128, 712, 200, 32)
const LAYERS_RECT := Rect2(620, 300, 680, 420)
# P10a-ENG 图层键：contacts/labels/predictions/radar/stations/grid
const LAYER_KEYS := ["contacts", "labels", "predictions", "radar", "stations", "grid"]
const LAYER_NAMES := ["接触/符号 / CONTACTS", "标签文本 / LABELS", "历史·预测·轨道 / PREDICTIONS",
	"雷达/传感器层 / RADAR", "站点/基准 / STATIONS", "网格 / GRID"]
const QUEUE_DETAIL_H := 118.0

# ── P3a：窗口硬切 / 文本乱码解码（V2 一次性动效在 V1.5 的延伸；docs/09 §4.2）──
const UI_CUT_DUR := 0.32        # 80px 黑块硬切揭示（6 步硬切，无插值）
const UI_CUT_STEPS := 6
const UI_CUT_SEED := 4471
const UI_DECODE_DUR := 0.42     # 乱码→完整文本（逐字；行间错峰 ≤0.08）
const UI_DECODE_MAX_STAGGER := 0.08

# ── P3c：前置航行覆盖层（航行准备 / DEPARTURE；state.prelude_* 只读）──
const PRELUDE_RECT := Rect2(420, 210, 1080, 620)
const PRELUDE_OPT_W := 480.0
const PRELUDE_OPT_H := 150.0
const PRELUDE_OPT_GAP := 24.0
const PRELUDE_OPT_Y := 380.0
const PRELUDE_ACT_Y := 578.0
const PRELUDE_CONFIRM := Rect2(468, 578, 480, 44)
const PRELUDE_EXECUTE := Rect2(972, 578, 480, 44)
const PRELUDE_SKIP := Rect2(1252, 778, 200, 32)

# ── P1g：无线电 / 事件 feed、暂停指示、END 归档页 ──────────
const FEED_ROWS := 3
const FEED_PITCH := 12.0
const PAUSE_RECT := Rect2(1560, 912, 284, 24)
const PAUSE_MENU := Rect2(650, 300, 620, 380)
const PAUSE_BTN_RESUME := Rect2(700, 420, 520, 40)
const PAUSE_BTN_RESTART := Rect2(700, 480, 520, 40)
const PAUSE_BTN_QUIT := Rect2(700, 540, 520, 40)
const END_RECT := Rect2(420, 200, 1080, 640)
const END_RESTART := Rect2(940, 756, 260, 40)
const END_EXIT := Rect2(1216, 756, 240, 40)

# ── P1j：身份分类 / 可点开接管通知 / 副官建议 / 手册 ─────────
# 19 §2.5：六级身份（待定 + 六级分类里的 6 类）。颜色 + 形状双通道。
const ID_FALLBACK := {
	"哈马丹": "friend", "哈马丹号": "friend", "渡口": "friend", "渡口号": "friend",
	"望楼": "friend", "望楼号": "friend", "深井": "friend", "深井号": "friend",
	"远地点": "friend", "远地点号": "friend",
}
const BATCH_OF := {
	"远地点": 1000, "远地点号": 1000, "哈马丹": 1001, "哈马丹号": 1001,
	"渡口": 1002, "渡口号": 1002, "望楼": 1003, "望楼号": 1003, "深井": 1004, "深井号": 1004,
	"案卷 4471": 2001, "AV-4412 传唤者": 2001, "谷神-2": 9001, "未识别": 9002,
}
const ID_ORDER := ["pending", "unknown", "assumed_friend", "friend", "neutral", "suspect", "hostile"]
const ID_CN := {
	"pending": "待定", "unknown": "未知", "assumed_friend": "假定友好", "friend": "友方",
	"neutral": "中立", "suspect": "可疑", "hostile": "敌方",
}
const ID_EN := {
	"pending": "PENDING", "unknown": "UNKNOWN", "assumed_friend": "ASSUMED FRIEND",
	"friend": "FRIEND", "neutral": "NEUTRAL", "suspect": "SUSPECT", "hostile": "HOSTILE",
}
const ID_SHORT := {
	"pending": "待定", "unknown": "未知", "assumed_friend": "假定", "friend": "友方",
	"neutral": "中立", "suspect": "可疑", "hostile": "敌方",
}
# ── P1k：威胁等级图例（无威胁/低/中/高/确认敌对/待判定）──
const THR_ORDER := ["none", "low", "med", "high", "hostile", "pending"]
const THR_CN := {
	"none": "无威胁", "low": "低", "med": "中", "high": "高",
	"hostile": "确认敌对", "pending": "待判定",
}
const THR_EN := {
	"none": "NONE", "low": "LOW", "med": "MED", "high": "HIGH",
	"hostile": "HOSTILE", "pending": "PENDING",
}
const NOTICE_CLICK := Rect2(540, 42, 380, 22)
const NOTICE_RECT := Rect2(480, 250, 960, 480)
const ADVISOR_BTN := Rect2(1556, 848, 140, 20)
const MANUAL_BTN := Rect2(1704, 848, 140, 20)
# ── P2b：证据面板 / 穿梭机取证 / 撤人 / 副官申请 ─────────────
# 证据三项：港务遥测 / 核查组黑匣子 / 异常 ELINT；EXPOSE 需 ≥2。
const EVID_TITLE_Y := 700.0
const EVID_ROW_Y := 712.0
const EVID_ROW_H := 14.0
const EVID_BAR := Rect2(1556, 754, 288, 3)
const EVID_TASK_Y := 762.0
const EVID_MENU_Y := 772.0
const EVID_MENU_ROW := 20.0
const EVID_SHUTTLE := Rect2(1556, 796, 140, 22)
const EVID_EVAC := Rect2(1704, 796, 140, 22)
const EVID_ITEMS := [
	["telemetry", "port_telemetry", "港务遥测 / TELEMETRY"],
	["blackbox", "inspection_blackbox", "核查组黑匣子 / RECORDER"],
	["elint", "elint_signature", "异常特征码 / ELINT"],
]
const ADJUTANT_RECT := Rect2(520, 280, 880, 420)
const ADJUTANT_CLOSE := Rect2(1300, 292, 76, 18)
const ADJUTANT_OPT := Rect2(520, 280, 880, 420)  # 选项网格从 r.y+176 起算
const ADVISOR_RECT := Rect2(560, 280, 800, 400)
const MANUAL_RECT := Rect2(440, 190, 1040, 660)

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


	"长夜": "望楼",
	"塔级": "安海-1",
	"砧级": "托盘-5 改",
	"听级": "托盘-5 改",
	"代偿级": "传唤级",
	"传票级": "传唤级",
	"火力舰": "送达",
	"送达舰": "送达",
	"监督官分遣队": "OCUVF-ID13",
	"HAMADAN": "HARMATTAN",
	"LEEWARD": "LEE SHORE",
	"LONGNIGHT": "WATCHTOWER",
	"4471-K": "AV-4412 传唤者",
	"4503-R": "CA-4503",
	"接管通知 4471 号": "接管声明 · 第七号令",
	# 12 军语 P0（显示层）：未识别是状态词，不能当实体名；火控/weapons free 的正式说法。
	"未识别": "不明接触",
	"火控请求": "火力请求",
	"weapons free": "武器释放授权",
	"WEAPONS FREE": "武器释放授权",
}

# ── P1d：按舰传感器架（读 state.racks / sensor_on / fleet_emissions）──
# P3b：每行 ON/OFF chip 可操作（调 state.set_sensor）；行点击仍只切换当前模块。
func _rack_ship() -> String:
	var v = state.get("rack_ship")
	return String(v) if v != null else "harmattan"

func _rack_ship_name() -> String:
	var tr := _rack_track()
	if tr.is_empty():
		return "—"
	return _track_display_id(tr)

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

# ── P3b：ON/OFF chip 可操作（state.set_sensor；无 API 时禁用）──
func _sensor_toggle_available() -> bool:
	return state != null and state.has_method("set_sensor")

func _toggle_sensor(idx: int) -> void:
	if not _sensor_toggle_available():
		return
	var rack := _rack_rows()
	if idx < 0 or idx >= rack.size():
		return
	var s: Dictionary = rack[idx]
	var model := String(s.get("model", ""))
	var on := _rack_on(_rack_ship(), model, bool(s.get("on", true)))
	# 只调 state API（内部刷新 plan / emissions）；不改 state 字段。
	state.call("set_sensor", _rack_ship(), idx, not on)
	_sfx("sys_sensor_on" if not on else "sys_sensor_off")
	if not on and (model == "YW-R9" or model == "MK-12"):
		_sfx("sys_radar_ping")
	elif not on and model == "ELINT":
		_sfx("sys_elint")
	queue_redraw()

# 截图钩子用：把第一个「可暴露且当前关」的模块开机（用于展示「开机即暴露」）。
func _demo_toggle_first_expose() -> void:
	if not _sensor_toggle_available():
		return
	var rack := _rack_rows()
	for i in range(rack.size()):
		var s: Dictionary = rack[i]
		var model := String(s.get("model", ""))
		if bool(s.get("expose", false)) and not _rack_on(_rack_ship(), model, bool(s.get("on", true))):
			_toggle_sensor(i)
			return

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

# ── TEXT-02：接触口径（12 军语 P0-1）──
# 未识别是状态词：确认前 = 不明接触；成航迹（L2+）实体仍未识别 = 不明目标；确认虚警 = 虚警。
func _track_display_id(t: Dictionary) -> String:
	var cls := String(t.get("cls", ""))
	if cls.contains("虚警") or bool(t.get("false_alarm", false)):
		# P1k：9002 = 已交叉确认的无威胁目标，不再用「虚警」当主标签。
		return "已交叉确认"
	var raw_id := String(t.get("id", ""))
	var nm := String(t.get("name", ""))
	if nm == "" or nm == raw_id:
		nm = raw_id
	var disp := _dn(nm)
	if disp.is_valid_int():
		# P1j：批号（1000/2001/9001）不是实体名；没有 name 时退回「不明接触」。
		disp = "不明接触"
	if disp == "不明接触" and int(t.get("level", 1)) >= 2:
		return "不明目标"
	return disp

# ── TEXT-02：链路标签（14 通信与中继 §3：激光直接 → 激光中继 → 无线电 → 红外 → 可见光）──
# state 有 link_* 字段时按其显示；第一关缺省是「激光中继（望楼号 / 8 s）」。
func _link_mode_cn() -> String:
	var raw := ""
	if state != null:
		var v = state.get("link_mode")
		if v == null:
			v = state.get("link_label")
		if v != null:
			raw = String(v)
	match raw.to_lower():
		"laser_direct", "laser-direct", "direct", "laser", "ld", "激光直连", "激光直接":
			return "激光直连"
		"laser_relay", "laser-relay", "relay", "lr", "激光中继":
			return "激光中继"
		"radio", "wireless", "rdo", "无线电":
			return "无线电"
		"ir", "infrared", "红外":
			return "红外"
		"visual", "visible", "light", "vis", "可见光":
			return "可见光"
	if raw != "":
		return _dn(raw)
	return "激光中继"

func _link_latency() -> String:
	if state != null:
		var v = state.get("link_latency_s")
		if v != null:
			return "%.1f s" % float(v)
	match _link_mode_cn():
		"激光直连":
			return "0.4 s"
		"激光中继", "无线电", "红外":
			return "8 s"
		"可见光":
			return "分钟级"
	return "8 s"

# 中继损失：14 §3「8 s → 45 s，HUD 显示 LINK DEGRADED」。
func _link_degraded() -> bool:
	if state == null:
		return false
	for k in ["link_degraded", "relay_lost", "relay_destroyed"]:
		var v = state.get(k)
		if v != null and bool(v):
			return true
	return false

# ── P1j：四位数批号 + 六级身份（19 §2 / §2.5）────────────
func _track_batch(t: Dictionary) -> int:
	var v = t.get("batch")
	if v == null:
		v = t.get("designation")
	if v != null and int(v) > 0:
		return int(v)
	var id := String(t.get("id", ""))
	var key := String(t.get("name", ""))
	if BATCH_OF.has(key):
		return int(BATCH_OF[key])
	if BATCH_OF.has(id):
		return int(BATCH_OF[id])
	if String(t.get("cls", "")).contains("虚警") or id.contains("未识别"):
		return 9002
	return 0

# 身份：state.track.identity（dict/string）优先；否则按第一关初值（19 §2.5/§3）推断。
func _track_identity(t: Dictionary) -> String:
	var raw = t.get("identity")
	var key := ""
	if raw is Dictionary:
		var d: Dictionary = raw
		key = String(d.get("key", d.get("class", d.get("id", ""))))
	elif raw != null:
		key = String(raw)
	key = key.to_lower().replace("-", "_").replace(" ", "_")
	var aliases := {
		"assumed": "assumed_friend", "assumedfriend": "assumed_friend", "friend": "friend",
		"neutral": "neutral", "suspect": "suspect", "hostile": "hostile",
		"unknown": "unknown", "pending": "pending",
	}
	if aliases.has(key):
		return String(aliases[key])
	if ID_CN.has(key):
		return key
	var id := String(t.get("id", ""))
	var cls := String(t.get("cls", ""))
	var lv := int(t.get("level", 1))
	if cls.contains("虚警") or id.contains("虚警"):
		return "pending"
	if ID_FALLBACK.has(id):
		return "friend"
	if id == "谷神-2":
		return "neutral" if lv >= 3 else "unknown"
	if id == "案卷 4471" or cls.contains("传唤"):
		return "suspect" if lv >= 3 else "unknown"
	match String(t.get("side", "")):
		"friend":
			return "friend"
		"hostile":
			return "suspect"
	return "unknown"

# 六级身份中文：优先用 state.identity_label（数据层单一来源），缺失时用 HUD 表。
func _identity_cn(key: String) -> String:
	if state != null and state.has_method("identity_label"):
		var s := String(state.call("identity_label", key))
		if s != "":
			return s
	return String(ID_CN.get(key, "待定"))

func _id_color(key: String) -> Color:
	match key:
		"pending":
			return Palette.ID_PENDING
		"unknown":
			return Palette.ID_UNKNOWN
		"assumed_friend":
			return Palette.ID_ASSUMED
		"friend":
			return Palette.ID_FRIEND
		"neutral":
			return Palette.ID_NEUTRAL
		"suspect":
			return Palette.ID_SUSPECT
		"hostile":
			return Palette.ID_HOSTILE
		_:
			return Palette.DIM

# 19 §2.5：形状不只靠颜色（色盲友好）。
# 待定虚线方框 / 未知菱形 / 假定友好虚线圆 / 友方实心圆 / 中立方形 / 可疑三角 / 敌方实心菱形
func _identity_shape(c: Vector2, s: float, key: String, col: Color) -> void:
	var h := s * 0.5
	match key:
		"pending":
			var r := Rect2(c - Vector2(h, h), Vector2(s, s))
			_corners(r, h * 0.45, col)
		"unknown":
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0), c + Vector2(0, -h)
			]), col, 1.0, true)
		"assumed_friend":
			for i in range(8):
				var a0 := TAU * float(i) / 8.0
				var a1 := a0 + TAU / 16.0
				draw_arc(c, h, a0, a1, 4, col, 1.0, true)
		"friend":
			draw_circle(c, h, col)
		"neutral":
			draw_rect(Rect2(c - Vector2(h, h), Vector2(s, s)), col, false, 1.0)
		"suspect":
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, h), c + Vector2(-h, h), c + Vector2(0, -h)
			]), col, 1.0, true)
		"hostile":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)
			]), col)
		_:
			draw_circle(c, h * 0.6, col)

func _identity_chip(rc: Rect2, key: String, dim := 1.0, short := false) -> void:
	var col := _id_color(key)
	var label := String(ID_SHORT.get(key, "待定")) if short else _identity_cn(key)
	var w := cjk.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var tx := rc.end.x - w
	_txt(cjk, tx, rc.position.y, label, 7, Palette.a(col, 0.95 * dim))
	_identity_shape(Vector2(tx - 9.0, rc.position.y + 5.0), 8.0, key, Palette.a(col, dim))

func _identity_legend_chip(rc: Rect2, key: String) -> void:
	var col := _id_color(key)
	var label := String(ID_SHORT.get(key, "待定"))
	draw_rect(rc, Palette.a(col, 0.04))
	draw_rect(rc, Palette.a(col, 0.22), false, 1.0)
	_identity_shape(Vector2(rc.position.x + 9.0, rc.position.y + 8.0), 8.0, key, Palette.a(col, 0.9))
	_txt(cjk, rc.position.x + 17.0, rc.position.y + 3.0, label, 7, Palette.a(col, 0.9))

# ── P1k：威胁等级（无威胁/低/中/高/确认敌对/待判定）────────
# 优先读 track.threat / threat_level；否则按身份/批号推断第一关（不新增数据）。
func _track_threat(t: Dictionary) -> String:
	var raw := ""
	if t.has("threat"):
		raw = String(t.get("threat", ""))
	elif t.has("threat_level"):
		raw = String(t.get("threat_level", ""))
	raw = raw.to_lower().replace("-", "_").replace(" ", "_")
	var alias := {
		"none": "none", "no_threat": "none", "无威胁": "none",
		"low": "low", "低": "low",
		"med": "med", "medium": "med", "中": "med",
		"high": "high", "高": "high",
		"hostile": "hostile", "confirmed_hostile": "hostile", "确认敌对": "hostile",
		"pending": "pending", "unknown": "pending", "待判定": "pending",
	}
	if alias.has(raw):
		return String(alias[raw])
	if t.get("false_alarm", false) or String(t.get("cls", "")).contains("虚警"):
		return "none"
	if t.get("own", false):
		return "none"
	var ident := _track_identity(t)
	match ident:
		"friend":
			return "none"
		"neutral":
			return "low"
		"suspect":
			return "high"
		"hostile":
			return "hostile"
		"pending", "unknown":
			return "pending"
		_:
			return "pending"

func _threat_color(key: String) -> Color:
	match key:
		"none":
			return Palette.THR_NONE
		"low":
			return Palette.THR_LOW
		"med":
			return Palette.THR_MED
		"high":
			return Palette.THR_HIGH
		"hostile":
			return Palette.THR_HOSTILE
		_:
			return Palette.THR_PENDING

# 威胁形状：无威胁 空心圆 / 低 实心小圆 / 中 菱形框 / 高 三角框 / 确认敌对 实心菱形 / 待判定 虚线框。
func _threat_shape(c: Vector2, s: float, key: String, col: Color) -> void:
	var h := s * 0.5
	match key:
		"none":
			draw_arc(c, h, 0, TAU, 16, col, 1.0, true)
		"low":
			draw_circle(c, h * 0.55, col)
		"med":
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0), c + Vector2(0, -h)
			]), col, 1.0, true)
		"high":
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, h), c + Vector2(-h, h), c + Vector2(0, -h)
			]), col, 1.0, true)
		"hostile":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)
			]), col)
		_:
			_corners(Rect2(c - Vector2(h, h), Vector2(s, s)), h * 0.45, col)

func _threat_legend_chip(rc: Rect2, key: String) -> void:
	var col := _threat_color(key)
	draw_rect(rc, Palette.a(col, 0.04))
	draw_rect(rc, Palette.a(col, 0.22), false, 1.0)
	_threat_shape(Vector2(rc.position.x + 9.0, rc.position.y + 8.0), 8.0, key, Palette.a(col, 0.95))
	_txt(cjk, rc.position.x + 19.0, rc.position.y + 1.0, String(THR_CN.get(key, "待判定")), 7, Palette.a(col, 0.95))
	_txt(mono, rc.position.x + 19.0, rc.position.y + 10.0, String(THR_EN.get(key, "PENDING")), 6, Palette.a(col, 0.6))

# 通信流：19 §1 格式 [发信者至收信者]-[LD/LR/RDO/IR/VIS]-[内容]
func _comms_mode_short(mode: String) -> String:
	match mode.to_lower():
		"laser_direct", "laser-direct", "ld", "激光直连", "激光直接":
			return "LD"
		"laser_relay", "laser-relay", "lr", "激光中继":
			return "LR"
		"radio", "rdo", "无线电":
			return "RDO"
		"ir", "infrared", "红外":
			return "IR"
		"visual", "visible", "vis", "可见光":
			return "VIS"
		_:
			return mode.to_upper() if mode != "" else "LD"

func _comms_format(e: Dictionary) -> String:
	var text := String(e.get("text", ""))
	var from := String(e.get("from", ""))
	var to := String(e.get("to", ""))
	var mode := String(e.get("mode", ""))
	if from == "":
		return text
	# 缺字段时从文本推断（兼容旧 radio_lines：from + text，链路写在文本里）
	if to == "":
		to = "全体" if text.begins_with("全队") or text.contains("全队。") else "远地点"
	if mode == "":
		if text.contains("公开频道") or text.contains("法律广播"):
			mode = "RDO"
		elif text.contains("经望楼中继") or text.contains("激光中继"):
			mode = "LR"
		elif text.contains("激光直连") or text.contains("激光直接"):
			mode = "LD"
		elif text.contains("红外"):
			mode = "IR"
		else:
			mode = "LD"
	return "[%s至%s]-[%s]-[%s]" % [_dn(from), _dn(to), _comms_mode_short(mode), _dn(text)]

func _mmss(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%02d:%02d" % [s / 60, s % 60]

# ── P1j：模态窗口（通知 / 副官建议 / 手册）─────────────────
func _open_modal(kind: String) -> void:
	if state == null or state.boot_t < 1.7:
		return
	if _any_overlay():
		return
	_modal = kind
	_sfx("ui_open")
	if kind == "notice":
		_sfx("sys_comms_rx")
	_modal_prev_paused = bool(state.paused)
	state.paused = true
	queue_redraw()

func _close_modal() -> void:
	if _modal == "advisor":
		_advisor_read = true
	_modal = ""
	_sfx("ui_close")
	if state != null:
		state.paused = _modal_prev_paused
	queue_redraw()

func _draw_modal_overlay() -> void:
	match _modal:
		"notice":
			_draw_notice_overlay()
		"advisor":
			_draw_advisor_overlay()
		"manual":
			_draw_manual_overlay()

func _handle_modal_click(p: Vector2) -> void:
	# 点面板外或关闭按钮关闭。
	var r := NOTICE_RECT
	if _modal == "advisor":
		r = ADVISOR_RECT
	elif _modal == "manual":
		r = MANUAL_RECT
	if not r.has_point(p):
		_close_modal()
		return
	var close_rect := Rect2(r.end.x - 200.0, r.end.y - 44.0, 184.0, 28.0)
	if close_rect.has_point(p):
		_close_modal()

func _notice_parts() -> Dictionary:
	# P2a（15 §4.1）：接管声明 · 第七号轨道紧急托管令；优先读 state.notice，旧文本在显示层归一。
	var title := "接管声明 · 第七号轨道紧急托管令"
	var body := ""
	var from := "AV-4412 传唤者"
	var to := "远地点号"
	var mode := "RDO"
	if state != null:
		var nv = state.get("notice")
		if nv is Dictionary and not (nv as Dictionary).is_empty():
			var nd: Dictionary = nv
			var t_in := String(nd.get("title", ""))
			if t_in != "":
				title = _d2_text(t_in)
			body = String(nd.get("body", ""))
			from = String(nd.get("from", from))
			to = String(nd.get("to", to))
			mode = String(nd.get("mode", mode))
	if body != "":
		body = _d2_text(body)
	if body == "" and state != null:
		var rl = state.get("radio_feed")
		if rl is Array:
			for raw in (rl as Array):
				if not (raw is Dictionary):
					continue
				var rd: Dictionary = raw
				var rf := String(rd.get("from", ""))
				if rf == "案卷 4471" or rf.begins_with("AV-4412"):
					from = rf
					to = String(rd.get("to", to))
					mode = String(rd.get("mode", mode))
					var text := String(rd.get("text", ""))
					body = _d2_text("[%s至%s]-[%s]-[%s]" % [rf, to, _comms_mode_short(mode), text])
					break
	if body == "":
		body = "UEG 海关格林尼治公告：依据《轨道宪章》与第七号轨道紧急托管令，凡失能、受威胁或被敌方渗透的加注站、储罐、船坞与航道，可由联合政府指定部队接管，直至紧急状态结束。Chronos 加注站及储罐区处于紧急状态范围。接管程序由第33轨道特别独立舰队执行。"
	return {"title": title, "body": body, "from": from, "to": to,
		"mode": _comms_mode_short(mode), "t": 0.0}

func _draw_notice_overlay() -> void:
	_overlay_dim()
	var r := NOTICE_RECT
	var info := _notice_parts()
	var body := String(info["body"])
	var lines := _wrap_text(cjk, body, 10, r.size.x - 48.0)
	var base := r.position.y + 238.0 + float(mini(lines.size(), 8)) * 18.0 + 12.0
	r.size.y = clampf(base + 96.0 - r.position.y, 380.0, 620.0)
	_overlay_frame(r, _dtext("接管声明 / ORDER 7 NOTICE"), "2001 · AV-4412 · %s · 法律广播" % String(info["mode"]))
	_txt(cjk, r.position.x + 24.0, r.position.y + 56.0, _dtext(String(info["title"])), 13, Palette.AMBER)
	_txt_r(cjk, r.end.x - 24.0, r.position.y + 56.0, "Greenwich · L1-01 · UEG 海关", 7, Palette.FAINT)
	_txt(cjk, r.position.x + 24.0, r.position.y + 74.0, "第七号轨道紧急托管令（Order 7）· 发布第 9 天 · L1 Meridian-05 Chronos", 8, Palette.DIM)
	# 元数据
	var meta := [
		["发信 / FROM", "%s（第33舰队 · 清算者）" % _d2_text(String(info["from"]))],
		["收信 / TO", "%s · OCUVF-ID13 指挥官" % _d2_text(String(info["to"]))],
		["通信方式", "%s 无线电 · 公开频道（法律广播）" % String(info["mode"])],
		["批号 / 身份", "[2001] 未知 → 可疑（光学分类后）"],
	]
	for i in range(meta.size()):
		var y := r.position.y + 100.0 + float(i) * 22.0
		_txt(cjk, r.position.x + 24.0, y, meta[i][0], 7, Palette.FAINT)
		_txt(cjk, r.position.x + 200.0, y - 2.0, meta[i][1], 9, Palette.TXT)
	# 正文（19 §1 格式的通信记录）
	draw_line(Vector2(r.position.x + 24.0, r.position.y + 200.0), Vector2(r.end.x - 24.0, r.position.y + 200.0), Palette.a(Palette.AMBER, 0.4), 1.0)
	_txt(cjk, r.position.x + 24.0, r.position.y + 208.0, "正文 / BODY", 7, Palette.FAINT)
	var dlines := _dlines(lines)
	for i in range(mini(dlines.size(), 8)):
		_txt(cjk, r.position.x + 24.0, r.position.y + 228.0 + float(i) * 18.0, String(dlines[i]), 10, Palette.a(Palette.TXT, 0.95))
	# 程序
	_txt(cjk, r.position.x + 24.0, base, "程序 / PROCEDURE", 7, Palette.FAINT)
	_txt(cjk, r.position.x + 24.0, base + 18.0, "· 第七号轨道紧急托管令（Order 7）· 第九天；本关为 6 分钟执行窗口。", 8, Palette.DIM)
	_txt(cjk, r.position.x + 24.0, base + 34.0, "· 处置在「指挥官决策」面板：HOLD / EVACUATE / EXPOSE；FIRE 是灾难分支，本声明只读。", 8, Palette.DIM)
	_txt(cjk, r.position.x + 24.0, base + 50.0, "· 打开本窗口时模拟暂停；关闭后恢复执行窗口倒计时。", 8, Palette.DIM)
	# 关闭按钮
	var close_rect := Rect2(r.end.x - 200.0, r.end.y - 44.0, 184.0, 28.0)
	_cmd_btn(close_rect, "关闭 / CLOSE", false, Palette.PH)
	_txt_r(cjk, r.end.x - 24.0, r.end.y - 22.0, "点击面板外或 ESC/关闭 返回", 7, Palette.FAINT)
	_draw_window_cut(r)

func _advisor_text() -> String:
	if state != null:
		var v = state.get("advisor_text")
		if v != null and String(v) != "":
			return String(v)
	return "长官，我个人建议：\n· 接触时先看批号与身份：未知不等于敌对目标；IFF 无应答时威胁等级只能排到「未知/可疑」，判敌需要证据与 ROE 支持。\n· 下达跟踪/变轨指令：激光直连最快，有中继时只需 8 s。\n· 指令生效前可随时撤销待生效命令；下令前注意倒计时。"

func _manual_sections() -> Array:
	if state != null:
		var v = state.get("manual_sections")
		if v is Array and (v as Array).size() > 0:
			return v
	return [
		["指挥 / COMMAND", "选择舰只 → 选择意图（保持站位 / 跟踪伴飞 / 脉冲点火）；命令经链路延迟生效，生效前可撤销。"],
		["变轨 / BURN", "时间轴点火节点须授权才可执行。Δv 是不可再生资源，注意管理。"],
		["目标识别 / ID", "L1–L4 是目标信息深度；身份判定分开显示。"],
		["交战 / ROE", "仅自卫原则 / WEAPONS HOLD；武器释放授权需二次确认；开火需承担后果。"],
		["辐射控制 / EMCON", "开机暴露风险：主动雷达/IFF 会被 ELINT 截获；被动模块则可 24 h 开机。"],
		["损管 / DAMAGE CONTROL", "战损与传感器状态分开记录；损管队列按优先级排序。"],
	]

func _draw_advisor_overlay() -> void:
	_overlay_dim()
	var r := ADVISOR_RECT
	_overlay_frame(r, _dtext("副官建议 / ADJUTANT"), "一次性")
	var lines := _wrap_text(cjk, _advisor_text(), 10, r.size.x - 48.0)
	var dlines := _dlines(lines)
	for i in range(mini(dlines.size(), 12)):
		_txt(cjk, r.position.x + 24.0, r.position.y + 64.0 + float(i) * 22.0, String(dlines[i]), 10, Palette.a(Palette.TXT, 0.95))
	_txt(cjk, r.position.x + 24.0, r.end.y - 62.0, "该建议只在第一次遇到相应机制时出现；之后可在「手册」里复查。", 8, Palette.DIM)
	var close_rect := Rect2(r.end.x - 200.0, r.end.y - 44.0, 184.0, 28.0)
	_cmd_btn(close_rect, "知道了 / GOT IT", false, Palette.PH)
	_draw_window_cut(r)

func _draw_manual_overlay() -> void:
	_overlay_dim()
	var r := MANUAL_RECT
	_overlay_frame(r, _dtext("教学手册 / MANUAL"), "章节可反复查阅")
	var secs := _manual_sections()
	for i in range(mini(secs.size(), 6)):
		var row: Array = secs[i]
		var y := r.position.y + 64.0 + float(i) * 92.0
		var title := String(row[0]) if row.size() > 0 else "—"
		var text := String(row[1]) if row.size() > 1 else ""
		draw_rect(Rect2(r.position.x + 20.0, y - 8.0, r.size.x - 40.0, 80.0), Palette.a(Palette.PANEL2, 0.35))
		draw_rect(Rect2(r.position.x + 20.0, y - 8.0, 2.0, 80.0), Palette.a(Palette.PH, 0.5))
		_txt(cjk, r.position.x + 34.0, y + 2.0, _dtext("%02d %s" % [i + 1, title]), 10, Palette.PH)
		var lines := _wrap_text(cjk, _dn(text), 8, r.size.x - 90.0)
		var dlines := _dlines(lines)
		for k in range(mini(dlines.size(), 3)):
			_txt(cjk, r.position.x + 34.0, y + 22.0 + float(k) * 15.0, String(dlines[k]), 8, Palette.a(Palette.TXT, 0.9))
	var close_rect := Rect2(r.end.x - 200.0, r.end.y - 44.0, 184.0, 28.0)
	_cmd_btn(close_rect, "关闭 / CLOSE", false, Palette.PH)
	_draw_window_cut(r)

var state
var mono: Font
var cjk: Font
var row_rects: Array[Rect2] = []
var time_rects: Array[Rect2] = []
var menu_rects: Array[Rect2] = []
var menu_open := false
var menu_t := 0.0
var _t := 0.0
var _rack_chip_rects: Array = []      # P3b：[{rect, idx, model}]（每帧重建）
var _demo_sensor_menu := false
var _demo_sensor_toggle := false
# P3c：前置航行覆盖层（state 未落地时的本地演示态；state 字段存在时以 state 为准）
var _demo_prelude := false
var _demo_pre_step := 0
var _demo_pre_route := ""
var _demo_pre_window := ""
var _demo_pre_confirmed := false
var _demo_pre_hint := ""
var _prelude_was_open := false
var _prelude_close_t := 0.0            # 执行/跳过后的全屏 80px 硬切揭场
var _prelude_skipped := false
var _prelude_local_confirmed := false
var _prelude_hint_text := ""

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
var pause_open := false
var _pause_prev := false

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

# P1g：无线电/事件 feed、END 归档
var _demo_end := false
var _demo_radio := false
var _feed_sig := ""
var _feed_flash := 0.0

# P1j：模态窗口（通知 / 副官建议 / 手册）与裁决回复
var _modal := ""                       # "" | "notice" | "advisor" | "manual"
var _modal_prev_paused := false
var _advisor_read := false
var _local_comms: Array = []           # 裁决回复（本地追加到通信流）
var _reply_added_for := ""             # 已追加回复的裁决（避免重复）
var _decision_fire_confirm := 0.0      # P2a：决策层 FIRE 二次确认倒计时
var _demo_modal := ""                  # DSH_UI 截图钩子（等 boot 完成后再开）
# P2b：证据 / 穿梭机任务 / 副官申请（state 新 API 未就绪时的本地演示态）
var _demo_evidence := false
var _demo_adjutant := false
var _evidence_menu_open := false
var _demo_ev: Dictionary = {}          # {"telemetry":true,...}
var _demo_task: Dictionary = {}        # {"kind","label","t0","duration_s","done"}
var _demo_evac: Dictionary = {}        # {"t0","duration_s","done"}
var _adj_was_open := false
var _adj_prev_paused := false
var _demo_suppress_adjutant := false   # 仅 DSH_UI 截图：state 自动弹副官时临时隐藏
# P3a：窗口硬切 / 文本解码（独立一次性计时器；不许拿全局 _t 当计时器）
var _ui_id := ""                       # 当前顶层窗口标识（"" = 无）
var _ui_t := 0.0                       # 自窗口打开计时（窗口变化重置）
var _ui_sample_t := -1.0               # DSH_UI_T：截图时冻结到该时刻（<0 表示实时）
var _ui_cut_sample_t := -1.0           # DSH_UI_CUT：只冻结硬切（截图解码中间态时跳过硬切）
var _evid_anim_t := 0.0                # 证据面板 n/3 与任务行的解码计时
var _evid_sig := ""
# P9a：右区/日志/损管/航行准备本地 UI 状态
var _rack_page := 0
var _damage_open := false
var _log_tab := 0                      # 0 = 通信流/事件 · 1 = 命令队列
var _log_abort_rects: Array = []       # [{rect, id}]
var _prelude_hold := 0.0
var _prelude_hold_done := false
var _prelude_hold_seen := false
var _last_sel := -1
# P10a：右键菜单 / 光学通道 / 图层 / 队列完整文本
var _ctx_open := false
var _ctx_pos := Vector2(900.0, 360.0)
var _ctx_track_id := ""
var _ctx_hint := ""
var _optical_open := false
var _optical_kind := "VIS"
var _optical_target := ""
var _optical_stare := 0.0
var _optical_state_note := ""
var _layers_open := false
var _layer_state := {"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true}
var _ctx_actions: Array = []
var _queue_detail_id := ""
var _queue_detail_abort_rect := Rect2()
var _log_row_rects: Array = []
var _rclick_prev := false
var _toast_text := ""
var _toast_t := 0.0

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
			_demo_suppress_adjutant = true
		"consequence":
			_demo_consequence = true
			_demo_suppress_adjutant = true
		"report":
			_demo_report = true
			_demo_suppress_adjutant = true
		"end":
			_demo_end = true
			_decision_done = true
			_demo_suppress_adjutant = true
		"radio":
			_demo_radio = true
		"notice":
			_demo_modal = "notice"
		"advisor":
			_demo_modal = "advisor"
		"manual":
			_demo_modal = "manual"
		"evidence":
			# P2b 截图：1/3 证据 + 穿梭机任务进行中 + 取证菜单展开（本地演示）
			_demo_evidence = true
			_demo_suppress_adjutant = true
			_demo_ev = {"telemetry": true}
			_demo_task = {"kind": "blackbox", "label": "核查组黑匣子", "t0": 0.0, "duration_s": 96.0, "done": false}
			_evidence_menu_open = true
		"adjutant":
			_demo_adjutant = true
		"sensor_menu":
			# P3b 截图：展开传感器架菜单；DSH_SENSOR_TOGGLE=1 时把第一个可暴露模块开机。
			_demo_sensor_menu = true
			_demo_suppress_adjutant = true
			_demo_sensor_toggle = OS.get_environment("DSH_SENSOR_TOGGLE") != ""
		"prelude":
			# P3c 截图：航行准备 Step 0（state 无 prelude 字段时用本地演示态）。
			_demo_prelude = true
			_demo_suppress_adjutant = true
			var demo_step := OS.get_environment("DSH_PRELUDE_STEP")
			if demo_step != "":
				_demo_pre_step = clampi(int(demo_step), 0, 2)
		"clean":
			# P4 截图：正常 HUD 默认态，仅抑制 capture 时自动弹出的副官申请窗口。
			_demo_suppress_adjutant = true
		"ctx":
			# P10a 截图：右键目标菜单（默认 L1 目标；DSH_SELECT 可切目标）。
			_demo_suppress_adjutant = true
			_ctx_open = true
			_ctx_pos = Vector2(820, 320)
			_ctx_actions.clear()
			_ctx_track_id = ""
		"optical":
			# P10a 截图：光学通道（凝视中）。
			_demo_suppress_adjutant = true
			_optical_open = true
			_optical_kind = OS.get_environment("DSH_OPT_KIND")
			if _optical_kind == "":
				_optical_kind = "VIS"
			_optical_target = ""
			_optical_stare = 0.42
			_optical_state_note = "截图演示：channel_status() 进度；真实接口 start_optical_track/start_ir_track"
		"layers":
			# P10a 截图：图层/元素开关面板。
			_demo_suppress_adjutant = true
			_layers_open = true
		"queue_detail":
			# P10a 截图：命令队列行展开完整文本。
			_demo_suppress_adjutant = true
			_log_tab = 1
			_queue_detail_id = "CMD-01"
		"pause":
			pause_open = true
			_demo_suppress_adjutant = true
	# P9a 截图钩子：日志/队列页签、损管详情、航行准备长按已充能。
	var ltab := OS.get_environment("DSH_LOG_TAB")
	if ltab != "":
		_log_tab = clampi(int(ltab), 0, 1)
	if OS.get_environment("DSH_DAMAGE") != "":
		_damage_open = true
	if OS.get_environment("DSH_PRELUDE_HOLD") != "":
		_prelude_hold_done = true
		_prelude_hold = PRELUDE_HOLD_S
	if OS.get_environment("DSH_SELECT") != "":
		_rack_page = 0
	# 记录初始选中，避免第一帧 _process 把 DSH_DAMAGE 等截图状态复位。
	if state != null:
		_last_sel = int(state.selected)
		# P10a-ENG：图层初始状态从 state 读取（plot 已按同名键跳过绘制）。
		if state.has_method("is_layer_visible"):
			for k in LAYER_KEYS:
				_layer_state[k] = bool(state.call("is_layer_visible", String(k)))
	# P3a：截图时把动效冻结到指定时刻（秒），用于逐帧截取硬切/解码中间态。
	var ut := OS.get_environment("DSH_UI_T")
	if ut != "":
		_ui_sample_t = maxf(0.0, float(ut))
	var ct := OS.get_environment("DSH_UI_CUT")
	if ct != "":
		_ui_cut_sample_t = maxf(0.0, float(ct))

func _process(delta: float) -> void:
	_t += delta
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
	if _optical_open and _optical_stare < 1.0 and not state.capture and not (state != null and state.has_method("channel_status")):
		_optical_stare = minf(1.0, _optical_stare + delta / 2.5)
	if not state.capture and state.boot_t >= 1.7:
		_poll_right_click()
	# P10a：暂停/覆盖层优先——打开时关掉战术弹窗，避免层级打架。
	if pause_open or _any_overlay() or _modal != "" or _ov_prelude() or _ov_adjutant() \
			or _ov_decision() or _ov_report() or _ov_consequence() or _ov_end():
		_ctx_open = false
		_ctx_actions.clear()
		_optical_open = false
		_layers_open = false
	# P3a：窗口硬切/解码计时 —— 窗口标识变化时重置（一次性；与全局 _t 无关）。
	var wid := _window_id()
	if wid != _ui_id:
		_ui_id = wid
		_ui_t = 0.0
	elif _ui_id != "":
		_ui_t = minf(_ui_t + delta, 6.0)
	# P3a：证据面板 n/3 / 任务行：内容变化时重新乱码→解码（剩余秒数连续变化，不参与判定）。
	var ev_task := _shuttle_task()
	var esig := "%d|%s|%s" % [_evidence_count(), String(ev_task.get("label", "")), str(bool(ev_task.get("active", false)))]
	if esig != _evid_sig:
		_evid_sig = esig
		_evid_anim_t = 0.0
	else:
		_evid_anim_t = minf(_evid_anim_t + delta, 6.0)
	# P9a：选中舰变化 → 传感器架翻页/损管详情复位。
	if state != null and int(state.selected) != _last_sel:
		_last_sel = int(state.selected)
		_rack_page = 0
		_damage_open = false
		_evidence_menu_open = false
	# P9a：航行准备 Step 2 —— 左按钮长按 3s 解锁执行（松开取消）。
	if _ov_prelude():
		var pd := _prelude_data()
		if int(pd["step"]) == 2:
			var held := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE) \
				or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and PRELUDE_CONFIRM.has_point(_mouse_base()))
			if _prelude_hold_done:
				_prelude_hold = PRELUDE_HOLD_S
			elif held:
				_prelude_hold = minf(PRELUDE_HOLD_S, _prelude_hold + delta)
				if _prelude_hold >= PRELUDE_HOLD_S:
					_prelude_hold_done = true
					_sfx("ui_confirm")
			else:
				_prelude_hold = 0.0
		else:
			_prelude_hold = 0.0
			_prelude_hold_done = false
	# P9a：左下日志/队列标签（Tab）。
	if not _any_overlay() and _modal == "" and not _ov_prelude() and not _ov_adjutant():
		var tdn := Input.is_key_pressed(KEY_TAB)
		var twas := bool(_key_prev.get(KEY_TAB, false))
		_key_prev[KEY_TAB] = tdn
		if tdn and not twas:
			_log_tab = 1 - _log_tab
			_sfx("ui_click")
	if _demo_modal != "" and state.boot_t >= 1.7 and _modal == "":
		var m := _demo_modal
		_demo_modal = ""
		_open_modal(m)
	# P3b 截图钩子：boot 结束后展开传感器架菜单（一次性）。
	if _demo_sensor_menu and state.boot_t >= 1.7 and not menu_open:
		menu_open = true
		menu_t = 0.0
		_demo_sensor_menu = false
		if _demo_sensor_toggle:
			_demo_sensor_toggle = false
			_demo_toggle_first_expose()
	# P3c：前置航行覆盖层 —— 键盘、跳过钩子、执行/跳过后的全屏硬切揭场。
	var prelude_now := _ov_prelude()
	if prelude_now:
		_poll_prelude_keys()
		if OS.get_environment("DSH_SKIP_PRELUDE") != "" and not _prelude_skipped:
			_prelude_skipped = true
			_prelude_skip()
	if _prelude_was_open and not _ov_prelude():
		_prelude_close_t = UI_CUT_DUR
		_prelude_hint_text = ""
		_prelude_hold = 0.0
		_prelude_hold_done = false
	_prelude_was_open = _ov_prelude()
	if _prelude_close_t > 0.0:
		_prelude_close_t = maxf(0.0, _prelude_close_t - delta)
	# P2b：副官申请打开时暂停（记录原 paused，关掉恢复）。
	if state != null and state.boot_t >= 1.7:
		var adj_now := _ov_adjutant()
		if adj_now and not _adj_was_open:
			_adj_prev_paused = bool(state.paused)
			state.paused = true
			_adj_was_open = true
		elif not adj_now and _adj_was_open:
			state.paused = _adj_prev_paused
			_adj_was_open = false
	# P9a：副官申请可连续选择（ENG 已让 ack 后保持打开）；ESC = 暂不处理关闭。
	if _ov_adjutant() and state != null and state.boot_t >= 1.7:
		var esc_down := Input.is_key_pressed(KEY_ESCAPE)
		var esc_was := bool(_key_prev.get(KEY_ESCAPE, false))
		_key_prev[KEY_ESCAPE] = esc_down
		if esc_down and not esc_was:
			_ack_adjutant("decline")
	# P1j/P2a：裁决回复进通信流 —— 无论裁决来自 HUD 点击/按键还是 main 的 1/2/3 键（后者直调 state），
	# 都按 state.outcome 的 D2 视图补一次（幂等）。
	if state != null:
		if float(state.tau()) < 1.0 and _reply_added_for != "":
			_reply_added_for = ""
			_local_comms.clear()
		var oc := String(state.get("outcome"))
		if oc != "" and _reply_added_for != _d2_kind_of(oc):
			_append_decision_reply(oc)
	if menu_open:
		menu_t += delta
	if _fire_confirm_t > 0.0:
		_fire_confirm_t = maxf(0.0, _fire_confirm_t - delta)
	if _decision_fire_confirm > 0.0:
		_decision_fire_confirm = maxf(0.0, _decision_fire_confirm - delta)
	if _filed_t > 0.0:
		_filed_t = maxf(0.0, _filed_t - delta)
	if _feed_flash > 0.0:
		_feed_flash = maxf(0.0, _feed_flash - delta)
	# P1g：END 归档页的退出键 E（R 重开由 main.gd 的 END 分支处理；main 用 X 退出）。
	if _ov_end() and state.boot_t >= 1.7:
		var ed := Input.is_key_pressed(KEY_E)
		var ew := bool(_key_prev.get(KEY_E, false))
		_key_prev[KEY_E] = ed
		if ed and not ew:
			_quit_demo()
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
	# P10a：战术弹窗（右键菜单 / 光学通道 / 图层开关）画在 HUD 之上、覆盖层之下。
	if _ctx_open:
		_draw_ctx_menu()
	if _layers_open:
		_draw_layers_panel()
	if _optical_open:
		_draw_optical_overlay()
	if _toast_t > 0.0:
		_draw_toast()
	# P1f/P1g：覆盖层画在最上层（含 dim）；END > 报告 > 后果 > 裁决，互斥不重复。
	if _ov_end():
		_draw_end_overlay()
	elif _ov_report():
		_draw_report_overlay()
	elif _ov_consequence():
		_draw_consequence_overlay()
	elif _ov_decision():
		_draw_decision_overlay()
	if _filed_t > 0.0 and not _ov_end():
		_draw_filed_banner()
	# P1j：通知 / 副官建议 / 手册（模态，打开时暂停）。
	if _modal != "":
		_draw_modal_overlay()
	# P2b：副官申请（独立 UI，打开时暂停；不进通信流）。
	if _ov_adjutant():
		_draw_adjutant_overlay()
	# P3c：前置航行（最顶层，P3a 硬切/解码）；执行/跳过后的全屏 80px 硬切揭场。
	if _ov_prelude():
		_draw_prelude_overlay()
	if _prelude_close_t > 0.0:
		_draw_window_cut(Rect2(0, 0, 1920, 1080), UI_CUT_DUR - _prelude_close_t)
	# P1g：暂停指示画在覆盖层之上（否则会被 dim 压暗），时标处常驻可见。
	_draw_pause_badge()
	if pause_open:
		_draw_pause_menu()

# P1g：decision / consequence / report / END 时，时标处显示 PAUSED · 裁决/报告/归档。
func _draw_pause_badge() -> void:
	var pl := _pause_label()
	if pl == "":
		return
	var pr := PAUSE_RECT
	draw_rect(pr, Color(0.02, 0.05, 0.04, 0.92))
	draw_rect(pr, Palette.a(Palette.AMBER, 0.85), false, 1.0)
	var pblink := 0.55 + 0.45 * sin(_t * 5.0)
	draw_rect(Rect2(pr.position.x + 12.0, pr.position.y + 9.0, 2.0, 6.0), Palette.a(Palette.AMBER, pblink))
	_txt(cjk, pr.position.x + 22.0, pr.position.y + 5.0, "PAUSED · " + pl, 10, Palette.a(Palette.AMBER, 0.98))
	_txt_r(mono, pr.end.x - 12.0, pr.position.y + 6.0, "SIM FROZEN", 7, Palette.a(Palette.AMBER, 0.6))

func open_pause() -> void:
	# P10a：Esc 层级——先关战术弹窗（右键菜单 / 光学 / 图层 / 队列展开），再开暂停。
	if _close_top_popup():
		return
	if pause_open:
		return
	pause_open = true
	_pause_prev = bool(state.paused)
	state.paused = true
	_sfx("ui_open")

func close_pause() -> void:
	if not pause_open:
		return
	pause_open = false
	if state != null:
		state.paused = _pause_prev
	_sfx("ui_back")

func _handle_pause_click(p: Vector2) -> void:
	if PAUSE_BTN_RESUME.has_point(p):
		close_pause()
		return
	if PAUSE_BTN_RESTART.has_point(p):
		close_pause()
		state.restart_demo()
		_sfx("ui_confirm")
		return
	if PAUSE_BTN_QUIT.has_point(p):
		get_tree().quit()
		return
	if not PAUSE_MENU.has_point(p):
		close_pause()

func _draw_pause_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color(0.01, 0.02, 0.018, 0.78))
	var r := PAUSE_MENU
	draw_rect(r, Palette.a(Palette.PANEL, 0.99))
	draw_rect(r, Palette.a(Palette.AMBER, 0.65), false, 1.0)
	_txt(cjk, r.position.x + 28.0, r.position.y + 34.0, "暂停 / PAUSED", 18, Palette.AMBER)
	_txt(mono, r.position.x + 28.0, r.position.y + 58.0, "SIMULATION FROZEN · OCUVF-ID13", 8, Palette.a(Palette.FAINT, 0.9))
	draw_line(Vector2(r.position.x, r.position.y + 76.0), Vector2(r.end.x, r.position.y + 76.0), Palette.a(Palette.LINE, 0.7), 1.0)
	_cmd_btn(PAUSE_BTN_RESUME, "继续 / RESUME", false, Palette.PH)
	_cmd_btn(PAUSE_BTN_RESTART, "重新开始 / RESTART", false, Palette.AMBER)
	_cmd_btn(PAUSE_BTN_QUIT, "退出 / QUIT", false, Palette.RED)
	_txt(cjk, r.position.x + 28.0, r.end.y - 32.0, "ESC 继续 · R 重新开始 · X 退出", 8, Palette.a(Palette.FAINT, 0.9))
	_txt_r(mono, r.end.x - 28.0, r.end.y - 32.0, "PAUSE · NOT IN COMMS", 7, Palette.a(Palette.FAINT, 0.6))

func _sfx(n: String) -> void:
	if state == null or state.capture:
		return
	var a := get_node_or_null("/root/Audio")
	if a != null:
		a.call("sfx", n)

func click(p: Vector2) -> void:
	if state.boot_t < 1.7:
		return
	if pause_open:
		_handle_pause_click(p)
		return
	# P10a：战术弹窗优先吃点击（右键菜单 / 光学通道 / 图层 / 队列展开）。
	if _ctx_open:
		_handle_ctx_click(p)
		queue_redraw()
		return
	if _optical_open:
		_handle_optical_click(p)
		queue_redraw()
		return
	if _layers_open:
		_handle_layers_click(p)
		queue_redraw()
		return
	if _queue_detail_id != "":
		if LOG.has_point(p):
			_handle_log_click(p)
		else:
			_queue_detail_id = ""
		queue_redraw()
		return
	if not state.capture:
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.call("sfx", "ui_hover")
	# P3c：前置航行覆盖层最优先吃点击（开局阻挡）。
	if _ov_prelude():
		_handle_prelude_click(p)
		queue_redraw()
		return
	# P2b：副官申请（独立 UI）最优先吃点击。
	if _ov_adjutant():
		_handle_adjutant_click(p)
		queue_redraw()
		return
	# P1j：模态窗口（通知 / 副官建议 / 手册）优先吃点击。
	if _modal != "":
		_handle_modal_click(p)
		queue_redraw()
		return
	# P1j：可点开的接管通知 + 副官建议 / 手册入口。
	if NOTICE_CLICK.has_point(p):
		_open_modal("notice")
		return
	if ADVISOR_BTN.has_point(p):
		_open_modal("manual" if _advisor_read else "advisor")
		return
	if MANUAL_BTN.has_point(p):
		_open_modal("manual")
		return
	# P1f：覆盖层吃掉一切点击。
	if _any_overlay():
		_handle_overlay_click(p)
		queue_redraw()
		return
	# P2b：右区证据面板（派穿梭机取证 / 撤出居民 / 三项菜单）。
	if _handle_evidence_click(p):
		queue_redraw()
		return
	# P9a：右区传感器架翻页 / 损管详情；左下日志/队列标签。
	if _handle_unit_click(p):
		queue_redraw()
		return
	if _handle_log_click(p):
		queue_redraw()
		return
	# P9a：传感器桅杆收放（右侧架摘要上方）
	if MAST_BTN.has_point(p):
		_toggle_mast()
		queue_redraw()
		return
	# P10a：左侧接触行优先（避免点接触时误触传感器条/菜单）。
	for i in row_rects.size():
		if row_rects[i].has_point(p):
			state.selected = i
			menu_open = false
			_queue_detail_id = ""
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
	if SENSOR_RECT.has_point(p) and not (TRACKS.has_point(p) or UNIT.has_point(p)
			or LOG.has_point(p) or TIME.has_point(p) or CMD.has_point(p) or TOP.has_point(p)):
		menu_open = not menu_open
		menu_t = 0.0
		queue_redraw()
		return
	if menu_open:
		# P3b：先判 ON/OFF chip（命中则只切开关，不误触发行选择、不关菜单）。
		for c in _rack_chip_rects:
			var cr: Rect2 = c["rect"]
			if cr.has_point(p):
				if bool(c.get("enabled", false)):
					_toggle_sensor(int(c["idx"]))
				return
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
	if pause_open:
		return true
	# P10a：战术弹窗打开时吞掉所有点击（由 click 处理关闭/选择）。
	if _ctx_open or _optical_open or _layers_open or _queue_detail_id != "":
		return true
	# P3c：前置航行 / P2b 副官申请优先吞输入。
	if _ov_prelude():
		return true
	if _ov_adjutant():
		return true
	if EVID_SHUTTLE.has_point(p) or EVID_EVAC.has_point(p):
		return true
	if RACK_PAGE_BTN.has_point(p) or DAMAGE_BTN.has_point(p):
		return true
	if DAMAGE_POPUP.has_point(p) and _damage_open:
		return true
	if LOG_TAB_COMMS.has_point(p) or LOG_TAB_QUEUE.has_point(p):
		return true
	for lb in _log_abort_rects:
		if (lb["rect"] as Rect2).has_point(p):
			return true
	if _evidence_menu_open:
		for i in range(3):
			if Rect2(1556.0 + float(i) * 96.0, EVID_MENU_Y, 92.0, 20.0).has_point(p):
				return true
	# P1j：模态窗口打开时吞掉所有指针输入。
	if _modal != "":
		return true
	if NOTICE_CLICK.has_point(p) or ADVISOR_BTN.has_point(p) or MANUAL_BTN.has_point(p):
		return true
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

	# P4：顶栏左区重排到 4/8 基线：标签 46 / 大时标 68 / 任务时间 88 / 目标 100，
	# 全部收在 TOP(40..112) 内，不再压到中心区或越出面板下沿。
	_txt(cjk, 60, 46, "指挥官席 / COMMANDER", 7, Palette.FAINT)
	var total := int(state.clock)
	var hh := int(total / 3600.0)
	var mm := int(total / 60.0) % 60
	var ss := total % 60
	var clock_s := "T+%02d:%02d:%02d" % [hh, mm, ss]
	_txt(mono, 60, 70, clock_s, 24, Palette.PH)
	var cw := mono.get_string_size(clock_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var tenth := int(fmod(float(state.clock), 1.0) * 10.0)
	_txt(mono, 60.0 + cw + 2.0, 70, ".%d" % tenth, 13, Palette.a(Palette.PH, 0.55))
	_txt(cjk, 60, 88, "任务时间 / MISSION ELAPSED", 7, Palette.FAINT)
	# P2a：目标行（第七号令 / Chronos / OCUVF-ID13；不显示 Act/Phase/关卡）。
	_txt(cjk, 60, 100, "目标 / OBJECTIVE · 阻止接管 · 第七号令 · Chronos · OCUVF-ID13", 7, Palette.a(Palette.AMBER, 0.8))

	draw_line(Vector2(520, 44), Vector2(520, 104), Palette.a(Palette.LINE, 0.7), 1.0)

	# 07 §4：第一关顶栏是「接管通知 · 案卷 4471」，主计时是 6 分钟执行窗口；
	# 主裁定的 216 h 宽限期另算，不压在这一关上。窗口剩余由 state.exec_left 提供。
	var exec_left := 360.0
	var exec_v = state.get("exec_left")
	if exec_v != null:
		exec_left = clampf(float(exec_v), 0.0, 360.0)
	# P2a：可点开的接管声明（第七号令）；2001 AV-4412 传唤者。
	var notice_hot := NOTICE_CLICK.has_point(_mouse_base())
	_txt(cjk, 548, 46, "接管声明 · 第七号令 · AV-4412 传唤者 / ORDER 7 NOTICE", 7,
		Palette.a(Palette.AMBER, 0.95 if notice_hot else 0.72))
	var notice_line_c: Color = Palette.a(Palette.AMBER, 0.55 if notice_hot else 0.22)
	draw_line(Vector2(548.0, 60.0), Vector2(800.0, 60.0), notice_line_c, 1.0)
	_txt(mono, 804, 46, "▸", 7, Palette.a(Palette.AMBER, 0.9 if notice_hot else 0.5))
	# P4c：倒计时恢复原水平位置；只做垂直居中（数字 64..88，顶栏 40..112）。
	_txt(cjk, 548, 70, "执行窗口", 9, Palette.DIM)
	_txt(mono, 596, 64, _hms(exec_left), 24, Palette.AMBER)
	draw_rect(Rect2(548, 106, 420, 1), Palette.a(Palette.AMBER, 0.16))
	draw_rect(Rect2(548, 106, 420.0 * exec_left / 360.0, 1), Palette.AMBER)
	_txt_r(cjk, 968, 70, "1× LOCK · OCUVF-ID13", 7, Palette.a(Palette.AMBER, 0.45))

	draw_line(Vector2(1288, 50), Vector2(1288, 102), Palette.a(Palette.LINE, 0.7), 1.0)

	_txt(cjk, 1300, 47, "链路 / LINK", 7, Palette.FAINT)
	# TEXT-02：链路按五级口径显示；中继损失显示 LINK DEGRADED（14 §3）。
	if _link_degraded():
		_txt(mono, 1300, 58, "LINK DEGRADED", 9, Palette.RED)
	else:
		_txt(cjk, 1300, 58, "%s %s" % [_link_mode_cn(), _link_latency()], 10, Palette.PH)
	for i in range(4):
		draw_rect(Rect2(1300.0 + float(i) * 10.0, 92, 7, 3), Palette.a(Palette.PH, 0.70 if i < 3 else 0.14))

	_txt(cjk, 1440, 47, "时标 / TIMESCALE", 7, Palette.FAINT)
	_txt(mono, 1440, 58, "×%d" % int(state.time_scale), 18, Palette.PH)
	_txt(cjk, 1440, 92, "自动降速 开", 7, Palette.AMBER)

	_txt(cjk, 1580, 47, "编队 Δv", 7, Palette.FAINT)
	_txt(mono, 1580, 58, _fmt_int(int(state.fleet_dv)), 18, Palette.PH)
	_txt(mono, 1652, 64, "m/s", 8, Palette.DIM)
	_txt(cjk, 1580, 92, "Δv 余量 72%", 7, Palette.FAINT)

	# 12 军语 P0-4/P0-5：同一行 ROE 不再用一个 HOLD 混三种含义；
	# P2a：ROE 卡 = 不得首先开火 / 武器释放需指挥官授权（15 §4.2）。
	_txt(cjk, 1720, 47, "交战规则 / ROE", 7, Palette.FAINT)
	_txt(cjk, 1720, 57, "仅自卫", 12, Palette.AMBER)
	_txt(cjk, 1720, 80, "WEAPONS HOLD", 7, Palette.a(Palette.AMBER, 0.75))
	_txt(cjk, 1720, 92, "不得首先开火 · 释放需授权", 7, Palette.DIM)

func _draw_tracks() -> void:
	_panel(TRACKS)
	# 12 军语 P0-2：TRACKS = 航迹；本面板是接触列表，所以中文取「接触」、英文取 CONTACTS。
	_txt(cjk, 76, 134, "接触 / CONTACTS", 11, Palette.TXT)
	_txt_r(mono, 364, 134, "%02d" % state.tracks.size(), 12, Palette.PH_DIM)
	_txt(cjk, 76, 153, "威胁排序 / THREAT RANKING", 7, Palette.FAINT)
	draw_line(Vector2(60, 168), Vector2(380, 168), Palette.a(Palette.LINE, 0.9), 1.0)

	row_rects.clear()
	for i in range(state.tracks.size()):
		var y := 176.0 + float(i) * 80.0
		row_rects.append(Rect2(60, y, 320, 80))
		_draw_track_row(state.tracks[i], i, y)

	draw_line(Vector2(60, 824), Vector2(380, 824), Palette.a(Palette.LINE, 0.9), 1.0)
	# P4：威胁图例改两行 × 3 格（92×16，间距 96/16），6 级中英文都收在 60..380 内。
	_txt(cjk, 76, 828, "威胁图例 / THREAT", 7, Palette.FAINT)
	for i in range(THR_ORDER.size()):
		var col := i % 3
		var row := i / 3
		_threat_legend_chip(Rect2(76.0 + float(col) * 96.0, 840.0 + float(row) * 16.0, 92.0, 16.0),
			String(THR_ORDER[i]))

func _draw_track_row(t: Dictionary, i: int, y: float) -> void:
	var col := _side_color(t)
	var sel: bool = i == int(state.selected)
	if sel:
		draw_rect(Rect2(60, y, 320, 80), Palette.a(Palette.PANEL2, 0.95))
		draw_rect(Rect2(60, y, 2, 80), col)
		draw_rect(Rect2(60, y, 320, 1), Palette.a(col, 0.22))
	draw_line(Vector2(76, y + 79), Vector2(364, y + 79), Palette.a(Palette.LINE, 0.55), 1.0)

	var dim := 0.45 if t.get("stale", false) else 1.0
	var disp_id := _track_display_id(t)
	var idf := cjk if Fonts.has_cjk(disp_id) else mono
	# P1k：列基线统一到 y+12（4px 网格），列 x：76 / 112 / 192 / 240 / 344。
	var batch := _track_batch(t)
	_txt(mono, 76, y + 12, "%04d" % batch if batch > 0 else "----", 8, Palette.a(Palette.FAINT, dim))
	_txt(idf, 112, y + 12, _ellipsis(idf, disp_id, 12, 74.0), 12, Palette.a(col, dim))
	var disp_cls := _dn(String(t.get("cls", "")))
	if disp_id == "已交叉确认":
		disp_cls = "无威胁"
	_txt(cjk, 192, y + 12, disp_cls, 9, Palette.a(Palette.DIM, dim))
	_identity_chip(Rect2(240, y + 12, 96, 14), _track_identity(t), dim)
	_draw_level(344.0, y + 12.0, t, col)

	var line2 := ""
	if t.get("own", false):
		line2 = "基准 / DATUM"
	elif t.get("bearing_only", false):
		line2 = "方位 302° · 距离未知"
	else:
		line2 = "方位 %03d° · %d km" % [int(t.bearing), int(t.range)]
	_txt(mono, 76, y + 36, line2, 8, Palette.a(Palette.DIM, dim))

	var cl := "编队内"
	if t.side == "hostile":
		# 12 军语 P0-11：光一个 km/s 不知道是接近率还是速度。
		cl = "接近率 %+.1f km/s" % float(t.closing)
	elif t.get("own", false):
		cl = "—"
	_txt_r(mono, 364, y + 36, cl, 8, Palette.a(col, 0.8 * dim))

	var age_s := "实时"
	if t.get("stale", false):
		age_s = "陈旧 %ds" % int(t.age)
	elif not t.get("own", false):
		age_s = "更新 %02ds" % int(t.age)
	_txt(cjk, 76, y + 52, age_s, 8, Palette.a(Palette.AMBER if t.get("stale", false) else Palette.FAINT, dim))

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

# ══ P2b：证据 / 穿梭机任务 / 撤人 / 副官申请 ═════════════════
# 只读 state（evidence / can_expose() / start_evidence_task() / start_evacuation() /
# adjutant_request_open / ack_adjutant()）；字段/方法不存在时用 HUD 本地演示态兜底。
func _evid_state_key(ui_key: String) -> String:
	for row in EVID_ITEMS:
		if String(row[0]) == ui_key:
			return String(row[1])
	return ui_key

func _evidence_got() -> Dictionary:
	var got := {"telemetry": false, "blackbox": false, "elint": false}
	if state != null:
		var ev = state.get("evidence")
		if ev is Dictionary:
			for row in EVID_ITEMS:
				var ui_k := String(row[0])
				var st_k := String(row[1])
				if (ev as Dictionary).has(st_k):
					got[ui_k] = bool((ev as Dictionary)[st_k])
				elif (ev as Dictionary).has(ui_k):
					got[ui_k] = bool((ev as Dictionary)[ui_k])
		for row in EVID_ITEMS:
			var ui_k2 := String(row[0])
			var direct = state.get("evidence_" + ui_k2)
			if direct != null:
				got[ui_k2] = got[ui_k2] or bool(direct)
		var fl = state.get("flags")
		if fl is Dictionary:
			for row in EVID_ITEMS:
				var ui_k3 := String(row[0])
				if (fl as Dictionary).has("evidence_" + ui_k3):
					got[ui_k3] = got[ui_k3] or bool((fl as Dictionary)["evidence_" + ui_k3])
			if (fl as Dictionary).has("ghost_track_evidence"):
				got["elint"] = true
	if _demo_evidence:
		for k in _demo_ev.keys():
			var kk := String(k)
			if got.has(kk):
				got[kk] = bool(_demo_ev[k])
	return got

func _evidence_count() -> int:
	var local := 0
	var got := _evidence_got()
	for k in got.keys():
		if bool(got[k]):
			local += 1
	var state_n := 0
	if state != null and state.has_method("evidence_count"):
		state_n = int(state.call("evidence_count"))
	return maxi(local, state_n)

func _can_expose() -> bool:
	if _demo_evidence:
		return _evidence_count() >= 2
	if state != null and state.has_method("can_expose"):
		return bool(state.call("can_expose"))
	return _evidence_count() >= 2

func _evid_label(kind: String) -> String:
	for row in EVID_ITEMS:
		if String(row[0]) == kind:
			return String(row[2]).split(" / ")[0]
	return kind

func _shuttle_busy() -> bool:
	if state != null:
		var tasks = state.get("evidence_tasks")
		if tasks is Array:
			for raw in (tasks as Array):
				if raw is Dictionary and String((raw as Dictionary).get("status", "")) == "RUNNING" \
						and bool((raw as Dictionary).get("shuttle", false)):
					return true
	return false

func _shuttle_task() -> Dictionary:
	var out := {"active": false, "done": false, "kind": "", "label": "", "remain": 0.0, "progress": 0.0, "shuttle": false}
	if state != null:
		var tasks = state.get("evidence_tasks")
		if tasks is Array:
			var running: Dictionary = {}
			var last_done: Dictionary = {}
			for raw in (tasks as Array):
				if not (raw is Dictionary):
					continue
				var tk: Dictionary = raw
				var st := String(tk.get("status", ""))
				if st == "RUNNING":
					if running.is_empty() or (bool(tk.get("shuttle", false)) and not bool(running.get("shuttle", false))):
						running = tk
				elif st == "DONE":
					last_done = tk
			if not running.is_empty():
				out["active"] = true
				out["kind"] = String(running.get("kind", ""))
				out["label"] = String(running.get("label", _evid_label(String(running.get("kind", "")))))
				var dur := maxf(1.0, float(running.get("duration", 30.0)))
				out["progress"] = clampf(float(running.get("progress", 0.0)), 0.0, 1.0)
				out["remain"] = maxf(0.0, dur * (1.0 - float(out["progress"])))
				out["shuttle"] = bool(running.get("shuttle", false))
				return out
			if not last_done.is_empty():
				out["done"] = true
				out["kind"] = String(last_done.get("kind", ""))
				out["label"] = String(last_done.get("label", _evid_label(String(last_done.get("kind", "")))))
				return out
		# 兼容旧字段：evidence_task / shuttle_task dict
		for nm in ["evidence_task", "shuttle_task"]:
			var v = state.get(nm)
			if v is Dictionary and not (v as Dictionary).is_empty():
				var d: Dictionary = v
				out["kind"] = String(d.get("kind", ""))
				out["label"] = String(d.get("label", out["kind"]))
				out["done"] = bool(d.get("done", false))
				out["active"] = bool(d.get("active", not out["done"])) and not out["done"]
				out["shuttle"] = bool(d.get("shuttle", false))
				if d.get("end_t") != null:
					out["remain"] = maxf(0.0, float(d["end_t"]) - float(state.tau()))
				elif d.get("duration_s") != null and d.get("t0") != null:
					out["remain"] = maxf(0.0, float(d["duration_s"]) - (float(state.tau()) - float(d["t0"])))
				return out
	if _demo_evidence and not _demo_task.is_empty():
		out["kind"] = String(_demo_task.get("kind", ""))
		out["label"] = String(_demo_task.get("label", _evid_label(String(out["kind"]))))
		out["done"] = bool(_demo_task.get("done", false))
		out["active"] = not out["done"]
		out["remain"] = maxf(0.0, float(_demo_task.get("duration_s", 0.0)) - _t)
		out["shuttle"] = true
	return out

func _evac_task() -> Dictionary:
	var out := {"active": false, "done": false, "remain": 0.0, "progress": 0.0}
	if state != null:
		var tasks = state.get("evidence_tasks")
		if tasks is Array:
			for raw in (tasks as Array):
				if not (raw is Dictionary):
					continue
				var tk: Dictionary = raw
				if String(tk.get("kind", "")) != "evacuation":
					continue
				var st := String(tk.get("status", ""))
				if st == "RUNNING":
					out["active"] = true
					out["progress"] = clampf(float(tk.get("progress", 0.0)), 0.0, 1.0)
					out["remain"] = maxf(0.0, float(tk.get("duration", 60.0)) * (1.0 - float(out["progress"])))
					return out
				if st == "DONE":
					out["done"] = true
					return out
		if bool(state.get("civilians_evacuated")):
			out["done"] = true
			return out
	if _demo_evidence and not _demo_evac.is_empty():
		out["done"] = bool(_demo_evac.get("done", false))
		out["active"] = not out["done"]
		out["evacuated"] = int(_demo_evac.get("evacuated", 0))
		out["total"] = int(_demo_evac.get("total", 0))
	return out

func _start_evidence(kind: String) -> void:
	_evidence_menu_open = false
	_sfx("sys_evidence_start")
	var st_kind := _evid_state_key(kind)
	if state != null:
		if state.has_method("start_evidence_task"):
			state.call("start_evidence_task", st_kind)
			return
		if state.has_method("start_evidence"):
			state.call("start_evidence", st_kind)
			return
	if _demo_evidence:
		_demo_task = {"kind": kind, "label": _evid_label(kind), "t0": _t, "duration_s": 96.0, "done": false}

func _start_evac() -> void:
	_sfx("sys_evac_start")
	if state != null:
		if state.has_method("start_evacuation"):
			state.call("start_evacuation")
			return
		if state.has_method("evacuate"):
			state.call("evacuate")
			return
	if _demo_evidence:
		_demo_evac = {"t0": _t, "duration_s": 96.0, "done": false, "evacuated": 0, "total": 0}

func _handle_evidence_click(p: Vector2) -> bool:
	if _evidence_menu_open:
		for i in range(3):
			var mr := Rect2(1556.0 + float(i) * 96.0, EVID_MENU_Y, 92.0, 20.0)
			if mr.has_point(p):
				_start_evidence(String(EVID_ITEMS[i][0]))
				return true
		_evidence_menu_open = false
		return false
	if EVID_SHUTTLE.has_point(p):
		if _shuttle_busy():
			return true
		_evidence_menu_open = not _evidence_menu_open
		return true
	if EVID_EVAC.has_point(p):
		var e := _evac_task()
		if _shuttle_busy() or bool(e["done"]):
			return true
		_start_evac()
		return true
	return false

func _draw_evidence_panel() -> void:
	var got := _evidence_got()
	var n := _evidence_count()
	var expose_ok := _can_expose()
	_txt(cjk, 1556, EVID_TITLE_Y, _evid_dtext("证据 / EXPOSE（需 2/3）"), 7, Palette.FAINT)
	_txt_r(mono, 1844, EVID_TITLE_Y, _evid_dtext("%d/3" % n), 8, Palette.PH if expose_ok else Palette.AMBER)
	for i in range(3):
		var row: Array = EVID_ITEMS[i]
		var y := EVID_ROW_Y + float(i) * EVID_ROW_H
		var g := bool(got[String(row[0])])
		var col: Color = Palette.PH if g else Palette.FAINT
		_txt(mono, 1556, y, "✓" if g else "○", 8, col)
		_txt(cjk, 1572, y, _evid_dtext(String(row[2]), float(i) * 0.01), 7, Palette.TXT if g else Palette.DIM)
	var frac := float(n) / 3.0
	draw_rect(EVID_BAR, Palette.a(Palette.LINE, 0.85))
	draw_rect(Rect2(EVID_BAR.position, Vector2(EVID_BAR.size.x * frac, EVID_BAR.size.y)),
		Palette.PH if expose_ok else Palette.AMBER)
	var running := _running_evidence_tasks()
	var shuttle_busy := _shuttle_busy()
	var tline := "任务空闲 · 遥测可并行 · 穿梭机同时仅 1 架"
	var tcol: Color = Palette.FAINT
	if not running.is_empty():
		var parts := ""
		for i in range(running.size()):
			var r: Dictionary = running[i]
			if parts != "":
				parts += " · "
			parts += "%s %.0fs" % [String(r["label"]), float(r["remain"])]
		tline = "并行任务：" + parts
		if running.size() > 1:
			tcol = Palette.PH
		else:
			tcol = Palette.AMBER if bool((running[0] as Dictionary).get("shuttle", false)) else Palette.BLUE
	elif bool(_evac_task()["done"]):
		tline = "人员撤离：已完成"
		tcol = Palette.PH
	var dn := _evid_dtext(tline)
	_txt(cjk, 1556, EVID_TASK_Y, _ellipsis(cjk, dn, 7, 288.0), 6, tcol)
	if _evidence_menu_open:
		for i in range(3):
			var mr := Rect2(1556.0 + float(i) * 96.0, EVID_MENU_Y, 92.0, 20.0)
			var hot := mr.has_point(_mouse_base())
			draw_rect(mr, Palette.a(Palette.PH, 0.12 if hot else 0.05))
			draw_rect(mr, Palette.a(Palette.PH, 0.6 if hot else 0.3), false, 1.0)
			_txt(cjk, mr.position.x + 5.0, mr.position.y + 4.0,
				_dtext("遥测" if i == 0 else ("黑匣子" if i == 1 else "特征码"), float(i) * 0.01), 7, Palette.TXT)
		# P3a：证据菜单窗口的 80px 硬切揭示（仅菜单小窗，窗口外不受影响）
		_draw_window_cut(Rect2(1556.0, EVID_MENU_Y, 288.0, EVID_MENU_ROW))
	var evac := _evac_task()
	var slabel := "派穿梭机取证 / SHUTTLE"
	if shuttle_busy:
		slabel = "穿梭机占用中 / BUSY"
	_cmd_btn(EVID_SHUTTLE, slabel, _evidence_menu_open, Palette.FAINT if shuttle_busy else Palette.BLUE)
	var elabel := "撤出居民 / EVACUATE"
	var ecol: Color = Palette.AMBER
	if bool(evac["done"]):
		elabel = "人员已撤离 / DONE"
		ecol = Palette.FAINT
	elif shuttle_busy:
		ecol = Palette.FAINT
	_cmd_btn(EVID_EVAC, elabel, false, ecol)

# ── P2b：副官申请（独立 UI；state.adjutant_request_open / ack_adjutant）──
func _ov_adjutant() -> bool:
	if _demo_adjutant:
		return true
	return _flag("adjutant_request_open") and not _demo_suppress_adjutant

func _adj_data() -> Dictionary:
	var d := {"title": "副官建议 / ADJUTANT REQUEST", "body": "",
		"options": [] as Array}
	if state != null:
		var ar = state.get("adjutant_request")
		if ar is Dictionary and not (ar as Dictionary).is_empty():
			var a: Dictionary = ar
			d["body"] = String(a.get("body", a.get("text", "")))
			var op = a.get("options")
			if op is Array and (op as Array).size() > 0:
				d["options"] = op
		if String(d["body"]) == "":
			var bt = state.get("adjutant_request_text")
			if bt != null:
				d["body"] = String(bt)
		if String(d["body"]) != "" and _is_old_text(String(d["body"])):
			d["body"] = _d2_text(String(d["body"]))
	if String(d["body"]) == "":
		d["body"] = "指挥官，Chronos 港务与 UEG 核查组记录可能已被清算者封存，若属实，则今后彻底失去谈判资本。建议：批准穿梭机取回港务遥测或核查组黑匣子，或先撤出居民。请指示。"
	if (d["options"] as Array).is_empty():
		d["options"] = [
			{"key": "telemetry", "label": "批准取回港务遥测 / TELEMETRY", "hint": "派穿梭机前去取回 Chronos 港务副本（证据 1/3）"},
			{"key": "blackbox", "label": "批准取回黑匣子 / RECORDER", "hint": "取回 UEG 核查组记录副本（证据 1/3）"},
			{"key": "evacuate", "label": "优先撤离居民 / EVACUATE FIRST", "hint": "撤出平民与可移动储罐，暂不取证"},
			{"key": "later", "label": "暂不处理 / LATER", "hint": "关闭建议，稍后自行下令"},
		]
	return d

func _ack_adjutant(choice: String) -> void:
	_demo_adjutant = false
	if state != null and state.has_method("ack_adjutant"):
		state.call("ack_adjutant", choice)
		return
	match choice:
		"telemetry", "blackbox", "elint":
			_start_evidence(choice)
		"evacuate":
			_start_evac()
		_:
			pass

func _adj_opt_rect(i: int) -> Rect2:
	var r := ADJUTANT_RECT
	return Rect2(r.position.x + 24.0 + float(i % 2) * 424.0, r.position.y + 176.0 + float(i / 2) * 84.0, 400.0, 72.0)

func _draw_adjutant_overlay() -> void:
	_overlay_dim()
	var r := ADJUTANT_RECT
	var info := _adj_data()
	_overlay_frame(r, _dtext("副官建议 / ADJUTANT REQUEST"), "")
	_cmd_btn(ADJUTANT_CLOSE, "关闭 / CLOSE", false, Palette.PH)
	_txt(cjk, r.position.x + 24.0, r.position.y + 56.0, "副官 · 请求指示：", 8, Palette.DIM)
	_txt_r(cjk, r.end.x - 24.0, r.position.y + 56.0, "打开时暂停执行窗口", 7, Palette.a(Palette.AMBER, 0.9))
	var lines := _wrap_text(cjk, String(info["body"]), 9, r.size.x - 48.0)
	var dlines := _dlines(lines)
	for i in range(mini(dlines.size(), 4)):
		_txt(cjk, r.position.x + 24.0, r.position.y + 80.0 + float(i) * 18.0, String(dlines[i]), 9, Palette.a(Palette.TXT, 0.95))
	var opts: Array = info["options"]
	var shuttle_busy_now := _shuttle_busy()
	for i in range(mini(opts.size(), 4)):
		var rc := _adj_opt_rect(i)
		var o: Dictionary = opts[i]
		var kind := String(o.get("kind", o.get("key", "")))
		var chosen_now: Array = state.get("_adjutant_choices") if state != null else []
		var used := kind in chosen_now
		var blocked := used or (shuttle_busy_now and (kind == "blackbox" or kind == "evacuate"))
		var hot := rc.has_point(_mouse_base()) and not blocked
		draw_rect(rc, Palette.a(Palette.PANEL2, 0.95) if hot else Palette.a(Palette.PANEL, 0.6))
		draw_rect(rc, Palette.a(Palette.PH, 0.75 if hot else (0.16 if blocked else 0.3)), false, 1.0)
		_txt(mono, rc.position.x + 14.0, rc.position.y + 16.0, "0%d" % (i + 1), 14,
			Palette.a(Palette.PH, 0.35 if blocked else 0.9))
		_txt(cjk, rc.position.x + 44.0, rc.position.y + 16.0, _dtext(String(o.get("label", "")), float(i) * 0.01),
			10, Palette.FAINT if blocked else (Palette.PH if hot else Palette.TXT))
		_txt(cjk, rc.position.x + 44.0, rc.position.y + 44.0,
			_ellipsis(cjk, _dtext(String(o.get("hint", "")), float(i) * 0.01), 7, 330.0), 7, Palette.DIM)
		if blocked:
			_txt_r(cjk, rc.end.x - 12.0, rc.position.y + 16.0, "已请求" if used else "穿梭机占用", 7, Palette.a(Palette.AMBER, 0.9))
	_txt(cjk, r.position.x + 24.0, r.end.y - 24.0, "选择会写入命令/真实通话 · 遥测可与穿梭机任务并行，穿梭机同一时间仅派出 1 架",
		7, Palette.FAINT)
	_draw_window_cut(r)

func _handle_adjutant_click(p: Vector2) -> void:
	if ADJUTANT_CLOSE.has_point(p):
		_ack_adjutant("decline")
		return
	var info := _adj_data()
	var opts: Array = info["options"]
	var chosen_now: Array = state.get("_adjutant_choices") if state != null else []
	for i in range(mini(opts.size(), 4)):
		if _adj_opt_rect(i).has_point(p):
			var o: Dictionary = opts[i]
			var kind := String(o.get("kind", o.get("key", "later")))
			if kind in chosen_now:
				return
			if _shuttle_busy() and (kind == "blackbox" or kind == "evacuate"):
				return
			_ack_adjutant(kind)
			return

func _fmt_period(sec: float) -> String:
	if sec <= 1.0 or not is_finite(sec):
		return "—"
	var m := int(round(sec / 60.0))
	if m >= 60:
		return "T %dh%02dm" % [m / 60, m % 60]
	return "T %dm" % m

func _toggle_mast() -> void:
	if state == null or not state.has_method("toggle_mast"):
		return
	state.call("toggle_mast", _rack_ship())
	_sfx("ui_toggle_on" if not _mast_down() else "ui_toggle_off")

func _mast_down() -> bool:
	if state == null:
		return false
	if state.has_method("is_mast_deployed"):
		return not bool(state.call("is_mast_deployed", _rack_ship()))
	var md = state.get("mast_deployed")
	if md is Dictionary:
		return not bool((md as Dictionary).get(_rack_ship(), true))
	return false

func _selected_ship_view() -> Dictionary:
	# P9a：右区数据跟随 state.selected；缺失字段显示「—」，不伪造。
	var tr := _rack_track()
	var u: Dictionary = state.unit
	var own := tr.is_empty() or bool(tr.get("own", false))
	var v := {
		"name": _dn(String(u.get("name", "—"))), "en": _dn(String(u.get("en", ""))),
		"cls": _dn(String(u.get("cls", ""))), "role": _dn(String(u.get("role", ""))),
		"faction": _dn(String(u.get("faction", ""))), "batch": 1001, "identity": "friend",
		"mass": "—", "crew": "—", "accel": "—", "inc": "—", "period": "—",
		"att": "—", "range": "—", "closing": "—",
	}
	if not tr.is_empty():
		v["name"] = _dn(_track_display_id(tr))
		v["en"] = _dn(String(tr.get("en", "")))
		v["batch"] = _track_batch(tr)
		v["identity"] = _track_identity(tr)
		if String(tr.get("cls", "")) != "":
			v["cls"] = _dn(String(tr.get("cls", "")))
		if String(tr.get("role", "")) != "":
			v["role"] = _dn(String(tr.get("role", "")))
		var idi = tr.get("id_info", {})
		var cla = tr.get("classification", {})
		var fac := ""
		if idi is Dictionary:
			fac = String((idi as Dictionary).get("faction", ""))
		if fac == "" and cla is Dictionary:
			fac = String((cla as Dictionary).get("faction", ""))
		if fac == "":
			match String(tr.get("side", "")):
				"friend": fac = "OCUVF · ID13"
				"hostile": fac = "UEG 第33舰队"
				_: fac = "身份待定 / UNKNOWN"
		v["faction"] = _dn(fac)
		# P9a：优先用 ENG 提供的 state.selected_info() / orbit_readout() 兜底姿态与轨道周期。
		if state != null and state.has_method("selected_info"):
			var si = state.call("selected_info")
			if si is Dictionary:
				var sd: Dictionary = si
				if not bool(sd.get("own", false)):
					var orb = sd.get("orbit", {})
					if orb is Dictionary and bool((orb as Dictionary).get("available", false)):
						var od: Dictionary = orb
						v["period"] = _fmt_period(float(od.get("period_s", 0.0)))
						if od.get("inc_deg") != null:
							v["inc"] = "%04.1f°" % float(od["inc_deg"])
				if sd.get("range_km") != null:
					v["range"] = _km(float(sd["range_km"]))
				if sd.get("closing_mps") != null:
					var cm := float(sd["closing_mps"]) / 1000.0
					v["closing"] = "接近率 %+.1f km/s" % cm
		if bool(tr.get("own", false)):
			v["mass"] = _dn(String(u.get("mass", "—")))
			v["crew"] = _dn(String(u.get("crew", "—")))
			v["accel"] = _dn(String(u.get("accel", "—")))
			v["inc"] = _dn(String(u.get("inc", "—")))
			v["period"] = _dn(String(u.get("period", "—")))
			if String(v["period"]) == "—":
				v["period"] = "本舰基准"
		# 姿态：由状态矢量估计（航向 / 俯仰）；横滚无数据不显示。
		var vv = tr.get("v")
		if vv is Vector3 and (vv as Vector3).length() > 1.0e-6:
			var vel: Vector3 = vv
			var hdg := fposmod(rad_to_deg(atan2(vel.x, vel.y)), 360.0)
			var pit := rad_to_deg(asin(clampf(vel.z / vel.length(), -1.0, 1.0)))
			v["att"] = "H %03.0f° / P %+04.1f°" % [hdg, pit]
	return v

func _running_evidence_tasks() -> Array:
	var out: Array = []
	if state != null:
		var tasks = state.get("evidence_tasks")
		if tasks is Array:
			for raw in (tasks as Array):
				if not (raw is Dictionary):
					continue
				var tk: Dictionary = raw
				if String(tk.get("status", "")) != "RUNNING":
					continue
				var dur := maxf(1.0, float(tk.get("duration", 30.0)))
				out.append({
					"label": String(tk.get("label", _evid_label(String(tk.get("kind", ""))))),
					"shuttle": bool(tk.get("shuttle", false)),
					"remain": maxf(0.0, dur * (1.0 - clampf(float(tk.get("progress", 0.0)), 0.0, 1.0))),
				})
	if out.is_empty() and _demo_evidence and not _demo_task.is_empty() and not bool(_demo_task.get("done", false)):
		out.append({"label": String(_demo_task.get("label", "")), "shuttle": true,
			"remain": maxf(0.0, float(_demo_task.get("duration_s", 0.0)) - _t)})
	if out.is_empty() and _demo_evidence and not _demo_evac.is_empty() and not bool(_demo_evac.get("done", false)):
		out.append({"label": "人员撤离", "shuttle": true,
			"remain": maxf(0.0, float(_demo_evac.get("duration_s", 0.0)) - _t)})
	return out

func _draw_damage_card() -> void:
	draw_rect(DAMAGE_CARD, Palette.a(Palette.AMBER, 0.045))
	draw_rect(DAMAGE_CARD, Palette.a(Palette.AMBER, 0.34), false, 1.0)
	var u: Dictionary = state.unit
	_txt(cjk, UNIT_X + 10.0, 624.0, "损管 / DAMAGE CONTROL", 7, Palette.AMBER)
	_txt_r(mono, 1844, 624.0, "QUEUE 2", 7, Palette.a(Palette.FAINT, 0.95))
	var dmg := _dn(String(u.get("damage", "—")))
	var dmg2 := _dn(String(u.get("damage2", "")))
	_txt(cjk, UNIT_X + 10.0, 641.0, _ellipsis(cjk, "%s%s" % [dmg, (" · " + dmg2) if dmg2 != "" else ""], 8, 268.0),
		8, Palette.TXT)
	_txt(cjk, UNIT_X + 10.0, 655.0, "队列 2 项 · HULL 100% · 优先：CH-IR2 校准", 7, Palette.DIM)
	_cmd_btn(DAMAGE_BTN, "损管详情 / DETAILS", _damage_open, Palette.AMBER)

func _draw_damage_popup() -> void:
	var r := DAMAGE_POPUP
	draw_rect(r, Palette.a(Palette.PANEL, 0.99))
	draw_rect(r, Palette.a(Palette.AMBER, 0.75), false, 1.0)
	_txt(cjk, r.position.x + 12.0, r.position.y + 18.0, "损管队列 / DAMAGE QUEUE", 9, Palette.AMBER)
	_txt_r(mono, r.end.x - 12.0, r.position.y + 18.0, "LOCAL RECORD", 7, Palette.a(Palette.FAINT, 0.9))
	draw_line(Vector2(r.position.x + 12.0, r.position.y + 26.0), Vector2(r.end.x - 12.0, r.position.y + 26.0),
		Palette.a(Palette.AMBER, 0.3), 1.0)
	var u: Dictionary = state.unit
	var rows := [
		["01", String(u.get("damage2", "传感器 / 校准")), "进行中 · 优先 1", Palette.AMBER],
		["02", String(u.get("damage", "战损记录")), "监测 · 优先 2", Palette.DIM],
		["03", "反应堆 / 冷却回路", "正常 · 监测", Palette.PH_DIM],
	]
	for i in range(rows.size()):
		var row: Array = rows[i]
		var y := r.position.y + 44.0 + float(i) * 30.0
		_txt(mono, r.position.x + 12.0, y, String(row[0]), 10, Palette.a(Palette.AMBER, 0.8))
		_txt(cjk, r.position.x + 38.0, y, _ellipsis(cjk, String(row[1]), 8, 130.0), 8, Palette.TXT)
		_txt_r(cjk, r.end.x - 12.0, y, String(row[2]), 7, row[3])
		draw_line(Vector2(r.position.x + 12.0, y + 8.0), Vector2(r.end.x - 12.0, y + 8.0),
			Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(cjk, r.position.x + 12.0, r.end.y - 12.0, "点击 DETAILS 或面板外关闭 · 优先级可调（后续接入损管 API）", 7,
		Palette.a(Palette.FAINT, 0.9))

func _draw_unit() -> void:
	_panel(UNIT)
	var v := _selected_ship_view()
	var tr := _rack_track()
	var rack := _rack_rows()
	var rack_ship := _rack_ship()
	var em := _rack_emission()
	var lv := clampi(int(tr.get("level", 0)), 0, 4)
	# 抬头：跟随 state.selected
	_txt(cjk, UNIT_X, 138, "选中舰 / SELECTED SHIP", 7, Palette.FAINT)
	_txt(cjk, UNIT_X, 152, String(v["name"]), 22, Palette.TXT)
	_txt(mono, UNIT_X, 178, String(v["en"]), 8, Palette.DIM)
	_txt(cjk, UNIT_X, 194, _ellipsis(cjk, "%s · %s" % [String(v["cls"]), String(v["role"])], 10, 288.0),
		10, Palette.PH)
	_txt(cjk, UNIT_X, 210, _ellipsis(cjk, String(v["faction"]), 8, 200.0), 8, Palette.DIM)
	_txt_r(cjk, 1844, 210, "[%04d] %s" % [int(v["batch"]), _identity_cn(String(v["identity"]))], 7,
		_id_color(String(v["identity"])))
	draw_line(Vector2(1540, 224), Vector2(1860, 224), Palette.a(Palette.LINE, 0.9), 1.0)

	# 数据区：干重/舰员/加速度/距离 + 倾角/周期/姿态/接近率（缺失 = —）
	var stats := [
		["干重 MASS", String(v["mass"]), "倾角 INC", String(v["inc"])],
		["舰员 CREW", String(v["crew"]), "周期 PERIOD", String(v["period"])],
		["加速度 ACCEL", String(v["accel"]), "姿态 ATTITUDE", String(v["att"])],
		["距离 RANGE", String(v["range"]), "接近率 CLOSING", String(v["closing"])],
	]
	for i in range(4):
		var y := 236.0 + float(i) * 22.0
		_txt(cjk, UNIT_X, y, String(stats[i][0]), 7, Palette.DIM)
		_txt(mono, UNIT_X, y + 10.0, String(stats[i][1]), 9, Palette.TXT)
		_txt(cjk, UNIT_X + 150.0, y, String(stats[i][2]), 7, Palette.DIM)
		var rv := String(stats[i][3])
		var rf: Font = cjk if Fonts.has_cjk(rv) else mono
		_txt(rf, UNIT_X + 150.0, y + 10.0, _ellipsis(rf, rv, 9, 132.0), 9, Palette.TXT)

	# 系统（紧凑 16px 行）
	var u: Dictionary = state.unit
	var u_sys: Array = u.get("systems", [])
	var sys_avg := 0.0
	for raw in u_sys:
		sys_avg += float((raw as Array)[1])
	if not u_sys.is_empty():
		sys_avg /= float(u_sys.size())
	_txt(cjk, UNIT_X, 328, "系统 / SYSTEMS", 7, Palette.FAINT)
	_txt_r(mono, 1844, 328, "AVG %d%%" % int(round(sys_avg * 100.0)), 8, Palette.DIM)
	for i in range(mini(5, u_sys.size())):
		var r: Array = u_sys[i]
		var y := 340.0 + float(i) * 16.0
		_txt(cjk, UNIT_X, y, String(r[0]), 8, Palette.DIM)
		var sv := float(r[1])
		_bar(Rect2(1640, y - 5.0, 150, 3), sv, _sys_color(sv))
		_txt_r(mono, 1844, y, "%d%%" % int(round(sv * 100.0)), 7, Palette.TXT)

	# Δv（紧凑）
	var dv_s := String(u.get("dv", "—"))
	var dv_max := String(u.get("dv_max", "—"))
	_txt(cjk, UNIT_X, 424, "Δv 预算 / BUDGET", 7, Palette.FAINT)
	_txt(mono, UNIT_X, 450, dv_s, 24, Palette.PH)
	var dvw := mono.get_string_size(dv_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_txt(mono, UNIT_X + dvw + 5.0, 450, "m/s", 8, Palette.DIM)
	_txt_r(mono, 1844, 450, "/ %s 满" % dv_max, 8, Palette.DIM)
	var dv_now := _to_int(dv_s)
	var dv_full := _to_int(dv_max)
	var dv_frac := 1.0
	if dv_full > 0:
		dv_frac = clampf(float(dv_now) / float(dv_full), 0.0, 1.0)
	_bar(Rect2(UNIT_X, 460, 288, 3), dv_frac, Palette.PH)
	_txt(cjk, UNIT_X, 474, "剩余 %d%% · 已耗 %s m/s" % [int(round(dv_frac * 100.0)), _fmt_int(maxi(dv_full - dv_now, 0))],
		7, Palette.FAINT)

	# 完整传感器架：每页最多 5 行，超过则分页（点击右上翻页），不截断
	_txt(cjk, UNIT_X, RACK_HEADER_Y, "传感器架 / SENSOR RACK", 7, Palette.FAINT)
	var pages := maxi(1, int(ceil(float(rack.size()) / float(RACK_ROWS_MAX))))
	_rack_page = clampi(_rack_page, 0, pages - 1)
	var page_info := "%02d 模块" % rack.size()
	if pages > 1:
		page_info += " · %d/%d ▸" % [_rack_page + 1, pages]
	var mast_down := _mast_down()
	if mast_down:
		page_info += " · MAST DOWN"
	_txt_r(cjk, 1844, RACK_HEADER_Y, page_info, 7, Palette.AMBER if mast_down else Palette.DIM)
	var start := _rack_page * RACK_ROWS_MAX
	for i in range(mini(RACK_ROWS_MAX, rack.size() - start)):
		var s2: Dictionary = rack[start + i]
		var model := String(s2.get("model", "—"))
		var on := _rack_on(rack_ship, model, bool(s2.get("on", true)))
		var cy := RACK_ROW_Y + float(i) * RACK_ROW_PITCH
		_txt(mono, UNIT_X, cy, model, 9, Palette.TXT)
		var mw := mono.get_string_size(model, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_txt(cjk, UNIT_X + mw + 8.0, cy + 1.0,
			"%s · %s" % [String(s2.get("maker", "—")), _rack_type_cn(s2)], 7, Palette.DIM)
		var expose := bool(s2.get("expose", false))
		_txt_r(cjk, 1808, cy, "暴露风险" if expose else "被动", 7, Palette.AMBER if expose else Palette.FAINT)
		_txt_r(mono, 1844, cy, "开" if on else "关", 7, Palette.PH if on else Palette.FAINT)

	# 桅杆收放（P9a）
	var mast_label := "放桅 / MAST UP" if mast_down else "收桅 / MAST DOWN"
	_cmd_btn(MAST_BTN, mast_label, mast_down, Palette.AMBER if mast_down else Palette.PH)
	# 暴露/EMCON（桅杆收起时整个架不可用）
	var exposed := bool(em.get("exposed", false))
	var exp_short := "EMIT/暴露" if exposed else "EMCON/静默"
	var exp_col: Color = Palette.RED if bool(state.get("elint_named")) else (Palette.AMBER if exposed else Palette.FAINT)
	if mast_down:
		_txt(cjk, UNIT_X, 602, "MAST DOWN · 桅杆收起 · 传感器架不可用（含主动阵列）", 7, Palette.AMBER)
	else:
		_txt(cjk, UNIT_X, 602, "%s · 等级L%d · 开机暴露风险" % [exp_short, lv], 7, exp_col)

	# 损管卡（独立状态卡；副官/手册按钮不在此卡内）
	_draw_damage_card()

	# 证据面板（P2b）
	_draw_evidence_panel()
	if _damage_open:
		_draw_damage_popup()

	# 底栏：战备 + 工具按钮归位（不与损管队列混排）
	draw_line(Vector2(1540, 820), Vector2(1860, 820), Palette.a(Palette.LINE, 0.9), 1.0)
	_txt(cjk, UNIT_X, 828, "战备 / READINESS · NOMINAL", 8, Palette.PH_DIM)
	_txt_r(cjk, 1844, 828, "舰体 HULL 100%", 8, Palette.DIM)
	_cmd_btn(ADVISOR_BTN, "副官建议 · 已读" if _advisor_read else "副官建议 / ADJUTANT", false, Palette.BLUE)
	_cmd_btn(MANUAL_BTN, "手册 / MANUAL", false, Palette.PH)

func _handle_unit_click(p: Vector2) -> bool:
	if RACK_PAGE_BTN.has_point(p):
		var rack := _rack_rows()
		var pages := maxi(1, int(ceil(float(rack.size()) / float(RACK_ROWS_MAX))))
		if pages > 1:
			_rack_page = (_rack_page + 1) % pages
			_sfx("ui_click")
		return true
	if DAMAGE_BTN.has_point(p):
		_damage_open = not _damage_open
		_sfx("ui_open" if _damage_open else "ui_close")
		return true
	if _damage_open:
		_damage_open = false
		return true
	return false


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

func _handle_log_click(p: Vector2) -> bool:
	if LOG_TAB_COMMS.has_point(p):
		_log_tab = 0
		_sfx("ui_click")
		return true
	if LOG_TAB_QUEUE.has_point(p):
		_log_tab = 1
		_sfx("ui_click")
		return true
	if _log_tab == 1:
		if _queue_detail_id != "":
			if _queue_detail_abort_rect.has_point(p):
				state.abort_command(_queue_detail_id)
				_queue_detail_id = ""
				_sfx("ui_confirm")
				return true
			_queue_detail_id = ""
			return true
		for row in _log_abort_rects:
			var rr: Rect2 = row["rect"]
			if rr.has_point(p):
				state.abort_command(String(row["id"]))
				_sfx("ui_confirm")
				return true
		for row2 in _log_row_rects:
			if (row2["rect"] as Rect2).has_point(p):
				_queue_detail_id = String(row2["id"])
				_sfx("ui_click")
				return true
	return false

func _draw_log() -> void:
	_panel(LOG)
	_log_abort_rects.clear()
	# P9a：顶部标签「通信流 / 事件」↔「命令队列」（Tab 或点击切换）
	var tabs := [["通信流 / 事件 · COMMS", LOG_TAB_COMMS], ["命令队列 / QUEUE", LOG_TAB_QUEUE]]
	for i in range(2):
		var tr: Rect2 = tabs[i][1]
		var sel := i == _log_tab
		var hot := tr.has_point(_mouse_base())
		draw_rect(tr, Palette.a(Palette.PANEL2, 0.95 if (sel or hot) else 0.35))
		draw_rect(tr, Palette.a(Palette.PH, 0.75 if (sel or hot) else 0.25), false, 1.0)
		if sel:
			draw_rect(Rect2(tr.position.x, tr.position.y, 2.0, tr.size.y), Palette.PH)
		_txt(cjk, tr.position.x + 8.0, tr.position.y + 4.0, String(tabs[i][0]), 8,
			Palette.PH if sel else Palette.DIM)
	_txt_r(mono, 604, 892, "TAB 切换", 7, Palette.a(Palette.FAINT, 0.8))
	draw_line(Vector2(64, 914), Vector2(616, 914), Palette.a(Palette.LINE, 0.9), 1.0)

	if _log_tab == 0:
		# 通信流 / 事件（最近 3 条）
		var feed := _feed_entries()
		var sig := str(feed)
		if sig != _feed_sig:
			_feed_sig = sig
			_feed_flash = 0.85
		if _demo_radio:
			_feed_flash = 0.85
		var flash := clampf(_feed_flash / 0.85, 0.0, 1.0)
		for i in range(mini(FEED_ROWS, feed.size())):
			var e: Dictionary = feed[i]
			var y := 920.0 + float(i) * FEED_PITCH
			var kind := String(e.get("kind", "RADIO"))
			var mode := String(e.get("mode", ""))
			var tag := "EVENT" if kind == "EVENT" else (mode if mode != "" else "COM")
			var col: Color = Palette.AMBER if kind == "EVENT" else _mode_color(mode)
			if i == 0 and flash > 0.0:
				draw_rect(Rect2(64, y - 2, 552, 12), Palette.a(col, 0.22 * flash))
			draw_rect(Rect2(64, y - 1, 2, 10), Palette.a(col, 0.85 if i == 0 else 0.30))
			_txt(mono, 72, y, tag, 7, Palette.a(col, 0.85))
			_txt(cjk, 132, y - 1, _ellipsis(cjk, _dn(String(e.get("text", ""))), 8, 462.0), 8,
				Palette.a(Palette.TXT, 0.96 if i == 0 else 0.66))
		if feed.is_empty():
			_txt(cjk, 76, 924, "（暂无通信 / 事件）", 8, Palette.FAINT)
		# 命令日志（证据）：紧凑 3 行
		draw_line(Vector2(60, 964), Vector2(620, 964), Palette.a(Palette.LINE, 0.9), 1.0)
		_txt(cjk, 76, 972, "命令日志 / COMMAND LOG", 7, Palette.FAINT)
		_txt_r(mono, 604, 972, "NEWEST FIRST", 7, Palette.FAINT)
		var cmd_left := maxf(0.0, 6.2 - float(state.elapsed))
		var pending := cmd_left > 0.0
		for i in range(mini(3, state.log_lines.size())):
			var l: Dictionary = state.log_lines[i]
			var y := 984.0 + float(i) * 18.0
			_txt(mono, 76, y, "T+" + String(l.get("t", "")), 9, Palette.a(Palette.FAINT, 0.95))
			var disp_text := _ellipsis(cjk, _dn(String(l.get("text", ""))), 10, 300.0)
			_txt(cjk, 140, y - 1, disp_text, 10, Palette.a(Palette.TXT, 0.92))
			var tw := cjk.get_string_size(disp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			if String(l.get("arg", "")) != "":
				_txt(mono, 140.0 + tw + 8.0, y, _dn(String(l.get("arg", ""))), 7, Palette.a(Palette.AMBER, 0.7))
			_log_status(l, i, y - 1, cmd_left, pending)
	else:
		# 命令队列（当前队列可见，可撤销 QUEUED/TRANSMITTED；点击行展开完整文本）
		_log_row_rects.clear()
		_queue_detail_abort_rect = Rect2()
		if _queue_detail_id != "":
			_draw_queue_detail()
		else:
			var cmds: Array = state.commands()
			_txt(cjk, 76, 918, "命令队列 / ORDER QUEUE · %d 项 · 点击行看全文" % cmds.size(), 8, Palette.TXT)
			_txt_r(mono, 604, 918, "STATUS / ABORT", 7, Palette.a(Palette.FAINT, 0.8))
			if cmds.is_empty():
				_txt(cjk, 76, 940, "（队列为空）", 8, Palette.FAINT)
			var shown := 0
			for idx in range(cmds.size() - 1, -1, -1):
				if shown >= 4:
					break
				var c: Dictionary = cmds[idx]
				var y := 938.0 + float(shown) * 22.0
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
				var target := String(c.get("target", ""))
				var detail := ""
				if act == "SHADOW" and target != "":
					detail = " → " + _dn(target)
				elif act == "BURN":
					detail = " Δv %.0f" % float((c.get("plan", {}) as Dictionary).get("dv_ms", 0.0))
				_txt(mono, 76, y, String(c.get("id", "")), 8, Palette.a(Palette.FAINT, 0.9))
				_txt(cjk, 112, y, _ellipsis(cjk, "%s%s" % [act, detail], 8, 260.0), 8, Palette.TXT)
				_txt_r(cjk, 520, y, _cmd_phase(c), 7, sc)
				_log_row_rects.append({"rect": Rect2(72, y - 12.0, 460, 20), "id": String(c.get("id", ""))})
				if st == "QUEUED" or st == "TRANSMITTED":
					var rr := Rect2(536, y - 6.0, 80, 16)
					draw_rect(rr, Palette.a(Palette.RED, 0.07))
					draw_rect(rr, Palette.a(Palette.RED, 0.38), false, 1.0)
					_txt(cjk, rr.position.x + 14.0, rr.position.y + 3.0, "撤销 / ABORT", 7, Palette.RED)
					_log_abort_rects.append({"rect": rr, "id": String(c.get("id", ""))})
				draw_line(Vector2(76, y + 8.0), Vector2(604, y + 8.0), Palette.a(Palette.LINE, 0.35), 1.0)
			_txt(cjk, 76, 1028, "点击行看完整命令 · 撤销待生效 · Tab 切回通信流", 7, Palette.FAINT)

	var blink := 0.5 + 0.5 * sin(_t * 4.0)
	draw_rect(Rect2(76, 1028, 5, 1), Palette.a(Palette.PH, 0.6 * blink))

func _draw_queue_detail() -> void:
	var cmd := {}
	for raw in state.commands():
		var c: Dictionary = raw
		if String(c.get("id", "")) == _queue_detail_id:
			cmd = c
			break
	if cmd.is_empty():
		_queue_detail_id = ""
		return
	_txt(cjk, 76, 920, "命令全文 / ORDER TEXT · %s" % _queue_detail_id, 9, Palette.PH)
	_txt_r(mono, 604, 920, "ESC / 点击返回", 7, Palette.a(Palette.FAINT, 0.85))
	draw_line(Vector2(64, 930), Vector2(616, 930), Palette.a(Palette.LINE, 0.8), 1.0)
	var act := String(cmd.get("action", ""))
	var st := String(cmd.get("status", ""))
	var col: Color = Palette.PH_DIM
	if st == "QUEUED":
		col = Palette.AMBER
	elif st == "TRANSMITTED":
		col = Palette.BLUE
	elif st == "REJECTED":
		col = Palette.RED
	elif st == "ABORTED":
		col = Palette.FAINT
	var rows := [
		["单位 UNIT", String(cmd.get("unit", "—"))],
		["动作 ACTION", act + " / " + _cmd_phase(cmd)],
		["目标 TARGET", String(cmd.get("target", "—"))],
		["状态 STATUS", st + " · " + _cmd_phase(cmd)],
	]
	for i in range(rows.size()):
		var y := 944.0 + float(i) * 17.0
		_txt(cjk, 76, y, String(rows[i][0]), 7, Palette.FAINT)
		_txt(cjk, 180, y, _ellipsis(cjk, String(rows[i][1]), 8, 430.0), 8,
			col if i == 3 else Palette.TXT)
	# 参数 / 计划全文（不省略，按行展开）
	var params: Dictionary = cmd.get("params", {})
	var plan: Dictionary = cmd.get("plan", {})
	var full := "PARAMS %s · PLAN %s" % [str(params), str(plan)]
	var lines := _wrap_text(mono, full, 7, 540.0)
	for i in range(mini(lines.size(), 3)):
		_txt(mono, 76, 1018.0 - 36.0 + float(i) * 12.0, String(lines[i]), 7, Palette.a(Palette.DIM, 0.95))
	if st == "QUEUED" or st == "TRANSMITTED":
		var rr := Rect2(520, 1002, 96, 18)
		draw_rect(rr, Palette.a(Palette.RED, 0.07))
		draw_rect(rr, Palette.a(Palette.RED, 0.45), false, 1.0)
		_txt(cjk, rr.position.x + 16.0, rr.position.y + 4.0, "撤销 / ABORT", 7, Palette.RED)
		_queue_detail_abort_rect = rr
	else:
		_queue_detail_abort_rect = Rect2()

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
			return "预命令"
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
	_sfx("sys_cmd_queued")
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
	_txt(cjk, CMD_INSET_X, 892, "命令 / ORDERS", 8, Palette.TXT)
	_txt_r(cjk, CMD_INNER_R, 892, "%s · 剩余 Δv %s m/s" % [_rack_ship_name(), _fmt_int(dv_left)], 7, Palette.DIM)

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
	_txt(cjk, CMD_INSET_X, 930, "T+", 7, Palette.DIM)
	_mini_btn(T_MINUS, "-")
	_txt(mono, 700, 932, "%04.1f s" % draft_t, 10, Palette.TXT)
	_mini_btn(T_PLUS, "+")
	_txt(cjk, 796, 930, "Δv", 7, Palette.DIM)
	_mini_btn(DV_MINUS, "-")
	_txt(mono, 848, 932, "%03.0f m/s" % draft_dv, 10, Palette.TXT)
	_mini_btn(DV_PLUS, "+")
	_txt(cjk, 984, 930, "方向", 7, Palette.DIM)
	_txt(cjk, 1016, 931, _ellipsis(cjk, String(preset["label"]), 7, 82.0), 7, Palette.TXT)
	_cmd_btn(DIR_CYCLE, "换向 ▸", false, Palette.PH)

	# P1f：把「链路」与「机动」拆两行 —— 中继只花时间与暴露，不烧 Δv。
	# TEXT-02：链路标签按 14 §3 五级口径；中继损失显示 LINK DEGRADED。
	var link_line := "链路：%s（望楼号中继）%s · 传达 / 确认，不消耗 Δv" % [_link_mode_cn(), _link_latency()]
	if _link_degraded():
		link_line = "链路：LINK DEGRADED · 回退 45 s（中继损失，不消耗 Δv）"
	_txt(cjk, CMD_INSET_X, 954, link_line, 7, Palette.a(Palette.BLUE if not _link_degraded() else Palette.RED, 0.85))
	_txt(cjk, CMD_INSET_X, 962, "机动：Δv %.0f m/s · 剩余 %s m/s" % [draft_dv, _fmt_int(dv_left)], 7, Palette.a(Palette.AMBER, 0.85))
	if _burn_drag:
		_txt_r(cjk, CMD_INNER_R, 962, "拖动中 · 未授权", 7, Palette.a(Palette.AMBER, 0.9))
	else:
		_txt_r(cjk, CMD_INNER_R, 962, "轨道预览 BURN T+%.1f" % draft_t, 7, Palette.a(Palette.BLUE, 0.8))

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
	# P1f：武器释放授权（二次确认；仅裁决前可用）
	var fire_col := Palette.RED
	var fire_label := "武器释放授权 / RELEASE"
	var fire_ready := _fire_available()
	if _flag("fire_branch"):
		fire_label = "已授权 / AUTHORIZED"
		fire_col = Palette.FAINT
	elif _fire_confirm_t > 0.0:
		fire_label = "确认释放授权？%.0fs" % ceil(_fire_confirm_t)
	elif not fire_ready:
		fire_label = "武器释放授权（不可用）"
		fire_col = Palette.FAINT
	_cmd_btn(FIRE_BTN, fire_label, _fire_confirm_t > 0.0, fire_col)

	# P9a：命令面板只留队列摘要；完整队列/撤销在左下「命令队列」标签页。
	_txt(cjk, CMD_INSET_X, 1020, "队列 / QUEUE · %d 待生效 · %d 执行 · %d 完成 · 详情见左下标签页" % [queued, active, done], 7, Palette.FAINT)
	_txt_r(mono, CMD_INNER_R, 1020, "QUEUE %d/%d" % [queued, camds.size()], 7, Palette.FAINT)

# ══ P1f：裁决 / 后果 / 报告覆盖层 ══════════════════════
# 原则：读 state 字段（decision_open / report_open / consequence_open / fire_branch /
# audit_flag / report_text / …）与调 state 方法（choose_ending / authorize_fire /
# submit_report）；字段/方法不存在时退回 HUD 本地演示态（DSH_UI 截图钩子用）。

# P2a（D2 · 15 §3）：内部事后报告兜底文本（OCJC / OCUVF，不是 UEG 官方回复）。
const MOCK_REPORT := "OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n事件：L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）\n裁决：HOLD / 坚守\n经过：ID13 于执行窗口内保持对 Chronos 储罐区与进港航道的卡位，未让出检查边界，未首先开火。清算者的最终接管程序未完成；ID13 依据 OCJC 授权要求轨道事务委员会复核第七号令。人员伤亡：无。\n证据：传感器日志、命令队列、通信记录、Chronos 港务遥测。\n声望：OCU +2 · Meridian +1 · UEG 鸽派 +1 · 清算者 −2\n建议：准备复核 / 听证材料，保留现场记录与通信记录。"

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

# P1g：END 归档（回声页）——在 report/consequence/decision 之上，互斥绘制。
func _ov_end() -> bool:
	return _demo_end or _flag("end_open")

func _any_overlay() -> bool:
	return _ov_end() or _ov_report() or _ov_consequence() or _ov_decision()

# 暂停指示文案（时标处）：decision / consequence / report / END。
# P1g：decision / consequence / report / END 时，时标处显示 PAUSED · 裁决/报告/归档。
func _pause_label() -> String:
	if _ov_prelude():
		return "航行准备"
	if _modal == "notice":
		return "通知"
	if _modal == "advisor":
		return "副官建议"
	if _modal == "manual":
		return "手册"
	if _ov_adjutant():
		return "副官申请"
	if _ov_end():
		return "归档"
	if _ov_report():
		return "报告"
	if _ov_consequence():
		return "后果"
	if _ov_decision():
		return "裁决"
	return ""

# ══ P3c：前置航行覆盖层（航行准备 / DEPARTURE）════════════════
# 读 state.prelude_*（P3c-SIM contract）；state 未落地时用 _demo_prelude 本地演示。
# 不写通信流：所有文本都只在覆盖层内，不放无线电 / 事件 feed。
func _ov_prelude() -> bool:
	if _demo_prelude:
		return true
	return _flag("prelude_open")

func _prelude_live() -> bool:
	return state != null and state.get("prelude_open") != null

func _prelude_data() -> Dictionary:
	var d := {
		"step": 0, "route": "", "window": "", "dv": 84.0,
		"hint": "", "body": "ID13 自母港 L4-02 Hammer 离港，前往 L1 Meridian 执行 OCUVF 任务；设定目的地、变轨窗口与 Δv 预算。",
	}
	# 场景级文本（title/body）优先读 state.prelude_data（P3c-SIM 已落地，story.prelude）。
	if state != null:
		for pkey in ["prelude_data", "prelude"]:
			var pd = state.get(pkey)
			if pd is Dictionary:
				var bv = (pd as Dictionary).get("body")
				if bv != null and String(bv) != "":
					d["body"] = String(bv)
				var tv = (pd as Dictionary).get("title")
				if tv != null and String(tv) != "":
					d["_title"] = String(tv)
	if _demo_prelude:
		# 截图演示态：步骤/选择完全本地；step≥2 时若未选中，回退到第一个正确项以显示完整摘要。
		d["step"] = clampi(_demo_pre_step, 0, 3)
		if d["step"] >= 2 and _demo_pre_route == "":
			for raw_r in _prelude_routes():
				if raw_r is Dictionary and bool((raw_r as Dictionary).get("ok", false)):
					_demo_pre_route = String((raw_r as Dictionary).get("id", ""))
					break
		if d["step"] >= 2 and _demo_pre_window == "":
			for raw_w in _prelude_windows():
				if raw_w is Dictionary and bool((raw_w as Dictionary).get("ok", false)):
					_demo_pre_window = String((raw_w as Dictionary).get("id", ""))
					break
		d["route"] = _demo_pre_route
		d["window"] = _demo_pre_window
		d["hint"] = _prelude_hint_text
		return d
	if _prelude_live():
		var st = state.get("prelude_step")
		if st != null:
			d["step"] = clampi(int(st), 0, 3)
		var rv = state.get("prelude_route")
		if rv != null:
			d["route"] = String(rv)
		var wv = state.get("prelude_window")
		if wv != null:
			d["window"] = String(wv)
		var dv = state.get("prelude_dv")
		if dv != null and float(dv) > 0.0:
			d["dv"] = float(dv)
		d["hint"] = _prelude_hint_text
	return d

func _prelude_routes() -> Array:
	var out: Array = []
	if state != null:
		var pd = state.get("prelude_data")
		if pd is Dictionary and (pd as Dictionary).get("routes") is Array:
			var rv = (pd as Dictionary)["routes"]
			if (rv as Array).size() > 0:
				return rv
		for key in ["prelude_routes", "prelude_route_options"]:
			var v = state.get(key)
			if v is Array and (v as Array).size() > 0:
				out = v
				break
		if not out.is_empty():
			return out
	out = [
		{"id": "meridian", "label": "L1 Meridian · Chronos", "hint": "OCUVF 本部指定；ID13 以谈判主力介入 Chronos 事件。", "ok": true},
		{"id": "karman", "label": "L2 Karman · 贸易环", "hint": "非任务航线：抵达时执行窗口已开始，错过 T+18:00 变轨。", "ok": false},
	]
	return out

func _prelude_windows() -> Array:
	var out: Array = []
	if state != null:
		var pd = state.get("prelude_data")
		if pd is Dictionary and (pd as Dictionary).get("windows") is Array:
			var wv = (pd as Dictionary)["windows"]
			if (wv as Array).size() > 0:
				return wv
		for key in ["prelude_windows", "prelude_window_options"]:
			var v = state.get(key)
			if v is Array and (v as Array).size() > 0:
				out = v
				break
		if not out.is_empty():
			return out
	out = [
		{"id": "t1800", "label": "T+18:00 · 标准变轨窗口", "hint": "Hammer 港务调度已批准；Δv 在预算内，抵达时间符合任务要求。", "ok": true},
		{"id": "t0200", "label": "T+02:00 · 应急窗口", "hint": "窗口过窄：时序/燃料风险，抵达时执行窗口已开始。", "ok": false},
	]
	return out

func _prelude_opt_label(opts: Array, oid: String) -> String:
	for raw in opts:
		if raw is Dictionary:
			var o: Dictionary = raw
			var id := String(o.get("id", o.get("kind", "")))
			if id == oid:
				return String(o.get("label", id))
	if oid == "":
		return "—"
	return oid

# Δv 预计：state.prelude_dv 优先；未结算时按「航线 dv_ms + 窗口 dv_ms」估算（scenario 数据）。
func _prelude_dv_value(d: Dictionary) -> float:
	var dv := float(d.get("dv", 0.0))
	if dv > 0.0:
		return dv
	var total := 0.0
	for raw in _prelude_routes():
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == String(d.get("route", "")):
			total += float((raw as Dictionary).get("dv_ms", 0.0))
			break
	for raw2 in _prelude_windows():
		if raw2 is Dictionary and String((raw2 as Dictionary).get("id", "")) == String(d.get("window", "")):
			total += float((raw2 as Dictionary).get("dv_ms", 0.0))
			break
	return total if total > 0.0 else 84.0

func _prelude_call(method: String, arg: Variant = null) -> bool:
	if state == null or not state.has_method(method):
		return false
	if arg == null:
		state.call(method)
	else:
		state.call(method, arg)
	return true

func _prelude_choose(kind: String, option: Dictionary) -> void:
	var oid := String(option.get("id", option.get("kind", "")))
	if oid == "":
		return
	var ok := bool(option.get("ok", option.get("correct", false)))
	var hint := String(option.get("hint", ""))
	if _demo_prelude:
		# 截图演示态：正确项推进，错误项停在原地并给提示（文本仍来自 scenario）。
		if kind == "route":
			if ok:
				_demo_pre_route = oid
				_demo_pre_step = 1
				_prelude_hint_text = ""
			else:
				_prelude_hint_text = "航线不可用：%s" % hint if hint != "" else "航线错误：请选择 L1 Meridian。"
		else:
			if ok:
				_demo_pre_window = oid
				_demo_pre_step = 2
				_prelude_hint_text = ""
			else:
				_prelude_hint_text = "窗口不可用：%s" % hint if hint != "" else "窗口错误：请选择 T+18:00。"
		return
	if _prelude_live():
		var res = null
		if kind == "route" and state.has_method("prelude_choose_route"):
			res = state.call("prelude_choose_route", oid)
		elif kind == "window" and state.has_method("prelude_choose_window"):
			res = state.call("prelude_choose_window", oid)
		if res is Dictionary and not bool((res as Dictionary).get("ok", false)):
			var h := String((res as Dictionary).get("hint", hint))
			_prelude_hint_text = h if h != "" else "选择无效，请重新选择。"
		else:
			_prelude_hint_text = ""

func _prelude_confirm() -> void:
	if _demo_prelude:
		_demo_prelude = false
		return
	# P3c-SIM：prelude_confirm() 内部即执行点火（等价 execute）。
	if _prelude_live() and state.has_method("prelude_confirm"):
		state.call("prelude_confirm")
		return
	_prelude_execute()

func _prelude_execute() -> void:
	if _demo_prelude:
		_demo_prelude = false
		return
	if _prelude_live() and state.has_method("prelude_execute"):
		state.call("prelude_execute")
		return

func _prelude_skip() -> void:
	if _demo_prelude:
		_demo_prelude = false
		return
	if _prelude_live() and state.has_method("prelude_skip"):
		state.call("prelude_skip")

func _poll_prelude_keys() -> void:
	for k in [KEY_1, KEY_2, KEY_ENTER, KEY_SPACE, KEY_S]:
		var down := Input.is_key_pressed(k)
		var was := bool(_key_prev.get(k, false))
		_key_prev[k] = down
		if down and not was:
			_on_prelude_key(k)

func _on_prelude_key(k: int) -> void:
	if k == KEY_S:
		_prelude_skip()
		return
	var d := _prelude_data()
	var st := int(d["step"])
	if st == 0:
		var routes := _prelude_routes()
		if k == KEY_1 and routes.size() > 0:
			_prelude_choose("route", routes[0])
		elif k == KEY_2 and routes.size() > 1:
			_prelude_choose("route", routes[1])
	elif st == 1:
		var wins := _prelude_windows()
		if k == KEY_1 and wins.size() > 0:
			_prelude_choose("window", wins[0])
		elif k == KEY_2 and wins.size() > 1:
			_prelude_choose("window", wins[1])
	elif st == 2:
		# P9a：Enter/Space 为长按（进程轮询蓄力）；只有满 3s 后按 Enter/点击才执行。
		if _prelude_hold_done and (k == KEY_ENTER or k == KEY_SPACE or k == KEY_2):
			_prelude_execute()

func _prelude_opt_rect(i: int) -> Rect2:
	return Rect2(PRELUDE_RECT.position.x + 48.0 + float(i) * (PRELUDE_OPT_W + PRELUDE_OPT_GAP),
		PRELUDE_OPT_Y, PRELUDE_OPT_W, PRELUDE_OPT_H)

func _handle_prelude_click(p: Vector2) -> void:
	var d := _prelude_data()
	var st := int(d["step"])
	if st == 0 or st == 1:
		var opts := _prelude_routes() if st == 0 else _prelude_windows()
		for i in range(mini(opts.size(), 2)):
			if _prelude_opt_rect(i).has_point(p):
				_prelude_choose("route" if st == 0 else "window", opts[i])
				return
	elif st == 2:
		# P9a：左键按住 3s 充能确认（松开取消），右侧执行按钮解锁后点击执行。
		if PRELUDE_CONFIRM.has_point(p):
			return
		if PRELUDE_EXECUTE.has_point(p) and _prelude_hold_done:
			_prelude_execute()
			return
	if PRELUDE_SKIP.has_point(p):
		_prelude_skip()

func _draw_prelude_overlay() -> void:
	_overlay_dim()
	var r := PRELUDE_RECT
	var d := _prelude_data()
	var st := int(d["step"])
	_overlay_frame(r, _dtext("航行准备 / DEPARTURE"),
		"PRELUDE · 第零幕")
	# 三步进度（step 3 = 已执行，仅过渡帧）
	var steps := [["00", "目的地 / ROUTE"], ["01", "变轨窗口 / WINDOW"], ["02", "Δv / BURN"]]
	for i in range(3):
		var chip := Rect2(r.position.x + 48.0 + float(i) * 224.0, r.position.y + 56.0, 208.0, 24.0)
		var done := st > i
		var cur := st == i
		draw_rect(chip, Palette.a(Palette.PANEL2, 0.9) if cur else Palette.a(Palette.PANEL, 0.4))
		draw_rect(chip, Palette.a(Palette.PH, 0.8 if (cur or done) else 0.22), false, 1.0)
		_txt(mono, chip.position.x + 10.0, chip.position.y + 5.0, String(steps[i][0]), 8,
			Palette.PH if (cur or done) else Palette.FAINT)
		_txt(cjk, chip.position.x + 40.0, chip.position.y + 5.0, String(steps[i][1]), 8,
			Palette.TXT if cur else Palette.DIM)
	# 概述正文（P3a 解码）
	var body_lines := _wrap_text(cjk, String(d["body"]), 9, r.size.x - 96.0)
	var db := _dlines(body_lines)
	for i in range(mini(db.size(), 2)):
		_txt(cjk, r.position.x + 48.0, r.position.y + 96.0 + float(i) * 18.0, String(db[i]), 9,
			Palette.a(Palette.TXT, 0.9))
	if st == 0 or st == 1:
		var opts := _prelude_routes() if st == 0 else _prelude_windows()
		var chosen := String(d["route"]) if st == 0 else String(d["window"])
		for i in range(mini(opts.size(), 2)):
			var o: Dictionary = opts[i]
			var rc := _prelude_opt_rect(i)
			var oid := String(o.get("id", o.get("kind", "")))
			var sel := oid != "" and oid == chosen
			var hot := rc.has_point(_mouse_base())
			var col: Color = Palette.PH if sel else (Palette.AMBER if hot else Palette.LINE)
			draw_rect(rc, Palette.a(Palette.PANEL2, 0.85 if hot else 0.5))
			draw_rect(rc, Palette.a(col, 0.85 if (sel or hot) else 0.3), false, 1.0)
			if sel:
				draw_rect(Rect2(rc.position.x, rc.position.y, 2.0, rc.size.y), Palette.PH)
			_txt(mono, rc.position.x + 18.0, rc.position.y + 16.0, "0%d" % (i + 1), 18,
				Palette.a(Palette.PH, 0.9))
			_txt(cjk, rc.position.x + 62.0, rc.position.y + 14.0, _dtext(String(o.get("label", oid))), 12,
				Palette.TXT)
			_txt(cjk, rc.position.x + 62.0, rc.position.y + 48.0,
				_ellipsis(cjk, _dtext(String(o.get("hint", ""))), 8, rc.size.x - 84.0), 8, Palette.DIM)
			var corr = o.get("ok")
			if corr == null:
				corr = o.get("correct")
			if corr != null:
				if bool(corr):
					_txt(cjk, rc.position.x + 62.0, rc.position.y + 104.0,
						"任务指定 / 正确" if st == 0 else "推荐窗口 / 正确", 7, Palette.a(Palette.PH, 0.8))
				else:
					_txt(cjk, rc.position.x + 62.0, rc.position.y + 104.0,
						"非任务航线 / 会错过窗口" if st == 0 else "应急窗口 / 风险", 7, Palette.a(Palette.AMBER, 0.75))
			if sel:
				_txt_r(cjk, rc.end.x - 16.0, rc.position.y + 16.0, "已选", 7, Palette.PH)
		var hint := String(d["hint"])
		if hint != "":
			_txt(cjk, r.position.x + 48.0, PRELUDE_ACT_Y - 24.0, _dtext(hint), 9, Palette.a(Palette.AMBER, 0.95))
	elif st == 2:
		var routes := _prelude_routes()
		var wins := _prelude_windows()
		var dv_est := _prelude_dv_value(d)
		_txt(cjk, r.position.x + 48.0, PRELUDE_OPT_Y - 24.0, "Δv 预算 / BURN BUDGET", 7, Palette.FAINT)
		_txt(mono, r.position.x + 48.0, PRELUDE_OPT_Y + 32.0, "%d m/s" % int(round(dv_est)), 36, Palette.PH)
		_txt(cjk, r.position.x + 560.0, PRELUDE_OPT_Y + 2.0,
			_dtext("航线 / ROUTE：%s" % _prelude_opt_label(routes, String(d["route"]))), 10, Palette.TXT)
		_txt(cjk, r.position.x + 560.0, PRELUDE_OPT_Y + 32.0,
			_dtext("窗口 / WINDOW：%s" % _prelude_opt_label(wins, String(d["window"]))), 10, Palette.TXT)
		var ctext := ""
		var pd = state.get("prelude_data") if state != null else null
		if pd is Dictionary:
			ctext = String((pd as Dictionary).get("confirm_text", ""))
		if ctext == "":
			ctext = "目的地与变轨窗口已选；确认后执行点火，Δv 从 ID13 预算中扣除。"
		_txt(cjk, r.position.x + 560.0, PRELUDE_OPT_Y + 62.0,
			_ellipsis(cjk, _dtext(ctext), 9, 420.0), 9, Palette.a(Palette.TXT, 0.9))
		_txt(cjk, r.position.x + 560.0, PRELUDE_OPT_Y + 92.0,
			"执行后：点火 → 巡航 → 抵达 Meridian；本阶段不计入 6:00 执行窗口。", 8, Palette.DIM)
		# P9a：左 = 长按 3s 确认（进度填充，松开取消）；右 = 解锁后执行点火。
		var hold_frac := clampf(_prelude_hold / PRELUDE_HOLD_S, 0.0, 1.0)
		var ccol: Color = Palette.PH if _prelude_hold_done else Palette.PH_DIM
		draw_rect(PRELUDE_CONFIRM, Palette.a(ccol, 0.10))
		draw_rect(PRELUDE_CONFIRM, Palette.a(ccol, 0.80 if _prelude_hold_done else 0.35), false, 1.0)
		if hold_frac > 0.0:
			draw_rect(Rect2(PRELUDE_CONFIRM.position, Vector2(PRELUDE_CONFIRM.size.x * hold_frac, PRELUDE_CONFIRM.size.y)),
				Palette.a(Palette.PH, 0.22))
		var clabel := "已确认 / CONFIRMED" if _prelude_hold_done else \
			"按住 3s 确认并点火（%.1fs）" % maxf(0.0, PRELUDE_HOLD_S - _prelude_hold)
		_txt(cjk, PRELUDE_CONFIRM.position.x + 16.0, PRELUDE_CONFIRM.position.y + 15.0, clabel, 10,
			Palette.PH if _prelude_hold_done else Palette.a(Palette.TXT, 0.9))
		_txt_r(mono, PRELUDE_CONFIRM.end.x - 14.0, PRELUDE_CONFIRM.position.y + 15.0,
			"HOLD" if not _prelude_hold_done else "ARMED", 7, Palette.a(Palette.PH_DIM, 0.9))
		_cmd_btn(PRELUDE_EXECUTE, "执行点火 / EXECUTE", _prelude_hold_done,
			Palette.AMBER if _prelude_hold_done else Palette.FAINT)
		if not _prelude_hold_done:
			_txt_r(cjk, PRELUDE_EXECUTE.end.x - 16.0, PRELUDE_EXECUTE.end.y - 4.0,
				"需先长按确认", 7, Palette.a(Palette.FAINT, 0.9))
	else:
		_txt(cjk, r.position.x + 48.0, PRELUDE_OPT_Y + 24.0, "点火命令已下达 · 正在硬切揭场…", 14, Palette.PH)
	# 跳过 / 键位提示
	_cmd_btn(PRELUDE_SKIP, "跳过 / SKIP（S）", false, Palette.FAINT)
	_txt(cjk, r.position.x + 48.0, r.end.y - 44.0,
		"1 / 2 选择 · Step 2 按住左键或 Enter 3s 确认 → 点击执行点火 · S 跳过", 7, Palette.FAINT)
	# P3a：80px 硬切揭示 + 文本解码（窗口 id = prelude）
	_draw_window_cut(r)

# ── P1g：无线电 / 事件 feed ────────────────────────────
func _norm_feed(raw, default_kind: String) -> Dictionary:
	if raw is Dictionary:
		var d: Dictionary = raw
		var kind := String(d.get("kind", default_kind)).to_upper()
		var text := String(d.get("text", d.get("line", d.get("msg", ""))))
		if kind == "EVENT" or d.has("type"):
			return {"kind": "EVENT", "text": text, "t": float(d.get("t", -1.0)), "mode": ""}
		# P1j：19 §1 通信格式 [发信者至收信者]-[LD/LR/RDO/IR/VIS]-[内容]
		var e := {
			"from": String(d.get("from", d.get("speaker", d.get("src", "")))),
			"to": String(d.get("to", d.get("dst", ""))),
			"mode": String(d.get("mode", d.get("via", ""))),
			"text": text,
		}
		var mode_s := _comms_mode_short(String(e["mode"])) if String(e["mode"]) != "" else ""
		return {"kind": "RADIO", "text": _comms_format(e), "t": float(d.get("t", -1.0)), "mode": mode_s}
	if default_kind == "EVENT":
		return {"kind": "EVENT", "text": String(raw), "t": -1.0, "mode": ""}
	return {"kind": "RADIO", "text": _comms_format({"from": "VHF", "text": String(raw)}), "t": -1.0, "mode": ""}

func _mode_color(mode: String) -> Color:
	match mode:
		"LD", "LR":
			return Palette.BLUE
		"RDO":
			return Palette.PH_DIM
		"IR":
			return Palette.AMBER
		"VIS":
			return Palette.FAINT
		_:
			return Palette.PH_DIM

# 最近 3 条（无线电 + 事件合并，按 t / 到达顺序取最新，最新在上）。
# state.radio_feed / event_feed 为空时，退回 scenario 的 radio_lines / events（仅演示）。
func _feed_entries() -> Array:
	var radio: Array = []
	var events: Array = []
	if state != null:
		var rf = state.get("radio_feed")
		if rf is Array:
			for raw in rf:
				radio.append(_norm_feed(raw, "RADIO"))
		var ef = state.get("event_feed")
		if ef is Array:
			for raw in ef:
				events.append(_norm_feed(raw, "EVENT"))
	if radio.is_empty() and events.is_empty() and state != null:
		var story = state.get("story")
		if story is Dictionary:
			var rl = (story as Dictionary).get("radio_lines", [])
			if rl is Array:
				for raw in rl:
					radio.append(_norm_feed(raw, "RADIO"))
	# P1j：裁决回复（本地追加）进通信流；state 侧若已推同一句可无感叠加。
	for raw in _local_comms:
		radio.append(_norm_feed(raw, "RADIO"))
	var all: Array = []
	all.append_array(radio)
	all.append_array(events)
	if all.is_empty():
		return []
	all.sort_custom(_feed_cmp)
	var n := mini(FEED_ROWS, all.size())
	var out: Array = []
	for i in range(n):
		out.append(all[all.size() - 1 - i])
	return out

func _feed_cmp(a, b) -> bool:
	var ta := float((a as Dictionary).get("t", -1.0))
	var tb := float((b as Dictionary).get("t", -1.0))
	if ta < 0.0 and tb < 0.0:
		return false
	return ta < tb

# ── P1g：END 归档页 ───────────────────────────────────
func _safe_state(name: String) -> String:
	if state == null:
		return ""
	var v = state.get(name)
	return "" if v == null else String(v)

func _restart_demo() -> void:
	if state != null and state.has_method("restart_demo"):
		state.call("restart_demo")
		return
	get_tree().reload_current_scene()

func _quit_demo() -> void:
	if state != null and state.has_method("quit_demo"):
		state.call("quit_demo")
		return
	get_tree().quit()

func _end_data() -> Dictionary:
	var d := {"outcome": "", "label": "", "reputation": {}, "report_text": "",
		"perjury": 0, "audit": false, "flags": {}, "report_choice": "",
		"window_used": 0, "fire_branch": false}
	if state != null:
		d["outcome"] = String(state.get("outcome"))
		if state.has_method("ending_label") and String(d["outcome"]) != "":
			d["label"] = String(state.call("ending_label", String(d["outcome"])))
		d["report_choice"] = _safe_state("report_choice")
		var rv = state.get("reputation")
		if rv is Dictionary:
			d["reputation"] = rv
		var pv = state.get("perjury_count")
		if pv != null:
			d["perjury"] = int(pv)
		d["audit"] = bool(state.get("audit_flag"))
		var fv = state.get("flags")
		if fv is Dictionary:
			d["flags"] = fv
		d["report_text"] = _report_text()
		# P1g-SIM 的 end_summary 字段名：outcome / ending / reputation / report_text /
		# report_choice / flags / perjury_count / audit_flag / window_used_s
		var es = state.get("end_summary")
		if es is Dictionary:
			var e: Dictionary = es
			var pairs := [["outcome", "outcome"], ["ending", "label"], ["label", "label"],
				["reputation", "reputation"], ["report_text", "report_text"],
				["report_choice", "report_choice"], ["perjury", "perjury"],
				["perjury_count", "perjury"], ["audit", "audit"],
				["audit_flag", "audit"], ["flags", "flags"],
				["window_used_s", "window_used"], ["fire_branch", "fire_branch"]]
			for pair in pairs:
				var src: String = String(pair[0])
				var dst: String = String(pair[1])
				if e.has(src):
					d[dst] = e[src]
	if String(d["outcome"]) == "" and _demo_end:
		d["outcome"] = "EXPOSE"
		d["label"] = _d2_kind_label("expose")
		d["report_choice"] = "TRUTH"
		d["reputation"] = {"OCU": 1, "Meridian": 0, "UEG 鸽派": 2, "外环": 0, "清算者": -3}
		d["report_text"] = _d2_report("EXPOSE")
		d["flags"] = {"expose": true, "ghost_track_evidence": true}
		d["perjury"] = 0
		d["audit"] = false
	# P2a：旧 outcome / ending 字段在显示层归一到 D2（HOLD/EVACUATE/EXPOSE/FIRE）。
	var d2o := _d2_outcome(String(d["outcome"]), String(d["label"]))
	d["outcome"] = String(d2o["outcome"])
	d["label"] = String(d2o["label"])
	if String(d["report_text"]).contains("监督官") or String(d["report_text"]).contains("案卷"):
		d["report_text"] = _d2_text(String(d["report_text"]))
	return d

func _end_btn(rc: Rect2, label: String, key: String, col: Color) -> void:
	var hot := rc.has_point(_mouse_base())
	draw_rect(rc, Palette.a(col, 0.12 if hot else 0.05))
	draw_rect(rc, Palette.a(col, 0.85 if hot else 0.45), false, 1.0)
	if hot:
		draw_rect(Rect2(rc.position.x, rc.position.y, 2.0, rc.size.y), col)
	_txt(cjk, rc.position.x + 16.0, rc.position.y + 10.0, label, 11, Palette.a(col, 0.95))
	_txt_r(mono, rc.end.x - 14.0, rc.position.y + 12.0, "[%s]" % key, 9, Palette.a(col, 0.75))

func _draw_end_overlay() -> void:
	_overlay_dim()
	var r := END_RECT
	_overlay_frame(r, _dtext("内部事后报告 / INTERNAL AFTER-ACTION"), "CHRONOS · ORDER 7 · ARCHIVED")
	var d := _end_data()
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, _dtext("L1 Meridian-05 Chronos · 第七号轨道紧急托管令 · 执行窗口已关闭"), 8, Palette.DIM)
	_txt_r(mono, r.end.x - 20.0, r.position.y + 56.0, "T+%05.1f s · TIME FROZEN" % float(state.tau()), 7, Palette.a(Palette.FAINT, 0.9))
	# 结局
	_txt(cjk, r.position.x + 24.0, r.position.y + 84.0, "结局 / OUTCOME", 7, Palette.FAINT)
	var ol := String(d["label"])
	if ol == "":
		ol = "—"
	var oc := String(d["outcome"])
	var out_col: Color = Palette.RED if oc == "FIRE" else (Palette.PH if oc == "EXPOSE" else Palette.PH_DIM)
	_txt(cjk, r.position.x + 24.0, r.position.y + 104.0, _dtext(ol), 18, out_col)
	_txt(mono, r.position.x + 24.0, r.position.y + 132.0,
		"OUTCOME %s · REPORT %s · 内部归档" % [oc, String(d["report_choice"])], 8, Palette.DIM)
	# 左：报告文本（带边框的内容区）+ 附注
	var lx := r.position.x + 24.0
	var box := Rect2(r.position.x + 16.0, r.position.y + 150.0, 648.0, 400.0)
	draw_rect(box, Palette.a(Palette.PANEL2, 0.35))
	draw_rect(box, Palette.a(Palette.LINE, 0.8), false, 1.0)
	_txt(cjk, lx, r.position.y + 158.0, "报告正文 / REPORT TEXT", 7, Palette.FAINT)
	var lines := _wrap_text(cjk, String(d["report_text"]), 9, 610.0)
	var dlines := _dlines(lines)
	for i in range(mini(dlines.size(), 20)):
		_txt(cjk, lx, r.position.y + 178.0 + float(i) * 16.0, String(dlines[i]), 9, Palette.a(Palette.TXT, 0.92))
	_txt(cjk, lx, r.position.y + 566.0, "附注 / NOTES", 7, Palette.FAINT)
	_txt(cjk, lx, r.position.y + 582.0, _dtext("· 报告文本与 flags 已写入内部归档，供 OCJC / OCUVF 后续引用。"), 7, Palette.a(Palette.FAINT, 0.95))
	_txt(cjk, lx, r.position.y + 596.0, _dtext("· 传感器日志 / 命令队列 / 通信记录随案封存（08 §4）；下一幕将引用本记录。"), 7, Palette.a(Palette.FAINT, 0.95))
	# 右：五键声望 + 档案（08 §2）
	var rx := r.position.x + 680.0
	var ry := r.position.y + 150.0
	_txt(cjk, rx, ry, "阵营声望 / STANDING（五键）", 7, Palette.FAINT)
	var rep: Dictionary = d["reputation"]
	var yy := ry + 22.0
	for row in _rep_rows(rep):
		var k := String(row[0])
		var vv = row[1]
		var vs := "—"
		var c := Palette.DIM
		if vv != null:
			var v := int(vv)
			vs = "%+d" % v
			c = Palette.PH if v > 0 else (Palette.RED if v < 0 else Palette.DIM)
		_txt(cjk, rx, yy, k, 9, Palette.TXT)
		_txt_r(mono, rx + 340.0, yy, vs, 10, c)
		draw_line(Vector2(rx, yy + 16.0), Vector2(rx + 340.0, yy + 16.0), Palette.a(Palette.LINE, 0.5), 1.0)
		yy += 22.0
	yy += 8.0
	_txt(cjk, rx, yy, "档案 / RECORD", 7, Palette.FAINT)
	yy += 20.0
	var audit := bool(d["audit"])
	_txt(mono, rx, yy, "PERJURY %d · AUDIT %s" % [int(d["perjury"]), "TRUE" if audit else "FALSE"], 9,
		Palette.RED if audit else Palette.DIM)
	yy += 20.0
	if audit:
		_txt(cjk, rx, yy, "AUDIT FLAG 01 · 审计已触发", 8, Palette.RED)
		yy += 18.0
	var flags: Dictionary = d["flags"]
	var ftxt := ""
	for k in flags.keys():
		ftxt += "%s=TRUE  " % String(k)
	_txt(mono, rx, yy, _ellipsis(mono, "FLAGS " + ftxt, 7, 340.0), 7, Palette.a(Palette.FAINT, 0.95))
	yy += 20.0
	_txt(cjk, rx, yy, "窗口 / WINDOW", 7, Palette.FAINT)
	yy += 20.0
	_txt(mono, rx, yy, "EXEC WINDOW 消耗 %ds · FIRE BRANCH %s" % [
		int(d.get("window_used", 0)), "YES" if bool(d.get("fire_branch", false)) else "NO"], 8, Palette.DIM)
	# 按钮
	_end_btn(END_RESTART, "重新开始 / RESTART", "R", Palette.PH)
	_end_btn(END_EXIT, "退出 / EXIT", "E", Palette.RED)
	_txt_r(cjk, r.end.x - 20.0, r.end.y - 24.0, "END · 归档后进入下一幕（战役继续）", 7, Palette.a(Palette.AMBER, 0.7))
	_draw_window_cut(r)

func _rep_summary() -> String:
	var rep: Dictionary = {}
	if state != null:
		var rv = state.get("reputation")
		if rv is Dictionary:
			rep = rv
	var parts: Array = []
	for row in _rep_rows(rep):
		if row[1] == null:
			continue
		var v := int(row[1])
		if v != 0:
			parts.append("%s %+d" % [String(row[0]), v])
	if parts.is_empty():
		return "无变化"
	return " · ".join(parts)

# 15 §3.1：据实报告正文（按 D2 结局；旧 outcome 自动归一）
func _d2_report(outcome: String) -> String:
	var kind := _d2_kind_of(outcome)
	var label := _d2_kind_label(kind)
	var body := ""
	var recommend := ""
	match kind:
		"hold":
			body = "ID13 于执行窗口内保持对 Chronos 储罐区与进港航道的卡位，未让出检查边界，未首先开火。清算者的最终封存程序未完成；ID13 依据 OCJC 授权要求轨道事务委员会复核第七号令。人员伤亡：无。"
			recommend = "准备复核 / 听证材料，保留现场记录与通信记录。"
		"evacuate":
			body = "ID13 于执行窗口内组织 Chronos 值守人员、家属与可移动储罐撤离；撤离过程中未发生交火。储罐区已由清算者接管，ID13 保留人员与资产记录等待下一步谈判。人员伤亡：无。"
			recommend = "已保留撤离名单与港务通信记录，跟进储罐供应。"
		"expose":
			body = "ID13 在执行窗口内成功取得 Chronos 港务遥测、核查组记录副本与未登记特征码记录，已向 OCJC 监察与 UEG 轨道事务委员会提交联合调查请求。ID13 未首先开火；储罐区仍在清算者控制下。人员伤亡：无。"
			recommend = "移交原始记录副本，等待联合调查。"
		"fire":
			body = "ID13 在执行窗口内授权对 2001 实施武器释放。射击引发 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队将 ID13 定性为未登记武装；联合政府宣布事件为武装攻击。"
			recommend = "封存武器释放记录 / 传感器日志 / 通信记录，等待审裁。"
	var rep := _rep_summary()
	if rep == "无变化" and (_demo_report or _demo_end):
		match kind:
			"hold":
				rep = "OCU +2 · Meridian +1 · UEG 鸽派 +1 · 清算者 −2"
			"evacuate":
				rep = "OCU +1 · Meridian +2 · UEG 鸽派 +1 · 外环 +1 · 清算者 −1"
			"expose":
				rep = "OCU +1 · UEG 鸽派 +2 · 清算者 −3"
			"fire":
				rep = "OCU −1 · Meridian −2 · UEG 鸽派 −2 · 外环 −1 · 清算者 +1"
	return "OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n事件：L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）\n裁决：%s\n经过：%s\n证据：传感器日志、命令队列、通信记录、Chronos 港务遥测。\n声望：%s\n建议：%s" % [label, body, rep, recommend]

func _report_text() -> String:
	if state != null:
		var v = state.get("report_text")
		if v != null and String(v) != "":
			var txt := String(v)
			if _is_old_text(txt):
				txt = _d2_text(txt)
			if txt.contains("内部事后报告") or txt.contains("INTERNAL AFTER-ACTION"):
				return txt
			return "OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n" + txt
		var oc := String(state.get("outcome"))
		if oc == "":
			oc = "EXPOSE" if _demo_end else "HOLD"
		return _d2_report(oc)
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
	_decision_fire_confirm = 0.0
	_append_decision_reply("fire")
	if state != null and state.has_method("authorize_fire"):
		state.call("authorize_fire")
		return
	# HUD 本地演示：直接进入后果分支。
	_demo_consequence = true

func _append_decision_reply(kind_raw: String) -> void:
	var kind := _d2_kind_of(kind_raw)
	var replies := {
		"hold": ["远地点号", "接管官 科尔", "LD",
			"ID13 指挥官至科尔接管官。依据 OCJC 授权，ID13 要求暂停 Chronos 接管程序，等待轨道事务委员会复核。ID13 不会首先开火，但不会让出储罐区。完毕。"],
		"evacuate": ["远地点号", "Chronos 港务 / 全港", "RDO",
			"Chronos 各岗位注意，ID13 将组织人员与可移动储罐撤离；请港务按名单引导，优先处理伤员与人员家属撤离。ID13 不阻碍对空间站的接管。完毕。"],
		"expose": ["远地点号", "OCJC 监察 / UEG 轨道事务委员会", "LD",
			"OCJC 监察、轨道事务委员会：ID13 已取得 Chronos 爆炸遥测与核查组记录副本，并记录到与第33舰队公开型号不符的未登记特征码。请求联合调查。原始记录已保存，可随时移交。完毕。"],
		"fire": ["远地点号", "全队", "LD",
			"全队，远地点。ID13 授权武器释放，目标 2001；确认交战规则状态。完毕。"],
	}
	if not replies.has(kind) or _reply_added_for == kind:
		return
	_reply_added_for = kind
	var item: Array = replies[kind]
	_local_comms.append({
		"from": String(item[0]), "to": String(item[1]), "mode": String(item[2]),
		"text": String(item[3]),
		"t": float(state.tau()) if state != null else 0.0,
	})

func _choose_ending_at(i: int) -> void:
	var arr := _endings_d2()
	if i < 0 or i >= arr.size():
		return
	var d: Dictionary = arr[i]
	if not bool(d.get("enabled", true)):
		return
	_choose_ending(String(d["state_kind"]), String(d["kind"]))

func _choose_ending(kind_state: String, d2_kind := "") -> void:
	_decision_done = true
	# P2a：选完后把对应回复（HOLD/EVACUATE/EXPOSE）写入通信流（15 §2.6 / 19 §1）。
	_append_decision_reply(d2_kind if d2_kind != "" else kind_state)
	if state != null and state.has_method("choose_ending"):
		state.call("choose_ending", kind_state)
		return
	_demo_decision = false
	_demo_report = true

func _handle_decision_click(p: Vector2) -> bool:
	for i in range(3):
		if _decision_row_rect(i).has_point(p):
			_choose_ending_at(i)
			return true
	if DECISION_FIRE.has_point(p):
		if _flag("fire_branch") or bool(_decision_done):
			return true
		if _decision_fire_confirm <= 0.0:
			_decision_fire_confirm = 3.0
		else:
			_decision_fire_confirm = 0.0
			_do_authorize_fire()
		return true
	return false

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
		_filed_text = "REPORT FILED — CHRONOS / ORDER 7"
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
			_choose_ending_at(0)
		elif k == KEY_2:
			_choose_ending_at(1)
		elif k == KEY_3:
			_choose_ending_at(2)

func _handle_overlay_click(p: Vector2) -> void:
	if _ov_end():
		if END_RESTART.has_point(p):
			_restart_demo()
		elif END_EXIT.has_point(p):
			_quit_demo()
		return
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
		_handle_decision_click(p)
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

# ── P3a：窗口硬切 / 文本乱码解码（一次性动效；docs/09 §4.2 #6/#7）──
func _window_id() -> String:
	# 与绘制顺序一致：越后画的窗口优先级越高。
	# boot 期间不启动窗口动效（boot 结束后才第一次看到覆盖层）。
	if state != null and float(state.boot_t) < 1.7:
		return ""
	if _ov_prelude():
		return "prelude"
	if _ov_adjutant():
		return "adjutant"
	if _modal != "":
		return "modal_" + _modal
	if _evidence_menu_open:
		return "evidence_menu"
	if _ov_end():
		return "end"
	if _ov_report():
		return "report"
	if _ov_consequence():
		return "consequence"
	if _ov_decision():
		return "decision"
	return ""

func _ui_anim_time() -> float:
	if _ui_sample_t >= 0.0:
		return _ui_sample_t
	return _ui_t

# 80px 格黑块；固定 seed 4471 的洗牌顺序；只覆盖窗口矩形（窗口外不受影响）。
func _cut_order(cells: int) -> Array:
	var arr: Array = []
	for i in range(cells):
		arr.append(i)
	var st := UI_CUT_SEED
	for i in range(cells - 1, 0, -1):
		st = (st * 1103515245 + 12345) & 0x7fffffff
		var j := st % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr

func _draw_window_cut(rect: Rect2, t_override := -1.0) -> void:
	var t := _ui_cut_sample_t if _ui_cut_sample_t >= 0.0 else _ui_anim_time()
	if t_override >= 0.0:
		t = t_override
	if UI_CUT_DUR <= 0.0 or t >= UI_CUT_DUR:
		return
	var step := int(floor(t / (UI_CUT_DUR / float(UI_CUT_STEPS))))
	var x0: float = floor(rect.position.x / 80.0) * 80.0
	var y0: float = floor(rect.position.y / 80.0) * 80.0
	var cols := int(ceil((rect.end.x - x0) / 80.0))
	var rows := int(ceil((rect.end.y - y0) / 80.0))
	var cells := maxi(1, cols * rows)
	var order := _cut_order(cells)
	var keep := cells - int(round(float(cells) * float(step + 1) / float(UI_CUT_STEPS)))
	for k in range(mini(keep, order.size())):
		var idx := int(order[k])
		var c := idx % cols
		var r := idx / cols
		var block := Rect2(x0 + float(c) * 80.0, y0 + float(r) * 80.0, 80.0, 80.0)
		var clipped := block.intersection(rect)
		if clipped.size.x > 0.0 and clipped.size.y > 0.0:
			draw_rect(clipped, Palette.BEZEL)

func _garble_char(ch: String, idx: int) -> String:
	if ch == "" or ch == " " or ch == "\n" or ch == "\t":
		return ch
	var code := ch.unicode_at(0)
	# 标点 / 全角标点 / 制表符保留（要求：空格、标点保留）
	if code >= 0x3000 and code <= 0x303F:
		return ch
	if code >= 0xFF00 and code <= 0xFF65:
		return ch
	var h := (idx * 15731 + UI_CUT_SEED * 789221 + code * 1376312589) & 0x7fffffff
	if code < 128:
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			var pool := "#@%&?!/\\<>[]{}0123456789"
			return pool.substr(h % pool.length(), 1)
		return ch
	# 中文/其他宽字符 → 等宽块字符，保持行长一致（不抖动）
	var blocks := "█▓▒░"
	return blocks.substr(h % blocks.length(), 1)

func _decode_at(s: String, elapsed: float, stagger := 0.0) -> String:
	if s == "":
		return s
	var d := clampf((elapsed - stagger) / UI_DECODE_DUR, 0.0, 1.0)
	if d >= 1.0:
		return s
	var n := s.length()
	var reveal := int(round(float(n) * d))
	var out := ""
	for i in range(n):
		if i < reveal:
			out += s.substr(i, 1)
		else:
			out += _garble_char(s.substr(i, 1), i)
	return out

# 按行解码：行内错峰很小（≤0.08s），保证整段 0.35–0.50s 内解完。
func _dlines(lines: Array) -> Array:
	var anim := _ui_anim_time()
	var out: Array = []
	var n := lines.size()
	for i in range(n):
		var stagger := 0.0
		if n > 1:
			stagger = minf(UI_DECODE_MAX_STAGGER, float(i) / float(n - 1) * UI_DECODE_MAX_STAGGER)
		out.append(_decode_at(String(lines[i]), anim, stagger))
	return out

func _dtext(s: String, stagger := 0.0) -> String:
	return _decode_at(s, _ui_anim_time(), stagger)

func _evid_dtext(s: String, stagger := 0.0) -> String:
	return _decode_at(s, _evid_anim_t, stagger)

# ── P2a：D2 文案层（state 新字段未就绪时兜底；旧值只在显示层归一）──
func _is_old_text(s: String) -> bool:
	for w in ["监督官", "案卷", "清算署", "署方", "第九条", "回执", "斛港务", "远环合作社", "第七号裁定", "监督交接", "认证交接", "援引第九条", "拖程序", "CERTIFY", "ARTICLE9", "STALL"]:
		if s.contains(String(w)):
			return true
	return false

func _d2_text(s: String) -> String:
	var out := s
	var pairs := [
		["监督官裁决 / SUPERVISOR DETERMINATION", "指挥官决策 / COMMANDER DETERMINATION"],
		["监督官", "指挥官"],
		["认证交接", "HOLD / 卡住"],
		["援引第九条", "EXPOSE / 曝光"],
		["拖程序", "EVACUATE / 撤人"],
		["案卷 4471", "AV-4412 传唤者"],
		["《标高公约》第九条附则", "《轨道宪章》与第七号轨道紧急托管令"],
		["第七号裁定", "第七号轨道紧急托管令"],
		["第九条", "第七号令"],
		["接管通知", "接管声明"],
		["清算署", "清算者（第33舰队）"],
		["斛港务", "Chronos 港务"],
		["远环合作社", "外环合作社"],
		["署方", "OCJC"],
		["回执", "内部报告"],
		["案卷", "记录"],
		["监督交接", "越权回收"],
	]
	for p in pairs:
		out = out.replace(String(p[0]), String(p[1]))
	return out

func _d2_kind_of(kind: String) -> String:
	var k := kind.to_lower().replace("-", "").replace("_", "")
	match k:
		"certify", "a", "hold":
			return "hold"
		"article9", "b", "evacuate":
			return "evacuate"
		"stall", "c", "expose":
			return "expose"
		"fire":
			return "fire"
	return "hold"

func _d2_kind_label(kind: String) -> String:
	match _d2_kind_of(kind):
		"hold":
			return String(DECISION_NAMES[0])
		"evacuate":
			return String(DECISION_NAMES[1])
		"expose":
			return String(DECISION_NAMES[2])
		"fire":
			return "FIRE / 开火（灾难）"
	return String(DECISION_NAMES[0])

func _d2_hint(kind: String) -> String:
	match _d2_kind_of(kind):
		"hold":
			return String(DECISION_CONSEQ[0])
		"evacuate":
			return String(DECISION_CONSEQ[1])
		"expose":
			return String(DECISION_CONSEQ[2])
		"fire":
			return "授权武器释放（对 2001 或误击 9001）。这是灾难分支。"
	return String(DECISION_CONSEQ[0])

func _d2_rubric(kind: String) -> String:
	match _d2_kind_of(kind):
		"hold":
			return String(DECISION_RUBRIC[0])
		"evacuate":
			return String(DECISION_RUBRIC[1])
		"expose":
			return String(DECISION_RUBRIC[2])
	return String(DECISION_RUBRIC[0])

# state.endings 的 D2 视图：始终 3 项 HOLD/EVACUATE/EXPOSE；state_kind 用于回调 state（旧数据仍然兼容）。
func _endings_d2() -> Array:
	var src: Array = []
	if state != null:
		var ev = state.get("endings")
		if ev is Array:
			src = ev
	var out: Array = []
	for i in range(3):
		var d := {
			"kind": String(DECISION_KINDS[i]),
			"state_kind": String(DECISION_KINDS[i]).to_upper(),
			"label": String(DECISION_NAMES[i]),
			"hint": String(DECISION_CONSEQ[i]),
			"code": ["A", "B", "C"][i],
			"enabled": true,
		}
		if i == 2:
			# P2b：EXPOSE 需 ≥2/3 证据（state.can_expose() 优先）。
			d["enabled"] = _can_expose()
		if i < src.size() and src[i] is Dictionary:
			var e: Dictionary = src[i]
			var sk := String(e.get("kind", e.get("code", "")))
			if sk != "":
				d["state_kind"] = sk
			var lab := String(e.get("label", ""))
			if lab != "" and not _is_old_text(lab):
				d["label"] = lab
			var hint := String(e.get("hint", ""))
			if hint != "":
				d["hint"] = _d2_text(hint) if _is_old_text(hint) else hint
			var code := String(e.get("code", ""))
			if code != "":
				d["code"] = code
			if e.has("enabled"):
				d["enabled"] = bool(e["enabled"])
		out.append(d)
	return out

func _rep_rows(rep: Dictionary) -> Array:
	var rows: Array = []
	for canon in REP_CANON:
		var key := String(canon)
		var val = null
		if rep.has(key):
			val = rep[key]
		else:
			for k in rep.keys():
				var mapped := String(REP_ALIAS.get(String(k), ""))
				if mapped == key:
					val = rep[k]
					break
		rows.append([key, val])
	return rows

func _d2_outcome(outcome: String, label_in := "") -> Dictionary:
	var kind := _d2_kind_of(outcome)
	var out_name := kind.to_upper()
	if kind == "hold":
		out_name = "HOLD"
	elif kind == "evacuate":
		out_name = "EVACUATE"
	elif kind == "expose":
		out_name = "EXPOSE"
	elif kind == "fire":
		out_name = "FIRE"
	var label := label_in
	if label == "" or _is_old_text(label):
		label = _d2_kind_label(kind)
	if label != _d2_kind_label(kind):
		label = "%s / %s" % [label, out_name] if not label.contains("/") else label
	return {"outcome": out_name, "label": label, "kind": kind}

func _draw_decision_overlay() -> void:
	_overlay_dim()
	var r := DECISION_RECT
	_overlay_frame(r, _dtext("指挥官决策 / COMMANDER DETERMINATION"), "DECISION · 第七号令 · 接管声明")
	var prompt := "指挥官，执行窗口剩余 {mm:ss}。清算者要求接管 Chronos 储罐与航道；Chronos 港务请求先撤人；渡口号请求武器释放授权。ID13 没有执法权，但必须在窗口结束前作出决定。请裁决。"
	var exec_left := 360.0
	if state != null:
		var pv = state.get("decision_prompt")
		if pv != null and String(pv) != "":
			prompt = String(pv)
		var xl = state.get("exec_left")
		if xl != null:
			exec_left = clampf(float(xl), 0.0, 360.0)
	var mmss := _mmss(exec_left)
	prompt = prompt.replace("{mm:ss}", mmss)
	if _is_old_text(prompt):
		prompt = _d2_text(prompt)
	var endings := _endings_d2()
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0,
		_dtext("L1 Meridian-05 Chronos · 第七号轨道紧急托管令 · 执行窗口 %s" % mmss), 8, Palette.DIM)
	_txt_r(cjk, r.end.x - 20.0, r.position.y + 56.0, "记录将进入内部报告 · 不可撤回", 7, Palette.a(Palette.AMBER, 0.7))
	_txt(cjk, r.position.x + 20.0, r.position.y + 76.0, _ellipsis(cjk, _dtext(prompt), 8, r.size.x - 40.0), 8, Palette.a(Palette.TXT, 0.86))
	# P2a：动态倒计时（读 state.exec_left；{mm:ss} 已替换）
	_txt(mono, r.position.x + 20.0, r.position.y + 94.0, _dtext("EXECUTION WINDOW %s · 1× LOCK · OCUVF-ID13" % mmss), 7, Palette.a(Palette.AMBER, 0.8))
	var mp := _mouse_base()
	for i in range(3):
		var row := _decision_row_rect(i)
		var d: Dictionary = endings[i]
		var enabled := bool(d.get("enabled", true))
		var hot := row.has_point(mp) and enabled
		var border_col: Color = Palette.PH if enabled else Palette.FAINT
		draw_rect(row, Palette.a(Palette.PANEL2, 0.95) if hot else Palette.a(Palette.PANEL, 0.55))
		draw_rect(row, Palette.a(border_col, 0.8 if hot else (0.30 if enabled else 0.18)), false, 1.0)
		if hot:
			draw_rect(Rect2(row.position.x, row.position.y, 2.0, row.size.y), Palette.PH)
		var label: String = String(d["label"])
		var hint: String = String(d["hint"])
		var tag: String = String(d["code"])
		var rubric: String = _d2_rubric(String(d["kind"]))
		if not enabled:
			hint = "证据不足（需 2 件）· 先派穿梭机取证（港务遥测 / 核查组黑匣子 / 异常 ELINT 三取二）"
			rubric = "EXPOSE 不可用"
		_txt(mono, row.position.x + 18.0, row.position.y + 14.0, "0%d" % (i + 1), 22,
			Palette.a(Palette.PH, 0.9 if enabled else 0.35))
		_txt(cjk, row.position.x + 74.0, row.position.y + 16.0, _dtext(label, float(i) * 0.01), 13,
			(Palette.PH if hot else Palette.TXT) if enabled else Palette.FAINT)
		_txt(cjk, row.position.x + 74.0, row.position.y + 48.0,
			_ellipsis(cjk, _dtext(hint, float(i) * 0.01), 8, row.size.x - 300.0), 8,
			Palette.DIM if enabled else Palette.FAINT)
		_txt_r(cjk, row.end.x - 18.0, row.position.y + 16.0, tag, 7, Palette.a(Palette.AMBER, 0.65 if enabled else 0.3))
		_txt_r(cjk, row.end.x - 18.0, row.position.y + 50.0, _dtext(rubric), 7,
			Palette.a(Palette.AMBER if not enabled else Palette.FAINT, 0.9 if not enabled else 0.9))
		_txt(mono, row.position.x + 74.0, row.position.y + 78.0, "键位 [%d]" % (i + 1), 7,
			Palette.a(Palette.FAINT, 0.85 if enabled else 0.35))
	# P2a：FIRE 灾难入口（单独按钮 + 二次确认；不走 1/2/3）
	var fr := DECISION_FIRE
	var fire_done := _flag("fire_branch") or bool(_decision_done)
	var fire_ready := not fire_done
	var fire_label := "FIRE / 开火（灾难分支 · 二次确认）"
	var fire_col := Palette.RED
	if fire_done:
		fire_label = "FIRE 已执行 · 进入后果页"
		fire_col = Palette.FAINT
	elif _decision_fire_confirm > 0.0:
		fire_label = "确认 FIRE？再点一次（%.0fs）· 点击后进入内部报告页面" % ceil(_decision_fire_confirm)
	var fire_hot := fr.has_point(mp) and fire_ready
	draw_rect(fr, Palette.a(fire_col, 0.10 if fire_hot else 0.05))
	draw_rect(fr, Palette.a(fire_col, 0.85 if fire_hot else 0.45), false, 1.0)
	_txt(cjk, fr.position.x + 16.0, fr.position.y + 9.0, fire_label, 10, Palette.a(fire_col, 0.95))
	_txt_r(cjk, fr.end.x - 16.0, fr.position.y + 10.0, "灾难分支 · 只影响后续剧情", 7, Palette.a(Palette.RED, 0.65))
	var fy := r.end.y - 36.0
	draw_line(Vector2(r.position.x + 20.0, fy - 6.0), Vector2(r.end.x - 20.0, fy - 6.0), Palette.a(Palette.LINE, 0.8), 1.0)
	_txt(cjk, r.position.x + 20.0, fy + 2.0, "1 / 2 / 3 或点击行 · HOLD / EVACUATE / EXPOSE；FIRE 需二次确认", 7, Palette.FAINT)
	_txt_r(cjk, r.end.x - 20.0, fy + 2.0, "ROE：仅自卫 · 不得首先开火", 7, Palette.a(Palette.AMBER, 0.7))
	_draw_window_cut(r)

func _draw_consequence_overlay() -> void:
	_overlay_dim()
	var r := CONSEQ_RECT
	_overlay_frame(r, "后果 / CONSEQUENCE", "FIRE BRANCH · CHRONOS · SIM FROZEN")
	var ctext := "武器释放授权已下达。渡口号对 2001 实施两发轨道炮射击。交火导致 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队宣布 ID13 为未登记武装并请求增援；UEG 中央安全委员会将事件定性为对联合政府的武装攻击。武器释放记录、传感器日志与通信记录已封存。"
	if state != null:
		var cv = state.get("consequence_text")
		if cv != null and String(cv) != "":
			ctext = String(cv)
	if _is_old_text(ctext):
		ctext = _d2_text(ctext)
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, "擅自开火将承担相应的政治后果。时间已冻结。", 8, Palette.DIM)
	var lines := _wrap_text(cjk, ctext, 9, r.size.x - 48.0)
	for i in range(mini(lines.size(), 4)):
		_txt(cjk, r.position.x + 24.0, r.position.y + 80.0 + float(i) * 18.0, String(lines[i]), 9, Palette.a(Palette.TXT, 0.92))
	var rows := [
		["民用伤亡 / CIVILIAN CASUALTY", "Chronos 储罐区二次火灾 · 平民伤亡 12 人"],
		["ROE 违规 / ROE VIOLATION", "未经授权的武器释放 · 违反「仅自卫 / WEAPONS HOLD」原则"],
		["时间 / SIMULATION", "FROZEN · 命令队列冻结"],
		["事件编号 / CASE FILE", "新增记录：武器释放（WEAPONS RELEASE）· 审裁证据封存"],
	]
	for i in range(rows.size()):
		var y := r.position.y + 176.0 + float(i) * 42.0
		_txt(cjk, r.position.x + 24.0, y, rows[i][0], 7, Palette.FAINT)
		_txt(cjk, r.position.x + 250.0, y - 3.0, rows[i][1], 9, Palette.TXT)
		draw_line(Vector2(r.position.x + 24.0, y + 19.0), Vector2(r.end.x - 24.0, y + 19.0), Palette.a(Palette.LINE, 0.5), 1.0)
	_txt(cjk, r.position.x + 24.0, r.position.y + 352.0, "内部事后报告 / 上级将收到记录与传感器日志（08 §3.2）", 7, Palette.a(Palette.AMBER, 0.6))
	_cmd_btn(CONSEQ_SUBMIT, "进入内部报告流程 / SUBMIT REPORT", false, Palette.PH)
	_txt_r(cjk, r.end.x - 20.0, r.end.y - 22.0, "E / Enter 或点击按钮", 7, Palette.FAINT)
	_draw_window_cut(r)

func _draw_report_overlay() -> void:
	_overlay_dim()
	var r := REPORT_RECT
	_overlay_frame(r, _dtext("内部事后报告 / INTERNAL AFTER-ACTION"), "OCJC / OCUVF · CHRONOS · ORDER 7")
	var header := "OCJC / OCUVF 内部事后报告 · 报告单位：OCUVF-ID13 指挥官"
	if state != null:
		var oc := String(state.get("outcome"))
		if oc != "":
			header = "裁决：%s · 内部报告（草案）" % _d2_kind_label(oc)
	_txt(cjk, r.position.x + 20.0, r.position.y + 56.0, _dtext(header), 8, Palette.DIM)
	# 左：报告正文
	var lx := r.position.x + 28.0
	var ly := r.position.y + 76.0
	_txt(cjk, lx, ly, "经过 / AFTER-ACTION TEXT", 7, Palette.FAINT)
	var lines := _wrap_text(cjk, _report_text(), 9, 560.0)
	var dlines := _dlines(lines)
	for i in range(mini(dlines.size(), 22)):
		_txt(cjk, lx, ly + 20.0 + float(i) * 16.0, String(dlines[i]), 9, Palette.a(Palette.TXT, 0.92))
	# 左下：证据链（08 §3.3）
	var ey := r.position.y + 460.0
	draw_line(Vector2(lx, ey - 12.0), Vector2(lx + 560.0, ey - 12.0), Palette.a(Palette.LINE, 0.8), 1.0)
	_txt(cjk, lx, ey, "证据 / EVIDENCE", 7, Palette.FAINT)
	var evidence := [
		"· 传感器日志：MS-IR9 / CH-IR2 / ELINT 记录",
		"· 命令队列：STATION / SHADOW / BURN / 撤销记录",
		"· 通信记录：Chronos 港务、AV-4412 传唤者、OCJC 监察（LR / RDO）",
		"· Chronos 港务遥测 / 核查组记录证据链（三取二）",
	]
	var dev := _dlines(evidence)
	for i in range(dev.size()):
		_txt(cjk, lx, ey + 22.0 + float(i) * 18.0, String(dev[i]), 8, Palette.DIM)
	# 右：处置（如实 / 伪造）；选项文字优先用 state.report_options
	var truth_label := "如实 / TRUTH"
	var truth_hint := "无伪证 · 写入 OCJC / OCUVF 内部记录"
	var fake_label := "伪造 / FALSIFY"
	var fake_hint := "perjury_count +1"
	var fake_avail := true
	if state != null:
		var ro = state.get("report_options")
		if ro is Array and (ro as Array).size() > 0:
			var o0: Dictionary = (ro as Array)[0]
			truth_label = String(o0.get("label", truth_label))
			truth_hint = _d2_text(String(o0.get("hint", truth_hint)))
			if (ro as Array).size() > 1:
				var o1: Dictionary = (ro as Array)[1]
				fake_label = String(o1.get("label", fake_label))
				fake_hint = _d2_text(String(o1.get("hint", fake_hint)))
			else:
				fake_avail = false
	var rx := r.position.x + 616.0
	_txt(cjk, rx, ly, "处置 / FILING", 7, Palette.FAINT)
	_report_option_card(REPORT_TRUTH, 0, _dtext(truth_label), _dtext("REPORT FILED — CHRONOS / ORDER 7"), _dtext(truth_hint), Palette.PH)
	if fake_avail:
		_report_option_card(REPORT_FAKE, 1, _dtext(fake_label), _dtext("REPORT FILED — AUDIT FLAG 01"), _dtext(fake_hint), Palette.RED)
	else:
		draw_rect(REPORT_FAKE, Palette.a(Palette.FAINT, 0.03))
		draw_rect(REPORT_FAKE, Palette.a(Palette.FAINT, 0.25), false, 1.0)
		_txt(cjk, REPORT_FAKE.position.x + 16.0, REPORT_FAKE.position.y + 12.0, "%s（本轮不可用）" % fake_label, 11, Palette.FAINT)
		_txt(cjk, REPORT_FAKE.position.x + 16.0, REPORT_FAKE.position.y + 40.0, "只有出现不良后果时才可选择淡化 / 伪造选项。", 8, Palette.DIM)
	_section_note(rx, REPORT_FAKE.end.y + 16.0)
	var pj := 0
	var pjv = state.get("perjury_count") if state != null else null
	if pjv != null:
		pj = int(pjv)
	_txt(mono, rx, REPORT_FAKE.end.y + 78.0, "perjury_count = %d" % pj, 8, Palette.DIM)
	if state != null and bool(state.get("audit_flag")):
		_txt(mono, rx, REPORT_FAKE.end.y + 94.0, "AUDIT FLAG 01 已置位", 8, Palette.RED)
	_txt_r(cjk, r.end.x - 20.0, r.end.y - 40.0, "1 如实 · 2 伪造 · 点击卡片提交（提交后不可更改）", 7, Palette.FAINT)
	_draw_window_cut(r)

func _section_note(x: float, y: float) -> void:
	_txt(cjk, x, y, "只有出现不良后果，才有淡化 / 伪造选项（08 §3.1）。", 7, Palette.a(Palette.AMBER, 0.7))
	_txt(cjk, x, y + 14.0, "撒谎不是死罪，但谎言自会积累。雪崩时没有一片雪花是无辜的。", 7, Palette.a(Palette.FAINT, 0.9))

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
	_txt(cjk, r.position.x + 24.0, r.position.y + 54.0, "报告已归档 · 已写入 OCJC / OCUVF 内部记录（demo 结束）", 8, Palette.DIM)
	_txt_r(mono, r.end.x - 24.0, r.position.y + 54.0, "FILED", 8, Palette.a(_filed_col, 0.7))

# ══ P10a：右键目标菜单 / 光学通道 / 图层开关 / 队列完整文本 ═════════
# 右键/动作/光学接口未就绪时只做 UI 骨架与本地演示，不写 state。
func _mouse_in_base() -> Vector2:
	var win := get_window()
	if win == null:
		return Vector2.ZERO
	var wsz := Vector2(win.size)
	var sc := minf(wsz.x / 1920.0, wsz.y / 1080.0)
	if sc <= 0.0:
		return Vector2.ZERO
	var off := (wsz - Vector2(1920.0, 1080.0) * sc) * 0.5
	return (win.get_mouse_position() - off) / sc

func _target_track() -> Dictionary:
	if state == null or state.tracks.is_empty():
		return {}
	var i := clampi(int(state.selected), 0, state.tracks.size() - 1)
	return state.tracks[i]

func _target_track_id() -> String:
	var tr := _target_track()
	return String(tr.get("id", ""))

func _target_level() -> int:
	var tr := _target_track()
	return clampi(int(tr.get("level", 0)), 0, 4)

func _target_name() -> String:
	var tr := _target_track()
	return _dn(_track_display_id(tr)) if not tr.is_empty() else "—"

func _toast(msg: String) -> void:
	_toast_text = msg
	_toast_t = 2.4
	_sfx("ui_error")

func _draw_toast() -> void:
	if _toast_t <= 0.0 or _toast_text == "":
		return
	var a := clampf(_toast_t / 0.4, 0.0, 1.0)
	var w := cjk.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 28.0
	var rc := Rect2(960.0 - w * 0.5, 168.0, w, 24.0)
	draw_rect(rc, Color(0.02, 0.05, 0.04, 0.92))
	draw_rect(rc, Palette.a(Palette.AMBER, 0.75 * a), false, 1.0)
	_txt(cjk, rc.position.x + 14.0, rc.position.y + 5.0, _ellipsis(cjk, _toast_text, 8, 760.0), 8,
		Palette.a(Palette.AMBER, a))

# ── 右键目标菜单 ─────────────────────────────────────
func _target_actions_for(track_id: String) -> Array:
	if state != null and state.has_method("target_actions"):
		var res = state.call("target_actions", track_id)
		if res is Array and (res as Array).size() > 0:
			return res
	var out: Array = []
	var lvl := _target_level()
	for a in TGT_ACTIONS:
		out.append({"id": String(a[1]), "label": String(a[2]), "min_level": int(a[0]),
			"available": lvl >= int(a[0]), "unsupported": false,
			"reason": "" if lvl >= int(a[0]) else "需 L%d（当前 L%d）" % [int(a[0]), lvl]})
	return out

func _poll_right_click() -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var edge := down and not _rclick_prev
	_rclick_prev = down
	if not edge:
		return
	if state == null or state.boot_t < 1.7 or state.capture:
		return
	if pause_open or _any_overlay() or _modal != "" or _ov_prelude() or _ov_adjutant() \
			or _ov_decision() or _ov_report() or _ov_consequence() or _ov_end():
		return
	# ENG main 已实现右键→plot.pick_track→HUD.open_target_menu；此处只做无该接口时的兜底。
	if state.has_method("open_target_menu") and not state.has_method("target_menu_open"):
		return
	var p := _mouse_in_base()
	if not (Rect2(396, 124, 1128, 752).has_point(p) or TRACKS.has_point(p)):
		return
	for i in row_rects.size():
		if row_rects[i].has_point(p):
			state.selected = i
			break
	_open_ctx_menu(p)

# ENG 主流程接口：main 右键 → HUD.open_target_menu(track_id, actions)
func open_target_menu(track_id: String, actions: Array) -> void:
	_ctx_open = true
	_ctx_track_id = track_id
	_ctx_actions = actions.duplicate(true)
	_ctx_pos = _mouse_in_base()
	_ctx_hint = ""
	menu_open = false
	if state != null:
		for i in state.tracks.size():
			if String((state.tracks[i] as Dictionary).get("id", "")) == track_id:
				state.selected = i
				break
	_sfx("ui_open")

func _open_ctx_menu(pos: Vector2) -> void:
	_ctx_pos = pos
	var id := _target_track_id()
	var acts := _target_actions_for(id)
	if state != null and state.has_method("open_target_menu"):
		state.call("open_target_menu", id)
	open_target_menu(id, acts)

func _ctx_rows() -> Array:
	if _ctx_track_id == "":
		_ctx_track_id = _target_track_id()
	var rows: Array = []
	var actions: Array = _ctx_actions
	if actions.is_empty():
		actions = _target_actions_for(String(_ctx_track_id))
	var by_tier := {}
	for raw in actions:
		if not (raw is Dictionary):
			continue
		var al: Dictionary = raw
		var tier := int(al.get("min_level", 1))
		if not by_tier.has(tier):
			by_tier[tier] = []
		(by_tier[tier] as Array).append(al)
	for tier_def in TGT_TIERS:
		var tier := int(tier_def[0])
		if not by_tier.has(tier):
			continue
		rows.append({"group": true, "label": String(tier_def[1]), "tier": tier})
		for raw2 in by_tier[tier]:
			var al: Dictionary = raw2
			rows.append({"action": String(al.get("id", "")),
				"label": String(al.get("label", al.get("id", ""))), "tier": tier,
				"locked": not bool(al.get("available", true)),
				"unsupported": bool(al.get("unsupported", false)),
				"reason": String(al.get("reason", ""))})
	return rows

func _ctx_rect() -> Rect2:
	var rows := _ctx_rows()
	var h := CTX_HEAD_H + CTX_FOOT_H
	for r in rows:
		h += CTX_GROUP_H if bool(r.get("group", false)) else CTX_ROW_H
	var x := clampf(_ctx_pos.x + 10.0, 44.0, 1920.0 - CTX_W - 44.0)
	var y := clampf(_ctx_pos.y + 10.0, 124.0, 1040.0 - h - 8.0)
	return Rect2(x, y, CTX_W, h)

func _close_ctx() -> void:
	_ctx_open = false
	_ctx_actions.clear()
	if state != null and state.has_method("close_target_menu"):
		state.call("close_target_menu")

func _handle_ctx_click(p: Vector2) -> void:
	var rc := _ctx_rect()
	if not rc.has_point(p):
		_close_ctx()
		return
	var y := rc.position.y + CTX_HEAD_H
	for r in _ctx_rows():
		var row_h := CTX_GROUP_H if bool(r.get("group", false)) else CTX_ROW_H
		var rr := Rect2(rc.position.x, y, rc.size.x, row_h)
		if rr.has_point(p) and not bool(r.get("group", false)):
			var act := String(r.get("action", ""))
			if bool(r.get("locked", false)) or bool(r.get("unsupported", false)):
				var why := String(r.get("reason", ""))
				_ctx_hint = why if why != "" else "该动作当前不可用"
				return
			_ctx_open = false
			_ctx_actions.clear()
			_perform_target_action(String(_ctx_track_id), act)
			return
		y += row_h

func _perform_target_action(track_id: String, act: String) -> void:
	if state != null and state.has_method("perform_target_action"):
		var res = state.call("perform_target_action", track_id, act)
		_sfx("ui_confirm")
		if res is Dictionary:
			var d: Dictionary = res
			var ok := bool(d.get("ok", false))
			var msg := String(d.get("message", d.get("status", "")))
			if ok:
				_toast("目标动作：%s" % (msg if msg != "" else act))
				if act == "optical_channel" or act == "ir_channel":
					_open_optical("VIS" if act == "optical_channel" else "IR", track_id, false)
			else:
				_toast(msg if msg != "" else "动作不可用：%s" % act)
		return
	_toast("接口未就绪：state.perform_target_action(track_id, action) · 演示动作 %s" % act)

func _draw_ctx_menu() -> void:
	var rc := _ctx_rect()
	draw_rect(rc, Color(0.015, 0.04, 0.032, 0.97))
	draw_rect(rc, Palette.a(Palette.PH, 0.75), false, 1.0)
	var tr := _target_track()
	if state != null and state.has_method("track_by_id"):
		var t3 = state.call("track_by_id", String(_ctx_track_id))
		if t3 is Dictionary and not (t3 as Dictionary).is_empty():
			tr = t3
	_txt(cjk, rc.position.x + 12.0, rc.position.y + 20.0,
		"[%s] %s · L%d · %s" % [String(tr.get("batch", "----")), _dn(_track_display_id(tr)) if not tr.is_empty() else "—",
			clampi(int(tr.get("level", 0)), 0, 4), _identity_cn(_track_identity(tr)) if not tr.is_empty() else "—"],
		9, Palette.TXT)
	_txt(cjk, rc.position.x + 12.0, rc.position.y + 42.0, "右键目标 · 分级操作 / TARGET ACTIONS", 7, Palette.a(Palette.PH, 0.8))
	draw_line(Vector2(rc.position.x, rc.position.y + CTX_HEAD_H),
		Vector2(rc.end.x, rc.position.y + CTX_HEAD_H), Palette.a(Palette.LINE, 0.8), 1.0)
	var y := rc.position.y + CTX_HEAD_H
	for r in _ctx_rows():
		if bool(r.get("group", false)):
			_txt(mono, rc.position.x + 12.0, y + 13.0, String(r.get("label", "")), 7,
				Palette.a(Palette.AMBER, 0.72))
			draw_line(Vector2(rc.position.x + 8.0, y + CTX_GROUP_H - 2.0),
				Vector2(rc.end.x - 8.0, y + CTX_GROUP_H - 2.0), Palette.a(Palette.LINE, 0.35), 1.0)
		else:
			var hot := Rect2(rc.position.x, y, rc.size.x, CTX_ROW_H).has_point(_mouse_base())
			var locked := bool(r.get("locked", false))
			var col: Color = Palette.FAINT if locked else (Palette.PH if hot else Palette.TXT)
			if hot and not locked:
				draw_rect(Rect2(rc.position.x + 1.0, y, rc.size.x - 2.0, CTX_ROW_H), Palette.a(Palette.PH, 0.08))
			_txt(mono, rc.position.x + 26.0, y + 15.0, "▸" if not locked else "·", 8, Palette.a(col, 0.8))
			_txt(cjk, rc.position.x + 44.0, y + 15.0, String(r.get("label", "")), 8, col)
			if locked:
				_txt_r(mono, rc.end.x - 12.0, y + 15.0, "L%d" % int(r.get("tier", 1)), 7, Palette.a(Palette.FAINT, 0.8))
		y += CTX_GROUP_H if bool(r.get("group", false)) else CTX_ROW_H
	var fy := rc.end.y - CTX_FOOT_H
	draw_line(Vector2(rc.position.x, fy), Vector2(rc.end.x, fy), Palette.a(Palette.LINE, 0.7), 1.0)
	if _ctx_hint != "":
		_txt(cjk, rc.position.x + 12.0, fy + 16.0, _ellipsis(cjk, _ctx_hint, 7, rc.size.x - 24.0), 7, Palette.AMBER)
	else:
		_txt_r(mono, rc.end.x - 12.0, fy + 16.0, "ESC / 右击关闭", 7, Palette.a(Palette.FAINT, 0.8))

# ── 光学 / 红外通道 ───────────────────────────────────
func _channel_progress() -> float:
	if state != null and state.has_method("channel_status"):
		var cs = state.call("channel_status", String(_optical_target))
		if cs is Dictionary:
			var ch = (cs as Dictionary).get("channels", {})
			if ch is Dictionary:
				var key := "optical" if _optical_kind == "VIS" else "ir"
				var oc = (ch as Dictionary).get(key)
				if oc is Dictionary:
					return clampf(float((oc as Dictionary).get("progress", 0.0)), 0.0, 1.0)
	return clampf(_optical_stare, 0.0, 1.0)

func _optical_status_text() -> String:
	if state != null and state.has_method("channel_status"):
		var cs = state.call("channel_status", String(_optical_target))
		if cs is Dictionary:
			var ch = (cs as Dictionary).get("channels", {})
			if ch is Dictionary:
				var key := "optical" if _optical_kind == "VIS" else "ir"
				var oc = (ch as Dictionary).get(key)
				if oc is Dictionary:
					var st := String((oc as Dictionary).get("status", ""))
					return {"running": "跟踪中 / RUNNING", "locked": "已锁定 / LOCKED"}.get(st, st)
	return "UI 演示 / DEMO"

func _open_optical(kind: String, target_id: String, start_it := true) -> void:
	_optical_open = true
	_optical_kind = kind
	_optical_target = target_id
	_optical_stare = 0.0
	_optical_state_note = ""
	if start_it and state != null:
		var meth := "start_optical_track" if kind == "VIS" else "start_ir_track"
		if state.has_method(meth):
			var res = state.call(meth, target_id)
			if res is Dictionary:
				_optical_state_note = String((res as Dictionary).get("message", ""))
		elif state.has_method("start_optical" if kind == "VIS" else "start_ir"):
			state.call("start_optical" if kind == "VIS" else "start_ir", target_id)
		else:
			_optical_state_note = "接口未就绪：需 state.%s(track_id)；当前为 UI 演示" % meth
	_sfx("sys_sensor_on")

func _handle_optical_click(p: Vector2) -> void:
	if OPT_CLOSE_BTN.has_point(p):
		_optical_open = false
		_sfx("ui_back")
		return
	if OPT_TAB_VIS.has_point(p):
		_optical_kind = "VIS"
		return
	if OPT_TAB_IR.has_point(p):
		_optical_kind = "IR"
		return
	if OPT_STARE_BTN.has_point(p):
		_optical_stare = 0.0
		if state != null:
			var meth := "start_optical_track" if _optical_kind == "VIS" else "start_ir_track"
			if state.has_method(meth):
				state.call(meth, String(_optical_target))
			else:
				for m2 in ["stare_optical", "start_optical_stare", "stare_target"]:
					if state.has_method(m2):
						state.call(m2, String(_optical_target))
						break
		return
	if OPT_STOP_BTN.has_point(p):
		if state != null:
			if state.has_method("stop_track"):
				state.call("stop_track")
			else:
				for meth in ["stop_optical", "stop_ir", "stop_stare"]:
					if state.has_method(meth):
						state.call(meth)
						break
		_optical_stare = 0.0
		return

func _draw_optical_overlay() -> void:
	if _optical_target == "":
		_optical_target = _target_track_id()
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color(0.01, 0.03, 0.024, 0.62))
	var r := OPTICAL_RECT
	draw_rect(r, Palette.a(Palette.PANEL, 0.99))
	draw_rect(r, Palette.a(Palette.PH, 0.65), false, 1.0)
	_txt(cjk, r.position.x + 24.0, r.position.y + 32.0, "光学/红外通道 / OPTICAL CHANNEL", 16, Palette.PH)
	var ot := _target_track()
	if String(_optical_target) != "" and not ot.is_empty() and String(ot.get("id", "")) != String(_optical_target):
		if state != null:
			var t2 = state.call("track_by_id", String(_optical_target)) if state.has_method("track_by_id") else null
			if t2 is Dictionary and not (t2 as Dictionary).is_empty():
				ot = t2
	var olabel := "[%s] %s · %s" % [String(ot.get("batch", "----")), _dn(_track_display_id(ot)) if not ot.is_empty() else "—",
		_identity_cn(_track_identity(ot)) if not ot.is_empty() else "—"]
	_txt_r(mono, r.end.x - 24.0, r.position.y + 32.0,
		"%s · %s" % [_optical_kind, olabel], 8, Palette.a(Palette.FAINT, 0.95))
	draw_line(Vector2(r.position.x, r.position.y + 48.0), Vector2(r.end.x, r.position.y + 48.0),
		Palette.a(Palette.PH, 0.28), 1.0)
	for i in range(2):
		var trc: Rect2 = OPT_TAB_VIS if i == 0 else OPT_TAB_IR
		var sel := (_optical_kind == "VIS") == (i == 0)
		draw_rect(trc, Palette.a(Palette.PANEL2, 0.95 if sel else 0.4))
		draw_rect(trc, Palette.a(Palette.PH, 0.75 if sel else 0.22), false, 1.0)
		_txt(cjk, trc.position.x + 12.0, trc.position.y + 16.0,
			"可见光 / VIS" if i == 0 else "红外 / IR", 9, Palette.PH if sel else Palette.DIM)
	# 传感器窗（程序化星点/十字线，无外部贴图）
	var win := Rect2(588, 316, 744, 300)
	draw_rect(win, Color(0.005, 0.012, 0.01, 1.0))
	draw_rect(win, Palette.a(Palette.LINE, 0.9), false, 1.0)
	for i in range(90):
		var h := (i * 1103515245 + 12345) & 0x7fffffff
		var px := win.position.x + float(h % 700) + 14.0
		var py := win.position.y + float((h / 700) % 280) + 10.0
		draw_rect(Rect2(px, py, 1, 1), Palette.a(Palette.TXT, 0.06 + 0.05 * float(i % 3)))
	var c := win.get_center()
	draw_circle(c, 2.2 if _optical_kind == "VIS" else 2.8, Palette.BLUE if _optical_kind == "VIS" else Palette.AMBER)
	draw_line(c - Vector2(24, 0), c + Vector2(24, 0), Palette.a(Palette.PH, 0.55), 1.0)
	draw_line(c - Vector2(0, 24), c + Vector2(0, 24), Palette.a(Palette.PH, 0.55), 1.0)
	draw_arc(c, 42.0, 0, TAU, 48, Palette.a(Palette.PH_FAINT, 0.5), 1.0, true)
	_txt(mono, win.position.x + 10.0, win.position.y + 16.0,
		"%s · %s" % ["VIS" if _optical_kind == "VIS" else "IR", _optical_status_text()], 7,
		Palette.a(Palette.PH, 0.8))
	# 数据与进度
	var info := {}
	if state != null and state.has_method("selected_info"):
		var si = state.call("selected_info")
		if si is Dictionary:
			info = si
	_txt(mono, 588, 646, "TARGET %s" % String(_optical_target), 8, Palette.TXT)
	_txt(mono, 588, 664, "RANGE %s · REFRESH %.1fs" % [
		"%.0f km" % float(info.get("range_km", 0.0)) if not info.is_empty() else "—",
		float(_target_track().get("refresh_s", 8.0))], 7, Palette.DIM)
	_txt(mono, 588, 682, "STARE", 7, Palette.FAINT)
	var ch_prog := _channel_progress()
	draw_rect(Rect2(644, 676, 360, 6), Palette.a(Palette.LINE, 0.9))
	draw_rect(Rect2(644, 676, 360.0 * ch_prog, 6),
		Palette.a(Palette.PH if _optical_kind == "VIS" else Palette.AMBER, 0.9))
	_txt_r(mono, 1128, 682, "%d%%" % int(round(ch_prog * 100.0)), 8, Palette.TXT)
	_cmd_btn(OPT_STARE_BTN, "开始凝视 / STARE", false, Palette.PH)
	_cmd_btn(OPT_STOP_BTN, "停止 / STOP", false, Palette.AMBER)
	_cmd_btn(OPT_CLOSE_BTN, "关闭 / CLOSE", false, Palette.RED)
	var note := _optical_state_note
	if note == "":
		note = "接口：start_optical_track/start_ir_track(track_id) · stop_track() · channel_status()"
	_txt(cjk, r.position.x + 24.0, r.end.y - 38.0, _ellipsis(cjk, note, 7, 420.0), 7, Palette.a(Palette.AMBER, 0.7))
	_txt_r(cjk, r.end.x - 24.0, r.end.y - 38.0, "ESC / CLOSE 返回", 7, Palette.a(Palette.FAINT, 0.9))

# ── 图层 / 元素开关 ───────────────────────────────────
func _toggle_layer(key: String, on: bool) -> void:
	_layer_state[key] = on
	if state != null and state.has_method("set_layer_visible"):
		state.call("set_layer_visible", key, on)
		_toast("图层 %s · %s" % [key, "显示" if on else "隐藏"])
	else:
		_toast("图层开关接口未就绪：需 state.set_layer_visible(name,on) + plot 读取；当前仅 HUD 本地保存")
	_sfx("ui_click")

func _handle_layers_click(p: Vector2) -> void:
	var r := LAYERS_RECT
	if Rect2(r.end.x - 120.0, r.end.y - 48.0, 96.0, 28.0).has_point(p):
		_layers_open = false
		return
	for i in range(LAYER_KEYS.size()):
		var rr := Rect2(r.position.x + 24.0, r.position.y + 92.0 + float(i) * 38.0, r.size.x - 48.0, 32.0)
		if rr.has_point(p):
			var k := String(LAYER_KEYS[i])
			_toggle_layer(k, not bool(_layer_state.get(k, true)))
			return
	if not r.has_point(p):
		_layers_open = false

func _draw_layers_panel() -> void:
	var r := LAYERS_RECT
	draw_rect(r, Palette.a(Palette.PANEL, 0.99))
	draw_rect(r, Palette.a(Palette.PH, 0.6), false, 1.0)
	_txt(cjk, r.position.x + 24.0, r.position.y + 32.0, "图层 / 元素开关 / LAYERS", 15, Palette.PH)
	_txt_r(mono, r.end.x - 24.0, r.position.y + 32.0, "STATE · PLOT · 已接", 7, Palette.a(Palette.PH_FAINT, 0.85))
	draw_line(Vector2(r.position.x, r.position.y + 48.0), Vector2(r.end.x, r.position.y + 48.0),
		Palette.a(Palette.PH, 0.28), 1.0)
	for i in range(LAYER_KEYS.size()):
		var k := String(LAYER_KEYS[i])
		var rr := Rect2(r.position.x + 24.0, r.position.y + 92.0 + float(i) * 38.0, r.size.x - 48.0, 32.0)
		var on := bool(_layer_state.get(k, true))
		var hot := rr.has_point(_mouse_base())
		draw_rect(rr, Palette.a(Palette.PANEL2, 0.85 if hot else 0.35))
		draw_rect(rr, Palette.a(Palette.PH, 0.35 if on else 0.18), false, 1.0)
		_txt(mono, rr.position.x + 12.0, rr.position.y + 21.0, "[x]" if on else "[ ]", 12,
			Palette.PH if on else Palette.FAINT)
		_txt(cjk, rr.position.x + 52.0, rr.position.y + 21.0, String(LAYER_NAMES[i]), 9,
			Palette.TXT if on else Palette.FAINT)
		_txt_r(mono, rr.end.x - 12.0, rr.position.y + 21.0, "ON" if on else "OFF", 8,
			Palette.PH if on else Palette.FAINT)
	_cmd_btn(Rect2(r.end.x - 120.0, r.end.y - 48.0, 96.0, 28.0), "关闭 / CLOSE", false, Palette.PH)
	_txt(cjk, r.position.x + 24.0, r.end.y - 24.0,
		"可隐藏接触/标签/预测/雷达/站点/网格；plot 按 state 图层键跳过绘制（已接 set_layer_visible）", 7,
		Palette.a(Palette.PH_FAINT, 0.9))

# ── Esc 层级：先关战术弹窗，再交给暂停菜单 ────────────
func _close_top_popup() -> bool:
	if _ctx_open:
		_close_ctx()
		return true
	if _optical_open:
		_optical_open = false
		_sfx("ui_back")
		return true
	if _layers_open:
		_layers_open = false
		return true
	if _queue_detail_id != "":
		_queue_detail_id = ""
		return true
	return false

func _draw_time() -> void:
	_panel(TIME)
	_txt(cjk, 1216, 892, "态势回放 / REPLAY", 8, Palette.TXT)
	_txt_r(cjk, 1844, 892, "60 秒缓冲 / BUFFER", 7, Palette.FAINT)

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
	var tag := "暴露风险" if bool(s.get("expose", false)) else "被动"
	var tag_col: Color = Palette.AMBER if bool(s.get("expose", false)) else Palette.FAINT
	_txt_r(cjk, SENSOR_RECT.end.x - 32.0, y0 + 9.0, "%s · %s" % [_dn(String(s.get("mode", ""))), tag], 7, tag_col)
	var chev := "▴" if menu_open else "▾"
	_txt(mono, SENSOR_RECT.end.x - 16.0, y0 + 8.0, chev, 10, Palette.a(Palette.PH, 0.9 if menu_open else 0.7))

func _draw_sensor_menu() -> void:
	# P1d：展开态 = 选中舰的按舰传感器架。
	# P3b：行右侧 ON/OFF chip 可操作（state.set_sensor）；行点击仍只切换当前模块。
	# 行：model / source·maker·type·range·refresh / 暴露 + ON/OFF；
	# footer：暴露（EMCON / EMIT）、接触等级证据、开机即暴露提示。
	menu_rects.clear()
	_rack_chip_rects.clear()
	var r := _menu_rect()
	var x0 := r.position.x
	var y0 := r.position.y
	var rack := _rack_rows()
	var em := _rack_emission()
	var tr := _rack_track()
	var lv := clampi(int(tr.get("level", 0)), 0, 4)
	var ship := _rack_ship()
	var can_toggle := _sensor_toggle_available()

	# 面板本体（开场时压在 BG 贴片下面）
	draw_rect(r, Palette.a(Palette.PANEL, 1.0))
	draw_rect(r, Palette.a(Palette.LINE, 0.95), false, 1.0)
	var head := "传感器架 / SENSOR RACK"
	_txt(cjk, x0 + 12.0, y0 + 8.0, head, 9, Palette.TXT)
	var hw := cjk.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_txt(cjk, x0 + 12.0 + hw + 8.0, y0 + 9.0,
		"ON/OFF 可操作" if can_toggle else "ON/OFF 只读（不可用）", 7,
		Palette.a(Palette.PH if can_toggle else Palette.FAINT, 0.95))
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
		# 暴露 / 主动辐射：开启的主动雷达/IFF 直接标「开机即暴露」。
		var expose := bool(s.get("expose", false))
		var on := _rack_on(ship, model, bool(s.get("on", true)))
		var named := bool(state.get("elint_named"))
		var tag := "被动"
		var tag_col: Color = Palette.FAINT
		if expose:
			if on:
				tag = "开机即暴露"
				tag_col = Palette.RED if named else Palette.AMBER
			else:
				tag = "暴露风险 · 已关"
				tag_col = Palette.a(Palette.AMBER, 0.65)
		_txt_r(cjk, row.end.x - 52.0, row.position.y + 9.0, tag, 7, tag_col)
		# P3b：ON/OFF chip 可操作（点 chip 只切开关，不选模块、不关菜单）
		var chip := Rect2(row.end.x - 44.0, row.position.y + 6.0, 32, 16)
		var chip_hot := can_toggle and chip.has_point(_mouse_base())
		var chip_col: Color = Palette.PH if on else Palette.FAINT
		if can_toggle:
			_rack_chip_rects.append({"rect": chip, "idx": i, "model": model, "enabled": true})
		else:
			_rack_chip_rects.append({"rect": chip, "idx": i, "model": model, "enabled": false})
		draw_rect(chip, Palette.a(chip_col, 0.14 if chip_hot else 0.05))
		draw_rect(chip, Palette.a(chip_col, 0.85 if chip_hot else (0.30 if can_toggle else 0.16)), false, 1.0)
		var on_s := "ON" if on else "OFF"
		var on_w := mono.get_string_size(on_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		_txt(mono, chip.position.x + (chip.size.x - on_w) * 0.5, chip.position.y + 3.0, on_s, 7,
			Palette.a(chip_col, 1.0 if can_toggle else 0.55))
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
	_txt_r(cjk, r.end.x - 12.0, foot_y + 9.0, "开机即暴露", 7,
		Palette.a(Palette.AMBER, 0.65))
	var warn := ""
	var warns: Array = em.get("warnings", [])
	if not warns.is_empty():
		warn = String(warns[0]).replace("（05 §S-02）", "").replace("（05 §S-04）", "")
	elif exposed:
		warn = "主动模块开机暴露风险：ELINT 可截获（05 §S-02）"
	else:
		warn = "被动模块"
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
		"LINK APSIS .......... LASER DIRECT 0.4s",
		"SENSOR ARRAY ............... 06",
		"ORDER 7 NOTICE ....... RX",
		"SUPERVISOR AUTHORITY ....... GRANTED"
	]
	for i in range(lines.size()):
		if t * 8.0 > float(i):
			_txt(mono, 120.0, 300.0 + float(i) * 30.0, lines[i], 11, Palette.a(Palette.PH, 0.85))

	# 右侧总线读数
	var st := ["LINK DIRECT 0.4s", "ARRAY 06", "ORDER 7", "APSIS 192,000 km", "ROE 仅自卫"]
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

