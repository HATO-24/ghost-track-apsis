class_name V2Entity
extends RefCounted

# 数据驱动实体。不要在这里写死批号/关卡专用逻辑。
# 所有 UI/动作都按 kind、side、capabilities 查询。

var id := ""
var kind := "unknown"          # ship / station / tank / wreck / unknown
var side := "unknown"          # friend / hostile / neutral / unknown
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
var track_level := 0
var identity := "unknown"
var threat := ""

static func from_dict(d: Dictionary) -> V2Entity:
	var e := V2Entity.new()
	e.id = String(d.get("id", ""))
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

func is_own() -> bool:
	return side == "friend" and ("own" in tags)

func display_name() -> String:
	return name if name != "" else ("[%s]" % id)

func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "side": side, "name": name, "name_en": name_en,
		"class": cls, "role": role, "faction": faction, "hull": hull,
		"capabilities": capabilities.duplicate(), "signatures": signatures.duplicate(true),
		"orbit": orbit.duplicate(true), "tags": tags.duplicate(), "meta": meta.duplicate(true),
	}
