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
