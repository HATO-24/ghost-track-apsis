# 完整游戏-阶段4I · CICView 可观测信息层

> 任务 task-198。工程 `game_v17`。
> 新文件：`scripts/core/cic_view.gd`、`tests/cic_view_probe.gd`、本文件。
> 不改其他；不写 TrackTable/world/UI/V15；未 commit。

## 1　定位 / 契约

CICView 是 **CIC 可观测信息层**：把 TrackTable 的融合结果、ownship/observer 状态、
FacilityRegistry 已知设施和 track metadata 组合成只读视图。

**硬契约**：

- `truth = false`（view 与 track/facility/ownship 行均标 `truth=false`）；
- `writes = {track_table:false, world:false, ui:false, physics:false, v15:false}`；
- **不读 PhysicsWorld truth / 不读真实实体坐标**；本层只使用输入 TrackTable/ownship/
  注册表/metadata；
- **L1 不给位置**：只有 `bearing_ray`（origin/bearing/cone），`range_km=null`，
  没有 `estimate_km/position_km/uncertainty_km/position_source`；
- L2/L3/L4 的位置是 **由 ownship+bearing+range 计算的估计**（`position_truth=false`），
  不是 truth；缺 bearing/range/ownship 时不出位置；
- 输出所有数组/字典为副本，输入不被修改。

## 2　输入

```gdscript
CICView.new({
  "track_table": TrackTable,          # 或 "track_table_vm": {...}
  "ownship": {"id":"apsis", "pos_km":[x,y,z], "heading_deg":0.0},
  # 兼容 "observer"
  "facility_registry": FacilityRegistry,   # 或 "facilities":[...]
  "metadata": {"T0001": {"known":true, "entity_id":"ceres_2",
                          "facility_id":"L1-05"}}
  # 可选 config：base_cone_deg/quality_cone_deg/age_cone_deg_per_s/
  # base_uncertainty_km/range_uncertainty_factor/quality_penalty_km/
  # age_penalty_km_per_s/max_uncertainty_km/stale_after_s
})
```

- TrackTable VM 需含 `t` 与 `tracks[]`；track 字段可含
  `id/batch/entity_id/level/bearing_deg/range_km/quality/last_update/sources/
  identity/threat/evidence/stale/known`。
- metadata 可按 track id 或 entity_id 索引；`known/entity_id/facility_id`
  只来自 metadata/TrackTable 可观测字段，**不使用输入里的 truth 字段**。
- 设施位置来自 FacilityRegistry 的 `physical.orbit.position_km` 或 `pos_km`；
  注册表已知设施输出 `known=true`，但仍是可观测/档案数据，不是实时 truth。

## 3　输出（schema `v17.cic_view.v1`）

```text
{
  schema, ready, t, truth:false,
  writes:{track_table:false,world:false,ui:false,physics:false,v15:false},
  ownship:{id,known:true,pos_km,heading_deg,truth:false},
  facilities:[{facility_id,facility_code,name,cluster_id,known:true,pos_km|null,truth:false}],
  tracks:[{
    id,batch,entity_id,facility_id,known,
    level(1..4),level_name,level_label,
    identity,threat,quality,confidence,age_s,stale,sources,truth:false,
    bearing_deg|null, range_km|null,
    bearing_ray:{origin_km,bearing_deg,cone_deg,range_km:null,truth:false}|null,
    uncertainty_deg,
    # L2+ 且 bearing/range/ownship 有效时：
    estimate_km,position_km,uncertainty_km,position_source,position_truth:false,
    # L3/L4：
    evidence:[...],
    reason  # missing_bearing/missing_range
  }],
  summary:{tracks,levels{1..4},known,stale,with_position,bearing_only,
           missing_geometry,facilities,ownship_known,truth:false}
}
```

- **方位约定**：`bearing_deg` 归一化 0..360；北=+Y、顺时针为正；
  `x = own.x + r·sin(bearing)`，`y = own.y + r·cos(bearing)`，
  `z = own.z + r·sin(elevation)`（无 elevation 时 0）。
- **L1**：`bearing_ray` 的 origin 为 ownship；`cone_deg` 随质量/年龄变宽；
  `range_km=null`，无位置字段。
- **L2**：`estimate_km`/`position_km` 为局部估计；`uncertainty_km =
  base + range·range_factor + (1-quality)·quality_penalty + age·age_penalty`，
  夹在 `max_uncertainty_km`；`confidence=quality`。
- **L3/L4**：保留身份/威胁/证据；有 bearing/range 时同样给估计位置，但不声称 truth。
- 缺 `bearing_deg` 或 `range_km`、或无 ownship 时不生成位置，给 `reason`。
- `age_s` 优先取 track.age，否则 `vm.t - last_update`；`stale` 取 track 或
  age≥`stale_after_s`（默认 30s）。

## 4　API

| API | 说明 |
| --- | --- |
| `CICView.new(cfg)` / `setup(cfg)` | 校验/准备输入；缺 TrackTable VM/tracks/ownship → ready=false + errors |
| `build()` | 生成只读 view；失败 reason（`not_ready`） |
| `tracks()` / `ownship()` / `facilities()` / `summary()` | 只读副本 |
| `to_dict()` / `to_json()` | 完整 view/JSON |
| `check()` | 契约检查（truth=false/writes=false/L1 无位置/L2 位置一致） |
| `ready/errors/warnings/contract_errors` | 状态 |

失败 reason：`not_ready`、setup 的 `缺少 TrackTable VM/track_table`/
`TrackTable VM 缺少 tracks 数组`/`ownship/observer pos_km 必须是有限三维`/
`ownship heading_deg 非法`；未知/缺字段 track 跳过或给 `reason`，不伪造位置。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/cic_view_probe.gd
# V17 CIC VIEW PROBE RESULT: PASS=924 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：setup 错误/合法 view contract；L1 无位置+ray/cone+范围/质量年龄影响；
L2/L3/L4 估计/uncertainty/身份/威胁/证据/缺 geometry；metadata known/entity/facility、
设施 registry/array、ownship 平移、summary；truth 输入忽略/只读/JSON 无 truth；
实际 TrackTable 两观测 L2；确定性/排序/重复 build/空 tracks/错误 reason。

## 6　边界

- 只做可观测信息组合与估计，不是传感器/融合/识别算法；不读 PhysicsWorld truth，
  不写 TrackTable/world/UI/V15；不渲染 UI/战术图。
- 估计位置来自 ownship+bearing/range；误差模型是游戏化可测占位，不实现真实
  Kalman/协方差/传感器误差传播；`uncertainty_km` 只是标量估计。
- metadata `known/entity/facility` 只用于可观测关联；未提供时不推断真实实体。
- 未接 StoryRuntime/UI；未跑全量回归；未 commit。
