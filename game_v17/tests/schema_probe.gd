extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段0 最小 probe：UI token / 数据 schema / loader
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/schema_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接旧场景/HUD/UI。
# ═══════════════════════════════════════════════════════════════════

const UITokens := preload("res://scripts/core/ui_tokens.gd")
const SchemaLoader := preload("res://scripts/core/schema_loader.gd")

const TOKENS_PATH := "res://config/ui_tokens.json"
const SCHEMA_DIR := "res://config/schema"
const SCHEMA_IDS := ["entity", "time", "frame", "order", "comms",
	"sensor_observation", "track", "save", "story_state", "ui_field"]
const SIZE_KEYS := ["7", "8", "9", "11", "14", "18"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE0 PROBE · UI token / 数据 schema / loader")
	print("════════════════════════════════════════════════════════════")
	_test_token_file()
	_test_token_queries()
	_test_schema_files()
	_test_loader()
	_test_loader_rejections()
	_test_examples()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SCHEMA PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SCHEMA PROBE FAILED")
		quit(1)
	else:
		print("V17 SCHEMA PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _semver(v: String) -> bool:
	var parts := v.split(".")
	if parts.size() != 3:
		return false
	for p in parts:
		if not String(p).is_valid_int():
			return false
	return true

# ═══════════════════════════════════════════════════════════════════
# 1. UI token 文件
# ═══════════════════════════════════════════════════════════════════

func _test_token_file() -> void:
	_section_begin("1 UI token 文件")
	_ok(FileAccess.file_exists(TOKENS_PATH), "ui_tokens.json 存在")
	var parsed = _read_json(TOKENS_PATH)
	_ok(parsed is Dictionary, "ui_tokens JSON 可解析")
	var d: Dictionary = parsed if parsed is Dictionary else {}
	_eq(String(d.get("schema", "")), "v17.ui_tokens.v1", "ui tokens schema")
	_ok(_semver(String(d.get("version", ""))), "ui tokens version semver",
		String(d.get("version", "")))
	_ok(String(d.get("updated", "")) != "", "ui tokens updated")
	var ff: Dictionary = d.get("font_files", {}) if d.get("font_files") is Dictionary else {}
	for k in ["sans", "mono", "cjk"]:
		_ok(String(ff.get(k, "")) != "", "font_files." + k)
	var fs: Dictionary = d.get("font_sizes", {}) if d.get("font_sizes") is Dictionary else {}
	for k in SIZE_KEYS:
		_eq(int(fs.get(k, -1)), int(k), "font_sizes[" + k + "]")
	_eq(fs.size(), 6, "font_sizes 恰好 6 档")
	var lh: Dictionary = d.get("line_heights", {}) if d.get("line_heights") is Dictionary else {}
	for k in SIZE_KEYS:
		_ok(int(lh.get(k, 0)) > int(k), "line_heights[%s] > 字号" % k)
	var bl: Dictionary = d.get("baselines", {}) if d.get("baselines") is Dictionary else {}
	for k in ["cjk_font_size", "mono_font_size", "cjk_baseline_px", "mono_baseline_px"]:
		_ok(bl.has(k), "baselines." + k)
	_ok(float(bl.get("cjk_baseline_px", 0.0)) > 0.0, "cjk 基线 >0")
	_ok(float(bl.get("mono_baseline_px", 0.0)) > 0.0, "等宽基线 >0")
	var sp: Dictionary = d.get("spacing", {}) if d.get("spacing") is Dictionary else {}
	for k in ["panel_padding_x", "panel_padding_y", "content_gap", "line_gap", "section_gap"]:
		_ok(sp.has(k), "spacing." + k)
	var pal: Dictionary = d.get("palette", {}) if d.get("palette") is Dictionary else {}
	for k in ["bg", "panel", "panel_border", "text", "text_dim", "accent", "warn",
			"danger", "ok", "selection", "transparent"]:
		_ok(pal.has(k), "palette." + k)
		_ok(String(pal.get(k, "")).begins_with("#"), "palette %s 为 hex" % k)
	var sl: Dictionary = d.get("panel_9slice", {}) if d.get("panel_9slice") is Dictionary else {}
	for k in ["margin_left", "margin_top", "margin_right", "margin_bottom", "content_margin"]:
		_ok(int(sl.get(k, -1)) >= 0, "panel_9slice." + k)
	var btn: Dictionary = d.get("button", {}) if d.get("button") is Dictionary else {}
	_ok(int(btn.get("height", 0)) > 0, "button.height")
	_ok(int(btn.get("min_width", 0)) > 0, "button.min_width")
	var card: Dictionary = d.get("target_card", {}) if d.get("target_card") is Dictionary else {}
	_ok(int(card.get("width", 0)) > 0 and int(card.get("height", 0)) > 0, "target_card 尺寸")
	var list: Dictionary = d.get("list", {}) if d.get("list") is Dictionary else {}
	_ok(int(list.get("row_height", 0)) > 0, "list.row_height")
	var dlg: Dictionary = d.get("dialog", {}) if d.get("dialog") is Dictionary else {}
	_ok(int(dlg.get("padding", 0)) > 0, "dialog.padding")
	var ptr: Dictionary = d.get("pointer", {}) if d.get("pointer") is Dictionary else {}
	_ok(int(ptr.get("size", 0)) > 0, "pointer.size")
	_data_line("tokens_file", "schema/version/fonts/palette/9slice/button/card/list/dialog/pointer 齐全")

# ═══════════════════════════════════════════════════════════════════
# 2. UI token 查询 / 未知 token
# ═══════════════════════════════════════════════════════════════════

func _test_token_queries() -> void:
	_section_begin("2 UI token 查询")
	var ui = UITokens.new()
	_ok(ui.ready, "ui_tokens ready", str(ui.errors))
	_eq(ui.errors.size(), 0, "ui_tokens 无 errors")
	_eq(ui.version, "1.0.0", "ui_tokens.version")
	_ok(ui.font("sans").length() > 0, "font(sans)")
	_ok(ui.font("mono").length() > 0, "font(mono)")
	_ok(ui.font("cjk").length() > 0, "font(cjk)")
	for k in SIZE_KEYS:
		_eq(ui.font_size(k), int(k), "font_size(%s)" % k)
		_ok(ui.line_height(k) > int(k), "line_height(%s)" % k)
	_ok(ui.baseline("cjk") > 0.0, "baseline(cjk)")
	_ok(ui.baseline("mono") > 0.0, "baseline(mono)")
	_ok(ui.line_gap("cjk") >= 0, "line_gap(cjk)")
	var pp: Vector2 = ui.padding("panel")
	_ok(pp.x > 0 and pp.y > 0, "padding(panel)")
	var bp: Vector2 = ui.padding("button")
	_ok(bp.x > 0 and bp.y > 0, "padding(button)")
	var dp: Vector2 = ui.padding("dialog")
	_ok(dp.x == dp.y and dp.x > 0, "padding(dialog)")
	var cp: Vector2 = ui.padding("card")
	_ok(cp.x > 0, "padding(card)")
	var lp: Vector2 = ui.padding("list")
	_ok(lp.x > 0, "padding(list)")
	var text_color: Color = ui.color("text")
	_ok(text_color != Color.TRANSPARENT, "color(text) 非透明")
	_ok(ui.color("transparent").a == 0.0, "color(transparent) alpha=0")
	var card: Rect2 = ui.rect("target_card")
	_ok(card.size.x > 0 and card.size.y > 0, "rect(target_card)")
	var btn_rect: Rect2 = ui.rect("button")
	_ok(btn_rect.size.x > 0 and btn_rect.size.y > 0, "rect(button)")
	var dlg_rect: Rect2 = ui.rect("dialog")
	_ok(dlg_rect.size.x > 0 and dlg_rect.size.y > 0, "rect(dialog)")
	_ok(ui.rect("icon_normal").size.x > 0, "rect(icon_normal)")
	_ok(ui.margin("margin_left") >= 0, "margin(margin_left)")
	_ok(ui.has("palette.text"), "has(palette.text)")
	_ok(not ui.has("palette.no_such"), "has(未知) false")
	_eq(int(ui.value("button.height", -1)), int(ui.value("button.height", 0)),
		"value 点路径")
	# 未知 token 报错（不静默）
	var err_before: int = ui.errors.size()
	var bad_color: Color = ui.color("no_such_color")
	_ok(bad_color.a == 0.0, "未知 color 返回透明")
	_ok(ui.errors.size() > err_before, "未知 color 记录 error")
	_ok(ui.last_error.contains("unknown token") or ui.last_error.contains("unknown"), "last_error 说明未知 token",
		ui.last_error)
	var err2: int = ui.errors.size()
	_eq(ui.margin("no_such_margin"), 0, "未知 margin 返回 0")
	_ok(ui.errors.size() > err2, "未知 margin 记录 error")
	_eq(ui.rect("no_such_rect"), Rect2(), "未知 rect 返回空")
	_ok(ui.errors.size() > err2, "未知 rect 记录 error")
	_ok(ui.to_dict().get("ready") is bool, "to_dict.ready")
	_data_line("tokens_query", "size/padding/line_height/baseline/color/rect/margin + 未知报错")

# ═══════════════════════════════════════════════════════════════════
# 3. schema 文件
# ═══════════════════════════════════════════════════════════════════

func _test_schema_files() -> void:
	_section_begin("3 schema 文件")
	var files: Array = DirAccess.get_files_at(SCHEMA_DIR)
	_eq(files.size(), 10, "schema 文件数=10", str(files.size()))
	var seen := {}
	for raw in files:
		var name := String(raw)
		_ok(name.ends_with(".json"), "schema 文件扩展名: " + name)
		var path := SCHEMA_DIR.path_join(name)
		_ok(FileAccess.file_exists(path), "schema 存在: " + name)
		var parsed = _read_json(path)
		_ok(parsed is Dictionary, "schema 解析: " + name)
		if not (parsed is Dictionary):
			continue
		var s: Dictionary = parsed
		var sid := String(s.get("id", ""))
		_ok(sid != "", "schema id 非空: " + name)
		_ok(not seen.has(sid), "schema id 唯一: " + sid)
		seen[sid] = true
		_eq(String(s.get("schema", "")), "v17.schema.v1", "%s format" % sid)
		_ok(_semver(String(s.get("version", ""))), "%s version" % sid)
		_ok(String(s.get("title", "")) != "", "%s title" % sid)
		_ok(s.get("properties") is Dictionary, "%s properties" % sid)
		_ok(s.get("required") is Array, "%s required" % sid)
		if s.get("properties") is Dictionary and s.get("required") is Array:
			var props: Dictionary = s.get("properties", {})
			for raw_req in (s.get("required", []) as Array):
				_ok(props.has(String(raw_req)), "%s required 在 properties: %s" % [sid, String(raw_req)])
		_ok(s.get("example") is Dictionary, "%s example" % sid)
	for sid in SCHEMA_IDS:
		_ok(seen.has(sid), "必需 schema: " + sid)
	_data_line("schema_files", "files=%d ids=%s" % [files.size(), str(seen.keys())])

# ═══════════════════════════════════════════════════════════════════
# 4. loader 加载/示例
# ═══════════════════════════════════════════════════════════════════

func _test_loader() -> void:
	_section_begin("4 loader")
	var loader = SchemaLoader.new()
	_ok(loader.ready, "loader ready", str(loader.errors))
	_eq(loader.errors.size(), 0, "loader 无 errors")
	_eq(loader.count(), 10, "loader count=10")
	var expected_ids: Array = SCHEMA_IDS.duplicate()
	expected_ids.sort()
	_eq(loader.ids(), expected_ids, "loader ids 与期望一致")
	for sid in SCHEMA_IDS:
		var s: Dictionary = loader.schema(sid)
		_ok(not s.is_empty(), "schema(%s)" % sid)
		_ok(String(s.get("id", "")) == sid, "schema %s id" % sid)
		var ex: Dictionary = loader.example(sid)
		_ok(not ex.is_empty(), "example(%s)" % sid)
		if not ex.is_empty():
			var v: Dictionary = loader.validate_instance(sid, ex)
			_ok(bool(v.get("ok", false)), "示例通过 %s" % sid, str(v.get("errors", [])))
	# 单位白名单暴露
	var td: Dictionary = loader.to_dict()
	_ok(td.get("allowed_units") is Array, "to_dict.allowed_units")
	_ok("km" in (td.get("allowed_units") as Array), "allowed_units 含 km")
	_ok("km/s" in (td.get("allowed_units") as Array), "allowed_units 含 km/s")
	_ok("deg" in (td.get("allowed_units") as Array), "allowed_units 含 deg")
	_data_line("loader", "ready/count=10/examples=10/allowed_units 就绪")

# ═══════════════════════════════════════════════════════════════════
# 5. loader 拒绝（缺字段/枚举/单位/重复 id）
# ═══════════════════════════════════════════════════════════════════

func _test_loader_rejections() -> void:
	_section_begin("5 loader 拒绝")
	var loader = SchemaLoader.new()
	# 缺必需字段
	var e1: Array = loader.validate_schema_dict({
		"schema": "v17.schema.v1", "id": "bad_missing", "version": "1.0.0",
		"title": "bad", "type": "object",
		"required": ["id", "missing_field"],
		"properties": {"id": {"type": "string"}},
		"example": {"id": "x"},
	})
	_ok(e1.size() > 0, "required 不在 properties 被拒")
	# 缺 unit
	var e2: Array = loader.validate_schema_dict({
		"schema": "v17.schema.v1", "id": "bad_unit", "version": "1.0.0",
		"title": "bad", "type": "object", "required": ["range_km"],
		"properties": {"range_km": {"type": "number"}},
		"example": {"range_km": 1.0},
	})
	_ok(e2.size() > 0, "数值字段缺 unit 被拒")
	# 非法 unit
	var e3: Array = loader.validate_schema_dict({
		"schema": "v17.schema.v1", "id": "bad_unit2", "version": "1.0.0",
		"title": "bad", "type": "object", "required": ["range_km"],
		"properties": {"range_km": {"type": "number", "unit": "bananas"}},
		"example": {"range_km": 1.0},
	})
	_ok(e3.size() > 0, "非法 unit 被拒")
	# 枚举非法
	var e4: Array = loader.validate_schema_dict({
		"schema": "v17.schema.v1", "id": "bad_enum", "version": "1.0.0",
		"title": "bad", "type": "object", "required": ["mode"],
		"properties": {"mode": {"type": "string", "enum": []}},
		"example": {"mode": "x"},
	})
	_ok(e4.size() > 0, "空 enum 被拒")
	# 示例缺必需字段 / 枚举非法 / 类型错误 / 单位错配
	var base: Dictionary = loader.schema("track")
	var ex: Dictionary = loader.example("track")
	_eq(bool(loader.validate_instance("track", ex).get("ok", false)), true, "合法示例 ok")
	var miss := ex.duplicate(true)
	miss.erase("batch")
	var vm: Dictionary = loader.validate_instance("track", miss)
	_eq(bool(vm.get("ok", true)), false, "缺字段实例被拒")
	var bad_enum := ex.duplicate(true)
	bad_enum["identity"] = "alien"
	_eq(bool(loader.validate_instance("track", bad_enum).get("ok", true)), false,
		"非法枚举实例被拒")
	var bad_type := ex.duplicate(true)
	bad_type["level"] = "high"
	_eq(bool(loader.validate_instance("track", bad_type).get("ok", true)), false,
		"类型错误实例被拒")
	var obs_ex: Dictionary = loader.example("sensor_observation")
	var bad_unit := obs_ex.duplicate(true)
	bad_unit["range_km_unit"] = "m"
	_eq(bool(loader.validate_instance("sensor_observation", bad_unit).get("ok", true)), false,
		"单位错配实例被拒")
	# 重复 schema id / 重复 example id
	var s1: Dictionary = loader.schema("entity")
	var s2: Dictionary = loader.schema("time")
	s2["id"] = "entity"
	var dup1: Array = loader.validate_collection([s1, s2])
	_ok(dup1.size() > 0, "重复 schema id 被拒")
	var s3: Dictionary = loader.schema("entity")
	var s4: Dictionary = loader.schema("time")
	s4["example"] = (s4.get("example", {}) as Dictionary).duplicate(true)
	(s4["example"] as Dictionary)["id"] = String((s3.get("example", {}) as Dictionary).get("id", ""))
	var dup2: Array = loader.validate_collection([s3, s4])
	_ok(dup2.size() > 0, "重复 example id 被拒")
	# 非法 schema id/version/type/格式
	var e5: Array = loader.validate_schema_dict({
		"schema": "bad", "id": "Bad-ID", "version": "1.0", "title": "",
		"type": "nonsense", "required": [], "properties": {},
		"example": {},
	})
	_ok(e5.size() >= 3, "格式/id/version/type 非法均报错", str(e5.size()))
	_data_line("rejections", "缺字段/unit/枚举/类型/单位错配/重复 id 均被拒")

# ═══════════════════════════════════════════════════════════════════
# 6. 关键 schema 示例
# ═══════════════════════════════════════════════════════════════════

func _test_examples() -> void:
	_section_begin("6 关键示例")
	var loader = SchemaLoader.new()
	var checks := {
		"entity": ["id", "kind", "side", "name"],
		"time": ["id", "t_s", "epoch", "mode"],
		"frame": ["id", "kind", "origin", "unit"],
		"order": ["id", "ship_id", "kind", "status"],
		"comms": ["id", "from", "to", "mode", "encrypted"],
		"sensor_observation": ["id", "observer_id", "sensor", "t_s"],
		"track": ["id", "batch", "entity_id", "level", "identity", "threat"],
		"save": ["id", "version", "scenario_id", "t_s", "entities", "tracks", "ui"],
		"story_state": ["id", "scenario_id", "phase", "flags", "evidence", "decisions"],
		"ui_field": ["id", "token", "label", "value_type", "source"],
	}
	for sid in checks.keys():
		var ex: Dictionary = loader.example(String(sid))
		for field in checks[sid]:
			_ok(ex.has(String(field)), "%s 示例含 %s" % [sid, String(field)])
		var res: Dictionary = loader.validate_instance(String(sid), ex)
		_ok(bool(res.get("ok", false)), "%s 示例通过校验" % sid, str(res.get("errors", [])))
	# 数值单位（从 schema 读取）
	var track: Dictionary = loader.schema("track")
	var props: Dictionary = track.get("properties", {})
	_eq(String((props.get("level", {}) as Dictionary).get("unit", "")), "none", "track.level unit=none")
	_eq(String((props.get("age_s", {}) as Dictionary).get("unit", "")), "s", "track.age_s unit=s")
	var obs: Dictionary = loader.schema("sensor_observation")
	var oprops: Dictionary = obs.get("properties", {})
	_eq(String((oprops.get("range_km", {}) as Dictionary).get("unit", "")), "km",
		"sensor.range unit=km")
	_eq(String((oprops.get("bearing_deg", {}) as Dictionary).get("unit", "")), "deg",
		"sensor.bearing unit=deg")
	_data_line("examples", "10 schema 示例全部通过 · 单位元数据正确")

# ═══════════════════════════════════════════════════════════════════
# 7. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("7 JSON")
	var loader = SchemaLoader.new()
	var js := JSON.stringify(loader.to_dict())
	_ok(js.length() > 5000, "loader to_dict JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "loader JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq(int(pd.get("count", -1)), 10, "回读 count=10")
		_ok(pd.get("ids") is Array, "回读 ids")
		_ok(pd.get("schemas") is Dictionary, "回读 schemas")
		_ok(pd.get("examples") is Dictionary, "回读 examples")
	var ui = UITokens.new()
	var tjs := JSON.stringify(ui.to_dict())
	_ok(tjs.length() > 1000, "tokens to_dict JSON", "len=%d" % tjs.length())
	var tp = JSON.parse_string(tjs)
	_ok(tp is Dictionary, "tokens JSON 回读")
	if tp is Dictionary:
		_ok((tp as Dictionary).get("tokens") is Dictionary, "回读 tokens")
		_eq(String((tp as Dictionary).get("version", "")), "1.0.0", "回读 version")
	# 所有 config JSON 可解析
	for sid in SCHEMA_IDS:
		var text := FileAccess.get_file_as_string(SCHEMA_DIR.path_join(sid + ".json"))
		_ok(JSON.parse_string(text) is Dictionary, "schema file JSON 回读: " + sid)
	_data_line("json", "loader=%d tokens=%d 全部 config JSON 可回读" % [js.length(), tjs.length()])
