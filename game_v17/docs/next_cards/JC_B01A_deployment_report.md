# JC-B01A（#62）两套编制独立部署 · D1 交付报告

> 分支 `jc/b01a-deployment`；开工 main `4e75897`（含 A4 合入）；平台 Godot 4.7.2 / Windows；证据 `game_v17/docs/next_cards/evidence/b01a/`

## 状态

**B1 部署切片（D1）完成**；B1b 逐舰火控账本、B1c 舰组控制未完成；未启动下一卡。

## 交付

- **部署核心**：DeploymentService（选择校验/授权 controller-owner-fleet-domain/冻结 revision/稳定实例/独立资源/幂等/部署锁/严格恢复），boot 同源 seed 接线 catalog/physics/world；部署态覆盖显式 physics 旧名单；旧 seed/旧档覆盖不残留上一局；实际 FleetRefit 当前配置与 config_revision/几何进入冻结快照（缺失 ammo/command 初态明确标注 `not_integrated_b1b`）。
- **入口**：Session `fleet_deployment_plan/fleet_deploy/fleet_deployment_vm/deployment_resources/deployment_test_patch`；Binder `DEPLOY_PLAN/DEPLOY`；HUD `fleet_builder` 可见按钮/状态/结果与拒绝原因；测试场景 `scenario_b01a_deploy_demo.json`。
- **验收**：两套合法编制（A/B）实体集合与资源可解释差异；未选舰零残留；独立资源互不影响；负例（未知舰/重复 instance id/重复命名舰/槽位超限/越预算/无授权控制者/非法坐标/缺 confirm）原子拒绝；部署前/后真实文件恢复、同 t 映射、10 tick 运动+事件一致、无重复实体；旧单舰 seed 兼容；最小非 headless 窗口截图证据。

## 红→绿

`integration.jc_deployment`：实现前 15 PASS / 34 FAIL → 当前 **83 PASS / 0 FAIL**（matrix 92 项）。

## 同一 HEAD 运行

```
卡指定专项 7/7 PASS：ship_catalog 1488/0、fleet_probe 511/0、a1_entity_metadata 359/0、
  a0_world_physics_sync 107/0、a0_entity_metadata 31/0、a0_save_roundtrip 41/0、jc_deployment 83/0
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 92 = 85 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true
```

七历史 baseline 未刷新；未扩 B1b/AI/RF/预算产品取舍。

## 边界 / NOT RUN

B1b 多舰火控/弹药发射、B1c 舰组控制、完整战役试玩未实现；真实 RF/光学未接；Linux/macOS、>1000 tick 成本 NOT RUN；部署样张为最小可见入口，不等于战斗验收。
