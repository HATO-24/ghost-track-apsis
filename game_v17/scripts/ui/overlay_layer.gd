extends Control

# 方案B-32：子界面（overlay）独立绘制层。
# 位于 plot_surface 之后加入，因此永远盖在战术图之上；clip_contents 保证弹层内容
# 不溢出到左侧接触栏/底栏。绘制使用局部坐标（原点=弹层左上角），调用方传入的
# Rect2 已归零，所以各 overlay 内部仍按 r.position/r.end 计算，不需要改坐标口径。
var host: Node = null


func _draw() -> void:
	if host != null and host.has_method("_draw_overlay_layer"):
		host._draw_overlay_layer(self)
