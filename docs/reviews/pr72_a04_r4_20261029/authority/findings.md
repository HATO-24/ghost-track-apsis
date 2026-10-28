# PR72 round 4: original R1 modern no-context sender boundary CLOSED

HEAD `af924d09f5c1d763f8d2556cd94062134ef3c456`. Root import-ready preceded the single bounded Godot run. Exit 0, elapsed 3.1818354s; no parse/runtime errors or warnings found in the log. Exit 0 means the diagnostic completed; final A04 acceptance remains with root's full review.

The previous round's authority script was reused, changing only HEAD/output directory and adding pending snapshots. No new counterexample, fuzzing, or R2/R3/R4 diagnostic was run.

## Exact outcomes

| Same modern authority seed: fresh public call | Result |
|---|---|
| ally_ship + explicit opts {} | rejected sender_context_required; empty delivery_id; no foreign pending/SENT/DELIVERED |
| enemy_ship + opts omitted | rejected sender_context_required; empty delivery_id; no foreign pending/SENT/DELIVERED |
| own_ship + opts omitted | C-000001 accepted; DELIVERED exactly once at t2 |
| own_ship + full player context | C-000001 accepted; DELIVERED exactly once at t2 |
| ally_ship + full ally context | C-000002 accepted; DELIVERED exactly once at t2 |
| ally_ship + full player context | rejected sender_context_mismatch |
| enemy_ship + full player context | rejected sender_context_mismatch |
| own_ship + full opfor context | rejected sender_context_mismatch |
| unknown ghost_issuer + player context | rejected unknown_from |
| enemy_ship hold order + full player context | rejected sender_context_mismatch; empty order_id; no order after due |
| genuine legacy-style seed own_ship + opts omitted | accepted; DELIVERED exactly once at t2 |

The no-context case still explicitly contains command_domains and fleet_instances, and records the actual authority map. Its pending snapshot at send contains only the allowed own C-000001; pending at t2 is empty. Combined foreign SENT/DELIVERED count is 0. This closes the original third-round residual while retaining the existing positives and explicit mismatch rejections.

## Static boundary

`game_session.gd:3325-3346` now checks modern seed/registered sender/own domain before deciding legacy or permitted own default; foreign modern no-context sends return sender_context_required. Genuine old seed and `_replaying` are separate paths.

`_derive_share_context` at 3259 uses the existing A01 original-owner share authorization anchor for queue_intel_share only. It does not authorize ordinary send/order defaults. The existing A01 receive path (`authority_intel.gd:292-306`) still checks original observer owner authorization and actual delivery. This read does not introduce crypto/authentication or AI requirements. No new share-delivery diagnostic or old-log replay was run here; their prior evidence and root's current formal checks remain separate.

No authorize_order/begin_execute_order/complete_order/fire API was called. No automatic execution or granted fire authority is claimed. Production, formal probes, matrix, baseline, and old evidence were not modified by this agent. All agent-created files are within this directory. Stopped after this one run.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a04-r4-validation/GHOST TRACK_APSIS/.test-results/sol-a04-r4/authority/authority_audit.gd'
```

Files: authority_audit.gd, authority_audit.json, authority_audit.log, authority_audit.exit.txt, run.json, summary.json.
