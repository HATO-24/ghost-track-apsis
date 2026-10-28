extends "res://tests/jc_identity_pipeline_probe.gd"

const OUT := "C:/Users/ASUS/.codex/worktrees/jc-a02-r3-validation/GHOST TRACK_APSIS/.test-results/sol-a02-r3/hud_validity/result.json"

func _run() -> void:
	var report := {"head": "755ab5ed629165656a566427523b01045775fc0f", "cases": {}}
	var s = _new()
	var ing: Dictionary = s.identity_ingest("player_intel", _ev("ttl_cons", "optical", "friend", 0.9, {"ttl_s": 5.0}))
	var binder = Binder.new()
	binder.session = s
	binder.refresh()
	var valid_view: Dictionary = binder.ident_view({"track_id": "ttl_cons"})
	var valid_contact := _find_contact(binder.contacts, "ttl_cons")
	var valid_op: Dictionary = s.identity_operational("player_intel", "ttl_cons")
	for i in range(11):
		s.tick(1.0)
	var expired_op: Dictionary = s.identity_operational("player_intel", "ttl_cons")
	var expired_view: Dictionary = binder.ident_view({"track_id": "ttl_cons"})
	binder.refresh()
	var expired_contact := _find_contact(binder.contacts, "ttl_cons")
	var fire: Dictionary = s.combat_identity("ttl_cons")
	report["cases"]["ttl5_t11_valid_to_expired"] = {"ingest": ing, "valid_operational": valid_op, "valid_ident_view": valid_view, "valid_contact": valid_contact, "now": s.now_s(), "expired_operational": expired_op, "expired_ident_view": expired_view, "expired_contact": expired_contact, "fire_control": fire}

	# Separate dimension sample: stale time validity may coexist with valid assessment state.
	var st = _new()
	for j in range(8):
		st.tick(1.0)
	var stale_ingest: Dictionary = st.identity_ingest("player_intel", _ev("stale_cons", "transponder", "friend", 0.9, {"observed_t": 0.0, "received_t": 8.0, "ttl_s": 5.0}))
	var stale_op: Dictionary = st.identity_operational("player_intel", "stale_cons")
	var stale_binder = Binder.new()
	stale_binder.session = st
	var stale_view: Dictionary = stale_binder.ident_view({"track_id": "stale_cons"})
	report["cases"]["stale_dimensions"] = {"ingest": stale_ingest, "operational": stale_op, "ident_view": stale_view}

	var of := FileAccess.open(OUT, FileAccess.WRITE)
	if of == null:
		push_error("Could not open report: " + OUT)
		quit(2)
		return
	of.store_string(JSON.stringify(report, "\t"))
	of.close()
	print("JC-A02 R4 HUD VALIDITY DIAGNOSTIC report=", OUT)
	print(JSON.stringify({"valid": {"view_identity": valid_view.get("identity", ""), "contact_identity": valid_contact.get("identity", ""), "contact_side": valid_contact.get("side", ""), "contact_type": valid_contact.get("type", "")}, "expired": {"view_identity": expired_view.get("identity", ""), "view_last_known": expired_view.get("last_known_identity", ""), "view_validity": expired_view.get("validity", ""), "view_warn": expired_view.get("warn", false), "view_tag": expired_view.get("tag", ""), "contact_identity": expired_contact.get("identity", ""), "contact_side": expired_contact.get("side", ""), "contact_type": expired_contact.get("type", ""), "contact_validity": expired_contact.get("validity", ""), "contact_last_known": expired_contact.get("last_known_identity", ""), "contact_ident": expired_contact.get("ident", {}), "fire_identity": fire.get("identity", "")}, "stale": {"state": stale_op.get("identity_state", ""), "alias": stale_op.get("state", ""), "validity": stale_op.get("validity", ""), "effective": stale_op.get("effective_identity", ""), "view_identity": stale_view.get("identity", ""), "view_last_known": stale_view.get("last_known_identity", "")}, "report": OUT}))
	quit(0)


func _find_contact(rows: Array, tid: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get("track_id", "")) == tid:
			return raw.duplicate(true)
	return {}
