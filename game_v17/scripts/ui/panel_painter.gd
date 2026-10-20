extends RefCounted

# 方案B 统一 PanelPainter：1px 框 / 标题 / 分割线 / 内边距 / 按钮 / 目标牌 / 列表行。
# 所有绘制用 LayoutTokens + TextMetrics；不依赖旧 HUD/Control 样式。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")
const TM := preload("res://scripts/ui/text_metrics.gd")


static func panel(ci: CanvasItem, r: Rect2, title := "", accent: Color = P.PH) -> void:
	ci.draw_rect(r, P.a(P.PANEL, 0.96))
	ci.draw_rect(r, P.a(P.LINE2, 0.55), false, 1.0)
	if title != "":
		ci.draw_string(F.cjk(), Vector2(r.position.x + 12, r.position.y + 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, accent)
		ci.draw_line(Vector2(r.position.x + 10, r.position.y + 26), Vector2(r.end.x - 10, r.position.y + 26), P.a(P.LINE, 0.8), 1.0)


static func sub_panel(ci: CanvasItem, r: Rect2, label := "", accent: Color = P.PH_DIM) -> void:
	ci.draw_rect(r, P.a(P.PANEL2, 0.55))
	ci.draw_rect(r, P.a(P.LINE, 0.6), false, 1.0)
	if label != "":
		ci.draw_string(F.cjk(), Vector2(r.position.x + 8, r.position.y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, accent)


static func divider(ci: CanvasItem, x1: float, y: float, x2: float, col: Color = P.a(P.LINE, 0.8)) -> void:
	ci.draw_line(Vector2(x1, y), Vector2(x2, y), col, 1.0)


static func label(ci: CanvasItem, x: float, y: float, text: String, size := 9, col: Color = P.TXT, mono := false) -> void:
	ci.draw_string(F.mono() if mono else F.cjk(), Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func label_right(ci: CanvasItem, right_x: float, y: float, text: String, size := 9, col: Color = P.DIM, mono := true) -> void:
	ci.draw_string(F.mono() if mono else F.cjk(), Vector2(TM.align_right(text, right_x, mono, size), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func button(ci: CanvasItem, r: Rect2, text: String, active := true, col: Color = P.PH) -> void:
	ci.draw_rect(r, P.a(P.PANEL2, 0.9))
	ci.draw_rect(r, P.a(col if active else P.LINE, 0.65 if active else 0.35), false, 1.0)
	var w := TM.width(text, false, 8)
	ci.draw_string(F.cjk(), Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + r.size.y * 0.5 + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, P.TXT if active else P.FAINT)


static func list_row(ci: CanvasItem, r: Rect2, title: String, meta: String, type_col: Color, selected := false) -> void:
	ci.draw_rect(r, P.a(type_col, 0.12 if selected else 0.045))
	ci.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), P.a(type_col, 0.9 if selected else 0.35))
	ci.draw_rect(r, P.a(type_col if selected else P.LINE, 0.55 if selected else 0.25), false, 1.0)
	label(ci, r.position.x + 8, r.position.y + 13, TM.fit(title, r.size.x - 20, false, 9), 9, P.TXT if selected else P.DIM)
	label_right(ci, r.end.x - 8, r.position.y + 12, meta, 7, P.a(type_col, 0.9))


static func target_card(ci: CanvasItem, r: Rect2, title: String, sub: String, type_col: Color) -> void:
	ci.draw_rect(r, P.a(P.PANEL2, 0.7))
	ci.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), P.a(type_col, 0.8))
	label(ci, r.position.x + 8, r.position.y + 14, TM.fit(title, r.size.x - 16, false, 8), 8, P.TXT)
	label(ci, r.position.x + 8, r.position.y + 27, TM.fit(sub, r.size.x - 16, true, 7), 7, P.a(P.DIM, 0.9))
	ci.draw_rect(r, P.a(type_col, 0.45), false, 1.0)


static func key_value(ci: CanvasItem, x: float, y: float, right: float, key: String, value: String, val_col: Color = P.TXT) -> void:
	label(ci, x, y, key, 8, P.a(P.FAINT, 0.95))
	label_right(ci, right, y, value, 8, val_col, true)


static func section(ci: CanvasItem, x: float, y: float, right: float, title: String) -> void:
	label(ci, x, y, title, 8, P.PH_DIM)
	divider(ci, x, y + 4, right, P.a(P.LINE, 0.55))
