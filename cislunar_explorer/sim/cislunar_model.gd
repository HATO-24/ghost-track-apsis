class_name CislunarModel
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# CISLUNAR EXPLORER · 地月系轨道 / 站点模型（技术 demo，V1）
#
# 一个明确、可验证（而不是“看起来像”）的地月圆轨道模型：
#   - 惯性系：地球中心惯性帧（ECI-demo）；XY 平面 = 月球轨道面，+Z = 轨道法向，
#     t=0 时月球在 +X 方向。地球固定在原点（忽略地月质心偏移；见 docs/model.md）。
#   - 月球：圆轨道，半径 384,400 km，恒星周期 27.321661 d；相对运动用
#     μ_total = μ_E + μ_M 的二体关系（n²R³ = μ_total）。
#   - L1–L5：CR3BP 旋转系位置；L1/L2/L3 用二分法解共线平衡方程（不是写死数值），
#     L4/L5 为 ±60°。同时给出旋转系/惯性系位置与速度（按共转近似）。
#   - 站点：L1/L2/L4/L5 站、GEO 环、月球同步环、月球低轨/极轨站、地球港、月球港。
#     每站 id/name/kind/parent/orbit{radius_km,period_s,inclination_deg}/position/velocity/
#     distances{earth_center_km,moon_center_km}，全部 km、km/s、rad。
#   - sample(t)：地球/月球/L 点/站点/环/距离/epoch 的 JSON 可序列化快照。
#
# 单位：距离 km；时间 s；速度 km/s；角度 rad（对外字段另附 _deg 便于显示）。
# 边界：圆轨道 + CR3BP 驻点近似 + 共转速度，不是 JPL 星历；月球同步环半径在月球
#       Hill 球之外（按任务公式计算，仅作演示数据），详见 docs/model.md。
# ═══════════════════════════════════════════════════════════════════

# —— 物理常数（km³/s²、km、s；来源见 docs/model.md）——
const MU_EARTH := 398600.4418          # 地球引力常数
const MU_MOON := 4902.800118           # 月球引力常数
const MU_TOTAL := MU_EARTH + MU_MOON
const EARTH_RADIUS_KM := 6378.137
const MOON_RADIUS_KM := 1737.4
const EARTH_MOON_DIST_KM := 384400.0
const MOON_PERIOD_S := 27.321661 * 86400.0        # 2360591.51 s（月球恒星月）
const EARTH_SIDEREAL_DAY_S := 86164.0905
const GEO_RADIUS_KM := 42164.0
const G_SI := 6.67430e-11
const MOON_MASS_KG := 7.342e22
const LUNAR_LEO_ALTITUDE_KM := 100.0
const EPOCH_ISO := "2026-01-01T00:00:00Z"
const MODEL_ID := "cislunar_circular_cr3bp_v1"

# —— 地月质量比 μ = m_Moon/(m_Earth+m_Moon) ≈ 0.012150585 ——
const MU := 0.012150585

# 演示用初始相位（rad）：让各站点在 t=0 不完全重合，便于绘图/检查。
const LEO_PHASE0 := 0.35
const POLAR_PHASE0 := 1.10
const LUNAR_SYNC_PHASE0 := 0.0
const GEO_PHASE0 := 0.0

const STATION_IDS := ["l1_station", "l2_station", "l4_station", "l5_station",
	"geo_ring", "lunar_sync_ring", "lunar_leo", "lunar_polar", "earth_port", "lunar_port"]

var t := 0.0

func _init(t0 := 0.0) -> void:
	t = float(t0)

# ═══════════════════════════════════════════════════════════════════
# 基础工具
# ═══════════════════════════════════════════════════════════════════

## 月球轨道角速度（rad/s），来自 n = 2π/T。
static func moon_mean_motion() -> float:
	return TAU / MOON_PERIOD_S

## 由半径与引力常数算圆轨道周期（Kepler 第三定律）。
static func period_s(radius_km: float, mu_km3_s2 := MU_EARTH) -> float:
	if radius_km <= 0.0 or mu_km3_s2 <= 0.0:
		return 0.0
	return TAU * sqrt(radius_km * radius_km * radius_km / mu_km3_s2)

## 圆轨道速度（km/s）。
static func circular_speed_kmps(radius_km: float, mu_km3_s2 := MU_EARTH) -> float:
	if radius_km <= 0.0:
		return 0.0
	return sqrt(mu_km3_s2 / radius_km)

## GEO 环周期（由 Kepler 从 42,164 km 推，≈ 地球恒星日）。
static func geo_period_s() -> float:
	return period_s(GEO_RADIUS_KM, MU_EARTH)

## 月球同步环半径：按任务公式 r = (G·M_moon·T² / 4π²)^(1/3)，T = 月球恒星日（= 恒星月）。
static func lunar_sync_radius_km() -> float:
	var radius := MOON_MU() * MOON_PERIOD_S * MOON_PERIOD_S / (4.0 * PI * PI)
	return pow(radius, 1.0 / 3.0)

## 月球同步环周期（= 月球恒星日/恒星月）。
static func lunar_sync_period_s() -> float:
	return MOON_PERIOD_S

## 月球 Hill 球半径（≈ R·(μ/3)^(1/3)），用于说明同步环超出稳定范围。
static func hill_radius_km() -> float:
	return EARTH_MOON_DIST_KM * pow(MU / 3.0, 1.0 / 3.0)

## 由 R 与 T 隐含的“圆轨道引力常数” μ_implied = n²R³。
## 任务给定 R=384,400 km、T=27.321661 d 与真实 μ_total 并非严格自洽（差约 0.27%，
## 因真实月球平均距离≈384,748 km），模型以给定 R/T 为准并在文档标注。
static func implied_mu_km3_s2() -> float:
	var n := moon_mean_motion()
	return n * n * pow(EARTH_MOON_DIST_KM, 3.0)

## |μ_implied - μ_total| / μ_total（模型自洽误差）。
static func mu_consistency_rel_err() -> float:
	return absf(implied_mu_km3_s2() - MU_TOTAL) / MU_TOTAL

## μ_moon 的“G·M”形式（文档用；数值与 MU_MOON 一致到舍入）。
static func MOON_MU() -> float:
	return MU_MOON

## 由 μ_E、μ_M 推的地月质量比（用于验证 const MU）。
static func mu_derived() -> float:
	return MU_MOON / MU_TOTAL

## 旋转系（+X 指向月球，XY=轨道面）→ 惯性系。
static func rot_to_inertial(v: Vector3, phase_rad: float) -> Vector3:
	var c := cos(phase_rad)
	var s := sin(phase_rad)
	return Vector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)

## 共转速度：v = ω ẑ × r（rad/s）。
static func corotation_velocity(pos_km: Vector3, omega_rad_s: float) -> Vector3:
	return Vector3(0.0, 0.0, omega_rad_s).cross(pos_km)

## 把 Vector3 / [x,y,z] / {position|pos|r|position_km} 归一为 Vector3。
static func vec3_of(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float((v as Array)[0]), float((v as Array)[1]), float((v as Array)[2]))
	if v is Dictionary:
		for k in ["position", "pos", "r", "position_km", "position_inertial_km"]:
			if (v as Dictionary).has(k):
				return vec3_of((v as Dictionary).get(k))
	return Vector3.ZERO

## 两点距离（km）；接受 Vector3 / [x,y,z] / Dictionary（含 position/pos/r）。
static func distance(a, b) -> float:
	return vec3_of(a).distance_to(vec3_of(b))

static func arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

# ═══════════════════════════════════════════════════════════════════
# 时间 / 地球 / 月球状态
# ═══════════════════════════════════════════════════════════════════

func set_time(t_s: float) -> void:
	t = float(t_s)

func get_time() -> float:
	return t

## 月球相位（rad，0..2π）：t=0 时在惯性 +X。
static func moon_phase(t_s: float) -> float:
	return fposmod(moon_mean_motion() * t_s, TAU)

## 月球状态：惯性位置/速度（km、km/s）。
static func moon_state(t_s: float) -> Dictionary:
	var phase := moon_phase(t_s)
	var n := moon_mean_motion()
	var pos := Vector3(cos(phase), sin(phase), 0.0) * EARTH_MOON_DIST_KM
	var vel := Vector3(-sin(phase), cos(phase), 0.0) * (n * EARTH_MOON_DIST_KM)
	return {
		"position": arr(pos),
		"velocity": arr(vel),
		"distance_km": pos.length(),
		"speed_kmps": vel.length(),
		"phase_rad": phase,
		"phase_deg": rad_to_deg(phase),
		"period_s": MOON_PERIOD_S,
		"mean_motion_rad_s": n,
		"mu_km3_s2": MU_MOON,
		"radius_km": MOON_RADIUS_KM,
		# 同步自转：月球本体 +X 指向地球（近地面），旋转角与轨道相位一致。
		"rotation_angle_rad": phase,
		"rotation_period_s": MOON_PERIOD_S,
	}

## 地球状态：固定在惯性原点的近似（忽略地月质心摆动）。
static func earth_state(t_s: float) -> Dictionary:
	var omega := TAU / EARTH_SIDEREAL_DAY_S
	return {
		"position": [0.0, 0.0, 0.0],
		"velocity": [0.0, 0.0, 0.0],
		"radius_km": EARTH_RADIUS_KM,
		"mu_km3_s2": MU_EARTH,
		"sidereal_day_s": EARTH_SIDEREAL_DAY_S,
		"rotation_angle_rad": fposmod(omega * t_s, TAU),
		"angular_velocity_rad_s": omega,
	}

# ═══════════════════════════════════════════════════════════════════
# L1–L5：CR3BP 旋转系驻点
#   旋转系归一化：地月距离 R=1，地球在 x=-μ，月球在 x=1-μ（质心系），
#   共线平衡方程 f(x) = x - (1-μ)(x+μ)/|x+μ|³ - μ(x-1+μ)/|x-1+μ|³ = 0。
#   二分法求根（不写死数值），再换算为地心旋转系 km 与惯性系。
# ═══════════════════════════════════════════════════════════════════

static func collinear_equation(x: float) -> float:
	var d1 := absf(x + MU)
	var d2 := absf(x - 1.0 + MU)
	if d1 < 1.0e-12 or d2 < 1.0e-12:
		return NAN
	return x - (1.0 - MU) * (x + MU) / (d1 * d1 * d1) \
		- MU * (x - 1.0 + MU) / (d2 * d2 * d2)

static func _bisect(lo: float, hi: float, iterations := 200) -> float:
	var flo := collinear_equation(lo)
	var fhi := collinear_equation(hi)
	if is_nan(flo) or is_nan(fhi) or flo * fhi > 0.0:
		return NAN
	for i in range(iterations):
		var mid := 0.5 * (lo + hi)
		var fm := collinear_equation(mid)
		if is_nan(fm):
			return mid
		if absf(hi - lo) <= 1.0e-15:
			return mid
		if fm * flo <= 0.0:
			hi = mid
			fhi = fm
		else:
			lo = mid
			flo = fm
	return 0.5 * (lo + hi)

## 共线平衡点归一化根（质心系；用二分法求 f(x)=0，不写死数值）。
static func _collinear_roots_normalized() -> Dictionary:
	var eps := 1.0e-6
	return {
		"L1": _bisect(-MU + eps, 1.0 - MU - eps),   # L1：地月之间
		"L2": _bisect(1.0 - MU + eps, 2.0),         # L2：月球外侧
		"L3": _bisect(-2.0, -MU - eps),             # L3：地球外侧（反月点）
	}

## 三个共线点在“地心旋转系”的位置（km，+X 指向月球，XY=轨道面）。
static func collinear_points_rotating_km() -> Dictionary:
	var roots := _collinear_roots_normalized()
	var r := EARTH_MOON_DIST_KM
	return {
		"L1": Vector3((float(roots["L1"]) + MU) * r, 0.0, 0.0),
		"L2": Vector3((float(roots["L2"]) + MU) * r, 0.0, 0.0),
		"L3": Vector3((float(roots["L3"]) + MU) * r, 0.0, 0.0),
	}

## 归一化共线点（质心系，用于验证 f(x)≈0；直接用根，不经 km 往返，避免 float32 损失）。
static func collinear_points_normalized() -> Dictionary:
	return _collinear_roots_normalized()

## L1–L5 在旋转系（地心）的位置（km）。L4/L5 为 ±60°。
static func lagrange_rotating_km() -> Dictionary:
	var out := collinear_points_rotating_km()
	var r := EARTH_MOON_DIST_KM
	out["L4"] = Vector3(0.5 * r, sqrt(3.0) / 2.0 * r, 0.0)
	out["L5"] = Vector3(0.5 * r, -sqrt(3.0) / 2.0 * r, 0.0)
	return out

## 全部 L 点：旋转系 + 惯性系位置/速度、与地/月距离、与月球夹角。
static func lagrange_state(t_s: float) -> Dictionary:
	var phase := moon_phase(t_s)
	var n := moon_mean_motion()
	var rot := lagrange_rotating_km()
	var moon_pos := vec3_of(moon_state(t_s).get("position"))
	var out := {}
	for pid in ["L1", "L2", "L3", "L4", "L5"]:
		var rp: Vector3 = rot[pid]
		var ip := rot_to_inertial(rp, phase)
		# 共转近似：L 点在旋转系静止 → 惯性系以月球角速度绕地球旋转。
		var iv := corotation_velocity(ip, n)
		var moon_dir := moon_pos.normalized()
		var pos_dir := ip.normalized()
		var angle := rad_to_deg(acos(clampf(pos_dir.dot(moon_dir), -1.0, 1.0)))
		var side := 1.0
		if rp.y < 0.0:
			side = -1.0
		elif rp.y > 0.0:
			side = 1.0
		out[pid] = {
			"id": pid,
			"position_rot_km": arr(rp),
			"position": arr(ip),
			"velocity": arr(iv),
			"distance_earth_km": ip.length(),
			"distance_moon_km": ip.distance_to(moon_pos),
			"angle_from_moon_deg": angle,
			# 相对“地月连线”的旋转系角度（L1/L2/L3=0/180，L4/L5=±60）
			"rot_angle_deg": rad_to_deg(atan2(rp.y, rp.x)),
			"lagrange_type": "collinear" if pid in ["L1", "L2", "L3"] else "triangular",
			"side": side,
		}
	return out

# ═══════════════════════════════════════════════════════════════════
# 环（GEO / 月球同步）采样
# ═══════════════════════════════════════════════════════════════════

static func geo_ring(t_s: float, count := 24) -> Dictionary:
	var omega := TAU / EARTH_SIDEREAL_DAY_S
	var phase0 := fposmod(omega * t_s + GEO_PHASE0, TAU)
	var points: Array = []
	var velocities: Array = []
	for k in range(maxi(3, count)):
		var a := phase0 + TAU * float(k) / float(maxi(3, count))
		var p := Vector3(cos(a), sin(a), 0.0) * GEO_RADIUS_KM
		points.append(arr(p))
		velocities.append(arr(corotation_velocity(p, omega)))
	return {
		"id": "geo_ring",
		"name": "地球静止环 / GEO RING",
		"parent": "earth",
		"kind": "ring",
		"radius_km": GEO_RADIUS_KM,
		"period_s": geo_period_s(),
		"period_days": geo_period_s() / 86400.0,
		"count": maxi(3, count),
		"points": points,
		"velocities": velocities,
	}

static func lunar_sync_ring(t_s: float, count := 24) -> Dictionary:
	var phase := moon_phase(t_s)
	var moon_pos := vec3_of(moon_state(t_s).get("position"))
	var moon_vel := vec3_of(moon_state(t_s).get("velocity"))
	var radius := lunar_sync_radius_km()
	var n := moon_mean_motion()
	var points: Array = []
	var velocities: Array = []
	for k in range(maxi(3, count)):
		var a := LUNAR_SYNC_PHASE0 + TAU * float(k) / float(maxi(3, count))
		var rel_rot := Vector3(cos(a), sin(a), 0.0) * radius
		var rel := rot_to_inertial(rel_rot, phase)
		points.append(arr(moon_pos + rel))
		velocities.append(arr(moon_vel + corotation_velocity(rel, n)))
	return {
		"id": "lunar_sync_ring",
		"name": "月球同步环 / LUNAR-SYNC RING",
		"parent": "moon",
		"kind": "ring",
		"radius_km": radius,
		"period_s": lunar_sync_period_s(),
		"period_days": lunar_sync_period_s() / 86400.0,
		"count": maxi(3, count),
		"hill_radius_km": hill_radius_km(),
		"outside_hill_sphere": radius > hill_radius_km(),
		"points": points,
		"velocities": velocities,
	}

# ═══════════════════════════════════════════════════════════════════
# 站点
# ═══════════════════════════════════════════════════════════════════

static func _station_base(id: String, name: String, kind: String, parent: String,
		radius_km: float, period: float, inclination_deg := 0.0) -> Dictionary:
	return {
		"id": id, "name": name, "kind": kind, "parent": parent,
		"orbit": {
			"radius_km": radius_km,
			"period_s": period,
			"period_days": period / 86400.0,
			"inclination_deg": inclination_deg,
		},
	}

static func stations_state(t_s: float) -> Array:
	var phase := moon_phase(t_s)
	var n := moon_mean_motion()
	var moon_pos := vec3_of(moon_state(t_s).get("position"))
	var moon_vel := vec3_of(moon_state(t_s).get("velocity"))
	var lag := lagrange_state(t_s)
	var out: Array = []

	# —— L1/L2/L4/L5 站（共转，静止于旋转系）——
	for pair in [["L1", "l1_station", "L1 前哨站 / L1 STATION"],
			["L2", "l2_station", "L2 中继站 / L2 STATION"],
			["L4", "l4_station", "L4 站 / L4 STATION"],
			["L5", "l5_station", "L5 站 / L5 STATION"]]:
		var lpid := String(pair[0])
		var stid := String(pair[1])
		var stname := String(pair[2])
		var ld: Dictionary = lag[lpid]
		var st := _station_base(stid, stname, "lagrange_station", "earth",
			float(ld.get("distance_earth_km", 0.0)), MOON_PERIOD_S, 0.0)
		st["lagrange_id"] = lpid
		st["position"] = (ld.get("position", []) as Array).duplicate()
		st["velocity"] = (ld.get("velocity", []) as Array).duplicate()
		st["speed_kmps"] = vec3_of(st["velocity"]).length()
		st["distance_earth_km"] = float(ld.get("distance_earth_km", 0.0))
		st["distance_moon_km"] = float(ld.get("distance_moon_km", 0.0))
		out.append(st)

	# —— GEO 环（取环上 t 时刻的锚点）——
	var geo_period := geo_period_s()
	var omega_e := TAU / EARTH_SIDEREAL_DAY_S
	var geo_phase := fposmod(omega_e * t_s + GEO_PHASE0, TAU)
	var geo_pos := Vector3(cos(geo_phase), sin(geo_phase), 0.0) * GEO_RADIUS_KM
	var st_geo := _station_base("geo_ring", "GEO 环锚点 / GEO RING", "ring_station", "earth",
		GEO_RADIUS_KM, geo_period, 0.0)
	st_geo["position"] = arr(geo_pos)
	st_geo["velocity"] = arr(corotation_velocity(geo_pos, omega_e))
	st_geo["speed_kmps"] = (corotation_velocity(geo_pos, omega_e)).length()
	st_geo["distance_earth_km"] = geo_pos.length()
	st_geo["distance_moon_km"] = geo_pos.distance_to(moon_pos)
	out.append(st_geo)

	# —— 月球同步环锚点（在月球同步半径上，随月球共转）——
	var ls_radius := lunar_sync_radius_km()
	var rel_rot := Vector3(cos(LUNAR_SYNC_PHASE0), sin(LUNAR_SYNC_PHASE0), 0.0) * ls_radius
	var rel := rot_to_inertial(rel_rot, phase)
	var ls_pos := moon_pos + rel
	var ls_vel := moon_vel + corotation_velocity(rel, n)
	var st_ls := _station_base("lunar_sync_ring", "月球同步环锚点 / LUNAR-SYNC",
		"ring_station", "moon", ls_radius, lunar_sync_period_s(), 0.0)
	st_ls["position"] = arr(ls_pos)
	st_ls["velocity"] = arr(ls_vel)
	st_ls["speed_kmps"] = ls_vel.length()
	st_ls["distance_earth_km"] = ls_pos.length()
	st_ls["distance_moon_km"] = rel.length()
	st_ls["outside_hill_sphere"] = ls_radius > hill_radius_km()
	out.append(st_ls)

	# —— 月球低轨站（赤道面）——
	var leo_radius := MOON_RADIUS_KM + LUNAR_LEO_ALTITUDE_KM
	var leo_period := period_s(leo_radius, MU_MOON)
	var leo_n := TAU / leo_period
	var leo_phase := fposmod(leo_n * t_s + LEO_PHASE0, TAU)
	var leo_rel := Vector3(cos(leo_phase), sin(leo_phase), 0.0) * leo_radius
	var leo_pos := moon_pos + leo_rel
	var leo_vel := moon_vel + Vector3(-sin(leo_phase), cos(leo_phase), 0.0) * (leo_n * leo_radius)
	var st_leo := _station_base("lunar_leo", "月球低轨站 / LUNAR LEO", "lunar_orbit_station",
		"moon", leo_radius, leo_period, 0.0)
	st_leo["position"] = arr(leo_pos)
	st_leo["velocity"] = arr(leo_vel)
	st_leo["speed_kmps"] = leo_vel.length()
	st_leo["distance_earth_km"] = leo_pos.length()
	st_leo["distance_moon_km"] = leo_rel.length()
	st_leo["altitude_km"] = leo_radius - MOON_RADIUS_KM
	out.append(st_leo)

	# —— 月球极轨站（倾角 90°，绕月）——
	var pol_phase := fposmod(leo_n * t_s + POLAR_PHASE0, TAU)
	var pol_rel := Vector3(cos(pol_phase), 0.0, sin(pol_phase)) * leo_radius
	var pol_pos := moon_pos + pol_rel
	var pol_vel := moon_vel + Vector3(-sin(pol_phase), 0.0, cos(pol_phase)) * (leo_n * leo_radius)
	var st_pol := _station_base("lunar_polar", "月球极轨站 / LUNAR POLAR", "lunar_orbit_station",
		"moon", leo_radius, leo_period, 90.0)
	st_pol["position"] = arr(pol_pos)
	st_pol["velocity"] = arr(pol_vel)
	st_pol["speed_kmps"] = pol_vel.length()
	st_pol["distance_earth_km"] = pol_pos.length()
	st_pol["distance_moon_km"] = pol_rel.length()
	st_pol["altitude_km"] = leo_radius - MOON_RADIUS_KM
	out.append(st_pol)

	# —— 地球港（地球赤道表面，随地球自转）——
	var earth_omega := TAU / EARTH_SIDEREAL_DAY_S
	var earth_phase := fposmod(earth_omega * t_s, TAU)
	var ep_pos := Vector3(cos(earth_phase), sin(earth_phase), 0.0) * EARTH_RADIUS_KM
	var st_ep := _station_base("earth_port", "地球港 / EARTH PORT", "port", "earth",
		EARTH_RADIUS_KM, EARTH_SIDEREAL_DAY_S, 0.0)
	st_ep["position"] = arr(ep_pos)
	st_ep["velocity"] = arr(corotation_velocity(ep_pos, earth_omega))
	st_ep["speed_kmps"] = (corotation_velocity(ep_pos, earth_omega)).length()
	st_ep["distance_earth_km"] = ep_pos.length()
	st_ep["distance_moon_km"] = ep_pos.distance_to(moon_pos)
	out.append(st_ep)

	# —— 月球港（月球近地面赤道点，同步自转）——
	var mp_rel := Vector3(-MOON_RADIUS_KM, 0.0, 0.0)
	var mp_rel_i := rot_to_inertial(mp_rel, phase)
	var mp_pos := moon_pos + mp_rel_i
	var st_mp := _station_base("lunar_port", "月球港 / LUNAR PORT", "port", "moon",
		MOON_RADIUS_KM, MOON_PERIOD_S, 0.0)
	st_mp["position"] = arr(mp_pos)
	st_mp["velocity"] = arr(moon_vel + corotation_velocity(mp_rel_i, n))
	st_mp["speed_kmps"] = (moon_vel + corotation_velocity(mp_rel_i, n)).length()
	st_mp["distance_earth_km"] = mp_pos.length()
	st_mp["distance_moon_km"] = mp_rel_i.length()
	out.append(st_mp)

	# 每站补 relative distances（到地/月中心已在上面；补到两港的直观值）
	var earth_port_pos := Vector3.ZERO
	var lunar_port_pos := Vector3.ZERO
	for raw in out:
		if String((raw as Dictionary).get("id", "")) == "earth_port":
			earth_port_pos = vec3_of(raw)
		elif String((raw as Dictionary).get("id", "")) == "lunar_port":
			lunar_port_pos = vec3_of(raw)
	for raw in out:
		var st: Dictionary = raw
		st["distances"] = {
			"earth_center_km": float(st.get("distance_earth_km", 0.0)),
			"moon_center_km": float(st.get("distance_moon_km", 0.0)),
			"earth_port_km": vec3_of(st).distance_to(earth_port_pos),
			"lunar_port_km": vec3_of(st).distance_to(lunar_port_pos),
		}
	return out

# ═══════════════════════════════════════════════════════════════════
# 采样 / 轨道点列
# ═══════════════════════════════════════════════════════════════════

## 全系统快照；t_s 省略（< -1e29）时使用 model.t。全部 JSON 可序列化（km/km/s/rad）。
func sample(t_s := -1.0e30) -> Dictionary:
	var at := t
	if t_s > -1.0e29:
		at = t_s
	var moon := moon_state(at)
	var earth := earth_state(at)
	var lag := lagrange_state(at)
	var stations := stations_state(at)
	var rings := {
		"geo": geo_ring(at, 24),
		"lunar_sync": lunar_sync_ring(at, 24),
	}
	# 站点两两距离（便于验证/绘图；JSON dict）
	var distances := {"earth|moon": EARTH_MOON_DIST_KM}
	var st_ids: Array = []
	for raw in stations:
		st_ids.append(String((raw as Dictionary).get("id", "")))
	for i in range(st_ids.size()):
		for j in range(i + 1, st_ids.size()):
			var a_id := String(st_ids[i])
			var b_id := String(st_ids[j])
			var a: Dictionary = {}
			var b: Dictionary = {}
			for raw in stations:
				var st: Dictionary = raw
				if String(st.get("id", "")) == a_id:
					a = st
				elif String(st.get("id", "")) == b_id:
					b = st
			distances["%s|%s" % [a_id, b_id]] = vec3_of(a).distance_to(vec3_of(b))
	return {
		"model": MODEL_ID,
		"units": {"distance": "km", "velocity": "km_per_s", "angle": "rad", "time": "s"},
		"epoch": {"t0_iso": EPOCH_ISO, "t_s": at, "t_days": at / 86400.0},
		"mu": MU,
		"mu_derived": mu_derived(),
		"constants": {
			"mu_earth_km3_s2": MU_EARTH,
			"mu_moon_km3_s2": MU_MOON,
			"mu_total_km3_s2": MU_TOTAL,
			"earth_radius_km": EARTH_RADIUS_KM,
			"moon_radius_km": MOON_RADIUS_KM,
			"earth_moon_distance_km": EARTH_MOON_DIST_KM,
			"moon_period_s": MOON_PERIOD_S,
			"earth_sidereal_day_s": EARTH_SIDEREAL_DAY_S,
			"geo_radius_km": GEO_RADIUS_KM,
			"geo_period_s": geo_period_s(),
			"lunar_sync_radius_km": lunar_sync_radius_km(),
			"lunar_sync_period_s": lunar_sync_period_s(),
			"hill_radius_km": hill_radius_km(),
			"g_si": G_SI,
			"moon_mass_kg": MOON_MASS_KG,
			"mu_implied_km3_s2": implied_mu_km3_s2(),
			"mu_consistency_rel_err": mu_consistency_rel_err(),
			"vector_precision": "Godot Vector3 float32（相对 ~1e-7；384,400 km 处 ~0.03 km）",
		},
		"earth": earth,
		"moon": moon,
		"lagrange": lag,
		"stations": stations,
		"rings": rings,
		"distances": distances,
	}

## 轨道采样点列：月球轨道 / GEO 环 / 月球同步环（km、JSON 可序列化）。
func orbits(samples := 96) -> Dictionary:
	var n := maxi(8, samples)
	var moon_points: Array = []
	var geo_points: Array = []
	var ls_points: Array = []
	for k in range(n):
		var frac := float(k) / float(n)
		var tm := MOON_PERIOD_S * frac
		moon_points.append(moon_state(tm).get("position"))
		var ta := EARTH_SIDEREAL_DAY_S * frac
		var geo := geo_ring(ta, 1)
		geo_points.append(((geo.get("points", []) as Array)[0] as Array).duplicate())
		ls_points.append(lunar_sync_ring(tm, 1).get("points", [])[0])
	return {
		"model": MODEL_ID,
		"samples": n,
		"moon": {
			"id": "moon_orbit", "parent": "earth",
			"radius_km": EARTH_MOON_DIST_KM, "period_s": MOON_PERIOD_S,
			"points": moon_points,
		},
		"geo": {
			"id": "geo_ring", "parent": "earth",
			"radius_km": GEO_RADIUS_KM, "period_s": geo_period_s(),
			"points": geo_points,
		},
		"lunar_sync": {
			"id": "lunar_sync_ring", "parent": "moon",
			"radius_km": lunar_sync_radius_km(), "period_s": lunar_sync_period_s(),
			"points": ls_points,
		},
		"periods": {
			"moon_s": MOON_PERIOD_S,
			"geo_s": geo_period_s(),
			"lunar_sync_s": lunar_sync_period_s(),
			"earth_sidereal_day_s": EARTH_SIDEREAL_DAY_S,
		},
	}
