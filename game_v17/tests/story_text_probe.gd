extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3T 最小 probe：StoryTextLibrary（序章文本库）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/story_text_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 UI/world。
# ═══════════════════════════════════════════════════════════════════

const StoryTextLibrary := preload("res://scripts/core/story_text_library.gd")

const KEYS := ["briefing.body", "deputy.hello", "deputy.terminal", "deputy.nav",
	"deputy.nav_panel", "deputy.command", "nav.wrong_dest", "nav.correct",
	"nav.depart_prompt", "comms.hammer", "comms.formation", "nav.arrival_prompt"]
const DOCS44 := "../docs/44_新剧本_2193.md"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3T PROBE · StoryTextLibrary")
	print("════════════════════════════════════════════════════════════")
	_test_load_keys()
	_test_verbatim()
	_test_render()
	_test_invalid()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 STORY TEXT PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 STORY TEXT PROBE FAILED")
		quit(1)
	else:
		print("V17 STORY TEXT PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
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

func _new_lib() -> Object:
	var lib = StoryTextLibrary.new()
	_ok(bool(lib.ready), "StoryTextLibrary ready", str(lib.errors))
	return lib

func _base(lib) -> Dictionary:
	return (lib.to_dict() as Dictionary).duplicate(true)

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

func _lines_from_num(arr: Array) -> Array:
	var out: Array = []
	for n in arr:
		out.append(int(float(n)))
	return out

func _doc_lines() -> Array:
	var abs_path := ProjectSettings.globalize_path("res://").path_join(DOCS44).simplify_path()
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return []
	var lines: Array = f.get_as_text().split("\n")
	f.close()
	return lines

func _trim(s: String) -> String:
	var out := s
	while out.begins_with("　"):
		out = out.substr(1)
	return out.strip_edges()

# ═══════════════════════════════════════════════════════════════════
# 1. load / keys / schema
# ═══════════════════════════════════════════════════════════════════

func _test_load_keys() -> void:
	_section_begin("1 load/keys")
	var lib = _new_lib()
	_eq((lib.text_keys() as Array).size(), 12, "12 text keys")
	for key in KEYS:
		_ok(str(key) in lib.text_keys(), "含 key " + str(key))
		var e: Dictionary = lib.get_text(str(key))
		_ok(not e.is_empty(), "get_text " + str(key))
		for f in ["id", "text_key", "channel", "speaker_role", "listener_role",
				"mode", "source_lines", "draft", "zh", "en", "vars", "var_specs"]:
			_ok(e.has(f), "%s 字段 %s" % [key, f])
		_ok(str(e.get("text_key", "")) == str(key), "text_key 一致 " + str(key))
		_ok(str(e.get("id", "")) != "", "id 非空 " + str(key))
		var sl: Array = _lines_from_num(e.get("source_lines", []) as Array)
		_ok(sl.size() > 0, "source_lines 非空 " + str(key))
		for n in sl:
			_ok(int(n) > 0, "source_line 正整数 " + str(key))
		_ok(str(e.get("channel", "")) != "", "channel 非空 " + str(key))
		_ok(str(e.get("speaker_role", "")) != "", "speaker_role 非空 " + str(key))
		_ok(str(e.get("listener_role", "")) != "", "listener_role 非空 " + str(key))
		_ok(str(e.get("mode", "")) != "", "mode 非空 " + str(key))
		_ok(bool(e.get("draft", false)), "draft=true " + str(key))
		_ok(str(e.get("zh", "")) != "", "zh 非空 " + str(key))
		_ok(e.get("en") is String, "en 字符串 " + str(key))
		_ok(e.get("vars") is Array, "vars 数组 " + str(key))
		_ok(e.get("var_specs") is Dictionary, "var_specs 对象 " + str(key))
		_ok(lib.get(str(key)).get("text_key") == str(key), "Object.get(key) " + str(key))
	_eq(lib.entry_ids().size(), 12, "12 ids")
	_eq((lib.channels() as Array), ["briefing", "comms", "deputy", "nav"],
		"channels 排序")
	_eq((lib.by_channel("briefing") as Array).size(), 1, "briefing 1 条")
	_eq((lib.by_channel("deputy") as Array).size(), 5, "deputy 5 条")
	_eq((lib.by_channel("nav") as Array).size(), 4, "nav 4 条")
	_eq((lib.by_channel("comms") as Array).size(), 2, "comms 2 条")
	_ok((lib.by_role("deputy") as Array).size() >= 1, "by_role deputy")
	_ok((lib.by_role("commander") as Array).size() >= 5, "by_role commander")
	_eq((lib.source_lines("comms.hammer") as Array).size(), 2, "comms 两行源")
	_eq(lib.get_text("NOPE").size(), 0, "未知 key get 空")
	_eq(lib.get("NOPE"), null, "未知 key Object.get null")
	_ok(bool(lib.check_contracts().get("ok", false)), "contracts ok")
	var sum: Dictionary = lib.summary()
	_eq(str(sum.get("schema", "")), "v17.story_text.v1", "summary schema")
	_eq(int(sum.get("entries", 0)), 12, "summary entries")
	_eq(bool(sum.get("draft", false)), true, "summary draft")
	_eq(bool((sum.get("writes", {}) as Dictionary).get("ui", true)), false, "不写 UI")
	_eq(bool((sum.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_data_line("keys", "12 keys/channels briefing1+deputy5+nav4+comms2 · schema 字段全 · draft")

# ═══════════════════════════════════════════════════════════════════
# 2. docs/44 原文逐字
# ═══════════════════════════════════════════════════════════════════

func _test_verbatim() -> void:
	_section_begin("2 docs/44 原文")
	var lib = _new_lib()
	var ver: Dictionary = lib.verify_against_source()
	_eq(bool(ver.get("ok", false)), true, "verify_against_source ok", str(ver.get("mismatches", [])))
	_eq(int(ver.get("checked", 0)), 12, "verify checked 12")
	var doc: Array = _doc_lines()
	_ok(doc.size() > 100, "docs/44 可读")
	# 每 key 的 zh 必须与 docs/44 的 source_lines 行逐字相等
	for key in KEYS:
		var e: Dictionary = lib.get_text(str(key))
		var zh := str(e.get("zh", ""))
		var matched := false
		for n in _lines_from_num(e.get("source_lines", []) as Array):
			var idx := int(n) - 1
			if idx >= 0 and idx < doc.size() and _trim(str(doc[idx])) == zh:
				matched = true
				break
		_ok(matched, "逐字匹配 docs/44 " + str(key))
	# 关键句/来源
	var b: String = str(lib.get_text("briefing.body").get("zh", ""))
	_ok(b.begins_with("简报：三天前，位于Chronos 的燃料加注站发生爆炸"), "briefing 关键句")
	_ok(b.contains("严格遵守ROE，不得首先开火"), "briefing ROE 句")
	_ok(str(lib.get_text("deputy.hello").get("zh", "")).contains("我是你的副官[姓名待补]"),
		"deputy 姓名占位原样")
	_ok(str(lib.get_text("deputy.nav").get("zh", "")).contains("L1 Meridian"), "deputy nav L1")
	_ok(str(lib.get_text("nav.wrong_dest").get("zh", "")).contains("重新选择"),
		"nav wrong 句")
	_ok(str(lib.get_text("nav.correct").get("zh", "")).contains("申请离港"),
		"nav correct 句")
	_ok(str(lib.get_text("comms.hammer").get("zh", "")).contains("离港许可已签发"),
		"comms hammer 句")
	_ok(str(lib.get_text("comms.formation").get("zh", "")).contains("执行变轨后进入巡航"),
		"comms formation 句")
	_ok(str(lib.get_text("nav.arrival_prompt").get("zh", "")).contains("Chronos进行并轨"),
		"arrival 句")
	# 不伪译：en 全空或 TBD
	for key2 in KEYS:
		var en := str(lib.get_text(str(key2)).get("en", ""))
		_ok(en == "" or en.to_upper().contains("TBD"), "en 不伪译 " + str(key2))
	# 来源标注
	_eq(str(lib.summary().get("source", "")).contains("docs/44"), true, "summary source")
	_ok(str(lib.summary().get("source_path", "")) != "", "summary source_path")
	# 篡改测试：verify 能发现不一致
	var bad := _base(lib)
	((bad.get("entries", []) as Array)[0] as Dictionary)["zh"] = "被改写的简报"
	var ver_bad: Dictionary = lib.verify_content_against_source(bad)
	_ok(not bool(ver_bad.get("ok", true)), "verify 能发现改写")
	# 直接用坏内容验证 validate 结构（不依赖 docs）
	_ok(bool(lib.validate(bad).get("ok", false)), "改写内容结构仍合法")
	_data_line("verbatim", "12 条逐字匹配 docs/44 · 关键句 · en 不伪译 · verify 可发现改写")

# ═══════════════════════════════════════════════════════════════════
# 3. render / vars
# ═══════════════════════════════════════════════════════════════════

func _test_render() -> void:
	_section_begin("3 render/vars")
	var lib = _new_lib()
	# 无变量条目
	for key in ["briefing.body", "deputy.terminal", "deputy.command",
			"nav.wrong_dest", "nav.correct", "comms.hammer", "comms.formation",
			"nav.arrival_prompt", "deputy.nav", "deputy.nav_panel",
			"deputy.nav_panel"]:
		var r: Dictionary = lib.render(str(key))
		_eq(bool(r.get("ok", false)), true, "render 无变量 " + str(key))
		_ok(str(r.get("text", "")) == str(lib.get_text(str(key)).get("zh", "")),
			"render 原文 " + str(key))
		_ok((r.get("source_lines", []) as Array).size() > 0, "render source_lines " + str(key))
	# deputy.hello 需要变量
	var miss: Dictionary = lib.render("deputy.hello")
	_eq(bool(miss.get("ok", true)), false, "缺变量拒绝")
	_eq(str(miss.get("reason", "")), "missing_variables", "missing_variables reason")
	_ok((miss.get("missing", []) as Array).has("deputy_name"), "missing deputy_name")
	var okv: Dictionary = lib.render("deputy.hello", {"deputy_name": "测试副官"})
	_eq(bool(okv.get("ok", false)), true, "带变量 render ok")
	var text := str(okv.get("text", ""))
	_ok(text.contains("测试副官"), "变量替换")
	_ok(not text.contains("[姓名待补]"), "占位被替换")
	_ok(text.contains("副官"), "其余原文保留")
	# 未知 key / language
	_eq(str(lib.render("NOPE").get("reason", "")), "unknown_key", "未知 key render")
	_eq(str(lib.render("briefing.body", {}, "fr").get("reason", "")),
		"unknown_language", "未知 language")
	# en 空 → missing_translation（不伪译）
	_eq(str(lib.render("briefing.body", {}, "en").get("reason", "")),
		"missing_translation", "en 缺失明确错误")
	# 无变量但传入多余变量不应改原文
	var extra: Dictionary = lib.render("deputy.command", {"deputy_name": "X"})
	_eq(str(extra.get("text", "")), str(lib.get_text("deputy.command").get("zh", "")),
		"多余变量不改原文")
	_data_line("render", "无变量原文 · 缺变量错误 · 替换占位 · unknown key/lang · en 缺失")

# ═══════════════════════════════════════════════════════════════════
# 4. 非法内容 / 原子
# ═══════════════════════════════════════════════════════════════════

func _test_invalid() -> void:
	_section_begin("4 非法/原子")
	var lib = _new_lib()
	var before := _norm(lib.to_dict())
	var keys_before: Array = lib.text_keys()
	var bads: Array = []
	var b1 := _base(lib); b1["schema"] = "bad"; bads.append(b1)
	var b2 := _base(lib); b2["version"] = "9.9.9"; bads.append(b2)
	var b3 := _base(lib); b3["entries"] = []; bads.append(b3)
	var b4 := _base(lib); ((b4["entries"] as Array)[1] as Dictionary)["text_key"] = "briefing.body"; bads.append(b4)
	var b5 := _base(lib); ((b5["entries"] as Array)[1] as Dictionary)["id"] = "STXT-0001"; bads.append(b5)
	var b6 := _base(lib); ((b6["entries"] as Array)[0] as Dictionary).erase("zh"); bads.append(b6)
	var b7 := _base(lib); ((b7["entries"] as Array)[0] as Dictionary)["zh"] = ""; bads.append(b7)
	var b8 := _base(lib); ((b8["entries"] as Array)[0] as Dictionary)["source_lines"] = []; bads.append(b8)
	var b9 := _base(lib); ((b9["entries"] as Array)[0] as Dictionary)["source_lines"] = [0]; bads.append(b9)
	var b10 := _base(lib); ((b10["entries"] as Array)[0] as Dictionary)["en"] = 3; bads.append(b10)
	var b11 := _base(lib); ((b11["entries"] as Array)[0] as Dictionary)["vars"] = "x"; bads.append(b11)
	var b12 := _base(lib); ((b12["entries"] as Array)[0] as Dictionary)["var_specs"] = []; bads.append(b12)
	var b13 := _base(lib); ((b13["entries"] as Array)[0] as Dictionary)["channel"] = ""; bads.append(b13)
	var b14 := _base(lib); ((b14["entries"] as Array)[0] as Dictionary)["draft"] = "yes"; bads.append(b14)
	for i in range(bads.size()):
		var brok: bool = lib.load_data(bads[i])
		_ok(not brok, "非法内容拒绝 #" + str(i))
	_eq(_norm(lib.to_dict()), before, "非法内容不改场景")
	_eq(lib.text_keys(), keys_before, "非法内容不改 keys")
	_ok(bool(lib.ready), "非法内容后仍 ready")
	_ok(not bool(lib.load_data("x")), "字符串内容拒绝")
	_ok(not bool(lib.load_data([])), "数组内容拒绝")
	_ok(not bool(lib.load_data({})), "空对象拒绝")
	# 不存在内容
	var badlib = StoryTextLibrary.new({"content_path": "/no/such.json"})
	_ok(not bool(badlib.ready), "不存在内容拒绝")
	_data_line("invalid", "14 类非法内容原子拒绝 · 非对象/空/不存在文件拒绝")

# ═══════════════════════════════════════════════════════════════════
# 5. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("5 JSON/确定性")
	var lib = _new_lib()
	var js: String = str(lib.to_json())
	_ok(JSON.parse_string(js) is Dictionary, "to_json 可解析")
	var d: Dictionary = lib.to_dict()
	_eq(str(d.get("schema", "")), "v17.story_text.v1", "to_dict schema")
	_eq((d.get("entries", []) as Array).size(), 12, "to_dict entries 12")
	_ok(str(d.get("source", "")) != "", "to_dict source")
	_ok(str(d.get("source_path", "")) != "", "to_dict source_path")
	# 往返
	var lib2 = _new_lib()
	_ok(bool(lib2.load_data(d)), "load_data(to_dict) ok")
	_eq(_norm(lib2.to_dict()), _norm(d), "to_dict 往返一致")
	_eq(lib2.text_keys(), lib.text_keys(), "往返 keys")
	_eq(_norm(lib2.summary()), _norm(lib.summary()), "往返 summary")
	# 确定性
	var a = _new_lib()
	var b = _new_lib()
	_eq(_norm(a.to_dict()), _norm(b.to_dict()), "两次加载一致")
	_eq(a.to_json(), b.to_json(), "to_json 一致")
	_eq(_norm(a.verify_against_source()), _norm(b.verify_against_source()),
		"verify 确定")
	_ok(bool(a.check_contracts().get("ok", false)), "contracts ok 2")
	_data_line("json", "to_dict/to_json 往返 · 两次加载/verify/contracts 确定")
