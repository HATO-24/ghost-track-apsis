# Phase 0 · 执行前检查与实施计划

> 执行日期：2026-10-22
> 开发分支：`feat/phase0-simulator-first`（基于审计分支 HEAD `263e97e`）
> 工作目录：干净 worktree `D:\gt_phase0`（用户的 `D:\GHOST TRACK_APSIS` 工作区含未提交的模型改动，保持不动）
> 目标：GitHub Issue #1（模拟器优先 profile）与 #5（可重复的 headless 回归与端到端测试矩阵）
> 交付边界：完成 Phase 0 后暂停，等待人工审阅，不进入 Phase A。

---

## 1. 执行前检查结果

### 1.1 仓库、分支、工作区

| 项 | 实际状态 |
|---|---|
| 当前 `main` | `62356da 方案B-40：四类空间站独立拆分+人口功能自动匹配；…` |
| 审计分支 | `audit/2026-10-cislunar-simulator` = `263e97e docs: add simulator-first systems audit and task queue` |
| 本任务基线 | `263e97e`（`main` + 1 个纯文档提交） |
| 开发分支 | `feat/phase0-simulator-first`，从 `origin/audit/2026-10-cislunar-simulator` 建立 |
| 用户工作区 `D:\GHOST TRACK_APSIS` | 在 `main`，含 8 个已修改文件、1 个已删除文件、若干未跟踪模型/mockup 文件（模型相关 WIP）。**本任务不触碰该工作区。** |
| 开发 worktree | 独立干净 worktree `D:\gt_phase0`，避免 WIP 污染导致测试结果不可复现 |
| Godot | `4.7.2.stable.official.ed1daf0bf`（`tools/godot/Godot_v4.7.2-stable_win64_console.exe`，仓库内 `tools/` 被 gitignore） |
| 工程 | `game_v17/project.godot`（config_version=5，main_scene=`res://main_menu.tscn`，GL Compatibility） |

仓库体量复核（审计 HEAD）：272 个 `.gd`、54 个 `.json`、32 个 `.tscn`；`game_v17/tests/*_probe.gd` 受版本管理 **67 个**；`game_session.gd` 实测 4,872 行。

### 1.2 PR #12 与审计文档状态（重要）

- `gh pr view 12`：**OPEN，未合并**。`baseRefName=main`、`headRefName=audit/2026-10-cislunar-simulator`、`mergeCommit=null`。
- 审计文档 `docs/40_系统完成度复核与开发任务队列.md` **不在 `main` 上**，只存在于审计分支提交 `263e97e`。
- 处理方式：本分支直接基于审计分支 HEAD，因此审计文档在分支内可读；本 PR 叠加在 `#12` 之上（stacked PR），评审说明中会突出这一点。若 #12 先被合并，本分支 rebase 后即等价于基于 `main`。
- 结论：**不得假设审计文档已在 `main`**；本分支的文档引用以 `263e97e` 中的版本为准。

### 1.3 Issue #1 / #5 与当前代码的一致性核对

状态口径：已完成 = 代码+运行证据；部分完成 = 有代码但缺验收；过时 = 描述与当前代码不符；未验证 = 本轮未运行，不能当结论。

#### Issue #1（模拟器优先 profile）

| Issue 中的描述 | 当前代码事实 | 状态 |
|---|---|---|
| 主场景为 `res://main_menu.tscn` | `game_v17/project.godot` 第 6 行确认 | 已完成 |
| `build_profiles.json` 默认 `full`（story/prelude/triggers 开启） | 配置确认，`default="full"` | 已完成 |
| `combat_sim` 关闭剧情，但 `traffic=false`、`port=false`，且开启 `unlimited_ammo`、`auto_authorize` | `game_v17/framework/content/build_profiles.json` 确认；`build_profile.gd` 的 `sandbox_opts` 只在 `boot_mode=="sandbox"` 生效 | 已完成 |
| `shell_binder.gd` 可按 BuildProfile 组装 GameSession | `shell_binder.boot()` / `_sandbox_seed()` 确认 | 部分完成（尚无真实模拟器 profile 的系统装配与 ready 日志） |
| 需要独立 `orbital_sim` 拟真剖面 | 当前不存在；只有 `full` / `combat_sim` 两个配置 | 未实现（本任务交付） |
| 剧情/序章/触发器必须保留、可独立启动 | `full` + `PreludeScenario` 路径完整 | 已完成（本任务必须不破坏） |
| 模拟器不得默认免弹药/免授权 | 现有 `combat_sim` 默认两者全开 → 不符合拟真目标 | 待实现（本任务以新 profile 解决，旧条目保留兼容） |
| 不得为启动而关闭核心系统 | 现状 `combat_sim` 恰好关掉 traffic/port → 不符合 | 待实现（新 profile 必须开启） |
| 明确标识未实现功能 | 配置无 limitations 字段，启动日志无系统开关/缺口清单 | 待实现 |

#### Issue #5（统一回归与 E2E 矩阵）

| Issue 中的描述 | 当前代码事实 | 状态 |
|---|---|---|
| `game_v17/tests` 已有大量 SceneTree probes | 受版本管理 67 个 `*_probe.gd`，覆盖战斗/弹道/物理/传感器/EW/IFF/traffic/docking/refit/save/profile 等 | 已完成 |
| 多份文档记录历史 PASS，但本轮未重跑 | 审计文档 §6 明确未运行；本次基线仅重跑了 `build_profile_probe`（PASS=191 FAIL=0） | 未验证（本任务建立统一入口后全量重跑） |
| 仓库无 `.github/workflows` / CI | 确认不存在 | 已完成（本任务新增） |
| 缺统一可重复入口与端到端组合测试 | 只有零散 probe 命令写在各文档；无矩阵、无机器可读摘要、无单命令入口 | 待实现 |
| README 未反映 V17 状态与测试命令 | `README.md` 仍是 V1.5 时期内容（目录、状态、Demo 段均过时） | 待实现（本任务最小修订） |
| 需要一条真实入口 E2E（main_menu → v1_hud → ShellBinder → GameSession + 战斗流程） | 现有 `DSH_V1_TEST`/`DSH_FLOW_SMOKE` 只是 HUD 自测打印，不是断言式 E2E probe | 待实现 |

### 1.4 本轮实测基线（审计 HEAD `263e97e`，Windows，Godot 4.7.2）

先执行资产导入（新 worktree 必须）：

```powershell
& '.\tools\godot\Godot_v4.7.2-stable_win64_console.exe' --headless `
    --path 'D:\gt_phase0\game_v17' --import
# exit 0；约 16.6 s；产出 .godot/imported（否则音频 sample 缺失，会打印 ERROR 噪声）
```

| 检查 | 命令摘要 | 结果 |
|---|---|---|
| Godot 版本 | `Godot_v4.7.2-stable_win64_console.exe --version` | `4.7.2.stable.official.ed1daf0bf`，exit 0 |
| Profile probe | `--headless --path game_v17 --script res://tests/build_profile_probe.gd` | **PASS=191 FAIL=0**，exit 0 |
| 旧沙盒 boot smoke | main scene，`DSH_BUILD=combat_sim`、`DSH_FLOW_SMOKE=1`、`--quit-after 5000` | exit 0；日志含 `[MAIN MENU] BUILD=combat_sim → skip to res://v1_hud.tscn`、`[SHELL BINDER] BUILD profile=combat_sim mode=sandbox`、`SANDBOX entities=7`、`FLOW SMOKE COMPLETE` |
| 剧情 boot smoke | `res://v1_hud.tscn` 作为场景，`DSH_BUILD=full`、`DSH_FLOW_SMOKE=1` | exit 0；日志含 `BUILD profile=full mode=prelude`、`prelude ready=true entities=9 triggers=3`、`FLOW SMOKE COMPLETE` |

已知无害噪声：headless 主菜单切换场景时出现一次
`ERROR: Parent node is busy adding/removing children...`（引擎级、非致命、既有行为）。回归入口需要记录该噪声但不能仅因此判 FAIL；判定以退出码、断言结果和期望标记为准。

### 1.5 审计结论与当前代码的差异 / 需修订项（初始清单）

1. **已确认**：审计关于 `combat_sim`（traffic/port 关闭 + 便利项全开）、默认 `full`、无 CI、probe 数量与体量的描述与代码一致。
2. **需修订**：审计 §6 声明未运行 Godot；本轮已实际运行（见 §1.4），历史文档中的 PASS 数不作为当前提交结论，只作基线。
3. **需说明**：审计 §1.7 提到 `scripts/ui/near_view.gd` 存在 —— 该文件在用户未提交的 WIP 中被删除，但审计分支/本分支 HEAD 仍保留；此差异属于用户工作区改动，不属于审计错误。
4. **需修订**：审计对 `game_session.gd` 的行数表述（约 4,873）与实测（4,872）仅差 1 行，无须修订，仅记录。
5. **需补充**：审计结论中“当前 main head 未跑全量 probe”的空白，将由本任务建立的统一入口 + 全量矩阵执行结果补齐（真实 FAIL 照实报告，不修饰）。

---

## 2. 实施计划

### 2.1 目标与设计决策

**Task #1（Issue #1）—— profile 分层（不新增剧情）**

| profile | 定位 | boot_mode | 剧情/序章/触发器 | 核心系统 | 便利项 | 存档根 |
|---|---|---|---|---|---|---|
| `full` | 正式剧情构建（默认，保留原行为） | `prelude` | 开 | 全开 | 强制关 | `user://saves` |
| `orbital_sim`（新） | **正式拟真模拟器** | `simulator`（新） | 关 | 物理/传感器/识别/信号/战斗/弹道/损管/交通/港口/舰船目录/改装 全开 | **无**（免弹药/免授权不可用） | `user://saves_sim` |
| `sandbox`（新） | 开发测试 sandbox | `sandbox` | 关 | 全开 | 免弹药/免授权/快速重开全开（仅此 profile） | `user://saves_sandbox` |
| `combat_sim`（保留） | 旧演示 profile，兼容旧命令/存档 | `sandbox` | 关 | 保持现状（traffic/port 关） | 保持现状 | `user://saves_sim` |

设计约束：

- 默认 profile 不悄悄改变：仍为 `full`；开发进入模拟器用显式命令 `DSH_BUILD=orbital_sim`。
- 新正式模拟器不通过关闭核心系统换取启动成功：traffic/port/docking 相关系统必须开启并报告 ready；若配置试图关闭核心系统，加载器给出明确告警/错误。
- 未实现能力不得伪装：profile 配置新增 `limitations`（≥6 条，来自审计的真实缺口），启动日志逐条输出 `[BUILD PROFILE][LIMITATION]`；系统状态只报告真实服务对象的 ready。
- 旧剧情路径（PreludeScenario / story_state / 剧情触发器 / 内容）不删除、不破坏；模拟器不创建 `story_state`，也不因缺失 story 报错。
- 运行时装配必须验证，而非只检查 JSON：以两种 profile 的真实启动日志 + probe 断言为准。

**Task #5（Issue #5）—— 统一回归入口**

- 仓库根 `run_tests.ps1`：一条命令跑矩阵；Godot 发现（参数/env/tools/PATH，绝不写死个人绝对路径）；导入预检；`DSH_*`/`V17_*` 环境隔离；超时与逐例日志；机器可读 `summary.json`（probe/exit code/pass-fail/duration/commit/profile/log）；真实 PASS/FAIL/TIMEOUT/NOT RUN；任何 FAIL/超时/导入错误非零退出；缺 Godot → 环境阻塞（NOT RUN，非 PASS）。
- `game_v17/tests/probe_matrix.json`：67 个已跟踪 probe 归类（profile/unit/content/integration/e2e），不重复建设功能相同的测试；新增 boot smoke（full / orbital_sim / sandbox / 旧 combat_sim）与 E2E。
- 新 E2E probe：真实入口 `main_menu → v1_hud → ShellBinder → GameSession`，执行一条真实交战流程（含未授权 FIRE 被拒、弹药真实扣减、弹道/命中或脱靶的真实结果）。
- CI：`.github/workflows/tests.yml`，固定 Godot 4.7.2；**本地无法执行 CI，报告中标记 NOT RUN，不以 workflow 文件冒充已通过 CI**。
- README / `game_v17/docs/test_matrix.md`：入口、版本、命令、矩阵、结果解释与当前真实结果；不抄袭历史 PASS 数。

### 2.2 文件与写作用域（并行分工，互不重叠）

| 任务 | 负责人 | 写作用域 | 验收 |
|---|---|---|---|
| T1 profile | profile-dev | `game_v17/framework/content/build_profiles.json`、`game_v17/framework/content/scenario_orbital_sim.json`、`game_v17/scripts/core/build_profile.gd`、`game_v17/scripts/ui/main_menu.gd`、`game_v17/scripts/ui/shell_binder.gd`、`game_v17/tests/build_profile_probe.gd`、`game_v17/docs/build_profiles.md` | probe 全绿；orbital_sim/full/sandbox/combat_sim 四条 boot smoke 真实退出码；日志含 profile/系统开关/ready/limitations |
| T2 回归入口 | test-infra | `run_tests.ps1`、`game_v17/tests/probe_matrix.json`、`.github/workflows/tests.yml`、`README.md`、`game_v17/docs/test_matrix.md`、`.gitignore` | 一条命令可跑；summary 真实；环境隔离；FAIL 非零退出；旧 probe 全量基线如实记录 |
| T3 E2E | e2e-dev | `game_v17/tests/e2e_orbital_sim_probe.gd`（新文件） | 真实入口跑通 + 战斗流程；orbital_sim 无剧情状态/无便利项 |
| T4 独立验证 | verifier | `docs/54_Phase0_验收报告.md`（仅最后阶段） | 干净 worktree 独立复跑；逐项验收 #1/#5；APPROVE/BLOCK |
| 集成/PR | Lead | `docs/52`（本文件）、提交、PR | 全部真实结果汇总；PR 可审阅 |

### 2.3 依赖与顺序

1. T1、T2、T3 可并行（T3 先用旧 `combat_sim` 验证真实入口 harness；T1 落地后切 `orbital_sim`）。
2. T2 的 orbital_sim/sandbox boot case 在 T1 完成前为 **NOT RUN（blocked）**，不得记为 PASS。
3. T4 阶段 A（审计 HEAD 独立基线）立即启动；阶段 B（最终验收）在 T1/T2/T3 全部完成、Lead 给出最终 commit SHA 后执行。
4. Lead 在关键节点提交（小步），最终跑全矩阵 + boot smoke + E2E 后推送分支、开 PR，然后暂停等待人工审阅。

### 2.4 潜在回归风险与缓解

| 风险 | 缓解 |
|---|---|
| JSON 配置改了但运行时没装配 | boot smoke 断言真实日志 + `systems_vm()` 真实对象 ready；不只看 JSON |
| full 剧情路径被破坏 | full boot smoke（prelude ready / entities / triggers）+ 剧情内容零改动 + 保留 story_state 契约 |
| 旧 `combat_sim` 命令/存档失效 | `combat_sim` 条目行为保持不变，仅标记 deprecated；boot smoke 回归 |
| 新场景几何/帧约定错误导致实体错位 | 新场景沿用 `scenario_combat_sandbox.json` 的真实 bary_rot EML1 几何；probe 断言关键距离/own_entity |
| 全量 probe 有既有失败 | 先跑审计 HEAD 基线，区分既有失败与本次回归；不隐藏、不弱化断言 |
| 环境变量/顺序影响结果 | runner 每例前后清理 `DSH_*`/`V17_*`，固定顺序与超时 |
| CI 无法本地执行 | CI 标记 NOT RUN；本地入口与 CI 使用同一脚本，以本地真实结果为准 |
| 用户 WIP 干扰 | 独立 worktree；不触碰 `D:\GHOST TRACK_APSIS`；最终 diff 只含 Phase 0 文件 |
| 并行写冲突 | 各任务写作用域互斥；Lead 统一提交；共享文件（probe_matrix/README）由单一 owner 维护 |

### 2.5 验收命令（最终以真实执行记录为准）

```powershell
# 0) 环境
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --version

# 1) 统一回归入口（含矩阵内 boot smoke / E2E）
pwsh .\run_tests.ps1

# 2) profile 专项
... --headless --path game_v17 --script res://tests/build_profile_probe.gd

# 3) 正式模拟器真实入口 boot smoke（主菜单自动进入战术台）
$env:DSH_BUILD='orbital_sim'; $env:DSH_FLOW_SMOKE='1'
... --headless --path game_v17 --quit-after 5000

# 4) 剧情构建 boot smoke
$env:DSH_BUILD='full'; $env:DSH_FLOW_SMOKE='1'
... --headless --path game_v17 res://v1_hud.tscn --quit-after 5000

# 5) E2E
... --headless --path game_v17 --script res://tests/e2e_orbital_sim_probe.gd
```

判定口径：退出码 0 + 断言结果 + 期望日志标记同时满足才可记 PASS；未执行一律记 NOT RUN，并说明原因。

---

## 3. 开发纪律（本任务自我约束）

1. 先读代码与文档再改；复用现有 BuildProfile/ShellBinder/Probe 骨架，不做无关重构。
2. 只做 Phase 0 范围；不新增剧情内容；不删除旧剧情路径与存档 schema。
3. 不以降低断言、跳过测试、关闭核心系统制造完成假象；核心系统被关闭时加载器必须报错/告警。
4. 配置修改必须有运行时装配证据；历史 PASS 数不作为本次结果。
5. 任何未执行测试/未验证项写 NOT RUN，并给出阻塞原因。
6. 完成 Phase 0 后暂停，不进入 Phase A。
