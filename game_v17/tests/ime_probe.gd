extends SceneTree

# 阶段1B IME 输入 probe（无系统 IME 环境：使用显式注入/直接 API 模拟，非 OS IME）。
# 运行：
#   godot --headless --path game_v17 --script res://tests/ime_probe.gd

const ImeInput := preload("res://scripts/ui/ime_input.gd")
const ImeCandidate := preload("res://scripts/ui/ime_candidate.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _fails: Array[String] = []


func _initialize() -> void:
	print("══════════════════════════════════════════════════")
	print("阶段1B IME PROBE · 注入模拟（非系统 IME）")
	print("══════════════════════════════════════════════════")
	_test_sanitize()
	_test_length()
	_test_validate()
	_test_composition()
	_test_candidates()
	_test_candidate_window()
	_test_json()
	print("──────────────────────────────────────────────────")
	print("IME PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _fails:
			print("[FAILED] " + f)
		quit(1)
	else:
		print("IME PROBE OK")
		quit(0)


func _begin(name: String) -> void:
	_section = name
	print("-- " + name + " --")


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(_section + " · " + label + (" (" + detail + ")" if detail != "" else ""))


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label, "actual=%.3f expected=%.3f" % [actual, expected])


func _test_sanitize() -> void:
	_begin("sanitize")
	_eq(ImeInput.sanitize("Aps" + String.chr(0x200b) + "is" + String.chr(1)), "Apsis", "过滤零宽/控制")
	_eq(ImeInput.sanitize("  Apsis  "), "Apsis", "trim/空格")
	_eq(ImeInput.sanitize("哈马丹"), "哈马丹", "CJK")
	_eq(ImeInput.sanitize("ハマダン"), "ハマダン", "日文片假名")
	_eq(ImeInput.sanitize("한마단"), "한마단", "韩文")
	_eq(ImeInput.sanitize("Apsis!"), "Apsis", "过滤感叹号")
	_eq(ImeInput.sanitize("@#$%^&*"), "", "过滤特殊符号")
	_eq(ImeInput.sanitize("A B"), "A B", "保留内部空格")
	_eq(ImeInput.sanitize("A  B"), "A B", "空格归一")
	_eq(ImeInput.sanitize("A-B_C·D"), "A-B_C·D", "保留连接符")
	_eq(ImeInput.sanitize("😀Apsis"), "Apsis", "过滤 emoji")
	_eq(ImeInput.sanitize("A\nB\tC"), "ABC", "过滤换行/tab")
	_eq(ImeInput.sanitize(""), "", "空串")


func _test_length() -> void:
	_begin("length")
	_eq(ImeInput.truncate("abcdef", 3), "abc", "truncate 3")
	_eq(ImeInput.truncate("abc", 3), "abc", "truncate exact")
	_eq(ImeInput.truncate("abc", 10), "abc", "truncate longer")
	_eq(ImeInput.truncate("abc", 0), "", "truncate 0")
	_eq(ImeInput.truncate("哈马丹", 2), "哈马", "CJK length")
	var s := ""
	for i in range(30):
		s += "a"
	_eq(ImeInput.truncate(s, 24).length(), 24, "24 长度")
	var inp = ImeInput.new()
	inp.max_length = 5
	inp.set_text("abcdefgh")
	_eq(inp.text, "abcde", "set_text 截断")
	_eq(inp.validate_name("a").get("reason", ""), "name_too_short", "1 char invalid")
	_eq(inp.validate_name("").get("reason", ""), "empty_name", "empty invalid")
	inp.free()


func _test_validate() -> void:
	_begin("validate")
	var inp = ImeInput.new()
	_eq(bool(inp.validate_name("Apsis").get("ok", false)), true, "valid 2+")
	_eq(bool(inp.validate_name("哈马丹").get("ok", false)), true, "valid CJK")
	_eq(bool(inp.validate_name("  ").get("ok", true)), false, "whitespace reject")
	inp.duplicate_names = ["Apsis"]
	var dup: Dictionary = inp.validate_name("Apsis")
	_eq(bool(dup.get("ok", true)), false, "duplicate reject")
	_eq(String(dup.get("reason", "")), "duplicate_name", "duplicate reason")
	_eq(bool(inp.validate_name("apsis").get("ok", false)), true, "duplicate case-sensitive")
	var checked := [false]
	inp.duplicate_check = func(n: String) -> bool:
		checked[0] = true
		return n == "Blocked"
	_eq(String(inp.validate_name("Blocked").get("reason", "")), "duplicate_name", "callable duplicate")
	_eq(bool(checked[0]), true, "duplicate callable called")
	_eq(bool(inp.validate_name("Free").get("ok", false)), true, "callable free")
	inp.free()


func _test_composition() -> void:
	_begin("composition")
	var inp = ImeInput.new()
	inp.set_composition("沧", ["沧澜", "沧海"])
	_eq(inp.composition, "沧", "composition set")
	_eq(inp.candidates.size(), 2, "candidates count")
	_eq(inp.current_candidate(), "沧澜", "first candidate")
	_eq(inp.select_next(), "沧海", "next candidate")
	_eq(inp.current_candidate(), "沧海", "next selected")
	_eq(inp.select_prev(), "沧澜", "prev candidate")
	var confirmed := inp.confirm_candidate()
	_eq(confirmed, "沧澜", "confirm candidate")
	_eq(inp.text, "沧澜", "committed text")
	_eq(inp.composition, "", "composition cleared")
	_eq(inp.candidates.size(), 0, "candidates cleared")
	inp.set_composition("A", ["Apsis"])
	inp.cancel_composition()
	_eq(inp.composition, "", "cancel composition clear")
	inp.set_composition("日", ["日本", "日向"])
	_eq(inp.select_next(), "日向", "jp candidate select")
	inp.free()


func _test_candidates() -> void:
	_begin("candidate paging")
	var inp = ImeInput.new()
	var cs := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一"]
	inp.set_composition("x", cs)
	_eq(inp.candidates.size(), 11, "11 candidates")
	_eq(inp.page_count(), 3, "page count 3")
	for i in range(5):
		inp.select_next()
	_eq(inp.page, 1, "after 5 next page=1")
	_eq(inp.current_candidate(), "六", "page boundary current 六")
	inp.next_page()
	_eq(inp.page, 2, "next page 2")
	inp.prev_page()
	_eq(inp.page, 1, "prev page 1")
	inp.next_page()
	inp.next_page()
	_eq(inp.page, 2, "clamp last page")
	inp.free()


func _test_candidate_window() -> void:
	_begin("candidate window")
	var cw = ImeCandidate.new()
	get_root().add_child(cw)
	cw.set_data("沧", ["沧澜", "沧海", "沧溟", "苍岚", "苍梧", "苍山", "苍海"], 0, 0)
	_eq(cw.visible, true, "visible with candidates")
	_eq(cw.page_count(), 2, "page_count 2")
	cw.place(Rect2(200, 700, 460, 44))
	var p: Vector2 = cw.position
	_ok(p.y >= 8.0, "not above screen")
	_ok(p.y + cw.size.y <= 1080.0 - 8.0 + 1.0, "not below screen", "p.y=%f size=%f" % [p.y, cw.size.y])
	_ok(p.x >= 8.0, "x left")
	_ok(p.x + cw.size.x <= 1920.0 - 8.0 + 1.0, "x right")
	# 靠近底部应翻到输入框上方
	cw.place(Rect2(900, 1040, 460, 30))
	_ok(cw.position.y < 1040.0, "flip above near bottom")
	var h_before: float = cw.size.y
	cw.set_data("", [], 0, 0)
	_eq(cw.visible, false, "hidden no composition")
	cw.free()


func _test_json() -> void:
	_begin("JSON")
	var inp = ImeInput.new()
	inp.max_length = 24
	inp.set_text("哈马丹")
	inp.set_composition("沧", ["沧澜", "沧海"])
	var js := inp.to_json()
	_ok(js.length() > 40, "json length")
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "json parse")
	if parsed is Dictionary:
		_eq(String(parsed.get("text", "")), "哈马丹", "json text")
		_eq((parsed.get("candidates", []) as Array).size(), 2, "json candidates")
		_ok(parsed.get("valid") is Dictionary, "json valid")
	var d1 := inp.to_dict()
	var d2 := inp.to_dict()
	_eq(JSON.stringify(d1), JSON.stringify(d2), "deterministic")
	inp.free()
