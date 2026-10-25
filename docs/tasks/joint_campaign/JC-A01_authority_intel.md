# JC-A01：指挥权限与分方情报隔离

状态：WAIT G0/K0；交付A1。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 1. 目标与复现

C55的`GameSession.request_fire`在显式shooter_id无效时回退本舰，CombatService仍单一；系统`plot_positions`等真值接口也未形成可验收的多owner读域。先堵住错误授权与情报混流，为后续逐舰战斗/AI建立边界。

## 2. 基线与范围

解锁时将G0、K0填为实际40位SHA，并核对整链；C55仅为调查来源。范围为授权入口、owner隔离的观测/TrackTable访问、HUD/ViewModel/绘图的读取适配、命令日志及必要恢复。不得同时实现完整AI或逐舰战斗账本，不将系统物理解算内部真值接口删除后再从UI取代。

## 3. 写者、读者与可见域

部署/控制注册表写归属与授权；Sensor/合法消息投递写接收owner的证据入口；每owner的TrackTable写其融合结果；玩家UI和未来AI只能读对应context。真实弹体碰撞/物理解算可读内部真值，但不得随快照交玩家/AI。阵营关系只能影响许可检查，不能隐式复制航迹或武器控制权。

命令保留actor/controller/fleet/shooter及模拟秒；显式未知或非授权shooter在消耗资源、排弹、成功事件前拒绝，拒绝审计可记录。无context的兼容调用仅指旧本舰；已授权其他本方舰若尚无独立战斗运行态，返回`shooter_runtime_unavailable`，绝不借旗舰发射。friend盟军的直接命令拒绝，未来协同请求走另一协议。

## 4. 实施与提交拆分

1. 红例：无效shooter触发旗舰路径；同一隐藏敌方真值变化影响未经观测的玩家视图；三owner观测串域。先记录现状，已有正确项保留绿证据。
2. 按K0落授权检查与明确拒绝，补输入/事件/重放context；不要用到处if friend代替统一授权。
3. 落owner隔离的证据入口、融合与读取facade，覆盖list/selected、HUD、plot、导出日志/诊断视图。共享观测必须经受权链路实际到达，带来源与观测/接收时间，接收后才融合。
4. 补存档/恢复各域航迹与context；旧档迁入legacy本舰域，不能复制到盟军。提交顺序为红probe、服务/入口、UI读路径、恢复与证据。

## 5. 验收

正例：自有舰授权检查、合法本舰旧调用、三个owner独立观测，链路投递后只有接收方获得共享证据。负例：未知/敌方/友军shooter均无资源变化；未实现的其他本方舰战斗返回不可用；隐藏目标改名/改坐标但保持相同合法观测时，玩家视图与测试决策输入不变；无观测的owner仍未知。不得把测试用决策器当已完成AI。

覆盖selected/list/plot/导出、重复共享、非法owner、延迟到达、同tick顺序、旧seed/旧档。内存＋真实文件恢复再继续至少10tick，事件context、owner航迹与在途共享一致；共享几何使用observed_t，received_t单调，单位/容差按公共契约。

## 6. 命令与证据

注册新probe `integration.jc_authority_intel`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_authority_intel|track_table_probe|fleet_probe|a0_(track_truth|event_continuity|integration_authority|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_authority_intel|track_table_probe|fleet_probe|a0_(track_truth|event_continuity|integration_authority|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A01/targeted
```

加C回归；日志列每条输入context、拒绝原因、前后资源差、每owner可见字段、未来10tick对比、真实SHA/退出码/断言与CI。

## 7. 旧失败

特别核对#46本舰ID/TWS/显示来源，但不以权限修复掩盖原问题；7项full旧失败转绿/漂移单列，无新失败。保留orbital_sim有限资源/正常ROE，不通过改profile消除拒绝。

## 8. 交付与复核

A1提供授权/情报接口表、调用者迁移清单、兼容语义、独立证据及未接入点。独立审查应尝试直接调用Session、selected、plot与存档导出绕过facade。此卡完成不等于逐舰战斗或友军AI已完成。
