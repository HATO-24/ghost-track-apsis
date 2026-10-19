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
	}
