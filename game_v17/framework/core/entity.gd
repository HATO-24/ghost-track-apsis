class_name V2Entity
extends RefCounted

# 数据驱动实体。不要在这里写死批号/关卡专用逻辑。
# 所有 UI/动作都按 kind、side、capabilities 查询。
#
# V2-1 扩展（与 V2-0 向后兼容）：
#   - batch：融合系统批号（数据字段；与实体 slug id 分开；老场景里 id 就是批号）
#   - meta / ui / orbit / signatures：原样保留，供 UI/sim 读取
#   - track_level / identity / threat：只读快照，由 V2World 从航迹同步（UI 兼容层）
#   - capability 查询：has / has_any / has_all / has_any_of

var id := ""
var batch := ""                # 融合批号（可为空；不要用它做逻辑判断）
var kind := "unknown"          # ship / station / tank / wreck / unknown
var side := "unknown"          # friend / hostile / neutral / unknown（真实阵营；身份见航迹）
var name := ""
var name_en := ""
var cls := ""
var role := ""
var faction := ""
var hull := ""
var capabilities: Array[String] = []
var signatures: Dictionary = {}
var orbit: Dictionary = {}
var tags: Array[String] = []
var meta: Dictionary = {}
var ui: Dictionary = {}

# —— 兼容快照：由 world 从航迹同步，UI 可读；逻辑以 V2Track 为准 ——
var track_level := 0
var identity := "unknown"
var threat := ""

# —— V2-CORE-3 损管（本舰/受损实体；world 提供 API 操作）——
var damage_sections: Array = []   # [{id,label,state,severity,repair_eta_s,repair_progress_s,started_t}]
var damage_queue: Array = []      # 维修队列（section id 顺序）

# —— R2-DAMAGE-2 完整损管模型（可选；V2DamageModel 实例）——
# 仅当实体在 damage_l1.json 有档案时初始化；其他实体保持 null（懒加载/默认空）。
const DamageModelScript := preload("res://framework/core/damage_model.gd")
var damage = null

## 初始化完整损管模型；内容缺省从 damage_l1.json 读取。返回成功与否。
func init_damage(content := {}, ship_id := "") -> bool:
	var c: Dictionary = content if content is Dictionary else {}
	if c.is_empty():
		c = DamageModelScript.load_content()
	var m = DamageModelScript.new()
	var sid := ship_id if String(ship_id) != "" else id
	if not m.setup(c, sid):
		damage = null
		return false
	damage = m
	return true

## 懒加载：仅当内容里有本实体档案时才建模型；否则返回 null（不伪造损管数据）。
func ensure_damage(content := {}, ship_id := ""):
	if damage != null:
		return damage
	var c: Dictionary = content if content is Dictionary else {}
	if c.is_empty():
		c = DamageModelScript.load_content()
	var ships: Dictionary = c.get("ships", {}) if c.get("ships") is Dictionary else {}
	var sid := ship_id if String(ship_id) != "" else id
	if not ships.has(sid):
		return null
	if init_damage(c, sid):
		return damage
	return null

func has_damage_model() -> bool:
	return damage != null


static func from_dict(d: Dictionary) -> V2Entity:
	var e := V2Entity.new()
	e.id = String(d.get("id", ""))
	e.batch = String(d.get("batch", ""))
	e.kind = String(d.get("kind", "ship"))
	e.side = String(d.get("side", "unknown"))
	e.name = String(d.get("name", d.get("name_cn", "")))
	e.name_en = String(d.get("name_en", d.get("en", "")))
	e.cls = String(d.get("class", d.get("cls", "")))
	e.role = String(d.get("role", ""))
	e.faction = String(d.get("faction", ""))
	e.hull = String(d.get("hull", ""))
	e.orbit = (d.get("orbit", {}) as Dictionary).duplicate(true)
	e.signatures = (d.get("signatures", {}) as Dictionary).duplicate(true)
	e.meta = (d.get("meta", {}) as Dictionary).duplicate(true)
	e.ui = (d.get("ui", {}) as Dictionary).duplicate(true)
	for c in (d.get("capabilities", []) as Array):
		e.capabilities.append(String(c))
	for t in (d.get("tags", []) as Array):
		e.tags.append(String(t))
	return e

func has(cap: String) -> bool:
	return cap in capabilities

func has_any(prefix: String) -> bool:
	for c in capabilities:
		if c.begins_with(prefix):
			return true
	return false

func has_any_of(caps: Array) -> bool:
	for raw in caps:
		if has(String(raw)):
			return true
	return false

func has_all(caps: Array) -> bool:
	for raw in caps:
		if not has(String(raw)):
			return false
	return true

func is_own() -> bool:
	return side == "friend" and ("own" in tags)

func is_friend() -> bool:
	return side == "friend"

func is_hostile() -> bool:
	return side == "hostile"

## 固定设施（站体/储罐）：tags 含 fixed，或轨道速度≈0。UI/sim 据此不画推进/预测。
func is_fixed() -> bool:
	if "fixed" in tags:
		return true
	var v = orbit.get("v", null)
	if v is Array and (v as Array).size() >= 3:
		return absf(float((v as Array)[0])) < 1.0e-9 and absf(float((v as Array)[1])) < 1.0e-9 \
			and absf(float((v as Array)[2])) < 1.0e-9
	return false

func display_kind() -> String:
	match kind:
		"station":
			return "站体"
		"tank":
			return "储罐"
		"wreck":
			return "残骸"
		"ship":
			return "舰船"
		_:
			return kind

func icon() -> String:
	return String(meta.get("icon", kind))

func size_km() -> float:
	return float(meta.get("size_km", 0.0))

func display_name() -> String:
	return name if name != "" else ("[%s]" % (batch if batch != "" else id))

func display_batch() -> String:
	return batch if batch != "" else id

func to_dict() -> Dictionary:
	return {
		"id": id, "batch": batch, "kind": kind, "side": side,
		"name": name, "name_en": name_en, "class": cls, "role": role,
		"faction": faction, "hull": hull,
		"capabilities": capabilities.duplicate(), "signatures": signatures.duplicate(true),
		"orbit": orbit.duplicate(true), "tags": tags.duplicate(),
		"meta": meta.duplicate(true), "ui": ui.duplicate(true),
		"track_level": track_level, "identity": identity, "threat": threat,
		"fixed": is_fixed(), "icon": icon(), "size_km": size_km(),
		"damage_sections": damage_sections.duplicate(true),
		"damage_queue": damage_queue.duplicate(),
		"damage_ready": damage != null,
	}
