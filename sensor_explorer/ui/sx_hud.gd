extends Control

## SENSOR EXPLORER · V1 HUD（SENSOR-EXPLORER-1）
##
## 纯绘制层：只读 explorer 每帧填充的 `vm`；不持有仿真/相机/时间逻辑。
## V1 视觉：薄荷绿线框、1px 边框、四角刻度、7–11pt 等宽+中文字体、Palette。
## 诚实标注：页脚固定 `V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17`。

const Pal := preload("res://scripts/pal.gd")
const UiFonts := preload("res://scripts/fonts.gd")

const TARGET_RECT := Rect2(40.0, 88.0, 430.0, 250.0)
const SELECT_RECT := Rect2(1450.0, 104.0, 430.0, 360.0)
const OPTICAL_RECT := Rect2(40.0, 350.0, 430.0, 350.0)
const INFO_RECT := Rect2(1450.0, 480.0, 430.0, 230.0)
const EW_RECT := Rect2(1450.0, 720.0, 430.0, 78.0)
const TWS_RECT := Rect2(40.0, 810.0, 540.0, 214.0)
const EVENT_RECT := Rect2(600.0, 810.0, 660.0, 214.0)
const SENSOR_RECT := Rect2(1280.0, 810.0, 600.0, 214.0)
const TIME_RECT := Rect2(1450.0, 30.0, 430.0, 56.0)
const ROW_H := 23.0
const TARGET_TOP := 158.0
const FOOT_Y := 1052.0

const STATE_ORDER := ["SEARCH", "DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const STATE_SHORT := {"SEARCH": "SRCH", "DETECT": "DET", "ACQUIRE": "ACQ",
	"TRACK": "TRK", "STARE": "STARE", "FIRE_CONTROL": "FC"}

var vm: Dictionary = {}
var mono: Font
var cjk: Font
var _stars: Array[Vector2] = []
var _star_a: Array[float] = []


func _ready() -> void:
	mono = UiFonts.mono()
	cjk = UiFonts.cjk()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6058
	for i in range(150):
		_stars.append(Vector2(rng.randf_range(0.0, 1920.0), rng.randf_range(0.0, 1080.0)))
		_star_a.append(rng.randf_range(0.09, 0.30))


func set_vm(view_model: Dictionary) -> void:
	vm = view_model


# ── 点击命中：目标列表 ────────────────────────────────────────────

func row_at(p: Vector2) -> String:
	if p.x < TARGET_RECT.position.x or p.x > TARGET_RECT.end.x:
		return ""
	var targets: Array = vm.get("targets", [])
	for i in range(targets.size()):
		var top := TARGET_TOP + ROW_H * float(i)
		var r := Rect2(TARGET_RECT.position.x + 8.0, top - 15.0,
			TARGET_RECT.size.x - 16.0, ROW_H)
		if r.has_point(p):
			return String((targets[i] as Dictionary).get("id", ""))
	return ""


# ── 绘制 ─────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_stars()
	_draw_title()
	_draw_time()
	_draw_targets()
	_draw_selected()
	_draw_optical()
	_draw_info()
	_draw_ew()
	_draw_tws()
	_draw_events()
	_draw_sensors()
	_draw_labels()
	_draw_footer()


func _draw_stars() -> void:
	for i in range(_stars.size()):
		var p: Vector2 = _stars[i]
		draw_circle(p, 1.0 if i % 9 == 0 else 0.6, Pal.a(Pal.PH_FAINT, float(_star_a[i])))


func _panel(r: Rect2, en: String, cn: String) -> void:
	draw_rect(r, Pal.a(Pal.BG, 0.66))
	draw_rect(r, Pal.a(Pal.LINE, 0.9), false, 1.0)
	var k := 9.0
	draw_line(r.position, r.position + Vector2(k, 0), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.position, r.position + Vector2(0, k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - k, r.position.y), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + k, r.end.y), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - k), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.end, r.end - Vector2(k, 0), Pal.a(Pal.PH, 0.55), 1.0)
	draw_line(r.end, r.end - Vector2(0, k), Pal.a(Pal.PH, 0.55), 1.0)
	_txt(mono, r.position.x + 10.0, r.position.y + 16.0, en, 8, Pal.a(Pal.PH, 0.92))
	_txt(cjk, r.position.x + 12.0 + 7.2 * float(en.length()), r.position.y + 16.0,
		" / " + cn, 8, Pal.a(Pal.DIM, 0.85))
	draw_line(Vector2(r.position.x + 10.0, r.position.y + 22.0),
		Vector2(r.end.x - 10.0, r.position.y + 22.0), Pal.a(Pal.LINE, 0.7), 1.0)


func _draw_title() -> void:
	_txt(mono, 40.0, 28.0, "SENSOR EXPLORER", 11, Pal.PH)
	_txt(cjk, 236.0, 28.0, "雷达 / 光电 / IFF / ELINT 独立技术演示", 8, Pal.a(Pal.DIM, 0.9))
	_txt(mono, 40.0, 44.0, "V2 SENSOR STACK · SPHERICAL SEARCH / TWS / OPTICAL-IR / IFF / ELINT · SER. 060",
		7, Pal.a(Pal.PH_FAINT, 0.95))


func _draw_time() -> void:
	_panel(TIME_RECT, "TIME", "时间")
	var t := float(vm.get("t", 0.0))
	_txt(mono, TIME_RECT.position.x + 12.0, TIME_RECT.position.y + 42.0, "T+ " + _fmt_hms(t), 9,
		Pal.a(Pal.PH, 0.95))
	_txt(mono, TIME_RECT.position.x + 190.0, TIME_RECT.position.y + 42.0,
		"×%s" % _fmt_speed(float(vm.get("speed", 1.0))), 8, Pal.a(Pal.BLUE, 0.9))
	var paused := bool(vm.get("paused", false))
	_txt(mono, TIME_RECT.position.x + 278.0, TIME_RECT.position.y + 42.0,
		"PAUSED" if paused else "RUNNING", 7,
		Pal.a(Pal.AMBER if paused else Pal.PH, 0.95))


func _draw_targets() -> void:
	_panel(TARGET_RECT, "TARGETS", "目标")
	var targets: Array = vm.get("targets", [])
	for i in range(targets.size()):
		var tr: Dictionary = targets[i]
		var y := TARGET_TOP + ROW_H * float(i)
		var sel := bool(tr.get("selected", false))
		var col: Color = tr.get("color", Pal.PH)
		if sel:
			draw_rect(Rect2(TARGET_RECT.position.x + 6.0, y - 15.0,
				TARGET_RECT.size.x - 12.0, ROW_H - 1.0), Pal.a(Pal.PH, 0.07))
			draw_rect(Rect2(TARGET_RECT.position.x + 6.0, y - 15.0, 2.0, ROW_H - 1.0),
				Pal.a(col, 0.9))
		_txt(mono, TARGET_RECT.position.x + 12.0, y, "[%s]" % String(tr.get("id", "")), 7,
			Pal.a(Pal.PH_FAINT, 0.95))
		var name := String(tr.get("name", ""))
		var f: Font = cjk if UiFonts.has_cjk(name) else mono
		_txt(f, TARGET_RECT.position.x + 66.0, y, name, 7, Pal.a(col, 0.96 if sel else 0.78))
		_txt_r(mono, TARGET_RECT.position.x + 270.0, y,
			"%.0f km" % float(tr.get("range_km", 0.0)), 7, Pal.a(Pal.TXT, 0.8))
		_txt(mono, TARGET_RECT.position.x + 300.0, y, _state_short(String(tr.get("state", ""))),
			7, Pal.a(_state_col(String(tr.get("state", ""))), 0.95))
		_txt_r(mono, TARGET_RECT.end.x - 10.0, y,
			"V%d I%d q%.0f" % [int(tr.get("vis_level", 0)), int(tr.get("ir_level", 0)),
			float(tr.get("quality", 0.0)) * 100.0], 7, Pal.a(Pal.FAINT, 0.95))
	# 提示
	_txt(mono, TARGET_RECT.position.x + 12.0, TARGET_RECT.end.y - 10.0,
		"TAB/1-6 选择 · Q IFF 询问 · M 雷达 · V/I 光学/IR · E ELINT",
		7, Pal.a(Pal.FAINT, 0.9))


func _draw_selected() -> void:
	_panel(SELECT_RECT, "SELECTED", "选中目标")
	var s: Dictionary = vm.get("selected", {})
	if s.is_empty():
		_txt(mono, SELECT_RECT.position.x + 12.0, SELECT_RECT.position.y + 50.0,
			"NO TARGET SELECTED", 8, Pal.a(Pal.FAINT, 0.9))
		return
	var col: Color = s.get("color", Pal.PH)
	var name := String(s.get("name", ""))
	var f: Font = cjk if UiFonts.has_cjk(name) else mono
	_txt(mono, SELECT_RECT.position.x + 12.0, SELECT_RECT.position.y + 42.0,
		String(s.get("id", "")), 8, Pal.a(Pal.FAINT, 0.9))
	_txt(f, SELECT_RECT.position.x + 12.0, SELECT_RECT.position.y + 60.0, name, 11, Pal.a(col, 0.98))
	var y := SELECT_RECT.position.y + 84.0
	var rows := [
		["RANGE", String(s.get("range_text", "—"))],
		["GEOM", String(s.get("bearing_text", "—"))],
		["RCS / REFF", String(s.get("rcs_text", "—"))],
		["ILLUM", String(s.get("illum_text", "—"))],
		["TWS", String(s.get("tws_text", "—"))],
		["TRACK", String(s.get("quality_text", "—"))],
		["VIS / IR", String(s.get("optical_text", "—"))],
		["IFF", String(s.get("iff_text", "—"))],
		["EMITTER", String(s.get("emitter_text", "—"))],
	]
	for row in rows:
		var it: Array = row
		_txt(mono, SELECT_RECT.position.x + 12.0, y, String(it[0]), 7, Pal.a(Pal.FAINT, 0.9))
		_txt(mono, SELECT_RECT.position.x + 112.0, y, String(it[1]), 7, Pal.a(Pal.TXT, 0.86))
		y += 16.0
	var note := String(s.get("note", ""))
	if note != "":
		var fn: Font = cjk if UiFonts.has_cjk(note) else mono
		_txt(fn, SELECT_RECT.position.x + 12.0, y + 4.0, note, 7, Pal.a(Pal.DIM, 0.85))


func _draw_optical() -> void:
	_panel(OPTICAL_RECT, "OPTICAL / IR CHANNELS", "完整相机 · FOV/遮挡/SNR")
	var opt: Dictionary = vm.get("optical", {})
	var vis: Dictionary = opt.get("vis", {}) if opt.get("vis", {}) is Dictionary else {}
	var ir: Dictionary = opt.get("ir", {}) if opt.get("ir", {}) is Dictionary else {}
	var x := OPTICAL_RECT.position.x + 12.0
	var y := OPTICAL_RECT.position.y + 42.0
	_txt(mono, x, y, "BACKEND optical_ir · VIS MS-OT2 · IR CH-IR2", 7, Pal.a(Pal.PH_FAINT, 0.95))
	y += 17.0
	var rows := [["VIS T1", vis], ["IR T6", ir]]
	for raw in rows:
		var it: Array = raw
		var label := String(it[0])
		var ch: Dictionary = it[1]
		var col: Color = Pal.PH if String(ch.get("status", "")) == "locked" else Pal.DIM
		_txt(mono, x, y, label, 8, Pal.a(col, 0.95))
		_txt(mono, x + 70.0, y, "%s %d%%" % [String(ch.get("status", "off")),
			int(float(ch.get("progress", 0.0)) * 100.0)], 8, Pal.a(col, 0.9))
		_txt(mono, x + 220.0, y, "L%d" % int(ch.get("level_support", 0)), 8,
			Pal.a(Pal.AMBER if int(ch.get("level_support", 0)) >= 3 else Pal.TXT, 0.9))
		y += 15.0
		if not ch.is_empty():
			var fov := float(ch.get("fov_deg", 0.0))
			var ifov := float(ch.get("ifov_eff_urad", ch.get("ifov_urad", 0.0)))
			var snr := float(ch.get("snr_db", -999.0))
			var occ := bool(ch.get("occluded", false))
			var bores := float(ch.get("boresight_deg", -1.0))
			var offax := float(ch.get("off_axis_deg", -1.0))
			var npx := float(ch.get("n_px", 0.0))
			var reason := String(ch.get("reason", ""))
			_txt(mono, x + 10.0, y, "FOV %.3f° · IFOV %.2fµrad · Npx %.1f" % [fov, ifov, npx],
				7, Pal.a(Pal.TXT, 0.86))
			y += 13.0
			_txt(mono, x + 10.0, y, "SNR %.1f dB · illum %.2f · SNR_OK %s" % [
				snr, float(ch.get("illum", 0.0)), "Y" if snr >= float(ch.get("min_snr_db", 8.0)) else "N"],
				7, Pal.a(Pal.TXT, 0.86))
			y += 13.0
			_txt(mono, x + 10.0, y, "BORESIGHT %.1f° · OFF-AXIS %.3f° · OCCLUDED %s" % [
				bores, offax, "Y" if occ else "N"], 7,
				Pal.a(Pal.AMBER if (occ or offax > fov * 0.5) else Pal.TXT, 0.86))
			y += 13.0
			if reason != "":
				_txt(mono, x + 10.0, y, "REASON %s" % reason, 7, Pal.a(Pal.AMBER, 0.9))
				y += 13.0
		else:
			_txt(mono, x + 10.0, y, "channel off", 7, Pal.a(Pal.FAINT, 0.9))
			y += 13.0
		y += 5.0
	_txt(mono, x, OPTICAL_RECT.end.y - 18.0,
		"VIS L3=classification · IR L1 only · NO RANGE MEASUREMENT", 7, Pal.a(Pal.FAINT, 0.9))


func _draw_info() -> void:
	_panel(INFO_RECT, "IFF / ELINT / COMINT", "V2InformationWarfare · 只读")
	var info: Dictionary = vm.get("info", {})
	var iff: Dictionary = info.get("iff", {}) if info.get("iff", {}) is Dictionary else {}
	var elint: Dictionary = info.get("elint", {}) if info.get("elint", {}) is Dictionary else {}
	var comint: Dictionary = info.get("comint", {}) if info.get("comint", {}) is Dictionary else {}
	var x := INFO_RECT.position.x + 12.0
	var y := INFO_RECT.position.y + 40.0
	# IFF 最近结果 + friend/unknown 计数（永远没有 hostile）
	var iff_rows: Array = []
	var by_t: Dictionary = iff.get("by_target", {}) if iff.get("by_target", {}) is Dictionary else {}
	var friend_n := 0
	var unknown_n := 0
	var last_iff: Dictionary = {}
	var last_t := -1.0
	for tid2 in by_t.keys():
		var row: Dictionary = by_t[tid2] if by_t[tid2] is Dictionary else {}
		iff_rows.append(row)
		var idn := String(row.get("identity", "unknown"))
		if idn == "friend":
			friend_n += 1
		else:
			unknown_n += 1
		if float(row.get("t", 0.0)) >= last_t:
			last_t = float(row.get("t", 0.0))
			last_iff = row
	_txt(mono, x, y, "IFF friend %d · unknown %d · hostile 0 %s" % [
		friend_n, unknown_n, String(last_iff.get("status", ""))], 7, Pal.a(Pal.PH, 0.9))
	_txt(mono, x, y + 12.0, "last %s identity=%s；无应答/缴获码/超距 → unknown；NO AUTO HOSTILE" % [
		String(last_iff.get("target_id", "—")), String(last_iff.get("identity", "unknown"))],
		7, Pal.a(Pal.AMBER, 0.85))
	y += 30.0
	var sigs: Array = elint.get("signals", []) if elint.get("signals", []) is Array else []
	var fixes: Array = elint.get("fix_candidates", []) if elint.get("fix_candidates", []) is Array else []
	var last_sig: Dictionary = sigs[sigs.size() - 1] if not sigs.is_empty() else {}
	_txt(mono, x, y, "ELINT signals %d · fix candidates %d" % [sigs.size(), fixes.size()],
		7, Pal.a(Pal.PH_DIM, 0.95))
	_txt(mono, x + 10.0, y + 13.0, "sig %s · %s · brg %.1f° · σ%.1f°" % [
		String(last_sig.get("source_id", "—")), String(last_sig.get("signature", "—")),
		float(last_sig.get("bearing_deg", 0.0)), float(last_sig.get("bearing_sigma_deg", 0.0))],
		7, Pal.a(Pal.TXT, 0.85))
	_txt(mono, x + 10.0, y + 25.0, "single station → NO CONTACT；FIX 仅为候选（需确认）", 7,
		Pal.a(Pal.FAINT, 0.9))
	y += 46.0
	var cevents: Array = comint.get("events", []) if comint.get("events", []) is Array else []
	var last_c: Dictionary = cevents[cevents.size() - 1] if not cevents.is_empty() else {}
	var content: Dictionary = last_c.get("comms_content", {}) if last_c.get("comms_content", {}) is Dictionary else {}
	_txt(mono, x, y, "COMINT %d · encrypted %s · decode=%s" % [
		cevents.size(), "Y" if bool(content.get("encrypted", false)) else "N",
		"OFF" if not bool(comint.get("auto_decode", false)) else "ON"], 7, Pal.a(Pal.TXT, 0.9))
	_txt(mono, x + 10.0, y + 13.0, "%s→%s · %s" % [
		String(last_c.get("from", "—")), String(last_c.get("to", "—")),
		String(content.get("mode", "radio"))], 7, Pal.a(Pal.FAINT, 0.9))


func _draw_ew() -> void:
	_panel(EW_RECT, "EW / INFO OPS", "单一事件总线 · 无自动判敌")
	var ew: Dictionary = vm.get("ew", {})
	var radar: Dictionary = ew.get("radar", {}) if ew.get("radar", {}) is Dictionary else {}
	var comms: Dictionary = ew.get("comms", {}) if ew.get("comms", {}) is Dictionary else {}
	var optical: Dictionary = ew.get("optical", {}) if ew.get("optical", {}) is Dictionary else {}
	var phantom: Dictionary = ew.get("phantom", {}) if ew.get("phantom", {}) is Dictionary else {}
	var effects: Array = ew.get("effects", []) if ew.get("effects", []) is Array else []
	var x := EW_RECT.position.x + 12.0
	var y := EW_RECT.position.y + 40.0
	var eff_names: Array = []
	for raw in effects:
		if raw is Dictionary:
			eff_names.append(String((raw as Dictionary).get("effect", "")))
	_txt(mono, x, y, "EFFECTS %d · %s" % [effects.size(), ",".join(eff_names)], 7,
		Pal.a(Pal.AMBER if effects.size() > 0 else Pal.FAINT, 0.9))
	_txt(mono, x, y + 12.0, "RADAR jam %.2f → R_eff %.0f km · COMMS %.1fs loss %.0f%%" % [
		float(radar.get("jamming", 0.0)), float(radar.get("effective_radius_km", 0.0)),
		float(comms.get("latency_s", 0.0)), float(comms.get("packet_loss", 0.0)) * 100.0],
		7, Pal.a(Pal.TXT, 0.86))
	_txt(mono, x + 250.0, y + 12.0, "PHANTOM %d · DAZZLE %s" % [
		int(phantom.get("active", 0)), "Y" if bool(optical.get("dazzled", false)) else "N"],
		7, Pal.a(Pal.AMBER, 0.9))


func _draw_tws() -> void:
	_panel(TWS_RECT, "TWS STATE MACHINE", "六态通道")
	var by: Dictionary = vm.get("by_state", {})
	var x := TWS_RECT.position.x + 12.0
	var y := TWS_RECT.position.y + 42.0
	for st in STATE_ORDER:
		var n := int(by.get(st, 0))
		var col := _state_col(st)
		var chip := "%s %d" % [_state_short(st), n]
		var w := 8.0 + 6.6 * float(chip.length())
		draw_rect(Rect2(x - 4.0, y - 11.0, w, 15.0),
			Pal.a(col, 0.10 if n == 0 else 0.20))
		draw_rect(Rect2(x - 4.0, y - 11.0, w, 15.0), Pal.a(col, 0.35 if n == 0 else 0.8), false, 1.0)
		_txt(mono, x, y, chip, 7, Pal.a(col, 0.95 if n > 0 else 0.45))
		x += w + 8.0
	var chans: Array = vm.get("channels", [])
	var yy := TWS_RECT.position.y + 66.0
	for i in range(mini(6, chans.size())):
		var ch: Dictionary = chans[i]
		var stc := String(ch.get("state", ""))
		_txt(mono, TWS_RECT.position.x + 12.0, yy, "S%d" % int(ch.get("slot", i)), 7,
			Pal.a(Pal.PH_FAINT, 0.9))
		_txt(mono, TWS_RECT.position.x + 40.0, yy, String(ch.get("target_id", "")), 7,
			Pal.a(Pal.TXT, 0.85))
		_txt(mono, TWS_RECT.position.x + 112.0, yy, _state_short(stc), 7,
			Pal.a(_state_col(stc), 0.95))
		var q := float(ch.get("quality", 0.0))
		_txt(mono, TWS_RECT.position.x + 190.0, yy, "q%.0f%%" % (q * 100.0), 7,
			Pal.a(Pal.TXT, 0.8))
		_txt(mono, TWS_RECT.position.x + 266.0, yy, "age%.0fs" % float(ch.get("age_s", 0.0)),
			7, Pal.a(Pal.FAINT, 0.95))
		_txt(mono, TWS_RECT.position.x + 356.0, yy, "lost%d" % int(ch.get("lost_lock_count", 0)),
			7, Pal.a(Pal.AMBER if int(ch.get("lost_lock_count", 0)) > 0 else Pal.FAINT, 0.9))
		yy += 17.0
	if chans.is_empty():
		_txt(mono, TWS_RECT.position.x + 12.0, yy, "NO CHANNELS · 雷达/EMCON 关闭或扫描未命中", 7,
			Pal.a(Pal.FAINT, 0.9))
	var tws: Dictionary = vm.get("tws", {})
	_txt(mono, TWS_RECT.end.x - 10.0, TWS_RECT.position.y + 42.0,
		"SCAN %d · %.0f s · 6 slots" % [int(tws.get("scan_index", 0)),
		float(tws.get("scan_period_s", 6.0))], 7, Pal.a(Pal.FAINT, 0.9))


func _draw_events() -> void:
	_panel(EVENT_RECT, "EVENT LOG", "事件时间线")
	var events: Array = vm.get("events", [])
	var y := EVENT_RECT.position.y + 40.0
	var n := 0
	for i in range(events.size() - 1, -1, -1):
		if n >= 8:
			break
		var ev: Dictionary = events[i]
		var kind := String(ev.get("kind", ""))
		var col := _event_col(kind)
		_txt(mono, EVENT_RECT.position.x + 12.0, y, "T+%06.1f" % float(ev.get("t", 0.0)), 7,
			Pal.a(Pal.PH_FAINT, 0.95))
		var text := _fit(cjk if UiFonts.has_cjk(String(ev.get("text", ""))) else mono, String(ev.get("text", "")), 7, EVENT_RECT.size.x - 104.0)
		var f: Font = cjk if UiFonts.has_cjk(text) else mono
		_txt(f, EVENT_RECT.position.x + 92.0, y, text, 7, Pal.a(col, 0.92))
		y += 17.0
		n += 1
	if n == 0:
		_txt(mono, EVENT_RECT.position.x + 12.0, y, "WAITING FOR SENSOR EVENTS…", 7,
			Pal.a(Pal.FAINT, 0.9))


func _draw_sensors() -> void:
	_panel(SENSOR_RECT, "SENSORS", "传感器状态")
	var x := SENSOR_RECT.position.x + 12.0
	var y := SENSOR_RECT.position.y + 40.0
	var radar_on := bool(vm.get("radar_on", false))
	_txt(mono, x, y, "RADAR", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, x + 86.0, y, "YW-R9 · " + ("ON / EMITTING" if radar_on else "EMCON / OFF"), 7,
		Pal.a(Pal.PH if radar_on else Pal.AMBER, 0.92))
	y += 16.0
	var exp: Dictionary = vm.get("exposure", {})
	_txt(mono, x, y, "EXPOSURE", 7, Pal.a(Pal.FAINT, 0.9))
	if bool(exp.get("exposed", false)):
		_txt(mono, x + 86.0, y, "ELINT ≤ %.0f km · fix %.0f%% (%.0f s)" % [
			float(exp.get("elint_intercept_range_km", 0.0)),
			float(exp.get("fix_progress", 0.0)) * 100.0,
			float(exp.get("fix_after_s", 0.0))], 7, Pal.a(Pal.AMBER, 0.9))
	else:
		_txt(mono, x + 86.0, y, "PASSIVE / not exposed", 7, Pal.a(Pal.PH, 0.9))
	y += 16.0
	var elint_on := bool(vm.get("elint_on", false))
	_txt(mono, x, y, "ELINT RX", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, x + 86.0, y, ("ON · passive" if elint_on else "OFF"), 7,
		Pal.a(Pal.PH if elint_on else Pal.FAINT, 0.9))
	y += 16.0
	var opt: Dictionary = vm.get("optical", {})
	_txt(mono, x, y, "VIS / IR", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, x + 86.0, y, "VIS %d ch (lock %d) · IR %d ch (lock %d)" % [
		int(opt.get("vis_total", 0)), int(opt.get("vis_locked", 0)),
		int(opt.get("ir_total", 0)), int(opt.get("ir_locked", 0))], 7,
		Pal.a(Pal.BLUE, 0.9))
	y += 18.0
	var signals: Array = (vm.get("elint", {}) as Dictionary).get("signals", [])
	_txt(mono, x, y, "ELINT SIGNALS", 7, Pal.a(Pal.FAINT, 0.9))
	if signals.is_empty():
		_txt(mono, x + 130.0, y, "none captured", 7, Pal.a(Pal.FAINT, 0.9))
	else:
		var first: Dictionary = signals[0]
		_txt(mono, x + 130.0, y, "%s · bearing-only · q%.2f" % [
			String(first.get("signature", "?")), float(first.get("quality", 0.0))], 7,
			Pal.a(Pal.AMBER, 0.9))
	y += 16.0
	var iff: Dictionary = vm.get("iff", {})
	_txt(mono, x, y, "IFF", 7, Pal.a(Pal.FAINT, 0.9))
	_txt(mono, x + 86.0, y, "%s → %s" % [
		String(iff.get("target_id", "—")), String(iff.get("status", "no query"))], 7,
		Pal.a(Pal.BLUE if String(iff.get("status", "")) == "friend" else Pal.AMBER, 0.9))


func _draw_labels() -> void:
	var placed: Array[Rect2] = []
	var targets: Array = vm.get("targets", [])
	for i in range(targets.size()):
		var tr: Dictionary = targets[i]
		if not bool(tr.get("on_screen", false)):
			continue
		var p: Vector2 = tr.get("screen", Vector2(-9999, -9999))
		if p.x < 0.0 or p.y < 0.0 or p.x > 1920.0 or p.y > 1080.0:
			continue
		if TARGET_RECT.has_point(p) or SELECT_RECT.has_point(p) or TWS_RECT.has_point(p) \
				or EVENT_RECT.has_point(p) or SENSOR_RECT.has_point(p) \
				or OPTICAL_RECT.has_point(p) or INFO_RECT.has_point(p) or EW_RECT.has_point(p):
			continue
		var sel := bool(tr.get("selected", false))
		var stc := String(tr.get("state", ""))
		var col := _state_col(stc)
		var label := "%s · %s" % [String(tr.get("name", "")), _state_short(stc)]
		var f: Font = cjk if UiFonts.has_cjk(label) else mono
		var sz := 8 if sel else 7
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
		var cands: Array[Vector2] = []
		for row in range(3):
			cands.append(Vector2(p.x + 12.0, p.y - 3.0 + 12.0 * float(row)))
		for row2 in range(3):
			cands.append(Vector2(p.x - 16.0 - tw, p.y - 3.0 + 12.0 * float(row2)))
		var tx := p.x + 12.0
		var ty := p.y - 3.0
		var ok := false
		for cpos in cands:
			var cp: Vector2 = cpos
			var r := Rect2(cp.x - 2.0, cp.y - float(sz), tw + 4.0, float(sz) + 4.0)
			if cp.x < 8.0 or cp.y < 22.0 or cp.x + tw > 1912.0 or cp.y > 1006.0:
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
				ok = true
				break
		if not ok and not sel:
			continue
		if not ok:
			placed.append(Rect2(tx - 2.0, ty - float(sz), tw + 4.0, float(sz) + 4.0))
		# 目标环（2D 投影上的六态短线）
		draw_arc(p, 10.0, 0.0, TAU, 20, Pal.a(col, 0.35 if not sel else 0.7), 1.0, true)
		var idx := STATE_ORDER.find(stc)
		if idx >= 0:
			var ang := -PI * 0.5 + TAU * float(idx) / 6.0
			var d := Vector2(cos(ang), sin(ang))
			draw_line(p + d * 10.0, p + d * 14.0, Pal.a(col, 0.95), 2.0 if sel else 1.0)
		draw_line(p + Vector2(2.0, 0.0), p + Vector2(6.0, 0.0), Pal.a(col, 0.7), 1.0)
		draw_line(p, Vector2(tx - 2.0, ty - 3.0), Pal.a(col, 0.5), 1.0)
		if sel:
			draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Pal.a(col, 0.9), false, 1.0)
		_txt(f, tx, ty, label, sz, Pal.a(col, 0.98 if sel else 0.82))
	# 雷达球/光学标注
	var notes: Array = vm.get("labels_3d", [])
	for raw in notes:
		if not (raw is Dictionary):
			continue
		var nt: Dictionary = raw
		var sp: Vector2 = nt.get("screen", Vector2(-9999, -9999))
		if sp.x < 0.0 or sp.y < 0.0:
			continue
		# 3D 标注收进可用区域，避开 HUD 面板
		sp.x = clampf(sp.x, 450.0, 1250.0)
		sp.y = clampf(sp.y, 120.0, 780.0)
		var txt := String(nt.get("text", ""))
		var f2: Font = cjk if UiFonts.has_cjk(txt) else mono
		_txt(f2, sp.x, sp.y, txt, 7, Pal.a(nt.get("color", Pal.PH), 0.85))


func _draw_footer() -> void:
	draw_line(Vector2(40.0, FOOT_Y - 14.0), Vector2(1880.0, FOOT_Y - 14.0), Pal.a(Pal.LINE, 0.8), 1.0)
	_txt(mono, 40.0, FOOT_Y, "V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17", 8, Pal.a(Pal.AMBER, 0.95))
	var note := String(vm.get("model_note", ""))
	if note != "":
		_txt(mono, 500.0, FOOT_Y, note, 7, Pal.a(Pal.FAINT, 0.8))
	_txt_r(mono, 1880.0, FOOT_Y, "SENSOR TECHNICAL DEMO · V1 WIREFRAME · SER. 060", 7,
		Pal.a(Pal.PH_FAINT, 0.95))


# ── 工具 ─────────────────────────────────────────────────────────

func _state_short(st: String) -> String:
	return String(STATE_SHORT.get(st, st if st != "" else "—"))


func _state_col(st: String) -> Color:
	match st:
		"SEARCH":
			return Pal.FAINT
		"DETECT":
			return Pal.PH_DIM
		"ACQUIRE":
			return Pal.BLUE
		"TRACK", "STARE":
			return Pal.PH
		"FIRE_CONTROL":
			return Pal.AMBER
		_:
			return Pal.DIM


func _event_col(kind: String) -> Color:
	if kind.find("iff") >= 0:
		return Pal.BLUE
	if kind.find("elint") >= 0:
		return Pal.AMBER
	if kind.find("optical") >= 0 or kind.find("stare") >= 0:
		return Pal.BLUE
	if kind.find("lost") >= 0 or kind.find("drop") >= 0:
		return Pal.RED
	if kind.find("fire") >= 0 or kind.find("fc") >= 0:
		return Pal.AMBER
	return Pal.PH_DIM


func _fit(f: Font, s: String, size: int, maxw: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= maxw:
		return s
	var cut := s
	while cut.length() > 1 and f.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > maxw:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "…"


func _fmt_hms(t: float) -> String:
	var sec := int(maxf(0.0, t))
	var h := (sec % 86400) / 3600
	var m := (sec % 3600) / 60
	var s := sec % 60
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
