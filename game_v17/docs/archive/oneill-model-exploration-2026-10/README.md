# O'Neill Island Three model archive candidate

Status: preserved for later Phase D/E evaluation. This package does not activate or integrate the model into the current gameplay path.

## Contents

- Procedural high-detail model source and its standalone scene.
- Manual structural audit probe and its audit rules.
- Three selected preview captures: clean exterior, reflector mount detail, and the latest interior iteration.

The local `oneill_island3.tscn` is a duplicate-name alias of the high-detail scene and is omitted to keep one canonical scene. Older iteration screenshots remain local; they are not part of this focused backup.

## Verification evidence and limits

These checks were run locally with Godot 4.7.2 on the worktree's then-current `main` snapshot `62356da5d863326e77b070953eca55ba5833e49a`. That worktree was dirty and 17 commits behind GitHub `main` at `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`; results below apply only to that local snapshot:

- `model_structure_probe.gd`: 181 checks, 0 failures, 0 warnings.
- `facility_model_probe.gd`: 1,697 checks, 0 failures, 0 fallbacks.
- Headless model preview: high-detail scene loaded, 1 loaded / 0 failed.
- The structural probe is manual and is not part of the default CI matrix.

These results establish that the local model can be constructed and its declared geometry checks pass. They do not establish visual approval, physical accuracy, collision behavior, gameplay integration, or compatibility with the newer GitHub main.

## Deliberately excluded

- Local HUD/NEAR-view deletion and other UI changes.
- Local changes wiring this model into the existing habitat/facility preview path.
- Unattributed reference images under `refs/`; provenance and redistribution rights are unknown.
- Older WIP preview captures beyond the three selected snapshots.

Re-run the relevant probes against current `main` before any Phase D/E integration. Keep this package as a candidate asset until the project owner approves that phase.
