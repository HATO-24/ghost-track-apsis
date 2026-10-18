class_name SensorModel
extends RefCounted

## GHOST TRACK / APSIS · 传感器规则模型（P1b）
##
## 纯函数层：只做探测判定 / 接触等级 / 衰减 / 暴露 / 误差协方差。
## 不依赖 Node、不读写 UI、不 import state.gd；state / plot / hud 通过字典调用本文件。
##
## 数据与口径来源：
##   05_技术手册.md §3（S-01 IRST / S-02 雷达 / S-03 光学 / S-04 激光测距 /
##                       S-05 ELINT / S-06 IFF / S-07 航迹融合）+ §附录 A/B
##   06_工业与企业.md §4.3 感知 / §4.3 通信 / §4.6 配置 / §5 供应链
##   07_第一关_监督交接.md §1 教学目标 / §2 卡斯 / §3 Act 1 / Phase 1–3 / §7 数据需求
##   01_设计计划书.md §5 传感器与接触等级 / §5.3 探测概率
##   02_物理与轨道模型.md §8 相对几何 / §9.2 确定性
##   04_舰船设定.md §12 数据接口（传感器只有 ir / radar / optical；lidar 是 optical 子型）
##   09_UI设计.md §5 per-ship 传感器架 + §5.6 数据接口提案
##   10_术语表.md §7.3 05↔06 型号对照 / §10.1 接触等级（C-3：以 05/07 为准）
##
## 规则约定（与文档的分工）：
##   * 05 §S-01：IR 只给方位线、无距离、只给远/中/近三档；对应 L1。
##   * 05 §S-02：雷达给距离+方位 → L2；开机即暴露（ELINT 立刻获得方位并记录型号）；
##                数值 30,000 km 探测 / 15,000 km 稳定跟踪。
##   * 05 §S-03：光学需光照 + 凝视时间，分类完成 → L3；阴影区不可见。
##   * 05 §S-04：LR-4 是 optical 子型 lidar（04 §12），给火控级精确距离；暴露微弱（LWR）。
##   * 05 §S-05：ELINT 出「信号」不出「接触」：方位 + 特征码；静默时什么都收不到。
##   * 05 §S-06：IFF 2,000 km，应答正确 → L4；不应答 ≠ 敌意（永远不自动判敌）。
##   * 05 §S-07：融合周期 1 s；失去跟踪不删除，标记陈旧并逐级降级；协方差随时间变大。
##
## 只写规则，不写平衡：所有 05/06 没给的数字均标 [本文定值]，见 docs/11_传感器规则.md 参数表。
##
## 自测（headless，模块内静态函数）：
##   var ok: bool = SensorModel.run_self_test()
## 命令行见本文件末尾注释。
## ═══════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════
# 0. 接触等级（05 §附录 B / 07 §1 / 01 §5.2 / 10 §10.1）
#    L1 探测 → L2 定位 → L3 识别 → L4 确认。
#    C-3 冲突口径：04 §9.1 的「L2 认船厂」让位于 05/07（07 教学已实现）。
# ═══════════════════════════════════════════════════════════════════

const LEVEL_NONE := 0
const LEVEL_IR := 1        # 有回波 / 方位线（IR）
const LEVEL_TRACK := 2     # 定位（雷达 / 三角测量）
const LEVEL_CLASSIFY := 3  # 分类完成（光学凝视 + 数据库）
const LEVEL_IDENTITY := 4  # 识别到具体舰名（IFF / 信号指纹 / 数据库比对）

const LEVEL_LABELS := [
	"L0 无接触",
	"L1 有回波 · 仅方位",
	"L2 定位 · 舰种未知",
	"L3 分类完成 · 舰级/船厂/阵营",
	"L4 识别到具体舰名",
]

const LEVEL_CAPS := [
	[],
	["方位线（无距离解）", "极粗距离档：远 / 中 / 近"],
	["距离 + 方位", "航向 / 径向速度", "可推测威胁大小"],
	["舰级 / 船厂 / 使用方", "可分配火力"],
	["舰名 / 舷号 / 具体身份", "知道它的武器与弱点"],
]

# 证据有效期（秒，自该级证据最近一次写入起算）。
# 05 §S-07 只规定「逐级降级 L4→L3→L2→L1」，未给时间；下列为 [本文定值]，
# 按第一关 12–15 分钟节奏校准：
#   L4 证据 30 s 后失效 → 掉到 L3（L3 证据累计 90 s、L2 证据累计 210 s 仍有效）
#   L3 证据 90 s 后失效 → 掉到 L2
#   L2 证据 210 s 后失效 → 掉到 L1（L1 是记忆地板，05 §S-07：失去跟踪不删除）
const LEVEL_VALID_S := {4: 30.0, 3: 90.0, 2: 210.0}

const FUSION_PERIOD_S := 1.0     # 05 §S-07：融合周期 1 s
const STALE_AFTER_S := 30.0      # [本文定值] 失去刷新 → 标记陈旧（state.gd 现有 stale=age>30）
const MEMORY_KEEP_S := 300.0     # [本文定值] 只给 sim 的清理提示；05 §S-07 要求不删除

# 协方差增长：目标未知加速度按 0.1 g（04 §8 炮舰侧向机动基线）[本文定值]
const TARGET_ACCEL_KMPS2 := 0.00098


# ═══════════════════════════════════════════════════════════════════
# 1. 探测概率（01 §5.3）
#    SNR_dB = -10·n·log10(R / R_ref)，n=2（IR/ELINT 单程）或 4（雷达/激光测距双程）
#    Pd = 1 / (1 + exp(-k·SNR_dB))，k 由 [本文定值] 取 0.5 / dB
#    R_ref 定义为 Pd=0.5 的距离（即 05/06 给出的「探测距离」口径）。
# ═══════════════════════════════════════════════════════════════════

const DETECT_SLOPE_DB := 0.5
const LN10 := 2.302585092994046
const JAMMED_RANGE_FACTOR := 0.30   # 05 §E-01：噪声干扰可把雷达探测距离压到 30%
const LPI_INTERCEPT_MULT := 0.5     # 06：KD-R6 低截获概率 → 更难被定位
const LPI_FIX_MULT := 2.0           # 同上：被定位所需时长翻倍


# ═══════════════════════════════════════════════════════════════════
# 2. 暴露 / EMCON（05 §S-02 / §S-04 / §S-06 / §C-01 / §C-02 / §E-01）
# ═══════════════════════════════════════════════════════════════════

# 开机权重：0 = 纯被动；1 = 全场最亮（05 §E-01「干扰机自己变成全场最亮的信号源」）
const EXPOSURE_WEIGHT := {
	"ir": 0.0, "optical": 0.0, "elint": 0.0,
	"radar": 1.0, "iff": 0.6, "radio": 0.5, "lidar": 0.25, "lasercom": 0.15,
}

# 谁能截获：elint = 对方 ELINT 可全向截获；lwr = 只有被照射目标收到激光告警；
# scatter = 激光通信侧向散射，概率极低（05 §C-01）
const EXPOSURE_KIND := {
	"radar": "elint", "iff": "elint", "radio": "elint",
	"lidar": "lwr", "lasercom": "scatter",
}

# ELINT 截获距离 = 该发射器标称距离 × 系数。05 §S-05 只给「取决于对方发射」，
# 下面系数为 [本文定值]，给第一关用（雷达单程优势，IFF 询问范围 ×2，无线电可测向，
# 激光通信几乎截不到；激光测距 0 —— 05 §S-04 只有被照射目标的激光告警机收到，不是 ELINT）。
const ELINT_INTERCEPT_FACTOR := {
	"radar": 1.5, "iff": 2.0, "radio": 0.5, "lidar": 0.0, "lasercom": 0.02,
}

# 被定位所需开机时长（秒，[本文定值]；05 §S-02「开得越久，被定位得越准」）
const ELINT_FIX_TIME_S := {
	"radar": 20.0, "iff": 12.0, "radio": 40.0, "lidar": 30.0, "lasercom": 60.0,
}

# IFF 友军码前缀（[本文定值]；05 §S-06 只说「编码询问 / 正确码」）
const ALLIED_CODES := ["CMP"]


# ═══════════════════════════════════════════════════════════════════
# 3. 型号库（05 §3 + 06 §4.3；参数逐项标来源，未给的标 [本文定值]）
#    必填字段（任务 schema）：source / maker / model / type / range_km /
#    refresh_s / expose —— source 在「按舰架」里填（见 §4 RACK_BLUEPRINTS），
#    型号库里只填技参。
# ═══════════════════════════════════════════════════════════════════

const SENSOR_LIBRARY := {
	# ── 红外阵列（06 §4.3；05 §S-01 数值 120,000 km / 300 K / 1,000 m²）────────
	"MS-IR9": {
		"maker": "明视光学", "type": "ir", "mode": "被动红外",
		"range_km": 120000.0, "refresh_s": 1.0, "expose": false,
		"false_alarm": 0.02, "sigma_bearing_deg": 0.4,
		"band_edges": [0.333, 0.667],
		"ir_ref_temp_k": 300.0, "ir_ref_area_m2": 1000.0,
		"ref": "05 §S-01（120,000 km / 300 K / 1,000 m²）；06 §4.3；σ/虚警率 [本文定值]",
	},
	"NO-IR7": {
		"maker": "中村光学", "type": "ir", "mode": "被动红外",
		"range_km": 110000.0, "refresh_s": 1.0, "expose": false,
		"false_alarm": 0.04, "sigma_bearing_deg": 0.5,
		"band_edges": [0.333, 0.667],
		"ir_ref_temp_k": 300.0, "ir_ref_area_m2": 1000.0,
		"ref": "06 §4.3（110,000 km，抗震动寿命长）；其余 [本文定值]",
	},
	"YW-IR5": {
		"maker": "远望电子", "type": "ir", "mode": "被动红外",
		"range_km": 90000.0, "refresh_s": 1.0, "expose": false,
		"false_alarm": 0.08, "sigma_bearing_deg": 0.8,
		"band_edges": [0.333, 0.667],
		"ir_ref_temp_k": 300.0, "ir_ref_area_m2": 1000.0,
		"ref": "06 §4.3（90,000 km，抗干扰）；其余 [本文定值]",
	},
	"CH-IR2": {
		"maker": "车肆重工", "type": "ir", "mode": "被动红外",
		"range_km": 60000.0, "refresh_s": 1.0, "expose": false,
		"false_alarm": 0.22, "sigma_bearing_deg": 1.2,
		"band_edges": [0.333, 0.667],
		"ir_ref_temp_k": 300.0, "ir_ref_area_m2": 1000.0,
		"ref": "06 §4.3（60,000 km，虚警多）；09 §5.6 提案 false_alarm=0.22；σ [本文定值]",
	},

	# ── 雷达（06 §4.3；05 §S-02 30,000 探测 / 15,000 稳定跟踪）────────────────
	"YW-R9": {
		"maker": "远望电子", "type": "radar", "mode": "主动雷达",
		"range_km": 30000.0, "track_range_km": 15000.0, "refresh_s": 6.0,
		"expose": true, "expose_kind": "elint", "lpi": false,
		"jamming_resist": 0.2,
		"sigma_range_frac": 0.0025, "sigma_range_floor_km": 0.5,
		"sigma_bearing_deg": 0.15, "ref_rcs_m2": 10.0, "false_alarm": 0.03,
		"ref": "05 §S-02（30,000 / 15,000；开机即暴露）；06 §4.3（精度高、耗电大）；σ [本文定值]",
	},
	"KD-R6": {
		"maker": "红隼动力", "type": "radar", "mode": "主动雷达",
		"range_km": 28000.0, "track_range_km": 14000.0, "refresh_s": 6.0,
		"expose": true, "expose_kind": "elint", "lpi": true,
		"jamming_resist": 0.2,
		"sigma_range_frac": 0.004, "sigma_range_floor_km": 0.8,
		"sigma_bearing_deg": 0.25, "ref_rcs_m2": 10.0, "false_alarm": 0.04,
		"ref": "06 §4.3（28,000 km，低截获概率、精度略低）；track_range 取半 [本文定值]",
	},
	"MS-R4": {
		"maker": "明视光学", "type": "radar", "mode": "主动雷达",
		"range_km": 26000.0, "track_range_km": 13000.0, "refresh_s": 6.0,
		"expose": true, "expose_kind": "elint", "lpi": false,
		"jamming_resist": 0.5,
		"sigma_range_frac": 0.003, "sigma_range_floor_km": 0.6,
		"sigma_bearing_deg": 0.2, "ref_rcs_m2": 10.0, "false_alarm": 0.03,
		"ref": "06 §4.3（26,000 km，抗干扰强）；其余 [本文定值]",
	},
	"SC-R2": {
		"maker": "南十字动力", "type": "radar", "mode": "主动雷达",
		"range_km": 20000.0, "track_range_km": 10000.0, "refresh_s": 6.0,
		"expose": true, "expose_kind": "elint", "lpi": false,
		"jamming_resist": 0.0,
		"sigma_range_frac": 0.006, "sigma_range_floor_km": 1.0,
		"sigma_bearing_deg": 0.4, "ref_rcs_m2": 10.0, "false_alarm": 0.06,
		"ref": "06 §4.3（20,000 km，便宜、易被干扰）；其余 [本文定值]",
	},

	# ── 光学（05 §S-03；06 未列光学整机 → 型号本文登记，06 补目录时替换）──────
	"MS-OT2": {
		"maker": "明视光学", "type": "optical", "mode": "光学凝视",
		"range_km": 15000.0, "refresh_s": 8.0, "expose": false,
		"stare_s": 40.0, "stare_ref_km": 8000.0, "illum_min": 0.05,
		"reset_maneuver_g": 0.02,
		"sigma_bearing_deg": 0.05, "false_alarm": 0.0,
		"ref": "05 §S-03（15,000 km 可分辨舰级轮廓；需光照；需凝视）；05 §2.1（识别 40 s @ 8,000 km）；06 未列 → 型号本文登记",
	},
	"NO-OT1": {
		"maker": "中村光学", "type": "optical", "mode": "光学凝视",
		"range_km": 13000.0, "refresh_s": 8.0, "expose": false,
		"stare_s": 52.0, "stare_ref_km": 8000.0, "illum_min": 0.05,
		"reset_maneuver_g": 0.02,
		"sigma_bearing_deg": 0.06, "false_alarm": 0.0,
		"ref": "05 §S-03（口径 0.5–2 m）；06 §3.1（中村：抗震动、寿命长、比明视近一点）；其余 [本文定值]",
	},

	# ── 激光测距（05 §S-04；04 §12：optical 子型 lidar，不是第四种传感器）──────
	"LR-4": {
		"maker": "—", "type": "optical", "subtype": "lidar", "mode": "激光测距",
		"range_km": 4000.0, "refresh_s": 2.0, "expose": true, "expose_kind": "lwr",
		"sigma_range_km": 0.2, "sigma_bearing_deg": 0.05,
		"ref_rcs_m2": 10.0, "false_alarm": 0.0,
		"ref": "05 §S-04（4,000 km）；04 §12（optical 子型）；σ=0.2 km 为 [本文定值]（火控可用级）",
	},

	# ── 敌我识别（05 §S-06；06 未列 IFF）────────────────────────────────────
	"MK-12": {
		"maker": "—", "type": "iff", "mode": "敌我识别",
		"range_km": 2000.0, "refresh_s": 2.0, "expose": true, "expose_kind": "elint",
		"sigma_bearing_deg": 1.0, "false_alarm": 0.0,
		"ref": "05 §S-06（2,000 km；应答正确 → L4；询问即暴露）；06 未列 IFF",
	},

	# ── ELINT（05 §S-05；06 未列通用接收阵列）──────────────────────────────
	"ELINT": {
		"maker": "—", "type": "elint", "mode": "通信截听",
		"range_km": 60000.0, "refresh_s": 1.0, "expose": false,
		"sigma_bearing_deg": 1.0, "false_alarm": 0.0,
		"ref": "05 §S-05（方位 + 特征码，不出接触；静默收不到）；截获距离 60,000 km 为 [本文定值]（05 未给）",
	},

	# ── 通信（06 §4.3）────────────────────────────────────────────────────
	"MS-L2": {
		"maker": "明视光学", "type": "lasercom", "mode": "激光通信",
		"range_km": 384400.0, "refresh_s": 0.5, "expose": false,
		"latency_s": 0.5, "los_required": true, "relay_capable": true,
		"ref": "06 §4.3（0.5 s 激光）；05 §C-01（延迟 0.3–2 s；需要视线；极低截获）；距离取 02 §11 地月距上限 [本文定值]",
	},
	"YW-L1": {
		"maker": "远望电子", "type": "lasercom", "mode": "激光通信",
		"range_km": 384400.0, "refresh_s": 1.0, "expose": false,
		"latency_s": 1.0, "los_required": true, "relay_capable": true,
		"ref": "06 §4.3（1 s 激光）；05 §C-01；距离 [本文定值]",
	},
	"CH-R0": {
		"maker": "车肆重工", "type": "radio", "mode": "无线电",
		"range_km": 120000.0, "refresh_s": 4.0, "expose": true, "expose_kind": "elint",
		"latency_s": 4.0, "los_required": false, "relay_capable": false,
		"ref": "06 §4.3（4 s 延迟，全向、易被干扰/测向）；距离取 09 §5.6 提案示例 120,000 km（04/06 未给通信距离）",
	},
}

# 05 §S-05：特征码 → 可推断的舰级/身份。level_support 按 05 §附录 B（信号指纹可到 L3/L4）。
const SIGNATURE_DB := {
	"YW-R9": {
		"signature": "search-radar", "class_hint": "R-9 搜索雷达",
		"platform_hint": "签约国 / 清算署标准雷达", "faction_hint": "签约国 / 清算署",
		"level_support": 3, "confidence": 0.8, "ref": "05 §S-05（示例：R-9 雷达只有清算级装）；06 §4.3",
	},
	"KD-R6": {
		"signature": "lpi-radar", "class_hint": "红隼低截获雷达",
		"platform_hint": "高端分遣队舰", "faction_hint": "签约国 / 公约",
		"level_support": 3, "confidence": 0.7, "ref": "06 §4.3（低截获概率）",
	},
	"MS-R4": {
		"signature": "search-radar", "class_hint": "明视 R-4 雷达",
		"platform_hint": "签约国舰", "faction_hint": "签约国",
		"level_support": 3, "confidence": 0.6, "ref": "06 §4.3",
	},
	"SC-R2": {
		"signature": "civil-radar", "class_hint": "南十字 R-2 雷达",
		"platform_hint": "民用 / 改装船", "faction_hint": "民用",
		"level_support": 2, "confidence": 0.5, "ref": "06 §4.3",
	},
	"CH-R0": {
		"signature": "radio", "class_hint": "车肆无线电",
		"platform_hint": "车肆改装船 / 民用", "faction_hint": "民用 / 公约",
		"level_support": 2, "confidence": 0.4, "ref": "06 §4.3（易被测向）",
	},
	"MK-12": {
		"signature": "iff-interrogator", "class_hint": "MK-12 询问",
		"platform_hint": "公约 / 签约国标准件", "faction_hint": "公约 / 签约国",
		"level_support": 2, "confidence": 0.5, "ref": "05 §S-06",
	},
	"MS-L2": {
		"signature": "lasercom-scatter", "class_hint": "激光通信侧向散射",
		"platform_hint": "中继舰 / 指挥链", "faction_hint": "未知",
		"level_support": 2, "confidence": 0.2, "ref": "05 §C-01（极低截获概率）",
	},
}


# ═══════════════════════════════════════════════════════════════════
# 4. 按舰载传感器架 schema
#    all_racks() → { ship_id: [sensor, ...] }
#    sensor 必填字段：source / maker / model / type / range_km / refresh_s / expose
#    扩展字段：on（默认开关）/ mode / subtype / track_range_km / stare_s /
#              sigma_* / false_alarm / lpi / latency_s / ref（来源）…
# ═══════════════════════════════════════════════════════════════════

const RACK_BLUEPRINTS := {
	# 远地点号（刺桐-2M，泉州重工，船坞舰，001）——旗舰，后方；07 §2
	"apsis": {
		"source": "公约 · AD 特遣群",
		"sensors": [
			{"model": "MS-IR9", "on": true},
			{"model": "MS-OT2", "on": true},
			{"model": "MK-12", "on": false},   # 询问即暴露，按需
			{"model": "ELINT", "on": true},
		],
	},
	# 哈马丹号（托盘-5 改，车肆重工，哨舰，114）——舰队 AWACS/EWR 节点（19 §6）
	"harmattan": {
		"source": "公约 · AD 特遣群",
		"sensors": [
			{"model": "YW-R9", "on": false},   # 默认 EMCON；第一关由命令哈马丹开机
			{"model": "MS-OT2", "on": true},
			{"model": "CH-IR2", "on": true},
			{"model": "ELINT", "on": true},
			{"model": "CH-R0", "on": true},
		],
	},
	# 渡口号（赤铁-6 改，永昼机械，炮舰）——传感器差，但有火控级 LR-4
	"ferry": {
		"source": "公约 · AD 特遣群",
		"sensors": [
			{"model": "CH-IR2", "on": true},
			{"model": "LR-4", "on": false},
			{"model": "CH-R0", "on": true},
		],
	},
	# 深井号（月港-4，泉州重工，油船）——只有无线电
	"deepwell": {
		"source": "公约 · AD 特遣群",
		"sensors": [
			{"model": "CH-R0", "on": true},
		],
	},
	# 望楼号（安海-1，泉州重工，中继舰）——07 §7：望楼的激光通信
	"watchtower": {
		"source": "公约 · AD 特遣群",
		"sensors": [
			{"model": "MS-L2", "on": true},
			{"model": "CH-R0", "on": true},
		],
	},
	# AV-4412 传唤者（2001，传唤级，清算署）——它的 ELINT 会点名玩家雷达（07 §3 Phase 1）
	"summons_4471": {
		"source": "清算署",
		"sensors": [
			{"model": "YW-R9", "on": false},
			{"model": "MK-12", "on": false},
			{"model": "ELINT", "on": true},
			{"model": "CH-R0", "on": true},
		],
	},
	# 谷神-2（谷神改，远环合作社，民用工作船）——应答机故障；只有无线电
	"ceres_2": {
		"source": "远环合作社",
		"sensors": [
			{"model": "CH-R0", "on": true},
		],
	},
}

# 舰级元数据（占位：最终进 data/ships.json 或 scenario.json）。
# rcs_m2 / temp_k / area_m2 只服务探测判定的量纲，不是 04 的最终数据。
const SHIPS := {
	"apsis": {
		"name": "远地点", "name_en": "APSIS", "hull": "001", "ship_class": "远地点级",
		"builder": "泉州重工", "role": "船坞舰", "faction": "公约", "side": "friend",
		"transponder": "ok", "iff_code": "CMP-001",
		"rcs_m2": 12000.0, "temp_k": 320.0, "area_m2": 9000.0,
	},
	"harmattan": {
		"name": "哈马丹", "name_en": "HARMATTAN", "hull": "114", "ship_class": "托盘-5 改",
		"builder": "车肆重工", "role": "哨舰", "faction": "公约", "side": "friend",
		"transponder": "ok", "iff_code": "CMP-114",
		"rcs_m2": 300.0, "temp_k": 305.0, "area_m2": 700.0,
	},
	"ferry": {
		"name": "渡口号", "name_en": "FERRY", "hull": "207", "ship_class": "赤铁-6 改",
		"builder": "永昼机械", "role": "炮舰", "faction": "公约", "side": "friend",
		"transponder": "ok", "iff_code": "CMP-207",
		"rcs_m2": 1200.0, "temp_k": 310.0, "area_m2": 1800.0,
	},
	"deepwell": {
		"name": "深井", "name_en": "DEEPWELL", "hull": "503", "ship_class": "月港-4",
		"builder": "泉州重工", "role": "油船", "faction": "公约", "side": "friend",
		"transponder": "ok", "iff_code": "CMP-503",
		"rcs_m2": 4000.0, "temp_k": 300.0, "area_m2": 4600.0,
	},
	"watchtower": {
		"name": "望楼", "name_en": "WATCHTOWER", "hull": "311", "ship_class": "安海-1",
		"builder": "泉州重工", "role": "中继舰", "faction": "公约", "side": "friend",
		"transponder": "ok", "iff_code": "CMP-311",
		"rcs_m2": 1500.0, "temp_k": 300.0, "area_m2": 1200.0,
	},
	"summons_4471": {
		"name": "案卷 4471", "name_en": "SUMMONS", "hull": "4471", "ship_class": "传唤级",
		"builder": "清算署改装", "role": "送达舰", "faction": "清算署", "side": "hostile",
		"transponder": "ok", "iff_code": "RCV-4471",
		"rcs_m2": 1400.0, "temp_k": 310.0, "area_m2": 1600.0,
	},
	"ceres_2": {
		"name": "谷神-2", "name_en": "CERES-2", "hull": "G-2", "ship_class": "谷神改",
		"builder": "远环合作社", "role": "民用 · 应答机故障", "faction": "民用", "side": "unknown",
		"transponder": "faulty", "iff_code": "",
		"rcs_m2": 800.0, "temp_k": 295.0, "area_m2": 1500.0,
	},
}

static var _racks_cache: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════
# 5. 查询 API（架 / 型号 / 舰）
# ═══════════════════════════════════════════════════════════════════

static func ship_ids() -> Array:
	return SHIPS.keys()


static func ship_info(ship_id: String) -> Dictionary:
	var info: Dictionary = SHIPS.get(ship_id, {})
	return info.duplicate(true)


static func level_label(level: int) -> String:
	var i: int = clampi(level, 0, LEVEL_LABELS.size() - 1)
	return String(LEVEL_LABELS[i])


static func level_caps(level: int) -> Array:
	var i: int = clampi(level, 0, LEVEL_CAPS.size() - 1)
	return (LEVEL_CAPS[i] as Array).duplicate()


static func sensor_model_info(model: String) -> Dictionary:
	var base: Dictionary = SENSOR_LIBRARY.get(model, {})
	var out: Dictionary = base.duplicate(true)
	out["model"] = model
	return out


static func _build_all_racks() -> Dictionary:
	var out: Dictionary = {}
	for raw_ship_id in RACK_BLUEPRINTS.keys():
		var ship_id := String(raw_ship_id)
		var bp: Dictionary = RACK_BLUEPRINTS[ship_id]
		var arr: Array = []
		for raw_entry in (bp["sensors"] as Array):
			var entry: Dictionary = raw_entry
			arr.append(_make_sensor(entry, String(bp.get("source", "—"))))
		out[ship_id] = arr
	return out


static func _make_sensor(entry: Dictionary, source: String) -> Dictionary:
	var model := String(entry.get("model", ""))
	var base: Dictionary = SENSOR_LIBRARY.get(model, {})
	var s: Dictionary = base.duplicate(true)
	s["model"] = model
	s["source"] = String(entry.get("source", source))
	s["on"] = bool(entry.get("on", true))
	if not s.has("expose"):
		s["expose"] = false
	if not s.has("expose_kind"):
		s["expose_kind"] = ("elint" if bool(s.get("expose", false)) else "passive")
	if not s.has("false_alarm"):
		s["false_alarm"] = 0.0
	if not s.has("sigma_bearing_deg"):
		s["sigma_bearing_deg"] = 1.0
	for raw_key in entry.keys():
		var k := String(raw_key)
		if k == "model" or k == "source" or k == "on":
			continue
		s[k] = entry[k]
	return s


static func all_racks() -> Dictionary:
	if _racks_cache.is_empty():
		_racks_cache = _build_all_racks()
	return _racks_cache.duplicate(true)


static func sensor_rack(ship_id: String) -> Array:
	var racks: Dictionary = all_racks()
	var arr: Array = racks.get(ship_id, [])
	var out: Array = []
	for raw in arr:
		out.append((raw as Dictionary).duplicate(true))
	return out


static func rack_sensor(ship_id: String, model: String) -> Dictionary:
	for sensor in sensor_rack(ship_id):
		if String(sensor.get("model", "")) == model:
			return sensor
	return {}


static func rack_models(ship_id: String) -> Array:
	var out: Array = []
	for sensor in sensor_rack(ship_id):
		out.append(String(sensor.get("model", "")))
	return out


static func _sensor_on(sensor: Dictionary, ctx: Dictionary = {}) -> bool:
	var on_map: Dictionary = ctx.get("on", {})
	var model := String(sensor.get("model", ""))
	if on_map.has(model):
		return bool(on_map[model])
	return bool(sensor.get("on", true))


## 校验 schema；返回错误字符串数组（空 = 通过）。
static func validate_racks() -> Array:
	var errors: Array = []
	var required := ["source", "maker", "model", "type", "range_km", "refresh_s", "expose"]
	var valid_types := ["ir", "radar", "optical", "iff", "elint", "radio", "lasercom"]
	for ship_id in all_racks().keys():
		var rack: Array = all_racks()[ship_id]
		if rack.is_empty():
			errors.append("%s: 空传感器架" % ship_id)
		for sensor in rack:
			for field in required:
				if not (sensor as Dictionary).has(field):
					errors.append("%s/%s: 缺字段 %s" % [ship_id, sensor.get("model", "?"), field])
			var t := String(sensor.get("type", ""))
			if not valid_types.has(t):
				errors.append("%s/%s: type=%s 不在 %s" % [ship_id, sensor.get("model", "?"), t, str(valid_types)])
			if float(sensor.get("range_km", 0.0)) <= 0.0:
				errors.append("%s/%s: range_km 必须 > 0" % [ship_id, sensor.get("model", "?")])
			if float(sensor.get("refresh_s", 0.0)) <= 0.0:
				errors.append("%s/%s: refresh_s 必须 > 0" % [ship_id, sensor.get("model", "?")])
			if typeof(sensor.get("expose", null)) != TYPE_BOOL:
				errors.append("%s/%s: expose 必须是 bool" % [ship_id, sensor.get("model", "?")])
	return errors


## 由舰级元数据拼出一部「目标」字典（给仿真 / 测试 / plot 适配用）。
## overrides 可覆盖任意字段（range_km / bearing_deg / rcs_m2 / emissions …）。
## emissions 语义：雷达 / IFF / LR-4 按架的默认开关；**无线电 / 激光通信默认不发射**
## （通信模块「开机」= 在收听，发射由 sim 按命令/通话事件显式写入 on=true）。
static func target_from_ship(ship_id: String, range_km: float, bearing_deg: float,
		overrides: Dictionary = {}) -> Dictionary:
	var info: Dictionary = SHIPS.get(ship_id, {})
	var emissions: Array = []
	for sensor in sensor_rack(ship_id):
		var t := String(sensor.get("type", ""))
		if t == "ir" or t == "elint":
			continue
		if t == "optical":
			# 只有激光测距是发射器；光学望远镜是被动成像（04 §12：lidar 是 optical 子型）
			if String(sensor.get("subtype", "")) != "lidar":
				continue
		var emitting := bool(sensor.get("on", true))
		if t == "radio" or t == "lasercom":
			emitting = false
		emissions.append({
			"model": String(sensor.get("model", "")),
			"type": _emission_class(sensor),
			"on": emitting,
			"range_km": float(sensor.get("range_km", 0.0)),
			"lpi": bool(sensor.get("lpi", false)),
		})
	var target := {
		"id": ship_id,
		"name": String(info.get("name", ship_id)),
		"faction": String(info.get("faction", "unknown")),
		"side": String(info.get("side", "unknown")),
		"range_km": range_km,
		"bearing_deg": bearing_deg,
		"rcs_m2": float(info.get("rcs_m2", 10.0)),
		"temp_k": float(info.get("temp_k", 300.0)),
		"area_m2": float(info.get("area_m2", 1000.0)),
		"radial_vel_kmps": 0.0,
		"transponder": String(info.get("transponder", "off")),
		"iff_code": String(info.get("iff_code", "")),
		"classification": {
			"ship_class": String(info.get("ship_class", "—")),
			"builder": String(info.get("builder", "—")),
			"role": String(info.get("role", "—")),
			"faction": String(info.get("faction", "unknown")),
		},
		"emissions": emissions,
	}
	for raw_key in overrides.keys():
		target[String(raw_key)] = overrides[raw_key]
	return target


# ═══════════════════════════════════════════════════════════════════
# 6. 几何与概率工具
# ═══════════════════════════════════════════════════════════════════

## 02 §8.1：站心 +x 东 / +y 北 / +z 天顶（与 state.gd 的 L1 站心口径一致）。
static func bearing_range(pos_km: Vector3) -> Dictionary:
	var rng_km := pos_km.length()
	var bearing := 180.0
	if absf(pos_km.x) + absf(pos_km.y) > 1.0e-9:
		bearing = fposmod(rad_to_deg(atan2(pos_km.x, pos_km.y)), 360.0)
	return {"bearing_deg": bearing, "range_km": rng_km, "alt_km": pos_km.z}


## 地球/月球遮挡：线段−球体最近距离判定（02 §8；05 §S-02/S-03 对抗：地形遮挡 / 阴影）。
static func line_of_sight_ok(a_km: Vector3, b_km: Vector3,
		center_km: Vector3 = Vector3.ZERO, radius_km: float = 6378.137) -> bool:
	var ab := b_km - a_km
	var ab_len2 := ab.length_squared()
	if ab_len2 < 1.0e-12:
		return a_km.distance_to(center_km) > radius_km
	var t := clampf((center_km - a_km).dot(ab) / ab_len2, 0.0, 1.0)
	var closest := a_km + ab * t
	return closest.distance_to(center_km) > radius_km


## 01 §5.3 / 05 §S-02：探测概率。R_ref 为 Pd=0.5 的距离；n=2 单程、n=4 双程。
static func detection_pd(range_km: float, ref_range_km: float, exponent: float = 2.0) -> float:
	if ref_range_km <= 0.0:
		return 0.0
	if range_km <= 0.0:
		return 1.0
	var ratio: float = range_km / ref_range_km
	if ratio <= 0.0001:
		return 1.0
	var snr_db: float = -(10.0 * exponent) * (log(ratio) / LN10)
	return 1.0 / (1.0 + exp(-DETECT_SLOPE_DB * snr_db))


## IR 三档距离：以 05 §S-01 的「远 / 中 / 近」为准，按探测距离的 1/3、2/3 分档。
## [本文定值] 分档比例；05 只规定三档、不给阈值。
static func ir_range_band(range_km: float, sensor_range_km: float,
		edges: Array = [0.333, 0.667]) -> String:
	if range_km < 0.0 or sensor_range_km <= 0.0:
		return "UNKNOWN"
	var frac: float = range_km / sensor_range_km
	var near_edge: float = float(edges[0]) if edges.size() > 0 else 0.333
	var mid_edge: float = float(edges[1]) if edges.size() > 1 else 0.667
	if frac <= near_edge:
		return "NEAR"
	if frac <= mid_edge:
		return "MID"
	if frac <= 1.0:
		return "FAR"
	return "OUT"


## 方位漂移（度/秒），已处理 0/360 环绕。07 Phase 1「一条在动、一条不动」的判定工具。
static func bearing_drift_deg_per_s(prev_bearing_deg: float, bearing_deg: float, dt_s: float) -> float:
	if dt_s <= 0.0:
		return 0.0
	var diff := fposmod(bearing_deg - prev_bearing_deg + 180.0, 360.0) - 180.0
	return absf(diff) / dt_s


## 运动提示：IR 不给距离，只能靠方位漂移区分「在动 / 不动」。
## [本文定值] 阈值 0.02 °/s（< 0.005 °/s 视为静止）。
static func motion_hint(drift_deg_per_s: float) -> String:
	if drift_deg_per_s >= 0.02:
		return "moving"
	if drift_deg_per_s <= 0.005:
		return "static"
	return "unclear"


## 04 §2.3 / 01 §5.1：双平台方位交叉 → L2 定位（光学 / IR 纯方位定位的正规手段）。
## a/b 为平台 2D 位置（km，+x 东 / +y 北），方位为 0°=北 / 90°=东。
static func triangulate(a_pos_km: Vector2, a_bearing_deg: float, a_sigma_deg: float,
		b_pos_km: Vector2, b_bearing_deg: float, b_sigma_deg: float) -> Dictionary:
	var d1 := Vector2(sin(deg_to_rad(a_bearing_deg)), cos(deg_to_rad(a_bearing_deg)))
	var d2 := Vector2(sin(deg_to_rad(b_bearing_deg)), cos(deg_to_rad(b_bearing_deg)))
	var denom := d1.cross(d2)
	if absf(denom) < 1.0e-4:
		return {"ok": false, "reason": "parallel_rays"}
	var delta := b_pos_km - a_pos_km
	var t1 := delta.cross(d2) / denom
	var t2 := delta.cross(d1) / denom
	if t1 <= 0.0 or t2 <= 0.0:
		return {"ok": false, "reason": "intersection_behind_platform"}
	var pos := a_pos_km + d1 * t1
	var angle := rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0)))
	var cross_km := sqrt(pow(t1 * deg_to_rad(a_sigma_deg), 2.0) + pow(t2 * deg_to_rad(b_sigma_deg), 2.0))
	var sigma_range := cross_km / maxf(0.1, sin(deg_to_rad(angle)))
	var good := angle >= 10.0 and sigma_range <= t1 * 0.25
	return {
		"ok": true,
		"pos_km": pos,
		"range_km": t1,
		"range_from_b_km": t2,
		"angle_deg": angle,
		"sigma_range_km": sigma_range,
		"level_support": LEVEL_TRACK if good else LEVEL_IR,
	}


## 确定性随机：02 §9.2「不用 Math.random()，用种子化伪随机」。
## rng 为空时退化为 Pd≥0.5 的确定性判定（便于无状态测试）。
static func roll(pd: float, rng: Variant = null) -> bool:
	if pd >= 1.0:
		return true
	if pd <= 0.0:
		return false
	if rng is RandomNumberGenerator:
		return (rng as RandomNumberGenerator).randf() < pd
	return pd >= 0.5


# ═══════════════════════════════════════════════════════════════════
# 7. 暴露 / EMCON API
# ═══════════════════════════════════════════════════════════════════

## 发射分类：type=optical 且 subtype=lidar 的（LR-4）按 lidar 计权，
## 否则按 04 §12 的 ir / radar / optical 三型。避免把激光测距误当被动光学。
static func _emission_class(sensor: Dictionary) -> String:
	var t := String(sensor.get("type", ""))
	if t == "optical" and String(sensor.get("subtype", "")) == "lidar":
		return "lidar"
	return t


## 单部传感器的发射特征；被动传感器返回 {}。
static func emission_for(sensor: Dictionary) -> Dictionary:
	var t := _emission_class(sensor)
	var weight := float(EXPOSURE_WEIGHT.get(t, 0.0))
	if weight <= 0.0:
		return {}
	var kind := String(sensor.get("expose_kind", EXPOSURE_KIND.get(t, "elint")))
	var range_km := float(sensor.get("range_km", 0.0))
	var factor := float(ELINT_INTERCEPT_FACTOR.get(t, 0.0))
	var lpi := bool(sensor.get("lpi", false))
	var model := String(sensor.get("model", ""))
	return {
		"model": model,
		"type": t,
		"kind": kind,
		"weight": weight,
		"range_km": range_km,
		"elint_range_km": range_km * factor * (LPI_INTERCEPT_MULT if lpi else 1.0),
		"fix_after_s": float(ELINT_FIX_TIME_S.get(t, 30.0)) * (LPI_FIX_MULT if lpi else 1.0),
		"lpi": lpi,
		"signature": model,
		"seconds_on": 0.0,
	}


## 05 §S-02「开得越久，被定位得越准」：测向 σ 从 1.0° 随开机时长收敛到 0.2°。
static func expose_fix(seconds_on: float, emitter_type: String, lpi: bool = false) -> Dictionary:
	var fix_after_s := float(ELINT_FIX_TIME_S.get(emitter_type, 30.0)) * (LPI_FIX_MULT if lpi else 1.0)
	var progress := clampf(seconds_on / maxf(1.0e-6, fix_after_s), 0.0, 1.0)
	return {
		"seconds_on": seconds_on,
		"fix_after_s": fix_after_s,
		"progress": progress,
		"fixed": progress >= 1.0,
		"bearing_sigma_deg": lerp(1.0, 0.2, progress),
	}


## 本舰当前暴露态。ctx:
##   "on": {model: bool} 覆盖开关
##   "seconds_on": {model: float} 已开机/发射时长
##   "transmitting": ["CH-R0"] 正在发送的通信模块（通信「开着」不等于在发射）
static func emission_state(ship_id: String, ctx: Dictionary = {}) -> Dictionary:
	var seconds: Dictionary = ctx.get("seconds_on", {})
	var transmitting: Array = ctx.get("transmitting", [])
	var emitters: Array = []
	var max_weight := 0.0
	for sensor in sensor_rack(ship_id):
		var raw_type := String(sensor.get("type", ""))
		var eclass := _emission_class(sensor)
		if raw_type == "radio" or raw_type == "lasercom":
			if not transmitting.has(String(sensor.get("model", ""))):
				continue
		if not _sensor_on(sensor, ctx):
			continue
		var em := emission_for(sensor)
		if em.is_empty():
			continue
		var model := String(em.get("model", ""))
		var sec := float(seconds.get(model, 0.0))
		em["seconds_on"] = sec
		em["fix"] = expose_fix(sec, eclass, bool(em.get("lpi", false)))
		emitters.append(em)
		max_weight = maxf(max_weight, float(em.get("weight", 0.0)))
	var warnings: Array = []
	for em in emitters:
		var kind := String(em.get("kind", "elint"))
		if kind == "lwr":
			warnings.append("%s 激光照射：只有被照目标收到激光告警（05 §S-04）" % String(em.get("model", "")))
		elif kind == "scatter":
			warnings.append("%s 激光通信：侧向散射，极低概率被截听（05 §C-01）" % String(em.get("model", "")))
		else:
			warnings.append("%s 开机即暴露：ELINT 可截获 %d km，%.0f s 后可定位（05 §S-02）" % [
				String(em.get("model", "")), int(round(float(em.get("elint_range_km", 0.0)))),
				float(em.get("fix_after_s", 0.0)),
			])
	return {
		"ship_id": ship_id,
		"emitters": emitters,
		"emission_level": max_weight,
		"exposed": emitters.size() > 0,
		"emcon": emitters.is_empty(),
		"warnings": warnings,
	}


## 对方 ELINT 观察本舰发射器：05 §S-02「开机即暴露：对方 ELINT 立刻获得你的方位，
## 且你的雷达型号被记录」。
static func elint_intercept(emitter: Dictionary, distance_km: float, seconds_on: float,
		ctx: Dictionary = {}) -> Dictionary:
	var t := String(emitter.get("type", ""))
	var lpi := bool(emitter.get("lpi", false))
	var fix := expose_fix(seconds_on, t, lpi)
	var erange := float(emitter.get("elint_range_km", 0.0))
	var pd := detection_pd(distance_km, erange, 2.0)
	var detected := roll(pd, ctx.get("rng"))
	return {
		"detected": detected,
		"pd": pd,
		"immediate": detected,
		"model_recorded": String(emitter.get("model", "")) if detected else "",
		"signal": String(emitter.get("signature", "")) if detected else "",
		"bearing_sigma_deg": fix["bearing_sigma_deg"],
		"fix": fix["fixed"],
		"fix_after_s": fix["fix_after_s"],
		"warning": "开机即暴露（05 §S-02；05 §附录 A）" if detected else "",
	}


## EMCON 计划：把所有会暴露的模块预置为关（供 UI / 命令层使用）。
static func emcon_plan(ship_id: String) -> Dictionary:
	var plan: Dictionary = {}
	for sensor in sensor_rack(ship_id):
		var t := String(sensor.get("type", ""))
		if bool(sensor.get("expose", false)) or t == "radio" or t == "lasercom":
			plan[String(sensor.get("model", ""))] = false
	return plan


## 虚警（06：CH-IR2「虚警多，常把残骸当敌舰」）。默认关闭，由 sim 显式启用。
static func maybe_false_alarm(sensor: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var p := float(sensor.get("false_alarm", 0.0))
	p += float(ctx.get("clutter", 0.0))
	p *= float(ctx.get("false_alarm_scale", 1.0))
	var alarm := roll(clampf(p, 0.0, 1.0), ctx.get("rng"))
	return {
		"alarm": alarm,
		"bearing_deg": float(ctx.get("false_bearing_deg", 0.0)),
		"level_support": LEVEL_IR if alarm else LEVEL_NONE,
		"warning": "虚警候选（06 CH-IR2：虚警多，常把残骸当敌舰）" if alarm else "",
	}


# ═══════════════════════════════════════════════════════════════════
# 8. 单传感器判定
#    统一返回 observation 字典：
#    { sensor, maker, kind, detected, pd, level_support, produces_contact,
#      bearing_deg, bearing_sigma_deg, range_km, range_sigma_km, range_band,
#      quality, notes, expose_self, ...类型专属 }
# ═══════════════════════════════════════════════════════════════════

static func _result(sensor: Dictionary, kind: String) -> Dictionary:
	var r := {
		"sensor": String(sensor.get("model", "")),
		"maker": String(sensor.get("maker", "—")),
		"kind": kind,
		"detected": false,
		"pd": 0.0,
		"level_support": LEVEL_NONE,
		"produces_contact": true,
		"bearing_deg": -1.0,
		"bearing_sigma_deg": 180.0,
		"range_km": -1.0,
		"range_sigma_km": -1.0,
		"range_band": "",
		"band_ref_km": -1.0,
		"quality": 0.0,
		"notes": [],
		"expose_self": {},
	}
	# 主动照射类传感器：只要开机就在发射（是否被对方收到由 elint_intercept 判）。
	# 无线电 / 激光通信的发射由 comm_link(ctx.transmitting) 与 emission_state 单独判。
	var emission_class := _emission_class(sensor)
	if bool(sensor.get("expose", false)) and (emission_class == "radar" or emission_class == "iff" or emission_class == "lidar"):
		r["expose_self"] = emission_for(sensor)
	return r


static func _miss(sensor: Dictionary, kind: String, reason: String,
		extra: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, kind)
	r["reason"] = reason
	for raw_key in extra.keys():
		r[String(raw_key)] = extra[raw_key]
	return r


## 探测调度。type 取值：ir / radar / optical（含 lidar）/ iff / elint / radio / lasercom。
static func detect(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var t := String(sensor.get("type", ""))
	if t == "ir":
		return detect_ir(sensor, target, ctx)
	if t == "radar":
		return detect_radar(sensor, target, ctx)
	if t == "optical":
		if String(sensor.get("subtype", "")) == "lidar":
			return detect_lidar(sensor, target, ctx)
		return detect_optical(sensor, target, ctx)
	if t == "iff":
		return interrogate_iff(sensor, target, ctx)
	if t == "elint":
		return detect_elint(sensor, target, ctx)
	if t == "radio" or t == "lasercom":
		return comm_link(sensor, ctx)
	return _miss(sensor, "unknown", "unsupported_type:%s" % t)


## 本舰所有开机模块各判一次。返回 observation 数组（含 detected=false 的，方便调试）。
static func detect_all(ship_id: String, target: Dictionary, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for sensor in sensor_rack(ship_id):
		if not _sensor_on(sensor, ctx):
			continue
		out.append(detect(sensor, target, ctx))
	return out


## 05 §S-01：被动红外。给方位线 + 三档距离，不给距离解 → L1。
## 物理：300 K / 1,000 m² 基准下探测距离 = 型号标称（05 §S-01）；强度 ∝ T⁴·A，
## 探测距离 ∝ sqrt(强度)（SNR ∝ 1/R²）；阴影中热对比下降（05 §S-01 对抗：躲进阴影）。
static func detect_ir(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "ir")
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "ir", "no_geometry")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "ir", "occluded: 地球/月球遮挡（05 §S-01/S-02 对抗）")

	var contrast := ir_contrast(target, ctx)
	var eff_range := float(sensor.get("range_km", 120000.0)) * sqrt(contrast)
	var pd := detection_pd(range_km, eff_range, 2.0)
	r["pd"] = pd
	r["contrast"] = contrast

	if not roll(pd, ctx.get("rng")):
		if bool(ctx.get("enable_false_alarms", false)):
			var fa := maybe_false_alarm(sensor, ctx)
			if bool(fa.get("alarm", false)):
				r["detected"] = true
				r["phantom"] = true
				r["level_support"] = LEVEL_IR
				r["bearing_deg"] = float(fa.get("bearing_deg", 0.0))
				r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 1.2)) * 3.0
				r["range_band"] = "UNKNOWN"
				r["quality"] = 0.1
				r["notes"].append(String(fa.get("warning", "虚警")))
				r["notes"].append("IR 虚警：06 CH-IR2 常把残骸当敌舰")
				r["reason"] = "false_alarm"
				return r
		r["reason"] = "below_detection_threshold"
		return r

	r["detected"] = true
	r["level_support"] = LEVEL_IR
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 0.6))
	r["range_band"] = ir_range_band(range_km, eff_range, sensor.get("band_edges", [0.333, 0.667]))
	r["band_ref_km"] = eff_range
	r["quality"] = clampf(pd, 0.0, 1.0)
	r["notes"].append("IR 只给方位线、无距离解；距离只有远/中/近三档（05 §S-01）")
	if bearing >= 0.0:
		var prev_bearing := float(ctx.get("prev_bearing_deg", -1.0))
		var dt := float(ctx.get("prev_dt_s", 0.0))
		if prev_bearing >= 0.0 and dt > 0.0:
			var drift := bearing_drift_deg_per_s(prev_bearing, bearing, dt)
			r["bearing_drift_deg_per_s"] = drift
			r["motion_hint"] = motion_hint(drift)
	return r


## IR 热对比：300 K / 1,000 m² = 1.0（05 §S-01 数值基准）。
static func ir_contrast(target: Dictionary, ctx: Dictionary = {}) -> float:
	var temp_k := maxf(10.0, float(target.get("temp_k", 300.0)))
	var area_m2 := maxf(1.0, float(target.get("area_m2", 1000.0)))
	var contrast := pow(temp_k / 300.0, 4.0) * (area_m2 / 1000.0)
	if bool(ctx.get("shadow", false)):
		contrast *= 0.6   # [本文定值] 阴影里热对比下降，但不是零（05 §S-01 对抗）
	contrast *= float(ctx.get("ir_contrast_scale", 1.0))
	return clampf(contrast, 0.01, 100.0)


## 05 §S-02：主动雷达。给距离 + 方位 → L2；开机即暴露；按 R⁴ 与 RCS 缩放。
static func detect_radar(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "radar")
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "radar", "no_geometry")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "radar", "occluded: 地球临边/月球背面遮挡（05 §S-02 对抗）")

	var ref_rcs := float(sensor.get("ref_rcs_m2", 10.0))
	var rcs := maxf(0.01, float(target.get("rcs_m2", ref_rcs)))
	var jam := clampf(float(ctx.get("jamming", 0.0)), 0.0, 1.0)
	var resist := clampf(float(sensor.get("jamming_resist", 0.0)), 0.0, 1.0)
	var jam_factor := 1.0 - jam * (1.0 - JAMMED_RANGE_FACTOR) * (1.0 - resist)
	var rcs_factor := pow(rcs / ref_rcs, 0.25)
	var eff_range := float(sensor.get("range_km", 30000.0)) * rcs_factor * jam_factor
	var pd := detection_pd(range_km, eff_range, 4.0)
	r["pd"] = pd
	r["eff_range_km"] = eff_range

	if not roll(pd, ctx.get("rng")):
		r["reason"] = "below_detection_threshold"
		return r

	r["detected"] = true
	r["level_support"] = LEVEL_TRACK
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 0.15))
	var range_sigma := maxf(float(sensor.get("sigma_range_floor_km", 0.5)),
		range_km * float(sensor.get("sigma_range_frac", 0.0025)))
	var track_range_eff := float(sensor.get("track_range_km", 15000.0)) * rcs_factor * jam_factor
	var stable := range_km <= track_range_eff and pd >= 0.5
	if not stable:
		range_sigma *= 3.0   # 05 §S-02：15,000 km 外只有探测，没有稳定跟踪
	r["range_km"] = range_km
	r["range_sigma_km"] = range_sigma
	r["track_range_eff_km"] = track_range_eff
	r["stable_track"] = stable
	r["quality"] = clampf(pd * (1.0 if stable else 0.4), 0.0, 1.0)
	r["notes"].append("雷达给距离 + 方位 → L2（05 §S-02）")
	r["notes"].append("稳定跟踪 %d km / 探测 %d km（05 §S-02）" % [
		int(round(track_range_eff)), int(round(eff_range))])
	if jam > 0.0:
		r["notes"].append("噪声干扰：有效探测距离 ×%.2f（05 §E-01）" % jam_factor)
	return r


## 05 §S-03：光学。需光照 + 凝视时间；分类完成 → L3；阴影区不可见。
## ctx["stare_s"] = 该 (传感器, 目标) 已累积凝视秒数；返回 stare_s 供下一 tick 回填。
static func detect_optical(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "optical")
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "optical", "no_geometry")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "optical", "occluded: 被地球/月球遮挡（05 §S-03 对抗）")

	var illum := clampf(float(ctx.get("sun_illum", 1.0)), 0.0, 1.0)
	if illum < 0.05:
		return _miss(sensor, "optical", "shadow: 阴影区目标不可见（05 §S-03）",
			{"sun_illum": illum})

	var eff_range := float(sensor.get("range_km", 15000.0)) * sqrt(illum)
	var pd := detection_pd(range_km, eff_range, 2.0)
	r["pd"] = pd
	r["sun_illum"] = illum
	if not roll(pd, ctx.get("rng")):
		r["reason"] = "below_detection_threshold"
		return r

	r["detected"] = true
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 0.05))
	r["quality"] = clampf(pd, 0.0, 1.0)

	# 凝视：越久越清晰；中途大幅机动则重来（05 §S-03 缺陷）
	var prev_stare := maxf(0.0, float(ctx.get("stare_s", 0.0)))
	var refresh := float(sensor.get("refresh_s", 8.0))
	var maneuver := float(ctx.get("self_maneuver_g", 0.0))
	var reset_g := float(sensor.get("reset_maneuver_g", 0.02))
	var stare := prev_stare + refresh
	if maneuver > reset_g:
		stare = 0.0
		r["notes"].append("自舰大幅机动，凝视中断重来（05 §S-03 缺陷）")
	var required := optical_stare_s(sensor, range_km)
	r["stare_s"] = stare
	r["stare_required_s"] = required
	r["stare_progress"] = clampf(stare / maxf(1.0e-6, required), 0.0, 1.0)

	if stare >= required:
		r["level_support"] = LEVEL_CLASSIFY
		var cls: Dictionary = (target.get("classification", {}) as Dictionary).duplicate(true)
		cls["confidence"] = clampf(0.5 + 0.5 * r["stare_progress"], 0.0, 1.0)
		r["classification"] = cls
		r["notes"].append("光学凝视完成 → L3 分类（05 §S-03；05 §2.1 识别 40 s）")
	else:
		r["level_support"] = LEVEL_IR
		r["range_band"] = ""
		r["range_km"] = -1.0
		r["notes"].append("光学只给方位，凝视中 %.0f/%.0f s（05 §S-03）" % [stare, required])
	return r


## 光学凝视所需时间：05 §2.1 给出「8,000 km 识别需 40 s」。
## 角分辨率 ∝ 1/R，光子 ∝ 1/R² → 凝视时间按 (R/R_ref)² 缩放 [本文定值]。
static func optical_stare_s(sensor: Dictionary, range_km: float) -> float:
	var base := float(sensor.get("stare_s", 40.0))
	var ref_km := maxf(1.0, float(sensor.get("stare_ref_km", 8000.0)))
	return clampf(base * pow(range_km / ref_km, 2.0), 4.0, 240.0)


## 05 §S-04：激光测距（LR-4，optical 子型 lidar）。单目标精确距离 → 火控级；
## 需要已有方位；暴露微弱（对方激光告警机收到）。不提升等级（最高支撑 L2）。
static func detect_lidar(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "lidar")
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "lidar", "no_geometry")
	if not bool(ctx.get("has_bearing", true)):
		return _miss(sensor, "lidar", "no_pointing: 需要精确指向，先有方位（05 §S-04 缺陷）")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "lidar", "occluded")
	if range_km > float(sensor.get("range_km", 4000.0)):
		return _miss(sensor, "lidar", "out_of_range: LR-4 4,000 km（05 §S-04）")

	var pd := detection_pd(range_km, float(sensor.get("range_km", 4000.0)), 4.0)
	r["pd"] = pd
	if not roll(pd, ctx.get("rng")):
		r["reason"] = "below_detection_threshold"
		return r

	r["detected"] = true
	r["level_support"] = LEVEL_TRACK   # 只给火控级距离，不提升到 L3/L4
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 0.05))
	r["range_km"] = range_km
	r["range_sigma_km"] = float(sensor.get("sigma_range_km", 0.2))
	r["quality"] = clampf(pd, 0.0, 1.0)
	r["target_warning"] = "LWR：被激光测距照射（05 §S-04）"
	r["notes"].append("LR-4 将定位精度推到火控可用（05 §S-04；04 §12 归 optical 子型）")
	return r


## 05 §S-06：IFF 2,000 km。应答正确 → L4；不应答 ≠ 敌意（永不自动判敌）。
## produces_contact=false：IFF 不能凭空产生位置，只能给已有接触补身份。
static func interrogate_iff(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "iff")
	r["produces_contact"] = false
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "iff", "no_geometry")
	if range_km > float(sensor.get("range_km", 2000.0)):
		return _miss(sensor, "iff", "out_of_range: IFF 2,000 km 有效（05 §S-06）")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "iff", "occluded")

	r["detected"] = true            # 询问动作成立（无论应答与否）
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 1.0))

	var transponder := String(target.get("transponder", "off"))
	var code := String(target.get("iff_code", ""))
	var allied: Array = ctx.get("allied_codes", ALLIED_CODES)
	var status := "no_reply"
	var matched := _iff_code_matches(code, allied)

	if transponder == "off":
		status = "no_reply"
		r["notes"].append("应答机关闭")
	elif transponder == "faulty":
		status = "faulty_transponder"
		r["notes"].append("应答机故障（07 §2 谷神-2：「不明」是坏掉的友舰）")
	elif transponder == "ok" or transponder == "captured":
		if matched:
			status = "friend"
			r["level_support"] = LEVEL_IDENTITY
			r["identity"] = {
				"name": String(target.get("name", "")),
				"hull": String((SHIPS.get(String(target.get("id", "")), {}) as Dictionary).get("hull", "")),
				"faction": String(target.get("faction", "")),
				"via": "iff",
				"confidence": 0.5 if transponder == "captured" else 0.9,
			}
			if transponder == "captured":
				r["notes"].append("缴获应答码：应答正确不等于友军（05 §S-06 对抗）")
		else:
			status = "wrong_code"
	else:
		status = "no_reply"

	r["iff_status"] = status
	r["code_matched"] = matched
	if status != "friend":
		r["notes"].append("不明 ≠ 敌意：可能是一艘关掉应答机的友舰（05 §S-06；07 §1）")
		r["warning"] = "不明 ≠ 敌意"
	return r


static func _iff_code_matches(code: String, prefixes: Array) -> bool:
	if code.is_empty():
		return false
	for raw in prefixes:
		var prefix := String(raw)
		if prefix.is_empty():
			continue
		if code == prefix or code.begins_with(prefix):
			return true
	return false


## 05 §S-05：ELINT。出「信号」不出「接触」：方位 + 特征码；对方静默时收不到。
## produces_contact=false；匹配特征库可推断舰级（支撑 L3/L4，05 §附录 B）。
static func detect_elint(sensor: Dictionary, target: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r := _result(sensor, "elint")
	r["produces_contact"] = false
	var range_km := float(target.get("range_km", -1.0))
	var bearing := float(target.get("bearing_deg", 0.0))
	if range_km < 0.0:
		return _miss(sensor, "elint", "no_geometry")
	if not bool(ctx.get("los", true)):
		return _miss(sensor, "elint", "occluded")

	var emissions: Array = target.get("emissions", [])
	if emissions.is_empty():
		return _miss(sensor, "elint", "no_emission: 对方静默时什么都收不到（05 §S-05 缺陷）")

	var hits: Array = []
	var best: Dictionary = {}
	var best_pd := -1.0
	for raw in emissions:
		var em: Dictionary = raw
		if not bool(em.get("on", false)):
			continue
		var etype := String(em.get("type", ""))
		var factor := float(ELINT_INTERCEPT_FACTOR.get(etype, 0.0))
		if factor <= 0.0:
			continue
		var base_range := float(em.get("range_km", 0.0))
		if base_range <= 0.0:
			base_range = float((SENSOR_LIBRARY.get(String(em.get("model", "")), {}) as Dictionary).get("range_km", 0.0))
		var lpi := bool(em.get("lpi", false))
		var intercept_range := base_range * factor * (LPI_INTERCEPT_MULT if lpi else 1.0)
		if intercept_range <= 0.0 or range_km > intercept_range:
			continue
		var pd := detection_pd(range_km, intercept_range, 2.0)
		if not roll(pd, ctx.get("rng")):
			continue
		var model := String(em.get("model", ""))
		hits.append({"model": model, "type": etype, "pd": pd, "intercept_range_km": intercept_range})
		if pd > best_pd:
			best_pd = pd
			best = hits[hits.size() - 1]

	if hits.is_empty():
		return _miss(sensor, "elint", "no_emission_in_range: 对方未发射或超出截获距离（05 §S-05）")

	r["detected"] = true
	r["bearing_deg"] = bearing
	r["bearing_sigma_deg"] = float(sensor.get("sigma_bearing_deg", 1.0))
	r["range_km"] = -1.0
	r["quality"] = clampf(best_pd, 0.0, 1.0)

	var signature := String(best.get("model", ""))
	var matched: Dictionary = ((SIGNATURE_DB.get(signature, {}) as Dictionary).duplicate(true))
	r["signal"] = {
		"signature": signature,
		"emitter_type": String(best.get("type", "")),
		"matched": matched,
		"signatures": hits,           # 可能同时截到多个发射源（05 §S-05：发射最多的就是指挥舰）
		"bearing_only": true,
		"produces_contact": false,
	}
	var support := int(matched.get("level_support", LEVEL_TRACK))
	r["level_support"] = support
	r["identity_hint"] = matched
	r["notes"].append("ELINT 出「信号」不出「接触」：需与已有航迹按方位相关（05 §S-05）")
	if not matched.is_empty():
		r["notes"].append("特征码 %s → %s（置信 %.1f）" % [
			signature, String(matched.get("class_hint", "未知")), float(matched.get("confidence", 0.0))])
	return r


## 通信链路（不产生探测/等级）。06 §4.3：激光 0.5/1 s、无线电 4 s；
## 05 §C-01：激光需要视线；05 §E-03：通信干扰可把命令延迟拉到 40 s。
static func comm_link(sensor: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var t := String(sensor.get("type", "comm"))
	var r := _result(sensor, t)
	r["produces_contact"] = false
	r["level_support"] = LEVEL_NONE
	var los := bool(ctx.get("los", true))
	var need_los := bool(sensor.get("los_required", false))
	var ok := true
	if need_los and not los:
		ok = false
		r["reason"] = "no_line_of_sight: 被遮挡就断（05 §C-01）"
	var latency := float(sensor.get("latency_s", 0.0))
	if t == "radio":
		var jam := clampf(float(ctx.get("comms_jamming", 0.0)), 0.0, 1.0)
		latency = lerp(latency, 40.0, jam)   # 05 §E-03：2 s → 40 s
	r["detected"] = ok
	r["quality"] = 1.0 if ok else 0.0
	r["link"] = {
		"ok": ok,
		"latency_s": latency,
		"los_required": need_los,
		"relay_capable": bool(sensor.get("relay_capable", false)),
	}
	if bool(ctx.get("transmitting", false)):
		r["expose_self"] = emission_for(sensor)
	return r


# ═══════════════════════════════════════════════════════════════════
# 9. 航迹融合 / 等级 / 衰减 / 协方差（05 §S-07）
# ═══════════════════════════════════════════════════════════════════

static func new_track(track_id: String, t: float) -> Dictionary:
	return {
		"id": track_id,
		"level": LEVEL_IR,
		"level_max_seen": LEVEL_IR,
		"level_evidence": {},
		"bearing_deg": -1.0,
		"bearing_sigma_deg": 180.0,
		"range_km": -1.0,
		"range_sigma_km": -1.0,
		"range_band": "",
		"band_ref_km": -1.0,
		"radial_vel_kmps": 0.0,
		"radial_vel_sigma_kmps": -1.0,
		"first_seen_t": t,
		"last_update_t": t,
		"last_bearing_t": -1.0,
		"last_range_t": -1.0,
		"age_s": 0.0,
		"stale": false,
		"sources": [],
		"classification": {},
		"identity": {},
		"iff_status": "",
		"signal": {},
		"covariance": {},
		"notes": [],
	}


## 融合一批 observation 进航迹。返回新字典（不原地改入参）。
## 05 §S-07：批号、等级、方位、距离、协方差、最后更新时刻；融合周期 1 s（调用方按 1 s 调）。
static func update_track(track: Dictionary, observations: Array, t: float,
		opts: Dictionary = {}) -> Dictionary:
	var had_track := not track.is_empty()
	var tr: Dictionary = track.duplicate(true) if had_track else new_track(String(opts.get("track_id", "UNKNOWN")), t)

	var bearing_x := 0.0
	var bearing_y := 0.0
	var bearing_w := 0.0
	var range_sum := 0.0
	var range_w := 0.0
	var evidence_updates: Array = []
	var sources: Array = tr.get("sources", [])
	var any_update := false

	for raw in observations:
		var obs: Dictionary = raw
		if not bool(obs.get("detected", false)):
			continue
		var support := int(obs.get("level_support", LEVEL_NONE))
		var produces := bool(obs.get("produces_contact", true))
		var can_support := produces or had_track

		# 身份 / 分类 / 信号：即使不产生接触也可以补到已有航迹上
		if obs.has("classification") and not (obs.get("classification") as Dictionary).is_empty():
			tr["classification"] = (obs.get("classification") as Dictionary).duplicate(true)
		if obs.has("identity") and not (obs.get("identity") as Dictionary).is_empty():
			tr["identity"] = (obs.get("identity") as Dictionary).duplicate(true)
		if obs.has("iff_status"):
			tr["iff_status"] = String(obs.get("iff_status", ""))
		if obs.has("signal") and not (obs.get("signal") as Dictionary).is_empty():
			tr["signal"] = (obs.get("signal") as Dictionary).duplicate(true)
			# 05 §附录 B：信号指纹可作为 L4 的达成手段之一（由特征库给出支撑级）
			support = maxi(support, int(obs.get("level_support", LEVEL_NONE)))

		if produces:
			any_update = true
			var obs_bearing := float(obs.get("bearing_deg", -1.0))
			if obs_bearing >= 0.0:
				var sigma_b := maxf(0.01, float(obs.get("bearing_sigma_deg", 1.0)))
				var w := 1.0 / (sigma_b * sigma_b)
				var br := deg_to_rad(obs_bearing)
				bearing_x += w * cos(br)
				bearing_y += w * sin(br)
				bearing_w += w
				tr["last_bearing_t"] = t
			var obs_range := float(obs.get("range_km", -1.0))
			var obs_rs := float(obs.get("range_sigma_km", -1.0))
			if obs_range >= 0.0 and obs_rs > 0.0:
				var rw := 1.0 / (obs_rs * obs_rs)
				range_sum += rw * obs_range
				range_w += rw
				tr["last_range_t"] = t
			var band := String(obs.get("range_band", ""))
			if not band.is_empty():
				tr["range_band"] = band
				tr["band_ref_km"] = float(obs.get("band_ref_km", -1.0))
			if obs.has("radial_vel_kmps"):
				tr["radial_vel_kmps"] = float(obs.get("radial_vel_kmps", 0.0))
				tr["radial_vel_sigma_kmps"] = float(obs.get("radial_vel_sigma_kmps", -1.0))

		if support > LEVEL_NONE and can_support:
			evidence_updates.append(support)
			var model := String(obs.get("sensor", ""))
			if not model.is_empty() and not sources.has(model):
				sources.append(model)
			any_update = true

	# 融合位置（反方差加权）
	if bearing_w > 0.0:
		var mean_angle := atan2(bearing_y, bearing_x)
		tr["bearing_deg"] = fposmod(rad_to_deg(mean_angle), 360.0)
		tr["bearing_sigma_deg"] = sqrt(1.0 / bearing_w)
	if range_w > 0.0:
		tr["range_km"] = range_sum / range_w
		tr["range_sigma_km"] = sqrt(1.0 / range_w)
		tr["range_band"] = ""
		tr["band_ref_km"] = -1.0

	# 证据时间戳：支撑级 S 的观测同时刷新 1..S 全部下级证据（身份隐含分类与定位）
	var evidence: Dictionary = tr.get("level_evidence", {})
	for raw_support in evidence_updates:
		var support := int(raw_support)
		for level in range(LEVEL_IR, support + 1):
			evidence[level] = t
	tr["level_evidence"] = evidence

	if any_update:
		tr["last_update_t"] = t
		tr["age_s"] = 0.0
		tr["stale"] = false
		if float(tr.get("first_seen_t", t)) > t:
			tr["first_seen_t"] = t

	tr["sources"] = sources
	tr["level"] = level_from_evidence(evidence, t)
	tr["level_max_seen"] = maxi(int(tr.get("level_max_seen", LEVEL_IR)), int(tr["level"]))
	tr["covariance"] = covariance_at(tr, t)
	return tr


## 05 §S-07「逐级降级 L4→L3→L2→L1」：由各级证据的年龄推出当前等级。
static func level_from_evidence(evidence: Dictionary, now_t: float) -> int:
	var level := LEVEL_IR   # 有航迹 = 至少 L1（05 §S-07：失去跟踪不删除）
	for lv in [LEVEL_TRACK, LEVEL_CLASSIFY, LEVEL_IDENTITY]:
		if not evidence.has(lv):
			continue
		var last_t := float(evidence[lv])
		var valid := float(LEVEL_VALID_S.get(lv, 0.0))
		if now_t - last_t <= valid:
			level = maxi(level, int(lv))
	return level


## 05 §S-07：丢失刷新后标记陈旧；协方差椭圆随时间变大（不确定性可以被画出来）。
static func age_track(track: Dictionary, now_t: float, opts: Dictionary = {}) -> Dictionary:
	if track.is_empty():
		return track
	var tr: Dictionary = track.duplicate(true)
	var last_t := float(tr.get("last_update_t", now_t))
	var age := maxf(0.0, now_t - last_t)
	tr["age_s"] = age
	tr["level"] = level_from_evidence(tr.get("level_evidence", {}), now_t)
	tr["stale"] = age > float(opts.get("stale_after_s", STALE_AFTER_S))
	tr["retire_hint"] = age > float(opts.get("memory_keep_s", MEMORY_KEEP_S))
	tr["covariance"] = covariance_at(tr, now_t)
	return tr


static func fuse(track: Dictionary, observations: Array, t: float,
		opts: Dictionary = {}) -> Dictionary:
	return update_track(track, observations, t, opts)


## 位置不确定性：方位 σ 经距离换成横向误差；距离 σ 为径向误差；
## 丢失刷新后按 0.1 g 未知加速度增长（[本文定值]，量级取 04 §8 机动基线）。
static func covariance_at(track: Dictionary, now_t: float) -> Dictionary:
	var bearing_sigma := maxf(0.01, float(track.get("bearing_sigma_deg", 180.0)))
	var bearing_deg := float(track.get("bearing_deg", -1.0))
	var range_km := float(track.get("range_km", -1.0))
	var range_sigma := float(track.get("range_sigma_km", -1.0))
	var last_bearing_t := float(track.get("last_bearing_t", track.get("last_update_t", now_t)))
	var last_range_t := float(track.get("last_range_t", track.get("last_update_t", now_t)))
	var last_t := float(track.get("last_update_t", now_t))
	if last_bearing_t < 0.0:
		last_bearing_t = last_t
	if last_range_t < 0.0:
		last_range_t = last_t
	var age_b := maxf(0.0, now_t - last_bearing_t)
	var age_r := maxf(0.0, now_t - last_range_t)
	var growth_b := 0.5 * TARGET_ACCEL_KMPS2 * age_b * age_b
	var growth_r := 0.5 * TARGET_ACCEL_KMPS2 * age_r * age_r

	var cross_km := 0.0
	var radial_km := 0.0
	var has_position := false
	if range_km >= 0.0 and bearing_deg >= 0.0:
		cross_km = range_km * deg_to_rad(bearing_sigma) + growth_b
		radial_km = maxf(0.0, range_sigma) + growth_r
		has_position = true
	elif bearing_deg >= 0.0 and range_km < 0.0:
		# 仅方位（L1）：用 IR 三档的档位宽度当径向不确定度
		var band_ref := float(track.get("band_ref_km", -1.0))
		if band_ref > 0.0:
			radial_km = band_ref / 6.0 + growth_r   # 三档各占 1/3，半宽 1/6 [本文定值]
		else:
			radial_km = 100000.0
		cross_km = 100000.0 * deg_to_rad(bearing_sigma) + growth_b
		has_position = false

	var pos_sigma := 0.0
	if has_position:
		pos_sigma = sqrt(cross_km * cross_km + radial_km * radial_km)
	else:
		pos_sigma = sqrt(cross_km * cross_km + radial_km * radial_km)

	return {
		"bearing_sigma_deg": bearing_sigma,
		"range_sigma_km": range_sigma,
		"cross_sigma_km": cross_km,
		"radial_sigma_km": radial_km,
		"pos_sigma_km": pos_sigma,
		"semi_major_km": maxf(cross_km, radial_km),
		"semi_minor_km": minf(cross_km, radial_km),
		"has_position": has_position,
		"growth_km": maxf(growth_b, growth_r),
		"age_s": maxf(0.0, now_t - last_t),
	}


# ═══════════════════════════════════════════════════════════════════
# 10. 自测（headless 可跑；见文件末尾注释命令）
# ═══════════════════════════════════════════════════════════════════

static func _check(ok: bool, cond: bool, label: String, detail: String = "") -> bool:
	if cond:
		print("[PASS] ", label, ("  " + detail) if not detail.is_empty() else "")
	else:
		print("[FAIL] ", label, ("  " + detail) if not detail.is_empty() else "")
	return ok and cond


static func _count_sensors() -> int:
	var n := 0
	for ship_id in all_racks().keys():
		n += (all_racks()[ship_id] as Array).size()
	return n


## 返回 true = 全部通过；同时打印 [REPORT] 行证明 API 能返回 等级/暴露/误差。
static func run_self_test() -> bool:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var ctx: Dictionary = {"rng": rng, "los": true, "sun_illum": 1.0}
	print("==== SensorModel self-test · GHOST TRACK / APSIS ====")
	print("[SRC] 05 §3 / 06 §4.3 / 07 §1 / 01 §5 / 02 §8·§9.2 / 04 §12 / 10 §7.3·§10.1")

	# ── 1. 按舰架 schema ─────────────────────────────────────────
	var errors := validate_racks()
	ok = _check(ok, errors.is_empty(), "rack_schema",
		"ships=%d sensors=%d errors=%d" % [all_racks().size(), _count_sensors(), errors.size()])
	if not errors.is_empty():
		for e in errors:
			print("[SCHEMA] ", e)
	ok = _check(ok, rack_models("harmattan") == ["YW-R9", "MS-OT2", "CH-IR2", "ELINT", "CH-R0"],
		"19 §6 rack: 哈马丹 = YW-R9 + MS-OT2 + CH-IR2 + ELINT + CH-R0", str(rack_models("harmattan")))
	ok = _check(ok, rack_models("apsis").has("MS-IR9"),
		"07 rack: 远地点带 MS-IR9", str(rack_models("apsis")))
	ok = _check(ok, rack_models("watchtower").has("MS-L2"),
		"07 rack: 望楼带激光通信 MS-L2", str(rack_models("watchtower")))
	ok = _check(ok, rack_models("summons_4471").has("ELINT"),
		"07 rack: 传唤级带 ELINT", str(rack_models("summons_4471")))
	var required_models := ["MS-IR9", "NO-IR7", "YW-IR5", "CH-IR2",
		"YW-R9", "KD-R6", "MS-R4", "SC-R2", "MK-12", "LR-4", "CH-R0", "MS-L2", "YW-L1"]
	var missing_models: Array = []
	for model in required_models:
		if not SENSOR_LIBRARY.has(model):
			missing_models.append(model)
	ok = _check(ok, missing_models.is_empty(), "型号库覆盖 05/06 要求型号（含 NO-IR7 / KD-R6）",
		"models=%d missing=%s" % [SENSOR_LIBRARY.size(), str(missing_models)])

	# ── 2. 被动红外：方位线 + 三档 + 无距离 → L1（05 §S-01）──────
	var ceres := target_from_ship("ceres_2", 8000.0, 47.0, {"temp_k": 300.0, "area_m2": 1000.0})
	var ch_ir2 := rack_sensor("harmattan", "CH-IR2")
	var ms_ir9 := rack_sensor("apsis", "MS-IR9")
	var ir_low := detect_ir(ch_ir2, ceres, ctx)
	var ir_high := detect_ir(ms_ir9, ceres, ctx)
	ok = _check(ok, bool(ir_low.get("detected", false)), "IR CH-IR2 @8,000 km 发现",
		"pd=%.3f band=%s" % [float(ir_low.get("pd", 0.0)), String(ir_low.get("range_band", ""))])
	ok = _check(ok, int(ir_low.get("level_support", 0)) == LEVEL_IR, "IR → L1")
	ok = _check(ok, float(ir_low.get("range_km", 0.0)) < 0.0,
		"IR 不给距离（05 §S-01）", "range=%.1f band=%s" % [
			float(ir_low.get("range_km", -1.0)), String(ir_low.get("range_band", ""))])
	ok = _check(ok, float(ir_high.get("bearing_sigma_deg", 99.0)) < float(ir_low.get("bearing_sigma_deg", 99.0)),
		"MS-IR9 测向优于 CH-IR2", "σ %.2f° < %.2f°" % [
			float(ir_high.get("bearing_sigma_deg", 0.0)), float(ir_low.get("bearing_sigma_deg", 0.0))])

	# ── 3. 雷达：距离 + 方位 → L2 + 开机暴露（05 §S-02）───────────
	var summons := target_from_ship("summons_4471", 8000.0, 41.0, {"rcs_m2": 10.0})
	var radar_obs := detect_radar(rack_sensor("harmattan", "YW-R9"), summons, ctx)
	ok = _check(ok, bool(radar_obs.get("detected", false))
		and int(radar_obs.get("level_support", 0)) == LEVEL_TRACK,
		"雷达 → L2（距离+方位）", "range=%.0f km σr=%.2f km stable=%s" % [
			float(radar_obs.get("range_km", -1.0)),
			float(radar_obs.get("range_sigma_km", -1.0)),
			str(radar_obs.get("stable_track", false))])
	ok = _check(ok, bool(radar_obs.get("stable_track", false)),
		"8,000 km < 15,000 km 稳定跟踪（05 §S-02）")
	var em_radar := emission_for(rack_sensor("harmattan", "YW-R9"))
	ok = _check(ok, bool(radar_obs.get("expose_self", {}).size() > 0) and not em_radar.is_empty(),
		"雷达开机即暴露：observation 带 expose_self", "ELINT %.0f km" % float(em_radar.get("elint_range_km", 0.0)))
	var far_obs := detect_radar(rack_sensor("harmattan", "YW-R9"),
		target_from_ship("summons_4471", 20000.0, 41.0, {"rcs_m2": 10.0}), ctx)
	ok = _check(ok, bool(far_obs.get("detected", false)) and not bool(far_obs.get("stable_track", true)),
		"20,000 km 探测到但无稳定跟踪（05 §S-02）")

	# ── 3b. 激光测距 LR-4（05 §S-04；04 §12：optical 子型 lidar）────
	var lidar := rack_sensor("ferry", "LR-4")
	var near_summons := target_from_ship("summons_4471", 3000.0, 41.0, {"rcs_m2": 10.0})
	var lidar_obs := detect_lidar(lidar, near_summons, ctx)
	ok = _check(ok, bool(lidar_obs.get("detected", false))
		and int(lidar_obs.get("level_support", 0)) == LEVEL_TRACK
		and absf(float(lidar_obs.get("range_sigma_km", -1.0)) - 0.2) < 0.001,
		"LR-4 精确距离（σ=0.2 km）→ 火控级 L2",
		"range=%.0f km σ=%.2f km" % [
			float(lidar_obs.get("range_km", -1.0)), float(lidar_obs.get("range_sigma_km", -1.0))])
	ok = _check(ok, String(lidar_obs.get("target_warning", "")).contains("LWR")
		and String((lidar_obs.get("expose_self", {}) as Dictionary).get("kind", "")) == "lwr",
		"LR-4 暴露 = 激光告警机可收到（05 §S-04）",
		"kind=%s" % String((lidar_obs.get("expose_self", {}) as Dictionary).get("kind", "")))
	ok = _check(ok, not bool(detect_lidar(lidar, summons, ctx).get("detected", true)),
		"LR-4 4,000 km 外无效（05 §S-04）")
	var no_point_ctx: Dictionary = ctx.duplicate(true)
	no_point_ctx["has_bearing"] = false
	ok = _check(ok, not bool(detect_lidar(lidar, near_summons, no_point_ctx).get("detected", true)),
		"LR-4 需要精确指向（05 §S-04 缺陷）")
	var em_lidar := emission_for(lidar)
	ok = _check(ok, not em_lidar.is_empty()
		and float(em_lidar.get("elint_range_km", -1.0)) == 0.0,
		"LR-4 被 ELINT 截获距离 = 0（只有 LWR；05 §S-04）",
		"kind=%s weight=%.2f" % [String(em_lidar.get("kind", "")), float(em_lidar.get("weight", 0.0))])
	var kd := _make_sensor({"model": "KD-R6"}, "测试")
	var em_kd := emission_for(kd)
	var em_yw := emission_for(rack_sensor("harmattan", "YW-R9"))
	ok = _check(ok, float(em_kd.get("elint_range_km", 0.0)) < float(em_yw.get("elint_range_km", 0.0))
		and float(em_kd.get("fix_after_s", 0.0)) > float(em_yw.get("fix_after_s", 0.0)),
		"KD-R6 低截获概率：更难被定位（06 §4.3）",
		"ELINT %.0f km / fix %.0f s" % [
			float(em_kd.get("elint_range_km", 0.0)), float(em_kd.get("fix_after_s", 0.0))])

	# ── 4. 暴露 / EMCON（05 §S-02 / §S-06 / §C-02）────────────────
	var ex_on := emission_state("harmattan", {
		"on": {"YW-R9": true, "MS-IR9": false, "MS-OT2": false, "MK-12": false, "ELINT": false},
		"seconds_on": {"YW-R9": 25.0},
	})
	ok = _check(ok, bool(ex_on.get("exposed", false)) and float(ex_on.get("emission_level", 0.0)) >= 0.99,
		"exposure_state：雷达开 = 暴露 1.0", "emission_level=%.2f" % float(ex_on.get("emission_level", 0.0)))
	var ex_ite: Dictionary = (ex_on.get("emitters", [{}]) as Array)[0]
	var fix25: Dictionary = ex_ite.get("fix", {})
	ok = _check(ok, bool(fix25.get("fixed", false)),
		"ELINT 25 s 后可定位（20 s 阈值）", "fix_after=%.0fs σ=%.2f°" % [
			float(fix25.get("fix_after_s", 0.0)), float(fix25.get("bearing_sigma_deg", 0.0))])
	var itc := elint_intercept(em_radar, 8000.0, 25.0, ctx)
	ok = _check(ok, bool(itc.get("detected", false)) and String(itc.get("model_recorded", "")) == "YW-R9",
		"对方 ELINT 截获并记录型号（05 §S-02）", "immediate=%s" % str(itc.get("immediate", false)))
	var ex_passive := emission_state("harmattan", {"on": {"CH-IR2": true, "CH-R0": false}})
	ok = _check(ok, not bool(ex_passive.get("exposed", true)), "被动红外不暴露（05 §S-01）")
	var ex_radio := emission_state("harmattan", {
		"on": {"CH-IR2": true, "CH-R0": true}, "transmitting": ["CH-R0"]})
	ok = _check(ok, bool(ex_radio.get("exposed", false)), "无线电发射暴露（05 §C-02）",
		"emission_level=%.2f" % float(ex_radio.get("emission_level", 0.0)))

	# ── 5. 光学：凝视 + 光照 → L3；阴影不可见（05 §S-03）──────────
	var optical := rack_sensor("apsis", "MS-OT2")
	var octx: Dictionary = ctx.duplicate(true)
	var o_first := detect_optical(optical, ceres, octx)
	ok = _check(ok, int(o_first.get("level_support", 0)) == LEVEL_IR,
		"光学首帧只给方位（凝视中）", "stare=%.0f/%.0f s" % [
			float(o_first.get("stare_s", 0.0)), float(o_first.get("stare_required_s", 0.0))])
	var stare := 0.0
	var o_last: Dictionary = {}
	for i in range(5):
		octx["stare_s"] = stare
		o_last = detect_optical(optical, ceres, octx)
		stare = float(o_last.get("stare_s", 0.0))
	ok = _check(ok, int(o_last.get("level_support", 0)) == LEVEL_CLASSIFY,
		"光学凝视 40 s → L3", "stare=%.0f s class=%s" % [
			stare, String((o_last.get("classification", {}) as Dictionary).get("ship_class", ""))])
	var shadow_ctx: Dictionary = ctx.duplicate(true)
	shadow_ctx["sun_illum"] = 0.0
	var o_shadow := detect_optical(optical, ceres, shadow_ctx)
	ok = _check(ok, not bool(o_shadow.get("detected", true)), "阴影区光学不可见（05 §S-03）")

	# ── 6. IFF：正确应答 → L4；故障/关闭 ≠ 敌意（05 §S-06）────────
	var iff := rack_sensor("apsis", "MK-12")
	var iff_friend := interrogate_iff(iff, target_from_ship("harmattan", 1800.0, 12.0), ctx)
	ok = _check(ok, int(iff_friend.get("level_support", 0)) == LEVEL_IDENTITY
		and String((iff_friend.get("identity", {}) as Dictionary).get("name", "")) == "哈马丹",
		"IFF 正确应答 → L4 友军", String(iff_friend.get("iff_status", "")))
	var iff_faulty := interrogate_iff(iff, target_from_ship("ceres_2", 1800.0, 118.0), ctx)
	ok = _check(ok, int(iff_faulty.get("level_support", 0)) == LEVEL_NONE
		and String(iff_faulty.get("warning", "")).contains("不明"),
		"应答机故障 → 不明，不自动判敌（07 §1）", String(iff_faulty.get("iff_status", "")))
	var iff_far := interrogate_iff(iff, target_from_ship("ferry", 8000.0, 332.0), ctx)
	ok = _check(ok, not bool(iff_far.get("detected", true)), "IFF 2,000 km 外无效（05 §S-06）")

	# ── 7. ELINT：方位 + 信号指纹，不出接触（05 §S-05）─────────────
	var elint := rack_sensor("apsis", "ELINT")
	var summons_emit := target_from_ship("summons_4471", 8000.0, 41.0, {"emissions": [{
		"model": "YW-R9", "type": "radar", "on": true, "range_km": 30000.0, "lpi": false}]})
	var sig := detect_elint(elint, summons_emit, ctx)
	ok = _check(ok, bool(sig.get("detected", false))
		and not bool(sig.get("produces_contact", true))
		and String((sig.get("signal", {}) as Dictionary).get("signature", "")) == "YW-R9",
		"ELINT 信号：方位 + YW-R9 指纹，不出接触",
		"level_support=%d" % int(sig.get("level_support", 0)))
	var silent := target_from_ship("ceres_2", 8000.0, 47.0, {"emissions": []})
	var sig_none := detect_elint(elint, silent, ctx)
	ok = _check(ok, not bool(sig_none.get("detected", true)), "ELINT 对静默目标无信号（05 §S-05）")

	# ── 8. 融合 + 等级衰减 L4→L3→L2→L1 + 协方差（05 §S-07）───────
	var ferry := target_from_ship("ferry", 8000.0, 332.0, {"rcs_m2": 10.0})
	var tr := update_track({}, [detect_ir(ms_ir9, ferry, ctx)], 0.0, {"track_id": "T-1"})
	var lv1 := int(tr.get("level", 0))
	tr = update_track(tr, [detect_radar(rack_sensor("harmattan", "YW-R9"), ferry, ctx)], 10.0)
	var lv2 := int(tr.get("level", 0))
	var octx2: Dictionary = ctx.duplicate(true)
	octx2["stare_s"] = 40.0
	tr = update_track(tr, [detect_optical(optical, ferry, octx2)], 20.0)
	var lv3 := int(tr.get("level", 0))
	tr = update_track(tr, [interrogate_iff(iff, target_from_ship("ferry", 1800.0, 332.0), ctx)], 30.0)
	var lv4 := int(tr.get("level", 0))
	ok = _check(ok, lv1 == LEVEL_IR and lv2 == LEVEL_TRACK and lv3 == LEVEL_CLASSIFY and lv4 == LEVEL_IDENTITY,
		"融合等级 L1→L2→L3→L4", "%d→%d→%d→%d" % [lv1, lv2, lv3, lv4])
	var aged31 := age_track(tr, 61.0)
	var aged91 := age_track(tr, 121.0)
	var aged211 := age_track(tr, 241.0)
	ok = _check(ok, int(aged31.get("level", 0)) == LEVEL_CLASSIFY
		and int(aged91.get("level", 0)) == LEVEL_TRACK
		and int(aged211.get("level", 0)) == LEVEL_IR,
		"等级衰减 L4→L3→L2→L1（+31/+91/+211 s）", "%d→%d→%d" % [
			int(aged31.get("level", 0)), int(aged91.get("level", 0)), int(aged211.get("level", 0))])
	ok = _check(ok, bool(aged31.get("stale", false)), "失去刷新 → 陈旧（05 §S-07）")
	var cov_now: Dictionary = tr.get("covariance", {})
	var cov_late: Dictionary = aged91.get("covariance", {})
	ok = _check(ok, float(cov_late.get("pos_sigma_km", 0.0)) > float(cov_now.get("pos_sigma_km", 0.0)),
		"协方差随时间变大（05 §S-07）", "σpos %.1f → %.1f km" % [
			float(cov_now.get("pos_sigma_km", 0.0)), float(cov_late.get("pos_sigma_km", 0.0))])

	# ── 9. 双平台三角测量 → L2（01 §5.1 / 04 §2.3）────────────────
	var tri := triangulate(Vector2(0.0, 0.0), 45.0, 0.5, Vector2(200.0, 0.0), 315.0, 0.5)
	ok = _check(ok, bool(tri.get("ok", false))
		and absf(float(tri.get("range_km", 0.0)) - 141.42) < 1.0
		and int(tri.get("level_support", 0)) == LEVEL_TRACK,
		"双平台方位交叉 → L2 定位", "range=%.1f km σ=%.2f km angle=%.0f°" % [
			float(tri.get("range_km", 0.0)), float(tri.get("sigma_range_km", 0.0)),
			float(tri.get("angle_deg", 0.0))])

	# ── 10. 遮挡 / 探测概率 / 通信 ────────────────────────────────
	ok = _check(ok, not line_of_sight_ok(Vector3(0.0, 0.0, 6778.0), Vector3(0.0, 0.0, -6778.0)),
		"地球遮挡判定（05 §S-02/S-03 对抗）")
	ok = _check(ok, line_of_sight_ok(Vector3(6778.0, 0.0, 0.0), Vector3(14000.0, 0.0, 0.0)),
		"无遮挡判定")
	ok = _check(ok, absf(detection_pd(30000.0, 30000.0, 4.0) - 0.5) < 0.02,
		"Pd(R_ref)=0.5（01 §5.3）")
	ok = _check(ok, detection_pd(60000.0, 30000.0, 4.0) < 0.2, "R⁴ 衰减（01 §5.3）")
	var laser := comm_link(rack_sensor("watchtower", "MS-L2"), ctx)
	ok = _check(ok, bool((laser.get("link", {}) as Dictionary).get("ok", false))
		and absf(float((laser.get("link", {}) as Dictionary).get("latency_s", 0.0)) - 0.5) < 0.01,
		"望楼激光通信 0.5 s（06 §4.3）")
	var no_los_ctx: Dictionary = ctx.duplicate(true)
	no_los_ctx["los"] = false
	var laser_blocked := comm_link(rack_sensor("watchtower", "MS-L2"), no_los_ctx)
	ok = _check(ok, not bool((laser_blocked.get("link", {}) as Dictionary).get("ok", true)),
		"激光通信被遮挡即断（05 §C-01）")

	# ── 11. REPORT：证明 API 能返回 等级 / 暴露 / 误差 ─────────────
	var report_track: Dictionary = update_track(tr, [
		detect_radar(rack_sensor("harmattan", "YW-R9"), ferry, ctx),
		interrogate_iff(iff, target_from_ship("ferry", 1800.0, 332.0), ctx),
	], 40.0)
	print("[REPORT] level: %d · %s · caps=%s" % [
		int(report_track.get("level", 0)), level_label(int(report_track.get("level", 0))),
		str(level_caps(int(report_track.get("level", 0))))])
	print("[REPORT] identity: ", JSON.stringify(report_track.get("identity", {})))
	print("[REPORT] exposure: ", JSON.stringify(ex_on))
	print("[REPORT] error/cov: ", JSON.stringify(covariance_at(report_track, 100.0)))
	print("[REPORT] IR obs: ", JSON.stringify({
		"detected": ir_low.get("detected", false),
		"level_support": ir_low.get("level_support", 0),
		"bearing_deg": ir_low.get("bearing_deg", -1.0),
		"bearing_sigma_deg": ir_low.get("bearing_sigma_deg", -1.0),
		"range_km": ir_low.get("range_km", -1.0),
		"range_band": ir_low.get("range_band", ""),
	}))

	if ok:
		print("SENSOR SELFTEST PASS")
	else:
		print("SENSOR SELFTEST FAIL")
	return ok


# ═══════════════════════════════════════════════════════════════════
# 11. headless 自测命令（模块内注释命令）
#
# 1) 建一个临时 runner（不进仓库）：
#    $tmp = "$env:TEMP\gt_sensor_selftest.gd"
#    @'
#    extends SceneTree
#    func _initialize() -> void:
#        var ok: bool = preload("res://scripts/sensor_model.gd").run_self_test()
#        quit(0 if ok else 1)
#    '@ | Set-Content -Path $tmp -Encoding UTF8
#
# 2) 跑（工作区根目录）：
#    .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
#        --path .\game_v15 --script $tmp
#
# 3) 期望末行 SENSOR SELFTEST PASS；退出码 0。
# ═══════════════════════════════════════════════════════════════════

