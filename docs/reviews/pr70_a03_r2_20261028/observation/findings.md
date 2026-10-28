# PR70 second round: original R2 full-delivery-boundary audit

HEAD `ea29da7138ad353c4198f76547f57c4e0b07142d`; prior reviewed head `6bd919aa19898bbf31f5dd7c3287befc47392877`.

**CLOSED:** the original real OBS-000008 replay no longer rolls back measurement or combat quality, duplicates candidates, or increments accepted-delivery history. **OPEN [P2], same acceptance boundary:** an owner-rejected misaddressed delivery still creates a global TrackTable row and sensor target mapping before the rejection return.

No production/formal probe/matrix/baseline/old evidence was changed. Writes are only under this new `.test-results/sol-a03-r2/observation/`. No formal/full run or fire request was performed. No new fire-gating, RF-band, receiver-model or transaction-system requirement is proposed.

## Closed: exact old replay and required side effects

`replay_audit.gd:31-49` retains the original real source fixture and sequence: clean ticks2 -> apply noise=.5 -> wait for an actual delayed entry -> capture immutable **OBS-000008 / observed_t=7 / quality=.7** -> normal delivery -> explicit EW expire -> five normal ticks -> exactly one unchanged replay at the production delivery boundary. A registered combat entity row was added only to observe the already-existing quality projection; no firing was requested.

At t21, both before and after replay:

- owner measurement **.90849375 / measurement_t=21 / degraded=false**, aggregate1;
- actual combat track measurement **.90849375 / measurement_t=21**, and combat quality cache unchanged;
- player owner observation count **19 -> 19**, ally0;
- accepted-delivery audit **19 -> 19**, candidates0, identity evidence unchanged, sensor map unchanged;
- rejected-delivery audit **0 -> 1**, reason duplicate_event. A separate rejection record is permitted and is not classified as duplicate accepted fusion.

Exact JSON equality is true for all nine checked operational/accepted-history fields in summary.json. This closes the original .90849375@21 -> .7@7 regression. The fix must be retained.

A nonempty real deception-candidate control (`replay_audit.gd:51-61`) also passes: source noise fixture changed through normal apply_ew(effect=deception,severity=.6), actual candidate-bearing queue entry naturally delivered, then replayed once. Candidate list **1 -> 1**, identity evidence unchanged, measurement/combat **.82@1 unchanged**, accepted audit **1 -> 1**, owner observations **1 -> 1**; only rejection audit grows0 -> 1. This verifies candidate deduplication with a genuinely nonempty producer result.

Normal new observations remain accepted: own-owner history grows **10 -> 19** across normal continuation; the separate registered ally observer control grows **1 -> 4** between t6 and t11, while player observations remain0 and no rejects occur. The result is not achieved by discarding all new observations.

## Remaining [P2]: owner rejection still mutates global TrackTable and target map

Primary location: **game_v17/scripts/core/game_session.gd:2662-2674**; rejection occurs at 2656-2658, but the early return is deferred until 2675-2680.

Bounded control (`replay_audit.gd:71-82`): use a fresh same-seed receiver, legitimately disable radar via SensorService.set_radar_enabled(false), and tick to t7. Preconditions: global TrackTable count0, sensor map empty, neither owner has an observation/measurement. Reuse the actual captured OBS-000008 snapshot, change **only owner_id to ally_intel**, retain its actual observer_id=own_ship and all source fields, and deliver once without share authorization. This is explicit misaddressed-message injection at the original acceptance boundary, not a claim that normal observer routing misaddresses its own entries.

Observed result:

| Boundary | Before -> after |
|---|---|
| Owner intake | rejected share_not_authorized |
| Player / ally owner observations | 0 / 0 -> 0 / 0 |
| Player / ally measurement | unavailable -> unavailable |
| Accepted EW delivery audit | 0 -> 0 |
| Rejected delivery audit | 0 -> 1, share_not_authorized |
| **Global TrackTable count** | **0 -> 1 (T0001)** |
| **Sensor target map** | **{} -> {raider_2:T0001}** |

The new accepted flag correctly protects measurement/combat/candidates/accepted audit, but it is checked only after the global observation write and map assignment. `_deliver_ew_observation` calls receive_observation at 2645, sets accepted=false on owner refusal at 2656-2658, still calls handle_observation at 2667 and writes the map at 2674, then returns at 2680. Stop rejected owner deliveries before these writes, or provide an equivalent narrow acceptance guard. This does not require a general transaction architecture.

Preserve the closed exact-replay/candidate controls and legitimate own/ally new observations while closing this remaining original-boundary side effect.

## Command / status

Root import-ready was received before execution. Exactly **one** bounded Godot run completed, **exit0**. Exit0 means the diagnostic completed; the remaining rejection-side-effect control still fails acceptance. Raw input/before/after snapshots are in replay_audit.json; stdout is replay_audit.log; the exit code is replay_audit.exit.txt.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a03-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a03-r2/observation/replay_audit.gd'
```

Engine4.7.2.stable.official.ed1daf0bf. No GDScript parse/runtime error appears. Fixture teardown reports142 ObjectDB instances /22 resources still in use. Stopped after these original R2 controls; no further testing was performed.
