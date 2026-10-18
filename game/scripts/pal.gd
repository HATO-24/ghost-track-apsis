class_name Pal
extends RefCounted

# Marathon FUI 色板：中性灰底盘 + 单一酸性绿 + 一个信号红。
# 不再用满屏绿字——绿色只给"被点亮"的东西。

static var BG := Color("#0B0D0B")
static var PANEL := Color("#17171D")
static var PANEL2 := Color("#212129")
static var PANEL3 := Color("#2A2A33")
static var LINE := Color("#33333E")
static var LINE2 := Color("#4A4A57")
static var PH := Color("#C0FE04")
static var PH_DIM := Color("#7C9E12")
static var PH_FAINT := Color("#3E4A16")
static var AMBER := Color("#E8A34B")
static var RED := Color("#FF003C")
static var BLUE := Color("#8FC7D8")
static var TXT := Color("#DFDEE0")
static var DIM := Color("#8E8E9A")
static var FAINT := Color("#5B5B66")
static var BEZEL := Color("#070809")
static var GRID := Color("#23232B")

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
