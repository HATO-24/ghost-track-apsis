# R6 返修报告：#56 / #57 / #63（G0 候选）

> 分支 `jc/g0-integration`；本轮返修提交
> `f687ba1`（#56 G1/G2/G3）、`4fa9696`（#57 K0 + #63 P0 返修）
> 起点 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`；main 仍为 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`
> Godot `4.7.2.stable.official.ed1daf0bf`，Windows

## 一、#56 JC-A00 三项返修

### G1 只保存角度、跟踪目标/模式丢失 → 已修
- `mount_pointing` 现在保存 `pointing_mode` + `desired_target_id` + az/el，导入时校验（模式枚举、角度范围、kind 必须已存在）。
- 新增探针 `integration.jc_a00_sensor_state`：移动目标持续指向对照，**130 继续 tick 零分歧**（修复前恢复侧会因目标为空停止跟踪）。
- 结果：**28/0 PASS**。

### G2 导入半写 + 子状态校验不足 → 已修
- `sensor_authority.import_backend_state` 改为**两阶段**：先校验 optical / TWS / radar / authority 元数据全部通过，再统一提交；任何失败保持原状态（含子模块时钟）完全不变。
- 新增严格校验：精确整数 version（optical/TWS/radar 均补）、`scan_index` 安全整数范围（拒绝 1e100）、负时长拒绝、TWS 通道必需字段（`last_update_t`/`state`/`quality`/`target_id`）、缺 radar 子状态拒绝、光学 az/el 越界拒绝（不再 wrap/clamp 掩盖）。
- 探针覆盖 4 个原子性反例（坏 optical / 坏 TWS 通道 / `authority_t=Inf` / 缺 TWS 子段），断言**拒绝后全部时钟不变**。

### G3 比较器漏检 payload / 上下文 / 分配器 → 已修
- 事件：比较 `type/source/target/text_key/payload`（规范化 JSON，数值按值语义，消除 int→float 载体差异）。
- 观测：比较 `sensor/target_id/quality/range_km/bearing_deg`，不只 `event_id`。
- 通信：比较在途**完整记录**（正文/接收者/模式/路径/到达时刻）+ 事件流内容 + `_delivery_seq`；移除不存在的 `last_event()` 调用。
- 分配器：`bus._id_seq` 与 `comms._delivery_seq` 值必须一致（不只比大小）。
- 故障注入：`A07_FAULT_SAMPLE=<sample>` + `A07_FAULT_KIND=seen_ids|eta|comms_text`，三种真实篡改均由正常比较器发现并 **EXIT=1**；未注入对照 **27/0，EXIT=0**。

### #56 验收
```
R6 四规模基准：PASS 90/0，724s（12 样本全验，code SHA f687ba1）
1000 tick：UTF-8 2,172,752 B / save 中位 ~304 ms / 构造+恢复 49,078 ms / 读盘 4 ms
```
- 正确性全绿；**性能预算（#49：≤1,500,000 B / ≤250 ms / ≤5000 ms / ≤50 ms）仍不达标**，交 #49，未刷新阈值。

## 二、#57 JC-B00 K0 返修

| 返修项 | 实现 |
|---|---|
| 冻结 actor→controller→shooter 授权 | 每域 `authorized_actors`；actor 必须在名单内；controller 必须等于域直控；shooter 必须是该域实例；legacy 必须 `own_entity_instance_id` 且 `shooter==own`。**玩家填 ally_ai 直接 fire 盟军 → 拒绝** |
| 情报共享授权与延迟关系 | observer 必须是实例；owner 必须是某域 intel_owner；`share_authorized_by` 必须等于 owner；`received-observed` 必须与 `delay_s` 一致（≤1e-6 s） |
| 选择→部署映射、幂等键、roster/command_id | 实例显式 `selected`；只有 selected+DEPLOYED 可部署且必须逐一对应；`request_id` 唯一、冲突载荷拒绝；roster 必须引用本舰队实例；`command_id` 唯一 |
| 连续 vs 整数数值 | `mass_kg/fuel_kg/delta_v_kmps` 连续有限非负≤1e15；`ammo/cooldown_s_count` 真整数非负≤2^53-1；必要字段缺失即拒绝 |
| 冻结方案 | `intel_partitioning=per_owner_track_table`；`ai_read_view.reads_ground_truth=false` 且按域只读；`event_lifecycle` 6 阶段固定；`legacy_scope.own_ship_only=true` |

- 探针：`integration.jc_contracts` **64/0**；负例 fixture **17 个**，全部命中期望原因。

## 三、#63 JC-B03P P0 返修

| 返修项 | 实现 |
|---|---|
| 真实 canonical 舰级 | 只读 `ships_friendly.json` / `ships_enemy.json` 校验；命名舰用 `entity_bindings`（apsis→OCUVF-APOGEE）；**APSIS/HARMATTAN 不再当 class_id** |
| 容量与预算实际生效 | 点数公式 `round(displacement_t/60)`；FORM-SENSOR 25 点/3 舰、FORM-STRIKE 55 点/3 舰；探针断言超容量/超预算拒绝 |
| 目标/终态自洽 | **零完成→defeat**（不是 stalemate）；时限永不产生胜利；同 tick 优先级 `defeat>victory>withdrawal>stalemate`，只结算一次；每条轨迹唯一 `decision_id` |
| 权威 vs 玩家视图 | 每条轨迹分别给 `expected_authority` 与 `expected_player_report`；已失能未报告 = 权威 `in_progress` / 玩家 `unknown` |
| 贡献语义 | 玩家直控/授权请求计玩家贡献；友军自主不计；**AI 不得包干首胜**；无操作按 timeout 结算 |
| 失能机制 | 每目标给出 `disable_mechanism` + `mechanism_dependency` + `mechanism_alternative`（临时压制不计永久失能） |
| 保护对象绑定 | `PROT-1→SECTOR-RELAY-CIV`（被毁 defeat）、`PROT-2→I-A1`；民用设施不得作为攻击/胜利对象 |

- 探针：`integration.jc_scenario_spec` **190/0**；含 3 个负例变体（未知舰级 / 超指挥容量 / 胜利轨迹缺失能事件）。

## 四、C 回归（head `4fa9696`）

```
Phase 0 gate:  6/6 PASS
Phase A gate:  3/3 PASS
Full matrix:   87 = 80 PASS / 7 FAIL / 0 TIMEOUT / 0 NOT RUN
BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```

- 矩阵 87 = 原 84 + `jc_contracts` + `jc_scenario_spec` + `jc_a00_sensor_state`；
- 7 项历史失败保持原状，未登记新增、未刷新 baseline。

## 五、命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '^integration\.jc_contracts$'        -Ci -ResultsDir .test-results/jc-r2/JC-B00/r6d
pwsh -NoProfile -File ./run_tests.ps1 -Only '^integration\.jc_scenario_spec$'    -Ci -ResultsDir .test-results/jc-r2/JC-B03P/r6d
pwsh -NoProfile -File ./run_tests.ps1 -Only '^integration\.jc_a00_sensor_state$' -Ci -ResultsDir .test-results/jc-r2/JC-A00/r6/probe

# 故障注入（期望非零）
$env:A07_SCALES="50"; $env:A07_FAULT_SAMPLE="1"; $env:A07_FAULT_KIND="seen_ids"   # EXIT=1
$env:A07_FAULT_KIND="eta"                                                          # EXIT=1
$env:A07_FAULT_KIND="comms_text"                                                   # EXIT=1
Remove-Item Env:A07_FAULT_SAMPLE,Env:A07_FAULT_KIND; $env:A07_SCALES=""            # 对照 27/0 EXIT=0

# 四规模基准
$env:A07_HEAD = (git rev-parse HEAD).Trim()
pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/jc-r2/JC-A00/r6/benchmark
```

## 六、仍未完成 / 待复核

- G0、K0 仍需 Sol 独立复核；本报告不自行宣告放行；
- P0 的内容选择（战区命名、点数公式、失能阈值、结算口径）待用户核对；
- #58–#62 仍未解锁；
- 性能预算不达标（#49 保留）。
