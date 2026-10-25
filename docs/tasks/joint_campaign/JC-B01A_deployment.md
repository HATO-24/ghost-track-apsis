# JC-B01A：两套编制转为独立、可恢复的参战部署

执行Issue：[JC-B01A #62](https://github.com/HATO-24/ghost-track-apsis/issues/62)。

状态：服务WAIT A1/K0，Session最终集成WAIT A4；交付D1，属于B1前半。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 1. 目标与缺口

C55的FleetFormation管理选择/名册，但尚未把自由组舰变成完整的参战世界实体。建立“选择→校验→冻结部署→真实生成”的最小链，确保未选舰不出战、每舰资源独立，两套选择产生可解释差异。

## 2. 基线与范围

服务基于已审A1/K0；最终接线以A4精确SHA为底，按顺序集成，不同时重写GameSession。范围为既有Formation/ShipCatalog复用、deployment seed/实体映射、独立单舰初始运行态、必要部署入口/存档。舰池/点数/命名由B03P提案；旧13舰/8槽不是固定产品要求。

本卡不开发完整Refit/港口、舰队AI、目标结算或多舰发射。其他本方舰在B1b逐舰火控账本完成前明确返回战斗运行态不可用；绝不能借旗舰service展示“多舰开火已完成”。

## 3. 写者、资源与生命周期

Formation写选择，部署服务原子校验/冻结实例；EntityCatalog在boot按部署seed注册静态来源，PhysicsWorld写各实体运动学；单舰运行态容器按K0持独立装备/弹药/燃料/损伤/命令。选择/config snapshot与运行态分开，禁止共享可变Dictionary/Array。

实例ID稳定且全局唯一，named hull唯一、通用舰体重复要不同ID；fleet_id/controller/owner分开。mass/fuel从名册t到物理kg仅×1000一次，Δv用km/s，部署坐标/速度/参考系/历元同源。不能boot后绕开catalog临时生成无元数据舰。

## 4. 实施与提交拆分

1. 先写选A/B但world仍旧实体、未选舰仍存在、两个实例共享资源等红例；列实际可用舰型与需要用户批准的命名/预算。
2. 实现纯选择校验与部署seed生成：全部合法才提交，重复请求幂等，失败不半生成；以预部署阶段冻结/明确重置为边界，不在交战中重boot抹掉损伤。
3. 从同一seed构造catalog/physics/单舰初始容器，接最小编制确认→部署入口，呈现合法/拒绝原因；无目标运行层就显示未就绪，不伪造胜利结算。
4. 保存选择、冻结配置revision、实例映射及已存在的独立资源；恢复不能再次生成重复实体。提交按纯服务、boot接线、最小UI、恢复与证据拆开。

## 5. 验收

两套合法编制在实体集合、装备配置/质量/传感器输入等方面有可解释差异；实际火力差异留B1b验证，不以纸面数字宣称战斗已通。未选舰不在catalog、world、physics或资源账本；至少两个实例互不共享资源，改一舰燃料/损伤不改另一舰。自有直控/友军请求边界继续成立。

负例：重复命名舰/实例ID、未知舰级、越预算、无授权控制者、缺配置、质量转换错/无效坐标、重复部署；失败原子且理由明确。旧单舰seed/旧档可用；部署前/后真实文件恢复、同tick映射与至少10tick运动/事件一致，无重复实体。需最小非headless确认选择→部署可见，完整战斗试玩仍在B4。

## 6. 命令与证据

注册`integration.jc_deployment`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_deployment|fleet_probe|ship_catalog|a1_entity_metadata|a0_(world_physics|entity_metadata|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_deployment|fleet_probe|ship_catalog|a1_entity_metadata|a0_(world_physics|entity_metadata|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-B01A/targeted
```

加C回归。保存两套seed/实例清单、前后资源diff、catalog/physics来源表、拒绝对照、读档继续日志与非headless截图/操作步骤/环境；不能以probe通过替代UI存在。记录精确SHA、计数、退出码与限制。

## 7. 旧失败

#45仍为后续B1逐舰战斗必要依赖，本卡不靠关毁伤绕开；若部署触发其既有红例，按历史记录并分清新失败。#49预算保持固定旧负载，新战役规模另测，不修改fixture凑合格；不自动刷新baseline。

## 8. 交付与复核

D1提供可复现最小部署入口、两套编制、独立资源/实体映射、恢复与UI证据；独立审查尝试重按部署、换编制读旧档、修改一个实例后观察另一个。完成状态注明“B1部署切片完成”，后续B1b火控账本/B1c舰组控制未完成。
