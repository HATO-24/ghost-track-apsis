class_name V2Mission
extends RefCounted

signal phase_changed(from: String, to: String)

const PHASES := ["PRELUDE", "READ", "COMMAND", "DECISION", "REPORT", "END"]

var phase := "PRELUDE"
var entered_t := 0.0
var phase_flags: Dictionary = {}

func enter(next: String, now: float) -> bool:
	if not (next in PHASES):
		return false
	var old := phase
	phase = next
	entered_t = now
	phase_flags[next] = true
	phase_changed.emit(old, next)
	return true

func advance(now: float) -> String:
	var i := PHASES.find(phase)
	if i < 0 or i >= PHASES.size() - 1:
		return phase
	enter(PHASES[i + 1], now)
	return phase

func elapsed(now: float) -> float:
	return maxf(0.0, now - entered_t)

func is_phase(p: String) -> bool:
	return phase == p
