# V17 Headless 测试矩阵与统一回归入口

> 适用：`game_v17/`（Godot 4.7.2，主场景 `res://main_menu.tscn`）。
> 入口：仓库根目录 `run_tests.ps1`（Windows PowerShell 5.1 / PowerShell 7+）；
> 跨平台薄封装：`run_tests.sh`（需要 `pwsh`）。
> 矩阵清单：`game_v17/tests/probe_matrix.json`（schema `probe_matrix.v1`）。
>
> 本文档只记录**本仓库当前真实执行结果**；不复制其它文档中的历史 PASS 数。
> 历史运行记录（Phase 0 时期 72 cases）统一放在 §7A 并明确标注为历史，不与当前结果混用。

---

## 1. 一条命令跑回归

```powershell
# 仓库根目录
pwsh ./run_tests.ps1                 # 全矩阵（74 cases：69 probes + 1 e2e + 4 boot smoke）
pwsh ./run_tests.ps1 -List           # 只列出解析后的矩阵，不要求 Godot
pwsh ./run_tests.ps1 -Category profile
pwsh ./run_tests.ps1 -Category boot
pwsh ./run_tests.ps1 -Only 'damage|story_text'
pwsh ./run_tests.ps1 -TimeoutSec 300 -NoImport
pwsh ./run_tests.ps1 -Ci             # CI 模式：无颜色
```

Linux / macOS（pwsh 7+）：

```bash
./run_tests.sh -List
GODOT_BIN=/usr/local/bin/godot ./run_tests.sh -Ci
```

### 参数

| 参数 | 说明 |
| --- | --- |
| `-GodotBin <path>` | 显式指定 Godot 可执行文件（最高优先级） |
| `-Category <name>` | 逗号分隔的分类过滤：`profile` / `content` / `unit` / `integration` / `e2e` / `boot` |
| `-Gate <name>` | 按矩阵 `gates` 选择专项门禁用例（当前 `phase0`；与 `-Category`/`-Only` 可叠加）；未知 gate → exit 2 |
| `-Baseline <path>` | baseline-aware 模式（**strict fail-closed**）：已知遗留失败仍显示 FAIL；每个 baseline 项必须实际执行成预期 FAIL 且计数匹配，否则 exit 1（见 §3.3） |
| `-AllowPartialBaseline` | **仅本地筛选调试**：允许未选入的 baseline 项不导致失败，但输出 `BASELINE PARTIAL`、summary `complete=false`，绝不报告为完整 baseline 通过；CI 不使用 |
| `-Only <regex>` | 对 case id 或目标（`res://` 路径）做正则过滤 |
| `-List` | 只打印矩阵并退出（exit 0），不要求 Godot |
| `-NoImport` | 跳过 `--import` 预检（不建议用于新 worktree） |
| `-TimeoutSec <n>` | 覆盖所有用例的 per-case 超时；不传则逐用例使用矩阵 `timeout_s` |
| `-Ci` | 非交互、无颜色 |
| `-Matrix <path>` | 自定义矩阵清单路径（默认 `game_v17/tests/probe_matrix.json`） |
| `-ResultsDir <path>` | 结果根目录（默认 `.test-results`，已 gitignore） |

### Godot 发现顺序

1. `-GodotBin <path>`
2. `$env:GODOT_BIN`
3. `tools/godot/Godot*console.exe`（仓库本地工具目录，`tools/` 已 gitignore，不提交二进制）
4. PATH 上的 `godot` / `godot4`

全都找不到时：打印 BLOCKED/NOT RUN 表、写 summary/report、**exit 2**（绝不 exit 0）。

### 版本与缓存策略

- 目标版本 **Godot 4.7.2 stable**；每次运行记录 `--version` 原始字符串（如
  `4.7.2.stable.official.ed1daf0bf`）。与矩阵 `godot_version` 不一致时记录 MISMATCH 警告，
  不静默通过也不硬失败；以日志与 summary 中的版本为准。
- 本地：把 `Godot_v4.7.2-stable_win64_console.exe`（及同目录主程序）放进 `tools/godot/`。
- CI：固定下载 `Godot_v4.7.2-stable_win64.exe.zip`，用官方 SHA-256 校验后解压到
  `tools/godot/`，并按版本+SHA-256 做 `actions/cache`；不会上传游戏内容或密钥。

---

## 2. 矩阵分类

| 分类 | 数量 | 含义 |
| --- | --- | --- |
| `profile` | 1 | 构建剖面加载/选择/回退/sandbox 守卫（`build_profile_probe`） |
| `content` | 8 | schema / 内容数据 / 目录与映射校验（schema、facility registry/model、ship catalog、damage profiles、story text、prelude scenario、ephemeris） |
| `unit` | 37 | 单服务/模型契约（物理、战斗、传感器、EW、IFF、轨迹、交通、对接、港口、改装、存档、设置、剧情运行时…） |
| `integration` | 21 | 跨服务编排 / V15↔V2 bridge / 剧情链 / session / 报告 |
| `e2e` | 1 | 真实入口 `main_menu → v1_hud → ShellBinder → GameSession`（`e2e_orbital_sim_probe`） |
| `boot` | 4 | 剖面 boot smoke：`full` / `legacy_combat_sim` / `orbital_sim` / `sandbox` |

每个已跟踪的 probe 在矩阵中**只出现一次**；`duplicates` 字段记录重复检查结论
（当前：无重复；传感器/物理/伤害等按 module / world-integration / V17-bridge 分层，属于
有意的覆盖分层，不是重复测试）。

### 用例类型（`entry`）

- `script`：`godot --headless --path game_v17 --script res://tests/<probe>.gd`
- `scene`：`godot --headless --path game_v17 res://v1_hud.tscn --quit-after 5000`
- `main`：`godot --headless --path game_v17 --quit-after 5000`（主场景 `res://main_menu.tscn`）

boot 用例通过 `env` 字段声明剖面（`DSH_BUILD=full|orbital_sim|sandbox|combat_sim`、
`DSH_FLOW_SMOKE=1`），并以 `expected_markers` 校验真实启动日志。

---

## 3. 判定规则（PASS / FAIL / TIMEOUT / NOT RUN）

| 状态 | 判定 |
| --- | --- |
| **PASS** | 进程 exit 0，且 probe 的 `FAIL` 计数为 0，且 `expected_markers` 全部出现；（boot/e2e 另需真实日志 marker 命中） |
| **FAIL** | exit != 0、probe FAIL>0、缺少结果行（parse error）、缺少 marker、boot 日志出现 `SCRIPT ERROR` / parse error |
| **TIMEOUT** | 超过 per-case 超时后进程被 kill；计入失败，整体非零退出 |
| **NOT RUN** | 矩阵声明 `blocked: true` 的前置条件未就绪；或 `res://` 脚本/场景在 worktree 中缺失。**绝不记为 PASS** |

`run_tests.ps1` 解析规则（矩阵 `result_parsers` 单一定义，特殊 probe 在用例上显式覆盖）：

- 常规 probe：取**最后一条** `PROBE RESULT: PASS=n FAIL=m`
- `plot_tws_probe`：`[SUMMARY] pass=n fail=m` + 成功 marker `V17 SENSOR-1 TWS PROBE PASS`
- `facility_model_probe`：`checks=n fails=m` + 成功 marker `FACILITY MODEL PROBE OK`
- boot smoke：exit 0 + 全部 `expected_markers`（无 PASS/FAIL 计数时 pass/fail 字段记为 marker 命中数）

### 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 所有实际运行用例 PASS（声明 blocked 的 NOT RUN 不导致失败）；`-Baseline` strict 模式下表示“无新增回归 **且 baseline 覆盖完整**” |
| `1` | 任一 FAIL / TIMEOUT，或出现“非预期 NOT RUN”（例如已启用用例的脚本缺失）；`-Baseline` 模式下表示存在新增失败 / 基线漂移 / 超时 / 非预期 NOT RUN / **baseline 项未选入或未执行（unselected/unverified）** |
| `2` | 环境/设置被阻塞：找不到 Godot、import 预检失败、矩阵/参数错误、过滤后无用例、baseline 文件缺失/非法 |

### Phase 0 专项门禁（`-Gate phase0`）

Issue #14 要求把「Phase 0 必需门禁」与「完整历史回归矩阵」严格区分。门禁定义在
`game_v17/tests/probe_matrix.json` 的 `gates.phase0`，当前为 **6 个 case**：

| gate case | 覆盖 |
| --- | --- |
| `profile.build_profile_probe` | 四剖面开关矩阵、选择/回退、simulator 校验负例、sandbox 守卫 |
| `e2e.orbital_sim` | 真实入口 `main_menu → v1_hud → ShellBinder → GameSession` + 真实战斗闭环 |
| `boot.full` | 剧情构建仍可启动（prelude ready） |
| `boot.legacy_combat_sim` | 旧 `combat_sim` 向后兼容 |
| `boot.orbital_sim` | 正式拟真剖面真实主场景启动 + SYSTEMS ready |
| `boot.sandbox` | 开发测试 sandbox 启动 |

命令：`pwsh ./run_tests.ps1 -Gate phase0`。门禁用例必须全 PASS（否则 exit 1），
C/CI 中它是必须为绿的检查；它**不包含**全量历史 probe，不能代表“全矩阵通过”。

### baseline-aware 模式（`-Baseline`，strict fail-closed）

`game_v17/tests/known_baseline_failures.json` 记录审计 HEAD `263e97e` 已存在、Phase 0 不负责修复的
8 个遗留失败（exact PASS/FAIL 计数来自独立基线证据与 PR head 复跑）。

`pwsh ./run_tests.ps1 -Baseline game_v17/tests/known_baseline_failures.json` 的语义（**default = strict**）：

- **74 个 case 全部执行**；已知遗留失败**状态仍是 FAIL**，逐条出现在控制台表、`report.md`、
  `summary.json`、CI job summary 与 artifact 中，绝不会被改名 PASS、跳过或 `continue-on-error`；
- 对每个 FAIL case 额外给出 `baseline` 分类：`known`（命中已知失败且 PASS/FAIL 计数完全一致）
  或 `new`（新增失败 / 计数漂移）；
- **fail-closed 覆盖要求**：每个声明的 baseline entry 必须 (i) 被选入本次运行、(ii) 实际执行
  （不能是 NOT RUN/blocked）、(iii) 结果为 FAIL 且 exit code、PASS/FAIL 计数与声明完全一致。
  任何一项不满足都计入 `baseline_unselected` / `baseline_unverified` / `baseline_drift`，
  **默认直接 exit 1**；控制台会打印
  `BASELINE CHECK: known_fail=N new_fail=N drift=N unverified=N unselected=N complete=true|false`。
- 汇总字段：`known_fail`、`new_fail`、`baseline_drift`、`baseline_unselected`、`baseline_unverified`、
  `baseline_complete`；summary 的 `baseline` 段还含 `complete`、`verified`、`unselected_ids[]`、
  `unverified[]`、`coverage`。CI 只有 `complete=true` 才可绿。
- 退出码：**只有** 所有 baseline entry 均 selected+executed+FAIL+计数匹配，且
  `new_fail==0 && baseline_drift==0 && baseline_unverified==0 && baseline_unselected==0 &&
  timeout==0 && unexpected NOT RUN==0` 时为 0。绿灯含义是「无新增回归 + baseline 覆盖完整」，
  **不是**「所有测试通过」。
- **本地筛选调试**：`-Only/-Category/-Gate` 会缩小选择集，使部分 baseline entry 未选入。
  此时 strict 检查会 exit 1（正确行为）。如确需只跑一部分做调试，加 `-AllowPartialBaseline`：
  允许未选入/未验证项不导致失败，但输出必须是
  `RESULT: BASELINE PARTIAL - NOT a complete baseline verification (unselected=N, unverified=M)`，
  summary `baseline.complete=false / verified=false`，**不得**出现 "BASELINE MATCH" 或完整通过措辞。
  CI 不使用该开关。
- **可重复回归**：`pwsh ./game_v17/tests/baseline_gate_selftest.ps1 -NoImport` 会验证
  (A) baseline 项被 blocked 成 NOT RUN → strict exit 1；(B) baseline 项被筛选掉 → strict exit 1；
  (C) 筛选 + `-AllowPartialBaseline` → exit 0 但明确标记 PARTIAL/未验证。
  该脚本在 CI 的 full-matrix job 中执行，失败即 job 红。

> 8 个遗留失败对应的后续责任任务（建议）见 `known_baseline_failures.json` 的 `follow_up` 字段与 §7A.2。

### 环境隔离

每次运行先快照并清除调用方进程里的全部 `DSH_*`、`V17_*` 环境变量（列表与数量写入
summary 的 `env_isolation`），每个用例在独立 Godot 进程中只注入矩阵 `env` 声明的变量；
运行结束（含异常路径）在 `finally` 中恢复调用方环境。因此：

- 本地 shell 里残留的 `DSH_BUILD` / `DSH_SHOT` / `V17_*` 不会污染结果；
- boot 用例的剖面只来自矩阵声明；
- `v17_bridge_probe` 等自身读写 `DSH_*` / `V17_*` 的 probe 在“干净环境”下按默认分支执行。

### import 预检

除非 `-NoImport`，运行前执行一次：

```
godot --headless --path game_v17 --import
```

- 新 clone / 新 worktree 必须先 import，否则场景与资源可能加载失败；
- 预检 exit != 0，或日志出现 `SCRIPT ERROR` / parse error / import error：本次所有用例
  标记 **NOT RUN/BLOCKED**、import 日志写入 run dir、**exit 2**；
- `--import` 会生成未跟踪的 `*.uid` 旁路文件、并可能让 `.import` 文件出现 stat-dirty
  （`git diff` 为空，属引擎生成的正常噪音）——不要提交这些噪音，也不要把它们当作源码脏改动。

### 超时与重试

- per-case 超时默认取矩阵 `timeout_s`；实测最慢的 probe（`fleet_transfer`/`transfer`/
  `v17_transit_bridge`）在并发负载下可达 70–77s，矩阵给了 300s；其余 probe 180s；
  boot 180–240s；e2e 300s。
- 只在日志匹配明显的文件锁/导入竞争模式（`file is locked`、`Access is denied`、
  `Failed to open file` 等）时**自动重试一次**，并在该 case 的 `attempts` 字段如实记录。
- 良性引擎错误（例如主菜单换场时的 `ERROR: Parent node is busy adding/removing children...`）
  不会单独导致 boot smoke 失败；以 exit code、marker、`SCRIPT ERROR`/parse error 为准。

---

## 4. 输出格式

每次运行创建 `.test-results/<run-id>/`（`run-id = yyyyMMdd-HHmmss-<短 commit>`）：

| 路径 | 内容 |
| --- | --- |
| `summary.json` | 机器可读摘要（schema `test_summary.v1`） |
| `report.md` | 人读报告（环境、totals、逐用例表、原因） |
| `import.log` | import 预检原始日志 |
| `logs/<case-id>.log` | 每个用例的 raw 合并输出（stdout+stderr） |
| `logs/<case-id>.stderr.log` | 有 stderr 时额外保存的 stderr 原始流 |

`summary.json` 顶层字段：`schema`、`run_id`、`started_at` / `ended_at`、`invocation`
（矩阵/过滤/CI/超时）、`godot`（路径、发现方式、`version_raw`、`version_expected`、
`version_match`）、`git`（branch / commit / worktree_dirty / modified_tracked）、`host`
（OS、PowerShell 版本）、`import`（status/exit_code/duration/error 数/日志）、
`env_isolation`、`environment_blocked`、`cases[]`、`totals`、`exit_code`；
另有扁平便捷字段 `godot_version` / `git_branch` / `git_commit` / `host_os`。

每个 case：`id`、`category`、`profile`、`entry`、`purpose`、`script`/`scene`、`env`、
`command`、`exit_code`、`status`、`duration_s`、`pass_count`、`fail_count`、
`expected_markers`、`marker_ok`、`log_path`、`reason`、`attempts`、`blocked`。

totals：`total` / `pass` / `fail` / `timeout` / `not_run`（含
`not_run_expected` 声明阻塞、`not_run_unexpected` 非预期缺失）/ `ran` / `duration_s`。

### 控制台表

```
CASE                                 CATEGORY     PROFILE    STATUS    EXIT     TIME PASS/FAIL LOG
profile.build_profile_probe          profile      -          PASS         0     0.5s    553/0 .test-results/<run>/logs/profile.build_profile_probe.log
```

### 如何解读

- 只有 **PASS** 行是“当前提交在 Godot 4.7.2 runtime 中实际通过”的证据；
- 报告中出现 FAIL 时，先看 `reason` 与该 case 的 `log_path`，再看是不是已知的
  **pre-existing 内容漂移**（见 §7A.2）；本任务不修改 probe、不掩盖失败；
- NOT RUN 必须带原因；`blocked: true` 是矩阵声明的前置条件未就绪，
  非预期缺失（脚本被删/改名）会让整体 exit 1。

---

## 5. 新增 probe / boot 用例

1. 新 probe 放在 `game_v17/tests/*_probe.gd`，沿用现有 `extends SceneTree` 约定：
   末尾打印 `... PROBE RESULT: PASS=<n> FAIL=<m>`，`quit(0/1)`；
2. 在 `probe_matrix.json` 的 `cases` 中加一条（顺序即执行顺序，按 category 排序）：

```json
{
  "id": "unit.my_new_probe",
  "category": "unit",
  "profile": "",
  "entry": "script",
  "purpose": "one-line purpose",
  "script": "res://tests/my_new_probe.gd",
  "expected_markers": ["MY NEW PROBE RESULT:"],
  "result": "probe",
  "timeout_s": 180
}
```

3. 特殊结果格式：在 `result` 选 `summary` / `checks`，或把 `result_parsers` 中对应正则补进
   矩阵顶层；不要改一段式 `PROBE RESULT` 约定之外的输出。
4. boot smoke：`entry` 用 `main`/`scene`，`env` 声明 `DSH_BUILD`/`DSH_FLOW_SMOKE`，
   `expected_markers` 用真实日志中出现过的稳定前缀（不要用会随数据变化的整行）；
   启动命令用 `extra_args: ["--quit-after", "5000"]` 限制运行帧数。
5. 暂未就绪的用例：`blocked: true` + `blocked_reason`（会显示 NOT RUN，不算失败）；
   就绪后删除这两个字段即可启用。
6. 新增后先跑 `pwsh ./run_tests.ps1 -List` 与 `-Only '<新 case id 正则>'`，
   再跑受影响的 `-Category`，最后跑全矩阵。

---

## 6. CI

`.github/workflows/tests.yml`（Issue #14 重写后）包含**两个语义明确区分的 check**，两者都会上传
真实测试产物 artifact：

| check（job） | 命令 | 语义 | PR 上的意义 |
| --- | --- | --- | --- |
| **Phase 0 gate (Phase 0 acceptance)** | `run_tests.ps1 -Ci -Gate phase0` | 6 个 Phase 0 必需用例必须全 PASS | Phase 0 验收门禁；不包含全量历史 probe。job 名称**不代表 branch protection 已生效**（见下） |
| **Full matrix (baseline-aware)** | `run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json` | 74 cases 全跑；8 个已知遗留失败仍以 FAIL 显示；**strict fail-closed**：新增失败/漂移/超时/非预期 NOT RUN/**baseline 项未执行或被筛选掉/计数不符**都会红灯 | 绿灯仅表示「**无新增回归 + baseline 覆盖完整**」，**不是**「全矩阵通过」 |

公共设置：

- runner：`windows-latest`（与本地 Windows + `win64_console` 二进制一致，结果可直接对照本地基线）；
- 工具链：固定下载 `Godot_v4.7.2-stable_win64.exe.zip` → SHA-256 校验
  （`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`）→ 解压到
  `tools/godot/` → `actions/cache` 按版本+SHA 缓存；启动前验证 `--version` 含 `4.7.2`；
- 产物：两个 job 都用 `actions/upload-artifact@v4` 上传 `.test-results/`
  （`include-hidden-files: true` —— `.test-results` 是点目录，默认会被 upload-artifact 忽略，
  这是 Issue #14 中「No files were found」的根因），artifact 内含该次运行的 `summary.json`、
  `report.md` 与逐例日志；不上传游戏内容、用户数据或密钥；
- **产物 fail-closed**：每个 job 在上传前有 `Assert test artifacts exist before upload` 步骤
  （断言最新 `<run-id>/` 下 `summary.json`、`report.md`、`logs/` 非空，且 `summary.run_id == run-dir`、
  `cases>0`），上传配置为 `if-no-files-found: error`；**缺失证据会使 job 失败**，不会静默无 artifact；
- **baseline 回归**：full-matrix job 在矩阵之后执行 `baseline_gate_selftest.ps1`
  （验证 blocked/NOT RUN 与 filtered-out baseline 项都会让 strict 检查失败），失败即 job 红；
- job summary：两个 job 都向 GitHub Step Summary 写本次 totals / 逐例表格；
  full-matrix 明确列出 **known-baseline failures（可见）**、**NEW failures**、
  `unverified`、`unselected`、`baseline complete`；
- 禁止 `continue-on-error`：已知遗留失败不阻塞，是因为它们被显式建模为 baseline 已知项并在
  所有输出中保持 FAIL 可见，而不是把失败伪装成成功；
- **branch protection 无法确认**：本仓库为 private 且未启用 GitHub Pro，branch protection /
  required status checks API 返回 HTTP 403。因此 CI 只能证明「job 实际运行并通过」，
  **不能**把 job 名称里的措辞（旧版曾写 "required"）当作保护规则已生效的证据；job 名称已改为
  `Phase 0 gate (Phase 0 acceptance)` 以避免歧义。

artifact 获取（需 `gh` 登录）：

```powershell
gh run list --branch phase0/issue-14-ci-closeout            # 找到 run id
gh run download <run-id> -n phase0-gate-results-<run>-<attempt> -D .\_ci_artifacts
gh run download <run-id> -n full-matrix-results-<run>-<attempt> -D .\_ci_artifacts
```

### 6.1 真实运行记录（Issue #14 修复后）

- **run [39786721057](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39786721057)**
  （`pull_request`，head `04b0d51`）：conclusion=**success**，两个 job 都 pass。
  - `Phase 0 gate (required)` → success，1m20s：6/6 PASS，`PHASE0_GATE_EXIT=0`；
  - `Full matrix (baseline-aware)` → success，4m44s：72 cases = **64 PASS / 8 KNOWN-BASELINE FAIL / 0 new / 0 drift / 0 timeout / 0 not-run**，`BASELINE CHECK: known_fail=8 new_fail=0 drift=0`，`FULL_MATRIX_EXIT=0`。
- **artifact 实际上传并下载校验**（修复前 run 39778490176 为 0 个 artifact）：
  - `phase0-gate-results-39786721057-1`：id 12428559095，26,039 B，sha256 `9fdd86da…`，12 files；
  - `full-matrix-results-39786721057-1`：id 12429463292，372,318 B，sha256 `677c164b…`，118 files；
  - `gh run download 39786721057` exit 0；解压后含 `summary.json` / `report.md` / `import.log` /
    逐例 `logs/`（gate 9 个日志、full 115 个日志）；full 的 `summary.json` 中 8 条遗留失败仍为
    `status=FAIL` 且 `baseline.known=true`，`report.md` 含 `## Baseline` 与逐条 `KNOWN-BASELINE`。
- 重要语义：full-matrix 绿灯 = **无新增回归**，不是「全矩阵通过」；默认 `run_tests.ps1`（无 `-Baseline`）
  仍会因这 8 个遗留失败 exit 1。

### 6.2 真实运行记录（PR #15 review 修正：fail-closed baseline）

- **run [39795265144](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144)**
  （`pull_request`，被验证代码提交 `e73bc69`）：conclusion=**success**，两个 job 均 success。
  - `Phase 0 gate (Phase 0 acceptance)`（重命名后）→ success：6/6 PASS，`PHASE0_GATE_EXIT=0`；
  - `Full matrix (baseline-aware)` → success：72 cases = **64 PASS / 8 KNOWN-BASELINE FAIL / 0 new /
    0 drift / 0 timeout / 0 not-run**，`BASELINE CHECK: known_fail=8 new_fail=0 drift=0 unverified=0
    unselected=0 complete=true`，`FULL_MATRIX_EXIT=0`；
  - **CI 内 fail-closed selftest step**：`BASELINE GATE SELFTEST RESULT: PASS=24 FAIL=0 (assertions=24)`；
    其中 Scenario A 输出 `unverified=1 complete=false` → `BASELINE CHECK FAILED`；
    Scenario B 输出 `unselected=7 complete=false` → `BASELINE CHECK FAILED`；
    Scenario C 输出 `RESULT: BASELINE PARTIAL - NOT a complete baseline verification`；
  - **artifact 断言**：`ARTIFACT ASSERT OK run_dir=20261022-142403-c3da2bbe cases=72 logs=115`
    与 `cases=6 logs=9`；上传仍 `include-hidden-files: true`，`if-no-files-found: error`；
    artifact `phase0-gate-results-39795265144-1`（id 12431684980，26,103 B，sha256 `e2dbe7b7…`）与
    `full-matrix-results-39795265144-1`（id 12432368909，372,766 B，sha256 `47872c81…`）均已下载核对。
- 合并后（历史对照）：run 39786721057 = 代码提交验证；run 39787908114 = 最终 docs-only head
  `e150c94…` 复核；二者结果一致（详见 `docs/54` §12/§13）。

Linux CI 备选（当前未启用）：runner 改为 `ubuntu-latest`，用 `-GodotBin` 指向 Linux 版
Godot 4.7.2 即可；`run_tests.ps1` 不依赖 Windows 专有 API（进程/环境变量/stdout 重定向均
跨平台），但会改变被测 OS/二进制，因此当前选择 Windows 以保持与本机基线一致。

---

## 7. 当前真实矩阵状态（本 session 实际执行）

### 7.0 当前 PR #19（A0-T1）实际结果 —— 74 cases

> 本节是**当前分支 `phase-a1/worldstate-physics-sync`（PR #19，base=PR #17）**的
> **代码验证 head `6f60de7`（运行时代码最后变更）/ 最终 docs head `f0153ea`** 上的真实执行结果。**§7A.1–§7A.3 是 Phase 0 时期的历史记录
> （72 cases），不是本次运行结果**，两者不可混用。

- 矩阵规模（当前仓库）：**74 cases = 69 个常规 probe + 1 个 e2e probe + 4 个 boot smoke**
  （仓库当前共 **70 个 tracked `game_v17/tests/*_probe.gd`**：69 常规 + 1 e2e；A0-T1 新增
  `a0_world_physics_sync_probe.gd`，A1.1 已新增 `a1_entity_metadata_authority_probe.gd`）
- 命令：`pwsh ./run_tests.ps1 -Baseline game_v17/tests/known_baseline_failures.json -Ci`
- **totals：total=74，PASS=66，FAIL=8，TIMEOUT=0，NOT RUN=0**；
  `BASELINE CHECK: known_fail=8 new_fail=0 drift=0 unverified=0 unselected=0 complete=true`，exit 0
- 8 个已知遗留失败仍是 **FAIL**（逐条见 §7A.2 表格，计数不变）；**不是“全矩阵通过”**
- Phase 0 gate：`pwsh ./run_tests.ps1 -Gate phase0 -Ci` → **6/6 PASS**，exit 0
- A0-T1 新探针：`integration.a0_world_physics_sync` → **PASS 97/0**
- **CI（代码验证 head `6f60de7`）**：run
  [39990675827](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39990675827)
  （head `6f60de7744ffcf551a96c78e74008cda5f6ad3cc`）两个 job 均 success；
  - `Phase 0 gate` → 6/6 PASS（[job/120541309623](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39990675827/job/120541309623)）
  - `Full matrix (baseline-aware)` → **74 = 66 PASS / 8 KNOWN-BASELINE FAIL / 0 TIMEOUT / 0 NOT RUN**，
    `known_fail=8 new_fail=0 drift=0 complete=true`，exit 0（[job/120541309265](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39990675827/job/120541309265)）
  - artifacts 已 `gh run download` 核对：`full-matrix-results-39990675827-1` 388,482 B /
    sha256 `1f9ea7bb466d723f25bcfa8cd22af9396f6fac2e2bfc95964696570dfdf136ab`（summary
    total=74/pass=66/fail=8/timeout=0/not_run=0、baseline complete=true）；
    `phase0-gate-results-39990675827-1` 26,110 B /
    sha256 `81e8119ba61d8e6404a8fe93962fd770f01003146e4a801e6222e5f54b101cde`（summary
    total=6/pass=6/gate=phase0）；A0-T1 日志 `PASS=97 FAIL=0`
- **CI（最终 docs-only head `f0153ea`，当前 head）**：run
  [39996883639](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39996883639)
  （head `f0153eac0e05863ed1d6ba998d33c5bff7da7ebd`）两个 job 均 success；
  - `Phase 0 gate` → 6/6 PASS（[job/120562619857](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39996883639/job/120562619857)）
  - `Full matrix (baseline-aware)` → **74 = 66 PASS / 8 KNOWN-BASELINE FAIL / 0 TIMEOUT / 0 NOT RUN**，
    `known_fail=8 new_fail=0 drift=0 complete=true`，exit 0（[job/120562619537](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39996883639/job/120562619537)）
  - artifacts 已 `gh run download` 核对：`full-matrix-results-39996883639-1` 388,464 B /
    sha256 `0037b351a2b780b6849c66d32f0ca989a14c816b5252825f1cbdecd0e44691ae`；
    `phase0-gate-results-39996883639-1` 26,113 B /
    sha256 `becd586d23f4c749eea1b31fc5caa6fcf7fe411d42af5afa51642708b0c7b89a`；A0-T1 日志 `PASS=97 FAIL=0`
- **修正前历史运行（保留，勿当作当前结果）**：run
  [39973495277](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39973495277)
  （head `1fcda468`，`updated`/`mismatched` 语义修正**之前**）→ 74 = 66 PASS / 8 FAIL / 0 TIMEOUT /
  0 NOT RUN，A0-T1 探针 **78/0**。该轮已被本轮的 97/0 取代，仅作审查修正前证据保留。
- 注：`f0153ea` 为 **docs-only** 提交（仅本文档），运行时代码最后变更为 `6f60de7`；
  两轮 CI 的测试数字一致（74=66/8/0/0，A0-T1 97/0）。

| 分类 | total | pass | fail |
| --- | --- | --- | --- |
| `profile` | 1 | 1 | 0 |
| `content` | 8 | 6 | 2 |
| `unit` | 37 | 35 | 2 |
| `integration` | 23 | 19 | 4 |
| `e2e` | 1 | 1 | 0 |
| `boot` | 4 | 4 | 0 |

---

## 7A. 历史记录（Phase 0 时期，72 cases，HEAD `73fc4a6c`）

> ⚠️ **以下 §7A.1–§7A.3 是 Phase 0 交付时的历史运行记录**：当时矩阵为 **72 cases**、
> tracked probe 为 **68 个**（67 常规 + 1 e2e）。这些数字**不代表当前 PR #19 的运行结果**，
> 仅用于保留 Phase 0 验收证据。当前结果见 §7.0。

Phase 0 历史基准：worktree `D:\gt_phase0`（branch `feat/phase0-simulator-first`），
HEAD `73fc4a6c`（T1 profile 与 T3 e2e probe 已提交；T2 runner/matrix/docs 为待提交的 worktree 改动）。

- 运行：`pwsh ./run_tests.ps1 -Ci`
- run id：`.test-results/20261022-200954-73fc4a6c/`
- Godot：`4.7.2.stable.official.ed1daf0bf`（`tools/godot/Godot_v4.7.2-stable_win64_console.exe`，MATCH）
- import 预检：PASS，exit 0，6.8s，0 条 error
- 环境隔离：清除 6 个继承的 `DSH_*` 变量（`DSH_HOME`、`DSH_PROFILE`、`DSH_PROFILE_DIR`、
  `DSH_SESSION_ID`、`DSH_SHELL`、`DSH_WEB_URL`）
- 矩阵规模（历史）：72 cases = 67 个常规 probe + 1 个 e2e probe + 4 个 boot smoke
  （当时仓库共 68 个 tracked `game_v17/tests/*_probe.gd`：67 常规 + 1 e2e）
- **历史 totals：total=72，PASS=64，FAIL=8，TIMEOUT=0，NOT RUN=0，duration=269.0s，进程 exit code=1**
  （exit 1 是 8 个 pre-existing probe FAIL 的如实结果，不是环境阻塞）

| 分类（历史） | total | pass | fail |
| --- | --- | --- | --- |
| `profile` | 1 | 1 | 0 |
| `content` | 8 | 6 | 2 |
| `unit` | 37 | 35 | 2 |
| `integration` | 21 | 17 | 4 |
| `e2e` | 1 | 1 | 0 |
| `boot` | 4 | 4 | 0 |

### 7A.1 Phase 0 交付用例（全部 PASS）

| case | 结果 | 证据 |
| --- | --- | --- |
| `profile.build_profile_probe` | **PASS 553/0**，exit 0，0.5s | 覆盖 full / orbital_sim / sandbox / combat_sim、选择优先级、回退、sandbox 守卫 |
| `e2e.orbital_sim` | **PASS 153/0**，exit 0，3.4s | 真实入口 `main_menu → v1_hud → ShellBinder → GameSession`；probe 自身强制 `DSH_BUILD=orbital_sim` |
| `boot.full` | **PASS**，exit 0，3.1s，markers 3/3 | `[SHELL BINDER] BUILD profile=full`、`prelude ready=true`、`FLOW SMOKE COMPLETE` |
| `boot.legacy_combat_sim` | **PASS**，exit 0，3.2s，markers 3/3 | `[MAIN MENU] BUILD=combat_sim`、`[SHELL BINDER] BUILD profile=combat_sim`、`FLOW SMOKE COMPLETE` |
| `boot.orbital_sim` | **PASS**，exit 0，3.2s，markers 3/3 | 主场景自动跳转 + `[SHELL BINDER] BUILD profile=orbital_sim` + `FLOW SMOKE COMPLETE` |
| `boot.sandbox` | **PASS**，exit 0，3.2s，markers 3/3 | 主场景自动跳转 + `[SHELL BINDER] BUILD profile=sandbox` + `FLOW SMOKE COMPLETE` |

### 7A.2 已知 pre-existing FAIL（8 个，全部 exit 1，与本轮 Phase 0 改动无关）

这些失败在 audit HEAD 的独立基线（verifier 复跑）中同样存在，属于内容/数据漂移
（ship catalog 已扩到 36 型、story 文本已演进、旧模块契约未同步），**本任务不修改 probe、
不掩盖失败**；Phase 0 不负责修复，需另开内容/契约同步任务。

| case | PASS/FAIL | 备注 |
| --- | --- | --- |
| `content.damage_profile_probe` | 554/4 | probe 断言 32 个 damage profile，当前 ShipCatalog 已 36 型（另含 4 条 pre-existing SCRIPT ERROR：`damage_profile_service.gd:208`） |
| `content.story_text_probe` | 469/13 | 12 条文本与 `docs/44` 原文不再逐字一致（内容已演进） |
| `unit.incident_record_probe` | 2761/1 | 事故记录生成器单条断言漂移 |
| `unit.save_probe` | 153/3 | 存档契约 3 条断言漂移 |
| `integration.damage_integration_probe` | 198/6 | damage 接入 V17 world 的 6 条断言漂移 |
| `integration.plot_tws_probe` | 58/1 | TWS bridge 1 条断言（`[SUMMARY] pass=58 fail=1`，特殊解析器已正确处理） |
| `integration.v17_nav_integration_probe` | 181/1 | nav 集成 1 条断言 |
| `integration.v17_sensor_authority_display_probe` | 71/3 | 传感器权威显示 3 条断言 |

> 说明：上述 8 个失败与 verifier 独立基线的 8 个 pre-existing 失败**逐项一致**
> （`damage_integration` 198/6、`damage_profile` 554/4、`incident_record` 2761/1、
> `plot_tws` 58/1、`save` 153/3、`story_text` 469/13、`v17_nav_integration` 181/1、
> `v17_sensor_authority_display` 71/3）。因此“全矩阵全绿”目前仍被这 8 个历史内容漂移阻塞；
> CI 的 `Full matrix (baseline-aware)` 会在**新增回归**时如实红灯，日常绿灯仅表示
> 「与审计 HEAD 基线相比无新增失败/无漂移」，且 8 条失败始终保持可见（见 §6.1）。

### 7A.3 历史参考（同一 session 的其它真实运行，仅用于说明差异）

- `.test-results/20261022-195827-122c0d14/`：e2e 用例仍为 `blocked`、慢 probe 超时仍为 120s
  时的第一次全矩阵运行 → **total=72，PASS=63，FAIL=8，TIMEOUT=0，NOT RUN=1（expected，e2e 未启用）**，
  duration=306.2s。
- `.test-results/20261022-200412-a92867d9/`：解除 e2e 阻塞、调整慢 probe 超时后、HEAD `a92867d9`
  上的运行 → **total=72，PASS=64，FAIL=8，TIMEOUT=0，NOT RUN=0**，duration=270.7s。
- 最终运行见 §7A 主体（HEAD `73fc4a6c`，269.0s），两次全量运行结果逐 case 一致。

---

## 8. 已知限制

- **CI 已真实执行并验证 artifact**（run [39795265144](https://github.com/HATO-24/ghost-track-apsis/actions/runs/39795265144)，见 §6.2；
  更早 run 39786721057 / 39787908114 见 §6.1）；
  - full-matrix 绿灯语义是「**无新增回归 + baseline 覆盖完整**」而非「全矩阵通过」；8 个遗留失败仍需
    独立内容/契约同步任务修复（修复前会一直被标记为 KNOWN-BASELINE 并保持 FAIL 可见）；
  - **strict fail-closed**：baseline 项被 NOT RUN/blocked/未选入/计数不符时检查失败（selftest 可重复验证）；
    `-AllowPartialBaseline` 只用于本地筛选调试，永远声明 `BASELINE PARTIAL` 且 `complete=false`，CI 不使用；
  - **artifact fail-closed**：上传前断言 summary/report/logs 存在且 run_id 匹配，上传 `if-no-files-found: error`；
  - **branch protection 无法确认**（private repo / 未启用 GitHub Pro，API 403）：job 名称不代表保护规则已生效；
- 基线证据来自审计 HEAD `263e97e` 的独立基线 + docs/54 §2.1 + PR head 复跑，三者逐项一致；
  **不是在 CI 环境从审计 HEAD 独立复现**（`known_baseline_failures.json` 的 `evidence_provenance` 已写明）；
- `plot_tws_probe` / `facility_model_probe` 不使用统一 `PROBE RESULT` 行，需矩阵显式
  指定解析器；这是对现存 probe 的兼容，不修改 probe 本身；
- 并发运行多个 Godot（多队友/多 job 共享同一 worktree）会让部分计算密集 probe 变慢
  （实测 `fleet_transfer` 72.9s、`transfer` 76.8s、`v17_transit_bridge` 56.7s），因此
  超时留有 4× 余量；runner 只做保守的文件锁重试，不掩盖确定性失败；
- `--import` 产生的 `*.uid` / `.import` stat-dirty 是 Godot 4.7.2 的正常引擎噪音，
  不纳入提交、不视为源码脏改动；
- `run_tests.sh` 是薄封装；如在 Linux 上直接 `./run_tests.sh` 执行，需要该文件带可执行位
  （git 提交时由维护者 `git update-index --chmod=+x run_tests.sh`，或直接 `sh run_tests.sh`）。
