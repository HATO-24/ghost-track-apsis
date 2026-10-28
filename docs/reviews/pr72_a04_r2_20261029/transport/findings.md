# PR72 second round: original transport R1/R2 remain OPEN

HEAD `bc0b8bb258ae78f4bcc5da87ee4ca0868a3aee72`; preceding head `1de99a85c4f69dca706509648450487197523ab5`.

This run repeats only the original registered-sender context and ordinary ignore_ew counterexamples, plus their existing normal controls. The original transport_audit.gd was copied unchanged except HEAD/output path. No callback/share/due/recovery diagnostic or new counterexample was added. No production/formal probe/matrix/baseline/old evidence was modified; writes are only in this new evidence directory.

## R1 [P2] OPEN: registered sender/context mismatch

The new production diff does not change sender authorization in Session.send_comms / issue_order or the direct Comms node checks. Repeated real public API outcomes:

| Sender/context | Result |
|---|---|
| own_ship/player | C-000001 accepted and DELIVERED at t2 |
| ally_ship/ally | C-000002 accepted and DELIVERED at t2 |
| ally_ship/player | **C-000003 accepted and DELIVERED at t2** |
| enemy_ship/player | **C-000004 accepted and DELIVERED at t2** |
| own_ship/opfor | **C-000005 accepted and DELIVERED at t2** |
| unknown ghost_issuer/player | rejected unknown_from |

The original enemy_ship→own_ship hold order with explicit player actor/controller/domain/fleet/owner context is again accepted and reaches **QUEUED** after due. No authorize/begin/complete action was called; this is not evidence of automatic execution or granted fire authority. Matching own/player and independent ally/ally contexts remain legal positive controls.

Location: `game_session.gd:3107-3114` still forwards normal opts without checking sender-domain authority; `comms_service.gd:567` onward validates node existence, not the supplied authorized context. Original R1 is unchanged, not a new scope.

## R2 [P2] OPEN: ordinary ignore_ew bypass

Actual active comms_jam=.5 / duration120, same base-latency2 route and normal player context:

- Normal C-000001 freezes **base2 + EW20 =22s**, failure_chance=.4, draw=.1, will_fail=true.
- Ordinary send with opts.ignore_ew=true creates C-000002 with **total2s**, EW add0, failure_chance0, ignored=true, draw=-1; it actually DELIVERS at t2.
- Expire the live effect only after t2: normal C-000001 still actually FAILS/comms_jam at t22. This retains the verified send-time freezing behavior.

`comms_service.gd:606` still reads the ordinary caller option and `_sample_ew_for_send:544-545` still returns an all-zero snapshot on that flag. The legitimate v1 replay still sets the same key internally at `game_session.gd:6684`; that migration capability must remain, while ordinary sends must not control it. No player UI bypass was claimed.

## Run record

Root import-ready preceded execution. Exactly **one** minimal Godot run, **exit0**; no formal/full probe run by this agent. No GDScript parse/runtime errors appear. Exit0 means records were written, not acceptance. Raw actual inputs/results/events: transport_audit.json; engine output: transport_audit.log; exit: transport_audit.exit.txt; compact results: summary.json.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a04-r2-validation/GHOST TRACK_APSIS/.test-results/sol-a04-r2/transport/transport_audit.gd'
```

Stopped after confirming both original residuals and retained positives. No conclusions about this round's callback or recovery changes are made here.
