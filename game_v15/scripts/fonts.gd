class_name UiFonts
extends RefCounted

static var _mono: Font
static var _cjk: Font

static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Courier New"])
		_mono = f
	return _mono

static func cjk() -> Font:
	if _cjk == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei"])
		_cjk = f
	return _cjk

static func has_cjk(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) > 0x2E80:
			return true
	return false
