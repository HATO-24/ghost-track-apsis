# Phase A 合并审查、预算与下一批任务卡

日期：2026-10-25（Asia/Shanghai）；规划/审查：Sol；实现执行：DeepSeek v4.1 Flash。

## 1. 本轮决定

1. **七项历史失败全部进入下一批台账**，按共同原因分为四张修复卡，不按七个文件名机械拆分。它们是 7 个失败 case、29 个失败断言，另有 damage profile 的 4 条 SCRIPT ERROR；不得当成可忽略噪音。
2. **1000 tick 优化卡采用明确的工程预算**：UTF-8 存档≤1,500,000 B，保存≤250 ms，内存恢复≤5,000 ms；在下述参考负载/机器上三次正式测量每次都达标。文件读取≤50 ms 单列核对。数字是下一卡需求，当前尚未达到；不能通过调整期望消除超预算。
3. **#32–#39 本轮均暂缓合并**。现有矩阵通过了严格历史失败核对，但额外运行已复现真值泄漏、事件去重和恢复契约缺口。先修 R01–R05，再按顺序整合。当前 main 仍为 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`。
4. Linux/macOS、非 headless 渲染、>1000 tick 成本分别立验证卡。真实 RF/光学物理先做模型规格与校准研究，保留当前抽象边界；不把这些尚未承诺的扩展硬塞进本批修复。

本次未修改游戏实现。隔离工作区在最终候选上运行回归和诊断，原工作区的模型/HUD/近景改动保留。

GitHub任务卡已发布，R01–R05先返修，其余按各卡依赖解锁：

- [R01 · #40 玩家 VM 所有分支遵守相同可见性](https://github.com/HATO-24/ghost-track-apsis/issues/40)
- [R02 · #41 事件自动 ID 唯一与新档完整性](https://github.com/HATO-24/ghost-track-apsis/issues/41)
- [R03 · #42 传感器严格恢复及同输入续跑一致](https://github.com/HATO-24/ghost-track-apsis/issues/42)
- [R04 · #43 通信 outcome 的版本与完整性校验](https://github.com/HATO-24/ghost-track-apsis/issues/43)
- [R05 · #44 成本报告使用真实字节，逐样本校验恢复](https://github.com/HATO-24/ghost-track-apsis/issues/44)
- [H01 · #45 舰级/毁伤档案与缺档案语义（覆盖3 cases）](https://github.com/HATO-24/ghost-track-apsis/issues/45)
- [H02 · #46 legacy TWS/显示的本舰 ID 归属（覆盖2 cases）](https://github.com/HATO-24/ghost-track-apsis/issues/46)
- [H03 · #47 设施事故生成的输入集合（覆盖1 case）](https://github.com/HATO-24/ghost-track-apsis/issues/47)
- [H04 · #48 现有序章文本与批准来源对齐（覆盖1 case）](https://github.com/HATO-24/ghost-track-apsis/issues/48)
- [S01 · #49 按预算优化1000 tick恢复成本](https://github.com/HATO-24/ghost-track-apsis/issues/49)
- [Q01 · #50 Linux/macOS支持验证](https://github.com/HATO-24/ghost-track-apsis/issues/50)
- [Q02 · #51 非 headless 产品入口与可见性渲染验收](https://github.com/HATO-24/ghost-track-apsis/issues/51)
- [Q03 · #52 超过1000 tick的成本与恢复正确性](https://github.com/HATO-24/ghost-track-apsis/issues/52)
- [F01 · #53 真实RF/光学模型的规格与校准研究](https://github.com/HATO-24/ghost-track-apsis/issues/53)

## 2. 审查基线与证据

| PR | 精确 head | 依赖/本轮决定 |
| --- | --- | --- |
| #32 A-00 | `882e058e2a0550684ade73f6978122fef46d42d7` | base=main；待整链放行 |
| #33 A-01 | `26f1d5398a4ed6654b057f23a27819e4bf700b31` | base=#32；R01 返修 |
| #34 A-02 | `7b5691482929d493467aec12eddbe20f3782f35e` | base=#33；随上游更新重验 |
| #35 A-03 | `f842b3db6158d08bb6da5221252745882a2cc858` | base=#34；R02 返修 |
| #36 A-04 | `b04726641057aa80ccc83829e8da00b973f2f733` | base=#35；保持旧档 union 负例，随上游重验 |
| #37 A-05 | `0a66ea2ca45e36739e3c92da80f742526b8b24cb` | base=#36；R03 返修 |
| #38 A-06 | `10a48653f9ff5b07517d6eb39c06dbdffb09104e` | base=#37；R04 返修 |
| #39 A-07 | `af5b92471a0f12f1ab95c7defda88360e171e277` | base=#38；R05 修验收/报告 |

以下称最后一行 **S7**。各返修先从本表所属 PR 的精确 head 复现，再验证修复后的最终整链；不能把八个独立结果相加。下游卡使用的 **M** 指未来通过审查并合并后的完整 main SHA，当前尚不存在；合并前均为 WAIT，不捏造执行基线。

本轮真实运行环境：Windows / Godot `4.7.2.stable.official.ed1daf0bf`。在 S7 上运行：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin $env:GODOT_BIN -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/merge-review/full
```

结果：84=77 PASS/7 FAIL，0 TIMEOUT、0 NOT RUN；`known_fail=7 new_fail=0 drift=0 complete=true`，耗时 386.9 s。[完整摘要](reviews/phase_a_20261025/full-matrix-summary.json)、[报告](reviews/phase_a_20261025/full-matrix-report.md)、[历史失败摘录](reviews/phase_a_20261025/historical-failures.log)。最终候选的 [CI run 40163649138](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40163649138) 三个 job 也均成功。此处只说明原矩阵结果，**不覆盖下面新增的反例**。

追加 [诊断脚本](reviews/phase_a_20261025/boundary_repro.gd) 在同一 S7 运行，输出 [结构化结果](reviews/phase_a_20261025/boundary-results.json)，退出 1、`violations=7`。它是审查复现脚本，不在默认矩阵中；需把这些反例纳入对应正式 probe 后再验收。

```powershell
& $env:GODOT_BIN --headless --path ./game_v17 --script (Join-Path (Get-Location).Path 'docs/reviews/phase_a_20261025/boundary_repro.gd')
```

| 反例 | 实际运行结果 | 归属 |
| --- | --- | --- |
| 显式 ID 后自动发布 | 两次均 ok，ID 都是 `evt-000001` | R02 |
| v2 state 删除 seen_ids，历史超过1000条 | import ok，已裁出的早期 ID 可再次发布 | R02 |
| 未知航迹的玩家 VM | tracks 无 batch，但 selected 返回 `SECRET-9001` | R01 |
| 已有通信 outcome 的 version=999 | load ok，降格为 legacy_unverified | R04 |
| sensor version=1.5 | 被 int 截断为1并接受 | R03 |
| 非空 optical 通道的 backend=null | import ok，实际通道从1变0 | R03 |
| 同 seed/输入，保存恢复后继续10 tick | 相同时刻15.1s，obs_seq 原会话64、恢复会话68 | R03 |

前三项既有缺陷/修复覆盖不足和新恢复器校验缺口应分别溯源，不都声称为本批新引入；均属于已承诺验收未满足。追加诊断发现的问题**没有**加入历史失败 baseline。

## 3. A-07 数字与预算口径

原始数据位于 S7 的 `game_v17/docs/benchmarks/a07_save_cost/measurements.json`。`bytes` 来自 `String.length()`，实际是字符数；正确 UTF-8 大小应取 `bytes_utf8` 并与落盘文件长度交叉检查。

| ticks | 原报告字符数 | 实际 UTF-8 B | 保存 median ms | 恢复 median ms |
| --- | --- | --- | --- | --- |
| 50 | 421869 | 426915 | 76 | 1103 |
| 200 | 1139120 | 1144166 | 175 | 5166 |
| 800 | 1925900 | 1930946 | 293 | 35184 |
| 1000 | 2160472 | **2165518** | 331 | **50164** |

1000 tick 三次保存为336/329/331 ms，恢复50267/50164/49690 ms，故最大值分别336/50267 ms。计时器位于 `GameSession.new()` 前，当前“load_state”样本实际包含会话构造+load；不含引擎启动、文件读。修报告时准确命名，不悄悄缩短计时窗口换取达标。

参考负载沿 A-07：Ryzen 7 7435H、Windows 10.0.26200、Godot4.7.2 headless，orbital_sim，dt=1s、scale=1、无暂停，固定每50tick控制序列；scenario hash=`cdd46e8b074840f34369da415f821ff7247a0806f8b76d86c181c41d9ff3cbf1`，seed hash=`2de7681ffb1d7578105146d7b7005e7890710e72d9aa7a1512d5c93431333760`。109.5MB 是进程静态内存读数，不是机器 RAM；下一次补记录实际 RAM/磁盘。

| 下一优化卡项目 | 1000 tick 工程预算 | 评价方式 |
| --- | --- | --- |
| UTF-8 文件 | ≤1,500,000 B（十进制1.5MB） | 三个样本逐个核文件长度；相对当前约减少30.7% |
| save_state | ≤250 ms | 预热一次后3次正式测量，每次均达标，不宣称p95 |
| 构造+内存恢复 | ≤5000 ms | 同上，继续沿原计时窗口，至少约10倍改善 |
| 文件读取 | ≤50 ms | 独立测量；不混入恢复计时，也不以快磁盘掩盖 replay 成本 |
| 正确性 | 全部保持 | 每个样本核状态并续跑10ticks，不能只查首样本或只比较seq下界 |

这些数字不外推为 Linux/macOS、渲染或10,000 tick 的已验证预算。>1000 tick 先按 Q03 标定，再冻结其预算。先分项 profile，再评估 checkpoint/完整状态恢复/尾部重放；现有数据支持重放是主要方向，不能据此断言“压缩无效”或证明某一复杂度。完整已用ID和可恢复历史不能为缩小体积被删掉。

## 4. 共同执行与回归规则

每卡开工先锁定完整 SHA、读取40/56及对应旧卡，列权威写者/读者、允许文件、旧档策略。先保留红证据，再最小修复；测试、实现、baseline/报告拆提交。PhysicsWorld 写运动学，EntityCatalog 写静态来源，TrackTable 写证据航迹，EventBus 写seq/ID，各服务恢复自己的运行态；UI只读。

沿用已有单位：bary_rot、km/km/s、模拟秒；同tick≤1e-6s，位置投影≤1e-9km、速度投影≤1e-12km/s，确定性几何≤1e-6km/deg。JSON 载体按数值语义校验，恢复后对契约整数检查真实int，不能全局转int。浮点时间/payload按原契约保真；玩家真值边界、有限弹药/正常授权、默认full保持。

下称 **C回归**，从执行仓库根目录运行；每卡把 `<卡号>` 替换为实际编号（仅结果目录占位）：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/next-cards/<卡号>/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/next-cards/<卡号>/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/next-cards/<卡号>/full
```

专项按卡给出的 `-Only` 运行，不带全量baseline；确认 `-List` 的选项和实际case，不接受0 case/NOT RUN/超时。报告保留原始命令、完整SHA、退出码、断言数、summary.json/report.md/import.log/logs与CI artifact。七项历史条目转绿或计数变化需逐项审查证据，再独立提交删除/修正；新发现缺陷不登记为历史。若历史条目全清零，去掉 `-Baseline`，runner拒绝空failures[]；不得放宽检查、跳过失败或continue-on-error。

R01–R05按源码所属原PR追加小提交，最终统一整理堆叠依赖并更新下游SHA/证据。GameSession集成顺序 R02→R03→R04；R01、R05 的独立服务/报告可先行。不能让多个任务分别重写save/load。M之后H01、H02、H03以及Q01/Q02可独立分支，最终顺序集成并重跑C。这里是执行依赖说明，不表示已启动任何执行器。

## 5. 合并前返修卡

### R01｜玩家 VM 所有分支遵守相同可见性

- **状态/基线**：READY；P1；#33 head=`26f1d5398a4ed6654b057f23a27819e4bf700b31`，复现也在S7；父卡A-01。
- **目标/范围**：修复选中未知目标时返回批号；允许track_table.gd的玩家投影、CIC/实际HUD的必要读取适配及a0_integration_authority/track probes；不改内部融合身份算法或清空内部batch。
- **契约**：玩家tracks/selected/嵌套events等公开分支使用同一字段策略；内部snapshot/all_tracks保留去重信息。稳定命令ID不丢失，未知身份不自动升级；本舰/公开设施例外写明来源。
- **步骤/验收**：先固定`SECRET-9001`反例；逐入口审计并最小修复。未知列表/选中/取消选中/嵌套事件都无真值泄漏，内部记录仍有batch、已有命令与选择可用；正例验证获准公开字段。对比原VM，不能靠删整个selected/events通过。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'track_table|cic_view|a0_integration_authority|a1_entity_metadata' -Ci -ResultsDir .test-results/next-cards/R01/targeted`，随后C回归。
- **交付**：原/新VM字段映射、红→绿、完整SHA、源码/测试/报告分提交。独立审查真实HUD与嵌套分支；#33未修前不放行整链。

### R02｜事件自动 ID 唯一与新档完整性

- **状态/基线**：READY；P1；#35 head=`f842b3db6158d08bb6da5221252745882a2cc858`及S7；父卡A-03/A-04。
- **目标/范围**：防显式`evt-000001`与下一自动ID重复，防v2缺seen_ids被当成功恢复；允许event_bus.gd、Session bus导入小段、event/legacy probes；不改其它服务或换存档编码。
- **契约**：EventBus分配ID/seq；所有成功publish唯一。新版本必需state字段严格校验，缺失/错误类型明确拒绝，失败不半写；仅真实旧格式走显式迁移。保留A-04重放集合∪可见历史、2^53−1范围、浮点payload与无历史派发规则。
- **步骤/验收**：显式ID在自动前/后/隔多个ID、达到分配边界均测；恢复后继续发布无碰撞。>1000事件后删除seen_ids的新档必须拒绝且原bus不变；旧seq/events档仍恢复已重放的早期ID并拒绝重发。校验可见ID与保存集合对应，不把新损坏档降为旧档。拒绝路径不推进counter；只修缺陷不刷新baseline。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'core_time_event|a0_event_continuity|a0_legacy_save|save_probe|a0_save_roundtrip_authority' -Ci -ResultsDir .test-results/next-cards/R02/targeted`，随后C。
- **交付**：两项复现、new/legacy支持矩阵、红→绿及同提交完整回归；测试/修复/证据分提交。审查ID高水位和裁剪历史去重，随后更新#36及下游。

### R03｜传感器严格恢复及同输入续跑一致

- **状态/基线**：READY；P1；#37 head=`0a66ea2ca45e36739e3c92da80f742526b8b24cb`及S7；父卡A-05；Session接入等R02。
- **目标/范围**：拒绝version=1.5及丢失必需backend的新档；消除原会话64/恢复68的观测序号差。允许SensorService、authority/optical后端导入、Session sensor接入小段、a0_sensor_persistence/A0-T3。
- **契约**：明确完整运行态包含哪些时钟、pending/outbox、通道、分配器和去重信息；临时验证对象不是代码注释，应确实做到失败不半写。新档不能以默认值掩盖缺字段。未知/分数/越界版本拒绝，旧档缺整个sensor段按已公布partial策略处理。
- **步骤/验收**：先重现三个反例；定位额外四条观测实际来自哪里，不预判是backend、时钟还是待路由队列。保存前主动切EMCON、建非空optical/IR、推进非初始状态；每次内存/文件恢复都比较完整规范化状态及未来10tick的新观测/证据/ID/时间/通道内容。相同输入应有相同输出；不能只检查“不回退”或解释为设计差异。异常backend/版本/目标/通道/非有限值拒绝且原态不变；不重复路由历史。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_sensor_persistence|sensor_service|optical_ir|a0_save_roundtrip_authority|save_probe|session_probe' -Ci -ResultsDir .test-results/next-cards/R03/targeted`，随后C。
- **交付**：状态字段分类、差异根因、三项红→绿、逐tick输出对照和完整回归。独立核查临时对象/原子导入、provider重绑和真实文件；不扩大IFF/EW范围。

### R04｜通信 outcome 的版本与完整性校验

- **状态/基线**：READY；P1；#38 head=`10a48653f9ff5b07517d6eb39c06dbdffb09104e`及S7；父卡A-06；等R03的Session接入。
- **目标/范围**：带未知版本的新outcome必须拒绝，而非legacy_unverified；允许Session通信日志/重放小段、schema/docs及a0_comms_restore。
- **契约**：只有确实没有outcome字段的旧操作才可按旧策略标unverified；字段存在但schema/version/必需类型错误属于损坏/不支持。核对声明保存的mode、relay_count、sent_t/arrive_t、路径/ID/时延与成功/原因；离散值精确，时间≤1e-6s，数值有限。
- **步骤/验收**：固定version999；增加未知schema、1.5版本、null/错类型、溢出数字、缺必需字段的JSON负例，内存对象另测NaN/Inf；原成功/原no_route失败均按同一结果恢复，真正分歧拒绝。旧无outcome仍诚实partial，消息恰好一次。不能加LR链、删失败发送或忽略所有错误。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_comms_restore|order_comms|a0_save_roundtrip_authority|session_probe' -Ci -ResultsDir .test-results/next-cards/R04/targeted`，随后C。
- **交付**：版本/字段支持表、原执行/replay对照、红→绿、完整回归；独立核查旧档分支与投递语义。

### R05｜成本报告使用真实字节，逐样本校验恢复

- **状态/基线**：READY；P1验收；#39 head=S7；父卡A-07；最终测量等R03/R04完成。
- **目标/范围**：修正bytes=字符数、git_head空及仅首样本完整验收；允许benchmark driver/manifest、原始数据和报告，不做checkpoint优化。
- **契约**：字符数与UTF-8字节分列，实际文件长度交叉核对；计时窗口沿§3并精确命名。每个样本的tick/control错误、load结果、状态及后续10ticks均影响FAIL；不能只测首样本。记录真实代码SHA，不用环境空字符串当provenance。
- **步骤/验收**：原始旧数据保留，报告从bytes_utf8重算；三次非预热样本均校验world/physics/epoch、完整ID集合而非仅size、sensor通道/输出、消息队列/投递。故意在第二或第三样本注入恢复差异，驱动必须非零。CSV避免在res内被当作翻译资源导入；不改旧数据冒称重测。改过driver/源码后在同一最终提交重跑，旧样本只作历史。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/next-cards/R05/benchmark`，随后C。1800s仅安全超时，不是性能预算。
- **交付**：逐样本raw JSON/CSV、准确units/provenance、故障注入日志、新性能表与局限。去掉“压缩无效/统一线性KB每操作”等证据不足的结论；独立核查每样本正确性，尚不要求本卡实现§3优化预算。

## 6. 七项历史失败：四张独立修复卡

### H01｜舰级/毁伤档案与缺档案语义（覆盖3 cases）

- **状态/基线**：WAIT M；P1，Phase B前处理；审查参考S7。覆盖`content.damage_profile_probe 554/4`、`integration.damage_integration_probe 198/6`、`integration.v17_nav_integration_probe 181/1`。
- **实际问题**：档案36vs旧期待32、harmattan舰级归属和回退；4条String构造SCRIPT ERROR；后两个case都包含“ferry已出现档案而测试仍当无档案”的同一契约，不应另派导航重写。
- **范围/契约**：允许damage_profile_service、舰级/实体档案映射及三probe的fixture和文档；档案/ShipCatalog是唯一内容来源，伤害由既有服务写入，不改弹道/战斗授权或升级所有舰船参数。
- **步骤/验收**：先列批准目录与实体→class映射、明确缺档案拒绝/回退策略；修实际String错误和归属缺陷。目录变化的测试调整附来源diff，缺档案负例改用真正未注册fixture，保留拒绝及无伪造断言。正例全目录覆盖、合法命中一次；负例未知class/错ID/缺档案/重复shot不产生错误状态。存读档及product smoke保持。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'damage_profile|damage_integration|v17_nav_integration' -Ci -ResultsDir .test-results/next-cards/H01/targeted`，随后C。
- **交付**：三case归因表、4条SCRIPT ERROR消失证据、红→绿、批准的内容契约、独立baseline删除提交及同提交回归。不能仅把32改36或把true改false应付测试。

### H02｜legacy TWS/显示的本舰 ID 归属（覆盖2 cases）

- **状态/基线**：WAIT M；P1，接Phase A后续；参考S7。覆盖`integration.plot_tws_probe 58/1`、`integration.v17_sensor_authority_display_probe 71/3`。
- **实际问题**：TWS observer预期本舰track1001却用1000；显示1000 level4/friend/空sources与fixture的2/unknown/YW-R9不符。先核对own_entity/track/entity映射，不能按track编号硬改身份。
- **范围/契约**：允许legacy bridge/state/plot适配和对应fixtures/probes，产品HUD只做兼容验证。稳定实体ID决定本舰，不能列表序号替代；明确legacy/advisory与产品权威边界，不让旧显示写主线track。
- **步骤/验收**：证明误归属路径后修最小映射；对调track创建顺序/编号、不同own_entity、缺本舰、跨帧和无证据目标均测。来源/等级/身份按同一证据一致，未知不友军、本舰例外有真实归属；产品同tick观测与R01可见性不回退。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'plot_tws|v17_sensor_authority_display|a0_integration_authority|a0_track_truth_authority' -Ci -ResultsDir .test-results/next-cards/H02/targeted`，随后C。
- **交付**：旧/新实体映射、两case红→绿及主线无双写证据；审查后独立移除2条baseline。不得通过关闭legacy probe或把friend写成期望解决。

### H03｜设施事故生成的输入集合（覆盖1 case）

- **状态/基线**：WAIT M；P2内容一致性；参考S7，`unit.incident_record_probe 2761/1`。
- **实际问题**：registry输入设施数 actual89/expected23，尚未证明该变更属于fixture滞后还是生成器混入额外来源。
- **范围/契约**：允许incident_record_service/设施注册输入适配及probe fixture；FacilityRegistry决定设施集合，事故服务只消费明确快照，不增写设施、不扩写剧情或重新生成站点设定。
- **步骤/验收**：先列输入IDs、去重/过滤规则、批准目录变化；独立构造2站点正例只产生这2个输入的记录，未知/重复/空输入有明确行为。全目录按内容来源diff验收，而非把89抄为新常量；固定seed重复运行一致，存档/报告继续可用。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'incident_record|facility_registry' -Ci -ResultsDir .test-results/next-cards/H03/targeted`，随后C。
- **交付**：23→89的来源解释、输入契约、红→绿、baseline独立更新和完整回归；不能直接扩大生成范围掩盖计数差。

### H04｜现有序章文本与批准来源对齐（覆盖1 case）

- **状态/基线**：WAIT M；P2维护，剧情扩写仍暂停；参考S7，`content.story_text_probe 469/13`。
- **实际问题**：12个text_key与docs/44逐字源不符，另1条汇总失败；先查文本审批记录与来源版本，不能默认代码或旧doc任一方必然正典。
- **范围/契约**：仅已存在12键、其source_lines/批准引用、验证器/fixture及必要文档；不新增对白、分支或CG。批准文本是内容权威，验证器按固定revision校验，不能读实现现值当expected。
- **步骤/验收**：逐键给旧/新文本和批准依据；若找不到决定某键的证据，仅该内容取舍标待负责人，不阻止独立技术工作。正例批准文本匹配，负例改一个字符/缺键/错源行仍失败；中文UTF-8与full启动保持。
- **执行**：`pwsh -NoProfile -File ./run_tests.ps1 -Only 'story_text|story_runtime|prelude_scenario' -Ci -ResultsDir .test-results/next-cards/H04/targeted`，随后C。
- **交付**：12键审批映射、13断言归因、已批准部分红→绿与局限、baseline独立更新；未批准键不能自动改为期望。

## 7. 性能与未验证平台/物理边界

### S01｜按预算优化1000 tick恢复成本

- **状态/基线**：WAIT M和R05可信新测量；P1；参考负载/预算见§3。
- **目标/范围**：达到§3全部预算；允许存档版本化完整状态/检查点、尾部日志重放及相关服务恢复接口和benchmark；不顺手重构GameSession全类，不关闭系统、压缩掉已用ID或丢历史事实。
- **契约/步骤**：先分项profile验证主要耗时；设计完整恢复覆盖表，避免只恢复图像。给出版本迁移、完整checkpoint+tail顺序、错误原子性、随机/ID/通道/队列状态；先用中途机动/排队通信/非空通道/超过1000事件的正负例红证据，再最小实现。损坏checkpoint/错tail/重叠ID/不支持版本拒绝，旧档继续受支持。
- **验收**：同一参考负载预热1次+3正式样本，**每样本**≤1500000 UTF-8 B、save≤250ms、构造+恢复≤5000ms，file-read≤50ms；完整状态和未来10tick输出一致，不能只比较count或下界。
- **执行**：沿R05的独立benchmark命令，将结果目录改为S01；专项`-Only 'save_probe|a0_event_continuity|a0_legacy_save|a0_sensor_persistence|a0_comms_restore|a0_save_roundtrip_authority'`后C。
- **交付**：设计/失败用例/实现/迁移/性能证据分提交、原始样本、同机前后表与完整回归。预算不达标如实报告，不自行改预算；进一步方案需有分项测量。

### Q01｜Linux/macOS支持验证

- **状态/基线**：WAIT M；P1验证，可与独立内容卡并行。当前只确认Windows，不能把未测平台写成支持完成。
- **范围/契约**：允许CI矩阵、Godot4.7.2下载/发现、PowerShell封装、路径/大小写/换行兼容小修；不改仿真规则以适配OS。runner发现失败明确exit2，文件路径和UTF-8存档可移植。
- **步骤/验收**：明确ubuntu/macOS runner架构与匹配二进制，先真实执行，再修平台缺陷；两平台至少跑C的Phase0/PhaseA与完整矩阵，保留逐OS失败集合和计数、导入错误/权限/存档文件往返。无运行器/配额记NOT RUN，不伪造PASS；legacy失败若平台不同须先归因，不能复制Windows baseline蒙混通过。
- **执行**：各平台`pwsh -NoProfile -File ./run_tests.ps1 -GodotBin <该runner已发现的4.7.2可执行文件> -Gate phase0 -Ci`及同参数PhaseA/完整C；路径由CI真实发现，不能照抄Windows exe。
- **交付**：OS/架构/引擎hash/完整SHA、各平台Actions/artifacts、迁移文件fixture、支持矩阵和局限；独立核查未运行平台未被写为支持。

### Q02｜非 headless 产品入口与可见性渲染验收

- **状态/基线**：WAIT M；P1；不依赖真实RF研究。
- **范围/契约**：允许最小截图/交互验证钩子、渲染兼容修复；维持已批准四区HUD，不做模型细化或HUD重做。视图只消费同tick只读数据，未知目标不能从选中/tooltip/事件窗口泄漏真值。
- **步骤/验收**：真实显示后端运行orbital_sim与full，1920×1080及1280×720，记录renderer/GPU/OS/缩放；检查进入菜单→HUD、暂停/倍速、选中未知目标、EMCON切换、内存/文件读档、非空通道和消息后续显示。正常/缺数据/恢复后各留截图及动作日志；UI字形、中文输入、命中区域、遮挡和来源标签人审。虚拟显示通过仅表示该renderer路径，不冒充真实GPU验证。
- **执行**：`DSH_BUILD=orbital_sim`环境下用4.7.2**不加--headless**启动`--path ./game_v17`，按上述固定步骤；full另跑。用各平台正确设置环境的方法，结束清理DSH_*；源码如有改动再C。
- **交付**：动作清单、前后截图、GPU/renderer/provenance、错误日志、可复现差异和未覆盖设备；独立视觉审查后确认，不能用headless boot替代。

### Q03｜超过1000 tick的成本与恢复正确性

- **状态/基线**：WAIT R05；P1标定，可先用修正后的候选完整SHA测量，最终与S01优化版同负载比较；未测前不设产品秒数预算。
- **范围/契约**：benchmark参数化及报告；固定A-07相同seed/dt/操作序列。新增2000/5000/10000 tick规模，每规模新会话；保留完整去重集合、日志/通道/队列，不靠减少事件换速度。
- **步骤/验收**：先2000再向上扩，逐规模记录UTF-8大小、各耗时、内存、IDs/log数量；每样本核完整状态及后10tick。基准耗时超过当前1800s安全上限时保留TIMEOUT和可用数据，分析后再决定单独延长，不把超时当失败样本删除。1预热+3正式适用；资源不足规模明确NOT RUN，不能外推宣称通过。
- **执行**：扩展独立benchmark manifest/driver的显式scale参数，给出最终真实命令；仍用`-Matrix game_v17/tests/benchmark_matrix.json`、精确`-Only`、`-TimeoutSec 1800`，不加入默认全量矩阵。默认84项及新增correctness probes不能因长测量被跳过。
- **交付**：规模表/原样本/超时、环境与完整SHA、S01前后曲线；基于实际数据另冻结>1000tick预算，当前数字保持“未测”。没有达到更大规模不妨碍诚实发布1000tick结果。

### F01｜真实RF/光学模型的规格与校准研究

- **状态/基线**：PLANNED，P2研究；先等Phase A后续身份/IFF/EW消费者契约明确。不是当前八卡的合并门槛，也不能以本卡名义把抽象模型改称真实物理。
- **范围/权威**：只交规格、参考来源和独立校准fixture；不在同一卡实现完整RF波形/光学链。现有PhysicsWorld给几何，Sensor/EW/Comms消费明确的模型结果，不新增第二套坐标真值或直接写身份/伤害。
- **研究交付**：分别列RF/光学要达到的精度层级、频段/设备参数、距离/遮挡/指向/噪声/处理增益等已支持和未支持输入、计算/采样成本、校准数据与单位。使用可追溯一手标准/官方技术资料和公开数据，明确近似与适用范围；不给无来源常数或“全物理”口号。
- **验收**：单位和维度、可复算的基准算例、边界/不可用输入、同tick几何与误差预算、计划消费者/事件schema、存档和随机种子策略；每类量化阈值由参考与fixture推导。规格审查后再拆最小实现卡；未实现的波形/衍射等能力保持NOT IMPLEMENTED。
- **执行/报告**：研究阶段不运行无关全矩阵；文档给出后续验证命令与样例，新增独立原型时留原始数据/命令；若改产品代码则越出本卡。交付规格、校准计划、性能预算建议和明确进入条件，经独立物理/架构审查。

## 8. 修复后的合并操作与关闭条件

1. R01–R05各自红→绿并补正式回归，不抹去本轮原始失败；统一更新堆叠分支，冻结新的每个head和最终候选完整SHA。S7旧报告保留为历史，不能改写成新head已通过。
2. 最终候选上的Phase0、PhaseA、本批新增负例和完整矩阵都满足门槛后，按 **#32→#33→#34→#35→#36→#37→#38→#39** 合并。中间PR历史PhaseA红属于分阶段缺口，不能作为最终交付通过；原7项历史失败仍单列。
3. 使用保留祖先关系的merge commit；每次核对expected head SHA，将下一PR显式改base=main，再确认差异仅为下一切片和所需检查，不把它合回旧功能分支。不要先squash/rebase合并导致后续重复祖先；不提前删除堆叠分支。
4. 最后检查main树与已验收候选一致，并在最终main跑C；若出现新差异先解决再声称完成。更新交付索引、实际merge SHA和对应任务状态；七项历史失败继续按H01–H04处理。
5. 本文是规划和审查结果，不伪造Astra已独立批准。用户已要求按序合并，授权本身不缺；本轮暂停的原因是已运行复现的验收缺口，待DeepSeek返修后即可继续该顺序。
