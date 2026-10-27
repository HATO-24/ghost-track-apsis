# PR #66 / JC-A01 独立复核与原 #58 返修（2026-10-26）

候选 `1d1e8399da438b77b74acee40d753711c8d2a8f9`；base/main `3045311657609dfe10a133802b93dde2fc8abb79`；Godot `4.7.2.stable.official.ed1daf0bf`、Windows。依据仍是56 R2及现有JC-A01八段卡，未改产品范围。

**结论：#58 尚未完成，PR #66 暂缓合并，A1不冻结，#59–#62保持原依赖等待。** G0/K0已完成的结论保留。问题集中在本卡原定的真实授权、每owner消费链、共享到达与恢复；不要求提前实现完整AI、EW或B1b逐舰账本。

## 1. 先保留通过的部分

- 原显式未知shooter、敌方shooter、盟军直接命令、无运行态的其他本方舰，实际均拒绝；有限弹药8→8、0弹体、0成功事件。
- 真实合法本舰正对照能发射：正常TIGHT、有FIRE授权、有限8弹，射击后8→7、1弹体、1个 `combat.weapon_launch`。审查没有以无限资源/自动授权替代验收。
- 新owner字典的直接读写能把不同owner的记录分开，未知owner输入拒绝；这层容器本身的修复保留，但尚未隔离旧实际消费者。
- 有效新段的真实文件写入、关闭、读取、加载后，三owner视图保存且继续10tick一致。仅证明所测已收记录的同实现序列化，不冒充在途共享已验证。
- `version=999` 已明确拒绝；正常格式往返无需重做。

## 2. 运行结果及其边界

根代理独立专项 **8/8 PASS，0 TIMEOUT/NOT RUN，退出0，46.8s（含22.2s统一import）**：fleet511/0、TrackTable161/0、A01新probe31/0、K0合同84/0、事件89/0、物理/信息authority65/0、track-truth45/0、save41/0。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_authority_intel|track_table_probe|fleet_probe|a0_(track_truth|event_continuity|integration_authority|save_roundtrip)|jc_contracts)' -Ci -ResultsDir .test-results/sol-a01/targeted
```

候选精确head的 [Actions 40343442634](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40343442634) 三项Phase0/PhaseA/full均success；作者full报告 **88=81 PASS/7历史FAIL，baseline匹配**。本轮根代理没有再次运行完整88项或长测：已用下面独立反例证明原卡未完成，不将作者full写作主审独立全量，也不把新反例加入历史baseline。

独立诊断中的退出0有两种含义：发射/情报脚本代表“诊断完成、反例已复现”，需看实际接受/耗弹/可见数据；不能写成业务验收通过。隐藏真值钩子与真正旧档迁移的根诊断以退出1标出缺陷。既有退出清理stderr保留，没有声称零stderr。

## 3. R1：真实发射授权必须使用请求来源及真实运行态（P1）

### R1a 请求的actor/controller/fleet未参与授权

`authority_intel.gd:119–158` 只读取shooter，未使用setup保存的 `authorized_actors`，也未核对请求actor/controller/fleet。返回的controller由shooter所属域重新填写，不能证明请求来源合法；legacy缺shooter分支同样忽略显式非法actor。

独立真实发射对照仅改一项：actor=`opfor_ai`、controller=`opfor_ai`、fleet=`enemy_fleet`，或无shooter却带敌方actor，四例均 `authorize_fire.ok=true`，实际 `request_fire.ok=true`，8→7弹、1弹体、1成功事件。

**最小收尾**：来源context→actor名单→controller/域→fleet/shooter关系进入真实入口，且在资源/排弹/成功事件之前拒绝；真正无context的旧调用才绑定可信本舰，不能把显式非法context抹成legacy。无锚点纯服务测试的deferred兼容未被证明越权，不要求一概改为拒绝。

### R1b 配置bool不能代替真实逐舰运行态

`authority_intel.gd:108–110,153` 允许 `own_fleet[].combat_runtime=true` 自证可用。仅增加第二本方舰物理实体/登记，并把该bool设true，会从 `second_own` 实际发射，却扣唯一 `combat_service.own_id=session_ship` 的8→7弹，launch_spec仍指旗舰。false正对照则unavailable、无副作用。

**最小收尾**：没有绑定真正逐舰战斗运行态时保持 `shooter_runtime_unavailable`，不能借旗舰账本。此时不要求实现B1b；保留正常本舰和已修拒绝分支。证据：`evidence/fire/fire_context_audit.{gd,json,txt}`、`findings.md`。

## 4. R2：规范化授权context必须进入日志、事件/审计与重放（P2）

`game_session.gd:2967–2968` 的已成功操作仍仅记录op/target/weapon/confirmed/salvo；`5472–5477` 重放只传salvo，回到无shooter的本舰legacy路径。审计 `5716–5727` 也缺actor/fleet及原请求controller，因此敌方actor与正常请求的成功审计无法区分来源。

**最小收尾**：保存并使用同一份规范化授权context，包含actor/controller/fleet/shooter、模拟时刻及legacy来源；重放按其版本恢复同样语义。补内存/文件恢复、10tick后context与资源/事件对照，不仅比较返回值里重填的controller。本证据证明context丢失，不声称所有load都会失败。原发射组同一证据可复现。

## 5. R3：owner隔离必须覆盖实际融合及玩家读路径（P1）

### R3a 空情报绘图仍回退到物理真值

`shell_binder.gd:1514–1569` 只有owner positions非空才返回安全facade，否则继续枚举PhysicsWorld，之后还有snapshot实体fallback。正式sensor路由只给owner range/bearing、不带pos_km，所以空位置不是异常边界。

真实 `main_menu→v1_hud→Binder`：owner已有2条航迹而positions空，HUD却返回source=physics和7实体；隐藏 `raider_2` 不在owner情报。通过真实 `PhysicsWorld.upsert_entity` 仅将它移动 `[+1234,+77,+9]km`，owner视图/facade不变，玩家绘图立即跟随隐藏真值变化。

### R3b 新owner副本之外，旧全局融合/列表继续混流

`game_session.gd:1506–1524` 写owner字典后仍无条件 `track_table.handle_observation`；`shell_binder.gd:568,911–916` 刷新/selected仍读全局VM。

将一条合法盟军sensor事件投到真实sensor outbox，走 `_advance_sensors(0.0)`，未直接写玩家view/TrackTable：ally owner有1条，player owner为空；但全局生成 `T0001`，Binder玩家contacts显示 `ally_private_contact` 的range456km。尚无共享投递也能看见盟军独有观测。

**最小收尾**：按K0完成每owner融合/衰减/selected状态与对应读取facade；HUD/list/selected/plot/玩家可见导出都走它。无情报返回空/未知，不从全量PhysicsWorld或snapshot补齐；不能为填绘图位置读取隐藏目标真值。内部物理/弹道与明确系统诊断的真值接口保留，不要求删除它们。不要同时维护“表面隔离字典”和“对外全局融合”两套事实。证据：`evidence/intel/hud_truth_audit.*`、`owner_boundary_audit.*`。

## 6. R4：基本共享必须经授权与实际到达，再融合（P1/P2）

公共 `receive_intel_observation` 直接转交 `authority_intel.gd:194–218`，只查owner存在便append/upsert；`owner_of_entity:181–184` 对未知observer还默认player。

独立反例：敌方observer、path=direct、无授权便能写player；now=0却标received_t=30即刻可见；observed_t=99/received_t=1/delay=-98照收；相同observation_id重复投递使流再增长。合法本舰direct和未知owner拒绝正对照仍通过。

**最小收尾**：明确可信已投递写者，检查注册observer原始owner、合法共享授权/接收owner、实际到达时刻、有限非负且一致/单调的时间、幂等键；未知来源不能默认本方。至少一条基本共享走既有消息/投递链，保留发出→未到达不可见→到达只接收方融合→重投幂等的证据。未来EW效果、AI协同请求协议留后续；不能把本卡原有共享到达门整体顺延到A03/A04。

## 7. R5：旧档迁移、坏新段拒绝与公开恢复信息（P2）

- **真正旧来源对照**：根代理用R8 `9d0f3b4…` 代码（game_v17 tree与执行基线3045311完全相同）实际导出含一条TrackTable航迹的文件，并在来源代码自读成功。候选加载同文件也ok、旧全局表保留 `T0001`，但player/ally owner视图都空。并非只用删字段新档冒充旧来源。缺新段时应把旧单舰航迹迁入可信本舰owner，不复制给盟军。
- **坏新段静默降级**：合法新档把 `authority_intel` 改成字符串 `broken`，`game_session.gd:5174–5182` 将非对象强制变 `{}`，`authority_intel.gd:272–276` 又按旧档接受，最终ok=true、各owner空。version999正确拒绝，应保留；真正缺段与已存在但畸形的新段需区分。
- **公开恢复模式**：计算的 `ai_res.restore_mode` 未进入load返回/恢复报告，调用者无法区分完整恢复与authority旧档迁移。沿既有恢复元数据披露，不污染规范化snapshot。

**最小收尾**：实际旧域迁移、坏新段明确失败、恢复标签可读；覆盖新格式及真正旧来源的内存＋文件往返。无需整套GameSession原子加载重构或承诺全部原型版本。证据：`evidence/save/`（Luna的同实现文件对照/损坏输入）及 `evidence/qa/baseline_legacy_*`（真实基线生成、自读、候选导入）。

## 8. R6：将独立反例变成实际消费者验收，修掉空洞正例

`game_session.gd:5771–5788` 新加的 `_apply_hidden_truth_mutation` 没有实际改动所测真值：PhysicsWorld没有 `set_position` 方法；`world.entity()` 返回deep copy。根诊断显示钩子报 `moved_surfaces=1`，物理和world原始坐标/名称前后却完全一致。因此现有“变更后玩家视图不变”不能证明隔离。

交付的 `jc_authority_intel_probe.gd` 对“合法发射”只断言“不因授权原因拒绝”，下游unknown_weapon/无物理目标也能通过；资源只比projectile/不存在state方法的默认计数，不是实际库存。这是该probe的验收缺口；第1节主审另跑的真正成功发射正对照仍保留。该probe的共享样例直接插入未来received_t记录，没有真实投递；恢复主probe只内存比较player。

**最小收尾**：先断言真实被测隐藏值确已改变，再比较真正Binder/HUD消费者；正常有限资源射击必须成功耗一弹，并用实际库存/弹体/成功事件证明拒绝零副作用；实际共享链、各owner融合/读取、真实文件与在途共享恢复继续至少10tick。使用现有合法测试入口，不为测试新增大套生产setter。保留当前绿项，红probe→最小实现→证据分开提交；最终源码/命令/报告对齐同一40位SHA。

## 9. 交付要求与后续依赖

继续原 #58，不开重复卡。允许范围仍是授权服务/入口、owner融合与玩家读取、操作/事件context、共享基础投递、恢复及相应probe；先合服务边界再改GameSession，避免两套并行事实源。修复后执行本卡专项与既定C回归，逐项列旧失败、计数漂移、新失败，不能刷新baseline掩盖问题。

PR #66保持open待返修；#59不解锁。#63的内容校正及#49性能继续原范围。Sol只编写复核/任务文档与诊断，主要生产代码仍交DeepSeek；Luna辅助存档核验。证据文件SHA256见 `manifest.json`。
