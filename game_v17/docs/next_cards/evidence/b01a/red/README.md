# JC-B01A 部署红例（实现前，开工 HEAD 4e75897）

- 探针：`game_v17/tests/jc_deployment_probe.gd`
- 注册：`integration.jc_deployment`（matrix 92 项）
- 结果：`PASS=15 FAIL=34`，退出 1
- 覆盖：两套编制 boot/vm/revision、catalog/physics/world 零残留、独立资源与 t→kg、负例原子拒绝、幂等/部署锁、真实文件恢复与 10 tick、旧单舰 seed、部署入口合同
- 失败根因（实现前）：Formation 只写 assignments；Session 无 deployment seed/冻结/实例映射；catalog/physics/world 仍按 seed.entities 全量名册；无 per-instance 资源账本与部署入口。
