# PR #65 JC-B00/K0 独立契约审查
精确被审 head: dc3821eda91d25f14e44dd9f57e6f5a985e04a9c
Task: #57 JC-B00. Date: 2026-10-26 Asia/Shanghai.

结论: K0 暂不能解锁 JC-A01。现有 39/0 证明固定 fixtures 与当前校验器一致，未证明 #57 要求的权限、情报归属、部署选择与幂等边界成立。以下是合同层漏洞；本卡尚未接入运行态，不能据此声称当前游戏已发生越权开火。

## P1: 命令 actor 未与 controller 绑定，own_ship 标签不约束真正本舰
Source: game_v17/scripts/core/jc_contracts.gd:269-291,292-294.
From valid fixture, keep actor_id=player_commander/kind=fire but change domain_id=ally, controller_id=ally_ai, shooter_id=I-AL1. validate returns ok=true/errors=[].
Add legacy_context=own_ship: also accepted. Validator only checks actor is nonempty and command controller matches the domain field supplied in the same object. There is no actor authorization capability map or validated request/acceptance mode. This does not satisfy player direct-control only own fleets or legacy only old ownship.
Repro cases: player_actor_direct_fires_ally, legacy_own_ship_label_with_ally_shooter.

## P1: 情报 owner/source 无引用与共享权限边界，且 K0 所需存储决策被推迟
Source: jc_contracts.gd:233-250; docs/contracts/joint_campaign_r2.md:157-158.
Set observer_id=NO-SUCH-OBSERVER, intel_owner_id=NOT-A-DOMAIN-OWNER, observed_t=100/received_t=102/delay_s=999: accepted.
Also two command domains can use same intel_owner_id without any sharing grant, and all three kinds may be player: accepted.
#57 requires B00 compare per-owner TrackTable vs explicit partition and choose one preserving independent fusion/decay. Doc instead defers the choice to A01, despite K0 gating A01. No sender_owner/receiver_owner/authorized share route or AI read-view API is frozen. Need explicit source observer/owner registry references, legal grants, delay relation and ownership/fusion model; add negatives that cannot pass just because strings are nonempty.
Repro: unknown_intel_owner_observer_and_delay_conflict, player_and_ally_share_intel_owner_without_share_grant, all_three_domains_are_player.

## P1: 幂等键可省略且可跨实例复用，生命周期记录未验证当前状态/时间
Source: jc_contracts.gd:198-214.
The idempotent_replay=true flag suppresses missing request_id errors, even though this flag itself provides no prior result or idempotency registry. Same request_id for I-A1/I-A2 is accepted. Negative t and a DRAFT->VALIDATED record on a current DEPLOYED instance are accepted.
Must freeze duplicate request behavior (same payload produces same instance/result; conflicting payload rejected), event/record identity, current state and monotonic time relations at contract level; no runtime deploy implementation requested here.
Repro: same_deploy_request_id_different_instances, idempotent_replay_flag_bypasses_missing_request_id, deployment_negative_time_and_transition_disagrees_current_state.

## P1: selected 字段被丢弃，未选择舰仍进入部署清单
Source: jc_contracts.gd:177-180.
Set instances[0].selected=false and keep its existing deployment: accepted. The index deliberately does not preserve selected and deployments only consults deployment_state. #57 explicitly requires unselected ships excluded and selection-to-instance mapping. Current positive fixture omits selected on every instance; probe line about unselected ships merely checks IDs exist.
Repro: unselected_instance_still_deployed.
Related source: tests/jc_contracts_probe.gd:133-141.

## P2: 冻结文档承诺的 roster/命令 ID 拒绝未执行
Source: jc_contracts.gd:124-128,264-295.
Changing player roster member to ally I-AL1 is accepted. Duplicate command_id or deleting command_id is accepted. Doc field table says roster must belong to same fleet and command_id empty/duplicate must reject. Current probe checks roster only on valid fixture and no negative contract call for these cases; no command ID uniqueness assertion.
Repro: player_roster_references_ally_instance, duplicate_command_id, missing_command_id.

## P2: 数值与单舰资源合同不稳定
Source: jc_contracts.gd:358-369,389-398.
Native int 9007199254740992 passes _is_int because int branch returns true without safe range; this conflicts with safe JSON range and can pass validate but fail serialization roundtrip. Infinite mass passes because only <0 is checked. Ledger missing ammo/fuel/cooldown passes, and valid fixture has only one ledger for five DEPLOYED instances. Fuel 3000.5 kg is rejected as a count; kilograms of fuel should be finite nonnegative physical quantity and need not be integer count.
Repro: native_int_exceeds_safe_integer, infinite_mass, ledger_without_ammo_fuel_cooldown, fractional_kg_fuel_rejected.

## 还需补齐的 K0 设计交付
No runtime AI/deployment/mission implementation is required by B00. However #57 does require its interface contract:
- separate per-owner fusion/decay storage choice;
- versioned event ID/seq and comms request/receipt/execution shapes;
- actor/controller/fleet/shooter API signatures and legacy ownship mapping;
- AI authorized view API not exposing raw Session enemy truth;
- objective authority vs per-owner known-view interface;
- legacy save-scope fixture and versioned migration policy, including no fabricated fleets;
- K0 actual G0 40-character SHA alignment (current doc only C55 and future promise).
Current docs have broad writer tables but do not freeze these signatures/transport/save contracts.

## Runtime evidence
Environment: Godot 4.7.2.stable.official.ed1daf0bf, Windows; no performance claims.
Command executed from worktree root:
```powershell
$env:JC_K0_AUDIT_OUTPUT='C:/Users/ASUS/.codex/worktrees/jc-g0-k0-rereview/GHOST TRACK_APSIS/.test-results/r5-k0-audit/mutations.json'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/Users/ASUS/.codex/worktrees/jc-g0-k0-rereview/GHOST TRACK_APSIS/game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-g0-k0-rereview/GHOST TRACK_APSIS/.test-results/r5-k0-audit/mutations.gd'
```
Exit=0 means diagnostic completed, not contracts accepted/rejected correctly. 17 cases printed: original valid true; 15 invalid/contradictory mutation cases true; fractional-fuel valid quantity false.
Artifacts: mutations.gd, mutations.log, mutations.json in this directory.
No production source, existing tests, GitHub comments or merge state changed.

