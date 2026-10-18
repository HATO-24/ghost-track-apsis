class_name WarState
extends RefCounted

const T0 := 62.0 * 3600.0 + 14.0 * 60.0 + 8.0

var clock := T0
var time_scale := 60.0
var paused := false
var capture := false
var elapsed := 0.0
var boot_t := 0.0
var grace_left := 62.0 * 3600.0 + 18.0 * 60.0 + 44.0
var selected := 0
var sensor := 0
var sensors: Array[Dictionary] = []
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
		{"mfr": "远地点船坞", "model": "CCS-7", "mode": "综合战斗系统", "sig": "SYNC 1.0s", "glyph": "ring", "color": "#C0FE04"},
		{"mfr": "铁砧重工", "model": "R-9", "mode": "主动雷达", "sig": "SWEEP 6s", "glyph": "hex", "color": "#C0FE04"},
		{"mfr": "北辰光学", "model": "听-3", "mode": "被动红外", "sig": "STARE ∞", "glyph": "web", "color": "#E8A34B"},
		{"mfr": "白霜仪器", "model": "M-2", "mode": "光学凝视", "sig": "MAG 8×", "glyph": "frame", "color": "#8FC7D8"},
		{"mfr": "静默通信", "model": "MK-12", "mode": "敌我识别", "sig": "PULSE 2s", "glyph": "gate", "color": "#C0FE04"},
		{"mfr": "天平动船坞", "model": "N-4", "mode": "电子战", "sig": "NOISE", "glyph": "jag", "color": "#FF003C"}
	]

func _build_tracks() -> void:
	tracks = [
		{
			"id": "远地点", "en": "APSIS", "cls": "母舰", "role": "船坞舰",
			"side": "friend", "level": 4, "bearing": 0.0, "range": 0.0, "alt": 0.0,
			"closing": 0.0, "age": 0.0, "own": true, "off": Vector2(18, 16),
			"pos": Vector3(192000, 0, 12000)
		},
		{
			"id": "哈马丹", "en": "HAMADAN", "cls": "砧级", "role": "炮舰",
			"side": "friend", "level": 4, "bearing": 0.0, "range": 2100.0, "alt": 180.0,
			"closing": 0.1, "age": 1.0, "off": Vector2(16, -20),
			"pos": Vector3(192000, 2100, 12180)
		},
		{
			"id": "背风岸", "en": "LEEWARD", "cls": "听级", "role": "哨舰",
			"side": "friend", "level": 4, "bearing": 112.0, "range": 2640.0, "alt": -90.0,
			"closing": -0.1, "age": 1.0, "off": Vector2(-88, -20),
			"pos": Vector3(194448, -988, 11910)
		},
		{
			"id": "长夜", "en": "LONGNIGHT", "cls": "塔级", "role": "中继舰",
			"side": "friend", "level": 4, "bearing": 75.0, "range": 4200.0, "alt": 1800.0,
			"closing": 0.2, "age": 1.0, "off": Vector2(16, -18),
			"pos": Vector3(196057, 1087, 13800)
		},
		{
			"id": "4471-K", "en": "RECEIVERSHIP", "cls": "代偿级", "role": "火力舰",
			"side": "hostile", "level": 3, "bearing": 86.0, "range": 160400.0, "alt": 1000.0,
			"closing": -4.2, "age": 2.0, "off": Vector2(18, -30),
			"pos": Vector3(352000, 12000, 13000)
		},
		{
			"id": "4503-R", "en": "RECEIVERSHIP", "cls": "传票级", "role": "送达舰",
			"side": "hostile", "level": 2, "bearing": 93.0, "range": 173200.0, "alt": -800.0,
			"closing": -1.1, "age": 5.0, "off": Vector2(16, -30),
			"pos": Vector3(365000, -9000, 11200)
		},
		{
			"id": "未识别", "en": "UNKNOWN", "cls": "未识别", "role": "接触",
			"side": "unknown", "level": 1, "bearing": 60.0, "range": 78900.0, "alt": 2400.0,
			"closing": 0.0, "age": 12.0, "off": Vector2(18, 12),
			"pos": Vector3(260000, 40000, 14400)
		},
		{
			"id": "幽影", "en": "GHOST TRACK", "cls": "未归档", "role": "幽影航迹",
			"side": "ghost", "level": 0, "bearing": 117.0, "range": 132400.0, "alt": 5000.0,
			"closing": 0.0, "age": 9.0, "ghost": true, "off": Vector2(-108, -26),
			"pos": Vector3(310000, -60000, 17000)
		}
	]

func _build_log() -> void:
	log_lines = [
		{"t": "62:13.8", "text": "SENSOR 下拉 → 远地点 CCS-7", "arg": "SYNC", "status": "EXEC"},
		{"t": "62:11.2", "text": "TRANSFER 哈马丹 → 节点 B-2", "arg": "Δv 84", "status": "PENDING"},
		{"t": "62:06.5", "text": "ELINT 截获 清算署 窄带信号", "arg": "方位 086°", "status": "RX"},
		{"t": "61:58.0", "text": "光学凝视 4471-K · 目标级 L3", "arg": "12.4s", "status": "EXEC"},
		{"t": "61:44.3", "text": "接收 接管通知 4471 号 · 回执已发", "arg": "", "status": "RX"}
	]

func _build_unit() -> void:
	unit = {
		"name": "远地点", "en": "APSIS", "cls": "母舰", "role": "船坞舰",
		"faction": "公约 · 监督官旗舰",
		"mass": "9,000 t", "crew": "240", "accel": "0.02 g",
		"orbit": "地月转移 · T+62h", "inc": "—", "period": "—",
		"dv": "1,420", "dv_max": "3,150",
		"systems": [["传感器", 0.86], ["火控", 0.34], ["推进", 0.58], ["通信", 0.91], ["反应堆", 0.94]],
		"weapons": [["近防炮", "4 管 · 弹 1,200"], ["舰载艇", "2 艘"], ["导弹", "—"]],
		"damage": "船坞 2/2 可用", "damage2": "无损伤"
	}

