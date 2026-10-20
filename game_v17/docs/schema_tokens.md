# 完整游戏-阶段0 · UI token / 数据 schema / loader

> 任务 完整游戏-阶段0（task-115）。工程 `game_v17`。
> 新文件（未改旧场景/HUD/transit/project；未 commit）：
> - `config/ui_tokens.json`
> - `config/schema/*.json`（10 个：entity/time/frame/order/comms/sensor_observation/track/save/story_state/ui_field）
> - `scripts/core/schema_loader.gd`
> - `scripts/core/ui_tokens.gd`
> - `tests/schema_probe.gd`（`PASS=422 FAIL=0`）
> - 本文件
> 不实现 UI/物理；只提供 token/数据 schema/校验基础。

## 1　文件与版本

| 文件 | schema | version | 说明 |
| --- | --- | --- | --- |
| `config/ui_tokens.json` | `v17.ui_tokens.v1` | `1.0.0` | UI token（字体/字号/行高/基线/间距/色板/9-slice/控件尺寸） |
| `config/schema/<id>.json` | `v17.schema.v1` | 各自 `1.0.0` | 10 个数据 schema（JSON Schema 风格 + example） |
| `scripts/core/schema_loader.gd` | — | — | 加载/校验/查询（只读） |
| `scripts/core/ui_tokens.gd` | — | — | token 查询（未知 token 报错） |

- 所有版本号 **semver**（`^\d+\.\d+\.\d+$`）；schema 文件必须有 `schema/id/title/version/type/required/properties/example`。
- schema id 规则 `^[a-z][a-z0-9_]*$`，跨文件唯一；示例 `example.id` 跨文件唯一（loader 检测重复）。

## 2　`ui_tokens.json` 内容

- `font_files`：`sans/mono/cjk` 字体文件路径（字符串，文件由后续 UI 资源提供）。
- `font_sizes`：档位 **7/8/9/11/14/18**（key 与值一致）。
- `line_heights`：各档行高（必须大于字号）。
- `baselines`：CJK/等宽字号、基线偏移 px、行距 px。
- `spacing`：面板 padding x/y、content_gap、line_gap、section_gap。
- `palette`：bg/panel/panel_border/text/text_dim/accent/warn/danger/ok/selection/transparent（hex）。
- `panel_9slice`：4 边 margin + content_margin。
- `button`：height/min_width/padding_x/padding_y/font_size。
- `target_card`：width/height/padding/font_size。
- `list`：row_height/header_height/padding_x/font_size。
- `dialog`：padding/min_width/min_height/font_size。
- `pointer`：size/hotspot_x/hotspot_y；`icons`：size_small/normal/large。

### 2.1　`ui_tokens.gd` API

| API | 说明 |
| --- | --- |
| `UITokens.new(path)` / `load_path(path)` | 加载并校验；`ready/errors/warnings/version` |
| `value(path_key, fallback)` | 点路径查询（`button.height`/`palette.text`） |
| `has(path_key)` | 静默存在性查询 |
| `font(name)` | 字体文件路径（sans/mono/cjk） |
| `font_size(size_key)` / `line_height(size_key)` | 字号/行高（7/8/9/11/14/18） |
| `baseline(kind)` / `line_gap(kind)` | cjk/mono 基线偏移/行距（px） |
| `padding(name)` | panel/button/card/dialog/list（Vector2） |
| `color(name)` | palette 颜色（Color；非法返回透明并报错） |
| `rect(name)` | target_card/dialog/button/icon_small/normal/large（Rect2） |
| `margin(name)` | panel 9-slice 边距 |
| `all()/to_dict()/reset()` | 全量/摘要/复位 |

**未知 token**：`push_error` + `errors` 追加 + `last_error` 文本，返回安全默认（0/透明/空 Rect2），
不静默忽略；`has()` 探测不会污染 errors。

## 3　数据 schema（10 个）

| schema | required 关键字段 | 说明/单位 |
| --- | --- | --- |
| `entity` | id/kind/side/name | kind=ship/station/tank/wreck/marker；pos_km(km)/vel_kmps(km/s)/size_km(km)；frame L1/L4/bary_rot/earth_eci |
| `time` | id/t_s/epoch/mode | t_s(s)/t_days(day)/epoch(s)/scale(none)/mode paused/running/window |
| `frame` | id/kind/origin/unit | kind inertial/rotating；origin barycenter/earth/moon/ship；unit km/m；rotation(deg/s) |
| `order` | id/ship_id/kind/status | kind move/sensor/comms/interact/hold；status queued/transmitted/active/done/aborted；delay_s(s)；sequence（number 数组，单位 none） |
| `comms` | id/from/to/mode/encrypted | mode radio/laser；latency_s(s)；frequency_mhz(MHz)；text |
| `sensor_observation` | id/observer_id/sensor/t_s | sensor radar/tws/optical/ir/elint/iff/comint；level(none,0–4)；bearing_deg(deg)/range_km(km)/snr_db(dB) |
| `track` | id/batch/entity_id/level/identity/threat | level(none,0–4)；identity friend/hostile/neutral/unknown/pending；threat none/pending/low/medium/high；age_s(s)；pos/vel；sources |
| `save` | id/version/scenario_id/t_s/entities/tracks/ui | 存档根；entities/tracks/ui 为 object/array；不存实现细节 |
| `story_state` | id/scenario_id/phase/flags/evidence/decisions | phase prelude/read/command/decision/consequence/report/end；t_s(s) |
| `ui_field` | id/token/label/value_type/source | value_type string/number/boolean/status/timestamp；source v15/v2/teaching/transfer/damage |

- 每个 schema 使用 JSON Schema 风格：`type/properties/required/enums/min/max/minItems/maxItems/unit` + `example`。
- **数值字段必须有 `unit`**；单位白名单：`none/km/km/s/s/day/deg/deg/s/dB/kg/m/MHz`。
- 示例必须通过本 schema（loader 加载时自动校验）。

## 4　`schema_loader.gd` 校验规则

加载 `config/schema/*.json`：

1. 文件可解析、schema marker=`v17.schema.v1`、id 合法且跨文件唯一、version semver、title 非空；
2. type/properties/required 合法；required 字段必须存在于 properties；
3. 属性类型合法；enum 非空且元素为标量；min/max/minItems/maxItems 数值合理；
4. 数值字段（number/integer/数组 of number）必须有合法 unit（白名单）；
5. `example` 通过本 schema（缺字段/类型/枚举/范围/单位错配均报错）；
6. 示例 `example.id` 跨文件唯一；重复 schema/example id 报错；
7. 全部错误写入 `errors`；`ready = errors.is_empty() && 存在 schema`；**不写 world/V15**。

### 4.1　API

| API | 说明 |
| --- | --- |
| `SchemaLoader.new(path)` / `load_all(path)` | 加载全部；返回 ready；`errors/warnings/schemas/ids` |
| `validate_schema_dict(s)` | 单 schema 校验（返回错误数组；供迁移/CI） |
| `validate_schema_dict_list(list)` | 批量 schema 校验 |
| `validate_collection(list)` | 跨文件重复 schema id / example id |
| `validate_instance(schema_id, data)` | 实例校验：`{ok, schema_id, errors}` |
| `validate_instance_against(schema, data)` | 直接对 schema 对象校验 |
| `schema(id)` / `example(id)` / `ids()` / `count()` / `to_dict()` / `reset()` | 查询/摘要 |

实例校验：required、类型、枚举、min/max、minItems/maxItems、数组元素类型；若实例包含
`<field>_unit` 且与 schema unit 不同 → 报错（明确单位错配）。

## 5　验证（最小 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/schema_probe.gd
# V17 SCHEMA PROBE RESULT: PASS=422 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：UI token 文件（version/字体/字号 6 档/行高/基线/间距/色板/9-slice/控件尺寸）；
token 查询（size/padding/line_height/baseline/color/rect/margin/value/has + 未知 token 报错且返回安全默认）；
10 个 schema 文件解析/format/version/id/required-properties/example；loader 加载（count=10、ids、
allowed_units、全部示例通过）；loader 拒绝（required 缺失、缺 unit、非法 unit、空 enum、示例缺字段/
非法枚举/类型错误/单位错配、重复 schema id/example id、非法 format/id/version/type）；
关键示例字段与单位元数据；JSON 回读（loader/tokens/全部 config JSON）。

## 6　版本 / 迁移规则（后续）

1. **加字段**：追加 property（非 required）→ 提升 schema `version` patch；示例补字段；loader 直接通过。
2. **新增必填字段**：提升 minor；必须提供迁移（旧数据补默认值/从旧字段推导）；否则旧 save 会校验失败。
3. **删除/重命名字段**：提升 major；提供字段映射（旧→新）与一次性迁移脚本；不静默丢数据。
4. **单位变更**：禁止静默改（同名字段换单位）；必须改字段名或 major 版本 + 显式换算迁移。
5. **枚举扩展**：追加枚举值 → minor；删除/重命名枚举值 → major。
6. **UI token 变更**：`ui_tokens.json` 版本提升；删除/重命名 token 视为 breaking（UI 会报 unknown token）；
   新增 token 兼容。颜色/尺寸调整属 patch。
7. Schema id 稳定；新增 schema 文件独立版本；loader 跨文件 id/示例 id 必须唯一。

## 7　边界 / 未完成

- 只提供 token/schema/loader/probe/文档；**不实现 UI、不改旧场景/HUD/transit/project**，不写 world/V15。
- schema 校验是轻量 JSON Schema 子集（不含 `$ref/oneOf/patternProperties` 等）；对象嵌套字段内部不再递归校验（按需后续扩展）。
- `ui_tokens.json` 字体路径为占位（实际字体由 UI 资源提供）；`ui_tokens.gd` 不加载字体。
- 未知 token 通过 `push_error` 报错并记录（便于开发期发现），生产 UI 应优先用 `has()` 探测。
- 旧存档/场景未迁移；未接存档读写；未跑全量回归；未 commit。
