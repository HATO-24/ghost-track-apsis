# PR66 / JC-A01 第三轮独立复核

日期：2026-10-27（Asia/Shanghai）。结论：**RETURNED，继续原[#58](https://github.com/HATO-24/ghost-track-apsis/issues/58)，PR66暂缓合并、A1未冻结。** 已修项保留；只完成原卡情报生命周期、在途恢复、实际显示与等强度测试适配，不增加AI/EW/逐舰账本范围。

## 1. 被审版本与证据来源

| 项目 | 实际值 |
|---|---|
| PR66 head，根代理本地运行 | `8b4cf990021bafe0f5b2945039c850b5c985cf5a` |
| main / PR base | `3045311657609dfe10a133802b93dde2fc8abb79` |
| CI检查关联head | 同上8b4cf990；[Actions run 40360314445](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40360314445) |
| CI实际checkout | `1196fdb14483dbcf3c1e19095d26e0b68b00053d`，日志明确为8b4cf990合入3045311的PR合成merge；不是本地运行SHA |
| 本地环境 | Windows，Godot `4.7.2.stable.official.ed1daf0bf` |
| 产品/合同 | 56 R2、原#58、K0 §8.2 `per_owner_track_table`；G0/K0既有完成结论不变 |

根代理统一导入并运行5项；分项审查复用其日志，另执行旧发射十组、selected/老化、共享连续性诊断。未修改生产代码、正式probe、baseline或测试矩阵。只归档诊断及本轮规划文档。导入生成的`.import`/`.uid`不纳入文档提交。

## 2. 本轮关闭项，不再整项返工

| 原问题 | 本轮证据与保留结论 |
|---|---|
| R1请求来源、伪runtime借旗舰账本 | [原十组发射](fire/results.json)退出0：正常TIGHT＋实际FIRE grant＋有限8弹，库存8→7、1弹体、1成功事件；9个非法来源/运行态均8→8、0弹体/成功事件 |
| R2 context字段 | 已有成功操作/日志/审计字段保留；最终验收仍按原卡核对真实文件和重放，不重开已修字段工作 |
| R3 selected/实体详情跨owner | [实际selected对照](intel/owner_lifecycle_audit.json)：全局盟军T0001存在，player无观测时selected_track/selected_entity均空；本方合法观测正例range111可读。此前contacts/空plot不回退真值的修复保留 |
| R4正常投递、幂等 | [实际共享对照](intel/share_continue_audit.json)：t2发、ETA5，连续会话t3/4不可见、t5到达后可见；第三owner空；同键重投1→1，duplicate=true。callback类型异常已修 |
| R5 present-null / 旧档 | 新probe63/0包含显式null拒绝；此前真正旧来源迁player不迁盟军、broken/999拒绝与公开恢复模式结论保留，不整项重做 |
| R6探针与门禁 | 新A01探针恢复注册，63/0；空contacts选择越界已补；原合法发射/旧来源夹具已修；full workflow捕获并传递真实LASTEXITCODE，CI此次正确为failure。不能继续沿用上轮“绿job包装红结果”的现状描述 |

## 3. 三项实际缺口

### 3.1 原R3：owner航迹仍未老化

同一会话只接收t0一条合法观测，此后无新观测；两次真实tick至31s、301s均ok。全局TrackTable按现有30s stale/300s forget配置，在31s标旧、301s移除；player owner仍保留t0的range500/quality0.8，无stale标记，字段不变。

当前`authority_intel.gd`存普通字典，`GameSession._advance_components`只推进全局表；尚未等价运行原卡的每owner融合/衰减。要求的是可观察行为，不强制某个类名，也不新定30/300为产品阈值。按原合同明确owner策略，使融合、老化、忘却、选择/绘图和恢复一致；保留owner隔离与合法新观测更新正例。

证据：[分项说明与运行命令](intel/findings.md)、[生命周期原始结果](intel/owner_lifecycle_audit.json)。该脚本退出0只代表selected对照关闭，`owner_retained_after_forget=true`仍是未完成生命周期证据。

### 3.2 原R4 / 恢复：在途共享丢失实际队列，提前两秒可见

t2发送ETA5后立即save/load。保存前Comms.pending含1条、arrive_t=5；load成功、共享待融合索引恢复1条，但`restored.comms.pending=[]`。恢复后首tick到t3，`_reconcile_standalone`将“pending不存在”视作送达，提前融合；连续会话到t5才可见，received_t也分别为3和5。

恢复实际Comms在途状态/ETA及投递结果，不能将索引存在或队列项消失等同成功。按每tick比较可见集合、时间与输出，覆盖到达前save/load和继续至少原卡10tick；不得仅比较终点都有target。正常到达与去重已绿，集中修继续语义。

证据：[脚本](intel/share_continue_audit.gd)、[JSON](intel/share_continue_audit.json)、[log](intel/share_continue_audit.log)、[退出1](intel/share_continue_exit.txt)。`normal_arrival_closed=true`、`duplicate_closed=true`而`continuation_equal=false`。

### 3.3 原R3消费者：光学标签仍拼接内部ID

实际metadata probe中的两条红灯为：

```text
ENTITY/TRACK TRACK-001 · TRACK harmattan
ENTITY/TRACK TRACK-002 · TRACK l1_station
```

`v1_hud.gd:643–649`的`_optical_entity_line`先用匿名display_id，又拼接原track_id。真实可见界面和hud_target_texts均使用该函数。最小修正只改变玩家标签，内部稳定ID继续供操作路由；保留“实际文本不含未获真值”与“内部路由ID未改写”双重检查。不能允许这两个内部名或放宽truth检查换绿。

这是现有A01消费者缺陷，继续#58修，不等后续UI-01。详见[两probe契约映射](contracts/findings.md)及[metadata原日志](targeted/logs/integration.a1_entity_metadata_authority.log)。

## 4. 允许的旧probe适配及不可削弱项

两失败probe合计10条断言失败：metadata的7条中，4条旧source/display-ID等式、1条无观测signal注册应可见的假设需要更新，另2条是上述真实泄漏；world-sync的3条来自旧玩家plot读全量当前物理真值假设。**不能将两项probe全部称为纯测试问题。**

- metadata：精确验证`intel_view`、可信本舰owner、每行映射该owner获准观测及内容/时刻；显示ID匿名，内部ID仍稳定。signal注册本身不产生玩家contact/selected/plot，再用合法观测验证安全显示正例。隐藏真值须实际改变并先证明改变，玩家已知观测不变时视图不变。不能只放宽source取值或靠永远空列表跳过断言。
- world-sync：保留内部完整7实体和PhysicsWorld→WorldState单向权威、同刻精度（位置1e-9 km、速度1e-12 km/s、时间1e-6 s）、save/load和手写world自愈对照。玩家plot另与owner获准观测的位置/采样时间比较；无观测/盟军私有不可见，合法观测可见；隐藏physics移动而未新观测时plot不跟随，合法新观测后才更新。
- 逐项提交“旧断言→新契约→等强度正负例→结果”。[完整映射与源码定位](contracts/findings.md)可直接作为返修清单。不移出matrix、不添加到7项历史baseline、不自动刷新期望计数或减少负例。

## 5. 实际运行结果

根代理运行命令与完整结果：[report](targeted/report.md)、[summary](targeted/summary.json)、[import](targeted/import.log)。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_authority_intel|a1_entity_metadata_authority|a0_world_physics_sync|a0_integration_authority|a0_save_roundtrip)' -Ci -ResultsDir .test-results/sol-a01-r3/targeted
```

| 本地case | PASS/FAIL断言 | 退出 |
|---|---|---|
| integration.jc_authority_intel | 63/0 | 0 |
| integration.a1_entity_metadata_authority | 342/7 | 1 |
| integration.a0_world_physics_sync | 94/3 | 1 |
| integration.a0_integration_authority | 65/0 | 0 |
| integration.a0_save_roundtrip_authority | 41/0 | 0 |

共5项、3PASS/2FAIL，42.8s含20.4s导入，整体退出1。原始stderr中的对象/资源退出清理信息一并保留，不混为上述业务缺口，也不声称零stderr。

本地未重跑完整88项；CI的Phase0/PhaseA两个job success，full job failure。已核对[full原始日志](ci/full-job.log)与[关联元数据](ci/checks.json)：**88=79 PASS/9 FAIL，7 known＋2 new、drift0、complete=false，FULL_MATRIX_EXIT=1**，201.7s。新失败就是上述两probe；正常共享/owner老化独立反例未被63/0覆盖。Linux/macOS、真实渲染/人工可读性、真实RF/光学物理、>1000tick成本本轮均NOT RUN，不改变原专项任务或预算。

## 6. 下一次交付与UI新指引

DeepSeek先在原#58窄修三项实际缺口，同时按等强度映射适配两probe；保留本轮已绿项。提供同一最终40位SHA的原C回归、新旧文件/在途继续对照、实际HUD文本，更新PR body旧版本与计数，之后再独立放行A1、按原顺序解锁后续卡。Sol不代写生产实现。

新的60号UI指引已原样收录，未覆盖当前底层合同/门禁。Sol另交[61 UI文案台账与实施队列](../../61_UI文案台账与实施队列.md)：40条文案、术语表、五状态规格、UI-01至04卡。设计审校可以并行，HUD/Binder运行时修改等待A1及相应设计核对；UI-04并入实际B1/B2接口。没有新UI实机截图，也没有宣称视觉或联合战役Demo已完成。

归档文件校验见[SHA256清单](manifest.sha256)，清单不含自身。前两轮记录保留为历史，以上关闭项和剩余项为当前结论。
