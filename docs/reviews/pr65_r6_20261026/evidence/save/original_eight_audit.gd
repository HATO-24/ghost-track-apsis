extends SceneTree

const Authority = preload("res://framework/sim/sensor_authority.gd")
const Tws = preload("res://framework/sim/tws.gd")
const Radar = preload("res://framework/sim/radar.gd")
const Optical = preload("res://framework/sim/optical_ir_channel.gd")

var rows: Array = []
var violations: int = 0

func record_case(name: String, expected: String, result: Dictionary, before: Dictionary, after: Dictionary, violated: bool) -> void:
	var row: Dictionary = {"case": name, "expected": expected, "result": result,
		"before": before, "after": after, "violation": violated}
	rows.append(row)
	if violated:
		violations += 1
	print("R6-SAVE-AUDIT ", JSON.stringify(row))

func _initialize() -> void:
	var a = Authority.new()
	var setup_ok: bool = a.setup()
	print("R6-SAVE-AUDIT SETUP ready=", setup_ok)
	if not setup_ok:
		quit(2)
		return
	var st: Dictionary = a.export_backend_state()
	var valid: Dictionary = a.import_backend_state(st)
	record_case("positive_roundtrip", "ok=true", valid, {}, {}, not bool(valid.get("ok", false)))

	# Newly supplied bad TWS must not commit the already-valid optical state.
	var before: Dictionary = a.export_backend_state()
	var bad: Dictionary = before.duplicate(true)
	bad["t"] = 123.0
	bad["tws"] = "not-an-object"
	var r: Dictionary = a.import_backend_state(bad)
	var after: Dictionary = a.export_backend_state()
	record_case("bad_tws_partial_optical_commit", "reject and optical.t unchanged", r,
		{"optical_t": before["t"]}, {"optical_t": after["t"]},
		bool(r.get("ok", false)) or after["t"] != before["t"])

	# A rejected optical payload must not nevertheless commit the new TWS state.
	a = Authority.new()
	a.setup()
	before = a.export_backend_state()
	bad = before.duplicate(true)
	bad["schema"] = "wrong-schema"
	bad["tws"]["now_t"] = 321.0
	r = a.import_backend_state(bad)
	after = a.export_backend_state()
	record_case("bad_optical_partial_tws_commit", "reject and tws.now_t unchanged", r,
		{"tws_t": before["tws"]["now_t"]}, {"tws_t": after["tws"]["now_t"]},
		bool(r.get("ok", false)) or after["tws"]["now_t"] != before["tws"]["now_t"])

	# Neither newly introduced substate checks its exported version field.
	var tw = Tws.new()
	var ts: Dictionary = tw.export_state()
	ts["version"] = 999
	ts["radar"]["version"] = 999
	r = tw.import_state(ts)
	record_case("future_nested_versions", "unsupported version rejected", r,
		{}, {"tws_input_version": 999, "radar_input_version": 999}, bool(r.get("ok", false)))

	var rd = Radar.new()
	var rs: Dictionary = rd.export_state()
	rs["scan_index"] = 1.0e100
	r = rd.import_state(rs)
	record_case("scan_index_overflow", "out-of-range integer rejected", r,
		{"scan_index": 0}, {"scan_index": rd.scan_index}, bool(r.get("ok", false)))

	rd = Radar.new()
	rs = rd.export_state()
	rs["elapsed_s"] = -10.0
	rs["seconds_on"] = -7.0
	rs["time_since_scan"] = -4.0
	r = rd.import_state(rs)
	record_case("negative_radar_timers", "negative elapsed/on/phase rejected", r,
		{}, {"elapsed_s": rd.elapsed_s, "seconds_on": rd.seconds_on,
			"time_since_scan": rd.time_since_scan}, bool(r.get("ok", false)))

	var op = Optical.new()
	var os: Dictionary = op.export_state()
	os["mount_pointing"]["optical"]["boresight_deg"] = 1000.0
	os["mount_pointing"]["optical"]["boresight_el_deg"] = 120.0
	r = op.import_state(os)
	var oa: Dictionary = op.export_state()
	record_case("out_of_range_mount_pointing", "out-of-range angles rejected as report claims", r,
		{"az": 1000.0, "el": 120.0}, oa["mount_pointing"]["optical"], bool(r.get("ok", false)))

	# A new-format TWS snapshot can omit the radar phase and silently retain old state.
	tw = Tws.new()
	ts = tw.export_state()
	ts["now_t"] = 200.0
	ts.erase("radar")
	r = tw.import_state(ts)
	record_case("missing_radar_substate", "new TWS snapshot must reject or explicitly migrate missing radar", r,
		{}, {"tws_t": tw.now_t, "radar_t": tw.radar.elapsed_s, "scan_index": tw.radar.scan_index},
		bool(r.get("ok", false)))

	# Empty row is accepted, but the subsequent maintenance loop indexes required keys.
	tw = Tws.new()
	ts = tw.export_state()
	ts["channels"] = {"broken": {}}
	r = tw.import_state(ts)
	record_case("malformed_tws_channel", "reject malformed channel before continuation", r,
		{}, {"channels": tw.channels}, bool(r.get("ok", false)))
	print("R6-SAVE-AUDIT BEFORE malformed continuation (SCRIPT ERROR is a failure even if process returns 0)")
	var out: Dictionary = tw.step(1.0, {"t": 1.0, "targets": []})
	print("R6-SAVE-AUDIT AFTER malformed continuation returned=", JSON.stringify(out))

	var path: String = OS.get_environment("SAVE_AUDIT_OUT")
	if path != "":
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"head": "5d7208b82ebae81da874e059c2d88286317c6483", "violations": violations, "cases": rows}, "  "))
	print("R6-SAVE-AUDIT RESULT violations=", violations)
	quit(1 if violations > 0 else 0)
