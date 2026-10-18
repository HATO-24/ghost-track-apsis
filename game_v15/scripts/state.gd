class_name WarState
extends RefCounted

# 演示用状态。真实 sim 会接管 clock / tracks / commands，
# 这里的数值只服务于"把 GUI 长相对出来"。

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
	tracks = [
		{
			"id": "哈马丹", "en": "HARMATTAN", "cls": "托盘-5 改", "role": "哨舰",
			"side": "friend", "level": 4, "bearing": 0.0, "range": 0.0, "alt": 0.0,
			"closing": 0.0, "age": 0.0, "own": true, "off": Vector2(16, 14)
		},
		{
			"id": "渡口号", "en": "FERRY", "cls": "赤铁-6 改", "role": "炮舰",
			"side": "friend", "level": 4, "bearing": 332.0, "range": 68.0, "alt": -4.0,
			"closing": -0.1, "age": 1.0, "off": Vector2(-72, -20)
		},
		{
			"id": "望楼号", "en": "WATCHTOWER", "cls": "安海-1", "role": "中继舰",
			"side": "friend", "level": 4, "bearing": 12.0, "range": 96.0, "alt": 38.0,
			"closing": 0.2, "age": 1.0, "off": Vector2(16, -18)
		},
		{
			"id": "案卷 4471", "en": "SUMMONS", "cls": "传唤级", "role": "送达舰",
			"side": "hostile", "level": 3, "bearing": 41.0, "range": 318.0, "alt": 12.0,
			"closing": -4.2, "age": 2.0, "off": Vector2(-86, -38)
		},
		{
			"id": "谷神-2", "en": "CERES-2", "cls": "工作船", "role": "民用 · 应答机故障",
			"side": "unknown", "level": 1, "bearing": 118.0, "range": 260.0, "alt": -6.0,
			"closing": 0.0, "age": 12.0, "off": Vector2(16, 12)
		},
		{
			"id": "未识别", "en": "UNKNOWN", "cls": "仅方位", "role": "陈旧接触",
			"side": "unknown", "level": 1, "bearing": 302.0, "range": 340.0, "alt": 0.0,
			"closing": 0.0, "age": 41.0, "stale": true, "bearing_only": true,
			"off": Vector2(-120, -26)
		}
	]

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
