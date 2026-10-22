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
| 2 | CI 报告所有运行 probe 并在失败时红灯；main 合并前必须通过 | **部分 MET / CI NOT RUN** | runner 实测：72/72 case 全部入 `summary.json`（含 NOT RUN 原因）、任何 FAIL/TIMEOUT/非预期 NOT RUN → exit 1；`.github/workflows/tests.yml` 存在且固定 Godot 4.7.2+SHA256、失败即 job 红，但**本机无法执行 Actions → CI 状态 NOT RUN**。“main 合并前通过”因 8 个 pre-existing FAIL（明确不修）当前不可能全绿，属 Phase 0 外内容/契约同步任务（见 §8） |
| 3 | 至少一个 simulator integration test 沿真实入口启动并执行一条战斗流程 | **MET** | `e2e.orbital_sim` PASS 153/0：真实 `main_menu→v1_hud→ShellBinder→GameSession`，真实未授权拒绝/授权/FIRE/弹道/impact/损管，非伪造 |
| 4 | README 入口、版本、测试命令与当前实现一致 | **MET** | README 已更新 V17/Godot 4.7.2/四剖面启动命令/`pwsh ./run_tests.ps1`；CI 状态明确写“本地无法执行，NOT RUN/未验证” |

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
| §1.8/§2「自动回归/CI」：缺统一入口与端到端组合测试，当前结果未验收 | 已交付 `run_tests.ps1` + `probe_matrix.json`（72 case）+ 真实入口 e2e + CI workflow；本报告给出当前提交真实结果（64 PASS/8 pre-existing FAIL）；CI 执行仍 NOT RUN/未验证 |
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
| GitHub Actions CI 实际执行 | **NOT RUN** | 本机无法运行 Actions；workflow 仅静态审查（固定 Godot 4.7.2+SHA256、失败红灯、artifact 只含 `.test-results/`） |
| Linux/macOS `run_tests.sh` 实跑 | **NOT RUN** | 本机为 Windows；脚本仅静态审查（薄封装 pwsh，缺 pwsh 时 exit 2） |
| 非 headless / 窗口化渲染 | **NOT RUN** | 验收范围仅 headless 回归；渲染路径与性能未测量 |
| `DSH_SHOT` 截图模式 | **NOT RUN** | 同上；文档明确未验证 |
| orbital_sim `user://saves_sim` 存档 round-trip | **NOT RUN** | 超出 Phase 0 范围；`save_probe` 另有 pre-existing FAIL（内容漂移） |
| 导入失败路径的端到端负例 | 未复现（逻辑审查） | 代码审查确认 import 非零/error 行 → 环境阻塞 exit 2；未故意破坏导入做真机负例 |
| GitHub PR / main 合并门禁 | **NOT RUN** | 验证时分支已推送（origin=3c0800f），但 Phase 0 PR 尚未创建/合并；PR #12 为审计 PR |

---

## 10. 最终结论

**APPROVE（Phase 0 通过）。**

- 最终提交 `3c0800f` 在 pristine worktree 独立复跑：`build_profile_probe` PASS 553/0、
  `e2e.orbital_sim` PASS 153/0、四个 boot smoke（full/orbital_sim/legacy_combat_sim/sandbox）全 exit 0 且
  marker 3/3；统一矩阵 **72 cases = 64 PASS / 8 FAIL / 0 TIMEOUT / 0 NOT RUN / exit 1**，
  8 个 FAIL 与审计 HEAD 独立基线逐项一致（同计数、同 case），**无新增失败、无断言弱化、无测试删除、
  无故事路径/核心系统删除或禁用**，full 与 legacy 行为与基线逐字节一致。
- Issue #1 四项验收全部满足；Issue #5 三项满足、CI 项因本机不可执行记 NOT RUN（runner 红灯语义已受控验证）。
- 无阻塞项（BLOCK list 为空）。放行条件（非阻塞、需后续任务消化）：
  1) 8 个 pre-existing probe FAIL 由独立的内容/契约同步任务修复前，CI 将保持红灯（Phase 0 不负责，已如实披露）；
  2) CI workflow 首次 GitHub 实跑结果需回填（NOT RUN→实际状态）；
  3) 建议 docs-only 修正 F1/F2 两处滞后陈述；
  4) 已知 20 km vs 420 km 融合距离、side 元数据丢失按计划转 Phase A #2/#4。

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

代码/配置/测试文件自 `3c0800f` 起未再改动：本 PR head 相对被验收提交只多一个 docs-only 提交（本报告与上述两处文档修正）。若需最终确认，可核对：

```powershell
git diff --stat 3c0800f..HEAD
# 预期仅 docs/54_Phase0_验收报告.md 与 game_v17/docs/build_profiles.md，且无 .gd/.json/.ps1/.yml 改动
```
