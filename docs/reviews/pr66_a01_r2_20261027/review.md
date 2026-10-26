# PR #66 第二轮独立复核：保留修复、收窄剩余（2026-10-27）

被审 `61f27fc8e841666705b5fd2e843824a03bf6c0b8`（实现 `3163795d97e495a8dd43efcf49823595779fb989`，后续只加进展文档）；base/main仍为 `3045311657609dfe10a133802b93dde2fc8abb79`。Windows、Godot `4.7.2.stable.official.ed1daf0bf`。运行跨越10月26/27日，原日志时间保留。

**结论：这是明确标为“未完成，需继续”的进度候选。继续原 #58，#66不合并、A1不冻结、#59–#62按原依赖等待。** 上轮许多重要反例已关闭，下表作为本轮交接依据，不能继续整项要求返工。G0/K0和已有main合并结论不变。

## 1. 已独立关闭的反例

| 原项 | 本轮结果 |
|---|---|
| 敌方actor、错误controller/fleet仍真实发射 | 原十组对照中对应输入均拒绝，8→8弹、0弹体/成功事件，CLOSED |
| legacy无shooter抹去显式敌actor | 正确拒绝，无副作用，CLOSED |
| 第二舰仅bool运行态借旗舰账本 | 仍无真实逐舰运行态时返回unavailable，无副作用，CLOSED |
| 正常有限资源本舰正例 | 主审原合法夹具正常TIGHT、真实FIRE授权，8→7、1弹体、1成功事件，通过 |
| 操作/返回/审计缺context | 实际成功日志、返回、审计现带actor/controller/domain/fleet/shooter/t；静态重放也不再仅传salvo。字段缺失反例CLOSED，动态文件重放仍随最终验收验证 |
| 真实HUD空情报回退物理真值 | 正式main_menu→v1_hud，隐藏实体真实物理移动后HUD仍为空/intel且不变，CLOSED |
| 盟军未共享观测进入玩家contacts | 合法盟军sensor output经实际路由，ally有1条、player0、contacts0，列表泄漏窄项CLOSED |
| 真正旧基线航迹没有迁入player | 上轮实际旧来源文件加载成功，T0001迁player=1、ally=0，CLOSED |
| 坏新段字符串被当旧档 | broken拒绝、模式failed；version999继续拒绝，CLOSED |
| authority恢复模式不公开 | load及report公开legacy_own_ship_only与迁移条数/原因，CLOSED |

发射证据 `evidence/fire/`，情报证据 `evidence/intel/`，存档证据 `evidence/save/`。发射组十例明确为1个成功控制＋9个安全拒绝；不因交付新probe的错误正例而重开这些已验证修复。

## 2. 实际测试结果，不能只看绿色job

| 运行 | 独立结果 |
|---|---|
| 5项基础专项（含import） | 4 PASS / 1 FAIL，退出1；a0_integration_authority从65/0变为64/1，缺HUD可追溯contact；其余TrackTable161/0、K0 84/0、事件89/0、save41/0 |
| Phase 0 | 4/6 PASS，退出1；E2E152/1，full boot虽exit0、3/0但有真实SCRIPT ERROR，正确计FAIL |
| Phase A | 1/3 PASS，退出1；track_truth44/1、metadata_pipeline29/1，save41/0 |
| 直接执行未注册的新A01 probe | **45 PASS / 12 FAIL、退出1**；实际reason为no_ready_solution、共享回调异常及错误旧档夹具等 |

作者进展报告写43/13及needs_authorization，和本轮实际45/12、no_ready_solution不同；报告应更新为真实最终环境/结果，而不是沿用旧描述。主审未重跑整套长时full，已保存必要专项、两门禁、直接probe和独立反例。

候选 [Actions 40352405076](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40352405076) 的full job显示success，但其原始日志实际为 **87=71 PASS/16 FAIL，known_fail=7、new_fail=9、drift=0、complete=false，runner输出BASELINE CHECK FAILED**。它不是87项无新增回归。日志运行于PR合并ref `5031e361…`，与主审候选直接运行分别记录，不冒充同一SHA。

`.github/workflows/tests.yml:511–513` 在调用runner后直接打印/exit `$code`，没有将 `$LASTEXITCODE` 赋给它，因此full失败未传成job失败；后面的baseline selftest24/0也不能代替full结果。该包装缺陷从base继承，本轮未修改workflow，不把它说成作者故意移除门禁。修复退出码传递属于本卡最终验收证据收尾；不用改游戏断言或历史baseline。

新A01 probe已从 `probe_matrix.json` 删除，矩阵从88退到87。红例应注册并保持红，不能靠移除任务验收用例让CI看不到未完成行为。最终恢复稳定ID `integration.jc_authority_intel`，保留既有7项失败、禁止把这9项新增登记为历史。

## 3. 剩余A：原R3的selected、融合与生命周期读取尚未闭环

列表/空绘图修复保留。但同一条合法盟军未共享观测仍在全局TrackTable生成T0001，`shell_binder.gd:975–980` 的 `selected_track` 继续读取全局 `track_vm`：player owner=0、contacts=0时，直接selected(T0001)仍读到盟军私有 `range=456`、entity和证据。

owner仍是普通字典，尚未完成按已冻结K0的每owner融合/衰减/选择状态及消费者迁移。**只收拢原剩余selected/详情/可见导出与融合生命周期**，不重做已关闭的contacts/plot，不删除内部物理/系统真值接口，不新增完整AI。

## 4. 剩余B：原R4实际到达回调报错，幂等和在途恢复需在真实成功投递后验证

主审直接新probe已走 `queue_intel_share`；发出后未到达不可见的断言通过，但到达时 `_reconcile_standalone` 在 `game_session.gd:2779` 调用处出现 **SCRIPT ERROR: Invalid call 'String' constructor: COMMS_SENT**，`last_intel_share_result()`仍空，接收owner没有target_b。存在函数/调用点尚不等于正确接入。

按现有Comms真实事件的kind/delivery_id/t及实际到达时刻完成一次融合，处理类型错误；以正常的已投递共享为起点，再检查相同幂等键重投不增长、第三方不可见、在途文件恢复继续10tick。当前“重复投递增长1”发生在首次实际回调没有成功之后，**不单凭这个计数另认定一种新的去重根因**。保留来源/时间等已修拒绝路径；不提前实现EW或完整AI协同协议。

## 5. 剩余C：原R5显式null仍混同真正缺段旧档

真实缺段旧来源、字符串broken、version999和公开模式均通过。仅新档显式 `authority_intel:null` 仍ok=true、legacy_own_ship_only。`game_session.gd` 的畸形判断要求 `ai_state != null`；应以字段是否存在及新格式段合同区分缺段旧档和坏新段。保留失败模式与原因，补null负例，不需要全系统加载原子性重构。

## 6. 剩余D：修正新probe夹具与因owner消费变化暴露的集成回归

### 新probe的真实发射正例

主审原有限8枚导弹夹具可真实成功，说明生产授权链的这些原反例已关闭；新probe用railgun/当前解算未READY而返回no_ready_solution，库存读取也仍为默认/错误表。请复用已证实的正常ROE、真实FIRE grant、有效武器/READY解算、实际库存控制，随后验证规范化context及重放。不要关闭ROE或用“没有权限错误”替代真实成功。

### 所谓“真正旧档”失败来自当前候选造出的不同时刻夹具

`jc_authority_intel_probe.gd:370–391` 在session还为0时手工给全局TrackTable写t=1观测，再推进tick；日志明确TrackTable2/session1、3/session2并返回contract_violation。随后保存当前候选状态、删除新段，称为“真正旧来源”。它不能替代实际旧版本导出文件的兼容对照，后者本轮已成功加载。

修夹具时刻/生成顺序，先证明源会话tick均ok、源自读成功，再验证迁移和继续。**不采用进展文档中“只迁航迹、不重放旧tick”来绕过连续模拟合同**；不要把坏夹具作为合法旧档损坏的证明。

### 真实门禁回归需逐项修复或等强度契约对齐

- full boot：`v1_hud.gd:723 _select_preserving` 对空contacts取index0导致真实越界；空/未知情报是合法输入，需正确处理。
- E2E：目标未进入实际玩家contacts；a0_integration_authority缺contact的source/frame/t可追溯记录。将合法已到达的owner证据接到真实操作/显示，不依赖旧全局注入。
- 旧metadata probe仍要求“全部7场景实体都有contact”，新owner隔离下要区分内部全7实体元数据验证和玩家已知子集。给出断言映射与等强度负例，保留来源/匿名性/隐藏实体不出现的验证；不能为让旧测试绿恢复物理真值fallback，也不能直接删掉来源/非空正例。

## 7. 下一次交付条件（继续原 #58）

1. 保留第1节关闭项；只完成selected/融合剩余、共享回调及成功后的幂等/在途继续、present-null、probe与必要门禁消费适配。
2. 完成有效红/绿夹具，恢复A01 probe注册；修继承的full-job退出码传递，job必须反映runner真实失败。
3. 原卡专项＋Phase0/PhaseA＋完整strict baseline回归，源码/报告/CI对齐最终40位SHA；更新PR body仍指向1d1e8399/31/0的旧摘要。
4. 逐项报告既有7项、真实新增失败和合法契约调整，不刷新baseline、不跳过旧log重放、不通过删除测试凑绿。

PR66保持open待返修；A1不冻结，不开新的功能卡。Sol只写诊断/复核/原卡更新，主要生产代码继续交DeepSeek，Luna辅助旧档核对。证据清单与SHA256见 `manifest.json`；前一轮报告及44份材料保持原样。
