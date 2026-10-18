class_name Pal
extends RefCounted

# 终端色板：磷光绿 / 冰蓝 / 琥珀 / 朱红，只保留四种色相。

static var BG := Color("#06100D")
static var EARTH := Color("#08181B")
static var PANEL := Color("#0A1713")
static var PANEL2 := Color("#10221C")
static var LINE := Color("#1D4438")
static var LINE2 := Color("#34735D")
static var PH := Color("#8CF0C0")
static var PH_DIM := Color("#4E8F76")
static var PH_FAINT := Color("#2A5546")
static var AMBER := Color("#E8A34B")
static var RED := Color("#E2564A")
static var BLUE := Color("#7FB6C9")
static var TXT := Color("#CFE9DB")
static var DIM := Color("#7FA995")
static var FAINT := Color("#527868")
static var BEZEL := Color("#0A0C0B")
static var GRID := Color("#1E4A42")

# P1j：身份分类色（19 §2.5）——颜色之外还有形状，色盲友好。
static var ID_PENDING := Color("#8B9A92")      # 待定：灰
static var ID_UNKNOWN := Color("#E8A34B")      # 未知：琥珀
static var ID_ASSUMED := Color("#9BC7D8")      # 假定友好：浅蓝
static var ID_FRIEND := Color("#8CF0C0")       # 友方：薄荷绿
static var ID_NEUTRAL := Color("#93A98F")      # 中立：灰绿
static var ID_SUSPECT := Color("#E8843B")      # 可疑：橙
static var ID_HOSTILE := Color("#E2564A")      # 敌方：红

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
