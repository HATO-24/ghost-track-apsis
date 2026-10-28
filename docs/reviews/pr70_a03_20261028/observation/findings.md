# PR70 / JC-A03 observation, owner, current quality and replay audit

HEAD `6bd919aa19898bbf31f5dd7c3287befc47392877`; PR implementation base `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`.

Result: **one confirmed P2 duplicate-consumption defect**. Natural observer-to-owner routing, abstract target/kind exclusion, EW multiplier and current/history quality separation passed the bounded controls. Observer-scoped effect and RF-band exclusion remain unproven because the current supported sampler interface has no such receiver context.

Read the A03 task card, writer_reader_matrix, delivery report, and production diff. Diagnostics reuse only the formal A03 seed fixture, not its assertions or runner. Only `.test-results/sol-a03/observation/` artifacts were written; production, formal probes, matrix, baseline and GitHub were not edited. No A04/AI/real RF investigation was performed.

## Confirmed [P2]: repeated EW delivery overwrites current measurement after the base stores deduplicate it

Primary location: `game_v17/scripts/core/game_session.gd:2657-2668`; relevant upstream calls at 2640-2656. `receive_observation` returns `duplicated=true` at `authority_intel.gd:338-340`, but the new delivery function discards its return. It also proceeds after TrackTable rejects `duplicate_event`. It unconditionally calls apply_measurement and the own-owner combat-quality updater.

Bounded trigger in `replay_audit.gd:4-29`:

1. Use the unchanged real Sensor fixture. Tick clean 2s, apply legitimate noise_jam=.5, and wait for an actually emitted delayed entry. Capture its immutable queue snapshot **OBS-000008 / observed_t=7 / quality=.7**. Do not invent its fields.
2. Let normal ticks deliver it, then explicitly expire EW through the service API and run five normal ticks. At t=21, current measurement is **.90849375 / measurement_t=21 / degraded=false**.
3. Redeliver that exact previously delivered snapshot once through the real production `_deliver_ew_observation` boundary (`replay_audit.gd:23`). This is an intentional message-replay injection; it is not a claim that an untouched normal run produces duplicates by itself.

Observed after the one replay:

| Consumer/store | Before → after |
|---|---|
| Owner observation history count | 19 → 19; base owner intake deduplicates |
| TrackTable result | explicit rejected / reason=duplicate_event |
| Owner current measurement | **.90849375 @ t21 → .7 @ t7**, degraded becomes true |
| New EW delivery audit count | 19 → 20 |
| Historical aggregate | remains 1 |

Thus the new operational measurement writer consumes a duplicate that the authority/TrackTable stores already reject. It can restore an obsolete jammed value after recovery and changes the quality that later fire-control boundaries read. An accepted-once gate must cover the new measurement/combat/candidate side effects as well as old fusion. No fire-control experiment was run in this agent's scope.

Evidence: `replay_audit.json` (complete input snapshot and before/after), `replay_audit.log` (compact observed values and explicit duplicate_event). The unmodified natural phase had **10 deliveries / 10 unique observation IDs**; no natural double delivery was observed in this bounded run.

## Passed bounded controls

All controls use real GameSession.apply_ew → tick → Sensor sampling → normal owner delivery, without directly writing a measurement.

| Control | Result |
|---|---|
| EW off, own_ship observer | player q=1, multiplier1, delay0; ally has no measurement |
| noise=.5, own_ship observer | first raw q1 → effective .7, delay3; delivered owner=player_intel, observer=own_ship; ally has no measurement |
| Same fixture with registered ally_ship observer | ally q=.7; delivered owner=ally_intel, observer=ally_ship; player has no measurement |
| Physical but unregistered observer | neither player nor ally gets a measurement; no fallback to player owner |
| Effect aimed at other_target | actual raider_2 q1, multiplier1, delay0 |
| noise effect restricted to optical target_kinds | actual radar q1, multiplier1, delay0 |
| Clean history then jammed current | aggregate=1, current=.48825 from actual raw .6975 × .7; historical max does not replace current measurement |

The explicit noise coefficient remains .7 within the required tolerance. Later raw sensor/TWS quality changes are preserved and multiplied once; the .48825 value must not be described as a hardcoded expected .7.

## Observer and frequency-band acceptance limit

`_advance_sensors` derives obs_owner from the actual observer (`game_session.gd:1525-1527`), and the queue retains that owner and the full observation snapshot. Normal owner isolation above passes. The sample audit record itself omits observer/owner identifiers; they remain available in the queue/delivery owner and owner observation row.

However `_ew_sample_for` at `game_session.gd:2555-2558` queries only `(target_id,sensor_kind)`. EW `_max_sev` at `ew_service.gd:373-385` filters only effect type, target and target_kinds; apply stores band at 154 but never matches it. There is no supported affected-observer/owner or receiver-band argument on this sampling path. Changing only the accepted effect label band=X to band=S produces identical real samples (.7, 3s). The sensor model does not provide a supported receiver band declaration, so this audit **does not claim an independently measured X-vs-S mismatch against a known receiver**. The card's required wrong-observer/band exclusion cannot be marked passed; abstract target/kind filtering is a narrower verified property.

## Commands and run status

Root import-ready was received before any Godot execution. Two bounded diagnostics completed, both exit **0**; no formal probe was run by this audit. Exit 0 means observation completed, not that acceptance passed. The first diagnostic's attempted replay was skipped because its t3 capture preceded the next real radar sample (first scan t1, next t7). The second waits for a real queue entry and supplies the confirmed replay result; the first skipped case is not used as evidence of successful deduplication.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/observation/observation_audit.gd'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a03-validation/GHOST TRACK_APSIS/.test-results/sol-a03/observation/replay_audit.gd'
```

Engine: 4.7.2.stable.official.ed1daf0bf. No GDScript parse/runtime error appears in either completed log. Fixture teardown retains ObjectDB/resource cleanup warnings. Stopped after the bounded controls and confirmed duplicate defect; no broader test or performance measurement was added.
