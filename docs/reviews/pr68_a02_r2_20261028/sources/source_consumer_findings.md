# PR68 second round: original R1 / R3 source-consumer recheck

HEAD: `4a658699868b8d046ec5472f9c4b9ea204af6be9`; main base: `1738a5e41509c09e04dc34da382dc07f4b8982e9`; first-round head: `7293058d1c0d3cdedceff1fae6233523e7f8b313`.

Result: **R1 CLOSED for the three original source-routing defects; R3 OPEN [P2] for the original real-HUD consumer mismatch.** No new production issue outside the original five groups was investigated. No production, formal probe, matrix, baseline, or GitHub edit was made by this audit.

## Execution and exact reuse

The original `source_consumer_audit.gd` was copied from the first-round tree. Only HEAD/comment and JSON output path were changed. All original fixture controls, assertions-by-observation, radar 6-second detection, actual producer paths, real `HUD._seed_combat_tracks`, and entity-key positive control remain unchanged. The original R2 cases also ran in this unchanged script; R2 disposition belongs to the separate authority audit.

Root sent import-ready before execution. This audit did not rerun any of the seven formal probes. The single effective diagnostic run exited **0**; this means completed observation, not acceptance. The initial relative-script launch exited 1 before script load because Godot resolved it below res://; the corrected absolute-script launch is recorded in `launch_attempts.json`.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a02-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a02-r2/sources/source_consumer_audit.gd'
```

Observed engine version: 4.7.2.stable.official.ed1daf0bf. No SCRIPT ERROR or parse error appears in the completed log. Multi-session shutdown retains the original fixture cleanup warnings (338 ObjectDB instances / 23 resources); no claim of a cleanup fix is made.

## R1 CLOSED: owner / reply deduplication / ELINT category

- Legal radar-established ally query: before and after `identity_iff_query('ally_intel','harmattan',{mode:'mode_s'})`, player remains `unknown_target`, unknown, no operational record and **0 raw evidence**. Ally receives **friend / confidence 0.75 / 1 evidence / valid**. No intel share/delivery occurs. This closes the original own-owner leak. The actual requested owner now reaches the flush at `game_session.gd:4310-4311`, is attached to evidence at 1915-1916, and is selected at 3852-3859.
- Default mode and explicit mode_s both produce **one normalized IEV-000001, mode_s, source=transponder, category=iff, confidence=1.0**, with operational **friend / confidence 0.75 / evidence_count=1**. Repeating explicit mode_s in the same tick stays **0.75 / 1**. The legal Binder player query also remains friend. This closes the original default-mode double-consumption and its confidence distortion. Owner event consumption is guarded at `game_session.gd:4046-4049`; successful queries use the actual producer evidence via `_identity_execute_iff` at 4302-4311, without the prior second success ingest.
- The actual SignalService emitter still emits **SEVD-000001 / evidence_type=elint / confidence=0.8**. The resulting IEV-000001 now preserves **source=elint / category=elint / evidence_type=elint**, with owner player_intel. This closes the original category collapse. Source mapping is at `game_session.gd:3890-3893`, bridge category use at 3868, normalization lookup at 3992-3993.

Evidence cases: `iff_ally_query_own_leak` (JSON line 741), `iff_default_double_route` (875), `real_signal_elint` (1827). The old sensor positive control also stays friend with one evidence before and after outbox flush (confidence 0.375 -> 0.355); optical remains source optical/category sensor, and hidden-side friend/hostile no-reply variants both remain unknown. These controls are observations within the original script, not extra acceptance coverage.

## R3 OPEN [P2]: real HUD T0001 still cannot resolve to owner entity identity

Exact unchanged trigger: default real radar tick 6s -> Binder refresh -> actual `HUD._seed_combat_tracks()` -> command-authorized `identity_manual_confirm('player_intel','raider_2','friend',{authority:'command'})` -> Binder refresh -> `request_fire('T0001','missile',true,{target_entity:'raider_2'})`.

Observed values (JSON case `actual_hud_track_key`, line 3):

| Boundary | Actual result |
|---|---|
| Real global TrackTable VM | one `T0001`, identity unknown, `entity_id=''`, radar, range 602.400024414063 km |
| Binder owner contact | raider_2, friend, manual=true, confidence 1 |
| Owner operational entity record | raider_2, friend, valid=true, effective_identity=friend, confidence 1, audited IDA-000001 |
| `combat_identity('T0001')` | unknown, source=combat_track, resolved_key='', valid=false |
| Actual combat T0001 after `request_fire` | identity unknown, entity_id='', ship_id='' |
| Fire return | ok=false, reason=needs_authorization, needs_authorization=true |
| Unchanged entity-key positive control | combat raider_2 projects to friend; its separate fire return also needs_authorization |

This is the original identity-consumer mismatch; **no actual launch or bypass of the independent fire grant is claimed**.

The new resolver's claimed sensor fallback at `game_session.gd:4255-4261` calls `_entity_for_track`. That helper (3138-3150) only considers combat entity_id, ship_id, or a same-named physical entity; it does not reverse the existing `_sensor_track_map` (real population at 1701). The real HUD consumer (v1_hud.gd:2755-2764) registers the global VM row as-is, whose identity mapping fields are empty in this fixture. Consequently the new resolver cannot map T0001 to raider_2 and `combat_identity` falls back at 4484-4490; `_sync_combat_identity` returns without projection at 4499-4501. The request's valid `target_entity` resolves physics but is not supplied to this identity resolution boundary (3007-3009).

The added formal R12 does not close this counterexample: `jc_identity_pipeline_probe.gd:411` manually calls `_register_combat_track(sR12,'T0001','raider_2')`. Its helper at 576-578 pre-fills both track_id=raider_2 and entity_id=raider_2; it does not call actual HUD._seed_combat_tracks. That covers the new explicit combat-field branch while omitting the real empty-field HUD row. No formal probe was changed or rerun here.

Stopped after the original counterexamples and controls produced their dispositions. Artifacts: source_consumer_audit.gd / .json / .log / .exit.txt, launch_attempts.json, this report, summary.json.
