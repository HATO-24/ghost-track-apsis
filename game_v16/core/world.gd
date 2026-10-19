class_name V2World
extends RefCounted

# 纯数据世界状态。UI 只能通过只读查询或明确的命令方法修改。
signal state_changed(reason: String)
signal log_event(kind: String, text: String)

var scenario: V2Scenario
var entities: Array[V2Entity] = []
var by_id: Dictionary = {}
var own_id := ""
var selected_id := ""
var t := 0.0
var layers := {
	"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true,
}

func load_scenario(s: V2Scenario) -> bool:
	scenario = s
	entities.clear()
	by_id.clear()
	own_id = ""
	for e in s.entities:
		entities.append(e)
		by_id[e.id] = e
		if e.is_own() or ("own" in e.tags):
			own_id = e.id
	if own_id == "" and entities.size() > 0:
		own_id = entities[0].id
	# 基准舰默认选中，后续 UI 可改。
	selected_id = own_id
	return s.errors.is_empty()

func selected() -> V2Entity:
	return by_id.get(selected_id)

func own() -> V2Entity:
	return by_id.get(own_id)

func select(eid: String) -> bool:
	if not by_id.has(eid):
		return false
	selected_id = eid
	state_changed.emit("select")
	return true

func select_batch(batch: String) -> bool:
	for e in entities:
		if e.id == batch:
			return select(e.id)
	return false

func entity(eid: String) -> V2Entity:
	return by_id.get(eid)

func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	state_changed.emit("tick")

func set_layer(name: String, on: bool) -> void:
	if layers.has(name):
		layers[name] = on
		state_changed.emit("layer")

func visible_entities() -> Array[V2Entity]:
	var out: Array[V2Entity] = []
	for e in entities:
		if e.side == "unknown" and not layers.get("contacts", true):
			continue
		out.append(e)
	return out

func log(kind: String, text: String) -> void:
	log_event.emit(kind, text)
