# PR68 / JC-A02 首轮独立复核

日期：2026-10-27（Asia/Shanghai）。**RETURNED，继续原[#59](https://github.com/HATO-24/ghost-track-apsis/issues/59)，PR68暂缓合并、A2不冻结。** A1/G0/K0完成结论保留，不新增AI/EW/逐舰账本或真实RF范围。

## 1. 版本与结果来源

被审/本地运行HEAD `7293058d1c0d3cdedceff1fae6233523e7f8b313`，base/main `1738a5e41509c09e04dc34da382dc07f4b8982e9`。Windows，Godot `4.7.2.stable.official.ed1daf0bf`。

根代理统一导入，独立跑原卡七专项：**7/7 PASS，44.1s含24.4s import，退出0**。新identity66/0、identification310/0、track_table161/0、transponder272/0、sensor persistence86/0、event continuity89/0、save41/0。[report](targeted/report.md) / [summary](targeted/summary.json)。

[CI run40506547800](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40506547800)关联同head，实际checkout `2d8bac3f16ef825d95a901234fbb3f8da7f626bd`，为7293058d合入1738a5e的合成merge。三个job success；已下载核对[full原始日志](ci/full.log)与[关键行](ci/full-relevant.txt)：**89=82 PASS/7历史FAIL，new_fail0、drift0、complete=true，FULL_MATRIX_EXIT=0**，254.0s。[元数据](ci/checks.json)。本地未重复完整89项，不将CI冒称独立全量。

分项诊断退出0表示执行并保存记录，不代表验收通过；TTL脚本继承的PASS0/FAIL0不是正式测试结果。未改生产、正式probe、矩阵或baseline；导入生成的.import/.uid保留在验证树，不纳入文档提交。退出资源清理stderr保留。

## 2. 保留的绿项

- 新owner计算器/独立存储、未知owner拒绝、直接API两owner不同身份的隔离对照生效，不整项重做。
- 合法玩家应答查询确实接入；真实sensor IFF的直接结果/后续outbox在本对照保持一条证据。真实光学和ELINT生产者也已接入，保守unknown本身不是缺陷。
- 应答关闭时，隐藏side分别friend/hostile的无回应对照均unknown，没有据此认定隐藏side泄漏。
- 新人工入口正常确认/撤销专项正例保留；问题在真实旧入口、可信权限与审计闭环。
- 非本舰owner真实文件恢复后，10对tick的身份、状态、置信度、事件ID一致，包括自然跨TTL变化。手工Q-DIAG-1只证明pending容器序列化，不代表真实查询等待/投递链。
- A1授权、航迹老化、共享在途恢复、匿名显示完成结论不重开。

## 3. 原#59内五组返修

### R1 [P1] 真实来源须保留owner和事件，同一回复只消费一次

合法雷达接触已建立，对harmattan调用 `identity_iff_query("ally_intel",...,{mode:"mode_s"})`，未共享投递：player仍被写friend/confidence0.75/1证据，ally为friend/0.375/1证据。几何接触不等于获准接收盟军身份回复。原因：game_session.gd:4134–4139先flush真实应答，桥接:3841–3845无条件选本舰owner，之后才向请求owner再次ingest。

本舰默认mode查询的同一回复被桥接为mode_s/confidence1，再以空mode/confidence0.5二次送入；两条证据、confidence0.563。显式mode_s一条/0.75，同tick重复显式模式仍一条。这里观察到扭曲/降低，**不是实测虚增**。查询位置:4133–4165，计算器去重含mode。

真实SEVD-000001 ELINT事件归一后source=elint，category/evidence_type却为iff（桥接:3852及缺省:3973–3974）。来源类别确实丢失；混合IFF对独立性权重的影响是算法推论，未额外实测。

修同一来源链：保留可信owner、canonical target、原始事件ID、实际mode/置信度、observed/received/TTL/类别，一次回复只进入一次。无owner的legacy仅在明确本舰来源兼容，显式跨owner不得静默回退。保留本舰、sensor IFF去重、光学unknown正例。见[来源/消费者说明](evidence/source_consumer_findings.md)，[JSON](evidence/source_consumer_audit.json)案例iff_ally_query_own_leak、iff_default_double_route、real_signal_elint。

### R2 [P1] 人工确认/撤销统一可信权限和审计，覆盖实际Binder旧口

真实 `Binder.ident_confirm(...,"hostile")`走旧wrapper（shell_binder.gd:2090–2091，game_session.gd:4386–4393），直写旧计算器，下一tick转入新记录：manual=true、authorized=true、hostile，audit/audit_ids却空。同authority=cic_operator走新口拒绝；不带authority的旧Session确认也能在tick后变authorized hostile。即时Binder旧fallback与操作结果还会暂时分歧。

新identity_manual_confirm（:4185–4204）仅认自报authority字符串：operator=untrusted-caller、authority=command可向ally_intel写授权人工friend；identity_manual_clear（:4207–4223）无actor/authority参数也能撤销；审计:4232–4235把operator写空。存储隔离不等于调用者有权改这个owner。

Binder、新旧公开入口、日志/重放统一到受信actor/controller/owner许可及审计，保留真正有权的本方指挥员正例。身份确认权和FIRE/ROE许可分开，不能靠禁用全部人工动作收尾。见[真实Binder数据](evidence/source_consumer_audit.json)、[新口权限数据](iff_manual/results.json)。

### R3 [P2] 实际HUD航迹键须解析到同一owner身份

真实HUD _seed_combat_tracks（v1_hud.gd:2755–2764）得到T0001，对应raider_2。合法本方人工friend后，Binder/HUD与entity键操作记录均friend；调用request_fire(T0001,...,target_entity=raider_2)后，combat track仍unknown，combat_identity(T0001)回退combat_track/unknown。新game_session.gd:4238–4268直接把combat ID当身份键，没做获准映射。

实体键raider_2注册的合法控制能正确投影friend；正式probe也只走实体键，漏掉实际T0001路径。请求停needs_authorization，本轮**没有证明发射或绕过独立FIRE授权**。

统一owner限定的内部target/track/entity映射，修实际HUD→Session→ROE/火控边界；匿名显示ID不参与路由，稳定内部ID不改写，无获准身份不得补隐藏真值。保留实体键兼容正例。见[actual_hud_track_key](evidence/source_consumer_audit.json)。

### R4 [P2] TTL与迟到策略须进入计算器和读者，不仅改标签/跳过一次写入

observed0/received0/TTL5的friend证据，真实tick到11：identity_state=expired、age11，HUD、combat_identity及同步combat track却仍按friend读，未消费有效性。延迟t8接收observed0/received8/TTL5时，identity_state=stale却同时state=valid；别名在TTL更新前复制（game_session.gd:4087、4094–4103）。消费者见:4238–4268及Binder:1996–2021。

按合同把每条证据TTL/采样与接收时间真正用于评估/消费者策略，统一state别名、HUD提示和火控读域。可保留最后已知身份作历史，但不能与有效身份无差别使用；不硬规定所有旧记录必须unknown，不另定产品阈值。

合法迟到对照已修为非负时间：两会话真实到t2，新observed2/received2，旧observed1/received2，TTL20，所有ingest均ok。新后旧返回late_ignored=true、即时op friend；旧证据仍进入svc，下一tick转suspect/conflict、confidence0.386。旧后新控制即时即冲突，tick后同样0.386。最终收敛，但“忽略”与下一tick行为不符（:3992–4012、4301–4317）。

明确迟到接纳/忽略策略，审计保留不能污染下一重算；按规定时间语义比较，不仅比终点。早期负时间探索不是主证据，归档已换合法t2夹具。[时间/恢复说明](ttl_restore/findings.md) / [数据](ttl_restore/result.json)。

### R5 [P2] IFF传输状态与身份评估状态分开

光学先形成suspect/conflict，正常IFF回复friend后，assessment仍suspect，但identity_iff_query末尾直接apply_identity（game_session.gd:4169–4170）把identity_state覆盖为valid，操作读者丢失冲突。

实际reply_status=occluded的相同遮挡条件，加请求jam=0.95后仍是occluded，却被:4155–4157回报jammed；请求参数被当作实际阻断原因。

修评估/人工状态与IFF查询状态的独立字段/唯一写者，保留实际回复原因；按原卡补可观察未查询、等待、过期及真实查询继续。只恢复手工pending数组不能证明生命周期。不扩真实RF或军用IFF新协议。[IFF原始数据](iff_manual/results.json)。

## 4. 下一次交付

先在原#59保存真实入口红例，再最小修复，按五组逐项关闭，不重写整个计算器或重做绿项。正式probe覆盖实际Binder、盟军回复不串player、默认/显式mode同事件不重复、真实T0001、合法迟到下一tick、TTL有效性及查询冲突；不能只比较新API/helper返回值。

记录每owner、来源/查询/审计ID、观测/接收时间、数量和置信度前后、真实消费者及文件继续。取证脚本退出0与正式断言结果分开。最终同一40位SHA按原C回归；可增加有效断言/用例，不硬保持89，七历史baseline不刷新、新缺陷不登记历史。

PR68保持open，#59为RETURNED，#60继续WAIT A2；A1及PR66/67完成不撤销。核心仍A02→A03→A04→B01A。UI文案/交互文档由GPT/Sol维护，主要代码由DeepSeek实现，HUD/Binder与UI接入串行。

Linux/macOS、非headless渲染/人工可读性、真实RF/光学物理、>1000tick成本本轮均NOT RUN，原专项/预算不变。文件校验见[manifest.sha256](manifest.sha256)。
