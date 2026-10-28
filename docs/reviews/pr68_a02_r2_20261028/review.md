# PR68 / JC-A02 第二轮独立复核

日期：2026-10-28（Asia/Shanghai）。**RETURNED，仅剩实际消费者两处收尾；继续原#59，PR68暂缓合并，A2不冻结。** 本轮不重开已关闭来源、权限、时钟和恢复工作。

## 1. 被审版本与实际结果

HEAD `4a658699868b8d046ec5472f9c4b9ea204af6be9`，上轮 `7293058d1c0d3cdedceff1fae6233523e7f8b313`，base/main `1738a5e41509c09e04dc34da382dc07f4b8982e9`。Windows，Godot `4.7.2.stable.official.ed1daf0bf`。

根代理独立七专项 **7/7 PASS，36.4s含18.3s import，退出0**：identity110/0、identification310/0、track_table161/0、transponder272/0、sensor persistence86/0、event continuity89/0、save41/0。[专项report](targeted/report.md) / [summary](targeted/summary.json)。

[CI run40532405925](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40532405925)关联同HEAD；实际checkout `73164f942c285a9d0e5bb69496385aacd0a7ab22` 为4a658699合入1738a5e的合成merge。三个job success；已核对[full原始日志](ci/full.log)与[关键行](ci/full-relevant.txt)：**89=82PASS/7历史FAIL，new_fail0、drift0、complete=true、FULL_MATRIX_EXIT=0**，335.0s。[CI元数据](ci/checks.json)。本轮未独立重跑本地全量89项。

原三个取证脚本/新接口对照均正常完成，退出0表示记录完成，不表示全部验收通过。源审查初次相对script路径未加载，随后绝对路径有效运行，见其launch记录；权限诊断为归档stdout额外执行一次，不计作正式probe。原始stderr/资源退出清理诊断保留。未改生产、正式probe、矩阵或baseline；.import/.uid生成物不纳入交付。

## 2. 逐项关闭，不再派发返工

| 原组 | 本轮真实对照与处置 |
|---|---|
| R1 owner/去重/类别 | 真实雷达接触后盟军IFF不写玩家：player unknown/0证据，ally friend/0.75/1。默认、显式mode_s及同tick重复均1证据/0.75。真实SEVD-000001归一后source/category/evidence_type均elint。**原三项CLOSED** |
| R2人工权限/审计 | 真实Binder确认/撤销与旧Session、新owner API同语义，审计含player_ctrl、owner、authority和operator。显式不可信actor写ally拒绝；受信ally_ai本owner确认成功。**CLOSED** |
| R4迟到/有效性服务与火控 | 合法t2新obs2/recv2、旧obs1/recv2，late_ignored后即时及下一tick均只含已接纳optical，friend/confidence0.639；不再偷偷进重算。TTL5到t11为expired、valid=false/effective_identity=unknown，火控与同步combat track均unknown。**这些子项CLOSED** |
| R5状态与自然查询继续 | IFF正常回友军后评估仍suspect/conflict，独立iff_state=valid。occluded与occluded+jam均保留no_reply/reason=occluded。自然API latency3s创建IFFQ-000001，t2保存/真实文件load，t3/4 pending、t5按ETA到达，源/恢复10/10 tick三owner身份、置信度、查询和事件ID相等。**CLOSED** |

[来源/消费者分项](sources/source_consumer_findings.md) / [数据](sources/source_consumer_audit.json)；[权限/状态数据](authority/results.json) / [归档运行输出](authority/run.log)；[时间/自然队列说明](time/findings.md) / [完整逐tick数据](time/result.json)。

自然队列这次由真实identity_iff_query创建，无手工pending数组。旧owner文件继续绿项保留：ally事件ID到ID-EV-000014、10tick置信度到0.229，两边逐tick一致。A1/G0/K0完成结论不变，不要求重做已落服务。

## 3. 仅剩两处实际消费者

### R3 [P2] 真实HUD产生的T0001仍无法解析到owner实体身份

原合法反例未改：真实radar 6s→Binder.refresh→实际HUD._seed_combat_tracks→合法本舰人工friend→实际request_fire(T0001,missile,...,target_entity=raider_2)。

| 实际边界 | 值 |
|---|---|
| global TrackTable VM/HUD种入的combat行 | T0001，entity_id与ship_id空 |
| Binder owner contact / raider_2操作记录 | friend，valid=true，effective_identity=friend，审计IDA-000001 |
| combat_identity(T0001) | unknown，source=combat_track，resolved_key空 |
| request_fire后的实际combat T0001 | 仍unknown |
| 实体键raider_2合法控制 | 正确投影friend |

请求仍在needs_authorization拒绝，**没有实际弹体发射或绕过FIRE授权的证明**。这是原身份读者不一致，不是新增射击范围。

当前game_session.gd:4255–4261所谓sensor fallback调用_entity_for_track；该helper(:3138–3150)只看combat entity_id/ship_id或同名physical实体，没有反查已有_sensor_track_map。实际HUD(v1_hud.gd:2755–2764)原样注册空映射字段的VM行；request_fire已合法解析出的target_entity也未供身份同步(:3007–3009)。因而本轮新resolver只覆盖“字段预填”的分支。

新正式R12在jc_identity_pipeline_probe.gd:411用_register_combat_track(T0001,raider_2)，helper(:576–578)预填track_id/entity_id；未调用实际HUD种入流程。其绿色不能关闭原反例。

**最小收尾**：在现有owner许可和内部稳定ID下接通真实sensor/track/entity映射，或复用已经核验的目标实体解析结果，统一传到实际身份/ROE投影。不要从全量隐藏真值补身份、不要改匿名显示ID。保留预填字段与实体键兼容正例，正式验收补实际HUD空映射字段的合法路径。详见来源分项的actual_hud_track_key。

### R4 [P2] 过期有效性已到helper，实际HUD仍不消费

真实时间对照：TTL5、t11，Binder.ident_view返回validity=expired、valid=false、effective_identity=unknown，但原identity字段保留friend。保留最后已知身份**本身允许**；残项在实际普通显示未区分历史/有效值。

根代理核对实际读者：v1_hud.gd:3651–3655的_draw_ident_overlay只读取iv.identity；:3699直接以ident.to_upper及_ident_col画身份。该界面没有读取新增validity/effective_identity；正常联系人路径也仍从owner原identity生成side/type与ident。新增字段暴露和正式probe只断字段，不能代替实际读者接入。相关源码定位见[hud-reader-evidence](hud-reader-evidence.md)。

**最小收尾**：让实际普通HUD身份读有效结果，或明确显示“最后已知/已失效”并区分原值；raw identity仍可留历史详情。同步相应联系人/详情读者，不能只再增加一个未消费字段。按已批准身份语义接线，不重做TTL/置信度算法、不要求全屏UI重排，也不推给UI-01文案卡。

分项提到的stale/valid并存按本候选新合同解释：state/identity_state是评估态，validity是时效，二者可以不同；**不把这个单独判成别名错误，也不强制stale一律unknown**。本轮只保留上述实际HUD显示未消费的子项，过期火控、late、别名一致与自然恢复均已关闭。

## 4. 下一次交付边界

仅原R3和R4的两个实际消费者收口；R1/R2/R5及R4已绿子项不再派发。先保留原真实HUD反例，再小改接线，真实入口与字段/实体键兼容对照共同验收；不得在测试手工预填生产路径缺失字段后宣布完成。

最终同40位SHA按原C回归，七历史baseline不刷新。PR68保持open，#59仍RETURNED、A2不冻结，#60仍WAIT A2。UI文档和设计规格由GPT/Sol维护，主要代码交DeepSeek；本次数据读者修正属于现卡，不另开大UI功能。

Linux/macOS、非headless渲染/人工可读性、真实RF/光学物理、>1000tick成本本轮NOT RUN；本报告HUD结论为真实数据加实际绘制源码核对，不冒称新实机截图或视觉验收。校验见[manifest.sha256](manifest.sha256)。
