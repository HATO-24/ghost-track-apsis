# data/ephemeris · 紧凑星历表目录（不附带 JPL 数据）

本目录**默认不包含任何星历表**。`game_v17/framework/sim/ephemeris_compact.gd` 在
找不到 `.json` 表时会明确返回 `available=false`，使用解析地球/月球参考
（`earth_eci`，标记 `analytic_fallback`），**不伪造 JPL 数据**。

## 放置真实数据

将 **已获授权、由真实 JPL 星历（如 DE440/DE441）派生** 的紧凑表放入本目录，
例如 `de440_compact_1960_2025.json`。格式见下。只放你有权分发/使用的数据；
仓库不包含任何 JPL kernel/系数副本。

## 表格式 `v17_compact_ephemeris.v1`

```json
{
  "schema": "v17_compact_ephemeris.v1",
  "source": {
    "provider": "JPL",
    "derived_from": "DE440 (说明派生方式/工具版本)",
    "kernel": "de440.bsp",
    "license": "数据许可/使用范围说明",
    "generated_at": "2025-01-01T00:00:00Z",
    "generator": "工具名/版本",
    "checksum_sha256": "可选：本文件 sha256"
  },
  "version": "table-1.0",
  "frame": "earth_eci",
  "units": {"length": "km", "time": "s", "velocity": "km/s", "angle": "rad"},
  "time_scale": "TDB",
  "time_window": {"start_s": 0.0, "end_s": 86400.0},
  "bodies": {
    "moon": {
      "body_id": "301",
      "center": "earth",
      "interpolation": "chebyshev",
      "max_error_km": 0.02,
      "segments": [
        {
          "t0": 0.0,
          "t1": 86400.0,
          "order": 8,
          "coeffs": {
            "x": [/* Chebyshev 系数，T0..Tn */],
            "y": [/* ... */],
            "z": [/* ... */]
          }
        }
      ]
    },
    "earth": {
      "body_id": "399",
      "center": "ssb",
      "interpolation": "kepler",
      "max_error_km": 0.01,
      "kepler": {
        "a": 7000.0, "e": 0.001, "i": 0.0,
        "raan": 0.0, "argp": 0.0, "M0": 0.0,
        "n": 0.001, "epoch_s": 0.0, "mu_km3_s2": 398600.4418
      }
    }
  }
}
```

- `frame` 仅支持 `earth_eci` / `bary_rot` / `earth_rot`。
- `units` 必须 `km / s / km/s`；角度 `rad`。
- `interpolation` 仅支持 `chebyshev` / `kepler`。
- Chebyshev：`segments[].coeffs.x/y/z` 至少 2 项、有限、`order` 与数组长度一致更好；
  `t0<t1`，段落在 `time_window` 内；速度为 Chebyshev 导数（km/s）。
- Kepler：`a>0`、`0≤e<1`、`n` rad/s、`epoch_s` 秒；输出地心惯性位置/速度。
- `source` 必须可审计：`provider/derived_from/license/generated_at`。
  写入 `provider:"JPL"` 时请确保文件确实是 JPL 派生数据；测试夹具请写
  `provider:"TEST_FIXTURE"`，不要冒充 JPL。
- 服务会校验 schema/source/version/frame/units/time_window/bodies；
  非法表拒绝并写 `errors`，不静默使用。

## 无表行为

- `available() == false`，`using_analytic_fallback() == true`；
- `body_state("earth", t)`：地心 ECI 原点 `[0,0,0]`；
- `body_state("moon", t)`：`cislunar_physics.moon_state_eci(t)` 解析参考；
- `warnings` 含 `NO_EPHEMERIS_TABLE` / `ANALYTIC FALLBACK`；
- 返回 state 带 `analytic_fallback=true`、`available=false`、`source=analytic_*`。

## 生成/校验建议

1. 从真实 JPL 派生数据生成表（记录工具、版本、派生时间、单位）；
2. 独立计算已知采样点误差，填 `max_error_km`；
3. 用 `ephemeris_compact.gd::validate_table`/probe 验证；
4. 记录许可证；不要提交无授权数据。

本 README 不是数据许可文件；实际数据许可以表内 `source.license` 为准。
