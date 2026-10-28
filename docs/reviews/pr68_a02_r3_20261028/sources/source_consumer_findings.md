# PR68 R3 recheck — CLOSED

HEAD `755ab5ed629165656a566427523b01045775fc0f`; previous reviewed HEAD `4a658699868b8d046ec5472f9c4b9ea204af6be9`.

Only the original R3 real-HUD mapping chain and its entity-key / prefilled compatibility positives were executed. R1/R2/R5 were not rerun. Writes are confined to this new `.test-results/sol-a02-r3/sources/` directory; production, formal probes, matrix, baseline and old evidence were not edited.

Root import-ready was received first. Exactly **one** Godot diagnostic run completed, **exit 0**. Independent observations satisfy **13/13** bounded checks in `summary.json`; no formal probe was run by this audit. No SCRIPT ERROR or parse error appears. Fixture teardown reports 82 ObjectDB instances / 22 resources still in use.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a02-r3-validation/GHOST TRACK_APSIS/.test-results/sol-a02-r3/sources/source_consumer_audit.gd'
```

## Actual HUD proof

The diagnostic preserves the original fixture and chain: real radar `tick(6.0)` → Binder.refresh → **actual HUD._seed_combat_tracks()** → command-authorized manual friend for player_intel/raider_2 → Binder.refresh → actual request_fire for T0001 with target_entity=raider_2. The script calls radar at line 31, actual HUD method at 37, snapshots the empty mapping precondition at 45, confirms at 46, reads the no-hint consumer at 48, and requests fire at 51.

Observed `actual_hud_track_key`:

| Boundary | Value |
|---|---|
| Actual radar VM row | T0001; source radar; identity unknown; entity_id empty; range 602.400024414063 km |
| Session sensor map | raider_2 → T0001 |
| Combat row immediately after actual HUD seeding | T0001; entity_id empty; ship_id empty; identity unknown |
| Legal manual operational result | player_intel/raider_2; friend; confidence 1; valid; audit IDA-000001 |
| No-hint combat_identity(T0001), before fire | friend; source operational_identity; owner player_intel; resolved_key raider_2; via sensor_map |
| Actual T0001 combat row after request_fire | **friend**, entity_id/ship_id still empty |
| Entity-key positive | raider_2 consumer friend; combat row friend |
| Prefilled T0009 positive | friend; resolved_key raider_2; via combat_track; combat row friend |
| All fire responses | ok=false; needs_authorization=true; reason needs_authorization |

The original empty-field identity-consumer mismatch is closed. The result does not claim a projectile or bypass of the independent fire grant.

## Static mapping and owner review

- `game_session.gd:3139-3155` now reverses the existing session sensor map to stable physical entities, with physical-entity validation. Original entity/ship fields and same-name candidates remain supported.
- `game_session.gd:3009` passes request_fire's already-resolved physical entity into identity synchronization. `_identity_resolve_target` at 4231-4240 accepts that hint only when the supplied owner has an operational identity record.
- `combat_identity` at 4479-4485 still selects `_identity_own_owner()` and reads `identity_operational(owner,key)`. The sensor map supplies entity routing; identity comes from that owner record. No direct cross-owner identity read or new hidden-side inference was added in these mapping changes.
- The real HUD seeder remains `v1_hud.gd:2755-2764` and passes its global VM row as-is. This independent run proves that exact consumer with genuinely empty mapping fields.
- Updated formal R12 at `jc_identity_pipeline_probe.gd:411-419` now creates a real radar map, then registers an empty entity/ship row; it covers the missing empty-field condition. It still simulates the HUD row through register_track rather than invoking HUD._seed_combat_tracks. This diagnostic closes that coverage distinction by calling the real method. Compatibility checks remain at 443-450.

No directly proven mapping regression remains in the original R3 chain or its required positives. Stopped after closure; no additional range exploration or performance measurement was performed.
