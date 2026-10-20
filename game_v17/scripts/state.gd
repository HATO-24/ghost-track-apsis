class_name WarState
extends RefCounted

# V17：V1 HUD 仍读本类字段；V2 数据桥可选接入（未接入时为 null）。
var framework = null

# —— V17-CORE-1：V2 数据桥归一字段（HUD/plot 只读；V15 原有字段不变）——
var fw_ready := false
var fw_tutorial: Dictionary = {}
var fw_flow: Dictionary = {}
var fw_damage: Dictionary = {}
var fw_replay: Dictionary = {}
var fw_actions: Array = []
var fw_contacts: Array = []
var fw_actions_target := ""
var fw_decision_reason := ""
var fw_decision_deferred := false
var fw_sync_count := 0
var fw_t := 0.0
var fw_last_action: Dictionary = {}
# —— R4-CORE-2：导航/交通管制/机动规划（V2NavigationModel 只读快照）——
var fw_nav: Dictionary = {}
var fw_nav_ready := false
var fw_nav_summary: Dictionary = {}
# —— R2-DAMAGE-2：完整损管模型只读暴露（旧 fw_damage 保持 legacy）——
var fw_damage_model := false          # 完整损管模型是否就绪
var fw_damage_full: Dictionary = {}   # world.vm_damage_full() 只读快照
# —— R6-SHADOW-1：CR3BP/RK4 物理 shadow 只读快照（authoritative=false）——
var fw_physics: Dictionary = {}
var fw_physics_ready := false
var fw_physics_summary: Dictionary = {}
var fw_physics_mode := "off"
# —— R6-AUTH-1：authoritative 物理适配层只读视图 / V15 对比 ——
var fw_physics_authoritative: Dictionary = {}
var fw_physics_adapter: Dictionary = {}
# —— R6-DISPLAY-CORE-1：物理显示数据接口（只读；给 plot 用）——
const PHYSICS_DISPLAY_ENV := "DSH_PHYSICS_DISPLAY"
var fw_physics_display: Dictionary = {}
# —— R5-SENSOR-BRIDGE-1：传感器 shadow 只读 advisory / compare ——
var fw_sensor_shadow: Dictionary = {}
var fw_sensor_shadow_ready := false
var fw_sensor_compare: Dictionary = {}
# —— R5-AUTHORITY-DISPLAY-1：V2 传感器权威显示层（显式 authoritative；默认 shadow 不写）——
var fw_sensor_authority := "legacy_v15"
var fw_sensor_authority_diff: Dictionary = {}
# —— R5-INFO-BRIDGE-1：信息作战 shadow 只读（IFF/ELINT/COMINT/EW）——
var fw_info_warfare: Dictionary = {}
var fw_info_warfare_ready := false
var fw_info_warfare_summary: Dictionary = {}
# —— R5-OPT-DOCK-BRIDGE-1 / R5-AUTO-SENSOR-1：光学/IR 与对接只读 VM + auto 开关 ——
var fw_optical_ir: Dictionary = {}
var fw_docking: Dictionary = {}
var fw_optical_ir_auto := false
var fw_docking_auto := false

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
var reputation: Dictionary = {"ocu": 0, "meridian": 0, "ueg_doves": 0, "outer": 0, "reclaimers": 0}
var sim_frozen := false
var decision_t := 300.0
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
var report_unit := "OCUVF-ID13 指挥官"
var report_event := "L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）"
var report_evidence := "传感器日志、命令队列、通信记录、港务与核查组黑匣子。"
var report_bodies: Dictionary = {}
var report_recommend: Dictionary = {}
var link_mode := "LD"
var scenario_sensor_init: Dictionary = {}   # scenario 传感器初始开关（非时序项）

# ── P2b：EXPOSE 取证 / 撤人 / 副官申请 ─────────────────
var evidence: Dictionary = {"port_telemetry": false, "inspection_blackbox": false, "elint_signature": false}
var evidence_tasks_def: Dictionary = {}
var evidence_tasks: Array = []
var civilians_evacuated := false
var adjutant_request: Dictionary = {}
var adjutant_request_open := false
var adjutant_request_seen := false
var _demo_tasks := false
var _demo_tasks_seeded := false

# ── V17-CORE-3：清算者无线电教学 / 传感器权威边界 ─────────
# 内容在 framework/content（V17 副本）；COMMAND 阶段手动触发，不自动完成。
const RECLAIMER_RADIO_PATH := "res://framework/content/reclaimer_radio_l1.json"
const RECLAIMER_RADIO_SCHEMA := "reclaimer_radio.v1"
const RECLAIMER_RADIO_MODES := ["LD", "LR", "RDO"]
const SENSOR_AUTHORITY_LEGACY := "legacy_v15"
const SENSOR_AUTHORITY_NOTE := "V15 sensor_model 决定接触等级/融合/威胁；V2 radar/TWS/optical 仅为数据/演示模型，V17 不切换、不伪造。"
var reclaimer_radio_content: Dictionary = {}
var reclaimer_radio_stage := "idle"        # idle / open / done
var reclaimer_radio_open := false
var reclaimer_radio_seen := false
var reclaimer_radio_started_t := -1.0
var reclaimer_radio_choice := ""
var reclaimer_radio_transcript: Array = []
var sensor_authority := SENSOR_AUTHORITY_LEGACY

# ── P3c：前置航行（L4 Hammer → L1 Meridian）────────────
var prelude_open := false
var prelude_step := 0            # 0 目的地 / 1 变轨窗口 / 2 点火确认 / 3 完成
var prelude_route := ""
var prelude_window := ""
var prelude_dv := 0.0
var prelude_data: Dictionary = {}
# ── P9a：选中舰数据 / 传感器桅杆 / 导航页 ─────────────
var mast_deployed: Dictionary = {}      # ship_id -> bool（默认伸出）
var mast_note := ""
var nav_data: Dictionary = {}
var _adjutant_choices: Array = []
# ── P10a：目标动作 / 光学红外通道 / 图层 / AV-4412 对接 ──
var target_menu_open := false
var target_menu_track := ""
var target_menu_actions: Array = []
var target_menu_hud_handled := false
var layer_visible: Dictionary = {
	"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true,
}
var track_channels: Dictionary = {}         # track_id -> {optical:{...}, ir:{...}}
var channel_last_t := -1.0
var av4412_dock: Dictionary = {"active": false, "state": "none", "target": "Chronos", "started_t": 0.0, "docked_t": 0.0}
var av4412_dock_text: Dictionary = {}
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
	if OS.get_environment("DSH_TASK") == "demo":
		_demo_tasks = true
	scenario = _load_scenario()
	_apply_scenario_env()
	_load_story()
	_load_reclaimer_radio()
	_init_mast()
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
	_update_identity(0.0)
	_update_threat(0.0)
	_prelude_init()
	if not prelude_open:
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
	var key := "%s#%s#%s" % [ship, str(racks.get(ship, [])), str(is_mast_deployed(ship))]
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
		_track("1000", "APSIS", "远地点级", "船坞舰", "friend", 4,
			_rel(300.0, 210.0, 55.0), Vector3(-0.050, -0.060, 0.010), 1.0, false, Vector2(10, -30), false, "远地点", "friend"),
		_track("1001", "HARMATTAN", "托盘-5 改", "哨舰", "friend", 4,
			own_r, own_v, 0.0, true, Vector2(16, 14), false, "哈马丹", "friend"),
		_track("1002", "FERRY", "赤铁-6 改", "炮舰", "friend", 4,
			_rel(332.0, 68.0, -4.0), Vector3(-0.0607, -0.0775, 0.0074), 1.0, false, Vector2(-72, -20), false, "渡口号", "friend"),
		_track("1003", "WATCHTOWER", "安海-1", "中继舰", "friend", 4,
			_rel(12.0, 96.0, 38.0), Vector3(-0.1174, 0.0250, 0.0200), 1.0, false, Vector2(16, -18), false, "望楼号", "friend"),
		_track("1004", "DEEPWELL", "月港-4", "油船", "friend", 4,
			_rel(60.0, 280.0, -26.0), Vector3(0.045, 0.060, -0.005), 1.0, false, Vector2(14, 12), false, "深井号", "friend"),
		_track("2001", "AV-4412", "传唤级", "通报舰", "hostile", 1,
			_rel(41.0, 318.0, 12.0), Vector3(-1.1683, -0.5067, -0.0634), 2.0, false, Vector2(26, -40), false, "AV-4412 传唤者", "unknown"),
		_track("9001", "CERES-2", "谷神改", "民用工作船", "unknown", 1,
			_rel(118.0, 260.0, -6.0), Vector3(0.0505, 0.0524, -0.0005), 12.0, false, Vector2(16, 12), false, "谷神-2", "pending"),
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

# CH-IR2 回波候选（07 §3 Phase 1「两条回波」：真目标是 AV-4412 传唤者，另一条是残骸/反射）。
# 没有真实实体：无 r/v、不发射、不预测；只有一条方位线。
func _build_phantom() -> void:
	var ch_ir2 := SensorModel.rack_sensor("harmattan", "CH-IR2")
	var fa := SensorModel.maybe_false_alarm(ch_ir2, {
		"false_alarm_scale": 100.0,   # 教学：强制掷出
		"false_bearing_deg": phantom_bearing,
	})
	var d := {
		"id": "9002", "batch": "9002", "name": "不明接触", "en": "UNKNOWN CONTACT", "cls": "CH-IR2 回波候选", "role": "待交叉确认", "identity": "pending", "threat": "pending", "threat_label": "待判定",
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
		"threat": "pending", "threat_label": "待判定",
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
	d["az_deg"] = d["bearing"]
	var horiz := sqrt(r.x * r.x + r.y * r.y)
	d["el_deg"] = rad_to_deg(atan2(r.z, maxf(horiz, 1.0e-6)))
	d["range_3d_km"] = rng_km
	d["speed_mps"] = v.length() * 1000.0
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
	if prelude_open:
		_push_log("前置航行未完成：无法下达战斗命令", "NAV", "HOLD")
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
	if prelude_open:
		if capture or OS.get_environment("DSH_SKIP_PRELUDE") == "1":
			prelude_skip()
		else:
			paused = true
			clock = T0
			return
	var t := now - T0
	_update_phase_gate(t)
	_pump_feeds(t)
	_seed_demo_tasks(t)
	_advance_tasks(t)
	_advance_channels(t)
	_advance_av4412_dock(t)
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
	_update_threat(t)

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
		# 清算者（2001 AV-4412 传唤者）：ELINT 与无线电接收常开；雷达保持静默
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
	# P9a：桅杆收起时整架不可用（主动/被动全部关断）
	for raw_ship_m in plan.keys():
		var ship_m := String(raw_ship_m)
		if not is_mast_deployed(ship_m):
			for raw_model_m in (plan[ship_m] as Dictionary).keys():
				(plan[ship_m] as Dictionary)[String(raw_model_m)] = false
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
	if not is_mast_deployed(ship):
		return false
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
		ph["false_alarm"] = true   # 内部仍记 false_alarm；对外主标签改为“无威胁目标”
		ph["name"] = "无威胁目标"
		ph["cls"] = "已交叉确认 · 无威胁"
		ph["role"] = "残骸/反射"
		ph["threat"] = "none"
		ph["threat_label"] = "无威胁"
		ph["notes"] = [
			"MS-IR9 交叉确认：该方位无回波",
			"残骸/反射 · 无实体 · 无威胁",
		]
		_push_log("交叉确认：9002 无威胁目标 · 残骸/反射 · 方位 302°", "NO THREAT", "EXEC")
	elif not phantom_true:
		ph["name"] = "不明接触"
		ph["cls"] = "CH-IR2 回波候选"
		ph["role"] = "待交叉确认"
		ph["threat"] = "pending"
		ph["threat_label"] = "待判定"

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
	if not is_mast_deployed(ship_id):
		_push_log("传感器桅杆已收起：%s 不可操作" % ship_id, "MAST", "HOLD")
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
	if not is_mast_deployed(ship_id):
		return false
	var s: Dictionary = rack[idx]
	var model := String(s.get("model", ""))
	var m: Dictionary = sensor_on.get(ship_id, {})
	return bool(m.get(model, bool(s.get("on", true))))

func set_emcon(ship_id: String, on: bool) -> void:
	emcon[ship_id] = on
	_plan_tick(tau())
	_update_emissions(tau())
	_push_log("%s EMCON %s" % [ship_id, "开启 · 进入电磁管制" if on else "解除"], "EMCON", "EXEC")

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
	decision_t = float(story.get("decision_t", 300.0))
	decision_prompt = String(story.get("decision_prompt", "指挥官，执行窗口剩余 {mm:ss}。请抉择。"))
	consequence_text = String(story.get("consequence_fire", "武器释放授权已下达；交火导致 Chronos 储罐区二次火灾，平民伤亡 12 人。"))
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
	report_unit = String(story.get("report_unit", "OCUVF-ID13 指挥官"))
	report_event = String(story.get("report_event", "L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）"))
	report_evidence = String(story.get("report_evidence", "传感器日志、命令队列、通信记录、港务与核查组黑匣子。"))
	report_bodies = story.get("report_bodies", {})
	report_recommend = story.get("report_recommend", {})
	evidence_tasks_def = story.get("evidence_tasks", {})
	adjutant_request = (story.get("adjutant_request", {}) as Dictionary).duplicate(true)
	prelude_data = (story.get("prelude", {}) as Dictionary).duplicate(true)
	nav_data = (story.get("navigation", {}) as Dictionary).duplicate(true)
	av4412_dock_text = (story.get("av4412_dock", {}) as Dictionary).duplicate(true)

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
	if tut_phase == PHASE_COMMAND and not adjutant_request_seen:
		adjutant_request_seen = true
		adjutant_request_open = true
		_push_log("副官建议：Chronos 取证/撤离（派遣穿梭机）", "ADJUTANT", "RX")
	_update_freeze()
	if t >= decision_t or (exec_locked and exec_left <= 0.0):
		_open_decision()

# P1g：决断/后果/报告/END 真正冻结仿真（main 停 clock / exec_left）
func _update_freeze() -> void:
	sim_frozen = decision_open or consequence_open or report_open or end_open or fire_branch or prelude_open

func _open_decision() -> void:
	if decision_open or report_open or consequence_open or tut_phase == PHASE_END:
		return
	# V17：V2 教学门控 —— 关键识别未完成时阻塞 V15 决策，不自动完成识别；
	# 玩家用 fw_perform_action/目标动作补完后，fw_sync 会自动打开（见 fw_sync）。
	if not fw_tutorial_allows():
		if not fw_decision_deferred:
			fw_decision_deferred = true
			fw_decision_reason = fw_decision_gate_reason()
			if fw_decision_reason == "":
				fw_decision_reason = "教学门控：关键识别未完成"
			_push_log(fw_decision_reason, "教学门控", "WARN")
		return
	decision_open = true
	fw_decision_deferred = false
	fw_decision_reason = ""
	tut_phase = PHASE_DECIDE
	decision_prompt = _fmt_decision_prompt()
	_update_freeze()
	_push_log("决断窗口开启", "抉择", "EXEC")
	# V17：同步到 V2 数据后端（教学门控已通过；失败不阻塞 V15）
	if framework != null and bool(framework.ready):
		framework.open_decision()
		_fw_pull()

func story_text(key: String, fallback: String = "") -> String:
	var v = story.get(key, fallback)
	return String(v)

func ending_label(kind: String) -> String:
	match kind:
		"HOLD":
			return "坚守 / HOLD"
		"EVACUATE":
			return "人员撤离 / EVACUATE"
		"EXPOSE":
			return "证据曝光 / EXPOSE"
		"FIRE":
			return "开火 / FIRE"
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

func _rep_label(key: String) -> String:
	match key:
		"ocu":
			return "OCU/OCJC"
		"meridian":
			return "Meridian"
		"ueg_doves":
			return "UEG 鸽派"
		"outer":
			return "外环"
		"reclaimers":
			return "清算者"
		_:
			return key

func _rep_text() -> String:
	var parts: Array = []
	for k in reputation.keys():
		var v := int(reputation[k])
		if v != 0:
			parts.append("%s %+d" % [_rep_label(String(k)), v])
	if parts.is_empty():
		return "无变化"
	return " · ".join(parts)

# 三种默认结局（HOLD / EVACUATE / EXPOSE）：写 outcome / 五对象声望 / flags，打开内部报告
func choose_ending(kind: String) -> Dictionary:
	if not decision_open or report_open or consequence_open:
		return {}
	var k := kind.to_upper()
	match k:
		"HOLD", "A":
			outcome = "HOLD"
			flags["hold"] = true
			reputation["ocu"] = int(reputation.get("ocu", 0)) + 2
			reputation["meridian"] = int(reputation.get("meridian", 0)) + 1
			reputation["ueg_doves"] = int(reputation.get("ueg_doves", 0)) + 1
			reputation["reclaimers"] = int(reputation.get("reclaimers", 0)) - 2
		"EVACUATE", "B":
			outcome = "EVACUATE"
			flags["evacuate"] = true
			reputation["ocu"] = int(reputation.get("ocu", 0)) + 1
			reputation["meridian"] = int(reputation.get("meridian", 0)) + 2
			reputation["ueg_doves"] = int(reputation.get("ueg_doves", 0)) + 1
			reputation["outer"] = int(reputation.get("outer", 0)) + 1
			reputation["reclaimers"] = int(reputation.get("reclaimers", 0)) - 1
			_start_av4412_dock("evacuate")
		"EXPOSE", "C":
			if not can_expose():
				_push_log("选项不可用：证据不足（%d/3，需至少 2 项）" % evidence_count(), "GATE", "HOLD")
				return {}
			outcome = "EXPOSE"
			flags["expose"] = true
			flags["ghost_track_evidence"] = true
			reputation["ocu"] = int(reputation.get("ocu", 0)) + 1
			reputation["ueg_doves"] = int(reputation.get("ueg_doves", 0)) + 2
			reputation["reclaimers"] = int(reputation.get("reclaimers", 0)) - 3
		_:
			return {}
	decision_open = false
	report_open = true
	tut_phase = PHASE_REPORT
	_build_report_options()
	var reply: Dictionary = (decision_replies.get(outcome, {}) as Dictionary)
	if not reply.is_empty():
		_append_radio(String(reply.get("from", "远地点号")), String(reply.get("to", "OCJC / OCUVF")),
			String(reply.get("mode", "LD")), String(reply.get("text", "")), tau())
	decision_prompt = ""
	_push_log("抉择：%s · 声望 %s" % [ending_label(outcome), _rep_text()], "OUTCOME", "EXEC")
	_fw_mirror_choice(outcome)
	return {
		"outcome": outcome,
		"reputation": reputation.duplicate(true),
		"standing": reputation.duplicate(true),
		"report_open": true,
	}

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
	flags["weapons_release"] = true
	flags["disaster"] = true
	flags["roe_violation"] = true
	flags["civilian_casualties"] = true
	reputation["ocu"] = int(reputation.get("ocu", 0)) - 1
	reputation["meridian"] = int(reputation.get("meridian", 0)) - 2
	reputation["ueg_doves"] = int(reputation.get("ueg_doves", 0)) - 2
	reputation["outer"] = int(reputation.get("outer", 0)) - 1
	reputation["reclaimers"] = int(reputation.get("reclaimers", 0)) + 1
	consequence_text = story_text("consequence_fire", consequence_text)
	if civilians_evacuated:
		flags["civilians_evacuated"] = true
		consequence_text += "\nID13 已提前撤出 Chronos 值勤人员与家属；平民伤亡显著减少。"
	var reply: Dictionary = (decision_replies.get("FIRE", {}) as Dictionary)
	if not reply.is_empty():
		_append_radio(String(reply.get("from", "远地点号")), String(reply.get("to", "全队")),
			String(reply.get("mode", "LD")), String(reply.get("text", "")), tau())
	_push_log("武器释放授权 → 2001 · 灾难分支", "FIRE", "HOLD")
	_push_log("时间冻结 · 记录封存", "CONSEQ", "HOLD")
	_fw_mirror_choice("FIRE")
	return {"fire_branch": true, "consequence_open": true, "frozen": true, "standing": reputation.duplicate(true)}

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
	report_options = [{"kind": "TRUTH", "label": "据实报告", "hint": "完整记录裁决与经过，进入 OCJC/OCUVF 内部档案"}]
	if fire_branch:
		report_options.append({"kind": "FAKE", "label": "淡化 / 伪造", "hint": "只在试图逃离追责时可选 · perjury+1"})

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
		"standing": reputation.duplicate(true),
		"ghost_track_evidence": bool(flags.get("ghost_track_evidence", false)),
		"av4412_dock": av4412_dock.duplicate(true),
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
	_fw_mirror_report(truth)
	return {"report": report_text, "audit_flag": audit_flag, "perjury_count": perjury_count, "phase": tut_phase, "end_open": end_open, "end_summary": end_summary.duplicate(true)}

func _compose_report(truth: bool) -> String:
	var body := ""
	var rec := ""
	if truth:
		body = String((report_bodies as Dictionary).get(outcome, ""))
		rec = String((report_recommend as Dictionary).get(outcome, ""))
	else:
		body = String((story.get("report_fake", {}) as Dictionary).get(outcome, ""))
		if body == "":
			body = "未发现异常。"
		rec = "建议按程序归档。"
	body = body.replace("{decision}", ending_label(outcome))
	var lines: Array[String] = [
		"OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION",
		"报告单位：%s" % report_unit,
		"事件：%s" % report_event,
		"裁决：%s" % ending_label(outcome),
		"经过：%s" % body,
		"证据：%s" % report_evidence,
		"声望：%s" % _rep_text(),
		"建议：%s" % (rec if rec != "" else "—"),
	]
	if av4412_dock.get("active", false):
		var dock_line := String(av4412_dock_text.get("report_line", "")).strip_edges()
		if dock_line == "":
			dock_line = "2001 AV-4412 传唤者已进入 Chronos 对接（%s）。" % String(av4412_dock.get("state", ""))
		lines.append("后续：%s" % dock_line)
	if fire_branch:
		lines.append("备注：武器释放已执行；ID13 被定性为未登记武装，进入调查程序。")
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
				"title": "第七号令接管声明 · AV-4412 传唤者",
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
	fw_restart()
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
	reputation = {"ocu": 0, "meridian": 0, "ueg_doves": 0, "outer": 0, "reclaimers": 0}
	sim_frozen = false
	decision_t = 300.0
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
	report_unit = "OCUVF-ID13 指挥官"
	report_event = "L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）"
	report_evidence = "传感器日志、命令队列、通信记录、港务与核查组黑匣子。"
	report_bodies = {}
	report_recommend = {}
	link_mode = "LD"
	scenario_sensor_init = {}
	evidence = {"port_telemetry": false, "inspection_blackbox": false, "elint_signature": false}
	evidence_tasks_def = {}
	evidence_tasks = []
	civilians_evacuated = false
	adjutant_request = {}
	adjutant_request_open = false
	adjutant_request_seen = false
	_demo_tasks = false
	_demo_tasks_seeded = false
	prelude_open = false
	prelude_step = 0
	prelude_route = ""
	prelude_window = ""
	prelude_dv = 0.0
	prelude_data = {}
	mast_deployed = {}
	mast_note = ""
	nav_data = {}
	_adjutant_choices = []
	reclaimer_radio_content = {}
	reclaimer_radio_stage = "idle"
	reclaimer_radio_open = false
	reclaimer_radio_seen = false
	reclaimer_radio_started_t = -1.0
	reclaimer_radio_choice = ""
	reclaimer_radio_transcript = []
	sensor_authority = SENSOR_AUTHORITY_LEGACY
	target_menu_open = false
	target_menu_track = ""
	target_menu_actions = []
	target_menu_hud_handled = false
	layer_visible = {"contacts": true, "labels": true, "predictions": true, "radar": true, "stations": true, "grid": true}
	track_channels = {}
	channel_last_t = -1.0
	av4412_dock = {"active": false, "state": "none", "target": "Chronos", "started_t": 0.0, "docked_t": 0.0}
	av4412_dock_text = {}
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
	# R4-CORE-2 / R2-DAMAGE-2：桥接派生字段复位（framework 由 fw_restart 重建快照）
	fw_nav = {}
	fw_nav_ready = false
	fw_nav_summary = {}
	fw_damage_model = false
	fw_damage_full = {}
	fw_physics = {}
	fw_physics_ready = false
	fw_physics_summary = {}
	fw_physics_mode = "off"
	fw_physics_authoritative = {}
	fw_physics_adapter = {}
	fw_physics_display = {}
	fw_sensor_shadow = {}
	fw_sensor_shadow_ready = false
	fw_sensor_compare = {}
	fw_sensor_authority = "legacy_v15"
	fw_sensor_authority_diff = {}
	fw_info_warfare = {}
	fw_info_warfare_ready = false
	fw_info_warfare_summary = {}
	fw_optical_ir = {}
	fw_docking = {}
	fw_optical_ir_auto = false
	fw_docking_auto = false

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

# ── P1k：威胁等级 ───────────────────────────────────────
# threat: none / low / medium / high / hostile / pending
func threat_text(kind: String) -> String:
	match kind:
		"none":
			return "无威胁"
		"low":
			return "低"
		"medium":
			return "中"
		"high":
			return "高"
		"hostile":
			return "敌对"
		"pending":
			return "待判定"
		_:
			return kind

# 威胁映射（P1k）：友军/9001 = none；2001 = high；9002 = none（交叉确认后）；未判定 = pending
func _update_threat(t: float) -> void:
	for tr in tracks:
		var id := String(tr.get("id", ""))
		var ident := String(tr.get("identity", ""))
		var threat := "pending"
		if bool(tr.get("own", false)) or ident == "friend":
			threat = "none"
		elif bool(tr.get("phantom", false)):
			threat = "none" if bool(tr.get("false_alarm", false)) else "pending"
		elif id == "2001":
			# 按身份走：Unknown 时待判定，光学分类成 Suspect 后才高威胁
			threat = "high" if (ident == "suspect" or ident == "hostile") else "pending"
		elif id == "9001":
			threat = "none"
		elif ident == "neutral":
			threat = "none"
		elif ident == "suspect":
			threat = "high"
		elif ident == "hostile":
			threat = "hostile"
		elif ident == "assumed_friend":
			threat = "low"
		var prev := String(tr.get("threat", ""))
		tr["threat"] = threat
		tr["threat_label"] = threat_text(threat)
		if prev != "" and prev != threat and (id == "2001" or id == "9002"):
			_push_log("威胁更新：[%s] %s → %s" % [id, threat_text(prev), threat_text(threat)], "THREAT", "RX")

# ── P2b：EXPOSE 证据 / 取证任务 / 撤人 / 副官申请 ───────

func evidence_count() -> int:
	var n := 0
	for k in evidence.keys():
		if bool(evidence[k]):
			n += 1
	return n

func can_expose() -> bool:
	return evidence_count() >= 2

func evidence_label(kind: String) -> String:
	match kind:
		"port_telemetry":
			return "港务遥测"
		"inspection_blackbox":
			return "核查组黑匣子"
		"elint_signature":
			return "异常特征码"
		"evacuation":
			return "撤出人员"
		_:
			return kind

func _task_def(kind: String) -> Dictionary:
	var def: Dictionary = evidence_tasks_def.get(kind, {})
	if def.is_empty():
		var durs := {"port_telemetry": 30.0, "inspection_blackbox": 75.0, "elint_signature": 45.0, "evacuation": 60.0}
		def = {
			"label": evidence_label(kind),
			"duration": float(durs.get(kind, 30.0)),
			"shuttle": kind == "inspection_blackbox" or kind == "evacuation",
		}
	return def

func _tasks_allowed() -> bool:
	if prelude_open or decision_open or consequence_open or report_open or end_open:
		return false
	return tut_phase == PHASE_COMMAND

func _shuttle_busy() -> bool:
	for raw in evidence_tasks:
		var tk: Dictionary = raw
		if String(tk.get("status", "")) == "RUNNING" and bool(tk.get("shuttle", false)):
			return true
	return false

func _has_task(kind: String) -> bool:
	for raw in evidence_tasks:
		var tk: Dictionary = raw
		if String(tk.get("kind", "")) == kind and String(tk.get("status", "")) == "RUNNING":
			return true
	return false

func _new_task(kind: String) -> Dictionary:
	var def := _task_def(kind)
	var task := {
		"kind": kind,
		"label": String(def.get("label", evidence_label(kind))),
		"duration": float(def.get("duration", 30.0)),
		"started_t": tau(),
		"progress": 0.0,
		"status": "RUNNING",
		"shuttle": bool(def.get("shuttle", false)),
		"risk": String(def.get("risk", "")),
	}
	evidence_tasks.append(task)
	return task

func start_evidence_task(kind: String) -> Dictionary:
	var k := kind.to_lower()
	if not _tasks_allowed():
		_push_log("当前阶段无法派取证任务", "TASK", "HOLD")
		return {}
	if k == "evacuation":
		return start_evacuation()
	if not evidence.has(k):
		return {}
	if bool(evidence[k]):
		_push_log("证据已取得：%s" % evidence_label(k), "TASK", "HOLD")
		return {}
	if _has_task(k):
		return {}
	var def := _task_def(k)
	if bool(def.get("shuttle", false)) and _shuttle_busy():
		_push_log("穿梭机占用：同一时间只能执行一项穿梭机任务", "TASK", "HOLD")
		return {}
	var task := _new_task(k)
	_push_log(String(def.get("start_text", "开始取证：%s" % task.label)), "TASK", "EXEC")
	_append_radio("远地点号", "Chronos 港务" if not bool(task.shuttle) else "ID13 穿梭机", "RDO", String(def.get("start_text", task.label)), tau())
	return task

func start_evacuation() -> Dictionary:
	if not _tasks_allowed():
		_push_log("当前阶段无法派撤人任务", "TASK", "HOLD")
		return {}
	if civilians_evacuated:
		_push_log("Chronos 人员已撤离", "TASK", "HOLD")
		return {}
	if _has_task("evacuation"):
		return {}
	if _shuttle_busy():
		_push_log("穿梭机占用：同一时间只能执行一项穿梭机任务", "TASK", "HOLD")
		return {}
	var def := _task_def("evacuation")
	var task := _new_task("evacuation")
	_push_log(String(def.get("start_text", "开始撤离 Chronos 人员")), "TASK", "EXEC")
	_append_radio("远地点号", "Chronos 港务", "RDO", String(def.get("start_text", "开始撤离 Chronos 人员")), tau())
	return task

func _advance_tasks(t: float) -> void:
	for raw in evidence_tasks:
		var tk: Dictionary = raw
		if String(tk.get("status", "")) != "RUNNING":
			continue
		var dur := maxf(1.0, float(tk.get("duration", 30.0)))
		var elapsed := t - float(tk.get("started_t", t))
		tk["progress"] = clampf(elapsed / dur, 0.0, 1.0)
		if elapsed < dur:
			continue
		tk["status"] = "DONE"
		tk["progress"] = 1.0
		tk["finished_t"] = t
		var kind := String(tk.get("kind", ""))
		var def := _task_def(kind)
		if kind == "evacuation":
			civilians_evacuated = true
			flags["civilians_evacuated"] = true
			_start_av4412_dock("civilians_evacuated")
		else:
			evidence[kind] = true
		_push_log(String(def.get("done_text", "任务完成：%s" % tk.label)), "TASK", "EXEC")
		_append_radio("远地点号", "全队", "LD", String(def.get("done_text", tk.label)), t)

func ack_adjutant(choice: String) -> Dictionary:
	if not adjutant_request_open:
		return {}
	var c := choice.to_lower()
	var task: Dictionary = {}
	match c:
		"telemetry":
			task = start_evidence_task("port_telemetry")
		"blackbox":
			task = start_evidence_task("inspection_blackbox")
		"evacuate":
			task = start_evacuation()
		"decline":
			adjutant_request_open = false
			adjutant_request_seen = true
			_push_log("副官申请：暂不处理", "ADJUTANT", "HOLD")
			return {"choice": c, "task": task, "adjutant_request_open": false}
		_:
			return {}
	_adjutant_choices.append(c)
	# P9a：非 decline 保留申请，允许连续选择（遥测可与穿梭机任务并行）
	adjutant_request_open = true
	adjutant_request_seen = true
	return {"choice": c, "task": task, "adjutant_request_open": true,
		"choices": _adjutant_choices.duplicate()}

# 截图演示：按时间线预置“遥测已完成 + 黑匣子进行中”，供 p2b-sim 截图
func _seed_demo_tasks(t: float) -> void:
	if not _demo_tasks or _demo_tasks_seeded:
		return
	_demo_tasks_seeded = true
	var tel := start_evidence_task("port_telemetry")
	if not tel.is_empty():
		tel["started_t"] = 20.0
	var bb := start_evidence_task("inspection_blackbox")
	if not bb.is_empty():
		bb["started_t"] = 50.0
	adjutant_request_open = false
	adjutant_request_seen = true

# ── P3c：前置航行（Hammer → Meridian）────────────────────

func _prelude_init() -> void:
	if prelude_data.is_empty():
		prelude_open = false
		return
	prelude_open = true
	prelude_step = 0
	prelude_route = ""
	prelude_window = ""
	prelude_dv = 0.0
	paused = true
	if OS.get_environment("DSH_SKIP_PRELUDE") == "1":
		prelude_skip()

func _prelude_route_def(id: String) -> Dictionary:
	for raw in prelude_data.get("routes", []):
		var r: Dictionary = raw
		if String(r.get("id", "")) == id:
			return r
	return {}

func _prelude_window_def(id: String) -> Dictionary:
	for raw in prelude_data.get("windows", []):
		var w: Dictionary = raw
		if String(w.get("id", "")) == id:
			return w
	return {}

func prelude_choose_route(id: String) -> Dictionary:
	if not prelude_open or prelude_step > 1:
		return {}
	var r := _prelude_route_def(id)
	if r.is_empty():
		return {}
	var hint := String(r.get("hint", ""))
	if not bool(r.get("ok", false)):
		_push_log("前置航行：%s —— %s" % [String(r.get("label", id)), hint], "NAV", "HOLD")
		return {"ok": false, "hint": hint, "step": prelude_step}
	prelude_route = id
	prelude_step = 1
	_push_log("前置航行：目的地 = %s" % String(r.get("label", id)), "NAV", "EXEC")
	return {"ok": true, "route": id, "step": prelude_step}

func prelude_choose_window(id: String) -> Dictionary:
	if not prelude_open or prelude_step != 1:
		return {}
	var w := _prelude_window_def(id)
	if w.is_empty():
		return {}
	var hint := String(w.get("hint", ""))
	if not bool(w.get("ok", false)):
		_push_log("前置航行：%s —— %s" % [String(w.get("label", id)), hint], "NAV", "HOLD")
		return {"ok": false, "hint": hint, "step": prelude_step}
	prelude_window = id
	var r := _prelude_route_def(prelude_route)
	prelude_dv = float(r.get("dv_ms", 0.0)) + float(w.get("dv_ms", 0.0))
	prelude_step = 2
	_push_log("前置航行：变轨窗口 = %s；预计 Δv %.0f m/s" % [String(w.get("label", id)), prelude_dv], "NAV", "EXEC")
	return {"ok": true, "window": id, "dv_ms": prelude_dv, "step": prelude_step}

func prelude_confirm() -> Dictionary:
	if not prelude_open:
		return {}
	if prelude_step != 2:
		return {"ok": false, "reason": "prelude_step"}
	return prelude_execute()

func prelude_execute() -> Dictionary:
	if not prelude_open:
		return {}
	var r := _prelude_route_def(prelude_route)
	var w := _prelude_window_def(prelude_window)
	if r.is_empty() or w.is_empty() or not bool(r.get("ok", false)) or not bool(w.get("ok", false)):
		_push_log("前置航行：目的地或窗口未确认", "NAV", "HOLD")
		return {"ok": false, "reason": "prelude_invalid"}
	prelude_dv = float(r.get("dv_ms", 0.0)) + float(w.get("dv_ms", 0.0))
	unit_dv_ms = maxf(0.0, unit_dv_ms - prelude_dv)
	fleet_dv = maxi(0, fleet_dv - int(round(prelude_dv)))
	unit["dv"] = _fmt_int(int(round(unit_dv_ms)))
	flags["prelude_done"] = true
	flags["prelude_route"] = prelude_route
	flags["prelude_window"] = prelude_window
	prelude_open = false
	prelude_step = 3
	if not capture:
		clock = T0
		paused = false
	_push_log(String(prelude_data.get("execute_text", "点火执行；ID13 进入转移轨道。")), "NAV", "EXEC")
	for raw in prelude_data.get("done_comm", []):
		var c: Dictionary = raw
		_append_radio(String(c.get("from", "—")), String(c.get("to", "—")), String(c.get("mode", "RDO")),
			String(c.get("text", "")), tau())
	return {"ok": true, "open": false, "step": 3, "dv_ms": prelude_dv,
		"route": prelude_route, "window": prelude_window}

# 静默完成（截图/自动化）：不扣 Δv、不写通信，避免影响既有截图
func prelude_skip() -> Dictionary:
	if not prelude_open:
		return {}
	for raw in prelude_data.get("routes", []):
		var r: Dictionary = raw
		if bool(r.get("ok", false)):
			prelude_route = String(r.get("id", ""))
			break
	for raw2 in prelude_data.get("windows", []):
		var w: Dictionary = raw2
		if bool(w.get("ok", false)):
			prelude_window = String(w.get("id", ""))
			break
	prelude_open = false
	prelude_step = 3
	if not capture:
		clock = T0
		paused = false
	flags["prelude_skipped"] = true
	return {"ok": true, "open": false, "skipped": true,
		"route": prelude_route, "window": prelude_window}

# ── P9a：桅杆 / 选中舰 / 相对轨道读数 / 导航页 ─────────

func _init_mast() -> void:
	mast_deployed = {}
	for raw_ship in SensorModel.all_racks().keys():
		mast_deployed[String(raw_ship)] = true
	mast_note = "桅杆：全部伸出"

func is_mast_deployed(ship_id: String) -> bool:
	return bool(mast_deployed.get(ship_id, true))

func set_mast(ship_id: String, deployed: bool) -> bool:
	if not SensorModel.all_racks().has(ship_id):
		return false
	if bool(mast_deployed.get(ship_id, true)) == deployed:
		return true
	mast_deployed[ship_id] = deployed
	if not deployed:
		# 收起：清掉手动覆盖，_plan_tick 会整架强制关断；伸出后恢复脚本时序
		sensor_override.erase(ship_id)
	mast_note = "桅杆：%s %s" % [ship_id, "伸出" if deployed else "收起 · 传感器不可用"]
	_plan_tick(tau())
	_update_emissions(tau())
	_sync_sensor_view()
	_push_log("传感器桅杆 %s：%s" % [ship_id, "伸出" if deployed else "收起"], "MAST", "EXEC")
	return true

func toggle_mast(ship_id: String) -> bool:
	return set_mast(ship_id, not is_mast_deployed(ship_id))

func selected_track() -> Dictionary:
	if tracks.is_empty():
		return {}
	var idx := clampi(int(selected), 0, tracks.size() - 1)
	return tracks[idx]

func datum_note() -> String:
	var tr := selected_track()
	if tr.is_empty() or bool(tr.get("own", false)):
		return "基准锁本舰 / OWN FRAME"
	return "基准锁本舰（选中舰只读）/ OWN FRAME · SELECTED READ-ONLY"

func selected_info() -> Dictionary:
	var tr := selected_track()
	if tr.is_empty():
		return {}
	var id := String(tr.get("id", ""))
	var closing_ms := float(tr.get("closing", 0.0)) * 1000.0
	return {
		"id": id,
		"batch": String(tr.get("batch", id)),
		"name": String(tr.get("name", id)),
		"own": bool(tr.get("own", false)),
		"identity": identity_label(String(tr.get("identity", "pending"))),
		"threat": threat_text(String(tr.get("threat", "none"))),
		"az_deg": float(tr.get("az_deg", tr.get("bearing", 0.0))),
		"el_deg": float(tr.get("el_deg", 0.0)),
		"range_km": float(tr.get("range_3d_km", tr.get("range", 0.0))),
		"speed_mps": float(tr.get("speed_mps", 0.0)),
		"closing_mps": closing_ms,
		"orbit": orbit_readout(id),
	}

# 相对轨道读数：以本舰为原点的运动学估算；不是地心根数（绝对根数需星历，第二批）
func orbit_readout(id: String) -> Dictionary:
	var tr := track_by_id(id)
	if tr.is_empty():
		return {"available": false, "note": "无该批号"}
	if bool(tr.get("own", false)):
		return {"available": false, "scheme": "station", "label": "本舰 · 基准",
			"note": "本舰是基准舰；绝对轨道根数由外部星历提供（第二批）"}
	var r: Vector3 = tr.get("cur_r", Vector3.ZERO)
	var v: Vector3 = tr.get("cur_v", Vector3.ZERO)
	var rng := r.length()
	if rng <= 0.001:
		return {"available": false, "note": "无位置解（L1 方位线）"}
	var spd := v.length()
	var radial := r.dot(v) / maxf(rng, 1.0e-6)
	var tang := sqrt(maxf(spd * spd - radial * radial, 0.0))
	var period_est := (TAU * rng / tang) if tang > 1.0e-6 else 0.0
	var h := r.cross(v)
	var inc := 0.0
	if h.length() > 1.0e-9:
		inc = rad_to_deg(asin(clampf(h.normalized().z, -1.0, 1.0)))
	return {
		"available": true,
		"scheme": "relative",
		"label": "相对轨道（本舰为原点；非地心根数）",
		"semi_major_km": rng,
		"period_s": period_est,
		"inc_deg": absf(inc),
		"speed_mps": spd * 1000.0,
		"radial_mps": radial * 1000.0,
		"tangential_mps": tang * 1000.0,
		"closing_mps": -radial * 1000.0,
		"note": "运动学估算；绝对轨道根数需星历（第二批）",
	}

func navigation_open() -> bool:
	return prelude_open

func navigation_step() -> int:
	return prelude_step

func navigation_stage() -> String:
	match prelude_step:
		0:
			return "目的地 / DESTINATION"
		1:
			return "变轨窗口 / WINDOW"
		2:
			return "点火确认 / CONFIRM"
		3:
			return "航行 / TRANSIT"
		_:
			return "—"

func navigation_steps() -> Array:
	var st = nav_data.get("stages", null)
	if st is Array:
		return st
	return ["目的地", "变轨窗口", "点火确认", "航行"]

func navigation_tutorial() -> String:
	return String(nav_data.get("tutorial", ""))

# ── P10a：目标动作 / 光学红外通道 / 图层 / AV-4412 对接 ──

const TARGET_ACTION_CATALOG := [
	{"id": "crossfix", "label": "交叉定位", "min": 1},
	{"id": "radar_illum", "label": "雷达照射识别", "min": 1},
	{"id": "model_ident", "label": "型号识别", "min": 2},
	{"id": "radar_track", "label": "雷达跟踪", "min": 3},
	{"id": "iff_query", "label": "IFF 问答", "min": 3},
	{"id": "optical_channel", "label": "光学通道", "min": 3},
	{"id": "ir_channel", "label": "红外通道", "min": 3},
	{"id": "fire_control", "label": "火控解算", "min": 4},
	{"id": "missile_path", "label": "导弹路径解算", "min": 4},
	{"id": "armed_standby", "label": "武装待命", "min": 4},
]

func track_level(track_id: String) -> int:
	var tr := track_by_id(track_id)
	if tr.is_empty():
		return 0
	return clampi(int(tr.get("level", 0)), 0, 4)

func select_track_by_id(track_id: String) -> bool:
	for i in range(tracks.size()):
		if String((tracks[i] as Dictionary).get("id", "")) == track_id:
			selected = i
			return true
	return false

func _channel_sensor_ready(kind: String) -> bool:
	for raw_ship in racks.keys():
		var ship := String(raw_ship)
		if not is_mast_deployed(ship):
			continue
		for raw_s in SensorModel.sensor_rack(ship):
			var sen: Dictionary = raw_s
			var ty := String(sen.get("type", ""))
			var ok_type := (ty == "optical" and kind == "optical") or (ty == "ir" and kind == "ir")
			if not ok_type:
				continue
			var model := String(sen.get("model", ""))
			if bool((sensor_on.get(ship, {}) as Dictionary).get(model, false)):
				return true
	return false

func target_actions(track_id: String) -> Array:
	var tr := track_by_id(track_id)
	if tr.is_empty():
		return []
	var lv := track_level(track_id)
	var out: Array = []
	for raw in TARGET_ACTION_CATALOG:
		var def: Dictionary = raw
		var aid := String(def.get("id", ""))
		var min_lv := int(def.get("min", 1))
		var ok := lv >= min_lv
		var unsupported := aid in ["fire_control", "missile_path", "armed_standby"]
		var reason := ""
		if not ok:
			reason = "需 L%d 识别（当前 L%d）" % [min_lv, lv]
		elif unsupported:
			reason = "未实现：本作尚无武器系统（第二批）"
		elif aid == "optical_channel" and not _channel_sensor_ready("optical"):
			ok = false
			reason = "无可用光学通道（传感器关机/桅杆收起）"
		elif aid == "ir_channel" and not _channel_sensor_ready("ir"):
			ok = false
			reason = "无可用红外通道（传感器关机/桅杆收起）"
		elif aid == "radar_illum" and not _channel_sensor_ready("radar") and not SensorModel.rack_sensor("harmattan", "YW-R9").is_empty():
			pass
		out.append({
			"id": aid, "label": String(def.get("label", aid)), "min_level": min_lv,
			"level": lv, "available": ok and not unsupported, "unsupported": unsupported,
			"reason": reason,
		})
	return out

func open_target_menu(track_id: String) -> Array:
	var tr := track_by_id(track_id)
	if tr.is_empty():
		target_menu_open = false
		target_menu_track = ""
		target_menu_actions = []
		return []
	select_track_by_id(track_id)
	target_menu_open = true
	target_menu_track = track_id
	target_menu_actions = target_actions(track_id)
	target_menu_hud_handled = false
	_push_log("目标菜单：[%s] %s · L%d · %d 项" % [String(tr.get("batch", track_id)), String(tr.get("name", "")), track_level(track_id), target_menu_actions.size()], "MENU", "EXEC")
	return target_menu_actions

func close_target_menu() -> void:
	target_menu_open = false
	target_menu_track = ""
	target_menu_actions = []

func perform_target_action(track_id: String, action: String) -> Dictionary:
	var acts := target_actions(track_id)
	var found: Dictionary = {}
	for raw in acts:
		var a: Dictionary = raw
		if String(a.get("id", "")) == action:
			found = a
			break
	if found.is_empty():
		return {"ok": false, "status": "error", "track_id": track_id, "action": action, "message": "未知动作或目标不存在"}
	if bool(found.get("unsupported", false)):
		return {"ok": false, "status": "unsupported", "track_id": track_id, "action": action, "message": String(found.get("reason", "未实现"))}
	if not bool(found.get("available", false)):
		return {"ok": false, "status": "unavailable", "track_id": track_id, "action": action, "message": String(found.get("reason", "当前不可用"))}
	var tr := track_by_id(track_id)
	var msg := ""
	match action:
		"crossfix":
			tr["crossfix_t"] = tau()
			flags["crossfix_%s" % track_id] = true
			msg = "交叉定位完成（基于现有被动传感器方位）"
		"radar_illum":
			if not is_mast_deployed("harmattan") or not set_sensor("harmattan", 0, true):
				return {"ok": false, "status": "error", "track_id": track_id, "action": action, "message": "哈马丹雷达不可用（桅杆/传感器状态）"}
			tr["radar_illum_t"] = tau()
			msg = "雷达照射识别：YW-R9 已开机（EMIT 暴露）"
		"model_ident":
			tr["classification_confirmed"] = true
			msg = "型号识别已确认（写入该批号分类状态）"
		"radar_track":
			tr["tracking"] = true
			tr["tracking_since"] = tau()
			msg = "雷达跟踪已建立（状态标记；TWS 状态机第二批）"
		"iff_query":
			tr["iff_queried"] = true
			if String(tr.get("iff_status", "")) == "":
				tr["iff_status"] = "queried_no_response"
			msg = "IFF 问答已发出（无应答时仅到“不明/可疑”，不能自动判敌）"
		"optical_channel":
			var ro := start_optical_track(track_id)
			if not bool(ro.get("ok", false)):
				return ro
			msg = "光学通道已建立（凝视中）"
		"ir_channel":
			var ri := start_ir_track(track_id)
			if not bool(ri.get("ok", false)):
				return ri
			msg = "红外通道已建立（跟踪中）"
		_:
			return {"ok": false, "status": "unsupported", "track_id": track_id, "action": action, "message": "未实现"}
	flags["action_%s_%s" % [action, track_id]] = true
	_push_log("目标动作 %s → [%s]：%s" % [action, track_id, msg], "ACTION", "EXEC")
	# V17：同一动作镜像到 V2 数据桥，教学门控/任务状态以 V2 为准；
	# V15 自己的视觉/日志仍保留。武器类在 V15 已 unsupported，不会到这里。
	if framework != null and bool(framework.ready):
		var fw_action := action
		if fw_action == "missile_path":
			fw_action = "missile_solve"
		elif fw_action == "armed_standby":
			fw_action = "weapons_hold"
		var fw_res: Dictionary = fw_perform_action(fw_action, track_id)
		fw_last_action = fw_res
		fw_sync(0.0)
	return {"ok": true, "status": "ok", "track_id": track_id, "action": action, "message": msg,
		"level": track_level(track_id), "actions": acts}

# ── 光学 / 红外通道 ────────────────────────────────────

func start_optical_track(track_id: String, elapsed_s := 0.0) -> Dictionary:
	return _start_channel(track_id, "optical", 6.0, elapsed_s)

func start_ir_track(track_id: String, elapsed_s := 0.0) -> Dictionary:
	return _start_channel(track_id, "ir", 4.0, elapsed_s)

func _start_channel(track_id: String, kind: String, required_s: float, elapsed_s: float) -> Dictionary:
	var tr := track_by_id(track_id)
	if tr.is_empty():
		return {"ok": false, "status": "error", "message": "无该批号"}
	if track_level(track_id) < 2:
		return {"ok": false, "status": "error", "message": "需 L2（有距离解）才可建立通道"}
	if not _channel_sensor_ready(kind):
		return {"ok": false, "status": "error", "message": "%s通道不可用（传感器/桅杆）" % ("光学" if kind == "optical" else "红外")}
	var ch: Dictionary = track_channels.get(track_id, {})
	if ch.is_empty():
		track_channels[track_id] = {}
	var entry := {
		"kind": kind,
		"status": "running",
		"started_t": tau() - maxf(0.0, elapsed_s),
		"required_s": required_s,
		"progress": clampf(elapsed_s / required_s, 0.0, 0.999),
		"elapsed_s": elapsed_s,
	}
	(track_channels[track_id] as Dictionary)[kind] = entry
	if channel_last_t < 0.0:
		channel_last_t = tau()
	_push_log("%s通道启动：[%s] %s" % ["光学" if kind == "optical" else "红外", track_id, String(tr.get("name", ""))], "CHANNEL", "EXEC")
	return {"ok": true, "status": "running", "track_id": track_id, "kind": kind, "channel": entry.duplicate(true)}

func stop_track() -> Dictionary:
	var stopped: Array = []
	for raw_id in track_channels.keys():
		var tid := String(raw_id)
		var ch: Dictionary = track_channels[tid]
		for kind in ch.keys():
			var e: Dictionary = ch[kind]
			if String(e.get("status", "")) == "running":
				e["status"] = "stopped"
				stopped.append("%s:%s" % [tid, String(kind)])
	track_channels.clear()
	_push_log("通道停止：%s" % ("无" if stopped.is_empty() else ", ".join(stopped)), "CHANNEL", "HOLD")
	return {"ok": true, "stopped": stopped, "status": "stopped"}

func channel_status(track_id := "") -> Dictionary:
	if track_id != "":
		return {"track_id": track_id, "channels": (track_channels.get(track_id, {}) as Dictionary).duplicate(true)}
	var active: Array = []
	for raw_id in track_channels.keys():
		var ch: Dictionary = track_channels[raw_id]
		for k in ch.keys():
			if String((ch[k] as Dictionary).get("status", "")) == "running":
				active.append(String(raw_id))
				break
	return {"active_tracks": active, "channels": track_channels.duplicate(true)}

func _advance_channels(t: float) -> void:
	if track_channels.is_empty():
		return
	if channel_last_t < 0.0:
		channel_last_t = t
	for raw_id in track_channels.keys():
		var tid := String(raw_id)
		var ch: Dictionary = track_channels[tid]
		for kind in ch.keys():
			var e: Dictionary = ch[kind]
			if String(e.get("status", "")) != "running":
				continue
			var elapsed := t - float(e.get("started_t", t))
			var req := maxf(0.1, float(e.get("required_s", 6.0)))
			e["elapsed_s"] = elapsed
			e["progress"] = clampf(elapsed / req, 0.0, 1.0)
			if elapsed >= req:
				e["status"] = "locked"
				e["locked_t"] = t
				var tr := track_by_id(tid)
				if not tr.is_empty():
					(tr as Dictionary)["%s_locked" % String(kind)] = true
				_push_log("%s通道锁定：[%s]" % ["光学" if String(kind) == "optical" else "红外", tid], "CHANNEL", "EXEC")
	channel_last_t = t

# ── 图层显隐 ──────────────────────────────────────────

func _layer_key(name: String) -> String:
	match name.to_lower():
		"contact", "contacts", "track", "tracks":
			return "contacts"
		"label", "labels", "text":
			return "labels"
		"prediction", "predictions", "orbit", "orbits", "history":
			return "predictions"
		"radar", "sensor", "sensors", "emit", "elint":
			return "radar"
		"station", "stations", "site", "sites", "chronos":
			return "stations"
		"grid", "grids":
			return "grid"
		_:
			return name.to_lower()

func set_layer_visible(name: String, on: bool) -> bool:
	var k := _layer_key(name)
	if not layer_visible.has(k):
		return false
	layer_visible[k] = on
	_push_log("图层 %s：%s" % [k, "显示" if on else "隐藏"], "LAYER", "EXEC")
	return true

func is_layer_visible(name: String) -> bool:
	return bool(layer_visible.get(_layer_key(name), true))

func toggle_layer(name: String) -> bool:
	var k := _layer_key(name)
	if not layer_visible.has(k):
		return false
	return set_layer_visible(k, not bool(layer_visible[k]))

# ── AV-4412 与 Chronos 对接（EVACUATE 后） ─────────────

func _start_av4412_dock(reason: String) -> void:
	if bool(av4412_dock.get("active", false)):
		return
	av4412_dock = {"active": true, "state": "approach", "target": "Chronos",
		"started_t": tau(), "docked_t": 0.0, "reason": reason}
	flags["av4412_dock"] = true
	flags["chronos_handover"] = true
	var tr := track_by_id("2001")
	if not tr.is_empty():
		(tr as Dictionary)["dock_state"] = "approach"
		(tr as Dictionary)["dock_target"] = "Chronos"
	var txt := String(av4412_dock_text.get("approach_text", "2001 AV-4412 传唤者进入 Chronos 对接航道。"))
	_push_log(txt, "DOCK", "EXEC")
	_append_radio("接管官 科尔", "远地点号", "RDO", txt, tau())

func _advance_av4412_dock(t: float) -> void:
	if not bool(av4412_dock.get("active", false)):
		return
	if String(av4412_dock.get("state", "")) != "approach":
		return
	var wait_s := float(av4412_dock_text.get("approach_after_s", 45.0))
	if t - float(av4412_dock.get("started_t", t)) < wait_s:
		return
	av4412_dock["state"] = "docked"
	av4412_dock["docked_t"] = t
	flags["av4412_docked"] = true
	var tr := track_by_id("2001")
	if not tr.is_empty():
		(tr as Dictionary)["dock_state"] = "docked"
	var txt2 := String(av4412_dock_text.get("docked_text", "2001 AV-4412 传唤者已与 Chronos 对接，接管程序完成。"))
	_push_log(txt2, "DOCK", "EXEC")
	_append_radio("接管官 科尔", "远地点号", "RDO", txt2, t)

# DSH/测试：强制推进对接（不伪造几何，只写状态）
func force_av4412_dock() -> Dictionary:
	_start_av4412_dock("debug")
	av4412_dock["state"] = "docked"
	av4412_dock["docked_t"] = tau()
	flags["av4412_docked"] = true
	var tr := track_by_id("2001")
	if not tr.is_empty():
		(tr as Dictionary)["dock_state"] = "docked"
	return av4412_dock.duplicate(true)

func av4412_dock_state() -> Dictionary:
	return av4412_dock.duplicate(true)

# ── 日志 / 单位面板 ────────────────────────────────────

func _build_log() -> void:
	log_lines = [
		{"t": "12:31.4", "text": "点火（BURN）哈马丹 → 节点 B-2", "arg": "Δv 84", "status": "PENDING"},
		{"t": "12:28.0", "text": "电磁管制 · 雷达关机", "arg": "", "status": "EXEC"},
		{"t": "12:19.3", "text": "武器释放授权请求 → AV-4412 传唤者（2001）", "arg": "ROE 拒绝", "status": "HOLD"},
		{"t": "12:04.8", "text": "传感器：红外 / 光学", "arg": "", "status": "EXEC"},
		{"t": "11:52.1", "text": "接收 第七号令接管声明 · AV-4412 传唤者（2001）", "arg": "", "status": "RX"}
	]

func _build_unit() -> void:
	unit = {
		"name": "哈马丹", "en": "HARMATTAN", "cls": "托盘-5 改", "role": "哨舰",
		"faction": "OCUVF · ID13",
		"mass": "300 t", "crew": "12", "accel": "0.15 g",
		"orbit": "L1 Meridian-05 Chronos", "inc": "—", "period": "—",
		"dv": _fmt_int(int(round(unit_dv_ms))), "dv_max": _fmt_int(int(round(unit_dv_max))),
		"systems": [["传感器", 0.74], ["火控", 0.42], ["推进", 0.66], ["通信", 0.82], ["反应堆", 0.95]],
		"weapons": [["CH-IR2 红外", "1 · 被动"], ["CH-R0 无线电", "1 · 4s"], ["武器释放", "无"]],
		"damage": "红外虚警偏高", "damage2": "· CH-IR2 校准中"
	}

# ═══════════════════════════════════════════════════════════════════
# V17-CORE-1：V2 数据桥归一字段 / 封装（HUD/plot 只读；V15 原有流程不变）
#
# 归一字段（每帧 fw_sync 刷新）：
#   fw_ready        bool            framework 就绪
#   fw_tutorial     Dictionary      world.vm_tutorial()（教学门控）
#   fw_flow         Dictionary      world.vm_flow()（prelude/decision/report/end/exec/reputation/damage/replay）
#   fw_damage       Dictionary      world.vm_damage()（损管 sections/queue/summary）
#   fw_replay       Dictionary      world.vm_replay()（回放帧列表，只读）
#   fw_contacts     Array           10 条接触（V2 归一；V15 tracks 仍独立保留）
#   fw_actions      Array           当前选中目标可用动作（available/reason/reason_code）
#   fw_actions_target String        当前 fw_actions 对应批号
#   fw_decision_reason String       V15 决策被教学门控阻塞的原因（"" = 未阻塞）
#   fw_decision_deferred bool       决策已到点但被门控挂起
#   fw_t / fw_sync_count             V2 世界时间 / 同步次数
#
# 写操作（HUD 只调这些，不要直接改 V2 world）：
#   fw_perform_action / fw_start_repair / fw_apply_damage
#   fw_open_decision / fw_choose_ending / fw_submit_report / fw_evidence_start
#   fw_replay_start / fw_replay_pause / fw_replay_stop / fw_replay_seek / fw_replay_frame
#   fw_restart / fw_sync
# ═══════════════════════════════════════════════════════════════════

## 每帧由 main._process 在 state.refresh() 之后调用；dt 为真实帧时间。
func fw_sync(dt: float) -> void:
	if framework == null:
		fw_ready = false
		return
	var step := 0.0
	if not paused and not sim_frozen and not capture:
		step = maxf(0.0, dt) * maxf(0.0, time_scale)
	framework.sync(step)
	_fw_pull()
	_fw_update_physics_adapter()
	_fw_update_sensor_compare()
	_fw_apply_sensor_authority_display()
	# 决策挂起：V15 决策窗口已到但教学未完成 → 完成后自动打开（不自动完成识别）
	if fw_decision_deferred and not decision_open and not report_open and not consequence_open \
			and fw_tutorial_allows():
		fw_decision_deferred = false
		fw_decision_reason = ""
		_open_decision()
	# 选中目标变化时刷新 fw_actions
	var batch := fw_selected_batch()
	if batch != fw_actions_target:
		fw_actions_target = batch
		framework.set_actions_target(batch)
		fw_actions = (framework.actions as Array).duplicate(true)

func _fw_pull() -> void:
	if framework == null or not bool(framework.ready):
		fw_ready = false
		fw_tutorial = {}
		fw_flow = {}
		fw_damage = {}
		fw_replay = {}
		fw_contacts = []
		fw_actions = []
		fw_t = 0.0
		fw_nav = {}
		fw_nav_ready = false
		fw_nav_summary = {}
		fw_damage_model = false
		fw_damage_full = {}
		fw_physics = {}
		fw_physics_ready = false
		fw_physics_summary = {}
		fw_physics_mode = "off"
		fw_physics_authoritative = {}
		fw_physics_adapter = {}
		fw_physics_display = {}
		fw_sensor_shadow = {}
		fw_sensor_shadow_ready = false
		fw_sensor_compare = {}
		fw_sensor_authority = "legacy_v15"
		fw_sensor_authority_diff = {}
		fw_info_warfare = {}
		fw_info_warfare_ready = false
		fw_info_warfare_summary = {}
		fw_optical_ir = {}
		fw_docking = {}
		fw_optical_ir_auto = false
		fw_docking_auto = false
		return
	fw_ready = true
	fw_tutorial = (framework.tutorial_view() as Dictionary).duplicate(true)
	fw_flow = (framework.flow_view() as Dictionary).duplicate(true)
	fw_damage = (framework.damage_view() as Dictionary).duplicate(true)
	fw_replay = (framework.replay_view() as Dictionary).duplicate(true)
	fw_contacts = (framework.contacts_view() as Array).duplicate(true)
	fw_actions = (framework.actions as Array).duplicate(true)
	fw_t = float(framework.synced_t)
	fw_sync_count += 1
	fw_decision_reason = String(framework.decision_gate_reason())
	# R4-CORE-2 / R2-DAMAGE-2：导航与完整损管只读快照
	fw_nav_ready = bool(framework.nav_ready)
	fw_nav = (framework.navigation_view() as Dictionary).duplicate(true)
	fw_nav_summary = (framework.navigation_summary() as Dictionary).duplicate(true)
	fw_damage_model = bool(framework.damage_model_ready)
	fw_damage_full = (framework.damage_full_view() as Dictionary).duplicate(true)
	# R6-SHADOW-1：物理 shadow 只读快照
	fw_physics_ready = bool(framework.physics_ready)
	fw_physics_mode = String(framework.physics_mode)
	fw_physics = (framework.physics_view() as Dictionary).duplicate(true)
	fw_physics_summary = (framework.physics_summary() as Dictionary).duplicate(true)
	fw_physics_authoritative = (framework.physics_authoritative_view() as Dictionary).duplicate(true)
	fw_physics_display = physics_display_frame()
	# R5-SENSOR-BRIDGE-1：传感器 shadow 只读快照（compare 在 fw_sync 里用 state.tracks 生成）
	fw_sensor_shadow_ready = bool(framework.sensor_shadow_ready)
	fw_sensor_shadow = (framework.sensor_shadow_view() as Dictionary).duplicate(true)
	# R5-INFO-BRIDGE-1：信息作战 shadow 只读快照
	fw_info_warfare_ready = bool(framework.info_warfare_ready)
	fw_info_warfare = (framework.info_warfare_view() as Dictionary).duplicate(true)
	fw_info_warfare_summary = (framework.info_warfare_summary() as Dictionary).duplicate(true)
	# R5-OPT-DOCK-BRIDGE-1 / R5-AUTO-SENSOR-1：光学/IR + 对接只读 VM（auto 每帧刷新）
	fw_optical_ir = (framework.optical_ir_view() as Dictionary).duplicate(true)
	fw_docking = (framework.docking_view() as Dictionary).duplicate(true)
	fw_optical_ir_auto = bool(framework.optical_ir_auto_enabled)
	fw_docking_auto = bool(framework.docking_auto_enabled)

## R6-AUTH-1：用当前 V15 board 数据生成物理对比（只读；显示层尚未切换）。
## 未就绪/关闭时清空，不报错、不写 V15。
func _fw_update_physics_adapter() -> void:
	fw_physics_adapter = {}
	if framework == null or not bool(framework.ready):
		return
	if not bool(framework.physics_ready):
		return
	if not (String(framework.physics_mode) in ["shadow", "authoritative"]):
		return
	var t_now := tau()
	var own_state: Dictionary = own_at(t_now)
	var rows: Array = []
	for raw in tracks:
		var tr: Dictionary = raw
		if bool(tr.get("own", false)):
			continue
		var bpos: Vector3 = board_pos(tr, t_now)
		var bvel: Vector3 = board_vel(tr, t_now)
		rows.append({
			"track_id": String(tr.get("id", "")),
			"entity_id": String(tr.get("entity_id", "")),
			"board_r": [bpos.x, bpos.y, bpos.z],
			"board_v": [bvel.x, bvel.y, bvel.z],
		})
	fw_physics_adapter = framework.physics_adapter_compare(own_state, rows)

## R5-SENSOR-BRIDGE-1：用当前 V15 tracks 生成只读 compare（不写任何轨道）。
func _fw_update_sensor_compare() -> void:
	fw_sensor_compare = {}
	if framework == null or not bool(framework.ready):
		return
	if not bool(framework.sensor_shadow_ready):
		return
	if String(framework.sensor_shadow_mode) != "shadow":
		return
	var rows: Array = []
	for raw in tracks:
		var tr: Dictionary = raw
		if bool(tr.get("own", false)):
			continue
		rows.append({
			"id": String(tr.get("id", "")),
			"batch": String(tr.get("batch", tr.get("id", ""))),
			"level": int(tr.get("level", 0)),
			"identity": String(tr.get("identity", "")),
			"range_km": float(tr.get("range_3d_km", tr.get("range", -1.0))),
			"bearing_deg": float(tr.get("bearing", tr.get("az_deg", -1.0))),
		})
	fw_sensor_compare = framework.sensor_compare(rows)

## R5-AUTHORITY-DISPLAY-1：authoritative 显示层（显式 env；默认 shadow 不写）。
## 用 V2 advisory contacts 映射 V15 显示字段 level/identity/sources(/sensor)；
## 只改显示字段，不改 r/v/own/off/任务/损管/威胁；映射缺失不写；bridge 不写 TrackTable。
func _fw_apply_sensor_authority_display() -> void:
	fw_sensor_authority_diff = {}
	if framework == null or not bool(framework.ready):
		fw_sensor_authority = "legacy_v15"
		return
	var mode := String(framework.sensor_authority_mode)
	if mode == "off":
		fw_sensor_authority = "off"
		return
	if mode != "authoritative" or not bool(framework.sensor_shadow_ready):
		fw_sensor_authority = "legacy_v15"
		return
	fw_sensor_authority = "v2_display"
	var view: Dictionary = framework.sensor_shadow_view()
	var advisories: Array = view.get("advisory_contacts", []) if not view.is_empty() else []
	var adv_map := {}
	for raw in advisories:
		var ac: Dictionary = raw
		for key in [String(ac.get("batch", "")), String(ac.get("track_id", "")),
				String(ac.get("id", ""))]:
			if key != "" and not adv_map.has(key):
				adv_map[key] = ac
	var applied := 0
	var skipped := 0
	var changed := 0
	var unchanged := 0
	var rows: Array = []
	for raw in tracks:
		var tr: Dictionary = raw
		if bool(tr.get("own", false)):
			continue
		var tid := String(tr.get("id", ""))
		var batch := String(tr.get("batch", tid))
		var ac: Dictionary = {}
		if adv_map.has(tid):
			ac = adv_map[tid]
		elif adv_map.has(batch):
			ac = adv_map[batch]
		if ac.is_empty():
			skipped += 1
			continue
		var before_level := int(tr.get("level", 0))
		var before_identity := String(tr.get("identity", ""))
		var before_sources: Array = (tr.get("sources", []) as Array).duplicate()
		var new_level := int(ac.get("level", before_level))
		var new_identity := String(ac.get("identity", ""))
		if new_identity == "":
			new_identity = before_identity
		var new_sources: Array = []
		if ac.get("sources") is Array:
			new_sources = (ac.get("sources") as Array).duplicate()
		var is_changed := before_level != new_level or before_identity != new_identity \
			or before_sources != new_sources
		tr["level"] = new_level
		tr["identity"] = new_identity
		tr["sources"] = new_sources.duplicate()
		tr["sensor"] = String(new_sources[0]) if not new_sources.is_empty() else ""
		applied += 1
		if is_changed:
			changed += 1
		else:
			unchanged += 1
		rows.append({
			"track_id": tid, "batch": batch,
			"entity_id": String(ac.get("entity_id", "")),
			"before": {"level": before_level, "identity": before_identity,
				"sources": before_sources},
			"after": {"level": new_level, "identity": new_identity,
				"sources": new_sources.duplicate(true)},
			"changed": is_changed,
		})
	fw_sensor_authority_diff = {
		"schema": "v17_sensor_authority_display_diff.v1",
		"mode": "authoritative",
		"applied": applied,
		"skipped_missing": skipped,
		"changed": changed,
		"unchanged": unchanged,
		"advisory_count": advisories.size(),
		"rows": rows,
		"display_fields": ["level", "identity", "sources", "sensor"],
		"untouched_fields": ["r", "v", "own", "off", "task", "damage", "threat",
			"side", "role", "action"],
		"writes_track_table": false,
		"note": "每帧只映射显示字段；映射失败/缺失不写；不改 r/v/任务/损管/威胁；默认 shadow 不写。",
	}

## R5-AUTHORITY-DISPLAY-1：authoritative_display 只读摘要（含最近 diff 与 bridge 摘要）。
func fw_sensor_authority_display() -> Dictionary:
	var bridge_part: Dictionary = {}
	if framework != null and framework.has_method("sensor_authority_display"):
		bridge_part = (framework.sensor_authority_display() as Dictionary).duplicate(true)
	return {
		"schema": "v17_sensor_authority_display_state.v1",
		"authority": fw_sensor_authority,
		"mode": String(framework.sensor_authority_mode) if framework != null else "off",
		"diff": fw_sensor_authority_diff.duplicate(true),
		"bridge": bridge_part,
	}

## 传感器 shadow 只读 vm / compare 的 getter。
func fw_sensor_shadow_view() -> Dictionary:
	return fw_sensor_shadow

func fw_sensor_compare_view() -> Dictionary:
	return fw_sensor_compare

# ═══════════════════════════════════════════════════════════════════
# R5-OPT-DOCK-BRIDGE-1：光学/IR + 对接只读字段与显式 API 包装
#   - fw_optical_ir / fw_docking 只读 VM；显式调用后自动 _fw_pull() 刷新；
#   - 不写 world/TrackTable/V15；不接 HUD。
# ═══════════════════════════════════════════════════════════════════

func fw_optical_ir_view() -> Dictionary:
	return fw_optical_ir

func fw_docking_view() -> Dictionary:
	return fw_docking

## 显式：VIS/IR 对准/启动/推进/停止（只读 bridge；不写 V15）。
func fw_optical_ir_point(target_id: String) -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.optical_ir_point(target_id)
	_fw_pull()
	return res

func fw_optical_ir_start(kind: String, target_id: String, opts := {}) -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.optical_ir_start(kind, target_id, opts)
	_fw_pull()
	return res

func fw_optical_ir_step(dt: float) -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.optical_ir_step(dt)
	_fw_pull()
	return res

func fw_optical_ir_stop(kind: String, target_id := "") -> void:
	if framework == null:
		return
	framework.optical_ir_stop(kind, target_id)
	_fw_pull()

## 显式：对接选择端口/相对状态 update/保持/恢复/中止/复位（只读 bridge；不写 V15）。
func fw_docking_select_port(port_id: String) -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_select_port(port_id)
	_fw_pull()
	return res

func fw_docking_update(rel, attitude := {}, dt := 0.0) -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_update(rel, attitude, dt)
	_fw_pull()
	return res

func fw_docking_hold(reason := "commander_hold") -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_hold(reason)
	_fw_pull()
	return res

func fw_docking_resume() -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_resume()
	_fw_pull()
	return res

func fw_docking_abort(reason := "commander_abort") -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_abort(reason)
	_fw_pull()
	return res

func fw_docking_reset() -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_reset()
	_fw_pull()
	return res

## R5-AUTHORITY-DISPLAY-1：UNDOCK 包装（调模型 undock；刷新；无实例 ok=false）。
func fw_docking_undock(reason := "commander_undock") -> Dictionary:
	if framework == null:
		return {"ok": false, "reason": "framework 未就绪"}
	var res: Dictionary = framework.docking_undock(reason)
	_fw_pull()
	return res

## 当前 authoritative 只读视图（HUD 后续接 [未切换]）。
func fw_physics_authoritative_view() -> Dictionary:
	return fw_physics_authoritative

## 最近一次物理 vs V15 对比（只读）。
func fw_physics_adapter_view() -> Dictionary:
	return fw_physics_adapter

## 物理显示数据字段的只读视图（同 fw_physics_display；DSH_PHYSICS_DISPLAY=0 时为空）。
func fw_physics_display_view() -> Dictionary:
	return fw_physics_display

# ═══════════════════════════════════════════════════════════════════
# R6-DISPLAY-CORE-1：物理显示数据接口（只读；供 plot 下一步消费）
#   - 仅当前时刻；不用于历史回放/预测；不写 V15 tracks（display_switched 保持 false）。
#   - available：V17_PHYSICS=authoritative 且 authoritative view.ready；
#   - enabled：available 且 DSH_PHYSICS_DISPLAY != "0"（"1" 显式开；默认开）。
#   - board 坐标：earth_rot 相对本舰（own 原点 (0,0,0)），与 physics 适配层一致。
# ═══════════════════════════════════════════════════════════════════

func _physics_display_authoritative_view() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	if not bool(framework.physics_ready):
		return {}
	if String(framework.physics_mode) != "authoritative":
		return {}
	if not framework.has_method("physics_authoritative_view"):
		return {}
	var view = framework.physics_authoritative_view()
	if view is Dictionary and bool((view as Dictionary).get("ready", false)):
		return view
	return {}

## 物理显示数据是否可用（authoritative 就绪；与用户开关无关）。
func physics_display_available() -> bool:
	return not _physics_display_authoritative_view().is_empty()

## 物理显示是否启用（available + DSH_PHYSICS_DISPLAY 覆盖；默认开）。
func physics_display_enabled() -> bool:
	if not physics_display_available():
		return false
	if OS.get_environment(PHYSICS_DISPLAY_ENV).strip_edges() == "0":
		return false
	return true

## 物理显示状态摘要（只读；HUD/plot 可用于灰显说明）。
func physics_display_status() -> Dictionary:
	var view := _physics_display_authoritative_view()
	var avail := not view.is_empty()
	var env := OS.get_environment(PHYSICS_DISPLAY_ENV).strip_edges()
	var out := {
		"schema": "v17_physics_display_status.v1",
		"available": avail,
		"enabled": physics_display_enabled(),
		"override": env,
		"mode": String(framework.physics_mode) if framework != null else "off",
		"requested_mode": String(framework.physics_requested_mode) if framework != null else "off",
		"display_switched": bool(view.get("display_switched", false)),
		"reason": "",
	}
	if not avail:
		out["reason"] = "authoritative 物理未就绪（V17_PHYSICS=authoritative 且 ready 时可用）"
	elif env == "0":
		out["reason"] = "DSH_PHYSICS_DISPLAY=0 关闭物理显示"
	return out

## 物理显示帧（只读 JSON 可序列化；未启用/未就绪返回空）。
func physics_display_frame() -> Dictionary:
	if not physics_display_enabled():
		return {}
	var view := _physics_display_authoritative_view()
	if view.is_empty():
		return {}
	var own_row: Dictionary = view.get("own", {}) if view.get("own") is Dictionary else {}
	var flag_row: Dictionary = view.get("flagship", {}) if view.get("flagship") is Dictionary else {}
	var target_map := {}
	for raw in (view.get("targets", []) as Array):
		var trow: Dictionary = raw
		target_map[String(trow.get("entity_id", ""))] = trow
	var fixed_map := {}
	for raw in (view.get("fixed", []) as Array):
		var frow: Dictionary = raw
		fixed_map[String(frow.get("entity_id", ""))] = frow
	var own_id := String(own_row.get("entity_id", ""))
	var flag_id := String(flag_row.get("entity_id", ""))
	var entries := {}
	var missing: Array = []
	var own_entry := {}
	var flag_entry := {}
	for raw in tracks:
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		if tid == "":
			continue
		var eid := _physics_entity_for_track_id(tid)
		var row: Dictionary = {}
		var role := ""
		if eid != "" and eid == own_id:
			row = own_row
			role = "own"
		elif eid != "" and eid == flag_id:
			row = flag_row
			role = "flagship"
		elif eid != "" and target_map.has(eid):
			row = target_map[eid]
			role = "target"
		elif eid != "" and fixed_map.has(eid):
			row = fixed_map[eid]
			role = "fixed"
		if row.is_empty():
			missing.append(tid)
			continue
		var entry := _physics_display_entry(tid, String(tr.get("batch", tid)), eid, role, row)
		entries[tid] = entry
		if role == "own" and own_entry.is_empty():
			own_entry = entry.duplicate(true)
		elif role == "flagship" and flag_entry.is_empty():
			flag_entry = entry.duplicate(true)
	if own_entry.is_empty():
		own_entry = {"track_id": "", "batch": "", "entity_id": own_id, "role": "own",
			"entity_kind": "ship", "name": String(own_row.get("name", "")), "fixed": false,
			"board_r": [0.0, 0.0, 0.0], "board_v": [0.0, 0.0, 0.0],
			"range_km": 0.0, "bearing_deg": 0.0, "elevation_deg": 0.0,
			"age_s": 0.0, "source": String(own_row.get("source", "")), "filled": false}
	# R6-FIXED-CORE-1：固定站体列表（含 V15 track id 映射；无映射时 track_id 为空）
	var fixed_list: Array = []
	var fixed_ids: Array = []
	for raw in (view.get("fixed", []) as Array):
		var frow: Dictionary = raw
		var feid := String(frow.get("entity_id", ""))
		if feid == "":
			continue
		var ftrack := ""
		var fbatch := String(frow.get("batch", ""))
		for trraw in tracks:
			var tr2: Dictionary = trraw
			var tid2 := String(tr2.get("id", ""))
			if tid2 == "":
				continue
			if _physics_entity_for_track_id(tid2) == feid:
				ftrack = tid2
				fbatch = String(tr2.get("batch", tid2))
				break
		if ftrack == "":
			var cmap := _physics_display_contact_for_entity(feid)
			ftrack = String(cmap.get("track_id", ""))
			if fbatch == "":
				fbatch = String(cmap.get("batch", ftrack))
		var fentry := _physics_display_entry(ftrack, fbatch, feid, "fixed", frow)
		fixed_list.append(fentry)
		fixed_ids.append(feid)
		if ftrack != "" and not entries.has(ftrack):
			entries[ftrack] = fentry.duplicate(true)
	return {
		"schema": "v17_physics_display.v1",
		"available": true,
		"enabled": true,
		"mode": String(framework.physics_mode),
		"requested_mode": String(framework.physics_requested_mode),
		"display_switched": bool(view.get("display_switched", false)),
		"source": String(view.get("source", "")),
		"frame": (view.get("frame", {}) as Dictionary).duplicate(true),
		"tau": tau(),
		"physics_t": float(view.get("t", 0.0)),
		"delta_t_s": tau() - float(view.get("t", 0.0)),
		"replay_ok": false,
		"note": "只读当前时刻；不用于历史回放/预测；V15 位置源/plot 尚未切换。",
		"mapping_note": "entries 以 V15 track id（批号）为键；entity_id 由 bridge contacts/entities.batch 映射；固定站体 role=fixed；无对应列入 missing，不伪造。",
		"own": own_entry,
		"flagship": flag_entry,
		"fixed": fixed_list,
		"fixed_ids": fixed_ids,
		"entries": entries,
		"missing": missing,
		"warnings": (view.get("warnings", []) as Array).duplicate(true),
	}

func _physics_display_entry(track_id: String, batch: String, entity_id: String, role: String,
		row: Dictionary) -> Dictionary:
	return {
		"track_id": track_id,
		"batch": batch,
		"entity_id": entity_id,
		"role": role,
		"entity_kind": String(row.get("entity_kind", row.get("kind", ""))),
		"name": String(row.get("name", "")),
		"fixed": bool(row.get("fixed", role == "fixed")),
		"board_r": ((row.get("board_r", []) as Array) as Array).duplicate(),
		"board_v": ((row.get("board_v", []) as Array) as Array).duplicate(),
		"range_km": float(row.get("range_km", 0.0)),
		"bearing_deg": float(row.get("bearing_deg", 0.0)),
		"elevation_deg": float(row.get("elevation_deg", 0.0)),
		"range_rate_kmps": float(row.get("range_rate_kmps", 0.0)),
		"closing_kmps": float(row.get("closing_kmps", 0.0)),
		"age_s": float(row.get("age_s", 0.0)),
		"source": String(row.get("source", "")),
		"filled": true,
	}

## 物理 entity id → bridge 归一接触的 {track_id,batch}（固定站体映射；无返回空）。
func _physics_display_contact_for_entity(entity_id: String) -> Dictionary:
	if entity_id == "":
		return {}
	for raw in fw_contacts:
		var c: Dictionary = raw
		if String(c.get("entity_id", "")) != entity_id:
			continue
		var tid := String(c.get("track_id", c.get("id", "")))
		return {"track_id": tid, "batch": String(c.get("batch", tid))}
	if framework != null and framework.world != null:
		for raw in framework.world.vm_contacts():
			var c2: Dictionary = raw
			if String(c2.get("entity_id", "")) != entity_id:
				continue
			var tid2 := String(c2.get("track_id", ""))
			return {"track_id": tid2, "batch": String(c2.get("batch", tid2))}
	return {}

## V15 track id（批号）→ 物理实体 id；找不到返回 ""（不伪造）。
func _physics_entity_for_track_id(track_id: String) -> String:
	var batch := track_id
	for raw in tracks:
		var tr: Dictionary = raw
		if String(tr.get("id", "")) == track_id:
			var direct := String(tr.get("entity_id", ""))
			if direct != "":
				return direct
			batch = String(tr.get("batch", track_id))
			break
	for raw in fw_contacts:
		var c: Dictionary = raw
		if track_id == String(c.get("track_id", "")) or track_id == String(c.get("batch", "")) \
				or batch == String(c.get("batch", "")):
			var eid := String(c.get("entity_id", ""))
			if eid != "":
				return eid
	if framework != null and framework.world != null:
		for raw in framework.world.entities:
			var e = raw
			if String(e.batch) == track_id or String(e.batch) == batch or String(e.id) == track_id:
				return String(e.id)
	return ""

## 物理显示 board 坐标（km，earth_rot 相对本舰）；未启用/无对应返回 []。
func physics_display_board_for(id: String) -> Array:
	var entry := physics_display_entry_for(id)
	if entry.is_empty():
		return []
	return ((entry.get("board_r", []) as Array) as Array).duplicate()

## 物理显示 board 速度（km/s，earth_rot 相对本舰）；未启用/无对应返回 []。
func physics_display_velocity_for(id: String) -> Array:
	var entry := physics_display_entry_for(id)
	if entry.is_empty():
		return []
	return ((entry.get("board_v", []) as Array) as Array).duplicate()

## 物理显示条目（支持 V15 track id/批号/entity id）；无对应返回空。
func physics_display_entry_for(id: String) -> Dictionary:
	var frame := physics_display_frame()
	if frame.is_empty():
		return {}
	var entries: Dictionary = frame.get("entries", {})
	if entries.has(id):
		return (entries[id] as Dictionary).duplicate(true)
	for raw in entries.values():
		var e: Dictionary = raw
		if String(e.get("entity_id", "")) == id:
			return e.duplicate(true)
	var own: Dictionary = frame.get("own", {})
	if String(own.get("entity_id", "")) == id or String(own.get("track_id", "")) == id:
		return own.duplicate(true)
	var flag: Dictionary = frame.get("flagship", {})
	if String(flag.get("entity_id", "")) == id or String(flag.get("track_id", "")) == id:
		return flag.duplicate(true)
	return {}

## 固定站体物理显示条目（R6-FIXED-CORE-1）：支持 V15 track id/批号/entity id；非固定/无对应返回空。
func physics_display_fixed_for(id: String) -> Dictionary:
	var frame := physics_display_frame()
	if frame.is_empty():
		return {}
	for raw in (frame.get("fixed", []) as Array):
		var e: Dictionary = raw
		if String(e.get("entity_id", "")) == id or String(e.get("track_id", "")) == id \
				or String(e.get("batch", "")) == id:
			return e.duplicate(true)
	return {}

## V2 教学门控是否放行 V15 决策（截图/自动化/演示时自动放行）。
func fw_tutorial_allows() -> bool:
	if framework == null or not bool(framework.ready):
		return true
	if capture:
		return true
	if OS.get_environment("DSH_SKIP_TUTORIAL") == "1":
		return true
	if OS.get_environment("DSH_SIM") != "" or OS.get_environment("DSH_SHOT") != "":
		return true
	return bool(framework.tutorial_allowed())

## 教学门控原因（"" = 未阻塞）。
func fw_decision_gate_reason() -> String:
	if framework == null or not bool(framework.ready):
		return ""
	return String(framework.decision_gate_reason())

## V2 教程是否 ready（未接入时 true）。
func fw_tutorial_ready() -> bool:
	return bool(fw_tutorial.get("ready", true))

## 当前选中 V15 航迹的批号（fw_actions 目标）。
func fw_selected_batch() -> String:
	if tracks.is_empty():
		return ""
	var idx := clampi(int(selected), 0, tracks.size() - 1)
	var tr: Dictionary = tracks[idx]
	return String(tr.get("batch", tr.get("id", "")))

## 指定目标的 V2 可用动作（HUD 右键菜单可直接渲染 available/reason）。
func fw_actions_for(track_id: String) -> Array:
	if framework == null or not bool(framework.ready):
		return []
	return framework.actions_for(track_id)

## 执行 V2 识别动作（教学门控的关键路径）。返回 V2 结果：
## {ok, action, level, level_name, identity, actor_id, actor_name, reason, reason_code, detail, ...}
func fw_perform_action(action_id: String, target_id := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var tid := target_id if target_id != "" else fw_selected_batch()
	var r: Dictionary = framework.perform_action(action_id, tid)
	fw_last_action = r.duplicate(true)
	_fw_pull()
	# 动作可能满足教学门控 → 立即尝试解除挂起的决策
	if fw_decision_deferred and fw_tutorial_allows() and not decision_open \
			and not report_open and not consequence_open:
		fw_decision_deferred = false
		fw_decision_reason = ""
		_open_decision()
	return r

func fw_start_repair(section_id: String) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.start_repair(section_id)
	_fw_pull()
	return r

func fw_apply_damage(id: String, severity := 0.5, label := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.apply_damage(id, severity, label)
	_fw_pull()
	return r

func fw_open_decision() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.open_decision()
	_fw_pull()
	return r

func fw_choose_ending(kind: String) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.choose_ending(kind)
	_fw_pull()
	return r

func fw_submit_report(truth := true) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.submit_report(truth)
	_fw_pull()
	return r

func fw_evidence_start(id: String) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.evidence_start(id)
	_fw_pull()
	return r

# —— 回放（只读帧；回放定位不推进世界）——
func fw_replay_start() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	var r: Dictionary = framework.replay_start()
	_fw_pull()
	return r

func fw_replay_pause() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	var r: Dictionary = framework.replay_pause()
	_fw_pull()
	return r

func fw_replay_stop() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	var r: Dictionary = framework.replay_stop()
	_fw_pull()
	return r

func fw_replay_seek(t_s: float) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	var r: Dictionary = framework.replay_seek(t_s)
	_fw_pull()
	return r

## 按帧号精确 seek（HUD 播放头/回放拖动可用；seek 后固定查看头，录制追加帧不移动）。
func fw_replay_seek_index(index: int) -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	var r: Dictionary = framework.replay_seek_index(index)
	_fw_pull()
	return r

func fw_replay_frame() -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {}
	return framework.replay_frame()

# ── R4-CORE-2：导航/交通管制/机动规划包装（只转发；不自动执行/不自动授权）──

func _fw_nav_call(method: String, args: Array = []) -> Dictionary:
	if framework == null or not bool(framework.ready) or not bool(framework.nav_ready):
		return {"ok": false, "reason": "navigation 未就绪"}
	var r = framework.callv(method, args)
	_fw_pull()
	return r as Dictionary if r is Dictionary else {}

func fw_nav_plan_routes(from_id: String, to_id: String, constraints := {}) -> Dictionary:
	return _fw_nav_call("nav_plan_routes", [from_id, to_id, constraints])

func fw_nav_select_route(route_arg = null) -> Dictionary:
	return _fw_nav_call("nav_select_route", [route_arg])

func fw_nav_request_clearance(route_arg = null, window = null, priority := 3) -> Dictionary:
	return _fw_nav_call("nav_request_clearance", [route_arg, window, priority])

func fw_nav_grant(request_id: String) -> Dictionary:
	return _fw_nav_call("nav_grant_clearance", [request_id])

func fw_nav_deny(request_id: String, reason := "authority_denied") -> Dictionary:
	return _fw_nav_call("nav_deny_clearance", [request_id, reason])

func fw_nav_hold(request_id: String, until_t := -1.0) -> Dictionary:
	return _fw_nav_call("nav_hold_clearance", [request_id, until_t])

func fw_nav_plan_maneuver(kind: String, target := "", opts := {}) -> Dictionary:
	return _fw_nav_call("nav_plan_maneuver", [kind, target, opts])

func fw_nav_authorize(plan_id: String) -> Dictionary:
	return _fw_nav_call("nav_authorize", [plan_id])

func fw_nav_queue_maneuver(plan_id: String, clearance_id := "") -> Dictionary:
	return _fw_nav_call("nav_queue_maneuver", [plan_id, clearance_id])

func fw_nav_execute(plan_id: String) -> Dictionary:
	return _fw_nav_call("nav_execute", [plan_id])

func fw_nav_abort(plan_id: String, reason := "commander_abort") -> Dictionary:
	return _fw_nav_call("nav_abort", [plan_id, reason])

# ── R2-DAMAGE-2：完整损管模型写 API（仅转发；不自动生成命中）──

func fw_damage_apply_hit(section: String, energy: float, penetration := 0.5,
		direction := "fore", source := "state", entity_id := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.damage_apply_hit(section, energy, penetration, direction,
		source, entity_id)
	_fw_pull()
	return r

func fw_damage_assign_repair(section: String, priority := 2, entity_id := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.damage_assign_repair(section, priority, entity_id)
	_fw_pull()
	return r

func fw_damage_cancel_repair(section: String, entity_id := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.damage_cancel_repair(section, entity_id)
	_fw_pull()
	return r

func fw_damage_set_priority(section: String, priority: int, entity_id := "") -> Dictionary:
	if framework == null or not bool(framework.ready):
		return {"ok": false, "reason": "framework 未就绪"}
	var r: Dictionary = framework.damage_set_priority(section, priority, entity_id)
	_fw_pull()
	return r

## 完整损管模型是否就绪（fw_damage_model 字段的 getter 版）。
func fw_damage_model_ready() -> bool:
	return fw_damage_model

func fw_restart() -> void:
	fw_decision_deferred = false
	fw_decision_reason = ""
	if framework == null:
		return
	framework.restart()
	_fw_pull()
	_fw_update_physics_adapter()
	_fw_update_sensor_compare()
	_fw_apply_sensor_authority_display()

## HUD 一帧总览（其余字段仍可按需读 state.fw_*）。
func fw_bridge_state() -> Dictionary:
	return {
		"ready": fw_ready,
		"t": fw_t,
		"sync_count": fw_sync_count,
		"tutorial": fw_tutorial.duplicate(true),
		"tutorial_ready": fw_tutorial_ready(),
		"tutorial_allowed": fw_tutorial_allows(),
		"decision_reason": fw_decision_reason,
		"decision_deferred": fw_decision_deferred,
		"flow": fw_flow.duplicate(true),
		"damage": fw_damage.duplicate(true),
		"replay": fw_replay.duplicate(true),
		"contacts": fw_contacts.duplicate(true),
		"actions": fw_actions.duplicate(true),
		"actions_target": fw_actions_target,
		"nav": fw_nav.duplicate(true),
		"nav_ready": fw_nav_ready,
		"nav_summary": fw_nav_summary.duplicate(true),
		"damage_full": fw_damage_full.duplicate(true),
		"damage_model": fw_damage_model,
		"physics": fw_physics.duplicate(true),
		"physics_ready": fw_physics_ready,
		"physics_summary": fw_physics_summary.duplicate(true),
		"physics_mode": fw_physics_mode,
		"physics_authoritative": fw_physics_authoritative.duplicate(true),
		"physics_adapter": fw_physics_adapter.duplicate(true),
		"physics_display": fw_physics_display.duplicate(true),
		"sensor_shadow": fw_sensor_shadow.duplicate(true),
		"sensor_shadow_ready": fw_sensor_shadow_ready,
		"sensor_compare": fw_sensor_compare.duplicate(true),
		"sensor_authority": fw_sensor_authority,
		"sensor_authority_diff": fw_sensor_authority_diff.duplicate(true),
		"info_warfare": fw_info_warfare.duplicate(true),
		"info_warfare_ready": fw_info_warfare_ready,
		"info_warfare_summary": fw_info_warfare_summary.duplicate(true),
		"optical_ir": fw_optical_ir.duplicate(true),
		"docking": fw_docking.duplicate(true),
		"optical_ir_auto": fw_optical_ir_auto,
		"docking_auto": fw_docking_auto,
		"exec_window_s": float(fw_flow.get("exec_window_s", 360.0)),
		"exec_left": float(fw_flow.get("exec_left", 0.0)),
		"exec_pct": float(fw_flow.get("exec_pct", 0.0)),
		"reputation": (fw_flow.get("reputation", {}) as Dictionary).duplicate(true),
		"reputation_settled": bool(fw_flow.get("reputation_settled", false)),
		"last_action": fw_last_action.duplicate(true),
	}

# —— V15 → V2 流程镜像（best effort；V2 端拒绝不影响 V15 流程）——

func _fw_mirror_choice(kind: String) -> void:
	if framework == null or not bool(framework.ready):
		return
	framework.choose_ending(kind)
	_fw_pull()

func _fw_mirror_report(truth: bool) -> void:
	if framework == null or not bool(framework.ready):
		return
	framework.submit_report(truth)
	_fw_pull()

# ═══════════════════════════════════════════════════════════════════
# V17-CORE-3：清算者无线电教学 API / 传感器权威边界
#
# 无线电：COMMAND 阶段手动触发，标准通信格式 [from至to]-[LD/LR/RDO]-[text]，
#   写入 radio_feed（_append_radio）与本流程只读状态；不自动完成、不改变证据/裁决/
#   声望/时钟/冻结。HUD 后续只需读 state.reclaimer_radio_* 与调用 initiate/reply。
#
# 传感器边界：V15 sensor_model 仍是接触等级/融合/威胁的唯一权威；
#   V2 radar/TWS/optical 仅为数据/演示模型（advisory），不切换、不伪造。
# ═══════════════════════════════════════════════════════════════════

func _load_reclaimer_radio() -> void:
	reclaimer_radio_content = {}
	var candidates: Array = [RECLAIMER_RADIO_PATH]
	var base := ProjectSettings.globalize_path("res://")
	candidates.append(base.path_join("../framework/content/reclaimer_radio_l1.json").simplify_path())
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
			var content: Dictionary = parsed
			if content.get("exchange") is Array and (content.get("exchange", []) as Array).size() > 0:
				reclaimer_radio_content = content
				return
	reclaimer_radio_content = _reclaimer_fallback_content()

## 内容文件丢失时的最小兜底（仍遵守手动/无自动完成/标准格式；探针会验证正式文件）。
func _reclaimer_fallback_content() -> Dictionary:
	var own := "远地点号"
	var cp := "AV-4412 传唤者"
	return {
		"schema": RECLAIMER_RADIO_SCHEMA,
		"id": "l1_reclaimer_radio_fallback",
		"title": "清算者程序性通话（兜底）",
		"trigger_phase": "COMMAND",
		"own_callsign": own,
		"counterpart": cp,
		"exchange": [{
			"dir": "rx", "from": cp, "to": own, "mode": "RDO",
			"text": "远地点号，AV-4412 传唤者。依据第七号轨道紧急托管令，ID13 应于 50 km 检查边界外待命。完毕。",
		}],
		"options": [{
			"id": "ack", "code": "A", "label": "确认收到 / ACK",
			"hint": "确认记录，不改变当前程序。",
			"reply": {"dir": "tx", "from": own, "to": cp, "mode": "RDO",
				"text": "AV-4412 传唤者，远地点号。收到，ID13 将记录本次通话。完毕。"},
			"ack": {"dir": "rx", "from": cp, "to": own, "mode": "RDO",
				"text": "远地点号，收到。通话结束。完毕。"},
		}],
	}

## 标准通信格式：`[from至to]-[LD/LR/RDO]-[text]`（docs/15 §0.3、docs/19 §1）。
func reclaimer_radio_format(from_s: String, to_s: String, mode: String, text: String) -> String:
	return "[%s至%s]-[%s]-[%s]" % [from_s, to_s, mode, text]

## 通用格式 helper（其他通信也可用；不写死清算者）。
func format_radio_line(from_s: String, to_s: String, mode: String, text: String) -> String:
	return reclaimer_radio_format(from_s, to_s, mode, text)

## 是否可发起：仅 COMMAND 阶段、未发起过、未冻结/未进入裁决或报告/END。
func reclaimer_radio_available() -> bool:
	if reclaimer_radio_content.is_empty():
		return false
	if reclaimer_radio_stage != "idle":
		return false
	if prelude_open or sim_frozen:
		return false
	if decision_open or consequence_open or report_open or end_open:
		return false
	return tut_phase == PHASE_COMMAND

## 只读状态（HUD 直接读；不含可变引用）。
func reclaimer_radio_state() -> Dictionary:
	var opts: Array = []
	var raw_opts: Array = reclaimer_radio_content.get("options", []) if reclaimer_radio_content.has("options") else []
	for raw in raw_opts:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = raw
		var enabled := reclaimer_radio_open
		var reason := ""
		if not enabled:
			reason = "通话已结束" if reclaimer_radio_stage == "done" else "尚未发起通话"
		opts.append({
			"id": String(o.get("id", "")),
			"code": String(o.get("code", "")),
			"label": String(o.get("label", "")),
			"hint": String(o.get("hint", "")),
			"enabled": enabled,
			"reason": reason,
		})
	var transcript_lines: Array = []
	for raw in reclaimer_radio_transcript:
		transcript_lines.append(String((raw as Dictionary).get("formatted", "")))
	return {
		"available": reclaimer_radio_available(),
		"phase": tut_phase,
		"trigger_phase": "COMMAND",
		"stage": reclaimer_radio_stage,
		"open": reclaimer_radio_open,
		"seen": reclaimer_radio_seen,
		"choice": reclaimer_radio_choice,
		"started_t": reclaimer_radio_started_t,
		"content_id": String(reclaimer_radio_content.get("id", "")),
		"content_loaded": not reclaimer_radio_content.is_empty(),
		"title": String(reclaimer_radio_content.get("title", "")),
		"own_callsign": String(reclaimer_radio_content.get("own_callsign", "远地点号")),
		"counterpart": String(reclaimer_radio_content.get("counterpart", "AV-4412 传唤者")),
		"options": opts,
		"transcript": reclaimer_radio_transcript.duplicate(true),
		"formatted_transcript": transcript_lines,
		"note": "COMMAND 阶段手动发起；只写 radio_feed/日志与本流程状态，不自动完成，不改变证据/裁决/声望/时钟。",
	}

## 手动发起（接收清算者程序性通话）。只写 radio_feed/日志；不改变其他游戏状态。
func reclaimer_radio_initiate() -> Dictionary:
	if not reclaimer_radio_available():
		var reason := ""
		if prelude_open:
			reason = "前置航行未完成"
		elif tut_phase != PHASE_COMMAND:
			reason = "仅 COMMAND 阶段可发起（当前 %s）" % tut_phase
		elif reclaimer_radio_stage != "idle":
			reason = "本次通话已发起（stage=%s）" % reclaimer_radio_stage
		elif reclaimer_radio_content.is_empty():
			reason = "无线电内容未就绪"
		else:
			reason = "当前不可发起"
		_push_log("清算者无线电不可发起：%s" % reason, "COMMS", "HOLD")
		return {"ok": false, "reason": reason, "stage": reclaimer_radio_stage,
			"phase": tut_phase, "available": false, "state": reclaimer_radio_state()}
	reclaimer_radio_stage = "open"
	reclaimer_radio_open = true
	reclaimer_radio_seen = true
	reclaimer_radio_started_t = tau()
	reclaimer_radio_choice = ""
	var lines: Array = []
	for raw in (reclaimer_radio_content.get("exchange", []) as Array):
		if raw is Dictionary:
			lines.append(_reclaimer_append_line(raw as Dictionary, "initiate"))
	_push_log("无线电教学：已发起与清算者的程序性通话（COMMAND 阶段手动触发）", "COMMS", "EXEC")
	return {"ok": true, "stage": "open", "lines": lines, "state": reclaimer_radio_state()}

## 玩家选择回复（需先 initiate）。只写 radio_feed/日志；不自动完成/不改变流程外状态。
func reclaimer_radio_reply(choice: String) -> Dictionary:
	if reclaimer_radio_stage != "open" or not reclaimer_radio_open:
		return {"ok": false, "reason": "通话未开启或已结束", "stage": reclaimer_radio_stage,
			"state": reclaimer_radio_state()}
	var key := choice.strip_edges().to_lower()
	var raw_opts: Array = reclaimer_radio_content.get("options", []) if reclaimer_radio_content.has("options") else []
	var opt: Dictionary = {}
	for raw in raw_opts:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = raw
		var oid := String(o.get("id", "")).to_lower()
		var ocode := String(o.get("code", "")).to_lower()
		if key == oid or key == ocode or key == String(o.get("label", "")).to_lower():
			opt = o
			break
	if opt.is_empty():
		return {"ok": false, "reason": "未知选项：%s" % choice, "stage": reclaimer_radio_stage,
			"options": (reclaimer_radio_state().get("options", []) as Array).duplicate(true),
			"state": reclaimer_radio_state()}
	var lines: Array = []
	var reply: Dictionary = (opt.get("reply", {}) as Dictionary) if opt.get("reply") is Dictionary else {}
	if not reply.is_empty():
		lines.append(_reclaimer_append_line(reply, "reply"))
	var ack: Dictionary = (opt.get("ack", {}) as Dictionary) if opt.get("ack") is Dictionary else {}
	if not ack.is_empty():
		lines.append(_reclaimer_append_line(ack, "ack"))
	reclaimer_radio_choice = String(opt.get("id", ""))
	reclaimer_radio_stage = "done"
	reclaimer_radio_open = false
	reclaimer_radio_seen = true
	_push_log("无线电教学：已回复清算者（%s），通话结束；未改变证据/裁决/声望" % String(opt.get("label", reclaimer_radio_choice)),
		"COMMS", "EXEC")
	return {"ok": true, "choice": reclaimer_radio_choice, "code": String(opt.get("code", "")),
		"stage": "done", "lines": lines, "state": reclaimer_radio_state()}

## 已发生的通话条目（只读，按发生顺序）。
func reclaimer_radio_transcript_lines() -> Array:
	return reclaimer_radio_transcript.duplicate(true)

## 追加一条通话：写 radio_feed + 日志（复用 _append_radio 的标准格式），并记录只读 transcript。
func _reclaimer_append_line(line: Dictionary, stage_name: String) -> Dictionary:
	var dir := String(line.get("dir", "rx")).to_lower()
	if dir != "tx":
		dir = "rx"
	var from_s := String(line.get("from", ""))
	var to_s := String(line.get("to", ""))
	var mode := String(line.get("mode", "RDO")).to_upper()
	var text := String(line.get("text", ""))
	var at := tau()
	_append_radio(from_s, to_s, mode, text, at)
	var rec := {
		"stage": stage_name,
		"dir": dir,
		"from": from_s,
		"to": to_s,
		"mode": mode,
		"text": text,
		"formatted": reclaimer_radio_format(from_s, to_s, mode, text),
		"t": at,
	}
	reclaimer_radio_transcript.append(rec)
	return rec

# ── 传感器权威边界（不切换，仅声明/摘要）────────────────────

func sensor_authority_note() -> String:
	return SENSOR_AUTHORITY_NOTE

## V2 传感器/数据模型的只读 advisory 摘要；V15 sensor_model 仍是接触等级权威。
func v2_sensor_advisory() -> Dictionary:
	var sel_level := 0
	var sel_identity := ""
	var sel_id := ""
	var idx := clampi(int(selected), 0, maxi(0, tracks.size() - 1))
	if idx >= 0 and idx < tracks.size():
		var tr: Dictionary = tracks[idx]
		sel_level = int(tr.get("level", 1))
		sel_identity = String(tr.get("identity", ""))
		sel_id = String(tr.get("id", ""))
	var adv := {
		"authority": sensor_authority,
		"authority_source": "scripts/sensor_model.gd（V15 传感器融合/接触等级）",
		"role": "advisory_data_demo",
		"switching": false,
		"note": SENSOR_AUTHORITY_NOTE,
		"v2_ready": false,
		"v2_sources": ["framework/sim/radar.gd", "framework/sim/tws.gd", "framework/sim/optical.gd"],
		"v15": {
			"selected_track_id": sel_id,
			"selected_level": sel_level,
			"selected_identity": sel_identity,
			"sensor": sensor,
			"fusion_count": fusion_count,
		},
	}
	if framework != null and bool(framework.ready):
		adv["v2_ready"] = true
		var contacts: Array = []
		if framework.has_method("contacts_view"):
			contacts = framework.contacts_view() as Array
		elif framework.contacts is Array:
			contacts = framework.contacts as Array
		adv["v2_contact_count"] = contacts.size()
		if framework.has_method("summary"):
			adv["v2_summary"] = framework.summary()
	return adv
