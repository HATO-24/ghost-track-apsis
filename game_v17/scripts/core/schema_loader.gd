extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段0：数据 schema 加载/校验器（新文件；不写 world）
#
# - 扫描 config/schema/*.json（JSON Schema 风格：type/properties/required/
#   enums/units + example）；
# - 校验：格式 marker、id/version、required 与 properties 一致、类型/枚举/数值范围/
#   数组长度、数值字段单位（白名单）、示例通过本 schema、跨文件 id 重复；
# - API：load_all/validate_instance/schema/ids/example/to_dict；
# - 只读：不实例化 world/V15，不写任何游戏状态。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA_ROOT := "res://config/schema"
const SCHEMA_FORMAT := "v17.schema.v1"
const VERSION_PATTERN := "^\\d+\\.\\d+\\.\\d+$"
const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const ALLOWED_TYPES := ["object", "array", "string", "number", "integer", "boolean"]
const ALLOWED_UNITS := ["none", "km", "km/s", "s", "day", "deg", "deg/s", "dB", "kg", "m", "MHz"]

var root_path := SCHEMA_ROOT
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var schemas: Dictionary = {}       # id -> schema dict
var schema_ids: Array = []
var examples: Dictionary = {}      # id -> example dict
var loaded_files: Array = []

func _init(path := SCHEMA_ROOT) -> void:
	load_all(path)

# ── 加载 ─────────────────────────────────────────────────────────

func load_all(path := SCHEMA_ROOT) -> bool:
	root_path = path
	schemas = {}
	schema_ids = []
	examples = {}
	loaded_files = []
	errors.clear()
	warnings.clear()
	ready = false
	var files: Array = DirAccess.get_files_at(path)
	if files.is_empty():
		errors.append("schema 目录为空或不可读：" + path)
		return false
	files.sort()
	var raw_list: Array = []
	for raw_name in files:
		var name := String(raw_name)
		if not name.ends_with(".json"):
			continue
		var full := path.path_join(name)
		var text := FileAccess.get_file_as_string(full)
		if text == "":
			errors.append("schema 文件为空：" + name)
			continue
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			errors.append("schema JSON 无效：" + name)
			continue
		var s: Dictionary = parsed
		raw_list.append(s)
	var per_errors: Array = validate_schema_dict_list(raw_list)
	errors.append_array(per_errors)
	# 注册（schema 自身通过后再登记示例）
	for raw in raw_list:
		var s2: Dictionary = raw
		var sid := String(s2.get("id", ""))
		if sid == "" or not (s2.get("schema", "") == SCHEMA_FORMAT):
			continue
		if schemas.has(sid):
			continue
		var own_errors: Array = validate_schema_dict(s2)
		if not own_errors.is_empty():
			continue
		schemas[sid] = s2.duplicate(true)
		schema_ids.append(sid)
		var ex: Dictionary = s2.get("example", {}) if s2.get("example") is Dictionary else {}
		if not ex.is_empty():
			examples[sid] = ex.duplicate(true)
			var ex_errors: Array = validate_instance_against(s2, ex)
			for e in ex_errors:
				errors.append("example[%s]: %s" % [sid, String(e)])
		loaded_files.append(String(s2.get("id", sid)) + ".json")
	schema_ids.sort()
	# 重复 id / 示例 id 检查
	var dup_errors: Array = validate_collection(raw_list)
	errors.append_array(dup_errors)
	ready = errors.is_empty() and not schemas.is_empty()
	return ready

## 批量校验（含重复 schema id / 重复 example id）。
func validate_schema_dict_list(list: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in list:
		if raw is Dictionary:
			out.append_array(validate_schema_dict(raw))
		else:
			out.append("schema 项不是对象")
	return out

func validate_collection(list: Array) -> Array[String]:
	var out: Array[String] = []
	var ids := {}
	var ex_ids := {}
	for raw in list:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		var sid := String(s.get("id", ""))
		if sid != "":
			if ids.has(sid):
				out.append("duplicate schema id: " + sid)
			ids[sid] = true
		var ex: Dictionary = s.get("example", {}) if s.get("example") is Dictionary else {}
		var exid := String(ex.get("id", ""))
		if exid != "":
			if ex_ids.has(exid):
				out.append("duplicate example id: " + exid)
			ex_ids[exid] = true
	return out

# ── schema 自校验 ────────────────────────────────────────────────

func validate_schema_dict(s: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if String(s.get("schema", "")) != SCHEMA_FORMAT:
		e.append("schema format 必须为 " + SCHEMA_FORMAT)
	var sid := String(s.get("id", ""))
	if not _matches(sid, ID_PATTERN):
		e.append("schema id 非法：'%s'（需 %s）" % [sid, ID_PATTERN])
	var version := String(s.get("version", ""))
	if not _matches(version, VERSION_PATTERN):
		e.append("schema version 非法：'%s'（需 semver）" % version)
	if String(s.get("title", "")) == "":
		e.append("schema title 不能为空")
	var stype := String(s.get("type", ""))
	if not (stype in ALLOWED_TYPES):
		e.append("schema type 非法：'%s'" % stype)
	if not (s.get("properties", null) is Dictionary):
		e.append("schema.properties 必须是对象")
		return e
	var props: Dictionary = s.get("properties", {})
	if props.is_empty():
		e.append("schema.properties 不能为空")
	if not (s.get("required", null) is Array):
		e.append("schema.required 必须是数组")
		return e
	var req: Array = s.get("required", [])
	for raw_req in req:
		var rk := String(raw_req)
		if not props.has(rk):
			e.append("required 字段不在 properties：" + rk)
	for raw_key in props.keys():
		var key := String(raw_key)
		var p = props[raw_key]
		if not (p is Dictionary):
			e.append("property %s 必须是对象" % key)
			continue
		e.append_array(_validate_prop(key, p))
	if not (s.get("example", null) is Dictionary):
		e.append("schema.example 必须是对象")
	else:
		var ex: Dictionary = s.get("example", {})
		e.append_array(validate_instance_against(s, ex))
	return e

func _validate_prop(name: String, p: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var t := String(p.get("type", ""))
	if not (t in ALLOWED_TYPES):
		e.append("property %s.type 非法：'%s'" % [name, t])
	if p.has("enum"):
		var en = p.get("enum")
		if not (en is Array) or (en as Array).is_empty():
			e.append("property %s.enum 必须是非空数组" % name)
		else:
			for raw_v in (en as Array):
				if not _json_primitive(raw_v):
					e.append("property %s.enum 含非标量" % name)
	if p.has("min"):
		if not _is_number(p.get("min")):
			e.append("property %s.min 必须是数字" % name)
	if p.has("max"):
		if not _is_number(p.get("max")):
			e.append("property %s.max 必须是数字" % name)
	if p.has("minItems") and int(p.get("minItems", -1)) < 0:
		e.append("property %s.minItems 必须 >=0" % name)
	if p.has("maxItems") and int(p.get("maxItems", -1)) < 0:
		e.append("property %s.maxItems 必须 >=0" % name)
	var numeric := t in ["number", "integer"]
	if t == "array" and p.get("items") is Dictionary:
		var it: Dictionary = p.get("items", {})
		if String(it.get("type", "")) == "number" or String(it.get("type", "")) == "integer":
			numeric = true
	if numeric:
		if not p.has("unit"):
			e.append("property %s 数值字段必须有 unit" % name)
		elif not (String(p.get("unit", "")) in ALLOWED_UNITS):
			e.append("property %s unit 非法：'%s'" % [name, String(p.get("unit", ""))])
	elif p.has("unit") and not (String(p.get("unit", "")) in ALLOWED_UNITS):
		e.append("property %s unit 非法：'%s'" % [name, String(p.get("unit", ""))])
	return e

# ── 实例校验 ────────────────────────────────────────────────────

func validate_instance(schema_id: String, data) -> Dictionary:
	if not schemas.has(schema_id):
		return {"ok": false, "schema_id": schema_id,
			"errors": ["unknown schema: " + schema_id]}
	if not (data is Dictionary):
		return {"ok": false, "schema_id": schema_id, "errors": ["instance 必须是对象"]}
	var e: Array[String] = validate_instance_against(schemas[schema_id], data)
	return {"ok": e.is_empty(), "schema_id": schema_id, "errors": e}

func validate_instance_against(schema: Dictionary, data: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if schema.is_empty():
		e.append("schema 为空")
		return e
	var t := String(schema.get("type", "object"))
	if t != "object":
		e.append("当前 loader 只校验 object schema")
		return e
	var req: Array = schema.get("required", []) if schema.get("required") is Array else []
	for raw_req in req:
		var key := String(raw_req)
		if not data.has(key):
			e.append("缺必需字段：" + key)
	var props: Dictionary = schema.get("properties", {}) if schema.get("properties") is Dictionary else {}
	for raw_key in props.keys():
		var key2 := String(raw_key)
		if not data.has(key2):
			continue
		var p: Dictionary = props[raw_key]
		e.append_array(_check_value(key2, p, data.get(key2)))
		var unit_key := key2 + "_unit"
		if data.has(unit_key):
			var expect_unit := String(p.get("unit", "none"))
			if String(data.get(unit_key)) != expect_unit and expect_unit != "":
				e.append("字段 %s 单位错误：'%s' != '%s'" % [key2,
					String(data.get(unit_key)), expect_unit])
	return e

func _check_value(path: String, p: Dictionary, value) -> Array[String]:
	var e: Array[String] = []
	var t := String(p.get("type", ""))
	match t:
		"string":
			if not (value is String):
				e.append("字段 %s 应为 string" % path)
				return e
		"number":
			if not _is_number(value):
				e.append("字段 %s 应为 number" % path)
				return e
		"integer":
			if not (_is_number(value) and float(value) == floorf(float(value))):
				e.append("字段 %s 应为 integer" % path)
				return e
		"boolean":
			if not (value is bool):
				e.append("字段 %s 应为 boolean" % path)
				return e
		"object":
			if not (value is Dictionary):
				e.append("字段 %s 应为 object" % path)
				return e
		"array":
			if not (value is Array):
				e.append("字段 %s 应为 array" % path)
				return e
			if p.has("minItems") and (value as Array).size() < int(p.get("minItems", 0)):
				e.append("字段 %s 元素数不足（minItems=%d）" % [path, int(p.get("minItems", 0))])
			if p.has("maxItems") and (value as Array).size() > int(p.get("maxItems", 0)):
				e.append("字段 %s 元素数超限（maxItems=%d）" % [path, int(p.get("maxItems", 0))])
			if p.get("items") is Dictionary:
				var it: Dictionary = p.get("items", {})
				var idx := 0
				for raw_item in (value as Array):
					e.append_array(_check_value("%s[%d]" % [path, idx], it, raw_item))
					idx += 1
			return e
		_:
			return e
	if p.has("enum"):
		var ok_enum := false
		for raw_v in (p.get("enum", []) as Array):
			if raw_v == value:
				ok_enum = true
				break
		if not ok_enum:
			e.append("字段 %s 枚举非法：%s" % [path, str(value)])
	if p.has("min") and float(value) < float(p.get("min", value)):
		e.append("字段 %s 小于 min" % path)
	if p.has("max") and float(value) > float(p.get("max", value)):
		e.append("字段 %s 大于 max" % path)
	return e

# ── 查询 ────────────────────────────────────────────────────────

func schema(schema_id: String) -> Dictionary:
	return (schemas.get(schema_id, {}) as Dictionary).duplicate(true)

func ids() -> Array:
	return schema_ids.duplicate()

func example(schema_id: String) -> Dictionary:
	return (examples.get(schema_id, {}) as Dictionary).duplicate(true)

func count() -> int:
	return schema_ids.size()

func to_dict() -> Dictionary:
	return {
		"schema": "v17.schema_loader.v1",
		"root": root_path,
		"ready": ready,
		"count": schema_ids.size(),
		"ids": schema_ids.duplicate(),
		"formats": {"schema": SCHEMA_FORMAT, "version_pattern": VERSION_PATTERN},
		"allowed_types": ALLOWED_TYPES.duplicate(),
		"allowed_units": ALLOWED_UNITS.duplicate(),
		"schemas": schemas.duplicate(true),
		"examples": examples.duplicate(true),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}

func reset() -> void:
	ready = false
	schemas = {}
	schema_ids = []
	examples = {}
	loaded_files = []
	errors.clear()
	warnings.clear()

# ── 工具 ────────────────────────────────────────────────────────

func _matches(value: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(value) != null

func _is_number(v) -> bool:
	return (v is int) or (v is float)

func _json_primitive(v) -> bool:
	return (v is String) or (v is bool) or _is_number(v)
