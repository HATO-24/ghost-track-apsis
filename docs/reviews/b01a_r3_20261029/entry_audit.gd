extends SceneTree
const Binder := preload("res://scripts/ui/shell_binder.gd")
const SCENARIO := "res://framework/content/scenario_b01a_deploy_demo.json"

func _snapshot(b) -> Dictionary:
	var s = b.session
	var ids: Array = s.world.entities.keys(); ids.sort()
	var current: Dictionary = s.fleet_refit.refit_state("APSIS")
	var resources: Dictionary = s.deployment_resources("apsis")
	var frozen: Dictionary = resources.get("config_snapshot", {})
	return {"ready":b.ready,"errors":b.errors,"t":s.now_s(),
		"world_ids":ids,"deployment":s.fleet_deployment_vm(),
		"current_refit_state":current,"frozen_config":frozen,
		"current_refit_equals_frozen":JSON.stringify(current)==JSON.stringify(frozen.get("refit_service_state",{}))}

func _initialize() -> void:
	OS.set_environment("DSH_BUILD","orbital_sim")
	OS.set_environment("DSH_B01A_SCENARIO",SCENARIO)
	var out := {"head":"3ea9e8ceb9f247acd4a24641277c621146730d8f",
		"scope":"Original R4 actual config and R5 first deployment via real Binder; no UI input or rendering by reviewer"}
	var b = Binder.new()
	var ok := b.boot()
	var before := _snapshot(b)
	var plan: Dictionary = b.fleet_builder_op("DEPLOY_PLAN")
	var dep: Dictionary = b.fleet_builder_op("DEPLOY")
	out["delivered_scenario"] = {"boot_ok":ok,"before":before,
		"plan_ok":plan.get("ok"),"plan_revision":plan.get("revision"),
		"deploy":dep,"after":_snapshot(b)}
	var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	sd["deployment"]["auto"] = false
	var p := ProjectSettings.globalize_path("res://../.test-results/sol-b01a-r3/pre_scenario.json")
	var f := FileAccess.open(p,FileAccess.WRITE)
	f.store_string(JSON.stringify(sd));f.close()
	OS.set_environment("DSH_B01A_SCENARIO",p)
	var control = Binder.new()
	var c_ok := control.boot()
	var cb := _snapshot(control)
	var cp: Dictionary = control.fleet_builder_op("DEPLOY_PLAN")
	var cd: Dictionary = control.fleet_builder_op("DEPLOY")
	out["predeploy_immediate_control"] = {"boot_ok":c_ok,"before":cb,
		"plan_ok":cp.get("ok"),"plan_revision":cp.get("revision"),"deploy":cd,"after":_snapshot(control)}
	var delayed = Binder.new()
	var d_ok := delayed.boot()
	var db := _snapshot(delayed)
	delayed.tick(0.1)
	var dp: Dictionary = delayed.fleet_builder_op("DEPLOY_PLAN")
	var dd: Dictionary = delayed.fleet_builder_op("DEPLOY")
	out["predeploy_after_one_hud_tick"] = {"boot_ok":d_ok,"before":db,
		"plan_ok":dp.get("ok"),"plan_revision":dp.get("revision"),"deploy":dd,"after":_snapshot(delayed)}
	var dest := ProjectSettings.globalize_path("res://../.test-results/sol-b01a-r3/entry_audit.json")
	var r := FileAccess.open(dest,FileAccess.WRITE)
	r.store_string(JSON.stringify(out,"  "));r.close()
	print("SOL_B01A_ENTRY_AUDIT_COMPLETE ",dest)
	quit(0)
