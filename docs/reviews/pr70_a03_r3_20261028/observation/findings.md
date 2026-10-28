# PR70 third round: original R2 CLOSED

HEAD `022a7e0e6b0ab2ce65f228f98b4a1146d18792f8`; preceding reviewed HEAD `ea29da7138ad353c4198f76547f57c4e0b07142d`.

**Original R2 is CLOSED.** The owner-rejection residual no longer writes global TrackTable or the sensor map. Previously closed exact-replay, nonempty candidate, and legitimate own/ally new-observation controls remain green.

Only this new `.test-results/sol-a03-r3/observation/` evidence was written. No production, formal probe, matrix, baseline or old archive was modified. No formal/full run, firing request, RF-model or generalized transaction investigation was performed.

## Static boundary

`game_v17/scripts/core/game_session.gd:2657-2662` captures owner refusal/duplicate. The new narrow guard at **2664-2669** records the rejected attempt and returns before the TrackTable write at2675 or sensor map assignment at2682. Normal accepted entries continue through the existing measurement/combat/candidate/accepted-history pipeline. No broad implementation requirement was added.

## Same runtime counterexample and retained positives

The previous round's complete `replay_audit.gd` was reused unchanged except HEAD, output directory and output marker. It calls the same real producer fixture and the same intentional boundary injections; no assertions or source fields were weakened.

| Original control | Observed result |
|---|---|
| Owner-rejected misaddressed entry | Actual OBS-000008 snapshot; change only owner_id to ally_intel, retain observer own_ship/no share. At t7, rejection remains **share_not_authorized**; global TrackTable **0 -> 0**, map **{} -> {}**; player/ally observations0; measurement unavailable; accepted audit0 -> 0; rejected audit0 -> 1 |
| Exact OBS-000008 replay | Capture actual delayed entry observed7/q.7; natural delivery, normal EW expiration/recovery, once unchanged replay. Current owner and registered combat quality remain **.90849375@21**, degraded=false; combat cache unchanged; owner observations and accepted audit **19 -> 19**; rejection reason **duplicate_delivery** |
| Nonempty real candidate replay | Actual apply_ew(deception=.6), naturally delivered candidate-bearing entry, once unchanged replay. Candidates **1 -> 1**, identity evidence unchanged, owner/combat quality **.82@1** unchanged, accepted audit **1 -> 1**; rejection reason duplicate_delivery |
| Normal own new observations | Normal continuation grows **10 -> 19** owner observations |
| Normal ally new observations | Registered ally observer between t6 and t11 grows **1 -> 4**, player remains0; no rejects |

The owner-rejection setup is the same explicit misaddressed-message control as the previous round: fresh receiver, legitimate radar disable, tick to t7, then reuse the captured real entry with only its recipient owner changed. It does not claim that an untouched normal run misroutes its own observations.

For **each** of the three rejection/replay cases, exact before/after JSON equality passes for ten fields: player measurement, combat row, combat-quality cache, candidate list, identity evidence, accepted-delivery history, player observations, ally observations, sensor map and the full global TrackTable VM. Only the separate rejection-attempt audit grows. See summary.json for every comparison. This closes the earlier globalTrack0 -> 1 / map creation as well as preserving the already-fixed measurement rollback.

## Run record

Root confirmed tree/import-ready before execution. Exactly **one** bounded Godot run completed, **exit0**. No extra fixture repair or repeat run was required. Raw input and all before/after snapshots: replay_audit.json; engine output: replay_audit.log; exit: replay_audit.exit.txt.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a03-r3-validation/GHOST TRACK_APSIS/.test-results/sol-a03-r3/observation/replay_audit.gd'
```

Godot4.7.2.stable.official.ed1daf0bf. No GDScript parse/runtime error appears. The unchanged multi-session fixture teardown reports142 ObjectDB instances /22 resources still in use. These cleanup messages are retained in the raw log. No remaining original R2 failure was found; stopped after closure.
