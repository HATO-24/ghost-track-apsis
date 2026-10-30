# H01 原始证据索引

基线：main `018bd4d0adc882a9123210f022fe8b7c71f68c06`；平台 Windows / Godot `4.7.2.stable.official.ed1daf0bf` / headless。
代码修复提交 `236826f61fc092a8737ca855943b76c0882813b9`；baseline 独立提交 `cd6883b0991d4aae0b6f1582f2cf63ccfb6f7263`。

## red/（修复前）

命令（摘要）：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'damage_profile|damage_integration|v17_nav_integration' -Ci -ResultsDir .test-results/next-cards/H01/red
```

结果：

```text
content.damage_profile_probe          FAIL  554/4   exit 1
integration.damage_integration_probe  FAIL  198/6   exit 1
integration.v17_nav_integration_probe FAIL  181/1   exit 1
total=3 pass=0 fail=3; RESULT: FAILURES PRESENT
stderr SCRIPT ERROR: 4 × damage_profile_service.gd:208 String(batch) constructor
```

## final/（修复后专项，同一代码 HEAD）

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'damage_profile|damage_integration|v17_nav_integration' -Ci -NoImport -ResultsDir .test-results/next-cards/H01/targeted-final
```

```text
content.damage_profile_probe          PASS  562/0
integration.damage_integration_probe  PASS  215/0
integration.v17_nav_integration_probe PASS  185/0
total=3 pass=3 fail=0; RESULT: ALL RUN CASES PASS; stderr SCRIPT ERROR=0
```

## full/（共同 C，baseline-aware）

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Ci -NoImport -Baseline game_v17/tests/known_baseline_failures.json
```

```text
total=92 pass=88 fail=4 timeout=0 not_run=0
BASELINE CHECK: known_fail=4 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
RESULT: BASELINE MATCH ... exit 0
```

剩余 4 项历史失败保持：story_text 469/13、incident_record 2761/1、plot_tws 58/1、sensor_authority_display 71/3。

## gates/

```text
Phase 0: total=6 pass=6 fail=0 exit 0
Phase A: total=3 pass=3 fail=0 exit 0
```

## 说明

- `red/script-errors.txt` 保留修复前 4 条 SCRIPT ERROR 原文；修复后 `final/logs/*.stderr.log` 为空。
- 本目录为原始运行产物摘要/日志；报告见 `../H01_damage_profiles_report.md`。
- 未把旧 HEAD/旧 dirty 结果冒充最终 HEAD；最终 40 位 HEAD 见 PR/回报。
