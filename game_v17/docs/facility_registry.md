# 完整游戏-阶段3O/4B · FacilityRegistry 全设施注册表

> 任务 task-162（基础）/ task-184（4B OTC/燃料/轨道节点合并）。工程 `game_v17`。
> 文件：`scripts/core/facility_registry.gd`、`tests/facility_registry_probe.gd`、本文件、
> `framework/content/facilities_system.json`。
> 另由 GameSession 可选接入（见 `game_session.md`）；不写 world/UI/物理/V15；未 commit。

## 1　数据来源与覆核口径

- **基础 29 设施（L1–L5 20 站 + NESOSS 6 + LUNSYNC 3）**：legacy `docs/20`/`docs/42`；
  旧 facility/port 数完全保留，不重复 ID。
- **4B 扩展（facilities_system.json 顶层）**：
  - `otc_satellites`：19 个 OTC 交通管制卫星（L1 2、L2 2、L3 1、L4 2、L5 2、
    NESOSS 3、LEO 3、FAR 2、LUNSYNC 2）；
  - `fuel_facilities`：62 个（31 TNK 储罐 + 31 FUL 加注设施；覆盖 L1–L5、
    NESOSS、LEO、FAR、LUNSYNC）；
  - `orbital_nodes`：LEO/FAR 轨道节点元数据，合并为 cluster（不占用 facility 计数）；
  - 扩展 facility 含 facility_id/code/transponder/class/ports/physical/entity_ids，
    与 base 共用查询与唯一性校验。
- 物理参数为原型级可运行占位；不伪造工程定值。

## 2　内容 schema（`facilities_system.json`）

```text
schema: v17.facilities_system.v1, version: 1.0.0
title/source/generated_at
clusters: [{cluster_id,name,name_en,name_zh,kind,point,description}]
facilities: [ ...基础 29... ]
orbital_nodes: [{cluster_id,name,name_en,name_zh,kind,point,description}]  # 4B LEO/FAR
otc_satellites: [ facility schema ]   # 4B 19 OTC
fuel_facilities: [ facility schema ]  # 4B TNK+FUL 62
```

- 覆盖（4B 合并后）：
  - **base**：7 cluster / 29 facility / 57 ports；
    L1_MERIDIAN 4 / L2_KARMAN 4 / L3_ALBORADA 4 / L4_ANVIL 4 / L5_NEW_LAGOS 4；
    NESOSS 6；LUNSYNC 3。
  - **extension**：19 OTC + 62 TNK/FUL = 81 facility / 81 ports；orbital_nodes 2（LEO/FAR）。
  - **total**：9 cluster（base 7 + LEO/FAR）/ 110 facility / 138 ports。
- 示例绑定：L1-05 Chronos `entity_ids=["l1_station"]`；扩展 facility 也可配置
  `entity_ids`，`facility_for_entity` 统一查询；其余默认空（不硬编码舰名）。
- **兼容语义**：`summary()["clusters"|"facilities"|"ports"|"facility_codes"|"transponders"]`
  保持 base 值（7/29/57/29/29），新增 `base_*`/`extension_*`/`otc_satellites`/
  `fuel_facilities`/`orbital_nodes`/`total_*` 字段；`facilities_by_cluster` 对 base
  cluster 保持旧计数，扩展节点 LEO/FAR 返回合并结果，全合并用
  `all_facilities_by_cluster`。

## 3　API

| API | 说明 |
| --- | --- |
| `FacilityRegistry.new(cfg)` / `setup(cfg)` | cfg：`content`(Dictionary) 或 `content_path`；默认加载本内容 |
| `load_content(path)` | 读 JSON；不存在/非法 JSON 失败；成功才替换 |
| `load_data(value)` | validate 后应用；失败**不改旧注册表**（原子）；首次失败 ready=false |
| `validate(value)` | 全量校验（schema/version/cluster/facility/唯一性/物理/端口），返回 `{ok,errors}` |
| `ready/errors/warnings` | 状态 |
| `facility(facility_id)` / `by_code(code)` / `by_transponder_code(code)` | 按 id/code/transponder 查询；未知返回空 |
| `cluster(cluster_id)` / `facility_ids()` / `base_facility_ids()` / `extension_facility_ids()` / `cluster_ids()` / `count()` | cluster/列表；`count()` 为 total 110 |
| `otc_satellite_ids()` / `fuel_facility_ids()` / `orbital_node_ids()` | 4B 扩展列表 |
| `base_count()` / `extension_count()` / `otc_count()` / `fuel_count()` / `orbital_node_count()` | 4B 计数 |
| `classify_transponder(code)` | `{ok,matched,transponder_code,transponder_type,facility_id,facility}`；未知/空有 reason |
| `facility_card(facility_id)` | `facility_card.v1`：facility/cluster/ports/physical/codes/registry_group/writes |
| `facilities_by_cluster(id)` / `facilities_by_parent(id)` | 按 parent 查询（base cluster 保持旧语义；id 排序） |
| `all_facilities_by_cluster(id)` / `base_facilities_by_cluster(id)` / `extension_facilities_for_cluster(id)` | 全合并/base/扩展查询 |
| `orbital_node(cluster_id)` | LEO/FAR 节点元数据 |
| `facility_for_entity(entity_id)` | 通过 base+扩展 `entity_ids` 绑定查设施；未知空 |
| `ports_for(id)` / `port_ids_for(id)` | 港口绑定查询（base+扩展共 138 ports） |
| `summary()` / `to_dict()` / `to_json()` / `check_contracts()` | 摘要/基础+扩展内容/JSON/DbC |
| `to_merged_dict()` | 合并视图（9 cluster/110 facility + summary，供调试/UI） |

失败/未知：未知 facility/code/transponder/cluster/entity 返回空；`classify_transponder` 未知
返回 `{ok:false,reason:"unknown_transponder",matched:false}`；非法内容原子拒绝。

## 4　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/facility_registry_probe.gd
# V17 FACILITY REGISTRY PROBE RESULT: PASS=6059 FAIL=0（exit 0，只跑一次）
```

覆盖（6 节）：coverage（base 7/29/57 + total 9/110/138 + OTC19/fuel62/LEO/FAR）；
4B 扩展（OTC 查询/TNK+FUL 31+31/节点/旧 29 回归/扩展 entity_ids/merged）；
schema/唯一性（code/transponder 110、port 138）/物理/港口/entity 绑定；
按 id/code/transponder（大小写）/card/classify/cluster 排序/base+all 查询/未知拒绝；
21 类非法内容（含扩展重复/非法）原子拒绝；to_dict 基础+扩展往返/两次加载/card 确定性/
contracts/不写 world/UI。

## 5　接入 / 边界

- **GameSession 可选接入**：boot `facility_registry: true` 或 `{content_path/content}`；
  session API `facility_lookup/facility_by_transponder/facility_for_entity/facilities_by_cluster/
  facility_vm/facility_summary`；save 嵌入完整注册表，load 恢复；旧存档缺字段 → 组件退化。
- **只读**：不写 world/UI/物理/V15；不改现有实体；`facility_for_entity` 只读 `entity_ids`
  绑定（base+扩展），不做实体移动/生成。
- **4B 合并边界**：扩展只并入本注册表查询/校验/摘要，不改 base 29 条数据、不重复 ID；
  `to_dict()` 保留原 schema（base clusters/facilities + `orbital_nodes`/`otc_satellites`/
  `fuel_facilities`），load 后查询等价；`to_merged_dict()` 仅供调试/UI 查看合并视图。
- 不实现碰撞/停靠物理、不生成 PortService 实例；`ports[]` 仅数据绑定（port_id 供上层/PortService
  配置引用）；不实现 UI 卡片渲染（只提供 `facility_card` 数据）。
- 月同步站名 TBD 提案；物理参数为原型占位；不接真实星历表；未跑全量回归；未 commit。
