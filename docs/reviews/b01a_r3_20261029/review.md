# PR75 / JC-B01A第三轮：原R4/R5仍未关闭

2026-10-29（Asia/Shanghai），冻结`3ea9e8ceb9f247acd4a24641277c621146730d8f`。**RETURNED，继续原#62；D1不放行，PR75/74保持OPEN，不启动下一卡。** 本轮只查原装备冻结与最小可见部署入口，不重新派发第二轮已关闭的五个窄观察。

## 根独立专项与证据口径

Windows / Godot4.7.2.stable.official.ed1daf0bf / headless，卡指定专项**7/7 PASS、新部署probe83/0、退出0**，80.5s含44.2s导入。[summary](targeted/summary.json) / [逐项报告](targeted/report.md)。生产、正式probe、matrix、baseline无根修改；本机导入元数据不交付。七历史baseline未刷新。

交付四份final/phase摘要实际为`323018ac`加dirty生产/UI/probe，不是干净`3ea9e8ce`运行。可作为实现工作树记录，不能称同一最终HEAD。[源交付](https://github.com/HATO-24/ghost-track-apsis/pull/75)。最终同head CI三个job SUCCESS，full92=85PASS/7历史FAIL、new0/drift0/complete=true、FULL_MATRIX_EXIT=0，[快照](ci-checks.json) / [原始full](ci-full.log)；不是用旧dirty结果替代当前CI。根原C未重跑，因为真实入口已有原卡阻塞，等待修复后最终HEAD再跑。

## 原R5：首次确认路径仍被锁住

已检查[交付非headless截图与README](https://github.com/HATO-24/ghost-track-apsis/tree/3ea9e8ceb9f247acd4a24641277c621146730d8f/game_v17/docs/next_cards/evidence/b01a/nonheadless)。1600×900真实HUD中确有部署按钮、状态与结果，接线可保留；但截图是`DEPLOYED`且selftest调用返回`already_deployed`。`deployment.auto=true`在boot已部署，`_b01a_deploy_selftest`直接调用Binder动作，没有经过玩家按钮操作。这证明已有窗口和显示，未证明从未部署选择首次确认生成。

根一次有界诊断只复用交付场景及其`auto=false`控制，调用真实ShellBinder.boot/DEPLOY_PLAN/DEPLOY，不做桌面输入或根非headless渲染。[诊断源码](entry_audit.gd) / [完整实际记录](entry_audit.json) / [原始日志](entry_audit.log) / [命令及限定](run.json)。退出0表示记录完成，日志保留既有ObjectDB/resource退出提示，不称零stderr。

| 控制臂 | 实际观察 |
| --- | --- |
| 原交付场景auto=true | boot成功，已部署5舰；PLAN rev-425754d2，DEPLOY成功却返回旧rev-91bf12e8/already_deployed |
| 仅改auto=false，boot后立即PLAN/DEPLOY | boot成功且未部署，但时间已0.1s；PLAN成功，DEPLOY=false/deployment_locked，world仍只有legacy_ship |
| 同auto=false，再走一次Binder.tick(0.1) | 时间0.2s，仍deployment_locked，未生成选择舰 |

`shell_binder.gd:267`在boot就调用session.tick(0.1)，HUD之后继续tick；`fleet_deploy`的首次部署只准now_s≈0。因而不是玩家手速或缺一张截图：当前真实Binder路径在首次可操作前已把预部署窗口锁死。原卡需使真实预部署阶段可选择/确认并首次生成，保留交战中重部署锁、损伤和幂等语义；不能靠提前自动部署、回填时间或重启战斗来替代。

## 原R4：实际配置已读取，但冻结时机与版本仍不一致

新代码有从FleetRefit读取当前状态的路径，手动Session预部署的实现与新增断言可保留。实际交付auto路径在`_setup_deployment_from_seed`调用时FleetFormation/FleetRefit尚未初始化，先冻结了空实际配置。根记录当前APSIS refit状态非空、冻结refit_service_state却为空，current_refit_equals_frozen=false。

随后PLAN刷新了当前配置，所以得到新revision；DEPLOY的早期`matches_selection`只比ship/slot/instance_id，直接返回旧冻结。交付README中的两个不同revision与根诊断完全一致。应在所需配置就绪后冻结，并使PLAN、首次确认、资源快照、实际实例及恢复指向同一版本；相同配置重复确认保持幂等，不把不同配置请求静默报成旧部署成功。不要求B1b发射/完整改装。

## 原卡返修与放行条件

只继续R4/R5：补真实Binder/HUD未部署→检查→确认→首次部署与受阻结果；快照应断言具体已有配置内容、plan/confirm同revision及真实文件恢复保持。保留已通过的合法恢复/单位转换/独立资源及第二轮关闭子项；新增正式83断言的存在不代替实际入口证明。10tick新增比较目前仅事件type，证据口径保留该限定。

修复后同40位最终HEAD交卡指定专项＋原C、真实文件续行、非headless操作前后/拒绝证据及新日志，再独立复核。原CI完成可补原始日志，不能仅凭CI绿宣称首次UI部署通过。UI设计文档GPT/Sol，代码DeepSeek；交接由用户转发，Sol未操作DSH、未直接派发。既有A4、七历史baseline、B1b/B1c/AI/RF/产品参数范围不变。[第二轮已关闭表](../b01a_r2_20261029/review.md)。
