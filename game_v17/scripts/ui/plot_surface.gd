extends Control

# 独立裁剪层：战术图只允许画在这个 Control 内，防止线框/标签溢出到侧栏。
var host: Node = null


func _draw() -> void:
	if host != null and host.has_method("_draw_plot_surface"):
		host._draw_plot_surface(self)
