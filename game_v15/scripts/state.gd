class_name WarState
extends RefCounted

# 演示用状态。真实 sim 会接管 clock / tracks / commands，
# 这里的数值只服务于"把 GUI 长相对出来"。

const T0 := 760.8

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

var tracks: Array[Dictionary] = []
var log_lines: Array[Dictionary] = []
var unit: Dictionary = {}

func _init() -> void:
	_build_sensors()
	_build_tracks()
	_build_log()
	_build_unit()

func _build_sensors() -> void:
	sensors = [
		{"mfr": "远地点号", "model": "S-07", "mode": "舰载战斗系统", "sig": "SYNC 1.0s", "glyph": "ring", "color": "#8CF0C0"},
		{"mfr": "沙克尔顿租界", "model": "听-3", "mode": "被动红外", "sig": "STARE ∞", "glyph": "web", "color": "#E8A34B"},
		{"mfr": "签约国", "model": "R-9", "mode": "主动雷达", "sig": "SWEEP 6s", "glyph": "hex", "color": "#8CF0C0"},
		{"mfr": "外权地", "model": "光学", "mode": "光学凝视", "sig": "MAG 8×", "glyph": "frame", "color": "#7FB6C9"},
		{"mfr": "签约国", "model": "MK-12", "mode": "敌我识别", "sig": "PULSE 2s", "glyph": "gate", "color": "#8CF0C0"},
		{"mfr": "天平动", "model": "ELINT", "mode": "通信截听", "sig": "SNIFF", "glyph": "jag", "color": "#E2564A"}
	]

func _build_tracks() -> void:
	tracks = [
		{
			"id": "哈马丹", "en": "HAMADAN", "cls": "砧级", "role": "炮舰",
			"side": "friend", "level": 4, "bearing": 0.0, "range": 0.0, "alt": 0.0,
			"closing": 0.0, "age": 0.0, "own": true, "off": Vector2(16, 14)
		},
		{
			"id": "背风岸", "en": "LEEWARD", "cls": "听级", "role": "哨舰",
			"side": "friend", "level": 4, "bearing": 356.0, "range": 44.0, "alt": 3.0,
			"closing": -0.1, "age": 1.0, "off": Vector2(-72, -20)
		},
		{
			"id": "长夜", "en": "LONGNIGHT", "cls": "塔级", "role": "中继舰",
			"side": "friend", "level": 4, "bearing": 12.0, "range": 96.0, "alt": 38.0,
			"closing": 0.2, "age": 1.0, "off": Vector2(16, -18)
		},
		{
			"id": "4471-K", "en": "RECEIVERSHIP", "cls": "代偿级", "role": "火力舰",
			"side": "hostile", "level": 3, "bearing": 41.0, "range": 318.0, "alt": 12.0,
			"closing": -4.2, "age": 2.0, "off": Vector2(-62, -38)
		},
		{
			"id": "4503-R", "en": "RECEIVERSHIP", "cls": "传票级", "role": "送达舰",
			"side": "hostile", "level": 2, "bearing": 38.0, "range": 402.0, "alt": -8.0,
			"closing": -1.1, "age": 5.0, "off": Vector2(20, 12)
		},
		{
			"id": "未识别", "en": "UNKNOWN", "cls": "未识别", "role": "接触",
			"side": "unknown", "level": 1, "bearing": 118.0, "range": 260.0, "alt": -6.0,
			"closing": 0.0, "age": 12.0, "off": Vector2(16, 12)
		},
		{
			"id": "未识别", "en": "UNKNOWN", "cls": "仅方位", "role": "陈旧接触",
			"side": "unknown", "level": 1, "bearing": 302.0, "range": 340.0, "alt": 0.0,
			"closing": 0.0, "age": 41.0, "stale": true, "bearing_only": true,
			"off": Vector2(-120, -26)
		},
		{
			"id": "幽影", "en": "GHOST TRACK", "cls": "未归档", "role": "幽影航迹",
			"side": "ghost", "level": 0, "bearing": 128.0, "range": 470.0, "alt": 4.0,
			"closing": 0.0, "age": 9.0, "ghost": true, "off": Vector2(-100, -26)
		}
	]

func _build_log() -> void:
	log_lines = [
		{"t": "12:31.4", "text": "TRANSFER 哈马丹 → 节点 B-2", "arg": "Δv 84", "status": "PENDING"},
		{"t": "12:28.0", "text": "EMCON 静默 · 雷达关机", "arg": "", "status": "EXEC"},
		{"t": "12:19.3", "text": "火控请求 → 4471-K", "arg": "ROE 拒绝", "status": "HOLD"},
		{"t": "12:04.8", "text": "传感器：被动红外 / 光学", "arg": "", "status": "EXEC"},
		{"t": "11:52.1", "text": "接收 接管通知 4471 号 · 回执已发", "arg": "", "status": "RX"}
	]

func _build_unit() -> void:
	unit = {
		"name": "哈马丹", "en": "HAMADAN", "cls": "砧级", "role": "炮舰",
		"faction": "公约 · 监督官分遣队",
		"mass": "1,200 t", "crew": "68", "accel": "0.10 g",
		"orbit": "400 × 402 km", "inc": "28.5°", "period": "92.5 min",
		"dv": "2,840", "dv_max": "3,150",
		"systems": [["传感器", 0.92], ["火控", 0.88], ["推进", 0.76], ["通信", 0.64], ["反应堆", 0.97]],
		"weapons": [["轨道炮", "1 门 · 弹 180"], ["近防炮", "6 管 · 弹 2,400"], ["导弹", "—"]],
		"damage": "散热片 B 组损伤", "damage2": "输出 -18%"
	}
