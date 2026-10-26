# PR66 R2 focused save QA

HEAD: `61f27fc8e841666705b5fd2e843824a03bf6c0b8`.

- Genuine pre-A01 save (`baseline_pre_a01.json`, 3,060 bytes; no `authority_intel` key) loads `ok=true`. Its old TrackTable has one `T0001`; candidate migrates it to `player_intel` (1 track), leaves `ally_intel` empty, and exposes `legacy_own_ship_only` plus `legacy_tracks_migrated:1` in both load result and `authority_restore_report()`. This fixture's seed/log replay has no errors.
- New save with `authority_intel="broken"` fails with `authority_restore_mode=failed` and `invalid_authority_intel_section`; nested `version=999` fails with `invalid_version`. Those R2 cases are fixed.
- **Remaining defect:** new save with an explicit `authority_intel: null` loads `ok=true`, reports `legacy_own_ship_only`, and has no migration reason. The load guard in `game_session.gd` only rejects non-dictionaries when `ai_state != null`; actual old saves are distinguishable by the key being absent. Present-null therefore still silently downgrades malformed new data to legacy.

Raw output: `focused_save_qa.stdout.txt`; fixture hash: `AF330E3776E3D8DEC6F18569B62797D7600253AF93C25BF06703D45A98B2FB69`.
