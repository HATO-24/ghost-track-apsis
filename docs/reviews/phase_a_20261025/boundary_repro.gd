extends SceneTree

const Bus = preload("res://scripts/core/event_bus.gd")
const Tracks = preload("res://scripts/core/track_table.gd")
const Session = preload("res://scripts/core/game_session.gd")
const Binder = preload("res://scripts/ui/shell_binder.gd")

func ev(id := "") -> Dictionary:
	var e := {"type":"review.boundary", "t":0.125, "source":"review", "payload":{}}
	if id != "": e["id"] = id
	return e

func _initialize() -> void:
	var bus = Bus.new()
	var explicit: Dictionary = bus.publish(ev("evt-000001"))
	var automatic: Dictionary = bus.publish(ev())
	print("REVIEW_EXPLICIT_AUTO_COLLISION ", JSON.stringify({"explicit":explicit.event.id,
		"automatic":automatic.event.id,"both_ok":explicit.ok and automatic.ok,
		"same_id":explicit.event.id == automatic.event.id}))
	var history = Bus.new()
	history.publish(ev("review-early-explicit"))
	for i in range(1001): history.publish(ev())
	var state: Dictionary = history.export_state()
	state.erase("seen_ids")
	var restored = Bus.new()
	var imported: Dictionary = restored.import_state(state)
	var duplicate: Dictionary = restored.publish(ev("review-early-explicit"))
	print("REVIEW_V2_MISSING_SEEN_IDS ", JSON.stringify({"import_ok":imported.ok,
		"reused_old_id_accepted":duplicate.ok,"original_seen":history._seen_ids.size(),
		"restored_seen":restored._seen_ids.size()}))
	var tracks = Tracks.new()
	var obs: Dictionary = tracks.handle_observation({"id":"review-obs", "t":0.0,
		"sensor":"radar", "support":2, "entity_id":"review-unknown",
		"batch":"SECRET-9001", "range_km":5.0,"bearing_deg":20.0}, "fusion_authority")
	var tid := String(obs.get("track",{}).get("id",""))
	var player: Dictionary = tracks.vm({"selected_id":tid})
	print("REVIEW_PLAYER_SELECTED_TRUTH ", JSON.stringify({"observation_ok":obs.ok,
		"list_has_batch":player.tracks[0].has("batch"),
		"selected_has_batch":player.selected.has("batch"),
		"selected_batch":player.selected.get("batch","")}))
	var session = Session.new()
	session.send_comms("review-unknown-from", "review-unknown-to", "LD")
	var saved: Dictionary = JSON.parse_string(session.save_state())
	for op in saved.log:
		if op.get("op", "") == "send_comms": op.outcome.version = 999
	var loaded = Session.new()
	var lr: Dictionary = loaded.load_state(JSON.stringify(saved))
	print("REVIEW_COMMS_UNKNOWN_OUTCOME ", JSON.stringify({"load_ok":lr.ok,
		"report":loaded.comms_restore_report()}))
	OS.set_environment("DSH_BUILD", "orbital_sim")
	var binder = Binder.new()
	binder.boot()
	var svc = binder.session.sensor_service
	svc.start_channel("optical", "harmattan")
	var sensor_state: Dictionary = svc.export_state()
	var sensor_fraction: Dictionary = sensor_state.duplicate(true)
	sensor_fraction.version = 1.5
	var fractional_import: Dictionary = svc.import_state(sensor_fraction)
	print("REVIEW_SENSOR_FRACTIONAL_VERSION ", JSON.stringify(fractional_import))
	var binder2 = Binder.new()
	binder2.boot()
	var svc2 = binder2.session.sensor_service
	var sensor_missing: Dictionary = sensor_state.duplicate(true)
	sensor_missing.backend = null
	var sr: Dictionary = svc2.import_state(sensor_missing)
	print("REVIEW_SENSOR_MISSING_BACKEND ", JSON.stringify({"import_ok":sr.ok,
		"original_backend_channels":sensor_state.backend.channels.size(),
		"restored_backend_channels":svc2._authority.export_backend_state().channels.size(),
		"selected_target":svc2.selected_target}))
	var binder3 = Binder.new()
	binder3.boot()
	var original = binder3.session
	original.sensor_service.start_channel("optical", "harmattan")
	original.sensor_service.start_channel("ir", "harmattan")
	original.sensor_service.set_emcon(true)
	for i in range(5): original.tick(1.0)
	var continuation = Session.new()
	var continuation_load: Dictionary = continuation.load_state(original.save_state())
	for i in range(10):
		original.tick(1.0)
		continuation.tick(1.0)
	print("REVIEW_SENSOR_CONTINUATION ", JSON.stringify({"load_ok":continuation_load.ok,
		"original":original.sensor_service.runtime_state_summary(),
		"restored":continuation.sensor_service.runtime_state_summary()}))
	var violations := 0
	if explicit.event.id == automatic.event.id: violations += 1
	if imported.ok and duplicate.ok: violations += 1
	if player.selected.has("batch"): violations += 1
	if lr.ok and loaded.comms_restore_report().legacy_unverified == 1: violations += 1
	if fractional_import.ok: violations += 1
	if sr.ok and svc2._authority.export_backend_state().channels.size() != sensor_state.backend.channels.size(): violations += 1
	if original.sensor_service._obs_seq != continuation.sensor_service._obs_seq: violations += 1
	print("REVIEW_BOUNDARIES_RESULT violations=", violations)
	quit(1 if violations > 0 else 0)
