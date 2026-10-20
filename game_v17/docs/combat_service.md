# 完整游戏-阶段3G · 战斗系统核心（武器/ROE/授权/火控/损伤接口）

> 任务 task-140。工程 `game_v17`。**只新增 4 个文件**：
> `scripts/core/combat_service.gd`、`tests/combat_probe.gd`、
> `docs/combat_service.md`、`framework/content/weapons_l1.json`。
> 未改旧 world/UI/bridge/core/sim/project；不执行物理、不直接改实体；未 commit。

## 1　定位与数据流

```
weapons_l1.json（内容驱动：射程/弹药/冷却/解算/制导/伤害/授权）
        │
        ▼
V2CombatService
  tracks（来自 fusion/TrackTable 的只读目标行）
        │
        ├─ ROE 四档 + TRACK/SOLUTION/FIRE 授权（scope/duration）
        ├─ 火控：track → solution（时间/误差）→ FIRE → launch/prediction
        ├─ 武器：轨道炮/导弹（进攻）；点防御/干扰/诱饵（防御/对抗）
        ├─ 命中判定 → combat_damage_event.v1（不直接 applied）
        └─ 点防御 / incoming / 自动降级 / save/load
        │
        ▼
VM / events / JSON；上层物理/损管消费 damage event，UI 只读 VM
```

- **不执行物理**：预测接口只返回飞行时间/概率/误差/接口标记；不积分轨迹。
- **不直接改实体**：命中只产生 `combat_damage_event.v1`，`applied=false`；
  由上层 V2DamageModel/world 决定如何应用。
- **不写 world/TrackTable/V15/UI**；`writes` 恒 false。

## 2　内容 schema（`weapons_l1.json`）

```json
{
  "schema": "weapons.v1", "id": "weapons_l1",
  "weapons": [
    {"id":"railgun","kind":"kinetic","range_km":1200,"min_range_km":0,
     "ammo":120,"cooldown_s":6,"solution_s":4,"accuracy":0.82,
     "damage":0.35,"penetration":0.6,"speed_kmps":15,
     "guidance":"ballistic","auth_level":"FIRE","interceptable":false,
     "salvo":1,"suggested_sections":["hull","power"],"damage_kind":"kinetic"},
    {"id":"missile","kind":"guided","range_km":6000,"ammo":8,
     "cooldown_s":20,"solution_s":10,"accuracy":0.90,"damage":0.55,
     "penetration":0.8,"speed_kmps":8,"interceptable":true,...},
    {"id":"pd","kind":"point_defense","range_km":180,"ammo":80,
     "cooldown_s":2,"solution_s":0.5,"intercept_accuracy":0.65,...},
    {"id":"jammer","kind":"ew","range_km":5000,"ammo":6,
     "cooldown_s":30,"duration_s":30,"effect":"radar_jam",...},
    {"id":"decoy","kind":"decoy","ammo":12,"cooldown_s":15,
     "duration_s":20,"effect":"decoy",...}
  ],
  "roe": {
    "schema":"roe.v1",
    "levels":[
      {"id":"DEFEND","track":"auto_passive","solution":"auto_direct_threat","fire":"confirm"},
      {"id":"HOLD","track":"auto_passive","solution":"confirm","fire":"confirm"},
      {"id":"TIGHT","track":"auto_suspect","solution":"auto_hostile","fire":"confirm_once"},
      {"id":"FREE","track":"auto_hostile","solution":"auto_hostile","fire":"manual_confirm"}
    ],
    "authorization_levels":["TRACK","SOLUTION","FIRE"],
    "scopes":["target","weapon_group","ship","fleet"]
  }
}
```

校验：schema/weapons 非空/唯一 id/kind 合法/必需数值有限/ammo≥0/cooldown≥0/
进攻武器 damage>0/auth_level 合法/ROE 四档齐全。加载失败 `ready=false` 并报错。

## 3　API

```gdscript
const Combat := preload("res://scripts/core/combat_service.gd")
var c = Combat.new({
  "content_path": "res://framework/content/weapons_l1.json",
  "roe": "TIGHT", "own_id": "harmattan", "fleet_id": "taskforce"
})

c.register_track(id, {identity, threat, range_km, in_arc, destroyed, ship_id})
c.update_track(id, {...}) / c.track(id)
c.set_roe("DEFEND"|"HOLD"|"TIGHT"|"FREE") -> {ok,roe,from,changed}
c.roe_label()

c.request_track(target_id, confirmed=false) -> {ok,auto,reason,...}
c.request_solution(target_id, weapon_id, confirmed=false) -> {ok,solution|reason}
c.solution_status(solution_id)
c.request_fire(target_id, weapon_id, confirmed=false) -> {ok,hit,damage_event,prediction,...}
c.predict_shot(target_id, weapon_id) -> 预测接口（no_physics/trajectory=interface_only）

c.grant_authorization(level, scope_type, scope_id, duration_s=0, until_destroyed=false)
c.revoke_authorization(grant_id="") / c.check_authorization(level,target,weapon)
c.weapons_status() / c.track_rows() / c.grant_rows() / c.solution_rows()

c.incoming_missile(threat_id,target_id,damage,opts)   # 点防御输入
c.launch_decoy() / c.activate_jammer(target_id)
c.tick(dt) -> {ok,t,roe,events,counts}
c.set_sensor_damage(v) / c.set_link_lost(b) / c.notify_downgrade(reason)

c.vm() / c.summary() / c.to_dict() / c.to_json()
c.events / c.events_since(seq) / c.take_events()
c.save_state() / c.snapshot() / c.load_state(json_or_dict)
```

### 3.1 ROE 四档行为

| 档位 | TRACK | SOLUTION | FIRE | 点防御 |
| --- | --- | --- | --- | --- |
| DEFEND | 被动/全部自动 | 仅直接威胁自动；其余需确认/授权 | 需确认 + FIRE 授权 | 自动 |
| HOLD | 自动 | 需确认/授权 | 需确认 + FIRE 授权 | 自动 |
| TIGHT | 疑似/敌对所有自动 | 敌对自动；其他需确认/授权 | 需确认 + FIRE 授权 | 自动 |
| FREE | 敌对自动；其他需确认/授权 | 敌对自动；其他需确认/授权 | 需确认 + FIRE 授权 | 自动 |

- **FIRE 永不自动**；未知/中立/友方目标不允许自动开火，必须人工 `confirmed=true` 且
  有匹配 FIRE 授权；
- `request_fire` 前置：已确认、FIRE 授权、READY solution、射程内、弹药/冷却；
- `request_solution` 可显式 `confirmed=true`（人工确认）或使用 SOLUTION 授权；
- `TRACK` 授权不隐含 SOLUTION/FIRE，等级隔离。

### 3.2 三级授权 / 范围 / 时限

- Levels：`TRACK/SOLUTION/FIRE`（FIRE 需同时 `confirmed=true`）。
- Scopes：
  - `target`：匹配 target/track id（`*` 通配）；
  - `weapon_group`：匹配 weapon id（`*`）；
  - `ship`：匹配本舰 `own_id`；
  - `fleet`：匹配 `fleet_id`。
- `duration_s>0`：tick 到期自动移除并 emit `authorization_expired`；
- `until_destroyed=true`：目标 `destroyed` 后失效；
- `revoke_authorization(grant_id="")` 撤销单个/全部。

## 4　火控状态机

```text
track（register/update）
  → request_solution：校验 ROE/授权/目标/射程 → COMPUTING（ready_t=t+solution_s）
  → tick：READY（quality/error_km）或 FAILED（target_unavailable/out_of_range）
  → request_fire：confirmed + FIRE 授权 + READY + 射程/弹药/冷却
  → launch（weapon_launch）→ 命中 roll → combat_hit / combat_miss
  → 命中：combat_damage_event.v1（applied=false，不直接改实体）
```

- `solution.quality = accuracy × range 因子`；`error_km = range×(1-quality)×0.01`；
- `predict_shot()` 返回 `{no_physics:true, trajectory:"interface_only",
  time_of_flight_s, hit_probability, error_km, guidance, interceptable}`；
- 命中判定是**确定性** roll（hash target/weapon/shot seq），非物理模拟；
- 发射消耗 ammo；cooldown 由 tick/t 推进；无弹药/冷却返回 `no_ammo/cooldown`；
- 目标 damage_taken 仅在服务内部用于“直到摧毁”授权/VM，不等于改实体；
  实际应用 damage 由上层损管。

### 4.1 Damage event

```json
{"schema":"combat_damage_event.v1","kind":"damage","t":12.0,
 "shot_id":"SHOT-000001","target_id":"T0001","source_id":"harmattan",
 "weapon_id":"missile","damage":0.55,"penetration":0.8,
 "damage_kind":"explosive","suggested_section":"hull",
 "source":"combat_service","applied":false,"writes_v15":false}
```

## 5　点防御 / 诱饵 / 干扰 / incoming

- `incoming_missile()` 注册来袭；`tick` 自动点防御（PD 自动，所有 ROE）：
  消耗 PD 弹药/冷却，按 `intercept_accuracy` 确定性判定；
  成功 `combat_intercept`，失败 `incoming_impact` + damage event（不 applied）。
- `launch_decoy()`：消耗诱饵、设置 active window；降低敌方命中/提高 PD 机会；
- `activate_jammer()`：消耗干扰机、设置窗口；影响来袭拦截概率；
- 不可拦截 incoming（`interceptable=false`）直接命中；
- 所有入口检查 ammo/cooldown；无对应武器返回 `no_decoy/no_jammer`。

## 6　自动降级

`_maybe_downgrade(reason)` 只会下降、不会升级；触发：
- 目标身份变 friend/assumed_friend/neutral 且 `in_arc=true` → HOLD；
- `sensor_damage>=0.5` / `link_lost=true` → HOLD；
- 进攻武器弹药全空（tick 检查）→ HOLD；
- 事件 `roe_downgrade {from,to,reason}`；`notify_downgrade()` 可手动触发。

## 7　VM / events / save

```text
VM schema=combat_service.v1, mode=combat_core, ready, t, roe, roe_label,
own_id, fleet_id, weapons[], tracks[], solutions[], grants[], incoming[],
decoy_until, jammer_until, events[], counts{...}, warnings, errors,
writes={world:false,track_table:false,v15:false,ui:false}
```

- events schema `combat_event.v1`：`{seq,t,kind,payload,shadow,writes_v15:false}`；
  `weapon_launch/combat_hit/combat_miss/point_defense/combat_intercept/incoming_impact/
  solution_*/authorization_*/roe_*/track_registered` 等；
- `save_state()` JSON schema `v17.combat_service_save.v1` version `1.0.0`：
  weapons（ammo/cooldown）、tracks、solutions、grants、incoming、events、roe、
  t/seq/decoy/jammer/sensor/link；`load_state` 校验 schema/version/weapons 后恢复；
- 确定性：相同输入/命令序列 VM/events 逐字节一致（probe 已断言）。

## 8　接入物理 / UI / 边界

- **输入**：上层 fusion/TrackTable/传感器提供 target 行（id/identity/threat/range/
  in_arc/ship_id）；本服务只读，不写回 TrackTable。
- **输出**：damage events 由上层 V2DamageModel/实体应用；本服务不调用 `apply_hit`，
  不修改 `world`/实体；`applied=false`。
- **UI**：只读 `vm()`/events（ROE/授权/解算/弹药/冷却/降级原因）；不直接触发写，
  发射/授权必须走服务 API 并记录事件。
- 不执行物理轨迹/碰撞；预测是接口数据；不做传感器跟踪/融合/身份判定。
- 不实现完整命令通信/延迟/撤销/事件文本库；不实现存档文件 I/O（仅 JSON）。
- ROE 矩阵为可测试的显式规则，未覆盖完整交战几何/射界遮挡/多目标饱和；
  自动降级只做保守 HOLD，不自动升级。
- 点防御/干扰/诱饵为抽象概率接口，不含真实弹道/电子战模型；
  incoming 命中后 damage event 只给上层，不直接扣血。
- probe 209 checks（内容/四档/三级授权/scope/时限/解算/发射/弹药/冷却/命中/
  PD/诱饵/干扰/incoming/降级/save/JSON/确定性）；只单次运行，未跑全量回归。
- 未 commit；未改其他文件。

## 9　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/combat_probe.gd
# COMBAT PROBE RESULT: PASS=209 FAIL=0
# COMBAT PROBE OK（退出码 0）
```
