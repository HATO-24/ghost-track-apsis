# PR75 / JC-B01A第四轮：保留关闭子项，只收尾原R4/R5

2026-10-29，候选`db3bef90420178ba246a54b13efd7a342bb6c013`，Windows/Godot4.7.2.stable.official.ed1daf0bf。**RETURNED，D1未放行，继续原#62；不启动下一卡。**

根仅复用原Binder诊断、补看确认后的三层实体集合，运行一次；部署probe83/0、退出0，39.4s含30.7s导入。[专项](targeted/summary.json) / [原诊断](entry_audit.gd) / [实际数据](entry_audit.json) / [日志](entry_audit.log) / [命令](run.json)。日志保留退出时ObjectDB/resource提示，退出0只代表记录完成。无根生产/正式probe/matrix/baseline修改。

## 这次已关闭的子项

auto=false真实Binder在t0.1及额外一帧后均能首次DEPLOY成功，plan/commit均rev-425754d2，冻结实际FleetRefit状态与当前状态相等。原“首次确认被时钟锁死”、手动路径版本不一致与空实际配置子项均关闭，不再重做。已查看[新非headless样张](https://github.com/HATO-24/ghost-track-apsis/blob/db3bef90420178ba246a54b13efd7a342bb6c013/game_v17/docs/next_cards/evidence/b01a/nonheadless/fleet_builder_first_confirm.png)，窗口按钮/状态显示证据保留；根未操作桌面或DSH。

## 仍剩原R5：确认成功后必须真正生成同一套实体

两个auto=false控制均返回成功，但实际：catalog是5艘选择舰；physics只有`legacy_ship`；world是5艘选择舰加`legacy_ship`共6个实体。原卡“未选舰零残留、catalog/world/physics同源”的首次确认验收未通过，HUD的5 instances来自部署记录，不能代替物理实例。

同一次原入口诊断已定位接点：`_apply_deployment_runtime`发送despawn时target为空，只把id放payload.entity_id；WorldState的despawn按event.target删除，apply因unknown_entity失败却未处理，因此旧舰残留。随后重建physics时尚未更新`_seed.entities`；`_seed_physics_entities`的部署分支优先读取旧seed，忽略传入新ents，再次生成旧物理舰。请在原运行接线上修正target/结果处理及新seed应用顺序，补首次确认后**三层集合**及后续同步断言。不是重做第二轮已关闭的auto=true/显式名单分支。

## 仍剩原R4：auto=true兼容路径仍冻结空实际配置

原auto=true控制臂保留（仅把同一demo的auto改true）：三层均正确5舰，plan/deploy现在返回相同旧冻结revision，但实际当前FleetRefit状态非空，冻结refit_service_state仍为空。新增plan返回committed只消除了版本表面差异，没有把实际配置补进冻结。

`_setup_deployment_from_seed`依然先于`_setup_optional_components`中的Formation/FleetRefit初始化。只修自动部署的配置就绪/冻结顺序，使它与手动路径同样冻结实际配置；保留合法幂等、已部署后更换编制锁、损伤和旧档语义，不以改demo默认值代替原兼容路径。

## 保留证据边界与下一次验收

第二轮五个窄观察的已关闭范围保持；本轮只收尾上述原R4/R5，不扩AI/B1b/B1c/RF/预算产品参数。交付final2等本地摘要实际基于3ea9e8ce加dirty，不称干净db3bef9；同head CI当时Phase0/PhaseA成功、full运行中，[快照](ci-checks.json)。根原C等待实际入口全部闭合后的最终HEAD，不重复跑仍有明确阻塞的中间版全量。

修后同40位HEAD交卡指定专项＋原C、手动首次生成三层一致/10tick续行、auto=true实际配置冻结/恢复及对应非headless证据。已有通过项不重派。[第三轮历史](../b01a_r3_20261029/review.md)。交接由用户转发，Sol未直接联系DeepSeek。
