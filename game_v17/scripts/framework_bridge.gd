class_name V17Bridge
extends RefCounted

# V17 数据桥：V1 HUD/plot 继续做主角，V2 core/sim 只作为数据后端。
# 不在这里画 UI；V17 HUD 通过 bridge.world / bridge.mission 读取 view-model。

const ScenarioScript := preload("res://framework/core/scenario.gd")
const WorldScript := preload("res://framework/core/world.gd")
const MissionScript := preload("res://framework/core/mission.gd")

var scenario: V2Scenario
var world: V2World
var mission: V2Mission
var ready := false
var errors: Array[String] = []

func boot(scenario_path := "res://framework/content/scenario_l1_v2.json") -> bool:
	scenario = ScenarioScript.load_file(scenario_path)
	if not scenario.errors.is_empty():
		errors.append_array(scenario.errors)
	world = WorldScript.new()
	var ok := world.load_scenario(scenario)
	if not ok:
		errors.append_array(world.errors)
	mission = MissionScript.from_scenario(scenario)
	mission.attach_world(world)
	ready = ok
	return ready

func summary() -> Dictionary:
	if not ready:
		return {"ready": false, "errors": errors.duplicate()}
	return {
		"ready": true,
		"scenario": scenario.id,
		"title": scenario.title,
		"entities": world.entities.size(),
		"contacts": world.vm_contacts().size(),
		"own": world.own_id,
		"phase": mission.phase,
		"errors": errors.duplicate(),
	}

func contacts() -> Array:
	return world.vm_contacts() if ready else []

func selected() -> Dictionary:
	return world.vm_selected() if ready else {}

func actions(target_id: String) -> Array:
	return world.vm_actions(target_id) if ready else []

func flow() -> Dictionary:
	return world.vm_flow() if ready and world.has_method("vm_flow") else {}

func tutorial() -> Dictionary:
	return world.vm_tutorial() if ready and world.has_method("vm_tutorial") else {}

func damage() -> Dictionary:
	return world.vm_damage() if ready and world.has_method("vm_damage") else {}

func replay() -> Dictionary:
	return world.vm_replay() if ready and world.has_method("vm_replay") else {}

func advance(dt: float) -> void:
	if ready:
		world.advance(dt)
