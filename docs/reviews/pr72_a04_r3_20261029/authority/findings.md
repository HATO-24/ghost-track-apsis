# PR72 round 3: original R1 sender boundary

HEAD `563e97a61bc00d31104ad6db969edfe87f2fc25f`. One bounded run after root import-ready, exit 0, elapsed 3.1656084s. Exit 0 records successful diagnostic execution, not full acceptance. No GDScript parse/runtime errors or warnings were found in the log.

## Closed portions retained

The original transport fixture and registered-sender controls were reused. Actual public API results:

| Input | Result |
|---|---|
| own_ship + full player context | C-000001 accepted; DELIVERED exactly once at t2 |
| ally_ship + full ally context | C-000002 accepted; DELIVERED exactly once at t2 |
| ally_ship + full player context | rejected sender_context_mismatch; no delivery ID |
| enemy_ship + full player context | rejected sender_context_mismatch; no delivery ID |
| own_ship + full opfor context | rejected sender_context_mismatch; no delivery ID |
| unknown ghost_issuer + player context | rejected unknown_from |
| enemy_ship hold order + full player context | rejected sender_context_mismatch; empty order_id and no order after due |

Thus the three original explicit mismatch sends and the original explicit enemy/player order are closed. Normal independent own/player and ally/ally sends remain valid.

## Remaining R1 [P2]: fresh modern no-context sends are classified as legacy

The same seed explicitly contains all three command_domains and fleet_instances. The raw diagnostic records the actual player/ally/opfor authority domains and own_ship/ally_ship/enemy_ship instance mapping. Without load, replay, or an internal legacy-migration call:

| Fresh public send | Result |
|---|---|
| own_ship -> ally_ship, opts omitted | C-000001 accepted; DELIVERED once at t2 (positive) |
| ally_ship -> own_ship, explicit opts {} | C-000002 accepted; DELIVERED once at t2 (remaining boundary) |
| enemy_ship -> own_ship, opts omitted | C-000003 accepted; DELIVERED once at t2 (remaining boundary) |

`game_session.gd:3264-3271` classifies any opts without the six authority fields as legacy and returns success before inspecting the modern registered instance/domain. `comms_service.gd:601-607` calls that authorizer for a normal fresh send, so removing the mismatching context from the same registered foreign sender bypasses the newly added explicit-context rejection. The public modern call proves no authorized actor/controller/fleet/owner; merely omitting those fields does not establish that the seed or operation is legacy.

Keep true compatibility: the separate legacy-style seed omits command_domains and fleet_instances; its normal own_ship default-context send remains accepted and DELIVERED once at t2. Modern own default-context also remains a positive. The narrow correction should distinguish genuine legacy seed/log migration from fresh modern authority sends, while preserving authorized own defaults and explicit independent ally context. No blanket rejection of all old no-context operations is requested.

## Evidence boundary and command

Only original R1 was executed. The old ignore_ew case was removed from this diagnostic, not rerun. No R2/R3/R4, callback/recovery, no-context order/share delivery, or old-log replay conclusion is made. No authorize_order/begin_execute_order/complete_order/fire API was called; message delivery is not evidence of automatic execution or granted fire authority. No production, formal probe, matrix, baseline, or old evidence was modified. All agent-created files are in this directory.

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a04-r3-validation/GHOST TRACK_APSIS/.test-results/sol-a04-r3/authority/authority_audit.gd'
```

Raw inputs/results/events: authority_audit.json. Engine output: authority_audit.log. Exact exit: authority_audit.exit.txt. Run metadata: run.json. Compact extracted outcomes: summary.json. Diagnostic stopped after this one run.
