# PR72 / JC-A04 transport and sender-boundary audit

HEAD `1de99a85c4f69dca706509648450487197523ab5`; base `4e4f90f9eb4964503a61dd915cb1c445294b10a5`.

Two bounded **P2** acceptance defects are confirmed: the ordinary ignore_ew option bypasses active EW, and registered sender identities are accepted despite explicitly foreign caller/controller/fleet/owner context. Normal fixture and send-time freezing work in the legal control.

This audit read the original A04 task card, delivery report and production diff. It reused only the formal probe's seed helper, not its assertions or runner. Root sent import-ready before execution. Exactly one diagnostic run completed, **exit0**; no formal/full probe was run by this agent. Only new `.test-results/sol-a04/transport/` artifacts were written; production, formal probes, matrix and baseline were not modified. Root's authority agent owns successful-share/due tests, which were not duplicated here.

## [P2] Ordinary send opts.ignore_ew bypasses the actual EW channel

Locations: `comms_service.gd:599` passes caller-controlled opts.ignore_ew into the sampler; sampler `539-545` returns all-zero EW immediately. `game_session.gd:3107-3114` normalizes and forwards ordinary public send options without a replay-only boundary. The legitimate v1 migration uses this same option at `game_session.gd:6683`.

Exact legal control: real session.apply_ew(comms_jam=.5,target=ally_ship,duration120), player-owned sender with matching actor/controller/fleet/owner context, a real route with base latency2, and test-only fixed draw=.1. Normal send C-000001 records **base2 + EW20 = total22, failure_chance=.4, draw=.1, will_fail=true**.

While the same jam is active, the same ordinary send API with only opts.ignore_ew=true produces C-000002 with **base2 + EW0 = total2, failure_chance=0, draw=-1, ignored=true**. At t2 it receives an actual DELIVERED event and Session comms.delivered callback. There is no legacy load/replay in this case. An internal migration switch has become a normal-message bypass.

Retained positive: explicitly expire EW only after t2. The original C-000001 still reaches **FAILED/comms_jam at t22**, not DELIVERED. This proves the normal path's send-time effect and failure result remain frozen correctly after the live effect changes. Restrict migration behavior to a trusted replay/internal path while preserving that positive and v1 compatibility; no new UI option or RF model is needed.

Evidence: JSON case `ordinary_ignore_ew_option`; summary.json records both send snapshots and real result events. Test draw injection is used only to make the normal positive deterministic; the bypass itself does not consume that draw.

## [P2] Node existence is treated as sender authorization despite mismatched caller domain

Locations: `game_session.gd:3107-3114` directly calls Comms.send with no caller-to-sender check. Comms.send at `560-568` checks only whether from/to nodes exist. Its outgoing record does not validate actor/controller/fleet/owner against the sender domain. The order entry similarly forwards to draft/issue (`game_session.gd:3029`, `order_service.gd:246`), where opts caller context is not validated or retained as authority.

The seed registers player_ctrl/player_intel/own_fleet, ally_ai/ally_intel/ally_fleet and opfor_ai/opfor_intel/enemy_fleet with their actual ship instances. The diagnostic passes all six explicit caller-context fields: actor_id, controller_id, domain_id, fleet_id, owner_id and intel_owner_id.

| Sender / supplied context | Actual result |
|---|---|
| own_ship / matching player | accepted, C-000001 DELIVERED at t2 |
| ally_ship / matching ally | accepted, C-000002 DELIVERED at t2 |
| **ally_ship / player context** | **accepted, C-000003 DELIVERED at t2** |
| **enemy_ship / player context** | **accepted, C-000004 DELIVERED at t2** |
| **own_ship / opfor context** | **accepted, C-000005 DELIVERED at t2** |
| unknown ghost_issuer / player | rejected unknown_from |

A real `issue_order('hold','enemy_ship',['own_ship'],{},player_context)` is also accepted and reaches **QUEUED** at t2. No authorize/begin/complete call was made, so this is evidence of unauthenticated cross-domain issuing/delivery, **not automatic command execution** or a grant of fire authority.

The original card explicitly requires legal sender/controller/fleet/owner and rejection of friendly impersonation/cross-domain issuing. Checking only unknown ghost nodes (formal S6) does not exercise a registered sender impersonated by another domain. Preserve the matching-context controls and explicit unknown-node failure, and validate the existing authorized context against each actual sender rather than treating a known node as sufficient authority. This is the original A04 boundary, not an AI task-acceptance feature.

Evidence: JSON case `registered_sender_and_caller_context` contains exact input contexts, all normal API returns, raw actual DELIVERED events and the order state after due.

## Closed wiring and unproven spoof boundary

Static wiring correctly attaches the same EW service to Comms and routes all three actual sends through it: Session.send_comms, OrderService.issue and Session.queue_intel_share. Comms advances once via OrderService.tick; that tick forwards the same real DELIVERED/FAILED event batch to Session. The normal failure callback is observed above, with no false delivered for C-000001.

EWService.comms_effect can report spoof_text/spoof_events/suspicious/requires_confirmation/auto_execute=false (`ew_service.gd:322-349`). The new send sampler retains only jam severity, added latency, failure probability and draw, and does not carry those spoof fields into its record. This agent did **not** run a spoof-message/command execution diagnostic and does not mark actual transport spoof handling proven. The delivery report's statement about untrusted spoof messages must be distinguished from the pre-existing effect query; listing unsupported spoof integration is preferable to claiming a live message path was verified. No new spoof protocol, AI policy or UI is requested.

## Command / limits

```powershell
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-a04-validation/GHOST TRACK_APSIS/.test-results/sol-a04/transport/transport_audit.gd'
```

Engine4.7.2.stable.official.ed1daf0bf; exit0. No GDScript parse/runtime error appears in the completed log. Exit0 means observed records were written, not that acceptance passed. No direct user message, GitHub mutation, additional test run or production fix was performed. Stopped after these bounded controls.
