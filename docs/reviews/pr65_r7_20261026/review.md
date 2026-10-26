# PR #65 R7 独立复核与原卡收尾（2026-10-26）

审查候选：`2ae7bf7cba8af32ff4456cefe28efa3650b868dd`，相对 R6 `5d7208b82ebae81da874e059c2d88286317c6483`。运行环境：Windows、Godot `4.7.2.stable.official.ed1daf0bf`。main 仍为 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`。

**结论：本轮有实质进展，原 #56 / #57 / #63 仍需下列窄收尾；#65 暂缓合并，G0/K0 尚未放行，#58–#62 的核心整合保持等待。** 本次只增加复核文档和诊断证据，不修改生产代码、baseline 或预算。主要代码继续交由 DeepSeek；Luna 帮助复核 P0 内容，主审已收窄其初稿中过强的阻断措辞。

## 1. 已关闭的反例，下一轮不再整项返工

| 原项 | R7 独立核验 |
|---|---|
| 缺 `stare_s` 的不完整 STARE 通道 | 现在导入即拒绝；不是先接受再到 step 报错。剩余 `present:null` 见 G0-1 |
| 非法 authority/child 时钟与负计数的原子性 | 原三个 quick 反例均拒绝，前后状态未变 |
| ID 分配器只查类型、不查数值 | `220 → 320` 已被 `bus.id_seq` 比较检出 |
| 事件 payload / 观测质量篡改 | 内容差异均检出 |
| 非满历史下的通信正文篡改 | 即刻 pending 与真实逐 tick 投递均检出；不再调用不存在的 `last_event()` |
| 真实 C55 旧 v1 完全无法加载 | 现公共 load 成功；底层明确 partial，剩余顶层报告丢失见 G0-2 |
| 未选、未部署的实例仍可 fire | 正确拒绝 |
| 敌方 observer 自报我方 owner、自授权 | 正确拒绝；合法 ally→player 延迟共享 OBS-3 通过 |
| 部署负时间、记录终点与当前状态冲突 | 正确拒绝 |
| 缺 command_id、错误 request_id 关联 | 正确拒绝 |
| P0 的 APOGEE 150 点超 100 点预算 | 主案改为编制内 HEMATITE 20 点，两套范例 30 / 55 点均合法；既有命名实体映射另需归一 |
| 无武装友军却承诺火力任务 | 已改为侦察、中继、撤离支援，与真实目录能力一致 |
| 旧 62/70 点正文与新主案并存 | 已改为唯一当前主案，旧内容在明确历史附录 |
| 同 tick 民用损失 + 撤离覆盖成 withdrawal | 新逻辑按声明优先级判 defeat |
| 全目标失能但报告未回、友军自主完成 | 双视图与自主贡献轨迹已补入；不要求此时实现 B1–B3 运行层 |

专项 quick 的 `review_defects=0` 仅代表原诊断项目关闭。饱和通信诊断是对同一比较器追加的边界载荷，必须看 JSON 中的内容/violations，不能将其继承的退出 0 误写成全覆盖通过。K0 mutations 的退出 0 同样表示诊断完成，具体接受/拒绝看每条载荷结果。

## 2. #56 / G0：剩余四项

### G0-1：显式 null 绕过完整类型校验，仍会在后续 tick 报错

`game_v17/framework/sim/tws.gd:639–642` 对 `val == null` 直接 `continue`；前面的 required 校验只查 key 是否存在。完整合法 STARE 通道仅将 `history` 改为 JSON null，`validate_state` / `import_state` 均 `ok=true`，step 在 `tws.gd:413/470` 报 Nil→Array 的 SCRIPT ERROR。`stare_s`、`stare_required_s`、`quality`、`state_since_t` 显式 null 也被接受，详见诊断 JSON。

**最小收尾**：对 FSM 实际消费的必需字段明确拒绝 null 和错误类型，保持导入前全量校验、失败无半写入；保留正常快照和原缺字段负例。无需新增系统。证据：`evidence/save/tws_null_audit.{gd,json,log}`。

### G0-2：旧档 partial 已在底层返回，但公共 load 丢失模式和原因

复用 R6 从真正 C55 `30b8d33…` 导出的合法旧文件（含原格式、自身可加载的来源证据）。R7 底层 `SensorService.import_state` 返回 `restore_mode=partial`，原因含 `mount_pointing_missing` / `tws_runtime_reset_unrecoverable` / `authority_clock_rebuilt_from_optical_t`。这部分修复有效。

但 `game_v17/scripts/core/game_session.gd:5099–5124` 只取 `sr.ok`，重新构造 `_sensor_restore_report` 时丢弃恢复模式与原因；`GameSession.load_state` 与 `sensor_restore_report()` 都只展示 saved/time_ok/rebind 等字段。调用者无法得知扫描相位或目标指向未完整恢复。

**最小收尾**：把已存在的 partial 模式/原因透传到稳定的公共 load 结果或恢复报告，区分完整恢复与可接受的部分迁移。不要求凭空重建旧档未保存的历史，也不要求所有原型版本均完整向后兼容。证据：`evidence/save/legacy_partial_audit.{gd,json,log}`、C55 原文件及来源。

### G0-3：滚动历史满载后，逐 tick 比较仍会漏真实新增输出

`game_v17/tests/a0_save_cost_probe.gd:614–669` 用 tick 前的数组长度做 tick 后 `slice(old_size)`。这些历史是有界滚动队列（Comms `MAX_EVENTS=200`，Sensor observations `MAX_OBS=200`，EventBus 可见历史也有上限）；满载后新事件替换队首，长度不再增长。

独立对照将两会话的通信历史预置为同样 200 条合法结构记录，只篡改恢复会话的在途正文。实际 DELIVERED `seq=201` 正文不同，但 `_behavior_violations=[]`，最终比较也 `[]`；即刻 pending 比较仍能检出。说明“逐 tick 真正比较”在非满载已修，在长会话边界尚不成立。**不声称全部故障注入都逃过即刻检查。**

**最小收尾**：按事件/观测稳定序号或 tick 的真实输出提取新增记录，不能依赖滚动数组长度增长；验证满载前后同序号异内容会失败、正常继续会通过。底层比较能力修复后刷新相应证据。报告中“即刻＋逐 tick＋最终三处均发现正文”也需与实际比较范围一致。证据：`evidence/save/saturated_comms_audit.{gd,log}`。

### G0-4：本轮长测 JSON 已正确归档，但声明的 stdout/stderr 未进入 Git

本轮 `measurements.json` 与 `summary.json` 均记录测量代码 `a51e19f2e2609b69f4e90a87da7855538de205c4`，共有 4 规模 × 3 measured 样本；不再借用旧 `eaf953286…` 数据。这部分关闭。

然而候选 Git tree 的 `docs/benchmarks/jc_r2/r7_a51e19f2_20261026/` 仅有 README、measurements、summary 三个文件；README/返修报告所列完整 `a0_save_cost.log` 和 stderr 不存在。仓库 `*.log` 忽略规则可解释漏提交，但目录说明不能替代原始文件。

**最小收尾**：将实际原始输出作为可追溯的 tracked 文件/附件归档（可用 `.txt`，或显式加入），修正文档链接；不要把旧测量换标签。根审此次没有独立重跑四规模 14 分钟长测，`90/0、860.51s` 仍是作者归档结果。证据：`evidence/benchmark_evidence_audit.json`。

预算仍单列 #49，不改阈值。作者 1000 tick 三个 measured 样本：2,172,752 B，save 374–495 ms，恢复 57,707–69,618 ms，读盘 4–5 ms。要求逐样本满足 ≤1,500,000 B / ≤250 ms / ≤5000 ms / ≤50 ms，故仍不达标；不把本轮性能优化另塞进 G0 正确性修复。

## 3. #57 / K0：核心拒绝已修，完成最后一份一致的冻结合同

正常 `jc_contracts_probe` 独立 **78/0，退出 0**。原发射者/owner/部署/command_id 反例全部关闭。窄变异另确认以下规范与实现缺口：

| 项 | 证据与最小收尾 |
|---|---|
| seq 的必需性 | `jc_contracts.gd:389–391` 仅非 null 时校验；删除 `commands[0].seq` 仍接受。源码/报告声称事件 ID/seq 冻结：应落实必需性，或明确合法省略用途，正负例统一 |
| lifecycle 版本身份 | `:396–397` 只查非空；`UNSUPPORTED-999` 仍接受。列出受支持版本/未知版本策略并按合同校验，不需要实现 AI 生命周期 |
| receiver 是否必须显式声明 | `:338` 默认到 intel_owner，删除跨 owner OBS-3 的 `received_by_intel_owner_id` 仍接受，与 R7 报告“必须存在”冲突。选择并明示规范后保持一致，不添加权限服务 |
| 正式合同未更新 | `game_v17/docs/contracts/joint_campaign_r2.md:181–184` 仍写旧 authz==接收 owner 口径，与新合法 OBS-3（原始 ally 授权、player 接收）冲突；新 event/seq/lifecycle/receiver 的写者、读者、时间、版本/可见域也要进入当前字段表 |

请在同一份 canonical 合同中说明原始 owner、接收 owner、共享授权来源及旧单舰输入的可信本舰锚点/适配口径；保留旧 own_ship 正例和 all_allies 拒绝，不把字符串相等自证可信，也不擅自选定产品旗舰。

反向生命周期时间、rejected→completed 等附加组合仅列后续非阻塞观察，不临时扩大本轮前置要求。完整 K0 记录见 `evidence/contracts/findings.md` 和 mutations 脚本/JSON/日志。

## 4. #63 / P0：主案已接近可审，收尾限于内容一致性

这是提案，不是已批准正典；预算/容量、舰型组合、日期、目标阈值和终态数值不因探针通过而生效。用户已确认的阶段性战区行动和自有直控＋友军请求，不重复询问。

1. **既有命名实体映射归一**：新虚构旗舰 I-A1 选 HEMATITE 完全可以，但当前 `catalog_binding.entity_bindings.apsis → HEMATITE` 与真实目录既有 `apsis → APSIS → APOGEE` 不同。改为明确的新实例映射、去掉不用的旧命名实体绑定或说明场景覆盖策略；不恢复超预算旗舰，不要求必须选 FERRY。
2. **自由编制与预设的关系写明**：两套合法范例不证明产品只能二选一，但 briefing 写“FORM-SENSOR 或 FORM-STRIKE”、P2 写“从池中选择编制”，缺少自由组合规则。明确它们是推荐预设，补舰池数量/重复选取与自定义旗舰占位口径，使产品可审；此时不要求完成编辑器/部署 UI。
3. **终态表补贡献例外**：探针已实现 ally_only 完成移除 victory、加入 stalemate，贡献段也有推荐。只是 canonical `terminal_rules.victory` / 主文终态表仍写三目标全完成直接 victory，stalemate 表仅时限1–2目标。将已采用的提案例外写入同一规则，保持“待用户核对”，不再说逻辑完全未处理。
4. **完整文案样例**：简报已有具体任务/预算/时限信息，战报 `sections` 仍是“各目标终态与判定依据、次数与效果、延迟”等占位提纲。至少给一份与某条轨迹一致的具体简报/结算文本，标明虚构样例，包含友军可拒绝、真实玩家/友军贡献、延迟报告和终态理由。无需建设 B3 运行层。

Luna 收窄后的逐项记录见 `p0_findings.md`。本轮不另开新卡，不要求重做已合法的两套编制或无武装友军方案。

## 5. 回归与证据

根审独立运行 **87 = 80 PASS / 7 FAIL / 0 TIMEOUT / 0 NOT RUN，退出 0，412.1 s**；known_fail=7、new_fail=0、drift=0、unverified=0、unselected=0、complete=true。7 项 FAIL 保留为历史失败，没有改名为 PASS。场景探针 247/0、合同 78/0、sensor-state 37/0；它们通过不抵消本报告新增载荷检出的同范围残项。

统一入口命令（完整运行结果见 `results.json` 与 `evidence/full/summary.json`）：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Baseline game_v17/tests/known_baseline_failures.json -Ci -ResultsDir .test-results/sol-r7/full
```

候选精确 head 的 GitHub Actions `40311846698` 三项 Phase0 / PhaseA / full 均 success；CI 状态与主审新反例分开记录。未刷新 7 项历史失败 baseline，未把它们改名 PASS。

证据归档路径与 SHA256 在 `manifest.json`；保存完整矩阵 summary/report、全部7项失败和本轮相关专项/正式入口的原始输出。stdout/stderr 以 `.txt` 保存以避开仓库 `*.log` 忽略规则。诊断脚本中的旧临时绝对路径只用于说明原运行来源，重放时应改为当前项目/输出路径。四规模原测量文件仍引用 PR65 候选内的作者归档，本次不冒充独立长测。

## 6. 下一轮执行边界

- #56 仅 G0-1～4：null 类型拒绝、partial 公共报告、满载新增输出比较、实际日志归档；保留上表已通过修复。
- #57 归一冻结合同与校验/声明，保留已通过的 actor/shooter/owner/部署链。
- #63 仅补映射、自由编制与预设关系、终态表及一份具体文案样例，然后交用户核对一套自洽提案。
- 不提前实现 A01/EW/逐舰 AI 大功能；#45–#53 的历史失败、性能、跨平台、真实渲染/物理和 >1000 tick 任务范围保持原卡。
- 下一次以新 40 位候选 SHA 重跑这些剩余反例；根据生产/测试改动范围执行必要回归，避免把每次局部修复变成重复整项返工。
