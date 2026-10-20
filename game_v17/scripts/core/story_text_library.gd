extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3T：StoryTextLibrary（序章文本库；新文件）
#
# - 从 docs/44_新剧本_2193.md 原样摘录序章文本（briefing/deputy/nav/
#   comms/arrival），不改写；多语言字段 zh/en（en 为空/TBD，不伪译）；
# - schema v17.story_text.v1：id/text_key/channel/speaker_role/listener_role/
#   mode/source_lines/draft/zh/en/vars/var_specs；
# - load/validate/get/render(vars)/by_channel/by_role/source_lines/to_dict；
# - 缺 key/缺变量明确错误；不写 UI/world/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.story_text.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/story_prologue_text.json"
const REQUIRED_FIELDS := ["id", "text_key", "channel", "speaker_role",
	"listener_role", "mode", "source_lines", "draft", "zh", "en", "vars",
	"var_specs"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var source_path := ""
var entries: Array = []
var _by_key: Dictionary = {}
var _by_channel: Dictionary = {}
var _channels: Array = []
var _roles: Array = []

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	content_path = str(c.get("content_path", DEFAULT_CONTENT))
	content = {}
	if c.get("content") is Dictionary and not (c.get("content") as Dictionary).is_empty():
		content = (c.get("content") as Dictionary).duplicate(true)
	else:
		content = _read_json(content_path)
	if content.is_empty():
		errors.append("文本库内容不可读：" + content_path)
		ready = false
		return false
	return load_data(content)

func load_content(path := DEFAULT_CONTENT) -> bool:
	var d: Dictionary = _read_json(path)
	if d.is_empty():
		errors.append("文本库内容不可读/JSON 无效：" + path)
		ready = false
		return false
	content_path = path
	return load_data(d)

func load_data(value: Variant) -> bool:
	if not (value is Dictionary):
		errors.append("文本库内容必须是对象")
		return false
	var v: Dictionary = validate(value)
	if not bool(v.get("ok", false)):
		errors.clear()
		for e in (v.get("errors", []) as Array):
			errors.append("story_text: " + str(e))
		return false
	_apply(value as Dictionary)
	ready = true
	return true

# ── 校验 ───────────────────────────────────────────────────────

func validate(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != SCHEMA:
		errs.append("schema 必须为 " + SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	if str(d.get("source", "")) == "":
		errs.append("source 为空")
	var arr = d.get("entries", null)
	if not (arr is Array) or (arr as Array).is_empty():
		errs.append("entries 必须为非空数组")
		return {"ok": false, "errors": errs}
	var ids: Dictionary = {}
	var keys: Dictionary = {}
	for raw in (arr as Array):
		if not (raw is Dictionary):
			errs.append("entry 非对象")
			continue
		var e: Dictionary = raw
		for f in REQUIRED_FIELDS:
			if not e.has(f):
				errs.append("entry 缺少字段：" + str(f))
		var tid := str(e.get("id", ""))
		var key := str(e.get("text_key", ""))
		if tid == "":
			errs.append("entry id 为空")
		elif ids.has(tid):
			errs.append("entry id 重复：" + tid)
		ids[tid] = true
		if key == "":
			errs.append("text_key 为空")
		elif keys.has(key):
			errs.append("text_key 重复：" + key)
		keys[key] = true
		for f2 in ["channel", "speaker_role", "listener_role", "mode"]:
			if str(e.get(f2, "")) == "":
				errs.append("entry %s %s 为空" % [key, f2])
		var sl = e.get("source_lines", null)
		if not (sl is Array) or (sl as Array).is_empty():
			errs.append("entry %s source_lines 为空" % key)
		else:
			for n in (sl as Array):
				if not (n is int or n is float) or int(float(n)) <= 0 \
						or absf(float(n) - float(int(float(n)))) > 1.0e-9:
					errs.append("entry %s source_lines 必须为正整数" % key)
		if not (e.get("draft") is bool):
			errs.append("entry %s draft 必须是 bool" % key)
		if str(e.get("zh", "")) == "":
			errs.append("entry %s zh 为空" % key)
		if not (e.get("en") is String):
			errs.append("entry %s en 必须是字符串" % key)
		var vars = e.get("vars", null)
		if not (vars is Array):
			errs.append("entry %s vars 必须是数组" % key)
		else:
			for v in (vars as Array):
				if str(v) == "":
					errs.append("entry %s var 为空" % key)
		if not (e.get("var_specs") is Dictionary):
			errs.append("entry %s var_specs 必须是对象" % key)
	return {"ok": errs.is_empty(), "errors": errs}

func _apply(d: Dictionary) -> void:
	content = d.duplicate(true)
	source_path = str(d.get("source_path", ""))
	entries = (d.get("entries", []) as Array).duplicate(true)
	_by_key = {}
	_by_channel = {}
	_channels = []
	_roles = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var key := str(e.get("text_key", ""))
		_by_key[key] = e
		var ch := str(e.get("channel", ""))
		if not _by_channel.has(ch):
			_by_channel[ch] = []
		(_by_channel[ch] as Array).append(e)
		if not (ch in _channels):
			_channels.append(ch)
		for rk in ["speaker_role", "listener_role"]:
			var r := str(e.get(rk, ""))
			if r != "" and not (r in _roles):
				_roles.append(r)
	_channels.sort()
	_roles.sort()

# ── 查询 ────────────────────────────────────────────────────────

func text_keys() -> Array:
	var out: Array = _by_key.keys()
	out.sort()
	return out

func entry_ids() -> Array:
	var out: Array = []
	for raw in entries:
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("id", "")))
	out.sort()
	return out

func channels() -> Array:
	return _channels.duplicate()

func roles() -> Array:
	return _roles.duplicate()

## 读取条目（lang：zh/en；缺省 zh；未知 key 返回空）。
func get_text(text_key: String, lang := "zh") -> Dictionary:
	var e: Dictionary = (_by_key.get(text_key, {}) as Dictionary).duplicate(true)
	if e.is_empty():
		return {}
	if not e.has("text"):
		e["text"] = str(e.get(lang, e.get("zh", "")))
	return e

## 兼容 Object.get("text_key")：未知属性返回 null；读取到的条目为只读副本。
func _get(property: StringName) -> Variant:
	var key := str(property)
	if _by_key.has(key):
		return (_by_key[key] as Dictionary).duplicate(true)
	return null

func by_channel(channel: String) -> Array:
	var out: Array = []
	for raw in (_by_channel.get(channel, []) as Array):
		out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str((a as Dictionary).get("text_key", "")) < str((b as Dictionary).get("text_key", "")))
	return out

func by_role(role: String) -> Array:
	var out: Array = []
	for raw in entries:
		if raw is Dictionary and (str((raw as Dictionary).get("speaker_role", "")) == role \
				or str((raw as Dictionary).get("listener_role", "")) == role):
			out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str((a as Dictionary).get("text_key", "")) < str((b as Dictionary).get("text_key", "")))
	return out

## 返回条目 source_lines；不传 key 时返回 {text_key: lines}。
func source_lines(text_key := "") -> Variant:
	if text_key != "":
		var e: Dictionary = _by_key.get(text_key, {}) as Dictionary
		return (e.get("source_lines", []) as Array).duplicate() if not e.is_empty() else []
	var out: Dictionary = {}
	for key in _by_key.keys():
		out[str(key)] = ((_by_key[key] as Dictionary).get("source_lines", []) as Array).duplicate()
	return out

## 渲染：支持 lang zh/en、变量替换；缺翻译/缺变量返回明确错误。
func render(text_key: String, vars := {}, lang := "zh") -> Dictionary:
	var e: Dictionary = _by_key.get(text_key, {}) as Dictionary
	if e.is_empty():
		return {"ok": false, "reason": "unknown_key", "text_key": text_key}
	if not (lang in ["zh", "en"]):
		return {"ok": false, "reason": "unknown_language", "lang": lang, "text_key": text_key}
	var text := str(e.get(lang, ""))
	if text.strip_edges() == "":
		return {"ok": false, "reason": "missing_translation", "lang": lang,
			"text_key": text_key}
	var v: Dictionary = vars if vars is Dictionary else {}
	var required: Array = e.get("vars", []) as Array
	var missing: Array = []
	for key in required:
		if not v.has(str(key)):
			missing.append(str(key))
	if not missing.is_empty():
		return {"ok": false, "reason": "missing_variables", "missing": missing,
			"text_key": text_key, "text": text}
	var specs: Dictionary = e.get("var_specs", {}) if e.get("var_specs") is Dictionary else {}
	for key2 in v.keys():
		var k := str(key2)
		if specs.has(k):
			text = text.replace(str(specs[k]), str(v[key2]))
		text = text.replace("{" + k + "}", str(v[key2]))
		text = text.replace("{{" + k + "}}", str(v[key2]))
	return {"ok": true, "reason": "", "text_key": text_key, "lang": lang,
		"text": text, "vars": v.duplicate(true),
		"source_lines": (e.get("source_lines", []) as Array).duplicate()}

# ── 原文校验 ───────────────────────────────────────────────────

func _trim_line(s: String) -> String:
	var out := s
	while out.begins_with("　"):
		out = out.substr(1)
	return out.strip_edges()

func _resolve_source(path: String) -> String:
	var p := path if path != "" else source_path
	if p == "":
		return ""
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	if p.begins_with("/") or (p.length() > 1 and p[1] == ":"):
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()

## 逐字校验：每条 zh 必须出现在 docs/44 的 source_lines 某一行（去缩进后相等）。
func verify_against_source(path := "") -> Dictionary:
	if not ready:
		return {"ok": false, "errors": ["story text library 未 ready"]}
	return verify_content_against_source(content, path)

## 对任意内容字典做逐字校验（不改变当前库状态；即使库未 ready 也可用于测试）。
func verify_content_against_source(value: Variant, path := "") -> Dictionary:
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var sp := _resolve_source(path)
	if sp == "" or not FileAccess.file_exists(sp):
		return {"ok": false, "errors": ["source 文件不存在：" + sp]}
	var f := FileAccess.open(sp, FileAccess.READ)
	if f == null:
		return {"ok": false, "errors": ["source 文件不可读：" + sp]}
	var lines: Array = f.get_as_text().split("\n")
	f.close()
	var bad: Array = []
	var check_entries: Array = ((value as Dictionary).get("entries", []) as Array) \
		if (value as Dictionary).get("entries") is Array else []
	for raw in check_entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var key := str(e.get("text_key", ""))
		var found := false
		for n in (e.get("source_lines", []) as Array):
			var idx := int(n) - 1
			if idx >= 0 and idx < lines.size():
				if _trim_line(str(lines[idx])) == str(e.get("zh", "")):
					found = true
					break
		if not found:
			bad.append({"text_key": key, "source_lines": (e.get("source_lines", []) as Array).duplicate()})
	return {"ok": bad.is_empty(), "checked": check_entries.size(), "mismatches": bad,
		"source": sp}

func to_dict() -> Dictionary:
	return content.duplicate(true)

func to_json() -> String:
	return JSON.stringify(to_dict())

func summary() -> Dictionary:
	var per_channel: Dictionary = {}
	for ch in _channels:
		per_channel[str(ch)] = (_by_channel[ch] as Array).size()
	return {"schema": SCHEMA, "ready": ready, "title": str(content.get("title", "")),
		"source": str(content.get("source", "")), "source_path": source_path,
		"entries": entries.size(), "channels": per_channel,
		"roles": _roles.duplicate(), "draft": bool(content.get("draft", true)),
		"writes": {"ui": false, "world": false, "v15": false}}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("library 未 ready")
	if entries.is_empty():
		v.append("entries 为空")
	if _by_key.size() != entries.size():
		v.append("text_key 索引数量不一致")
	for key in text_keys():
		var e: Dictionary = _by_key[key]
		if str(e.get("zh", "")) == "":
			v.append("entry %s zh 为空" % str(key))
		if not bool(e.get("draft", false)):
			v.append("entry %s draft=false（本轮应 draft）" % str(key))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
