extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段0：UI token 查询器（新文件；供后续 UI 使用，不实现 UI）
#
# - 读取 config/ui_tokens.json（版本化：字体/字号档位/行高/CJK+等宽基线/内边距/行距/
#   色板/面板 9-slice/按钮/目标牌/列表/弹窗/指针）；
# - 查询：size/padding/line_height/baseline/color/rect/margin/font/value；
# - 未知 token：push_error + errors 记录（不静默）；返回安全默认。
# ═══════════════════════════════════════════════════════════════════

const TOKENS_PATH := "res://config/ui_tokens.json"
const TOKENS_SCHEMA := "v17.ui_tokens.v1"
const VERSION_PATTERN := "^\\d+\\.\\d+\\.\\d+$"
const REQUIRED_SECTIONS := ["font_files", "font_sizes", "line_heights", "baselines",
	"spacing", "palette", "panel_9slice", "button", "target_card", "list", "dialog",
	"pointer"]
const SIZE_KEYS := ["7", "8", "9", "11", "14", "18"]

var path := TOKENS_PATH
var data: Dictionary = {}
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var last_error := ""
var version := ""

func _init(token_path := TOKENS_PATH) -> void:
	load_path(token_path)

func load_path(token_path := TOKENS_PATH) -> bool:
	path = token_path
	data = {}
	errors.clear()
	warnings.clear()
	last_error = ""
	version = ""
	ready = false
	if not FileAccess.file_exists(token_path):
		_append_error("ui_tokens 文件不存在：" + token_path)
		return false
	var text := FileAccess.get_file_as_string(token_path)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_append_error("ui_tokens JSON 无效：" + token_path)
		return false
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != TOKENS_SCHEMA:
		_append_error("ui_tokens schema 必须为 " + TOKENS_SCHEMA)
	version = String(d.get("version", ""))
	if not _version_ok(version):
		_append_error("ui_tokens version 非法：'%s'" % version)
	for key in REQUIRED_SECTIONS:
		if not d.has(key):
			_append_error("ui_tokens 缺少节：" + key)
	if d.get("font_files") is Dictionary:
		var ff: Dictionary = d.get("font_files", {})
		for k in ["sans", "mono", "cjk"]:
			if String(ff.get(k, "")) == "":
				_append_error("font_files.%s 为空" % k)
	if d.get("font_sizes") is Dictionary:
		var fs: Dictionary = d.get("font_sizes", {})
		for k in SIZE_KEYS:
			if not fs.has(k):
				_append_error("font_sizes 缺档位：" + k)
			elif int(fs.get(k, 0)) != int(k):
				_append_error("font_sizes.%s=%s（应为 %s）" % [k, str(fs.get(k, 0)), k])
	if d.get("line_heights") is Dictionary:
		var lh: Dictionary = d.get("line_heights", {})
		for k in SIZE_KEYS:
			if not lh.has(k):
				_append_error("line_heights 缺档位：" + k)
			elif int(lh.get(k, 0)) <= int(k):
				_append_error("line_heights.%s 必须大于字号" % k)
	if d.get("palette") is Dictionary:
		var pal: Dictionary = d.get("palette", {})
		for k in pal.keys():
			if Color.from_string(String(pal.get(k, "")), Color.TRANSPARENT) == Color.TRANSPARENT \
					and String(pal.get(k, "")).to_upper() != "#00000000":
				_append_error("palette.%s 颜色非法：%s" % [k, String(pal.get(k, ""))])
	if d.get("panel_9slice") is Dictionary:
		var sl: Dictionary = d.get("panel_9slice", {})
		for k in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			if not sl.has(k) or int(sl.get(k, 0)) < 0:
				_append_error("panel_9slice.%s 必须 >=0" % k)
	for pair in [["button", "height"], ["list", "row_height"], ["dialog", "padding"],
			["pointer", "size"], ["target_card", "width"], ["target_card", "height"]]:
		var sec := String(pair[0])
		var field := String(pair[1])
		if d.get(sec) is Dictionary:
			if not (d.get(sec) as Dictionary).has(field):
				_append_error("%s.%s 缺失" % [sec, field])
	if d.get("baselines") is Dictionary:
		var bl: Dictionary = d.get("baselines", {})
		for k in ["cjk_font_size", "mono_font_size", "cjk_baseline_px", "mono_baseline_px"]:
			if not bl.has(k):
				_append_error("baselines.%s 缺失" % k)
	data = d.duplicate(true)
	ready = errors.is_empty()
	return ready

# ── 通用查询 ────────────────────────────────────────────────────

## 点路径查询（如 "button.height"、"palette.text"）；未知 token 报错并返回 fallback。
func value(path_key: String, fallback = null) -> Variant:
	if data.is_empty():
		_append_error("ui_tokens 未加载")
		return fallback
	var parts := path_key.split(".")
	var cur: Variant = data
	for raw_part in parts:
		var part := String(raw_part)
		if cur is Dictionary:
			var d: Dictionary = cur
			if not d.has(part):
				_append_error("unknown token: " + path_key)
				return fallback
			cur = d[part]
		elif cur is Array:
			var arr: Array = cur
			if not part.is_valid_int():
				_append_error("unknown token(index): " + path_key)
				return fallback
			var idx := int(part)
			if idx < 0 or idx >= arr.size():
				_append_error("unknown token(index): " + path_key)
				return fallback
			cur = arr[idx]
		else:
			_append_error("unknown token: " + path_key)
			return fallback
	return cur

func has(path_key: String) -> bool:
	var before := errors.size()
	var v = value(path_key, null)
	if errors.size() > before:
		errors.resize(before)
		last_error = ""
		return false
	return v != null

# ── 语义查询 ────────────────────────────────────────────────────

func font(name := "sans") -> String:
	return String(value("font_files." + name, ""))

func size(token: String) -> int:
	return int(value("icons." + token, 0)) if has("icons." + token) else int(value("font_sizes." + token, 0))

func font_size(size_key := "11") -> int:
	return int(value("font_sizes." + str(size_key), 0))

func line_height(size_key := "11") -> int:
	return int(value("line_heights." + str(size_key), 0))

## CJK / 等宽基线（px）；kind=cjk|mono。
func baseline(kind := "cjk") -> float:
	var key := kind + "_baseline_px"
	if not data.get("baselines", {}).has(key):
		_append_error("unknown baseline kind: " + kind)
		return 0.0
	return float(value("baselines." + key, 0.0))

func line_gap(kind := "cjk") -> int:
	var key := kind + "_line_gap_px"
	if not data.get("baselines", {}).has(key):
		_append_error("unknown line_gap kind: " + kind)
		return 0
	return int(value("baselines." + key, 0))

## 内边距：panel/button/card/dialog/list 或 spacing.<name>。
func padding(name := "panel") -> Vector2:
	match name:
		"panel":
			return Vector2(float(value("spacing.panel_padding_x", 0.0)),
				float(value("spacing.panel_padding_y", 0.0)))
		"button":
			return Vector2(float(value("button.padding_x", 0.0)),
				float(value("button.padding_y", 0.0)))
		"card":
			return Vector2(float(value("target_card.padding", 0.0)),
				float(value("target_card.padding", 0.0)))
		"dialog":
			var pad := float(value("dialog.padding", 0.0))
			return Vector2(pad, pad)
		"list":
			var px := float(value("list.padding_x", 0.0))
			return Vector2(px, px)
		_:
			return Vector2(float(value("spacing." + name, 0.0)),
				float(value("spacing." + name, 0.0)))

func color(name := "text") -> Color:
	var hex := String(value("palette." + name, ""))
	if hex == "":
		return Color.TRANSPARENT
	var c := Color.from_string(hex, Color.TRANSPARENT)
	if c == Color.TRANSPARENT and hex.to_upper() != "#00000000":
		_append_error("palette color 非法：palette." + name)
	return c

## 矩形：target_card/dialog/button/icon_small/icon_normal/icon_large。
func rect(name := "target_card") -> Rect2:
	match name:
		"target_card":
			return Rect2(0.0, 0.0, float(value("target_card.width", 0.0)),
				float(value("target_card.height", 0.0)))
		"dialog":
			return Rect2(0.0, 0.0, float(value("dialog.min_width", 0.0)),
				float(value("dialog.min_height", 0.0)))
		"button":
			return Rect2(0.0, 0.0, float(value("button.min_width", 0.0)),
				float(value("button.height", 0.0)))
		"icon_small", "icon_normal", "icon_large":
			var key := "icons.size_" + name.replace("icon_", "")
			if not has(key):
				_append_error("unknown rect token: " + name)
				return Rect2()
			var s := float(value(key, 0.0))
			return Rect2(0.0, 0.0, s, s)
		_:
			_append_error("unknown rect token: " + name)
			return Rect2()

func margin(name := "margin_left") -> int:
	if not has("panel_9slice." + name):
		_append_error("unknown margin token: " + name)
		return 0
	return int(value("panel_9slice." + name, 0))

func all() -> Dictionary:
	return data.duplicate(true)

func to_dict() -> Dictionary:
	return {
		"schema": "v17.ui_tokens_loader.v1",
		"path": path,
		"ready": ready,
		"version": version,
		"tokens": data.duplicate(true),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}

func reset() -> void:
	data = {}
	ready = false
	version = ""
	errors.clear()
	warnings.clear()
	last_error = ""

# ── 内部 ────────────────────────────────────────────────────────

func _append_error(msg: String) -> void:
	last_error = msg
	errors.append(msg)
	push_error("ui_tokens: " + msg)

func _version_ok(v: String) -> bool:
	var re := RegEx.new()
	re.compile(VERSION_PATTERN)
	return re.search(v) != null
