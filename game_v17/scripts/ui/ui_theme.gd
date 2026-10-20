extends RefCounted

# 阶段1A UI 壳主题：V1 色板 + 终端字体 + 程序化 9-Slice 面板。
# 不依赖旧 HUD/Theme；新 Control 壳统一使用本文件。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")


static func build() -> Theme:
	var th := Theme.new()
	th.default_font = F.cjk()
	th.default_font_size = 12
	th.set_color("font_color", "Label", P.TXT)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	for type_name in ["PanelContainer", "Panel"]:
		th.set_stylebox("panel", String(type_name), panel_style())
	th.set_stylebox("normal", "Button", button_style(false))
	th.set_stylebox("hover", "Button", button_style(true))
	th.set_stylebox("pressed", "Button", button_style(true))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", P.PH_DIM)
	th.set_color("font_hover_color", "Button", P.PH)
	th.set_color("font_pressed_color", "Button", P.AMBER)
	th.set_font_size("font_size", "Button", 10)
	th.set_color("font_color", "RichTextLabel", P.DIM)
	th.set_font_size("normal_font_size", "RichTextLabel", 11)
	return th


static func nine_slice_texture() -> ImageTexture:
	# 24×24 程序化边框：2px 外框 + 内孔；StyleBoxTexture 以 8px 边距 9-slice 拉伸。
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(P.a(P.PANEL, 0.96))
	for x in range(24):
		for y in range(24):
			var edge := x <= 1 or y <= 1 or x >= 22 or y >= 21
			if edge:
				img.set_pixel(x, y, P.a(P.LINE2, 0.85))
			elif x == 2 or y == 2 or x == 21 or y == 20:
				img.set_pixel(x, y, P.a(P.LINE, 0.55))
			elif x in [4, 19] and y in [4, 19]:
				img.set_pixel(x, y, P.a(P.PH_FAINT, 0.55))
	return ImageTexture.create_from_image(img)


static func panel_style() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = nine_slice_texture()
	sb.texture_margin_left = 8.0
	sb.texture_margin_right = 8.0
	sb.texture_margin_top = 8.0
	sb.texture_margin_bottom = 8.0
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func button_style(hot: bool) -> StyleBoxTexture:
	var sb := panel_style()
	sb.modulate_color = P.a(P.PH if hot else P.PH_DIM, 0.9)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


static func make_label(text: String, mono := false, size := 11, color: Color = P.TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F.mono() if mono else F.cjk())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
