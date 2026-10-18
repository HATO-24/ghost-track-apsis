class_name WarState
extends RefCounted

# 演示用状态。真实 sim 会接管 clock / tracks / commands，
# 这里的数值只服务于"把 GUI 长相对出来"。

const Orbit := preload("res://scripts/orbit_model.gd")

const T0 := 760.8

# 基准（datum）：图上"下"参照谁。EARTH / MOON / L1。
# L1 = 环一 · 斛（站点基准）；第一关的 DATUM 是 L1 / STATION FRAME。
const DATUMS := ["EARTH", "MOON", "L1"]
var datum := "L1"

var clock := T0
var time_scale := 60.0
var paused := false
var capture := false
var elapsed := 0.0
var selected := 0
var sensor := 0
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

# 本舰基线状态（L1 站心，km / km/s）。own 是场景 epoch（T0）时的状态，
# own_cur 是 refresh() 之后"当前时刻"的状态；plot 用它当局部板原点。
var own: Dictionary = {}
var own_cur: Dictionary = {}
# 本舰点火计划（同一套轨道模型传播；plot 不再画固定假弧）
var burn: Dictionary = {}

func set_datum(d: String) -> void:
	var u := d.to_upper()
	if DATUMS.has(u):
		datum = u

func cycle_datum() -> String:
	var i := DATUMS.find(datum)
	datum = DATUMS[(i + 1) % DATUMS.size()]
	return datum

func _init() -> void:
	_build_sensors()
	_build_tracks()
	_build_log()
	_build_unit()

func _build_sensors() -> void:
	sensors = [
		{"mfr": "公约舰队", "model": "S-07", "mode": "舰载战斗系统", "sig": "SYNC 1.0s", "glyph": "ring", "color": "#8CF0C0"},
		{"mfr": "永昼租界", "model": "明视 IR-9", "mode": "被动红外", "sig": "STARE ∞", "glyph": "web", "color": "#E8A34B"},
		{"mfr": "签约国", "model": "远望 R-9", "mode": "主动雷达", "sig": "SWEEP 6s", "glyph": "hex", "color": "#8CF0C0"},
		{"mfr": "明视光学", "model": "明视 MS-IR9", "mode": "光学凝视", "sig": "MAG 8×", "glyph": "frame", "color": "#7FB6C9"},
		{"mfr": "签约国", "model": "MK-12", "mode": "敌我识别", "sig": "PULSE 2s", "glyph": "gate", "color": "#8CF0C0"},
		{"mfr": "天市", "model": "ELINT", "mode": "通信截听", "sig": "SNIFF", "glyph": "jag", "color": "#E2564A"}
	]

func _build_tracks() -> void:
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
		_track("案卷 4471", "SUMMONS", "传唤级", "送达舰", "hostile", 3,
			_rel(41.0, 318.0, 12.0), Vector3(-1.1683, -0.5067, -0.0634), 2.0, false, Vector2(-86, -38)),
		_track("谷神-2", "CERES-2", "工作船", "民用 · 应答机故障", "unknown", 1,
			_rel(118.0, 260.0, -6.0), Vector3(0.0505, 0.0524, -0.0005), 12.0, false, Vector2(16, 12)),
		_track("未识别", "UNKNOWN", "仅方位", "陈旧接触", "unknown", 1,
			_rel(302.0, 340.0, 0.0), Vector3(0.0900, 0.0200, 0.0), 41.0, false, Vector2(-120, -26), true)
	]
	# 点火计划：T+6.2 s、Δv 84 m/s、方位 340°、仰角 +20°（含离面分量）。
	burn = {
		"t": 6.2,
		"brg": 340.0,
		"elev": 20.0,
		"dv_ms": 84.0,
		"dv": _dv_vec(340.0, 20.0, 0.084),
		"label": "TRANSFER 哈马丹 → 节点 B-2"
	}

func _rel(bearing: float, range_km: float, alt_km: float) -> Vector3:
	var b := deg_to_rad(bearing)
	return Vector3(sin(b) * range_km, cos(b) * range_km, alt_km)

func _dv_vec(bearing: float, elev: float, dv_kms: float) -> Vector3:
	var b := deg_to_rad(bearing)
	var e := deg_to_rad(elev)
	return Vector3(sin(b) * cos(e), cos(b) * cos(e), sin(e)) * dv_kms

func _track(id: String, en: String, cls: String, role: String, side: String, level: int,
		r: Vector3, v: Vector3, age: float, is_own := false,
		off := Vector2(16, 12), bearing_only := false) -> Dictionary:
	var d := {
		"id": id, "en": en, "cls": cls, "role": role, "side": side, "level": level,
		"r": r, "v": v, "epoch": T0, "age": age,
		"own": is_own, "off": off, "bearing_only": bearing_only,
		"stale": age > 30.0
	}
	_derive(d, r, v)
	return d

# 从站心状态派生 HUD / 图上用的量（bearing/range/alt/closing 都由 r/v 算，不再手填）
func _derive(d: Dictionary, r: Vector3, v: Vector3) -> void:
	d["cur_r"] = r
	d["cur_v"] = v
	var rng := r.length()
	d["range"] = rng
	d["bearing"] = fposmod(rad_to_deg(atan2(r.x, r.y)), 360.0)
	d["alt"] = r.z
	d["closing"] = (-r.dot(v) / rng) if rng > 1.0e-6 else 0.0

func tau() -> float:
	return clock - T0

# 把每条 track 推进到 now（相对 T0 的秒），并刷新派生量。
# 捕获/截图时 clock 不动，这里就是幂等的。
func refresh(now: float) -> void:
	var t := now - T0
	for tr in tracks:
		var st := Orbit.local_propagate(tr["r"], tr["v"], t)
		var rr: Vector3 = st["r"]
		var vv: Vector3 = st["v"]
		_derive(tr, rr, vv)
		if tr.get("own", false):
			own_cur = {"r": rr, "v": vv}

func _build_log() -> void:
	log_lines = [
		{"t": "12:31.4", "text": "TRANSFER 哈马丹 → 节点 B-2", "arg": "Δv 84", "status": "PENDING"},
		{"t": "12:28.0", "text": "EMCON 静默 · 雷达关机", "arg": "", "status": "EXEC"},
		{"t": "12:19.3", "text": "火控请求 → 案卷 4471", "arg": "ROE 拒绝", "status": "HOLD"},
		{"t": "12:04.8", "text": "传感器：被动红外 / 光学", "arg": "", "status": "EXEC"},
		{"t": "11:52.1", "text": "接收 接管通知 · 案卷 4471", "arg": "", "status": "RX"}
	]

func _build_unit() -> void:
	unit = {
		"name": "哈马丹", "en": "HARMATTAN", "cls": "托盘-5 改", "role": "哨舰",
		"faction": "公约 · AD 特遣群",
		"mass": "300 t", "crew": "12", "accel": "0.15 g",
		"orbit": "L1 · 斛站", "inc": "—", "period": "—",
		"dv": "1,120", "dv_max": "1,260",
		"systems": [["传感器", 0.74], ["火控", 0.42], ["推进", 0.66], ["通信", 0.82], ["反应堆", 0.95]],
		"weapons": [["CH-IR2 红外", "1 · 被动"], ["CH-R0 无线电", "1 · 4s"], ["武器", "无"]],
		"damage": "红外虚警偏高", "damage2": "· CH-IR2 校准中"
	}
