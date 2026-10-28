# JC-B01A 部署核心链证据（里程碑 2）

- 探针：`jc_deployment` 72/0（实现前红例 15/34）
- 卡指定专项 7/7 PASS：ship_catalog 1488/0、fleet_probe 511/0、a1_entity_metadata 359/0、
  a0_world_physics_sync 107/0、a0_entity_metadata 31/0、a0_save_roundtrip 41/0、jc_deployment 72/0
- Full strict：92 = 85 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true
- 已实现：DeploymentService（选择校验/冻结 revision/稳定实例/t→kg 一次/独立资源/幂等/部署锁/严格恢复）、
  boot 同源 seed 接线（catalog/physics/world/own_entity/fleet_instances/owner）、auto=false 预部署阶段
  t=0 confirm 部署、部署状态随档恢复不重复生成。
- 待完成：Binder 最小 DEPLOY_PLAN/DEPLOY 入口与可见确认/拒绝原因、非 headless 截图/操作步骤证据；
  负例补充（重复命名舰/越预算等）与最终报告。
