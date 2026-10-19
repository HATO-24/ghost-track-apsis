class_name V2Actions
extends RefCounted

# 动作注册表：动作定义来自数据；可用性由能力、目标等级、距离共同决定。
# 这里只保留框架必需的默认动作，后续 content/actions/*.json 可覆盖/扩展。
const DEFAULT_ACTIONS := [
	{"id": "crossfix", "label": "交叉定位", "requires": [], "levels": [1], "unsupported": false},
	{"id": "radar_illum", "label": "雷达照射识别", "requires": ["sensor.radar.active"], "levels": [1, 2], "unsupported": false},
	{"id": "model_ident", "label": "型号识别", "requires": ["sensor.optical"], "levels": [2], "unsupported": false},
	{"id": "radar_track", "label": "雷达跟踪", "requires": ["sensor.radar.active"], "levels": [3], "unsupported": false},
	{"id": "iff_query", "label": "IFF 问答", "requires": ["sensor.iff.interrogator"], "levels": [3], "unsupported": false},
	{"id": "optical_channel", "label": "光学通道", "requires": ["sensor.optical"], "levels": [3], "unsupported": false},
	{"id": "ir_channel", "label": "红外通道", "requires": ["sensor.ir"], "levels": [3], "unsupported": false},
	{"id": "fire_control", "label": "火控解算", "requires": ["weapon.firecontrol"], "levels": [4], "unsupported": true},
	{"id": "missile_solve", "label": "导弹路径解算", "requires": ["weapon.missile"], "levels": [4], "unsupported": true},
	{"id": "weapons_hold", "label": "武装待命", "requires": ["weapon.armed"], "levels": [4], "unsupported": true},
]

static func actions_for(actor: V2Entity, target: V2Entity) -> Array:
	var out: Array = []
	for raw in DEFAULT_ACTIONS:
		var a: Dictionary = (raw as Dictionary).duplicate(true)
		var available := true
		var reason := ""
		if a.unsupported:
			available = false
			reason = "未实现（无武器系统）"
		elif not int(a.levels[0]) <= target.track_level:
			available = false
			reason = "需 L%d 识别（当前 L%d）" % [int(a.levels[0]), target.track_level]
		else:
			for req in (a.requires as Array):
				if not actor.has(String(req)):
					available = false
					reason = "缺少能力：" + String(req)
					break
		a["available"] = available
		a["reason"] = reason
		out.append(a)
	return out

static func find(actions: Array, aid: String) -> Dictionary:
	for raw in actions:
		var a: Dictionary = raw
		if String(a.get("id", "")) == aid:
			return a
	return {}

static func level_name(level: int) -> String:
	return ["L0", "L1", "L2", "L3", "L4"][clampi(level, 0, 4)]
