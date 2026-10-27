# PR68 / JC-A02 independent source and consumer audit

Head: `7293058d1c0d3cdedceff1fae6233523e7f8b313`; base: `1738a5e41509c09e04dc34da382dc07f4b8982e9`.

Read original `docs/tasks/joint_campaign/JC-A02_identity.md` and both `game_v17/docs/next_cards/JC_A02*` delivery documents. Only wrote this audit's `.test-results/sol-a02/evidence/source_consumer_*` artifacts. Production, formal tests, probe matrix, baselines, and GitHub were not changed. Ran only after root's import-ready notification.

## Runtime evidence

`source_consumer_audit.gd` reuses the formal probe's seed helper, not its assertions or runner. Godot 4.7.2 headless executed the bounded diagnostic and completed with exit 0. `source_consumer_audit.json` contains complete observed records; `source_consumer_audit.log` contains engine output. Exit 0 means diagnostic completed, not that acceptance passed. The process reports ObjectDB/resource cleanup warnings at shutdown after using multiple fixture sessions; there are no GDScript parse/runtime errors.

To run from repository root:

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script './.test-results/sol-a02/evidence/source_consumer_audit.gd'
```

All IFF routing comparisons first tick a real radar for 6 seconds to establish an existing valid target track. An initial exploratory query without a detected track was correctly rejected by the legacy TrackTable evidence precondition; the final diagnostic uses the legitimate detected-contact positive and does not report that precondition as a bug.

## Confirmed defects

### 1. [P1] Existing Binder manual confirmation bypasses the new authorization and audit gate

Locations: `scripts/ui/shell_binder.gd:2090-2091`, `scripts/core/game_session.gd:4386-4393`, and the new forwarding path `game_session.gd:4301-4315`. New gate: `game_session.gd:4185-4194`.

Actual trigger: call the real `Binder.ident_confirm({entity_id: 'raider_2'}, 'hostile')`. It calls the old session wrapper, which directly invokes `IdentificationService.manual_confirm`; the next tick forwards that assessment into the operational writer. Result: `identity=hostile`, `authorized=true`, `manual=true`, confidence 1, and both identity audit / audit_ids empty. The same authority string `cic_operator` is rejected as unauthorized by the new owner API. The still-public old session wrapper also accepts `identification_manual_confirm('raider_2', 'hostile')` with no authority and forwards an authorized hostile result after one tick.

The immediate real Binder view reads hostile from the old assessment fallback while combat/operational identity is still unknown. After tick both read hostile; no audit is added. Binder clear similarly changes the old calculator immediately but leaves the operational/HUD result hostile until another tick. This is a live UI path, not merely a test-only direct service call.

Evidence JSON cases: `binder_manual_old_route`, `legacy_manual_no_authority`.

### 2. [P1] An ally IFF query leaks its reply into player operational identity

Locations: `game_session.gd:4134-4139` calls `_flush_transponder_outputs` without owner context; `game_session.gd:1915-1918` bridges successful evidence; `game_session.gd:3841-3845` unconditionally selects the own/player owner. The explicit requested-owner ingest happens only afterward at `game_session.gd:4158-4165`.

Actual trigger: real radar detects harmattan; player has no identity evidence; call `identity_iff_query('ally_intel', 'harmattan', {mode: 'mode_s'})`. No intel share or delivery is performed. Result: player is nevertheless written `friend` / confidence .75 / 1 evidence, while ally gets `friend` / .375 / 1 evidence. This violates owner isolation through a normal transponder-service reply. A player-side detected track is only a geometric observation, not authorization to receive the ally query's identity evidence.

Legal control: real `Binder.ident_interrogate(..., 'mode_s')` for the player also uses the producer output route and correctly writes player friend. The defect is the unconditional owner choice when the requested query belongs to another owner.

Evidence JSON cases: `iff_ally_query_own_leak` and `iff_default_double_route.binder_legal_*`.

### 3. [P2] Real HUD combat track keys do not resolve to the operational entity identity

Locations: new `game_session.gd:4238-4251` and `4256-4268`, especially `combat_identity(target_id)` using the combat track ID directly. Existing real consumer: `scripts/ui/v1_hud.gd:2755-2764` seeds combat from Binder's global TrackTable VM.

Actual trigger: radar creates global track `T0001` for raider_2; call the real HUD `_seed_combat_tracks`; make a legitimate command-authorized `identity_manual_confirm('player_intel', 'raider_2', 'friend', ...)`; refresh Binder; call real `session.request_fire('T0001', 'missile', true, {target_entity: 'raider_2'})`.

Observed: Binder contact/HUD and entity-keyed operational record say friend, but the combat track remains unknown and `combat_identity('T0001')` reports `{identity: unknown, source: combat_track}`. `_sync_combat_identity` never resolves the supplied target's entity identity. The fire request reaches the ordinary `needs_authorization` gate; this diagnostic does not claim an actual projectile or bypass of the separate fire grant.

Legal control: register a combat track under the entity key `raider_2`, then call the same fire boundary; that combat track is correctly projected to friend. The formal probe manually registers under that entity key, so its consumer equality assertions do not exercise the real `T0001` path.

Evidence JSON case: `actual_hud_track_key` (actual track list, HUD contacts, fire result, same-ID control).

### 4. [P2] Default IFF query consumes one physical reply twice with different mode/confidence

Locations: `game_session.gd:4133-4139`, `4158-4165`; actual evidence mode is retained by bridge `3844-3853`, while the second route uses requested mode (empty by default) and hardcoded confidence .5. Service dedup key includes mode at `identification_service.gd:152-156`.

Actual trigger: existing detected harmattan; call `identity_iff_query('player_intel', 'harmattan')`. The real transponder defaults to mode_s and emits confidence 1. The bridge creates IEV-000001 with mode_s, then the query creates IEV-000002 with empty mode and confidence .5 from the same reply. Result: 2 evidence records and confidence .563. Explicit `{mode: 'mode_s'}` consumes only 1 record and confidence .75. Repeating explicit mode_s in the same tick keeps count 1 and confidence .75.

This is a confirmed double-consumption / conclusion-distortion bug. In this legitimate positive it lowers confidence, so it must not be described as observed confidence inflation. The ordinary sensor IFF direct-result plus later outbox route is deduplicated correctly in the bounded comparison.

Evidence JSON case: `iff_default_double_route`.

### 5. [P2] Real ELINT evidence is normalized into the IFF category

Locations: `game_session.gd:3852`, default fallback `3973-3974`. The reused calculator's intended source mapping at `identification_service.gd:23-26` maps ELINT to category elint, separate from iff.

Actual trigger: boot the existing SignalService with the known YW-R9 emitter fixture, then tick. Real source SEVD-000001 has `evidence_type=elint`, fingerprint search-radar, confidence .8. After the real signal flush and bridge it is IEV-000001 with `source=elint` but `category=iff` and `evidence_type=iff`. This collapses ELINT and IFF into one evidence category before the existing calculator's independence/confidence logic. No new EW behavior or faction inference is needed to preserve the existing source category.

Evidence JSON case: `real_signal_elint`. Runtime proves the erroneous normalized category; the resulting mixed-IFF independence effect is a direct inference from calculator category use at `identification_service.gd:354-365`, not separately measured here.

## Passed bounded controls and coverage observations

- Actual sensor IFF with a visible active declaration plus an already detected track produces friend through the owner calculator and operational/HUD/consumer helper. Its direct response and later outbox flush stay at one normalized evidence record; the next tick confidence decays normally (.375 to .355), without inflation.
- Actual optical channel reaches a classified/locked result and produces a real optical evidence record, then normalized source optical/category sensor and an operational record. Producer identity remains unknown; that conservative unknown is not itself a defect.
- Actual SignalService emits real ELINT evidence and reaches the operational/HUD helper; its unknown identity is not itself a defect. The category loss is listed separately above.
- With transponder off, otherwise identical target rows with hidden side friend versus hostile both return and retain unknown. No hidden-side identity leakage was seen in this bounded normal no-reply control.
- These results do not prove all fields or all source orderings. Formal coverage should follow the actual Binder action, real transponder reply owner, and actual HUD-generated T0001 combat key. Existing direct new-API equality checks alone miss those live-path defects.
