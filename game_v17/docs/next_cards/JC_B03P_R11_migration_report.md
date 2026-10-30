# JC-B03P R11 / #63：fixture/probe/K0 有界迁移报告

> 执行卡：[#63 R11 迁移交接](https://github.com/HATO-24/ghost-track-apsis/issues/63#issuecomment-6517317184)。基线 main = `042a5e5e03f38f7b7e4367ffb0b6f38834773503`（含 H01 PR77）；开工重核。
> 代码/规格提交：`7fb575bca423cda62c544d94c018319c01e2cbc8`。最终报告/证据提交后的 40 位 HEAD 以 PR/回报为准。
> 范围：`jc_sector_01_proposal.json` v4、`jc_scenario_spec_probe.gd`、K0 说明、任务卡迁移记录；**不含运行层/AI/B1b/B2/B3/UI/弹种**。

## 1. 旧 → 新映射

| 旧 v3（P0-r7-1） | v4（P0-r11-1） | 处理 |
|---|---|---|
| `schema=v17.jc.scenario_spec.v3`, version 3 | `v17.jc.scenario_spec.v4`, version 4 | 旧 v3 **拒绝**为当前规格；`old_schema_policy` 显式注明需迁移 |
| `fleet_pool.points_budget=100` / `command_capacity=3` / `points_formula` / 两套编制 | 删除；`fleet_ownership` + `combat_selection` + `deployment` | 旧固定预算/3 舰仅历史；不新冻结数字 |
| `formations[]` = SENSOR/STRIKE 预设 | `combat_selection.four_legal_compositions`（3:0/2:1/1:2/0:3） | 四组合作合法规格；不固定 FERRY/ANVIL/VESUVIUS |
| `own_flag` = I-A1 HEMATITE，20 点，in_formation | `apsis` / `OCUVF-APOGEE` / `in_theater_rear_support` / PROT-2 | APSIS 计入 8 支援，不占 3；损失→defeat；场外指挥/继承不实现 |
| 8 支援/3 作战未分离；combat 固定 3 舰 | 11 独立舰：APSIS 1 + PALLET 2 + SAFEHARBOR 2 + MOONPORT 2 + WINCH 1 + 作战 3；ARIA-1 随旗舰不独立 | 临时候选/实例；未选组合不额外拥有 |
| 3 艘作战舰固定 FERRY+ANVIL+VESUVIUS | 3 个 combat slot 由 HEMATITE/GANTRY 选择；每组合唯一实例 + 独立 `resource_ref` | 临时呼号，不复制具名舰/不改身份 |
| 无 owned/deployed 分离 | `fleet_ownership` / `deployment.deployed_instance_ids` / `reserve_instance_ids` / `task_groups` | 全舰队、任务部署、留后/分组分开 |
| `terminal_rules.contribution_exception`（全友军→stalemate） | 删除；R9 truth + `command_evaluation` 有序唯一 | 友军自主真实结果 victory，评价未参与 |
| 3600 s 被当硬时限 | M0 默认：t3600 仅观测不结算；M1 仅显式配置到期裁决；M2 未定义不采用 | PT05 M1 合成条件保留 + M0 ongoing 对照 |
| R9 2 舰无武装友军 | R9 有限武装独立友军（PALLET+SAFEHARBOR+HEMATITE）；SUPPRESS 真实 railgun | 无固定 120s 减益、无身份免杀 |
| OBJ-B 只写 railgun 火控 | OBJ-B 导弹 VLS + railgun 双攻击链均永久失能才完成 | 单链失效=未完成，战报写剩余能力 |
| `event_traces` 14 条 | 17 条（含 M0 ongoing/M1 硬限/OBJ-B 单链/友军自主/报告防泄漏/幂等） | 仅内容逻辑，不是真实战报 |

## 2. 11 舰与四组合（规格正例）

- **8 支援**：APSIS（`apsis`/APOGEE，旗舰、战区后方、PROT-2、不占作战 slot）1；PALLET 哨舰 2；SAFEHARBOR 中继 2；MOONPORT 油船 2；WINCH 拖船 1。
- **3 作战**：3 个 slot，只允许 `OCUVF-HEMATITE-6C` 与 `OCUVF-GANTRY-3M`；四种合法比例 3:0、2:1、1:2、0:3；每组合实例 ID/`resource_ref` 唯一；当前 `owned_instance_ids` 只含选中组合的 3 艘。
- **临时实例**：支援/作战实例使用 `picket-1`、`C21-H1` 等临时呼号；APSIS 使用既有命名实例；`entity_bindings` 为空，不覆盖既有命名舰。
- **owned/deployed/reserve**：默认 11 舰全部部署、reserve 空；`TG-CMD`/`TG-SCREEN`/`TG-STRIKE` 三组恰好覆盖 deployed，不重复；不是“只能带 3 舰”。

## 3. 断言覆盖表（`integration.jc_scenario_spec`，507/0）

| 覆盖域 | 正例 | 负例/拒绝 |
|---|---|---|
| v4 本体/实例 | schema/version/status、catalog 路径、11 实例 ID 唯一、class 存在 | 旧 v3 schema |
| 11 舰 | 8 支援精确计数、APSIS 计入 8、不占 3、穿梭机不独立、owned=11 | 4 艘作战、12 艘、缺必需位、重复实例、APSIS 占作战位 |
| 四组合 | 四个比例均合法、每组合 3 舰/唯一实例/独立资源引用、owned 只含选中组合 | 错误舰级、未选组合混入 owned、错误比例/实例 |
| 部署 | deployed/reserve/task_groups 分离、成员不重复、组覆盖全部 deployed | unknown/reserve 冲突、任务组重复/漏项 |
| APSIS | `apsis`/APOGEE、rear、PROT-2、损失→defeat、不在 combat | PROT-2 错绑实例 |
| 目标 | OBJ-A/B/C、OBJ-B 双攻击链永久失能、OBJ-C 无身份免疫、不可恢复/机制/替代 | 单链完成、目标仍有效、错误目标引用 |
| 时间 | M0 3600 观测不自动结算、M1 显式硬限、M2 不采用 | M0 自动终态、M1 未显式、t3600 默认终态 |
| truth/report | 报告未回玩家 unknown、权威可已达成、同 tick 优先级、幂等 | 报告未回泄漏真值、重复裁决、同 tick 冲突 |
| 贡献评价 | 有序唯一 主导→有效协同→有限参与→未参与；友军自主 victory+未参与 | 贡献改写真实结果、缺评价 |
| 友军/R9 | 有限武装、真实 railgun、无固定减益/身份免疫、回执区分投递/接受/执行/目标完成 | 固定减益/射手免疫/伪装混用 |
| 轨迹 | 17 条，含 M0 ongoing、M1 零完成/部分、OBJ-B 单链、报告防泄漏、友军自主、幂等 | 终态与规则不符、时间非单调、非法终态 |
| 旧 schema | v4 current、v3 rejected/需迁移 | 旧 v3 直接读取 |

## 4. 原始结果（同一代码 HEAD `7fb575b`）

```text
integration.jc_scenario_spec  PASS  507/0  exit 0
integration.jc_contracts      PASS   84/0  exit 0
total=2 pass=2 fail=0

Full C:
total=92 pass=88 fail=4 timeout=0 not_run=0
BASELINE CHECK: known_fail=4 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
RESULT: BASELINE MATCH — exit 0
Phase 0: 6/6 PASS；Phase A: 3/3 PASS
```

baseline 未刷新：仍保留 H01 后其余 4 项历史失败（`content.story_text_probe 469/13`、`unit.incident_record_probe 2761/1`、`integration.plot_tws_probe 58/1`、`integration.v17_sensor_authority_display_probe 71/3`）。本卡无新增回归、无 baseline 变更。

## 5. 旧版本策略与未覆盖

- **旧 v3**：不在当前规格中自动兼容；探针用 `old_schema_policy` 和“v3 mutation 被拒绝”断言。旧 100/45 点、3 舰、SENSOR/STRIKE、I-A1 旗舰只作历史/迁移对照，不塞入 v4。
- **未实现/NOT RUN**：B1b 逐舰战斗/损伤账本、B2 AI/请求回执、B3a/b 运行态裁决/内容、真实部署、UI/HUD/Binder、补给生产/全球战争、弹种/混装（E-AMMO-00 后延）、11 舰规模与四组合真实运行/平衡/可玩性。
- 纸面合法不等于可平衡或可玩；本卡只交内容规格与校验，不启动下一卡。
- UI_COPY_B001 继续原串行排程，未串入 HUD。

## 6. 证据

- `game_v17/docs/next_cards/evidence/b03p_r11/targeted/`：专项 summary/report/两 case 日志
- `.../full/`：共同 C summary/report
- `.../gates/`：Phase0/PhaseA summary
- fixture：`game_v17/tests/fixtures/jc_scenario/jc_sector_01_proposal.json`
- probe：`game_v17/tests/jc_scenario_spec_probe.gd`
- K0：`game_v17/docs/contracts/joint_campaign_r2.md` §9
