extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2A：TimeService（仿真时间内核；新文件，不依赖 UI）
#
# - 仿真时间/epoch/时标（scale）/暂停/时间窗/港内时间（docked）；
# - tick(dt) 单调：负/非有限 dt 拒绝；dt 上限裁剪（max_dt）；暂停不推进；
# - DbC：前置检查（finite dt/scale/window）与后置不变量（t>=0、docked_s<=t、window 合法）；
# - 不写 world/scene/UI；snapshot() 只读 JSON。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.time_service.v1"
const MODE_PAUSED := "paused"
const MODE_RUNNING := "running"
const MODES := [MODE_PAUSED, MODE_RUNNING]
const DEFAULT_EPOCH_S := 760.8
const DEFAULT_MAX_DT_S := 3600.0
# A-02：历元来源。日历历元（scenario UTC）与动力学相位基准（epoch_s / CR3BP）**分开**。
const EPOCH_SOURCE_SCENARIO := "scenario"
const EPOCH_SOURCE_LEGACY := "legacy_unknown"
const EPOCH_SOURCE_INVALID := "invalid"
# 动力学相位基准标签（与日历历元分离，禁止混用）
const PHASE_BASIS_CR3BP := "cr3bp_phase_s"

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var t_s := 0.0
# 动力学相位基准（CR3BP 相位时刻；**不是** Unix epoch，也不是日历时刻）
var epoch_s := DEFAULT_EPOCH_S
# A-02：日历历元元数据（唯一来源；由 scenario UTC 解析一次）
var calendar_epoch_utc := ""
var calendar_epoch_unix_s := -1.0
var epoch_source := EPOCH_SOURCE_LEGACY
var scale := 1.0
var paused := false
var docked := false
var docked_s := 0.0
var window_active := false
var window_duration_s := 0.0
var window_left_s := 0.0
var window_expired := false
var tick_count := 0
var last_dt_s := 0.0
var max_dt_s := DEFAULT_MAX_DT_S

func _init(opts := {}) -> void:
	setup(opts)

func setup(opts := {}) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	t_s = float(o.get("t_s", 0.0))
	epoch_s = float(o.get("epoch_s", DEFAULT_EPOCH_S))
	# A-02：日历历元。空 = 旧 seed（legacy，标记不伪造）；非法 = 显式拒绝。
	calendar_epoch_utc = String(o.get("epoch_utc", "")).strip_edges()
	calendar_epoch_unix_s = -1.0
	epoch_source = EPOCH_SOURCE_LEGACY
	if calendar_epoch_utc != "":
		var parsed := _parse_utc_epoch(calendar_epoch_utc)
		if bool(parsed.get("ok", false)):
			calendar_epoch_unix_s = float(parsed.get("unix_s", -1.0))
			epoch_source = EPOCH_SOURCE_SCENARIO
		else:
			epoch_source = EPOCH_SOURCE_INVALID
			errors.append("precondition: 非法 UTC 历元 '" + calendar_epoch_utc + "'")
			return false
	scale = float(o.get("scale", 1.0))
	paused = bool(o.get("paused", false))
	docked = bool(o.get("docked", false))
	docked_s = float(o.get("docked_s", 0.0))
	window_duration_s = float(o.get("window_duration_s", 0.0))
	window_left_s = window_duration_s
	window_active = window_duration_s > 0.0
	window_expired = false
	tick_count = 0
	last_dt_s = 0.0
	max_dt_s = float(o.get("max_dt_s", DEFAULT_MAX_DT_S))
	# DbC 前置：参数合法
	var pre := _pre_setup()
	contract_errors.append_array(pre)
	if not pre.is_empty():
		errors.append_array(pre)
		return false
	var inv: Array = _invariants()
	contract_errors.append_array(inv)
	if not inv.is_empty():
		errors.append_array(inv)
		return false
	ready = true
	return true

func _pre_setup() -> Array[String]:
	var e: Array[String] = []
	if not is_finite(t_s) or t_s < 0.0:
		e.append("precondition: t_s 必须为有限非负数")
	if not is_finite(epoch_s):
		e.append("precondition: epoch_s 必须有限")
	if not is_finite(scale) or scale < 0.0:
		e.append("precondition: scale 必须有限且 >=0")
	if not is_finite(docked_s) or docked_s < 0.0:
		e.append("precondition: docked_s 必须有限且 >=0")
	if not is_finite(max_dt_s) or max_dt_s <= 0.0:
		e.append("precondition: max_dt_s 必须有限且 >0")
	if not is_finite(window_duration_s) or window_duration_s < 0.0:
		e.append("precondition: window_duration_s 必须有限且 >=0")
	if docked_s > t_s + 1.0e-9:
		e.append("precondition: docked_s 不能大于 t_s")
	return e

## 推进仿真时间（dt 为真实秒；乘以 time_scale）。暂停时返回 t 不变。
func tick(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	# DbC 前置
	if not is_finite(dt) or dt < 0.0:
		_contract("precondition: tick(dt) 要求 dt 有限且 >=0")
		return {"ok": false, "reason": "invalid_dt", "t_s": t_s,
			"errors": contract_errors.duplicate()}
	if paused:
		last_dt_s = 0.0
		tick_count += 1
		_check_post()
		return {"ok": true, "t_s": t_s, "dt_scaled_s": 0.0, "paused": true,
			"docked_s": docked_s, "window_left_s": window_left_s}
	var scaled := dt * scale
	if scaled > max_dt_s:
		warnings.append("dt_scaled %.1fs > max_dt %.1fs，已裁剪" % [scaled, max_dt_s])
		scaled = max_dt_s
	t_s += scaled
	last_dt_s = scaled
	tick_count += 1
	if docked:
		docked_s += scaled
	if window_active:
		window_left_s = maxf(0.0, window_left_s - scaled)
		if window_left_s <= 1.0e-9:
			window_left_s = 0.0
			window_active = false
			window_expired = true
			warnings.append("时间窗已过期")
	_check_post()
	return {"ok": true, "t_s": t_s, "dt_scaled_s": scaled, "paused": false,
		"docked_s": docked_s, "window_active": window_active,
		"window_left_s": window_left_s, "window_expired": window_expired}

func pause() -> Dictionary:
	paused = true
	return {"ok": true, "paused": true, "t_s": t_s}

func resume() -> Dictionary:
	paused = false
	return {"ok": true, "paused": false, "t_s": t_s}

func set_scale(new_scale: float) -> Dictionary:
	if not is_finite(new_scale) or new_scale < 0.0:
		_contract("precondition: scale 必须有限且 >=0")
		return {"ok": false, "reason": "invalid_scale", "errors": contract_errors.duplicate()}
	scale = new_scale
	_check_post()
	return {"ok": true, "scale": scale}

func set_docked(on: bool) -> Dictionary:
	docked = bool(on)
	_check_post()
	return {"ok": true, "docked": docked, "docked_s": docked_s}

## 设置时间窗（秒）；0 关闭。窗口只影响 window_left/expired，不阻止 tick。
func set_window(duration_s: float) -> Dictionary:
	if not is_finite(duration_s) or duration_s < 0.0:
		_contract("precondition: window_duration_s 必须有限且 >=0")
		return {"ok": false, "reason": "invalid_window", "errors": contract_errors.duplicate()}
	window_duration_s = duration_s
	window_left_s = duration_s
	window_active = duration_s > 0.0
	window_expired = false
	return {"ok": true, "window_active": window_active, "window_left_s": window_left_s}

func clear_window() -> Dictionary:
	window_duration_s = 0.0
	window_left_s = 0.0
	window_active = false
	window_expired = false
	return {"ok": true}

## 显式 seek：只允许向前（保证 tick 单调语义）；负值/回退拒绝。
func seek(new_t_s: float) -> Dictionary:
	if not is_finite(new_t_s) or new_t_s < 0.0:
		_contract("precondition: seek 目标必须有限且 >=0")
		return {"ok": false, "reason": "invalid_seek", "errors": contract_errors.duplicate()}
	if new_t_s < t_s - 1.0e-9:
		_contract("precondition: seek 不允许回退（%.3f < %.3f）" % [new_t_s, t_s])
		return {"ok": false, "reason": "backwards_seek", "t_s": t_s,
			"errors": contract_errors.duplicate()}
	docked_s = minf(docked_s, new_t_s)
	t_s = new_t_s
	_check_post()
	return {"ok": true, "t_s": t_s, "docked_s": docked_s}

func now_s() -> float:
	return t_s

func now_days() -> float:
	return t_s / 86400.0

func epoch_abs_s() -> float:
	return epoch_s + t_s


# ── A-02：日历历元（唯一来源）────────────────────────────────

## 解析并校验 UTC 字符串（要求往返一致，避免把非法串当成 0 时刻）。
func _parse_utc_epoch(text: String) -> Dictionary:
	var s := String(text).strip_edges()
	if s == "":
		return {"ok": false, "reason": "empty"}
	# 统一成 Godot 期望的无时区形式（尾部 Z）
	var probe := s
	if probe.ends_with("Z"):
		probe = probe.substr(0, probe.length() - 1)
	var unix_s := Time.get_unix_time_from_datetime_string(probe)
	if unix_s == 0 and probe.substr(0, 4) != "1970":
		return {"ok": false, "reason": "unparsable"}
	# 往返校验：解析回来必须与输入一致（拒绝 2193-13-45 之类溢出值）。
	# Godot 的 datetime string 用空格分隔（"YYYY-MM-DD HH:MM:SS"），先把输入归一化。
	var norm_in := probe.replace("T", " ").replace("t", " ")
	var back := Time.get_datetime_string_from_unix_time(unix_s, true)
	if back != norm_in:
		return {"ok": false, "reason": "roundtrip_mismatch",
			"parsed": back, "input": norm_in}
	return {"ok": true, "unix_s": float(unix_s), "utc": norm_in}


## 相对秒 → 绝对日历时刻（UTC 字符串）。历元未知时返回 ""（不伪造日期）。
func calendar_at(rel_s: float) -> String:
	if epoch_source != EPOCH_SOURCE_SCENARIO or calendar_epoch_unix_s < 0.0:
		return ""
	var abs_s := int(round(calendar_epoch_unix_s + float(rel_s)))
	return Time.get_datetime_string_from_unix_time(abs_s, true)


func calendar_now_utc() -> String:
	if epoch_source != EPOCH_SOURCE_SCENARIO:
		return ""
	return Time.get_datetime_string_from_unix_time(
		int(round(calendar_epoch_unix_s + t_s)), true)


## 历元元数据（**唯一权威**）：日历历元与动力学相位基准则分别标明，禁止混用。
func epoch_meta() -> Dictionary:
	var known := (epoch_source == EPOCH_SOURCE_SCENARIO)
	return {
		"schema": "v17.time_epoch.v2",
		"epoch_source": epoch_source,
		"epoch_known": known,
		"epoch_unknown": not known,
		"calendar_epoch_utc": calendar_epoch_utc,
		"calendar_epoch_unix_s": calendar_epoch_unix_s if known else null,
		"calendar_now_utc": calendar_now_utc(),
		"t_s": t_s,
		# 动力学相位基准：沿用现有 CR3BP 相位时刻，绝不是日历/Unix 秒
		"phase_basis": PHASE_BASIS_CR3BP,
		"phase_epoch_s": epoch_s,
		"phase_abs_s": epoch_abs_s(),
		"calendar_vs_phase_note": "date = calendar_epoch + t_s；CR3BP 相位 = phase_epoch_s + t_s；两者互不替换",
		"raw_epoch_s_is_unix": false,
	}


func mode() -> String:
	return MODE_PAUSED if paused else MODE_RUNNING

## 事件时间（EventBus 使用）。
func event_time() -> Dictionary:
	return {
		"schema": SCHEMA,
		"t_s": t_s,
		"t_days": now_days(),
		"epoch_s": epoch_s,
		"epoch_abs_s": epoch_abs_s(),
		# A-02：日历历元/相位基准随快照持久化（唯一来源）
		"epoch": epoch_meta(),
		"scale": scale,
		"paused": paused,
		"mode": mode(),
	}

func check_invariants() -> Dictionary:
	var violations: Array = _invariants()
	return {"ok": violations.is_empty(), "violations": violations, "schema": SCHEMA}

func _check_post() -> void:
	var violations: Array = _invariants()
	contract_errors.append_array(violations)
	if not violations.is_empty():
		errors.append_array(violations)
		warnings.append("TimeService 后置不变量失败：" + str(violations))

func _invariants() -> Array[String]:
	var e: Array[String] = []
	if not is_finite(t_s) or t_s < 0.0:
		e.append("postcondition: t_s 必须有限且 >=0")
	if not is_finite(docked_s) or docked_s < 0.0:
		e.append("postcondition: docked_s 必须有限且 >=0")
	if docked_s > t_s + 1.0e-9:
		e.append("postcondition: docked_s 不能大于 t_s")
	if not is_finite(epoch_s):
		e.append("postcondition: epoch_s 必须有限")
	if not is_finite(scale) or scale < 0.0:
		e.append("postcondition: scale 必须有限且 >=0")
	if window_active:
		if not is_finite(window_left_s) or window_left_s < 0.0:
			e.append("postcondition: window_left_s 非法")
		if window_left_s > window_duration_s + 1.0e-9:
			e.append("postcondition: window_left_s 不能大于 duration")
	return e

func _contract(msg: String) -> void:
	contract_errors.append(msg)
	errors.append(msg)
	push_error("TimeService: " + msg)

func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"ready": ready,
		"t_s": t_s,
		"t_days": now_days(),
		"epoch_s": epoch_s,
		"epoch_abs_s": epoch_abs_s(),
		# A-02：日历历元/相位基准随快照持久化（唯一来源）
		"epoch": epoch_meta(),
		"scale": scale,
		"paused": paused,
		"mode": mode(),
		"docked": docked,
		"docked_s": docked_s,
		"window": {
			"active": window_active,
			"duration_s": window_duration_s,
			"left_s": window_left_s,
			"expired": window_expired,
		},
		"tick_count": tick_count,
		"last_dt_s": last_dt_s,
		"max_dt_s": max_dt_s,
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate(),
		"invariants": check_invariants(),
	}

func to_dict() -> Dictionary:
	return snapshot()

func reset() -> void:
	setup({})
