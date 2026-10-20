# 完整游戏-阶段2D · 紧凑星历接口（JPL 派生格式 / 无表回退）

> 任务 task-122。工程 `game_v17`。**只新增 4 个文件**：
> `framework/sim/ephemeris_compact.gd`、`tests/ephemeris_compact_probe.gd`、
> `docs/ephemeris_compact.md`、`data/ephemeris/README.md`。
> 未改旧 HUD/state/bridge/core/sim/project；不接 UI/物理；不写 world/V15；未 commit。
>
> **仓库不附带 JPL 数据，不生成/伪造 JPL 数据。** 本接口只定义、校验、读取
> “JPL 派生紧凑表”；无表时明确 `available=false` 并使用解析地球/月球参考。

## 1　定位

`V2CompactEphemeris`（`framework/sim/ephemeris_compact.gd`）是**只读**星历接口：

- **有表**：读取 `data/ephemeris/*.json`，校验 schema/source/version/frame/units/
  time_window/bodies；时间窗内 Chebyshev/Kepler 插值，返回位置/速度/误差/来源元数据。
- **无表**：`available()==false`、`using_analytic_fallback()==true`，用
  `cislunar_physics` 的解析地球/月球参考（earth_eci）；返回 `analytic_fallback=true`，
  **不冒充 JPL**。
- **非法表**：拒绝（`errors`），不静默使用；仍可 analytic fallback 查询。
- API：`load()`、`available()`、`body_state(id,t)`、`bodies()`、`errors/warnings`、
  `to_dict()`；另提供 `validate_table()` / `load_data()`（测试夹具/内存表）。
- 单位 km / km/s / s；frame 支持 `earth_eci` / `bary_rot` / `earth_rot`。

## 2　表格式 `v17_compact_ephemeris.v1`

完整示例与数据放置规则见 [`data/ephemeris/README.md`](../data/ephemeris/README.md)。

```json
{
  "schema": "v17_compact_ephemeris.v1",
  "source": {
    "provider": "JPL", "derived_from": "DE440（派生工具/版本）",
    "kernel": "de440.bsp", "license": "数据许可", "generated_at": "ISO8601",
    "generator": "生成器", "checksum_sha256": "可选"
  },
  "version": "table-1.0",
  "frame": "earth_eci",
  "units": {"length": "km", "time": "s", "velocity": "km/s", "angle": "rad"},
  "time_scale": "TDB",
  "time_window": {"start_s": 0.0, "end_s": 86400.0},
  "bodies": {
    "moon": {
      "body_id": "301", "center": "earth",
      "interpolation": "chebyshev", "max_error_km": 0.02,
      "segments": [
        {"t0": 0.0, "t1": 86400.0, "order": 8,
         "coeffs": {"x": [], "y": [], "z": []}}
      ]
    },
    "earth": {
      "body_id": "399", "center": "ssb", "interpolation": "kepler",
      "max_error_km": 0.01,
      "kepler": {"a": 7000.0, "e": 0.001, "i": 0.0, "raan": 0.0,
        "argp": 0.0, "M0": 0.0, "n": 0.001, "epoch_s": 0.0,
        "mu_km3_s2": 398600.4418}
    }
  }
}
```

### 2.1 必填校验

| 字段 | 校验 |
| --- | --- |
| `schema` | 必须 `v17_compact_ephemeris.v1` |
| `source` | 对象；`provider/derived_from/license/generated_at` 非空（审计；测试夹具写 TEST_FIXTURE，不得冒充 JPL） |
| `version` | 非空 |
| `frame` | `earth_eci` / `bary_rot` / `earth_rot` |
| `units` | `length=km`、`time=s`、`velocity=km/s` |
| `time_window` | 有限 `start_s<end_s` |
| `bodies` | 非空；每 body 有 `body_id`；`interpolation∈{chebyshev,kepler}` |
| Chebyshev | `segments[]`：`t0<t1`、`order≥1`、`coeffs.x/y/z` 至少 2 项且有限 |
| Kepler | `a>0`、`0≤e<1`、`i/raan/argp/M0/n/epoch_s` 有限 |
| `max_error_km` | 可选；若给必须 ≥0 |

非法表 → `load_data/load` 返回 false，`errors` 记录具体原因，`available=false`；
不会把坏表当有效表使用。

### 2.2 插值

- **Chebyshev**：`tau=(2t-t1-t0)/(t1-t0)`，`pos=Σ c_k T_k(tau)`；
  `vel=(dpos/dtau)·2/(t1-t0)`（Chebyshev 导数首项按半处理）。
  选择覆盖 t 的 segment；无覆盖即 `out_of_time_window`。
- **Kepler**：由 `a,e,i,raan,argp,M0,n,epoch_s` 解 Kepler 方程；
  输出地心惯性位置/速度（rad、km、km/s）。
- `body_state()` 返回 `max_error_km/source/source_meta/table_path`；
  无表 analytic fallback 下 `max_error_km=-1` 并明确 `analytic_fallback=true`。

## 3　API

```gdscript
const Eph := preload("res://framework/sim/ephemeris_compact.gd")
var e = Eph.new()                 # 默认扫描 res://data/ephemeris
e.load(path := "")                # 目录或单文件；无表 analytic fallback；返回 available
e.available() -> bool
e.using_analytic_fallback() -> bool
e.bodies() -> Array
e.body_state(id: String, t: float) -> Dictionary
e.validate_table(data) -> {ok, errors[]}
e.load_data(data, source_name := "<memory>") -> bool   # 测试夹具/内存表
e.to_dict() / e.summary() / e.to_json()
e.errors / e.warnings
```

`body_state()` 成功返回：

```text
{ok,schema,body,body_id,t,frame,units,time_scale,
 position_km[3],velocity_kmps[3],speed_kmps,
 interpolation,max_error_km,source,source_meta,table_path,available,
 analytic_fallback,writes_v15:false}
```

失败 reason：`unknown_body`、`out_of_time_window`、`non_finite_time`、
`unsupported_interpolation`。

## 4　无表回退

- `available()==false`，`using_analytic_fallback()==true`；
- `bodies()` 返回 `earth`(399)/`moon`(301)，`interpolation="analytic"`；
- `earth`：earth_eci 原点 `[0,0,0]`，速度 0；
- `moon`：`cislunar_physics.moon_state_eci(t)` 的解析参考；
- 所有返回带 `analytic_fallback=true`、`available=false`、`source=analytic_*`；
- `warnings` 含 `NO_EPHEMERIS_TABLE` / `ANALYTIC FALLBACK`；
- 查询任意 t（analytic 时间窗无界）；不写 V15/world。

## 5　接入 world / 其他系统（本任务不接）

建议只读适配：

```gdscript
# world/sim 读取体位置时
var st = eph.body_state("moon", sim_t)
if bool(st.get("ok", false)):
    # 使用 st.position_km / velocity_kmps；不要写回 Eph
```

- 星历只作为参考数据源；不得由 Eph 直接改 world/TrackTable/V15。
- 若上层需要 `bary_rot`，表内 frame 必须明确；Eph 不在内部换帧，避免静默变换。
- 存档仅保存表路径/版本/校验结果，不复制表内容。

## 6　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ephemeris_compact_probe.gd
# EPHEMERIS COMPACT PROBE RESULT: PASS=138 FAIL=0
# EPHEMERIS COMPACT PROBE OK（退出码 0）
```

覆盖（138 checks）：
- **无表**：ready、available=false、analytic fallback earth/moon、位置/速度、
  frame/units、未知 body、非有限 t、warnings、JSON、不写；
- **非法表**：坏 schema/缺 source/version/frame/units/time_window/空 bodies/
  非法 interpolation/缺 coeffs/coeffs 过短/Kepler 坏 e；全部拒绝并保留 fallback；
- **合法 Chebyshev**：t=0/50/100 位置、导数速度、speed、时间窗外
  `out_of_time_window`、unknown_body、JSON、确定性；
- **Kepler**：半径范围/速度、确定性、units/frame/零宽窗口拒绝；
- **文件加载**：`user://` 临时合法表、非法 JSON 拒绝、默认无表 available=false、
  默认 source=analytic（不冒充 JPL）；
- **确定性/只读**：同表同查询逐字节一致；to_dict/summary JSON；writes=false。

## 7　边界 / 未明确

- **不附带、不生成、不伪造 JPL 数据**；仓库只有格式/README/接口。
  真实表须由有权限的 JPL 派生数据生成，并填 `source` 审计字段。
- 不做 SPK/PCK/BSP 解析，不做 JPL kernel 读取；只读预先派生的紧凑表。
- 不做坐标变换：表 `frame` 原样暴露，调用方自行转换。
- 不做长期传播：超出 `time_window` 明确失败，不插值外推。
- 精度仅来自表内 `max_error_km`（作者声明）；本接口不重新计算 JPL 误差。
- Kepler 仅两体惯性状态，不含摄动；Chebyshev 段边界连续性由派生数据保证。
- 未接入 world/HUD/plot/bridge，不写 V15；未做存档/热重载/表签名验证
  （`checksum_sha256` 仅格式位，当前未在服务内校验）。
- 未跑全量回归；只单次跑本 probe。
