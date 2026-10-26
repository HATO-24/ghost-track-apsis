extends SceneTree

const Tws = preload("res://framework/sim/tws.gd")

func _initialize() -> void:
	var tw = Tws.new()
	var st: Dictionary = tw.export_state()
	st["channels"] = {"broken": {
		"target_id": "broken", "state": "STARE", "quality": 1.0,
		"last_update_t": 0.0}}
	var vr: Dictionary = tw.validate_state(st)
	var ir: Dictionary = tw.import_state(st)
	print("R6-STARE-AUDIT head=5d7208b82ebae81da874e059c2d88286317c6483")
	print("R6-STARE-AUDIT VALIDATE=", JSON.stringify(vr))
	print("R6-STARE-AUDIT IMPORT=", JSON.stringify(ir))
	print("R6-STARE-AUDIT IMPORTED_CHANNELS=", JSON.stringify(tw.channels))
	if not bool(ir.get("ok", false)):
		print("R6-STARE-AUDIT PASS malformed channel rejected before continuation")
		quit(0)
		return
	print("R6-STARE-AUDIT BEFORE STEP (any SCRIPT ERROR means failure)")
	var result: Dictionary = tw.step(1.0, {"t": 1.0, "targets": []})
	print("R6-STARE-AUDIT AFTER STEP=", JSON.stringify(result))
	print("R6-STARE-AUDIT FAIL malformed STARE channel was accepted")
	quit(1)
