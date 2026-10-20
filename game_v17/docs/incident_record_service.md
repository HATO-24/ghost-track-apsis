# 完整游戏-阶段3Y · IncidentRecordService（未来事故记录生成器）

> 任务 task-180。工程 `game_v17`。
> 新文件：`scripts/core/incident_record_service.gd`、`tests/incident_record_probe.gd`、
> 本文件、`framework/content/incident_templates.json`。
> 不改其他；不写 world/UI/V15；未 commit。

## 1　定位

- 从 **2193-11-07** 开场时间向后，按设施/港群的“33OSID 接管意愿强度” pressure
  （0..1）确定性生成未来事故排程与记录。
- **NESOSS 全部排除**（`parent_cluster=NESOSS` / `FC-NESOSS*` / 任意 code 含 NESOSS）；
  当前设施内容 29 个中排除 6 个，可用 23 个（含 L1–L5 + LUNSYNC）。
- 生成三类记录 + GT 线索；**不写具体人物台词/小说**，只生成日志/黑匣子/UI 可用的
  结构化记录与格式化文本。

## 2　算法（确定性排程）

1. 载入 `incident_templates.json`（9 类事故 A1–A9、设施类别→类型权重、异常模式、
   schedule/格式配置）。
2. 设施输入：`facility_registry`（FacilityRegistry 实例）、`facilities` 数组，或默认
   `facilities_system.json`；排除 NESOSS。
3. 从 `start_date=2193-11-07`、`t=0` 开始；每步：
   - 按设施 weight=`0.5+pressure` 加权选站点；
   - 间隔 `base_interval_days × (1 − pressure_scale×p) × jitter`，并夹到
     `min_interval_days`；
   - 高 pressure → 更短间隔、更高频率、更偏向高 pressure 站点；
   - 按设施类别权重选 A1–A9 类型；同站点可多次事故；
   - t 超出 `horizon_days` 停止；`max_incidents` 保护。
4. 确定性：`RandomNumberGenerator(seed)`；同 seed/配置/操作 → 相同 incidents/clues/save。
5. `generate()` 每次从开场重新排程（清空旧结果）；`reset()` 清空并复位 RNG，可用于重放。

## 3　记录 schema

### accident_log（`incident_accident_log.v1`）

```json
{
  "incident_id": "INC-0001", "t_s": 840925.07, "t_iso": "2193-11-16 17:35:25",
  "facility_id": "L5-07", "facility_code": "FC-L5-07",
  "facility_name": "Savannah", "cluster_id": "L5_NEW_LAGOS",
  "type": "A2", "type_key": "decompression", "type_name": "舱段失压",
  "severity": 4, "severity_scale": "1-5",
  "impact": {"casualties": "minor", "berths_closed": 1, "cargo_lost_t": 0.0,
    "power_loss": false, "evacuation": true},
  "disposition": {"response": "port_authority", "status": "sealed", "reporting": "full"},
  "record_integrity": {"status": "edited|gaps|intact", "score": 0-100,
    "gaps": 0, "time_jumps": 0, "duplicate_codes": 0, "edited": true, "anomalies": []},
  "operator": {"role": "...", "source": "facility_operations", "generic": true},
  "summary": "设施发生 类型（A#），严重度 N；处置：...；记录完整性：..."
}
```

### telemetry（`incident_telemetry.v1`）

- `window {start_s,end_s}`、`channels`（固定含压力/温度/功率/流量 + 类型额外通道）；
- `samples[]`：事故前后采样 `{t_s, offset_s, values{...}}`；
- `gaps[]`、`anomalies[]`、`edit_marks[]`（缺口/时间戳跳变/覆盖写/功率尖峰）；
- `hash:"sha256:..."`、`record_integrity`。

### OTC / traffic（`incident_otc_record.v1`）

- `tracks[]`：`{track_id, transponder, clearance, handoff{from,to,t_s}}`；
- `clearances[]`、`handoffs[]`；
- `deleted_records[]`、`rewritten_records[]`、`duplicate_codes[]`；
- `hash`、`record_integrity`。

### ghost_track_clues（`incident_ghost_track_clue.v1`）

- `clue_id/GTC-xxxx`、`incident_id`、`facility_code`、`kind`（timestamp_gap /
  timestamp_jump / duplicate_track / edit_mark / power_spike）、`severity`、
  `evidence_ref{record,anomaly}`、`description`、`confidence`。
- 每个事故至少 1 条线索；异常越编辑/跳变越多，可信度按完整性/ pressure 计算。

## 4　事故类型（A1–A9）

| 类型 | key | 名称 | 典型设施类别 | 异常模式 |
| --- | --- | --- | --- | --- |
| A1 | airlock_failure | 气密门失效 | station/port/research/observation | gap/edit |
| A2 | tank_explosion | 储罐爆炸 | depot/station/port | gap/timestamp_jump/power_spike |
| A3 | tank_leak | 储罐泄漏 | depot/station/port | gap/edit |
| A4 | module_depress | 外部舱段失压 | station/research/observation/port | gap/timestamp_jump |
| A5 | solar_panel_damage | 太阳能板损坏 | station/depot/relay/observation | power_spike/edit |
| A6 | radiator_panel_damage | 散热板损坏 | station/depot/research/observation | gap/edit |
| A7 | docking_failure | 对接口失效 | port/station/depot | gap/edit |
| A8 | docking_depress | 对接口失压 | port/station/depot | gap/timestamp_jump |
| A9 | docking_damage | 对接口损坏 | port/station/depot | edit/timestamp_jump |

## 5　API

| API | 说明 |
| --- | --- |
| `IncidentRecordService.new(cfg)` / `setup(cfg)` | 载入模板/设施；cfg：`facility_registry/facilities/facilities_content_path/templates_path/start_date/horizon_days/seed/pressure` |
| `generate(opts={})` | 重新排程并生成；opts 可覆盖 `seed/horizon_days`；返回生成数/线索数/设施数/排除数 |
| `incidents()` / `incident_ids()` | 全部事故（按时间） |
| `in_between(t0,t1)` | 时间窗过滤（秒或 ISO 日期） |
| `records(incident_id)` | 三类记录 + 线索 |
| `clues(incident_id="")` / `clues_for(id)` | 全部/单事故线索 |
| `format_accident_text/format_telemetry_text/format_otc_text` | 事故日志/遥测/OTC 文本 |
| `pressure_map()` | 每个设施当前 pressure |
| `save_state()/load_state()/reset()/vm()/summary()/check_contracts()` | 存档/重置/VM/DbC |

失败：setup/generate 返回 `ok=false` + `reason`（`invalid_horizon`、`invalid_payload`、
模板/设施/日期/pressure 非法）；未知记录查询返回空，不伪造。

## 6　示例文本（生成结果格式，非剧情台词）

```text
[事故记录] INC-0001  2193-11-16 17:35:25
设施：FC-L5-07（Savannah / L5_NEW_LAGOS）
类型：A4 外部舱段失压  严重度：4/5
影响：{"berths_closed":1,"cargo_lost_t":0.0,"casualties":"minor","evacuation":true}
处置：{"reporting":"full","response":"port_authority","status":"sealed"}
记录完整性：{"status":"edited","score":...,"gaps":...,"edited":true,...}
摘要：Savannah 发生 外部舱段失压（A4），严重度 4；处置：sealed；记录完整性：edited。

[遥测记录] INC-0001  2193-11-16 17:35:25  设施：FC-L5-07
窗口：{"end_s":...,"start_s":...}  通道：["pressure_kpa","temperature_c","power_kw","flow_tph"]
  t=-240.0s {"pressure_kpa":...,"temperature_c":...}
  ...
缺口：[...]  异常：["edit"]  编辑痕迹：[...]  hash：sha256:...

[OTC/交通记录] INC-0001  2193-11-16 17:35:25  设施：FC-L5-07
  track=TRK-0001-01 transponder=TXP-L5-07-01 clearance=CLR-0001-01
handoff：[...]  删除记录：[...]  改写记录：[...]  重复码：[...]  hash：sha256:...
```

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/incident_record_probe.gd
# V17 INCIDENT RECORD PROBE RESULT: PASS=2762 FAIL=0（exit 0，只跑一次）
```

覆盖（5 节）：模板/23 设施/6 NESOSS 排除/Registry 输入/失败 setup；开场后不规则排程/
递增时间/同站点多次/高 pressure 更高频/长 horizon/同 seed 一致/不同 seed 不同；
全部事故三类记录字段/遥测前后采样+4 通道+缺口+异常+编辑+hash/OTC track/transponder/
clearance/handoff/删除/改写/重复码/线索；in_between 秒+ISO、records/clues 查询、三文本；
save/load/reset 重生成、非法 generate/存档原子拒绝、确定性与 contracts。

## 8　接入 / 边界

- 只生成记录与格式化文本：不写 world/UI/V15、不伪造具体人物台词、不改设施/剧情状态。
- 输入 FacilityRegistry 可只读；NESOSS 排除不参与事故生成。
- 生成结果供后续日志/黑匣子/OTC/调查 UI/剧情线索系统消费；本任务不接 UI/剧情运行时。
- 文本/数值为模板化生成（可复现），不是真实历史记录；未跑全量回归；未 commit。
