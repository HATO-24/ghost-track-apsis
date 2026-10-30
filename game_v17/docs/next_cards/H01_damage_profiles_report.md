# H01 / #45：舰级档案映射与三 case 红→绿交付报告

> 执行卡：[DeepSeek][历史失败][H01] 舰级/毁伤档案与缺档案语义 [#45](https://github.com/HATO-24/ghost-track-apsis/issues/45)。
> 开工基线：main `018bd4d0adc882a9123210f022fe8b7c71f68c06`（含 D1 PR75、PR74/76 合入）。
> 代码修复提交：`236826f61fc092a8737ca855943b76c0882813b9`；baseline 独立提交：`cd6883b0991d4aae0b6f1582f2cf63ccfb6f7263`。**最终报告/证据提交后的 40 位 HEAD 以 PR/回报为准**。
> 平台：Windows / Godot `4.7.2.stable.official.ed1daf0bf` / headless。错误基线记录在 `.test-results/next-cards/H01/red/20261030-141548-018bd4d0`。

## 1. 三 case 归因与真实红

| case | 红结果（同一 018bd4d0 基线） | 真实根因 | 非根因/不采用 |
|---|---|---|---|
| `content.damage_profile_probe` | 554 PASS / 4 FAIL，exit 1；另有 **4 条 SCRIPT ERROR** | `damage_profile_service.gd:208` 用 `String(r.get("batch"))` 转换整数 batch（如 1001），触发 `Invalid call 'String' constructor: 2001`，函数在实体/hull 查找前中止，`harmattan` 等实体落回默认 `UEOF-7TH-DD`；同时 probe 把 36 个档案与 32 个基础 class 直接比较，忽略了 4 个 UEOF 变体 archetype | 不把 32 改成 36 了事；不删除仍被 ORBFLT U7/U3 变体引用的 UEOF 档案 |
| `integration.damage_integration_probe` | 198 PASS / 6 FAIL，exit 1 | FERRY=HEMATITE 现已有 `damage_l1` 完整模型与 HEMATITE 档案；旧测试仍把 FERRY 当“无档案”，用未注册语义的负例 | 不把 ferry 档案删掉、不伪造“无档案” |
| `integration.v17_nav_integration_probe` | 181 PASS / 1 FAIL，exit 1 | 与上一项同一契约：旧测试用 FERRY 当无档案实体 | 不重写导航；只替换负例 fixture |

## 2. 真实修复

### 2.1 SCRIPT ERROR（`damage_profile_service.gd`）

`_resolve_catalog_class` 的字段构造改为 `str(...)`，可在 batch/hull_code 为数字时安全转换；实体/大小写/hull 查找恢复：

- `harmattan` → `OCUVF-PALLET-5C`
- `HARMATTAN` → `OCUVF-PALLET-5C`
- `apsis` → `OCUVF-APOGEE`
- `CA-4471` → `33OSID-ENFORCEMENT`

修复前 stderr 4 条 SCRIPT ERROR，修复后 stderr **0 条**（`red/script-errors.txt`、`final/logs/*.stderr.log`）。

### 2.2 档案/舰级映射契约

- 批准内容为 **36 档案 = 32 基础舰级（友8+敌24）+ 4 UEOF 变体 archetype**；4 个 UEOF 档案并非独立 ShipCatalog class，而是 `ORBFLT` 的 U7/U3 `operator_variants` 的 `damage_profile_class_id`。
- 因此 probe 的 parity 断言改为 **ShipCatalog 基础 class + variants 的 damage_profile_class_id** 的并集（36），并核对 `catalog+variant == profile`；不再把 36 与 32 直接比较，也不删除合法变体档案。
- `damage_profiles.json` 只更新 title/source 说明（36 的组成），**未改任何 class/profile 数值，未改 ShipCatalog，未改 damage_l1**。

### 2.3 缺档案负例改用真正未注册 fixture

新增 `game_v17/tests/fixtures/damage_profile/unregistered_entity.json`：`unregistered_hulk` / `UNREGISTERED-TEST-HULL`，不在 ShipCatalog、damage_l1、damage_profiles 中。

- 修复前：FERRY 被当成缺档案实体；修复后：FERRY 断言为**有 HEMATITE 档案**的正例。
- `unregistered_hulk`：
  - world/damage model 为 null；
  - `damage_apply_hit` 返回拒绝（`无完整损管模型`）；
  - 拒绝后模型/`vm_damage_full`/资源仍为空，**无部分伤害/错误扣资源**；
  - 在 damage_profile probe 中作为未知实体/未知 class 的只读 fallback 断言（默认 `ORBFLT-SENTINEL` 回退，不伪造档案）。

## 3. 红→绿计数

| 阶段 | 命令（摘要） | 结果 |
|---|---|---|
| 红 | `run_tests.ps1 -Only 'damage_profile\|damage_integration\|v17_nav_integration' -Ci` | 3 case：PASS 0 / FAIL 3；`554/4`、`198/6`、`181/1`；exit 1；stderr SCRIPT ERROR 4 |
| 绿（专项） | 同上，修复后 | 3 case：PASS 3 / FAIL 0；`562/0`、`215/0`、`185/0`；exit 0；SCRIPT ERROR 0 |
| 共同 C | `run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json` | total=92，pass=88，fail=4（剩余历史）；`known_fail=4 new_fail=0 drift=0 unverified=0 unselected=0 complete=true`；exit 0 |
| Phase 0 | `-Gate phase0` | 6/6 PASS，exit 0 |
| Phase A | `-Gate phaseA` | 3/3 PASS，exit 0 |

剩余 4 项历史失败严格保留：`content.story_text_probe 469/13`、`unit.incident_record_probe 2761/1`、`integration.plot_tws_probe 58/1`、`integration.v17_sensor_authority_display_probe 71/3`。baseline 只删除了本卡证实的 3 项（`content.damage_profile_probe`、`integration.damage_integration_probe`、`integration.v17_nav_integration_probe`），见独立提交 `cd6883b`；其余未动。

## 4. 保存/读取与 product smoke

共同 C 中以下既有覆盖全部 PASS（不是本卡新增，但保留）：

- `unit.save_probe`、`integration.a0_save_roundtrip_authority`、`integration.a0_legacy_save`、`integration.a0_event_continuity`；
- `e2e.orbital_sim`、`boot.full`、`boot.orbit_sim`、`boot.sandbox`、`boot.legacy_combat_sim`；
- 合法命中一次由 `integration.damage_integration_probe`（215/0）与全 C 覆盖；未知 class、错 ID、重复 shot 的既有拒绝断言保持通过。

## 5. 范围/非范围

- 只改：`damage_profile_service.gd`、`damage_profiles.json`（仅说明文本）、三 probe、未注册 fixture、baseline 三条记录。
- **未实现/未改**：编组扩展、11 舰部署、AI、UI、新弹种（E-AMMO-00 另登记）、B1b 战斗、舰队数值、正式 scenario/K0 迁移；低质量仍可射击、固定 EW/通信夹具未动。
- 未提交临时脚本、`.import`/`.uid` 生成物；未跑无关游戏试玩/性能。
- 最终 PR 由 DeepSeek 分支提交，交 Sol 独立复核；不自行合并/不启动下一卡。

## 6. 证据

- `game_v17/docs/next_cards/evidence/h01/red/`：原始红 summary/report/logs、`script-errors.txt`（4 条）
- `game_v17/docs/next_cards/evidence/h01/final/`：修后专项 summary/report/logs（562/0、215/0、185/0；stderr 无 SCRIPT ERROR）
- `game_v17/docs/next_cards/evidence/h01/full/`：共同 C summary/report（92=88/4，new_fail=0，complete=true）
- `game_v17/docs/next_cards/evidence/h01/gates/`：Phase0/PhaseA summary（6/6、3/3）
- `game_v17/tests/fixtures/damage_profile/unregistered_entity.json`：未注册 fixture
