# 设施 3D 模型映射 / FACILITY MODEL FACTORY（方案B-35 task-211）

## 文件

- `scripts/ui/facility_model_factory.gd`：FacilityRegistry/facility dict → station_model 基型。
- `tests/facility_model_probe.gd`：110 设施逐一探针（300+ 检查）。
- `scripts/ui/near_view.gd`：NEAR VIEW 改用 factory。
- 数据：`framework/content/facilities_system.json`（29 base + 19 OTC + 62 fuel = 110）。

## 映射表

| facility_class | station_model 基型 | 说明 |
|---|---|---|
| station | port | 港/站点基型 |
| port | port | 港口 |
| depot | depot | 仓库/补给站 |
| otc | otc | OTC 交通管制卫星（碟形+环+板） |
| tank | tank | 储罐 |
| fuel | fuel | 加注/燃料区 |
| relay | otc | 中继（OTC 类基型） |
| research | research | 研究环 |
| commercial / logistics / industrial / shipyard / observation / residential / agricultural / water_utility / salvage / food_processing / cultural / tourism | port/depot/tank/research/port | 内容其他 class 的基型映射 |

未知 class：fallback `port`，metadata `facility_model_fallback=true`，并在描述中标注 `→fallback/port`；不伪装为独立美术。

## 尺度 / 模块

- `scale = base_scale(model_type) × clamp(0.82 + ln(1+radius_km)×0.22, 0.82, 1.35)`，clamp 0.55..1.65。
- base_scale：port 1.15、depot 1.05、otc 0.82、tank 0.72、fuel 0.78、research 0.92。
- `module_count = base_modules + int(min(3,radius_km))`，clamp 2..8。
- 300+ probe 验证 scale/module 范围、模型非空、meta、确定性。

## Probe 结果（headless）

- Registry：total=110（base 29 + OTC 19 + fuel 62）。
- Mapped=110，classes=20；model buckets：port 12、depot 8、otc 21、research 4、tank 34、fuel 31。
- `checks=1697 fails=0 fallbacks=0`；“unknown class fallback”独立测试通过。
- 命令：`--headless --path game_v17 --script res://tests/facility_model_probe.gd`；退出码 0。

## NEAR VIEW 接入

- NEAR VIEW 选中设施时用 `FacilityModelFactory.create(facility)`；info 显示 SCALE/MODULES/MAPPING/FALLBACK。
- 无选中设施默认 L1 PORT；Earth/Moon 仍走 planet 模型；8 类按钮切换使用同一 factory。
- 截图重截：`mockups/v1-hud-nearview-facility-1920.png`（Chronos/depot，mapping depot→depot）；1600 布局 `v1-hud-nearview-1600.png`。

## 边界

- 全部设施共享 6 个基型，不是每设施独立美术网格；纯色 StandardMaterial3D、无贴图。
- 近景为只读 UI 展示；不读 truth 位置、不写 world/physics/session。
- 待未来替换：独立高模/贴图/LOD；保留 factory API 即可切换。


---

## B-36 空间站基型更新（task-213）

- station_model 6 基型已按 ISS/天宫参考重做：
  - port：核心舱 + 节点舱 + 径向实验舱 + 分段太阳翼 + 多向对接 + 桁架/散热器；
  - depot：核心 + 长桁架 + 货舱/储罐 + 太阳翼；
  - otc：天线转台 + 碟形天线 + 相控阵 + 太阳翼；
  - tank：桁架 + 多圆柱储罐 + 管线；
  - fuel：储罐 + 加注臂/喷嘴；
  - research：实验舱 + 暴露平台 + 散热器 + 太阳翼。
- FacilityModelFactory 的 class→基型映射/尺度/probe 不变；110 设施仍全部映射到 6 基型。
- NEAR VIEW 已改用新模型并重截 `mockups/v1-hud-nearview-facility-1920.png`（Chronos/depot）。
- 纯色 StandardMaterial3D；无贴图；仍是过渡资产，不是每设施独立美术网格。


---

## B-37 居住站映射（task-214）

- Factory 新增 `habitat_type/model_family` 输出；特殊大型站不再使用模块站：
  - L5-07 Savannah / L5-01 Eko / L3-01 Aurora → `oneill`（O'Neill 双圆柱）；
  - NESOSS-05 Saturnus → `stanford`（Stanford 环面）。
- 小 station/port/depot/otc/tank/fuel/research 继续 station_model 6 基型。
- 未知居住类设施（residential/tourism/agricultural/habitat，radius≥2.0）按半径 fallback：≥3.2 oneill，否则 stanford，并标注 `habitat_fallback`。
- near_view 显示 habitat 模型与 `MODEL habitat_model.gd / oneill|stanford`、ID/CODE；Savannah 截图 `mockups/v1-hud-nearview-savannah-1920.png`。
- Festival 模型预览截图 `mockups/models-habitats-lore-1920.png`。
- 仍为纯色过渡资产；不复制现实实体；110 设施 probe 仍通过（checks=1697）。


---

## B-38 小行星居住站映射（task-217）

- B-38 曾把大型 lore 站映射为含内部 O'Neill/Stanford 的小行星站；B-40 已撤销该拼合，改为四类独立，见下节。
- 小型 station/port/depot/otc/tank/fuel/research 继续模块站。
- Factory 输出新增 `asteroid_type/asteroid_known/asteroid_fallback`；未知大型居住站按半径 fallback（≥3.2 oneill，否则 stanford）并标注。
- 近景 NEAR VIEW 自动使用小行星/舰船模型：选中舰船（无 facility_id）时由 near_view 读取 v1_hud 选中 contact 并构建 ship_model；无选中设施默认 L1 PORT。
- 截图：`models-asteroid-habitats-1920.png`、`v1-hud-nearview-savannah-1920.png`。
- 110 设施 probe 仍通过（checks=1697, fails=0）。


---

## B-40 四类独立匹配（task-220）

`framework/content/habitat_profiles.json` 提供 known/class-default 的人口/资源/功能，Factory 自动匹配：

| 族 | 当前数量 | 代表设施 | 场景 |
|---|---:|---|---|
| O'Neill | 3 | Savannah / Eko / Aurora | `oneill_cylinder.tscn` |
| Stanford | 1 | Saturnus | `stanford_torus.tscn` |
| Asteroid Habitat | 1 | Victoria（外环小行星） | `asteroid_habitat.tscn` |
| UEG Asteroid Fortress | 1 | Horizon（L2-07，military） | `asteroid_fortress.tscn` |
| Module Station | 104 | Greenwich/Chronos/… | `station_model.gd` |

匹配顺序：military → fortress；known profile 优先；小型模块 class → module_station；人口≥200k→oneill；10k–199999→stanford；<10k/low resource→asteroid_habitat。Factory 输出 `model_family/family_reason/population/resources/function/profile_source`。

- 小行星居住站不再含 O'Neill/Stanford 内部（仅隧道/小舱段）；要塞为民用之外的独立军用族。
- 近景截图：Savannah/Eko/Aurora（O'Neill）、Saturnus（Stanford）、Victoria（asteroid_habitat）、Horizon（fortress）。
- 边界：profile 是视觉匹配元数据，不是 gameplay 人口/资源模拟；104 小站保持模块站；纯色/无贴图。
