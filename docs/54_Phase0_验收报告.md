# Phase 0 独立验收报告（模拟器优先剖面 + 统一 headless 回归）

> 验收人：独立验证者（verifier，T4；不复用实现者结论，全部命令在本机实际执行）
> 验收日期：2026-10-22（+08:00）
> 被验收提交：**`3c0800f`**（`feat/phase0-simulator-first`，`origin/feat/phase0-simulator-first` 同 SHA，已推送）
> 基线提交：`263e97e`（审计 PR #12 HEAD；= main `62356da` + 审计文档）
> 干净验证 worktree：`D:\gt_verify`（`git worktree add D:\gt_verify 3c0800f`，detached）
> 独立基线 worktree：`D:\gt_baseline`（`263e97e`，见 `D:\gt_baseline\.test-results\baseline-20261022-195243\BASELINE_NOTES.md`）
> 结论：**APPROVE（通过）** —— Phase 0 范围内无阻塞项；8 个 pre-existing FAIL 与基线逐项一致，不计为本次回归。

---

## 1. 环境与方法

| 项 | 值 |
| --- | --- |
| OS | Microsoft Windows 11 家庭版 中文版 10.0.26200（16 逻辑 CPU） |
| PowerShell | 7.6.6（另用 Windows PowerShell 5.1 复核兼容性） |
| Godot | `4.7.2.stable.official.ed1daf0bf`，`Godot_v4.7.2-stable_win64_console.exe` |
| 工程 | `game_v17`（main_scene `res://main_menu.tscn`，GL Compatibility） |
| 验证 worktree | `D:\gt_verify`（clean checkout；`tools/godot` 为 gitignore 的本地工具目录，复制 console 二进制） |
| 矩阵 run id | `.test-results/20261022-201657-3c0800fb/`（`summary.json` / `report.md` / 逐例 `logs/`） |

方法：从 pristine worktree 独立复跑；不采信实现者 PASS 声明；逐项对照审计 HEAD 独立基线；
对 runner 的 PASS/FAIL/TIMEOUT/NOT RUN/标记断言/环境阻塞路径做受控负例测试（临时矩阵文件放在仓库外，
未修改仓库内 probe/runner/matrix）。

### 1.1 提交与工作区检查

- `git -C D:\gt_phase0 rev-parse HEAD` = `3c0800fb1a5f1c1a57e01d804415b32f488b03a2`，分支 `feat/phase0-simulator-first`；
  `git branch --contains 3c0800f` → `* feat/phase0-simulator-first`；`origin/feat/phase0-simulator-first` = 同 SHA。
- `git worktree add D:\gt_verify 3c0800f` 后立即 `git status --porcelain` = **0 行（干净）**；
  之后 `--import` 产生的 53 个 `.import` stat-dirty（CRLF 归一化，`git diff` 为空）与 30 个未跟踪 `.uid`
  属 Godot 4.7.2 引擎噪音，不是源码改动；验证 worktree 无非 `.import/.uid` 脏项。
- 4 个提交全部在 Phase 0 写作用域内（17 文件，+4963/−278，**无任何文件删除**）：
  `122c0d1` docs/52 计划 · `a92867d` profile/orbital_sim + scenario + probe + docs · `73fc4a6` e2e probe（+uid） · `3c0800f` runner/matrix/CI/README/.gitignore/test_matrix。
- 66 个既有 probe **零改动**（仅 `build_profile_probe.gd` 因四剖面重组扩展 191→553 断言，未删除覆盖）；
  受版本管理 probe = 基线 67 + 新增 e2e 1 = 68，矩阵覆盖 68/68，无重复、无删除。
- 剧情/序章/触发器/内容/资产路径无删除、无改写（diff 无 `D` 状态文件）；用户 WIP `D:\GHOST TRACK_APSIS`
  仍在 `main@62356da`，35 个脏项均为用户模型/UI WIP（8 M + 1 D + 26 ??），无 Phase 0 文件改动（见 §8 发现 F4）。

---

## 2. 统一回归矩阵（独立复跑）

命令（`D:\gt_verify`，Godot 由 `tools/godot` 自动发现）：

```powershell
pwsh -NoProfile -File .\run_tests.ps1
# exit code = 1；run id .test-results/20261022-201657-3c0800fb；总时长 301.2s
# total=72  pass=64  fail=8  timeout=0  not_run=0 (expected=0 unexpected=0)
```

| 分类 | total | pass | fail |
| --- | --- | --- | --- |
| `profile` | 1 | 1 | 0 |
| `content` | 8 | 6 | 2 |
| `unit` | 37 | 35 | 2 |
| `integration` | 21 | 17 | 4 |
| `e2e` | 1 | 1 | 0 |
| `boot` | 4 | 4 | 0 |
| **合计** | **72** | **64** | **8** |

- 72 个 case id 与 `probe_matrix.json` 的 72 个 id **集合完全一致**（无遗漏、无重复、无静默跳过）；
  每个已运行 case 的日志文件均存在；`attempts` 全为 1（无重试掩盖）；8 个 FAIL 均 `exit=1`。
- `summary.json` 自洽性：totals 与 cases 分组一致；`report.md` 汇总行 `72 | 64 | 8 | 0 | 0 | 0 | 301.2s`、
  `Overall run exit code: 1`；`git_commit=3c0800fb…`、`godot_version=4.7.2.stable.official.ed1daf0bf`
  （`version_match=true`）、import 预检 PASS（exit 0，7.6s，0 error）。
- 与验证者基线（审计 HEAD `263e97e`，67 probes：PASS=59/FAIL=8）对比：**66 个 probe 状态与
  PASS/FAIL 计数逐项一致**；唯一计数变化是 `build_profile_probe` 191→553（本任务扩展探针，预期内）。
  **无新增失败、无结果翻转、无 PASS 数缩水。**
- 时长说明：本次 301.2s，T2 文档记录 269.0s；差异来自与 Lead 并发的第二次全量矩阵（CPU 争用）。
  72 个 case 的 PASS/FAIL 结果与文档记录逐项一致，故不构成差异。最慢 case：
  `v17_transit_bridge` 70.8s、`fleet_transfer` 63.6s、`transfer` 63.3s；矩阵已为这三者与 e2e 设 300s 超时，
  boot 240s、其余 180s，实际 **TIMEOUT=0**。

### 2.1 8 个 pre-existing FAIL（与基线逐项一致，非 Phase 0 回归）

| case | exit | PASS/FAIL | 基线 `263e97e` | 结论 |
| --- | --- | --- | --- | --- |
| `content.damage_profile_probe` | 1 | 554/4 | 554/4 | 一致（另含 4 条既有 `damage_profile_service.gd:208` SCRIPT ERROR） |
| `content.story_text_probe` | 1 | 469/13 | 469/13 | 一致（12 条文本与 docs/44 演进漂移） |
| `unit.incident_record_probe` | 1 | 2761/1 | 2761/1 | 一致 |
| `unit.save_probe` | 1 | 153/3 | 153/3 | 一致 |
| `integration.damage_integration_probe` | 1 | 198/6 | 198/6 | 一致 |
| `integration.plot_tws_probe` | 1 | 58/1 | 58/1 | 一致（非标准 `[SUMMARY]` 解析器正确判 FAIL，未误判 PASS） |
| `integration.v17_nav_integration_probe` | 1 | 181/1 | 181/1 | 一致 |
| `integration.v17_sensor_authority_display_probe` | 1 | 71/3 | 71/3 | 一致 |

> 以上 8 项为审计 HEAD 已存在的**内容/契约漂移**，属 Phase 0 明确不修范围（Lead 已确认）。
> 本次验收口径：**无新增失败、无 case 被改判、无 PASS 数变化** —— 满足。

### 2.2 Phase 0 交付用例（全部 PASS，独立复跑）

| case | 结果 | 独立证据 |
| --- | --- | --- |
| `profile.build_profile_probe` | PASS 553/0，exit 0，0.5s | 四剖面开关矩阵、选择优先级、坏配置回退、simulator 校验负例、sandbox_opts 守卫、场景几何、JSON 安全 |
| `e2e.orbital_sim` | PASS 153/0，exit 0，3.8s | 真实入口 `main_menu → v1_hud → ShellBinder → GameSession` + 完整战斗闭环 |
| `boot.full` | PASS，exit 0，3.2s，markers 3/3 | `[SHELL BINDER] BUILD profile=full`、`prelude ready=true`、`FLOW SMOKE COMPLETE` |
| `boot.legacy_combat_sim` | PASS，exit 0，3.5s，markers 3/3 | `[MAIN MENU] BUILD=combat_sim`、`BUILD profile=combat_sim`、`FLOW SMOKE COMPLETE` |
| `boot.orbital_sim` | PASS，exit 0，3.3s，markers 3/3 | 主场景自动跳转 + `BUILD profile=orbital_sim` + `FLOW SMOKE COMPLETE` |
| `boot.sandbox` | PASS，exit 0，3.4s，markers 3/3 | 主场景自动跳转 + `BUILD profile=sandbox` + `FLOW SMOKE COMPLETE` |

### 2.3 runner 真实性与失败语义（受控负例，本人执行）

| 受控场景 | 期望 | 实测 |
| --- | --- | --- |
| `-List` | exit 0，列出矩阵 | exit 0，72 行，0 blocked |
| `-Category profile`（全 PASS） | exit 0 | exit 0，PASS 553/0，`ALL RUN CASES PASS` |
| 全量矩阵（含 8 个既有 FAIL） | 非零 | exit 1，`FAILURES PRESENT` |
| `-Only plot_tws_probe` | 必须 FAIL（非 PASS） | exit 1，FAIL 58/1（`[SUMMARY]` 解析器正确） |
| `-Only facility_model_probe` | 必须 PASS（非 NO_MARKER） | exit 0，PASS 1697/0（`checks=` 解析器正确） |
| 临时矩阵：脚本不存在 | 非预期 NOT RUN → exit 1，带原因 | exit 1，`NOT RUN`，reason `missing script (not present in worktree): …` |
| 临时矩阵：`blocked: true` | 预期 NOT RUN → exit 0，带原因 | exit 0，reason `blocked by matrix precondition: …` |
| `-TimeoutSec 2` 跑慢 probe | TIMEOUT → exit 1 | exit 1，状态 `TIMEOUT`，reason 明确 |
| 临时矩阵：boot 退出码 0 但必需 marker 缺失 | FAIL（证明不是只看 exit code） | exit 1，FAIL 0/1（Godot 自身 exit 0） |
| `-GodotBin` 指向不存在路径 | 环境阻塞 exit 2 + 全 NOT RUN 带原因 | exit 2，BLOCKED，NOT RUN，原因 `-GodotBin not found: …` |
| Windows PowerShell 5.1 `-List` / 过滤执行 | 兼容 | 均 exit 0；`facility_model_probe` PS5.1 PASS 1697/0 |

逻辑检查：`Get-ExitCodeForTotals` 对 FAIL/TIMEOUT/非预期 NOT RUN 返回 1；导入失败/无 Godot 返回 2；
`summary.json` 含 case id/exit/status/duration/pass/fail/commit/godot version/profile/log/reason；
`DSH_*`/`V17_*` 按前缀清除再按 case 注入（本次实跑清除 6 个继承变量）。
runner/matrix/workflow 中**无个人绝对路径硬编码**（grep `D:\`、`C:\Users`、`gt_phase0` 均无命中）。

---

## 3. 拟真剖面与启动证据（本人命令，非实现者转述）

### 3.1 `orbital_sim` 真实主场景 boot smoke —— exit 0

```powershell
$env:DSH_BUILD='orbital_sim'; $env:DSH_FLOW_SMOKE='1'
& ...\Godot_v4.7.2-stable_win64_console.exe --headless --path D:\gt_verify\game_v17
# EXIT=0，3.4s
```

关键日志（实跑摘录）：

```text
[MAIN MENU] BUILD=orbital_sim → skip to res://v1_hud.tscn
[BUILD PROFILE] id=orbital_sim mode=simulator scene=res://v1_hud.tscn scenario=res://framework/content/scenario_orbital_sim.json save_root=user://saves_sim
[BUILD PROFILE] SYSTEM story=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM prelude=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM triggers=OFF reason=剧情扩写暂停（Phase 0）
[BUILD PROFILE] SYSTEM sandbox=OFF reason=非测试剖面
[BUILD PROFILE] SYSTEM identification/traffic/port/signal/combat/ballistics/damage/physics_world/ship_catalog/refit=ON
[BUILD PROFILE][LIMITATION] ×7（CR3BP 近似 / EW 抽象 / 传感器权威 / 对接 / 交通 / 改装 / UI 图层，均标注 Phase A–D）
[SHELL BINDER] SYSTEMS physics=true sensors=true track_table=true combat=true ballistics=true damage=true ew=true identification=true traffic=true port=true ship_catalog=true refit=true story=disabled
[V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=7 commands=0
```

- 该日志中 `story_state`、`"unlimited_ammo": true`、`"auto_authorize": true`、`"quick_restart": true`、
  `"sandbox": true`、`SCRIPT ERROR` 出现次数均为 **0**（grep 实测）。
- `SYSTEMS` 行来自 `systems_vm()` 真实服务对象 `ready` 字段（e2e 逐对象断言，见 §4），非硬编码。
- 场景 `scenario_orbital_sim.json` 为 EML1 真实 bary_rot 几何（地球 x≈−4671 km、月球 x≈379729 km、
  态势 x≈321719 km，7 实体，ROE TIGHT，无任何便利项配置）。

### 3.2 `full` 剧情构建 boot smoke —— exit 0，且行为与基线一致

```powershell
$env:DSH_FLOW_SMOKE='1'
& ...console.exe --headless --path D:\gt_verify\game_v17 res://v1_hud.tscn
# EXIT=0，3.1s；prelude ready=true entities=9 triggers=3 used=true；story=ready
# [V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=9 commands=1
```

用同样命令在基线 worktree `D:\gt_baseline`（`263e97e`）复跑，输出的 `FLOW SMOKE COMPLETE` 行
与最终提交**逐字节相同**（`contacts=9 commands=1`），剧情/序章路径未被破坏；story 相关 probe
（`story_runtime` / `story_state` / `story_trigger` / `prologue` / `prelude_scenario` / `teaching`）全 PASS。

### 3.3 旧 `combat_sim` 向后兼容 boot smoke —— exit 0

```text
[MAIN MENU] BUILD=combat_sim → skip to res://v1_hud.tscn
[BUILD PROFILE] WARN 选中的剖面 'combat_sim' 已弃用（deprecated）…
[SHELL BINDER] SANDBOX entities=7 scenario=res://framework/content/scenario_combat_sandbox.json
[V1 HUD] COMBAT source=session sandbox={ "unlimited_ammo": true, "auto_authorize": true }
[V1 HUD] FLOW SMOKE COMPLETE name=指挥官 · 沧澜 contacts=7 commands=0
# EXIT=0；基线同命令输出逐字节相同（含便利项仍为 true、traffic direct-fallback）→ 旧行为未变
```

`sandbox` 剖面 boot smoke 亦 exit 0（`user://saves_sandbox`、SYSTEMS 全 true、story=disabled）。

---

## 4. 真实入口 E2E（`e2e_orbital_sim_probe.gd`）—— exit 0，PASS 153/0

本人直接执行（非矩阵转述）：

```powershell
& ...console.exe --headless --path D:\gt_verify\game_v17 --script res://tests/e2e_orbital_sim_probe.gd
# EXIT=0，3.6s；E2E ORBITAL SIM PROBE RESULT: PASS=153 FAIL=0
```

- **真实入口**：`change_scene_to_file(res://main_menu.tscn)` → 记录主菜单真实实例化（`saw_main_menu=true`，
  3 帧内自动跳过）→ `current_scene` 为 `V1HUD` 且脚本 `v1_hud.gd` → `ShellBinder.boot()` → `GameSession.booted`。
- **剖面契约**：id/boot_mode/entry_scene/scenario 精确断言；story/prelude/triggers=false、
  sandbox=false，identification/traffic/port/signal/combat/ballistics/damage/physics_world/ship_catalog/refit=true；
  `limitations` 7 条非空；`is_simulator()==true`、`is_sandbox()==false`。
- **系统真实度**：12 个服务对象逐个断言 `present && ready`（physics_world/sensor_service/track_table/
  combat_service/combat_ballistics/damage_service/ew_service/identification_service/traffic_control/
  port_service/ship_catalog/refit_service），并与 `binder.systems_vm()` 同源交叉核对；
  `story_state == null`、`story_vm()` 为空、`used_prelude == false`；世界实体 7/7 同时进入 world 与 PhysicsWorld。
- **拟真约束**：`combat_service.unlimited_ammo=false`、`auto_authorize=false`；profile 三项便利项全 false；
  `quick_restart()` 被拒且原因非空。
- **真实战斗闭环**：传感器→航迹产生真实 track → 从未授权 FIRE（`needs_authorization` 被拒、弹药 120 未变）→
  TRACK → SOLUTION 真实 tick 到 READY → `grant_authorization` → FIRE（`physics=ballistics`，
  返回**不含**伪造 hit/miss）→ 弹丸在飞 → 14×2s tick 闭环 → `impact IMP-00001`（target=harmattan，t=32.1，
  miss_dist=0.0 km）→ DamageService `integrity_avg=0.9424`（真实下降）→ `weapon_launch` 1 条 == launched；
  弹药 120→119 真实扣减且 `ammo_left` 一致；全程 `SCRIPT ERROR` 0 条。
- 交通/港口：traffic 18 lanes/19 OTC/6 NPC（source=session，非 direct-fallback 桩）、lane/OTC 行可查询；
  port `ports>0`、`berths_total>0`、`port_summary`/`window_status` 可查询。

---

## 5. Issue #1 验收逐项

| # | 验收标准 | 判定 | 证据 |
| --- | --- | --- | --- |
| 1 | headless/profile probe 覆盖每个 profile 开关矩阵与缺配置回退 | **MET** | `build_profile_probe` PASS 553/0；四剖面（full/orbital_sim/sandbox/combat_sim）开关逐项、选择优先级、缺配置/坏 schema/坏 default/坏 env 回退、simulator 负例（关 traffic/port→ready=false 报错不自动开启；注入 sandbox_opts→强制 false+告警；开 story→强制关+告警；缺 scenario→error；未知 boot_mode→回退 prelude+error） |
| 2 | 模拟器 profile 真实启动到战术界面，实体/战斗/物理/传感器/交通/港口/改装均 ready | **MET** | `boot.orbital_sim` exit 0（真实 main scene 自动跳 v1_hud）；`[SHELL BINDER] SYSTEMS` 12 项全 true；e2e 逐对象 ready + 世界 7/7 实体 |
| 3 | full 启动 smoke 仍通过；模拟器中 story/triggers 明确 disabled | **MET** | `boot.full` exit 0 + markers 3/3，prelude ready=true entities=9 triggers=3；基线同命令 FLOW SMOKE 行逐字节相同；orbital_sim 日志 story/prelude/triggers=OFF+原因，`SYSTEMS … story=disabled` |
| 4 | 启动日志明确显示 profile、场景、启用系统和禁用理由 | **MET** | `[BUILD PROFILE] id/mode/scene/scenario/save_root` + 每功能 `SYSTEM x=ON|OFF reason=…` + 7 条 `[LIMITATION]` + `[SHELL BINDER] SYSTEMS` 实测就绪 |

Issue #1 实施要求：#1 新剖面系统矩阵（含 traffic/port/refit/ship_catalog）→ MET（配置+运行日志+probe）；
#2 拟真剖面默认无作弊项、仅测试 profile 可开 → MET（orbital_sim 全 false；sandbox 全 true；full 强制 false）；
#4 剧情服务仅剧情剖面装载、模拟器无 story_state 不报错不伪造 → MET（e2e `story_state==null`、`story_vm` 空）；
#5 不新增剧情、不破坏剧情兼容 → MET（零剧情内容改动、full 路径逐字节回归）。
#3「明确开发启动命令；开发默认可进入模拟器，但保留 full」→ 以 `README` 显式命令 `DSH_BUILD=orbital_sim`
实现，**默认 profile 仍为 full**（遵循审计交接规则“不得默默改变默认 profile”）；这是对 issue 措辞的
保守解释，已在 README/docs 明示命令，记为“满足（解释性）”。

## 6. Issue #5 验收逐项

| # | 验收标准 | 判定 | 证据 |
| --- | --- | --- | --- |
| 1 | 新机器按文档一条命令跑完回归 | **MET**（本机复现） | README + `game_v17/docs/test_matrix.md`；pristine worktree 中仅复制 gitignored `tools/godot` 后 `pwsh ./run_tests.ps1` 即跑完 72 case；Godot 发现顺序 参数/env/tools/PATH，无个人路径硬编码；PS 5.1 与 7.6.6 均验证 |
| 2 | CI 报告所有运行 probe 并在失败时红灯；main 合并前必须通过 | **MET（Issue #14 后真实 Actions 运行）** | 新 workflow 拆两个 check：`Phase 0 gate (required)`（`-Gate phase0`，必须绿）与 `Full matrix (baseline-aware)`（72 cases 全跑；8 个遗留失败仍以 FAIL 可见；仅新增回归/漂移/超时/非预期 NOT RUN 红灯）。真实 run [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057)：两个 job 均 success，artifact 已上传并下载验证（§12）。注意：full-matrix 绿灯含义是「无新增回归」，**不是**「全矩阵通过」；8 个 pre-existing FAIL 仍需独立内容/契约同步任务修复 |
| 3 | 至少一个 simulator integration test 沿真实入口启动并执行一条战斗流程 | **MET** | `e2e.orbital_sim` PASS 153/0：真实 `main_menu→v1_hud→ShellBinder→GameSession`，真实未授权拒绝/授权/FIRE/弹道/impact/损管，非伪造 |
| 4 | README 入口、版本、测试命令与当前实现一致 | **MET** | README 已更新 V17/Godot 4.7.2/四剖面启动命令/`pwsh ./run_tests.ps1`，并写明 `-Gate`/`-Baseline` 与两个 CI check 的语义；默认 profile 仍为 `full`（Issue #14 §4） |

Issue #5 实施要求补充核对：#2 机器可读摘要字段完整（probe/exit/pass-fail/duration/commit/profile/log）→ MET；
#4 `DSH_*`/`V17_*` 隔离 → MET（实跑清除 6 个继承变量）；#6 不拿注释 PASS 数当结果 → MET（runner 执行当前脚本）；
#3 矩阵组成（单模块/schema/content/两 profile boot/战斗闭环/物理同步/dock+refit/sensor/IFF/EW/save-load）
→ 由 72 case 分类矩阵覆盖；唯一既有失败 8 项如实报告，未隐藏/未弱化。

---

## 7. 审计文档（docs/40）需更新的陈述（因 Phase 0 代码现状变化）

| 审计陈述 | 当前现实（3c0800f 实测） |
| --- | --- |
| §1.1/§2：`combat_sim` 关 traffic/port 且带作弊项 → 缺拟真 profile | 已新增 `orbital_sim`（traffic/port/refit/catalog 全开、无作弊项、story 关）；`combat_sim` 保留但标记 deprecated；审计对旧 profile 的事实仍成立 |
| §1.1：`main_menu` 仅在 sandbox 情况自动跳过 | 现在 `is_simulation()`（simulator/sandbox）均自动跳过；`DSH_SHOT`/`DSH_NO_AUTOSKIP=1` 守卫保留 |
| §1.8/§2「自动回归/CI」：缺统一入口与端到端组合测试，当前结果未验收 | 已交付 `run_tests.ps1` + `probe_matrix.json`（72 case）+ 真实入口 e2e + 两个 CI check；Issue #14 后 GitHub Actions 已真实运行：run [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057) 两个 job success，artifact 已上传/下载验证（§12）；8 个 pre-existing FAIL 保持可见并建模为 known baseline |
| §6：未在 Godot runtime 执行、未跑全量 probe | Phase 0 已全量执行 68 个 tracked probe + 4 boot + 1 e2e；审计“历史 PASS 不可信”的判断被验证：确有 8 个历史漂移 FAIL，均已如实保留 |
| §2 行「构建/profile/剧情分离：部分完成；默认仍 full；拟真 profile 缺」 | Phase 0 后：默认仍 full（刻意不变），拟真 `orbital_sim` 已具备启动/就绪证据；更上层集成仍属 Phase A+ |
| §1.7 提到 `scripts/ui/near_view.gd` | 仓库/分支仍保留该文件；用户 WIP 中删除属用户改动，非审计错误（docs/52 已记录） |

---

## 8. 发现项（discrepancy / 风险）与处置

| id | 级别 | 发现 | 处置 |
| --- | --- | --- | --- |
| F1 | 记录（非阻塞） | `game_v17/docs/build_profiles.md` §12.4 仍写「e2e/boot.orbital_sim/boot.sandbox 目前仍标记 blocked: true（T1 pending）」；最终提交矩阵已 0 个 blocked、全量已跑、e2e PASS | 文档滞后于 T2 解阻塞；`test_matrix.md` 为权威且正确。建议后续 docs-only 提交顺手修正（不影响 Phase 0 判定） |
| F2 | 记录（非阻塞） | `build_profiles.md` §12.5 引用 e2e `PASS=150`，最终实际 `PASS=153`（`test_matrix.md` §7.1 写的是 153，正确） | 同上，建议随 F1 修正为 153 |
| F3 | 记录（非阻塞） | 日志文案：orbital_sim/sandbox 仍打印 `[SHELL BINDER] SANDBOX entities=7 …`（历史标签未改名） | 纯文案，不影响断言/机器解析；建议 Phase A 更名 `external` 或保留（文档已按现状引用） |
| F4 | 记录（需人处理） | 用户 WIP `D:\GHOST TRACK_APSIS` 下出现 1 个 **0 字节**未跟踪 `run_tests.ps1`（mtime 19:57，Phase 0 实施窗口内），疑为并行工具误写；**未改动任何 tracked 文件，main 仍 `62356da`** | 验证者未触碰用户工作区；建议 Lead/用户确认后删除该空文件 |
| F5 | pre-existing（非 Phase 0） | `damage_profile_service.gd:208` 仍有 `SCRIPT ERROR: Invalid call 'String' constructor`（基线即存在，本次 4+1 次）；8 个 probe FAIL 均为内容/契约漂移 | 不在 Phase 0 范围；`test_matrix.md` §7.2 已如实披露。CI 在修复前会保持红灯 |
| F6 | 环境噪音 | `--import` 产生 `.uid` 未跟踪与 `.import` CRLF stat-dirty（`git diff` 为空）；`summary.json` 的 `worktree_dirty=true` 正因此产生（验证 worktree 已预先 import） | 非源码脏改动；CI 全新 checkout 时 runner 在 import 前采集 git 信息，不受影响 |

**Phase 0 允许保留的已知集成缺口（已验证按约定记录，非阻塞）**：

1. 轨道融合距离 ≠ 物理真值：`_sensor_config()` 旧装订几何使 fused track `range=20.0 km`，而
   PhysicsWorld 真值 `420.0 km`（火控门禁用 track 值、弹道用真值）；`build_profiles.md` §12.6 与
   e2e `[E2E] INFO` 均如实记录，明确转 Phase A #4。
2. `WorldState._normalize_entity()` 丢弃 side/identity/batch 元数据，`_build_contacts()` 回退
   `side="friend"`；e2e 实测 `CONTACT SIDE MISMATCH n=5`（harmattan/ferry/raider_2/skiff/watchtower），
   明确转 Phase A #2；e2e 未放宽断言、未伪造 threat。

两项均在 `build_profiles.md` §12.6 以「NOT FIXED · 不在 Phase 0 修复」记录，并给出修复方向 → **记录诚实，符合要求**。

---

## 9. NOT RUN / 未验证项

| 项 | 状态 | 原因 |
| --- | --- | --- |
| GitHub Actions CI 实际执行 | **MET（Issue #14 后已实际运行）** | run [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057)：`Phase 0 gate (required)` success（6/6 PASS，artifact 26,039 B）、`Full matrix (baseline-aware)` success（72=64 PASS/8 KNOWN-BASELINE FAIL/0 new/0 drift，artifact 372,318 B）；artifact 已用 `gh run download` 实际下载并校验内容（§12）。旧 run [39778490176](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39778490176)（artifact 0）只作为修复前证据 |
| Linux/macOS `run_tests.sh` 实跑 | **NOT RUN** | 本机为 Windows；脚本仅静态审查（薄封装 pwsh，缺 pwsh 时 exit 2） |
| 非 headless / 窗口化渲染 | **NOT RUN** | 验收范围仅 headless 回归；渲染路径与性能未测量 |
| `DSH_SHOT` 截图模式 | **NOT RUN** | 同上；文档明确未验证 |
| orbital_sim `user://saves_sim` 存档 round-trip | **NOT RUN** | 超出 Phase 0 范围；`save_probe` 另有 pre-existing FAIL（内容漂移） |
| 导入失败路径的端到端负例 | 未复现（逻辑审查） | 代码审查确认 import 非零/error 行 → 环境阻塞 exit 2；未故意破坏导入做真机负例 |
| GitHub PR / main 合并门禁 | **部分 MET** | PR #13（Phase 0）与 stacked PR #15（Issue #14 收尾）均已创建，CI checks 见 §12；合并动作仍待项目负责人执行（本任务不擅自合并） |

---

## 10. 最终结论

**APPROVE（Phase 0 通过）。**

- 最终提交 `3c0800f` 在 pristine worktree 独立复跑：`build_profile_probe` PASS 553/0、
  `e2e.orbital_sim` PASS 153/0、四个 boot smoke（full/orbital_sim/legacy_combat_sim/sandbox）全 exit 0 且
  marker 3/3；统一矩阵 **72 cases = 64 PASS / 8 FAIL / 0 TIMEOUT / 0 NOT RUN / exit 1**，
  8 个 FAIL 与审计 HEAD 独立基线逐项一致（同计数、同 case），**无新增失败、无断言弱化、无测试删除、
  无故事路径/核心系统删除或禁用**，full 与 legacy 行为与基线逐字节一致。
- Issue #1 四项验收全部满足；Issue #5 四项全部满足（Issue #14 后 CI 已真实运行并验证 artifact；§12）。
- 无阻塞项（BLOCK list 为空）。放行条件（非阻塞、需后续任务消化）：
  1) 8 个 pre-existing probe FAIL 由独立的内容/契约同步任务修复；修复前 CI 的 full-matrix check 以 known-baseline 方式报告，不阻塞 Phase 0 门禁且失败保持可见；
  2) CI 的绿灯语义是「Phase 0 gate 通过 + 无新增回归」，不是「全矩阵全绿」；项目负责人决定 merge 时需接受这一语义；
  3) 已知 20 km vs 420 km 融合距离、side 元数据丢失按计划转 Phase A #2/#4；
  4) `SIM_CORE` 负例校验可考虑扩展 damage/ship_catalog/refit（Issue #14 审阅非阻塞建议，不在本任务实施）。

---

### 附：本报告使用的关键命令与退出码（全部本机实跑）

| # | 命令 | exit |
| --- | --- | --- |
| 1 | `git worktree add D:\gt_verify 3c0800f`；随后 `git status --porcelain` | 0 / 0 行 |
| 2 | `Godot … --version` | 0（`4.7.2.stable.official.ed1daf0bf`） |
| 3 | `Godot … --headless --path D:\gt_verify\game_v17 --import` | 0（17.3s） |
| 4 | `pwsh ./run_tests.ps1`（全矩阵） | **1**（预期：8 pre-existing FAIL；72=64/8/0/0，301.2s） |
| 5 | `pwsh ./run_tests.ps1 -List` / `-Category profile` | 0 / 0 |
| 6 | `-Only plot_tws_probe` / `-Only facility_model_probe` | 1（FAIL 58/1） / 0（PASS 1697/0） |
| 7 | 受控 NOT RUN（缺脚本 / blocked） | 1（非预期） / 0（预期） |
| 8 | 受控 TIMEOUT（`-TimeoutSec 2`）/ 受控 boot marker 缺失 | 1 / 1（Godot exit 0 仍判 FAIL 0/1） |
| 9 | 无 Godot（`-GodotBin` 不存在） | **2**（BLOCKED，全部 NOT RUN 带原因） |
| 10 | `--script res://tests/build_profile_probe.gd` | 0（PASS 553/0） |
| 11 | `--script res://tests/e2e_orbital_sim_probe.gd` | 0（PASS 153/0，3.6s） |
| 12 | `DSH_BUILD=orbital_sim DSH_FLOW_SMOKE=1` 真实主场景 | 0（自动跳 v1_hud，SYSTEMS 全 true） |
| 13 | `DSH_FLOW_SMOKE=1` `res://v1_hud.tscn`（full） | 0（prelude ready=true，与基线同 FLOW SMOKE 行） |
| 14 | `DSH_BUILD=combat_sim DSH_FLOW_SMOKE=1` 真实主场景 | 0（与基线同 FLOW SMOKE 行） |
| 15 | `DSH_BUILD=sandbox DSH_FLOW_SMOKE=1` 真实主场景 | 0 |
| 16 | 基线 `263e97e`：67 probes 全量 | 59 PASS/8 FAIL（逐项复现两次，确定性） |

---

## 11. 验收后处理（Lead 补充，docs-only）

在独立验收（被验收提交 `3c0800f`）之后，Lead 只做了以下**不含代码改动**的处理，因此 §1–§10 的验收结论继续有效：

| 发现项 | 处理 | 提交 |
| --- | --- | --- |
| F1 `build_profiles.md` §12.4 仍写「blocked: true（T1 pending）」 | 已改为：T5 已解除阻塞并跑通全量矩阵（72 cases：64 PASS / 8 pre-existing FAIL / 0 TIMEOUT / 0 NOT RUN），本任务相关 4 个 boot smoke 与 e2e 全 PASS | 本 docs-only 提交 |
| F2 §12.5 e2e `PASS=150` | 已更正为实测 `PASS=153` | 本 docs-only 提交 |
| F4 用户工作区 0 字节 `run_tests.ps1` 误写 | 已确认 0 字节、未跟踪、非用户 WIP 后删除；`D:\GHOST TRACK_APSIS` 已恢复为初始 WIP 状态（main@62356da） | 用户工作区文件，不在本仓库提交 |
| F3 `[SHELL BINDER] SANDBOX entities=` 历史标签 | 纯文案，保留（不影响断言/机器解析）；记录待 Phase A 更名 | 未改 |
| F5 pre-existing SCRIPT ERROR / 8 个 probe FAIL | Phase 0 明确不修，保留如实报告；需独立内容/契约同步任务 | 未改 |
| F6 import 噪音（`.uid` / `.import` stat-dirty） | 环境噪音，不提交；runner/CI 已按要求处理 | 未改 |

Issue #14 之前，代码/配置/测试文件在 `3c0800f` 之后只多了 docs-only 提交；Issue #14 收尾新增了
`run_tests.ps1` 的 `-Gate`/`-Baseline`、`probe_matrix.json` 的 `gates.phase0`、
`known_baseline_failures.json` 与 `.github/workflows/tests.yml` 改造（commit `731a3cd`、`04b0d51`），
这些改动的真实 CI 结果见 §12。

---

## 12. Issue #14：CI artifact 修复与真实 GitHub Actions 证据

> 本节记录 Issue #14（修复 CI 测试产物上传 + Phase 0 门禁/验收报告收尾）的**实际运行结果**。
> 所有数字来自本机 `gh` 读取的 Actions API / 运行日志 / 重新下载的 artifact，不是 YAML 静态推断。

### 12.1 修复前后对照

| 项 | 修复前 run [39778490176](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39778490176) | 修复后 run [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057) |
| --- | --- | --- |
| 触发/分支 | pull_request / `feat/phase0-simulator-first` | pull_request / `phase0/issue-14-ci-closeout` |
| 结论 | failure | **success（两个 job 均 success）** |
| 测试结果 | 72 cases = 64 PASS / 8 FAIL / exit 1 | gate 6/6 PASS；full matrix 72 = 64 PASS / 8 KNOWN-BASELINE FAIL / 0 new / 0 drift / exit 0 |
| artifact | **0 个**；日志 `No files were found with the provided path: .test-results/.` | **2 个 artifact 已上传并可下载**（§12.3） |

根因与修复：`.test-results/` 是点目录（隐藏目录），`actions/upload-artifact@v4` 默认
`include-hidden-files: false`，所以找不到文件；修复为在两个 job 的 upload step 显式设置
`include-hidden-files: true`（保留原输出路径，不改 runner 约定、不搬动产物）。

### 12.2 真实 workflow run（被验证代码提交 `04b0d51`）

- run：**39786721057**，event=`pull_request`，head branch=`phase0/issue-14-ci-closeout`，
  head SHA=`04b0d5157634a7328f0a5f6ba4b07235c913efb0`，conclusion=**success**，
  created 2026-10-22T13:25:37Z / updated 13:30:46Z。
- 两个 check（PR #15 checks 实际显示 pass）：

| job | 结果 | 耗时 | job 链接 |
| --- | --- | --- | --- |
| `Phase 0 gate (required) — profile / boot smokes / real-entry E2E` | **success** | 1m20s | [job/119851773148](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057/job/119851773148) |
| `Full matrix (baseline-aware; known legacy FAILs shown, red only on new regressions)` | **success** | 4m44s | [job/119851773953](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057/job/119851773953) |

- 本 run 覆盖的提交：Issue #14 的 `731a3cd`（runner gate/baseline + matrix gates +
  known_baseline_failures）与 `04b0d51`（workflow + README/test_matrix 文档）。
- 说明：`pull_request` checkout 的是 PR merge ref，因此 runner `summary.json` 的 `git_commit` 记录为
  `8cc1e047…`（PR #15 的 merge commit）；GitHub Actions artifact metadata 绑定的是本次 run id +
  head SHA `04b0d515…`（§12.3 API 可查）。

### 12.3 artifact 上传与下载验证（Issue #14 强制要求）

Actions API 查询（`gh api repos/HATO-24/ghost-track-apsis/actions/runs/39786721057/artifacts`）：

| artifact 名称 | id | 大小 | SHA-256 | 过期 | 绑定 head SHA |
| --- | --- | --- | --- | --- | --- |
| `phase0-gate-results-39786721057-1` | 12428559095 | 26,039 B | `9fdd86da0ef463e0c03a61425ebcf94e7703c0c0a4913d3c290e3813c4421d33` | 2026-11-05 前 | `04b0d515…` |
| `full-matrix-results-39786721057-1` | 12429463292 | 372,318 B | `677c164b6e62cca9578c5ad2a95d7d282f671968414109a97352789e81c01a23` | 2026-11-05 前 | `04b0d515…` |

上传日志（run 日志实摘）：

```text
Phase 0 gate  → With the provided path, there will be 12 files uploaded
              → Uploaded bytes 26039
              → Artifact phase0-gate-results-39786721057-1 has been successfully uploaded!
Full matrix   → With the provided path, there will be 118 files uploaded
              → Uploaded bytes 372318
              → SHA256 digest of uploaded artifact zip is 677c164b… (与 API digest 一致)
              → Artifact full-matrix-results-39786721057-1 has been successfully uploaded!
```

实际下载校验（`gh run download 39786721057 -D .test-results/ci-artifacts/39786721057` → exit 0）：

| 检查项 | gate artifact | full-matrix artifact |
| --- | --- | --- |
| run 目录 | `20261022-132621-8cc1e047/` | `20261022-132607-8cc1e047/` |
| 必备文件 | `summary.json`(8,572 B)、`report.md`(3,052 B)、`import.log`、`logs/` | `summary.json`(70,982 B)、`report.md`(18,546 B)、`import.log`、`logs/` |
| 逐例日志 | 9 个（63,336 B） | 115 个（2,449,573 B） |
| Godot | `4.7.2.stable.official.ed1daf0bf` | `4.7.2.stable.official.ed1daf0bf` |
| import | PASS，exit 0，0 error | PASS，exit 0，0 error |
| totals | total=6 / pass=6 / fail=0 / timeout=0 / not_run=0 | total=72 / pass=64 / **fail=8** / timeout=0 / not_run=0 |
| baseline（仅 full） | — | `known_fail=8`、`new_fail=0`、`baseline_drift=0`、entries=8 |
| runner exit code | 0 | **0**（baseline-aware：无新增回归） |
| 8 个遗留失败可见性 | — | `summary.json` 中 8 条 `status=FAIL` + `baseline.known=true,matches=true`；`report.md` 含 `## Baseline`、逐条 `KNOWN-BASELINE`；控制台日志含 `BASELINE CHECK: known_fail=8 new_fail=0 drift=0` |

结论：**artifact 上传成功且可访问，内容为本次运行真实产物（summary/report/逐项日志），
run id / head SHA / 文件大小 / SHA-256 与 Actions API 一致。**

### 12.4 CI 语义（不误导审阅者）

- `Phase 0 gate (required)`：6 个 Phase 0 必需用例，**必须全绿**；本 run 6/6 PASS。
- `Full matrix (baseline-aware)`：72 cases **全部执行**；8 个遗留失败**仍是 FAIL**（未改名 PASS、未跳过、
  无 `continue-on-error`）；本 run 绿灯的唯一含义是 `new_fail=0 && baseline_drift=0 && timeout=0 &&
  unexpected_not_run=0`，即「**与基线相比无新增回归**」，**不是「全矩阵通过」**。
- 默认命令 `run_tests.ps1`（不带 `-Baseline`）语义不变：当前仍会因 8 个遗留失败 exit 1，可随时本地复核。
- 基线证据措辞（满足 Issue #14 §3）：`known_baseline_failures.json` 与 CI summary 均写明
  “Report-provided baseline evidence, NOT independently re-executed from the audit HEAD in the CI
  environment.”；8 项计数来自 verifier 在审计 HEAD `263e97e` 的独立基线、`docs/54` §2.1 与
  Phase 0 PR head 复跑三者逐项一致。**本任务没有在 CI 环境从审计 HEAD 独立复现基线**。
- 旧 run 39778490176 的 artifact=0 与红灯只作为修复前证据，不作为修复验证。

### 12.5 默认 profile 语义（Issue #14 §4）

`build_profiles.json` 的 `"default"` **仍是 `full`**（本 task 未改）。普通启动（不设 `DSH_BUILD`）
进入剧情构建；进入正式模拟器必须显式 `DSH_BUILD=orbital_sim`（README 已写明）。
"模拟器优先"是开发/验收方向，不是默认值变更；若项目负责人希望把默认值改为 `orbital_sim`，
需单独批准后另行提交。

### 12.6 本任务新增/修改文件（Issue #14）

| 文件 | 变化 |
| --- | --- |
| `run_tests.ps1` | 新增 `-Gate`、`-Baseline` baseline-aware 模式（状态不伪装、known/new/drift 分类、退出码收紧） |
| `game_v17/tests/probe_matrix.json` | `version: 1.0.0` + `gates.phase0`（6 个门禁用例）；72 个既有 case 语义零改动 |
| `game_v17/tests/known_baseline_failures.json` | **新增**：审计 HEAD 8 个 pre-existing 失败、exact counts、原因、follow-up、provenance |
| `.github/workflows/tests.yml` | **重写**：两 job + `include-hidden-files: true` + job summary + 双 artifact 上传；无 continue-on-error |
| `README.md` / `game_v17/docs/test_matrix.md` | `-Gate`/`-Baseline` 用法、两个 CI check 语义、artifact 下载方式、默认 profile 说明 |

### 12.7 Issue #14 验收标准对照

| 验收标准 | 结果 |
| --- | --- |
| 新 Actions run 完成，artifact 上传成功且可访问 | **MET**：run 39786721057 success，2 个 artifact 经 API 查询 + `gh run download` 实际下载校验（§12.3） |
| artifact 含本次运行 summary/report 和逐项日志 | **MET**：见 §12.3 表（72/6 case 的 logs、summary.json、report.md） |
| 完整矩阵失败仍明确展示；无删除/弱化断言造绿灯 | **MET**：8 FAIL 状态保留于 summary/report/log/artifact；72 cases 数量与基线一致；无 probe 修改 |
| Phase 0 必需门禁定义清晰、可审计；CI 不误导 | **MET**：`gates.phase0` 显式定义；两 check 名称/job summary/文档均区分"门禁通过 / 无新增回归 / 全矩阵通过" |
| Phase 0 报告与最新真实运行一致 | **MET**：§6/§9/§10 更新 + 新增 §12（真实 run/artifact 数据） |
| PR 区分专项门禁/完整矩阵/基线遗留 | **MET**：PR #15 描述与 job summary 均按三类表述 |
| 旧剧情 profile 兼容；不改变默认 profile | **MET**：`full` 未改；`boot.full`/`boot.legacy_combat_sim` 在 CI gate 中 PASS |
| 独立 PR，完成后暂停 | **MET**：PR #15（stacked on #13）；未进入 Phase A |

---

## 13. PR #15 审查修正：baseline 门禁 fail-closed（第三轮）

> 触发：PR #15 review（2026-10-22）。审查指出一个**未在本次 CI 实际触发、但门禁必须堵住**的误绿路径：
> 声明为 baseline 的项如果变成 NOT RUN、被 blocked、缺失，或被 `-Only/-Category/-Gate` 过滤掉，
> 旧实现仍可能以 `known_fail=N new_fail=0 drift=0` 成功退出。本节记录修正后的语义、真实 CI 结果、
> selftest 回归与 artifact 核对。

### 13.1 缺陷与修正

| 旧行为（fail-open） | 修正后（fail-closed） |
| --- | --- |
| baseline 项未选入 → `entries_not_selected` 标注 "informational, not drift"，exit 0 | `baseline_unselected>0` → **exit 1**；列出未选入 id |
| baseline 项变 NOT RUN/blocked → 不计入任何统计，exit 0 | `baseline_unverified>0` → **exit 1**；报告 `BASELINE UNVERIFIED` 与原因 |
| 只看 new_fail/drift/timeout | 额外要求每个 baseline entry 实际执行且为 **FAIL + exit/pass/fail 计数完全匹配**；`complete=true` 才允许 exit 0 |
| 筛选运行也能报 "BASELINE MATCH" | 新增 `-AllowPartialBaseline`（本地调试）：明确输出 `BASELINE PARTIAL - NOT a complete baseline verification`，summary `complete=false/verified=false`，绝不出现 "BASELINE MATCH"；CI 不传该开关 |

实现：`run_tests.ps1`（strict 默认 + 覆盖统计 + partial 开关）、新增
`game_v17/tests/baseline_gate_selftest.ps1`（可重复回归 A/B/C/D）、workflow 的 artifact 缺失 fail-closed
断言与 selftest step（见 §13.4）。

### 13.2 修正轮代码提交与被验证 run

- 分支：`phase0/issue-14-ci-closeout`（PR #15），修正提交：
  - `40e95bf` test: baseline 门禁 fail-closed + 可重复回归 selftest；
  - `e73bc69` ci: artifact 缺失 fail-closed + baseline selftest 步骤 + 门禁语义/文档同步。
- **被验证代码提交 `e73bc692c1a4765dec70d8db748cb2b9cd351211`**；
  run **[39795265144](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144)**
  （`pull_request`，conclusion=**success**，created 14:23:35Z / updated 14:36:07Z）。
- 两个 job 均 success：
  - `Phase 0 gate (Phase 0 acceptance)`（[job/119880883143](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144/job/119880883143)）：
    `Run Phase 0 required gate`、`Assert test artifacts exist`、`Upload` 全 success；
  - `Full matrix (baseline-aware)`（[job/119880882889](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144/job/119880882889)）：
    `Run FULL regression matrix`、`Regression — baseline gate fail-closed self-test`、
    `Assert test artifacts exist`、`Job summary`、`Upload` 全 success。

### 13.3 run 39795265144 的真实结果（fail-closed 生效）

- **Phase 0 专项门禁：6/6 PASS，exit 0**（gate artifact）：
  `build_profile_probe 553/0`、`e2e.orbital_sim 153/0`、4 个 boot smoke markers 3/3。
- **完整矩阵：72 cases = 64 PASS / 8 FAIL / 0 TIMEOUT / 0 NOT RUN，exit 0**（full artifact）；
  `BASELINE CHECK: known_fail=8 new_fail=0 drift=0 unverified=0 unselected=0 complete=true`；
  `RESULT: BASELINE MATCH - all 8 baseline entries executed as expected FAIL with matching counts
  (known_fail=8, new_fail=0, drift=0, unverified=0, unselected=0, complete=true)`。
  8 条遗留失败仍为 `status=FAIL` 且 `baseline.known=true`。
- **CI 内 selftest（可重复回归）输出**：
  - Scenario A（baseline 项 blocked → NOT RUN）：`unverified=1 unselected=0 complete=false` →
    `RESULT: BASELINE CHECK FAILED ... unverified=1 ...`；
  - Scenario B（baseline 项被筛选掉）：`unselected=7 complete=false` →
    `RESULT: BASELINE CHECK FAILED ... unselected=7 ...`；
  - Scenario C（筛选 + `-AllowPartialBaseline`）：`RESULT: BASELINE PARTIAL - NOT a complete
    baseline verification (unselected=7, unverified=0)`；
  - 最终 `BASELINE GATE SELFTEST RESULT: PASS=24 FAIL=0 (assertions=24)`，step success。
- **artifact 缺失 fail-closed**：两个 job 的 `ARTIFACT ASSERT OK run_dir=20261022-142403-c3da2bbe
  cases=72 logs=115` / `cases=6 logs=9` 均 success；上传配置 `if-no-files-found: error`。
  对断言逻辑做了**等价本地负例**：把 workflow 中的 Assert 脚本原样提取执行——
  空 `.test-results` → **exit 1**（`ARTIFACT ASSERT FAILED: no .test-results run directory was produced`）；
  构造完整假 run dir → exit 0。证明"无文件上传步骤会失败"不是静态声明。

### 13.4 artifact 清单与核对（run 39795265144）

Actions API（`gh api .../runs/39795265144/artifacts`，均未过期、绑定 head `e73bc69…`）：

| artifact | id | 大小 | SHA-256 | 下载核对 |
| --- | --- | --- | --- | --- |
| `phase0-gate-results-39795265144-1` | 12431684980 | 26,103 B | `e2dbe7b7d3dc255619c1be77c58b434521862e50006a4787ceaa9d35f16f0851` | `gh run download` exit 0；12 files；9 个逐例日志 |
| `full-matrix-results-39795265144-1` | 12432368909 | 372,766 B | `47872c8104a31ff3dbe7d551f0d390a8171550474e02a8438d96a27c2f1c3bcf` | `gh run download` exit 0；118 files；115 个逐例日志 |

解包核对（summary/report/日志属于同一 run）：

- 两个 artifact 的 run 目录均为 **`20261022-142403-c3da2bbe`**；`summary.run_id` = 目录名；
  Godot `4.7.2.stable.official.ed1daf0bf`；
- gate `summary.json`：`total=6/pass=6/fail=0/exit=0/gate=phase0`；
- full `summary.json`：`total=72/pass=64/fail=8/timeout=0/not_run=0/exit=0`，
  `baseline.complete=true`、`verified=true`、`partial=false`、`coverage={required:8,selected:8,executed:8,verified:8}`、
  `unverified=0`、`unselected=0`；`report.md` 含 `## Baseline`、coverage 表与 `KNOWN-BASELINE` 行；
- 上传日志实摘：`include-hidden-files: true`、`there will be 118 files uploaded`、
  `Artifact full-matrix-results-39795265144-1 has been successfully uploaded! Final size is 372766 bytes`；
  gate 为 12 files / 26,103 B；与 API 的 size/digest 一致；
- 说明：`pull_request` checkout 是 PR merge ref，runner summary 的 `git_commit` 为 merge commit
  `c3da2bbe…`；artifact metadata / run headSha 为 `e73bc69…`，与上表一致。

### 13.5 历史 run 映射（评审要求）

| run | 对应提交 | 性质 | 结果 |
| --- | --- | --- | --- |
| [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057) | `04b0d51` | **代码提交验证** | 两 job success；72=64/8/0/0；artifact 已下载校验（§12） |
| [39787908114](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39787908114) | `e150c9446221e6d75357b869ac4affbe171b69ee`（**最终 docs-only head 复核**） | 两 job success；结果与 39786721057 一致；artifact 已下载校验（§12） |
| [39795265144](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144) | `e73bc69` | **本轮 fail-closed 修正的代码提交验证** | 两 job success；72=64/8/0/0，complete=true；§13.3/§13.4 |

- 本轮修正后的最终 docs-only head（包含本节报告更新）会触发最后一个复核 run；它只改文档，
  测试用例与上述 run 逐项一致，其链接记录在 PR #15 描述中（报告无法引用触发自身的 run id）。
- 以上 run 的共同事实：**Phase 0 gate 6/6 PASS；完整矩阵 64 PASS / 8 FAIL / 0 NOT RUN / 0 TIMEOUT**；
  8 个失败与审计 HEAD 基线逐项一致，保持 FAIL 可见。

### 13.6 branch protection 检查（如实陈述）

- `gh api repos/HATO-24/ghost-track-apsis/branches/main/protection` 与
  `.../branches/feat/phase0-simulator-first/protection` 均返回 **HTTP 403**：
  `Upgrade to GitHub Pro or make this repository public to enable this feature.`
  → **无法确认**是否有 branch protection / required status checks。
- 因此本文只陈述：`Phase 0 gate` 与 `Full matrix` 两个 job 在 **clean 代码提交 run 39795265144**
  中实际运行并通过且 job 记录为 completed/success；**不把 job 名称当作保护规则已生效的证据**；
  job 名称已从 `Phase 0 gate (required)` 改为 `Phase 0 gate (Phase 0 acceptance)` 以避免误导。
- 最终 head 的 check 记录受 2026-10-22 GitHub Actions Results 平台事故影响（见 §13.9），
  该 run 以 run-level conclusion 与真实 artifact 为准，不以 stale job/check 记录为准。
- 若项目负责人需要将门禁设为强制合并条件，需在仓库 Settings → Branches 中配置（私有仓库需 GitHub Pro）。

### 13.7 本轮验收标准对照（PR #15 review）

| 验收标准 | 结果 |
| --- | --- |
| 自动化回归证明 baseline NOT RUN/被阻塞/未选入都会失败 | **MET**：CI selftest step success（`PASS=24 FAIL=0`），A=unverified=1、B=unselected=7 均输出 `BASELINE CHECK FAILED`；本地 `baseline_gate_selftest.ps1` 同样 PASS=24 |
| 新 run 中 Phase 0 gate 6/6；完整矩阵 72 项 = 64 PASS/8 FAIL/0 TIMEOUT/0 NOT RUN | **MET**：run 39795265144（§13.3） |
| baseline 仅在全部执行且计数匹配、无新增/漂移时成功 | **MET**：strict 默认 + `complete=true` 才 exit 0；`unverified/unselected/drift/new_fail` 任一非零 → exit 1 |
| artifact 缺失使检查失败；更新后 artifact 可下载核对 | **MET**：Assert 步骤 + `if-no-files-found: error`（CI 实际 success 且本地负例 exit 1）；两个 artifact 已下载核对（§13.4） |
| 验收报告与最终 head 运行记录一致 | **MET（结构化，含平台事故说明）**：§13.5 给出 run/commit 映射；最终 head 复核 run 39797358545 的真实 artifact 已下载核对；该 run 的 check 记录受 GitHub Actions 平台事故影响（§13.9），以 run-level conclusion + artifact 为准 |
| 不删除测试/不放宽断言/不跳过失败/不改默认 profile/不进入 Phase A | **MET**：diff 无 probe/断言删除或弱化；8 FAIL 保持 FAIL；`default=full` 未改；未进入 Phase A |

### 13.8 本轮 NOT RUN / 未解决问题

- **GitHub Actions 平台事故期间的 final-head check 记录**：run 39797358545 的 job/check 记录
  在不同 attempt 中 stale（详见 §13.9）；代码/artifact 证据成立，但"最终 head 在 PR 上显示全绿
  check"需平台恢复后重跑回填（非代码问题）。
- `baseline_gate_selftest.ps1 -IncludeFullRun` 的场景 D（本地全量 strict）未单独执行：CI 的 full-matrix
  run 本身已覆盖同一路径（72=64/8/0/0、complete=true）。
- artifact 缺失路径没有在生产 CI 中实际触发（否则等于故意破坏流水线）；用**等价本地负例**验证其失败语义。
- branch protection/required checks 无法读取（403），见 §13.6。
- 8 个 pre-existing probe FAIL 仍未修复（Phase 0 范围外，保持可见、follow-up 已在
  `known_baseline_failures.json`）；非 headless 渲染、`DSH_SHOT`、Linux/macOS wrapper、orbital_sim
  存档 round-trip 仍未运行。
- 默认 profile 保持 `full`（`DSH_BUILD=orbital_sim` 显式进入正式模拟器）；未改产品默认值。

### 13.9 GitHub Actions 平台事故（2026-10-22T14:18:15Z 起，外部故障）

- GitHub Status API：**"Incident with Actions Results"**（impact=minor，组件 Actions
  **degraded_performance**，说明为 "delays affecting GitHub Actions workflow and step results"），
  shortlink：https://stspg.io/44w94j036yc8 。与本轮 final-head run 的时间窗口完全重合。
- 观测到的具体症状（均只在 GitHub 的 job/check 记录侧，**run-level conclusion 与 artifact 正常**）：
  - attempt 1：run success，gate check pass；full-matrix artifact 已成功上传，但该 job 记录停在 `queued`；
  - attempt 2：run success，full-matrix check pass（6m58s）；gate artifact 已成功上传，但 gate job 记录停在 `queued`；
  - attempt 3（仅重跑 gate）：run success，attempt-3 gate artifact（26,105 B，sha256 `5d611769…`）
    已上传且日志完整（`PHASE0_GATE_EXIT=0`、`ARTIFACT ASSERT OK`、`successfully uploaded`），
    但 gate job 记录停在 `in_progress`，PR checks 显示 pending。
  - 事故期间 attempt-1 的 full artifact（id 12434341983）随后在 API 中变为 **404/不可达**；
    因此本文/PR 只把 **attempt-2/3 的可下载 artifact** 作为 final-head 的执行证据。
- 证据层级（本轮最终结论采用）：
  1. **主 CI 证据 = clean 代码提交 run [39795265144](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144)**
     （head `e73bc69`）：两个 job 记录 completed/success；gate 6/6；full 72=64/8/0/0、`complete=true`、
     selftest `PASS=24`；两个 artifact 已下载并按 API digest 校验（§13.3/§13.4）。
  2. **最终 head 39797358545 执行证据 = attempt-2 full artifact（72=64/8/0/0、complete=true、115 logs）+
     attempt-3 gate artifact（6/6、exit 0）**，均已实际下载核对；
  3. run-level conclusion=success；**不把 stale job/check 记录当作失败或通过证据**。
- 处置：等 GitHub 平台恢复后可对该 head 重跑以回填 clean check（仅流程性操作，不改代码）；
  在此之前 PR 上 gate check 可能仍显示 pending，属外部事故，已在此与 PR 描述中如实披露。


