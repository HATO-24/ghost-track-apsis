class_name V2RadarModel
extends RefCounted

## GHOST TRACK / APSIS · V2 搜索雷达模型（V2-SENSOR-1）
##
## 只做「球形搜索 + 距离衰减 + 刷新率 + 暴露风险 + 检测概率」，不画扇形、不做 UI。
## 探测体是**以平台为球心的球**（sphere），全向、无方位/俯仰视场限制；
## 与旧版「扇形扫描」的区别：任何方向只要距离落在球内就参与检测。
##
## 数学沿用 v15 规则库（game_v16/scripts/sensor_model.gd）：
##   R_eff = range_km × (RCS/10 m²)^0.25 × 干扰因子              ← 05 §S-02
##   Pd    = logistic(-40·log10(R/R_eff))                        ← 01 §5.3（双程 R⁴）
##   稳定跟踪 = R ≤ track_range_eff 且 Pd ≥ 0.5                  ← 05 §S-02（15,000 km 档）
##   暴露   = 开机即被 ELINT 截获；截获距离 = range_km × 系数；20 s 后可定位 ← 05 §S-02
##
## 公开 API：
##   V2RadarModel.new(record, opts)                     # record = sensor_types.record(...)
##   radar.step(dt, world_snapshot) -> Dictionary       # 扫描节奏 / 观测 / 暴露
##   radar.scan_now(world_snapshot) -> Dictionary
##   radar.set_enabled(false)                           # EMCON
##   V2RadarModel.exposure_state(record, seconds_on) -> Dictionary     # 静态，暴露风险
##   V2RadarModel.effective_radius_km(record, rcs, jamming) -> float   # 静态，球半径
##
## 不修改 core 状态：只读 snapshot，输出新 Dictionary。

const SM := preload("res://scripts/sensor_model.gd")
const Types := preload("res://framework/sim/sensor_types.gd")

const JAMMED_RANGE_FACTOR := 0.30   # 05 §E-01：干扰可把探测距离压到 30%
const LPI_INTERCEPT_MULT := 0.5     # 06 KD-R6：低截获概率
const LPI_FIX_MULT := 2.0           # 同上：被定位所需时长翻倍
const DETECT_EXPONENT := 4.0        # 雷达双程：SNR ∝ 1/R⁴（01 §5.3）
const OUT_OF_SPHERE := "out_of_sphere"

var record                      # Types.SensorRecord
var radar_id := ""
var enabled := true
var elapsed_s := 0.0            # 雷达自身时钟（由 step 的 dt 推进）
var seconds_on := 0.0           # 累计开机时长（暴露 / 定位进度）
var scan_period_s := 6.0        # 扫描周期（= record.refresh_s）
var time_since_scan := 0.0
var scan_index := 0
var last_scan_t := -1.0
var last_scan: Dictionary = {}
var target_memory: Dictionary = {}   # id -> {last_hit_t, last_scan_index, detected, ...}


func _init(rec = null, opts: Dictionary = {}) -> void:
	record = rec
	radar_id = String(opts.get("id", rec.id if rec != null else "radar"))
	enabled = bool(opts.get("enabled", true))
	if rec != null:
		scan_period_s = maxf(0.25, float(rec.refresh_s))
	seconds_on = 0.0


func set_enabled(on: bool) -> void:
	enabled = on


func set_record(rec) -> void:
	record = rec
	if rec != null:
		scan_period_s = maxf(0.25, float(rec.refresh_s))


func is_enabled() -> bool:
	return enabled


# ═══════════════════════════════════════════════════════════════════
# 1. 球形搜索半径（真实几何 + 衰减）
# ═══════════════════════════════════════════════════════════════════

## 标称球半径（Pd=0.5 距离，RCS=基准 10 m²、无干扰）。
static func nominal_radius_km(rec) -> float:
	if rec == null:
		return 0.0
	return float(rec.range_km)


## RCS 因子：(RCS/10 m²)^0.25（05 §S-02 以 10 m² 为基准）。
static func rcs_factor(rec, target_rcs_m2: float) -> float:
	var ref_rcs := 10.0
	if rec != null:
		ref_rcs = float((rec.params as Dictionary).get("ref_rcs_m2", 10.0))
	return pow(maxf(0.01, target_rcs_m2) / maxf(0.01, ref_rcs), 0.25)


## 干扰因子：1 − jamming·(1−0.30)·(1−抗干扰)（05 §E-01）。
static func jam_factor(rec, jamming: float) -> float:
	var jam := clampf(jamming, 0.0, 1.0)
	var resist := 0.0
	if rec != null:
		resist = clampf(float((rec.params as Dictionary).get("jamming_resist", 0.0)), 0.0, 1.0)
	return 1.0 - jam * (1.0 - JAMMED_RANGE_FACTOR) * (1.0 - resist)


## 有效球半径：标称 × RCS 因子 × 干扰因子（km）。
static func effective_radius_km(rec, target_rcs_m2: float, jamming: float = 0.0) -> float:
	return nominal_radius_km(rec) * rcs_factor(rec, target_rcs_m2) * jam_factor(rec, jamming)


## 有效稳定跟踪半径（km）。
static func effective_track_radius_km(rec, target_rcs_m2: float, jamming: float = 0.0) -> float:
	var base := 0.0
	if rec != null:
		base = rec.track_range_km()
	return base * rcs_factor(rec, target_rcs_m2) * jam_factor(rec, jamming)


## 是否落在球形搜索范围内（不是扇区、不是锥体）。
static func in_sphere(range_km: float, radius_km: float) -> bool:
	return range_km >= 0.0 and range_km <= radius_km + 1.0e-6


## 球形搜索体的展示/查询数据（供 core/UI 后续读取；本文件不绘制）。
static func sphere_for(rec, center_km: Vector3, target_rcs_m2: float = 10.0,
		jamming: float = 0.0) -> Dictionary:
	return {
		"shape": "sphere",
		"center_km": center_km,
		"nominal_radius_km": nominal_radius_km(rec),
		"effective_radius_km": effective_radius_km(rec, target_rcs_m2, jamming),
		"track_radius_km": effective_track_radius_km(rec, target_rcs_m2, jamming),
		"refresh_s": float(rec.refresh_s) if rec != null else 0.0,
		"tws_capacity": int(rec.track_capacity) if rec != null else 0,
		"no_sector": true,
	}


# ═══════════════════════════════════════════════════════════════════
# 2. 暴露风险（05 §S-02：开机即暴露；05 §附录 A）
# ═══════════════════════════════════════════════════════════════════

## 暴露态：ELINT 截获距离、被定位所需时长、当前定位进度、测向 σ。
## 口径同 sensor_model.emission_for()/expose_fix()，按能力记录重算。
static func exposure_state(rec, seconds_on: float, ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"exposed": false,
		"emission_level": 0.0,
		"emission_class": "",
		"exposure_kind": "passive",
		"elint_intercept_range_km": 0.0,
		"fix_after_s": 0.0,
		"fix_progress": 0.0,
		"fixed": false,
		"bearing_sigma_deg": 1.0,
		"seconds_on": maxf(0.0, seconds_on),
		"warning": "",
	}
	var emitting := true
	if ctx.has("on"):
		emitting = bool(ctx["on"])
	if rec == null or not rec.exposed or not emitting:
		return out
	var eclass: String = rec.v15_type
	if eclass == "optical" and rec.subtype == "lidar":
		eclass = "lidar"
	var weight := float(SM.EXPOSURE_WEIGHT.get(eclass, rec.exposure_weight))
	var factor := float(SM.ELINT_INTERCEPT_FACTOR.get(eclass, 0.0))
	var fix_after := float(SM.ELINT_FIX_TIME_S.get(eclass, 30.0))
	if rec.lpi:
		factor *= LPI_INTERCEPT_MULT
		fix_after *= LPI_FIX_MULT
	var intercept_km := float(rec.range_km) * factor
	var so := maxf(0.0, seconds_on)
	var progress := clampf(so / maxf(1.0e-6, fix_after), 0.0, 1.0)
	out["exposed"] = weight > 0.0 or rec.exposed
	out["emission_level"] = weight
	out["emission_class"] = eclass
	out["exposure_kind"] = rec.exposure_kind
	out["elint_intercept_range_km"] = intercept_km
	out["fix_after_s"] = fix_after
	out["fix_progress"] = progress
	out["fixed"] = progress >= 1.0
	out["bearing_sigma_deg"] = lerp(1.0, 0.2, progress)
	out["lpi"] = rec.lpi
	if rec.exposure_kind == "lwr":
		out["warning"] = "激光告警：只有被照射目标收到 LWR（05 §S-04）"
	elif rec.exposure_kind == "scatter":
		out["warning"] = "侧向散射：极低概率被截听（05 §C-01）"
	else:
		out["warning"] = "开机即暴露：ELINT 可截获 %.0f km，%.0f s 后可定位（05 §S-02）" % [
			intercept_km, fix_after]
	return out


# ═══════════════════════════════════════════════════════════════════
# 3. 单目标检测（球形范围内 → v15 规则库判定）
# ═══════════════════════════════════════════════════════════════════

## 检测一个目标。返回单个 observation 字典（含球形/衰减/暴露附注）。
func observe_target(target: Dictionary, snapshot: Dictionary, t: float = -1.0) -> Dictionary:
	var at := t
	if at < 0.0:
		at = Types.snapshot_time(snapshot, elapsed_s)
	var tid := String(target.get("id", ""))
	var obs_pos := Types.observer_pos_km(snapshot)
	var tgt_pos := Types.target_pos_km(target)
	var geom := Types.geometry_km(obs_pos, tgt_pos)
	var rcs := float(target.get("rcs_m2", 10.0))
	if target.get("rcs_m2", null) == null and record != null:
		rcs = float((record.params as Dictionary).get("ref_rcs_m2", 10.0))
	var jam := Types.jamming_of(snapshot)
	var eff_radius := effective_radius_km(record, rcs, jam)
	var track_radius := effective_track_radius_km(record, rcs, jam)
	var inside := in_sphere(float(geom["range_km"]), eff_radius) if record != null else false
	var los := Types.los_ok(snapshot, obs_pos, tgt_pos)

	# 组装 v15 detect_radar 的 target / ctx（只读快照字段的副本，不写回 snapshot）。
	var v15_target: Dictionary = target.duplicate(true)
	v15_target["range_km"] = geom["range_km"]
	v15_target["bearing_deg"] = geom["bearing_deg"]
	v15_target["rcs_m2"] = rcs
	var ctx: Dictionary = {
		"los": los,
		"jamming": jam,
		"rng": Types.rng_of(snapshot),
	}
	var sensor_dict: Dictionary = record.as_v15_sensor() if record != null else {}
	var det: Dictionary = SM.detect_radar(sensor_dict, v15_target, ctx)

	var obs: Dictionary = det.duplicate(true)
	obs["target_id"] = tid
	obs["sensor_id"] = radar_id
	obs["kind"] = "radar"
	obs["t"] = at
	obs["scan_index"] = scan_index
	obs["range_3d_km"] = geom["range_km"]
	obs["bearing_deg"] = geom["bearing_deg"]
	obs["elevation_deg"] = geom["elevation_deg"]
	obs["in_sphere"] = inside
	obs["effective_radius_km"] = eff_radius
	obs["track_radius_km"] = track_radius
	obs["sphere_shape"] = "sphere"
	obs["refresh_s"] = scan_period_s
	obs["jamming"] = jam
	obs["exposure"] = exposure_state(record, seconds_on)
	if not inside:
		obs["detected"] = false
		obs["reason"] = "%s: 球形搜索范围外（R=%.0f km > 球半径 %.0f km）" % [
			OUT_OF_SPHERE, float(geom["range_km"]), eff_radius]
	elif not los:
		obs["detected"] = false
		obs["reason"] = "occluded: 地球/月球遮挡（05 §S-02 对抗）"
	return obs


## 立即扫描一次（不受刷新周期约束；probe / core 首次开机用）。
func scan_now(snapshot: Dictionary) -> Dictionary:
	var t := Types.snapshot_time(snapshot, elapsed_s)
	scan_index += 1
	last_scan_t = t
	last_scan = _do_scan(snapshot, t)
	return last_scan.duplicate(true)


func _do_scan(snapshot: Dictionary, t: float) -> Dictionary:
	var observations: Array = []
	var per_target: Dictionary = {}
	for raw in Types.targets_of(snapshot):
		if not (raw is Dictionary):
			continue
		var target: Dictionary = raw
		var obs := observe_target(target, snapshot, t)
		var tid := String(obs.get("target_id", ""))
		observations.append(obs)
		per_target[tid] = {
			"target_id": tid,
			"detected": bool(obs.get("detected", false)),
			"pd": float(obs.get("pd", 0.0)),
			"in_sphere": bool(obs.get("in_sphere", false)),
			"range_km": float(obs.get("range_3d_km", -1.0)),
			"t": t,
			"scan_index": scan_index,
		}
		var mem: Dictionary = target_memory.get(tid, {})
		mem["last_scan_t"] = t
		mem["last_scan_index"] = scan_index
		mem["detected"] = bool(obs.get("detected", false))
		mem["pd"] = float(obs.get("pd", 0.0))
		mem["in_sphere"] = bool(obs.get("in_sphere", false))
		mem["range_km"] = float(obs.get("range_3d_km", -1.0))
		if bool(obs.get("detected", false)):
			mem["last_hit_t"] = t
		target_memory[tid] = mem
	return {
		"t": t,
		"scan_index": scan_index,
		"observer_pos_km": Types.observer_pos_km(snapshot),
		"observations": observations,
		"targets": per_target,
	}


# ═══════════════════════════════════════════════════════════════════
# 4. step(dt, world_snapshot)：扫描节奏 + 暴露累计
# ═══════════════════════════════════════════════════════════════════

## 推进 dt 秒。只有扫描周期到点才产生 observations；暴露/开机时长每步累计。
## 首次保持开机的 step 立即扫描一次（scan_index==0），保证开机即可见。
func step(dt: float, snapshot: Dictionary) -> Dictionary:
	var step_dt := maxf(0.0, dt)
	elapsed_s += step_dt
	if enabled:
		seconds_on += step_dt
	var scanned := false
	var observations: Array = []
	if enabled:
		time_since_scan += step_dt
		var due := scan_index == 0 or time_since_scan + 1.0e-9 >= scan_period_s
		if due:
			scanned = true
			if scan_index == 0:
				time_since_scan = 0.0
			else:
				time_since_scan = fposmod(time_since_scan, scan_period_s)
			scan_index += 1
			var t := Types.snapshot_time(snapshot, elapsed_s)
			last_scan_t = t
			last_scan = _do_scan(snapshot, t)
			observations = last_scan.get("observations", [])
	var obs_pos := Types.observer_pos_km(snapshot)
	var jam := Types.jamming_of(snapshot)
	return {
		"t": elapsed_s,
		"dt": step_dt,
		"enabled": enabled,
		"scanned": scanned,
		"scan_index": scan_index,
		"scan_period_s": scan_period_s,
		"seconds_on": seconds_on,
		"scan_progress": clampf(time_since_scan / maxf(1.0e-6, scan_period_s), 0.0, 1.0),
		"sphere": {
			"shape": "sphere",
			"center_km": obs_pos,
			"nominal_radius_km": nominal_radius_km(record),
			"refresh_s": scan_period_s,
		},
		"observations": observations,
		"exposure": exposure_state(record, seconds_on, {"on": enabled}),
		"jamming": jam,
		"tws_capacity": int(record.track_capacity) if record != null else 0,
	}


func to_dict() -> Dictionary:
	return {
		"radar_id": radar_id,
		"enabled": enabled,
		"elapsed_s": elapsed_s,
		"seconds_on": seconds_on,
		"scan_period_s": scan_period_s,
		"scan_index": scan_index,
		"last_scan_t": last_scan_t,
		"sphere": {
			"shape": "sphere",
			"nominal_radius_km": nominal_radius_km(record),
		},
		"exposure": exposure_state(record, seconds_on, {"on": enabled}),
		"target_memory": target_memory.duplicate(true),
	}
