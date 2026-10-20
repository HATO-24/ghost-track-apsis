extends RefCounted

# 方案B 统一布局 token：读取 config/ui_tokens.json（缺失用同值回退）。
# 自绘 HUD 的所有面板 rect/字号/行高/基线/padding/gap 都从这里取；V1 色板单独固定。
# 不依赖旧 HUD/Control 壳。

const P := preload("res://scripts/pal.gd")
const F := preload("res://scripts/fonts.gd")
const TOKEN_PATH := "res://config/ui_tokens.json"

const FALLBACK := {
	"font_sizes": {"7": 7, "8": 8, "9": 9, "11": 11, "14": 14, "18": 18},
	"line_heights": {"7": 10, "8": 11, "9": 12, "11": 15, "14": 19, "18": 24},
	"baselines": {"cjk_baseline_px": 3.0, "mono_baseline_px": 2.0, "cjk_line_gap_px": 2, "mono_line_gap_px": 1},
	"spacing": {"panel_padding_x": 12, "panel_padding_y": 10, "content_gap": 6, "line_gap": 2, "section_gap": 10},
	"button": {"height": 28, "min_width": 88, "padding_x": 10, "padding_y": 4, "font_size": 11},
	"target_card": {"width": 180, "height": 44, "padding": 6, "font_size": 9},
	"list": {"row_height": 20, "header_height": 24, "padding_x": 6, "font_size": 9},
	"dialog": {"padding": 14, "min_width": 360, "min_height": 220, "font_size": 11},
	"pointer": {"size": 10, "hotspot_x": 5, "hotspot_y": 5},
}

var V1_COLORS := {
	"bg": P.BG, "panel": P.PANEL, "panel2": P.PANEL2, "line": P.LINE, "line2": P.LINE2,
	"text": P.TXT, "dim": P.DIM, "faint": P.FAINT, "ph": P.PH, "ph_dim": P.PH_DIM,
	"ph_faint": P.PH_FAINT, "amber": P.AMBER, "red": P.RED, "blue": P.BLUE,
	"earth": P.EARTH, "selection": P.a(P.PH, 0.10), "transparent": P.a(P.BG, 0.0),
}

var data: Dictionary = {}
var loaded_path := ""


func _init(path := TOKEN_PATH) -> void:
	data = FALLBACK.duplicate(true)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				data = (parsed as Dictionary).duplicate(true)
				loaded_path = path
	# 缺键回退
	for k in FALLBACK.keys():
		if not data.has(k):
			data[k] = (FALLBACK[k] as Dictionary).duplicate(true)


func size(name: Variant) -> int:
	var key := str(name)
	var fs: Dictionary = data.get("font_sizes", {})
	return int(fs.get(key, int(key) if key.is_valid_int() else 9))


func line_height(name: Variant) -> float:
	var key := str(name)
	var lh: Dictionary = data.get("line_heights", {})
	if lh.has(key):
		return float(lh[key])
	var s := size(name)
	return float(s) * 1.35


func baseline(font_size: Variant) -> float:
	var b: Dictionary = data.get("baselines", {})
	var s := size(font_size)
	var px := float(b.get("cjk_baseline_px" if F.has_cjk("字") else "mono_baseline_px", 2.0))
	return float(s) + px


func padding(key := "panel_padding_x") -> float:
	var sp: Dictionary = data.get("spacing", {})
	return float(sp.get(key, 10))


func gap(key := "content_gap") -> float:
	var sp: Dictionary = data.get("spacing", {})
	return float(sp.get(key, 6))


func metric(group: String, key: String, fallback := 0.0) -> float:
	var g: Dictionary = data.get(group, {}) if data.get(group) is Dictionary else {}
	return float(g.get(key, fallback))


func color(name: String) -> Color:
	return V1_COLORS.get(name, P.TXT) as Color


## 按视口计算五区，不写死面板坐标。
func layout(w: float, h: float) -> Dictionary:
	var m := 16.0
	var gap := gap("content_gap")
	var top_h := 72.0
	var bottom_h := 132.0
	var left_w := clampf(roundf(w * 0.166), 286.0, 340.0)
	var right_w := clampf(roundf(w * 0.18), 300.0, 360.0)
	var body_y := m + top_h + 8.0
	var body_h := h - body_y - bottom_h - m - 8.0
	var x0 := m
	var x1 := x0 + left_w + gap
	var x2 := w - m - right_w
	var center_w := maxf(120.0, x2 - gap - x1)
	return {
		"top": Rect2(m, m, w - m * 2.0, top_h),
		"left": Rect2(x0, body_y, left_w, body_h),
		"center": Rect2(x1, body_y, center_w, body_h),
		"right": Rect2(x2, body_y, right_w, body_h),
		"bottom": Rect2(m, h - m - bottom_h, w - m * 2.0, bottom_h),
		"gap": gap,
	}


func fonts() -> Dictionary:
	return {"cjk": F.cjk(), "mono": F.mono()}
