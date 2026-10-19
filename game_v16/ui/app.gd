extends Control

## V2 启动路由（V2-3 起默认进入第一关游戏屏）。
##
## - `DSH_V2_VIEW` = tactical|prelude|decision|report|end（或不设）→ `ui/game_screen.gd`
## - `DSH_V2_VIEW` = framework|target|menu|scroll|layout|empty|fallback|local
##   → `ui/framework_demo.gd`（V2-2 UI 框架演示屏，保留用于回归/截图）
##
## 两个屏都自己处理 DSH_V2_SHOT 截图与 headless 自检；本路由只负责实例化。

const L := preload("res://ui/layout.gd")
const GameScreen := preload("res://ui/game_screen.gd")
const FrameworkDemo := preload("res://ui/framework_demo.gd")
const IntroScreen := preload("res://ui/intro.gd")

const LEGACY_VIEWS := [
	"framework", "target", "menu", "scroll", "layout", "empty", "fallback", "local",
]


func _ready() -> void:
	var view := OS.get_environment("DSH_V2_VIEW")
	var screen: Control
	if view == "intro" or view == "menu" or view == "settings":
		screen = IntroScreen.new()
		print("V2 ROUTER → intro (DSH_V2_VIEW=%s)" % view)
	elif view in LEGACY_VIEWS:
		screen = FrameworkDemo.new()
		print("V2 ROUTER → framework_demo (DSH_V2_VIEW=%s)" % view)
	else:
		screen = GameScreen.new()
		print("V2 ROUTER → game_screen (DSH_V2_VIEW=%s)" % ("default" if view == "" else view))
	screen.position = Vector2.ZERO
	screen.size = L.DESIGN
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
