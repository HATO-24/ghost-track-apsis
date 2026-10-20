extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 阶段2-TRANSIT-DAMAGE-1：转场 5 舰损管数据层（只读 / 显式 API）
#
# - 从 framework/content/damage_l1.json 加载 5 舰 V2DamageModel：
#   apsis(1000) / harmattan(1001) / ferry(1002) / watchtower(1003) / deepwell(1004)；
#   每舰 7 分区 hull/power/propulsion/sensors/comms/tanks/docking；
# - step(dt) 推进全部舰；vm(ship_id) 只读 VM（在 V2DamageModel vm 上附 wrapper 字段）；
# - assign_repair/cancel_repair/set_priority 包装；apply_hit 为显式诊断输入；
# - summary() 舰队汇总；**不生成武器/命中来源**、不写 world/V15、不接 HUD。
# ═══════════════════════════════════════════════════════════════════

const DamageModel := preload("res://framework/core/damage_model.gd")
const CONTENT_PATH := "res://framework/content/damage_l1.json"
const SCHEMA := "v17_transit_damage.v1"
const FLEET := "transit_l4_l1"
const SHIP_IDS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const SHIP_BATCH := {"apsis": "1000", "harmattan": "1001", "ferry": "1002",
	"watchtower": "1003", "deepwell": "1004"}
const SHIP_ROLE := {"apsis": "flagship", "harmattan": "command", "ferry": "escort",
	"watchtower": "relay", "deepwell": "tanker"}

var content_path := CONTENT_PATH
var content: Dictionary = {}
var models: Dictionary = {}
var model_order: Array = []
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var t := 0.0
var step_count := 0

func _init(content_override := {}, ship_ids := SHIP_IDS) -> void:
	load_models(content_override, ship_ids)

## 加载内容并初始化 5 舰；已有档案（harmattan/summons_4471）不覆盖。
func load_models(content_override := {}, ship_ids := SHIP_IDS) -> bool:
	models = {}
	model_order = []
	errors.clear()
	warnings.clear()
	t = 0.0
	step_count = 0
	content = content_override if content_override is Dictionary and not (content_override as Dictionary).is_empty() \
		else DamageModel.load_content(CONTENT_PATH)
	if content.is_empty():
		errors.append("damage content 未就绪：" + CONTENT_PATH)
		ready = false
		return false
	var ids: Array = ship_ids if ship_ids is Array and not (ship_ids as Array).is_empty() else SHIP_IDS
	var ships: Dictionary = content.get("ships", {}) if content.get("ships") is Dictionary else {}
	for raw in ids:
		var sid := String(raw)
		if not ships.has(sid):
			warnings.append("damage 档案缺失：%s（跳过）" % sid)
			continue
		var m = DamageModel.new()
		if bool(m.setup(content, sid)):
			models[sid] = m
			model_order.append(sid)
		else:
			errors.append("舰 %s 损管初始化失败：%s" % [sid, str(m.errors)])
	ready = errors.is_empty() and models.size() == ids.size() and ids.size() > 0
	if not ready and errors.is_empty():
		warnings.append("5 舰档案未全部就绪（models=%d/%d）" % [models.size(), ids.size()])
	return ready

func model(ship_id: String):
	return models.get(ship_id, null)

func ship_ids() -> Array:
	return model_order.duplicate()

func has_ship(ship_id: String) -> bool:
	return models.has(ship_id)

func batch_for(ship_id: String) -> String:
	return String(SHIP_BATCH.get(ship_id, ""))

func role_for(ship_id: String) -> String:
	return String(SHIP_ROLE.get(ship_id, ""))

# ── 推进 / 只读 VM ───────────────────────────────────────────────

## 推进全部舰（仅模型内部时间；不写 world/V15）。
func step(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	var d := maxf(0.0, float(dt))
	if d <= 0.0:
		return {"ok": true, "t": t, "step_count": step_count, "summary": summary()}
	t += d
	step_count += 1
	for sid in model_order:
		var m = models[sid]
		m.step(d)
	return {"ok": true, "t": t, "step_count": step_count, "summary": summary()}

## 单舰只读 VM（V2DamageModel vm + wrapper 字段；JSON 安全）。
func vm(ship_id: String) -> Dictionary:
	var m = models.get(ship_id, null)
	if m == null:
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	var base: Dictionary = m.vm_damage()
	var out: Dictionary = base.duplicate(true)
	out["ok"] = true
	out["wrapper_schema"] = SCHEMA
	out["fleet"] = FLEET
	out["ship_id"] = ship_id
	out["batch"] = batch_for(ship_id)
	out["role"] = role_for(ship_id)
	out["step_count"] = step_count
	out["weapon_source"] = "none（模型不生成武器/命中；伤害需显式 apply_hit 诊断输入）"
	out["hud_fields"] = ["ship_id", "batch", "name", "class", "t", "sections",
		"(sections[].integrity/state/fire/decompression/powered/power_loss/repair)",
		"queue", "resources", "summary", "effects"]
	return out

## 舰队汇总（5 舰 summary/effects 聚合；只读）。
func summary() -> Dictionary:
	var ships: Array = []
	var totals := {
		"ships": 0, "operational": 0, "nominal": 0, "degraded": 0,
		"damaged": 0, "critical": 0, "destroyed": 0,
		"on_fire": 0, "decompressed": 0, "unpowered": 0,
		"repairing": 0, "queued": 0, "needs_attention": 0,
	}
	var integrity_sum := 0.0
	var section_total := 0
	for sid in model_order:
		var m = models[sid]
		var s: Dictionary = m.summary()
		var eff: Dictionary = m.effects()
		var row := {
			"ship_id": sid,
			"batch": batch_for(sid),
			"role": role_for(sid),
			"name": String(m.name),
			"class": String(m.ship_class),
			"summary": s.duplicate(true),
			"effects": {
				"power": (eff.get("power", {}) as Dictionary).duplicate(true),
				"sensors": (eff.get("sensors", {}) as Dictionary).duplicate(true),
				"comms": (eff.get("comms", {}) as Dictionary).duplicate(true),
				"propulsion": (eff.get("propulsion", {}) as Dictionary).duplicate(true),
				"docking": (eff.get("docking", {}) as Dictionary).duplicate(true),
				"fire": (eff.get("fire", {}) as Dictionary).duplicate(true),
				"decompression": (eff.get("decompression", {}) as Dictionary).duplicate(true),
				"unpowered_sections": (eff.get("unpowered_sections", []) as Array).duplicate(),
			},
			"operational": bool(m.is_operational()),
		}
		ships.append(row)
		totals["ships"] += 1
		if bool(row["operational"]):
			totals["operational"] = int(totals["operational"]) + 1
		for k in ["nominal", "degraded", "damaged", "critical", "destroyed",
				"on_fire", "decompressed", "unpowered", "repairing", "queued",
				"needs_attention"]:
			totals[k] = int(totals[k]) + int(s.get(k, 0))
		integrity_sum += float(s.get("integrity_avg", 0.0))
		section_total += int(s.get("total", 0))
	totals["integrity_avg"] = integrity_sum / float(maxi(1, ships.size()))
	totals["sections"] = section_total
	return {
		"schema": SCHEMA,
		"fleet": FLEET,
		"ready": ready,
		"t": t,
		"step_count": step_count,
		"ships": ships,
		"totals": totals,
		"weapon_source": "none（无武器命中来源；伤害需显式 apply_hit）",
		"note": "转场 5 舰损管只读数据层；不写 world/V15；不接 HUD。",
	}

# ── 损管 / 诊断输入（包装 V2DamageModel）─────────────────────────

func assign_repair(ship_id: String, section_id: String, priority := 2) -> Dictionary:
	var m = models.get(ship_id, null)
	if m == null:
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	return m.assign_repair(section_id, priority)

func cancel_repair(ship_id: String, section_id: String) -> Dictionary:
	var m = models.get(ship_id, null)
	if m == null:
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	return m.cancel_repair(section_id)

func set_priority(ship_id: String, section_id: String, priority: int) -> Dictionary:
	var m = models.get(ship_id, null)
	if m == null:
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	return m.set_priority(section_id, priority)

## 显式诊断伤害（无武器来源；用于数据层验证/脚本事件）。
func apply_hit(ship_id: String, section_id: String, energy: float,
		penetration := 0.5, direction := "fore", source := "diagnostic") -> Dictionary:
	var m = models.get(ship_id, null)
	if m == null:
		return {"ok": false, "reason": "unknown_ship", "ship_id": ship_id}
	return m.apply_hit(section_id, energy, penetration, direction, source)

## 单舰重置（重新用内容档案初始化该舰）。
func reset_ship(ship_id: String) -> bool:
	if not models.has(ship_id):
		return false
	var m = DamageModel.new()
	if not bool(m.setup(content, ship_id)):
		return false
	models[ship_id] = m
	return true

## 全部重置（重建 5 舰；事件/队列/资源清空）。
func reset() -> bool:
	return load_models(content, SHIP_IDS)

func summary_totals() -> Dictionary:
	return (summary().get("totals", {}) as Dictionary).duplicate(true)
