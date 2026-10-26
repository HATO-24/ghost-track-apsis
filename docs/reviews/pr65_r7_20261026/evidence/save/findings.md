# R7 A00/G0 narrow independent audit

- Reviewed HEAD: `2ae7bf7cba8af32ff4456cefe28efa3650b868dd` (2026-10-26 Asia/Shanghai).
- Engine: Godot `4.7.2.stable.official.ed1daf0bf`, Windows.
- Review-only scripts/logs; no production edits, no GitHub writes. Full matrix and long benchmark belong to root agent.

## CLOSED at this HEAD

1. Original incomplete STARE object is rejected by validate/import before continuation (`stare_channel_audit.log`, exit 0). The new field-list validation fixes the original missing-field counterexample.
2. Original three authority/child/counter atomic failures reject and leave backend state unchanged (`quick.log`, exit 0, review_defects=0).
3. `bus._id_seq` 220→320 is now detected by normal full-state comparison. Original event payload and observation-quality tampering remain detected.
4. At non-full communication history, tampered pending message text is detected both immediately and by real `comms.events.new` during delivery. The nonexistent `last_event()` path is removed and `_comms_event_sigs` is actually called.
5. Real C55-generated old-v1 file now loads successfully. Direct `SensorService.import_state` honestly returns `restore_mode=partial` with reasons. This closes old-data rejection and the absence of a bottom-layer migration policy.

## Remaining original-card items

### P1 — TWS required fields explicitly set to null bypass validation and break continuation

`game_v17/framework/sim/tws.gd:639-642` skips every field whose value is null. The required-key pass only tests presence. A complete real channel created through `ingest`, changed to STARE with quality=1 and stare_s=7.5, passes validation/import after setting only `history=null`. On the next 1s step, transition raises `Trying to assign value of type Nil to Array` at line 413, then export raises another invalid Array cast at line 470. Five null variants (history/stare_s/stare_required_s/quality/state_since_t) are accepted; history is the concrete crash reproduction.

Evidence: `tws_null_audit.gd`, `tws_null_audit.json`, `tws_null_audit.log` (exit 1, intentional defect diagnostic). Required fields must reject null through their declared type check before any commit. Keep existing two-phase atomic import and the now-fixed missing-key counterexamples.

### P2 — Per-tick signatures miss newly produced records after bounded history reaches capacity

`game_v17/tests/a0_save_cost_probe.gd:666-669` uses `comms.events.slice(previous_size)`. `CommsService` keeps only 200 records and pops the front. At capacity, previous and new size are both 200, so this always yields `[]`. The same size/slice pattern is used for bus events (639-642) and observations (654-657).

Minimal comparison: use the original 50-tick quick fixture; give both sessions the same 200-record communication history, then change only restored pending text. Real delivery appends seq 201 with changed text and trims the oldest record. Immediate pending comparison catches it, but `_behavior_violations(...,10)==[]` and final `_full_state_violations==[]`. Non-full history detects the same change. Thus the current claim of per-tick output coverage has a bounded-history hole, not a re-opening of the non-full fix.

Evidence: `saturated_comms_audit.gd` / `.log`; diagnostic exit 0 means it ran to completion, not that the delivered-content mismatch was rejected. Existing `quick.log` is the non-full positive comparison. Capture by sequence/event-id/tick outbox rather than pre-tick retained-array length, and use a full-history positive/negative control. This is the same original G3 output-comparison requirement, not a new gameplay feature.

The PR's “immediate + per-tick + final all detect” wording is also too broad: even the non-full quick result has `after_violations=[]`; actual per-tick detection is what closes that old defect. There is no need to demand three independent detections as a new condition.

### P2 — Top-level save load discards the new partial-restore disclosure

`game_v17/scripts/core/game_session.gd:5099-5124` checks sensor `sr.ok` then discards the result; `sensor_restore_report()` exposes only saved/geometry/rebind/time. The same real C55 file produces direct sensor import `{ok:true, restore_mode:"partial", partial_reasons:["mount_pointing_missing","tws_runtime_reset_unrecoverable","authority_clock_rebuilt_from_optical_t"]}`. Public `GameSession.load_state` and `sensor_restore_report()` both omit the mode and reasons, with `ok=true`/`time_ok=true`.

Evidence: `legacy_partial_audit.gd` / `.json` / `.log` (exit 0). Preserve the now-working bottom-layer migration and carry its disclosure into the existing top-level restore report, without polluting normalized gameplay snapshot warnings. This requires no reconstruction of absent old history and no blanket support for every prototype version.

## Reproduce

All scripts run under the reviewed game root:

```powershell
$engine='D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path ./game_v17 --script '<absolute path to audit.gd>'
```

`review65_probe.gd` and `saturated_comms_audit.gd`: `SOL65_MODE=quick`, `A07_HEAD` set to the reviewed 40-char SHA. `tws_null_audit.gd`: `R7_NULL_OUT` points to output JSON. `legacy_partial_audit.gd`: `R6_LEGACY_OUT` points to archived `c55_valid_save.json`, `R7_LEGACY_RESULT` points to result JSON. The reused original scripts retain old “R6” log labels; actual executing HEAD and engine are recorded above and in `audit_results.json`.

Resource cleanup warnings/errors at engine exit are retained in logs. The concrete null-history SCRIPT ERROR is distinguished from those existing cleanup diagnostics.
