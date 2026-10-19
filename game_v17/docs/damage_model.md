# R2-DAMAGE-1 · 损管/毁伤模型说明（V17）

> 模块：`game_v17/framework/core/damage_model.gd`（`class_name V2DamageModel`）。
> 内容：`game_v17/framework/content/damage_l1.json`（本舰/敌舰档案、阈值、维修参数）。
> 探针：`game_v17/tests/damage_probe.gd`。本文档说明 API、状态图、效果表、边界与 V17 接入建议。
>
> **边界先说**：本模型**不含武器系统**，不判断命中/射程/制导；只接受外部伤害输入
> `apply_hit(section, energy, penetration, direction, source)`。R2-DAMAGE-2 已把它接入
> V17 world（`entity.damage` + advance + vm 合并，legacy 字段保持兼容），详见 §9。

## 1　文件与运行

| 文件 | 说明 |
| --- | --- |
| `framework/core/damage_model.gd` | 新模块 `V2DamageModel`（分区/命中/火灾/失压/断电/维修队列/资源/vm_damage） |
| `framework/content/damage_l1.json` | 内容：7 分区 × 本舰/敌舰、状态阈值、火灾/失压/断电/维修/效果参数 |
| `tests/damage_probe.gd` | headless 探针（独立模型，219 断言，PASS/FAIL） |
| `tests/damage_integration_probe.gd` | world 接入探针（204 断言，PASS/FAIL） |
| `framework/core/entity.gd` | R2-DAMAGE-2 接入：`entity.damage` + init/ensure（最小改动） |
| `framework/core/world.gd` | R2-DAMAGE-2 接入：初始化/advance/vm 合并/转发 API（最小改动） |
| `docs/damage_model.md` | 本文件 |

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/damage_probe.gd
# DAMAGE PROBE RESULT: PASS=219 FAIL=0（exit 0）

.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/damage_integration_probe.gd
# DAMAGE INTEGRATION PROBE RESULT: PASS=204 FAIL=0（exit 0）
```

未改 `hud.gd/plot.gd/main.gd/state.gd/project.godot`，未改 V15 视觉，未 commit。

## 2　单位与分区

- `integrity`：0..1（1=完好，0=完全毁坏）；`energy`：0..1 归一化命中能量（内部 clamp 上限 2.0）；
  时间 s；所有 view-model 字段 JSON 可序列化。
- 分区 7 个（内容文件可扩展，代码按 `section_id` 通用处理）：

| 分区 id | 名称 | systems | 特点 |
| --- | --- | --- | --- |
| `hull` | 舰体 / HULL | structure | 真空风险高；失压会导致结构损伤 |
| `power` | 动力/配电 / POWER | power | `power_critical`：完整度 <0.5 → 断电传播到 sensors/comms/docking/propulsion |
| `propulsion` | 推进 / PROPULSION | dv / turn | 受损 → Δv/转向倍率下降；断电 → 0 |
| `sensors` | 传感器 / SENSORS | radar/optical/ir/iff/elint | 受损 → 传感倍率下降；断电/毁坏 → 不可用 |
| `comms` | 通信 / COMMS | comms / command | 受损 → 命令延迟（2/6/15/60 s 分级） |
| `tanks` | 储罐/燃料 / TANKS | fuel / cargo | 火灾风险最高；失压/火灾易扩散 |
| `docking` | 对接口 / DOCKING | docking | 完整度 <0.5 或失压 → 对接不可用 |

状态阈值（内容 `state_thresholds`）：`integrity ≥0.9` nominal；`≥0.65` degraded；
`≥0.25` damaged；`>0.001` critical；`≤0.001` destroyed。
维修难度用每分区 `repair_s`（秒，内容文件）表示。

## 3　状态图

```
                 apply_hit(energy, penetration)
  nominal ──integrity↓──► degraded ──► damaged ──► critical ──► destroyed
     ▲                        │            │           │
     └──── repair done ───────┴────────────┴───────────┘（destroyed 不可现场修复）

  分区附加状态（与 integrity 并行）：
    fire: active + intensity(0..1)   —— 随时间增长、造成伤害、向相邻低完整度分区蔓延
    decompression: active+intensity  —— 随时间造成伤害并扩散；维修先封堵后修复
    power_loss/powered              —— power 区分受损后传播；修复到 ≥0.65 恢复
```

- 命中：`damage = energy × (1 − resist)`，resist 由内容 `armor` 按穿透率混合动能/能量抗性；
  穿透：`energy ≥ min_energy` 且 `penetration>0` 时，溢出能量
  `energy×penetration×overflow_ratio` 均分给最多 `max_sections` 个相邻分区（方向只影响溢出
  优先顺序，确定、不伪造弹道）。
- 火灾：分区 `fire_risk ≥0.2` 且 `energy ≥ ignite_threshold` 起火；`step()` 中强度按
  `growth_per_s` 增长并造成 `damage_per_s×intensity` 伤害；强度 ≥`spread_threshold` 且
  达到 `spread_interval_s` 后向相邻最低完整度分区蔓延。
- 失压：`vacuum_risk ≥0.2` 且能量≥`activate_threshold`（非 hull/tanks 还要求穿透≥0.2）触发；
  随时间造成伤害并扩散；维修可封堵。
- 断电：`power` 完整度 < `loss_integrity_threshold`（0.5）→ 向 `propagate_sections` 传播
  `power_loss/powered=false` 并产生事件；修到 ≥ `restore_integrity_threshold`（0.65）恢复并产生
  `power_restored`。
- 分区 destroyed：清除该区火灾/失压、产生 `destroyed` 事件；该区不可现场修复（`assign_repair`
  返回失败）；`is_operational()` 在 hull/power 毁坏时为 false。

## 4　损管资源与维修队列

内容 `repair` 参数（全局，本/敌舰共用；可在后续按舰覆盖）：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `teams_total` | 2 | 同时可用的维修队数 |
| `spares` / `spares_per_job` | 3 / 1 | 备件总数 / 每个维修任务启动消耗 |
| `power_max` / `power_per_s` / `power_recharge_per_s` | 200 / 0.5 / 1.0 | 电力池；维修消耗；电力区正常时回充 |
| `personnel` / `personnel_per_team` | 12 / 2 | 人员限制 |
| `team_speed` | 1.0 | 维修进度倍率 |
| `min_priority`/`max_priority` | 1 / 3 | 优先级范围（1 最高） |

API 行为：

- `assign_repair(section, priority=2)`：未知分区/已毁坏/已在队列 → `{ok:false, reason}`；
  成功入队并按 priority（同优先级按入队顺序）排序。
- `cancel_repair(section)`：移除任务；active 任务释放维修队/人员；**已消耗备件不返还**。
- `set_priority(section, priority)`：修改优先级并重新排序。
- `step(dt)`：
  1. 火灾/失压发展（伤害、蔓延、毁坏判定）；
  2. `_update_power()` 断电传播/恢复；
  3. 维修队分配（按队列优先级，检查备件/人员），电力回充；
  4. active 任务：消耗电力；先压制火灾/封堵失压，再推进结构维修；
     `progress_s ≥ required_s` → 完成：integrity=1.0、清火灾/失压、释放维修队；
  5. 失败条件：备件耗尽 `spares`、电力不足 `power`、人员不足 `personnel`、
     分区中途被毁 `section_destroyed`；失败任务保留在队列（status=failed+reason）供 HUD 展示。
- 每次仅 `teams_total` 个任务 active；其余 queued。

## 5　效果映射（内容 `effects`）

| 系统 | 字段 | 规则（状态来自分区，断电优先置 0） |
| --- | --- | --- |
| 电力 | `power.available/fraction/state` | `fraction=power.integrity`；power destroyed → unavailable |
| 传感器 | `sensors.available/mult/state/systems` | mult：degraded 0.6 / damaged 0.3 / critical 0.1 / destroyed 0；断电或 destroyed → available=false、mult=0 |
| 通信/命令 | `comms.available/command_delay_s/state` | 延迟：degraded 2 s / damaged 6 s / critical 15 s / destroyed 60 s；断电取 60 s |
| 推进 | `propulsion.available/dv_mult/turn_mult/state` | degraded 0.8 / damaged 0.5 / critical 0.2 / destroyed 0；断电 → 0 |
| 对接 | `docking.available/min_integrity/integrity` | powered 且 integrity ≥0.5 且该区无失压 → 可用 |
| 火灾/失压 | `fire.count/sections`、`decompression.count/sections` | 当前 active 分区列表 |
| 断电 | `unpowered_sections` | 当前断电分区 id 列表 |

映射参数全部在内容 `effects`，代码不写死倍率。

## 6　API

```gdscript
const DamageModel := preload("res://framework/core/damage_model.gd")
var m = DamageModel.new()
m.setup({}, "harmattan")            # 内容缺省从 damage_l1.json；第二参为舰船档案 id
m.setup(custom_content, "summons_4471")  # 可用覆盖内容（测试/模组）

# 伤害输入（唯一入口；不生成武器）
m.apply_hit("tanks", 0.6, 0.5, "aft", "probe")
# → {ok, hit{...}, overflow_sections, events, section, summary, effects}

m.assign_repair("tanks", 1)        # 1..3，1 最高
m.set_priority("tanks", 2)
m.cancel_repair("tanks")
m.step(dt)                         # 推进火灾/失压/断电/维修

m.section(id) / m.section_ids() / m.summary() / m.effects() / m.is_operational()
m.vm_damage()                      # 只读 view-model（见 §7）
m.reset()                          # 按当前内容复位
DamageModel.load_content() / DamageModel.list_ships(content)
```

`setup()` 返回 bool；失败原因在 `m.errors`（未知档案/内容缺失）。
每实例 = 一艘舰；内容可含多舰档案（当前 harmattan + summons_4471）。

## 7　vm_damage() 结构（JSON 可序列化，HUD 损管页用）

```
{
  "schema": "damage.v1", "model": "V2DamageModel", "content_id": "damage_l1",
  "entity_id": "harmattan", "name": "...", "class": "...", "t": 0.0,
  "units": {"integrity":"0..1","time":"s","energy":"0..1"},
  "sections": [{
    "id","label","kind","integrity","integrity_pct","state",
    "fire":{"active","intensity"}, "decompression":{"active","intensity"},
    "powered","power_loss","requires_power","systems":[...],
    "repair":{"status","priority","progress_s","required_s","remaining_s","reason"}
  } × 7],
  "events": [{seq,t,type,section,text,...} 最近 64 条],
  "queue": [{section,priority,status,progress_s,required_s,remaining_s,progress_pct,reason,team}],
  "resources": {"teams_total","teams_busy","spares","spares_used","power","power_max",
                "personnel","personnel_used"},
  "summary": {"total","integrity_avg","nominal","degraded","damaged","critical","destroyed",
              "on_fire","decompressed","unpowered","repairing","queued","needs_attention"},
  "effects": {...见 §5...},
  "note": "只读 view-model；伤害输入由 apply_hit 提供（模型不生成武器/命中）。"
}
```

事件类型：`hit`、`penetration`、`fire`、`fire_spread`、`fire_out`、`decompression`、
`decompression_spread`、`sealed`、`power_loss`、`power_restored`、`destroyed`、
`repair_queued`、`repair_start`、`repair_done`、`repair_cancelled`、`repair_failed`。

## 8　内容 schema（damage_l1.json）

```
{
  "schema":"damage.v1","id":"damage_l1",
  "state_thresholds":{nominal,degraded,damaged,destroyed},
  "armor":{kinetic_resist,energy_resist},
  "penetration":{overflow_ratio,min_energy,max_sections,directions[]},
  "fire":{ignite_threshold,ignite_intensity_base,growth_per_s,damage_per_s,
          spread_threshold,spread_interval_s,spread_ignite_intensity,suppress_rate_per_s},
  "decompression":{activate_threshold,damage_per_s,spread_interval_s,
                   spread_ignite_intensity,seal_rate_per_s},
  "power":{loss_integrity_threshold,propagate_sections[],restore_integrity_threshold},
  "repair":{team_speed,teams_total,spares,spares_per_job,power_max,power_per_s,
            power_recharge_per_s,personnel,personnel_per_team,min_priority,max_priority},
  "effects":{sensors{...},comms{...},propulsion{...},docking{...}},
  "ships":{ "<ship_id>": { id,name,class,note,
      sections:[{id,label,kind,integrity,systems[],requires_power,power_critical,
                 adjacent[],repair_s,fire_risk,vacuum_risk}] } }
}
```

每个分区必须有 `id/label/kind/adjacent/repair_s`；`adjacent` 决定穿透/火灾/失压扩散候选。
修改内容即可改变阈值/资源/火势速度（probe §13 验证）。

## 9　V17 world 接入（R2-DAMAGE-2，已执行）

接入点（只改 `framework/core/entity.gd`、`framework/core/world.gd`；未改 `damage_model.gd`
与 `damage_l1.json` 参数；未改 HUD/plot/main/state/project）：

- `V2Entity`：`damage_sections`/`damage_queue`（legacy）保留；新增可选 `var damage = null`
  （V2DamageModel 实例）与 `init_damage(content, ship_id)` / `ensure_damage(content, ship_id)`；
  只有内容有档案的实体（harmattan / summons_4471）初始化，其他实体保持 null（懒加载不伪造）。
  `to_dict()` 增 `damage_ready`。
- `V2World.load_scenario()`：`_init_damage_models(s)` 读 `damage_l1.json`（全场景只读一次），
  为有档案实体建模型；内容缺失时 warning 并保留 legacy 损管。
- `V2World.advance(dt)`：legacy `advance_damage(dt)` 保持；另 `_advance_damage_models(dt)` 对
  每个实体 `damage.step(dt)`（火灾/失压/断电/维修队列）；新事件写 `world.events`（kind=damage）
  与 `world.damage_events_log`（按 entity_id+seq 去重，含 entity_id，最多 128 条）；
  advance 返回值新增 `damage_events`（旧 `damage` 字段保留）。
- `V2World.vm_damage()`：**legacy 字段不变**（`entity_id/entity_name/sections/queue/repair_rate_s/
  summary`，v17 bridge probe 与 V17 HUD 损管卡契约）；追加：
  `damage_sections`/`damage_queue`（旧字段别名）、`has_full_model`、`model`（完整模型 vm）、
  `events`、`resources`、`effects`、`summary_full`、`units`、`note`。
- 只读入口：`world.vm_damage_full(entity_id = own)`、`world.damage_model_for(entity_id)`、
  `world.damage_events(limit := 64)`。

便捷 API（只转发到 `entity.damage`；**不自动命中、不生成武器**）：

| API | 说明 |
| --- | --- |
| `damage_apply_hit(section, energy, penetration=0.5, direction="fore", source="script", entity_id=own)` | 剧情/调试/未来武器系统调用；写日志+事件 |
| `damage_assign_repair(section, priority=2, entity_id=own)` | 指派维修（1 最高） |
| `damage_cancel_repair(section, entity_id=own)` | 取消维修（active 释放维修队） |
| `damage_set_priority(section, priority, entity_id=own)` | 调整优先级 |

兼容策略：legacy 3 项（sensor_cal/ir_false_alarm/thermal）是**独立投影**，供旧 HUD/bridge probe；
完整模型是权威数据但**不反向覆盖 legacy 行**；legacy `apply_damage/start_repair/advance_damage`
行为不变且不推进完整模型。后续独立损管页读 `vm_damage()["model"]` 或 `vm_damage_full()`；
`state.fw_damage` 字段映射见 `game_v17/docs/v17_bridge_fields.md §10`。

未做：HUD 损管页接线（R2-UI 任务）、真实命中几何/武器、按场景指定 damage 内容路径
（`scenario.gd` 未改；world 使用 `damage_l1.json` 默认路径，可后续在场景 schema 加可选字段）。

## 10　验证与覆盖

`tests/damage_probe.gd`（219 断言，PASS=219 FAIL=0，独立模型）覆盖：

- 内容 JSON：schema、双舰档案、7 分区、阈值/维修/火灾/失压参数存在；
- 初始化与 `vm_damage` 结构（sections/events/queue/resources/summary/effects/units/note）；
- 命中与状态迁移、未知分区拒绝、穿透溢出到 2 个相邻分区、低能量不溢出；
- 火灾：起火/增长/伤害/蔓延/维修压制与恢复、`fire_out`；失压：触发/伤害/扩散/封堵恢复；
- 断电：power 低完整度传播、effects 倍率/延迟、维修恢复与 `power_restored`；
- 子系统：sensors 0.3 / comms 6 s / propulsion 0.5 / docking min_integrity 与摧毁后不可用；
- 维修队列：优先级排序、重复拒绝、set_priority、cancel 释放、团队与备件消耗、完成恢复；
- 资源耗尽：6 任务 + 3 备件 → 3 个 failed（reason=spares）、无残留占用；
- 分区毁坏：不可现场修复、power 毁坏→动力 0/不可用/非 operational；
- 双舰档案、vm JSON stringify/parse 回读、无 weapons 字段；
- 确定性（同输入序列 → 相同 vm JSON）；内容驱动（覆盖 spares/teams/火势/阈值生效）。

`tests/damage_integration_probe.gd`（204 断言，PASS=204 FAIL=0，world 接入）覆盖：

- world 初始化：damage_l1 装载、harmattan/summons_4471 有模型、其他实体 null（懒加载不伪造）；
- 旧字段兼容：vm_damage 的 sections=3/summary.total=3/queue/repair_rate_s 与 bridge probe 契约一致，
  别名 damage_sections/damage_queue 可用；model/events/resources/effects/summary_full 存在；
- 完整模型 vm：schema/model/entity/sections=7/queue/resources/effects；敌舰 7 分区；无档案实体空；
- `damage_apply_hit` → hit 事件、完整模型完整度下降、legacy 字段不变；
  `world.advance` 返回 damage_events 并推进模型 t；火灾事件/统一事件日志（entity_id）；
- 损管 API：assign/set_priority/cancel 转发完整模型；advance 后修复完成；
- legacy 维修链路（start_repair/advance_damage）保持原行为且不污染完整模型；
- 敌舰可受击且不影响本舰；无档案实体命中被拒绝（原因明确）；
- HUD 旧读取字段齐全（不崩）、完整损管页字段齐全、vm JSON 可回读、无 weapons；
- V17 bridge `damage_view()` 保留 legacy sections=3 并暴露 has_full_model/model。

回归（同一任务内）：`damage_probe` 219/0、`v17_core3_probe` 171/0、`v17_bridge_probe` 138/0、
`plot_tws_probe` 59/0、boot exit 0、`DSH_SKIP_INTRO=1 --quit-after 10` exit 0。

## 11　边界（明确不做 / 不假装）

- **无武器系统/命中判定**：不做射程、制导、弹种、命中概率；`apply_hit` 是唯一伤害入口。
- 不做空间几何/部位坐标：方向 `direction` 仅用于溢出顺序与事件记录，不模拟弹道/装甲角度。
- 确定性模型（无随机）：蔓延选“相邻最低完整度分区”，便于复现与 probe；不模拟随机故障。
- 修复完成直接恢复到 integrity=1.0（不建模备件质量/永久损伤）；destroyed 分区不可现场修复
  （需要船坞，未建模）。
- 维修资源是全局池（每实例一套）；尚未按舰覆盖（内容支持后续扩展 `ships.<id>.repair`）。
- 电力回充简化（电力区未毁坏即按固定速率回充）；不建模配电网络拓扑。
- 无人物伤亡/舱室人员模型；`personnel` 只作为维修人力限制。
- world 接入已完成（§9），但**未接 HUD 损管页、未接真实命中几何/武器**；legacy 3 项与完整
  模型是两套独立投影（不互相驱动）。`scenario.gd` 未改：damage 内容路径固定默认，后续可加
  可选场景字段。
- 未 commit。
