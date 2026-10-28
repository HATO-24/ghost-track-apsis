# PR72 / JC-A04 第四轮独立放行与 B01A 交接

日期：2026-10-29（Asia/Shanghai）。**PASS：原R1现代缺省入口关闭，A4放行；PR72已合入main，#61完成。** 下一张既有卡为[JC-B01A/#62](../../tasks/joint_campaign/JC-B01A_deployment.md)，本轮只准备交接，不自动启动实现。

## 1. 冻结与合入

| 项目 | 精确值 |
| --- | --- |
| A4冻结 / 独立验证HEAD | `af924d09f5c1d763f8d2556cd94062134ef3c456` |
| 原main/base | `4e4f90f9eb4964503a61dd915cb1c445294b10a5` |
| PR72合入main | `1b483e0f2f2a9bfdaa100caf2ee6742091193204` |
| 候选与合入的完整tree | `7576df59d39feb86fff7073240d0f8bdcfc99587`，相同 |
| 候选与合入的game_v17 tree | `d9e503460b3cefdb56fe14d9d9050e0d3ecd525a`，相同 |
| 环境 | Windows / Godot4.7.2.stable.official.ed1daf0bf / headless |

根未修改生产、正式probe、matrix、baseline或退出码包装，只写诊断和根docs。C启动时tracked dirty来自自动导入元数据与根docs复核稿，运行代码/正式测试保持HEAD不变；本机.import/.uid未交付。91个注册ID非空唯一，原ID保留。七历史baseline原始SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`，未刷新。[机器记录](verification.json)。

## 2. 原最后入口已关闭

同一显式现代authority seed、真实新发送，无load/replay：

| 输入/控制臂 | 实际结果 |
| --- | --- |
| ally_ship＋空opts | sender_context_required，无delivery_id、foreign pending、SENT/DELIVERED |
| enemy_ship＋省略opts | 同样拒绝，无投递 |
| 现代own缺省 | 合法，t2只送达一次 |
| 显式own/player、ally/ally | 各t2送达一次 |
| 原三显式错配及enemy/player订单 | sender_context_mismatch，订单无order_id |
| 真正旧seed默认 | 兼容并t2送达一次 |

现代缺省先按已登记实例/域与可信本方锚点判定，不再仅凭缺调用字段就降为legacy。非本方需完整合法上下文；原A01共享owner授权锚点只用于共享入口，普通send/order不借该路径。这里只验证原sender边界，不声称新增加密认证或所有攻击面已经证明。

[一次诊断源码](authority/authority_audit.gd) / [完整数据](authority/authority_audit.json) / [摘要](authority/summary.json) / [说明](authority/findings.md) / [日志](authority/authority_audit.log) / [命令与退出码](authority/run.json)。一次运行exit0，3.18s；保留原日志提示，不称零stderr。原R1整组CLOSED。

R2普通ignore_ew拒绝与v1内部重放、R3真实RNG/配置/无send日志共享文件续存、R4严格状态/版本拒绝与正式合法fresh共享0→1稳定，以及三入口/唯一推进/真实callback/失败订单不执行等，均保留关闭。不因最终收尾重做这些链路。前轮证据：[第三轮](../pr72_a04_r3_20261029/review.md)、[第二轮](../pr72_a04_r2_20261029/review.md)、[首轮](../pr72_a04_20261029/review.md)。

## 3. 同一冻结HEAD的独立原C

| 运行 | 总项 | PASS/FAIL | 耗时含import | exit | 原始结果 |
| --- | --- | --- | --- | --- | --- |
| targeted | 8 | 8/0 | 60.6s | 0 | [report](targeted/report.md) / [summary](targeted/summary.json) |
| phase0 | 6 | 6/0 | 36.84s | 0 | [report](phase0/report.md) / [summary](phase0/summary.json) |
| phaseA | 3 | 3/0 | 27.51s | 0 | [report](phaseA/report.md) / [summary](phaseA/summary.json) |
| full | 91 | 84/7 | 446.65s | 0 | [report](full/report.md) / [summary](full/summary.json) |

根full **91=84PASS/7历史FAIL，known_fail7、new_fail0、drift0、unverified0、unselected0、complete=true、退出0**。A01实际authority回归90/0，A02及A03原用例也在全量保留。耗时不是>1000tick成本或新战役规模验收。

| 保留历史FAIL | pass/fail断言 |
| --- | --- |
| `content.damage_profile_probe` | 554/4 |
| `content.story_text_probe` | 469/13 |
| `unit.incident_record_probe` | 2761/1 |
| `integration.damage_integration_probe` | 198/6 |
| `integration.plot_tws_probe` | 58/1 |
| `integration.v17_nav_integration_probe` | 181/1 |
| `integration.v17_sensor_authority_display_probe` | 71/3 |

同head [CI run40762023327](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40762023327)三个job SUCCESS；full实际checkout合成merge`86c5630a6a1396f0b143d451043d2c333262b8f8`（af924d09合入4e4f90f9），91=84/7历史FAIL、无新增/漂移、complete=true、FULL_MATRIX_EXIT=0，360.0s。[原始CI](ci/full.log) / [关键行](ci/full-relevant.txt) / [元数据](ci/checks.json)。本地直接冻结HEAD与CI合成merge分别记录，不混称同一checkout。

命令沿原卡：8项`-Only`专项；`-Gate phase0 -Ci`；`-Gate phaseA -Ci`；全量`-Ci -Baseline game_v17/tests/known_baseline_failures.json`。均显式使用上述GodotBin、ResultsDir为`.test-results/sol-a04-r4/{targeted,phase0,phaseA,full}`；完整参数在summary.invocation。原始字节校验：[manifest.sha256](manifest.sha256)。

## 4. 下一既有卡准备完成，尚未启动

[B01A/#62](../../tasks/joint_campaign/JC-B01A_deployment.md)以本轮获审A4及其main合入提交为前置，从包含该合入的最新main开始并记录实际40位HEAD。只做原部署切片：编制选择/校验→冻结稳定独立实例→同源deployment seed→catalog/world/physics/每实例资源与恢复→最小确认部署入口及原非headless验证。不将纸面编制或单独physics upsert称作完整部署。

已补清实际boot顺序：先注册catalog，再在_setup_optional_components中初始化/seed PhysicsWorld，随后发布并apply world的entity.spawn；三者同源而非部署时新增第二套运行时写者。physics_world.entities优先于seed.entities、world缺ID时sync跳过，均为实现需保留的实际接点。实例归属继续用own_entity/fleet_instances/command_domains，生成实体不直接授予玩家敌方真值航迹。

最小UI沿原UI-04a编制/部署合同和既有组件排程，保留合法/拒绝原因与非headless验收；不扩整站UI或协同页。UI设计文档GPT/Sol，主要代码DeepSeek。B03P舰池/预算/命名仍为待核对提案；不固定旧13舰/8槽，不扩B1b多舰发射、AI、目标结算或产品参数。本轮未启动B01A实现。

A4放行不等于完整联合战役demo完成。低质量仍能射击不自动构成禁射缺陷。Linux/macOS、非headless渲染、真实RF/光学、>1000tick成本本轮NOT RUN；spoof effect查询与未验证真实消息能力的既有界限保持。
