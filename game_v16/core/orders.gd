class_name V2Order
extends RefCounted

# 预命令 → 授权 → 队列 → 传输 → 执行 → 完成；失败/撤销是显式状态。
const STATES := ["PRE_ORDER", "AUTHORIZED", "QUEUED", "TRANSMITTED", "EXECUTING", "DONE", "ABORTED", "REJECTED"]

var id := ""
var action := ""
var target := ""
var params: Dictionary = {}
var state := "PRE_ORDER"
var issued_t := 0.0
var exec_t := 0.0
var note := ""

func _init(p_id: String, p_action: String, p_target: String = "", p_params: Dictionary = {}) -> void:
	id = p_id
	action = p_action
	target = p_target
	params = p_params.duplicate(true)

func can(next: String) -> bool:
	var i := STATES.find(state)
	var j := STATES.find(next)
	return i >= 0 and j >= 0 and j > i and j <= STATES.find("DONE")

func go(next: String, now: float) -> bool:
	if not can(next):
		return false
	state = next
	issued_t = now
	return true

func to_dict() -> Dictionary:
	return {"id": id, "action": action, "target": target, "params": params.duplicate(true),
		"state": state, "issued_t": issued_t, "exec_t": exec_t, "note": note}
