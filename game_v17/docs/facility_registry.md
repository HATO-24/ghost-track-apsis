# 完整游戏-阶段3O · FacilityRegistry 全设施注册表

> 任务 task-162。工程 `game_v17`。
> 新文件：`scripts/core/facility_registry.gd`、
> `tests/facility_registry_probe.gd`、本文件、
> `framework/content/facilities_system.json`。
> 另由 GameSession 可选接入（见 `game_session.md`）；不写 world/UI/物理/V15；未 commit。

## 1　数据来源与覆核口径

- **L1–L5 港群站点（20 站）**：legacy `docs/20_港群与站点.md`（编号/站名/职责/特色/归属）；
  本内容保留正式站号，跳号不补。
- **NESOSS-01..06**：legacy `docs/42_legacy迭代记录.md` §3（Polaris/Arclight/
  Hyperion/Vega Prime/Saturnus/Noah）。
- **月同步轨道站群（3 站）**：新提案，名称标 **TBD**（`name="TBD"`，`name_zh` 带提案：
  月脊/静海/月港），待用户确认；`owner=TBD`、`side=unknown`。
- 物理参数为原型级可运行占位（质量/半径/截面/站保持 Δv/周期），不是工程定值；
  轨道 `physical.orbit.type` 标 lagrange_halo/geo/moon_sync。

## 2　内容 schema（`facilities_system.json`）

```text
schema: v17.facilities_system.v1, version: 1.0.0
title/source/generated_at
clusters: [{cluster_id,name,name_en,name_zh,kind,point,description}]
facilities: [{
  facility_id, name, name_en, name_zh,
  facility_code,            # 全局唯一，FC-<facility_id>
  transponder_code,         # 全局唯一，TXP-<facility_id>
  transponder_type,         # station/traffic_control/commercial/depot/shipyard/
                            # habitat/industrial/observation/relay/agriculture/...
  parent_cluster,           # 必须存在
  facility_class, owner, side,
  services: [String],
  ports: [{port_id, kind, berths, max_length_m}],  # port_id 全局唯一
  physical: {
    orbit: {frame, type, position_km},
    mass_kg, radius_km, cross_section_m2,
    station_keeping: {mode, dv_m_s_year},
    period_s
  },
  note, entity_ids: [world entity id]  # 可选绑定
}]
```

- 覆盖：**7 cluster / 29 facility / 57 ports**。
  - L1_MERIDIAN 4 / L2_KARMAN 4 / L3_ALBORADA 4 / L4_ANVIL 4 / L5_NEW_LAGOS 4；
  - NESOSS 6；LUNSYNC 3。
- 示例绑定：L1-05 Chronos `entity_ids=["l1_station"]`；其余设施默认空（不搞硬编码舰名）。

## 3　API

| API | 说明 |
| --- | --- |
| `FacilityRegistry.new(cfg)` / `setup(cfg)` | cfg：`content`(Dictionary) 或 `content_path`；默认加载本内容 |
| `load_content(path)` | 读 JSON；不存在/非法 JSON 失败；成功才替换 |
| `load_data(value)` | validate 后应用；失败**不改旧注册表**（原子）；首次失败 ready=false |
| `validate(value)` | 全量校验（schema/version/cluster/facility/唯一性/物理/端口），返回 `{ok,errors}` |
| `ready/errors/warnings` | 状态 |
| `facility(facility_id)` / `by_code(code)` / `by_transponder_code(code)` | 按 id/code/transponder 查询；未知返回空 |
| `cluster(cluster_id)` / `facility_ids()` / `cluster_ids()` / `count()` | cluster/列表 |
| `classify_transponder(code)` | `{ok,matched,transponder_code,transponder_type,facility_id,facility}`；未知/空有 reason |
| `facility_card(facility_id)` | `facility_card.v1`：facility/cluster/ports/physical/codes/writes |
| `facilities_by_cluster(id)` / `facilities_by_parent(id)` | 按 parent 查询（id 排序） |
| `facility_for_entity(entity_id)` | 通过 `entity_ids` 绑定查设施；未知空 |
| `ports_for(id)` / `port_ids_for(id)` | 港口绑定查询 |
| `summary()` / `to_dict()` / `to_json()` / `check_contracts()` | 摘要/内容/JSON/DbC |

失败/未知：未知 facility/code/transponder/cluster/entity 返回空；`classify_transponder` 未知
返回 `{ok:false,reason:"unknown_transponder",matched:false}`；非法内容原子拒绝。

## 4　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/facility_registry_probe.gd
# V17 FACILITY REGISTRY PROBE RESULT: PASS=1694 FAIL=0（exit 0，只跑一次）
```

覆盖（5 节）：coverage（7 cluster/29 站/20 已知站名/NESOSS 6/LUNSYNC 3 TBD/57 ports）；
schema/唯一性/物理/港口/entity 绑定；按 id/code/transponder（大小写）/card/classify/cluster 排序
/未知拒绝；16 类非法内容原子拒绝/不存在文件/非对象；to_dict/to_json 往返/两次加载/card 确定性/
contracts/不写 world/UI。

## 5　接入 / 边界

- **GameSession 可选接入**：boot `facility_registry: true` 或 `{content_path/content}`；
  session API `facility_lookup/facility_by_transponder/facility_for_entity/facilities_by_cluster/
  facility_vm/facility_summary`；save 嵌入完整注册表，load 恢复；旧存档缺字段 → 组件退化。
- **只读**：不写 world/UI/物理/V15；不改现有实体；`facility_for_entity` 只读 `entity_ids` 绑定，
  不做实体移动/生成。
- 不实现碰撞/停靠物理、不生成 PortService 实例；`ports[]` 仅数据绑定（port_id 供上层/PortService
  配置引用）；不实现 UI 卡片渲染（只提供 `facility_card` 数据）。
- 月同步站名 TBD 提案；物理参数为原型占位；不接真实星历表；未跑全量回归；未 commit。
