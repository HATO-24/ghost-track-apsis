class_name V2CompactEphemeris
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2D · 紧凑星历接口（JPL 派生格式；只读）
#
# 设计原则：
#   * 仓库**不附带 JPL 数据**；本接口只定义/校验“JPL 派生紧凑星历”格式。
#   * data/ephemeris 无表时：明确 available=false，用解析地球/月球参考做
#     **analytic fallback**（earth_eci；不冒充 JPL）。
#   * 有表时：校验 schema/source/version/frame/units/time_window/bodies，
#     在时间窗内插值；非法表拒绝，不静默使用。
#   * API：load/available/body_state/bodies/to_dict/errors/warnings/validate_table/
#     load_data；只读，不写 world/V15。
#
# 单位：km / km/s / s；角度 rad。frame 默认 earth_eci（地心惯性）。
# ═══════════════════════════════════════════════════════════════════

const Physics := preload("res://framework/sim/cislunar_physics.gd")

const SCHEMA_TABLE := "v17_compact_ephemeris.v1"
const SCHEMA_API := "compact_ephemeris.v1"
const DEFAULT_DIR := "res://data/ephemeris"
const ALLOWED_FRAMES := ["earth_eci", "bary_rot", "earth_rot"]
const ALLOWED_INTERP := ["chebyshev", "kepler"]
const MAX_TABLE_BYTES := 8 * 1024 * 1024
const MAX_BODIES := 64
const MAX_SEGMENTS := 4096
const MAX_COEFFS := 64

var ready := false
var available_flag := false
var using_analytic := false
var table_path := ""
var table: Dictionary = {}
var source: Dictionary = {}
var version := ""
var frame := "earth_eci"
var units: Dictionary = {"length": "km", "time": "s", "velocity": "km/s",
	"angle": "rad"}
var time_scale := "TDB"
var time_window: Dictionary = {"start_s": 0.0, "end_s": 0.0}
var bodies_data: Dictionary = {}
var errors: Array = []
var warnings: Array = []
var loaded := false


func _init(path := "") -> void:
	self.load(path)


# ── 加载 / 校验 ─────────────────────────────────────────────────

## path 为空 → 扫描 res://data/ephemeris；无表时 analytic fallback。
## path 可为目录或单个 JSON 文件。返回 available（有合法表）。
func load(path := "") -> bool:
	reset()
	loaded = true
	var p := String(path)
	if p == "":
		p = DEFAULT_DIR
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p)):
		_load_dir(ProjectSettings.globalize_path(p))
	elif FileAccess.file_exists(p):
		_load_file(p)
	else:
		warnings.append("EPHEMERIS DIR NOT FOUND: %s；使用 analytic fallback（earth/moon）" % p)
		_set_analytic_fallback()
	if not available_flag and not using_analytic:
		_set_analytic_fallback()
	ready = loaded
	return available_flag


func _load_dir(dir_path: String) -> void:
	var files: Array = DirAccess.get_files_at(dir_path)
	if files.is_empty():
		warnings.append("NO_EPHEMERIS_TABLE: %s 下无 .json；使用 analytic fallback（earth/moon）" % dir_path)
		return
	files.sort()
	for raw in files:
		var name := String(raw)
		if not name.ends_with(".json"):
			continue
		var full := dir_path.path_join(name)
		if _load_file(full):
			return
	# 所有文件都不合法：errors 已记录；fallback 由 load 兜底


func _load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		errors.append("table 文件不存在: " + path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("table 文件不可读: " + path)
		return false
	var size := f.get_length()
	if size <= 0 or size > MAX_TABLE_BYTES:
		f.close()
		errors.append("table 文件大小非法: %s (%d bytes)" % [path, size])
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		errors.append("table JSON 无效: " + path)
		return false
	var data: Dictionary = parsed
	var vr := validate_table(data)
	if not bool(vr.get("ok", false)):
		for e in (vr.get("errors", []) as Array):
			errors.append("table %s: %s" % [path, String(e)])
		return false
	table_path = path
	_apply_table(data)
	return true


func validate_table(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["table 必须是 JSON 对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != SCHEMA_TABLE:
		errs.append("schema 必须为 " + SCHEMA_TABLE)
	# source 契约：真实来源必须可审计；测试夹具也应明确非 JPL
	var src = d.get("source", null)
	if not (src is Dictionary):
		errs.append("source 必须是对象")
	else:
		var s: Dictionary = src
		for k in ["provider", "derived_from", "license", "generated_at"]:
			if String(s.get(k, "")).strip_edges() == "":
				errs.append("source.%s 不能为空" % k)
	if String(d.get("version", "")).strip_edges() == "":
		errs.append("version 不能为空")
	var fr := String(d.get("frame", ""))
	if not (fr in ALLOWED_FRAMES):
		errs.append("frame 不受支持: " + fr)
	var u = d.get("units", null)
	if not (u is Dictionary):
		errs.append("units 必须为对象")
	else:
		var ud: Dictionary = u
		if String(ud.get("length", "")) != "km":
			errs.append("units.length 必须 km")
		if String(ud.get("time", "")) != "s":
			errs.append("units.time 必须 s")
		if String(ud.get("velocity", "")) != "km/s":
			errs.append("units.velocity 必须 km/s")
	var tw = d.get("time_window", null)
	if not (tw is Dictionary):
		errs.append("time_window 必须为对象")
	else:
		var w: Dictionary = tw
		var ts := float(w.get("start_s", NAN))
		var te := float(w.get("end_s", NAN))
		if not is_finite(ts) or not is_finite(te):
			errs.append("time_window 必须含有限 start_s/end_s")
		elif te <= ts:
			errs.append("time_window.end_s 必须 > start_s")
	var bs = d.get("bodies", null)
	if not (bs is Dictionary):
		errs.append("bodies 必须为对象")
	elif (bs as Dictionary).is_empty():
		errs.append("bodies 不能为空")
	elif (bs as Dictionary).size() > MAX_BODIES:
		errs.append("bodies 过多")
	else:
		for bid in (bs as Dictionary).keys():
			var one = (bs as Dictionary)[bid]
			if not (one is Dictionary):
				errs.append("body %s 必须为对象" % String(bid))
				continue
			errs.append_array(_validate_body(String(bid), one as Dictionary))
	return {"ok": errs.is_empty(), "errors": errs}


func _validate_body(id: String, b: Dictionary) -> Array:
	var errs: Array = []
	if String(b.get("body_id", "")).strip_edges() == "":
		errs.append("body %s 缺 body_id" % id)
	var interp := String(b.get("interpolation", ""))
	if not (interp in ALLOWED_INTERP):
		errs.append("body %s interpolation 不支持: %s" % [id, interp])
		return errs
	if b.has("max_error_km"):
		var me := float(b.get("max_error_km", -1.0))
		if not is_finite(me) or me < 0.0:
			errs.append("body %s max_error_km 非法" % id)
	if interp == "chebyshev":
		errs.append_array(_validate_chebyshev(id, b))
	elif interp == "kepler":
		errs.append_array(_validate_kepler(id, b))
	return errs


func _validate_chebyshev(id: String, b: Dictionary) -> Array:
	var errs: Array = []
	var segs = b.get("segments", null)
	if not (segs is Array) or (segs as Array).is_empty():
		errs.append("body %s chebyshev 缺 segments" % id)
		return errs
	if (segs as Array).size() > MAX_SEGMENTS:
		errs.append("body %s segments 过多" % id)
		return errs
	for i in range((segs as Array).size()):
		var s = (segs as Array)[i]
		if not (s is Dictionary):
			errs.append("body %s segments[%d] 必须为对象" % [id, i])
			continue
		var sg: Dictionary = s
		var t0 := float(sg.get("t0", NAN))
		var t1 := float(sg.get("t1", NAN))
		if not is_finite(t0) or not is_finite(t1) or t1 <= t0:
			errs.append("body %s segments[%d] t0/t1 非法" % [id, i])
		var order := int(sg.get("order", -1))
		if order < 1 or order > MAX_COEFFS:
			errs.append("body %s segments[%d] order 非法" % [id, i])
		var coeffs = sg.get("coeffs", null)
		if not (coeffs is Dictionary):
			errs.append("body %s segments[%d] 缺 coeffs" % [id, i])
			continue
		var cd: Dictionary = coeffs
		for axis in ["x", "y", "z"]:
			var a = cd.get(axis, null)
			if not (a is Array) or (a as Array).size() < 2:
				errs.append("body %s segments[%d].coeffs.%s 至少 2 项" % [id, i, axis])
				continue
			if (a as Array).size() > MAX_COEFFS:
				errs.append("body %s segments[%d].coeffs.%s 过多" % [id, i, axis])
			for v in (a as Array):
				if not is_finite(float(v)):
					errs.append("body %s segments[%d].coeffs.%s 含非有限值" % [id, i, axis])
					break
	return errs


func _validate_kepler(id: String, b: Dictionary) -> Array:
	var errs: Array = []
	var el = b.get("kepler", null)
	if not (el is Dictionary):
		errs.append("body %s kepler 缺 kepler 元素" % id)
		return errs
	var e: Dictionary = el
	for k in ["a", "e", "i", "raan", "argp", "M0", "n"]:
		if not e.has(k):
			errs.append("body %s kepler 缺 %s" % [id, k])
		elif not is_finite(float(e.get(k, NAN))):
			errs.append("body %s kepler.%s 非有限" % [id, k])
	if e.has("a") and float(e.get("a", 0.0)) <= 0.0:
		errs.append("body %s kepler.a 必须 >0" % id)
	if e.has("e") and (float(e.get("e", 0.0)) < 0.0 or float(e.get("e", 0.0)) >= 1.0):
		errs.append("body %s kepler.e 必须在 [0,1)" % id)
	if not e.has("epoch_s"):
		errs.append("body %s kepler 缺 epoch_s" % id)
	return errs


func _apply_table(data: Dictionary) -> void:
	table = data.duplicate(true)
	source = (data.get("source", {}) as Dictionary).duplicate(true)
	version = String(data.get("version", ""))
	frame = String(data.get("frame", "earth_eci"))
	units = (data.get("units", {}) as Dictionary).duplicate(true)
	time_scale = String(data.get("time_scale", "TDB"))
	time_window = (data.get("time_window", {}) as Dictionary).duplicate(true)
	bodies_data = (data.get("bodies", {}) as Dictionary).duplicate(true)
	available_flag = true
	using_analytic = false
	table_path = table_path
	errors.clear()


## 内存表加载（probe/测试夹具）；不会写入仓库/磁盘。
func load_data(data: Variant, source_name := "<memory>") -> bool:
	reset()
	loaded = true
	var vr := validate_table(data)
	if not bool(vr.get("ok", false)):
		for e in (vr.get("errors", []) as Array):
			errors.append("table %s: %s" % [source_name, String(e)])
		_set_analytic_fallback()
		ready = true
		return false
	table_path = source_name
	_apply_table(data as Dictionary)
	ready = true
	return true


func _set_analytic_fallback() -> void:
	available_flag = false
	using_analytic = true
	frame = "earth_eci"
	units = {"length": "km", "time": "s", "velocity": "km/s", "angle": "rad"}
	time_scale = "analytic"
	time_window = {"start_s": -1.0e18, "end_s": 1.0e18}
	bodies_data = {}
	source = {"provider": "analytic", "derived_from": "earth/moon analytic reference",
		"license": "internal", "generated_at": "runtime"}
	warnings.append("ANALYTIC FALLBACK: earth/moon analytic reference（非 JPL；available=false）")


func reset() -> void:
	ready = false
	available_flag = false
	using_analytic = false
	table_path = ""
	table = {}
	source = {}
	version = ""
	frame = "earth_eci"
	units = {"length": "km", "time": "s", "velocity": "km/s", "angle": "rad"}
	time_scale = "TDB"
	time_window = {"start_s": 0.0, "end_s": 0.0}
	bodies_data = {}
	errors = []
	warnings = []
	loaded = false


# ── 查询 ────────────────────────────────────────────────────────

func available() -> bool:
	return available_flag


func using_analytic_fallback() -> bool:
	return using_analytic


func bodies() -> Array:
	var out: Array = []
	if available_flag:
		for bid in bodies_data.keys():
			var b: Dictionary = bodies_data[bid] as Dictionary
			out.append({
				"id": String(bid), "body_id": String(b.get("body_id", "")),
				"center": String(b.get("center", "")),
				"interpolation": String(b.get("interpolation", "")),
				"frame": frame, "max_error_km": float(b.get("max_error_km", -1.0)),
				"source": "table", "analytic_fallback": false,
			})
	else:
		for bid in ["earth", "moon"]:
			out.append({"id": bid, "body_id": "399" if bid == "earth" else "301",
				"center": "earth" if bid == "moon" else "ssb",
				"interpolation": "analytic", "frame": "earth_eci",
				"max_error_km": -1.0, "source": "analytic_fallback",
				"analytic_fallback": true})
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


func body_state(id: String, t: float) -> Dictionary:
	var body_id := _normalize_body(id)
	if not is_finite(t):
		return {"ok": false, "reason": "non_finite_time", "body": body_id}
	if available_flag:
		var b = _find_body(body_id)
		if not (b is Dictionary) or (b as Dictionary).is_empty():
			return {"ok": false, "reason": "unknown_body", "body": body_id,
				"available": true, "frame": frame}
		var start := float(time_window.get("start_s", 0.0))
		var end := float(time_window.get("end_s", 0.0))
		if t < start - 1.0e-9 or t > end + 1.0e-9:
			return {"ok": false, "reason": "out_of_time_window", "body": body_id,
				"t": t, "time_window": time_window.duplicate(true),
				"available": true, "frame": frame}
		var st := _eval_body(b as Dictionary, t)
		if not bool(st.get("ok", false)):
			st["body"] = body_id
			st["available"] = true
			return st
		return {
			"ok": true, "reason": "", "schema": SCHEMA_API,
			"body": body_id, "body_id": String((b as Dictionary).get("body_id", "")),
			"t": t, "frame": frame, "units": units.duplicate(true),
			"time_scale": time_scale,
			"position_km": st.get("position_km", []),
			"velocity_kmps": st.get("velocity_kmps", []),
			"speed_kmps": st.get("speed_kmps", 0.0),
			"interpolation": String((b as Dictionary).get("interpolation", "")),
			"max_error_km": float((b as Dictionary).get("max_error_km", -1.0)),
			"source": "table", "source_meta": source.duplicate(true),
			"table_path": table_path, "available": true,
			"analytic_fallback": false, "writes_v15": false,
		}
	# 无表 analytic fallback：earth/moon 参考
	return _analytic_body_state(body_id, t)


func _normalize_body(id: String) -> String:
	var s := id.strip_edges().to_lower()
	if s in ["earth", "399", "terra"]:
		return "earth"
	if s in ["moon", "301", "luna"]:
		return "moon"
	return s


func _find_body(id: String) -> Dictionary:
	if bodies_data.has(id):
		return bodies_data[id] as Dictionary
	for bid in bodies_data.keys():
		var b = bodies_data[bid]
		if b is Dictionary and String((b as Dictionary).get("body_id", "")) == id:
			return b as Dictionary
	return {}


func _analytic_body_state(id: String, t: float) -> Dictionary:
	var pos := [0.0, 0.0, 0.0]
	var vel := [0.0, 0.0, 0.0]
	var src := "analytic_earth_reference"
	if id == "moon":
		var ms: Dictionary = Physics.moon_state_eci(t)
		pos = Physics.vec3_to_array(ms.get("r", Vector3.ZERO))
		vel = Physics.vec3_to_array(ms.get("v", Vector3.ZERO))
		src = "analytic_moon_reference"
	elif id != "earth":
		return {"ok": false, "reason": "unknown_body", "body": id,
			"available": false, "analytic_fallback": true}
	var speed := sqrt(vel[0] * vel[0] + vel[1] * vel[1] + vel[2] * vel[2])
	return {
		"ok": true, "reason": "", "schema": SCHEMA_API, "body": id,
		"body_id": "399" if id == "earth" else "301",
		"t": t, "frame": "earth_eci",
		"units": units.duplicate(true), "time_scale": "analytic",
		"position_km": pos, "velocity_kmps": vel, "speed_kmps": speed,
		"interpolation": "analytic", "max_error_km": -1.0,
		"source": src, "source_meta": source.duplicate(true),
		"table_path": "", "available": false,
		"analytic_fallback": true, "writes_v15": false,
	}


# ── 插值实现 ───────────────────────────────────────────────────

func _eval_body(b: Dictionary, t: float) -> Dictionary:
	var interp := String(b.get("interpolation", ""))
	if interp == "chebyshev":
		return _eval_chebyshev(b, t)
	if interp == "kepler":
		return _eval_kepler(b, t)
	return {"ok": false, "reason": "unsupported_interpolation"}


func _eval_chebyshev(b: Dictionary, t: float) -> Dictionary:
	var segs: Array = b.get("segments", []) if b.get("segments") is Array else []
	for raw in segs:
		if not (raw is Dictionary):
			continue
		var s: Dictionary = raw
		var t0 := float(s.get("t0", 0.0))
		var t1 := float(s.get("t1", 0.0))
		if t < t0 - 1.0e-9 or t > t1 + 1.0e-9:
			continue
		var coeffs: Dictionary = s.get("coeffs", {}) if s.get("coeffs") is Dictionary else {}
		var tau := 0.0
		if t1 > t0:
			tau = clampf((2.0 * t - t1 - t0) / (t1 - t0), -1.0, 1.0)
		var pos: Array = []
		var vel: Array = []
		for axis in ["x", "y", "z"]:
			var arr: Array = coeffs.get(axis, []) if coeffs.get(axis) is Array else []
			var ev := _cheb_sum(arr, tau)
			var dv := _cheb_deriv(arr, tau)
			var scale := 2.0 / maxf(1.0e-9, t1 - t0)
			pos.append(float(ev["value"]))
			vel.append(float(dv) * scale)
		var speed := sqrt(vel[0] * vel[0] + vel[1] * vel[1] + vel[2] * vel[2])
		return {"ok": true, "position_km": pos, "velocity_kmps": vel,
			"speed_kmps": speed, "segment_t0": t0, "segment_t1": t1}
	return {"ok": false, "reason": "out_of_time_window"}


func _cheb_sum(coeffs: Array, tau: float) -> Dictionary:
	var n := coeffs.size()
	if n == 0:
		return {"value": 0.0, "dvalue": 0.0}
	var t0 := 1.0
	var t1 := tau
	var sum := float(coeffs[0]) if n > 0 else 0.0
	if n > 1:
		sum += float(coeffs[1]) * t1
	for k in range(2, n):
		var t2 := 2.0 * tau * t1 - t0
		sum += float(coeffs[k]) * t2
		t0 = t1
		t1 = t2
	return {"value": sum}


func _cheb_deriv(coeffs: Array, tau: float) -> float:
	var n := coeffs.size()
	if n < 2:
		return 0.0
	# 逐项求导的 Chebyshev 系数：b[k-1] += 2k*c[k]，然后按 Chebyshev 求和
	var d: Array = []
	for i in range(n - 1):
		d.append(0.0)
	for k in range(1, n):
		d[k - 1] = float(d[k - 1]) + 2.0 * float(k) * float(coeffs[k])
	# 导数 Chebyshev 级数的首项系数按惯例取半（f' = b0/2*T0 + b1*T1 + ...）。
	var deriv_sum := float(_cheb_sum(d, tau).get("value", 0.0))
	return deriv_sum - 0.5 * float(d[0])


func _eval_kepler(b: Dictionary, t: float) -> Dictionary:
	var e: Dictionary = b.get("kepler", {}) if b.get("kepler") is Dictionary else {}
	var a := float(e.get("a", 0.0))
	var ecc := float(e.get("e", 0.0))
	var inc := float(e.get("i", 0.0))
	var raan := float(e.get("raan", 0.0))
	var argp := float(e.get("argp", 0.0))
	var m0 := float(e.get("M0", 0.0))
	var n := float(e.get("n", 0.0))
	var epoch := float(e.get("epoch_s", 0.0))
	var mu := float(e.get("mu_km3_s2", Physics.MU_EARTH_KM3_S2))
	if a <= 0.0 or ecc < 0.0 or ecc >= 1.0:
		return {"ok": false, "reason": "invalid_kepler_elements"}
	var M := m0 + n * (t - epoch)
	M = fposmod(M, TAU)
	var E := M
	for _i in range(20):
		var f := E - ecc * sin(E) - M
		var fp := 1.0 - ecc * cos(E)
		if absf(fp) < 1.0e-12:
			break
		E -= f / fp
		if absf(f) < 1.0e-12:
			break
	var cosE := cos(E)
	var sinE := sin(E)
	var r := a * (1.0 - ecc * cosE)
	var x_p := a * (cosE - ecc)
	var y_p := a * sqrt(maxf(0.0, 1.0 - ecc * ecc)) * sinE
	var vx_p := -a * n * sinE / maxf(1.0e-12, 1.0 - ecc * cosE)
	var vy_p := a * n * sqrt(maxf(0.0, 1.0 - ecc * ecc)) * cosE / maxf(1.0e-12, 1.0 - ecc * cosE)
	# 旋转到惯性系（raan, inc, argp）
	var cO := cos(raan)
	var sO := sin(raan)
	var ci := cos(inc)
	var si := sin(inc)
	var cw := cos(argp)
	var sw := sin(argp)
	var m11 := cO * cw - sO * sw * ci
	var m12 := -cO * sw - sO * cw * ci
	var m21 := sO * cw + cO * sw * ci
	var m22 := -sO * sw + cO * cw * ci
	var m31 := sw * si
	var m32 := cw * si
	var pos := [m11 * x_p + m12 * y_p, m21 * x_p + m22 * y_p, m31 * x_p + m32 * y_p]
	var vel := [m11 * vx_p + m12 * vy_p, m21 * vx_p + m22 * vy_p, m31 * vx_p + m32 * vy_p]
	var speed := sqrt(vel[0] * vel[0] + vel[1] * vel[1] + vel[2] * vel[2])
	return {"ok": true, "position_km": pos, "velocity_kmps": vel, "speed_kmps": speed,
		"radius_km": r, "mu_km3_s2": mu}


# ── JSON ────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_API, "ready": ready, "available": available_flag,
		"using_analytic_fallback": using_analytic,
		"table_path": table_path,
		"source": source.duplicate(true), "version": version,
		"frame": frame, "units": units.duplicate(true), "time_scale": time_scale,
		"time_window": time_window.duplicate(true),
		"bodies": bodies(),
		"body_count": bodies().size(),
		"errors": errors.duplicate(), "warnings": warnings.duplicate(),
		"note": "仓库不含 JPL 数据；有表时按表的 source/version 审计；无表仅 analytic earth/moon fallback",
		"writes": {"track_table": false, "v15": false},
	}


func summary() -> Dictionary:
	return {
		"schema": SCHEMA_API, "ready": ready, "available": available_flag,
		"using_analytic": using_analytic, "frame": frame,
		"time_window": time_window.duplicate(true),
		"body_count": bodies().size(), "errors": errors.size(),
		"warnings": warnings.size(), "writes_v15": false,
	}


func to_json() -> String:
	return JSON.stringify(to_dict())
