# JC-B03P R11 / #63 迁移原始证据

基线：main `042a5e5e03f38f7b7e4367ffb0b6f38834773503`（含 H01 PR77）
代码/规格 HEAD：`7fb575bca423cda62c544d94c018319c01e2cbc8`
平台：Windows / Godot `4.7.2.stable.official.ed1daf0bf` / headless；本地测试规则（`-Ci` 本地严格模式，非 GitHub Actions）。

## targeted/（迁移专项）

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'jc_scenario_spec|jc_contracts' -Ci -NoImport
```

```text
integration.jc_scenario_spec  PASS  507/0  exit 0
integration.jc_contracts      PASS   84/0  exit 0
total=2 pass=2 fail=0; RESULT: ALL RUN CASES PASS
```

`-List` 预先确认选中 2 case（不是 0 case）。

## full/（共同 C，baseline-aware）

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Ci -NoImport -Baseline game_v17/tests/known_baseline_failures.json
```

```text
total=92 pass=88 fail=4 timeout=0 not_run=0
BASELINE CHECK: known_fail=4 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
RESULT: BASELINE MATCH — exit 0
```

剩余 4 项历史失败未刷新：
`content.story_text_probe 469/13`、`unit.incident_record_probe 2761/1`、`integration.plot_tws_probe 58/1`、`integration.v17_sensor_authority_display_probe 71/3`。

## gates/

```text
Phase 0: total=6 pass=6 fail=0 exit 0
Phase A: total=3 pass=3 fail=0 exit 0
```

## 边界

本目录只含规格迁移与自动校验证据；**NOT RUN**：B1b/B2/B3 运行层、AI、真实部署、UI/HUD、弹种/混装、11 舰真实规模/平衡/可玩性。报告见 `../JC_B03P_R11_migration_report.md`。
