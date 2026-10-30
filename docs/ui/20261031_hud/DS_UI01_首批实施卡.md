# DS_UI01｜首批主屏真实字段与无效果可读基线

**状态：可供根独立复核的 DS 单卡草案；尚未派发、未改运行代码，测试/实机 NOT RUN。** 不把 UI-01 改名为 UI-03，也不含 B001、UI-02 字体系统、四区重构或 Phase B 业务页。按 DS 当前单卡串行队列安排。

## 1. 执行身份、归属和开工门

- 本卡静态定位源 `origin/main@018bd4d0adc882a9123210f022fe8b7c71f68c06`，源行号见同目录 CSV。H01/PR77 已合并；已知含 H01 的 main 为 `042a5e5e03f38f7b7e4367ffb0b6f38834773503`。**实施者开工时先核当时 `origin/main` 的最终完整 40 位 SHA、目标工作树 `HEAD`、`git status --short` 和相关改动 PR/owner**；如与本映射有差异，返 Sol 重核行条件，不盲贴旧行号。
- 允许生产文件只有 `game_v17/scripts/ui/v1_hud.gd` 的 `_load_data` 计时注入调用、`_draw` 顶栏、`_draw_map` 和 `_draw_right` 固定旁白、`_draw_roe_overlay` API 副标题中**下述被点名的局部显示路径**。如确需独立最小文案映射文件，先报路径与 owner 给 Sol，再纳入同一张卡；本首批不改 `shell_binder.gd`、`GameSession`、通信/ROE/火控服务、存档 schema、场景布局、字体度量、权限或自动射击逻辑。
- 主仓 `D:\GHOST TRACK_APSIS` 的旧 HEAD 和脏 `v1_hud.gd`、`model_preview.gd`、删除中的 `near_view.gd` 均属未知 owner，不借用、不覆盖、不清理。本次设计批次不建新工作树/新聊天；后续实施由根在 #63 已交付且独立放行后，按 DS 现有项目队列确认唯一 HUD 持有人和常规隔离执行分支。若文件仍被其他任务持有，**本卡停在字段映射与设计**，不要抢锁；常规隔离分支不另设用户批准门。
- UI-01 的 A1 前置已满足；UI-02 仍 WAIT UI-01，UI-03（含 B001）仍 WAIT UI-02/A1 和所触业务 view；UI-04 等 B1/B2。完成本卡不宣布 UI-01 整卡、UI-02 或 HUD 总体 PASS。B001 白名单 9 ID/10 行属于 UI-03，已接收但未派发，本卡不得顺手做。

## 2. 唯一可实现切片与提交顺序

1. **锁源与截图**：记录当前正式 `orbital_sim` 入口（`build_profiles.json` 指向 `res://v1_hud.tscn`）前图，分别列 `build_profile.id/label`、`session` 是否存在、`session.now_s()`、`_transfer_ok/_delta_v`、`combat_service.vm().roe` 的真实读取结果及其来源。`binder.ready` 仅为 boot 错误检查，不等于全视图实时；不从装饰计时或字符串推断任何服务状态。
2. **先处理确定伪值**：从顶栏去掉固定 `L1 港内 06:42:17`、`LINK OK · 無線電 8s`、`×1`，取消 HUD 对 `binder.seed_timers()` 的调用，把初始 `_timers` 固定数组置空，并隐藏仅来自该注入的 `BURN WINDOW/ARRIVAL/LINK` 三组倒计时；从中央时间条去掉固定 `T+00:00/TOF 144h/WINDOW OPEN/CLOSE`。不可改 `ShellBinder.seed_timers()` 或业务事件历史；若发现其他真实发布者依赖该事件，停下计时行并交根拆依赖，不直接删除真实事件。
3. **再做有限文案**：顶栏保留真实 profile 标题和 `session.now_s()` 的 T+；有可信 `delta_v_ready` 才保留带单位的数值，否则显示不可用或不显示。中央 `SESSION LIVE · CIC VIEW · V1 WIREFRAME · 不写 WORLD`、右栏 `SENSOR CONTROLS / 只读最小交互` 和 `LIVE SESSION · 最小交互 · 自绘 V1` 改为玩家有用的标题或删除。无 session 时标数据不可用；**仅有授权视图空接触时不得写“预览”**，因为 HUD 会自行合成 `demo=true` 占位接触。只有明确 mock/fallback 来源字段才能标“演示预览”；若没有该字段，停下该标签行，不能靠 `demo`/`binder.ready` 猜。正常模式不出现 API 名、`不写 WORLD` 等开发旁白，原始 code 和调试日志仍在诊断路径。
4. **ROE 只改能证实的行**：保留 `_combat.roe` 的真实当前档位，去掉 `session.set_roe(...)` API 副标题。保留“交战规则与开火授权分别管理”的含义，不把 ROE 当 FIRE 许可；当前 `_roe_locked` 默认 `story_vm.phase=prelude`，正式无 story 的 `orbital_sim` 会误判锁态，且 `DSH_V1_ROE_UNLOCK` 可覆写。**锁定/可编辑原因、四档自动/手动授权细则、`_roe_action` 失败说明停行**，先交下面最小解锁卡。不得用“ROE 未就绪”掩盖锁态缺合同。
5. 显示 diff 与实机/回归证据分别提交；每一行标已实施、停行或未触发。测试不能为迎合文字修改业务结果；不把低质量或未知观测自动变为禁射。状态词分明：sent、delivered、accepted、executing、completed、rejected、failed；unknown、尚未收到、stale、unavailable、preview 各有不同触发来源。本切片不修改这些命令阶段的运行映射。

**最小解锁卡（本卡外）**：ROE 服务/授权 owner 提供只读 `current_roe`、`can_edit_roe`、`edit_block_reason`（含不可用/未收到的显式状态），并证明 `orbital_sim` 的真实规则和 `set_roe` 拒绝原因一致；火控的 TRACK/SOLUTION/FIRE 授权仍独立提供。Sol 再按真实字段复核锁定和失败文案，DS 用单独小卡接 HUD。实时链路、延迟、倍率与任务窗口也须由各自已授权业务 view 提供来源/时效/缺失状态，再开卡；无字段时本首卡只移除假值。不得为了短文案改服务阈值或规则。

## 3. 局部正负验收

| 场景 | 应见 | 禁止 |
| --- | --- | --- |
| 正式 orbital_sim 正常启动 | 正确 profile、会话真实 T+、有效 Δv/ROE 仅按源字段展示，复古深色/线框/轨道图可读 | 固定链路 OK、8s、虚构窗口/倍率、`SESSION LIVE` 由 `ready` 冒认 |
| 无 session / boot 不完整 / 已证实显式 fallback | 前两者如实不可用；只有可信 fallback 来源才标演示预览；原诊断可追溯 | 空接触合成 `demo=true` 就说预览，空值说成 0、用隐藏实体名或内部 ID 占位 |
| Δv 缺失、任务窗口缺字段、链路未收到或过期 | 受影响区域不可用/未知或不显示；独立状态不互相代替 | 0.0 m/s、畅通、倒计时/预计延迟的伪值 |
| ROE 真正可用、锁定、无服务、设置拒绝 | 本卡只核当前真实档位与帮助语义；停行报告中列实际阻断，待解锁卡接入 | `prelude` 默认值冒充真实锁定原因，ROE 档位冒充 FIRE 授权，低质量自动禁射 |
| 选择/长舰名/后台刷新 | 旧选择、合法动作、事件与资源不因删旁白变化；需要的模式/失效标记仍在 | 焦点被重绘抢走、文字无提示裁断、开发字段泄漏玩家界面 |

## 4. 本地执行命令与证据包（由 DS 在执行 SHA 上运行）

先用 UI-01 原卡的通用过滤式 `-List` 确认选中 case 非 0、名称与当前执行 SHA 的 matrix 一致，再跑局部显示/权限探针。受影响正式入口按原 UI-01 §6 跑**原 C 完整 baseline-aware 回归**。本批编卡者没有执行这些命令；后续 DS 验收不减项。不触发云端 CI：

```powershell
git rev-parse HEAD
git status --short
pwsh -NoProfile -File ./run_tests.ps1 -Only '(build_profile_probe|cic_view_probe|a1_entity_metadata_authority|jc_authority_intel)' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(build_profile_probe|cic_view_probe|a1_entity_metadata_authority|jc_authority_intel)' -Ci -ResultsDir .test-results/ui/UI-01/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline ./game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/ui/UI-01/original-c
```

正式入口非 headless 实机：在 DS 目标工作树设置 `DSH_BUILD=orbital_sim`，用已配置的 Godot 4 控制台可执行文件启动 `game_v17/v1_hud.tscn`；例如 `$env:DSH_BUILD='orbital_sim'; & $env:GODOT_BIN --path ./game_v17 res://v1_hud.tscn`（先核 `$env:GODOT_BIN` 非空且指向正确版本）。记录启动命令/Godot 版本、执行 SHA、源字段快照和可见结果。在 **1920×1080、1600×900、100% 与经 UI-02 核定的放大比例（建议先测 125%，尚非批准最终值）** 分别留正常、不可用、ROE 受阻的前后截图；有可信显式预览入口时再留预览图，否则记该条件 NOT RUN/缺来源。另检中文/英文混排、长舰名、换行/裁切、键盘 Tab/回退焦点、鼠标命中区、关扫描/辉光后的基础对比；本卡不因截图好看就把 UI-02 字体/焦点验收记为 PASS。没有实机则逐项写 **NOT RUN**，不能用 headless 或旧 mockup 代替。

证据包列：`HEAD` 40 位、目标文件 owner 与 diff、每行旧→新/停行理由、实际可见 view 字段及其权限、专项与原 C 的选中 case/断言/退出码/结果目录、截图分辨率和 UI 比例、人工操作记录、已知基线对照。原 C 必须报告 4 项历史 FAIL 实际执行和精确匹配、新增失败/漂移/未执行数及 `complete`，不能只凭进程退出 0 写全绿；不触发云端 CI，也不擅自刷新基线。

### 历史 baseline 的精确口径

`018bd4d` 静态源的旧 `game_v17/tests/known_baseline_failures.json` 列 7 项，属于旧提交记录。H01 合并后的当前 main（根已核 `042a5e5e03f38f7b7e4367ffb0b6f38834773503`）保留 **4 个真实历史 FAIL**：`content.story_text_probe` 469 PASS/13 FAIL、`unit.incident_record_probe` 2761/1、`integration.plot_tws_probe` 58/1、`integration.v17_sensor_authority_display_probe` 71/3。当前 main 原始 Git blob bytes 的 baseline SHA256 据根核为 `c55e298cf8e953fe7819b3e098d852a9b5aca881317648ac2c9d27b856037b0e`；工作文件因换行可能不同。DS 在实际执行 SHA 重新读文件并计算**实际文件** SHA256，记录与 Git blob hash 的区别；如果身份/4 项计数有变，停下回 Sol/根核定。专项不选中这 4 项，不能宣称 baseline-aware 完整验证；原 C 全矩阵必须实际执行全部声明历史项并精确匹配后才能报告 `complete=true`。

## 5. 交付判定

交付局部 diff、局部专项与原 C 完整回归、正式入口实机证据、停行依赖清单和完整执行 SHA。根 6.1Sol 本轮暂代 Astra 审文字/清晰度与复古工业战术终端气质，并审代码和证据；项目负责人最终产品验收。文档完成、代码可编译、探针 PASS、独立审查、实机阅读和最终合并各自单独记账。
