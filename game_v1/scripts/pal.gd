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

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
