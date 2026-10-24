# 完整游戏-阶段2C/2H · GameSession 编排层（含 TrackTable/StoryState）

> 任务 完整游戏-阶段2C（task-121）+ 2H（task-129）+ 2J（task-131）+ 3I（task-142）+ 2K（task-146）+ 2M（task-154）+ 3L（task-157）+ 3M（task-159）+ 3N（task-160）+ 3O（task-162）+ 3P（task-164）+ 3R（task-167）+ **4Z 交战物理化（统一开火路径）**。工程 `game_v17`。
> 修改（不改其他；不接旧场景/UI/旧 transit；未 commit）：
> - `scripts/core/game_session.gd`
> - `tests/session_probe.gd`（`PASS=1541 FAIL=0`）
> - 本文件
> 不实现物理/UI/剧情/ROE；组合既有内核并做内存 save/load。

**4Z 变更摘要（本轮）**

| 变更 | 语义 |
| --- | --- |
| `request_fire()` 物理前置 | 门禁之前先解 shooter/target 物理状态；解不出 → `no_physics_state`，**绝不白扣弹药** |
| 开火改异步 | 返回时只有 `launched/projectile_ids`；命中由 `tick` 内的弹道积分与 `impact` 决定，不在开火时判定 |
| `own_entity` seed 字段 | 本舰实体 id 的唯一显式来源（白名单字段）；缺省时按 `combat_service.own_id` → tags → side 兜底 |
| `_entity_kinematics()` | 弹道取态唯一入口：物理世界优先、剧情世界兜底；**不能**用 `position_of()` |
| `combat_time_cap` | 有弹在飞时把倍速压到 60×，交战结束恢复原倍速 |
| 规划辅助 | `combat_plan()` 把意图（direct/silent/offset/multi_axis）翻译成巡航剖面 + Δv 预算 |

## 1　角色与依赖

```
GameSession
 ├─ TimeService      时间/epoch/scale/pause/docked
 ├─ EventBus          事件 id/type/t/source/target/payload/text_key + seq
 ├─ WorldState        实体表 + TimeService 钟引用 + 已应用事件引用（单写者）
 ├─ OrderService      命令状态机（依赖 CommsService 投递）
 ├─ CommsService      节点/链路/路由/延迟/丢包/遮挡/干扰
 ├─ TrackTable（可选） 观测/证据融合（L1-L4，单写者）= V2FusedTrackTable
 ├─ StoryState（可选） 剧情 flags/evidence/choices/trust/morality/reputation/threat/gate
 ├─ SensorService（可选） 传感器管道 → observation/evidence，经 session 显式白名单路由到 TrackTable
 ├─ PortService（可选） 港口/对接/加注/维修/拖曳/穿梭机状态机与资源
 ├─ CombatService（可选） ROE/授权/火控/武器/点防御（damage event 不直接应用）
 ├─ DamageService（可选） 每舰 V2DamageModel；combat damage 事件→分区伤害/维修
 ├─ PhysicsWorld（可选） 单一位置/速度权威；固定步长 CR3BP/星历；tick 边界同步 world 只读副本
 ├─ SignalService（可选） ELINT/DF/灯语；observation/evidence→TrackTable，light→bus
├─ EWService（可选） 干扰/欺骗/假目标/EMCON/通信 spoof/激光；effect 接口不写 world
 ├─ FacilityRegistry（可选） 全设施只读注册表；cluster/站/应答机/港口/物理参数
 ├─ TransponderService（可选） 应答机行为；询问/广播/状态/加密/触发→evidence/events
 └─ IdentificationService（可选） 识别自动化/证据融合；自动询问/身份评估→identity.* 事件
 ├─ LegalStatusService（可选） ID13 法律状态/影响标志；UNLISTED→HUNTED/CLEARED；不写 world
 └─ TrafficControlService（可选） OTC/航道/NPC/伪装线索；申请-许可-占用-释放；不写 world/TrackTable/UI
 └─ CombatBallistics（可选） 弹道/导弹/PD/诱饵；session 状态驱动 step；impact→damage_event；不写 world
 └─ ShipCatalog（可选） 友军/敌军舰级目录；entity→class/known_ship/entity_binding；只读
 └─ RefitService（可选） APSIS 改装事务/槽位/质量/功率/成本/地点；不写 world/UI
 └─ DamageProfileService（可选） 舰级毁伤档案（分区/材质/effects）；旧 damage_l1 显式档案优先
 └─ FleetRefitService（可选） 13 舰独立改装/共享资源/按 class 过滤模块；不写 world/UI
 └─ FleetFormationService（可选） 8 槽自由编组/角色/上限/燃料维修校验；不写 world/UI
```

- **依赖方向**：OrderService 内部持有 CommsService；`tick` 时订单服务推进通信并消费其投递事件。
- **事件方向**：session 把订单/通信/链路事件发布到 EventBus；**bus 不自动写 world**；
  world 仅由 session 写者显式 apply（seed 实体、或调用方显式事件）。
- **单写者**：session 的 writer（默认 `"session"`）是 WorldState 唯一写者；TrackTable 自己是
  独立单写者（默认 `session_fusion`）；外部 token 写两处均拒绝。
- **bus → TrackTable/StoryState**：只按**显式白名单** `story.flag/story.evidence/story.choice/
  track.observation/track.evidence` 路由；其它事件不写组件（不让 bus 偷写）。
- **Sensor → TrackTable**：SensorService 只输出 observation/evidence（不写 TrackTable/world/UI）；
  session 在 tick 中取走其事件，按 schema/kind 白名单（`sensor_observation.v1` support 1..2、
  `track_evidence.v1`）路由到 TrackTable；support=0/>2 的非 L1/L2 行忽略。
- **Sensor 几何 → PhysicsWorld（A0-T2 / Issue #4.1）**：boot 末尾由
  `_bind_sensor_geometry()` 把传感器几何（observer/targets 的位置+速度）绑定到统一物理世界；
  `SensorService.step()` 在推进后按当前 `t` 刷新几何，保证 `geometry_t == physics t ==
  session t`（容差 1e-6 s）。frame=`bary_rot`，单位 km / km/s。静态元数据（rcs/side/iff/
  classification）仍来自原权威，不被几何刷新覆盖。**降级显式**：无 physics →
  `source=static`；4F 帧转换会话 → `source=static, reason=frame_mismatch`（不做隐式跨帧）。
  诊断：`sensor_geometry_status()` / `sensor_service.geometry_status()`。几何绑定不写
  world/TrackTable/V15/UI；`range_km` 仍是**观测值**，不替换为物理真值。

- **Port/Combat → EventBus**：session tick 驱动二者 step；其 outbox 事件映射为 `port.*`/`combat.*`
  发布到 bus（只读事件）；Port/Combat 不写 world/TrackTable/物理/UI。
- **Combat → Damage**：combat `combat_damage_event`（combat_hit/incoming_impact 内嵌
  `damage_event`）经显式白名单路由到 DamageService（`applied=true` 才写损伤）；`shot_id` 去重，
  同一伤害不会因 request_fire 立即应用 + tick flush 二次应用。Damage 事件发布 `damage.*`。
- **Physics 位置权威（A0-T1 更新）**：启用 `physics_world` 时实体位置/速度以 PhysicsWorld 为
  唯一权威（`position_of/physics_state` 读 physics；仅 PhysicsWorld 内部推进位置）。tick 顺序为
  `time → physics.step → world 副本同步 → orders/sensor/track/...`：**tick 边界**把 physics 当前
  时刻的 r/v 作为**只读副本**写入 WorldState（world 写者仍是 session，`source="physics_world"`），
  使 `snapshot().entities`、`plot_positions()` 物理分支、存档恢复后的 world 副本与 physics 处于
  同一仿真时刻。策略与诊断：`world_physics_sync_status()` 返回 `{enabled,mode,frame,in_sync,
  compared,mismatched,sync_count,last}`；tick 返回值新增 `world_sync` 段。
  - **单向性**：副本写入绝不反向覆盖 physics；调用方手写 world 位置后，下一次 tick 边界会用
    physics 覆盖回来（副本自愈）。
  - **帧门禁**：若 seed 做过 L1→bary_rot 帧转换（`physics_frame_meta.applied=true`），world 副本
    仍是 L1 相对语义，与 physics 不同坐标空间 → 策略为 `frame_mismatch`，**显式不同步**并在
    `world_physics_sync_status().reason` 记录；不做隐式跨帧搬运（4F 帧契约不变）。
  - **不变量**：`check_contracts()` 在 `mode=tick` 时新增「world 位置副本与 physics 一致」检查。
  - `sync_world_from_physics()` 保留为**显式全量同步**入口（全量写一遍并发布
    `physics.world_synced`，供存档/调试/外部脚本使用）；tick 边界同步不逐实体发 bus 事件（避免
    每 tick 噪声）。
- **Physics 帧（4F）**：Prelude/`scenario_prologue` 的 `pos_km/vel_kmps` 是 **L1 相对 km**，
  PhysicsWorld 默认 **bary_rot**。boot 自动灌入 seed 时，`_seed_physics_entities` 默认
  `seed_frame=auto`：检测到 prelude（`prelude` 标记/特定实体 id）→ 把 r 平移到 L1 bary
  （`cislunar_physics.equilibrium_points()["L1"].pos_rot`，CR3BP μ/D），**v 保持不变**；
  显式 `seed_frame=l1` 可强制，`bary_rot/none` 可显式关闭；`frame_origin` 可指定 L1/数组
  origin；非法帧 warning 并按 bary 处理。只转换本次 boot 的 seed 实体、不重复转换；
  显式 `physics_world.entities[]` 默认视为已 bary（除非显式请求 l1）。转换元数据见
  `physics_frame_meta()`/`snapshot().physics_frame`；world 实体仍保留 L1 相对坐标（不写 world）。
  A0-T1 后这类帧转换会话的 world 副本同步策略为 `frame_mismatch`（显式不同步），
  保证不会把 bary_rot 数值写进 L1 语义的 world 实体。
- **Signal → TrackTable/EventBus**：SignalService 的 `sensor_observation.v1`/`track_evidence.v1`
  经白名单路由到 TrackTable（共享 target→track 映射，不重复建 track；elint.comms→elint；
  elint_fix→elint 类型归一）；`light_*` 事件映射为 `light_signal.*` 发布 EventBus；
  SignalService 不写 world/UI/V15。
- **Signal→Track 实体绑定**：写 TrackTable 前补 `entity_id`/`batch`（observation 与 evidence
  同一规则）：优先 `_sensor_target_meta[target_id]`（sensor 配置或 signal targets 自带
  entity_id/batch）；其次 world 同名实体（id/batch/name/kind/side）；不硬编码具体舰名；
  两者都缺失时保持空并在 session warnings 记一次（route 返回 `missing_meta/bound/world_bound`）。
  绑定后的 track 具备 entity_id/batch（`track_table.vm().tracks` 可直接给 UI 使用）。
- **IdentificationService（3R）**：证据融合/识别自动化；`identity_assessment`（L1–L4、
  confidence、sources、contradictions、spoof_suspicion、age）；自动分类最高 suspect/L3，
  hostile 需人工/授权，L4 需人工/授权或至少两类独立高置信证据；只输出
  `identity.<kind>` 事件，不写 world/TrackTable；自动询问只产生 query_request，
  由 session 经 TransponderService 执行（不发射武器）。
- **LegalStatusService（3X）**：ID13 法律状态（UNLISTED→WATCHLIST→RESTRICTED→
  DESIGNATED_ILLEGAL→HUNTED；CLEARED 极少数）；`apply_event(trigger,payload)` 累计
  heat/阈值迁移，去重、log、reason；`impact()` 只输出 `port_access(UEG/共管)/
  iff_watch_flag/combat_roe_modifier/ending_branch_hint`，**不**改 world side/
  港口/ROE/法律文本；不写 UI；CLEARED 锁定。
- **TrafficControlService（4D）**：可选 OTC/航道/NPC/伪装线索服务；session 在 tick
  调 `step(sim_dt)`（NPC 定时/窗口/clearance 过期/队列），API 委托申请/许可/占用/
  释放/伪装；事件白名单 `lane_record/otc_event/clue` 映射为 `traffic.*` 发布 EventBus；
  不写 world/TrackTable/UI；存档嵌入服务快照。
- **CombatBallistics（4H）**：可选弹道/导弹/PD/诱饵/线索服务；tick 用 session 实体
  （physics 优先，否则 world）的 pos/vel 构造 states 调 `step(sim_dt, states)`；API
  `combat_ballistics_launch/combat_predict/...`；impact 的 `damage_event` 白名单→
  DamageService（`applied=true`，shot_id 去重）；事件 `ballistics.*` 发布 EventBus；
  不写 world/TrackTable/UI；存档嵌入服务快照。
- **ShipCatalog/Refit/DamageProfile（5D）**：可选 `ship_catalog` 初始化目录；`entity_class_id`
  按 known_ship/entity_binding → 实体 class_id → TBD 解析，`class_vm` 返回舰级数据；
  可选 `refit` 初始化 RefitService（catalog/options/resources/location），API
  `refit_vm/refit_quote/refit_install/refit_remove/refit_commit/refit_tick/refit_stats`，
  成功操作发布 `refit.*` 事件；DamageService 建档带 class_id（旧 damage_l1 ships 显式档案
  属性优先），`damage_class_of/damage_profile_for` 可查；不写 world/UI；save 嵌入
  catalog 摘要与 refit 快照。
- **FleetFormation/FleetRefit（5G）**：可选 `fleet_formation` / `fleet_refit`（缺省互相联动
  启用，依赖 `ship_catalog`，未给则自动加载目录）；FleetRefitService 为 13 艘友舰各建独立
  RefitService、共享 credits/materials/location；FleetFormationService 提供 8 槽自由编组/
  command 必需/槽上限/角色兼容/总 mass-dv-crew/燃料/维修坞校验；事件 `fleet.*`/
  `fleet_refit.*` 进 EventBus；save 嵌入两服务快照。
- **弹道取态唯一入口 `_entity_kinematics(entity_id)`（4Z）**：返回
  `{ok, source:"physics_world"|"world", frame:"bary_rot", r[3], v[3], ...}`。
  顺序为 **物理世界优先 → 剧情世界兜底**，两者都没有才 `{ok:false, reason:"unknown_entity"}`。
  **禁止**用 `position_of()` 做弹道取态：该函数在 `physics_world_service != null` 时短路，
  一个空的物理世界会把剧情世界整个遮蔽掉，表现为"沙盒/序章实弹永远 `no_physics_state`"。
  **隐性契约**：`physics_world.state()` 的返回值**不含 `ok` 字段**，判成功只能看
  `r` 是否为长度 ≥3 的数组；`_entity_kinematics` 负责把它归一化成带 `ok/source/frame` 的形状，
  调用方一律以归一化后的形状为准。
- **本舰解析 `_own_ballistics_entity(states)`（4Z）**：候选链
  `seed.own_entity` → `combat_service.own_id` → 实体 tags(`own`/`own_fleet`) →
  实体 `has_pd` → `side == "friend"`，取第一个能在 states 里命中的 id；都没有返回 `""`。
  `combat_ballistics.config.pd_platform_id` 的哨兵值 `"own"` 在 `_ballistics_states()` 里
  用同一条链解析成真实实体 id（config 写死 id 亦可）。

- **TransponderService（3P）**：应答机行为层（ship 绑 entity，station/port/fuel/tank/otc/relay
  绑 FacilityRegistry）；询问/广播输出 `track_evidence.v1`（→TrackTable 白名单）与
  `transponder_event.v1`（→bus `transponder.<kind>`）；不写 world；触发只输出 trigger_id/event，
  不硬编码剧情文本。
- **FacilityRegistry（3O）**：只读设施注册表（7 cluster / 29 facility / 57 ports：
  L1–L5 20 站 + NESOSS-06 + LUNSYNC-03 TBD 提案）；不写 world/UI、不改现有实体；
  `facility_for_entity` 只按 `entity_ids` 绑定读取（L1-05↔l1_station），不做实体移动。
- **Signal 动态目标（3N）**：session 包装 `signal_upsert_target/signal_remove_target/
  signal_set_targets/signal_sync_targets/signal_target_ids/signal_target`；
  `signal_sync_from_world()` 从 world 实体（只读）同步目标，`signal_sync_from_contacts()`
  从 TrackTable 接触同步目标（id 优先 entity_id）；均只写 SignalService，不写 world。
  灯语不因 `side` 拒绝（hostile/neutral/unknown 均可发）；ACK 由目标
  `light_capable/receiver_facing/active/destroyed` 能力/状态决定，失败保持 RECEIVED、不伪造回应。
- seed/demo 数据仅示例，**不进入关卡**。

## 2　boot(config)

`boot(config := {})` 返回 `{ok,ready,booted,writer,t_s,errors,warnings,snapshot}`；
空 config 使用 demo seed（3 实体：apsis/harmattan/l1_station；节点 3；链路 2：apsis↔harmattan LD、
harmattan↔l1_station LR；无订单；**不启用** TrackTable/StoryState）。

config 可覆盖字段（省略用 demo）：

| 字段 | 说明 |
| --- | --- |
| `time` | TimeService 参数（t_s/epoch_s/scale/max_dt_s/paused…） |
| `writer` | WorldState 写者 token（默认 `session`） |
| `entities[]` | seed 实体（id/batch/kind/name/pos_km/vel_kmps/flags） |
| `nodes[]` / `links[]` | CommsService 节点/链路（a/b/mode/latency_s/range_km/packet_loss/jam/occluded/enabled） |
| `orders[]` | seed 订单（action/issuer_id/target_ids/params/opts/issue:bool） |
| `order_mode` / `comms_text_key` / `delivery_delay_s` | 订单默认通信模式/发送文本键/本地延迟 |
| `track_table` | **可选**：`true` 或配置字典（writer_id/stale_after_s/forget_after_s/max_tracks…）；缺省/`false` → 不组合 |
| `story_state` | **可选**：`true` 或 StoryState seed 字典（flags/evidence_ids/trust…）；缺省/`false` → 不组合 |
| `sensor_service` | **可选**：`true` 或 SensorService 配置字典（`observer`/`mounts`/`targets`/`snapshot`/`options`）；缺省/`false` → 不组合 |
| `port_service` | **可选**：`true` 或 PortService 配置（`ports[]` 泊位/船坞/拖船/燃料/窗口/许可/services）；缺省/`false` → 不组合 |
| `combat_service` | **可选**：`true` 或 CombatService 配置（`content_path`(weapons_l1)/`roe`/`own_id`/`fleet_id`）；缺省/`false` → 不组合 |
| `damage_service` | **可选**：`true` 或 DamageService 配置（`content_path`(damage_l1)/`ships[]`/`default_ship`）；缺省/`false` → 不组合 |
| `physics_world` | **可选**：`true` 或 PhysicsWorld 配置（`step_s`≤60/`sun`/`ephemeris_path`/`entities[]`/`auto_seed`/`seed_frame`/`frame_origin`）；缺省/`false` → 不组合；启用时 seed 实体自动灌入（auto_seed=false 可关）。4F 帧：`seed_frame=auto/l1/bary_rot/none`、`frame_origin=auto/l1/[x,y,z]/bary_rot/none`，也可放 top-level |
| `signal_service` | **可选**：`true` 或 SignalService 配置（`observer`/`targets`/`stations`/`elint`/`codes_path`/`light_codes`/`emitters[]`/`month`/`time`）；缺省/`false` → 不组合；启用时 ELINT/灯语可用 |
| `ew_service` | **可选**：`true` 或 EWService 配置（`observer`/`targets`/`emcon`）；缺省/`false` → 不组合；启用时 tick/事件 bus/效果接口/存档可用 |
| `facility_registry` | **可选**：`true`（默认设施内容）或 `{content_path/content}`；缺省/`false` → 不组合；只读注册表 |
| `transponder_service` | **可选**：`true`（默认序章内容）或配置 `{content_path/content/max_range_km/max_latency_s/jam}`；缺省/`false` → 不组合；station 绑定自动注入 FacilityRegistry |
| `identification_service` | **可选**：`true` 或配置 `{auto{enabled,interval_s,modes,max_range_km,...}/evidence_ttl_s/decay_half_life_s}`；缺省/`false` → 不组合 |
| `legal_status` | **可选**：`true` 或配置 `{thresholds/weights/impacts/decay_per_day/allow_deescalation}`；缺省/`false` → 不组合；旧档兼容 |
| `traffic_control` | **可选**：`true` 或配置 `{facilities_path/lanes_path/facilities_content/lanes_content}`；缺省/`false` → 不组合；旧档兼容 |
| `combat_ballistics` | **可选**：`true` 或配置 `{content_path(weapons_l1)/content/pd_platform_id}`；缺省/`false` → 不组合；旧档兼容 |
| `ship_catalog` | **可选**：`true` 或 ShipCatalog 配置 `{friendly_path/enemy_path}`；缺省/`false` → 不组合；坏内容 boot 失败 |
| `refit` | **可选**：`true` 或 RefitService 配置 `{options/options_path/resources/location}`；缺 catalog 自动加载；旧档兼容 |
| `damage_profiles` | **可选**：`true` 或 DamageProfileService 配置；catalog 启用时自动建 profile service |
| `fleet_formation` | **可选**：`true` 或 `{roster/roster_path}`；缺省与 `fleet_refit` 互相联动启用；依赖 ShipCatalog |
| `fleet_refit` | **可选**：`true` 或 `{roster/options/resources/location}`；显式 `false` 可只保留 formation |
| `own_entity` | **本舰实体 id**（4Z，字符串）：弹道 shooter 解析、`pd_platform_id="own"` 哨兵解析的唯一显式来源。**在 seed 白名单内**（不在白名单的字段会被 `_normalize_seed` 丢弃）；缺省时走 `combat_service.own_id` → tags → side 兜底 |
| `seed_frame` / `frame_origin` / `prelude` | 帧转换开关（4F）：`auto/l1/bary_rot/none`；**沙盒必须显式 `bary_rot`**，否则会被套用 L1 相对帧导致整图平移 32 万公里 |

- boot 建 5 个必需组件 + 可选 TrackTable/StoryState；任一启用组件 `ready=false` → `ok=false` + errors，不伪造。
- TrackTable 默认 writer = `<session writer>_fusion`；StoryState 时间在 boot 时对齐 session 时间。
- seed 实体：bus 发布 `entity.spawn` + world.apply（session 写者）；seed 订单可选 `issue:true`。

## 3　API

| API | 说明 |
| --- | --- |
| `tick(dt) -> Dictionary` | 时间推进 → 订单/通信 tick（scaled dt）→ 订单事件发布 → **TrackTable.tick/story.set_time** → 白名单总线路由 → 通信投递对账；返回 `{ok,t_s,paused,dt_scaled_s,events,routed,components,order_counts,contracts}` |
| `pause()` / `resume()` / `set_scale(s)` | 时间控制；暂停时 tick 不推进订单/通信/轨道/剧情时间 |
| `issue_order` / `authorize_order` / `begin_execute_order` / `complete_order` / `abort_order` / `reject_order` | 订单包装（含 events） |
| `send_comms` / `set_link` | 通信/链路包装 |
| `handle_observation(observation)` | 观测 → TrackTable（需启用；自动补 t；单写者 writer；失败不改状态） |
| `handle_evidence(evidence)` | **TrackTable 证据**（`track_evidence.v1`）→ L3/L4 |
| `handle_story_evidence(evidence_id)` | **StoryState 证据**（独立于 TrackTable 证据） |
| `route_event(event)` | 显式白名单事件：应用组件 + 发布 bus；不在白名单 → `not_routable`，不写组件 |
| `track_vm(opts={})` / `track_filter(where={})` | 只读 TrackTable VM/过滤（未启用返回空） |
| `story_vm()` / `gate(conditions)` | 只读 StoryState 快照/条件判定（未启用返回空/`no_story_state`） |
| `sensor_vm()` | 只读 SensorService VM（未启用返回空） |
| `set_sensor_target(target_id)` | 选中传感器目标（未知目标 `unknown_target`，失败不改状态） |
| `start_sensor_channel(kind, target, opts={})` / `stop_sensor_channel(kind, target)` | 启停 optical/ir 通道 |
| `set_radar_enabled(on)` / `set_emcon(on)` | 雷达开关/EMCON（关闭主动雷达观测；被动光学/IR 继续） |
| `query_iff(target_id="")` | 显式 IFF 询问：产生 iff evidence（support 4），成功后显式路由到 TrackTable；`never_hostile=true` |
| `port_request/port_permit/port_approach/port_dock/port_refuel/port_repair/port_finish_service/port_undock` | PortService 委托（失败不改状态；成功记录 log） |
| `port_tow/port_shuttle/port_services/port_vm/port_summary` | 拖曳/穿梭机委托与只读 VM |
| `set_roe/combat_register_track/combat_request_solution/grant_authorization/revoke_authorization` | CombatService 委托（失败不改状态） |
| `request_fire(target_id, weapon_id, confirmed=false, opts={})` | **统一开火路径（4Z）**。顺序：`no_combat_service` → `unknown_track` → `no_ballistics` → **`no_physics_state`**（物理前置检查）→ CombatService 门禁（ROE/授权/确认/冷却/弹药/齐射）→ `combat_ballistics.launch()`。成功返回 `{ok, launched, projectile_ids[], salvo, shooter_id, target_entity, physics:"ballistics", launch, prediction, plan?, time_cap}`；**开火不判命中**，命中由后续 tick 的弹道积分产生 `ballistics.impact` 并经白名单进 DamageService。`opts`：`target_entity`/`shooter_id`/`intent`(direct/silent/offset/multi_axis)/`plan`/`profile`/`force_pd` |
| `set_weapon_salvo(weapon_id, n)` | 玩家设置齐射数（钳制到 `[1, salvo_max]`）；返回 `{ok, salvo, salvo_max}`；记 `set_weapon_salvo` 日志 |
| `combat_predict_track(target_id, weapon_id)` | 按航迹 id 做**真实弹道预测**（CR3BP RK4 + 射击法；不发射）；无物理状态 → `no_physics_state` |
| `combat_plan(target_id, weapon_id, intent="direct", opts={})` | **规划辅助**：意图 → 巡航剖面（Δv 时序点）+ 可行性/预算；`salvo>1` 自动走 `plan_salvo`；发射前可预演 |
| `combat_time_cap_state()` | 交战倍速状态 `{active, restore_to, cap:60.0, scale}`；由 `_apply_combat_time_cap()` 在开火/tick 时驱动 |
| `combat_authorization/combat_vm/combat_summary/flush_events` | 授权查询/只读 VM/立即 flush Port+Combat+Dage bus 事件 |
| `damage_apply_event/damage_apply_hit/damage_repair/damage_fix/damage_cancel_repair/damage_set_priority` | DamageService 委托（直接伤害/维修；失败不改状态） |
| `damage_vm/damage_ship_vm/damage_summary/damage_ships` | 只读损管 VM/摘要/舰列表 |
| `physics_vm/physics_summary/physics_state/physics_entity_ids/physics_positions/position_of` | PhysicsWorld 只读 VM/状态/位置权威读取（position_of 无 physics 时退回 world 只读） |
| `physics_frame_meta()` / `physics_l1_position()` | 4F 帧转换元数据（seed_frame/frame_origin/offset/applied/converted/conversion_count/reason）与 L1 bary 位置 |
| `upsert_physics_entity/remove_physics_entity/set_physics_time` | 物理实体增删/显式设置物理时间（向前推进整个 session；暂停/回退拒绝） |
| `sync_world_from_physics` | **显式全量同步**：把 physics 位置/速度写一遍到 world 已有实体并发布 `physics.world_synced`（tick 边界已自动同步只读副本；单向、不反向写 physics） |
| `world_physics_sync(reason)` / `world_physics_sync_status()` | A0-T1：tick 边界副本同步入口与只读诊断（`enabled/mode/frame/in_sync/compared/mismatched/sync_count/last`；`frame_mismatch` 会话显式不同步） |
| `signal_intercept/signal_df/signal_resolve` | ELINT 拦截/多站 DF/候选 fix 解析；失败不改状态 |
| `signal_upsert_target/signal_remove_target/signal_set_targets/signal_sync_targets` | Signal 动态目标增删/全量替换/增量同步（side/light_capable/receiver_facing 等）；失败不改状态 |
| `signal_target_ids/signal_target/signal_sync_from_world/signal_sync_from_contacts` | 目标只读/从 world 实体或 TrackTable 接触同步（只读 source，不写 world） |
| `facility_lookup/facility_by_transponder/facility_for_entity/facilities_by_cluster` | 设施卡片/应答机识别/实体绑定/按 cluster 查询（只读） |
| `facility_vm/facility_summary` | 全设施内容/摘要（只读，不写 world/UI） |
| `transponder_interrogate/transponder_broadcast/transponder_passive_listen/transponder_lookup_code` | 应答机询问/广播/被动监听/注册码查询；evidence→TrackTable、事件→bus |
| `transponder_set_status/transponder_set_crypto/transponder_set_jam/transponder_set_occlusion` | 应答机状态/加密/干扰/遮挡（失败不改状态） |
| `transponder_upsert_profile/transponder_remove_profile/transponder_profile/transponder_vm/transponder_summary/transponder_trigger_ids` | profile 管理/只读 VM/摘要/触发 ID |
| `identification_ingest/identification_step/identification_assess/identification_get/identification_auto_tick` | 身份证据融合/推进/评估/只读/自动询问（auto_tick 经 transponder 执行请求并回灌） |
| `identification_set_auto/identification_manual_confirm/identification_authorize_hostile/identification_clear_manual` | 自动策略/人工确认/授权 hostile/清除人工 |
| `identification_set_target_state/identification_vm/identification_summary/identification_take_query_requests` | 询问条件/只读 VM/摘要/取 query_request |
| `legal_apply_event/apply_legal_event/legal_set_status/legal_tick` | ID13 法律状态事件/显式设置/时间推进（可选组件；失败不改状态） |
| `legal_vm/legal_summary/legal_impact/legal_status_text` | 只读 VM/摘要/影响标志/当前状态 |
| `legal_port_access/legal_iff_watch_flag/legal_combat_roe_modifier/legal_ending_branch_hint` | UEG/共管港访问、IFF watch、ROE 修正、结局分支提示（只输出标志） |
| `traffic_vm/traffic_summary/traffic_lane/traffic_otc_for/traffic_clues` | OTC/航道/NPC/伪装线索只读查询（可选组件；无组件返回空） |
| `traffic_request/traffic_permit/traffic_occupy/traffic_release/traffic_disguise` | 交通申请/许可/占用/释放/伪装（服务显式 API 委托；失败不改状态） |
| `combat_ballistics_vm/combat_ballistics_summary/combat_ballistics_active/combat_ballistics_intercepts/combat_ballistics_impacts/combat_ballistics_pd` | 弹道 VM/摘要/主动弹/拦截/命中/PD 只读（无组件返回空） |
| `combat_ballistics_launch/combat_predict/ballistics_launch` | 用 session 实体状态发射/预测；失败 reason；不写 world |
| `ship_catalog` | **可选**：`true` 或 ShipCatalog 配置（`friendly_path/enemy_path`）；缺省不组合；坏内容 boot 失败 |
| `refit` | **可选**：`true` 或 RefitService 配置（`options/options_path/resources/location`）；缺 catalog 时自动加载；不写 world/UI |
| `damage_profiles` | **可选**：`true` 或 DamageProfileService 配置；catalog 启用时自动建 profile service |
| `fleet_formation` | **可选**：`true` 或 `{roster/roster_path}`；缺省与 `fleet_refit` 互相联动启用；依赖 ShipCatalog |
| `fleet_refit` | **可选**：`true` 或 `{roster/options/resources/location}`；显式 `false` 可只保留 formation |
| `entity_class_id/class_vm/ship_catalog_vm/ship_catalog_summary` | 实体→舰级（known_ship/binding→实体 class_id→TBD）；舰级只读数据 |
| `damage_class_of/damage_profile_for` | DamageService 模型的 class_id/profile_source / DamageProfile 查询 |
| `refit_vm/refit_slots/refit_options/refit_quote/refit_install/refit_remove/refit_commit/refit_tick/refit_stats` | APSIS 改装事务 API（quote/install 支持 id 或模块对象）；成功发 `refit.*` 事件 |
| `fleet_vm/fleet_summary/fleet_roster/fleet_slots/fleet_assign/fleet_unassign/fleet_move/fleet_validate/fleet_stats` | 5G 舰队编制（13 舰/8 槽）；成功发 `fleet.*`；不写 world/UI |
| `fleet_refit_vm/fleet_refit_ships/fleet_select_ship/fleet_options/fleet_quote/fleet_install/fleet_remove/fleet_commit/fleet_refit_tick/fleet_refit_stats/fleet_refit_state` | 5G 全舰队改装（共享资源/逐舰独立）；成功发 `fleet_refit.*` |
| 别名 `select_ship/options/quote/install/remove/commit/stats` | 对齐 5G task API；`tick` 与主 tick 冲突，用 `fleet_refit_tick` |
| `light_send/light_receive/light_ack/signal_vm/signal_summary/signal_flush_events` | 可见光灯语发送/接收/确认、只读 VM/摘要、显式拉取 Signal outbox |
| `apply_ew/ew_observation_effect/ew_comms_effect/ew_transponder_effect/ew_active/ew_vm` | EW 效果应用/观测-通信-应答机影响/活动效果/只读 VM；apply 记录 log 可 replay |
| `set_ew_emcon` | EW EMCON 开关（独立于 sensor `set_emcon`；只写 EWService） |
| `order(id)` / `comms_pending()` | 只读查询 |
| `snapshot()` / `to_dict()` / `to_json()` | 只读快照（time/world/orders/comms/bus 最近 32 事件/track/story/contracts/errors） |
| `save_state() -> String` / `load_state(json) -> Dictionary` | **内存 JSON**：seed + 操作日志重放 + track/story/bus 快照 |
| `check_contracts()` / `reset()` | DbC 检查/按原 seed 重开 |

### 3.1　tick 语义

1. 非有限/负 dt 拒绝；暂停时返回 `paused=true`，时间/订单/通信/轨道/剧情/physics 均不推进；
2. `TimeService.tick(dt)` 乘以 scale 得 `sim_dt`；
3. **`physics_world.step(sim_dt)`（固定步长；位置权威，先于 orders/world/sensor/track）**；
4. `orders.tick(sim_dt)`（内部推进 comms）；`orders.take_events()` → 发布 `order.<event>`；
5. `track_table.tick(sim_dt)`（stale/forget 过期）；`story_state.set_time(now_s)`；
6. `sensor_service.step(sim_dt)` → `take_events()` → 只路由 observation（support 1..2）/evidence
   到 TrackTable（target_id 映射到已建 track；support=0/>2 忽略；控制事件忽略）；
7. `signal_service.step(sim_dt)`（ELINT/灯语超时）；outbox 白名单：
   observation/evidence→（补 entity_id/batch 绑定后）TrackTable（不重复建 track）、
   light_*→`light_signal.*` bus；
8. `ew_service.step(sim_dt)`（效果过期/衰减）；EW 事件 → `ew.<kind>` bus；不写 world/TrackTable；
8. `port_service.tick(sim_dt)` / `combat_service.tick(sim_dt)`；各自 outbox 事件 → `port.*`/`combat.*`
   发布到 EventBus（tick 自动 flush；也可 `flush_events()` 显式拉取）；
9. combat `combat_damage_event` 白名单 → DamageService（applied=true）；`damage_service.tick(sim_dt)`
   推进火灾/失压/断电/维修；damage.* 事件发布到 bus；
9b. `legal_status_service.tick(sim_dt)`（可选；decay/状态变化只写 LegalStatusService 日志与
   `legal_status_tick` 返回；**不**写 world/TrackTable/其他组件）；
9c. `traffic_control.step(sim_dt)`（可选；NPC/窗口/队列；outbox 白名单
   `lane_record/otc_event/clue` → `traffic.*` EventBus；**不**写 world/TrackTable/UI；
   结果在 `traffic_step`，components.traffic=true）；
9d. `combat_ballistics.step(sim_dt, session_states)`（可选；states 来自 physics/world
   实体 pos/vel；outbox 事件 → `ballistics.*` EventBus；impact.damage_event →
   DamageService（shot_id 去重）；**不**写 world/TrackTable/UI；结果在 `ballistics_step`，
   components.combat_ballistics=true）；
10. 白名单总线路由：tick 处理 bus 中未被路由且类型在白名单的事件（`track.observation` 等）；
11. standalone `send_comms` 的投递对账：tick 后 pending 消失 → 发布 `comms.delivered`；
12. 事件 bus 只接收发布；不改变 world 实体（probe 断言 tick 前后 world 不变；physics 也
    不在 tick 中自动写 world，需显式 sync；signal 只写 TrackTable/bus）。

### 3.2　事件类型

- session 发布：`entity.spawn`（seed）、`order.*`、`comms.sent/delivered/failed`、`comms.link`。
- **可路由白名单（bus → 组件）**：`story.flag`（payload flag/value）、`story.evidence`（evidence_id）、
  `story.choice`（choice_id/meta）、`track.observation`（observation 对象）、`track.evidence`（证据对象）。
- 非白名单类型（如 `entity.move`、`order.*`、`comms.*`）**不写** TrackTable/StoryState。
- SensorService 输出不经过 bus（session 直接 take_events 并显式过滤）；其 observation/evidence
  与 TrackTable 输入 schema 一致，控制事件不路由。
- TrafficControl 事件：`traffic.lane_record/otc_event/clue`（payload 保留 schema/kind/seq/payload；只读）。
- CombatBallistics 事件：`ballistics.launch/impact/pd_launch/projectile_intercepted/miss/
  projectile_expired/countermeasure_*`；impact payload 内 `damage_event.applied=true`
  （已路由 DamageService；只读发布，不回写 world）。
- Refit 事件：`refit.install/remove/commit/tick`（成功操作发布；payload 含 module_id/committed/
  costs/completed；只读，不写 world/UI）。
- Fleet 事件：`fleet.assign/unassign/move/validated`、`fleet_refit.select_ship/install/remove/
  commit/tick`（成功操作发布；payload 含 ship_id/module_id/slot/committed；只读，不写 world/UI）。
- PortService 事件：`port.request_created/granted/denied/held/expired/approach/docked/service_started/
  service_finished/departed`；CombatService 事件：`combat.<kind>`（weapon_launch/combat_hit/combat_miss/
  point_defense/authorization_*/roe_* 等），均为只读事件。
- DamageService 事件：`damage.applied/repair_queued/repair_cancelled/repair_priority/tick`；
  combat damage 应用后 bus 上对应 combat 事件的 `payload.damage_event.applied=true`。
- PhysicsWorld 事件：`physics.world_ready/entity_added/entity_updated/entity_removed/
  step_started/step_completed/jacobi_drift/time_set`（防重复）；显式同步发布
  `physics.world_synced`。
- SignalService 事件：`light_signal.send/receive/ack/timeout/occluded/misread`（→ EventBus）；
  observation/evidence 不进 bus，只走 TrackTable 白名单。

## 4　DbC / 一致性

`check_contracts()` 返回 `{ok, violations[]}`：

- **单写者**：`world.current_writer() == session.writer`；TrackTable `current_writer()==_track_writer`；
  外部 token 写 world → `writer_mismatch`，写 track → `unauthorized_writer`。
- **时间单调**：session last_time_s；TimeService 不变量；`orders.t`、`track_table.t`、
  `story_state.t_s` 均与 `now_s()` 同步（非暂停）。
- **版本单调**：story `revision` 不回退（track 以 t/等级单调 + 事件 seq 保证）。
- **订单-通信一致**：活动订单必须有 `delivery_id`；`issued_t` 不超过会话时间。
- **世界时钟**：`world.clock_t_s() == session.now_s()`。
- **组件失败不改状态**：observation/evidence/route 非法时返回 `{ok:false,reason}`，TrackTable/StoryState
  不部分写入；tick 路由失败写 warnings（不静默）。
- **传感器一致**：`sensor_service.t == now_s()`；失败控制（未知目标/非法通道/非法 stop/无传感器）
  返回 `{ok:false,reason}`，sensor 计数/状态不变；IFF 只给 friend/unknown，不自动判敌。
- **Port/Combat 一致**：`port_service.t_s == combat_service.t == now_s()`；两者 ready 且内部
  contracts/ROE 合法；失败委托（无服务/错误状态/非法 ROE/冷却/未授权）不改组件状态。
- **Damage 一致**：`damage_service.t == now_s()`、ready、内部 contracts ok；combat damage 只在
  whitelist 路由且 `shot_id` 去重；伤害/维修失败不改状态。
- **Physics 一致**：`physics_world.t == now_s()`、ready、内部 contracts ok；tick 顺序
  time→physics→world 副本同步固定；暂停不推进；`mode=tick` 时 world 位置/速度副本必须与
  physics 逐位一致（不变量），`frame_mismatch` 会话显式不同步且不参与该不变量。
- **Signal 一致**：`signal_service.t == now_s()`、ready；ELINT observation/evidence 只进
  TrackTable（不重复建 track），light 事件只进 bus；不写 world/UI/V15；失败委托不改状态。
- **Signal 绑定一致**：observation/evidence 的 entity_id/batch 来自 target_meta/world；
  同一 target 的 evidence 复用 observation 建的 track；缺失绑定留空 + warning，不猜实体。
- **Signal 目标一致**：动态目标 side/能力字段只存在于 SignalService；world/contacts 同步
  只读、不双写；灯语发送不看 side；ACK 只看目标能力/状态（无能力时不伪造回应）。
- **Facility 一致**：`facility_registry.ready` 且内部 contracts ok；查询/卡片不写 world；
  `facility_for_entity` 只读 entity_ids 绑定；未启用时 API 返回空/`no_facility_registry`。
- **Transponder 一致**：`transponder_service.t == now_s()`、ready、contracts ok；evidence 只走
  TrackTable 白名单、事件只走 bus；不写 world；captured/spoofed 不改 identity 为 hostile；
  触发只输出 trigger_id/event，不写剧情文本。
- **Identification 一致**：`identification_service.t == now_s()`、ready、contracts ok；
  自动身份永不 hostile；hostile 必须 authorized；L4 需 manual/授权或两类独立高置信证据；
  自动询问只经 transponder 执行、不发射武器；不写 world/TrackTable。
- **LegalStatus 一致**：`legal_status_service.ready` 且自身 contracts ok（status/heat/log/
  阈值递增）；只输出 impact 标志，不改 world side/港口/ROE/法律文本；CLEARED 锁定；
  日志中的 legal op 在未启用组件的旧档中跳过。
- **Traffic 一致**：`traffic_control.ready`、`t == now_s()`、vm().writes 全 false；
  `traffic.*` 事件只读发布，不由 bus 回写 world/TrackTable；旧档缺字段/seed 配置 →
  组件退化、traffic replay 跳过（skipped:no_traffic_control）。
- **CombatBallistics 一致**：`combat_ballistics.ready`、`t == now_s()`、vm().writes 全 false；
  tick states 来自 physics/world 只读；impact `damage_event` 只经白名单进 DamageService，
  `shot_id` 去重（重复 tick 不二次应用）；`ballistics.*` 事件只读发布；旧档缺字段/seed
  配置 → 组件退化、ballistics replay 跳过（skipped:no_combat_ballistics）。
- **5D 一致**：`ship_catalog.ready`（若启用）、`refit_service.ready/check_contracts`、
  `damage_profile_service.ready`；`entity_class_id` 只读解析（不写 world）；refit 事务
  `planned→commit→queue→tick`，不写 world/UI；save 含 `ship_catalog/catalog/refit/
  damage_profile`；旧档缺字段 → catalog/refit 退化（entity_class TBD、refit API
  `no_refit_service`），不报错；存档含 refit 但 seed 未启用 → replay error。
- **5G 一致**：`fleet_refit.ready`/`fleet_formation.ready`（若启用）；FleetRefit 13 舰独立
  refit state、共享 resources；FleetFormation 8 槽/command 必需/总 mass-dv-crew/燃料/维修
  校验；`fleet.*`/`fleet_refit.*` 事件只读发布，不写 world/TrackTable/UI；save 含两快照；
  旧档缺字段 → fleet 退化（API `no_fleet_refit/no_fleet_formation`），不报错。
- **统一开火路径一致（4Z）**：`request_fire()` 的前置检查顺序固定为
  `no_combat_service → unknown_track → no_ballistics → no_physics_state → 门禁 → launch`，
  **任何前置检查失败都不得扣弹药、不得改航迹/授权状态**（返回 `ok=false` + `reason`，
  且 `combat_service` 的弹药计数与 fire 计数保持不变）。成功路径必须满足
  `launched == salvo`（弹药不足时 CombatService 直接拒绝 `insufficient_ammo_for_salvo` 并给
  `salvo_max`，要求玩家重设齐射数，**不做部分发射**）。
  `projectile_ids` 长度必须等于 `launched`（单发兼容字段 `projectile_id` 也一并回填）。
  **命中不在开火时判定**：`request_fire` 返回 `ok=true` 只代表弹丸已进入物理积分，
  战果（`damage_taken`/航迹终态）只能由后续 tick 的 impact 产生。
- **交战倍速一致（4Z）**：`_apply_combat_time_cap()` 只在 `active_projectiles() > 0` 时把
  `time.scale` 压到 `COMBAT_SCALE_CAP(60.0)`，并在弹全部消失后**恢复进入交战前的倍速**
  （`_scale_before_combat`）；非交战期间不反复改倍速（幂等）；返回
  `{ok, capped, scale, restore_to?}`，状态经 `combat_time_cap_state()` 只读查询。
  降倍速会 append 一条 `warnings`，不静默。

- tick 失败/拒绝路径不静默：返回 `ok=false` + `errors/contract_errors`；失败订单不伪造状态。

## 5　内存 save/load（不写盘）

`save_state()` 返回 JSON：

```text
{
  schema:"v17.game_session_save.v1", version:"1.0.0",
  seed: {time/writer/entities/nodes/links/orders/.../track_table/story_state},
  log: [ {op:"tick"/"issue_order"/.../ "handle_observation"/"handle_evidence"/
          "handle_story_evidence"/"route_event", ...} ],
  track_table: <V2FusedTrackTable.snapshot()> | null,
  story: <StoryState.snapshot()> | null,
  port_service: <PortService.save_state() JSON> | "",
  combat_service: <CombatService.save_state() JSON> | "",
  damage_service: <DamageService.save_state() JSON> | "",
  physics_world: <PhysicsWorld.save_state() JSON> | "",
  physics_frame: <帧转换 meta> | null,
  signal_service: <SignalService.save_state() JSON> | "",
ew_service: <EWService.save_state() JSON> | "",
  facility_registry: <FacilityRegistry.to_dict()> | null,
  transponder_service: <TransponderService.save_state() JSON> | "",
  identification_service: <IdentificationService.save_state() JSON> | "",
  legal_status_service: <LegalStatusService.save_state() JSON> | "",
  traffic_control: <TrafficControlService.save_state() JSON> | "",
  combat_ballistics: <CombatBallistics.save_state() JSON> | "",
  ship_catalog: {schema, summary} | null,
  catalog: {schema, summary} | null,          # 别名
  damage_profile: <DamageProfileService.summary()> | null,
  refit: <RefitService.save_state()> | null,
  fleet_formation: <FleetFormationService.save_state()> | null,
  fleet_refit: <FleetRefitService.save_state()> | null,
  bus: {seq, events[]}
}
```

**Damage 存档**：save 嵌入 DamageService 每舰模型快照；load boot 重建 + log 重放 +
damage 快照恢复；load 后 damage VM/snapshot 一致、t 同步、可继续维修/tick、再次 save 一致。
旧存档缺 `damage_service` 字段/seed 配置 → damage 操作 replay 跳过、组件退化。

**Physics 存档**：save 嵌入 PhysicsWorld 快照（entities r/v/steps/samples/events）；
load boot(seed) 自动灌入/重放 tick → physics 快照恢复（双精度完全一致），load 后
physics VM/snapshot 一致、t 同步、可继续 tick，再次 save 一致。旧存档缺
`physics_world` 字段/seed 配置 → physics 操作 replay 跳过（skipped:no_physics_world）、
组件退化；不自动把旧 world 位置搬入 physics。

**Signal 存档**：save 嵌入 SignalService 快照（ELINT/DF/候选/observations/evidence/**动态
targets**/灯语 transmissions/events）；load boot(seed)+log 重放+signal 快照恢复；load 后
signal VM/snapshot 一致、t 同步、TrackTable/bus 历史一致、可继续 intercept/灯语/tick、再次 save 一致。
旧存档缺 `signal_service` 字段/seed 配置 → signal 操作 replay 跳过（skipped:no_signal_service）、
组件退化；旧 signal 快照缺 `targets` → 按 boot+log 重建目标列表。

**Facility 存档**：save 嵌入 FacilityRegistry 完整内容（cluster/facility/ports/physical）；
load boot(seed) 重建 + 快照恢复（校验后应用）；load 后 facility_vm/summary 一致、contracts ok、
不再写 world；旧存档缺 `facility_registry` 字段/seed 配置 → 组件退化。

**EW 存档**：save 嵌入 EWService 快照（effects/events/emcon/t/seq）；load boot+log 重放后恢复，load 后 ew VM/snapshot 一致、可继续 tick/效果查询；旧存档缺 `ew_service` 字段/seed 配置 → 组件退化、EW replay 跳过（skipped:no_ew_service）。`apply_ew`/`ew_emcon` 记录操作日志。

**Transponder 存档**：save 嵌入 TransponderService 快照（profiles 运行时状态/events/evidence/
triggers/jam/occlusion）；load 校验 profile 后恢复；load 后 transponder_vm/snapshot 一致、
t 同步、可继续询问/广播；旧存档缺字段/seed 配置 → 组件退化。

**Identification 存档**：save 嵌入 IdentificationService 快照（evidence/assessments/
target_states/auto/query_requests/events）；load 校验后恢复；load 后 identification_vm/
snapshot 一致、t 同步、可继续 assess/auto/manual；旧存档缺字段/seed 配置 → 组件退化。

**LegalStatus 存档**：save 嵌入 LegalStatusService 快照（status/heat/log/dedupe/
thresholds/weights/impacts/t/seq）；load 校验后恢复；load 后 legal_vm/snapshot 一致、
可继续 apply_event/set_status/tick；`legal_apply_event/legal_set_status/legal_tick`
记录操作日志；旧存档缺字段/seed 配置 → 组件退化、对应 legal replay 跳过
（`skipped:no_legal_status_service`），不报错。

**Physics 帧**：boot 以 seed 配置重建并做一次 L1→bary 转换（snapshot().physics_frame 记录）；
load 先 boot（按 seed/config 重新解析帧）再恢复 PhysicsWorld 快照，因此不会重复平移；
旧存档无 `physics_frame` 字段仍可加载（按 seed/config 推导）；`save_state` 的 seed 保留
`seed_frame/frame_origin/prelude`。

**Traffic 存档**：save 嵌入 TrafficControlService 快照（t/requests/clearances/
occupancies/active_npc/disguises/clues/records/events/seq）；load 校验后恢复；
load 后 traffic_vm/summary/snapshot 一致、可继续 request/permit/occupy/disguise；
`traffic_request/traffic_permit/traffic_occupy/traffic_release/traffic_disguise`
记录操作日志；旧存档缺字段/seed 配置 → 组件退化、对应 traffic replay 跳过
（`skipped:no_traffic_control`），不报错。

**CombatBallistics 存档**：save 嵌入 CombatBallistics 快照（projectiles/countermeasures/
intercepts/impacts/events/pd/seq）；load 校验后恢复；load 后 combat_ballistics_vm/
summary/snapshot 一致、可继续 launch/tick；`combat_ballistics_launch` 记录操作日志；
伤害已应用结果同时由 DamageService 快照恢复；旧存档缺字段/seed 配置 → 组件退化、
对应 ballistics replay 跳过（`skipped:no_combat_ballistics`），不报错。

**5D 存档**：save 嵌入 `ship_catalog`（schema+summary；`catalog` 为别名）、
`damage_profile` summary、`refit` save_state（location/t_days/resources/installed/planned/queue）；
load 先 boot(seed) 重建 catalog/refit，再恢复 refit 快照；load 后 entity_class/class_vm/
refit_stats 一致、可继续改装；旧存档缺 5D 字段/seed 配置 → catalog/refit 退化
（entity_class TBD、refit API `no_refit_service`），不报错；存档含 refit 而 seed 未启用 →
replay error。

**5G 存档**：save 嵌入 `fleet_formation`（assignments）与 `fleet_refit`（selected/
resources/13 舰 refit state）；load 后 roster/编组/各舰 refit stats/共享资源一致、
可继续编组/改装；旧档缺 5G 字段/seed 配置 → fleet 退化（API `no_fleet_formation/
no_fleet_refit`）、不报错；存档含 fleet 快照而 seed 未启用 → replay error。

**Port/Combat 存档**：save 嵌入二者 `save_state()` JSON；load 时先 boot(seed) 重建并按 log 重放
（port/combat 委托操作 + tick），再恢复快照；load 后 VM/snapshot 一致、时间与 session 同步、
可继续操作/再次 save。旧存档缺 `port_service/combat_service` 字段与 seed 配置时，replay 对应操作
被跳过（`skipped:no_port_service/no_combat_service`），组件退化、不报错。

**Sensor 重建**：save **不写 sensor 快照**；seed 保留 sensor_service 配置，log 记录控制操作
（set_sensor_target/start_sensor_channel/stop_sensor_channel/set_radar_enabled/set_emcon/query_iff）；
`load_state` 时 boot 重建 SensorService 并按 log 重放，tick 重放重新 step/路由 → sensor VM/计数/
summary 与保存前一致。旧存档 seed 无 sensor_service 时，log 中 sensor 操作 replay 被跳过
（`skipped:no_sensor_service`），不报错、组件退化。

- `load_state(json)`：校验 schema → `boot(seed)` → 重放 log → 恢复 `track_table/story/bus` 快照 →
  设置 writer/时间/事件索引 → 返回 ok/errors。
- 恢复后：track/story VM 与原状态一致、`track.t`/`story.t_s` 与 session 时间一致、contracts ok；
  可继续 tick/观测且再次 `save_state()` 规范化一致。
- **旧存档兼容**：缺 `track_table/story/bus` 字段、seed 无组件配置的旧 JSON → 正常 load，
  组件保持退化（不伪造）；旧存档核心时间/订单/世界/事件可恢复。
- JSON 数值往返按浮点（快照一致性用 JSON 规范化比较）；组件快照恢复失败 → `ok=false` + errors。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/session_probe.gd
# V17 SESSION PROBE RESULT: PASS=1541 FAIL=0（exit 0，只跑一次）
```

覆盖（40 节）：boot（多组件/seed 实体/节点链路/contracts/snapshot schema）；订单流
（ISSUED→…→DONE、事件类型、delivery_id、订单-通信一致、终态拒绝）；通信/链路；失败/过期/
撤销/拒绝；暂停/时标/时间单调；bus-world 分离与单写者；save/load snapshot 一致+二次 save；
错误路径；JSON/确定性；**可选组件**（无配置/false 退化、true 启用、退化 save/load）；
**TrackTable L1-L4**（单/多源观测 L1/L2、光学证据 L3、IFF L4、重复/非法/未授权拒绝、
stale/forget、filter、track t 同步）；**StoryState 集成**（story evidence/flag/choice 路由、
非白名单不写、gate/t_s/revision）；**组件存档**（track/story/bus 快照、load 后 VM/t/contracts
一致、继续操作、再次 save、无组件存档被启用会话读取兼容）；**旧存档缺字段兼容**；
**组件非法事件/确定性**（失败不改状态、总线路由失败 warning、同操作 snapshot/save 一致、
world/track 外部写拒绝）；**Sensor 可选/API**（无/false 退化、true 默认、空目标 ready、无传感器
API 返回 no_sensor_service）；**Sensor 管道**（雷达观测→track L1/L2、optical→L3、IFF→L4、
EMCON/雷达开关/通道启停、unknown_target/非法通道拒绝、sensor t 同步、不写 track_table/v15/world）；
**Sensor 存档**（seed+log 重建、load 后 sensor_vm/summary/track/snapshot/save 一致、继续控制 tick、
旧存档缺 sensor 配置兼容）；**Sensor 失败/确定性**（失败控制不改状态、support=0 忽略、
同操作 VM/snapshot/save 一致）；**Port/Combat 可选**（无配置退化、单启用、true 默认、
无服务 API 拒绝）；**Port 集成**（request→permit→approach→dock→refuel/repair→finish→undock、
tow/shuttle、port.* 事件进 bus、tick 不自动、失败不改状态）；**Combat 集成**（set_roe/register/
solution/READY/grant/check/confirmed fire/冷却拒绝/未知目标/友方拒绝/非法 ROE、combat.* 事件）；
**Port/Combat 存档**（save 嵌入两快照、load 后 VM/snapshot 一致、继续操作、旧档兼容、同操作确定性）；
**Damage 集成**（可选退化、直接伤害/维修/tick、damage.* 事件、combat incoming damage 白名单路由、
shot_id 去重、失败不改状态）；**EW 集成**（可选退化、apply/tick/bus、observation/comms/transponder 接口、EMCON、save/load）；**Damage 存档**（save 嵌入 damage 快照、load VM/snapshot 一致、
继续维修/tick、旧档兼容、同操作确定性）；**LegalStatus 集成**（可选退化、初始 UNLISTED、
apply_event/去重/影响接口、tick、save/load/旧档兼容、确定性）；**TrafficControl 集成**（可选退化、
110 设施/18 航道、request/permit/occupy/release/disguise、tick NPC/outbox→bus、线索、save/load/旧档/确定性）；
**Physics 帧（4F）**（Prelude L1→bary 平移、Earth/Moon 距旗舰、实体相对/速度、显式 bary/none/origin、
无重复转换、save/load、确定性）；**CombatBallistics 集成**（可选退化、predict/launch、tick 命中→
DamageService applied、PD 自动拦截、ballistics.* bus、失败不改状态、save/load/旧档/确定性）；
**统一开火路径（4Z，第 40 节）**（门禁→真实弹丸→异步 impact→Damage→倍速降档/恢复、
齐射/逐发散布/弹药不足拒绝+`salvo_max`、规划预演、`no_physics_state`、存档往返）；
**5D 集成**（catalog 32/8+24、变体 18、entity_class known_ship/binding/hull/batch/实体 class_id/TBD、
class_vm、refit 30 模块事务/槽位/质量/功率/成本/地点/事件、damage class_id 与旧 damage_l1
优先、save/load/旧档/失败原子/确定性）；**5G 集成**（fleet_formation/fleet_refit 联动启用、
13 舰/8 槽/19 位、自由 assign/move/unassign、command/角色/槽满/limits、refit 多舰共享资源/
逐舰独立、fleet.* + fleet_refit.* bus、save/load/旧档/坏配置/确定性）。
当前 `V17 SESSION PROBE RESULT: PASS=1541 FAIL=0`（含 legal/traffic/帧转换/ballistics/统一开火/5D/5G；exit 0，只跑一次）。

## 7　边界 / 未完成

- 只做**编排**：不实现物理/传感器/武器/ROE/UI/剧情文本；不接旧场景/HUD/transit；不写 V15。
- TrackTable/StoryState/SensorService/PortService/CombatService/DamageService/PhysicsWorld/SignalService 为**可选组合**；未配置时相关 API 返回空/`no_*`，session 退化运行。
- PhysicsWorld 启用时是实体位置唯一权威；world 位置只在显式 sync 后更新（单写者仍是 session），
  tick 不自动同步；无 physics 时 `position_of` 退回 world 只读。
- EWService 只输出效果/接口/事件；不写 world/TrackTable/transponder/UI；EMCON 只作用于 EWService，不直接关外部传感器；假目标只给候选；通信 spoof 不自动执行。
- SignalService 只输出 ELINT observation/evidence 与灯语事件；session 按白名单路由，不写
  world/UI/V15；ELINT 不判敌/不产生 contact；灯语只是可见光事件流。
- Signal 目标→实体绑定只读 `target_meta`/world 既有字段；不硬编码舰名、不凭空发明
  entity_id；无绑定 track 仍可用于方位/等级显示，但 UI 实体联动需等绑定或后续人工关联。
- Signal 动态目标是服务内部注册表；从 world/contacts 同步只读、不写 world；灯语 send 不按
  side 过滤；ACK 能力字段由上层配置/注册提供，不推断真实平台能力，无能力时不伪造 ACK。
- FacilityRegistry 只读内容/绑定；不写 world/UI、不生成实体/PortService、不做停靠物理；
  `ports[]` 只是数据绑定（port_id 供上层引用）；月同步站名 TBD 提案、物理参数原型占位。
- TransponderService 是行为/证据/触发层：不写 world/TrackTable/UI、不模拟真实 SSR/IFF 波形/
  Mode 5 密码学；不决定敌我；触发只输出 ID/event/reason 供 StoryRuntime 消费。
- IdentificationService 只做证据融合/识别建议：自动最高 suspect/L3，hostile 需授权，
  L4 需人工/授权或两类独立高置信证据；自动询问不发射武器；不写 world/TrackTable/UI；
  confidence/阈值是可调游戏参数，不复刻真实 IFF 概率模型。
- 4F 帧转换只发生在 boot physics seed 灌入（L1 相对→bary_rot）；world 实体不被改写。
  A0-T1 后这类会话的 world 副本同步策略为 `frame_mismatch`（**显式不同步**），
  `sync_world_from_physics()` 若被显式调用仍会把 bary 坐标写回 world（调用方自行决定帧语义）；
  不要混用 L1 相对坐标与 bary_rot 坐标。
- **A0-T1 未覆盖的位置消费者（明确记录）**：`CICView` 的位置由 `ownship+bearing+range` 派生且
  声明 `position_truth=false`（不读 physics truth，属信息战设计，不在本任务范围）；contacts
  `range_km` 来自航迹观测几何（保留航迹作为观测信息的语义，传感器目标几何绑定属后续 #4.1，
  **本任务不把 TrackTable 距离改成物理真值**）；`combat_ballistics`/`_ballistics_states()` 走
  `_entity_kinematics()`（physics 优先，本任务前已正确）；`probe` 的 world 手工事件仍可显式写
  world（不反向写 physics）。`SensorService` 的目标几何仍是静态配置（#4.1）。
- TrafficControlService 只做 OTC/航道/NPC/伪装线索：申请/许可/占用/释放由显式 API 驱动；
  `traffic.*` 只读事件进 bus；不写 world/TrackTable/UI/V15；不做物理/泊位/身份判定。
- CombatBallisticsService 只做弹道/导弹/PD/诱饵与 damage_event：states 由 session 每步只读提供；
  impact damage_event 只经白名单进 DamageService（shot_id 去重），事件只读进 bus；不写
  world/TrackTable/UI/V15；不执行身份判定。
- ShipCatalog/Refit/DamageProfile 只做目录/改装事务/毁伤档案查询：catalog 为静态内容，
  refit 为事务状态，DamageProfile 只在建档/查询时用；不接 UI 干船坞、不写 world/V15、
  不生成实体；旧 damage_l1 ships 显式档案属性优先，class_id 仅补元数据。
- FleetRefitService/FleetFormationService 只做舰队改装事务与编组状态：13 舰/8 槽来自名册
  提案，不写 world/TrackTable/UI/V15、不生成/移动实体；编队状态允许暂时 validate=false
  （例如移除 command），由 `fleet_validate()` 报告；不自动在主 tick 推进 fleet refit。
- **开火是异步的（4Z）**：`request_fire()` 返回 `ok=true` 仅表示弹丸已进入物理积分，不代表命中。
  上层/UI 不得据此宣布战果，必须等 `ballistics.impact` 事件或航迹 `damage_taken` 变化。
  门禁通过但物理状态缺失时一律 `no_physics_state` 拒绝（不降级成"抽象命中"），
  这是刻意的：宁可不发射，也不产生无物理来源的伤害。
- 弹道/导弹的**制导、引导头（radar_active/ir_passive/arm）、对抗（decoy/jammer）、
  打击后效（抗性/溢出/火灾/失压/断电/殉爆）**都在 `combat_ballistics` + `damage_model` 内部，
  session 只做编排与白名单路由；未做真实末端气动/大气层再入/破片场建模。
- 交战倍速上限 `COMBAT_SCALE_CAP=60.0` 是**游戏性**参数（让 900 s 导弹寿命在 15 实秒内可观察），
  不是物理常量；改它只影响观感，不影响弹道解算（解算始终在旋转系 RK4 里按仿真秒推进）。

- LegalStatusService 只做 ID13 法律状态与影响标志：heat/阈值迁移、去重、log；
  `impact()` 只读输出 port_access/iff_watch/roe_modifier/ending_hint，**不**改 world side、
  港口放行、战斗 ROE 或法律文本；CLEARED 锁定；不写 UI/V15。
- DamageService 只做多舰损管组合/事件/存档；combat 命中概率由 CombatService 决定，damage event
  经白名单应用；damage 不直接写 world/V15/UI。
- PortService/CombatService 只输出状态/事件；session 不自动许可/对接/服务/开火；FIRE 永不自动，
  需 confirmed + 授权；combat damage event `applied=false`，由上层损管决定应用。
- SensorService 只产生 observation/evidence（不直接写 TrackTable/world/UI）；routing 由 session
  显式白名单完成；传感器不判等级/身份，等级由 TrackTable 融合规则决定；IFF 不自动判敌。
- 传感器 target_id → TrackTable track 的内部分配在 session 记录（观测后映射）；无观测的目标
  evidence 会 `unknown_track` 拒绝（不伪造航迹）。
- bus 只按显式白名单路由，不自动把订单/通信事件写成剧情/航迹；world 变更仍必须 session 写者显式 apply。
- demo seed 为示例（3 实体/3 节点/2 链路），**不是关卡内容**。
- standalone `comms.delivered` 仅按 pending 消失对账；若在途链路失败，原因未从 comms 事件取回
  （订单路径的 comms 失败仍由 OrderService 处理并体现在 order.reason）。
- save/load 为内存 JSON（seed+log 重放 + 组件快照），不是完整序列化；log 随操作增长；
  组件快照 JSON 数值/整数按浮点往返（规范化比较）；无文件槽位（SaveService 负责）。
- **版本划分（4Z）**：session 本身**不知道**自己跑在哪个剖面下——`V2BuildProfile`
  在 UI 层（`shell_binder`/`main_menu`）决定 boot 哪些组件、用哪个 seed、存到哪个 `save_root`。
  因此 `full` 与 `combat_sim` 两个剖面共用同一份 session 代码，不存在分叉；
  详见 `docs/build_profiles.md`。
- 全量套件 66 探针已跑（9m26s）：6 个失败经 `git stash` 对照确认为**既有基线漂移**
  （`damage_integration_probe`/`incident_record_probe`/`save_probe`/`story_text_probe`/
  `v17_nav_integration_probe`/`v17_sensor_authority_display_probe`），本轮改动零回归。
- 未 commit。
