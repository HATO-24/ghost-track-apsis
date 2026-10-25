# Phase A 八卡交付总览（I0–I7）

> 任务卡来源：PR #31 `codex/deepseek-phase-a-task-cards-20261025` 的
> `docs/57_DeepSeek_PhaseA_任务队列与首批任务卡.md` 与 `docs/tasks/phase_a/DS-A-00..07`。
> 远端 `main` 保持 **`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`（S0）未被合并/改动**；
> Phase A 全部工作在独立分支与层叠 PR 上，**未并入 Phase 0**。

## 1. 八卡交付表

| 卡 | 交付 SHA（完整） | PR | CI run | 结果 |
|---|---|---|---|---|
| DS-A-00 契约协调 | **I0** `b9101c8369c44dc293e579701efa0a4029d28dec`（A-00 分支 head `882e058e2a0550684ade73f6978122fef46d42d7`） | #32 | 40149419719 | Phase 0 6/6；矩阵 78=68/10 |
| DS-A-01 整合验收 | **I1** `26f1d5398a4ed6654b057f23a27819e4bf700b31` | #33 | 40152010634 | Phase A 2P/1F；矩阵 79=70/9 |
| DS-A-02 frame/历元 | **I2** `7b5691482929d493467aec12eddbe20f3782f35e` | #34 | 40153699786 | A0-T3 38/3；矩阵 80=71/9 |
| DS-A-03 事件续写 | **I3** `f842b3db6158d08bb6da5221252745882a2cc858` | #35 | 40154855534 | save_probe 转绿；81=73/8 |
| DS-A-04 旧档迁移 | **I4** `b04726641057aa80ccc83829e8da00b973f2f733` | #36 | 40158154261 | 82=74/8 |
| DS-A-05 传感器运行态 | **I5** `0a66ea2ca45e36739e3c92da80f742526b8b24cb` | #37 | 40159920556 | A0-T3 40/1；83=75/8 |
| DS-A-06 通信读档 | **I6** `10a48653f9ff5b07517d6eb39c06dbdffb09104e` | #38 | 40161001811 | **Phase A 3/3 全绿**；84=77/7 |
| DS-A-07 存档成本 | **I7** `6d7bba732b0f1119c2dd2fb5b8041bcd76030c33` | #39 | 40163207847 | benchmark PASS 62/0；84=77/7 |

## 2. 各卡文档（断言/契约映射、failure ledger、真实日志）

| 卡 | 文档 |
|---|---|
| A-00 | `docs/a00_contract_mapping.md`（+ `.test-results/phase-a/cards/DS-A-00/` 的 inventory/review/failure ledger） |
| A-01 | `docs/a01_integration_acceptance.md` |
| A-02 | `docs/a02_frame_epoch.md` |
| A-03 | `docs/a03_event_continuity.md` |
| A-04 | `docs/a04_legacy_migration.md`（+ fixture provenance/hash） |
| A-05 | `docs/a05_sensor_persistence.md`（字段分类/恢复顺序） |
| A-06 | `docs/a06_comms_restore.md`（原执行/replay 对照、旧日志矩阵） |
| A-07 | `docs/a07_save_cost.md`（+ `docs/benchmarks/a07_save_cost/` 原始 JSON/CSV、预算建议） |

## 3. 最终门禁状态（I7 / run 40163207847）

| Job | 结果 |
|---|---|
| Phase 0 gate | ✅ **6/6 PASS**（语义未改，gate 仍为 6 case） |
| Phase A gate | ✅ **3/3 PASS**（45/0、30/0、41/0） |
| Full matrix | ✅ **84 = 77 PASS / 7 FAIL**，`known_fail=7 new_fail=0 drift=0 complete=true` |

**7 个 FAIL 为 Phase 0 历史失败，逐条可见、未被清零、未被隐藏**：
`content.damage_profile_probe 554/4`、`content.story_text_probe 469/13`、
`unit.incident_record_probe 2761/1`、`integration.damage_integration_probe 198/6`、
`integration.plot_tws_probe 58/1`、`integration.v17_nav_integration_probe 181/1`、
`integration.v17_sensor_authority_display_probe 71/3`。

## 4. 贯穿全批的真实修复（红→绿，均有日志）

| 修复 | 卡 |
|---|---|
| 几何可用性分级 live/advisory/unavailable（无效几何停止路由） | A-01 |
| 弹道注入 catalog 权威 + `state_source()`（不再静默 800 兜底） | A-01 |
| 玩家视图扣留 truth-only 字段（track vm/CICView），内部与存档不变 | A-01 |
| snapshot 静态字段来源块 | A-01 |
| scenario UTC 历元单一来源 + CR3BP 相位基准分离 | A-02 |
| 集中转换器双精度标量路径（EML1 速度 1.9e-5 → <1e-9 km/s） | A-02 |
| EventBus 版本化 state（整数契约/无派发导入/完整去重/上限拒绝） | A-03 |
| 旧档迁移「重放集合 ∪ 可见历史」（非尾部替换）+ 迁移报告 | A-04 |
| 传感器运行态持久化（控制/时钟/后端通道/分配器/去重）+ 静默重绑 | A-05 |
| `send_comms` 版本化 outcome + 重放逐项核对（原始失败保留、分歧拒绝） | A-06 |
| 长时存档成本标定（2.09 KB/op；load 1.1→50.2 s） | A-07 |

## 5. 明确未完成 / 未验证

- **不宣称全量零失败**：7 项 Phase 0 历史失败仍红；
- 身份/IFF/EW 与完整战斗未触及（后续工作）；
- 存档优化（checkpoint/压缩）**未实现**，A-07 只给预算建议与进入条件，数字**待负责人/Astra 冻结**；
- 未验证 Linux/macOS、非 headless 渲染、真实 RF/光学物理、>1000 tick 成本；
- DS-A-07 的三样本不足以声称 p95。
