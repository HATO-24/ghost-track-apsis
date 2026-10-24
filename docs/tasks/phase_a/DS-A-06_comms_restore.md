# DS-A-06｜真实 HUD 会话的通信读档恢复

状态：WAIT I5；优先级：P0；父需求：#2.5/通信恢复；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

包含通信操作的真实会话可以保存、读取并继续，原来的成功/失败发送及延迟均被保留。T22 A0-T3 的真实 HUD 往返记录了 `replay send_comms 失败：no_route`；本次写卡没有重跑，不能先断言路由状态丢失。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`、T22=`8bf7517cef32ca14699cca1b048ef3398b9eb88d`；执行基线为 A-05 的 I5 完整 SHA，输出 I6。

## 复现线索与范围

静态线索：`V1HUD._ready()` 调 `_seed_comms_sample()`，分别发送 LD/LR；orbital_sim 的 links 都为 LD；CommsService 按 mode 精确选路；Session 在发送前记录 op，load 把任何重放 op `ok=false` 当恢复错误。**待验证假设**是“原运行就失败的 LR 操作被重放成读档错误”。先记录原执行 outcome，区分该假设、路由确实缺失、初始化顺序、状态未保存及已修复五种情况。

允许 `game_session.gd` 的通信操作日志/恢复局部接口、`comms_service.gd` 或 `order_comms_core.gd` 中已复现缺陷、相关 schema、`a0_comms_restore_probe.gd` 与 A0-T3。HUD 只允许必要的可测试入口钩子，不删除示例发送、不加不存在的 LR 链、不篡改 scenario 拓扑转绿。事件恢复遵守 A-03/A-04，不大改整个重放器。

CommsService 写消息/路径/投递状态；Session 记录操作及可验证 outcome；EventBus 分配事件。时间/延迟为模拟秒，路径节点用稳定实体 ID，frame/geometry 由 I5 契约提供。排队/投递顺序、消息 ID、成功/失败原因精确一致；浮点发信/到达时间容差≤`1e-6 s`。玩家仍按原授权与可见性操作。

## 步骤与验收

1. 从 `main_menu → v1_hud → ShellBinder → GameSession` 进入 orbital_sim，捕捉启动通信、原始 send outcome、路由拓扑和消息队列。保存并用真实 SaveService 文件读回，在 I5 上先复现；如果已不存在，保存同入口通过证据并解释由哪个前置提交消除，禁止凭旧文档制造修复。
2. 对照原执行和 replay 的相同 operation，记录 mode、source/target、route、delay、outcome/reason、消息 ID 与时刻；确认是预期失败还是恢复后发生分歧。
3. 若需保存 outcome，使用版本化、可校验的操作记录；恢复必须复现相同结果。原先 no_route 仍是失败发送及对应失败事件，不把它改成功；原先成功但重放 no_route 则是恢复失败。旧日志没有 outcome 时由 A-04 的版本规则明确判断可恢复范围，不能捕获所有错误后忽略。
4. 正例：LD 直连、存在的中继、队列中/已投递消息、读档时尚未到期的消息；继续到达后投递恰好一次，残余延迟与未中断会话一致，接收者/顺序/ID 保留。
5. 负例：原始失败 no_route、成功路径被故意移除、mode 不存在、错误 target、重放 outcome 与记录不符、重复消息 ID。原先失败可被正确恢复，但仍显示相同失败；真实不一致明确拒绝恢复或报告失败，不能吞异常/跳过操作。
6. 测试/最小修复/兼容/报告分提交，保存原失败日志；最后对三项 Phase A 与已新增切片在同一最终提交总验收。若全部切片已绿，Phase A job 应自然成功；历史 8 项仅按证据更新，不能宣称全量零失败。

## 命令与交付

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_comms_restore|order_comms|core_time_event|a0_event_continuity|a0_legacy_save|a0_sensor_persistence|a0_save_roundtrip_authority|save_probe|session_probe|e2e_orbital_sim' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-06/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-06/full
```

验收要求真实文件/HUD 会话恢复与续跑通过，Phase 0 6/6，Phase A 三探针及本批相关切片通过。上面的最终完整命令在 Phase A 登记失败经证据审查清零后使用；相应 CI 去掉 `-BaselineExtra`，避免 runner 拒绝空 baseline。若仍有失败，保留双 baseline 诊断，明确不能交付 I6 为完成，不刷新期望消除红灯。旧失败转绿、漂移及新失败按总队列 §4 逐项处理。

交付 I6 完整 SHA、原执行/replay outcome 对照、路由/延迟报告、旧日志兼容矩阵、红→绿和同提交全量 artifact；目录如命令。Astra 独立审查预期失败保留、真实不一致可检测和投递无重复。无论此卡通过与否，身份/EW 和完整战斗仍是后续工作。
