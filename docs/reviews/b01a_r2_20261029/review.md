# JC-B01A / #62 第二轮：原窄反例关闭，继续原卡交付

2026-10-29，Windows / Godot4.7.2.stable.official.ed1daf0bf / headless。冻结`323018ac4c13c9815c6b56d7e32c14976000d38e`。**D1尚未放行；不启动下一卡。** 只复测首轮原五个观察与单个部署probe，未新增反例或扩大范围。

根部署probe **72/0，退出0**，耗时44.7s含36.7s导入。[专项summary](targeted/summary.json) / [报告](targeted/report.md)。一次原诊断复用只更换HEAD与输出路径，退出0；[源码](diagnostic.gd) / [数据](diagnostic.json) / [日志](diagnostic.log)。退出0只说明观察记录完成，下表分别判定。

| 原项 | 本轮实际结果 | 状态 |
| --- | --- | --- |
| R1显式物理旧名单 | catalog/world/physics均恰为apsis、harmattan，合法控制臂继续成功 | CLOSED，不重派 |
| R2原非法controller | ready=false，deployment_invalid:unauthorized_controller:unregistered_controller | 原窄反例CLOSED，不夸大所有权限路径已验 |
| R3无deployment旧seed文件覆盖活跃部署 | load成功，三层仅old_ship；VM enabled=false/deployed=false，旧apsis资源no_deployment | CLOSED；文件由本候选生成，不冒称历史归档fixture |
| R3缺实例资源 | load明确invalid_state/resource_missing:apsis，原有效资源仍可读 | 原窄反例CLOSED |
| R4几何冻结 | 原100→200km变更得到不同revision：rev-6fe680fe、rev-e712a0bf | 此子项CLOSED |

R4仍需收尾实际配置来源：新config_snapshot包含class字段、roster.refit_state和config_revision，并明确ammo/command为not_integrated_b1b；本fixture的refit_state={}、weapon_loadout=[]。差分没有读取玩家当前FleetRefit实际配置，不能把该快照称为当前已选装备已冻结。沿原卡接已有配置、版本和独立初态/恢复，缺失明确；不要求在此实现B1b发射或完整改装。

R5仍OPEN：本轮差分只有Binder部署接线与核心修复，没有HUD绘制提交；正式部署probe仍是原72断言。最小可见确认→部署→结果/拒绝原因、非headless操作/截图、原负例/10tick事件连续性、最终同40位HEAD卡指定专项＋原C及新的B01A交付PR仍待完成。远程核验到本候选时尚无B01A PR；PR74仅Sol复核文档。

本轮**原C、非headless均NOT RUN**，未把旧dirty full摘要当本候选证据。七历史baseline未刷新，未修改生产/正式probe/matrix；本PR运行tree保持原main。其余首轮未重测项保留原限定。[首轮记录](../b01a_r1_20261029/review.md)。交接由用户转发，Sol未操作DSH或直接派发。
