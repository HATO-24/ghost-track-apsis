# PR68 JC-A02 TTL / late evidence / restore diagnostic

Revision under review: `7293058d1c0d3cdedceff1fae6233523e7f8b313`.

This custom diagnostic was rerun once after correcting the late-evidence time premise. All late/order evidence now uses non-negative observed times with both sessions first ticked to `t=2`: new evidence `(observed=2, received=2)`, older evidence `(observed=1, received=2)`, both TTL 20. Every ingest returned `ok=true`. No production or formal test code was changed, and no formal test/probe was rerun. The diagnostic command exited 0 and printed `JC-A02 IDENTITY PIPELINE PROBE OK`; inherited counters are `PASS=0 FAIL=0`, so this is a custom observation probe, not an assertion suite. Godot shutdown emitted ObjectDB/resource leak diagnostics after the report was written.

## Findings

### F1 — TTL age starts at observation, but validity is not consumed consistently

The code ages from `identity_observed_t` (`game_session.gd:4094-4103`). Delayed-arrival control: now/received time 8, observed time 0, TTL 5 returns facade fields `identity_age_s=8`, `identity_state=stale`, yet `identity=friend` and alias `state=valid`. At 11 ticks from the original observed time, the owner result has `identity_state=expired`, age 11, confidence `0.322`, but still `identity=friend`. The consumer reads also remain `friend`: `combat_identity`, the synchronized combat track, and HUD `ident_view` (`game_session.gd:4238-4266`, `shell_binder.gd:1996-2021`). CombatService's downstream decisions inspect the copied identity field (`combat_service.gd:253-258,300-301`), not the expired validity state.

The alias mismatch is localized: `state` is copied at `game_session.gd:4087`, before the TTL branch changes `identity_state` at `4099-4103`. This confirms an inconsistency in the returned facade. The diagnostic establishes that stale/expired metadata is not consumed as validity by HUD/fire-control identity reads; it does not prescribe that every expired identity must become `unknown`. The implementation needs an explicit TTL validity/confidence policy that reaches the intended consumers, rather than only attaching a label.

### F2 — Late evidence is tagged ignored, but the next tick routes it (bug)

Both sequences began at simulation time 2 with the same valid records, all observed/received timestamps non-negative and within TTL:

- New-first: optical friend `(2,2)` is accepted and becomes operational friend. Then transponder hostile `(1,2)` is accepted with `late_ignored=true`; its service assessment already contains both records and reports conflict. The immediate operational record remains friend. On the next tick it changes to suspect/conflict, confidence `0.386`, evidence_count 2.
- Old-first control: transponder hostile `(1,2)` and then optical friend `(2,2)` are both accepted with `late_ignored=false`; the immediate operational result is suspect/conflict. After one tick it remains suspect/conflict at confidence `0.386`.

Thus identical valid evidence eventually converges, but the late path has a different immediate conclusion and the `late_ignored` evidence contaminates the next-tick result. `identity_ingest` calls `svc.ingest(env)` before branching on `late` and skips only the immediate route (`game_session.gd:3992-4012`); `_identity_advance_owners` later routes the full service assessment (`4301-4317`). A narrowly scoped repair should prevent ignored late evidence from entering the assessment that will be routed, while retaining its audit record.

Earlier diagnostic data used observed time -1. That was not a valid simulated-time counterexample and is not used in this finding or the current result JSON.

### F3 — Real-file owner restore and 10-tick continuation passed; pending lifecycle not tested

The diagnostic saved to an actual `user://` file, loaded it into a new session, then compared the source and restored `ally_intel` calculator for ten paired ticks. Restore mode was `full`, and the owner calculator was present. Event IDs matched exactly from `ID-EV-000003` to `ID-EV-000012`; identity, state, and confidence matched on each tick. Both traces naturally crossed TTL 5 at tick 6 and became stale; tick-10 confidence was `0.273` on both.

The `Q-DIAG-1` pending query row was manually inserted directly into `_identity_pending_queries` solely to verify that the dictionary survives serialization. This is only a pending-query serialization positive example; it does not verify that a real pending query is created, consumed, or otherwise follows its runtime lifecycle.

This covers one non-own owner and one evidence stream; it does not establish malformed/legacy payload behavior.

## Artifacts

- `diag.gd`: custom diagnostic script extending the existing probe's setup/seed helpers.
- `result.json`: full TTL, corrected late/order, and file-restore data.
- `run.log`: output from the single corrected rerun.

## Workspace status note

`git status --short` after the Godot run also showed generated metadata outside this output directory: modified `.import` files under `game_v17/assets/` and untracked `.uid` sidecars under `game_v17/`. Their timestamps coincide with the engine import/run window. I did not edit or remove them because the worktree's pre-run status was unavailable and some may belong to the preceding import-ready pass.
