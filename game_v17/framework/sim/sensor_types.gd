class_name V2SensorTypes
extends RefCounted

## GHOST TRACK / APSIS · V2 传感器类型与能力记录（V2-SENSOR-1）
##
## 纯数据层：能力枚举 + SensorRecord(RefCounted) + world_snapshot 几何工具。
## 不依赖 Node / 不依赖 UI / 不读写 core 状态；radar.gd / tws.gd / optical.gd 共用本文件。
##
## 口径来源：
##   docs/34（V2 分层：sim/ 承载既有物理数学 + TWS/雷达模型）
##   docs/11_传感器规则.md（参数表 / 判定流程；D2 版本）
##   05_技术手册.md §S-01…S-07（IR / 雷达 / 光学 / 激光测距 / ELINT / IFF / 融合）
##   game_v16/scripts/sensor_model.gd（v15 规则库：型号库 / 暴露权重 / 截获系数）
##
## world_snapshot 契约（radar/tws/optical 的 step 输入，由 core 后续适配填充）：
##   {
##     "t": float,                                  # 仿真时刻（可选；模型用自身 dt 计时）
##     "observer": {                                # 观测平台（本舰）
##        "id": String, "pos_km": Vector3|[x,y,z],  # 也接受 r / pos / position
##        "maneuver_g": float,                      # 当前机动加速度（光学凝视中断判定）
##        "enabled": bool                           # 该平台传感器总开关（可选）
##     },
##     "targets": [                                 # 目标列表（只读；模型不得写入）
##        {"id": String, "pos_km": Vector3|[x,y,z], "rcs_m2": float,
##         "temp_k": float, "area_m2": float, "emissions": Array,
##         "classification": Dictionary, "illum": float}
##     ],
##     "sun_illum": float,                          # 0–1 光照（05 §S-03；1=日照明亮）
##     "jamming": float,                            # 0–1 噪声干扰（05 §E-01）
##     "los": bool,                                 # 可选：直接指定通视
##     "occluders": [{"center_km": Vector3, "radius_km": float}],  # 可选：地球/月球遮挡
##     "rng": RandomNumberGenerator                 # 可选：确定性随机；缺省用 Pd≥0.5 判定
##   }
##
## 模型只读 snapshot（不写入 core 状态）；输出均为普通 Dictionary，供 core/UI 后续消费。

const SM := preload("res://scripts/sensor_model.gd")


# ═══════════════════════════════════════════════════════════════════
# 1. 传感器能力枚举（任务要求六类：搜索雷达 / TWS / 光学 / IR / IFF / ELINT）
# ═══════════════════════════════════════════════════════════════════

const KIND_SEARCH_RADAR := "search_radar"   # 球形搜索雷达（全向球体，不是扇形）
const KIND_TWS_RADAR := "tws_radar"         # 专用 TWS 火控雷达（本关型号库无整机，保留能力位）
const KIND_OPTICAL := "optical"             # 可见光 / 光学凝视（含 lidar 子型）
const KIND_IR := "ir"                       # 被动红外阵列（只给方位线）
const KIND_IFF := "iff"                     # 敌我识别询问机（不产生位置）
const KIND_ELINT := "elint"                 # 电子侦察接收机（出信号，不出接触）
const KIND_UNKNOWN := "unknown"

## 遍历顺序固定，保证 probe / UI 可复现。
const KINDS: Array = [
	KIND_SEARCH_RADAR, KIND_TWS_RADAR, KIND_OPTICAL,
	KIND_IR, KIND_IFF, KIND_ELINT,
]

const KIND_LABELS := {
	KIND_SEARCH_RADAR: "搜索雷达 · 球形全向",
	KIND_TWS_RADAR: "TWS 火控雷达",
	KIND_OPTICAL: "光学凝视",
	KIND_IR: "被动红外阵列",
	KIND_IFF: "敌我识别询问机",
	KIND_ELINT: "电子侦察接收机",
	KIND_UNKNOWN: "未知传感器",
}

## 能力 → 与 docs/34 实体 schema `capabilities` 对齐的字符串。
const CAPABILITY_BY_KIND := {
	KIND_SEARCH_RADAR: "sensor.radar.active",
	KIND_TWS_RADAR: "sensor.radar.tws",
	KIND_OPTICAL: "sensor.optical",
	KIND_IR: "sensor.ir",
	KIND_IFF: "sensor.iff.interrogator",
	KIND_ELINT: "sensor.elint.passive",
}

const CAP_SEARCH := "search"                 # 球形搜索（sphere，不是 sector）
const CAP_TWS := "tws"                       # 多目标边扫边跟（track-while-scan）
const CAP_TRACK := "track"                   # 单目标稳定跟踪
const CAP_STARE := "stare"                   # 凝视 / 驻留照射
const CAP_LIDAR := "sensor.optical.lidar"    # LR-4：optical 子型（04 §12）
const CAP_PASSIVE := "passive"               # 被动（不暴露）
const CAP_ACTIVE_EMIT := "emitter"           # 主动发射（开机即暴露）

const SPHERE := "sphere"                     # 雷达探测体：以平台为球心的球
const HEMISPHERE := "hemisphere"
const SECTOR := "sector"                     # 本框架**不使用**扇形；保留值仅用于拒绝旧数据

## 暴露类别（与 sensor_model.gd EXPOSURE_WEIGHT 的键一致）。
const EMIT_CLASSES: Array = ["radar", "iff", "lidar", "radio", "lasercom", "ir", "optical", "elint"]

const DEFAULT_TWS_CHANNELS := 6             # [本文定值] 一部 TWS 搜索雷达的并行跟踪通道数


# ═══════════════════════════════════════════════════════════════════
# 2. SensorRecord：传感器能力记录（RefCounted，可被 core/UI 只读引用）
# ═══════════════════════════════════════════════════════════════════

class SensorRecord extends RefCounted:
	## 一部传感器的能力记录。字段全部是纯数据，to_dict() 可直接进 JSON/UI。

	var id := ""                    # 记录 id（默认 = model）
	var model := ""                 # 型号（YW-R9 / MS-OT2 / CH-IR2 / MK-12 / ELINT …）
	var maker := ""                 # 厂商/来源（docs/06）
	var kind := "unknown"           # 六类能力之一（见 V2SensorTypes.KINDS）
	var v15_type := ""              # v15 规则库的 type：radar / optical / ir / iff / elint
	var subtype := ""               # lidar（LR-4）等
	var range_km := 0.0             # 标称探测半径（R_ref，Pd=0.5 距离；01 §5.3）
	var refresh_s := 1.0            # 刷新 / 扫描周期
	var exposed := false            # 开机是否发射
	var exposure_weight := 0.0      # 暴露权重 0–1（sensor_model.gd EXPOSURE_WEIGHT）
	var exposure_kind := "passive"  # elint / lwr / scatter / passive
	var lpi := false                # 低截获概率（KD-R6，06 §4.3）
	var spherical := false          # 探测体形状：球形全向
	var scan_volume := "sector"     # "sphere" = 球形搜索；不再使用 sector
	var track_capacity := 0         # TWS 并行通道数（0 = 无 TWS）
	var sigma_bearing_deg := 1.0    # 测向 σ [本文定值]
	var sigma_range_frac := 0.0     # 测距 σ（比例）
	var sigma_range_floor_km := 0.0 # 测距 σ（下限）
	var stare_s := 40.0             # 光学凝视基准（05 §2.1：40 s @ 8,000 km）
	var stare_ref_km := 8000.0
	var illum_min := 0.05           # 最低光照（05 §S-03）
	var reset_maneuver_g := 0.02    # 自舰机动超此值 → 光学凝视重来
	var capabilities: Array = []    # 能力字符串（docs/34 schema）
	var params: Dictionary = {}     # v15 型号库原始参数（as_v15_sensor 可复原）

	func has_capability(cap: String) -> bool:
		return capabilities.has(cap)

	func is_tws() -> bool:
		return track_capacity > 0

	func is_radar() -> bool:
		return kind == "search_radar" or kind == "tws_radar"

	func track_range_km() -> float:
		return float(params.get("track_range_km", range_km * 0.5))

	## 输出与 sensor_model.gd 的 detect_*() 兼容的 sensor 字典（适配旧规则库）。
	func as_v15_sensor() -> Dictionary:
		var s: Dictionary = params.duplicate(true)
		s["model"] = model if model != "" else id
		if v15_type != "":
			s["type"] = v15_type
		if subtype != "":
			s["subtype"] = subtype
		s["range_km"] = range_km
		s["refresh_s"] = refresh_s
		s["expose"] = exposed
		s["expose_kind"] = exposure_kind
		s["sigma_bearing_deg"] = sigma_bearing_deg
		return s

	func describe() -> String:
		return "%s · %s（%.0f km / %.1f s / TWS×%d%s）" % [
			model, kind, range_km, refresh_s, track_capacity,
			" · 暴露" if exposed else " · 被动",
		]

	func to_dict() -> Dictionary:
		return {
			"id": id, "model": model, "maker": maker, "kind": kind,
			"v15_type": v15_type, "subtype": subtype,
			"range_km": range_km, "refresh_s": refresh_s,
			"exposed": exposed, "exposure_weight": exposure_weight,
			"exposure_kind": exposure_kind, "lpi": lpi,
			"spherical": spherical, "scan_volume": scan_volume,
			"track_capacity": track_capacity,
			"sigma_bearing_deg": sigma_bearing_deg,
			"sigma_range_frac": sigma_range_frac,
			"sigma_range_floor_km": sigma_range_floor_km,
			"stare_s": stare_s, "stare_ref_km": stare_ref_km,
			"illum_min": illum_min, "reset_maneuver_g": reset_maneuver_g,
			"capabilities": capabilities.duplicate(),
			"params": params.duplicate(true),
		}


# ═══════════════════════════════════════════════════════════════════
# 3. 型号 → 能力记录（适配 v15 型号库）
# ═══════════════════════════════════════════════════════════════════

## 由型号名构造能力记录。overrides 可覆盖 kind / range_km / refresh_s /
## track_capacity / params 等（probe 与后续关卡配置用）。
static func record(model: String, overrides: Dictionary = {}):
	var base: Dictionary = {}
	if SM.SENSOR_LIBRARY.has(model):
		base = (SM.SENSOR_LIBRARY.get(model, {}) as Dictionary).duplicate(true)

	var r = SensorRecord.new()
	r.model = model
	r.id = String(overrides.get("id", model))
	r.v15_type = String(overrides.get("v15_type", base.get("type", "")))
	r.subtype = String(overrides.get("subtype", base.get("subtype", "")))
	var vk: String = _kind_for(r.v15_type, r.subtype)
	if overrides.has("kind"):
		vk = String(overrides["kind"])
	r.kind = vk
	r.maker = String(base.get("maker", "—"))
	r.range_km = float(overrides.get("range_km", base.get("range_km", 0.0)))
	r.refresh_s = maxf(0.05, float(overrides.get("refresh_s", base.get("refresh_s", 1.0))))
	r.exposed = bool(base.get("expose", false))
	var eclass: String = _emission_class(r.v15_type, r.subtype)
	r.exposure_weight = float(SM.EXPOSURE_WEIGHT.get(eclass, 0.0))
	r.exposure_kind = String(base.get("expose_kind", SM.EXPOSURE_KIND.get(eclass, "passive")))
	r.lpi = bool(base.get("lpi", false))
	r.spherical = vk == KIND_SEARCH_RADAR or vk == KIND_TWS_RADAR
	r.scan_volume = SPHERE if r.spherical else "line_of_sight"
	var cap_default := 0
	if vk == KIND_SEARCH_RADAR or vk == KIND_TWS_RADAR:
		cap_default = DEFAULT_TWS_CHANNELS
	r.track_capacity = int(overrides.get("track_capacity", cap_default))
	r.sigma_bearing_deg = float(base.get("sigma_bearing_deg", 1.0))
	r.sigma_range_frac = float(base.get("sigma_range_frac", 0.0))
	r.sigma_range_floor_km = float(base.get("sigma_range_floor_km", 0.0))
	r.stare_s = float(base.get("stare_s", 40.0))
	r.stare_ref_km = float(base.get("stare_ref_km", 8000.0))
	r.illum_min = float(base.get("illum_min", 0.05))
	r.reset_maneuver_g = float(base.get("reset_maneuver_g", 0.02))
	r.params = (overrides.get("params", base) as Dictionary).duplicate(true)
	r.capabilities = _capabilities_for(vk, r.subtype, r.track_capacity)
	if overrides.has("capabilities"):
		var caps: Array = []
		for c in (overrides["capabilities"] as Array):
			caps.append(String(c))
		r.capabilities = caps
	if overrides.has("exposed"):
		r.exposed = bool(overrides["exposed"])
	if overrides.has("lpi"):
		r.lpi = bool(overrides["lpi"])
	return r


## 从 to_dict() 复原记录（JSON 往返 / core 存档用）。
static func record_from_dict(d: Dictionary):
	var model := String(d.get("model", ""))
	var overrides: Dictionary = {
		"id": String(d.get("id", model)),
		"v15_type": String(d.get("v15_type", "")),
		"subtype": String(d.get("subtype", "")),
		"kind": String(d.get("kind", KIND_UNKNOWN)),
		"range_km": float(d.get("range_km", 0.0)),
		"refresh_s": float(d.get("refresh_s", 1.0)),
		"track_capacity": int(d.get("track_capacity", 0)),
		"capabilities": (d.get("capabilities", []) as Array),
		"params": (d.get("params", {}) as Dictionary),
	}
	var r = record(model, overrides)
	r.maker = String(d.get("maker", r.maker))
	r.exposed = bool(d.get("exposed", r.exposed))
	r.exposure_weight = float(d.get("exposure_weight", r.exposure_weight))
	r.exposure_kind = String(d.get("exposure_kind", r.exposure_kind))
	r.lpi = bool(d.get("lpi", r.lpi))
	r.spherical = bool(d.get("spherical", r.spherical))
	r.scan_volume = String(d.get("scan_volume", r.scan_volume))
	r.sigma_bearing_deg = float(d.get("sigma_bearing_deg", r.sigma_bearing_deg))
	r.sigma_range_frac = float(d.get("sigma_range_frac", r.sigma_range_frac))
	r.sigma_range_floor_km = float(d.get("sigma_range_floor_km", r.sigma_range_floor_km))
	r.stare_s = float(d.get("stare_s", r.stare_s))
	r.stare_ref_km = float(d.get("stare_ref_km", r.stare_ref_km))
	r.illum_min = float(d.get("illum_min", r.illum_min))
	r.reset_maneuver_g = float(d.get("reset_maneuver_g", r.reset_maneuver_g))
	return r


## 由 v15 传感器架（sensor_model.sensor_rack() 的一条）构造能力记录。
static func record_from_rack_sensor(sensor: Dictionary):
	var model := String(sensor.get("model", ""))
	var r = record(model)
	r.v15_type = String(sensor.get("type", r.v15_type))
	r.subtype = String(sensor.get("subtype", r.subtype))
	r.kind = _kind_for(r.v15_type, r.subtype)
	r.range_km = float(sensor.get("range_km", r.range_km))
	r.refresh_s = maxf(0.05, float(sensor.get("refresh_s", r.refresh_s)))
	r.exposed = bool(sensor.get("expose", r.exposed))
	r.exposure_kind = String(sensor.get("expose_kind", r.exposure_kind))
	r.lpi = bool(sensor.get("lpi", r.lpi))
	r.spherical = r.kind == KIND_SEARCH_RADAR or r.kind == KIND_TWS_RADAR
	r.track_capacity = DEFAULT_TWS_CHANNELS if r.spherical else 0
	r.sigma_bearing_deg = float(sensor.get("sigma_bearing_deg", r.sigma_bearing_deg))
	r.sigma_range_frac = float(sensor.get("sigma_range_frac", r.sigma_range_frac))
	r.sigma_range_floor_km = float(sensor.get("sigma_range_floor_km", r.sigma_range_floor_km))
	r.stare_s = float(sensor.get("stare_s", r.stare_s))
	r.stare_ref_km = float(sensor.get("stare_ref_km", r.stare_ref_km))
	r.illum_min = float(sensor.get("illum_min", r.illum_min))
	r.reset_maneuver_g = float(sensor.get("reset_maneuver_g", r.reset_maneuver_g))
	r.params = sensor.duplicate(true)
	r.capabilities = _capabilities_for(r.kind, r.subtype, r.track_capacity)
	return r


static func _kind_for(v15_type: String, subtype: String) -> String:
	match v15_type:
		"radar":
			return KIND_SEARCH_RADAR
		"optical":
			return KIND_OPTICAL
		"ir":
			return KIND_IR
		"iff":
			return KIND_IFF
		"elint":
			return KIND_ELINT
		_:
			return KIND_UNKNOWN


static func _emission_class(v15_type: String, subtype: String) -> String:
	if v15_type == "optical" and subtype == "lidar":
		return "lidar"
	return v15_type


static func _capabilities_for(kind: String, subtype: String, track_capacity: int) -> Array:
	var caps: Array = []
	var base_cap := String(CAPABILITY_BY_KIND.get(kind, ""))
	if base_cap != "":
		caps.append(base_cap)
	match kind:
		KIND_SEARCH_RADAR, KIND_TWS_RADAR:
			caps.append(CAP_SEARCH)
			caps.append(CAP_TRACK)
			caps.append(CAP_STARE)
			if track_capacity > 0:
				caps.append(CAP_TWS)
			caps.append(CAP_ACTIVE_EMIT)
		KIND_OPTICAL:
			if subtype == "lidar":
				caps.append(CAP_LIDAR)
				caps.append(CAP_ACTIVE_EMIT)
			else:
				caps.append(CAP_PASSIVE)
				caps.append(CAP_STARE)
		KIND_IR, KIND_ELINT:
			caps.append(CAP_PASSIVE)
		KIND_IFF:
			caps.append(CAP_ACTIVE_EMIT)
	return caps


## 记录合法性校验；返回错误字符串数组（空 = 通过）。
static func validate_record(rec) -> Array:
	var errors: Array = []
	if rec == null:
		errors.append("record == null")
		return errors
	if not KINDS.has(rec.kind):
		errors.append("%s: kind=%s 不在 %s" % [rec.id, rec.kind, str(KINDS)])
	if rec.range_km <= 0.0:
		errors.append("%s: range_km 必须 > 0" % rec.id)
	if rec.refresh_s <= 0.0:
		errors.append("%s: refresh_s 必须 > 0" % rec.id)
	if rec.track_capacity < 0:
		errors.append("%s: track_capacity 不能为负" % rec.id)
	if not (rec.exposure_kind in ["elint", "lwr", "scatter", "passive"]):
		errors.append("%s: exposure_kind=%s 非法" % [rec.id, rec.exposure_kind])
	if rec.spherical and rec.scan_volume != SPHERE:
		errors.append("%s: 球形雷达 scan_volume 必须是 sphere（不画扇形）" % rec.id)
	if not rec.spherical and rec.scan_volume == SECTOR:
		errors.append("%s: V2 不使用扇形扫描体" % rec.id)
	if rec.exposed and rec.exposure_weight <= 0.0:
		errors.append("%s: exposed=true 但 exposure_weight=0" % rec.id)
	return errors


# ═══════════════════════════════════════════════════════════════════
# 4. world_snapshot 几何工具（radar / tws / optical 共用；纯静态函数）
# ═══════════════════════════════════════════════════════════════════

## 把 Vector3 / [x,y,z] / {"pos_km"|"r"|"pos"|"position": …} 统一成 Vector3（km）。
static func to_vec3(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		return fallback
	if value is Dictionary:
		var d: Dictionary = value
		for key in ["pos_km", "r", "pos", "position", "center_km"]:
			if d.has(key):
				return to_vec3(d[key], fallback)
	return fallback


## 观测平台（本舰）位置，km（L1 站心 / 快照坐标系）。
static func observer_pos_km(snapshot: Dictionary) -> Vector3:
	var obs: Variant = snapshot.get("observer", null)
	if obs is Dictionary:
		var d: Dictionary = obs
		if d.has("pos_km") or d.has("r") or d.has("pos") or d.has("position"):
			return to_vec3(d)
		return to_vec3(d.get("orbit", Vector3.ZERO))
	if obs is Vector3 or obs is Array:
		return to_vec3(obs)
	for key in ["observer_pos_km", "own_pos_km", "center_km"]:
		if snapshot.has(key):
			return to_vec3(snapshot[key])
	return Vector3.ZERO


## 目标位置，km。
static func target_pos_km(target: Dictionary) -> Vector3:
	if target.has("pos_km") or target.has("r") or target.has("pos") or target.has("position"):
		return to_vec3(target)
	return to_vec3(target.get("orbit", Vector3.ZERO))


## 目标列表（也接受 "contacts" 别名）。
static func targets_of(snapshot: Dictionary) -> Array:
	var arr: Variant = snapshot.get("targets", snapshot.get("contacts", []))
	if arr is Array:
		return arr
	return []


static func target_by_id(snapshot: Dictionary, target_id: String) -> Dictionary:
	for raw in targets_of(snapshot):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == target_id:
			return raw
	return {}


## 快照时刻（缺失时用 fallback）。
static func snapshot_time(snapshot: Dictionary, fallback: float = 0.0) -> float:
	return float(snapshot.get("t", fallback))


## 相对几何：距离 km / 方位 °（0=北，90=东）/ 俯仰 °（站心 +z 天顶，02 §8.1）。
static func geometry_km(observer_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var rel := target_pos - observer_pos
	var range_km := rel.length()
	var horiz := Vector2(rel.x, rel.y).length()
	var bearing := 0.0
	if horiz > 1.0e-9:
		bearing = fposmod(rad_to_deg(atan2(rel.x, rel.y)), 360.0)
	var elevation := 0.0
	if range_km > 1.0e-9:
		elevation = rad_to_deg(atan2(rel.z, horiz))
	return {
		"range_km": range_km,
		"bearing_deg": bearing,
		"elevation_deg": elevation,
		"rel_km": rel,
	}


## 通视判定：snapshot["los"] 优先；否则按 occluders（地球/月球球体）逐段判定。
## L1 局部几何通常无遮挡 → 缺省 true（调用方负责几何前提）。
static func los_ok(snapshot: Dictionary, observer_pos: Vector3, target_pos: Vector3) -> bool:
	if snapshot.has("los"):
		return bool(snapshot["los"])
	var occluders: Variant = snapshot.get("occluders", [])
	if occluders is Array:
		for raw in (occluders as Array):
			if not (raw is Dictionary):
				continue
			var oc: Dictionary = raw
			var center := to_vec3(oc.get("center_km", Vector3.ZERO))
			var radius := float(oc.get("radius_km", 6378.137))
			if not SM.line_of_sight_ok(observer_pos, target_pos, center, radius):
				return false
	return true


## 光照（05 §S-03）：目标级 illum 覆盖 > 快照全局 sun_illum。
static func illum_of(snapshot: Dictionary, target: Dictionary) -> float:
	var v := float(target.get("illum", snapshot.get("sun_illum", 1.0)))
	return clampf(v, 0.0, 1.0)


## 噪声干扰 0–1（05 §E-01）。
static func jamming_of(snapshot: Dictionary) -> float:
	return clampf(float(snapshot.get("jamming", 0.0)), 0.0, 1.0)


## 观测平台当前机动加速度（g）——光学凝视中断判定（05 §S-03 缺陷）。
static func maneuver_of(snapshot: Dictionary) -> float:
	var obs: Variant = snapshot.get("observer", null)
	if obs is Dictionary:
		return maxf(0.0, float((obs as Dictionary).get("maneuver_g", 0.0)))
	if snapshot.has("maneuver_g"):
		return maxf(0.0, float(snapshot["maneuver_g"]))
	return 0.0


## 确定性随机源（可选）。无 rng 时 sensor_model.roll() 退化为 Pd≥0.5。
static func rng_of(snapshot: Dictionary) -> Variant:
	if snapshot.has("rng"):
		return snapshot["rng"]
	return null


## 组装 sensor_model.detect_*() 需要的 ctx（los / 光照 / 干扰 / 随机）。
static func ctx_of(snapshot: Dictionary, target: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {
		"los": los_ok(snapshot, observer_pos_km(snapshot), target_pos_km(target)),
		"sun_illum": illum_of(snapshot, target),
		"shadow": bool(snapshot.get("shadow", false)),
		"jamming": jamming_of(snapshot),
	}
	var rng: Variant = rng_of(snapshot)
	if rng != null:
		ctx["rng"] = rng
	return ctx
