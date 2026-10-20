extends RefCounted

# 方案B 文本测量器：CJK/等宽宽度、行高、基线、椭圆省略。
# 由 LayoutTokens 提供字号；不改变字体资源。

const F := preload("res://scripts/fonts.gd")
const Tokens := preload("res://scripts/ui/layout_tokens.gd")

static var _cache: Dictionary = {}


static func font(mono: bool) -> Font:
	return F.mono() if mono else F.cjk()


static func width(text: String, mono := false, size := 9) -> float:
	var key := "%s|%s|%d" % ["m" if mono else "c", text, size]
	if _cache.has(key):
		return float(_cache[key])
	var w := font(mono).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if _cache.size() > 4000:
		_cache.clear()
	_cache[key] = w
	return w


static func line_height(size := 9) -> float:
	return Tokens.new().line_height(size)


static func baseline(size := 9) -> float:
	return Tokens.new().baseline(size)


static func fit(text: String, max_width: float, mono := false, size := 9) -> String:
	if width(text, mono, size) <= max_width:
		return text
	var ell := "…"
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi) / 2
		if width(text.substr(0, mid) + ell, mono, size) <= max_width:
			lo = mid + 1
		else:
			hi = mid
	return text.substr(0, maxi(0, lo - 1)) + ell


static func pad(text: String, width_chars: int, mono := true, size := 9) -> String:
	var cur := text
	while width(cur, mono, size) < width(" ", mono, size) * width_chars:
		cur += " "
	return cur


static func align_right(text: String, right_x: float, mono := false, size := 9) -> float:
	return right_x - width(text, mono, size)


static func clear_cache() -> void:
	_cache.clear()
