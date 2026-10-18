class_name WarState
extends RefCounted

# 演示用状态。真实 sim 会接管 clock / tracks / commands，
# 这里的数值只服务于"把 GUI 长相对出来"。
#
# P1c：传感器规则接线。
#   - 传感器架来自 SensorModel.all_racks()（不再手填 V2 全局 sensors）；
#     HUD 的传感器条/下拉显示"当前选中舰"的按舰架（state.sensors 只是视图）。
#   - 每仿真秒（FUSION_PERIOD_S）跑一次融合 tick：
#       detect_all（各友军传感器、按 refresh_s 节流）→ update_track → age_track
#     得到等级证据 / 协方差 / 分类 / 身份 / IFF 状态；
#   - 暴露：emission_state 合并全队发射器；敌方 ELINT 截获 → elint_hits；
#   - 保留 P1a 的 r/v/epoch 轨道推进（refresh）。
#
# 教学时序（占位：最终由命令层决定开关）：
#   T+0   CH-IR2 / MS-IR9 被动红外 → L1 方位线（另有一条 CH-IR2 虚警）
#   T+12  交叉确认：MS-IR9 该方位无回波 → 虚警 / FALSE ALARM
#   T+20  远地点 YW-R9 开机 → L2（同时 EMIT 暴露，被传唤级 ELINT 点名）
#   T+46  远地点 MS-OT2 光学凝视 → L3 分类
#   T+62  远地点 MK-12 IFF → 友军 L4（谷神-2 应答机故障 → 不明 ≠ 敌意）

const Orbit := preload("res://scripts/orbit_model.gd")
const SensorModel := preload("res://scripts/sensor_model.gd")
const CommandModel := preload("res://scripts/command_model.gd")

const T0 := 760.8

# 融合节奏与教学开关时刻（仿真秒，相对 T0）
const FUSION_PERIOD_S := 1.0
const RADAR_ON_T := 20.0
const OPTICAL_ON_T := 46.0
const IFF_ON_T := 62.0
const PHANTOM_TRUE_T := 12.0
const MAX_CATCHUP_TICKS := 600

# 可由 scenario 覆盖的教学时序（仿真秒，T0 起算）
var radar_on_t := RADAR_ON_T
var optical_on_t := OPTICAL_ON_T
var iff_on_t := IFF_ON_T
var phantom_true_t := PHANTOM_TRUE_T

# L1 站心几何：地球 / 月球位置（km），用于视线/阴影判定
const EARTH_LOCAL_KM := Vector3(-326000.0, 0.0, 0.0)
const R_EARTH_KM := 6378.137
const SUN_ILLUM := 1.0

# 本队探测器（融合画面来源）
const DETECTOR_SHIPS := ["apsis", "harmattan", "ferry", "watchtower"]

# 基准（datum）：图上"下"参照谁。EARTH / MOON / L1。
const DATUMS := ["EARTH", "MOON", "L1"]
var datum := "L1"

var clock := T0
var time_scale := 60.0
var paused := false
var capture := false
var elapsed := 0.0
var selected := 0
var sensor := 0
# HUD 视图：当前选中舰的传感器架（字段：mfr/model/mode/sig/glyph/color）
var sensors: Array[Dictionary] = []
var boot_t := 0.0
var sensor_fx_t := -1.0
var fleet_dv := 8420
var grace_left := 62.0 * 3600.0 + 18.0 * 60.0 + 44.0

# 执行窗口：传唤级进入 50 km 检查边界后开始，仿真时间 6 分钟，时标锁 1×。
var exec_left := 360.0
var exec_locked := true

var tracks: Array[Dictionary] = []
var log_lines: Array[Dictionary] = []
var unit: Dictionary = {}

# 本舰基线状态（L1 站心，km / km/s）。
var own: Dictionary = {}
var own_cur: Dictionary = {}
var burn: Dictionary = {}

# ── P1d 命令 / 点火 ────────────────────────────────────
var cmd_model                          # CommandModel（命令队列）
var own_events: Array = []             # 已生效点火 [{t: 绝对 tau, dv: Vector3}]
var unit_dv_ms := 1120.0               # 本舰剩余 Δv（m/s）
var unit_dv_max := 1260.0
var shadow_target := ""                # SHADOW 生效目标
var shadow_since := -1.0
var station_hold := false
var cmd_note := ""
# P1e：场景 / 传感器开关 / EMCON
var scenario: Dictionary = {}
var scenario_source := "fallback"
var sensor_override: Dictionary = {}   # ship -> {model: bool}（set_sensor 手动开关，优先于脚本时序）
var emcon: Dictionary = {}             # ship -> bool（EMCON：发射类传感器强制关）
var phantom_bearing := 302.0

# ── P1f 第一关闭环：三个阶段 → 决断 → 报告 ─────────────────
const PHASE_READ := "READ"
const PHASE_COMMAND := "COMMAND"
const PHASE_DECIDE := "DECIDE"
const PHASE_REPORT := "REPORT"
const PHASE_END := "END"

var tut_phase := PHASE_READ
var decision_open := false
var report_open := false
var consequence_open := false
var fire_branch := false
var outcome := ""
var report_text := ""
var report_options: Array[Dictionary] = []
var audit_flag := false
var perjury_count := 0
var reputation: Dictionary = {"斛港务": 0, "清算署": 0, "远环合作社": 0}
var sim_frozen := false
var decision_t := 75.0
var decision_prompt := ""
var consequence_text := ""
var report_choice := ""
var story: Dictionary = {}
var story_events: Array = []
var endings: Array[Dictionary] = []
var flags: Dictionary = {}
# P1g：完整流程（事件/无线电 feed、END、重开）
var end_open := false
var end_summary: Dictionary = {}
var radio_feed: Array = []
var event_feed: Array = []
var _feed_fired: Dictionary = {}
# P1j：通信格式 / 身份 / 通知
var notice: Dictionary = {}
var decision_replies: Dictionary = {}
var report_unit := "AD 特遣群监督官"
var report_event := "斛 · 第七号裁定接管通知"
var report_evidence := "黑匣子、通信流、传感器日志与光学分类记录。"
var report_bodies: Dictionary = {}
var report_recommend: Dictionary = {}
var link_mode := "LD"
var scenario_sensor_init: Dictionary = {}   # scenario 传感器初始开关（非时序项）

# ── P1c 传感器状态 ─────────────────────────────────────
var racks: Dictionary = {}                 # ship_id -> [sensor...]（SensorModel）
var sensor_on: Dictionary = {}             # ship_id -> {model: bool}（当前融合计划）
var rack_ship := "harmattan"               # HUD 传感器架对应的舰
var emission: Dictionary = {}              # 合并后的舰队暴露态
var fleet_emissions: Array = []            # 各舰 emission_state
var elint_hits: Array = []                 # 敌方 ELINT 截获记录
var elint_named := false                   # 是否已被点名
var fusion_t := 0.0                        # 上次融合的仿真秒
var fusion_count := 0
var phantom_true := false                  # CH-IR2 虚警是否已交叉确认为假
var sensor_note := ""                      # 给 plot 的一行状态
var rng := RandomNumberGenerator.new()

var _seconds_on: Dictionary = {}           # ship -> {model: 秒}
var _last_call: Dictionary = {}            # "ship|model" -> tau
var _stare: Dictionary = {}                # "ship|model|track" -> 凝视秒
var _optical_target := ""                  # 光学一次只凝视一个目标
var _optical_done: Dictionary = {}         # track_id -> 已分类
var _sensors_view_key := ""

func set_datum(d: String) -> void:
	var u := d.to_upper()
	if DATUMS.has(u):
		datum = u

func cycle_datum() -> String:
	var i := DATUMS.find(datum)
	datum = DATUMS[(i + 1) % DATUMS.size()]
	return datum

func _init() -> void:
	_bootstrap()

func _bootstrap() -> void:
	rng.seed = 4471
	scenario = _load_scenario()
	_apply_scenario_env()
	_load_story()
	racks = SensorModel.all_racks()
	cmd_model = CommandModel.new()
	_build_tracks()
	_build_phantom()
	_build_log()
	_build_unit()
	_seed_demo_commands()
	selected = _own_track_index()
	_sync_sensor_view()
	_plan_tick(0.0)
	_fusion_tick(0.0)
	_pump_feeds(0.0)

# ── 舰 / 架 ────────────────────────────────────────────

const TRACK_SHIP := {
	"1000": "apsis",
	"1001": "harmattan",
	"1002": "ferry",
	"1003": "watchtower",
	"1004": "deepwell",
	"2001": "summons_4471",
	"9001": "ceres_2",
	"9002": "harmattan",
}

func _own_track_index() -> int:
	for i in range(tracks.size()):
		if bool((tracks[i] as Dictionary).get("own", false)):
			return i
	return 0

func _ship_id_for_track(track_id: String) -> String:
	return String(TRACK_SHIP.get(track_id, "harmattan"))

func _hud_sensor(s: Dictionary) -> Dictionary:
	var t := String(s.get("type", ""))
	var glyph := "ring"
	var col := "#8CF0C0"
	match t:
		"ir":
			glyph = "web"
			col = "#E8A34B"
		"radar":
			glyph = "hex"
			col = "#8CF0C0"
		"optical":
			glyph = "frame"
			col = "#7FB6C9"
		"iff":
			glyph = "gate"
			col = "#8CF0C0"
		"elint":
			glyph = "jag"
			col = "#E2564A"
		_:
			glyph = "ring"
			col = "#7FA995"
	var sig := "刷新 %.0f s" % float(s.get("refresh_s", 1.0))
	if t == "radio" or t == "lasercom":
		sig = "时延 %.1f s" % float(s.get("latency_s", 4.0))
	if bool(s.get("expose", false)):
		sig += " · 辐射"
	return {
		"mfr": String(s.get("source", "—")),
		"model": String(s.get("model", "?")),
		"mode": String(s.get("mode", t)),
		"sig": sig,
		"glyph": glyph,
		"color": col,
		"on": bool(s.get("on", true)),
		"expose": bool(s.get("expose", false)),
	}

# 按当前 selected 行重建 HUD 传感器架视图；返回是否变化
func _sync_sensor_view() -> void:
	var idx := clampi(int(selected), 0, maxi(0, tracks.size() - 1))
	var tid := "哈马丹"
	if idx >= 0 and idx < tracks.size():
		tid = String(tracks[idx].get("id", "哈马丹"))
	var ship := _ship_id_for_track(tid)
	var key := "%s#%s" % [ship, str(racks.get(ship, []))]
	if key == _sensors_view_key and not sensors.is_empty():
		return
	_sensors_view_key = key
	rack_ship = ship
	var arr: Array[Dictionary] = []
	for s in SensorModel.sensor_rack(ship):
		arr.append(_hud_sensor(s))
	if arr.is_empty():
		arr.append(_hud_sensor({"model": "—", "type": "comm", "source": "—", "mode": "—"}))
	sensors = arr
	sensor = clampi(int(sensor), 0, sensors.size() - 1)

func active_sensor() -> Dictionary:
	if sensors.is_empty():
		return {}
	var i := clampi(int(sensor), 0, sensors.size() - 1)
	var model := String(sensors[i].get("model", ""))
	return SensorModel.rack_sensor(rack_ship, model)

# ── 轨道 / 几何 ────────────────────────────────────────

func _build_tracks() -> void:
	if scenario.has("tracks") and (scenario.get("tracks", []) as Array).size() > 0:
		_build_tracks_from_scenario()
		if tracks.size() > 0:
			burn = {}
			return
	# r/v 全部是 L1 站点相对（km, km/s）：+x 地月连线方向（指向月球）、
	# +y 面内横向、+z 轨道法向。plot 里把 +y 当"北"、+x 当"东"用。
	var own_r := Vector3(2.0, -3.0, 0.0)
	var own_v := Vector3(0.22, -0.12, 0.03)
	own = {"r": own_r, "v": own_v}
	own_cur = {"r": own_r, "v": own_v}
	tracks = [
		_track("哈马丹", "HARMATTAN", "托盘-5 改", "哨舰", "friend", 4,
			own_r, own_v, 0.0, true, Vector2(16, 14)),
		_track("渡口号", "FERRY", "赤铁-6 改", "炮舰", "friend", 4,
			_rel(332.0, 68.0, -4.0), Vector3(-0.0607, -0.0775, 0.0074), 1.0, false, Vector2(-72, -20)),
		_track("望楼号", "WATCHTOWER", "安海-1", "中继舰", "friend", 4,
			_rel(12.0, 96.0, 38.0), Vector3(-0.1174, 0.0250, 0.0200), 1.0, false, Vector2(16, -18)),
		_track("案卷 4471", "SUMMONS", "传唤级", "送达", "hostile", 1,
			_rel(41.0, 318.0, 12.0), Vector3(-1.1683, -0.5067, -0.0634), 2.0, false, Vector2(-86, -38)),
		_track("谷神-2", "CERES-2", "谷神改", "民用工作船", "unknown", 1,
			_rel(118.0, 260.0, -6.0), Vector3(0.0505, 0.0524, -0.0005), 12.0, false, Vector2(16, 12)),
	]
	# 点火计划：T+6.2 s、Δv 84 m/s、方位 340°、仰角 +20°（含离面分量）。
	burn = {
		"t": 6.2,
		"brg": 340.0,
		"elev": 20.0,
		"dv_ms": 84.0,
		"dv": _dv_vec(340.0, 20.0, 0.084),
		"label": "点火（BURN）哈马丹 → 节点 B-2"
	}

# CH-IR2 虚警（07 §3 Phase 1「两条回波」：真目标是案卷 4471，另一条是残骸/反射）。
# 没有真实实体：无 r/v、不发射、不预测；只有一条方位线。
func _build_phantom() -> void:
	var ch_ir2 := SensorModel.rack_sensor("harmattan", "CH-IR2")
	var fa := SensorModel.maybe_false_alarm(ch_ir2, {
		"false_alarm_scale": 100.0,   # 教学：强制掷出
		"false_bearing_deg": phantom_bearing,
	})
	var d := {
		"id": "9002", "batch": "9002", "name": "CH-IR2 虚警", "en": "UNKNOWN CONTACT", "cls": "CH-IR2 虚警候选", "role": "虚警候选 · 残骸/反射", "identity": "pending",
		"side": "unknown", "level": 1, "bearing": phantom_bearing, "range": 0.0, "alt": 0.0,
		"closing": 0.0, "age": 0.0, "own": false, "off": Vector2(-120, -26),
		"stale": false, "bearing_only": true, "phantom": true,
		"r": Vector3.ZERO, "v": Vector3.ZERO, "epoch": T0,
		"range_band": "UNKNOWN", "sources": ["CH-IR2"],
		"no_prediction": true, "false_alarm": false, "occluded": false,
		"obs_range_km": -1.0, "obs_bearing_deg": phantom_bearing,
		"covariance": {}, "classification": {}, "id_info": {}, "iff_status": "",
		"notes": [String(fa.get("warning", "CH-IR2 虚警候选"))],
	}
	tracks.append(d)

func _rel(bearing: float, range_km: float, alt_km: float) -> Vector3:
	var b := deg_to_rad(bearing)
	return Vector3(sin(b) * range_km, cos(b) * range_km, alt_km)

func _dv_vec(bearing: float, elev: float, dv_kms: float) -> Vector3:
	var b := deg_to_rad(bearing)
	var e := deg_to_rad(elev)
	return Vector3(sin(b) * cos(e), cos(b) * cos(e), sin(e)) * dv_kms

func _track(id: String, en: String, cls: String, role: String, side: String, level: int,
		r: Vector3, v: Vector3, age: float, is_own := false,
		off := Vector2(16, 12), bearing_only := false,
		name := "", identity := "") -> Dictionary:
	var d := {
		"id": id, "en": en, "cls": cls, "role": role, "side": side, "level": level,
		"r": r, "v": v, "epoch": T0, "age": age,
		"own": is_own, "off": off, "bearing_only": bearing_only,
		"stale": age > 30.0,
		# P1c 融合字段
		"sensor_track": {}, "level_evidence": {}, "covariance": {},
		"sources": [], "classification": {}, "id_info": {}, "iff_status": "",
		"range_band": "", "obs_range_km": -1.0, "obs_bearing_deg": -1.0,
		"occluded": false, "stare": {}, "notes": [],
	}
	d["batch"] = id
	d["name"] = name if name != "" else id
	d["identity"] = identity if identity != "" else _default_identity(side)
	_derive(d, r, v)
	return d

# 从站心状态派生 HUD / 图上用的量（bearing/range/alt/closing 都由 r/v 算，不再手填）
func _derive(d: Dictionary, r: Vector3, v: Vector3) -> void:
	d["cur_r"] = r
	d["cur_v"] = v
	var rng_km := r.length()
	d["range"] = rng_km
	d["bearing"] = fposmod(rad_to_deg(atan2(r.x, r.y)), 360.0)
	d["alt"] = r.z
	d["closing"] = (-r.dot(v) / rng_km) if rng_km > 1.0e-6 else 0.0

func tau() -> float:
	return clock - T0

func track_by_id(id: String) -> Dictionary:
	for tr in tracks:
		if String(tr.get("id", "")) == id:
			return tr
	return {}

# 把每条 track 推进到 now（相对 T0 的秒），并刷新派生量；
# 按仿真时间补齐融合 tick（1 Hz）。捕获/截图时 clock 不动，这里幂等。
# ── 命令 / 点火（P1d）──────────────────────────────────

func commands() -> Array:
	return cmd_model.commands if cmd_model != null else []

func pending_commands() -> Array:
	return cmd_model.pending() if cmd_model != null else []

func _commands_locked() -> bool:
	return tut_phase == PHASE_DECIDE or tut_phase == PHASE_REPORT or tut_phase == PHASE_END \
		or decision_open or consequence_open or report_open or end_open

func issue_command(action: String, params: Dictionary = {}, target := "") -> Dictionary:
	if cmd_model == null:
		return {}
	if _commands_locked():
		_push_log("命令不可用：已进入决断/报告阶段", "LOCKED", "HOLD")
		return {}
	var p := params.duplicate(true)
	p["budget_ms"] = unit_dv_ms
	var cmd: Dictionary = cmd_model.issue("哈马丹", action, target, p, tau())
	_push_command_log(cmd)
	cmd_note = _cmd_note()
	return cmd

func abort_command(id: String) -> Dictionary:
	if cmd_model == null:
		return {}
	if _commands_locked():
		return {}
	var c: Dictionary = cmd_model.abort(id, tau())
	if not c.is_empty():
		_update_command_log(c)
		_push_log("撤销 %s %s" % [String(c.get("id", "")), CommandModel.action_label(String(c.get("action", "")))], "ABORT", "HOLD")
		cmd_note = _cmd_note()
	return c

func abort_latest_command() -> Dictionary:
	if _commands_locked():
		return {}
	for raw in pending_commands():
		return abort_command(String((raw as Dictionary).get("id", "")))
	return {}

func _seed_demo_commands() -> void:
	var init_cmds: Array = scenario.get("initial_commands", [])
	if init_cmds.size() > 0:
		for raw in init_cmds:
			var c: Dictionary = raw
			var params: Dictionary = (c.get("params", {}) as Dictionary).duplicate(true)
			params["budget_ms"] = unit_dv_ms
			var cmd: Dictionary = cmd_model.issue(
				String(c.get("unit", "哈马丹")), String(c.get("action", "")),
				String(c.get("target", "")), params, float(c.get("issue_t", 0.0)))
			_push_command_log(cmd)
		cmd_note = _cmd_note()
		return
	# 07 §3 Phase 1：哈马丹跟踪谷神-2（命令经望楼中继 8 s）
	var shadow: Dictionary = cmd_model.issue("哈马丹", "SHADOW", "9001", {"hold_km": 60.0}, 0.0)
	# 本舰计划点火：T+6.2 s、Δv 84 m/s、BRG 340 / ELEV +20
	var dv := CommandModel.dv_vector(340.0, 20.0, 84.0)
	var burn_cmd: Dictionary = cmd_model.issue("哈马丹", "BURN", "", {
		"exec_t": 6.2, "dv_ms": 84.0, "brg": 340.0, "elev": 20.0, "dv": dv,
		"budget_ms": unit_dv_ms,
	}, 0.0)
	# HUD 日志首两行 = 真实命令（状态随命令机更新）
	log_lines[0] = {"t": "T+00.0", "text": "点火（BURN）哈马丹 · 节点 B-2", "arg": "T+06.2s", "status": "PENDING", "_cmd": String(burn_cmd.get("id", ""))}
	log_lines[1] = {"t": "T+00.0", "text": "跟踪（SHADOW）哈马丹 → 9001", "arg": "中继 8s", "status": "PENDING", "_cmd": String(shadow.get("id", ""))}
	cmd_note = _cmd_note()

func _push_command_log(cmd: Dictionary) -> void:
	if cmd.is_empty():
		return
	var act := String(cmd.get("action", ""))
	var stat := String(cmd.get("status", ""))
	var txt := "%s 哈马丹" % act
	if act == "SHADOW":
		txt = "跟踪（SHADOW）哈马丹 → %s" % String(cmd.get("target", ""))
	elif act == "BURN":
		txt = "点火（BURN）哈马丹 · Δv %.0f" % float((cmd.get("plan", {}) as Dictionary).get("dv_ms", 0.0))
	log_lines.push_front({
		"t": "T+%05.1f" % float(cmd.get("issue_t", 0.0)),
		"text": txt,
		"arg": CommandModel.status_label(stat),
		"status": ("PENDING" if stat == "QUEUED" else "RX"),
		"_cmd": String(cmd.get("id", "")),
	})
	while log_lines.size() > 6:
		log_lines.pop_back()

func _update_command_log(cmd: Dictionary) -> void:
	var id := String(cmd.get("id", ""))
	var st := String(cmd.get("status", ""))
	for raw in log_lines:
		var r: Dictionary = raw
		if String(r.get("_cmd", "")) != id:
			continue
		r["arg"] = CommandModel.status_label(st)
		match st:
			"EXEC":
				r["status"] = "EXEC"
			"DONE":
				r["status"] = "EXEC"
			"TRANSMITTED":
				r["status"] = "RX"
			"ABORTED":
				r["status"] = "HOLD"
			"REJECTED":
				r["status"] = "HOLD"
			_:
				r["status"] = "PENDING"

func _cmd_note() -> String:
	if cmd_model == null:
		return ""
	var n: Dictionary = cmd_model.counted()
	var q := int(n.get("QUEUED", 0)) + int(n.get("TRANSMITTED", 0))
	return "CMD 待%d / 执行%d / 完成%d / 撤销%d · Δv %.0f m/s" % [
		q, int(n.get("EXEC", 0)), int(n.get("DONE", 0)), int(n.get("ABORTED", 0)), unit_dv_ms]

func _apply_command(cmd: Dictionary, tick_t: float) -> void:
	var act := String(cmd.get("action", ""))
	match act:
		"BURN":
			var plan: Dictionary = cmd.get("plan", {})
			var dv: Vector3 = plan.get("dv", Vector3.ZERO)
			var dv_ms := float(plan.get("dv_ms", 0.0))
			own_events.append({"t": float(cmd.get("exec_t", tick_t)), "dv": dv})
			own_events.sort_custom(func(a, b): return float((a as Dictionary).get("t", 0.0)) < float((b as Dictionary).get("t", 0.0)))
			unit_dv_ms = maxf(0.0, unit_dv_ms - dv_ms)
			fleet_dv = maxi(0, fleet_dv - int(round(dv_ms)))
			unit["dv"] = _fmt_int(int(round(unit_dv_ms)))
			_push_log("点火（BURN）哈马丹 · Δv %.0f m/s" % dv_ms, "T+%04.1fs" % float(cmd.get("exec_t", 0.0)), "EXEC")
		"SHADOW":
			shadow_target = String(cmd.get("target", ""))
			shadow_since = float(cmd.get("exec_t", tick_t))
			station_hold = false
			if _optical_target == "" and not _optical_done.has(shadow_target):
				_optical_target = shadow_target
			_push_log("跟踪（SHADOW）生效：哈马丹 → %s" % shadow_target, "望楼号中继", "EXEC")
		"STATION":
			station_hold = true
			for raw in cmd_model.pending():
				var other: Dictionary = raw
				if String(other.get("action", "")) == "BURN":
					cmd_model.abort(String(other.get("id", "")), tick_t)
					_update_command_log(other)
			_push_log("保持站位（STATION）· 哈马丹", "小修正", "EXEC")
	_update_command_log(cmd)
	cmd_note = _cmd_note()

# ── 本舰状态（含已生效点火的分段传播）────────────────────

func own_at(tau_abs: float) -> Dictionary:
	var r: Vector3 = own.r
	var v: Vector3 = own.v
	var cur := 0.0
	for raw in own_events:
		var ev: Dictionary = raw
		var et := float(ev.get("t", 0.0))
		if et > tau_abs + 1.0e-9:
			break
		var st := Orbit.local_propagate(r, v, et - cur)
		r = st["r"]
		v = st["v"] + (ev.get("dv", Vector3.ZERO) as Vector3)
		cur = et
	var st2 := Orbit.local_propagate(r, v, tau_abs - cur)
	return {"r": st2["r"], "v": st2["v"]}

func own_vel_at(tau_abs: float) -> Vector3:
	var st := own_at(tau_abs)
	return st["v"]

func track_at(tr: Dictionary, tau_abs: float) -> Dictionary:
	var ep := float(tr.get("epoch", T0)) - T0
	return Orbit.local_propagate(tr["r"], tr["v"], tau_abs - ep)

# 目标相对本舰（局部板坐标，km）
func board_pos(tr: Dictionary, tau_abs: float) -> Vector3:
	var st := track_at(tr, tau_abs)
	var ow := own_at(tau_abs)
	return (st["r"] as Vector3) - (ow["r"] as Vector3)

func board_vel(tr: Dictionary, tau_abs: float) -> Vector3:
	var st := track_at(tr, tau_abs)
	return (st["v"] as Vector3) - own_vel_at(tau_abs)

func _fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func refresh(now: float) -> void:
	var t := now - T0
	_update_phase_gate(t)
	_pump_feeds(t)
	if sim_frozen:
		return
	# 命令状态机 tick：QUEUED→TRANSMITTED→EXEC→DONE
	if cmd_model != null:
		var ph: Dictionary = cmd_model.tick(t)
		for raw in ph.get("transmitted", []):
			_update_command_log(raw as Dictionary)
		for raw in ph.get("exec", []):
			_apply_command(raw as Dictionary, t)
		for raw in ph.get("done", []):
			_update_command_log(raw as Dictionary)
		cmd_note = _cmd_note()
	# 本舰当前状态（含已生效点火的分段传播）
	own_cur = own_at(t)
	for tr in tracks:
		if tr.get("phantom", false):
			tr["age"] = maxf(0.0, t - phantom_true_t) if phantom_true else maxf(0.0, t)
			continue
		var st := track_at(tr, t)
		var rr: Vector3 = st["r"]
		var vv: Vector3 = st["v"]
		_derive(tr, rr, vv)
	# 融合 tick 补齐
	var steps := 0
	while fusion_t + FUSION_PERIOD_S <= t + 1.0e-6 and steps < MAX_CATCHUP_TICKS:
		fusion_t += FUSION_PERIOD_S
		_plan_tick(fusion_t)
		_fusion_tick(fusion_t)
		steps += 1
	_sync_sensor_view()
	_update_identity(t)

# ── 传感器融合 ─────────────────────────────────────────

# 教学用传感器开关计划（占位：最终由命令层/玩家开关决定）
func _plan_tick(t: float) -> void:
	var plan := {
		"apsis": {
			"MS-IR9": true,
			"MS-OT2": t >= optical_on_t,
			"MK-12": t >= iff_on_t,
			"ELINT": true,
		},
		"harmattan": {"YW-R9": t >= radar_on_t, "MS-OT2": t >= optical_on_t, "CH-IR2": true, "ELINT": true, "CH-R0": true},
		"ferry": {"CH-IR2": true, "LR-4": false, "CH-R0": true},
		"watchtower": {"MS-L2": true, "CH-R0": true},
		"deepwell": {"CH-R0": true},
		# 敌方（案卷 4471）：ELINT 与无线电接收常开；雷达保持静默
		"summons_4471": {"YW-R9": false, "MK-12": false, "ELINT": true, "CH-R0": true},
		"ceres_2": {"CH-R0": true},
	}
	# scenario 传感器初始开关：对非时序项生效（雷达/光学/IFF 由剧情时序控制）
	var tl_models := {"apsis": ["MK-12", "MS-OT2"], "harmattan": ["YW-R9", "MS-OT2"]}
	for raw_ship_s in scenario_sensor_init.keys():
		var ship_s := String(raw_ship_s)
		if not plan.has(ship_s):
			continue
		var skip: Array = tl_models.get(ship_s, [])
		var init_map: Dictionary = scenario_sensor_init[ship_s]
		for raw_model_s in init_map.keys():
			var model_s := String(raw_model_s)
			if skip.has(model_s):
				continue
			if (plan[ship_s] as Dictionary).has(model_s):
				(plan[ship_s] as Dictionary)[model_s] = bool(init_map[model_s])
	# P1e：手动开关（set_sensor）与 EMCON（发射类强制关）覆盖脚本时序
	for raw_ship in plan.keys():
		var ship := String(raw_ship)
		var om: Dictionary = sensor_override.get(ship, {})
		for raw_model in om.keys():
			var model := String(raw_model)
			if (plan[ship] as Dictionary).has(model):
				(plan[ship] as Dictionary)[model] = bool(om[model])
		if bool(emcon.get(ship, false)):
			for raw_model2 in (plan[ship] as Dictionary).keys():
				var model2 := String(raw_model2)
				if _sensor_exposes(ship, model2):
					(plan[ship] as Dictionary)[model2] = false
	for raw_ship2 in plan.keys():
		var ship2 := String(raw_ship2)
		if not _seconds_on.has(ship2):
			_seconds_on[ship2] = {}
		var on_map: Dictionary = plan[ship2]
		for raw_model3 in on_map.keys():
			var model3 := String(raw_model3)
			var on := bool(on_map[model3])
			var prev := float((_seconds_on[ship2] as Dictionary).get(model3, 0.0))
			(_seconds_on[ship2] as Dictionary)[model3] = (prev + FUSION_PERIOD_S) if on else 0.0
	sensor_on = plan
	# 开机事件写日志：第一次雷达开机（EMIT）
	if t >= radar_on_t and t - FUSION_PERIOD_S < radar_on_t:
		_push_log("远地点号 → 哈马丹：YW-R9 搜索雷达开机（EMIT 暴露）", "COMMAND", "EXEC")

func _sensor_exposes(ship: String, model: String) -> bool:
	var s := SensorModel.rack_sensor(ship, model)
	return bool(s.get("expose", false))

func _sensor_is_on(ship: String, model: String) -> bool:
	var m: Dictionary = sensor_on.get(ship, {})
	return bool(m.get(model, false))

func _sensor_due(ship: String, s: Dictionary, t: float) -> bool:
	var key := "%s|%s" % [ship, String(s.get("model", ""))]
	var last := float(_last_call.get(key, -1.0e9))
	return t - last >= float(s.get("refresh_s", 1.0)) - 1.0e-6

func _mark_sensor_call(ship: String, s: Dictionary, t: float) -> void:
	_last_call["%s|%s" % [ship, String(s.get("model", ""))]] = t

func _detect_ctx(ship: String, s: Dictionary, tr: Dictionary) -> Dictionary:
	var tgt_km: Vector3 = tr.get("cur_r", Vector3.ZERO)
	var los := SensorModel.line_of_sight_ok(Vector3.ZERO, tgt_km, EARTH_LOCAL_KM, R_EARTH_KM)
	var key := "%s|%s|%s" % [ship, String(s.get("model", "")), String(tr.get("id", ""))]
	return {
		"los": los,
		"sun_illum": SUN_ILLUM,
		"shadow": false,
		"has_bearing": true,
		"jamming": 0.0,
		"comms_jamming": 0.0,
		"rng": rng,
		"stare_s": float(_stare.get(key, 0.0)),
		"prev_bearing_deg": float(tr.get("bearing", -1.0)),
		"prev_dt_s": FUSION_PERIOD_S,
	}

# 把 track 的精确几何 + 舰元数据拼成 SensorModel 的 target 字典
func _make_target(tr: Dictionary) -> Dictionary:
	var ship := _ship_id_for_track(String(tr.get("id", "")))
	var km: Vector3 = tr.get("cur_r", Vector3.ZERO)
	var geo := SensorModel.bearing_range(km)
	var tgt := SensorModel.target_from_ship(ship, float(geo["range_km"]), float(geo["bearing_deg"]), {
		"radial_vel_kmps": float(tr.get("closing", 0.0)),
	})
	# 目标发射源按"目标自己的传感器开关"重算（无线电默认不发射）
	var ems: Array = []
	for raw in SensorModel.sensor_rack(ship):
		var s: Dictionary = raw
		var model := String(s.get("model", ""))
		if not _sensor_is_on(ship, model):
			continue
		var ty := String(s.get("type", ""))
		if ty == "ir" or ty == "elint" or ty == "radio" or ty == "lasercom":
			continue
		if ty == "optical" and String(s.get("subtype", "")) != "lidar":
			continue
		ems.append({
			"model": model, "type": ty, "on": true,
			"range_km": float(s.get("range_km", 0.0)),
			"lpi": bool(s.get("lpi", false)),
		})
	tgt["emissions"] = ems
	return tgt

func _fusion_tick(t: float) -> void:
	fusion_count += 1
	for tr in tracks:
		tr["occluded"] = false
		if not tr.has("stare"):
			tr["stare"] = {}
	# 本 tick 到期的传感器（按 refresh_s 节流；一次扫描覆盖所有目标）
	var due: Array = []
	for det in DETECTOR_SHIPS:
		for raw_s in SensorModel.sensor_rack(det):
			var s: Dictionary = raw_s
			if not _sensor_is_on(det, String(s.get("model", ""))):
				continue
			if not _sensor_due(det, s, t):
				continue
			due.append({"ship": det, "sensor": s})
	# 光学一次只凝视一个目标（05 §S-04：望远镜单目标；07 §3 先推一条到 L3）
	# SHADOW 生效时优先凝视被跟踪目标。
	if _optical_target == "" and shadow_target != "" and not _optical_done.has(shadow_target):
		_optical_target = shadow_target
	if _optical_target == "":
		for tr in tracks:
			if tr.get("own", false) or bool(tr.get("phantom", false)):
				continue
			if String(tr.get("side", "")) == "friend":
				continue
			if _optical_done.has(String(tr.get("id", ""))):
				continue
			_optical_target = String(tr.get("id", ""))
			break
	# 真实目标：全队传感器探测 → 融合
	for tr in tracks:
		if tr.get("phantom", false) or tr.get("own", false):
			continue
		var tgt := _make_target(tr)
		var obs_all: Array = []
		for raw in due:
			var det := String((raw as Dictionary).get("ship", ""))
			var s: Dictionary = (raw as Dictionary).get("sensor", {})
			var model := String(s.get("model", ""))
			var s_type := String(s.get("type", ""))
			if s_type == "elint":
				continue   # 05 §S-05：ELINT 出信号不出接触，不并入航迹融合（P1j）
			var is_telescope := s_type == "optical" and String(s.get("subtype", "")) != "lidar"
			if is_telescope and String(tr.get("id", "")) != _optical_target:
				continue
			var ctx := _detect_ctx(det, s, tr)
			var o: Dictionary = SensorModel.detect(s, tgt, ctx)
			var key := "%s|%s|%s" % [det, model, String(tr.get("id", ""))]
			if o.has("stare_s"):
				_stare[key] = float(o.get("stare_s", 0.0))
				tr["stare"] = {
					"progress": float(o.get("stare_progress", 0.0)),
					"stare_s": float(o.get("stare_s", 0.0)),
					"required_s": float(o.get("stare_required_s", 0.0)),
					"sensor": model,
					"owner": det,
				}
				if is_telescope and float(o.get("stare_progress", 0.0)) >= 0.999:
					_optical_done[String(tr.get("id", ""))] = true
					_optical_target = ""
			var reason := String(o.get("reason", ""))
			if reason.begins_with("occluded"):
				tr["occluded"] = true
			obs_all.append(o)
		var st: Dictionary = tr.get("sensor_track", {})
		st = SensorModel.update_track(st, obs_all, t, {"track_id": String(tr.get("id", ""))})
		st = SensorModel.age_track(st, t)
		tr["sensor_track"] = st
		_sync_track_from_sensor(tr, st)
	# 本 tick 的扫描完成，登记
	for raw in due:
		var it: Dictionary = raw
		_mark_sensor_call(String(it.get("ship", "")), it.get("sensor", {}), t)
	# 友军：数据链直接给 L4 身份（07：编队是己方链路，不靠 IFF）
	for tr in tracks:
		if tr.get("phantom", false):
			continue
		if String(tr.get("side", "")) == "friend":
			_apply_datalink_identity(tr)
	# 虚警 / 暴露 / ELINT
	_update_phantom(t)
	_update_emissions(t)
	sensor_note = _sensor_note(t)

func _sync_track_from_sensor(tr: Dictionary, st: Dictionary) -> void:
	tr["level"] = int(st.get("level", 1))
	tr["level_evidence"] = (st.get("level_evidence", {}) as Dictionary).duplicate(true)
	tr["covariance"] = (st.get("covariance", {}) as Dictionary).duplicate(true)
	tr["sources"] = (st.get("sources", []) as Array).duplicate()
	tr["range_band"] = String(st.get("range_band", ""))
	tr["obs_range_km"] = float(st.get("range_km", -1.0))
	tr["obs_bearing_deg"] = float(st.get("bearing_deg", -1.0))
	tr["iff_status"] = String(st.get("iff_status", ""))
	tr["age"] = float(st.get("age_s", 0.0))
	tr["stale"] = bool(st.get("stale", false))
	var cls: Dictionary = st.get("classification", {})
	if not cls.is_empty():
		tr["classification"] = cls.duplicate(true)
	var ident: Dictionary = st.get("identity", {})
	if not ident.is_empty():
		tr["id_info"] = ident.duplicate(true)
	var sig: Dictionary = st.get("signal", {})
	if not sig.is_empty():
		tr["signal"] = sig.duplicate(true)

func _apply_datalink_identity(tr: Dictionary) -> void:
	if tr.is_empty():
		return
	tr["level"] = 4
	tr["level_evidence"] = {1: clock, 2: clock, 3: clock, 4: clock}
	var ship := _ship_id_for_track(String(tr.get("id", "")))
	var info := SensorModel.ship_info(ship)
	if not info.is_empty():
		tr["identity"] = "friend"
		tr["id_info"] = {
			"name": String(info.get("name", tr.id)),
			"hull": String(info.get("hull", "")),
			"faction": String(info.get("faction", "")),
			"via": "datalink",
			"confidence": 1.0,
		}
		tr["classification"] = {
			"ship_class": String(info.get("ship_class", "")),
			"builder": String(info.get("builder", "")),
			"role": String(info.get("role", "")),
			"faction": String(info.get("faction", "")),
			"confidence": 1.0,
		}
		tr["iff_status"] = "friend"

func _update_phantom(t: float) -> void:
	phantom_true = t >= phantom_true_t
	var ph := track_by_id("9002")
	if ph.is_empty():
		return
	ph["level"] = 1
	ph["sources"] = ["CH-IR2"]
	ph["range_band"] = "UNKNOWN"
	ph["bearing"] = phantom_bearing
	if phantom_true and not bool(ph.get("false_alarm", false)):
		ph["false_alarm"] = true
		ph["cls"] = "虚警 / FALSE ALARM"
		ph["role"] = "残骸/反射 · 无实体"
		ph["notes"] = [
			"MS-IR9 交叉确认：该方位无回波",
			"CH-IR2 虚警（06 §4.3：虚警多，常把残骸当敌舰）",
		]
		_push_log("交叉确认：CH-IR2 虚警 · 方位 302°", "FALSE ALARM", "EXEC")
	elif not phantom_true:
		ph["cls"] = "CH-IR2 虚警候选"
		ph["role"] = "虚警候选 · 残骸/反射"

func _update_emissions(t: float) -> void:
	var merged := {
		"ship_id": "fleet", "emitters": [], "emission_level": 0.0,
		"exposed": false, "emcon": true, "warnings": [],
	}
	fleet_emissions = []
	for det in DETECTOR_SHIPS:
		var on_map: Dictionary = sensor_on.get(det, {})
		var sec_map: Dictionary = _seconds_on.get(det, {})
		var st := SensorModel.emission_state(det, {"on": on_map, "seconds_on": sec_map, "transmitting": []})
		st["owner"] = det
		fleet_emissions.append(st)
		if not bool(st.get("exposed", false)):
			continue
		merged["exposed"] = true
		merged["emcon"] = false
		merged["emission_level"] = maxf(float(merged["emission_level"]), float(st.get("emission_level", 0.0)))
		for raw in st.get("emitters", []):
			var em: Dictionary = (raw as Dictionary).duplicate(true)
			em["owner"] = det
			(merged["emitters"] as Array).append(em)
		for w in st.get("warnings", []):
			(merged["warnings"] as Array).append("[%s] %s" % [det, String(w)])
	emission = merged

	# 敌方 ELINT 截获我方发射器（07 §3：开机即暴露，被传唤级点名）
	elint_hits = []
	elint_named = false
	if bool(merged.get("exposed", false)) and _sensor_is_on("summons_4471", "ELINT"):
		var hostile := track_by_id("2001")
		# 几何占位：APSI 后方位置不在局部板内，用"对方 ELINT 距离足够近"的保守值
		var distance_km := 318.0
		if not hostile.is_empty():
			distance_km = maxf(50.0, float(hostile.get("range", 318.0)))
		for raw_em in merged.get("emitters", []):
			var em: Dictionary = raw_em
			var kind := String(em.get("kind", "elint"))
			if kind != "elint":
				continue
			var itc := SensorModel.elint_intercept(em, distance_km, float(em.get("seconds_on", 0.0)))
			if bool(itc.get("detected", false)):
				var hit := {
					"from": "2001",
					"owner": String(em.get("owner", "")),
					"model": String(em.get("model", "")),
					"distance_km": distance_km,
					"intercept_km": float(em.get("elint_range_km", 0.0)),
					"itc": itc,
				}
				elint_hits.append(hit)
				elint_named = true
				if elint_hits.size() == 1:
					_push_log("AV-4412 传唤者 ELINT 截获：%s 点名我方雷达" % String(em.get("model", "")), "EXPOSED", "RX")
	if elint_named:
		(merged["warnings"] as Array).append("AV-4412 传唤者 ELINT 已点名：我方雷达开机即暴露（07 §3）")
	emission = merged

func _sensor_note(t: float) -> String:
	var lv := [0, 0, 0, 0, 0]
	for tr in tracks:
		if bool(tr.get("phantom", false)):
			lv[1] += 1
			continue
		var l := clampi(int(tr.get("level", 1)), 0, 4)
		lv[l] += 1
	return "融合 %d Hz · L4 %d / L3 %d / L2 %d / L1 %d · %s" % [
		1, lv[4], lv[3], lv[2], lv[1],
		("辐射 " + ("已点名" if elint_named else "暴露")) if bool(emission.get("exposed", false)) else "电磁管制",
	]

func _push_log(text: String, arg: String, status: String) -> void:
	var sec := int(maxf(0.0, tau()))
	var tn := "T+%05.1f" % tau()
	log_lines.push_front({"t": tn, "text": text, "arg": arg, "status": status})
	while log_lines.size() > 6:
		log_lines.pop_back()

# ── P1e：传感器开关 / EMCON / 预览 / scenario ─────────

func set_sensor(ship_id: String, idx: int, on: bool) -> bool:
	var rack := SensorModel.sensor_rack(ship_id)
	if idx < 0 or idx >= rack.size():
		return false
	var model := String((rack[idx] as Dictionary).get("model", ""))
	if not sensor_override.has(ship_id):
		sensor_override[ship_id] = {}
	(sensor_override[ship_id] as Dictionary)[model] = on
	_plan_tick(tau())
	_update_emissions(tau())
	_push_log("%s %s %s" % [ship_id, model, "开机" if on else "关机"], "SWITCH", "EXEC")
	return true

func get_sensor_on(ship_id: String, idx: int) -> bool:
	var rack := SensorModel.sensor_rack(ship_id)
	if idx < 0 or idx >= rack.size():
		return false
	var s: Dictionary = rack[idx]
	var model := String(s.get("model", ""))
	var m: Dictionary = sensor_on.get(ship_id, {})
	return bool(m.get(model, bool(s.get("on", true))))

func set_emcon(ship_id: String, on: bool) -> void:
	emcon[ship_id] = on
	_plan_tick(tau())
	_update_emissions(tau())
	_push_log("%s EMCON %s" % [ship_id, "开启 · 发射类全关" if on else "解除"], "EMCON", "EXEC")

func is_emcon(ship_id: String) -> bool:
	return bool(emcon.get(ship_id, false))

# 预览：返回同结构命令（status=DRAFT）但不入队、不扣 Δv，plot 画 draft 节点
func preview_command(action: String, params: Dictionary = {}, target := "") -> Dictionary:
	if cmd_model == null:
		return {}
	var p := params.duplicate(true)
	p["budget_ms"] = unit_dv_ms
	return cmd_model.preview("哈马丹", action, target, p, tau())

func clear_preview() -> void:
	if cmd_model != null:
		cmd_model.clear_preview()

func _load_scenario() -> Dictionary:
	var candidates: Array = ["res://data/scenario_l1.json"]
	var base := ProjectSettings.globalize_path("res://")
	candidates.append(base.path_join("../data/scenario_l1.json").simplify_path())
	for raw_path in candidates:
		var path := String(raw_path)
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			scenario_source = path
			return parsed
	scenario_source = "fallback"
	return {}

func _apply_scenario_env() -> void:
	if scenario.is_empty():
		return
	if scenario.has("datum"):
		set_datum(String(scenario.get("datum", datum)))
	if scenario.has("timeline"):
		var tl: Dictionary = scenario.get("timeline", {})
		radar_on_t = float(tl.get("radar_on_t", radar_on_t))
		optical_on_t = float(tl.get("optical_on_t", optical_on_t))
		iff_on_t = float(tl.get("iff_on_t", iff_on_t))
		phantom_true_t = float(tl.get("phantom_true_t", phantom_true_t))
	if scenario.has("sensors"):
		var sc_sensors: Dictionary = scenario.get("sensors", {})
		for raw_ship in sc_sensors.keys():
			var ship := String(raw_ship)
			if not scenario_sensor_init.has(ship):
				scenario_sensor_init[ship] = {}
			for raw in (sc_sensors[ship] as Array):
				var e: Dictionary = raw
				(scenario_sensor_init[ship] as Dictionary)[String(e.get("model", ""))] = bool(e.get("on", true))
	if scenario.has("false_alarm"):
		var fa: Dictionary = scenario.get("false_alarm", {})
		phantom_bearing = float(fa.get("bearing_deg", phantom_bearing))

# 职责文案归一（role 只放职责；状态另放 notes/iff_status，见 docs/12 P0-9）
func _role_text(role: String) -> String:
	match role:
		"送达舰":
			return "送达"
		"民用 · 应答机故障":
			return "民用工作船"
		_:
			return role

func _build_tracks_from_scenario() -> void:
	var arr: Array = scenario.get("tracks", [])
	tracks = []
	var own_r := Vector3(2.0, -3.0, 0.0)
	var own_v := Vector3(0.22, -0.12, 0.03)
	own = {"r": own_r, "v": own_v}
	own_cur = {"r": own_r, "v": own_v}
	for raw in arr:
		var d: Dictionary = raw
		var r := _vec3_from_json(d.get("r", null), own_r)
		var v := _vec3_from_json(d.get("v", null), Vector3.ZERO)
		var off := _vec2_from_json(d.get("off", null), Vector2(16.0, 12.0))
		var tr := _track(
			String(d.get("id", "?")), String(d.get("en", "")), String(d.get("cls", "")),
			String(_role_text(String(d.get("role", "")))), String(d.get("side", "unknown")),
			int(d.get("level", 1)), r, v, float(d.get("age", 0.0)),
			bool(d.get("own", false)), off, bool(d.get("bearing_only", false)),
			String(d.get("name", "")), String(d.get("identity", "")))
		tracks.append(tr)
		if bool(d.get("own", false)):
			own = {"r": r, "v": v}
			own_cur = {"r": r, "v": v}

func _vec3_from_json(raw, fallback: Vector3) -> Vector3:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 3:
		var a: Array = raw
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback

func _vec2_from_json(raw, fallback: Vector2) -> Vector2:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		var a: Array = raw
		return Vector2(float(a[0]), float(a[1]))
	return fallback

# ── P1f：第一关闭环（三个阶段 / 决断 / 报告）─────────────────

func _load_story() -> void:
	story = scenario.get("story", {})
	if typeof(story) != TYPE_DICTIONARY:
		story = {}
	decision_t = float(story.get("decision_t", 75.0))
	decision_prompt = String(story.get("decision_prompt", "执行窗口剩余：交接 / 阻止 / 拖程序，选一个。"))
	consequence_text = String(story.get("consequence_fire", "谷神-2 被击毁（民用船）。ROE 违规。"))
	story_events = story.get("events", [])
	endings = []
	for raw in story.get("endings", []):
		var e: Dictionary = raw
		endings.append(e)
	var rep0: Dictionary = story.get("reputation", {})
	for k in rep0.keys():
		reputation[String(k)] = int(rep0[k])
	notice = (story.get("notice", {}) as Dictionary).duplicate(true)
	decision_replies = story.get("decision_replies", {})
	report_unit = String(story.get("report_unit", "AD 特遣群监督官"))
	report_event = String(story.get("report_event", "斛 · 第七号裁定接管通知"))
	report_evidence = String(story.get("report_evidence", "黑匣子、通信流、传感器日志。"))
	report_bodies = story.get("report_bodies", {})
	report_recommend = story.get("report_recommend", {})

func _update_phase_gate(t: float) -> void:
	if end_open:
		tut_phase = PHASE_END
		_update_freeze()
		return
	if report_open:
		tut_phase = PHASE_REPORT
		_update_freeze()
		return
	if consequence_open:
		tut_phase = PHASE_DECIDE
		_update_freeze()
		return
	if decision_open:
		tut_phase = PHASE_DECIDE
		decision_prompt = _fmt_decision_prompt()
		_update_freeze()
		return
	tut_phase = PHASE_READ if t < 20.0 else PHASE_COMMAND
	_update_freeze()
	if t >= decision_t or (exec_locked and exec_left <= 0.0):
		_open_decision()

# P1g：决断/后果/报告/END 真正冻结仿真（main 停 clock / exec_left）
func _update_freeze() -> void:
	sim_frozen = decision_open or consequence_open or report_open or end_open or fire_branch

func _open_decision() -> void:
	if decision_open or report_open or consequence_open or tut_phase == PHASE_END:
		return
	decision_open = true
	tut_phase = PHASE_DECIDE
	decision_prompt = _fmt_decision_prompt()
	_update_freeze()
	_push_log("决断窗口开启 · 三选一（或武器释放）", "裁决", "EXEC")

func story_text(key: String, fallback: String = "") -> String:
	var v = story.get(key, fallback)
	return String(v)

func ending_label(kind: String) -> String:
	match kind:
		"CERTIFY":
			return "认证交接"
		"ARTICLE9":
			return "援引第九条"
		"STALL":
			return "拖程序 / 文书复核"
		"FIRE":
			return "开火击毁"
		_:
			return kind

func phase_label() -> String:
	match tut_phase:
		PHASE_READ:
			return "读"
		PHASE_COMMAND:
			return "令"
		PHASE_DECIDE:
			return "裁决"
		PHASE_REPORT:
			return "报告"
		PHASE_END:
			return "归档"
		_:
			return tut_phase

func _rep_text() -> String:
	var parts: Array = []
	for k in reputation.keys():
		var v := int(reputation[k])
		if v != 0:
			parts.append("%s %+d" % [String(k), v])
	if parts.is_empty():
		return "无变化"
	return " · ".join(parts)

# 三种结局：写 outcome / 阵营声望 / 案卷 flag，打开报告
func choose_ending(kind: String) -> Dictionary:
	if not decision_open or report_open or consequence_open:
		return {}
	var k := kind.to_upper()
	match k:
		"CERTIFY", "A":
			outcome = "CERTIFY"
			flags["certify"] = true
			reputation["斛港务"] = int(reputation.get("斛港务", 0)) - 2
			reputation["清算署"] = int(reputation.get("清算署", 0)) + 2
		"ARTICLE9", "B":
			outcome = "ARTICLE9"
			flags["article9"] = true
			reputation["斛港务"] = int(reputation.get("斛港务", 0)) + 2
			reputation["清算署"] = int(reputation.get("清算署", 0)) - 2
		"STALL", "C":
			outcome = "STALL"
			flags["stall"] = true
			reputation["斛港务"] = int(reputation.get("斛港务", 0)) + 1
			reputation["清算署"] = int(reputation.get("清算署", 0)) - 1
		_:
			return {}
	decision_open = false
	report_open = true
	tut_phase = PHASE_REPORT
	_build_report_options()
	var reply: Dictionary = (decision_replies.get(outcome, {}) as Dictionary)
	if not reply.is_empty():
		_append_radio(String(reply.get("from", "远地点")), String(reply.get("to", "署方")),
			String(reply.get("mode", "LD")), String(reply.get("text", "")), tau())
	decision_prompt = ""
	_push_log("裁决：%s · 声望 %s" % [ending_label(outcome), _rep_text()], "OUTCOME", "EXEC")
	return {"outcome": outcome, "reputation": reputation.duplicate(true), "report_open": true}

# 开火分支：冻结时间、consequence、民用伤亡 / ROE 违规
func authorize_fire() -> Dictionary:
	if not decision_open or fire_branch:
		return {}
	fire_branch = true
	decision_open = false
	consequence_open = true
	sim_frozen = true
	outcome = "FIRE"
	flags["fire"] = true
	flags["roe_violation"] = true
	flags["civilian_casualties"] = true
	reputation["斛港务"] = int(reputation.get("斛港务", 0)) - 5
	reputation["远环合作社"] = int(reputation.get("远环合作社", 0)) - 3
	consequence_text = story_text("consequence_fire", consequence_text)
	_push_log("武器释放授权 → 谷神-2（民用）· ROE 违规", "FIRE", "HOLD")
	_push_log("时间冻结 · 审裁证据已封存", "CONSEQ", "HOLD")
	return {"fire_branch": true, "consequence_open": true, "frozen": true}

# 看完后果后进入报告（main 按 E 调）
func finish_consequence() -> void:
	if not consequence_open:
		return
	consequence_open = false
	report_open = true
	tut_phase = PHASE_REPORT
	_build_report_options()
	_update_freeze()

func _build_report_options() -> void:
	report_options = [{"kind": "TRUTH", "label": "据实报告", "hint": "完整记录交接/裁决过程，进入审裁档案"}]
	if fire_branch:
		report_options.append({"kind": "FAKE", "label": "淡化 / 伪造", "hint": "只在不希望被追责时可选 · perjury+1"})

# 报告：truth / fake；fake 增 perjury，第二次审计触发 audit_flag
func submit_report(kind: String) -> Dictionary:
	if not report_open:
		return {}
	var k := kind.to_upper()
	var truth := k != "FAKE"
	if not truth and not fire_branch:
		return {}
	var audit_before := audit_flag
	if not truth:
		perjury_count += 1
		flags["perjury"] = true
		audit_flag = true
		flags["audit_flag_%02d" % perjury_count] = true
		if perjury_count >= 2:
			flags["routine_audit"] = true
	report_choice = "TRUTH" if truth else "FAKE"
	report_open = false
	consequence_open = false
	tut_phase = PHASE_END
	report_text = _compose_report(truth)
	end_open = true
	end_summary = {
		"outcome": outcome,
		"ending": ending_label(outcome),
		"reputation": reputation.duplicate(true),
		"report_text": report_text,
		"report_choice": report_choice,
		"flags": flags.duplicate(true),
		"perjury_count": perjury_count,
		"audit_flag": audit_flag,
		"fire_branch": fire_branch,
		"window_used_s": maxf(0.0, 360.0 - exec_left),
		"t": tau(),
	}
	_update_freeze()
	_push_log("报告提交：%s%s" % ["据实" if truth else "伪造 · REPORT FILED — AUDIT FLAG %02d" % perjury_count, " · 例行审计" if perjury_count >= 2 and not audit_before else ""], "REPORT", "EXEC" if truth else "HOLD")
	return {"report": report_text, "audit_flag": audit_flag, "perjury_count": perjury_count, "phase": tut_phase, "end_open": end_open, "end_summary": end_summary.duplicate(true)}

func _compose_report(truth: bool) -> String:
	var body := ""
	var rec := ""
	if truth:
		body = String((report_bodies as Dictionary).get(outcome, ""))
		if body == "":
			body = String((story.get("report_truth", {}) as Dictionary).get(outcome, ""))
		rec = String((report_recommend as Dictionary).get(outcome, ""))
	else:
		body = String((story.get("report_fake", {}) as Dictionary).get(outcome, ""))
		if body == "":
			body = "未发现异常。"
		rec = "建议维持现有记录。"
	body = body.replace("{decision}", ending_label(outcome))
	var lines: Array[String] = [
		"舰队内部事后报告 / INTERNAL AFTER-ACTION",
		"报告单位：%s" % report_unit,
		"事件：%s" % report_event,
		"裁决：%s" % ending_label(outcome),
		"经过：%s" % body,
		"证据：%s" % report_evidence,
		"声望：%s" % _rep_text(),
		"建议：%s" % (rec if rec != "" else "—"),
	]
	if fire_branch:
		lines.append("备注：武器释放已执行；民用船只损失，ROE 审查启动。")
	if not truth:
		lines.append("备注：内部版本与黑匣子记录不一致（perjury=%d）。" % perjury_count)
	var out := ""
	for ln in lines:
		out += ("\n" if out != "" else "") + ln
	return out

# ── P1g：事件 / 无线电 feed、END、重开 ───────────────────

# scenario 的 events / radio_lines 按 t 触发，写入 event_feed / radio_feed，只触发一次
func _pump_feeds(t: float) -> void:
	var evs: Array = story.get("events", [])
	for i in range(evs.size()):
		var key := "ev:%d" % i
		if _feed_fired.has(key):
			continue
		var e: Dictionary = evs[i]
		if float(e.get("t", 1.0e9)) > t + 1.0e-6:
			continue
		_feed_fired[key] = true
		event_feed.append({
			"t": float(e.get("t", 0.0)),
			"type": String(e.get("type", "")),
			"text": String(e.get("text", "")),
		})
	var rds: Array = story.get("radio_lines", [])
	for i in range(rds.size()):
		var key2 := "rd:%d" % i
		if _feed_fired.has(key2):
			continue
		var raw = rds[i]
		var rr: Dictionary
		if raw is Dictionary:
			rr = raw
		else:
			rr = {"t": 0.0, "from": "VHF", "text": String(raw)}
		if float(rr.get("t", 1.0e9)) > t + 1.0e-6:
			continue
		_feed_fired[key2] = true
		var item := {
			"t": float(rr.get("t", 0.0)),
			"from": String(rr.get("from", "—")),
			"to": String(rr.get("to", "—")),
			"mode": String(rr.get("mode", "RDO")),
			"text": String(rr.get("text", "")),
		}
		radio_feed.append(item)
		link_mode = String(item["mode"])
		_push_log("[%s至%s]-[%s]-[%s]" % [item["from"], item["to"], item["mode"], item["text"]], String(item["mode"]), "RX")
		if String(item.get("from", "")).begins_with("AV-4412"):
			notice = {
				"title": "接管通知 · AV-4412 传唤者",
				"body": "[%s至%s]-[%s]-[%s]" % [item["from"], item["to"], item["mode"], item["text"]],
				"from": String(item["from"]), "to": String(item["to"]),
				"mode": String(item["mode"]), "t": float(item["t"]),
			}

func latest_radio(n: int = 1) -> Array:
	var out: Array = []
	var start := maxi(0, radio_feed.size() - n)
	for i in range(start, radio_feed.size()):
		out.append(radio_feed[i])
	return out

# 重置到 T+0 开局（重建 tracks / sensors / commands / feeds / 阶段/决断/END 全部状态）
func restart_demo() -> void:
	_reset_runtime()
	_bootstrap()
	_push_log("RESTART · 演示重置到 T+0 开局", "RESET", "EXEC")
	cmd_note = _cmd_note()

func _reset_runtime() -> void:
	datum = "L1"
	clock = T0
	time_scale = 60.0
	paused = false
	elapsed = 0.0
	selected = 0
	sensor = 0
	sensors.clear()
	boot_t = 0.0
	sensor_fx_t = -1.0
	fleet_dv = 8420
	grace_left = 62.0 * 3600.0 + 18.0 * 60.0 + 44.0
	exec_left = 360.0
	exec_locked = true
	tracks.clear()
	log_lines.clear()
	unit = {}
	own = {}
	own_cur = {}
	burn = {}
	cmd_model = null
	own_events = []
	unit_dv_ms = 1120.0
	unit_dv_max = 1260.0
	shadow_target = ""
	shadow_since = -1.0
	station_hold = false
	cmd_note = ""
	scenario = {}
	scenario_source = "fallback"
	sensor_override = {}
	emcon = {}
	phantom_bearing = 302.0
	radar_on_t = RADAR_ON_T
	optical_on_t = OPTICAL_ON_T
	iff_on_t = IFF_ON_T
	phantom_true_t = PHANTOM_TRUE_T
	tut_phase = PHASE_READ
	decision_open = false
	report_open = false
	consequence_open = false
	fire_branch = false
	outcome = ""
	report_text = ""
	report_options.clear()
	audit_flag = false
	perjury_count = 0
	reputation = {"斛港务": 0, "清算署": 0, "远环合作社": 0}
	sim_frozen = false
	decision_t = 75.0
	decision_prompt = ""
	consequence_text = ""
	report_choice = ""
	story = {}
	story_events = []
	endings.clear()
	flags = {}
	end_open = false
	end_summary = {}
	radio_feed = []
	event_feed = []
	_feed_fired = {}
	notice = {}
	decision_replies = {}
	report_unit = "AD 特遣群监督官"
	report_event = "斛 · 第七号裁定接管通知"
	report_evidence = "黑匣子、通信流、传感器日志与光学分类记录。"
	report_bodies = {}
	report_recommend = {}
	link_mode = "LD"
	scenario_sensor_init = {}
	tracks.clear()
	racks = {}
	sensor_on = {}
	rack_ship = "harmattan"
	emission = {}
	fleet_emissions = []
	elint_hits = []
	elint_named = false
	fusion_t = 0.0
	fusion_count = 0
	phantom_true = false
	sensor_note = ""
	rng = RandomNumberGenerator.new()
	_seconds_on = {}
	_last_call = {}
	_stare = {}
	_optical_target = ""
	_optical_done = {}
	_sensors_view_key = ""

# ── P1j：身份 / 通信格式 / 动态裁决提示 ─────────────────

func _default_identity(side: String) -> String:
	match side:
		"friend":
			return "friend"
		"hostile":
			return "unknown"
		_:
			return "pending"

# 六级身份中文（plot / hud 共用）
func identity_label(kind: String) -> String:
	match kind:
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
			return kind

func _fmt_mmss(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%02d:%02d" % [s / 60, s % 60]

func _fmt_decision_prompt() -> String:
	var tmpl := story_text("decision_prompt", decision_prompt)
	if tmpl.contains("{mm:ss}"):
		tmpl = tmpl.replace("{mm:ss}", _fmt_mmss(exec_left))
	return tmpl

# 通信：统一 [发信者至收信者]-[LD/LR/RDO/IR/VIS]-[内容] 四字段
func _append_radio(from_s: String, to_s: String, mode: String, text: String, t: float) -> void:
	link_mode = mode
	radio_feed.append({
		"t": t, "from": from_s, "to": to_s, "mode": mode, "text": text,
	})
	_push_log("[%s至%s]-[%s]-[%s]" % [from_s, to_s, mode, text], mode, "RX")

func _has_source(tr: Dictionary, model: String) -> bool:
	return (tr.get("sources", []) as Array).has(model)

# 身份迁移（19 §2.5）：敌方 2001 Unknown→Suspect（光学分类）；9001 Pending→Neutral（IFF/光学）；
# 9002 Pending→虚警；友军恒 Friend。IFF 不自动判敌。
func _update_identity(t: float) -> void:
	for tr in tracks:
		var id := String(tr.get("id", ""))
		var side := String(tr.get("side", ""))
		if bool(tr.get("own", false)) or side == "friend":
			tr["identity"] = "friend"
			continue
		if bool(tr.get("phantom", false)):
			tr["identity"] = "pending"
			continue
		var lvl := int(tr.get("level", 1))
		var cls: Dictionary = tr.get("classification", {})
		match id:
			"2001":
				if _has_source(tr, "MS-OT2"):
					if String(tr.get("identity", "")) != "suspect":
						tr["identity"] = "suspect"
						_push_log("身份更新：[2001] 未知 → 可疑（光学分类完成）", "IDENTITY", "RX")
				elif String(tr.get("identity", "")) != "unknown":
					tr["identity"] = "unknown"
			"9001":
				if _has_source(tr, "MS-OT2") or String(tr.get("iff_status", "")) != "":
					if String(tr.get("identity", "")) != "neutral":
						tr["identity"] = "neutral"
						_push_log("身份更新：[9001] 待定 → 中立（光学/IFF 确认）", "IDENTITY", "RX")
				elif String(tr.get("identity", "")) != "pending":
					tr["identity"] = "pending"
			"9002":
				tr["identity"] = "pending"
			_:
				pass

# ── 日志 / 单位面板 ────────────────────────────────────

func _build_log() -> void:
	log_lines = [
		{"t": "12:31.4", "text": "点火（BURN）哈马丹 → 节点 B-2", "arg": "Δv 84", "status": "PENDING"},
		{"t": "12:28.0", "text": "电磁管制 · 雷达关机", "arg": "", "status": "EXEC"},
		{"t": "12:19.3", "text": "武器释放授权请求 → AV-4412 传唤者（2001）", "arg": "ROE 拒绝", "status": "HOLD"},
		{"t": "12:04.8", "text": "传感器：红外 / 光学", "arg": "", "status": "EXEC"},
		{"t": "11:52.1", "text": "接收 接管通知 · AV-4412 传唤者（2001）", "arg": "", "status": "RX"}
	]

func _build_unit() -> void:
	unit = {
		"name": "哈马丹", "en": "HARMATTAN", "cls": "托盘-5 改", "role": "哨舰",
		"faction": "公约 · AD 特遣群",
		"mass": "300 t", "crew": "12", "accel": "0.15 g",
		"orbit": "L1 · 站位 斛", "inc": "—", "period": "—",
		"dv": _fmt_int(int(round(unit_dv_ms))), "dv_max": _fmt_int(int(round(unit_dv_max))),
		"systems": [["传感器", 0.74], ["火控", 0.42], ["推进", 0.66], ["通信", 0.82], ["反应堆", 0.95]],
		"weapons": [["CH-IR2 红外", "1 · 被动"], ["CH-R0 无线电", "1 · 4s"], ["武器释放", "无"]],
		"damage": "红外虚警偏高", "damage2": "· CH-IR2 校准中"
	}

