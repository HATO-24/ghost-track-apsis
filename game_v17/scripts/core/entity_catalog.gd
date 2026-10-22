extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# Phase A1.1 · EntityCatalog — 实体静态元数据唯一权威来源
#
# 职责：
#   * 从场景/seed 实体表建立 id → 静态元数据的稳定映射（只读副本）；
#   * 供模拟系统（弹道/PD/未来系统）按 entity_id 读取 side/identity/batch/
#     ship_class/rcs_m2/ir_signature/radius_km/has_pd/facility_id/
#     transponder_profile/name/kind；
#   * 不保存位置/速度（运动学仍由 PhysicsWorld 唯一负责）、不写 world、
#     不写 TrackTable、不生成事件；
#   * 缺失字段以空串/0 表示，调用方不得静默把缺失当成“友方/已知”；
#     弹道侧用 radius_source 显式标注是否走了兜底默认值。
#
# 单写者语义：catalog 在 GameSession.boot() 由 seed 一次性构建，运行期只读；
# 动态实体（world/physics 新增）不在 catalog 中时，consumer 必须显式处理
# “无权威元数据”，不得回退成世界真值猜测。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.entity_catalog.v1"
const VERSION := "1.0.0"

const STRING_FIELDS := ["name", "kind", "ship_class", "side", "identity",
	"batch", "facility_id", "transponder_profile"]
const NUMBER_FIELDS := ["rcs_m2", "ir_signature", "radius_km"]

var ready := false
var errors: Array[String] = []
var source := "seed"
var entities: Dictionary = {}


func _init(cfg := {}) -> void:
	setup(cfg)


func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	entities.clear()
	source = String(cfg.get("source", "seed"))
	var rows = cfg.get("entities", [])
	if not (rows is Array):
		errors.append("entities 必须是数组")
		return false
	for raw in (rows as Array):
		if not (raw is Dictionary):
			errors.append("实体项必须是对象")
			continue
		var row: Dictionary = raw
		var eid := String(row.get("id", "")).strip_edges()
		if eid == "":
			errors.append("实体缺少 id")
			continue
		if entities.has(eid):
			errors.append("实体 id 重复：" + eid)
			continue
		var rec := _normalize_entity(eid, row)
		if rec.is_empty():
			continue
		entities[eid] = rec
	ready = errors.is_empty()
	return ready


# ── 查询（只读副本）────────────────────────────────────────────

func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func entity_ids() -> Array:
	var out: Array = entities.keys()
	out.sort()
	return out


func count() -> int:
	return entities.size()


## 未知 id 返回 {found:false, id}；不伪造元数据。
func get_entity(entity_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {"found": false, "id": entity_id}
	var out: Dictionary = (entities[entity_id] as Dictionary).duplicate(true)
	out["found"] = true
	return out


func all_entities() -> Array:
	var out: Array = []
	for eid in entity_ids():
		out.append(get_entity(String(eid)))
	return out


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA, "version": VERSION, "ready": ready,
		"source": source, "count": entities.size(),
		"entities": all_entities(), "errors": errors.duplicate(),
	}


func to_dict() -> Dictionary:
	return snapshot()


func to_json() -> String:
	return JSON.stringify(snapshot())


# ── 规范化 ────────────────────────────────────────────────────

func _normalize_entity(eid: String, row: Dictionary) -> Dictionary:
	var out := {"id": eid}
	for field in STRING_FIELDS:
		out[field] = String(row.get(field, ""))
	# ship_class 缺省按 kind（旧场景只写 kind 时仍可读）
	if out["ship_class"] == "":
		out["ship_class"] = out["kind"]
	for field in NUMBER_FIELDS:
		var v = row.get(field, 0.0)
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) < 0.0:
			errors.append("%s.%s 必须是非负有限数值" % [eid, field])
			return {}
		out[field] = float(v)
	out["has_pd"] = bool(row.get("has_pd", false))
	return out
