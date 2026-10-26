extends SceneTree
const Binder = preload("res://scripts/ui/shell_binder.gd")
const Session = preload("res://scripts/core/game_session.gd")
func _initialize() -> void:
	OS.set_environment("DSH_BUILD", "orbital_sim")
	var binder = Binder.new()
	binder.boot()
	var s = binder.session
	for i in range(5):
		s.tick(1.0)
	var text = s.save_state()
	var file = FileAccess.open(OS.get_environment("R6_LEGACY_OUT"), FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(text)
	file.close()
	var check = Session.new()
	var roundtrip = check.load_state(text)
	print("R6_LEGACY_EXPORT ", JSON.stringify({"source_head": "30b8d33dae9787aadf89bb206757cafb2cad7bd3",
		"ready": s.ready, "chars": text.length(), "sensor_state": s.sensor_service != null,
		"source_roundtrip_ok": roundtrip.get("ok", false), "source_roundtrip_errors": roundtrip.get("errors", []),
		"sensor_version": s.sensor_service.export_state().version,
		"backend": s.sensor_service._authority.export_backend_state()}))
	quit(0 if bool(roundtrip.get("ok", false)) else 1)
