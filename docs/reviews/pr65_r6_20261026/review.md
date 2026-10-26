# PR #65 R6独立复核：已关闭项与剩余返修

日期：2026-10-26，Asia/Shanghai。精确被审提交：**`5d7208b82ebae81da874e059c2d88286317c6483`**；上轮`dc3821eda91d25f14e44dd9f57e6f5a985e04a9c`；main仍为`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`。需求56 R2的SHA256未变。审查：Sol，独立分项复核覆盖持久化、K0与P0；本轮只改验证资料，生产代码由DeepSeek负责。

**结论：返修有实质进展，但G0/K0尚有原要求内的残项，P0尚未归一，#65暂不合并。继续原#56/#57/#63，不新开整批任务；以下“已关闭”不得再次要求重做。**

## 1. 本轮独立确认的已关闭项

| 项目 | 独立结果 |
| --- | --- |
| 11专项 | **11/11 PASS**，0 FAIL/TIMEOUT/NOT RUN，62.8s含23.4s导入；新sensor28/0、K0 64/0、P0 190/0 |
| 动态指向G1 | 原0.003°/s移动目标继续150tick，原始/恢复均locked，目标ID一致，完整模型状态相同；原第123tick失锁反例关闭 |
| 原聚合半写与字段校验 | 原八反例退出0、violations=0；坏optical/TWS/authority元数据均拒绝且保持状态；版本999、溢出、负计时、角度越界和缺radar原反例已关闭 |
| G3部分 | 事件payload替换、观测quality 1→0、在途正文篡改已能被即刻状态比较发现，保留该修复 |
| K0主要旧反例 | player actor冒用ally controller、未选舰留部署、缺request/冲突key、跨舰roster、未知owner/observer/错误delay已拒绝；连续燃料3000.5kg合法，INF/超安全整数/缺fuel拒绝，数值组关闭 |
| K0方案 | 已选每owner独立TrackTable，已有AI只读策略/生命周期/legacy scope的补充；不要求本卡提前实现A01、AI或B1 |
| P0三条变异 | 未知舰级、超容量、删除失能却胜利均正确拒绝，各退出1、189PASS/1FAIL，原漏检关闭 |

专项原始结果见[evidence/targeted-summary.json](evidence/targeted-summary.json)；其余见[evidence/](evidence/)。精确head的[CI run40225575811](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40225575811)三个job成功。完整87=80/7与四规模90/0为作者结果，本轮未独立重跑full或完整四规模。

P0三条变异是**故意制造非法输入**再运行同一校验probe，预期触发一条断言FAIL并退出1；这表示拒绝成功，不是正常fixture的回归（正常fixture为190/0）。后述同tick对照则应按提案自己的优先级判defeat，其退出1表示校验与声明矛盾，二者不能混为一谈。

## 2. #56 / G0剩余项

### A. 畸形TWS通道组只修了空对象反例

[tws.gd:570–610](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/framework/sim/tws.gd#L570)只要求target_id/state/quality/last_update_t。以下满足当前全部校验，validate/import均成功：

```json
{"target_id":"broken","state":"STARE","quality":1,"last_update_t":0}
```

下一次step却在[tws.gd:339](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/framework/sim/tws.gd#L339)因缺`stare_s`产生SCRIPT ERROR。证据：[STARE脚本](evidence/save/stare_channel_audit.gd)、[日志](evidence/save/stare_channel_audit.log)，退出1。需按FSM实际消费的状态字段完整校验类型/范围和关联，先拒绝再提交；不能只验证上次缺last_update_t的那一个载荷。原八反例已关闭，不改动已正确的两阶段提交路线。

### B. 比较器还有两个原G3缺口

1. [a0_save_cost_probe.gd:438–444](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/tests/a0_save_cost_probe.gd#L438)只查`bus._id_seq is int`，未比较值。旧quick把220改320仍得到`violations=[]`；因此quick本轮仍退出1、review_defects=1。应补分配器值与未来自动ID续写的有意义对照。
2. `_comms_event_sigs`虽新增，但没有调用点；[行为检查:634–640](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/tests/a0_save_cost_probe.gd#L634)仍查询不存在的`last_event()`。在途正文篡改现在已被即刻状态发现，但继续10tick与最终状态检查仍为`[]`，实际DELIVERED正文已变。需让通信事件流和逐tick输出真正参与比较；不要求重做已接入的pending正文比较。

证据：[quick.log](evidence/quick.log)、[脚本](evidence/review65_probe.gd)。注意将“篡改已被即刻比较检出”与“后续交付仍没比较”分开，不能把前者重新列成未修。

### C. 旧v1兼容需明确迁移/版本策略

本轮用C55精确源码实际生成一份合法save；**C55自行往返成功**，同一文件交R6则因缺TWS/authority元数据失败。四组件仍是v1，无sensor迁移/partial分支；`dc3821e`旧角度格式虽然可过，缺目标/模式仍落默认值。

证据：[旧文件](evidence/c55_valid_save.json)、[C55导出/自读日志](evidence/legacy_export.log)、[R6读档日志](evidence/legacy_import.log)、[两个脚本](evidence/legacy_export.gd)。明确支持矩阵：能重建的做版本化迁移；不能完全恢复的如实标部分恢复或明确不支持的旧版本及原因。不能把同v1的合法旧数据无说明当损坏，也不能以默认空目标声称完整恢复。这是原卡旧档要求，不要求凭空重建旧文件未记录的历史。

### D. R6长测原始证据尚未归档到本PR

R6报告写本轮90/0、724s、测量代码f687ba1；PR正文又写4fa9696。仓库`docs/benchmarks/jc_r2/a00_g0_measurements.json`仍标**eaf953286fe388f1013d0ef7cd2062ab535016b8**，是上轮数据，不能证明这轮修复后的12样本。请保留旧数据并另外归档本轮原始summary/日志/JSON/CSV，列确切40位代码SHA及最终候选关系。补齐A–C后，再取得同一代码版本的最终证据；本轮不否认作者可能在本地已运行，只是不把旧文件当本轮证明。

## 3. #57 / K0剩余项

K0是合同层，本轮错误接受不等于已证明生产游戏发生越权。已修数值/actor名单/选择映射等不再返工。仍需：

| 项 | 当前反例与位置 | 收尾要求 |
| --- | --- | --- |
| fire发射者资格 | [jc_contracts.gd:375–384](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/scripts/core/jc_contracts.gd#L375)：I-A2设未选/DRAFT、移除其部署记录，再作为同域fire shooter仍ok | 区分已登记实例与实际参战/可受令实例；补未选、未部署拒绝 |
| 共享来源与接收授权 | [:301–319](https://github.com/HATO-24/ghost-track-apsis/blob/5d7208b82ebae81da874e059c2d88286317c6483/game_v17/scripts/core/jc_contracts.gd#L301)：observer改敌方I-OP1，仍自报player_intel并由player_intel授权，校验通过 | 固定原始owner、接收owner、共享grant/path的关系；给盟军合法延迟共享和接收方自我授权敌观测的负例，不只是字符串存在 |
| 部署记录一致性 | :254–274：t=-5或实例DEPLOYED但记录DRAFT→VALIDATED仍通过 | 按文档校验有限非负时间、当前状态与记录用途；若是历史而非最终部署记录，应明确字段语义 |
| 标识与冻结接口 | 删除command_id仍通过；event_lifecycle仍只是六字符串 | 拒绝缺命令ID；补事件ID/seq、请求/回执/执行记录版本与关联及legacy fixture，无需实现完整AI/通信 |

证据：[K0完整窄复核](evidence/k0/findings.md)、[变异脚本](evidence/k0/mutations.gd)、[JSON](evidence/k0/mutations.json)。原10个缺陷/正例对照已符合预期；6个残留变体仍接受。其中legacy自报第二舰为own的结果只用于要求定义可信ownship锚点，不擅自把“用户选择哪舰作旗舰”的产品提案判成错误。

## 4. #63 / P0尚需归一的内容

这是提案内部一致性，不要求现在实现B1–B3。canonical舰级、原三变异、机制依赖/替代说明已有进步，予以保留。

- **旗舰与预算冲突**：JSON指定APOGEE作旗舰；目录9000t，按本提案公式9000/60=150点，超过预算100；两套编制25/55点都不含它，保护对象却仍绑定I-A1旗舰。明确旗舰是否额外部署、是否计预算/容量，或改成在合法编制内选择旗舰，并提供两套完整合法实例映射。
- **友军能力不支持回执**：PALLET＋SAFEHARBOR的真实目录均`weapons=[]`，回执却仍写射击位、拦截和火控失能。改成可承担的侦察/中继/撤离支援，或提出含武装舰的阵容；不以文本假装已执行。
- **旧正文与新追加方案冲突**：Markdown §1–12仍保留旧舰名、62/70点和旧结算口径，§13才追加新方案。重写为一份当前主案，旧方案放显式历史附录；用户不必自行判断哪段有效。
- **同tick规则与校验不一致**：声明defeat>victory>withdrawal，但probe先判defeat后被withdraw_complete覆盖。仅在TR-CIVILIAN-LOSS加入同tick撤离完成、保持expected=defeat，结果189/1失败（actual=defeat / validator expected=withdrawal）。修复规格校验的冲突优先级并保留此轨迹，非新建B3运行层。
- **双视图、贡献、简报战报仍需完整主案**：补“全部目标已失能但报告未回”的真实双视图样例；目标真实完成与玩家贡献分开，给AI自主完成后的一个明确推荐口径；补完整简报/战报样例。保持其为待用户核对的具体提案，不把未获批数字当正典。

证据：[P0三变异摘要](evidence/p0/mutation_summary.json)、[同tick反例](evidence/p0/terminal_priority.log)。两个友军武器列表、旗舰质量与类ID均直接核过`ships_friendly.json`；不能只用自建点数表自证。修成一致方案后，再核对用户尚未决定的舰池/预算/目标阈值/时限等；已确认的阶段性行动与自有直控＋友军请求不重问。

## 5. 下一步仍用原卡与原预算

1. **#56**只补TWS完整状态校验、比较器剩余调用/allocator、旧档策略及本轮可归档证据；已关闭项保留绿证据。修复完成后同一代码SHA四规模正确性与C回归，旧7失败按原baseline逐项核对，真实新缺陷不得登记为历史。
2. **#57**只补表中资格/共享授权/记录语义/标识与接口冻结；不要重做已正确的数值和actor检查。K0通过前#58核心实现仍未解锁。
3. **#63**归一当前主案、部署/预算/能力、终态/双视图和完整文案，再交用户核对。不要为修提案提前开发运行态AI/战役裁决。

#49的固定旧负载预算仍为1,500,000 UTF-8 B / 保存250ms / 构造＋恢复5000ms / 读盘50ms；作者报告仍未达体积/保存/恢复，继续#49。**性能优化不额外变成G0冻结前提，本轮暂缓来自上述正确性和验收残项。** 不修改生产代码、不合并PR，不动主工作区资产/HUD未提交内容。

## 6. 复现与证据口径

Godot`4.7.2.stable.official.ed1daf0bf`，Windows；归档脚本在被审SHA的独立副本执行，承载报告的#64分支只是文档材料。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(core_time_event|track_table_probe|a0_(event_continuity|legacy_save|sensor_persistence|comms_restore|integration_authority|save_roundtrip_authority)|jc_contracts|jc_scenario_spec|jc_a00_sensor_state)' -Ci -ResultsDir .test-results/sol-r6/targeted
```

专项断言依次197/161/28/190/64/59/86/60/89/65/41，11/11、退出0。移动目标150tick退出0；旧八反例退出0；quick退出1只剩allocator反例；STARE退出1且真实SCRIPT ERROR；K0窄诊断退出0仅表示脚本正常完成，需看错误变体是否拒绝；P0三个旧错误变体退出1是正确拒绝；新同tick对照退出1说明校验规则矛盾。

旧档对照：`legacy_export.gd`在C55代码根目录运行，写`R6_LEGACY_OUT`并在C55自行读取（退出0）；同一文件再在R6运行`legacy_import.gd`（退出1）。其余脚本通过`godot --headless --path ./game_v17 --script <绝对路径>`复现；quick需`SOL65_MODE=quick`、`A07_HEAD`为实际HEAD，移动目标设置`R5_POINTING_OUT`。各子目录保留执行元数据及原始stdout/stderr。未独立跑full/完整四规模/跨平台/渲染/战役试玩，不复制其历史PASS作为本轮结果。
